
function notifyDone(stepName, detail, opts)

% Author: James Barlow
% Created: 05/13/2026
% Last updated: 10/24/2026

% End-of-step notification: chime, timestamped console line, and a message box. During a bipate batch run
% (appdata 'bipateBatch' = true) it stays silent; the app calls it once when the whole batch has finished.
% A new box replaces any open 'Done' box, so finished steps never pile up on top of each other.
% Settings > Misc can turn off the chime (misc.sound) and the per-step box (misc.doneBox); the
% end-of-batch summary box (called with detail) always shows.

% IN:   stepName = name of the finished step (char)
%       detail   = (optional) extra line for the console and message box, e.g. the batch summary
%       showBox  = (name-value, default true) false = chime + console line only; bipate shows the batch
%                  summary itself on its own window, where the clean-up cannot cover it

% OUT:  none

    arguments
        stepName {mustBeTextScalar}
        detail {mustBeTextScalar} = ''
        opts.showBox (1,1) logical = true
    end

    if isappdata(0, 'bipateBatch') && getappdata(0, 'bipateBatch')
        return   % inside a batch: one notification at the end instead of one per step
    end
    if appSetting('misc.sound', true)
        Fs = 8000;
        t = 0:1/Fs:1;
        y = (sin(2*pi*261.63*t) + sin(2*pi*293.66*t) + sin(2*pi*349.23*t) + sin(2*pi*392*t)) .* exp(-5*t);   % decaying C-D-F-G chord
        sound(y, Fs);
    end
    fprintf('\n[%s] %s complete.\n', char(datetime('now', 'Format', 'HH:mm:ss')), stepName);
    if nargin < 2 || isempty(detail)
        if appSetting('misc.doneBox', true)
            msgbox([stepName ' done!'], 'Done', 'replace');
        end
    else
        fprintf('    %s\n', detail);
        if opts.showBox
            msgbox({[stepName ' done!'], detail}, 'Done', 'replace');
        end
    end
end
