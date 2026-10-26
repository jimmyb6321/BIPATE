function EEG = callICA(EEG, cfg_full)

% Author: James Barlow
% Created: 06/17/2026
% Last updated: 10/25/2026

% Runs ICA (Picard, AMICA, extended Infomax runica, or FastICA) on the good channels/samples and writes the weights back onto the full EEG

% IN:   EEG = EEGLAB struct after preICAreref (EEG.etc.ica_rank set there)
%       cfg_full = configuration struct (ica.method, ica.hp, ica.amica_threads, sessionID, paths.data_out)

% OUT:  EEG = EEG struct with icaweights/icasphere/icawinv/icachansind filled
%           EEG.etc.ica_algo.ICA<n> = method used for this ICA round
arguments
    EEG (1,1) struct
    cfg_full (1,1) struct
end

EEG = mask_init(EEG);
[goodChan, goodSamp] = mask_good(EEG);
checkPrerequisites(EEG, 'ica');   % what must run first is listed in jobs.json
% a second (or later) ICA is optional: ask first, and leave the set as it is if the answer is no
doneTags = cellstr(string(EEG.etc.processing_done));
earlierICA = doneTags(~cellfun(@isempty, regexp(doneTags, '^ICA\d+$', 'once')));
if ~isempty(earlierICA) || ~isempty(EEG.icaweights)
    if isempty(earlierICA), earlierICA = {'ICA'}; end
    again = questdlg(sprintf(['ICA has already been run on this set (%s). Are you sure you want to run ICA again?\n\n' ...
        'Yes = a new decomposition replaces the current one. No = skip this ICA and keep the current one.'], ...
        strjoin(earlierICA, ', ')), 'Run ICA again?', 'Yes', 'No', 'No');
    if ~strcmp(again, 'Yes')
        EEG.etc.processing_log{end+1} = sprintf('Repeat ICA skipped (kept %s) at %s', earlierICA{end}, string(datetime('now')));
        fprintf('ICA skipped: the set keeps %s.\n', earlierICA{end});
        return
    end
end
if isfield(EEG.etc, "ica_rank")
    r = EEG.etc.ica_rank;
else
    warning('ICA ranks not properly saved! Regenerating...');
    r = EEG.nbchan - 1;
