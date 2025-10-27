function [ act, param ] = nk_GreedySearch_config(param, SVM, MULTI, defaultsfl, parentstr)
global EXPERT

% Expert-only parameters
if isempty(EXPERT), EXPERT = false; end
% Minimum # of features
GreedySearch.Direction           = 1;
GreedySearch.EarlyStop.Thresh    = 50;   % Early stopping criterion
GreedySearch.EarlyStop.Perc      = 1;    % Early stopping mode = percentage
GreedySearch.WeightSort          = 1;
GreedySearch.CritGap.flag        = 2;
GreedySearch.CritGap.crit        = 10;

% Wrapper feature evaluation mode at each optimization step
GreedySearch.FeatStepPerc           = 0;
GreedySearch.FeatRandPerc           = 0;
GreedySearch.KneePointDetection     = 2;
GreedySearch.MultiClassOptimization = 1;
GreedySearch.PreSort                = 1;
GreedySearch.PERM.flag              = 0;
GreedySearch.PERM.nperms            = 100;

%% --- ADAPTIVE WRAPPER: defaults (kept lightweight here; full detail in training code)
GreedySearch.AdRef.Enable           = false;     % master toggle (appears when EarlyStop disabled)
GreedySearch.AdRef.lambda           = 0.5;       % manual λ (used if Auto disabled)
GreedySearch.AdRef.kNN              = 20;        % neighbors per feature for similarity
GreedySearch.AdRef.gamma            = 0.98;      % memory decay
GreedySearch.AdRef.eta0             = 1e-3;      % global drift
GreedySearch.AdRef.eta1             = 5e-3;      % similarity bump scale
GreedySearch.AdRef.rmax             = 10;        % cap
% redundancy-well (negative on [0.4,0.7], positive outside)
GreedySearch.AdRef.c                = 0.55;
GreedySearch.AdRef.w                = 0.15;
GreedySearch.AdRef.beta_well        = 1;
GreedySearch.AdRef.beta_hi          = 1;
GreedySearch.AdRef.sigma_lo         = GreedySearch.AdRef.w/3;
GreedySearch.AdRef.sigma_hi         = 0.06;

% natural stopping
GreedySearch.AdRef.Stop.Enable      = true;
GreedySearch.AdRef.Stop.TauAbs      = 1e-4;
GreedySearch.AdRef.Stop.UseMAD      = true;
GreedySearch.AdRef.Stop.MADWinsz    = 8;
GreedySearch.AdRef.Stop.Zmad        = 2.0;
GreedySearch.AdRef.Stop.Patience    = 0;
% Auto mode (nearly parameter-free)
GreedySearch.AdRef.Auto.Enable      = false;
GreedySearch.AdRef.Auto.LambdaC     = 0.8;
GreedySearch.AdRef.Auto.HalfLife    = 10;
GreedySearch.AdRef.Auto.TargetBumpS = 0.90;
GreedySearch.AdRef.Auto.TargetBump  = 0.10;
GreedySearch.AdRef.Auto.AutoKNN     = true;
GreedySearch.AdRef.Auto.ZeroTauAbs  = true;

