function EEG = badChanDetect(EEG, cfg_full)

% Author: James Barlow
% Created: 05/13/2026
% Last updated: 10/25/2026

% Semi-automated bad-channel detection: chosen features are computed on median-referenced data, robust (MAD)
% outliers are auto-flagged, then the user reviews/edits the list; final picks go to the channel mask

% IN:   EEG = EEGLAB struct after chanSetup (chanlocs needed for mhc and the topoplot)
%       cfg_full = configuration struct (artifact.badChanMethodAll/Def, sessionID, paths.data_out)

% OUT:  EEG = EEG struct with final bad channels in EEG.masks.chan (source 'badChanDetect')
%           EEG.etc.bad_channels
%               auto / auto_labels = auto-flagged indices / labels
%               reasons = cell [nbchan x 1] of the features that flagged each channel
%               thresholds = per-feature high/low cutoffs
%               manual_added / manual_removed / final / removed_labels = review outcome

% TODO: custom thresholding

% --- Bad-channel detection methods ---------------------------------------
% variance      : log10 signal variance per channel. Outliers = very low
%                 (dead/flatlined) or very high (railed/saturated or
%                 line-noise-dominated).
% kurtosis      : log10 kurtosis per channel. High = spiky non-Gaussian
%                 transients (pops, movement); low = abnormally flat
%                 amplitude distribution (clipping).
% mhc           : weighted mean correlation with the 10 nearest spatial
%                 neighbors. Flags abnormally LOW values -- disconnected/
%                 floating/noisy channels not tracking the volume-conducted
%                 signal their neighbors share.
% bridge        : count of channels correlated >= 0.999. Flags electrically
%                 bridged electrodes (gel/saline shorts) duplicating a signal.
% psd           : band-power deviance (from ecog-analysis powerDeviantRejection):
%                 mean power in alpha/beta/gamma/highGamma (delta/theta dropped: eyes) and
%                 in total, z-scored across channels per segment, averaged
%                 over segments; |z| > 3.5 in any band flags the channel.
% Every feature except clean_rawdata is computed per segment (15 s clean
% windows, or good epochs) and then combined, not over the whole recording.
% clean_rawdata : EEGLAB clean_rawdata channel criterion, for cross-check.
% lineNoise     : log10 ratio of power at the line frequency to the bands beside it, measured by
%                 filter_max BEFORE filtering (EEG.etc.lineNoise). Flags high outliers (4 x MAD).
% kurtosis is flagged on the high side only, at 5 x MAD; kurtosisBurst also flags a channel whose kurtosis,
%                 relative to its 10 nearest neighbours, is above that in at least 10% of segments.
% -------------------------------------------------------------------------

% already has ICA: only continue (and wipe the ICA) after two confirmations
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

if ~isempty(EEG.icaweights)
    warningMsg = sprintf(['It appears ICA has already been ran on this data set! ...\n' ...
        'By removing additional channels, it may cause unintented effects \n' ...
        'As a safe guard, rerunning channel removal will delete your previous ICA variables\n' ...
        'Only select yes if you are ok with this (cancel if not) \n' ...
        '(PLEASE NOTE: Unintended data errors could still occur. It is recommended to use a pre-ICA file \n' ...
        'to remove more channels)']);
    getWarned  = questdlg(warningMsg, 'WARNING', 'Yes', 'Cancel', 'Cancel');
    if strcmpi(getWarned, 'Yes')
        onceMore = questdlg('Are you SURE?!?!?', 'WARNING', 'Yes', 'Cancel', 'Cancel');
        if strcmpi(onceMore, 'Yes')
            EEG.icaact = [];
            EEG.icawinv = [];
            EEG.icasphere  = [];
            EEG.icaweights = [];
            EEG.icachansind = [];
            EEG.reject.gcompreject = [];
            EEG.etc.processing_log{end+1} = sprintf('Current ICA deleted at %s', string(datetime('now')));
            EEG.etc.processing_done{end+1} = 'ICAreset';
        else
            warning('Canceling...')
            return;
        end
    else
        warning('Canceling...')
        return;
    end

end

EEG = mask_init(EEG);

EEGref = EEG;   % median-referenced copy used for every feature
EEGref.data = EEG.data - median(EEG.data, 1);

