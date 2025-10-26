function [FASTICA, PX, act] = cv_fastICA_config(FASTICA, PX, parentstr, defaultsfl)

if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end

algorithms = {'parallel', 'deflation'};
algorithm_opt = 'parallel';
funs = {'logcosh', 'exp', 'cube'};
fun_opt = 'logcosh';
whitens = {'unit-variance', 'arbitrary-variance'};
whiten_opt = 'unit-variance';

if ~defaultsfl
    if ~isfield(FASTICA, 'dimmode')
        FASTICA.dimmode = 1;
    end
    if ~isfield(FASTICA, 'dims')
        FASTICA.dims = 0;
    end

    if ~isfield(FASTICA, 'tolerance')
        FASTICA.tolerance = 1e-4;
    end

    if ~isfield(FASTICA, 'max_iters')
        FASTICA.max_iters = 200;
    end

    if ~isfield(FASTICA, 'whiten_opt')
        FASTICA.whiten_opt = whiten_opt;
    end

    if ~isfield(FASTICA, 'fun_opt')
        FASTICA.fun_opt = fun_opt;
    end

    if ~isfield(FASTICA, 'algorithm_opt')
        FASTICA.algorithm_opt = algorithm_opt;
    end


    REMVARCOMP_tolerance_str = nk_ConcatParamstr(FASTICA.tolerance);
    REMVARCOMP_max_iters_str = nk_ConcatParamstr(FASTICA.max_iters);
    REMVARCOMP_algorithm_str = FASTICA.algorithm_opt;
    REMVARCOMP_fun_str = FASTICA.fun_opt;
    REMVARCOMP_whiten_str = FASTICA.whiten_opt;
    algoopdef = find(strcmp(algorithms, FASTICA.fun_opt));
    funopdef = find(strcmp(funs, FASTICA.fun_opt));
    whitenopdef = find(strcmp(whitens, FASTICA.fun_opt));

    switch FASTICA.dimmode
        case 1
            REMVARCOMP_dims_str = ['Fixed: ' nk_ConcatParamstr(FASTICA.dims) ' components '];
        case 3
            REMVARCOMP_dims_str = ['Percentage: ' nk_ConcatParamstr(FASTICA.dims*100) '% of total variance '];
    end


    menustr = ['Define fixed number of independent components in ICA projection [ ' REMVARCOMP_dims_str ']|' , ...
        'Define tolerance for fastICA algorithm [' REMVARCOMP_tolerance_str ']|'...
        'Define maximum number of iterations for fastICA algorithm [' REMVARCOMP_max_iters_str ']|'...
        'Define algorithm for fastICA algorithm [' REMVARCOMP_algorithm_str ']|'...
        'Define whitening strategy for fastICA algorithm [' REMVARCOMP_whiten_str ']|'...
        'Define functional form of the G function used in the approximation to neg-entropy for fastICA algorithm [' REMVARCOMP_fun_str ']' ];


    menuact = 1:6;


    nk_PrintLogo
    mestr = 'fastICA settings'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr);
    act = nk_input(mestr,0,'mq', menustr, menuact);

    switch act
        case 1
            FASTICA.dimmode = 1;
            FASTICA.dims = nk_input('Fixed number of independent components to be returned by fastICA (1-num(dims))',0,'e', FASTICA.dims);
        case 2
            FASTICA.tolerance = nk_input('Tolerance parameter (tol) of fastICA algorithm (scikit-learn)',0,'e', FASTICA.tolerance);
        case 3
            FASTICA.max_iters = nk_input('Maximum iterations parameter (max_iter) of fastICA algorithm (scikit-learn)',0,'e', FASTICA.max_iters);
        case 4
            algoopnum = nk_input('Choose algorithm for fastICA', 0, 'parallel|deflation', algorithms, algoopdef);
            FASTICA.algorithm_opt = char(algoopnum);
        case 5
            whitenopnum = nk_input('Choose whitening strategy for fastICA', 0, 'unit-variance|arbitrary-variance',whitens, whitenopdef);
            FASTICA.whiten_opt = char(whitenopnum);
        case 6
            funopnum = nk_input('Choose functional form of the G function used in the approximation to neg-entropy for fastICA', 0, 'logcosh|exp|cube',funs, funopdef);
            FASTICA.fun_opt = char(funopnum);
    end
else
    act = 0;
end

PX = nk_AddParam(FASTICA.tolerance, 'FastICA_tol', 1, PX);
PX = nk_AddParam(FASTICA.max_iters, 'FastICA_max_iter', 1, PX);
end