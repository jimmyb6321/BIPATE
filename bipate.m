% bipate - Bespoke Integrative Preprocessing and Analysis Toolbox for EEG (BIPATE)
% Author: James Barlow
% Created: 09/01/2026
% Last updated: 10/25/2026
%
% Batch app for the hdEEG preprocessing pipeline. Add recordings ("sets") on the right, pick jobs on the
% left and put them in order, choose an output folder, then Run batch. Every set goes through the jobs in
% order. The Job plan window turns single jobs off for single sets and can make a job use the same
% settings for every set. Every job can run more than once; each run is numbered (stepRound).
%
% obj.queue holds the sets; the set grid only shows it and is rebuilt by refresh().
% obj.jobs holds the job ids in run order; obj.jobOn (sets x jobs) and obj.shareOn (1 x jobs) hold the
% job plan ticks.
% A run has a name and an id. Pressing Run batch again can continue that run (each set picks up at the
% job it stopped at) or start a new one. Runs are saved to <userpath>\BIPATE_user\batch_history and
% listed in the History dropdown.
%
% Launch: type bipate in the Command Window.


classdef bipate < handle
    properties
        f
        mainColor = [220/255, 208/255, 255/255]
        buttonColor = [0.82 0.79 0.92]
        setColumnWidths = {70, 60, 190, 40, 105, 55, 40, 22}   % set list columns after Recording

        % layout grids
        g
        gTitle
        gHeader
        gBody
        gSetTit
        gSetTopBut
        gSet
        addSet
        remSet
        gJobTit
        gJobTopBut
        gJob
        rightAdmin
        leftAdmin
        gMethodTit
        gMethodBut
        gMethod

        % controls
        methodList      % every job in the catalog
        methodInfo      % description of the highlighted job
        jobList         % the chosen jobs, in run order
        outLabel        % output folder path
        runLabel        % "Run: <name>" in the header (set by showRunName)
        sameOptsCB      % use row 1 options for every set
        saveEndCB               % main-window box: save only at the end of each set
        runBut
        stopBut
        histDD          % batch history dropdown
        planTable       % table in the Job plan window (empty when the window is closed)
        planNotes       % text box under it listing blocked jobs

        sameOpts        % true = row 1's options apply to every set
        cfg
    end

    properties (SetAccess = private, GetAccess = public)
        queue
        selected
        jobs                    % 1 x nJobs string of job ids, run order
        catalog                 % from jobCatalog (jobs.json)
        jobOn                   % nSets x nJobs logical, job plan ticks
        shareOn                 % 1 x nJobs logical, same settings for every set
        outRoot = ''
        runId = ''              % id of the current run (yyyyMMdd_HHmmss), '' before the first run
        runName = ''
        runStart = ''
        saveAtEnd = false       % true = each set is saved once, at the end of its jobs (saveStep / flushSet)
        runStartFile = ''         % set the current set started this run from (see saveProgress)
        progress                % containers.Map: sessionID -> how far the run got on that set
        rerunFrom               % containers.Map: sessionID -> job number to redo from (Rerun in the job plan)
        running = false
        stopRequested = false
        closeAfterStop = false
        statusFig = []          % small "BIPATE is running" window: current set, job, progress, Stop
        statusText = []
        statusGauge = []
        statusStop = []
        statusTime = []         % "Running for ... | batch done about HH:mm" line, ticked by statusTimer
        statusTimer = []
        runTic = []             % tic when Run batch was pressed
        etaText = ''            % "batch done about HH:mm" (clock time), set by showStatus
        batchSummary = ''       % end-of-batch summary; finishRun shows it once BIPATE is back in front
        savedAfter = {}         % per set, "save only at the end" mode: the file each job really wrote ('' = none)
    end

    methods (Access = public)
        function obj = bipate
            bipate.addRepoPaths();      % every folder under <repo>\functions onto the path, so nothing is added by hand
            obj.buildUI();
            obj.sameOpts = false;
            obj.selected = false(0, 1);
            obj.jobs = strings(1, 0);
            obj.jobOn = false(0, 0);
            obj.shareOn = false(1, 0);
            obj.progress = containers.Map('KeyType', 'char', 'ValueType', 'any');
            obj.rerunFrom = containers.Map('KeyType', 'char', 'ValueType', 'double');
            try
                obj.cfg = cfg_init;
                obj.queue = blankEntry(obj.cfg, true);
                obj.catalog = jobCatalog;
            catch ME
                uialert(obj.f, ME.message, 'Could not load the configuration or job list', 'Icon', 'error');
                return
            end
            if ~isfile(fullfile(obj.cfg.paths.userPath, 'userInfo.mat'))   % new user / fresh clone
                if ~isempty(firstLaunch(obj.cfg.paths.userPath, string(obj.cfg.paths.eeglab)))
                    obj.cfg = cfg_init;   % pick up the saved name and EEGLAB folder
                end
                figure(obj.f);
            end
            obj.buildJobUI();
            obj.refresh();
            obj.refreshJobs();
            obj.fitSetColumns();
            obj.saveAtEnd = isfield(obj.cfg.general, 'saveMode') && strcmp(obj.cfg.general.saveMode, 'Once per set, at the end');
            obj.saveEndCB.Value = obj.saveAtEnd;   % starting value from Settings > General
            obj.f.CloseRequestFcn = @(~, ~) obj.onClose();
            if isfield(obj.cfg, 'general') && ~isempty(obj.cfg.general.outRoot) && isfolder(obj.cfg.general.outRoot)
                obj.setOutputFolder(obj.cfg.general.outRoot);   % default from Settings > General
            end
            if obj.checkEEGLABPath()      % asks for the EEGLAB folder the first time
                obj.startEEGLAB();            % EEGLAB + its plugins on the path now, not at the first Run
            end
        end

        function obj = addFiles(obj, paths)
            % adds recordings to the queue without the file pickers (Add set uses this; so can a script,
            % e.g. app.addFiles({'D:\data\R001.mff', 'D:\data\R002.mff'}))
            % IN: paths = char, string or cellstr of full paths (recording files or .mff folders)
            paths = cellstr(string(paths));
            for p = 1:numel(paths)
                qf = paths{p};
                thisSize = numel(obj.queue);
                try
                    qQue = blankEntry(obj.cfg);
                    ent = deriveEntry(qQue, qf, obj.cfg);
                    ent.state.doneJobs = inputHistory(qf);   % a .set BIPATE already processed brings its done jobs into the job plan
                    obj.queue = queueAdd(obj.queue, ent);
                catch ME
                    uialert(obj.f, ME.message, 'Could not add set', 'Icon', 'error');
                    continue
                end
                newSize = numel(obj.queue);
                if newSize == thisSize
                    uialert(obj.f, sprintf('%s was not added: it is already in the queue, or its entry does not match the queue template.', qf), ...
                        'Set not added', 'Icon', 'warning');
                    continue
                end
                if strcmp(ent.state.status, 'failed')
                    uialert(obj.f, sprintf('%s was added but cannot be processed: %s', qf, ent.state.message), ...
                        'Set flagged', 'Icon', 'warning');
                end
                %check select boxes vs queue size
                if newSize - thisSize > 0
                    obj.selected(end+1:newSize) = false;
                    obj.jobOn(end+1:newSize, :) = true;
                elseif newSize - thisSize < 0
                    uialert(obj.f, ...
                        "ERROR: critical indexing error, please restart the program!", ...
                        "Code bug", "Icon","error");
                    continue
                end
            end
            obj.refresh;
            obj.refreshJobs();
        end

        function obj = setOutputFolder(obj, folder)
            % sets the output root (the Output folder button uses this); every set writes to <folder>\<sessionID>
            folder = char(folder);
            if any(contains(split(string(folder), filesep), '.mff'))
                uialert(obj.f, 'The output folder cannot be inside a .mff recording. Pick a folder outside it.', ...
                    'Output folder', 'Icon', 'warning');
                return
            end
            obj.outRoot = folder;
            obj.outLabel.Text = folder;
            obj.outLabel.FontAngle = 'normal';
            obj.syncDone();
            obj.refreshJobs();
        end
    end

    methods (Access = private)
        function buildUI(obj)
            % static layout:
            %   row 1  title bar: title | batch history
            %   row 2  header: output folder | same options
            %   row 3  body: left = available jobs, right = sets (top) and chosen jobs (bottom)
            scr = get(groot, 'ScreenSize');
            obj.f = uifigure("Name", 'BIPATE', "Position", [scr(3) * 0.1, scr(4) * 0.1, scr(3) * 0.75, scr(4) * 0.75], ...
                "Color", obj.mainColor, "AutoResizeChildren", 'off', "SizeChangedFcn", @(~, ~) obj.fitSetColumns());
            obj.g = uigridlayout(obj.f, "BackgroundColor", obj.mainColor - 10/255, "RowSpacing", 6, "Padding", [8 8 8 8]);
            obj.g.ColumnWidth = {'1x'};
            obj.g.RowHeight = {34, 30, '1x'};
            stripColor = obj.mainColor - [20/255, 20/255, 0];

            obj.gTitle = uigridlayout(obj.g, [1 4], "BackgroundColor", stripColor, "Padding", [8 2 8 2], "ColumnSpacing", 8);
            obj.gTitle.ColumnWidth = {'1x', '1x', 'fit', 420};   % title | run name (centre) | History | dropdown
            obj.gTitle.Layout.Row = 1;
            titleLabel = uilabel(obj.gTitle, "Text", "BIPATE Toolbox", "FontSize", 18, "FontWeight", 'bold');
            titleLabel.Layout.Row = 1;
            titleLabel.Layout.Column = 1;

            obj.gHeader = uigridlayout(obj.g, [1 4], "BackgroundColor", stripColor, "Padding", [8 2 8 2], "ColumnSpacing", 8);
            obj.gHeader.Layout.Row = 2;

            obj.gBody = uigridlayout(obj.g, [5 2], "BackgroundColor", stripColor, "RowSpacing", 6, "ColumnSpacing", 8, ...
                "Padding", [6 6 6 6]);
            obj.gBody.ColumnWidth = {'0.5x', '1x'};
            obj.gBody.RowHeight = {28, '3x', 28, '2x', 30};
            obj.gBody.Layout.Row = 3;

            % right: sets
            obj.gSetTopBut = obj.makeStrip(1, 2, {'1x', 85, 100, 80, 90});
            obj.gSetTit = uilabel(obj.gSetTopBut, "Text", "Sets to process", "FontSize", 14, "FontWeight", 'bold');
            obj.gSetTit.Layout.Row = 1;
            obj.gSetTit.Layout.Column = 1;
            obj.addSet = obj.makeButton(obj.gSetTopBut, 2, 'Add set', @(~, ~) obj.addNewSet());
            obj.remSet = obj.makeButton(obj.gSetTopBut, 3, 'Remove set', @(~, ~) obj.removeSet());
            obj.gSet = uigridlayout(obj.gBody, "BackgroundColor", [200/255, 200/255, 200/255], "Scrollable", "on", ...
                "RowSpacing", 3, "ColumnSpacing", 6, "Padding", [6 4 6 4]);
            % name | pptID | time point | cap | file type | artifacts | status | info | select
            obj.gSet.ColumnWidth = [{200}, obj.setColumnWidths];
            obj.gSet.RowHeight = {20};
            obj.gSet.Layout.Row = 2;
            obj.gSet.Layout.Column = 2;

            % right: chosen jobs
            obj.gJobTopBut = obj.makeStrip(3, 2, {'1x', 85, 70, 80, 70, 80});
            obj.gJobTit = uilabel(obj.gJobTopBut, "Text", "Jobs to run (in order)", "FontSize", 14, "FontWeight", 'bold');
            obj.gJobTit.Layout.Row = 1;
            obj.gJobTit.Layout.Column = 1;
            obj.gJob = uigridlayout(obj.gBody, [1 1], "BackgroundColor", [200/255, 200/255, 200/255], "Padding", [4 4 4 4]);
            obj.gJob.Layout.Row = 4;
            obj.gJob.Layout.Column = 2;
            obj.rightAdmin = obj.makeStrip(5, 2, {'1x', '1x', '1x', '1x'});

            % left: available jobs
            obj.gMethodBut = obj.makeStrip(1, 1, {'1x', 80, 115});
            obj.gMethodTit = uilabel(obj.gMethodBut, "Text", "Jobs available", "FontSize", 14, "FontWeight", 'bold');
            obj.gMethodTit.Layout.Row = 1;
            obj.gMethodTit.Layout.Column = 1;
            obj.gMethod = uigridlayout(obj.gBody, [2 1], "BackgroundColor", obj.mainColor - [0, 50/255, 0], ...
                "RowSpacing", 4, "Padding", [4 4 4 4]);
            obj.gMethod.Layout.Row = [2, 4];
            obj.gMethod.Layout.Column = 1;
            obj.leftAdmin = obj.makeStrip(5, 1, {'1x', '1x', '1x'});
        end

        function strip = makeStrip(obj, row, col, widths)
            % one-row strip of buttons in obj.gBody
            strip = uigridlayout(obj.gBody, [1 numel(widths)], "BackgroundColor", obj.mainColor - [0, 50/255, 0], ...
                "Padding", [4 2 4 2], "ColumnSpacing", 6);
            strip.ColumnWidth = widths;
            strip.RowHeight = {'1x'};
            strip.Layout.Row = row;
            strip.Layout.Column = col;
        end

        function fitSetColumns(obj)
            % the Recording column takes whatever the other set columns leave, but never less than
            % minName pixels; below that the set list scrolls sideways instead of squashing the names
            if isempty(obj.gSet) || ~isvalid(obj.gSet), return; end
            minName = 200;
            drawnow limitrate
            otherCols = obj.setColumnWidths;
            used = sum([otherCols{:}]) + obj.gSet.ColumnSpacing * numel(otherCols) + sum(obj.gSet.Padding([1 3])) + 18;
            obj.gSet.ColumnWidth = [{max(minName, obj.gSet.Position(3) - used)}, otherCols];
        end

        function button = makeButton(obj, parent, col, text, callback)
            % standard app button, placed in column col of a one-row strip
            button = uibutton(parent, "BackgroundColor", obj.buttonColor, "Text", text, "FontSize", 12, ...
                "ButtonPushedFcn", callback);
            button.Layout.Row = 1;
            button.Layout.Column = col;
        end

        function refresh(obj)
            % IN: obj.queue (1 x n) and obj.selected (n x 1). Deletes every widget tagged 'setRow' in obj.gSet and
            % redraws a header row plus one row per queue entry (grid row i + 1); columns: 1 name, 2 pptID,
            % 3 time point, 4 cap type, 5 file type, 6 artifact mode, 7 status, 8 info, 9 select
            delete(findobj(obj.gSet, 'Tag', 'setRow')) % clear gSet
            n = numel(obj.queue);
            % last row takes the leftover space so the rows sit at the top; a grid row with nothing in it
            % collapses, so it holds an empty label
            obj.gSet.RowHeight = [{20}, repmat({26}, 1, n), {'1x'}];
            spacer = uilabel(obj.gSet, 'Text', '', 'Tag', 'setRow');
            spacer.Layout.Row = n + 2;
            spacer.Layout.Column = 1;
            capItems = obj.cfg.recording.caplist;
            capLabels = cellfun(@(c) shortLabel(c, 26), capItems, 'UniformOutput', false);
            artItems = {'Manual', 'Semi-automatic'};

            % column headers (grid row 1)
            heads = {'Recording', 'pptID', 'Time point', 'Cap', 'Type', 'Artifacts', 'Status', '', ''};
            for h = 1:numel(heads)
                c = uilabel(obj.gSet, 'Text', heads{h}, 'FontWeight', 'bold', 'FontSize', 11, 'Tag', 'setRow');
                c.Layout.Row = 1; c.Layout.Column = h;
            end

            for i = 1:n % build
                e = obj.queue(i);
                r = i + 1;                                   % grid row (row 1 holds the headers)
                %set name (full path on hover)
                c = uilabel(obj.gSet, 'Text', [e.identity.fileName e.identity.inputFormat], 'Tag', 'setRow', ...
                    'Tooltip', e.identity.filePath);
                c.Layout.Row = r; c.Layout.Column = 1;
                if strcmp(e.state.status, 'failed'), c.FontColor = [0.8 0 0]; c.Tooltip = e.state.message; end

                % pptID
                c = uieditfield(obj.gSet, 'text', 'Value', e.identity.pptID, 'Tag', 'setRow', ...
                    'ValueChangedFcn', @(src, ~) obj.onPptEdit(i, src));
                c.Layout.Row = r; c.Layout.Column = 2;

                % time point
                timeIP = uieditfield(obj.gSet, 'text', 'Value', e.identity.timePoint, 'Tag', 'setRow', ...
                    'ValueChangedFcn', @(src, ~) obj.onTimeEdit(i, src));
                timeIP.Layout.Row = r; timeIP.Layout.Column = 3;

                % cap type (short name shown, full name on hover)
                % a cap no longer in the list (custom cap renamed or deleted) is shown as such, not silently swapped
                capVal = char(e.opts.recording.cap_type);
                rowCapItems = capItems;
                rowCapLabels = capLabels;
                if ~ismember(capVal, capItems)
                    rowCapItems = [{capVal}, capItems(:)'];
                    rowCapLabels = [{['(not saved) ' shortLabel(capVal, 14)]}, capLabels(:)'];
                end
                capDD = uidropdown(obj.gSet, 'Items', rowCapLabels, 'ItemsData', rowCapItems, 'Value', capVal, ...
                    'Tooltip', capVal, 'Tag', 'setRow', 'ValueChangedFcn', @(src, ~) obj.onCapChange(i, src));
                capDD.Layout.Row = r; capDD.Layout.Column = 4;

                % File type
                c = uilabel(obj.gSet, 'Text', e.identity.inputFormat, 'Tag', 'setRow');
                c.Layout.Row = r; c.Layout.Column = 5;

                %artifact mode
                artVal = e.opts.artifact.mode; if ~ismember(artVal, artItems), artVal = artItems{1}; end
                artDD = uidropdown(obj.gSet, 'Items', artItems, 'Value', artVal, 'Tag', 'setRow', ...
                    'ValueChangedFcn', @(src, ~) obj.onArtChange(i, src));
                artDD.Layout.Row = r; artDD.Layout.Column = 6;

                % status (red + reason on hover when failed)
                stac = uilabel(obj.gSet, 'Text', e.state.status, 'Tag', 'setRow');
                stac.Layout.Row = r; stac.Layout.Column = 7;
                if strcmp(e.state.status, 'failed'), stac.FontColor = [0.8 0 0]; stac.Tooltip = e.state.message; end

                %more info
                c = uibutton(obj.gSet, 'Text', 'info', 'Tag', 'setRow', 'FontSize', 11, 'BackgroundColor', obj.buttonColor, ...
                    'ButtonPushedFcn', @(~, ~) obj.onInfo(i));
                c.Layout.Row = r; c.Layout.Column = 8;

                % select (for Remove set)
                cb = uicheckbox(obj.gSet, "Text", "", "Value", obj.selected(i), 'Tag', 'setRow', ...
                    "ValueChangedFcn", @(src, ~) obj.checkcheck(src, i));
                cb.Layout.Row = r; cb.Layout.Column = 9;

                if obj.sameOpts && i > 1
                    capDD.Enable = 'off'; artDD.Enable = 'off';
                end
            end
            if obj.running   % nothing editable while a batch runs
                set(findobj(obj.gSet, 'Tag', 'setRow', '-property', 'Enable'), 'Enable', 'off');
            end
        end

        function obj = onTimeEdit(obj, i, src)
            % timePoint callback (row i): store src.Value in
            % queue(i).identity.timePoint
            obj.queue(i).identity.timePoint = src.Value;
            obj.syncDone();
            obj.refreshJobs();
        end
        function obj = onCapChange(obj, i, src)
            % cap dropdown callback (row i): store src.Value in 
            % queue(i).opts.recording.cap_type
            obj.queue(i).opts.recording.cap_type = src.Value;
            src.Tooltip = src.Value;
        end

        function obj = onPptEdit(obj, i, src)
            % pptID edit-field callback (row i): store src.Value in 
            % queue(i).identity.pptID
            obj.queue(i).identity.pptID = src.Value;
            obj.syncDone();
            obj.refreshJobs();
        end

        function obj = onArtChange(obj, i, src)
            % artifact-mode dropdown callback (row i): store src.Value in 
            % queue(i).opts.artifact.mode
            obj.queue(i).opts.artifact.mode = src.Value;
        end
        function obj = onInfo(obj, i)
            % info button callback (row i): pop-up listing that entry's 
            % identity, options and state
            message = {['PPT ID: ' obj.queue(i).identity.pptID], ...
                ['File: ' obj.queue(i).identity.filePath], ...
                ['Time Point: ' obj.queue(i).identity.timePoint], ...
                ['Input Format: ' obj.queue(i).identity.inputFormat], ...
                ['Session: ' obj.queue(i).identity.sessionID], ...
                ['Cap Type: ' obj.queue(i).opts.recording.cap_type], ...
                ['Artifact Mode: ' obj.queue(i).opts.artifact.mode], ...
                ['ICA: ' obj.queue(i).opts.ica.method], ...
                ['Status: ' obj.queue(i).state.status], ...
                ['Message: ' obj.queue(i).state.message], ...
                ['Output Directory: ' obj.queue(i).state.outDir]};
            uialert(obj.f, message, obj.queue(i).identity.pptID, 'Icon', 'info')

        end
        function obj = addNewSet(obj)
            % adds new set into the set box
            % .mff recordings are folders, so ask first which picker to 
            % open (uigetdir vs uigetfile)

            mffcon = uiconfirm(obj.f, "If data is not .mff, select 'Other File'", "File type", "Options", ...
                {'.mff folder', 'Other file', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3);
            if strcmpi(mffcon, '.mff folder')
                fdir = uigetdir;
                figure(obj.f);   % the picker leaves the app behind other windows; bring it back
                if fdir == 0
                    return;
                end
                qf = fdir;
                % a folder holding .mff recordings (not an .mff itself): pick which to add; two or more picked
                % = one set made of those recordings joined in recording order (e.g. Net Station restarted
                % mid-session). Stored as their paths joined by "|"; loadData_max joins the recordings.
                if ~isfile(fullfile(fdir, 'info.xml'))
                    kids = dir(fullfile(fdir, '*.mff'));
                    kids = kids([kids.isdir] & arrayfun(@(k) isfile(fullfile(k.folder, k.name, 'info.xml')), kids)');
                    if isempty(kids)
                        uialert(obj.f, sprintf('%s is not an .mff recording and holds none.', fdir), 'No .mff found');
                        return
                    end
                    [pick, ok] = listdlg('PromptString', {'Pick the recording(s) for this set.', ...
                        'Pick two or more to join them into one set,', 'in recording order.'}, ...
                        'ListString', {kids.name}, 'SelectionMode', 'multiple', 'ListSize', [360 260], 'Name', '.mff recordings');
                    figure(obj.f);
                    if ~ok || isempty(pick), return; end
                    qf = strjoin(fullfile(fdir, {kids(pick).name}), '|');
                end
            elseif strcmpi(mffcon, 'Other file')
                exts = string(obj.cfg.recording.inputTypes([2, 3, 5, 6]));   % .set .edf .eeg .nxe
                goodF = [{strjoin("*" + exts, ';'), ['EEG files (' char(strjoin(exts, ', ')) ')']}; ...
                    cellstr("*" + exts(:)), cellstr(exts(:) + " files")];   % all four first, then each on its own
                [qfile, fdir] = uigetfile(goodF, 'Pick an EEG file');
                figure(obj.f);
                if qfile == 0
                    return;
                end
                qf = fullfile(fdir, qfile);
            else
                return;
            end
            obj.addFiles(qf);

        end

        function obj = checkcheck(obj, src, i)
            % select-checkbox callback (row i): copy the tick into obj.selected(i)
            obj.selected(i) = src.Value;
        end

        function obj = removeSet(obj)
            % removes all selected sets
            if ~any(obj.selected)
                uialert(obj.f, 'Tick the sets you want to remove first.', 'Nothing selected', 'Icon', 'info');
                return
            end
            try
                obj.queue = queueRemove(obj.queue, obj.selected);
            catch ME
                uialert(obj.f, ME.message, 'Could not remove sets', 'Icon', 'error');
                return
            end
            obj.jobOn(obj.selected, :) = [];
            obj.selected = false(numel(obj.queue), 1);
            obj.refresh;
            obj.refreshJobs();
        end


        %% Job lists and controls

        function buildJobUI(obj)
            % controls that need the job catalog: history, header, job lists and their buttons

            historyLabel = uilabel(obj.gTitle, "Text", 'History:', "HorizontalAlignment", 'right');
            historyLabel.Layout.Row = 1;
            historyLabel.Layout.Column = 3;
            obj.histDD = uidropdown(obj.gTitle, "Items", {'Recent batches'}, "ItemsData", {''}, "Value", '', ...
                "ValueChangedFcn", @(src, ~) obj.onHistory(src));
            obj.histDD.Layout.Row = 1;
            obj.histDD.Layout.Column = 4;

            obj.gHeader.ColumnWidth = {100, '1x', 'fit', 'fit'};
            obj.makeButton(obj.gHeader, 1, 'Output folder', @(~, ~) obj.pickOutRoot());
            obj.outLabel = uilabel(obj.gHeader, "Text", '(choose where the processed sets go)', "FontAngle", 'italic');
            obj.outLabel.Layout.Row = 1;
            obj.outLabel.Layout.Column = 2;
            obj.sameOptsCB = uicheckbox(obj.gHeader, "Text", 'Use row 1 options for every set', "Value", obj.sameOpts, ...
                "ValueChangedFcn", @(src, ~) obj.onSameOpts(src));
            obj.sameOptsCB.Layout.Row = 1;
            obj.sameOptsCB.Layout.Column = 3;
            obj.saveEndCB = uicheckbox(obj.gHeader, "Text", 'Save only at the end of each set', "Value", false, ...
                "Tooltip", 'Steps keep their results in memory and each set is written once, when its jobs end (or it stops or fails). Saves disk space; Rerun can then only go back to files that exist.', ...
                "ValueChangedFcn", @(src, ~) obj.onSaveAtEnd(src));
            obj.saveEndCB.Layout.Row = 1;
            obj.saveEndCB.Layout.Column = 4;
            obj.runLabel = uilabel(obj.gTitle, "Text", 'Run: (none yet)', "FontSize", 16, "FontWeight", 'bold', ...
                "FontAngle", 'italic', "HorizontalAlignment", 'center');   % centre of the title strip
            obj.runLabel.Layout.Row = 1;
            obj.runLabel.Layout.Column = 2;

            obj.makeButton(obj.gMethodBut, 2, 'Add job(s)', @(~, ~) obj.addJobs());
            obj.makeButton(obj.gMethodBut, 3, 'Add pipeline', @(~, ~) obj.addAllJobs());
            obj.gMethod.RowHeight = {'1x', 84};
            obj.methodList = uilistbox(obj.gMethod, "Items", {}, "Multiselect", 'on', ...
                "ValueChangedFcn", @(src, ~) obj.showJobInfo(src));
            obj.methodList.Layout.Row = 1;
            obj.methodList.Layout.Column = 1;
            obj.methodInfo = uitextarea(obj.gMethod, "Editable", 'off', "WordWrap", 'on', "FontSize", 11, ...
                "Value", {'Select a job to see what it does and what it needs.'});
            obj.methodInfo.Layout.Row = 2;
            obj.methodInfo.Layout.Column = 1;
            obj.fillMethodList();

            obj.makeButton(obj.gJobTopBut, 2, 'Remove job', @(~, ~) obj.removeJob());
            obj.makeButton(obj.gJobTopBut, 3, 'Move up', @(~, ~) obj.moveJob(-1));
            obj.makeButton(obj.gJobTopBut, 4, 'Move down', @(~, ~) obj.moveJob(1));
            obj.makeButton(obj.gJobTopBut, 5, 'Clear all', @(~, ~) obj.clearJobs());
            obj.makeButton(obj.gJobTopBut, 6, 'Job plan', @(~, ~) obj.showPlan());
            obj.jobList = uilistbox(obj.gJob, "Items", {}, "Multiselect", 'off');
            obj.jobList.Layout.Row = 1;
            obj.jobList.Layout.Column = 1;

            obj.makeButton(obj.gSetTopBut, 4, 'Select all', @(~, ~) obj.selectAll(true));
            obj.makeButton(obj.gSetTopBut, 5, 'Select none', @(~, ~) obj.selectAll(false));

            obj.runBut = obj.makeButton(obj.rightAdmin, 1, 'Run batch', @(~, ~) obj.runBatch());
            obj.runBut.BackgroundColor = [0.45 0.75 0.45];
            obj.runBut.FontWeight = 'bold';
            obj.stopBut = obj.makeButton(obj.rightAdmin, 2, 'Stop', @(~, ~) obj.requestStop());
            obj.stopBut.BackgroundColor = [0.85 0.5 0.5];
            obj.stopBut.Enable = 'off';
            obj.makeButton(obj.rightAdmin, 3, 'Save batch', @(~, ~) obj.saveBatch());
            obj.makeButton(obj.rightAdmin, 4, 'Load batch', @(~, ~) obj.loadBatch());
            obj.makeButton(obj.leftAdmin, 1, 'Reload jobs', @(~, ~) obj.reloadCatalog());
            obj.makeButton(obj.leftAdmin, 2, 'Edit jobs', ...
                @(~, ~) edit(fullfile(fileparts(which('jobCatalog')), 'jobs.json')));
            obj.makeButton(obj.leftAdmin, 3, 'Settings', @(~, ~) settingsWindow(@() obj.reloadSettings()));

            obj.refreshHistory();
        end

        function fillMethodList(obj)
            % fills the available-jobs list from the catalog
            labels = {obj.catalog.label};
            isInteractive = [obj.catalog.interactive];
            labels(isInteractive) = strcat(labels(isInteractive), ' (interactive)');
            obj.methodList.Items = labels;
            obj.methodList.ItemsData = {obj.catalog.id};
        end

        function obj = showJobInfo(obj, src)
            % shows what the highlighted job does and needs
            if isempty(src.Value)
                return
            end
            job = obj.catalog(strcmp({obj.catalog.id}, src.Value{1}));
            info = {job.label, job.description, '', ...
                ['Needs: ' listText(job.requires)], ...
                ['Recommended first: ' listText(job.recommends)], ...
                ['Marks as done: ' listText(job.provides)]};
            if job.interactive
                info{end+1} = 'Opens its own windows.';
            end
            if job.shareable
                info{end+1} = 'Can use the same settings for every set (Job plan, top row).';
            end
            obj.methodInfo.Value = info;
        end

        function obj = addJobs(obj)
            % adds the highlighted jobs to the end of the job list
            newIds = obj.methodList.Value;
            if isempty(newIds)
                uialert(obj.f, 'Highlight one or more jobs on the left first.', 'Nothing selected', 'Icon', 'info');
                return
            end
            obj.setJobs([obj.jobs, string(newIds(:)')], ...
                [obj.jobOn, true(numel(obj.queue), numel(newIds))], ...
                [obj.shareOn, obj.sameOpts & obj.shareableJobs(newIds)]);   % new jobs follow the header box
        end

        function obj = addAllJobs(obj)
            % replaces the job list with a whole pipeline: the default (pipeline.json) or one of the user's
            % named pipelines (Settings > My Pipeline), picked from a list when there is more than one
            pipes = pipelineStore('list', obj.cfg.paths.userPath);
            pick = 1;
            if numel(pipes) > 1
                [pick, ok] = listdlg('PromptString', 'Add which pipeline?', 'SelectionMode', 'single', ...
                    'ListString', {pipes.name}, 'ListSize', [280 160], 'InitialValue', min(2, numel(pipes)), 'Name', 'Add pipeline');
                figure(obj.f);
                if ~ok || isempty(pick)
                    return
                end
            end
            if ~isempty(obj.jobs)
                answer = uiconfirm(obj.f, sprintf('Replace the current job list with "%s"?', pipes(pick).name), 'Add pipeline', ...
                    'Options', {'Replace', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if ~strcmp(answer, 'Replace')
                    return
                end
            end
            pipelineIds = pipes(pick).jobs;
            known = ismember(pipelineIds, string({obj.catalog.id}));
            pipelineIds = pipelineIds(known);
            nJobs = numel(pipelineIds);
            obj.setJobs(pipelineIds, true(numel(obj.queue), nJobs), obj.sameOpts & obj.shareableJobs(pipelineIds));   % follows the header box
        end

        function obj = removeJob(obj)
            % removes the highlighted job
            k = obj.jobList.Value;
            if isempty(k) || isempty(obj.jobs)
                return
            end
            keep = true(1, numel(obj.jobs));
            keep(k) = false;
            obj.setJobs(obj.jobs(keep), obj.jobOn(:, keep), obj.shareOn(keep), min(k, sum(keep)));
        end

        function obj = moveJob(obj, step)
            % moves the highlighted job up (step = -1) or down (step = +1)
            k = obj.jobList.Value;
            if isempty(k) || isempty(obj.jobs)
                return
            end
            target = k + step;
            if target < 1 || target > numel(obj.jobs)
                return
            end
            order = 1:numel(obj.jobs);
            order([k target]) = [target k];
            obj.setJobs(obj.jobs(order), obj.jobOn(:, order), obj.shareOn(order), target);
        end

        function obj = clearJobs(obj)
            obj.setJobs(strings(1, 0), false(numel(obj.queue), 0), false(1, 0));
        end

        function setJobs(obj, jobIds, jobOn, shareOn, highlight)
            % the one place the job list changes, so the job plan ticks always move with their jobs
            if nargin < 5
                highlight = [];
            end
            obj.jobs = jobIds;
            obj.jobOn = jobOn;
            obj.shareOn = shareOn;
            obj.refreshJobs(highlight);
        end

        function checkPlanSize(obj)
            % job plan ticks must be sets x jobs; anything else (e.g. an old saved batch) resets to all on
            if ~isequal(size(obj.jobOn), [numel(obj.queue), numel(obj.jobs)])
                obj.jobOn = true(numel(obj.queue), numel(obj.jobs));
            end
            if numel(obj.shareOn) ~= numel(obj.jobs)
                obj.shareOn = false(1, numel(obj.jobs));
            end
        end

        function refreshJobs(obj, highlight)
            % redraws the job list; each row says on how many sets the job will run, e.g.
            % "3. Filter   [3 of 3 sets, same settings]" or "5. ICA   [BLOCKED on 1 set: needs reref]"
            if nargin < 2 || isempty(highlight)
                highlight = obj.jobList.Value;
            end
            obj.checkPlanSize();
            nJobs = numel(obj.jobs);
            plans = obj.planAll();
            items = cell(1, nJobs);
            for k = 1:nJobs
                actions = strings(1, numel(plans));
                for p = 1:numel(plans)
                    actions(p) = plans{p}(k).action;
                end
                label = obj.jobLabel(k);
                nBlocked = sum(actions == "blocked");
                nRun = sum(actions == "run");
                if nBlocked > 0
                    firstBlocked = find(actions == "blocked", 1);
                    status = sprintf('BLOCKED on %d set(s): %s', nBlocked, plans{firstBlocked}(k).why);
                elseif nRun == 0 && all(actions == "off")
                    status = 'off';
                else
                    status = sprintf('%d of %d sets', nRun, numel(actions));
                end
                if obj.shareOn(k)
                    items{k} = sprintf('%d. %s   [%s, same settings]', k, label, status);
                else
                    items{k} = sprintf('%d. %s   [%s]', k, label, status);
                end
            end
            set(obj.jobList, 'Items', items, 'ItemsData', num2cell(1:nJobs));
            if ~isempty(highlight) && isnumeric(highlight) && highlight >= 1 && highlight <= nJobs
                obj.jobList.Value = highlight;
            end
            obj.fillPlanTable();
        end

        function label = jobLabel(obj, k)
            job = obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k)));
            if isempty(job)
                label = char(obj.jobs(k));
            else
                label = job.label;
            end
        end

        function plans = planAll(obj)
            % one jobPlan per set; with no sets, one plan as if on fresh data so blocked jobs still show
            plans = cell(1, numel(obj.queue));
            for i = 1:numel(obj.queue)
                plans{i} = jobPlan(obj.jobs, obj.catalog, obj.queue(i).state.doneJobs, obj.jobOn(i, :), ...
                    obj.finishedJobs(i));
            end
            if isempty(plans)
                plans = {jobPlan(obj.jobs, obj.catalog, {}, true(1, numel(obj.jobs)))};
            end
        end


        %% Job plan window

        function obj = showPlan(obj)
            % "Job plan": a table with one row per set and one tick box per job.
            % Top row = same settings for every set (only jobs whose dialogs can be shared).
            % Red = blocked (something it needs is off or not done), green = already done in this run.
            if isempty(obj.jobs)
                uialert(obj.f, 'Add jobs to the list first.', 'No jobs', 'Icon', 'info');
                return
            end
            if ~isempty(obj.planTable) && isvalid(obj.planTable)
                figure(ancestor(obj.planTable, 'figure'));
                return
            end
            obj.syncDone();
            planFig = uifigure("Name", 'Job plan', "Color", obj.mainColor, ...
                "Position", [obj.f.Position(1:2) + 60, min(1200, obj.f.Position(3)), 460]);
            planGrid = uigridlayout(planFig, [4 1], "RowSpacing", 4, "Padding", [8 8 8 8], "BackgroundColor", obj.mainColor);
            planGrid.RowHeight = {36, 30, '1x', 70};
            helpText = ['Untick a box to skip that job for that set. Tick the top row to ask a job''s questions once ', ...
                'and use the same answers for every set. Highlight cells (or set names for whole rows) and use the buttons above the table. Rerun highlighted redoes a green (done) job and every job after it, from the file that went into it (orange); press it again on the same cell to cancel.'];
            helpLabel = uilabel(planGrid, "Text", helpText, "WordWrap", 'on');
            helpLabel.Layout.Row = 1;
            obj.planTable = uitable(planGrid, "SelectionType", 'cell', "Multiselect", 'on', "RowName", {}, ...
                "CellEditCallback", @(src, evt) obj.onPlanEdit(src, evt));
            obj.planTable.Layout.Row = 3;
            obj.planNotes = uitextarea(planGrid, "Editable", 'off', "FontSize", 11);
            obj.planNotes.Layout.Row = 4;
            buttonStrip = uigridlayout(planGrid, [1 6], "Padding", [0 0 0 0], "ColumnSpacing", 6, ...
                "BackgroundColor", obj.mainColor);
            buttonStrip.Layout.Row = 2;
            obj.makeButton(buttonStrip, 1, 'All on', @(~, ~) obj.setPlanTicks('all', true));
            obj.makeButton(buttonStrip, 2, 'All off', @(~, ~) obj.setPlanTicks('all', false));
            obj.makeButton(buttonStrip, 3, 'Highlighted on', @(~, ~) obj.setPlanTicks('highlighted', true));
            obj.makeButton(buttonStrip, 4, 'Highlighted off', @(~, ~) obj.setPlanTicks('highlighted', false));
            obj.makeButton(buttonStrip, 5, 'Rerun highlighted', @(~, ~) obj.markRerun());
            obj.makeButton(buttonStrip, 6, 'Close', @(~, ~) delete(planFig));
            obj.fillPlanTable();
        end

        function fillPlanTable(obj)
            % redraws the job plan table (if the window is open) from obj.jobOn, obj.shareOn and the plans
            if isempty(obj.planTable) || ~isvalid(obj.planTable)
                return
            end
            nSets = numel(obj.queue);
            nJobs = numel(obj.jobs);
            columnNames = cell(1, nJobs + 1);
            columnNames{1} = 'Set';
            for k = 1:nJobs
                columnNames{k + 1} = sprintf('%d. %s', k, obj.jobLabel(k));
            end
            shareable = false(1, nJobs);
            for k = 1:nJobs
                job = obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k)));
                shareable(k) = ~isempty(job) && job.shareable;
            end

            tableData = cell(nSets + 1, nJobs + 1);
            tableData{1, 1} = 'Same settings for all sets';
            tableData(1, 2:end) = num2cell(obj.shareOn & shareable);
            for i = 1:nSets
                tableData{i + 1, 1} = obj.queue(i).identity.fileName;
                tableData(i + 1, 2:end) = num2cell(obj.jobOn(i, :));
            end
            obj.planTable.Data = tableData;
            obj.planTable.ColumnName = columnNames;
            obj.planTable.ColumnFormat = [{'char'}, repmat({'logical'}, 1, nJobs)];
            obj.planTable.ColumnEditable = [false, true(1, nJobs)] & ~obj.running;
            obj.planTable.ColumnWidth = [{160}, repmat({'fit'}, 1, nJobs)];

            % colours: header row, not-shareable header cells, blocked, done in this run
            removeStyle(obj.planTable);
            addStyle(obj.planTable, uistyle('BackgroundColor', [0.88 0.84 1]), 'row', 1);
            notShareable = find(~shareable) + 1;
            if ~isempty(notShareable)
                addStyle(obj.planTable, uistyle('BackgroundColor', [0.8 0.8 0.8]), 'cell', ...
                    [ones(numel(notShareable), 1), notShareable(:)]);
            end
            notes = {};
            blockedCells = zeros(0, 2);
            doneCells = zeros(0, 2);
            for i = 1:nSets
                plan = jobPlan(obj.jobs, obj.catalog, obj.queue(i).state.doneJobs, obj.jobOn(i, :), obj.finishedJobs(i));
                for k = 1:nJobs
                    if plan(k).action == "blocked"
                        blockedCells(end+1, :) = [i + 1, k + 1]; %#ok<AGROW>
                        notes{end+1} = sprintf('%s: %d. %s %s', obj.queue(i).identity.fileName, k, plan(k).label, plan(k).why); %#ok<AGROW>
                    elseif plan(k).action == "done"
                        doneCells(end+1, :) = [i + 1, k + 1]; %#ok<AGROW>
                    end
                end
            end
            if ~isempty(blockedCells)
                addStyle(obj.planTable, uistyle('BackgroundColor', [1 0.6 0.6]), 'cell', blockedCells);
            end
            if ~isempty(doneCells)
                addStyle(obj.planTable, uistyle('BackgroundColor', [0.7 0.9 0.7]), 'cell', doneCells);
            end
            rerunCells = zeros(0, 2);   % orange: will be redone (Rerun highlighted)
            for i = 1:nSets
                sessionID = obj.sessionName(i);
                if ~isempty(sessionID) && isKey(obj.rerunFrom, sessionID)
                    k0 = obj.rerunFrom(sessionID);
                    rerunCells = [rerunCells; [repmat(i + 1, nJobs - k0 + 1, 1), (k0:nJobs)' + 1]]; %#ok<AGROW>
                    notes{end+1} = sprintf('%s: rerun from %d. %s - the set that went into it is reloaded and every file saved after it is deleted at Run', ...
                        obj.queue(i).identity.fileName, k0, obj.jobLabel(k0)); %#ok<AGROW>
                end
            end
            if ~isempty(rerunCells)
                addStyle(obj.planTable, uistyle('BackgroundColor', [1 0.8 0.5]), 'cell', rerunCells);
            end
            if isempty(notes)
                notes = {'Nothing blocked.'};
            end
            obj.planNotes.Value = notes;
        end

        function onPlanEdit(obj, src, evt)
            % a tick changed in the job plan table
            row = evt.Indices(1);
            col = evt.Indices(2);
            k = col - 1;
            if row == 1
                job = obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k)));
                if isempty(job) || ~job.shareable
                    src.Data{row, col} = false;
                    return
                end
                obj.shareOn(k) = evt.NewData;
            else
                obj.jobOn(row - 1, k) = evt.NewData;
            end
            obj.refreshJobs();
        end

        function setPlanTicks(obj, which, value)
            % All on / All off, or the highlighted cells (a highlighted set name means its whole row)
            if obj.running
                return
            end
            if strcmp(which, 'all')
                obj.jobOn(:) = value;
            else
                cells = obj.planTable.Selection;
                for c = 1:size(cells, 1)
                    row = cells(c, 1);
                    col = cells(c, 2);
                    if row == 1
                        continue
                    end
                    if col == 1
                        obj.jobOn(row - 1, :) = value;
                    else
                        obj.jobOn(row - 1, col - 1) = value;
                    end
                end
            end
            obj.refreshJobs();
        end


        function markRerun(obj)
            % IN:  none (reads the highlighted cells of the job plan table)
            % OUT: obj.rerunFrom(sessionID) = earliest highlighted done job per set; a cell that is already the
            %      rerun start is cleared instead. Only green (done in this run) cells can be marked.
            if obj.running || isempty(obj.planTable) || ~isvalid(obj.planTable)
                return
            end
            cells = obj.planTable.Selection;
            marked = false;
            for c = 1:size(cells, 1)
                i = cells(c, 1) - 1;   % table row 1 is the same-settings row
                k = cells(c, 2) - 1;   % table column 1 is the set name
                sessionID = obj.sessionName(max(i, 1));
                if i < 1 || k < 1 || isempty(sessionID)
                    continue
                end
                if isKey(obj.rerunFrom, sessionID) && obj.rerunFrom(sessionID) == k
                    remove(obj.rerunFrom, sessionID);   % same cell again = cancel
                    marked = true;
                elseif k <= obj.finishedJobs(i)
                    if isKey(obj.rerunFrom, sessionID)
                        k = min(k, obj.rerunFrom(sessionID));
                    end
                    obj.rerunFrom(sessionID) = k;
                    marked = true;
                end
            end
            if ~marked
                uialert(ancestor(obj.planTable, 'figure'), ['Highlight a green (done) job to rerun it. Jobs that have not ' ...
                    'run yet in this run will run anyway.'], 'Rerun', 'Icon', 'info');
                return
            end
            obj.refreshJobs();
        end

        function [EEG, setFile, kStart] = prepareRerun(obj, i, cfg_full, k)
            % IN:  i = set number, cfg_full = its configuration, k = job to redo from
            % OUT: EEG = the set as it was going into job k (loaded from disk; [] if k is Load data),
            %      setFile = that file. Every .set saved after it in <data_out> is deleted first (asked once).
            %      kStart = the job the rerun really starts at: k, or earlier when the jobs just before k were never
            %      saved on their own ("save only at the end"), so their work is redone from the last file on disk.
            %      Errors if the user cancels. Uses the per-job file list in _runProgress.mat; runs from before
            %      that list existed ask for the file.
            sessionID = obj.sessionName(i);
            dataOut = char(cfg_full.paths.data_out);
            setFile = '';
            kStart = k;
            if isKey(obj.progress, sessionID)
                saved = obj.progress(sessionID);
                if isfield(saved, 'files')
                    jFound = 0;   % job whose output file is the starting point (0 = the run's start file)
                    for j = k-1:-1:1   % the file the set was in after the job before k (a job that saves nothing keeps the last one)
                        if j <= numel(saved.files) && ~isempty(saved.files{j}) && isfile(saved.files{j})
                            setFile = saved.files{j};
                            jFound = j;
                            break
                        end
                    end
                    if isempty(setFile) && isfield(saved, 'startFile') && isfile(saved.startFile)
                        setFile = saved.startFile;
                    end
                    % blank entries between that file and k = jobs whose result was never written ("save only at the end"):
                    % their work is not in setFile, so the rerun has to redo them
                    gap = (jFound + 1):(k - 1);
                    gap = gap(gap <= numel(saved.files));
                    if ~isempty(setFile) && ~isempty(gap) && any(cellfun(@isempty, saved.files(gap)))
                        kStart = jFound + 1;
                    end
                end
            end
            if isempty(setFile) && ~(k == 1 && strcmp(obj.jobs(1), "loadData"))
                [fn, fp] = uigetfile(fullfile(dataOut, '*.set'), sprintf('Pick the set that went INTO %s (for %s)', obj.jobLabel(k), sessionID));
                figure(obj.f);
                if isequal(fn, 0), error('Rerun cancelled: no starting set picked.'); end
                setFile = fullfile(fp, fn);
            end
            % everything saved after the starting file is from job k onwards
            F = dir(fullfile(dataOut, '**', '*.set'));
            if isempty(setFile)
                cutoff = -Inf;
            else
                startInfo = dir(setFile);
                cutoff = startInfo.datenum + 1/86400;   % 1 s margin: same-second saves belong to the start file's job
            end
            F = F([F.datenum] > cutoff & ~strcmpi(strcat({F.folder}, filesep, {F.name}), setFile));
            if ~isempty(F)
                names = erase(strcat({F.folder}, filesep, {F.name}), [dataOut filesep]);
                note = '';
                if kStart < k
                    note = sprintf('\n\nJobs %d-%d were not saved on their own ("save only at the end"), so the rerun redoes them from job %d.', kStart, k - 1, kStart);
                end
                figure(obj.f);   % in front of the status window and any job window, so this box cannot hide behind them
                answer = uiconfirm(obj.f, sprintf('Rerun %s from %d. %s. These files will be DELETED:\n\n%s\n\nStarting from: %s%s', ...
                    sessionID, kStart, obj.jobLabel(kStart), strjoin(names, newline), erase(setFile, [dataOut filesep]), note), ...
                    'Rerun', 'Options', {'Delete and rerun', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                if ~strcmp(answer, 'Delete and rerun'), error('Rerun cancelled; nothing was deleted.'); end
                for n = 1:numel(F)
                    delete(fullfile(F(n).folder, F(n).name));
                end
            end
            EEG = [];
            if ~isempty(setFile)
                [fp, fn, ext] = fileparts(setFile);
                EEG = pop_loadset('filename', [fn ext], 'filepath', fp);
            end
            remove(obj.rerunFrom, sessionID);
        end


        %% Header, set list and batch files

        function obj = pickOutRoot(obj)
            folder = uigetdir('', 'Choose the output folder for this batch');
            figure(obj.f);
            if isequal(folder, 0)
                return
            end
            obj.setOutputFolder(folder);
        end

        function obj = onSameOpts(obj, src)
            obj.sameOpts = src.Value;
            % row 1's options for every set also means no repeated dialogs: "same settings" goes on (or off)
            % for every shareable job; the job plan's top row can still untick single jobs afterwards
            obj.shareOn = obj.sameOpts & obj.shareableJobs(obj.jobs);
            obj.refreshJobs();
            obj.refresh();
        end

        function mask = shareableJobs(obj, ids)
            % logical 1 x numel(ids): true where jobs.json marks the job "shareable"
            ids = string(ids);
            mask = false(1, numel(ids));
            for k = 1:numel(ids)
                job = obj.catalog(strcmp({obj.catalog.id}, ids(k)));
                mask(k) = ~isempty(job) && job.shareable;
            end
        end

        function obj = selectAll(obj, tickValue)
            obj.selected = repmat(logical(tickValue), numel(obj.queue), 1);
            obj.refresh();
        end

        function batch = batchStruct(obj)
            % everything needed to restore this batch (Save batch, autosave, history)
            batch = struct('queue', obj.queue, 'jobs', obj.jobs, 'jobOn', obj.jobOn, 'shareOn', obj.shareOn, ...
                'outRoot', obj.outRoot, 'sameOpts', obj.sameOpts, 'runId', obj.runId, 'runName', obj.runName, ...
                'runStart', obj.runStart, 'saved', datetime('now'));
        end

        function obj = saveBatch(obj)
            startFile = 'bipate_batch.mat';
            if ~isempty(obj.outRoot)
                startFile = fullfile(obj.outRoot, startFile);
            end
            [fileName, filePath] = uiputfile('*.mat', 'Save batch', startFile);
            figure(obj.f);
            if isequal(fileName, 0)
                return
            end
            batch = obj.batchStruct();
            save(fullfile(filePath, fileName), 'batch');
        end

        function obj = loadBatch(obj)
            % restores a batch saved with Save batch, or the autosave in an output folder
            if obj.running
                return
            end
            [fileName, filePath] = uigetfile('*.mat', 'Load batch');
            figure(obj.f);
            if isequal(fileName, 0)
                return
            end
            try
                loaded = load(fullfile(filePath, fileName), 'batch');
            catch ME
                uialert(obj.f, ME.message, 'Could not load batch', 'Icon', 'error');
                return
            end
            obj.applyBatch(loaded.batch);
        end

        function obj = applyBatch(obj, batch)
            % puts a saved batch into the app. Older batches without job plan ticks get all ticks on.
            % Jobs no longer in jobs.json are dropped with a warning.
            try
                obj.queue = batch.queue;
                for i = 1:numel(obj.queue)
                    if strcmp(obj.queue(i).state.status, 'running')
                        obj.queue(i).state.status = 'queued';
                    end
                end
                obj.selected = false(numel(obj.queue), 1);
                nSets = numel(obj.queue);
                jobIds = string(batch.jobs);
                jobOnLoaded = true(nSets, numel(jobIds));
                shareOnLoaded = false(1, numel(jobIds));
                if isfield(batch, 'jobOn') && isequal(size(batch.jobOn), size(jobOnLoaded))
                    jobOnLoaded = batch.jobOn;
                end
                if isfield(batch, 'shareOn') && numel(batch.shareOn) == numel(jobIds)
                    shareOnLoaded = batch.shareOn;
                end
                known = ismember(jobIds, string({obj.catalog.id}));
                if ~all(known)
                    uialert(obj.f, sprintf('These jobs are not in jobs.json any more and were left out: %s', ...
                        strjoin(jobIds(~known), ', ')), 'Batch loaded', 'Icon', 'warning');
                end
                obj.outRoot = batch.outRoot;
                obj.sameOpts = batch.sameOpts;
                obj.runId = '';
                obj.runName = '';
                obj.runStart = '';
                if isfield(batch, 'runId')
                    obj.runId = batch.runId;
                    obj.runName = batch.runName;
                    obj.runStart = batch.runStart;
                end
                obj.showRunName();   % loaded batch: its run name in the title bar
            catch ME
                uialert(obj.f, ME.message, 'Could not load batch', 'Icon', 'error');
                return
            end
            if isempty(obj.outRoot)
                obj.outLabel.Text = '(choose where the processed sets go)';
                obj.outLabel.FontAngle = 'italic';
            else
                obj.outLabel.Text = obj.outRoot;
                obj.outLabel.FontAngle = 'normal';
            end
            obj.sameOptsCB.Value = obj.sameOpts;
            obj.syncDone();
            obj.refresh();
            obj.setJobs(jobIds(known), jobOnLoaded(:, known), shareOnLoaded(known));
        end

        function obj = reloadSettings(obj)
            % after the Settings window saved: rebuild the base cfg (cfg_init applies the saved overrides).
            % Sets already in the list keep their own cap / artifact choices; the ICA method is the Settings one
            try
                obj.cfg = cfg_init;
            catch ME
                uialert(obj.f, ME.message, 'Could not reload the settings', 'Icon', 'error');
                return
            end
            if isempty(obj.outRoot) && isfield(obj.cfg, 'general') && isfolder(obj.cfg.general.outRoot)
                obj.setOutputFolder(obj.cfg.general.outRoot);
            end
            for i = 1:numel(obj.queue)   % recorded per set (history, saved batches): keep it in step with Settings
                obj.queue(i).opts.ica.method = obj.cfg.defaults.icaMethod;
            end
            obj.refresh();
        end

        function obj = reloadCatalog(obj)
            % "Reload jobs": reads jobs.json again after it was edited, without restarting the app
            try
                obj.catalog = jobCatalog;
            catch ME
                uialert(obj.f, ME.message, 'jobs.json problem', 'Icon', 'error');
                return
            end
            obj.fillMethodList();
            known = ismember(obj.jobs, string({obj.catalog.id}));
            obj.setJobs(obj.jobs(known), obj.jobOn(:, known), obj.shareOn(known));
        end


        %% Running a batch

        function obj = runBatch(obj)
            % checks the batch, asks for a name (new run) or whether to continue the last run, then runs
            % every set through the jobs one set at a time
            if obj.running
                return
            end
            if isempty(obj.queue)
                uialert(obj.f, 'Add at least one set first.', 'Nothing to run', 'Icon', 'info');
                return
            end
            if isempty(obj.jobs)
                uialert(obj.f, 'Add at least one job first.', 'Nothing to run', 'Icon', 'info');
                return
            end
            if isempty(obj.outRoot)
                uialert(obj.f, 'Choose an output folder first (header, left).', 'No output folder', 'Icon', 'info');
                return
            end

            % continue the last run, or start a new one. Continue is only offered when a set in the queue
            % stopped part-way through the run that is loaded now (same run id and same job list).
            % jobs added (or a pipeline swapped in) after this run finished some jobs: offer to add them to the
            % same run instead of starting over (offerExtend explains); '' = not that situation
            ext = obj.offerExtend();
            if strcmp(ext, 'cancel')
                return
            end
            canResume = false;
            resumeText = '';
            if isempty(ext)
                [canResume, resumeText] = obj.resumeSummary();
            end
            newRun = ~canResume && ~strcmp(ext, 'add');
            if canResume
                answer = uiconfirm(obj.f, resumeText, 'Unfinished run found', 'Options', ...
                    {'Continue', 'New run', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3);
                if strcmp(answer, 'Cancel')
                    return
                end
                newRun = strcmp(answer, 'New run');
            end
            if newRun
                defaultName = char(datetime('now', 'Format', 'yyyy-MM-dd_HHmm'));
                nameAnswer = inputdlg('Name for this batch run:', 'Run batch', [1 50], {['batch_' defaultName]});
                figure(obj.f);
                if isempty(nameAnswer)
                    return
                end
                obj.runName = strtrim(nameAnswer{1});
                if isempty(obj.runName)
                    obj.runName = ['batch_' defaultName];
                end
                % before a new run overwrites earlier work: its name is already in History, or sets in the queue
                % already have results in the output folder (same <outRoot>\<sessionID>)
                clash = {};
                try
                    hist = jsondecode(fileread(fullfile(obj.historyDir(), 'batch_history.json')));
                    if iscell(hist), hist = [hist{:}]; end
                    if ~isempty(hist) && any(strcmpi(string({hist.name}), obj.runName))
                        clash{end + 1} = sprintf('A run called "%s" is already in History.', obj.runName);
                    end
                catch
                    % no history yet (or unreadable): nothing to compare against
                end
                hasOut = {};
                loadCol = strcmp(cellstr(string(obj.jobs)), 'loadData');   % only a run that starts sets over from Load data replaces their files (later steps get round numbers)
                for i = 1:numel(obj.queue)
                    sid = char(obj.sessionName(i));
                    if any(loadCol & logical(obj.jobOn(i, :))) && ~isempty(sid) && ~isempty(obj.outRoot) && ~isempty(dir(fullfile(obj.outRoot, sid, '**', '*.set')))
                        hasOut{end + 1} = sid; %#ok<AGROW>
                    end
                end
                if ~isempty(hasOut)
                    clash{end + 1} = sprintf('This run starts these sets over from Load data, replacing their results in %s: %s', ...
                        obj.outRoot, strjoin(hasOut, ', '));
                end
                if ~isempty(clash)
                    answer = uiconfirm(obj.f, strjoin([clash, {'Go ahead anyway?'}], [newline newline]), ...
                        'This run would overwrite earlier work', 'Options', {'Go ahead', 'Cancel'}, ...
                        'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning');
                    if strcmp(answer, 'Cancel')
                        obj.runName = '';
                        obj.showRunName();
                        return
                    end
                end
                obj.showRunName();
                obj.runId = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
                remove(obj.rerunFrom, keys(obj.rerunFrom));   % a new run redoes everything anyway
                obj.runStart = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
                for i = 1:numel(obj.queue)
                    if ~strcmp(obj.queue(i).state.status, 'failed') || startsWith(obj.queue(i).state.message, 'Run:')
                        obj.queue(i).state.status = 'queued';
                        obj.queue(i).state.message = '';
                    end
                end
                batchShared('clear');
            else
                for i = 1:numel(obj.queue)
                    status = obj.queue(i).state.status;
                    % a finished set marked with Rerun highlighted has to be queued again, or nothing runs
                    markedRerun = ~isempty(obj.sessionName(i)) && isKey(obj.rerunFrom, obj.sessionName(i));
                    if strcmp(status, 'running') || markedRerun || (strcmp(status, 'failed') && startsWith(obj.queue(i).state.message, 'Run:'))
                        obj.queue(i).state.status = 'queued';
                        obj.queue(i).state.message = '';
                    end
                end
            end

            try
                obj.queue = queueValidate(obj.queue, obj.cfg);
            catch ME
                uialert(obj.f, ME.message, 'Could not validate the sets', 'Icon', 'error');
                return
            end
            figure(obj.f);
            obj.syncDone();
            obj.refresh();
            obj.refreshJobs();

            toRun = find(arrayfun(@(e) strcmp(e.state.status, 'queued'), obj.queue));
            if isempty(toRun)
                uialert(obj.f, 'No set is waiting to run (finished sets are left alone; failed ones show why on hover).', ...
                    'Nothing to run', 'Icon', 'warning');
                return
            end

            blockedList = {};
            for i = toRun
                plan = jobPlan(obj.jobs, obj.catalog, obj.queue(i).state.doneJobs, obj.jobOn(i, :), obj.finishedJobs(i));
                for k = find([plan.action] == "blocked")
                    blockedList{end+1} = sprintf('%s: %d. %s (%s)', obj.queue(i).identity.sessionID, k, plan(k).label, plan(k).why); %#ok<AGROW>
                end
            end
            if ~isempty(blockedList)
                uialert(obj.f, [{'Nothing was started. These jobs cannot run (see Job plan):'}, blockedList], ...
                    'Batch blocked', 'Icon', 'error');
                return
            end

            % a step already in a set's history (done before this batch) runs again as its next round
            % (e.g. segmentRejection2): list every such repeat once and ask. Sets that start over from Load data
            % are left out (the overwrite warning covers them), and so are repeats inside this job list.
            cleanTag = @(t) regexprep(regexprep(lower(strtrim(cellstr(string(t)))), '\s*\(.*?\)', ''), '\d+$', '');
            repeats = {};
            repIdx = zeros(0, 2);
            for i = toRun
                if any(strcmp(cellstr(obj.jobs), 'loadData') & logical(obj.jobOn(i, :))), continue; end
                had = cleanTag(obj.queue(i).state.doneJobs);
                if isempty(had), continue; end
                plan = jobPlan(obj.jobs, obj.catalog, obj.queue(i).state.doneJobs, obj.jobOn(i, :), obj.finishedJobs(i));
                for k = find([plan.action] == "run")
                    job = obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k)));
                    gives = erase(cleanTag(job.provides), '*');
                    if any(cellfun(@(g) ~isempty(g) && any(startsWith(had, g)), gives))
                        repeats{end + 1} = sprintf('  %s: %s', obj.sessionName(i), job.label); %#ok<AGROW>
                        repIdx(end + 1, :) = [i k]; %#ok<AGROW>
                    end
                end
            end
            if ~isempty(repeats)
                answer = uiconfirm(obj.f, [{'These steps were already done on these sets. Running them again saves the result ' ...
                    'as the next round (e.g. segmentRejection2); the earlier files are kept:'}, repeats, ...
                    {'Skip those = untick them in the job plan and run the rest.'}], 'Run steps again?', ...
                    'Options', {'Run them again', 'Skip those', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 3, 'Icon', 'warning');
                if strcmp(answer, 'Cancel'), return; end
                if strcmp(answer, 'Skip those')
                    for r = 1:size(repIdx, 1)
                        obj.jobOn(repIdx(r, 1), repIdx(r, 2)) = false;
                    end
                    obj.refreshJobs();
                end
            end

            try
                obj.startEEGLAB();
            catch ME
                uialert(obj.f, ME.message, 'EEGLAB', 'Icon', 'error');
                return
            end

            obj.stopRequested = false;
            obj.runTic = tic;
            obj.setRunning(true);
            setappdata(0, 'bipateBatch', true);       % notifyDone stays quiet until the whole batch is done
            setappdata(0, 'bipateBatchSize', [numel(toRun), nnz(any(obj.jobOn(toRun, :), 1))]);   % [sets jobs], for showQC
            setappdata(0, 'bipateICAOverviewShown', false);   % callICA: the component overview opens for the first set only
            cleanup = onCleanup(@() obj.finishRun());
            obj.writeHistory('running');
            for i = toRun
                if obj.stopRequested
                    break
                end
                try
                    obj.runSet(i);
                catch ME   % anything runSet did not catch itself: the set is marked failed, the batch goes on
                    obj.setState(i, 'failed', ['Run: ' ME.message]);
                    fprintf(2, 'BIPATE: set %d stopped by an unexpected error:\n%s\n', i, getReport(ME, 'extended', 'hyperlinks', 'off'));
                end
                obj.saveManifest();
                obj.writeHistory('running');
            end

            statuses = arrayfun(@(e) string(e.state.status), obj.queue);
            summary = sprintf('%s: %d set(s) done, %d failed.', obj.runName, sum(statuses == "done"), sum(statuses == "failed"));
            if obj.stopRequested
                summary = [summary ' Stopped before the end; Run batch and Continue to pick it up.'];
                obj.writeHistory('stopped');
            else
                obj.writeHistory('finished');
            end
            setappdata(0, 'bipateBatch', false);
            notifyDone('Batch', summary, 'showBox', false);   % chime + console only: a msgbox here was buried by finishRun's figure(obj.f)
            obj.batchSummary = summary;
        end

        function obj = runSet(obj, i)
            % runs the ticked jobs on set i. Starts from the newest .set saved for the session (if any).
            % When the run is continued, jobs this run already finished on the set are not run again.
            % A failing job stops this set only; its message starts with "Run:" so Continue retries it.
            entry = obj.queue(i);
            if obj.sameOpts
                entry.opts = obj.queue(1).opts;
            end
            clearRej = onCleanup(@clearRejInfo);   % segmentRejection's global is dropped when the set ends %#ok<NASGU>
            try
                cfg_full = sessionCfg(obj.cfg, entry, obj.outRoot);
                createOutputFolders(cfg_full);
            catch ME
                obj.setState(i, 'failed', ['Run: setup: ' ME.message]);
                return
            end
            nFinished = obj.finishedJobs(i);

            obj.setState(i, 'running', 'looking for saved data');
            try
                sessionID = obj.sessionName(i);
                if isKey(obj.rerunFrom, sessionID)
                    k0 = obj.rerunFrom(sessionID);
                    [EEG, setFile, k0] = obj.prepareRerun(i, cfg_full, k0);   % k0 can move earlier (unsaved jobs)   % the set going into job k0, later files deleted
                    nFinished = k0 - 1;
                else
                    [EEG, setFile] = latestSet(cfg_full.paths.data_out);
                end
            catch ME
                obj.setState(i, 'failed', ['Run: loading saved data: ' ME.message]);
                return
            end
            if nFinished == 0
                obj.runStartFile = setFile;   % what the run started from, for a later Rerun of job 1
            else
                obj.runStartFile = '';        % keep the one saved in _runProgress.mat
            end
            if ~isempty(EEG) && isfield(EEG, 'etc') && isfield(EEG.etc, 'processing_done')
                obj.queue(i).state.doneJobs = EEG.etc.processing_done;
                obj.queue(i).state.message = ['started from ' setFile];
            end

            setappdata(0, 'bipateDeferSave', obj.saveAtEnd);   % saveStep holds step saves back when true
            obj.savedAfter = cell(1, numel(obj.jobs));      % what this set's jobs write to disk along the way
            setStartNum = now; %#ok<TNOW1> datenum to compare with dir()  % files older than this are left over from an earlier run
            doneK = nFinished;                                  % jobs of this run finished on this set
            for k = 1:numel(obj.jobs)
                if obj.stopRequested
                    obj.setState(i, 'queued', sprintf('Stopped before job %d', k));
                    obj.flushSet(i, cfg_full, EEG, doneK);
                    return
                end
                job = obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k)));
                plan = jobPlan(job.id, obj.catalog, obj.queue(i).state.doneJobs, obj.jobOn(i, k), double(k <= nFinished));
                if plan.action == "blocked"
                    obj.setState(i, 'failed', sprintf('Run: %s: %s', job.label, plan.why));
                    obj.flushSet(i, cfg_full, EEG, doneK);
                    return
                end
                if plan.action == "run"
                    inFile = '';
                    if isfield(cfg_full.paths, 'inputFile'), inFile = char(cfg_full.paths.inputFile); end
                    if isempty(EEG) && ismember('EEG', job.inputs) && ~isempty(inputHistory(inFile))
                        % a .set BIPATE already processed needs no Load data job (loadData never runs twice):
                        % loadData_max brings it in with its history kept and saves it to the set's folder
                        try
                            obj.setState(i, 'running', 'loading the input set');
                            EEG = loadData_max(cfg_full);
                        catch ME
                            obj.setState(i, 'failed', ['Run: loading the input set: ' ME.message]);
                            return
                        end
                    end
                    if isempty(EEG) && ismember('EEG', job.inputs)
                        obj.setState(i, 'failed', sprintf('Run: %s needs data: add Load data before it (nothing saved in %s yet)', ...
                            job.label, cfg_full.paths.data_out));
                        obj.flushSet(i, cfg_full, EEG, doneK);
                        return
                    end
                    obj.setState(i, 'running', job.label);
                    try
                        obj.showStatus(i, k, job.label);
                    catch ME
                        warning('bipate:status', 'Status window not updated: %s', ME.message);   % never stops the job
                    end
                    if obj.shareOn(k)
                        batchShared('start', sprintf('%s_%d', job.id, k));
                    else
                        batchShared('stop');
                    end
                    figsBefore = findall(groot, 'Type', 'figure');
                    if ~isempty(EEG) && isfield(cfg_full, 'user')
                        EEG = stampUser(EEG, cfg_full.user);   % saved with the job's output
                    end
                    dataSize = 0;   % channels x samples going in, to scale the time estimate
                    if ~isempty(EEG), dataSize = double(EEG.nbchan) * double(EEG.pnts) * double(EEG.trials); end
                    jobTic = tic;
                    try
                        [EEG, cfg_full] = runJob(job, EEG, cfg_full);
                    catch ME
                        batchShared('stop');
                        closeNewFigures(figsBefore);
                        obj.setState(i, 'failed', sprintf('Run: %s: %s', job.label, ME.message));
                        obj.flushSet(i, cfg_full, EEG, doneK);   % the last good state of the set
                        return
                    end
                    batchShared('stop');
                    closeNewFigures(figsBefore);   % review windows and plots the job left open
                    if job.interactive && isvalid(obj.f)   % a dialog closing hands focus to MATLAB; bring BIPATE back in front
                        figure(obj.f);
                    end
                    if dataSize == 0 && ~isempty(EEG), dataSize = double(EEG.nbchan) * double(EEG.pnts) * double(EEG.trials); end
                    jobTimes('add', job.id, toc(jobTic), dataSize);
                    if ~isempty(EEG) && isfield(EEG, 'etc') && isfield(EEG.etc, 'processing_done')
                        obj.queue(i).state.doneJobs = EEG.etc.processing_done;
                    end
                end
                currentFile = '';
                if ~isempty(EEG) && isfield(EEG, 'filename') && ~isempty(EEG.filename)
                    currentFile = fullfile(EEG.filepath, EEG.filename);   % where the set lives after job k
                end
                % jobs 1..nFinished were finished before this resume or rerun: their recorded files stay as they are
                if k > nFinished && obj.saveAtEnd && ~isempty(currentFile) && isfile(currentFile) && ~(isfield(EEG, 'saved') && strcmp(EEG.saved, 'no')) ...
                        && writtenSince(currentFile, setStartNum)
                    obj.savedAfter{k} = currentFile;   % this job really wrote it (e.g. Load data's _raw.set), so Rerun can start there
                end
                if k > nFinished && ~obj.saveAtEnd   % with saving at the end, progress is recorded when the set is written
                    obj.saveProgress(i, cfg_full, k, currentFile);
                end
                doneK = k;
            end
            EEG = obj.flushSet(i, cfg_full, EEG, doneK); %#ok<NASGU> written once here when saving at the end

            % keep this session's configuration with its data, as launch_pipeline does
            try
                save(fullfile(char(cfg_full.paths.data_out), 'Configurations', [char(cfg_full.sessionID) '_cfg.mat']), 'cfg_full');
            catch ME
                warning('bipate:cfgSave', 'Could not save the configuration for %s: %s', cfg_full.sessionID, ME.message);
            end
            obj.queue(i).state.outDir = char(cfg_full.paths.data_out);
            obj.setState(i, 'done', '');
        end

        function EEG = flushSet(obj, i, cfg_full, EEG, doneK)
            % IN:  i = set number, cfg_full = its configuration, EEG = the set as it is now, doneK = how many
            %      jobs of this run it has finished
            % OUT: EEG, written to disk if "save once per set" held it back (under the last step's name and
            %      folder), and the run progress recorded up to doneK -- only now, so a crash before the save
            %      never leaves Continue thinking unsaved jobs are done. Does nothing in save-every-step mode.
            if ~obj.saveAtEnd
                return
            end
            currentFile = '';
            if ~isempty(EEG) && isfield(EEG, 'saved') && strcmp(EEG.saved, 'no') && ~isempty(EEG.filename)
                if ~isfolder(EEG.filepath), mkdir(EEG.filepath); end
                EEG = pop_saveset(EEG, 'filename', EEG.filename, 'filepath', EEG.filepath, 'savemode', 'onefile', 'version', '7.3');
                fprintf('Saved once for this set: %s\n', fullfile(EEG.filepath, EEG.filename));
            end
            if ~isempty(EEG) && isfield(EEG, 'filename') && ~isempty(EEG.filename)
                currentFile = fullfile(EEG.filepath, EEG.filename);
            end
            if doneK > 0
                obj.saveProgress(i, cfg_full, doneK, currentFile);
            end
        end

        function onSaveAtEnd(obj, src)
            % main-window box "Save only at the end of each set"
            obj.saveAtEnd = src.Value;
        end

        function sessionID = sessionName(obj, i)
            % pptID or pptID_timepoint, the same rule as queueValidate ('' without a pptID)
            pptID = strtrim(char(obj.queue(i).identity.pptID));
            timePoint = strtrim(char(obj.queue(i).identity.timePoint));
            if isempty(pptID)
                sessionID = '';
            elseif isempty(timePoint)
                sessionID = pptID;
            else
                sessionID = [pptID '_' timePoint];
            end
        end

        function choice = offerExtend(obj)
            % When the loaded run already finished some jobs on its sets and the job list has changed since
            % (jobs added, or a pipeline swapped in), asks whether to add the new jobs to the SAME run.
            % "Add to this run": the jobs the run finished move to the top of the list, in the order they ran,
            % and count as done (never run again); every other job runs after them, in list order, on each
            % set's latest file. Run name, history entry and output folder stay the same.
            % OUT: choice = '' (not this situation), 'add', 'new' (New run) or 'cancel'
            choice = '';
            if isempty(obj.runId) || isempty(obj.jobs)
                return
            end
            fin = strings(1, 0);       % jobs the run finished, in run order (the furthest set's)
            oldJobs = strings(1, 0);   % the run's job list before the change
            for i = 1:numel(obj.queue)
                sid = obj.sessionName(i);
                if isempty(sid) || ~isKey(obj.progress, sid), continue; end
                p = obj.progress(sid);
                if ~strcmp(p.runId, obj.runId) || p.nFinished < 1, continue; end
                if p.nFinished > numel(fin)
                    oldJobs = string(p.jobs);
                    fin = oldJobs(1:p.nFinished);
                end
            end
            if isempty(fin) || isequal(oldJobs, obj.jobs)
                return   % nothing finished yet, or the list is unchanged (Continue covers that)
            end
            % new list: finished jobs first (their ticks / same-settings boxes move with them; one the user
            % removed comes back, already done), then the rest of the current list in its order
            cur = obj.jobs;
            used = false(1, numel(cur));
            newJobs = strings(1, 0); newOn = false(numel(obj.queue), 0); newShare = false(1, 0);
            for j = fin
                k = find(cur == j & ~used, 1);
                if isempty(k)
                    newJobs(end + 1) = j; newOn(:, end + 1) = true; newShare(end + 1) = false; %#ok<AGROW>
                else
                    used(k) = true;
                    newJobs(end + 1) = cur(k); newOn(:, end + 1) = obj.jobOn(:, k); newShare(end + 1) = obj.shareOn(k); %#ok<AGROW>
                end
            end
            rest = find(~used);
            if isempty(rest)
                return   % no new job to add
            end
            moved = any(rest < max([find(used), 0]));   % a new job sat above a finished one in the user's list
            newJobs = [newJobs, cur(rest)]; newOn = [newOn, obj.jobOn(:, rest)]; newShare = [newShare, obj.shareOn(rest)];
            label = @(ids) strjoin(arrayfun(@(id) string(obj.catalog(strcmp({obj.catalog.id}, id)).label), ids), ', ');
            msg = sprintf(['Run "%s" already finished: %s. Those stay done and are not run again.\n\n' ...
                'Add to this run: %s. Each set carries on from its latest file, same run name and output folder.'], ...
                obj.runName, label(fin), label(cur(rest)));
            if moved
                msg = [msg sprintf(['\n\nOrder: some new jobs were above jobs that are already done; they now run ' ...
                    'after them (the job list is reordered to show this).'])];
            end
            msg = [msg sprintf('\n\nNew run = a separate run with a new name that runs every ticked job again.')];
            answer = uiconfirm(obj.f, msg, 'Add jobs to this run?', 'Options', {'Add to this run', 'New run', 'Cancel'}, ...
                'DefaultOption', 1, 'CancelOption', 3);
            switch answer
                case 'Cancel', choice = 'cancel'; return
                case 'New run', choice = 'new'; return
            end
            choice = 'add';
            obj.setJobs(newJobs, newOn, newShare);
            % each set's saved progress now refers to the new list; finished jobs keep their files
            for i = 1:numel(obj.queue)
                sid = obj.sessionName(i);
                if isempty(sid) || ~isKey(obj.progress, sid), continue; end
                p = obj.progress(sid);
                if ~strcmp(p.runId, obj.runId), continue; end
                files = cell(1, numel(newJobs));
                nKeep = min([p.nFinished, numel(p.files), numel(newJobs)]);
                files(1:nKeep) = p.files(1:nKeep);
                p.jobs = newJobs;
                p.files = files;
                obj.progress(sid) = p;
                runProgress = p;
                configDir = fullfile(obj.outRoot, sid, 'Configurations');
                if isfolder(configDir), save(fullfile(configDir, [sid '_runProgress.mat']), 'runProgress'); end
                if any(strcmp(obj.queue(i).state.status, {'done', 'failed'}))
                    obj.queue(i).state.status = 'queued';
                    obj.queue(i).state.message = '';
                end
            end
            obj.refresh();
        end

        function [canResume, msg] = resumeSummary(obj)
            % IN:  none (reads obj.runId/runName/runStart, obj.jobs, obj.catalog, obj.queue, obj.progress)
            % OUT: canResume = true if at least one queued set stopped part-way through the loaded run
            %      msg       = text for the Continue / New run box: which run, where its output is, and for
            %                  each set where it stopped and where Continue would pick up
            %      A run stopped between sets (some sets finished, the rest not started) also counts as resumable
            canResume = false;
            msg = '';
            if isempty(obj.runId)
                return
            end
            nJobs = numel(obj.jobs);
            label = @(k) obj.catalog(strcmp({obj.catalog.id}, obj.jobs(k))).label;
            lines = strings(0, 1);
            nDone = 0;
            nFresh = 0;
            for i = 1:numel(obj.queue)
                nF = obj.finishedJobs(i);   % 0 when the set has no progress saved for this run
                setName = obj.sessionName(i);
                if ~isempty(setName) && isKey(obj.rerunFrom, setName)
                    canResume = true;
                    lines(end+1) = sprintf('  %s: rerun from %s (files saved from there on are deleted first; you will be asked)', ...
                        setName, label(obj.rerunFrom(setName))); %#ok<AGROW>
                elseif nF >= nJobs || strcmp(obj.queue(i).state.status, 'done')
                    nDone = nDone + 1;
                elseif nF == 0
                    nFresh = nFresh + 1;
                else
                    canResume = true;
                    lines(end+1) = sprintf('  %s: finished %d of %d jobs (last: %s), Continue starts at %s', ...
                        setName, nF, nJobs, label(nF), label(nF + 1)); %#ok<AGROW>
                end
            end
            % stopped between sets: the set that was running finished its last job, so no set is part-way,
            % but sets later in the queue never started -> still the same run, Continue picks them up
            if ~canResume && nDone > 0 && nFresh > 0
                canResume = true;
            end
            if ~canResume
                return
            end
            msg = sprintf('Run "%s" (started %s) has jobs left to do. Output folder: %s', obj.runName, obj.runStart, obj.outRoot);
            msg = [msg newline newline char(strjoin(lines, newline))];
            if nDone > 0
                msg = [msg newline sprintf('  %d set(s) already finished: Continue leaves them alone.', nDone)];
            end
            if nFresh > 0
                msg = [msg newline sprintf('  %d set(s) not started in this run: Continue runs them from the first job.', nFresh)];
            end
            msg = [msg newline newline 'Continue = pick up where it stopped, same run name. New run = asks for a new name ' ...
                'and runs every ticked job again (earlier output is kept; repeated steps get the next round number).'];
        end

        function nFinished = finishedJobs(obj, i)
            % how many jobs the current run already finished on set i (0 for a new run or a changed job list)
            nFinished = 0;
            sessionID = obj.sessionName(i);
            if isempty(obj.runId) || isempty(sessionID) || ~isKey(obj.progress, sessionID)
                return
            end
            saved = obj.progress(sessionID);
            if strcmp(saved.runId, obj.runId) && isequal(string(saved.jobs), obj.jobs)
                nFinished = saved.nFinished;
            end
            if isKey(obj.rerunFrom, sessionID)   % marked for rerun: jobs from that one on count as not done
                nFinished = min(nFinished, obj.rerunFrom(sessionID) - 1);
            end
        end

        function obj = saveProgress(obj, i, cfg_full, nFinished, currentFile)
            % after each job: writes the set's done tags and how far this run got, to
            % <data_out>\Configurations\<sessionID>_doneJobs.mat and _runProgress.mat
            % runProgress.files{k} = the .set the data was in after job k, runProgress.startFile = what the
            % run started from (used by Rerun to find the file that went into a job)
            sessionID = char(cfg_full.sessionID);
            configDir = fullfile(char(cfg_full.paths.data_out), 'Configurations');
            doneJobs = obj.queue(i).state.doneJobs;
            files = cell(1, numel(obj.jobs));
            startFile = obj.runStartFile;
            if isKey(obj.progress, sessionID)
                old = obj.progress(sessionID);
                if strcmp(old.runId, obj.runId) && isfield(old, 'files') && numel(old.files) == numel(files)
                    files = old.files;
                    if isempty(startFile), startFile = old.startFile; end
                end
            end
            files(nFinished+1:end) = {''};   % a rerun forgets what came after
            for kk = 1:min(nFinished - 1, numel(obj.savedAfter))   % "save at end": files the jobs did write along the way
                if isempty(files{kk}) && ~isempty(obj.savedAfter{kk}), files{kk} = obj.savedAfter{kk}; end
            end
            files{nFinished} = currentFile;
            runProgress = struct('runId', obj.runId, 'jobs', obj.jobs, 'nFinished', nFinished, ...
                'files', {files}, 'startFile', startFile);
            obj.progress(sessionID) = runProgress;
            try
                save(fullfile(configDir, [sessionID '_doneJobs.mat']), 'doneJobs');
                save(fullfile(configDir, [sessionID '_runProgress.mat']), 'runProgress');
            catch ME
                warning('bipate:progressSave', 'Could not save the progress for %s: %s', sessionID, ME.message);
            end
        end

        function obj = syncDone(obj)
            % reads what earlier runs did to each set from <outRoot>\<sessionID>\Configurations
            if isempty(obj.outRoot)
                return
            end
            for i = 1:numel(obj.queue)
                sessionID = obj.sessionName(i);
                if isempty(sessionID)
                    continue
                end
                configDir = fullfile(obj.outRoot, sessionID, 'Configurations');
                doneFile = fullfile(configDir, [sessionID '_doneJobs.mat']);
                if isfile(doneFile)
                    loaded = load(doneFile, 'doneJobs');
                    obj.queue(i).state.doneJobs = loaded.doneJobs;
                end
                progressFile = fullfile(configDir, [sessionID '_runProgress.mat']);
                if isfile(progressFile)
                    loaded = load(progressFile, 'runProgress');
                    obj.progress(sessionID) = loaded.runProgress;
                end
            end
        end

        function obj = setState(obj, i, status, message)
            obj.queue(i).state.status = status;
            obj.queue(i).state.message = char(message);
            obj.refresh();
            drawnow;
        end

        function ok = checkEEGLABPath(obj)
            % runs when the app opens (and again before a run): the EEGLAB folder saved in
            % BIPATE_user\eeglabPath.mat (read by cfg_init into cfg.paths.eeglab) must exist and hold
            % eeglab.m; if not, asks for the folder and saves the answer. ok = false if the user cancels.
            ok = true;
            saved = string(obj.cfg.paths.eeglab);
            if strlength(saved) > 0 && isfile(fullfile(saved, 'eeglab.m'))
                return
            end
            uialert(obj.f, ['Pick the EEGLAB folder (the one holding eeglab.m). It is saved, so this is only ', ...
                'asked again if the folder moves.'], 'EEGLAB folder', 'Icon', 'info', ...
                'CloseFcn', @(~, ~) uiresume(obj.f));
            uiwait(obj.f);
            eeglabPath = uigetdir('', 'Select the EEGLAB folder');
            figure(obj.f);
            if isequal(eeglabPath, 0) || ~isfile(fullfile(eeglabPath, 'eeglab.m'))
                ok = false;
                uialert(obj.f, 'No EEGLAB folder set (no eeglab.m there). You will be asked again before a run.', ...
                    'EEGLAB folder', 'Icon', 'warning');
                return
            end
            save(fullfile(obj.cfg.paths.userPath, "eeglabPath.mat"), "eeglabPath");
            obj.cfg.paths.eeglab = string(eeglabPath);
        end

        function obj = startEEGLAB(obj)
            % puts EEGLAB on the path once per MATLAB session (checkEEGLABPath asks for the folder if needed)
            if ~obj.checkEEGLABPath()
                error('The EEGLAB folder is needed to run the pipeline.');
            end
            if ~exist('pop_loadset', 'file')
                addpath(char(obj.cfg.paths.eeglab));
                eeglab nogui
            end
            check_dependencies();
        end

        function obj = saveManifest(obj)
            % autosave next to the output, so Load batch can pick up after a crash
            if isempty(obj.outRoot)
                return
            end
            batch = obj.batchStruct();
            try
                save(fullfile(obj.outRoot, 'bipate_batch_autosave.mat'), 'batch');
            catch ME
                warning('bipate:autosave', 'Batch autosave failed: %s', ME.message);
            end
        end

        function showStatus(obj, i, k, jobLabel)
            % IN:  i = set number, k = job number in obj.jobs, jobLabel = that job's name
            % OUT: none. Opens (first call) or updates a small window in the top-right corner that shows which
            %      set and job are running, a bar for jobs done on this set, the start time, and a Stop button.
            %      It never takes focus, so a job's own windows (dialogs, review plots) stay on top of it.
            %      MATLAB runs one thing at a time, so it can only change between jobs, not during one; the
            %      estimates are clock times ("done about 12:05") so they stay right while a long job runs.
            nJobs = numel(obj.jobs);
            if isempty(obj.statusFig) || ~isvalid(obj.statusFig)
                scr = get(0, 'ScreenSize');
                obj.statusFig = uifigure('Name', 'BIPATE is running', 'Color', obj.mainColor, 'Resize', 'off', ...
                    'Position', [scr(3) - 520, scr(4) - 360, 490, 300], 'CloseRequestFcn', @(~, ~) obj.requestStop());
                sg = uigridlayout(obj.statusFig, [4 1], 'RowHeight', {'1x', 22, 30, 42}, 'BackgroundColor', obj.mainColor);
                obj.statusText = uilabel(sg, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top');
                obj.statusTime = uilabel(sg, 'Text', '', 'FontWeight', 'bold');
                obj.statusTimer = timer('Period', 1, 'ExecutionMode', 'fixedSpacing', 'BusyMode', 'drop', ...
                    'TimerFcn', @(~, ~) obj.tickStatus());
                start(obj.statusTimer);
                % note: an EMPTY MajorTicks makes a linear gauge fail to draw, and every control after it in the grid
                % then stays at its default size (that was the narrow Stop button); end ticks with blank labels instead
                obj.statusGauge = uigauge(sg, 'linear', 'Limits', [0 max(nJobs, 1)], 'MajorTicks', [0 max(nJobs, 1)], ...
                    'MajorTickLabels', {'', ''}, 'MinorTicks', 0:max(nJobs, 1));
                obj.statusStop = uibutton(sg, 'Text', 'Stop after this job', 'BackgroundColor', [0.85 0.82 0.95], 'FontSize', 14, ...
                    'ButtonPushedFcn', @(~, ~) obj.requestStop());
            end
            [obj.etaText, jobEnd] = obj.estimateLeft(i, k);
            jobEndText = '';
            if ~isempty(jobEnd), jobEndText = [', done about ' jobEnd]; end
            obj.statusText.Text = sprintf(['Set %d of %d: %s\n' ...
                'Job %d of %d: %s   (started %s%s)\n\n' ...
                'If a job needs your input, its window opens in front of this one. '  ...
                'Closing this window also stops the batch after the current job.'], ...
                i, numel(obj.queue), obj.queue(i).identity.fileName, k, nJobs, jobLabel, ...
                char(datetime('now', 'Format', 'HH:mm')), jobEndText);
            obj.tickStatus();
            obj.statusGauge.Value = k - 1;   % jobs finished on this set
            % a full drawnow plus a short pause: a new window is drawn by a separate renderer, and a job that
            % starts computing straight away (ICA) otherwise keeps it blank or hidden until the job ends
            drawnow
            pause(0.2)
        end

        function tickStatus(obj)
            % IN/OUT: none. Rewrites the time line of the status window: time since Run batch + the estimate.
            %         Called every second by statusTimer; a timer only gets a turn while MATLAB is not busy
            %         with a calculation, so the clock can pause during a long job and catch up after it.
            if isempty(obj.statusTime) || ~isvalid(obj.statusTime) || isempty(obj.runTic)
                return
            end
            elapsed = duration(0, 0, toc(obj.runTic), 'Format', 'hh:mm:ss');
            obj.statusTime.Text = sprintf('Running for %s%s', char(elapsed), obj.etaText);
        end

        function [txt, jobEnd] = estimateLeft(obj, i, k)
            % IN:  i = set running now, k = job starting now
            % OUT: jobEnd = clock time this job should finish ('HH:mm'), '' with no estimate for it
            %      txt = '   |   batch done about 13:10' from jobTimes (seconds per channel x sample of earlier runs,
            %      scaled to this set); '' until every job still to come has run at least once. Time spent
            %      in a job's dialogs is part of what was measured, so it is a typical time, not a promise.
            txt = '';
            jobEnd = '';
            dataSize = 0;
            sessionID = obj.sessionName(i);
            % only this run's progress counts: an older run's files list can be shorter than this job list
            if isKey(obj.progress, sessionID) && isfield(obj.progress(sessionID), 'files') ...
                    && strcmp(obj.progress(sessionID).runId, obj.runId)
                files = obj.progress(sessionID).files;
                last = find(~cellfun(@isempty, files(1:min(k-1, numel(files)))), 1, 'last');
                if ~isempty(last) && isfile(files{last})
                    try
                        m = matfile(files{last});   % header only, the data is not read
                        dataSize = double(m.nbchan) * double(m.pnts) * double(m.trials);
                    catch
                    end
                end
            end
            if dataSize == 0, return; end
            jobRate = jobTimes('rate', obj.jobs(k));   % this job on its own, even if a later one has no estimate
            if ~isnan(jobRate)
                jobEnd = clockAfter(jobRate * dataSize);
            end
            later = find(obj.jobOn(i, :));
            left = 0;
            for kk = later(later >= k)
                rate = jobTimes('rate', obj.jobs(kk));
                if isnan(rate), return; end   % a job with no earlier run: no estimate yet
                left = left + rate * dataSize;
            end
            setsAfter = numel(obj.queue) - i;   % assume the sets still to come are about this size
            for kk = 1:numel(obj.jobs)
                left = left + setsAfter * jobTimes('rate', obj.jobs(kk)) * dataSize;
            end
            if isnan(left), return; end
            txt = sprintf('   |   batch done about %s', clockAfter(left));
        end

        function obj = setRunning(obj, isRunning)
            % locks every control except Stop while a batch runs
            obj.running = isRunning;
            if isRunning
                set(findobj(obj.f, '-property', 'Enable'), 'Enable', 'off');
                obj.stopBut.Enable = 'on';
            else
                set(findobj(obj.f, '-property', 'Enable'), 'Enable', 'on');
                obj.stopBut.Enable = 'off';
                obj.stopBut.Text = 'Stop';
            end
            obj.fillPlanTable();
        end

        function obj = requestStop(obj)
            % the batch stops before its next job; a running step is never interrupted
            obj.stopRequested = true;
            obj.stopBut.Text = 'Stopping after this job...';
            if ~isempty(obj.statusStop) && isvalid(obj.statusStop)
                obj.statusStop.Text = 'Stopping after this job...';
                obj.statusStop.Enable = 'off';
            end
        end

        function showRunName(obj)
            % puts the current run's name in the BIPATE title bar so it is always visible ("BIPATE" when none)
            if isempty(obj.f) || ~isvalid(obj.f)
                return
            end
            if isempty(obj.runName)
                obj.f.Name = 'BIPATE';
                txt = 'Run: (none yet)';
            else
                obj.f.Name = ['BIPATE   |   run: ' char(obj.runName)];
                txt = ['Run: ' char(obj.runName)];
            end
            if ~isempty(obj.runLabel) && isvalid(obj.runLabel)
                obj.runLabel.Text = txt;
                obj.runLabel.FontAngle = 'normal';
            end
        end

        function finishRun(obj)
            % end of a batch, also after an error
            setappdata(0, 'bipateBatch', false);
            setappdata(0, 'bipateICAOverviewShown', false);
            setappdata(0, 'bipateDeferSave', false);   % steps run on their own save as usual
            batchShared('stop');
            if ~isempty(obj.statusTimer) && isvalid(obj.statusTimer)
                stop(obj.statusTimer);
                delete(obj.statusTimer);
            end
            obj.statusTimer = [];
            if ~isempty(obj.statusFig) && isvalid(obj.statusFig)
                delete(obj.statusFig);
            end
            obj.statusFig = [];
            if ~isvalid(obj.f)
                return
            end
            % each step on its own: an error in one (it runs from onCleanup, where errors are only warnings)
            % must not leave every button greyed out
            steps = {@() obj.setRunning(false), @() obj.refresh(), @() obj.refreshJobs(), @() figure(obj.f)};
            for s = 1:numel(steps)
                try
                    steps{s}();
                catch ME
                    fprintf(2, 'BIPATE: clean-up after the batch hit an error: %s\n', ME.message);
                    obj.running = false;
                    set(findobj(obj.f, '-property', 'Enable'), 'Enable', 'on');
                end
            end
            if ~obj.closeAfterStop && ~isempty(obj.batchSummary)   % on the BIPATE window itself, so nothing covers it
                uialert(obj.f, obj.batchSummary, 'Batch done', 'Icon', 'success');
            end
            obj.batchSummary = '';
            if obj.closeAfterStop
                delete(obj.f);
            end
        end

        function onClose(obj)
            % while a batch runs, ask first and close once the current step has finished
            if obj.running
                answer = uiconfirm(obj.f, 'A batch is running. Stop after the current step and close?', 'Close BIPATE', ...
                    'Options', {'Stop and close', 'Keep running'}, 'DefaultOption', 2, 'CancelOption', 2);
                if strcmp(answer, 'Stop and close')
                    obj.closeAfterStop = true;
                    obj.requestStop();
                end
                return
            end
            if ~isempty(obj.planTable) && isvalid(obj.planTable)
                delete(ancestor(obj.planTable, 'figure'));
            end
            delete(obj.f);
        end


        %% Batch history (History dropdown and its window)

        function folder = historyDir(obj)
            folder = fullfile(char(obj.cfg.paths.userPath), 'batch_history');
        end

        function writeHistory(obj, runStatus)
            % adds or updates this run's history entry; runStatus = 'running', 'finished' or 'stopped'
            if isempty(obj.runId)
                return
            end
            sets = struct('file', {}, 'sessionID', {}, 'status', {}, 'message', {});
            for i = 1:numel(obj.queue)
                entry = obj.queue(i);
                sets(i) = struct('file', char(entry.identity.filePath), 'sessionID', char(entry.identity.sessionID), ...
                    'status', char(entry.state.status), 'message', char(entry.state.message));
            end
            statuses = string({sets.status});
            finished = '';
            if ~strcmp(runStatus, 'running')
                finished = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm'));
            end
            historyEntry = struct('id', obj.runId, 'name', obj.runName, 'started', obj.runStart, 'finished', finished, ...
                'status', runStatus, 'outRoot', char(obj.outRoot), 'jobs', {cellstr(obj.jobs)}, 'nSets', numel(sets), ...
                'nDone', sum(statuses == "done"), 'nFailed', sum(statuses == "failed"), 'sets', sets);
            try
                batchHistory('save', obj.historyDir(), historyEntry, obj.batchStruct());
            catch ME
                warning('bipate:history', 'Could not write the batch history: %s', ME.message);
            end
            if ~strcmp(runStatus, 'running')
                obj.refreshHistory();
            end
        end

        function refreshHistory(obj)
            % History dropdown: placeholder, the 8 newest runs, then "More..."
            try
                history = batchHistory('list', obj.historyDir());
            catch ME
                warning('bipate:history', 'Could not read the batch history: %s', ME.message);
                history = [];
            end
            nShown = min(numel(history), 8);
            labels = cell(1, nShown);
            ids = cell(1, nShown);
            for h = 1:nShown
                labels{h} = historyLabel(history(h));
                ids{h} = history(h).id;
            end
            set(obj.histDD, 'Items', [{'Recent batches'}, labels, {'More...'}], 'ItemsData', [{''}, ids, {'more'}]);
            obj.histDD.Value = '';
        end

        function obj = onHistory(obj, src)
            % a run loads that batch; "More..." opens the history window
            choice = src.Value;
            src.Value = '';
            if isempty(choice)
                return
            end
            if strcmp(choice, 'more')
                obj.showHistory();
            else
                obj.openHistory(choice, []);
            end
        end

        function obj = openHistory(obj, id, setRows)
            % loads history run id into the app; setRows = [] for every set, or the rows to load
            if obj.running
                return
            end
            if ~isempty(obj.queue)
                answer = uiconfirm(obj.f, 'Replace the sets and jobs currently in the app with this batch?', 'Load batch', ...
                    'Options', {'Replace', 'Cancel'}, 'DefaultOption', 1, 'CancelOption', 2);
                if ~strcmp(answer, 'Replace')
                    return
                end
            end
            try
                batch = batchHistory('load', obj.historyDir(), id);
            catch ME
                uialert(obj.f, ME.message, 'Could not load batch', 'Icon', 'error');
                return
            end
            if ~isempty(setRows)
                batch.queue = batch.queue(setRows);
                if isfield(batch, 'jobOn') && size(batch.jobOn, 1) >= max(setRows)
                    batch.jobOn = batch.jobOn(setRows, :);
                end
            end
            obj.applyBatch(batch);
        end

        function obj = showHistory(obj)
            % "More...": every run (top) and the sets of the highlighted run (bottom)
            history = batchHistory('list', obj.historyDir());
            if isempty(history)
                uialert(obj.f, 'No batches have been run yet.', 'History', 'Icon', 'info');
                return
            end
            histFig = uifigure("Name", 'Batch history', "Color", obj.mainColor, ...
                "Position", [obj.f.Position(1:2) + 40, min(1000, obj.f.Position(3)), min(560, obj.f.Position(4))]);
            histGrid = uigridlayout(histFig, [5 1], "RowSpacing", 4, "Padding", [8 8 8 8], "BackgroundColor", obj.mainColor);
            histGrid.RowHeight = {20, '1x', 20, '1x', 30};
            runsLabel = uilabel(histGrid, "Text", 'Batches (newest first)', "FontWeight", 'bold');
            runsLabel.Layout.Row = 1;
            runTable = table(string({history.name})', string({history.started})', string({history.status})', ...
                [history.nSets]', [history.nDone]', [history.nFailed]', ...
                string(arrayfun(@(h) strjoin(h.jobs, ', '), history, 'UniformOutput', false)), string({history.outRoot})', ...
                'VariableNames', {'Name', 'Started', 'Status', 'Sets', 'Done', 'Failed', 'Jobs', 'Output folder'});
            runList = uitable(histGrid, "Data", runTable, "SelectionType", 'row', "Multiselect", 'off', "RowName", {});
            runList.Layout.Row = 2;
            setsLabel = uilabel(histGrid, "Text", 'Sets in the highlighted batch (highlight rows to load only those)', ...
                "FontWeight", 'bold');
            setsLabel.Layout.Row = 3;
            setList = uitable(histGrid, "SelectionType", 'row', "Multiselect", 'on', "RowName", {});
            setList.Layout.Row = 4;
            buttonStrip = uigridlayout(histGrid, [1 4], "Padding", [0 0 0 0], "ColumnSpacing", 6, "BackgroundColor", obj.mainColor);
            buttonStrip.Layout.Row = 5;
            obj.makeButton(buttonStrip, 1, 'Load whole batch', @(~, ~) loadRun(false));
            obj.makeButton(buttonStrip, 2, 'Load highlighted sets', @(~, ~) loadRun(true));
            obj.makeButton(buttonStrip, 3, 'Open output folder', @(~, ~) openOutput());
            obj.makeButton(buttonStrip, 4, 'Close', @(~, ~) delete(histFig));
            runList.SelectionChangedFcn = @(~, ~) showSets();
            runList.Selection = 1;
            showSets();

            function showSets()
                runRow = runList.Selection;
                if isempty(runRow)
                    return
                end
                sets = history(runRow(1)).sets;
                if isempty(sets)
                    setList.Data = table();
                else
                    [~, names, exts] = cellfun(@fileparts, {sets.file}, 'UniformOutput', false);
                    setList.Data = table(string(strcat(names, exts))', string({sets.sessionID})', string({sets.status})', ...
                        string({sets.message})', 'VariableNames', {'Recording', 'Session', 'Status', 'Message'});
                end
                setList.Selection = [];
            end

            function loadRun(onlyHighlighted)
                runRow = runList.Selection;
                if isempty(runRow)
                    return
                end
                setRows = [];
                if onlyHighlighted
                    setRows = unique(setList.Selection(:))';
                    if isempty(setRows)
                        uialert(histFig, 'Highlight one or more sets first.', 'No sets', 'Icon', 'info');
                        return
                    end
                end
                delete(histFig);
                obj.openHistory(history(runRow(1)).id, setRows);
            end

            function openOutput()
                runRow = runList.Selection;
                if isempty(runRow)
                    return
                end
                folder = history(runRow(1)).outRoot;
                if isfolder(folder)
                    winopen(folder);
                else
                    uialert(histFig, ['Folder not found: ' folder], 'Output folder', 'Icon', 'warning');
                end
            end
        end
    end

    methods (Static)
        function addRepoPaths()
            % IN:  none. bipate.m sits in the repo root, so only that folder has to be on the path.
            % OUT: none. Adds <repo>\functions and all its subfolders to the MATLAB path (this session only).
            repoRoot = fileparts(mfilename('fullpath'));
            addpath(genpath(fullfile(repoRoot, 'functions')));
        end
    end
end


function closeNewFigures(figsBefore)
% closes the plain figures (eegplot, plots) opened since figsBefore was taken; app windows (uifigures, e.g.
% the Job plan) are left alone
figsNow = findall(groot, 'Type', 'figure');
newFigs = figsNow(~ismember(figsNow, figsBefore));
for fig = newFigs(:)'
    if isvalid(fig) && ~matlab.ui.internal.isUIFigure(fig) && ~strcmp(fig.Tag, 'bipateKeep')   % bipateKeep = notices meant to stay up
        delete(fig);
    end
end
end

function clearRejInfo()
% removes segmentRejection's global (eegplot's REJECT button writes into it) once a set is finished
clear global rejInfo
end

function text = listText(list)
% list of tags as 'a, b' ('none' when empty)
if isempty(list)
    text = 'none';
else
    text = strjoin(cellstr(string(list)), ', ');
end
end

function label = historyLabel(entry)
% one History dropdown entry, e.g. "pilot_batch (2026-10-18 19:13) | 2 sets: 2 done, 0 failed | finished"
name = entry.name;
if isempty(name)
    name = 'unnamed';
end
label = sprintf('%s (%s) | %d sets: %d done, %d failed | %s', name, entry.started, entry.nSets, entry.nDone, ...
    entry.nFailed, entry.status);
end

function tf = writtenSince(file, startNum)
% true when file was saved at or after startNum (a datenum), i.e. by this run rather than left over from an
% earlier one at the same path; 5 s of slack for the file server's clock
info = dir(file);
tf = ~isempty(info) && info.datenum >= startNum - 5/86400;
end

function txt = clockAfter(secs)
% the clock time secs seconds from now: 'HH:mm', with the weekday added when it is not today
finish = datetime('now') + seconds(secs);
if isequal(dateshift(finish, 'start', 'day'), dateshift(datetime('now'), 'start', 'day'))
    txt = char(datetime(finish, 'Format', 'HH:mm'));
else
    txt = char(datetime(finish, 'Format', 'EEE HH:mm'));
end
end

function label = shortLabel(text, maxChars)
% the first maxChars characters of text, with ... when it was cut
text = char(text);
if numel(text) > maxChars
    label = [strtrim(text(1:maxChars)) '...'];
else
    label = text;
end
end
