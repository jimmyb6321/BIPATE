function checkPrerequisites(EEG, requiredSteps, recommendedSteps)

% Author: James Barlow
% Created: 05/12/2026
% Last updated: 10/18/2026

% Checks EEG.etc.processing_done for earlier steps: errors on a missing required step, warns on a missing
% recommended one. The usual call names the step's job id, and the requirements are read from jobs.json
% (the same list bipate's job plan uses), so there is one place to change them:
%     checkPrerequisites(EEG, 'filter')
% The older form with explicit lists still works:
%     checkPrerequisites(EEG, {'chanSetup'}, {'filter'})

% IN:   EEG = EEGLAB struct (EEG.etc.processing_done)
%       requiredSteps = job id from jobs.json (char/string), or a cell of tags that must be done
%       recommendedSteps = (optional, cell form only) cell of tags that should be done

% OUT:  none (error or warning)

arguments
    EEG (1,1) struct
    requiredSteps = {}
    recommendedSteps cell = {}
end

done = {};
if isfield(EEG, 'etc') && isfield(EEG.etc, 'processing_done')
    done = EEG.etc.processing_done;
end

% job id: requirements from jobs.json, checked the way the job plan checks them
if ischar(requiredSteps) || (isstring(requiredSteps) && isscalar(requiredSteps))
    plan = jobPlan(string(requiredSteps), jobCatalog, done);
    if plan.action == "blocked"
        error('Cannot run %s: it %s (see jobs.json).', plan.label, plan.why);
    end
    if ~isempty(plan.missingRec)
        warning('%s: recommended earlier step(s) not done: %s', plan.label, strjoin(string(plan.missingRec), ', '));
    end
    return
end

for s = requiredSteps
    if ~any(strcmpi(done, s{1}))
        error('Required prior step missing: %s', s{1});
    end
end
for s = recommendedSteps
    if ~any(strcmpi(done, s{1}))
        warning('Recommended prior step missing: %s', s{1});
    end
end
end
