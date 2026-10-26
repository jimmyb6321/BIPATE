function EEG = interpChans(EEG, cfg_full)

% Author: James Barlow
% Created: 06/17/2026
% Last updated: 10/25/2026

% Spherically interpolates the channels badChanDetect masked, then puts the final reference back over the full montage

% IN:   EEG = EEGLAB struct after component removal (needs EEG.chanlocs)
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = interpolated EEG struct, referenced like the final re-reference (average if there was none)
%           EEG.masks.chan.keepMask = all true
%           EEG.masks.chan.interpolated = logical, true for channels that were interpolated
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'interp');   % what must run first is listed in jobs.json
EEG = mask_init(EEG);
[goodChan, ~] = mask_good(EEG);
if ~isfield(EEG, 'chanlocs') || isempty(EEG.chanlocs)
    error('interpChans:noLocs', 'EEG.chanlocs not found -- cannot interpolate without channel locations!');
end
% interpolate channels masked by badChanDetect
EEG = pop_interp(EEG, find(~goodChan), 'spherical');
EEG.masks.chan.keepMask(:) = true;
EEG.masks.chan.interpolated = ~goodChan;
% put the final reference back over the full montage, the same kind the final re-reference used
% (EEG.etc.reref.final, written by rerefEEG; none = average, as before):
%   average / median / robust average -> recomputed so the rebuilt channels are part of it
%   channel(s), e.g. Fz or linked mastoids -> left alone: the interpolated channels are already relative to it
finalRef = 'average';
if isfield(EEG.etc, 'reref') && isfield(EEG.etc.reref, 'final'), finalRef = char(EEG.etc.reref.final); end
labels = {EEG.chanlocs.labels};
if strcmp(finalRef, 'average')
    EEG = pop_reref(EEG, []);
    refNote = 'average';
elseif strcmp(finalRef, 'median')
    EEG.data(:, :) = double(EEG.data(:, :)) - median(double(EEG.data(:, :)), 1);
    refNote = 'median';
elseif startsWith(finalRef, 'robust average')
    leftOut = strtrim(strsplit(char(extractBetween(string(finalRef), 'left out: ', ')')), ','));
    refChans = find(~ismember(labels, leftOut));   % every channel except the ones the robust average left out
    EEG.data(:, :) = double(EEG.data(:, :)) - mean(double(EEG.data(refChans, :)), 1);
    refNote = finalRef;
else
    refNote = [finalRef ' (kept, not recomputed)'];
end
EEG.ref = finalRef;
% save
EEG.etc.processing_log{end+1}  = sprintf('Channels interpolated + final reference (%s) at %s', refNote, string(datetime('now')));
[interpTag, roundSuffix] = stepRound(EEG, 'interpChans');
EEG.etc.processing_done{end+1} = interpTag;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath); mkdir(savePath); end
ppt = char(cfg_full.sessionID);
EEG.setname = [ppt '_interp' roundSuffix];
EEG = saveStep(EEG, 'filename', [ppt '_interp' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone('Interpolation + final reference done')
