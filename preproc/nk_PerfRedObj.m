function [sY, IN] = nk_PerfRedObj(Y, IN)
% =========================================================================
% FORMAT [sY, IN] = nk_PerfRedObj(Y, IN)
% =========================================================================
% This function is the core dimensionality reduction interface of NM. It
% makes avilable a bunch of methods for extracting patterns from Y using
% unsupervised and supervised algorithms. Learned mappings can be applied
% to out-of-sample (test) data. Not all methods are tested and some do not
% provide a back-projection option. In these cases a vizualisation of the 
% extracted patterns in the original space is not possible.
%
% I/O Arguments:
% -------------------------------------------------------------------------
% Y             : M cases x N features data matrix
% IN.DR         : Dimensionality reduction directives
% IN.mpp        : (Precomputed) mapping / factorization model
% IN.indNonRem  : Non-Zero-variance features
% IN.X          : Training data in original space (for out-of-sample-est)
% IN.mapX       : Embedded training data (for out-of-sample-est)
% sY            : Mapped Y
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 08 / 2020

% =========================== WRAPPER FUNCTION ============================ 
if iscell(Y) && exist('IN','var') && ~isempty(IN)
    sY = cell(1,numel(Y)); 
    for i=1:numel(Y)
        IN.i = i+1;
        [sY{i}, IN] = PerfRedObj(Y{i}, IN); 
    end
else
    [ sY, IN ] = PerfRedObj( Y, IN );
end

% =========================================================================
function [pY, IN] = PerfRedObj(Y, IN)

global VERBOSE TEMPL

% Defaults
if isempty(IN),eIN=true; else, eIN=false; end

% Check for and eliminate zero variance attributes
if eIN || ~isfield(IN,'DR') || isempty(IN.DR), error('Parameters for dimensionality reduction not specified'); end
if eIN || ~isfield(IN,'indNonRem') || isempty(IN.indNonRem)
    if isempty(TEMPL) 
        IN.indNonRem = any(Y); if VERBOSE, fprintf(' removing %g zero features.', sum(~IN.indNonRem)); end
    else
        IN.indNonRem = true(1,width(Y));
    end
end

if isfield(IN.DR,'opt')
    Params_desc = IN.DR.Params_desc;
    opt = IN.DR.opt;
elseif isfield(IN.DR,'dims')
    Params_desc{1} = 'dimensions';
    opt = IN.DR.dims;
else
    Params_desc=[]; opt =[]; IN.DR.dims= [];
end

% Remove zero-variance and nonfinite features
Y( ~isfinite(Y) ) = 0;
Y = Y(:,IN.indNonRem);
if isempty(Y)
    warning('No features in input matrix!!!\nCheck your previous processing steps.')
    Y = nan(1, size(Y,2));
