function fig = plotChannelPSD(power, freqs, labels, highlight, titleText)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/18/2026

% One line per channel on a log-frequency axis. Clicking a line shows its channel label, frequency and
% power (data tip). Highlighted channels are drawn in red on top of the others.

% IN:   power = [nFreq x nChan] power (units^2/Hz), e.g. from channelPSD
%       freqs = [nFreq x 1] frequencies (Hz)
%       labels = cell array of channel labels (nChan)
%       highlight = (optional) channel indices to draw in red
%       titleText = (optional) figure title

% OUT:  fig = figure handle

arguments
    power {mustBeNumeric}
    freqs {mustBeNumeric}
    labels {mustBeText}
    highlight {mustBeNumericOrLogical} = []
    titleText {mustBeTextScalar} = 'Channel PSDs'
end

if nargin < 4, highlight = []; end
if nargin < 5, titleText = 'Channel PSDs'; end
labels = cellstr(labels);
powerDB = 10 * log10(power);
keep = freqs > 0;   % log axis: drop 0 Hz
freqs = freqs(keep);
powerDB = powerDB(keep, :);

fig = qcFigure('Name', titleText, 'Color', 'w');   % hidden during a bipate batch
ax = axes(fig);
hold(ax, 'on');
isHighlighted = false(1, size(powerDB, 2));
isHighlighted(highlight) = true;
order = [find(~isHighlighted), find(isHighlighted)];   % red lines last so they sit on top
for ch = order
    if isHighlighted(ch)
        lineColor = [0.85 0 0]; lineWidth = 1.2;
    else
        lineColor = [0.55 0.55 0.75]; lineWidth = 0.5;
    end
    h = plot(ax, freqs, powerDB(:, ch), 'Color', lineColor, 'LineWidth', lineWidth);
    h.DataTipTemplate.DataTipRows(1).Label = 'Hz';
    h.DataTipTemplate.DataTipRows(2).Label = 'dB';
    h.DataTipTemplate.DataTipRows = [dataTipTextRow('Channel', repmat(labels(ch), size(freqs))); ...
        h.DataTipTemplate.DataTipRows(:)];
end
set(ax, 'XScale', 'log', 'XLim', [max(0.5, freqs(1)), freqs(end)]);
xlabel(ax, 'Frequency (Hz)');
ylabel(ax, 'Power (dB)');
grid(ax, 'on');
if ~isempty(highlight)
    titleText = [titleText '  (red = flagged)'];
end
title(ax, [titleText '  -  click a line for its channel'], 'Interpreter', 'none');
drawnow;
end
