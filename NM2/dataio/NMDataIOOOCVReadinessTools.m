classdef NMDataIOOOCVReadinessTools
% NMDataIOOOCVReadinessTools
% -------------------------------------------------------------------------
% Backend readiness checks for applying trained NM models to explicit
% OOCV/application data containers.  Import may be incomplete; application
% must be blocked until the selected model's required modalities are present
% and resolvable.
% -------------------------------------------------------------------------

    methods (Static)
        function tf = anyReadyContainer(NM)
            % Workbench readiness: reuse DataIO modality and scientific authorities only.
            tf = false;
            % nm2-allow: Legacy nk_GetAnalysisStatus permits NM without OOCV before dataset creation.
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV), return; end
            nTrain = NMDataIOImportTargetTools.nTrainingModalities(NM);
            for o = 1:numel(NM.OOCV)
                D = NM.OOCV{o};
                % nm2-allow: NMDataIOBrowserModeTools.createOOCVContainer creates drafts without committed Y.
                if ~isstruct(D) || ~isfield(D,'Y') || ~iscell(D.Y), continue; end
                present = find(~cellfun(@isempty,D.Y(1:min(nTrain,numel(D.Y)))));
                if isempty(present) || any(arrayfun(@(v)NMDataIOModalityMutationTools.isUncommittedDraftModality(D,v), ...
                        setdiff(1:nTrain,present)))
                    continue;
                end
                target = struct('scope','oocv','containerField','OOCV','containerIndex',o,'varind',1);
                try
                    [report,~] = NMDataIOOOCVReadinessTools.validate(NM,target,present);
                    if report.ready, tf = true; return; end
                catch ME
                    warning('NMDataIOOOCVReadinessTools:readinessFailed', ...
                        'Could not assess OOCV container %d readiness: %s (%s)',o,ME.message,ME.identifier);
                end
            end
        end

        function [report, messages] = validate(NM, importTarget, requiredModalities)
            % validate  Validate OOCV/application readiness for the modality set supplied by the caller.
            %
            % Consumes NM, importTarget, requiredModalities; returns report, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 2 || isempty(importTarget)
                importTarget = struct('scope','oocv','containerField','OOCV','containerIndex',1);
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget);
            if ~NMDataIOImportTargetTools.isOOCV(importTarget)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    'OOCV/application readiness can only be checked for an OOCV dataset.', 1, 'red*')];
                report = NMDataIOOOCVReadinessTools.emptyReport(importTarget, []);
                report.ready = false;
                return;
            end
            if nargin < 3 || isempty(requiredModalities)
                nTrain = NMDataIOImportTargetTools.nTrainingModalities(NM);
                requiredModalities = 1:nTrain;
            end
            requiredModalities = unique(max(1, round(double(requiredModalities(:)'))), 'stable');
            report = NMDataIOOOCVReadinessTools.emptyReport(importTarget, requiredModalities);

            [D, targetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                report.ready = false;
                return;
            end
            if isfield(D,'labels_known') && ~isempty(D.labels_known)
                report.labelsKnown = logical(D.labels_known);
            elseif isfield(importTarget,'labels_known')
                report.labelsKnown = logical(importTarget.labels_known);
            end
            if isfield(D,'cases') && ~isempty(D.cases)
                report.nCases = numel(D.cases);
            else
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('%s has no OOCV case list. Import the first OOCV modality before model application.', NMDataIOImportTargetTools.targetLabel(importTarget)), 1, 'red*')];
            end
            if isfield(D,'groups') && ~isempty(D.groups)
                report.studyGroupsConfigured = true;
                if size(D.groups,1) ~= report.nCases
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                        sprintf('OOCV study groups contain %d entries but the OOCV dataset contains %d cases. Reconfigure the study groups before model application.', size(D.groups,1), report.nCases), 1, 'red*')];
                elseif islogical(D.groups) && size(D.groups,2) > 1
                    [~, groupIDs] = max(D.groups,[],2);
                    report.nStudyGroups = numel(unique(groupIDs));
                elseif (isnumeric(D.groups) || islogical(D.groups)) && size(D.groups,2) == 1 && all(isfinite(double(D.groups(:))))
                    report.nStudyGroups = numel(unique(double(D.groups(:))));
                else
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                        'OOCV study groups must contain one valid group assignment per case.', 1, 'red*')];
                end
            end
            if isequal(report.labelsKnown, true)
                labelIO = struct('oocvflag',true,'labels_known',true);
                if isfield(NM,'modeflag') && ~isempty(NM.modeflag), labelIO.modeflag = NM.modeflag; end
                if isfield(NM,'groupnames') && ~isempty(NM.groupnames), labelIO.desc_groups = NM.groupnames; end
                if isfield(D,'cases') && ~isempty(D.cases), labelIO.ID = D.cases; end
                if isfield(D,'label') && ~isempty(D.label), labelIO.label = D.label; end
                if isfield(D,'s_label') && ~isempty(D.s_label), labelIO.s_label = D.s_label; end
                labelMessages = NMDataIOImportTools.validateOOCVKnownLabels(labelIO, NM);
                messages = [messages; labelMessages];
            end

            for i = 1:numel(requiredModalities)
                v = requiredModalities(i);
                if ~isfield(D,'Y') || ~iscell(D.Y) || numel(D.Y) < v || isempty(D.Y{v})
                    report.missingModalities(end+1) = v; %#ok<AGROW>
                    continue;
                end
                report.presentModalities(end+1) = v; %#ok<AGROW>
                Yv = D.Y{v};
                if ischar(Yv) || isstring(Yv)
                    yPath = char(Yv);
                    if exist(yPath,'file') ~= 2
                        report.unresolvedExternalLinks{end+1} = yPath; %#ok<AGROW>
                    else
                        targetV = importTarget;
                        targetV.varind = v;
                        [okLink, linkDetail] = NMDataIOExternalStorageTools.validateMatFeatureFile(yPath, D, v, targetV);
                        if ~okLink
                            report.externalHashMismatches{end+1} = linkDetail; %#ok<AGROW>
                        end
                    end
                end
                try
                    info = nk_GetNMModalityInfo(D, v, struct('ScanInMemory', false));
                    if isfield(info,'requiresEarlyFusionImputation') && isequal(info.requiresEarlyFusionImputation,true)
                        report.requiresEarlyFusionImputation = true;
                        report.imputationWarnings{end+1} = sprintf('modality %g', double(v)); %#ok<AGROW>
                    end
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness.modalityInfo', ...
                        sprintf(['NM2 could not determine whether OOCV modality %g requires early-fusion imputation because its modality information could not be read: %s. ' ...
                        'Model-application readiness cannot be established until this modality information is repaired or the modality is reimported.'], ...
                        double(v), ME.message), 1, 'red*')];
                end
                [okFeatureMap, detail] = NMDataIOOOCVReadinessTools.featureMapMatchesTraining(NM, D, v);
                if ~okFeatureMap
                    report.featureNameMismatches{end+1} = detail; %#ok<AGROW>
                end
                [unassignedIndices, unassignedNames] = NMDataIOOOCVReadinessTools.unassignedOOCVFeatures(NM, D, v);
                if ~isempty(unassignedIndices)
                    report.unassignedFeatureModalities(end+1) = v; %#ok<AGROW>
                    report.unassignedFeatureNames{end+1} = unassignedNames; %#ok<AGROW>
                end
                [okScientific, scientificDetail] = NMDataIOOOCVReadinessTools.scientificCompatibilityMatchesTraining(NM, D, v);
                if ~okScientific
                    report.scientificCompatibilityMismatches{end+1} = scientificDetail; %#ok<AGROW>
                end
                if isfield(D,'datadescriptor') && iscell(D.datadescriptor) && numel(D.datadescriptor) >= v && ...
                        isstruct(D.datadescriptor{v}) && isfield(D.datadescriptor{v},'QC') && isstruct(D.datadescriptor{v}.QC) && ...
                        isfield(D.datadescriptor{v}.QC,'payload') && isstruct(D.datadescriptor{v}.QC.payload) && ...
                        isfield(D.datadescriptor{v}.QC.payload,'referenceShift') && isstruct(D.datadescriptor{v}.QC.payload.referenceShift) && ...
                        isfield(D.datadescriptor{v}.QC.payload.referenceShift,'status') && ...
                        strcmpi(char(string(D.datadescriptor{v}.QC.payload.referenceShift.status)),'warning')
                    report.distributionShiftModalities(end+1) = v; %#ok<AGROW>
                end
            end

            if ~isempty(report.missingModalities)
                missingNames = cell(1,numel(report.missingModalities));
                for i = 1:numel(report.missingModalities)
                    v = report.missingModalities(i);
                    info = NMModalityInfoTools.fromNM(NM, v, struct('ScanInMemory',false));
                    missingNames{i} = sprintf('%s (modality %d)', info.description, v);
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf(['OOCV/application dataset is missing required training modality/modalities: %s. ' ...
                        'Import the missing modality before application; OOCV-specific imputation cannot substitute an absent modality.'], ...
                        strjoin(missingNames, ', ')), 1, 'red*')];
            end
            if ~isempty(report.unresolvedExternalLinks)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('OOCV/application dataset contains external data file(s) that cannot be found or opened: %s.', strjoin(report.unresolvedExternalLinks, ', ')), 1, 'red*')];
            end
            if ~isempty(report.featureNameMismatches)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('OOCV/application features do not match the features used for training: %s.', strjoin(report.featureNameMismatches, '; ')), 1, 'red*')];
            end
            if ~isempty(report.unassignedFeatureModalities)
                detail = cell(1,numel(report.unassignedFeatureModalities));
                for i = 1:numel(report.unassignedFeatureModalities)
                    names = report.unassignedFeatureNames{i};
                    detail{i} = sprintf('modality %g: %s', double(report.unassignedFeatureModalities(i)), strjoin(names, ', '));
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('OOCV/application data contain unassigned training features (%s). OOCV-level feature imputation is not currently available; model application is blocked.', strjoin(detail, '; ')), 1, 'red*')];
            end
            if ~isempty(report.scientificCompatibilityMismatches)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('OOCV/application data do not match the scientific feature definition used for training: %s.', strjoin(report.scientificCompatibilityMismatches, '; ')), 1, 'red*')];
            end
            if ~isempty(report.externalHashMismatches)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'OOCVReadiness', ...
                    sprintf('OOCV/application external data file(s) do not match the files recorded for this dataset: %s.', strjoin(report.externalHashMismatches, '; ')), 1, 'red*')];
            end
            if report.requiresEarlyFusionImputation
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'OOCVReadiness', ...
                    sprintf('Some OOCV cases are missing data for %s. Early-fusion model application requires a preprocessing imputation step for these missing values.', strjoin(report.imputationWarnings, ', ')), 2, 'SystemCommands')];
            end
            if ~isempty(report.distributionShiftModalities)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'OOCVReadiness', ...
                    sprintf('Substantial training/OOCV distribution discrepancy was detected for modality/modalities %s. Review DataIO QC before model application.', ...
                    NMDataIOOOCVReadinessTools.joinNumeric(report.distributionShiftModalities)), 2, 'orange')];
            end
            report.ready = ~NMDataIOMessageTools.hasFatal(messages);
            if report.ready
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'OOCVReadiness', ...
                    sprintf('OOCV/application dataset is ready for the required modality/modalities: %s.', NMDataIOOOCVReadinessTools.joinNumeric(requiredModalities)), 0, 'green*')];
            end
        end

        function report = emptyReport(importTarget, requiredModalities)
            % emptyReport  Create the fixed-schema OOCV readiness report used by validators and UI.
            %
            % ImportTarget, requiredModalities -> report.
            % It is part of readiness validator that checks whether OOCV/application containers are compatible with the finished training modalities.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            report = struct();
            report.ready = false;
            report.importTarget = importTarget;
            report.requiredModalities = requiredModalities;
            report.presentModalities = [];
            report.missingModalities = [];
            report.unresolvedExternalLinks = {};
            report.featureNameMismatches = {};
            report.unassignedFeatureModalities = [];
            report.unassignedFeatureNames = {};
            report.scientificCompatibilityMismatches = {};
            report.externalHashMismatches = {};
            report.requiresEarlyFusionImputation = false;
            report.imputationWarnings = {};
            report.distributionShiftModalities = [];
            report.studyGroupsConfigured = false;
            report.nStudyGroups = 0;
            report.labelsKnown = [];
            report.nCases = [];
        end

        function [indices, names] = unassignedOOCVFeatures(NM, D, varind)
            % unassignedOOCVFeatures  Read the explicit committed OOCV feature-gap state.
            indices = []; names = {};
            if ~isstruct(D) || ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || ...
                    numel(D.datadescriptor) < varind || ~isstruct(D.datadescriptor{varind}) || ...
                    ~isfield(D.datadescriptor{varind},'input_settings') || ~isstruct(D.datadescriptor{varind}.input_settings)
                return;
            end
            S = D.datadescriptor{varind}.input_settings;
            if ~isfield(S,'importReport') || ~isstruct(S.importReport) || ...
                    ~isfield(S.importReport,'oocvFeatureMap') || ~isstruct(S.importReport.oocvFeatureMap) || ...
                    ~isfield(S.importReport.oocvFeatureMap,'unresolvedTargetIndices') || isempty(S.importReport.oocvFeatureMap.unresolvedTargetIndices)
                return;
            end
            indices = unique(round(double(S.importReport.oocvFeatureMap.unresolvedTargetIndices(:)')),'stable');
            trainingNames = NMDataIOOOCVReadinessTools.featureNames(NM, varind);
            valid = indices >= 1 & indices <= numel(trainingNames);
            indices = indices(valid);
            names = trainingNames(indices);
        end

        function [ok, detail] = featureMapMatchesTraining(NM, D, varind)
            % featureMapMatchesTraining  Compare OOCV feature metadata against the corresponding training modality.
            %
            % Consumes NM, D, varind; returns ok, detail.
            % It is part of readiness validator that checks whether OOCV/application containers are compatible with the finished training modalities.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ok = true;
            detail = '';
            trainFeatures = NMDataIOOOCVReadinessTools.featureNames(NM, varind);
            oocvFeatures = NMDataIOOOCVReadinessTools.featureNames(D, varind);
            if isempty(trainFeatures)
                return;
            end
            if isempty(oocvFeatures)
                ok = false;
                detail = sprintf('modality %g has no saved OOCV feature names', double(varind));
                return;
            end
            if numel(trainFeatures) ~= numel(oocvFeatures) || ~isequal(trainFeatures(:)', oocvFeatures(:)')
                ok = false;
                detail = sprintf('modality %g feature names/order differ', double(varind));
            end
        end

        function [ok, detail] = scientificCompatibilityMatchesTraining(NM, D, varind)
            % scientificCompatibilityMatchesTraining  Validate one committed OOCV modality against canonical training identity.
            %
            % Training scientific provenance is authoritative; physical OOCV source representation is not compared.
            % The check is intentionally read-only and consumes the canonical ROI/connectivity contracts plus the
            % training-owned imaging/surface settings projected by applyOOCVScientificContract.
            ok = true;
            detail = '';

            trainCount = NMDataIOOOCVReadinessTools.featureCount(NM, varind);
            oocvCount = NMDataIOOOCVReadinessTools.featureCount(D, varind);
            if isnan(trainCount)
                ok = false;
                detail = sprintf('modality %g training feature count is unavailable, so OOCV compatibility cannot be established', double(varind));
                return;
            end
            if isnan(oocvCount)
                ok = false;
                detail = sprintf('modality %g has no usable saved OOCV feature count', double(varind));
                return;
            elseif oocvCount ~= trainCount
                ok = false;
                detail = sprintf('modality %g has %g OOCV feature(s), training expects %g', double(varind), oocvCount, trainCount);
                return;
            end

            trainDD = NMDataIOOOCVReadinessTools.modalityDescriptor(NM, varind);
            oocvDD = NMDataIOOOCVReadinessTools.modalityDescriptor(D, varind);
            if isempty(fieldnames(trainDD))
                return;
            end

            if NMDataIOROIProvenanceTools.declaredInDescriptor(trainDD)
                if isempty(fieldnames(oocvDD)) || ~NMDataIOROIProvenanceTools.declaredInDescriptor(oocvDD)
                    ok = false;
                    detail = sprintf('modality %g is missing the OOCV ROI definition required for comparison with training', double(varind));
                    return;
                end
                trainN = []; if ~isnan(trainCount), trainN = trainCount; end
                oocvN = []; if ~isnan(oocvCount), oocvN = oocvCount; end
                trainROI = NMDataIOROIProvenanceTools.normalizeDescriptor(trainDD, trainN);
                oocvROI = NMDataIOROIProvenanceTools.normalizeDescriptor(oocvDD, oocvN);
                if ~trainROI.ok || ~oocvROI.ok
                    ok = false;
                    detail = sprintf('modality %g has an invalid ROI definition in the training or OOCV data', double(varind));
                    return;
                end
                if ~isequal(trainROI.columnKeys(:)', oocvROI.columnKeys(:)') || ...
                        ~isequal(trainROI.roiNames(:)', oocvROI.roiNames(:)')
                    ok = false;
                    detail = sprintf('modality %g ROI identity/order differs from training', double(varind));
                    return;
                end
                trainSpatial = NMDataIOOOCVReadinessTools.roiSpatialIdentityKeys(trainROI);
                oocvSpatial = NMDataIOOOCVReadinessTools.roiSpatialIdentityKeys(oocvROI);
                if ~isequal(sort(trainSpatial), sort(oocvSpatial))
                    ok = false;
                    detail = sprintf('modality %g ROI atlas/annotation spatial identity differs from training', double(varind));
                    return;
                end
                [okGlobal, globalDetail] = NMDataIOOOCVReadinessTools.roiGlobalCorrectionMatches(trainDD, oocvDD);
                if ~okGlobal
                    ok = false;
                    detail = sprintf('modality %g %s', double(varind), globalDetail);
                end
                return;
            end

            trainSource = '';
            if isfield(trainDD,'source') && ~isempty(trainDD.source), trainSource = lower(char(string(trainDD.source))); end
            if strcmp(trainSource, 'connectivity')
                if isempty(fieldnames(oocvDD)) || ~isfield(oocvDD,'connectivity') || ~isstruct(oocvDD.connectivity)
                    ok = false;
                    detail = sprintf('modality %g is missing the OOCV connectivity node/edge definition', double(varind));
                    return;
                end
                if ~isfield(trainDD,'connectivity') || ~isstruct(trainDD.connectivity)
                    ok = false;
                    detail = sprintf('modality %g is missing the training connectivity node/edge definition', double(varind));
                    return;
                end
                trainConn = trainDD.connectivity;
                oocvConn = oocvDD.connectivity;
                required = {'nodeIDs','edgeIndex','matrixType','includeDiagonal'};
                for k = 1:numel(required)
                    name = required{k};
                    if ~isfield(trainConn,name) || isempty(trainConn.(name)) || ~isfield(oocvConn,name) || isempty(oocvConn.(name))
                        ok = false;
                        detail = sprintf('modality %g connectivity definition is missing %s', double(varind), name);
                        return;
                    end
                end
                if ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainConn.nodeIDs, oocvConn.nodeIDs) || ...
                        ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainConn.edgeIndex, oocvConn.edgeIndex) || ...
                        ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainConn.matrixType, oocvConn.matrixType) || ...
                        ~NMDataIOOOCVReadinessTools.scientificValueEqual(logical(trainConn.includeDiagonal), logical(oocvConn.includeDiagonal))
                    ok = false;
                    detail = sprintf('modality %g connectivity node/edge namespace differs from training', double(varind));
                    return;
                end
                identityFields = {'nodeLabels'};
                for k = 1:numel(identityFields)
                    name = identityFields{k};
                    if isfield(trainConn,name) && ~isempty(trainConn.(name)) && ...
                            (~isfield(oocvConn,name) || ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainConn.(name), oocvConn.(name)))
                        ok = false;
                        detail = sprintf('modality %g connectivity %s differs from training', double(varind), name);
                        return;
                    end
                end
                return;
            end

            trainInfo = NMModalityInfoTools.fromNM(NM, varind, struct('ScanInMemory',false));
            oocvInfo = NMModalityInfoTools.fromNM(D, varind, struct('ScanInMemory',false));
            trainFamily = ''; oocvFamily = '';
            if isequal(trainInfo.isSurface,true)
                trainFamily = 'surface';
            elseif isequal(trainInfo.isImaging,true)
                trainFamily = 'volume';
            end
            if isempty(trainFamily), return; end
            if isequal(oocvInfo.isSurface,true)
                oocvFamily = 'surface';
            elseif isequal(oocvInfo.isImaging,true)
                oocvFamily = 'volume';
            end
            if ~strcmp(trainFamily, oocvFamily)
                ok = false;
                detail = sprintf('modality %g OOCV scientific family (%s) differs from training (%s)', double(varind), oocvFamily, trainFamily);
                return;
            end
            trainInput = struct(); oocvInput = struct();
            if isfield(trainDD,'input_settings') && isstruct(trainDD.input_settings), trainInput = trainDD.input_settings; end
            if isfield(oocvDD,'input_settings') && isstruct(oocvDD.input_settings), oocvInput = oocvDD.input_settings; end
            if strcmp(trainFamily,'surface')
                fields = {'surfaceImportMode','surfaceTemplate','surfaceHemisphere','surfaceGeometryIdentity', ...
                    'surfaceInflatedGeometryIdentity','surfaceTopologyIdentity','surfaceVertexOrderIdentity','surfaceRoiCollapseMethod'};
            else
                fields = {'spaceDefType','maskFile','atlasImportMode','atlasCollapseMethod','excludeSubjectZeros', ...
                    'atlasLabelNames','atlasLabelFile','atlasLabelDelimiter','atlasLabelHasHeader','atlasLabelIDColumn','atlasLabelNameColumn', ...
                    'threshop','threshval','threshlabels','uiGlobalModeSelection','globalMode','globalName','globnorm'};
            end
            [fieldsMatch, mismatchField] = NMDataIOOOCVReadinessTools.trainingOwnedFieldsMatch(trainDD, trainInput, oocvDD, oocvInput, fields);
            if ~fieldsMatch
                ok = false;
                detail = sprintf('modality %g OOCV setting %s does not match the training modality', double(varind), mismatchField);
                return;
            end
            splitFields = {'atlasSplit','atlasSplitIndex','atlasSplitRoiID','atlasSplitRoiName'};
            [splitMatch, mismatchField] = NMDataIOOOCVReadinessTools.trainingOwnedFieldsMatch(trainDD, trainInput, oocvDD, oocvInput, splitFields);
            if ~splitMatch
                ok = false;
                detail = sprintf('modality %g OOCV atlas setting %s does not match the training modality', double(varind), mismatchField);
            end
        end

        function n = featureCount(S, varind)
            n = NaN;
            if ~isstruct(S), return; end
            info = NMModalityInfoTools.fromNM(S, varind, struct('ScanInMemory',false));
            if isfield(info,'nFeatures') && isnumeric(info.nFeatures) && isscalar(info.nFeatures) && isfinite(info.nFeatures)
                n = double(info.nFeatures);
            end
        end

        function dd = modalityDescriptor(S, varind)
            dd = struct();
            if isstruct(S) && isfield(S,'datadescriptor') && iscell(S.datadescriptor) && ...
                    numel(S.datadescriptor) >= varind && isstruct(S.datadescriptor{varind}) && isscalar(S.datadescriptor{varind})
                dd = S.datadescriptor{varind};
            end
        end

        function keys = roiSpatialIdentityKeys(roi)
            keys = {};
            if ~isstruct(roi) || ~isfield(roi,'spatialReferences') || isempty(roi.spatialReferences), return; end
            refs = roi.spatialReferences;
            keys = cell(1,numel(refs));
            for k = 1:numel(refs)
                kind = ''; identity = '';
                if isfield(refs(k),'kind') && ~isempty(refs(k).kind), kind = char(string(refs(k).kind)); end
                if isfield(refs(k),'identity') && ~isempty(refs(k).identity), identity = char(string(refs(k).identity)); end
                keys{k} = sprintf('%s|%s', kind, identity);
            end
        end

        function [ok, detail] = roiGlobalCorrectionMatches(trainDD, oocvDD)
            ok = true; detail = '';
            if ~isfield(trainDD,'globalVolumeCorrection') || ~isstruct(trainDD.globalVolumeCorrection) || isempty(fieldnames(trainDD.globalVolumeCorrection))
                return;
            end
            if ~isfield(oocvDD,'globalVolumeCorrection') || ~isstruct(oocvDD.globalVolumeCorrection) || isempty(fieldnames(oocvDD.globalVolumeCorrection))
                ok = false; detail = 'global-volume correction settings are missing'; return;
            end
            fields = {'mode','globalName','globalMultiplier'};
            for k = 1:numel(fields)
                name = fields{k};
                if isfield(trainDD.globalVolumeCorrection,name) && ~isempty(trainDD.globalVolumeCorrection.(name))
                    if ~isfield(oocvDD.globalVolumeCorrection,name) || ...
                            ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainDD.globalVolumeCorrection.(name), oocvDD.globalVolumeCorrection.(name))
                        ok = false; detail = sprintf('global-volume correction %s differs from training', name); return;
                    end
                end
            end
        end

        function [ok, mismatchField] = trainingOwnedFieldsMatch(trainDD, trainInput, oocvDD, oocvInput, fields)
            ok = true; mismatchField = '';
            for k = 1:numel(fields)
                name = fields{k};
                [haveTrain, trainValue] = NMDataIOOOCVReadinessTools.scientificFieldValue(trainDD, trainInput, name);
                if ~haveTrain, continue; end
                [haveOOCV, oocvValue] = NMDataIOOOCVReadinessTools.scientificFieldValue(oocvDD, oocvInput, name);
                if ~haveOOCV || ~NMDataIOOOCVReadinessTools.scientificValueEqual(trainValue, oocvValue)
                    ok = false; mismatchField = name; return;
                end
            end
        end

        function [tf, value] = scientificFieldValue(dd, input, name)
            tf = false; value = [];
            if isstruct(input) && isfield(input,name) && ~isempty(input.(name))
                value = input.(name); tf = true; return;
            end
            if isstruct(dd) && isfield(dd,name) && ~isempty(dd.(name))
                value = dd.(name); tf = true;
            end
        end

        function tf = scientificValueEqual(a, b)
            if (ischar(a) || (isstring(a) && isscalar(a))) && (ischar(b) || (isstring(b) && isscalar(b)))
                tf = strcmp(char(string(a)), char(string(b)));
                return;
            end
            if (isnumeric(a) || islogical(a)) && (isnumeric(b) || islogical(b))
                tf = isequaln(double(a), double(b));
                return;
            end
            if iscell(a) && iscell(b) && all(cellfun(@(x)ischar(x) || (isstring(x) && isscalar(x)),a(:))) && ...
                    all(cellfun(@(x)ischar(x) || (isstring(x) && isscalar(x)),b(:)))
                aa = cellfun(@(x)char(string(x)),a(:)','UniformOutput',false);
                bb = cellfun(@(x)char(string(x)),b(:)','UniformOutput',false);
                tf = isequal(aa,bb);
                return;
            end
            tf = isequaln(a,b);
        end

        function f = featureNames(S, varind)
            % featureNames  Return feature names for a target container/modality from datadescriptor metadata.
            %
            % S, varind -> f.
            % It is part of readiness validator that checks whether OOCV/application containers are compatible with the finished training modalities.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            f = {};
            if ~isstruct(S) || ~isfield(S,'featnames') || numel(S.featnames) < varind || isempty(S.featnames{varind})
                return;
            end
            x = S.featnames{varind};
            if isstring(x)
                f = cellstr(x(:)');
            elseif ischar(x)
                f = cellstr(x);
                f = f(:)';
            elseif iscell(x)
                f = cell(size(x));
                for i = 1:numel(x)
                    f{i} = char(string(x{i}));
                end
                f = f(:)';
            end
        end

        function txt = joinNumeric(v)
            % joinNumeric  Format a short bounded list for diagnostics text.
            %
            % V -> txt.
            % It is part of readiness validator that checks whether OOCV/application containers are compatible with the finished training modalities.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v)
                txt = '';
                return;
            end
            txt = strjoin(arrayfun(@(x) sprintf('%g', double(x)), v(:)', 'UniformOutput', false), ', ');
        end
    end
end
