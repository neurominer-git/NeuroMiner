function nk_MLOptimizer_batch(paramfile)

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
% =======================================================================================================
NMpath        		= params{1}{1};					% NM root folder
datpath             = params{1}{2};					% NM structure
preprocmaster       = params{1}{3};                 % Optionally, path to PreprocMaster file
jobdir              = params{1}{4};                 % job/output directory
analind             = str2double(params{1}{5});		% Analysis index to identify analysis for HPC
ovrwrtfl            = str2double(params{1}{6}); 	% Runtime flag for MLOptimizer
curCPU              = str2double(params{1}{7});		% Current CPU to be used
numCPU              = str2double(params{1}{8});     % Number of CPUs in the submitted job
CV2x1               = str2double(params{1}{9});     % Range param for CV2 grid definition: Perm start CV2
CV2x2               = str2double(params{1}{10});     % Range param for CV2 grid definition: Perm end CV2
CV2y1               = str2double(params{1}{11});	% Range param for CV2 grid definition: Fold start CV2
CV2y2               = str2double(params{1}{12});	% Range param for CV2 grid definition: Fold end CV2

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
inp = struct('analind',			analind,...
				'gdmat',		[], ...
				'gdanalmat', 	[], ...
				'varstr', 		[], ...
				'concatfl', 	[], ...
				'ovrwrt', 		ovrwrtfl, ...
				'update', 		true, ...
                'HideGridAct',  false, ...
                'batchflag',    true);
				
inp.GridAct = nk_GenGridAct_batch(NM.analysis{analind}.params.cv, curCPU, numCPU, CV2x1, CV2x2, CV2y1, CV2y2);                       

inp = nk_GetAnalModalInfo_config(NM, inp);

if ischar(preprocmaster) && exist(preprocmaster,'file')
    preprocmat = load(preprocmaster); 
    inp.lfl = 2;
    inp.preprocmat = preprocmat.featmat;
else
    inp.preprocmat = []; inp.lfl = 1;
end
                                
nk_MLOptimizerPrep(7, inp, 'NM:HPC:MLOPTIMIZER');
            
