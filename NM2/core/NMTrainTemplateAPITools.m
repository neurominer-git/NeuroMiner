classdef NMTrainTemplateAPITools
% NMTrainTemplateAPITools
% -------------------------------------------------------------------------
% Public compact API for materializing a one-modality preprocessing + learner
% template into the legacy NM.TrainParam structure.  Scripts pass modular
% specs; TrainParam mutation remains centralized in NMTrainTemplateOrchestrator.
% -------------------------------------------------------------------------

    methods (Static)
        function [NM, out] = configureOneModality(NM, spec)
            % configureOneModality  Build and materialize a one-modality training template from an API spec.
            %
            % [NM, out] = NMTrainTemplateAPITools.configureOneModality(NM, spec)
            % is the compact public API for creating a usable NeuroMiner
            % training template before an analysis is created. It accepts a
            % scalar struct with modular preprocessing and learner settings,
            % routes the preprocessing steps through NMPreprocOrchestrator,
            % routes the learner branch through NMTrainConfigOrchestrator, and
            % lets NMTrainTemplateOrchestrator write the corresponding legacy
            % TrainParam branches back into NM.
            %
            % This method changes training-template configuration in NM. It
            % does not create an analysis, run preprocessing, run model
            % training, or import data. Call it before
            % NMAnalysisManagerTools.createAnalysis so that the analysis
            % snapshots the intended template. If NMStatusGuardTools is
            % available, locked/application-mode workspaces are rejected.
            %
            % spec fields understood by this API include:
            % varind           Target modality index. Default: 1.
            % subjectPreproc   Cell array of subject-level preprocessing
            % step structs with moduleId/config fields.
            % cvPreproc        Cell array of CV-level preprocessing step
            % structs. Defaults: median imputation and
            % mean standardization.
            % learner          Struct with algorithm and optional config
            % fields. Default algorithm: 'LIBSVM'.
            % fusionFlag       Legacy fusion flag passed to the template
            % orchestrator. Default: 0.
            % fusionModalities Modalities participating in fusion; defaults
            % to varind when omitted or empty.
            % stackingFlag     Legacy stacking flag. Default: 2.
            % saveModel        Logical SAV setting materialized through
            % NMSAVTools. Default: false.
            % modelSaveName    Optional model filename base; empty input is
            % resolved by NMSAVTools.defaultMatName.
            % verbosity        Runtime verbosity flag. Default: true.
            % rfe, vis, mli, oocv
            % Optional structs merged into auxiliary
            % runtime-default branches before snapshotting.
            %
            % out.ok is true on success. out contains the materialized PREPROC
            % branch, preprocessing/template/SAV reports, and the auxiliary
            % default reports returned by configureAuxiliaryDefaults. Failures
            % are raised as errors with component-specific identifiers so API
            % callers can stop before creating an inconsistent analysis.
            %
            % Example:
            % spec = struct('varind',1, ...
            % 'cvPreproc',{{struct('moduleId','reducedim', ...
            % 'config',struct('method','PCA','fitDim',20))}}, ...
            % 'learner',struct('algorithm','LIBSVM'));
            % [NM, out] = NMTrainTemplateAPITools.configureOneModality(NM, spec);
            %
            % spec.cvPreproc: supplies the cv preproc value in the public API/import specification.
            % spec.fusionFlag: supplies the fusion flag value in the public API/import specification.
            % spec.fusionModalities: supplies the fusion modalities value in the public API/import specification.
            % spec.learner: supplies the learner value in the public API/import specification.
            % spec.modelSaveName: supplies the model save name value in the public API/import specification.
            % spec.saveModel: supplies the save model value in the public API/import specification.
            % spec.stackingFlag: supplies the stacking flag value in the public API/import specification.
            % spec.subjectPreproc: supplies the subject preproc value in the public API/import specification.
            % spec.varind: selects the modality index addressed by the runner or configuration operation.
            % spec.verbosity: supplies the verbosity value in the public API/import specification.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMTrainTemplateAPITools.configureOneModality');
            end
            spec = NMTrainTemplateAPITools.normalizeSpec(spec);
            ctx = struct('modeflag', NMTrainTemplateAPITools.modeflag(NM), 'NM', NM, 'varind', spec.varind, 'time', []);

            pp = NMPreprocOrchestrator.fromNM(NM, spec.varind, []);
            [pp, PREPROC, ppReport] = pp.cli_configure('SubjectSteps', spec.subjectPreproc, 'CVSteps', spec.cvPreproc); %#ok<ASGLU>
            if isfield(ppReport,'ok') && ~ppReport.ok
                error('NMTrainTemplateAPITools:preprocFailed', 'Preprocessing configuration failed: %s', NMTrainTemplateAPITools.reportText(ppReport));
            end

            ml = NMTrainConfigOrchestrator.fromNM(NM, [], ctx);
            if isfield(spec.learner,'algorithm') && ~isempty(spec.learner.algorithm)
                ml = ml.setAlgorithm(spec.learner.algorithm, ctx);
            end
            if isfield(spec.learner,'config') && isstruct(spec.learner.config)
                ml.MLConfig = NMTrainTemplateAPITools.mergeStruct(ml.MLConfig, spec.learner.config);
            end

            orch = NMTrainTemplateOrchestrator.fromNM(NM, spec.varind, ctx);
            branches = orch.Preproc;
            if isempty(branches) || numel(branches) < spec.varind
                branches{spec.varind} = pp;
            else
                branches{spec.varind} = pp;
            end
            [orch, rep] = orch.configure('VarIndex', spec.varind, ...
                'FusionFlag', spec.fusionFlag, 'FusionModalities', spec.fusionModalities, ...
                'StackingFlag', spec.stackingFlag, 'Preproc', branches, 'MLGlobal', ml);
            if isfield(rep,'ok') && ~rep.ok
                error('NMTrainTemplateAPITools:templateFailed', 'Training-template configuration failed.');
            end
            NM = orch.toNM(NM, ctx);
            if exist('NMSAVTools','class') == 8
                modelSaveName = spec.modelSaveName;
                if isempty(strtrim(char(string(modelSaveName))))
                    modelSaveName = NMSAVTools.defaultMatName(NM);
                end
                savArgs = {'savSaveModel', spec.saveModel, 'savMatName', modelSaveName, 'verbosity', spec.verbosity};
                [NM, savState, savReport] = NMSAVTools.configure(NM, savArgs{:});
                if isfield(savReport,'ok') && ~savReport.ok
                    error('NMTrainTemplateAPITools:savFailed', 'Saving/verbosity configuration failed: %s', NMTrainTemplateAPITools.reportText(savReport));
                end
            else
                savState = struct();
                savReport = struct('ok',false, 'message','NMSAVTools not found; SAV/verbosity defaults not applied.');
                error('NMTrainTemplateAPITools:missingNMSAVTools', 'NMSAVTools is required to materialize legacy TrainParam.SAV and TrainParam.verbosity.');
            end

            out = struct();
            out.ok = true;
            out.message = 'One-modality training template configured.';
            out.varind = spec.varind;
            out.PREPROC = PREPROC;
            out.preprocReport = ppReport;
            out.templateReport = rep;
            [NM, auxOut] = NMTrainTemplateAPITools.configureAuxiliaryDefaults(NM, spec);

            out.auxiliaryDefaults = auxOut;
            out.savState = savState;
            out.savReport = savReport;

        end

        function [NM, out] = copyPreprocessingSetup(NM, spec)
            % copyPreprocessingSetup  Replicate one modality's preprocessing template to target modalities.
            %
            % [NM, out] = NMTrainTemplateAPITools.copyPreprocessingSetup(NM, spec)
            % copies the subject-level and CV-level preprocessing branch from
            % spec.sourceModality: source modality copied to spec.targetModalities. The method is a
            % narrow API convenience for multi-modality workflows where several
            % modalities should start from the same preprocessing recipe.
            %
            % The operation updates only legacy preprocessing configuration in
            % NM.TrainParam.PREPROC and, for late-fusion strategies when
            % present, NM.TrainParam.STRAT{i}.PREPROC. It does not copy data
            % descriptors, imported matrices/images, labels, covariates, CV
            % partitions, learner settings, saved models, results, fusion
            % definitions, or analysis cards. If NMStatusGuardTools is
            % available and requireUnlocked is true, locked/application-mode
            % workspaces are rejected before any copy is attempted.
            %
            % Required and relevant spec fields:
            % spec.sourceModality: source modality index. Defaults to spec.varind or 1.
            % spec.targetModalities: numeric vector of target modality indices; defaults to all modalities except source.
            % spec.copyMode: copy policy. Currently only 'replace' is supported.
            % spec.requireUnlocked: logical guard against modifying locked training workspaces. Default true.
            % spec.validateTargets: lightweight compatibility check; detects absolute dimensionality-reduction requests that exceed a target feature count.
            %
            % out.targetStatus is a fixed-schema struct array with one entry
            % per requested target modality. Each entry records ok,
            % modalityIndex, message, warnings, and stepCount. out also reports
            % copied/skipped target lists and labels for the source preprocessing
            % steps. If no target is copied, the method raises an error rather
            % than silently returning a partly ambiguous state.
            %
            % Example:
            % spec = struct('sourceModality',1,'targetModalities',2:10);
            % [NM,out] = NMTrainTemplateAPITools.copyPreprocessingSetup(NM,spec);
            %
            % spec.copyMode: supplies the copy mode value in the public API/import specification.
            % spec.requireUnlocked: supplies the require unlocked value in the public API/import specification.
            %
            % spec.targetModalities: numeric vector of destination modality indices; defaults to all other modalities.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            spec = NMTrainTemplateAPITools.normalizeCopyPreprocSpec(NM, spec);
            if spec.requireUnlocked && exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMTrainTemplateAPITools.copyPreprocessingSetup');
            end

            nModal = NMTrainTemplateAPITools.numModalities(NM);
            if spec.sourceModality < 1 || spec.sourceModality > nModal
                error('NMTrainTemplateAPITools:badSourceModality', ...
                    'Source modality %g is outside the available modality range 1..%g.', double(spec.sourceModality), double(nModal));
            end
            spec.targetModalities = spec.targetModalities(spec.targetModalities >= 1 & spec.targetModalities <= nModal);
            spec.targetModalities = unique(spec.targetModalities(:)', 'stable');
            spec.targetModalities(spec.targetModalities == spec.sourceModality) = [];
            if isempty(spec.targetModalities)
                error('NMTrainTemplateAPITools:noTargets', 'No valid target modality remains after removing the source modality and out-of-range indices.');
            end
            if ~strcmpi(spec.copyMode, 'replace')
                error('NMTrainTemplateAPITools:unsupportedCopyMode', 'Only copyMode=''replace'' is supported.');
            end

            sourcePREPROC = NMTrainTemplateAPITools.legacyPreprocAt(NM, spec.sourceModality);
            sourcePP = NMPreprocOrchestrator.fromNM(NM, spec.sourceModality, sourcePREPROC);
            sourceState = sourcePP.toUIState();
            nSteps = NMTrainTemplateAPITools.preprocStepCount(sourceState);
            if nSteps <= 0
                error('NMTrainTemplateAPITools:emptySourcePreproc', ...
                    'Source modality %g has no preprocessing steps to copy.', double(spec.sourceModality));
            end

            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            if ~isfield(NM.TrainParam,'PREPROC') || ~iscell(NM.TrainParam.PREPROC), NM.TrainParam.PREPROC = cell(1,nModal); end
            if numel(NM.TrainParam.PREPROC) < nModal, NM.TrainParam.PREPROC{nModal} = []; end

            status = repmat(struct('ok',false,'modalityIndex',NaN,'message','','warnings',{{}},'copiedModules',{{}}), 1, numel(spec.targetModalities));
            copied = [];
            skipped = [];
            for k = 1:numel(spec.targetModalities)
                tgt = spec.targetModalities(k);
                status(k).modalityIndex = tgt;
                [ok, msg, warns] = NMTrainTemplateAPITools.validateCopyPreprocTarget(NM, tgt, sourceState, spec);
                status(k).warnings = warns;
                if ~ok
                    status(k).message = msg;
                    skipped(end+1) = tgt; %#ok<AGROW>
                    continue;
                end
                try
                    pp = NMPreprocOrchestrator.fromNM(NM, tgt, []);
                    pp.applyUIState(sourceState, pp.Context);
                    targetPREPROC = pp.toLegacyPreproc();
                    NM.TrainParam.PREPROC{tgt} = targetPREPROC;
                    if isfield(NM.TrainParam,'STRAT') && iscell(NM.TrainParam.STRAT) && numel(NM.TrainParam.STRAT) >= tgt && ...
                            isstruct(NM.TrainParam.STRAT{tgt})
                        NM.TrainParam.STRAT{tgt}.PREPROC = targetPREPROC;
                    end
                    status(k).ok = true;
                    status(k).message = sprintf('Copied preprocessing setup from modality %g to modality %g.', double(spec.sourceModality), double(tgt));
                    status(k).copiedModules = NMTrainTemplateAPITools.preprocStepLabels(sourceState);
                    copied(end+1) = tgt; %#ok<AGROW>
                catch ME
                    status(k).message = sprintf('Copy failed for modality %g: %s', double(tgt), ME.message);
                    skipped(end+1) = tgt; %#ok<AGROW>
                end
            end

            out = struct();
            out.ok = ~isempty(copied);
            out.sourceModality = spec.sourceModality;
            out.targetModalities = spec.targetModalities;
            out.copiedModalities = copied;
            out.skippedModalities = skipped;
            out.targetStatus = status;
            out.sourceStepCount = nSteps;
            out.sourceStepLabels = NMTrainTemplateAPITools.preprocStepLabels(sourceState);
            if out.ok
                out.message = sprintf('Copied preprocessing setup from modality %g to %g target modality/modalities.', ...
                    double(spec.sourceModality), double(numel(copied)));
            else
                msgs = {status.message};
                out.message = sprintf('No preprocessing setup was copied. %s', strjoin(msgs(~cellfun(@isempty,msgs)), ' '));
                error('NMTrainTemplateAPITools:noCopyPerformed', '%s', out.message);
            end
        end

        function [NM, out] = configureAuxiliaryDefaults(NM, spec)
            % configureAuxiliaryDefaults  Materialize runtime auxiliary defaults before analysis snapshotting.
            %
            % [NM, out] = NMTrainTemplateAPITools.configureAuxiliaryDefaults(NM, spec)
            % fills the feature-selection, visualization, model-interpretation
            % and OOCV runtime branches that are required by legacy NeuroMiner
            % analysis snapshots even when the caller only supplies a compact
            % preprocessing/learner spec. configureOneModality calls this
            % method after the main template and SAV branch have been written.
            %
            % The method reads the current state from NMRFETools, NMVISTools,
            % NMMLITools and NMOOCVTools, merges optional override structs from
            % spec.rfe: optional RFE override; spec.vis: optional VIS override; spec.mli: optional MLI override; spec.oocv: optional OOCV override. The method marks the respective
            % branches dirty, and calls each tool's configure method so the
            % corresponding TrainParam substructure is materialized in NM. It
            % preserves the caller's varind/fusionFlag routing for RFE, VIS and
            % MLI; OOCV is workspace-level and is configured without a modality
            % index.
            %
            % Inputs:
            % NM    Training workspace struct to update.
            % spec  Scalar struct. Relevant fields are varind, fusionFlag,
            % and optional rfe/vis/mli/oocv override structs. Missing
            % varind and fusionFlag default to 1 and 0.
            %
            % out.ok is true on success and out.rfeReport, out.visReport,
            % out.mliReport and out.oocvReport contain the tool-level reports.
            % Missing auxiliary tool classes or failed branch reports raise
            % component-specific errors because downstream analysis creation
            % should not proceed with incomplete TrainParam defaults.
            %
            % spec.fusionFlag: supplies the fusion flag value in the public API/import specification.
            % spec.varind: selects the modality index addressed by the runner or configuration operation.
            %
            % spec.vis: optional VIS override struct merged before NMVISTools.configure materializes TrainParam.VIS.
            % spec.mli: optional MLI override struct merged before NMMLITools.configure materializes TrainParam.MLI.
            % spec.oocv: optional OOCV override struct merged before NMOOCVTools.configure materializes TrainParam.OOCV.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if ~isfield(spec,'varind') || isempty(spec.varind), spec.varind = 1; end
            if ~isfield(spec,'fusionFlag') || isempty(spec.fusionFlag), spec.fusionFlag = 0; end
            spec.varind = max(1, round(double(spec.varind)));

            out = struct('ok',true, 'message','Runtime auxiliary defaults materialized.', ...
                'rfeReport',[], 'visReport',[], 'mliReport',[], 'oocvReport',[]);

            if exist('NMRFETools','class') ~= 8
                error('NMTrainTemplateAPITools:missingNMRFETools', ...
                    'NMRFETools is required to materialize TrainParam.RFE defaults before analysis snapshotting.');
            end
            rfeState = NMRFETools.stateFromNM(NM, spec.varind, spec.fusionFlag);
            if isfield(spec,'rfe') && isstruct(spec.rfe), rfeState = NMTrainTemplateAPITools.mergeStruct(rfeState, spec.rfe); end
            rfeState.rfeDirty = true;
            [NM, rfeState, rfeReport] = NMRFETools.configure(NM, rfeState, ...
                'VarIndex', spec.varind, 'FusionFlag', spec.fusionFlag, 'rfeDirty', true); %#ok<ASGLU>
            if isfield(rfeReport,'ok') && ~rfeReport.ok
                error('NMTrainTemplateAPITools:rfeFailed', 'RFE/default feature-selection configuration failed: %s', NMTrainTemplateAPITools.reportText(rfeReport));
            end
            out.rfeReport = rfeReport;

            if exist('NMVISTools','class') ~= 8
                error('NMTrainTemplateAPITools:missingNMVISTools', ...
                    'NMVISTools is required to materialize TrainParam.VIS defaults before analysis snapshotting.');
            end
            visState = NMVISTools.stateFromNM(NM, spec.varind, spec.fusionFlag);
            if isfield(spec,'vis') && isstruct(spec.vis), visState = NMTrainTemplateAPITools.mergeStruct(visState, spec.vis); end
            visState.visDirty = true;
            [NM, visState, visReport] = NMVISTools.configure(NM, visState, ...
                'VarIndex', spec.varind, 'FusionFlag', spec.fusionFlag, 'visDirty', true); %#ok<ASGLU>
            if isfield(visReport,'ok') && ~visReport.ok
                error('NMTrainTemplateAPITools:visFailed', 'Visualization/default VIS configuration failed: %s', NMTrainTemplateAPITools.reportText(visReport));
            end
            out.visReport = visReport;

            if exist('NMMLITools','class') ~= 8
                error('NMTrainTemplateAPITools:missingNMMLITools', ...
                    'NMMLITools is required to materialize TrainParam.MLI defaults before analysis snapshotting.');
            end
            mliState = NMMLITools.stateFromNM(NM, spec.varind, spec.fusionFlag);
            if isfield(spec,'mli') && isstruct(spec.mli), mliState = NMTrainTemplateAPITools.mergeStruct(mliState, spec.mli); end
            mliState.mliDirty = true;
            [NM, mliState, mliReport] = NMMLITools.configure(NM, mliState, ...
                'VarIndex', spec.varind, 'FusionFlag', spec.fusionFlag, 'mliDirty', true); %#ok<ASGLU>
            if isfield(mliReport,'ok') && ~mliReport.ok
                error('NMTrainTemplateAPITools:mliFailed', 'MLI/default interpretation configuration failed: %s', NMTrainTemplateAPITools.reportText(mliReport));
            end
            out.mliReport = mliReport;

            if exist('NMOOCVTools','class') ~= 8
                error('NMTrainTemplateAPITools:missingNMOOCVTools', ...
                    'NMOOCVTools is required to materialize TrainParam.OOCV defaults before analysis snapshotting.');
            end
            oocvState = NMOOCVTools.stateFromNM(NM);
            if isfield(spec,'oocv') && isstruct(spec.oocv), oocvState = NMTrainTemplateAPITools.mergeStruct(oocvState, spec.oocv); end
            oocvState.oocvDirty = true;
            [NM, oocvState, oocvReport] = NMOOCVTools.configure(NM, oocvState, 'oocvDirty', true); %#ok<ASGLU>
            if isfield(oocvReport,'ok') && ~oocvReport.ok
                error('NMTrainTemplateAPITools:oocvFailed', 'OOCV/default independent-test configuration failed: %s', NMTrainTemplateAPITools.reportText(oocvReport));
            end
            out.oocvReport = oocvReport;
        end

        function spec = defaultOneModalitySpec()
            % defaultOneModalitySpec  Return the compact API defaults for one-modality template creation.
            %
            %   spec = NMTrainTemplateAPITools.defaultOneModalitySpec() returns
            %   the scalar struct used by normalizeSpec and configureOneModality
            %   as the baseline for scripted template creation. The default path
            %   targets modality 1, applies no subject-level preprocessing, applies
            %   median imputation followed by mean standardization at the CV level,
            %   selects LIBSVM as the learner, disables model saving, enables
            %   runtime verbosity, and provides empty override structs for RFE,
            %   VIS, MLI and OOCV.
            %
            %   This method is read-only. It does not inspect or mutate NM. Power
            %   users can call it to obtain a stable schema, edit selected fields,
            %   and pass the result to configureOneModality. The empty
            %   modelSaveName intentionally means "let NMSAVTools derive the
            %   default model MAT name from the workspace" when saving is enabled
            %   by the caller.

            spec = struct();
            spec.varind = 1;
            spec.subjectPreproc = {};
            spec.cvPreproc = { ...
                struct('moduleId','impute', 'config',struct('method','median')), ...
                struct('moduleId','standardize', 'config',struct('method','mean','useIQR',false))};
            spec.learner = struct('algorithm','LIBSVM');
            spec.fusionFlag = 0;
            spec.fusionModalities = 1;
            spec.stackingFlag = 2;
            spec.saveModel = false;
            spec.modelSaveName = '';  % Empty user input is resolved to NMSAVTools.defaultMatName(NM).
            spec.verbosity = true;
            spec.rfe = struct();
            spec.vis = struct();
            spec.mli = struct();
            spec.oocv = struct();
        end
    end

    methods (Static, Access = private)
        function spec = normalizeSpec(spec)
            d = NMTrainTemplateAPITools.defaultOneModalitySpec();
            spec = NMTrainTemplateAPITools.mergeStruct(d, spec);
            spec.varind = max(1, round(double(spec.varind)));
            if isempty(spec.fusionModalities), spec.fusionModalities = spec.varind; end
            if ~iscell(spec.cvPreproc), spec.cvPreproc = num2cell(spec.cvPreproc); end
            if ~iscell(spec.subjectPreproc), spec.subjectPreproc = num2cell(spec.subjectPreproc); end
            if ~isstruct(spec.learner), spec.learner = struct('algorithm','LIBSVM'); end
            if ~isfield(spec,'saveModel') || isempty(spec.saveModel), spec.saveModel = false; end
            if ~isfield(spec,'modelSaveName'), spec.modelSaveName = ''; end
            if ~isfield(spec,'verbosity') || isempty(spec.verbosity), spec.verbosity = true; end
        end


        function spec = normalizeCopyPreprocSpec(NM, spec)
            if ~isstruct(spec), spec = struct(); end
            if ~isfield(spec,'sourceModality') || isempty(spec.sourceModality)
                if isfield(spec,'varind') && ~isempty(spec.varind)
                    spec.sourceModality = spec.varind;
                else
                    spec.sourceModality = 1;
                end
            end
            if isnumeric(spec.sourceModality) || islogical(spec.sourceModality)
                spec.sourceModality = max(1, round(double(spec.sourceModality(1))));
            else
                v = str2double(char(string(spec.sourceModality)));
                if ~isfinite(v), v = 1; end
                spec.sourceModality = max(1, round(v));
            end
            if ~isfield(spec,'targetModalities') || isempty(spec.targetModalities)
                spec.targetModalities = setdiff(1:NMTrainTemplateAPITools.numModalities(NM), spec.sourceModality);
            end
            if isnumeric(spec.targetModalities) || islogical(spec.targetModalities)
                spec.targetModalities = round(double(spec.targetModalities(:)'));
            else
                spec.targetModalities = str2double(cellstr(string(spec.targetModalities(:)')));
            end
            spec.targetModalities = spec.targetModalities(isfinite(spec.targetModalities));
            if ~isfield(spec,'copyMode') || isempty(spec.copyMode), spec.copyMode = 'replace'; end
            spec.copyMode = char(string(spec.copyMode));
            if ~isfield(spec,'requireUnlocked') || isempty(spec.requireUnlocked), spec.requireUnlocked = true; end
            spec.requireUnlocked = logical(spec.requireUnlocked);
            if ~isfield(spec,'validateTargets') || isempty(spec.validateTargets), spec.validateTargets = true; end
            spec.validateTargets = logical(spec.validateTargets);
        end

        function n = numModalities(NM)
            n = 1;
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = max(1, numel(NM.Y));
            elseif isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor)
                n = max(1, numel(NM.datadescriptor));
            end
        end

        function PREPROC = legacyPreprocAt(NM, idx)
            PREPROC = [];
            try
                if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'FUSION') && isstruct(NM.TrainParam.FUSION) && ...
                        isfield(NM.TrainParam.FUSION,'flag') && double(NM.TrainParam.FUSION.flag) == 3 && ...
                        isfield(NM.TrainParam,'STRAT') && iscell(NM.TrainParam.STRAT) && numel(NM.TrainParam.STRAT) >= idx && ...
                        isstruct(NM.TrainParam.STRAT{idx}) && isfield(NM.TrainParam.STRAT{idx},'PREPROC')
                    PREPROC = NM.TrainParam.STRAT{idx}.PREPROC;
                    return;
                end
                if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'PREPROC') && iscell(NM.TrainParam.PREPROC) && ...
                        numel(NM.TrainParam.PREPROC) >= idx
                    PREPROC = NM.TrainParam.PREPROC{idx};
                end
            catch
                PREPROC = [];
            end
        end

        function n = preprocStepCount(state)
            n = 0;
            try
                if isfield(state,'subject') && isfield(state.subject,'sequence') && isfield(state.subject.sequence,'steps')
                    n = n + numel(state.subject.sequence.steps);
                end
                if isfield(state,'cv') && isfield(state.cv,'sequence') && isfield(state.cv.sequence,'steps')
                    n = n + numel(state.cv.sequence.steps);
                elseif isfield(state,'sequence') && isfield(state.sequence,'steps')
                    n = n + numel(state.sequence.steps);
                end
            catch
                n = 0;
            end
        end

        function labels = preprocStepLabels(state)
            labels = {};
            try
                stages = {'subject','cv'};
                for sidx = 1:numel(stages)
                    stage = stages{sidx};
                    steps = {};
                    if isfield(state,stage) && isfield(state.(stage),'sequence') && isfield(state.(stage).sequence,'steps')
                        steps = state.(stage).sequence.steps;
                    end
                    if isstruct(steps), steps = num2cell(steps); end
                    for k = 1:numel(steps)
                        st = steps{k};
                        if isstruct(st) && isfield(st,'moduleId')
                            labels{end+1} = sprintf('%s: %s', stage, char(string(st.moduleId))); %#ok<AGROW>
                        end
                    end
                end
            catch
                labels = {};
            end
        end

        function [ok, msg, warnings] = validateCopyPreprocTarget(NM, targetIdx, sourceState, spec)
            ok = true;
            msg = '';
            warnings = {};
            if ~spec.validateTargets, return; end
            nFeat = NMTrainTemplateAPITools.modalityFeatureCount(NM, targetIdx);
            maxDim = NMTrainTemplateAPITools.maxAbsoluteProjectionDim(sourceState);
            if isfinite(nFeat) && isfinite(maxDim) && maxDim > nFeat
                ok = false;
                msg = sprintf(['Target modality %g has %g feature(s), but the source preprocessing contains ', ...
                    'an absolute dimensionality-reduction request of %g component(s).'], double(targetIdx), double(nFeat), double(maxDim));
                return;
            end
            if ~isfinite(nFeat)
                warnings{end+1} = sprintf('Target modality %g feature count is unknown; dimensionality-specific preprocessing could not be prevalidated.', double(targetIdx));
            end
        end

        function nFeat = modalityFeatureCount(NM, idx)
            nFeat = NaN;
            try
                if isfield(NM,'Y') && iscell(NM.Y) && numel(NM.Y) >= idx && ~isempty(NM.Y{idx}) && isnumeric(NM.Y{idx})
                    nFeat = size(NM.Y{idx},2);
                elseif isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && numel(NM.datadescriptor) >= idx && ...
                        isstruct(NM.datadescriptor{idx}) && isfield(NM.datadescriptor{idx},'n_features')
                    nFeat = double(NM.datadescriptor{idx}.n_features);
                end
            catch
                nFeat = NaN;
            end
        end

        function maxDim = maxAbsoluteProjectionDim(state)
            maxDim = NaN;
            try
                stages = {'subject','cv'};
                vals = [];
                for sidx = 1:numel(stages)
                    stage = stages{sidx};
                    steps = {};
                    if isfield(state,stage) && isfield(state.(stage),'sequence') && isfield(state.(stage).sequence,'steps')
                        steps = state.(stage).sequence.steps;
                    end
                    if isstruct(steps), steps = num2cell(steps); end
                    for k = 1:numel(steps)
                        st = steps{k};
                        if ~isstruct(st) || ~isfield(st,'moduleId') || ~isfield(st,'config'), continue; end
                        id = lower(char(string(st.moduleId)));
                        if ~any(strcmp(id, {'reducedim','remvarcomp'})), continue; end
                        cfg = st.config;
                        if ~isfield(cfg,'fitDim') || isempty(cfg.fitDim), continue; end
                        if NMTrainTemplateAPITools.isAbsoluteProjectionMode(cfg)
                            v = double(cfg.fitDim(:));
                            v = v(isfinite(v));
                            vals = [vals; v(:)]; %#ok<AGROW>
                        end
                    end
                end
                if ~isempty(vals), maxDim = max(vals); end
            catch
                maxDim = NaN;
            end
        end

        function tf = isAbsoluteProjectionMode(cfg)
            tf = true;
            try
                if isfield(cfg,'percMode') && ~isempty(cfg.percMode)
                    pm = cfg.percMode;
                elseif isfield(cfg,'dimMode') && ~isempty(cfg.dimMode)
                    pm = cfg.dimMode;
                else
                    pm = [];
                end
                if isempty(pm), return; end
                if isnumeric(pm) || islogical(pm)
                    tf = double(pm(1)) == 1;
                else
                    txt = lower(char(string(pm)));
                    tf = any(strcmp(txt, {'absolute','fixed','components','component'}));
                end
            catch
                tf = true;
            end
        end

        function mode = modeflag(NM)
            mode = 'classification';
            if isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                mode = char(string(NM.modeflag));
            end
        end

        function s = mergeStruct(a, b)
            s = a;
            if ~isstruct(b), return; end
            if ~isscalar(b)
                s = b;
                return;
            end
            fn = fieldnames(b);
            for i = 1:numel(fn)
                v = b.(fn{i});
                if isfield(s,fn{i})
                    sv = s.(fn{i});
                else
                    sv = [];
                end
                if isstruct(v) && isscalar(v) && isstruct(sv) && isscalar(sv)
                    s.(fn{i}) = NMTrainTemplateAPITools.mergeStruct(sv, v);
                else
                    s.(fn{i}) = v;
                end
            end
        end

        function txt = reportText(report)
            txt = '';
            if isfield(report,'errors') && ~isempty(report.errors)
                try, txt = strjoin(cellstr(string(report.errors)), '; '); catch, txt = 'see report.errors'; end
            elseif isfield(report,'message') && ~isempty(report.message)
                txt = char(string(report.message));
            end
        end
    end
end
