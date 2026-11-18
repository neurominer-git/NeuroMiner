classdef NMSynthTools
% NMSynthTools
% -------------------------------------------------------------------------
% Browser-port helper for nk_Synth_config.m. The helper keeps UI-only fields
% out of NM.TrainParam.SYNTH and writes only the legacy SYNTH structure.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        MethodChoices = struct( ...
            'symbol', {'knn','adasyn','pcagauss','gmm','copula'}, ...
            'code', {1,2,3,4,5}, ...
            'description', {'k-nearest-neighbour interpolation','Adaptive synthetic sampling','PCA Gaussian sampling','Gaussian mixture model','Gaussian copula'})
        StandardizationChoices = struct( ...
            'symbol', {'standardize','already_standardized'}, ...
            'code', {1,2}, ...
            'description', {'Standardize before distance analysis','Data already standardized or standardization not needed'})
        StorageChoices = struct( ...
            'symbol', {'persist','regenerate'}, ...
            'code', {1,2}, ...
            'description', {'Persist generated samples on disk','Regenerate synthetic samples for each training run'})
        ComponentCriterionChoices = struct( ...
            'symbol', {'bic','aic'}, ...
            'code', {1,2}, ...
            'description', {'Bayesian information criterion','Akaike information criterion'})
        DistanceChoices = struct( ...
            'symbol', {'Euclidean','Manhattan','Cosine','Mahalanobis'}, ...
            'code', {'Euclidean','Manhattan','Cosine','Mahalanobis'}, ...
            'description', {'Euclidean distance','Manhattan distance', ...
                            'Cosine distance','Mahalanobis distance'})
    end

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the synthetic-data branch.
            %
            % Merges canonical state/name-value inputs with stateFromNM, normalizes and materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the established target NM.TrainParam.SYNTH and returns a structured report.
            
            defaultState = NMSynthTools.stateFromNM(NM);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.synthDirty = true; end
            try
                uiComponents = NMConfigureAPITools.optionValue(varargin,'synthNComponentsText',[]);
                if ~isequal(uiComponents,[]), state.synthNComponents = NMSynthTools.numericVector(uiComponents); end
                state = NMConfigureAPITools.normalizeChoices(state, NMSynthTools.apiChoices(), 'MATLAB:assertion:failed');
                state = NMSynthTools.normalizeState(state);
                NM = NMSynthTools.applyToNM(NM, state);
                if isempty(report.message), report.message = 'NMSynthTools configuration applied.'; end
            % nm2-allow: Public configure API returns failures through the structured report contract.
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public synthetic-data configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMSynthTools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted synthetic-data configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.SYNTH. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.synthDistanceMeasure = 'Select one canonical textual distance metric in h.choices.synthDistanceMeasure.';
            opts.synthK = 'Nearest-neighbour count (positive integer).';
            opts.synthNumSyntheticObservations = 'Number of generated observations (nonnegative integer).';
            opts.synthUncertaintyScale = 'Population uncertainty scale (nonnegative scalar; 0 retains fixed-distribution generation).';
            opts.synthNComponents = 'Gaussian-mixture component counts (numeric vector).';
            h = NMConfigureAPITools.helpStruct('NMSynthTools.cli_configure', ...
                '[NM, state, report] = NMSynthTools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMSynthTools.configure(NM, ''synthMethod'',''gmm'', ''synthMinMethod'',''bic'');'}, NMSynthTools.apiChoices());
            h.validationRules = {'Categorical selections are converted at the public API; TrainParam.SYNTH remains numeric.'; ...
                'Method-specific parameters retain their established numerical representation.'};
        end

        function choices = apiChoices()
            choices.synthMethod = NMSynthTools.MethodChoices;
            choices.synthStandardizeData = NMSynthTools.StandardizationChoices;
            choices.synthWrite2Disk = NMSynthTools.StorageChoices;
            choices.synthMinMethod = NMSynthTools.ComponentCriterionChoices;
            choices.synthDistanceMeasure = NMSynthTools.DistanceChoices;
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the synthetic-data branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMSynthTools.cli_configureHelp();
        end

        function state = stateFromNM(NM)
            % stateFromNM  Reconstruct synthetic-data browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.SYNTH and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            present = false;
            SYNTH = struct();
            % nm2-allow: NM1.4 workspaces can omit TrainParam or its SYNTH branch.
            if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'SYNTH')
                SYNTH = NM.TrainParam.SYNTH;
                validateattributes(SYNTH,{'struct'},{'scalar'}, ...
                    'NMSynthTools.stateFromNM','Persisted SYNTH');
                present = true;
            end
            SYNTH = NMSynthTools.completeDefaults(SYNTH, NM);
            state = NMSynthTools.stateFromSynth(SYNTH);
            state.synthPresent = present;
            state.synthDirty = false;
        end

        function SYNTH = completeDefaults(SYNTH, NM)
            % completeDefaults  Fill missing legacy SYNTH fields with modular defaults.
            %
            % Normalizes an existing SYNTH struct before it is converted to browser/API state or written back to NM. Defaults are chosen to preserve legacy NeuroMiner behavior unless the caller explicitly changes them.
            n = 0;
            if isfield(NM,'label') && ~isempty(NM.label)
                n = size(NMAlternativeLabelTools.activeLabel(NM), 1);
            end
            nSyn = round(double(n) * 0.1);

            if ~isfield(SYNTH,'flag') || isempty(SYNTH.flag), SYNTH.flag = 2; end
            if ~isfield(SYNTH,'method') || isempty(SYNTH.method), SYNTH.method = 1; end
            if ~isfield(SYNTH,'k') || isempty(SYNTH.k), SYNTH.k = 5; end
            if ~isfield(SYNTH,'distanceMeasure') || isempty(SYNTH.distanceMeasure), SYNTH.distanceMeasure = 'Euclidean'; end
            if ~isfield(SYNTH,'standardize_data') || isempty(SYNTH.standardize_data), SYNTH.standardize_data = 2; end
            if ~isfield(SYNTH,'numSyntheticObservations') || isempty(SYNTH.numSyntheticObservations), SYNTH.numSyntheticObservations = nSyn; end
            if ~isfield(SYNTH,'write2disk') || isempty(SYNTH.write2disk), SYNTH.write2disk = 1; end
            if ~isfield(SYNTH,'beta') || isempty(SYNTH.beta), SYNTH.beta = 0.5; end
            if ~isfield(SYNTH,'kDensity') || isempty(SYNTH.kDensity), SYNTH.kDensity = 5; end
            if ~isfield(SYNTH,'kSMOTE') || isempty(SYNTH.kSMOTE), SYNTH.kSMOTE = 5; end
            if ~isfield(SYNTH,'n_components') || isempty(SYNTH.n_components), SYNTH.n_components = 2; end
            if ~isfield(SYNTH,'minMethod') || isempty(SYNTH.minMethod), SYNTH.minMethod = 1; end
            % nm2-allow: Legacy persisted SYNTH settings predate population uncertainty.
            if ~isfield(SYNTH,'uncertaintyScale'), SYNTH.uncertaintyScale = 0; end

            SYNTH = NMSynthTools.validateSynth(SYNTH);
        end


        function SYNTH = defaultSetting(NM)
            % defaultSetting  Public legacy default for nk_Synth_config in disabled mode.
            SYNTH = NMSynthTools.completeDefaults(struct(), NM);
        end

        function state = stateFromSynth(SYNTH)
            % stateFromSynth  Convert legacy SYNTH settings into browser/API state.
            %
            % Maps synthetic-data enablement, neighbor, distance, standardization and disk-output fields to stable public state names. The method is read-only and does not generate synthetic observations.
            state = struct();
            state.synthEnabled = isequal(round(double(SYNTH.flag)),1);
            state.synthMethod = double(SYNTH.method);
            state.synthK = double(SYNTH.k);
            state.synthDistanceMeasure = char(SYNTH.distanceMeasure);
            state.synthStandardizeData = double(SYNTH.standardize_data);
            state.synthNumSyntheticObservations = double(SYNTH.numSyntheticObservations);
            state.synthWrite2Disk = double(SYNTH.write2disk);
            state.synthBeta = double(SYNTH.beta);
            state.synthKDensity = double(SYNTH.kDensity);
            state.synthKSMOTE = double(SYNTH.kSMOTE);
            state.synthNComponents = SYNTH.n_components;
            state.synthNComponentsText = strtrim(sprintf('%g ', SYNTH.n_components));
            state.synthMinMethod = double(SYNTH.minMethod);
            state.synthUncertaintyScale = double(SYNTH.uncertaintyScale);
        end

        function state = stateFromMenu(NM, current, menuState)
            % stateFromMenu  Translate browser synthetic-data controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            state = current;
            src = menuState.synth;
            fn = fieldnames(src);
            for i = 1:numel(fn)
                if strcmp(fn{i},'synthNComponentsText')
                    state.synthNComponents = NMSynthTools.numericVector(src.synthNComponentsText);
                elseif startsWith(fn{i}, 'synth')
                    state.(fn{i}) = src.(fn{i});
                end
            end
            state = NMSynthTools.normalizeState(state);
        end

        function state = normalizeState(state)
            % normalizeState  Enforce valid synthetic-data state values before legacy materialization.
            %
            % Validates inherited SYNTH choices and produces a complete canonical state. applyToNM consumes this normalized state.
            %
            % state.synthDirty: carries the synth dirty value between browser/API state and legacy NeuroMiner structures.
            % state.synthPresent: carries the synth present value between browser/API state and legacy NeuroMiner structures.
            SYNTH = NMSynthTools.validateSynth(NMSynthTools.synthFromState(state));
            keepPresent = logical(state.synthPresent);
            keepDirty = logical(state.synthDirty);
            state = NMSynthTools.stateFromSynth(SYNTH);
            state.synthPresent = keepPresent;
            state.synthDirty = keepDirty;
        end

        function SYNTH = synthFromState(state)
            % Convert complete, normalized NM2 state to the inherited backend schema.
            % UI-only synthNComponentsText is never a numeric authority.
            SYNTH = struct('flag',2-double(logical(state.synthEnabled)), ...
                'method',state.synthMethod,'k',state.synthK, ...
                'distanceMeasure',state.synthDistanceMeasure, ...
                'standardize_data',state.synthStandardizeData, ...
                'numSyntheticObservations',state.synthNumSyntheticObservations, ...
                'write2disk',state.synthWrite2Disk,'beta',state.synthBeta, ...
                'kDensity',state.synthKDensity,'kSMOTE',state.synthKSMOTE, ...
                'n_components',state.synthNComponents,'minMethod',state.synthMinMethod, ...
                'uncertaintyScale',state.synthUncertaintyScale);
        end

        function NM = applyToNM(NM, state)
            % applyToNM  Materialize synthetic-data settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.SYNTH at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.synthDirty: carries the synth dirty value between browser/API state and legacy NeuroMiner structures.
            % state.synthPresent: carries the synth present value between browser/API state and legacy NeuroMiner structures.
            present = logical(state.synthPresent);
            dirty = logical(state.synthDirty);
            if ~(present || dirty)
                return;
            end
            NM.TrainParam.SYNTH = NMSynthTools.synthFromState(state);
        end

        function text = summary(state)
            % summary  Render a concise human-readable synthetic-data configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            %
            % state.synthEnabled: carries the synth enabled value between browser/API state and legacy NeuroMiner structures.
            % state.synthMethod: carries the synth method value between browser/API state and legacy NeuroMiner structures.
            methods = {'kNN-based','ADASYN','PCAGauss','GMM','Gaussian copula'};
            if ~state.synthEnabled
                text = 'Synthetic data generation disabled.';
                return;
            end
            m = state.synthMethod;
            text = sprintf('Enabled: %s synthetic data generation.', methods{m});
            if state.synthUncertaintyScale > 0
                text = sprintf('%s Population uncertainty scale: %g.', text, state.synthUncertaintyScale);
            end
        end
    end

    methods (Static, Access = private)
        function SYNTH = validateSynth(SYNTH)
            SYNTH.flag = NMSynthTools.allowedScalar(SYNTH.flag, [1 2]);
            SYNTH.method = NMSynthTools.allowedScalar(SYNTH.method, 1:5);
            SYNTH.standardize_data = NMSynthTools.allowedScalar(SYNTH.standardize_data, [1 2]);
            SYNTH.write2disk = NMSynthTools.allowedScalar(SYNTH.write2disk, [1 2]);
            SYNTH.minMethod = NMSynthTools.allowedScalar(SYNTH.minMethod, [1 2]);
            validateattributes(SYNTH.k,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'}, ...
                'NMSynthTools.validateSynth','SYNTH.k');
            validateattributes(SYNTH.numSyntheticObservations,{'numeric'}, ...
                {'scalar','real','finite','integer','nonnegative'}, ...
                'NMSynthTools.validateSynth','SYNTH.numSyntheticObservations');
            validateattributes(SYNTH.kDensity,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'}, ...
                'NMSynthTools.validateSynth','SYNTH.kDensity');
            validateattributes(SYNTH.kSMOTE,{'numeric'}, ...
                {'scalar','real','finite','integer','positive'}, ...
                'NMSynthTools.validateSynth','SYNTH.kSMOTE');
            validateattributes(SYNTH.beta,{'numeric'}, ...
                {'scalar','real','finite','>=',0,'<=',1}, ...
                'NMSynthTools.validateSynth','SYNTH.beta');
            SYNTH.k = double(SYNTH.k);
            SYNTH.numSyntheticObservations = double(SYNTH.numSyntheticObservations);
            SYNTH.kDensity = double(SYNTH.kDensity);
            SYNTH.kSMOTE = double(SYNTH.kSMOTE);
            SYNTH.beta = double(SYNTH.beta);
            assert(any(strcmp(SYNTH.distanceMeasure,{NMSynthTools.DistanceChoices.symbol})), ...
                'NMSynthTools:invalidDistanceMeasure','Invalid SYNTH distance measure.');
            SYNTH.n_components = NMSynthTools.numericVector(SYNTH.n_components);
            validateattributes(SYNTH.uncertaintyScale, {'numeric'}, ...
                {'scalar','real','finite','nonnegative'}, ...
                'NMSynthTools.validateSynth', 'SYNTH.uncertaintyScale');
            SYNTH.uncertaintyScale = double(SYNTH.uncertaintyScale);
        end

        function v = allowedScalar(v, allowed)
            validateattributes(v,{'numeric'},{'scalar','real','finite','integer'}, ...
                'NMSynthTools.allowedScalar');
            assert(ismember(v,allowed),'NMSynthTools:invalidChoice', ...
                'Unsupported SYNTH categorical value.');
            v = double(v);
        end

        function v = numericVector(v)
            if ischar(v) || isstring(v)
                txt = char(v);
                assert(~isempty(regexp(txt,'^\s*\d+([,;\s]+\d+)*\s*$','once')), ...
                    'NMSynthTools:invalidComponents','Enter positive integer GMM components.');
                v = sscanf(regexprep(txt,'[,;]',' '),'%f')';
            end
            validateattributes(v,{'numeric'},{'vector','nonempty','real','finite','positive','integer'}, ...
                'NMSynthTools.numericVector','GMM components');
            v = double(v(:))';
        end

    end
end
