function EEG = rerefEEG(EEG, cfg_full)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Re-references the data at any point in the pipeline. (Named rerefEEG so it does not shadow EEGLAB's reref.m,
% which pop_reref calls.) Replaces preICAreref and postICAreref.
% Where we are is read from EEG.etc.processing_done:
%   no ICA yet               -> before ICA1, saved as <sessionID>_preICAreref
%   ICA run, no removal yet  -> before a later ICA round, saved as <sessionID>_preICA2reref
%   components removed       -> final reference, saved as <sessionID>_finalReRef
% Running the same stage again adds a round number (stepRound), e.g. <sessionID>_finalReRef2.
% The reference type comes from Settings > Re-reference (pre-selected when asking; used as is when "Ask me
% every time" is off, along with its channel(s) and VREF):
%   Average         = average of the good channels (bad channels stay out of the average)
%   Channel(s)      = one or more chosen channels, e.g. Cz; they are marked bad afterwards
%   Linked mastoids = the two mastoids averaged (same as picking both channels), tagged e.g. rerefm1m2
%   Median          = median of the good channels at each sample
%   Robust average  = average of the good channels minus any whose deviation is an outlier (robust z > 5),
%                     repeated until stable; those channels are only left out of the reference
% The first time a set is re-referenced the user also picks the online reference channel (VREF),
% which is marked bad so it stays out of the average and of ICA.
% In a batch with "same settings for all files" ticked, the answers from the first file are reused
% (channels are matched by label).

% IN:   EEG = EEGLAB struct with masks (after bad channel detection)
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = re-referenced EEG struct
%           EEG.etc.ica_rank = rank left for ICA (read by callICA)
%           EEG.etc.reref.<stage> = reference used at that stage
%           EEG.etc.processing_done gets 'reref' + the reference (rerefavg, rerefm1m2, numbered
%           per reference by stepRound, e.g. rerefavg, rerefcz, rerefavg2) plus the stage tags:
%               preICAreref, preICA2reref, or postICAreref and finalReRef

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'reref');   % what must run first is listed in jobs.json
EEG = mask_init(EEG);
doneTags = string(EEG.etc.processing_done);
chanLabels = string({EEG.chanlocs.labels});
shared = batchShared('get');
% Settings > Re-reference: default type / channels / VREF; ask = false runs without any dialog
rr = struct('type', 'Average of good channels', 'channels', '', 'vref', '', 'ask', true);
if isfield(cfg_full, 'reref')
    for fn = fieldnames(cfg_full.reref)'
        rr.(fn{1}) = cfg_full.reref.(fn{1});
    end
end
askUser = logical(rr.ask);
settingTypes = ["Average of good channels", "Channel(s), e.g. Cz", "Linked mastoids", "Median of good channels", "Robust average"];
defType = find(settingTypes == string(rr.type), 1);   % row of refTypes below (same order)
if isempty(defType), defType = 1; end
setChans = split(strtrim(string(rr.channels)))';
setChans = setChans(strlength(setChans) > 0);   % e.g. ["TP9" "TP10"]

% stage
icaDone = any(~cellfun(@isempty, regexp(cellstr(doneTags), '^ICA\d+$', 'once')));
removalDone = any(startsWith(doneTags, 'componentRemoval'));
if removalDone
    stage = 'final';
    stageTag = 'finalReRef';
    saveFolder = '';
elseif icaDone
    stage = 'preICA2';
    stageTag = 'preICA2reref';
    saveFolder = '';
else
    stage = 'preICA1';
    stageTag = 'preICAreref';
    saveFolder = '';
end

