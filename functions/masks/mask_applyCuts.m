function EEG = mask_applyCuts(EEG, cfg)

% Author: Mika Hess, Modified by: James Barlow
% Created: 08/19/2026
% Last updated: 10/25/2026

% The only step that removes data: cuts masked epochs/segments/channels and logs what was removed

% IN:   EEG = EEGLAB struct with EEG.masks set by earlier steps
%       cfg = configuration struct (sessionID, paths.data_out, artifact.minKeptSec = shortest kept piece in s, [] = off)

% OUT:  EEG = cut EEG struct, keep-masks reset to all true at the new size
%           EEG.etc.cutMasks.rejection<n> = what this call removed (epoch indices or [start end] sample ranges)
%           EEG.etc.removal_log = running totals: epochs_removed, segments_removed_samples, channels_removed,
%                                 short_pieces_dropped (kept pieces under artifact.minKeptSec that were cut too)
%           EEG.etc.originalEvent = events before any cut
arguments
    EEG (1,1) struct
    cfg (1,1) struct
end

checkPrerequisites(EEG, 'applyCuts');   % what must run first is listed in jobs.json
isEpoched = EEG.trials > 1;

 if ~isfield(EEG, 'masks')
    error('No masks have been created/saved!');
end
    
if all(EEG.masks.epoch.keepMask) && all(EEG.masks.chan.keepMask) && all(EEG.masks.seg.keepMask)
    error('No channels or segments to cut!');
end

% keep a copy of the original events
if ~isfield(EEG.etc, 'originalEvent')
    EEG.etc.originalEvent = EEG.event;
end

% audit trail: one rejection<n> entry per call
if ~isfield(EEG.etc, 'cutMasks')
    EEG.etc.cutMasks = struct();
end
rejectionNum = numel(fieldnames(EEG.etc.cutMasks)) + 1;
rejectionFieldName = sprintf('rejection%d', rejectionNum);
if isEpoched
    badEpochs = find(~EEG.masks.epoch.keepMask);
    if ~isempty(badEpochs)
        numRemovedEpochs = numel(badEpochs);
        EEG.etc.cutMasks.(rejectionFieldName) = struct('type', 'epoch', 'removedIndices', badEpochs(:));
        EEG = pop_rejepoch(EEG, badEpochs, 0);
        % running total for QC
        if ~isfield(EEG.etc, 'removal_log')
            EEG.etc.removal_log = struct();
        end
        if ~isfield(EEG.etc.removal_log, 'epochs_removed')
            EEG.etc.removal_log.epochs_removed = 0;
        end
        EEG.etc.removal_log.epochs_removed = EEG.etc.removal_log.epochs_removed + numRemovedEpochs;
        EEG.masks.epoch.keepMask = true(1, EEG.trials);   % reset to the new trial count
    end
else

    if any(~EEG.masks.seg.keepMask)
        [EEG, nShort] = dropShortPieces(EEG, cfg);   % optional: kept slivers between cuts are cut too
        EEG = shiftEvents(EEG);   % move events out of cut gaps first

        runner = diff([false ~EEG.masks.seg.keepMask false]);
        rejStart = find(runner == 1);
        rejEnd = find(runner == -1) - 1;
        numRemovedSamples = sum(EEG.masks.seg.keepMask == 0);
        EEG.etc.cutMasks.(rejectionFieldName) = struct('type', 'segment', 'removedRanges', [rejStart(:) rejEnd(:)]);
        EEG = eeg_eegrej(EEG, [rejStart(:) rejEnd(:)]);
        % running total for QC
        if ~isfield(EEG.etc, 'removal_log')
            EEG.etc.removal_log = struct();
        end
        if ~isfield(EEG.etc.removal_log, 'segments_removed_samples')
            EEG.etc.removal_log.segments_removed_samples = 0;
        end
        EEG.etc.removal_log.segments_removed_samples = EEG.etc.removal_log.segments_removed_samples + numRemovedSamples;
        if ~isfield(EEG.etc.removal_log, 'short_pieces_dropped')
            EEG.etc.removal_log.short_pieces_dropped = 0;
        end
        EEG.etc.removal_log.short_pieces_dropped = EEG.etc.removal_log.short_pieces_dropped + nShort;
        EEG.masks.seg.keepMask = true(1, EEG.pnts);        % reset to the new sample count
    end
