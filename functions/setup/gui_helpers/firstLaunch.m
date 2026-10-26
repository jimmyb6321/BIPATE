function userInfo = firstLaunch(varPath, eeglabGuess)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/25/2026

% First-launch window for BIPATE. Asks who is using this copy (name, institution, how they heard about
% bipate) and where EEGLAB lives, saves both into permanent_variables, and - only if the user ticks the
% box - opens a pre-filled Google Form in their browser so they can tell the developer they use it.
% Nothing is sent from MATLAB itself; the user presses Submit on the form.

% IN:   varPath      = <userpath>\BIPATE_user (bipateUserDir) (char/string), where userInfo.mat and eeglabPath.mat go
%       eeglabGuess  = EEGLAB folder to pre-fill (char/string, may be empty)

% OUT:  userInfo = struct (also saved as BIPATE_user\userInfo.mat)
%           name, credentials, institution, heardFrom = char, as typed (credentials e.g. 'PhD', may be empty)
%           sharedWithDev                  = logical, true if the form was opened
%           created                        = char, datetime of first launch
%       empty [] if the window was closed without saving

arguments
    varPath     (1,1) string
    eeglabGuess (1,1) string = ""
end

% Google Form that collects opt-in usage reports. Leave FORM_URL empty until the form exists: the box is
% then shown disabled. FORM_FIELDS are the form's "entry.<id>" names for name / institution / credentials / heard from
% (Google Forms > three-dot menu > Get pre-filled link shows them).
FORM_URL    = "https://docs.google.com/forms/d/e/1FAIpQLSegO2tHdDGBQDV53B9nNG9tVdXB-1sM0O71s-cIOcZXV3m3Zg/viewform";
FORM_FIELDS = ["entry.285668221", "entry.535359678", "entry.1206406431", "entry.416954879"];   % Name, Institution, Credentials, How did you hear about BIPATE?

heardOptions = {'Colleague / lab member', 'Paper or poster', 'GitHub', 'Conference or workshop', ...
    'Search engine', 'Other'};

userInfo = [];

% ---- window -------------------------------------------------------------------------------------------
f = uifigure('Name', 'Welcome to BIPATE', 'Position', [500 310 600 476], 'Resize', 'off', ...
    'WindowStyle', 'modal');
g = uigridlayout(f, [10 3], 'RowHeight', {50, 30, 30, 30, 30, 30, 30, 34, 40, 36}, ...
    'ColumnWidth', {200, '1x', 80}, 'Padding', [16 16 16 16], 'RowSpacing', 8);

intro = uilabel(g, 'Text', ['First time here - tell BIPATE who is processing, so each dataset''s log can ', ...
    'record it, and point it at your EEGLAB folder. Saved on this computer only.'], 'WordWrap', 'on');
intro.Layout.Row = 1; intro.Layout.Column = [1 3];

uilabel(g, 'Text', 'Name');
nameBox = uieditfield(g, 'text');
nameBox.Layout.Column = [2 3];

uilabel(g, 'Text', 'Credentials (optional)');
credBox = uieditfield(g, 'text', 'Placeholder', 'e.g. PhD, MD, MS, BS, RPSGT');
credBox.Layout.Column = [2 3];

uilabel(g, 'Text', 'Institution');
instBox = uieditfield(g, 'text');
instBox.Layout.Column = [2 3];

uilabel(g, 'Text', 'How did you hear about BIPATE?');
heardBox = uidropdown(g, 'Items', heardOptions, 'Editable', 'on', 'Value', heardOptions{1});
heardBox.Layout.Column = [2 3];

uilabel(g, 'Text', 'EEGLAB folder');
eeglabBox = uieditfield(g, 'text', 'Value', char(eeglabGuess), ...
    'Placeholder', 'folder holding eeglab.m');
uibutton(g, 'Text', 'Browse', 'ButtonPushedFcn', @(~, ~) browseEEGLAB());

shareBox = uicheckbox(g, 'Text', 'Let the developer know I''m using BIPATE (opens a form; you press Submit)');
shareBox.Layout.Row = 7; shareBox.Layout.Column = [1 3];
listNote = uilabel(g, 'WordWrap', 'on', 'FontAngle', 'italic', 'FontSize', 11, 'Text', ...
    ['Submitting the form also adds you to the BIPATE email list for update news. To be taken off it, ' ...
    'email bipatecoding@gmail.com.']);
listNote.Layout.Row = 8; listNote.Layout.Column = [1 3];
if strlength(FORM_URL) == 0
    shareBox.Enable = 'off';
    shareBox.Text = 'Let the developer know I''m using BIPATE (form not set up yet)';
    listNote.Visible = 'off';
end

msg = uilabel(g, 'Text', '', 'FontColor', [0.7 0 0], 'WordWrap', 'on');
msg.Layout.Row = 9; msg.Layout.Column = [1 3];

btnRow = uigridlayout(g, [1 3], 'ColumnWidth', {'1x', 100, 100}, 'Padding', [0 0 0 0]);
btnRow.Layout.Row = 10; btnRow.Layout.Column = [1 3];
uilabel(btnRow, 'Text', '');
uibutton(btnRow, 'Text', 'Later', 'ButtonPushedFcn', @(~, ~) delete(f));   % nothing saved: asked again next launch, sets not stamped
uibutton(btnRow, 'Text', 'Save', 'ButtonPushedFcn', @(~, ~) onSave(), ...
    'BackgroundColor', [0.85 0.82 0.95]);

applyTheme(f);   % BIPATE colours
uiwait(f);   % returns when the window is deleted (Save or Later or X)

% ---- callbacks ----------------------------------------------------------------------------------------
    function browseEEGLAB()
        picked = uigetdir(eeglabBox.Value, 'Select the EEGLAB folder (holding eeglab.m)');
        figure(f);   % uigetdir drops the window behind MATLAB
        if ~isequal(picked, 0)
            eeglabBox.Value = picked;
        end
    end

    function onSave()
        name = strtrim(nameBox.Value);
        inst = strtrim(instBox.Value);
        eeglabPath = strtrim(eeglabBox.Value);
        if isempty(name)
            msg.Text = 'Please enter a name (it goes in the "processed by" line of each log).';
            return
        end
        if isempty(eeglabPath) || ~isfile(fullfile(eeglabPath, 'eeglab.m'))
            msg.Text = 'That EEGLAB folder has no eeglab.m in it - pick the folder that does.';
            return
        end

        userInfo = struct('name', name, 'credentials', strtrim(credBox.Value), 'institution', inst, 'heardFrom', char(heardBox.Value), ...
            'sharedWithDev', shareBox.Value, 'created', char(datetime('now')));
        save(fullfile(varPath, 'userInfo.mat'), 'userInfo');
        save(fullfile(varPath, 'eeglabPath.mat'), 'eeglabPath');

        if shareBox.Value
            vals = [string(name), string(inst), string(userInfo.credentials), string(userInfo.heardFrom)];   % same order as FORM_FIELDS
            query = strjoin(FORM_FIELDS + "=" + arrayfun(@(s) string(urlencode(char(s))), vals), "&");
            web(FORM_URL + "?usp=pp_url&" + query, '-browser');
        end
        delete(f);
    end
end
