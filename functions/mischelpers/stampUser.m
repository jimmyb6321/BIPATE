function EEG = stampUser(EEG, user)

% Author: James Barlow
% Created: 10/22/2026
% Last updated: 10/25/2026

% Records who processed a dataset: adds "Name, Credentials (Institution)" to EEG.etc.processed_by once per person,
% so a set handled by two people lists both, in the order they first touched it.

% IN:   EEG  = EEGLAB struct (any stage)
%       user = struct from BIPATE_user\userInfo.mat (fields name, credentials, institution), or empty

% OUT:  EEG  = same struct; EEG.etc.processed_by = cellstr, one entry per person

if isempty(user) || ~isstruct(user) || ~isfield(user, 'name') || isempty(user.name)
    return   % no first-launch info saved (user clicked Later): leave the set alone
end
who = char(user.name);
if isfield(user, 'credentials') && ~isempty(user.credentials)   % e.g. "Jane Doe, PhD"
    who = sprintf('%s, %s', who, char(user.credentials));
end
if isfield(user, 'institution') && ~isempty(user.institution)
    who = sprintf('%s (%s)', who, char(user.institution));
end
if ~isfield(EEG, 'etc') || ~isfield(EEG.etc, 'processed_by') || ~iscell(EEG.etc.processed_by)
    EEG.etc.processed_by = {};
end
if ~any(strcmp(EEG.etc.processed_by, who))
    EEG.etc.processed_by{end+1} = who;
end
end