if ~exist('defaultsfl','var') || isempty(defaultsfl), defaultsfl = false; end
if ~defaultsfl
    
    % Inherit from existing param, if present
    if isfield(param,'GreedySearch') 
        if isfield(param.GreedySearch,'Direction') && ~isempty( param.GreedySearch.Direction)
            GreedySearch.Direction              = param.GreedySearch.Direction;
        end
        if isfield(param.GreedySearch,'WeightSort') && ~isempty( param.GreedySearch.WeightSort)
            GreedySearch.WeightSort             = param.GreedySearch.WeightSort;
        end
        if isfield(param.GreedySearch,'EarlyStop') && isfield(param.GreedySearch.EarlyStop,'Thresh') && ~isempty( param.GreedySearch.EarlyStop )
            GreedySearch.EarlyStop.Thresh       = param.GreedySearch.EarlyStop.Thresh; 
            GreedySearch.EarlyStop.Perc         = param.GreedySearch.EarlyStop.Perc;
        end
        if isfield(param.GreedySearch,'FeatStepPerc') && ~isempty( param.GreedySearch.FeatStepPerc)
            GreedySearch.FeatStepPerc           = param.GreedySearch.FeatStepPerc;
        end
        if isfield(param.GreedySearch,'FeatRandPerc') && ~isempty( param.GreedySearch.FeatRandPerc)
            GreedySearch.FeatRandPerc           = param.GreedySearch.FeatRandPerc;
        end
        if isfield(param.GreedySearch,'KneePointDetection') && ~isempty( param.GreedySearch.KneePointDetection)
            GreedySearch.KneePointDetection     = param.GreedySearch.KneePointDetection;
        end
        if isfield(param.GreedySearch,'MultiClassOptimization') && ~isempty( param.GreedySearch.MultiClassOptimization)
            GreedySearch.MultiClassOptimization = param.GreedySearch.MultiClassOptimization;
        end
        if isfield(param.GreedySearch,'PreSort') && ~isempty( param.GreedySearch.PreSort)
            GreedySearch.PreSort = param.GreedySearch.PreSort;
        end
        if isfield(param.GreedySearch,'PERM')
            GreedySearch.PERM                   = param.GreedySearch.PERM;
        end
        if isfield(param.GreedySearch,'CritGap') && ~isempty( param.GreedySearch.CritGap)
            GreedySearch.CritGap = param.GreedySearch.CritGap;
        end
        %% --- ADAPTIVE WRAPPER: inherit prior config if present
        if isfield(param.GreedySearch,'AdRef') && ~isempty(param.GreedySearch.AdRef)
            GreedySearch.AdRef = merge_structs(GreedySearch.AdRef, param.GreedySearch.AdRef);
        end
    end
    
    % Direction label
    if GreedySearch.Direction == 1, dirstr = 'Forward'; else, dirstr = 'Backward'; end
    
    % Linear machine?
    if any(strcmp(SVM.kernel.kernstr,{' -t 0', 'lin', 'linear', 'Linear'})) 
        LinMode = 1;
    else
        LinMode = 0;
    end
    
    if LinMode && GreedySearch.MultiClassOptimization ~= 1
        switch GreedySearch.WeightSort
            case 1, linstr2 = 'Optimize features for prediction performance';
            case 2, linstr2 = 'Optimize features for their weights (Guyon''s)';
        end
        linstr = sprintf('|Feature sorting criterion (Linear machine) [ %s ]', linstr2 );
        actind = [1 2];
    else
        linstr = ''; 
        actind = 1;
    end
    
    % Early stopping label
    if GreedySearch.EarlyStop.Thresh
        if GreedySearch.EarlyStop.Perc == 1
            if GreedySearch.Direction == 1
                earlystr = sprintf('Stop when %g%% of the candidate features are still in the pool',GreedySearch.EarlyStop.Thresh);
            else    
                earlystr = sprintf('Stop when %g%% of the features are still used by the model',GreedySearch.EarlyStop.Thresh);
            end
        else
            earlystr = sprintf('Stop at %g selected features',GreedySearch.EarlyStop.Thresh);
        end
    else
        earlystr = 'Early stopping disabled';
    end
    actind = [actind 3];
    
    % Stepping / random selection labels (unchanged)
    randstr = '';
    if GreedySearch.FeatStepPerc
        if GreedySearch.EarlyStop.Perc == 1, percstr = '%'; else, percstr = ''; end
        stepstr = sprintf('%g%s of top features at each cycle',GreedySearch.FeatStepPerc, percstr);
        if GreedySearch.WeightSort == 1
            if ~GreedySearch.FeatRandPerc, randoptstr = 'deactivated';
            else, randoptstr = sprintf('randomly select %g%s  of top features', GreedySearch.FeatRandPerc, percstr);
            end
            randstr = sprintf('|Randomly select features from top-ranked feature block [ %s ]', randoptstr);
            actind = [actind 4 5];
        else
            actind = [actind 4];
        end
    else
        stepstr = '1% feature blocks will be evaluated';
        actind = [actind 4];
    end
    
    if (~GreedySearch.FeatStepPerc || ~GreedySearch.EarlyStop.Thresh) || ...
         ( GreedySearch.FeatStepPerc > 0 && GreedySearch.EarlyStop.Perc == 1 && (100-GreedySearch.EarlyStop.Thresh) / GreedySearch.FeatStepPerc >= 3 )
        kneestrdef = {'enabled','disabled'};
        kneestr = sprintf('|Kneepoint-based threshold detection [ %s ]',kneestrdef{GreedySearch.KneePointDetection});
        actind = [ actind 6 ];
    else
        kneestr = [];
    end
    
    multistr = []; multipermflagstr = []; multinpermsstr = []; presortstr=[];
    if MULTI.flag && MULTI.train
        if GreedySearch.MultiClassOptimization, multistrdef = 'Multi-class performance';
        else, multistrdef = 'Binary/Regression performance';
        end
        multistr = sprintf('|Optimization criterion [ %s ]', multistrdef); actind = [ actind 7 ]; 
        if GreedySearch.MultiClassOptimization
            if GreedySearch.PERM.flag, multipermflagstrdef = 'activated';
            else, multipermflagstrdef = 'not activated';
            end
            multipermflagstr = sprintf('|Permutation-based multi-class optimization [ %s ]',multipermflagstrdef ); actind = [actind 8 ];
            if GreedySearch.PERM.flag
                multinpermsstr = sprintf('|Number of permutations to be performed [ %g ]', GreedySearch.PERM.nperms); actind = [ actind 9 ];
            end
            if GreedySearch.PreSort, presortstrdef = 'yes'; else, presortstrdef = 'no'; end
            presortstr = sprintf('|Sort features according to binary performance before multi-class optimization [ %s ]',presortstrdef); actind = [ actind 10 ];
        end
    end

    critgapstr = [];
    critvaluestr=[];
    if param.datamode == 4
        critgapstrdef = {'enabled','disabled'};
        critgapstr = sprintf('|Critical-gap based early stopping [ %s ]',critgapstrdef{GreedySearch.CritGap.flag}); actind = [ actind 11 ];
        if GreedySearch.CritGap.flag == 1
            critvaluestr = sprintf('|Early stop-inducing gap between CV1 training and test criteria in %% [ %g ]', GreedySearch.CritGap.crit); actind = [ actind 12 ];
        end
    end

    % Build menu
    % Helper to append a menu item and get its index (position)
    add_item = @(lst, label) deal([lst, {label}], numel(lst)+1);
    
    menu_list = {};
    idx = struct();  % will store indices of each visible item
    
    % --- Base items (no leading "|")
    [menu_list, idx.dir]      = add_item(menu_list, sprintf('Search direction [ %s ]', dirstr));
    
    if ~isempty(linstr)   % if the linear-criterion string is active
        [menu_list, idx.weightsort] = add_item(menu_list, linstr( linstr(1)=='|' ) * "" + linstr ); % ensure no leading "|"
    end
    
    [menu_list, idx.early]    = add_item(menu_list, sprintf('Early stopping [ %s ]', earlystr));
    [menu_list, idx.step]     = add_item(menu_list, sprintf('Feature stepping [ %s ]', stepstr));
    
    if ~isempty(randstr)
        if randstr(1)=='|', randstr = randstr(2:end); end
        [menu_list, idx.rand] = add_item(menu_list, randstr);
    end
    
    if ~isempty(kneestr)
        if kneestr(1)=='|', kneestr = kneestr(2:end); end
        [menu_list, idx.knee] = add_item(menu_list, kneestr);
    end
    
    if ~isempty(multistr)
        if multistr(1)=='|', multistr = multistr(2:end); end
        [menu_list, idx.multi] = add_item(menu_list, multistr);
    end
    if ~isempty(multipermflagstr)
        if multipermflagstr(1)=='|', multipermflagstr = multipermflagstr(2:end); end
        [menu_list, idx.mpermflag] = add_item(menu_list, multipermflagstr);
    end
    if ~isempty(multinpermsstr)
        if multinpermsstr(1)=='|', multinpermsstr = multinpermsstr(2:end); end
        [menu_list, idx.mperms] = add_item(menu_list, multinpermsstr);
    end
    if ~isempty(presortstr)
        if presortstr(1)=='|', presortstr = presortstr(2:end); end
        [menu_list, idx.presort] = add_item(menu_list, presortstr);
    end
    
    if ~isempty(critgapstr)
        if critgapstr(1)=='|', critgapstr = critgapstr(2:end); end
        [menu_list, idx.critgap] = add_item(menu_list, critgapstr);
    end
    if ~isempty(critvaluestr)
        if critvaluestr(1)=='|', critvaluestr = critvaluestr(2:end); end
        [menu_list, idx.critval] = add_item(menu_list, critvaluestr);
    end
    
    % --- Adaptive block (only when early stop is disabled)
    if GreedySearch.EarlyStop.Thresh == 0
        enstr = tern(GreedySearch.AdRef.Enable,'enabled','disabled');
        [menu_list, idx.ad_enable] = add_item(menu_list, sprintf('Adaptive wrapper [ %s ]', enstr));
    
        if GreedySearch.AdRef.Enable
            autoStr = tern(GreedySearch.AdRef.Auto.Enable,'ON','OFF');
            [menu_list, idx.ad_auto] = add_item(menu_list, sprintf('Adaptive: Auto mode [ %s ]', autoStr));
    
            % Expert-only
            if EXPERT
                [menu_list, idx.ad_help]   = add_item(menu_list, 'Adaptive: Quick help');  % no bracket text
    
                [menu_list, idx.ad_lambda] = add_item(menu_list, sprintf('Adaptive: lambda (manual) [ %g ]', GreedySearch.AdRef.lambda));
                [menu_list, idx.ad_kNN]    = add_item(menu_list, sprintf('Adaptive: kNN neighbors [ %g ]', GreedySearch.AdRef.kNN));
                [menu_list, idx.ad_gamma]  = add_item(menu_list, sprintf('Adaptive: gamma (memory) [ %.3f ]', GreedySearch.AdRef.gamma));
                [menu_list, idx.ad_eta0]   = add_item(menu_list, sprintf('Adaptive: eta0 (drift) [ %.3g ]', GreedySearch.AdRef.eta0));
                [menu_list, idx.ad_eta1]   = add_item(menu_list, sprintf('Adaptive: eta1 (sim bump) [ %.3g ]', GreedySearch.AdRef.eta1));
                [menu_list, idx.ad_rmax]   = add_item(menu_list, sprintf('Adaptive: rmax (cap) [ %g ]', GreedySearch.AdRef.rmax));
    
                [menu_list, idx.ad_c]      = add_item(menu_list, sprintf('Adaptive φ: center c [ %.2f ]', GreedySearch.AdRef.c));
                [menu_list, idx.ad_w]      = add_item(menu_list, sprintf('Adaptive φ: half-width w [ %.2f ]', GreedySearch.AdRef.w));
                [menu_list, idx.ad_beta_well]  = add_item(menu_list, sprintf('Adaptive φ: beta(well) [ %g ]', GreedySearch.AdRef.beta_well));
                [menu_list, idx.ad_beta_hi]   = add_item(menu_list, sprintf('Adaptive φ: beta(high) [ %g ]', GreedySearch.AdRef.beta_hi));
                [menu_list, idx.ad_sigma_lo]  = add_item(menu_list, sprintf('Adaptive φ: sigma(low) [ %g ]', GreedySearch.AdRef.sigma_lo));
                [menu_list, idx.ad_sigma_hi]   = add_item(menu_list, sprintf('Adaptive φ: sigma(high) [ %g ]', GreedySearch.AdRef.sigma_hi));
                [menu_list, idx.ad_plot_pen]   = add_item(menu_list, sprintf('Adaptive φ: inspect penalty function defined by current parameters'));

                [menu_list, idx.ad_usemad] = add_item(menu_list, sprintf('Adaptive Stop: Use MAD [ %s ]', tern(GreedySearch.AdRef.Stop.UseMAD,'yes','no')));
                [menu_list, idx.ad_zmad]   = add_item(menu_list, sprintf('Adaptive Stop: Zmad [ %.2f ]', GreedySearch.AdRef.Stop.Zmad));
                [menu_list, idx.ad_pat]    = add_item(menu_list, sprintf('Adaptive Stop: Patience [ %g ]', GreedySearch.AdRef.Stop.Patience));
    
                [menu_list, idx.ad_lc]     = add_item(menu_list, sprintf('Auto: LambdaC [ %.2f ]', GreedySearch.AdRef.Auto.LambdaC));
                [menu_list, idx.ad_hl]     = add_item(menu_list, sprintf('Auto: HalfLife [ %g ]', GreedySearch.AdRef.Auto.HalfLife));
                [menu_list, idx.ad_tbs]    = add_item(menu_list, sprintf('Auto: TargetBumpS [ %.2f ]', GreedySearch.AdRef.Auto.TargetBumpS));
                [menu_list, idx.ad_tb]     = add_item(menu_list, sprintf('Auto: TargetBump [ %.2f ]', GreedySearch.AdRef.Auto.TargetBump));
                [menu_list, idx.ad_autok]  = add_item(menu_list, sprintf('Auto: AutoKNN [ %s ]', tern(GreedySearch.AdRef.Auto.AutoKNN,'yes','no')));
                [menu_list, idx.ad_ztau]   = add_item(menu_list, sprintf('Auto: ZeroTauAbs [ %s ]', tern(GreedySearch.AdRef.Auto.ZeroTauAbs,'yes','no')));
            end
        end
    end
    
    nk_PrintLogo
    % --- Prompt (ids are simply 1..N by position)
    mestr = 'Define Greedy Search wrapper parameters'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>>',parentstr);
    act = nk_input(mestr, 0, 'mq', menu_list, 1:numel(menu_list));

    if act == idx.dir
        GreedySearch.Direction = nk_input('Feature search mode',0,'m', ...
            'Forward selection|Backward selection', [1,2], GreedySearch.Direction);
    
    elseif isfield(idx,'weightsort') && act == idx.weightsort
        GreedySearch.WeightSort = nk_input('Feature sorting criterion',0,'m', ...
            'Performance|Weights (Guyon''s method)', [1,2], GreedySearch.WeightSort);
        if GreedySearch.WeightSort == 2, GreedySearch.FeatRandPerc = 0; end
    
    elseif act == idx.early
        GreedySearch.EarlyStop.Thresh = nk_input('Early stopping threshold (0 = disables early stopping)', 0,'e', GreedySearch.EarlyStop.Thresh);
        if GreedySearch.EarlyStop.Thresh
            GreedySearch.EarlyStop.Perc = nk_input('Absolute number or Percentage of features',0,'m', ...
                'Percentage|Absolute', [1,2], GreedySearch.EarlyStop.Perc);
        end
    
    elseif act == idx.step
        GreedySearch.FeatStepPerc = nk_input('Define %% of top-ranked features selected at each wrapper cycle (0 = disables block selection)',0,'e', GreedySearch.FeatStepPerc);
    
    elseif isfield(idx,'rand') && act == idx.rand
        GreedySearch.FeatRandPerc = nk_input('Randomly select %% of features in block of top-ranked features (0 = disables random selection)',0,'e', GreedySearch.FeatRandPerc);
    
    elseif isfield(idx,'knee') && act == idx.knee
        GreedySearch.KneePointDetection = 3 - GreedySearch.KneePointDetection; % toggle 1<->2
    
    elseif isfield(idx,'multi') && act == idx.multi
        GreedySearch.MultiClassOptimization = ~GreedySearch.MultiClassOptimization;
    
    elseif isfield(idx,'mpermflag') && act == idx.mpermflag
        GreedySearch.PERM.flag = ~GreedySearch.PERM.flag;
    
    elseif isfield(idx,'mperms') && act == idx.mperms
        GreedySearch.PERM.nperms = nk_input('Define number of permutations for multi-class feature optimization',0,'i', GreedySearch.PERM.nperms);
    
    elseif isfield(idx,'presort') && act == idx.presort
        GreedySearch.PreSort = ~GreedySearch.PreSort;
    
    elseif isfield(idx,'critgap') && act == idx.critgap
        GreedySearch.CritGap.flag = 3 - GreedySearch.CritGap.flag; % toggle 1<->2
    
    elseif isfield(idx,'critval') && act == idx.critval
        GreedySearch.CritGap.crit = nk_input('Define critical gap in %% between CV1 training and test for early stopping',0,'i', GreedySearch.CritGap.crit);
    end
    
    % -------- Adaptive actions -----------
    if isfield(idx,'ad_enable') && act == idx.ad_enable
        GreedySearch.AdRef.Enable = ~GreedySearch.AdRef.Enable;
    
    elseif isfield(idx,'ad_auto') && act == idx.ad_auto
        GreedySearch.AdRef.Auto.Enable = ~GreedySearch.AdRef.Auto.Enable;
    
    elseif isfield(idx,'ad_help') && act == idx.ad_help
        print_adref_quick_help();      % show help
        input('\nPress ENTER to return to the menu: ','s');  % reliable pause
    
    elseif isfield(idx,'ad_lambda') && act == idx.ad_lambda
        GreedySearch.AdRef.lambda = nk_input('Adaptive: lambda (manual)',0,'e', GreedySearch.AdRef.lambda);
    
    elseif isfield(idx,'ad_kNN') && act == idx.ad_kNN
        GreedySearch.AdRef.kNN = nk_input('Adaptive: kNN neighbors',0,'i', GreedySearch.AdRef.kNN);
    
    elseif isfield(idx,'ad_gamma') && act == idx.ad_gamma
        GreedySearch.AdRef.gamma = nk_input('Adaptive: gamma (0..1)',0,'e', GreedySearch.AdRef.gamma);
    
    elseif isfield(idx,'ad_eta0') && act == idx.ad_eta0
        GreedySearch.AdRef.eta0 = nk_input('Adaptive: eta0 (drift)',0,'e', GreedySearch.AdRef.eta0);
    
    elseif isfield(idx,'ad_eta1') && act == idx.ad_eta1
        GreedySearch.AdRef.eta1 = nk_input('Adaptive: eta1 (sim bump)',0,'e', GreedySearch.AdRef.eta1);
    
    elseif isfield(idx,'ad_rmax') && act == idx.ad_rmax
        GreedySearch.AdRef.rmax = nk_input('Adaptive: rmax (cap)',0,'e', GreedySearch.AdRef.rmax);
    
    elseif isfield(idx,'ad_c') && act == idx.ad_c
        GreedySearch.AdRef.c = nk_input('Adaptive φ: center c',0,'e', GreedySearch.AdRef.c);
    
    elseif isfield(idx,'ad_w') && act == idx.ad_w
        GreedySearch.AdRef.w = nk_input('Adaptive φ: half-width w',0,'e', GreedySearch.AdRef.w);
    
    elseif isfield(idx,'ad_beta_well') && act == idx.ad_beta_well
        GreedySearch.AdRef.beta_well = nk_input('Adaptive φ: magnitude of the ''well'' (moderate-redundancy region)',0,'e', GreedySearch.AdRef.beta_well);
    
    elseif isfield(idx,'ad_beta_hi') && act == idx.ad_beta_hi
        GreedySearch.AdRef.beta_hi = nk_input('Adaptive φ: magnitude of the high-redundancy region',0,'e', GreedySearch.AdRef.beta_hi);

    elseif isfield(idx,'ad_sigma_lo') && act == idx.ad_sigma_lo
        GreedySearch.AdRef.sigma_lo = nk_input('Adaptive φ: transition smoothness of the ''well'' (moderate-redundancy region)',0,'e', GreedySearch.AdRef.sigma_lo);
    
    elseif isfield(idx,'ad_sigma_hi') && act == idx.ad_sigma_hi
        GreedySearch.AdRef.sigma_hi = nk_input('Adaptive φ: sigma (high) transition to the high-redundancy region',0,'e', GreedySearch.AdRef.sigma_hi);
    
    elseif isfield(idx,'ad_plot_pen') && act == idx.ad_plot_pen
        nk_plot_adaptive_penalty(GreedySearch.AdRef);

    elseif isfield(idx,'ad_usemad') && act == idx.ad_usemad
        GreedySearch.AdRef.Stop.UseMAD = ~GreedySearch.AdRef.Stop.UseMAD;
    
    elseif isfield(idx,'ad_zmad') && act == idx.ad_zmad
        GreedySearch.AdRef.Stop.Zmad = nk_input('Adaptive Stop: Zmad',0,'e', GreedySearch.AdRef.Stop.Zmad);
    
    elseif isfield(idx,'ad_pat') && act == idx.ad_pat
        GreedySearch.AdRef.Stop.Patience = nk_input('Adaptive Stop: Patience (iterations)',0,'i', GreedySearch.AdRef.Stop.Patience);
    
    elseif isfield(idx,'ad_lc') && act == idx.ad_lc
        GreedySearch.AdRef.Auto.LambdaC = nk_input('Auto: LambdaC (λ scale)',0,'e', GreedySearch.AdRef.Auto.LambdaC);
    
    elseif isfield(idx,'ad_hl') && act == idx.ad_hl
        GreedySearch.AdRef.Auto.HalfLife = nk_input('Auto: HalfLife (steps of memory)',0,'i', GreedySearch.AdRef.Auto.HalfLife);
    
    elseif isfield(idx,'ad_tbs') && act == idx.ad_tbs
        GreedySearch.AdRef.Auto.TargetBumpS = nk_input('Auto: TargetBumpS (similarity s)',0,'e', GreedySearch.AdRef.Auto.TargetBumpS);
    
    elseif isfield(idx,'ad_tb') && act == idx.ad_tb
        GreedySearch.AdRef.Auto.TargetBump = nk_input('Auto: TargetBump (desired bump)',0,'e', GreedySearch.AdRef.Auto.TargetBump);
    
    elseif isfield(idx,'ad_autok') && act == idx.ad_autok
        GreedySearch.AdRef.Auto.AutoKNN = ~GreedySearch.AdRef.Auto.AutoKNN;
    
    elseif isfield(idx,'ad_ztau') && act == idx.ad_ztau
        GreedySearch.AdRef.Auto.ZeroTauAbs = ~GreedySearch.AdRef.Auto.ZeroTauAbs;
    end
