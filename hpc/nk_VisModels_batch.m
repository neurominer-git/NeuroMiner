function nk_VisModels_batch(paramfile)

global NM

% Read parameter file
% ===========================
if ~exist(paramfile,'file')
    error([paramfile 'not found. Abort job!']);
end
fid = fopen(paramfile);
params = textscan(fid, '%s');
fclose(fid);

% Parse parameters in params
% ==================================================================================================================
NMpath              = params{1}{1};                   % NM root folder
datpath             = params{1}{2};                   % NM structure
jobdir              = params{1}{3};                   % job/output directory
analind             = str2double(params{1}{4});       % Analysis index to identify analysis for HPC
multiflag           = str2double(params{1}{5});       % multi flag in case MULTI-CLASS analysis has been conducted
saveparam           = str2double(params{1}{6});       % Save optimized parameters and models to disk for future use
loadparam           = str2double(params{1}{7});       % Load optimized parameters and models from disk instead
writeCV2flag        = str2double(params{1}{8});       % Write out CVR and sign-based consistency at the CV1 level
ovrwrt              = str2double(params{1}{9});
optparammaster      = params{1}{10};                  % Master file containing paths optimized preproc parameter files
optmodelsmaster     = params{1}{11};                  % Master file containing paths optimized models files
CV1flag             = str2double(params{1}{12});
lowmem              = str2double(params{1}{13});
CVRnorm             = str2double(params{1}{14});      % CVR param choosing SD or SEM
imagingflag         = str2double(params{1}{15});
spacedefimg_path    = params{1}{16};
curCPU              = str2double(params{1}{17});      % Current CPU to be used
numCPU              = str2double(params{1}{18});      % Number of CPUs in the submitted job
CV2x1               = str2double(params{1}{19});      % Range param for CV2 grid definition: Perm start CV2
CV2x2               = str2double(params{1}{20});      % Range param for CV2 grid definition: Perm end CV2
CV2y1               = str2double(params{1}{21});      % Range param for CV2 grid definition: Fold start CV2
CV2y2               = str2double(params{1}{22});      % Range param for CV2 grid definition: Fold end CV2
% <<< MODIFIED SECTION START
DecompMode          = str2double(params{1}{23});      % Back-projection mode
simCorrThresh       = str2double(params{1}{24});      % Similarity threshold for realignment
simCorrMethod       = params{1}{25};                  % Similarity method
CorrCompCutOff      = str2double(params{1}{26});      % Similarity cutoff for pruning
SelCompCutOff       = str2double(params{1}{27});      % Presence cutoff for pruning
% <<< MODIFIED SECTION END

if ~isdeployed
    addpath(NMpath);
end
warning('off','MATLAB:FINITE:obsoleteFunction')
fprintf('\nLoading NM structure: %s',datpath)
load(datpath);

% change analysis rootpath in batch mode
if isdeployed
    if jobdir(end) == '/'
        jobdir = jobdir(1:end-1);
    end
    for i=1:analind
        analind_i = i;
        parentdir = NM.analysis{1,analind_i}.parentdir;
        if parentdir(end) == '/'
            parentdir = parentdir(1:end-1);
        end
        NM.analysis{1,analind_i}.parentdir = jobdir;
        NM.analysis{1,analind_i}.rootdir = strrep(NM.analysis{1,analind_i}.rootdir,parentdir,jobdir);
        NM.analysis{1,analind_i}.logfile = strrep(NM.analysis{1,analind_i}.logfile,parentdir,jobdir);
        NM.analysis{1,analind_i}.paramdir = strrep(NM.analysis{1,analind_i}.paramdir,parentdir,jobdir);
        NM.analysis{1,analind_i}.paramfile = strrep(NM.analysis{1,analind_i}.paramfile,parentdir,jobdir);
        if isfield(NM.analysis{1,analind_i}, 'GDdims')
            NM.analysis{1,analind_i}.GDdims{1,1}.RootPath = strrep(NM.analysis{1,analind_i}.GDdims{1,1}.RootPath, parentdir, jobdir);
        end
    end
    if imagingflag % isfield(NM, 'brainmask') % this will not work for fusion analyses (since same space defining image will be used
        for m=1:size(NM.brainmask, 2)
            if ~isempty(NM.brainmask{m})
                NM.brainmask{1,m} = spacedefimg_path;
            end
        end
    end
end

assignin('base','NM',NM);

fprintf('\nThe updated path of the NM structure root dir is: %s',NM.analysis{1,analind}.rootdir)
fprintf('\n')

% %%%%%%%%%%%%%%%%%%%%%%%%% INITIALIZE NeuroMiner %%%%%%%%%%%%%%%%%%%%%%%%%
action = struct('addrootpath',1, ...
                'addDRpath',1, ...
                'addMIpath',1, ...
                'addLIBSVMpath',1, ...
                'addLIBLINpath',1, ...
                'addMikeRVMpath',1, ...
                'all',1);

nk_Initialize(action)

% %%%%%%%%%%%%%%%%%%%%%%%%% SETUP PARAMETERS %%%%%%%%%%%%%%%%%%%%%%%%
if saveparam == 1
    
    loadparam = 2;
    optparammaster = [];
    optmodelsmaster=[];

elseif saveparam == 2
    
    if ischar(optparammaster) && exist(optparammaster,'file')
        load(optparammaster,'featmat');
        optparammaster = featmat;
    else
        optparammaster = [];
    end
    if ischar(optmodelsmaster) && exist(optmodelsmaster,'file')
        load(optmodelsmaster,'featmat');
        optmodelsmaster = featmat;
    else
        optmodelsmaster = [];
    end
    
end

% <<< MODIFIED SECTION START
inp = struct('analind',       analind, ...
             'lfl',           1, ...
             'extraL',        [], ...
             'ovrwrt',        ovrwrt, ...
             'multiflag',     multiflag, ...
             'CV1',           CV1flag, ...
             'saveparam',     saveparam, ...
             'loadparam',     loadparam, ...
             'batchflag',     1, ...
             'writeCV2',      writeCV2flag, ...
             'analysis',      NM.analysis{analind}, ...
             'HideGridAct',   false, ...
             'lowmem',        lowmem, ...
             'CVRnorm',       CVRnorm, ...
             'DecompMode',    DecompMode, ...
             'simCorrThresh', simCorrThresh, ...
             'simCorrMethod', simCorrMethod, ...
             'CorrCompCutOff', CorrCompCutOff, ...
             'SelCompCutOff', SelCompCutOff ...
             );
% <<< MODIFIED SECTION END
                
inp.GridAct = nk_GenGridAct_batch(NM.analysis{analind}.params.cv, curCPU, numCPU, CV2x1, CV2x2, CV2y1, CV2y2);
inp.optpreprocmat = optparammaster;
inp.optmodelmat = optmodelsmaster;

nk_VisModelsPrep( 99, inp, 'NM:HPC:VISMODELS' );
