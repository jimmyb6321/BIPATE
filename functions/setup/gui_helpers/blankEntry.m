function queueEntry = blankEntry(cfg, emp)

% Author: James Barlow
% Created: 10/15/2026
% Last updated: 10/18/2026

% Creates template for queue entries to fill in--always has the same fields

% IN:   cfg = configuration struct
%       emp = true returns a 1 x 0 struct with these fields (empty queue); default false

% OUT:  queueEntry = row struct containing empty/default fields for every field
%           Fields:
%               identity 
%                   pptID = study ID for participant (i.e. R024)
%                   filePath = FULL path for recording file
%                   fileName = JUST the name of the recording file with no
%                       directories
%                   inputFormat = the extension/what kind of EEG recording the file is
%                   sessionID = which recording it is for the participant
%                   timePoint = visit/session descriptor (text, e.g. baseline)
%               opts
%                   recording
%                       cap_type = what kind of montage/cap your recording is
%                   artifact
%                       mode = whether automated, semi-automated or manual artifact rejection is used
%                   ica
%                       method = kind of ICA being ran
%               state
%                   status = queued, running, done, skipped or failed
%                   message = error message if run crashes
%                   outDir = where processed file lands
%                   doneJobs = which prepro processes have been ran on this file.

arguments
    cfg (1,1) struct
    emp (1,1) logical = false
end

if nargin < 2
    emp = false;
end

queueEntry.identity.pptID = '';
queueEntry.identity.filePath = '';
queueEntry.identity.fileName = '';
queueEntry.identity.inputFormat = '';
queueEntry.identity.sessionID = '';
queueEntry.identity.timePoint = '';
queueEntry.opts.recording.cap_type = cfg.defaults.cap_type;
queueEntry.opts.artifact.mode = cfg.defaults.mode_default;
queueEntry.opts.ica.method = cfg.defaults.icaMethod;
queueEntry.state.status = 'queued'; 


queueEntry.state.message = '';
queueEntry.state.outDir = '';
queueEntry.state.doneJobs = {};

if emp
    queueEntry(1) = [];
end
