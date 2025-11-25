function [CURACT, act ] = nk_UnivCorrProcs_config(NM, CURACT, varind, parentstr, defaultsfl)
global EXPERT

if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end
% ======== Defaults ========
METHOD_DEF              = 1;
COVAR_DEF               = 1;
COVDIR_DEF              = 1;
INTERCEPT_DEF           = 2;
BETAEXT_DEF             = [];
MBATCHUSE_DEF           = 1;
MBATCH_DEF              = [];
REFBATCH_DEF            = [];    % numeric label of the reference batch (empty = pooled)
MCOVARUSE_DEF           = 1;
MCOVAR_DEF              = [];
MCOVARREM_DEF           = [];
MCOVARLABEL_DEF         = 1;
COVBAT_MODE_DEF         = 1;     % 1 = Simple ComBat, 2 = ComBat + CovBat
COVBAT_K_DEF            = [];    % integer PCs (used if non-empty)
COVBAT_VAR_DEF          = 0.95;  % cumulative variance in [0,1] (used if K is empty)
DIST_DEF                = 1;
LAMBDA_DEF              = 0.8;
SUBGROUP_DEF            = [];
MCOVAR_TYPE_DEF         = {};    % cellstr, per conceptual covariate
MCOVAR_SPLINE_DF_DEF    = [];    % numeric, per conceptual covariate (0/1 = none, >=2 = df)
UNSEENBATCH_MODE_DEF    = 1;     % 1=EB, 2=no-shrink, 3=strong-shrink
UNSEENBATCH_ALPHA_DEF   = 0.7;   % for strong-shrink extra shrinkage