else
    act = 0;
end

param.GreedySearch = GreedySearch;
end

% ---------------- small local helpers ----------------
function out = tern(cond, a, b)
    if cond, out = a; else, out = b; end
end

function c = cond_cell(cond, str)
    if cond, c = {str}; else, c = {}; end
end

function tf = which_var(name)
% returns 1 if a variable with this name exists in any workspace we can see
    tf = evalin('base', sprintf('exist(''%s'',''var'')', name));
end

function S = merge_structs(S, T)
% shallow merge T into S (fields present in T overwrite S)
    if ~isstruct(T), return; end
    f = fieldnames(T);
    for i = 1:numel(f)
        k = f{i};
        if isstruct(T.(k))
            if ~isfield(S,k) || ~isstruct(S.(k)), S.(k) = struct(); end
            S.(k) = merge_structs(S.(k), T.(k));
        else
            S.(k) = T.(k);
        end
    end
end

function print_adref_quick_help()
    fprintf('\n============================================================\n');
    fprintf(' Adaptive Wrapper — Quick Help (EXPERT)\n');
    fprintf('============================================================\n');
    fprintf('\nCORE TOGGLES\n');
    fprintf('  • Adaptive wrapper            Turns on dynamic, similarity-aware refusal r_j.\n');
    fprintf('  • Auto mode                   Auto-calibrates λ; optional auto defaults for γ, η0, η1, kNN, τ_abs.\n');

    fprintf('\nMANUAL KNOBS (when Auto=OFF)\n');
    fprintf('  • lambda (λ)                  Penalization strength in ranking: score’ = score − λ·r_j.\n');
    fprintf('  • kNN                         Neighbors per feature in sparse |corr| graph (update locality & cost).\n');
    fprintf('  • gamma (γ)                   Memory decay of r (0<γ≤1). Larger γ → longer memory.\n');
    fprintf('  • eta0 (η0)                   Small global drift; keeps refusal growing slowly.\n');
    fprintf('  • eta1 (η1)                   Scale of similarity bump around accepted features.\n');
    fprintf('  • rmax                        Cap to avoid runaway values.\n');

    fprintf('\nREDUNDANCY WELL φ(s)\n');
    fprintf('  • c, w                        Center & half-width; φ(s)<0 for s∈[c−w,c+w] (default [0.40,0.70]).\n');
    fprintf('  • beta_well / beta_hi         Magnitude of negative well (moderate redundancy) / high-similarity penalty (near-duplicates).\n');
    fprintf('  • sigma_lo / sigma_hi         Smoothness (std): window edges around [c-w,c+w] / turn-on of high-sim penalty; larger = gentler.\n');
    fprintf('  • φ(s) range                  Roughly bounded by [-beta_well, +beta_hi] (exact extrema depend on gating windows).\n');
    
    fprintf('\nNATURAL STOPPING\n');
    fprintf('  • Use MAD, Zmad               Robust tolerance τ from recent gains (≈1.4826·MAD), τ = max(τ_abs, Zmad·σ̂).\n');
    fprintf('  • Patience                    Require condition for K iterations.\n');
    fprintf('  Rule: stop when max_j{ (val(j)−best) − λ·r_j } ≤ τ.\n');

    fprintf('\nAUTO MODE\n');
    fprintf('  • LambdaC                     λ_eff = LambdaC·σ_g / (1 + median(r_pool)), σ_g = robust gain scale.\n');
    fprintf('  • HalfLife → γ                γ = 2^(−1/HalfLife); η0 ≈ 0.1·(1−γ).\n');
    fprintf('  • TargetBumpS, TargetBump     Sets η1 so bump equals TargetBump at similarity s=TargetBumpS.\n');
    fprintf('  • AutoKNN                     Sets kNN ≈ min(30, max(10, floor(3·log p))).\n');
    fprintf('  • ZeroTauAbs                  If ON, τ_abs=0 (pure MAD-based stop).\n');
    fprintf('------------------------------------------------------------\n');
end