function userPath = bipateUserDir()

% Author: James Barlow
% Created: 10/25/2026
% Last updated: 10/25/2026

% The folder for everything personal to one user: settings (userPreferences.mat), Welcome info (userInfo.mat),
% the EEGLAB folder (eeglabPath.mat), job timings (jobTimes.mat), batch history and custom caps. It sits outside
% the BIPATE folder, so replacing BIPATE with a new version (ZIP or git) never touches it.
%   <userpath>\BIPATE_user   e.g. Documents\MATLAB\BIPATE_user on Windows (created when missing)

% IN:   none
% OUT:  userPath = char, full path of the folder

base = strtok(char(userpath), pathsep);   % MATLAB's user folder (older versions add a trailing pathsep)
if isempty(base)   % userpath can be empty on some setups: fall back to <home>\Documents\MATLAB
    base = fullfile(char(java.lang.System.getProperty('user.home')), 'Documents', 'MATLAB');
end
userPath = fullfile(base, 'BIPATE_user');
if ~isfolder(userPath)
    mkdir(userPath);
end
end
