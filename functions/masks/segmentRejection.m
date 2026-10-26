function EEG = segmentRejection(EEG, cfg_full, spaceWork)

% Author: James Barlow
% Created: 06/18/2026
% Last updated: 10/25/2026 (good channels only)

% Manual bad-segment/epoch marking in eegplot (one pass, 60 channels per page), written to the masks; nothing is cut here

% IN:   EEG = EEGLAB struct
%       cfg_full = configuration struct (sessionID, paths.data_out)
%       spaceWork = (optional) 'data' (channel data) or 'icaact' (component activations). Left out, it is
%           'data' before ICA, and once ICA has been run the user is asked which one

% OUT:  EEG = EEG struct with the marked ranges in EEG.masks.seg (continuous) or EEG.masks.epoch (epoched),
%           source = spaceWork. Running it again in the same space edits that space's earlier marks (they
%           open pink and can be removed or changed). Stretches already masked by other steps (segmentation,
%           the other space) are not shown at all -- the window jumps over them at a 'boundary' marker --
%           and stay masked.
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
    spaceWork {mustBeMember(spaceWork, {'', 'data', 'icaact'})} = ''
end

checkPrerequisites(EEG, 'segReject');   % what must run first is listed in jobs.json
EEG = mask_init(EEG);
isEpoched = EEG.trials > 1;

% channel data or component activations (asked only once ICA weights exist)
if nargin < 3 || isempty(spaceWork)
    spaceWork = 'data';
    if ~isempty(EEG.icaweights)
        spaceAns = batchShared('get');
        if isempty(spaceAns)
            spaceAns = questdlg('ICA has been run on this set. Mark bad segments on:', 'Segment rejection', ...
                'Channel data', 'ICA components', 'ICA components');
            if isempty(spaceAns)
                error('Segment rejection cancelled.');
            end
            batchShared('set', spaceAns);
        end
        if strcmp(spaceAns, 'ICA components')
            spaceWork = 'icaact';
        end
    end
end
global rejInfo;   % eegplot's REJECT button writes its marks here

% existing marks, split into this space's own (editable, pink) and everyone else's (kept, grey).
% maskKind = which mask the marks live in; nUnits = samples (continuous) or epochs (epoched)
if isEpoched
    pickWin = 5;
    maskKind = 'epoch';
    nUnits = EEG.trials;
else
    pickWin = 30;
    maskKind = 'seg';
    nUnits = EEG.pnts;
end
ownBad = false(1, nUnits);
if isfield(EEG.masks.(maskKind), 'source') && isfield(EEG.masks.(maskKind).source, spaceWork)
    ownBad(EEG.masks.(maskKind).source.(spaceWork)) = true;
end
withoutOwn = mask_clearSource(EEG, maskKind, spaceWork);
otherBad = ~withoutOwn.masks.(maskKind).keepMask;   % bad from other sources
clear withoutOwn
% what is scrolled through: only the samples (or epochs) no other step has masked, joined end to end
% with a 'boundary' marker at each join. This space's own earlier marks stay visible (pink) so they can
% be edited. shown = indices into the full recording, in order; nShown = how many.
shown = find(~otherBad);
nShown = numel(shown);
allRej = unitsToMarks(ownBad(shown), isEpoched, EEG.pnts, [1 0.5 0.5]);
% what to scroll through
switch spaceWork
    case 'data'
        % channels already marked bad (EEG.masks.chan) are left out of the window: they are going anyway
        goodChan = find(mask_good(EEG));
        plotDat = EEG.data(goodChan, :, :);
        plotLocs = EEG.chanlocs(goodChan);
        outFolder = '';   tag = 'segmentRejection_raw';
    case 'icaact'
        if isempty(EEG.icaact)
            if isEpoched
                d = EEG.data(EEG.icachansind, :, :);
                d2 = reshape(d, size(d, 1), []);
                act = (EEG.icaweights*EEG.icasphere) * d2;
                plotDat = reshape(act, size(act, 1), EEG.pnts, EEG.trials);
            else
                plotDat = (EEG.icaweights*EEG.icasphere)*EEG.data(EEG.icachansind,:);  
            end
        else
            plotDat = EEG.icaact;
        end  
        plotLocs = [];   % components have no channel labels
        
        outFolder = '';   tag = 'segmentRejection_component';
end
    
if isEpoched
    pnts0 = EEG.trials;
    plotDat = plotDat(:, :, shown);   % masked epochs left out
else
    pnts0 = EEG.pnts;
    plotDat = plotDat(:, shown);      % masked stretches left out
