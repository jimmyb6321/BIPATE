function [looksPeriph, suggType, matcher] = detectPeriphs(EEG, periphSel)

% Author: James Barlow
% Created: 08/26/2026
% Last updated: 10/18/2026

% Guesses which channels are peripheral (EOG, ECG, EMG, ...) from their label/type keywords

% IN:   EEG = EEGLAB struct
%       periphSel = logical [nbchan x 1] of channels to check (optional, default all)

% OUT:  looksPeriph = logical [nSel x 1], true = keyword match
%       suggType = cell [nSel x 1] of suggested types ('OTHER' when no match)
%       matcher = cell of allowed type names, ending in 'OTHER'

arguments
    EEG (1,1) struct
    periphSel {mustBeNumericOrLogical} = true(numel(EEG.chanlocs), 1)
end

if nargin < 2
    periphSel = true(numel(EEG.chanlocs), 1);
end
chanLab = {EEG.chanlocs(periphSel).labels};

% channel type text to match against: type, else description, else empty
if isfield(EEG.chanlocs, 'type')
    getType = {EEG.chanlocs(periphSel).type};
elseif isfield(EEG.chanlocs, 'description')
    getType = {EEG.chanlocs(periphSel).description};
else
    [EEG.chanlocs.type] = deal([]);
    getType = {EEG.chanlocs(periphSel).type};
end

% keywords per type; looker{j} -> matcher{j}
looker = {{'veog', 'heog', 'eog', 'eye'},{'ecg', 'ekg'}, ...
    {'emg', 'chin'}, {'chest', 'thor', 'thorax'}, {'abd', 'abdomen'},...
    {'cannula', 'flow', 'nasal'}, {'spo2', 'sat', 'saturation'},...
    {'ref', 'cms', 'drl'}, {'pos', 'position'}, {'fid'}, {'noise'}};
matcher = {'EOG', 'ECG', 'EMG', 'CHEST', 'ABDOMEN', 'NASAL', 'O2', 'REF', 'POSITION', 'FID', 'NOISE'};

looksPeriph = false(numel(chanLab), 1);
suggType = cell(numel(chanLab), 1);
suggType(:) = {'OTHER'};

% first keyword hit in the label or type wins
for i = 1:numel(chanLab)
    thisChan = chanLab{i};
    for j = 1:numel(looker)
        thisL = looker{j};
        if (any(contains(thisChan, thisL, 'IgnoreCase', true))) || any(strcmpi(getType{i}, thisL))
            
            looksPeriph(i) = 1;
            suggType{i} = matcher{j};
            break;
            
        end
    end
end

matcher{end+1} = 'OTHER';

