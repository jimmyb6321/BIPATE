function [videoSec, segIdx, isCovered]  = videoTimeFromEEG(vidStruct, eegSec)

% Author: Mika Hess, Modified by: James Barlow
% Created: 07/24/2026
% Last updated: 10/18/2026

% Converts an EEG time to the video segment covering it and the time within that video

% IN:   vidStruct = sync table from parseMovieSyncs
%       eegSec = EEG time (s)

% OUT:  videoSec = time within the covering video (s); NaN if no video covers eegSec
%       segIdx = index of that video segment (0 if none)
%       isCovered = true if a video covers eegSec
arguments
    vidStruct struct
    eegSec (1,1) {mustBeNumeric}
end

begins = [vidStruct.eegBeginSec];
ends = [vidStruct.eegEndSec];
segIdx = find(eegSec >= begins & eegSec <= ends, 1);   % first segment that covers this time
if isempty(segIdx), videoSec = NaN; segIdx = 0; isCovered = false; return; end
seg = vidStruct(segIdx);
frac     = (eegSec - seg.eegBeginSec) / (seg.eegEndSec - seg.eegBeginSec);
videoSec = seg.videoBeginSec + frac * (seg.videoEndSec - seg.videoBeginSec);
isCovered = true;
