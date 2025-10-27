function [act, inp, NMo] = nk_MLOptimizerPrep(act, inp, parentstr)
% =========================================================================
% [act, inp] = nk_MLOptimizerPrep(act, inp, parentstr)
% Configure and run NM's ML training & CV optimizer (interactive or batch)
% ========================================================================= 
% DESCRIPTION
%   Entry point for preparing and launching the NeuroMiner (NM) machine
%   learning training and cross-validation (CV) module. Supports:
%     • Interactive menu-driven setup (analysis selection, mode, files, grid)
%     • Batch execution using a prefilled `inp` struct
%     • Simulation mode (act == 999) using xNM instead of NM
%
%   Depending on the selected "operation mode" (inp.lfl), the function can:
%     1) Compute everything from scratch
%     2) Use existing PreprocData MATs
%     3) Assemble from existing CVdatamat files
%     4) Assemble from existing CVresults MATs
%
% SYNTAX
%   % Interactive (typical):
%   [act, inp]  = nk_MLOptimizerPrep([], [], 'MAIN INTERFACE');
%
%   % Batch (provide NM and CV via inp.NM / inp.CV, set batchflag=2):
%   [act, inp]  = nk_MLOptimizerPrep(6, inp, 'BATCH');
%
%   % Simulation mode (use xNM, act==999):
%   [~, inp]    = nk_MLOptimizerPrep(999, [], 'SIM');
%
% INPUTS
%   act        : Scalar action code. If empty and not batch mode, an
%                interactive menu is shown. Special:
%                  0   -> exit
%                  1   -> select analyses
%                  2   -> choose operation mode (lfl)
%                  3   -> specify files (depending on lfl)
%                  4   -> toggle overwrite behavior
%                  5   -> select CV2 grid partitions
%                 6/7  -> proceed (train/aggregate)
%                999   -> simulation mode using xNM
%
%   inp        : Struct with runtime configuration. If empty, defaults are
%                created from NM/xNM. Important fields include:
%                  analind     : Analysis index/indices (default: 1)
%                  lfl         : Operation mode (1..4, see above; default 1)
%                  preprocmat  : PreprocData MAT master (cell), used if lfl=2
%                  gdmat       : CVdatamat master (cell), used if lfl=3
%                  gdanalmat   : CVresults MATs (cellstr), used if lfl=4
%                  varstr      : Optional variable name suffix(es)
%                  concatfl    : Modality concatenation flag(s)
%                  ovrwrt      : Overwrite policy for target files (1=Yes,2=No)
%                  update      : Update/refresh derived files when using precomputed data
%                  HideGridAct : If true, skip CV2 grid selection
%                  batchflag   : 0=interactive, 1=batch (non-deployed),
%                                2=batch with inp.NM / inp.CV supplied
%                  debugall    : Save all models and training data (DEV only)
%                  debugopt    : Save chosen optimum results/models (DEV only)
%                In batchflag==2, you must provide:
%                  inp.NM      : NM struct
%                  inp.CV      : CV struct array
%
%   parentstr  : Char label for breadcrumb / UI display.
%
% OUTPUTS
%   act        : Final action taken (useful if menu-driven).
%   inp        : Finalized runtime configuration (with computed defaults,
%                grid selections, resolved paths, etc.).
%   NMo        : (optional) Returns the current NM struct after processing
%                (mirrors NM or xNM depending on mode).
%
% GLOBALS (read/modified)
%   CV, NM, xNM, simFlag, JSMEM, DEBUG, DEV
%
% BEHAVIOR & SIDE EFFECTS
%   • Initializes or updates `inp` from NM/xNM and selected analyses.
%   • May delete prior analysis results (GDdims, visdata, OOCV) if the user
%     confirms when starting from scratch.
%   • Configures overwrite/update flags based on lfl and ovrwrt.
%   • Builds/loads preproc/CV masters depending on mode and selections.
%   • Calls the nested MLOptimizerPrep() to run optimization per analysis,
%     saving results under analysis.rootdir / <method>/.
%   • Updates NM/xNM.analysis{…} with GDdims and related metrics.
%
% OPERATION MODES (inp.lfl)
%   1  Compute all from scratch (no Preproc/CV MATs required)
%   2  Use existing PreprocData MATs (compute CVdatamats/results)
%   3  Assemble from existing CVdatamats (aggregate / tweak selection)
%   4  Assemble from existing CVresults (aggregate only; hides grid selection)
%
% NOTES
%   • act==999 enters simulation mode: uses xNM, sets simFlag, prepares
%     full grid (all CV2 partitions selected).
%   • For multiple analyses, grid selection may be hidden if CV structures
%     are not equal across analyses.
%   • When DEV is true, extra debug toggles appear in the menu.
%
% SEE ALSO
%   nk_GetAnalModalInfo_config, nk_GenPreprocMaster2, nk_GenCVdataMaster2,
%   nk_GenCVresultsMaster, nk_CVGridSelector, nk_SelectAnalysis,
%   nk_SetupGlobalVariables, nk_MLOptimizer_main
%
% COPYRIGHT
%   (c) Nikolaos Koutsouleris 06/2024
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris 06/2024

