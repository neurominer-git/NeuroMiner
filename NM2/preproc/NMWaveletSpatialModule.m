classdef NMWaveletSpatialModule < NMPreprocModule
% NMWaveletSpatialModule
% -------------------------------------------------------------------------
% Subject-specific, image-preserving multiscale wavelet reconstruction.
%
% This module is deliberately implemented as an image-space operation rather
% than a wavelet-coefficient feature extractor. Its output has the same
% voxel geometry as the input and can therefore feed downstream JuSpace,
% ROImeans or KL graph construction in PREPROC.SPATIAL chains.
% -------------------------------------------------------------------------

    methods
        function obj = NMWaveletSpatialModule()
            % NMWaveletSpatialModule  Construct the Wavelet spatial reconstruction preprocessing adapter.
            %   Registers module id 'waveletSpatial' with legacy branch 'WAVELET' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('waveletSpatial','WAVELET','Wavelet spatial reconstruction');
            obj.Category = 'subject-preprocessing';
            obj.Aliases = {'wavelet','spatialwavelet','waveletreconstruction'};
            obj.Capabilities.executionStages = {'subject'};
            obj.Capabilities.imagingOnly = true;
            obj.Capabilities.requiresImageSpace = true;
            obj.Capabilities.isImageSpaceTerminal = false;
            obj.Capabilities.uniqueAcrossStages = false;
            obj.Capabilities.trainFoldEstimated = false;
            obj.Capabilities.changesFeatureSpace = false;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = '';
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Wavelet spatial reconstruction.
            %   Defines editable fields for the module that adds wavelet-domain spatial
            %   reconstruction as a subject-level preprocessing step. The schema feeds
            %   defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            if isequal(ctx,struct()), ctx = NMPreprocContext.empty(); end
            isSurface = strcmp(ctx.datasource,'surf');
            familyDefault = 'b3spline';
            familyValues = {'b3spline','haar','heat'};
            if isSurface
                familyDefault = 'heat';
                familyValues = {'heat'};
                spec.description = ['Undecimated graph heat-wavelet reconstruction on the validated native surface mesh. ', ...
                    'Output retains the input vertex axis. Multiple levels define alternative surface smoothing scales.'];
                familyHelp = 'The surface mesh uses the heat graph-wavelet kernel.';
                levelHelp = 'Select one or more graph-wavelet levels; the heat smoothing scale doubles with each level.';
                reconstructionHelp = ['Approximation returns the smoothed surface signal; denoised recombines the approximation and thresholded details. ', ...
                    'Selected_details sums selected graph-wavelet detail bands; detail_bands returns signed D_j, ', ...
                    'detail_magnitude returns abs(D_j), and detail_energy returns D_j.^2.'];
                batchHelp = 'Number of subjects processed in each batch of surface heat-wavelet operations.';
            else
                if any(strcmp(ctx.datasource,{'spm','nifti'}))
                    familyValues = {'b3spline','haar'};
                end
                spec.description = ['Image-preserving undecimated 3-D wavelet reconstruction. ', ...
                    'The output remains in voxel space and can precede JuSpace, ROI means, or KL graph construction. ', ...
                    'Multiple levels create subject-spatial hyperparameter branches analogous to multiple smoothing FWHM values.'];
                familyHelp = 'B3-spline and Haar are voxel-grid kernels; the heat graph-wavelet kernel applies to surface meshes.';
                levelHelp = 'Select one or more wavelet decomposition levels. Multiple levels can be evaluated as preprocessing alternatives.';
                reconstructionHelp = ['Approximation returns the low-pass image at the selected level; denoised reconstructs approximation plus thresholded details; ', ...
                    'selected_details returns the cumulative configured detail residuals; detail_bands returns the scale-specific signed detail band D_j; ', ...
                    'detail_magnitude returns abs(D_j); detail_energy returns D_j.^2.'];
                batchHelp = 'Controls memory use during vectorized 4-D wavelet convolution.';
            end
            spec.fields = { ...
                struct('name','family','type','enum','default',familyDefault,'label','Wavelet kernel', ...
                    'values',{familyValues},'uiHidden',isSurface, ...
                    'help',familyHelp), ...
                struct('name','boundary','type','enum','default','mirror','label','Boundary handling', ...
                    'values',{{'mirror','zero'}},'uiHidden',isSurface, ...
                    'help','Volumetric boundary handling: mirror uses symmetric padding; zero uses convn(...,''same'') zero-padding. Surface heat-wavelets do not use voxel-grid boundaries.'), ...
                struct('name','levels','type','numeric_vector','default',[1 2 3],'label','Decomposition level(s)', ...
                    'allowEmpty',false,'help',levelHelp), ...
                struct('name','reconstructionMode','type','enum','default','approximation','label','Reconstruction mode', ...
                    'values',{{'approximation','denoised','selected_details','detail_bands','detail_magnitude','detail_energy'}}, ...
                    'help',reconstructionHelp), ...
                struct('name','applyWaveletToExternalWeightMap','type','boolean','default',true, ...
                    'label','Apply wavelet reconstruction to external weighting image', ...
                    'visibleIfDownstreamExternalRanking',true, ...
                    'help',['Visible only when a downstream feature-ranking step uses external ranking. ', ...
                            'The browser auto-selects this option for approximation/denoised reconstruction and auto-clears it for detail-derived feature spaces; manual disagreement with this recommendation raises a warning.']), ...
                struct('name','applyWaveletToExternalWeightMapManualOverride','type','boolean','default',false, ...
                    'label','Manual external weighting-map override','uiHidden',true, ...
                    'help','Retains an explicit manual weighting-map setting rather than deriving it from reconstructionMode.'), ...
                struct('name','detailLevels','type','numeric_vector','default',[1 2 3],'label','Detail levels to reconstruct', ...
                    'visibleIf',struct('field','reconstructionMode','equals','selected_details'), ...
                    'help','Only used for selected_details. Levels exceeding the current branch level are ignored; with levels [1 2 3] and detailLevels [1 2 3], branches are D1, D1+D2 and D1+D2+D3.'), ...
                struct('name','thresholdMode','type','enum','default','soft','label','Detail thresholding', ...
                    'values',{{'none','soft','hard'}}, ...
                    'visibleIf',struct('field','reconstructionMode','equals','denoised'), ...
                    'help','Choose no detail thresholding, soft shrinkage, or hard thresholding for denoised reconstruction.'), ...
                struct('name','thresholdSigma','type','number','default',3,'label','Threshold multiplier', ...
                    'min',0,'visibleIf',struct('all',{{struct('field','reconstructionMode','equals','denoised'),struct('field','thresholdMode','in',{{'soft','hard'}})}}), ...
                    'help','Multiplier applied to a robust per-subject noise estimate from wavelet detail coefficients.'), ...
                struct('name','batchSize','type','integer','default',8,'min',1,'label','Subject batch size', ...
                    'help',batchHelp), ...
                struct('name','legacySPATIAL','type','struct','default',struct(),'label','Raw legacy SPATIAL structure','uiHidden',true, ...
                    'help','Preserved imported SPATIAL fields used during legacy round-trip; current wavelet settings determine the exported wavelet branch.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Preserved imported PX parameter metadata; the current wavelet levels determine the exported PX level candidates.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate and normalize Wavelet spatial reconstruction configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to legacy branch 'WAVELET'.
            %
            % cfg.applyWaveletToExternalWeightMap: stores the normalized apply wavelet to external weight map value in the module configuration.
            % cfg.applyWaveletToExternalWeightMapManualOverride: stores the normalized apply wavelet to external weight map manual override value in the module configuration.
            % cfg.batchSize: stores the normalized batch size value in the module configuration.
            % cfg.detailLevels: stores the normalized detail levels value in the module configuration.
            % cfg.levels: stores the normalized levels value in the module configuration.
            % cfg.reconstructionMode: stores the normalized reconstruction mode value in the module configuration.
            % cfg.thresholdSigma: stores the normalized threshold sigma value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            if ~report.ok, return; end
            cfg.levels = unique(round(double(cfg.levels(:)')));
            cfg.levels = cfg.levels(cfg.levels >= 1);
            if strict && isempty(cfg.levels)
                report.errors{end+1} = 'At least one positive integer wavelet decomposition level is required.';
            end
            if isfield(cfg,'detailLevels') && ~isempty(cfg.detailLevels)
                cfg.detailLevels = unique(round(double(cfg.detailLevels(:)')));
                cfg.detailLevels = cfg.detailLevels(cfg.detailLevels >= 1);
            end
            cfg.batchSize = max(1, round(double(cfg.batchSize)));
            if isfield(cfg,'thresholdSigma') && ~isempty(cfg.thresholdSigma)
                cfg.thresholdSigma = max(0, double(cfg.thresholdSigma));
            end
            if ~isfield(cfg,'applyWaveletToExternalWeightMapManualOverride') || isempty(cfg.applyWaveletToExternalWeightMapManualOverride)
                cfg.applyWaveletToExternalWeightMapManualOverride = false;
            else
                cfg.applyWaveletToExternalWeightMapManualOverride = logical(cfg.applyWaveletToExternalWeightMapManualOverride);
            end
            if ~cfg.applyWaveletToExternalWeightMapManualOverride || ...
                    ~isfield(cfg,'applyWaveletToExternalWeightMap') || isempty(cfg.applyWaveletToExternalWeightMap)
                cfg.applyWaveletToExternalWeightMap = any(strcmpi(char(cfg.reconstructionMode), {'approximation','denoised'}));
            else
                cfg.applyWaveletToExternalWeightMap = logical(cfg.applyWaveletToExternalWeightMap);
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacySubject(obj, cfg, ctx)
            % toLegacySubject  Convert wavelet spatial settings to a subject-level SPATIAL legacy step.
            %
            % Builds the WAVELET branch and resolved spatial geometry fields consumed by
            % nk_PerfSpatialChain.
            %
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.
            % cfg.legacySPATIAL: stores the normalized legacy spatial value in the module configuration.
            % cfg.levels: stores the normalized levels value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end %#ok<INUSD>
            cfg = obj.validateOrError(cfg, ctx);
            if isfield(cfg,'legacySPATIAL') && isstruct(cfg.legacySPATIAL) && ~isempty(fieldnames(cfg.legacySPATIAL))
                legacy = cfg.legacySPATIAL;
            else
                legacy = struct();
            end
            legacy.cmd = obj.Id;
            legacy.cubetype = uint8(9);
            legacy.WAVELET = obj.configToWaveletStruct(cfg);
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                PX = cfg.legacyPX;
                % The branch-defining level vector must follow the current
                % canonical config, even when an imported PX shell is retained.
                PX.opt = cfg.levels(:);
            else
                PX = obj.buildPX(cfg.levels);
            end
            legacy.PX = PX;
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Wavelet spatial reconstruction config to legacy preprocessing fields.
            %   Validates/normalizes canonical cfg and materializes legacy branch 'WAVELET' for the
            %   CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.

            legacy = obj.toLegacySubject(cfg, ctx);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy Wavelet spatial reconstruction settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            cfg.legacySPATIAL = legacy;
            if isfield(legacy,'PX') && isstruct(legacy.PX)
                cfg.legacyPX = legacy.PX;
                if isfield(legacy.PX,'opt') && ~isempty(legacy.PX.opt)
                    cfg.levels = legacy.PX.opt(:)';
                end
            end
            if isfield(legacy,'WAVELET') && isstruct(legacy.WAVELET)
                W = legacy.WAVELET;
                if isfield(W,'family'), cfg.family = char(W.family); end
                if isfield(W,'boundary'), cfg.boundary = char(W.boundary); end
                if isfield(W,'levels') && ~isempty(W.levels), cfg.levels = W.levels(:)'; end
                if isfield(W,'reconstructionMode'), cfg.reconstructionMode = char(W.reconstructionMode); end
                if isfield(W,'mode'), cfg.reconstructionMode = char(W.mode); end
                if isfield(W,'detailLevels'), cfg.detailLevels = W.detailLevels(:)'; end
                if isfield(W,'thresholdMode'), cfg.thresholdMode = char(W.thresholdMode); end
                if isfield(W,'thresholdSigma'), cfg.thresholdSigma = W.thresholdSigma; end
                if isfield(W,'batchSize'), cfg.batchSize = W.batchSize; end
                if isfield(W,'applyWaveletToExternalWeightMap')
                    cfg.applyWaveletToExternalWeightMap = logical(W.applyWaveletToExternalWeightMap);
                elseif isfield(W,'ApplyWaveletToExternalWeightMap')
                    cfg.applyWaveletToExternalWeightMap = logical(W.ApplyWaveletToExternalWeightMap);
                end
                if isfield(W,'applyWaveletToExternalWeightMapManualOverride')
                    cfg.applyWaveletToExternalWeightMapManualOverride = logical(W.applyWaveletToExternalWeightMapManualOverride);
                elseif isfield(W,'ApplyWaveletToExternalWeightMapManualOverride')
                    cfg.applyWaveletToExternalWeightMapManualOverride = logical(W.ApplyWaveletToExternalWeightMapManualOverride);
                end
            end
            cfg = obj.validateOrError(cfg, ctx);
        end


        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Fit or apply the Wavelet spatial reconstruction runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfSpatialChain,
            %   nm_preproc_spatial_param_from_context.

            % Programmatic single-step subject-spatial execution. Complex
            % multi-step subject-spatial chains should prefer
            % nm_preproc_scaffold_apply_subject_spatial, which delegates the
            % whole PREPROC.SPATIAL array to nk_PerfSpatialChain.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.
            if nargin < 5 || isempty(mode), mode = 'fit'; end %#ok<NASGU>
            if nargin < 6 || isempty(ctx), ctx = struct(); end
            cfg = struct();
            if isstruct(ctx) && isfield(ctx,'config') && isstruct(ctx.config), cfg = ctx.config; end
            if isempty(fieldnames(cfg)), cfg = obj.defaultConfig(ctx); end
            legacy = obj.toLegacySubject(cfg, ctx);
            PREPROC = struct('SPATIAL', legacy);
            Param = nm_preproc_spatial_param_from_context(Y, ctx);
            if exist('nk_PerfSpatialChain','file') ~= 2
                error([class(obj) ':missingBackend'], 'nk_PerfSpatialChain.m is required for programmatic spatial execution.');
            end
            [Yout, branchTable] = nk_PerfSpatialChain(Y, PREPROC, Param);
            trained = struct('moduleId',obj.Id, 'config',cfg, 'legacySPATIAL',legacy, ...
                'branchTable',branchTable, 'mode','deterministic_subject_spatial');
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Wavelet spatial reconstruction for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end %#ok<INUSD>
            legacy = obj.toLegacySubject(cfg, ctx);
            act = 0; aux = [];
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg, ctx)
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok, error('NMWaveletSpatialModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end

        function W = configToWaveletStruct(~, cfg)
            W = struct();
            W.family = char(cfg.family);
            W.levels = cfg.levels(:)';
            W.boundary = char(cfg.boundary);
            W.reconstructionMode = char(cfg.reconstructionMode);
            W.mode = W.reconstructionMode;
            W.detailLevels = cfg.detailLevels(:)';
            W.thresholdMode = char(cfg.thresholdMode);
            W.thresholdSigma = double(cfg.thresholdSigma);
            W.batchSize = double(cfg.batchSize);
            W.applyWaveletToExternalWeightMap = logical(cfg.applyWaveletToExternalWeightMap);
            W.applyWaveletToExternalWeightMapManualOverride = logical(cfg.applyWaveletToExternalWeightMapManualOverride);
            if strcmp(cfg.family,'heat')
                W.transform = 'undecimated_graph_heat';
                W.outputDomain = 'surface';
            else
                W.transform = 'undecimated_atrous_3d';
                W.outputDomain = 'image';
            end
        end

        function PX = buildPX(obj, levels)
            PX = [];
            if obj.functionExists('nk_AddParam')
                try
                    PX = nk_AddParam([], [], [], [], 'reset');
                    PX = nk_AddParam(levels(:), 'WaveletLevel', 0, PX, 'replace');
                    return;
                catch
                    PX = [];
                end
            end
            PX = struct('opt',levels(:));
        end
    end
end