end
method = cfg_full.ica.method;
% temp copy: extra highpass for ICA, bad samples cut, bad channels dropped
tmpEEG = pop_eegfiltnew(EEG, cfg_full.ica.hp, []);   
runner = diff([false ~goodSamp false]);
rStart = find(runner == 1)';
rEnd = (find(runner == -1) - 1)';
ranges = [rStart, rEnd];
tmpEEG = eeg_eegrej(tmpEEG, ranges);
tmpEEG = pop_select(tmpEEG, 'channel', find(goodChan));
switch method
    case "Picard"
        tmpEEG = pop_runica(tmpEEG, 'icatype','picard', 'pca', r, 'mode', 'ortho', 'maxiter', 500);
        W = tmpEEG.icaweights;  S = tmpEEG.icasphere;  A = tmpEEG.icawinv;
    case "AMICA"
        outdir = fullfile(tempdir, ['amica_' char(cfg_full.sessionID)]);   
        if isfolder(outdir); rmdir(outdir,'s'); end                    
        mkdir(outdir);
        runamica15(tmpEEG.data, 'num_models',1, 'outdir',outdir, 'pcakeep',r, 'max_threads',cfg_full.ica.amica_threads, 'max_iter',1000);
        mod = loadmodout15(outdir);            % load AMICA results
        W = mod.W; A = mod.A;  
        S = mod.S(1:size(mod.W,1), :);
        rmdir(outdir, 's');
    case {"runica", "Infomax"}   % extended Infomax (EEGLAB's own)
        tmpEEG = pop_runica(tmpEEG, 'icatype', 'runica', 'extended', 1, 'pca', r, 'maxsteps', 1024);
        W = tmpEEG.icaweights;  S = tmpEEG.icasphere;  A = tmpEEG.icawinv;
    case "FastICA"   % FastICA plugin, symmetric approach
        if ~exist('fastica', 'file')
            error(['FastICA is not on the path: install the FastICA plugin (EEGLAB > File > Manage EEGLAB ' ...
                'extensions) or pick another ICA method.']);
        end
        tmpEEG = pop_runica(tmpEEG, 'icatype', 'fastica', 'lastEig', r, 'numOfIC', r, 'approach', 'symm', 'g', 'tanh');
        W = tmpEEG.icaweights;  S = tmpEEG.icasphere;  A = tmpEEG.icawinv;
    otherwise
        error('Unknown ICA method "%s" (use Picard, AMICA, runica or FastICA).', method);
end
clear tmpEEG
% weights go back onto the full (unfiltered, uncut) data
EEG.icaweights  = W;         
EEG.icasphere   = S;
EEG.icawinv     = A;
EEG.icachansind = find(goodChan);
EEG = eeg_checkset(EEG, 'ica');  
% number this ICA round (ICA1, ICA2, ...) from processing_done
icaCheck = unique(EEG.etc.processing_done);
icaRan = icaCheck(~cellfun(@isempty, regexp(icaCheck, '^ICA\d+$', 'once')));   % ICA1, ICA2, ... only
icaCount = 0;
for ic = 1:numel(icaRan)
    yesICA = char(icaRan{ic});
   
    if isstrprop(yesICA(end), 'digit')
        icaCount = icaCount + 1;
    end
end
icaName = ['ICA' num2str(icaCount + 1)];
EEG.etc.ica_algo.(icaName) = char(method);
EEG.etc.processing_log{end+1} = sprintf([icaName ' done at %s'], string(datetime('now')));
EEG.etc.processing_done{end+1} = icaName;
if strcmpi(icaName, 'ICA1')
    savePath = fullfile(cfg_full.paths.data_out);
elseif strcmpi(icaName, 'ICA2')
    savePath = fullfile(cfg_full.paths.data_out);
else
    savePath = fullfile(cfg_full.paths.data_out);
    if ~isfolder(savePath); mkdir(savePath); end
end
    
% ICLabel classes (saved with the set) and a look-only overview of the components, so what comes next
% (segment rejection on components, another ICA, component removal) can be decided from them
if exist('iclabel', 'file')
    try
        EEG = iclabel(EEG);
    catch ME
        warning('callICA:iclabel', 'ICLabel failed: %s', ME.message);
    end
end
showComponents(EEG, cfg_full, icaName);

EEG.setname = [char(cfg_full.sessionID) '_' icaName];
EEG = saveStep(EEG, 'filename', [char(cfg_full.sessionID) '_' icaName '.set'], ...
    'filepath', char(savePath), 'savemode', 'onefile', 'version', '7.3');
notifyDone(icaName);
end


% look-only grid of the first 35 component maps, titled with their ICLabel class; saved to
% QC\figures\<sessionID>_<ICAn>_components and left open until the user closes it (the job waits)
% IN:  EEG with icawinv / icachansind (and etc.ic_classification.ICLabel if ICLabel ran), cfg_full, icaName
function showComponents(EEG, cfg_full, icaName)
nComp = size(EEG.icawinv, 2);
nShow = min(35, nComp);
hasClass = isfield(EEG.etc, 'ic_classification') && isfield(EEG.etc.ic_classification, 'ICLabel');
fig = figure('Name', sprintf('%s: first %d of %d components (look only; close to continue)', icaName, nShow, nComp), ...
    'NumberTitle', 'off', 'Color', 'w', 'Visible', 'off', 'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);   % drawn hidden, shown when complete
locs = EEG.chanlocs(EEG.icachansind);
try   % look-only: a problem drawing the overview must never fail the ICA itself
for k = 1:nShow
    subplot(5, 7, k);
    topoplot(EEG.icawinv(:, k), locs, 'electrodes', 'off');
    label = sprintf('IC%d', k);
    if hasClass
        [p, c] = max(EEG.etc.ic_classification.ICLabel.classifications(k, :));
        label = sprintf('IC%d %s %.0f%%', k, EEG.etc.ic_classification.ICLabel.classes{c}, 100 * p);
    end
    title(label, 'FontSize', 8, 'Interpreter', 'none');
end
catch ME
    warning('callICA:overview', 'Component overview not drawn: %s', ME.message);
    if isvalid(fig), close(fig); end
    return
end
qcSave = fullfile(cfg_full.paths.data_out, 'QC', 'figures');
if ~isfolder(qcSave), mkdir(qcSave); end
saveQCFigure(fig, fullfile(qcSave, [char(cfg_full.sessionID) '_' icaName '_components']), true);
% in a batch the overview opens for the first set only (the rest are saved to QC\figures, not shown);
% bipate clears 'bipateICAOverviewShown' at the start and end of every batch
inBatch = isappdata(0, 'bipateBatch') && getappdata(0, 'bipateBatch');
alreadyShown = inBatch && isappdata(0, 'bipateICAOverviewShown') && getappdata(0, 'bipateICAOverviewShown');
if isvalid(fig) && alreadyShown
    delete(fig);
elseif isvalid(fig)   % saveQCFigure may already have closed it (Settings: no QC figures)
    if inBatch, setappdata(0, 'bipateICAOverviewShown', true); end
    fig.Visible = 'on';
    uiwait(fig);   % the batch carries on once the overview is closed
end
end
