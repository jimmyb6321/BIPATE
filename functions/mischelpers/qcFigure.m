function fig = qcFigure(varargin)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% New figure for a QC plot: shown or hidden as Settings > Misc "Open QC figures" says (showQC), hidden
% during a bipate batch (the plot is still drawn and saved by saveQCFigure, it just never pops up).

% IN:   varargin = any figure name/value pairs (e.g. 'Name', 'Color')
% OUT:  fig = figure handle

arguments (Repeating)
    varargin
end

if showQC()   % Settings > Misc "Open QC figures"
    visible = 'on';
else
    visible = 'off';
end
fig = figure(varargin{:}, 'Visible', visible);
if isBatchRun() && showQC() && isempty(fig.Tag)
    fig.Tag = 'bipateKeep';   % shown during a batch: bipate leaves it open after the job
end
end
