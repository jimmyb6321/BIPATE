function EEG = loadData_max(cfg_full)

% Author: James Barlow
% Created: 05/04/2026
% Last updated: 10/25/2026

% Loads a recording (.mff folder, .set, .edf, .eeg/.vhdr, .nxe) or a resume file, starts the processing log,
% and saves it as the raw .set

% IN:   cfg_full = configuration struct (recording.input_format, paths.data_in/data_out, sessionID, pptID;
%       paths.inputFile may hold several .mff paths joined by "|": they are joined into one set, see joinMffs;
%           resumeFile/resumePath when resuming; paths.inputFile from the batch app = load that file, no picker)

% OUT:  EEG = loaded EEGLAB struct
%           EEG.etc.sample_map_original = (1:pnts)' original sample index
%           EEG.etc.processing_done/log started with 'loadData'
%           (a .set that already has 'loadData' keeps its processing_done/log and sample_map_original)
%           EEG.etc.mffFolder = source folder (.mff only)

% TODO: test .nxe (Nexstim) through pop_fileio; add a session selection box
arguments
    cfg_full (1,1) struct
end

if isfield(cfg_full, 'resumeFile')
    EEG = pop_loadset('filename', cfg_full.resumeFile, 'filepath', cfg_full.resumePath);
else
    mffYes = "No";
    
    % batch app (bipate): the file was chosen when the set was added, so no picker
    inFile = '';
    if isfield(cfg_full.paths, 'inputFile'), inFile = char(cfg_full.paths.inputFile); end
    if ~isempty(inFile)
        [~, ~, ext] = fileparts(inFile);
        switch lower(ext)
            case '.mff'
                if contains(inFile, '|')   % several recordings joined into one set (bipate Add set)
                    EEG = joinMffs(strtrim(strsplit(inFile, '|')));
                else
                    EEG = pop_mffimport(inFile, {'code'});
                    EEG.etc.mffFolder = inFile;
                end
                EEG.filename = '';        % set by pop_saveset
                EEG.filepath = '';
            case '.set', EEG = pop_loadset(inFile);
            case '.edf', EEG = pop_biosig(inFile);
            case '.eeg', EEG = pop_fileio(strrep(inFile, '.eeg', '.vhdr'));   % BrainVision: load through the .vhdr
            case '.nxe', EEG = pop_fileio(inFile);
            otherwise, error('Unsupported file type %s (%s)', ext, inFile);
        end
    else
    if strcmpi(cfg_full.recording.input_format, 'auto')
         mffYes = questdlg('Is your file a .mff?', '', "Yes", "No", "No");
    end
    
    if strcmpi(cfg_full.recording.input_format, ".mff") || mffYes == "Yes" %.mff is a folder, not a file
        filepath = uigetdir(cfg_full.paths.data_in, 'Select .mff folder');
        if isequal(filepath, 0), error('No folder seleceted') ;end

        EEG = pop_mffimport(filepath, {'code'});
        EEG.filename = '';        % set by pop_saveset
        EEG.filepath = '';        % set by pop_saveset  
        EEG.etc.mffFolder = filepath;
    
    elseif strcmpi(cfg_full.recording.input_format, "Auto") %any supported file, loader picked by extension
        [filename, filepath] = uigetfile({'*.eeg;*.set;*.edf;*.nxe', 'EEG Files'}, "Pick EEG file to process", cfg_full.paths.data_in);
        if isequal(filename, 0), error('No file selected.');end
    
        [~, ~, ext] = fileparts(filename);
    
        switch ext
            case ".set"
                EEG = pop_loadset(fullfile(filepath, filename));
            case ".eeg"
                EEG = pop_fileio(fullfile(filepath, strrep(filename, '.eeg', '.vhdr')));
            case ".edf"
                EEG = pop_biosig(fullfile(filepath, filename));
            case ".nxe"
                EEG = pop_fileio(fullfile(filepath, filename));
        end
    elseif strcmpi(cfg_full.recording.input_format, ".set")
        [filename, filepath] = uigetfile('*.set', "Pick EEG file to process", cfg_full.paths.data_in);
        EEG = pop_loadset(fullfile(filepath, filename));
    elseif strcmpi(cfg_full.recording.input_format, ".edf")
        [filename, filepath] = uigetfile('*.edf', "Pick EEG file to process", cfg_full.paths.data_in);
        EEG = pop_biosig(fullfile(filepath, filename));
    elseif strcmpi(cfg_full.recording.input_format, ".eeg") %BrainVision: load through the .vhdr
        [filename, filepath] = uigetfile('*.eeg', "Pick EEG file to process", cfg_full.paths.data_in);
        EEG = pop_fileio(fullfile(filepath, strrep(filename, '.eeg', '.vhdr')));
    elseif strcmpi(cfg_full.recording.input_format, ".nxe")
        [filename, filepath] = uigetfile('*.nxe', "Pick EEG file to process", cfg_full.paths.data_in);
        EEG = pop_fileio(fullfile(filepath, filename));
        
    end
    end
    
    % events: EDF+ annotations pop_biosig skipped, and the "empty" placeholder events some readers add
    srcFile = inFile;
    if isempty(srcFile) && exist('filename', 'var') && exist('filepath', 'var') && ischar(filename)
        srcFile = fullfile(filepath, filename);
    end
    EEG = tidyEvents(EEG, srcFile);
    EEG = findMff(EEG, srcFile);   % a linked .mff given relative to the .set, or moved next to it

    % identity + processing log
    EEG.setname  = char(cfg_full.sessionID);
    EEG.subject  = char(cfg_full.pptID);
    EEG.session  = 1;
    reloaded = isfield(EEG.etc, 'processing_done') && any(strcmp(cellstr(string(EEG.etc.processing_done)), 'loadData'));
    if reloaded
        % a .set BIPATE already processed: loadData never runs twice, so its history, processing log and
        % original sample map are kept (bipate's job plan already counts those jobs as done)
        EEG.etc.processing_log{end+1} = sprintf('Reloaded as %s from %s: %s', char(cfg_full.sessionID), ...
            fullfile(EEG.filepath, EEG.filename), string(datetime('now')));
    else
        EEG.comments = sprintf('Loaded from %s on %s', char(cfg_full.paths.data_in), string(datetime('now')));
        EEG.etc.sample_map_original = (1:EEG.pnts)';
        EEG.etc.processing_done = {};
        EEG.etc.processing_log = {};
        EEG.etc.processing_done{end+1} = 'loadData';
        EEG.etc.processing_log{end+1} = sprintf('Step 01 load Data to .set format (BIPATE %s): %s', bipateVersion(), string(datetime('now')));
        if isfield(EEG.etc, 'mffJoinNote'), EEG.etc.processing_log{end+1} = EEG.etc.mffJoinNote; end
    end
    if isfield(cfg_full, 'user'), EEG = stampUser(EEG, cfg_full.user); end   % EEG.etc.processed_by
    EEG.etc.bipate_version = bipateVersion();   % the version that made this set (saveStep keeps it current)
    
    savePath = fullfile(cfg_full.paths.data_out);
    EEG = pop_saveset(EEG, 'filename', [char(cfg_full.sessionID) '_raw.set'], 'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
end

notifyDone('Data load');



end

% IN:  EEG = just-loaded EEGLAB struct; srcFile = the file it came from (char, may be empty)
% OUT: EEG with (1) EDF+ annotations as events when the reader brought none (pop_biosig skips them;
%      read with MATLAB's edfread, Signal Processing Toolbox) and (2) "empty"-type events removed (the
%      BrainVision New Segment marker and EDF data-record markers come in with that type)
function EEG = tidyEvents(EEG, srcFile)
[~, ~, ext] = fileparts(char(srcFile));
if strcmpi(ext, '.edf') && isempty(EEG.event) && exist('edfread', 'file')
    try
        [~, ann] = edfread(srcFile);
        for k = 1:height(ann)
            EEG.event(k).type = char(string(ann.Annotations(k)));
            EEG.event(k).latency = seconds(ann.Properties.RowTimes(k)) * EEG.srate + 1;
            EEG.event(k).duration = seconds(ann.Duration(k)) * EEG.srate;
        end
        if height(ann) > 0
            fprintf('Load data: %d EDF+ annotation(s) added as events.\n', height(ann));
        end
    catch ME
        warning('Could not read EDF+ annotations from %s: %s', srcFile, ME.message);
    end
end
if ~isempty(EEG.event)
    isEmptyType = cellfun(@(t) strcmpi(char(string(t)), 'empty'), {EEG.event.type});
    EEG.event(isEmptyType) = [];
end
EEG = eeg_checkset(EEG, 'eventconsistency');
end

% IN:  EEG = just-loaded set; srcFile = the file it came from
% OUT: EEG.etc.mffFolder made a full path when it is stored relative to the .set (e.g. the demo in testData),
%      or when the .mff it names is not where it was but a folder of that name sits next to the .set
function EEG = findMff(EEG, srcFile)
if ~isfield(EEG.etc, 'mffFolder') || isempty(EEG.etc.mffFolder) || isfolder(EEG.etc.mffFolder), return; end
[~, name, ext] = fileparts(char(EEG.etc.mffFolder));
here = fileparts(char(srcFile));
cands = {fullfile(here, char(EEG.etc.mffFolder)), fullfile(here, [name ext])};
for c = 1:numel(cands)
    if isfolder(cands{c})
        EEG.etc.mffFolder = cands{c};
        return
    end
end
end

% IN:  parts = cellstr of .mff folders from one session (any order)
% OUT: EEG = the recordings joined end to end in recording order (info.xml recordTime), with a boundary event
%      at each join; the time between recordings is not kept as data. Every part must have the same channels
%      and sampling rate.
%          EEG.etc.mffFolder = the first recording (recording start, video sync)
%          EEG.etc.mffFolders = all recordings in order
%          EEG.etc.mffPartStartSec = where each recording starts in the joined data (s; first = 0)
%          EEG.etc.mffPartRecordTime = each recording's wall-clock start (cellstr)
%          EEG.etc.mffJoinNote = one line for the processing log (gaps between recordings)
function EEG = joinMffs(parts)
n = numel(parts);
recs = cell(1, n);
starts = NaT(1, n, 'TimeZone', 'local');
for k = 1:n
    recs{k} = pop_mffimport(parts{k}, {'code'});
    info = fileread(fullfile(parts{k}, 'info.xml'));
    tok = regexp(info, '<recordTime>(.*?)</recordTime>', 'tokens', 'once');
    starts(k) = datetime(tok{1}, 'InputFormat', 'yyyy-MM-dd''T''HH:mm:ss.SSSSSSZ', 'TimeZone', 'local');
end
[starts, order] = sort(starts);
parts = parts(order);
recs = recs(order);
for k = 2:n
    if recs{k}.srate ~= recs{1}.srate || ~isequal({recs{k}.chanlocs.labels}, {recs{1}.chanlocs.labels})
        error('Cannot join %s to %s: different channels or sampling rate.', parts{k}, parts{1});
    end
end
partStart = zeros(1, n);   % samples before each recording
EEG = recs{1};
firstEtc = EEG.etc;
gapText = {};
for k = 2:n
    partStart(k) = EEG.pnts;
    EEG = pop_mergeset(EEG, recs{k}, 0);   % appends, with a boundary event at the join
    gapMin = minutes(starts(k) - (starts(k - 1) + seconds(recs{k - 1}.pnts / recs{k - 1}.srate)));
    gapText{end + 1} = sprintf('%s after a %.1f min gap', char(string(starts(k), 'HH:mm:ss')), gapMin); %#ok<AGROW>
end
EEG.etc = firstEtc;
EEG.etc.mffFolder = parts{1};
EEG.etc.mffFolders = parts;
EEG.etc.mffPartStartSec = partStart / EEG.srate;
EEG.etc.mffPartRecordTime = cellstr(string(starts, 'yyyy-MM-dd HH:mm:ss'));
EEG.etc.mffJoinNote = sprintf('Joined %d .mff recordings in recording order (first at %s; then %s)', n, ...
    char(string(starts(1), 'HH:mm:ss')), strjoin(gapText, '; '));
fprintf('Load data: %s\n', EEG.etc.mffJoinNote);
end