end
if eIN || ~isfield(IN,'mpp') || isempty(IN.mpp)
    
    if VERBOSE, fprintf('==>'); end
    
    if ~isempty(Params_desc); IN.DR.dims = nk_ReturnParam('dimensions', Params_desc, opt); end

    % Dimensionality check
    if ~isempty(IN.DR.dims)
        if VERBOSE, fprintf(' %g', IN.DR.dims); end
        if sum(IN.indNonRem) < IN.DR.dims || size(Y,2) < IN.DR.dims
           fprintf('Number of nonzero features (=%g) in original space less than number of features (=%g) in projected space!', ...
               sum(IN.indNonRem),IN.DR.dims);
           IN.DR.dims = sum(IN.indNonRem)-1;
        end
    end
    
    switch IN.DR.RedMode
        
        case 'PLS'
            IN.cu = nk_ReturnParam('SPLS-cu',Params_desc, opt);
            IN.cv = nk_ReturnParam('SPLS-cv',Params_desc, opt);
            if isfield(IN.DR.PLS,'V')
                L=IN.DR.PLS.V;
            else
                L=IN.DR.labels;
            end
            if isfield(IN.DR.PLS,'algostr'), IN.algostr = IN.DR.PLS.algostr; end
            [pY,pX,~,IN] = nk_PLS(Y, L, IN);
            % If other X designs than the label are used, we can combine the
            % latent scores of both LVs, otherwise we use only the latent
            % scores of Y because otherwise the method will introduce
            % information leakage despite rdCV.
            if IN.DR.PLS.uselabel>1, pY=[pY pX]; end
            
        case 'ProbPCA'
            iter = nk_ReturnParam([IN.DR.RedMode '-Iter'],Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y,IN.DR.RedMode,IN.DR.dims,iter,IN.DR.Modus);

        case 'Laplacian'
            K = nk_ReturnParam([IN.DR.RedMode '-K'],Params_desc, opt);
            Sigma = nk_ReturnParam([IN.DR.RedMode '-Sigma'],Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y,IN.DR.RedMode,IN.DR.dims,K,Sigma,IN.DR.Modus);

        case 'LDA'
            [pY,IN.mpp] = compute_mapping([IN.DR.labels Y],IN.DR.RedMode,IN.DR.dims,IN.DR.Modus);

        case 'LLE'
            IN.DR.Modus = 'JDQR';
            k = nk_ReturnParam('LLE-K',Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y,IN.DR.RedMode, IN.DR.dims, k ,IN.DR.Modus);

        case 'LPP' % Locality preserving projections
            K = nk_ReturnParam('LPP-K',Params_desc, opt);
            Sigma = nk_ReturnParam('LPP-Sigma',Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, K, Sigma, IN.DR.Modus);
            
        case 'AutoEncoder'
            Lambda = nk_ReturnParam('AutoEncoder-Lambda',Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, Lambda, IN.DR.Modus);
            
        case 'LLTSA'
            IN.DR.Modus = 'JDQR';
            k = nk_ReturnParam('LLTSA-K', Params_desc, opt);
            [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, k ,IN.DR.Modus);

        case {'KLDA', 'KFDA', 'KernelLDA', 'KernelFDA', 'GDA'}
            [pY,IN.mpp] = compute_mapping([IN.DR.labels Y],IN.DR.RedMode, IN.DR.dims, IN.DR.Modus);

        case {'PCA','SparsePCA'}
            if isfield(IN.DR,'PercMode') 
                switch IN.DR.PercMode
                    case 1
                        nd = IN.DR.dims;
                    case 2
                        nd = floor(IN.DR.dims*size(Y,1)/100);
                    case 3
                        options.PCARatio = IN.DR.dims;
                        nd = 0;
                end
            end
            switch IN.DR.RedMode
                case 'PCA'
                    SoftType = IN.DR.DRsoft;
                    switch SoftType
                        case 0 % Dimensionality reduction toolbox
                            %fprintf(' (Dim red. toolbox)')
                            [~,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, IN.DR.Modus);
                            M = IN.mpp.mean; vec = IN.mpp.M;
                        case 1 % DrTools
                            %fprintf(' (Deng Cai)')
                            options.ReducedDim = nd;
                            [IN.mpp.vec,IN.mpp.val,IN.mpp.sampleMean, IN.mpp.energy] = PCA(Y, options);
                            M = IN.mpp.sampleMean; vec = IN.mpp.vec;
                    end
                case 'SparsePCA'
                    options.ReducedDim = nd;
                    options.maxiter = nk_ReturnParam('SparsePCA-Iter',Params_desc,opt);
                    options.lambda  = nk_ReturnParam('SparsePCA-Lambda',Params_desc,opt);
                    options.stop    = nk_ReturnParam('SparsePCA-Stop',Params_desc,opt);
                    [IN.mpp.vec, IN.mpp.val, IN.mpp.vec_pca, IN.mpp.val_pca, IN.mpp.sampleMean] = spca(Y, [], options);
                    M = IN.mpp.sampleMean;
                    vec = IN.mpp.vec;
            end

            % Finally, map data to component space
            pY = bsxfun(@minus, Y, M) * vec; 

        case 'RobPCA' % Robust PCA
            results = robpca(Y, 'k', IN.DR.dims, 'kmax', IN.DR.dims,'plots',0);
            IN.mpp.vec = results.P; IN.mpp.val = results.L; IN.mpp.sampleMean = results.M;
            pY = bsxfun(@minus, Y, IN.mpp.sampleMean) * IN.mpp.vec;
            
        case 'NNMF'
            if isfield(IN.DR,'NMFmethod') 
                optFE.feMethod = IN.DR.NMFmethod; 
            else
                optFE.feMethod = 'nmf';
            end
            if isfield(IN.DR,'options')
                optFE.option = IN.DR.options;
            end
            optFE.facts = IN.DR.dims;
            if isfield(IN.DR,'numstarts')
                numstarts = IN.DR.numstarts; 
            else
                numstarts = 1;
            end
            fitRes = Inf;
            nY = norm(Y,'fro'); %Compute the Frobenius norm of Y
            for i=1:numstarts
                [i_pY, i_mpp] = featureExtractionTrain(Y',[], IN.DR.labels, optFE.feMethod, optFE);
                switch optFE.feMethod
                    case {'orthnmf','convexnmf'}
                        W = i_mpp.factors{1}; S = i_mpp.factors{2}; H = i_mpp.factors{3};
                        R = W*S*H;
                    otherwise
                        W = i_mpp.factors{1}; H = i_mpp.factors{2};
                        R = W*H;
                end
                % Compute reconstruction error
                e = norm(Y'-R,'fro')*100/nY;
                % Pick model if reconstruction error is reduced
                if e<=fitRes
                    pY = i_pY; IN.mpp = i_mpp; fitRes = e;
                    fprintf('.. res=%g', fitRes);
                end
            end
            pY = pY'; IN.mpp.r_err = fitRes;
        case {'optNMF', 'NeNMF','NMFlib'}
            switch IN.DR.RedMode
                case 'optNMF'
                    [IN.mpp.W, IN.mpp.H] = opnmf_mem(Y', IN.DR.dims);
                    nY = norm(Y,'fro'); %Compute the Frobenius norm of Y
                    R = IN.mpp.W*IN.mpp.H;
                    % Compute reconstruction error
                    IN.mpp.r_err  = norm(Y'-R,'fro')*100/nY;
                    pY = AUtoPhysicalUnits(Y',IN.mpp.W); pY=pY';
                case 'NeNMF'
                    [IN.mpp.W, IN.mpp.H, IN.mpp.r_err] = feval( IN.DR.NMFmethod, Y', [], [], IN.DR.dims, IN.DR.tmax);
                    pY = AUtoPhysicalUnits(Y',IN.mpp.W); pY=pY';
                case 'NMFlib'
                    switch IN.DR.NMFmethod
                        case 'ordinal-nmf'
                            [out, infos] = ordinalNMF(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = ordinalNMF_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.logLikelihood(end);
                        case 'sparse-mu-nmf'
                            [out, infos] = sparse_mu_nmf(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = sparse_mu_nmf_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.cost_best(end);
                        case 'orth-mu'
                            [out, infos] = orth_mu_nmf(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = orth_mu_nmf_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.cost_best(end);
                        case 'dtpp'
                            [out, infos] = dtpp_nmf(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = dtpp_nmf_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.cost_best(end);
                        case 'hals-so-nmf'
                            [out, infos] = hals_so_nmf(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = hals_so_nmf_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.cost_best(end);
                        case 'alternating_onmf'
                            [out, infos] = alternating_onmf(Y', IN.DR.dims, IN.DR.options);
                            IN.mpp.W = out.W; IN.mpp.H = out.H; 
                            pY = alternating_onmf_test(Y', IN.mpp, IN.DR.options);
                            IN.mpp.r_err = infos.cost_best(end);
                    end
                    pY=pY';
            end
            
        case 'NCA'
            Lambda = nk_ReturnParam('Lambda',Params_desc, opt);
            [pY,IN.mpp] = compute_mapping([IN.DR.labels Y], IN.DR.RedMode, IN.DR.dims, Lambda);
        case 'LMNN'
            [pY,IN.mpp] = compute_mapping([IN.DR.labels Y], IN.DR.RedMode);
        case 'KernelPCA'
            switch IN.DR.kernel.type
                case 'linear'
                    [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims);
                case 'gauss'
                    [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, IN.DR.kernel.type, IN.DR.kernel.sigma);
                case 'poly'
                    [pY,IN.mpp] = compute_mapping(Y, IN.DR.RedMode, IN.DR.dims, IN.DR.kernel.type, IN.DR.kernel.d, IN.DR.kernel.R);
            end
        case 'fastICA'
            if ~isfield(IN,'tolerance')
                IN.tolerance = 1.0000e-04; % default of scikit-learn implementation
                IN.max_iters = 200; % default of scikit-learn implementation
                IN.algorithm_opt = 'parallel';
                IN.fun_opt = 'logcosh';
                IN.whiten_opt = 'unit-variance';
            end
            fastICAoptions.dims = IN.DR.dims;
            fastICAoptions.tolerance = IN.tolerance; % CV: could be added as hyperparameter in the future
            fastICAoptions.max_iters= IN.max_iters; % CV: could be added as hyperparameter in the future
            fastICAoptions.algorithm_opt = IN.algorithm_opt;
            fastICAoptions.whiten_opt = IN.whiten_opt;
            fastICAoptions.fun_opt = IN.fun_opt;

            [pY, IN.mpp] = cv_PerfICA(Y, fastICAoptions, 'train'); 
        otherwise
            [pY,IN.mpp] = compute_mapping(Y,IN.DR.RedMode, IN.DR.dims, IN.DR.Modus);
    end
    % Re-order components to map current 
    % component space to template component space.
    % This currently works only for PCA. To make it work for more methods, 
    % we need to assign from the different transformation matrix structures 
    % to target and reference matrices (according to dim red techniques).
    if isfield(IN.DR,'mpp_template') && ~isempty(IN.DR.mpp_template) && (isfield(TEMPL,'execute_template_creation') && ~TEMPL.execute_template_creation)
        if VERBOSE, fprintf(' Run procrustes transform ...'); end
        switch IN.DR.RedMode
            case {'PCA', 'RobPCA', 'FactorAnalysis', 'SparsePCA', 'ProbPCA'}
                [aligned_target, aligned_targetval] = nk_AlignPCAModels(IN.DR.mpp_template.vec , IN.mpp.vec, IN.mpp.val);
                IN.mpp.vec = aligned_target;
                IN.mpp.val = aligned_targetval;
                pY = bsxfun(@minus, Y, M) * IN.mpp.vec; 
            otherwise
                if VERBOSE, fprintf(' currently not supported for %s', IN.DR.RedMode); end
        end
    end
else
    switch IN.DR.RedMode
        case 'PLS'
            [pY, pX] = nk_PLS(Y, IN.DR.PLS.VT{IN.i}, IN);
            % If other X designs than the label are used, we can combine the
            % latent scores of both LVs, otherwise we use only the latent
            % scores of Y because otherwise the method will introduce
            % information leakage despite rdCV.
            if IN.DR.PLS.uselabel>1, pY = [ pY pX ]; end
        case {'PCA','SparsePCA'}
            switch IN.DR.DRsoft
                case 0
                    pY = out_of_sample(Y, IN.mpp);
                case 1
                    % corrected on the 11/11/2023, the floating point
                    % precision is insufficient to produce identical
                    % results across different matrices with partly
                    % identical rows. Therefore the precision is reduced
                    % using round at 9 decimal places (potentially this
                    % needs to be adapted in the future(
                    pY = round(bsxfun(@minus, Y, IN.mpp.sampleMean) * IN.mpp.vec, 9);    
            end
        case 'RobPCA'
            pY = bsxfun(@minus, Y, IN.mpp.sampleMean) * IN.mpp.vec;
        case 'NNMF'
            pY = featureExtrationTest(IN.TrX',Y',IN.mpp); pY = pY';
        case {'optNMF','NeNMF'}
            pY = AUtoPhysicalUnits(Y',IN.mpp.W); pY=pY';
        case 'NMFlib'
            switch IN.DR.NMFmethod
                case 'ordinal-nmf'
                    pY = ordinalNMF_test(Y', IN.mpp, IN.DR.options);
                case 'sparse-mu-nmf'
                    pY = sparse_mu_nmf_test(Y', IN.mpp, IN.DR.options);
                case 'orth-mu'
                    pY = orth_mu_nmf_test(Y', IN.mpp, IN.DR.options);
                case 'dtpp'
                    pY = dtpp_nmf_test(Y', IN.mpp, IN.DR.options);
                case 'hals-so-nmf'
                    pY = hals_so_nmf_test(Y', IN.mpp, IN.DR.options);
                case 'alternating_onmf'
                    pY = alternating_onmf_test(Y', IN.mpp, IN.DR.options);
            end
            pY = pY';
        case 'SPCA'
            pY = nk_PerfSPCA(Y, IN.mpp);
        case 'fastICA'
            pY = cv_PerfICA(Y, IN.mpp, 'test');
        otherwise
            try
                pY = out_of_sample(Y, IN.mpp);
            catch
                warning('deterministic out of sample extension does not exist! Trying out-of-sample estimation procedure')
                pY = out_of_sample_est(Y, IN.TrX, IN.mappedX);
            end
    end
end
