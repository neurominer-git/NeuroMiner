function [act, inp] = nk_VisModelsPrep(act, inp, parentstr)
% =========================================================================
% function [act, inp] = nk_VisModelsPrep(act, inp, parentstr)
% =========================================================================
% Wrapper for the NeuroMiner visualization module. Displays an interactive
% menu that allows the user to choose run‐time options for analyzing and
% visualizing model patterns (e.g., CV consistency maps, factor
% back‐projections, parameter loading/saving).
%
% INPUTS:
%   act         Initial action code (integer). If zero or omitted, forces
%               display of the configuration menu.
%   inp         Configuration struct with fields (defaults in parentheses):
%                 analind    – index(es) of analysis to work on
%                 lfl        – 1=compute from scratch, 2=use precomputed
%                 extraL     – extra labels struct for permutation testing
%                 ovrwrt     – 1=overwrite existing, 2=do not overwrite
%                 multiflag  – 1=multi‐class optimum, 2=binary optima
%                 CV1        – 1=save at CV1, 2=operate at CV2
%                 saveparam  – 1=save preprocessing/models, 2=do not save
%                 loadparam  – 1=load existing params, 2=recompute
%                 writeCV2   – 1=write CV2 maps, 2=do not write
%                 CVRnorm    – 1=use SD, 2=use SEM for CVR
%                 DecompMode – 1=back‐project components, 2=standard
%                 FDRcompSearch – 1=back‐project only components that reach
%                               FDR-corrected significance 
%                 HideGridAct– true=hide CV grid selector, false=show
%                 batchflag  – 1=batch mode, 2=interactive mode
%                 lowmem     – 1=low memory mode, 2=standard mode
%               If empty or missing, all fields are initialized to defaults.
%   parentstr   String indicating the menu navigation path (for nested UIs).
%
% OUTPUTS:
%   act         Selected menu action code (integer).
%   inp         Updated configuration struct containing all user selections.
%
% EXAMPLE:
%   % Start fresh in interactive mode under “Main” menu
%   [act, inp] = nk_VisModelsPrep(0, [], 'Main');
%
% NOTES:
%   - Requires global variables MULTI, CV, and NM to be already set.
%   - After selection (act==99) this function calls VisModelsPrep to run
%     the actual visualization analysis and then clears global state.
%
% SEE ALSO:
%   nk_GetAnalysisStatus, nk_Input, nk_VisModels, nk_VisModelsC
% =========================================================================
% (c) Nikolaos Koutsouleris, 05/2025

global MULTI CV NM

%% Setup defaults
as = nk_GetAnalysisStatus(NM); complvec = find(as.completed_analyses);
if ~exist('inp','var') || isempty(inp)
    inp = struct( 'analind', complvec(1), ...       % Index to analysis
                    'lfl', 1, ...                   % 1 = compute from scratch, 2 = use existing (allowing the user to specify OOCVdatamats)
                    'extraL', [], ...               % Extra labels structure with label matrix (double m x n) and names (cell array 1 x n)
                    'ovrwrt', 2, ...                % if lfl == 1 ==> 1 = overwrite existing OOCVdatamats, 2 = do not overwrite (use existing OOCVdatamats automatically)
                    'multiflag', 2, ...             % operate at multi-class optimum (=1) or at binary optima (=2)
                    'CV1', 2, ...                   % if loadparam == 2 && saveparam ==1 => 1 = save large processing containers at the CV1 level,  2 = operate at CV2 level
                    'saveparam', 2, ...             % if loadparam == 2=> 1 = save OOCV processing parameters (preprocessing / models), 2 = do not save parameters to disk
                    'loadparam', 2, ...             % 1 = load existing optpreproc and/or optmodel parameters from disk, 2 = recompute parameters
                    'writeCV2', 2, ...              % 1 = write-out CVR and SignBasedConsistency-Maps (FDR) and resp. masked CVR to disk
                    'CVRnorm', 1, ...               % 1 = use standard deviation to compute CVR, 2 = use SEM to compute CVR
                    'DecompMode', 2, ...            % 1 = back-project factorization components (e.g. principal components of a PCA-based model) separately to input space
                    'fdr_comp_search', 2, ...       % 1 = only back-project components that are significant at q <= alpha threshold (0.05).
                    'simCorrThresh', 0.3, ...       % if DecompMode = 1, threshold for similarity-based realignment of components
                    'simCorrMethod', 'pearson', ... % if DecompMode = 1, similarity computation method
                    'CorrCompCutOff', 0.3, ...      % if DecompMode = 1, similarity cutoff for dropping componentsat low-memory problems or at the final pruning step in nk_VisModelsC
                    'SelCompCutOff', 0.2, ...       % if DecompMode = 1, Cross-CV2 selection probability of components 
                    'HideGridAct', false, ...
                    'batchflag', 2, ...
                    'lowmem', 2);
