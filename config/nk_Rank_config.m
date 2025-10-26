function [RANK, PX] = nk_Rank_config(RANK, PX, NM, varind, defaultsfl, parentstr)

if ~exist('defaultsfl','var') || isempty(defaultsfl),  defaultsfl = 0; end
ranktype            = 1;
weightmethod        = 1;
label               = NM.label;
labeldesc           = 'NM target label';
algostr             = 'pearson';
vartype             = NM.datadescriptor{varind}.type;
ReplInfwithMax      = 1;
TakeAbs             = 1;
ReplZeroNaNwithRealMin = 1;
WeightScale         = 1;
act = 0;
BINMOD              = NM.TrainParam.PREPROC{varind}.BINMOD;

if ~defaultsfl

    if ~isfield(RANK,'ranktype'),               RANK.ranktype = ranktype; end
    if ~isfield(RANK,'weightmethod'),           RANK.weightmethod = weightmethod; end
    if ~isfield(RANK,'label');                  RANK.label = label; RANK.labeldesc = labeldesc;end
    if ~isfield(RANK,'algostr'),                RANK.algostr = algostr; RANK.Pearson = 1; end
    if ~isfield(RANK,'TakeAbs'),                RANK.TakeAbs = TakeAbs; end
    if ~isfield(RANK,'Scale'),                  RANK.Scale = WeightScale; end
    if ~isfield(RANK,'ReplZeroNaNwithRealMin'); RANK.ReplZeroNaNwithRealMin = ReplZeroNaNwithRealMin; end
    if ~isfield(RANK,'ReplInfwithMax'),         RANK.ReplInfwithMax = ReplInfwithMax ; end
    if ~exist('PX','var'),                      PX = []; end
    if RANK.weightmethod == 1, weightstr = 'upweight features'; else, weightstr = 'downweight features'; end
    yesno = {'yes','no'};

    if strcmp(RANK.algostr,'extern') 
        extfilstr = '';
        if isfield(RANK,'F')
            [~,extfilstr] = fileparts(RANK.F);
            extfilstr = sprintf(' File: %s,', extfilstr);
        end
        if isfield(RANK,'EXTERN')
           if height(RANK.EXTERN)>1
               extdat = sprintf(' Matrix (dims: %g x %g) ', size(RANK.EXTERN,1), size(RANK.EXTERN,2));
           else
               extdat = sprintf(' Vector (dims: %g) ', numel(RANK.EXTERN));
           end
        elseif isfield(RANK,'V') && RANK.V==1
            [~,extfilstr] = fileparts(NM.datadescriptor{varind}.input_settings.Pw);
            extfilstr = sprintf(' NM weight map: %s,', extfilstr);
            if height(NM.datadescriptor{varind}.Yw)>1
               extdat = sprintf(' Matrix (dims: %g x %g) ', size(NM.datadescriptor{varind}.Yw,1), size(NM.datadescriptor{varind}.Yw,2));
            else
               extdat = sprintf(' Vector (dims: %g) ', numel(NM.datadescriptor{varind}.Yw));
            end
        else
            extdat = ' undefined ';
        end
        extstr = sprintf('External ranking (%s%s)', extfilstr, extdat);
    else
        extstr = 'External Ranking'; 
    end

    nk_PrintLogo
    
    mestr = 'Rank / Weight features'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 
    if strcmp(RANK.algostr,'extern')
        act = nk_input(mestr,0,'mq', ...
            [sprintf('Choose algorithm and specify its parameters [ %s ]|', extstr) ...
             sprintf('Up- or downweight predictive features [ %s ]|', weightstr) ...
             sprintf('Postprocessing: Take absolute of ranking vector [ %s ]|', yesno{RANK.TakeAbs}) ...
             sprintf('Postprocessing: Scale ranking vector to (0,1) [ %s ]|', yesno{RANK.Scale}) ...
             sprintf('Postprocessing: Replace 0s and NaNs with realmin [ %s ]|', yesno{RANK.ReplZeroNaNwithRealMin}) ...
             sprintf('Postprocessing: Replace Infs with max of rank vector [ %s ] ', yesno{RANK.ReplInfwithMax}) ...
             ], [1 3 4 5 6 7]);
    else
        switch RANK.algostr
            case 'pearson'
                if RANK.Pearson ==1, algostr = 'Pearson'; else, algostr = 'Spearman'; end
            otherwise
                algostr = RANK.algostr;
        end
        switch RANK.algostr
            case 'pls'
                act = nk_input(mestr,0,'mq', ...
                    [sprintf('Choose algorithm and specify its parameters [ %s ]|', algostr), ...
                     sprintf('Define PLS parameters ...|') ...
                     sprintf('Postprocessing: Take absolute of ranking vector [ %s ]|', yesno{RANK.TakeAbs}) ...
                     sprintf('Postprocessing: Scale ranking vector to (0,1) [ %s ]|', yesno{RANK.Scale}) ...
                     sprintf('Postprocessing: Replace 0s and NaNs with realmin in ranking vector [ %s ]|', yesno{RANK.ReplZeroNaNwithRealMin}) ...
                     sprintf('Postprocessing: Replace Infs with max of ranking vector [ %s ] ', yesno{RANK.ReplInfwithMax}) ],[1 2 4 5 6 7]);
            otherwise
                act = nk_input(mestr,0,'mq', ...
                    [sprintf('Choose algorithm and specify its parameters [ %s ]|', algostr)  ...
                     sprintf('Define targets for ranking/weighting [ %s ]|', RANK.labeldesc) ...
                     sprintf('Up- or downweight predictive features [ %s ]|', weightstr) ...
                     sprintf('Postprocessing: Take absolute of ranking vector [ %s ]|', yesno{RANK.TakeAbs}) ...
                     sprintf('Postprocessing: Scale ranking vector to (0,1) [ %s ]|', yesno{RANK.Scale}) ...
                     sprintf('Postprocessing: Replace 0s and NaNs with realmin in ranking vector [ %s ]|', yesno{RANK.ReplZeroNaNwithRealMin}) ...
                     sprintf('Postprocessing: Replace Infs with max of ranking vector [ %s ] ', yesno{RANK.ReplInfwithMax}) ],1:7);
        end
    end

    switch act
        case 1
            if exist('PX','var'), PX = []; end
            
            %% Ranking algorithm list depending on framework
            rstr_cl = ['Pearson correlation|' ...
                       'Spearman correlation|' ...
                       'G-flip|' ...
                       'Simba|' ... %'Large-Margin Nearest Neighbour Weighting (LMNN)|' ...
                       'IMRelief|' ...
                       'Relief for classification|' ...
                       'Linear SVC (LIBSVM)|' ...
                       'Linear SVC (LIBLINEAR)|' ...
                       'F-Score|' ...
                       'AUC|' ...
                       'FEAST|' ...
                       'ANOVA|' ...
                       'PLS|' ...
                       extstr];
            rsel_cl = {'pearson','spearman','gflip','simba','imrelief','relief','libsvm','liblin','fscore','auc','feast','anova','pls','extern'};
            
            rstr_reg = ['Pearson correlation|' ...
                        'Spearman correlation|' ...
                        'RGS|' ...
                        'Linear SVR (LIBSVM)|' ...
                        'Linear SVR (LIBLINEAR)|' ...
                        'Relief for regression|' ...
                        'ANOVA|', ...
                        'PLS|', ...
                        extstr];
            rsel_reg = {'pearson','spearman','rgs','libsvm','liblin','relief','anova','pls','extern'};
    
            switch RANK.ranktype
                case 1
                    if  NM.TrainParam.LABEL.flag==1
                        modeflag = NM.TrainParam.LABEL.newmode;
                    else
                        modeflag = NM.modeflag;
                    end
                    switch modeflag
                        case 'classification'
                            menuact = rstr_cl; menusel = rsel_cl;
                        case 'regression'
                            menuact = rstr_reg; menusel = rsel_reg;
                    end
                case 2
                    menuact = rstr_cl; menusel = rsel_cl;
                case 3
                    menuact = rstr_reg; menusel = rsel_reg;
            end

            algostr = char(nk_input('Select ranking algorithm',0,'mq', menuact, menusel));

            if ~strcmp(algostr,'BACK')
                RANK.algostr = algostr;
                switch algostr
                    case 'gflip'
                        ngroups = numel(unique(RANK.label));
                        if isfield(RANK,'gflip') 
                            gflip = RANK.gflip; 
                        else
                            gflip = nk_Gflip_config([], 1, [], ngroups);
                        end
                        gflip = nk_Gflip_config(gflip, 0, [], ngroups); RANK.gflip = gflip;
                        if isfield(gflip.gflip,'extra_param') && ...
                            isnumeric(gflip.gflip.extra_param.beta),                 PX = nk_AddParam(gflip.gflip.extra_param.beta, 'Beta', 1, PX, 'replace');
                        end
                        
                    case 'simba'
                        ngroups = numel(unique(RANK.label));
                        if isfield(RANK,'simba') 
                            simba = RANK.simba; 
                        else
                            simba = nk_Simba_config([], 1,[],ngroups, BINMOD);
                        end
                        simba = nk_Simba_config(simba, 0,[],ngroups, BINMOD); RANK.simba = simba;
                        if isfield(simba.simba,'extra_param') && ...
                                isnumeric(simba.simba.extra_param.beta),             PX = nk_AddParam(simba.simba.extra_param.beta, 'Beta',1, PX, 'replace');
                        end
    
                    case 'idetect'
                        if isfield(RANK,'idetect') 
                            idetect = RANK.idetect; setupfl = false;
                        else
                            idetect = []; setupfl = true; 
                        end
                        RANK.idetect = nk_IMRelief_config(idetect, [], setupfl); 
                        PX = nk_AddParam(RANK.idetect.sigma, 'Sigma',1 ,PX, 'replace'); PX = nk_AddParam(RANK.idetect.lambda, 'Lambda',1, PX); 
                        
                    case 'imrelief'
                        if isfield(RANK,'imrelief') 
                            imrelief = RANK.imrelief; setupfl = false;
                        else
                            imrelief = []; setupfl = true; 
                        end
                        RANK.imrelief = nk_IMRelief_config(imrelief, [], setupfl); 
                        PX = nk_AddParam(RANK.imrelief.sigma, 'Sigma',1 ,PX, 'replace'); PX = nk_AddParam(RANK.imrelief.lambda, 'Lambda',1, PX); 
                        
                    case {'libsvm','liblin'}
                        if ~isfield(RANK,'SVM'), RANK.SVM = []; end
                        RANK.SVM.prog = upper(RANK.algostr); 
                        switch RANK.ranktype
                            case 1
                                RANK.SVM.modeflag = NM.modeflag;
                                RANK.SVM.evalfunc = NM.TrainParam.SVM.GridParam;
                            case 2
                                RANK.SVM.modeflag = 'classification'; 
                                RANK.SVM.evalfunc = 14;
                            case 3
                                RANK.SVM.modeflag = 'regression';
                                RANK.SVM.evalfunc = 18;
                        end
                        % Only linear kernel is permitted
                        RANK.SVM.kernel.kerndef = 1;
                        switch RANK.algostr
                            case 'libsvm'
                                act =1; while act, [act, RANK.SVM] = nk_LIBSVM_config(RANK.SVM, RANK.SVM, [],[], navistr, RANK.SVM.modeflag); end
                                RANK.SVM.kernel.kernstr = ' -t 0';
                            case 'liblin'
                                act = 1; while act, [act, RANK.SVM] = nk_LIBLIN_config(RANK.SVM.modeflag, RANK.SVM, [], navistr); end
                                RANK.SVM.kernel.kernstr = 'lin';
                                if numel(RANK.SVM.LIBLIN.tolerance)>0
                                    PX = nk_AddParam(RANK.SVM.LIBLIN.tolerance, 'TolRank', 1, PX, 'replace');
                                end
                        end
                        ctype = nk_GetLIBSVMClassType(RANK.SVM);
                        % Check if regression parameters are needed 
                        rtype = nk_GetLIBSVMRegrType(RANK.SVM);
                        switch rtype
                            case 1
                                if isfield(RANK.SVM,'EpsParam'), EpsParam = RANK.SVM.EpsParam; else, EpsParam = 0.1; end
                                RANK.SVM.EpsParam = nk_input('Define Epsilon parameter(s)',0,'e',EpsParam);     PX = nk_AddParam(RANK.SVM.EpsParam, 'EpsilonRank', 1, PX);
                                
                            case 2
                                if isfield(RANK.SVM,'NuParam'), NuParam = RANK.SVM.NuParam; else, NuParam = 0.5; end
                                RANK.SVM.NuParam = nk_input('Define Nu parameter(s)',0,'e',NuParam);            PX = nk_AddParam(RANK.SVM.NuParam, 'NuRank', 1, PX);
                                
                        end
                        % This is the slack / nu-SVC parameter of the SVM
                        Slackdesc = 'SlackRank'; 
                        if isfield(RANK.SVM,'SlackParam'), SlackParam = RANK.SVM.SlackParam; else, SlackParam = 1; end
                        RANK.SVM.SlackParam = nk_input(['Define ' Slackdesc ' parameter(s)'],0,'e', SlackParam); PX = nk_AddParam(RANK.SVM.SlackParam, Slackdesc, 1, PX);
                       
                    case 'rgs'
                        if ~isfield(RANK,'RGS'), RANK = nk_RGS_config(RANK, true); end
                        RANK = nk_RGS_config(RANK);                                                     
                        if isfield(RANK.RGS.extra_param,'k') && isnumeric(RANK.RGS.extra_param.k)
                            PX = nk_AddParam(RANK.RGS.extra_param.k, 'K', 1, PX, 'replace'); 
                        else
                            PX = nk_AddParam([], [], [], [], 'reset');
                        end
                        if isfield(RANK.RGS.extra_param,'beta') && isnumeric(RANK.RGS.extra_param.beta)
                            PX = nk_AddParam(RANK.RGS.extra_param.beta, 'Beta', 1, PX); 
                        end
                    case 'feast'
                        act=1; while act > 0, [act, RANK ] = nk_FEAST_config(RANK, 1, navistr); end
                        PX = nk_AddParam(RANK.FEAST.NumFeat, 'NumFeat', 1, PX); 
                    case 'relief'
                        RANK.Relief.k = nk_input('Define number(s) of nearest neigbours for RELIEF',0,'i',10,1); PX = nk_AddParam(RANK.Relief.k, 'K', 1, PX); 
                    case 'fscore'
                        FScoreDef = 1; if isfield(RANK,'FScoreType'), FScoreVals = {'mean','median'}; FScoreDef = find(contains(FScoreVals,RANK.FScoreType)); end
                        RANK.FScoreType = char(nk_input('Define F-score computation method',0,'m','mean(std)|median(IQR)',{'mean','median'},FScoreDef)); 
                        FScoreWeightDef = 1; if isfield(RANK,'WeightMode'), FScoreWeightVals = {'none','auto'}; FScoreWeightDef = find(contains(FScoreWeightVals,RANK.WeightMode)); end
                        RANK.WeightMode = char(nk_input('Define F-score weighting mode in case of unbalanced classes',0,'m', ...
                            'no weighting|automatic weighting',{'none','auto'},FScoreWeightDef));
                        if strcmp(RANK.WeightMode,'manual')
                            RANK.Weights = nk_input('Define sample weight vector',0,'e');
                        else
                            RANK.Weights = [];
                        end
                        FScoreBootDef = 0; if isfield(RANK,'B'), FScoreBootDef = RANK.B; end
                        RANK.B = nk_input('Define number of bootstrap iteration for stablity-enhanced F-score computation (0=bootstrapping disabled)',0,'i',FScoreBootDef );
                        RANK.Nuisance = [];
                    case 'pls'
                        if ~isfield(RANK,'PLS'), [~, RANK.PLS ] = nk_PLS_config(NM, [], [], true); end
                    case 'extern' 
                        if vartype
                            if isfield(NM.datadescriptor{varind},'Yw')
                                readimg = nk_input('Do you want to read-in external ranking map',0,'mq', ...
                                    ['Use weighting image in NM|' ...
                                     'Import external weighting map from file|' ...
                                     'Read-in weighting vector from MATLAB workspace'],[2,1,0],1);
                            else
                                 readimg = nk_input('Do you want to read-in external ranking map',0,'mq', ...
                                    ['Import external weighting map from file|' ...
                                     'Read-in weighting vector from MATLAB workspace'],[1,0],1);
                            end
                        else
                            readimg = false;
                        end
                        switch readimg
                            case 0
                                RANK.EXTERN = nk_input('Define external map/vector',0,'e',[],[size(NM.badcoords{varind},2)]);
                            case 1
                                % Currently only NIFTI/Analyze supported
                                imgtype = NM.datadescriptor{varind}.input_settings.datasource;
                                RANK.V  = [];

                                [RANK.F, RANK.V{1}] = nk_FileSelector(1,imgtype,'Select Ranking Map','.*');
                                switch imgtype
                                    case {'spm','nifti'}
                                         Thresh = NM.datadescriptor{varind}.input_settings.Thresh;
                                         Vm = spm_vol(NM.brainmask{varind}); 
                                         [RANK.EXTERN, RANK.THRESH] = nk_ReturnSubSpaces(RANK.V, Vm, 1, 1, Thresh);
                                    case 'surf'
                                         if isfield(RANK.V{1},'cdata')
                                            RANK.EXTERN = RANK.V{1}.cdata;
                                         else
                                            RANK.EXTERN = MRIread(RANK.F);
                                         end
                                end
                            case 2
                                nPw = size(NM.datadescriptor{varind}.input_settings.Pw,1);
                                if nPw>1
                                    mn_sel = strjoin(cellstr(NM.datadescriptor{varind}.input_settings.Pw),'|');
                                    mn_act = 1:nPw;
                                    RANK.V = nk_input('Select weighting image',0,'m',mn_act,mn_sel,1);
                                else
                                    RANK.V = 1;
                                end
                                if isfield(RANK,'EXTERN'), RANK = rmfield(RANK,'EXTERN'); end
                                if isfield(RANK,'F'), RANK = rmfield(RANK,'F'); end
                        end
                end
            end
            
        case 2
            switch RANK.algostr
                
                case 'pls'
                    PX = nk_AddParam([], [], [], PX,'reset');
                    if ~isfield(RANK,'PLS'), [~, RANK.PLS ] = nk_PLS_config(NM, [], [], true); end
                    act = 1; while act >0, [act, RANK.PLS, PX ] = nk_PLS_config(NM, RANK.PLS, PX, false, navistr); end  
                    RANK.label = RANK.PLS.V;
                    switch RANK.PLS.uselabel
                        case 1
                            RANK.labeldesc = 'NM target label';
                        case 2
                            RANK.labeldesc = 'NM covariate matrix';
                        case 3
                            RANK.labeldesc = 'NM user-defined matrix';
                    end
                otherwise
                    
                    %% Label definition
                    if isfield(RANK,'label')
                        flg = nk_input('Target label vector found',0,'Use existing|Define new one',[0,1],1);
                    else
                        flg = true;
                    end

                    if flg 
                        RANK.ranktype = nk_input('Define target labels',0,'m', ...
                                            ['NM target labels|'...
                                             'Categorical data|' ...
                                             'Continuous data'],[1,2,3],ranktype);

                        if RANK.ranktype > 1
                            switch RANK.algostr
                                case 'anova'
                                    RANK.label = nk_input('Define design matrix or batch effects vector for ANOVA',0,'e',[],[size(NM.label,1),Inf]); lbstr = 'design matrix';
                                otherwise
                                    RANK.label = nk_input('Define target label vector',0,'e',[],[size(NM.label,1),1]); lbstr = 'label vector';
                            end
                            RANK.labeldesc = nk_input(['Give a short description of the ' lbstr ],0,'s');
                        else
                            switch NM.TrainParam.LABEL.flag
                                case 1
                                    RANK.label = NM.TrainParam.LABEL.newlabel;
                                    RANK.labeldesc = sprintf('NM alternative label: %s', NM.TrainParam.LABEL.newlabelname);
                                otherwise
                                    if isfield(NM.TrainParam,'MULTILABEL')
                                        RANK.label = NM.label(:, NM.TrainParam.MULTILABEL.sel );
                                    else
                                        RANK.label = NM.label;
                                    end
                                    RANK.labeldesc = 'NM target label';
                            end
                            
                        end
                    end
                    
            end
            
            if RANK.ranktype == 3
                flg = nk_input('Weight feature using only one specific subgroup?',0,'yes|no',[1,0],0);
                if flg 
                    RANK.glabel = nk_input('Define index vector for subgroup idenitification (ones = use / zeros = not use)',0,'e',[],[numel(NM.label),1]);
                else
                    if isfield(RANK,'glabel'), RANK= rmfield(RANK,'glabel'); end
                end
            else
                if isfield(RANK,'glabel'), RANK= rmfield(RANK,'glabel'); end
            end

        case 3
            if RANK.weightmethod==1, RANK.weightmethod=2; else, RANK.weightmethod=1; end
        case 4
            if RANK.TakeAbs==1, RANK.TakeAbs=2; else, RANK.TakeAbs=1; end
        case 5
            if RANK.Scale==1, RANK.Scale=2; else, RANK.Scale=1; end
        case 6
            if RANK.ReplZeroNaNwithRealMin==1, RANK.ReplZeroNaNwithRealMin=2; else, RANK.ReplZeroNaNwithRealMin=1; end
        case 7
            if RANK.ReplInfwithMax==1, RANK.ReplInfwithMax=2; else, RANK.ReplInfwithMax=1; end
    end
else
    RANK.ranktype       = ranktype;
    RANK.weightmethod   = weightmethod;
    switch NM.TrainParam.LABEL.flag
        case 1
            RANK.label = NM.TrainParam.LABEL.newlabel;
            RANK.labeldesc = sprintf('NM alternative label: %s', NM.TrainParam.LABEL.newlabelname);
        otherwise
            RANK.label          = NM.label;
            RANK.labeldesc      = 'NM target label';
    end
    RANK.rankmethod             = 8;
    RANK.algostr                = 'pearson';
    RANK.TakeAbs                = TakeAbs;
    RANK.Scale                  = WeightScale;
    RANK.ReplZeroNaNwithRealMin = ReplZeroNaNwithRealMin;
    RANK.ReplInfwithMax         = ReplInfwithMax;
end
if act, [RANK, PX] = nk_Rank_config(RANK, PX, NM, varind, [], parentstr); end
