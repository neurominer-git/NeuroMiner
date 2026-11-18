classdef NMRemVarCompWaveletSubconfigLibrary
% NMRemVarCompWaveletSubconfigLibrary
% -------------------------------------------------------------------------
% Nested UI schemas and legacy export helpers for the experimental
% wavelet-domain RemVarComp backend.
%
% The UI deliberately exposes only parameters that the user should control:
% fixed signed a-trous wavelet bands, protected covariates, and the soft
% association-to-attenuation mapping. Output-domain selection is handled by
% the main RemVarComp reconstruction/back-project checkbox for consistency
% with the legacy PCA/ICA methods. Spatial geometry is resolved internally
% from the active imaging context and is not user-configurable here.
% -------------------------------------------------------------------------

    methods (Static)
        function specMap = specs(ctx)
            % specs  Return the nested subconfiguration schema map for supported methods.
            %   Used by parent modules, UI builders, and documentation extraction so method-specific
            %   options remain centralized in this library.

            if nargin < 1, ctx = struct(); end
            specMap = struct();
            specMap.waveletpca = NMRemVarCompWaveletSubconfigLibrary.spec('waveletPCA', ctx);
            specMap.waveletica = NMRemVarCompWaveletSubconfigLibrary.spec('waveletICA', ctx);
            specMap.waveletdirect = NMRemVarCompWaveletSubconfigLibrary.spec('waveletDirect', ctx);
        end

        function spec = spec(method, ctx) %#ok<INUSD>
            % spec  Return the schema for one nested method/algorithm.
            %   The returned schema drives defaultParams, validateParams, UI rendering, and legacy
            %   conversion for the parent preprocessing module.

            method = NMRemVarCompWaveletSubconfigLibrary.canonMethod(method);
            spec = struct();
            spec.id = method;
            spec.kind = 'remvarcomp-wavelet-subconfig';
            spec.title = NMRemVarCompWaveletSubconfigLibrary.title(method);
            if strcmpi(method,'waveletDirect')
                spec.description = ['Experimental direct wavelet-coefficient nuisance attenuation. ', ...
                    'The decomposition is fixed; supervision enters through training-fold coefficient-wise associations with G, ', ...
                    'optionally partialled for protected covariates. Application to held-out or external data uses stored band-wise alpha maps ', ...
                    'and does not require target scanner covariates. Output is controlled by the main RemVarComp back-project/reconstruct checkbox.'];
            else
                spec.description = ['Experimental wavelet-domain nuisance attenuation. ', ...
                    'The decomposition is fixed; supervision enters only through training-fold component/covariate associations that define soft attenuation weights. ', ...
                    'Application to held-out or external data projects into the frozen per-band PCA/ICA spaces and does not require target scanner covariates. ', ...
                    'Output is controlled by the main RemVarComp back-project/reconstruct checkbox.'];
            end
            spec.cliConfigurator = '';
            spec.status = 'experimental';
            spec.fields = { ...
                struct('name','family','type','enum','default','b3spline','label','Wavelet kernel', ...
                    'values',{{'b3spline','haar'}}, ...
                    'help','Use an a trous wavelet reconstruction for image-space processing.'), ...
                struct('name','boundary','type','enum','default','mirror','label','Boundary handling', ...
                    'values',{{'mirror','zero'}}, ...
                    'help','Choose mirror or zero wavelet boundary extension.'), ...
                struct('name','levels','type','numeric_vector','default',[1 2 3],'label','Decomposition levels', ...
                    'allowEmpty',false, ...
                    'help','The maximum level defines A_J; signed detail bands D_1...D_J are reconstructed using detail_bands.'), ...
                struct('name','bandSet','type','enum','default','approximation_and_details','label','Bands to correct/recompose', ...
                    'values',{{'approximation_and_details','approximation_only','details_only'}}, ...
                    'help','approximation_and_details reconstructs A_J + D_1 + ... + D_J. Only signed bands are used because magnitude/energy bands are not invertible.'), ...
                struct('name','protectLabel','type','boolean','default',true,'label','Protect outcome-label variance', ...
                    'help','For waveletDirect, labels are partialled out when estimating nuisance association maps, giving the method a ComBat-like preserve-biological-design flavour. Stored only in the training-fold correction model; not needed at application time.'), ...
                struct('name','protectedCovariateColumns','type','covariate_indices','default',[],'allowEmpty',true,'multiple',true,'label','Protected covariate columns', ...
                    'help','Select additional covariates whose variance should be protected during training-fold nuisance attenuation.'), ...
                struct('name','protectedWorkspaceVar','type','workspace_var','default','','label','Protected workspace matrix', ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Optional numeric workspace vector/matrix with one row per subject. Columns are added to the protected design in waveletDirect.'), ...
                struct('name','alphaMode','type','enum','default','soft_r2_shrinkage','label','Association-to-attenuation mapping', ...
                    'values',{{'soft_r2_shrinkage','soft_corr'}}, ...
                    'help','Continuous mapping from training-fold component/coefficient nuisance association strength to attenuation alpha. No corr/p-value threshold or hard deletion is used in wavelet mode.'), ...
                struct('name','tau','type','number','default',0.02,'min',eps,'label','Soft-shrinkage tau', ...
                    'visibleIf',struct('field','alphaMode','equals','soft_r2_shrinkage'), ...
                    'help','Larger values make the correction more conservative.'), ...
                struct('name','maxAlpha','type','number','default',1,'min',0,'max',1,'label','Maximum attenuation', ...
                    'help','Upper bound for component-/coefficient-wise attenuation weights.'), ...
                struct('name','bandAlphaNormalization','type','enum','default','none','label','Global band attenuation scaling', ...
                    'values',{{'none','divide_by_sqrt_nbands','divide_by_nbands'}}, ...
                    'help','Optional global scaling of per-band alpha weights. none preserves the raw per-band association strength; the other choices make total correction strength less dependent on the number of bands.'), ...
                struct('name','batchSize','type','integer','default',8,'min',1,'label','Wavelet batch size', ...
                    'help','Number of image samples processed per wavelet batch.'), ...
                struct('name','tolerance','type','numeric_vector','default',1e-4,'allowEmpty',false,'label','fastICA tolerance', ...
                    'visibleIf',struct('field','__algorithm','equals','waveletICA'), ...
                    'help','Convergence tolerance candidate(s) used by fastICA.'), ...
                struct('name','max_iters','type','numeric_vector','default',200,'allowEmpty',false,'label','fastICA maximum iterations', ...
                    'visibleIf',struct('field','__algorithm','equals','waveletICA'), ...
                    'help','Maximum iteration candidate(s) used by fastICA.'), ...
                struct('name','algorithm_opt','type','enum','default','parallel','label','fastICA algorithm', ...
                    'values',{{'parallel','deflation'}}, ...
                    'visibleIf',struct('field','__algorithm','equals','waveletICA'), ...
                    'help','Select parallel or deflationary fastICA estimation.'), ...
                struct('name','whiten_opt','type','enum','default','unit-variance','label','fastICA whitening strategy', ...
                    'values',{{'unit-variance','arbitrary-variance'}}, ...
                    'visibleIf',struct('field','__algorithm','equals','waveletICA'), ...
                    'help','Choose unit-variance or arbitrary-variance fastICA whitening.'), ...
                struct('name','fun_opt','type','enum','default','logcosh','label','fastICA G-function', ...
                    'values',{{'logcosh','exp','cube'}}, ...
                    'visibleIf',struct('field','__algorithm','equals','waveletICA'), ...
                    'help','Choose the fastICA contrast nonlinearity (logcosh, exp or cube).') };
        end

        function fp = fastICASubSpecs()
            % fastICASubSpecs  Return the fastICA sub-schema used inside wavelet ICA settings.
            %   Centralizes options that mirror cv_fastICA_config so wavelet RemVarComp export
            %   remains consistent.

            s = struct();
            s.waveletica = struct();
            s.waveletica.id = 'waveletICA';
            s.waveletica.kind = 'remvarcomp-wavelet-fastica-subconfig';
            s.waveletica.title = 'fastICA inside wavelet bands';
            s.waveletica.description = 'Equivalent to cv_fastICA_config, applied independently inside each signed wavelet band.';
            s.waveletica.fields = { ...
                struct('name','tolerance','type','numeric_vector','default',1e-4,'allowEmpty',false,'label','Tolerance parameter(s)', ...
                    'help','Convergence tolerance candidate(s) used by fastICA.'), ...
                struct('name','max_iters','type','numeric_vector','default',200,'allowEmpty',false,'label','Maximum iteration value(s)', ...
                    'help','Maximum iteration candidate(s) used by fastICA.'), ...
                struct('name','algorithm_opt','type','enum','default','parallel','label','fastICA algorithm', 'values',{{'parallel','deflation'}}, ...
                    'help','Select parallel or deflationary fastICA estimation.'), ...
                struct('name','whiten_opt','type','enum','default','unit-variance','label','Whitening strategy', 'values',{{'unit-variance','arbitrary-variance'}}, ...
                    'help','Choose unit-variance or arbitrary-variance fastICA whitening.'), ...
                struct('name','fun_opt','type','enum','default','logcosh','label','G-function', 'values',{{'logcosh','exp','cube'}}, ...
                    'help','Choose the fastICA contrast nonlinearity (logcosh, exp or cube).') };
            fp = s;
        end

        function cfg = defaultParams(method, ctx)
            % defaultParams  Return default parameters for a nested method/algorithm.
            %   Defaults come from the method schema and are normalized before parent modules embed
            %   them into canonical configs.

            if nargin < 2, ctx = struct(); end
            cfg = NMConfigTools.defaultsFromSpec(NMRemVarCompWaveletSubconfigLibrary.spec(method, ctx));
            cfg = NMRemVarCompWaveletSubconfigLibrary.normalizeParams(method, cfg, ctx);
        end

        function [cfg, report] = validateParams(method, cfg, ctx, strict)
            % validateParams  Validate nested method/algorithm parameters.
            %   Returns normalized params and a report so parent modules can distinguish strict API
            %   errors from permissive legacy import repair.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = false; end
            if nargin < 2 || isempty(cfg) || ~isstruct(cfg), cfg = struct(); end
            spec = NMRemVarCompWaveletSubconfigLibrary.spec(method, ctx);
            [cfg, report] = NMConfigTools.validateConfig(spec, cfg, ctx, strict);
            if ~report.ok, return; end
            cfg = NMRemVarCompWaveletSubconfigLibrary.normalizeValues(method, cfg);
        end

        function cfg = normalizeParams(method, cfg, ctx)
            % normalizeParams  Normalize nested parameters or raise if validation fails.
            %   Used immediately before legacy export so generated ACTPARAM branches use canonical,
            %   backend-compatible values.

            if nargin < 2 || isempty(cfg) || ~isstruct(cfg), cfg = struct(); end
            if nargin < 3, ctx = struct(); end
            [cfg, report] = NMRemVarCompWaveletSubconfigLibrary.validateParams(method, cfg, ctx, false);
            if ~report.ok
                error('NMRemVarCompWaveletSubconfigLibrary:invalidParams','%s',strjoin(report.errors,newline));
            end
        end

        function W = toLegacy(method, cfg, ctx)
            % toLegacy  Convert nested method parameters to a legacy payload.
            %
            % Used by parent modules that need a complete sub-branch rather than in-place mutation
            % of a larger ACTPARAM struct.
            %
            % cfg.alphaMode: stores the normalized alpha mode value in the module configuration.
            % cfg.bandAlphaNormalization: stores the normalized band alpha normalization value in the module configuration.
            % cfg.bandSet: stores the normalized band set value in the module configuration.
            % cfg.batchSize: stores the normalized batch size value in the module configuration.
            % cfg.boundary: stores the normalized boundary value in the module configuration.
            % cfg.family: stores the normalized family value in the module configuration.
            % cfg.levels: stores the normalized levels value in the module configuration.
            % cfg.maxAlpha: stores the normalized max alpha value in the module configuration.
            % cfg.tau: stores the normalized tau value in the module configuration.

            if nargin < 3, ctx = struct(); end
            rawCfg = cfg;
            cfg = NMRemVarCompWaveletSubconfigLibrary.normalizeParams(method, cfg, ctx);
            W = struct();
            W.enabled = true;
            W.family = char(cfg.family);
            W.boundary = char(cfg.boundary);
            W.levels = cfg.levels(:)';
            W.maxLevel = max(W.levels);
            W.bandSet = char(cfg.bandSet);
            W.baseReductionMethod = NMRemVarCompWaveletSubconfigLibrary.baseReductionMethod(method);
            W.alphaMode = char(cfg.alphaMode);
            W.tau = double(cfg.tau);
            W.maxAlpha = double(cfg.maxAlpha);
            W.bandAlphaNormalization = char(cfg.bandAlphaNormalization);
            W.assertPartition = logical(local_get_cfg(rawCfg,'assertPartition',true));
            W.partitionTolerance = double(local_get_cfg(rawCfg,'partitionTolerance',1e-8));
            W.batchSize = double(cfg.batchSize);
            W.outputDomain = char(local_get_cfg(rawCfg,'outputDomain','image'));
            if ~any(strcmpi(W.outputDomain, {'image','embedding'})), W.outputDomain = 'image'; end
            W.reconstructImage = strcmpi(W.outputDomain, 'image');
            W.finalEmbeddingMethod = char(local_get_cfg(rawCfg,'finalEmbeddingMethod','PCA'));
            if ~any(strcmpi(W.finalEmbeddingMethod, {'PCA','fastICA'})), W.finalEmbeddingMethod = 'PCA'; end
            W.transform = 'undecimated_atrous_3d';
            W.SPATIAL = NMRemVarCompWaveletSubconfigLibrary.resolveSpatialGeometry(ctx);
            cm = NMRemVarCompWaveletSubconfigLibrary.canonMethod(method);
            if strcmpi(cm,'waveletICA') || (strcmpi(cm,'waveletDirect') && strcmpi(W.outputDomain,'embedding') && strcmpi(W.finalEmbeddingMethod,'fastICA'))
                W.fastICA = NMRemVarCompWaveletSubconfigLibrary.normalizeFastICA(rawCfg);
            else
                W.fastICA = NMRemVarCompWaveletSubconfigLibrary.normalizeFastICA(struct());
            end
        end

        function cfg = fromLegacy(method, W, ctx)
            % fromLegacy  Import nested method parameters from a legacy payload.
            %   Preserves older ACTPARAM fields while returning canonical params suitable for UI
            %   display and later re-export.

            if nargin < 3, ctx = struct(); end
            cfg = NMRemVarCompWaveletSubconfigLibrary.defaultParams(method, ctx);
            if ~isstruct(W), return; end
            fns = {'family','boundary','levels','bandSet','alphaMode','tau','maxAlpha','bandAlphaNormalization','batchSize'};
            for i=1:numel(fns)
                if isfield(W,fns{i}) && ~isempty(W.(fns{i})), cfg.(fns{i}) = W.(fns{i}); end
            end
            if isfield(W,'fastICA') && isstruct(W.fastICA)
                fp = W.fastICA;
                fpf = fieldnames(fp);
                for j=1:numel(fpf), cfg.(fpf{j}) = fp.(fpf{j}); end
            end
            cfg = NMRemVarCompWaveletSubconfigLibrary.normalizeParams(method, cfg, ctx);
        end

        function method = canonMethod(method)
            % canonMethod  Normalize method aliases to canonical library tokens.
            %   Keeps UI labels, legacy command names, and power-user shorthand on the same
            %   validation/export path.

            if isempty(method), method = 'waveletPCA'; return; end
            m = lower(char(method));
            switch m
                case {'waveletica','wavelet_ica','waveletfastica','wavelet_fastica'}
                    method = 'waveletICA';
                case {'waveletdirect','wavelet_direct','waveletcoeff','wavelet_coeff','waveletmap'}
                    method = 'waveletDirect';
                otherwise
                    method = 'waveletPCA';
            end
        end

        function titleStr = title(method)
            % title  Return a readable title for a nested method/algorithm.
            %   Used by config schemas, UI controls, and RAG documentation instead of exposing raw
            %   legacy command ids.

            cm = NMRemVarCompWaveletSubconfigLibrary.canonMethod(method);
            if strcmpi(cm,'waveletICA')
                titleStr = 'Wavelet-domain RemVarComp using fastICA';
            elseif strcmpi(cm,'waveletDirect')
                titleStr = 'Direct wavelet-coefficient RemVarComp';
            else
                titleStr = 'Wavelet-domain RemVarComp using PCA';
            end
        end

        function base = baseReductionMethod(method)
            % baseReductionMethod  Map a wavelet method to its underlying reduction strategy.
            %   Used during legacy export/import to decide whether PCA, fastICA, or direct
            %   coefficient handling is required.

            cm = NMRemVarCompWaveletSubconfigLibrary.canonMethod(method);
            if strcmpi(cm,'waveletICA')
                base = 'fastICA';
            elseif strcmpi(cm,'waveletDirect')
                base = 'direct';
            else
                base = 'PCA';
            end
        end

        function cfg = normalizeValues(method, cfg)
            % normalizeValues  Coerce wavelet configuration values to backend-safe ranges.
            %
            % Normalizes levels, alpha/tau limits, batch size, and band selections before legacy
            % export.
            %
            % cfg.algorithm_opt: stores the normalized algorithm opt value in the module configuration.
            % cfg.bandAlphaNormalization: stores the normalized band alpha normalization value in the module configuration.
            % cfg.batchSize: stores the normalized batch size value in the module configuration.
            % cfg.fun_opt: stores the normalized fun opt value in the module configuration.
            % cfg.levels: stores the normalized levels value in the module configuration.
            % cfg.max_iters: stores the normalized max iters value in the module configuration.
            % cfg.maxAlpha: stores the normalized max alpha value in the module configuration.
            % cfg.tau: stores the normalized tau value in the module configuration.
            % cfg.tolerance: stores the normalized tolerance value in the module configuration.
            % cfg.whiten_opt: stores the normalized whiten opt value in the module configuration.

            cfg.levels = unique(round(double(cfg.levels(:)')));
            cfg.levels = cfg.levels(cfg.levels >= 1);
            if isempty(cfg.levels), cfg.levels = [1 2 3]; end
            cfg.batchSize = max(1, round(double(cfg.batchSize)));
            cfg.tau = max(eps, double(cfg.tau));
            cfg.maxAlpha = min(1, max(0, double(cfg.maxAlpha)));
            if ~any(strcmpi(char(cfg.bandAlphaNormalization), {'none','divide_by_sqrt_nbands','divide_by_nbands'}))
                cfg.bandAlphaNormalization = 'none';
            end
            if strcmpi(NMRemVarCompWaveletSubconfigLibrary.canonMethod(method),'waveletICA')
                fp = NMRemVarCompWaveletSubconfigLibrary.normalizeFastICA(cfg);
                cfg.tolerance = fp.tolerance;
                cfg.max_iters = fp.max_iters;
                cfg.algorithm_opt = fp.algorithm_opt;
                cfg.whiten_opt = fp.whiten_opt;
                cfg.fun_opt = fp.fun_opt;
            end
        end

        function fp = normalizeFastICA(fp)
            % normalizeFastICA  Normalize embedded fastICA settings for wavelet ICA.
            %   Fills defaults and sanitizes algorithm/whitening/nonlinearity options before
            %   inserting them into the wavelet legacy branch.

            if nargin < 1 || isempty(fp) || ~isstruct(fp), fp = struct(); end
            def = struct('tolerance',1e-4,'max_iters',200,'algorithm_opt','parallel','whiten_opt','unit-variance','fun_opt','logcosh');
            f = fieldnames(def);
            for i=1:numel(f)
                if ~isfield(fp,f{i}) || isempty(fp.(f{i})), fp.(f{i}) = def.(f{i}); end
            end
        end

        function SP = resolveSpatialGeometry(ctx)
            % resolveSpatialGeometry  Resolve wavelet geometry from canonical preprocessing context.
            %
            % NMPreprocContext.fromNM publishes the active brainmask together
            % with the inherited per-modality threshold operator/value written
            % by TransferModality2NM. Those facts reproduce the feature axis
            % used by nk_ReturnSubSpaces without reopening NM or accepting a
            % preserved SPATIAL payload as a competing geometry authority.
            if ~isstruct(ctx) || ~isfield(ctx,'brainmask') || isempty(ctx.brainmask)
                error('NMRemVarCompWaveletSubconfigLibrary:missingGeometry', ...
                    'Wavelet RemVarComp requires ctx.brainmask from NMPreprocContext.');
            end
            if ~isfield(ctx,'spatialMaskOperator') || isempty(ctx.spatialMaskOperator) || ...
                    ~isfield(ctx,'spatialMaskValue') || isempty(ctx.spatialMaskValue)
                error('NMRemVarCompWaveletSubconfigLibrary:missingMaskSelector', ...
                    'Wavelet RemVarComp requires the active modality mask operator and value from NMPreprocContext.');
            end
            if exist('spm_vol','file') ~= 2 || exist('spm_read_vols','file') ~= 2
                error('NMRemVarCompWaveletSubconfigLibrary:missingSPM', ...
                    'Resolving wavelet RemVarComp geometry from a brainmask requires spm_vol and spm_read_vols on the MATLAB path.');
            end
            op = char(string(ctx.spatialMaskOperator));
            val = ctx.spatialMaskValue;
            if ~isscalar(val) || ~isnumeric(val) || ~isfinite(double(val)) || ...
                    ~any(strcmp(op, {'gt','ge','eq','lt','le'}))
                error('NMRemVarCompWaveletSubconfigLibrary:badMaskSelector', ...
                    'The active modality mask selector must contain one numeric threshold and one of gt/ge/eq/lt/le.');
            end
            Vm = spm_vol(ctx.brainmask);
            M = spm_read_vols(Vm);
            SP = struct();
            SP.dims = double(Vm.dim(1:3));
            SP.indvol = find(feval(op, M, double(val)));
            SP.brainmask = ctx.brainmask;
            SP.thresholdOperator = op;
            SP.thresholdValue = double(val);
        end
    end
end

function v = local_get_cfg(cfg, name, defaultVal)
    % local_get_cfg  Return a named config field or fallback value.
    %   Small public compatibility helper used by legacy translation code; kept documented because
    %   it is currently public.

if isstruct(cfg) && isfield(cfg,name) && ~isempty(cfg.(name))
    v = cfg.(name);
else
    v = defaultVal;
end
end
