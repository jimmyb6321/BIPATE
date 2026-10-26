% demoVideo  Write synthetic monitoring video and movieSyncs1.xml into an .mff
%
% Author: James Barlow
% Created: 08/28/2026
% Last updated: 08/28/2026
%
% Produces the video side of the demo dataset: a small number of short MP4
% segments plus an EGI-schema movieSyncs1.xml, written into an existing .mff
% folder so that vidManifest / parseMovieSyncs / VideoEditorApp can be run
% end to end without any real recording.
%
% The video is generated rather than sourced. Real clinical monitoring video
% is patient footage regardless of where it is hosted, and this repository is
% headed for public release; a generated clip also carries a burned-in EEG
% clock, so whoever is watching the demo can see the frame time and the EEG
% cursor agree instead of taking the sync on faith.
%
% Each frame shows a stylised bedside view. The figure moves gently most of
% the time and thrashes during the windows passed in 'moveWindows', which are
% the same windows where synthEEG plants its movement artifact -- so the
% video and the EEG tell the same story.
%
% USAGE
%   segs = demoVideo(mffFolder, 'segments',[0 89; 91 180], ...
%                               'moveWindows', mv, 'baseName',"DEMO_20260828_100000")
%
% NAME-VALUE
%   segments     N-by-2, EEG seconds covered by each video file  ([0 89;91 180])
%   moveWindows  M-by-2, EEG seconds where the subject moves            ([])
%   fps          frames per second                                       (12)
%   width,height frame size                                        (320, 240)
%   baseName     stem for the .mp4 files                       ("DEMO_video")
%
% OUTPUT
%   segs  struct array (fileName, eegBeginSec, eegEndSec, videoBeginSec,
%         videoEndSec) matching what parseMovieSyncs will read back.
%
function segs = demoVideo(mffFolder, opts)
arguments
    mffFolder   (1,1) string
    opts.segments    (:,2) double = [0 89; 91 180]
    opts.moveWindows (:,2) double = zeros(0,2)
    opts.fps         (1,1) double = 12
    opts.width       (1,1) double = 320
    opts.height      (1,1) double = 240
    opts.baseName    (1,1) string = "DEMO_video"
end

if ~isfolder(mffFolder)
    error('demoVideo:noFolder', 'mff folder does not exist: %s', mffFolder);
end
if ~license('test','video_and_image_blockset') && isempty(which('insertText'))
    error('demoVideo:noCVT', 'Computer Vision Toolbox (insertText/insertShape) is required.');
end

W = opts.width; H = opts.height; fps = opts.fps;
nSeg = size(opts.segments, 1);
segs = struct('fileName',{},'eegBeginSec',{},'eegEndSec',{}, ...
              'videoBeginSec',{},'videoEndSec',{});

% static background: dark room with a lighter bed
[xx, yy] = meshgrid(1:W, 1:H);
bg = uint8(28 + 16*(yy/H) + 6*sin(2*pi*xx/W));
bg = repmat(bg, 1, 1, 3);
bg(:,:,3) = bg(:,:,3) + 12;
bedTop = round(0.46*H);
bg(bedTop:end, :, :) = bg(bedTop:end, :, :) + 26;

rng(11);

for s = 1:nSeg
    t0 = opts.segments(s,1);
    t1 = opts.segments(s,2);
    nFrames = max(1, round((t1 - t0) * fps));
    fname   = sprintf('%s_%d.mp4', opts.baseName, s);
    fpath   = fullfile(mffFolder, fname);

    vw = VideoWriter(fpath, 'MPEG-4');
    vw.FrameRate = fps;
    vw.Quality   = 70;
    open(vw);

    for k = 1:nFrames
        tEEG = t0 + (k-1)/fps;

        moving = any(tEEG >= opts.moveWindows(:,1) & tEEG <= opts.moveWindows(:,2));
        if moving
            jx = 9*sin(2*pi*3.1*tEEG) + 5*randn;
            jy = 7*sin(2*pi*2.3*tEEG + 1) + 4*randn;
        else
            jx = 1.5*sin(2*pi*0.20*tEEG);
            jy = 1.0*sin(2*pi*0.27*tEEG) + 0.8*sin(2*pi*0.9*tEEG);   % breathing
        end

        f = bg;
        cx = round(0.36*W + jx); cy = round(0.40*H + jy);
        f = insertShape(f, 'FilledRectangle', ...
                        [cx+18 cy-14 round(0.46*W) round(0.26*H)], ...
                        'Color', [150 150 160], 'Opacity', 1);
        f = insertShape(f, 'FilledCircle', [cx cy round(0.085*H)], ...
                        'Color', [205 185 170], 'Opacity', 1);
        f = insertShape(f, 'FilledCircle', [cx cy round(0.098*H)], ...
                        'Color', [90 130 200], 'Opacity', 0.35);   % net

        stamp = sprintf('EEG  %s', string(duration(0,0,tEEG, 'Format','hh:mm:ss.SS')));
        f = insertText(f, [6 4], stamp, 'FontSize', 14, ...
                       'BoxColor', [0 0 0], 'BoxOpacity', 0.55, 'TextColor', 'white');
        f = insertText(f, [6 H-24], sprintf('SEG %d   SYNTHETIC DEMO - NOT A PATIENT', s), ...
                       'FontSize', 10, 'BoxColor', [0 0 0], 'BoxOpacity', 0.55, ...
                       'TextColor', [255 210 120]);
        if moving
            f = insertText(f, [W-96 4], 'MOVEMENT', 'FontSize', 12, ...
                           'BoxColor', [140 0 0], 'BoxOpacity', 0.8, 'TextColor', 'white');
        end

        writeVideo(vw, f);
    end
    close(vw);

    segs(s).fileName      = fname;
    segs(s).eegBeginSec   = t0;
    segs(s).eegEndSec     = t1;
    segs(s).videoBeginSec = 0;
    segs(s).videoEndSec   = nFrames / fps;
    fprintf('  %s  %d frames  %.1f s  (EEG %.1f-%.1f s)\n', fname, nFrames, nFrames/fps, t0, t1);
end

writeMovieSyncs(fullfile(mffFolder, 'movieSyncs1.xml'), segs);
end

% ======================================================================= local

function writeMovieSyncs(xmlPath, segs)
% EGI movieSyncs schema: sample times in microseconds, video times in seconds
fid = fopen(xmlPath, 'w');
if fid < 0, error('demoVideo:xml', 'Could not open %s for writing.', xmlPath); end
c = onCleanup(@() fclose(fid));
fprintf(fid, '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\n');
fprintf(fid, ['<movieSyncs xmlns="http://www.egi.com/movieSyncs_mff" ' ...
              'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n']);
for k = 1:numel(segs)
    fprintf(fid, '    <movieSync>\n');
    fprintf(fid, '        <fileName>%s</fileName>\n',                segs(k).fileName);
    fprintf(fid, '        <sampleBeginTime>%.0f</sampleBeginTime>\n', segs(k).eegBeginSec*1e6);
    fprintf(fid, '        <sampleEndTime>%.0f</sampleEndTime>\n',     segs(k).eegEndSec*1e6);
    fprintf(fid, '        <videoBeginTime>%.9f</videoBeginTime>\n',   segs(k).videoBeginSec);
    fprintf(fid, '        <videoEndTime>%.6f</videoEndTime>\n',       segs(k).videoEndSec);
    fprintf(fid, '        <category>-1</category>\n');
    fprintf(fid, '        <segment>-1</segment>\n');
    fprintf(fid, '    </movieSync>\n');
end
fprintf(fid, '</movieSyncs>\n');
end
