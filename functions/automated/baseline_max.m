function EEG = baseline_max(EEG, currStep)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/18/2026

% Baseline-corrects epoched (evoked) data. Asks for the window once, then reuses it from EEG.etc.baselineWin

% IN:   EEG = epoched EEGLAB struct (EEG.trials > 1)
%       currStep = name of the step this runs after, used in the processing_done tag

% OUT:  EEG = baselined EEG struct
%           EEG.etc.baselineWin = [start end] baseline window in ms


arguments
    EEG (1,1) struct
    currStep {mustBeTextScalar}
end

if EEG.trials == 1
    warning('Evoked Data baselining cannot be run on continuous data!')
    return;
end

% ask for the window the first time, reuse it after that
if ~isfield(EEG.etc, 'baselineWin')

    basOut = inputdlg({'Baseline Start (ms)', ' Baseline End (ms)'}, 'Please enter window that evoked data will be baselined to', 1, {'-200', '-2'});
    if isempty(basOut)
        warning('No baseline window specified! Returning to main script...');
        return;
    end
    basOut = str2double(string(basOut));
    EEG.etc.baselineWin = basOut;
    basWin = basOut;

else
    basWin = EEG.etc.baselineWin;

end


if any(basWin <= EEG.times(1)) || any(basWin >= EEG.times(end))
    error('Baseline window exceeds epoch bounds! Please enter a range encompassed by the epoch window')
end


EEG = pop_rmbase(EEG, basWin);

EEG.etc.processing_log{end+1}  = sprintf('Evoked data baselined at %s', string(datetime('now')));
EEG.etc.processing_done{end+1} = ['evokedData_post' currStep];


notifyDone('Baseline Done!')
