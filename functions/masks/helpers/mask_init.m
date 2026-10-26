function EEG = mask_init(EEG)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Creates the channel, segment and epoch keep-masks (all true) if they don't exist yet; existing masks are left alone

% IN:   EEG = EEGLAB struct

% OUT:  EEG = EEG struct with
%           EEG.masks.seg.keepMask = logical [1 x pnts]
%           EEG.masks.chan.keepMask = logical [nbchan x 1]
%           EEG.masks.epoch.keepMask = logical [1 x trials]

% segment mask
arguments
    EEG (1,1) struct
end

if ~isfield(EEG, 'masks')
    EEG.masks.seg.keepMask = true(1,EEG.pnts);
 
elseif ~isfield(EEG.masks, 'seg')
    EEG.masks.seg.keepMask = true(1, EEG.pnts);

elseif ~isfield(EEG.masks.seg, 'keepMask')
    EEG.masks.seg.keepMask = true(1, EEG.pnts);

end

% channel mask
if ~isfield(EEG, 'masks')
    EEG.masks.chan.keepMask = true(EEG.nbchan, 1);

elseif ~isfield(EEG.masks, 'chan')
    EEG.masks.chan.keepMask = true(EEG.nbchan, 1);

elseif ~isfield(EEG.masks.chan, 'keepMask')
    EEG.masks.chan.keepMask = true(EEG.nbchan, 1);

end

% epoch mask
if ~isfield(EEG, 'masks')
    EEG.masks.epoch.keepMask = true(1, EEG.trials);

elseif ~isfield(EEG.masks, 'epoch')
    EEG.masks.epoch.keepMask = true(1, EEG.trials);
    
elseif ~isfield(EEG.masks.epoch, 'keepMask')
    EEG.masks.epoch.keepMask = true(1, EEG.trials);

end

