function EEG = downsample_max(EEG, cfg_full)

% Author: James Barlow
% Created: 05/11/2026
% Last updated: 10/25/2026

% Resamples to the target fs (pop_resample's anti-alias lowpass built in) and keeps the sample map and masks aligned

% IN:   EEG = EEGLAB struct after chanSetup
%       cfg_full = configuration struct (recording.target_fs, sessionID, paths.data_out)

% OUT:  EEG = resampled EEG struct (unchanged if already at or below target)
%           EEG.etc.sample_map_editable = original-sample index per new sample


arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'downsample');   % what must run first is listed in jobs.json

EEG = mask_init(EEG);
% sample_map_editable = original-sample index of every current sample. Nothing before this step makes it,
% so it starts as a copy of sample_map_original (loadData_max) or, without that, 1..pnts.
if ~isfield(EEG.etc, 'sample_map_editable') || numel(EEG.etc.sample_map_editable) ~= EEG.pnts
    if isfield(EEG.etc, 'sample_map_original') && numel(EEG.etc.sample_map_original) == EEG.pnts
        EEG.etc.sample_map_editable = EEG.etc.sample_map_original(:);
    else
        EEG.etc.sample_map_editable = (1:EEG.pnts)';
    end
end
[resTag, roundSuffix] = stepRound(EEG, 'resample');

% confirm or change target fs (asked once per batch when the batch shares this step)
target_fs = batchShared('get');
if isempty(target_fs)
    prompt = {'Please input target sampling frequency:'};
    dlgTitle = 'Downsampling';
    lines = 1;
    default_ans = {num2str(cfg_full.recording.target_fs)};
    if ~isfield(cfg_full.recording, 'askTargetFs') || cfg_full.recording.askTargetFs   % Settings > Downsample
        target_fs = inputdlg(prompt, dlgTitle, lines, default_ans);
    else
        target_fs = default_ans;   % the Settings rate, no dialog
        fprintf('Downsample: using Settings rate %s Hz.\n', default_ans{1});
    end
    if isempty(target_fs)
        error('Downsampling cancelled by user.');
    end
    batchShared('set', target_fs);
end

tfs = str2double(target_fs{1});

if isnan(tfs)
    error('Invalid sampling rate entered.');
end

cfs = EEG.srate;

if tfs == cfs
    warning('Sampling rate already at target frequency, cancelling downsampling...')
    EEG.etc.processing_log{end+1} = sprintf('Resampling skipped: %s', string(datetime('now')));
    EEG.etc.processing_done{end+1} = [resTag ' (skipped)'];
elseif tfs > cfs
    warning('Sampling rate is below target frequency, cancelling downsampling...')
    EEG.etc.processing_log{end+1} = sprintf('Resampling skipped: %s', string(datetime('now')));
    EEG.etc.processing_done{end+1} = [resTag ' (skipped)'];
else

    % resample (anti-alias lowpass built in)
    EEG = pop_resample(EEG, tfs);


    EEG.etc.processing_log{end+1} = sprintf('Resampling done: %s', string(datetime('now')));
    EEG.etc.processing_done{end+1} = resTag;

    % keep sample map pointing at original samples
    downsample_factor = cfs / tfs;
    if mod(downsample_factor, 1) == 0
        EEG.etc.sample_map_editable = EEG.etc.sample_map_editable(1:downsample_factor:end);
    else
        % non-integer ratio (e.g. 750 -> 500)
        new_pnts = numel(EEG.times);  % already updated by pop_resample
        orig_idx = linspace(1, numel(EEG.etc.sample_map_editable), new_pnts);
        EEG.etc.sample_map_editable = round(interp1(1:numel(EEG.etc.sample_map_editable), ...
                                              EEG.etc.sample_map_editable, orig_idx));
    end

    EEG = mask_resample(EEG);
    
    savePath = fullfile(cfg_full.paths.data_out);
    EEG.setname = [char(cfg_full.sessionID) '_resampled' roundSuffix];
    EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_resampled' roundSuffix '.set'], 'filepath', char(savePath), ...
        'savemode', 'onefile', 'version', '7.3');


end


notifyDone('Downsampling');

%DONT WRITE BELOW THIS LINE
end