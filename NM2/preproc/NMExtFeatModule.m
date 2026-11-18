classdef NMExtFeatModule < NMPreprocModule
% NMExtFeatModule
% -------------------------------------------------------------------------
% Canonical adapter for the feature-ranking action step. This step consumes
% the W vector produced by an immediately preceding rankfeat step and applies
% soft weighting or hard feature extraction through nk_PerfWActObj.
% -------------------------------------------------------------------------

    methods
        function obj = NMExtFeatModule()
            % NMExtFeatModule  Construct the Feature-ranking action preprocessing adapter.
            %   Registers module id 'extfeat' with legacy branch 'W_ACT' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('extfeat','W_ACT','Feature-ranking action');
            obj.Capabilities.requiresLabels = false;
            obj.Capabilities.usesLabels = false;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.supportsHyperparameters = true;
            obj.Capabilities.supportsMissingData = true;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for Feature-ranking action.
            %   Defines editable fields for the module that extracts or weights features according
            %   to a previous feature-ranking result. The schema feeds defaultConfig,
            %   validateConfig, browser rendering, CLI/API help, and RAG documentation extraction.

            if nargin < 2, ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Apply the feature-ranking vector produced by rankfeat. ', ...
                'Supports soft weighting, percentile thresholds, absolute thresholds, top-k extraction, and operator/cutoff masks.'];

            hardExtractionActions = {'percentile_threshold','absolute_threshold','top_features','operator_cutoff'};
            fields = { ...
                struct('name','action','type','enum','default','soft_weight','label','Ranking action', ...
                    'values',{{'soft_weight','percentile_threshold','absolute_threshold','top_features','operator_cutoff'}}, ...
                    'help','Choose whether feature extraction is soft or hard. Only settings relevant to the selected action are shown.'), ...
                struct('name','exponent','type','numeric_vector','default',1,'label','Soft-weighting exponent(s)','allowEmpty',false, ...
                    'visibleIf',struct('field','action','equals','soft_weight'), ...
                    'help','Exponent(s) applied to ranking weights during soft feature weighting.'), ...
                struct('name','percentiles','type','numeric_vector','default',[25 50 75],'label','Percentile threshold(s)','allowEmpty',false, ...
                    'visibleIf',struct('field','action','equals','percentile_threshold'), ...
                    'help','Ranking percentile threshold candidates for hard feature extraction.'), ...
                struct('name','absoluteThresholds','type','numeric_vector','default',[0.25 0.50 0.75],'label','Absolute threshold(s)','allowEmpty',false, ...
                    'visibleIf',struct('field','action','equals','absolute_threshold'), ...
                    'help','Absolute ranking-weight cutoff candidates for hard feature extraction.'), ...
                struct('name','topFeatures','type','numeric_vector','default',10:10:100,'label','Top feature count(s)','allowEmpty',false, ...
                    'visibleIf',struct('field','action','equals','top_features'), ...
                    'help','Number(s) of highest-ranked features retained in top-feature selection.'), ...
                struct('name','operator','type','enum','default','>=','label','Operator','values',{{'>=','>','<=','<','~='}}, ...
                    'visibleIf',struct('field','action','equals','operator_cutoff'), ...
                    'help','Comparison operator applied to ranking weights in operator/cutoff selection.'), ...
                struct('name','cutoff','type','numeric_vector','default',0,'label','Operator cutoff(s)','allowEmpty',false, ...
                    'visibleIf',struct('field','action','equals','operator_cutoff'), ...
                    'help','Ranking-weight cutoff candidate(s) paired with the selected comparison operator.') };

            if isstruct(ctx) && isfield(ctx,'isImaging') && isequal(ctx.isImaging,true)
                fields{end+1} = struct('name','clusterize','type','boolean','default',false, ...
                    'label','Clusterize suprathreshold imaging features', ...
                    'visibleIf',struct('field','action','in',{hardExtractionActions}), ...
                    'help','Available only for hard feature-extraction actions.');
            end

            fields{end+1} = struct('name','legacyW_ACT','type','struct','default',struct(), ...
                'label','Raw legacy W_ACT structure','uiHidden',true, ...
                    'help','Imported feature-weight action settings retained for legacy round trips.');
            fields{end+1} = struct('name','legacyPX','type','struct','default',struct(), ...
                'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Imported PX optimization values retained for legacy threshold/candidate round trips.');
            spec.fields = fields;
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Convert Feature-ranking action config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'W_ACT' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.absoluteThresholds: stores the normalized absolute thresholds value in the module configuration.
            % cfg.action: stores the normalized action value in the module configuration.
            % cfg.clusterize: stores the normalized clusterize value in the module configuration.
            % cfg.cutoff: stores the normalized cutoff value in the module configuration.
            % cfg.exponent: stores the normalized exponent value in the module configuration.
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.
            % cfg.legacyW_ACT: stores the normalized legacy w act value in the module configuration.
            % cfg.operator: stores the normalized operator value in the module configuration.
            % cfg.percentiles: stores the normalized percentiles value in the module configuration.
            % cfg.topFeatures: stores the normalized top features value in the module configuration.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end %#ok<INUSD>
            cfg = obj.parseConfig(cfg);

            if isfield(cfg,'legacyW_ACT') && isstruct(cfg.legacyW_ACT) && ~isempty(fieldnames(cfg.legacyW_ACT))
                W_ACT = cfg.legacyW_ACT;
            else
                W_ACT = struct();
            end
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                PX = cfg.legacyPX;
            else
                PX = [];
            end

            W_ACT.softflag = obj.actionCode(cfg.action);
            W_ACT.exponent = cfg.exponent;
            W_ACT.threshvec = cfg.percentiles;
            W_ACT.absvec = cfg.absoluteThresholds;
            W_ACT.topfeats = cfg.topFeatures;
            W_ACT.operator = obj.operatorHandle(cfg.operator);
            W_ACT.cutoff = cfg.cutoff;
            if isfield(cfg,'clusterize') && cfg.clusterize, W_ACT.clustflag = 1; else, W_ACT.clustflag = 2; end

            [PX, W_ACT] = obj.ensurePX(PX, W_ACT);
            legacy = struct('cmd',obj.Id,'W_ACT',W_ACT);
            if ~isempty(PX), legacy.PX = PX; end
        end

        function cfg = fromLegacy(obj, legacy, ctx) %#ok<INUSD>
            % fromLegacy  Import legacy Feature-ranking action settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            cfg = obj.defaultConfig();
            if isempty(legacy), return; end
            if isfield(legacy,'W_ACT'), W_ACT = legacy.W_ACT; else, W_ACT = legacy; end
            cfg.legacyW_ACT = W_ACT;
            if isfield(legacy,'PX') && isstruct(legacy.PX) && ~isempty(legacy.PX)
                cfg.legacyPX = legacy.PX;
            else
                % Older NM configurations may contain PX = [] for action
                % steps without an active hyperparameter shelf. Keep the
                % canonical hidden field structurally valid during import.
                cfg.legacyPX = struct();
            end

            if isfield(W_ACT,'softflag'), cfg.action = obj.actionName(W_ACT.softflag); end
            if isfield(W_ACT,'exponent'), cfg.exponent = W_ACT.exponent; end
            if isfield(W_ACT,'threshvec'), cfg.percentiles = W_ACT.threshvec; end
            if isfield(W_ACT,'absvec'), cfg.absoluteThresholds = W_ACT.absvec; end
            if isfield(W_ACT,'topfeats'), cfg.topFeatures = W_ACT.topfeats; end
            if isfield(W_ACT,'cutoff'), cfg.cutoff = W_ACT.cutoff; end
            if isfield(W_ACT,'operator'), cfg.operator = obj.operatorName(W_ACT.operator); end
            if isfield(W_ACT,'clustflag'), cfg.clusterize = W_ACT.clustflag == 1; end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure Feature-ranking action for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('nk_WAction_config')
                [NM, varind] = obj.resolveNM(ctx);
                if isempty(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < varind
                    error('NMExtFeatModule:noNM', ...
                        'Legacy extfeat CLI configuration requires ctx.NM from NMPreprocContext.');
                end
                datadesc = NM.datadescriptor{varind};
                brainmask = [];
                if isfield(ctx,'brainmask'), brainmask = ctx.brainmask; end
                parentstr = obj.getParentString(ctx);
                [legacy.W_ACT, PX] = nk_WAction_config(legacy.W_ACT, obj.getLegacyPX(legacy), datadesc, brainmask, [], parentstr);
                if ~isempty(PX), legacy.PX = PX; elseif isfield(legacy,'PX'), legacy = rmfield(legacy,'PX'); end
                legacy.cmd = obj.Id;
                cfg = obj.fromLegacy(legacy, ctx);
                act = 0;
            else
                act = 0;
            end
        end

        function [Yout, trained] = execute(obj, Y, trained, mode, ctx)
            % execute  Fit or apply the Feature-ranking action runtime transform.
            %   Uses ctx.config when supplied, translates it to legacy settings, and delegates
            %   fit/transform to the legacy backend while returning Yout and trained state. Direct
            %   execution/configuration path references nk_PerfWActObj.
            %
            % ctx.config: canonical module configuration consumed for programmatic execution; it is converted to the corresponding legacy parameter struct before the backend is called.

            if nargin < 5 || isempty(ctx), ctx = struct(); end
            if nargin < 4 || isempty(mode), mode = 'fit'; end
            switch lower(char(mode))
                case 'fit'
                    cfg = obj.defaultConfig();
                    if isfield(ctx,'config'), cfg = ctx.config; end
                    legacy = obj.toLegacy(cfg, ctx);
                    IN = obj.legacyToRuntime(legacy);
                    IN.W = obj.previousRankingWeights(ctx);
                    [Yout, trained] = nk_PerfWActObj(Y, IN);
                case 'transform'
                    if isempty(trained)
                        error('NMExtFeatModule:noTrained','extfeat transform requires trained W_ACT parameters.');
                    end
                    [Yout, trained] = nk_PerfWActObj(Y, trained);
                otherwise
                    error('NMExtFeatModule:badMode','Unknown execution mode: %s', char(mode));
            end
        end
    end

    methods (Access = private)
        function code = actionCode(~, action)
            switch lower(char(action))
                case 'soft_weight', code = 1;
                case 'percentile_threshold', code = 2;
                case 'absolute_threshold', code = 3;
                case 'top_features', code = 4;
                case 'operator_cutoff', code = 5;
                otherwise, code = 1;
            end
        end

        function action = actionName(~, code)
            switch code
                case 2, action = 'percentile_threshold';
                case 3, action = 'absolute_threshold';
                case 4, action = 'top_features';
                case 5, action = 'operator_cutoff';
                otherwise, action = 'soft_weight';
            end
        end

        function fh = operatorHandle(~, op)
            switch char(op)
                case '>',  fh = @gt;
                case '<=', fh = @le;
                case '<',  fh = @lt;
                case '~=', fh = @ne;
                otherwise, fh = @ge;
            end
        end

        function op = operatorName(~, fh)
            if isa(fh,'function_handle'), nm = func2str(fh); else, nm = char(fh); end
            switch nm
                case {'gt','>'},  op = '>';
                case {'le','<='}, op = '<=';
                case {'lt','<'},  op = '<';
                case {'ne','~='}, op = '~=';
                otherwise, op = '>=';
            end
        end

        function [PX, W_ACT] = ensurePX(obj, PX, W_ACT)
            % Mirrors nk_WAction_config. This PX shelf determines how
            % feature extraction / weighting actions are ramified later in
            % nk_PerfPreprocessingCore_obj; therefore it must be generated
            % through nk_AddParam and must not be fabricated manually.
            switch W_ACT.softflag
                case 1
                    vals = W_ACT.exponent; desc = 'ExpMult';
                case 2
                    vals = W_ACT.threshvec; desc = 'Thresholds';
                case 3
                    vals = W_ACT.absvec; desc = 'Absolute thresholds';
                case 4
                    vals = W_ACT.topfeats; desc = 'Top feats';
                case 5
                    vals = W_ACT.cutoff; desc = 'Cutoffs';
                otherwise
                    vals = 1; desc = 'ExpMult';
            end
            PX = obj.pxAdd([], [], [], 1, 'reset');
            PX = obj.pxAdd(PX, vals, desc, 1);
            W_ACT.opt = PX.opt;
            if isfield(PX,'Px') && isfield(PX.Px,'Params_desc')
                W_ACT.Params_desc = PX.Px.Params_desc;
            end
        end

        function IN = legacyToRuntime(obj, legacy)
            IN = struct();
            IN.W_ACT = legacy.W_ACT;
            if isfield(legacy,'PX')
                [~, IN.W_ACT] = obj.ensurePX(legacy.PX, IN.W_ACT);
            else
                [~, IN.W_ACT] = obj.ensurePX([], IN.W_ACT);
            end
            if isfield(IN.W_ACT,'brainmask'), IN.Mask = IN.W_ACT.brainmask; end
        end

        function W = previousRankingWeights(~, ctx)
            W = [];
            if isstruct(ctx) && isfield(ctx,'previousTrainedSteps') && ~isempty(ctx.previousTrainedSteps)
                pts = ctx.previousTrainedSteps;
                if iscell(pts), last = pts{end}; else, last = pts(end); end
                if isstruct(last) && isfield(last,'trained') && isfield(last.trained,'W')
                    W = last.trained.W;
                elseif isstruct(last) && isfield(last,'W')
                    W = last.W;
                end
            end
            if isempty(W) && isstruct(ctx) && isfield(ctx,'rankWeights')
                W = ctx.rankWeights;
            end
            if isempty(W)
                error('NMExtFeatModule:noWeights','extfeat requires weights from the immediately preceding rankfeat step.');
            end
        end

        function [NMout, varind] = resolveNM(~, ctx)
            NMout = []; varind = 1;
            if isstruct(ctx)
                if isfield(ctx,'NM'), NMout = ctx.NM; end
                if isfield(ctx,'varind') && ~isempty(ctx.varind), varind = ctx.varind; end
            end
        end

        function PX = getLegacyPX(~, legacy)
            if isfield(legacy,'PX'), PX = legacy.PX; else, PX = []; end
        end

        function cfg = validateOrError(obj, cfg)
            if isfield(cfg,'legacyPX') && isempty(cfg.legacyPX) && ~isstruct(cfg.legacyPX)
                cfg.legacyPX = struct();
            end
            if isfield(cfg,'legacyW_ACT') && isempty(cfg.legacyW_ACT) && ~isstruct(cfg.legacyW_ACT)
                cfg.legacyW_ACT = struct();
            end
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMExtFeatModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end
    end
end
