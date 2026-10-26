function [EEG, setFile] = latestSet(dataOut)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/22/2026

% Resume helper for the batch app: loads the most recently saved .set anywhere in a session's output
% tree, so a batch can continue a set that already has some steps done.

% IN:   dataOut = the session's output folder (cfg_full.paths.data_out)

% OUT:  EEG     = loaded EEGLAB struct, or [] if the folder has no .set yet
%       setFile = full path of the file loaded ('' if none)

arguments
    dataOut {mustBeTextScalar}
end

EEG = [];  setFile = '';
dataOut = char(dataOut);
if ~isfolder(dataOut), return; end
F = dir(fullfile(dataOut, '**', '*.set'));
% side files are not the working dataset: the split-off peripheral channels (chanSplitter), the
% per-segment copies (walkSeg) and the video editor's own copy. Skip them, or a resume would pick up
% e.g. the 1-channel ECG file as the EEG.
sideFile = ~cellfun(@isempty, regexp({F.name}, '(_splitChannels|_segment\d{3}|_eventsEdited)\.set$', 'once'));
F = F(~sideFile);
if isempty(F), return; end
[~, newest] = max([F.datenum]);
setFile = fullfile(F(newest).folder, F(newest).name);
EEG = pop_loadset('filename', F(newest).name, 'filepath', F(newest).folder);
end