global CV NM xNM simFlag JSMEM DEBUG DEV  %xNM for simulation 

JSMEM = []; NMo = [];
clearNM = false; 
if exist('inp','var') && ~isempty(inp) && inp.batchflag==2
    NM = inp.NM; inp = rmfield(inp,'NM'); 
    CV = inp.CV; inp = rmfield(inp,'CV'); 
end
na_str = '?';
if ~exist('inp','var') || isempty(inp)
    inp = struct('analind',1, ...
        'lfl',1, ...
        'preprocmat',[], ...
        'gdmat',[], ...
        'gdanalmat', [], ...
        'varstr', [], ...
        'concatfl', [], ...
        'ovrwrt', 2, ...
        'update', true, ...
        'HideGridAct', false, ...
        'batchflag', false, ...
        'debugall', false, ...
        'debugopt', false);
    if act == 999
        inp.analind = xNM.analind;
        inp.simFlag =true;
        inp.batchflag = true;
        inp = nk_GetAnalModalInfo_config(xNM, inp);
        [ ix, jx ] = size(xNM.cv(1).TrainInd);
        simFlag = 1;
    else
        inp = nk_GetAnalModalInfo_config(NM, inp);
        [ ix, jx ] = size(CV(1).TrainInd);
        simFlag = 0; 
    end
    inp.GridAct = false(ix,jx);
end

