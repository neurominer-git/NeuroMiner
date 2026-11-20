function varargout = nm(varargin)
%
% NeuroMiner Startup and Main Interface Function
%
% *******************************************
% ****\                                 /****
% *****\     ~~~~~~~~~~~~~~~~~~~~~     /*****
% ******\     N e u r o M i n e r     /******
% *******\   ~~~~~~~~~~~~~~~~~~~~~   /*******
% *******/                           \*******
% ******/     pattern recognition     \******
% *****/      for neurodiagnostic      \*****
% ****/           applications          \****
% ***/                                   \***
% *******************************************
%
% type 'nm <varargin>' at the MATLAB command line to start the program
% <varargin> could be e.g.
% nm nosplash
% nm nosplash expert
% nm expert
% nm nosplash expert ui NM_struct
% nm nosplash expert ui browser-edge NM_struct
% nm ui html-relay
%
% A named NM structure argument is resolved from the MATLAB base workspace
% and written back to the same variable when NeuroMiner closes. Supported
% UI targets are browser-default, browser-edge, browser-chrome,
% browser-firefox and html-relay.
% =========================================================================
% nm.m implements three different analysis stages;
%
% (1) Data import: Allows the user to add, modify and delete modalities from
%     the NM workspace. Data can be input into NM from a variety of
%     sources. Currently, the user can choose among 3D neuroimaging data
%     (.img/.nii, .nii.gz/.img.gz and .mgh/.mgz formats are supported.),
%     MATLAB 2D-matrix data, and table-based /text-based formats
%     (.xlsx/.xls,.txt/.csv). For latter data formats a matrix inspector
%     allows the user to visualize the matrix, to select features and cases
%     based on descriptive statistics criteria.
%
% (2) Model generation and cross-validation: Enables the user to define a
%     hyperparameter space for the optimization of complex machine learning
%     pipelines. The model generation and validation process is split into
%     three steps - preprocessing, model training and visualization. These
%     steps are completely wrapped into a repeated, nested cross-validation
%     structure that is defined by the user. In addition, the user can run
%     NM's intepretable ML module to compute the input features' saliencies
%     for the individual predictions obtained at the CV2 level. NM currently
%     provides classification and regression models. Classification can be
%     conducted for binary and multi-group problems, with the latter being
%     always decomposed into one-vs-one or one-vs-all binary classifiers.
%     Currently, a real multi-group learning process is not implemented,
%     but it is planned for a future release. Results can be inspected with
%     the NM Results Viewer.
%
% (3) Application to independent data: Allows the user to apply models
%     trained in (2) to new datasets, which have to comply with the input
%     settings defined in (1). The entire set of models obtained
%     from the cross-validation setup defined in (1) and trained in (2)
%     will be applied to these new data. In addition, the user can use NM's
%     interpretation module to gain insight into which features determined
%     the individual prediction most.
%
% Each stage has to be completed in order to move to the next stage
% User can choose to use NM in expert mode by invoking nm with the 'expert'
% option.
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 06/2026
global EXPERT DEV OCTAVE NM UI

if nargout > 1
    error('nm:TooManyOutputs', 'nm returns at most one updated NM structure.');
end
startup = localParseStartupArguments(varargin);
if startup.hasNMInput && isempty(startup.writeBackVariable) && nargout == 0
    error('nm:OutputRequired','A structure passed by value requires an NM output. Supply a workspace variable name for automatic write-back.');
end
EXPERT = startup.expert;
OCTAVE = startup.octave;
DEV = startup.dev;
init = struct('all', 1, 'addrootpath', 0, 'addDRpath', 0, 'addLIBSVMpath', 0, 'addMIpath', 0, 'addLIBLINpath', 0, 'addMikeRVMpath', 0);
if startup.hasNMInput
    baseNM = evalin('base','whos(''NM'')');
    if ~strcmp(startup.writeBackVariable,'NM') && ~isempty(baseNM) && baseNM.global
        error('nm:GlobalNMConflict','Base-workspace NM is global and cannot be isolated from a separately named NM input.');
    end
    nk_Initialize(init, startup.NMInput);
