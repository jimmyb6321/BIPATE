function prefs = userPref(cfg_full)

% Author: James Barlow
% Created: 05/05/2026
% Last updated: 10/25/2026

% Loads the saved user preferences, or builds the standard defaults on first run, and (re)saves them

% IN:   cfg_full = configuration struct (paths.userPath)

% OUT:  prefs = preferences struct
%           cap_types = cap dropdown list; custom_chanlocs = {capName, chanlocsPath} pairs
%           default_cap, default_ica, target_fs, bandpass [hp lp], bandstop [Hz...], asr_threshold,
%           input (file type), artifactMode, badChanThresh, badChanMethodDef

% TODO: add new channel maps / save new cap types; preview channels and peripheral signals

arguments
    cfg_full (1,1) struct
end

if isfile(fullfile(cfg_full.paths.userPath, "userPreferences.mat")) %saved prefs exist
    loaded = load(fullfile(cfg_full.paths.userPath, "userPreferences.mat"));
    prefs = loaded.prefs;
else %first run: standard defaults
    prefs.cap_types        = {
    'GSN HydroCel-257', ...
    'GSN HydroCel-128', ...
    'GSN HydroCel-64', ...
    'GSN HydroCel-32', ...
    'BrainVision EasyCap 64', ...
    'QuikCap 32', ...
    'Standard 10-20 19ch', ...
    'Standard 10-20 81ch', ...
    'Standard 10-10 33ch', ...
    'PSG / Non-Standard EEG', ...
    'Other'};
    prefs.custom_chanlocs  = {};   % {cap_name, chanlocs_path} pairs
    prefs.default_cap      = 'GSN HydroCel-257';
    prefs.default_ica      = 'runica';   % EEGLAB's own ICA, no plugin needed
    prefs.target_fs        = 500;
    prefs.bandpass         = [0.5 NaN];
    prefs.bandstop         = [60, 120, 180];
    prefs.asr_threshold    = 5;
    prefs.input            = '.set';
    prefs.artifactMode     = 'Semi-automatic';
    prefs.badChanThresh    = 5;
    prefs.badChanMethodDef = {'Variance (Line Noise and Saturation)', 'Kurtosis', 'Mean neighborhood correlation'};
end

save(fullfile(cfg_full.paths.userPath, "userPreferences.mat"), 'prefs')
end