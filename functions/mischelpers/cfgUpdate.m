function cfg_full = cfgUpdate(cfg_full)

% Author: James Barlow
% Created: 05/08/2026
% Last updated: 10/25/2026

% Overlays the saved user preferences (BIPATE_user\userPreferences.mat) onto a cfg,
% and back-fills fields older saved cfgs are missing

% IN:   cfg_full = configuration struct (paths.userPath; bipateUserDir if missing)

% OUT:  cfg_full = updated cfg: defaults.*, recording.target_fs, filter.*, artifact.badChan*,
%           recording.caplist and custom chanloc paths taken from prefs; sessionID and recording.timepoint ensured;
%           then every Settings-window override (prefs.overrides)

% backward compatibility: cfg files saved before sessionID existed
arguments
    cfg_full (1,1) struct
end

if ~isfield(cfg_full, 'sessionID')
    cfg_full.sessionID = cfg_full.pptID;
end
if ~isfield(cfg_full.recording, 'timepoint')
    cfg_full.recording.timepoint = "";
end

% personal settings live in the user folder (bipateUserDir), outside the package
if isfield(cfg_full.paths, 'userPath'), userPath = cfg_full.paths.userPath; else, userPath = bipateUserDir(); end
if isfile(fullfile(userPath, 'userPreferences.mat'))
    tmp = load(fullfile(userPath, 'userPreferences.mat'));
    prefs = tmp.prefs;
    
    % custom caps -> cfg.paths.<capName>
    if ~isfield(prefs, 'custom_chanlocs'), prefs.custom_chanlocs = {}; end
    for i = 1:length(prefs.custom_chanlocs)
        pair = prefs.custom_chanlocs{i};
        locName = matlab.lang.makeValidName(pair{1});
        locPath = pair{2};
        cfg_full.paths.(locName) = locPath;
    end
    
    % older preference fields -> cfg (each only if it was saved)
    legacy = {'default_cap', 'defaults.cap_type'; 'default_ica', 'defaults.icaMethod'; ...
        'artifactMode', 'defaults.mode_default'; 'asr_threshold', 'defaults.asr_threshold'; ...
        'input', 'defaults.input_format'; 'target_fs', 'recording.target_fs'; 'bandstop', 'filter.notch'; ...
        'badChanThresh', 'artifact.badChanThresh'; 'badChanMethodDef', 'artifact.badChanMethodDef'; ...
        'cap_types', 'recording.caplist'};
    for row = 1:size(legacy, 1)
        if isfield(prefs, legacy{row, 1})
            parts = strsplit(legacy{row, 2}, '.');
            cfg_full = setfield(cfg_full, parts{:}, prefs.(legacy{row, 1}));
        end
    end
    % the cap list's CUSTOM entries always come from the saved custom caps, so renamed / deleted ones drop out
    isCustom = startsWith(string(cfg_full.recording.caplist), 'CUSTOM: ');
    customNames = cellfun(@(pair) char(pair{1}), prefs.custom_chanlocs, 'UniformOutput', false);
    cfg_full.recording.caplist = [reshape(cfg_full.recording.caplist(~isCustom), 1, []), customNames(:)'];

    if isfield(prefs, 'bandpass')
        cfg_full.filter.highpass = prefs.bandpass(1);
        cfg_full.filter.lowpass = prefs.bandpass(2);
    end

    % Settings window overrides: rows of {key, value}, key = dotted cfg field ('filter.highpass'); applied
    % last so they win over everything above
    if isfield(prefs, 'overrides')
        for row = 1:size(prefs.overrides, 1)
            parts = strsplit(prefs.overrides{row, 1}, '.');
            cfg_full = setfield(cfg_full, parts{:}, prefs.overrides{row, 2});
        end
    end

end



end