function EEG = runVideoEditor(EEG, cfg_full)

% Author: Mika Hess, Modified by: James Barlow
% Created: 07/27/2026
% Last updated: 10/25/2026

% Opens VideoEditorApp on the recording's synced videos for event correction, waits for it to close, and saves.
% The recording (.mff) folder and the video folder are separate: the .mff comes from EEG.etc.mffFolder (asked
% for if missing or moved), the videos are looked for in EEG.etc.videoFolder, then the .mff, then asked for.
% Both choices are stored in EEG.etc so the next run doesn't ask again.

% IN:   EEG = EEGLAB struct loaded from an .mff (EEG.etc.mffFolder set by loadData_max)
%       cfg_full = configuration struct (sessionID, paths.data_out)
%                  cfg_full.video.storedEvents = n x 2 cell {type, label} offered when adding an event
%       With no .mff linked it asks which to do: pick the .mff, edit the events without video, or skip this
%       set (events unchanged, nothing saved). A recording made without video opens events-only.

% OUT:  EEG = EEG struct with the edited events, saved as <sessionID>_videoEdited
%           EEG.etc.mffFolder, EEG.etc.videoFolder = where the recording and its videos were found
%           (unchanged and not saved if the editor was closed without saving)

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'videoEditor');   % what must run first is listed in jobs.json
mffFolder = '';
eventsOnly = false;   % true = open the editor without video (traces and events only)
if isfield(EEG.etc, 'mffFolder'), mffFolder = char(EEG.etc.mffFolder); end
if ~isMff(mffFolder)
    % no recording linked (a .set made elsewhere, synthetic data, or the .mff moved): say which set this is for,
    % and let the processor point at the .mff or skip the editor for this set
    sessionID = char(cfg_full.sessionID);
    choices = {'Pick the .mff folder...', 'Edit events without video', 'Skip video for this set'};
    % asked until it is answered: a cancelled folder picker comes back here instead of failing the set
    % (default = Skip, so a stray Enter from an earlier dialog cannot open a picker by itself)
    note = '';
    while true
        answer = questdlg(sprintf(['%sNo recording (.mff folder) is linked to %s, so there is no video to show.\n\n' ...
            'Pick its .mff folder (the folder whose name ends in .mff, not the Contents folder inside it), ' ...
            'edit its events without video, or skip the video editor for this set.'], note, sessionID), ['Video editor: ' sessionID], choices{:}, 'Skip video for this set');
        switch answer
            case 'Edit events without video'   % traces and event tools only
                eventsOnly = true;
                break
            case 'Pick the .mff folder...'
                picked = uigetdir('', ['Select the .mff folder for ' sessionID]);
                if isequal(picked, 0)
                    note = sprintf('No folder was picked.\n\n');
                    continue
                end
                if ~isMff(picked) && isMff(fileparts(picked))   % picked the Contents folder inside the .mff
                    picked = fileparts(picked);
                end
                if ~isMff(picked)
                    note = sprintf('%s is not an .mff recording folder (it has no info.xml).\n\n', picked);
                    continue
                end
                mffFolder = picked;
                break
            case 'Skip video for this set'
                EEG.etc.processing_log{end+1} = sprintf('Video editor skipped (no recording linked) at %s', string(datetime('now')));
                warning('runVideoEditor:skipped', 'Video editor skipped for %s: no .mff linked, events unchanged, nothing saved.', sessionID);
                return
            otherwise   % box closed with X
                error('Video editor cancelled for %s.', sessionID);
        end
    end
end
videoFolder = '';
if isfield(EEG.etc, 'videoFolder'), videoFolder = char(EEG.etc.videoFolder); end

manifest = [];
skipWhy = '';
if ~eventsOnly
    if isfield(EEG.etc, 'mffFolders') && numel(EEG.etc.mffFolders) > 1   % joined recordings: every one's videos
        [manifest, skipWhy, eventsOnly] = joinedManifest(cellstr(EEG.etc.mffFolders), EEG.etc.mffPartStartSec, ...
            videoFolder, char(cfg_full.sessionID));
    else
        [manifest, skipWhy, eventsOnly] = vidManifest(mffFolder, videoFolder, char(cfg_full.sessionID));
    end
    EEG.etc.mffFolder = mffFolder;
