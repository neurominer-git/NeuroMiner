classdef NMDataIOImportTools
% NMDataIOImportTools
% -------------------------------------------------------------------------
% Matrix/table import execution helpers for the browser/API DataIO port.
%
% Purpose / authority:
%   Generic scientific materialization authority for matrix/tabular DataIO. Provenance-specific
%   layers stop at retrieval/type conversion; filtering, role materialization, Case-ID alignment,
%   first-axis policy, Preview/QC and Commit converge here.
%
% Execution contract:
%   - materialize each scientific source once per unchanged import state;
%   - derive diagnostics, mandatory QC, and Preview from that retained IO;
%   - Commit consumes the retained IO or invokes the same materializer on cache miss;
%   - preserve DataIO message semantics via NMDataIOMessageTools.
%
% Invariants / failure semantics:
%   No permissive fallback may silently replace invalid keys, filters, labels or source identity.
%   Blocking conditions are returned as structured DataIO messages. Preview does not mutate the
%   committed modality; Commit is the mutation boundary.
% -------------------------------------------------------------------------

    methods (Static)
        function out = matrixPreview(NM, state, opts)
            % matrixPreview  Preview, diagnose, and QC one canonical retained matrix materialization.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOImportTools.emptyServiceOut('matrixPreview');
            progressTask = NMProgressTools.fromOptions(opts, 'Preparing DataIO preview', 'Reading selected source data.');
            opts.ProgressTask = progressTask;
            try
                [entry, cacheHit, cacheKey] = NMDataIOImportTools.materializeMatrixImport(NM, state, opts);
                messages = entry.messages;
                out.audit = NMDataIOImportTools.dataIOAuditFromIO(entry.IO);
                if NMDataIOMessageTools.hasFatal(messages) && ~logical(NMDataIOImportTools.fieldOr(entry,'previewableBlocking',false))
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    out.preview = struct();
                    NMProgressTools.finish(progressTask, out.message);
                    return;
                end
                page = NMDataIOImportTools.opt(opts, 'Page', NMDataIOImportTools.stateNumber(state, {'page','previewPage'}, 1));
                pageSize = NMDataIOImportTools.opt(opts, 'PageSize', NMDataIOImportTools.stateNumber(state, {'pageSize','previewPageSize'}, 30));
                maxCols = NMDataIOImportTools.opt(opts, 'MaxColumns', NMDataIOImportTools.stateNumber(state, {'maxColumns','previewMaxColumns'}, 20));
                progressTask = NMProgressTools.phase(progressTask, 'preview_slice', 92, 98, 'Preparing the Preview table.');
                [preview, IO] = NMDataIOImportTools.previewFromIO(entry.IO, page, pageSize, maxCols);
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'NMDataIOImportTools.matrixPreview', ...
                    sprintf('Preview prepared: %g case row(s) and %g feature column(s) shown.', numel(preview.rowIndex), numel(preview.columnIndex)), 0, 'green*')];
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.preview = preview;
                out.probe = entry.probe;
                out.qc = entry.qc;
                out.cacheHit = cacheHit; out.materializationCacheKey = cacheKey;
                out.statePatch = NMDataIOStateTools.ioToState(NMDataIOProbeTools.stripTransientIO(IO));
                NMProgressTools.finish(progressTask, out.message);
            catch ME
                NMProgressTools.fail(progressTask, 'NMDataIOImportTools.matrixPreview', ME);
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOImportTools.matrixPreview');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.preview = struct();
            end
        end

        function identityState = materializationIdentityState(NM, state)
            % Bind retained Preview identity to the scientific target context used during preparation.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            identityState = state;
            target = NMDataIOImportTargetTools.normalize(NM,state,NMDataIOImportTools.fieldOr(state,'varind',[]));
            [targetContainer,targetMessages] = NMDataIOImportTargetTools.getContainer(NM,target);
            context = struct('targetAvailable',~NMDataIOMessageTools.hasFatal(targetMessages), ...
                'referenceCases',{{}},'trainingFeatures',{{}},'trainingClassMap',struct(), ...
                'trainingModeflag',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(NM,'modeflag','')), ...
                'trainingGroupnames',{NMDataIOImportTools.fieldOr(NM,'groupnames',{})},'trainingInputSettings',struct());
            if context.targetAvailable
                referenceContainer = NMDataIOImportTools.alignmentReferenceContainer(NM,targetContainer,target);
                context.referenceCases = NMDataIOImportTools.containerCases(referenceContainer);
            end
            % A new training modality's unfinished draft is the import being prepared,
            % not an independent target reference. Its input_settings can be re-saved
            % when Preview/QC artifacts are persisted without changing scientific input.
            % Existing training modalities remain target references for OOCV and Modify.
            targetHasTrainingReference = NMDataIOImportTargetTools.isOOCV(target) || ...
                NMDataIOUI.hasCommittedFeatureData(NM,target.varind);
            if targetHasTrainingReference
                context.trainingFeatures = NMDataIOImportTools.trainingFeatureNames(NM,target.varind);
            end
            context.trainingClassMap = NMDataIOImportTools.trainingClassificationLabelMap(NM);
            % nm2-allow: Inherited NM1.4 descriptors may omit optional input_settings entirely.
            if targetHasTrainingReference && isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && ...
                    numel(NM.datadescriptor) >= target.varind && isstruct(NM.datadescriptor{target.varind}) && ...
                    isfield(NM.datadescriptor{target.varind},'input_settings') && isstruct(NM.datadescriptor{target.varind}.input_settings)
                % input_settings remains the MATLAB-side import-definition repository and the
                % training template for OOCV/application import. Project it through the existing
                % rehydration authority so cache identity sees its scientific state, not Preview/
                % draft artifacts; Matrix Inspector masks remain late transfer state.
                repositoryState = NMDataIOStateTools.ioToState(NM.datadescriptor{target.varind}.input_settings);
                context.trainingInputSettings = NMDataIOMaterializationCache.withoutMatrixItemSelection(repositoryState);
            end
            identityState.materializationTargetContextKey = NMDataIOMaterializationCache.keyForState('target',context);
        end

        function [entry, cacheHit, cacheKey, owner] = materializeMatrixImport(NM, state, opts)
            % materializeMatrixImport  Resolve one canonical matrix/table/database payload and mandatory QC.
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMDataIOImportTools.fieldOr(opts, 'ProgressTask', NMProgressTools.emptyTaskForLocalUse()); cacheKeyHint = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(opts,'MaterializationCacheKey',''));
            requireRetained = logical(NMDataIOImportTools.fieldOr(opts,'RequireRetainedMaterialization',false));
            owner = NMDataIOUI.sessionKey(NMDataIOImportTools.fieldOr(opts,'tmpDir',''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit,entry,cacheKey] = NMDataIOImportTools.retainedMaterialization('matrix',identityState,cacheKeyHint,requireRetained,owner,'');
            if cacheHit
                NMProgressTools.phase(progressTask, 'preview_cache_hit', 0, 92, 'Reusing the data, diagnostics and QC from the current Preview.');
                return;
            end
            materialState = NMDataIOMaterializationCache.withoutMatrixItemSelection(state);
            doProfile = NMDataIOProfileTools.enabled([], [], opts);
            profileLabel = char(string(NMDataIOImportTools.opt(opts, 'ProfileLabel', 'materializeMatrixImport')));
            progressTask = NMProgressTools.phase(progressTask, 'preview_source_materialization', 0, 50, 'Reading the selected source data.');
            prepareOpts = struct('RequireReady', true, 'ProfileEnabled', doProfile, 'ProfileLabel', [profileLabel '.prepareMatrixIO'], 'ProgressTask', progressTask);
            [IO, messages] = NMDataIOImportTools.prepareMatrixIO(NM, materialState, prepareOpts);
            progressTask = NMProgressTools.phase(progressTask, 'preview_diagnostics', 50, 65, 'Checking Case-ID matching and import settings.');
            if ~NMDataIOMessageTools.hasFatal(messages)
                [IO, alignMessages] = NMDataIOImportTools.applyReferenceCaseAlignmentIfNeeded(NM, IO, 'probe');
                messages = [messages; alignMessages];
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                [~, IO] = NMDataIOImportTools.previewFromIO(IO, 1, 1, 1); % forces source materialization once
                importTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, IO.varind);
                [IO, resolvedMessages] = NMDataIOImportTools.prepareResolvedMatrixPayload(IO, NM, importTarget);
                messages = [messages; resolvedMessages];
            end
            probe = struct(); qc = struct();
            structurallyReadyForPreview = ~NMDataIOMessageTools.hasFatal(messages);
            if structurallyReadyForPreview
                probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, struct());
                sourceType = lower(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(materialState,'sourceType','matrix')));
                progressTask = NMProgressTools.phase(progressTask, 'preview_mandatory_qc', 65, 90, 'Computing mandatory QC from the prepared Preview data.');
                qcOpts = opts; qcOpts.ProgressTask = progressTask; qcOpts.ReferenceNM = NM;
                [qc, qcMessages] = NMDataIOFeatureQCTools.computeFromMaterializedIO(IO, sourceType, qcOpts, struct());
                messages = [messages; qcMessages];
            end
            numericMessages = NMDataIOImportTools.numericSourceIssueMessages(IO);
            messages = [messages; numericMessages];
            previewableBlocking = structurallyReadyForPreview && ~isempty(numericMessages) && NMDataIOMessageTools.hasFatal(messages);
            entry = struct('IO',IO,'messages',messages,'probe',probe,'qc',qc,'previewableBlocking',previewableBlocking);
            if ~NMDataIOMessageTools.hasFatal(messages) || previewableBlocking
                NMProgressTools.phase(progressTask, 'preview_cache_store', 90, 92, 'Keeping the prepared Preview data, diagnostics and QC for Commit.');
                cacheKey = NMDataIOMaterializationCache.put('matrix', identityState, entry, owner);
            end
        end

        function [entry, cacheHit, cacheKey, owner] = materializeROIImport(NM, state, opts)
            % materializeROIImport  Resolve one retained canonical ROI payload and mandatory QC.
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMDataIOImportTools.fieldOr(opts,'ProgressTask',NMProgressTools.emptyTaskForLocalUse());
            cacheKeyHint = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(opts,'MaterializationCacheKey',''));
            requireRetained = logical(NMDataIOImportTools.fieldOr(opts,'RequireRetainedMaterialization',false));
            owner = NMDataIOUI.sessionKey(NMDataIOImportTools.fieldOr(opts,'tmpDir',''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit,entry,cacheKey] = NMDataIOImportTools.retainedMaterialization('roi',identityState,cacheKeyHint,requireRetained,owner,'ROI ');
            if cacheHit
                NMProgressTools.phase(progressTask,'roi_preview_cache_hit',0,98,'Reusing the ROI data, diagnostics and QC from the current Preview.');
                return;
            end
            materialState = NMDataIOMaterializationCache.withoutMatrixItemSelection(state);
            progressTask = NMProgressTools.phase(progressTask,'roi_preview_source_materialization',0,60,'Reading the selected ROI data.');
            resolveOpts = opts; resolveOpts.ProgressTask = progressTask;
            [roiOut,resolvedState,messages,roiSpec] = NMDataIOAPITools.prepareROIImportState(NM,materialState,resolveOpts);
            IO = struct(); probe = struct(); qc = struct(); viewerReference = struct();
            progressTask = NMProgressTools.phase(progressTask,'roi_preview_diagnostics',60,72,'Checking the ROI data and spatial reference.');
            if ~NMDataIOMessageTools.hasFatal(messages)
                IO = NMDataIOStateTools.stateToIO(resolvedState,NM);
                importTarget = NMDataIOImportTargetTools.normalize(NM,IO.importTarget,IO.varind);
                [IO,resolvedMessages] = NMDataIOImportTools.prepareResolvedMatrixPayload(IO,NM,importTarget);
                messages = [messages;resolvedMessages];
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                probe = NMDataIOProbeTools.matrixSummaryFromIO(IO,struct());
                progressTask = NMProgressTools.phase(progressTask,'roi_preview_mandatory_qc',72,96,'Computing mandatory ROI QC from the prepared Preview data.');
                qcOpts = opts; qcOpts.ProgressTask = progressTask; qcOpts.ReferenceNM = NM;
                refs = NMDataIOImportTools.fieldOr(NMDataIOImportTools.fieldOr(roiOut,'roiProvenance',struct()),'spatialReferences',struct([]));
                if isstruct(refs) && ~isempty(refs)
                    kinds = arrayfun(@(r)lower(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(r,'kind',''))),refs,'UniformOutput',false);
                    if any(strcmp(kinds,'volumetric_atlas')), qcOpts.structuralFile = NMImagingTemplateService.structuralReferenceFile(NM); end
                end
                [qc,qcMessages] = NMDataIOFeatureQCTools.computeFromMaterializedIO(IO,'roi',qcOpts,roiOut);
                messages = [messages;qcMessages];
                viewerReference = NMDataIOImportTools.fieldOr(qc,'viewerOverlay',struct());
            end
            statePatch = NMDataIOStateTools.ioToState(NMDataIOProbeTools.stripTransientIO(IO));
            roiCachePayload = struct('roiProvenance',NMDataIOImportTools.fieldOr(roiOut,'roiProvenance',struct()), ...
                'globalVolumeCorrection',NMDataIOImportTools.fieldOr(roiOut,'globalVolumeCorrection',struct()), ...
                'importReport',NMDataIOImportTools.fieldOr(roiOut,'importReport',struct()), ...
                'sourceMetadata',NMDataIOImportTools.fieldOr(roiOut,'sourceMetadata',struct()));
            if isfield(roiOut,'weightingProvenance'), roiCachePayload.weightingProvenance = roiOut.weightingProvenance; end
            entry = struct('IO',IO,'statePatch',statePatch,'sourcePayload',roiCachePayload,'messages',messages,'probe',probe,'qc',qc,'viewerReference',viewerReference,'spec',roiSpec);
            if ~NMDataIOMessageTools.hasFatal(messages)
                NMProgressTools.phase(progressTask,'roi_preview_cache_store',96,98,'Keeping the prepared ROI Preview data, diagnostics and QC for Commit.');
                cacheKey = NMDataIOMaterializationCache.put('roi',identityState,entry, owner);
            end
        end

        function [entry, cacheHit, cacheKey, owner] = materializeConnectivityImport(NM, state, opts)
            % materializeConnectivityImport  Resolve one retained canonical connectivity payload and mandatory QC.
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMDataIOImportTools.fieldOr(opts,'ProgressTask',NMProgressTools.emptyTaskForLocalUse());
            cacheKeyHint = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(opts,'MaterializationCacheKey',''));
            requireRetained = logical(NMDataIOImportTools.fieldOr(opts,'RequireRetainedMaterialization',false));
            owner = NMDataIOUI.sessionKey(NMDataIOImportTools.fieldOr(opts,'tmpDir',''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit,entry,cacheKey] = NMDataIOImportTools.retainedMaterialization('connectivity',identityState,cacheKeyHint,requireRetained,owner,'connectivity ');
            if cacheHit
                NMProgressTools.phase(progressTask,'connectivity_preview_cache_hit',0,98,'Reusing the connectivity data, diagnostics and QC from the current Preview.');
                return;
            end
            materialState = NMDataIOMaterializationCache.withoutMatrixItemSelection(state);
            progressTask = NMProgressTools.phase(progressTask,'connectivity_preview_source_materialization',0,60,'Reading the selected connectivity data.');
            resolveOpts = opts; resolveOpts.ResolveWeighting = true; resolveOpts.ProgressTask = progressTask;
            [connOut,resolvedState,messages,spec,compatReport] = NMDataIOAPITools.prepareConnectivityImportState(NM,materialState,resolveOpts);
            IO = struct(); probe = struct(); qc = struct();
            if ~NMDataIOMessageTools.hasFatal(messages)
                IO = NMDataIOStateTools.stateToIO(resolvedState,NM);
                if isfield(materialState,'importTarget') && isstruct(materialState.importTarget)
                    IO.importTarget = NMDataIOImportTargetTools.normalize(NM,materialState,NMDataIOStateTools.pick(materialState,{'varind'},[]));
                end
            end
            progressTask = NMProgressTools.phase(progressTask,'connectivity_preview_diagnostics',60,72,'Running Preview diagnostics and edge-space validation.');
            if ~NMDataIOMessageTools.hasFatal(messages)
                importTarget = NMDataIOImportTargetTools.normalize(NM,IO.importTarget,IO.varind);
                [IO,resolvedMessages] = NMDataIOImportTools.prepareResolvedMatrixPayload(IO,NM,importTarget);
                messages = [messages;resolvedMessages];
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                probe = NMDataIOProbeTools.matrixSummaryFromIO(IO,struct());
                progressTask = NMProgressTools.phase(progressTask,'connectivity_preview_mandatory_qc',72,96,'Computing mandatory connectivity QC from the prepared Preview data.');
                qcOpts = opts; qcOpts.ProgressTask = progressTask; qcOpts.ReferenceNM = NM;
                [qc,qcMessages] = NMDataIOFeatureQCTools.computeFromMaterializedIO(IO,'connectivity',qcOpts,connOut);
                messages = [messages;qcMessages];
            end
            connCachePayload = struct('provenance',NMDataIOImportTools.fieldOr(connOut,'provenance',struct()), ...
                'importReport',NMDataIOImportTools.fieldOr(connOut,'importReport',struct()));
            entry = struct('IO',IO,'sourcePayload',connCachePayload,'messages',messages,'probe',probe,'qc',qc,'spec',spec,'compatibility',compatReport);
            if ~NMDataIOMessageTools.hasFatal(messages)
                NMProgressTools.phase(progressTask,'connectivity_preview_cache_store',96,98,'Keeping the prepared connectivity Preview data, diagnostics and QC for Commit.');
                cacheKey = NMDataIOMaterializationCache.put('connectivity',identityState,entry, owner);
            end
        end

        function out = imagePreview(NM, state, opts)
            % imagePreview  Preview, diagnose, and QC one retained spatial materialization.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOImportTools.emptyServiceOut('imagePreview');
            progressTask = NMProgressTools.fromOptions(opts, 'Preparing imaging preview', 'Reading selected imaging data.');
            opts.ProgressTask = progressTask;
            try
                [entry, cacheHit, cacheKey] = NMDataIOImportTools.materializeImageImport(NM, state, opts);
                out = NMDataIOImportTools.finishServiceOut(out, entry.messages);
                if ~out.ok
                    out.preview = struct();
                    NMProgressTools.finish(progressTask, out.message);
                    return;
                end
                progressTask = NMProgressTools.phase(progressTask, 'image_preview_rows', 99, 100, 'Preparing the imaging Preview table.');
                out.preview = NMDataIOImportTools.imagePreviewFromIO(entry.IO);
                out.probe = entry.probe;
                out.qc = entry.qc;
                out.cacheHit = cacheHit; out.materializationCacheKey = cacheKey;
                out.statePatch = NMDataIOStateTools.ioToState(NMDataIOProbeTools.stripTransientIO(entry.IO));
                NMProgressTools.finish(progressTask, out.message);
            catch ME
                NMProgressTools.fail(progressTask, 'NMDataIOImportTools.imagePreview', ME);
                out = NMDataIOImportTools.finishServiceOut(out, NMDataIOMessageTools.fromException(ME,'NMDataIOImportTools.imagePreview'));
                out.preview = struct();
            end
        end

        function [entry, cacheHit, cacheKey, owner] = materializeImageImport(NM, state, opts)
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMDataIOImportTools.fieldOr(opts, 'ProgressTask', NMProgressTools.emptyTaskForLocalUse()); cacheKeyHint = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(opts,'MaterializationCacheKey',''));
            requireRetained = logical(NMDataIOImportTools.fieldOr(opts,'RequireRetainedMaterialization',false));
            owner = NMDataIOUI.sessionKey(NMDataIOImportTools.fieldOr(opts,'tmpDir',''));
            identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
            [cacheHit,entry,cacheKey] = NMDataIOImportTools.retainedMaterialization('image',identityState,cacheKeyHint,requireRetained,owner,'imaging ');
            if cacheHit
                NMProgressTools.phase(progressTask, 'image_preview_cache_hit', 0, 99, 'Reusing the imaging data, diagnostics and QC from the current Preview.');
                return;
            end
            materialState = NMDataIOMaterializationCache.withoutMatrixItemSelection(state);
            progressTask = NMProgressTools.phase(progressTask, 'image_preview_source_materialization', 0, 5, 'Reading the selected imaging source settings.');
            importTarget = NMDataIOImportTargetTools.normalize(NM, materialState);
            [NMlocal, importTarget, targetMessages] = NMDataIOImportTargetTools.ensureContainer(NM, importTarget);
            messages = targetMessages;
            IO = struct();
            if ~NMDataIOMessageTools.hasFatal(messages)
                [IO, prepMessages] = NMDataIOImageImportTools.prepareImageIO(NMlocal, materialState, struct('RequireReady', true));
                messages = [messages; prepMessages];
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                importTarget = NMDataIOImportTargetTools.normalize(NMlocal, IO.importTarget, IO.varind);
                [targetContainer, containerMessages] = NMDataIOImportTargetTools.getContainer(NMlocal, importTarget);
                messages = [messages; containerMessages];
            else
                targetContainer = struct();
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType','')), 'surface-list')
                    importMessage = 'Reading the selected surface scalar data.';
                else
                    importMessage = 'Reading the selected volumetric image data.';
                end
                progressTask = NMProgressTools.phase(progressTask, 'image_preview_source_read', 5, 55, importMessage);
                progressTask = NMProgressTools.setIndeterminate(progressTask, importMessage, 'image_preview_source_read');
                [IO, readMessages] = NMDataIOImageImportTools.readImagePayload(IO, targetContainer, importTarget, NMlocal, progressTask);
                messages = [messages; readMessages];
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                auxiliaryRoles = NMDataIOImportTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
                labelRefs = {}; covariateRefs = {};
                if isstruct(auxiliaryRoles)
                    if isfield(auxiliaryRoles,'labels'), labelRefs = NMDataIOStateTools.roleRefCell(auxiliaryRoles.labels); end
                    if isfield(auxiliaryRoles,'covariates'), covariateRefs = NMDataIOStateTools.roleRefCell(auxiliaryRoles.covariates); end
                end
                if ~isempty(labelRefs) || ~isempty(covariateRefs)
                    resolvedRoles = auxiliaryRoles;
                    for roleName = {'globals','features','featureNames'}
                        if isfield(resolvedRoles, roleName{1}), resolvedRoles.(roleName{1}) = {}; end
                    end
                    IO.auxiliaryVariableRoles = resolvedRoles;
                    IO.covariateNameList = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covariateNames',{}));
                    [IO, auxiliaryMessages] = NMDataIOImportTools.materializeResolvedAuxiliaryRoles(IO);
                    IO.auxiliaryVariableRoles = auxiliaryRoles;
                    messages = [messages; auxiliaryMessages];
                    if ~NMDataIOMessageTools.hasFatal(messages) && ~isempty(labelRefs) && ...
                            strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification')),'regression') && ...
                            strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'auxiliarySourceType','workspace')),'tablefile') && ...
                            isfield(IO,'desc_labels') && ~isempty(IO.desc_labels)
                        IO.labelNamesSpec = IO.desc_labels;
                        IO.labelNamesSource = 'headers';
                    end
                    if ~NMDataIOMessageTools.hasFatal(messages) && ~isempty(covariateRefs)
                        covariateNaNMask = isnan(IO.covars);
                        if any(covariateNaNMask(:))
                            nCovariateNaN = nnz(covariateNaNMask);
                            nCasesWithCovariateNaN = nnz(any(covariateNaNMask,2));
                            nCovariatesWithNaN = nnz(any(covariateNaNMask,1));
                            IO.importReport.covariateMissingness = struct('hasNaN',true,'nNaN',double(nCovariateNaN), ...
                                'nCasesWithNaN',double(nCasesWithCovariateNaN),'nCovariatesWithNaN',double(nCovariatesWithNaN));
                            messages = [messages; NMDataIOMessageTools.make('warn', false, 'imageMetadata.covariates', ...
                                sprintf(['Imaging/surface covariates contain %g NaN value(s) across %g case(s) and %g covariate(s). ', ...
                                'Import will continue, but preprocessing or training operations that use these covariates require explicit imputation or complete-case handling.'], ...
                                double(nCovariateNaN),double(nCasesWithCovariateNaN),double(nCovariatesWithNaN)),2,'orange*')];
                        else
                            IO.importReport.covariateMissingness = struct('hasNaN',false,'nNaN',0,'nCasesWithNaN',0,'nCovariatesWithNaN',0);
                        end
                        IO.importReport.covariateMapping = NMDataIOImportTools.fieldOr(IO.importReport,'auxiliaryMaterialization',struct());
                    end
                end
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                labelsKnown = logical(NMDataIOImportTools.fieldOr(IO,'labels_known',true));
                if labelsKnown && strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification')),'classification') && ...
                        NMDataIOImportTargetTools.isOOCV(importTarget)
                    IO.trainingClassificationLabelMap = NMDataIOImportTools.trainingClassificationLabelMap(NMlocal);
                end
                [IO, labelMessages] = NMDataIOImportTools.prepareResolvedTransferCounts( ...
                    IO, numel(NMDataIOImportTools.asCaseCell(IO.ID)), labelsKnown);
                messages = [messages; labelMessages];
                if ~NMDataIOMessageTools.hasFatal(messages)
                    messages = [messages; NMDataIOImportTools.validateOOCVKnownLabels(IO, NMlocal)];
                end
                if ~NMDataIOMessageTools.hasFatal(messages) && ~isempty(labelRefs)
                    labelMapping = NMDataIOImportTools.fieldOr(IO.importReport,'auxiliaryMaterialization',struct());
                    if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification')),'classification')
                        labelMapping.derivedGroupSizes = NMDataIOImportTools.fieldOr(IO,'n_subjects',[]);
                        labelMapping.derivedGroupNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_groups',{}));
                    else
                        labelMapping.derivedLabelNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_labels',{}));
                        labelMapping.nRegressionLabels = size(IO.label,2);
                    end
                    IO.importReport.labelMapping = labelMapping;
                end
            end
            probe = struct(); qc = struct();
            if ~NMDataIOMessageTools.hasFatal(messages)
                progressTask = NMProgressTools.phase(progressTask, 'image_preview_diagnostics', 55, 65, 'Checking the prepared imaging data and import settings.');
                probe = NMDataIOImageImportTools.imageSummaryFromIO(IO, IO.varind);
                sourceType = lower(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(materialState,'sourceType','image-list')));
                if isempty(sourceType), sourceType = 'image-list'; end
                progressTask = NMProgressTools.phase(progressTask, 'image_preview_mandatory_qc', 65, 99, 'Computing mandatory imaging QC from the prepared Preview data.');
                qcOpts = opts; qcOpts.ProgressTask = progressTask; qcOpts.ReferenceNM = NM;
                [qc, qcMessages] = NMDataIOFeatureQCTools.computeFromMaterializedIO(IO, sourceType, qcOpts, struct());
                messages = [messages; qcMessages];
            end
            entry = struct('IO',IO,'messages',messages,'probe',probe,'qc',qc);
            if ~NMDataIOMessageTools.hasFatal(messages), cacheKey = NMDataIOMaterializationCache.put('image', identityState, entry, owner); end
        end

        function [hit, entry, key] = retainedMaterialization(family, identityState, requestedKey, required, owner, descriptor)
            % One scientific identity check for all retained Preview families; key is a locator only.
            if required && isempty(requestedKey)
                error('NMDataIOImportTools:previewMaterializationUnavailable', ...
                    'The %sdata prepared by the current Preview are no longer available. Run Preview again before Commit.',descriptor);
            end
            if required && ~strcmp(requestedKey,NMDataIOMaterializationCache.keyForState(family,identityState))
                error('NMDataIOImportTools:previewMaterializationChanged', ...
                    'The %simport settings have changed since Preview. Run Preview again before Commit.',descriptor);
            end
            [hit,entry,key] = NMDataIOMaterializationCache.get(family,identityState,requestedKey,owner);
            if required && ~hit
                error('NMDataIOImportTools:previewMaterializationUnavailable', ...
                    'The %sdata prepared by the current Preview are no longer available. Run Preview again before Commit.',descriptor);
            end
        end

        function preview = imagePreviewFromIO(IO)
            files = NMDataIOImportTools.asCellstr(NMDataIOImportTools.fieldOr(IO,'files',{}));
            if isempty(files), files = NMDataIOImportTools.asCellstr(NMDataIOImportTools.fieldOr(IO,'imageFiles',{})); end
            nRows = 0;
            if isfield(IO,'Y') && isnumeric(IO.Y), nRows = size(IO.Y,1); end
            if nRows < 1, nRows = numel(files); end
            ids = NMDataIOImportTools.asCellstr(NMDataIOImportTools.fieldOr(IO,'ID',{}));
            labels = NMDataIOImportTools.fieldOr(IO,'label',[]);
            globals = NMDataIOImportTools.fieldOr(IO,'g',[]);
            covars = NMDataIOImportTools.fieldOr(IO,'covars',[]);
            volumeDim = NMDataIOImportTools.fieldOr(IO,'Vdim',[]);
            volumeVoxelSize = NMDataIOImportTools.fieldOr(IO,'Vvox',[]);
            surfaceVertices = NaN; surfaceFormat = '';
            if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType','')), 'surface-list') && isfield(IO,'Vm') && isstruct(IO.Vm)
                surfaceVertices = double(NMDataIOImportTools.fieldOr(IO.Vm,'nVertices',NaN));
                surfaceFormats = NMDataIOImportTools.asCellstr(NMDataIOImportTools.fieldOr(IO.Vm,'format',{}));
                surfaceFormat = strjoin(surfaceFormats(:)', ', ');
            end
            rows = repmat(struct('index',0,'file','','caseId','','label',[],'globalValue',[],'covariates',[], ...
                'dim',[],'voxelSize',[],'status','OK','statusLevel','ok','statusText','Prepared Preview data','included',true), nRows, 1);
            for i = 1:nRows
                rows(i).index = i;
                if i <= numel(files), rows(i).file = files{i}; end
                if i <= numel(ids), rows(i).caseId = ids{i}; else, rows(i).caseId = sprintf('S%g',i); end
                if ~isempty(labels) && size(labels,1) >= i, rows(i).label = labels(i,:); end
                if ~isempty(globals) && size(globals,1) >= i, rows(i).globalValue = globals(i,:); end
                if ~isempty(covars) && size(covars,1) >= i, rows(i).covariates = covars(i,:); end
                if isfinite(surfaceVertices)
                    rows(i).dim = sprintf('%g vertices', surfaceVertices);
                    rows(i).voxelSize = surfaceFormat;
                else
                    if size(volumeDim,1) >= i && size(volumeDim,2) >= 3 && all(isfinite(volumeDim(i,1:3)))
                        rows(i).dim = sprintf('%g×%g×%g', volumeDim(i,1), volumeDim(i,2), volumeDim(i,3));
                    end
                    if size(volumeVoxelSize,1) >= i && size(volumeVoxelSize,2) >= 3 && all(isfinite(volumeVoxelSize(i,1:3)))
                        rows(i).voxelSize = sprintf('%.3g×%.3g×%.3g', volumeVoxelSize(i,1), volumeVoxelSize(i,2), volumeVoxelSize(i,3));
                    end
                end
            end
            preview = struct('rows',rows,'nRows',double(nRows),'page',1,'pageSize',double(nRows),'paged',false,'persistedPreview',false);
        end

        function out = commitImageImport(NM, state, opts)
            % commitImageImport  Commit retained Preview materialization; read sources only when Preview was not performed.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMProgressTools.fromOptions(opts, 'Committing imaging import', 'Checking the current imaging Preview data.');
            opts.ProgressTask = progressTask;
            out = NMDataIOImportTools.emptyServiceOut('commitImageImport'); out.NM = NM;
            try
                cacheKeyHint = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(opts,'MaterializationCacheKey',''));
                opts.RequireRetainedMaterialization = logical(NMDataIOImportTools.fieldOr(opts,'RequireRetainedMaterialization',~isempty(cacheKeyHint)));
                progressTask = NMProgressTools.phase(progressTask, 'image_commit_materialize', 0, 65, ...
                    'Reusing the current Preview data, or reading the source if Preview was not run.');
                [entry, cacheHit, ~, owner] = NMDataIOImportTools.materializeImageImport(NM, state, opts);
                messages = entry.messages;
                if NMDataIOMessageTools.hasFatal(messages), out=NMDataIOImportTools.finishServiceOut(out,messages); NMProgressTools.finish(progressTask,out.message); return; end
                IO = entry.IO;
                if isfield(IO,'Y') && isnumeric(IO.Y)
                    IO.selCases = NMDataIOMaterializationCache.caseSelection(state, size(IO.Y,1));
                    [IO, selectionMessages] = NMDataIOImageImportTools.applySubjectSelectionToResolvedIO(IO);
                    messages = [messages; selectionMessages];
                end
                importTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, IO.varind);
                [NM, importTarget, targetMessages] = NMDataIOImportTargetTools.ensureContainer(NM, importTarget);
                messages = [messages; targetMessages];
                [targetContainer, containerMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
                messages = [messages; containerMessages];
                if NMDataIOMessageTools.hasFatal(messages), out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; NMProgressTools.finish(progressTask,out.message); return; end
                progressTask = NMProgressTools.phase(progressTask, 'image_commit_transfer', 65, 94, 'Adding the prepared imaging data to NM2.');
                varind = IO.varind; oldCases = NMDataIOImportTools.containerCases(targetContainer);
                replacesExisting = NMDataIOImportTargetTools.hasTargetModality(NM, importTarget, varind) || ...
                    any(strcmpi(char(string(importTarget.mode)), {'replace','resume','modify','overwrite'}));
                transferIO = IO;
                if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'spaceDefType','')), 'atlas') && strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasImportMode','')), 'collapse')
                    transferIO.atlasCollapseOriginalDatasource = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'datasource','nifti'));
                    transferIO.datasource = 'matrix'; transferIO.groupmode = 1;
                end
                [transferIO, covMessages] = NMDataIOImportTools.canonicalizeCovariateTransfer(targetContainer, transferIO, '?'); messages=[messages;covMessages];
                if NMDataIOMessageTools.hasFatal(messages), out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
                transferContainer = NMDataIOImportTools.prepareReplacementTransferContainer(targetContainer, transferIO, importTarget, replacesExisting);
                [targetContainer2, inputSettings] = TransferModality2NM(transferContainer, transferIO, varind);
                [targetContainer2,m1]=NMDataIOImageImportTools.postprocessAtlasCollapseTransfer(targetContainer2,IO,varind);
                [targetContainer2,m2]=NMDataIOImageImportTools.postprocessAtlasSplitTransfer(targetContainer2,IO,varind);
                [targetContainer2,m3]=NMDataIOImageImportTools.postprocessSurfaceRoiTransfer(targetContainer2,IO,varind); messages=[messages;m1;m2;m3];
                [targetContainer2, canonicalLabelMessages] = NMDataIOImportTools.restoreTransferredOOCVClassificationLabels( ...
                    targetContainer2, transferIO, importTarget);
                messages = [messages; canonicalLabelMessages];
                if NMDataIOMessageTools.hasFatal(messages), out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
                targetContainer2 = NMDataIOImportTools.applyRegressionLabelNames(targetContainer2, IO);
                if NMDataIOImportTargetTools.isOOCV(importTarget) && isfield(targetContainer2,'cases'), targetContainer2.n_subjects_all=numel(targetContainer2.cases); end
                targetContainer2 = NMDataIOImportTools.persistInputSettings(targetContainer2, IO, inputSettings, varind);
                [targetContainer2,m4]=NMDataIOImportTools.preserveExistingLabelsIfSkipped(targetContainer,targetContainer2,IO,'?');
                [targetContainer2,m5]=NMDataIOImportTools.preserveExistingCovariatesIfSkipped(targetContainer,targetContainer2,IO,'?'); messages=[messages;m4;m5];
                if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'spaceDefType','')), 'atlas') && strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasImportMode','')), 'split') && iscell(IO.Y) && isfield(targetContainer2,'datadescriptor')
                    for sv=2:numel(IO.Y), vv=varind+sv-1; if numel(targetContainer2.datadescriptor)>=vv && isstruct(targetContainer2.datadescriptor{vv}), targetContainer2=NMDataIOImportTools.persistInputSettings(targetContainer2,IO,inputSettings,vv); end; end
                end
                [targetContainer2,m6]=NMDataIOImportTools.resetDependentModalitiesIfCaseListChanged(targetContainer2, varind, oldCases, importTarget, replacesExisting); messages=[messages;m6;NMDataIOImportTools.validateTransferredImagingContainer(targetContainer2,varind,importTarget)];
                if NMDataIOMessageTools.hasFatal(messages) || ~isfield(targetContainer2,'Y') || numel(targetContainer2.Y)<varind || isempty(targetContainer2.Y{varind})
                    if ~NMDataIOMessageTools.hasFatal(messages), messages=[messages;NMDataIOMessageTools.make('danger',true,'TransferModality2NM','Transfer did not create the requested imaging modality.',1,'red*')]; end
                    out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return;
                end
                if replacesExisting
                    [targetContainer2, storageMessages] = NMDataIOExternalStorageTools.finalizeReplacementStorage( ...
                        targetContainer, targetContainer2, varind);
                    messages = [messages; storageMessages];
                    if NMDataIOMessageTools.hasFatal(messages), out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
                end
                NM2=NMDataIOImportTargetTools.setContainer(NM,importTarget,targetContainer2);
                if replacesExisting, txt=sprintf('Imaging import replaced %s.',NMDataIOImportTargetTools.targetLabel(importTarget)); else, txt=sprintf('Imaging modality imported successfully as %s.',NMDataIOImportTargetTools.targetLabel(importTarget)); end
                messages=[messages;NMDataIOMessageTools.make('ok',false,'commitImageImport',txt,0,'green*')];
                out=NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM2; out.varind=varind; out.importTarget=importTarget;
                out.modalityInfo=nk_GetNMModalityInfo(targetContainer2,varind,struct('ScanInMemory',true,'MaxScanElements',1e7)); out.probe=entry.probe; out.qc=entry.qc; out.cacheHit=cacheHit;
                NMDataIOMaterializationCache.clearFamilyForOwner('image', owner);
                NMProgressTools.finish(progressTask,out.message);
            catch ME
                NMProgressTools.fail(progressTask,'commitImageImport',ME); out=NMDataIOImportTools.finishServiceOut(out,NMDataIOMessageTools.fromException(ME,'commitImageImport')); out.NM=NM;
            end
        end

        function out = commitMatrixImport(NM, state, opts)
            % commitMatrixImport  Commit retained Preview materialization; read sources only when Preview was not performed.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = NMDataIOImportTools.emptyServiceOut('commitMatrixImport');
            out.NM = NM;
            progressTask = NMProgressTools.fromOptions(opts, 'Committing DataIO import', 'Checking the current Preview data.');
            opts.ProgressTask = progressTask;
            try
                NMDataIOImportTools.assertLegacyImportPath();
                progressTask = NMProgressTools.phase(progressTask, 'commit_materialize', 0, 62, 'Reusing the current Preview data, or reading and checking the source if Preview was not run.');
                opts.ProgressTask = progressTask;
                [entry, cacheHit, ~, owner] = NMDataIOImportTools.materializeMatrixImport(NM, state, opts);
                messages = entry.messages;
                out.audit = NMDataIOImportTools.dataIOAuditFromIO(entry.IO);
                if NMDataIOMessageTools.hasFatal(messages)
                    out = NMDataIOImportTools.finishServiceOut(out, messages);
                    NMProgressTools.finish(progressTask, out.message);
                    return;
                end
                IO = entry.IO;
                IO.selCases = NMDataIOMaterializationCache.caseSelection(state, size(IO.Y,1));
                IO.selFeats = NMDataIOMaterializationCache.featureSelection(state, size(IO.Y,2));
                if NMDataIOImportTargetTools.isOOCV(IO.importTarget) && ~all(IO.selFeats)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                        'OOCV/application import cannot use item-selector feature filtering. The source features must map exactly to the trained modality feature space.', 1, 'red*')];
                    out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM = NM; NMProgressTools.finish(progressTask,out.message); return;
                end
                if NMDataIOImportTargetTools.isOOCV(IO.importTarget), IO.selFeats = []; end
                progressTask = NMProgressTools.phase(progressTask, 'commit_transfer', 62, 96, 'Applying the case/feature selection and adding the prepared data to NM2.');
                [out, messages] = NMDataIOImportTools.commitMaterializedMatrixIO(NM, IO, messages);
                out.qc = entry.qc;
                out.audit = NMDataIOImportTools.dataIOAuditFromIO(IO);
                out.cacheHit = cacheHit;
                if out.ok
                    NMDataIOMaterializationCache.clearFamilyForOwner('matrix', owner);
                end
                NMProgressTools.finish(progressTask, out.message);
            catch ME
                NMProgressTools.fail(progressTask, 'NMDataIOImportTools.commitMatrixImport', ME);
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOImportTools.commitMatrixImport');
                out = NMDataIOImportTools.finishServiceOut(out, messages);
                out.NM = NM;
            end
        end

        function [out, messages] = commitMaterializedMatrixIO(NM, IO, messages)
            % commitMaterializedMatrixIO  Transfer a resident canonical IO contract without source resolution.
            if nargin < 3 || isempty(messages), messages = NMDataIOMessageTools.emptyMessages(); end
            out = NMDataIOImportTools.emptyServiceOut('commitMaterializedMatrixIO');
            out.NM = NM;
            importTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, IO.varind);
            [NM, importTarget, targetMessages] = NMDataIOImportTargetTools.ensureContainer(NM, importTarget);
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            [targetContainer, containerMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            messages = [messages; containerMessages];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            % IO is the retained canonical Preview materialization. Scientific preparation
            % has already completed in the family materializer; Commit must consume it directly.
            messages = [messages; NMDataIOImportTools.validateOOCVKnownLabels(IO, NM)];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            varind = IO.varind;
            oldCases = NMDataIOImportTools.containerCases(targetContainer);
            replacesExisting = NMDataIOImportTargetTools.hasTargetModality(NM, importTarget, varind) || ...
                    any(strcmpi(char(string(importTarget.mode)), {'replace','resume','modify','overwrite'}));
            transferIO = IO;
            [transferIO, covMessages] = NMDataIOImportTools.canonicalizeCovariateTransfer(targetContainer, transferIO, '?');
            messages = [messages; covMessages];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end

            % Late case masks do not change retained scientific materialization. At the
            % transfer boundary, however, every case-indexed field must be projected onto
            % the same selected axis before legacy TransferModality2NM sees the payload.
            % Leaving selection to the legacy transfer filters Y/cases/labels but can leave
            % generic auxiliary matrices (notably covariates) on the pre-selection axis.
            if isfield(transferIO,'selCases') && ~isempty(transferIO.selCases) && ~all(transferIO.selCases(:))
                caseMask = logical(transferIO.selCases(:));
                nPrepared = size(transferIO.Y,1);
                if numel(caseMask) ~= nPrepared
                    error('NMDataIOImportTools:lateCaseSelectionLength', ...
                        'The late case selection contains %g entries, but the retained Preview contains %g cases.', ...
                        numel(caseMask),nPrepared);
                end
                caseFields = {'Y','ID','s_ID','label','s_label','L','covars','g'};
                for cf = 1:numel(caseFields)
                    fieldName = caseFields{cf};
                    if ~isfield(transferIO,fieldName) || isempty(transferIO.(fieldName)), continue; end
                    value = transferIO.(fieldName);
                    if isvector(value) && numel(value) == nPrepared
                        if isrow(value), transferIO.(fieldName) = value(caseMask.');
                        else, transferIO.(fieldName) = value(caseMask); end
                    elseif size(value,1) == nPrepared
                        transferIO.(fieldName) = value(caseMask,:);
                    else
                        error('NMDataIOImportTools:lateCaseIndexedFieldRows', ...
                            'Case-indexed field %s contains %g row(s), but the retained Preview contains %g cases.', ...
                            fieldName,size(value,1),nPrepared);
                    end
                end
                nSelected = nnz(caseMask);
                % The original late mask remains in IO/input_settings. The execution payload
                % is now already projected, so legacy transfer must retain every remaining row.
                transferIO.selCases = true(nSelected,1);
                if logical(NMDataIOImportTools.fieldOr(transferIO,'labels_known',true)) && ...
                        strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(transferIO,'modeflag','classification')),'classification')
                    selectedLabels = double(transferIO.label(:));
                    K = numel(NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(transferIO,'desc_groups',{})));
                    finiteLabels = selectedLabels(isfinite(selectedLabels));
                    transferIO.n_subjects = arrayfun(@(classId)nnz(finiteLabels == classId),1:K);
                    transferIO.n_samples = K;
                else
                    transferIO.n_subjects = nSelected;
                    transferIO.n_samples = 1;
                end
                transferIO.n_subjects_all = nSelected;
            end

            transferContainer = NMDataIOImportTools.prepareReplacementTransferContainer(targetContainer, transferIO, importTarget, replacesExisting);
            [targetContainer2, inputSettings] = TransferModality2NM(transferContainer, transferIO, varind);
            [targetContainer2, canonicalLabelMessages] = NMDataIOImportTools.restoreTransferredOOCVClassificationLabels( ...
                targetContainer2, transferIO, importTarget);
            messages = [messages; canonicalLabelMessages];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            targetContainer2 = NMDataIOImportTools.applyRegressionLabelNames(targetContainer2, IO);
            if NMDataIOImportTargetTools.isOOCV(importTarget) && isstruct(targetContainer2) && isfield(targetContainer2,'cases')
                targetContainer2.n_subjects_all = numel(targetContainer2.cases);
            end
            targetContainer2 = NMDataIOImportTools.persistInputSettings(targetContainer2, IO, inputSettings, varind);
            [targetContainer2, labelMessages] = NMDataIOImportTools.preserveExistingLabelsIfSkipped(targetContainer, targetContainer2, IO, '?');
            [targetContainer2, covPreserveMessages] = NMDataIOImportTools.preserveExistingCovariatesIfSkipped(targetContainer, targetContainer2, IO, '?');
            messages = [messages; labelMessages; covPreserveMessages];
            [targetContainer2, resetMessages] = NMDataIOImportTools.resetDependentModalitiesIfCaseListChanged(targetContainer2, varind, oldCases, importTarget, replacesExisting);
            messages = [messages; resetMessages; NMDataIOImportTools.validateTransferredImagingContainer(targetContainer2, varind, importTarget)];
            if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            if ~isstruct(targetContainer2) || ~isfield(targetContainer2,'Y') || numel(targetContainer2.Y) < varind || isempty(targetContainer2.Y{varind})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'TransferModality2NM', ...
                    sprintf('TransferModality2NM returned without creating %s.', NMDataIOImportTargetTools.targetLabel(importTarget)), 1, 'red*')];
                out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return;
            end
            if replacesExisting
                [targetContainer2, storageMessages] = NMDataIOExternalStorageTools.finalizeReplacementStorage( ...
                    targetContainer, targetContainer2, varind);
                messages = [messages; storageMessages];
                if NMDataIOMessageTools.hasFatal(messages), out = NMDataIOImportTools.finishServiceOut(out,messages); out.NM=NM; return; end
            end
            NM2 = NMDataIOImportTargetTools.setContainer(NM, importTarget, targetContainer2);
            if replacesExisting, commitText = sprintf('Matrix/table import replaced %s.', NMDataIOImportTargetTools.targetLabel(importTarget));
            else, commitText = sprintf('Matrix/table modality imported successfully as %s.', NMDataIOImportTargetTools.targetLabel(importTarget)); end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'commitMatrixImport', commitText, 0, 'green*')];
            out = NMDataIOImportTools.finishServiceOut(out,messages);
            out.NM = NM2; out.varind = varind; out.importTarget = importTarget;
            out.modalityInfo = nk_GetNMModalityInfo(targetContainer2, varind, struct('ScanInMemory', true, 'MaxScanElements', 1e7));
            out.probe = NMDataIOProbeTools.matrixSummaryFromIO(IO, struct());
        end

        function [IO, messages] = prepareMatrixIO(NM, state, opts)
            % prepareMatrixIO  Normalize browser/API matrix-import state into a legacy IO contract.
            %
            % [IO, messages] = NMDataIOImportTools.prepareMatrixIO(NM, state, opts)
            % resolves source type, import target, labels, covariates, globals, case IDs,
            % feature names and readiness diagnostics.  It does not commit data to NM.
            %
            % opts.NaString: defines the text token interpreted as missing data during table/matrix import.
            % opts.ProfileLabel: names the profiling segment so nested timing diagnostics can be traced to the caller.
            % opts.RequireReady: requires the prepared import/configuration state to be complete before the method proceeds.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            requireReady = NMDataIOImportTools.opt(opts, 'RequireReady', false);
            na = NMDataIOImportTools.opt(opts, 'NaString', '?');
            doProfile = NMDataIOProfileTools.enabled([], [], opts);
            profileLabel = char(string(NMDataIOImportTools.opt(opts, 'ProfileLabel', 'prepareMatrixIO')));
            tTotal = tic;

            tTarget = tic;
            importTarget = NMDataIOImportTargetTools.normalize(NM, state);
            targetMessages = NMDataIOImportTargetTools.validateForImport(NM, importTarget);
            [NM, importTarget, initMessages] = NMDataIOImportTargetTools.ensureContainer(NM, importTarget);
            targetMessages = [targetMessages; initMessages];
            NMDataIOProfileTools.log(doProfile, '%s target normalize/ensure: %.3fs', profileLabel, toc(tTarget));

            tStateToIO = tic;
            IO = NMDataIOStateTools.stateToIO(state, NM, importTarget.varind);
            NMDataIOProfileTools.log(doProfile, '%s stateToIO: %.3fs', profileLabel, toc(tStateToIO));
            IO.importTarget = importTarget;
            IO.varind = importTarget.varind;
            messages = targetMessages;
            if NMDataIOMessageTools.hasFatal(messages)
                return;
            end
            tContext = tic;
            [IO, contextMessages] = NMDataIOImportTools.applyImportTargetContext(NM, IO, importTarget, na);
            NMDataIOProfileTools.log(doProfile, '%s applyImportTargetContext: %.3fs', profileLabel, toc(tContext));
            messages = [messages; contextMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                return;
            end

            % Establish the source-block case-axis contract before workspace/MAT
            % materialization. Once a training or OOCV container owns cases, that
            % case list is authoritative for every later modality and each incoming
            % source block is projected onto it independently. Only an axis-establishing
            % import may apply the configured first-modality case-axis policy.
            [axisTargetContainer, axisTargetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            messages = [messages; axisTargetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            axisReferenceContainer = NMDataIOImportTools.alignmentReferenceContainer(NM, axisTargetContainer, importTarget);
            if NMDataIOImportTools.hasReferenceCases(axisReferenceContainer)
                IO.sourceBlockReferenceCases = NMDataIOImportTools.asCaseCell(axisReferenceContainer.cases);
                IO.caseAxisEstablishing = false;
                IO.caseAxisPolicy = NMDataIOImportTools.trainingCaseAxisPolicy(NM);
            else
                IO.sourceBlockReferenceCases = {};
                IO.caseAxisEstablishing = true;
                if NMDataIOImportTargetTools.isOOCV(importTarget)
                    IO.caseAxisPolicy = NMDataIOImportTools.trainingCaseAxisPolicy(NM);
                else
                    IO.caseAxisPolicy = NMDataIOImportTools.normalizeCaseAxisPolicy(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case'));
                    % A training import that establishes a new case axis must not
                    % inherit cohort counts from the resident training container.
                    % In particular, first-modality replacement may redefine the
                    % case list; legacy CheckLabel otherwise treats those stale
                    % counts as previous-modality authority before an ID axis exists.
                    staleCaseContext = {'n_subjects','n_subjects_all','n_samples'};
                    for k = 1:numel(staleCaseContext)
                        if isfield(IO,staleCaseContext{k}), IO = rmfield(IO,staleCaseContext{k}); end
                    end
                end
            end

            % Resolved matrix payloads may explicitly carry covars/covnames. For
            % an added modality those values are transferable only when the same
            % incoming state also carries an explicit covariate-assignment contract.
            % stateToIO no longer inherits existing NM covariates; this guard applies
            % only to ambiguous covariates supplied by the incoming resolved payload.
            IO = NMDataIOImportTools.clearInheritedCovariatesWithoutAssignment(IO, NM, na);

            if NMDataIOImportTools.hasVariableRoleMaterialization(IO)
                IO.dataioProgressTask = NMDataIOImportTools.fieldOr(opts,'ProgressTask',NMProgressTools.emptyTaskForLocalUse());
                [IO, variableMessages] = NMDataIOImportTools.materializeVariableRolePayload(IO);
                messages = [messages; variableMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end

            if ~strcmpi(char(IO.datasource), 'matrix')
                messages = NMDataIOMessageTools.make('danger', true, 'prepareMatrixIO', ...
                    sprintf('Only datasource=''matrix'' is supported by the matrix/table importer; received ''%s''.', char(IO.datasource)), 1, 'red*');
                return;
            end

            if NMDataIOImportTools.hasResolvedMatrixPayload(IO)
                [IO, resolvedMessages] = NMDataIOImportTools.prepareResolvedMatrixPayload(IO, NM, importTarget);
                messages = [messages; resolvedMessages];
                NMDataIOProfileTools.log(doProfile, '%s resolved matrix payload: %.3fs', profileLabel, toc(tTotal));
                return;
            end

            if exist('CheckTabFile','file') ~= 2 || exist('CheckReadyStatus','file') ~= 2
                messages = NMDataIOMessageTools.make('danger', true, 'prepareMatrixIO', ...
                    'Legacy DataIO helpers CheckTabFile.m and CheckReadyStatus.m must be on the MATLAB path.', 1, 'red*');
                return;
            end

            if NMDataIOImportTools.isUnknown(IO.desc_data, na)
                if requireReady
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareMatrixIO', ...
                        'Data description is required before committing this matrix/table import.', 1, 'red*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'prepareMatrixIO', ...
                        'Data description is missing. Add a concise modality description before committing the import.', 2, 'orange*')];
                end
            end

            if isfield(IO,'groupmode') && double(IO.groupmode) == 6
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareMatrixIO', ...
                    'Refresh the database tables, then assign the required Case-ID, feature, label and covariate columns before Preview or Commit.', 1, 'red*')];
                return;
            end

            roleManagedTable = NMDataIOImportTools.isRoleManagedTableImport(IO);
            if roleManagedTable
                alignedCacheKey = NMDataIOImportTools.tableAlignedPreparedCacheKey(NM, IO);
                if ~isempty(alignedCacheKey)
                    [alignedCacheHit, alignedCached] = NMDataIOImportTools.tablePreparedCache('get', alignedCacheKey);
                    if alignedCacheHit && isstruct(alignedCached) && isfield(alignedCached,'IO') && isstruct(alignedCached.IO)
                        IO = alignedCached.IO;
                        if isfield(alignedCached,'messages')
                            messages = [messages; alignedCached.messages];
                        end
                        IO.dataioAlignedCacheKey = alignedCacheKey;
                        IO.dataioAlignedCacheHit = true;
                        NMDataIOProfileTools.log(doProfile, '%s aligned prepared table cache hit: %.3fs', profileLabel, toc(tTotal));
                        NMDataIOProfileTools.log(doProfile, '%s TOTAL: %.3fs', profileLabel, toc(tTotal));
                        return;
                    end
                end
                cacheKey = NMDataIOImportTools.tablePreparedCacheKey(IO, [], 'raw');
                if ~isempty(cacheKey)
                    [cacheHit, cached] = NMDataIOImportTools.tablePreparedCache('get', cacheKey);
                    if cacheHit && isstruct(cached) && isfield(cached,'IO') && isstruct(cached.IO)
                        IO = cached.IO;
                        if isfield(cached,'messages')
                            messages = cached.messages;
                        end
                        IO.dataioPreparedCacheKey = cacheKey;
                        IO.dataioPreparedCacheHit = true;
                        NMDataIOProfileTools.log(doProfile, '%s prepared table cache hit: %.3fs', profileLabel, toc(tTotal));
                        NMDataIOProfileTools.log(doProfile, '%s TOTAL: %.3fs', profileLabel, toc(tTotal));
                        return;
                    end
                end
            end

            mess = [];
            try
                tCheckMatrix = tic;
                [~, mess, IO] = CheckTabFile(IO, 'check_matrix', na, mess);
                NMDataIOProfileTools.log(doProfile, '%s CheckTabFile(check_matrix): %.3fs', profileLabel, toc(tCheckMatrix));
                if ~CheckReadyStatus(mess) && ~roleManagedTable
                    labelsRequired = NMDataIOImportTools.labelsRequiredForIO(IO);
                    if labelsRequired && ~NMDataIOImportTools.isUnknown(IO.label_edit, na)
                        tCheckLabel = tic;
                        [~, mess, IO] = CheckTabFile(IO, 'check_label', na, mess);
                        NMDataIOProfileTools.log(doProfile, '%s CheckTabFile(check_label): %.3fs', profileLabel, toc(tCheckLabel));
                    elseif requireReady && labelsRequired && (~isfield(IO,'label') || isempty(IO.label))
                        mess = GenerateMessageEntry(mess, 'ERROR in prepareMatrixIO: Label variable/column is required for the first modality commit.', 1, 'red*');
                    end
                end
                if ~CheckReadyStatus(mess) && ~roleManagedTable
                    if ~NMDataIOImportTools.isUnknown(IO.case_edit, na)
                        tCheckID = tic;
                        [~, mess, IO] = CheckTabFile(IO, 'check_ID', na, mess);
                        NMDataIOProfileTools.log(doProfile, '%s CheckTabFile(check_ID): %.3fs', profileLabel, toc(tCheckID));
                    elseif requireReady
                        mess = GenerateMessageEntry(mess, 'ERROR in prepareMatrixIO: Case-ID variable/column is required for committing this import.', 1, 'red*');
                    end
                end
                if ~CheckReadyStatus(mess) && ismember(IO.groupmode, [1 2])
                    if ~NMDataIOImportTools.isUnknown(IO.col_edit, na)
                        tCheckFeat = tic;
                        [~, mess, IO] = CheckTabFile(IO, 'check_featnames', na, mess);
                        NMDataIOProfileTools.log(doProfile, '%s CheckTabFile(check_featnames): %.3fs', profileLabel, toc(tCheckFeat));
                    end
                end
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'prepareMatrixIO.CheckTabFile');
                return;
            end
            tLegacyMsg = tic;
            legacyMessages = NMDataIOMessageTools.fromLegacyMess(mess, 'CheckTabFile');
            messages = [messages; legacyMessages];
            NMDataIOProfileTools.log(doProfile, '%s legacy message conversion: %.3fs', profileLabel, toc(tLegacyMsg));
            if roleManagedTable && ~NMDataIOMessageTools.hasFatal(messages)
                cacheKey = NMDataIOImportTools.tablePreparedCacheKey(IO, [], 'raw');
                if ~isempty(cacheKey)
                    IO.dataioPreparedCacheKey = cacheKey;
                    IO.dataioPreparedCacheHit = false;
                    NMDataIOImportTools.tablePreparedCache('set', cacheKey, struct('IO', IO, 'messages', messages, 'createdAt', datestr(now,30), 'stage', 'validated'));
                end
            end
            NMDataIOProfileTools.log(doProfile, '%s TOTAL: %.3fs', profileLabel, toc(tTotal));
        end

        function [IO, messages] = applyImportTargetContext(NM, IO, importTarget, na)
            % APPLYIMPORTTARGETCONTEXT  Attach target-container context to an import IO struct.
            %
            %   [IO, messages] = ... normalizes the requested import target, sets varind,
            %   and configures OOCV/application flags and inherited training semantics.
            %   It preserves existing diagnostics through NMDataIOMessageTools.
            if nargin < 4 || isempty(na), na = '?'; end
            messages = NMDataIOMessageTools.emptyMessages();
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
            IO.importTarget = importTarget;
            IO.varind = importTarget.varind;
            if ~NMDataIOImportTargetTools.isOOCV(importTarget)
                IO.oocvflag = false;
                return;
            end

            IO.oocvflag = true;
            IO.labels_known = logical(importTarget.labels_known);
            if isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                IO.modeflag = NM.modeflag;
            end

            resolvedTargetPayload = NMDataIOImportTools.hasResolvedMatrixPayload(IO);
            if strcmpi(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'),'classification') && IO.labels_known
                IO.trainingClassificationLabelMap = NMDataIOImportTools.trainingClassificationLabelMap(NM);
            end
            if isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                IO.desc_groups = NM.groupnames;
            end
            if strcmpi(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'), 'classification') && IO.labels_known && ...
                    (~isfield(IO,'desc_groups') || isempty(IO.desc_groups) || NMDataIOImportTools.isUnknown(IO.desc_groups, na))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                    'OOCV classification labels are marked as known, but the training class/group names are unavailable for label mapping.', 1, 'red*')];
                return;
            end

            if ismember(double(NMDataIOImportTools.fieldOr(IO,'groupmode',1)), [1 2 3 4 5 6])
                trainFeatures = NMDataIOImportTools.trainingFeatureNames(NM, importTarget.varind);
                if isempty(trainFeatures)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                        sprintf('OOCV modality %g cannot be imported because the matching training modality has no feature-name vector for exact feature-space mapping.', double(importTarget.varind)), 1, 'red*')];
                    return;
                end
                IO.featnames_cv = trainFeatures;
            end

            [D, dMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            messages = [messages; dMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                return;
            end

            hasExistingTargetCases = NMDataIOImportTools.hasReferenceCases(D);
            if hasExistingTargetCases
                IO.ID = D.cases;
                if isfield(D,'label') && ~isempty(D.label) && (~isfield(IO,'oocvflag') || ~IO.oocvflag || IO.labels_known)
                    IO.label = D.label;
                elseif isfield(IO,'label')
                    IO = rmfield(IO,'label');
                end
                if isfield(D,'n_subjects'), IO.n_subjects = D.n_subjects; end
                if isfield(D,'n_subjects_all'), IO.n_subjects_all = D.n_subjects_all; end
            else
                % Unresolved states must not carry stale/direct case or label fields into
                % first-modality OOCV source resolution. A resolved resident payload, however,
                % already owns its OOCV case axis and known-label vector; removing those fields
                % here would turn a valid first-modality import into a false "labels required" diagnostic.
                if resolvedTargetPayload
                    inherited = {'n_subjects','n_subjects_all','n_samples','survanal_time'};
                else
                    inherited = {'ID','label','L','s_label','n_subjects','n_subjects_all','n_samples','survanal_time'};
                end
                for k = 1:numel(inherited)
                    if isfield(IO, inherited{k})
                        IO = rmfield(IO, inherited{k});
                    end
                end
            end

            if ~IO.labels_known
                IO.label_edit = na;
                removeFields = {'label','L','s_label','desc_labels'};
                for k = 1:numel(removeFields)
                    if isfield(IO, removeFields{k})
                        IO = rmfield(IO, removeFields{k});
                    end
                end
                IO.n_subjects = Inf;
                IO.n_subjects_all = Inf;
                IO.n_samples = 1;
            end

            if hasExistingTargetCases
                IO.label_edit = na;
                IO.covar_edit = {};
                IO.covnames_edit = na;
                if isfield(IO,'s_label'), IO = rmfield(IO,'s_label'); end
                if isfield(IO,'L'), IO = rmfield(IO,'L'); end
                if isfield(IO,'covars'), IO = rmfield(IO,'covars'); end
                if isfield(IO,'covnames'), IO = rmfield(IO,'covnames'); end
            end

            if isfield(IO,'selFeats') && ~isempty(IO.selFeats)
                selFeats = logical(IO.selFeats(:));
                if ~all(selFeats)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                        'OOCV/application import cannot use item-selector feature filtering. The source features must map exactly to the trained modality feature space.', 1, 'red*')];
                    return;
                end
                IO.selFeats = [];
            end
        end

        function features = trainingFeatureNames(NM, varind)
            % TRAININGFEATURENAMES  Return feature names for an existing training modality.
            %
            %   features = NMDataIOImportTools.trainingFeatureNames(NM, varind) reads
            %   NM.featnames{varind}, normalizes supported text containers to a row cell
            %   array, and returns {} when no names are available.
            features = {};
            if ~isstruct(NM) || ~isfield(NM,'featnames') || numel(NM.featnames) < varind || isempty(NM.featnames{varind})
                return;
            end
            f = NM.featnames{varind};
            if isstring(f)
                features = cellstr(f(:)');
            elseif ischar(f)
                features = cellstr(f);
                features = features(:)';
            elseif iscell(f)
                features = cell(size(f));
                for i = 1:numel(f)
                    features{i} = char(string(f{i}));
                end
                features = features(:)';
            end
        end

        function D = alignmentReferenceContainer(NM, targetContainer, importTarget)
            % ALIGNMENTREFERENCECONTAINER  Select the case-list container used for row alignment.
            %
            %   D = NMDataIOImportTools.alignmentReferenceContainer(NM, targetContainer, importTarget)
            %   returns the correct reference for OOCV, first-modality replacement, and
            %   additional training-modality imports without redefining NM semantics.
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget);
            if NMDataIOImportTargetTools.isOOCV(importTarget)
                D = targetContainer;
                return;
            end

            % Replacing/resuming the first training modality is allowed to
            % redefine the training case list.  Do not use the old NM.cases as
            % a reference in this specific branch; otherwise the commit path
            % incorrectly treats first-modality replacement as an add-modality
            % alignment problem.  Added modalities and replacement of later
            % modalities must still align to NM.cases.
            if importTarget.varind == 1 && any(strcmpi(char(string(importTarget.mode)), {'replace','resume','modify','overwrite'}))
                D = struct();
            else
                D = NM;
            end
        end

        function D = prepareReplacementTransferContainer(D, IO, importTarget, replacesExisting)
            % PREPAREREPLACEMENTTRANSFERCONTAINER  Present the resolved first-modality case axis to the legacy transfer boundary.
            %
            % TransferModality2NM predates the explicit DataIO replace target. When training
            % modality 1 is intentionally replaced with a different case axis, its legacy
            % case-reconciliation branch otherwise treats the incoming axis like an added
            % modality and opens an interactive old/new Case-ID prompt. DataIO has already
            % resolved the replacement axis before this boundary, so seed that axis into the
            % transfer copy only. The original container remains authoritative for post-transfer
            % change detection, preservation rules and dependent-modality reset.
            if nargin < 4 || ~isstruct(D) || ~isstruct(IO)
                return;
            end
            importTarget = NMDataIOImportTargetTools.normalize(struct(), importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
            mode = lower(char(string(NMDataIOImportTools.fieldOr(importTarget,'mode','add'))));
            if NMDataIOImportTargetTools.isOOCV(importTarget) || importTarget.varind ~= 1 || ...
                    ~any(strcmp(mode, {'replace','resume','modify','overwrite'}))
                return;
            end
            ids = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'ID',{}));
            if isempty(ids)
                ids = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'s_ID',{}));
            end
            if isempty(ids), return; end
            % Explicit replace/resume intent is authoritative at this boundary.  The
            % legacy transfer routine predates that target model and carries add-style
            % semantics for global labels/covariates.  Remove the old case-indexed
            % auxiliary state from the transfer copy so incoming data can establish the
            % new first-modality axis.  The untouched original container is still passed
            % to the post-transfer preservation rules, which restore skipped labels or
            % covariates only when their old axis remains compatible.
            staleFields = {'label','s_label','L','covars','covnames','groupnames','labelnames'};
            for staleIndex = 1:numel(staleFields)
                staleField = staleFields{staleIndex};
                if isfield(D, staleField), D = rmfield(D, staleField); end
            end
            D.cases = ids(:);
            if isfield(IO,'n_subjects') && ~isempty(IO.n_subjects), D.n_subjects = IO.n_subjects; end
            if isfield(IO,'n_subjects_all') && ~isempty(IO.n_subjects_all), D.n_subjects_all = IO.n_subjects_all; else, D.n_subjects_all = numel(ids); end
            if isfield(IO,'n_samples') && ~isempty(IO.n_samples), D.n_samples = IO.n_samples; end
        end

        function [D, messages] = restoreTransferredOOCVClassificationLabels(D, IO, importTarget)
            % RESTORETRANSFERREDOOCVCLASSIFICATIONLABELS  Preserve the training-owned class axis across the legacy transfer boundary.
            %
            % TransferModality2NM predates the persisted DataIO class-map contract and may
            % rebuild classification labels from local transfer bookkeeping. For labelled OOCV
            % imports, the canonical source Case-ID -> training-class association resolved before
            % transfer is authoritative. Reconcile that vector to the committed case order using
            % the existing exact Case-ID matcher, then restore labels/counts without local recoding.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(D) || ~isstruct(IO) || ...
                    ~NMDataIOImportTargetTools.isOOCV(importTarget) || ...
                    ~logical(NMDataIOImportTools.fieldOr(IO,'labels_known',false)) || ...
                    ~strcmpi(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'),'classification')
                return;
            end
            classMap = NMDataIOLabelStatsTools.normalizeClassificationMap( ...
                NMDataIOImportTools.fieldOr(IO,'classificationLabelMap',struct()));
            if isempty(fieldnames(classMap))
                messages = NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap.transfer', ...
                    'OOCV labels cannot be imported because the training class definition is missing or invalid. Check the training labels before importing this OOCV dataset.', 1, 'red*');
                return;
            end
            canonicalLabels = [];
            for labelField = {'label','s_label','L'}
                name = labelField{1};
                if isfield(IO,name) && ~isempty(IO.(name)), rawCanonicalLabels = IO.(name); canonicalLabels = double(rawCanonicalLabels(:)); break; end
            end
            sourceCases = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'ID',{}));
            if isempty(sourceCases), sourceCases = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'s_ID',{})); end
            targetCases = NMDataIOImportTools.containerCases(D);
            if isempty(canonicalLabels) || isempty(sourceCases) || isempty(targetCases) || numel(canonicalLabels) ~= numel(sourceCases)
                messages = NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap.transfer', ...
                    'OOCV labels cannot be matched because the Case IDs and labels are incomplete or have different lengths.', 1, 'red*');
                return;
            end
            opts = struct('idMappingMode','direct','mappingApproved',false);
            [matched, loc] = NMDataIOImportTools.resolveCaseRowMap(targetCases, sourceCases, opts);
            if ~all(matched) || numel(unique(loc(matched))) ~= numel(targetCases)
                messages = NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap.transfer', ...
                    'The OOCV cases cannot be matched one-to-one to the OOCV labels by Case ID. Check the Case-ID variables and duplicate/missing IDs.', 1, 'red*');
                return;
            end
            canonicalLabels = canonicalLabels(loc(:));
            finiteLabels = canonicalLabels(isfinite(canonicalLabels));
            K = numel(classMap.canonicalIds);
            if any(finiteLabels ~= round(finiteLabels)) || any(finiteLabels < 1) || any(finiteLabels > K)
                messages = NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap.transfer', ...
                    'OOCV labels contain class values that are not defined by the training labels after Case-ID matching.', 1, 'red*');
                return;
            end
            changed = isfield(D,'label') && ~isempty(D.label) && ~isequaln(double(D.label(:)), canonicalLabels);
            D.label = canonicalLabels;
            if isfield(D,'s_label'), D.s_label = canonicalLabels; end
            if isfield(D,'L'), D.L = canonicalLabels; end
            counts = zeros(1,K);
            for classId = 1:K, counts(classId) = nnz(canonicalLabels == classId); end
            D.n_subjects = double(counts);
            D.n_samples = double(K);
            D.n_subjects_all = numel(targetCases);
            if changed
                messages = [messages; NMDataIOMessageTools.make('info', false, 'OOCVLabelMap.transfer', ...
                    'Matched OOCV class labels to the training class mapping using exact Case IDs.', 0, 'blue')];
            end
        end

        function classMap = trainingClassificationLabelMap(trainingNM)
            % TRAININGCLASSIFICATIONLABELMAP  Resolve the persisted training source->class map.
            %
            % New DataIO imports persist the exact source-label mapping in modality input_settings.
            % Labelled OOCV import requires that persisted raw-source mapping; no class axis is inferred.
            classMap = struct();
            if ~isstruct(trainingNM), return; end
            if isfield(trainingNM,'datadescriptor') && iscell(trainingNM.datadescriptor)
                for i = 1:numel(trainingNM.datadescriptor)
                    dd = trainingNM.datadescriptor{i};
                    if ~isstruct(dd) || ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings) || ...
                            ~isfield(dd.input_settings,'classificationLabelMap')
                        continue;
                    end
                    candidate = NMDataIOLabelStatsTools.normalizeClassificationMap(dd.input_settings.classificationLabelMap);
                    if ~isempty(fieldnames(candidate))
                        classMap = candidate;
                        return;
                    end
                end
            end
        end

        function classMap = classificationLabelMapFromDefinition(IO, groupNames)
            % CLASSIFICATIONLABELMAPFROMDEFINITION  Resolve an explicit numeric source-code axis.
            classMap = struct();
            def = NMDataIOImportTools.fieldOr(IO,'labelDefinition',struct());
            if ~isstruct(def) || ~isfield(def,'sourceCodes') || isempty(def.sourceCodes), return; end
            codes = NMDataIOImportTools.asCaseCell(def.sourceCodes);
            if isempty(codes) || numel(codes) ~= numel(groupNames), return; end
            numericCodes = cellfun(@str2double,codes);
            if all(isfinite(numericCodes))
                classMap = NMDataIOLabelStatsTools.makeClassificationMap('numeric',numericCodes,groupNames);
            else
                classMap = NMDataIOLabelStatsTools.makeClassificationMap('text',codes,groupNames);
            end
        end

        function messages = validateOOCVKnownLabels(IO, trainingNM)
            % VALIDATEOOCVKNOWNLABELS  Check known-label OOCV imports against training task constraints.
            %
            %   messages = ... validates supplied OOCV labels for classification or regression
            %   using the training NM context.  It returns blocking diagnostics on label/task
            %   incompatibilities and performs no transfer itself.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 2 || isempty(trainingNM), trainingNM = struct(); end
            if ~isstruct(IO) || ~isfield(IO,'oocvflag') || ~IO.oocvflag || ...
                    ~isfield(IO,'labels_known') || ~IO.labels_known
                return;
            end

            modeflag = NMDataIOImportTools.fieldOr(IO,'modeflag','classification');
            modeflag = lower(strtrim(char(string(modeflag))));

            labelValue = [];
            labelIsNumeric = false;
            if isfield(IO,'label') && ~isempty(IO.label)
                labelValue = IO.label;
                labelIsNumeric = isnumeric(labelValue) || islogical(labelValue);
            elseif isfield(IO,'s_label') && ~isempty(IO.s_label)
                labelValue = IO.s_label;
                labelIsNumeric = isnumeric(labelValue) || islogical(labelValue);
            end

            if isempty(labelValue)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                    'OOCV labels_known=true, but no OOCV labels were supplied. Supply labels or set labelsKnown=false.', 1, 'red*')];
                return;
            end

            nLabelRows = size(labelValue,1);
            if isvector(labelValue), nLabelRows = numel(labelValue); end
            nCases = 0;
            if isfield(IO,'ID') && ~isempty(IO.ID)
                nCases = numel(IO.ID);
            elseif isfield(IO,'Y') && ~isempty(IO.Y)
                if iscell(IO.Y) && ~isempty(IO.Y) && ~isempty(IO.Y{1})
                    nCases = size(IO.Y{1},1);
                elseif isnumeric(IO.Y) || islogical(IO.Y)
                    nCases = size(IO.Y,1);
                end
            end
            if nCases > 0 && nLabelRows ~= nCases
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                    sprintf('OOCV labels have %g row(s), but the OOCV feature/case matrix has %g case(s).', double(nLabelRows), double(nCases)), 1, 'red*')];
                return;
            end

            if strcmp(modeflag, 'regression')
                if ~(isnumeric(labelValue) || islogical(labelValue))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                        'Regression OOCV labels must be numeric.', 1, 'red*')];
                    return;
                end
                lbl = double(labelValue(:));
                if any(~isfinite(lbl))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                        'Regression OOCV labels contain non-finite values.', 1, 'red*')];
                end
                return;
            end

            if labelIsNumeric
                lbl = double(labelValue(:));
                lbl = lbl(isfinite(lbl));
                trained = [];
                if isstruct(trainingNM) && isfield(trainingNM,'label') && ~isempty(trainingNM.label) && ...
                        (isnumeric(trainingNM.label) || islogical(trainingNM.label))
                    trained = unique(double(trainingNM.label(:)))';
                    trained = trained(isfinite(trained));
                end
                if isempty(trained)
                    groupNames = {};
                    if isstruct(trainingNM) && isfield(trainingNM,'groupnames') && ~isempty(trainingNM.groupnames)
                        groupNames = NMDataIOImportTools.asCaseCell(trainingNM.groupnames);
                    elseif isfield(IO,'desc_groups') && ~isempty(IO.desc_groups)
                        groupNames = NMDataIOImportTools.asCaseCell(IO.desc_groups);
                    end
                    if ~isempty(groupNames)
                        trained = 1:numel(groupNames);
                    end
                end
                if ~isempty(trained)
                    unknown = setdiff(unique(lbl(:))', trained(:)', 'stable');
                    if ~isempty(unknown)
                        txt = sprintf('%g, ', unknown(1:min(numel(unknown),8)));
                        txt = regexprep(txt, ', $', '');
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                            sprintf('OOCV numeric class labels contain value(s) outside the trained label domain: %s.', txt), 1, 'red*')];
                    end
                end
                return;
            end

            if ~isfield(IO,'s_label') || isempty(IO.s_label)
                labels = NMDataIOImportTools.asCaseCell(labelValue);
            else
                labels = NMDataIOImportTools.asCaseCell(IO.s_label);
            end
            groups = {};
            if isstruct(trainingNM) && isfield(trainingNM,'groupnames') && ~isempty(trainingNM.groupnames)
                groups = NMDataIOImportTools.asCaseCell(trainingNM.groupnames);
            elseif isfield(IO,'desc_groups') && ~isempty(IO.desc_groups)
                groups = NMDataIOImportTools.asCaseCell(IO.desc_groups);
            end
            if isempty(groups), return; end
            labels = labels(~cellfun(@isempty, labels));
            unknown = setdiff(unique(labels(:)', 'stable'), groups(:)', 'stable');
            if ~isempty(unknown)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVLabelMap', ...
                    sprintf('OOCV labels contain unknown class value(s) not present in the training labels: %s.', NMDataIOImportTools.joinCases(unknown, 8)), 1, 'red*')];
            end
        end

        function D = persistInputSettings(D, IO, inputSettings, varind)
            % PERSISTINPUTSETTINGS  Store lightweight restorable import metadata in a datadescriptor.
            %
            %   D = NMDataIOImportTools.persistInputSettings(D, IO, inputSettings, varind)
            %   enriches and strips input settings, preserves existing preview/QC metadata,
            %   and writes the result to D.datadescriptor{varind}.input_settings.
            inputSettings = NMDataIOImportTools.enrichInputSettingsFromIO(inputSettings, IO);
            if isstruct(D) && isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind
                existingPreview = struct();
                haveExistingPreview = isfield(D.datadescriptor{varind}, 'input_settings') && isstruct(D.datadescriptor{varind}.input_settings) && ...
                    isfield(D.datadescriptor{varind}.input_settings, 'preview') && isstruct(D.datadescriptor{varind}.input_settings.preview);
                if haveExistingPreview
                    existingPreview = D.datadescriptor{varind}.input_settings.preview;
                end
                % Enrichment writes the restorable contract for prepared IO.
                D.datadescriptor{varind}.input_settings = inputSettings;
                if isstruct(inputSettings) && isfield(inputSettings, 'importReport')
                    D.datadescriptor{varind}.input_settings.importReport = inputSettings.importReport;
                elseif isfield(IO,'importReport')
                    D.datadescriptor{varind}.input_settings.importReport = IO.importReport;
                end
                if isfield(D.datadescriptor{varind}, 'input_settings') && isstruct(D.datadescriptor{varind}.input_settings)
                    D.datadescriptor{varind}.input_settings = NMDataIOImportTools.annotateInputSettingsForImportReport(D.datadescriptor{varind}.input_settings, IO);
                    if ~isfield(D.datadescriptor{varind}.input_settings, 'preview') && haveExistingPreview
                        D.datadescriptor{varind}.input_settings.preview = existingPreview;
                    end
                end
                if isfield(D.datadescriptor{varind}, 'input_settings') && isstruct(D.datadescriptor{varind}.input_settings) && ...
                        isfield(IO,'importTarget') && isstruct(IO.importTarget)
                    D.datadescriptor{varind}.input_settings.importTarget = NMDataIOImportTargetTools.normalize(struct(), IO.importTarget, varind);
                end
                sourceType = lower(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType','')));
                sourceFamily = lower(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceFamily','')));
                isDirectROI = strcmp(sourceType,'roi') || strcmp(sourceFamily,'roi');
                if isDirectROI && isfield(IO,'roiProvenance') && isstruct(IO.roiProvenance)
                    D.datadescriptor{varind}.type = 0;
                    D.datadescriptor{varind}.source = 'roi';
                    D.datadescriptor{varind}.roiProvenance = IO.roiProvenance;
                    if isfield(IO,'globalVolumeCorrection') && isstruct(IO.globalVolumeCorrection)
                        D.datadescriptor{varind}.globalVolumeCorrection = IO.globalVolumeCorrection;
                    end
                    if isfield(IO,'Yw') && ~isempty(IO.Yw)
                        if isfield(D,'Y') && numel(D.Y) >= varind && ~isempty(D.Y{varind}) && size(IO.Yw,2) ~= size(D.Y{varind},2)
                            error('NMDataIOImportTools:roiWeightingFeatureMismatch', ...
                                'ROI weighting transfer failed: Yw has %g ROI column(s), but Y{%g} has %g feature(s).', ...
                                size(IO.Yw,2), double(varind), size(D.Y{varind},2));
                        end
                        D.datadescriptor{varind}.Yw = IO.Yw;
                        if isfield(IO,'roiWeightingProvenance') && isstruct(IO.roiWeightingProvenance)
                            D.datadescriptor{varind}.roiWeightingProvenance = IO.roiWeightingProvenance;
                        end
                        D.datadescriptor{varind}.roiProvenance.hasWeightingMaps = true;
                    else
                        D.datadescriptor{varind}.roiProvenance.hasWeightingMaps = false;
                    end
                    D.datadescriptor{varind}.input_settings.roiProvenance = D.datadescriptor{varind}.roiProvenance;
                    if (~isfield(D.datadescriptor{varind},'desc') || isempty(D.datadescriptor{varind}.desc)) && ...
                            isfield(IO,'desc_data') && ~isempty(IO.desc_data)
                        D.datadescriptor{varind}.desc = IO.desc_data;
                    end
                end
                if isfield(IO,'connectivityProvenance') && isstruct(IO.connectivityProvenance)
                    D.datadescriptor{varind}.type = 0;
                    D.datadescriptor{varind}.source = 'connectivity';
                    D.datadescriptor{varind}.connectivity = IO.connectivityProvenance;
                    if isfield(IO,'Yw') && ~isempty(IO.Yw)
                        if isfield(D,'Y') && numel(D.Y) >= varind && ~isempty(D.Y{varind}) && size(IO.Yw,2) ~= size(D.Y{varind},2)
                            error('NMDataIOImportTools:connectivityWeightingFeatureMismatch', ...
                                'Connectivity weighting transfer failed: Yw has %g edge column(s), but Y{%g} has %g feature(s).', ...
                                size(IO.Yw,2), double(varind), size(D.Y{varind},2));
                        end
                        D.datadescriptor{varind}.Yw = IO.Yw;
                    end
                    if (~isfield(D.datadescriptor{varind},'desc') || isempty(D.datadescriptor{varind}.desc)) && ...
                            isfield(IO,'desc_data') && ~isempty(IO.desc_data)
                        D.datadescriptor{varind}.desc = IO.desc_data;
                    end
                end
            end
        end


        function S = stripHeavyConnectivitySpec(S)
            % stripHeavyConnectivitySpec  Remove in-memory connectivity payloads while retaining restorable references.
            if nargin < 1 || ~isstruct(S), return; end
            heavyFields = {'data','Y','connectivityArray','matrixArray','edgeMatrix','vectorizedData','table','t_Y', ...
                'weightingMatrices','weightingMaps','weightingData','Yw'};
            for hf = 1:numel(heavyFields)
                f = heavyFields{hf};
                if ~isfield(S,f), continue; end
                v = S.(f);
                if ischar(v) || (isstring(v) && isscalar(v))
                    if strlength(string(v)) == 0 || strcmp(strtrim(char(string(v))),'?')
                        S = rmfield(S,f);
                    end
                    continue;
                end
                S = rmfield(S,f);
            end
        end

        function S = stripHeavyInputSettings(S)
            % STRIPHEAVYINPUTSETTINGS  Remove bulky payload fields from persisted input settings.
            %
            %   S = NMDataIOImportTools.stripHeavyInputSettings(S) deletes raw data, file/header
            %   arrays and transient cache fields while retaining lightweight provenance needed
            %   for later browser rehydration.
            if nargin < 1 || ~isstruct(S), return; end
            if isfield(S,'connectivitySpec') && isstruct(S.connectivitySpec)
                S.connectivitySpec = NMDataIOImportTools.stripHeavyConnectivitySpec(S.connectivitySpec);
            end
            % Keep lightweight space-definition headers (Vm) when present;
            % OOCV/application imports may need the training-space geometry.
            % Strip volume arrays and subject image/header payloads from
            % restorable input_settings to avoid browser/session bloat.
            heavyFields = {'Y','t_Y','s_label','s_ID','s_featnames','label','covars','covnames','P','PP','V','VV','Vmvol','Yw', ...
                'databasePassword','password','passwd', ...
                'dataioPreparedCacheKey','dataioPreparedCacheHit','dataioAlignedCacheKey','dataioAlignedCacheHit'};
            for k = 1:numel(heavyFields)
                if isfield(S, heavyFields{k})
                    S = rmfield(S, heavyFields{k});
                end
            end
        end

        function inputSettings = enrichInputSettingsFromIO(inputSettings, IO)
            % ENRICHINPUTSETTINGSFROMIO  Add import-source provenance from IO to input settings.
            %
            %   inputSettings = ... records datasource, source type, modality metadata, role
            %   assignments and selected imaging/table options.  It is metadata-only and does
            %   not read or transfer payload data.
            if nargin < 1 || ~isstruct(inputSettings), inputSettings = struct(); end
            inputSettings = NMDataIOImportTools.stripHeavyInputSettings(inputSettings);
            if nargin < 2 || ~isstruct(IO), return; end

            isImage = NMDataIOImportTools.isImagingIO(IO);
            if isImage
                inputSettings.datasource = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'datasource','nifti'));
                if strcmpi(inputSettings.datasource,'image'), inputSettings.datasource = 'nifti'; end
                if strcmpi(inputSettings.datasource,'surf')
                    inputSettings.sourceType = 'surface-list';
                else
                    inputSettings.sourceType = 'image-list';
                end
                inputSettings.groupmode = -2;
            else
                inputSettings.datasource = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'datasource','matrix'));
                inputSettings.sourceType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType',''));
                inputSettings.groupmode = NMDataIOImportTools.fieldOr(IO,'groupmode',1);
                if isempty(inputSettings.sourceType) || strcmp(inputSettings.sourceType,'?')
                    inputSettings.sourceType = NMDataIOStateTools.normalizeSourceType('', inputSettings.groupmode);
                end
            end
            inputSettings.varind = NMDataIOImportTools.fieldOr(IO,'varind',[]);
            inputSettings.modeflag = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'));
            inputSettings.labels_known = logical(NMDataIOImportTools.fieldOr(IO,'labels_known',true));
            inputSettings.oocvflag = logical(NMDataIOImportTools.fieldOr(IO,'oocvflag',false));
            if isfield(IO,'classificationLabelMap') && isstruct(IO.classificationLabelMap)
                inputSettings.classificationLabelMap = IO.classificationLabelMap;
            end
            inputSettings.desc_data = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'desc_data','?'));
            inputSettings.desc_groups = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_groups',{}));
            if isfield(IO,'caseAlignment') && isstruct(IO.caseAlignment), inputSettings.caseAlignment = IO.caseAlignment; end
            if isfield(IO,'importTarget') && isstruct(IO.importTarget), inputSettings.importTarget = IO.importTarget; end

            isConnectivity = strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType','')),'connectivity') || ...
                strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceFamily','')),'connectivity') || ...
                isfield(IO,'connectivityProvenance') || isfield(IO,'connectivitySpec');
            if isConnectivity
                inputSettings.sourceFamily = 'connectivity';
                inputSettings.sourceType = 'connectivity';
                inputSettings.datasource = 'matrix';
                inputSettings.groupmode = 1;
                spec = NMDataIOImportTools.fieldOr(IO,'connectivitySpec',struct());
                if ~isstruct(spec), spec = struct(); end
                if isempty(fieldnames(spec)) && isfield(IO,'input_settings') && isstruct(IO.input_settings) && ...
                        isfield(IO.input_settings,'connectivitySpec') && isstruct(IO.input_settings.connectivitySpec)
                    spec = IO.input_settings.connectivitySpec;
                end
                inputSettings.connectivitySpec = NMDataIOImportTools.stripHeavyConnectivitySpec(spec);
                if isfield(IO,'connectivityProvenance') && isstruct(IO.connectivityProvenance)
                    inputSettings.connectivityProvenance = IO.connectivityProvenance;
                end
                if isfield(IO,'importReport') && isstruct(IO.importReport)
                    inputSettings.importReport = IO.importReport;
                end
                return;
            end

            if ~isImage
                inputSettings.M_edit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'M_edit','?'));
                inputSettings.matrix_edit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'matrix_edit','?'));
                inputSettings.tableVariable = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'tableVariable','?'));
                if isfield(IO,'tableVariables'), inputSettings.tableVariables = IO.tableVariables; end
                if isfield(IO,'matFiles'), inputSettings.matFiles = IO.matFiles; end
                if isfield(IO,'tableFiles'), inputSettings.tableFiles = IO.tableFiles; end
                if isfield(IO,'tabularFilters'), inputSettings.tabularFilters = IO.tabularFilters; end
                if isfield(IO,'variableRoles'), inputSettings.variableRoles = IO.variableRoles; end
                inputSettings.featureMappingMode = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'featureMappingMode','automatic'))));
                if ~strcmp(inputSettings.featureMappingMode,'manual'), inputSettings.featureMappingMode = 'automatic'; end
                if isfield(IO,'labelDefinition'), inputSettings.labelDefinition = IO.labelDefinition; end
                if isfield(IO,'metadataAlignmentMode'), inputSettings.metadataAlignmentMode = IO.metadataAlignmentMode; end
                inputSettings.caseAxisPolicy = NMDataIOImportTools.normalizeCaseAxisPolicy(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case'));
                inputSettings.caseAxisEstablishedByImport = logical(NMDataIOImportTools.fieldOr(IO,'caseAxisEstablishing',false));
                inputSettings.databaseConnector = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseConnector','sqlite_file'));
                inputSettings.databaseUrl = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseUrl','?'));
                inputSettings.databaseFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseFile','?'));
                inputSettings.databaseUser = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseUser','?'));
                inputSettings.databaseName = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseName','?'));
                inputSettings.databaseSchema = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseSchema','?'));
                inputSettings.databaseTable = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseTable','?'));
                inputSettings.databaseUseQuery = logical(NMDataIOImportTools.fieldOr(IO,'databaseUseQuery',false));
                inputSettings.databaseQuery = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'databaseQuery','?'));
                inputSettings.label_edit = NMDataIOImportTools.fieldOr(IO,'label_edit','?');
                inputSettings.case_edit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'case_edit','?'));
                inputSettings.col_edit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'col_edit','?'));
                inputSettings.covnames_edit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'covnames_edit','?'));
                inputSettings.covar_edit = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covar_edit',{}));
                inputSettings.ignore_edit = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'ignore_edit',{}));
                inputSettings.feature_edit = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'feature_edit',{}));
                inputSettings.covmanage_edit = NMDataIOImportTools.fieldOr(IO,'covmanage_edit',1);
                inputSettings.delimit = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'delimit','tab'));
                inputSettings.sheet = NMDataIOImportTools.fieldOr(IO,'sheet','?');
                inputSettings.sheets = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'sheets',{}));
                inputSettings.headerRow = NMDataIOImportTools.fieldOr(IO,'headerRow',[]);
                inputSettings.headerAutoDetect = logical(NMDataIOImportTools.fieldOr(IO,'headerAutoDetect',false));
                inputSettings.uniquelim = NMDataIOImportTools.fieldOr(IO,'uniquelim',15);
                inputSettings.requireFeatureNames = logical(NMDataIOImportTools.fieldOr(IO,'requireFeatureNames',false));
                inputSettings.requireCovariateNames = logical(NMDataIOImportTools.fieldOr(IO,'requireCovariateNames',false));
                if isfield(IO,'nanMapper') && isstruct(IO.nanMapper), inputSettings.nanMapper = IO.nanMapper; end
                if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles), inputSettings.tableColumnRoles = IO.tableColumnRoles; end
                if isfield(IO,'selFeats') && ~isempty(IO.selFeats), inputSettings.selFeats = IO.selFeats; end
                if isfield(IO,'selCases') && ~isempty(IO.selCases), inputSettings.selCases = IO.selCases; end
                return;
            end

            imageFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'imageFilesSpec',{}));
            if isempty(imageFiles), imageFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'imageFiles',{})); end
            if isempty(imageFiles), imageFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'PP',{})); end
            if isempty(imageFiles), imageFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'files',{})); end
            inputSettings.imageFiles = imageFiles(:);

            maskFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'maskFile',''));
            if isempty(maskFile), maskFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'brainmask','')); end
            inputSettings.maskFile = maskFile;
            inputSettings.brainmask = maskFile;
            inputSettings.caseIDMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'caseIDMode','legacy_spm'));
            if strcmpi(inputSettings.caseIDMode,'explicit')
                inputSettings.caseIds = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'imageCaseIDSpec',NMDataIOImportTools.fieldOr(IO,'explicitCaseIDs',{})));
            else
                inputSettings.caseIds = {};
            end

            inputSettings.auxiliarySourceType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'auxiliarySourceType','workspace'));
            inputSettings.auxiliaryAlignmentMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id'));
            inputSettings.auxiliaryVariableRoles = NMDataIOImportTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
            inputSettings.auxiliaryTableFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'auxiliaryTableFiles',{}));
            inputSettings.labelMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'labelMode','metadata'));
            inputSettings.groupSizes = NMDataIOImportTools.numericVector(NMDataIOImportTools.fieldOr(IO,'imageGroupSizes',[]));
            inputSettings.imageGroupSizes = inputSettings.groupSizes;
            inputSettings.groupNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'imageGroupNames',NMDataIOImportTools.fieldOr(IO,'desc_groups',{})));
            inputSettings.imageGroupNames = inputSettings.groupNames;
            inputSettings.classFileLists = NMDataIOImportTools.classFileListsFromIO(IO, inputSettings.imageFiles, inputSettings.groupNames, inputSettings.groupSizes);

            labelNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'labelNamesSpec', ...
                NMDataIOImportTools.fieldOr(IO,'labelNames', ...
                NMDataIOImportTools.fieldOr(IO,'regressionLabelNames', ...
                NMDataIOImportTools.fieldOr(IO,'desc_labels', ...
                NMDataIOImportTools.fieldOr(IO,'labelnames',{}))))));
            inputSettings.labelNames = labelNames;
            inputSettings.regressionLabelNames = labelNames;
            inputSettings.labelNamesSource = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'labelNamesSource','manual'));
            descLabels = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_labels', labelNames));
            if isempty(descLabels), descLabels = labelNames; end
            inputSettings.desc_labels = descLabels;
            inputSettings.labelnames = descLabels;
            inputSettings.covariateNames = NMDataIOImportTools.fieldOr(IO,'covariateNames',{});
            inputSettings.covmanage_edit = NMDataIOImportTools.fieldOr(IO,'covmanage_edit',1);
            inputSettings.uiGlobalModeSelection = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'uiGlobalModeSelection',NMDataIOImportTools.fieldOr(IO,'globalMode','none')));
            inputSettings.globalMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalMode','none'));
            inputSettings.globalSource = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalSource','user'));
            inputSettings.globalUserSourceType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalUserSourceType','workspace'));
            inputSettings.globalAlignmentMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalAlignmentMode','case_id'));
            inputSettings.globalVariableRoles = NMDataIOImportTools.fieldOr(IO,'globalVariableRoles',struct());
            inputSettings.globalTableFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'globalTableFiles',{}));
            inputSettings.globalName = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalName','GlobalSignal'));
            inputSettings.globnorm = NMDataIOImportTools.fieldOr(IO,'globnorm',1);
            inputSettings.threshop = NMDataIOImportTools.fieldOr(IO,'threshop',{'gt'});
            inputSettings.threshval = NMDataIOImportTools.fieldOr(IO,'threshval',0);
            inputSettings.threshlabels = NMDataIOImportTools.fieldOr(IO,'threshlabels',{'Bin Mask'});
            inputSettings.weightingFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'weightingFiles',{}));
            inputSettings.surfaceImportMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceImportMode','vertex_template'));
            inputSettings.surfaceTemplate = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceTemplate','unknown'));
            inputSettings.surfaceHemisphere = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceHemisphere','auto'));
            inputSettings.surfaceGeometryFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceGeometryFile',''));
            inputSettings.surfaceInflatedGeometryFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceInflatedGeometryFile',''));
            inputSettings.surfaceGeometryIdentity = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceGeometryIdentity',''));
            inputSettings.surfaceInflatedGeometryIdentity = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceInflatedGeometryIdentity',''));
            inputSettings.surfaceTopologyIdentity = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceTopologyIdentity',''));
            inputSettings.surfaceVertexOrderIdentity = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceVertexOrderIdentity',''));
            inputSettings.surfaceInflatedValidated = logical(NMDataIOImportTools.fieldOr(IO,'surfaceInflatedValidated',false));
            if isfield(IO,'surfaceGeometryContract') && isstruct(IO.surfaceGeometryContract), inputSettings.surfaceGeometryContract = IO.surfaceGeometryContract; end
            inputSettings.surfaceRoiCollapseMethod = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'surfaceRoiCollapseMethod','mean'));
            inputSettings.surfaceRoiLHScalarFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'surfaceRoiLHScalarFiles',{}));
            inputSettings.surfaceRoiLHAnnotFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'surfaceRoiLHAnnotFiles',{}));
            inputSettings.surfaceRoiRHScalarFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'surfaceRoiRHScalarFiles',{}));
            inputSettings.surfaceRoiRHAnnotFiles = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'surfaceRoiRHAnnotFiles',{}));
            if isfield(IO,'surfaceRoiInfo') && isstruct(IO.surfaceRoiInfo), inputSettings.surfaceRoiInfo = IO.surfaceRoiInfo; end
            if isfield(IO,'roiProvenance') && isstruct(IO.roiProvenance), inputSettings.roiProvenance = IO.roiProvenance; end
            inputSettings.spaceDefType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'spaceDefType','brainmask'));
            inputSettings.atlasImportMode = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasImportMode','voxelwise'));
            inputSettings.atlasCollapseMethod = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasCollapseMethod','soft_mean'));
            inputSettings.excludeSubjectZeros = logical(NMDataIOImportTools.fieldOr(IO,'excludeSubjectZeros',true));
            inputSettings.atlasLabelNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'atlasLabelNames',{}));
            inputSettings.atlasLabelFile = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasLabelFile',''));
            inputSettings.atlasLabelDelimiter = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasLabelDelimiter','auto'));
            inputSettings.atlasLabelHasHeader = NMDataIOImportTools.fieldOr(IO,'atlasLabelHasHeader','auto');
            inputSettings.atlasLabelIDColumn = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasLabelIDColumn',''));
            inputSettings.atlasLabelNameColumn = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'atlasLabelNameColumn',''));
            if isfield(IO,'atlasInfo') && isstruct(IO.atlasInfo), inputSettings.atlasInfo = IO.atlasInfo; end
            if isfield(IO,'atlasCollapseProvenance') && isstruct(IO.atlasCollapseProvenance), inputSettings.atlasCollapseProvenance = IO.atlasCollapseProvenance; end
            if isfield(IO,'selCases') && ~isempty(IO.selCases), inputSettings.selCases = IO.selCases; end
            if isfield(IO,'selFeats') && ~isempty(IO.selFeats), inputSettings.selFeats = IO.selFeats; end
        end

        function D = applyRegressionLabelNames(D, IO)
            % APPLYREGRESSIONLABELNAMES  Persist regression label names and clear classification groups.
            %
            %   D = NMDataIOImportTools.applyRegressionLabelNames(D, IO) copies available
            %   regression label descriptors into D.labelnames and removes D.groupnames when
            %   the import mode is regression.
            if nargin < 2 || ~isstruct(IO) || ~isstruct(D), return; end
            if ~strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','')), 'regression')
                return;
            end
            names = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_labels', ...
                NMDataIOImportTools.fieldOr(IO,'labelnames', ...
                NMDataIOImportTools.fieldOr(IO,'labelNames', ...
                NMDataIOImportTools.fieldOr(IO,'regressionLabelNames', ...
                NMDataIOImportTools.fieldOr(IO,'labelNamesSpec',{}))))));
            if ~isempty(names)
                D.labelnames = names(:)';
            end
            if isfield(D,'groupnames')
                D = rmfield(D,'groupnames');
            end
        end

        function tf = isImagingIO(IO)
            % isImagingIO  Detect whether a prepared IO payload belongs to image or surface import flow.
            %
            % IO -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            ds = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'datasource',''))));
            st = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType',''))));
            tf = ismember(ds, {'nifti','spm','surf','image'}) || strcmp(st,'image-list') || isfield(IO,'imageFiles') || isfield(IO,'maskFile');
        end

        function lists = classFileListsFromIO(IO, files, names, sizes)
            % classFileListsFromIO  Build class-specific image file lists from IO metadata for legacy transfer/reporting.
            %
            % Consumes IO, files, names, sizes; returns lists.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            files = NMDataIOImportTools.asCaseCell(files);
            names = NMDataIOImportTools.asCaseCell(names);
            sizes = NMDataIOImportTools.numericVector(sizes);
            lists = {};
            if isempty(sizes) && isfield(IO,'P') && iscell(IO.P)
                sizes = zeros(1,numel(IO.P));
                files = {};
                for i = 1:numel(IO.P)
                    pf = NMDataIOImportTools.asCaseCell(IO.P{i});
                    sizes(i) = numel(pf);
                    files = [files; pf(:)]; %#ok<AGROW>
                end
            end
            if isempty(sizes) || isempty(files), return; end
            sizes = round(double(sizes(:)'));
            pos = 1;
            for i = 1:numel(sizes)
                n = max(0, sizes(i));
                idx = pos:min(pos+n-1, numel(files));
                if numel(names) >= i && ~isempty(names{i}), nm = names{i}; else, nm = sprintf('Class_%d', i); end
                lists{end+1,1} = struct('name', char(string(nm)), 'files', {files(idx)}); %#ok<AGROW>
                pos = pos + n;
            end
        end

        function inputSettings = annotateInputSettingsForImportReport(inputSettings, IO)
            % ANNOTATEINPUTSETTINGSFORIMPORTREPORT  Copy import-report summaries into input settings.
            %
            %   inputSettings = ... stores case-alignment and related modalityInfo diagnostics
            %   from IO.importReport so that previews and committed datadescriptors can expose
            %   the same operational provenance.
            if nargin < 1 || ~isstruct(inputSettings), inputSettings = struct(); end
            if nargin < 2 || ~isstruct(IO) || ~isfield(IO,'importReport') || ~isstruct(IO.importReport)
                return;
            end
            if ~isfield(inputSettings,'modalityInfo') || ~isstruct(inputSettings.modalityInfo)
                inputSettings.modalityInfo = struct();
            end
            rep = IO.importReport;
            if isfield(rep,'caseAlignment') && isstruct(rep.caseAlignment)
                ca = rep.caseAlignment;
                inputSettings.modalityInfo.caseAlignment = ca;
                inputSettings.modalityInfo.missingCasesFilledWithNaN = false;
                inputSettings.modalityInfo.nMissingCasesFilledWithNaN = 0;
                inputSettings.modalityInfo.missingCasesFilledWithNaNIDs = {};
                if isfield(ca,'missingCases') && ~isempty(ca.missingCases) && ...
                        isfield(ca,'allowMissingCasesAsNaN') && ca.allowMissingCasesAsNaN
                    inputSettings.modalityInfo.missingCasesFilledWithNaN = true;
                    inputSettings.modalityInfo.nMissingCasesFilledWithNaN = numel(ca.missingCases);
                    inputSettings.modalityInfo.missingCasesFilledWithNaNIDs = ca.missingCases(:)';
                end
            end
            req = false;
            if isfield(rep,'requiresEarlyFusionImputation') && ~isempty(rep.requiresEarlyFusionImputation)
                req = logical(rep.requiresEarlyFusionImputation);
            end
            inputSettings.modalityInfo.requiresEarlyFusionImputation = req;
            inputSettings.modalityInfo.imputationRequiredForEarlyFusionOOCV = req;
            if req
                if isfield(IO,'oocvflag') && IO.oocvflag
                    inputSettings.modalityInfo.earlyFusionImputationReason = ...
                        'OOCV/application modality import filled missing target cases with NaN; early-fusion application models require an imputation step before/within concatenated data processing.';
                else
                    inputSettings.modalityInfo.earlyFusionImputationReason = ...
                        'Training modality import filled missing target cases with NaN; analyses require an explicit imputation strategy before affected features are used.';
                end
            elseif ~isfield(inputSettings.modalityInfo,'earlyFusionImputationReason')
                inputSettings.modalityInfo.earlyFusionImputationReason = '';
            end
        end

        function [preview, IO] = previewFromIO(IO, page, pageSize, maxCols)
            % PREVIEWFROMIO  Build a paginated browser preview from a prepared matrix IO contract.
            %
            %   [preview, IO] = ... extracts matrix axes, slices requested rows/columns,
            %   normalizes labels and feature names, and returns JSON-stable preview fields.
            %   The method does not commit data.
            if nargin < 2 || isempty(page), page = 1; end
            if nargin < 3 || isempty(pageSize), pageSize = 30; end
            if nargin < 4 || isempty(maxCols), maxCols = 20; end
            page = max(1, round(double(page)));
            pageSize = min(500, max(1, round(double(pageSize))));
            maxCols = min(200, max(1, round(double(maxCols))));

            [M, featureNames, caseIds, labels, IO] = NMDataIOImportTools.extractMatrixAxes(IO);
            nRows = size(M,1); nCols = size(M,2);
            rowStart = min(nRows+1, (page-1)*pageSize + 1);
            rowEnd = min(nRows, rowStart + pageSize - 1);
            if rowStart > nRows
                rowIdx = zeros(0,1);
            else
                rowIdx = (rowStart:rowEnd)';
            end
            colIdx = (1:min(nCols, maxCols));

            preview = struct();
            preview.page = page;
            preview.pageSize = pageSize;
            preview.maxColumns = maxCols;
            preview.nRows = nRows;
            preview.nColumns = nCols;
            preview.rowIndex = rowIdx(:)';
            preview.columnIndex = colIdx(:)';
            preview.caseIds = NMDataIOImportTools.selectCell(caseIds, rowIdx);
            if NMDataIOImportTools.previewShouldSuppressLabels(IO) || isempty(labels)
                preview.labels = {};
            else
                preview.labels = NMDataIOImportTools.selectCell(labels, rowIdx);
            end
            preview.featureNames = NMDataIOImportTools.selectCell(featureNames, colIdx);
            preview.values = NMDataIOImportTools.matrixToNestedCell(M(rowIdx, colIdx));
            preview.selection = struct();
            preview.selection.nSelectedCases = NMDataIOImportTools.selectionCount(IO, 'selCases', nRows);
            preview.selection.nSelectedFeatures = NMDataIOImportTools.selectionCount(IO, 'selFeats', nCols);
            preview.selection.hasSelection = (isfield(IO,'selCases') && ~isempty(IO.selCases)) || (isfield(IO,'selFeats') && ~isempty(IO.selFeats));
            preview.nanByPreviewSubject = NMDataIOImportTools.nanCounts(M(rowIdx, :), 2);
            preview.nanByPreviewFeature = NMDataIOImportTools.nanCounts(M(:, colIdx), 1);
        end

        function tf = previewShouldSuppressLabels(IO)
            % PREVIEWSHOULDSUPPRESSLABELS  Decide whether preview labels should be hidden.
            %
            %   tf = ... returns true for reference-case imports where labels are inherited
            %   from the existing target container rather than supplied by the incoming source.
            tf = false;
            if ~isstruct(IO), return; end
            if isfield(IO,'referenceCaseImport') && ~isempty(IO.referenceCaseImport) && logical(IO.referenceCaseImport)
                tf = true;
                return;
            end
            if isfield(IO,'importReport') && isstruct(IO.importReport) && ...
                    isfield(IO.importReport,'referenceCaseImport') && ~isempty(IO.importReport.referenceCaseImport) && ...
                    logical(IO.importReport.referenceCaseImport)
                tf = true;
            end
        end

        function [M, F, ID, L, IO] = extractMatrixAxes(IO)
            % EXTRACTMATRIXAXES  Resolve matrix values and associated feature/case/label axes.
            %
            %   [M, F, ID, L, IO] = ... reads supported prepared IO forms, validates two-
            %   dimensional predictor data, normalizes feature names and case IDs, and returns
            %   labels when present.  Invalid contracts raise explicit errors.
            if ~isstruct(IO)
                error('NMDataIOImportTools:invalidIO', 'IO must be a struct.');
            end
            L = [];
            if isfield(IO,'Y') && ~isempty(IO.Y) && ...
                    ((isfield(IO,'ID') && ~isempty(IO.ID)) || (isfield(IO,'s_ID') && ~isempty(IO.s_ID)))
                M = IO.Y;
                if istable(M), M = table2array(M); end
                if ~ismatrix(M)
                    error('NMDataIOImportTools:notMatrix', 'Predictor data must be a two-dimensional matrix/table.');
                end
                if isfield(IO,'ID') && ~isempty(IO.ID)
                    rawID = IO.ID;
                else
                    rawID = IO.s_ID;
                end
                ID = NMDataIOImportTools.asCellstr(rawID, 'S', size(M,1));
                if isfield(IO,'featnames') && ~isempty(IO.featnames)
                    F = NMDataIOImportTools.asCellstr(IO.featnames, 'F', size(M,2));
                elseif isfield(IO,'s_featnames') && ~isempty(IO.s_featnames)
                    F = NMDataIOImportTools.asCellstr(IO.s_featnames, 'F', size(M,2));
                else
                    F = NMDataIOImportTools.defaultNames('F', size(M,2));
                end
                if NMDataIOImportTools.isRoleManagedTableImport(IO) && isfield(IO,'s_label') && ~isempty(IO.s_label)
                    % Modern table-role materialization owns the incoming source label axis.
                    % Legacy CheckTabFile/ReadTabular may also populate IO.label; that field
                    % can be a converted/stale representation and must not supersede the
                    % native table label before canonical normalization.
                    L = IO.s_label;
                elseif isfield(IO,'label') && ~isempty(IO.label)
                    L = IO.label;
                elseif isfield(IO,'s_label') && ~isempty(IO.s_label)
                    L = IO.s_label;
                end
                return;
            end
            switch IO.groupmode
                case {1,2}
                    if isfield(IO,'t_Y') && ~isempty(IO.t_Y)
                        M = IO.t_Y;
                    else
                        switch IO.groupmode
                            case 1
                                M = evalin('base', IO.M_edit);
                            case 2
                                S = load(IO.M_edit, IO.matrix_edit); M = S.(IO.matrix_edit);
                        end
                    end
                    if istable(M)
                        error('NMDataIOImportTools:workspaceTableFeatureData', 'Workspace/MAT-file feature data must be a numeric matrix. Use the MATLAB table variable source for table feature data.');
                    end
                    F = NMDataIOImportTools.loadNamedVector(IO, 'feature');
                    ID = NMDataIOImportTools.loadNamedVector(IO, 'case');
                    if NMDataIOImportTools.labelsRequiredForIO(IO)
                        L = NMDataIOImportTools.loadNamedVector(IO, 'label');
                    end
                case {3,4,5,6}
                    if ~isfield(IO,'t_Y') || isempty(IO.t_Y)
                        switch IO.groupmode
                            case {3,4,5,6}
                                if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                                    IO.t_Y = NMDataIOTableReadTools.readTableFromIO(IO);
                                else
                                    switch IO.groupmode
                                        case 3, IO.t_Y = readtable(IO.M_edit, 'Delimiter', IO.delimit);
                                        case 4, IO.t_Y = readtable(IO.M_edit, 'Sheet', char(IO.sheet));
                                        case 5, IO.t_Y = evalin('base', char(IO.M_edit));
                                    end
                                end
                        end
                    end
                    if exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2
                        mess = [];
                        sourceTable = IO.t_Y;
                        [IO2, featureTable, mess] = NMDataIOTableRoleTools.prepareReadTabular(IO, sourceTable, mess);
                        if exist('CheckReadyStatus','file') == 2 && CheckReadyStatus(mess)
                            error('NMDataIOImportTools:tableRolePreviewFailed', 'Could not prepare table preview because column-role diagnostics are blocking.');
                        end
                        ID = IO2.s_ID;
                        if isfield(IO2,'s_label') && ~isempty(IO2.s_label)
                            L = IO2.s_label;
                        end
                        if isfield(IO2,'cellcols') && any(IO2.cellcols) && exist('nk_ScopeCellRetDummyFromTable','file') == 2
                            featureTable = nk_ScopeCellRetDummyFromTable('replace', featureTable, IO2.uniquelim);
                        end
                        if isfield(IO2,'s_featnames') && ~isempty(IO2.s_featnames)
                            F = IO2.s_featnames;
                        else
                            F = featureTable.Properties.VariableNames;
                        end
                        M = table2array(featureTable);
                        IO = IO2;
                        IO.t_Y = sourceTable;
                        IO.Y = M;
                        IO.ID = ID;
                        IO.s_ID = ID;
                        IO.featnames = F;
                        IO.s_featnames = F;
                        if ~isempty(L)
                            IO.s_label = L;
                        end
                    else
                        names = IO.t_Y.Properties.VariableNames;
                        col_cases = strcmp(names, char(IO.case_edit));
                        col_label = NMDataIOProbeTools.labelColumns(names, IO.label_edit);
                        ID = table2cell(IO.t_Y(:, col_cases));
                        if any(col_label)
                            L = table2array(IO.t_Y(:, col_label));
                        end
                        T = IO.t_Y(:, ~col_cases & ~col_label);
                        if isfield(IO,'cellcols') && any(IO.cellcols) && exist('nk_ScopeCellRetDummyFromTable','file') == 2
                            T = nk_ScopeCellRetDummyFromTable('replace', T, IO.uniquelim);
                        end
                        F = T.Properties.VariableNames;
                        M = table2array(T);
                    end
                otherwise
                    error('NMDataIOImportTools:unsupportedGroupmode', 'Unsupported groupmode for matrix preview: %g.', IO.groupmode);
            end
            if istable(M), M = table2array(M); end
            if ~ismatrix(M)
                error('NMDataIOImportTools:notMatrix', 'Predictor data must be a two-dimensional matrix/table.');
            end
            if isempty(F), F = NMDataIOImportTools.defaultNames('F', size(M,2)); end
            if isempty(ID), ID = NMDataIOImportTools.defaultNames('S', size(M,1)); end
            F = NMDataIOImportTools.asCellstr(F, 'F', size(M,2));
            ID = NMDataIOImportTools.asCellstr(ID, 'S', size(M,1));
            % Preserve the native explicit-label representation here. Classification
            % label normalization/encoding is owned centrally by
            % NMDataIOLabelStatsTools.normalizeForTransfer at the resolved transfer boundary.

            % Keep the resolved axes in the service-local IO container so
            % downstream preview, item selector, alignment and summaries do
            % not re-run table role resolution for the same source.  These
            % fields are stripped before browser state/draft persistence.
            IO.Y = M;
            IO.ID = ID;
            IO.s_ID = ID;
            IO.featnames = F;
            IO.s_featnames = F;
            if ~isempty(L)
                IO.s_label = L;
            end
            if NMDataIOImportTools.isRoleManagedTableImport(IO)
                cacheKey = NMDataIOImportTools.tablePreparedCacheKey(IO, [], 'raw');
                if ~isempty(cacheKey)
                    IO.dataioPreparedCacheKey = cacheKey;
                    IO.dataioPreparedCacheHit = false;
                    cachedMessages = NMDataIOMessageTools.emptyMessages();
                    [cacheHit0, cached0] = NMDataIOImportTools.tablePreparedCache('get', cacheKey);
                    if cacheHit0 && isstruct(cached0) && isfield(cached0,'messages')
                        cachedMessages = cached0.messages;
                    end
                    NMDataIOImportTools.tablePreparedCache('set', cacheKey, struct('IO', IO, 'messages', cachedMessages, 'createdAt', datestr(now,30), 'stage', 'resolved'));
                end
            end
        end

        function v = loadNamedVector(IO, kind)
            % LOADNAMEDVECTOR  Load a named feature, case, or label vector from the base workspace.
            %
            %   v = NMDataIOImportTools.loadNamedVector(IO, kind) resolves the configured
            %   *_edit field for the requested vector kind.  It returns [] for unknown or
            %   missing selectors and may evaluate a base-workspace variable name.
            v = [];
            switch lower(kind)
                case 'feature'
                    fld = 'col_edit';
                case 'case'
                    fld = 'case_edit';
                case 'label'
                    fld = 'label_edit';
                otherwise
                    fld = '';
            end
            if isempty(fld) || ~isfield(IO,fld) || NMDataIOImportTools.isUnknown(IO.(fld), '?'), return; end
            nameValue = IO.(fld);
            if iscell(nameValue)
                if isempty(nameValue), return; end
                nameValue = nameValue{1};
            elseif isstring(nameValue) && numel(nameValue) > 1
                nameValue = nameValue(1);
            end
            name = char(nameValue);
            switch IO.groupmode
                case 1
                    if evalin('base', sprintf('exist(''%s'', ''var'')', name))
                        v = evalin('base', name);
                    end
                case 2
                    W = whos('-file', IO.M_edit, name);
                    if ~isempty(W)
                        S = load(IO.M_edit, name); v = S.(name);
                    end
            end
        end


        function tf = hasVariableRoleMaterialization(IO)
            % HASVARIABLEROLEMATERIALIZATION  True for workspace/MAT variable-role imports.
            tf = false;
            if ~isstruct(IO) || ~isfield(IO,'sourceType') || ~isfield(IO,'variableRoles') || ~isstruct(IO.variableRoles)
                return;
            end
            st = lower(char(string(IO.sourceType)));
            if ~(ismember(st, {'workspace','matfile','tablefile','tablevar'}) || strcmp(st,'database')), return; end
            refs = NMDataIOImportTools.variableRoleRefs(IO, 'features');
            tf = ~isempty(refs);
        end

        function [IO, messages, mapping] = materializeConfiguredGlobalRole(IO, targetCaseIDs)
            % materializeConfiguredGlobalRole  Project one configured external global role onto an established case axis.
            %
            % This is the generic bridge from the persisted global-source contract to the existing
            % variable-role materializer. It owns no matching or source-reading algorithm itself.
            % Derived globals are provenance-context computations and therefore bypass this path.
            messages = NMDataIOMessageTools.emptyMessages();
            mapping = struct();
            if nargin < 2 || isempty(targetCaseIDs), return; end
            if NMDataIOImportTools.isDerivedGlobalSource(NMDataIOImportTools.fieldOr(IO,'globalSource','')), return; end
            roles = NMDataIOImportTools.fieldOr(IO,'globalVariableRoles',struct());
            refs = {};
            if isstruct(roles) && isfield(roles,'globals'), refs = NMDataIOStateTools.roleRefCell(roles.globals); end
            if isempty(refs), return; end
            roleIO = IO;
            roleIO.variableRoles = roles;
            roleIO.sourceType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalUserSourceType','workspace'));
            roleIO.metadataAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                NMDataIOImportTools.fieldOr(IO,'globalAlignmentMode','case_id'));
            if isfield(IO,'globalTableFiles'), roleIO.tableFiles = IO.globalTableFiles; end
            [roleIO, messages] = NMDataIOImportTools.materializeVariableRolePayload(roleIO, targetCaseIDs);
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if isfield(roleIO,'g') && ~isempty(roleIO.g)
                IO.g = roleIO.g(:);
                if any(~isfinite(double(IO.g)))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                        'Global input contains non-finite values. Provide one finite global value per case.', 1, 'red*')];
                    return;
                end
            end
            mapping = NMDataIOImportTools.fieldOr(roleIO,'dataIOAudit',struct());
            if isfield(IO,'importReport') && isstruct(IO.importReport), IO.importReport.globalMapping = mapping; end
        end

        function [IO, messages] = materializeVariableRolePayload(IO, targetCaseIDs)
            % MATERIALIZEVARIABLEROLEPAYLOAD  Materialize generic source blocks through one tabular contract.
            %
            % One-argument calls preserve the established tabular modality contract: at
            % least one feature block is required and the materializer owns case-axis
            % construction. A two-argument call is the explicit auxiliary-only contract:
            % labels/covariates/globals are projected onto the supplied established Case-ID
            % axis and no feature block is required. No existing automatic call site uses
            % the auxiliary-only contract.
            %
            % Keyed modes treat every row-bearing assignment as an atomic source block
            % consisting of the data reference plus ordered scalar/composite Case-ID key references.
            % Explicit row-order auxiliary materialization uses the supplied target Case-ID
            % axis and requires every selected auxiliary block to contain exactly that many rows.
            if nargin < 2, targetCaseIDs = []; end
            auxiliaryOnly = nargin >= 2;
            progressTask = NMDataIOImportTools.fieldOr(IO,'dataioProgressTask',NMProgressTools.emptyTaskForLocalUse());
            if isfield(IO,'dataioProgressTask'), IO = rmfield(IO,'dataioProgressTask'); end
            messages = NMDataIOMessageTools.emptyMessages();
            audit = NMDataIOImportTools.emptyDataIOAudit(IO);
            IO.dataIOAudit = audit;
            try
                featureRefs = NMDataIOImportTools.variableRoleRefs(IO, 'features');
                if ~auxiliaryOnly && isempty(featureRefs)
                    error('NMDataIOImportTools:variableFeatureRole', 'Assign at least one feature input.');
                end
                if auxiliaryOnly && isempty(targetCaseIDs)
                    error('NMDataIOImportTools:auxiliaryTargetCases', 'This operation needs an existing Case-ID list.');
                end
                caseRefs = NMDataIOImportTools.variableRoleRefs(IO, 'caseId');
                labelRefs = NMDataIOImportTools.variableRoleRefs(IO, 'labels');
                covRefs = NMDataIOImportTools.variableRoleRefs(IO, 'covariates');
                globalRefs = NMDataIOImportTools.variableRoleRefs(IO, 'globals');
                if auxiliaryOnly && isempty(labelRefs) && isempty(covRefs) && isempty(globalRefs)
                    error('NMDataIOImportTools:auxiliaryRoles', 'Select at least one label, covariate or global-value input.');
                end
                if numel(globalRefs) > 1
                    error('NMDataIOImportTools:globalRole', 'Select only one global-value input.');
                end
                if ~auxiliaryOnly && ~isempty(globalRefs)
                    error('NMDataIOImportTools:globalRoleContext', 'Global values can be added only to data matched to an existing Case-ID list.');
                end
                featNameRefs = NMDataIOImportTools.variableRoleRefs(IO, 'featureNames');
                covNameRefs = NMDataIOImportTools.variableRoleRefs(IO, 'covariateNames');
                if numel(covNameRefs) > 1
                    error('NMDataIOImportTools:variableNameRole', 'Select at most one covariate-name variable.');
                end
                mode = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'))));
                if strcmp(mode,'classification') && numel(labelRefs) > 1
                    error('NMDataIOImportTools:classificationMultiLabel', 'Classification accepts exactly one label input. Multiple label inputs are available only for regression.');
                end
                alignMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                    NMDataIOImportTools.fieldOr(IO,'metadataAlignmentMode','key_per_block'));
                audit.alignmentMode = alignMode;
                if auxiliaryOnly
                    audit.caseAxisPolicy = 'fixed_reference';
                else
                    audit.caseAxisPolicy = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case'));
                end
                audit.caseAxis.policy = audit.caseAxisPolicy;
                numericIssues = repmat(struct('role','','sourcePath','','sourceObject','','sourceLabel','','columnName','', ...
                    'headerRow',0,'nOffending',0,'rows',[],'sourceRows',[],'values',{{}},'nReported',0, ...
                    'mapperEnabled',false,'nMapped',0,'mapperTokens',{{}}),0,1);

                sourceObjectRefs = [featureRefs; labelRefs; covRefs; globalRefs; caseRefs; featNameRefs; covNameRefs];
                keyedBlockRefs = [featureRefs; labelRefs; covRefs; globalRefs];
                for ri = 1:numel(keyedBlockRefs)
                    oneRef = keyedBlockRefs{ri};
                    if isstruct(oneRef) && isfield(oneRef,'caseKeyRefs') && ~isempty(oneRef.caseKeyRefs)
                        sourceObjectRefs = [sourceObjectRefs; NMDataIOStateTools.roleRefCell(oneRef.caseKeyRefs)]; %#ok<AGROW>
                    end
                end
                sourceObjects = NMDataIOTableReadTools.materializeSourceObjects(IO, sourceObjectRefs, progressTask);
                NMProgressTools.phase(progressTask, 'tabular_role_materialization', 45, 50, ...
                    'Assigning selected columns and matching Case IDs.');

                featureBlocks = cell(numel(featureRefs),1);
                labelBlocks = cell(numel(labelRefs),1);
                covBlocks = cell(numel(covRefs),1);
                globalBlocks = cell(numel(globalRefs),1);
                for i = 1:numel(featureRefs)
                    [rawSource, sourceRows, sourceAudit] = NMDataIOImportTools.resolveVariableRef(IO, featureRefs{i}, sourceObjects);
                    raw = NMDataIOImportTools.rowVariable(rawSource, NMDataIOImportTools.variableRefName(featureRefs{i}));
                    conversionFailures = 0;
                    if NMDataIOImportTools.isCanonicalTabularColumnRef(featureRefs{i})
                        [raw, numericReport] = NMDataIOTableRoleTools.numericSourceColumn(IO, raw, 'Feature');
                        if ~numericReport.ok
                            issue = NMDataIOImportTools.numericSourceIssue(featureRefs{i}, numericReport, sourceRows);
                            numericIssues(end+1,1) = issue; %#ok<AGROW>
                            conversionFailures = double(issue.nOffending);
                        end
                    end
                    if ~(isnumeric(raw) || islogical(raw)) || ~ismatrix(raw)
                        error('NMDataIOImportTools:featureMatrixType', 'Assigned feature variable %s must be a two-dimensional numeric/logical matrix.', NMDataIOImportTools.variableRefName(featureRefs{i}));
                    end
                    [audit, auditIndex] = NMDataIOImportTools.registerDataIOAuditBlock(audit, IO, featureRefs{i}, 'feature', double(raw), sourceRows, sourceAudit, conversionFailures);
                    featureBlocks{i} = struct('ref',{featureRefs{i}},'data',{double(raw)},'ids',{{}},'auditIndex',auditIndex);
                end
                for i = 1:numel(labelRefs)
                    [rawSource, sourceRows, sourceAudit] = NMDataIOImportTools.resolveVariableRef(IO, labelRefs{i}, sourceObjects);
                    raw = NMDataIOImportTools.rowVariable(rawSource, NMDataIOImportTools.variableRefName(labelRefs{i}));
                    conversionFailures = 0;
                    if strcmp(mode,'regression') && NMDataIOImportTools.isCanonicalTabularColumnRef(labelRefs{i})
                        [raw, numericReport] = NMDataIOTableRoleTools.numericSourceColumn(IO, raw, 'Regression target');
                        if ~numericReport.ok
                            issue = NMDataIOImportTools.numericSourceIssue(labelRefs{i}, numericReport, sourceRows);
                            numericIssues(end+1,1) = issue; %#ok<AGROW>
                            conversionFailures = double(issue.nOffending);
                        end
                    end
                    if strcmp(mode,'regression') && ~(isnumeric(raw) || islogical(raw))
                        error('NMDataIOImportTools:regressionLabelType', 'Regression label input %s must contain numeric values.', NMDataIOImportTools.variableRefName(labelRefs{i}));
                    end
                    if strcmp(mode,'regression'), raw = double(raw); end
                    [audit, auditIndex] = NMDataIOImportTools.registerDataIOAuditBlock(audit, IO, labelRefs{i}, 'label', raw, sourceRows, sourceAudit, conversionFailures);
                    labelBlocks{i} = struct('ref',{labelRefs{i}},'data',{raw},'ids',{{}},'auditIndex',auditIndex);
                end
                for i = 1:numel(covRefs)
                    [rawSource, sourceRows, sourceAudit] = NMDataIOImportTools.resolveVariableRef(IO, covRefs{i}, sourceObjects);
                    raw = NMDataIOImportTools.rowVariable(rawSource, NMDataIOImportTools.variableRefName(covRefs{i}));
                    conversionFailures = 0;
                    if NMDataIOImportTools.isCanonicalTabularColumnRef(covRefs{i})
                        [raw, numericReport] = NMDataIOTableRoleTools.numericSourceColumn(IO, raw, 'Covariate');
                        if ~numericReport.ok
                            issue = NMDataIOImportTools.numericSourceIssue(covRefs{i}, numericReport, sourceRows);
                            numericIssues(end+1,1) = issue; %#ok<AGROW>
                            conversionFailures = double(issue.nOffending);
                        end
                    end
                    if ~(isnumeric(raw) || islogical(raw))
                        error('NMDataIOImportTools:covariateType', 'Covariate input %s must contain numeric values with one row per case.', NMDataIOImportTools.variableRefName(covRefs{i}));
                    end
                    [audit, auditIndex] = NMDataIOImportTools.registerDataIOAuditBlock(audit, IO, covRefs{i}, 'covariate', double(raw), sourceRows, sourceAudit, conversionFailures);
                    covBlocks{i} = struct('ref',{covRefs{i}},'data',{double(raw)},'ids',{{}},'auditIndex',auditIndex);
                end
                for i = 1:numel(globalRefs)
                    [rawSource, sourceRows, sourceAudit] = NMDataIOImportTools.resolveVariableRef(IO, globalRefs{i}, sourceObjects);
                    raw = NMDataIOImportTools.rowVariable(rawSource, NMDataIOImportTools.variableRefName(globalRefs{i}));
                    conversionFailures = 0;
                    if NMDataIOImportTools.isCanonicalTabularColumnRef(globalRefs{i})
                        [raw, numericReport] = NMDataIOTableRoleTools.numericSourceColumn(IO, raw, 'Global');
                        if ~numericReport.ok
                            issue = NMDataIOImportTools.numericSourceIssue(globalRefs{i}, numericReport, sourceRows);
                            numericIssues(end+1,1) = issue; %#ok<AGROW>
                            conversionFailures = double(issue.nOffending);
                        end
                    end
                    if ~(isnumeric(raw) || islogical(raw)) || ~isvector(raw)
                        error('NMDataIOImportTools:globalType', 'Assigned global variable %s must be one numeric/logical value per subject.', NMDataIOImportTools.variableRefName(globalRefs{i}));
                    end
                    raw = double(raw(:));
                    [audit, auditIndex] = NMDataIOImportTools.registerDataIOAuditBlock(audit, IO, globalRefs{i}, 'global', raw, sourceRows, sourceAudit, conversionFailures);
                    globalBlocks{i} = struct('ref',{globalRefs{i}},'data',{raw},'ids',{{}},'auditIndex',auditIndex);
                end

                allBlocks = [featureBlocks; labelBlocks; covBlocks; globalBlocks];
                % Keyed alignment plans are created once per unique source object + ordered Case-ID key.
                % Row-order mode deliberately leaves these collections empty because no key matching is performed.
                keyPlanKeys = cell(0,1); keyPlanIDs = cell(0,1); keyPlanSourceRows = cell(0,1);
                keyPlanRefs = cell(0,1); keyPlanDuplicateReports = cell(0,1); keyPlanRowMaps = cell(0,1);
                if strcmp(alignMode,'row_order')
                    if auxiliaryOnly
                        finalIDs = NMDataIOImportTools.caseKeyRows(targetCaseIDs, true);
                        nRows = cellfun(@(b) size(b.data,1), allBlocks);
                        if ~isempty(nRows) && any(nRows ~= nRows(1))
                            error('NMDataIOImportTools:rowOrderRowCount', 'Explicit row order requires the same number of rows in every selected case-based input.');
                        end
                        if ~isempty(nRows) && numel(finalIDs) ~= nRows(1)
                            error('NMDataIOImportTools:rowOrderCaseCount', 'The current Case-ID list contains %g cases, but the selected label/covariate/global input contains %g rows.', numel(finalIDs), nRows(1));
                        end
                        NMDataIOImportTools.assertUniqueCaseKeyRows(finalIDs, 'NMDataIOImportTools:duplicatePSN', ...
                            'The target Case-ID list contains duplicates. Each case must have a unique PSN/Case-ID value.');
                        axisSource = 'row_order';
                        audit.axisSource = axisSource;
                        audit.caseAxis.source = axisSource;
                        audit.caseAxis.nFinalCases = numel(finalIDs);
                        audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'row_order', 'case_axis', ...
                            'established_container', 0, numel(finalIDs), numel(finalIDs));
                        for ai = 1:numel(allBlocks)
                            audit = NMDataIOImportTools.markDataIOAuditBlockRowOrder(audit, allBlocks{ai}.auditIndex, allBlocks{ai}.data);
                        end
                    else
                        if numel(caseRefs) ~= 1
                            error('NMDataIOImportTools:rowOrderCaseId', 'Explicit row-order mode requires exactly one PSN/Case-ID variable for the final case list. Select one Case-ID variable.');
                        end
                        [rowOrderCaseSource, rowOrderCaseRows] = NMDataIOImportTools.resolveVariableRef(IO, caseRefs{1}, sourceObjects);
                        finalIDs = NMDataIOImportTools.caseIdCell(rowOrderCaseSource);
                        nRows = cellfun(@(b) size(b.data,1), allBlocks);
                        if ~isempty(nRows) && any(nRows ~= nRows(1))
                            error('NMDataIOImportTools:rowOrderRowCount', 'Explicit row order requires the same number of rows in every selected case-based input.');
                        end
                        if ~isempty(nRows) && numel(finalIDs) ~= nRows(1)
                            error('NMDataIOImportTools:rowOrderCaseCount', 'The row-order Case-ID variable contains %g entries, but the selected inputs contain %g rows.', numel(finalIDs), nRows(1));
                        end
                        rowOrderDup = NMDataIOImportTools.caseKeyDuplicateReport(finalIDs, rowOrderCaseRows, caseRefs);
                        NMDataIOImportTools.assertUniqueCaseKeyRows(finalIDs, 'NMDataIOImportTools:duplicatePSN', ...
                            'PSN/Case-ID values must be unique in explicit row-order mode.', rowOrderCaseRows, caseRefs);
                        axisSource = 'row_order';
                        audit.axisSource = axisSource;
                        audit.caseAxis.source = axisSource;
                        audit.caseAxis.nFinalCases = numel(finalIDs);
                        audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'row_order', 'case_axis', ...
                            NMDataIOImportTools.variableRefName(caseRefs{1}), 0, numel(finalIDs), numel(finalIDs));
                        for ai = 1:numel(allBlocks)
                            audit = NMDataIOImportTools.markDataIOAuditBlockRowOrder(audit, allBlocks{ai}.auditIndex, allBlocks{ai}.data);
                        end
                    end
                else
                    componentCounts = zeros(numel(allBlocks),1);
                    for i = 1:numel(allBlocks)
                        blockRef = allBlocks{i}.ref;
                        planKey = NMDataIOImportTools.sourceBlockCaseKeyIdentity(IO, blockRef);
                        planIndex = find(strcmp(keyPlanKeys,planKey),1);
                        if isempty(planIndex)
                            [ids, keySourceRows] = NMDataIOImportTools.resolveSourceBlockCaseKeys(IO, blockRef, sourceObjects);
                            keyRefs = NMDataIOStateTools.roleRefCell(blockRef.caseKeyRefs);
                            planIndex = numel(keyPlanKeys) + 1;
                            keyPlanKeys{planIndex,1} = planKey;
                            keyPlanIDs{planIndex,1} = ids;
                            keyPlanSourceRows{planIndex,1} = keySourceRows;
                            keyPlanRefs{planIndex,1} = keyRefs;
                            keyPlanDuplicateReports{planIndex,1} = NMDataIOImportTools.caseKeyDuplicateReport(ids, keySourceRows, keyRefs);
                        else
                            ids = keyPlanIDs{planIndex}; keySourceRows = keyPlanSourceRows{planIndex}; keyRefs = keyPlanRefs{planIndex};
                        end
                        nKeyRows = size(ids,1);
                        if nKeyRows ~= size(allBlocks{i}.data,1)
                            error('NMDataIOImportTools:blockCaseCount', ...
                                'Input %s has %g row(s), but its selected Case-ID key has %g row(s).', ...
                                NMDataIOImportTools.variableRefName(blockRef), size(allBlocks{i}.data,1), nKeyRows);
                        end
                        audit = NMDataIOImportTools.updateDataIOAuditBlockKeys(audit, allBlocks{i}.auditIndex, keyPlanDuplicateReports{planIndex});
                        allBlocks{i}.ids = ids;
                        allBlocks{i}.keySourceRows = keySourceRows;
                        allBlocks{i}.keyRefs = keyRefs;
                        allBlocks{i}.keyPlanIndex = planIndex;
                        componentCounts(i) = NMDataIOImportTools.caseKeyComponentCount(ids);
                    end
                    sourceType = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType','workspace'))));
                    if strcmp(sourceType,'workspace') && any(componentCounts > 1)
                        error('NMDataIOImportTools:workspaceCompositeCaseKey', ...
                            'MATLAB workspace arrays support one Case-ID variable. Composite Case IDs require tabular input.');
                    end
                    if strcmp(sourceType,'workspace') && strcmp(alignMode,'shared_key')
                        error('NMDataIOImportTools:workspaceSharedKey', ...
                            'Plain MATLAB workspace arrays do not support shared-key assignment; use explicit per-block Case-ID vectors or row order.');
                    end
                    if strcmp(alignMode,'shared_key') && numel(unique(componentCounts)) > 1
                        error('NMDataIOImportTools:sharedKeyWidth', ...
                            'A shared Case-ID key requires the same ordered key columns in every selected input.');
                    end
                    featureBlocks = allBlocks(1:numel(featureBlocks));
                    labelOffset = numel(featureBlocks);
                    labelBlocks = allBlocks(labelOffset + (1:numel(labelBlocks)));
                    covOffset = labelOffset + numel(labelBlocks);
                    covBlocks = allBlocks(covOffset + (1:numel(covBlocks)));
                    globalOffset = covOffset + numel(covBlocks);
                    globalBlocks = allBlocks(globalOffset + (1:numel(globalBlocks)));
                    featureAxisBlocks = NMDataIOImportTools.uniqueCaseKeyPlanBlocks(featureBlocks);
                    labelAxisBlocks = NMDataIOImportTools.uniqueCaseKeyPlanBlocks(labelBlocks);
                    covAxisBlocks = NMDataIOImportTools.uniqueCaseKeyPlanBlocks(covBlocks);
                    if auxiliaryOnly
                        referenceIDs = NMDataIOImportTools.caseKeyRows(targetCaseIDs, true);
                    else
                        referenceIDs = NMDataIOImportTools.caseKeyRows(NMDataIOImportTools.fieldOr(IO,'sourceBlockReferenceCases',{}), true);
                    end
                    if auxiliaryOnly
                        caseAxisPolicy = 'fixed_reference';
                    else
                        caseAxisPolicy = NMDataIOImportTools.normalizeCaseAxisPolicy(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case'));
                    end
                    if ~isempty(referenceIDs)
                        NMDataIOImportTools.assertUniqueCaseKeyRows(referenceIDs, 'NMDataIOImportTools:duplicateReferencePSN', ...
                            'The current Case-ID list contains duplicate Case IDs.');
                        finalIDs = referenceIDs;
                        axisSource = 'established_container';
                        audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'fixed_reference', 'case_axis', axisSource, 0, numel(referenceIDs), numel(referenceIDs));
                    else
                        switch caseAxisPolicy
                            case 'complete_case'
                                finalIDs = NMDataIOImportTools.uniqueCaseKeyRowsStable(featureAxisBlocks{1}.ids);
                                audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'seed', 'feature', NMDataIOImportTools.variableRefName(featureAxisBlocks{1}.ref), 0, numel(finalIDs), numel(finalIDs));
                                for i = 2:numel(featureAxisBlocks)
                                    nBefore = numel(finalIDs); nIncoming = numel(featureAxisBlocks{i}.ids);
                                    finalIDs = NMDataIOImportTools.intersectIdsStable(finalIDs, featureAxisBlocks{i}.ids);
                                    audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'intersection', 'feature', NMDataIOImportTools.variableRefName(featureAxisBlocks{i}.ref), nBefore, nIncoming, numel(finalIDs));
                                end
                                for i = 1:numel(covAxisBlocks)
                                    nBefore = numel(finalIDs); nIncoming = numel(covAxisBlocks{i}.ids);
                                    finalIDs = NMDataIOImportTools.intersectIdsStable(finalIDs, covAxisBlocks{i}.ids);
                                    audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'intersection', 'covariate', NMDataIOImportTools.variableRefName(covAxisBlocks{i}.ref), nBefore, nIncoming, numel(finalIDs));
                                end
                                if strcmp(mode,'classification')
                                    for i = 1:numel(labelAxisBlocks)
                                        nBefore = numel(finalIDs); nIncoming = numel(labelAxisBlocks{i}.ids);
                                        finalIDs = NMDataIOImportTools.intersectIdsStable(finalIDs, labelAxisBlocks{i}.ids);
                                        audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'intersection', 'label', NMDataIOImportTools.variableRefName(labelAxisBlocks{i}.ref), nBefore, nIncoming, numel(finalIDs));
                                    end
                                end
                                axisSource = 'complete_case';
                            case 'target_anchored'
                                if isempty(labelBlocks)
                                    error('NMDataIOImportTools:targetAnchoredLabelsRequired', ...
                                        'Using cases defined by the labels requires labels when the first modality creates a new training or OOCV Case-ID list.');
                                end
                                for i = 1:numel(labelAxisBlocks)
                                    NMDataIOImportTools.assertUniqueCaseKeyRows(labelAxisBlocks{i}.ids, 'NMDataIOImportTools:duplicatePSN', ...
                                        sprintf('Case-ID combinations must be unique in axis-defining label input %s.', NMDataIOImportTools.variableRefName(labelAxisBlocks{i}.ref)), ...
                                        labelAxisBlocks{i}.keySourceRows, labelAxisBlocks{i}.keyRefs);
                                end
                                finalIDs = labelAxisBlocks{1}.ids(:);
                                audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'seed', 'label', NMDataIOImportTools.variableRefName(labelAxisBlocks{1}.ref), 0, numel(finalIDs), numel(finalIDs));
                                for i = 2:numel(labelAxisBlocks)
                                    ids = labelAxisBlocks{i}.ids(:); nBefore = numel(finalIDs);
                                    finalIDs = NMDataIOImportTools.unionIdsStable(finalIDs, ids);
                                    audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'union', 'label', NMDataIOImportTools.variableRefName(labelAxisBlocks{i}.ref), nBefore, numel(ids), numel(finalIDs));
                                end
                                axisSource = 'targets';
                            case 'feature_union'
                                finalIDs = NMDataIOImportTools.uniqueCaseKeyRowsStable(featureAxisBlocks{1}.ids);
                                audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'seed', 'feature', NMDataIOImportTools.variableRefName(featureAxisBlocks{1}.ref), 0, numel(finalIDs), numel(finalIDs));
                                for i = 2:numel(featureAxisBlocks)
                                    ids = NMDataIOImportTools.uniqueCaseKeyRowsStable(featureAxisBlocks{i}.ids); nBefore = numel(finalIDs);
                                    finalIDs = NMDataIOImportTools.unionIdsStable(finalIDs, ids);
                                    audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'union', 'feature', NMDataIOImportTools.variableRefName(featureAxisBlocks{i}.ref), nBefore, numel(ids), numel(finalIDs));
                                end
                                if strcmp(mode,'classification') && ~isempty(labelAxisBlocks)
                                    nBefore = numel(finalIDs); nIncoming = numel(labelAxisBlocks{1}.ids);
                                    finalIDs = NMDataIOImportTools.intersectIdsStable(finalIDs, labelAxisBlocks{1}.ids);
                                    audit = NMDataIOImportTools.appendDataIOCaseAxisStep(audit, 'intersection', 'label', NMDataIOImportTools.variableRefName(labelAxisBlocks{1}.ref), nBefore, nIncoming, numel(finalIDs));
                                end
                                axisSource = 'feature_union';
                        end
                        finalIDs = NMDataIOImportTools.sortCaseKeyRows(finalIDs);
                    end
                    audit.axisSource = axisSource;
                    audit.caseAxis.source = axisSource;
                    audit.caseAxis.nFinalCases = numel(finalIDs);
                    if isempty(finalIDs)
                        error('NMDataIOImportTools:noCommonCases', 'Case-ID matching produced no cases. Check the selected Case-ID variables, filters and matching mode.');
                    end
                    keyPlanRowMaps = cell(numel(keyPlanIDs),1);
                    uniquePlanBlocks = NMDataIOImportTools.uniqueCaseKeyPlanBlocks(allBlocks);
                    for i = 1:numel(uniquePlanBlocks)
                        block = uniquePlanBlocks{i};
                        NMDataIOImportTools.assertBlockCaseKeysUniqueOnAxis(block, finalIDs, keyPlanDuplicateReports{block.keyPlanIndex});
                        opts = struct('idMappingMode','auto','mappingApproved',true);
                        [matched, loc, mapReport] = NMDataIOImportTools.resolveCaseRowMap(finalIDs, block.ids, opts);
                        keyPlanRowMaps{block.keyPlanIndex} = struct('matched',matched,'loc',loc,'report',mapReport);
                    end
                end

                featureParts = cell(numel(featureBlocks),1);
                reportedKeyPlans = false(numel(keyPlanIDs),1);
                for i = 1:numel(featureBlocks)
                    if strcmp(alignMode,'row_order')
                        featureParts{i} = featureBlocks{i}.data;
                    else
                        allowFeatureMissing = ~isempty(NMDataIOImportTools.fieldOr(IO,'sourceBlockReferenceCases',{})) || ...
                            ismember(NMDataIOImportTools.normalizeCaseAxisPolicy(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case')), {'target_anchored','feature_union'});
                        rowMap = keyPlanRowMaps{featureBlocks{i}.keyPlanIndex};
                        [featureParts{i}, blockMap] = NMDataIOImportTools.alignBlockRows(featureBlocks{i}.data, featureBlocks{i}.ids, finalIDs, allowFeatureMissing, rowMap);
                        audit = NMDataIOImportTools.updateDataIOAuditBlockAlignment(audit, featureBlocks{i}.auditIndex, blockMap, featureParts{i}, featureBlocks{i}.data, allowFeatureMissing);
                        if ~reportedKeyPlans(featureBlocks{i}.keyPlanIndex)
                            messages = [messages; NMDataIOImportTools.sourceBlockMapMessage(featureBlocks{i}.ref, blockMap)];
                            reportedKeyPlans(featureBlocks{i}.keyPlanIndex) = true;
                        end
                    end
                end
                if isempty(featureParts), M = zeros(size(finalIDs,1),0); else, M = horzcat(featureParts{:}); end
                featureNames = {};
                if isempty(featNameRefs)
                    tableFeatureRefs = cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), featureRefs);
                    if all(tableFeatureRefs)
                        featureNames = cellfun(@(r) NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(r,'columnName',NMDataIOImportTools.variableRefName(r))), featureRefs, 'UniformOutput', false);
                    elseif logical(NMDataIOImportTools.fieldOr(IO,'requireFeatureNames',false))
                        error('NMDataIOImportTools:featureNamesRequired', 'Assign a feature-name variable to every feature input before Preview or Commit.');
                    else
                        featureNames = NMDataIOImportTools.defaultNames('F', size(M,2));
                    end
                else
                    featureNameParts = cell(numel(featureBlocks),1);
                    for i = 1:numel(featureBlocks)
                        hits = [];
                        for j = 1:numel(featNameRefs)
                            targetRef = NMDataIOImportTools.fieldOr(featNameRefs{j},'featureBlockRef',struct());
                            targetName = NMDataIOImportTools.variableRefName(targetRef);
                            if isempty(targetName) && numel(featureRefs) == 1 && numel(featNameRefs) == 1
                                hits(end+1) = j; %#ok<AGROW>
                            elseif ~isempty(targetName) && ...
                                    strcmp(targetName, NMDataIOImportTools.variableRefName(featureRefs{i})) && ...
                                    strcmp(NMDataIOImportTools.variableRefSourceKey(IO,targetRef), NMDataIOImportTools.variableRefSourceKey(IO,featureRefs{i}))
                                hits(end+1) = j; %#ok<AGROW>
                            end
                        end
                        if isempty(hits)
                            error('NMDataIOImportTools:featureNamesRequired', 'Feature input %s has no assigned feature-name variable.', NMDataIOImportTools.variableRefName(featureRefs{i}));
                        elseif numel(hits) > 1
                            error('NMDataIOImportTools:featureNameMapping', 'Feature input %s has more than one assigned feature-name variable.', NMDataIOImportTools.variableRefName(featureRefs{i}));
                        end
                        localNames = NMDataIOImportTools.nameCell(NMDataIOImportTools.resolveVariableRef(IO, featNameRefs{hits(1)}, sourceObjects));
                        if numel(localNames) ~= size(featureBlocks{i}.data,2)
                            error('NMDataIOImportTools:featureNameCount', 'Feature-name variable %s contains %g name(s), but feature input %s contains %g column(s).', ...
                                NMDataIOImportTools.variableRefName(featNameRefs{hits(1)}), numel(localNames), NMDataIOImportTools.variableRefName(featureRefs{i}), size(featureBlocks{i}.data,2));
                        end
                        featureNameParts{i} = localNames(:)';
                    end
                    featureNames = [featureNameParts{:}];
                end

                labelParts = cell(numel(labelBlocks),1);
                for i = 1:numel(labelBlocks)
                    if strcmp(alignMode,'row_order')
                        labelParts{i} = labelBlocks{i}.data;
                    elseif strcmp(mode,'regression')
                        rowMap = keyPlanRowMaps{labelBlocks{i}.keyPlanIndex};
                        [labelParts{i}, blockMap] = NMDataIOImportTools.alignBlockRows(labelBlocks{i}.data, labelBlocks{i}.ids, finalIDs, true, rowMap);
                        audit = NMDataIOImportTools.updateDataIOAuditBlockAlignment(audit, labelBlocks{i}.auditIndex, blockMap, labelParts{i}, labelBlocks{i}.data, true);
                        if ~reportedKeyPlans(labelBlocks{i}.keyPlanIndex), messages = [messages; NMDataIOImportTools.sourceBlockMapMessage(labelBlocks{i}.ref, blockMap)]; reportedKeyPlans(labelBlocks{i}.keyPlanIndex) = true; end
                    else
                        rowMap = keyPlanRowMaps{labelBlocks{i}.keyPlanIndex};
                        [labelParts{i}, blockMap] = NMDataIOImportTools.alignBlockRows(labelBlocks{i}.data, labelBlocks{i}.ids, finalIDs, false, rowMap);
                        audit = NMDataIOImportTools.updateDataIOAuditBlockAlignment(audit, labelBlocks{i}.auditIndex, blockMap, labelParts{i}, labelBlocks{i}.data, false);
                        if ~reportedKeyPlans(labelBlocks{i}.keyPlanIndex), messages = [messages; NMDataIOImportTools.sourceBlockMapMessage(labelBlocks{i}.ref, blockMap)]; reportedKeyPlans(labelBlocks{i}.keyPlanIndex) = true; end
                    end
                end
                if isempty(labelParts)
                    labels = [];
                elseif strcmp(mode,'classification')
                    labels = labelParts{1};
                    if ischar(labels), labels = cellstr(labels); end
                    if isstring(labels) || iscategorical(labels), labels = labels(:); end
                    if iscell(labels), labels = labels(:); end
                    if (isnumeric(labels) || islogical(labels)) && isvector(labels), labels = labels(:); end
                else
                    labels = horzcat(labelParts{:});
                    % Canonical tabular regression targets are intrinsically named by
                    % their selected source columns. Preserve that ordered identity so
                    % the established transfer-count path writes the same names into
                    % IO.desc_labels / NM.labelnames without a redundant naming dialog.
                    if ~isempty(labelRefs)
                        tableRefs = cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), labelRefs);
                        scalarRefs = numel(labelParts) == numel(labelRefs) && all(cellfun(@(x) size(x,2)==1, labelParts));
                        if all(tableRefs) && scalarRefs
                            sourceNames = cellfun(@(r) NMDataIOImportTools.asChar( ...
                                NMDataIOImportTools.fieldOr(r,'columnName',NMDataIOImportTools.variableRefName(r))), ...
                                labelRefs, 'UniformOutput', false);
                            if numel(sourceNames) == size(labels,2) && ~any(cellfun(@isempty,sourceNames))
                                % For canonical tabular regression, source headers are the target
                                % identity. Remove stale/manual naming fields so they cannot override
                                % the selected columns during transfer or Resume.
                                for nameField = {'labelDefinition','labelNamesSpec','labelNames','regressionLabelNames','labelnames'}
                                    if isfield(IO,nameField{1}), IO = rmfield(IO,nameField{1}); end
                                end
                                IO.desc_labels = sourceNames(:)';
                            end
                        end
                    end
                end

                covParts = cell(numel(covBlocks),1);
                for i = 1:numel(covBlocks)
                    if strcmp(alignMode,'row_order')
                        covParts{i} = covBlocks{i}.data;
                    else
                        allowCovariateMissing = auxiliaryOnly || ~isempty(NMDataIOImportTools.fieldOr(IO,'sourceBlockReferenceCases',{})) || ...
                            ismember(NMDataIOImportTools.normalizeCaseAxisPolicy(NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case')), {'target_anchored','feature_union'});
                        rowMap = keyPlanRowMaps{covBlocks{i}.keyPlanIndex};
                        [covParts{i}, blockMap] = NMDataIOImportTools.alignBlockRows(covBlocks{i}.data, covBlocks{i}.ids, finalIDs, allowCovariateMissing, rowMap);
                        audit = NMDataIOImportTools.updateDataIOAuditBlockAlignment(audit, covBlocks{i}.auditIndex, blockMap, covParts{i}, covBlocks{i}.data, allowCovariateMissing);
                        if ~reportedKeyPlans(covBlocks{i}.keyPlanIndex), messages = [messages; NMDataIOImportTools.sourceBlockMapMessage(covBlocks{i}.ref, blockMap)]; reportedKeyPlans(covBlocks{i}.keyPlanIndex) = true; end
                    end
                end
                if isempty(covParts), covars = []; else, covars = horzcat(covParts{:}); end
                covNames = {};
                if ~isempty(covars)
                    if ~isempty(covNameRefs)
                        covNames = NMDataIOImportTools.nameCell(NMDataIOImportTools.resolveVariableRef(IO, covNameRefs{1}, sourceObjects));
                    else
                        tableCovRefs = cellfun(@(r) NMDataIOImportTools.isCanonicalTabularColumnRef(r), covRefs);
                        if ~isempty(covRefs) && all(tableCovRefs)
                            covNames = cellfun(@(r) NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(r,'columnName',NMDataIOImportTools.variableRefName(r))), covRefs, 'UniformOutput', false);
                        else
                            covNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covariateNameList',{}));
                            covNames = cellfun(@(x) strtrim(char(string(x))), covNames, 'UniformOutput', false);
                            covNames = covNames(~cellfun(@isempty,covNames));
                        end
                    end
                    if isempty(covNames) && logical(NMDataIOImportTools.fieldOr(IO,'requireCovariateNames',false))
                        error('NMDataIOImportTools:covariateNamesRequired', 'Assign a covariate-name variable or provide manual covariate names before preview or commit.');
                    end
                    if isempty(covNames), covNames = NMDataIOImportTools.defaultNames('Covariate_', size(covars,2)); end
                    if numel(covNames) ~= size(covars,2)
                        error('NMDataIOImportTools:covariateNameCount', 'Covariate-name definition contains %g name(s), but the concatenated covariate blocks contain %g column(s).', numel(covNames), size(covars,2));
                    end
                end

                globalParts = cell(numel(globalBlocks),1);
                for i = 1:numel(globalBlocks)
                    if strcmp(alignMode,'row_order')
                        globalParts{i} = globalBlocks{i}.data;
                    else
                        rowMap = keyPlanRowMaps{globalBlocks{i}.keyPlanIndex};
                        [globalParts{i}, blockMap] = NMDataIOImportTools.alignBlockRows(globalBlocks{i}.data, globalBlocks{i}.ids, finalIDs, false, rowMap);
                        audit = NMDataIOImportTools.updateDataIOAuditBlockAlignment(audit, globalBlocks{i}.auditIndex, blockMap, globalParts{i}, globalBlocks{i}.data, false);
                        if ~reportedKeyPlans(globalBlocks{i}.keyPlanIndex), messages = [messages; NMDataIOImportTools.sourceBlockMapMessage(globalBlocks{i}.ref, blockMap)]; reportedKeyPlans(globalBlocks{i}.keyPlanIndex) = true; end
                    end
                end
                if isempty(globalParts), globals = []; else, globals = globalParts{1}; end

                axisIDs = NMDataIOImportTools.caseKeyAxisIds(finalIDs);
                if auxiliaryOnly
                    IO.ID = axisIDs(:);
                    IO.s_ID = axisIDs(:);
                    if ~isempty(labels), IO.label = labels; IO.s_label = labels; IO.L = labels; end
                    if ~isempty(covars), IO.covars = covars; IO.covnames = covNames(:)'; end
                    if ~isempty(globals), IO.g = globals(:); end
                    sourceKeys = cellfun(@(b) NMDataIOImportTools.variableRefSourceKey(IO,b.ref), allBlocks, 'UniformOutput', false);
                    sourceKeys = unique(sourceKeys, 'stable');
                    anchorRows = size(allBlocks{1}.data,1);
                    if strcmp(alignMode,'row_order')
                        excludedAnchorRows = 0;
                    else
                        anchorReport = keyPlanRowMaps{allBlocks{1}.keyPlanIndex}.report;
                        excludedAnchorRows = anchorRows - double(NMDataIOImportTools.fieldOr(anchorReport,'nMatchedIncomingCases',0));
                    end
                    audit.status = 'complete';
                    audit.nFinalCases = size(finalIDs,1);
                    audit.nFinalFeatures = 0;
                    audit.nFinalLabelTargets = size(labels,2);
                    if strcmp(mode,'classification') && ~isempty(labels), audit.nFinalLabelTargets = 1; end
                    audit.nFinalCovariates = size(covars,2);
                    audit.nFinalGlobals = double(~isempty(globals));
                    audit.caseAxis.nFinalCases = size(finalIDs,1);
                    IO.dataIOAudit = audit;
                    IO.variableMaterialization = struct('alignmentMode',alignMode,'caseAxisPolicy','fixed_reference', ...
                        'axisSource',axisSource,'sourceKeys',{sourceKeys},'nSourceRows',anchorRows,'nAlignedRows',size(finalIDs,1), ...
                        'caseKeyComponentCount',NMDataIOImportTools.caseKeyComponentCount(finalIDs),'excludedAnchorRows',excludedAnchorRows, ...
                        'nFeatureBlocks',0,'nLabelBlocks',numel(labelBlocks),'nCovariateBlocks',numel(covBlocks), ...
                        'nGlobalBlocks',numel(globalBlocks),'nCaseKeyPlans',numel(keyPlanKeys),'auxiliaryOnly',true,'numericSourceIssues',{numericIssues});
                    messages = [messages; NMDataIOMessageTools.make('info', false, 'variableRoleMaterialization', ...
                        sprintf('Prepared %g existing case(s), %g label target(s), %g covariate(s), and %g global-value vector(s) from the selected inputs.', ...
                        size(finalIDs,1), audit.nFinalLabelTargets, size(covars,2), double(~isempty(globals))), 0, 'blue')];
                    return;
                end

                if isempty(labels), nLabelTargets = 0; elseif strcmp(mode,'classification'), nLabelTargets = 1; else, nLabelTargets = size(labels,2); end
                IO.Y = double(M);
                IO.ID = axisIDs(:); IO.s_ID = IO.ID;
                IO.featnames = featureNames(:)'; IO.s_featnames = IO.featnames;
                if ~isempty(labels), IO.label = labels; IO.s_label = labels; IO.L = labels; end
                if ~isempty(covars), IO.covars = double(covars); IO.covnames = covNames(:)'; end
                audit.nFinalCases = size(finalIDs,1);
                audit.nFinalFeatures = size(M,2);
                audit.nFinalLabelTargets = nLabelTargets;
                audit.nFinalCovariates = size(covars,2);
                audit.caseAxis.nFinalCases = size(finalIDs,1);
                IO.dataIOAudit = audit;
                sourceKeys = cellfun(@(b) NMDataIOImportTools.variableRefSourceKey(IO,b.ref), allBlocks, 'UniformOutput', false);
                sourceKeys = unique(sourceKeys, 'stable');
                anchorRows = size(featureBlocks{1}.data,1);
                if strcmp(alignMode,'row_order')
                    axisSource = 'row_order';
                    excludedAnchorRows = 0;
                else
                    anchorReport = keyPlanRowMaps{featureBlocks{1}.keyPlanIndex}.report;
                    excludedAnchorRows = anchorRows - double(NMDataIOImportTools.fieldOr(anchorReport,'nMatchedIncomingCases',0));
                end
                audit.status = 'complete';
                audit.nFinalCases = size(IO.Y,1);
                audit.nFinalFeatures = size(IO.Y,2);
                audit.nFinalLabelTargets = nLabelTargets;
                audit.nFinalCovariates = size(covars,2);
                audit.caseAxis.nFinalCases = size(finalIDs,1);
                IO.dataIOAudit = audit;
                IO.variableMaterialization = struct('alignmentMode',alignMode,'caseAxisPolicy',NMDataIOImportTools.fieldOr(IO,'caseAxisPolicy','complete_case'), ...
                    'axisSource',axisSource,'sourceKeys',{sourceKeys},'nSourceRows',anchorRows,'nAlignedRows',size(finalIDs,1), ...
                    'caseKeyComponentCount',NMDataIOImportTools.caseKeyComponentCount(finalIDs),'excludedAnchorRows',excludedAnchorRows,'nFeatureBlocks',numel(featureBlocks), ...
                    'nLabelBlocks',numel(labelBlocks),'nCovariateBlocks',numel(covBlocks),'nCaseKeyPlans',numel(keyPlanKeys),'numericSourceIssues',{numericIssues});
                messages = [messages; NMDataIOMessageTools.make('info', false, 'variableRoleMaterialization', ...
                    sprintf('Prepared %g case(s), %g feature(s), %g label target(s), and %g covariate(s) from the selected inputs.', size(IO.Y,1), size(IO.Y,2), nLabelTargets, size(covars,2)), 0, 'blue')];
            catch ME
                audit.status = 'blocked';
                audit.blockingIdentifier = ME.identifier;
                audit.blockingMessage = ME.message;
                IO.dataIOAudit = audit;
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'variableRoleMaterialization')];
            end
        end

        function audit = emptyDataIOAudit(IO)
            % EMPTYDATAIOAUDIT  Create the non-authoritative provenance/attrition ledger for one materialization.
            sourceType = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType',''))));
            audit = struct('schemaVersion',1,'sourceType',sourceType,'status','materializing', ...
                'alignmentMode','','caseAxisPolicy','','axisSource','','sourceObjects',{cell(0,1)},'blocks',{cell(0,1)}, ...
                'caseAxis',struct('policy','','source','','nFinalCases',0,'steps',{cell(0,1)}), ...
                'nFinalCases',0,'nFinalFeatures',0,'nFinalLabelTargets',0,'nFinalCovariates',0, ...
                'blockingIdentifier','','blockingMessage','');
        end

        function [audit, blockIndex] = registerDataIOAuditBlock(audit, IO, ref, role, data, sourceRows, sourceAudit, conversionFailures)
            % REGISTERDATAIOAUDITBLOCK  Record one scientific source block and its object-level filter provenance.
            if nargin < 8 || isempty(conversionFailures), conversionFailures = 0; end
            sourceKey = NMDataIOImportTools.variableRefSourceKey(IO, ref);
            sourceLabel = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'sourceLabel',''));
            if isempty(sourceLabel), sourceLabel = sourceKey; end
            if isstruct(sourceAudit) && ~isempty(fieldnames(sourceAudit))
                objectKey = [NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(sourceAudit,'sourceType','')) '|' ...
                    NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(sourceAudit,'sourcePath','')) '|' ...
                    NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(sourceAudit,'sourceObject','')) '|' ...
                    NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(sourceAudit,'sourceName',''))];
                existing = [];
                if iscell(audit.sourceObjects) && ~isempty(audit.sourceObjects)
                    keys = cellfun(@(x) NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(x,'sourceKey','')), audit.sourceObjects, 'UniformOutput', false);
                    existing = find(strcmp(keys,objectKey),1);
                end
                objectRecord = sourceAudit;
                objectRecord.sourceKey = objectKey;
                if isempty(existing), audit.sourceObjects{end+1,1} = objectRecord; else, audit.sourceObjects{existing} = objectRecord; end
            end
            [nFinite,nNaN,nInf] = NMDataIOImportTools.numericAuditCounts(data);
            block = struct('index',numel(audit.blocks)+1,'role',char(role),'name',NMDataIOImportTools.variableRefName(ref), ...
                'sourceKey',sourceKey,'sourceLabel',sourceLabel,'nSourceRows',size(data,1),'nColumns',size(data,2), ...
                'nKeyRows',0,'nUniqueKeys',0,'nDuplicateTuples',0,'nDuplicateRows',0,'duplicateKeys',struct([]), ...
                'nFiniteSourceValues',nFinite,'nSourceNaNValues',nNaN,'nSourceInfValues',nInf, ...
                'nConversionFailures',double(conversionFailures),'nAlignedRows',0,'nMatchedReferenceCases',0, ...
                'nMatchedSourceCases',0,'nMissingReferenceCases',0,'nUnmatchedSourceCases',0, ...
                'nFiniteAlignedValues',NaN,'nAlignedNaNValues',NaN,'nAlignedInfValues',NaN,'nAlignmentInducedNaNValues',0, ...
                'sourceRowsPreserved',~isempty(sourceRows));
            audit.blocks{end+1,1} = block;
            blockIndex = numel(audit.blocks);
        end

        function audit = updateDataIOAuditBlockKeys(audit, blockIndex, duplicateReport)
            % UPDATEDATAIOAUDITBLOCKKEYS  Attach one already-computed key-cardinality report to a source block.
            if blockIndex < 1 || blockIndex > numel(audit.blocks), return; end
            audit.blocks{blockIndex}.nKeyRows = double(duplicateReport.nRows);
            audit.blocks{blockIndex}.nUniqueKeys = double(duplicateReport.nUniqueRows);
            audit.blocks{blockIndex}.nDuplicateTuples = double(duplicateReport.nDuplicateTuples);
            audit.blocks{blockIndex}.nDuplicateRows = double(duplicateReport.nDuplicateRows);
            audit.blocks{blockIndex}.duplicateKeys = duplicateReport.examples;
        end

        function audit = updateDataIOAuditBlockAlignment(audit, blockIndex, mapReport, alignedData, sourceData, allowMissing)
            % UPDATEDATAIOAUDITBLOCKALIGNMENT  Record exact source-to-final-axis coverage and missingness introduced by projection.
            if blockIndex < 1 || blockIndex > numel(audit.blocks), return; end
            nRef = double(NMDataIOImportTools.fieldOr(mapReport,'nReferenceCases',size(alignedData,1)));
            nIncoming = double(NMDataIOImportTools.fieldOr(mapReport,'nIncomingCases',size(sourceData,1)));
            nMatchedRef = double(NMDataIOImportTools.fieldOr(mapReport,'nMatchedReferenceCases',nRef));
            nMatchedIncoming = double(NMDataIOImportTools.fieldOr(mapReport,'nMatchedIncomingCases',min(nIncoming,nMatchedRef)));
            [nFinite,nNaN,nInf] = NMDataIOImportTools.numericAuditCounts(alignedData);
            b = audit.blocks{blockIndex};
            b.nAlignedRows = size(alignedData,1);
            b.nMatchedReferenceCases = nMatchedRef;
            b.nMatchedSourceCases = nMatchedIncoming;
            b.nMissingReferenceCases = max(0,nRef-nMatchedRef);
            b.nUnmatchedSourceCases = max(0,nIncoming-nMatchedIncoming);
            b.nFiniteAlignedValues = nFinite;
            b.nAlignedNaNValues = nNaN;
            b.nAlignedInfValues = nInf;
            if allowMissing, b.nAlignmentInducedNaNValues = b.nMissingReferenceCases * size(sourceData,2); else, b.nAlignmentInducedNaNValues = 0; end
            audit.blocks{blockIndex} = b;
        end

        function audit = markDataIOAuditBlockRowOrder(audit, blockIndex, data)
            % MARKDATAIOAUDITBLOCKROWORDER  Record the explicit-row-order path without inventing key matching.
            if blockIndex < 1 || blockIndex > numel(audit.blocks), return; end
            [nFinite,nNaN,nInf] = NMDataIOImportTools.numericAuditCounts(data);
            b = audit.blocks{blockIndex};
            b.nAlignedRows = size(data,1);
            b.nMatchedReferenceCases = size(data,1);
            b.nMatchedSourceCases = size(data,1);
            b.nFiniteAlignedValues = nFinite;
            b.nAlignedNaNValues = nNaN;
            b.nAlignedInfValues = nInf;
            audit.blocks{blockIndex} = b;
        end

        function audit = appendDataIOCaseAxisStep(audit, operation, role, blockName, nBefore, nIncoming, nAfter)
            % APPENDDATAIOCASEAXISSTEP  Log one already-executed axis intersection/union/seed operation.
            step = struct('order',numel(audit.caseAxis.steps)+1,'operation',char(operation),'role',char(role), ...
                'blockName',char(blockName),'nBefore',double(nBefore),'nIncoming',double(nIncoming),'nAfter',double(nAfter), ...
                'nRemoved',max(0,double(nBefore)-double(nAfter)),'nAdded',max(0,double(nAfter)-double(nBefore)));
            audit.caseAxis.steps{end+1,1} = step;
        end

        function [nFinite,nNaN,nInf] = numericAuditCounts(data)
            % NUMERICAUDITCOUNTS  Count numeric finite/NaN/Inf cells without coercing text labels.
            nFinite = NaN; nNaN = NaN; nInf = NaN;
            if ~(isnumeric(data) || islogical(data)), return; end
            x = double(data);
            nFinite = double(nnz(isfinite(x)));
            nNaN = double(nnz(isnan(x)));
            nInf = double(nnz(isinf(x)));
        end

        function audit = dataIOAuditFromIO(IO)
            % DATAIOAUDITFROMIO  Return the materialization audit ledger when the current producer created one.
            audit = NMDataIOImportTools.fieldOr(IO,'dataIOAudit',struct());
            if ~isstruct(audit), audit = struct(); end
        end

        function issue = numericSourceIssue(ref, report, filteredSourceRows)
            % numericSourceIssue  Bind one numeric-conversion report to its exact table-file provenance.
            if nargin < 3, filteredSourceRows = []; end
            detail = NMDataIOImportTools.fieldOr(report,'detail',struct());
            rows = double(NMDataIOImportTools.fieldOr(detail,'rows',[])); rows = rows(:)';
            values = NMDataIOImportTools.fieldOr(detail,'values',{});
            if isstring(values), values = cellstr(values(:)'); elseif ~iscell(values), values = cellstr(string(values(:)')); end
            nOffending = double(NMDataIOImportTools.fieldOr(detail,'nOffending',numel(rows)));
            if isempty(rows) && isfinite(NMDataIOImportTools.fieldOr(detail,'row',NaN))
                rows = double(detail.row); values = {NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(detail,'value',''))};
                nOffending = max(1,nOffending);
            end
            maxReported = min(numel(rows), 50);
            headerRow = double(NMDataIOImportTools.fieldOr(ref,'headerRow',0));
            sourceRows = rows;
            if ~isempty(filteredSourceRows) && all(rows >= 1) && all(rows <= numel(filteredSourceRows))
                sourceRows = double(filteredSourceRows(rows));
            end
            issue = struct('role',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(report,'role','Source')), ...
                'sourcePath',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'sourcePath','')), ...
                'sourceObject',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'sourceObject','')), ...
                'sourceLabel',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'sourceLabel','')), ...
                'columnName',NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'columnName',NMDataIOImportTools.variableRefName(ref))), ...
                'headerRow',headerRow,'nOffending',nOffending,'rows',rows(1:maxReported), ...
                'sourceRows',sourceRows(1:maxReported)+headerRow,'values',{values(1:min(maxReported,numel(values)))},'nReported',maxReported, ...
                'mapperEnabled',logical(NMDataIOImportTools.fieldOr(report,'mapperEnabled',false)), ...
                'nMapped',double(NMDataIOImportTools.fieldOr(NMDataIOImportTools.fieldOr(report,'nanMapper',struct()),'nMapped',0)), ...
                'mapperTokens',{NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(report,'mapperTokens',{}))});
        end

        function messages = numericSourceIssueMessages(IO)
            % numericSourceIssueMessages  Expose recoverable Preview substitutions as blocking cell-level diagnostics.
            messages = NMDataIOMessageTools.emptyMessages();
            vm = NMDataIOImportTools.fieldOr(IO,'variableMaterialization',struct());
            issues = NMDataIOImportTools.fieldOr(vm,'numericSourceIssues',[]);
            if isempty(issues) || ~isstruct(issues), return; end
            for i = 1:numel(issues)
                q = issues(i);
                sourceLabel = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(q,'sourceLabel',''));
                if isempty(sourceLabel), sourceLabel = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(q,'sourcePath','table source')); end
                examples = {};
                rows = NMDataIOImportTools.fieldOr(q,'sourceRows',[]); values = NMDataIOImportTools.fieldOr(q,'values',{});
                for j = 1:min(numel(rows),numel(values))
                    examples{end+1} = sprintf('row %g = ''%s''', rows(j), NMDataIOImportTools.asChar(values{j})); %#ok<AGROW>
                end
                exampleText = '';
                if ~isempty(examples), exampleText = [' Offending source cells: ' strjoin(examples, '; ') '.']; end
                nOffending = double(NMDataIOImportTools.fieldOr(q,'nOffending',numel(rows)));
                nReported = double(NMDataIOImportTools.fieldOr(q,'nReported',numel(rows)));
                if nOffending > nReported, exampleText = sprintf('%s Showing the first %g of %g offending cells.', exampleText, nReported, nOffending); end
                if logical(NMDataIOImportTools.fieldOr(q,'mapperEnabled',false))
                    toks = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(q,'mapperTokens',{}));
                    toks = cellfun(@(x) NMDataIOImportTools.asChar(x), toks, 'UniformOutput', false); toks = toks(~cellfun(@isempty,toks));
                    if numel(toks) > 12, toks = [toks(1:12) {'...'}]; end
                    tokenText = '';
                    if ~isempty(toks), tokenText = ['; tokens: ' strjoin(toks, ', ')]; end
                    mapperText = sprintf(' Missing-value conversion mapped %g configured text value occurrence(s) to NaN%s.', ...
                        double(NMDataIOImportTools.fieldOr(q,'nMapped',0)), tokenText);
                else
                    mapperText = ' Missing-value text conversion is disabled.';
                end
                txt = sprintf('%s column ''%s'' in %s contains %g unresolved non-numeric value(s).%s%s Preview temporarily treats these cells as missing so diagnostics and QC can complete. Commit remains blocked. Correct the source values, leave them genuinely missing, or add the corresponding text to Missing-value tokens.', ...
                    NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(q,'role','Source')), ...
                    NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(q,'columnName','')), sourceLabel, nOffending, exampleText, mapperText);
                messages(end+1,1) = NMDataIOMessageTools.make('danger', true, 'tableNumericConversion', txt, 1, 'red*'); %#ok<AGROW>
            end
        end

        function refs = variableRoleRefs(IO, role)
            refs = {};
            if ~isstruct(IO) || ~isfield(IO,'variableRoles') || ~isstruct(IO.variableRoles) || ~isfield(IO.variableRoles,role), return; end
            raw = IO.variableRoles.(role);
            if isempty(raw), return; end
            if iscell(raw)
                items = raw(:);
            elseif isstruct(raw)
                items = arrayfun(@(x) x, raw(:), 'UniformOutput', false);
            elseif ischar(raw) || isstring(raw)
                items = cellstr(string(raw(:)));
            else
                error('NMDataIOImportTools:variableRoleContract', 'Variable role %s has an unsupported reference representation.', role);
            end
            for i = 1:numel(items)
                item = items{i};
                if ischar(item) || isstring(item), item = struct('name',char(string(item))); end
                if ~isstruct(item) || isempty(NMDataIOImportTools.variableRefName(item))
                    error('NMDataIOImportTools:variableRoleReference', 'Variable role %s contains an invalid reference.', role);
                end
                refs{end+1,1} = item; %#ok<AGROW>
            end
        end

        function policy = normalizeCaseAxisPolicy(value)
            % NORMALIZECASEAXISPOLICY  Validate the first-container Case-ID axis policy.
            policy = lower(strtrim(char(string(value))));
            if isempty(policy), policy = 'complete_case'; end
            if ~ismember(policy, {'complete_case','target_anchored','feature_union'})
                error('NMDataIOImportTools:caseAxisPolicy', 'Unsupported Case-ID alignment policy: %s.', policy);
            end
        end

        function policy = trainingCaseAxisPolicy(NM)
            % TRAININGCASEAXISPOLICY  Read the persisted policy that established NM.cases.
            policy = 'complete_case';
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor), return; end
            fallback = '';
            for i = 1:numel(NM.datadescriptor)
                dd = NM.datadescriptor{i};
                if ~isstruct(dd) || ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings), continue; end
                S = dd.input_settings;
                if ~isfield(S,'caseAxisPolicy') || isempty(S.caseAxisPolicy), continue; end
                candidate = NMDataIOImportTools.normalizeCaseAxisPolicy(S.caseAxisPolicy);
                if isempty(fallback), fallback = candidate; end
                if isfield(S,'caseAxisEstablishedByImport') && ~isempty(S.caseAxisEstablishedByImport) && logical(S.caseAxisEstablishedByImport)
                    policy = candidate;
                    return;
                end
            end
            if ~isempty(fallback), policy = fallback; end
        end

        function assertBlockCaseKeysUniqueOnAxis(block, finalIDs, duplicateReport)
            % ASSERTBLOCKCASEKEYSUNIQUEONAXIS  Reject ambiguity only among source rows relevant to the final Case-ID axis.
            if duplicateReport.nDuplicateTuples == 0, return; end
            ids = NMDataIOImportTools.caseKeyRows(NMDataIOImportTools.fieldOr(block,'ids',{}));
            finalIDs = NMDataIOImportTools.caseKeyRows(finalIDs);
            opts = struct('idMappingMode','auto','mappingApproved',true);
            [relevant, ~] = NMDataIOImportTools.resolveCaseRowMap(ids, finalIDs, opts);
            sourceRows = NMDataIOImportTools.fieldOr(block,'keySourceRows',[]);
            if ~isempty(sourceRows) && numel(sourceRows) == numel(ids), sourceRows = sourceRows(relevant); else, sourceRows = []; end
            keyRefs = NMDataIOImportTools.fieldOr(block,'keyRefs',{});
            ref = NMDataIOImportTools.fieldOr(block,'ref',struct());
            NMDataIOImportTools.assertUniqueCaseKeyRows(ids(relevant), 'NMDataIOImportTools:duplicatePSN', ...
                sprintf('Case-ID combinations that match the current Case-ID list must be unique in input %s.', NMDataIOImportTools.variableRefName(ref)), ...
                sourceRows, keyRefs);
        end

        function rows = uniqueCaseKeyRowsStable(rows)
            % UNIQUECASEKEYROWSSTABLE  Build a set-like axis candidate without masking later source ambiguity checks.
            rows = NMDataIOImportTools.caseKeyRows(rows);
            if isempty(rows), return; end
            keyMatrix = NMDataIOImportTools.caseKeyStringMatrix(rows);
            [~, first] = unique(keyMatrix,'rows','stable');
            rows = rows(sort(first));
        end

        function ids = intersectIdsStable(ids, other)
            % INTERSECTIDSSTABLE  Intersect scalar or composite case-key rows through the shared matcher.
            ids = NMDataIOImportTools.caseKeyRows(ids);
            other = NMDataIOImportTools.caseKeyRows(other);
            if isempty(ids), ids = cell(0,1); return; end
            if isempty(other), ids = cell(0,1); return; end
            opts = struct('idMappingMode','auto','mappingApproved',true);
            [matched, loc] = NMDataIOImportTools.resolveCaseRowMap(ids, other, opts);
            kept = ids(matched);
            if NMDataIOImportTools.caseKeyComponentCount(kept) == 1
                incoming = other(loc(matched));
                for i = 1:numel(kept)
                    kept{i} = NMDataIOImportTools.canonicalCaseId(kept{i}, incoming{i});
                end
            end
            ids = kept;
        end

        function ids = unionIdsStable(ids, other)
            % UNIONIDSSTABLE  Append incoming scalar/composite keys not represented by the shared matcher.
            ids = NMDataIOImportTools.caseKeyRows(ids);
            other = NMDataIOImportTools.caseKeyRows(other);
            if isempty(ids), ids = other; return; end
            if isempty(other), return; end
            opts = struct('idMappingMode','auto','mappingApproved',true);
            [matched, loc] = NMDataIOImportTools.resolveCaseRowMap(ids, other, opts);
            if NMDataIOImportTools.caseKeyComponentCount(ids) == 1
                matchedRows = find(matched);
                for i = 1:numel(matchedRows)
                    r = matchedRows(i);
                    ids{r} = NMDataIOImportTools.canonicalCaseId(ids{r}, other{loc(r)});
                end
            end
            usedIncoming = unique(loc(matched));
            ids = [ids; other(~ismember((1:numel(other))', usedIncoming(:)))];
        end

        function id = canonicalCaseId(a, b)
            % CANONICALCASEID  Choose a deterministic representative for structurally equivalent IDs.
            pair = sort({char(string(a)), char(string(b))});
            id = pair{1};
        end

        function [out, mapReport] = alignBlockRows(data, sourceIds, targetIds, allowMissing, rowMap)
            % ALIGNBLOCKROWS  Project a source block onto a scalar/composite target case-key axis.
            sourceIds = NMDataIOImportTools.caseKeyRows(sourceIds);
            targetIds = NMDataIOImportTools.caseKeyRows(targetIds);
            if nargin >= 5 && isstruct(rowMap) && isfield(rowMap,'matched') && isfield(rowMap,'loc') && isfield(rowMap,'report')
                tf = logical(rowMap.matched(:)); loc = double(rowMap.loc(:)); mapReport = rowMap.report;
                if numel(tf) ~= numel(targetIds) || numel(loc) ~= numel(targetIds)
                    error('NMDataIOImportTools:caseRowMapSize', 'A retained source-block row map does not match the current target Case-ID axis.');
                end
            else
                opts = struct('idMappingMode','auto','mappingApproved',true);
                [tf, loc, mapReport] = NMDataIOImportTools.resolveCaseRowMap(targetIds, sourceIds, opts);
            end
            if ~isempty(targetIds) && ~isempty(sourceIds) && ~any(tf)
                error('NMDataIOImportTools:sourceBlockNoOverlap', ...
                    'No cases could be matched between the selected input and the current Case-ID list. Check the selected Case-ID key(s).');
            end
            if ~allowMissing && any(~tf)
                error('NMDataIOImportTools:sourceBlockMissingCases', 'A required input is missing %g case(s) from the current Case-ID list.', nnz(~tf));
            end
            if allowMissing
                if ~(isnumeric(data) || islogical(data))
                    error('NMDataIOImportTools:missingTargetType', 'Missing-value alignment is supported only for numeric/logical regression targets.');
                end
                out = nan(numel(targetIds), size(data,2));
                if any(tf), out(tf,:) = double(data(loc(tf),:)); end
            else
                out = data(loc,:);
            end
        end

        function messages = sourceBlockMapMessage(blockRef, mapReport)
            % SOURCEBLOCKMAPMESSAGE  Report structural or sparse Case-ID mapping for one source block.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(mapReport), return; end
            blockName = NMDataIOImportTools.variableRefName(blockRef);
            sourceLabel = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(blockRef,'sourceLabel',''));
            if NMDataIOImportTools.isCanonicalTabularColumnRef(blockRef) && ~isempty(sourceLabel)
                context = sprintf('Source %s', sourceLabel);
            else
                context = sprintf('Input %s', blockName);
            end
            messages = [messages; NMDataIOImportTools.caseCoverageMessage(context, mapReport, 'variableRoleCaseAlignment')];
            if logical(NMDataIOImportTools.fieldOr(mapReport,'mappingApproved',false))
                exampleClause = NMDataIOImportTools.sharedKeyExampleClause(mapReport);
                messages = [messages; NMDataIOMessageTools.make('info', false, 'variableRoleCaseAlignment', ...
                    sprintf('%s was matched by the selected Case-ID key rather than by exact full Case-ID text.%s Every match was unique, and the rows were aligned to the modality case list.', ...
                    context, exampleClause), 0, 'blue')];
            end
        end

        function messages = caseCoverageMessage(context, mapReport, code)
            % CASECOVERAGEMESSAGE  Warn when at least half of either compared case set is unmatched.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(mapReport) || ~logical(NMDataIOImportTools.fieldOr(mapReport,'lowCoverage',false)), return; end
            nRef = double(NMDataIOImportTools.fieldOr(mapReport,'nReferenceCases',0));
            nIncoming = double(NMDataIOImportTools.fieldOr(mapReport,'nIncomingCases',0));
            nRefMatched = double(NMDataIOImportTools.fieldOr(mapReport,'nMatchedReferenceCases',0));
            nIncomingMatched = double(NMDataIOImportTools.fieldOr(mapReport,'nMatchedIncomingCases',0));
            if nRefMatched <= 0 || nRef <= 0 || nIncoming <= 0, return; end
            refPct = 100 * nRefMatched / nRef;
            incomingPct = 100 * nIncomingMatched / nIncoming;
            messages = NMDataIOMessageTools.make('warn', false, code, ...
                sprintf('%s has low Case-ID overlap: %g/%g existing case(s) (%.1f%%) and %g/%g selected-source case(s) (%.1f%%) matched. At least 50%% of one case set could not be matched. Verify the Case-ID mapping and that the two sources are intended to contain the same cases.', ...
                context, nRefMatched, nRef, refPct, nIncomingMatched, nIncoming, incomingPct), 2, 'SystemCommands');
        end

        function names = resolveLabelDefinitionNames(IO, mode)
            % RESOLVELABELDEFINITIONNAMES  Resolve user-defined class/target names from one persisted authority.
            names = {};
            def = NMDataIOImportTools.fieldOr(IO,'labelDefinition',struct());
            if isstruct(def)
                ref = NMDataIOImportTools.fieldOr(def,'nameSourceRef',[]);
                if isstruct(ref) && ~isempty(NMDataIOImportTools.variableRefName(ref))
                    names = NMDataIOImportTools.nameCell(NMDataIOImportTools.resolveVariableRef(IO, ref));
                else
                    names = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(def,'manualNames',{}));
                end
            end
            if isempty(names) && strcmpi(mode,'regression')
                spec = NMDataIOImportTools.fieldOr(IO,'labelNamesSpec', ...
                    NMDataIOImportTools.fieldOr(IO,'desc_labels',{}));
                source = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'labelNamesSource','manual'))));
                if any(strcmp(source, {'workspace','variable','var'})) && ...
                        (ischar(spec) || (isstring(spec) && isscalar(spec)))
                    name = strtrim(NMDataIOImportTools.asChar(spec));
                    if ~isempty(name) && ~strcmp(name,'?') && evalin('base', sprintf('exist(''%s'',''var'')', name))
                        spec = evalin('base', name);
                    end
                elseif (ischar(spec) || (isstring(spec) && isscalar(spec))) && ...
                        any(strcmp(strtrim(NMDataIOImportTools.asChar(spec)), {'','?'}))
                    spec = {};
                end
                names = NMDataIOImportTools.asCaseCell(spec);
            end
            names = names(:)';
            names = cellfun(@(x) strtrim(char(string(x))), names, 'UniformOutput', false);
            if any(cellfun(@isempty,names))
                error('NMDataIOImportTools:labelDefinitionName', '%s name definitions must not contain empty entries.', mode);
            end
        end

        function name = variableRefName(ref)
            name = '';
            if isstruct(ref)
                if isfield(ref,'name') && ~isempty(ref.name), name = char(string(ref.name));
                elseif isfield(ref,'id') && ~isempty(ref.id), name = char(string(ref.id)); end
            elseif ischar(ref) || isstring(ref)
                name = char(string(ref));
            end
        end

        function tf = isCanonicalTabularColumnRef(ref)
            % isCanonicalTabularColumnRef  True for column refs whose scientific names come from tabular headers.
            st = lower(char(string(NMDataIOImportTools.fieldOr(ref,'sourceType',''))));
            tf = ismember(st, {'tablefile','tablevar'}) || strcmp(st,'database');
        end

        function key = variableRefSourceKey(IO, ref)
            st = lower(char(string(NMDataIOImportTools.fieldOr(ref,'sourceType',NMDataIOImportTools.fieldOr(IO,'sourceType','workspace')))));
            if strcmp(st,'matfile')
                files = NMDataIOImportTools.matSourceFiles(IO);
                pathValue = char(string(NMDataIOImportTools.fieldOr(ref,'sourcePath','')));
                if isempty(pathValue)
                    if numel(files) ~= 1
                        error('NMDataIOImportTools:missingMatProvenance', 'MAT-file variable %s is missing its source-file reference.', NMDataIOImportTools.variableRefName(ref));
                    end
                    pathValue = files{1};
                end
                if isempty(files) || ~any(strcmp(files,pathValue))
                    error('NMDataIOImportTools:staleMatVariableSource', ...
                        'MAT-file variable %s refers to a file that is not part of the current MAT-file source definition: %s', ...
                        NMDataIOImportTools.variableRefName(ref), pathValue);
                end
                key = pathValue;
            elseif strcmp(st,'tablefile')
                pathValue = char(string(NMDataIOImportTools.fieldOr(ref,'sourcePath','')));
                objectValue = char(string(NMDataIOImportTools.fieldOr(ref,'sourceObject','')));
                if isempty(pathValue), error('NMDataIOImportTools:missingTableProvenance','Table column %s is missing its source-file reference.',NMDataIOImportTools.variableRefName(ref)); end
                key = ['tablefile|' pathValue '|' objectValue];
            elseif strcmp(st,'tablevar')
                tableName = char(string(NMDataIOImportTools.fieldOr(ref,'sourceName','')));
                tables = NMDataIOImportTools.fieldOr(IO,'tableVariables',{});
                if ischar(tables) || isstring(tables), tables=cellstr(string(tables(:))); end
                if isempty(tableName), error('NMDataIOImportTools:missingTableProvenance','MATLAB-table column %s is missing its source-table reference.',NMDataIOImportTools.variableRefName(ref)); end
                if ~isempty(tables) && ~any(strcmp(cellfun(@(x) char(string(x)),tables(:),'UniformOutput',false),tableName))
                    error('NMDataIOImportTools:staleTableVariableSource','MATLAB-table column %s refers to a table that is no longer part of the current source definition: %s',NMDataIOImportTools.variableRefName(ref),tableName);
                end
                key = ['tablevar|' tableName];
            elseif strcmp(st,'database')
                key = NMDataIOStateTools.variableRefSourceIdentity(ref, IO);
            else
                key = 'workspace';
            end
        end

        function [v, sourceRows, sourceAudit] = resolveVariableRef(IO, ref, sourceObjects)
            if nargin < 3, sourceObjects = struct([]); end
            sourceRows = []; sourceAudit = struct();
            name = NMDataIOImportTools.variableRefName(ref);
            if isempty(name), error('NMDataIOImportTools:missingVariableName', 'Variable reference has no name.'); end
            st = lower(char(string(NMDataIOImportTools.fieldOr(ref,'sourceType',NMDataIOImportTools.fieldOr(IO,'sourceType','workspace')))));
            if strcmp(st,'matfile')
                filePath = NMDataIOImportTools.variableRefSourceKey(IO, ref);
                if exist(filePath,'file') ~= 2, error('NMDataIOImportTools:matFileNotFound', 'MAT-file does not exist: %s', filePath); end
                W = whos('-file', filePath, name);
                if isempty(W), error('NMDataIOImportTools:matVariableNotFound', 'Variable %s is not present in MAT-file %s.', name, filePath); end
                S = load(filePath, name); v = S.(name);
            elseif ismember(st,{'tablefile','tablevar'}) || strcmp(st,'database')
                [v, sourceRows, sourceAudit] = NMDataIOTableReadTools.readSourceRef(IO, ref, sourceObjects);
            else
                v = NMWorkspaceTools.resolve(name, 'base');
            end
        end

        function files = matSourceFiles(IO)
            files = {};
            if isstruct(IO) && isfield(IO,'matFiles') && ~isempty(IO.matFiles)
                raw = IO.matFiles;
                if ischar(raw), files = {raw}; elseif isstring(raw), files = cellstr(raw(:)); elseif iscell(raw), files = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false); end
            end
            if isempty(files) && isstruct(IO) && isfield(IO,'M_edit') && ~NMDataIOImportTools.isUnknown(IO.M_edit,'?')
                raw = char(string(IO.M_edit)); files = regexp(raw, '\r?\n', 'split'); files = files(~cellfun(@isempty,strtrim(files)));
            end
            files = unique(files(:)', 'stable');
        end

        function key = sourceBlockCaseKeyIdentity(IO, blockRef)
            % SOURCEBLOCKCASEKEYIDENTITY  Deterministic identity for one source object plus its ordered Case-ID key.
            keyRefs = NMDataIOStateTools.roleRefCell(NMDataIOImportTools.fieldOr(blockRef,'caseKeyRefs',{}));
            keySources = cell(1,numel(keyRefs)); keyNames = cell(1,numel(keyRefs));
            for k = 1:numel(keyRefs)
                keySources{k} = NMDataIOImportTools.variableRefSourceKey(IO,keyRefs{k});
                keyNames{k} = NMDataIOImportTools.variableRefName(keyRefs{k});
            end
            key = jsonencode(struct('sourceKey',NMDataIOImportTools.variableRefSourceKey(IO,blockRef), ...
                'caseKeySources',{keySources},'caseKeyNames',{keyNames}));
        end

        function blocks = uniqueCaseKeyPlanBlocks(blocks)
            % UNIQUECASEKEYPLANBLOCKS  Retain one representative block for each already-materialized Case-ID key plan.
            if isempty(blocks), return; end
            planIndex = cellfun(@(b) double(NMDataIOImportTools.fieldOr(b,'keyPlanIndex',0)), blocks);
            [~, first] = unique(planIndex,'stable');
            blocks = blocks(sort(first));
        end

        function [ids, sourceRows] = resolveSourceBlockCaseKeys(IO, blockRef, sourceObjects)
            % RESOLVESOURCEBLOCKCASEKEYS  Materialize one ordered scalar/composite source-block key.
            if nargin < 3, sourceObjects = struct([]); end
            if ~isstruct(blockRef) || ~isfield(blockRef,'caseKeyRefs') || isempty(blockRef.caseKeyRefs)
                error('NMDataIOImportTools:missingPSNRole', ...
                    'Input %s has no Case-ID key assignment.', NMDataIOImportTools.variableRefName(blockRef));
            end
            keyRefs = NMDataIOStateTools.roleRefCell(blockRef.caseKeyRefs);
            components = cell(numel(keyRefs),1);
            nRows = []; sourceRows = [];
            for k = 1:numel(keyRefs)
                ref = keyRefs{k};
                if ~isstruct(ref) || isempty(NMDataIOImportTools.variableRefName(ref))
                    error('NMDataIOImportTools:caseKeyReference', ...
                        'Input %s contains an invalid Case-ID key column.', NMDataIOImportTools.variableRefName(blockRef));
                end
                [componentSource, componentRows] = NMDataIOImportTools.resolveVariableRef(IO, ref, sourceObjects);
                component = NMDataIOImportTools.caseIdCell(componentSource);
                if isempty(nRows)
                    nRows = numel(component); sourceRows = componentRows(:);
                elseif ~isempty(sourceRows) && ~isempty(componentRows) && ~isequal(sourceRows,componentRows(:))
                    error('NMDataIOImportTools:caseKeySourceRows', ...
                        'The Case-ID key columns for input %s do not refer to the same filtered rows.', ...
                        NMDataIOImportTools.variableRefName(blockRef));
                end
                if numel(component) ~= nRows
                    error('NMDataIOImportTools:caseKeyComponentCount', ...
                        'Case-ID key component %s has %g row(s), but the first component has %g row(s).', ...
                        NMDataIOImportTools.variableRefName(ref), numel(component), nRows);
                end
                components{k} = component(:);
            end
            if numel(components) == 1
                ids = components{1};
            else
                ids = cell(nRows,1);
                for r = 1:nRows
                    tuple = cell(1,numel(components));
                    for k = 1:numel(components), tuple{k} = components{k}{r}; end
                    ids{r} = tuple;
                end
            end
        end

        function rows = caseKeyRows(v, decodeAxisEncoding)
            % CASEKEYROWS  Normalize scalar IDs or ordered tuple keys to one cell per case.
            % Encoded legacy-axis IDs are decoded only at an explicit boundary.
            if nargin < 2, decodeAxisEncoding = false; end
            if isempty(v), rows = cell(0,1); return; end
            if iscell(v) && isvector(v) && any(cellfun(@iscell,v(:)))
                rows = v(:);
                width = 0;
                for r = 1:numel(rows)
                    if ~iscell(rows{r})
                        error('NMDataIOImportTools:mixedCaseKeyAxis', ...
                            'The Case-ID list cannot mix single-column Case IDs with composite Case IDs.');
                    end
                    tuple = rows{r}(:)';
                    for c = 1:numel(tuple), tuple{c} = strtrim(char(string(tuple{c}))); end
                    if any(cellfun(@isempty,tuple))
                        error('NMDataIOImportTools:emptyCaseId', 'Case-ID key components must not be empty.');
                    end
                    if r == 1, width = numel(tuple); end
                    if numel(tuple) ~= width
                        error('NMDataIOImportTools:caseKeyTupleWidth', ...
                            'Composite Case IDs must contain the same number of key values in every row.');
                    end
                    rows{r} = tuple;
                end
                if width == 1
                    for r = 1:numel(rows), rows{r} = rows{r}{1}; end
                end
                return;
            end
            if iscell(v) && ~isvector(v)
                rows = cell(size(v,1),1);
                for r = 1:size(v,1)
                    tuple = cell(1,size(v,2));
                    for c = 1:size(v,2), tuple{c} = strtrim(char(string(v{r,c}))); end
                    if any(cellfun(@isempty,tuple))
                        error('NMDataIOImportTools:emptyCaseId', 'Case-ID key components must not be empty.');
                    end
                    rows{r} = tuple;
                end
                return;
            end
            scalar = NMDataIOImportTools.caseIdCell(v);
            if ~decodeAxisEncoding, rows = scalar(:); return; end

            tuplePrefix = 'NM2KEY:T:';
            scalarPrefix = 'NM2KEY:S:';
            isEscapedScalar = cellfun(@(x) strncmp(x,scalarPrefix,numel(scalarPrefix)), scalar);
            isTuple = cellfun(@(x) strncmp(x,tuplePrefix,numel(tuplePrefix)), scalar);
            if any(isEscapedScalar)
                if any(isTuple)
                    error('NMDataIOImportTools:mixedCaseKeyAxis', ...
                        'The saved Case-ID list cannot mix single-column Case IDs with composite Case IDs.');
                end
                for r = find(isEscapedScalar(:))'
                    payload = jsondecode(scalar{r}(numel(scalarPrefix)+1:end));
                    if ~(ischar(payload) || (isstring(payload) && isscalar(payload)))
                        error('NMDataIOImportTools:caseKeyScalarEncoding', 'Encoded scalar Case-ID %g is invalid.', r);
                    end
                    scalar{r} = char(string(payload));
                end
                rows = scalar(:);
                return;
            end
            if ~any(isTuple), rows = scalar(:); return; end
            if ~all(isTuple)
                % Composite axes written by NM2 are uniformly tuple-encoded. A
                % mixed set is therefore an ordinary scalar legacy axis.
                rows = scalar(:);
                return;
            end
            decoded = cell(numel(scalar),1);
            width = 0;
            for r = 1:numel(scalar)
                try
                    payload = jsondecode(scalar{r}(numel(tuplePrefix)+1:end));
                catch ME
                    error('NMDataIOImportTools:caseKeyTupleEncoding', ...
                        'Composite Case ID %g is invalid: %s', r, ME.message);
                end
                parts = NMDataIOImportTools.asCaseCell(payload);
                if r == 1, width = numel(parts); end
                if width < 2
                    error('NMDataIOImportTools:caseKeyTupleEncoding', ...
                        'Composite Case IDs must contain at least two key values.');
                end
                if numel(parts) ~= width
                    error('NMDataIOImportTools:caseKeyTupleEncoding', ...
                        'Composite Case IDs must contain the same number of key values in every row.');
                end
                decoded{r} = parts(:)';
            end
            rows = decoded;
        end

        function n = caseKeyComponentCount(rows)
            % CASEKEYCOMPONENTCOUNT  Return the ordered key width for scalar or composite case rows.
            rows = NMDataIOImportTools.caseKeyRows(rows);
            if isempty(rows), n = 0; return; end
            if iscell(rows{1}), n = numel(rows{1}); else, n = 1; end
        end

        function ids = caseKeyAxisIds(rows)
            % CASEKEYAXISIDS  Lower structured key tuples to deterministic reversible scalar axis IDs.
            rows = NMDataIOImportTools.caseKeyRows(rows);
            if NMDataIOImportTools.caseKeyComponentCount(rows) <= 1
                ids = rows;
                axisPrefix = 'NM2KEY:';
                for r = 1:numel(ids)
                    if strncmp(ids{r},axisPrefix,numel(axisPrefix)), ids{r} = ['NM2KEY:S:' jsonencode(ids{r})]; end
                end
                return;
            end
            ids = cell(numel(rows),1);
            for r = 1:numel(rows)
                ids{r} = ['NM2KEY:T:' jsonencode(rows{r})];
            end
        end

        function rows = sortCaseKeyRows(rows)
            % SORTCASEKEYROWS  Deterministically order scalar or composite Case-ID key rows.
            rows = NMDataIOImportTools.caseKeyRows(rows);
            if isempty(rows), return; end
            [~, order] = sortrows(NMDataIOImportTools.caseKeyStringMatrix(rows));
            rows = rows(order);
        end

        function assertUniqueCaseKeyRows(rows, errorId, message, sourceRows, keyRefs)
            % ASSERTUNIQUECASEKEYROWS  Reject duplicate keys using the shared structured duplicate report.
            if nargin < 4, sourceRows = []; end
            if nargin < 5, keyRefs = {}; end
            report = NMDataIOImportTools.caseKeyDuplicateReport(rows, sourceRows, keyRefs);
            if double(NMDataIOImportTools.fieldOr(report,'nDuplicateTuples',0)) < 1, return; end
            examples = NMDataIOImportTools.fieldOr(report,'examples',struct([]));
            lines = cell(1,numel(examples));
            for e = 1:numel(examples)
                rowText = arrayfun(@(x) sprintf('%g',x),double(examples(e).rows(:))','UniformOutput',false);
                lines{e} = sprintf('%s at %s %s',examples(e).keyText,report.rowLabel,strjoin(rowText,', '));
            end
            detail = sprintf(' Found %g duplicate Case-ID key combination(s) across %g row occurrence(s).', ...
                report.nDuplicateTuples,report.nDuplicateRows);
            if ~isempty(lines), detail = sprintf('%s\n%s',detail,strjoin(lines,newline)); end
            if report.nDuplicateTuples > numel(examples)
                detail = sprintf('%s\nShowing the first %g duplicate Case-ID key combination(s).',detail,numel(examples));
            end
            if ~isempty(report.sourceLabel), detail = sprintf('%s\nTable / sheet: %s.',detail,report.sourceLabel); end
            error(errorId,'%s%s',message,detail);
        end

        function report = caseKeyDuplicateReport(rows, sourceRows, keyRefs)
            % CASEKEYDUPLICATEREPORT  Describe duplicate scalar/composite key tuples without changing uniqueness semantics.
            if nargin < 2, sourceRows = []; end
            if nargin < 3, keyRefs = {}; end
            rows = NMDataIOImportTools.caseKeyRows(rows);
            refs = NMDataIOStateTools.roleRefCell(keyRefs);
            report = struct('schemaVersion',1,'nRows',numel(rows),'nUniqueRows',numel(rows), ...
                'nDuplicateTuples',0,'nDuplicateRows',0,'sourceLabel','','rowLabel','materialized row(s)','examples',struct([]));
            if isempty(rows), return; end
            keyMatrix = NMDataIOImportTools.caseKeyStringMatrix(rows);
            [~,~,group] = unique(keyMatrix,'rows');
            counts = accumarray(group,1);
            duplicateGroups = find(counts > 1);
            report.nUniqueRows = numel(counts);
            if isempty(duplicateGroups), return; end
            useSourceRows = ~isempty(sourceRows) && numel(sourceRows) == numel(rows);
            if useSourceRows, displayRows = double(sourceRows(:)); else, displayRows = (1:numel(rows))'; end
            keyNames = cell(1,size(keyMatrix,2));
            for c = 1:numel(keyNames)
                if c <= numel(refs), keyNames{c} = NMDataIOImportTools.variableRefName(refs{c}); end
                if isempty(keyNames{c}), keyNames{c} = sprintf('Key%g',c); end
            end
            headerRow = 0;
            if ~isempty(refs)
                report.sourceLabel = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(refs{1},'sourceLabel',''));
                if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(refs{1},'sourceType','')),'tablefile')
                    headerRow = double(NMDataIOImportTools.fieldOr(refs{1},'headerRow',0));
                end
            end
            if useSourceRows
                displayRows = displayRows + headerRow;
                report.rowLabel = 'source row(s)';
            end
            firstOccurrence = zeros(numel(duplicateGroups),1);
            for g = 1:numel(duplicateGroups), firstOccurrence(g) = find(group == duplicateGroups(g),1,'first'); end
            [~, order] = sort(firstOccurrence); duplicateGroups = duplicateGroups(order);
            maxExamples = min(20,numel(duplicateGroups));
            examples = repmat(struct('keyText','','rows',[]),maxExamples,1);
            for e = 1:maxExamples
                idx = find(group == duplicateGroups(e));
                parts = cell(1,size(keyMatrix,2));
                for c = 1:size(keyMatrix,2)
                    parts{c} = sprintf('%s=''%s''',keyNames{c},char(keyMatrix(idx(1),c)));
                end
                examples(e) = struct('keyText',sprintf('[%s]',strjoin(parts,', ')),'rows',double(displayRows(idx))');
            end
            report.nDuplicateTuples = numel(duplicateGroups);
            report.nDuplicateRows = sum(counts(duplicateGroups));
            report.examples = examples;
        end

        function [matched, loc] = exactCaseKeyRowMap(referenceRows, incomingRows)
            % EXACTCASEKEYROWMAP  Match structured key rows component-by-component without string concatenation.
            referenceRows = NMDataIOImportTools.caseKeyRows(referenceRows);
            incomingRows = NMDataIOImportTools.caseKeyRows(incomingRows);
            refWidth = NMDataIOImportTools.caseKeyComponentCount(referenceRows);
            inWidth = NMDataIOImportTools.caseKeyComponentCount(incomingRows);
            if ~isempty(referenceRows) && ~isempty(incomingRows) && refWidth ~= inWidth
                error('NMDataIOImportTools:caseKeyWidthMismatch', ...
                    'Case-key alignment cannot compare %g-component and %g-component keys.', refWidth, inWidth);
            end
            if isempty(referenceRows)
                matched = false(0,1); loc = zeros(0,1); return;
            end
            if isempty(incomingRows)
                matched = false(numel(referenceRows),1); loc = zeros(numel(referenceRows),1); return;
            end
            referenceMatrix = NMDataIOImportTools.caseKeyStringMatrix(referenceRows);
            incomingMatrix = NMDataIOImportTools.caseKeyStringMatrix(incomingRows);
            [matched, loc] = ismember(referenceMatrix, incomingMatrix, 'rows');
            matched = logical(matched(:));
            loc = double(loc(:));
        end

        function keyMatrix = caseKeyStringMatrix(rows)
            % CASEKEYSTRINGMATRIX  Expand one-cell-per-case keys to an N-by-K structured comparison matrix.
            rows = NMDataIOImportTools.caseKeyRows(rows);
            width = NMDataIOImportTools.caseKeyComponentCount(rows);
            keyMatrix = strings(numel(rows),width);
            if width == 0, return; end
            for r = 1:numel(rows)
                if width == 1
                    keyMatrix(r,1) = string(rows{r});
                else
                    tuple = rows{r};
                    for c = 1:width, keyMatrix(r,c) = string(tuple{c}); end
                end
            end
        end

        function ids = caseIdCell(v)
            % CASEIDCELL  Normalize one PSN/Case-ID source without changing row identity.
            % Character matrices are accepted because MATLAB commonly stores one
            % fixed-width subject identifier per row. Other representations must be
            % vectors so a matrix cannot be silently flattened into subject IDs.
            if ischar(v)
                ids = cellstr(v);
            elseif isstring(v)
                if ~isvector(v), error('NMDataIOImportTools:caseIdShape', 'PSN/Case-ID variable must be a vector or a character matrix with one identifier per row.'); end
                ids = cellstr(v(:));
            elseif iscategorical(v)
                if ~isvector(v), error('NMDataIOImportTools:caseIdShape', 'PSN/Case-ID variable must be a vector or a character matrix with one identifier per row.'); end
                ids = cellstr(string(v(:)));
            elseif isnumeric(v) || islogical(v)
                if ~isvector(v), error('NMDataIOImportTools:caseIdShape', 'PSN/Case-ID variable must be a vector or a character matrix with one identifier per row.'); end
                ids = cellstr(string(v(:)));
            elseif iscell(v)
                if ~isvector(v), error('NMDataIOImportTools:caseIdShape', 'PSN/Case-ID variable must be a vector or a character matrix with one identifier per row.'); end
                ids = cell(numel(v),1);
                for i = 1:numel(v), ids{i} = char(string(v{i})); end
            else
                error('NMDataIOImportTools:caseIdType', 'PSN/Case-ID variable must be a vector of text or scalar numeric identifiers, or a character matrix with one identifier per row.');
            end
            ids = strtrim(ids(:));
            if any(cellfun(@isempty,ids)), error('NMDataIOImportTools:emptyCaseId', 'PSN/Case-ID values must not be empty.'); end
        end

        function names = nameCell(v)
            if ischar(v), names = cellstr(v); elseif isstring(v), names = cellstr(v(:)); elseif iscategorical(v), names = cellstr(string(v(:)));
            elseif isnumeric(v) || islogical(v), names = cellstr(string(v(:)));
            elseif iscell(v)
                names = cell(numel(v),1); for i=1:numel(v), names{i}=char(string(v{i})); end
            else, error('NMDataIOImportTools:nameVariableType', 'Name variables must contain text-like or scalar numeric values.'); end
            names = names(:)';
        end

        function v = rowVariable(v, name)
            if ischar(v)
                v = cellstr(v);
            elseif isvector(v)
                if size(v,1) == 1 && numel(v) > 1
                    error('NMDataIOImportTools:rowOrientation', 'Variable %s is a row vector; subjects must be represented in rows.', name);
                end
                v = v(:);
            end
            if ndims(v) > 2
                error('NMDataIOImportTools:rowVariableDimensions', 'Variable %s must be a vector or two-dimensional matrix with subjects in rows.', name);
            end
        end

        function tf = hasResolvedMatrixPayload(IO)
            % HASRESOLVEDMATRIXPAYLOAD  Test whether IO already contains matrix data and case IDs.
            %
            %   tf = ... returns true when IO.Y is populated and an ID/s_ID vector is available.
            %   The predicate is used to bypass source rereading for already resolved payloads.
            tf = isstruct(IO) && isfield(IO,'Y') && ~isempty(IO.Y) && ...
                ((isfield(IO,'ID') && ~isempty(IO.ID)) || (isfield(IO,'s_ID') && ~isempty(IO.s_ID)));
        end

        function [IO, messages] = materializeResolvedAuxiliaryRoles(IO)
            % materializeResolvedAuxiliaryRoles  Align labels/covariates/globals to a resolved payload case axis.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(IO) || ~isfield(IO,'ID') || isempty(IO.ID), return; end
            roles = NMDataIOImportTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
            if ~isstruct(roles), return; end
            labelRefs = {}; covRefs = {}; globalRefs = {};
            if isfield(roles,'labels'), labelRefs = NMDataIOStateTools.roleRefCell(roles.labels); end
            if isfield(roles,'covariates'), covRefs = NMDataIOStateTools.roleRefCell(roles.covariates); end
            if isfield(roles,'globals'), globalRefs = NMDataIOStateTools.roleRefCell(roles.globals); end
            if isempty(labelRefs) && isempty(covRefs) && isempty(globalRefs), return; end

            auxIO = IO;
            auxIO.variableRoles = roles;
            auxIO.sourceType = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'auxiliarySourceType','workspace'));
            auxIO.metadataAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                NMDataIOImportTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id'));
            if isfield(IO,'auxiliaryTableFiles'), auxIO.tableFiles = IO.auxiliaryTableFiles; end
            auxIO.covariateNameList = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covariateNameList',{}));
            auxIO.requireCovariateNames = false;
            [auxIO, auxMessages] = NMDataIOImportTools.materializeVariableRolePayload(auxIO, IO.ID);
            messages = [messages; auxMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if ~isempty(labelRefs) && isfield(auxIO,'label') && ~isempty(auxIO.label)
                % The auxiliary source now owns the label payload. Any canonical-label
                % marker/map inherited from the target container describes the previous
                % payload and must not survive replacement by raw source labels. The
                % resolved transfer-count authority canonicalizes the new label payload once
                % the final case axis and OOCV training-map context are available.
                if isfield(IO,'classificationLabelMap'), IO = rmfield(IO,'classificationLabelMap'); end
                IO.label = auxIO.label; IO.s_label = auxIO.label; IO.L = auxIO.label;
                if strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification')),'regression') && ...
                        isfield(auxIO,'desc_labels') && ~isempty(auxIO.desc_labels)
                    for nameField = {'labelDefinition','labelNamesSpec','labelNames','regressionLabelNames','labelnames'}
                        if isfield(IO,nameField{1}), IO = rmfield(IO,nameField{1}); end
                    end
                    IO.desc_labels = NMDataIOImportTools.asCaseCell(auxIO.desc_labels);
                end
            end
            if ~isempty(covRefs) && isfield(auxIO,'covars') && ~isempty(auxIO.covars)
                retainedCovars = [];
                retainedCovnames = {};
                if any(strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalMode','none')), {'ancova','covariate'})) && ...
                        isfield(IO,'covars') && ~isempty(IO.covars)
                    retainedCovars = double(IO.covars);
                    retainedCovnames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covnames',{}));
                end
                IO.covars = double(auxIO.covars);
                IO.covnames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(auxIO,'covnames',{}));
                if ~isempty(retainedCovars)
                    IO.covars = [IO.covars retainedCovars];
                    IO.covnames = [IO.covnames(:)' retainedCovnames(:)'];
                end
            end
            if ~isempty(globalRefs) && isfield(auxIO,'g') && ~isempty(auxIO.g), IO.g = auxIO.g(:); end
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.auxiliaryMaterialization = NMDataIOImportTools.fieldOr(auxIO,'dataIOAudit',struct());
        end

        function [IO, messages] = prepareResolvedMatrixPayload(IO, NM, importTarget)
            % PREPARERESOLVEDMATRIXPAYLOAD  Convert an in-memory matrix payload into legacy IO fields.
            %
            %   [IO, messages] = ... validates numeric/logical matrix data, aligns metadata,
            %   applies import-target context, and prepares fields consumed by TransferModality2NM.
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(importTarget)
                importTarget = NMDataIOImportTargetTools.normalize(NM, IO, NMDataIOImportTools.fieldOr(IO,'varind',1));
            else
                importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
            end
            messages = NMDataIOMessageTools.emptyMessages();

            preparedKey = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'dataioPreparedCacheKey',''));
            if strncmp(preparedKey,'resolved:',9) && isfield(IO,'importTarget') && isstruct(IO.importTarget)
                preparedTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
                if isequaln(preparedTarget, importTarget)
                    return;
                end
            end

            % The canonical source locators remain unchanged when a numeric payload
            % is prepared. The materialized IO.Y/ID axis owns subsequent transfer.
            sourceSettings = struct();
            if isfield(IO,'input_settings') && isstruct(IO.input_settings), sourceSettings = IO.input_settings; end
            IO.input_settings = NMDataIOImportTools.enrichInputSettingsFromIO(sourceSettings, IO);
            try
                [M, F, ID, L, IO] = NMDataIOImportTools.extractMatrixAxes(IO);
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'prepareResolvedMatrixPayload.extractMatrixAxes');
                return;
            end
            if ~(isnumeric(M) || islogical(M))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedMatrixPayload', ...
                    sprintf('The prepared feature matrix must be numeric; received %s.', class(M)), 1, 'red*')];
                return;
            end
            if size(M,1) ~= numel(ID)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedMatrixPayload', ...
                    sprintf('The prepared feature matrix has %g row(s), but there are %g Case IDs.', size(M,1), numel(ID)), 1, 'red*')];
                return;
            end
            if size(M,2) ~= numel(F)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedMatrixPayload', ...
                    sprintf('The prepared feature matrix has %g feature column(s), but there are %g feature name(s).', size(M,2), numel(F)), 1, 'red*')];
                return;
            end
            hasReferenceCases = false;
            if ~NMDataIOImportTargetTools.isOOCV(importTarget)
                hasReferenceCases = isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases);
            elseif ~logical(NMDataIOImportTools.fieldOr(IO,'caseAxisEstablishing',false))
                [targetContainer, targetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
                messages = [messages; targetMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                hasReferenceCases = NMDataIOImportTools.hasReferenceCases(targetContainer);
            end
            labelsKnown = logical(NMDataIOImportTools.fieldOr(IO,'labels_known',true));
            IO.Y = double(M);
            IO.ID = ID(:);
            IO.s_ID = IO.ID;
            IO.featnames = F(:)';
            IO.s_featnames = IO.featnames;
            if ~isempty(L)
                % extractMatrixAxes has already resolved the authoritative label axis.
                % Project that same axis to every legacy transfer field before
                % canonicalisation so stale table/modify label fields cannot win later.
                IO.label = L;
                IO.s_label = L;
                IO.L = L;
            end
            IO.importTarget = importTarget;
            auxRoles = NMDataIOImportTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
            auxCovRefs = {};
            if isstruct(auxRoles) && isfield(auxRoles,'covariates'), auxCovRefs = NMDataIOStateTools.roleRefCell(auxRoles.covariates); end
            retainGeneratedANCOVA = ~isempty(auxCovRefs) && ...
                any(strcmpi(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'globalMode','none')), {'ancova','covariate'})) && ...
                isfield(IO,'covars') && ~isempty(IO.covars);
            if ~isempty(auxCovRefs) && ~retainGeneratedANCOVA
                if isfield(IO,'covars'), IO = rmfield(IO,'covars'); end
                if isfield(IO,'covnames'), IO = rmfield(IO,'covnames'); end
            elseif isempty(auxCovRefs)
                IO = NMDataIOImportTools.clearInheritedCovariatesWithoutAssignment(IO, NM, '?');
            end
            [IO, alignMessages] = NMDataIOImportTools.applyReferenceCaseAlignmentIfNeeded(NM, IO, 'probe');
            messages = [messages; alignMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if NMDataIOImportTargetTools.isOOCV(importTarget) && ...
                    ismember(double(NMDataIOImportTools.fieldOr(IO,'groupmode',1)), [1 2 3 4 5 6])
                trainingFeatures = NMDataIOImportTools.trainingFeatureNames(NM, importTarget.varind);
                [IO.Y, mappedFeatureNames, featureMessages, featureMap] = NMDataIOImportTools.mapOOCVFeaturesToTrainingOrder(IO.Y, IO.featnames, trainingFeatures, IO);
                messages = [messages; featureMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                IO.featnames = mappedFeatureNames(:)';
                IO.s_featnames = IO.featnames;
                if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
                IO.importReport.oocvFeatureMap = featureMap;
            end
            [IO, auxiliaryMessages] = NMDataIOImportTools.materializeResolvedAuxiliaryRoles(IO);
            messages = [messages; auxiliaryMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if labelsKnown && ~hasReferenceCases && ...
                    (~isfield(IO,'label') || isempty(IO.label)) && (~isfield(IO,'s_label') || isempty(IO.s_label))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedMatrixPayload', ...
                    'The first modality requires labels because this dataset is configured as having known labels.', 1, 'red*')];
                return;
            end
            nFeatures = size(IO.Y,2);
            if ~isfield(IO,'selFeats') || isempty(IO.selFeats)
                IO.selFeats = true(1, nFeatures);
            elseif numel(IO.selFeats) ~= nFeatures
                oldCount = numel(IO.selFeats);
                IO.selFeats = true(1, nFeatures);
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'prepareResolvedMatrixPayload.selection', ...
                    sprintf(['The saved feature selection contained %g entries, but the current source has %g features. ' ...
                    'NM2 cleared the old selection and selected all current features.'], double(oldCount), double(nFeatures)), 2, 'SystemCommands')];
            end
            nCases = size(IO.Y,1);
            if ~isfield(IO,'selCases') || isempty(IO.selCases)
                IO.selCases = true(nCases, 1);
            elseif numel(IO.selCases) ~= nCases
                oldCount = numel(IO.selCases);
                IO.selCases = true(nCases, 1);
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'prepareResolvedMatrixPayload.selection', ...
                    sprintf(['The saved case selection contained %g entries, but the current source has %g cases. ' ...
                    'NM2 cleared the old selection and selected all current cases.'], double(oldCount), double(nCases)), 2, 'SystemCommands')];
            end
            if NMDataIOImportTargetTools.isOOCV(importTarget) && labelsKnown && ...
                    strcmpi(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'),'classification')
                IO.trainingClassificationLabelMap = NMDataIOImportTools.trainingClassificationLabelMap(NM);
            end
            [IO, transferMessages] = NMDataIOImportTools.prepareResolvedTransferCounts(IO, size(IO.Y,1), labelsKnown);
            messages = [messages; transferMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~isfield(IO,'dataioPreparedCacheKey') || isempty(IO.dataioPreparedCacheKey)
                IO.dataioPreparedCacheKey = sprintf('resolved:%s:%g:%g', char(string(NMDataIOImportTools.fieldOr(IO,'sourceType','matrix'))), size(IO.Y,1), size(IO.Y,2));
            end
            IO.dataioPreparedCacheHit = false;
            messages = [messages; NMDataIOMessageTools.make('info', false, 'prepareResolvedMatrixPayload', ...
                sprintf('Prepared %g case(s) and %g feature(s).', size(IO.Y,1), size(IO.Y,2)), 0, 'blue')];
        end

        function [IO, messages] = prepareResolvedTransferCounts(IO, nRows, labelsKnown)
            % prepareResolvedTransferCounts  Complete the generic label/count contract for a resolved case axis.
            %
            % Purpose
            %   Establish canonical labels plus n_subjects, n_subjects_all and n_samples before
            %   TransferModality2NM is entered for any already-resolved case-indexed payload.
            %
            % Inputs/outputs and authority
            %   IO is the canonical resolved transfer state; nRows is its validated case count and
            %   labelsKnown is the import-target label contract. This is the single transfer-time
            %   classification canonicalization authority and also owns the legacy subject/sample counts.
            %   It is representation-independent: numeric matrices and imaging cell payloads share this
            %   case/label contract. It does not reinterpret provenance identity or mutate NM.
            %
            % Scientific/state contract
            %   Training labels establish one deterministic source-value -> canonical 1..K map. Raw OOCV
            %   labels are mapped only through the persisted training map; target-owned OOCV labels are
            %   already canonical and are validated against that map without reinterpretation. Regression
            %   and unlabeled application payloads are one-sample transfers containing nRows subjects.
            %
            % Materialization and performance
            %   O(N) over the already-resident label vector; performs no file IO, source parsing, atlas/
            %   annotation loading, or feature-scale allocation. Safe on commit preparation, not used by
            %   interactive viewer navigation.
            %
            % Failure semantics
            %   Missing/malformed known labels or row-count disagreement are fatal DataIO diagnostics;
            %   no neutral counts or guessed class identities are substituted.
            messages = NMDataIOMessageTools.emptyMessages();
            nRows = double(nRows);
            if ~isscalar(nRows) || ~isfinite(nRows) || nRows < 1 || nRows ~= round(nRows)
                messages = NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                    'The selected data must contain a valid positive number of cases.', 1, 'red*');
                return;
            end
            mode = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'modeflag','classification'))));
            labels = [];
            for name = {'label','s_label','L'}
                f = name{1};
                if isfield(IO,f) && ~isempty(IO.(f)), labels = IO.(f); break; end
            end
            if labelsKnown
                if isempty(labels)
                    messages = NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                        'This dataset is configured as having known labels, but no labels were found in the selected data.', 1, 'red*');
                    return;
                end
                if strcmp(mode,'classification')
                    groupNamesIn = {};
                    if logical(NMDataIOImportTools.fieldOr(IO,'oocvflag',false))
                        classMap = NMDataIOLabelStatsTools.normalizeClassificationMap( ...
                            NMDataIOImportTools.fieldOr(IO,'trainingClassificationLabelMap',struct()));
                        if isempty(fieldnames(classMap))
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                                'OOCV classification labels cannot be canonicalized because the persisted training class-label mapping is unavailable.', 1, 'red*')];
                            return;
                        end
                        if NMDataIOImportTools.hasExplicitLabelAssignment(IO, '?')
                            [labels, groupNames, labelMessages, classMap] = NMDataIOLabelStatsTools.normalizeForTransfer( ...
                                labels, mode, groupNamesIn, 'prepareResolvedTransferCounts', classMap);
                        else
                            if ~(isnumeric(labels) || islogical(labels)) || ~isvector(labels)
                                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                                    'Established OOCV classification labels must be a numeric canonical class vector.', 1, 'red*')];
                                return;
                            end
                            labels = double(labels(:));
                            finiteLabels = labels(isfinite(labels));
                            canonicalIds = double(classMap.canonicalIds(:));
                            if any(~ismember(finiteLabels, canonicalIds))
                                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                                    'Established OOCV labels contain class IDs outside the persisted training class definition.', 1, 'red*')];
                                return;
                            end
                            groupNames = classMap.groupNames;
                            labelMessages = NMDataIOMessageTools.emptyMessages();
                        end
                    else
                        classMapIn = struct();
                        % Intrinsic text classes establish their own source axis and names.
                        % Explicit code definitions apply only to numeric training labels.
                        if isnumeric(labels) || islogical(labels)
                            groupNamesIn = NMDataIOImportTools.resolveLabelDefinitionNames(IO, 'classification');
                            if isempty(groupNamesIn), groupNamesIn = NMDataIOImportTools.fieldOr(IO,'desc_groups',{}); end
                            classMapIn = NMDataIOImportTools.classificationLabelMapFromDefinition(IO, groupNamesIn);
                        end
                        [labels, groupNames, labelMessages, classMap] = NMDataIOLabelStatsTools.normalizeForTransfer( ...
                            labels, mode, groupNamesIn, 'prepareResolvedTransferCounts', classMapIn);
                    end
                else
                    groupNamesIn = {};
                    [labels, groupNames, labelMessages, classMap] = NMDataIOLabelStatsTools.normalizeForTransfer( ...
                        labels, mode, groupNamesIn, 'prepareResolvedTransferCounts', struct());
                end
                messages = [messages; labelMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if size(labels,1) ~= nRows
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                        sprintf('Labels contain %g row(s), but the feature data contain %g case row(s).', size(labels,1), nRows), 1, 'red*')];
                    return;
                end
                IO.label = labels;
                IO.s_label = labels;
                IO.L = labels;
                if strcmp(mode,'classification')
                    IO.desc_groups = groupNames;
                    IO.classificationLabelMap = classMap;
                else
                    labelNames = NMDataIOImportTools.resolveLabelDefinitionNames(IO, 'regression');
                    if isempty(labelNames)
                        labelNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_labels',{}));
                    end
                    if isempty(labelNames) || (numel(labelNames)==1 && strcmp(strtrim(labelNames{1}),'?'))
                        labelNames = NMDataIOImportTools.defaultNames('Label_', size(labels,2));
                    end
                    if numel(labelNames) ~= size(labels,2)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                            sprintf('Regression target names contain %g name(s), but the label data contain %g target column(s).', numel(labelNames), size(labels,2)), 1, 'red*')];
                        return;
                    end
                    IO.desc_labels = labelNames(:)';
                    IO.labelNames = IO.desc_labels;
                    IO.regressionLabelNames = IO.desc_labels;
                end
            end
            if labelsKnown && strcmp(mode,'classification')
                K = numel(NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'desc_groups',{})));
                finiteLabels = labels(isfinite(labels));
                if K < 1 || any(finiteLabels ~= round(finiteLabels)) || any(finiteLabels < 1) || any(finiteLabels > K)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareResolvedTransferCounts', ...
                        'Classification labels contain values outside the classes defined for this analysis.', 1, 'red*')];
                    return;
                end
                counts = zeros(1,K);
                for classId = 1:K, counts(classId) = nnz(finiteLabels == classId); end
                IO.n_subjects = double(counts);
                IO.n_samples = double(K);
            else
                IO.n_subjects = nRows;
                IO.n_samples = 1;
            end
            IO.n_subjects_all = nRows;
        end


        function name = tempTableVariableName()
            % TEMPTABLEVARIABLENAME  Create a valid temporary base-workspace variable name.
            %
            %   name = ... returns a timestamped MATLAB identifier for staging tabular data
            %   into legacy import code paths that require base-workspace variables.
            stamp = datestr(now, 'yyyymmddTHHMMSSFFF');
            name = sprintf('NMDataIO_DB_%s_%06d', stamp, randi(999999));
            name = matlab.lang.makeValidName(name);
        end

        function clearBaseVariable(name)
            % CLEARBASEVARIABLE  Remove a temporary variable from the MATLAB base workspace.
            %
            %   NMDataIOImportTools.clearBaseVariable(name) clears the named variable used for
            %   legacy staging.  Failures are reported as warnings rather than silently hidden.
            try
                evalin('base', sprintf('clear(''%s'')', char(name)));
            catch ME
                warning('NMDataIOImportTools:BaseClearFailed', ...
                    'Could not clear temporary base-workspace variable %s. %s (%s)', char(name), ME.message, ME.identifier);
            end
        end


        function cases = containerCases(D)
            % containerCases  Return the authoritative case list stored in a training or OOCV container.
            %
            % D -> cases.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            cases = {};
            if isstruct(D) && isfield(D,'cases') && ~isempty(D.cases)
                cases = NMDataIOImportTools.asCaseCell(D.cases);
            end
        end

        function messages = validateTransferredImagingContainer(D, varind, importTarget)
            % VALIDATETRANSFERREDIMAGINGCONTAINER  Check post-transfer modality case/data consistency.
            %
            %   messages = ... verifies that the transferred Y{varind} row count is compatible
            %   with the target case list and returns blocking diagnostics on inconsistencies.
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(D) || ~isfield(D,'Y') || numel(D.Y) < varind || isempty(D.Y{varind})
                return;
            end
            cases = NMDataIOImportTools.containerCases(D);
            nCases = numel(cases);
            Y = D.Y{varind};
            if iscell(Y) && ~isempty(Y), Y0 = Y{1}; else, Y0 = Y; end
            if ~(isnumeric(Y0) || islogical(Y0)), return; end
            nRows = size(Y0,1);
            if nCases > 0 && nRows ~= nCases
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                    sprintf('Blocked inconsistent transfer for %s: Y{%g} has %g row(s), but the case list has %g case(s).', NMDataIOImportTargetTools.targetLabel(importTarget), double(varind), nRows, nCases), 1, 'red*')];
            end
            if isfield(D,'files') && numel(D.files) >= varind && ~isempty(D.files{varind})
                F = D.files{varind};
                if ischar(F), nF = size(F,1);
                elseif iscell(F) || isstring(F), nF = numel(F);
                else, nF = NaN; end
                if isfinite(nF) && nCases > 0 && nF ~= nCases
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                        sprintf('Blocked inconsistent transfer for %s: files{%g} has %g row(s), but the case list has %g case(s).', NMDataIOImportTargetTools.targetLabel(importTarget), double(varind), nF, nCases), 1, 'red*')];
                end
            end
            if isfield(D,'label') && ~isempty(D.label) && nCases > 0 && size(D.label,1) ~= nCases
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                    sprintf('Blocked inconsistent transfer for %s: label has %g row(s), but the case list has %g case(s).', NMDataIOImportTargetTools.targetLabel(importTarget), size(D.label,1), nCases), 1, 'red*')];
            end
            if isfield(D,'covars') && ~isempty(D.covars) && nCases > 0 && size(D.covars,1) ~= nCases
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                    sprintf('Blocked inconsistent transfer for %s: covars has %g row(s), but the case list has %g case(s).', NMDataIOImportTargetTools.targetLabel(importTarget), size(D.covars,1), nCases), 1, 'red*')];
            end
            if isfield(D,'n_subjects') && ~isempty(D.n_subjects) && nCases > 0
                ns = double(D.n_subjects(:));
                expectedObserved = nCases;
                if strcmpi(NMDataIOLabelStatsTools.modeName(D),'classification') && ...
                        isfield(D,'label') && ~isempty(D.label) && size(D.label,1) == nCases && ...
                        (isnumeric(D.label) || islogical(D.label)) && isvector(D.label)
                    expectedObserved = nCases - nnz(isnan(double(D.label(:))));
                end
                if all(isfinite(ns)) && sum(ns) ~= expectedObserved
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                        sprintf(['Transfer for %s is inconsistent: the stored group counts sum to %g, but %g observed label(s) ' ...
                        'are available across %g cases.'], NMDataIOImportTargetTools.targetLabel(importTarget), sum(ns), expectedObserved, nCases), 1, 'red*')];
                end
            end
            if isfield(D,'badcoords') && numel(D.badcoords) >= varind && ~isempty(D.badcoords{varind}) && (isnumeric(D.badcoords{varind}) || islogical(D.badcoords{varind}))
                nBad = numel(D.badcoords{varind});
                nFeat = size(Y0,2);
                if nBad ~= nFeat
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'transferConsistency', ...
                        sprintf('Blocked inconsistent transfer for %s: badcoords{%g} has length %g, but Y{%g} has %g feature(s).', NMDataIOImportTargetTools.targetLabel(importTarget), double(varind), nBad, double(varind), nFeat), 1, 'red*')];
                end
            end
        end

        function [D, messages] = resetDependentModalitiesIfCaseListChanged(D, varind, oldCases, importTarget, replacesExisting)
            % RESETDEPENDENTMODALITIESIFCASELISTCHANGED  Drop dependent modalities after case-list redefinition.
            %
            %   [D, messages] = ... is used when replacing training modality 1 changes cases.
            %   It preserves the new first modality and removes later modality artifacts that
            %   can no longer be aligned safely.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 5 || isempty(replacesExisting) || ~logical(replacesExisting) || double(varind) ~= 1 || ~isstruct(D)
                return;
            end
            if isempty(oldCases) || ~isfield(D,'cases') || isempty(D.cases)
                return;
            end
            oldCases = NMDataIOImportTools.asCaseCell(oldCases);
            newCases = NMDataIOImportTools.asCaseCell(D.cases);
            if isequal(oldCases(:), newCases(:))
                return;
            end
            resetCount = 0;
            fields = {'Y','files','datadescriptor','featnames','brainmask','badcoords'};
            for f = 1:numel(fields)
                name = fields{f};
                if isfield(D, name) && iscell(D.(name)) && numel(D.(name)) > 1
                    resetCount = max(resetCount, numel(D.(name)) - 1);
                    D.(name) = D.(name)(1);
                end
            end
            if isfield(D,'n_subjects_all')
                D.n_subjects_all = numel(newCases);
            end
            if resetCount > 0
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseListChanged', ...
                    sprintf('Case list changed while overwriting %s. %g dependent modality slot(s) were reset because their row alignment is no longer valid.', NMDataIOImportTargetTools.targetLabel(importTarget), double(resetCount)), 2, 'SystemCommands')];
            else
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseListChanged', ...
                    sprintf('Case list changed while overwriting %s. No dependent modality slots were present.', NMDataIOImportTargetTools.targetLabel(importTarget)), 1, 'SystemCommands')];
            end
        end

        function [IO, messages] = applyReferenceCaseAlignmentIfNeeded(NM, IO, stage)
            % APPLYREFERENCECASEALIGNMENTIFNEEDED  Align incoming rows to an existing target case list.
            %
            %   [IO, messages] = ... resolves the target container, applies row alignment for
            %   additional/replacement imports when reference cases exist, and caches aligned
            %   prepared table payloads where applicable.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(stage), stage = 'probe'; end
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || ~isstruct(IO), return; end
            if ~isfield(IO,'importTarget') || ~isstruct(IO.importTarget)
                IO.importTarget = NMDataIOImportTargetTools.normalize(NM, IO, NMDataIOImportTools.fieldOr(IO,'varind',1));
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
            if logical(NMDataIOImportTools.fieldOr(IO,'caseAxisEstablishing',false))
                return;
            end
            [targetContainer, targetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            alignmentContainer = NMDataIOImportTools.alignmentReferenceContainer(NM, targetContainer, importTarget);
            if NMDataIOImportTools.hasReferenceCases(alignmentContainer) && ismember(double(NMDataIOImportTools.fieldOr(IO,'groupmode',1)), [1 2 3 4 5 6])
                cacheKey = NMDataIOImportTools.tablePreparedCacheKey(IO, alignmentContainer, 'aligned-covariates-v2');
                if ~isempty(cacheKey)
                    [cacheHit, cached] = NMDataIOImportTools.tablePreparedCache('get', cacheKey);
                    if cacheHit && isstruct(cached) && isfield(cached,'IO') && isstruct(cached.IO)
                        IO = cached.IO;
                        IO.dataioAlignedCacheKey = cacheKey;
                        IO.dataioAlignedCacheHit = true;
                        if isfield(cached,'messages')
                            messages = [messages; cached.messages];
                        end
                        return;
                    end
                end
                [IO, alignMessages] = NMDataIOImportTools.readAndAlignReferenceCaseImport(IO, alignmentContainer, stage);
                messages = [messages; alignMessages];
                if ~NMDataIOMessageTools.hasFatal(alignMessages) && ~isempty(cacheKey) && ...
                        (~isfield(IO,'dataioAlignedCacheKey') || isempty(IO.dataioAlignedCacheKey))
                    IO.dataioAlignedCacheKey = cacheKey;
                    IO.dataioAlignedCacheHit = false;
                    NMDataIOImportTools.tablePreparedCache('set', cacheKey, struct('IO', IO, 'messages', alignMessages, 'createdAt', datestr(now,30), 'stage', 'aligned'));
                end
            end
        end

        function tf = hasReferenceCases(S)
            % hasReferenceCases  Test whether a reference container exposes a usable case list for row alignment.
            %
            % S -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = isstruct(S) && isfield(S,'cases') && ~isempty(S.cases);
        end

        function [IO, messages] = readAndAlignReferenceCaseImport(IO, targetContainer, stage)
            % READANDALIGNREFERENCECASEIMPORT  Read source data and align it to target-container cases.
            %
            %   [IO, messages] = ... handles matrix/table import contracts, applies row mapping
            %   and missing-case policy, records importReport diagnostics, and may reuse the
            %   prepared-table cache.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(stage), stage = 'commit'; end
            cacheKey = NMDataIOImportTools.tablePreparedCacheKey(IO, targetContainer, 'aligned-covariates-v2');
            if ~isempty(cacheKey)
                [cacheHit, cached] = NMDataIOImportTools.tablePreparedCache('get', cacheKey);
                if cacheHit && isstruct(cached) && isfield(cached,'IO') && isstruct(cached.IO)
                    IO = cached.IO;
                    IO.dataioAlignedCacheKey = cacheKey;
                    IO.dataioAlignedCacheHit = true;
                    if isfield(cached,'messages')
                        messages = cached.messages;
                    end
                    return;
                end
            end
            if nargin < 2 || ~NMDataIOImportTools.hasReferenceCases(targetContainer)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment', ...
                    'Case-ID matching was requested, but the current NM2 dataset does not yet contain a Case-ID list.', 1, 'red*')];
                return;
            end

            % Conceptual legacy flow with one deliberate API correction:
            % once a target container has a case list, the import aligns to
            % that list and inherits the existing labels.  It must not read
            % or overwrite labels again for added/replaced modalities.  Do
            % not preload IO.ID with the target cases before reading the
            % source: the case mapper needs the raw incoming IDs/evidence,
            % and using the reference IDs as incoming evidence can produce
            % position-based false shared-key matches.
            sourceIO = IO;
            sourceIO.referenceCaseImport = true;
            sourceIO.label_edit = '?';
            hasResolvedIncomingPayload = NMDataIOImportTools.hasResolvedMatrixPayload(sourceIO);
            if hasResolvedIncomingPayload
                clearIncomingFields = {'label','s_label','L'};
            else
                clearIncomingFields = {'ID','s_ID','label','s_label','L'};
            end
            for kClear = 1:numel(clearIncomingFields)
                if isfield(sourceIO, clearIncomingFields{kClear})
                    sourceIO = rmfield(sourceIO, clearIncomingFields{kClear});
                end
            end

            if isfield(targetContainer,'label') && ~isempty(targetContainer.label) && ...
                    (~isfield(IO,'oocvflag') || ~IO.oocvflag || NMDataIOImportTools.fieldOr(IO,'labels_known',true))
                IO.label = targetContainer.label;
            elseif isfield(IO,'label')
                IO = rmfield(IO,'label');
            end
            IO.label_edit = '?';
            if isfield(IO,'s_label'), IO = rmfield(IO,'s_label'); end
            if isfield(IO,'L'), IO = rmfield(IO,'L'); end

            try
                [M, featureNames, incomingIDs, ~, sourceIO] = NMDataIOImportTools.extractMatrixAxes(sourceIO);
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'referenceCaseImport.readSource');
                return;
            end
            if isempty(M) || isempty(incomingIDs)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'referenceCaseImport', ...
                    'Could not read a non-empty feature matrix and case-ID vector from the source.', 1, 'red*')];
                return;
            end

            IO.featnames = featureNames;

            opts = NMDataIOImportTools.caseAlignmentOptions(IO);
            opts = NMDataIOImportTools.referenceCaseAlignmentOptions(sourceIO, opts, targetContainer, IO.importTarget);
            opts.incomingEvidence = NMDataIOImportTools.importCaseEvidenceRows(sourceIO, numel(incomingIDs));
            opts.referenceLabel = NMDataIOImportTargetTools.caseReferenceLabel(IO.importTarget);
            [alignedM, alignmentReport, alignMessages, rowMap] = NMDataIOImportTools.alignRowsToReferenceCases(M, incomingIDs, targetContainer.cases, opts, stage);
            messages = [messages; alignMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                return;
            end

            referenceIDs = NMDataIOImportTools.asCaseCell(targetContainer.cases);
            if isfield(sourceIO,'covars') && ~isempty(sourceIO.covars)
                sourceCovars = sourceIO.covars;
                if ~(isnumeric(sourceCovars) || islogical(sourceCovars))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment.covariates', ...
                        'Covariates must be numeric before they can be matched to the existing cases.', 1, 'red*')];
                    return;
                end
                sourceCovars = double(sourceCovars);
                if size(sourceCovars,1) ~= numel(incomingIDs)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment.covariates', ...
                        sprintf('Covariates contain %g row(s), but the selected source contains %g Case IDs.', size(sourceCovars,1), numel(incomingIDs)), 1, 'red*')];
                    return;
                end
                alignedCovars = nan(numel(referenceIDs), size(sourceCovars,2));
                if any(rowMap.matched)
                    alignedCovars(rowMap.matched,:) = sourceCovars(rowMap.incomingRowIndex(rowMap.matched),:);
                end
                IO.covars = alignedCovars;
                if isfield(sourceIO,'covnames')
                    IO.covnames = sourceIO.covnames;
                end
            end
            IO.Y = alignedM;
            IO.s_ID = referenceIDs(:);
            IO.ID = referenceIDs(:);
            IO.s_featnames = featureNames(:)';
            IO.featnames = featureNames(:)';
            IO.n_samples = numel(referenceIDs);
            if isfield(targetContainer,'n_subjects'), IO.n_subjects = targetContainer.n_subjects; else, IO.n_subjects = numel(referenceIDs); end
            if isfield(targetContainer,'n_subjects_all'), IO.n_subjects_all = targetContainer.n_subjects_all; else, IO.n_subjects_all = numel(referenceIDs); end
            IO.selCases = true(numel(referenceIDs), 1);
            if ~isfield(IO,'selFeats') || isempty(IO.selFeats), IO.selFeats = true(1, size(alignedM,2)); end
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.caseAlignment = alignmentReport;
            IO.importReport.referenceCaseImport = true;
            IO.importReport.labelSource = 'target-container';
            if isfield(alignmentReport,'missingCases') && ~isempty(alignmentReport.missingCases) && ...
                    isfield(alignmentReport,'allowMissingCasesAsNaN') && alignmentReport.allowMissingCasesAsNaN
                IO.importReport.missingCasesFilledWithNaN = true;
                IO.importReport.requiresEarlyFusionImputation = isfield(IO,'oocvflag') && IO.oocvflag;
            else
                IO.importReport.missingCasesFilledWithNaN = false;
                IO.importReport.requiresEarlyFusionImputation = false;
            end
            if ~isempty(cacheKey) && ~NMDataIOMessageTools.hasFatal(messages)
                IO.dataioAlignedCacheKey = cacheKey;
                IO.dataioAlignedCacheHit = false;
                cachedMessages = messages;
                rawKey = NMDataIOImportTools.tablePreparedCacheKey(sourceIO, [], 'raw');
                if ~isempty(rawKey)
                    [rawHit, rawCached] = NMDataIOImportTools.tablePreparedCache('get', rawKey);
                    if rawHit && isstruct(rawCached) && isfield(rawCached,'messages')
                        cachedMessages = [rawCached.messages; messages];
                    end
                end
                alignedCacheKeys = {cacheKey, NMDataIOImportTools.tablePreparedCacheKey(IO, targetContainer, 'aligned-covariates-v2')};
                alignedCacheKeys = unique(alignedCacheKeys(~cellfun(@isempty, alignedCacheKeys)), 'stable');
                for kCache = 1:numel(alignedCacheKeys)
                    NMDataIOImportTools.tablePreparedCache('set', alignedCacheKeys{kCache}, struct('IO', IO, 'messages', cachedMessages, 'createdAt', datestr(now,30), 'stage', 'aligned'));
                end
            end
        end

        function [M2, mappedNames, messages, report] = mapOOCVFeaturesToTrainingOrder(M, sourceNames, targetNames, IO)
            % MAPOOCVFEATURESTOTRAININGORDER  Materialize OOCV data on the trained feature axis.
            %
            % Automatic mode delegates exact-name correspondence to NMDataIOTableRoleTools.
            % Manual expert mode uses the explicit targetFeatureIndex stored on each
            % assigned source ref; source names are descriptive and never override that map.
            messages = NMDataIOMessageTools.emptyMessages();
            sourceNames = NMDataIOImportTools.asCellstr(sourceNames, 'F', size(M,2));
            targetNames = NMDataIOImportTools.asCellstr(targetNames, 'F', numel(targetNames));
            if nargin < 4 || ~isstruct(IO), IO = struct(); end
            mappingMode = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'featureMappingMode','automatic'))));
            manualMode = strcmp(mappingMode,'manual') && ismember(double(NMDataIOImportTools.fieldOr(IO,'groupmode',1)),[3 4 5 6]);
            if manualMode
                featureRefs = NMDataIOImportTools.variableRoleRefs(IO, 'features');
                if numel(featureRefs) ~= size(M,2)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                        'Manual OOCV feature correspondence no longer matches the materialized source-column count. Refresh the source inventory and repair the mapping.', 1, 'red*')];
                    M2 = M; mappedNames = sourceNames; report = struct('mode','manual'); return;
                end
                sourceIds = cell(1,numel(featureRefs)); targetIndices = nan(1,numel(featureRefs));
                for i = 1:numel(featureRefs)
                    ref = featureRefs{i};
                    if ~NMDataIOImportTools.isCanonicalTabularColumnRef(ref) || ~isfield(ref,'targetFeatureIndex') || isempty(ref.targetFeatureIndex)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                            'Manual OOCV feature correspondence requires every assigned tabular source column to carry one explicit training-target index.', 1, 'red*')];
                        M2 = M; mappedNames = sourceNames; report = struct('mode','manual'); return;
                    end
                    targetIndices(i) = double(ref.targetFeatureIndex);
                    sourceIds{i} = NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(ref,'id',NMDataIOImportTools.variableRefName(ref)));
                end
                if numel(unique(sourceIds,'stable')) ~= numel(sourceIds)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                        'Manual OOCV feature correspondence assigns the same source variable more than once. Each source variable may map to at most one training target.', 1, 'red*')];
                    M2 = M; mappedNames = sourceNames; report = struct('mode','manual'); return;
                end
                try
                    report = NMDataIOTableRoleTools.featureCorrespondence(sourceNames, targetNames, sourceNames, targetIndices);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureMap.manual')];
                    M2 = M; mappedNames = sourceNames; report = struct('mode','manual'); return;
                end
            else
                report = NMDataIOTableRoleTools.featureCorrespondence(sourceNames, targetNames);
            end
            if ~isempty(report.duplicateTargetColumns)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                    sprintf('The persisted training feature definition contains duplicate feature name(s): %s.', strjoin(report.duplicateTargetColumns, ', ')), 1, 'red*')];
                M2 = M; mappedNames = sourceNames; return;
            end
            if ~isempty(report.ambiguousColumns)
                if manualMode
                    detail = strjoin(report.ambiguousColumns, ', ');
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                        sprintf('Manual OOCV feature correspondence assigns more than one source variable to training target(s): %s.', detail), 1, 'red*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureMap', ...
                        sprintf('OOCV source contains ambiguous duplicate column(s) for training feature(s): %s.', strjoin(report.ambiguousColumns, ', ')), 1, 'red*')];
                end
                M2 = M; mappedNames = sourceNames; return;
            end
            if ~manualMode && ~isempty(report.extraColumns)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureMap', ...
                    sprintf('Ignoring %g extra OOCV source feature(s): %s.', numel(report.extraColumns), strjoin(report.extraColumns(1:min(end,8)), ', ')), 2, 'SystemCommands')];
            end
            if ~isempty(report.missingColumns)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureMap', ...
                    sprintf('OOCV source leaves %g training feature(s) unassigned: %s. Missing targets are represented as NaN and require OOCV-level feature imputation before model application.', ...
                    numel(report.missingColumns), strjoin(report.missingColumns(1:min(end,8)), ', ')), 2, 'SystemCommands')];
            end
            M2 = nan(size(M,1), numel(targetNames));
            matchedTargets = report.matchedTargetIndices;
            if ~isempty(matchedTargets)
                sourceIndex = report.targetSourceIndex(matchedTargets);
                M2(:,matchedTargets) = M(:,sourceIndex);
            end
            if ~manualMode && report.reordered
                messages = [messages; NMDataIOMessageTools.make('info', false, 'featureMap', ...
                    'OOCV/application features reordered to match the trained modality feature space.', 0, 'blue')];
            elseif manualMode
                messages = [messages; NMDataIOMessageTools.make('info', false, 'featureMap', ...
                    sprintf('Applied explicit manual correspondence for %g of %g trained feature(s).', numel(report.matchedTargetIndices), numel(targetNames)), 0, 'blue')];
            end
            mappedNames = targetNames;
        end

        function [matched, loc, report] = resolveCaseRowMap(referenceIDs, incomingIDs, opts)
            % RESOLVECASEROWMAP  Resolve one deterministic Case-ID row map for all DataIO alignment paths.
            %
            % Exact IDs are matched first. When enabled, the existing unique shared-key
            % authority may add unambiguous structural matches. No substring fallback or
            % position-based correspondence is introduced here.
            if nargin < 3 || ~isstruct(opts), opts = struct(); end
            referenceIDs = NMDataIOImportTools.caseKeyRows(referenceIDs);
            incomingIDs = NMDataIOImportTools.caseKeyRows(incomingIDs);
            refWidth = NMDataIOImportTools.caseKeyComponentCount(referenceIDs);
            inWidth = NMDataIOImportTools.caseKeyComponentCount(incomingIDs);
            if ~isempty(referenceIDs) && ~isempty(incomingIDs) && refWidth ~= inWidth
                error('NMDataIOImportTools:caseKeyWidthMismatch', ...
                    'Case-key alignment cannot compare %g-component and %g-component keys.', refWidth, inWidth);
            end
            [matched, loc] = NMDataIOImportTools.exactCaseKeyRowMap(referenceIDs, incomingIDs);
            report = struct('mappingMode','direct','mappingSuggested',false,'mappingApproved',false, ...
                'proposedMatched',matched,'proposedLoc',loc,'matchExamples',struct([]),'ambiguousKeys',{{}}, ...
                'nReferenceCases',numel(referenceIDs),'nIncomingCases',numel(incomingIDs), ...
                'nMatchedReferenceCases',sum(matched),'nMatchedIncomingCases',numel(unique(loc(matched))), ...
                'lowCoverage',false);
            report.lowCoverage = NMDataIOImportTools.caseMapLowCoverage(report);
            mode = lower(strtrim(char(string(NMDataIOImportTools.fieldOr(opts,'idMappingMode','direct')))));
            if refWidth > 1 || inWidth > 1 || sum(matched) >= numel(referenceIDs) || ...
                    ~any(strcmp(mode, {'shared_key','numeric_suffix','suffix','auto'}))
                return;
            end
            [matched2, loc2, keyReport] = NMDataIOImportTools.inferUniqueSharedKeyCaseMap(referenceIDs, incomingIDs, opts, matched, loc);
            report.matchExamples = keyReport.matchExamples;
            report.ambiguousKeys = keyReport.ambiguousKeys;
            if sum(matched2) <= sum(matched), return; end
            report.mappingMode = 'shared_key';
            report.mappingSuggested = true;
            report.proposedMatched = matched2(:);
            report.proposedLoc = loc2(:);
            if logical(NMDataIOImportTools.fieldOr(opts,'mappingApproved',false))
                matched = matched2(:);
                loc = loc2(:);
                report.mappingApproved = true;
            end
            coverageMatched = matched;
            coverageLoc = loc;
            if report.mappingSuggested && ~report.mappingApproved
                coverageMatched = report.proposedMatched;
                coverageLoc = report.proposedLoc;
            end
            report.nMatchedReferenceCases = sum(coverageMatched);
            report.nMatchedIncomingCases = numel(unique(coverageLoc(coverageMatched)));
            report.lowCoverage = NMDataIOImportTools.caseMapLowCoverage(report);
        end

        function tf = caseMapLowCoverage(report)
            % CASEMAPLOWCOVERAGE  True when at least half of either non-empty case set is unmatched.
            nRef = double(NMDataIOImportTools.fieldOr(report,'nReferenceCases',0));
            nIncoming = double(NMDataIOImportTools.fieldOr(report,'nIncomingCases',0));
            nRefMatched = double(NMDataIOImportTools.fieldOr(report,'nMatchedReferenceCases',0));
            nIncomingMatched = double(NMDataIOImportTools.fieldOr(report,'nMatchedIncomingCases',0));
            tf = nRefMatched > 0 && nRef > 0 && nIncoming > 0 && ...
                (nRefMatched / nRef <= 0.5 || nIncomingMatched / nIncoming <= 0.5);
        end

        function [alignedM, report, messages, rowMap] = alignRowsToReferenceCases(M, incomingIDs, referenceIDs, opts, stage)
            % alignRowsToReferenceCases  Reorder and optionally pad rows according to reference case IDs.
            %
            % [alignedM, report, messages, rowMap] = ... matches incomingIDs to referenceIDs using
            % direct or approved shared-key/suffix mapping, applies missing-case policy, and
            % returns an audit report for the alignment decision.
            %
            % opts.allowMissingCasesAsNaN: allows absent reference cases to be padded with NaN rows when adding a modality.
            % opts.idMappingMode: selects the case-ID matching strategy used during reference-case alignment.
            % opts.mappingApproved: records whether the user/API has approved non-exact case-ID mapping.
            % opts.missingCasePolicy: defines whether missing reference cases block import or are represented as NaN rows.
            % opts.referenceLabel: names the reference case set in alignment diagnostics.
            % rowMap: exact reference-row to incoming-row mapping used for companion row-wise payloads such as covariates.
            messages = NMDataIOMessageTools.emptyMessages();
            incomingIDs = NMDataIOImportTools.asCaseCell(incomingIDs);
            referenceIDs = NMDataIOImportTools.asCaseCell(referenceIDs);
            rowMap = struct('matched', false(numel(referenceIDs),1), 'incomingRowIndex', zeros(numel(referenceIDs),1));
            stage = lower(char(stage));
            if isempty(stage), stage = 'commit'; end

            [matched, loc, mapReport] = NMDataIOImportTools.resolveCaseRowMap(referenceIDs, incomingIDs, opts);
            mappingSuggested = mapReport.mappingSuggested;
            mappingApproved = mapReport.mappingApproved;
            mappingModeUsed = mapReport.mappingMode;
            keyReport = mapReport;
            usedIncomingRows = unique(loc(matched));
            extraCases = incomingIDs(~ismember((1:numel(incomingIDs))', usedIncomingRows(:)));

            if mappingSuggested && ~mappingApproved
                matched2 = mapReport.proposedMatched;
                loc2 = mapReport.proposedLoc;
                txt = ['Case-ID mapping suggestion: incoming IDs appear to match existing NM cases by unique shared keys ', ...
                    'extracted from case IDs, file names, and folder/path components. Approve the proposed mapping before committing this added modality.'];
                if strcmp(stage, 'commit')
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment', txt, 1, 'red*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseAlignment', txt, 2, 'SystemCommands')];
                end
                alignedM = nan(numel(referenceIDs), size(M, 2));
                report = struct();
                report.schemaVersion = 1;
                report.reference = NMDataIOImportTools.fieldOr(opts, 'referenceLabel', 'NM.cases');
                report.nReferenceCases = numel(referenceIDs);
                report.nIncomingCases = numel(incomingIDs);
                report.nMatchedCases = sum(matched2);
                report.missingCases = {};
                report.extraCases = {};
                report.missingCasePolicy = opts.missingCasePolicy;
                report.allowMissingCasesAsNaN = opts.allowMissingCasesAsNaN;
                report.mappingMode = mappingModeUsed;
                report.mappingSuggested = true;
                report.mappingApproved = false;
                report.reordered = true;
                report.matchExamples = keyReport.matchExamples;
                report.ambiguousKeys = keyReport.ambiguousKeys;
                rowMap.matched = matched2(:);
                rowMap.incomingRowIndex = loc2(:);
                return;
            end

            rowMap.matched = matched(:);
            rowMap.incomingRowIndex = loc(:);
            missingCases = referenceIDs(~matched);
            report = struct();
            report.schemaVersion = 1;
            report.reference = NMDataIOImportTools.fieldOr(opts, 'referenceLabel', 'NM.cases');
            report.nReferenceCases = numel(referenceIDs);
            report.nIncomingCases = numel(incomingIDs);
            report.nMatchedCases = sum(matched);
            report.missingCases = missingCases(:)';
            report.extraCases = extraCases(:)';
            report.missingCasePolicy = opts.missingCasePolicy;
            report.allowMissingCasesAsNaN = opts.allowMissingCasesAsNaN;
            report.mappingMode = mappingModeUsed;
            report.mappingSuggested = mappingSuggested;
            report.mappingApproved = mappingApproved;
            if exist('keyReport','var') && isstruct(keyReport)
                report.matchExamples = keyReport.matchExamples;
                report.ambiguousKeys = keyReport.ambiguousKeys;
            else
                report.matchExamples = struct([]);
                report.ambiguousKeys = {};
            end
            report.reordered = false;
            if all(matched)
                report.reordered = ~isequal(loc(:), (1:numel(referenceIDs))') || ~isempty(extraCases) || mappingApproved;
            elseif any(matched)
                report.reordered = true;
            end

            if numel(referenceIDs) > 0 && numel(incomingIDs) > 0 && ~any(matched)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment', ...
                    sprintf(['No usable overlap was found between incoming case IDs and existing cases during %s. ', ...
                             'Incoming examples: %s. Existing case examples: %s. Automatic detection checks exact IDs ', ...
                             'and unique shared keys extracted from case IDs, file names, and folder/path components.'], ...
                             char(stage), NMDataIOImportTools.joinCases(incomingIDs, 5), NMDataIOImportTools.joinCases(referenceIDs, 5)), 1, 'red*')];
                alignedM = nan(numel(referenceIDs), size(M, 2));
                return;
            end
            messages = [messages; NMDataIOImportTools.caseCoverageMessage('Incoming modality', mapReport, 'caseAlignment')];

            alignedM = nan(numel(referenceIDs), size(M, 2));
            if any(matched)
                alignedM(matched, :) = M(loc(matched), :);
            end

            if mappingApproved
                exampleClause = NMDataIOImportTools.sharedKeyExampleClause(report);
                messages = [messages; NMDataIOMessageTools.make('info', false, 'caseAlignment', ...
                    sprintf('Incoming case IDs were matched by a unique shared key (%g/%g existing case(s) matched) and incoming rows were reordered to the existing NM case order.%s', sum(matched), numel(referenceIDs), exampleClause), 0, 'blue')];
            elseif report.reordered && isempty(missingCases)
                messages = [messages; NMDataIOMessageTools.make('info', false, 'caseAlignment', ...
                    'Added modality rows reordered to match the target case order.', 0, 'blue')];
            end

            if ~isempty(extraCases)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseAlignment', ...
                    sprintf('Extra unmatched incoming case(s) ignored while adding modality: %s.', NMDataIOImportTools.joinCases(extraCases, 8)), 2, 'SystemCommands')];
            end

            if ~isempty(missingCases)
                if opts.allowMissingCasesAsNaN
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseAlignment', ...
                        sprintf('Missing target case(s) filled with NaN while adding modality: %s.', NMDataIOImportTools.joinCases(missingCases, 8)), 2, 'SystemCommands')];
                else
                    txt = sprintf('Missing target case(s) block add-modality commit by default: %s.', NMDataIOImportTools.joinCases(missingCases, 8));
                    if strcmp(stage, 'commit')
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'caseAlignment', txt, 1, 'red*')];
                    else
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'caseAlignment', txt, 2, 'SystemCommands')];
                    end
                end
            end
        end

        function opts = caseAlignmentOptions(IO)
            % CASEALIGNMENTOPTIONS  Normalize case-alignment policy from an IO contract.
            %
            %   opts = NMDataIOImportTools.caseAlignmentOptions(IO) returns fixed fields for
            %   missing-case handling, ID mapping and evidence.  Defaults preserve current NM
            %   add-modality semantics by filling missing cases with NaN.
            ca = struct();
            if isstruct(IO) && isfield(IO,'caseAlignment') && isstruct(IO.caseAlignment)
                ca = IO.caseAlignment;
            end
            opts = struct();
            opts.missingCasePolicy = 'fill_nan';
            if isfield(ca,'missingCasePolicy') && ~isempty(ca.missingCasePolicy)
                opts.missingCasePolicy = char(string(ca.missingCasePolicy));
            end
            opts.allowMissingCasesAsNaN = true;
            if isfield(ca,'allowMissingCasesAsNaN') && ~isempty(ca.allowMissingCasesAsNaN)
                opts.allowMissingCasesAsNaN = logical(ca.allowMissingCasesAsNaN);
            end
            opts.allowMissingCasesAsNaN = opts.allowMissingCasesAsNaN || strcmpi(opts.missingCasePolicy, 'fill_nan');
            opts.idMappingMode = 'direct';
            if isfield(ca,'idMappingMode') && ~isempty(ca.idMappingMode)
                opts.idMappingMode = char(string(ca.idMappingMode));
            end
            opts.mappingApproved = false;
            if isfield(ca,'mappingApproved') && ~isempty(ca.mappingApproved)
                opts.mappingApproved = logical(ca.mappingApproved);
            end
            opts.referenceLabel = 'NM.cases';
        end

        function opts = referenceCaseAlignmentOptions(IO, opts, referenceContainer, importTarget)
            % referenceCaseAlignmentOptions  Adapt alignment options for reference-case imports.
            %
            % opts = ... strengthens default mapping and missing-case behavior when an existing
            % target container constrains the case list.  It does not perform the alignment.
            %
            % opts.allowMissingCasesAsNaN: allows absent reference cases to be padded with NaN rows when adding a modality.
            % opts.idMappingMode: selects the case-ID matching strategy used during reference-case alignment.
            % opts.incomingEvidence: passes evidence text for the incoming case-ID mapping decision.
            % opts.mappingApproved: records whether the user/API has approved non-exact case-ID mapping.
            % opts.missingCasePolicy: defines whether missing reference cases block import or are represented as NaN rows.
            % opts.referenceEvidence: passes evidence text for the reference case-ID mapping decision.
            % opts.referenceLabel: names the reference case set in alignment diagnostics.
            if nargin < 2 || isempty(opts)
                opts = NMDataIOImportTools.caseAlignmentOptions(IO);
            end
            if nargin < 3, referenceContainer = struct(); end
            if nargin < 4, importTarget = struct(); end %#ok<INUSD>
            if ~isfield(opts,'missingCasePolicy') || isempty(opts.missingCasePolicy)
                opts.missingCasePolicy = 'fill_nan';
            end
            if ~isfield(opts,'allowMissingCasesAsNaN') || isempty(opts.allowMissingCasesAsNaN)
                opts.allowMissingCasesAsNaN = true;
            end
            opts.allowMissingCasesAsNaN = logical(opts.allowMissingCasesAsNaN) || strcmpi(char(string(opts.missingCasePolicy)), 'fill_nan');
            if ~isfield(opts,'idMappingMode') || isempty(opts.idMappingMode) || strcmpi(char(string(opts.idMappingMode)), 'direct')
                opts.idMappingMode = 'auto';
            end
            % Reference-case imports are already constrained by the existing NM
            % case list.  A unique shared-key match is therefore safe to apply
            % automatically, while ambiguous/no-overlap mappings remain blocking.
            opts.mappingApproved = true;
            if ~isfield(opts,'referenceLabel') || isempty(opts.referenceLabel)
                opts.referenceLabel = 'existing NM cases';
            end
            if ~isfield(opts,'incomingEvidence') || isempty(opts.incomingEvidence)
                opts.incomingEvidence = NMDataIOImportTools.importCaseEvidenceRows(IO, []);
            end
            if ~isfield(opts,'referenceEvidence') || isempty(opts.referenceEvidence)
                refCases = NMDataIOImportTools.referenceCaseIDs(referenceContainer, struct());
                opts.referenceEvidence = NMDataIOImportTools.referenceContainerCaseEvidenceRows(referenceContainer, refCases);
            end
        end


        function key = tableAlignedPreparedCacheKey(NM, IO)
            % TABLEALIGNEDPREPAREDCACHEKEY  Build a prepared-table cache key for aligned imports.
            %
            %   key = ... resolves the target container and returns a stable key only when a
            %   role-managed table import needs reference-case alignment.
            key = '';
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || ~isstruct(IO), return; end
            if ~NMDataIOImportTools.isRoleManagedTableImport(IO), return; end
            if ~isfield(IO,'importTarget') || ~isstruct(IO.importTarget)
                IO.importTarget = NMDataIOImportTargetTools.normalize(NM, IO, NMDataIOImportTools.fieldOr(IO,'varind',1));
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, NMDataIOImportTools.fieldOr(IO,'varind',1));
            [targetContainer, targetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            if NMDataIOMessageTools.hasFatal(targetMessages)
                return;
            end
            alignmentContainer = NMDataIOImportTools.alignmentReferenceContainer(NM, targetContainer, importTarget);
            if NMDataIOImportTools.hasReferenceCases(alignmentContainer) && ismember(double(NMDataIOImportTools.fieldOr(IO,'groupmode',1)), [1 2 3 4 5 6])
                key = NMDataIOImportTools.tablePreparedCacheKey(IO, alignmentContainer, 'aligned-covariates-v2');
            end
        end

        function key = tablePreparedCacheKey(IO, context, variant)
            % tablePreparedCacheKey  Build the cache key for aligned prepared tables in matrix import flow.
            %
            % Consumes IO, context, variant; returns key.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % May inspect or update the MATLAB workspace according to the source mode; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % context.cases: exposes the cases execution-context value to preprocessing/runtime code.
            % context.featnames: exposes the featnames execution-context value to preprocessing/runtime code.
            % context.Y: exposes the y execution-context value to preprocessing/runtime code.
            if nargin < 2, context = []; end
            if nargin < 3 || isempty(variant), variant = 'raw'; end
            if startsWith(lower(char(variant)), 'aligned_')
                variant = 'aligned';
            end
            key = '';
            if ~NMDataIOImportTools.isRoleManagedTableImport(IO)
                return;
            end
            gm = double(NMDataIOImportTools.fieldOr(IO,'groupmode',NaN));
            if ~ismember(gm, [3 4 5 6])
                return;
            end
            sourceKey = '';
            if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                sourceKey = NMDataIOTableReadTools.tableCacheKey(IO);
            end
            if isempty(sourceKey) && gm == 5
                tableVar = NMDataIOImportTools.fieldOr(IO,'M_edit','?');
                if NMDataIOImportTools.isUnknown(tableVar)
                    tableVar = NMDataIOImportTools.fieldOr(IO,'tableVariable','?');
                end
                if ~NMDataIOImportTools.isUnknown(tableVar)
                    try
                        w = evalin('base', sprintf('whos(''%s'')', char(tableVar)));
                        if ~isempty(w)
                            sourceKey = sprintf('groupmode=5|tablevar=%s|class=%s|size=%s|bytes=%.0f', ...
                                char(tableVar), w(1).class, mat2str(w(1).size), double(w(1).bytes));
                        else
                            sourceKey = sprintf('groupmode=5|tablevar=%s', char(tableVar));
                        end
                    catch
                        sourceKey = sprintf('groupmode=5|tablevar=%s', char(tableVar));
                    end
                end
            end
            if isempty(sourceKey)
                return;
            end
            roleFields = {'datasource','sourceType','groupmode','modeflag','labels_known','oocvflag', ...
                'case_edit','label_edit','col_edit','feature_edit','covar_edit','covnames_edit','ignore_edit', ...
                'uniquelim','nanMapper','selCases','selFeats','desc_data','variableRoles','auxiliaryVariableRoles', ...
                'metadataAlignmentMode','auxiliaryAlignmentMode','caseAxisPolicy','tabularFilters','labelDefinition'};
            parts = {['variant=' char(variant)], sourceKey};
            for i = 1:numel(roleFields)
                if isfield(IO, roleFields{i})
                    parts{end+1} = [roleFields{i} '=' NMDataIOImportTools.cacheValue(IO.(roleFields{i}))]; %#ok<AGROW>
                end
            end
            if isfield(IO,'importTarget') && isstruct(IO.importTarget)
                it = IO.importTarget;
                itFields = {'scope','containerField','containerIndex','varind','labels_known'};
                for i = 1:numel(itFields)
                    if isfield(it, itFields{i})
                        parts{end+1} = ['importTarget.' itFields{i} '=' NMDataIOImportTools.cacheValue(it.(itFields{i}))]; %#ok<AGROW>
                    end
                end
            end
            if contains(lower(char(variant)), 'aligned')
                if isstruct(context) && isfield(context,'cases') && ~isempty(context.cases)
                    parts{end+1} = ['referenceCases=' NMDataIOImportTools.cacheValue(NMDataIOImportTools.asCaseCell(context.cases))]; %#ok<AGROW>
                    if isfield(context,'featnames') && ~isempty(context.featnames)
                        parts{end+1} = ['referenceFeatures=' NMDataIOImportTools.cacheValue(context.featnames)]; %#ok<AGROW>
                    end
                elseif isstruct(context) && isfield(context,'Y') && isfield(context,'cases') && ~isempty(context.cases)
                    parts{end+1} = ['referenceCases=' NMDataIOImportTools.cacheValue(NMDataIOImportTools.asCaseCell(context.cases))]; %#ok<AGROW>
                end
            end
            key = strjoin(parts, '|');
        end

        function [hit, value] = tablePreparedCache(action, key, value)
            % tablePreparedCache  Read, write, or clear the aligned-table cache used by repeated probes and commits.
            %
            % Consumes action, key, value; returns hit, value.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Throws on invalid preconditions instead of returning an ambiguous partial result; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            persistent cache order
            if isempty(cache)
                cache = containers.Map('KeyType','char','ValueType','any');
                order = {};
            end
            if nargin < 3, value = []; end
            hit = false;
            switch lower(char(action))
                case 'get'
                    if ~isempty(key) && isKey(cache, key)
                        value = cache(key);
                        hit = true;
                    end
                case 'set'
                    if isempty(key), return; end
                    cache(key) = value;
                    order(strcmp(order, key)) = [];
                    order{end+1} = key;
                    maxEntries = 6;
                    while numel(order) > maxEntries
                        oldKey = order{1};
                        order(1) = [];
                        if isKey(cache, oldKey)
                            remove(cache, oldKey);
                        end
                    end
                case 'clear'
                    cache = containers.Map('KeyType','char','ValueType','any');
                    order = {};
                otherwise
                    error('NMDataIOImportTools:badPreparedCacheAction', 'Unknown prepared-table operation: %s', char(action));
            end
        end

        function clearPreparedTableCache()
            % CLEARPREPAREDTABLECACHE  Clear cached prepared table payloads.
            %
            %   NMDataIOImportTools.clearPreparedTableCache() resets the persistent prepared-
            %   table cache used by preview and commit alignment paths.
            NMDataIOImportTools.tablePreparedCache('clear', '');
        end

        function txt = cacheValue(v)
            % cacheValue  Convert cache-key components into stable text tokens.
            %
            % V -> txt.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if isempty(v)
                txt = '';
            elseif ischar(v)
                txt = v;
            elseif isstring(v)
                txt = char(strjoin(v(:)', ','));
            elseif isnumeric(v) || islogical(v)
                txt = mat2str(v);
            elseif iscell(v)
                c = cell(size(v));
                for ii = 1:numel(v)
                    c{ii} = NMDataIOImportTools.cacheValue(v{ii});
                end
                txt = strjoin(c(:)', ',');
            elseif isstruct(v)
                if numel(v) > 1
                    c = cell(1,numel(v));
                    for ii = 1:numel(v), c{ii} = NMDataIOImportTools.cacheValue(v(ii)); end
                    txt = strjoin(c, '|');
                    return;
                end
                f = fieldnames(v);
                c = cell(1,numel(f));
                for ii = 1:numel(f)
                    c{ii} = [f{ii} ':' NMDataIOImportTools.cacheValue(v.(f{ii}))];
                end
                txt = strjoin(c, ';');
            else
                try
                    txt = char(string(v));
                catch
                    txt = class(v);
                end
            end
        end

        function tf = isAdditionalModalityIO(IO, NM)
            % ISADDITIONALMODALITYIO  Compatibility predicate for imports constrained by existing cases.
            %
            %   tf = ... returns true when NM or IO already exposes a case list that should act
            %   as an alignment reference.  The public method is retained for older probe code.
            % Compatibility predicate retained for older probe code.  The
            % harmonised API import path now uses target-container case-list
            % state directly; a reference-case import is needed whenever the
            % target container already has cases, irrespective of modality index.
            tf = false;
            if nargin >= 2 && isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                tf = true;
                return;
            end
            if nargin >= 1 && isstruct(IO) && isfield(IO,'ID') && ~isempty(IO.ID)
                tf = true;
            end
        end

        function tf = isRoleManagedTableImport(IO)
            % isRoleManagedTableImport  Identify table imports whose labels/covariates/globals are managed by column roles.
            %
            % IO -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = false;
            if nargin < 1 || ~isstruct(IO) || ~isfield(IO,'groupmode') || isempty(IO.groupmode)
                return;
            end
            if ~ismember(double(IO.groupmode), [3 4 5 6])
                return;
            end
            tf = (exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2) && ...
                 (exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2);
        end

        function tf = labelsRequiredForIO(IO)
            % LABELSREQUIREDFORIO  Determine whether incoming table IO must provide labels.
            %
            %   tf = ... respects reference-case imports that inherit labels and otherwise
            %   delegates to table-role tools when available, preserving first-modality label rules.
            % Additional/replacement modality imports align to an existing
            % case list and inherit the target labels.  They must not pass
            % through the first-modality label-column requirement, even while
            % the raw source is being read for case/feature alignment.
            if isfield(IO,'referenceCaseImport') && ~isempty(IO.referenceCaseImport) && logical(IO.referenceCaseImport)
                tf = false;
                return;
            end
            if isfield(IO,'caseAxisEstablishing') && ~isempty(IO.caseAxisEstablishing) && ~logical(IO.caseAxisEstablishing)
                tf = false;
                return;
            end
            if exist('NMDataIOTableRoleTools','class') == 8 || exist('NMDataIOTableRoleTools','file') == 2
                tf = NMDataIOTableRoleTools.labelsRequired(IO);
                return;
            end
            labelsKnown = true;
            if isfield(IO,'labels_known') && ~isempty(IO.labels_known)
                labelsKnown = IO.labels_known;
            end
            if isfield(IO,'ID') && ~isempty(IO.ID)
                tf = false;
                return;
            end
            tf = (~isfield(IO,'oocvflag') || ~IO.oocvflag || labelsKnown);
        end

        function ids = referenceCaseIDs(NM, IO)
            % referenceCaseIDs  Return the case IDs that act as the alignment reference for a matrix/table import.
            %
            % NM, IO -> ids.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ids = {};
            if nargin >= 1 && isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                ids = NMDataIOImportTools.asCaseCell(NM.cases);
                return;
            end
            if nargin >= 2 && isstruct(IO) && isfield(IO,'ID') && ~isempty(IO.ID)
                ids = NMDataIOImportTools.asCaseCell(IO.ID);
            end
        end

        function c = asCaseCell(v)
            % asCaseCell  Normalize text or cell input into a cell-string style representation.
            %
            % V -> c.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v), c = {}; return; end
            if isstring(v)
                c = cellstr(v(:));
            elseif ischar(v)
                c = cellstr(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v)
                    if isempty(v{i})
                        c{i} = '';
                    elseif isnumeric(v{i}) || islogical(v{i})
                        if isscalar(v{i})
                            c{i} = num2str(v{i});
                        else
                            c{i} = char(string(v{i}));
                        end
                    else
                        c{i} = char(string(v{i}));
                    end
                end
                c = c(:);
            elseif isnumeric(v) || islogical(v)
                c = cellstr(num2str(v(:)));
            else
                c = cellstr(string(v(:)));
            end
            for i = 1:numel(c)
                c{i} = strtrim(char(c{i}));
            end
        end

        function [matched, loc, report] = inferUniqueSharedKeyCaseMap(referenceIDs, incomingIDs, opts, matched, loc)
            % inferUniqueSharedKeyCaseMap  Infer additional row matches from unique shared ID tokens.
            %
            % [matched, loc, report] = ... compares reference and incoming case-token evidence
            % to improve incomplete direct matches.  It only accepts unambiguous token matches
            % and returns examples/ambiguous keys for diagnostics.
            %
            % opts.incomingEvidence: passes evidence text for the incoming case-ID mapping decision.
            % opts.referenceEvidence: passes evidence text for the reference case-ID mapping decision.
            referenceIDs = NMDataIOImportTools.asCaseCell(referenceIDs);
            incomingIDs = NMDataIOImportTools.asCaseCell(incomingIDs);
            if nargin < 4 || isempty(matched)
                [matched, loc] = ismember(referenceIDs, incomingIDs);
            end
            matched = logical(matched(:));
            loc = double(loc(:));
            nRef = numel(referenceIDs);
            nIn = numel(incomingIDs);
            report = struct('matchExamples',struct([]), 'ambiguousKeys',{{}});
            if nRef < 1 || nIn < 1, return; end

            refEvidence = NMDataIOImportTools.evidenceRows(referenceIDs, NMDataIOImportTools.fieldOr(opts,'referenceEvidence',{}), nRef);
            inEvidence = NMDataIOImportTools.evidenceRows(incomingIDs, NMDataIOImportTools.fieldOr(opts,'incomingEvidence',{}), nIn);
            refTokens = NMDataIOImportTools.evidenceTokenSets(referenceIDs, refEvidence);
            inTokens = NMDataIOImportTools.evidenceTokenSets(incomingIDs, inEvidence);

            refKeyRows = containers.Map('KeyType','char','ValueType','any');
            inKeyRows = containers.Map('KeyType','char','ValueType','any');
            for r = 1:nRef
                toks = refTokens{r};
                for t = 1:numel(toks)
                    key = toks{t};
                    if isKey(refKeyRows, key)
                        refKeyRows(key) = [refKeyRows(key) r];
                    else
                        refKeyRows(key) = r;
                    end
                end
            end
            for i = 1:nIn
                toks = inTokens{i};
                for t = 1:numel(toks)
                    key = toks{t};
                    if isKey(inKeyRows, key)
                        inKeyRows(key) = [inKeyRows(key) i];
                    else
                        inKeyRows(key) = i;
                    end
                end
            end

            keys = refKeyRows.keys;
            candidates = cell(nRef,1);
            ambiguousKeys = {};
            for k = 1:numel(keys)
                key = keys{k};
                if ~isKey(inKeyRows, key), continue; end
                rr = unique(double(refKeyRows(key)));
                ii = unique(double(inKeyRows(key)));
                if numel(rr) == 1 && numel(ii) == 1
                    r = rr(1);
                    i = ii(1);
                    score = NMDataIOImportTools.sharedKeyScore(key);
                    candidates{r} = [candidates{r}; struct('incoming',i,'key',key,'score',score)]; %#ok<AGROW>
                else
                    ambiguousKeys{end+1} = key; %#ok<AGROW>
                end
            end

            proposed = nan(nRef,1);
            proposedKey = repmat({''}, nRef, 1);
            for r = 1:nRef
                if matched(r), continue; end
                cand = candidates{r};
                if isempty(cand), continue; end
                scores = [cand.score];
                bestScore = max(scores);
                best = cand(scores == bestScore);
                bestIncoming = unique([best.incoming]);
                if numel(bestIncoming) == 1 && ~ismember(bestIncoming, loc(matched))
                    proposed(r) = bestIncoming;
                    idx = find(scores == bestScore, 1, 'first');
                    proposedKey{r} = cand(idx).key;
                elseif numel(bestIncoming) == 1
                    for b = 1:numel(best)
                        ambiguousKeys{end+1} = best(b).key; %#ok<AGROW>
                    end
                else
                    for b = 1:numel(best)
                        ambiguousKeys{end+1} = best(b).key; %#ok<AGROW>
                    end
                end
            end

            % A proposed incoming row must not be assigned to multiple reference
            % rows.  When this happens, leave all involved rows unmapped and let
            % the missing-case diagnostics expose the ambiguity conservatively.
            valid = isfinite(proposed);
            inVals = unique(proposed(valid));
            for j = 1:numel(inVals)
                rows = find(proposed == inVals(j));
                if numel(rows) > 1
                    ambiguousKeys = [ambiguousKeys; proposedKey(rows)]; %#ok<AGROW>
                    proposed(rows) = nan;
                end
            end

            for r = 1:nRef
                if ~matched(r) && isfinite(proposed(r))
                    matched(r) = true;
                    loc(r) = proposed(r);
                end
            end

            ex = struct('key',{}, 'referenceCase',{}, 'incomingCase',{});
            mappedRows = find(~cellfun(@isempty, proposedKey) & isfinite(proposed));
            for e = 1:min(3,numel(mappedRows))
                r = mappedRows(e);
                ex(e).key = proposedKey{r}; %#ok<AGROW>
                ex(e).referenceCase = referenceIDs{r}; %#ok<AGROW>
                ex(e).incomingCase = incomingIDs{proposed(r)}; %#ok<AGROW>
            end
            report.matchExamples = ex;
            report.ambiguousKeys = unique(ambiguousKeys(:)', 'stable');
        end

        function rows = evidenceRows(ids, evidence, nRows)
            % EVIDENCEROWS  Combine primary IDs and auxiliary evidence into per-row text strings.
            %
            %   rows = NMDataIOImportTools.evidenceRows(ids, evidence, nRows) prepares the
            %   text evidence used by shared-key case mapping while preserving row count.
            ids = NMDataIOImportTools.asCaseCell(ids);
            rows = repmat({''}, nRows, 1);
            for i = 1:min(nRows,numel(ids))
                rows{i} = ids{i};
            end
            if isempty(evidence), return; end
            if iscell(evidence) && numel(evidence) == nRows
                for i = 1:nRows
                    rows{i} = strtrim(sprintf('%s %s', rows{i}, NMDataIOImportTools.evidenceText(evidence{i})));
                end
            else
                ev = NMDataIOImportTools.asCaseCell(evidence);
                if numel(ev) == nRows
                    for i = 1:nRows
                        rows{i} = strtrim(sprintf('%s %s', rows{i}, ev{i}));
                    end
                end
            end
        end

        function txt = evidenceText(v)
            % evidenceText  Normalize case-evidence values before shared-key matching is attempted.
            %
            % V -> txt.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v)
                txt = '';
            elseif iscell(v)
                parts = cell(size(v));
                for i = 1:numel(v)
                    parts{i} = NMDataIOImportTools.evidenceText(v{i});
                end
                txt = strjoin(parts(:)', ' ');
            elseif isstring(v)
                txt = strjoin(cellstr(v(:))', ' ');
            elseif ischar(v)
                txt = strjoin(cellstr(v), ' ');
            elseif isnumeric(v) || islogical(v)
                txt = strjoin(cellstr(num2str(v(:)))', ' ');
            else
                txt = char(string(v));
            end
        end

        function tokenSets = evidenceTokenSets(ids, evidenceRows)
            % EVIDENCETOKENSETS  Tokenize case IDs and evidence rows for shared-key matching.
            %
            %   tokenSets = ... lowercases alphanumeric tokens, filters uninformative tokens,
            %   and returns one token cell array per case row.
            ids = NMDataIOImportTools.asCaseCell(ids);
            evidenceRows = NMDataIOImportTools.asCaseCell(evidenceRows);
            nRows = numel(ids);
            tokenSets = cell(nRows,1);
            for i = 1:nRows
                txt = ids{i};
                if i <= numel(evidenceRows)
                    txt = sprintf('%s %s', txt, evidenceRows{i});
                end
                rawToks = regexp(lower(char(txt)), '[a-z0-9]+', 'match');
                toks = {};
                for t = 1:numel(rawToks)
                    tok = rawToks{t};
                    if NMDataIOImportTools.isInformativeSharedKey(tok)
                        toks{end+1} = tok; %#ok<AGROW>
                    end
                    digitParts = regexp(tok, '\d{4,}', 'match');
                    for d = 1:numel(digitParts)
                        if NMDataIOImportTools.isInformativeSharedKey(digitParts{d})
                            toks{end+1} = digitParts{d}; %#ok<AGROW>
                        end
                    end
                end
                tokenSets{i} = unique(toks, 'stable');
            end
        end

        function tf = isInformativeSharedKey(key)
            % isInformativeSharedKey  Decide whether a token is specific enough to support inferred case matching.
            %
            % Key -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            key = lower(strtrim(char(key)));
            if numel(key) < 3 || any(strcmp(key, {'nii','gz','img','hdr','mat','mri','smri','fmri','bold','anat','func','map','mask','slow','slow5','t1','t2','mprage','spm','cat','cat12','wp','mwp','m0wp','m0wp1','zfalffmap'}))
                tf = false;
                return;
            end
            hasDigit = ~isempty(regexp(key, '\d', 'once'));
            hasLetter = ~isempty(regexp(key, '[a-z]', 'once'));
            if all(isstrprop(key, 'digit'))
                tf = numel(key) >= 4;
            elseif hasDigit && hasLetter
                tf = numel(key) >= 4;
            else
                tf = numel(key) >= 6;
            end
        end

        function score = sharedKeyScore(key)
            % sharedKeyScore  Score a shared case-evidence token for deterministic row-alignment tie breaking.
            %
            % Key -> score.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            key = char(key);
            score = numel(key);
            if all(isstrprop(key, 'digit'))
                score = score + 100;
            elseif ~isempty(regexp(key, '\d', 'once'))
                score = score + 50;
            end
        end

        function rows = importCaseEvidenceRows(IO, nRows)
            % importCaseEvidenceRows  Collect incoming case-ID evidence from import rows for reference alignment.
            %
            % IO, nRows -> rows.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(nRows)
                nRows = 0;
                fields = {'s_ID','ID','caseIds','caseIDs','explicitCaseIDs','imageFilesSpec','imageFiles','files','PP','PPspm'};
                for k = 1:numel(fields)
                    if isstruct(IO) && isfield(IO,fields{k}) && ~isempty(IO.(fields{k}))
                        vals = NMDataIOImportTools.asCaseCell(IO.(fields{k}));
                        if numel(vals) > nRows, nRows = numel(vals); end
                    end
                end
            end
            rows = repmat({''}, double(nRows), 1);
            if nRows < 1, return; end
            fields = {'s_ID','ID','caseIds','caseIDs','explicitCaseIDs','imageFilesSpec','imageFiles','files','PP','PPspm'};
            for k = 1:numel(fields)
                if ~isstruct(IO) || ~isfield(IO,fields{k}) || isempty(IO.(fields{k})), continue; end
                rows = NMDataIOImportTools.appendEvidenceRows(rows, IO.(fields{k}));
            end
        end

        function rows = referenceContainerCaseEvidenceRows(S, ids)
            % referenceContainerCaseEvidenceRows  Collect reference-container case evidence used for inferred row alignment.
            %
            % S, ids -> rows.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ids = NMDataIOImportTools.asCaseCell(ids);
            nRows = numel(ids);
            rows = NMDataIOImportTools.evidenceRows(ids, {}, nRows);
            if ~isstruct(S) || nRows < 1, return; end
            fields = {'cases','ID','s_ID'};
            for k = 1:numel(fields)
                if isfield(S,fields{k}) && ~isempty(S.(fields{k}))
                    rows = NMDataIOImportTools.appendEvidenceRows(rows, S.(fields{k}));
                end
            end
            if isfield(S,'files') && ~isempty(S.files)
                if iscell(S.files)
                    for k = 1:numel(S.files)
                        rows = NMDataIOImportTools.appendEvidenceRows(rows, S.files{k});
                    end
                else
                    rows = NMDataIOImportTools.appendEvidenceRows(rows, S.files);
                end
            end
            if isfield(S,'datadescriptor') && ~isempty(S.datadescriptor)
                dd = S.datadescriptor;
                if ~iscell(dd), dd = num2cell(dd); end
                for d = 1:numel(dd)
                    ds = dd{d};
                    if isstruct(ds) && isfield(ds,'input_settings') && isstruct(ds.input_settings)
                        inputSettings = ds.input_settings;
                        candidateFields = {'ID','caseIds','imageFilesSpec','imageFiles','PP','files','explicitCaseIDs'};
                        for k = 1:numel(candidateFields)
                            if isfield(inputSettings,candidateFields{k}) && ~isempty(inputSettings.(candidateFields{k}))
                                rows = NMDataIOImportTools.appendEvidenceRows(rows, inputSettings.(candidateFields{k}));
                            end
                        end
                    end
                end
            end
        end

        function rows = appendEvidenceRows(rows, evidence)
            % appendEvidenceRows  Append optional case-evidence columns while preserving row count and field schema.
            %
            % Rows, evidence -> rows.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            nRows = numel(rows);
            if nRows < 1 || isempty(evidence), return; end
            vals = NMDataIOImportTools.asCaseCell(evidence);
            if numel(vals) ~= nRows, return; end
            for i = 1:nRows
                rows{i} = strtrim(sprintf('%s %s', rows{i}, vals{i}));
            end
        end

        function txt = sharedKeyExampleClause(report)
            % sharedKeyExampleClause  Format shared-key examples for row-alignment diagnostics.
            %
            % Report -> txt.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            txt = '';
            if ~isstruct(report) || ~isfield(report,'matchExamples') || isempty(report.matchExamples)
                return;
            end
            ex = report.matchExamples(1);
            key = NMDataIOImportTools.fieldOr(ex, 'key', '');
            refCase = NMDataIOImportTools.fieldOr(ex, 'referenceCase', '');
            inCase = NMDataIOImportTools.fieldOr(ex, 'incomingCase', '');
            if ~isempty(key) && ~isempty(refCase) && ~isempty(inCase)
                txt = sprintf(' Example: key ''%s'' matched incoming case ''%s'' to existing case ''%s''.', char(string(key)), char(string(inCase)), char(string(refCase)));
            end
        end

        function keys = numericSuffixKeys(ids)
            % NUMERICSUFFIXKEYS  Extract trailing numeric tokens from case identifiers.
            %
            %   keys = NMDataIOImportTools.numericSuffixKeys(ids) returns per-ID numeric suffixes
            %   used by suffix-based case mapping, or empty strings for IDs without suffixes.
            ids = NMDataIOImportTools.asCaseCell(ids);
            keys = cell(size(ids));
            for i = 1:numel(ids)
                tok = regexp(char(ids{i}), '(\d+)$', 'tokens', 'once');
                if isempty(tok)
                    keys{i} = '';
                else
                    keys{i} = tok{1};
                end
            end
        end

        function txt = joinCases(cases, maxN)
            % joinCases  Format a short bounded list for diagnostics text.
            %
            % Cases, maxN -> txt.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(maxN), maxN = 8; end
            cases = NMDataIOImportTools.asCaseCell(cases);
            if isempty(cases)
                txt = '<none>';
                return;
            end
            show = cases(1:min(maxN, numel(cases)));
            txt = strjoin(show(:)', ', ');
            if numel(cases) > maxN
                txt = sprintf('%s, ... (%g total)', txt, numel(cases));
            end
        end

        function assertLegacyImportPath()
            % ASSERTLEGACYIMPORTPATH  Verify that required legacy DataIO transfer functions exist.
            %
            %   NMDataIOImportTools.assertLegacyImportPath() raises explicit errors when legacy
            %   ReadTabular/TransferModality2NM dependencies are missing from the MATLAB path.
            req = {'ReadTabular','TransferModality2NM','CheckTabFile','CheckReadyStatus','GenerateMessageEntry'};
            missing = {};
            for i = 1:numel(req)
                if exist(req{i}, 'file') ~= 2
                    missing{end+1} = [req{i} '.m']; %#ok<AGROW>
                end
            end
            if ~isempty(missing)
                error('NMDataIOImportTools:missingLegacyPath', ...
                    'Legacy DataIO import helper(s) missing from MATLAB path: %s', strjoin(missing, ', '));
            end
        end

        function out = emptyServiceOut(source)
            % emptyServiceOut  Create the service-style output structure returned by DataIO commit/preview calls.
            %
            % Source -> out.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            out = struct();
            out.ok = false;
            out.readyToImport = false;
            out.blocking = true;
            out.message = '';
            out.strip = NMDataIOMessageTools.highestPriorityStrip([], 'Not run.');
            out.messages = NMDataIOMessageTools.emptyMessages();
            out.summary = NMDataIOMessageTools.summarize(out.messages);
            out.audit = struct();
            out.source = source;
        end

        function out = finishServiceOut(out, messages)
            % finishServiceOut  Attach diagnostics and success/blocking flags to a DataIO service output.
            %
            % Out, messages -> out.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'DataIO operation completed.');
            out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
            out.summary = NMDataIOMessageTools.summarize(messages);
            out.strip = strip;
            out.message = strip.text;
            out.blocking = strip.blocking;
            out.readyToImport = ~strip.blocking;
            out.ok = ~strip.blocking;
        end

        function legacy = toLegacyMess(messages)
            % TOLEGACYMESS  Convert structured DataIO messages to legacy mess cell entries.
            %
            %   legacy = NMDataIOImportTools.toLegacyMess(messages) maps message-table fields
            %   into the legacy GenerateMessageEntry-compatible representation.
            legacy = [];
            if isempty(messages) || ~isstruct(messages), return; end
            for i = 1:numel(messages)
                if isempty(messages(i).text), continue; end
                legacy(end+1).format = messages(i).legacyFormat; %#ok<AGROW>
                legacy(end).flag = messages(i).legacyFlag;
                legacy(end).text = messages(i).text;
                if isempty(legacy(end).format)
                    switch messages(i).level
                        case 'danger', legacy(end).format = 'red*'; legacy(end).flag = 1;
                        case 'warn', legacy(end).format = 'SystemCommands'; legacy(end).flag = 2;
                        case 'ok', legacy(end).format = 'green*'; legacy(end).flag = 0;
                        otherwise, legacy(end).format = 'blue'; legacy(end).flag = 0;
                    end
                end
            end
        end

        function n = selectionCount(IO, fieldName, defaultN)
            % SELECTIONCOUNT  Count selected logical entries in an IO field with a fallback.
            %
            %   n = NMDataIOImportTools.selectionCount(IO, fieldName, defaultN) returns the
            %   number of true entries when the field exists, otherwise defaultN.
            if isfield(IO,fieldName) && ~isempty(IO.(fieldName))
                n = sum(logical(IO.(fieldName)));
            else
                n = defaultN;
            end
        end

        function rows = matrixToNestedCell(M)
            % MATRIXTONESTEDCELL  Convert a matrix-like value to JSON-stable row-cell arrays.
            %
            %   rows = NMDataIOImportTools.matrixToNestedCell(M) returns one cell row per
            %   matrix row so jsonencode/browser decoding preserves two-dimensional structure.
            % Return a 1-by-nRows cell array where each element is a 1-by-nCols
            % cell row. This serializes robustly to JSON as an array of row
            % arrays. A plain MATLAB cell matrix is not sufficiently stable
            % across jsonencode / browser combinations and can appear flattened.
            if isempty(M)
                rows = {};
                return;
            end
            if isnumeric(M) || islogical(M)
                C = num2cell(M);
            elseif iscell(M)
                C = M;
            else
                C = cellstr(string(M));
            end
            nR = size(C,1);
            rows = cell(1,nR);
            for rr = 1:nR
                rows{rr} = C(rr,:);
            end
        end

        function c = matrixToCell(M)
            % matrixToCell  Convert a numeric matrix into a cell payload for preview/table serialization.
            %
            % M -> c.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(M)
                c = cell(0,0);
                return;
            end
            if isnumeric(M) || islogical(M)
                c = num2cell(M);
            elseif iscell(M)
                c = M;
            else
                c = cellstr(string(M));
            end
        end

        function counts = nanCounts(M, dim)
            % NANCOUNTS  Count NaN entries along a matrix dimension.
            %
            %   counts = NMDataIOImportTools.nanCounts(M, dim) returns row-vector counts for
            %   numeric/logical inputs and [] for unsupported input classes.
            counts = [];
            if isnumeric(M) || islogical(M)
                counts = full(sum(isnan(M), dim));
                counts = counts(:)';
            end
        end

        function names = defaultNames(prefix, n)
            % DEFAULTNAMES  Generate deterministic indexed names with a prefix.
            %
            %   names = NMDataIOImportTools.defaultNames(prefix, n) returns {prefix1, ..., prefixN}
            %   and is used when source case/feature names are absent.
            names = cell(1,n);
            for i = 1:n
                names{i} = sprintf('%s%g', prefix, i);
            end
        end

        function [ids, messages] = deriveCaseIDsFromFiles(files, mode, source)
            % deriveCaseIDsFromFiles  Apply the established DataIO subject-file case-ID procedure.
            %
            % This is the shared authority for file-level imaging and ROI imports.  The
            % legacy_spm mode delegates to nk_DefineCaseNames2 exactly once and returns
            % structured DataIO diagnostics; callers remain responsible for uniqueness
            % and source-row cardinality checks.
            messages = NMDataIOMessageTools.emptyMessages();
            ids = {};
            if nargin < 2 || isempty(mode), mode = 'legacy_spm'; end
            if nargin < 3 || isempty(source), source = 'fileCaseIDs'; end
            mode = lower(strrep(NMDataIOImportTools.asChar(mode), '-', '_'));
            if ~ismember(mode, {'','legacy','legacy_spm','spm','spm_unique','spm_unique_filename_parts','filename_unique','unique_filename_parts'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, source, ...
                    sprintf('Unsupported subject-file case-ID mode: %s. Use explicit case IDs or legacy_spm.', mode), 1, 'red*')];
                return;
            end
            ex = exist('nk_DefineCaseNames2', 'file');
            if ~(any(ex == [2 3 5 6 8]) || ~isempty(which('nk_DefineCaseNames2')))
                messages = [messages; NMDataIOMessageTools.make('danger', true, source, ...
                    ['Automatic subject-file case-ID extraction requires legacy nk_DefineCaseNames2.m on the MATLAB path. ', ...
                     'Provide explicit case IDs or add the legacy DataIO helper to the path.'], 1, 'red*')];
                return;
            end
            try
                [rawIDs, ~, legacyMess] = nk_DefineCaseNames2(char(files(:)), numel(files), [], []);
                if isempty(rawIDs)
                    ids = {};
                elseif ischar(rawIDs)
                    if isvector(rawIDs), ids = {reshape(rawIDs,1,[])}; else, ids = cellstr(rawIDs); end
                elseif isstring(rawIDs)
                    ids = cellstr(rawIDs(:));
                elseif iscell(rawIDs)
                    ids = cell(numel(rawIDs),1);
                    for i = 1:numel(rawIDs), ids{i} = char(string(rawIDs{i})); end
                else
                    ids = cellstr(string(rawIDs(:)));
                end
                if ~isempty(legacyMess)
                    try
                        if isstruct(legacyMess)
                            for i = 1:numel(legacyMess)
                                txt = '';
                                if isfield(legacyMess,'msg') && ~isempty(legacyMess(i).msg), txt = char(string(legacyMess(i).msg)); end
                                if isempty(txt) && isfield(legacyMess,'message') && ~isempty(legacyMess(i).message), txt = char(string(legacyMess(i).message)); end
                                if isempty(txt), txt = evalc('disp(legacyMess(i))'); end
                                messages = [messages; NMDataIOMessageTools.make('warning', false, source, strtrim(txt), 2, 'blue')]; %#ok<AGROW>
                            end
                        elseif iscell(legacyMess)
                            for i = 1:numel(legacyMess)
                                messages = [messages; NMDataIOMessageTools.make('warning', false, source, char(string(legacyMess{i})), 2, 'blue')]; %#ok<AGROW>
                            end
                        else
                            messages = [messages; NMDataIOMessageTools.make('warning', false, source, char(string(legacyMess)), 2, 'blue')];
                        end
                    catch
                        messages = [messages; NMDataIOMessageTools.make('warning', false, source, ...
                            'Legacy case-ID extraction returned non-empty diagnostics.', 2, 'blue')];
                    end
                end
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'nk_DefineCaseNames2')];
                return;
            end
            if isempty(ids) || numel(ids) ~= numel(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, source, ...
                    sprintf('Legacy case-ID extraction returned %g ID(s) for %g subject file(s).', numel(ids), numel(files)), 1, 'red*')];
            end
        end

        function c = asCellstr(v, prefix, expectedN)
            % asCellstr  Normalize text or cell input into a cell-string style representation.
            %
            % Consumes v, prefix, expectedN; returns c.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, prefix = 'X'; end
            if nargin < 3, expectedN = numel(v); end
            if isempty(v)
                c = NMDataIOImportTools.defaultNames(prefix, expectedN);
                return;
            end
            if isstring(v), c = cellstr(v(:));
            elseif ischar(v), c = cellstr(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v), c{i} = char(string(v{i})); end
                c = c(:);
            elseif isnumeric(v)
                c = cellstr(num2str(v(:)));
            else
                c = NMDataIOImportTools.defaultNames(prefix, expectedN);
            end
            c = c(:)';
            if numel(c) ~= expectedN
                c = NMDataIOImportTools.defaultNames(prefix, expectedN);
            end
        end

        function tf = isDerivedGlobalSource(source)
            % isDerivedGlobalSource  Identify global-value modes derived from materialized scientific data.
            source = lower(strtrim(NMDataIOImportTools.asChar(source)));
            tf = ismember(source, {'derived','spm_global','surface_sum','surface_mean'});
        end
        function [g, messages] = globalVector(IO)
            % globalVector  Resolve one aligned global value per case from user-supplied or derived state.
            messages = NMDataIOMessageTools.emptyMessages();
            source = NMDataIOImportTools.fieldOr(IO,'globalSource','');
            if NMDataIOImportTools.isDerivedGlobalSource(source)
                datasource = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'datasource',''))));
                sourceType = lower(strtrim(NMDataIOImportTools.asChar(NMDataIOImportTools.fieldOr(IO,'sourceType',''))));
                if strcmp(datasource,'surf') || strcmp(sourceType,'surface-list')
                    Y = NMDataIOImportTools.fieldOr(IO,'Y',[]);
                    if ~(isnumeric(Y) || islogical(Y)) || isempty(Y)
                        g = [];
                    elseif strcmpi(NMDataIOImportTools.asChar(source),'surface_mean')
                        g = nm_nanmean(double(Y),2);
                    else
                        g = nm_nansum(double(Y),2);
                    end
                else
                    ex = exist('CalcGlobals','file');
                    if ~(any(ex == [2 3 5 6 8]) || ~isempty(which('CalcGlobals')))
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                            'Derived volumetric globals require legacy CalcGlobals.m / spm_global on the MATLAB path.', 1, 'red*')];
                        g = [];
                        return;
                    end
                    try
                        tmp = CalcGlobals(IO);
                        g = tmp.g;
                    catch ME
                        messages = [messages; NMDataIOMessageTools.fromException(ME, 'CalcGlobals')];
                        g = [];
                        return;
                    end
                end
            else
                g = NMDataIOImportTools.fieldOr(IO,'g',[]);
            end
            if isempty(g)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                    'Global-scaling mode requires a non-empty global vector.', 1, 'red*')];
                return;
            end
            g = double(g(:));
            if any(~isfinite(g(:)))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                    'Global vector contains non-finite values. NM globals must provide one finite value per case; remove or impute invalid global values before import.', 1, 'red*')];
            end
            ids = NMDataIOImportTools.fieldOr(IO,'ID',{});
            if numel(g) ~= numel(ids)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                    sprintf('Global vector length (%g) differs from number of cases (%g).', numel(g), numel(ids)), 1, 'red*')];
            end
        end
        function s = asChar(v)
            % asChar  Normalize a value into character text for legacy/DataIO metadata fields.
            %
            % V -> s.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v)
                s = '';
            elseif ischar(v)
                s = v;
            elseif isstring(v)
                s = char(v(1));
            elseif iscell(v)
                if isempty(v), s = ''; else, s = char(string(v{1})); end
            elseif isnumeric(v) || islogical(v)
                s = char(string(v(1)));
            else
                try
                    s = char(string(v));
                catch
                    s = '';
                end
            end
        end

        function x = numericVector(v)
            % numericVector  Normalize numeric scalar or vector input for DataIO state/spec fields.
            %
            % V -> x.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v)
                x = [];
            elseif isnumeric(v) || islogical(v)
                x = double(v(:)');
            elseif iscell(v)
                x = nan(1,numel(v));
                for i = 1:numel(v), x(i) = str2double(char(string(v{i}))); end
                x = x(isfinite(x));
            else
                txt = char(string(v));
                parts = regexp(txt, '[,;\s]+', 'split');
                x = nan(1,numel(parts));
                for i = 1:numel(parts), x(i) = str2double(parts{i}); end
                x = x(isfinite(x));
            end
        end

        function out = selectCell(c, idx)
            % SELECTCELL  Select indexed entries from a cell array with empty-input guards.
            %
            %   out = NMDataIOImportTools.selectCell(c, idx) returns c(idx) or {} when the
            %   source or index list is empty.
            if isempty(c) || isempty(idx)
                out = {};
                return;
            end
            out = c(idx);
        end


        function [D2, messages] = preserveExistingLabelsIfSkipped(D1, D2, IO, na)
            % preserveExistingLabelsIfSkipped  Carry forward existing labels when a replace/resume import explicitly skips label assignment.
            %
            % Consumes D1, D2, IO, na; returns D2, messages.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4 || isempty(na), na = '?'; end
            if ~isstruct(D1) || ~isstruct(D2) || ~isfield(D1,'label') || isempty(D1.label)
                return;
            end
            if NMDataIOImportTools.hasExplicitLabelAssignment(IO, na)
                return;
            end
            existingLabels = D1.label;
            if ~(isnumeric(existingLabels) || islogical(existingLabels) || iscell(existingLabels) || isstring(existingLabels) || ischar(existingLabels)) || isempty(existingLabels)
                return;
            end
            oldCases = NMDataIOImportTools.containerCases(D1);
            newCases = NMDataIOImportTools.containerCases(D2);
            if ~isempty(newCases)
                nCases = numel(newCases);
                if size(existingLabels, 1) ~= nCases && ~(isvector(existingLabels) && numel(existingLabels) == nCases)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'preserveExistingLabels', ...
                        sprintf('Existing labels could not be kept because they contain %g value(s), while the current case list contains %g case(s). Review the Case-ID matching or reselect the labels.', double(size(existingLabels,1)), double(nCases)), 2, 'orange*')];
                    return;
                end
                if ~isempty(oldCases) && numel(oldCases) == numel(newCases)
                    oldCases = oldCases(:);
                    newCases = newCases(:);
                    if ~isequal(oldCases, newCases)
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'preserveExistingLabels', ...
                            'Existing labels could not be kept because the Case-ID order changed. Review the Case-ID matching or reselect the labels.', 2, 'orange*')];
                        return;
                    end
                end
            end
            if isvector(existingLabels) && ~ischar(existingLabels)
                existingLabels = existingLabels(:);
            end
            D2.label = existingLabels;
            D2.s_label = existingLabels;
            if isfield(D2,'L') || isfield(D1,'L')
                D2.L = existingLabels;
            end
            if isfield(D1,'groupnames') && ~isempty(D1.groupnames)
                D2.groupnames = D1.groupnames;
            end
            if isfield(D1,'labelnames') && ~isempty(D1.labelnames)
                D2.labelnames = D1.labelnames;
            end
            if isfield(D1,'n_subjects') && ~isempty(D1.n_subjects)
                D2.n_subjects = D1.n_subjects;
            end
            if isfield(D1,'n_subjects_all') && ~isempty(D1.n_subjects_all)
                D2.n_subjects_all = D1.n_subjects_all;
            end
            if isfield(D1,'n_samples') && ~isempty(D1.n_samples)
                D2.n_samples = D1.n_samples;
            end
            if isfield(IO,'varind') && isnumeric(IO.varind) && isscalar(IO.varind) && isfield(D2,'datadescriptor') && iscell(D2.datadescriptor)
                vv = round(double(IO.varind));
                if vv >= 1 && vv <= numel(D2.datadescriptor) && isstruct(D2.datadescriptor{vv}) && ...
                        isfield(D2.datadescriptor{vv},'input_settings') && isstruct(D2.datadescriptor{vv}.input_settings)
                    D2.datadescriptor{vv}.input_settings.label_edit = '?';
                end
            end
            messages = [messages; NMDataIOMessageTools.make('info', false, 'preserveExistingLabels', ...
                'Existing NM.label was preserved because the import state did not explicitly assign labels.', 0, 'blue')];
        end

        function [IO, messages] = canonicalizeCovariateTransfer(D, IO, na)
            % canonicalizeCovariateTransfer  Materialize additive covariates as one target set before legacy transfer.
            % TransferModality2NM appends for covmanage_edit==1. DataIO may legitimately
            % commit the same source contract again after Preview/Modify, so resolve Add
            % against the current target once and pass the resulting set through the
            % existing replace/create branch. This prevents repeated append by flow,
            % rather than repairing duplicate columns after mutation.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(na), na = '?'; end
            if ~isstruct(IO) || ~NMDataIOImportTools.hasExplicitCovariateAssignment(IO, na) || ...
                    double(NMDataIOImportTools.fieldOr(IO,'covmanage_edit',1)) ~= 1 || ...
                    ~isfield(IO,'covars') || isempty(IO.covars) || ...
                    ~isstruct(D) || ~isfield(D,'covars') || isempty(D.covars)
                return;
            end

            incoming = double(IO.covars);
            existing = double(D.covars);
            incomingNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(IO,'covnames',{}));
            existingNames = NMDataIOImportTools.asCaseCell(NMDataIOImportTools.fieldOr(D,'covnames',{}));
            if size(incoming,1) ~= size(existing,1) || numel(incomingNames) ~= size(incoming,2) || ...
                    numel(existingNames) ~= size(existing,2)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'canonicalizeCovariateTransfer', ...
                    'Add-covariate transfer received inconsistent case or covariate-name dimensions.', 1, 'red*')];
                return;
            end

            merged = existing;
            mergedNames = existingNames(:)';
            incomingNames = incomingNames(:)';
            for jj = 1:size(incoming,2)
                name = strtrim(incomingNames{jj});
                if isempty(name)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'canonicalizeCovariateTransfer', ...
                        sprintf('Incoming covariate column %g has no name.', double(jj)), 1, 'red*')];
                    return;
                end
                matches = find(strcmp(mergedNames, name));
                if isempty(matches)
                    merged(:,end+1) = incoming(:,jj); %#ok<AGROW>
                    mergedNames{end+1} = name; %#ok<AGROW>
                elseif ~any(arrayfun(@(kk) isequaln(merged(:,kk), incoming(:,jj)), matches))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'canonicalizeCovariateTransfer', ...
                        sprintf(['Covariate "%s" already exists with different aligned values. ' ...
                        'Add cannot overwrite it; use replace/create when replacement is intended.'], name), 1, 'red*')];
                    return;
                end
            end
            IO.covars = merged;
            IO.covnames = mergedNames;
            IO.covmanage_edit = 2;
        end

        function [D2, messages] = preserveExistingCovariatesIfSkipped(D1, D2, IO, na)
            % preserveExistingCovariatesIfSkipped  Carry forward existing covariates when a replace/resume import explicitly skips covariate assignment.
            %
            % Consumes D1, D2, IO, na; returns D2, messages.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4 || isempty(na), na = '?'; end
            if ~isstruct(D1) || ~isstruct(D2) || ~isfield(D1,'covars') || isempty(D1.covars) || ...
                    ~isfield(D1,'covnames') || isempty(D1.covnames)
                return;
            end
            if NMDataIOImportTools.hasExplicitCovariateAssignment(IO, na)
                return;
            end
            existingCovars = D1.covars;
            existingCovnames = NMDataIOStateTools.asCaseCell(D1.covnames);
            if ~(isnumeric(existingCovars) || islogical(existingCovars)) || isempty(existingCovars) || isempty(existingCovnames)
                return;
            end
            nCov = size(existingCovars, 2);
            if numel(existingCovnames) ~= nCov
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'preserveExistingCovariates', ...
                    sprintf('Existing covariates were not restored because NM.covars has %g column(s) but NM.covnames has %g name(s).', double(nCov), double(numel(existingCovnames))), 2, 'orange*')];
                return;
            end
            oldCases = NMDataIOImportTools.containerCases(D1);
            newCases = NMDataIOImportTools.containerCases(D2);
            if ~isempty(newCases)
                nCases = numel(newCases);
                if size(existingCovars, 1) ~= nCases
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'preserveExistingCovariates', ...
                        sprintf('Existing covariates could not be kept because they contain %g case row(s), while the current case list contains %g case(s). Review the Case-ID matching or reselect the covariates.', double(size(existingCovars,1)), double(nCases)), 2, 'orange*')];
                    return;
                end
                if ~isempty(oldCases) && numel(oldCases) == numel(newCases)
                    oldCases = oldCases(:);
                    newCases = newCases(:);
                    if ~isequal(oldCases, newCases)
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'preserveExistingCovariates', ...
                            'Existing covariates could not be kept because the Case-ID order changed. Review the Case-ID matching or reselect the covariates.', 2, 'orange*')];
                        return;
                    end
                end
            end
            D2.covars = existingCovars;
            D2.covnames = existingCovnames(:)';
            if isfield(IO,'varind') && isnumeric(IO.varind) && isscalar(IO.varind) && isfield(D2,'datadescriptor') && iscell(D2.datadescriptor)
                vv = round(double(IO.varind));
                if vv >= 1 && vv <= numel(D2.datadescriptor) && isstruct(D2.datadescriptor{vv}) && ...
                        isfield(D2.datadescriptor{vv},'input_settings') && isstruct(D2.datadescriptor{vv}.input_settings)
                    D2.datadescriptor{vv}.input_settings.covnames = D2.covnames;
                    D2.datadescriptor{vv}.input_settings.covariateNames = D2.covnames;
                end
            end
            messages = [messages; NMDataIOMessageTools.make('info', false, 'preserveExistingCovariates', ...
                'Existing NM.covars and NM.covnames were preserved because the import state did not explicitly assign covariates.', 0, 'blue')];
        end

        function tf = hasExplicitLabelAssignment(IO, na)
            % hasExplicitLabelAssignment  Detect whether the current source/state contains an explicit user assignment.
            %
            % IO, na -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(na), na = '?'; end
            tf = false;
            if ~isstruct(IO), return; end
            if isfield(IO,'label_edit') && NMDataIOImportTools.hasAssignedRoleEntries(IO.label_edit, na)
                tf = true;
                return;
            end
            if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'labels') && ...
                    NMDataIOImportTools.hasAssignedRoleEntries(IO.tableColumnRoles.labels, na)
                tf = true;
                return;
            end
            if isfield(IO,'auxiliaryVariableRoles') && isstruct(IO.auxiliaryVariableRoles) && ...
                    isfield(IO.auxiliaryVariableRoles,'labels') && ...
                    ~isempty(NMDataIOStateTools.roleRefCell(IO.auxiliaryVariableRoles.labels))
                tf = true;
                return;
            end
            if isfield(IO,'variableRoles') && isstruct(IO.variableRoles) && ...
                    isfield(IO.variableRoles,'labels') && ...
                    ~isempty(NMDataIOStateTools.roleRefCell(IO.variableRoles.labels))
                tf = true;
                return;
            end
            labelMode = '';
            if isfield(IO,'labelMode')
                labelMode = lower(strrep(strrep(NMDataIOImportTools.asChar(IO.labelMode), '-', '_'), ' ', '_'));
            end
            if ismember(labelMode, {'legacy_groups','legacy_group','groups','group_blocks','classification_groups','auto_groups','sequential_groups'}) && ...
                    isfield(IO,'imageFiles') && ~isempty(IO.imageFiles) && isfield(IO,'imageGroupSizes') && ~isempty(IO.imageGroupSizes) && ...
                    (~isfield(IO,'preserveExistingLabel') || ~logical(IO.preserveExistingLabel))
                tf = true;
            end
        end

        function tf = hasExplicitCovariateAssignment(IO, na)
            % hasExplicitCovariateAssignment  Detect whether the current source/state contains an explicit user assignment.
            %
            % IO, na -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(na), na = '?'; end
            tf = false;
            if ~isstruct(IO), return; end
            if isfield(IO,'covar_edit') && NMDataIOImportTools.hasAssignedRoleEntries(IO.covar_edit, na)
                tf = true;
                return;
            end
            if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'covariates') && ...
                    NMDataIOImportTools.hasAssignedRoleEntries(IO.tableColumnRoles.covariates, na)
                tf = true;
                return;
            end
            if isfield(IO,'auxiliaryVariableRoles') && isstruct(IO.auxiliaryVariableRoles) && ...
                    isfield(IO.auxiliaryVariableRoles,'covariates') && ...
                    ~isempty(NMDataIOStateTools.roleRefCell(IO.auxiliaryVariableRoles.covariates))
                tf = true;
                return;
            end
            if isfield(IO,'variableRoles') && isstruct(IO.variableRoles) && ...
                    isfield(IO.variableRoles,'covariates') && ...
                    ~isempty(NMDataIOStateTools.roleRefCell(IO.variableRoles.covariates))
                tf = true;
                return;
            end
            if isfield(IO,'globalMode') && any(strcmpi(NMDataIOImportTools.asChar(IO.globalMode), {'ancova','covariate'}))
                tf = true;
            end
        end

        function IO = clearInheritedCovariatesWithoutAssignment(IO, NM, na)
            % clearInheritedCovariatesWithoutAssignment  Reject ambiguous covariates on an added resolved matrix payload.
            %
            % stateToIO preserves covars/covnames when callers explicitly provide a
            % resolved matrix payload. Once NM already has a modality, those incoming
            % covariates are transferable only when the same payload contains an
            % explicit covariate assignment (role refs/covar_edit/global ANCOVA).
            % Existing NM covariates are not seeded into IO by stateToIO; this guard
            % therefore protects direct resolved-payload semantics, not inheritance.
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(na), na = '?'; end
            if ~isstruct(IO) || ~isfield(IO,'covars')
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'Y') || isempty(NM.Y)
                return;
            end

            if NMDataIOImportTools.hasExplicitCovariateAssignment(IO, na)
                return;
            end

            if isfield(IO,'covars')
                IO = rmfield(IO,'covars');
            end
            if isfield(IO,'covnames')
                IO = rmfield(IO,'covnames');
            end
        end

        function tf = hasAssignedRoleEntries(value, na)
            % hasAssignedRoleEntries  Test whether label/covariate/global role assignments contain meaningful entries.
            %
            % Value, na -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(na), na = '?'; end
            tf = false;
            if isempty(value)
                return;
            end
            if ischar(value) || isstring(value)
                entries = cellstr(string(value(:)));
            elseif iscell(value)
                entries = cell(size(value));
                for ii = 1:numel(value)
                    if isempty(value{ii})
                        entries{ii} = '';
                    else
                        entries{ii} = char(string(value{ii}));
                    end
                end
                entries = entries(:);
            else
                return;
            end
            for ii = 1:numel(entries)
                txt = strtrim(char(entries{ii}));
                if isempty(txt) || strcmp(txt, na) || strcmp(txt, '-')
                    continue;
                end
                tf = true;
                return;
            end
        end

        function tf = isUnknown(v, na)
            % isUnknown  Apply the local DataIO unknown/empty sentinel test.
            %
            % V, na -> tf.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, na = '?'; end
            tf = NMDataIOProbeTools.isUnknown(v, na);
        end

        function v = stateNumber(state, names, defaultValue)
            % STATENUMBER  Read the first finite numeric value from named state fields.
            %
            %   v = NMDataIOImportTools.stateNumber(state, names, defaultValue) scans field
            %   names in order and returns defaultValue when none can be parsed.
            v = defaultValue;
            if ~isstruct(state), return; end
            for i = 1:numel(names)
                if isfield(state,names{i}) && ~isempty(state.(names{i}))
                    x = state.(names{i});
                    if isnumeric(x), v = double(x(1)); return; end
                    y = str2double(char(string(x)));
                    if isfinite(y), v = y; return; end
                end
            end
        end

        function v = fieldOr(S, fieldName, defaultValue)
            % FIELDOR  Return a non-empty struct field value or a fallback.
            %
            %   v = NMDataIOImportTools.fieldOr(S, fieldName, defaultValue) is a local public
            %   helper retained for compatibility.  It does not inspect nested fields.
            if nargin < 3, defaultValue = []; end
            if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
                v = S.(fieldName);
            else
                v = defaultValue;
            end
        end

        function v = opt(opts, name, defaultValue)
            % opt  Read an option field with a caller-specific default without changing option semantics.
            %
            % Consumes opts, name, defaultValue; returns v.
            % It sits on the matrix/table commit path, between browser/API state preparation and mutation of the selected NM target.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            else
                v = defaultValue;
            end
        end
    end
end
