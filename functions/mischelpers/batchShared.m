function out = batchShared(action, value)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Lets a batch reuse a step's dialog answers for every file. When the job plan's "same settings for
% all files" box is ticked for a job, the batch app (bipate) turns sharing on while that job runs.
% The step function asks its questions on the first file, saves the answers here, and every later
% file gets the same answers without the dialog.
% Outside a batch, or when sharing is off for the job, 'get' returns [] and 'set' does nothing, so
% the step function always shows its dialogs.

% Use in a step function:
%   answer = batchShared('get');
%   if isempty(answer)
%       answer = inputdlg(...);
%       batchShared('set', answer);
%   end

% IN:   action = one of
%           'get'           returns the saved answers for the running job, or []
%           'set', value    saves the answers for the running job (ignored when sharing is off or value is empty)
%           'start', key    bipate: sharing on for the job about to run (key = job position, e.g. 'filter_6')
%           'stop'          bipate: sharing off after the job
%           'clear'         bipate: forget every saved answer (end of a batch)

% OUT:  out = saved answers for 'get' ([] if none); [] for the other actions

arguments
    action {mustBeTextScalar}
    value = []
end

out = [];
store = getappdata(0, 'bipateShared');
if isempty(store)
    store = struct('activeKey', '', 'answers', struct());
end

switch lower(action)
    case 'get'
        if ~isempty(store.activeKey) && isfield(store.answers, store.activeKey)
            out = store.answers.(store.activeKey);
        end
    case 'set'
        if ~isempty(store.activeKey) && ~isempty(value)
            store.answers.(store.activeKey) = value;
        end
    case 'start'
        store.activeKey = matlab.lang.makeValidName(char(value));
    case 'stop'
        store.activeKey = '';
    case 'clear'
        store = struct('activeKey', '', 'answers', struct());
    otherwise
        error('batchShared: unknown action "%s" (use get, set, start, stop or clear)', action);
end
setappdata(0, 'bipateShared', store);
end
