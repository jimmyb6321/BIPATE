function EEG = chanReduce(EEG, cfg_full) 

% Author: James Barlow
% Created: 05/07/2026
% Last updated: 10/22/2026

% Optionally reduces a GSN HydroCel-257 recording to the 185 on-scalp channels, keeping the 10-10 descriptions

% IN:   EEG = EEGLAB struct after chanSetup
%       cfg_full = configuration struct (recording.cap_type, paths.chanInfo_185, paths.inside185)

% OUT:  EEG = 185-channel EEG struct (unchanged if not GSN-257 or the user says no)

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

% no prerequisite check: chanSetup calls this before it adds its own done tag

if strcmp(cfg_full.recording.cap_type, 'GSN HydroCel-257') && EEG.nbchan == 257

    yRed = questdlg("Reduce the 257 GSN channels to the 185 on-scalp channels?", "Channel reduction", "Yes", "No", "Yes");
    if strcmpi(yRed, "No")
        return;
    end
    tmp185 = load(cfg_full.paths.chanInfo_185); %185-channel chanlocs
    chanInfo185 = tmp185.chanInfo;
    saveDesc = {EEG.chanlocs.description}; %keep 10-10 labels

    tmp_idx = load(cfg_full.paths.inside185); %indices of the 185 kept channels
    inside185ch = tmp_idx.inside185ch;
    extraidx = setdiff(1:257, inside185ch(:)');
    EEG = pop_select(EEG, 'nochannel', extraidx); %reduce to 185 channels

    EEG.chanlocs = chanInfo185;

    % put the 10-10 labels back on the kept channels
    for i = 1:length(inside185ch)
        EEG.chanlocs(i).description = saveDesc{inside185ch(i)};
    end

    EEG.etc.processing_done{end+1} = 'chanReduce';

    EEG.etc.processing_log{end+1} = sprintf('Channels reduced to 185: %s', string(datetime('now')));
    

end

end