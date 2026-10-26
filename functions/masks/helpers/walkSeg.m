function EEG = walkSeg(EEG, rules, cfg_full)

% Author: James Barlow
% Created: 08/27/2026
% Last updated: 10/25/2026

% Resolves the segmentEEG rules into sample ranges, writes them to the seg mask (source 'segmentation'),
% and optionally splits the recording into one .set per kept segment

% IN:   EEG = continuous EEGLAB struct
%       rules = segmentation rules from segmentEEG
%           .specs = rule array; .mode = 'span' | 'global' | 'periodic', with .start/.end (anchor, offset) or anchor/phase/period/duration
%           .keepOrCut = 'keep' | 'cut'
%           .eventList / .eventLatencies (s) / .eventLibrary = events the anchors were built on (walkSeg re-reads the
%               events from EEG via segEvents and finds anchors by .anchorName / .anchorNth when present)
%       cfg_full = configuration struct (sessionID, paths.data_out)

% OUT:  EEG = EEG struct with EEG.masks.seg updated (full recording, even when split)
%       files: <sessionID>_segmented.set, or <sessionID>_segment###.set per segment

arguments
    EEG (1,1) struct
    rules (1,1) struct
    cfg_full (1,1) struct
end

EEG = mask_init(EEG); 


sr = EEG.srate;
npts = EEG.pnts;
% events of the recording being cut (same naming as segmentEEG, via segEvents), so rules built on another
% copy of the events still land on the right event
[evList, evSecs] = segEvents(EEG);
evLib = unique(evList);

allRanges = zeros(0, 2);   % [start end] in seconds, one row per range
unpaired = 0;             % rules/ranges that couldn't be resolved
problems = strings(0, 1);  % plain-language reasons a rule gave nothing, shown in one box before the mask is written

% resolve every rule into time ranges

for j = 1:numel(rules.specs)
    spec = rules.specs(j);
    % anchors -> indices into THIS recording's events (span/periodic: evList, global: evLib), looked up by
    % event name when the rule has one (segmentEEG >= 18 Oct 2026), else bounds-checked; bad rules are skipped
    [spec, bad] = resolveAnchors(spec, evList, evLib);
    if ~isempty(bad)
        warning('walkSeg:anchor', 'Rule %d skipped: %s', j, bad);
        problems(end+1) = sprintf('Rule %d (%s) skipped: %s.', j, spec.mode, bad); %#ok<AGROW>
        unpaired = unpaired + 1;
        continue;
    end
    startoff = seconds(duration(spec.start.offset));
    endoff = seconds(duration(spec.end.offset));

    switch spec.mode
        case 'span'
            t0 = anchorTime(spec.start.anchor) + seconds(duration(spec.start.offset));
            t1 = anchorTime(spec.end.anchor) + seconds(duration(spec.end.offset));
            allRanges(end+1, :) = [t0 t1];
        case 'global'   % every start-type event paired with the next end-type event
            pairs = [];
            if spec.start.anchor == 0 || spec.end.anchor == 0
                unpaired = unpaired +1;
                continue;
            end
            sType = evLib(spec.start.anchor);
            eType = evLib(spec.end.anchor);
            sIdx = find(ismember(evList, sType));
            if strcmpi(sType, eType)
                pairs = [sIdx sIdx];
            else
                eIdx = find(ismember(evList, eType));
                for k = sIdx'
                    nxt = eIdx(find(eIdx > k, 1));
                    if isempty(nxt)
                        unpaired = unpaired + 1;
                    else
                        pairs(end+1, :) = [k, nxt];
                    end
                end

            end
            for i = 1:height(pairs)
                allRanges(end+1, :) = [evSecs(pairs(i, 1))+startoff, evSecs(pairs(i, 2))+endoff];
            end
        case 'periodic'   % fixed-length windows repeating from an anchor
            t0 = anchorTime(spec.anchor) + seconds(duration(spec.phase));
            per = seconds(duration(spec.period));
            if per <= 0 
                warning('A periodic segment cannot have a negative period!')
                continue;
            end
            dur = seconds(duration(spec.duration));
            if dur >= per
                problems(end+1) = sprintf(['Rule %d (periodic): each window lasts %s but they repeat every %s, so the ' ...
                    'windows touch or overlap and join into one continuous stretch.'], j, ...
                    char(duration(seconds(dur), 'Format', 'hh:mm:ss')), char(duration(seconds(per), 'Format', 'hh:mm:ss'))); %#ok<AGROW>
            end
            grid = t0 : per: (npts-1)/sr;
            if isempty(grid)
                problems(end+1) = sprintf(['Rule %d (periodic): the first window would start at %s, after the end of ' ...
                    'the recording (%s), so it covers nothing. Check "First window starts after".'], j, ...
                    char(duration(seconds(t0), 'Format', 'hh:mm:ss')), char(duration(seconds((npts-1)/sr), 'Format', 'hh:mm:ss'))); %#ok<AGROW>
            end
            allRanges = [allRanges; [grid(:), grid(:) + dur]];
    end
end

% a range that ends where it starts (e.g. the default Recording Start -> Recording Start) covers nothing
emptyRange = allRanges(:, 2) <= allRanges(:, 1);
allRanges(emptyRange, :) = [];
% seconds -> samples, clipped to the recording
s0 = max(1, round(allRanges(:, 1)*sr) + 1);
s1 = min(npts, round(allRanges(:, 2)*sr) + 1);

