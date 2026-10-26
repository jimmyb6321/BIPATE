
function    [EEG, ExG] = chanSplitter(EEG, cfg_full)

% Author: James Barlow
% Created: 08/26/2026
% Last updated: 10/25/2026

% Pulls non-EEG (peripheral) channels out of EEG: the user picks them and their types, then chooses which
% go to a separate ExG .set and which are kept in EEG.etc.peripheral. Picking no channels is allowed (a
% recording with no peripherals); EEG.etc.peripheral then exists but stays empty.

% IN:   EEG = EEGLAB struct
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = EEG struct with all peripheral channels removed
%           EEG.etc.peripheral = .labels, .data [nChan x pnts], .type, .srate for the ones not split out
%       ExG = EEGLAB struct of the split-out channels, saved to the set's folder ([] if none)

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

ExG = [];
if ~isfield(EEG.etc, 'peripheral') || isempty(EEG.etc.peripheral)
    EEG.etc.peripheral = struct('labels', {{}}, 'data', [], 'type', {{}}, 'srate', EEG.srate);
end

if ~isfield(EEG.chanlocs, 'type')
    [EEG.chanlocs.type] = deal('');
end

% every channel is listed; ones whose name/type looks peripheral (and not typed EEG) start ticked
notEEG = ~strcmpi({EEG.chanlocs.type}, 'EEG');
if isfield(EEG.chanlocs, 'description')
    notEEG = notEEG & ~strcmpi({EEG.chanlocs.description}, 'EEG');
end
looksPeriph = detectPeriphs(EEG);
% a clear peripheral name (VEOG, HEOG, ECG, EKG, EMG) is pre-ticked even when the file types it 'EEG'
% (many importers type every channel EEG); other keyword matches still need a non-EEG type
strongName = ~cellfun(@isempty, regexpi({EEG.chanlocs.labels}, 'eog|ecg|ekg|emg', 'once'));
ticked = looksPeriph(:) & (notEEG(:) | strongName(:));
labels = {EEG.chanlocs.labels};
types = {EEG.chanlocs.type};
types(cellfun(@isempty, types)) = {''};

% "Same settings for all sets" (batch): the first set's picks are reused on the others, matched by label
shared = batchShared('get');
useShared = isstruct(shared) && isfield(shared, 'periphLabels');
if useShared
    perIdx = find(ismember(lower(labels), lower(shared.periphLabels)));
else
    [perIdx, ok] = pickChannels('Non-EEG channels', ...
        ['Tick every non-EEG (peripheral) channel: ECG, EOG, EMG, respiration, etc. Likely ones are already ', ...
        'ticked. If the recording has none, untick everything (Select none) and press OK.'], ...
        labels, ticked, {'Type', types});
    if ~ok, error('Channel selection cancelled.'); end
end

if isempty(perIdx)
    if ~useShared
        batchShared('set', struct('periphLabels', {{}}, 'periphTypes', {{}}, 'splitLabels', {{}}));
    end
    EEG.etc.processing_log{end+1} = sprintf('No non-EEG channels to split (%s)', string(datetime('now')));
    EEG.etc.processing_done{end+1} = 'chanSplit';
    return
end

isPeriph = false(numel(EEG.chanlocs), 1);
isPeriph(perIdx) = true;
if useShared   % types from the first set, by label
    [~, where] = ismember(lower(labels(perIdx)), lower(shared.periphLabels));
    periphTypes = shared.periphTypes(where);
    periphTypes = periphTypes(:);
else
    periphTypes = assignPeriphTypes(EEG, isPeriph);
    periphTypes = periphTypes(:);
    if ~iscell(periphTypes) || isempty(periphTypes)
        error('Peripheral channel typing cancelled.');
    end
end
[EEG.chanlocs(perIdx).type] = deal(periphTypes{:});

% which go to their own file vs EEG.etc
if useShared
    splitPick = find(ismember(lower(labels(perIdx)), lower(shared.splitLabels)));
else
    [splitPick, ok] = pickChannels('Split channels', ...
        ['Tick the non-EEG channels to save into a separate .set file (<sessionID>_splitChannels). ', ...
        'Unticked ones stay with the EEG in EEG.etc.peripheral. Leave everything unticked to keep them all.'], ...
        labels(perIdx), false(numel(perIdx), 1), {'Type', periphTypes});
    if ~ok, error('Splitting cancelled.'); end
    % answers for the other sets of a "same settings" batch (ignored when sharing is off)
    batchShared('set', struct('periphLabels', {labels(perIdx)}, 'periphTypes', {periphTypes(:)'}, ...
        'splitLabels', {labels(perIdx(splitPick))}));
end

keepPick = setdiff(1:numel(perIdx), splitPick);
exgIdx = perIdx(splitPick);
etcIdx = perIdx(keepPick);

if ~isempty(exgIdx)
    savePath = fullfile(cfg_full.paths.data_out);
    if ~isfolder(savePath), mkdir(savePath); end
    ExG = pop_select(EEG, 'channel', exgIdx);
    ExG.setname = [char(cfg_full.sessionID) '_splitChannels'];
    ExG = pop_saveset(ExG, 'filename', [char(cfg_full.sessionID) '_splitChannels.set'], ...
        'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
end

% added to any kept from an earlier channel setup run
EEG.etc.peripheral.labels = [EEG.etc.peripheral.labels, {EEG.chanlocs(etcIdx).labels}];
EEG.etc.peripheral.data = [EEG.etc.peripheral.data; EEG.data(etcIdx, :)];
EEG.etc.peripheral.type = [EEG.etc.peripheral.type(:)', periphTypes(keepPick)'];

EEG = pop_select(EEG, 'nochannel', perIdx);   % EEG keeps EEG channels only

EEG.etc.processing_log{end+1} = sprintf('Non-EEG channels split at: %s', string(datetime('now')));
EEG.etc.processing_done{end+1} = 'chanSplit';
end
