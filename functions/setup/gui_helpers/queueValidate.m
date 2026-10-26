function queue = queueValidate(queue, cfg)

% Author: James Barlow
% Created: 10/15/2026
% Last updated: 10/18/2026

% Checks every entry against the blankEntry template (nested fields, both directions) and screens
% the timepoint descriptor and pptID for dates (PHI); rebuilds sessionID from pptID + timePoint
% and flags sets that would share a sessionID (same output folder). Validation failures start with "Validation:"
% and are re-checked on every run; file problems from deriveEntry are left as they are.

% IN:   queue - 1 x n queue struct array
%       cfg - configuration struct (needed to build the template)

% OUT:  queue - validated queue; entries that fail get state.status = 'failed' and a state.message


arguments
    queue struct
    cfg (1,1) struct
end

qc = blankEntry(cfg);
blankPath = findFields(qc, "");

for ii = 1:numel(queue)
    % file problems found when the set was added (deriveEntry) stay failed; validation results are redone
    if strcmp(queue(ii).state.status, 'failed') && ~startsWith(queue(ii).state.message, 'Validation:')
        continue;
    end
    if strcmp(queue(ii).state.status, 'failed')
        queue(ii).state.status = 'queued';  queue(ii).state.message = '';
    end

    % field check: every template field present, no extra fields
    qPath = findFields(queue(ii), "");
    missing = setdiff(blankPath, qPath);
    extra = setdiff(qPath, blankPath);
    if ~isempty(missing) || ~isempty(extra)
        queue(ii).state.status = 'failed';
        queue(ii).state.message = sprintf('Validation: field mismatch with blankEntry template (missing: %s | extra: %s)', ...
            strjoin(missing, ', '), strjoin(extra, ', '));
        continue;   % the fields below might not exist
    end

    % PHI screen on what ends up in filenames
    % timepoint: a date-like descriptor is dropped if the user says No (the set still runs)
    tp = strtrim(char(string(queue(ii).identity.timePoint)));
    [tf, hit] = looksLikeDate(tp);
    if tf
        dateWarn = questdlg(sprintf(['The timepoint descriptor "%s" contains "%s", which looks like a date.' ...
            newline newline 'Dates in filenames may count as PHI. Use it anyway?'], tp, hit), ...
            'Possible PHI', 'Yes', 'No', 'No');
        if ~strcmpi(dateWarn, 'Yes'), tp = ''; end
    end

    % pptID: a date-like ID must be confirmed or replaced (the replacement is screened too);
    % Cancel leaves the set out of the run
    ppt = strtrim(char(string(queue(ii).identity.pptID)));
    failMsg = '';
    [tf, hit] = looksLikeDate(ppt);
    while tf
        dateWarn = questdlg(sprintf(['The pptID "%s" contains "%s", which looks like a date.' ...
            newline newline 'Dates in filenames may count as PHI. Use it anyway?'], ppt, hit), ...
            'Possible PHI', 'Yes', 'No', 'No');
        if strcmpi(dateWarn, 'Yes'), break; end
        answer = inputdlg(sprintf('New participant ID for %s', queue(ii).identity.fileName), 'New pptID', [1 40], {''});
        if isempty(answer)                                   % Cancel
            failMsg = 'Validation: pptID looks like a date and no replacement was given';
            break;
        end
        ppt = strtrim(answer{1});
        [tf, hit] = looksLikeDate(ppt);
    end
    if isempty(failMsg) && isempty(ppt)
        failMsg = 'Validation: pptID is empty (it names every output folder and file)';
    end
    if ~isempty(failMsg)
        queue(ii).state.status = 'failed';
        queue(ii).state.message = failMsg;
        continue;
    end
    queue(ii).identity.timePoint = tp;
    queue(ii).identity.pptID = ppt;

    % sessionID is derived, same rule as launch_pipeline: pptID, or pptID_timepoint
    if isempty(tp)
        queue(ii).identity.sessionID = ppt;
    else
        queue(ii).identity.sessionID = [ppt '_' tp];
    end
end

% two sets with the same sessionID would write into the same folder and overwrite each other:
% the later ones are flagged
ok = find(~arrayfun(@(e) strcmp(e.state.status, 'failed'), queue));
sids = arrayfun(@(e) string(e.identity.sessionID), queue(ok));
for k = 2:numel(ok)
    firstSame = find(sids(1:k-1) == sids(k), 1);
    if ~isempty(firstSame)
        queue(ok(k)).state.status = 'failed';
        queue(ok(k)).state.message = sprintf(['Validation: same session ID "%s" as %s; give one of them a ' ...
            'different pptID or time point'], sids(k), queue(ok(firstSame)).identity.fileName);
    end
end

end


function pather = findFields(curStruct, parent)
% gives full list of terminal fields in a struct, as dotted paths ('identity.pptID')
% IN:   curStruct - structure to iterate over
%       parent - dotted path of curStruct ("" at the top)

% OUT:  pather - cell of terminal field paths (char)
    pather = {};

    if isstruct(curStruct)
        fields = fieldnames(curStruct);

        for i = 1:numel(fields)
            fName = fields{i};

            if strcmpi(parent, "")
                cPath = fName;
            else
                cPath = char(parent + "." + fName);
            end

            if isstruct(curStruct(1).(fName))
                pather = [pather, findFields(curStruct(1).(fName), cPath)]; %#ok<AGROW> % nested: add its leaves
            else
                pather{end+1} = cPath; %#ok<AGROW>                               % leaf
            end
        end
    end
end