else
    nk_Initialize(init);
end
UI = struct('enabled',startup.ui,'mode','cli','appUI',startup.ui, ...
    'bridgeEnabled',startup.ui,'devMode',DEV,'source','legacy_cli', ...
    'uiTarget',startup.uiTarget,'sessionTmpDir','','writeBackReady',~startup.ui);
if startup.ui, UI.mode = 'browser'; UI.source = 'workbench'; end

if ~startup.nosplash && ~startup.ui, splash('splash','png',1500); end
obj = onCleanup(@()QuitNeuroMiner(startup.writeBackVariable, startup.targetExisted)); 

% In development mode, the browser-based NM 2.0 workbench is the main
% interface. The legacy command-line menu below is retained for ordinary
% non-UI operation only and should not be entered by `nm dev`.
if UI.appUI
    [~, startupSplashToken] = fileparts(tempname);
    ctx = struct('materializeTemplateOnClose', true, ...
        'uiTarget', UI.uiTarget, ...
        'showStartupSplash', ~startup.nosplash, ...
        'startupSplashToken', startupSplashToken);
    NM = NMAppUI.openWorkbench(NM, [], ctx, [], true);
    UI.writeBackReady = true;
    if nargout == 1, varargout{1} = localCleanSessionNM(NM); end
    return
end

% Loop into the main interface as long as the user does not decide to quit
% or an error occurs.
act = []; ERR=[];
while ~strcmp(act,'quit') && isempty(ERR)
    [ERR, act] = nm_interface;
end

% Perform error handling if needed
if ~isempty(ERR)
    nk_SetupGlobalVariables(NM,'clear')
    fprintf('\n========================================================== \n');
    fprintf('>>> OOOops... NM crashed :-(( <<<');
    fprintf('\nError: %s\nStack:', ERR.message);
    for i=1:numel(ERR.stack)
        fprintf('\nIn %s, name: %s, line: %g.', ...
            ERR.stack(i).file,ERR.stack(i).name,ERR.stack(i).line)
        switch ERR.stack(i).name
            case {'nk_PreprocessPrep','nk_MLOptimizerPrep','nk_VisModelsPrep', 'nk_MLInterpreterPrep', 'nk_OOCVPrep'}
                if isfield(NM,'runtime')
                    nk_NMLogFileManager('add_entry', NM, NM.analysis{NM.runtime.curanal}, 'nm', ERR);
                end
        end
    end
    fprintf('\n>>> NM structure secured to MATLAB workspace.')
    fprintf('\n\nPlease copy the above message and email it with a description to: ')
    fprintf('\nnikolaos.koutsouleris@med.uni-muenchen.de\n')
    if isfield(NM,'runtime'), NM=rmfield(NM,'runtime'); end
end

if nargout == 1, varargout{1} = localCleanSessionNM(NM); end
end

function [ERR, action] = nm_interface
global NM BATCH NMinfo
ERR = [];

if ~isempty(NM) && ~isstruct(NM)
    error('The NM workspace variable does not have the correct format and thus cannot be not recognized. Clear the variable and start again!')
else
    NMfields = fieldnames(NM); action = 'quit';
end

