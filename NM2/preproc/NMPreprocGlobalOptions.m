classdef NMPreprocGlobalOptions
% NMPreprocGlobalOptions
% -------------------------------------------------------------------------
% Adapter for top-level legacy PREPROC fields that are configured by
% nk_Preproc_config outside the ACTPARAM sequence:
%   PREPROC.BINMOD
%   PREPROC.LABELMOD.TARGETSCALE
%   PREPROC.LABELMOD.POLYNOM
%   PREPROC.LABELMOD.LABELIMPUTE only for global/final missing-label handling
%   PREPROC.LABELMOD.cmd = 'labelimpute'
%
% Non-'none' label-imputation methods are not exported here: they are
% represented as CV-bound ACTPARAM labelimpute steps because their position
% in the preprocessing pipeline changes the feature space used for label
% propagation.
% -------------------------------------------------------------------------

    methods (Static)
        function opts = defaultOptions(ctx)
            % defaultOptions  Create default preprocessing-wide options for a context.
            %   Initializes BINMOD, target transformation, and label-imputation defaults before
            %   module sequences are added or a legacy PREPROC branch is imported.

            if nargin < 1 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            opts = struct();
            opts.binmod = NMPreprocGlobalOptions.defaultBinmod(ctx);
            opts.enableTargetTransform = false;
            opts.targetScale = false;
            opts.usePolynomial = false;
            opts.polynomial = 1;
            opts.enableLabelImpute = false;
            opts.labelImputeMethod = 'none';
            opts.labelImputeK = 7;
            opts.legacyLABELMOD = struct();
        end

        function opts = fromLegacy(PREPROC, ctx)
            % fromLegacy  Import preprocessing-wide options from a legacy PREPROC struct.
            %   Reads BINMOD, LABELMOD, target transform/scale flags, and imported metadata so an
            %   old NM branch can be shown and edited through the modular API.

            if nargin < 2 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            opts = NMPreprocGlobalOptions.defaultOptions(ctx);
            if nargin < 1 || isempty(PREPROC), return; end

            if isstruct(PREPROC) && isfield(PREPROC,'BINMOD') && ~isempty(PREPROC.BINMOD)
                opts.binmod = double(logical(PREPROC.BINMOD));
            else
                opts.binmod = NMPreprocGlobalOptions.defaultBinmod(ctx);
            end
            if NMPreprocGlobalOptions.ctxBool(ctx,'forceMultiGroupBinmod',false)
                opts.binmod = 0;
            end

            if isstruct(PREPROC) && isfield(PREPROC,'LABELMOD') && isstruct(PREPROC.LABELMOD)
                LM = PREPROC.LABELMOD;
                opts.legacyLABELMOD = LM;
                if isfield(LM,'TARGETSCALE') && ~isempty(LM.TARGETSCALE)
                    opts.enableTargetTransform = true;
                    opts.targetScale = logical(LM.TARGETSCALE);
                end
                if isfield(LM,'POLYNOM') && ~isempty(LM.POLYNOM)
                    opts.enableTargetTransform = true;
                    opts.usePolynomial = true;
                    opts.polynomial = double(LM.POLYNOM);
                end
                if isfield(LM,'LABELIMPUTE') && ~isempty(LM.LABELIMPUTE)
                    opts.enableLabelImpute = true;
                    L = LM.LABELIMPUTE;
                    if isfield(L,'method') && ~isempty(L.method)
                        opts.labelImputeMethod = NMPreprocGlobalOptions.canonicalLabelImputeMethod(L.method);
                    end
                    if isfield(L,'k') && ~isempty(L.k)
                        opts.labelImputeK = double(L.k);
                    end
                elseif isfield(LM,'cmd') && strcmpi(char(LM.cmd),'labelimpute')
                    opts.enableLabelImpute = true;
                end
            end
            opts = NMPreprocGlobalOptions.normalize(opts, ctx);
        end

        function PREPROC = toLegacy(PREPROC, opts, ctx)
            % toLegacy  Write preprocessing-wide options back into a legacy PREPROC struct.
            %
            % Normalizes options first, then updates BINMOD, LABELMOD, and target-transform fields
            % around the module-generated ACTPARAM/SPATIAL branches.
            %
            % opts.binmod: configures optional binmod behavior for this call.
            % opts.enableLabelImpute: configures optional enable label impute behavior for this call.
            % opts.enableTargetTransform: configures optional enable target transform behavior for this call.
            % opts.labelImputeK: configures optional label impute k behavior for this call.
            % opts.labelImputeMethod: configures optional label impute method behavior for this call.
            % opts.legacyLABELMOD: configures optional legacy labelmod behavior for this call.
            % opts.polynomial: configures optional polynomial behavior for this call.
            % opts.targetScale: configures optional target scale behavior for this call.
            % opts.usePolynomial: configures optional use polynomial behavior for this call.

            if nargin < 1 || isempty(PREPROC), PREPROC = struct(); end
            if nargin < 2 || isempty(opts), opts = NMPreprocGlobalOptions.defaultOptions(ctx); end
            if nargin < 3 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            opts = NMPreprocGlobalOptions.normalize(opts, ctx);

            PREPROC.BINMOD = opts.binmod;
            if NMPreprocGlobalOptions.ctxBool(ctx,'forceMultiGroupBinmod',false)
                PREPROC.BINMOD = 0;
            end

            if isfield(PREPROC,'LABELMOD') && isstruct(PREPROC.LABELMOD)
                LM = PREPROC.LABELMOD;
            elseif isfield(opts,'legacyLABELMOD') && isstruct(opts.legacyLABELMOD)
                LM = opts.legacyLABELMOD;
            else
                LM = struct();
            end

            if logical(opts.enableTargetTransform) || logical(opts.targetScale) || logical(opts.usePolynomial)
                LM.TARGETSCALE = double(logical(opts.targetScale));
                if logical(opts.usePolynomial)
                    LM.POLYNOM = double(opts.polynomial);
                elseif isfield(LM,'POLYNOM')
                    LM = rmfield(LM,'POLYNOM');
                end
            else
                if isfield(LM,'TARGETSCALE'), LM = rmfield(LM,'TARGETSCALE'); end
                if isfield(LM,'POLYNOM'), LM = rmfield(LM,'POLYNOM'); end
            end

            % Global LABELMOD.LABELIMPUTE is reserved for the final
            % post-preprocessing label-handling path in
            % nk_MLOptimizer_ExtractDimMat. If the method is non-'none', the
            % same configurator must be represented as a CV-bound ACTPARAM
            % labelimpute step so its position in the preprocessing chain is
            % respected. The orchestrator normalizes that placement; this
            % exporter therefore writes only the global/final 'none' case.
            if logical(opts.enableLabelImpute) && strcmpi(char(opts.labelImputeMethod),'none')
                L = struct();
                L.method = 'none';
                L.k = double(opts.labelImputeK);
                LM.LABELIMPUTE = L;
                LM.cmd = 'labelimpute';
            else
                if isfield(LM,'LABELIMPUTE'), LM = rmfield(LM,'LABELIMPUTE'); end
                if isfield(LM,'cmd') && strcmpi(char(LM.cmd),'labelimpute')
                    LM = rmfield(LM,'cmd');
                end
            end

            if isempty(fieldnames(LM))
                if isfield(PREPROC,'LABELMOD'), PREPROC = rmfield(PREPROC,'LABELMOD'); end
            else
                PREPROC.LABELMOD = LM;
            end
        end

        function spec = toUISpec(ctx, opts)
            % toUISpec  Return UI/API schema fields for preprocessing-wide options.
            %
            % Builds context-dependent controls for multi-group BINMOD, regression target
            % transforms, and label imputation; used beside the subject/CV module sequence
            % schemas.
            %
            % opts.binmod: configures optional binmod behavior for this call.
            % opts.enableLabelImpute: configures optional enable label impute behavior for this call.
            % opts.enableTargetTransform: configures optional enable target transform behavior for this call.
            % opts.labelImputeMethod: configures optional label impute method behavior for this call.
            % opts.polynomial: configures optional polynomial behavior for this call.
            % opts.targetScale: configures optional target scale behavior for this call.
            % opts.usePolynomial: configures optional use polynomial behavior for this call.

            if nargin < 1 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            if nargin < 2 || isempty(opts), opts = NMPreprocGlobalOptions.defaultOptions(ctx); end
            opts = NMPreprocGlobalOptions.normalize(opts, ctx);
            fields = {};

            if NMPreprocGlobalOptions.ctxBool(ctx,'isClassification',false) && NMPreprocGlobalOptions.ctxBool(ctx,'isMultiClass',false)
                if NMPreprocGlobalOptions.ctxBool(ctx,'forceMultiGroupBinmod',false)
                    fields{end+1} = struct('name','binmodNote','type','readonly','default','One-vs-all decomposition detected: multigroup processing is required for this analysis.','label','Multiclass group-processing mode'); %#ok<AGROW>
                else
                    fields{end+1} = struct('name','binmod','type','enum','default',opts.binmod,'label','Multiclass group-processing mode', ...
                        'values',{NMPreprocGlobalOptions.binmodChoices()}, ...
                        'help','Controls the multiclass decomposition strategy and is shown only for multiclass classification.'); %#ok<AGROW>
                end
            end

            targetTransformAvailable = NMPreprocGlobalOptions.ctxBool(ctx,'isRegression',false) || ...
                logical(opts.enableTargetTransform) || logical(opts.targetScale) || logical(opts.usePolynomial);

            % Missing-label handling is rendered as a global module card/dropdown
            % rather than as duplicated scalar controls. The global module
            % represents the legacy final-label path only:
            % PREPROC.LABELMOD.LABELIMPUTE.method = 'none'. Non-'none'
            % methods are configured exclusively as CV-bound ACTPARAM
            % labelimpute steps.
            labelImputeAvailable = NMPreprocGlobalOptions.ctxBool(ctx,'hasNaNsInLabels',false) || opts.enableLabelImpute;

            spec = struct();
            spec.kind = 'NMPreprocGlobalOptions';
            spec.schemaVersion = 1;
            spec.title = 'Label and multiclass preprocessing options';
            spec.description = 'Global label and target preprocessing settings applied outside the ordered feature-preprocessing steps.';
            spec.fields = fields;
            spec.targetTransform = struct( ...
                'available', logical(targetTransformAvailable), ...
                'enabled', logical(opts.enableTargetTransform) || logical(opts.targetScale) || logical(opts.usePolynomial), ...
                'moduleId', 'targetmod', ...
                'displayName', 'Label / target transformation', ...
                'description', 'Regression target transformation applied before model fitting.', ...
                'fields', {{ ...
                    struct('name','targetScale','type','boolean','default',opts.targetScale,'label','Scale target values', ...
                        'help','Scale regression targets before model fitting.'), ...
                    struct('name','usePolynomial','type','boolean','default',opts.usePolynomial,'label','Apply power transformation to target', ...
                        'help','Enable polynomial transformation of the regression target.'), ...
                    struct('name','polynomial','type','number','default',opts.polynomial,'label','Target exponent', ...
                        'visibleIf',struct('field','usePolynomial','equals',true), ...
                        'help','Polynomial exponent applied to the regression target. A value of 1 leaves the target unchanged.') }});
            spec.labelImpute = struct( ...
                'available', logical(labelImputeAvailable), ...
                'enabled', logical(opts.enableLabelImpute) && strcmpi(char(opts.labelImputeMethod),'none'), ...
                'moduleId', 'labelimpute', ...
                'displayName', 'Label imputation', ...
                'method', 'none', ...
                'description', 'Final/global missing-label handling applied outside the CV-bound preprocessing sequence.');
            spec.defaultState = opts;
        end

        function opts = normalize(opts, ctx)
            % normalize  Normalize preprocessing-wide option values against context defaults.
            %
            % Coerces scalar/logical/string fields and enforces context-driven invariants such as
            % mandatory multi-group BINMOD or unavailable target transforms.
            %
            % opts.binmod: configures optional binmod behavior for this call.
            % opts.enableLabelImpute: configures optional enable label impute behavior for this call.
            % opts.enableTargetTransform: configures optional enable target transform behavior for this call.
            % opts.labelImputeK: configures optional label impute k behavior for this call.
            % opts.labelImputeMethod: configures optional label impute method behavior for this call.
            % opts.polynomial: configures optional polynomial behavior for this call.
            % opts.targetScale: configures optional target scale behavior for this call.
            % opts.usePolynomial: configures optional use polynomial behavior for this call.

            if nargin < 2 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            d = NMPreprocGlobalOptions.defaultOptions(ctx);
            opts = NMConfigTools.mergeStruct(d, opts);
            switch class(opts.binmod)
                case {'char','string'}
                    choices = NMPreprocGlobalOptions.binmodChoices();
                    choices = [choices{:}];
                    idx = find(strcmp(opts.binmod,{choices.symbol}),1);
                    if isempty(idx), error('NMPreprocGlobalOptions:invalidBinmod','Unknown binmod symbol: %s',char(opts.binmod)); end
                    opts.binmod = choices(idx).value;
            end
            opts.binmod = double(logical(NMPreprocGlobalOptions.scalarOrDefault(opts.binmod, d.binmod)));
            if NMPreprocGlobalOptions.ctxBool(ctx,'forceMultiGroupBinmod',false)
                opts.binmod = 0;
            end
            opts.enableTargetTransform = logical(opts.enableTargetTransform);
            opts.targetScale = logical(opts.targetScale);
            opts.usePolynomial = logical(opts.usePolynomial);
            opts.polynomial = double(NMPreprocGlobalOptions.scalarOrDefault(opts.polynomial, 1));
            if ~isfinite(opts.polynomial), opts.polynomial = 1; end
            opts.enableLabelImpute = logical(opts.enableLabelImpute);
            opts.labelImputeMethod = NMPreprocGlobalOptions.canonicalLabelImputeMethod(opts.labelImputeMethod);
            opts.labelImputeK = max(1, round(double(NMPreprocGlobalOptions.scalarOrDefault(opts.labelImputeK, 7))));
        end

        function choices = binmodChoices()
            choices = {struct('value',1,'symbol','binary','label','Binary/pairwise processing'), ...
                       struct('value',0,'symbol','multigroup','label','Multigroup processing')};
        end

        function b = defaultBinmod(ctx)
            % defaultBinmod  Return the context-sensitive default for legacy BINMOD.
            %   Classification defaults to binary decomposition unless the context requires native
            %   multi-group handling.

            b = 1;
            if nargin >= 1 && NMPreprocGlobalOptions.ctxBool(ctx,'forceMultiGroupBinmod',false)
                b = 0;
            end
        end

        function m = canonicalLabelImputeMethod(m)
            % canonicalLabelImputeMethod  Normalize label-imputation method aliases for UI and legacy export.
            %   Maps synonymous labels such as cityblock/manhattan while preserving the canonical
            %   tokens used by PREPROC.LABELMOD.

            if isempty(m), m = 'none'; return; end
            m = lower(char(m));
            switch m
                case {'cityblock','manhattan'}
                    m = 'manhattan';
                case {'dist','dist2','euclid','euclidean'}
                    m = 'euclidean';
                case {'seuclid','seuclidean'}
                    m = 'seuclidean';
                case {'cos','cosine'}
                    m = 'cosine';
                case {'ham','hamming'}
                    m = 'hamming';
                case {'jac','jaccard'}
                    m = 'jaccard';
                case {'learner','supervised','ml'}
                    m = 'ml';
                otherwise
                    m = 'none';
            end
        end

        function tf = ctxBool(ctx, field, defaultVal)
            % ctxBool  Read a logical flag from a context struct with fallback.
            %   Used throughout global-option schema and normalization code to avoid repeated
            %   fragile isfield/logical conversion blocks.

            if nargin < 3, defaultVal = false; end
            tf = defaultVal;
            try
                if isstruct(ctx) && isfield(ctx,field) && ~isempty(ctx.(field))
                    tf = logical(ctx.(field));
                end
            catch
                tf = defaultVal;
            end
        end

        function x = scalarOrDefault(x, defaultVal)
            % scalarOrDefault  Extract a scalar option value or substitute a default.
            %   Protects global option normalization from empty arrays, vectors, strings, and
            %   invalid caller-provided values.

            try
                if isempty(x), x = defaultVal; return; end
                if isnumeric(x) || islogical(x)
                    x = x(1);
                else
                    x = str2double(char(x));
                    if isnan(x), x = defaultVal; end
                end
            catch
                x = defaultVal;
            end
        end
    end
end
