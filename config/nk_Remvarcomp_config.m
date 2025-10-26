function [REMVARCOMP, PX] = nk_Remvarcomp_config(NM, varind, REMVARCOMP, PX, parentstr)

m = height(NM.cases);
corrmeth    = 1;
corrthresh  = 0.5;
corrcrit = 'corr';
varop = 'gt';
recon = 2;
varops = {'gt','ge','lt','le'};
recons = {'yes', 'no'};
corrmeths = {'Pearson','Spearman','ANOVA'};
corrcrits = {'corr','pval'};
dims = 1;
dimmode = 3;
redmethod = 1; % 1= PCA, 2= fastICA
tolerance = 1.0000e-04; % default of scikit-learn implementation
max_iters = 200; % default of scikit-learn implementation
algorithms = {'parallel', 'deflation'};
algorithm_opt = 'parallel';
funs = {'logcosh', 'exp', 'cube'};
fun_opt = 'logcosh';
whitens = {'unit-variance', 'arbitrary-variance'};
whiten_opt = 'unit-variance';

SUBGROUP.flag = 1;
subgroupstr = {'Entire training set', ...
                'User-defined subset of CV1 training partition', ...
                'Random subset of CV1 training partition', ...
                'Entire calibration set', ...
                'User-defined subset of calibration data',...
                'Random subset of caobration data'};
            
%% Define defaults
if ~isfield(REMVARCOMP,'corrmeth'),     REMVARCOMP.corrmeth = corrmeth; end
if ~isfield(REMVARCOMP,'corrthresh'),   REMVARCOMP.corrthresh = corrthresh; end
if ~isfield(REMVARCOMP,'corrcrit'),     REMVARCOMP.corrcrit = corrcrit; end
if ~isfield(REMVARCOMP,'varop'),        REMVARCOMP.varop = varop; end
if ~isfield(REMVARCOMP,'recon'),        REMVARCOMP.recon = recon; end
if ~isfield(REMVARCOMP,'dims'),         REMVARCOMP.dims = dims; end
if ~isfield(REMVARCOMP,'dimmode'),      REMVARCOMP.dimmode = dimmode; end
if ~isfield(REMVARCOMP,'SUBGROUP'),     REMVARCOMP.SUBGROUP = SUBGROUP; end
if ~isfield(REMVARCOMP,'redmethod'),    REMVARCOMP.redmethod = redmethod; end
if ~isfield(REMVARCOMP,'tolerance'),    REMVARCOMP.tolerance = tolerance; end
if ~isfield(REMVARCOMP,'max_iters'),    REMVARCOMP.max_iters = max_iters; end
if ~isfield(REMVARCOMP,'algorithm_opt'),REMVARCOMP.algorithm_opt =algorithm_opt; end
if ~isfield(REMVARCOMP,'whiten_opt'),   REMVARCOMP.whiten_opt = whiten_opt; end
if ~isfield(REMVARCOMP,'fun_opt'),      REMVARCOMP.fun_opt = fun_opt; end

% possible other parameters for fastica (already implemented in function; just needs to be added here): 
% algorithm: 'parallel' (default), 'deflation'
% whiten: 'unit-variance' (default), 'arbitrary-variance', 
% fun:  'logcosh' (default), 'fexpd', 'ecubef'
if ~exist('PX','var'),                  PX = []; end

%% Define menu
if isfield(REMVARCOMP,'G')
    [p,q] = size(REMVARCOMP.G);
    if q>1
        RANKVARCOMP_G_str = sprintf('%g-by-%g matrix specified',p,q);
    else
        RANKVARCOMP_G_str = 'vector specified';
    end
else
    RANKVARCOMP_G_str = 'No covariate vector or matrix specified!';
end

if isfield(REMVARCOMP, 'redmethod') && REMVARCOMP.redmethod == 1
    REMVARCOMP_redmethod_str = 'PCA';
elseif isfield(REMVARCOMP, 'redmethod') && REMVARCOMP.redmethod == 2
    REMVARCOMP_redmethod_str = 'fastICA';
    REMVARCOMP.dimmode = 1; 
%     REMVARCOMP_tolerance_str = nk_ConcatParamstr(REMVARCOMP.tolerance);
%     REMVARCOMP_max_iters_str = nk_ConcatParamstr(REMVARCOMP.max_iters);
%     REMVARCOMP_algorithm_str = REMVARCOMP.algorithm_opt;
%     REMVARCOMP_fun_str = REMVARCOMP.fun_opt;
%     REMVARCOMP_whiten_str = REMVARCOMP.whiten_opt;
%     algoopdef = find(strcmp(algorithms, REMVARCOMP.fun_opt));
%     funopdef = find(strcmp(funs, REMVARCOMP.fun_opt));
%     whitenopdef = find(strcmp(whitens, REMVARCOMP.fun_opt));
end
REMVARCOMP_corrmeth_str = corrmeths{REMVARCOMP.corrmeth};
REMVARCOMP_corrthresh_str = nk_ConcatParamstr(REMVARCOMP.corrthresh);
varopdef = find(strcmp(varops, REMVARCOMP.varop));
REMVARCOMP_recon_str = recons{REMVARCOMP.recon};
switch REMVARCOMP.dimmode
    case 1
        REMVARCOMP_dims_str = ['Fixed: ' nk_ConcatParamstr(REMVARCOMP.dims) ' components '];
    case 3
        REMVARCOMP_dims_str = ['Percentage: ' nk_ConcatParamstr(REMVARCOMP.dims*100) '% of total variance '];
