function inBatch = isBatchRun()

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% True while bipate is running a batch (bipate sets appdata 'bipateBatch' on the root for the length of the
% run). Steps use it to stay quiet: QC figures are drawn hidden, saved and closed, and notifyDone waits for
% the end of the batch.

% IN:   none
% OUT:  inBatch = logical scalar

inBatch = isappdata(0, 'bipateBatch') && isequal(getappdata(0, 'bipateBatch'), true);
end
