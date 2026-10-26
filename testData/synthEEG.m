% synthEEG  Generate a physiologically-shaped synthetic EEG recording
%
% Author: James Barlow
% Created: 08/28/2026
% Last updated: 10/25/2026
%
% Builds a continuous recording whose spatial and spectral structure is close
% enough to a real scalp recording to exercise every artifact stage of
% BIPATE. The important departure from the old demo generator is
% that the background is built in SOURCE space -- dipoles inside a unit
% sphere, projected to the sensors through a forward model, then referenced
% to a single electrode the way the amplifier does it. That gives genuinely
% correlated neighbours; independent per-channel noise makes topoplots,
% mean-neighbour-correlation and ICA all meaningless, which is why the old
% demo could not exercise mhc, bridge or ICLabel.
%
% Calibrated against a real 258-channel GSN HydroCel-257 recording
% (258 ch, 500 Hz, ref E257). Target statistics, measured on a 2-min slice of
% that file after a 0.5 Hz highpass and median re-reference:
%
%       median channel SD          20.6 uV     (raw, with drift: 131 uV)
%       common mode SD             16.5 uV
%       mhc  median / MAD          0.867 / 0.107
%       log10 var median / MAD     2.627 / 0.473
%       log10 kurtosis median      0.620
%
% What is generated
%   background   1/f-shaped source spectra plus band-limited oscillatory
%                bursts: posterior alpha, frontal-midline theta, central
%                beta, widespread delta.
%   physiology   blink, saccade, cardiac and muscle added as low-rank spatial
%                patterns, so ICA/ICLabel have real components to recover.
%   drift        slow electrode drift, removed by the pipeline highpass, so
%                the raw file has a realistic pre-filter amplitude.
%   bad channels one plant per badChanDetect feature (see EEG.etc.demo).
%   bad segments broadband movement, chewing and electrode-pop windows for
%                manual segmentRejection.
%
% Ground truth for everything planted is written to EEG.etc.demo.
%
% USAGE
%   EEG = synthEEG(chanlocs)
%   EEG = synthEEG(chanlocs, 'srate',500, 'dur',180, 'refIdx',257, ...
%                            'pnsIdx',258, 'ecgIdx',258, 'keepIdx',inside185ch)
%
% NAME-VALUE
%   srate      sampling rate, Hz                              (default 500)
%   dur        duration, seconds                              (default 180)
%   seed       rng seed                                       (default 7)
%   amp        target median channel SD after highpass, uV    (default 12.5)
%   driftAmp   slow drift amplitude, uV (removed by pipeline) (default 112)
%   nSources   number of background dipoles                   (default 30)
%   lineFreq   mains frequency, Hz                            (default 60)
%   refIdx     recording reference channel, zeroed after ref  (default [])
%   pnsIdx     indices of non-scalp channels (ECG, EOG...)    (default [])
%   ecgIdx     index of the ECG channel                       (default [])
%   keepIdx    channels eligible for bad-channel plants       (default all scalp)
%   artifacts  add blink/saccade/cardiac/muscle/line          (default true)
%   plantBad   plant bad channels                             (default true)
%   plantSegs  plant bad segments                             (default true)
%
function EEG = synthEEG(chanlocs, opts)
arguments
    chanlocs  (1,:) struct
    opts.srate     (1,1) double  = 500
    opts.dur       (1,1) double  = 180
    opts.seed      (1,1) double  = 7
    opts.amp       (1,1) double  = 12.5
    opts.driftAmp  (1,1) double  = 112
    opts.nSources  (1,1) double  = 30
    opts.lineFreq  (1,1) double  = 60
    opts.refIdx    (1,:) double  = []
    opts.pnsIdx    (1,:) double  = []
    opts.ecgIdx    (1,:) double  = []
    opts.keepIdx   (1,:) double  = []
    opts.artifacts (1,1) logical = true
    opts.plantBad  (1,1) logical = true
    opts.plantSegs (1,1) logical = true
end

rng(opts.seed);
a  = opts.amp / 20;   % all artifact amplitudes scale with the background
fs = opts.srate;
n  = round(fs * opts.dur);
t  = (0:n-1) / fs;
nb = numel(chanlocs);

demo = struct();
demo.srate = fs; demo.dur = opts.dur; demo.seed = opts.seed;

%% ------------------------------------------------------------------ geometry
xyz = nan(nb, 3);
fnm = {'X','Y','Z'};
for c = 1:nb
    for j = 1:3
        if isfield(chanlocs, fnm{j}) && ~isempty(chanlocs(c).(fnm{j}))
            xyz(c,j) = chanlocs(c).(fnm{j});
        end
    end
