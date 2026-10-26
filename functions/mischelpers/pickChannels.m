function [picked, ok] = pickChannels(titleText, promptText, labels, ticked, extraColumn)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/22/2026

% Tick-box channel picker (replaces listdlg where picking nothing is a valid answer). The prompt wraps
% instead of being cut off, and Select all / Select none buttons sit above the list.

% IN:   titleText = window title
%       promptText = instructions shown above the list (wraps)
%       labels = cell array of channel labels
%       ticked = (optional) logical vector, channels ticked when the window opens
%       extraColumn = (optional) {header, cell array of text}, an extra read-only column (e.g. channel type)

% OUT:  picked = indices (into labels) of the ticked channels, possibly empty
%       ok = false if the window was cancelled or closed

arguments
    titleText {mustBeTextScalar}
    promptText {mustBeTextScalar}
    labels {mustBeText}
    ticked {mustBeNumericOrLogical} = []
    extraColumn cell = {}
end

labels = cellstr(labels(:));
nChan = numel(labels);
if nargin < 4 || isempty(ticked), ticked = false(nChan, 1); end
ticked = logical(ticked(:));

tableData = [num2cell(ticked), labels];
columnNames = {'Pick', 'Channel'};
columnWidth = {40, 'auto'};
if nargin >= 5 && ~isempty(extraColumn)
    tableData = [tableData, cellstr(extraColumn{2}(:))];
    columnNames{end+1} = extraColumn{1};
    columnWidth = {40, 'auto', 'auto'};
end

picked = [];
ok = false;
scr = get(groot, 'ScreenSize');
fig = uifigure('Name', titleText, 'Position', [scr(3)/2 - 210, scr(4)/2 - 260, 420, 520], ...
    'Color', [220/255, 208/255, 255/255], 'WindowStyle', 'modal');
fig.CloseRequestFcn = @(~, ~) uiresume(fig);
grid = uigridlayout(fig, [4 1], 'RowHeight', {'fit', 28, '1x', 32}, 'Padding', [10 10 10 10], ...
    'BackgroundColor', [220/255, 208/255, 255/255]);
promptLabel = uilabel(grid, 'Text', promptText, 'WordWrap', 'on', 'FontSize', 12);
promptLabel.Layout.Row = 1;

topButtons = uigridlayout(grid, [1 3], 'ColumnWidth', {100, 100, '1x'}, 'Padding', [0 0 0 0], ...
    'BackgroundColor', [220/255, 208/255, 255/255]);
topButtons.Layout.Row = 2;
makeButton(topButtons, 1, 'Select all', @(~, ~) setAll(true));
makeButton(topButtons, 2, 'Select none', @(~, ~) setAll(false));

channelTable = uitable(grid, 'Data', tableData, 'ColumnName', columnNames, 'RowName', {}, ...
    'ColumnEditable', [true, false(1, numel(columnNames) - 1)], 'ColumnWidth', columnWidth);
channelTable.Layout.Row = 3;

bottomButtons = uigridlayout(grid, [1 3], 'ColumnWidth', {'1x', 90, 90}, 'Padding', [0 0 0 0], ...
    'BackgroundColor', [220/255, 208/255, 255/255]);
bottomButtons.Layout.Row = 4;
okButton = makeButton(bottomButtons, 2, 'OK', @(~, ~) finish(true));
okButton.BackgroundColor = [0.45 0.75 0.45];
makeButton(bottomButtons, 3, 'Cancel', @(~, ~) finish(false));

applyTheme(fig);   % BIPATE colours
uiwait(fig);
if isvalid(fig)
    delete(fig);
end

    function setAll(value)
        channelTable.Data(:, 1) = {value};
    end

    function finish(accepted)
        if accepted
            picked = find(cell2mat(channelTable.Data(:, 1)));
            picked = picked(:)';
            ok = true;
        end
        uiresume(fig);
    end
end

function button = makeButton(parent, col, text, callback)
button = uibutton(parent, 'Text', text, 'BackgroundColor', [0.82 0.79 0.92], 'ButtonPushedFcn', callback);
button.Layout.Row = 1;
button.Layout.Column = col;
end
