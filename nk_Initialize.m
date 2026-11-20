function nk_Initialize(action, varargin)
% =========================================================================
% nk_Initialize(action)
% =========================================================================
% startup script for NeuroMiner
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 09/2026

global NMinfo NM CALIBAVAIL OOCVAVAIL SPMAVAIL FSAVAIL JUAVAIL OCTAVE

NMinfo.info.name    = 'NeuroMiner';
if OCTAVE
    NMinfo.info.ver     = sprintf('v2.0 | OLORIN [OCTAVE %s]', OCTAVE_VERSION);
else
    matver = ver('matlab');
    NMinfo.info.ver     = sprintf('v2.0 | OLORIN [%s %s]', matver.Name, matver.Release);
end
NMinfo.info.author  = 'N. Koutsouleris, C. Vetter, A. Wiegand, L. Hahn, S. Mena';
NMinfo.info.affil   = 'Section for Precision Psychiatry / Artificial Intelligence in Mental Health (AIM)';
NMinfo.info.dep     = 'Dept. of Psychiatry and Psychotherapy / IoPPN, Department of Psychosis Studies';
NMinfo.info.inst    = 'Ludwig-Maximilians-University / King''s College London';
NMinfo.info.datever = '11/2026';
NMinfo.info.timestamp = datetime("today");
NMinfo.info.email   = 'nm@pronia.eu';
if ~isempty(varargin)
    NM = varargin{1};
elseif evalin('base','exist(''NM'',''var'')') == 1
    NM = evalin('base','NM');
else
    NM = [];
end
CALIBAVAIL          = false;
OOCVAVAIL           = false;

clc
fprintf('>>> Initializing NeuroMiner %s\n',  NMinfo.info.ver);
matpaths = path;

if isunix, sep = ':'; else, sep = ';'; end
try
  matpaths = nk_strsplit(sep,matpaths);
catch
  matpaths = nk_strsplit(matpaths, sep);
end
if exist(which('nm.m'),'file')
    neurominerpath = fileparts(which('nm.m'));
else
    neurominerpath = fileparts(which('nm.p'));
end

if nargin < 2
	action.all=1;
end

% Add root path
fprintf('\nRoot path is %s.\n',neurominerpath)
defs.path = neurominerpath;
if action.addrootpath || action.all, addpath(defs.path); end

% Initialise SPM directory
SPMAVAIL = false; FSAVAIL=false;
imaging_init_path = fullfile(neurominerpath,'imaging_init.mat');
if ~isdeployed
    [spmrootdir, fsrootdir, judir] = nk_ImagingInit(neurominerpath, imaging_init_path);
    if ischar(spmrootdir) && exist(spmrootdir,'dir')
        SPMAVAIL = true;
        if ~checkpaths(matpaths,spmrootdir)
            addpath(spmrootdir);
            spm('Defaults','pet')
            fprintf('.');
        end
    end
    if ischar(fsrootdir) && exist(fsrootdir,'dir')
        FSAVAIL = true;
        if ~checkpaths(matpaths,fsrootdir)
            addpath(fsrootdir);
            fprintf('.');
        end

    end
    if ischar(judir) && exist(judir,'dir')
        JUAVAIL = true;
        if ~checkpaths(matpaths,judir)
            addpath(judir);
            fprintf('.');
        end

    end
else
    if which('spm'), SPMAVAIL=true; spm('Defaults','pet'); FSAVAIL = true; JUAVAIL=true; end
end

% Initialize MEX file repository
if ~checkpaths(matpaths,fullfile(defs.path,'cfiles'))
    addpath(fullfile(defs.path,'cfiles'));
    fprintf('.');
end

