classdef NMLegacyPreprocModule < NMPreprocModule
% NMLegacyPreprocModule
% -------------------------------------------------------------------------
% Placeholder for preprocessing modules whose dependency grammar is already
% known but whose canonical configurator/execution adapter has not yet been
% ported. Imported legacy ACTPARAM structs are preserved exactly.
% -------------------------------------------------------------------------

    properties (Access = private)
        HelpText char = ''
    end

    methods
        function obj = NMLegacyPreprocModule(id, displayName, helpText)
            % NMLegacyPreprocModule  Construct a raw-preservation adapter for an unported legacy command.
            %   Uses the caller-supplied id/display name and stores raw ACTPARAM payloads so
            %   not-yet-ported preprocessing steps remain visible, editable as raw structs, and
            %   round-trippable through NMPreprocSequence without implying full modular support.


            if nargin < 2 || isempty(displayName), displayName = id; end
            if nargin < 3, helpText = ''; end
            obj@NMPreprocModule(id,'',displayName);
            obj.HelpText = helpText;
            obj.Capabilities.legacyBackend = true;
            obj.Capabilities.trainFoldEstimated = true;
            obj.Capabilities.supportsMissingData = true;
            obj.Capabilities.changesFeatureSpace = any(strcmp(id, {'extfeat','extdim','reducedim','remvarcomp','elimzero','JuSpace','ROImeans','graphMetrics','graphSparsity','graphComputation'}));
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for NMLegacyPreprocModule.
            %   Defines editable fields for the module that preserves unported legacy ACTPARAM steps
            %   as raw preprocessing branches. The schema feeds defaultConfig, validateConfig,
            %   browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = obj.HelpText;
            if isempty(spec.description)
                spec.description = sprintf('%s is an imported compatibility step. Its stored settings are preserved, but this configurator does not expose editable options for this step.', obj.DisplayName);
            end
            spec.fields = {};
            spec.unported = true;
        end

        function cfg = defaultConfig(obj, ctx) %#ok<INUSD>
            % defaultConfig  Return default canonical config for NMLegacyPreprocModule.
            %   Creates the raw-preservation or schema-derived defaults that scripts and legacy
            %   import use before validation and command-specific legacy fields export.

            cfg = struct('rawLegacy',struct('cmd',obj.Id));
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict) %#ok<INUSD>
            % validateConfig  Validate and normalize NMLegacyPreprocModule configuration.
            %
            % Checks canonical config fields and nested method settings before scripted use,
            % UI-state application, and legacy conversion to command-specific legacy fields.
            %
            % cfg.rawLegacy: preserves the original legacy configuration fragment for compatibility/audit use.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if ~isstruct(cfg), cfg = obj.defaultConfig(); end
            if ~isfield(cfg,'rawLegacy') || isempty(cfg.rawLegacy)
                cfg.rawLegacy = struct('cmd',obj.Id);
            end
            if ~isstruct(cfg.rawLegacy)
                report = struct('ok',false,'errors',{{'rawLegacy must be a struct.'}},'warnings',{{}});
                return;
            end
            if ~isfield(cfg.rawLegacy,'cmd') || isempty(cfg.rawLegacy.cmd)
                cfg.rawLegacy.cmd = obj.Id;
            end
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert NMLegacyPreprocModule config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes command-specific legacy fields
            % for the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.rawLegacy: preserves the original legacy configuration fragment for compatibility/audit use.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if isstruct(cfg) && isfield(cfg,'rawLegacy') && isstruct(cfg.rawLegacy)
                legacy = cfg.rawLegacy;
            else
                legacy = struct('cmd',obj.Id);
            end
            if ~isfield(legacy,'cmd') || isempty(legacy.cmd), legacy.cmd = obj.Id; end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy NMLegacyPreprocModule settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 2 || isempty(legacy), legacy = struct('cmd',obj.Id); end
            if ~isfield(legacy,'cmd') || isempty(legacy.cmd), legacy.cmd = obj.Id; end
            cfg = struct('rawLegacy',legacy);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure NMLegacyPreprocModule for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end %#ok<NASGU>
            legacy = obj.toLegacy(cfg, ctx);
            act = 0;
            aux = [];
            warning('NMLegacyPreprocModule:unportedCLI', ...
                'The canonical CLI configurator for %s has not yet been ported. Existing raw legacy configuration is preserved.', obj.Id);
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Report unsupported direct execution for NMLegacyPreprocModule.
            %   Configuration and legacy export are available, but this module intentionally leaves
            %   numerical execution to the full legacy preprocessing scaffold rather than the
            %   single-step smoke path.

            error('NMLegacyPreprocModule:notPorted', ...
                'Direct execution for legacy placeholder module %s is not implemented in the modular smoke-gun layer.', obj.Id);
        end
    end
end
