function check_dependencies()

% Author: James Barlow
% Created: 05/04/2026
% Last updated: 10/25/2026

% Reports MATLAB/EEGLAB versions, checks toolbox licences, and installs any missing EEGLAB plugins
% (warns with a download link for the ones that can't auto-install)

% IN:   none (EEGLAB must be on the path)

% OUT:  none

% TODO: add fieldtrip, ssp

% versions
matlabVer = version('-release');   % e.g. '2023b'
eeglabVer = eeg_getversion();
fprintf('Built on MATLAB R2023b and EEGLAB 2023.1\n');
fprintf('Your MATLAB: %s | Your EEGLAB: %s\n', matlabVer, eeglabVer);


% toolboxes
if license('test', 'Signal_Toolbox') == 0
    warning('Signal Processing Toolbox is not installed! Please download for this package to function correctly')
end

if license('test', 'Statistics_Toolbox') == 0
    warning('Statistics and Machine Learning Toolbox is not installed! Please download for this package to function correctly')
end

% plugins: install if missing
if ~exist('sopen', 'file')
    warning('BIOSIG not installed! Installing now')
    plugin_askinstall('Biosig', 'sopen', true);  % capital B
end

if ~exist('ft_read_data', 'file')
    warning('FileIO not installed! Installing now')
    plugin_askinstall('Fileio', 'ft_read_data', true);
end

% ICA: runica (extended Infomax) ships with EEGLAB and is the default; Picard, AMICA and FastICA are optional
% plugins, only needed when picked in Settings or a set's ICA choice (a note, not an install prompt)
if ~exist('picard', 'file'), fprintf('Optional ICA plugin PICARD not installed (EEGLAB > File > Manage extensions).\n'); end
if ~exist('runamica15', 'file'), fprintf('Optional ICA plugin AMICA not installed (EEGLAB > File > Manage extensions).\n'); end

% FastICA: manual download only
if ~exist('fastica', 'file')
    fprintf(['Optional: FastICA not found. Download manually from: ' ...
        'https://research.ics.aalto.fi/ica/fastica/ ' ...
        'and add to your MATLAB path. For MATLAB versions past 2004, use the version for MATLAB 7.x\n']);
end

if ~exist('pop_viewprops', 'file')   % optional (Advanced component viewer): never stops BIPATE from opening
    warning('viewprops not installed! Trying to install it (Advanced component viewer)')
    try
        plugin_askinstall('viewprops', 'pop_viewprops', true);
    catch ME
        warning('check_dependencies:viewprops', ['viewprops could not be installed from the EEGLAB server (%s). ' ...
            'Download https://github.com/sccn/viewprops into EEGLAB''s plugins folder; the Lite component viewer works without it.'], ME.message);
    end
end

if ~exist('iclabel', 'file')
    warning('ICLabel not installed! Installing now')
    plugin_askinstall('ICLabel', 'iclabel', true);
end

% clean_rawdata also needs its private\ helpers
if ~exist('clean_rawdata', 'file')
    warning('clean_rawdata not installed! Installing now')
    plugin_askinstall('clean_rawdata', 'clean_rawdata', true);
else
    crd = fileparts(which('clean_rawdata'));
    if isempty(dir(fullfile(crd, 'private', '*.m')))
        warning('clean_rawdata dependencies not found! Delete plugin folder and redownload off Github')
    end
end

if ~exist('firfilt', 'file')
    warning('firfilt not installed! Installing now')
    plugin_askinstall('firfilt', 'firfilt', true);
end

if ~exist('pop_mffimport', 'file')
    warning('MFFMatlabIO not installed! Installing now')
    plugin_askinstall('MFFMatlabIO', 'pop_mffimport', true);
end

if ~exist('bids_export', 'file')
    warning('EEG-BIDS not installed! Installing now')
    plugin_askinstall('EEG-BIDS', 'bids_export', true)
end

end