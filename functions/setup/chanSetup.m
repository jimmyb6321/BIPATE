function [EEG, cfg_full] = chanSetup(EEG, cfg_full)

% Author: James Barlow
% Created: 05/05/2026
% Last updated: 10/25/2026

% Channel setup: stamps the recording start time, splits off peripheral channels, matches the data to the
% chosen cap's channel locations (or builds and saves a new custom cap), optionally reduces GSN-257 to 185

% IN:   EEG = EEGLAB struct from loadData_max
%       cfg_full = configuration struct (recording.cap_type, chanloc paths, paths.userPath, sessionID, paths.data_out)

% OUT:  EEG = EEG struct with chanlocs for the cap, EEG channels only, all typed 'EEG'
%           EEG.etc.metaTime = recording start datetime; metaTimeSource = 'recording' | 'fallback'
%           EEG.etc.chanSetupDropped = cellstr of EEG channels the cap had no location for (dropped; {} if none)
%       cfg_full = cfg refreshed from prefs (and with a new custom cap path when one was made)

% TODO: option to use EEGLAB sample_locs; preview channels and peripheral signals

% recording start: recordingtime is days since 2000-01-01
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'chanSetup');   % what must run first is listed in jobs.json
if isfield(EEG.etc, 'recordingtime')
    holdTime = datetime(2000, 1, 1) + days(EEG.etc.recordingtime);
    holdTime.TimeZone = EEG.etc.timezone;
    EEG.etc.metaTime = holdTime;
    EEG.etc.metaTimeSource = 'recording';
else
    EEG.etc.metaTime = datetime('now', 'TimeZone', 'local');
    warning("No datetime found in meta variables... \n creating datetime as today")
    EEG.etc.metaTimeSource = 'fallback';
end


tmpEasy = load(cfg_full.paths.easyCap4);

cap_type = cfg_full.recording.cap_type;

% peripheral channels out first
[EEG, ~] = chanSplitter(EEG, cfg_full);
labelsBeforeCap = {EEG.chanlocs.labels};   % EEG channels going into the cap match (peripherals already out)


% saved custom cap: keep channels whose labels match its chanlocs
if startsWith(cap_type, 'CUSTOM: ')
    rawNick = char(strtrim(extractAfter(cfg_full.recording.cap_type, 'CUSTOM: ')));   % char: a string here made findCustomCap's keys a string array
    customLocs = load(findCustomCap(cfg_full, rawNick));
    savedChans = customLocs.chanlocs_custom;
    savedChans   = normalizeLocs(savedChans, EEG);
    keptLabels   = {EEG.chanlocs.labels};
    customLabels = {savedChans.labels};
    [matched, idx] = ismember(lower(keptLabels), lower(customLabels));
    if ~any(matched)
        error('No channels matched the custom montage "%s".', rawNick);
    end
    EEG = pop_select(EEG, 'channel', find(matched));
    EEG.chanlocs = savedChans(idx(matched));
    [EEG.chanlocs.type] = deal('EEG');
