function out = nm_preproc_generate_matrix_scaffold_code(configFile, outDir)
% nm_preproc_generate_matrix_scaffold_code  Generate standalone matrix-preprocessing scaffold files that replay a configured preprocessing pipeline.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

if nargin < 1 || isempty(configFile), error('Config file required.'); end
if nargin < 2 || isempty(outDir), outDir = fullfile(pwd,'NM_preproc_exports',['nm_preproc_matrix_scaffold_' datestr(now,'yyyymmdd_HHMMSS')]); end
if ~exist(outDir,'dir'), mkdir(outDir); end
cfgOut = fullfile(outDir,'nm_preproc_pipeline_config.json');
copyfile(configFile, cfgOut, 'f');
runFile = fullfile(outDir,'run_nm_matrix_preproc_scaffold.m');
readmeFile = fullfile(outDir,'README_matrix_scaffold.txt');
write_text(runFile, local_run_code());
write_text(readmeFile, local_readme());
out = struct('ok',true, ...
    'message','MATLAB matrix-level preprocessing scaffold exported.', ...
    'exportDir',outDir, ...
    'files',{{'run_nm_matrix_preproc_scaffold.m','nm_preproc_pipeline_config.json','README_matrix_scaffold.txt'}}, ...
    'runFile',runFile, 'configFile',cfgOut, 'readmeFile',readmeFile);
end

function write_text(path, txt)
% write_text  Write text artifacts used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.
% The function is intended to be readable as a scripting/API boundary: callers should rely on the documented inputs and returned report structures rather than editing internal NM fields directly.

fid = fopen(path,'w'); if fid < 0, error('Could not write %s', path); end
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, txt, 'char');
end

function txt = local_run_code()
% local_run_code  Perform the local run code step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

nl = newline;
L = { ...
'function out = run_nm_matrix_preproc_scaffold(Ytrain, Ytest, varargin)'
'% run_nm_matrix_preproc_scaffold'
'% Auto-generated NeuroMiner matrix-level preprocessing scaffold.'
'%'
'% This scaffold is close to executable. It is not the full NM backend runner.'
'% It exposes labels, covariates, subject-spatial branches and CV-bound trained'
'% preprocessing parameters so expert users can integrate the pipeline into'
'% custom ML code or external hyperparameter search loops.'
'%'
'% Usage:'
'%   out = run_nm_matrix_preproc_scaffold(Ytrain, []);'
'%   out = run_nm_matrix_preproc_scaffold(Ytrain, Ytest, "LabelTrain", labelTrain);'
'%'
'% Optional name/value arguments:'
'%   "LabelTrain"   vector or nTrain x nLabels matrix; default []'
'%   "LabelTest"    vector or nTest x nLabels matrix; default []'
'%   "CovarsTrain"  optional covariates; default []'
'%   "CovarsTest"   optional covariates; default []'
'%   "Context"      struct, e.g. Context.brainmask for imaging spatial ops'
''
'if nargin < 2, Ytest = []; end'
'p = inputParser;'
'addParameter(p,"LabelTrain",[]);'
'addParameter(p,"LabelTest",[]);'
'addParameter(p,"CovarsTrain",[]);'
'addParameter(p,"CovarsTest",[]);'
'addParameter(p,"Context",struct());'
'parse(p,varargin{:});'
''
'% Default NM.label handling placeholder. If you call this script from an NM'
'% workspace, uncomment and adapt trainInd/testInd as needed.'
'% if exist("NM","var") && isfield(NM,"label") && exist("trainInd","var")'
'%     labelTrain = NM.label(trainInd,:);'
'%     labelTest  = [];'
'%     if exist("testInd","var") && ~isempty(testInd), labelTest = NM.label(testInd,:); end'
'% else'
'    labelTrain = p.Results.LabelTrain;'
'    labelTest  = p.Results.LabelTest;'
'% end'
''
'thisDir = fileparts(mfilename("fullpath"));'
'cfgFile = fullfile(thisDir,"nm_preproc_pipeline_config.json");'
''
'[res, PP, report] = nm_preproc_matrix_scaffold_fit_transform(Ytrain, cfgFile, ...'
'    "Ytest", Ytest, ...'
'    "LabelTrain", labelTrain, ...'
'    "LabelTest", labelTest, ...'
'    "CovarsTrain", p.Results.CovarsTrain, ...'
'    "CovarsTest", p.Results.CovarsTest, ...'
'    "Context", p.Results.Context);'
''
'out = struct();'
'out.results = res;'
'out.PP = PP;'
'out.report = report;'
''
'% Example access:'
'%   Ytrain_branch1 = out.results.branches(1).Ytrain;'
'%   Ytest_branch1  = out.results.branches(1).Ytest;'
'%   PP_branch1     = out.PP.branches{1};'
'%   hyperTable     = out.PP.hyperparameters;'
'end'};
txt = strjoin(L,nl);
end

function txt = local_readme()
% local_readme  Perform the local readme step used by the surrounding scaffold workflow.
%
% It belongs to the generated-code/scaffold layer that makes UI configurations reproducible for power users and scripted workflows.

txt = sprintf(['NeuroMiner matrix-level preprocessing scaffold\n', ...
    '================================================\n\n', ...
    'This export is intentionally not the full NM backend runner. It loads the\n', ...
    'UI current_config.json, executes subject-specific spatial operations through\n', ...
    'nk_PerfSpatialChain/nk_PerfSpatFilt where possible, and then applies the\n', ...
    'configured CV-bound modular execute() chain.\n\n', ...
    'Labels: provide LabelTrain as a vector or nSubjects x nLabels matrix if the\n', ...
    'pipeline contains label-dependent modules.\n\n', ...
    'Hyperparameters/branches: branch outputs are explicit in out.results.branches.\n', ...
    'Expert users should decide how to select or cross-validate these branches.\n\n', ...
    'Use the full NM backend runner for exact CV2/CV1, binary, calibration, OOCV,\n', ...
    'synthetic-data, fusion, and complex spatial shelf semantics.\n']);
end
