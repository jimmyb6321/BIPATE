function fig = settingsWindow(onSaved)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Settings window (replaces the old user-preferences dialog). Sections listed down the left side:
%   General      default cap / file type / ICA method / artifact mode for new sets, default output folder,
%                EEGLAB folder
%   My Pipeline  named pipelines for "Add pipeline" (the default from pipeline.json is fixed)
%   Misc         notification sound and Done boxes, whether QC figures open when a step runs on its own
%   one tab per job, listing that job's settings from the "settings" entry of jobs.json (jobs without
%   settings show their description; they ask what they need while running)
%
% Where things are stored: every setting is a cfg field named by its key (e.g. 'filter.highpass'). Changed
% values are saved as overrides in BIPATE_user\userPreferences.mat (prefs.overrides, rows of
% {key, value}); cfgUpdate applies them on top of cfg_init's defaults every time a cfg is built, so a new
% batch picks them up. "Reset this tab" removes the tab's overrides (back to cfg_init's defaults or the older saved preferences).
% Named pipelines are saved as prefs.pipelines (pipelineStore); the EEGLAB folder in eeglabPath.mat.

% IN:   onSaved = (optional) function handle called with no inputs after a save (bipate reloads its cfg)
% OUT:  fig = the settings window (uifigure)

arguments
    onSaved = []
end

cfg = cfg_init();
prefsFile = fullfile(cfg.paths.userPath, 'userPreferences.mat');
catalog = jobCatalog();
bg = [220/255, 208/255, 255/255];

