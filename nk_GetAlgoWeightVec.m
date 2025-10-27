function [xV, AnalP] = nk_GetAlgoWeightVec(SVM, Y, L, MD, decompfl, errorflag)
global STACKING

AnalP = []; xV=[];
switch SVM.prog
    case {'LIBSVM','LIBLIN'}
        switch SVM.kernel.kernstr
            case{' -t 0',' -t 4',' -t 5','lin', 'linear', 'none'} 
                %%%%%%%%%%%%% USE WEIGHTS OF MODEL %%%%%%%%%%%%
                xV = nk_GetPrimalW(MD); % Get weight vector over feature space
                if sum(decompfl==0)>0
                    % Remove cases which are completely NaN
                    [Yn, Ln] = nk_ManageNanCases(Y, L);
                    try
                        AnalP = compute_analytical_pvals(Ln,Yn,xV'); 
                    catch
                        who Ln Yn xV
                    end
                end
            otherwise % non-linear
                %%%%%%%%%% COMPUTE MIN. DIFF. VECTORS %%%%%%%%% 
                xV = nk_VisSV(MD, Y, L);
        end
    case 'MEXELM'
        xV = nm_nanmean(MD.inW)';
    case  'GLMFIT'
        xV = MD.beta(2:end);
    case 'matLRN'
        % Check whether addBias == 1 and whether algo was kernalized
        offs=1; if isfield(MD,'addBias') && MD.addBias, offs = 2; end
        if isfield(MD,'kernel') && MD.kernel
            error('Unfortunately, the pre-image of the kernel weight vector cannot be computed with the current version NM.'); 
        end
        if isfield(MD,'w')
            w = MD.w;
        elseif isfield(MD,'weights')
            w = MD.weights;
        else
            error(sprintf('\nNo weight vector found in matLearn model. Unfortunately, the visualization of this model is not supported by NM.'));
        end
        xV = w(offs:end);  
    case 'GLMNET'
        xV = MD.beta;
    case {'RNDFOR', 'GRDBST', 'MLPERC', 'TFDEEP', 'BAYLIN'}
        %xV = MD.feature_importances_ %This gets the Gini importance of
        %features, but it isn't compatible with SVM weights since they
        %don't mean the same. 
        xV = nk_GetGradientWeight(MD, Y);
    case 'DECTRE'
        xV = MD.predictorImportance;
    case 'SEQOPT'
        nF = numel(STACKING.sel_anal);
        xV = zeros(nF,1);
        xV(MD.AnalSeq) = (MD.examsfreq(MD.examsfreq>0)/100)';
    case 'WBLCOX'
        xV = MD.beta;
    case 'IMRELF'
        xV = MD.Weight;
    case 'ELASVM'
        xV = MD.beta;
    case {'MVTRVR', 'MVTRVM'}
        % regression
        if size(MD.weights, 2) == 1
            xV = zeros(size(Y,2),1);
            xV(MD.rv) = MD.weights;
        end
        % classification TO DO
    case 'MikRVM'
        % Exact primal weights for LINEAR kernel; RV-based approximation for others

        assert(isfield(MD,'P') && isfield(MD.P,'Relevant') && isfield(MD.P,'Value'), ...
            'MikRVM: MD.P.Relevant / MD.P.Value not found.');

        N = size(Y,1);           % cases
        p = size(Y,2);           % features
        a = zeros(N,1);
        a(MD.P.Relevant(:)) = MD.P.Value(:);

        % Detect kernel type (adjust to your kernel string conventions)
        kern = ''; 
        if isfield(SVM,'kernel') && isfield(SVM.kernel,'kernstr')
            kern = lower(SVM.kernel.kernstr);
        end
        isLinear = contains(kern, {'lin','linear'}) || strcmp(kern,' -t 0');

        if isLinear
            % LINEAR kernel, no bias: exact primal weights
            xV = Y' * a;                 % (p x 1)
        else
            % NON-LINEAR kernel (e.g., RBF): fall back to RV-based linear approx
            [Vmean, ~] = nk_VisRV(MD, Y, L);
            xV = Vmean(:);               % (p x 1)
        end

        % Optional: analytical p-values (same pattern as your linear SVM)
        if sum(decompfl==0)>0
            [Yn, Ln] = nk_ManageNanCases(Y, L);
            try
                AnalP = compute_analytical_pvals(Ln, Yn, xV'); 
            catch
                who Ln Yn xV
            end
        end

    otherwise
        if errorflag
            error(['Vizualisation for ' SVM.prog ' not supported yet. Please consult the NM Manual for more information']);
        end
end
if ~any(xV)
    error('The feature weight vector contains only 0. Check your settings'); 
end