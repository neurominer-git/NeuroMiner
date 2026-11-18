classdef NMOOCVTools
% NMOOCVTools
% -------------------------------------------------------------------------
% Browser/API-port helper for the legacy OOCV runtime parameter branch.
%
% Legacy target:
%   NM.TrainParam.OOCV
%
% This helper intentionally does not call nk_OOCV_config.m.  The legacy
% function is an interactive CLI configurator and also mutates the global NM
% workspace.  The defaults below mirror the non-interactive initialization
% logic at the top/end of nk_OOCV_config.m and are materialized through the
% same state -> legacy-struct -> applyToNM pattern used by the other modular
% configurator tools.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        MeanChoices = struct('symbol',{'aggregate_all','mean_cv1_then_aggregate'}, ...
            'code',{1,2},'description',{'Aggregate all base learners into one ensemble', ...
            'Average CV1 ensemble decisions before aggregation'})
        GroupChoices = struct('symbol',{'binary','multigroup','binary_and_multigroup'}, ...
            'code',{1,2,3},'description',{'OOCV at binary-learner optimum', ...
            'OOCV at multigroup-learner optimum','Evaluate both binary and multigroup optima'})
        RetrainChoices = struct('symbol',{'cv_training','all_cv_data'}, ...
            'code',{1,2},'description',{'Use the existing CV training definition', ...
            'Retrain using all available CV1 and CV2 data'})
    end

    methods (Static)
        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the OOCV runtime branch.
            %
            % Merges state/name-value inputs with stateFromNM, applies aliases and normalization, then materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the documented legacy target NM.TrainParam.OOCV and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            defaultState = NMOOCVTools.stateFromNM(NM);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.oocvDirty = true; end
            try
                state = NMConfigureAPITools.normalizeChoices(state, NMOOCVTools.apiChoices(), 'MATLAB:assertion:failed');
                state = NMOOCVTools.finalizeState(NM, state);
                NM = NMOOCVTools.applyToNM(NM, state);
                if isempty(report.message), report.message = 'NMOOCVTools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public OOCV runtime configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMOOCVTools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted OOCV runtime configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.OOCV. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.multiflag = 'Logical MULTI availability/status; inherited OOCV field.';
            opts.savemodels = 'Numeric inherited OOCV model-saving flag (default 2).';
            opts.saveoocvdata = 'Numeric inherited OOCV data-saving flag (default 1).';
            h = NMConfigureAPITools.helpStruct('NMOOCVTools.cli_configure', ...
                '[NM, state, report] = NMOOCVTools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMOOCVTools.configure(NM, ''meanflag'',''aggregate_all'', ''trainwithCV2Ts'',''cv_training'');'}, NMOOCVTools.apiChoices());
            h.validationRules = {'Group processing mode is applicable when MULTI is active and classification is configured.'; ...
                'OOCV application imputation/lifecycle is outside the training-template configuration API.'};
        end

        function choices = apiChoices()
            choices.meanflag = NMOOCVTools.MeanChoices;
            choices.groupmode = NMOOCVTools.GroupChoices;
            choices.trainwithCV2Ts = NMOOCVTools.RetrainChoices;
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the OOCV runtime branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMOOCVTools.cli_configureHelp();
        end

        function state = stateFromNM(NM)
            % stateFromNM  Reconstruct OOCV runtime browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.OOCV and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            [OOCV, present] = NMOOCVTools.extractLegacyOOCV(NM);
            OOCV = NMOOCVTools.completeDefaults(OOCV, NM);
            state = NMOOCVTools.stateFromOOCV(OOCV);
            state.oocvPresent = present;
            state.oocvDirty = false;
            state.oocvSummary = NMOOCVTools.summary(state);
        end

        function OOCV = completeDefaults(OOCV, NM)
            % completeDefaults  Fill missing legacy OOCV fields with modular defaults.
            %
            % Normalizes an existing OOCV struct before it is converted to browser/API state or written back to NM. Defaults are chosen to preserve legacy NeuroMiner behavior unless the caller explicitly changes them.
            if nargin < 1 || isempty(OOCV) || ~isstruct(OOCV), OOCV = struct(); end
            if nargin < 2, NM = struct(); end
            def = NMOOCVTools.defaultOOCV(NM);
            fn = fieldnames(def);
            for i = 1:numel(fn)
                if ~isfield(OOCV, fn{i}) || isempty(OOCV.(fn{i}))
                    OOCV.(fn{i}) = def.(fn{i});
                end
            end
            OOCV.meanflag = NMOOCVTools.allowedScalar(OOCV.meanflag, def.meanflag, [1 2], 'meanflag');
            OOCV.groupmode = NMOOCVTools.allowedScalar(OOCV.groupmode, def.groupmode, [1 2 3], 'groupmode');
            OOCV.trainwithCV2Ts = NMOOCVTools.allowedScalar(OOCV.trainwithCV2Ts, def.trainwithCV2Ts, [1 2], 'trainwithCV2Ts');
            OOCV.savemodels = NMOOCVTools.numericScalar(OOCV.savemodels, def.savemodels, 'savemodels');
            OOCV.saveoocvdata = NMOOCVTools.numericScalar(OOCV.saveoocvdata, def.saveoocvdata, 'saveoocvdata');
            if isfield(OOCV,'multiflag')
                OOCV.multiflag = logical(NMOOCVTools.numericScalar(OOCV.multiflag, def.multiflag, 'multiflag'));
            else
                OOCV.multiflag = logical(def.multiflag);
            end
        end

        function state = stateFromOOCV(OOCV)
            % stateFromOOCV  Convert legacy OOCV settings into browser/API state.
            %
            % Exposes mean aggregation, group mode, CV2 training and model/data saving flags using the public state field names. The method is read-only and is used after completeDefaults has filled missing legacy OOCV fields.
            state = OOCV;
        end

        function state = finalizeState(NM, state)
            % finalizeState  Normalize OOCV state after defaults and before legacy conversion.
            %
            % Repairs invalid booleans/numerics, resolves mode-dependent saving flags and derives values required by oocvFromState. This step keeps applyToNM from writing partial OOCV branches.
            %
            % state.oocvDirty: carries the oocv dirty value between browser/API state and legacy NeuroMiner structures.
            % state.oocvPresent: carries the oocv present value between browser/API state and legacy NeuroMiner structures.
            % state.oocvSummary: carries the oocv summary value between browser/API state and legacy NeuroMiner structures.
            if nargin < 2 || isempty(state) || ~isstruct(state)
                state = NMOOCVTools.stateFromNM(NM);
                return;
            end
            present = isfield(state,'oocvPresent') && logical(state.oocvPresent);
            dirty = isfield(state,'oocvDirty') && logical(state.oocvDirty);
            OOCV = NMOOCVTools.oocvFromState(state);
            OOCV = NMOOCVTools.completeDefaults(OOCV, NM);
            state = NMOOCVTools.stateFromOOCV(OOCV);
            state.oocvPresent = present;
            state.oocvDirty = dirty;
            state.oocvSummary = NMOOCVTools.summary(state);
        end

        function OOCV = oocvFromState(state)
            % oocvFromState  Convert normalized OOCV state into the legacy OOCV struct.
            %
            % Builds NM.TrainParam.OOCV from public state fields controlling mean aggregation, group mode, CV2 training and model/data saving. Browser-only fields are omitted.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                OOCV = struct();
                return;
            end
            OOCV = state;
            meta = {'oocvPresent','oocvDirty','oocvSummary'};
            for i = 1:numel(meta)
                if isfield(OOCV, meta{i}), OOCV = rmfield(OOCV, meta{i}); end
            end
        end

        function NM = applyToNM(NM, state)
            % applyToNM  Materialize OOCV runtime settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.OOCV at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state)
                state = NMOOCVTools.stateFromNM(NM);
            else
                state = NMOOCVTools.finalizeState(NM, state);
            end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam)
                NM.TrainParam = struct();
            end
            NM.TrainParam.OOCV = NMOOCVTools.oocvFromState(state);
        end

        function txt = summary(state)
            % summary  Render a concise human-readable OOCV runtime configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            %
            % state.groupmode: carries the groupmode value between browser/API state and legacy NeuroMiner structures.
            % state.meanflag: carries the meanflag value between browser/API state and legacy NeuroMiner structures.
            % state.trainwithCV2Ts: carries the trainwith cv2 ts value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                txt = 'OOCV runtime parameters unavailable.';
                return;
            end
            txt = sprintf('OOCV: meanflag=%g, groupmode=%g, trainwithCV2Ts=%g.', ...
                NMOOCVTools.fieldOr(state,'meanflag',NaN), ...
                NMOOCVTools.fieldOr(state,'groupmode',NaN), ...
                NMOOCVTools.fieldOr(state,'trainwithCV2Ts',NaN));
        end
    end

    methods (Static, Access = private)
        function [OOCV, present] = extractLegacyOOCV(NM)
            OOCV = struct();
            present = false;
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'OOCV') && isstruct(NM.TrainParam.OOCV)
                OOCV = NM.TrainParam.OOCV;
                present = true;
            end
        end

        function OOCV = defaultOOCV(NM)
            if nargin < 1 || isempty(NM), NM = struct(); end
            multiflag = false;
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'MULTI') && isstruct(NM.TrainParam.MULTI) && ...
                    isfield(NM.TrainParam.MULTI,'flag') && logical(NM.TrainParam.MULTI.flag)
                multiflag = true;
            end
            if multiflag
                groupmode = 2;
            else
                groupmode = 1;
            end
            OOCV = struct();
            OOCV.meanflag = 1;
            OOCV.groupmode = groupmode;
            OOCV.multiflag = multiflag;
            OOCV.trainwithCV2Ts = 1;
            OOCV.savemodels = 2;
            OOCV.saveoocvdata = 1;
        end

        function v = allowedScalar(value, defaultValue, allowed, fieldName)
            v = NMOOCVTools.numericScalar(value, defaultValue, fieldName);
            if ~any(v == allowed)
                error('NMOOCVTools:invalidValue', ...
                    'OOCV field %s must be one of [%s]; received %g.', ...
                    fieldName, num2str(allowed), v);
            end
        end

        function v = numericScalar(value, defaultValue, fieldName)
            if nargin < 2, defaultValue = []; end
            if nargin < 3 || isempty(fieldName), fieldName = 'value'; end
            if isempty(value)
                v = double(defaultValue);
                return;
            end
            if islogical(value), value = double(value); end
            if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)))
                error('NMOOCVTools:invalidScalar', ...
                    'OOCV field %s must be a finite numeric scalar.', fieldName);
            end
            v = double(value);
        end

        function v = fieldOr(s, field, defaultValue)
            v = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end
    end
end
