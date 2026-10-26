function fig = qcSpectopo(EEG, varargin)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% pop_spectopo for a QC plot. pop_spectopo always opens its own figure (so a figure made beforehand stays
% empty), and spectopo switches that figure to visible while plotting. During a bipate batch the figure is
% therefore opened off screen, hidden once drawn, then moved back to the normal place (so the saved .fig
% opens on screen).

% IN:   EEG = EEGLAB struct
%       varargin = pop_spectopo arguments after EEG (dataflag, timerange, process, options...)
% OUT:  fig = handle of the figure pop_spectopo drew

arguments
    EEG (1,1) struct
end
arguments (Repeating)
    varargin
end

if showQC()   % Settings > Misc "Open QC figures"
    pop_spectopo(EEG, varargin{:});
    fig = gcf;
    if isBatchRun(), fig.Tag = 'bipateKeep'; end   % bipate leaves it open after the job
    return
end
normalPos = get(groot, 'DefaultFigurePosition');
restorePos = onCleanup(@() set(groot, 'DefaultFigurePosition', normalPos));
set(groot, 'DefaultFigurePosition', [-5000, -5000, normalPos(3:4)]);
pop_spectopo(EEG, varargin{:});
fig = gcf;
fig.Visible = 'off';
fig.Position = normalPos;
clear restorePos
end