%% Configure menu
if isfield(inp,'analind')
    if numel(inp.analind)<2
        AnalSelStr = sprintf('Analysis %g', inp.analind);
    else
        if ~inp.HideGridAct, cvequalstr = 'same-size CV structures'; else, cvequalstr = 'different CV structures'; end
        AnalSelStr = sprintf('%g Analyses: %s [ %s ]',numel(inp.analind), strjoin(cellstr(num2str(inp.analind'))',', '), cvequalstr);
    end
else
    AnalSelStr = 'none selected';
end

if ~isfield(inp,'simFlag') || ~inp.simFlag
    if numel(NM.analysis)>1
        AnalSelectStr = sprintf('Choose analyses to work on [ %s ]|', AnalSelStr);
        AnalSelectAct = 1;
    else
        AnalSelectStr = []; AnalSelectAct = [];
    end
else
    AnalSelectStr = []; AnalSelectAct = [];
    
end
% Initialize analysis with current training parameters
if isfield(inp,'simFlag') && inp.simFlag
    analysis = xNM.analysis{inp.analind};
else
    analysis = NM.analysis{inp.analind};
end
if ~exist('inp','var') || isempty(inp)
    if isfield(analysis,'GDdims')
        fprintf('\n')
        fprintf('******************************************************* \n')
        fprintf('ATTENTION: \n')
        fprintf('Previous analysis detected \n')
        fprintf('If you proceed this analysis will be deleted. \n')
        fprintf('******************************************************* \n')
        procflag = nk_input('Proceed anyway',0,'yes|no',[1,0], 2);
        if ~procflag, return; end
        analysis = rmfield(analysis,'GDdims');
        fprintf('\n');fprintf('Training and CV results deleted!');
        if isfield(analysis,'visdata')
            analysis = rmfield(analysis,'visdata');
            fprintf('\n');fprintf('Visualization results deleted!');
        end
        if isfield(analysis,'OOCV')
            analysis = rmfield(analysis,'OOCV');
            fprintf('\n');fprintf('Independent test data results deleted!');
        end
        analysis.status = 0;
    end

end

if ~isempty(analysis)

    %% Prepare some useful filename and fieldname definitions
    inp.tdatatypes = {'CVdatamat','CVdatamat','CVresults','CVdimanalysis'};
    inp.sdatatypes = {'','PreprocData','CVdatamat','CVresults'};
    inp.sfieldnames = {'','preprocmat','gdmat','gdanalmat'};

    if ~isfield(inp,'simFlag') || ~inp.simFlag
        nk_SetupGlobalVariables(NM.analysis{inp.analind(1)}.params, 'setup_main', 0);
        [ix, jx] = size(CV(1).TrainInd);
    else
        nk_SetupGlobalVariables(xNM.analysis{inp.analind(1)}.params, 'setup_main', 0);
        [ix, jx] = size(xNM.cv(1).TrainInd);
    end

    if isempty(inp.preprocmat),   inp.preprocmat = cell(inp.nF,1); end
    if isempty(inp.gdanalmat),    inp.gdanalmat = cell(inp.nF,1); end

    %% Compute from scratch or use pre-computed datamats from different stages of the analysis process?

    LFL_opts  = {'Compute from scratch (no CVdatamats or Preprocdata-MATs available)', ...
        'Compute using existing Preprocdata-MATs (no CVdatamats available)', ...
        'Assemble analysis using existing CVdatamats', ...
        'Assemble analysis using existing CVresult-MATs'};

    lflcnt = 0;
    if numel(inp.varind)>1
        LFL_opts(1)=[]; if inp.lfl == 1; inp.lfl = 2; end
        if inp.lfl > 1, lflcnt = 1; end
    end

    if inp.lfl == 4, inp.HideGridAct = true; else, inp.HideGridAct = false; end

    ModeStr   = sprintf('Operation mode of ML training module [ %s ]|',LFL_opts{inp.lfl-lflcnt});          ModeAct = 2;

    if inp.lfl>1 && ~inp.batchflag
        % precomputed
        nTargFiles = na_str; mT=1;
        if isfield(inp,inp.sfieldnames{inp.lfl}) && ~isempty(inp.(inp.sfieldnames{inp.lfl}))
            if iscell(inp.(inp.sfieldnames{inp.lfl}){1})
                nT = sum(sum(~cellfun(@isempty, inp.(inp.sfieldnames{inp.lfl}){1})));
                if numel(inp.(inp.sfieldnames{inp.lfl})) == numel(inp.varind)
                    mT=numel(inp.(inp.sfieldnames{inp.lfl}));
                elseif nT>0 && ~iscell(inp.(inp.sfieldnames{inp.lfl}){1}{1})
                    mT = size(inp.(inp.sfieldnames{inp.lfl}){1}{1},1);
                else
                    mT = size(inp.(inp.sfieldnames{inp.lfl}),1);
                end
            else
                nT = sum(sum(~cellfun(@isempty, inp.(inp.sfieldnames{inp.lfl}))));
                if nT>0
                    if iscell(inp.(inp.sfieldnames{inp.lfl}))
                        mT = 0;
                    else
                        mT = size(inp.(inp.sfieldnames{inp.lfl}{1}),1);
                    end
                end
            end
            if mT>1 && nT>0, nvarstr = sprintf('%gx',mT); else, nvarstr = ''; end
            nTargFiles = sprintf('%s%g selected', nvarstr, nT);
        end
        FilesStr = sprintf('Specify %s files [ %s ]|', inp.sdatatypes{inp.lfl}, nTargFiles);        FilesAct = 3;
    else
        FilesStr = ''; FilesAct = [];
    end
    % from scratch
    OVRWRT_opts = { sprintf('Overwrite %s files',inp.tdatatypes{inp.lfl}), ...
        sprintf('Do not overwrite %s files',inp.tdatatypes{inp.lfl})};

    OverWriteStr = sprintf('Overwrite existing %s files [ %s ]|', ...
        inp.tdatatypes{inp.lfl}, OVRWRT_opts{inp.ovrwrt}) ;                                         OverWriteAct = 4;

    %% Retrieve CV2 partitions to operate on
    if ~isfield(inp,'GridAct'), inp.GridAct = false(ix,jx); end
    if ~inp.HideGridAct
        GridSelectStr = sprintf('Select CV2 partitions to operate on [ %g selected ]|', ...
            sum(inp.GridAct(:)));  GridSelectAct = 5;
    else
        GridSelectStr = ''; GridSelectAct = [];
    end

    %% Build interactive menu
    menustr = [ AnalSelectStr ...
        ModeStr ...
        FilesStr ...
        OverWriteStr ...
        GridSelectStr ];

    menuact = [ AnalSelectAct ...
        ModeAct ...
        FilesAct ...
        OverWriteAct ...
        GridSelectAct ];

    if ~isdeployed && DEV
        debugallstr = 'no'; debugoptstr = 'no';
        if isfield(inp,'debugall') && inp.debugall, debugallstr = 'yes'; end
        if isfield(inp,'debugopt') && inp.debugopt, debugoptstr = 'yes'; end
        menustr = [ menustr ...
            sprintf('DEBUGGING: Save all models and respective training data [ %s ]|',debugallstr) ...
            sprintf('DEBUGGING: Save chosen optimum results with models [ %s ]|',debugoptstr) ];
        menuact = [ menuact 30 31];
    end

    disallow = false;

    %% Check whether all parameters are available
    if (~sum(inp.GridAct(:)) && ~inp.HideGridAct) || isempty(inp.analind), disallow = true; end
    if inp.lfl>1 
        if ~isfield(inp, inp.sfieldnames{inp.lfl}) || isempty(inp.(inp.sfieldnames{inp.lfl})) || (iscell(inp.(inp.sfieldnames{inp.lfl})) && isempty(inp.(inp.sfieldnames{inp.lfl}){1}))
            disallow = true; 
        end
    end

    if ~disallow, menustr = [menustr 'PROCEED >>>']; menuact = [menuact 6]; end

    % Set run-time flags
    if inp.ovrwrt == 2, ovrwrt = false; else, ovrwrt = true; end
    switch inp.lfl
        case 1
            inp.ovrwrtGD        = ovrwrt;
            inp.updGD           = true;
            inp.ovrwrtRes       = true;
            inp.updRes          = true;
        case 2
            inp.ovrwrtGD        = ovrwrt;
            inp.updGD           = inp.update;
            inp.ovrwrtRes       = true;
            inp.updRes          = true;
        case 3
            inp.ovrwrtGD        = false;
            inp.updGD           = inp.update;
            inp.ovrwrtRes       = ovrwrt;
            inp.updRes          = true;
        case 4
            inp.ovrwrtGD        = false;
            inp.updGD           = false;
            inp.updRes          = inp.update;
            inp.ovrwrtRes       = false;
    end

    %% Display menu and act on user selections
    nk_PrintLogo
    mestr = 'ML Training module run-time configuration'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>>',parentstr);
    if ~inp.batchflag, act = nk_input(mestr, 0, 'mq', menustr, menuact); end
    algostr = getAlgoStr(analysis);
    switch act
        case 0
            return
        case 1
            if isfield(inp,'analind'), analind = inp.analind; end
            brief = 1;t_act = 1; while t_act>0, [t_act, analind, ~, ~, brief] = nk_SelectAnalysis(NM, 0, 'MAIN INTERFACE >> TRAIN ML MODELS', analind, [], 0, 0, brief); end
            if ~isempty(analind)
                inp.analind             = analind;
                inp.preprocmat          = cell(inp.nF,1);
                inp.gdmat               = [];
                inp.gdanalmat           = [];
                nA = numel(inp.analind);
                if nA>1
                    AS = nk_GetAnalysisStatus(NM, inp.analind);
                    if ~AS.betweenfoldpermequal_cv
                        inp.HideGridAct = true; 
                    else
                        [ ix, jx ] = size(NM.analysis{inp.analind(1)}.params.cv.TrainInd);
                        inp.GridAct = false(ix,jx);
                        inp.HideGridAct = false;
                    end
                else
                    inp.HideGridAct = false;
                    inp = nk_GetAnalModalInfo_config(NM, inp);
                    [ ix, jx ] = size(NM.analysis{inp.analind}.params.cv.TrainInd);
                    inp.GridAct = false(ix,jx);
                end
                
            end
        case 2
            if numel(inp.varind)>1, selLFLopts = 2:4; lfldef = inp.lfl - 1; else, selLFLopts = 1:4; lfldef = inp.lfl; end
            lfl = nk_input('Define run-time mode of ML training module',0,'mq',strjoin(LFL_opts, '|'), selLFLopts, lfldef);
            if numel(inp.varind)>1 && lfl == lfl+1; end
            if lfl, inp.lfl = lfl; end
        case 3
            %% Prepare for runtime:
            % This section of the code sets the options and file masters for the ML optimization procedure
            % Basically we distinguish between:
            switch inp.lfl
                case 1 % Running from scratch
                    inp.preprocmat          = cell(inp.nF,1);
                    inp.gdmat               = [];
                    inp.gdanalmat           = [];
                    inp.GridAct             = true(ix,jx);
                case 2 % Running with precomputed Preprocdatamats
                    [preprocmat, emptfl]    = nk_GenPreprocMaster2(NM.id, CV(1), [],  NM.analysis{inp.analind}.rootdir, [], [], inp.varind, inp.varstr, inp.concatfl);
                    if ~emptfl && ~isempty(preprocmat)
                        inp.preprocmat      = preprocmat;
                        inp.gdmat           = [];
                        inp.gdanalmat       = [];
                        inp.GridAct         = ~cellfun(@isempty,preprocmat{1});
                    end
                case 3 % Running with precomputed CVdatamats (aggregation run --- allowing to tweak some post-training model selection options)

                    [gdmat, emptfl]         = nk_GenCVdataMaster2(NM.id, CV(1), [], fullfile(NM.analysis{inp.analind}.rootdir, algostr), [], [], inp.varind, inp.varstr, inp.concatfl);
                    if ~emptfl && ~isempty(gdmat)
                        inp.preprocmat      = cell(inp.nF,1);
                        inp.gdmat           = gdmat;
                        inp.GridAct         = ~cellfun(@isempty,gdmat{1});
                    end
                case 4 % Running with existing CVresults (simple aggregation run --- basically for multiple modalities)

                    [gdanalmat, emptfl]     = nk_GenCVresultsMaster(NM.id,[], fullfile(NM.analysis{inp.analind}.rootdir, algostr));
                    if ~emptfl && ~isempty(gdanalmat)
                        inp.preprocmat      = cell(inp.nF,1);
                        inp.gdmat           = [];
                        inp.gdanalmat       = gdanalmat;
                        load(gdanalmat{1});
                        inp.GridAct         = GDanalysis.GridAct;
                        clear GDanalysis
                    end
            end
        case 4
            if inp.ovrwrt ==1, inp.ovrwrt=2; elseif inp.ovrwrt == 2, inp.ovrwrt = 1; end
        case 5
            t_act = 1; while t_act > 0 && t_act < 11, [ t_act, inp.GridAct ] = nk_CVGridSelector(ix,jx, inp.GridAct, 0); end
        case 30
            inp.debugall = ~inp.debugall;
        case 31
            inp.debugopt = ~inp.debugopt;
        case {6,7,999}
            if inp.lfl ~=2, inp.preprocmat = []; end
            % act==7 is the automation option. Make sure that inp is properly defined
            % To this end create an inp structure based on
            nA = 1; if numel(inp.analind)>1, nA = numel(inp.analind); end
            % Differentiate according whether you work with real data or
            % in simulation mode
            if ~isfield(inp,'simFlag') || ~inp.simFlag
                tNM = NM;
            else
                tNM = xNM;
                inp.preprocmat          = [];
                inp.gdmat               = [];
                inp.gdanalmat           = [];
                inp.GridAct             = true(ix,jx);
                
            end
            if isdeployed || ~DEV
                clear DEBUG
            else
                if inp.debugall, DEBUG.eachmodel = true; end
                if inp.debugopt, DEBUG.optmodel = true; end
            end
            % Run through multiple analyses if needed    
            for i=1:nA
                tNM.runtime.curanal = inp.analind(i);
                % Configure inp structure according to actual analysis
                inp = nk_GetAnalModalInfo_config(tNM, inp); 
                inp.curanal = inp.analind(i);
                if inp.HideGridAct, [ ix, jx ] = size(NM.analysis{inp.analind(i)}.params.cv.TrainInd); inp.GridAct = true(ix,jx); end
                inp.analysis_id = tNM.analysis{inp.analind(i)}.id;
                
                % check whether alternative label should be used (only
                % necessary if analysis were set up with older NM
                % structure)
                if isfield(tNM.analysis{inp.analind(i)}.params,'label') && tNM.analysis{inp.analind(i)}.params.label.altlabelflag

                    tNM.label = tNM.analysis{inp.analind(i)}.params.label.label; 
                    tNM.modeflag = tNM.analysis{inp.analind(i)}.params.label.modeflag;  
                    %altlabel = true;
                end
                tNM.analysis{inp.analind(i)} = MLOptimizerPrep(tNM, tNM.analysis{inp.analind(i)}, inp);
                nk_SetupGlobalVariables(tNM.analysis{inp.analind(i)}.params, 'clear', 0)
              
            end
            % Copy back results to NM/xNM
            if ~isfield(inp,'simFlag') || ~inp.simFlag

                if isfield(tNM.analysis{inp.analind(i)}.params, 'label') && tNM.analysis{inp.analind(i)}.params.label.altlabelflag
                    tNM.label = NM.label; 
                    tNM.modeflag = NM.modeflag; 
                end
                NM = tNM;
                NM = rmfield(NM,'runtime');
            else
                xNM = tNM;
                xNM = rmfield(xNM,'runtime');
            end
            clear tNM
            h = findobj('Tag','PrintCVBarsBin'); if ~isempty(h), delete(h); end
            
    end
end

if nargout == 3, NMo = NM; end
if clearNM, clear NM; end

% _________________________________________________________________________
function analysis = MLOptimizerPrep(dat, analysis, inp1)

global PARMODE MULTI SAV MODEFL CV PREPROC RAND FUSION META SVM

nk_SetupGlobalVariables(analysis.params, 'setup_strat', 0, inp1.varind(1));
strout = nk_Preprocess_StrCfg([], []);

% Define # of classifiers to train (1 for multi-group classification & regression)
inp1.nclass = 1; if strcmp(MODEFL,'classification') && RAND.Decompose ~= 9, inp1.nclass = length(CV(1).class{1,1}); end
inp1.probflag = false;

% **************************** ANALYSIS SETUP *****************************
ld = 1; if FUSION.flag == 3, ld = numel(inp1.F); end
inp1.unique_groups = unique(dat.label); 
inp1.unique_groups(isnan(inp1.unique_groups))=[];
inp1.ngroups = numel(inp1.unique_groups);
hx = size(dat.label,2);
analysis.Time                               = zeros(ld,1);
analysis.TrainPerformanceBin                = zeros(ld,inp1.nclass,hx);
analysis.TestPerformanceBin                 = zeros(ld,inp1.nclass,hx);
analysis.TestPerformanceBinPermAggr         = zeros(ld,inp1.nclass,hx);
analysis.TestPerformanceBinPermAggrMajVote  = zeros(ld,inp1.nclass,hx);
analysis.TrainPerformanceMean               = zeros(ld,1);
analysis.TestPerformanceMean                = zeros(ld,1);
analysis.TestPerformanceMeanPermAggr        = zeros(ld,1);

if ~isempty(MULTI) && MULTI.flag && inp1.nclass > 1
    analysis.TrainPerformanceMulti          = zeros(ld,1);
    analysis.TestPerformanceMulti           = zeros(ld,1);
    analysis.TestPerformanceMultiPermAggr   = zeros(ld,1);
    analysis.TestPerformanceMultiPermAggrGroup = zeros(ld,inp1.ngroups,1);
    inp1.multiflag = true;
else
    inp1.multiflag = false;
end

PARMODE = 0;
analysis.status = 0;
GDdims = cell(inp1.nF,1);
preprocmat = inp1.preprocmat;

switch FUSION.flag
    case 3
        mthstr = 'DECFUSE';
    otherwise
        mthstr = SVM.prog;
end

% Create analysis directory if needed
if ~isfield(inp1,'rootdir') || isempty(inp1.rootdir) || ~exist(inp1.rootdir,'dir')==7
    inp1.rootdir = fullfile(pwd,mthstr);
else
    inp1.rootdir = fullfile(analysis.rootdir,mthstr);
end
inp1.maindir = analysis.rootdir;
if ~exist(inp1.rootdir,'dir'), mkdir(inp1.rootdir);end

% Write some info to command line
clc
fprintf('******************************\n')
fprintf('**  PARAMETER OPTIMIZATION  **\n')
fprintf('******************************\n')

for i = 1:inp1.nF

    %% Get Training / CV data (Y) & Build modality suffix
    inp2  = nk_DefineFusionModeParams(dat, analysis, inp1.F, inp1.nF, i);
    inp   = catstruct(inp1,inp2); clear inp2
    if isfield(dat,'time'), inp.time2event = dat.time; end
    if inp.lfl == 2, inp.preprocmat = preprocmat{i,:,:}; end

    inp.stranalysis = SAV.matname; strGDdimsfile = fullfile(inp.rootdir, ...
        [inp.stranalysis '_CVdimanalysis' strout '_ID' dat.id '.mat']);

    [~, PreML] = nk_GenPreML(PREPROC);

    maxacc = zeros(inp.nclass, 1); maxtestacc = zeros(inp.nclass,1 );
    
    if isfield(SVM,'ParameterOptimizationMode')
        inp.ParameterOptimizationMode = SVM.ParameterOptimizationMode;
    end

    % *********************************** GO **********************************
    if isfield(inp,'simFlag') && inp.simFlag
        if ~isempty(inp.gdanalmat)
        % Load precomputed CVresults file
            load(inp.gdanalmat{i}); GDdims{i} = GDanalysis;
        else
        % Train classifier / predictor at current dimensionality
            GDdims{i} = nk_MLOptimizer_main(inp, dat.id, PreML);
        end
    else
        if ~isempty(inp.gdanalmat{i})
            % Load precomputed CVresults file
            load(inp.gdanalmat{i}); GDdims{i} = GDanalysis;
        else
            % Train classifier / predictor at current dimensionality
            GDdims{i} = nk_MLOptimizer_main(inp, dat.id, PreML);
        end
    end
    if inp.batchflag ==0 || inp.batchflag ==2 || (isfield(inp,'simFlag') &&inp.simFlag)
        GDdims{i}.datadescriptor = dat.datadescriptor{inp.tF};
        % Retrieve best accuracies of binary classifiers from grid structure
        for j = 1:inp.nclass
            maxacc(j) = GDdims{i}.best_CVperf{j};
            analysis.TrainPerformanceBin(i,j) = maxacc(j);
            maxtestacc(j) = GDdims{i}.best_TSperf{j};
            analysis.TestPerformanceBin(i,j) = maxtestacc(j);
            switch MODEFL
                case 'regression'
                    analysis.TestPerformanceBinPermAggr(i,j,:)            = GDdims{i}.Regr.costfun_crit;
                case 'classification'
                    analysis.TestPerformanceBinPermAggr(i,j,:)            = GDdims{i}.BinClass{j}.costfun_crit;
                    if RAND.Decompose ~= 9
                        analysis.TestPerformanceBinPermAggrMajVote(i,j,:) = GDdims{i}.BinClass{j}.prob_contigency.BAC;
                    end
            end
        end

        % 1) Calculate maximum performance for current dimensionality by means of
        % averaging the binary classifiers
        meanmaxacc                              = mean(maxacc);
        analysis.TrainPerformanceMean(i)        = meanmaxacc;
        analysis.TestPerformanceMean(i)         = mean(maxtestacc(maxtestacc~=0));
        analysis.TestPerformanceMeanPermAggr(i) = mean(analysis.TestPerformanceBinPermAggr(i,:));
        if ~isempty(MULTI) && MULTI.flag && inp.nclass > 1
            analysis.TrainPerformanceMulti(i) = GDdims{i}.best_MultiCVperf;
            analysis.TestPerformanceMulti(i) = GDdims{i}.best_MultiTSperf;
            analysis.TestPerformanceMultiPermAggr(i) = GDdims{i}.MultiClass.accuracy;
            for z=1:inp.ngroups
                analysis.TestPerformanceMultiPermAggrGroup(i,z) = GDdims{i}.MultiClass.class{z}.BAC;
            end
        end
    end
end

% Store analysis results in analysis structure and set status to 1
analysis.GDdims = GDdims;
if ~isempty(META) && META.flag
    %if 
    IN.labels = inp.labels;
    IN.nclass = inp.nclass;
    IN.ngroups = unique(inp.labels); IN.ngroups(isnan(IN.ngroups))=[]; IN.ngroups = numel(IN.ngroups);
    METAres = nk_MLOptimizerMeta( analysis, IN );
    if ~isempty(METAres), analysis.META = METAres; end
end

analysis.status = 1;
% Save analysis to disk
if ~inp.batchflag || (~isfield(inp,'simFlag') || ~inp.simFlag)
    fprintf('\nSaving %s', strGDdimsfile);
    save(strGDdimsfile,'analysis');
end