try

    menutitle = 'MAIN INTERFACE';

    % Check NM status and define current NM mode based on status
    [s, paramstr] = nk_GetNMStatus(NM);

    if ~s.import_finished
        NMinfo.clback = rgb('HoneyDew');
        NMinfo.cllogo = rgb('ForestGreen');
        NMinfo.clmenu = rgb('DarkGreen');
        mn_str = 'Load data for model discovery and cross-validation|'; mn_act = 1;
        menutitle = [menutitle ' [ DATA INPUT MODE ]'];
    else
        switch NM.modeflag
            case 'classification'
                mdltypestr = 'classifiers';
            case 'regression'
                mdltypestr = 'regressors';
        end

        switch s.setup_ok

            case 1 % Parameter definitions ok

                if ~s.analyses_locked
                    menutitle = [menutitle ' [ MODEL DISCOVERY MODE ]'];
                    mn_str = 'Inspect data used for model discovery and cross-validation|'; mn_act = 8;
                    mn_str = [ mn_str 'Set up NM parameter workspace|' ]; mn_act = [ mn_act 2 ];
                    if s.analyses_exist
                        mn_str = [ mn_str ...
                            'Manage analyses|' ...
                            'Preprocess features|' ...
                            'Train supervised ' mdltypestr '|'];
                        mn_act = [mn_act 3:5];
                    else
                        mn_str = [ mn_str 'Initialize analyses|'];
                        mn_act = [mn_act 3];
                    end

                    if s.analyses_ready
                        if s.analyses_nondeterministic
                            mn_str = [mn_str 'Visualize ' mdltypestr ' (non-deterministic analysis - NM may crash)|'];
                        else
                            mn_str = [mn_str 'Visualize ' mdltypestr '|'];
                        end
                        mn_str = [mn_str ...
                            'Interpret predictions of ' mdltypestr ' in discovery data|' ...
                            'Open NM Results Viewer (cross-validation results)|' ...
                            'Save model parameters to disk|'];
                        mn_act = [mn_act 6 18 7 19];
                    end

                    if s.analyses_completed
                        mn_str = [ mn_str  'Lock analyses and start NM application mode|' ]; mn_act = [ mn_act 9 ];
                    end

                else
                    mn_str = 'Update analyses'' root paths'; mn_act = 17;
                    mn_str = [ mn_str '|Load data for model application' ]; mn_act = [mn_act 1 ];
                    if s.oocv_data_ready
                        mn_str = [ mn_str '|Set up parameters for model application' ]; mn_act = [ mn_act 2 ];
                        if s.oocv_anal_ready
                            mn_str = [ mn_str ...
                                '|Apply ' mdltypestr ' to independent data' ...
                                '|Interpret predictions of ' mdltypestr ' in independent data'];
                            mn_act = [ mn_act 10 18];
                        end
                    end
                    if s.oocv_anal_ready
                        mn_str = [mn_str '|Open NM Results Viewer (cross-validation & independent test results)'];
                    else
                        mn_str = [mn_str '|Open NM Results Viewer (cross-validation results)'];
                    end
                    mn_act = [mn_act 7 ];
                    if ~isfield(NM.defs,'data_scrambled') || ~NM.defs.data_scrambled
                        menutitle = [menutitle ' [ MODEL APPLICATION MODE ]'];
                        mn_str = [mn_str '|Shred input data in NM structure (external validation)']; mn_act = [ mn_act 16 ];
                    else
                        menutitle = [menutitle ' [ MODEL EXPORT MODE ]'];
                    end
                end

            case 0
                mn_str = ['Inspect data used for model discovery and cross-validation' ...
                    '|Set up NM parameter workspace' ];
                mn_act = [8 2];
        end

    end

    nk_PrintLogo(true)

    fprintf('\nCurrently working in: %s',pwd)
    if ~s.setup_ok && s.import_finished
        fprintf('\n\n')
        fprintf('Parameter setup not complete! \n')
        if iscell(paramstr), paramstr = char(paramstr); end
        for i=1:size(paramstr,1)
            fprintf('%s \n',paramstr(i,:));
        end
    end

    if isscalar(NMfields) && strcmp(NMfields{1},'defs')
        mn_str = [ mn_str ...
            '|Load NeuroMiner structure' ...
            '|Change working directory' ...
            '|Investigate sample size' ...
            '|Utilities'];
        mn_act = [ mn_act 11, 13, 99, 15 ];
    else
        mn_str = [ mn_str ...
            '|Load NeuroMiner structure' ...
            '|Save NeuroMiner structure' ...
            '|Change working directory' ...
            '|Investigate sample size' ...
            '|Utilities'];
        mn_act = [ mn_act 11 12 13 99 15 ];
    end

    mn_sel = nk_input(menutitle,0,'mq',mn_str,mn_act);

    mn_opt = {'loaddata', ...
        'config', ...
        'initanal', ...
        'preproc', ...
        'mlopt', ...
        'visual', ...
        'disptrain', ...
        'inspect', ...
        'lock', ...
        'oocv', ...
        'loadmat', ...
        'savemat', ...
        'changepwd', ...
        'help', ...
        'utilities', ...
        'export', ...
        'update', ...
        'interpret', ...
        'savemodels'};

    switch mn_sel
        case 0
            action = 'quit';
            return
        case 20
            action = 'disptrain_new';
        case 99 %sample size simulation
            action = 'simulateML';
        otherwise
            action = mn_opt{mn_sel};

    end

    switch action

        case 'loaddata'

            if s.analyses_locked
                NM = nk_OOCVDataIO_config(NM, 1,'MAIN');
            else
                act = Inf;
                while act>0
                    [NM, act] = nk_DataIO_config(NM, 'MAIN');
                end
            end

        case 'inspect'

            nk_SelectVariateIndex(NM,1,[],0);
            TrCV_containers = find(cellfun(@ischar, NM.Y));
            if ~isempty(TrCV_containers)
                NewRootDir = nk_DirSelector('Update paths to discovery data containers'' root paths');
                for i=1:numel(TrCV_containers)
                    [~, nam, ext] = spm_fileparts(NM.Y{TrCV_containers(i)});
                    NM.Y{TrCV_containers(i)} = fullfile(NewRootDir,[nam ext]);
                end
            end
            nk_input('Press enter to return to the main menu',0,'sq');

        case 'config'
            if s.oocv_data_ready && s.analyses_locked
                act = 1; while act>0, [NM.TrainParam, act] = nk_OOCV_config(NM.TrainParam); end
            else
                act = 1; varind = []; while act>0, [act, varind] = nk_TrainClass_config([], varind,'MAIN'); end
            end

        case 'initanal'
            t_act = 'loop'; A = []; while ~strcmp(t_act,'BACK'), [t_act, NM, A] = nk_InitAnalysisPrep(NM, A, 'MAIN INTERFACE >> ANALYSIS MANAGER'); end

        case 'preproc'
            BATCH = false; p = []; act = 1; analind = []; GridAct = []; while act>0, [act, analind, p, GridAct] = nk_PreprocessPrep(act, analind, GridAct, p, 'MAIN' ); end

        case 'mlopt'
            if isfield(NM,'analysis'), act = 1;  inp = []; while act>0, [act, inp] = nk_MLOptimizerPrep(act, inp, 'MAIN INTERFACE >> ML TRAINING MODULE'); end; end
            delete(findobj('Name','NM Optimization Status Viewer'));

        case 'disptrain'
            NM_Results_Viewer('Analysis',1, 'NM', NM);

        case 'lock'
            NM.defs.analyses_locked = nk_input('Do you want to finish the model discovery phase',0,'yes|no',[1,0],2);

        case 'visual'
            if isfield(NM,'analysis')
                inp = []; act = 1; while act>0, [act, inp] = nk_VisModelsPrep(act, inp, 'MAIN INTERFACE >> VISUALIZE MODELS'); end
            end

        case 'interpret'
            if isfield(NM,'analysis')
                if isfield(NM.defs,'analyses_locked') && NM.defs.analyses_locked
                    titstr = 'MAIN INTERFACE >> INTERPRET MODELS'' PREDICTIONS [application mode]';
                else
                    titstr = 'MAIN INTERFACE >> INTERPRET MODELS'' PREDICTIONS [discovery mode]';
                end
                inp = []; act = 1; while act>0, [act, NM, inp] = nk_MLInterpreterPrep(NM, act, inp, titstr); end
            end

        case 'oocv'
            if isfield(NM,'analysis')
                inp = []; act = 1;
                while act>0
                    [act, NM, inp ] = nk_OOCVPrep(NM, act, inp, 'MAIN INTERFACE >> APPLY MODELS TO NEW DATA');
                end
            end

        case 'loadmat'
            NM = loadmat(NM);
            NMx = NM;
            assignin('base', 'NM', NMx);

        case 'savemat'
            savemat(NM);

        case 'changepwd'
            directoryname = uigetdir(pwd, 'Pick a new working directory');
            if directoryname, cd(directoryname); end

        case 'utilities'
            nk_Utilities

        case 'export'
            scrambleflag = nk_input('Are you sure you want to shred all input features?',0,'yes|no',[1,0],2);
            if scrambleflag
                for i=1:numel(NM.Y)
                    if ischar(NM.Y{i})
                        m = numel(NM.cases); n = NM.datadescriptor{i}.input_settings.Ydims;
                    else
                        [m,n] = size(NM.Y{i});
                    end
                    NM.Y{i} = rand(m,n);
                end
                NM.defs.data_scrambled = 1;
                savemat(NM);
                msgbox('Data successfully scrambled to generate anonymized NM structure!')
            end

        case 'update'
            complvec = []; for z=1:numel(NM.analysis), if NM.analysis{z}.status, complvec = [ complvec z ]; end; end
            t_act = 1; brief = 1; analind = 1; showmodalvec = [];
            while t_act>0
                [t_act, analind, ~, showmodalvec , brief] = nk_SelectAnalysis(NM, 0, 'MAIN INTERFACE >> UPDATE ANALYSES ROOT DIRECTORIES ', analind, [], 1, showmodalvec, brief);
            end
            if ~isempty(analind)
                analind = complvec(analind);
            else
                analind = complvec;
            end
            newdir = nk_DirSelector('Update analyses'' root paths');

            NM = nk_UpdateRootPaths(NM, analind, newdir);

        case 'simulateML'
            if s.analyses_locked
                % use information from your sample TO DO
                %simulationRes = simulate_sampleSize(NM);
            else
                inp = []; act = 1;
                while act > 0
                    [act, NM, inp] = cv_estimate_samplesize_config(NM, act, inp, 'SAMPLE SIZE ESTIMATION (PRE/POSTHOC)');
                end
            end

        case 'savemodels'
            if isfield(NM,'analysis')
                inp = []; act = 1;
                while act > 0
                    [act, NM, inp] = cv_ExportModelsPrep(NM, act, inp, "EXPORT MODEL PARAMETERS");
                end
            end
    end

