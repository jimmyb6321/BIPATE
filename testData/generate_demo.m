% generate_demo
%
% Author: James Barlow
% Created: 06/17/2026
% Last updated: 10/25/2026
%
%% Demo dataset generator for BIPATE
%
% Builds a complete, self-contained demo recording that runs the whole
% pipeline from loadData_max through exportQC, and writes it as a real .mff
% folder so the file-conversion path is exercised too. A .set copy is written
% alongside for when you want to skip straight past conversion.
%
% Hyperparameters follow the reference recording
% a real 258-channel GSN HydroCel-257 recording (EGI Net Amps) --
%   258 channels (E1..E257 plus ECG typed PNS), 500 Hz, referenced to E257,
%   EGI User Markup event codes -- shortened to 3 minutes so a demo run
%   finishes in a coffee break rather than an afternoon.
%
% The signal itself comes from synthEEG, which builds the background in
% source space so neighbouring channels are genuinely correlated. See that
% file for what is planted and why.
%
% What this exercises
%   loadData_max     .mff -> .set conversion, etc.mffFolder
%   chanSetup        GSN257 branch, metaTime from etc.recordingtime
%   chanReduce       257 -> 185, E257 reference dropped
%   runVideoEditor   two video segments, a sync gap, EGI movieSyncs1.xml
%   segmentEEG       real event codes to anchor span and global rules
%   downsample/filter 500 -> 250 Hz, 0.5 Hz highpass, 60/120 notch
%   badChanDetect    one planted channel per feature (EEG.etc.demo)
%   segmentRejection movement, chewing and electrode-pop windows
%   ICA + ICLabel    blink, saccade, cardiac, muscle and line components
%   mask_applyCuts   markers planted inside artifact windows, for relocation
%
% Ground truth is in EEG.etc.demo and printed at the end of this script.

clear; clc
here = fileparts(mfilename('fullpath'));      % <repo>\testData
varPath = fullfile(fileparts(here), 'permanent_variables');
load(fullfile(bipateUserDir(), 'eeglabPath.mat'), 'eeglabPath');   % saved by bipate on first launch
addpath(char(eeglabPath)); eeglab nogui;
addpath(here);


outDir  = here;

FS       = 500;
DUR      = 180;                                  % seconds
REC_TIME = datetime(2026,8,28,9,14,11,'TimeZone','America/Chicago');
MFF_NAME = sprintf('DEMO_%s', string(REC_TIME, 'yyyyMMdd_HHmmss'));

%% ------------------------------------------------------------ montage
hc = load(fullfile(varPath,'chanlocs257.mat'));
chanlocs = hc.chanlocs257;
[chanlocs.type] = deal('EEG');                   % chanSetup GSN257 branch

ecg = chanlocs(1);
ecg.labels = 'ECG';
ecg.type   = 'PNS';
for f = ["theta","radius","X","Y","Z","sph_theta","sph_phi","sph_radius"]
    if isfield(ecg, f), ecg.(f) = []; end
end
chanlocs = [chanlocs, ecg];

ki      = load(fullfile(varPath,'inside185ch.mat'));
keepIdx = ki.inside185ch(:)';                    % survives chanReduce
refIdx  = find(strcmp({chanlocs.labels},'E257'));
ecgIdx  = numel(chanlocs);

%% ------------------------------------------------------------ signal
fprintf('Generating %d s of %d-channel data at %g Hz...\n', DUR, numel(chanlocs), FS);
EEG = synthEEG(chanlocs, 'srate',FS, 'dur',DUR, 'seed',7, ...
               'refIdx',refIdx, 'pnsIdx',ecgIdx, 'ecgIdx',ecgIdx, ...
               'keepIdx',keepIdx);

demo = EEG.etc.demo;
mv   = [demo.badSegments(strcmp({demo.badSegments.kind},'movement')).t0; ...
        demo.badSegments(strcmp({demo.badSegments.kind},'movement')).t1]';
ch   = [demo.badSegments(strcmp({demo.badSegments.kind},'chewing')).t0; ...
        demo.badSegments(strcmp({demo.badSegments.kind},'chewing')).t1]';
pop  = demo.badSegments(strcmp({demo.badSegments.kind},'pop'));

%% ------------------------------------------------------------ events
% EGI User Markup codes, matching the reference recording. Two markers are
% deliberately placed inside artifact windows so mask_applyCuts has something
% to relocate.
ev = { 'muon',   5.0
       'eyeo',  10.0
       'eyec',  45.0
       'eyeo',  75.0
       'spea', 120.0
       'eyec', 150.0
       'inen', 175.0 };
for k = 1:size(mv,1), ev(end+1,:) = {'move', mv(k,1) + 0.5}; end %#ok<SAGROW>
for k = 1:size(ch,1), ev(end+1,:) = {'emov', ch(k,1) + 0.5}; end %#ok<SAGROW>
ev(end+1,:) = {'inon', (pop.t0 + pop.t1)/2};     % marker inside the pop burst

