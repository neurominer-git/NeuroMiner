function [sY, IN, dT] = nk_PerfAdjForCovarsUsingPCAObj(Y, IN, S)
% =========================================================================
% [sY, IN, dT] = nk_PerfAdjForCovarsUsingPCAObj(Y, IN, S)
% =========================================================================
% Adjusts a target data matrix for covariate effects by projecting it into
% a dimensionality-reduced space (PCA or ICA) derived from a source matrix,
% identifying components correlated with covariates, and reconstructing the
% target matrix with the components retained (or returns the pruned target 
% matrix as is for downstream analyses).
%
% ----------------------------- INPUTS ------------------------------------
% Y :    Target matrix (rows = patterns, cols = features).
%        If cell array, adjustment is performed per cell element.
%
% IN :   Structure containing parameters and covariates:
%        IN.G          - Covariate matrix (rows = patterns).
%        IN.recon      - Reconstruction mode (1 = back-project adjusted 
%                        matrix to input space [default], 
%                        2 = return reduced-space representation).
%        IN.varop      - Operator for thresholding correlated factors 
%                        ('gt','lt','ge','le'; default: 'gt').
%        IN.corrmeth   - Correlation method for factor–covariate association:
%                          1 = Pearson [default], 2 = Spearman, 3 = ANOVA.
%        IN.corrthresh - Cutoff for correlation strength or p-value 
%                        (default: 0.3).
%        IN.corrcrit   - Thresholding criterion: 'corr' (default) or 'pval'.
%        IN.DR         - Dimensionality reduction parameters (see
%                        nk_DimRed_config). If not provided, PCA is used
%                        with percentage-of-variance mode.
%        IN.indX       - Logical index vector selecting subset of rows in S
%                        used to compute factorization (default: all rows).
%
% S :    Source matrix used to (1) compute the reduced embedding space and 
%        (2) identify variance components associated with covariates.
%
% ----------------------------- OUTPUTS -----------------------------------
% sY :   Adjusted target matrix (cell array if Y was a cell array).
% IN :   Updated parameter structure with computed reduction / correlation 
%        parameters (e.g., loadings, correlation values, masks).
% dT :   Dimensionality-reduced representation of the (adjusted) target.
%
% ----------------------------- NOTES -------------------------------------
% This approach is conceptually similar to component-based denoising methods 
% in neuroimaging such as:
%   - CompCor (Behzadi et al., NeuroImage 2007): PCA on a source matrix, 
%     identification of nuisance-related components, removal and reconstruction.
%   - ICA-AROMA (Pruim et al., NeuroImage 2015): ICA decomposition, 
%     classification of motion-related components, reconstruction without them.
%
% Both methods identify and remove variance components associated with 
% nuisance or covariate effects before back-projecting the cleaned signal, 
% which is the strategy applied here.
%
% Wavelet RemVarComp extension:
%   redmethod = 3 -> waveletPCA  (PCA inside signed a trous bands)
%   redmethod = 4 -> waveletICA  (fastICA inside signed a trous bands)
% The wavelet extension is a trained operator: band definitions, PCA/ICA
% mappings and component-wise attenuation weights are learned in the training
% partition and reused unchanged for test data. Test/application data are
% projected into the frozen per-band component spaces; no target-row scanner
% covariates are required or used.
% =========================================================================
% (c) Nikolaos Koutsouleris, 07/2023
% =========================================================================

% =========================== WRAPPER FUNCTION ============================ 
if ~exist('S','var'), S=[]; end
if iscell(Y) && exist('IN','var') && ~isempty(IN)
    sY = cell(1,numel(Y)); dT = [];
    for i=1:numel(Y), [sY{i}, IN] = PerfAdjForCovarsUsingPCAObj(Y{i}, IN, S); end
else
    [ sY, IN, dT ] = PerfAdjForCovarsUsingPCAObj( Y, IN, S );
end

end

% =========================================================================
function [adjT, IN, dT] = PerfAdjForCovarsUsingPCAObj(T, IN, S)
% =========================================================================
% [adjT, IN, dT] = PerfAdjForCovarsUsingPCAObj(T, IN, S)
% =========================================================================
% Core routine for covariate adjustment using PCA/ICA. 
% Projects a target matrix into the embedding space of a source matrix, 
% identifies variance components correlated with covariates, and reconstructs 
% the target matrix with those components retained (or just returns the pruned 
% target matrix as is for downstream analyses).
%
% ----------------------------- INPUTS ------------------------------------
% T :    Target matrix (rows = patterns, cols = features) to be adjusted.
%
% IN :   Structure with parameters and covariates:
%        IN.G          - Covariate matrix (rows = patterns).
%        IN.recon      - Reconstruction mode (1 = back-project adjusted 
%                        matrix to input space [default], 
%                        2 = return reduced-space representation).
%        IN.varop      - Operator for thresholding correlated factors 
%                        ('gt','lt','ge','le'; default: 'gt').
%        IN.corrmeth   - Method to assess factor–covariate correlation:
%                          1 = Pearson [default], 2 = Spearman, 3 = ANOVA.
%        IN.corrthresh - Cutoff for correlation strength or p-value 
%                        (default: 0.3).
%        IN.corrcrit   - Thresholding criterion: 'corr' (default) or 'pval'.
%        IN.DR         - Dimensionality reduction parameters (see 
%                        nk_DimRed_config). Defaults to PCA.
%        IN.indX       - Logical index vector specifying rows in S to use 
%                        for factorization (default: all rows).
%
% S :    Source matrix used to compute the reduced embedding space and to 
%        identify components correlated with covariates.
%
% ----------------------------- OUTPUTS -----------------------------------
% adjT : Adjusted target matrix (back-projected or reduced representation,
%        depending on IN.recon).
% IN :   Updated parameter structure containing computed reduction and
%        correlation parameters.
% dT :   Dimensionality-reduced representation of the target matrix.
%
% =========================================================================
global VERBOSE

% Wavelet-domain RemVarComp extension. This path deliberately reuses the
% existing image-preserving nk_WaveletSpatialReconstruct backend and the
% existing nk_PerfRedObj dimensionality-reduction interface per wavelet band.
if local_is_wavelet_remvarcomp(IN)
    [adjT, IN, dT] = local_PerfAdjForCovarsUsingWaveletObj(T, IN, S);
    return
end

% Check existence of paramater structure
if ~exist('IN','var') || isempty(IN)          
    error('No parameter structure specified! Abort!');  
end
if ~isfield(IN,'recon') || isempty(IN.recon)
    IN.recon = 1;
end
if ~isfield(IN,'varop') || isempty(IN.varop)
    IN.varop = 'gt';
end
    
