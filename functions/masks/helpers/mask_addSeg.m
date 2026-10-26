function EEG = mask_addSeg(EEG, ranges, source)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Marks continuous samples as bad and records which step flagged them

% IN:   EEG = continuous EEGLAB struct
%       ranges = sample indices, or a logical [1 x pnts] where true = remove
%       source = name of the flagging step (becomes a field name)

% OUT:  EEG = EEG struct with
%           EEG.masks.seg.keepMask(ranges) = false
%           EEG.masks.seg.source.(source) = sorted column of sample indices this step flagged
arguments
    EEG (1,1) struct
    ranges {mustBeNumericOrLogical}
    source {mustBeTextScalar}
end

EEG = mask_init(EEG);
if islogical(ranges), ranges = find(ranges); end

EEG.masks.seg.keepMask(ranges) = false;


ranges = ranges(:);

if ~isfield(EEG.masks.seg, 'source')
    EEG.masks.seg.source.(source) = ranges;
else
    if ~isfield(EEG.masks.seg.source, (source))
        EEG.masks.seg.source.(source) = ranges;
    else
        % append to this source's existing list (forced to a column)
        fixVert = EEG.masks.seg.source.(source);
        EEG.masks.seg.source.(source) = fixVert(:);
        EEG.masks.seg.source.(source) = [EEG.masks.seg.source.(source); ranges];
        EEG.masks.seg.source.(source) = sort(EEG.masks.seg.source.(source), "ascend");
    end
end