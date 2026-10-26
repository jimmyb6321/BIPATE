function queue = queueAdd(queue, entry)
% Author: James Barlow
% Created: 10/15/2026
% Last updated: 10/18/2026

% Adds new entry to the queue after safety checks

% IN:   queue = full queue structure (1 x n struct array; 1 x 0 when empty, from blankEntry(cfg, true))
%       entry = entry to add to queue(end+1), built by blankEntry + deriveEntry

% OUT:  queue = queue returned with new entry (unchanged if it's a duplicate or the wrong shape)

% file paths already in the queue
arguments
    queue struct
    entry struct
end

yeps = {queue(:).identity};
fps = cell(numel(yeps), 1);
for q = 1:numel(yeps)
    nextSt = yeps{q};
    fps{q} = nextSt.filePath;
end

% duplicate file: exact path match
if ~isempty(queue) && ismember(entry.identity.filePath, fps)
    warning('File %s already added to the queue!', entry.identity.filePath);
    return;
end

% top-level shape check (nested fields are checked in queueValidate)
if ~isequal(sort(fieldnames(queue)), sort(fieldnames(entry)))
    warning("Entry for %s is not valid for the queue structure (field mismatch)", entry.identity.filePath);
    return;
end

queue(end+1) = entry;
