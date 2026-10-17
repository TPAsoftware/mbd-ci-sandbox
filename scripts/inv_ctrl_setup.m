function root = inv_ctrl_setup()
%INV_CTRL_SETUP  Put the project folders on the MATLAB path and keep build files in work/.
%
%   root = inv_ctrl_setup() returns the repository root. Simulink cache files
%   (slprj, simulation targets) go to work/, which is not version controlled.

    root = fileparts(fileparts(mfilename('fullpath')));
    folders = {fullfile(root, 'model'), fullfile(root, 'model', 'components'), ...
               fullfile(root, 'model', 'util'), fullfile(root, 'params'), ...
               fullfile(root, 'scripts'), fullfile(root, 'tests', 'support')};
    addpath(folders{:});

    work = fullfile(root, 'work');
    if ~isfolder(work)
        mkdir(work);
    end
    Simulink.fileGenControl('set', 'CacheFolder', work, 'CodeGenFolder', work, 'createDir', true);
end
