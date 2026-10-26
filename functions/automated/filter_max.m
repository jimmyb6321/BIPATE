function EEG = filter_max(EEG, cfg_full)

% Author: James Barlow
% Created: 05/13/2026
% Last updated: 10/25/2026

% Highpass/lowpass/notch filtering with a confirm dialog; saves pre/post PSDs for QC

% IN:   EEG = EEGLAB struct after chanSetup
%       cfg_full = configuration struct (filter.highpass/lowpass/notch, sessionID, paths.data_out)

% OUT:  EEG = filtered EEG struct (unchanged if the dialog is cancelled)
%           EEG.etc.lineNoise = .freq (Hz), .labels, .ratio [nbchan x 1] line-noise power ratio before
%           filtering (used by badChanDetect's line-noise check)

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'filter');   % what must run first is listed in jobs.json
[filtTag, roundSuffix] = stepRound(EEG, 'filter');

% pre-filter PSD for comparison (log frequency axis, click a line for its channel)
qcSave = fullfile(cfg_full.paths.data_out, 'QC', 'figures');
if ~isfolder(qcSave), mkdir(qcSave); end
chanLabels = {EEG.chanlocs.labels};
[power, freqs] = channelPSD(EEG.data, EEG.srate);
f = plotChannelPSD(power, freqs, chanLabels, [], 'Before filtering');
preName = fullfile(qcSave, [char(cfg_full.sessionID) '_preFilterPSD' roundSuffix]);
saveQCFigure(f, preName);   % hidden and closed during a batch

% confirm or change filter settings
hp = numToStrDefault(cfg_full.filter.highpass);
lp = numToStrDefault(cfg_full.filter.lowpass);
notch = numToStrDefault(cfg_full.filter.notch);

prompt = {'Highpass cutoff (Hz, empty to skip):', ...
          'Lowpass cutoff (Hz, empty to skip):', ...
          'Notch frequency (Hz, empty to skip; comma-separated for multiple):'};
defAns = {hp, lp, notch};
answer = batchShared('get');
if isempty(answer)
    if ~isfield(cfg_full.filter, 'ask') || cfg_full.filter.ask   % Settings > Filter "Ask me every time"
        answer = inputdlg(prompt, 'Filter settings', 1, defAns);
    else
        answer = defAns;   % the Settings values, no dialog
        fprintf('Filter: using Settings values (high-pass %s, low-pass %s, notch %s).\n', hp, lp, notch);
    end
    batchShared('set', answer);
end

if isempty(answer)
    warning('Filtering cancelled, returning EEG unchanged.');
    return;
end


hp = str2double(answer{1});
lp = str2double(answer{2});
% notch list: numbers separated by commas and/or spaces ("60, 120" or "60 120"); empty = no notch
notchText = strtrim(answer{3});
notch = [];
if ~isempty(notchText)
    notch = str2double(strsplit(notchText, {',', ' ', ';'}, 'CollapseDelimiters', true));
    if any(isnan(notch))
        error('Notch frequencies "%s" are not all numbers (use e.g. 60, 120).', notchText);
    end
end




nyquist = EEG.srate / 2;

% line noise per channel, measured BEFORE any filtering (a working notch hides it afterwards, but a channel
% that picks up far more mains noise than the rest is badly connected). Ratio = mean power within 2 Hz of
% the line frequency / mean power 16-4 Hz either side of it, on median-referenced data. Most channels sit near 1-3; badChanDetect
% flags the outliers. Line frequency = first notch frequency, or 60 Hz when no notch is set.
lineFreq = 60;
if ~isempty(notch), lineFreq = notch(1); end
if lineFreq + 20 < nyquist
    winLen = 2 * EEG.srate;
    % median-referenced copy, like badChanDetect's features: channels next to the recording reference
    % carry almost no signal against it, which made their ratio look huge
    medRef = double(EEG.data(:, :));
    medRef = medRef - median(medRef, 1);
    [pxx, fx] = pwelch(medRef', hann(winLen), winLen / 2, winLen, EEG.srate);
    clear medRef
    onLine = abs(fx - lineFreq) <= 2;
    beside = abs(fx - lineFreq) >= 4 & abs(fx - lineFreq) <= 16;
    EEG.etc.lineNoise = struct('freq', lineFreq, 'labels', {{EEG.chanlocs.labels}}, ...
        'ratio', (mean(pxx(onLine, :), 1) ./ mean(pxx(beside, :), 1))', 'measured', char(datetime('now')));
    clear pxx
end
notch_valid = notch(notch < nyquist - 5);  % 5 Hz margin
if numel(notch_valid) < numel(notch)
    warning('Skipping notch frequencies within 5 Hz of Nyquist (%g Hz): %s', nyquist, num2str(notch(notch >= nyquist - 5)));
end
notch = notch_valid;

% apply filters (notch = narrow bandstop per frequency)
if ~isnan(hp)
    EEG = pop_eegfiltnew(EEG, 'locutoff', hp);
end
if ~isnan(lp)
    EEG = pop_eegfiltnew(EEG, 'hicutoff', lp);
end
if ~isempty(notch)
    for k = 1:numel(notch)
        hw = max(0.5, notch(k)/30);
        EEG = pop_eegfiltnew(EEG, notch(k)-hw, notch(k)+hw, [], 1);
    end
end

EEG.etc.processing_log{end+1} = sprintf('Filtered: hp=%s, lp=%s, notch=%s: at %s', num2str(hp), num2str(lp), num2str(notch), string(datetime('now')));
EEG.etc.processing_done{end+1} = filtTag;
savePath = fullfile(cfg_full.paths.data_out);
EEG.setname = [char(cfg_full.sessionID) '_filtered' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_filtered' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');



% post-filter PSD
[power, freqs] = channelPSD(EEG.data, EEG.srate);
f = plotChannelPSD(power, freqs, chanLabels, [], 'After filtering');
postName = fullfile(qcSave, [char(cfg_full.sessionID) '_filteredPSD' roundSuffix]);
saveQCFigure(f, postName);

notifyDone('Filtering')

end


% number -> dialog default string ('' for empty/NaN)
 function s = numToStrDefault(x)
    if isempty(x) || (isscalar(x) && isnan(x)) || ~isnumeric(x)
        s = '';
    else
        s = strjoin(string(x), ', ');   % "60, 120": reads back the same way
        s = char(s);
    end
end