catch ERR
    return
end

end

function NM = loadmat(NM)

[filename, pathname] = uigetfile('*.mat', 'Pick a NeuroMiner structure file');

if ~isequal(filename,0) && ~isequal(pathname,0)
    NM = [];
    fprintf('\nLoading %s ... please wait',filename)
    load(fullfile(pathname,filename))
    if ~exist('NM','var')
        retryflag = ...
            nk_input([filename ' does not contain a valid NeuroMiner structure! Retry ?'], ...
            0, 'yes|no',[1,0],1);
        if retryflag, loadmat, end
    else
        cd(pathname)
    end
end

end

function savemat(NM)

[filename, pathname] = uiputfile('*.mat', 'Save NeuroMiner structure file');

if isfield(NM.defs,'JTextArea')
    NM = nk_InitNMwindowColors(NM, [1 1 1 ]);
    NM.defs = rmfield(NM.defs,'JTextArea');
end
if ~isequal(filename,0) && ~isequal(pathname,0)
    fprintf('\nSaving %s ... please wait',filename)
    save(fullfile(pathname,filename),'NM','-v7.3')
end

end


function startup = localParseStartupArguments(args)
startup = struct( ...
    'nosplash', false, ...
    'expert', false, ...
    'octave', false, ...
    'dev', false, ...
    'ui', false, ...
    'uiTarget', 'browser-default', ...
    'hasNMInput', false, ...
    'NMInput', struct(), ...
    'writeBackVariable', 'NM');
