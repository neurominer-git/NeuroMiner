classdef NMRFETools
% NMRFETools
% -------------------------------------------------------------------------
% Browser-port helper for nk_RFE_config.m, nk_Filter_config.m and
% nk_Wrapper_config.m. The helper keeps UI metadata outside the exported
% legacy RFE branch and writes only NM.TrainParam.RFE or
% NM.TrainParam.STRAT{i}.RFE.
% -------------------------------------------------------------------------

    % One symbol/code/description authority for nested RFE API selections.
    properties (Constant, Access = private)
        NestedChoices = struct( ...
            'Pearson', struct('symbol',{{'pearson','spearman'}}, ...
                'code',{[1,2]}, 'description',{{'Pearson correlation','Spearman rank correlation'}}), ...
            'SubSpaceStrategy', struct('symbol',{{'winner_takes_all','within_range','percentile','all'}}, ...
                'code',{[1,2,3,4]}, 'description',{{'Best-performing subspace','Subspaces within a range of optimum','Subspaces above/below percentile according to metric direction','All subspaces'}}), ...
            'ConstructMode', struct('symbol',{{'aggregate','backward_elimination','forward_selection','probabilistic_subspace','boosting'}}, ...
                'code',{[0,1,2,4,5]}, 'description',{{'Aggregate base learners','Backward base-learner elimination','Forward base-learner selection','Probabilistic subspace construction','Boosting base learners'}}), ...
            'DataMode', struct('symbol',{{'train','test','full','train_test'}}, ...
                'code',{[1,2,3,4]}, 'description',{{'CV1 training cases','CV1 test cases','Full CV1 partition','CV1 train and test combined'}}), ...
            'PFEMode', struct('symbol',{{'agreement','top_n','top_percent'}}, ...
                'code',{[1,2,3]}, 'description',{{'Cross-CV1 agreement with tolerance window','Absolute number of stable features','Percentage of stable features'}}));
    end

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the feature-selection/RFE branch.
            %
            % Merges canonical state/name-value inputs with stateFromNM, normalizes and materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the established target NM.TrainParam.RFE or STRAT{i}.RFE and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            varind = NMConfigureAPITools.optionValue(varargin, 'VarIndex', 1);
            fusionFlag = NMConfigureAPITools.optionValue(varargin, 'FusionFlag', []);
            if isempty(fusionFlag), fusionFlag = NMFusionStateTools.flagFromNM(NM); end
            defaultState = NMRFETools.stateFromNM(NM, varind, fusionFlag);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {'VarIndex','FusionFlag'}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.rfeDirty = true; end
            try
                filters = NMRFETools.filterMethodLabels(NMAlternativeLabelTools.effectiveMode(NM));
                value = state.Filter.type;
                ix = find(strcmp(value,filters(:,2)),1);
                if ~isempty(ix)
                    state.Filter.type = filters{ix,1};
                else
                    assert(any([filters{:,1}] == value), ...
                        'Invalid Filter.type. See NMRFETools.configureHelp().choices.Filter.type.');
                end
                wrappers = cell(1,5);
                for k = 1:5
                    wrappers{k} = NMRFETools.wrapperMethodLabel(struct('type',k));
                end
                value = state.Wrapper.type;
                ix = find(strcmp(value,wrappers),1);
                if ~isempty(ix)
                    state.Wrapper.type = ix;
                else
                    assert(any((1:5) == value), ...
                        'Invalid Wrapper.type. See NMRFETools.configureHelp().choices.Wrapper.type.');
                end
                state = NMConfigureAPITools.normalizeChoices(state, NMRFETools.apiChoices(), 'NMRFETools:invalidChoice');
                state = NMRFETools.refreshPreML(NM, state, varind, fusionFlag);
                state = NMRFETools.normalizeState(NM, state, varind, fusionFlag);
                NM = NMRFETools.applyToNM(NM, state, varind, fusionFlag);
                if isempty(report.message), report.message = 'NMRFETools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public feature-selection/RFE configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMRFETools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted feature-selection/RFE configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.RFE or STRAT{i}.RFE. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.VarIndex = 'Modality/strategy index where applicable.';
            opts.FusionFlag = 'Fusion flag where applicable.';
            classifications = NMRFETools.filterMethodLabels('classification');
            regressions = NMRFETools.filterMethodLabels('regression');
            hFilter = struct();
            hFilter.classification = struct('symbol',classifications(:,2)', ...
                'code',num2cell([classifications{:,1}]), 'description',classifications(:,2)');
            hFilter.regression = struct('symbol',regressions(:,2)', ...
                'code',num2cell([regressions{:,1}]), 'description',regressions(:,2)');
            wrapperLabels = cell(1,5);
            for k = 1:5
                wrapperLabels{k} = NMRFETools.wrapperMethodLabel(struct('type',k));
            end
            hWrapper = struct('symbol',wrapperLabels, 'code',num2cell(1:5), ...
                'description',wrapperLabels);
            opts.Filter.type.classification = NMConfigureAPITools.choiceText(hFilter.classification);
            opts.Filter.type.regression = NMConfigureAPITools.choiceText(hFilter.regression);
            opts.Wrapper.type = NMConfigureAPITools.choiceText(hWrapper);
            h = NMConfigureAPITools.helpStruct('NMRFETools.cli_configure', ...
                '[NM, state, report] = NMRFETools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMRFETools.configure(NM, ''VarIndex'',1, ''Filter'',struct(''type'',''FEAST''));'}, struct());
            h.choices = NMRFETools.apiChoices();
            h.choices.Filter.type = hFilter;
            h.choices.Wrapper.type = hWrapper;
            paths = {'Filter.Pearson','Filter.SubSpaceStrategy','Wrapper.SubSpaceStrategy', ...
                'Filter.EnsembleStrategy.ConstructMode','Wrapper.EnsembleStrategy.ConstructMode', ...
                'Wrapper.datamode','Filter.PFE.Mode','Wrapper.PFE.Mode'};
            values = {h.choices.Filter.Pearson,h.choices.Filter.SubSpaceStrategy, ...
                h.choices.Wrapper.SubSpaceStrategy,h.choices.Filter.EnsembleStrategy.ConstructMode, ...
                h.choices.Wrapper.EnsembleStrategy.ConstructMode,h.choices.Wrapper.datamode, ...
                h.choices.Filter.PFE.Mode,h.choices.Wrapper.PFE.Mode};
            lines = cell(1,numel(paths));
            for j = 1:numel(paths)
                items = arrayfun(@(v)sprintf('''%s'' (%d): %s',v.symbol,v.code,v.description),values{j},'UniformOutput',false);
                lines{j} = sprintf('%s: %s',paths{j},strjoin(items,'; '));
            end
            h.options.nestedChoices = strjoin(lines,newline);
            h.scientificBlockSyntax = '[cfg] = NMRFETools.scientificConfig(NM, state, varind, fusionFlag);';
            h.validationRules = {'Filter.type choices depend on the effective classification/regression mode.'; ...
                'Nested RFE state remains in the inherited TrainParam.RFE.Filter and .Wrapper branches.'};
        end

        function choices = apiChoices()
            c = NMRFETools.NestedChoices;
            choices.Filter.Pearson = localRFEChoiceRecords(c.Pearson);
            choices.Filter.SubSpaceStrategy = localRFEChoiceRecords(c.SubSpaceStrategy);
            choices.Wrapper.SubSpaceStrategy = choices.Filter.SubSpaceStrategy;
            choices.Filter.EnsembleStrategy.ConstructMode = localRFEChoiceRecords(c.ConstructMode);
            choices.Wrapper.EnsembleStrategy.ConstructMode = choices.Filter.EnsembleStrategy.ConstructMode;
            choices.Wrapper.datamode = localRFEChoiceRecords(c.DataMode);
            choices.Filter.PFE.Mode = localRFEChoiceRecords(c.PFEMode);
            choices.Wrapper.PFE.Mode = choices.Filter.PFE.Mode;
        end

        function config = scientificConfig(NM, state, varind, fusionFlag)
            % Scientific, default-relative RFE block for public scripted configuration.
            % The owning RFE API alone determines which selected method's
            % parameters are scientifically active. cli_configure merges this
            % partial block with its canonical contextual defaults.
            defaults = NMRFETools.defaultSetting(NM, varind, fusionFlag);
            config = struct();
            if state.Filter.flag
                labels = NMRFETools.filterMethodLabels(NMAlternativeLabelTools.effectiveMode(NM));
                ix = find([labels{:,1}] == state.Filter.type);
                assert(isscalar(ix), 'NMRFETools:scientificFilter', ...
                    'The selected filter method is not supported for this prediction task.');
                method = labels{ix,2};
                settings = NMRFETools.scientificDifference(state.Filter, defaults.Filter);
                % A filter owns only the selected method's nested parameters.
                shelves = {'FEAST','MRMR','simba','gflip','imrelief','RGS','RSS','Relief'};
                switch state.Filter.type
                    case 1, selected = 'FEAST';
                    case 2, selected = 'MRMR';
                    case 4, selected = 'simba';
                    case 5, selected = 'gflip';
                    case 7, selected = 'imrelief';
                    case 10, selected = 'RGS';
                    case 11, selected = 'RSS';
                    case 12, selected = 'Relief';
                    otherwise, selected = '';
                end
                unused = setdiff(intersect(fieldnames(settings),shelves),{selected});
                settings = rmfield(settings,unused);
                if state.Filter.type ~= 3
                    settings = rmfield(settings,intersect(fieldnames(settings),{'Pearson'}));
                end
                if ~state.Filter.SubSpaceFlag
                    settings = rmfield(settings,intersect(fieldnames(settings), ...
                        {'SubSpaceStrategy','SubSpaceCrit','SubSpaceStepping','RankThresh'}));
                end
                if ~state.Filter.PFE.flag
                    settings = rmfield(settings,intersect(fieldnames(settings),{'PFE'}));
                end
                if state.Filter.EnsembleStrategy.type == 0
                    settings = rmfield(settings,intersect(fieldnames(settings),{'EnsembleStrategy'}));
                elseif any(strcmp(fieldnames(settings),'EnsembleStrategy'))
                    e = settings.EnsembleStrategy;
                    e = rmfield(e,intersect(fieldnames(e),{'type','DivStr','DivFunc','OptFunc'}));
                    settings.EnsembleStrategy = e;
                end
                config.Filter = NMRFETools.scientificBranch(settings,method);
            end
            if state.Wrapper.flag
                settings = NMRFETools.scientificDifference(state.Wrapper, defaults.Wrapper);
                shelves = {'GreedySearch','SA','GA','PSO','PFA'};
                selected = shelves{state.Wrapper.type};
                unused = setdiff(intersect(fieldnames(settings),shelves),{selected});
                settings = rmfield(settings,unused);
                if state.Wrapper.type == 1 && any(strcmp(fieldnames(settings),'GreedySearch'))
                    greedy = settings.GreedySearch;
                    if ~state.Wrapper.GreedySearch.AdRef.Enable
                        greedy = rmfield(greedy,intersect(fieldnames(greedy),{'AdRef'}));
                    end
                    if ~state.Wrapper.GreedySearch.PERM.flag
                        greedy = rmfield(greedy,intersect(fieldnames(greedy),{'PERM'}));
                    end
                    settings.GreedySearch = greedy;
                end
                if ~state.Wrapper.SubSpaceFlag
                    settings = rmfield(settings,intersect(fieldnames(settings), ...
                        {'SubSpaceStrategy','SubSpaceCrit','SubSpaceStepping'}));
                end
                if ~state.Wrapper.PFE.flag
                    settings = rmfield(settings,intersect(fieldnames(settings),{'PFE'}));
                end
                if state.Wrapper.EnsembleStrategy.type == 0
                    settings = rmfield(settings,intersect(fieldnames(settings),{'EnsembleStrategy'}));
                elseif any(strcmp(fieldnames(settings),'EnsembleStrategy'))
                    e = settings.EnsembleStrategy;
                    e = rmfield(e,intersect(fieldnames(e),{'type','DivStr','DivFunc','OptFunc'}));
                    settings.EnsembleStrategy = e;
                end
                config.Wrapper = NMRFETools.scientificBranch(settings, ...
                    NMRFETools.wrapperMethodLabel(state.Wrapper));
            end
            if ~isempty(fieldnames(config))
                if state.ClassRetrain ~= defaults.ClassRetrain
                    config.ClassRetrain = state.ClassRetrain;
                end
                if state.RetrainImmediate ~= defaults.RetrainImmediate
                    config.RetrainImmediate = state.RetrainImmediate;
                end
                config = NMRFETools.scientificSymbols(config, NMRFETools.apiChoices());
            end
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the feature-selection/RFE branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMRFETools.cli_configureHelp();
        end

        function state = refreshPreML(NM, state, varind, fusionFlag)
            % refreshPreML  Refresh preprocessing optimization metadata at RFE configurator entry.
            %
            % Uses the already-materialized legacy PREPROC branch and the inherited
            % nk_GenPreML authority. This operation is intentionally separate from
            % ordinary RFE state construction so menu/canvas reads do not regenerate
            % preprocessing parameter chains. Generator failures propagate.
            TP = NM.TrainParam;
            if fusionFlag == 3
                PREPROC = TP.STRAT{varind}.PREPROC;
            elseif isfield(TP,'ActiveModality')
                PREPROC = TP.PREPROC{TP.ActiveModality};
            else
                PREPROC = TP.PREPROC;
            end
            [~, state.PreML] = nk_GenPreML(PREPROC);
            state.rfeCanWrapperOpt = NMRFETools.canWrapperOpt(NM, state, varind, fusionFlag);
        end

        function state = stateFromNM(NM, varind, fusionFlag)
            % stateFromNM  Reconstruct feature-selection/RFE browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.RFE or STRAT{i}.RFE and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            [RFE, present] = NMRFETools.extractRFE(NM, varind, fusionFlag);
            RFE = NMRFETools.completeDefaults(RFE, NM);
            RFE = NMRFETools.enforceEnsembleActivation(RFE);
            state = RFE;
            state.rfePresent = present;
            state.rfeDirty = false;
            state.rfeModeFlag = NMAlternativeLabelTools.effectiveMode(NM);
            state.rfeCanWrapperOpt = NMRFETools.canWrapperOpt(NM, RFE, varind, fusionFlag);
            state.rfeCanRetrainImmediate = NMRFETools.canRetrainImmediate(NM, RFE, varind, fusionFlag);
            [state.rfeIsMulticlass, ~, ~] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            state.rfeScopeLabel = NMRFETools.scopeLabel(varind, fusionFlag);
        end


        function RFE = defaultSetting(NM, varind, fusionFlag)
            % defaultSetting  Public legacy default for nk_RFE_config.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            RFE = NMRFETools.completeDefaults(struct(), NM);
        end

        function state = stateFromMenu(NM, current, menuState, varind, fusionFlag)
            % stateFromMenu  Translate browser feature-selection/RFE controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            if nargin < 2 || isempty(current) || ~isstruct(current)
                current = NMRFETools.stateFromNM(NM, varind, fusionFlag);
            end
            state = current;
            if isfield(menuState,'rfe') && isstruct(menuState.rfe)
                src = menuState.rfe;
            else
                src = menuState;
            end
            skip = {'rfePresent','rfeDirty','rfeModeFlag','rfeCanWrapperOpt','rfeCanRetrainImmediate','rfeIsMulticlass','rfeScopeLabel'};
            fn = fieldnames(src);
            for i = 1:numel(fn)
                if any(strcmp(fn{i}, skip)) || any(strcmp(fn{i}, {'Filter','Wrapper','CV2Class','ClassRetrain','RetrainImmediate','dispres','PreML'}))
                    state.(fn{i}) = src.(fn{i});
                end
            end
            if isfield(src,'rfeDirty'), state.rfeDirty = logical(src.rfeDirty); end
            if isfield(current,'rfePresent'), state.rfePresent = logical(current.rfePresent); end
            state = NMRFETools.normalizeState(NM, state, varind, fusionFlag);
        end

        function state = normalizeState(NM, state, varind, fusionFlag)
            % normalizeState  Enforce valid feature-selection/RFE state values before legacy materialization.
            %
            % Coerces booleans/enums/numeric options, repairs invalid or unavailable choices and derives context-sensitive defaults. applyToNM expects this normalized state.
            %
            % state.rfeCanRetrainImmediate: carries the rfe can retrain immediate value between browser/API state and legacy NeuroMiner structures.
            % state.rfeCanWrapperOpt: carries the rfe can wrapper opt value between browser/API state and legacy NeuroMiner structures.
            % state.rfeDirty: carries the rfe dirty value between browser/API state and legacy NeuroMiner structures.
            % state.rfeIsMulticlass: carries the rfe is multiclass value between browser/API state and legacy NeuroMiner structures.
            % state.rfeModeFlag: carries the rfe mode flag value between browser/API state and legacy NeuroMiner structures.
            % state.rfePresent: carries the rfe present value between browser/API state and legacy NeuroMiner structures.
            % state.rfeScopeLabel: carries the rfe scope label value between browser/API state and legacy NeuroMiner structures.
            present = isfield(state,'rfePresent') && logical(state.rfePresent);
            dirty = isfield(state,'rfeDirty') && logical(state.rfeDirty);
            RFE = NMRFETools.rfeFromState(NM, state, varind, fusionFlag);
            state = RFE;
            state.rfePresent = present;
            state.rfeDirty = dirty;
            state.rfeModeFlag = NMAlternativeLabelTools.effectiveMode(NM);
            state.rfeCanWrapperOpt = NMRFETools.canWrapperOpt(NM, RFE, varind, fusionFlag);
            state.rfeCanRetrainImmediate = NMRFETools.canRetrainImmediate(NM, RFE, varind, fusionFlag);
            [state.rfeIsMulticlass, ~, ~] = NMAlternativeLabelTools.effectiveClassInfo(NM);
            state.rfeScopeLabel = NMRFETools.scopeLabel(varind, fusionFlag);
        end

        function RFE = rfeFromState(NM, state, varind, fusionFlag)
            % rfeFromState  Convert normalized feature-selection state into a legacy RFE struct.
            %
            % Builds the backend RFE/filter/wrapper configuration for either global or STRAT-scoped storage. Browser-only dirty and label fields are omitted before applyToNM writes the branch.
            if nargin < 2 || isempty(state) || ~isstruct(state), state = struct(); end
            RFE = rmfield_safe(state, {'rfePresent','rfeDirty','rfeModeFlag','rfeCanWrapperOpt', ...
                'rfeCanRetrainImmediate','rfeIsMulticlass','rfeScopeLabel','rfePFEEligibility'});
            RFE = NMRFETools.completeDefaults(RFE, NM);
            RFE.Filter.flag = double(logical(round(double(RFE.Filter.flag))));
            RFE.Wrapper.flag = double(logical(round(double(RFE.Wrapper.flag))));
            RFE.Filter.SubSpaceFlag = double(logical(round(double(RFE.Filter.SubSpaceFlag))));
            RFE.Wrapper.SubSpaceFlag = double(logical(round(double(RFE.Wrapper.SubSpaceFlag))));
            if ~(RFE.Filter.flag && RFE.Filter.SubSpaceFlag)
                RFE.Wrapper.SubSpaceFlag = 0;
            end
            RFE.Filter = NMRFETools.sanitizeBranchEnsemble(RFE.Filter, NMAlternativeLabelTools.effectiveMode(NM));
            RFE.Wrapper = NMRFETools.sanitizeBranchEnsemble(RFE.Wrapper, NMAlternativeLabelTools.effectiveMode(NM));
            RFE = NMRFETools.enforceEnsembleActivation(RFE);
            if ~NMRFETools.canRetrainImmediate(NM, RFE, varind, fusionFlag)
                RFE.RetrainImmediate = 0;
            end
            RFE.CV2Class.type = 2;
            if ~isfield(RFE.CV2Class,'EnsembleStrategy') || ~isstruct(RFE.CV2Class.EnsembleStrategy)
                RFE.CV2Class.EnsembleStrategy = NMRFETools.defaultEnsemble(NM);
            end
            RFE.CV2Class.EnsembleStrategy.type = 0;
            if strcmpi(NMAlternativeLabelTools.effectiveMode(NM),'regression')
                RFE.CV2Class.EnsembleStrategy.Metric = 2;
            end
        end

        function NM = applyToNM(NM, state, varind, fusionFlag)
            % applyToNM  Materialize feature-selection/RFE settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.RFE or STRAT{i}.RFE at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.rfeDirty: carries the rfe dirty value between browser/API state and legacy NeuroMiner structures.
            % state.rfePresent: carries the rfe present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = 1; end
            present = isfield(state,'rfePresent') && logical(state.rfePresent);
            dirty = isfield(state,'rfeDirty') && logical(state.rfeDirty);
            if ~(present || dirty), return; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            RFE = NMRFETools.rfeFromState(NM, state, varind, fusionFlag);
            if any(strcmp(fieldnames(RFE),'PreML'))
                RFE = rmfield(RFE,'PreML');
            end
            if fusionFlag == 3
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1, max(1,varind));
                end
                if numel(NM.TrainParam.STRAT) < varind, NM.TrainParam.STRAT{varind} = []; end
                if isempty(NM.TrainParam.STRAT{varind}) || ~isstruct(NM.TrainParam.STRAT{varind})
                    NM.TrainParam.STRAT{varind} = struct();
                end
                NM.TrainParam.STRAT{varind}.RFE = RFE;
            else
                NM.TrainParam.RFE = RFE;
            end
        end

        function text = summary(state)
            % summary  Render a concise human-readable feature-selection/RFE configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            %
            % state.Filter: carries the filter value between browser/API state and legacy NeuroMiner structures.
            % state.Wrapper: carries the wrapper value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                text = 'Ensemble learning strategies are not configured.'; return;
            end
            flt = isfield(state,'Filter') && isstruct(state.Filter) && isfield(state.Filter,'flag') && logical(state.Filter.flag);
            wrp = isfield(state,'Wrapper') && isstruct(state.Wrapper) && isfield(state.Wrapper,'flag') && logical(state.Wrapper.flag);
            if ~flt && ~wrp
                text = 'Filter- and wrapper-based ensemble learning disabled.';
                return;
            end
            parts = {};
            if flt
                parts{end+1} = ['Filter: ' NMRFETools.filterMethodLabel(state.Filter)]; %#ok<AGROW>
            end
            if wrp
                parts{end+1} = ['Wrapper: ' NMRFETools.wrapperMethodLabel(state.Wrapper)]; %#ok<AGROW>
            end
            text = strjoin(parts, '; ');
        end

        function labels = filterMethodLabels(modeflag)
            % filterMethodLabels  Return feature-selection method labels valid for the task mode.
            %
            % Filters legacy RFE/filter/wrapper display choices according to classification or regression context. The method is read-only and supports UI/API option construction.
            if strcmpi(modeflag,'regression')
                labels = {1,'FEAST';2,'MRMR';3,'Pearson/Spearman';10,'RGS';9,'Increasing feature subspace cardinality';11,'Random subspace sampling';12,'Relief'};
            else
                labels = {1,'FEAST';2,'MRMR';3,'Pearson/Spearman';4,'Simba';5,'Gflip';7,'IMRelief';9,'Increasing feature subspace cardinality';11,'Random subspace sampling';12,'Relief';13,'FScore'};
            end
        end
    end

    methods (Static, Access = private)
        function result = scientificBranch(settings, method)
            result = struct('flag',true,'type',method);
            names = setdiff(fieldnames(settings),{'flag','type'},'stable');
            for k = 1:numel(names)
                result.(names{k}) = settings.(names{k});
            end
        end

        function delta = scientificDifference(actual, defaults)
            % Contextual default comparison, recursively retaining changed
            % settings without serializing the full inherited RFE shelf.
            delta = struct();
            fields = fieldnames(actual);
            for k = 1:numel(fields)
                key = fields{k};
                current = actual.(key);
                baseline = defaults.(key);
                if isequaln(current,baseline), continue; end
                if strcmp(class(current),'struct') && strcmp(class(baseline),'struct') && ...
                        isscalar(current) && isscalar(baseline)
                    nested = NMRFETools.scientificDifference(current,baseline);
                    if ~isempty(fieldnames(nested)), delta.(key) = nested; end
                else
                    delta.(key) = current;
                end
            end
        end

        function state = scientificSymbols(state, choices)
            % Reverse lookup uses only the RFE owner's existing API vocabulary.
            names = intersect(fieldnames(choices),fieldnames(state),'stable');
            for k = 1:numel(names)
                key = names{k};
                entry = choices.(key);
                if isscalar(entry) && ~any(strcmp(fieldnames(entry),'symbol'))
                    state.(key) = NMRFETools.scientificSymbols(state.(key),entry);
                else
                    value = state.(key);
                    codes = {entry.code};
                    match = find(cellfun(@(c)isequaln(c,value),codes));
                    assert(isscalar(match),'NMRFETools:scientificSymbol', ...
                        'No unique declared symbolic choice for %s.',key);
                    state.(key) = entry(match).symbol;
                end
            end
        end

        function [RFE, present] = extractRFE(NM, varind, fusionFlag)
            RFE = struct(); present = false;
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if fusionFlag == 3 && isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && ...
                    isstruct(TP.STRAT{varind}) && isfield(TP.STRAT{varind},'RFE') && isstruct(TP.STRAT{varind}.RFE)
                RFE = TP.STRAT{varind}.RFE; present = true; return;
            end
            if isfield(TP,'RFE') && isstruct(TP.RFE)
                RFE = TP.RFE; present = true;
            end
        end

        function RFE = completeDefaults(RFE, NM)
            if nargin < 1 || isempty(RFE) || ~isstruct(RFE), RFE = struct(); end
            mode = NMAlternativeLabelTools.effectiveMode(NM);
            if ~isfield(RFE,'Filter') || ~isstruct(RFE.Filter)
                RFE.Filter = NMRFETools.defaultFilter(NM, mode);
            else
                RFE.Filter = NMRFETools.mergeStruct(NMRFETools.defaultFilter(NM, mode), RFE.Filter);
            end
            if ~isfield(RFE,'Wrapper') || ~isstruct(RFE.Wrapper)
                RFE.Wrapper = NMRFETools.defaultWrapper(NM, mode);
            else
                RFE.Wrapper = NMRFETools.mergeStruct(NMRFETools.defaultWrapper(NM, mode), RFE.Wrapper);
            end
            if ~isfield(RFE,'CV2Class') || ~isstruct(RFE.CV2Class), RFE.CV2Class = struct(); end
            if ~isfield(RFE.CV2Class,'type') || isempty(RFE.CV2Class.type), RFE.CV2Class.type = 2; end
            if ~isfield(RFE.CV2Class,'EnsembleStrategy') || ~isstruct(RFE.CV2Class.EnsembleStrategy)
                RFE.CV2Class.EnsembleStrategy = NMRFETools.defaultEnsemble(NM);
            else
                RFE.CV2Class.EnsembleStrategy = NMRFETools.mergeStruct(NMRFETools.defaultEnsemble(NM), RFE.CV2Class.EnsembleStrategy);
            end
            if ~isfield(RFE.CV2Class.EnsembleStrategy,'AggregationLevel') || isempty(RFE.CV2Class.EnsembleStrategy.AggregationLevel)
                RFE.CV2Class.EnsembleStrategy.AggregationLevel = 1;
            end
            % The inherited noninteractive default used 2; both 1 and 2 select the grand ensemble.
            if RFE.CV2Class.EnsembleStrategy.AggregationLevel == 2
                RFE.CV2Class.EnsembleStrategy.AggregationLevel = 1;
            end
            if ~isfield(RFE,'ClassRetrain') || isempty(RFE.ClassRetrain), RFE.ClassRetrain = 1; end
            if ~isfield(RFE,'RetrainImmediate') || isempty(RFE.RetrainImmediate), RFE.RetrainImmediate = 0; end
            if ~isfield(RFE,'dispres') || isempty(RFE.dispres), RFE.dispres = 1; end
            RFE.Filter.type = NMRFETools.allowedScalar(RFE.Filter.type, NMRFETools.defaultFilterType(mode), NMRFETools.allowedFilterTypes(mode));
            RFE.Wrapper.type = NMRFETools.allowedScalar(RFE.Wrapper.type, 1, 1:5);
            RFE.Filter = NMRFETools.sanitizeBranchEnsemble(RFE.Filter, mode);
            RFE.Wrapper = NMRFETools.sanitizeBranchEnsemble(RFE.Wrapper, mode);
        end

        function Filter = defaultFilter(NM, mode)
            Filter = struct();
            Filter.flag = 0;
            Filter.MinNum = 1;
            Filter.type = NMRFETools.defaultFilterType(mode);
            Filter.Pearson = 1;
            Filter.binmode = 1;
            Filter.CostFun = NMRFETools.defaultCostFun(NM);
            Filter.SubSpaceFlag = 1;
            Filter.RankThresh = 95;
            Filter.SubSpaceStrategy = 1;
            Filter.SubSpaceCrit = 0;
            Filter.EnsembleStrategy = NMRFETools.defaultEnsemble(NM);
            Filter.SubSpaceStepping = 0;
            Filter.PFE = NMRFETools.defaultPFE();
            Filter.FEAST = NMRFETools.defaultFEAST();
            Filter.MRMR = NMRFETools.defaultMRMR();
            Filter.simba = NMRFETools.defaultSimba();
            Filter.gflip = NMRFETools.defaultGflip();
            Filter.imrelief = {NMRFETools.defaultIMRelief()};
            Filter.RGS = NMRFETools.defaultRGS();
            Filter.RSS = NMRFETools.defaultRSS();
            Filter.Relief.k = 10;
        end

        function Wrapper = defaultWrapper(NM, mode)
            Wrapper = struct();
            Wrapper.flag = 0;
            Wrapper.optflag = 2;
            Wrapper.type = 1;
            Wrapper.datamode = 2;
            Wrapper.CostFun = 2;
            Wrapper.SubSpaceFlag = 0;
            Wrapper.SubSpaceStrategy = 1;
            Wrapper.SubSpaceCrit = 0;
            Wrapper.SubSpaceStepping = 0;
            Wrapper.GreedySearch = NMRFETools.defaultGreedySearch();
            Wrapper.SA = struct('c',0.95,'T',1,'T_stop',1e-6,'alpha',1,'itt_max',100,'Rep_T_max',10,'Rep_accept_max',10,'kc',1);
            Wrapper.GA = struct('N',20,'max_Iter',50,'CR',0.8,'MR',0.05);
            Wrapper.PSO = struct('N',20,'max_Iter',50,'c1',2,'c2',2,'w',0.9,'lb',0,'ub',1,'thres',0.5);
            Wrapper.PFA = struct('N',20,'max_Iter',50,'lb',0,'ub',1,'thres',0.5);
            Wrapper.EnsembleStrategy = NMRFETools.defaultEnsemble(NM);
            Wrapper.PFE = NMRFETools.defaultPFE();
        end

        function E = defaultEnsemble(NM) %#ok<INUSD>
            E = struct();
            E.type = 0; E.Metric = 2; E.Mode = 4; E.MinNum = 1; E.Perc = 75; E.DataType = 2;
            E.Weighting = 0; E.DivCrit = 2; E.ConstructMode = 0; E.DivStr = ''; E.DivFunc = '';
            E.OptFunc = ''; E.EntropRegMode = 1; E.CompFunc = 'max'; E.DiversitySource = 'entropy';
            E.DiversityObjective = [];
            E.PerfSlackPct = 0; E.EntropyWeight = 2; E.SizePenalty = 0; E.Patience = 0;
            E.DiversityEps = 0.02;
            E.Boosting = struct('mode','ridge','lambda',1e-3,'alpha',0,'useLogits',false,'wThreshold',0, ...
                'clip',1e-7,'eta',0.3,'T',200,'shareWeights',false, ...
                'Kernel',struct('regMode','residual-cov','diagMode','one','scaleTo','HHT','autoAlpha',false,'tau',0.10));
        end

        function Branch = sanitizeBranchEnsemble(Branch, mode)
            if ~isstruct(Branch), return; end
            if ~isfield(Branch,'SubSpaceStrategy') || isempty(Branch.SubSpaceStrategy), Branch.SubSpaceStrategy = 1; end
            if ~isfield(Branch,'SubSpaceCrit') || isempty(Branch.SubSpaceCrit), Branch.SubSpaceCrit = 0; end
            Branch.SubSpaceStrategy = NMRFETools.allowedScalar(Branch.SubSpaceStrategy, 1, 1:4);
            if ~isfield(Branch,'EnsembleStrategy') || ~isstruct(Branch.EnsembleStrategy)
                Branch.EnsembleStrategy = NMRFETools.defaultEnsemble(struct('modeflag',mode));
            else
                Branch.EnsembleStrategy = NMRFETools.mergeStruct(NMRFETools.defaultEnsemble(struct('modeflag',mode)), Branch.EnsembleStrategy);
            end
            E = Branch.EnsembleStrategy;
            if ~isfield(E,'ConstructMode') || isempty(E.ConstructMode), E.ConstructMode = 0; end
            E.ConstructMode = round(double(E.ConstructMode));
            if ~ismember(E.ConstructMode,[0 1 2 4 5]), E.ConstructMode = 0; end
            if ~isfield(E,'DivCrit') || isempty(E.DivCrit), E.DivCrit = 2; end
            E.DivCrit = round(double(E.DivCrit));
            if strcmpi(mode,'regression')
                if ~ismember(E.DivCrit,[2 5]), E.DivCrit = 2; end
                E.DiversitySource = 'regvar';
            elseif ~ismember(E.DivCrit,[1 2 3 4])
                E.DivCrit = 2;
            end
            if ~isfield(E,'DiversitySource') || isempty(E.DiversitySource)
                if strcmpi(mode,'classification'), E.DiversitySource = 'entropy'; else, E.DiversitySource = 'regvar'; end
            end
            if ~isfield(E,'DiversityObjective'), E.DiversityObjective = []; end
            if ~isfield(E,'DiversityEps') || isempty(E.DiversityEps), E.DiversityEps = 0.02; end
            E = NMRFETools.deriveEnsembleObjective(E, mode);
            switch E.ConstructMode
                case 0
                    E.type = 0;
                case 1
                    if strcmpi(E.OptFunc,'CVMax'), E.type = 2; else, E.type = 1; end
                case 2
                    if strcmpi(E.OptFunc,'CVMax'), E.type = 6; else, E.type = 5; end
                case 4
                    E.type = 9;
                    E.Mode = 4;
                    E.Weighting = 0;
                case 5
                    E.type = 10;
            end
            if strcmpi(mode,'regression')
                if E.ConstructMode == 5
                    E.Boosting.mode = 'ridge';
                    E.Boosting.useLogits = false;
                end
                if E.type ~= 9
                    E.Metric = 1;
                    E.DiversitySource = 'regvar';
                end
            end
            Branch.EnsembleStrategy = E;
        end

        function RFE = enforceEnsembleActivation(RFE)
            % enforceEnsembleActivation  Materialize inactive RFE ensemble branches with legacy type zero.
            %
            % EnsembleStrategy.type is the authoritative legacy runtime selector used by training code.
            % ConstructMode and the remaining branch settings are retained as dormant configuration so a
            % user can reactivate the branch without losing prior choices. Wrapper subspace ensembles are
            % valid only while the filter subspace branch is active.
            if ~logical(RFE.Filter.flag), RFE.Filter.PFE.flag = 0; end
            if ~logical(RFE.Wrapper.flag), RFE.Wrapper.PFE.flag = 0; end
            filterActive = logical(RFE.Filter.flag) && logical(RFE.Filter.SubSpaceFlag);
            if ~filterActive
                RFE.Filter.EnsembleStrategy.type = 0;
                RFE.Wrapper.SubSpaceFlag = 0;
            end
            wrapperActive = filterActive && logical(RFE.Wrapper.flag) && logical(RFE.Wrapper.SubSpaceFlag);
            if ~wrapperActive
                RFE.Wrapper.EnsembleStrategy.type = 0;
            end
        end

        function E = deriveEnsembleObjective(E, mode)
            if strcmpi(mode,'regression')
                if E.DivCrit == 5
                    E.DivFunc = 'nk_RegAmbig';
                    E.OptFunc = 'DiversityMax';
                    E.DiversitySource = 'regvar';
                    E.DivStr = 'Regression ambiguity (dispersion around ensemble mean)';
                else
                    E.DivCrit = 2;
                    E.DivFunc = 'nk_RegAmbig';
                    E.OptFunc = 'CVMax';
                    E.DiversitySource = 'regvar';
                    E.DivStr = 'prediction performance + regression ambiguity';
                end
                return;
            end
            switch E.DivCrit
                case 1
                    E.DivFunc = 'nk_Entropy';
                    E.OptFunc = 'DiversityMax';
                    E.DiversitySource = 'entropy';
                    E.DiversityObjective = 'H';
                    E.DivStr = 'vote-entropy';
                case 2
                    switch lower(char(string(E.DiversitySource)))
                        case 'kappaa',  E.DivFunc = 'nk_Diversity';      E.DivStr = 'prediction performance + (1 - double-fault A)';
                        case 'kappaq',  E.DivFunc = 'nk_Diversity';      E.DivStr = 'prediction performance + (-Q)';
                        case 'kappaf',  E.DivFunc = 'nk_DiversityKappa'; E.DivStr = 'prediction performance + (1 - Fleiss kappa)/2';
                        case 'lobag',   E.DivFunc = 'nk_Lobag';          E.DivStr = 'prediction performance + (-LoBag ED)';
                        otherwise,      E.DivFunc = 'nk_Entropy';        E.DivStr = 'prediction performance + vote-entropy'; E.DiversitySource = 'entropy';
                    end
                    E.OptFunc = 'CVMax';
                    E.DiversityObjective = [];
                case 3
                    if isempty(E.DiversityObjective)
                        switch lower(char(string(E.DiversitySource)))
                            case 'kappaa', E.DiversityObjective = 'A';
                            case 'kappaf', E.DiversityObjective = 'K';
                            otherwise,     E.DiversityObjective = 'Q'; E.DiversitySource = 'kappaq';
                        end
                    end
                    switch upper(char(string(E.DiversityObjective)))
                        case 'A'
                            E.DivFunc = 'nk_Diversity'; E.DivStr = 'Double-fault A (minimize A)'; E.DiversitySource = 'kappaa';
                        case 'K'
                            E.DivFunc = 'nk_DiversityKappa'; E.DivStr = 'Fleiss kappa (minimize kappa)'; E.DiversitySource = 'kappaf';
                        otherwise
                            E.DivFunc = 'nk_Diversity'; E.DivStr = 'Yule Q (minimize Q)'; E.DiversityObjective = 'Q'; E.DiversitySource = 'kappaq';
                    end
                    E.OptFunc = 'DiversityMax';
                case 4
                    E.DivFunc = 'nk_Lobag';
                    E.OptFunc = 'DiversityMax';
                    E.DiversitySource = 'lobag';
                    E.DiversityObjective = 'L';
                    E.DivStr = 'LoBag error diversity (minimize ED)';
                otherwise
                    E.DivCrit = 2;
                    E = NMRFETools.deriveEnsembleObjective(E, mode);
            end
        end

        function P = defaultPFE()
            P = struct('flag',0,'Mode',1,'Perc',90,'TolWin',25,'MinNum',1,'PruneFlag',true);
        end

        function G = defaultGreedySearch()
            G = struct();
            G.Direction = 1;
            G.EarlyStop = struct('Thresh',50,'Perc',1);
            G.WeightSort = 1;
            G.CritGap = struct('flag',2,'crit',10);
            G.FeatStepPerc = 0;
            G.FeatRandPerc = 0;
            G.KneePointDetection = 2;
            G.MultiClassOptimization = 1;
            G.PreSort = 1;
            G.PERM = struct('flag',0,'nperms',100);
            G.AdRef = NMRFETools.defaultAdRef();
        end

        function A = defaultAdRef()
            A = struct();
            A.Enable = false; A.lambda = 0.5; A.kNN = 20; A.gamma = 0.98; A.eta0 = 1e-3; A.eta1 = 5e-3; A.rmax = 10;
            A.c = 0.55; A.w = 0.15; A.beta_well = 1; A.beta_hi = 1; A.sigma_lo = A.w/3; A.sigma_hi = 0.06;
            A.Stop = struct('Enable',true,'TauAbs',1e-4,'UseMAD',true,'MADWinsz',8,'Zmad',2,'Patience',0);
            A.Auto = struct('Enable',false,'LambdaC',0.8,'HalfLife',10,'TargetBumpS',0.90,'TargetBump',0.10,'AutoKNN',true,'ZeroTauAbs',true);
        end

        function F = defaultFEAST()
            F = struct('Method',1,'MethodStr','mim','NumFeat',10,'cmd','discretize', ...
                'DISCRET',struct('binstart',2,'binsteps',1,'binstop',5), ...
                'SYMBOL',struct('symMinBin',4,'symMaxBin',16,'symSeqLength',5,'symStdNum',2));
        end

        function M = defaultMRMR()
            M = struct('mRMRscheme',1,'NumFeat',10,'cmd','discretize', ...
                'DISCRET',struct('binstart',2,'binsteps',1,'binstop',5), ...
                'SYMBOL',struct('symMinBin',4,'symMaxBin',16,'symSeqLength',5,'symStdNum',2));
        end

        function S = defaultSimba()
            S.extra_param = struct('start_points',1,'max_iter',5,'iter_abort_crit',100,'block_size',1,'beta','auto','utility','linear');
            S.gpu = false; S.utilfunc = 1;
        end

        function G = defaultGflip()
            G.extra_param = struct('start_points',1,'max_iter',5,'block_size',1,'beta','auto','utility','linear');
            G.gpu = false; G.utilfunc = 2; G.limfeat = 2;
        end

        function I = defaultIMRelief()
            I = struct('distance','block','sigma',2,'lambda',0.1,'maxiter',10,'plotfigure',false,'desc','IMRelief');
        end

        function R = defaultRGS()
            R.extra_param = struct('num_starts',2,'epochs',1,'verbose',true);
        end

        function R = defaultRSS()
            R = struct('nperms',50,'nMinFeatsPerc',10,'nMaxFeatsPerc',90);
        end

        function tf = canWrapperOpt(NM, RFE, varind, fusionFlag)
            GRD = NMRFETools.extractGRD(NM, varind, fusionFlag);
            tf = prod(double(GRD.n_params)) > 1;
            if tf || ~isfield(RFE,'PreML') || isempty(RFE.PreML), return; end
            tf = numel(RFE.PreML.Params) > 1 || numel(RFE.PreML.Params{1}) > 1;
        end

        function tf = canRetrainImmediate(NM, RFE, varind, fusionFlag)
            GRD = NMRFETools.extractGRD(NM, varind, fusionFlag);
            nparams = 1;
            try
                if isfield(GRD,'n_params'), nparams = prod(double(GRD.n_params)); end
            catch
                nparams = 1;
            end
            tf = nparams <= 1 && isfield(RFE,'Filter') && isfield(RFE.Filter,'flag') && ~logical(RFE.Filter.flag) && ...
                isfield(RFE,'Wrapper') && isfield(RFE.Wrapper,'flag') && ~logical(RFE.Wrapper.flag);
        end

        function GRD = extractGRD(NM, varind, fusionFlag)
            GRD = struct('n_params',1);
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if fusionFlag == 3 && isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && ...
                    isstruct(TP.STRAT{varind}) && isfield(TP.STRAT{varind},'GRD')
                GRD = TP.STRAT{varind}.GRD;
            elseif isfield(TP,'GRD')
                GRD = TP.GRD;
            end
            if ~isfield(GRD,'n_params'), GRD.n_params = 1; end
        end


        function label = scopeLabel(varind, fusionFlag)
            if fusionFlag == 3
                label = sprintf('late-fusion STRAT{%d}.RFE', varind);
            else
                label = 'global NM.TrainParam.RFE';
            end
        end

        function t = defaultFilterType(mode)
            if strcmpi(mode,'regression'), t = 2; else, t = 3; end
        end

        function a = allowedFilterTypes(mode)
            if strcmpi(mode,'regression'), a = [1 2 3 9 10 11 12]; else, a = [1 2 3 4 5 7 9 11 12 13]; end
        end

        function c = defaultCostFun(NM)
            c = 2;
            try
                SVM = NM.TrainParam.SVM;
                if isfield(SVM,'kernel') && isfield(SVM.kernel,'kernstr') && strcmp(char(SVM.kernel.kernstr),' -s 0')
                    c = 3;
                end
            catch
            end
        end

        function v = allowedScalar(v, default, allowed)
            v = round(double(v));
            if isempty(v) || ~isscalar(v) || ~isfinite(v) || ~ismember(v, allowed), v = default; end
        end

        function label = filterMethodLabel(Filter)
            map = containers.Map([1 2 3 4 5 7 9 10 11 12 13], ...
                {'FEAST','MRMR','Pearson/Spearman','Simba','Gflip','IMRelief','Increasing subspace cardinality','RGS','Random subspace sampling','Relief','FScore'});
            t = 3;
            if isfield(Filter,'type'), t = round(double(Filter.type)); end
            if isKey(map,t), label = map(t); else, label = sprintf('method %d', t); end
        end

        function label = wrapperMethodLabel(Wrapper)
            names = {'Greedy search','Simulated annealing','Genetic algorithm','Particle swarm optimization','Path finder algorithm'};
            t = 1;
            if isfield(Wrapper,'type'), t = NMRFETools.allowedScalar(Wrapper.type, 1, 1:5); end
            label = names{t};
        end

        function S = mergeStruct(S, T)
            if ~isstruct(T), return; end
            f = fieldnames(T);
            for i = 1:numel(f)
                k = f{i};
                if isstruct(T.(k)) && isfield(S,k) && isstruct(S.(k))
                    S.(k) = NMRFETools.mergeStruct(S.(k), T.(k));
                else
                    S.(k) = T.(k);
                end
            end
        end
    end
end


function records = localRFEChoiceRecords(C)
records = struct('symbol',C.symbol,'code',num2cell(C.code),'description',C.description);
end

function S = rmfield_safe(S, fields)
for i = 1:numel(fields)
    if isfield(S, fields{i}), S = rmfield(S, fields{i}); end
end
end
