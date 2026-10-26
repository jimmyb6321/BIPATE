function EEG = segmentEEG(EEG, cfg_full)

% Author: James Barlow
% Created: 08/27/2026
% Last updated: 10/23/2026

% Rule builder for keeping/cutting stretches of a continuous recording by event times (span, global, or
% periodic rules). Not epoching: it only removes unneeded data. walkSeg applies the rules.

% IN:   EEG = continuous EEGLAB struct
%       cfg_full = configuration struct (passed on to walkSeg)

% OUT:  EEG = EEG struct after walkSeg (seg mask updated, optionally split); unchanged if cancelled
%       rules (local, passed to walkSeg)
%           eventList / eventLatencies (s) / eventLibrary = events, their times, unique event names
%           keepOrCut = 'cut' | 'keep'
%           specs(j) = one rule: .mode, .start/.end (anchor index, 'hh:mm:ss.SSS' offset),
%               .anchor/.period/.phase/.duration for periodic rules
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'segmentation');   % what must run first is listed in jobs.json
if EEG.trials > 1
    error('Cannot segment epoched data!')
end

% event names (label if present, else type) and times (s); segEvents is shared with walkSeg so both
% name events the same way
[fullEvents, eventLatencies] = segEvents(EEG);
numVent = numel(fullEvents);

% list labels "name hh:mm:ss.SSS"
latstring = duration([zeros(numVent, 1), zeros(numVent, 1), eventLatencies], 'Format', 'hh:mm:ss.SSS');
eventLabs = fullEvents(:) + "     " + string(latstring);   % gap between name and time

eventDur = duration(seconds(eventLatencies));

% rules start with one empty span rule
rules.eventLatencies = eventLatencies;
rules.eventList = fullEvents;
rules.eventLibrary = unique(fullEvents);
rules.keepOrCut = 'cut';
upperKC = containers.Map({'cut', 'keep'}, {'Cut', 'Keep'});   % rules value -> switch label
rules.specs(1).mode = 'span';
rules.specs(1).start = struct('anchor', 1, 'offset', "00:00:00.000");
rules.specs(1).end = struct('anchor', 1, 'offset', "00:00:00.000");

rules.specs(1).anchor = 1;   % periodic fields kept on every rule so specs stay one shape
rules.specs(1).period = '01:00:00.000';
rules.specs(1).phase = '00:15:00.000';
rules.specs(1).duration = '00:30:00.000';

scr = get(0, 'screenSize');
figW   = scr(3) * 0.6;
figH   = min(190 + 46 * max(numVent, 3), scr(4) * 0.7);   % room for at least 3 captioned rule rows

fig = uifigure('Name', 'SEGMENTATION', ...
    'Position', [scr(3)*0.35, scr(4)*0.3, figW, figH]);
fig.CloseRequestFcn =  @(~,~) uiresume(fig);

% layout: scrollable event list + rule rows on top; Cancel | cut/keep switch | OK below
gprime = uigridlayout(fig, [2, 3]);
gprime.RowHeight = {'1x', 50};
gprime.ColumnWidth = {'1x', '1x' '1x'};
nRows = numVent;
g = uigridlayout(gprime, [nRows + 1, 7]);
g.RowHeight = [{44}, repmat({46}, 1, nRows)];   % 46: caption + box
g.ColumnWidth = {'fit', '1x', 115, '1x', 115, 140, 60};   % event list as wide as its text; anchors share the rest
g.Layout.Row = 1;
g.Layout.Column = [1, 3];
g.Scrollable = 'on';

l1 = uilabel(g, 'Text', sprintf('Ordered Events List \n (Recording Relative Time)'), 'FontWeight', 'bold');
l1.Layout.Row = 1;
l1.Layout.Column = 1;
l2 = uilabel(g, 'Text', sprintf('Segmentation Rules\n(hover a box for help; times as hh:mm:ss.SSS or seconds)'), 'HorizontalAlignment', 'center');
l2.Layout.Row = 1;
l2.Layout.Column = [2,5];
l3 = uilabel(g, 'Text', 'Rule type', 'HorizontalAlignment', 'center');
l3.Layout.Row = 1;
l3.Layout.Column = 6;
l4 = uilabel(g, 'Text', 'Add rule',  'HorizontalAlignment', 'center');
l4.Layout.Row = 1;
l4.Layout.Column = 7;

