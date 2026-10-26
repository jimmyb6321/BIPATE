function EEG = saveStep(EEG, varargin)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/25/2026

% Saves a step's output, or only notes where it would go when the batch saves once per set at the end.
% Every step calls this instead of pop_saveset for its main .set (side files such as the split peripheral
% channels or per-segment copies still use pop_saveset directly, and Load data always saves).
% "Once per set, at the end" is the BIPATE main-window option; bipate then writes the set once, under the
% name and folder of the last step that ran (also when the set stops or fails part-way).

% IN:   EEG = EEGLAB struct to save
%       varargin = the same name/value pairs as pop_saveset ('filename', ..., 'filepath', ..., 'savemode', ...)

% OUT:  EEG = saved EEG (EEG.saved = 'yes'), with EEG.etc.bipate_version set, or, when saving is deferred, EEG with filename/filepath set
%           and EEG.saved = 'no' (bipate writes it later)

% version stamp: EEG.etc.bipate_version = the BIPATE version that saved it; a set carried on by a newer
% version gets a log line saying so
v = bipateVersion();
if isfield(EEG.etc, 'bipate_version') && ~strcmp(char(EEG.etc.bipate_version), v)
    EEG.etc.processing_log{end+1} = sprintf('Continued with BIPATE %s (was %s) at %s', v, char(EEG.etc.bipate_version), string(datetime('now')));
end
EEG.etc.bipate_version = v;

if ~(isappdata(0, 'bipateDeferSave') && getappdata(0, 'bipateDeferSave'))
    EEG = pop_saveset(EEG, varargin{:});
    return
end
opts = struct('filename', '', 'filepath', '');
for n = 1:2:numel(varargin) - 1
    key = lower(char(varargin{n}));
    if isfield(opts, key), opts.(key) = char(varargin{n + 1}); end
end
[~, name, ext] = fileparts(opts.filename);
if isempty(ext), ext = '.set'; end
EEG.filename = [name ext];
EEG.filepath = opts.filepath;
EEG.saved = 'no';   % bipate saves it at the end of the set
fprintf('Saving deferred: %s will be written at the end of this set.\n', EEG.filename);
end
