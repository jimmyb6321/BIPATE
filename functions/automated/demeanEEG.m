function EEG = demeanEEG(EEG, cfg_full)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Removes each channel's mean. Continuous data: the mean over the good samples (EEG.masks.seg) is taken off
% the whole channel. Epoched data: each epoch's own mean, or the mean of a baseline window when
% cfg_full.demean.baseline is set (e.g. [-200 0] ms).

% IN:   EEG = EEGLAB struct
%       cfg_full = configuration struct (sessionID, paths.data_out; optional demean.baseline = [start end] in
%           ms, epoched data only)

% OUT:  EEG = demeaned EEG struct, saved as <sessionID>_demeaned (numbered on repeats)
%           EEG.etc.demean = what was removed ('good-sample mean', 'epoch mean' or 'baseline [a b] ms')

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end
checkPrerequisites(EEG, 'demean');   % what must run first is listed in jobs.json

EEG = mask_init(EEG);
baseline = [];
if isfield(cfg_full, 'demean') && isfield(cfg_full.demean, 'baseline')
    baseline = cfg_full.demean.baseline;
end

if EEG.trials == 1
    [~, goodSamp] = mask_good(EEG);
    if ~any(goodSamp), goodSamp(:) = true; end
    channelMean = mean(double(EEG.data(:, goodSamp)), 2);
    EEG.data = EEG.data - cast(channelMean, 'like', EEG.data);
    how = 'good-sample mean';
elseif isempty(baseline)
    EEG.data = EEG.data - mean(EEG.data, 2);
    how = 'epoch mean';
else
    inBase = EEG.times >= baseline(1) & EEG.times <= baseline(2);
    if ~any(inBase)
        error('Demean baseline [%g %g] ms is outside the epoch (%g to %g ms).', baseline, EEG.times([1 end]));
    end
    EEG.data = EEG.data - mean(EEG.data(:, inBase, :), 2);
    how = sprintf('baseline [%g %g] ms', baseline);
end
EEG.etc.demean = how;

[tag, roundSuffix] = stepRound(EEG, 'demean');
EEG.etc.processing_log{end+1} = sprintf('Demeaned (%s) at %s', how, string(datetime('now')));
EEG.etc.processing_done{end+1} = tag;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
EEG.setname = [char(cfg_full.sessionID) '_demeaned' roundSuffix];
EEG = saveStep(EEG, 'filename', [EEG.setname '.set'], 'filepath', char(savePath), ...
    'savemode', 'onefile', 'version', '7.3');
notifyDone('Demean')
end
