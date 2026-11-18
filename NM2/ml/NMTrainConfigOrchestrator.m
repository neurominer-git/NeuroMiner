classdef NMTrainConfigOrchestrator < handle
% NMTrainConfigOrchestrator
% -------------------------------------------------------------------------
% Thin integration boundary between modular configuration objects and the
% legacy NM.TrainParam structure. The class is intentionally small: it does
% not own preprocessing, CV, RFE, or UI state yet. Its current purpose is to
% insert/extract the modular ML configuration without changing the backend
% contract consumed by nk_MLOptimizer*.
% -------------------------------------------------------------------------

    properties
        NM = struct()          % lightweight ML context view, not the full project struct
        ML
        MLConfig = struct()
        VarIndex = []
        UseLateFusion = false
        ModeFlag char = 'classification'
        Time = []
    end

    methods (Static)
        function obj = fromNM(NM, varind, ctx)
        % fromNM  Create an ML configuration orchestrator from an existing NM project struct.
        %   Extracts a lightweight ML context, detects root-vs-late-fusion TrainParam placement via varind,
        %   imports existing SVM/GRD into MLConfig when present, or creates defaults otherwise. This is the
        %   main power-user entry point for editing ML settings programmatically.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2, varind = []; end
            if nargin < 3, ctx = struct(); end
            obj = NMTrainConfigOrchestrator();
            obj.NM = obj.lightNMForMLContext(NM);
            obj.ML = NMMLModule();
            obj.VarIndex = varind;
            obj.ModeFlag = obj.NM.modeflag;
            if isfield(obj.NM,'time'), obj.Time = obj.NM.time; end
            ctx = obj.contextFromNM(NM, ctx);

            [SVM, GRD, useLF] = obj.extractLegacyML(NM, varind);
            obj.UseLateFusion = useLF;
            if ~isempty(fieldnames(SVM)) || ~isempty(fieldnames(GRD))
                obj.MLConfig = obj.ML.fromLegacy(SVM, GRD, ctx);
            else
                obj.MLConfig = obj.ML.defaultConfig(ctx);
            end
        end


        function [SVM, GRD, MLConfig] = defaultSetting(NM, varind, ctx)
        % defaultSetting  Return default legacy SVM/GRD and modular MLConfig for an NM context.
        %   Provides the public non-interactive default path for the main ML branch; outputs are suitable
        %   for NM.TrainParam insertion and mirror the defaults produced by NMMLModule.defaultConfig/toLegacy.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2, varind = []; end %#ok<NASGU>
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            obj = NMTrainConfigOrchestrator();
            obj.NM = obj.lightNMForMLContext(NM);
            obj.ModeFlag = obj.NM.modeflag;
            if isfield(obj.NM,'time'), obj.Time = obj.NM.time; end
            ctx = obj.contextFromNM(NM, ctx);
            MLConfig = obj.ML.defaultConfig(ctx);
            [SVM, GRD] = obj.ML.toLegacy(MLConfig, ctx);
        end
    end

    methods
        function obj = NMTrainConfigOrchestrator()
        % NMTrainConfigOrchestrator  Construct an empty ML TrainParam integration object.
        %   Initializes the contained NMMLModule but does not inspect or modify NM until fromNM, toNM, or
        %   context-dependent methods are called.

            obj.ML = NMMLModule();
        end

        function ctx = context(obj, ctx)
        % context  Return an ML context struct derived from the orchestrator light NM view.
        %   Ensures ctx.NM, ctx.modeflag, and optional ctx.time are present before calls into NMMLModule
        %   or learner metadata factories.

            if nargin < 2, ctx = struct(); end
            ctx = obj.contextFromNM(obj.NM, ctx);
        end


        function [obj, report] = cli_configure(obj, varargin)
        % cli_configure  Configure the current MLConfig through the non-interactive ML module path.
        %   Optionally merges an existing config struct and Context name/value argument, then validates and
        %   exports legacy SVM/GRD into report fields. Exceptions are returned through the report object.

            report = NMConfigureAPITools.report(true, 'ML branch configured.');
            cfg = obj.MLConfig;
            ctx = struct();
            if ~isempty(varargin) && (isempty(varargin{1}) || isstruct(varargin{1}))
                if isstruct(varargin{1}), cfg = NMConfigureAPITools.mergeStruct(cfg, varargin{1}); end
                varargin = varargin(2:end);
            end
            ctx = NMConfigureAPITools.optionValue(varargin, 'Context', ctx);
            try
                ctx = obj.context(ctx);
                [cfg, legacy, act, aux] = obj.ML.cli_configure(cfg, ctx); %#ok<ASGLU>
                obj.MLConfig = cfg;
                report.legacy = legacy;
                report.aux = aux;
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function h = cli_configureHelp(obj) %#ok<MANU>
        % cli_configureHelp  Return structured help for orchestrator-level ML configuration.
        %   Documents how to call cli_configure after fromNM and is intended for CLI users, API scripts,
        %   and future assistant/RAG documentation.

            opts = struct();
            opts.existingMLConfig = 'Optional existing MLConfig struct; name/value modifications are currently passed to the contained NMMLModule where supported.';
            opts.Context = 'Optional ML context struct.';
            h = NMConfigureAPITools.helpStruct('NMTrainConfigOrchestrator.cli_configure', ...
                '[mlOrch, report] = mlOrch.cli_configure(existingMLConfig, ''Context'', ctx)', opts, ...
                {'ml = NMTrainConfigOrchestrator.fromNM(NM, [], ctx); [ml, rep] = ml.cli_configure(mlConfig, ''Context'', ctx);'});
        end


        function [SVM, GRD] = toLegacyML(obj, ctx)
        % toLegacyML  Export the orchestrator MLConfig to legacy SVM and GRD structs.
        %   Applies the current NM-derived context and delegates to NMMLModule.toLegacy without mutating NM;
        %   useful for inspection or tests before committing settings with toNM.

            if nargin < 2, ctx = struct(); end
            ctx = obj.context(ctx);
            [SVM, GRD] = obj.ML.toLegacy(obj.MLConfig, ctx);
        end

        function NM = toNM(obj, NM, ctx)
        % toNM  Write the orchestrator MLConfig back into the supplied NM.TrainParam structure.
        %   Exports SVM/GRD and stores them either in TrainParam.SVM/GRD or in TrainParam.STRAT{varind}
        %   for late fusion. The method updates only ML TrainParam branches and refreshes the internal
        %   lightweight context after insertion.

            if nargin < 2 || isempty(NM), NM = obj.NM; end
            if nargin < 3, ctx = struct(); end
            ctx = obj.contextFromNM(NM, ctx);
            [SVM, GRD] = obj.ML.toLegacy(obj.MLConfig, ctx);

            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam)
                NM.TrainParam = struct();
            end
            useLF = obj.shouldUseLateFusion(NM, obj.VarIndex);
            if useLF
                varind = obj.VarIndex;
                if isempty(varind) || varind < 1
                    error('NMTrainConfigOrchestrator:missingVarIndex', ...
                        'Late-fusion export requires a positive VarIndex.');
                end
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1,varind);
                elseif numel(NM.TrainParam.STRAT) < varind
                    NM.TrainParam.STRAT{varind} = struct();
                end
                if isempty(NM.TrainParam.STRAT{varind}) || ~isstruct(NM.TrainParam.STRAT{varind})
                    NM.TrainParam.STRAT{varind} = struct();
                end
                NM.TrainParam.STRAT{varind}.SVM = SVM;
                NM.TrainParam.STRAT{varind}.GRD = GRD;
            else
                NM.TrainParam.SVM = SVM;
                NM.TrainParam.GRD = GRD;
            end
            obj.NM = obj.lightNMForMLContext(NM);
            obj.ModeFlag = obj.NM.modeflag;
            if isfield(obj.NM,'time'), obj.Time = obj.NM.time; end
            obj.UseLateFusion = useLF;
        end

        function obj = setAlgorithm(obj, algorithm, ctx)
        % setAlgorithm  Switch the orchestrator MLConfig to a different learner.
        %   Delegates to NMMLModule.setAlgorithm with the current context, preserving compatible criterion
        %   and legacy round-trip fields according to the module rules.

            if nargin < 3, ctx = struct(); end
            ctx = obj.context(ctx);
            obj.MLConfig = obj.ML.setAlgorithm(obj.MLConfig, algorithm, ctx);
        end

        function ui = ui_configure(obj, ctx)
        % ui_configure  Return UI-ready ML schema/state/visibility for the orchestrator config.
        %   Delegates to NMMLModule.ui_configure using the current NM-derived context; no NM mutation or
        %   backend training is performed.

            if nargin < 2, ctx = struct(); end
            ctx = obj.context(ctx);
            ui = obj.ML.ui_configure(obj.MLConfig, ctx);
        end

        function paths = exportUI(obj, outDir, ctx)
        % exportUI  Export browser-editable ML configuration artifacts for this orchestrator.
        %   Delegates packaging to NMTrainConfigUI.export while keeping this class as the TrainParam/MLConfig
        %   integration boundary.

            if nargin < 3, ctx = struct(); end
            paths = NMTrainConfigUI.export(obj, outDir, ctx);
        end

        function obj = importUpdatedUI(obj, updatedPath, ctx)
        % importUpdatedUI  Import a browser-updated ML configuration into this orchestrator.
        %   Delegates parsing/validation to NMTrainConfigUI.importUpdated and returns the updated object so
        %   callers can subsequently inspect or commit the MLConfig with toNM.

            if nargin < 3, ctx = struct(); end
            obj = NMTrainConfigUI.importUpdated(obj, updatedPath, ctx);
        end

        function obj = openUI(obj, outDir, ctx, port)
        % openUI  Open the browser ML configuration UI for this orchestrator.
        %   Delegates to NMTrainConfigUI.open with optional output directory, context, and port; the actual
        %   TrainParam write-back still occurs through importUpdatedUI/toNM rather than through this call alone.

            if nargin < 2, outDir = []; end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            obj = NMTrainConfigUI.open(obj, outDir, ctx, port);
        end
    end

    methods (Access = private)
        function [SVM, GRD, useLF] = extractLegacyML(obj, NM, varind) %#ok<INUSL>
            SVM = struct();
            GRD = struct();
            useLF = false;
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            useLF = obj.shouldUseLateFusion(NM, varind);
            if useLF
                if isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && isstruct(TP.STRAT{varind})
                    st = TP.STRAT{varind};
                    if isfield(st,'SVM') && isstruct(st.SVM), SVM = st.SVM; end
                    if isfield(st,'GRD') && isstruct(st.GRD), GRD = st.GRD; end
                end
            else
                if isfield(TP,'SVM') && isstruct(TP.SVM), SVM = TP.SVM; end
                if isfield(TP,'GRD') && isstruct(TP.GRD), GRD = TP.GRD; end
            end
        end

        function tf = shouldUseLateFusion(obj, NM, varind) %#ok<INUSL>
            tf = false;
            if isempty(varind), return; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if isfield(TP,'FUSION') && isstruct(TP.FUSION) && isfield(TP.FUSION,'flag') && isequal(TP.FUSION.flag,3)
                tf = true;
            end
        end

        function ctx = contextFromNM(obj, NM, ctx)
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            lite = obj.lightNMForMLContext(NM);
            ctx.NM = lite;
            ctx.modeflag = lite.modeflag;
            if isfield(lite,'time'), ctx.time = lite.time; end
        end

        function lite = lightNMForMLContext(obj, NM) %#ok<INUSL>
            lite = struct();
            if isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                lite.modeflag = NMAlternativeLabelTools.effectiveMode(NM);
            else
                lite.modeflag = obj.ModeFlag;
            end
            if isstruct(NM) && isfield(NM,'time') && ~isempty(NM.time)
                lite.time = NM.time;
            elseif ~isempty(obj.Time)
                lite.time = obj.Time;
            end
        end
    end
end
