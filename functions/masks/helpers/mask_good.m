function [goodChan, goodSamp, goodEpoch] = mask_good(EEG)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Returns the current channel, sample and epoch keep-masks

% IN:   EEG = EEGLAB struct with EEG.masks (run mask_init first)

% OUT:  goodChan = logical [nbchan x 1], true = keep
%       goodSamp = logical [1 x pnts], true = keep
%       goodEpoch = logical [1 x trials], true = keep ([] unless a third output is asked for)

arguments
    EEG (1,1) struct
end

goodChan = EEG.masks.chan.keepMask;

goodSamp = EEG.masks.seg.keepMask;

if nargout >= 3 
    goodEpoch = EEG.masks.epoch.keepMask;
else
    goodEpoch = [];
end




