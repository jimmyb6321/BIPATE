function EEG = componentRemoval(EEG, cfg_full)

% Author: James Barlow
% Created: 06/19/2026
% Last updated: 10/25/2026

% Semi-automated ICA component removal: ICLabel flags confident artifact components, optional manual review,
% QC topo grids of kept vs removed, then removes the flagged components (no interpolation)

% IN:   EEG = EEGLAB struct after callICA (icaweights/icasphere set)
%       cfg_full = configuration struct (ica.artifactThresh, sessionID, paths.data_out)

% OUT:  EEG = component-removed EEG struct, saved to the set's folder
%           EEG.etc.removed_components{n} = component indices removed in removal round n
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

checkPrerequisites(EEG, 'compRemoval');   % what must run first is listed in jobs.json
if EEG.trials > 1
    isEpoched = true;
else
    isEpoched = false;
end
if isempty(EEG.icaweights)
    error('componentRemoval:noICA', 'No ICA decomposition found -- run callICA first.');
end
% rebuild component activations if they weren't stored
if isempty(EEG.icaact)
    if isEpoched
        d = EEG.data(EEG.icachansind, :, :);
        d2 = reshape(d, size(d, 1), []);
        act = (EEG.icaweights*EEG.icasphere) * d2;
        EEG.icaact = reshape(act, size(act, 1), EEG.pnts, EEG.trials);
    else
        EEG.icaact = (EEG.icaweights*EEG.icasphere)*EEG.data(EEG.icachansind,:);
    end
end
% ICLabel: flag any artifact class at or above threshold; Brain and Other are never flagged
% threshold rows: [Brain; Muscle; Eye; Heart; Line; Channel; Other]
EEG = pop_iclabel(EEG, 'default');
at = cfg_full.ica.artifactThresh;
thresh = [ nan(1,2);                 % Brain   - never flag
           repmat([at 1], 5, 1);     % Muscle/Eye/Heart/Line/Channel - flag if prob >= at
           nan(1,2) ];               % Other   - left alone (ambiguous catch-all)
% Manual mode (set's Artifact column): ICLabel still runs so its class labels show in the viewers, but
% nothing is pre-marked; Semi-automatic pre-marks every component at or above the threshold for review
manualMode = isfield(cfg_full, 'artifact') && isfield(cfg_full.artifact, 'mode') && strcmpi(string(cfg_full.artifact.mode), 'Manual');
if manualMode
    EEG.reject.gcompreject = zeros(1, size(EEG.icaweights, 1));
    fprintf('Manual mode: ICLabel labels for reference only, no components pre-marked\n');
else
    EEG = pop_icflag(EEG, thresh);
    fprintf('ICLabel flagged %d / %d comps (artifact class >= %.2f)\n', ...
        sum(EEG.reject.gcompreject), size(EEG.icaweights,1), cfg_full.ica.artifactThresh);
end
% optional manual review. In both viewers you click a component, set ACCEPT/REJECT in its window and
% press OK. That OK writes to EEGLAB's GLOBAL variable EEG (pop_prop / pop_prop_extended run
% "global EEG; EEG.reject.gcompreject(k) = ..."), not to this function's copy, so the set is put in the
% global first and the flags (EEG.reject.gcompreject) are read back once every viewer window is closed.
%   Lite     = pop_selectcomps: grid of component maps, flagged ones red
%   Advanced = pop_viewprops (viewprops plugin): grid with ICLabel class percentages on every map and a
%              fuller component window (spectrum, activity image, ICLabel bars). viewprops itself does not
%              colour the grid, so colourFlagged does it and links each component window back to its button.
viewers  = ["Lite", "Advanced (ICLabel details)"];
plotForm = batchShared('get');
if isempty(plotForm)
    plotForm = listdlg('PromptString', 'Select viewer for component review', 'SelectionMode', 'single', ...
                       'ListSize', [260 120], 'InitialValue', 1, 'ListString', viewers);
    batchShared('set', plotForm);
end
if ~isempty(plotForm)
    useViewer = viewers(plotForm);
    if startsWith(useViewer, "Advanced") && ~exist('pop_viewprops', 'file')
        warning('componentRemoval:viewprops', 'viewprops is not installed; using the Lite viewer.');
        useViewer = "Lite";
    end
    nComp = size(EEG.icaweights, 1);
    setReviewGlobals(EEG);                    % what the viewer windows read and write
    figsBefore = findall(groot, 'Type', 'figure');
    if startsWith(useViewer, "Advanced")
        pop_viewprops(EEG, 0, 1:nComp);       % one grid window per 35 components
    else
        pop_selectcomps(EEG, 1:nComp);
    end
    gridFigs = setdiff(findall(groot, 'Type', 'figure'), figsBefore);
    if startsWith(useViewer, "Advanced")
        colourFlagged(gridFigs, EEG.reject.gcompreject);
    end
    for g = 1:numel(gridFigs)                 % wait until every grid window is closed
        if isvalid(gridFigs(g)), uiwait(gridFigs(g)); end
    end
    edited = getReviewEEG();
    if isstruct(edited) && isfield(edited, 'reject') && numel(edited.reject.gcompreject) == nComp
        changed = nnz(logical(edited.reject.gcompreject(:)) ~= logical(EEG.reject.gcompreject(:)));
        EEG.reject.gcompreject = edited.reject.gcompreject;
        fprintf('Component review: %d flag(s) changed by hand, %d component(s) to remove.\n', changed, nnz(EEG.reject.gcompreject));
    end
    setReviewGlobals([]);                     % do not leave a copy of the data in memory