if action.all

        % Configuration subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'config'))
            addpath(fullfile(defs.path,'config'));
            fprintf('.');
            addpath(fullfile(defs.path,'config/data_import'));
            fprintf('.');
        end

        % Feature generation subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'FeatGen'))
            addpath(genpath(defs.path));
            addpath(fullfile(defs.path,'FeatGen/IMRelief')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/GFlip')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/Simba')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/RSS')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/RGS')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/FEAST')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/FEAST/FSToolbox')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/FEAST/MIToolbox')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/MRMR')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/SVM')); fprintf('.');
            addpath(fullfile(defs.path,'FeatGen/SA')); fprintf('.');
        end

        % Preprocessing subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'preproc'))
            addpath(fullfile(defs.path,'preproc')); %fprintf('.');
            addpath(fullfile(defs.path,'preproc/mi')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/combat')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/drtoolbox'));
            addpath(fullfile(defs.path,['preproc/drtoolbox' filesep 'techniques'])); fprintf('.');
            addpath(fullfile(defs.path,'preproc/drtools'));fprintf('.');
            addpath(fullfile(defs.path,'preproc/drrobust'));fprintf('.');
            addpath(fullfile(defs.path,'preproc/nmfv1_4')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/NeNMF')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/NMF_Library_v2')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/NMF_Soteiras')); fprintf('.');
            addpath(fullfile(defs.path,'preproc/SparsePLS')); fprintf('.');
        end

        % Train & Predict functions subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict'))
            addpath(fullfile(defs.path,'trainpredict')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/libsvm-weights-3.12/matlab')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/libsvm-mat-2.9-1')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/liblinear-2.44/')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/liblinear-2.47/')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/LIBSVM-Plus-2.89')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/mRVMs')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/MRVR'));fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/SB2_Release_200'));fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/elm_linear'));fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/blogreg')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/matLearn2016'));
            addpath(genpath(fullfile(defs.path,'trainpredict/matLearn2016'))); fprintf('.');
            addpath(genpath(fullfile(defs.path,'trainpredict/glmnet'))); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/weibull_cox_v_1_1_4')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/BBQ')); fprintf('.');
            addpath(fullfile(defs.path,'trainpredict/popfeatsel')); fprintf('.');
        end

        if ~checkpaths(matpaths,fullfile(defs.path,'gridsearch'))
            addpath(fullfile(defs.path,'gridsearch')); fprintf('.');
        end

        % Visualization subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'visual'))
            addpath(fullfile(defs.path,'visual')); fprintf('.');
        end

        % MLI subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'interpretable'))
            addpath(fullfile(defs.path,'interpretable')); fprintf('.');
        end

        % GUI subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'gui'))
            addpath(fullfile(defs.path,'gui')); fprintf('.');
            addpath(fullfile(defs.path,'gui/export_fig')); fprintf('.');
        end

        % Ensemble learning subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'ensemble'))
            addpath(fullfile(defs.path,'ensemble'));fprintf('.');
        end

         % Utilities subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'util'))
            addpath(fullfile(defs.path,'util')); fprintf('.');
            addpath(fullfile(defs.path,'util/freesurfer')); fprintf('.');
        end
        % Atlas subdirectory
        if ~checkpaths(matpaths,fullfile(defs.path,'atlas'))
            addpath(fullfile(defs.path,'atlas'));
            fprintf('.');
        end
end

if action.addDRpath || action.all

    % Preprocessing subdirectory

    % Path of dimensionality reduction toolbox
    if ~checkpaths(matpaths,fullfile(defs.path,'preproc/drtoolbox'))
        addpath(fullfile(defs.path,'preproc/drtoolbox'));
        addpath(fullfile(defs.path,['preproc/drtoolbox' filesep 'techniques'])); fprintf('.');
    end

    if ~checkpaths(matpaths,fullfile(defs.path,'preproc/drtools'))
        addpath(fullfile(defs.path,'preproc/drtools')); fprintf('.');
    end

    if ~checkpaths(matpaths,fullfile(defs.path,'preproc/drrobust'))
        addpath(fullfile(defs.path,'preproc/drrobust')); fprintf('.');
    end

    % Path of dimensionality reduction toolbox
    if ~checkpaths(matpaths,fullfile(defs.path,'preproc/nmfv1_4'))
        addpath(fullfile(defs.path,'preproc/nmfv1_4')); fprintf('.');
    end

end

if action.addMIpath
   
    if ~checkpaths(matpaths,fullfile(defs.path,'preproc/mi'))
        addpath(fullfile(defs.path,'preproc/mi')); fprintf('.');
    end
  
end

if action.addLIBSVMpath

    if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict/libsvm-weights-3.12/matlab'))
        addpath(fullfile(defs.path,'trainpredict/libsvm-weights-3.12/matlab')); fprintf('.');
    end
    if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict/libsvm-mat-2.9-1'))
        addpath(fullfile(defs.path,'trainpredict/libsvm-mat-2.9-1'));fprintf('.');
    end
    if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict/LIBSVM-Plus-2.89'))
        addpath(fullfile(defs.path,'trainpredict/LIBSVM-Plus-2.89'));fprintf('.');
    end
end

if action.addLIBLINpath
   
    if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict/liblinear-2.1/matlab'))
       addpath(fullfile(defs.path,'trainpredict/liblinear-2.1/matlab')); fprintf('.');
    end