end
if isempty(manifest) && ~eventsOnly   % the processor chose Skip: events unchanged
    EEG.etc.processing_log{end+1} = sprintf('Video editor skipped (%s) at %s', skipWhy, string(datetime('now')));
    warning('runVideoEditor:skipped', 'Video editor skipped for %s: %s; events unchanged, nothing saved.', char(cfg_full.sessionID), skipWhy);
    return
end
if ~eventsOnly, EEG.etc.videoFolder = manifest.videoFolder; end

% the editor reads event labels; sets whose events never had one (synthetic, .set from elsewhere) get empty ones
if ~isempty(EEG.event) && ~isfield(EEG.event, 'label')
    [EEG.event.label] = deal('');
end
stored = cell(0, 2);   % Settings > Edit event markers (video): {type, label} rows for the "Add event" box
if isfield(cfg_full, 'video') && isfield(cfg_full.video, 'storedEvents') && ~isempty(cfg_full.video.storedEvents)
    stored = cfg_full.video.storedEvents;
end
app = VideoEditorApp(manifest, EEG, stored);
uiwait(app.fig);   % block until SAVE & EXIT or the window is closed
wasSaved = app.saved;
changed = app.eventsChanged();   % Save & exit with no edits writes no new file
editedEEG = app.EEG;
delete(app);       % stops the timer and sound, closes the window

if ~wasSaved
    warning('Video editor closed without saving; events unchanged and nothing saved.');
    return
end
if ~changed
    fprintf('Video editor: no event changes; nothing saved.\n');
    return
end
EEG = editedEEG;
EEG.etc.processing_log{end+1} = sprintf('Video Editor ran at %s', string(datetime('now')));
[videoTag, roundSuffix] = stepRound(EEG, 'videoEditor');
EEG.etc.processing_done{end+1} = videoTag;
savePath = fullfile(cfg_full.paths.data_out);
EEG.setname = [char(cfg_full.sessionID) '_videoEdited' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_videoEdited' roundSuffix], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone('Video Editor closed and events edited!')

end

% true when folder is an .mff recording folder (it holds info.xml)
function tf = isMff(folder)
tf = ~isempty(folder) && isfolder(folder) && isfile(fullfile(folder, 'info.xml'));
end

% IN:  parts = the joined .mff recordings in order; startSec = where each starts in the joined set (s);
%      videoFolder = remembered video folder ('' if none); setName = for the question boxes
% OUT: one manifest for the joined set: every recording's videos, their sync times moved to where that
%      recording sits in the joined data. A recording with no video just adds none; Skip on any recording
%      skips the editor for the set (manifest [] + skipWhy); no video anywhere -> eventsOnly = true.
function [manifest, skipWhy, eventsOnly] = joinedManifest(parts, startSec, videoFolder, setName)
manifest = [];
skipWhy = '';
eventsOnly = false;
for k = 1:numel(parts)
    [m, why, noVid] = vidManifest(parts{k}, videoFolder, sprintf('%s (recording %d of %d)', setName, k, numel(parts)));
    if isempty(m)
        if ~noVid, skipWhy = why; manifest = []; return; end   % Skip picked
        continue   % this recording has no video (or its events-only answer): nothing to add
    end
    for j = 1:numel(m.sync)
        m.sync(j).eegBeginSec = m.sync(j).eegBeginSec + startSec(k);
        m.sync(j).eegEndSec = m.sync(j).eegEndSec + startSec(k);
    end
    if isempty(manifest)
        manifest = m;
    else
        manifest.sync = [manifest.sync(:); m.sync(:)]';
        manifest.videoProps = [manifest.videoProps(:); m.videoProps(:)]';
    end
    if isempty(videoFolder), videoFolder = m.videoFolder; end   % try the same folder for the next recordings
end
if isempty(manifest)
    eventsOnly = true;
else
    manifest.mffFolder = parts{1};   % recording start for the clock
end
end
