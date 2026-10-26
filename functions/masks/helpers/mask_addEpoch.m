function EEG = mask_addEpoch(EEG, removeEpochs, source)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Marks epochs as bad and records which step flagged them

% IN:   EEG = epoched EEGLAB struct
%       removeEpochs = epoch indices, or a logical [1 x trials] where true = remove
%       source = name of the flagging step (becomes a field name)

% OUT:  EEG = EEG struct with
%           EEG.masks.epoch.keepMask(removeEpochs) = false
%           EEG.masks.epoch.source.(source) = sorted column of epoch indices this step flagged
arguments
    EEG (1,1) struct
    removeEpochs {mustBeNumericOrLogical}
    source {mustBeTextScalar}
end

EEG = mask_init(EEG);
if islogical(removeEpochs), removeEpochs = find(removeEpochs); end

EEG.masks.epoch.keepMask(removeEpochs) = false;


removeEpochs = removeEpochs(:);

if ~isfield(EEG.masks.epoch, 'source')
    EEG.masks.epoch.source.(source) = removeEpochs;
else
    if ~isfield(EEG.masks.epoch.source, (source))
        EEG.masks.epoch.source.(source) = removeEpochs;
    else
        % append to this source's existing list (forced to a column)
        fixVert = EEG.masks.epoch.source.(source);
        EEG.masks.epoch.source.(source) = fixVert(:);
        EEG.masks.epoch.source.(source) = [EEG.masks.epoch.source.(source); removeEpochs];
        EEG.masks.epoch.source.(source) = sort(EEG.masks.epoch.source.(source), "ascend");
    end
end