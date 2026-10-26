function value = appSetting(key, default)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/25/2026

% One setting from the Settings window, for code that has no cfg at hand (notifyDone, qcFigure). Reads the
% override saved in BIPATE_user\userPreferences.mat (prefs.overrides, rows of {key, value}); when
% there is none, returns default.

% IN:   key = dotted cfg field name, e.g. 'misc.sound'
%       default = value to use when the setting was never changed
% OUT:  value

arguments
    key {mustBeTextScalar}
    default = []
end

value = default;
prefsFile = fullfile(bipateUserDir(), 'userPreferences.mat');
if ~isfile(prefsFile)
    return
end
try
    loaded = load(prefsFile, 'prefs');
    if isfield(loaded.prefs, 'overrides') && ~isempty(loaded.prefs.overrides)
        row = find(strcmp(loaded.prefs.overrides(:, 1), key), 1);
        if ~isempty(row)
            value = loaded.prefs.overrides{row, 2};
        end
    end
catch
    % unreadable prefs: keep the default
end
end
