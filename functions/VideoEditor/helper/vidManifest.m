function [manifest, skipWhy, eventsOnly] = vidManifest(mffFolder, videoFolder, setName)

% Author: Mika Hess, Modified by: James Barlow
% Created: 07/24/2026
% Last updated: 10/25/2026

% Builds the video manifest for an .mff: sync table, folder holding the videos, and each video's properties.
% The videos are looked for in videoFolder (if given), then inside the .mff, then the user is asked to pick
% their folder, edit the events without video, or skip the video for this set. A recording with no video at all opens events-only.

% IN:   mffFolder = path to the .mff folder (holds the sync file and info.xml)
%       videoFolder = (optional) folder expected to hold the videos, e.g. remembered from an earlier run
%       setName = (optional) set name shown in the question box

% OUT:  manifest
%           sync = vidStruct from parseMovieSyncs
%           mffFolder = the recording's .mff folder
%           videoFolder = folder the videos were found in
%           folder = same as videoFolder (older name, kept for code that still reads it)
%           videoProps = per video: FrameRate, Duration, durationMismatch (true if >1 s off the xml), Width, Height, file
%       manifest = [] when there is no video to show; eventsOnly = true -> open the editor without video,
%       false -> skipped (skipWhy = why, for the log; '' otherwise)

arguments
    mffFolder {mustBeTextScalar}
    videoFolder {mustBeTextScalar} = ''
    setName {mustBeTextScalar} = ''
end

if nargin < 2, videoFolder = ''; end
manifest = [];
skipWhy = '';
eventsOnly = false;
% a recording made without the camera has no movieSyncs file: nothing to show
if isempty(dir(fullfile(mffFolder, 'movieSyncs*.xml')))
    eventsOnly = true;   % no camera on this recording: open with traces and events only
    return
end
vidStruct = parseMovieSyncs(mffFolder);
fileNames = string({vidStruct.fileName});
if isempty(fileNames)
    eventsOnly = true;
    return
end

% first folder that holds every video in the sync file; keep asking until one does
candidates = {char(videoFolder), char(mffFolder)};
candidates = candidates(~cellfun(@isempty, candidates));
found = '';
for c = 1:numel(candidates)
    if all(isfile(fullfile(candidates{c}, fileNames)))
        found = candidates{c};
        break
    end
end
lastTried = char(mffFolder);
note = '';
where = '';
if ~isempty(videoFolder), where = ' or the folder used last time'; end
while isempty(found)
    % videos not in the .mff or the remembered folder: pick their folder or skip the video for this set
    % (default = Skip, so a stray Enter from an earlier dialog cannot open a picker by itself)
    answer = questdlg(sprintf(['%sThe %d video file(s) for %s (%s) are not in the .mff folder' ...
        '%s.\n\nPick the folder that holds all of them, edit the events without video, or skip the video editor for this set.'], note, numel(fileNames), ...
        char(setName), char(strjoin(fileNames, ', ')), where), ...
        'Videos not found', 'Pick the video folder...', 'Edit events without video', 'Skip video for this set', 'Skip video for this set');
    if strcmp(answer, 'Edit events without video')
        eventsOnly = true;
        return
    elseif strcmp(answer, 'Skip video for this set')
        skipWhy = 'videos not found, skipped by the user';
        return
    elseif ~strcmp(answer, 'Pick the video folder...')   % box closed with X
        error('Video editor cancelled for %s.', char(setName));
    end
    picked = uigetdir(lastTried, 'Select folder containing ALL .mov/.mp4 files');
    if isnumeric(picked)
        note = sprintf('No folder was picked.\n\n');
        continue
    end
    lastTried = picked;
    if all(isfile(fullfile(picked, fileNames)))
        found = picked;
    else
        note = sprintf('%s does not hold all of them.\n\n', picked);
    end
end
vidFiles = fullfile(found, fileNames);

manifest.sync = vidStruct;
manifest.mffFolder = char(mffFolder);
manifest.videoFolder = found;
manifest.folder = found;
manifest.videoProps = struct('FrameRate', {}, 'Duration', {}, 'durationMismatch', {}, 'Width', {}, 'Height', {}, 'file', {});
% read each video's properties and check its length against the xml
for i = 1:numel(vidFiles)
    vidRed = VideoReader(vidFiles(i));
    manifest.videoProps(i).FrameRate = vidRed.FrameRate;
    manifest.videoProps(i).Duration = vidRed.Duration;
    syncSpan = vidStruct(i).videoEndSec - vidStruct(i).videoBeginSec;
    manifest.videoProps(i).durationMismatch = abs(vidRed.Duration - syncSpan) > 1;
    if manifest.videoProps(i).durationMismatch
        warning('Segment %d (%s) from .mov file mismatches .xml by more than 1 second!', i, vidFiles(i));
    end
    manifest.videoProps(i).Width = vidRed.Width;
    manifest.videoProps(i).Height = vidRed.Height;
    manifest.videoProps(i).file = vidFiles(i);
end
end
