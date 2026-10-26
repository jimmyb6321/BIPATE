function cfg = cfg_init()

% Author: James Barlow
% Created: 06/19/2026
% Last updated: 10/25/2026

% Builds the base cfg: repo paths, permanent-variable files, and default processing settings,
% then overlays the user's saved preferences (cfgUpdate). Change defaults here.

% IN:   none

% OUT:  cfg = configuration struct
%           paths = repo, function, permanent_variables (shipped chanlocs), userPath (personal files: bipateUserDir),
%                   eeglab and chanloc file paths; data_in/data_out set later
%           recording = target_fs, cap_type, input_format, caplist, inputTypes
%           filter = highpass, lowpass, notch (Hz)
%           ica = method, hp, amica_threads, artifactThresh
%           artifact = mode, thresholds, bad-channel methods
%           defaults = cap_type, icaMethod, mode_default, asr_threshold, input_format (GUI defaults)
%           epoch.enabled, pptID

% repo paths, found from this file's location
pipeline_root = fileparts(mfilename('fullpath')); %folder holding cfg_init
cfg.paths.cfgpath   = pipeline_root;
[folder, ~, ~]   = fileparts(cfg.paths.cfgpath); %repo root
functionPath        = fullfile(folder, "functions");
varPath             = fullfile(folder, "permanent_variables");
cfg.paths.functionPath  = functionPath;
cfg.paths.varPath       = varPath;
% personal files live outside the package (bipateUserDir), so updating BIPATE never touches them
userPath = userFolder(varPath);
cfg.paths.userPath = userPath;
varD = dir(varPath);
permaVars = {varD.name}; %files in permanent_variables (shipped channel location files)
if ~isfile(fullfile(userPath, "eeglabPath.mat")) %eeglab path saved yet?
    cfg.paths.eeglab = '';
else
    load(fullfile(userPath, "eeglabPath.mat"), "eeglabPath");
    cfg.paths.eeglab = fullfile(string(eeglabPath));
end
% who is processing (first-launch window in bipate; empty until then) -> EEG.etc.processed_by
cfg.user = [];
if isfile(fullfile(userPath, "userInfo.mat"))
    loaded = load(fullfile(userPath, "userInfo.mat"), "userInfo");
    cfg.user = loaded.userInfo;
end
% channel location files: {file, description, cfg.paths field}
needed = {{"chanInfo_185.mat",'Reduced 256 to 185 channel info', 'chanInfo_185'}, {"inside185ch.mat", 'Reduced 256 to 185 index', 'inside185'}, ...
    {"chanlocs257.mat", 'GSN-Hydrocel 257 .mat', 'chanlocsHD'}, {"GSN-HydroCel-257_RECAP.sfp", 'GSN-Hydrocel 257 .sfp', 'GSN257'}, ...
    {"chlocs_brainamp62milano.mat", '64 Channel Easy Cap channel locations', 'easyCap4'}, {"GSN-HydroCel-128.sfp", 'GSN Hydrocel-128 .mat', 'chanlocsGSN128'}, ...
    {"GSN-HydroCel-64_1.0.sfp", 'GSN-HydroCel 64 .sfp', 'chanlocsGSN64'}, {"GSN-HydroCel-32.sfp", 'GSN-Hydrocel 32 .sfp', 'chanlocsGSN32'}, ...
    {"standard-10-20-Cap19.ced", '10-20 19 channel .ced', 'chanlocs1020_19'}, {"standard-10-20-Cap81.ced", '10-20 81 channel .ced', 'chanlocs1020_81'}, ...
    {"standard-10-10-Cap33.ced", '10-10 33 channel .ced', 'chanlocs1010_33'}, {"32ch_quikcap.sfp", ' 32 channel QuikCap .sfp', 'chanlocsQuik32'}, ...
    {"standard-10-5-cap385.elp", 'Standard channel locations', 'standard10_20'}, {"GSN256_10_10_mapping.mat", 'GSN HydroCel 256 10-10 mapping', 'GSN10_10'}};
