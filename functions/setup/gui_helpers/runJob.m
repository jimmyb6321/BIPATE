function [EEG, cfg_full] = runJob(job, EEG, cfg_full)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Calls one catalog job with the inputs and outputs its jobs.json entry lists, so every step can be run
% the same way even though their signatures differ (e.g. loadData_max(cfg), chanSetup returns cfg too,
% segmentRejection takes an extra 'data' / 'icaact', exportQC returns nothing).

% IN:   job      = one element of jobCatalog (uses .handle, .inputs, .args, .outputs)
%       EEG      = current EEGLAB struct ([] before the data is loaded)
%       cfg_full = this set's configuration (sessionCfg)

% OUT:  EEG      = EEG returned by the step (unchanged if the step returns no EEG)
%       cfg_full = cfg returned by the step (unchanged if it returns none); an ExG output is not kept
%                  (chanSplitter-style steps save it to disk themselves)

% inputs in the order the catalog lists them, then the extra arguments
arguments
    job (1,1) struct
    EEG
    cfg_full (1,1) struct
end

in = cell(1, numel(job.inputs));
for k = 1:numel(job.inputs)
    switch job.inputs{k}
        case 'EEG', in{k} = EEG;
        case 'cfg', in{k} = cfg_full;
    end
end
in = [in, job.args];

nOut = numel(job.outputs);
if nOut == 0
    job.handle(in{:});
    return
end
out = cell(1, nOut);
[out{:}] = job.handle(in{:});
for k = 1:nOut
    switch job.outputs{k}
        case 'EEG', EEG = out{k};
        case 'cfg', cfg_full = out{k};
        % 'ExG' (peripheral channels) is saved by the step itself and not carried through the batch
    end
end
end
