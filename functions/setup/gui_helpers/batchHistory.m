function out = batchHistory(action, histDir, varargin)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Batch history kept by the batch app (bipate). Every run writes two things to histDir
% (<userpath>\BIPATE_user\batch_history):
%   <id>.mat            = the full batch (sets, jobs, job plan, output folder), so it can be reloaded exactly
%   batch_history.json  = a list of every run, newest first, readable in any text editor
% The app rewrites a run's entry after every set, so a crash leaves the entry at status "running".

% IN:   action = 'list', 'save' or 'load'
%       histDir = history folder (created on the first save)
%       out = batchHistory('list', histDir)              -> entries, newest first ([] if none)
%             batchHistory('save', histDir, entry, batch) -> writes <entry.id>.mat and adds or replaces the entry
%       out = batchHistory('load', histDir, id)          -> the saved batch struct

% OUT:  entry fields:
%           id = run start as yyyyMMdd_HHmmss (also the .mat name)
%           name = the name given when the run was started
%           started = 'yyyy-MM-dd HH:mm'; finished = same format ('' while running)
%           status = 'running', 'finished' or 'stopped'
%           outRoot = output folder; jobs = job ids in run order
%           nSets, nDone, nFailed = counts
%           sets = struct array with file, sessionID, status, message (one per set)

arguments
    action {mustBeTextScalar}
    histDir {mustBeTextScalar}
end
arguments (Repeating)
    varargin
end

indexFile = fullfile(histDir, 'batch_history.json');
switch lower(action)
    case 'list'
        out = readIndex(indexFile);

    case 'save'
        entry = varargin{1};
        batch = varargin{2};
        if ~isfolder(histDir)
            mkdir(histDir);
        end
        save(fullfile(histDir, [entry.id '.mat']), 'batch');
        history = readIndex(indexFile);
        if ~isempty(history)
            history = history(~strcmp({history.id}, entry.id));
        end
        history = [entry; history(:)];
        history = history(1:min(end, 500));
        fileId = fopen(indexFile, 'w');
        if fileId < 0
            error('Cannot write %s', indexFile);
        end
        fwrite(fileId, jsonencode(history, 'PrettyPrint', true), 'char');
        fclose(fileId);

    case 'load'
        batchFile = fullfile(histDir, [char(varargin{1}) '.mat']);
        if ~isfile(batchFile)
            error('The saved batch %s is missing from %s', varargin{1}, histDir);
        end
        loaded = load(batchFile, 'batch');
        out = loaded.batch;

    otherwise
        error('batchHistory: unknown action "%s" (use list, save or load)', action);
end
end


function history = readIndex(indexFile)
% batch_history.json as a struct array with the same fields in every entry ([] if there is no file yet)
history = [];
if ~isfile(indexFile)
    return
end
raw = jsondecode(fileread(indexFile));
if isempty(raw)
    return
end
if iscell(raw)
    raw = raw(:);
else
    raw = num2cell(raw(:));
end
fields = {'id', 'name', 'started', 'finished', 'status', 'outRoot', 'jobs', 'nSets', 'nDone', 'nFailed', 'sets'};
textFields = {'id', 'name', 'started', 'finished', 'status', 'outRoot'};
for k = 1:numel(raw)
    entry = struct();
    for f = 1:numel(fields)
        if isfield(raw{k}, fields{f})
            entry.(fields{f}) = raw{k}.(fields{f});
        else
            entry.(fields{f}) = [];
        end
    end
    for f = 1:numel(textFields)
        entry.(textFields{f}) = char(entry.(textFields{f}));
    end
    entry.jobs = cellstr(string(entry.jobs));
    entry.jobs = entry.jobs(:)';
    if iscell(entry.sets)
        entry.sets = [entry.sets{:}];
    end
    if isempty(entry.sets)
        entry.sets = struct('file', {}, 'sessionID', {}, 'status', {}, 'message', {});
    end
    if isempty(history)
        history = entry;
    else
        history(end+1, 1) = entry; %#ok<AGROW>
    end
end
end
