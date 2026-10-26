function queue = queueRemove(queue, idx)
% Author: James Barlow
% Created: 10/15/2026
% Last updated: 10/18/2026

% Removes files from the queue

% IN:   queue - structure containing queue
%       idx - either a logical [1 x numel(queue)] (true = remove) or numeric indices of entries to remove

% OUT: queue - the trimmed queue

arguments
    queue struct
    idx {mustBeNumericOrLogical}
end

if isempty(idx), return; end   % nothing selected

if ~islogical(idx) && (~isnumeric(idx) || any(idx <= 0))
    error("Given index is not a logical structure or proper index")
elseif ~isvector(idx)
    error("Index must be a vector i.e. n x 1")
elseif islogical(idx) && numel(idx) ~= numel(queue)
    error("Logical index must have the same number of values as the the number of entries in the queue")
elseif ~islogical(idx) && max(idx) > numel(queue)
    error("Indexing contains values outside of the bounds of the queue")
end

% logical and numeric both work directly as deletion indices
queue(idx) = [];
