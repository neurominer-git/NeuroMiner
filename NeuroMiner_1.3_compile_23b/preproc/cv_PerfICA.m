function [pY, mapping] = cv_PerfICA(Y, opt, mode)
% function to extract independent components from data
% Input: Y - input data (N*D)
% Output: pY - output data (N*IC)
% in training mode, the ICs are computed; during testing the ICs are
% projected onto the unseen data (after unseen data is whitened)
global MODELDIR

if strcmp(mode, 'train') % in training mode

    if isfield(opt, 'dims')
        n_ics = opt.dims; % potentially add more options here, then opt should be struct with fields
    else
        n_ics = 0;
    end

    if isfield(opt, 'tolerance')
        tol = opt.tolerance; % potentially add more options here, then opt should be struct with fields
    else
        tol = 1e-4;
    end

    if isfield(opt, 'max_iters')
        n_iter = opt.max_iters; % potentially add more options here, then opt should be struct with fields
    else
        n_iter = 200;
    end

    if isfield(opt, 'whiten_opt')
        whiten_opt = opt.whiten_opt; % potentially add more options here, then opt should be struct with fields
    else
        whiten_opt = 'arbitrary-variance';
    end

    if isfield(opt, 'fun_opt')
        fun_opt = opt.fun_opt; % potentially add more options here, then opt should be struct with fields
    else
        fun_opt = 'logcosh';
    end

    if isfield(opt, 'algorithm_opt')
        algorithm_opt = opt.algorithm_opt; % potentially add more options here, then opt should be struct with fields
    else
        algorithm_opt = 'parallel';
    end

    %mode = 'train';
    data = Y;
    num_ics = int64(n_ics);
    num_iter = int64(n_iter);
    tolerance = double(tol);
    whiten_str = whiten_opt;
    algorithm_str =  algorithm_opt;
    fun_str = fun_opt;

    if num_ics == 0

        num_ics = 'None';

    end

    ica = py.sklearn.decomposition.FastICA(n_components=num_ics, ...
        algorithm = algorithm_str, ...
        fun = fun_str, ...
        max_iter = num_iter, ...
        tol = tolerance, ...
        whiten = whiten_str, ...
        random_state = int8(1234));

    ica_model = ica.fit(data); % # Reconstruct signals
    S = ica_model.transform(data);
    ICs = ica_model.components_;


    % [model_file, S, ICs] = pyrunfile('cv_py_PerfICA.py', ["model_file" "S", "ICs"], ...
    %     mode = 'train', ...
    %     data = Y, ...
    %     num_ics = int64(n_ics), ...
    %     num_iter = int64(n_iter), ...
    %     tolerance = double(tol), ...
    %     whiten_str = whiten_opt, ...
    %     algorithm_str =  algorithm_opt, ...
    %     fun_str = fun_opt, ...
    %     rootdir = MODELDIR);

    pY = py2mat(S); % transpose so that nrows = nsamples, ncols = nICs
    % mapping.ica_py_model_file = model_file;
    mapping.ica_py_model = ica_model;
    mapping.vec = py2mat(ICs)';
    mapping.sampleMean = mean(Y,1);
elseif strcmp(mode, 'test') % test mode
    mapping = opt;
    ica_model = mapping.ica_py_model;
    S = ica_model.transform(Y);
    % S = pyrunfile('cv_py_PerfICA.py', 'S' , ...
    %     mode = 'test', ...
    %     ica_model = mapping.ica_py_model_file, ...
    %     data = Y);
    pY = py2mat(S);
elseif strcmp(mode, 'inverse_transform')
    mapping = opt;
    ica_model = mapping.ica_py_model;
    S = ica_model.inverse_transform(Y);
    % S = pyrunfile('cv_py_PerfICA.py', 'S' , ...
    %     mode = 'inverse_transform', ...
    %     ica_model = mapping.ica_py_model_file, ...
    %     data = Y);
    pY = py2mat(S);
end
end


