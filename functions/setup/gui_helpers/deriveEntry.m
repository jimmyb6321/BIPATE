function entry = deriveEntry(entry, filepath, cfg)

% Author: James Barlow
% Created: 10/15/2026
% Last updated: 10/25/2026

% Plugs in file paths into queue

% IN:   entry = queue entry
%       filepath = filepath for file from GUI selection.
%       cfg = configuration file

%OUT:   entry = updated queue entry (struct).

arguments
    entry (1,1) struct
    filepath {mustBeTextScalar}
    cfg (1,1) struct
end

filepath = strip(filepath, 'right', '\');
% several .mff recordings joined into one set: paths joined by "|" (bipate Add set); every one must exist
if contains(filepath, '|')
    parts = strtrim(strsplit(char(filepath), '|'));
    if ~all(cellfun(@isfolder, parts))
        entry.state.status = 'failed';
        entry.state.message = 'One of the joined .mff recordings does not exist on this machine!';
        return;
    end
    entry.identity.filePath = char(filepath);
    [~, first] = fileparts(parts{1});
    entry.identity.fileName = sprintf('%s (+%d)', first, numel(parts) - 1);
    entry.identity.inputFormat = '.mff';
    return
end
if ~isfile(filepath) && ~isfolder(filepath)
    entry.state.status = 'failed';
    entry.state.message = 'File does not exist on this machine!';
    return;
end
try
    entry.identity.filePath = filepath;
    [~, entry.identity.fileName, entry.identity.inputFormat] = fileparts(filepath);
catch ME
    entry.state.status = 'failed';
    entry.state.message = ME.message;
    return;
end


if ~ismember(lower(entry.identity.inputFormat), lower(cfg.recording.inputTypes(2:end)))
    entry.state.status = 'failed';
    entry.state.message = 'File type is not supported by BIPATE';

end

