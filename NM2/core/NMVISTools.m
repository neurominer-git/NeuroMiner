classdef NMVISTools
% NMVISTools
% -------------------------------------------------------------------------
% Browser-port helper for nk_Vis_config.m. The helper keeps UI-only fields
% out of NM.TrainParam.VIS and writes only the legacy VIS structure.  The
% model-space permutation branch mirrors nk_Vis_config's dependency on
% dimensionality-reference preprocessing through the authoritative legacy
% nk_DetIfDimRefInPREPROC predicate.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        PermutationChoices = struct('symbol',{'labels','features','labels_and_features','covariates'}, ...
            'code',{1,2,3,4},'description',{'Permute labels','Permute features within labels', ...
            'Permute labels and features','Permute covariates (requires expert mode and covariate data)'})
        CorrectionChoices = struct('symbol',{'fdr_per_model','fdr_global','none'}, ...
            'code',{1,2,3},'description',{'FDR before back-projection, per model', ...
            'FDR after cross-validation, globally','No multiple-comparison correction'})
    end

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the visualization branch.
            %
            % Merges state/name-value inputs with stateFromNM, applies aliases and normalization, then materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the documented legacy target NM.TrainParam.VIS and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            varind = NMConfigureAPITools.optionValue(varargin, 'VarIndex', 1);
            fusionFlag = NMConfigureAPITools.optionValue(varargin, 'FusionFlag', []);
            if isempty(fusionFlag), fusionFlag = NMFusionStateTools.flagFromNM(NM); end
            defaultState = NMVISTools.stateFromNM(NM, varind, fusionFlag);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {'VarIndex','FusionFlag'}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.visDirty = true; end
            try
                state = NMConfigureAPITools.normalizeChoices(state, NMVISTools.apiChoices(), 'MATLAB:assertion:failed');
                state = NMVISTools.normalizeState(NM, state, varind, fusionFlag);
                NM = NMVISTools.applyToNM(NM, state, varind, fusionFlag);
                if isempty(report.message), report.message = 'NMVISTools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public visualization configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMVISTools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted visualization configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.VIS. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.VarIndex = 'Modality/strategy index where applicable.';
            opts.FusionFlag = 'Fusion flag where applicable.';
            opts.visNPerms = 'Positive integer count shared by input-space and model-space permutations.';
            opts.visSigPThresh = 'Positive significance threshold.';
            opts.visCovariateIndices = 'Existing covariate column indices, numeric.';
            h = NMConfigureAPITools.helpStruct('NMVISTools.cli_configure', ...
                '[NM, state, report] = NMVISTools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMVISTools.configure(NM, ''visPermMode'',''labels'', ''visSigCorrection'',''fdr_global'');'}, NMVISTools.apiChoices());
            h.validationRules = {'Covariate permutation is context-dependent; browser may restrict mode 4.'; ...
                'Model-space permutation requires dimensionality-reference preprocessing.'};
        end

        function choices = apiChoices()
            choices.visPermMode = NMVISTools.PermutationChoices;
            choices.visSigCorrection = NMVISTools.CorrectionChoices;
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the visualization branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMVISTools.cli_configureHelp();
        end

        function config = scientificConfig(NM, state, varind, fusionFlag)
            % scientificConfig  Effective VIS choices relative to contextual defaults.
            % The VIS owner selects only enabled permutation branches; derived
            % availability, preview metadata, and inactive settings are excluded.
            PREPROC = NMVISTools.extractLegacyPreproc(NM, varind, fusionFlag);
            defaults = NMVISTools.stateFromVIS( ...
                NMVISTools.defaultSetting(NM, PREPROC, varind, fusionFlag), ...
                NM, PREPROC, varind, fusionFlag);
            keys = {'visPermutationInput','visSigModelSpace'};
            if state.visPermutationInput
                keys = [keys, {'visNPerms','visPermMode'}];
                if state.visPermMode == 4
                    keys{end+1} = 'visCovariateIndices';
                end
            end
            if state.visSigModelSpace
                keys = [keys, {'visSigCorrection','visSigPThresh','visSigPNPerms'}];
                if ~state.visPermutationInput, keys{end+1} = 'visNPerms'; end
            end
            config = struct();
            if all(cellfun(@(k)isequaln(state.(k),defaults.(k)),keys)), return; end
            choices = NMVISTools.apiChoices();
            for k = 1:numel(keys)
                name = keys{k};
                value = state.(name);
                if ismember(name,fieldnames(choices))
                    available = choices.(name);
                    match = find(arrayfun(@(c)isequaln(c.code,value),available));
                    assert(isscalar(match),'NMVISTools:scientificSymbol', ...
                        'No unique symbolic VIS choice for %s.',name);
                    value = available(match).symbol;
                end
                config.(name) = value;
            end
        end

        function state = stateFromNM(NM, varind, fusionFlag)
            % stateFromNM  Reconstruct visualization browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.VIS and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            [VIS, present] = NMVISTools.extractLegacyVIS(NM, varind, fusionFlag);
            PREPROC = NMVISTools.extractLegacyPreproc(NM, varind, fusionFlag);
            state = NMVISTools.stateFromVIS(VIS, NM, PREPROC, varind, fusionFlag);
            state.visPresent = present;
            state.visDirty = false;
        end


        function VIS = defaultSetting(NM, PREPROC, varind, fusionFlag)
            % defaultSetting  Public legacy default used by NMTrainTemplateOrchestrator when.
            %
            % a VIS branch is absent. This mirrors nk_Vis_config defaults via
            % the browser helper's normalization path without opening the CLI.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2, PREPROC = []; end
            if nargin < 3 || isempty(varind), varind = 1; end
            VIS = NMVISTools.completeDefaults(struct(), NM, PREPROC, varind);
        end

        function VIS = completeDefaults(VIS, NM, PREPROC, varind)
            % completeDefaults  Fill missing legacy VIS fields with modular defaults.
            %
            % Normalizes an existing VIS struct before it is converted to browser/API state or written back to NM. Defaults are chosen to preserve legacy NeuroMiner behavior unless the caller explicitly changes them.
            if nargin < 1 || isempty(VIS), VIS = struct(); end
            if nargin < 2, NM = struct(); end
            if nargin < 3, PREPROC = []; end
            if nargin < 4 || isempty(varind), varind = 1; end
            if ~isstruct(VIS), VIS = struct(); end

            PERM = struct('flag',0,'nperms',5000,'sigflag',0, ...
                'sigPthresh',0.05,'sigPfdr',1,'mode',1);
            if isfield(VIS,'PERM') && isstruct(VIS.PERM)
                f = fieldnames(VIS.PERM);
                for i = 1:numel(f)
                    PERM.(f{i}) = VIS.PERM.(f{i});
                end
            end
            VIS.norm = 1; % Fixed descriptive L2 normalization; inference uses raw weights.

            flgProj = ~isempty(PREPROC) && logical(nk_DetIfDimRefInPREPROC(PREPROC, varind));
            PERM.flag = NMVISTools.allowedScalar(PERM.flag, 0, [0 1]);
            PERM.nperms = max(1, round(double(NMVISTools.scalarOrDefault(PERM.nperms, 5000))));
            PERM.sigflag = NMVISTools.allowedScalar(PERM.sigflag, 0, [0 1]);
            if ~flgProj, PERM.sigflag = 0; end
            PERM.sigPthresh = double(NMVISTools.scalarOrDefault(PERM.sigPthresh, 0.05));
            if ~isfinite(PERM.sigPthresh) || PERM.sigPthresh <= 0, PERM.sigPthresh = 0.05; end
            PERM.sigPfdr = NMVISTools.allowedScalar(PERM.sigPfdr, 1, 1:3);
            PERM.mode = NMVISTools.allowedScalar(PERM.mode, 1, 1:4);
            if isfield(PERM,'covars_idx')
                PERM.covars_idx = NMVISTools.indexVector(PERM.covars_idx, []);
            end
            if isfield(PERM,'sigPnperms')
                PERM.sigPnperms = max(1, round(double(NMVISTools.scalarOrDefault(PERM.sigPnperms, PERM.nperms))));
            end
            VIS.PERM = PERM;
        end

        function state = stateFromVIS(VIS, NM, PREPROC, varind, fusionFlag)
            % stateFromVIS  Convert legacy VIS settings into browser/API state.
            %
            % Combines stored VIS flags with preprocessing-derived availability for normalization, projection and model-space permutation controls. The method is read-only; applyToNM later materializes VIS changes into the training template.
            if nargin < 2, NM = struct(); end
            if nargin < 3, PREPROC = []; end
            if nargin < 4 || isempty(varind), varind = 1; end
            VIS = NMVISTools.completeDefaults(VIS, NM, PREPROC, varind);
            PERM = VIS.PERM;
            state = struct();
            state.visProjectionAvailable = ~isempty(PREPROC) && logical(nk_DetIfDimRefInPREPROC(PREPROC, varind));
            state.visPermutationInput = logical(PERM.flag);
            state.visNPerms = double(PERM.nperms);
            state.visPermMode = double(PERM.mode);
            if isfield(PERM,'covars_idx')
                state.visCovariateIndices = NMVISTools.indexVector(PERM.covars_idx, []);
            else
                state.visCovariateIndices = [];
            end
            state.visSigModelSpace = logical(PERM.sigflag);
            state.visSigCorrection = double(PERM.sigPfdr);
            state.visSigPThresh = double(PERM.sigPthresh);
            if isfield(PERM,'sigPnperms')
                state.visSigPNPerms = double(PERM.sigPnperms);
            else
                state.visSigPNPerms = [];
            end
            [names, hasCovars] = NMVISTools.covariateNames(NM);
            state.visCovariateNames = names;
            state.visCovariateAvailable = hasCovars;
            state.visExpert = NMVISTools.expertMode();
            state.visScope = NMVISTools.scopeLabel(NM, varind, fusionFlag);
        end

        function state = stateFromMenu(NM, current, menuState, varind, fusionFlag)
            % stateFromMenu  Translate browser visualization controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            if nargin < 2 || isempty(current) || ~isstruct(current)
                current = NMVISTools.stateFromNM(NM, varind, fusionFlag);
            end
            if nargin < 4 || isempty(varind), varind = 1; end
            state = current;
            if isfield(menuState,'vis') && isstruct(menuState.vis)
                src = menuState.vis;
            else
                src = menuState;
            end
            fn = fieldnames(src);
            for i = 1:numel(fn)
                if startsWith(fn{i}, 'vis')
                    state.(fn{i}) = src.(fn{i});
                end
            end
            state = NMVISTools.normalizeState(NM, state, varind, fusionFlag);
        end

        function state = normalizeState(NM, state, varind, fusionFlag)
            % normalizeState  Normalize browser visualization state directly.
            %
            % Derived availability comes from NM/PREPROC authorities; mutable VIS
            % values are normalized in the browser state without a state->legacy->state round trip.
            if nargin < 2 || isempty(state) || ~isstruct(state), state = struct(); end
            if nargin < 3 || isempty(varind), varind = 1; end
            PREPROC = NMVISTools.extractLegacyPreproc(NM, varind, fusionFlag);
            projectionAvailable = ~isempty(PREPROC) && logical(nk_DetIfDimRefInPREPROC(PREPROC, varind));
            present = isfield(state,'visPresent') && logical(NMVISTools.allowedScalar(state.visPresent, 0, [0 1]));
            dirty = isfield(state,'visDirty') && logical(NMVISTools.allowedScalar(state.visDirty, 0, [0 1]));
            mutableFields = {'visPermutationInput','visNPerms','visPermMode', ...
                'visCovariateIndices','visSigModelSpace','visSigCorrection','visSigPThresh','visSigPNPerms'};
            missing = ~isfield(state, mutableFields);
            if any(missing)
                base = NMVISTools.stateFromNM(NM, varind, fusionFlag);
                for i = find(missing)
                    state.(mutableFields{i}) = base.(mutableFields{i});
                end
            end

            state.visProjectionAvailable = projectionAvailable;
            state.visPermutationInput = logical(NMVISTools.allowedScalar(state.visPermutationInput, 0, [0 1]));
            state.visNPerms = max(1, round(double(NMVISTools.scalarOrDefault(state.visNPerms, 5000))));
            state.visPermMode = NMVISTools.allowedScalar(state.visPermMode, 1, 1:4);
            state.visCovariateIndices = NMVISTools.indexVector(state.visCovariateIndices, []);
            state.visSigModelSpace = logical(NMVISTools.allowedScalar(state.visSigModelSpace, 0, [0 1])) && projectionAvailable;
            state.visSigCorrection = NMVISTools.allowedScalar(state.visSigCorrection, 1, 1:3);
            state.visSigPThresh = double(NMVISTools.scalarOrDefault(state.visSigPThresh, 0.05));
            if state.visSigPThresh <= 0, state.visSigPThresh = 0.05; end
            if ~isempty(state.visSigPNPerms)
                state.visSigPNPerms = max(1, round(double(NMVISTools.scalarOrDefault(state.visSigPNPerms, state.visNPerms))));
            end
            [state.visCovariateNames, state.visCovariateAvailable] = NMVISTools.covariateNames(NM);
            state.visExpert = NMVISTools.expertMode();
            state.visScope = NMVISTools.scopeLabel(NM, varind, fusionFlag);
            state.visPresent = present;
            state.visDirty = dirty;
        end

        function VIS = visFromState(NM, state, varind, fusionFlag)
            % visFromState  Convert normalized visualization state into the legacy VIS struct.
            %
            % Builds the NM.TrainParam.VIS branch used by legacy model visualization routines, including model-space permutation options and modality/fusion context. Browser-only fields are omitted.
            %
            % state.visCovariateIndices: carries the vis covariate indices value between browser/API state and legacy NeuroMiner structures.
            % state.visNPerms: carries the vis nperms value between browser/API state and legacy NeuroMiner structures.
            % state.visPermMode: carries the vis perm mode value between browser/API state and legacy NeuroMiner structures.
            % state.visPermutationInput: carries the vis permutation input value between browser/API state and legacy NeuroMiner structures.
            % state.visSigCorrection: carries the vis sig correction value between browser/API state and legacy NeuroMiner structures.
            % state.visSigModelSpace: carries the vis sig model space value between browser/API state and legacy NeuroMiner structures.
            % state.visSigPNPerms: carries the vis sig pnperms value between browser/API state and legacy NeuroMiner structures.
            % state.visSigPThresh: carries the vis sig pthresh value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            PREPROC = NMVISTools.extractLegacyPreproc(NM, varind, fusionFlag);
            [base, ~] = NMVISTools.extractLegacyVIS(NM, varind, fusionFlag);
            VIS = NMVISTools.completeDefaults(base, NM, PREPROC, varind);
            flgProj = ~isempty(PREPROC) && logical(nk_DetIfDimRefInPREPROC(PREPROC, varind));
            PERM = VIS.PERM;
            if isfield(state,'visPermutationInput'), PERM.flag = NMVISTools.allowedScalar(state.visPermutationInput, PERM.flag, [0 1]); end
            if isfield(state,'visNPerms'), PERM.nperms = max(1, round(NMVISTools.scalarOrDefault(state.visNPerms, PERM.nperms))); end
            if isfield(state,'visPermMode'), PERM.mode = NMVISTools.allowedScalar(state.visPermMode, PERM.mode, 1:4); end
            if ~isempty(state.visCovariateIndices) || any(strcmp(fieldnames(PERM),'covars_idx'))
                PERM.covars_idx = NMVISTools.indexVector(state.visCovariateIndices, []);
            end
            if isfield(state,'visSigModelSpace'), PERM.sigflag = NMVISTools.allowedScalar(state.visSigModelSpace, PERM.sigflag, [0 1]); end
            if isfield(state,'visSigCorrection'), PERM.sigPfdr = NMVISTools.allowedScalar(state.visSigCorrection, PERM.sigPfdr, 1:3); end
            if isfield(state,'visSigPThresh')
                v = NMVISTools.scalarOrDefault(state.visSigPThresh, PERM.sigPthresh);
                if v > 0, PERM.sigPthresh = v; end
            end
            if isfield(state,'visSigPNPerms') && ~isempty(state.visSigPNPerms)
                PERM.sigPnperms = max(1, round(NMVISTools.scalarOrDefault(state.visSigPNPerms, PERM.nperms)));
            end
            if ~flgProj, PERM.sigflag = 0; end
            VIS.PERM = PERM;
        end

        function NM = applyToNM(NM, state, varind, fusionFlag)
            % applyToNM  Materialize visualization settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.VIS at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.visDirty: carries the vis dirty value between browser/API state and legacy NeuroMiner structures.
            % state.visPresent: carries the vis present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = 1; end
            present = isfield(state,'visPresent') && logical(state.visPresent);
            dirty = isfield(state,'visDirty') && logical(state.visDirty);
            if ~(present || dirty), return; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            VIS = NMVISTools.visFromState(NM, state, varind, fusionFlag);
            if round(double(fusionFlag)) == 3
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1, max(1,varind));
                end
                if numel(NM.TrainParam.STRAT) < varind, NM.TrainParam.STRAT{varind} = []; end
                if isempty(NM.TrainParam.STRAT{varind}) || ~isstruct(NM.TrainParam.STRAT{varind})
                    NM.TrainParam.STRAT{varind} = struct();
                end
                NM.TrainParam.STRAT{varind}.VIS = VIS;
            else
                if ~isfield(NM.TrainParam,'VIS') || isempty(NM.TrainParam.VIS)
                    NM.TrainParam.VIS = cell(1, max(1,varind));
                end
                if iscell(NM.TrainParam.VIS)
                    if numel(NM.TrainParam.VIS) < varind, NM.TrainParam.VIS{varind} = []; end
                    NM.TrainParam.VIS{varind} = VIS;
                else
                    NM.TrainParam.VIS = VIS;
                end
            end
        end

        function text = summary(state)
            % summary  Render a concise human-readable visualization configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            %
            % state.visPermutationInput: carries the vis permutation input value between browser/API state and legacy NeuroMiner structures.
            % state.visSigModelSpace: carries the vis sig model space value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                text = 'Visualization options are not configured.';
                return;
            end
            parts = {};
            if isfield(state,'visSigModelSpace') && logical(state.visSigModelSpace)
                parts{end+1} = 'model-space permutation/back-projection enabled'; %#ok<AGROW>
            end
            if isfield(state,'visPermutationInput') && logical(state.visPermutationInput)
                parts{end+1} = sprintf('input-space permutations: %g', double(state.visNPerms)); %#ok<AGROW>
            end
            if isempty(parts)
                text = 'Visualization defaults: no permutation testing enabled.';
            else
                text = strjoin(parts, '; ');
                text = [upper(text(1)) text(2:end) '.'];
            end
        end
    end

    methods (Static, Access = private)
        function [VIS, present] = extractLegacyVIS(NM, varind, fusionFlag)
            VIS = struct(); present = false;
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if round(double(fusionFlag)) == 3 && isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && ...
                    isstruct(TP.STRAT{varind}) && isfield(TP.STRAT{varind},'VIS') && isstruct(TP.STRAT{varind}.VIS)
                VIS = TP.STRAT{varind}.VIS; present = true; return;
            end
            if isfield(TP,'VIS')
                if iscell(TP.VIS) && numel(TP.VIS) >= varind && isstruct(TP.VIS{varind})
                    VIS = TP.VIS{varind}; present = true;
                elseif isstruct(TP.VIS)
                    VIS = TP.VIS; present = true;
                end
            end
        end

        function PREPROC = extractLegacyPreproc(NM, varind, fusionFlag)
            PREPROC = [];
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if round(double(fusionFlag)) == 3 && isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && ...
                    isstruct(TP.STRAT{varind}) && isfield(TP.STRAT{varind},'PREPROC')
                PREPROC = TP.STRAT{varind}.PREPROC;
                return;
            end
            if isfield(TP,'PREPROC')
                if iscell(TP.PREPROC)
                    if numel(TP.PREPROC) >= varind
                        PREPROC = TP.PREPROC{varind};
                    end
                else
                    PREPROC = TP.PREPROC;
                end
            end
        end

        function [names, hasCovars] = covariateNames(NM)
            names = {};
            if isfield(NM,'covars') && ~isempty(NM.covars)
                if iscell(NM.covars)
                    names = cellfun(@char, NM.covars(:)', 'UniformOutput', false);
                elseif isstring(NM.covars)
                    names = cellstr(NM.covars(:)');
                end
            end
            hasCovars = ~isempty(names);
        end

        function tf = expertMode()
            tf = false;
            try
                global EXPERT
                if ~isempty(EXPERT), tf = logical(EXPERT); end
            catch
                tf = false;
            end
        end

        function s = scopeLabel(NM, varind, fusionFlag) %#ok<INUSD>
            if round(double(fusionFlag)) == 3
                s = sprintf('NM.TrainParam.STRAT{%d}.VIS', varind);
            else
                s = sprintf('NM.TrainParam.VIS{%d}', varind);
            end
        end


        function v = allowedScalar(v, default, allowed)
            try
                v = round(double(v));
            catch
                v = default;
            end
            if isempty(v) || ~isscalar(v) || ~isfinite(v) || ~ismember(v, allowed), v = default; end
        end

        function v = scalarOrDefault(v, default)
            try
                v = double(v);
            catch
                v = default;
            end
            if isempty(v) || ~isscalar(v) || ~isfinite(v), v = default; end
        end

        function idx = indexVector(v, default)
            if nargin < 2, default = []; end
            try
                if ischar(v) || isstring(v)
                    v = str2num(char(v)); %#ok<ST2NM>
                end
                idx = round(double(v(:)'));
                idx = idx(isfinite(idx) & idx >= 1);
            catch
                idx = default;
            end
            if isempty(idx), idx = default; end
        end
    end
end
