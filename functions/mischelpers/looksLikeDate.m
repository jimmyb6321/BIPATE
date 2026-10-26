function [tf, hit] = looksLikeDate(str)

% Author: James Barlow
% Created: 09/01/2026
% Last updated: 10/18/2026

% PHI screen: flags user-typed text that looks like a calendar date before it ends up in a filename.
% Errs toward flagging: a false positive costs one click, a false negative can put PHI in a filename.

% IN:   str = text to check (char or string)

% OUT:  tf = true if str plausibly contains a date
%       hit = the matching substring ('' when tf is false)

arguments
    str {mustBeTextScalar}
end

str = strtrim(char(str));
tf  = false;
hit = '';

if isempty(str), return; end   % blank is never a date

months = '(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)';

pats = { ...
    '\d{1,4}[-/._]\d{1,2}([-/._]\d{1,4})?', ...   % 1-2-26, 2026-01-02, 01/02, 3.4.25
    '(?<!\d)\d{6}(?!\d)', ...                     % 010226, 260102
    '(?<!\d)\d{8}(?!\d)', ...                     % 20260102
    '(?<!\d)(19|20)\d{2}(?!\d)', ...              % bare 4-digit year
    ['(?i)' months '[a-z]*\s*[-_]?\s*\d{1,4}'], ...  % Jan2026, march-02
    ['(?i)\d{1,4}\s*[-_]?\s*' months '[a-z]*'], ...   % 02Jan, 2-march
    ['(?i)(?<![a-z])' months '(uary|ruary|ch|il|e|y|ust|tember|ober|ember)?(?![a-z])'] ... % bare month name
};

for k = 1:numel(pats)
    m = regexp(str, pats{k}, 'match', 'once');
    if ~isempty(m)
        tf = true; hit = m; return
    end
end

% last resort: anything MATLAB parses as a datetime
try
    datetime(str);
    tf = true; hit = str;
catch
    % not parseable - fine
end

end