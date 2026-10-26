function doneJobs = inputHistory(filePath)

% Author: James Barlow
% Created: 10/24/2026
% Last updated: 10/24/2026

% Reads the processing history an input .set already carries (EEG.etc.processing_done) without loading the
% data, so bipate's job plan counts the jobs done to it before. Other formats, and .set files from outside
% BIPATE, have no history and return {}.

% IN:   filePath = full path of the input recording (char or string)

% OUT:  doneJobs = 1 x n cellstr of done tags, {} when there are none or the header cannot be read

arguments
    filePath {mustBeTextScalar}
end

doneJobs = {};
filePath = char(filePath);
[~, ~, ext] = fileparts(filePath);
if ~strcmpi(ext, '.set') || ~isfile(filePath)
    return
end
try
    vars = {whos('-file', filePath).name};
    if any(strcmp(vars, 'etc'))          % onefile / v7.3 save: the EEG fields are top-level variables
        S = load(filePath, '-mat', 'etc');
        etc = S.etc;
    elseif any(strcmp(vars, 'EEG'))      % older save: one EEG struct (this also loads the data)
        S = load(filePath, '-mat', 'EEG');
        etc = S.EEG.etc;
    else
        return
    end
    if isfield(etc, 'processing_done') && ~isempty(etc.processing_done)
        doneJobs = cellstr(string(etc.processing_done(:)'));
    end
catch
    doneJobs = {};   % unreadable header: treat it as a fresh recording
end
end