function [CURACT, act ] = nk_UnivCorrProcs_config(NM, CURACT, varind, parentstr, defaultsfl)
global EXPERT
if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end
% Defaults
METHOD_DEF          = 1;
COVAR_DEF           = 1;
MCOVARUSE_DEF       = 1;
MCOVAR_DEF          = [];
MCOVARLABEL_DEF     = 1;
COVDIR_DEF          = 1;
INTERCEPT_DEF       = 2;
BETAEXT_DEF         = [];
SUBGROUP_DEF        = [];
REFBATCH_DEF        = [];    % numeric label of the reference batch (empty = pooled)
DIST_DEF            = 1;
LAMBDA_DEF          = 0.8;
COVBAT_MODE_DEF     = 1;     % 1 = Simple ComBat, 2 = ComBat + CovBat
COVBAT_K_DEF        = [];    % integer PCs (used if non-empty)
COVBAT_VAR_DEF      = 0.95;  % cumulative variance in [0,1] (used if K is empty)

if ~defaultsfl
    
    % Get information from CURACT if available
    if isfield(CURACT,'METHOD'),      METHOD_DEF      = CURACT.METHOD; end
    if isfield(CURACT,'COVAR'),       COVAR_DEF       = CURACT.COVAR; end
    if isfield(CURACT,'SUBGROUP'),    SUBGROUP_DEF    = CURACT.SUBGROUP; end
    if isfield(CURACT,'INTERCEPT'),   INTERCEPT_DEF   = CURACT.INTERCEPT; end
    if isfield(CURACT,'COVDIR'),      COVDIR_DEF      = CURACT.COVDIR; end
    if isfield(CURACT,'BETAEXT'),     BETAEXT_DEF     = CURACT.BETAEXT; end
    if isfield(CURACT,'MCOVARUSE'),   MCOVARUSE_DEF   = CURACT.MCOVARUSE; end
    if isfield(CURACT,'MCOVAR'),      MCOVAR_DEF      = CURACT.MCOVAR; end
    if isfield(CURACT,'MCOVARLABEL'), MCOVARLABEL_DEF = CURACT.MCOVARLABEL; end
    if isfield(CURACT,'REFERENCE_LEVEL'), REFBATCH_DEF = CURACT.REFERENCE_LEVEL; end  
    if isfield(CURACT,'DISTYPE'),    DIST_DEF         = CURACT.DISTYPE; end
    if isfield(CURACT,'LAMBDA'),  LAMBDA_DEF          = CURACT.LAMBDA; end
    if isfield(CURACT,'COVBAT_MODE'), COVBAT_MODE_DEF = CURACT.COVBAT_MODE; end
    if isfield(CURACT,'COVBAT_K'),    COVBAT_K_DEF    = CURACT.COVBAT_K;    end
    if isfield(CURACT,'COVBAT_VAR'),  COVBAT_VAR_DEF  = CURACT.COVBAT_VAR;  end
    COVAR_STR = strjoin(NM.covnames(COVAR_DEF),', ');
    SUBGROUP_MNU1 = []; SUBGROUP_MNU2 = [];
    menuact = [ 1 2 ];
    
    if METHOD_DEF == 1
        % Partial Correlations
        menuact = [ menuact 3 4 ];
        METHOD_STR = 'Partial Correlations';
        if INTERCEPT_DEF == 2,          INTERCEPT_STR = 'yes'; else     INTERCEPT_STR = 'no'; end
        if COVDIR_DEF == 1,             COVDIR_STR = 'attenuate'; else  COVDIR_STR = 'increase'; end; 
    
    elseif METHOD_DEF==2
        % ComBat
        menuact = [ menuact 5 ]; MCOVARLABEL_MNU = []; MCOVAR_MNU = [];
        METHOD_STR = 'ComBat';
        if MCOVARUSE_DEF == 1
            MCOVARUSE_STR = 'yes';
            if isempty( MCOVAR_DEF )
                MCOVAR_STR = 'none';
            else
                MCOVAR_STR = strjoin(NM.covnames(MCOVAR_DEF),', ');
            end
            MCOVAR_MNU = sprintf('|Define retainment covariates [ %s ]', MCOVAR_STR);
            if MCOVARLABEL_DEF == 1,    MCOVARLABEL_STR = 'yes'; else, MCOVARLABEL_STR = 'no'; end
            MCOVARLABEL_MNU = sprintf('|Include NM label in variance retainment [ %s ]', MCOVARLABEL_STR);
            menuact = [ menuact 6 7 ];
        else
            MCOVARUSE_STR = 'no'; 
        end
        % reference batch menu entry
        if isempty(REFBATCH_DEF), REF_STR = 'pooled (default)'; else, REF_STR = num2str(REFBATCH_DEF); end
        REFBATCH_MNU = sprintf('|Set reference batch label [ %s ]', REF_STR);
        menuact = [ menuact 14 ];   % NEW action id for reference batch

        % --- NEW: CovBat variant display strings ---
        if COVBAT_MODE_DEF == 1
            COVBAT_MODE_STR = 'Simple ComBat';
        else
            COVBAT_MODE_STR = 'ComBat + CovBat';
        end
        
        % Build display strings without ternary
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

        % --- NEW: menu entries (action ids 15/16/17) ---
        COVBAT_MODE_MNU = sprintf('|ComBat variant [ %s ]', COVBAT_MODE_STR);
        if COVBAT_MODE_DEF == 1
            COVBAT_SETK_MNU = '';
            COVBAT_SETV_MNU = '';
            menuact = [ menuact 15 ];
        else
            COVBAT_SETK_MNU = sprintf('|CovBat: set K (leave empty to use var_expl) [ %s ]', k_str);
            COVBAT_SETV_MNU = sprintf('|CovBat: set var_expl (0..1) [ %s ]', var_str);
            % Append to menuact list (keep order sensible; 14 was your reference batch)
            menuact = [ menuact 15 16 17 ];
        end
        BETAEXT_DEF = [];

    elseif METHOD_DEF == 3
        % Disparate Impact Remover
        menuact = [menuact 12 13]; 
        METHOD_STR = 'Disparate Impact Remover';
        % Type of distribution
        if DIST_DEF == 1
            DIST_STR = 'median'; 
        elseif DIST_DEF == 2
            DIST_STR = 'mean'; 
        end
    end
    
    % Do we have to deal with external betas for partial correlations?

    if ~isempty(BETAEXT_DEF)   
        BETAEXT_STR = 'yes';
        if isfinite(BETAEXT_DEF) 
            BETAEXT_MAT = sprintf('%g x %g matrix defined', size(BETAEXT_DEF,1), size(BETAEXT_DEF,2)); 
        else
            BETAEXT_MAT = 'undefined'; 
        end
        BETAEXT_MNU = sprintf('|Define beta coeficients [ %s ]',BETAEXT_MAT);
        menuact = [ menuact 8 9 ];
        
    else
        BETAEXT_STR = 'no'; 
        BETAEXT_MNU = [];
        if METHOD_DEF == 1, menuact = [menuact 9]; end
        if ~isempty(SUBGROUP_DEF)
            SUBGROUP_STR = 'yes'; 
            if isfinite(SUBGROUP_DEF) 
                SUBGROUP_MAT = sprintf('vector with %g case(s) defined', sum(SUBGROUP_DEF)); 
            else
                SUBGROUP_MAT = 'undefined';
            end
            SUBGROUP_MNU2 = sprintf('|Provide index to training cases [ %s ]', SUBGROUP_MAT );
            
            menuact = [menuact 10 11];
        else
            SUBGROUP_STR = 'no'; SUBGROUP_MNU2 = [];
            menuact = [menuact 10];
        end
        SUBGROUP_MNU1 = sprintf('|Define subgroup of training cases [ %s ]',  SUBGROUP_STR);
    end
    
    switch METHOD_DEF 
        case 1
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               '|Select covariates from NM covariate matrix [ ' COVAR_STR ' ]', ...
               '|Use intercept in partial correlation analysis [ ' INTERCEPT_STR ' ]', ...
               '|Attenuate or increase covariate effects [ ' COVDIR_STR ' ]' ...
               '|Use externally-computed beta coeficients [ ' BETAEXT_STR ' ]' ...
               BETAEXT_MNU ...
               SUBGROUP_MNU1 ...
               SUBGROUP_MNU2];
           
        case 2
            % And when composing the menustr for METHOD_DEF==2, insert the 3 new lines:
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               '|Define vector in NM covariate matrix indexing batch effects [ ' COVAR_STR ' ]', ...
               '|Retain variance effects during correction[ ' MCOVARUSE_STR ' ]', ...
               MCOVAR_MNU ...
               MCOVARLABEL_MNU ...
               REFBATCH_MNU ...          
               COVBAT_MODE_MNU ...       
               COVBAT_SETK_MNU ...       
               COVBAT_SETV_MNU ...       
               SUBGROUP_MNU1 ...
               SUBGROUP_MNU2];
        case 3
            menustr = ['Select method [ ' METHOD_STR ' ]', ...
               '|Select categorical covariate(s) from NM covariate matrix [ ' COVAR_STR ' ]', ...
               '|Type of distribution [' DIST_STR ']', ...
               '|Strength of correction [' num2str(LAMBDA_DEF) ']', ...
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
            if MCOVARUSE_DEF == 1, MCOVARUSE_DEF = 2; else, MCOVARUSE_DEF = 1; end

        case 6
            MCOVAR_DEF = nk_SelectCovariateIndex(NM, MCOVAR_DEF, 1);
            if ~MCOVAR_DEF , MCOVAR_DEF = []; end

        case 7
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
            
        case 8
            if ~isfield(CURACT,'BETAEXT')
                CURACT.BETAEXT = NaN; 
            elseif isfield(CURACT,'BETAEXT')
                CURACT = rmfield(CURACT,'BETAEXT'); 
            end
            
        case 9
            if INTERCEPT_DEF
                defc = numel(COVAR_DEF) + 1;
            else
                defc = numel(COVAR_DEF) ;
            end
            CURACT.BETAEXT = nk_input('Define precompute beta matrix',0,'e',[],[defc, size(NM.Y{varind},2)]);

        case 10
              if ~isfield(CURACT,'SUBGROUP')
                CURACT.SUBGROUP = NaN; 
            elseif isfield(CURACT,'SUBGROUP')
                CURACT = rmfield(CURACT,'SUBGROUP'); 
              end
              
        case 11
            CURACT.SUBGROUP = logical(nk_input('Define logical index vector to select cases for beta computation',0,'e',[],[numel(NM.label),1]));
            %Set no NM label variance retainment if not in expert mode.
            if ~EXPERT, MCOVARLABEL_DEF = 2; end
            
        
        case 12
             if DIST_DEF == 1, DIST_DEF = 2;
             elseif DIST_DEF == 2, DIST_DEF = 1; 
             end

        case 13
            LAMBDA_DEF = nk_input('Define strength of correction', 0, 'r', 0.8, [1, 1]);
            %Check if lambda is between 0 and 1. 
            if LAMBDA_DEF>1, LAMBDA_DEF = 1;
            elseif LAMBDA_DEF<0, LAMBDA_DEF = 0;
            end
        
        case 14   % NEW: set/clear reference batch label for ComBat
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
                    if ~isempty(COVAR_DEF) && isscalar(COVAR_DEF)
                        vec = nm_get_covariate_vector(NM, COVAR_DEF);   % your simplified helper
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

        case 15  % Toggle ComBat variant
            if COVBAT_MODE_DEF == 1
                COVBAT_MODE_DEF = 2;   % enable CovBat
            else
                COVBAT_MODE_DEF = 1;   % simple ComBat
            end
        
        case 16  % Set K (empty => clear to use var_expl)
            val = nk_input('Enter integer K for CovBat (enter 0 to leave empty and use var_expl):', 0, 'i', [], [1 1]);
            if ~val
                COVBAT_K_DEF = [];     % use var_expl instead
            else
                COVBAT_K_DEF = val;
            end
        
        case 17  % Set var_expl in [0..1]
            val = nk_input('Enter var_expl for CovBat (>0...1; enter 0 to leave empty and use K):', 0, 'e', COVBAT_VAR_DEF, [1 1]);
            if ~val
                COVBAT_VAR_DEF = [];
                % keep previous
            elseif isfinite(val) && val >= 0 && val <= 1
                COVBAT_VAR_DEF = val;
            else
                warning('var_expl must be within [0,1]. Keeping previous value.');
            end
    end 
end
CURACT.METHOD           = METHOD_DEF;
CURACT.COVAR            = COVAR_DEF;
CURACT.MCOVARUSE        = MCOVARUSE_DEF;
CURACT.MCOVARLABEL      = MCOVARLABEL_DEF;
CURACT.MCOVAR           = MCOVAR_DEF;
CURACT.INTERCEPT        = INTERCEPT_DEF;
CURACT.COVDIR           = COVDIR_DEF;
CURACT.REFERENCE_LEVEL  = REFBATCH_DEF;   
CURACT.DISTYPE          = DIST_DEF;
CURACT.LAMBDA           = LAMBDA_DEF;
CURACT.COVBAT_MODE      = COVBAT_MODE_DEF;     % 1=simple, 2=covbat
CURACT.COVBAT_K         = COVBAT_K_DEF;        % [] => use var_expl
CURACT.COVBAT_VAR       = COVBAT_VAR_DEF;      % used when K is []

function v = nm_get_covariate_vector(NM, colIdx)
v = []; if isnumeric(NM.covars) && size(NM.covars,2) >= colIdx; v = NM.covars(:, colIdx); end

