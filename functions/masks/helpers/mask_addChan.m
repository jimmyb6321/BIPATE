function EEG = mask_addChan(EEG, badIdx, source)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Marks channels as bad and records which step flagged them

% IN:   EEG = EEGLAB struct
%       badIdx = channel indices to mark bad
%       source = name of the flagging step (becomes a field name)

% OUT:  EEG = EEG struct with
%           EEG.masks.chan.keepMask(badIdx) = false
%           EEG.masks.chan.source.(source) = sorted column of channel indices this step flagged
arguments
    EEG (1,1) struct
    badIdx {mustBeNumericOrLogical}
    source {mustBeTextScalar}
end

EEG = mask_init(EEG);
EEG.masks.chan.keepMask(badIdx) = false;


if ~isfield(EEG.masks.chan, 'source')
    EEG.masks.chan.source.(source) = badIdx(:);
else
    if ~isfield(EEG.masks.chan.source, (source))
        EEG.masks.chan.source.(source) = badIdx(:);
    else
        % append to this source's existing list (forced to a column)
        fixVert = EEG.masks.chan.source.(source);
        EEG.masks.chan.source.(source) = fixVert(:);
        EEG.masks.chan.source.(source) = [EEG.masks.chan.source.(source); badIdx];
        EEG.masks.chan.source.(source) = sort(EEG.masks.chan.source.(source), 1, "ascend");
    end
end