end

scalp = setdiff(1:nb, opts.pnsIdx);
good  = all(isfinite(xyz(scalp,:)), 2) & vecnorm(xyz(scalp,:), 2, 2) > 0;
scalp = scalp(good);
if isempty(scalp)
    error('synthEEG:noLocs', 'No channels with usable X/Y/Z coordinates.');
end
S  = xyz(scalp,:) ./ vecnorm(xyz(scalp,:), 2, 2);   % unit sphere
ns = numel(scalp);

%% ------------------------------------------------------- background sources
% Deep-ish sources and a generous distance floor keep the field spatially
% smooth. Shallow sources give mhc far below what real hdEEG shows.
nS   = opts.nSources;
pDir = randn(nS,3); pDir = pDir ./ vecnorm(pDir,2,2);
P    = pDir .* (0.30 + 0.35*rand(nS,1));
D    = randn(nS,3); D = D ./ vecnorm(D,2,2);
D    = 0.6*pDir + 0.4*D; D = D ./ vecnorm(D,2,2);   % mostly radial moments

G = zeros(ns, nS);
for k = 1:nS
    G(:,k) = dipoleGain(S, P(k,:), D(k,:));
end
G = G - mean(G,1);
G = G ./ vecnorm(G,2,1);

Ssig = zeros(nS, n);
for k = 1:nS
    Ssig(k,:) = pinkNoise(n, fs, 0.7);
    Ssig(k,:) = Ssig(k,:) + 0.80*burstOsc(n, fs, [1 3.5],  8.0);          % delta
    if P(k,1) < -0.15                                                     % posterior
        Ssig(k,:) = Ssig(k,:) + 2.20*burstOsc(n, fs, [8 12], 3.0);        % alpha
    end
    if P(k,1) > 0.20 && abs(P(k,2)) < 0.35                                % frontal midline
        Ssig(k,:) = Ssig(k,:) + 1.00*burstOsc(n, fs, [4 7],  4.0);        % theta
    end
    if abs(P(k,1)) < 0.25 && P(k,3) > 0.25                                % central
        Ssig(k,:) = Ssig(k,:) + 0.55*burstOsc(n, fs, [13 25], 2.0);       % beta
    end
end

X = G * Ssig;
X = X ./ median(std(X, 0, 2)) * opts.amp;

data = zeros(nb, n);
data(scalp,:) = X;

%% ------------------------------------------------------------- physiological
wEMG = emgWeights(S);
if opts.artifacts
    % --- eye blinks: frontal-inferior dipole, upward moment ---------------
    wBlink = unitTopo(dipoleGain(S, [0.80 0 -0.55], [0.30 0 1]));
    blink  = zeros(1,n);
    bt = cumsum(2.5 + 3.5*rand(1, ceil(opts.dur/2.0)));
    bt = bt(bt < opts.dur - 1);
    w  = round(0.30*fs);
    g  = exp(-(((1:w) - w/2).^2) / (2*(w/5)^2));
    for bi = round(bt*fs)
        b0 = max(bi, 1);
        if b0 + w - 1 <= n, blink(b0:b0+w-1) = blink(b0:b0+w-1) + g; end
    end
    data(scalp,:) = data(scalp,:) + (a*110*wBlink) * blink;

    % --- saccades: lateral gradient, step-like ----------------------------
    wSacc = unitTopo(dipoleGain(S, [0.75 0 -0.50], [0 1 0]));
    sacc  = zeros(1,n);
    st = cumsum(1.5 + 3.0*rand(1, ceil(opts.dur/1.5)));
    st = st(st < opts.dur - 1);
    for s0 = round(st*fs)
        sacc(s0 : min(n, s0 + round((0.25 + 0.45*rand)*fs))) = sign(randn);
    end
    kk   = round(0.02*fs);
    sacc = filtfilt(ones(1,kk)/kk, 1, sacc);
    data(scalp,:) = data(scalp,:) + (a*40*wSacc) * sacc;

    % --- cardiac ----------------------------------------------------------
    ecgT = ecgTemplate(fs);
    ecg  = zeros(1,n);
    rt   = cumsum(0.85 + 0.06*randn(1, ceil(opts.dur/0.7)));
    rt   = rt(rt > 0.5 & rt < opts.dur - 0.6);
    half = floor(numel(ecgT)/2);
    for r0 = round(rt*fs)
        i0 = r0 - half; i1 = i0 + numel(ecgT) - 1;
        if i0 >= 1 && i1 <= n, ecg(i0:i1) = ecg(i0:i1) + ecgT; end
    end
    wECG = unitTopo(dipoleGain(S, [-0.20 0.90 -1.40], [0.3 -0.8 0.5]));
    data(scalp,:) = data(scalp,:) + (a*7*wECG) * ecg;
    if ~isempty(opts.ecgIdx)
        data(opts.ecgIdx,:) = a*90*ecg + a*3*randn(numel(opts.ecgIdx), n);
    end
    demo.heartRateBPM = 60 / mean(diff(rt));

    % --- tonic muscle: lateral-inferior ring ------------------------------
    emg  = bandNoise(n, fs, [20 min(100, fs/2 - 5)]);
    gate = 0.3 + 0.7*envGate(n, fs, 2.5);
    data(scalp,:) = data(scalp,:) + (a*12*wEMG) * (emg .* gate);

    % --- mains: a common component plus per-channel scatter, so that some
    %     line noise survives referencing and the notch actually has work.
    lf   = opts.lineFreq;
    data(scalp,:) = data(scalp,:) + a*3.0*sin(2*pi*lf*t);
    lamp = a*1.5 * (0.6 + 0.8*rand(nb,1));
    data = data + lamp .* sin(2*pi*lf*t + 2*pi*rand(nb,1));
    if 2*lf < fs/2
        data = data + 0.4*lamp .* sin(2*pi*2*lf*t + 2*pi*rand(nb,1));
    end
