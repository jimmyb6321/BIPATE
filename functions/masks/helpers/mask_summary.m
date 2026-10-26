function EEG = mask_summary(EEG, cfg_full)

% Author: James Barlow
% Created: 08/04/2026
% Last updated: 10/22/2026

% Writes a QC text summary of what the masks currently exclude (% samples, % channels, kept segment lengths)

% IN:   EEG = EEGLAB struct
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = unchanged EEG struct (masks initialised if missing)
%       file: QC\<sessionID>_maskRemovalSummary.txt

arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

EEG = mask_init(EEG);
qcSave = fullfile(cfg_full.paths.data_out, 'QC');
if ~isfolder(qcSave), mkdir(qcSave); end

% keep vector on the ORIGINAL timeline: after mask_applyCuts the masks are empty (the stretches are
% gone from the data), so the cut ranges it logged in EEG.etc.cutMasks are put back in place
[segs, nTotal] = keptSamples(EEG);
removedRat = sum(~segs) / nTotal * 100;

fid = fopen(fullfile(qcSave, [char(cfg_full.sessionID) '_maskRemovalSummary.txt']), 'w');
fprintf(fid, 'CHANNEL AND SAMPLE REMOVAL SUMMARY\n\n');
fprintf(fid, '%.2f%% of samples removed\n', removedRat);

% kept-segment runs
runner = diff([false segs false]);
runStarts = find(runner == 1);
runEnds = find(runner == -1) - 1;

goodLengths = runEnds-runStarts+1;

longestCont = max(goodLengths)/EEG.srate;


chanRat = sum(~EEG.masks.chan.keepMask) / EEG.nbchan * 100;

fprintf(fid,'%.1f%% of channels removed\n', chanRat);
if isfield(EEG.etc, 'bad_channels') && isfield(EEG.etc.bad_channels, 'final') && any(strcmp(EEG.etc.processing_done, 'interpChans'))
    fprintf(fid, '%d bad channel(s) interpolated (%s)\n', numel(EEG.etc.bad_channels.final), strjoin(EEG.etc.bad_channels.removed_labels, ', '));
end

fprintf(fid, 'Longest continuous EEG segment kept is %.1f seconds long\n', longestCont);

fprintf(fid, '\n EEG kept segment durations (%d total good segments)\n', numel(goodLengths));
for i = 1:numel(goodLengths)
    fprintf(fid, 'Duration\n');
    fprintf(fid, '%.2f seconds\n', goodLengths(i) / EEG.srate);
end


fclose(fid);



end

% keep = logical [1 x nTotal] on the original timeline; nTotal = samples before any cut
function [keep, nTotal] = keptSamples(EEG)
if isfield(EEG.etc, 'cutMasks') && ~isempty(fieldnames(EEG.etc.cutMasks))
    cuts = struct2cell(EEG.etc.cutMasks);
    ranges = zeros(0, 2);
    for c = 1:numel(cuts)
        if isfield(cuts{c}, 'type') && strcmp(cuts{c}.type, 'segment'), ranges = [ranges; cuts{c}.removedRanges]; end %#ok<AGROW>
    end
    nTotal = EEG.pnts + sum(ranges(:, 2) - ranges(:, 1) + 1);
    keep = true(1, nTotal);
    for r = 1:size(ranges, 1), keep(ranges(r, 1):ranges(r, 2)) = false; end
else
    keep = EEG.masks.seg.keepMask;
    nTotal = EEG.pnts;
end
end
