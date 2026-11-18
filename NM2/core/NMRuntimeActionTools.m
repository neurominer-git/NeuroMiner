classdef NMRuntimeActionTools
% NMRuntimeActionTools
% -------------------------------------------------------------------------
% Browser-entry-point independent runtime action planner/executor. Runtime
% actions are analysis-scoped but not owned by the Analysis Manager UI.  The
% concrete training runner remains NMRunTools.trainAnalysis; this class only
% derives shared runtime capability state and executes explicit runtime plans.
% -------------------------------------------------------------------------

    methods (Static)
        function state = runtimeState(NM, spec)
            % runtimeState  Derive shared browser/API runtime action state.
            %
            % state = NMRuntimeActionTools.runtimeState(NM, spec) returns a
            % fixed-schema capability report for analysis-scoped runtime
            % actions. The method is read-only and does not mutate NM.
            %
            % spec.analysisIndex: selects the analysis. Train ML and standalone preprocessing are wired
            % in B2.2; artifact state is represented so Analysis Manager and future
            % main-browser pages can share the same schema.
            %
            % spec.entryPoint: supplies the entry point value in the public API/import specification.

            if nargin < 2 || isempty(spec), spec = struct(); end
            analind = NMRuntimeActionTools.analysisIndexFromSpec(spec);
            defs = NMRuntimeActionTools.defsState(NM);
            state = struct();
            state.ok = true;
            state.message = sprintf('Runtime action state derived for analysis %d.', analind);
            state.analysisIndex = analind;
            state.entryPoint = NMRuntimeActionTools.fieldOr(spec,'entryPoint','api');
            state.mode = NMRuntimeActionTools.runtimeMode(defs);
            artifactSpec = struct('analysisIndex',analind, ...
                'useCache',NMRuntimeActionTools.useArtifactCacheForSpec(spec, state.entryPoint));
            state.artifacts = NMRuntimeActionTools.artifactState(NM, artifactSpec);
            state.actions = NMRuntimeActionTools.emptyActions();
            [preAction, preDefaults] = NMRuntimeActionTools.preprocessActionState(NM, analind, defs, state.artifacts);
            [trainAction, planDefaults] = NMRuntimeActionTools.trainMLActionState(NM, analind, defs, state.artifacts);
            state.actions.preprocess = preAction;
            state.actions.trainML = trainAction;
            state.planDefaults = struct('analysisIndex',analind, 'actions',{{}}, ...
                'options',struct('preprocess',preDefaults,'trainML',planDefaults));
            if trainAction.enabled
                state.planDefaults.actions = {'trainML'};
            end
        end


        function artifacts = artifactState(NM, spec)
            % artifactState  Inspect available runtime artifact files without UI prompts.
            %
            %   artifacts = NMRuntimeActionTools.artifactState(NM, spec) reports
            %   PreprocData, CVdatamat, CVresults, and CVdimanalysis file/master
            %   availability for one analysis. The method is read-only, avoids
            %   legacy interactive selectors, and follows the master/file naming
            %   contracts used by nk_GenPreprocMaster2, nk_GenCVdataMaster2, and
            %   nk_GenCVresultsMaster.

            if nargin < 2 || isempty(spec), spec = struct(); end
            analind = NMRuntimeActionTools.analysisIndexFromSpec(spec);
            artifacts = struct();
            artifacts.ok = true;
            artifacts.message = sprintf('Runtime artifacts inspected for analysis %d.', analind);
            artifacts.analysisIndex = analind;
            artifacts.rootdir = '';
            artifacts.algorithmRootdir = '';
            artifacts.dataId = '';
            artifacts.expectedCV2Cells = NaN;
            artifacts.expectedCV2GridSize = [NaN NaN];
            artifacts.recommendedTrainEntryPoint = 'scratch';
            artifacts.preprocData = NMRuntimeActionTools.artifactTemplate('preprocData','PreprocData');
            artifacts.cvDatamat = NMRuntimeActionTools.artifactTemplate('cvDatamat','CVdatamat');
            artifacts.cvResults = NMRuntimeActionTools.artifactTemplate('cvResults','CVresults');
            artifacts.cvDimAnalysis = NMRuntimeActionTools.artifactTemplate('cvDimAnalysis','CVdimanalysis');
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind < 1 || analind > numel(NM.analysis) || ~isstruct(NM.analysis{analind})
                artifacts.ok = false;
                artifacts.message = sprintf('Analysis %d does not exist.', analind);
                return;
            end
            A = NM.analysis{analind};
            artifacts.rootdir = NMRuntimeActionTools.fieldOr(A,'rootdir','');
            artifacts.algorithmRootdir = NMRuntimeActionTools.analysisAlgorithmRootDir(A, artifacts.rootdir);
            artifacts.dataId = NMRuntimeActionTools.dataId(NM, A);
            artifacts.expectedCV2Cells = NMRuntimeActionTools.expectedCV2Cells(A);
            artifacts.expectedCV2GridSize = NMRuntimeActionTools.expectedCV2GridSize(A);
            if isempty(artifacts.rootdir) || exist(artifacts.rootdir,'dir') ~= 7
                artifacts.ok = false;
                artifacts.message = sprintf('Analysis %d has no readable root directory for artifact inspection.', analind);
                artifacts = NMRuntimeActionTools.markArtifactsUnavailable(artifacts, artifacts.message);
                return;
            end
            if isempty(artifacts.dataId)
                artifacts.ok = false;
                artifacts.message = sprintf('Analysis %d has no NM.id/data ID for artifact inspection.', analind);
                artifacts = NMRuntimeActionTools.markArtifactsUnavailable(artifacts, artifacts.message);
                return;
            end
            rootDirs = NMRuntimeActionTools.candidateArtifactDirs(artifacts.rootdir);
            profile = NMRuntimeActionTools.analysisArtifactProfile(NM, analind);
            artifacts.profile = profile;
            artifacts.stacking = NMRuntimeActionTools.emptyStackingArtifactState();
            useCache = NMRuntimeActionTools.cacheRequested(spec);
            cacheKey = '';
            doProfile = NMRuntimeActionTools.profileEnabled();
            if useCache
                tCacheKey = tic;
                cacheKey = NMRuntimeActionTools.artifactStateCacheKey(NM, analind, artifacts, rootDirs, profile);
                [cacheHit, cachedArtifacts] = NMRuntimeArtifactCacheTools.cache('runtime','get', cacheKey, []);
                NMRuntimeActionTools.profileLog(doProfile, ...
                    '[nm-prof]     runtime artifact cache lookup analysis=%d: %.3fs (%s)\n', ...
                    double(analind), toc(tCacheKey), NMRuntimeArtifactCacheTools.hitMissText(cacheHit));
                if cacheHit
                    artifacts = cachedArtifacts;
                    artifacts.cache = NMRuntimeArtifactCacheTools.info(true, true, cacheKey);
                    return;
                end
            end
            tInspectAll = tic;
            if profile.isStacking
                artifacts.preprocData = NMRuntimeActionTools.inspectArtifactType('preprocData','PreprocData',rootDirs,artifacts.dataId,artifacts.expectedCV2Cells, ...
                    '','*PreprocDataMeta*ID%s*.mat');
            else
                artifacts.preprocData = NMRuntimeActionTools.inspectArtifactType('preprocData','PreprocData',rootDirs,artifacts.dataId,artifacts.expectedCV2Cells, ...
                    '*PreprocMaster*ID%s*.mat','*PreprocData*ID%s*.mat');
            end
            artifacts.cvDatamat = NMRuntimeActionTools.inspectArtifactType('cvDatamat','CVdatamat',rootDirs,artifacts.dataId,artifacts.expectedCV2Cells, ...
                '*CVdataMaster*ID%s*.mat','*CVdatamat*ID%s*.mat');
            artifacts.cvResults = NMRuntimeActionTools.inspectArtifactType('cvResults','CVresults',rootDirs,artifacts.dataId,NaN, ...
                '*CVresultsMaster*ID%s*.mat','*CVresults*ID%s*.mat');
            artifacts.cvDimAnalysis = NMRuntimeActionTools.inspectArtifactType('cvDimAnalysis','CVdimanalysis',rootDirs,artifacts.dataId,NaN, ...
                '','*CVdimanalysis*ID%s*.mat');
            artifacts.preprocData = NMRuntimeActionTools.applyArtifactExpectation(artifacts.preprocData, ...
                NMRuntimeActionTools.expectedArtifactCounts(profile, 'preprocData', artifacts.expectedCV2Cells, artifacts.expectedCV2GridSize));
            artifacts.cvDatamat = NMRuntimeActionTools.applyArtifactExpectation(artifacts.cvDatamat, ...
                NMRuntimeActionTools.expectedArtifactCounts(profile, 'cvDatamat', artifacts.expectedCV2Cells, artifacts.expectedCV2GridSize));
            artifacts.cvResults = NMRuntimeActionTools.applyArtifactExpectation(artifacts.cvResults, ...
                NMRuntimeActionTools.expectedArtifactCounts(profile, 'cvResults', artifacts.expectedCV2Cells, artifacts.expectedCV2GridSize));
            artifacts.cvDimAnalysis = NMRuntimeActionTools.applyArtifactExpectation(artifacts.cvDimAnalysis, ...
                NMRuntimeActionTools.expectedArtifactCounts(profile, 'cvDimAnalysis', artifacts.expectedCV2Cells, artifacts.expectedCV2GridSize));
            if profile.isStacking
                artifacts.stacking = NMRuntimeActionTools.inspectStackingInputCVData(NM, profile, artifacts.expectedCV2Cells);
                if ~artifacts.stacking.scratchAvailable && ~isempty(artifacts.stacking.message)
                    artifacts.preprocData.reason = sprintf('%s Stacking scratch input: %s', artifacts.preprocData.reason, artifacts.stacking.message);
                end
            end
            if artifacts.cvResults.available
                artifacts.recommendedTrainEntryPoint = 'results';
            elseif artifacts.cvDatamat.available
                artifacts.recommendedTrainEntryPoint = 'datamat';
            elseif artifacts.preprocData.available
                artifacts.recommendedTrainEntryPoint = 'preproc';
            elseif profile.isStacking && artifacts.stacking.scratchAvailable
                artifacts.recommendedTrainEntryPoint = 'scratch';
            elseif ~profile.isStacking
                artifacts.recommendedTrainEntryPoint = 'scratch';
            else
                artifacts.recommendedTrainEntryPoint = 'scratch';
            end
            if useCache
                artifacts.cache = NMRuntimeArtifactCacheTools.info(true, false, cacheKey);
                NMRuntimeArtifactCacheTools.cache('runtime','put', cacheKey, artifacts);
            else
                artifacts.cache = NMRuntimeArtifactCacheTools.info(false, false, '');
            end
            NMRuntimeActionTools.profileLog(doProfile, ...
                '[nm-prof]     runtime artifact inspect analysis=%d: %.3fs (cache=%d)\n', ...
                double(analind), toc(tInspectAll), double(useCache));
        end

        function plan = defaultPlan(NM, spec)
            % defaultPlan  Return an explicit runtime plan for feasible defaults.
            %
            % plan = NMRuntimeActionTools.defaultPlan(NM, spec) creates an
            % executable plan schema without running anything. The plan can be
            % used by browser UIs or MATLAB scripts and passed to runPlan.
            %
            % spec.dryRun: supplies the dry run value in the public API/import specification.

            if nargin < 2 || isempty(spec), spec = struct(); end
            state = NMRuntimeActionTools.runtimeState(NM, spec);
            plan = struct();
            plan.analysisIndex = state.analysisIndex;
            plan.actions = state.planDefaults.actions;
            plan.options = state.planDefaults.options;
            plan.dryRun = NMRuntimeActionTools.fieldOr(spec,'dryRun',false);
        end

        function [NM, out] = runPlan(NM, plan, runtimeUI)
            % runPlan  Execute a selected runtime plan through public runners.
            %
            %   [NM,out] = NMRuntimeActionTools.runPlan(NM, plan, runtimeUI) executes the
            %   explicitly selected analysis-scoped runtime actions. For B2.3c
            %   preprocessing and Train ML are executable and delegate directly
            %   to NMRunTools public runner APIs. When both are selected,
            %   preprocessing runs first and Train ML enters via existing PreprocData. Future runtime modules should be added
            %   here one by one without duplicating the public runner APIs.
            %
            %   Required plan fields:
            %       analysisIndex       analysis index
            %       actions             cellstr/string action keys
            %       options.trainML: Train ML options passed to NMRunTools
            %
            %   Optional:
            %       dryRun              validate/return plan without execution
            %
            % plan.analysisIndex: analysis index whose runtime actions should be validated or executed.
            % plan.actions: requested runtime action keys; currently preprocessing and Train ML are routed through NMRunTools.
            % plan.options: nested runner options, for example plan.options.trainML for NMRunTools.trainAnalysis.
            % plan.dryRun: when true, validate and return the execution plan without running legacy backends.

            if nargin < 2 || isempty(plan), plan = struct(); end
            if nargin < 3, runtimeUI = []; end
            plan = NMRuntimeActionTools.normalizePlan(NM, plan);
            hasRuntimeUI = isstruct(runtimeUI) && ~isempty(fieldnames(runtimeUI)) && ...
                isfield(runtimeUI,'enabled') && logical(runtimeUI.enabled);
            state = NMRuntimeActionTools.runtimeState(NM, struct('analysisIndex',plan.analysisIndex,'entryPoint','runtime_plan'));
            out = struct('ok',true, 'message','Runtime plan validated.', 'analysisIndex',plan.analysisIndex, ...
                'actionsRequested',{plan.actions}, 'actionsRun',{{}}, 'dryRun',logical(plan.dryRun), ...
                'state',state, 'results',struct());
            if isempty(plan.actions)
                error('NMRuntimeActionTools:noRuntimeActions', 'Runtime plan contains no selected actions.');
            end
            hasPreprocess = any(strcmp(plan.actions,'preprocess'));
            hasTrainML = any(strcmp(plan.actions,'trainML'));
            if hasPreprocess && hasTrainML
                plan.actions = NMRuntimeActionTools.orderPreprocessBeforeTrain(plan.actions);
                out.actionsRequested = plan.actions;
                out.handoff = struct('enabled',true, 'from','preprocess', 'to','trainML', ...
                    'operationMode','preproc', 'message','Train ML will consume PreprocData produced or refreshed by the preprocessing action.');
            else
                out.handoff = struct('enabled',false, 'from','', 'to','', 'operationMode','', 'message','');
            end
            if hasRuntimeUI && ~logical(plan.dryRun)
                runtimeUI.analysisIndex = double(plan.analysisIndex);
                NMRuntimeProgressTools.start(runtimeUI, 'NM Runtime Progress Viewer', ...
                    sprintf('Preparing runtime plan for analysis %d.', plan.analysisIndex));
            end
            nRuntimeSteps = numel(plan.actions);
            try
                for ii = 1:nRuntimeSteps
                    action = char(string(plan.actions{ii}));
                    if isfield(state.actions, action) && isstruct(state.actions.(action)) && ...
                            isfield(state.actions.(action),'label') && ~isempty(state.actions.(action).label)
                        stageLabel = char(string(state.actions.(action).label));
                    else
                        stageLabel = action;
                    end
                    if hasRuntimeUI && ~logical(plan.dryRun)
                        runtimeUI = NMRuntimeProgressTools.setStage(runtimeUI, stageLabel, ii, nRuntimeSteps, false);
                    end
                    switch action
                    case 'preprocess'
                        NMRuntimeActionTools.assertActionEnabled(state.actions.preprocess, 'Preprocessing');
                        preSpec = plan.options.preprocess;
                        if hasRuntimeUI, preSpec.UI = runtimeUI; end
                        if state.actions.preprocess.requiresOverwrite && ~logical(NMRuntimeActionTools.fieldOr(preSpec,'overwrite',false))
                            error('NMRuntimeActionTools:overwriteRequired', ...
                                'Analysis %d already contains PreprocData artifacts. Select overwrite before running preprocessing.', plan.analysisIndex);
                        end
                        if logical(plan.dryRun)
                            out.results.preprocess = struct('ok',true,'message','Dry run only; NMRunTools.preprocessAnalysis was not called.', ...
                                'runner','NMRunTools.preprocessAnalysis','analysisIndex',plan.analysisIndex,'spec',preSpec);
                        else
                            [NM, preOut] = NMRunTools.preprocessAnalysis(NM, plan.analysisIndex, preSpec);
                            out.results.preprocess = preOut;
                        end
                        out.actionsRun{end+1} = 'preprocess'; %#ok<AGROW>
                        if hasRuntimeUI && ~logical(plan.dryRun)
                            runtimeUI = NMRuntimeProgressTools.setStage(runtimeUI, stageLabel, ii, nRuntimeSteps, true);
                        end
                    case 'trainML'
                        NMRuntimeActionTools.assertActionEnabled(state.actions.trainML, 'Train ML');
                        trainSpec = plan.options.trainML;
                        if hasRuntimeUI, trainSpec.UI = runtimeUI; end
                        if state.actions.trainML.requiresOverwrite && ~logical(NMRuntimeActionTools.fieldOr(trainSpec,'overwrite',false))
                            error('NMRuntimeActionTools:overwriteRequired', ...
                                'Analysis %d already contains model results. Select overwrite before running Train ML.', plan.analysisIndex);
                        end
                        if hasPreprocess && hasTrainML
                            trainSpec.operationMode = 'preproc';
                            trainSpec.useExisting = true;
                            if ~isfield(trainSpec,'requireComplete'), trainSpec.requireComplete = true; end
                        end
                        if logical(plan.dryRun)
                            out.results.trainML = struct('ok',true,'message','Dry run only; NMRunTools.trainAnalysis was not called.', ...
                                'runner','NMRunTools.trainAnalysis','analysisIndex',plan.analysisIndex,'spec',trainSpec);
                        else
                            [NM, trainOut] = NMRunTools.trainAnalysis(NM, plan.analysisIndex, trainSpec);
                            out.results.trainML = trainOut;
                        end
                        out.actionsRun{end+1} = 'trainML'; %#ok<AGROW>
                        if hasRuntimeUI && ~logical(plan.dryRun)
                            runtimeUI = NMRuntimeProgressTools.setStage(runtimeUI, stageLabel, ii, nRuntimeSteps, true);
                        end
                    otherwise
                        error('NMRuntimeActionTools:unsupportedRuntimeAction', ...
                            'Runtime action ''%s'' is not wired in this staged patch.', action);
                    end
                end
                if hasRuntimeUI && ~logical(plan.dryRun)
                    NMRuntimeProgressTools.finish(runtimeUI, ...
                        sprintf('Runtime plan completed for analysis %d.', plan.analysisIndex), ...
                        'NM Runtime Progress Viewer');
                end
            catch ME
                if hasRuntimeUI
                    NMRuntimeProgressTools.fail(runtimeUI, 'NMRuntimeActionTools.runPlan', ME);
                end
                rethrow(ME);
            end
            if logical(plan.dryRun)
                out.message = sprintf('Runtime plan dry-run validated for analysis %d.', plan.analysisIndex);
            else
                out.state = NMRuntimeActionTools.runtimeState(NM, struct('analysisIndex',plan.analysisIndex,'entryPoint','runtime_plan'));
                out.message = sprintf('Runtime plan completed for analysis %d: %s.', plan.analysisIndex, strjoin(out.actionsRun, ', '));
            end
        end
    end

    methods (Static, Access = private)
        function actions = emptyActions()
            actions = struct();
            actions.preprocess = NMRuntimeActionTools.actionTemplate('preprocess', 'Preprocessing', true, false, 'Preprocessing runner feasibility has not been evaluated.');
            actions.trainML = NMRuntimeActionTools.actionTemplate('trainML', 'Train ML', true, false, 'Training runner feasibility has not been evaluated.');
            actions.visualizeModels = NMRuntimeActionTools.actionTemplate('visualizeModels', 'Visualize models', false, false, 'Runtime action is not wired in this staged patch.');
            actions.mlInterpreter = NMRuntimeActionTools.actionTemplate('mlInterpreter', 'ML Interpreter', false, false, 'Runtime action is not wired in this staged patch.');
            actions.exportModels = NMRuntimeActionTools.actionTemplate('exportModels', 'Export models', false, false, 'Runtime action is not wired in this staged patch.');
            actions.applyOOCV = NMRuntimeActionTools.actionTemplate('applyOOCV', 'Apply to OOCV data', false, false, 'Runtime action is not wired in this staged patch.');
        end

        function action = actionTemplate(key, label, wired, enabled, disabledReason)
            action = struct('key',key, 'label',label, 'wired',logical(wired), 'enabled',logical(enabled), ...
                'available',logical(enabled), 'selectedDefault',false, 'enabledReason','', ...
                'disabledReason',disabledReason, 'requiresOverwrite',false, 'hasExistingResults',false, ...
                'stage','B2.2');
        end

        function [action, planDefaults] = preprocessActionState(NM, analind, defs, artifacts)
            action = NMRuntimeActionTools.actionTemplate('preprocess', 'Preprocessing', true, false, '');
            action.enabledReason = 'Preprocessing can generate PreprocData files for later Train ML entry points.';
            action.selectedDefault = false;
            action.hasExistingResults = isstruct(artifacts) && isfield(artifacts,'preprocData') && isstruct(artifacts.preprocData) && logical(artifacts.preprocData.available);
            action.requiresOverwrite = action.hasExistingResults;
            planDefaults = struct('gridAction','all', 'useExisting',true, 'overwrite',false, ...
                'savePreproc',true, 'writeParameters',false, 'useExistingParameters',true, 'hideGrid',true);
            blocker = NMRuntimeActionTools.preprocessBlocker(NM, analind, defs);
            if isempty(blocker)
                action.enabled = true;
                action.available = true;
                action.disabledReason = '';
                if action.hasExistingResults
                    action.enabledReason = 'Preprocessing can be run after explicit overwrite confirmation.';
                end
            else
                action.enabled = false;
                action.available = false;
                action.disabledReason = blocker;
            end
        end

        function blocker = preprocessBlocker(NM, analind, defs)
            blocker = '';
            if ~defs.import_finished
                blocker = 'Finalize training data import before running preprocessing.'; return;
            end
            if defs.analyses_locked
                blocker = 'Preprocessing is disabled in application/OOCV mode.'; return;
            end
            if exist('NMRunTools','class') ~= 8
                blocker = 'NMRunTools is not available on the MATLAB path.'; return;
            end
            if exist('nk_PreprocessPrep','file') ~= 2
                blocker = 'Legacy runner nk_PreprocessPrep.m is not available on the MATLAB path.'; return;
            end
            if exist('nk_SetupGlobalVariables','file') ~= 2
                blocker = 'Legacy setup function nk_SetupGlobalVariables.m is not available on the MATLAB path.'; return;
            end
            if exist('nk_DefineFusionModeParams','file') ~= 2
                blocker = 'Legacy fusion/datamat function nk_DefineFusionModeParams.m is not available on the MATLAB path.'; return;
            end
            if exist('nk_Preprocess_StrCfg','file') ~= 2
                blocker = 'Legacy preprocessing filename function nk_Preprocess_StrCfg.m is not available on the MATLAB path.'; return;
            end
            if exist('nk_PerfPreprocess','file') ~= 2
                blocker = 'Legacy preprocessing executor nk_PerfPreprocess.m is not available on the MATLAB path.'; return;
            end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind < 1 || analind > numel(NM.analysis) || isempty(NM.analysis{analind}) || ~isstruct(NM.analysis{analind})
                blocker = sprintf('Analysis %d does not exist.', analind); return;
            end
            A = NM.analysis{analind};
            rootdir = NMRuntimeActionTools.fieldOr(A,'rootdir','');
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                blocker = sprintf('Analysis %d root path is stale or missing. Relink analysis root before running preprocessing.', analind); return;
            end
            if ~isfield(A,'params') || ~isstruct(A.params)
                blocker = sprintf('Analysis %d has no parameter snapshot.', analind); return;
            end
            if ~isfield(A.params,'TrainParam') || ~isstruct(A.params.TrainParam)
                blocker = sprintf('Analysis %d has no TrainParam snapshot.', analind); return;
            end
            if ~isfield(A.params,'cv') || isempty(A.params.cv)
                blocker = sprintf('Analysis %d has no CV snapshot.', analind); return;
            end
            if ~isfield(A.params.cv,'TrainInd') || isempty(A.params.cv.TrainInd)
                blocker = sprintf('Analysis %d CV snapshot has no TrainInd grid.', analind); return;
            end
        end

        function [action, planDefaults] = trainMLActionState(NM, analind, defs, artifacts)
            action = NMRuntimeActionTools.actionTemplate('trainML', 'Train ML', true, false, '');
            trainEntry = 'scratch';
            if isstruct(artifacts) && isfield(artifacts,'cvResults') && isstruct(artifacts.cvResults) && ...
                    isfield(artifacts.cvResults,'available') && logical(artifacts.cvResults.available)
                trainEntry = 'results';
            elseif isstruct(artifacts) && isfield(artifacts,'cvDatamat') && isstruct(artifacts.cvDatamat) && ...
                    isfield(artifacts.cvDatamat,'available') && logical(artifacts.cvDatamat.available)
                trainEntry = 'datamat';
            elseif isstruct(artifacts) && isfield(artifacts,'preprocData') && isstruct(artifacts.preprocData) && ...
                    isfield(artifacts.preprocData,'available') && logical(artifacts.preprocData.available)
                trainEntry = 'preproc';
            end
            action.enabledReason = 'Train ML can be run through NMRunTools.trainAnalysis.';
            if strcmpi(trainEntry,'results')
                action.enabledReason = 'Train ML can use existing CVresults artifacts via NMRunTools.trainAnalysis operationMode=results.';
            elseif strcmpi(trainEntry,'datamat')
                action.enabledReason = 'Train ML can use existing CVdatamat artifacts via NMRunTools.trainAnalysis operationMode=datamat.';
            elseif strcmpi(trainEntry,'preproc')
                action.enabledReason = 'Train ML can use existing PreprocData artifacts via NMRunTools.trainAnalysis operationMode=preproc.';
            end
            action.selectedDefault = false;
            action.hasExistingResults = NMRuntimeActionTools.hasExistingTrainingResults(NM, analind);
            action.requiresOverwrite = action.hasExistingResults;
            action.recommendedOperationMode = trainEntry;
            planDefaults = struct('gridAction','all', 'operationMode',trainEntry, 'overwrite',false, ...
                'update',true, 'hideGrid',true, 'debugall',false, 'debugopt',false);
            blocker = NMRuntimeActionTools.trainMLBlocker(NM, analind, defs);
            if isempty(blocker)
                action.enabled = true;
                action.available = true;
                action.disabledReason = '';
                if action.hasExistingResults
                    action.enabledReason = 'Train ML can be run after explicit overwrite confirmation.';
                end
            else
                action.enabled = false;
                action.available = false;
                action.disabledReason = blocker;
            end
        end

        function blocker = trainMLBlocker(NM, analind, defs)
            blocker = '';
            if ~defs.import_finished
                blocker = 'Finalize training data import before running Train ML.'; return;
            end
            if defs.analyses_locked
                blocker = 'Train ML is disabled in application/OOCV mode.'; return;
            end
            if exist('NMRunTools','class') ~= 8
                blocker = 'NMRunTools is not available on the MATLAB path.'; return;
            end
            if exist('nk_MLOptimizerPrep','file') ~= 2
                blocker = 'Legacy runner nk_MLOptimizerPrep.m is not available on the MATLAB path.'; return;
            end
            if exist('nk_GetAnalModalInfo_config','file') ~= 2
                blocker = 'Legacy modality-info configurator nk_GetAnalModalInfo_config.m is not available on the MATLAB path.'; return;
            end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind < 1 || analind > numel(NM.analysis) || isempty(NM.analysis{analind}) || ~isstruct(NM.analysis{analind})
                blocker = sprintf('Analysis %d does not exist.', analind); return;
            end
            A = NM.analysis{analind};
            rootdir = NMRuntimeActionTools.fieldOr(A,'rootdir','');
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                blocker = sprintf('Analysis %d root path is stale or missing. Relink analysis root before running Train ML.', analind); return;
            end
            if ~isfield(A,'params') || ~isstruct(A.params)
                blocker = sprintf('Analysis %d has no parameter snapshot.', analind); return;
            end
            if ~isfield(A.params,'TrainParam') || ~isstruct(A.params.TrainParam)
                blocker = sprintf('Analysis %d has no TrainParam snapshot.', analind); return;
            end
            if ~isfield(A.params,'cv') || isempty(A.params.cv)
                blocker = sprintf('Analysis %d has no CV snapshot.', analind); return;
            end
            if ~isfield(A.params.cv,'TrainInd') || isempty(A.params.cv.TrainInd)
                blocker = sprintf('Analysis %d CV snapshot has no TrainInd grid.', analind); return;
            end
        end

        function plan = normalizePlan(NM, plan)
            if ~isstruct(plan), error('NMRuntimeActionTools:badPlan', 'runtime plan must be a scalar struct.'); end
            if ~isfield(plan,'analysisIndex') || isempty(plan.analysisIndex)
                plan.analysisIndex = NMRuntimeActionTools.analysisIndexFromSpec(plan);
            end
            plan.analysisIndex = max(1, round(double(plan.analysisIndex)));
            if ~isfield(plan,'actions') || isempty(plan.actions)
                plan.actions = {};
            elseif ischar(plan.actions) || isstring(plan.actions)
                plan.actions = cellstr(string(plan.actions));
            elseif ~iscell(plan.actions)
                error('NMRuntimeActionTools:badActions', 'runtime plan actions must be a cell array or string array.');
            end
            plan.actions = NMRuntimeActionTools.normalizeActionKeys(plan.actions);
            if ~isfield(plan,'options') || ~isstruct(plan.options), plan.options = struct(); end
            if ~isfield(plan.options,'preprocess') || ~isstruct(plan.options.preprocess), plan.options.preprocess = struct(); end
            if ~isfield(plan.options,'trainML') || ~isstruct(plan.options.trainML), plan.options.trainML = struct(); end
            d = NMRuntimeActionTools.defaultPlan(NM, struct('analysisIndex',plan.analysisIndex));
            plan.options.preprocess = NMRuntimeActionTools.mergeStruct(d.options.preprocess, plan.options.preprocess);
            plan.options.trainML = NMRuntimeActionTools.mergeStruct(d.options.trainML, plan.options.trainML);
            if ~isfield(plan,'dryRun') || isempty(plan.dryRun), plan.dryRun = false; end
            plan.dryRun = logical(plan.dryRun);
        end


        function actions = orderPreprocessBeforeTrain(actionsIn)
            actions = actionsIn(:)';
            if any(strcmp(actions,'preprocess')) && any(strcmp(actions,'trainML'))
                others = actions(~strcmp(actions,'preprocess') & ~strcmp(actions,'trainML'));
                actions = [{'preprocess','trainML'}, others];
            end
        end

        function actions = normalizeActionKeys(actionsIn)
            actions = cell(1,0);
            for ii = 1:numel(actionsIn)
                key = char(string(actionsIn{ii}));
                key = strtrim(key);
                switch lower(key)
                    case {'preprocess','preprocessing','preproc','run_preprocessing'}
                        normKey = 'preprocess';
                    case {'trainml','train_ml','train','ml_training','run_ml_training'}
                        normKey = 'trainML';
                    case {'mlinterpreter','ml_interpreter','interpret'}
                        normKey = 'mlInterpreter';
                    case {'exportmodels','export_models','export'}
                        normKey = 'exportModels';
                    case {'applyoocv','apply_oocv','oocv'}
                        normKey = 'applyOOCV';
                    otherwise
                        normKey = key;
                end
                if ~isempty(normKey) && ~any(strcmp(actions, normKey))
                    actions{end+1} = normKey; %#ok<AGROW>
                end
            end
        end

        function assertActionEnabled(action, label)
            if ~isstruct(action) || ~isfield(action,'enabled') || ~logical(action.enabled)
                reason = 'action is not feasible.';
                if isstruct(action) && isfield(action,'disabledReason') && ~isempty(action.disabledReason)
                    reason = char(string(action.disabledReason));
                end
                error('NMRuntimeActionTools:runtimeActionDisabled', '%s is disabled: %s', char(string(label)), reason);
            end
        end

        function artifact = artifactTemplate(key, label)
            artifact = struct('key',key, 'label',label, 'available',false, 'status','missing', ...
                'coverageText','not found', 'nAvailable',0, 'nExpected',NaN, ...
                'nLogicalAvailable',0, 'nLogicalExpected',NaN, ...
                'nPhysicalAvailable',0, 'nPhysicalExpected',NaN, ...
                'nStreamsExpected',1, 'streamNoun','stream', 'cellAvailableMask',[], ...
                'masterFile','', ...
                'masterFiles',{{}}, 'files',{{}}, 'reason','No matching artifact files were found.');
        end

        function profile = analysisArtifactProfile(NM, analind)
            profile = struct('fusionFlag',0, 'fusionModalities',1, 'nModalities',1, ...
                'isIntermediateFusion',false, 'isLateFusion',false, 'isStacking',false, ...
                'stackingSelectedAnalyses',[], 'description','single-modality / no fusion');
            try
                A = NM.analysis{analind};
                if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam)
                    TP = A.params.TrainParam;
                    if isfield(TP,'FUSION') && isstruct(TP.FUSION)
                        if isfield(TP.FUSION,'flag') && ~isempty(TP.FUSION.flag)
                            profile.fusionFlag = max(0, min(3, round(double(TP.FUSION.flag))));
                        end
                        if isfield(TP.FUSION,'M') && ~isempty(TP.FUSION.M)
                            M = unique(round(double(TP.FUSION.M(:)')), 'stable');
                            M(~isfinite(M) | M < 1) = [];
                            if ~isempty(M), profile.fusionModalities = M; end
                        end
                    end
                    if isfield(TP,'ActiveModality') && ~isempty(TP.ActiveModality) && profile.fusionFlag == 0
                        m = round(double(TP.ActiveModality));
                        if isfinite(m) && m >= 1, profile.fusionModalities = m; end
                    end
                    if isfield(TP,'STACKING') && isstruct(TP.STACKING)
                        if isfield(TP.STACKING,'flag') && ~isempty(TP.STACKING.flag)
                            profile.isStacking = round(double(TP.STACKING.flag)) == 1;
                        end
                        if isfield(TP.STACKING,'sel_anal') && ~isempty(TP.STACKING.sel_anal)
                            sel = unique(round(double(TP.STACKING.sel_anal(:)')), 'stable');
                            sel(~isfinite(sel) | sel < 1) = [];
                            profile.stackingSelectedAnalyses = sel;
                        end
                    end
                end
            catch
                profile = struct('fusionFlag',0, 'fusionModalities',1, 'nModalities',1, ...
                    'isIntermediateFusion',false, 'isLateFusion',false, 'isStacking',false, ...
                    'stackingSelectedAnalyses',[], 'description','single-modality / no fusion');
            end
            profile.nModalities = max(1, numel(profile.fusionModalities));
            profile.isIntermediateFusion = profile.fusionFlag == 2;
            profile.isLateFusion = profile.fusionFlag == 3;
            switch profile.fusionFlag
                case 1, profile.description = 'early fusion';
                case 2, profile.description = 'intermediate fusion';
                case 3, profile.description = 'late fusion / decision-based fusion';
                otherwise, profile.description = 'single-modality / no fusion';
            end
            if profile.isStacking
                profile.description = 'stacking / decision-based meta-learning';
            end
        end

        function exp = expectedArtifactCounts(profile, key, nCells, gridSize)
            if nargin < 3 || isempty(nCells), nCells = NaN; end
            if nargin < 4 || isempty(gridSize), gridSize = [NaN NaN]; end
            nCells = double(nCells);
            if ~isfinite(nCells) || nCells < 1, nCells = NaN; end
            exp = struct('key',key, 'nLogicalExpected',nCells, 'nPhysicalExpected',NaN, ...
                'nStreamsExpected',1, 'streamNoun','stream', 'artifactNoun','files', ...
                'gridSize',double(gridSize(:)'), ...
                'resultsStyle',false, 'stackingMeta',false);
            nMod = max(1, double(profile.nModalities));
            switch char(string(key))
                case 'preprocData'
                    exp.artifactNoun = 'PreprocData files';
                    if profile.isStacking
                        exp.nStreamsExpected = 1;
                        exp.nPhysicalExpected = nCells;
                        exp.streamNoun = 'stacking stream';
                        exp.artifactNoun = 'PreprocDataMeta files';
                        exp.stackingMeta = true;
                    elseif profile.isIntermediateFusion || profile.isLateFusion
                        exp.nStreamsExpected = nMod;
                        exp.nPhysicalExpected = nCells * nMod;
                        exp.streamNoun = 'modality';
                    else
                        exp.nStreamsExpected = 1;
                        exp.nPhysicalExpected = nCells;
                        exp.streamNoun = 'stream';
                    end
                case 'cvDatamat'
                    exp.artifactNoun = 'CVdatamat files';
                    if profile.isLateFusion
                        exp.nStreamsExpected = nMod;
                        exp.nPhysicalExpected = nCells * nMod;
                        exp.streamNoun = 'modality-specific stream';
                    else
                        exp.nStreamsExpected = 1;
                        exp.nPhysicalExpected = nCells;
                        exp.streamNoun = 'stream';
                    end
                case 'cvResults'
                    exp.resultsStyle = true;
                    exp.artifactNoun = 'result streams';
                    if profile.isLateFusion
                        exp.nStreamsExpected = nMod;
                    else
                        exp.nStreamsExpected = 1;
                    end
                    exp.nLogicalExpected = exp.nStreamsExpected;
                    exp.nPhysicalExpected = exp.nStreamsExpected;
                    exp.streamNoun = 'result stream';
                otherwise
                    exp.artifactNoun = 'files';
                    exp.nLogicalExpected = NaN;
                    exp.nPhysicalExpected = NaN;
                    exp.nStreamsExpected = 1;
            end
        end

        function artifact = applyArtifactExpectation(artifact, exp)
            if ~isstruct(artifact) || ~isstruct(exp), return; end
            artifact.nLogicalExpected = exp.nLogicalExpected;
            artifact.nPhysicalExpected = exp.nPhysicalExpected;
            artifact.nStreamsExpected = exp.nStreamsExpected;
            artifact.streamNoun = exp.streamNoun;
            artifact.nPhysicalAvailable = numel(artifact.files);
            nLogical = 0;
            if isfield(exp,'resultsStyle') && exp.resultsStyle
                nLogical = artifact.nPhysicalAvailable;
                if artifact.nPhysicalAvailable == 0 && artifact.nAvailable > 0
                    nLogical = artifact.nAvailable;
                end
            elseif ~isnan(exp.nLogicalExpected) && exp.nStreamsExpected > 0 && artifact.nPhysicalAvailable > 0
                [mask, nLogical] = NMRuntimeActionTools.cvCellCoverageMaskFromFiles(artifact.files, artifact.key, exp.nStreamsExpected, exp.gridSize);
                if ~isempty(mask)
                    artifact.cellAvailableMask = mask;
                end
                if nLogical == 0 && artifact.nPhysicalAvailable >= exp.nPhysicalExpected
                    nLogical = exp.nLogicalExpected;
                    if isempty(artifact.cellAvailableMask) && NMRuntimeActionTools.validGridSize(exp.gridSize)
                        artifact.cellAvailableMask = true(exp.gridSize(1), exp.gridSize(2));
                    end
                end
            elseif artifact.nAvailable > 0
                nLogical = artifact.nAvailable;
            end
            if ~isnan(exp.nLogicalExpected)
                nLogical = min(nLogical, exp.nLogicalExpected);
            end
            artifact.nLogicalAvailable = nLogical;
            if ~isnan(exp.nPhysicalExpected)
                artifact.nExpected = exp.nPhysicalExpected;
            end
            artifact.nAvailable = artifact.nPhysicalAvailable;
            if artifact.nPhysicalAvailable == 0 && artifact.nLogicalAvailable > 0
                artifact.nAvailable = artifact.nLogicalAvailable;
            end
            if isfield(exp,'resultsStyle') && exp.resultsStyle
                artifact.available = artifact.nLogicalAvailable >= exp.nLogicalExpected;
            elseif ~isnan(exp.nLogicalExpected)
                artifact.available = artifact.nLogicalAvailable >= exp.nLogicalExpected;
            elseif ~isnan(exp.nPhysicalExpected)
                artifact.available = artifact.nPhysicalAvailable >= exp.nPhysicalExpected;
            else
                artifact.available = artifact.available && (artifact.nAvailable > 0);
            end
            if artifact.available && strcmpi(artifact.status,'missing')
                artifact.status = 'files_available';
            elseif ~artifact.available && artifact.nPhysicalAvailable > 0
                artifact.status = 'incomplete_files';
            end
            artifact.coverageText = NMRuntimeActionTools.artifactCoverageText(artifact, exp);
            if artifact.available
                artifact.reason = NMRuntimeActionTools.artifactReasonText(artifact, exp);
            elseif artifact.nPhysicalAvailable > 0
                artifact.reason = sprintf('Incomplete %s: %s.', artifact.label, artifact.coverageText);
            end
        end

    end

    methods (Static)
        function [mask, nComplete] = cvCellCoverageMaskFromFiles(files, key, nStreams, gridSize)
            nComplete = 0;
            mask = [];
            if isempty(files), return; end
            if nargin < 4 || isempty(gridSize), gridSize = [NaN NaN]; end
            useMask = NMRuntimeActionTools.validGridSize(gridSize);
            if useMask, mask = false(gridSize(1), gridSize(2)); end
            coords = zeros(numel(files),2);
            n = 0;
            for ii = 1:numel(files)
                fpath = files{ii};
                if isempty(fpath) || exist(fpath,'file') ~= 2, continue; end
                [a,b] = NMRuntimeActionTools.readArtifactCVIndex(fpath, key);
                if isempty(a) || isempty(b) || ~isfinite(a) || ~isfinite(b) || a < 1 || b < 1, continue; end
                n = n + 1;
                coords(n,:) = round([a b]);
            end
            if n == 0, return; end
            [uniqueCoords,~,group] = unique(coords(1:n,:),'rows');
            complete = accumarray(group,1) >= nStreams;
            nComplete = nnz(complete);
            if useMask
                completeCoords = uniqueCoords(complete,:);
                completeCoords = completeCoords(all(completeCoords <= gridSize,2),:);
                mask(sub2ind(gridSize,completeCoords(:,1),completeCoords(:,2))) = true;
            end
        end

    end

    methods (Static, Access = private)
        function tf = validGridSize(gridSize)
            tf = isnumeric(gridSize) && numel(gridSize) == 2 && all(isfinite(gridSize(:))) && all(gridSize(:) >= 1);
            if tf, gridSize = round(double(gridSize(:)')); tf = all(gridSize >= 1); end
        end

        function [a,b] = readArtifactCVIndex(fpath, key)
            a = []; b = [];
            try
                if strcmp(key,'cvDatamat')
                    [a,b] = NMRuntimeGridTools.fileCoordinates(fpath,'CVdatamat');
                elseif strcmp(key,'oocvDataMat')
                    [a,b] = NMRuntimeGridTools.fileCoordinates(fpath,'OOCVdatamat');
                else
                    [a,b] = NMRuntimeGridTools.fileCoordinates(fpath,'PreprocData');
                end
            catch
                a = []; b = [];
            end
        end

        function txt = artifactCoverageText(artifact, exp)
            if isfield(exp,'resultsStyle') && exp.resultsStyle
                txt = sprintf('%d/%d result streams available', artifact.nLogicalAvailable, exp.nLogicalExpected);
                return;
            end
            if isnan(exp.nLogicalExpected) || exp.nLogicalExpected <= 0
                txt = NMRuntimeActionTools.coverageText(artifact.nAvailable, artifact.nExpected, artifact.available);
                return;
            end
            if artifact.nPhysicalAvailable == 0 && artifact.nLogicalAvailable > 0 && ~isempty(artifact.masterFile)
                txt = sprintf('%d/%d CV2 cells complete; master file available', ...
                    artifact.nLogicalAvailable, exp.nLogicalExpected);
            elseif exp.nStreamsExpected > 1
                txt = sprintf('%d/%d CV2 cells complete; %d/%d %s found across %d %s', ...
                    artifact.nLogicalAvailable, exp.nLogicalExpected, artifact.nPhysicalAvailable, exp.nPhysicalExpected, ...
                    exp.artifactNoun, exp.nStreamsExpected, NMRuntimeActionTools.pluralNoun(exp.streamNoun, exp.nStreamsExpected));
            else
                txt = sprintf('%d/%d CV2 cells complete; %d/%d %s found', ...
                    artifact.nLogicalAvailable, exp.nLogicalExpected, artifact.nPhysicalAvailable, exp.nPhysicalExpected, exp.artifactNoun);
            end
        end

        function txt = artifactReasonText(artifact, exp)
            if isfield(exp,'resultsStyle') && exp.resultsStyle
                txt = sprintf('%s complete: %s.', artifact.label, artifact.coverageText);
            elseif exp.nStreamsExpected > 1
                txt = sprintf('%s complete across %d %s: %s.', artifact.label, exp.nStreamsExpected, NMRuntimeActionTools.pluralNoun(exp.streamNoun, exp.nStreamsExpected), artifact.coverageText);
            else
                txt = sprintf('%s complete: %s.', artifact.label, artifact.coverageText);
            end
        end

        function s = pluralSuffix(n)
            if n == 1, s = ''; else, s = 's'; end
        end

        function noun = pluralNoun(noun, n)
            noun = char(string(noun));
            if n == 1, return; end
            if strcmpi(noun, 'modality')
                noun = 'modalities';
            else
                noun = [noun 's'];
            end
        end

        function st = emptyStackingArtifactState()
            childTemplate = struct('analysisIndex',0, 'streamCount',0, 'analysisId','', 'description','', ...
                'nLogicalAvailable',0, 'nLogicalExpected',NaN, 'nPhysicalAvailable',0, ...
                'nPhysicalExpected',NaN, 'available',false, 'coverageText','', 'message','');
            st = struct('enabled',false, 'selectedAnalyses',[], 'scratchAvailable',false, ...
                'coverageText','not a stacking analysis', 'message','', 'nLogicalAvailable',0, ...
                'nLogicalExpected',NaN, 'nPhysicalAvailable',0, 'nPhysicalExpected',NaN, ...
                'nInputStreams',0, 'cellAvailableMask',[], 'streamCountMatrix',[], ...
                'childInputs',repmat(childTemplate,1,0));
        end

        function st = inspectStackingInputCVData(NM, profile, nCells)
            st = NMRuntimeActionTools.emptyStackingArtifactState();
            st.enabled = true;
            st.selectedAnalyses = profile.stackingSelectedAnalyses;
            if isempty(profile.stackingSelectedAnalyses)
                st.message = 'No first-tier analyses are selected for stacking.';
                st.coverageText = st.message;
                return;
            end
            nCells = double(nCells);
            if ~isfinite(nCells) || nCells < 1, nCells = NaN; end

            childTemplate = struct('analysisIndex',0, 'streamCount',0, 'analysisId','', 'description','', ...
                'nLogicalAvailable',0, 'nLogicalExpected',NaN, 'nPhysicalAvailable',0, ...
                'nPhysicalExpected',NaN, 'available',false, 'coverageText','', 'message','');
            nChild = numel(profile.stackingSelectedAnalyses);
            childInputs = repmat(childTemplate, 1, nChild);

            nStreams = 0;
            nFound = 0;
            completeByCell = [];
            firstGridSize = [];
            for ccChild = 1:nChild
                aa = profile.stackingSelectedAnalyses(ccChild);
                childInputs(ccChild).analysisIndex = aa;
                if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || aa < 1 || aa > numel(NM.analysis) || ~isstruct(NM.analysis{aa})
                    st.message = sprintf('Selected first-tier analysis %d is not available.', aa);
                    st.coverageText = st.message;
                    st.childInputs = childInputs;
                    return;
                end
                A = NM.analysis{aa};
                childInputs(ccChild).analysisId = NMRuntimeActionTools.fieldOr(A,'id',sprintf('Analysis %d', aa));
                childInputs(ccChild).description = NMRuntimeActionTools.fieldOr(A,'desc',childInputs(ccChild).analysisId);
                if ~isfield(A,'GDdims') || isempty(A.GDdims) || ~iscell(A.GDdims)
                    st.message = sprintf('Selected first-tier analysis %d has no trained GDdims/CVdatamat references.', aa);
                    st.coverageText = st.message;
                    st.childInputs = childInputs;
                    return;
                end
                nChildStreams = numel(A.GDdims);
                childInputs(ccChild).streamCount = nChildStreams;
                childCounts = [];
                childFound = 0;
                for jj = 1:nChildStreams
                    G = A.GDdims{jj};
                    if ~isstruct(G) || ~isfield(G,'RootPath') || isempty(G.RootPath) || ~isfield(G,'GDfilenames') || isempty(G.GDfilenames)
                        st.message = sprintf('Selected first-tier analysis %d stream %d has no CVdatamat root/path metadata.', aa, jj);
                        st.coverageText = st.message;
                        st.childInputs = childInputs;
                        return;
                    end
                    names = G.GDfilenames;
                    if ~iscell(names)
                        st.message = sprintf('Selected first-tier analysis %d stream %d has invalid GDfilenames metadata.', aa, jj);
                        st.coverageText = st.message;
                        st.childInputs = childInputs;
                        return;
                    end
                    if isempty(firstGridSize)
                        firstGridSize = size(names);
                    elseif ~isequal(firstGridSize, size(names))
                        st.message = sprintf('Selected first-tier analysis %d stream %d has a CV2 grid size that differs from the stacking analysis.', aa, jj);
                        st.coverageText = st.message;
                        st.childInputs = childInputs;
                        return;
                    end
                    if isempty(completeByCell), completeByCell = zeros(size(names)); end
                    if isempty(childCounts), childCounts = zeros(size(names)); end
                    nStreams = nStreams + 1;
                    for cc = 1:numel(names)
                        nm = names{cc};
                        if isempty(nm), continue; end
                        rootPath = G.RootPath;
                        if iscell(rootPath), rootPath = rootPath{1}; end
                        fpath = fullfile(char(string(rootPath)), char(string(nm)));
                        if exist(fpath,'file') == 2
                            nFound = nFound + 1;
                            childFound = childFound + 1;
                            completeByCell(cc) = completeByCell(cc) + 1;
                            childCounts(cc) = childCounts(cc) + 1;
                        end
                    end
                end
                if isnan(nCells), childExpectedCells = numel(childCounts); else, childExpectedCells = nCells; end
                childInputs(ccChild).nLogicalExpected = childExpectedCells;
                childInputs(ccChild).nPhysicalExpected = childExpectedCells * max(1,nChildStreams);
                childInputs(ccChild).nPhysicalAvailable = childFound;
                if isempty(childCounts)
                    childInputs(ccChild).nLogicalAvailable = 0;
                else
                    childInputs(ccChild).nLogicalAvailable = nnz(childCounts >= max(1,nChildStreams));
                end
                if ~isnan(childInputs(ccChild).nLogicalExpected)
                    childInputs(ccChild).nLogicalAvailable = min(childInputs(ccChild).nLogicalAvailable, childInputs(ccChild).nLogicalExpected);
                end
                childInputs(ccChild).available = childInputs(ccChild).nLogicalAvailable >= childInputs(ccChild).nLogicalExpected;
                childInputs(ccChild).coverageText = sprintf('%d/%d CV2 cells ready; %d/%d child CVdatamat files across %d stream%s', ...
                    childInputs(ccChild).nLogicalAvailable, childInputs(ccChild).nLogicalExpected, ...
                    childInputs(ccChild).nPhysicalAvailable, childInputs(ccChild).nPhysicalExpected, ...
                    nChildStreams, NMRuntimeActionTools.pluralSuffix(nChildStreams));
                if childInputs(ccChild).available
                    childInputs(ccChild).message = sprintf('First-tier analysis %d input complete: %s.', aa, childInputs(ccChild).coverageText);
                else
                    childInputs(ccChild).message = sprintf('First-tier analysis %d input incomplete: %s.', aa, childInputs(ccChild).coverageText);
                end
            end
            st.nInputStreams = nStreams;
            if isnan(nCells)
                st.nLogicalExpected = numel(completeByCell);
            else
                st.nLogicalExpected = nCells;
            end
            st.nPhysicalExpected = st.nLogicalExpected * max(1,nStreams);
            st.nPhysicalAvailable = nFound;
            if isempty(completeByCell)
                st.nLogicalAvailable = 0;
                st.cellAvailableMask = [];
                st.streamCountMatrix = [];
            else
                st.streamCountMatrix = completeByCell;
                st.cellAvailableMask = completeByCell >= max(1,nStreams);
                st.nLogicalAvailable = nnz(st.cellAvailableMask);
            end
            if ~isnan(st.nLogicalExpected), st.nLogicalAvailable = min(st.nLogicalAvailable, st.nLogicalExpected); end
            st.scratchAvailable = st.nInputStreams > 0 && st.nLogicalAvailable >= st.nLogicalExpected;
            st.childInputs = childInputs;
            st.coverageText = sprintf('%d/%d CV2 cells ready; %d/%d child CVdatamat files across %d first-tier stream%s', ...
                st.nLogicalAvailable, st.nLogicalExpected, st.nPhysicalAvailable, st.nPhysicalExpected, ...
                st.nInputStreams, NMRuntimeActionTools.pluralSuffix(st.nInputStreams));
            if st.scratchAvailable
                st.message = sprintf('Stacking scratch input complete: %s.', st.coverageText);
            else
                st.message = sprintf('Stacking scratch input incomplete: %s.', st.coverageText);
            end
        end

        function artifact = inspectArtifactType(key, label, dirs, dataId, expected, masterPattern, filePattern)
            artifact = NMRuntimeActionTools.artifactTemplate(key, label);
            if isempty(dataId), artifact.reason = 'No data ID is available.'; return; end
            doProfile = NMRuntimeActionTools.profileEnabled();
            masterFiles = {};
            masterCoverage = struct('available',false,'nAvailable',0,'nExpected',NaN,'reason','');
            tMaster = tic;
            if ~isempty(masterPattern)
                masterFiles = NMRuntimeActionTools.findArtifactFiles(dirs, sprintf(masterPattern, dataId), false);
            end
            artifact.masterFiles = masterFiles;
            artifact.masterFile = '';
            if ~isempty(masterFiles)
                artifact.masterFile = masterFiles{1};
                masterCoverage = NMRuntimeActionTools.masterCoverage(masterFiles{1}, dataId);
                masterComplete = masterCoverage.available && (isnan(masterCoverage.nExpected) || masterCoverage.nExpected <= 0 || masterCoverage.nAvailable >= masterCoverage.nExpected);
                if masterCoverage.available && masterComplete
                    artifact.available = true;
                    artifact.status = 'master_available';
                    artifact.nAvailable = masterCoverage.nAvailable;
                    artifact.nExpected = masterCoverage.nExpected;
                    artifact.reason = masterCoverage.reason;
                    artifact.coverageText = NMRuntimeActionTools.coverageText(artifact.nAvailable, artifact.nExpected, artifact.available);
                    NMRuntimeActionTools.profileLog(doProfile, ...
                        '[nm-prof]       artifact %s master-first: %.3fs (usable=1)\n', char(string(key)), toc(tMaster));
                    return;
                elseif masterCoverage.available
                    artifact.status = 'partial_master_available';
                    artifact.nAvailable = masterCoverage.nAvailable;
                    artifact.nExpected = masterCoverage.nExpected;
                    artifact.reason = masterCoverage.reason;
                    artifact.coverageText = NMRuntimeActionTools.coverageText(artifact.nAvailable, artifact.nExpected, false);
                end
            end
            NMRuntimeActionTools.profileLog(doProfile, ...
                '[nm-prof]       artifact %s master-first: %.3fs (usable=0, candidates=%d)\n', ...
                char(string(key)), toc(tMaster), double(numel(masterFiles)));
            tFiles = tic;
            files = NMRuntimeActionTools.findArtifactFiles(dirs, sprintf(filePattern, dataId), true);
            NMRuntimeActionTools.profileLog(doProfile, ...
                '[nm-prof]       artifact %s CV2-file scan: %.3fs (files=%d)\n', ...
                char(string(key)), toc(tFiles), double(numel(files)));
            artifact.files = files;
            if ~isempty(files)
                artifact.available = true;
                artifact.status = 'files_available';
                artifact.nAvailable = numel(files);
                artifact.nExpected = expected;
                artifact.reason = sprintf('%d matching %s file(s) found; no usable master file was loaded.', numel(files), label);
            else
                artifact.nExpected = expected;
                artifact.reason = 'No matching artifact files were found.';
                if ~isempty(masterCoverage.reason), artifact.reason = masterCoverage.reason; end
            end
            artifact.coverageText = NMRuntimeActionTools.coverageText(artifact.nAvailable, artifact.nExpected, artifact.available);
        end

        function c = masterCoverage(path, dataId)
            c = struct('available',false,'nAvailable',0,'nExpected',NaN,'reason','');
            if isempty(path) || exist(path,'file') ~= 2
                c.reason = 'Master file is not readable.'; return;
            end
            try
                S = load(path,'featmat','datid');
            catch ME
                c.reason = sprintf('Could not read master file: %s (%s)', ME.message, ME.identifier); return;
            end
            if isfield(S,'datid') && ~isempty(S.datid) && ~strcmp(char(string(S.datid)), char(string(dataId)))
                c.reason = 'Master file data ID does not match current NM.id.'; return;
            end
            if ~isfield(S,'featmat') || isempty(S.featmat)
                c.reason = 'Master file contains no featmat field.'; return;
            end
            [nAvail, nTotal] = NMRuntimeActionTools.cellCoverage(S.featmat);
            c.available = nAvail > 0;
            c.nAvailable = nAvail;
            c.nExpected = nTotal;
            if c.available
                c.reason = sprintf('Master file contains %d/%d populated entry/entries.', nAvail, nTotal);
            else
                c.reason = 'Master file has no populated featmat entries.';
            end
        end

        function [nAvail, nTotal] = cellCoverage(x)
            if iscell(x)
                nAvail = 0; nTotal = numel(x);
                for kk = 1:numel(x)
                    if iscell(x{kk})
                        [a,t] = NMRuntimeActionTools.cellCoverage(x{kk});
                        nAvail = nAvail + a;
                        if t > 0, nTotal = nTotal + t - 1; end
                    elseif ~isempty(x{kk})
                        nAvail = nAvail + 1;
                    end
                end
            else
                nTotal = 1;
                nAvail = double(~isempty(x));
            end
        end

        function txt = coverageText(nAvail, nExpected, available)
            if isnan(nExpected) || isempty(nExpected) || nExpected <= 0
                if available
                    txt = sprintf('%d file/entry available', nAvail);
                else
                    txt = 'not found';
                end
            else
                txt = sprintf('%d/%d available', nAvail, nExpected);
            end
        end

        function dirs = candidateArtifactDirs(rootdir)
            dirs = {rootdir};
            D = dir(rootdir);
            for ii = 1:numel(D)
                if D(ii).isdir && ~strcmp(D(ii).name,'.') && ~strcmp(D(ii).name,'..')
                    dirs{end+1} = fullfile(rootdir,D(ii).name); %#ok<AGROW>
                end
            end
        end

        function algdir = analysisAlgorithmRootDir(A, rootdir)
            algdir = char(string(rootdir));
            if isempty(algdir) || exist(algdir,'dir') ~= 7, return; end
            alg = '';
            try
                TP = struct();
                if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam)
                    TP = A.params.TrainParam;
                end
                fusionFlag = NaN;
                if isfield(TP,'FUSION') && isstruct(TP.FUSION) && isfield(TP.FUSION,'flag') && ~isempty(TP.FUSION.flag)
                    fusionFlag = round(double(TP.FUSION.flag));
                end
                if fusionFlag == 3
                    alg = 'DECFUSE';
                elseif isfield(TP,'SVM') && isstruct(TP.SVM) && isfield(TP.SVM,'prog') && ~isempty(TP.SVM.prog)
                    alg = char(string(TP.SVM.prog));
                elseif isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'SVM') && isstruct(A.params.SVM) && isfield(A.params.SVM,'prog') && ~isempty(A.params.SVM.prog)
                    alg = char(string(A.params.SVM.prog));
                end
            catch
                alg = '';
            end
            alg = strtrim(alg);
            if isempty(alg), return; end
            cand = fullfile(algdir, alg);
            if exist(cand,'dir') == 7, algdir = cand; end
        end

        function files = findArtifactFiles(dirs, pattern, excludeMasters)
            files = {};
            for ii = 1:numel(dirs)
                if isempty(dirs{ii}) || exist(dirs{ii},'dir') ~= 7, continue; end
                M = dir(fullfile(dirs{ii}, pattern));
                for jj = 1:numel(M)
                    if M(jj).isdir, continue; end
                    p = fullfile(M(jj).folder, M(jj).name);
                    if excludeMasters
                        if ~isempty(regexpi(M(jj).name,'Master','once')), continue; end
                        if isempty(regexpi(pattern,'Meta','once')) && ~isempty(regexpi(M(jj).name,'Param|Meta','once')), continue; end
                    end
                    if ~any(strcmp(files,p)), files{end+1} = p; end %#ok<AGROW>
                end
            end
        end

        function out = dataId(NM, A)
            out = '';
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id)
                out = char(string(NM.id)); return;
            end
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'id') && ~isempty(A.params.id)
                out = char(string(A.params.id));
            end
        end

        function n = expectedCV2Cells(A)
            n = NaN;
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'cv') && isstruct(A.params.cv) && ...
                    isfield(A.params.cv,'TrainInd') && ~isempty(A.params.cv.TrainInd)
                n = numel(A.params.cv.TrainInd);
            end
        end

        function sz = expectedCV2GridSize(A)
            sz = [NaN NaN];
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'cv') && isstruct(A.params.cv) && ...
                    isfield(A.params.cv,'TrainInd') && ~isempty(A.params.cv.TrainInd)
                sz = size(A.params.cv.TrainInd);
                if numel(sz) > 2, sz = sz(1:2); end
                sz = double(sz(:)');
            end
        end

        function artifacts = markArtifactsUnavailable(artifacts, reason)
            artifacts.preprocData.reason = reason;
            artifacts.cvDatamat.reason = reason;
            artifacts.cvResults.reason = reason;
            artifacts.cvDimAnalysis.reason = reason;
        end

        function defs = defsState(NM)
            if exist('NMStatusGuardTools','class') == 8
                defs = NMStatusGuardTools.defsState(NM);
            else
                defs = struct('import_finished',false,'analyses_locked',false);
                if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs)
                    if isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished), defs.import_finished = logical(NM.defs.import_finished); end
                    if isfield(NM.defs,'analyses_locked') && ~isempty(NM.defs.analyses_locked), defs.analyses_locked = logical(NM.defs.analyses_locked); end
                end
            end
        end

        function mode = runtimeMode(defs)
            if defs.analyses_locked
                mode = 'application';
            elseif defs.import_finished
                mode = 'training';
            else
                mode = 'data_import';
            end
        end

        function tf = hasExistingTrainingResults(NM, analind)
            tf = false;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind < 1 || analind > numel(NM.analysis) || ~isstruct(NM.analysis{analind}), return; end
            A = NM.analysis{analind};
            tf = (isfield(A,'GDdims') && ~isempty(A.GDdims)) || ...
                (isfield(A,'status') && ~isempty(A.status) && any(double(A.status(:)) >= 1));
        end

        function analind = analysisIndexFromSpec(spec)
            analind = 1;
            if isstruct(spec)
                names = {'analysisIndex','analind','index'};
                for ii = 1:numel(names)
                    if isfield(spec,names{ii}) && ~isempty(spec.(names{ii}))
                        analind = max(1, round(double(spec.(names{ii}))));
                        return;
                    end
                end
            end
        end

        function out = mergeStruct(defaults, overrides)
            out = defaults;
            if ~isstruct(overrides), return; end
            names = fieldnames(overrides);
            for ii = 1:numel(names)
                out.(names{ii}) = overrides.(names{ii});
            end
        end

        function tf = useArtifactCacheForSpec(spec, entryPoint)
            if isstruct(spec) && isfield(spec,'useArtifactCache') && ~isempty(spec.useArtifactCache)
                tf = NMRuntimeActionTools.toLogical(spec.useArtifactCache, false);
                return;
            end
            ep = lower(char(string(entryPoint)));
            tf = any(strcmp(ep, {'preprocess_runner','ml_train_runner','analysis_manager'}));
        end

        function tf = cacheRequested(spec)
            tf = false;
            if isstruct(spec) && isfield(spec,'useCache') && ~isempty(spec.useCache)
                tf = NMRuntimeActionTools.toLogical(spec.useCache, false);
            end
        end

        function key = artifactStateCacheKey(NM, analind, artifacts, dirs, profile)
            key = strjoin({ ...
                'NMRuntimeArtifact:v1', ...
                sprintf('analysis=%d', double(analind)), ...
                ['root=' NMRuntimeActionTools.safeKeyText(artifacts.rootdir)], ...
                ['dataId=' NMRuntimeActionTools.safeKeyText(artifacts.dataId)], ...
                sprintf('expected=%g', double(artifacts.expectedCV2Cells)), ...
                ['grid=' mat2str(double(artifacts.expectedCV2GridSize))], ...
                sprintf('fusion=%d', double(profile.fusionFlag)), ...
                sprintf('nmod=%d', double(profile.nModalities)), ...
                sprintf('stacking=%d', double(profile.isStacking)), ...
                ['stackSel=' mat2str(double(profile.stackingSelectedAnalyses(:)'))], ...
                ['dirs=' NMRuntimeActionTools.directorySignature(dirs)], ...
                ['stackDirs=' NMRuntimeActionTools.stackingDirectorySignature(NM, profile)]}, '|');
        end

        function sig = stackingDirectorySignature(NM, profile)
            sig = '';
            if ~isstruct(profile) || ~isfield(profile,'isStacking') || ~logical(profile.isStacking) || ...
                    ~isfield(profile,'stackingSelectedAnalyses') || isempty(profile.stackingSelectedAnalyses)
                return;
            end
            chunks = cell(1, numel(profile.stackingSelectedAnalyses));
            for ii = 1:numel(profile.stackingSelectedAnalyses)
                aa = profile.stackingSelectedAnalyses(ii);
                rootdir = '';
                if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && aa >= 1 && aa <= numel(NM.analysis) && isstruct(NM.analysis{aa})
                    rootdir = NMRuntimeActionTools.fieldOr(NM.analysis{aa}, 'rootdir', '');
                end
                childDirs = NMRuntimeActionTools.candidateArtifactDirs(rootdir);
                chunks{ii} = sprintf('%d:%s', double(aa), NMRuntimeActionTools.directorySignature(childDirs));
            end
            sig = strjoin(chunks, '||');
        end

        function sig = directorySignature(dirs)
            chunks = cell(1, max(1,numel(dirs)));
            if isempty(dirs)
                sig = 'none';
                return;
            end
            for ii = 1:numel(dirs)
                d = dirs{ii};
                if isempty(d) || exist(d,'dir') ~= 7
                    chunks{ii} = [NMRuntimeActionTools.safeKeyText(d) '#missing'];
                    continue;
                end
                try
                    L = dir(d);
                    names = {L.name};
                    keep = ~ismember(names,{'.','..'});
                    L = L(keep);
                    if isempty(L)
                        chunks{ii} = [NMRuntimeActionTools.safeKeyText(d) '#0#0#0'];
                    else
                        stamps = [L.datenum];
                        bytes = [L.bytes];
                        chunks{ii} = sprintf('%s#%d#%.0f#%.0f#%.0f', ...
                            NMRuntimeActionTools.safeKeyText(d), numel(L), ...
                            sum(round(stamps(:) * 86400)), max(round(stamps(:) * 86400)), sum(double(bytes(:))));
                    end
                catch
                    chunks{ii} = [NMRuntimeActionTools.safeKeyText(d) '#unreadable'];
                end
            end
            sig = strjoin(chunks, ';');
        end



        function tf = toLogical(v, defaultValue)
            tf = logical(defaultValue);
            try
                if islogical(v) || isnumeric(v)
                    tf = logical(v);
                else
                    tf = any(strcmpi(strtrim(char(string(v))), {'1','true','on','yes'}));
                end
            catch
                tf = logical(defaultValue);
            end
        end

        function txt = safeKeyText(v)
            try
                txt = char(string(v));
            catch
                txt = '';
            end
            txt = strrep(txt, '|', '/');
            txt = strrep(txt, char(10), ' ');
            txt = strrep(txt, char(13), ' ');
        end

        function tf = profileEnabled()
            tf = false;
            try
                env = getenv('NM_UI_PROFILE');
                if ~isempty(env)
                    tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
                end
            catch
                tf = false;
            end
        end

        function profileLog(enabled, varargin)
            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end

        function v = fieldOr(s, field, defaultValue)
            v = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end
    end
end