% online reference channel, only the first time
firstReref = ~any(startsWith(doneTags, "reref") | doneTags == "preICAreref");
if firstReref
    if isfield(shared, 'vref')
        vrefLabel = shared.vref;
    else
        if isfield(EEG.chanlocs, 'description')
            chanDesc = string({EEG.chanlocs.description});
        else
            chanDesc = strings(size(chanLabels));
        end
        vrefGuess = find(contains(lower(chanDesc), 'vref') | strcmpi(chanLabels, 'Cz') | contains(lower(chanLabels), 'vref'));
        if isempty(vrefGuess)
            vrefGuess = find(var(double(EEG.data(:, :)), 0, 2) < 1e-6, 1);
        end
        if isempty(vrefGuess)
            initVal = 1;
        else
            initVal = vrefGuess(1) + 1;
        end
        if askUser
            vrefAns = listdlg("PromptString", "Select VREF (NONE if VREF is not applicable)", ...
                "SelectionMode", "single", "ListString", ["NONE", chanLabels], "InitialValue", initVal, "ListSize", [300 300]);
            if isempty(vrefAns)
                error('If you have no reference channel, please select NONE');
            end
            vrefOptions = ["NONE", chanLabels];
            vrefLabel = vrefOptions(vrefAns);
        elseif strlength(strtrim(string(rr.vref))) > 0   % the Settings channel (or NONE)
            vrefLabel = strtrim(string(rr.vref));
            if upper(vrefLabel) == "NONE"
                vrefLabel = "NONE";
            else
                k = find(strcmpi(chanLabels, vrefLabel), 1);
                if isempty(k), error('Settings > Re-reference VREF channel %s is not in this recording.', vrefLabel); end
                vrefLabel = chanLabels(k);
            end
        elseif isempty(vrefGuess)   % not asking, nothing set: the guess, or NONE when there is none
            vrefLabel = "NONE";
        else
            vrefLabel = chanLabels(vrefGuess(1));
        end
        if ~askUser, fprintf('Re-reference: VREF = %s (Settings)\n', vrefLabel); end
        shared.vref = vrefLabel;
    end
    vrefIdx = find(chanLabels == vrefLabel, 1);
    if vrefLabel ~= "NONE" && isempty(vrefIdx)
        error('The shared VREF channel %s is not in this recording', vrefLabel);
    end
    if ~isempty(vrefIdx)
        EEG = mask_addChan(EEG, vrefIdx, 'ref');
    end
end

% reference type (typeAns = row of refTypes)
refTypes = ["Average of good channels", "Channel(s), e.g. Cz", "Linked mastoids (average of both mastoids)", ...
    "Median of good channels", "Robust average (outlying channels left out of the average)"];
if isfield(shared, 'refType')
    typeAns = shared.refType;
else
    if askUser   % the Settings default is pre-selected
        typeAns = listdlg("PromptString", "Reference type", "SelectionMode", "single", ...
            "ListString", refTypes, "ListSize", [340 110], "InitialValue", defType);
        if isempty(typeAns)
            error('Re-reference cancelled: no reference type picked.');
        end
    else
        typeAns = defType;
        fprintf('Re-reference: %s (Settings)\n', refTypes(typeAns));
    end
    shared.refType = typeAns;
end