% warn about any missing file, store the path for the rest
for i = 1:numel(needed)
    needCell = needed{i};
    varNam = char(needCell{3});
    needPath = char(needCell{1});
    if ~any(strcmpi(needCell{1}, permaVars))
        warning([char(needCell{2}) ' not found. You may run into errors when setting up channels. Please redownload this file from Github and move to permanent_variables folder'])
    else
        cfg.paths.(varNam) = fullfile(varPath, needPath);
    end
end
cfg.paths.fullfolder = folder; %main preprocessing folder
cfg.paths.data_in    = '';   % raw data input folder
cfg.paths.data_out   = '';   % processed output root (nested folders created here)
% processing defaults
cfg.recording.target_fs         = 500;
cfg.recording.askTargetFs       = true;   % false = Downsample uses target_fs without asking
cfg.filter.highpass             = 0.5;
cfg.filter.lowpass              = NaN;
cfg.filter.notch                = 60;
cfg.filter.ask                  = true;   % false = Filter uses the values above without asking
cfg.ica.amica_threads           = 6;
% GUI defaults (overwritten by userPreferences in cfgUpdate)
cfg.defaults.cap_type = 'GSN HydroCel-257';
cfg.recording.cap_type        = 'GSN HydroCel-257';
cfg.artifact.mode             = 'Semi-automatic';
cfg.artifact.asr_threshold    = 5;
cfg.recording.input_format    = '.set';
cfg.defaults.icaMethod               = 'runica';   % EEGLAB's own extended Infomax: works with no ICA plugin
cfg.defaults.mode_default             = 'Semi-automatic';
cfg.defaults.asr_threshold    = 5;
cfg.defaults.input_format    = '.set';
% artifact thresholds (not used yet)
cfg.artifact.amp_threshold    = ''; % amp threshold
cfg.artifact.step_threshold   = ''; % voltage step threshold
cfg.artifact.muscle_band      = ''; % muscle range
cfg.artifact.ultrahighSVD    = ''; % frequency range
cfg.artifact.clipping         = '';
cfg.artifact.kurt_threshold   = ''; %ex: 5 SD
cfg.ica.hp = 1;
% re-reference defaults (Settings > Re-reference); with ask = false the job runs without dialogs
cfg.reref.type     = 'Average of good channels';   % or Channel(s), e.g. Cz / Linked mastoids / Median of good channels / Robust average
cfg.reref.channels = '';     % e.g. 'TP9 TP10' (Channel(s) / Linked mastoids); empty = guess the mastoids
cfg.reref.vref     = '';     % online reference label, 'NONE', or empty = guess (description "vref", Cz, or a flat channel)
cfg.reref.ask      = true;
cfg.ica.method = 'runica';
cfg.ica.artifactThresh = 0.85;   % reject artifact-class comps (muscle/eye/heart/line/channel) above this prob
cfg.artifact.badChanThresh      = 5;
cfg.artifact.badChanMethodDef = {'Variance (Line Noise and Saturation)', 'Kurtosis', 'Mean neighborhood correlation', 'Line noise (measured before notch)'};
cfg.artifact.minKeptSec       = [];  % Apply cuts: kept pieces shorter than this many seconds are dropped too; [] = off (suggested 2)
cfg.artifact.badChanMethodAll   = {'Variance (Line Noise and Saturation)', 'Kurtosis', 'Mean neighborhood correlation', 'PSD outliers', 'clean_rawdata comparison', 'Line noise (measured before notch)'};
cfg.recording.caplist = { ... % cap dropdown options
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
cfg.recording.inputTypes = {'Auto', '.set', '.edf', '.mff', '.eeg', '.nxe'};
cfg.epoch.enabled = false;
cfg.pptID = '';
% settings added with the Settings window (overridden by prefs.overrides in cfgUpdate)
cfg.general.outRoot = '';            % default output folder for bipate ('' = choose each time)
cfg.general.saveMode = 'After every step';   % or 'Once per set, at the end' (bipate main window / Settings > General)
cfg.misc.sound = true;               % chime when a step finishes
cfg.misc.doneBox = true;             % 'done' message box when a step finishes
cfg.misc.showQC = 'Single-set runs only';   % when QC figures open: Never / After every job / Single-set runs only / Single-job runs only (showQC)
cfg.demean.baseline = [];            % ms window for epoched data; [] = whole epoch
cfg.baseline.window = [];            % baseline correction window (ms); [] = ask
cfg.laplacian.m = 4;                 % spline order
cfg.laplacian.lambda = 1e-5;         % smoothing
cfg.laplacian.nTerms = 50;           % Legendre terms
cfg.laplacian.headRadius = 10;       % cm (CSD in microvolt/cm^2)
% stored event list for the video editor (Settings > Edit event markers): {type, label, marker color}.
% Offered in "Add event"; a type in a recording that is on the list is drawn in the list's color.
% Package defaults: red eyes, green movement/speech, yellow interview, blue music.
cfg.video.storedEvents = {
    'eyeo', 'eyes open', '#FF0000'
    'eyec', 'eyes closed', '#FF0000'
    'emov', 'eye movement', '#FF0000'
    'esof', 'eye shades off', '#FF0000'
    'eson', 'eye shades on', '#FF0000'
    'move', 'ppt moving', '#00FF00'
    'sspe', 'staff speaking', '#00FF00'
    'spea', 'ppt speaking', '#00FF00'
    'snor', 'snoring', '#00FF00'
    'inen', 'interview start', '#FFFF00'
    'inon', 'interview end', '#FFFF00'
    'muof', 'music off', '#0000FF'
    'muon', 'music on', '#0000FF'
    'mush', 'music headphones', '#0000FF'
    'musp', 'music speakers', '#0000FF'
    };

cfg = cfgUpdate(cfg);   % overlay saved user preferences

addpath(genpath(cfg.paths.functionPath))
end

% IN:  varPath = <BIPATE>\permanent_variables
% OUT: userPath = the personal folder (same rule as bipateUserDir, repeated here because cfg_init runs before
%      BIPATE's subfolders are on the path). The first time, personal files an older version kept in
%      permanent_variables are moved there, and custom caps saved there are moved and re-pointed.
function userPath = userFolder(varPath)
base = strtok(char(userpath), pathsep);
if isempty(base)
    base = fullfile(char(java.lang.System.getProperty('user.home')), 'Documents', 'MATLAB');
end
userPath = fullfile(base, 'BIPATE_user');
if ~isfolder(userPath), mkdir(userPath); end
moved = {};
for f = {'userPreferences.mat', 'userInfo.mat', 'eeglabPath.mat', 'jobTimes.mat', 'batch_history'}
    src = fullfile(varPath, f{1});
    dst = fullfile(userPath, f{1});
    if (isfile(src) || isfolder(src)) && ~isfile(dst) && ~isfolder(dst)
        movefile(src, dst);
        moved{end+1} = f{1}; %#ok<AGROW>
    end
end
prefsFile = fullfile(userPath, 'userPreferences.mat');
if isfile(prefsFile)
    S = load(prefsFile);
    prefs = S.prefs;
    changed = false;
    if isfield(prefs, 'custom_chanlocs')
        for i = 1:numel(prefs.custom_chanlocs)
            [~, nm, ext] = fileparts(char(prefs.custom_chanlocs{i}{2}));
            if isempty(nm), continue; end
            src = fullfile(varPath, [nm ext]);
            dst = fullfile(userPath, [nm ext]);
            if isfile(src) && ~isfile(dst)
                movefile(src, dst);
                moved{end+1} = [nm ext]; %#ok<AGROW>
            end
            if isfile(dst) && ~strcmp(char(prefs.custom_chanlocs{i}{2}), dst)
                prefs.custom_chanlocs{i}{2} = dst;
                changed = true;
            end
        end
    end
    if changed, save(prefsFile, 'prefs'); end
end
if ~isempty(moved)
    fprintf('BIPATE: moved your personal files to %s (%s)\n', userPath, strjoin(moved, ', '));
end
end
