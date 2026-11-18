classdef NMDiscSymModule < NMPreprocModule
% Canonical adapter for NeuroMiner discretize/symbolize preprocessing.

    methods
        function obj = NMDiscSymModule()
            % NMDiscSymModule  Construct the Discretize / symbolize preprocessing adapter.
            %   Registers module id 'discsym' with command-specific legacy fields and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('discsym','','Discretize / symbolize');
            obj.Aliases = {'discretize','symbolize'};
        end

        function spec = configSpec(obj, ctx) %#ok<INUSD>
            % configSpec  Return the canonical API/UI schema for Discretize / symbolize.
            %   Defines editable fields for the module that discretizes or symbolizes continuous
            %   predictors through the legacy preprocessing engine. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = 'Discretize or symbolize features before model fitting.';
            spec.fields = { ...
                struct('name','mode','type','enum','default','discretize','label','Mode','values',{{'discretize','symbolize'}}, ...
                    'help','Discretize using binStart/binStep/binStop, or symbolize using the symbolization parameters.'), ...
                struct('name','binStart','type','number','default',0,'label','Discretization bin start', ...
                    'help','Lower starting value for the discretization bin grid.'), ...
                struct('name','binStep','type','number','default',0.5,'min',eps,'label','Discretization bin step', ...
                    'help','Positive spacing between consecutive discretization bins.'), ...
                struct('name','binStop','type','number','default',4,'label','Discretization bin stop', ...
                    'help','Upper stopping value for the discretization bin grid.'), ...
                struct('name','symbolMinBin','type','integer','default',3,'min',2,'label','Symbolization minimum bins', ...
                    'help','Minimum candidate number of bins for the symbolization procedure.'), ...
                struct('name','symbolMaxBin','type','integer','default',25,'min',2,'label','Symbolization maximum bins', ...
                    'help','Maximum candidate number of bins for the symbolization procedure.'), ...
                struct('name','symbolSeqLength','type','integer','default',4,'min',1,'label','Symbolization sequence length', ...
                    'help','Length of the symbol sequence used by the symbolization procedure.'), ...
                struct('name','symbolStdNum','type','number','default',3,'min',0,'label','Symbolization STD range', ...
                    'help','Standard-deviation range parameter passed to the symbolization procedure.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert Discretize / symbolize config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes command-specific legacy fields
            % for the CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.binStart: stores the normalized bin start value in the module configuration.
            % cfg.binStep: stores the normalized bin step value in the module configuration.
            % cfg.binStop: stores the normalized bin stop value in the module configuration.
            % cfg.mode: stores the normalized mode value in the module configuration.
            % cfg.symbolMaxBin: stores the normalized symbol max bin value in the module configuration.
            % cfg.symbolMinBin: stores the normalized symbol min bin value in the module configuration.
            % cfg.symbolSeqLength: stores the normalized symbol seq length value in the module configuration.
            % cfg.symbolStdNum: stores the normalized symbol std num value in the module configuration.

            cfg = obj.parseConfig(cfg);
            legacy = struct();
            legacy.cmd = cfg.mode;
            if strcmpi(cfg.mode,'discretize')
                legacy.DISCRET = struct('binstart',cfg.binStart,'binsteps',cfg.binStep,'binstop',cfg.binStop);
            else
                legacy.SYMBOL = struct('symMinBin',cfg.symbolMinBin,'symMaxBin',cfg.symbolMaxBin, ...
                    'symSeqLength',cfg.symbolSeqLength,'symStdNum',cfg.symbolStdNum);
            end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Discretize / symbolize settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isfield(legacy,'cmd'), cfg.mode = legacy.cmd; end
            if isfield(legacy,'DISCRET')
                cfg.mode = 'discretize'; D = legacy.DISCRET;
                if isfield(D,'binstart'), cfg.binStart = D.binstart; end
                if isfield(D,'binsteps'), cfg.binStep = D.binsteps; end
                if isfield(D,'binstop'), cfg.binStop = D.binstop; end
            end
            if isfield(legacy,'SYMBOL')
                cfg.mode = 'symbolize'; S = legacy.SYMBOL;
                if isfield(S,'symMinBin'), cfg.symbolMinBin = S.symMinBin; end
                if isfield(S,'symMaxBin'), cfg.symbolMaxBin = S.symMaxBin; end
                if isfield(S,'symSeqLength'), cfg.symbolSeqLength = S.symSeqLength; end
                if isfield(S,'symStdNum'), cfg.symbolStdNum = S.symStdNum; end
            end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Discretize / symbolize for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_DiscSym_config')
                [legacy, act] = nk_DiscSym_config(legacy, obj.getParentString(ctx));
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx) %#ok<INUSD>
            % execute  Report unsupported direct execution for Discretize / symbolize.
            %   Configuration and legacy export are available, but this module intentionally leaves
            %   numerical execution to the full legacy preprocessing scaffold rather than the
            %   single-step smoke path.

            error('NMDiscSymModule:executionNotSmokeTested', ...
                ['Direct execution for discretize/symbolize is not enabled in the smoking-gun slice because the legacy ', ...
                 'backend expects function handles installed by nk_GenPreprocSequence. Legacy export/configuration is available.']);
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMDiscSymModule:invalidConfig','%s',strjoin(report.errors,newline)); end
            if strcmpi(cfg.mode,'discretize') && cfg.binStop <= cfg.binStart
                error('NMDiscSymModule:invalidConfig','binStop must be larger than binStart.');
            end
            if strcmpi(cfg.mode,'symbolize') && cfg.symbolMaxBin < cfg.symbolMinBin
                error('NMDiscSymModule:invalidConfig','symbolMaxBin must be >= symbolMinBin.');
            end
        end
    end
end