% event list down column 1
for i = 1:numVent
    thisVent = eventLabs(i);

    tmpl = uilabel(g, 'Text', thisVent);
    tmpl.Layout.Row = i + 1;
    tmpl.Layout.Column = 1;
    tmpl.HorizontalAlignment = 'left';
end

redrawSeg();


okbutt = uibutton(gprime, 'Text', 'OK', 'ButtonPushedFcn', @(~,~) okpressed());
okbutt.Layout.Row = 2;
okbutt.Layout.Column = 3;

canbutt = uibutton(gprime, 'Text', 'CANCEL', 'ButtonPushedFcn', @(~,~) uiresume(fig));
canbutt.Layout.Row = 2;
canbutt.Layout.Column = 1;

kc = uiswitch(gprime, 'slider', 'Items', {'Cut', 'Keep'}, ...
    'Value', upperKC(rules.keepOrCut), ...
    'ValueChangedFcn', @(sccr, ~) setKeepCut(sccr));
kc.Layout.Row = 2;
kc.Layout.Column = 2;

fig.UserData.confirmed = false;



applyTheme(fig);   % BIPATE colours
uiwait(fig);
% the window goes away in every case (OK, Cancel or X); rules stays in this workspace
confirmed = isvalid(fig) && fig.UserData.confirmed;
if isvalid(fig), delete(fig); end
if ~confirmed
    return;
end

