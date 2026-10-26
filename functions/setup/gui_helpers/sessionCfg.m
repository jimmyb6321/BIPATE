function cfg_full = sessionCfg(cfg, entry, outRoot)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/24/2026

% Builds one set's session configuration for the batch app, the same fields launch_pipeline's New
% Session dialog fills in, but from a validated queue entry instead of a dialog.

% IN:   cfg     = base configuration from cfg_init (bipate's obj.cfg)
%       entry   = one validated queue entry (blankEntry fields; sessionID already built by queueValidate)
%       outRoot = output root folder chosen in the app; the session writes to <outRoot>\<sessionID>

% OUT:  cfg_full = configuration struct for this set:
%           pptID, sessionID, recording.timepoint, recording.cap_type / input_format, ica.method, artifact.mode
%           paths.data_in   = folder holding the recording (parent folder for an .mff bundle)
%           paths.inputFile = the recording itself (loadData_max loads it without a file picker)
%           paths.out_root, paths.data_out = <outRoot>\<sessionID>
%           batchMode = true

arguments
    cfg (1,1) struct
    entry (1,1) struct
    outRoot {mustBeTextScalar}
end

outRoot = char(outRoot);
if any(contains(split(string(outRoot), filesep), '.mff'))
    error('The output folder sits inside a .mff bundle: %s', outRoot);
end
if isempty(strtrim(char(entry.identity.sessionID)))
    error('Set %s has no session ID (run queueValidate first)', entry.identity.fileName);
end

cfg_full = cfg;
cfg_full.pptID = string(entry.identity.pptID);                 % subject ID only, never the descriptor
cfg_full.recording.timepoint = string(entry.identity.timePoint);
cfg_full.sessionID = string(entry.identity.sessionID);          % pptID or pptID_timepoint (queueValidate)

inFile = char(entry.identity.filePath);
cfg_full.paths.inputFile = string(inFile);
cfg_full.paths.data_in = string(fileparts(inFile));            % .mff is a folder: its parent holds it
cfg_full.paths.out_root = string(outRoot);
cfg_full.paths.data_out = string(fullfile(outRoot, char(cfg_full.sessionID)));

cfg_full.recording.cap_type = string(entry.opts.recording.cap_type);
cfg_full.recording.input_format = string(entry.identity.inputFormat);
% ICA method: sets no longer have their own (no ICA column), so the Settings > General choice decides;
% the per-set value is only a fallback for an older cfg without defaults.icaMethod
if isfield(cfg, 'defaults') && isfield(cfg.defaults, 'icaMethod') && strlength(string(cfg.defaults.icaMethod)) > 0
    cfg_full.ica.method = string(cfg.defaults.icaMethod);
else
    cfg_full.ica.method = string(entry.opts.ica.method);
end
cfg_full.artifact.mode = string(entry.opts.artifact.mode);
cfg_full.batchMode = true;
end
