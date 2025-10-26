function v = nk_CompVectorFromOSH2X(x, model, prog, normfl)
% =========================================================================
% function v = nk_CompVectorFromOSH2X(x, model, prog, normfl)
% =========================================================================
% Computes the vector from the Optimally Separating Hyperplane to
% observation x (in linear kernel space, case LIBSVM) by computing the
% the perpendicular projection of x on the OSH and measuring the vector
% between x and that point on the OSH
% not to be used with non-linear kernels!
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris 12/2023

if ~exist("normfl","var") || isempty(normfl)
    normfl = true;
end

if ~exist("prog","var") || isempty(prog)
    if isfield(model,'SVs')
        prog = 'LIBSVM';
    elseif isfield(model,'w')
        prog = 'LIBLIN';
    else
        error('\nFunction supports currently only LIBLINEAR or LIBSVM models');
    end
end

switch prog

    case 'LIBSVM'
        % Get the weights and bias from the model       
        w = model.SVs' * model.sv_coef;
        b = -model.rho; % The bias term with the opposite sign in LIBSVM

    case 'LIBLIN'
        % Get the weights and bias from the model
        if model.bias == 1
            w = model.w(1:end-1);  % Extract weights
            b = model.w(end);   
        else
            w = model.w;  % Extract weights as a column vector
            b = 0;
        end
end

% Calculate the vector from the OSH to 'x'
v = x(:) - (w' * x + b) * w / norm(w);

% Normalize the feature weights of 'v' while preserving their signs
if normfl, v = v / norm(v); end