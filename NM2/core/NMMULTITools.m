classdef NMMULTITools
% NMMULTITools
% -------------------------------------------------------------------------
% Browser-port helper for nk_Multi_config.m.  This helper keeps UI-only
% fields out of NM.TrainParam.MULTI and writes only the legacy MULTI struct.
% The configurator is available only for classification problems with more
% than two non-missing classes in the effective label vector.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        MethodChoices = struct( ...
            'symbol', {'pairwise','ecoc','dag'}, ...
            'code', {1,2,3}, ...
            'description', {'Pairwise maximum-wins decoding','Error-correcting output codes','Directed acyclic graph'})
        DecodingChoices = struct( ...
            'symbol', {'hamming','euclidean','laplacian','attenuated_euclidean','linear_loss'}, ...
            'code', {1,2,3,4,5}, ...
            'description', {'Hamming distance','Euclidean distance','Laplacian decoding','Attenuated Euclidean distance','Linear loss-based decoding'})
        CodingChoices = struct('symbol',{'fixed'},'code',{1}, ...
            'description',{'Inherited fixed multiclass coding convention'})
        DecisionChoices = struct( ...
            'symbol', {'sum','mean','product','majority','median'}, ...
            'code', {1,2,3,4,5}, ...
            'description', {'Sum of decision values','Mean of decision values','Product of decision values','Majority vote','Median of decision values'})
    end

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the multi-class branch.
            %
            % Merges canonical state/name-value inputs with stateFromNM, normalizes and materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the established target NM.TrainParam.MULTI and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            varind = NMConfigureAPITools.optionValue(varargin, 'VarIndex', 1);
            fusionFlag = NMConfigureAPITools.optionValue(varargin, 'FusionFlag', []);
            if isempty(fusionFlag), fusionFlag = NMFusionStateTools.flagFromNM(NM); end
            defaultState = NMMULTITools.stateFromNM(NM, varind, fusionFlag);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {'VarIndex','FusionFlag'}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.multiDirty = true; end
            try
                state = NMConfigureAPITools.normalizeChoices(state, NMMULTITools.apiChoices(), 'MATLAB:assertion:failed');
                state = NMMULTITools.normalizeState(NM, state, varind, fusionFlag);
                NM = NMMULTITools.applyToNM(NM, state, varind, fusionFlag);
                if isempty(report.message), report.message = 'NMMULTITools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public multi-class configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMMULTITools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted multi-class configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.MULTI. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.VarIndex = 'Modality/strategy index where applicable.';
            opts.FusionFlag = 'Fusion flag where applicable.';
            h = NMConfigureAPITools.helpStruct('NMMULTITools.cli_configure', ...
                '[NM, state, report] = NMMULTITools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMMULTITools.configure(NM, ''multiMethod'',''ecoc'', ''multiDecoding'',''hamming'');'}, NMMULTITools.apiChoices());
            h.validationRules = {'MULTI is available only in multiclass classification.'; ...
                'DAG is unavailable when the persisted RAND.Decompose selects one-vs-all (2).'; ...
                'ECOC uses multiDecoding; pairwise uses multiDecisionType.'};
        end

        function choices = apiChoices()
            choices.multiMethod = NMMULTITools.MethodChoices;
            choices.multiCoding = NMMULTITools.CodingChoices;
            choices.multiDecoding = NMMULTITools.DecodingChoices;
            choices.multiDecisionType = NMMULTITools.DecisionChoices;
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the multi-class branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMMULTITools.cli_configureHelp();
        end

        function state = stateFromNM(NM, varind, fusionFlag)
            % stateFromNM  Reconstruct multi-class browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.MULTI and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            [MULTI, present] = NMMULTITools.extractLegacyMULTI(NM, varind, fusionFlag);
            MULTI = NMMULTITools.completeDefaults(MULTI, NM);
            state = NMMULTITools.stateFromMULTI(MULTI, NM, varind, fusionFlag);
            state.multiPresent = present;
            state.multiDirty = false;
        end


        function MULTI = defaultSetting(NM, varind, fusionFlag) %#ok<INUSD>
            % defaultSetting  Public legacy default for nk_Multi_config. nk_TrainClass_config.
            %
            % materializes the branch but keeps multi-class prediction disabled
            % until explicitly configured.
            if nargin < 1 || isempty(NM), NM = struct(); end
            MULTI = NMMULTITools.completeDefaults(struct('flag',0,'train',0,'BinBind',0), NM);
            MULTI.flag = 0;
            MULTI.train = 0;
            MULTI.BinBind = 0;
        end

        function MULTI = completeDefaults(MULTI, NM)
            % completeDefaults  Fill missing legacy MULTI fields with modular defaults.
            %
            % Normalizes an existing MULTI struct before it is converted to browser/API state or written back to NM. Defaults are chosen to preserve legacy NeuroMiner behavior unless the caller explicitly changes them.
            if nargin < 1 || isempty(MULTI), MULTI = struct(); end
            if nargin < 2, NM = struct(); end
            if ~isstruct(MULTI), MULTI = struct(); end
            [available, ~, ~] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            def = struct('flag',1,'hardcoded',1,'train',1,'method',2, ...
                'coding',1,'decoding',1,'BinBind',0,'decisiontype',1);
            f = fieldnames(def);
            for i = 1:numel(f)
                if ~isfield(MULTI,f{i}) || isempty(MULTI.(f{i}))
                    MULTI.(f{i}) = def.(f{i});
                end
            end
            MULTI.flag = NMMULTITools.allowedScalar(MULTI.flag, def.flag, [0 1]);
            MULTI.hardcoded = NMMULTITools.allowedScalar(MULTI.hardcoded, def.hardcoded, [0 1]);
            MULTI.train = NMMULTITools.allowedScalar(MULTI.train, def.train, [0 1]);
            MULTI.method = NMMULTITools.allowedScalar(MULTI.method, def.method, 1:3);
            MULTI.coding = NMMULTITools.allowedScalar(MULTI.coding, def.coding, 1);
            MULTI.decoding = NMMULTITools.allowedScalar(MULTI.decoding, def.decoding, 1:5);
            MULTI.BinBind = NMMULTITools.allowedScalar(MULTI.BinBind, def.BinBind, [0 1]);
            MULTI.decisiontype = NMMULTITools.allowedScalar(MULTI.decisiontype, def.decisiontype, 1:5);
            if MULTI.train == 1, MULTI.BinBind = 0; end
            if ~NMMULTITools.dagAvailable(NM) && MULTI.method == 3, MULTI.method = 2; end
            if ~available
                MULTI.flag = 0;
                MULTI.train = 0;
                MULTI.BinBind = 0;
            end
        end

        function state = stateFromMULTI(MULTI, NM, varind, fusionFlag)
            % stateFromMULTI  Convert legacy MULTI settings into browser/API state.
            %
            % Adds multi-class availability, class-count and DAG eligibility diagnostics around the stored legacy flags. The method is read-only and lets UI/API callers understand why MULTI controls may be disabled before applyToNM writes changes.
            if nargin < 2, NM = struct(); end
            if nargin < 3 || isempty(varind), varind = 1; end
            MULTI = NMMULTITools.completeDefaults(MULTI, NM);
            [available, nClasses, classes] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            state = struct();
            state.multiAvailable = available;
            state.multiClassCount = nClasses;
            state.multiClassLabels = classes;
            state.multiDagAvailable = NMMULTITools.dagAvailable(NM);
            state.multiFlag = logical(MULTI.flag);
            state.multiTrain = logical(MULTI.train);
            state.multiHardcoded = double(MULTI.hardcoded);
            state.multiMethod = double(MULTI.method);
            state.multiCoding = double(MULTI.coding);
            state.multiDecoding = double(MULTI.decoding);
            state.multiBinBind = logical(MULTI.BinBind);
            state.multiDecisionType = double(MULTI.decisiontype);
            state.multiScope = NMMULTITools.scopeLabel(NM, varind, fusionFlag);
        end

        function state = stateFromMenu(NM, current, menuState, varind, fusionFlag)
            % stateFromMenu  Translate browser multi-class controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            if nargin < 2 || isempty(current) || ~isstruct(current)
                current = NMMULTITools.stateFromNM(NM, varind, fusionFlag);
            end
            if nargin < 4 || isempty(varind), varind = 1; end
            state = current;
            if isfield(menuState,'multi') && isstruct(menuState.multi)
                src = menuState.multi;
            else
                src = menuState;
            end
            fn = fieldnames(src);
            for i = 1:numel(fn)
                if startsWith(fn{i}, 'multi')
                    state.(fn{i}) = src.(fn{i});
                end
            end
            state = NMMULTITools.normalizeState(NM, state, varind, fusionFlag);
        end

        function state = normalizeState(NM, state, varind, fusionFlag)
            % normalizeState  Enforce valid multi-class state values before legacy materialization.
            %
            % Coerces booleans/enums/numeric options, repairs invalid or unavailable choices and derives context-sensitive defaults. applyToNM expects this normalized state.
            %
            % state.multiDirty: carries the multi dirty value between browser/API state and legacy NeuroMiner structures.
            % state.multiPresent: carries the multi present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            keepPresent = isfield(state,'multiPresent') && logical(state.multiPresent);
            keepDirty = isfield(state,'multiDirty') && logical(state.multiDirty);
            MULTI = NMMULTITools.multiFromState(NM, state, varind, fusionFlag);
            state = NMMULTITools.stateFromMULTI(MULTI, NM, varind, fusionFlag);
            state.multiPresent = keepPresent;
            state.multiDirty = keepDirty;
        end

        function MULTI = multiFromState(NM, state, varind, fusionFlag) %#ok<INUSD>
            % multiFromState  Convert normalized multi-class state into legacy MULTI struct.
            %
            % Builds the backend NM.TrainParam.MULTI branch only from values that legacy multi-class training expects. Browser-only eligibility and summary fields are not written.
            %
            % state.multiBinBind: carries the multi bin bind value between browser/API state and legacy NeuroMiner structures.
            % state.multiDecisionType: carries the multi decision type value between browser/API state and legacy NeuroMiner structures.
            % state.multiDecoding: carries the multi decoding value between browser/API state and legacy NeuroMiner structures.
            % state.multiFlag: carries the multi flag value between browser/API state and legacy NeuroMiner structures.
            % state.multiMethod: carries the multi method value between browser/API state and legacy NeuroMiner structures.
            % state.multiTrain: carries the multi train value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            [base, ~] = NMMULTITools.extractLegacyMULTI(NM, varind, fusionFlag);
            MULTI = NMMULTITools.completeDefaults(base, NM);
            if isfield(state,'multiFlag'), MULTI.flag = double(logical(state.multiFlag)); end
            if isfield(state,'multiTrain'), MULTI.train = double(logical(state.multiTrain)); end
            if isfield(state,'multiMethod'), MULTI.method = NMMULTITools.allowedScalar(state.multiMethod, MULTI.method, 1:3); end
            if isfield(state,'multiDecoding'), MULTI.decoding = NMMULTITools.allowedScalar(state.multiDecoding, MULTI.decoding, 1:5); end
            if isfield(state,'multiDecisionType'), MULTI.decisiontype = NMMULTITools.allowedScalar(state.multiDecisionType, MULTI.decisiontype, 1:5); end
            if isfield(state,'multiBinBind'), MULTI.BinBind = double(logical(state.multiBinBind)); end
            MULTI.coding = 1;
            MULTI.hardcoded = 1;
            MULTI = NMMULTITools.completeDefaults(MULTI, NM);
        end

        function NM = applyToNM(NM, state, varind, fusionFlag)
            % applyToNM  Materialize multi-class settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.MULTI at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.multiDirty: carries the multi dirty value between browser/API state and legacy NeuroMiner structures.
            % state.multiPresent: carries the multi present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = 1; end
            present = isfield(state,'multiPresent') && logical(state.multiPresent);
            dirty = isfield(state,'multiDirty') && logical(state.multiDirty);
            [available, ~, ~] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            if ~(present || dirty || ~available), return; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            MULTI = NMMULTITools.multiFromState(NM, state, varind, fusionFlag);
            if round(double(fusionFlag)) == 3
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1, max(1,varind));
                end
                if numel(NM.TrainParam.STRAT) < varind, NM.TrainParam.STRAT{varind} = []; end
                if isempty(NM.TrainParam.STRAT{varind}) || ~isstruct(NM.TrainParam.STRAT{varind})
                    NM.TrainParam.STRAT{varind} = struct();
                end
                NM.TrainParam.STRAT{varind}.MULTI = MULTI;
            else
                NM.TrainParam.MULTI = MULTI;
            end
        end

        function txt = summary(state)
            % summary  Render a concise human-readable multi-class configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            %
            % state.multiAvailable: carries the multi available value between browser/API state and legacy NeuroMiner structures.
            % state.multiClassCount: carries the multi class count value between browser/API state and legacy NeuroMiner structures.
            % state.multiFlag: carries the multi flag value between browser/API state and legacy NeuroMiner structures.
            % state.multiMethod: carries the multi method value between browser/API state and legacy NeuroMiner structures.
            % state.multiTrain: carries the multi train value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                txt = 'Multi-class configuration unavailable.';
                return;
            end
            if ~isfield(state,'multiAvailable') || ~logical(state.multiAvailable)
                txt = 'Binary or regression problem: multi-class configuration unavailable.';
                return;
            end
            n = NMMULTITools.scalarOrDefault(NMMULTITools.fieldOr(state,'multiClassCount',0),0);
            if ~isfield(state,'multiFlag') || ~logical(state.multiFlag)
                txt = sprintf('Multi-class problem detected (%d classes); multi-class predictor disabled.', n);
                return;
            end
            method = NMMULTITools.methodLabel(NMMULTITools.fieldOr(state,'multiMethod',2));
            train = 'binary-optimized';
            if isfield(state,'multiTrain') && logical(state.multiTrain), train = 'multi-class optimized'; end
            txt = sprintf('Multi-class predictor enabled (%d classes): %s; %s.', n, method, train);
        end

        function tf = dagAvailable(NM)
            % dagAvailable  Report whether directed-acyclic-graph multi-class mode is available.
            %
            % Checks task and class conditions required by the legacy DAG strategy. The method is read-only and isolates a legacy option gate from UI code.
            tf = true;
            try
                if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'RAND') && isstruct(NM.TrainParam.RAND) && ...
                        isfield(NM.TrainParam.RAND,'Decompose') && isequal(round(double(NM.TrainParam.RAND.Decompose)),2)
                    tf = false;
                end
            catch
                tf = true;
            end
        end

        function lbl = methodLabel(method)
            % methodLabel  Convert a MULTI method code into display text.
            %
            % Maps legacy numeric method identifiers to stable labels for cards, summaries and diagnostics. Unknown codes fall back to explicit text rather than changing configuration.
            method = NMMULTITools.allowedScalar(method, 2, 1:3);
            switch method
                case 1
                    lbl = 'simple pairwise decoding';
                case 2
                    lbl = 'error-correcting output codes';
                otherwise
                    lbl = 'directed acyclic graph';
            end
        end

        function lbl = scopeLabel(NM, varind, fusionFlag) %#ok<INUSL>
            % scopeLabel  Describe the modality/fusion scope of the current MULTI branch.
            %
            % Uses NM, VarIndex and FusionFlag to produce user-facing scope text for summaries. It is read-only and does not decide where applyToNM writes configuration.
            if nargin < 2 || isempty(varind), varind = 1; end
            if round(double(fusionFlag)) == 3
                lbl = sprintf('NM.TrainParam.STRAT{%d}.MULTI', varind);
            else
                lbl = 'NM.TrainParam.MULTI';
            end
        end

        function [MULTI, present] = extractLegacyMULTI(NM, varind, fusionFlag)
            % extractLegacyMULTI  Read the active legacy MULTI branch and report whether it exists.
            %
            % Looks in the appropriate NM.TrainParam location for global or fusion-scoped MULTI settings and returns a presence flag. This isolates legacy storage variation from stateFromNM.
            if nargin < 2 || isempty(varind), varind = 1; end
            MULTI = struct(); present = false;
            try
                if round(double(fusionFlag)) == 3 && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'STRAT') && iscell(NM.TrainParam.STRAT) && ...
                        numel(NM.TrainParam.STRAT) >= varind && isstruct(NM.TrainParam.STRAT{varind}) && ...
                        isfield(NM.TrainParam.STRAT{varind},'MULTI') && isstruct(NM.TrainParam.STRAT{varind}.MULTI)
                    MULTI = NM.TrainParam.STRAT{varind}.MULTI;
                    present = true;
                elseif isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'MULTI') && isstruct(NM.TrainParam.MULTI)
                    MULTI = NM.TrainParam.MULTI;
                    present = true;
                end
            catch
                MULTI = struct(); present = false;
            end
        end


        function out = allowedScalar(x, d, allowed)
            % allowedScalar  Coerce a scalar option to an allowed value with fallback.
            %
            % Normalizes numeric or logical legacy option values and returns the default when the input is empty, non-scalar or not in the allowed set. It supports robust state normalization.
            out = d;
            try
                v = round(double(x));
                if isfinite(v) && any(v == allowed), out = v; end
            catch
                out = d;
            end
        end

        function out = scalarOrDefault(x, d)
            % scalarOrDefault  Return a scalar value or a default fallback.
            %
            % Provides the simple scalar coercion used by MULTI normalization before values are written into legacy TrainParam fields.
            out = d;
            try
                v = double(x);
                if ~isempty(v) && isfinite(v(1)), out = v(1); end
            catch
                out = d;
            end
        end

        function v = fieldOr(S, fn, d)
            % fieldOr  Read a field from a struct with empty-value fallback.
            %
            % Returns the fallback when the input is not a struct, the field is absent or the value is empty. The method keeps MULTI normalization explicit about fallback behavior.
            if isstruct(S) && isfield(S,fn) && ~isempty(S.(fn))
                v = S.(fn);
            else
                v = d;
            end
        end
    end
end