end
plotEvents = shownEvents(EEG, shown, isEpoched);   % event times moved onto the shortened timeline
% eegplot's marks are [start end r g b] followed by one 0/1 column per plotted channel; marks built here
% have no channel columns, and eegplot fails on them ("Index ... must not exceed 5")
allRej = [allRej, zeros(size(allRej, 1), size(plotDat, 1))];
% one pass (22 Oct 2026; was 90 then 30 channels per page): 60 channels per page, scroll for the rest
viewSteps = 60;
viewSteps = min(viewSteps, size(plotDat,1));
for vs = viewSteps
    rejInfo = [];
    labelArgs = {};
    if ~isempty(plotLocs), labelArgs = {'eloc_file', plotLocs}; end   % channel names down the side
    eegplot(plotDat, 'srate', EEG.srate, 'winlength', pickWin, 'dispchans', vs, 'events', plotEvents, labelArgs{:}, ...
        'command', 'global rejInfo; rejInfo = TMPREJ;', 'butlabel', 'REJECT', 'winrej', allRej);
    uiwait(gcf);
    if ~isempty(rejInfo); allRej = rejInfo; end
end
% final marks -> samples (or epochs) marked bad. This space's mask is replaced by them, minus what other
% sources already hold (those stay theirs, and stay bad, even if their grey mark was removed in the window)
markedShown = false(1, nShown);   % in the shortened timeline
if ~isempty(allRej)
    % columns 1-2 of eegplot's marks are start/end sample (continuous numbering, epochs end to end).
    % Read them directly: marks that came back untouched have no channel columns, which
    % eegplot2event needs, so it failed with "Index ... must not exceed 5".
    rejArray = allRej(:, 1:2);
    if isEpoched
        rejArray = ceil(rejArray / EEG.pnts);   % sample -> epoch number
    end
    for r = 1:size(rejArray, 1)
        a = max(1, round(rejArray(r, 1)));
        b = min(nShown, round(rejArray(r, 2)));
        markedShown(a:b) = true;
    end
end
marked = false(1, pnts0);           % back onto the full recording
marked(shown(markedShown)) = true;
newOwn = marked & ~otherBad;
EEG = mask_clearSource(EEG, maskKind, spaceWork);
if any(newOwn)
    if isEpoched
        EEG = mask_addEpoch(EEG, newOwn, spaceWork);
    else
        EEG = mask_addSeg(EEG, newOwn, spaceWork);
    end
end
fprintf('Segment rejection (%s): %d marked before, %d now.\n', spaceWork, nnz(ownBad), nnz(newOwn));



tag = stepRound(EEG, tag);
EEG.etc.processing_log{end+1} = sprintf(['Bad segments marked in ' spaceWork ' at %s'], string(datetime('now')));
EEG.etc.processing_done{end+1} = tag;

if isEpoched
    EEG = baseline_max(EEG, spaceWork);
end

savePath = fullfile(cfg_full.paths.data_out, outFolder);
EEG.setname = [char(cfg_full.sessionID) '_' tag];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_' tag '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone('Segment Rejection')
end

% EEG.event moved onto the shortened timeline the window shows (only the shown samples/epochs, end to end)
% IN:  EEG; shown = kept sample (continuous) or epoch (epoched) indices, in order; isEpoched
% OUT: ev = events on shown data with latencies renumbered, plus a 'boundary' event at every join
function ev = shownEvents(EEG, shown, isEpoched)
ev = EEG.event;
if isempty(ev), ev = struct('type', {}, 'latency', {}); end
if isEpoched
    newEp = zeros(1, EEG.trials);  newEp(shown) = 1:numel(shown);
    lat = [ev.latency];
    ep = ceil(lat / EEG.pnts);
    keep = ep >= 1 & ep <= EEG.trials;
    keep(keep) = newEp(ep(keep)) > 0;
    ev = ev(keep);  ep = ep(keep);  lat = lat(keep);
    for k = 1:numel(ev)
        ev(k).latency = (newEp(ep(k)) - 1) * EEG.pnts + (lat(k) - (ep(k) - 1) * EEG.pnts);
        if isfield(ev, 'epoch'), ev(k).epoch = newEp(ep(k)); end
    end
    return
end
newPos = zeros(1, EEG.pnts);  newPos(shown) = 1:numel(shown);   % full sample -> shown sample (0 = hidden)
lat = round([ev.latency]);
keep = lat >= 1 & lat <= EEG.pnts;
keep(keep) = newPos(lat(keep)) > 0;
ev = ev(keep);  lat = lat(keep);
for k = 1:numel(ev)
    ev(k).latency = newPos(lat(k));
end
joins = find(diff(shown) > 1);   % a hidden stretch sits after shown sample joins(j)
for j = 1:numel(joins)
    ev(end+1).type = 'boundary';  %#ok<AGROW>
    ev(end).latency = joins(j) + 0.5;
end
if ~isempty(ev)
    [~, order] = sort([ev.latency]);
    ev = ev(order);
end
end

% runs of bad samples (or bad epochs) -> eegplot marks [start end r g b], in eegplot's sample numbering
function marks = unitsToMarks(bad, isEpoched, pnts, color)
if isEpoched
    ep = find(bad);
    starts = (ep(:) - 1) * pnts + 1;
    ends = ep(:) * pnts;
else
    edges = diff([false, bad(:)', false]);
    starts = find(edges == 1)';
    ends = (find(edges == -1) - 1)';
end
marks = [starts, ends, repmat(color, numel(starts), 1)];
end