end

%% ------------------------------------------------- per-electrode variation
% Electrode gain and impedance differ channel to channel; a pure forward
% model gives a much tighter amplitude spread than any real recording.
gainVar = exp(0.25*randn(nb,1));
data(scalp,:) = data(scalp,:) .* gainVar(scalp);
data(scalp,:) = data(scalp,:) + (0.12*opts.amp*exp(0.6*randn(ns,1))) .* randn(ns, n);

%% ---------------------------------------------------------- slow drift
% Spatially smooth low-frequency drift. Sets the raw amplitude scale; the
% pipeline highpass removes it.
if opts.driftAmp > 0
    nD = 8;
    Gd = zeros(ns, nD);
    for k = 1:nD
        pd = randn(1,3); pd = pd/norm(pd)*(0.3+0.4*rand);
        Gd(:,k) = unitTopo(dipoleGain(S, pd, pd));
    end
    Sd = zeros(nD, n);
    for k = 1:nD, Sd(k,:) = bandNoise(n, fs, [0.01 0.15]); end
    Xd = Gd * Sd;
    data(scalp,:) = data(scalp,:) + opts.driftAmp * Xd ./ median(std(Xd,0,2));
end

%% -------------------------------------------------------------- bad segments
segs = struct('kind',{},'t0',{},'t1',{});
if opts.plantSegs
    D0  = opts.dur;
    win = @(a,b) round(max(1, a*D0*fs)) : round(min(n, b*D0*fs));

    for fr = [0.14 0.18; 0.52 0.565; 0.80 0.835]'
        idx = win(fr(1), fr(2));
        m   = 1:numel(idx);
        bs  = ones(1, round(0.15*fs)) / round(0.15*fs);
        slow = filtfilt(bs, 1, randn(numel(idx), ns))';
        slow = slow ./ max(abs(slow), [], 2);
        data(scalp,idx) = data(scalp,idx) + a*180 * slow ...
                        + a*40 * randn(ns, numel(idx)) .* (1 + 0.5*sin(2*pi*1.5*m/fs));
        segs(end+1) = struct('kind','movement','t0',idx(1)/fs,'t1',idx(end)/fs); %#ok<AGROW>
    end

    for fr = [0.30 0.335; 0.66 0.69]'
        idx = win(fr(1), fr(2));
        ch  = bandNoise(numel(idx), fs, [20 min(90, fs/2-5)]);
        ch  = ch .* (0.5 + 0.5*abs(sin(2*pi*2.0*(0:numel(idx)-1)/fs)));
        data(scalp,idx) = data(scalp,idx) + (a*90*wEMG) * ch;
        segs(end+1) = struct('kind','chewing','t0',idx(1)/fs,'t1',idx(end)/fs); %#ok<AGROW>
    end

    idx = win(0.42, 0.428);
    hit = scalp(randperm(ns, round(0.35*ns)));
    data(hit, idx) = data(hit, idx) + a*250 * sign(randn(numel(hit),1)) .* ...
                     repmat(linspace(1, 0.2, numel(idx)), numel(hit), 1);
    segs(end+1) = struct('kind','pop','t0',idx(1)/fs,'t1',idx(end)/fs);
end
demo.badSegments = segs;