compfl = false;
% Check whether variance removal parameters have been already computed
if ~isfield(IN,'ind0') || isempty(IN.ind0)
    
    compfl = true;
    % The source data matrix to compute the factorized matrix from
    if ~exist('S','var') || isempty(S)
        error('No training matrix specified in parameter structure'); 
    end
    % The source covariate matrix to compute correlation coefficients with
    % factorized data matrix
    if (~isfield(IN,'G') || isempty(IN.G))
        error('No target vector / matrix specified in parameter structure'); 
    end
    % The defaults correlation method
    if ~isfield(IN,'corrmeth') || isempty(IN.corrmeth)
        IN.corrmeth = 1;                                    
    end
    switch IN.corrmeth
        case 1
            corrmeth = 'pearson';
        case 2
            corrmeth = 'spearman';
        case 3
            corrmeth = 'anova';
    end

    % The default correlation strength 
    if ~isfield(IN,'corrthresh') || isempty(IN.corrthresh)
        IN.corrthresh = 0.3;                                
    end
    
    % if not otherwise specified use the entire source data matrix
    if ~isfield(IN,'indX') || isempty(IN.indX)
        IN.indX = true(size(S,1),1);
    end
    
    % if not otherwise specified use PCA in the 'percentage of
    % sum(eigenvalues) mode'

    % CV Note: this can potentially also be adjusted so that DR.RedMode is
    % directly set in _config
    if (~isfield(IN,'DR') || isempty(IN.DR) || ~isfield(IN.DR,'RedMode')) && (~isfield(IN, 'redmethod') || IN.redmethod == 1)
        IN.DR.DRsoft = 1; 
        IN.DR.RedMode = 'PCA';
        IN.DR.PercMode = IN.dimmode;  
    elseif (~isfield(IN,'DR') || isempty(IN.DR) || ~isfield(IN.DR,'RedMode')) && IN.redmethod == 2 
        IN.DR.RedMode = 'fastICA'; 
        IN.DR.PercMode = IN.dimmode; % unecessary, might affect nk_PerfRedObj
        IN.DR.DRsoft = 1; % unused, might affect nk_PerfRedPbj
        IN.DR.whiten_opt = IN.whiten_opt; 
        IN.DR.algorithm_opt = IN.algorithm_opt; 
        IN.DR.fun_opt = IN.fun_opt; 
    end
    
    % Run dimensionality reduction on the source matrix
    [dS, IN] = nk_PerfRedObj(S(IN.indX,:),IN);
    IN.C = zeros(size(dS,2),size(IN.G,2));
    IN.Pvalue = IN.C;

    % Identify correlated factors in the factorized source matrix
    switch corrmeth
        case {'pearson', 'spearman'}
            for i = 1:size(IN.G,2)
                % Determine correlations with covars in the source matrix
                [Cvalues,~,~,Pvalues] = nk_CorrMat(dS,IN.G(IN.indX,i),corrmeth);
                IN.C(:,i)=abs(Cvalues); IN.Pvalue(:,i)=Pvalues;
                IN.C(isinf(IN.C(:,i)) | isnan(IN.C(:,i)),i) = 0;
                if VERBOSE 
                    maxi = max(IN.C(:,i)); 
                    fprintf('\nWorking on covariate #%g => max=%g', i, maxi); 
                end
            end
        case 'anova'
            % This is the more powerful option if we have multiple covars
            % for which we would like to identify respective variance
            % components
            RES.X = [ones(size(IN.G(IN.indX,:),1),1) IN.G(IN.indX,:)];
            RES = nk_PerfANOVAObj(dS, RES);
            IN.C = sqrt(RES.R2);
            IN.Pvalue = RES.p;
            IN.C(isinf(IN.C) | isnan(IN.C)) = 0;
            if VERBOSE
                maxi = max(IN.C); 
                fprintf('\nDummy matrix => max=%g', maxi); 
            end
    end

    % Threshold eigenvariate correlations with covars
    switch IN.corrcrit
        case 'corr'
            IN.subthresh = any(single(feval(IN.varop, IN.C, IN.corrthresh)),2);
        case 'pval'
            IN.subthresh = any(single(feval(IN.varop, IN.Pvalue, IN.corrthresh)),2);
    end

    % Check whether correlated factors exist or not!
    if ~sum(IN.subthresh)
        IN.ind0 = true(1,size(dS,2));
        warning('\nNo variance components identified at %g threshold. Returning unchanged matrix!', IN.corrthresh);
        switch IN.recon
            case 1
              adjT = T;
            case 2
              if isempty(T) ||(isequal(T, S) && sum(IN.indX) == size(S,1))
                 adjT = dS; 
              else
                 adjT = nk_PerfRedObj(T,IN);
              end
        end
        dT = adjT;
        return
    elseif sum(IN.subthresh) == size(IN.subthresh,2)
        IN.ind0 = true(1,size(dS,2));
        warning('\nAll variance components identified at %g threshold. Returning unchanged matrix!', IN.corrthresh);
        switch IN.recon
            case 1
              adjT = T;
            case 2
              if isempty(T) ||(isequal(T, S) && sum(IN.indX) == size(S,1))
                 adjT = dS; 
              else
                 adjT = nk_PerfRedObj(T,IN);
              end
        end
        dT = adjT;
        return
    end

    % Determine which eigenvariates have to be extracted
    IN.ind0 = ~IN.subthresh;
end
if ~any(IN.ind0) 
    warning('All eigenvariates meet threshold criterion [%s %g]!\nCheck your data and your settings.',IN.varop,IN.corrthresh);
end
    
% Now project target matrix to source matrix embedding space
if VERBOSE, fprintf(sprintf('\nProjecting target matrix to source %s space', IN.DR.RedMode)); end
if isempty(T) ||(exist('S','var') && isequal(T, S) && sum(IN.indX) == size(S,1))
    if exist('dS','var')
        dT = dS; 
    else
        % Run dimensionality reduction on the source matrix
        dT = nk_PerfRedObj(S(IN.indX,:),IN);
    end
else
    dT = nk_PerfRedObj(T,IN);
end

switch IN.recon
    case 1
        % Reconstruct target matrix only with / without extracted variance
        % componentsp
        if VERBOSE, fprintf('\nReconstructing target matrix based on selected components.'); end
        
        if strcmp(IN.DR.RedMode, 'fastICA')
            dT(:,~IN.ind0) = 0;
            [tT, IN.mpp] = cv_PerfICA(dT, IN.mpp, 'inverse_transform');
            adjT = zeros(size(dT,1),numel(IN.indNonRem)); adjT(:,IN.indNonRem) = tT;
        else
            tT = bsxfun(@plus, IN.mpp.vec(:,IN.ind0)* dT(:,IN.ind0)' , IN.mpp.sampleMean')';
            adjT = zeros(size(dT,1),numel(IN.indNonRem)); adjT(:,IN.indNonRem) = tT;
        end
    case 2
        if VERBOSE, fprintf('\nLimiting target matrix to selected components.'); end
        % Limited projected target matrix to selected variance components
        adjT = dT(:,IN.ind0);
end

if VERBOSE
    s0 = sum(~IN.ind0); if ~s0, fprintf('???'); end
    if compfl
        switch IN.varop
            case 'gt'
                varopstr = '>';
            case 'lt'
                varopstr = '<';
            case 'ge'
                varopstr = '>=';
            case 'le'
                varopstr = '<=';
        end
        switch IN.corrcrit
            case 'corr'
                critstr = 'correlation coefficient';
                funci = @max; funcistr = 'max'; mx = IN.C(~IN.ind0,:); 
            case 'pval'
                critstr = 'p value';
                funci = @min; funcistr = 'min'; mx = IN.Pvalue(~IN.ind0,:); 
        end
        fprintf(['\nProcessing finished. %g/%g components with %s %s %g (%s: %g) were identified.', ...
            '\nRespective variance components was extracted from the input matrix.\n'],s0, size(IN.mpp.vec,2), critstr, varopstr, IN.corrthresh, funcistr, funci(mx(:))); 
    else
        fprintf('\nProcessing finished. %g variance components were removed from input matrix', s0)
    end
end

end


% =========================================================================
function tf = local_is_wavelet_remvarcomp(IN)
% =========================================================================
tf = false;
if ~exist('IN','var') || isempty(IN) || ~isstruct(IN), return; end
if isfield(IN,'WAVELETREMVARCOMP') && ~isempty(IN.WAVELETREMVARCOMP)
    tf = true; return;
end
if isfield(IN,'redmethod') && ~isempty(IN.redmethod) && any(double(IN.redmethod(1)) == [3 4 5])
    tf = true; return;
end
if isfield(IN,'DR') && isstruct(IN.DR) && isfield(IN.DR,'RedMode') && ~isempty(IN.DR.RedMode)
    rm = lower(char(IN.DR.RedMode));
    tf = strncmp(rm,'wavelet',7);
end
end

% =========================================================================
function [adjT, IN, dTcat] = local_PerfAdjForCovarsUsingWaveletObj(T, IN, S)
% =========================================================================
% Wavelet-domain supervised nuisance attenuation for remvarcomp.
%
% Fit mode:
%   [adjT, IN] = ... (T, IN, S)
% learns a fixed a-trous wavelet decomposition, runs nk_PerfRedObj inside
% each signed reconstruction band, estimates component-wise nuisance
% association strengths, stores all band/component attenuation coefficients in IN,
% and either subtracts the corresponding soft component-axis back-projection
% from the original wavelet bands or returns the attenuated component scores.
%
% Transform mode:
%   adjT = ... (T, trainedIN)
% reuses the stored band models and attenuation coefficients. It never
% re-estimates wavelet bands, component bases or association metrics on
% held-out/test data and does not require target-row covariates for unseen
% scanners.
%
% The implementation avoids low-rank whole-image reconstruction. Each band is
% adjusted by subtracting only the learned soft component-axis back-projection:
%   adjusted_band = original_band - learned_component_axis_backprojection.
% If outputDomain='image', the final image is recomposed as A_J + D_1 + ... + D_J
% when the selected band set is a full a-trous partition. If outputDomain='embedding',
% the returned matrix is the concatenated adjusted per-band component scores.

global VERBOSE
if nargin < 3, S = []; end
if isempty(T), adjT = T; dTcat = []; return; end

[WR, IN] = local_wavelet_defaults(IN);
if ~isfield(WR,'SPATIAL') || isempty(WR.SPATIAL) || ~isfield(WR.SPATIAL,'dims') || ~isfield(WR.SPATIAL,'indvol')
    error('nk_PerfAdjForCovarsUsingPCAObj:missingWaveletGeometry', ...
        ['Wavelet remvarcomp requires image geometry in IN.WAVELETREMVARCOMP.SPATIAL or IN.SPATIAL. ', ...
         'This should be resolved internally from the active imaging modality/mask; it is not a user-facing wavelet option.']);
end
if exist('nk_WaveletSpatialReconstruct','file') ~= 2
    error('nk_PerfAdjForCovarsUsingPCAObj:missingWaveletBackend', ...
        'nk_WaveletSpatialReconstruct is required for wavelet remvarcomp but is not on the MATLAB path.');
end