uiTargetSpecified = false;

for i = 1:numel(args)
    value = args{i};
    if isstruct(value)
        if startup.hasNMInput
            error('nm:MultipleNMInputs', ...
                'Specify exactly one NM structure input.');
        end
        startup.hasNMInput = true;
        startup.NMInput = value;
        startup.writeBackVariable = '';
        continue
    end
    if ~(ischar(value) || (isstring(value) && isscalar(value)))
        error('nm:UnsupportedStartupArgument', ...
            'Startup argument %d has unsupported class %s.', i, class(value));
    end

    token = strtrim(char(value));
    option = lower(token);
    switch option
        case 'nosplash'
            startup.nosplash = true;
        case 'expert'
            startup.expert = true;
        case 'octave'
            startup.octave = true;
        case 'dev'
            startup.dev = true;
        case 'ui'
            startup.ui = true;
        case {'browser-default','browser-edge','browser-chrome','browser-firefox','html-relay'}
            if uiTargetSpecified && ~strcmp(startup.uiTarget, option)
                error('nm:MultipleUITargets', ...
                    'Specify exactly one UI target.');
            end
            startup.uiTarget = option;
            uiTargetSpecified = true;
        otherwise
            if ~isvarname(token)
                error('nm:UnknownStartupArgument', ...
                    'Unknown NeuroMiner startup argument: %s', token);
            end
            if startup.hasNMInput
                error('nm:MultipleNMInputs','Specify exactly one NM structure input.');
            end
            if evalin('base',sprintf('exist(''%s'',''var'')',token)) ~= 1
                error('nm:NMInputNotFound','The base-workspace variable %s does not exist.',token);
            end
            inputNM = evalin('base',token);
            assert(isstruct(inputNM),'nm:InvalidNMInput', ...
                'The base-workspace variable %s must contain a struct.',token);
            startup.hasNMInput = true;
            startup.NMInput = inputNM;
            startup.writeBackVariable = token;
    end