end

if action.addMikeRVMpath
   
    if ~checkpaths(matpaths,fullfile(defs.path,'trainpredict/SB2_Release_200'))
        addpath(fullfile(defs.path,'trainpredict/SB2_Release_200'));fprintf('.');
    end
end

if ~isempty(NM) && ~isstruct(NM)
    error('The NM workspace variable does not have the correct format and thus cannot be not recognized. Clear the variable and start again!')
end

NM2path = fullfile(defs.path,'NM2');
if exist(NM2path,"dir")
    if ~checkpaths(matpaths,NM2path)
        fprintf('\nAdding NM2 codebase to the MATLAB path ...\n')
        addpath(genpath(fullfile(defs.path,'NM2')));
        NM.defs.NM2_added = true;
    end
else
    NM.defs.NM2_added = false;
end

NM.defs.paths = defs.path;
NM.defs.atlas_path = fullfile(defs.path,'atlas');
NM.defs.NM_ver = NMinfo.info.ver;

if ~isfield(NM.defs,'ver'), NM.defs.ver = ver; end
if ~isfield(NM.defs,'computer'), NM.defs.computer = computer; end

% -------------------------------------------------------------------------
% Hardware / execution-environment provenance
% -------------------------------------------------------------------------
if ~isfield(NM.defs,'hardware') || isempty(NM.defs.hardware)

    HW = struct();

    HW.platform       = computer;
    HW.architecture   = computer('arch');
    HW.matlab_version = version;
    HW.matlab_release = version('-release');

    if ispc
        HW.os = nkSysInfo('ver');

        HW.cpu = nkSysInfo( ...
            'powershell -NoProfile -Command "(Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)"');

        HW.logical_processors = str2double(nkSysInfo( ...
            'powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors"'));

        ramBytes = str2double(nkSysInfo( ...
            'powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory"'));

    elseif ismac
        osver = nkSysInfo('sw_vers -productVersion');
        HW.os = ['macOS ' osver];

        HW.cpu = nkSysInfo( ...
            'sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model');

        HW.logical_processors = str2double( ...
            nkSysInfo('sysctl -n hw.logicalcpu'));

        ramBytes = str2double( ...
            nkSysInfo('sysctl -n hw.memsize'));

    elseif isunix
        HW.os = nkSysInfo( ...
            '. /etc/os-release 2>/dev/null; printf "%s" "$PRETTY_NAME"');

        HW.cpu = nkSysInfo( ...
            'lscpu | sed -n ''s/^Model name:[[:space:]]*//p'' | head -1');

        HW.logical_processors = str2double( ...
            nkSysInfo('nproc'));

        ramBytes = str2double(nkSysInfo( ...
            'awk ''/MemTotal/ {printf "%.0f", $2*1024}'' /proc/meminfo'));

    else
        HW.os                 = 'unknown';
        HW.cpu                = 'unknown';
        HW.logical_processors = NaN;
        ramBytes              = NaN;
    end

    if isfinite(ramBytes)
        HW.ram_GB = ramBytes / 1024^3;
    else
        HW.ram_GB = NaN;
    end

    % MATLAB-visible compute GPU; no dependency if PCT/GPU support is absent.
    HW.gpu = {};
    if exist('gpuDeviceCount','file') == 2 && exist('gpuDevice','file') == 2
        nGPU = gpuDeviceCount;
        HW.gpu = cell(1,nGPU);
        for g = 1:nGPU
            try
                G = gpuDevice(g);
            catch
                G.Name = [];
            end
            HW.gpu{g} = G.Name;
        end
    end

    NM.defs.hardware = HW;
end
if ~isfield(NM.defs,'import_finished'), NM.defs.import_finished=false;end

% _______________________________________
function [fnd, pathx] = checkpaths(matpaths,pathx,findmode)

fnd = 0;
if ~exist('findmode', 'var') || isempty(findmode)
    findmode = 1;
end
for i=1:length(matpaths)
    switch findmode
        case 1
            if strcmp(matpaths{i}, pathx)
                pathx = matpaths{i};
                fnd=1;
                break
            end
        case 2
            if strfind(matpaths{1}, pathx)
                pathx = matpaths{i};
                fnd=1;
                break
            end
    end
end

function value = nkSysInfo(cmd)

[status,value] = system(cmd);

if status ~= 0
    value = 'unavailable';
else
    value = strtrim(value);
    if isempty(value)
        value = 'unavailable';
    end
end