end
REMVARCOMP_subgroup_str = subgroupstr{REMVARCOMP.SUBGROUP.flag};

menustr = [ 'Define dimensionality reduction method [ ' REMVARCOMP_redmethod_str ']|', ...
            'Define target vector / matrix for identification of variance components [ ' RANKVARCOMP_G_str ' ]|', ...
            'Define correlation method for identification of variance components [ ' REMVARCOMP_corrmeth_str ' ]|', ...
            'Define metric for variance component identification [ ' REMVARCOMP.corrcrit ' ]|', ...
            'Define metric cutoff for variance extraction [ ' REMVARCOMP_corrthresh_str  ' ]|', ...
            'Define variance extraction operator [ ' REMVARCOMP.varop  ' ]|', ...
            'Back-project adjusted matrices to input space [ ' REMVARCOMP_recon_str ' ]|'...
            'Define training data for dimensionality reduction model generation [ ' REMVARCOMP_subgroup_str ' ]'];
menuact = 1:8;

if REMVARCOMP.redmethod ~= 2
    menustr = [menustr, '|Define variance retention parameters in PCA projection [ ' REMVARCOMP_dims_str ']'];
    menuact = [menuact 9];
else
    menustr = [menustr, '|Define fastICA parameters'];
    menuact = [menuact 10];
%     menustr = [menustr, '|Define fixed number of independent components in ICA projection [ ' REMVARCOMP_dims_str ']|' , ...
%         'Define tolerance for fastICA algorithm [' REMVARCOMP_tolerance_str ']|'...
%         'Define maximum number of iterations for fastICA algorithm [' REMVARCOMP_max_iters_str ']|'...
%         'Define algorithm for fastICA algorithm [' REMVARCOMP_algorithm_str ']|'...
%         'Define whitening strategy for fastICA algorithm [' REMVARCOMP_whiten_str ']|'...
%         'Define functional form of the G function used in the approximation to neg-entropy for fastICA algorithm [' REMVARCOMP_fun_str ']'...
%         ];
%     menuact = [menuact 10 11 12 13 14 15];
end

%% Print menu
nk_PrintLogo
mestr = 'Extract variance components from matrix'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 
act = nk_input(mestr,0,'mq', menustr , menuact);

% Get user data
switch act
    case 1
        REMVARCOMP.redmethod = nk_input('Choose dimensionality reduction method', 0, 'm', 'PCA|fastICA',[1,2], REMVARCOMP.redmethod);
    case 2
        REMVARCOMP.G = nk_input('Define target vector (matrix) for identification of variance components',0,'e',[],[m Inf]);
    case 3
        REMVARCOMP.corrmeth = nk_input('Define method for identifying variance components',0,'m','Pearson|Spearman|ANOVA', [1,2,3], REMVARCOMP.corrmeth);
    case 4
        corrcritdef = find(strcmp(corrcrits, REMVARCOMP.corrcrit));
        REMVARCOMP.corrcrit = char(nk_input('Define metric for identifying variance components',0,'m','correlation coefficient|P value',corrcrits,corrcritdef));
    case 5
        REMVARCOMP.corrthresh = nk_input('Define single absolute correlation cutoff or multiple cutoffs for variance extraction',0,'e',REMVARCOMP.corrthresh);
    case 6
        varopnum = nk_input('Define variance extraction operator',0,'>|>=|<|<=',{'gt','ge','lt','le'}, varopdef); REMVARCOMP.varop = char(varopnum);
    case 7
        if REMVARCOMP.recon == 1, REMVARCOMP.recon = 2; elseif REMVARCOMP.recon == 2, REMVARCOMP.recon = 1; end
    case 8
        REMVARCOMP.SUBGROUP = nk_SubgroupOperation_config( NM, REMVARCOMP.SUBGROUP );
    case 9
        switch REMVARCOMP.dimmode
            case 1
                dimmodedef = 1;
            case 3
                dimmodedef = 2;
        end
        REMVARCOMP.dimmode = nk_input('Retain fixed number or percentage of variance components',0,'m','Fixed|Percentage',[1,3],dimmodedef);
        switch REMVARCOMP.dimmode
            case 1
                REMVARCOMP.dims = nk_input('Fixed number of variance components to be returned by PCA (1-num(dims))',0,'e',REMVARCOMP.dims); 
            case 3
                REMVARCOMP.dims = nk_input('Percentage of variance components to be returned by PCA (0-1)',0,'e',REMVARCOMP.dims); 
        end
    case 10
        while act > 0
            [REMVARCOMP,PX, act] = cv_fastICA_config(REMVARCOMP, PX, parentstr, []);
        end
  

end

% Register correlation threshold to parameter space if numel(thresholds) > 1 
PX = nk_AddParam(REMVARCOMP.corrthresh, 'CorrThresh', 1, PX, 'replace');
PX = nk_AddParam(REMVARCOMP.dims, 'Dims', 1, PX); 
if act, [REMVARCOMP, PX] = nk_Remvarcomp_config(NM, varind, REMVARCOMP, PX, parentstr); end


