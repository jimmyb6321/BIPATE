function EEG = mask_clearSource(EEG, kind, source)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Removes everything one step flagged in the segment or epoch mask, then rebuilds that keepMask from the
% sources that are left (so a stretch another step also flagged stays bad).

% IN:   EEG = EEGLAB struct with EEG.masks (mask_init)
%       kind = 'seg' (continuous samples) or 'epoch'
%       source = name of the flagging step, as given to mask_addSeg / mask_addEpoch (e.g. 'data', 'icaact')

% OUT:  EEG = EEG struct with EEG.masks.(kind).source.(source) removed and EEG.masks.(kind).keepMask
%           = true everywhere except the indices still listed under the other sources

arguments
    EEG (1,1) struct
    kind {mustBeMember(kind, {'seg', 'epoch'})}
    source {mustBeTextScalar}
end

EEG = mask_init(EEG);
part = EEG.masks.(kind);
if ~isfield(part, 'source') || ~isfield(part.source, source)
    return
end
part.source = rmfield(part.source, source);
part.keepMask(:) = true;
for name = fieldnames(part.source)'
    part.keepMask(part.source.(name{1})) = false;
end
EEG.masks.(kind) = part;
end
