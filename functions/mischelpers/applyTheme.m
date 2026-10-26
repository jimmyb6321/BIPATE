function applyTheme(fig)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/22/2026

% Gives a BIPATE window the app's colour scheme (the lavender of the main window): window and layout
% backgrounds, panels a shade darker, buttons in the app's button colour, text boxes and lists a very light
% lavender. Call it once a uifigure is built (and again after rebuilding part of it, e.g. segmentEEG's rule
% rows). Only App Designer-style windows (uifigure) can be styled; EEGLAB's own windows (eegplot, the
% component viewers) and MATLAB's dialog boxes (questdlg, inputdlg, listdlg) keep their own look.

% IN:   fig = uifigure (or any container inside one)

% OUT:  none (colours set on fig and everything in it)

arguments
    fig (1,1) {mustBeA(fig, {'matlab.ui.Figure', 'matlab.ui.container.GridLayout', 'matlab.ui.container.Panel', ...
        'matlab.ui.container.Tab'})}
end

bg       = [220 208 255] / 255;          % bipate mainColor
panel    = bg - [20 20 0] / 255;          % bipate strip colour
button   = [0.82 0.79 0.92];             % bipate buttonColor
field    = [0.97 0.96 1.00];             % text boxes, dropdowns, lists

if isa(fig, 'matlab.ui.Figure'), fig.Color = bg; end
set(findall(fig, 'Type', 'uigridlayout'), 'BackgroundColor', bg);
set(findall(fig, 'Type', 'uipanel'), 'BackgroundColor', panel);
set(findall(fig, 'Type', 'uitab'), 'BackgroundColor', bg);
set(findall(fig, 'Type', 'uibutton'), 'BackgroundColor', button);
set(findall(fig, 'Type', 'uistatebutton'), 'BackgroundColor', button);
for kind = {'uieditfield', 'uinumericeditfield', 'uidropdown', 'uitextarea', 'uilistbox'}
    set(findall(fig, 'Type', kind{1}), 'BackgroundColor', field);
end
end
