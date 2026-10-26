function fixEventTimes(xmlPath, recTime, latencies, fs)
% fixEventTimes  Repair the event track written by mff_export
%
% Author: James Barlow
% Created: 08/28/2026
% Last updated: 08/28/2026
%
% mffmatlabio's exporter writes every <beginTime> with a malformed UTC offset
% (the fractional seconds run on and the sign is dropped, e.g.
% 2026-08-28T11:02:18.5506338200374178910400:00) and writes every
% <relativeBeginTime> as 0. The importer cannot parse the first and has
% nothing to fall back on in the second, so it silently drops the entire
% event list -- pop_mffimport returns EEG.event = [].
%
% This rewrites both fields per event from the known EEGLAB latencies. Events
% are handled one <event> block at a time; a global strrep does not work
% because all thirteen relativeBeginTime elements are the identical string
% '<relativeBeginTime>0</relativeBeginTime>' and the first replacement would
% overwrite all of them with the same value.
%
% INPUTS
%   xmlPath    path to Events_exported_from_EEGLAB.xml inside the .mff
%   recTime    datetime of recording start (must carry a TimeZone)
%   latencies  EEG.event latencies, in samples, in file order
%   fs         sampling rate, Hz

if ~isfile(xmlPath)
    warning('fixEventTimes:noFile', '%s not found', xmlPath);
    return
end

txt   = fileread(xmlPath);
parts = strsplit(txt, '<event>');          % parts{1} is the header
if numel(parts) - 1 ~= numel(latencies)
    warning('fixEventTimes:count', 'event XML holds %d events, EEG has %d -- left alone', ...
            numel(parts)-1, numel(latencies));
    return
end

for k = 2:numel(parts)
    offSec = (latencies(k-1) - 1) / fs;
    iso    = char(string(recTime + seconds(offSec), "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"));
    blk    = parts{k};
    blk    = regexprep(blk, '<beginTime>.*?</beginTime>', ...
                       ['<beginTime>' iso '</beginTime>'], 'once');
    blk    = regexprep(blk, '<relativeBeginTime>.*?</relativeBeginTime>', ...
                       sprintf('<relativeBeginTime>%.0f</relativeBeginTime>', offSec*1e6), 'once');
    parts{k} = blk;
end

fid = fopen(xmlPath, 'w');
if fid < 0, error('fixEventTimes:write', 'Could not open %s for writing.', xmlPath); end
fwrite(fid, strjoin(parts, '<event>'));
fclose(fid);
end
