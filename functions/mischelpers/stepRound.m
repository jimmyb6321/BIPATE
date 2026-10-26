function [tag, roundSuffix] = stepRound(EEG, baseTag)

% Author: James Barlow
% Created: 10/18/2026
% Last updated: 10/20/2026

% Names the next run of a step so running it again does not overwrite the last run.
% The first run keeps the plain name, later runs get a number, the same way callICA numbers ICA rounds:
%   first run   tag = 'filter'    roundSuffix = ''
%   second run  tag = 'filter2'   roundSuffix = '2'
% Earlier runs are counted from EEG.etc.processing_done ("(...)" notes are ignored, so
% 'resample (skipped)' counts as a run of 'resample').
% A tag that already ends in a digit gets an underscore before the round, so it still reads apart:
%   second run of 'rerefm1m2'   tag = 'rerefm1m2_2'   roundSuffix = '2'

% IN:   EEG = EEGLAB struct (reads EEG.etc.processing_done)
%       baseTag = the step's tag, e.g. 'filter'

% OUT:  tag = baseTag, or baseTag followed by the round number
%       roundSuffix = '' on the first run, otherwise the round number as text (for file names)

arguments
    EEG (1,1) struct
    baseTag {mustBeTextScalar}
end

doneTags = {};
if isfield(EEG, 'etc') && isfield(EEG.etc, 'processing_done')
    doneTags = cellstr(string(EEG.etc.processing_done));
end
doneTags = strtrim(regexprep(doneTags, '\s*\(.*?\)', ''));
sep = '';
if ~isempty(regexp(char(baseTag), '\d$', 'once'))   % e.g. rerefm1m2: keep the round number apart from the name
    sep = '_';
end
roundPattern = ['^' regexptranslate('escape', char(baseTag)) '(' sep '\d+)?$'];
nRuns = sum(~cellfun(@isempty, regexpi(doneTags, roundPattern, 'once')));

if nRuns == 0
    roundSuffix = '';
    sep = '';
else
    roundSuffix = num2str(nRuns + 1);
end
tag = [char(baseTag) sep roundSuffix];
end