fitMode = ~isfield(IN,'WAVELETREMVARCOMP_MODEL') || isempty(IN.WAVELETREMVARCOMP_MODEL);
if fitMode
    if ~exist('S','var') || isempty(S)
        error('nk_PerfAdjForCovarsUsingPCAObj:noTrainingMatrix', ...
            'Wavelet remvarcomp fit requires the source/training matrix S.');
    end
    if ~isfield(IN,'G') || isempty(IN.G)
        error('nk_PerfAdjForCovarsUsingPCAObj:noCovariates', ...
            'Wavelet remvarcomp requires IN.G nuisance covariates in fit mode.');
    end
    if isvector(IN.G), IN.G = IN.G(:); end
    if ~isfield(IN,'indX') || isempty(IN.indX)
        IN.indX = true(size(S,1),1);
    else
        IN.indX = logical(IN.indX(:));
    end
    if numel(IN.indX) ~= size(S,1)
        error('nk_PerfAdjForCovarsUsingPCAObj:badIndX', ...
            'IN.indX has %d entries but S has %d rows.', numel(IN.indX), size(S,1));
    end
    if size(IN.G,1) ~= size(S,1)
        error('nk_PerfAdjForCovarsUsingPCAObj:badG', ...
            'IN.G must have the same number of rows as S in fit mode.');
    end
    if VERBOSE
        fprintf('\nWavelet RemVarComp: fitting %s band-wise nuisance attenuation model.', upper(char(WR.baseReductionMethod)));
    end
    [bands, WR] = local_wavelet_band_spec(WR);
    WR.nBands = numel(bands);
    WR.bandAlphaScale = local_band_alpha_scale(WR, numel(bands));
    returnEmbedding = strcmpi(char(WR.outputDomain), 'embedding');

    if local_is_wavelet_direct(WR)
        [adjT, IN, dTcat] = local_wavelet_direct_fit(T, IN, S, WR, bands, returnEmbedding);
        return;
    end

    fullPartition = local_is_full_partition(WR, bands);
    doPartitionCheck = WR.assertPartition && fullPartition;
    if doPartitionCheck
        rawTsum = zeros(size(T), class(T));
        rawSsum = zeros(size(S), class(S));
    else
        rawTsum = [];
        rawSsum = [];
    end

    MODEL = struct();
    MODEL.version = 5;
    MODEL.description = 'Wavelet-domain RemVarComp using fixed a-trous bands and nk_PerfRedObj per band';
    MODEL.WAVELETREMVARCOMP = rmfield_if_present(WR, {'SPATIAL'});
    MODEL.SPATIAL = WR.SPATIAL;
    % MATLAB struct arrays cannot receive a scalar struct with fields into
    % a preallocated empty-field struct array. Initialise as truly empty and
    % append the first fitted band model as the field template.
    MODEL.band = struct([]);
    MODEL.diagnostics = struct();
    MODEL.diagnostics.fullPartition = fullPartition;
    MODEL.diagnostics.bandAlphaNormalization = WR.bandAlphaNormalization;
    MODEL.diagnostics.bandAlphaScale = WR.bandAlphaScale;
    MODEL.diagnostics.outputDomain = WR.outputDomain;
    if returnEmbedding
        adjT = [];
    else
        adjT = zeros(size(T), class(T));
    end
    dTparts = cell(1,numel(bands));
    for b = 1:numel(bands)
        if VERBOSE, fprintf('\n  Wavelet RemVarComp band %d/%d: %s(level=%g)', b, numel(bands), bands(b).name, bands(b).level); end
        Sb = local_wavelet_reconstruct_band(S, WR, bands(b));
        Tb = local_wavelet_reconstruct_band(T, WR, bands(b));
        if doPartitionCheck
            rawSsum = rawSsum + cast(Sb, class(rawSsum));
            rawTsum = rawTsum + cast(Tb, class(rawTsum));
        end
        B = local_fit_band_model(Sb, Tb, IN, WR, bands(b));
        if isempty(MODEL.band)
            MODEL.band = B.model;
        else
            MODEL.band(end+1) = B.model; %#ok<AGROW>
        end
        if ~returnEmbedding
            adjT = adjT + cast(B.adjustedBand, class(adjT));
        end
        dTparts{b} = B.componentScores;
    end
    if doPartitionCheck
        MODEL.diagnostics.partitionCheckSource = local_partition_check(S, rawSsum, WR, 'source');
        MODEL.diagnostics.partitionCheckTarget = local_partition_check(T, rawTsum, WR, 'target');
    end
    MODEL.diagnostics.aggregateAlpha = local_aggregate_alpha_diagnostics(MODEL.band);
    MODEL.diagnostics.bandAssociation = local_band_assoc_summary(MODEL.band);
    if VERBOSE
        local_print_wavelet_band_assoc_summary(MODEL.diagnostics.bandAssociation);
    end
    IN.WAVELETREMVARCOMP = WR;
    IN.WAVELETREMVARCOMP_MODEL = MODEL;
    dTcat = local_cat_scores(dTparts);
    if returnEmbedding
        adjT = dTcat;
    end
else
    MODEL = IN.WAVELETREMVARCOMP_MODEL;
    local_assert_wavelet_model(MODEL);
    if isfield(MODEL,'method') && strcmpi(char(MODEL.method),'waveletDirect')
        [adjT, dTcat] = local_wavelet_direct_apply(T, IN, MODEL);
        return;
    end
    if ~isfield(MODEL,'diagnostics') || isempty(MODEL.diagnostics)
        MODEL.diagnostics = struct();
    end
    if ~isfield(MODEL.diagnostics,'bandAssociation') || isempty(MODEL.diagnostics.bandAssociation)
        MODEL.diagnostics.bandAssociation = local_band_assoc_summary(MODEL.band);
        IN.WAVELETREMVARCOMP_MODEL = MODEL;
    end
    if isfield(MODEL,'WAVELETREMVARCOMP') && ~isempty(MODEL.WAVELETREMVARCOMP)
        WR = local_merge_struct(WR, MODEL.WAVELETREMVARCOMP);
    end
    if isfield(MODEL,'SPATIAL') && ~isempty(MODEL.SPATIAL)
        WR.SPATIAL = MODEL.SPATIAL;
    end
    if isfield(MODEL,'WAVELETREMVARCOMP') && isfield(MODEL.WAVELETREMVARCOMP,'outputDomain') && ~isempty(MODEL.WAVELETREMVARCOMP.outputDomain)
        WR.outputDomain = MODEL.WAVELETREMVARCOMP.outputDomain;
    end
    returnEmbedding = strcmpi(char(WR.outputDomain), 'embedding');
    if VERBOSE
        fprintf('\nWavelet RemVarComp: applying stored band-wise nuisance attenuation model.');
    end
    if returnEmbedding
        adjT = [];
    else
        adjT = zeros(size(T), class(T));
    end
    dTparts = cell(1,numel(MODEL.band));
    for b = 1:numel(MODEL.band)
        Bm = MODEL.band(b);
        bandSpec = struct('name',Bm.name,'mode',Bm.mode,'level',Bm.level);
        Tb = local_wavelet_reconstruct_band(T, WR, bandSpec);
        [adjBand, scores] = local_apply_band_model(Tb, IN, Bm, 'apply');
        if ~returnEmbedding
            adjT = adjT + cast(adjBand, class(adjT));
        end
        dTparts{b} = scores;
    end
    dTcat = local_cat_scores(dTparts);
    if returnEmbedding
        adjT = dTcat;
    end
end
end

% =========================================================================
function [WR, IN] = local_wavelet_defaults(IN)
% =========================================================================
WR = struct();
if isfield(IN,'WAVELETREMVARCOMP') && isstruct(IN.WAVELETREMVARCOMP)
    WR = IN.WAVELETREMVARCOMP;