end
% QC topo grids of kept vs removed comps (before removal, while comps still exist)
rej  = find(EEG.reject.gcompreject);
kept = find(~EEG.reject.gcompreject);
qcSave = fullfile(cfg_full.paths.data_out, 'QC');
if ~isfolder(qcSave); mkdir(qcSave); end
ppt = char(cfg_full.sessionID);
maxPlot = 35;   % topos per page
groups = {kept, [ppt '_keptComps']; rej, [ppt '_removedComps']};
hasLocs = isfield(EEG.chanlocs,'theta') && any(~cellfun(@isempty,{EEG.chanlocs.theta}));
for gi = 1:size(groups,1)
    comps = groups{gi,1};   fnameBase = groups{gi,2};
    if isempty(comps); continue; end
    n = numel(comps); 
    pgs = ceil(n / maxPlot);
    for pg = 1:pgs
        if hasLocs
            startn = maxPlot * (pg - 1) + 1;
            stopn = min(maxPlot * pg, n);
            n1 = stopn - startn + 1;
            nc = ceil(sqrt(n1)); nr = ceil(n1/nc);
            f = figure('Color','w','Visible','off');   % own hidden figure avoids pop_topoplot's curfig crash
            fname = [fnameBase num2str(pg)];
            for i = startn:stopn
                subplot(nr, nc, i - startn + 1);
                topoplot(EEG.icawinv(:,comps(i)), EEG.chanlocs(EEG.icachansind), 'electrodes','off');
                title(sprintf('IC%d', comps(i)), 'FontSize', 7);
            end
            try
                saveas(f,  fullfile(qcSave, [fname '.png']));
                savefig(f, fullfile(qcSave, [fname '.fig']));
            catch ME
                warning('componentRemoval:QC', '%s QC skipped: %s', fname, ME.message);
            end
            close(f);
        end
    end
end
if ~isfield(EEG.etc, 'removed_components')
    EEG.etc.removed_components = {};
end
if ~isempty(rej)
    EEG.etc.removed_components{end+1} = rej;
end
% remove flagged components
EEG = pop_subcomp(EEG, [], 0);
EEG.icaact = [];
% number this removal round from processing_done, then save
crCheck = unique(EEG.etc.processing_done);
crRan   = crCheck(~cellfun(@isempty, regexp(crCheck, '^componentRemoval\d+$', 'once')));
crCount = 0;
for ic = 1:numel(crRan)
    nm = char(crRan{ic});
    if isstrprop(nm(end), 'digit'); crCount = crCount + 1; end
end
crName = ['componentRemoval' num2str(crCount + 1)];
EEG.etc.processing_log{end+1}  = sprintf([crName ' done at %s'], string(datetime('now')));
EEG.etc.processing_done{end+1} = crName;
savePath = fullfile(cfg_full.paths.data_out);
if ~isfolder(savePath); mkdir(savePath); end
if isEpoched
    EEG = baseline_max(EEG, 'compRemoval');
end
EEG.setname = [ppt '_' crName];
EEG = saveStep(EEG, 'filename', [ppt '_' crName '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone('Component Removal Done')
end


% puts E in EEGLAB's globals (EEG, ALLEEG, CURRENTSET) and links the base workspace to them, so the
% viewers' button callbacks (which run in the base workspace) edit this copy; setReviewGlobals([]) empties them
function setReviewGlobals(E)
global EEG ALLEEG CURRENTSET
EEG = E;
ALLEEG = E;
CURRENTSET = double(~isempty(E));
evalin('base', 'global EEG ALLEEG CURRENTSET');
end

function E = getReviewEEG()
global EEG
E = EEG;
end

% viewprops grids: flagged components red, and each button's component window updates that button's
% colour when its OK is pressed (viewprops passes no button to the window, so it never did)
% IN:  figs = the grid windows pop_viewprops opened; flags = EEG.reject.gcompreject
function colourFlagged(figs, flags)
rejColour = [1 0.6 0.6];   % COLREJ in EEGLAB's icadefs
for f = 1:numel(figs)
    buttons = findobj(figs(f), '-regexp', 'Tag', '^comp\d+$');
    for b = buttons(:)'
        k = str2double(erase(b.Tag, 'comp'));
        if k <= numel(flags) && flags(k)
            b.BackgroundColor = rejColour;
        end
        cb = b.Callback;
        if iscell(cb) && numel(cb) >= 5
            cb{5} = double(b);   % winhandle: the window's OK recolours this button
            b.Callback = cb;
        end
    end
end
end
