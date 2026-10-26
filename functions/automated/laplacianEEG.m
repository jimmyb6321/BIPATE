function EEG = laplacianEEG(EEG, cfg_full)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Surface Laplacian (current source density) by spherical splines (Perrin et al., 1989; same maths as the CSD
% toolbox of Kayser & Tenke). Pipeline:
%   1. electrode positions (X, Y, Z) projected onto a unit sphere; only the good channels with positions are
%      used as spline sources
%   2. cosine of the angle between every pair of electrodes
%   3. G = spline interpolation matrix, H = its surface Laplacian, both as Legendre series:
%      G(x) = 1/(4 pi) sum_n (2n+1) / (n(n+1))^m     P_n(x)
%      H(x) = 1/(4 pi) sum_n (2n+1) / (n(n+1))^(m-1) P_n(x)
%   4. spline weights from (G + lambda I) with the constant term removed, per sample
%   5. CSD at every electrode with a position = H * weights / headRadius^2  (microvolt / cm^2)
% Channels marked bad get a spline estimate too (they were not used as sources). Any ICA decomposition no
% longer matches the data, so it is cleared.

% IN:   EEG = EEGLAB struct with chanlocs X, Y, Z
%       cfg_full = configuration struct (sessionID, paths.data_out; optional laplacian.m (default 4),
%           laplacian.lambda (default 1e-5), laplacian.nTerms (default 50), laplacian.headRadius in cm
%           (default 10))

% OUT:  EEG = EEG struct holding the CSD (channels without a position unchanged), saved to
%           laplacian as <sessionID>_laplacian (numbered on repeats)
%           EEG.etc.laplacian = settings used and which channels were sources / transformed

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end
checkPrerequisites(EEG, 'laplacian');   % what must run first is listed in jobs.json

opts = struct('m', 4, 'lambda', 1e-5, 'nTerms', 50, 'headRadius', 10);
if isfield(cfg_full, 'laplacian')
    for name = fieldnames(cfg_full.laplacian)'
        opts.(name{1}) = cfg_full.laplacian.(name{1});
    end
end

EEG = mask_init(EEG);
[goodChan, ~] = mask_good(EEG);
hasPos = arrayfun(@(c) ~isempty(c.X) && ~isempty(c.Y) && ~isempty(c.Z), EEG.chanlocs(:));
target = find(hasPos);                 % channels that get a CSD value
source = find(hasPos & goodChan(:));   % channels the splines are fitted to
if numel(source) < 10
    error('Surface Laplacian needs at least 10 good channels with positions (%d found).', numel(source));
end

% 1-2. unit-sphere positions and cosines between electrodes
pos = [[EEG.chanlocs(target).X]', [EEG.chanlocs(target).Y]', [EEG.chanlocs(target).Z]'];
pos = pos ./ vecnorm(pos, 2, 2);
cosAll = min(max(pos * pos', -1), 1);              % [nTarget x nTarget]
[~, srcInTarget] = ismember(source, target);

% 3. G (sources x sources) and H (targets x sources)
G = legendreSeries(cosAll(srcInTarget, srcInTarget), opts.m, opts.nTerms);
H = legendreSeries(cosAll(:, srcInTarget), opts.m - 1, opts.nTerms);

% 4-5. weights per sample, then CSD; done in chunks of samples to keep memory down
Gs = G + opts.lambda * eye(numel(source));
GsInv = inv(Gs);   % its column sums are needed too, so the inverse is formed once
colSum = sum(GsInv, 1);                % [1 x nSource]
total = sum(colSum);
data2D = reshape(EEG.data, EEG.nbchan, []);
csd = zeros(numel(target), size(data2D, 2), 'like', data2D);
chunk = 50000;
for first = 1:chunk:size(data2D, 2)
    cols = first:min(first + chunk - 1, size(data2D, 2));
    V = double(data2D(source, cols));
    C = GsInv * V; %#ok<MINV> (GsInv is reused for every chunk)
    C = C - colSum' * (sum(C, 1) / total);  % remove the constant term
    csd(:, cols) = H * C / opts.headRadius^2;
end
data2D(target, :) = csd;
EEG.data = reshape(data2D, size(EEG.data));

% ICA no longer matches the transformed data
if ~isempty(EEG.icaweights)
    warning('Surface Laplacian: the existing ICA decomposition no longer fits the data and was cleared.');
    EEG.icaweights = []; EEG.icasphere = []; EEG.icawinv = []; EEG.icachansind = []; EEG.icaact = [];
end
EEG.ref = 'laplacian (CSD)';
EEG.etc.laplacian = opts;
EEG.etc.laplacian.units = 'microvolt/cm^2';
EEG.etc.laplacian.sourceChannels = {EEG.chanlocs(source).labels};
EEG.etc.laplacian.transformedChannels = {EEG.chanlocs(target).labels};

[tag, roundSuffix] = stepRound(EEG, 'laplacian');
EEG.etc.processing_log{end+1} = sprintf('Surface Laplacian (m = %d, lambda = %g) at %s', opts.m, opts.lambda, ...
    string(datetime('now')));
EEG.etc.processing_done{end+1} = tag;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
EEG.setname = [char(cfg_full.sessionID) '_laplacian' roundSuffix];
EEG = saveStep(EEG, 'filename', [EEG.setname '.set'], 'filepath', char(savePath), ...
    'savemode', 'onefile', 'version', '7.3');
notifyDone('Surface Laplacian')
end

% Legendre series 1/(4 pi) * sum_{n=1}^{nTerms} (2n+1) / (n(n+1))^m * P_n(x), element by element over x
function out = legendreSeries(x, m, nTerms)
out = zeros(size(x));
pPrev = ones(size(x));   % P_0
pNow = x;                % P_1
for n = 1:nTerms
    out = out + (2*n + 1) / (n * (n + 1))^m * pNow;
    pNext = ((2*n + 1) * x .* pNow - n * pPrev) / (n + 1);   % Bonnet recursion
    pPrev = pNow;
    pNow = pNext;
end
out = out / (4 * pi);
end
