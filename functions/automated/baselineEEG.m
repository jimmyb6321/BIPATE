function EEG = baselineEEG(EEG, cfg_full)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Baseline correction of epoched data as its own job (pop_rmbase). The window comes from Settings > Baseline
% (cfg_full.baseline.window, ms); when that is empty it is asked for, starting from the window this set used
% before (EEG.etc.baselineWin) or -200 to -2 ms. In a batch with "same settings" ticked it is asked once.
% (baseline_max still does the automatic re-baselining inside epoching, segment and component rejection.)

% IN:   EEG = epoched EEGLAB struct (EEG.trials > 1)
%       cfg_full = configuration struct (sessionID, paths.data_out; optional baseline.window = [start end] ms)

% OUT:  EEG = baselined EEG struct, saved to <sessionID>_baselined.set (numbered on repeats)
%           EEG.etc.baselineWin = window used (ms), reused by baseline_max afterwards

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'baseline');   % what must run first is listed in jobs.json
if EEG.trials == 1
    error('Baseline correction needs epoched data (run Epoching first).');
end

% window: settings, else shared answer, else ask
window = [];
if isfield(cfg_full, 'baseline') && isfield(cfg_full.baseline, 'window')
    window = cfg_full.baseline.window;
end
shared = batchShared('get');
if isempty(window) && isfield(shared, 'window')
    window = shared.window;
end
if isempty(window)
    suggestion = [-200 -2];
    if isfield(EEG.etc, 'baselineWin'), suggestion = EEG.etc.baselineWin; end
    answer = inputdlg({'Baseline start (ms)', 'Baseline end (ms)'}, 'Baseline window', [1 40], ...
        {num2str(suggestion(1)), num2str(suggestion(2))});
    if isempty(answer)
        error('Baseline correction cancelled: no window given.');
    end
    window = str2double(answer(:)');
    shared.window = window;
    batchShared('set', shared);
end
if numel(window) ~= 2 || any(isnan(window)) || window(1) >= window(2)
    error('Baseline window must be [start end] in ms with start < end.');
end
if window(1) < EEG.times(1) || window(2) > EEG.times(end)
    error('Baseline window [%g %g] ms is outside the epoch (%g to %g ms).', window, EEG.times([1 end]));
end

EEG = pop_rmbase(EEG, window);
EEG.etc.baselineWin = window;

[tag, roundSuffix] = stepRound(EEG, 'baseline');
EEG.etc.processing_log{end+1} = sprintf('Baseline corrected [%g %g] ms at %s', window, string(datetime('now')));
EEG.etc.processing_done{end+1} = tag;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
EEG.setname = [char(cfg_full.sessionID) '_baselined' roundSuffix];
EEG = saveStep(EEG, 'filename', [EEG.setname '.set'], 'filepath', char(savePath), ...
    'savemode', 'onefile', 'version', '7.3');
notifyDone('Baseline correction')
end