[goodChan, ~] = mask_good(EEG);
goodIdx = find(goodChan);
switch typeAns
    case 1   % average of the good channels
        EEG = pop_reref(EEG, [], 'exclude', find(~goodChan));
        EEG.etc.ica_rank = sum(goodChan) - 1;
        refUsed = 'average';
        refName = 'avg';

    case {2, 3}   % chosen channel(s); linked mastoids = exactly two, likely mastoids pre-selected
        if isfield(shared, 'refLabels')
            refIdx = goodIdx(ismember(chanLabels(goodIdx), shared.refLabels));
            if numel(refIdx) < numel(shared.refLabels)
                error('Shared reference channel(s) %s are not all good channels in this recording', strjoin(shared.refLabels, ', '));
            end
        else
            prompt = "Reference channel(s)";
            initVal = 1;
            if typeAns == 3
                prompt = "Pick the two mastoid channels";
                mastoidNames = ["M1", "M2", "A1", "A2", "TP9", "TP10", "LM", "RM", "E57", "E100", "E94", "E190"];
                guess = find(ismember(upper(chanLabels(goodIdx)), mastoidNames) | ...
                    contains(upper(chanLabels(goodIdx)), "MAST"));   % also LMast / MastR / Mastoid_L style names
                if ~isempty(guess), initVal = guess(:)'; end
                badIdx = find(~goodChan);   % mastoids marked bad are not listed: say so instead of leaving one missing
                badMast = chanLabels(badIdx(ismember(upper(chanLabels(badIdx)), mastoidNames) | contains(upper(chanLabels(badIdx)), "MAST")));
                if ~isempty(badMast)
                    prompt = sprintf("Pick the two mastoid channels (%s marked bad, so not listed)", strjoin(string(badMast), ", "));
                end
            end
            if ~isempty(setChans)   % Settings > Re-reference channels: pre-selected, or used as they are when not asking
                pre = find(ismember(lower(chanLabels(goodIdx)), lower(setChans)));
                if ~isempty(pre), initVal = pre(:)'; end
            end
            if askUser
                chanAns = listdlg("PromptString", prompt, "SelectionMode", "multiple", ...
                    "ListString", chanLabels(goodIdx), "InitialValue", initVal, "ListSize", [300 300]);
                if isempty(chanAns)
                    error('Re-reference cancelled: no reference channel picked.');
                end
            elseif ~isempty(setChans)
                chanAns = find(ismember(lower(chanLabels(goodIdx)), lower(setChans)));
                if numel(chanAns) ~= numel(setChans)
                    error('Settings > Re-reference channel(s) %s are not all good channels in this recording.', strjoin(setChans, ', '));
                end
            elseif typeAns == 3 && numel(initVal) == 2 && ~isequal(initVal, 1)   % the two mastoids it recognised
                chanAns = initVal;
            else
                error('Re-reference: set the reference channel(s) in Settings > Re-reference (or tick "Ask me every time").');
            end
            if typeAns == 3 && numel(chanAns) ~= 2
                error('Linked mastoids needs exactly two channels (%d picked).', numel(chanAns));
            end
            refIdx = goodIdx(chanAns);
            shared.refLabels = chanLabels(refIdx);
        end
        EEG = pop_reref(EEG, refIdx, 'exclude', find(~goodChan), 'keepref', 'on');
        EEG = mask_addChan(EEG, refIdx, 'ref');
        EEG.etc.ica_rank = sum(goodChan) - numel(refIdx);
        refUsed = char(strjoin(chanLabels(refIdx), ', '));
        refName = lower(regexprep(char(strjoin(chanLabels(refIdx), '')), '[^A-Za-z0-9]', ''));

    case 4   % median across the good channels, sample by sample (not a linear reference, so no rank drop)
        refSignal = median(double(EEG.data(goodIdx, :)), 1);
        EEG.data(:, :) = double(EEG.data(:, :)) - refSignal;
        EEG.etc.ica_rank = sum(goodChan);
        refUsed = 'median';
        refName = 'median';

    case 5   % robust average: channels whose deviation is an outlier are left out of the average, repeated
             % until no new ones turn up (at most 4 times). They are only left out of the reference, not marked bad.
        refChans = goodIdx;
        for pass = 1:4
            refSignal = mean(double(EEG.data(refChans, :)), 1);
            spread = std(double(EEG.data(goodIdx, :)) - refSignal, 0, 2);   % per good channel
            robustZ = (spread - median(spread)) / (1.4826 * mad(spread, 1));
            keepRef = goodIdx(robustZ <= 5);
            if isequal(keepRef(:), refChans(:)), break; end
            refChans = keepRef;
        end
        EEG.data(:, :) = double(EEG.data(:, :)) - mean(double(EEG.data(refChans, :)), 1);
        EEG.etc.ica_rank = sum(goodChan) - 1;
        leftOut = setdiff(goodIdx, refChans);
        refUsed = sprintf('robust average (left out: %s)', char(strjoin(chanLabels(leftOut), ', ')));
        refName = 'robustavg';
end
EEG.ref = refUsed;

batchShared('set', shared);
EEG.etc.reref.(stage) = refUsed;

% tags and save
rerefTag = stepRound(EEG, ['reref' refName]);
stageTag = stepRound(EEG, stageTag);
if strcmp(stage, 'final')
    stageTags = {'postICAreref', stageTag};
else
    stageTags = {stageTag};
end
EEG.etc.processing_log{end+1} = sprintf('Re-referenced (%s, %s) at %s', refUsed, stage, string(datetime('now')));
EEG.etc.processing_done = [EEG.etc.processing_done, {rerefTag}, stageTags];

savePath = fullfile(cfg_full.paths.data_out, saveFolder);
if ~isfolder(savePath); mkdir(savePath); end
EEG.setname = [char(cfg_full.sessionID) '_' stageTag];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_' stageTag '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');

% spectra before ICA, for QC
if ~strcmp(stage, 'final')
    qcSave = fullfile(cfg_full.paths.data_out, 'QC');
    if ~isfolder(qcSave); mkdir(qcSave); end
    % pop_spectopo opens its own figure (an empty one made beforehand was what got saved until now)
    f1 = qcSpectopo(EEG, 1, [0 EEG.times(end)], 'EEG', 'percent', 25, 'freq', [2 6 10 22 45], ...
        'freqrange', [1 50], 'electrodes', 'off');
    saveQCFigure(f1, fullfile(qcSave, [char(cfg_full.sessionID) '_' stageTag '_spectopo']));
end

notifyDone('Re-reference')
end