%% --------------------------------------------------------------- bad channels
bad = struct('idx',{},'label',{},'kind',{},'expect',{});
if opts.plantBad
    elig = opts.keepIdx;
    if isempty(elig), elig = scalp; end
    elig = intersect(elig(:)', scalp, 'stable');
    if numel(elig) < 14
        error('synthEEG:tooFewEligible', ...
              'Need >= 14 eligible channels to plant bad channels, have %d.', numel(elig));
    end

    % The bridged pair must be true spatial neighbours or the bridge test in
    % badChanDetect (10 nearest neighbours) will never see them.
    [~, loc] = ismember(elig, scalp);
    Dm = squareform(pdist(S(loc,:)));
    Dm(1:size(Dm,1)+1:end) = inf;
    [~, flat] = min(Dm(:));
    [ba, bb]  = ind2sub(size(Dm), flat);
    pair = [elig(ba) elig(bb)];

    rest = setdiff(elig, pair, 'stable');
    pick = rest(round(linspace(1, numel(rest), 10)));

    add = @(i,k,e) struct('idx',i,'label',chanlocs(i).labels,'kind',k,'expect',e);

    % 1 dead electrode. NOTE: badChanDetect computes its features on
    %   EEG.data - median(EEG.data,1), which hands a dead channel the negated
    %   common mode. See EEG.etc.demo.knownMisses.
    i1 = pick(1);  data(i1,:) = a*0.05*randn(1,n);
    bad(end+1) = add(i1,'dead','variance low / flat / mhc');

    % 2 intermittent dropout (middle third of the recording)
    i2 = pick(2);  dz = round(0.33*n):round(0.66*n);
    data(i2,dz) = a*0.05*randn(1,numel(dz));
    bad(end+1) = add(i2,'intermittentFlat','flat fraction');

    % 3 popping electrode -> kurtosis high. Modelled as step-and-decay
    %   transients rather than impulses; a bare impulse is smeared into a
    %   long ringing by the highpass and stops looking leptokurtic.
    i3 = pick(3);
    tau = round(0.08*fs); dk = exp(-(0:4*tau-1)/tau);
    for p0 = sort(randperm(n - numel(dk), 60))
        pr = p0 : p0 + numel(dk) - 1;
        data(i3, pr) = data(i3, pr) + a*900*sign(randn)*dk;
    end
    bad(end+1) = add(i3,'spiky','kurtosis high');

    % 4 railed amplifier -> kurtosis low. Clipping a drifting signal only
    %   works pre-highpass; after the 0.5 Hz filter a slow square wave turns
    %   into a train of edges and reads as HIGH kurtosis. Squaring a 1-20 Hz
    %   band keeps it square in the passband, which is what a railed channel
    %   actually looks like once it is filtered.
    i4 = pick(4);  data(i4,:) = a*120*sign(bandNoise(n, fs, [1 20]));
    bad(end+1) = add(i4,'clipped','kurtosis low');

    % 5 floating electrode -> uncorrelated with neighbours, variance normal
    i5 = pick(5);  data(i5,:) = opts.amp * pinkNoise(n, fs, 0.7);
    bad(end+1) = add(i5,'floating','mhc low');

    % 6 railed / saturated -> variance high
    i6 = pick(6);  data(i6,:) = data(i6,:) * 8;
    bad(end+1) = add(i6,'railed','variance high');

    % 7 broadband HF noise -> psdHF high (survives the notch)
    i7 = pick(7);  data(i7,:) = data(i7,:) + a*70*bandNoise(n, fs, [40 min(100, fs/2-5)]);
    bad(end+1) = add(i7,'hfNoisy','variance / psdDev  (psdHF cannot fire -- see knownMisses)');

    % 8 sweat / drift -> psdLF high. Sits at 0.5-1.2 Hz so it survives the
    %   0.5 Hz highpass; amplitude kept moderate so variance stays in range
    %   and psdLF is the discriminating feature.
    i8 = pick(8);
    data(i8,:) = 0.4*data(i8,:) + a*160*bandNoise(n, fs, [0.5 1.2]);
    bad(end+1) = add(i8,'drift','variance  (psdLF cannot fire -- see knownMisses)');

    % 9 narrowband oscillator -> psdDev high (spectral shape unlike the rest)
    i9 = pick(9);  data(i9,:) = a*25*bandNoise(n, fs, [22 24]);
    bad(end+1) = add(i9,'oddSpectrum','psdDev high');

    % 10 line-dominated -> obvious in the pre-notch QC PSD
    i10 = pick(10); data(i10,:) = data(i10,:) + a*60*sin(2*pi*opts.lineFreq*t + 2*pi*rand);
    bad(end+1) = add(i10,'lineDominated','pre-notch QC PSD only -- removed by the notch');

    % 11/12 bridged pair -> perfect-correlation test
    data(pair(2),:) = data(pair(1),:) + a*0.15*randn(1,n);
    bad(end+1) = add(pair(1),'bridgeA','bridge');
    bad(end+1) = add(pair(2),'bridgeB','bridge');
end
demo.badChannels = bad;

%% ------------------------------------------------------------- reference
% Applied last, the way the amplifier does it: every scalp channel carries
% minus the reference electrode, and the reference itself reads flat.
if ~isempty(opts.refIdx)
    data(scalp,:) = data(scalp,:) - data(opts.refIdx,:);
    data(opts.refIdx,:) = 0;
    demo.refChannel = chanlocs(opts.refIdx).labels;
end

demo.scalpIdx = scalp;
demo.pnsIdx   = opts.pnsIdx;
demo.knownMisses = ['badChanDetect computes its features on ' ...
    'EEG.data - median(EEG.data,1). A dead or dropped-out electrode therefore ' ...
    'carries the negated common mode rather than nothing, so its variance is ' ...
    'normal, its flat fraction is zero, and it correlates strongly with its ' ...
    'neighbours. The dead and intermittentFlat plants are expected to be ' ...
    'missed until the amplitude features are computed on EEG.data directly.'];

%% ---------------------------------------------------------------- assemble
EEG = eeg_emptyset();
EEG.srate    = fs;
EEG.nbchan   = nb;
EEG.pnts     = n;
EEG.trials   = 1;
EEG.xmin     = 0;
EEG.xmax     = (n-1)/fs;
EEG.times    = t*1000;
EEG.data     = single(data);
EEG.chanlocs = chanlocs;
EEG.etc.demo = demo;
EEG = eeg_checkset(EEG);
end

% ======================================================================= local

function w = dipoleGain(S, p, d)
% Potential at unit-sphere sensors S from a current dipole at p with moment d.
% The 0.30 floor on the source-sensor distance keeps the field smooth.
R = S - p(:)';
w = (R * d(:)) ./ max(vecnorm(R, 2, 2), 0.30).^3;
end

function w = unitTopo(w)
w = w - mean(w);
m = max(abs(w)); if m > 0, w = w / m; end
end

function w = emgWeights(S)
w = max(0, abs(S(:,2)) - 0.30) .* max(0, 0.50 - S(:,3));
if max(w) > 0, w = w / max(w); end
end

function y = pinkNoise(n, fs, expAmp)
% 1/f^expAmp amplitude spectrum, unit variance
nf   = floor(n/2) + 1;
f    = (0:nf-1)' / n * fs;
f(1) = f(2);
H    = (f.^(-expAmp)) .* exp(1i*2*pi*rand(nf,1));
H(1) = abs(H(1));
if mod(n,2) == 0
    H(end) = abs(H(end));
    Y = [H; conj(flipud(H(2:end-1)))];
else
    Y = [H; conj(flipud(H(2:end)))];
end
y = real(ifft(Y))';
y = y / std(y);
end

function y = bandNoise(n, fs, band)
% unit-variance noise restricted to [band(1) band(2)] Hz
x = randn(1,n);
f = (0:n-1)/n*fs;
f(f > fs/2) = fs - f(f > fs/2);
y = real(ifft(fft(x) .* double(f >= band(1) & f <= band(2))));
s = std(y); if s == 0, s = 1; end
y = y / s;
end

function e = envGate(n, fs, tau)
% smooth 0-1 bursty envelope with characteristic timescale tau seconds
e = smoothdata(randn(1,n), 'gaussian', max(3, round(tau*fs)));
e = (e - mean(e)) / std(e);
e = 1 ./ (1 + exp(-2.5*e));
end

function y = burstOsc(n, fs, band, envSec)
% band-limited noise gated by a slow bursty envelope, unit variance
y = bandNoise(n, fs, band) .* envGate(n, fs, envSec);
s = std(y); if s == 0, s = 1; end
y = y / s;
end

function w = ecgTemplate(fs)
% P-QRS-T complex, peak R normalised to 1
tt = -0.25 : 1/fs : 0.45;
g  = @(mu, sd, a) a * exp(-((tt - mu).^2) / (2*sd^2));
w  = g(-0.16, 0.025,  0.10) ...   % P
   + g(-0.02, 0.008, -0.15) ...   % Q
   + g( 0.00, 0.010,  1.00) ...   % R
   + g( 0.03, 0.012, -0.25) ...   % S
   + g( 0.22, 0.055,  0.28);      % T
end
