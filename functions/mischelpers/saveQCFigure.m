function saveQCFigure(fig, basePath, keepOpen)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% Saves a QC figure as <basePath>.fig and <basePath>.png, then closes it unless Settings > Misc "Open QC figures" wants it on screen (left open
% when a step is run on its own). A figure drawn hidden would also open hidden from its .fig file, so the
% saved copy is told to make itself visible when opened.

% IN:   fig = figure handle (e.g. from qcFigure, qcSpectopo, plotChannelPSD)
%       basePath = full path without extension, e.g. fullfile(qcSave, [sessionID '_badChanPSD'])
%       keepOpen = (optional, default false) true leaves it open and visible even in a batch, for figures
%           the user needs while reviewing (the caller closes them)
% OUT:  none (files written)

arguments
    fig (1,1) matlab.ui.Figure
    basePath {mustBeTextScalar}
    keepOpen (1,1) logical = false
end

drawnow;
fig.CreateFcn = 'set(gcbo, ''Visible'', ''on'')';
savefig(fig, [char(basePath) '.fig']);
saveas(fig, [char(basePath) '.png']);
fig.CreateFcn = '';
if keepOpen
    fig.Visible = 'on';
elseif ~showQC() || strcmp(fig.Visible, 'off')   % not meant to be on screen (Settings > Misc): closed after saving
    close(fig);
end
end