checkPrerequisites(EEG, 'badChan');   % what must run first is listed in jobs.json

perfCorr = zeros(EEG.nbchan, 1);
bridges = cell(EEG.nbchan, 1);
crd_removed = [];
flatchan = [];

threshVar = 5;   % fallback MAD multiplier

% channels marked bad on an earlier run start checked in the review table
priorBad = [];
if isfield(EEG.etc, 'bad_channels') && isfield(EEG.etc.bad_channels, 'final')
    priorBad = EEG.etc.bad_channels.final;
end

% which features to compute
featureChoices = cfg_full.artifact.badChanMethodAll;
% asked once per batch when the batch shares this step
shared = batchShared('get');
% artifact mode (set's Artifact column / Settings > General): Manual = no automatic flags, review only;
% Semi-automatic = the picked methods run, then the review to edit their flags
manualMode = isfield(cfg_full, 'artifact') && isfield(cfg_full.artifact, 'mode') && strcmpi(string(cfg_full.artifact.mode), 'Manual');
if manualMode
    sel = [];
elseif isfield(shared, 'methods')
    sel = find(ismember(featureChoices, shared.methods));
else
    sel = pickFeatures(featureChoices, cfg_full);
    if ~isempty(sel)
        shared.methods = featureChoices(sel);
        batchShared('set', shared);
    end
end
if isempty(sel)   % allowed: no automatic flags, straight to the review where channels are picked by hand
    if manualMode
        fprintf('Bad channel detection: Manual mode, review only (Semi-automatic runs the detectors).\n');
    else
        fprintf('Bad channel detection: no automatic methods picked, manual review only.\n');
    end
end

% every feature is computed inside segments, not over the whole recording: 15 s windows of continuous data
% that don't touch a bad stretch (EEG.masks.seg), or each good epoch of epoched data (EEG.masks.epoch).
% Per-segment values are then combined per channel (median across segments, mean for the band z-scores).
segments = detectionSegments(EEG, 15);
nSeg = numel(segments);
if nSeg == 0 && ~isempty(sel)   % manual-only review does not need scored segments
    error(['Bad channel detection: no kept data to score (every sample or epoch is masked). Check the ' ...
        'segmentation rules: they may have cut the whole recording.']);
end
dataAll = EEGref.data(:, :);   % [nbchan x pnts*trials]; epochs side by side
[goodChanNow, ~] = mask_good(EEG);

% feat.<name> = [nbchan x 1] value per channel
featureMap = {'variance', 'kurtosis', 'mhc', 'psd', 'clean_rawdata', 'lineNoise'};   % same order as cfg.artifact.badChanMethodAll
% ecog-analysis bands without delta and theta: eye movements put most of their power there, so they
% flagged eye channels; large slow swings are caught by variance and by ICA instead (22 Oct 2026)
bandNames = {'alpha', 'beta', 'gamma', 'highGamma'};
bandLimits = [9 13; 16 28; 35 45; 80 100];   % Hz (ecogutils.FreqBands)
totalLimits = [1.5 100];                      % "total" band, upper edge capped at Nyquist
bandZCrit = 3.5;                                                           % |mean z| above this = deviant
kurtBurstShare = 0.10;   % kurtosis bursts: flagged when an outlier in at least this share of segments

feat = struct();
for i = sel(:)'
    fname = featureMap{i};
    switch fname
        case 'variance'   % median of per-segment variances; channels flat in >10% of segments also flagged
            segVar = zeros(EEG.nbchan, nSeg);
            for s = 1:nSeg
                segVar(:, s) = var(dataAll(:, segments{s}), [], 2);
            end
            segVar(segVar == 0) = eps;
            flatfloor = 0.01 * median(segVar(:));
            flatchan = find(mean(segVar < flatfloor, 2) > 0.1);
            feat.variance = log10(median(segVar, 2));

        case 'kurtosis'   % median of per-segment kurtosis
            segKurt = zeros(EEG.nbchan, nSeg);
            for s = 1:nSeg
                segKurt(:, s) = kurtosis(dataAll(:, segments{s}), 0, 2);
            end
            segKurt(~isfinite(segKurt)) = 1;   % inf -> 1
            feat.kurtosis = log10(median(segKurt, 2));
            % bursts: the median hides a channel that is only spiky now and then (E204, 22 Oct 2026).
            % Per segment, each channel's log10 kurtosis minus the median of its 10 nearest neighbours',
            % robust-z'd across channels; kurtosisBurst = share of segments where that is above the kurtosis
            % multiplier (5). Relative to neighbours, so a blink (spiky on all frontal channels together) is
            % not a burst -- compared with all channels it flagged ~24 frontal channels. Needs chanlocs.
            % Flagged at >= kurtBurstShare of segments.
            feat.kurtosisBurst = NaN(EEG.nbchan, 1);
            if isfield(EEG.chanlocs, 'X') && all(~cellfun(@isempty, {EEG.chanlocs.X}))
                xyz = [[EEG.chanlocs.X]', [EEG.chanlocs.Y]', [EEG.chanlocs.Z]'];
                [~, nearOrder] = sort(squareform(pdist(xyz)), 2);
                nearest = nearOrder(:, 2:min(11, EEG.nbchan));   % [nbchan x 10], column 1 is the channel itself
                logSegK = log10(max(segKurt, eps));             % [nbchan x nSeg]
                relK = zeros(size(logSegK));
                for c = 1:EEG.nbchan
                    relK(c, :) = logSegK(c, :) - median(logSegK(nearest(c, :), :), 1);
                end
                segMed = median(relK, 1);
                segMad = 1.4826 * median(abs(relK - segMed), 1);
                segZ = (relK - segMed) ./ max(segMad, eps);
                feat.kurtosisBurst = mean(segZ > 5, 2);
            end

        case 'mhc'   % distance-weighted mean correlation with the 10 nearest neighbours, median over segments;
                     % bridges from the median neighbour correlation
            feat.mhc = nan(EEG.nbchan, 1); 
            if ~isfield(EEG.chanlocs, "X") || isempty([EEG.chanlocs.X]) || isempty([EEG.chanlocs.Y]) || isempty([EEG.chanlocs.Z])
                warning('MHC is unable to be compute! Please add channel locations before running!')
            else
                cordNates = [[EEG.chanlocs.X]', [EEG.chanlocs.Y]', [EEG.chanlocs.Z]'];
                neighDist2 = squareform(pdist(cordNates));
                % neighbours and their weights (closer neighbours weigh more: inverse-sqrt distance through erf)
                neighChans = zeros(10, EEG.nbchan);
                weights = zeros(10, EEG.nbchan);
                for ik = 1:EEG.nbchan
                    [getClose, closeIdx] = sort(neighDist2(:, ik));
                    neighChans(:, ik) = closeIdx(2:11);
                    newY = getClose(2:11).^(-1/2);
                    weighter = (newY - mean(newY)) / std(newY) / sqrt(1/pi);
                    weights(:, ik) = (erf(weighter) + 1) / 2;
                end
                segMhc = zeros(EEG.nbchan, nSeg);
                segNear = zeros(10, EEG.nbchan, nSeg);   % each channel's correlation with its 10 neighbours
                for s = 1:nSeg
                    chanCorrelate = corr(dataAll(:, segments{s})');
                    for ik = 1:EEG.nbchan
                        getCorr = chanCorrelate(neighChans(:, ik), ik);
                        segNear(:, ik, s) = getCorr;
                        segMhc(ik, s) = sum(getCorr .* weights(:, ik)) / sum(weights(:, ik));
                    end
                end
                feat.mhc = median(segMhc, 2);

                % bridged: neighbour correlation >= 0.999 (median over segments)
                medNear = median(segNear, 3);
                for ik = 1:EEG.nbchan
                    nearCorr = medNear(:, ik);
                    bridged = neighChans(nearCorr >= 0.999, ik);
                    perfCorr(ik) = numel(bridged);
                    for ci = 1:numel(bridged)
                        bridges(ik, ci) = {EEG.chanlocs(bridged(ci)).labels};
                    end
                end
            end

        case 'psd'   % band-power deviance (ecog-analysis powerDeviantRejection): per segment, mean power in
                     % each band and in total, z-scored across channels; z averaged over segments
            nyq = EEG.srate / 2;
            useBands = find(bandLimits(:, 2) < nyq);
            nfft = 2^nextpow2(2 * EEG.srate);   % ~0.5 Hz bins
            segPow = zeros(EEG.nbchan, 1 + numel(useBands), nSeg);
            for s = 1:nSeg
                segData = dataAll(:, segments{s})';
                winLen = min(2 * EEG.srate, size(segData, 1));
                [pxx, fx] = pwelch(segData, hann(winLen), floor(winLen / 2), nfft, EEG.srate);
                segPow(:, 1, s) = mean(pxx(fx >= totalLimits(1) & fx <= min(totalLimits(2), nyq), :), 1)';   % total
                for b = 1:numel(useBands)
                    inBand = fx >= bandLimits(useBands(b), 1) & fx < bandLimits(useBands(b), 2);
                    segPow(:, 1 + b, s) = mean(pxx(inBand, :), 1)';
                end
            end
            % z across channels, using only channels not already marked bad for the mean and spread
            ref = segPow(goodChanNow, :, :);
            zPow = (segPow - mean(ref, 1)) ./ std(ref, 0, 1);
            zPow = mean(zPow, 3);
            feat.bandPow_total = zPow(:, 1);
            for b = 1:numel(useBands)
                feat.(['bandPow_' bandNames{useBands(b)}]) = zPow(:, 1 + b);
            end

        case 'clean_rawdata'   % channels clean_rawdata would drop (it windows the data itself)
            tmp = clean_rawdata(EEGref, 5, 'off', 0.8, 4, 'off', 'off');
            catchidx = ~ismember({EEG.chanlocs.labels}, {tmp.chanlocs.labels});
            crd_removed = find(catchidx);

        case 'lineNoise'   % log10 line-noise ratio measured by filter_max before it filtered (matched by label)
            feat.lineNoise = NaN(EEG.nbchan, 1);
            if isfield(EEG.etc, 'lineNoise')
                [found, where] = ismember({EEG.chanlocs.labels}, EEG.etc.lineNoise.labels);
                feat.lineNoise(found) = log10(EEG.etc.lineNoise.ratio(where(found)));
            else
                warning('No line-noise measurement on this set (it comes from the Filter step); line-noise check skipped.');
            end

    end
end


% robust outliers per feature: median +/- tv * 1.4826 * MAD, in that feature's direction
bad = [];
reasons = cell(EEG.nbchan, 1);
EEG.etc.bad_channels.thresholds = struct('multiplier', threshVar);
featDir = struct('variance','both','kurtosis','high','mhc','low','lineNoise','high');   % low kurtosis is not a bad sign here
featThresh = struct('variance',4, 'kurtosis',5, 'mhc',4, 'lineNoise',4);   % kurtosis 3.5 -> 5 (22 Oct 2026): blinks were flagging frontal channels
for i = 1:numel(fieldnames(feat))
    featNames = fieldnames(feat);
    d = 'both';

    if isfield(featDir, featNames{i}); d = featDir.(featNames{i}); end

    featVar = feat.(featNames{i});
    featMed = median(featVar, 'omitnan');   % NaN = not measured for that channel
    madVal = median(abs(featVar - featMed), 'omitnan');

    tv = threshVar;                              % fallback multiplier
    if isfield(featThresh, featNames{i}); tv = featThresh.(featNames{i}); end
    if strcmp(featNames{i}, 'kurtosisBurst')      % share of segments, fixed criterion, high side only
        threshold_high = kurtBurstShare;
        threshold_low = -Inf;
    elseif startsWith(featNames{i}, 'bandPow_')     % band z-scores: fixed |z| criterion, as in ecog-analysis
        threshold_high = bandZCrit;
        threshold_low = -bandZCrit;
    else
        threshold_high = featMed + tv * 1.4826 * madVal;
        threshold_low  = featMed - tv * 1.4826 * madVal;
    end

    % save thresholds
    thresh_hivar = [featNames{i} '_high'];
    thresh_lovar = [featNames{i} '_low'];
    EEG.etc.bad_channels.thresholds.(thresh_hivar) = threshold_high;
    EEG.etc.bad_channels.thresholds.(thresh_lovar) = threshold_low;

    switch d
        case 'both'; bad_i = find(featVar > threshold_high | featVar < threshold_low);
        case 'high'; bad_i = find(featVar > threshold_high);
        case 'low';  bad_i = find(featVar < threshold_low);
    end
    
    bad = union(bad, bad_i);

    fN = featNames{i};
    % log reasons
    for c = bad_i(:)'
        reasons{c} = [reasons{c}, {fN}];
    end


    
end

% add bridged, flat and clean_rawdata channels
perfBad = find(perfCorr >= 1);
bad = union(bad, perfBad);
if sum(perfBad) ~= 0
    for cc = perfBad(:)'
        bridgeChans = bridges(cc, :);
        bridgeChans = bridgeChans(~cellfun('isempty', bridgeChans));

        channelbridge = strjoin(bridgeChans, '-');
        reasons{cc} = [reasons{cc}, {['bridged, ' channelbridge]}];
        
    end
end

bad = union(bad, flatchan);
for c4 = flatchan(:)'
    reasons{c4} = [reasons{c4}, {'low variance'}];
end

bad = union(bad, crd_removed);
for ccc = crd_removed(:)'
    reasons{ccc} = [reasons{ccc}, {'clean_rawdata detected'}];
end



shared = batchShared('get');
if isempty(fieldnames(feat))   % manual review only: no features, nothing to plot or ask about
    answer = 'No';
elseif isfield(shared, 'histograms')
    answer = shared.histograms;
else
    answer = questdlg('View histograms?', 'Channel Preview', 'Yes', 'No', 'Yes');
    shared.histograms = answer;
    batchShared('set', shared);
end
if strcmpi(answer, 'Yes')
    fn = fieldnames(feat);
    for jk = 1:numel(fn)
        fv = feat.(fn{jk});
        if all(isnan(fv)), warning('Method (%s) not computed; skipped histogram', fn{jk});continue; end

        figure; histogram(fv); title(fn{jk}, 'Interpreter', 'none')
    end
    
end




EEG.etc.bad_channels.auto = bad;
EEG.etc.bad_channels.auto_labels = {EEG.chanlocs(bad).labels};
EEG.etc.bad_channels.reasons = reasons;             % per channel, which checks flagged it
EEG.etc.bad_channels.features = feat;               % each feature's value per channel, for tuning thresholds

badChans = EEG.etc.bad_channels.auto;

% QC: all PSDs, flagged in red, click a line for its channel (computed here if the psd check was off)
if ~exist('px', 'var')
    [px, f] = channelPSD(EEGref.data, EEG.srate);   % the median-referenced data the features were computed on
end
fPSD = plotChannelPSD(px, f, {EEG.chanlocs.labels}, badChans, 'Channel PSDs (median reference, as the detectors see them)');

qcSave = fullfile(cfg_full.paths.data_out, 'QC');
if ~exist(qcSave,'dir'); mkdir(qcSave); end
saveQCFigure(fPSD, fullfile(qcSave, [char(cfg_full.sessionID) '_badChanPSD']), true);   % open for the review, closed after it


% eegplot for the user's review
% reject = 0: view only, so eegplot shows no "mark stretches ... press REJECT" box and no REJECT button
if ~isempty(badChans)
    pop_eegplot(EEG, 1, 1, 0, [], 'spacing', 50, 'winlength', 30, 'dispchans', 50);
else
    pop_eegplot(EEG, 1, 1, 0);
    fprintf('No channels auto-flagged.\n');
end
% no rejecting at this stage (segments are rejected in segmentRejection): remove eegplot's REJECT button,
% which would cut the data here
rvFig = [findall(0, 'Type', 'figure', 'Tag', 'EEGPLOT'); findall(0, 'Type', 'figure', '-regexp', 'Name', 'eegplot')];
rvBut = findall(rvFig, 'Style', 'pushbutton');   % findall cannot regexp on String, so compare the labels here
delete(rvBut(strcmpi(strtrim(string(get(rvBut, 'String'))), 'REJECT')));

disp('Auto-flagged bad channels:');
disp({EEG.chanlocs(EEG.etc.bad_channels.auto).labels});

% QC topoplot of flagged channels, using only channels that have coordinates
if isfield(EEG.chanlocs, 'theta')
    hasLoc = ~cellfun(@isempty, {EEG.chanlocs.theta});
else
    hasLoc = false(1, EEG.nbchan);
end
if sum(hasLoc) >= 3
    locIdx = find(hasLoc);
    [~, badInLocs] = ismember(intersect(badChans, locIdx), locIdx);   % bad channels, numbered within locIdx
    f1 = qcFigure('Color', 'w');   % hidden in a batch
    topoplot(zeros(numel(locIdx), 1), EEG.chanlocs(locIdx), 'electrodes', 'on', ...
             'emarker2', {badInLocs, '.', 'r', 14, 1});
    colormap(gca, [1 1 1]);
    addTopoLabels(f1, gca, EEG.chanlocs(locIdx));   % click an electrode for its name
    noLoc = setdiff(badChans, locIdx);
    titleText = 'Flagged channels (red)';
    if ~isempty(noLoc)
        titleText = {titleText, ['No location: ' strjoin({EEG.chanlocs(noLoc).labels}, ', ')]};
    end
    title(titleText, 'Interpreter', 'none');
    saveQCFigure(f1, fullfile(qcSave, [char(cfg_full.sessionID) '_badChanTopo']), true);
else
    fprintf('Skipping bad-channel topoplot: fewer than 3 channels have coordinates.\n');
end

% review table: checked = remove

editChanF = uifigure;
getScreen = get(0, 'ScreenSize');

figW = 800; figH = 800;
    editChanF.Position    = [(getScreen(3)-figW)/2, (getScreen(4)-figH)/2, figW, figH];

editLabel = uilabel(editChanF, "Text", sprintf("Use eegplot to review channels and edit here \n(NOTE: checked boxes will be removed)"));
editLabel.Position = [20 720 760 60];
editLabel.FontSize = 16;
editLabel.HorizontalAlignment = 'center';

chanItems = cell(EEG.nbchan, 1);
for ci = 1:numel(chanItems)
    if sum(ismember(ci, EEG.etc.bad_channels.auto)) > 0
        chanItems{ci} = EEG.chanlocs(ci).labels;
        badReasons = EEG.etc.bad_channels.reasons{ci};
        badReasons = join(string(badReasons), ", ");
        chanItems{ci} = string(chanItems{ci}) +" MARKED BAD" + " -- " + string(badReasons);
    else
        chanItems{ci} = string(EEG.chanlocs(ci).labels);
    end

end

chanItems = cellstr(chanItems);



isBad = false(EEG.nbchan,1 );
isBad(EEG.etc.bad_channels.auto) = true; 
isBad(priorBad) = true;


chanT = table(chanItems, isBad, 'VariableNames', {'Channel/Reason(s)', 'Bad'});


naughtyList = uitable(editChanF, 'Data', chanT, 'ColumnEditable', [false true]);
naughtyList.Position = [20 60 760 600];

uibutton(editChanF, 'Text','Done', 'Position',[360 20 80 30], ...
         'ButtonPushedFcn', @(~,~) uiresume(editChanF));
applyTheme(editChanF);   % BIPATE colours
editChanF.CloseRequestFcn = @(~,~) uiresume(editChanF);   % closing with X counts as Done (was: table deleted -> error)
uiwait(editChanF);

finalBad = find(naughtyList.Data.Bad);          % checked rows -> channel indices
delete(editChanF);
% the review figures are done with now
if isvalid(fPSD), close(fPSD); end
if exist('f1', 'var') && isvalid(f1), close(f1); end

EEG.etc.bad_channels.manual_added   = setdiff(finalBad, EEG.etc.bad_channels.auto);
EEG.etc.bad_channels.manual_removed = setdiff(EEG.etc.bad_channels.auto, finalBad);
EEG.etc.bad_channels.final          = finalBad;

% mask (nothing removed from data here)
EEG.etc.bad_channels.removed_labels = {EEG.chanlocs(EEG.etc.bad_channels.final).labels};
EEG = mask_addChan(EEG, finalBad, 'badChanDetect');

% save

EEG.etc.processing_log{end+1} = sprintf('Bad channels detected at %s', string(datetime('now')));
[badTag, roundSuffix] = stepRound(EEG, 'badChanDetect');
EEG.etc.processing_done{end+1} = badTag;
savePath = fullfile(cfg_full.paths.data_out);
EEG.setname = [char(cfg_full.sessionID) '_badChanFlag' roundSuffix];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_badChanFlag' roundSuffix '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');

notifyDone('Bad Channel Detection')



end



% data tips on a topoplot's electrodes: clicking one shows its channel label
% IN:  fig, ax = the topoplot's figure and axes; locs = the chanlocs that were plotted, in order
% Positions are worked out the way topoplot places electrodes (polar theta/radius from readlocs, squeezed
% by 0.5/plotrad, drawn at (y, x)), because topoplot splits them over several marker lines (flagged ones
% via emarker2 are a separate line) so the plotted lines cannot be matched to labels one-to-one.
function addTopoLabels(fig, ax, locs)
[~, labels, theta, radius] = readlocs(locs);
[x, y] = pol2cart(pi / 180 * theta, radius);
plotrad = max(min(1.0, max(radius) * 1.02), 0.5);   % topoplot's default plotting radius
squeeze = 0.5 / plotrad;
pos = [y(:) * squeeze, x(:) * squeeze];            % [nChan x 2] screen x, y of each electrode
markerLines = findobj(ax, 'Type', 'line', '-not', 'Marker', 'none');
set(findobj(ax, 'Type', 'line'), 'PickableParts', 'none');
set(markerLines, 'PickableParts', 'visible');
dcm = datacursormode(fig);
dcm.Enable = 'on';
dcm.UpdateFcn = @(~, evt) labelAt(evt, pos, labels);
end

function txt = labelAt(evt, pos, labels)
[~, k] = min((pos(:, 1) - evt.Position(1)).^2 + (pos(:, 2) - evt.Position(2)).^2);
txt = labels{k};
end

% checkbox window for choosing detection methods (defaults pre-ticked); returns indices into choices
function sel = pickFeatures(choices, cfg_full)
    figH = 80 + 30 * numel(choices);
    fig = uifigure('Name', 'Select detection methods', 'Position', [400 400 340 figH]);
    cbs = gobjects(numel(choices), 1);
    defaults = cfg_full.artifact.badChanMethodDef;
    for i = 1:numel(choices)
        isDef = any(strcmp(choices{i}, defaults));
        cbs(i) = uicheckbox(fig, 'Text', choices{i}, ...
                            'Position', [20 figH-30*i-10 310 25], ...
                            'Value', isDef);  
    end
    btn = uibutton(fig, 'Text', 'OK', 'Position', [110 20 80 30]);
    btn.ButtonPushedFcn = @(~,~) uiresume(fig);
    applyTheme(fig);
    uiwait(fig);
    sel = find(arrayfun(@(c) c.Value, cbs));
    close(fig);
end

% sample indices (into EEG.data(:, :)) of the segments every feature is computed in:
% continuous data = non-overlapping winSec windows that contain no sample marked bad in EEG.masks.seg;
% epoched data = each epoch not marked bad in EEG.masks.epoch
function segments = detectionSegments(EEG, winSec)
if EEG.trials > 1
    [~, ~, goodEpoch] = mask_good(EEG);
    keep = find(goodEpoch(:)');
    segments = arrayfun(@(ep) (ep - 1) * EEG.pnts + (1:EEG.pnts), keep, 'UniformOutput', false);
    return
end
% windows are laid inside each kept stretch (not on one grid from time 0), so every kept piece is looked at:
% a stretch is cut into winSec windows, and its leftover tail (or a whole stretch shorter than winSec) becomes
% its own window when it is at least minSec long
[~, goodSamp] = mask_good(EEG);
winLen = round(winSec * EEG.srate);
minLen = round(2 * EEG.srate);   % shortest piece worth a window (2 s)
edges = diff([false logical(goodSamp(:)') false]);
runStart = find(edges == 1);
runEnd = find(edges == -1) - 1;
segments = {};
for r = 1:numel(runStart)
    s = runStart(r);
    while runEnd(r) - s + 1 >= winLen
        segments{end + 1} = s:(s + winLen - 1); %#ok<AGROW>
        s = s + winLen;
    end
    if runEnd(r) - s + 1 >= minLen
        segments{end + 1} = s:runEnd(r); %#ok<AGROW>
    end
end
if isempty(segments) && any(goodSamp)   % only slivers under 2 s are kept: use all clean samples together
    segments = {find(goodSamp)};
end
end