else
    % built-in caps: load the cap's chanlocs, keep channels whose labels match (case-insensitive)

    switch cap_type
        case 'GSN HydroCel-257'   % fixed order, so locs are assigned directly + 10-10 names in .description
            loc257 = load(cfg_full.paths.chanlocsHD);
            chan257 = loc257.chanlocs257;
            if EEG.nbchan ~= 257   % locations are assigned by position, so the count must match exactly
                error(['This set has %d EEG channels after the peripheral split; GSN HydroCel-257 expects 257. ' ...
                    'Check the Cap column for this set.'], EEG.nbchan);
            end
            EEG.chanlocs(1:257) = chan257(1:257);

            mapTmp = load(char(cfg_full.paths.GSN10_10));
            map = mapTmp.mapping256;
    
            % 10-10 labels
            for i = 1:length(map.chanNum)
                if map.chanNum(i) > 0 && map.chanNum(i) <= 257
                    EEG.chanlocs(map.chanNum(i)).description = map.label{i};
                end
            end
    
            [EEG.chanlocs.type] = deal('EEG');
    
    
    
       case 'GSN HydroCel-128'
            tmp = readlocs(char(cfg_full.paths.chanlocsGSN128));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels  = {EEG.chanlocs.labels};
            tmpLabels  = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
            

            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            EEG = pop_select(EEG, 'channel', find(matched));

            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');
    
        case 'GSN HydroCel-64'
            tmp = readlocs(char(cfg_full.paths.chanlocsGSN64));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels  = {EEG.chanlocs.labels};
            tmpLabels  = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
       

            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            EEG = pop_select(EEG, 'channel', find(matched));
            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');
   
        case 'GSN HydroCel-32'
            tmp = readlocs(char(cfg_full.paths.chanlocsGSN32));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels  = {EEG.chanlocs.labels};
            tmpLabels  = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
        

            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            EEG = pop_select(EEG, 'channel', find(matched));
            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');

        case 'Standard 10-20 19ch'
            tmp = readlocs(char(cfg_full.paths.chanlocs1020_19));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels = {EEG.chanlocs.labels};
            tmpLabels = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
            
          
            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            

            EEG = pop_select(EEG, 'channel', find(matched));

            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');

        case 'Standard 10-20 81ch'
            tmp = readlocs(char(cfg_full.paths.chanlocs1020_81));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels = {EEG.chanlocs.labels};
            tmpLabels = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
            
          
            
            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    

            EEG = pop_select(EEG, 'channel', find(matched));

            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');

        case 'Standard 10-10 33ch'
            tmp = readlocs(char(cfg_full.paths.chanlocs1010_33));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels = {EEG.chanlocs.labels};
            tmpLabels = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));
       
            
            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            EEG = pop_select(EEG, 'channel', find(matched));

            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');   

        case 'QuikCap 32'
            tmp = readlocs(char(cfg_full.paths.chanlocsQuik32));
            tmp = normalizeLocs(tmp, EEG);       
            eegLabels = {EEG.chanlocs.labels};
            tmpLabels = {tmp.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(tmpLabels));


            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end    
            EEG = pop_select(EEG, 'channel', find(matched));

            EEG.chanlocs = tmp(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');           
        case 'BrainVision EasyCap 64'
            eegLabels = {EEG.chanlocs.labels};
            easy64 = tmpEasy.chlocs;

            chlocLabels = {easy64.labels};
            [matched, idx] = ismember(lower(eegLabels), lower(chlocLabels));
            [EEG.chanlocs(matched).type] = deal('EEG');
    
            
            if ~any(matched)
                error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

            end       
            EEG = pop_select(EEG, 'channel', find(matched));
            EEG.chanlocs = easy64(idx(matched));
            [EEG.chanlocs.type] = deal('EEG');
    
    
        case 'PSG / Non-Standard EEG'   % look labels up in the standard 10-5 file
            EEG = pop_chanedit(EEG, 'lookup', char(cfg_full.paths.standard10_20));
            [EEG.chanlocs.type] = deal('EEG');
            
        case 'Other'   % new custom cap: name it, optionally give a chanlocs file, save it to prefs for reuse
            prefsPath = fullfile(cfg_full.paths.userPath, 'userPreferences.mat');
            if isfile(prefsPath)
                prefs = load(prefsPath);
                prefs = prefs.prefs;
            else
                prefs = userPref(cfg_full);   % first run: defaults
            end

            fig = uifigure("Name", "New montage/cap setup");
            scr = get(0, 'ScreenSize');
            figW = 500;
            figH = 350;
            fig.Position = [scr(3)*0.4 scr(4)*0.4 figW figH];
    
            % cap name
            nickname = uilabel(fig, "Text", "Enter cap/montage name (try to be as descriptive as possible");
            nickname.Position    = [20 290 460 30];
            nickname.HorizontalAlignment = 'center';
            textNick         = uitextarea(fig);
            textNick.Position    = [20 255 460 25]; 
            textNick.HorizontalAlignment = 'center';
            
            % chanlocs file (optional)
            browseLabel     = uilabel(fig, "Text", "Choose channel locations file (leave blank if no channel loc file)");
            browseLabel.Position = [20 200 460 30]; 
            browseLabel.HorizontalAlignment = 'center';
            btnBrowseIn = uibutton(fig, 'Text', 'Browse'); %browse button
            btnBrowseIn.Position = [390 165 90 25];
            btnBrowseIn.HorizontalAlignment = 'center';
            textchan = uitextarea(fig); %display of selected folder
            textchan.Position    = [20 165 360 25];
            textchan.HorizontalAlignment = 'center';
            btnBrowseIn.ButtonPushedFcn = @(~,~) browseFolder(textchan, fig);
    

            uilabel(fig, 'Text', 'Leave blank if no file available — pipeline will auto-detect using standard 10-20 labels.', ...
            'Position', [20 130 460 30], 'FontColor', [0.5 0.5 0.5], 'WordWrap', 'on');
            
            btn = uibutton(fig, 'Text', 'OK');
            btn.Position         = [figW/2-50 20 100 30];
            btn.ButtonPushedFcn = @(btn, event) uiresume(fig);
            applyTheme(fig);   % BIPATE colours
uiwait(fig);

            newNick = textNick.Value; 
            rawNick = strtrim(newNick{1});
            chanFile = strtrim(textchan.Value{1});
            delete(fig);
            if isempty(rawNick)
                error('Please enter montage/cap nickname')
            end

            % one name for the cap list, the prefs entry and the file; Windows file names ignore case, so a
            % name that differs from an existing cap only by case would overwrite that cap's file
            capName = ['CUSTOM: ' rawNick];
            capFile = fullfile(cfg_full.paths.userPath, [matlab.lang.makeValidName(rawNick) '.mat']);
            sameName = strcmpi(prefs.cap_types, capName);
            if any(sameName)
                answer = questdlg(sprintf('A cap called "%s" already exists. Replace its channel locations?', ...
                    prefs.cap_types{find(sameName, 1)}), 'Cap exists', 'Replace', 'Cancel', 'Cancel');
                if ~strcmp(answer, 'Replace')
                    error('Channel setup cancelled: cap name already in use.');
                end
                prefs.cap_types(sameName) = [];
            end
            prefs.cap_types{end+1} = capName;
            cfg_full.recording.cap_type = capName;

            % with a chanlocs file: save it as the custom cap, then match channels to it
            if ~isempty(chanFile)
                [~, ~, ext] = fileparts(chanFile);
                if strcmpi(ext, '.mat')
                    newGuy = load(chanFile);
                    newMat = fieldnames(newGuy);
                    chanlocs_custom = newGuy.(newMat{1});
                else
                    chanlocs_custom = readlocs(chanFile);   % .sfp / .ced / .elp
                end
                chanlocs_custom = normalizeLocs(chanlocs_custom, EEG);
                saveCustomCap(prefs, cfg_full, capName, capFile, chanlocs_custom);

                keptLabels = {EEG.chanlocs.labels};
                customLabels = {chanlocs_custom.labels};
                [matched, idx] = ismember(lower(keptLabels), lower(customLabels));
                if ~any(matched)
                    error("No channels in this file match the chanlocs file for this cap consider using a CUSTOM channel")

                end
                EEG = pop_select(EEG, 'channel', find(matched));

                EEG.chanlocs = chanlocs_custom(idx(matched));
                [EEG.chanlocs.type] = deal('EEG');

            % no file: look labels up in the standard 10-20 file and save the result as the custom cap
            else
                EEG = pop_chanedit(EEG, 'lookup', char(cfg_full.paths.standard10_20));
                [EEG.chanlocs.type] = deal('EEG');
                chanlocs_custom = EEG.chanlocs;
                saveCustomCap(prefs, cfg_full, capName, capFile, chanlocs_custom);
            end
    end
end

% channels the cap's locations file had no match for were dropped above: say which, never silently
dropped = labelsBeforeCap(~ismember(lower(labelsBeforeCap), lower({EEG.chanlocs.labels})));
EEG.etc.chanSetupDropped = dropped;
if ~isempty(dropped)
    dropMsg = sprintf('Cap "%s" has no location for %d channel(s), so they were dropped: %s', ...
        char(cap_type), numel(dropped), strjoin(dropped, ', '));
    EEG.etc.processing_log{end+1} = sprintf('%s (%s)', dropMsg, string(datetime('now')));
    warning('chanSetup:dropped', '%s', dropMsg);
    dropBox = warndlg(sprintf('%s: %s', char(cfg_full.sessionID), dropMsg), 'Channels dropped by the cap', 'non-modal');   % does not stop a batch
    dropBox.Tag = 'bipateKeep';   % bipate's clean-up after each job leaves it open
end

EEG = chanReduce(EEG, cfg_full);   % GSN-257 -> 185 if wanted

EEG = eeg_checkset(EEG);
EEG.etc.processing_log{end+1} = sprintf('Channel setup done: %s', string(datetime('now')));
[setupTag, roundSuffix] = stepRound(EEG, 'chanSetup');
EEG.etc.processing_done{end+1} = setupTag;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
EEG.setname = [char(cfg_full.sessionID) '_chanSetup' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_chanSetup' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');

cfg_full = cfgUpdate(cfg_full);

notifyDone('Channel Setup');
end 


% makes a chanlocs struct's fields match EEG.chanlocs (drops extras, adds missing as []), so eeg_checkset keeps them
function tmp = normalizeLocs(tmp, EEG)
if isempty(EEG.chanlocs) || ~isstruct(EEG.chanlocs)
    % nothing to match against: drop BESA fields, add ref/urchan
    if isfield(tmp, 'sph_theta_besa'), tmp = rmfield(tmp, 'sph_theta_besa'); end
    if isfield(tmp, 'sph_phi_besa'),   tmp = rmfield(tmp, 'sph_phi_besa');   end
    for k = 1:length(tmp), tmp(k).ref=''; tmp(k).urchan=[]; end
    return
end
eegFields = fieldnames(EEG.chanlocs);
tmpFields = fieldnames(tmp);

% drop fields EEG.chanlocs doesn't have
extraFields = setdiff(tmpFields, eegFields);
for i = 1:length(extraFields)
    tmp = rmfield(tmp, extraFields{i});
end

% add fields EEG.chanlocs has
missingFields = setdiff(eegFields, fieldnames(tmp));
for i = 1:length(missingFields)
    [tmp.(missingFields{i})] = deal([]);
end
end



% saves a custom cap's chanlocs to capFile and records it in userPreferences.mat under capName
% (replacing an entry with the same name, ignoring case)
function saveCustomCap(prefs, cfg_full, capName, capFile, chanlocs_custom)
save(capFile, 'chanlocs_custom');
if ~isfield(prefs, 'custom_chanlocs'), prefs.custom_chanlocs = {}; end
sameName = cellfun(@(pair) strcmpi(pair{1}, capName), prefs.custom_chanlocs);
prefs.custom_chanlocs(sameName) = [];
prefs.custom_chanlocs{end+1} = {capName, capFile};
save(fullfile(cfg_full.paths.userPath, 'userPreferences.mat'), 'prefs');
end

% path of a saved custom cap's chanlocs file. Older caps were saved under '<name>_autoGenerated' or the
% bare name, so those keys are tried too.
function capFile = findCustomCap(cfg_full, rawNick)
keys = {['CUSTOM: ' rawNick], rawNick, [rawNick '_autoGenerated']};
prefsPath = fullfile(cfg_full.paths.userPath, 'userPreferences.mat');
if isfile(prefsPath)
    prefs = load(prefsPath);
    pairs = prefs.prefs.custom_chanlocs;
    for k = 1:numel(keys)
        hit = find(cellfun(@(pair) strcmp(pair{1}, keys{k}), pairs), 1, 'last');
        if ~isempty(hit) && isfile(pairs{hit}{2})
            capFile = char(pairs{hit}{2});
            return
        end
    end
end
for k = 1:numel(keys)
    fieldName = matlab.lang.makeValidName(keys{k});
    if isfield(cfg_full.paths, fieldName) && isfile(cfg_full.paths.(fieldName))
        capFile = char(cfg_full.paths.(fieldName));
        return
    end
end
error('No saved channel locations found for custom cap "%s". Set it up again with cap type ''Other''.', rawNick);
end

% file picker for a chanlocs file -> text box, then refocus the dialog
function browseFolder(textField, fig)
    [fname, fpath] = uigetfile({'*.mat;*.sfp;*.ced;*.elp', 'Channel Location Files'}, 'Select channel locations file');
    if fname ~= 0
        textField.Value = fullfile(fpath, fname);
        figure(fig);
    end
end