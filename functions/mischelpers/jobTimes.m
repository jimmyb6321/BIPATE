function out = jobTimes(action, jobId, seconds, dataSize)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/25/2026

% Remembers how long each job took, so the BIPATE status window can estimate the time left.
% A job's time is stored per channel x sample (x trial) of the data it got, so a 30-minute test set
% and a 7-hour recording can share one record. Kept in BIPATE_user\jobTimes.mat (per computer,
% not in git); the last 20 runs of each job are kept and the median is used.

% IN:   action   = 'add'  -> also give jobId, seconds (wall time of the run), dataSize (nbchan*pnts*trials)
%                  'rate' -> give jobId
%       jobId    = job id from jobs.json (char/string)

% OUT:  'add'  : out = [] (nothing)
%       'rate' : out = median seconds per channel x sample for that job, NaN if it has never run here

arguments
    action {mustBeMember(action, {'add', 'rate'})}
    jobId {mustBeTextScalar}
    seconds (1,1) double = NaN
    dataSize (1,1) double = 0
end

persistent times timesFile   % times.(jobId) = [seconds, dataSize] rows, newest last
if isempty(timesFile)
        timesFile = fullfile(bipateUserDir(), 'jobTimes.mat');
    times = struct();
    if isfile(timesFile)
        loaded = load(timesFile, 'times');
        times = loaded.times;
    end
end
field = matlab.lang.makeValidName(char(jobId));
out = [];

switch action
    case 'add'
        if isnan(seconds) || dataSize <= 0
            return   % nothing to scale by (e.g. Load data before any data exists)
        end
        if ~isfield(times, field), times.(field) = zeros(0, 2); end
        times.(field)(end+1, :) = [seconds, dataSize];
        times.(field) = times.(field)(max(1, end-19):end, :);   % keep the last 20 runs
        try
            save(timesFile, 'times');
        catch ME
            warning('jobTimes:save', 'Could not save job times: %s', ME.message);
        end
    case 'rate'
        out = NaN;
        if isfield(times, field) && ~isempty(times.(field))
            rows = times.(field);
            out = median(rows(:, 1) ./ rows(:, 2));
        end
end
end
