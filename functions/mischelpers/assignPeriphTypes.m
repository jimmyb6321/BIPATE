
function periph_types = assignPeriphTypes(EEG, periphSel)

% Author: James Barlow
% Created: 05/08/2026
% Last updated: 10/22/2026

% Dialog for assigning a type (EOG, ECG, EMG, ...) to each selected peripheral channel, pre-filled from
% detectPeriphs. Layout, top to bottom: instructions | "Set all to" strip | scrolling channel list (channel,
% type dropdown, whether the type was guessed from the name) | OK / Cancel. Only the list scrolls, so the
% buttons stay in view however many channels there are.

% IN:   EEG = EEGLAB struct
%       periphSel = logical [1 x nbchan], true = peripheral channel

% OUT:  periph_types = cell [nPeriph x 1] of type names in channel order; {} if none selected, [] if cancelled

arguments
    EEG (1,1) struct
    periphSel {mustBeNumericOrLogical}
end

if sum(periphSel) == 0
    periph_types = {};
    return; 
end

[looksPeriph, suggType, matcher] = detectPeriphs(EEG, periphSel);   % suggested type per channel + allowed types
nowPeriphs = find(periphSel);
nPer = numel(nowPeriphs);
bg = [220/255, 208/255, 255/255];
buttonColor = [0.82 0.79 0.92];

scr = get(0, 'ScreenSize');
figW = 480;
figH = min(190 + 32 * nPer, scr(4) * 0.7);
fig = uifigure('Name', 'Assign Peripheral Channel Types', 'Color', bg, ...
    'Position', [(scr(3) - figW)/2, (scr(4) - figH)/2, figW, figH]);
fig.CloseRequestFcn = @(~,~) uiresume(fig);
fig.UserData.confirmed = false;   % only OK sets this true

outer = uigridlayout(fig, [4 1], 'RowHeight', {'fit', 30, '1x', 34}, 'Padding', [10 10 10 10], ...
    'RowSpacing', 8, 'BackgroundColor', bg);
uilabel(outer, 'Text', ['Choose a type for each non-EEG channel. Types guessed from the channel name are ', ...
    'already filled in; check the ones marked "no match".'], 'WordWrap', 'on');

% "Set all to" strip
allStrip = uigridlayout(outer, [1 3], 'ColumnWidth', {80, 140, 90}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
uilabel(allStrip, 'Text', 'Set all to', 'HorizontalAlignment', 'right');
allDD = uidropdown(allStrip, 'Items', matcher, 'Value', matcher{end});
uibutton(allStrip, 'Text', 'Apply', 'BackgroundColor', buttonColor, 'ButtonPushedFcn', @(~,~) setAll());

% channel list: header row + one row per channel
list = uigridlayout(outer, [nPer + 1, 3], 'Scrollable', 'on', 'BackgroundColor', [1 1 1], ...
    'ColumnWidth', {130, 150, '1x'}, 'RowHeight', [{20}, repmat({26}, 1, nPer)], 'RowSpacing', 4);
heads = {'Channel', 'Type', 'Guessed from name'};
for h = 1:3
    head = uilabel(list, 'Text', heads{h}, 'FontWeight', 'bold');
    head.Layout.Row = 1;
    head.Layout.Column = h;
end
dropdowns = cell(nPer, 1);
for i = 1:nPer
    lab = uilabel(list, 'Text', EEG.chanlocs(nowPeriphs(i)).labels);
    lab.Layout.Row = i + 1;
    lab.Layout.Column = 1;
    dropdowns{i} = uidropdown(list, 'Items', matcher, 'Value', suggType{i});
    dropdowns{i}.Layout.Row = i + 1;
    dropdowns{i}.Layout.Column = 2;
    if looksPeriph(i)
        note = uilabel(list, 'Text', 'yes', 'FontColor', [0.2 0.5 0.2]);
    else
        note = uilabel(list, 'Text', 'no match', 'FontColor', [0.75 0.2 0.2], 'FontWeight', 'bold');
    end
    note.Layout.Row = i + 1;
    note.Layout.Column = 3;
end

buttons = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 0 0 0], 'BackgroundColor', bg);
okButton = uibutton(buttons, 'Text', 'OK', 'BackgroundColor', [0.45 0.75 0.45], 'ButtonPushedFcn', @(~,~) okPressed());
okButton.Layout.Column = 2;
cancelButton = uibutton(buttons, 'Text', 'Cancel', 'BackgroundColor', buttonColor, 'ButtonPushedFcn', @(~,~) uiresume(fig));
cancelButton.Layout.Column = 3;

applyTheme(fig);   % BIPATE colours
uiwait(fig);
% cancelled or window closed
if ~isvalid(fig) || ~fig.UserData.confirmed
    periph_types = [];
    if isvalid(fig), delete(fig); end
    return;
end
periph_types = cellfun(@(d) d.Value, dropdowns, 'UniformOutput', false);
delete(fig);

    function setAll()
        for k = 1:nPer
            dropdowns{k}.Value = allDD.Value;
        end
    end

    function okPressed()
        fig.UserData.confirmed = true;
        uiresume(fig);
    end
end