end
WR.family = local_getfield(WR, 'family', 'b3spline');
WR.boundary = local_getfield(WR, 'boundary', 'mirror');
WR.levels = local_getfield(WR, 'levels', [1 2 3]);
WR.levels = unique(round(double(WR.levels(:)')));
WR.levels = WR.levels(WR.levels >= 1);
if isempty(WR.levels), WR.levels = [1 2 3]; end
WR.maxLevel = max(WR.levels);
WR.batchSize = max(1, round(double(local_getfield(WR,'batchSize',8))));
WR.bandSet = lower(char(local_getfield(WR, 'bandSet', 'approximation_and_details')));
WR.baseReductionMethod = lower(char(local_getfield(WR, 'baseReductionMethod', local_base_method_from_redmethod(IN))));
WR.alphaMode = lower(char(local_getfield(WR, 'alphaMode', 'soft_r2_shrinkage')));
WR.tau = double(local_getfield(WR, 'tau', 0.02));
WR.tau = max(eps, WR.tau);
WR.maxAlpha = double(local_getfield(WR, 'maxAlpha', 1));
WR.maxAlpha = min(1, max(0, WR.maxAlpha));
WR.assertPartition = logical(local_getfield(WR, 'assertPartition', true));
WR.partitionTolerance = double(local_getfield(WR, 'partitionTolerance', 1e-8));
if ~isfinite(WR.partitionTolerance) || WR.partitionTolerance <= 0, WR.partitionTolerance = 1e-8; end
WR.bandAlphaNormalization = lower(char(local_getfield(WR, 'bandAlphaNormalization', 'none')));
if isfield(WR,'outputDomain') && ~isempty(WR.outputDomain)
    WR.outputDomain = lower(char(WR.outputDomain));
elseif isfield(WR,'reconstructImage') && ~isempty(WR.reconstructImage)
    if logical(WR.reconstructImage), WR.outputDomain = 'image'; else, WR.outputDomain = 'embedding'; end
elseif isfield(IN,'recon') && isequal(IN.recon,2)
    WR.outputDomain = 'embedding';
else
    WR.outputDomain = 'image';
end
if ~any(strcmpi(WR.outputDomain, {'image','embedding'})), WR.outputDomain = 'image'; end
WR.reconstructImage = strcmpi(WR.outputDomain, 'image');
if ~isfield(WR,'SPATIAL') && isfield(IN,'SPATIAL') && isstruct(IN.SPATIAL)
    WR.SPATIAL = IN.SPATIAL;
end
if ~isfield(IN,'corrmeth') || isempty(IN.corrmeth), IN.corrmeth = 1; end
if ~isfield(IN,'dimmode') || isempty(IN.dimmode), IN.dimmode = 3; end
if ~isfield(IN,'dims') || isempty(IN.dims), IN.dims = 30; end
if WR.reconstructImage, IN.recon = 1; else, IN.recon = 2; end
end

% =========================================================================
function base = local_base_method_from_redmethod(IN)
% =========================================================================
base = 'pca';
if isfield(IN,'redmethod') && ~isempty(IN.redmethod) && double(IN.redmethod(1)) == 5
    base = 'direct';
elseif isfield(IN,'redmethod') && ~isempty(IN.redmethod) && double(IN.redmethod(1)) == 4
    base = 'fastica';
elseif isfield(IN,'DR') && isstruct(IN.DR) && isfield(IN.DR,'RedMode')
    rm = lower(char(IN.DR.RedMode));
    if ~isempty(strfind(rm,'ica')), base = 'fastica'; end %#ok<STREMP>
end
end

% =========================================================================
function [bands, WR] = local_wavelet_band_spec(WR)
% =========================================================================
J = WR.maxLevel;
bands = struct('name',{},'mode',{},'level',{});
useApprox = any(strcmpi(WR.bandSet, {'approximation_and_details','all','approximation_only','approximation'}));
useDetails = any(strcmpi(WR.bandSet, {'approximation_and_details','all','details_only','details'}));
if useApprox
    bands(end+1).name = sprintf('A%d', J); %#ok<AGROW>
    bands(end).mode = 'approximation';
    bands(end).level = J;
end
if useDetails
    for j = 1:J
        bands(end+1).name = sprintf('D%d', j); %#ok<AGROW>
        bands(end).mode = 'detail_bands';
        bands(end).level = j;
    end
end
if isempty(bands)
    WR.bandSet = 'approximation_and_details';
    [bands, WR] = local_wavelet_band_spec(WR);
end
end

% =========================================================================
function Yb = local_wavelet_reconstruct_band(Y, WR, band)
% =========================================================================
SP = WR.SPATIAL;
W = struct();
W.family = WR.family;
W.boundary = WR.boundary;
W.levels = WR.levels;
W.reconstructionMode = band.mode;
W.mode = band.mode;
W.detailLevels = band.level;
W.thresholdMode = 'none';
W.thresholdSigma = 0;
W.batchSize = WR.batchSize;
SP.WAVELET = W;
Yb = nk_WaveletSpatialReconstruct(Y, SP, band.level);
end

% =========================================================================
function B = local_fit_band_model(Sb, Tb, IN, WR, band)
% =========================================================================
Bin = local_band_reduction_input(IN, WR);
[dS, Bin] = nk_PerfRedObj(Sb(IN.indX,:), Bin);
local_assert_frozen_reduction(Bin, 'fit');
local_validate_delta_backprojection(Bin, size(Sb,2));
[C, P] = local_component_association(dS, IN.G(IN.indX,:), IN);
alpha = local_alpha_from_association(C, P, IN, WR);
alpha = alpha .* WR.bandAlphaScale;
M = local_pack_band_model(Bin, band, C, P, alpha, WR, IN);
[adjBand, dT] = local_apply_band_model(Tb, IN, M, 'fit');
B.adjustedBand = adjBand;
B.componentScores = dT;
B.model = M;
end

% =========================================================================
function M = local_pack_band_model(Bin, band, C, P, alpha, WR, IN)
% =========================================================================
M = struct();
M.version = 5;
M.name = band.name;
M.mode = band.mode;
M.level = band.level;
M.reduction = Bin;
M.association = C;
M.pvalue = P;
M.alpha = alpha(:)';
M.diagnostics = local_band_assoc_diagnostics(C, P, alpha, IN);
M.alphaMode = WR.alphaMode;
M.tau = WR.tau;
M.maxAlpha = WR.maxAlpha;
M.baseReductionMethod = WR.baseReductionMethod;
M.bandAlphaNormalization = WR.bandAlphaNormalization;
M.bandAlphaScale = WR.bandAlphaScale;
M.outputDomain = WR.outputDomain;
M.fitSourceRows = size(IN.G,1);
M.fitSelectedRows = sum(logical(IN.indX(:)));
M.fitIndX = logical(IN.indX(:));
end

% =========================================================================
function D = local_band_assoc_diagnostics(C, P, alpha, IN)
% =========================================================================
D = struct();
D.metricLabel = local_assoc_metric_label(IN);
D.maxAssociation = 0;
D.maxAssociationComponent = NaN;
D.maxAssociationCovariate = NaN;
D.maxAssociationPvalue = [];
D.maxAlpha = 0;
D.meanAlpha = 0;
D.sumAlpha = 0;
D.nAlphaNonzero = 0;
D.nComponents = 0;
D.nCovariates = 0;
if ~isempty(C)
    D.nComponents = size(C,1);
    D.nCovariates = size(C,2);
    [mx, ix] = max(C(:));
    if isempty(mx) || ~isfinite(mx), mx = 0; ix = 1; end
    [ci, gi] = ind2sub(size(C), ix);
    D.maxAssociation = mx;
    D.maxAssociationComponent = ci;
    D.maxAssociationCovariate = gi;
    if exist('P','var') && ~isempty(P) && numel(P) >= ix
        pv = P(ix);
        if isfinite(pv), D.maxAssociationPvalue = pv; end
    end
end
if exist('alpha','var') && ~isempty(alpha)
    a = alpha(:);
    a = a(isfinite(a));
    if ~isempty(a)
        D.maxAlpha = max(a);
        D.meanAlpha = mean(a);
        D.sumAlpha = sum(a);
        D.nAlphaNonzero = sum(a > 0);
    end
end
end

% =========================================================================
function label = local_assoc_metric_label(IN)
% =========================================================================
if ~isfield(IN,'corrmeth') || isempty(IN.corrmeth)
    cm = 1;
else
    cm = IN.corrmeth;
end
switch cm
    case 3
        label = 'sqrt(R2)';
    case 2
        label = '|rho|';
    otherwise
        label = '|r|';
end
end

% =========================================================================
function local_print_wavelet_band_assoc_summary(S)
% =========================================================================
if isempty(S), return; end
fprintf('\nWavelet RemVarComp band-wise association/attenuation summary:');
for i = 1:numel(S)
    pstr = '';
    if isfield(S(i),'maxAssociationPvalue') && ~isempty(S(i).maxAssociationPvalue)
        pstr = sprintf(', p=%0.4g', S(i).maxAssociationPvalue);
    end
    fprintf(['\n  %s(level=%g): max %s=%0.4g (component %d, covariate %d%s); ', ...
             'alpha max/mean/sum=%0.4g/%0.4g/%0.4g; alpha>0=%d/%d'], ...
        char(S(i).name), S(i).level, char(S(i).metricLabel), S(i).maxAssociation, ...
        S(i).maxAssociationComponent, S(i).maxAssociationCovariate, pstr, ...
        S(i).maxAlpha, S(i).meanAlpha, S(i).sumAlpha, S(i).nAlphaNonzero, S(i).nComponents);
end
end

% =========================================================================
function local_print_wavelet_band_association(M, IN)
% =========================================================================
if ~isfield(M,'diagnostics') || isempty(M.diagnostics)
    D = local_band_assoc_diagnostics(local_getfield(M,'association',[]), local_getfield(M,'pvalue',[]), local_getfield(M,'alpha',[]), IN);
else
    D = M.diagnostics;
end
if isempty(D.maxAssociationComponent) || any(isnan(D.maxAssociationComponent))
    fprintf(' -> no valid component-covariate association measured.');
    return
end
pstr = '';
if isfield(D,'maxAssociationPvalue') && ~isempty(D.maxAssociationPvalue)
    pstr = sprintf(', p=%0.4g', D.maxAssociationPvalue);
end
fprintf([' -> max %s=%0.4g (component %d, covariate %d%s); ', ...
         'alpha max/mean/sum=%0.4g/%0.4g/%0.4g; alpha>0=%d/%d.'], ...
    D.metricLabel, D.maxAssociation, D.maxAssociationComponent, D.maxAssociationCovariate, pstr, ...
    D.maxAlpha, D.meanAlpha, D.sumAlpha, D.nAlphaNonzero, D.nComponents);
end

% =========================================================================
function Bin = local_band_reduction_input(IN, WR)
% =========================================================================
Bin = IN;
Bin = rmfield_if_present(Bin, {'WAVELETREMVARCOMP','WAVELETREMVARCOMP_MODEL','SPATIAL','mpp','indNonRem','C','Pvalue','subthresh','ind0'});
Bin.indX = [];
Bin.G = [];
Bin.recon = 1;
switch lower(char(WR.baseReductionMethod))
    case {'fastica'}
        Bin.redmethod = 2;
        Bin.DR = struct();
        Bin.DR.RedMode = 'fastICA';
        Bin.DR.PercMode = 1;
        Bin.DR.DRsoft = 1;
        Bin.DR.dims = local_scalar_dim(IN.dims);
        if isfield(IN,'whiten_opt'), Bin.DR.whiten_opt = IN.whiten_opt; Bin.whiten_opt = IN.whiten_opt; end
        if isfield(IN,'algorithm_opt'), Bin.DR.algorithm_opt = IN.algorithm_opt; Bin.algorithm_opt = IN.algorithm_opt; end
        if isfield(IN,'fun_opt'), Bin.DR.fun_opt = IN.fun_opt; Bin.fun_opt = IN.fun_opt; end
        if isfield(IN,'tolerance'), Bin.tolerance = IN.tolerance; end
        if isfield(IN,'max_iters'), Bin.max_iters = IN.max_iters; end
    otherwise
        Bin.redmethod = 1;
        Bin.DR = struct();
        Bin.DR.RedMode = 'PCA';
        Bin.DR.PercMode = IN.dimmode;
        Bin.DR.DRsoft = 1;
        Bin.DR.dims = local_scalar_dim(IN.dims);
end
end

% =========================================================================
function dim = local_scalar_dim(x)
% =========================================================================
if isempty(x), dim = 30; else, dim = double(x(1)); end
end

% =========================================================================
function [adjBand, dT] = local_apply_band_model(Tb, IN, M, applyMode) %#ok<INUSD>
% =========================================================================
% Apply the frozen training-fold attenuation model. This intentionally mirrors
% the legacy RemVarComp logic: held-out data are projected into the learned
% component space, and the same component positions are attenuated. No target
% scanner/site covariates are required or used at application time.
if nargin < 4 || isempty(applyMode), applyMode = 'apply'; end
local_assert_wavelet_band_model(M);
Bin = M.reduction;
local_assert_frozen_reduction(Bin, applyMode);
dT = nk_PerfRedObj(Tb, Bin);
alpha = M.alpha(:)';
if isempty(dT) || isempty(alpha)
    adjBand = Tb;
    return
end
nComp = min(size(dT,2), numel(alpha));
alpha = alpha(1:nComp);
deltaScores = bsxfun(@times, dT(:,1:nComp), alpha);
% Return the adjusted embedding as dT. This mirrors legacy recon=2: the
% downstream pipeline continues in the mapped component space rather than in
% image space.
dT(:,1:nComp) = dT(:,1:nComp) - deltaScores;
deltaBand = local_backproject_delta(deltaScores, M.reduction, size(Tb,2));
adjBand = Tb - cast(deltaBand, class(Tb));
end

% =========================================================================
function deltaBand = local_backproject_delta(deltaScores, Bin, nFeat)
% =========================================================================
deltaBand = zeros(size(deltaScores,1), nFeat);
if ~isfield(Bin,'indNonRem') || isempty(Bin.indNonRem)
    Bin.indNonRem = true(1,nFeat);
end
ind = logical(Bin.indNonRem(:)');
switch lower(char(Bin.DR.RedMode))
    case 'fastica'
        if exist('cv_PerfICA','file') == 2
            try
                rec = cv_PerfICA(deltaScores, Bin.mpp, 'inverse_transform');
                rec0 = cv_PerfICA(zeros(size(deltaScores)), Bin.mpp, 'inverse_transform');
                rec = rec - rec0;
            catch
                rec = [];
            end
        else
            rec = [];
        end
        if isempty(rec)
            error('nk_PerfAdjForCovarsUsingPCAObj:fastICADeltaBackprojection', ...
                'Could not back-project fastICA delta scores. cv_PerfICA inverse_transform is required.');
        end
        deltaBand(:,ind) = rec;
    otherwise
        if ~isfield(Bin,'mpp') || ~isfield(Bin.mpp,'vec')
            error('nk_PerfAdjForCovarsUsingPCAObj:noPCALoadings', 'Stored PCA loadings are missing for wavelet remvarcomp.');
        end
        P = Bin.mpp.vec;
        nComp = min(size(deltaScores,2), size(P,2));
        deltaBand(:,ind) = deltaScores(:,1:nComp) * P(:,1:nComp)';
end
end

% =========================================================================
function [C, P] = local_component_association(dS, G, IN)
% =========================================================================
if isvector(G), G = G(:); end
if ~isfield(IN,'corrmeth') || isempty(IN.corrmeth), IN.corrmeth = 1; end
switch IN.corrmeth
    case 2, corrmeth = 'spearman';
    case 3, corrmeth = 'anova';
    otherwise, corrmeth = 'pearson';
end
C = zeros(size(dS,2), size(G,2));
P = ones(size(dS,2), size(G,2));
switch corrmeth
    case {'pearson','spearman'}
        for i = 1:size(G,2)
            if exist('nk_CorrMat','file') == 2
                [Cv,~,~,Pv] = nk_CorrMat(dS, G(:,i), corrmeth);
            else
                [Cv,Pv] = corr(dS, G(:,i), 'type', corrmeth, 'rows', 'pairwise');
            end
            C(:,i) = abs(Cv(:));
            P(:,i) = Pv(:);
        end
    otherwise
        if exist('nk_PerfANOVAObj','file') == 2
            RES.X = [ones(size(G,1),1) G];
            RES = nk_PerfANOVAObj(dS, RES);
            C = sqrt(RES.R2);
            P = RES.p;
            if isvector(C), C = C(:); end
            if isvector(P), P = P(:); end
        else
            for i = 1:size(G,2)
                [Cv,Pv] = corr(dS, G(:,i), 'type', 'Pearson', 'rows', 'pairwise');
                C(:,i) = abs(Cv(:)); P(:,i) = Pv(:);
            end
        end
end
C(~isfinite(C)) = 0;
P(~isfinite(P)) = 1;
end

% =========================================================================
function alpha = local_alpha_from_association(C, P, IN, WR) %#ok<INUSD>
% =========================================================================
% Convert training-fold component/covariate association strengths into soft
% attenuation weights. There is deliberately no corr/p-value threshold and no
% hard component-deletion operator in the wavelet backend.
if isempty(C), alpha = []; return; end
assoc = max(C, [], 2);
mode = lower(char(WR.alphaMode));
switch mode
    case {'soft_corr','corr'}
        alpha = assoc;
    case {'soft_r2_shrinkage','r2','soft_r2'}
        r2 = assoc .^ 2;
        alpha = r2 ./ (r2 + WR.tau);
    otherwise
        error('nk_PerfAdjForCovarsUsingPCAObj:unsupportedWaveletAlphaMode', ...
            'Wavelet RemVarComp only supports soft_r2_shrinkage and soft_corr alpha modes. Hard thresholding is intentionally disabled.');
end
alpha(~isfinite(alpha)) = 0;
alpha = min(WR.maxAlpha, max(0, alpha));
end


% =========================================================================
function tf = local_is_wavelet_direct(WR)
% =========================================================================
tf = isfield(WR,'baseReductionMethod') && any(strcmpi(char(WR.baseReductionMethod), {'direct','coeff','coefficient','waveletdirect'}));
end

% =========================================================================
function [adjT, IN, dTcat] = local_wavelet_direct_fit(T, IN, S, WR, bands, returnEmbedding)
% =========================================================================
% Direct wavelet-coefficient nuisance attenuation. No PCA/ICA basis is learned
% before estimating associations. G is used only in the training partition to
% derive band/voxel alpha maps, optionally after partialling protected
% covariates. Application to held-out data only reuses the stored alpha maps.
global VERBOSE
if nargin < 6, returnEmbedding = strcmpi(char(WR.outputDomain),'embedding'); end
fullPartition = local_is_full_partition(WR, bands);
doPartitionCheck = WR.assertPartition && fullPartition;
if doPartitionCheck
    rawTsum = zeros(size(T), class(T));
    rawSsum = zeros(size(S), class(S));
end
MODEL = struct();
MODEL.version = 6;
MODEL.method = 'waveletDirect';
MODEL.description = 'Direct wavelet-coefficient RemVarComp with soft nuisance-association alpha maps';
MODEL.WAVELETREMVARCOMP = rmfield_if_present(WR, {'SPATIAL'});
MODEL.SPATIAL = WR.SPATIAL;
MODEL.band = struct([]);
MODEL.diagnostics = struct('fullPartition',fullPartition,'bandAlphaNormalization',WR.bandAlphaNormalization, ...
    'bandAlphaScale',WR.bandAlphaScale,'outputDomain',WR.outputDomain,'protectedCovariates',local_protected_summary(WR));
adjTimg = zeros(size(T), class(T));
adjSimg = zeros(size(S), class(S));
for b = 1:numel(bands)
    if VERBOSE, fprintf('\n  Wavelet Direct RemVarComp band %d/%d: %s(level=%g)', b, numel(bands), bands(b).name, bands(b).level); end
    Sb = local_wavelet_reconstruct_band(S, WR, bands(b));
    Tb = local_wavelet_reconstruct_band(T, WR, bands(b));
    if doPartitionCheck
        rawSsum = rawSsum + cast(Sb, class(rawSsum));
        rawTsum = rawTsum + cast(Tb, class(rawTsum));
    end
    M = local_fit_direct_band_model(Sb, IN, WR, bands(b));
    if isempty(MODEL.band), MODEL.band = M; else, MODEL.band(end+1) = M; end %#ok<AGROW>
    adjSimg = adjSimg + cast(local_apply_direct_band_alpha(Sb, M), class(adjSimg));
    adjTimg = adjTimg + cast(local_apply_direct_band_alpha(Tb, M), class(adjTimg));
end
if doPartitionCheck
    MODEL.diagnostics.partitionCheckSource = local_partition_check(S, rawSsum, WR, 'source');
    MODEL.diagnostics.partitionCheckTarget = local_partition_check(T, rawTsum, WR, 'target');
end
MODEL.diagnostics.aggregateAlpha = local_aggregate_direct_alpha_diagnostics(MODEL.band);
MODEL.diagnostics.bandAssociation = local_direct_band_assoc_summary(MODEL.band);
if VERBOSE
    local_print_direct_band_assoc_summary(MODEL.diagnostics.bandAssociation);
end
if returnEmbedding
    [dTcat, IN, MODEL] = local_fit_apply_direct_final_embedding(adjSimg, adjTimg, IN, WR, MODEL);
    adjT = dTcat;
else
    dTcat = [];
    adjT = adjTimg;
end
IN.WAVELETREMVARCOMP = WR;
IN.WAVELETREMVARCOMP_MODEL = MODEL;
end

% =========================================================================
function [adjT, dTcat] = local_wavelet_direct_apply(T, IN, MODEL)
% =========================================================================
global VERBOSE
WR = local_merge_struct(local_wavelet_defaults_no_in(IN), MODEL.WAVELETREMVARCOMP);
WR.SPATIAL = MODEL.SPATIAL;
if VERBOSE, fprintf('\nWavelet Direct RemVarComp: applying stored coefficient-wise nuisance attenuation model.'); end
adjImg = zeros(size(T), class(T));
for b = 1:numel(MODEL.band)
    M = MODEL.band(b);
    bandSpec = struct('name',M.name,'mode',M.mode,'level',M.level);
    Tb = local_wavelet_reconstruct_band(T, WR, bandSpec);
    adjImg = adjImg + cast(local_apply_direct_band_alpha(Tb, M), class(adjImg));
end
if isfield(MODEL,'finalEmbedding') && ~isempty(MODEL.finalEmbedding) && strcmpi(local_getfield(MODEL.WAVELETREMVARCOMP,'outputDomain','image'),'embedding')
    dTcat = nk_PerfRedObj(adjImg, MODEL.finalEmbedding);
    adjT = dTcat;
else
    dTcat = [];
    adjT = adjImg;
end
end

% =========================================================================
function WR = local_wavelet_defaults_no_in(IN)
% =========================================================================
WR = struct();
if isstruct(IN) && isfield(IN,'WAVELETREMVARCOMP') && isstruct(IN.WAVELETREMVARCOMP)
    WR = IN.WAVELETREMVARCOMP;
end
WR.family = local_getfield(WR,'family','b3spline');
WR.boundary = local_getfield(WR,'boundary','mirror');
WR.levels = local_getfield(WR,'levels',[1 2 3]);
WR.maxLevel = max(WR.levels);
WR.batchSize = local_getfield(WR,'batchSize',8);
WR.bandSet = local_getfield(WR,'bandSet','approximation_and_details');
end

% =========================================================================
function M = local_fit_direct_band_model(Sb, IN, WR, band)
% =========================================================================
if ~isfield(IN,'indX') || isempty(IN.indX), indX = true(size(Sb,1),1); else, indX = logical(IN.indX(:)); end
G = IN.G; if isvector(G), G = G(:); end
P = local_get_protected_covariates(WR, size(Sb,1));
[C, Pv] = local_direct_coefficient_association(Sb(indX,:), G(indX,:), P(indX,:), IN);
alpha = local_alpha_from_association(C(:), Pv(:), IN, WR);
alpha = reshape(alpha, 1, []);
alpha = alpha .* WR.bandAlphaScale;
alpha(~isfinite(alpha)) = 0;
alpha = min(WR.maxAlpha, max(0, alpha));
M = struct();
M.version = 1;
M.name = band.name;
M.mode = band.mode;
M.level = band.level;
M.alphaMap = alpha;
M.associationMap = C(:)';
M.pvalueMap = Pv(:)';
M.diagnostics = local_direct_band_diagnostics(C(:)', Pv(:)', alpha, IN, WR);
end

% =========================================================================
function Xadj = local_apply_direct_band_alpha(X, M)
% =========================================================================
alpha = local_getfield(M,'alphaMap',[]);
if isempty(alpha)
    Xadj = X;
    return
end
alpha = alpha(:)';
if numel(alpha) ~= size(X,2)
    error('nk_PerfAdjForCovarsUsingPCAObj:directAlphaSizeMismatch', ...
        'Stored direct wavelet alpha map has %d features, but target band has %d features.', numel(alpha), size(X,2));
end
Xadj = bsxfun(@times, X, cast(1-alpha, class(X)));
end

% =========================================================================
function [C, Pval] = local_direct_coefficient_association(X, G, Prot, IN)
% =========================================================================
% Returns one maximum association value per coefficient. If method=ANOVA, a
% partial-R2/sqrt(partial-R2) model is used, with protected covariates in the
% reduced model and nuisance covariate(s) added in the full model.
if isempty(G), C = zeros(1,size(X,2)); Pval = ones(1,size(X,2)); return; end
if isempty(Prot), Prot = zeros(size(X,1),0); end
if isvector(G), G = G(:); end
if ~isfield(IN,'corrmeth') || isempty(IN.corrmeth), IN.corrmeth = 1; end
switch IN.corrmeth
    case 2
        Xr = local_tiedrank_matrix(X);
        Gr = local_tiedrank_matrix(G);
        Pr = local_tiedrank_matrix(Prot);
        [Cmat, Pmat] = local_corr_after_protection(Xr, Gr, Pr, 'Pearson');
    case 3
        [Cmat, Pmat] = local_partial_r2_assoc(X, G, Prot);
    otherwise
        [Cmat, Pmat] = local_corr_after_protection(X, G, Prot, 'Pearson');
end
Cmat(~isfinite(Cmat)) = 0;
Pmat(~isfinite(Pmat)) = 1;
[C, ix] = max(abs(Cmat), [], 2);
Pval = ones(size(C));
for i=1:numel(ix)
    if ~isempty(ix), Pval(i) = Pmat(i, ix(i)); end
end
C = C(:)'; Pval = Pval(:)';
end

% =========================================================================
function [Cmat, Pmat] = local_corr_after_protection(X, G, Prot, corrType)
% =========================================================================
Xr = local_residualize_columns(X, Prot);
Gr = local_residualize_columns(G, Prot);
Cmat = zeros(size(X,2), size(G,2));
Pmat = ones(size(X,2), size(G,2));
for g=1:size(G,2)
    try
        [c,p] = corr(Xr, Gr(:,g), 'type', corrType, 'rows', 'pairwise');
    catch
        c = local_fast_corr(Xr, Gr(:,g)); p = ones(size(c));
    end
    Cmat(:,g) = abs(c(:));
    Pmat(:,g) = p(:);
end
end

% =========================================================================
function [Cmat, Pmat] = local_partial_r2_assoc(X, G, Prot)
% =========================================================================
Z0 = local_design_with_intercept(Prot);
Xr0 = X - Z0 * (pinv(Z0) * X);
SSE0 = sum(Xr0.^2, 1);
SSE0(SSE0 <= eps) = eps;
Cmat = zeros(size(X,2), size(G,2));
Pmat = ones(size(X,2), size(G,2));
for g=1:size(G,2)
    Zg = local_encode_covariate(G(:,g));
    Z1 = [Z0 Zg];
    Z1 = local_drop_dependent_columns(Z1);
    Xr1 = X - Z1 * (pinv(Z1) * X);
    SSE1 = sum(Xr1.^2, 1);
    pr2 = max(0, min(1, (SSE0 - SSE1) ./ SSE0));
    Cmat(:,g) = sqrt(pr2(:));
    df1 = max(1, size(Z1,2)-size(Z0,2));
    df2 = max(1, size(X,1)-rank(Z1));
    F = ((SSE0 - SSE1)./df1) ./ max(eps, SSE1./df2);
    try
        Pmat(:,g) = 1 - fcdf(F(:), df1, df2);
    catch
        Pmat(:,g) = ones(size(X,2),1);
    end
end
end

% =========================================================================
function Xr = local_residualize_columns(X, Prot)
% =========================================================================
Z = local_design_with_intercept(Prot);
Xr = X - Z * (pinv(Z) * X);
end

% =========================================================================
function Z = local_design_with_intercept(P)
% =========================================================================
n = size(P,1);
if isempty(P)
    Z = ones(n,1);
    return;
end
P = double(P);
P(~isfinite(P)) = 0;
parts = cell(1, size(P,2));
for j = 1:size(P,2)
    x = P(:,j);
    if numel(unique(x)) <= min(20, max(2, floor(n/4)))
        parts{j} = local_encode_covariate(x);
    else
        parts{j} = x;
    end
end
Z = ones(n,1);
for j = 1:numel(parts)
    if ~isempty(parts{j}), Z = [Z parts{j}]; end %#ok<AGROW>
end
Z = local_drop_dependent_columns(Z);
end

% =========================================================================
function Z = local_encode_covariate(g)
% =========================================================================
g = double(g(:));
ok = isfinite(g);
u = unique(g(ok));
if numel(u) <= min(20, max(2, floor(numel(g)/4)))
    Z = zeros(numel(g), max(0,numel(u)-1));
    for k=2:numel(u)
        Z(:,k-1) = double(g == u(k));
    end
else
    Z = g;
end
Z(~isfinite(Z)) = 0;
end

% =========================================================================
function Z = local_drop_dependent_columns(Z)
% =========================================================================
if isempty(Z), return; end
keep = true(1,size(Z,2));
for j=1:size(Z,2)
    if std(Z(:,j)) < eps && j > 1, keep(j)=false; end
end
Z = Z(:,keep);
[~, R, E] = qr(Z,0); %#ok<ASGLU>
if isempty(R), return; end
tol = max(size(Z)) * eps(norm(R,'fro'));
r = sum(abs(diag(R)) > tol);
if r < size(Z,2)
    keep = sort(E(1:r));
    Z = Z(:,keep);
end
end

% =========================================================================
function R = local_tiedrank_matrix(X)
% =========================================================================
R = zeros(size(X));
if isempty(X), return; end
for j=1:size(X,2)
    x = X(:,j);
    try
        R(:,j) = tiedrank(x);
    catch
        [~,ord] = sort(x);
        r = zeros(size(x)); r(ord) = 1:numel(x);
        R(:,j) = r;
    end
end
end

% =========================================================================
function c = local_fast_corr(X, y)
% =========================================================================
y = y(:); y = y - mean(y,'omitnan');
X = bsxfun(@minus, X, mean(X,1,'omitnan'));
num = X' * y;
den = sqrt(sum(X.^2,1)' .* sum(y.^2));
c = num ./ max(eps, den);
end

% =========================================================================
function P = local_get_protected_covariates(WR, nRows)
% =========================================================================
P = zeros(nRows,0);
try
    if isfield(WR,'PROTECTED') && isstruct(WR.PROTECTED) && isfield(WR.PROTECTED,'matrix') && ~isempty(WR.PROTECTED.matrix)
        P = double(WR.PROTECTED.matrix);
        if size(P,1) ~= nRows
            error('bad protected rows');
        end
    end
catch
    error('nk_PerfAdjForCovarsUsingPCAObj:badProtectedCovariates', ...
        'Protected covariate matrix in WAVELETREMVARCOMP.PROTECTED.matrix must have one row per training subject.');
end
end

% =========================================================================
function S = local_protected_summary(WR)
% =========================================================================
S = struct('nColumns',0,'useLabel',false);
if isfield(WR,'PROTECTED') && isstruct(WR.PROTECTED)
    S.useLabel = local_getfield(WR.PROTECTED,'useLabel',false);
    if isfield(WR.PROTECTED,'matrix') && ~isempty(WR.PROTECTED.matrix)
        S.nColumns = size(WR.PROTECTED.matrix,2);
    end
end
end

% =========================================================================
function [dT, IN, MODEL] = local_fit_apply_direct_final_embedding(adjS, adjT, IN, WR, MODEL)
% =========================================================================
E = IN;
E = rmfield_if_present(E, {'WAVELETREMVARCOMP','WAVELETREMVARCOMP_MODEL','SPATIAL','mpp','indNonRem','C','Pvalue','subthresh','ind0'});
E.indX = [];
E.G = [];
E.recon = 2;
if strcmpi(local_getfield(WR,'finalEmbeddingMethod','PCA'),'fastICA')
    E.redmethod = 2;
    E.DR = struct('RedMode','fastICA','PercMode',1,'DRsoft',1,'dims',local_scalar_dim(IN.dims));
    if isfield(IN,'whiten_opt'), E.DR.whiten_opt = IN.whiten_opt; E.whiten_opt = IN.whiten_opt; end
    if isfield(IN,'algorithm_opt'), E.DR.algorithm_opt = IN.algorithm_opt; E.algorithm_opt = IN.algorithm_opt; end
    if isfield(IN,'fun_opt'), E.DR.fun_opt = IN.fun_opt; E.fun_opt = IN.fun_opt; end
    if isfield(IN,'tolerance'), E.tolerance = IN.tolerance; end
    if isfield(IN,'max_iters'), E.max_iters = IN.max_iters; end
else
    E.redmethod = 1;
    E.DR = struct('RedMode','PCA','PercMode',IN.dimmode,'DRsoft',1,'dims',local_scalar_dim(IN.dims));
end
if isfield(IN,'indX') && ~isempty(IN.indX), indX = logical(IN.indX(:)); else, indX = true(size(adjS,1),1); end
[~, E] = nk_PerfRedObj(adjS(indX,:), E);
dT = nk_PerfRedObj(adjT, E);
MODEL.finalEmbedding = E;
MODEL.diagnostics.finalEmbeddingMethod = local_getfield(WR,'finalEmbeddingMethod','PCA');
end

% =========================================================================
function D = local_direct_band_diagnostics(C, P, alpha, IN, WR) %#ok<INUSD>
% =========================================================================
D = struct();
D.metricLabel = local_assoc_metric_label(IN);
D.nCoefficients = numel(alpha);
D.maxAssociation = 0;
D.maxAssociationCoefficient = NaN;
D.maxAssociationPvalue = [];
if ~isempty(C)
    [mx,ix] = max(C(:));
    if isempty(mx) || ~isfinite(mx), mx = 0; ix = 1; end
    D.maxAssociation = mx;
    D.maxAssociationCoefficient = ix;
    if exist('P','var') && ~isempty(P) && numel(P) >= ix && isfinite(P(ix)), D.maxAssociationPvalue = P(ix); end
end
if isempty(alpha), alpha = 0; end
D.maxAlpha = max(alpha(:));
D.meanAlpha = mean(alpha(:));
D.sumAlpha = sum(alpha(:));
D.nAlphaNonzero = sum(alpha(:) > 0);
end

% =========================================================================
function S = local_direct_band_assoc_summary(band)
% =========================================================================
S = struct('name',{},'level',{},'metricLabel',{},'maxAssociation',{}, ...
           'maxAssociationCoefficient',{},'maxAssociationPvalue',{},'maxAlpha',{},'meanAlpha',{}, ...
           'sumAlpha',{},'nAlphaNonzero',{},'nCoefficients',{});
for i=1:numel(band)
    D = local_getfield(band(i),'diagnostics',struct());
    S(i).name = local_getfield(band(i),'name',''); %#ok<AGROW>
    S(i).level = local_getfield(band(i),'level',NaN);
    S(i).metricLabel = local_getfield(D,'metricLabel','');
    S(i).maxAssociation = local_getfield(D,'maxAssociation',0);
    S(i).maxAssociationCoefficient = local_getfield(D,'maxAssociationCoefficient',NaN);
    S(i).maxAssociationPvalue = local_getfield(D,'maxAssociationPvalue',[]);
    S(i).maxAlpha = local_getfield(D,'maxAlpha',0);
    S(i).meanAlpha = local_getfield(D,'meanAlpha',0);
    S(i).sumAlpha = local_getfield(D,'sumAlpha',0);
    S(i).nAlphaNonzero = local_getfield(D,'nAlphaNonzero',0);
    S(i).nCoefficients = local_getfield(D,'nCoefficients',0);
end
end

% =========================================================================
function local_print_direct_band_assoc_summary(S)
% =========================================================================
if isempty(S), return; end
fprintf('\nWavelet Direct RemVarComp band-wise coefficient association/attenuation summary:');
for i=1:numel(S)
    pstr = '';
    if isfield(S(i),'maxAssociationPvalue') && ~isempty(S(i).maxAssociationPvalue), pstr = sprintf(', p=%0.4g', S(i).maxAssociationPvalue); end
    fprintf(['\n  %s(level=%g): max %s=%0.4g (coefficient %d%s); ', ...
             'alpha max/mean/sum=%0.4g/%0.4g/%0.4g; alpha>0=%d/%d'], ...
        char(S(i).name), S(i).level, char(S(i).metricLabel), S(i).maxAssociation, ...
        S(i).maxAssociationCoefficient, pstr, S(i).maxAlpha, S(i).meanAlpha, S(i).sumAlpha, ...
        S(i).nAlphaNonzero, S(i).nCoefficients);
end
end

% =========================================================================
function S = local_aggregate_direct_alpha_diagnostics(band)
% =========================================================================
S = struct('maxAlpha',0,'meanAlpha',0,'sumAlpha',0,'nNonzero',0,'nBands',numel(band));
a = [];
for i=1:numel(band)
    if isfield(band(i),'alphaMap') && ~isempty(band(i).alphaMap), a = [a band(i).alphaMap(:)']; end %#ok<AGROW>
end
if isempty(a), return; end
S.maxAlpha = max(a);
S.meanAlpha = mean(a);
S.sumAlpha = sum(a);
S.nNonzero = sum(a > 0);
end

% =========================================================================
function out = local_cat_scores(parts)
% =========================================================================
parts = parts(~cellfun(@isempty, parts));
if isempty(parts), out = []; else, out = cat(2, parts{:}); end
end


% =========================================================================
function tf = local_is_full_partition(WR, bands)
% =========================================================================
tf = false;
if ~isfield(WR,'bandSet') || ~any(strcmpi(WR.bandSet, {'approximation_and_details','all'})), return; end
J = WR.maxLevel;
hasA = false(1,1); hasD = false(1,J);
for i = 1:numel(bands)
    if strcmpi(bands(i).mode,'approximation') && bands(i).level == J, hasA = true; end
    if strcmpi(bands(i).mode,'detail_bands') && bands(i).level >= 1 && bands(i).level <= J
        hasD(bands(i).level) = true;
    end
end
tf = hasA && all(hasD);
end

% =========================================================================
function chk = local_partition_check(Y, Ysum, WR, label)
% =========================================================================
D = double(Ysum) - double(Y);
den = norm(double(Y(:)));
if den == 0, den = 1; end
chk = struct();
chk.label = label;
chk.nrmsd = norm(D(:)) / den;
chk.maxAbs = max(abs(D(:)));
chk.tolerance = WR.partitionTolerance;
chk.ok = chk.nrmsd <= WR.partitionTolerance;
if ~chk.ok
    error('nk_PerfAdjForCovarsUsingPCAObj:waveletPartitionCheckFailed', ...
        'Wavelet RemVarComp no-op reconstruction check failed for %s matrix: NRMSD=%g exceeds tolerance=%g.', ...
        label, chk.nrmsd, WR.partitionTolerance);
end
end

% =========================================================================
function scale = local_band_alpha_scale(WR, nBands)
% =========================================================================
mode = lower(char(local_getfield(WR,'bandAlphaNormalization','none')));
switch mode
    case {'divide_by_nbands','n','nbands'}
        scale = 1 ./ max(1, nBands);
    case {'divide_by_sqrt_nbands','sqrt','sqrt_nbands'}
        scale = 1 ./ sqrt(max(1, nBands));
    otherwise
        scale = 1;
end
end

% =========================================================================
function S = local_band_assoc_summary(band)
% =========================================================================
S = struct('name',{},'level',{},'metricLabel',{},'maxAssociation',{}, ...
           'maxAssociationComponent',{},'maxAssociationCovariate',{}, ...
           'maxAssociationPvalue',{},'maxAlpha',{},'meanAlpha',{}, ...
           'sumAlpha',{},'nAlphaNonzero',{},'nComponents',{});
for i = 1:numel(band)
    D = struct();
    if isfield(band(i),'diagnostics') && ~isempty(band(i).diagnostics)
        D = band(i).diagnostics;
    end
    S(i).name = local_getfield(band(i),'name',''); %#ok<AGROW>
    S(i).level = local_getfield(band(i),'level',NaN);
    S(i).metricLabel = local_getfield(D,'metricLabel','');
    S(i).maxAssociation = local_getfield(D,'maxAssociation',0);
    S(i).maxAssociationComponent = local_getfield(D,'maxAssociationComponent',NaN);
    S(i).maxAssociationCovariate = local_getfield(D,'maxAssociationCovariate',NaN);
    S(i).maxAssociationPvalue = local_getfield(D,'maxAssociationPvalue',[]);
    S(i).maxAlpha = local_getfield(D,'maxAlpha',0);
    S(i).meanAlpha = local_getfield(D,'meanAlpha',0);
    S(i).sumAlpha = local_getfield(D,'sumAlpha',0);
    S(i).nAlphaNonzero = local_getfield(D,'nAlphaNonzero',0);
    S(i).nComponents = local_getfield(D,'nComponents',0);
end
end

% =========================================================================
function S = local_aggregate_alpha_diagnostics(band)
% =========================================================================
S = struct('maxAlpha',0,'meanAlpha',0,'sumAlpha',0,'nNonzero',0,'nBands',numel(band));
a = [];
for i = 1:numel(band)
    if isfield(band(i),'alpha') && ~isempty(band(i).alpha)
        a = [a band(i).alpha(:)']; %#ok<AGROW>
    end
end
if isempty(a), return; end
S.maxAlpha = max(a);
S.meanAlpha = mean(a);
S.sumAlpha = sum(a);
S.nNonzero = sum(a > 0);
end

% =========================================================================
function local_assert_wavelet_model(MODEL)
% =========================================================================
if ~isstruct(MODEL) || ~isfield(MODEL,'version') || MODEL.version < 3
    error('nk_PerfAdjForCovarsUsingPCAObj:oldWaveletModel', ...
        ['Stored wavelet RemVarComp model is missing the v3 metadata. ', ...
         'Refit the preprocessing object with the current code because nuisance_prediction and hard thresholding were removed.']);
end
if ~isfield(MODEL,'band') || isempty(MODEL.band)
    error('nk_PerfAdjForCovarsUsingPCAObj:badWaveletModel', 'Stored wavelet RemVarComp model has no band models.');
end
end

% =========================================================================
function local_assert_wavelet_band_model(M)
% =========================================================================
if ~isstruct(M) || ~isfield(M,'version') || M.version < 3
    error('nk_PerfAdjForCovarsUsingPCAObj:oldWaveletBandModel', ...
        'Wavelet RemVarComp band model lacks v3 metadata; refit the preprocessing object.');
end
end

% =========================================================================
function local_assert_frozen_reduction(Bin, mode)
% =========================================================================
if ~isstruct(Bin) || ~isfield(Bin,'mpp') || isempty(Bin.mpp)
    error('nk_PerfAdjForCovarsUsingPCAObj:unfrozenReduction', ...
        'Wavelet RemVarComp %s requires a fitted nk_PerfRedObj mapping in Bin.mpp.', char(mode));
end
if ~isfield(Bin,'DR') || ~isfield(Bin.DR,'RedMode') || isempty(Bin.DR.RedMode)
    error('nk_PerfAdjForCovarsUsingPCAObj:badReduction', 'Wavelet RemVarComp stored reduction lacks DR.RedMode.');
end
end

% =========================================================================
function local_validate_delta_backprojection(Bin, nFeat)
% =========================================================================
% A zero component-score delta must back-project to a zero image-space delta.
% This detects ICA inverse-transform implementations that add back the model
% mean during inverse projection.
if ~isfield(Bin,'mpp') || isempty(Bin.mpp), return; end
nComp = local_scalar_dim(Bin.DR.dims);
if isfield(Bin,'mpp') && isfield(Bin.mpp,'vec') && ~isempty(Bin.mpp.vec)
    nComp = size(Bin.mpp.vec,2);
end
nComp = max(1, nComp);
delta0 = local_backproject_delta(zeros(2,nComp), Bin, nFeat);
den = max(1, nFeat);
err = norm(double(delta0(:))) / den;
if err > 1e-10
    error('nk_PerfAdjForCovarsUsingPCAObj:deltaBackprojectionNotCentered', ...
        'Delta backprojection is not centred around zero (norm=%g). Check the PCA/ICA inverse transform.', err);
end
end

% =========================================================================
function v = local_getfield(S, f, defaultv)
% =========================================================================
if isstruct(S) && isfield(S,f) && ~isempty(S.(f)), v = S.(f); else, v = defaultv; end
end

% =========================================================================
function S = rmfield_if_present(S, fields)
% =========================================================================
for i = 1:numel(fields)
    if isfield(S,fields{i}), S = rmfield(S, fields{i}); end
end
end

% =========================================================================
function S = local_merge_struct(S, T)
% =========================================================================
if ~isstruct(T), return; end
fn = fieldnames(T);
for i = 1:numel(fn), S.(fn{i}) = T.(fn{i}); end
end
