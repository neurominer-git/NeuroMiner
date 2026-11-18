classdef NMOOCVApplicationPreprocTools
% NMOOCVApplicationPreprocTools
% -------------------------------------------------------------------------
% Analysis-specific OOCV application-preprocessing assessment.
% Resolves the effective preprocessing branches of a trained analysis and
% evaluates predictor/label missingness on those branches without building
% physically concatenated early-fusion matrices.
% -------------------------------------------------------------------------

    methods (Static)
        function report = assess(NM, analind, oocvind)
            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(oocvind), oocvind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            D = NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            [fusionFlag, fusionMode, modalities, branches, isStacking] = ...
                NMOOCVApplicationPreprocTools.resolveBranches(analysis);

            nCases = NMOOCVApplicationPreprocTools.oocvCaseCount(D);
            if isStacking
                emptyBranches = NMOOCVApplicationPreprocTools.branchPrototype(nCases);
                emptyBranches = emptyBranches([]);
                report = struct('analysisIndex',analind, 'oocvIndex',oocvind, ...
                    'fusionFlag',fusionFlag, 'fusionMode',fusionMode, ...
                    'requiredModalities',modalities, 'nCases',nCases, ...
                    'branches',emptyBranches, 'assessmentSupported',false, ...
                    'unsupportedReason','Stacking application preprocessing operates on first-tier prediction features, not raw fusion modalities.', ...
                    'specialFeatureImputationAvailable',false);
                return;
            end
            trainMatrices = cell(1, max(modalities));
            oocvMatrices = cell(1, max(modalities));
            for ii = 1:numel(modalities)
                v = modalities(ii);
                trainMatrices{v} = NMOOCVApplicationPreprocTools.matrixAt(NM, v, 'training');
                oocvMatrices{v} = NMOOCVApplicationPreprocTools.matrixAt(D, v, 'OOCV');
                if size(oocvMatrices{v},1) ~= nCases
                    error('NMOOCVApplicationPreprocTools:OOCVCaseAxisMismatch', ...
                        ['OOCV modality %d contains %d row(s), but the selected OOCV container ', ...
                         'defines %d case(s). Re-establish the aligned OOCV case axis before application.'], ...
                        v, size(oocvMatrices{v},1), nCases);
                end
            end

            labelMissingRows = NMOOCVApplicationPreprocTools.labelMissingRows(analysis, D, nCases);
            branchReports = repmat(NMOOCVApplicationPreprocTools.branchPrototype(nCases), 1, numel(branches));
            for p = 1:numel(branches)
                mods = branches(p).modalities;
                trainingHasNaN = false;
                oocvRowAllNaN = true(nCases,1);
                oocvRowAnyNaN = false(nCases,1);
                for ii = 1:numel(mods)
                    T = trainMatrices{mods(ii)};
                    O = oocvMatrices{mods(ii)};
                    trainingHasNaN = trainingHasNaN || any(isnan(T(:)));
                    oocvRowAllNaN = oocvRowAllNaN & all(isnan(O),2);
                    oocvRowAnyNaN = oocvRowAnyNaN | any(isnan(O),2);
                end
                activeRows = ~oocvRowAllNaN;
                activeMissingPredictors = activeRows & oocvRowAnyNaN;
                activeMissingLabels = activeRows & labelMissingRows;

                b = NMOOCVApplicationPreprocTools.branchPrototype(nCases);
                b.branchIndex = p;
                b.preprocIndex = branches(p).preprocIndex;
                b.modalities = mods;
                b.fusionFlag = fusionFlag;
                b.fusionMode = fusionMode;
                b.trainingHasNaN = trainingHasNaN;
                b.trainingComplete = ~trainingHasNaN;
                b.oocvRowAllNaN = oocvRowAllNaN;
                b.activeOOCVRows = activeRows;
                b.oocvRowAnyNaN = oocvRowAnyNaN;
                b.activeOOCVMissingPredictors = activeMissingPredictors;
                b.oocvNeedsImputation = any(activeMissingPredictors);
                b.specialFeatureImputationAvailable = b.trainingComplete && b.oocvNeedsImputation;
                b.oocvLabelMissingRows = labelMissingRows;
                b.activeOOCVMissingLabels = activeMissingLabels;
                b.nAllNaNOOCVRows = sum(oocvRowAllNaN);
                b.nActiveOOCVRows = sum(activeRows);
                b.nActiveOOCVRowsWithMissingPredictors = sum(activeMissingPredictors);
                b.nActiveOOCVRowsWithMissingLabels = sum(activeMissingLabels);
                branchReports(p) = b;
            end

            report = struct('analysisIndex',analind, 'oocvIndex',oocvind, ...
                'fusionFlag',fusionFlag, 'fusionMode',fusionMode, ...
                'requiredModalities',modalities, 'nCases',nCases, ...
                'branches',branchReports, 'assessmentSupported',true, ...
                'unsupportedReason','', ...
                'specialFeatureImputationAvailable',any([branchReports.specialFeatureImputationAvailable]));
        end

        function modalities = requiredModalities(NM, analind)
            if nargin < 2 || isempty(analind), analind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            [~,~,modalities] = NMOOCVApplicationPreprocTools.resolveBranches(analysis);
        end

        function PREPROC = branchPreproc(NM, analind, oocvind, preprocIndex)
            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(oocvind), oocvind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            preprocIndex = NMOOCVApplicationPreprocTools.assertPreprocIndex(analysis, preprocIndex);
            PREPROC = [];
            if ~isfield(analysis.params,'OOCV') || isempty(analysis.params.OOCV), return; end
            states = NMOOCVApplicationPreprocTools.normalizedOOCVParams(analysis.params.OOCV);
            if numel(states) < oocvind || isempty(states{oocvind}), return; end
            entry = states{oocvind};
            if numel(entry.PREPROC) >= preprocIndex && ~isempty(entry.PREPROC{preprocIndex})
                PREPROC = entry.PREPROC{preprocIndex};
            end
        end

        function NM = setBranchPreproc(NM, analind, oocvind, preprocIndex, PREPROC)
            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(oocvind), oocvind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            preprocIndex = NMOOCVApplicationPreprocTools.assertPreprocIndex(analysis, preprocIndex);
            if ~isempty(PREPROC) && (~isstruct(PREPROC) || ~isscalar(PREPROC))
                error('NMOOCVApplicationPreprocTools:BadApplicationPreproc', ...
                    'Application PREPROC{%d} must be a scalar struct or empty.', preprocIndex);
            end
            NM = NMOOCVApplicationPreprocTools.normalizeAnalysisState(NM, analind);
            if isfield(NM.analysis{analind}.params,'OOCV')
                states = NM.analysis{analind}.params.OOCV;
            else
                states = cell(1,oocvind);
            end
            if numel(states) < oocvind, states{oocvind} = []; end
            entry = states{oocvind};
            if isempty(entry)
                entry = struct('PREPROC',{cell(1,preprocIndex)});
            elseif numel(entry.PREPROC) < preprocIndex
                entry.PREPROC{preprocIndex} = [];
            end
            entry.PREPROC{preprocIndex} = PREPROC;
            if all(cellfun(@isempty,entry.PREPROC))
                states{oocvind} = [];
            else
                states{oocvind} = entry;
            end
            states = NMOOCVApplicationPreprocTools.trimOOCVParams(states);
            if isempty(states)
                NM.analysis{analind}.params = rmfield(NM.analysis{analind}.params,'OOCV');
            else
                NM.analysis{analind}.params.OOCV = states;
            end
        end

        function editor = configuratorEditor(NM, analind, oocvind, preprocIndex)
            % configuratorEditor  Project one analysis/OOCV preprocessing branch into the native editor.
            % Inherited training preprocessing is retained as the scientific baseline; only
            % application-specific feature/label imputation is exposed as editable state.
            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(oocvind), oocvind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            preprocIndex = NMOOCVApplicationPreprocTools.assertPreprocIndex(analysis, preprocIndex);
            report = NMOOCVApplicationPreprocTools.assess(NM, analind, oocvind);
            branch = NMOOCVApplicationPreprocTools.reportBranch(report, preprocIndex);
            trainedPREPROC = NMOOCVApplicationPreprocTools.trainedPreprocAt(analysis, preprocIndex);
            storedPREPROC = NMOOCVApplicationPreprocTools.branchPreproc(NM, analind, oocvind, preprocIndex);
            if isempty(storedPREPROC), applicationPREPROC = trainedPREPROC; else, applicationPREPROC = storedPREPROC; end

            [ctx, editNM] = NMOOCVApplicationPreprocTools.editorContext(NM, analysis, branch, preprocIndex, applicationPREPROC);
            pipelinePREPROC = NMOOCVApplicationPreprocTools.pipelinePreproc(applicationPREPROC, trainedPREPROC);
            trainedPipeline = NMOOCVApplicationPreprocTools.pipelinePreproc(trainedPREPROC, trainedPREPROC);
            appOrch = NMPreprocOrchestrator.fromNM(editNM, preprocIndex, pipelinePREPROC, ctx);
            trainedOrch = NMPreprocOrchestrator.fromNM(editNM, preprocIndex, trainedPipeline, ctx);
            spec = appOrch.toUISpec();
            state = appOrch.toUIState();
            trainedState = trainedOrch.toUIState();
            specialFeatureIndex = NMOOCVApplicationPreprocTools.specialFeatureIndex(applicationPREPROC, trainedPREPROC);
            [state, nSpecialFeature] = NMOOCVApplicationPreprocTools.markEditorRoles(state, trainedState, specialFeatureIndex);

            featureAvailable = logical(branch.specialFeatureImputationAvailable);
            allowFeatureCard = featureAvailable || nSpecialFeature > 0;
            spec.editPolicy = struct('mode','oocv_application', 'lockGlobalOptions',true, ...
                'allowedModulesByStage',struct('subject',{{}}, 'cv',{{}}));
            if allowFeatureCard
                spec.editPolicy.allowedModulesByStage.cv = {'impute'};
            end

            [labelSpec, labelState] = NMOOCVApplicationPreprocTools.applicationLabelEditor( ...
                ctx, trainedPREPROC, storedPREPROC, branch);
            spec.applicationOptions = struct('labelImpute',labelSpec);
            state.applicationOptions = struct('labelImpute',labelState);
            editor = struct('analysisIndex',analind, 'oocvIndex',oocvind, ...
                'preprocIndex',preprocIndex, 'fusionMode',branch.fusionMode, ...
                'modalities',branch.modalities, 'featureImputationAvailable',featureAvailable, ...
                'labelImputationAvailable',logical(labelSpec.available), ...
                'configured',~isempty(storedPREPROC), 'spec',spec, 'state',state);
        end

        function NM = applyConfiguratorState(NM, analind, oocvind, preprocIndex, state)
            % applyConfiguratorState  Validate/commit constrained OOCV preprocessing editor state.
            % The returned application PREPROC is rebuilt from the exact trained PREPROC and
            % therefore cannot mutate inherited training actions or unrelated preprocessing state.
            if nargin < 5 || ~isstruct(state) || ~isscalar(state)
                error('NMOOCVApplicationPreprocTools:BadEditorState', ...
                    'OOCV application preprocessing editor STATE must be one scalar struct.');
            end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            preprocIndex = NMOOCVApplicationPreprocTools.assertPreprocIndex(analysis, preprocIndex);
            report = NMOOCVApplicationPreprocTools.assess(NM, analind, oocvind);
            branch = NMOOCVApplicationPreprocTools.reportBranch(report, preprocIndex);
            trainedPREPROC = NMOOCVApplicationPreprocTools.trainedPreprocAt(analysis, preprocIndex);
            storedPREPROC = NMOOCVApplicationPreprocTools.branchPreproc(NM, analind, oocvind, preprocIndex);
            if isempty(storedPREPROC), applicationPREPROC = trainedPREPROC; else, applicationPREPROC = storedPREPROC; end
            [ctx, editNM] = NMOOCVApplicationPreprocTools.editorContext(NM, analysis, branch, preprocIndex, applicationPREPROC);

            trainedPipeline = NMOOCVApplicationPreprocTools.pipelinePreproc(trainedPREPROC, trainedPREPROC);
            trainedOrch = NMPreprocOrchestrator.fromNM(editNM, preprocIndex, trainedPipeline, ctx);
            trainedState = trainedOrch.toUIState();
            candidateOrch = NMPreprocOrchestrator.fromNM(editNM, preprocIndex, trainedPipeline, ctx);
            candidateOrch.applyUIState(state, ctx);
            candidateState = candidateOrch.toUIState();

            if ~NMOOCVApplicationPreprocTools.globalStateEqual(candidateState, trainedState)
                error('NMOOCVApplicationPreprocTools:InheritedGlobalChanged', ...
                    'Inherited trained label/target preprocessing is immutable in OOCV application mode.');
            end
            NMOOCVApplicationPreprocTools.assertTaggedSubjectState(state, trainedState);
            [matchToTrained, specialPos] = NMOOCVApplicationPreprocTools.matchTaggedCVSteps(state, trainedState);
            if numel(specialPos) > 1
                error('NMOOCVApplicationPreprocTools:MultipleSpecialImpute', ...
                    'Only one OOCV-specific feature-imputation action may be inserted per preprocessing branch.');
            end
            if ~isempty(specialPos) && ~logical(branch.specialFeatureImputationAvailable)
                error('NMOOCVApplicationPreprocTools:FeatureImputeNotApplicable', ...
                    ['OOCV-specific feature imputation is not applicable to PREPROC{%d}: ', ...
                     'the effective branch must have complete training predictors and missing predictors in surviving OOCV rows.'], ...
                    preprocIndex);
            end

            candidateLegacy = candidateOrch.toLegacyPreproc();
            candidateActs = NMOOCVApplicationPreprocTools.actCells(candidateLegacy);
            trainedActs = NMOOCVApplicationPreprocTools.actCells(trainedPREPROC);
            candidateSteps = NMOOCVApplicationPreprocTools.cvSteps(candidateState);
            if numel(candidateActs) ~= numel(candidateSteps)
                error('NMOOCVApplicationPreprocTools:CandidateActMismatch', ...
                    'The editor returned %d CV step(s) but %d ACTPARAM action(s).', ...
                    numel(candidateSteps), numel(candidateActs));
            end
            finalActs = cell(1,numel(candidateSteps));
            for ii = 1:numel(candidateSteps)
                tj = matchToTrained(ii);
                if tj > 0
                    if tj > numel(trainedActs)
                        error('NMOOCVApplicationPreprocTools:TrainedActMismatch', ...
                            'The trained preprocessing sequence cannot be aligned to its ACTPARAM chain.');
                    end
                    finalActs{ii} = trainedActs{tj};
                else
                    finalActs{ii} = candidateActs{ii};
                end
            end

            finalPREPROC = trainedPREPROC;
            if isempty(finalActs)
                if isfield(finalPREPROC,'ACTPARAM'), finalPREPROC = rmfield(finalPREPROC,'ACTPARAM'); end
            else
                finalPREPROC.ACTPARAM = finalActs;
            end
            if isfield(finalPREPROC,'OOCVAPP'), finalPREPROC = rmfield(finalPREPROC,'OOCVAPP'); end
            if ~isempty(specialPos)
                finalPREPROC.OOCVAPP = struct('featureActIndex',double(specialPos(1)));
            end
            finalPREPROC = NMOOCVApplicationPreprocTools.applyApplicationLabelState( ...
                finalPREPROC, trainedPREPROC, state, ctx, branch);

            if isequaln(finalPREPROC, trainedPREPROC)
                finalPREPROC = [];
            end
            NM = NMOOCVApplicationPreprocTools.setBranchPreproc( ...
                NM, analind, oocvind, preprocIndex, finalPREPROC);
        end

        function projection = runtimeProjection(NM, analind, oocvind, preprocIndex)
            % runtimeProjection  Build the transient P8D action/parameter alignment.
            % The trained PREPROC remains authoritative. The only ordered
            % application overlay admitted here is the marked feature-imputation
            % action; label-imputation remains outside the P8D ACTPARAM path.
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            NMOOCVApplicationPreprocTools.oocvAt(NM, oocvind);
            preprocIndex = NMOOCVApplicationPreprocTools.assertPreprocIndex(analysis, preprocIndex);
            trainedPREPROC = NMOOCVApplicationPreprocTools.trainedPreprocAt(analysis, preprocIndex);
            applicationPREPROC = NMOOCVApplicationPreprocTools.branchPreproc(NM, analind, oocvind, preprocIndex);
            trainedActs = NMOOCVApplicationPreprocTools.actCells(trainedPREPROC);
            runtimePREPROC = trainedPREPROC;
            sourceIndex = 1:numel(trainedActs);
            featureActIndex = [];

            if ~isempty(applicationPREPROC)
                featureActIndex = NMOOCVApplicationPreprocTools.specialFeatureIndex(applicationPREPROC, trainedPREPROC);
                if ~isempty(featureActIndex)
                    applicationActs = NMOOCVApplicationPreprocTools.actCells(applicationPREPROC);
                    specialAct = applicationActs{featureActIndex};
                    if ~isfield(specialAct,'IMPUTE') || ~isstruct(specialAct.IMPUTE) || ...
                            ~isfield(specialAct.IMPUTE,'method') || ...
                            ~strcmpi(char(string(specialAct.IMPUTE.method)),'seuclidean')
                        error('NMOOCVApplicationPreprocTools:UnsupportedRuntimeImpute', ...
                            'P8D currently supports only standardized-Euclidean OOCV feature imputation.');
                    end
                    runtimeActs = [trainedActs(1:featureActIndex-1), {specialAct}, trainedActs(featureActIndex:end)];
                    if ~isequaln(applicationActs,runtimeActs)
                        error('NMOOCVApplicationPreprocTools:StoredInheritedCVChanged', ...
                            'Stored OOCV application PREPROC does not preserve the trained ACTPARAM sequence around the marked imputation step.');
                    end
                    runtimePREPROC.ACTPARAM = runtimeActs;
                    sourceIndex = [1:featureActIndex-1, 0, featureActIndex:numel(trainedActs)];
                end
            end

            projection = struct('analysisIndex',analind, 'oocvIndex',oocvind, ...
                'preprocIndex',preprocIndex, 'PREPROC',runtimePREPROC, ...
                'featureActIndex',featureActIndex, ...
                'trainedParamSourceIndex',sourceIndex, ...
                'trainedActionCount',numel(trainedActs), ...
                'runtimeActionCount',numel(sourceIndex));
        end

        function runtimeTrainedParam = projectTrainedParam(projection, trainedParam)
            % projectTrainedParam  Splice one empty parameter slot into a trained shelf.
            if ~isstruct(projection) || ~isscalar(projection) || ...
                    ~isfield(projection,'trainedParamSourceIndex')
                error('NMOOCVApplicationPreprocTools:BadRuntimeProjection', ...
                    'A scalar runtime projection with trainedParamSourceIndex is required.');
            end
            sourceIndex = double(projection.trainedParamSourceIndex(:)');
            nTrained = max([0 sourceIndex]);
            if iscell(trainedParam)
                source = reshape(trainedParam,1,[]);
            elseif nTrained == 1 && ~isempty(trainedParam)
                source = {trainedParam};
            elseif nTrained == 0 && isempty(trainedParam)
                source = {};
            else
                error('NMOOCVApplicationPreprocTools:BadTrainedParamChain', ...
                    'The trained preprocessing parameter chain does not match the runtime projection.');
            end
            if numel(source) ~= nTrained
                error('NMOOCVApplicationPreprocTools:BadTrainedParamChain', ...
                    'Expected %d trained preprocessing parameter slot(s), but received %d.', nTrained, numel(source));
            end
            runtimeTrainedParam = cell(1,numel(sourceIndex));
            for ii = 1:numel(sourceIndex)
                if sourceIndex(ii) > 0
                    runtimeTrainedParam{ii} = source{sourceIndex(ii)};
                end
            end
        end

        function NM = normalizeAnalysisState(NM, analind)
            if nargin < 2 || isempty(analind), analind = 1; end
            analysis = NMOOCVApplicationPreprocTools.analysisAt(NM, analind);
            if ~isfield(analysis.params,'OOCV'), return; end
            states = NMOOCVApplicationPreprocTools.normalizedOOCVParams(analysis.params.OOCV);
            if isempty(states)
                NM.analysis{analind}.params = rmfield(NM.analysis{analind}.params,'OOCV');
            else
                NM.analysis{analind}.params.OOCV = states;
            end
        end

        function NM = removeOOCVIndex(NM, oocvind)
            oocvind = round(double(oocvind));
            if ~isscalar(oocvind) || ~isfinite(oocvind) || oocvind < 1
                error('NMOOCVApplicationPreprocTools:BadOOCVIndex', ...
                    'OOCV/application dataset index must be a positive integer.');
            end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis), return; end
            for a = 1:numel(NM.analysis)
                if isempty(NM.analysis{a}) || ~isstruct(NM.analysis{a}) || ...
                        ~isfield(NM.analysis{a},'params') || ~isstruct(NM.analysis{a}.params) || ...
                        ~isfield(NM.analysis{a}.params,'OOCV')
                    continue;
                end
                states = NMOOCVApplicationPreprocTools.normalizedOOCVParams(NM.analysis{a}.params.OOCV);
                if numel(states) >= oocvind, states(oocvind) = []; end
                states = NMOOCVApplicationPreprocTools.trimOOCVParams(states);
                if isempty(states)
                    NM.analysis{a}.params = rmfield(NM.analysis{a}.params,'OOCV');
                else
                    NM.analysis{a}.params.OOCV = states;
                end
            end
        end
    end

    methods (Static, Access=private)
        function analysis = analysisAt(NM, analind)
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || ...
                    analind < 1 || analind ~= round(analind) || analind > numel(NM.analysis) || ...
                    ~isstruct(NM.analysis{analind})
                error('NMOOCVApplicationPreprocTools:BadAnalysisIndex', ...
                    'Analysis %g does not exist.', double(analind));
            end
            analysis = NM.analysis{analind};
        end

        function D = oocvAt(NM, oocvind)
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || ...
                    oocvind < 1 || oocvind ~= round(oocvind) || oocvind > numel(NM.OOCV) || ...
                    ~isstruct(NM.OOCV{oocvind})
                error('NMOOCVApplicationPreprocTools:BadOOCVIndex', ...
                    'OOCV/application dataset %g does not exist.', double(oocvind));
            end
            D = NM.OOCV{oocvind};
        end

        function [flag, mode, modalities, branches, isStacking] = resolveBranches(analysis)
            if ~isfield(analysis,'params') || ~isstruct(analysis.params) || ...
                    ~isfield(analysis.params,'TrainParam') || ~isstruct(analysis.params.TrainParam)
                error('NMOOCVApplicationPreprocTools:MissingTrainParam', ...
                    'The selected analysis has no TrainParam snapshot.');
            end
            TP = analysis.params.TrainParam;
            if ~isfield(TP,'FUSION') || ~isstruct(TP.FUSION) || ...
                    ~isfield(TP.FUSION,'flag') || isempty(TP.FUSION.flag) || ...
                    ~isfield(TP.FUSION,'M') || isempty(TP.FUSION.M)
                error('NMOOCVApplicationPreprocTools:MissingFusionState', ...
                    'The selected analysis has no complete TrainParam.FUSION snapshot.');
            end
            flag = double(TP.FUSION.flag(1));
            modalities = double(TP.FUSION.M(:)');
            isStacking = isfield(TP,'STACKING') && isstruct(TP.STACKING) && ...
                isfield(TP.STACKING,'flag') && ~isempty(TP.STACKING.flag) && ...
                round(double(TP.STACKING.flag(1))) == 1;
            if ~isscalar(flag) || ~isfinite(flag) || flag ~= round(flag) || ~ismember(flag,0:3)
                error('NMOOCVApplicationPreprocTools:BadFusionFlag', ...
                    'The selected analysis contains an invalid fusion flag.');
            end
            if isempty(modalities) || any(~isfinite(modalities)) || ...
                    any(modalities ~= round(modalities)) || any(modalities < 1) || ...
                    numel(unique(modalities,'stable')) ~= numel(modalities)
                error('NMOOCVApplicationPreprocTools:BadFusionModalities', ...
                    'The selected analysis contains an invalid TrainParam.FUSION.M modality vector.');
            end
            if flag == 0 && numel(modalities) ~= 1
                error('NMOOCVApplicationPreprocTools:NoFusionModalityCount', ...
                    'No-fusion analysis state must resolve exactly one modality.');
            end

            if isStacking
                mode = 'stacking';
                branches = struct('preprocIndex',{},'modalities',{});
                return;
            end
            switch flag
                case 0
                    mode = 'none';
                    branches = struct('preprocIndex',modalities(1),'modalities',modalities(1));
                case 1
                    mode = 'early';
                    branches = struct('preprocIndex',modalities(1),'modalities',modalities);
                case 2
                    mode = 'intermediate';
                    branches = NMOOCVApplicationPreprocTools.modalityBranches(modalities);
                case 3
                    mode = 'late';
                    branches = NMOOCVApplicationPreprocTools.modalityBranches(modalities);
            end
        end

        function branches = modalityBranches(modalities)
            branches = repmat(struct('preprocIndex',NaN,'modalities',[]),1,numel(modalities));
            for ii = 1:numel(modalities)
                branches(ii).preprocIndex = modalities(ii);
                branches(ii).modalities = modalities(ii);
            end
        end

        function nCases = oocvCaseCount(D)
            if ~isfield(D,'cases') || isempty(D.cases)
                error('NMOOCVApplicationPreprocTools:MissingOOCVCases', ...
                    'The selected OOCV/application dataset has no aligned case axis.');
            end
            nCases = numel(D.cases);
        end

        function Y = matrixAt(D, varind, scopeName)
            if ~isfield(D,'Y') || ~iscell(D.Y) || numel(D.Y) < varind || isempty(D.Y{varind})
                error('NMOOCVApplicationPreprocTools:MissingMatrix', ...
                    '%s modality %d has no feature matrix.', scopeName, varind);
            end
            raw = D.Y{varind};
            if ischar(raw) || (isstring(raw) && isscalar(raw))
                if exist('nk_LoadLinkedData','file') ~= 2
                    error('NMOOCVApplicationPreprocTools:LinkedDataLoaderUnavailable', ...
                        ['%s modality %d is externally linked, but nk_LoadLinkedData is not ', ...
                         'available on the MATLAB path.'], scopeName, varind);
                end
                tmp = struct('Y',{D.Y});
                tmp = nk_LoadLinkedData(tmp, varind);
                raw = tmp.Y{varind};
            end
            if ~(isnumeric(raw) || islogical(raw)) || ndims(raw) ~= 2
                error('NMOOCVApplicationPreprocTools:BadMatrixType', ...
                    '%s modality %d must resolve to a two-dimensional numeric/logical matrix.', scopeName, varind);
            end
            Y = raw;
        end

        function rows = labelMissingRows(analysis, D, nCases)
            rows = false(nCases,1);
            if isfield(D,'labels_known') && ~isempty(D.labels_known) && ~logical(D.labels_known)
                return;
            end
            labelData = [];
            if isfield(analysis,'params') && isstruct(analysis.params) && ...
                    isfield(analysis.params,'label') && isstruct(analysis.params.label) && ...
                    isfield(analysis.params.label,'altlabelflag') && logical(analysis.params.label.altlabelflag) && ...
                    isfield(analysis.params.label,'labelname') && ~isempty(analysis.params.label.labelname) && ...
                    isfield(D,'altlabels') && isstruct(D.altlabels)
                labelName = char(string(analysis.params.label.labelname));
                if isfield(D.altlabels,labelName)
                    labelData = D.altlabels.(labelName);
                end
            elseif isfield(D,'label') && ~isempty(D.label)
                labelData = D.label;
            end
            if isempty(labelData), return; end
            if size(labelData,1) ~= nCases
                error('NMOOCVApplicationPreprocTools:OOCVLabelAxisMismatch', ...
                    'OOCV labels contain %d row(s), but the OOCV case axis contains %d case(s).', ...
                    size(labelData,1), nCases);
            end
            if isnumeric(labelData)
                rows = any(isnan(labelData),2);
            elseif islogical(labelData)
                rows = false(nCases,1);
            elseif isstring(labelData) || iscategorical(labelData) || iscellstr(labelData)
                rows = any(ismissing(labelData),2);
            else
                error('NMOOCVApplicationPreprocTools:UnsupportedLabelType', ...
                    'OOCV label missingness cannot be assessed for label type %s.', class(labelData));
            end
            rows = logical(rows(:));
        end

        function preprocIndex = assertPreprocIndex(analysis, preprocIndex)
            preprocIndex = round(double(preprocIndex));
            if ~isscalar(preprocIndex) || ~isfinite(preprocIndex) || preprocIndex < 1
                error('NMOOCVApplicationPreprocTools:BadPreprocIndex', ...
                    'Application preprocessing branch index must be a positive integer.');
            end
            [~,~,~,branches,isStacking] = NMOOCVApplicationPreprocTools.resolveBranches(analysis);
            valid = [branches.preprocIndex];
            if isStacking || ~ismember(preprocIndex,valid)
                error('NMOOCVApplicationPreprocTools:PreprocBranchNotUsed', ...
                    'PREPROC{%d} is not an effective preprocessing branch of the selected analysis.', preprocIndex);
            end
        end

        function branch = reportBranch(report, preprocIndex)
            branches = report.branches;
            if isempty(branches)
                error('NMOOCVApplicationPreprocTools:NoEditableBranches', ...
                    'The selected analysis has no raw-modality OOCV preprocessing branch available for special application preprocessing.');
            end
            k = find([branches.preprocIndex] == preprocIndex, 1);
            if isempty(k)
                error('NMOOCVApplicationPreprocTools:MissingBranchAssessment', ...
                    'No application-preprocessing assessment exists for PREPROC{%d}.', preprocIndex);
            end
            branch = branches(k);
        end

        function PREPROC = trainedPreprocAt(analysis, preprocIndex)
            TP = analysis.params.TrainParam;
            if ~isfield(TP,'PREPROC') || ~iscell(TP.PREPROC) || ...
                    numel(TP.PREPROC) < preprocIndex || isempty(TP.PREPROC{preprocIndex}) || ...
                    ~isstruct(TP.PREPROC{preprocIndex}) || ~isscalar(TP.PREPROC{preprocIndex})
                error('NMOOCVApplicationPreprocTools:MissingTrainedPreproc', ...
                    'The selected analysis has no trained PREPROC{%d} branch.', preprocIndex);
            end
            PREPROC = TP.PREPROC{preprocIndex};
        end

        function [ctx, editNM] = editorContext(NM, analysis, branch, preprocIndex, applicationPREPROC)
            editNM = NM;
            editNM.TrainParam = analysis.params.TrainParam;
            nFeatures = 0;
            for ii = 1:numel(branch.modalities)
                Y = NMOOCVApplicationPreprocTools.matrixAt(NM, branch.modalities(ii), 'training');
                nFeatures = nFeatures + size(Y,2);
            end
            trainedPREPROC = NMOOCVApplicationPreprocTools.trainedPreprocAt(analysis, preprocIndex);
            hasSpecialFeature = NMOOCVApplicationPreprocTools.hasSpecialFeatureAct(applicationPREPROC, trainedPREPROC);
            hasAppLabel = NMOOCVApplicationPreprocTools.hasApplicationLabelOverride(applicationPREPROC, trainedPREPROC);
            ctx = NMPreprocContext.fromNM(editNM, preprocIndex, ...
                'hasNaNsInPredictors',logical(branch.specialFeatureImputationAvailable || hasSpecialFeature), ...
                'hasNaNsInLabels',logical(branch.nActiveOOCVRowsWithMissingLabels > 0 || hasAppLabel), ...
                'nFeatures',double(nFeatures));
        end

        function PREPROC = pipelinePreproc(applicationPREPROC, trainedPREPROC)
            PREPROC = applicationPREPROC;
            if isfield(PREPROC,'OOCVAPP'), PREPROC = rmfield(PREPROC,'OOCVAPP'); end
            [hasTrainedLabel, trainedLabel] = NMOOCVApplicationPreprocTools.labelImputeValue(trainedPREPROC);
            if hasTrainedLabel
                if ~isfield(PREPROC,'LABELMOD') || ~isstruct(PREPROC.LABELMOD), PREPROC.LABELMOD = struct(); end
                PREPROC.LABELMOD.LABELIMPUTE = trainedLabel;
            elseif isfield(PREPROC,'LABELMOD') && isstruct(PREPROC.LABELMOD) && ...
                    isfield(PREPROC.LABELMOD,'LABELIMPUTE')
                PREPROC.LABELMOD = rmfield(PREPROC.LABELMOD,'LABELIMPUTE');
                if isempty(fieldnames(PREPROC.LABELMOD)), PREPROC = rmfield(PREPROC,'LABELMOD'); end
            end
        end

        function [state, nSpecial] = markEditorRoles(state, trainedState, specialFeatureIndex)
            if nargin < 3, specialFeatureIndex = []; end
            if ~NMOOCVApplicationPreprocTools.globalStateEqual(state, trainedState)
                error('NMOOCVApplicationPreprocTools:StoredGlobalChanged', ...
                    'Stored OOCV application preprocessing changes inherited trained global preprocessing state.');
            end
            subject = NMOOCVApplicationPreprocTools.subjectSteps(state);
            trainedSubject = NMOOCVApplicationPreprocTools.subjectSteps(trainedState);
            if numel(subject) ~= numel(trainedSubject)
                error('NMOOCVApplicationPreprocTools:StoredSubjectChanged', ...
                    'Stored OOCV application preprocessing changes inherited subject-specific preprocessing.');
            end
            for ii = 1:numel(subject)
                if ~NMOOCVApplicationPreprocTools.stepEquivalent(subject{ii},trainedSubject{ii})
                    error('NMOOCVApplicationPreprocTools:StoredSubjectChanged', ...
                        'Stored OOCV application preprocessing changes inherited subject-specific preprocessing step %d.', ii);
                end
                subject{ii}.editRole = 'inherited';
                subject{ii}.trainedIndex = double(ii);
            end
            if isfield(state,'subject') && isfield(state.subject,'sequence') && isfield(state.subject.sequence,'steps')
                state.subject.sequence.steps = subject;
            end

            candidate = NMOOCVApplicationPreprocTools.cvSteps(state);
            trained = NMOOCVApplicationPreprocTools.cvSteps(trainedState);
            nSpecial = double(~isempty(specialFeatureIndex));
            if isempty(specialFeatureIndex)
                if numel(candidate) ~= numel(trained)
                    error('NMOOCVApplicationPreprocTools:UnmarkedStoredApplicationStep', ...
                        'Stored OOCV application PREPROC contains an unmarked ordered application step.');
                end
            else
                if numel(candidate) ~= numel(trained)+1 || specialFeatureIndex < 1 || specialFeatureIndex > numel(candidate)
                    error('NMOOCVApplicationPreprocTools:BadStoredApplicationMarker', ...
                        'Stored OOCV application PREPROC contains an invalid feature-imputation insertion marker.');
                end
            end
            tj = 1;
            for ii = 1:numel(candidate)
                if ~isempty(specialFeatureIndex) && ii == specialFeatureIndex
                    if ~isfield(candidate{ii},'moduleId') || ~strcmpi(char(string(candidate{ii}.moduleId)),'impute')
                        error('NMOOCVApplicationPreprocTools:BadStoredApplicationMarker', ...
                            'The marked OOCV application action is not a feature-imputation step.');
                    end
                    candidate{ii}.editRole = 'application';
                    candidate{ii}.trainedIndex = 0;
                    continue;
                end
                if tj > numel(trained) || ~NMOOCVApplicationPreprocTools.stepEquivalent(candidate{ii},trained{tj})
                    error('NMOOCVApplicationPreprocTools:StoredInheritedCVChanged', ...
                        'Stored OOCV application PREPROC changes inherited CV preprocessing step %d.', tj);
                end
                candidate{ii}.editRole = 'inherited';
                candidate{ii}.trainedIndex = double(tj);
                tj = tj + 1;
            end
            if tj <= numel(trained)
                error('NMOOCVApplicationPreprocTools:StoredInheritedCVChanged', ...
                    'Stored OOCV application PREPROC omits inherited trained CV preprocessing.');
            end
            if isfield(state,'cv') && isfield(state.cv,'sequence') && isfield(state.cv.sequence,'steps')
                state.cv.sequence.steps = candidate;
                state.sequence = state.cv.sequence;
            end
        end

        function [spec, state] = applicationLabelEditor(ctx, trainedPREPROC, storedPREPROC, branch)
            module = NMModuleRegistry.default().get('labelimpute');
            available = branch.nActiveOOCVRowsWithMissingLabels > 0;
            active = false;
            cfg = module.defaultConfig(ctx);
            if ~isempty(storedPREPROC)
                [hasStored, storedValue] = NMOOCVApplicationPreprocTools.labelImputeValue(storedPREPROC);
                [hasTrained, trainedValue] = NMOOCVApplicationPreprocTools.labelImputeValue(trainedPREPROC);
                if hasStored ~= hasTrained || (hasStored && ~isequaln(storedValue,trainedValue))
                    active = hasStored;
                    if active
                        cfg = module.fromLegacy(struct('LABELIMPUTE',storedValue), ctx);
                    end
                end
            end
            moduleSpec = module.configSpec(ctx);
            moduleSpec.title = 'OOCV label imputation';
            moduleSpec.description = ['Impute missing OOCV labels for this analysis/application branch using the ', ...
                'native NeuroMiner label-imputation settings. The setting is persisted outside the ordered ACTPARAM chain.'];
            spec = struct('available',logical(available), 'show',logical(available || active), ...
                'editable',logical(available || active), 'displayName','OOCV label imputation', ...
                'description',moduleSpec.description, 'moduleSpec',moduleSpec, 'moduleInfo',module.info());
            state = struct('active',logical(active), 'config',cfg);
        end

        function PREPROC = applyApplicationLabelState(PREPROC, trainedPREPROC, state, ctx, branch)
            active = false; cfg = struct();
            if isfield(state,'applicationOptions') && isstruct(state.applicationOptions) && ...
                    isfield(state.applicationOptions,'labelImpute') && isstruct(state.applicationOptions.labelImpute)
                ls = state.applicationOptions.labelImpute;
                if isfield(ls,'active') && ~isempty(ls.active), active = logical(ls.active); end
                if isfield(ls,'config') && isstruct(ls.config), cfg = ls.config; end
            end
            if ~active, return; end
            module = NMModuleRegistry.default().get('labelimpute');
            cfg = module.parseConfig(struct('nm2PreprocContext',ctx), cfg);
            if isfield(cfg,'method') && strcmpi(char(string(cfg.method)),'none')
                return;
            end
            if branch.nActiveOOCVRowsWithMissingLabels < 1
                error('NMOOCVApplicationPreprocTools:LabelImputeNotApplicable', ...
                    'OOCV-specific label imputation is not applicable because no surviving OOCV case has a missing label.');
            end
            legacy = module.toLegacy(cfg, ctx);
            if ~isfield(PREPROC,'LABELMOD') || ~isstruct(PREPROC.LABELMOD), PREPROC.LABELMOD = struct(); end
            PREPROC.LABELMOD.LABELIMPUTE = legacy.LABELIMPUTE;
            %#ok<NASGU> trainedPREPROC is intentionally retained in the signature to emphasize
            % that PREPROC started from the immutable trained branch before this application overlay.
        end

        function tf = globalStateEqual(a, b)
            ga = struct(); gb = struct();
            if isfield(a,'global'), ga = a.global; end
            if isfield(b,'global'), gb = b.global; end
            tf = isequaln(ga,gb);
        end

        function assertTaggedSubjectState(state, trainedState)
            candidate = NMOOCVApplicationPreprocTools.subjectSteps(state);
            trained = NMOOCVApplicationPreprocTools.subjectSteps(trainedState);
            if numel(candidate) ~= numel(trained)
                error('NMOOCVApplicationPreprocTools:InheritedSubjectChanged', ...
                    'Inherited trained subject-specific preprocessing is immutable in OOCV application mode.');
            end
            for ii = 1:numel(candidate)
                role = NMOOCVApplicationPreprocTools.stepRole(candidate{ii});
                idx = NMOOCVApplicationPreprocTools.stepTrainedIndex(candidate{ii});
                if ~strcmp(role,'inherited') || idx ~= ii || ...
                        ~NMOOCVApplicationPreprocTools.stepEquivalent(candidate{ii},trained{ii})
                    error('NMOOCVApplicationPreprocTools:InheritedSubjectChanged', ...
                        'Inherited trained subject-specific preprocessing step %d was modified.', ii);
                end
            end
        end

        function [matchToTrained, specialPos] = matchTaggedCVSteps(state, trainedState)
            candidate = NMOOCVApplicationPreprocTools.cvSteps(state);
            trained = NMOOCVApplicationPreprocTools.cvSteps(trainedState);
            matchToTrained = zeros(1,numel(candidate));
            specialPos = [];
            expected = 1;
            for ii = 1:numel(candidate)
                role = NMOOCVApplicationPreprocTools.stepRole(candidate{ii});
                idx = NMOOCVApplicationPreprocTools.stepTrainedIndex(candidate{ii});
                if strcmp(role,'inherited')
                    if idx ~= expected || idx < 1 || idx > numel(trained) || ...
                            ~NMOOCVApplicationPreprocTools.stepEquivalent(candidate{ii},trained{idx})
                        error('NMOOCVApplicationPreprocTools:InheritedCVChanged', ...
                            'An inherited trained CV preprocessing card was changed, removed, or reordered.');
                    end
                    matchToTrained(ii) = idx;
                    expected = expected + 1;
                elseif strcmp(role,'application')
                    if idx ~= 0 || ~isfield(candidate{ii},'moduleId') || ...
                            ~strcmpi(char(string(candidate{ii}.moduleId)),'impute')
                        error('NMOOCVApplicationPreprocTools:UnsupportedApplicationModule', ...
                            'Only one tagged feature-imputation module may be inserted into the OOCV application ACTPARAM chain.');
                    end
                    specialPos(end+1) = ii; %#ok<AGROW>
                else
                    error('NMOOCVApplicationPreprocTools:MissingApplicationEditRole', ...
                        'OOCV application preprocessing STATE lost its inherited/application step identity.');
                end
            end
            if expected <= numel(trained)
                error('NMOOCVApplicationPreprocTools:InheritedCVChanged', ...
                    'An inherited trained CV preprocessing card was changed, removed, or reordered.');
            end
        end

        function role = stepRole(step)
            role = '';
            if isstruct(step) && isfield(step,'editRole') && ~isempty(step.editRole)
                role = lower(char(string(step.editRole)));
            end
        end

        function idx = stepTrainedIndex(step)
            idx = NaN;
            if isstruct(step) && isfield(step,'trainedIndex') && isnumeric(step.trainedIndex) && ...
                    isscalar(step.trainedIndex) && isfinite(step.trainedIndex)
                idx = double(step.trainedIndex);
            end
        end

        function tf = stepEquivalent(a, b)
            tf = false;
            if ~isstruct(a) || ~isstruct(b) || ~isfield(a,'moduleId') || ~isfield(b,'moduleId'), return; end
            if ~strcmpi(char(string(a.moduleId)),char(string(b.moduleId))), return; end
            ca = struct(); cb = struct();
            if isfield(a,'config'), ca = a.config; end
            if isfield(b,'config'), cb = b.config; end
            ea = true; eb = true;
            if isfield(a,'enabled') && ~isempty(a.enabled), ea = logical(a.enabled); end
            if isfield(b,'enabled') && ~isempty(b.enabled), eb = logical(b.enabled); end
            tf = isequaln(ca,cb) && isequal(ea,eb);
        end

        function steps = cvSteps(state)
            steps = {};
            if isfield(state,'cv') && isstruct(state.cv) && isfield(state.cv,'sequence') && ...
                    isstruct(state.cv.sequence) && isfield(state.cv.sequence,'steps')
                steps = NMOOCVApplicationPreprocTools.cvLikeCell(state.cv.sequence.steps);
            elseif isfield(state,'sequence') && isstruct(state.sequence) && isfield(state.sequence,'steps')
                steps = NMOOCVApplicationPreprocTools.cvLikeCell(state.sequence.steps);
            end
        end

        function steps = subjectSteps(state)
            steps = {};
            if isfield(state,'subject') && isstruct(state.subject) && isfield(state.subject,'sequence') && ...
                    isstruct(state.subject.sequence) && isfield(state.subject.sequence,'steps')
                steps = NMOOCVApplicationPreprocTools.cvLikeCell(state.subject.sequence.steps);
            end
        end

        function out = cvLikeCell(raw)
            if isempty(raw), out = {}; return; end
            if iscell(raw), out = raw; return; end
            if isstruct(raw), out = num2cell(raw); return; end
            error('NMOOCVApplicationPreprocTools:BadStepState', ...
                'Preprocessing editor steps must be a cell or struct array.');
        end

        function acts = actCells(PREPROC)
            acts = {};
            if ~isstruct(PREPROC) || ~isfield(PREPROC,'ACTPARAM') || isempty(PREPROC.ACTPARAM), return; end
            raw = PREPROC.ACTPARAM;
            if iscell(raw), acts = raw;
            elseif isstruct(raw), acts = num2cell(raw);
            else
                error('NMOOCVApplicationPreprocTools:BadActParam', ...
                    'PREPROC.ACTPARAM must be a cell or struct array.');
            end
        end

        function idx = specialFeatureIndex(applicationPREPROC, trainedPREPROC)
            idx = [];
            if isempty(applicationPREPROC), return; end
            appActs = NMOOCVApplicationPreprocTools.actCells(applicationPREPROC);
            trainedActs = NMOOCVApplicationPreprocTools.actCells(trainedPREPROC);
            if isfield(applicationPREPROC,'OOCVAPP') && isstruct(applicationPREPROC.OOCVAPP) && ...
                    isfield(applicationPREPROC.OOCVAPP,'featureActIndex') && ~isempty(applicationPREPROC.OOCVAPP.featureActIndex)
                raw = double(applicationPREPROC.OOCVAPP.featureActIndex);
                if ~isscalar(raw) || ~isfinite(raw) || raw ~= round(raw) || raw < 1 || raw > numel(appActs) || ...
                        numel(appActs) ~= numel(trainedActs)+1
                    error('NMOOCVApplicationPreprocTools:BadStoredApplicationMarker', ...
                        'Stored OOCV application PREPROC contains an invalid feature-imputation insertion marker.');
                end
                if ~isstruct(appActs{raw}) || ~isfield(appActs{raw},'cmd') || ...
                        ~strcmpi(char(string(appActs{raw}.cmd)),'impute')
                    error('NMOOCVApplicationPreprocTools:BadStoredApplicationMarker', ...
                        'The marked OOCV application action is not an impute ACTPARAM action.');
                end
                idx = raw;
                return;
            end
            if numel(appActs) > numel(trainedActs)
                error('NMOOCVApplicationPreprocTools:UnmarkedStoredApplicationStep', ...
                    'Stored OOCV application PREPROC contains an ordered application step without OOCVAPP.featureActIndex.');
            end
        end

        function tf = hasSpecialFeatureAct(applicationPREPROC, trainedPREPROC)
            if isempty(applicationPREPROC), tf = false; return; end
            aa = NMOOCVApplicationPreprocTools.actCells(applicationPREPROC);
            ta = NMOOCVApplicationPreprocTools.actCells(trainedPREPROC);
            tf = numel(aa) ~= numel(ta);
            if ~tf
                for ii = 1:numel(aa)
                    if ~isequaln(aa{ii},ta{ii}), tf = true; break; end
                end
            end
        end

        function tf = hasApplicationLabelOverride(applicationPREPROC, trainedPREPROC)
            if isempty(applicationPREPROC), tf = false; return; end
            [ha,a] = NMOOCVApplicationPreprocTools.labelImputeValue(applicationPREPROC);
            [ht,t] = NMOOCVApplicationPreprocTools.labelImputeValue(trainedPREPROC);
            tf = ha ~= ht || (ha && ~isequaln(a,t));
        end

        function [hasValue, value] = labelImputeValue(PREPROC)
            hasValue = false; value = [];
            if isstruct(PREPROC) && isfield(PREPROC,'LABELMOD') && isstruct(PREPROC.LABELMOD) && ...
                    isfield(PREPROC.LABELMOD,'LABELIMPUTE') && ~isempty(PREPROC.LABELMOD.LABELIMPUTE)
                hasValue = true;
                value = PREPROC.LABELMOD.LABELIMPUTE;
            end
        end

        function states = normalizedOOCVParams(raw)
            if isempty(raw)
                states = {};
                return;
            end
            if ~iscell(raw)
                error('NMOOCVApplicationPreprocTools:BadStoredOOCVParams', ...
                    'analysis.params.OOCV must be a cell array indexed by OOCV/application dataset.');
            end
            states = cell(size(raw));
            for o = 1:numel(raw)
                entry = raw{o};
                if isempty(entry), continue; end
                if ~isstruct(entry) || ~isscalar(entry)
                    error('NMOOCVApplicationPreprocTools:BadStoredOOCVEntry', ...
                        'analysis.params.OOCV{%d} must be a scalar parameter struct or empty.', o);
                end
                if ~isfield(entry,'PREPROC')
                    if NMOOCVApplicationPreprocTools.isLegacyOOCVCarrier(entry)
                        % Pre-P8B NMRunTools copied NM.OOCV{o} data containers
                        % into analysis.params.OOCV. Those entries are legacy
                        % carrier state, not application-preprocessing state.
                        continue;
                    end
                    error('NMOOCVApplicationPreprocTools:BadStoredOOCVEntry', ...
                        'analysis.params.OOCV{%d} has no PREPROC application-parameter branch.', o);
                end
                if ~iscell(entry.PREPROC)
                    error('NMOOCVApplicationPreprocTools:BadStoredPreproc', ...
                        'analysis.params.OOCV{%d}.PREPROC must be a cell array.', o);
                end
                states{o} = entry;
            end
            states = NMOOCVApplicationPreprocTools.trimOOCVParams(states);
        end

        function tf = isLegacyOOCVCarrier(entry)
            tf = isfield(entry,'Y') || isfield(entry,'cases') || ...
                isfield(entry,'datadescriptor') || isfield(entry,'labels_known') || ...
                isfield(entry,'analysis_used');
        end

        function states = trimOOCVParams(states)
            if isempty(states), states = {}; return; end
            last = find(~cellfun(@isempty,states),1,'last');
            if isempty(last)
                states = {};
            else
                states = states(1:last);
            end
        end

        function b = branchPrototype(nCases)
            b = struct('branchIndex',NaN, 'preprocIndex',NaN, 'modalities',[], ...
                'fusionFlag',NaN, 'fusionMode','', 'trainingHasNaN',false, ...
                'trainingComplete',false, 'oocvRowAllNaN',false(nCases,1), ...
                'activeOOCVRows',false(nCases,1), 'oocvRowAnyNaN',false(nCases,1), ...
                'activeOOCVMissingPredictors',false(nCases,1), ...
                'oocvNeedsImputation',false, 'specialFeatureImputationAvailable',false, ...
                'oocvLabelMissingRows',false(nCases,1), ...
                'activeOOCVMissingLabels',false(nCases,1), ...
                'nAllNaNOOCVRows',0, 'nActiveOOCVRows',0, ...
                'nActiveOOCVRowsWithMissingPredictors',0, ...
                'nActiveOOCVRowsWithMissingLabels',0);
        end
    end
end