[~, ord] = sort(cell2mat(ev(:,2)));
ev = ev(ord,:);

EEG.event = struct('type',     ev(:,1)', ...
                   'latency',  num2cell(cellfun(@(s) s*FS + 1, ev(:,2))'), ...
                   'duration', num2cell(ones(1, size(ev,1))));
EEG.setname = char(MFF_NAME);
EEG.subject = 'DEMO';
EEG.ref     = 'E257';
EEG = eeg_checkset(EEG, 'eventconsistency');

%% ------------------------------------------------------------ .mff export
mffPath = fullfile(outDir, MFF_NAME + ".mff");
if isfolder(mffPath)
    fprintf('Removing previous %s\n', mffPath);
    rmdir(mffPath, 's');
end

fprintf('Exporting .mff...\n');
X = EEG; X.etc = rmfield(X.etc, 'demo');          % keep ground truth out of the file
mff_export(X, char(fullfile(outDir, MFF_NAME)));

% mff_export writes a recordTime with a malformed UTC offset, which makes the
% importer fall back and shift the date by a day. Rewrite it properly so
% chanSetup derives the right metaTime.
fixRecordTime(fullfile(mffPath,'info.xml'), REC_TIME);

% Same problem, worse consequence: every <beginTime> in the exported event
% track carries the malformed offset and relativeBeginTime is written as 0,
% so the importer silently drops the whole event list. Rewrite both.
fixEventTimes(fullfile(mffPath,'Events_exported_from_EEGLAB.xml'), REC_TIME, ...
              [EEG.event.latency], FS);

%% ------------------------------------------------------------ video
fprintf('Rendering demo video...\n');
vsegs = demoVideo(string(mffPath), ...
                  'segments',    [0 DUR*0.495; DUR*0.51 DUR], ...
                  'moveWindows', mv, ...
                  'fps',         12, ...
                  'baseName',    MFF_NAME);

%% ------------------------------------------------------------ .set copy
EEG.etc.recordingtime = days(dateshift(REC_TIME,'start','second') - ...
                             datetime(2000,1,1,'TimeZone','America/Chicago'));
EEG.etc.mffFolder     = char(mffPath);
EEG.etc.timezone      = '-05:00';
EEG = pop_saveset(EEG, 'filename','demo_raw.set', 'filepath',char(outDir), ...
                  'savemode','onefile', 'version','7.3');

%% ------------------------------------------------------------ summary
fprintf('\n================ DEMO DATASET WRITTEN ================\n');
fprintf('  mff : %s\n', mffPath);
fprintf('  set : %s\n', fullfile(outDir,'demo_raw.set'));
fprintf('  %d ch, %g Hz, %g s, ref %s, %d events, ~%.0f bpm\n', ...
        EEG.nbchan, EEG.srate, DUR, EEG.ref, numel(EEG.event), demo.heartRateBPM);
fprintf('\n  video segments (EEG seconds covered):\n');
for k = 1:numel(vsegs)
    fprintf('    %-34s %6.1f - %6.1f s\n', vsegs(k).fileName, vsegs(k).eegBeginSec, vsegs(k).eegEndSec);
end
fprintf('    gap %.1f - %.1f s is deliberately uncovered\n', ...
        vsegs(1).eegEndSec, vsegs(2).eegBeginSec);

fprintf('\n  planted bad channels:\n');
for k = 1:numel(demo.badChannels)
    b = demo.badChannels(k);
    fprintf('    %-6s %-18s %s\n', b.label, b.kind, b.expect);
end
fprintf('\n  planted bad segments:\n');
for k = 1:numel(demo.badSegments)
    b = demo.badSegments(k);
    fprintf('    %-10s %6.1f - %6.1f s\n', b.kind, b.t0, b.t1);
end
fprintf('\n  %s\n', wrapText(demo.knownMisses, 68, '    '));
fprintf('======================================================\n');

%% ================================================================= local

function fixRecordTime(infoXml, when)
if ~isfile(infoXml), warning('generate_demo:noInfoXml','%s not found', infoXml); return; end
txt = fileread(infoXml);
iso = char(string(when, "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"));
txt = regexprep(txt, '<recordTime>.*?</recordTime>', ['<recordTime>' iso '</recordTime>'], 'once');
fid = fopen(infoXml,'w'); fwrite(fid, txt); fclose(fid);
end

function out = wrapText(s, width, pad)
w = strsplit(strtrim(s));
out = ''; line = '';
for k = 1:numel(w)
    if isempty(line), line = w{k};
    elseif numel(line) + numel(w{k}) + 1 <= width, line = [line ' ' w{k}]; %#ok<AGROW>
    else, out = [out line newline pad]; line = w{k}; %#ok<AGROW>
    end
end
out = [out line];
end