if ~defaultsfl
    
    %  ========================= Get information from CURACT if available  ========================= 
    if isfield(CURACT,'METHOD'),           METHOD_DEF                = CURACT.METHOD;            end
    if isfield(CURACT,'COVAR'),            COVAR_DEF                 = CURACT.COVAR;             end
    if isfield(CURACT,'SUBGROUP'),         SUBGROUP_DEF              = CURACT.SUBGROUP;          end
    if isfield(CURACT,'INTERCEPT'),        INTERCEPT_DEF             = CURACT.INTERCEPT;         end
    if isfield(CURACT,'COVDIR'),           COVDIR_DEF                = CURACT.COVDIR;            end
    if isfield(CURACT,'BETAEXT'),          BETAEXT_DEF               = CURACT.BETAEXT;           end
    if isfield(CURACT,'MBATCHUSE'),        MBATCHUSE_DEF             = CURACT.MBATCHUSE;         end
    if isfield(CURACT,'MBATCH'),           MBATCH_DEF                = CURACT.MBATCH;            end
    if isfield(CURACT,'REFERENCE_LEVEL'),  REFBATCH_DEF              = CURACT.REFERENCE_LEVEL;   end  
    if isfield(CURACT,'MCOVARUSE'),        MCOVARUSE_DEF             = CURACT.MCOVARUSE;         end
    if isfield(CURACT,'MCOVAR'),           MCOVAR_DEF                = CURACT.MCOVAR;            end
    if isfield(CURACT,'MCOVARREM'),        MCOVARREM_DEF             = CURACT.MCOVARREM;         end
    if isfield(CURACT,'MCOVARLABEL'),      MCOVARLABEL_DEF           = CURACT.MCOVARLABEL;       end
    if isfield(CURACT,'COVBAT_MODE'),      COVBAT_MODE_DEF           = CURACT.COVBAT_MODE;       end
    if isfield(CURACT,'COVBAT_K'),         COVBAT_K_DEF              = CURACT.COVBAT_K;          end
    if isfield(CURACT,'COVBAT_VAR'),       COVBAT_VAR_DEF            = CURACT.COVBAT_VAR;        end
    if isfield(CURACT,'DISTYPE'),          DIST_DEF                  = CURACT.DISTYPE;           end
    if isfield(CURACT,'LAMBDA'),           LAMBDA_DEF                = CURACT.LAMBDA;            end
    if isfield(CURACT,'MCOVAR_TYPE'),      MCOVAR_TYPE_DEF           = CURACT.MCOVAR_TYPE;       end
    if isfield(CURACT,'MCOVAR_SPLINE_DF'), MCOVAR_SPLINE_DF_DEF      = CURACT.MCOVAR_SPLINE_DF;  end
    if isfield(CURACT,'UNSEENBATCH_MODE'), UNSEENBATCH_MODE_DEF      = CURACT.UNSEENBATCH_MODE;  end
    if isfield(CURACT,'UNSEENBATCH_ALPHA'),UNSEENBATCH_ALPHA_DEF     = CURACT.UNSEENBATCH_ALPHA; end
    COVAR_STR = strjoin(NM.covnames(COVAR_DEF),', ');
    BETAEXTUSE_MNU = []; BETAEXT_MNU = [];
    menuact = 1;
    
     % ===================================== PARTIAL CORRELATION SETUP =====================================
    if METHOD_DEF == 1
        % Partial Correlations
        menuact = [ menuact 2 3 4 ];
        METHOD_STR = 'Partial Correlations';
        if INTERCEPT_DEF == 2,          INTERCEPT_STR = 'yes'; else,     INTERCEPT_STR = 'no'; end
        if COVDIR_DEF == 1,             COVDIR_STR = 'attenuate'; else,  COVDIR_STR = 'increase'; end
         if ~isempty(BETAEXT_DEF)   
            BETAEXT_STR = 'yes';    
            if isfinite(BETAEXT_DEF) 
                BETAEXT_MAT = sprintf('%g x %g matrix defined', size(BETAEXT_DEF,1), size(BETAEXT_DEF,2)); 
            else
                BETAEXT_MAT = 'undefined'; 
            end
            
            BETAEXT_MNU = sprintf('|Define beta coefficients [ %s ]',BETAEXT_MAT);
            menuact = [ menuact 19 20 ];
        else
            BETAEXT_STR = 'no';    
            menuact = [ menuact 19 ];
        end
        BETAEXTUSE_MNU = sprintf('|Use externally-computed beta coefficients [ %s ]', BETAEXT_STR );
    
    % ========================================= COMBAT SETUP =========================================
    elseif METHOD_DEF==2

        % ComBat    
        METHOD_STR = 'ComBat';
        MBATCHUSE_STR = 'no'; MBATCH_STR = 'undefined'; MBATCH_MNU = ''; REFBATCH_MNU = ''; 
        MCOVARUSE_STR = 'no'; MCOVARLABEL_MNU = []; MCOVAR_MNU = []; MCOVARREM_MNU = []; MCOVARTYPE_MNU=[]; MCOVARSPLINE_MNU = [];
        menuact = [ menuact 5 ]; 
        if MBATCHUSE_DEF == 1
            MBATCHUSE_STR = 'yes'; 
            if ~isempty( MBATCH_DEF ), MBATCH_STR = NM.covnames{MBATCH_DEF}; end
            
            % Batch effects menu entry
            MBATCH_MNU = sprintf('|Select batch effects vector (= categorical variable) in NM covariate matrix [ %s ]', MBATCH_STR); 
            menuact = [ menuact 6 ];
            
            % reference batch menu entry        
            if isempty(REFBATCH_DEF), REF_STR = 'pooled (default)'; else, REF_STR = num2str(REFBATCH_DEF); end
            REFBATCH_MNU = sprintf('|Set reference batch label [ %s ]', REF_STR);

            % Action ids for batch management
            menuact = [ menuact 7 ];   %  
        end
        
        MBATCHUSE_MNU = sprintf('|Correct for batch effects using ComBat [ %s ]', MBATCHUSE_STR); 
        
        menuact = [ menuact 8 ];
        if MCOVARUSE_DEF == 1; MCOVARUSE_STR = 'yes'; end
        MCOVARUSE_MNU = sprintf('|Include covariate effects into ComBat equation [ %s ]', MCOVARUSE_STR); 

        if MCOVARUSE_DEF == 1

            if MCOVARLABEL_DEF == 1, MCOVARLABEL_STR = 'yes'; else, MCOVARLABEL_STR = 'no'; end
            MCOVARLABEL_MNU = sprintf('|Add label(s) to covariate variance retainment [ %s ]', MCOVARLABEL_STR);
            menuact = [ menuact 9 ]; 
            
            % Deal with covariates & label
            MCOVAR_STR = 'none';
            if ~isempty( MCOVAR_DEF ), MCOVAR_STR = strjoin(NM.covnames(MCOVAR_DEF),', '); end
            % Covariates other than the label
            MCOVAR_MNU = sprintf('|Select covariates other than the label(s) [ %s ]', MCOVAR_STR);
            menuact = [ menuact 10 ];
            if ~isempty(MCOVAR_DEF)
                % "Covariate effects to be removed" menu entry
                if isempty(MCOVARREM_DEF) 
                    MCOVARREM_STR = 'none'; 
                else
                    MCOVARREM_STR = strjoin(NM.covnames(MCOVAR_DEF(MCOVARREM_DEF)),', ') ; 
                end
                MCOVARREM_MNU = sprintf('|Select covariate effects to be removed [ %s ]', MCOVARREM_STR); 
                menuact = [ menuact 11 ]; 
                MCOVARTYPE_MNU   = '';
                MCOVARSPLINE_MNU = '';
        
                % --- Measurement scale for MCOVAR covariates ---
                if MCOVARUSE_DEF == 1 && ~isempty(MCOVAR_DEF)
        
                    % ensure MCOVAR_TYPE_DEF matches current MCOVAR_DEF
                    if isempty(MCOVAR_TYPE_DEF) || numel(MCOVAR_TYPE_DEF) ~= numel(MCOVAR_DEF)
                        MCOVAR_TYPE_DEF = cell(1, numel(MCOVAR_DEF));
                        for i = 1:numel(MCOVAR_DEF)
                            vec = nm_get_covariate_vector(NM, MCOVAR_DEF(i));
                            MCOVAR_TYPE_DEF{i} = infer_covtype(vec);  
                        end
                    end
        
                    % ensure spline df vector has correct length
                    if isempty(MCOVAR_SPLINE_DF_DEF) || numel(MCOVAR_SPLINE_DF_DEF) ~= numel(MCOVAR_DEF)
                        MCOVAR_SPLINE_DF_DEF = zeros(1, numel(MCOVAR_DEF));
                    end
        
                    % build annotated label: covname [T:df]
                    typedNames = cell(1,numel(MCOVAR_DEF));
                    for i = 1:numel(MCOVAR_DEF)
                        nm_i = NM.covnames{MCOVAR_DEF(i)};
                        t_i  = MCOVAR_TYPE_DEF{i};
                        ch   = nm_typechar(t_i);                             
                        df_i = MCOVAR_SPLINE_DF_DEF(i);
                        if df_i >= 2
                            typedNames{i} = sprintf('%s (%s, spline df=%d)', nm_i, ch, df_i);
                        else
                            typedNames{i} = sprintf('%s (%s)', nm_i, ch);
                        end
                    end
        
                    MCOVARTYPE_MNU   = sprintf('|Set measurement scale of covariates [ %s ]', strjoin(typedNames, ', '));
                    MCOVARSPLINE_MNU = sprintf('|Configure spline modelling for covariates [ %s ]', 'press to edit');
        
                    % we will add them to menuact below as actions 22 and
                    menuact = [ menuact 22 23];
                end
            end
        end

        % --- CovBat variant display strings ---
        if COVBAT_MODE_DEF == 1
            COVBAT_MODE_STR = 'Simple ComBat';
        else
            COVBAT_MODE_STR = 'ComBat + CovBat';
        end
        
        if ~isempty(COVBAT_K_DEF)
            k_str = sprintf('%d', COVBAT_K_DEF);
        else
            k_str = 'empty';
        end
        
        if ~isempty(COVBAT_VAR_DEF)
            var_str = sprintf('%2f', COVBAT_VAR_DEF);
        else
            var_str = 'empty';
        end

        if isempty(COVBAT_VAR_DEF) && isempty(COVBAT_K_DEF)
            COVBAT_VAR_DEF = 0.95;
            var_str = sprintf('%2f (default reset because K and var_expl cannot be both empty)', COVBAT_VAR_DEF);
        end

        COVBAT_MODE_MNU = sprintf('|ComBat variant [ %s ]', COVBAT_MODE_STR);
        if COVBAT_MODE_DEF == 1
            COVBAT_SETK_MNU = '';
            COVBAT_SETV_MNU = '';
            menuact = [ menuact 12 ];
        else
            COVBAT_SETK_MNU = sprintf('|CovBat: set K (leave empty to use var_expl) [ %s ]', k_str);
            COVBAT_SETV_MNU = sprintf('|CovBat: set var_expl (0..1) [ %s ]', var_str);
            % Append to menuact list (keep order sensible; 14 was your reference batch)
            menuact = [ menuact 12 13 14 ];
        end

        % --- Unseen-batch mode strings ---
        switch UNSEENBATCH_MODE_DEF
            case 1
                ub_mode_str = 'EB (empirical Bayes, conservative)';
            case 2
                ub_mode_str = 'no-shrink (MoM, aggressive)';
            case 3
                ub_mode_str = sprintf('strong-shrink (alpha=%.2f)', UNSEENBATCH_ALPHA_DEF);
            otherwise
                ub_mode_str = 'EB (empirical Bayes, conservative)';
        end

        UNSEENBATCHMODE_MNU  = sprintf('|Unseen-batch mode [ %s ]', ub_mode_str);
        if UNSEENBATCH_MODE_DEF == 3
            UNSEENBATCHALPHA_MNU = sprintf('|Set strong-shrink alpha (0..1) [ %.2f ]', UNSEENBATCH_ALPHA_DEF);
        else
            UNSEENBATCHALPHA_MNU = '';  % hidden when not in strong-shrink
        end
        % unseen-batch mode
        menuact = [menuact 24];          % mode toggle
        if UNSEENBATCH_MODE_DEF == 3
            menuact = [menuact 25];      % set alpha
        end
    
    % ========================================= DIR SETUP =========================================
    elseif METHOD_DEF == 3
        % Disparate Impact Remover
        menuact = [menuact 2 15 16]; 
        METHOD_STR = 'Disparate Impact Remover';
        % Type of distribution
        if DIST_DEF == 1
            DIST_STR = 'median'; 
        elseif DIST_DEF == 2
            DIST_STR = 'mean'; 
        end
    end

    if ~isempty(SUBGROUP_DEF)
        SUBGROUP_STR = 'yes'; 
        if isfinite(SUBGROUP_DEF) 
            SUBGROUP_MAT = sprintf('vector with %g case(s) defined', sum(SUBGROUP_DEF)); 
        else
            SUBGROUP_MAT = 'undefined';
        end
        SUBGROUP_MNU2 = sprintf('|Provide index to training cases [ %s ]', SUBGROUP_MAT );
        menuact = [menuact 17 18];
    else
        SUBGROUP_STR = 'no'; SUBGROUP_MNU2 = [];
        menuact = [ menuact 17 ];
    end
    SUBGROUP_MNU1 = sprintf('|Define subgroup of training cases [ %s ]',  SUBGROUP_STR);
    
    switch METHOD_DEF 
        case 1
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               '|Select covariates from NM covariate matrix [ ' COVAR_STR ' ]', ...
               '|Use intercept in partial correlation analysis [ ' INTERCEPT_STR ' ]', ...
               '|Attenuate or increase covariate effects [ ' COVDIR_STR ' ]' ...
               BETAEXTUSE_MNU ...
               BETAEXT_MNU ...
               SUBGROUP_MNU1 ...
               SUBGROUP_MNU2];
           
        case 2
            % And when composing the menustr for METHOD_DEF==2, insert the 3 new lines:
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               MBATCHUSE_MNU ... 
               MBATCH_MNU ...
               REFBATCH_MNU ...
               MCOVARUSE_MNU ...
               MCOVARLABEL_MNU ...
               MCOVAR_MNU ...
               MCOVARREM_MNU ...
               MCOVARTYPE_MNU ...      % may be empty
               MCOVARSPLINE_MNU ...    % may be empty
               COVBAT_MODE_MNU ...
               COVBAT_SETK_MNU ...
               COVBAT_SETV_MNU ...
               UNSEENBATCHMODE_MNU ...
               UNSEENBATCHALPHA_MNU ...
               SUBGROUP_MNU1 ...
               SUBGROUP_MNU2];
        case 3
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               '|Select categorical covariate(s) from NM covariate matrix [ ' COVAR_STR ' ]', ...
               '|Type of distribution [ ' DIST_STR ' ]', ...
               '|Strength of correction [ ' num2str(LAMBDA_DEF) ' ]', ...
               SUBGROUP_MNU1, ...
               SUBGROUP_MNU2];
    end
           
    nk_PrintLogo
    mestr = 'Residualization setup'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 
    act = nk_input(mestr,0,'mq', menustr, menuact);
    
    switch act
        
        case 1
            if METHOD_DEF == 1 % TO DO: change to menu selection 
                METHOD_DEF = 2; 
            elseif METHOD_DEF == 2
                METHOD_DEF = 3;
            else 
                METHOD_DEF = 1; 
            end
        
        case 2
            COVAR_DEF = nk_SelectCovariateIndex(NM, COVAR_DEF, 1);
   
        case 3
            if INTERCEPT_DEF == 2, INTERCEPT_DEF = 1; elseif INTERCEPT_DEF == 1, INTERCEPT_DEF = 2; end
        
        case 4
            if COVDIR_DEF == 1, COVDIR_DEF = 2; elseif COVDIR_DEF == 2, COVDIR_DEF = 1; end
            
        case 5
            if MBATCHUSE_DEF == 1, MBATCHUSE_DEF = 2; elseif MBATCHUSE_DEF == 2, MBATCHUSE_DEF = 1; end
        
        case 6
            MBATCH_DEF = nk_SelectCovariateIndex(NM, MBATCH_DEF, 1);
            if ~MBATCH_DEF , MBATCH_DEF = []; end

        case 7
            if isempty(REFBATCH_DEF)
                curRefStr = 'pooled (default)';
            else
                curRefStr = num2str(REFBATCH_DEF);
            end
            ref_menu = sprintf('Reference batch (current: %s)', curRefStr);
        
            choice = nk_input(ref_menu, 0, 'm', 'Set|Clear|Cancel', [1 2 3]);
        
            switch choice
                case 1  % Set
                    % Fetch unique values and their counts from the chosen batch covariate
                    uvals = []; counts = [];
                    if ~isempty(MBATCH_DEF) && isscalar(MBATCH_DEF)
                        vec = nm_get_covariate_vector(NM, MBATCH_DEF);   % your simplified helper
                        if ~isempty(vec)
                            vec    = vec(:);
                            vec    = vec(~isnan(vec));                  % drop NaNs
                            [uvals,~,grp] = unique(vec);
                            counts = accumarray(grp,1);                 % same order as uvals
                        end
                    end
        
                    if ~isempty(uvals)
                        % First item = pooled default, then each unique label + count
                        labelCells = cell(1, numel(uvals)+1);
                        labelCells{1} = '0 (pooled default)';
                        for k = 1:numel(uvals)
                            labelCells{k+1} = sprintf('%g (n=%d)', uvals(k), counts(k));
                        end
                        sel = nk_input('Choose reference batch label', 0, ...
                                       'm', strjoin(labelCells,'|'), 1:numel(labelCells));
                        if sel == 1
                            REFBATCH_DEF = [];                           % 0 => pooled
                        else
                            REFBATCH_DEF = uvals(sel-1);
                        end
                    else
                        % Fallback: numeric entry (0 disables)
                        val = nk_input(['Enter numeric label (must match your batch covariate values). ' ...
                                        'Enter 0 to disable reference batch.'], ...
                                       0, 'e', [], [1 1]);
                        if isempty(val)
                            % cancel: keep previous setting
                        elseif isscalar(val) && isfinite(val)
                            if val == 0
                                REFBATCH_DEF = [];
                            else
                                REFBATCH_DEF = val;
                            end
                        else
                            warning('Reference label must be a finite scalar. Keeping previous setting.');
                        end
                    end
        
                case 2  % Clear
                    REFBATCH_DEF = [];
        
                otherwise  % Cancel
                    % no change
            end

        case 8
            if MCOVARUSE_DEF == 1, MCOVARUSE_DEF = 2; else, MCOVARUSE_DEF = 1; end
        case 9
            if MCOVARLABEL_DEF == 1
                MCOVARLABEL_DEF = 2;
            else
                MCOVARLABEL_DEF = 1;
                %Remove subgroup of training cases option if not in expert
                %mode.
                if ~EXPERT
                    if ~isfield(CURACT,'SUBGROUP')
                        CURACT.SUBGROUP = NaN;
                    elseif isfield(CURACT,'SUBGROUP')
                        CURACT = rmfield(CURACT,'SUBGROUP');
                    end
                end
            end
        case 10
            MCOVAR_DEF = nk_SelectCovariateIndex(NM, MCOVAR_DEF, 1);
            if ~MCOVAR_DEF
                MCOVAR_DEF = []; 
            end
            MCOVARREM_DEF = [];
            MCOVAR_TYPE_DEF    = {};   % reset type info when selection changes
            MCOVAR_SPLINE_DF_DEF = []; % reset spline info

        case 11
            fprintf('\n Selected ComBat covariates ')
            fprintf('\n ===========================')
            for i = 1:numel(MCOVAR_DEF)
                fprintf('\nSelect %g for covariate ''%s''', i, NM.covnames{MCOVAR_DEF(i)});
            end
            MCOVARREM_DEF = nk_input('Choose covariate(s) which effects should be removed (0=none)',0,'i',MCOVARREM_DEF,[]);
            if any(MCOVARREM_DEF > numel(MCOVAR_DEF)) || (isscalar(MCOVARREM_DEF) && ~MCOVARREM_DEF)
                MCOVARREM_DEF = [];
            end

        case 12  % Toggle ComBat variant
            if COVBAT_MODE_DEF == 1
                COVBAT_MODE_DEF = 2;   % enable CovBat
            else
                COVBAT_MODE_DEF = 1;   % simple ComBat
            end
        
        case 13  % Set K (empty => clear to use var_expl)
            val = nk_input('Enter integer K for CovBat (enter 0 to leave empty and use var_expl):', 0, 'i', [], [1 1]);
            if ~val
                COVBAT_K_DEF = [];     % use var_expl instead
            else
                COVBAT_K_DEF = val;
            end
        
        case 14  % Set var_expl in [0..1]
            val = nk_input('Enter var_expl for CovBat (>0...1; enter 0 to leave empty and use K):', 0, 'e', COVBAT_VAR_DEF, [1 1]);
            if ~val
                COVBAT_VAR_DEF = [];
                % keep previous
            elseif isfinite(val) && val >= 0 && val <= 1
                COVBAT_VAR_DEF = val;
            else
                warning('var_expl must be within [0,1]. Keeping previous value.');
            end
        
        case 15
             if DIST_DEF == 1, DIST_DEF = 2;
             elseif DIST_DEF == 2, DIST_DEF = 1; 
             end

        case 16
            LAMBDA_DEF = nk_input('Define strength of correction', 0, 'r', 0.8, [1, 1]);
            %Check if lambda is between 0 and 1. 
            if LAMBDA_DEF>1, LAMBDA_DEF = 1;
            elseif LAMBDA_DEF<0, LAMBDA_DEF = 0;
            end

        case 17
            if ~isfield(CURACT,'SUBGROUP')
                CURACT.SUBGROUP = NaN; 
            elseif isfield(CURACT,'SUBGROUP')
                CURACT = rmfield(CURACT,'SUBGROUP'); 
            end
              
        case 18
            CURACT.SUBGROUP = logical(nk_input('Define logical index vector to select cases for beta computation',0,'e',[],[numel(NM.label),1]));
            %Set no NM label variance retainment if not in expert mode.
            if ~EXPERT, MCOVARLABEL_DEF = 2; end

        case 20
            if ~isfield(CURACT,'BETAEXT')
                CURACT.BETAEXT = NaN; 
            elseif isfield(CURACT,'BETAEXT')
                CURACT = rmfield(CURACT,'BETAEXT'); 
            end
            
        case 21
            if INTERCEPT_DEF
                defc = numel(COVAR_DEF) + 1;
            else
                defc = numel(COVAR_DEF) ;
            end
            CURACT.BETAEXT = nk_input('Define precomputed beta matrix',0,'e',[],[defc, size(NM.Y{varind},2)]);

        case 22  % Set measurement scale of ComBat covariates
            if isempty(MCOVAR_DEF)
                fprintf('\nNo ComBat covariates selected.\n');
            else
                done = false;
                while ~done
                    fprintf('\nCurrent ComBat covariates and types:\n');
                    for i = 1:numel(MCOVAR_DEF)
                        nm_i = NM.covnames{MCOVAR_DEF(i)};
                        if i > numel(MCOVAR_TYPE_DEF) || isempty(MCOVAR_TYPE_DEF{i})
                            MCOVAR_TYPE_DEF{i} = 'continuous';
                        end
                        t_i  = MCOVAR_TYPE_DEF{i};
                        ch   = nm_typechar(t_i);
                        fprintf('  %2d) %s [%s]\n', i, nm_i, ch);
                    end
                    fprintf('  0) Done\n');
                    idx = nk_input('Select covariate to change (0=done)', 0, 'i', 0, [1 1]);
                    if idx == 0
                        done = true;
                    elseif idx>=1 && idx<=numel(MCOVAR_DEF)
                        choice = nk_input(sprintf('Set type for "%s"', NM.covnames{MCOVAR_DEF(idx)}), ...
                                          0, 'm', 'continuous|binary|ordinal|categorical', 1:4);
                        switch choice
                            case 1, MCOVAR_TYPE_DEF{idx} = 'continuous';
                            case 2, MCOVAR_TYPE_DEF{idx} = 'binary';
                            case 3, MCOVAR_TYPE_DEF{idx} = 'ordinal';
                            case 4, MCOVAR_TYPE_DEF{idx} = 'categorical';
                        end
                    end
                end
            end

        case 23  % Configure spline modelling for ComBat covariates
            if isempty(MCOVAR_DEF)
                fprintf('\nNo ComBat covariates selected.\n');
            else
                done = false;
                while ~done
                    fprintf('\nSpline settings (df>=2 uses spline; 0/1 = no spline):\n');
                    for i = 1:numel(MCOVAR_DEF)
                        nm_i = NM.covnames{MCOVAR_DEF(i)};
                        if i > numel(MCOVAR_TYPE_DEF) || isempty(MCOVAR_TYPE_DEF{i})
                            MCOVAR_TYPE_DEF{i} = 'continuous';
                        end
                        t_i  = MCOVAR_TYPE_DEF{i};
                        df_i = 0;
                        if ~isempty(MCOVAR_SPLINE_DF_DEF) && numel(MCOVAR_SPLINE_DF_DEF)>=i
                            df_i = MCOVAR_SPLINE_DF_DEF(i);
                        end
                        ch   = nm_typechar(t_i);
                        if df_i >= 2
                            df_str = sprintf('%d', df_i);
                        else
                            df_str = 'none';
                        end
                        fprintf('  %2d) %s [%s], spline df=%s\n', i, nm_i, ch, df_str);
                    end
                    fprintf('  0) Done\n');
                    idx = nk_input('Select covariate to edit spline (0=done)', 0, 'i', 0, [1 1]);
                    if idx == 0
                        done = true;
                    elseif idx>=1 && idx<=numel(MCOVAR_DEF)
                        t_i = MCOVAR_TYPE_DEF{idx};
                        if strcmp(t_i,'categorical') || strcmp(t_i,'binary')
                            fprintf('  -> Spline not applicable to type "%s". Use continuous/ordinal if needed.\n', t_i);
                        else
                            df_new = nk_input('Enter spline df (>=2) or 0 for no spline', 0, 'i', ...
                                              0, [1 1]);
                            if isempty(df_new) || df_new <= 1
                                MCOVAR_SPLINE_DF_DEF(idx) = 0;
                            else
                                MCOVAR_SPLINE_DF_DEF(idx) = df_new;
                            end
                        end
                    end
                end
            end
        case 24  % Toggle unseen-batch mode
            % 1=EB, 2=no-shrink, 3=strong-shrink
            if UNSEENBATCH_MODE_DEF == 1
                UNSEENBATCH_MODE_DEF = 2;
            elseif UNSEENBATCH_MODE_DEF == 2
                UNSEENBATCH_MODE_DEF = 3;
            else
                UNSEENBATCH_MODE_DEF = 1;
            end
        case 25  % Set strong-shrink alpha
            val = nk_input('Enter strong-shrink alpha in [0,1]', 0, 'e', UNSEENBATCH_ALPHA_DEF, [1 1]);
            if ~isempty(val) && isfinite(val) && val >= 0 && val <= 1
                UNSEENBATCH_ALPHA_DEF = val;
            else
                fprintf('Alpha must be between 0 and 1. Keeping previous value.\n');
            end
    end 
