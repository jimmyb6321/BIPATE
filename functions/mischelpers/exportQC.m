function exportQC(EEG, cfg_full)

% Author: James Barlow
% Created: 06/17/2026
% Last updated: 10/22/2026

% Final QC export: log-log spectra of the cleaned data plus a text summary of what was removed and which steps ran

% IN:   EEG = final cleaned EEGLAB struct
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  none; writes to QC\: <sessionID>_cleanedSpectra.png/.fig, _processingSummary.txt,
%           _removalLog.mat (if removals were logged), and the mask_summary text file
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'exportQC');   % what must run first is listed in jobs.json
qcSave = fullfile(cfg_full.paths.data_out, 'QC');
if ~isfolder(qcSave); mkdir(qcSave); end
ppt = char(cfg_full.sessionID);
% cleaned-data spectra (log-log)
upperF = min(100, floor(EEG.srate/2) - 1);   % just under Nyquist
fS = qcSpectopo(EEG, 1, [0 EEG.times(end)], 'EEG', 'percent', 25, 'freqrange', [1 upperF]);
set(fS.CurrentAxes, 'XScale', 'log');
title(fS.CurrentAxes, 'Cleaned data spectra');
saveQCFigure(fS, fullfile(qcSave, [ppt '_cleanedSpectra']));
% processing summary
fid = fopen(fullfile(qcSave, [ppt '_processingSummary.txt']), 'w');
fprintf(fid, 'Processing summary for %s\n', ppt);
fprintf(fid, 'Generated: %s\n\n', char(datetime('now')));
if isfield(EEG.etc, 'bad_channels') && isfield(EEG.etc.bad_channels, 'final')
    fprintf(fid, 'Bad channels removed : %d\n', numel(EEG.etc.bad_channels.final));
end
if isfield(EEG.etc, 'removed_components')
    fprintf(fid, 'Components removed    : %d\n', sum(cellfun(@numel, EEG.etc.removed_components)));
end
if isfield(EEG, 'masks')
    if isfield(EEG.masks, 'seg') && isfield(EEG.masks.seg, 'keepMask')
        cutSamples = sum(~EEG.masks.seg.keepMask);   % still masked (not cut yet)
        totalSamples = numel(EEG.masks.seg.keepMask);
        if isfield(EEG.etc, 'removal_log') && isfield(EEG.etc.removal_log, 'segments_removed_samples')
            cutSamples = cutSamples + EEG.etc.removal_log.segments_removed_samples;   % already cut by mask_applyCuts
            totalSamples = totalSamples + EEG.etc.removal_log.segments_removed_samples;
        end
        fprintf(fid, 'Samples cut (data)   : %d of %d (%.1f%%)\n', cutSamples, totalSamples, 100 * cutSamples / totalSamples);
    end
end
if isfield(EEG.etc, 'ica_algo')
    algos = fieldnames(EEG.etc.ica_algo);
    fprintf(fid, 'ICA passes:\n');
    for a = 1:numel(algos)
        fprintf(fid, '  %s: %s\n', algos{a}, EEG.etc.ica_algo.(algos{a}));
    end
end
if isfield(EEG.etc, 'removal_log')
    rems = EEG.etc.removal_log;
    fprintf(fid, '\nRemovals actually applied to the data:\n');
    rf = fieldnames(rems);
    if isempty(rf), fprintf(fid, '  (none recorded)\n'); end
    for r = 1:numel(rf)
        v = rems.(rf{r});
        if isnumeric(v) && isscalar(v)
            fprintf(fid, '  %-26s : %d\n', rf{r}, v);
        elseif iscell(v)
            fprintf(fid, '  %-26s : %d (%s)\n', rf{r}, numel(v), strjoin(v, ', '));
        else
            fprintf(fid, '  %-26s : %s\n', rf{r}, mat2str(v));
        end
    end
    save(fullfile(qcSave, [ppt '_removalLog.mat']), 'rems');
end
fprintf(fid, '\nProcessing steps (in order):\n');
for s = 1:numel(EEG.etc.processing_done)
    fprintf(fid, '  %d. %s\n', s, EEG.etc.processing_done{s});
end
fclose(fid);
mask_summary(EEG, cfg_full);
notifyDone('QC export done')