% build the keep vector (cut: start all-kept and remove ranges; keep: start all-cut and add ranges)
if strcmpi(rules.keepOrCut, 'cut')
    keep = true(1, npts);
    for li = 1:height(allRanges)
        
        this0 = s0(li);
        this1 = s1(li);
        if this0 > this1 
            warning('Segmenation mismatch! Segment starts before it begins!')
            unpaired = unpaired +1;
            continue;

        end
        keep(this0:this1) = false;
    end
elseif isempty(allRanges)
    warning('walkSeg:noKeep', 'Keep mode with no usable rule: nothing is cut.');
    problems(end+1) = "Keep mode, but no rule covered any time, so nothing was cut (the whole recording is kept).";
    keep = true(1, npts);
else
    keep = false(1, npts);
    for li = 1:height(allRanges)
        this0 = s0(li);
        this1 = s1(li);
        if this0 > this1
            warning('Segmenation mismatch! Segment starts before it begins!')
            unpaired = unpaired + 1;
            continue;

        end
        keep(this0:this1) = true;
    end
end

if unpaired > 0
    warning('walkSeg:unpaired', '%d rule(s)/range(s) could not be applied (%d applied).', unpaired, height(allRanges));
end
if ~any(keep)   % nothing left: stop here rather than hand every later job an empty recording
    error(['Segmentation would remove the whole recording, so nothing was saved. Check the rules ' ...
        '(e.g. a periodic window as long as or longer than its repeat). %s'], char(strjoin(problems, ' ')));
end
if ~isempty(problems)   % say so on screen, not only in the command window
    uiwait(warndlg(cellstr(problems), 'Segmentation: some rules did nothing', 'modal'));
end
EEG = mask_addSeg(EEG, find(~keep), 'segmentation');

% only worth asking when the cuts leave more than one kept stretch
runs = diff([false keep false]);
if nnz(runs == 1) > 1
    splitQ = questdlg('Would you like to split segments into multiple files?', 'Split?', 'No', 'Yes', 'No');
else
    splitQ = 'No';
end

% kept-segment runs
runner = diff([false keep false]);
starts = find(runner == 1);
ends = find(runner == -1) - 1;
segSp = numel(starts);

EEG.etc.processing_log{end+1}  = sprintf('Segmentation done at: %s', string(datetime('now')));
[segTag, roundSuffix] = stepRound(EEG, 'Segmentation');
EEG.etc.processing_done{end+1} = segTag;

savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath), mkdir(savePath); end
if strcmpi(splitQ, 'yes')
    for se = 1:segSp

        sEG = pop_select(EEG, 'point', [starts(se) ends(se)]);
        
        % re-base masks and source indices to the segment's own timeline
        segRange = starts(se):ends(se);
        sEG.masks.seg.keepMask = EEG.masks.seg.keepMask(segRange);
        
        if isfield(EEG.masks.seg, 'source')
            srcNames = fieldnames(EEG.masks.seg.source);
            for sn = 1:numel(srcNames)
                idxList = EEG.masks.seg.source.(srcNames{sn});
                idxList = idxList(idxList >= starts(se) & idxList <= ends(se));
                sEG.masks.seg.source.(srcNames{sn}) = idxList(:) - (starts(se) - 1);
            end
        end
        
        sEG.setname = [char(cfg_full.sessionID) sprintf('_segment%03d', se)];
        sEG.etc.metaTime = EEG.etc.metaTime + seconds((starts(se)-1)/sr);   % wall-clock start of this segment
        pop_saveset(sEG, 'filename', [char(cfg_full.sessionID) sprintf('_segment%03d.set', se)], ...
        'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');


    end
else
    EEG.setname = [char(cfg_full.sessionID) '_segmented' roundSuffix];
    EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_segmented' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
end

notifyDone('Segmentation done!');


    % event latency (s) for an anchor index; 0 = recording start
    function t = anchorTime(a)
        if a == 0, t = 0; else, t = evSecs(a); end
    end
end

function [spec, bad] = resolveAnchors(spec, evList, evLib)
% Turns one rule's anchors into valid indices for the recording being cut.
% Named anchors (.anchorName / .anchorNth from segmentEEG's nameAnchors) are looked up by name: the
% anchorNth-th event called anchorName (global rules: that name in the library). Index-only anchors (rules
% saved before names existed) must be a whole number from 0 to the list length. 0 = recording start.
% IN:   spec = one rules.specs element;  evList = [nEv x 1] string event names;  evLib = unique(evList)
% OUT:  spec = same rule with .start.anchor / .end.anchor (span, global) or .anchor (periodic) re-set
%       bad = '' if every anchor resolved, else why the rule cannot be applied
bad = '';
if strcmpi(spec.mode, 'global'), pool = evLib; else, pool = evList; end
if strcmpi(spec.mode, 'periodic'), slots = {''}; else, slots = {'start', 'end'}; end   % only the anchors this mode uses
for s = 1:numel(slots)
    if isempty(slots{s}), a = spec; else, a = spec.(slots{s}); end
    if isfield(a, 'anchorName') && strlength(a.anchorName) == 0
        idx = 0;                                                        % named as recording start
    elseif isfield(a, 'anchorName')
        hits = find(pool == a.anchorName);
        n = max(1, a.anchorNth);
        if numel(hits) < n
            bad = sprintf('event "%s" (occurrence %d) is not in this recording', a.anchorName, n);
            return
        end
        idx = hits(n);
    else
        idx = a.anchor;
        if isempty(idx) || ~isscalar(idx) || idx ~= round(idx) || idx < 0 || idx > numel(pool)
            bad = sprintf('anchor %s is outside 0-%d', mat2str(idx), numel(pool));
            return
        end
    end
    if isempty(slots{s}), spec.anchor = idx; else, spec.(slots{s}).anchor = idx; end
end
end