end
na_str = '?'; inp.datatype = 'VISdatamat'; 
% Resolves bug when running in batch mode
if ~isfield(inp,'extraL') , inp.extraL=[]; end
OverWriteStr = []; GridSelectStr = []; LoadModelsStr = []; LoadParamsStr = []; LoadStr = []; 
SaveStr = []; ExtraLStr = []; CV1OpStr = []; WriteCV2str = []; DecompModeStr = []; LowMemStr = []; 
simCorrThreshStr = []; simCorrMethodStr = []; CorrCompCutOffStr = []; SelCompCutOffStr = [];
OverWriteAct = []; GridSelectAct = []; LoadModelsAct = []; LoadParamsAct = []; LoadAct = []; 
SaveAct = []; ExtraLAct = []; CV1OpAct = []; WriteCV2Act = []; DecompModeAct= []; LowMemAct = [];
simCorrThreshAct = []; simCorrMethodAct = []; CorrCompCutOffAct = []; SelCompCutOffAct = [];

%% Configure menu
if numel(NM.analysis)>1
    if numel(inp.analind)<2
        AnalSelStr = sprintf('Analysis %g', inp.analind);
    else
        if ~inp.HideGridAct, cvequalstr = 'same-size CV structures'; else, cvequalstr = 'different CV structures'; end
        AnalSelStr = sprintf('%g Analyses: %s [ %s ]',numel(inp.analind), strjoin(cellstr(num2str(inp.analind'))',', '), cvequalstr);
    end 
    AnalSelectStr = sprintf('Choose analysis to work on [ %s ]|', AnalSelStr);  AnalSelectAct = 1;
else
    AnalSelectStr = ''; AnalSelectAct = [];
end

analysis = NM.analysis{inp.analind(1)}; 
[inp.permfl, inp.permsig, inp.permmode] = get_permflag( analysis );

if ~isempty(analysis)
    
    YesNo_opts  = {'yes', 'no'};   
    CVR_opts = {'SD','SEM'};

    % Initialize global parameters for the selected analysis
    nk_SetupGlobalVariables(analysis.params, 'setup_main', 0); 
    MULTI = analysis.params.TrainParam.MULTI;
    
    % Compute from scratch or use pre-computed datamats ?
    LFL_opts        = {'Compute from scratch',sprintf('Use precomputed %s',inp.datatype)};                                      
    ModeStr         = sprintf('Operation mode of visualization module [ %s ]|',LFL_opts{inp.lfl});                   ModeAct = 2;
    
    if inp.lfl == 1
        % from scratch
        OVRWRT_opts     = {'Overwrite existing','Do not overwrite'};       
        OverWriteStr = sprintf('Overwrite existing %s files [ %s ]|', inp.datatype, OVRWRT_opts{inp.ovrwrt}) ;       OverWriteAct = 3; 
    else
        % precomputed
        nVisFiles = na_str;
        if isfield(inp,'vismat') && ~isempty(inp.vismat) 
            selGrid = ~cellfun(@isempty,inp.vismat); inp.GridAct = selGrid;
            nVisFiles = sprintf('%g selected', sum(selGrid(:))); 
        end     
        OverWriteStr = sprintf('Specify %s files [ %s ]|', inp.datatype, nVisFiles);                                 OverWriteAct = 3; 
    end
    
    % Retrieve CV2 partitions to operate on
    if ~isfield(inp,'GridAct'), inp.GridAct = analysis.GDdims{1}.GridAct; end
    if ~inp.HideGridAct
        GridSelectStr = sprintf('Select CV2 partitions to operate on [ %g selected ]|',  sum(inp.GridAct(:)));       GridSelectAct = 4;
    else
        GridSelectStr =''; GridSelectAct=[];
    end
    % Configure extra label dialogue
    if inp.permfl
        if ~isempty(inp.extraL)
            m = size(inp.extraL.L,2); 
            ExtraLStr = sprintf('Test models'' generalization capacity to other labels [ activated, %g extra label(s) defined ]|', m);     ExtraLAct = 11;
        else
            ExtraLStr = sprintf('Test models'' generalization capacity to other labels [ not activated ]|');     ExtraLAct = 10;
        end
    end 

    % Configure write out of CV2 partition maps (for imaging analyses only)
    if numel(inp.analind)<2
        if nk_CheckContainsImagingData(NM, inp.analind)
            WRITECV2_opts     = {'yes','no'};       
            WriteCV2str = sprintf('Write CVR, sign-based consistency maps (FDR) and masked CVR images [ %s ]|', ...
                WRITECV2_opts{inp.writeCV2}) ;                                                                        WriteCV2Act = 13;  
        end
    end

    % Configure loading of pre-existing parameters and models
    if inp.saveparam == 2 && inp.lfl == 1 && inp.CV1==2
        LoadStr = sprintf('Use saved pre-processing params and models [ %s ]|', YesNo_opts{inp.loadparam});           LoadAct = 7;
        if inp.loadparam == 1
            if isfield(inp,'optpreprocmat') 
                selGridPreproc = ~cellfun(@isempty,inp.optpreprocmat);
                nParamFiles = sprintf('%g files selected', sum(selGridPreproc(:))); 
            else
                nParamFiles = na_str; 
            end
            LoadParamsStr = sprintf('Select preprocessing parameter files [ %s ]|' ,nParamFiles);                     LoadParamsAct = 8;
            if isfield(inp,'optmodelmat')
                selGridModel = ~cellfun(@isempty,inp.optmodelmat);
                nModelFiles = sprintf('%g files selected', sum(selGridModel(:))); 
            else
                nModelFiles = na_str; 
            end
            LoadModelsStr = sprintf('Select model files [ %s ]|',nModelFiles);                                        LoadModelsAct = 9;
        end
    end
    
    % Operate at the CV1 level to save RAM
    if inp.lfl==1
        CV1OpStr = sprintf('Operate at the CV1 level [ %s ]|', YesNo_opts{inp.CV1});                                  CV1OpAct = 12;
    else
        CV1OpStr = ''; inp.CV1=2;
    end
    
    % If loading of pre-existing models and params is not chosen, allow to
    % save the computed params and models to disk
    if inp.loadparam == 2 && inp.lfl == 1 && inp.CV1 == 2
        SaveStr = sprintf('Save pre-processing params and models to disk [ %s ]|', YesNo_opts{inp.saveparam});        SaveAct = 6;
    end

    % Check if at least one modality is processed without a dimensionality 
    % reduction method. If so, allow user to modify the memory mode and
    % thus compute correlation matrices and derived metrics
    switch analysis.params.TrainParam.FUSION.flag
        case {0,1,2}
            PREPROCs = analysis.params.TrainParam.PREPROC(analysis.params.TrainParam.FUSION.M);
        case 3
            nM = numel(analysis.params.TrainParam.FUSION.M); PREPROCs = cell(1,nM);
            for n=1:nM
                PREPROCs{n} = analysis.params.TrainParam.STRAT{analysis.params.TrainParam.FUSION.M(n)}.PREPROC;
            end
    end
    inp.decompfl = false(1,numel(PREPROCs));
    for i=1:numel(PREPROCs)
        inp.decompfl(i) = nk_DetIfDimRefInPREPROC(PREPROCs{i}, i);
    end
    if any(inp.decompfl) && analysis.params.TrainParam.FUSION.flag==1
        inp.decompfl = true(1,numel(inp.decompfl));
    end

    if isfield(inp,'decompfl') && any(inp.decompfl) 
        DecompModeStr = sprintf('Back-project factorization components separately to input space [ %s ]|', YesNo_opts{inp.DecompMode}); DecompModeAct= 16;
        if inp.DecompMode == 1
             simCorrThreshStr = sprintf('Define similarity cutoff (0-1) for factorization component realignment [ %g ]|', inp.simCorrThresh); simCorrThreshAct = 17;
             simCorrMethodStr = sprintf('Define similarity computation method for factorization component realignment [ %s ]|', inp.simCorrMethod); simCorrMethodAct = 18;
             CorrCompCutOffStr = sprintf('Define similarity cutoff (0-1) for keeping factorization components [ %g ]|', inp.CorrCompCutOff); CorrCompCutOffAct = 19;
             SelCompCutOffStr = sprintf('Define presence cutoff (0-1) for keeping factorization components [ %g ]|', inp.SelCompCutOff); SelCompCutOffAct = 20;
        end
    end
        
    if ~isfield(inp,'decompfl') || (isscalar(inp.decompfl) && ~inp.decompfl) || sum(inp.decompfl)<numel(inp.decompfl)
        LowMemStr = sprintf('Low memory mode (no correlation matrix being computed) [ %s ]|', YesNo_opts{inp.lowmem}); LowMemAct = 14;
    end

    CVRnormStr = sprintf('Use standard deviation or SEM to compute CVR metrics [ %s ]', CVR_opts{inp.CVRnorm}); CVRnormAct = 15;

end

%% Build interactive menu
menustr = [ AnalSelectStr ...
           ModeStr ...
           ExtraLStr ...
           OverWriteStr ...
           GridSelectStr ...
           CV1OpStr ...
           SaveStr ...
           LoadStr ...
           LoadParamsStr ... 
           LoadModelsStr ...
           WriteCV2str ...
           DecompModeStr ...
           simCorrMethodStr ...
           simCorrThreshStr ...
           CorrCompCutOffStr ...
           SelCompCutOffStr ...
           LowMemStr ...
           CVRnormStr ];

menuact = [ AnalSelectAct ...
            ModeAct ...
            ExtraLAct ...
            OverWriteAct ...
            GridSelectAct ...
            CV1OpAct ...
            SaveAct ...
            LoadAct ...
            LoadParamsAct ...
            LoadModelsAct ...
            WriteCV2Act ...
            DecompModeAct ...
            simCorrMethodAct ...
            simCorrThreshAct ...
            CorrCompCutOffAct ...
            SelCompCutOffAct ...
            LowMemAct ...
            CVRnormAct ];       

disallow = false;

%% Check whether all parameters are available
if (~sum(inp.GridAct(:)) && ~inp.HideGridAct) || isempty(inp.analind), disallow = true; end

if inp.loadparam == 1
    if ~isfield(inp,'optpreprocmat') || isempty(inp.optpreprocmat), disallow = true; end
    if ~isfield(inp,'optmodelmat') || isempty(inp.optmodelmat), disallow = true; end
end

if ~disallow, menustr = [menustr '|PROCEED >>>']; menuact = [menuact 99]; end

%% Display menu and act on user selections
nk_PrintLogo
mestr = 'Visualization module run-time configuration'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>>',parentstr);
if inp.batchflag == 2, act = nk_input(mestr, 0, 'mq', menustr, menuact); end

switch act
    case 0
        return
    case 1
        showmodalvec = []; analind = inp.analind; 
        if length(NM.analysis)>1, t_act = 1; brief = 1;
            while t_act>0
                [ t_act, analind, ~, showmodalvec, brief ] = nk_SelectAnalysis(NM, 0, navistr, analind, [], 1, showmodalvec, brief, [], 1); 
            end
            if ~isempty(analind), inp.analind = analind ; end
            nA = numel(inp.analind);
            if nA>1
                AS = nk_GetAnalysisStatus(NM, inp.analind);
                if ~AS.betweenfoldpermequal_cv
                    inp.HideGridAct = true; 
                else
                    inp.GridAct = NM.analysis{inp.analind(1)}.GDdims{1}.GridAct;
                    inp.HideGridAct = false;
                end
            else
                inp.HideGridAct = false;
                inp.GridAct = NM.analysis{inp.analind}.GDdims{1}.GridAct;
            end
        end
        
    case 2
        if inp.lfl == 1, inp.lfl = 2; else, inp.lfl = 1; end 
    case 3
        switch inp.lfl
            case 1
                if inp.ovrwrt == 1, inp.ovrwrt = 2; elseif inp.ovrwrt  == 2, inp.ovrwrt = 1; end
            case 2
                tdir = create_defpath(NM.analysis{inp.analind}, inp.DecompMode);
                inp.vismat = nk_GenDataMaster(NM.id, 'VISdatamat', CV, [], tdir);
        end
    case 4
        [operms,ofolds] = size(CV.TrainInd);
        tact = 1; while tact > 0 && tact < 10, [ tact, inp.GridAct ] = nk_CVGridSelector(operms, ofolds, inp.GridAct, 0); end
    case 6
        if inp.saveparam == 1, inp.saveparam = 2; elseif inp.saveparam == 2,  inp.saveparam = 1; end
    case 7
        if inp.loadparam == 1, inp.loadparam = 2; elseif inp.loadparam == 2,  inp.loadparam = 1; end
    case 8
        tdir = create_defpath(NM.analysis{inp.analind}, inp.DecompMode);
        optpreprocmat = nk_GenDataMaster(NM.id, 'OptPreprocParam', CV, [], tdir);
        if ~isempty(optpreprocmat), inp.optpreprocmat = optpreprocmat; end
    case 9
        tdir = create_defpath(NM.analysis{inp.analind}, inp.DecompMode);
        optmodelmat = nk_GenDataMaster(NM.id, 'OptModel', CV, [], tdir);
        if ~isempty(optmodelmat), inp.optmodelmat = optmodelmat; end
    case 10
        Ldef = []; Lsize = Inf; LNameDef = []; ActStr = 'Define'; 
        if isfield(inp,'extraL')
            if isfield(inp.extraL,'L')
                Ldef = inp.extraL.L; 
                Lsize = size(LDef,2); 
                ActStr = 'Modify'; 
            end
        end
        inp.extraL.L = nk_input([ ActStr ' extra label vector/matrix for permutation testing (numeric vector/matrix; for classification only binary labels will work)'],0,'e',Ldef,[size(NM.label,1),Lsize]);
        if isfield(inp.extraL,'Lnames'), LNameDef = inp.extraL.Lnames; end
        inp.extraL.Lnames = nk_input([ ActStr ' cell array of string descriptors for extra labels'],0,'e',LNameDef,[1 Lsize]);
   case 11
        del_extraL = nk_input('Do you really want to delete the extra labels?',0,'yes|no',[1,0]);
        if del_extraL, inp.extraL = []; end
    case 12
        if inp.CV1 == 1, inp.CV1 = 2; elseif inp.CV1 == 2,  inp.CV1 = 1; end
    case 13
        if inp.writeCV2 == 1, inp.writeCV2 = 2; elseif inp.writeCV2 == 2,  inp.writeCV2 = 1; end
    case 14
        if inp.lowmem == 1; inp.lowmem = 2; elseif inp.lowmem == 2, inp.lowmem = 1;  end
    case 15
        if inp.CVRnorm == 1; inp.CVRnorm = 2; elseif inp.CVRnorm == 2, inp.CVRnorm = 1;  end
    case 16
        if inp.DecompMode == 1; inp.DecompMode = 2; elseif inp.DecompMode == 2, inp.DecompMode = 1;  end
    case 17
       inp.simCorrThresh = nk_input('Define similarity cutoff for component realignment',0,'e',inp.simCorrThresh);
    case 18
        sim_methods = {'euclidean','pearson','spearman','cosine','bicor'};
        sim_methods_def = find(contains(sim_methods, inp.simCorrMethod));
        inp.simCorrMethod = char(nk_input('Define similarity method for component realignment',0, 'm', strjoin(sim_methods,'|'), sim_methods, sim_methods_def ));
    case 19
        inp.CorrCompCutOff = nk_input('Define similarity cutoff (0-1) for dropping/pruning factorization components',0,'e',inp.CorrCompCutOff );
    case 20
        inp.SelCompCutOff = nk_input('Define presence cutoff (0-1) for keeping factorization components',0,'e',inp.SelCompCutOff );
    case 99
        if MULTI.flag && MULTI.train && ~MULTI.BinBind, inp.multiflag = 1; else, inp.multiflag = 2; end
        nA = 1; if numel(inp.analind)>1, nA = numel(inp.analind); end
        for i=1:nA
            NM.runtime.curanal = inp.analind(i);
            inp = nk_GetAnalModalInfo_config(NM, inp);
            if inp.HideGridAct,[ ix, jx ] = size(NM.analysis{inp.analind(i)}.params.cv.TrainInd); inp.GridAct = true(ix,jx); end
            if ~isequaln(NM.analysis{inp.analind(i)}.params.label.label, NM.label) && ~NM.analysis{inp.analind(i)}.params.label.altlabelflag
                fprintf('\n');
                error('The labels with which your analysis was initialized are not identical with the main labels in your NM workspace!')
            end
            inp.analysis_id = NM.analysis{inp.analind(i)}.id;
            inp.saveoptdir = [ NM.analysis{inp.analind(i)}.rootdir filesep 'opt' ];
            NM.analysis{inp.analind(i)} = VisModelsPrep(NM, inp, NM.analysis{inp.analind(i)});
            nk_SetupGlobalVariables(NM.analysis{inp.analind(i)}.params, 'clear', 0); 
        end
        NM = rmfield(NM,'runtime');
end

function tdir = create_defpath(analysis, compwise)
 
rootdir = analysis.GDdims{1}.RootPath;
[ permfl, sigfl, permmode] = get_permflag ( analysis );

if permfl
    switch permmode 
        case 1
            visdir = 'VISUAL_L';
        case 2
            visdir = 'VISUAL_F';
        case 3
            visdir = 'VISUAL_LF';
        case 4
            visdir = 'VISUAL_COVAR';
    end
elseif sigfl
    visdir = 'VISUAL_P';
else
    visdir = 'VISUAL';
end
if compwise == 1
    visdir = [visdir 'c'];
end

tdir = fullfile(rootdir, visdir);
% _________________________________________________________________________
function analysis = VisModelsPrep(dat, inp1, analysis)
global CV COVAR MODEFL 

if inp1.multiflag   == 2, inp1.multiflag    = 0; end
if inp1.saveparam   == 2, inp1.saveparam    = 0; end
if inp1.loadparam   == 2, inp1.loadparam    = 0; end
if inp1.ovrwrt      == 2, inp1.ovrwrt       = 0; end

% Define fusion mode
FUSION = analysis.params.TrainParam.FUSION;    
F = analysis.params.TrainParam.FUSION.M;
nF = numel(F); if FUSION.flag < 3, nF = 1; end

% Create final decompfl boolean array
switch analysis.params.TrainParam.FUSION.flag
    case {0,1,2}
        PREPROCs = analysis.params.TrainParam.PREPROC(analysis.params.TrainParam.FUSION.M);
    case 3
        nM = numel(analysis.params.TrainParam.FUSION.M); PREPROCs = cell(1,nM);
        for n=1:nM
            PREPROCs{n} = analysis.params.TrainParam.STRAT{analysis.params.TrainParam.FUSION.M(n)}.PREPROC;
        end
end
inp1.decompfl = false(1, numel(PREPROCs));
for i=1:numel(PREPROCs)
    inp1.decompfl(i) = nk_DetIfDimRefInPREPROC(PREPROCs{i}, i);
end
if any(inp1.decompfl) && analysis.params.TrainParam.FUSION.flag==1
    inp1.decompfl = true(1,numel(inp1.decompfl));
end

% Define multi-label mode
if size(analysis.params.label.label,2)>1

if isfield(analysis.params.TrainParam, 'MULTILABEL')
    MULTILABEL = analysis.params.TrainParam.MULTILABEL;
else
    MULTILABEL.sel = 1:size(analysis.params.label.label,2);
    MULTILABEL.dim = size(analysis.params.label.label,2);
end
    MULTILABEL.flag = true;
else
    MULTILABEL.flag = false;
    MULTILABEL.dim = 1;
end
[nL,sL] = nk_GetLabelDim(MULTILABEL);

switch inp1.lfl
    case 1
        % *********** CONSTRUCT VISUALIZATION ANALYSIS INPUT STRUCTURE ************
        inp1.analmode    = 0;
        inp1.covstr = '';
        if ~isempty(COVAR)
            inp1.covstr = dat.covnames{1};
            for j=2:length(COVAR)
                inp1.covstr = [inp1.covstr ', ' dat.covnames{j}];
            end
        end        
    case 2
        inp1.analmode = 1;
        inp1.covstr = '';
end

inp1.nclass = 1;if strcmp(MODEFL,'classification'), inp1.nclass = numel(CV.class{1,1}); end
inp1.rootdir = create_defpath(analysis, inp1.DecompMode);
inp1.maindir = analysis.rootdir;
if ~exist(inp1.rootdir,'dir'), mkdir(inp1.rootdir); end

%%%%%%%%%%%%%%%%%%%%%%% RUN VISUALIZATION ANALYSIS  %%%%%%%%%%%%%%%%%%%%%%%
analysis.visdata = cell(nF,nL);
for i = 1:nF
    inp2            = nk_DefineFusionModeParams(dat, analysis, F, nF, i);
    inp2.labels     = analysis.params.label.label;
    inp             = catstruct(inp1,inp2); clear inp2;
    inp.curlabel    = 1;
    VIS = analysis.params.TrainParam.VIS{analysis.params.TrainParam.FUSION.M(i)};
    % Per default do not activate normalization of the weight vector
    if isfield(VIS,'norm'), inp.norm = VIS.norm; else, inp.norm = 2; end
    for j = 1:nL
        if MULTILABEL.flag && nL>1 && sL(j)>1 
            fprintf('\n\n====== Working on label #%g ======= ',sL(j)); inp.curlabel = j; 
        end
        %if inp.DecompMode == 1
        vis = nk_VisModelsC(inp, dat.id, inp.GridAct);
      
        % we have to map the results to the visdata container in a uniform
        % way to ease results inspection later.
        switch FUSION.flag
            case {0,3}
                analysis.visdata{i,j} = vis{1};
            case {1,2}
                for k=1:numel(F)
                    analysis.visdata{k,j} = vis{k};
                end
        end
    end
end
% _________________________________________________________________________

function [ permfl, sigfl, permmode] = get_permflag ( analysis )

permfl = false; sigfl = false; permmode =[]; 
varind = analysis.params.TrainParam.FUSION.M; 
for i=1:numel(varind)
    if isfield(analysis.params.TrainParam.VIS{varind(i)},'PERM') 
        if analysis.params.TrainParam.VIS{varind(i)}.PERM.flag
            permfl = true; 
            permmode = analysis.params.TrainParam.VIS{varind(i)}.PERM.mode;
        elseif analysis.params.TrainParam.VIS{varind(i)}.PERM.sigflag
            sigfl = true;
        end
        break;
    end
end