end
CURACT.METHOD           = METHOD_DEF;
CURACT.COVAR            = COVAR_DEF;
CURACT.INTERCEPT        = INTERCEPT_DEF;
CURACT.COVDIR           = COVDIR_DEF;
CURACT.MBATCHUSE        = MBATCHUSE_DEF;
CURACT.MBATCH           = MBATCH_DEF;
CURACT.REFERENCE_LEVEL  = REFBATCH_DEF;   
CURACT.MCOVARUSE        = MCOVARUSE_DEF;
CURACT.MCOVAR           = MCOVAR_DEF;
CURACT.MCOVARREM        = MCOVARREM_DEF;
CURACT.MCOVARLABEL      = MCOVARLABEL_DEF;
CURACT.LAMBDA           = LAMBDA_DEF;
CURACT.COVBAT_MODE      = COVBAT_MODE_DEF;     % 1=simple, 2=covbat
CURACT.COVBAT_K         = COVBAT_K_DEF;        % [] => use var_expl
CURACT.COVBAT_VAR       = COVBAT_VAR_DEF;      % used when K is []
CURACT.DISTYPE          = DIST_DEF;
CURACT.MCOVAR_TYPE      = MCOVAR_TYPE_DEF;
CURACT.MCOVAR_SPLINE_DF = MCOVAR_SPLINE_DF_DEF;
CURACT.UNSEENBATCH_MODE = UNSEENBATCH_MODE_DEF;
CURACT.UNSEENBATCH_ALPHA= UNSEENBATCH_ALPHA_DEF;

function v = nm_get_covariate_vector(NM, colIdx)
    v = []; if isnumeric(NM.covars) && size(NM.covars,2) >= colIdx; v = NM.covars(:, colIdx); end

function ch = nm_typechar(t)
    % Map type string to short letter for display.
    t = lower(t);
    switch t
        case 'continuous',  ch = 'C';
        case 'binary',      ch = 'B';
        case 'ordinal',     ch = 'O';
        case 'categorical', ch = 'K';  % K = kategorial :-)
        otherwise,          ch = '?';
    end

