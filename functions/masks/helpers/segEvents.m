function [names, latSec] = segEvents(EEG)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% Event names and times for segmentation, shared by segmentEEG (builds the rules) and walkSeg (applies
% them), so both always name events the same way: the event's label if it has one, else its type.

% IN:   EEG = continuous EEGLAB struct (uses EEG.event .label / .type / .latency and EEG.srate)

% OUT:  names  = [nEv x 1] string, one name per event, in EEG.event order
%       latSec = [nEv x 1] double, event latency in seconds from the recording start

arguments
    EEG (1,1) struct
end

if isempty(EEG.event)
    names = strings(0, 1);  latSec = zeros(0, 1);
    return
end

if isfield(EEG.event, 'label')
    names = string({EEG.event.label});
    blank = strcmpi(names, '');                       % no label -> fall back to the event type
    names(blank) = string({EEG.event(blank).type});
else
    names = string({EEG.event.type});
end
names = names(:);

latSec = cell2mat({EEG.event.latency});
latSec = latSec(:) ./ EEG.srate;
end