rules = nameAnchors(rules);   % store each anchor's event NAME too, so walkSeg finds events by name, not position
EEG = walkSeg(EEG, rules, cfg_full);

    % --- callbacks: each edits rules, then redraws if the row layout changed ---
    function setKeepCut(sccr)
        rules.keepOrCut = lower(sccr.Value);

    end
    function okpressed()
        % last check before closing: every periodic window must be shorter than its repeat
        for r = 1:numel(rules.specs)
            if strcmpi(rules.specs(r).mode, 'periodic') && ~windowFits(rules.specs(r))
                uialert(fig, sprintf('Rule %d: each window has to be shorter than the time between windows.', r), ...
                    'Periodic rule', 'Icon', 'warning');
                return
            end
        end
        fig.UserData.confirmed = true;
        uiresume(fig)
    end
    
    % new default span rule
    function  addNewRule()
        currRow = numel(rules.specs);
        rules.specs(currRow+1).start = struct('anchor', 1, 'offset', '00:00:00.000');
        rules.specs(currRow+1).end = struct('anchor', 1, 'offset', '00:00:00.000');
        rules.specs(currRow+1).anchor = 1;
        rules.specs(currRow+1).period = '01:00:00.000';
        rules.specs(currRow+1).phase = '00:15:00.000';
        rules.specs(currRow+1).duration = '00:30:00.000';
        rules.specs(currRow+1).mode = 'span';
        redrawSeg();
    end

    % rule type dropdown: 1 span, 2 global, 3 periodic (resets that rule's fields)
    function changeDrop(j, sccr)
        if sccr.Value == 1
            rules.specs(j).mode = 'span';
            rules.specs(j).start = struct('anchor', 1, 'offset', '00:00:00.000');
            rules.specs(j).end = struct('anchor', 1, 'offset', '00:00:00.000');
        elseif sccr.Value == 2
            rules.specs(j).mode = 'global';
            rules.specs(j).start = struct('anchor', 1, 'offset', '00:00:00.000');
            rules.specs(j).end = struct('anchor', 1, 'offset', '00:00:00.000');
        elseif sccr.Value == 3
            rules.specs(j).mode = 'periodic';
            rules.specs(j).anchor = 1;
            rules.specs(j).period = '01:00:00.000';
            rules.specs(j).phase = '00:15:00.000';
            rules.specs(j).duration = '00:30:00.000';
        end
        
        redrawSeg();
    end

    % anchor / offset edits are rejected (reverted) if the span would end before it starts
    function changeStart(j, sccr)
        fail = validateTimes(j, 'startanchor', sccr.Value);
            if fail 
                sccr.Value = rules.specs(j).start.anchor;
                return; 
            end
        rules.specs(j).start.anchor = sccr.Value;
    end
    function changeEnd(j, sccr)
        fail = validateTimes(j, 'endanchor', sccr.Value);
            if fail 
                sccr.Value = rules.specs(j).end.anchor;
                return; 
            end

        rules.specs(j).end.anchor = sccr.Value;
    end
    function changePeriodic(j, sccr)
        rules.specs(j).anchor = sccr.Value;
    end

    function changeOffset(j, sOrE, srrc)
        try
            newOff = string(toDuration(srrc.Value), 'hh:mm:ss.SSS');
            fail = validateTimes(j, [sOrE 'offset'], newOff);
            if fail, newOff = rules.specs(j).(sOrE).offset; end
        catch   % not a valid duration: keep the old one
            newOff = rules.specs(j).(sOrE).offset;
        end
        
        rules.specs(j).(sOrE).offset = newOff;
        srrc.Value = newOff;
    end
    % periodic period/phase/duration edits
    function changeTime(j, sOrE, src)
        % a periodic rule's period / phase / duration box; an unreadable time keeps the old value, and a
        % window as long as (or longer than) its repeat is refused, since the windows would join into one
        try
            newOff = string(toDuration(src.Value), 'hh:mm:ss.SSS');
        catch
            newOff = rules.specs(j).(sOrE);
        end
        trial = rules.specs(j);
        trial.(sOrE) = newOff;
        if ~windowFits(trial)
            uialert(fig, sprintf(['Each window (%s) has to be shorter than the time between windows (%s); ' ...
                'otherwise the windows join into one and cover everything.'], trial.duration, trial.period), ...
                'Periodic rule', 'Icon', 'warning');
            newOff = rules.specs(j).(sOrE);
        end
        rules.specs(j).(sOrE) = newOff;
        src.Value = newOff;
    end
    % delete a rule (deleting the last one leaves no rules: nothing is cut, or with Keep everything is kept)
    function removeRule(j)
        rules.specs(j) = [];
        redrawSeg();

    end


% rebuilds every rule row from rules.specs (rows tagged 'rulerow' so they can be cleared)
% one rule-row cell in g: a caption on top (small, grey) and a slot below for the box; returns the cell
    function cellGrid = field(j, col, caption)
        cellGrid = uigridlayout(g, [2 1], 'RowHeight', {14, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 1);
        cellGrid.Layout.Row = j + 1;
        cellGrid.Layout.Column = col;
        cellGrid.Tag = 'rulerow';
        cap = uilabel(cellGrid, 'Text', caption, 'FontSize', 10, 'FontColor', [0.35 0.35 0.45]);
        cap.Layout.Row = 1;
    end

    function redrawSeg()

    delete(findobj(g, 'Tag', 'rulerow'))
    
    nRules = numel(rules.specs);

    nRows = max(numVent, nRules+1) + 1;
    g.RowHeight = [{44} repmat({46}, 1, nRows-1)];

    for j = 1:nRules
        spec = rules.specs(j);
        
        switch spec.mode
            case 'span'
                lst = eventLabs; modeVal = 1;
            case 'global'
                lst = unique(fullEvents); modeVal = 2;
            case 'periodic'
                lst = strings(0, 1); modeVal = 3;
        end
        Items = ["Recording Start"; lst];
        idxVent = [0; (1:numel(lst))'];   % anchor 0 = recording start

        % anchors that don't exist in this mode's list fall back to recording start
        if ~ismember(spec.start.anchor, idxVent), spec.start.anchor = 0; end
        if ~ismember(spec.end.anchor, idxVent), spec.end.anchor = 0; end
        if ~ismember(spec.anchor, idxVent), spec.anchor = 0; end
        rules.specs(j) = spec;

        % columns 2-5: periodic = anchor | period | phase | duration; span/global = start | offset | end | offset
        % columns 2-5: periodic = anchor | period | phase | duration; span/global = start | offset | end | offset.
        % Every box sits under a small caption (field) that says what it is for this rule type.
        switch spec.mode
            case 'periodic', caps = ["Count from", "Repeat every", "First window starts after", "Each window lasts"];
            case 'global',   caps = ["Every event named", "+ offset (start)", "...to the next event named", "+ offset (end)"];
            otherwise,       caps = ["Start at", "+ offset (start)", "End at", "+ offset (end)"];
        end
        tip = 'Times as hh:mm:ss.SSS, or plain seconds (e.g. 90 or 2.5)';
        if strcmpi(spec.mode, 'periodic')
            c1 = uidropdown(field(j, 2, caps(1)), 'Value', rules.specs(j).anchor, 'Items', Items, 'ItemsData', idxVent, ...
                'Tooltip', 'Windows are counted from here (recording start for now)', ...
                'ValueChangedFcn', @(sccr, ~) changePeriodic(j, sccr));
            c2 = uieditfield(field(j, 3, caps(2)), 'text', 'Value', rules.specs(j).period, 'Tooltip', ['Start of one window to the start of the next. ' tip], ...
                'ValueChangedFcn', @(sccr, ~) changeTime(j, 'period', sccr));
            c3 = uieditfield(field(j, 4, caps(3)), 'text', 'Value', rules.specs(j).phase, 'Tooltip', ['Delay from the anchor to the first window. ' tip], ...
                'ValueChangedFcn', @(sccr, ~) changeTime(j, 'phase', sccr));
            c4 = uieditfield(field(j, 5, caps(4)), 'text', 'Value', rules.specs(j).duration, 'Tooltip', ['Length of each window. ' tip], ...
                'ValueChangedFcn', @(sccr, ~) changeTime(j, 'duration', sccr));
        else
            c1 = uidropdown(field(j, 2, caps(1)), "Value", rules.specs(j).start.anchor, 'Items', Items, 'ItemsData', idxVent, ...
                'ValueChangedFcn', @(sccr, ~) changeStart(j, sccr));
            c2 = uieditfield(field(j, 3, caps(2)), 'text', 'Value', rules.specs(j).start.offset, 'Tooltip', ['Shift the start (negative = earlier). ' tip], ...
                'ValueChangedFcn', @(sccr, ~) changeOffset(j, 'start', sccr));
            c3 = uidropdown(field(j, 4, caps(3)), "Value", rules.specs(j).end.anchor, 'Items', Items, 'ItemsData', idxVent, ...
                'ValueChangedFcn', @(sccr, ~) changeEnd(j, sccr));
            c4 = uieditfield(field(j, 5, caps(4)), 'text', 'Value', rules.specs(j).end.offset, 'Tooltip', ['Shift the end (negative = earlier). ' tip], ...
                'ValueChangedFcn', @(sccr, ~) changeOffset(j, 'end', sccr));
        end
        % column 6 rule type, column 7 delete
        c5 = uidropdown(field(j, 6, "Rule type"), 'Items', {'Single Span', 'Global Rule', 'Periodic Rule'}, ...
            'ItemsData', [1 2 3], 'Value', modeVal, 'ValueChangedFcn', @(sccr,~) changeDrop(j, sccr));
        c6 = uibutton(field(j, 7, ""), 'Text', 'DEL', 'ButtonPushedFcn', @(~, ~) removeRule(j));
        for w = [c1 c2 c3 c4 c5 c6], w.Layout.Row = 2; end   % under the caption in each little cell


    end
    addbutt = uibutton(g, 'Text', 'ADD', 'ButtonPushedFcn', @(~, ~) addNewRule());
    addbutt.Tag = 'rulerow';
    addbutt.Layout.Row = nRules + 2;
    addbutt.Layout.Column = 7;
    applyTheme(g);   % rebuilt rule rows get the BIPATE colours too

end

    % 1 if this edit would put a span's end before its start (with an alert); global/periodic always pass
    function fail = validateTimes(j, sccrType, aval)
        sanch = rules.specs(j).start.anchor;
        soffV = rules.specs(j).start.offset;
        eanch = rules.specs(j).end.anchor;
        eoffV = rules.specs(j).end.offset;

       
        switch sccrType
            case 'startoffset'
                soffV = aval;
            case 'endoffset'
                eoffV = aval;
            case 'startanchor'
                sanch = aval;
            case 'endanchor'
                eanch = aval;
        end

        if sanch == 0
            sanDur = duration("00:00:00.000");
        else
            sanDur = eventDur(sanch);
        end
        if eanch == 0
            eaDur = duration("00:00:00.000");
        else
            eaDur = eventDur(eanch);
        end
        if strcmpi(rules.specs(j).mode, 'span')
            if sanDur + duration(soffV) > eaDur + duration(eoffV)
                warnMe ="Your end time occurs before your start time!";
                uialert(fig, warnMe, "ERROR")
                fail = 1;
                return;
            else
                fail = 0;
                return;
            end
        else 
            fail = 0;
            return;

        end


            

        
    end

end

function rules = nameAnchors(rules)
% Writes each anchor's event name next to its index, so a rule keeps pointing at the same event even if the
% event list changes or the rule is reused on another recording (walkSeg resolves the names).
% IN:   rules = segmentation rules; anchors are indices (span: rules.eventList, global: rules.eventLibrary,
%           0 = recording start; periodic anchors are always 0 for now)
% OUT:  rules with .anchorName (string, "" = recording start) and .anchorNth (which occurrence of that name in
%           the event list; 1 for global rules, 0 for recording start) on .start, .end and the rule itself
c = cell(1, numel(rules.specs));
for j = 1:numel(rules.specs)
    sp = rules.specs(j);
    if strcmpi(sp.mode, 'global'), pool = rules.eventLibrary; else, pool = rules.eventList; end
    sp.start = addName(sp.start, pool, sp.mode);
    sp.end = addName(sp.end, pool, sp.mode);
    a = addName(struct('anchor', sp.anchor), rules.eventList, 'periodic');   % the periodic rule's own anchor
    sp.anchorName = a.anchorName;  sp.anchorNth = a.anchorNth;
    c{j} = sp;
end
rules.specs = [c{:}];
end

function a = addName(a, pool, mode)
% one anchor (struct with .anchor index into pool) -> adds .anchorName / .anchorNth
if isempty(a.anchor) || a.anchor < 1 || a.anchor > numel(pool)   % 0 = recording start (redrawSeg already maps bad indices to 0)
    a.anchorName = "";  a.anchorNth = 0;
else
    a.anchorName = string(pool(a.anchor));
    if strcmpi(mode, 'global')
        a.anchorNth = 1;                                               % library names are unique
    else
        a.anchorNth = nnz(pool(1:a.anchor) == pool(a.anchor));        % e.g. the 3rd "stim_on"
    end
end
end


% IN:  spec = one periodic rule (period, duration as hh:mm:ss.SSS text)
% OUT: tf = true when its window is shorter than its period (or a value can't be read, left to walkSeg)
function tf = windowFits(spec)
tf = true;
try
    tf = toDuration(char(spec.duration)) < toDuration(char(spec.period));
catch
end
end

% a typed time -> duration: plain seconds ("90", "2.5", "-1") or hh:mm:ss(.SSS); errors on anything else
function d = toDuration(txt)
secs = str2double(txt);
if ~isnan(secs)
    d = seconds(secs);
else
    d = duration(txt);
end
d.Format = 'hh:mm:ss.SSS';
end
