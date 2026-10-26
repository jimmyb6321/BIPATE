function pipes = pipelineStore(action, varPath, custom)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/25/2026

% The pipelines "Add pipeline" can use: the shipped default (pipeline.json, fixed) plus any number of named
% pipelines the user made in Settings > My Pipeline (BIPATE_user\userPreferences.mat, prefs.pipelines).
% A single saved order from before 22 Oct 2026 (prefs.pipeline) shows up as "My pipeline".

% IN:   action  = 'list' or 'save'
%       varPath = <userpath>\BIPATE_user (bipateUserDir)
%       custom  = ('save' only) struct array of the user's pipelines (.name, .jobs), the default left out

% OUT:  'list': pipes = struct array, default first: .name (char), .jobs (1 x n string of job ids),
%           .builtin (true for the default)
%       'save': pipes = [] (prefs.pipelines written, the old prefs.pipeline removed)

arguments
    action {mustBeMember(action, {'list', 'save'})}
    varPath {mustBeTextScalar}
    custom struct = struct('name', {}, 'jobs', {})
end

prefsFile = fullfile(varPath, 'userPreferences.mat');
prefs = struct();
if isfile(prefsFile)
    loaded = load(prefsFile);
    prefs = loaded.prefs;
end

if strcmp(action, 'save')
    prefs.pipelines = struct('name', {custom.name}, ...
        'jobs', cellfun(@(j) cellstr(string(j)), {custom.jobs}, 'UniformOutput', false));
    if isfield(prefs, 'pipeline'), prefs = rmfield(prefs, 'pipeline'); end
    save(prefsFile, 'prefs');
    pipes = [];
    return
end

% default, from pipeline.json next to jobCatalog
try
    defaultJobs = string(jsondecode(fileread(fullfile(fileparts(which('jobCatalog')), 'pipeline.json'))))';
catch
    defaultJobs = string({jobCatalog().id});
end
pipes = struct('name', 'Full pipeline (default)', 'jobs', defaultJobs, 'builtin', true);
if isfield(prefs, 'pipelines')
    for p = 1:numel(prefs.pipelines)
        pipes(end + 1) = struct('name', char(prefs.pipelines(p).name), ...
            'jobs', string(prefs.pipelines(p).jobs(:))', 'builtin', false); %#ok<AGROW>
    end
elseif isfield(prefs, 'pipeline') && ~isempty(prefs.pipeline)
    pipes(end + 1) = struct('name', 'My pipeline', 'jobs', string(prefs.pipeline(:))', 'builtin', false);
end
end
