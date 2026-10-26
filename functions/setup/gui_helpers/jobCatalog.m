function catalog = jobCatalog(catFile)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Loads the list of jobs the batch app can run from jobs.json (next to this file) and checks it.
% Adding or changing a job means editing jobs.json, not code.

% IN:   catFile = (optional) path to a catalog .json; default is jobs.json in this folder

% OUT:  catalog = struct array, one element per job, in file order
%           id = unique key, stored in bipate's obj.jobs (e.g. 'filter')
%           label = text shown in the job lists
%           fn = step function name; handle = function handle to it
%           inputs = what the step takes first, from {'EEG', 'cfg'}
%           args = extra arguments passed after the inputs
%           outputs = what the step returns, from {'EEG', 'cfg', 'ExG'} (can be empty)
%           provides = tags the step writes to EEG.etc.processing_done
%           requires = tags that must be done first (the job is blocked without them)
%           recommends = tags that should be done first (warning only)
%           interactive = true if the step opens its own windows
%           shareable = true if its dialog answers can be reused for every file (batchShared); optional, default false
%           description = one-line summary shown in the app
%           settings = 1 x n cell of the job's settings for the Settings window (optional): each has key (cfg
%               field, e.g. 'filter.highpass'), label, type (number, numbers, text, folder, choice, multichoice,
%               logical) and, for choices, options (a list, or "cfg:<key>" to take them from a cfg field)

arguments
    catFile {mustBeTextScalar} = ''
end

if nargin < 1 || isempty(catFile)
    catFile = fullfile(fileparts(mfilename('fullpath')), 'jobs.json');
end
if ~isfile(catFile)
    error('Job catalog not found: %s', catFile);
end
try
    raw = jsondecode(fileread(catFile));
catch ME
    error('Job catalog %s is not valid JSON: %s', catFile, ME.message);
end
% jsondecode gives a cell array when the entries do not all have the same fields
if ~iscell(raw)
    raw = num2cell(raw);
end

needFields = {'id', 'label', 'fn', 'inputs', 'args', 'outputs', 'provides', 'requires', 'recommends', ...
    'interactive', 'description'};
listFields = {'inputs', 'args', 'outputs', 'provides', 'requires', 'recommends'};

catalog = struct([]);
for k = 1:numel(raw)
    job = raw{k};
    missing = setdiff(needFields, fieldnames(job));
    if ~isempty(missing)
        error('Job %d in %s is missing field(s): %s', k, catFile, strjoin(missing, ', '));
    end
    if ~isfield(job, 'shareable')
        job.shareable = false;
    end
    if ~isfield(job, 'settings') || isempty(job.settings)
        job.settings = {};
    elseif isstruct(job.settings)
        job.settings = num2cell(job.settings(:)');   % 1 x n cell of setting structs
    end
    for f = 1:numel(listFields)
        job.(listFields{f}) = asList(job.(listFields{f}));
    end
    job.id = char(job.id);
    job.label = char(job.label);
    job.fn = char(job.fn);
    job.description = char(job.description);
    job.interactive = logical(job.interactive);
    job.shareable = logical(job.shareable);

    % the step function must be on the path (2 = .m file, 3 = MEX, 5 or 6 = built-in or p-code)
    if ~ismember(exist(job.fn), [2 3 5 6]) %#ok<EXIST>
        error('Job "%s": function %s is not on the MATLAB path', job.id, job.fn);
    end
    badInputs = setdiff(job.inputs, {'EEG', 'cfg'});
    if ~isempty(badInputs)
        error('Job "%s": unknown input(s) %s (use EEG or cfg)', job.id, strjoin(badInputs, ', '));
    end
    badOutputs = setdiff(job.outputs, {'EEG', 'cfg', 'ExG'});
    if ~isempty(badOutputs)
        error('Job "%s": unknown output(s) %s (use EEG, cfg or ExG)', job.id, strjoin(badOutputs, ', '));
    end
    job.handle = str2func(job.fn);
    job = orderfields(job);

    if isempty(catalog)
        catalog = job;
    else
        catalog(end+1, 1) = job; %#ok<AGROW>
    end
end

[~, firstIdx] = unique({catalog.id}, 'stable');
if numel(firstIdx) < numel(catalog)
    dupJob = catalog(setdiff(1:numel(catalog), firstIdx));
    error('Job id "%s" appears more than once in %s', dupJob(1).id, catFile);
end
end


function list = asList(value)
% jsondecode gives [] , 'a' or {'a';'b'} for a list; this always returns a 1 x n cell
if isempty(value)
    list = {};
elseif ischar(value) || isstring(value)
    list = cellstr(value);
    list = list(:)';
elseif iscell(value)
    list = value(:)';
else
    list = num2cell(value(:)');
end
end
