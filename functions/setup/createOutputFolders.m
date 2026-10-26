function createOutputFolders(cfg_full)

% Author: James Barlow
% Created: 05/05/2026
% Last updated: 10/25/2026

% Makes the set's output folder (data_out) with QC, QC\figures and Configurations inside; every step's .set is saved straight into data_out

% IN:   cfg_full = configuration struct (paths.data_out)

% OUT:  none

arguments
    cfg_full (1,1) struct
end

dataPath = cfg_full.paths.data_out;

folders = {'QC', fullfile('QC', 'figures'), 'Configurations'};   % every step's .set goes straight into data_out

for i = 1:length(folders)
    p = fullfile(dataPath, folders{i});
    if ~isfolder(p)
        mkdir(p);
    end
end

end