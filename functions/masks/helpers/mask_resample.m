function EEG = mask_resample(EEG)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Rescales the segment mask to the new sample count after resampling

% IN:   EEG = resampled EEGLAB struct; EEG.masks.seg.keepMask still at the old length

% OUT:  EEG = EEG struct with EEG.masks.seg.keepMask = logical [1 x new pnts]

% each new sample covers a block of old samples; keep it only if the whole block was kept
arguments
    EEG (1,1) struct
end

edges  = round(linspace(1, numel(EEG.masks.seg.keepMask) + 1, EEG.pnts + 1));
newsamp = false(1, EEG.pnts);
for j = 1:EEG.pnts
    newsamp(j) = all(EEG.masks.seg.keepMask(edges(j):edges(j+1) - 1));
end

EEG.masks.seg.keepMask = newsamp;