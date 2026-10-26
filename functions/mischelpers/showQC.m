function tf = showQC()

% Author: James Barlow
% Created: 10/25/2026
% Last updated: 10/25/2026

% Whether a QC figure should open on screen now (it is always drawn and saved either way), from
% Settings > Misc "Open QC figures":
%   Never                 = never open
%   After every job       = always open, also during batches
%   Single-set runs only  = open when a step runs on its own, or in a batch of one set (default)
%   Single-job runs only  = open when a step runs on its own, or in a batch with one job
% bipate sets appdata 'bipateBatchSize' = [nSets nJobs] for the length of a batch. Older on/off settings
% still work (true = Single-set runs only, false = Never).

% IN:   none
% OUT:  tf = logical scalar

mode = appSetting('misc.showQC', 'Single-set runs only');
if islogical(mode) || isnumeric(mode)   % saved by the old on/off box
    if mode, mode = 'Single-set runs only'; else, mode = 'Never'; end
end
mode = char(string(mode));
if strcmp(mode, 'Never')
    tf = false;
    return
end
if ~isBatchRun()   % a step run on its own
    tf = true;
    return
end
batchSize = [Inf Inf];
if isappdata(0, 'bipateBatchSize'), batchSize = getappdata(0, 'bipateBatchSize'); end
switch mode
    case 'After every job',      tf = true;
    case 'Single-set runs only', tf = batchSize(1) == 1;
    case 'Single-job runs only', tf = batchSize(2) == 1;
    otherwise,                   tf = false;
end
end
