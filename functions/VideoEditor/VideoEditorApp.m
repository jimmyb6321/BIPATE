classdef VideoEditorApp < handle

% Author: Mika Hess, Modified by: James Barlow
% Created: 07/24/2026
% Last updated: 10/25/2026

% Video + EEG event editor: plays the synced recording video (with its sound) next to regional EEG traces so
% event markers can be checked, added, dragged, typed in, or deleted. Close with SAVE & EXIT, or the window's X
% (asks whether to save).
%
% Playback: a timer ticks every 0.05 s and moves everything to the new time in one go (goToTime). To keep up
% with real time, the traces only hold the samples around the visible window (sliced from traceY), video frames
% are read forward instead of seeking when possible, and the sound plays in 30 s chunks read from the video file.

% IN:   manifest = from vidManifest (sync table, video folder, per-video properties), or [] for events only
%       EEG = EEGLAB struct from the .mff (events need .label)

% OUT:  app.EEG = EEG with edited events (sorted by latency); original events kept in EEG.etc.eventBackup
%       also saved as <filename>_eventsEdited.set next to the source when run on its own (not inside a BIPATE batch)

    properties
        % data / playback state
        manifest        % from vidManifest; [] = no video (events only)
        noVideo = false % true: traces and events only (no video panel, sound or video clock)
        eegSec = 0      % current EEG time (s)
        curSeg = 0      % video segment currently open
        reader = []     % VideoReader for curSeg
        % UI handles
        fig            
        vidAx
        eventAx
        vidImg
        scrubAx
        timeText 
        playhead
        tracePlayhead   % vertical line at the current time in the trace window (always its centre)
        isDragging = false
        playTimer
        Paused = true
        playPause
        lastTick
        % events
        EEG
        evTimes         % event times (s)
        evTypes
        evLabels
        typeColor       % event type -> marker colour
        eventPlayhead
        nextEvent
        lastEvent
        hoverLabel
        % trace view
        epochHalf = 180 % half of the trace window (s)
        regionChans     % channels averaged into each regional trace
        regionTraces    % central/frontal/parietal/occipital traces, 0.5-30 Hz, every 5th sample
        traceTime
        traceScales
        traceLines
        windowEdit
        scaleMult = 1
        scalingEdit
        % editing
        selectedEvent = []
        eventHover
        draggingMarker = false
        editBox
        dragLine
        recClockLabel
        recStart
        saveChanges
        deleteBtn
        addBtn
        % fast playback
        traceY              % full scaled trace per region (cell, same length as traceTime)
        sliceRange = [NaN NaN]   % time range currently held by the trace lines (s)
        frameStep = 1       % show every frameStep-th pixel (large videos are drawn at half size)
        % sound
        soundCheck          % 'Sound' tick box
        volumeSlider        % sound gain (x), applied to each chunk before playing; room-camera audio is often quiet
        player = []         % audioplayer for the current chunk
        audioInfo           % per video: SampleRate, TotalSamples, hasAudio
        audioChunkEnd = -Inf    % EEG time (s) where the current sound chunk ends
        saved = false       % true once SAVE & EXIT has saved
        storedEvents = cell(0, 2)   % n x 2 {type, label} from Settings, offered in "Add event" under the recording's own
        timelineEnd         % length of the timeline (s): the EEG, or the videos if they end sooner
    end
    methods
        % constructor: recording start time, traces, event lists, colour map, then the UI
        function obj = VideoEditorApp(manifest, EEG, stored)
            arguments
                manifest                   % struct from vidManifest, or [] to edit events without video
                EEG (1,1) struct
                stored cell = cell(0, 2)   % Settings stored event list: {type, label} rows
            end
            obj.noVideo = isempty(manifest);
            obj.manifest = manifest;
            obj.EEG = EEG;
            obj.storedEvents = VideoEditorApp.normEvents(stored);   % n x 3 {type, label, '#RRGGBB'}
            % a trimmed set can be much shorter than its videos (e.g. 30 min of a 7 h .mff): the scrub bar,
            % playback and event edits stop at the end of the EEG
            obj.timelineEnd = (EEG.pnts - 1) / EEG.srate;
            if ~obj.noVideo, obj.timelineEnd = min(manifest.sync(end).eegEndSec, obj.timelineEnd); end
            % wall-clock recording start from the .mff info.xml
            % (no .mff, e.g. events-only on a .set from elsewhere: NaT, and the clock shows time into the set)
            mffFolder = '';
            if isstruct(obj.manifest) && isfield(obj.manifest, 'mffFolder')
                mffFolder = obj.manifest.mffFolder;
            elseif isstruct(obj.manifest) && isfield(obj.manifest, 'folder')
                mffFolder = obj.manifest.folder;
            elseif isfield(EEG.etc, 'mffFolder')
                mffFolder = char(EEG.etc.mffFolder);
            end
            obj.recStart = NaT;
            if ~isempty(mffFolder) && isfile(fullfile(mffFolder, 'info.xml'))
                inf = fileread(fullfile(mffFolder,'info.xml'));
                tok = regexp(inf,'<recordTime>(.*?)</recordTime>','tokens','once');
                obj.recStart = datetime(tok{1}, 'InputFormat','yyyy-MM-dd''T''HH:mm:ss.SSSSSSZ', 'TimeZone','local');
            end
            obj.calcTraces();
            obj.syncEventLists();   % evTimes / evTypes / evLabels from EEG.event
            % event type -> marker color ('#RRGGBB'), from the stored event list in Settings (defaults in
            % cfg_init); a type in the recording that is on the list gets the list's color, others are black
            obj.typeColor = containers.Map('KeyType', 'char', 'ValueType', 'char');
            for r = 1:size(obj.storedEvents, 1)
                obj.typeColor(obj.storedEvents{r, 1}) = obj.storedEvents{r, 3};
            end
           
            obj.readAudioInfo();
            if ~obj.noVideo && obj.manifest.videoProps(1).Width > 1280, obj.frameStep = 2; end
            obj.buildUI();
            obj.goToTime(obj.eegSec);
        end
        % layout: video + controls | trace window | prev/play/next | full-recording scrub bar
        function buildUI(obj)
            obj.fig = uifigure('Name','Video Editor', 'CloseRequestFcn', @(~,~) obj.onCloseRequest(), ...
                'WindowKeyPressFcn', @(~, evt) obj.onKey(evt));
            scrSz = get(groot, 'ScreenSize');
            width = scrSz(3);
            height = scrSz(4);
            obj.fig.Position = [50 50 width-100 height-100];
            grid = uigridlayout(obj.fig, 'BackgroundColor', [230/255 230/255 250/255]);
            grid.ColumnWidth = {'1x'};
            grid.RowHeight = {'4x', '2x', '1x', '0.5x'};
            
            childGrid = uigridlayout(grid,  'BackgroundColor', [235/255 235/255 250/255]);
            childGrid.Layout.Row = 1;
            childGrid.Layout.Column = 1;
            childGrid.ColumnWidth = {'4x', '1x'};
            childGrid.RowHeight = {'1x'};
            % video panel
            vidView = uipanel(childGrid, "BackgroundColor", [225/255 225/255 255/255]);
            vidView.Layout.Row = 1;
            vidView.Layout.Column = 1;
            obj.vidAx = uiaxes(vidView);
            axis(obj.vidAx,'image');
            obj.vidAx.XTick = []; obj.vidAx.YTick = [];
            obj.vidAx.Units = 'normalized';
            obj.vidAx.Position = [0 0 1 1];
            obj.vidAx.Toolbar.Visible = 'off';
            disableDefaultInteractivity(obj.vidAx);
            if obj.noVideo   % events-only: say so where the video would be
                obj.vidAx.XLim = [0 1]; obj.vidAx.YLim = [0 1];
                text(obj.vidAx, 0.5, 0.5, sprintf('No video\nediting events only'), 'HorizontalAlignment', 'center', ...
                    'FontSize', 16, 'Color', [0.35 0.35 0.5]);
            end
            % controls: window size, trace scaling, recording clock, save & exit
            vidControl = uipanel(childGrid, "BackgroundColor", [225/255 225/255 255/255]);
            vidControl.Layout.Row = 1;
            vidControl.Layout.Column = 2;
            vidControlGrid = uigridlayout(vidControl, "BackgroundColor",[215/255 215/255 255/255]);
            vidControlGrid.ColumnWidth = {'1x', '1x'};
            vidControlGrid.RowHeight = {'1x', '1x', '1x', '1x', '1x', '1x', '1x', '1x'};
            windowEditLabel = uilabel(vidControlGrid, 'Text', 'Window Size', 'FontSize', 15);
            windowEditLabel.Layout.Column = 1;
            windowEditLabel.Layout.Row = 1;
            obj.windowEdit = uieditfield(vidControlGrid, 'numeric', 'Value', obj.epochHalf* 2, 'FontSize', 15, 'BackgroundColor', [195/255 195/255 225/255], "ValueChangedFcn", @(~, ~) obj.changeWindow);
            obj.windowEdit.Layout.Column = 1;
            obj.windowEdit.Layout.Row = 2;
            obj.saveChanges = uibutton(vidControlGrid, "BackgroundColor", [220/255 195/255 225/255], 'Text', sprintf('SAVE &\nEXIT') ,'FontSize', 15,"ButtonPushedFcn", @(~,~) obj.saveDataBack());
            obj.saveChanges.Layout.Column = 2;
            obj.saveChanges.Layout.Row = 8;
            scalingEditLabel = uilabel(vidControlGrid, 'Text', 'Trace Scaling', 'FontSize', 15);
            scalingEditLabel.Layout.Column = 1;
            scalingEditLabel.Layout.Row = 3;
            obj.scalingEdit = uieditfield(vidControlGrid, 'numeric', 'Value', obj.scaleMult, 'FontSize', 15, 'BackgroundColor',[195/255 195/255 225/255], "ValueChangedFcn", @(~,~) obj.changeScaling);
            obj.scalingEdit.Layout.Column = 1;
            obj.scalingEdit.Layout.Row = 4;
            obj.playTimer = timer('Period', 0.05, ExecutionMode='fixedRate', BusyMode='drop', TimerFcn=@(~,~) obj.onTick);
            clockLabelText = uilabel(vidControlGrid, 'Text', sprintf('Local Time at \n Recording'), 'FontSize', 15, 'HorizontalAlignment', 'right');
            clockLabelText.Layout.Column = 2;
            clockLabelText.Layout.Row = 1;
            obj.recClockLabel = uilabel(vidControlGrid, 'Text', obj.clockText(0), 'FontSize', 15, 'HorizontalAlignment', 'right');
            obj.recClockLabel.Layout.Column = 2;
            obj.recClockLabel.Layout.Row = 2;
            obj.addBtn = uibutton(vidControlGrid, "BackgroundColor", [220/255 195/255 225/255], 'Text', sprintf('ADD EVENT\nat playhead'), ...
                'FontSize', 15, 'Tooltip', 'Adds an event at the current time. Right-click an empty spot in the trace window to add one there.', ...
                "ButtonPushedFcn", @(~,~) obj.addEvent(obj.eegSec));
            obj.addBtn.Layout.Column = 2;
            obj.addBtn.Layout.Row = 6;
            obj.soundCheck = uicheckbox(vidControlGrid, 'Text', 'Sound', 'FontSize', 15, ...
                'Value', any([obj.audioInfo.hasAudio]), 'Enable', any([obj.audioInfo.hasAudio]), ...
                'ValueChangedFcn', @(~,~) obj.syncAudio());
            obj.soundCheck.Layout.Column = 1;
            obj.soundCheck.Layout.Row = 6;
            volGrid = uigridlayout(vidControlGrid, [1 2], 'ColumnWidth', {'fit', '1x'}, 'Padding', [0 0 0 0], ...
                'BackgroundColor', [215/255 215/255 255/255]);
            volGrid.Layout.Column = 1;
            volGrid.Layout.Row = 7;
            uilabel(volGrid, 'Text', 'Volume', 'FontSize', 15);
            obj.volumeSlider = uislider(volGrid, 'Limits', [0 10], 'Value', 4, 'MajorTicks', [0 1 5 10], ...
                'MinorTicks', [], 'Tooltip', 'Sound gain (x1 = as recorded). Loud parts are clipped, not distorted.', ...
                'ValueChangedFcn', @(~,~) obj.syncAudio());   % restarts the chunk at the playhead with the new gain
            % trace window with event markers (click = select/drag, right-click = type/delete, right-click
            % on an empty spot = add an event there)
            traceViewer = uipanel(grid, "BackgroundColor", [235/255 235/255 250/255]);
            traceViewer.Layout.Row = 2;
            traceViewer.Layout.Column = 1;
            obj.eventAx = uiaxes(traceViewer, "XLim", [obj.eegSec - obj.epochHalf obj.eegSec + obj.epochHalf], 'YLim', [-0.6 3.6],  'Color', [200/255 200/255 200/255]);
            obj.drawTraces();
            obj.drawMarkers(obj.eventAx, true);
            obj.tracePlayhead = xline(obj.eventAx, obj.eegSec, 'k', 'LineWidth', 1.5, 'PickableParts', 'none');
            obj.eventAx.XTick = []; obj.eventAx.YTick = [];
            obj.eventAx.Units = 'normalized';
            obj.eventAx.Position = [0 0 1 1];
            obj.eventAx.Toolbar.Visible = 'off';
            text(obj.eventAx, 0.01, 0.95, sprintf('Window: %d s', 2*obj.epochHalf), ...
                'Units','normalized', 'PickableParts','none', 'FontSize', 20);
            disableDefaultInteractivity(obj.eventAx);
            obj.eventAx.ButtonDownFcn = @(~,~) obj.onEventClick();
            obj.eventHover = text(obj.eventAx, 0, 5.2, '', 'Visible','off', 'PickableParts', 'none', 'Color', 'r', ...
                'FontWeight', 'bold', 'BackgroundColor', [1 1 1], 'Margin', 1);
            obj.eventAx.ContextMenu = [];
            obj.editBox = uieditfield(obj.fig, 'numeric', 'Visible', 'off', 'ValueChangedFcn', @(~,~) obj.commitEdit());
            obj.deleteBtn = uibutton(obj.fig, "BackgroundColor", [220/255 195/255 225/255], 'Text', 'DELETE', 'ButtonPushedFcn', @(~,~) obj.deleteEvent(), 'Visible', 'off');
            % prev / play / next
            transporter = uipanel(grid, "BackgroundColor",  [235/255 235/255 250/255]);
            transporter.Layout.Row = 3;
            transporter.Layout.Column = 1;
            transGrid = uigridlayout(transporter, 'RowHeight', {'1x'}, 'ColumnWidth', {'1x','1x','1x'});
            obj.lastEvent = uibutton(transGrid, "ButtonPushedFcn", @(s, e) obj.lastBtn(), "Text", 'Previous EVENT');
            obj.lastEvent.Layout.Column = 1;
            obj.playPause = uibutton(transGrid, "ButtonPushedFcn", @(s, e) obj.pauseBtn(), "Text", 'PLAY');
            obj.playPause.Layout.Column = 2;   
            obj.nextEvent = uibutton(transGrid, "ButtonPushedFcn", @(s, e) obj.nextBtn(), "Text", 'NEXT EVENT');
            obj.nextEvent.Layout.Column = 3;
            % scrub bar over the whole recording
            scrubber = uipanel(grid, "BackgroundColor", [235/255 235/255 250/255]);
            scrubber.Layout.Row = 4;
            scrubber.Layout.Column = 1;
            obj.scrubAx = uiaxes(scrubber, 'XLim', [0 obj.timelineEnd], 'YLim', [0 1], 'Color', [200/255 200/255 200/255]);
            obj.scrubAx.Units='normalized'; 
            obj.scrubAx.Position=[0 0 1 1];
            obj.scrubAx.XTick = [];
            obj.scrubAx.YTick = [];
            obj.scrubAx.Toolbar.Visible = 'off';
            obj.drawMarkers(obj.scrubAx, false);
            disableDefaultInteractivity(obj.scrubAx);
            obj.playhead = xline(obj.scrubAx, obj.eegSec, 'k', 'LineWidth', 1.5, 'PickableParts','none');
            obj.scrubAx.ButtonDownFcn = @(s, e) obj.onScrub();
            obj.fig.WindowButtonMotionFcn = @(s,e) obj.onDrag();
            obj.fig.WindowButtonUpFcn = @(s,e) obj.onDragEnd();
            obj.fig.WindowButtonDownFcn = @(s,e) obj.onFigureClick(e);
            obj.timeText = text(obj.scrubAx, obj.eegSec, 0.5, obj.formatTime(obj.eegSec), 'PickableParts', 'none');
            obj.hoverLabel = text(obj.scrubAx, 0, 0.8, '', 'Visible','off', 'Color', 'r');
            
        end
        % shows the video frame for eegSec (black if no video covers it). Seeking (setting CurrentTime) is
        % slow, so when the wanted time is a little ahead of the reader the frames in between are read instead.
        function redraw(obj)
            if obj.noVideo, return; end   % events-only: no frames to show
            [videoSec, segIdx, covered] = videoTimeFromEEG(obj.manifest.sync, obj.eegSec);
            frame = [];
            if ~covered
                frame = zeros(obj.manifest.videoProps(1).Height, obj.manifest.videoProps(1).Width, 3, 'uint8');
            else
                if segIdx ~= obj.curSeg
                    obj.reader = VideoReader(obj.manifest.videoProps(segIdx).file);
                    obj.curSeg = segIdx;
                end
                lead = videoSec - obj.reader.CurrentTime;   % how far the wanted time is past the next frame
                if lead < -1 || lead > 1 || (lead < 0 && obj.Paused)
                    obj.reader.CurrentTime = min(max(videoSec, 0), obj.reader.Duration - 1/obj.reader.FrameRate);
                    lead = 0;
                end
                if lead >= 0 || isempty(obj.vidImg)
                    while hasFrame(obj.reader)
                        frame = readFrame(obj.reader);
                        if obj.reader.CurrentTime > videoSec, break; end
                    end
                end
            end
            if isempty(frame), return; end   % reader is ahead of the wanted time: keep showing the current frame
            frame = frame(1:obj.frameStep:end, 1:obj.frameStep:end, :);
            if isempty(obj.vidImg), obj.vidImg = image(obj.vidAx, frame); end
            obj.vidImg.CData = frame;
        end
        % jump to time t because of the user (scrub, next/previous): moves everything and restarts the sound there
        function jumpTo(obj, t)
            obj.goToTime(t);
            obj.syncAudio();
        end
        % click on the scrub bar: jump there, snapping to a nearby event
        function onScrub(obj)
            obj.isDragging = true;
            t = obj.scrubAx.CurrentPoint(1,1);
            totalDur = obj.timelineEnd;
            [dist, idx] = min(abs(obj.evTimes - t));
            if dist < 0.005 * totalDur, t = obj.evTimes(idx); end   % snap to marker
            t = min(max(t, 0), totalDur);
            obj.jumpTo(t);
        end
        % mouse move: scrub, drag a marker, or show the event under the cursor
        function onDrag(obj)
            if obj.isDragging
                t = obj.scrubAx.CurrentPoint(1,1);
                t = min(max(t, 0), obj.timelineEnd);
                obj.goToTime(t);
            elseif obj.draggingMarker
                x = obj.eventAx.CurrentPoint(1,1);
                x = min(max(x, 0), obj.timelineEnd);
                obj.evTimes(obj.selectedEvent) = x;
                obj.dragLine.XData = [x x];
                obj.eventHover.Position(1) = x;
            else     
                ht = obj.scrubAx.CurrentPoint;
                htx = ht(1,1); hty = ht(1,2);
                totalDur = obj.timelineEnd;
                if htx < 0 ||htx > totalDur || hty < 0 || hty > 1
                    obj.hoverLabel.Visible = 'off'; return;
                end
                [dist, idx] = min(abs(obj.evTimes - htx));
                thresh = 0.005 * totalDur;
                if dist < thresh
                    obj.hoverLabel.Position(1) = obj.evTimes(idx); 
                    obj.hoverLabel.String = sprintf('%s @ %s', obj.evLabels(idx), obj.formatTime(obj.evTimes(idx)));
                    obj.hoverLabel.Visible = 'on';
                else
                    obj.hoverLabel.Visible = 'off';
                end
            end
        end
        % click in the trace window: near a marker, left = select + drag, right = edit box + delete;
        % away from markers, left = clear the selection, right = add an event at that time
        function onEventClick(obj)
            obj.clearSelection();
            ht = obj.eventAx.CurrentPoint(1,1);
            
            [dist, idx] = min(abs(obj.evTimes - ht));
            thresh = 0.03 *obj.epochHalf;
            if isempty(dist) || dist >= thresh
                if strcmp(obj.fig.SelectionType, 'alt')
                    obj.addEvent(ht);
                end
                return
            end
            if dist < thresh 
                obj.selectedEvent = idx; 
                if strcmp(obj.fig.SelectionType, 'alt')
                    xlim = obj.eventAx.XLim;
                    axPos = getpixelposition(obj.eventAx, true); % [x y w h], figure pixels
                    fracX = (obj.evTimes(idx) - xlim(1)) / (xlim(2)-xlim(1));
                    xPixels = axPos(1) + fracX * axPos(3);
                    yPixels = axPos(2) + axPos(4)*0.9;
                    obj.editBox.Position = [xPixels, yPixels, 60 22];
                    obj.editBox.Value = obj.evTimes(idx);
                    obj.editBox.Visible = 'on';
                    obj.deleteBtn.Position = [xPixels, yPixels-26, 60 22];
                    obj.deleteBtn.Visible = 'on';
                    focus(obj.editBox);
                    obj.eventHover.Visible = 'off';
                else
                    nowPos = obj.evTimes(idx);
                    obj.dragLine = line(obj.eventAx, [nowPos nowPos], obj.eventAx.YLim, 'Color', [1 0.5 0], 'LineWidth', 1, 'LineStyle', '--', 'PickableParts','none', 'Tag', 'drag');                   
                    obj.draggingMarker = true;
                    obj.eventHover.Position(1) = obj.evTimes(idx);
                    obj.eventHover.String = sprintf('%s', obj.evLabels(idx));
                    obj.eventHover.Visible = 'on';
                end
            end   
        end
        % hides the selected event's label, edit box and delete button
        function clearSelection(obj)
            obj.selectedEvent = [];
            obj.eventHover.Visible = 'off';
            obj.editBox.Visible = 'off';
            obj.deleteBtn.Visible = 'off';
        end
        % any click outside the trace window (video, buttons, scrub bar) clears the selection
        function onFigureClick(obj, evt)
            hit = evt.HitObject;
            if isempty(hit) || ~(isequal(hit, obj.eventAx) || isequal(ancestor(hit, 'axes'), obj.eventAx) ...
                    || isequal(hit, obj.editBox) || isequal(hit, obj.deleteBtn))
                obj.clearSelection();
            end
        end
        % mouse up: stop scrubbing, or commit a dragged marker's new time
        function onDragEnd(obj)
            obj.isDragging = false;
            wasDraggingMark = obj.draggingMarker;
            obj.draggingMarker = false;
            delete(obj.dragLine); 
            if wasDraggingMark
                totalDur = obj.timelineEnd;
                newT = obj.evTimes(obj.selectedEvent);
                if newT < 0 || newT > totalDur
                    obj.clearSelection();
                    return
                end
                obj.ensureBackup();
                obj.EEG.event(obj.selectedEvent).latency = newT * obj.EEG.srate;
                obj.evTimes(obj.selectedEvent) = newT;
                obj.refreshMarkers();
                obj.eventHover.Position(1) = newT;   % label stays on the selected event until the selection is cleared
            end
        end
        % seconds -> hh:mm:ss
        % IN: t = seconds into the set   OUT: wall-clock time of the recording, or "set time HH:MM:SS" when
        % evTimes (s), evTypes, evLabels (1 x n) from EEG.event; an empty event list gives empty rows
        function syncEventLists(obj)
            if isempty(obj.EEG.event)
                obj.evTimes = zeros(1, 0); obj.evTypes = strings(1, 0); obj.evLabels = strings(1, 0);
                return
            end
            obj.evTimes = [obj.EEG.event.latency]/obj.EEG.srate;
            obj.evTypes = string({obj.EEG.event.type});
            if isfield(obj.EEG.event, 'label')
                obj.evLabels = string(cellfun(@(x) char(string(x)), {obj.EEG.event.label}, 'UniformOutput', false));
            else
                obj.evLabels = strings(1, numel(obj.EEG.event));
            end
        end
        %     the recording start is unknown (no .mff)
        function str = clockText(obj, t)
            if isnat(obj.recStart)
                str = ['set time ' obj.formatTime(t)];
            else
                str = char(obj.recStart + seconds(t), 'yyyy-MM-dd HH:mm:ss');
            end
        end
        function str = formatTime(~, s)
            str = sprintf('%02d:%02d:%02d', floor(s/3600), mod(floor(s/60), 60), mod(floor(s), 60));
        end
        % moves everything (playhead, trace window, clock, video) to time t, then draws both axes together
        function goToTime(obj, t)
            if ~obj.draggingMarker
                obj.clearSelection();
            end
            obj.timeText.Position(1) = t;
            obj.timeText.String = obj.formatTime(t);
            obj.playhead.Value = t;    
            if isempty(obj.tracePlayhead) || ~isvalid(obj.tracePlayhead)   % redrawn traces can take it with them
                obj.tracePlayhead = xline(obj.eventAx, t, 'k', 'LineWidth', 1.5, 'PickableParts', 'none');
            end
            obj.tracePlayhead.Value = t;
            obj.eegSec = t;
            obj.eventAx.XLim = [t-obj.epochHalf, t+obj.epochHalf];
            obj.sliceTraces();
            obj.recClockLabel.Text = obj.clockText(t);
            obj.redraw();
            drawnow limitrate
        end
        % the trace lines hold only the samples from one window before to one window after the visible one;
        % they are re-cut when the view leaves that range
        % (sliceTraces(obj, 'force') re-cuts regardless, e.g. after the scaling changed)
        function sliceTraces(obj, ~)
            shown = obj.eventAx.XLim;
            if nargin < 2 && shown(1) >= obj.sliceRange(1) && shown(2) <= obj.sliceRange(2), return; end
            width = diff(shown);
            obj.sliceRange = [shown(1) - width, shown(2) + width];
            keep = obj.traceTime >= obj.sliceRange(1) & obj.traceTime <= obj.sliceRange(2);
            for k = 1:numel(obj.traceLines)
                set(obj.traceLines(k), 'XData', obj.traceTime(keep), 'YData', obj.traceY{k}(keep));
            end
        end
        % play/pause toggle
        function pauseBtn(obj)
            if obj.Paused == true
                obj.lastTick = tic;
                obj.Paused = false; 
                obj.playPause.Text = 'PAUSE';
                obj.syncAudio();
                start(obj.playTimer);
            else
                stop(obj.playTimer);
                obj.Paused = true; 
                obj.playPause.Text = 'PLAY';
                obj.syncAudio();
            end
        end
        % playback timer: advance by real elapsed time
        function onTick(obj)
            elapsed = toc(obj.lastTick);
            obj.lastTick = tic;
            t = obj.eegSec + elapsed;
            if t >= obj.timelineEnd
                stop(obj.playTimer); obj.Paused = true; obj.playPause.Text = 'PLAY';
                obj.syncAudio();
                return;
            end
            obj.goToTime(t)
            if t >= obj.audioChunkEnd - 0.1   % current sound chunk used up: start the next one
                obj.syncAudio();
            end
        end
        % IN: ty = event type   OUT: hex = its marker color '#RRGGBB' (black when it is not on the stored list)
        function hex = colorOf(obj, ty)
            ty = strtrim(char(ty));
            if ~isempty(ty) && isKey(obj.typeColor, ty), hex = obj.typeColor(ty); else, hex = '#000000'; end
        end
        % event lines on ax, one line object per color; labels optional
        function drawMarkers(obj, ax, showLabels)
            hold(ax, 'on')
            cols = string(arrayfun(@(ty) obj.colorOf(ty), obj.evTypes, 'UniformOutput', false));   % '#RRGGBB' per event
            for g = reshape(unique(cols), 1, [])
                typeGroup = obj.evTimes(cols == g);
                if isempty(typeGroup), continue; end
                typeGroup = reshape(typeGroup, 1, []);
                X = [typeGroup; typeGroup; nan(size(typeGroup))]; X = X(:)';
                Y = repmat([-0.9; 5.4; NaN], numel(typeGroup), 1)';
                line(ax, X, Y, 'Color', VideoEditorApp.hexToRGB(char(g)), 'LineWidth', 1, 'PickableParts','none', 'Tag', 'marker');
            end
            if showLabels
                for i = 1:numel(obj.evTimes)
                    text(ax, obj.evTimes(i), -0.9, obj.evLabels(i), 'Color', VideoEditorApp.hexToRGB(char(cols(i))), ...
                         'HorizontalAlignment', 'right', 'FontSize', 15, ...
                         'PickableParts','none', 'Clipping','on', 'VerticalAlignment', 'bottom', 'Tag', 'marker');
                end
            end
        end
        % jump to next / previous event (button greys out at the ends)
        function nextBtn(obj)
            obj.nextEvent.FontColor = [0 0 0];
            obj.lastEvent.FontColor = [0 0 0];
            t = min(obj.evTimes(obj.evTimes > obj.eegSec));
            if isempty(t), obj.nextEvent.FontColor = [0.4 0.4 0.4]; return; end
            obj.jumpTo(t);
        end
        function lastBtn(obj)
            obj.nextEvent.FontColor = [0 0 0];
            obj.lastEvent.FontColor = [0 0 0];
            t = max(obj.evTimes(obj.evTimes < obj.eegSec));
            if isempty(t), obj.lastEvent.FontColor = [0.4 0.4 0.4];return; end
            obj.jumpTo(t);
            
        end
        % regional traces: average of channels within R of Cz/Fz/Pz/Oz, 0.5-30 Hz, decimated by 5
        % four region traces (Cz, Fz, Pz, Oz) for the trace window: the mean of the channels within ~20 degrees of
        % each region centre, high-passed 0.5 Hz and low-passed 30 Hz, kept at every 5th sample. Directions, not
        % distances, so any cap scale works (EGI cm, 10-20 mm, unit sphere).
        % Region centre: the channel with the region's 10-20 name, else the mean of its nearest named neighbours
        % (e.g. O1 + O2); a region still missing is placed from the cap's own Cz/Fz axes when those exist, else
        % from EGI-style head directions (Y = front, Z = up; what GSN caps use). A region with no channel in
        % range uses its single nearest channel.
        function calcTraces(obj)
            names = {{'Cz'}, {'Fz', 'AFz', 'F1', 'F2'}, {'Pz', 'POz', 'P1', 'P2'}, {'Oz', 'O1', 'O2', 'Iz'}};
            egiDir = [0 0 9.7; 0 4 7; 0 -4 7; 0 -8 2];   % EGI-style (y = front, z = up): Cz Fz Pz Oz
            nCh = numel(obj.EEG.chanlocs);
            pos = nan(nCh, 3);   % channels without a location stay NaN and are never picked
            for c = 1:nCh
                xyz = [obj.EEG.chanlocs(c).X, obj.EEG.chanlocs(c).Y, obj.EEG.chanlocs(c).Z];
                if numel(xyz) == 3 && all(isfinite(xyz)), pos(c, :) = xyz; end
            end
            unitPos = pos ./ vecnorm(pos, 2, 2);
            labels = {obj.EEG.chanlocs.labels};
            centres = nan(4, 3);   % one unit direction per region
            named = false(1, 4);   % true = centre came from the cap's own channel names
            for i = 1:4
                have = find(ismember(lower(labels), lower(names{i})) & all(isfinite(unitPos), 2)');
                if isempty(have), continue; end
                first = have(strcmpi(labels(have), names{i}{1}));
                if ~isempty(first), have = first(1); end
                centre = mean(unitPos(have, :), 1);
                centres(i, :) = centre / norm(centre);
                named(i) = true;
            end
            % regions still missing: the EGI-style direction, expressed in this cap's up (Cz) / front (Fz) axes
            if named(1) && named(2)
                up = centres(1, :);
                front = centres(2, :) - (centres(2, :) * up') * up;
                front = front / norm(front);
                toCap = @(d) (d(2) * front + d(3) * up) / norm(d(2) * front + d(3) * up);
            else
                toCap = @(d) d / norm(d);
            end
            for i = find(~named)
                centres(i, :) = toCap(egiDir(i, :));
            end
            for i = 1:4
                cosAng = unitPos * centres(i, :)';   % cosine of the angle between each channel and the centre
                chans = find(cosAng > cosd(20));
                if isempty(chans)
                    [~, chans] = max(cosAng);   % nearest channel (max ignores the NaNs)
                end
                obj.regionChans{i} = chans;
                tr = double(mean(obj.EEG.data(chans, :), 1));
                tr = highpass(tr, 0.5, obj.EEG.srate);
                tr = lowpass(tr, 30, obj.EEG.srate);
                tr = tr - mean(tr);
                obj.regionTraces{i} = tr(1:5:end);
            end
            obj.traceTime = (0:5:obj.EEG.pnts-1)/obj.EEG.srate;
        end
        % one stacked line per region with its name
        function drawTraces(obj)
            offsets = [4.5 3 1.5 0];
            obj.traceLines = gobjects(1,4);
            names = {'Central','Frontal','Parietal','Occipital'};
            obj.eventAx.YLim = [-0.9 5.4];
            for k = 1:numel(names)
                obj.traceLines(k) = line(obj.eventAx, NaN, NaN, 'Color', 'k', 'PickableParts', 'none');
                % name sits in the gap just above its trace band (bands are offset +/- 0.6, y axis -0.9 to 5.4)
                text(obj.eventAx, 0.005, (offsets(k) + 0.62 + 0.9)/6.3, names{k}, ...
                    'Units', 'normalized', 'Color', [0.35 0.1 0.6], 'FontWeight', 'bold', ...
                    'VerticalAlignment', 'bottom', 'PickableParts', 'none');
                
            end
            obj.redrawTraces();
        end
        % window size / scaling edits
        function changeWindow(obj)
            obj.epochHalf = obj.windowEdit.Value / 2;
            obj.sliceRange = [NaN NaN];
            obj.goToTime(obj.eegSec)
        end
        function changeScaling(obj)
            obj.scaleMult = obj.scalingEdit.Value;
            obj.redrawTraces();
        end
        % rescale each trace to its median amplitude x scaleMult, clipped to its band
        function redrawTraces(obj)
            offsets = [4.5 3 1.5 0];
            halfband = 0.6;
            for k = 1:4
                tr = double(obj.regionTraces{k});
                s = 0.08/median(abs(tr));   
                obj.traceScales(k) = s;
                y = tr *s * obj.scaleMult +offsets(k);
                obj.traceY{k} = max(min(y, offsets(k)+halfband), offsets(k)-halfband);
            end
            if ~isempty(obj.eventAx) && isvalid(obj.eventAx)
                obj.sliceTraces('force');
            end
        end
        % keeps the original events once, before the first edit
        function ensureBackup(obj)
            if ~isfield(obj.EEG.etc, 'eventBackup')
                obj.EEG.etc.eventBackup = obj.EEG.event;
            end
        end
        % typed time from the edit box -> event latency
        function commitEdit(obj)
            newT = obj.editBox.Value;
            totalDur = obj.timelineEnd;
            if newT < 0 || newT > totalDur; return; end
            obj.ensureBackup();
            obj.EEG.event(obj.selectedEvent).latency = newT * obj.EEG.srate;
            obj.evTimes(obj.selectedEvent) = newT;
            obj.refreshMarkers();
            obj.clearSelection();
        end
        % redraws the event markers in the trace window and on the scrub bar
        function refreshMarkers(obj)
            delete(findobj(obj.eventAx, 'Tag', 'marker'));
            obj.drawMarkers(obj.eventAx, true);
            delete(findobj(obj.scrubAx, 'Tag', 'marker'));
            obj.drawMarkers(obj.scrubAx, false);
        end
        % new event at time t (s): asks for its type code and label (askNewEvent), then adds it
        function addEvent(obj, t)
            totalDur = obj.timelineEnd;
            if t < 0 || t > totalDur, return; end
            answer = obj.askNewEvent(t);
            if isempty(answer), return; end
            obj.ensureBackup();
            newEvent = struct();
            if ~isempty(obj.EEG.event)
                for name = fieldnames(obj.EEG.event)'
                    newEvent.(name{1}) = [];
                end
            end
            newEvent.type = answer{1};
            newEvent.label = answer{2};
            newEvent.latency = t * obj.EEG.srate;
            if isfield(newEvent, 'duration'), newEvent.duration = 0; end
            if isempty(obj.EEG.event)
                obj.EEG.event = newEvent;
            else
                obj.EEG.event(end + 1) = orderfields(newEvent, obj.EEG.event(1));
            end
            obj.syncEventLists();   % evTimes / evTypes / evLabels from EEG.event
            obj.refreshMarkers();
        end
        % small window for a new event: type and label are dropdowns you can also type into. Their lists are
        % the types/labels already in the recording, so ones added earlier show up next time. Picking a type
        % fills in the label most often used with it. Returns {type, label}, or {} if cancelled.
        function answer = askNewEvent(obj, t)
            answer = {};
            types = unique(obj.evTypes(strlength(strtrim(obj.evTypes)) > 0));
            labels = unique(obj.evLabels(strlength(strtrim(obj.evLabels)) > 0));
            pos = obj.fig.Position;
            % tall window: a dropdown's list can only open inside its own window, so the empty space below
            % the fields lets the Type / Label lists show many rows
            dlg = uifigure('Name', sprintf('Add event at %s', obj.formatTime(t)), 'WindowStyle', 'modal', ...
                'Position', [pos(1) + pos(3)/2 - 240, pos(2) + pos(4)/2 - 200, 480, 400], 'Color', [235/255 235/255 250/255]);
            dlg.CloseRequestFcn = @(~,~) uiresume(dlg);
            g = uigridlayout(dlg, [5 2], 'RowHeight', {22, 26, 26, 30, '1x'}, 'ColumnWidth', {70, '1x'}, ...
                'BackgroundColor', [235/255 235/255 250/255]);
            hint = uilabel(g, 'Text', 'Pick an existing one or type a new one.');
            hint.Layout.Column = [1 2];
            uilabel(g, 'Text', 'Type');
            % the recording's own types/labels first, then the stored list from Settings, each under a divider
            % line (the dividers are not real choices: picking one just clears the box)
            sepRec = "-------- in this recording --------";
            sepSto = "-------- stored list (Settings) --------";
            stoTypes = reshape(string(obj.storedEvents(:, 1)), 1, []);
            stoLabels = reshape(string(obj.storedEvents(:, 2)), 1, []);
            typeItems = withDividers(reshape(types, 1, []), unique(stoTypes, 'stable'));
            labelItems = withDividers(reshape(labels, 1, []), unique(stoLabels(strlength(strtrim(stoLabels)) > 0), 'stable'));
            typeDD = uidropdown(g, 'Items', typeItems, 'Editable', 'on', 'Value', "", ...
                'Tooltip', '4-character code, e.g. eyeo, move, aslp');
            uilabel(g, 'Text', 'Label');
            labelDD = uidropdown(g, 'Items', labelItems, 'Editable', 'on', 'Value', "");
            typeDD.ValueChangedFcn = @(~,~) fillLabel();
            labelDD.ValueChangedFcn = @(~,~) fillType();
            buttons = uigridlayout(g, [1 2], 'Padding', [0 0 0 0], 'BackgroundColor', [235/255 235/255 250/255]);
            buttons.Layout.Column = [1 2];
            uibutton(buttons, 'Text', 'Add', 'BackgroundColor', [0.45 0.75 0.45], 'ButtonPushedFcn', @(~,~) finish(true));
            uibutton(buttons, 'Text', 'Cancel', 'BackgroundColor', [220/255 195/255 225/255], 'ButtonPushedFcn', @(~,~) finish(false));
            uiwait(dlg);
            if isvalid(dlg), delete(dlg); end
            figure(obj.fig);

            % IN: fromRec, fromStore = string rows   OUT: items = "" then each non-empty list under its divider
            function items = withDividers(fromRec, fromStore)
                items = "";
                if ~isempty(fromRec), items = [items, sepRec, fromRec]; end
                if ~isempty(fromStore), items = [items, sepSto, fromStore]; end
            end
            % a divider line was picked: clear the box (tf = true)
            function tf = clearIfDivider(dd)
                tf = any(string(dd.Value) == [sepRec, sepSto]);
                if tf, dd.Value = ""; end
            end
            % picking a type fills in a label: the stored one if the type is on the stored list,
            % otherwise the label most often used with it in this recording
            function fillLabel()
                if clearIfDivider(typeDD), return; end
                k = find(stoTypes == string(typeDD.Value), 1);
                if ~isempty(k) && strlength(strtrim(stoLabels(k))) > 0
                    labelDD.Value = stoLabels(k);
                    return
                end
                used = obj.evLabels(obj.evTypes == string(typeDD.Value));
                if ~isempty(used)
                    [names, ~, nameIdx] = unique(used);
                    labelDD.Value = names(mode(nameIdx));
                end
            end
            % picking a label fills in its type the same way: the stored type that has this label, otherwise
            % the type most often used with it in this recording (an empty box is left alone)
            function fillType()
                if clearIfDivider(labelDD), return; end
                lab = string(labelDD.Value);
                if strlength(strtrim(lab)) == 0, return; end
                k = find(stoLabels == lab, 1);
                if ~isempty(k)
                    typeDD.Value = stoTypes(k);
                    return
                end
                used = obj.evTypes(obj.evLabels == lab);
                if ~isempty(used)
                    [names, ~, nameIdx] = unique(used);
                    typeDD.Value = names(mode(nameIdx));
                end
            end
            function finish(accepted)
                if accepted
                    newType = strtrim(char(typeDD.Value));
                    if isempty(newType)
                        uialert(dlg, 'Give the event a type.', 'No type');
                        return
                    end
                    answer = {newType, strtrim(char(labelDD.Value))};
                end
                uiresume(dlg);
            end
        end
        % sort events, save _eventsEdited.set (next to the source file, when there is one), then release
        % runVideoEditor's uiwait
        function saveDataBack(obj)
            obj.stopPlayback();
            obj.saveChanges.Text = 'Saving....';
            drawnow;
            [~, ord] = sort([obj.EEG.event.latency]);
            obj.EEG.event = obj.EEG.event(ord);
            obj.EEG = eeg_checkset(obj.EEG, 'eventconsistency');
            % standalone use keeps its own copy; inside a BIPATE batch runVideoEditor saves _videoEdited instead
            inBatch = isappdata(0, 'bipateBatch') && getappdata(0, 'bipateBatch');
            if ~inBatch && ~isempty(obj.EEG.filepath) && ~isempty(obj.EEG.filename)
                pop_saveset(obj.EEG, 'filename', [strrep(obj.EEG.filename,'.set','') '_eventsEdited.set'], 'filepath', obj.EEG.filepath);
            end
            obj.saved = true;
            obj.saveChanges.Text = 'SAVED ✓';
            pause(1);
            uiresume(obj.fig);
        end
        % window X: save and exit, exit without saving (events go back to how they were), or keep editing
        function onCloseRequest(obj)
            if ~obj.saved && isfield(obj.EEG.etc, 'eventBackup')
                choice = uiconfirm(obj.fig, 'Save the event changes before closing?', 'Close video editor', ...
                    'Options', {'Save & exit', 'Exit without saving', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3);
                switch choice
                    case 'Save & exit'
                        obj.saveDataBack();
                        return
                    case 'Cancel'
                        return
                end
                obj.EEG.event = obj.EEG.etc.eventBackup;
                obj.EEG.etc = rmfield(obj.EEG.etc, 'eventBackup');
            end
            obj.stopPlayback();
            uiresume(obj.fig);
            delete(obj.fig);
        end
        % OUT: tf = true when the events differ from how they were when the editor opened
        %      (EEG.etc.eventBackup is made on the first edit, so no backup = nothing was touched)
        function tf = eventsChanged(obj)
            if ~isfield(obj.EEG.etc, 'eventBackup')
                tf = false;
                return
            end
            tf = ~isequal(VideoEditorApp.eventKeys(obj.EEG.event), VideoEditorApp.eventKeys(obj.EEG.etc.eventBackup));
        end
        % stops the timer and the sound
        function stopPlayback(obj)
            if ~isempty(obj.playTimer) && isvalid(obj.playTimer)
                stop(obj.playTimer);
            end
            obj.Paused = true;
            if ~isempty(obj.playPause) && isvalid(obj.playPause), obj.playPause.Text = 'PLAY'; end
            obj.stopAudio();
        end
        % keyboard: space = play/pause, Delete/Backspace = delete the selected event
        function onKey(obj, evt)
            focusObj = obj.fig.CurrentObject;
            if isa(focusObj, 'matlab.ui.control.NumericEditField') || isa(focusObj, 'matlab.ui.control.EditField') ...
                    || isa(focusObj, 'matlab.ui.control.Button') || isa(focusObj, 'matlab.ui.control.DropDown')
                return   % typing in a box, or a focused button that handles the key itself
            end
            switch evt.Key
                case 'space'
                    obj.pauseBtn();
                case {'delete', 'backspace'}
                    if ~isempty(obj.selectedEvent), obj.deleteEvent(); end
            end
        end
        % sample rate and length of each video's sound track (hasAudio false if it has none or can't be read)
        function readAudioInfo(obj)
            if obj.noVideo   % no sound: the Sound box comes up unticked and greyed out
                obj.audioInfo = struct('SampleRate', {}, 'TotalSamples', {}, 'hasAudio', {});
                return
            end
            nVid = numel(obj.manifest.videoProps);
            obj.audioInfo = struct('SampleRate', cell(1, nVid), 'TotalSamples', 0, 'hasAudio', false);
            for v = 1:nVid
                try
                    info = audioinfo(char(obj.manifest.videoProps(v).file));
                    obj.audioInfo(v).SampleRate = info.SampleRate;
                    obj.audioInfo(v).TotalSamples = info.TotalSamples;
                    obj.audioInfo(v).hasAudio = info.TotalSamples > 0;
                catch
                    obj.audioInfo(v).hasAudio = false;
                end
            end
        end
        % (re)starts the sound at the current time when playing with Sound ticked; otherwise stops it.
        % Reads 30 s of the covering video's sound track from that point and plays it; onTick calls this
        % again when the chunk runs out.
        function syncAudio(obj)
            obj.stopAudio();
            if obj.noVideo || obj.Paused || isempty(obj.soundCheck) || ~obj.soundCheck.Value, return; end
            [videoSec, segIdx, covered] = videoTimeFromEEG(obj.manifest.sync, obj.eegSec);
            if ~covered || ~obj.audioInfo(segIdx).hasAudio
                obj.audioChunkEnd = obj.eegSec + 1;   % try again in a second
                return
            end
            info = obj.audioInfo(segIdx);
            chunkSec = 30;
            first = max(1, floor(videoSec * info.SampleRate) + 1);
            last = min(info.TotalSamples, first + chunkSec * info.SampleRate - 1);
            if last <= first, obj.audioChunkEnd = Inf; return; end
            try
                soundChunk = audioread(char(obj.manifest.videoProps(segIdx).file), [first last]);   % double, -1..1
                gain = 1;
                if ~isempty(obj.volumeSlider), gain = obj.volumeSlider.Value; end
                soundChunk = min(max(soundChunk * gain, -1), 1);   % scale, then clip so loud parts can't wrap around
            catch
                obj.audioInfo(segIdx).hasAudio = false;
                return
            end
            obj.player = audioplayer(soundChunk, info.SampleRate);
            play(obj.player);
            obj.audioChunkEnd = obj.eegSec + (last - first + 1) / info.SampleRate;
        end
        function stopAudio(obj)
            if ~isempty(obj.player)
                stop(obj.player);
            end
            obj.player = [];
            obj.audioChunkEnd = -Inf;
        end
        % delete the selected event after a confirm
        function deleteEvent(obj)
            idx = obj.selectedEvent;
            if isempty(idx), return; end
            
            sel = uiconfirm(obj.fig, ...
                sprintf('Delete event "%s" at %s?', obj.evLabels(idx), obj.formatTime(obj.evTimes(idx))), ...
                'Confirm delete', 'Options', {'Yes','No'}, 'DefaultOption','No', 'CancelOption','No');
            if strcmp(sel, 'No'), return; end
            obj.ensureBackup();
            obj.EEG.event(idx) = [];
            obj.syncEventLists();   % evTimes / evTypes / evLabels from EEG.event
            obj.clearSelection();
            obj.refreshMarkers();
        end
        % destructor: stop and remove the playback timer and the sound, close the window if still open
        function delete(obj)
            obj.stopAudio();
            if ~isempty(obj.playTimer) && isvalid(obj.playTimer)
                stop(obj.playTimer);
                delete(obj.playTimer);
            end
            if ~isempty(obj.fig) && isvalid(obj.fig)
                delete(obj.fig);
            end
        end
 
            
    end
    methods (Static)
        % IN:  ev = stored event list, n x 2 {type, label} or n x 3 {type, label, color}; color = '#RRGGBB'
        %      or a MATLAB color letter (r g b c m y k w)
        % OUT: out = n x 3 cellstr, every color as '#RRGGBB' (missing ones black)
        %      bad = rows whose color could not be read (left black in out)
        function [out, bad] = normEvents(ev)
            bad = [];
            if isempty(ev), out = cell(0, 3); return; end
            out = cellfun(@(x) strtrim(char(string(x))), ev, 'UniformOutput', false);
            if size(out, 2) < 3, out(:, 3) = {''}; end
            out = out(:, 1:3);
            letters = 'rgbcmykw';
            hexes = {'#FF0000', '#00FF00', '#0000FF', '#00FFFF', '#FF00FF', '#FFFF00', '#000000', '#FFFFFF'};
            for r = 1:size(out, 1)
                c = out{r, 3};
                if isempty(c)
                    out{r, 3} = '#000000';
                elseif isscalar(c) && any(letters == lower(c))
                    out{r, 3} = hexes{letters == lower(c)};
                elseif ~isempty(regexp(c, '^#?[0-9A-Fa-f]{6}$', 'once'))
                    out{r, 3} = ['#' upper(erase(c, '#'))];
                else
                    out{r, 3} = '#000000';
                    bad(end + 1) = r; %#ok<AGROW>
                end
            end
        end
        % IN: hex = '#RRGGBB'   OUT: rgb = 1 x 3, values 0..1
        function rgb = hexToRGB(hex)
            rgb = double(hex2dec({hex(2:3); hex(4:5); hex(6:7)}))' / 255;
        end
        % IN: ev = EEG.event struct array   OUT: keys = sorted cellstr, one "latency|type|label" per event (order-free)
        function keys = eventKeys(ev)
            keys = cell(numel(ev), 1);
            for n = 1:numel(ev)
                lab = '';
                if isfield(ev, 'label'), lab = char(string(ev(n).label)); end
                keys{n} = sprintf('%.3f|%s|%s', ev(n).latency, char(string(ev(n).type)), lab);
            end
            keys = sort(keys);
        end
    end
end
