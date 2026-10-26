function [EEG, cfg_full] = epoch_max(EEG, cfg_full)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/25/2026

% Epochs continuous data around user-chosen event types and window (baseline correction is its own job)

% IN:   EEG = continuous EEGLAB struct after badChanDetect
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = epoched EEG struct (not baselined; add the Baseline correction job for that)
%           EEG.etc.EpochInfo = per-epoch struct: .index (urevent), .latency, .type, .start, .end (samples, pre-epoch timeline)
%       cfg_full = cfg with epoch.enabled = true

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'epoch');   % what must run first is listed in jobs.json

EEG = mask_init(EEG);

unEvents = unique({EEG.event.type});

% events and window (asked once per batch when the batch shares this step; events are kept by name)
shared = batchShared('get');
if isempty(shared)
    pickEvent = listdlg("PromptString", "Pick the event type(s) to epoch around", "ListString", unEvents, "SelectionMode", 'multiple', "ListSize", [320 300], "Name", 'Epoching');
    if isempty(pickEvent), warning('No events markers selected! returning to main script...'); return; end
    window = inputdlg({'Start (ms, relative to the event)', 'End (ms, relative to the event)'}, 'Epoch window', [1 45], {'-600', '600'});
    if isempty(window), warning('No epoch window entered! returning to main script...'); return; end
    shared.events = unEvents(pickEvent);
    shared.window = window;
    batchShared('set', shared);
end
pickEvent = find(ismember(unEvents, shared.events));
if isempty(pickEvent), warning('None of the chosen events (%s) are in this recording! returning...', strjoin(shared.events, ', ')); return; end
window = shared.window;
baseWin = str2double(window{1}) /1000; % s
stimWin = str2double(window{2}) /1000; % s

% record where each epoch came from in the continuous data (makeur builds EEG.urevent when the file has none)
EEG = eeg_checkset(EEG, 'makeur');
useEvents = EEG.event(ismember(string({EEG.event.type}), unEvents(pickEvent)));
oldEpoch = struct();
for i = 1:numel(useEvents)
    oldEpoch(i).index = useEvents(i).urevent;
    oldEpoch(i).latency = useEvents(i).latency;
    oldEpoch(i).type = useEvents(i).type;
    oldEpoch(i).start = useEvents(i).latency + baseWin *EEG.srate;
    oldEpoch(i).end = useEvents(i).latency + stimWin*EEG.srate;
end

[EEG, indices] = pop_epoch(EEG, unEvents(pickEvent), [baseWin stimWin]);

oldEpoch = oldEpoch(indices);   % keep only epochs pop_epoch actually made
assert(numel(oldEpoch) == EEG.trials, 'Epoching failed! trials mismatch events!');
EEG = mask_init(EEG);   % fresh epoch mask at the new trial count
EEG.etc.EpochInfo = oldEpoch;


cfg_full.epoch.enabled = true;

savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end


EEG.etc.processing_log{end+1}  = sprintf('Data splitted at %s', string(datetime('now')));
[epochTag, roundSuffix] = stepRound(EEG, 'splitted_data');
EEG.etc.processing_done{end+1} = epochTag;

% no baseline here: the Baseline correction job does that (it asks for its own window)

EEG.setname = [char(cfg_full.sessionID) '_epoched' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_epoched' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');

notifyDone('Epoching Done!')
