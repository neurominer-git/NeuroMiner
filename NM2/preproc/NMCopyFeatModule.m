classdef NMCopyFeatModule < NMPreprocModule
% Minimal adapter for copyfeat. It primarily marks a sequence operation.

    methods
        function obj = NMCopyFeatModule()
            % NMCopyFeatModule  Construct the Copy features preprocessing adapter.
            %   Registers module id 'copyfeat' with command-specific legacy fields and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('copyfeat','','Copy features');
            obj.Capabilities.trainFoldEstimated = false;
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Copy features.
            %   Defines editable fields for the module that copies the current feature matrix into
            %   the legacy preprocessing stream for later reuse. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Copy the current feature matrix for later reuse in the preprocessing pipeline.';
            spec.fields = { struct('name','label','type','string','default','copy','label','Copy label', ...
                    'help','Name attached to the copied feature matrix for subsequent pipeline use.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Copy features config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes command-specific legacy fields
            % for the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.label: stores the normalized label value in the module configuration.

            cfg = obj.parseConfig(cfg);
            legacy = struct('cmd',obj.Id,'label',cfg.label);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Copy features for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx);
            act = 0;
            aux = [];
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Copy features settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'label'), cfg.label = legacy.label; end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Execute the no-op feature-copy adapter.
            %   Returns the input feature matrix unchanged while preserving the trained-state shape
            %   expected by modular fit/transform smoke tests.

            Yout = Y;
            if nargin < 3 || isempty(trained), trained = struct(); end
        end
    end
end