fig = uifigure('Name', 'BIPATE settings', 'Color', bg, 'Position', centerOnScreen(820, 600));
outer = uigridlayout(fig, [2 1], 'RowHeight', {'1x', 34}, 'Padding', [8 8 8 8], 'BackgroundColor', bg);
% left: a list of sections (wide enough for the long job names); right: the chosen section's page.
% Pages are panels stacked in the same cell; only the one picked in the list is visible.
body = uigridlayout(outer, [1 2], 'ColumnWidth', {240, '1x'}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
nav = uilistbox(body, 'Items', {}, 'ValueChangedFcn', @(src, ~) showTab(src.Value));
nav.Layout.Row = 1;
nav.Layout.Column = 1;
tabs = gobjects(0);   % one panel per section, in list order
tabTitles = {};

% controls(k): one row per editable setting -> key, type, the widget, which tab it is on
controls = struct('key', {}, 'type', {}, 'widget', {}, 'tab', {});
storedTab = [];   % the Edit event markers (video) page (stored event list), for Reset this tab

% ---- General
generalDefs = {
    struct('key', 'defaults.cap_type', 'label', 'Cap for new sets', 'type', 'choice', 'options', {cfg.recording.caplist}, 'help', '')
    struct('key', 'defaults.icaMethod', 'label', 'ICA method for new sets', 'type', 'choice', 'options', {{'runica', 'Picard', 'AMICA', 'FastICA'}}, 'help', 'runica = extended Infomax, built into EEGLAB; Picard, AMICA and FastICA need their plugins')
    struct('key', 'defaults.mode_default', 'label', 'Artifact mode for new sets', 'type', 'choice', 'options', {{'Manual', 'Semi-automatic'}}, 'help', '')
    struct('key', 'general.outRoot', 'label', 'Default output folder', 'type', 'folder', 'options', {{}}, 'help', 'Filled in when BIPATE opens; leave empty to choose each time')
    struct('key', 'general.saveMode', 'label', 'Saving', 'type', 'choice', 'options', {{'After every step', 'Once per set, at the end'}}, 'help', 'Starting value of the main window''s "Save only at the end of each set" box')};
generalTab = addTab('General', 'Defaults for new sets and folders.', generalDefs);
eeglabRow(generalTab.grid);

% ---- My Pipeline
pipelineTab();

% ---- Misc
miscDefs = {
    struct('key', 'misc.sound', 'label', 'Chime when a step finishes', 'type', 'logical', 'options', {{}}, 'help', '')
    struct('key', 'misc.doneBox', 'label', 'Show a "done" box when a step finishes', 'type', 'logical', 'options', {{}}, 'help', 'Batches show one box at the end either way')
    struct('key', 'misc.showQC', 'label', 'Open QC figures', 'type', 'choice', 'options', {{'Single-set runs only', 'Single-job runs only', 'After every job', 'Never'}}, 'help', 'QC figures are always saved; this only decides when they open on screen. A step run on its own always shows them unless Never.')};
addTab('Misc', 'Notifications and figures.', miscDefs);

% ---- one tab per job
for j = 1:numel(catalog)
    job = catalog(j);
    if strcmp(job.id, 'chanSetup')
        customCapTab(job);   % Channel setup page = the saved custom caps (list, rename, new file, delete)
    elseif strcmp(job.id, 'videoEditor')
        storedEventsTab(job);   % Edit event markers page = the stored event list for "Add event"
    else
        addTab(job.label, job.description, job.settings);
    end
end

% ---- buttons
strip = uigridlayout(outer, [1 5], 'ColumnWidth', {130, '1x', 90, 110, 90}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
makeButton(strip, 1, 'Reset this tab', @(~, ~) resetTab());
makeButton(strip, 3, 'Save', @(~, ~) saveAll(false));
saveClose = makeButton(strip, 4, 'Save & close', @(~, ~) saveAll(true));
saveClose.BackgroundColor = [0.45 0.75 0.45];
makeButton(strip, 5, 'Cancel', @(~, ~) delete(fig));

% fill the section list now that every page exists, and open on the first one
nav.Items = tabTitles;
nav.ItemsData = 1:numel(tabTitles);
nav.Value = 1;
showTab(1);

% =====================================================================================================
    function tab = newTab(title)
        % an empty page for one section, listed under title in the left-hand list
        tab = uipanel(body, 'BorderType', 'none', 'BackgroundColor', bg, 'Visible', 'off');
        tab.Layout.Row = 1;
        tab.Layout.Column = 2;
        tabs(end + 1) = tab;
        tabTitles{end + 1} = title;
    end

    function showTab(n)
        % shows page n (its number in the list) and hides the rest
        for p = 1:numel(tabs)
            tabs(p).Visible = p == n;
        end
    end

    function tabInfo = addTab(title, description, defs)
        % a tab with a wrapped description, then one row (label | control) per setting in defs
        if isempty(defs), defs = {}; end
        if isstruct(defs), defs = num2cell(defs); end
        tab = newTab(title);
        rowHeights = repmat({28}, 1, max(numel(defs), 1));   % one row per setting; lists get more room
        for d = 1:numel(defs)
            if strcmp(defs{d}.type, 'multichoice'), rowHeights{d} = 120; end
        end
        grid = uigridlayout(tab, [numel(rowHeights) + 2, 2], 'ColumnWidth', {250, '1x'}, ...
            'RowHeight', [{'fit'}, rowHeights, {'1x'}], 'Scrollable', 'on', 'BackgroundColor', bg, 'RowSpacing', 8);
        intro = uilabel(grid, 'Text', description, 'WordWrap', 'on', 'FontAngle', 'italic');
        intro.Layout.Row = 1;
        intro.Layout.Column = [1 2];
        if isempty(defs)
            note = uilabel(grid, 'Text', 'No settings here: this job asks what it needs while it runs.');
            note.Layout.Row = 2;
            note.Layout.Column = [1 2];
        end
        for d = 1:numel(defs)
            addSetting(grid, d + 1, defs{d}, tab);
        end
        tabInfo = struct('tab', tab, 'grid', grid);
    end

    function addSetting(grid, row, def, tab)
        % label + control for one setting; the control starts at the current value from cfg
        label = uilabel(grid, 'Text', def.label, 'WordWrap', 'on');
        label.Layout.Row = row;
        label.Layout.Column = 1;
        if isfield(def, 'help') && ~isempty(def.help), label.Tooltip = def.help; end
        current = getByKey(cfg, def.key, []);
        switch def.type
            case 'logical'
                widget = uicheckbox(grid, 'Text', '', 'Value', logical(defaultIfEmpty(current, true)));
            case 'choice'
                options = optionList(def);
                value = char(string(defaultIfEmpty(current, options{1})));
                if ~ismember(value, options), options = [{value}, options]; end
                widget = uidropdown(grid, 'Items', options, 'Value', value);
            case 'multichoice'
                options = optionList(def);
                widget = uilistbox(grid, 'Items', options, 'Multiselect', 'on', ...
                    'Value', intersect(cellstr(string(defaultIfEmpty(current, {}))), options, 'stable'));
            case 'folder'
                sub = uigridlayout(grid, [1 2], 'ColumnWidth', {'1x', 70}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
                widget = uieditfield(sub, 'text', 'Value', char(string(defaultIfEmpty(current, ''))));
                makeButton(sub, 2, 'Browse', @(~, ~) browseInto(widget));
                sub.Layout.Row = row;
                sub.Layout.Column = 2;
            otherwise   % 'number', 'numbers', 'text': typed in, checked on save
                widget = uieditfield(grid, 'text', 'Value', valueToText(current));
        end
        if ~strcmp(def.type, 'folder')
            widget.Layout.Row = row;
            widget.Layout.Column = 2;
        end
        if isfield(def, 'help') && ~isempty(def.help), widget.Tooltip = def.help; end
        controls(end + 1) = struct('key', def.key, 'type', def.type, 'widget', widget, 'tab', tab);
    end

    function eeglabRow(grid)
        % EEGLAB folder: saved straight to eeglabPath.mat (read by cfg_init), not as an override
        row = numel(grid.RowHeight);
        grid.RowHeight = [grid.RowHeight(1:end-1), {28}, {'1x'}];
        label = uilabel(grid, 'Text', 'EEGLAB folder');
        label.Layout.Row = row;
        label.Layout.Column = 1;
        sub = uigridlayout(grid, [1 2], 'ColumnWidth', {'1x', 70}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
        sub.Layout.Row = row;
        sub.Layout.Column = 2;
        shown = uilabel(sub, 'Text', char(string(cfg.paths.eeglab)), 'Tooltip', 'Folder holding eeglab.m');
        makeButton(sub, 2, 'Change', @(~, ~) pickEEGLAB(shown));
    end

    function customCapTab(job)
        % Channel setup page: the custom caps saved by cap type 'Other' (prefs.custom_chanlocs, rows of
        % {'CUSTOM: <name>', <.mat file holding chanlocs_custom>}), with Rename / Replace locations file /
        % Delete. Changes are staged here and written by Save (saveAll reads fig.UserData.customCaps).
        tab = newTab(job.label);
        grid = uigridlayout(tab, [4 1], 'RowHeight', {'fit', 22, '1x', 30}, 'BackgroundColor', bg);
        intro = uilabel(grid, 'Text', [job.description ' Custom caps saved with cap type ''Other'' are listed below; ', ...
            'changes are written when you press Save. Sets already in the queue keep the cap name they were given, ', ...
            'so pick the cap again on those after a rename or delete.'], 'WordWrap', 'on', 'FontAngle', 'italic');
        intro.Layout.Row = 1;
        head = uilabel(grid, 'Text', 'Saved custom caps', 'FontWeight', 'bold');
        head.Layout.Row = 2;
        capTable = uitable(grid, 'ColumnName', {'Name', 'Channels', 'Locations file'}, 'ColumnEditable', false, ...
            'ColumnWidth', {170, 70, 'auto'}, 'SelectionType', 'row', 'RowName', {});
        capTable.Layout.Row = 3;
        capButtons = uigridlayout(grid, [1 4], 'ColumnWidth', {90, 170, 90, '1x'}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
        capButtons.Layout.Row = 4;
        makeButton(capButtons, 1, 'Rename', @(~, ~) renameCap());
        makeButton(capButtons, 2, 'Replace locations file', @(~, ~) replaceCap());
        makeButton(capButtons, 3, 'Delete', @(~, ~) deleteCap());

        % caps(k): .name (without 'CUSTOM: '), .file (.mat path), .nChan, .newLocs (replacement chanlocs; [] = unchanged)
        caps = struct('name', {}, 'file', {}, 'nChan', {}, 'newLocs', {});
        prefs0 = loadPrefs(prefsFile);
        if isfield(prefs0, 'custom_chanlocs')
            for ci = 1:numel(prefs0.custom_chanlocs)
                pair = prefs0.custom_chanlocs{ci};
                capName = strtrim(char(pair{1}));
                if startsWith(capName, 'CUSTOM: '), capName = strtrim(extractAfter(capName, 'CUSTOM: ')); end
                nChan = NaN;
                try
                    S = load(char(pair{2}), 'chanlocs_custom');
                    nChan = numel(S.chanlocs_custom);
                catch
                    % file missing or unreadable: listed with NaN channels so it can be re-filed or deleted
                end
                caps(end + 1) = struct('name', capName, 'file', char(pair{2}), 'nChan', nChan, 'newLocs', []); %#ok<AGROW>
            end
        end
        showCaps();
        fig.UserData.customCaps = @currentCaps;   % read by saveAll (nested, so it sees the latest edits)

        function showCaps()
            % refreshes the table from caps (a staged new file shows its channel count and "(new file on Save)")
            data = cell(numel(caps), 3);
            for r = 1:numel(caps)
                data(r, :) = {caps(r).name, caps(r).nChan, caps(r).file};
                if ~isempty(caps(r).newLocs)
                    data(r, 2:3) = {numel(caps(r).newLocs), '(new locations file, written on Save)'};
                end
            end
            capTable.Data = data;
        end

        function k = pickedCap()
            % the highlighted row ([] and a note when none)
            k = [];
            if ~isempty(capTable.Selection)
                k = capTable.Selection(1);
            end
            if isempty(k)
                uialert(fig, 'Click a cap in the list first.', 'No cap selected', 'Icon', 'info');
            end
        end

        function renameCap()
            k = pickedCap();
            if isempty(k), return; end
            answer = inputdlg('New name:', 'Rename custom cap', [1 40], {caps(k).name});
            figure(fig);
            if isempty(answer) || isempty(strtrim(answer{1})), return; end
            newName = strtrim(answer{1});
            if any(strcmpi({caps([1:k-1, k+1:end]).name}, newName))
                uialert(fig, sprintf('A cap called "%s" already exists.', newName), 'Name taken');
                return
            end
            caps(k).name = newName;
            showCaps();
        end

        function replaceCap()
            % reads a new locations file with EEGLAB's readlocs; it replaces the cap's chanlocs on Save
            k = pickedCap();
            if isempty(k), return; end
            [fname, fpath] = uigetfile({'*.sfp;*.ced;*.elp;*.elc;*.loc;*.locs;*.xyz;*.txt', 'Channel location files'}, ...
                sprintf('New locations file for %s', caps(k).name));
            figure(fig);
            if isequal(fname, 0), return; end
            try
                locs = readlocs(fullfile(fpath, fname));
            catch ME
                uialert(fig, ME.message, 'Could not read the file');
                return
            end
            caps(k).newLocs = locs;
            showCaps();
        end

        function deleteCap()
            k = pickedCap();
            if isempty(k), return; end
            answer = uiconfirm(fig, sprintf(['Delete the custom cap "%s"? (Only when you press Save; its .mat file ', ...
                'stays on disk.)'], caps(k).name), 'Delete cap', 'Options', {'Delete', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2);
            if strcmp(answer, 'Delete')
                caps(k) = [];
                showCaps();
            end
        end

        function [pairs, writes] = currentCaps()
            % pairs = prefs.custom_chanlocs as it should be saved; writes(w).file/.locs = caps given a new file
            pairs = cell(1, numel(caps));
            writes = struct('file', {}, 'locs', {});
            for q = 1:numel(caps)
                pairs{q} = {['CUSTOM: ' caps(q).name], string(caps(q).file)};
                if ~isempty(caps(q).newLocs)
                    writes(end + 1) = struct('file', caps(q).file, 'locs', {caps(q).newLocs}); %#ok<AGROW>
                end
            end
        end
    end

    function pipelineTab()
        % pipeline picker (default + the user's named pipelines; New / Rename / Delete) above two lists:
        % every job (left) and the selected pipeline's order (right), with add / remove / move buttons.
        % The default (pipeline.json) cannot be edited; New makes an editable copy of the one shown.
        tab = newTab('My Pipeline');
        grid = uigridlayout(tab, [4 3], 'ColumnWidth', {'1x', 110, '1x'}, 'RowHeight', {'fit', 30, 22, '1x'}, ...
            'BackgroundColor', bg);
        intro = uilabel(grid, 'Text', ['Pipelines for "Add pipeline" in the main window. The default one is fixed; ', ...
            '"New" starts an empty pipeline to fill from the job list. A job can be added more than once ', ...
            '(e.g. segment rejection and ICA twice).'], 'WordWrap', 'on', 'FontAngle', 'italic');
        intro.Layout.Row = 1;
        intro.Layout.Column = [1 3];
        pick = uigridlayout(grid, [1 5], 'ColumnWidth', {65, '1x', 80, 80, 80}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
        pick.Layout.Row = 2;
        pick.Layout.Column = [1 3];
        pickLabel = uilabel(pick, 'Text', 'Pipeline', 'FontWeight', 'bold');
        pickLabel.Layout.Column = 1;
        pipeDD = uidropdown(pick, 'Items', {''}, 'ValueChangedFcn', @(~, ~) showSelected());
        pipeDD.Layout.Column = 2;
        makeButton(pick, 3, 'New', @(~, ~) newPipeline());
        renameBtn = makeButton(pick, 4, 'Rename', @(~, ~) renamePipeline());
        deleteBtn = makeButton(pick, 5, 'Delete', @(~, ~) deletePipeline());
        head1 = uilabel(grid, 'Text', 'Jobs', 'FontWeight', 'bold');
        head1.Layout.Row = 3; head1.Layout.Column = 1;
        head2 = uilabel(grid, 'Text', 'Jobs in this pipeline, in order', 'FontWeight', 'bold');
        head2.Layout.Row = 3; head2.Layout.Column = 3;
        allList = uilistbox(grid, 'Items', {catalog.label}, 'ItemsData', {catalog.id}, 'Multiselect', 'on');
        allList.Layout.Row = 4; allList.Layout.Column = 1;
        buttons = uigridlayout(grid, [6 1], 'RowHeight', repmat({30}, 1, 6), 'Padding', [0 30 0 0], 'BackgroundColor', bg);
        buttons.Layout.Row = 4; buttons.Layout.Column = 2;
        pipeList = uilistbox(grid, 'Items', {}, 'Multiselect', 'off');
        pipeList.Layout.Row = 4; pipeList.Layout.Column = 3;
        editButtons = [stackButton(buttons, 1, 'Add  >', @(~, ~) addJobs()), ...
                       stackButton(buttons, 2, 'Remove', @(~, ~) removeJob()), ...
                       stackButton(buttons, 3, 'Move up', @(~, ~) moveJob(-1)), ...
                       stackButton(buttons, 4, 'Move down', @(~, ~) moveJob(1)), ...
                       stackButton(buttons, 5, 'Default order', @(~, ~) resetPipeline())];

        % pipes(p): .name, .jobs (string ids), .builtin; cur = the one shown; pipeIds = its jobs while editing
        pipes = pipelineStore('list', cfg.paths.userPath);
        for p = 1:numel(pipes)
            pipes(p).jobs = pipes(p).jobs(ismember(pipes(p).jobs, string({catalog.id})));   % jobs no longer in jobs.json
        end
        cur = min(2, numel(pipes));   % the user's first pipeline if there is one, else the default
        pipeIds = pipes(cur).jobs;
        fillDropdown();
        showSelected();
        fig.UserData.pipelines = @currentPipelines;   % read by saveAll (a nested function sees the latest state)

        function custom = currentPipelines()
            % the user's pipelines (default left out), as saved by pipelineStore('save', ...)
            custom = rmfield(pipes(~[pipes.builtin]), 'builtin');
        end

        function fillDropdown()
            pipeDD.Items = {pipes.name};
            pipeDD.ItemsData = num2cell(1:numel(pipes));
            pipeDD.Value = cur;
        end

        function showSelected()
            cur = pipeDD.Value;
            pipeIds = pipes(cur).jobs;
            editable = ~pipes(cur).builtin;
            set(editButtons, 'Enable', matlab.lang.OnOffSwitchState(editable));
            renameBtn.Enable = matlab.lang.OnOffSwitchState(editable);
            deleteBtn.Enable = matlab.lang.OnOffSwitchState(editable);
            showPipeline();
        end

        function keepEdit()
            pipes(cur).jobs = pipeIds;
            showPipeline();
        end

        function showPipeline()
            labels = strings(1, numel(pipeIds));
            for p2 = 1:numel(pipeIds)
                labels(p2) = sprintf('%d. %s', p2, catalog(strcmp({catalog.id}, pipeIds(p2))).label);
            end
            pipeList.Items = cellstr(labels);
            pipeList.ItemsData = num2cell(1:numel(pipeIds));
        end

        function name = askName(prompt, startName, others)
            % asks for a pipeline name; '' if cancelled, empty, or already used by one of others (any capitalisation)
            name = '';
            answer = inputdlg(prompt, 'Pipeline name', [1 50], {startName});
            figure(fig);
            if isempty(answer), return; end
            candidate = strtrim(answer{1});
            if isempty(candidate)
                return
            elseif any(strcmpi(candidate, others))
                uialert(fig, sprintf('There is already a pipeline called "%s".', candidate), 'Name taken');
                return
            end
            name = candidate;
        end

        function newPipeline()
            name = askName('Name for the new pipeline:', 'My pipeline', {pipes.name});
            if isempty(name), return; end
            pipes(end + 1) = struct('name', name, 'jobs', pipeIds([]), 'builtin', false);   % starts empty: add its jobs from the left
            cur = numel(pipes);
            fillDropdown();
            showSelected();
        end

        function renamePipeline()
            if pipes(cur).builtin, return; end
            name = askName('New name:', pipes(cur).name, {pipes([1:cur-1, cur+1:end]).name});
            if isempty(name), return; end
            pipes(cur).name = name;
            fillDropdown();
        end

        function deletePipeline()
            if pipes(cur).builtin, return; end
            answer = uiconfirm(fig, sprintf('Delete the pipeline "%s"? (Only when you press Save.)', pipes(cur).name), ...
                'Delete pipeline', 'Options', {'Delete', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(answer, 'Delete'), return; end
            pipes(cur) = [];
            cur = 1;
            fillDropdown();
            showSelected();
        end

        function addJobs()
            picked = string(allList.Value);
            if isempty(picked), return; end
            where = numel(pipeIds);
            if ~isempty(pipeList.Value), where = pipeList.Value; end
            pipeIds = [pipeIds(1:where), picked(:)', pipeIds(where+1:end)];
            keepEdit();
            pipeList.Value = where + numel(picked);
        end
        function removeJob()
            if isempty(pipeList.Value), return; end
            pipeIds(pipeList.Value) = [];
            keepEdit();
        end
        function moveJob(step)
            k = pipeList.Value;
            if isempty(k) || k + step < 1 || k + step > numel(pipeIds), return; end
            pipeIds([k, k + step]) = pipeIds([k + step, k]);
            keepEdit();
            pipeList.Value = k + step;
        end
        function resetPipeline()
            pipeIds = pipes(1).jobs;   % the default's order
            keepEdit();
        end
    end

    function storedEventsTab(job)
        % Edit event markers (video) page: a table of {type, label, color} rows saved as the override
        % 'video.storedEvents' (package defaults in cfg_init). The editor's "Add event" box lists them under the
        % recording's own types, and any event of a listed type is drawn in that row's color.
        tab = newTab(job.label);
        storedTab = tab;
        grid = uigridlayout(tab, [3 1], 'RowHeight', {'fit', '1x', 30}, 'BackgroundColor', bg, 'RowSpacing', 8);
        uilabel(grid, 'WordWrap', 'on', 'FontAngle', 'italic', 'Text', [job.description ' The stored events below are offered ' ...
            'in the editor''s "Add event" box, under the types already in the recording; picking a stored type fills in its label. ' ...
            'Events of a listed type are drawn in its color (others black). Color = #RRGGBB, or click row(s) and use Pick color.']);
        evTable = uitable(grid, 'Data', VideoEditorApp.normEvents(getByKey(cfg, 'video.storedEvents', cell(0, 3))), ...
            'ColumnName', {'Type (4 characters, e.g. eyeo)', 'Label', 'Color'}, 'ColumnEditable', [true true true], ...
            'ColumnWidth', {200, 'auto', 100}, 'CellSelectionCallback', @(~, e) pickRows(e), 'CellEditCallback', @(~, ~) refreshAll());
        btns = uigridlayout(grid, [1 4], 'ColumnWidth', {80, 120, 90, '1x'}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
        makeButton(btns, 1, 'Add row', @(~, ~) addRow());
        makeButton(btns, 2, 'Remove selected', @(~, ~) removeRows());
        makeButton(btns, 3, 'Pick color', @(~, ~) pickColor());
        picked = [];   % table rows last clicked
        fig.UserData.storedEvents = @currentStored;      % read by saveAll
        fig.UserData.storedEventsTable = evTable;        % reset by resetTab
        fig.UserData.storedEventsRefresh = @refreshAll;
        refreshAll();

        function pickRows(e)
            picked = unique(e.Indices(:, 1));
        end
        function addRow()
            evTable.Data(end + 1, :) = {'', '', '#000000'};
            refreshAll();
        end
        function removeRows()
            if isempty(picked)
                uialert(fig, 'Click a cell in the row(s) to remove first.', 'Remove', 'Icon', 'info');
                return
            end
            evTable.Data(picked(picked <= size(evTable.Data, 1)), :) = [];
            picked = [];
            refreshAll();
        end
        function pickColor()
            % color for the clicked row(s): copy the color of a type already on the list, or choose any color
            rows = picked(picked <= size(evTable.Data, 1));
            if isempty(rows)
                uialert(fig, 'Click a cell in the row(s) to color first.', 'Pick color', 'Icon', 'info');
                return
            end
            [norm3, bad] = VideoEditorApp.normEvents(evTable.Data);
            ok = setdiff(1:size(norm3, 1), bad);
            ok = ok(~cellfun(@isempty, norm3(ok, 1)));   % rows that can lend their color
            choice = '';   % '#RRGGBB' to use, 'custom' for the color chooser, '' = cancelled
            fpos = fig.Position;
            dlg = uifigure('Name', 'Marker color', 'WindowStyle', 'modal', 'Color', bg, ...
                'Position', [fpos(1) + fpos(3)/2 - 200, fpos(2) + fpos(4)/2 - 150, 400, 300]);
            dlg.CloseRequestFcn = @(~, ~) uiresume(dlg);
            g = uigridlayout(dlg, [6 3], 'RowHeight', {'fit', 22, 26, 30, '1x', 30}, 'ColumnWidth', {'1x', 40, 120}, 'BackgroundColor', bg);
            who = uilabel(g, 'WordWrap', 'on', 'FontWeight', 'bold', 'Text', ['Color for: ' strjoin(norm3(rows, 1)', ', ')]);
            who.Layout.Row = 1; who.Layout.Column = [1 3];
            hint = uilabel(g, 'Text', 'Same color as a type on the list:');
            hint.Layout.Row = 2; hint.Layout.Column = [1 3];
            names = {'(none on the list yet)'}; data = 0;
            if ~isempty(ok), names = strcat(norm3(ok, 1), {'   '}, norm3(ok, 3)); data = ok; end
            dd = uidropdown(g, 'Items', names, 'ItemsData', data, 'ValueChangedFcn', @(~, ~) showSwatch());
            dd.Layout.Row = 3; dd.Layout.Column = 1;
            swatch = uipanel(g, 'BorderType', 'line');
            swatch.Layout.Row = 3; swatch.Layout.Column = 2;
            useBtn = uibutton(g, 'Text', 'Use this color', 'ButtonPushedFcn', @(~, ~) done(norm3{dd.Value, 3}));
            useBtn.Layout.Row = 3; useBtn.Layout.Column = 3;
            useBtn.Enable = ~isempty(ok);
            other = uibutton(g, 'Text', 'Choose any color...', 'ButtonPushedFcn', @(~, ~) done('custom'));
            other.Layout.Row = 4; other.Layout.Column = [1 3];
            stop = uibutton(g, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) done(''));
            stop.Layout.Row = 6; stop.Layout.Column = 3;
            showSwatch();
            uiwait(dlg);
            if isvalid(dlg), delete(dlg); end
            figure(fig);
            if strcmp(choice, 'custom')   % the chooser opens after the box has closed (two modal windows clash)
                c = uisetcolor(VideoEditorApp.hexToRGB(norm3{rows(1), 3}), 'Marker color');
                figure(fig);
                choice = '';
                if numel(c) == 3, choice = sprintf('#%02X%02X%02X', round(255 * c)); end
            end
            if isempty(choice), return; end
            evTable.Data(rows, 3) = {choice};
            refreshAll();

            function showSwatch()
                if dd.Value > 0, swatch.BackgroundColor = VideoEditorApp.hexToRGB(norm3{dd.Value, 3}); end
            end
            function done(what)
                choice = what;
                uiresume(dlg);
            end
        end
        function refreshAll()
            % each Color cell shaded in its color (white text on dark ones)
            removeStyle(evTable);
            [norm3, bad] = VideoEditorApp.normEvents(evTable.Data);
            for r = setdiff(1:size(norm3, 1), bad)
                rgb = VideoEditorApp.hexToRGB(norm3{r, 3});
                ink = [0 0 0];
                if [0.299 0.587 0.114] * rgb' < 0.5, ink = [1 1 1]; end
                addStyle(evTable, uistyle('BackgroundColor', rgb, 'FontColor', ink), 'cell', [r 3]);
            end
        end
        function [ev, problem] = currentStored()
            % OUT: ev = n x 3 cellstr {type, label, '#RRGGBB'}; blank types dropped, each type kept once
            %      problem = '' or a message naming rows whose color is not #RRGGBB / a color letter
            [ev, bad] = VideoEditorApp.normEvents(evTable.Data);
            problem = '';
            if ~isempty(bad)
                problem = sprintf('Stored events: color not readable for %s (use #RRGGBB, e.g. #FF8000).', strjoin(ev(bad, 1), ', '));
            end
            if isempty(ev), return; end
            ev = ev(~cellfun(@isempty, ev(:, 1)), :);
            [~, first] = unique(ev(:, 1), 'stable');
            ev = ev(first, :);
        end
    end

    function resetTab()
        % removes the overrides of the settings on the selected tab and shows the defaults again
        tab = tabs(nav.Value);
        if ~isempty(storedTab) && isequal(tab, storedTab)   % stored event list: ask, then back to the package defaults
            answer = uiconfirm(fig, 'Put the stored event list (types, labels, colors) back to the package defaults?', 'Reset', ...
                'Options', {'Reset', 'Cancel'}, 'DefaultOption', 2, 'CancelOption', 2);
            if ~strcmp(answer, 'Reset'), return; end
            prefs = loadPrefs(prefsFile);
            if isfield(prefs, 'overrides') && ~isempty(prefs.overrides)
                prefs.overrides(strcmp(prefs.overrides(:, 1), 'video.storedEvents'), :) = [];
            end
            save(prefsFile, 'prefs');
            cfg = cfg_init();
            fig.UserData.storedEventsTable.Data = VideoEditorApp.normEvents(cfg.video.storedEvents);
            fig.UserData.storedEventsRefresh();
            if ~isempty(onSaved), onSaved(); end
            return
        end
        onTab = arrayfun(@(c) isequal(c.tab, tab), controls);
        if ~any(onTab)
            uialert(fig, 'Nothing on this tab to reset (use "Default order" on My Pipeline).', 'Reset', 'Icon', 'info');
            return
        end
        prefs = loadPrefs(prefsFile);
        keys = {controls(onTab).key};
        if isfield(prefs, 'overrides') && ~isempty(prefs.overrides)
            prefs.overrides(ismember(prefs.overrides(:, 1), keys), :) = [];
        end
        save(prefsFile, 'prefs');
        cfg = cfg_init();
        for c = find(onTab)
            setWidget(controls(c), getByKey(cfg, controls(c).key, []));
        end
        if ~isempty(onSaved), onSaved(); end
    end

    function saveAll(closeAfter)
        % reads every control, checks the typed numbers, saves the changed ones as overrides
        prefs = loadPrefs(prefsFile);
        if ~isfield(prefs, 'overrides') || isempty(prefs.overrides), prefs.overrides = cell(0, 2); end
        problems = {};
        for c = 1:numel(controls)
            [value, ok] = readWidget(controls(c));
            if ~ok
                problems{end + 1} = sprintf('%s: "%s" is not a valid %s', controls(c).key, controls(c).widget.Value, controls(c).type); %#ok<AGROW>
                continue
            end
            if isequaln(value, getByKey(cfg, controls(c).key, []))
                continue   % unchanged
            end
            row = find(strcmp(prefs.overrides(:, 1), controls(c).key), 1);
            if isempty(row), row = size(prefs.overrides, 1) + 1; end
            prefs.overrides(row, :) = {controls(c).key, value};
        end
        if ~isempty(problems)
            uialert(fig, problems, 'Not saved');
            return
        end
        if isfield(fig.UserData, 'customCaps')   % Channel setup page: renamed / deleted / re-filed custom caps
            [prefs.custom_chanlocs, capWrites] = fig.UserData.customCaps();
            for w = 1:numel(capWrites)
                chanlocs_custom = capWrites(w).locs;   % saved under the name chanSetup loads
                save(capWrites(w).file, 'chanlocs_custom');
            end
        end
        if isfield(fig.UserData, 'storedEvents')   % Edit event markers page: the stored event list
            [stored, problem] = fig.UserData.storedEvents();
            if ~isempty(problem)
                uialert(fig, problem, 'Not saved');
                return
            end
            row = find(strcmp(prefs.overrides(:, 1), 'video.storedEvents'), 1);
            if isempty(row), row = size(prefs.overrides, 1) + 1; end
            prefs.overrides(row, :) = {'video.storedEvents', stored};
        end
        save(prefsFile, 'prefs');
        if isfield(fig.UserData, 'pipelines')   % the user's named pipelines (written after the overrides)
            pipelineStore('save', cfg.paths.userPath, fig.UserData.pipelines());
        end
        cfg = cfg_init();
        if ~isempty(onSaved), onSaved(); end
        if closeAfter
            delete(fig);
        else
            uialert(fig, 'Settings saved. New batches use them.', 'Saved', 'Icon', 'success');
        end
    end

    function pickEEGLAB(shown)
        folder = uigetdir(char(string(cfg.paths.eeglab)), 'Select the EEGLAB folder');
        figure(fig);
        if isequal(folder, 0), return; end
        if ~isfile(fullfile(folder, 'eeglab.m'))
            uialert(fig, 'That folder has no eeglab.m.', 'Not an EEGLAB folder');
            return
        end
        eeglabPath = folder;
        save(fullfile(cfg.paths.userPath, 'eeglabPath.mat'), 'eeglabPath');
        shown.Text = folder;
    end

    function browseInto(field)
        folder = uigetdir(field.Value, 'Select a folder');
        figure(fig);
        if ~isequal(folder, 0), field.Value = folder; end
    end

    function options = optionList(def)
        % options from the definition, or from a cfg field when written as "cfg:<key>"
        options = {};
        if isfield(def, 'options'), options = def.options; end
        if ischar(options) || isstring(options)
            options = char(options);
            if startsWith(options, 'cfg:')
                options = getByKey(cfg, extractAfter(options, 'cfg:'), {});
            else
                options = {options};
            end
        end
        options = cellstr(string(options(:)'));
    end
end


% ======================================================================================================
function [value, ok] = readWidget(control)
% widget -> value of the right type; ok = false when typed text can't be read
ok = true;
widget = control.widget;
switch control.type
    case 'logical'
        value = logical(widget.Value);
    case 'choice'
        value = char(widget.Value);
    case 'multichoice'
        value = cellstr(widget.Value);
        value = value(:)';
    case {'text', 'folder'}
        value = strtrim(char(widget.Value));
    case 'number'
        text = strtrim(char(widget.Value));
        if isempty(text) || strcmpi(text, 'none') || strcmpi(text, 'nan')
            value = NaN;
        else
            value = str2double(text);
            ok = ~isnan(value);
        end
    case 'numbers'
        text = strtrim(regexprep(char(widget.Value), '[,;\[\]]', ' '));
        if isempty(text)
            value = [];
        else
            value = str2double(strsplit(text));
            ok = all(~isnan(value) | strcmpi(strsplit(text), 'nan'));
        end
    otherwise
        value = widget.Value;
end
end

function setWidget(control, value)
switch control.type
    case 'logical'
        control.widget.Value = logical(defaultIfEmpty(value, true));
    case 'choice'
        value = char(string(value));
        if ismember(value, control.widget.Items), control.widget.Value = value; end
    case 'multichoice'
        control.widget.Value = intersect(cellstr(string(value)), control.widget.Items, 'stable');
    case 'folder'
        control.widget.Value = char(string(defaultIfEmpty(value, '')));
    otherwise
        control.widget.Value = valueToText(value);
end
end

function text = valueToText(value)
if isempty(value) || (isnumeric(value) && isscalar(value) && isnan(value))
    text = '';   % NaN shows as empty (= none)
elseif isnumeric(value) || islogical(value)
    text = strjoin(arrayfun(@(v) num2str(v), double(value(:)'), 'UniformOutput', false), ' ');
else
    text = char(strjoin(string(value), ' '));
end
end

function value = getByKey(cfg, key, default)
% cfg field named by a dotted key ('filter.highpass'); default when any part is missing
parts = strsplit(key, '.');
value = cfg;
for p = 1:numel(parts)
    if ~isstruct(value) || ~isfield(value, parts{p})
        value = default;
        return
    end
    value = value.(parts{p});
end
end

function value = defaultIfEmpty(value, default)
if isempty(value), value = default; end
end

function prefs = loadPrefs(prefsFile)
prefs = struct();
if isfile(prefsFile)
    loaded = load(prefsFile);
    prefs = loaded.prefs;
end
end

function button = makeButton(parent, col, text, callback)
button = uibutton(parent, 'Text', text, 'BackgroundColor', [0.82 0.79 0.92], 'ButtonPushedFcn', callback);
button.Layout.Row = 1;
button.Layout.Column = col;
end

function button = stackButton(parent, row, text, callback)
button = uibutton(parent, 'Text', text, 'BackgroundColor', [0.82 0.79 0.92], 'ButtonPushedFcn', callback);
button.Layout.Row = row;
button.Layout.Column = 1;
end

function position = centerOnScreen(width, height)
scr = get(groot, 'ScreenSize');
position = [(scr(3) - width) / 2, (scr(4) - height) / 2, width, height];
end