end

if uiTargetSpecified && ~startup.ui
    error('nm:UITargetRequiresUI', ...
        'A browser-* or html-relay target requires the ui startup option.');
end

startup.targetExisted = ~isempty(startup.writeBackVariable) && ...
    evalin('base',sprintf('exist(''%s'',''var'')',startup.writeBackVariable)) == 1;
end


function cleanNM = localCleanSessionNM(NM)
cleanNM = NM;
if isstruct(cleanNM) && isfield(cleanNM,'runtime')
    cleanNM = rmfield(cleanNM,'runtime');
end
end

function QuitNeuroMiner(writeBackVariable, targetExisted)
global NM UI

fprintf('\n'); %clc;
fprintf('Good Bye... \n');
if UI.bridgeEnabled
    try
        NMUIBridgeTools.killActiveBridges('NeuroMiner was interrupted from the MATLAB command window. The NM2 UI bridge is shutting down.');
    catch ME
        fprintf('\n[nm] Could not notify active NM2 UI bridge(s): %s\n', ME.message);
    end
end
delete(findobj('Tag','PrintCVBarsBin'));
delete(findobj('Name','Probabilistic Feature Exraction'));
clear CALIBAVAIL OOCVAVAIL
NMx = NM;
recovered = false;
if ~UI.writeBackReady && UI.bridgeEnabled && ~isempty(UI.sessionTmpDir)
    [NMx, recovered] = NMDataIOUI.loadSessionNM(NM, UI.sessionTmpDir);
end
NMx = localCleanSessionNM(NMx);
nowExists = ~isempty(writeBackVariable) && evalin('base',sprintf('exist(''%s'',''var'')',writeBackVariable)) == 1;
clearvars -global NM st
if (UI.writeBackReady || recovered) && ~isempty(writeBackVariable)
    if nowExists ~= targetExisted
        if targetExisted, detail = 'disappeared'; else, detail = 'appeared since launch'; end
        choice = strtrim(input(sprintf('Workspace variable %s has %s. Enter %s, another NEW variable name, or Return to cancel: ', ...
            writeBackVariable, detail, writeBackVariable),'s'));
        if ~isempty(choice) && (~isvarname(choice) || ...
                (~strcmp(choice,writeBackVariable) && evalin('base',sprintf('exist(''%s'',''var'')',choice)) == 1))
            fprintf('[nm] Invalid or occupied target; workspace write-back cancelled.\n');
            choice = '';
        end
        writeBackVariable = choice;
    end
    if ~isempty(writeBackVariable)
        assignin('base', char(writeBackVariable), NMx)
    end
else
    fprintf('[nm] No committed NM session state was recovered; workspace write-back skipped.\n');
end
if exist(fullfile(pwd,'temp.nii'),'file'); delete('temp.nii'); end
if exist('tempMLI.nii','file'); delete('tempMLI.nii'); end
try warning('off','last'); catch; end

end