end
% channels
if isfield(EEG.masks, 'chan') && ~all(EEG.masks.chan.keepMask)
    chanLabs = {EEG.chanlocs(~EEG.masks.chan.keepMask).labels};
    EEG = pop_select(EEG, 'nochannel', find(~EEG.masks.chan.keepMask) );
    EEG.masks.chan.keepMask = true(EEG.nbchan, 1);
    if ~isfield(EEG.etc, 'removal_log')
        EEG.etc.removal_log = struct();
    end
    if ~isfield(EEG.etc.removal_log, 'channels_removed')
        EEG.etc.removal_log.channels_removed = [];
    end
    EEG.etc.removal_log.channels_removed = [EEG.etc.removal_log.channels_removed, chanLabs];
end
EEG = eeg_checkset(EEG, 'eventconsistency');
EEG.etc.processing_log{end+1} = sprintf('Data masks cut %s', string(datetime('now')));
[cutTag, roundSuffix] = stepRound(EEG, 'maskCut');
EEG.etc.processing_done{end+1} = cutTag;
savePath = fullfile(cfg.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
EEG.setname = [char(cfg.sessionID) '_maskCut' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg.sessionID) '_maskCut' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone('Bad channel/segement/epoch masks cut from data!')
end

% IN:  EEG with EEG.masks.seg.keepMask (1 x pnts, true = keep), cfg.artifact.minKeptSec (s; missing/empty/0 = off)
% OUT: EEG with every kept run shorter than minKeptSec set to false in keepMask; nShort = how many runs that was.
%      Cuts are never shortened or merged (short cuts are often spike removal). If every kept run is short, nothing
%      is dropped (a warning says so) rather than cutting the whole recording.
function [EEG, nShort] = dropShortPieces(EEG, cfg)
    nShort = 0;
    if ~isfield(cfg, 'artifact') || ~isfield(cfg.artifact, 'minKeptSec') || isempty(cfg.artifact.minKeptSec) ...
            || ~isfinite(cfg.artifact.minKeptSec) || cfg.artifact.minKeptSec <= 0
        return
    end
    minLen = round(cfg.artifact.minKeptSec * EEG.srate);       % shortest kept run, in samples
    keep = logical(EEG.masks.seg.keepMask(:)');
    edges = diff([false keep false]);                         % +1 = kept run starts, -1 = ends (one past)
    runStart = find(edges == 1);
    runLen = find(edges == -1) - runStart;
    isShort = runLen < minLen;
    if ~any(isShort), return; end
    if all(isShort)
        warning('mask_applyCuts:allShort', 'Every kept piece is shorter than %g s; none were dropped.', cfg.artifact.minKeptSec);
        return
    end
    for r = find(isShort)
        keep(runStart(r):runStart(r) + runLen(r) - 1) = false;
    end
    nShort = sum(isShort);
    EEG.masks.seg.keepMask = keep;
    fprintf('Apply cuts: dropped %d kept piece(s) shorter than %g s (%.1f s of data).\n', nShort, cfg.artifact.minKeptSec, sum(runLen(isShort)) / EEG.srate);
end

% moves events that sit inside a cut to the nearest kept sample (first half of a gap -> before, second half -> after)
function EEG = shiftEvents(EEG)
    if isempty(EEG.event), return; end   % nothing to move (e.g. synthetic data with no events)
    noBound = ~strcmpi({EEG.event.type}, 'boundary');
    eventLat = cell2mat({EEG.event(noBound).latency});
    
    segsMask = EEG.masks.seg.keepMask;

    idx = find(noBound);


    for i = 1:numel(eventLat)
        thisLat = round(eventLat(i));
    
        if thisLat < 1 || thisLat > numel(segsMask), continue; end
        if segsMask(thisLat), continue; end          % already in a kept region
    
        prv = find(segsMask(1:thisLat), 1, 'last');  % last kept sample before
        nxtRel = find(segsMask(thisLat:end), 1);     % first kept sample after
        if isempty(nxtRel), nxt = []; else, nxt = thisLat + nxtRel - 1; end
    
        if isempty(prv) && isempty(nxt)
            continue;                                 % nothing kept anywhere
        elseif isempty(prv)
            EEG.event(idx(i)).latency = nxt;          % cut runs to the start of file
        elseif isempty(nxt)
            EEG.event(idx(i)).latency = prv;          % cut runs to the end of file
        else
            gapStart = prv + 1;
            gapEnd   = nxt - 1;
            if thisLat <= (gapStart + gapEnd) / 2
                EEG.event(idx(i)).latency = prv;
            else
                EEG.event(idx(i)).latency = nxt;
            end
        end
    end
    


end