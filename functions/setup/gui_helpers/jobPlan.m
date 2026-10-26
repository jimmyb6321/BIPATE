function plan = jobPlan(jobIds, catalog, alreadyDone, jobOn, nFinished)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Checks the chosen jobs for one set, in the order given, without running anything. Every job can run
% any number of times (each run is numbered by stepRound), so a job only stays off because the user
% unticked it in the job plan, or is blocked because something it needs is not done.
% A tag counts as done if it was done before the batch or an earlier job that will run provides it.
% Tags ignore case, round numbers and "(...)" notes, so 'filter2' and 'resample (skipped)' count as
% 'filter' and 'resample'. In jobs.json a tag ending in * matches anything that starts the same way,
% and a requirement can list alternatives with | (reref|preICAreref).

% IN:   jobIds = job ids in run order (bipate's obj.jobs)
%       catalog = struct array from jobCatalog
%       alreadyDone = cellstr of tags already on this set (EEG.etc.processing_done)
%       jobOn = logical, one per job, false = unticked in the job plan (default all true)
%       nFinished = how many of these jobs this run already finished on the set; they are not run
%           again when the run is continued (default 0)

% OUT:  plan = struct array, one row per job
%           id, label = from the catalog
%           action = "run", "off", "done" (finished earlier in this run) or "blocked"
%           why = reason for a block ("" otherwise)
%           missingRec = recommended tags that are not done yet (warning only)

arguments
    jobIds {mustBeText}
    catalog struct
    alreadyDone = {}
    jobOn {mustBeNumericOrLogical} = []
    nFinished (1,1) {mustBeNonnegative} = 0
end

jobIds = cellstr(string(jobIds));
if nargin < 4 || isempty(jobOn)
    jobOn = true(1, numel(jobIds));
end
if nargin < 5
    nFinished = 0;
end
haveTags = cleanTags(alreadyDone);

plan = struct('id', {}, 'label', {}, 'action', {}, 'why', {}, 'missingRec', {});
for k = 1:numel(jobIds)
    inCatalog = strcmp({catalog.id}, jobIds{k});
    if ~any(inCatalog)
        plan(k).id = jobIds{k};
        plan(k).label = jobIds{k};
        plan(k).action = "blocked";
        plan(k).why = "not in the job catalog";
        plan(k).missingRec = {};
        continue
    end
    job = catalog(inCatalog);
    plan(k).id = job.id;
    plan(k).label = job.label;
    plan(k).why = "";
    plan(k).missingRec = {};

    if k <= nFinished
        plan(k).action = "done";
    elseif ~jobOn(k)
        plan(k).action = "off";
    else
        missingReq = notDone(job.requires, haveTags);
        if isempty(missingReq)
            plan(k).action = "run";
            plan(k).missingRec = notDone(job.recommends, haveTags);
        else
            plan(k).action = "blocked";
            plan(k).why = "needs " + strjoin(string(missingReq), ", ");
        end
    end

    if plan(k).action == "run" || plan(k).action == "done"
        haveTags = union(haveTags, cleanTags(job.provides));
    end
end
end


function missing = notDone(needTags, haveTags)
% the tags in needTags (as written in jobs.json) that nothing in haveTags satisfies
missing = {};
for n = 1:numel(needTags)
    options = cleanTags(strsplit(char(needTags{n}), '|'));
    if ~any(cellfun(@(opt) tagDone(opt, haveTags), options))
        missing{end+1} = needTags{n}; %#ok<AGROW>
    end
end
end


function found = tagDone(tag, haveTags)
% true if tag is in haveTags; a * at the end of either one matches anything after it
found = false;
for h = 1:numel(haveTags)
    have = haveTags{h};
    if strcmp(tag, have)
        found = true;
    elseif endsWith(tag, '*') && startsWith(have, tag(1:end-1))
        found = true;
    elseif endsWith(have, '*') && startsWith(tag, have(1:end-1))
        found = true;
    end
    if found
        return
    end
end
end


function tags = cleanTags(tags)
% lower case, without "(...)" notes, round numbers at the end, outer spaces, or empty tags
tags = cellstr(string(tags));
tags = regexprep(tags, '\s*\(.*?\)', '');
tags = regexprep(strtrim(tags), '\d+$', '');
tags = lower(tags);
tags = tags(~cellfun(@isempty, tags));
tags = tags(:)';
end
