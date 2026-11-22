classdef NMDataIOImageImportTools
% NMDataIOImageImportTools
% -------------------------------------------------------------------------
% Purpose:
%   Imaging import authority for non-interactive volumetric image lists and native surface scalar
%   streams. It resolves image/surface provenance, metadata alignment, atlas operations and legacy
%   IO contracts before committing through established NeuroMiner image-transfer semantics.
%
% Authority and invariants:
%   Case-ID/label alignment reuses generic DataIO authorities; surface handling is delegated to
%   NMDataIOSurfaceTools. Imaging-specific code owns spatial retrieval and validation, not a second
%   classification-label or subject-matching implementation. Invalid spatial/mask contracts are
%   explicit diagnostics rather than permissive fallbacks.
% -------------------------------------------------------------------------

    methods (Static)
        function [IO, messages] = prepareImageIO(NM, state, opts)
            % prepareImageIO  Convert browser/API imaging state into a legacy IO structure ready for probe or commit.
            %
            % Consumes NM, state, opts; returns IO, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            %
            % opts.RequireReady: requires the prepared import/configuration state to be complete before the method proceeds.
            % state.caseAlignment: stores the case-alignment decision and diagnostics used before commit.
            %
            % state.imageDatasource: selected imaging datasource, normalized to nifti/image or surf for legacy IO.
            % state.dataSourceType: concrete image-list or surface-list source-type alias used by browser/API state.
            % state.mode: classification/regression task-mode alias used when state.modeflag is absent.
            % state.label: modality description alias used when desc_data/description is absent.
            % state.groupNames: group-label names alias used when desc_groups/groupnames are absent.
            % state.labelsKnown: logical alias for labels_known in OOCV/application imports.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            requireReady = NMDataIOImageImportTools.opt(opts, 'RequireReady', false);
            messages = NMDataIOMessageTools.emptyMessages();

            importTarget = NMDataIOImportTargetTools.normalize(NM, state);
            targetMessages = NMDataIOImportTargetTools.validateForImport(NM, importTarget);
            [NM, importTarget, initMessages] = NMDataIOImportTargetTools.ensureContainer(NM, importTarget);
            messages = [targetMessages; initMessages];

            IO = NMDataIOStateTools.defaultIO(NM, importTarget.varind);
            IO.importTarget = importTarget;
            IO.varind = importTarget.varind;
            IO.datasource = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick(state, {'datasource','imageDatasource'}, 'nifti')));
            stateSourceType = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick(state, {'sourceType','dataSourceType'}, 'image-list')));
            if strcmp(IO.datasource,'image'), IO.datasource = 'nifti'; end
            if strcmp(stateSourceType,'surface-list'), IO.datasource = 'surf'; end
            if strcmp(IO.datasource,'surf')
                IO.sourceType = 'surface-list';
            else
                IO.sourceType = 'image-list';
            end
            IO.groupmode = -2;
            IO.oocvflag = NMDataIOImportTargetTools.isOOCV(importTarget);
            IO.labels_known = logical(NMDataIOImageImportTools.pick(state, {'labels_known','labelsKnown'}, importTarget.labels_known));
            IO.modeflag = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick(state, {'modeflag','mode'}, NMDataIOStateTools.inferModeflag(NM)));
            IO.desc_data = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick(state, {'desc_data','description','label'}, sprintf('Imaging modality %d', importTarget.varind)));
            IO.desc_groups = NMDataIOImageImportTools.pick(state, {'desc_groups','groupnames','groupNames'}, NMDataIOImageImportTools.fieldOr(NM,'groupnames',{'Class_1','Class_2'}));
            if ischar(IO.desc_groups) || isstring(IO.desc_groups), IO.desc_groups = cellstr(string(IO.desc_groups)); end
            if isfield(state,'caseAlignment') && isstruct(state.caseAlignment)
                IO.caseAlignment = state.caseAlignment;
            end
            sel = NMDataIOImageImportTools.substructOrEmpty(state, {'selection'});
            IO.selCases = NMDataIOImageImportTools.pick2(state, sel, {'selCases','selectedCases'}, []);

            img = NMDataIOImageImportTools.substructOrEmpty(state, {'image','imaging','imageSource'});
            IO.imageFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'imageFiles','files','P','PP'}, {}));
            IO.imageFilesSpec = IO.imageFiles;
            IO.imageCaseIDSpec = NMDataIOImageImportTools.pick2(state, img, {'caseIds','caseIDs','cases','ID'}, {});
            IO.explicitCaseIDs = NMDataIOImageImportTools.asCellstr(IO.imageCaseIDSpec);
            IO.caseIDMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'caseIDMode','caseIdMode','caseIdSource','caseIDSource'}, 'legacy_spm')));
            IO.maskFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'maskFile','brainmask','spaceDefiningImage','spacedefimg','atlasFile','atlas','roiAtlas','roiAtlasFile','parcellationFile'}, ''));
            IO.threshop = NMDataIOImageImportTools.pick2(state, img, {'threshop','thresholdOperator'}, {'gt'});
            IO.threshval = NMDataIOImageImportTools.pick2(state, img, {'threshval','thresholdValue','Vml'}, 0);
            IO.threshlabels = NMDataIOImageImportTools.pick2(state, img, {'threshlabels','maskLabels','Lm'}, {'Bin Mask'});
            IO.weightingFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'weightingFiles','weightingMaps','Pw'}, {}));
            IO.surfaceImportMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceImportMode','surfaceMode','surfaceSpaceMode'}, 'vertex_template')));
            IO.surfaceTemplate = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceTemplate','surfaceTemplateSpace','templateSpace'}, 'unknown')));
            IO.surfaceHemisphere = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceHemisphere','hemisphere','hemi'}, 'auto')));
            IO.surfaceGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceGeometryFile','surfaceDisplayMeshFile','surfaceTemplateFile','geometryFile'}, ''));
            IO.surfaceInflatedGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceInflatedGeometryFile','inflatedSurfaceGeometryFile','surfaceInflatedTemplateFile'}, ''));
            IO.surfaceRoiCollapseMethod = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiCollapseMethod','surfaceCollapseMethod','roiCollapseMethod'}, 'mean')));
            IO.surfaceRoiLHScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiLHScalarFiles','surfaceLHScalarFiles','lhScalarFiles'}, {}));
            IO.surfaceRoiLHAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiLHAnnotFiles','surfaceLHAnnotFiles','lhAnnotFiles'}, {}));
            IO.surfaceRoiLHGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiLHGeometryFile','surfaceLHGeometryFile'}, ''));
            IO.surfaceRoiRHScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiRHScalarFiles','surfaceRHScalarFiles','rhScalarFiles'}, {}));
            IO.surfaceRoiRHAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiRHAnnotFiles','surfaceRHAnnotFiles','rhAnnotFiles'}, {}));
            IO.surfaceRoiRHGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiRHGeometryFile','surfaceRHGeometryFile'}, ''));
            IO.surfaceRoiScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiScalarFiles','surfaceScalarFiles','roiScalarFiles'}, {}));
            IO.surfaceRoiAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'surfaceRoiAnnotFiles','surfaceAnnotationFiles','roiAnnotationFiles','annotFiles'}, {}));
            IO.spaceDefType = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'spaceDefType','spaceDefinitionType','maskType'}, 'brainmask')));
            if strcmp(IO.datasource,'surf')
                IO.spaceDefType = 'surface_template';
            end
            IO.atlasImportMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasImportMode','spaceDefImportMode','roiImportMode'}, 'voxelwise')));
            IO.atlasCollapseMethod = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasCollapseMethod','collapseMethod','roiSummaryMethod'}, 'soft_mean')));
            IO.excludeSubjectZeros = logical(NMDataIOImageImportTools.pick2(state, img, {'excludeSubjectZeros','zeroExclusion','excludeZeros'}, true));
            IO.atlasLabelNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'atlasLabelNames','roiNames','roiLabels','atlasLabels'}, {}));
            IO.atlasLabelFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasLabelFile','atlasDescriptorFile','atlasSidecarFile','roiLabelFile'}, ''));
            IO.atlasLabelDelimiter = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasLabelDelimiter','atlasDescriptorDelimiter','roiLabelDelimiter'}, 'auto'));
            IO.atlasLabelHasHeader = NMDataIOImageImportTools.pick2(state, img, {'atlasLabelHasHeader','atlasDescriptorHasHeader','roiLabelHasHeader'}, 'auto');
            IO.atlasLabelIDColumn = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasLabelIDColumn','atlasDescriptorIDColumn','roiIDColumn'}, ''));
            IO.atlasLabelNameColumn = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'atlasLabelNameColumn','atlasDescriptorNameColumn','roiNameColumn'}, ''));
            IO.uiGlobalModeSelection = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'uiGlobalModeSelection'}, NMDataIOImageImportTools.pick2(state, img, {'globalMode','globalScaling','globalsMode'}, 'none'))));
            IO.globalMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'globalMode','globalScaling','globalsMode'}, 'none')));
            IO.globalSource = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'globalSource','globalsSource'}, 'user')));
            IO.auxiliarySourceType = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'auxiliarySourceType','auxSourceType'}, 'workspace')));
            IO.auxiliaryAlignmentMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'auxiliaryAlignmentMode'}, 'case_id')));
            IO.auxiliaryVariableRoles = NMDataIOImageImportTools.pick2(state, img, {'auxiliaryVariableRoles'}, struct());
            IO.auxiliaryTableFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'auxiliaryTableFiles','auxiliaryTableFile'}, {}));
            IO.globalUserSourceType = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'globalUserSourceType'}, 'workspace')));
            IO.globalAlignmentMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'globalAlignmentMode'}, 'case_id')));
            IO.globalVariableRoles = NMDataIOImageImportTools.pick2(state, img, {'globalVariableRoles'}, struct());
            IO.globalTableFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'globalTableFiles','globalTableFile'}, {}));
            IO.globalName = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'globalName','globalsName'}, 'GlobalSignal'));
            IO.globnorm = double(NMDataIOImageImportTools.pick2(state, img, {'globnorm','globalNorm','globalMultiplier'}, 1));
            IO.labelMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'labelMode','imageLabelMode','labelsMode'}, 'metadata')));
            IO.imageGroupSizes = NMDataIOImageImportTools.numericVector(NMDataIOImageImportTools.pick2(state, img, {'groupSizes','imageGroupSizes','classGroupSizes','n_subjects'}, []));
            IO.imageGroupNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.pick2(state, img, {'groupNames','imageGroupNames','classGroupNames','desc_groups'}, {}));
            IO.preserveExistingLabel = logical(NMDataIOImageImportTools.pick2(state, img, {'preserveExistingLabel'}, false));
            IO.labelNamesSpec = NMDataIOImageImportTools.pick2(state, img, {'labelNames','regressionLabelNames','labelnames','desc_labels'}, {});
            IO.labelNamesSource = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.pick2(state, img, {'labelNamesSource','regressionLabelNamesSource'}, 'manual')));
            IO.desc_labels = NMDataIOImageImportTools.asCellstr(IO.labelNamesSpec);
            IO.preserveExistingCovariates = logical(NMDataIOImageImportTools.pick2(state, img, {'preserveExistingCovariates'}, false));
            IO.covariateNames = NMDataIOImageImportTools.pick2(state, img, {'covariateNames','covnames','covnames_edit'}, {});
            IO.covmanage_edit = NMDataIOImageImportTools.pick2(state, img, {'covmanage_edit','covariateMode'}, 1);
            IO.nan_subjects = 0;
            IO.nangroup = 0;
            IO.globscale = 1;

            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~ismember(IO.datasource, {'nifti','spm','surf'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO', ...
                    sprintf('Browser spatial import supports NIfTI/SPM images or vertexwise surface scalar files; received datasource=''%s''.', IO.datasource), 1, 'red*')];
                return;
            end
            if NMDataIOImageImportTools.isSurfaceIO(IO)
                if ~NMDataIOImageImportTools.isFunctionAvailable('TransferModality2NM') || ...
                        (exist('NMDataIOSurfaceTools','class') ~= 8 && exist('NMDataIOSurfaceTools','file') ~= 2)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO', ...
                        'Surface import requires TransferModality2NM.m and NMDataIOSurfaceTools.m on the MATLAB path.', 1, 'red*')];
                    return;
                end
            else
                [IO, atlasModeMessages] = NMDataIOImageImportTools.normalizeAtlasMode(IO);
                messages = [messages; atlasModeMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if ~NMDataIOImageImportTools.isFunctionAvailable('spm_vol') || ~NMDataIOImageImportTools.isFunctionAvailable('spm_read_vols') || ...
                        ~NMDataIOImageImportTools.isFunctionAvailable('ReadNifti') || ~NMDataIOImageImportTools.isFunctionAvailable('TransferModality2NM')
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO', ...
                        'SPM and legacy imaging helpers ReadNifti.m / TransferModality2NM.m must be on the MATLAB path for imaging import.', 1, 'red*')];
                    return;
                end
            end
            if requireReady && isempty(IO.imageFiles)
                if NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO)
                    hasRoiSurfaceLists = ~isempty(IO.surfaceRoiLHScalarFiles) || ~isempty(IO.surfaceRoiRHScalarFiles) || ~isempty(IO.surfaceRoiScalarFiles);
                    if ~hasRoiSurfaceLists
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO.surfaceRoi', ...
                            'Native surface ROI import requires scalar and annotation file lists.', 1, 'red*')];
                    end
                else
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO', ...
                        'At least one image/surface scalar file is required for spatial import.', 1, 'red*')];
                end
            end
            if requireReady && ~IO.oocvflag && isempty(IO.maskFile) && ~NMDataIOImageImportTools.isSurfaceIO(IO)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareImageIO', ...
                    'A mask / space-defining image is required for training imaging import.', 1, 'red*')];
            end
        end

        function [IO, messages] = readImagePayload(IO, targetContainer, importTarget, trainingNM, progressTask)
            % readImagePayload  Read voxel/image/surface payloads for the target container and attach matrix/provenance fields.
            %
            % Consumes IO, targetContainer, importTarget, trainingNM; returns IO, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 4 || isempty(trainingNM), trainingNM = struct(); end
            if nargin < 5 || isempty(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            messages = NMDataIOMessageTools.emptyMessages();
            importTarget = NMDataIOImportTargetTools.normalize(trainingNM, importTarget, IO.varind);

            [IO, inheritanceMessages] = NMDataIOImageImportTools.applyImageTargetContext(IO, targetContainer, importTarget, trainingNM);
            messages = [messages; inheritanceMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if NMDataIOImageImportTools.isSurfaceIO(IO)
                [IO, fileMessages] = NMDataIOImageImportTools.resolveSurfaceFiles(IO);
            else
                [IO, fileMessages] = NMDataIOImageImportTools.resolveImageFiles(IO);
            end
            messages = [messages; fileMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if ~NMDataIOImportTools.hasReferenceCases(NMDataIOImportTools.alignmentReferenceContainer(trainingNM, targetContainer, importTarget))
                [IO, groupLabelMessages] = NMDataIOImageImportTools.resolveLegacyGroupLabels(IO);
                messages = [messages; groupLabelMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end

            [IO, roleMessages] = NMDataIOImportTools.materializeConfiguredGlobalRole(IO, IO.ID);
            messages = [messages; roleMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~NMDataIOImportTools.hasReferenceCases(NMDataIOImportTools.alignmentReferenceContainer(trainingNM, targetContainer, importTarget)) && IO.labels_known && ...
                    (~isfield(IO,'label') || isempty(IO.label)) && ~NMDataIOImportTools.hasExplicitLabelAssignment(IO,'?')
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageLabels', ...
                    'First imaging modality import requires labels when labels_known=true. For classification, use sequential image-group labels or assign a label role in Auxiliary Variables; for regression, assign a label role in Auxiliary Variables. Set labelsKnown=false only for unlabeled OOCV/application data.', 1, 'red*')];
                return;
            end

            [IO, selectionMessages] = NMDataIOImageImportTools.applySubjectSelectionToResolvedIO(IO);
            messages = [messages; selectionMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if ~NMDataIOImageImportTools.isSurfaceIO(IO)
                [IO, globalMessages] = NMDataIOImageImportTools.resolveGlobals(IO);
                messages = [messages; globalMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            if ~NMDataIOImageImportTools.isSurfaceIO(IO) && isfield(IO,'globscale') && IO.globscale > 1
                [~, scaleMessages] = NMDataIOImageImportTools.proportionalGlobalScaleFactors(IO.g, IO.globnorm, numel(IO.ID), 'globals.proportional');
                messages = [messages; scaleMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end

            if ~NMDataIOImageImportTools.isSurfaceIO(IO)
                messages = [messages; NMDataIOImageImportTools.validateReadNiftiReportDimensions(IO)];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end

            if NMDataIOImageImportTools.isSurfaceIO(IO)
                [IO, surfMessages] = NMDataIOImageImportTools.readSurfacePayload(IO, progressTask);
                messages = [messages; surfMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                consistencyStage = 'after surface scalar read';
            elseif NMDataIOImageImportTools.isAtlasCollapseMode(IO)
                [IO, collapseMessages] = NMDataIOImageImportTools.readAtlasCollapsePayload(IO);
                messages = [messages; collapseMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                consistencyStage = 'after atlas ROI collapse';
            elseif NMDataIOImageImportTools.isAtlasSplitMode(IO)
                [IO, splitMessages] = NMDataIOImageImportTools.readAtlasSplitPayload(IO);
                messages = [messages; splitMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                consistencyStage = 'after fast atlas ROI split';
            else
                % ReadNifti is a legacy reader whose V/n_subjects contract is
                % internal to the call. Keep modern DataIO case/group state
                % outside that boundary and adapt only the local call view.
                readIO = IO;
                if isfield(readIO,'V') && iscell(readIO.V) && numel(readIO.V) == 1 && ...
                        isfield(readIO,'n_subjects') && isnumeric(readIO.n_subjects) && numel(readIO.n_subjects) > 1 && ...
                        isfield(readIO,'ID') && sum(double(readIO.n_subjects(:))) == numel(readIO.ID) && ...
                        numel(readIO.V{1}) == numel(readIO.ID)
                    readIO.n_samples = 1;
                    readIO.n_subjects = numel(readIO.ID);
                    readIO.n_subjects_all = numel(readIO.ID);
                end
                readIO.Thresh.DataIOProgressTask = progressTask;
                readIO.Thresh.DataIOProgressRows = numel(readIO.ID);
                try
                    readIO = ReadNifti(readIO);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'ReadNifti')];
                    return;
                end

                % Project only the fields written by the supplied ReadNifti implementation.
                IO.PP = readIO.PP;
                IO.Vm = readIO.Vm;
                IO.Y = readIO.Y;
                if isfield(readIO,'Vmvol'), IO.Vmvol = readIO.Vmvol; end
                if isfield(readIO,'Yw'), IO.Yw = readIO.Yw; end
                consistencyStage = 'after ReadNifti';
            end

            messages = [messages; NMDataIOImageImportTools.validateImageIOConsistency(IO, consistencyStage)];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            [IO, postMessages] = NMDataIOImageImportTools.applyPostReadAlignment(IO, targetContainer, importTarget, trainingNM);
            messages = [messages; postMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            messages = [messages; NMDataIOImageImportTools.validateImageIOConsistency(IO, 'after case alignment')];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            [IO, contractMessages] = NMDataIOImageImportTools.finalizeImageTransportContract(IO);
            messages = [messages; contractMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.importReport.imageImport = true;
            IO.importReport.datasource = IO.datasource;
            IO.importReport.globalMode = IO.globalMode;
            IO.importReport.hasWeightingMaps = isfield(IO,'Yw') && ~isempty(IO.Yw);
        end

        function out = imageSummaryFromIO(IO, varind)
            % imageSummaryFromIO  Summarize an imaging IO payload for preview, diagnostics, and report metadata.
            %
            % IO, varind -> out.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2 || isempty(varind), varind = NMDataIOImageImportTools.fieldOr(IO,'varind',1); end
            out = struct();
            out.datasource = NMDataIOImageImportTools.fieldOr(IO,'datasource','nifti');
            out.varind = double(varind);
            out.nImages = double(numel(NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}))));
            out.nCases = NaN;
            if isfield(IO,'ID') && ~isempty(IO.ID), out.nCases = double(numel(IO.ID)); end
            out.nFeatures = NaN;
            if isfield(IO,'Y') && ~isempty(IO.Y)
                if iscell(IO.Y) && ~isempty(IO.Y{1})
                    out.nFeatures = double(size(IO.Y{1},2));
                elseif isnumeric(IO.Y) || islogical(IO.Y)
                    out.nFeatures = double(size(IO.Y,2));
                end
            end
            labels = NMDataIOImageImportTools.fieldOr(IO,'label',[]);
            out.hasLabels = ~isempty(labels);
            out.nLabelTargets = double(size(labels,2));
            if out.hasLabels && strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','')), 'classification')
                out.nLabelTargets = 1;
            end
            covars = NMDataIOImageImportTools.fieldOr(IO,'covars',[]);
            out.hasCovariates = ~isempty(covars);
            out.nCovariates = double(size(covars,2));
            out.maskFile = NMDataIOImageImportTools.fieldOr(IO,'maskFile','');
            out.globalMode = NMDataIOImageImportTools.fieldOr(IO,'globalMode','none');
            out.hasWeightingMaps = isfield(IO,'Yw') && ~isempty(IO.Yw);
            out.importReport = NMDataIOImageImportTools.fieldOr(IO,'importReport',struct());
        end


        function out = imageProbe(NM, state, opts)
            % imageProbe  Run the imaging import probe path without mutating NM.
            %
            % Consumes NM, state, opts; returns out.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'readyToImport',false,'blocking',true,'message','', ...
                'strip',NMDataIOMessageTools.highestPriorityStrip([], 'Not checked.'), ...
                'messages',NMDataIOMessageTools.emptyMessages(), 'summary',struct(), ...
                'probe',struct(), 'preview',struct(), 'stateEcho',state);
            messages = NMDataIOMessageTools.emptyMessages();
            progressTask = NMProgressTools.fromOptions(opts, 'Preparing imaging preview', 'Resolving spatial import settings.');
            try
                progressTask = NMProgressTools.phase(progressTask, 'prepare_image_preview', 0, 10, 'Resolving spatial import settings.');
                [IO, prepMessages] = NMDataIOImageImportTools.prepareImageIO(NM, state, struct('RequireReady', false));
                messages = [messages; prepMessages];
                probe = struct();
                preview = struct();
                preview.rows = struct('index',{},'file',{},'caseId',{},'label',{},'globalValue',{},'covariates',{}, ...
                    'dim',{},'voxelSize',{},'status',{},'statusLevel',{},'statusText',{},'included',{});
                files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}));
                probe.nImages = double(numel(files));
                probe.maskFile = NMDataIOImageImportTools.fieldOr(IO,'maskFile','');
                probe.caseIDMode = NMDataIOImageImportTools.fieldOr(IO,'caseIDMode','legacy_spm');
                probe.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOImageImportTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id'));
                if NMDataIOImageImportTools.isSurfaceIO(IO)
                    progressTask = NMProgressTools.phase(progressTask, 'prepare_surface_preview', 10, 95, 'Preparing surface preview rows.');
                    [out, surfaceMessages, progressTask] = NMDataIOImageImportTools.surfaceProbeFromIO(NM, state, IO, files, messages, progressTask);
                    out.messages = NMDataIOMessageTools.forDiagnosticsPanel([messages; surfaceMessages]);
                    if isfield(out,'ok') && out.ok
                        NMProgressTools.finish(progressTask, 'Surface preview prepared.');
                    else
                        NMProgressTools.finish(progressTask, 'Surface preview completed with diagnostics.');
                    end
                    return;
                end
                if isempty(files)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe', 'No image files were supplied.', 1, 'red*')];
                end
                ids = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'explicitCaseIDs',{}));
                V = [];
                spmFileReports = repmat(struct('input','','resolved','','usedExistingPair',false,'gunzipped',false,'usedCached',false,'cacheReused',false,'cacheRefreshed',false,'message',''), 0, 1);
                if ~isempty(files)
                    progressTask = NMProgressTools.phase(progressTask, 'resolve_image_preview_files', 10, 55, 'Reading image files and reusing previously prepared uncompressed NIfTI copies when available.');
                    [spmFiles, fileMessages, spmFileReports, progressTask] = NMDataIOImageFileTools.resolveNiftiFilesForSPM(files, 'imageProbe.files', true, ...
                        struct('ProgressTask', progressTask, 'ProgressMessage', 'Resolving image file %g of %g.'));
                    messages = [messages; fileMessages];
                    if ~NMDataIOMessageTools.hasFatal(messages)
                        try
                            progressTask = NMProgressTools.phase(progressTask, 'read_image_preview_headers', 55, 75, 'Reading image headers.');
                            V = [];
                            for vi = 1:numel(spmFiles)
                                progressTask = NMProgressTools.step(progressTask, vi, max(numel(spmFiles),1), sprintf('Reading image header %g of %g.', vi, max(numel(spmFiles),1)));
                                Vi = spm_vol(char(spmFiles{vi}));
                                V = [V; Vi(:)]; %#ok<AGROW>
                            end
                            [Vinfo, Vvox] = NMDataIOImageImportTools.volumeInfo(V(:));
                            probe.volumeInfo = Vinfo;
                            probe.voxelSize = Vvox;
                        catch ME
                            messages = [messages; NMDataIOMessageTools.fromException(ME, 'imageProbe.spm_vol')];
                        end
                    end
                    if isempty(ids)
                        [ids, idMessages] = NMDataIOImportTools.deriveCaseIDsFromFiles(files, IO.caseIDMode, 'imageCaseIDs');
                        messages = [messages; idMessages];
                    elseif numel(ids) ~= numel(files)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe', ...
                            sprintf('Number of explicit case IDs (%g) differs from number of image files (%g).', numel(ids), numel(files)), 1, 'red*')];
                    end
                end
                if ~isempty(ids)
                    probe.caseIds = ids(:);
                    [u,~,ic] = unique(ids, 'stable');
                    dup = u(accumarray(ic(:),1)>1);
                    if ~isempty(dup)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe', ...
                            sprintf('Derived image case IDs are not unique: %s.', strjoin(dup(1:min(end,8)), ', ')), 1, 'red*')];
                    end
                else
                    probe.caseIds = {};
                end

                maskFile = NMDataIOImageImportTools.fieldOr(IO,'maskFile','');
                isAtlasSpace = NMDataIOImageImportTools.isAtlasMode(IO);
                mask = struct('file',maskFile,'exists',false,'binary',false,'nVoxels',NaN,'dim',[],'uniqueValues',[],'message','');
                probe.spaceDefType = NMDataIOImageImportTools.fieldOr(IO,'spaceDefType','brainmask');
                probe.atlasImportMode = NMDataIOImageImportTools.fieldOr(IO,'atlasImportMode','voxelwise');
                if ~isempty(maskFile)
                    progressTask = NMProgressTools.phase(progressTask, 'inspect_space_definition', 75, 85, 'Inspecting mask or atlas definition.');
                    mask.exists = exist(maskFile,'file') == 2;
                    if ~mask.exists && exist(regexprep(maskFile, '\.gz$', '', 'ignorecase'),'file') ~= 2
                        if isAtlasSpace
                            missingText = sprintf('Atlas file does not exist and no paired uncompressed .nii was found: %s.', maskFile);
                        else
                            missingText = sprintf('Brainmask file does not exist and no paired uncompressed .nii was found: %s.', maskFile);
                        end
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe.mask', missingText, 1, 'red*')];
                    else
                        [spmMaskFiles, maskMessages, ~, progressTask] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({maskFile}, 'imageProbe.mask', true, ...
                            struct('ProgressTask', progressTask, 'ProgressMessage', 'Resolving mask/atlas file %g of %g.'));
                        messages = [messages; maskMessages];
                        if NMDataIOMessageTools.hasFatal(messages)
                            probe.mask = mask;
                            continueProbe = false;
                        else
                            continueProbe = true;
                        end
                        if continueProbe
                        try
                            Vm = spm_vol(spmMaskFiles{1});
                            Vmvol = spm_read_vols(Vm);
                            finiteVals = Vmvol(isfinite(Vmvol));
                            vals = unique(finiteVals(:));
                            tol = 1e-6;
                            mask.dim = double(Vm.dim);
                            if numel(vals) > 12
                                mask.uniqueValues = vals(1:12)';
                            else
                                mask.uniqueValues = vals(:)';
                            end
                            mask.binary = ~isempty(vals) && all(abs(vals(:)) <= tol | abs(vals(:) - 1) <= tol);
                            if isAtlasSpace
                                atlasVals = vals(isfinite(vals) & vals ~= 0);
                                mask.nVoxels = double(nnz(isfinite(Vmvol) & Vmvol ~= 0));
                                mask.nAtlasLabels = double(numel(atlasVals));
                                mask.binary = false;
                                if isempty(atlasVals)
                                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe.atlas', 'Selected atlas contains no finite non-zero ROI labels.', 1, 'red*')];
                                else
                                    descOpts = struct('roiIDs', double(atlasVals(:)'), 'delimiter', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelDelimiter','auto'), ...
                                        'hasHeader', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelHasHeader','auto'), ...
                                        'idColumn', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelIDColumn',''), ...
                                        'nameColumn', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelNameColumn',''));
                                    labelFile = NMDataIOImageImportTools.fieldOr(IO,'atlasLabelFile','');
                                    if isempty(labelFile)
                                        cand = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(maskFile);
                                        if strcmp(cand.status,'single')
                                            labelFile = cand.files{1};
                                        elseif strcmp(cand.status,'multiple')
                                            messages = [messages; NMDataIOMessageTools.make('warn', false, 'imageProbe.atlasDescriptor', cand.message, 1, 'SystemCommands')];
                                        else
                                            messages = [messages; NMDataIOMessageTools.make('warn', false, 'imageProbe.atlasDescriptor', cand.message, 1, 'SystemCommands')];
                                        end
                                    end
                                    if ~isempty(labelFile)
                                        desc = NMDataIOAtlasDescriptorTools.inspectAtlasDescriptor(maskFile, labelFile, descOpts);
                                        probe.atlasDescriptor = desc;
                                        if isfield(desc,'message') && ~isempty(desc.message)
                                            sev = 'ok'; col = 'green*'; block = false; pr = 0;
                                            if isfield(desc,'matchSummary') && isfield(desc.matchSummary,'status')
                                                if strcmp(desc.matchSummary.status,'none'), sev = 'danger'; col = 'red*'; block = true; pr = 1;
                                                elseif strcmp(desc.matchSummary.status,'partial'), sev = 'warn'; col = 'SystemCommands'; pr = 1; end
                                            end
                                            messages = [messages; NMDataIOMessageTools.make(sev, block, 'imageProbe.atlasDescriptor', desc.message, pr, col)];
                                        end
                                    end
                                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'imageProbe.atlas', ...
                                        sprintf('Atlas accepted for space definition: %g non-zero ROI label(s), %g non-zero voxel(s).', numel(atlasVals), mask.nVoxels), 0, 'green*')];
                                end
                            else
                                mask.nVoxels = double(nnz(abs(Vmvol - 1) <= tol));
                                if ~mask.binary
                                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe.mask', ...
                                        'Selected brainmask is not binary within tolerance 1e-6. Browser/API imaging import accepts finite mask values equivalent to 0/1 only.', 1, 'red*')];
                                elseif mask.nVoxels < 1
                                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe.mask', 'Selected brainmask contains no voxels with value 1.', 1, 'red*')];
                                else
                                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'imageProbe.mask', ...
                                        sprintf('Binary brainmask accepted: %g selected voxel(s).', mask.nVoxels), 0, 'green*')];
                                end
                            end
                        catch ME
                            messages = [messages; NMDataIOMessageTools.fromException(ME, 'imageProbe.mask')];
                        end
                        end
                    end
                else
                    if ~isfield(IO,'oocvflag') || ~IO.oocvflag
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageProbe.mask', 'A brainmask / space-defining image is required for training imaging import.', 1, 'red*')];
                    end
                end
                probe.mask = mask;

                progressTask = NMProgressTools.phase(progressTask, 'resolve_image_preview_metadata', 85, 92, 'Resolving labels, covariates, and case IDs.');
                labels = [];
                covars = [];
                globals = [];
                if ~isempty(ids)
                    IO.ID = ids(:);
                    importTargetProbe = NMDataIOImportTargetTools.normalize(NM, state);
                    [probeTargetContainer, probeTargetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTargetProbe);
                    messages = [messages; probeTargetMessages];
                    if NMDataIOImportTools.hasReferenceCases(NMDataIOImportTools.alignmentReferenceContainer(NM, probeTargetContainer, importTargetProbe))
                        optsAlign = NMDataIOImageImportTools.imageReferenceAlignmentOptions(IO, [], probeTargetContainer, importTargetProbe);
                        optsAlign.referenceLabel = NMDataIOImportTargetTools.caseReferenceLabel(importTargetProbe);
                        [alignedIncomingRows, alignmentReport, alignMessages] = NMDataIOImportTools.alignRowsToReferenceCases((1:numel(ids))', ids, probeTargetContainer.cases, optsAlign, 'probe');
                        messages = [messages; alignMessages];
                        messages = [messages; NMDataIOImageImportTools.referenceCaseImageAlignmentDiagnostics(alignmentReport, ids, probeTargetContainer.cases, 'probe')];
                        probe.caseAlignment = alignmentReport;
                        if isfield(probeTargetContainer,'label') && ~isempty(probeTargetContainer.label) && ~NMDataIOMessageTools.hasFatal(messages)
                            % Added/replaced imaging modalities inherit the
                            % existing NM label axis.  Do not display these
                            % inherited labels as if they were being re-imported
                            % by the current source.
                            probe.labelsInherited = true;
                            probe.labelPreviewSuppressed = true;
                            IO.desc_groups = NMDataIOImageImportTools.fieldOr(probeTargetContainer, 'groupnames', IO.desc_groups);
                        end
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            [IO, roleMessages] = NMDataIOImportTools.materializeConfiguredGlobalRole(IO, IO.ID);
                        else
                            roleMessages = NMDataIOMessageTools.emptyMessages();
                        end
                        messages = [messages; roleMessages];
                        if isfield(probe,'labelsInherited') && probe.labelsInherited
                            if isfield(IO,'label'), IO = rmfield(IO,'label'); end
                            if isfield(IO,'s_label'), IO = rmfield(IO,'s_label'); end
                            if isfield(IO,'L'), IO = rmfield(IO,'L'); end
                        elseif isfield(IO,'label') && ~isempty(IO.label)
                            labels = IO.label;
                        end
                        if isfield(IO,'covars') && ~isempty(IO.covars), covars = IO.covars; end
                    else
                        [IO, groupLabelMessages] = NMDataIOImageImportTools.resolveLegacyGroupLabels(IO);
                        messages = [messages; groupLabelMessages];
                        if ~NMDataIOMessageTools.hasFatal(messages)
                            [IO, roleMessages] = NMDataIOImportTools.materializeConfiguredGlobalRole(IO, IO.ID);
                        else
                            roleMessages = NMDataIOMessageTools.emptyMessages();
                        end
                        messages = [messages; roleMessages];
                        if isfield(IO,'label') && ~isempty(IO.label), labels = IO.label; end
                        if isfield(IO,'covars') && ~isempty(IO.covars), covars = IO.covars; end
                    end
                    if isfield(IO,'g') && ~isempty(IO.g), globals = IO.g; end
                end
                labelGroupNames = {};
                if isfield(IO,'desc_groups') && ~isempty(IO.desc_groups)
                    labelGroupNames = NMDataIOImageImportTools.asCellstr(IO.desc_groups);
                end
                isClassificationPreview = strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','')), 'classification');
                probe.hasLabels = ~isempty(labels);
                probe.nLabelTargets = double(size(labels,2));
                if ~probe.hasLabels && ~isfield(probe,'labelsInherited') && NMDataIOImportTools.hasExplicitLabelAssignment(IO,'?')
                    labelRoles = NMDataIOImageImportTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
                    labelRefs = {};
                    if isstruct(labelRoles) && isfield(labelRoles,'labels'), labelRefs = NMDataIOStateTools.roleRefCell(labelRoles.labels); end
                    probe.hasLabels = ~isempty(labelRefs);
                    probe.nLabelTargets = double(numel(labelRefs));
                    if probe.hasLabels, probe.labelSummary = 'Configured; resolved during Preview.'; end
                end
                if isClassificationPreview && probe.hasLabels, probe.nLabelTargets = 1; end
                if isfield(probe,'labelsInherited') && probe.labelsInherited && isempty(labels)
                    probe.labelSummary = 'Inherited from existing NM case list; not re-imported for this modality.';
                end
                probe.hasCovariates = ~isempty(covars);
                gMode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'globalMode','none')));
                gSource = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'globalSource','user')));
                probe.hasGlobals = ~ismember(gMode, {'','none','no','off'}) && (~isempty(globals) || NMDataIOImportTools.isDerivedGlobalSource(gSource));
                probe.nCovariates = size(covars,2);
                if isfield(IO,'covnames'), probe.covariateNames = IO.covnames; else, probe.covariateNames = {}; end
                probe.globalMode = NMDataIOImageImportTools.fieldOr(IO,'globalMode','none');
                probe.globalSource = NMDataIOImageImportTools.fieldOr(IO,'globalSource','user');
                probe.globalName = NMDataIOImageImportTools.fieldOr(IO,'globalName','GlobalSignal');

                n = max([numel(files), numel(ids), 0]);
                [selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(NMDataIOImageImportTools.fieldOr(IO,'selCases',[]), n, 'imageProbe.selection');
                messages = [messages; selectionMessages];
                IO.selCases = selCases;
                probe.nSelectedImages = double(sum(selCases));
                probe.nExcludedImages = double(numel(selCases) - sum(selCases));
                progressTask = NMProgressTools.phase(progressTask, 'build_image_preview_rows', 92, 98, 'Building imaging preview table.');
                rows = repmat(preview.rows, n, 1);
                for i = 1:n
                    progressTask = NMProgressTools.step(progressTask, i, max(n,1), sprintf('Building preview row %g of %g.', i, max(n,1)));
                    statusLevel = 'ok'; statusText = 'OK';
                    file = ''; if i <= numel(files), file = files{i}; end
                    id = ''; if i <= numel(ids), id = ids{i}; end
                    fileReadable = false;
                    resolvedReadable = false;
                    if ~isempty(file)
                        fileReadable = NMDataIOImageFileTools.existsForSPM(file);
                        if i <= numel(spmFileReports)
                            resolvedReadable = NMDataIOImageFileTools.existsForSPM(spmFileReports(i).resolved);
                        end
                    end
                    if isempty(file) || ~(fileReadable || resolvedReadable)
                        statusLevel = 'danger';
                        statusText = 'missing image file';
                    elseif ~fileReadable && resolvedReadable && i <= numel(spmFileReports)
                        if spmFileReports(i).usedExistingPair
                            statusText = 'OK (using .nii pair)';
                        elseif spmFileReports(i).gunzipped
                            statusText = 'OK (using prepared .nii copy)';
                        else
                            statusText = 'OK (using resolved image file)';
                        end
                    elseif fileReadable && i <= numel(spmFileReports) && spmFileReports(i).gunzipped
                        statusText = 'OK (using prepared .nii copy)';
                    end
                    if isempty(id), statusLevel = 'danger'; statusText = 'missing case ID'; end
                    dstr = ''; vstr = '';
                    if ~isempty(V) && i <= numel(V)
                        try
                            dstr = sprintf('%g×%g×%g', double(V(i).dim(1)), double(V(i).dim(2)), double(V(i).dim(3)));
                            vox = sqrt(sum(V(i).mat(1:3,1:3).^2,1));
                            vstr = sprintf('%.3g×%.3g×%.3g', vox(1), vox(2), vox(3));
                        catch
                            statusLevel = 'warn'; statusText = 'header summary unavailable';
                        end
                    end
                    lbl = '';
                    if ~isempty(labels) && i <= size(labels,1)
                        if isClassificationPreview && isnumeric(labels) && size(labels,2) == 1 && ~isempty(labelGroupNames)
                            idx = double(labels(i,1));
                            if isfinite(idx) && abs(idx - round(idx)) < eps && idx >= 1 && idx <= numel(labelGroupNames) && ...
                                    ~isempty(strtrim(labelGroupNames{round(idx)})) && ~strcmp(strtrim(labelGroupNames{round(idx)}), '?')
                                lbl = labelGroupNames{round(idx)};
                            else
                                lbl = NMDataIOImageImportTools.rowText(labels(i,:));
                            end
                        else
                            lbl = NMDataIOImageImportTools.rowText(labels(i,:));
                        end
                    end
                    glob = '';
                    if ~isempty(globals) && i <= size(globals,1), glob = NMDataIOImageImportTools.rowText(globals(i,:)); end
                    cov = '';
                    if ~isempty(covars) && i <= size(covars,1), cov = NMDataIOImageImportTools.rowText(covars(i,:)); end
                    rows(i).index = i;
                    rows(i).file = file;
                    rows(i).caseId = id;
                    rows(i).label = lbl;
                    rows(i).globalValue = glob;
                    rows(i).covariates = cov;
                    rows(i).dim = dstr;
                    rows(i).voxelSize = vstr;
                    rows(i).status = statusText;
                    rows(i).statusLevel = statusLevel;
                    rows(i).statusText = statusText;
                    rows(i).included = i <= numel(selCases) && logical(selCases(i));
                end
                preview.rows = rows;
                preview.nRows = n;
                strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Imaging import check completed.');
                out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
                out.summary = NMDataIOMessageTools.summarize(messages);
                out.strip = strip;
                out.message = strip.text;
                out.blocking = strip.blocking;
                out.readyToImport = ~strip.blocking;
                out.ok = ~strip.blocking;
                out.probe = probe;
                out.preview = preview;
                if out.ok
                    NMProgressTools.finish(progressTask, 'Imaging preview prepared.');
                else
                    NMProgressTools.finish(progressTask, 'Imaging preview completed with diagnostics.');
                end
            catch ME
                NMProgressTools.fail(progressTask, 'NMDataIOImageImportTools.imageProbe', ME);
                messages = NMDataIOMessageTools.fromException(ME, 'NMDataIOImageImportTools.imageProbe');
                strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'Imaging import check failed.');
                out.messages = messages;
                out.summary = NMDataIOMessageTools.summarize(messages);
                out.strip = strip;
                out.message = strip.text;
                out.blocking = true;
                out.readyToImport = false;
                out.ok = false;
            end
        end

        function [out, messages, progressTask] = surfaceProbeFromIO(NM, state, IO, files, messagesIn, progressTask)
            % surfaceProbeFromIO  Run the surface-import probe path from an already prepared imaging IO struct.
            %
            % Consumes NM, state, IO, files, messagesIn, progressTask; returns out, messages, progressTask.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 5 || isempty(messagesIn), messagesIn = NMDataIOMessageTools.emptyMessages(); end
            if nargin < 6 || isempty(progressTask) || ~isstruct(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            messages = NMDataIOMessageTools.emptyMessages();
            probe = struct();
            probe.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                NMDataIOImageImportTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id'));
            preview = struct();
            preview.rows = struct('index',{},'file',{},'caseId',{},'label',{},'globalValue',{},'covariates',{}, ...
                'dim',{},'voxelSize',{},'status',{},'statusLevel',{},'statusText',{},'included',{});
            if NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO)
                progressTask = NMProgressTools.phase(progressTask, 'prepare_surface_native_roi_preview', 10, 95, 'Preparing native-ROI surface preview rows.');
                [out, messages] = NMDataIOImageImportTools.surfaceNativeRoiProbeFromIO(NM, state, IO, messagesIn);
                progressTask = NMProgressTools.step(progressTask, 1, 1, 'Native-ROI surface preview prepared.', true);
                return;
            end
            ids = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'explicitCaseIDs',{}));
            if isempty(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceProbe.files', 'No surface scalar files were supplied.', 1, 'red*')];
            elseif isempty(ids)
                [ids, idMessages] = NMDataIOImportTools.deriveCaseIDsFromFiles(files, IO.caseIDMode, 'imageCaseIDs');
                messages = [messages; idMessages];
            elseif numel(ids) ~= numel(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceProbe.files', ...
                    sprintf('Number of explicit case IDs (%g) differs from number of surface files (%g).', numel(ids), numel(files)), 1, 'red*')];
            end
            metas = repmat(struct('file','','format','','nVertices',NaN,'dataSize',[],'nFinite',NaN,'nNaN',NaN,'minValue',NaN,'maxValue',NaN), numel(files), 1);
            readErrorText = repmat({''}, numel(files), 1);
            nVertices = NaN;
            if ~isempty(files)
                progressTask = NMProgressTools.phase(progressTask, 'read_surface_preview_metadata', 10, 45, 'Reading surface scalar metadata.');
                for i = 1:numel(files)
                    progressTask = NMProgressTools.step(progressTask, i, max(numel(files),1), sprintf('Reading surface scalar metadata %g of %g.', i, max(numel(files),1)), true);
                    try
                        [~, meta] = NMDataIOSurfaceTools.readSurfaceScalar(files{i});
                        metas(i) = meta;
                        if i == 1
                            nVertices = meta.nVertices;
                        end
                    catch ME
                        readErrorText{i} = ME.message;
                        messages = [messages; NMDataIOMessageTools.fromException(ME, sprintf('surfaceProbe.read[%g]', i))];
                    end
                end
            end
            finiteVertexCounts = double([metas.nVertices]);
            finiteVertexCounts = finiteVertexCounts(isfinite(finiteVertexCounts));
            uniqueVertexCounts = unique(finiteVertexCounts(:)');
            surfaceVertexMismatch = numel(uniqueVertexCounts) > 1;
            if surfaceVertexMismatch
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceProbe.vertexCount', ...
                    sprintf(['Surface vertex-space mismatch: selected files are readable but have different vertex counts ', ...
                             '(range %g-%g; %g distinct counts across %g file(s)). Vertexwise surface import requires ', ...
                             'a common template mesh such as fsaverage, fsaverage6, fsaverage5, CAT12 template surface, ', ...
                             'or a declared custom shared template. These files likely remain in native subject space. ', ...
                             'Resample/register surfaces outside DataIO or use the later ROI-based surface import.'], ...
                             min(uniqueVertexCounts), max(uniqueVertexCounts), numel(uniqueVertexCounts), numel(finiteVertexCounts)), 1, 'red*')];
            end
            weightFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'weightingFiles',{}));
            weightMetas = repmat(struct('file','','format','','nVertices',NaN,'dataSize',[],'nFinite',NaN,'nNaN',NaN,'minValue',NaN,'maxValue',NaN), numel(weightFiles), 1);
            if ~isempty(weightFiles)
                progressTask = NMProgressTools.phase(progressTask, 'read_surface_weighting_metadata', 45, 55, 'Reading surface weighting/ranking metadata.');
                for w = 1:numel(weightFiles)
                    progressTask = NMProgressTools.step(progressTask, w, max(numel(weightFiles),1), sprintf('Reading surface weighting/ranking map %g of %g.', w, max(numel(weightFiles),1)), true);
                    try
                        [~, wmeta] = NMDataIOSurfaceTools.readSurfaceScalar(weightFiles{w});
                        weightMetas(w) = wmeta;
                        if isfinite(nVertices) && wmeta.nVertices ~= nVertices
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceWeighting.vertexCount', ...
                                sprintf('Surface weighting/ranking map %g has %g vertices, but imported surface files have %g vertices: %s', w, wmeta.nVertices, nVertices, weightFiles{w}), 1, 'red*')]; %#ok<AGROW>
                        end
                    catch ME
                        messages = [messages; NMDataIOMessageTools.fromException(ME, sprintf('surfaceWeighting.read[%g]', w))]; %#ok<AGROW>
                    end
                end
                if ~NMDataIOMessageTools.hasFatal(messages)
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'surfaceWeighting.probe', ...
                        sprintf('Surface weighting/ranking maps accepted for registered vertexwise import: %g map(s).', numel(weightFiles)), 0, 'green*')];
                end
            end
            if ~isempty(ids)
                probe.caseIds = ids(:);
                [u,~,ic] = unique(ids, 'stable');
                dup = u(accumarray(ic(:),1)>1);
                if ~isempty(dup)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceProbe.caseIds', ...
                        sprintf('Derived surface case IDs are not unique: %s.', strjoin(dup(1:min(end,8)), ', ')), 1, 'red*')];
                end
            else
                probe.caseIds = {};
            end
            if ~isempty(ids)
                progressTask = NMProgressTools.phase(progressTask, 'align_surface_preview_cases', 55, 75, 'Validating surface case alignment and metadata roles.');
                IO.ID = ids(:);
                importTargetProbe = NMDataIOImportTargetTools.normalize(NM, state);
                [probeTargetContainer, probeTargetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTargetProbe);
                messages = [messages; probeTargetMessages];
                if NMDataIOImportTools.hasReferenceCases(NMDataIOImportTools.alignmentReferenceContainer(NM, probeTargetContainer, importTargetProbe))
                    optsAlign = NMDataIOImageImportTools.imageReferenceAlignmentOptions(IO, [], probeTargetContainer, importTargetProbe);
                    optsAlign.referenceLabel = NMDataIOImportTargetTools.caseReferenceLabel(importTargetProbe);
                    [~, alignmentReport, alignMessages] = NMDataIOImportTools.alignRowsToReferenceCases((1:numel(ids))', ids, probeTargetContainer.cases, optsAlign, 'probe');
                    messages = [messages; alignMessages];
                    messages = [messages; NMDataIOImageImportTools.referenceCaseImageAlignmentDiagnostics(alignmentReport, ids, probeTargetContainer.cases, 'probe')];
                    probe.caseAlignment = alignmentReport;
                    if isfield(probeTargetContainer,'label') && ~isempty(probeTargetContainer.label) && ~NMDataIOMessageTools.hasFatal(messages)
                        probe.labelsInherited = true;
                        probe.labelPreviewSuppressed = true;
                        IO.desc_groups = NMDataIOImageImportTools.fieldOr(probeTargetContainer, 'groupnames', IO.desc_groups);
                    end
                    if ~NMDataIOMessageTools.hasFatal(messages)
                        [IO, roleMessages] = NMDataIOImportTools.materializeConfiguredGlobalRole(IO, IO.ID);
                    else
                        roleMessages = NMDataIOMessageTools.emptyMessages();
                    end
                    messages = [messages; roleMessages];
                    if isfield(probe,'labelsInherited') && probe.labelsInherited
                        if isfield(IO,'label'), IO = rmfield(IO,'label'); end
                        if isfield(IO,'s_label'), IO = rmfield(IO,'s_label'); end
                        if isfield(IO,'L'), IO = rmfield(IO,'L'); end
                    end
                else
                    [IO, groupLabelMessages] = NMDataIOImageImportTools.resolveLegacyGroupLabels(IO);
                    messages = [messages; groupLabelMessages];
                    if ~NMDataIOMessageTools.hasFatal(messages)
                        [IO, roleMessages] = NMDataIOImportTools.materializeConfiguredGlobalRole(IO, IO.ID);
                    else
                        roleMessages = NMDataIOMessageTools.emptyMessages();
                    end
                    messages = [messages; roleMessages];
                end
            end
            labels = [];
            if isfield(IO,'label') && ~isempty(IO.label), labels = IO.label; end
            covars = [];
            if isfield(IO,'covars') && ~isempty(IO.covars), covars = IO.covars; end
            globals = [];
            if isfield(IO,'g') && ~isempty(IO.g), globals = IO.g; end
            [selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(NMDataIOImageImportTools.fieldOr(IO,'selCases',[]), max(numel(files),numel(ids)), 'surfaceProbe.selection');
            messages = [messages; selectionMessages];
            n = max([numel(files), numel(ids), 0]);
            rows = repmat(preview.rows, n, 1);
            progressTask = NMProgressTools.phase(progressTask, 'build_surface_preview_rows', 75, 95, 'Building surface preview rows.');
            for i = 1:n
                progressTask = NMProgressTools.step(progressTask, i, max(n,1), sprintf('Building surface preview row %g of %g.', i, max(n,1)), true);
                statusLevel = 'ok'; statusText = 'OK';
                file = ''; if i <= numel(files), file = files{i}; end
                id = ''; if i <= numel(ids), id = ids{i}; end
                if isempty(file) || exist(file,'file') ~= 2
                    statusLevel = 'danger'; statusText = 'missing surface file';
                elseif i <= numel(readErrorText) && ~isempty(readErrorText{i})
                    statusLevel = 'danger';
                    statusText = sprintf('surface read failed: %s', readErrorText{i});
                elseif i <= numel(metas) && isfinite(metas(i).nVertices)
                    if exist('surfaceVertexMismatch','var') && surfaceVertexMismatch
                        statusLevel = 'danger';
                        statusText = sprintf('vertex-space mismatch (%s, %g vertices)', metas(i).format, metas(i).nVertices);
                    else
                        statusText = sprintf('OK (%s, %g vertices)', metas(i).format, metas(i).nVertices);
                    end
                else
                    statusLevel = 'danger';
                    statusText = 'surface scalar metadata could not be read';
                end
                if isempty(id), statusLevel = 'danger'; statusText = 'missing case ID'; end
                rows(i).index = i;
                rows(i).file = file;
                rows(i).caseId = id;
                rows(i).label = '';
                if ~isempty(labels) && i <= size(labels,1), rows(i).label = NMDataIOImageImportTools.rowText(labels(i,:)); end
                rows(i).globalValue = '';
                if ~isempty(globals) && i <= size(globals,1), rows(i).globalValue = NMDataIOImageImportTools.rowText(globals(i,:)); end
                rows(i).covariates = '';
                if ~isempty(covars) && i <= size(covars,1), rows(i).covariates = NMDataIOImageImportTools.rowText(covars(i,:)); end
                rows(i).dim = sprintf('%g vertices', metas(i).nVertices);
                rows(i).voxelSize = metas(i).format;
                rows(i).status = statusText;
                rows(i).statusLevel = statusLevel;
                rows(i).statusText = statusText;
                rows(i).included = i <= numel(selCases) && logical(selCases(i));
            end
            preview.rows = rows;
            preview.nRows = n;
            probe.nImages = double(numel(files));
            probe.datasource = 'surf';
            probe.sourceType = 'surface-list';
            probe.nVertices = double(nVertices);
            probe.surfaceFormats = unique(NMDataIOSurfaceTools.surfaceFormats(files), 'stable');
            probe.surfaceMetadata = metas;
            probe.surfaceImportMode = NMDataIOImageImportTools.fieldOr(IO,'surfaceImportMode','vertex_template');
            probe.surfaceTemplate = NMDataIOImageImportTools.fieldOr(IO,'surfaceTemplate','unknown');
            probe.surfaceHemisphere = NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto');
            probe.surfaceGeometryFile = NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryFile', NMDataIOImageImportTools.fieldOr(IO,'surfaceDisplayMeshFile',''));
            probe.surfaceInflatedGeometryFile = NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryFile','');
            if ~NMDataIOMessageTools.hasFatal(messages)
                [IO, geometryMessages] = NMDataIOImageImportTools.validateSurfaceGeometryIO(IO,nVertices);
                messages = [messages; geometryMessages];
                if isfield(IO,'surfaceGeometryContract') && isstruct(IO.surfaceGeometryContract)
                    probe.surfaceGeometryContract = IO.surfaceGeometryContract;
                end
            end
            probe.nWeightingMaps = double(numel(weightFiles));
            probe.hasWeightingMaps = ~isempty(weightFiles);
            probe.weightingMapMode = 'surface_vertex_template';
            probe.surfaceWeightingMetadata = weightMetas;
            if ~NMDataIOMessageTools.hasFatal(messages) && ~isempty(files)
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'surfaceProbe', ...
                    sprintf('Surface scalar stream accepted: %g file(s), %g vertex feature(s), format(s): %s.', numel(files), nVertices, strjoin(probe.surfaceFormats, ', ')), 0, 'green*')];
            end
            allMessages = [messagesIn; messages];
            strip = NMDataIOMessageTools.highestPriorityStrip(allMessages, 'Surface import check completed.');
            out = struct('ok',~strip.blocking,'readyToImport',~strip.blocking,'blocking',strip.blocking, ...
                'message',strip.text,'strip',strip,'messages',NMDataIOMessageTools.forDiagnosticsPanel(allMessages), ...
                'summary',NMDataIOMessageTools.summarize(allMessages),'probe',probe,'preview',preview,'stateEcho',state);
        end

        function opts = imageReferenceAlignmentOptions(IO, opts, referenceContainer, importTarget)
            % imageReferenceAlignmentOptions  Collect case-alignment options for image/OOCV import against a reference container.
            %
            % Consumes IO, opts, referenceContainer, importTarget; returns opts.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
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
            if nargin < 4, importTarget = struct(); end
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
            % Imaging modalities may encode the shared subject key in different
            % positions (case ID, filename stem, full path, or parent folders).
            % Use a strict unique shared-key matcher as the imaging analogue of
            % metadata abbreviated-ID matching; ambiguous keys remain unmapped.
            opts.mappingApproved = true;
            if ~isfield(opts,'referenceLabel') || isempty(opts.referenceLabel)
                opts.referenceLabel = 'existing NM cases';
            end
            opts.incomingEvidence = NMDataIOImageImportTools.imageCaseEvidenceRows(IO, []);
            if isstruct(referenceContainer) && isfield(referenceContainer,'cases') && ~isempty(referenceContainer.cases)
                opts.referenceEvidence = NMDataIOImageImportTools.referenceCaseEvidenceRows(referenceContainer, referenceContainer.cases, importTarget);
            end
        end

        function messages = referenceCaseImageAlignmentDiagnostics(report, incomingIDs, referenceIDs, stage)
            % referenceCaseImageAlignmentDiagnostics  Convert image case-alignment reports into structured warning/error messages.
            %
            % Consumes report, incomingIDs, referenceIDs, stage; returns messages.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4 || isempty(stage), stage = 'image import'; end
            if isempty(report) || ~isstruct(report), return; end
            nMatched = NMDataIOImageImportTools.fieldOr(report, 'nMatchedCases', 0);
            nReference = NMDataIOImageImportTools.fieldOr(report, 'nReferenceCases', numel(referenceIDs));
            nIncoming = NMDataIOImageImportTools.fieldOr(report, 'nIncomingCases', numel(incomingIDs));
            mappingMode = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(report, 'mappingMode', 'direct'));
            if nReference > 0 && nIncoming > 0 && nMatched == 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageCaseAlignment', ...
                    sprintf(['No usable overlap was found between incoming image case IDs and existing NM cases during %s. ', ...
                             'Incoming examples: %s. Existing case examples: %s. Automatic detection checks exact IDs ', ...
                             'and unique shared keys extracted from case IDs, file names, and folder/path components.'], ...
                             char(string(stage)), NMDataIOImageImportTools.shortCaseIDList(incomingIDs, 5), ...
                             NMDataIOImageImportTools.shortCaseIDList(referenceIDs, 5)), 1, 'red*')];
                return;
            end
            if any(strcmpi(mappingMode, {'shared_key','numeric_suffix'})) && nMatched > 0
                exampleClause = NMDataIOImageImportTools.sharedKeyMatchExampleClause(report);
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'imageCaseAlignment', ...
                    sprintf(['Incoming image case IDs did not exactly match existing NM cases; a unique shared-key ', ...
                             'match was inferred automatically (%g/%g existing case(s) matched).%s Verify that this cross-modality abbreviated-ID mapping is intended.'], ...
                             nMatched, nReference, exampleClause), 2, 'SystemCommands')];
            end
        end

        function [factors, messages] = proportionalGlobalScaleFactors(globalValues, globalMultiplier, nSubjects, context)
            % proportionalGlobalScaleFactors  Compute the single authoritative proportional global-volume scale vector.
            %
            % Purpose:
            %   Convert one finite positive global value per subject into the multiplicative factors used
            %   by volumetric import, volumetric image QC and volumetric ROI import.
            % Inputs:
            %   globalValues - subject-aligned global brain-volume/intensity vector.
            %   globalMultiplier - finite positive target multiplier (legacy globnorm semantics).
            %   nSubjects - expected subject count. context - diagnostic message namespace.
            % Output: factors, an nSubjects-by-1 vector equal to globalMultiplier ./ globalValues.
            % Authority and flow:
            %   This is the sole NM2 arithmetic authority for proportional global scaling. Callers own
            %   provenance eligibility and case alignment; this function owns only validation and factors.
            % Invariants:
            %   Exactly one finite strictly positive global value is required per subject. No zero/nonfinite
            %   replacement or fallback-to-one behavior is permitted.
            % Materialization and performance:
            %   Pure O(N) resident-vector arithmetic. Reads no files and is safe during explicit preparation;
            %   interactive consumers should use already corrected/materialized feature data.
            % Failure semantics: invalid shape/value/multiplier returns a blocking structured message.
            if nargin < 4 || isempty(context), context = 'globals.proportional'; end
            messages = NMDataIOMessageTools.emptyMessages();
            factors = [];
            g = double(globalValues(:));
            GM = double(globalMultiplier);
            if numel(g) ~= nSubjects
                messages = [messages; NMDataIOMessageTools.make('danger', true, context, ...
                    sprintf('Global vector length (%g) differs from subject count (%g).', numel(g), nSubjects), 1, 'red*')];
                return;
            end
            if any(~isfinite(g)) || any(g <= 0)
                messages = [messages; NMDataIOMessageTools.make('danger', true, context, ...
                    'Proportional global scaling requires one finite strictly positive global value per subject.', 1, 'red*')];
                return;
            end
            if ~isscalar(GM) || ~isfinite(GM) || GM <= 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, context, ...
                    'Global multiplier must be one finite strictly positive scalar.', 1, 'red*')];
                return;
            end
            factors = GM ./ g;
        end

    end

    methods (Static, Access = private)

        function rows = imageCaseEvidenceRows(IO, nRows)
            if nargin < 2 || isempty(nRows)
                nRows = 0;
                probeFields = {'ID','imageFilesSpec','imageFiles','files','PP','PPspm','explicitCaseIDs'};
                for k = 1:numel(probeFields)
                    if isstruct(IO) && isfield(IO,probeFields{k}) && ~isempty(IO.(probeFields{k}))
                        vals = NMDataIOImageImportTools.asCellstr(IO.(probeFields{k}));
                        if numel(vals) > nRows, nRows = numel(vals); end
                    end
                end
            end
            rows = repmat({''}, double(nRows), 1);
            if nRows < 1, return; end
            fields = {'ID','imageFilesSpec','imageFiles','files','PP','PPspm','explicitCaseIDs'};
            for k = 1:numel(fields)
                if ~isstruct(IO) || ~isfield(IO,fields{k}) || isempty(IO.(fields{k})), continue; end
                vals = NMDataIOImageImportTools.asCellstr(IO.(fields{k}));
                if numel(vals) ~= nRows, continue; end
                for i = 1:nRows
                    rows{i} = strtrim(sprintf('%s %s', rows{i}, vals{i}));
                end
            end
        end

        function rows = referenceCaseEvidenceRows(container, referenceCases, importTarget)
            referenceCases = NMDataIOImageImportTools.asCellstr(referenceCases);
            nRows = numel(referenceCases);
            rows = referenceCases(:);
            if nRows < 1 || ~isstruct(container), return; end
            if nargin < 3, importTarget = struct(); end
            preferredVarind = [];
            if isstruct(importTarget) && isfield(importTarget,'varind') && ~isempty(importTarget.varind)
                preferredVarind = double(importTarget.varind);
            end
            if isfield(container,'datadescriptor') && iscell(container.datadescriptor)
                % The reference case order is defined by the existing container.
                % Evidence can come from any already imported modality whose
                % stored image file list has the same row count; this enables
                % matching on shared subject folders when the case key is not in
                % the basename. Prefer modalities other than the one currently
                % being added, but do not depend on modality #1 specifically.
                order = 1:numel(container.datadescriptor);
                if ~isempty(preferredVarind)
                    order = [setdiff(order, preferredVarind, 'stable') intersect(order, preferredVarind, 'stable')];
                end
                for jj = 1:numel(order)
                    m = order(jj);
                    dd = container.datadescriptor{m};
                    if ~isstruct(dd) || ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings), continue; end
                    rows = NMDataIOImageImportTools.appendInputSettingsEvidenceRows(rows, dd.input_settings, nRows);
                end
            end
        end

        function rows = appendInputSettingsEvidenceRows(rows, inputSettings, nRows)
            fields = {'caseIds','caseIDSpec','explicitCaseIDs','imageFiles','imageFilesSpec','files','PP'};
            for k = 1:numel(fields)
                if ~isfield(inputSettings,fields{k}) || isempty(inputSettings.(fields{k})), continue; end
                vals = NMDataIOImageImportTools.asCellstr(inputSettings.(fields{k}));
                if numel(vals) ~= nRows, continue; end
                for i = 1:nRows
                    rows{i} = strtrim(sprintf('%s %s', rows{i}, vals{i}));
                end
            end
        end

        function clause = sharedKeyMatchExampleClause(report)
            clause = '';
            if ~isstruct(report) || ~isfield(report,'matchExamples') || isempty(report.matchExamples)
                return;
            end
            ex = report.matchExamples;
            if isstruct(ex) && numel(ex) >= 1
                key = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(ex(1),'key',''));
                ref = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(ex(1),'referenceCase',''));
                inc = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(ex(1),'incomingCase',''));
                if ~isempty(key) && ~isempty(ref) && ~isempty(inc)
                    clause = sprintf(' Example: key ''%s'' matched incoming image case ''%s'' to existing NM case ''%s''.', key, inc, ref);
                end
            end
        end


        function M2 = alignMatrixByIncomingRows(M, alignedIncomingRows)
            alignedIncomingRows = double(alignedIncomingRows(:));
            nRef = numel(alignedIncomingRows);
            if isempty(M)
                M2 = M;
                return;
            end
            if ~(isnumeric(M) || islogical(M))
                M2 = M;
                return;
            end
            M2 = nan(nRef, size(M,2));
            valid = isfinite(alignedIncomingRows) & alignedIncomingRows >= 1 & alignedIncomingRows <= size(M,1);
            if any(valid)
                M2(valid,:) = M(alignedIncomingRows(valid),:);
            end
        end

        function [cells2, report] = alignCellsByIncomingRows(cells, alignedIncomingRows)
            cells = NMDataIOImageImportTools.asCellstr(cells);
            alignedIncomingRows = double(alignedIncomingRows(:));
            nRef = numel(alignedIncomingRows);
            cells2 = repmat({''}, nRef, 1);
            valid = isfinite(alignedIncomingRows) & alignedIncomingRows >= 1 & alignedIncomingRows <= numel(cells);
            if any(valid)
                cells2(valid) = cells(alignedIncomingRows(valid));
            end
            report = struct('matched',valid,'alignedIncomingRows',alignedIncomingRows);
        end

        function [IO, messages] = applyImageTargetContext(IO, targetContainer, importTarget, trainingNM)
            % applyImageTargetContext  Apply the training imaging/surface scientific contract to an OOCV import.
            %
            % Purpose:
            %   Preserve training/OOCV feature-space parity before image/surface source materialization.
            %   OOCV subject files and subject-specific metadata remain independent inputs; spatial,
            %   surface, weighting and global-correction semantics are inherited from training.
            %
            % Authority and flow:
            %   trainingNM.datadescriptor{varind}.input_settings plus persisted atlas/surface
            %   provenance are authoritative. The browser projects the same settings into controls,
            %   but this method reapplies them at the image-import owner boundary so direct API calls
            %   cannot redefine scientific state.
            %
            % Scientific/state contract:
            %   Volumetric and surface feature families cannot be interchanged. Training masks,
            %   atlas mode/descriptor, threshold semantics, surface template/hemisphere/geometry,
            %   global mode/name/multiplier and weighting policy remain fixed. OOCV global values,
            %   case IDs and subject data files remain OOCV-specific. Weighting maps are never
            %   supplied independently for OOCV because the fitted feature-space contract is training-owned.
            %
            % Materialization and performance:
            %   This method itself reads no files, parses no XML and scans no voxel/vertex arrays.
            %   Existing downstream mask/atlas/surface materializers may read the inherited references.
            %   It is an explicit import/probe preparation boundary, not an interactive navigation path.
            %
            % Failure semantics:
            %   A volumetric/surface family mismatch or missing training spatial definition returns a
            %   blocking DataIO diagnostic. Scientific settings are overwritten from training, never guessed.
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOImportTargetTools.isOOCV(importTarget)
                IO.oocvflag = true;
                IO.labels_known = logical(importTarget.labels_known);
                v = importTarget.varind;
                if isfield(trainingNM,'modeflag') && ~isempty(trainingNM.modeflag), IO.modeflag = trainingNM.modeflag; end
                if isfield(trainingNM,'groupnames') && ~isempty(trainingNM.groupnames), IO.desc_groups = trainingNM.groupnames; end
                if IO.labels_known && strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','classification')),'classification')
                    IO.trainingClassificationLabelMap = NMDataIOImportTools.trainingClassificationLabelMap(trainingNM);
                end
                dd = struct();
                trainingSource = '';
                if isfield(trainingNM,'datadescriptor') && numel(trainingNM.datadescriptor) >= v && isstruct(trainingNM.datadescriptor{v})
                    dd = trainingNM.datadescriptor{v};
                    if isfield(dd,'source') && ~isempty(dd.source), trainingSource = lower(NMDataIOImageImportTools.asChar(dd.source)); end
                    if isfield(dd,'input_settings') && isstruct(dd.input_settings)
                        base = dd.input_settings;
                        if isfield(base,'datasource') && ~isempty(base.datasource), trainingSource = lower(NMDataIOImageImportTools.asChar(base.datasource)); end
                        trainingIsSurface = strcmp(trainingSource,'surf') || (isfield(dd,'surfaceRoiCollapse') && logical(dd.surfaceRoiCollapse));
                        incomingIsSurface = NMDataIOImageImportTools.isSurfaceIO(IO);
                        trainingIsImaging = trainingIsSurface || any(strcmp(trainingSource, {'nifti','spm','image'})) || ...
                            (isfield(base,'spaceDefType') && ~isempty(base.spaceDefType)) || ...
                            (isfield(dd,'atlasCollapse') && logical(dd.atlasCollapse)) || ...
                            (isfield(dd,'atlasSplit') && logical(dd.atlasSplit));
                        if trainingIsImaging && incomingIsSurface ~= trainingIsSurface
                            incomingFamily = 'volumetric';
                            if incomingIsSurface, incomingFamily = 'surface'; end
                            trainingFamily = 'volumetric';
                            if trainingIsSurface, trainingFamily = 'surface'; end
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageTargetContext.featureFamily', ...
                                sprintf('OOCV modality %g uses a %s source, but the trained scientific feature family is %s. Source files may differ, but volumetric and surface feature spaces are not interchangeable.', ...
                                double(v), incomingFamily, trainingFamily), 1, 'red*')];
                            return;
                        end
                        % Scientific parity is inherited from the trained modality; only
                        % subject data sources remain OOCV-specific.  Apply the trained
                        % spatial/surface contract unconditionally so API callers cannot
                        % override the browser's locked scientific controls.
                        scientificFields = {'Thresh','threshop','threshval','threshlabels','Vm','Vmvol','brainmask','maskFile','badcoords','spaceDefType','atlasImportMode','atlasCollapseMethod','excludeSubjectZeros', ...
                            'atlasLabelNames','atlasLabelFile','atlasLabelDelimiter','atlasLabelHasHeader','atlasLabelIDColumn','atlasLabelNameColumn', ...
                            'surfaceImportMode','surfaceTemplate','surfaceHemisphere','surfaceGeometryFile','surfaceInflatedGeometryFile', ...
                            'surfaceGeometryIdentity','surfaceInflatedGeometryIdentity','surfaceTopologyIdentity','surfaceVertexOrderIdentity', ...
                            'surfaceInflatedValidated','surfaceGeometryContract','surfaceRoiCollapseMethod'};
                        for k = 1:numel(scientificFields)
                            if isfield(base,scientificFields{k}) && ~isempty(base.(scientificFields{k}))
                                IO.(scientificFields{k}) = base.(scientificFields{k});
                            end
                        end
                        if isfield(base,'uiGlobalModeSelection') && ~isempty(base.uiGlobalModeSelection)
                            IO.uiGlobalModeSelection = base.uiGlobalModeSelection;
                        elseif isfield(base,'globalMode') && ~isempty(base.globalMode)
                            IO.uiGlobalModeSelection = base.globalMode;
                        else
                            IO.uiGlobalModeSelection = 'none';
                        end
                        IO.globalMode = IO.uiGlobalModeSelection;
                        if isfield(base,'globalSource') && ~isempty(base.globalSource), IO.globalSource = base.globalSource; end
                        if isfield(base,'globalName') && ~isempty(base.globalName), IO.globalName = base.globalName; end
                        if isfield(base,'globnorm') && ~isempty(base.globnorm), IO.globnorm = base.globnorm; end
                        % OOCV does not define a second weighting/ranking feature space.
                        % Model-side weighting remains the persisted training contract.
                        IO.weightingFiles = {};
                        IO.Pw = [];
                        IO.Vw = [];
                        IO.Yw = [];
                    end
                    if isfield(dd,'Vm') && ~isempty(dd.Vm) && (~isfield(IO,'Vm') || isempty(IO.Vm)), IO.Vm = dd.Vm; end
                    if isfield(dd,'Vmvol') && ~isempty(dd.Vmvol) && (~isfield(IO,'Vmvol') || isempty(IO.Vmvol)), IO.Vmvol = dd.Vmvol; end
                    if isfield(dd,'atlasSplitProvenance') && isstruct(dd.atlasSplitProvenance)
                        IO.atlasSplitTrainingProvenance = dd.atlasSplitProvenance;
                    end
                    if isfield(dd,'atlasCollapseProvenance') && isstruct(dd.atlasCollapseProvenance)
                        IO.atlasCollapseTrainingProvenance = dd.atlasCollapseProvenance;
                    end
                    if isfield(dd,'threshop') && isfield(dd,'threshval') && ~isfield(IO,'Thresh')
                        thop = dd.threshop;
                        if ~iscell(thop), thop = {thop}; end
                        IO.Thresh = struct('nVml',1,'Vml',dd.threshval,'Lm',{{'Inherited training mask'}},'threshop',{thop});
                    end
                end
                if isfield(trainingNM,'brainmask') && numel(trainingNM.brainmask) >= v && ~isempty(trainingNM.brainmask{v})
                    IO.brainmask = trainingNM.brainmask{v};
                end
                if isfield(trainingNM,'badcoords') && numel(trainingNM.badcoords) >= v && ~isempty(trainingNM.badcoords{v})
                    IO.badcoords = trainingNM.badcoords{v};
                end
                if NMDataIOImageImportTools.isSurfaceIO(IO)
                    surfaceDescriptor = strcmp(trainingSource,'surf') || (isstruct(dd) && isfield(dd,'surfaceRoiCollapse') && logical(dd.surfaceRoiCollapse));
                    if ~surfaceDescriptor
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceTargetContext', ...
                            sprintf('OOCV surface import for modality %g cannot proceed because the matching training modality is not marked as a surface feature space.', double(v)), 1, 'red*')];
                        return;
                    end
                else
                    if (~isfield(IO,'Vm') || isempty(IO.Vm)) && (~isfield(IO,'maskFile') || isempty(IO.maskFile))
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageTargetContext', ...
                            sprintf('OOCV imaging import for modality %g cannot proceed because the training modality has no stored space-defining image metadata.', double(v)), 1, 'red*')];
                        return;
                    end
                end
            end

            if ~NMDataIOImageImportTools.isSurfaceIO(IO) && (~isfield(IO,'Vm') || isempty(IO.Vm)) && ~isempty(IO.maskFile)
                [spmMaskFiles, maskMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({IO.maskFile}, 'imageMask', true);
                messages = [messages; maskMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                try
                    IO.brainmask = IO.maskFile;
                    IO.maskFileSPM = spmMaskFiles{1};
                    IO.Vm = spm_vol(IO.maskFileSPM);
                    IO.Vmvol = spm_read_vols(IO.Vm);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'imageMask.spm_vol')];
                    return;
                end
            end
            if ~isfield(IO,'Thresh') || isempty(IO.Thresh)
                IO.Thresh = NMDataIOImageImportTools.thresholdStruct(IO);
            end
            if ~NMDataIOImageImportTools.isSurfaceIO(IO)
                [IO, atlasMessages] = NMDataIOImageImportTools.configureAtlasSpaceDefinition(IO);
                messages = [messages; atlasMessages];
            end
        end

        function [selCases, messages] = normalizeCaseSelection(selCases, nCases, context)
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(context), context = 'caseSelection'; end
            nCases = double(nCases);
            if isempty(selCases)
                selCases = true(nCases,1);
                return;
            end
            selCases = logical(selCases(:));
            if numel(selCases) ~= nCases
                messages = [messages; NMDataIOMessageTools.make('danger', true, context, ...
                    sprintf('Subject inclusion mask length (%g) does not match the number of image subjects (%g). Re-run preview or reset the subject exclusion toggles before committing.', numel(selCases), nCases), 1, 'red*')];
                return;
            end
            if ~any(selCases)
                messages = [messages; NMDataIOMessageTools.make('danger', true, context, ...
                    'At least one image subject must remain included for import.', 1, 'red*')];
                return;
            end
            nExcluded = sum(~selCases);
            if nExcluded > 0
                messages = [messages; NMDataIOMessageTools.make('warn', false, context, ...
                    sprintf('%g/%g image subject(s) are excluded from import by the preview/viewer subject-selection mask.', nExcluded, nCases), 0, 'amber*')];
            end
        end

        function [IO, messages] = resolveImageFiles(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            files = NMDataIOImageImportTools.asCellstr(IO.imageFiles);
            if isempty(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles', 'No image files were supplied.', 1, 'red*')];
                return;
            end
            [spmFiles, fileMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM(files, 'imageFiles', true);
            messages = [messages; fileMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            try
                P = char(files(:));
                Pspm = char(spmFiles(:));
                V = spm_vol(Pspm);
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'imageFiles.spm_vol')];
                return;
            end
            IO.PP = P;
            IO.PPspm = Pspm;
            IO.files = files(:);
            IO.explicitCaseIDs = NMDataIOImageImportTools.resolveCaseIDSpec(IO.explicitCaseIDs);
            if isempty(IO.explicitCaseIDs)
                [ids, idMessages] = NMDataIOImportTools.deriveCaseIDsFromFiles(files, IO.caseIDMode, 'imageCaseIDs');
                messages = [messages; idMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                IO.ID = ids(:);
            else
                if numel(IO.explicitCaseIDs) ~= numel(files)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles', ...
                        sprintf('Number of explicit case IDs (%g) differs from number of image files (%g).', numel(IO.explicitCaseIDs), numel(files)), 1, 'red*')];
                    return;
                end
                IO.ID = IO.explicitCaseIDs(:);
                IO.caseIDMode = 'explicit';
            end
            [IO.selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(IO.selCases, numel(files), 'imageFiles.selection');
            messages = [messages; selectionMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            groupMode = NMDataIOImageImportTools.isLegacyGroupLabelMode(IO) && strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','classification')), 'classification');
            groupSizes = NMDataIOImageImportTools.numericVector(NMDataIOImageImportTools.fieldOr(IO,'imageGroupSizes',[]));
            if groupMode && ~isempty(groupSizes)
                groupSizes = round(double(groupSizes(:)'));
                if any(~isfinite(groupSizes)) || any(groupSizes < 1) || sum(groupSizes) ~= numel(files)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.groups', ...
                        sprintf('Auto-label image groups define %s file(s), but %g image file(s) are present. Rebuild the class-specific image lists before import.', mat2str(groupSizes), numel(files)), 1, 'red*')];
                    return;
                end
                IO.P = cell(1,numel(groupSizes));
                IO.V = cell(1,numel(groupSizes));
                pos = 1;
                for g = 1:numel(groupSizes)
                    idx = pos:(pos + groupSizes(g) - 1);
                    IO.P{g} = char(files(idx));
                    IO.V{g} = V(idx)';
                    pos = pos + groupSizes(g);
                end
                IO.n_samples = numel(groupSizes);
                IO.n_subjects = groupSizes;
                IO.n_subjects_all = numel(files);
            else
                IO.P = {P};
                IO.V = {V(:)'};
                IO.n_samples = 1;
                IO.n_subjects = numel(files);
                IO.n_subjects_all = numel(files);
            end
            [IO.Vinfo, IO.Vvox, IO.Vdim] = NMDataIOImageImportTools.volumeInfo(V);

            weightFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'weightingFiles',{}));
            if ~isempty(weightFiles)
                [spmWeightFiles, weightMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM(weightFiles, 'weightingMaps', true);
                messages = [messages; weightMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                try
                    IO.Pw = char(weightFiles(:));
                    IO.Pwspm = char(spmWeightFiles(:));
                    Vw = spm_vol(IO.Pwspm);
                    IO.Vw = Vw(:)';
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'weightingMaps.spm_vol')];
                    return;
                end
            end
        end


        function [IO, messages] = resolveSurfaceFiles(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO)
                [IO, messages] = NMDataIOImageImportTools.resolveNativeSurfaceRoiFiles(IO);
                return;
            end
            files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}));
            if isempty(files)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceFiles', 'No surface scalar files were supplied.', 1, 'red*')];
                return;
            end
            for i = 1:numel(files)
                if exist(files{i},'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceFiles', sprintf('Surface scalar file does not exist: %s', files{i}), 1, 'red*')]; %#ok<AGROW>
                end
            end
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.PP = char(files(:));
            IO.files = files(:);
            IO.imageFiles = files(:);
            IO.explicitCaseIDs = NMDataIOImageImportTools.resolveCaseIDSpec(IO.explicitCaseIDs);
            if isempty(IO.explicitCaseIDs)
                [ids, idMessages] = NMDataIOImportTools.deriveCaseIDsFromFiles(files, IO.caseIDMode, 'imageCaseIDs');
                messages = [messages; idMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                IO.ID = ids(:);
            else
                if numel(IO.explicitCaseIDs) ~= numel(files)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceFiles', ...
                        sprintf('Number of explicit case IDs (%g) differs from number of surface files (%g).', numel(IO.explicitCaseIDs), numel(files)), 1, 'red*')];
                    return;
                end
                IO.ID = IO.explicitCaseIDs(:);
                IO.caseIDMode = 'explicit';
            end
            [IO.selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(IO.selCases, numel(files), 'surfaceFiles.selection');
            messages = [messages; selectionMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.P = {char(files(:))};
            IO.V = {files(:)'};
            IO.n_samples = 1;
            IO.n_subjects = numel(files);
            IO.n_subjects_all = numel(files);
            IO.Vinfo = [];
            IO.Vvox = [];
            IO.datasource = 'surf';
            IO.sourceType = 'surface-list';
        end

        function [IO, messages] = readSurfacePayload(IO, progressTask)
            if nargin < 2 || isempty(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            messages = NMDataIOMessageTools.emptyMessages();
            nativeRoi = NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO);
            if nativeRoi
                [IO, messages] = NMDataIOImageImportTools.readNativeSurfaceRoiPayload(IO);
                if NMDataIOMessageTools.hasFatal(messages), return; end
            else
                files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'files',{}));
                if isempty(files), files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{})); end
                [Y, metas, readMessages] = NMDataIOSurfaceTools.readSurfaceMatrix(files, progressTask);
                messages = [messages; readMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                [IO, geometryMessages] = NMDataIOImageImportTools.validateSurfaceGeometryIO(IO,size(Y,2));
                messages = [messages; geometryMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                IO.Y = Y;
            end
            [IO, globalMessages] = NMDataIOImageImportTools.resolveGlobals(IO);
            messages = [messages; globalMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if isfield(IO,'globscale') && IO.globscale > 1
                [gSF, scaleMessages] = NMDataIOImageImportTools.proportionalGlobalScaleFactors( ...
                    IO.g, IO.globnorm, size(IO.Y,1), 'globals.surface.proportional');
                messages = [messages; scaleMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                IO.Y = bsxfun(@times, double(IO.Y), gSF);
            end
            if nativeRoi, return; end
            IO.datasource = 'surf';
            IO.sourceType = 'surface-list';
            IO.Thresh = struct('threshop',{{'all'}}, 'Vml', 1, 'Lm',{{'Surface vertices'}});
            IO.Vm = struct('datasource','surf', 'format',{unique(NMDataIOSurfaceTools.surfaceFormats(files), 'stable')}, ...
                'nVertices',double(size(Y,2)), 'files',{files(:)'}, 'metadata',{metas}, ...
                'surfaceImportMode',NMDataIOImageImportTools.fieldOr(IO,'surfaceImportMode','vertex_template'), ...
                'surfaceTemplate',NMDataIOImageImportTools.fieldOr(IO,'surfaceTemplate','unknown'), ...
                'surfaceHemisphere',NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto'), ...
                'surfaceGeometryFile',NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryFile', NMDataIOImageImportTools.fieldOr(IO,'surfaceDisplayMeshFile','')), ...
                'surfaceInflatedGeometryFile',NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryFile',''), ...
                'surfaceGeometryIdentity',NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryIdentity',''), ...
                'surfaceInflatedGeometryIdentity',NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryIdentity',''), ...
                'surfaceTopologyIdentity',NMDataIOImageImportTools.fieldOr(IO,'surfaceTopologyIdentity',''), ...
                'surfaceVertexOrderIdentity',NMDataIOImageImportTools.fieldOr(IO,'surfaceVertexOrderIdentity',''), ...
                'surfaceInflatedValidated',logical(NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedValidated',false)), ...
                'surfaceGeometryContract',NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryContract',struct()));
            IO.Vmvol = [];
            IO.brainmask = [];
            IO.featnames = arrayfun(@(k) sprintf('Vertex_%06d', k), 1:size(Y,2), 'UniformOutput', false);
            if NMDataIOImageImportTools.hasWeightingMaps(IO)
                [IO, weightMessages] = NMDataIOImageImportTools.readSurfaceWeightingPayload(IO, size(Y,2));
                messages = [messages; weightMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.surfaceImport = true;
            IO.importReport.surfaceFormats = unique(NMDataIOSurfaceTools.surfaceFormats(files), 'stable');
            IO.importReport.nVertices = double(size(Y,2));
            IO.importReport.surfaceImportMode = NMDataIOImageImportTools.fieldOr(IO,'surfaceImportMode','vertex_template');
            IO.importReport.surfaceTemplate = NMDataIOImageImportTools.fieldOr(IO,'surfaceTemplate','unknown');
            IO.importReport.surfaceHemisphere = NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto');
            IO.importReport.surfaceGeometryFile = NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryFile', NMDataIOImageImportTools.fieldOr(IO,'surfaceDisplayMeshFile',''));
            IO.importReport.surfaceInflatedGeometryFile = NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryFile','');
            if isfield(IO,'surfaceGeometryContract') && isstruct(IO.surfaceGeometryContract)
                IO.importReport.surfaceGeometryContract = IO.surfaceGeometryContract;
                IO.importReport.surfaceGeometryIdentity = NMDataIOImageImportTools.fieldOr(IO.surfaceGeometryContract,'nativeGeometryIdentity','');
                IO.importReport.surfaceInflatedGeometryIdentity = NMDataIOImageImportTools.fieldOr(IO.surfaceGeometryContract,'inflatedGeometryIdentity','');
                IO.importReport.surfaceTopologyIdentity = NMDataIOImageImportTools.fieldOr(IO.surfaceGeometryContract,'topologyIdentity','');
                IO.importReport.surfaceVertexOrderIdentity = NMDataIOImageImportTools.fieldOr(IO.surfaceGeometryContract,'vertexOrderIdentity','');
                IO.importReport.surfaceInflatedValidated = logical(NMDataIOImageImportTools.fieldOr(IO.surfaceGeometryContract,'inflatedValidated',false));
            end
            if isfield(IO,'Yw') && ~isempty(IO.Yw)
                IO.importReport.hasWeightingMaps = true;
                IO.importReport.weightingMapMode = 'surface_vertex_template';
                IO.importReport.nWeightingMaps = double(size(IO.Yw,1));
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'surfaceFiles.read', ...
                sprintf('Surface data read successfully: %g case file(s), %g vertex feature(s).', size(Y,1), size(Y,2)), 0, 'green*')];
        end

        function [IO, messages] = validateSurfaceGeometryIO(IO, expectedVertexCount)
            % validateSurfaceGeometryIO  Require native geometry; validate optional inflated geometry for vertexwise surfaces.
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO)
                if ~isempty(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryFile','')))
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'surfaceGeometry.inflated.roiNative', ...
                        'An inflated template geometry applies only to registered/template vertexwise surface import, not native ROI collapse.',1,'red*')];
                end
                return;
            end
            nativeFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryFile',NMDataIOImageImportTools.fieldOr(IO,'surfaceDisplayMeshFile','')));
            inflatedFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceInflatedGeometryFile',''));
            options = struct('surfaceTemplate',NMDataIOImageImportTools.fieldOr(IO,'surfaceTemplate','unknown'), ...
                'surfaceHemisphere',NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto'));
            try
                contract = NMDataIOSurfaceTools.validateSurfaceGeometryContract(nativeFile,inflatedFile,expectedVertexCount,options);
                IO.surfaceGeometryContract = contract;
                IO.surfaceGeometryIdentity = contract.nativeGeometryIdentity;
                IO.surfaceInflatedGeometryIdentity = contract.inflatedGeometryIdentity;
                IO.surfaceTopologyIdentity = contract.topologyIdentity;
                IO.surfaceVertexOrderIdentity = contract.vertexOrderIdentity;
                IO.surfaceInflatedValidated = logical(contract.inflatedValidated);
                if contract.inflatedValidated
                    messages = [messages; NMDataIOMessageTools.make('ok',false,'surfaceGeometry.inflated.validated', ...
                        sprintf('Native/inflated surface correspondence validated: %g vertex/vertices, %g triangle(s), method=%s.', ...
                        contract.vertexCount,contract.faceCount,contract.correspondenceMethod),0,'green*')];
                elseif contract.nativeAvailable
                    messages = [messages; NMDataIOMessageTools.make('info',false,'surfaceGeometry.native.validated', ...
                        sprintf('Native surface geometry matches the %g imported vertex features.',contract.vertexCount),0,'SystemCommands')];
                end
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME,'surfaceGeometry.validation')];
            end
        end

        function [IO, messages] = readSurfaceWeightingPayload(IO, nFeatures)
            messages = NMDataIOMessageTools.emptyMessages();
            weightFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'weightingFiles',{}));
            if isempty(weightFiles) && isfield(IO,'Pw') && ~isempty(IO.Pw)
                weightFiles = NMDataIOImageImportTools.asCellstr(IO.Pw);
            end
            if isempty(weightFiles), return; end
            for w = 1:numel(weightFiles)
                if exist(weightFiles{w}, 'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceWeighting.files', ...
                        sprintf('Surface weighting/ranking map file does not exist: %s', weightFiles{w}), 1, 'red*')]; %#ok<AGROW>
                end
            end
            if NMDataIOMessageTools.hasFatal(messages), return; end
            [Yw, weightMetas, readMessages] = NMDataIOSurfaceTools.readSurfaceMatrix(weightFiles);
            messages = [messages; readMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if size(Yw,2) ~= nFeatures
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceWeighting.featureContract', ...
                    sprintf('Surface weighting/ranking map inconsistency: imported surface modality has %g vertex feature(s), but weighting map(s) have %g vertex feature(s).', nFeatures, size(Yw,2)), 1, 'red*')];
                return;
            end
            IO.Yw = Yw;
            IO.Pw = char(weightFiles(:));
            IO.Vw = weightFiles(:)';
            prov = struct();
            prov.mode = 'surface_vertex_template';
            prov.weightingFiles = weightFiles(:)';
            prov.nWeightingMaps = double(size(Yw,1));
            prov.nFeatures = double(size(Yw,2));
            prov.metadata = weightMetas;
            prov.featureSpace = 'same vertex order as imported registered/template surface scalar files';
            IO.surfaceWeightingProvenance = prov;
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.hasWeightingMaps = true;
            IO.importReport.weightingMapMode = 'surface_vertex_template';
            IO.importReport.nWeightingMaps = double(size(Yw,1));
            messages = [messages; NMDataIOMessageTools.make('info', false, 'surfaceWeighting.read', ...
                sprintf('Surface weighting/ranking maps read: %g map(s), %g vertex feature(s).', size(Yw,1), size(Yw,2)), 0, 'SystemCommands')];
        end


        function tf = isSurfaceNativeRoiMode(IO)
            mode = lower(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceImportMode','')));
            tf = NMDataIOImageImportTools.isSurfaceIO(IO) && any(strcmp(mode, {'roi_native','native_roi','roi_collapse_native','roi_collapse'}));
        end


        function [out, messages] = surfaceNativeRoiProbeFromIO(NM, state, IO, messagesIn)
            if nargin < 4 || isempty(messagesIn), messagesIn = NMDataIOMessageTools.emptyMessages(); end
            messages = NMDataIOMessageTools.emptyMessages();
            [IO2, resMessages] = NMDataIOImageImportTools.resolveNativeSurfaceRoiFiles(IO);
            messages = [messages; resMessages];
            if NMDataIOImageImportTools.hasWeightingMaps(IO2)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.weightingMaps', ...
                    ['Surface weighting/ranking maps are currently supported only for registered/template vertexwise surface import. ', ...
                     'Native subject-space ROI weighting is not supported by the current ROI weighting-map option.'], 1, 'red*')];
            end
            preview = struct();
            preview.rows = struct('index',{},'file',{},'caseId',{},'label',{},'globalValue',{},'covariates',{}, ...
                'dim',{},'voxelSize',{},'status',{},'statusLevel',{},'statusText',{},'included',{});
            files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'files',{}));
            ids = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'ID',{}));
            n = max(numel(files), numel(ids));
            rows = repmat(preview.rows, n, 1);
            for i = 1:n
                file = ''; if i <= numel(files), file = files{i}; end
                id = ''; if i <= numel(ids), id = ids{i}; end
                rows(i).index = i;
                rows(i).file = file;
                rows(i).caseId = id;
                rows(i).label = '';
                rows(i).globalValue = '';
                rows(i).covariates = '';
                rows(i).dim = 'native ROI collapse';
                rows(i).voxelSize = 'surface_roi';
                rows(i).statusLevel = 'ok';
                rows(i).statusText = 'OK (native scalar + annotation pair)';
                rows(i).status = rows(i).statusText;
                rows(i).included = true;
            end
            if ~NMDataIOMessageTools.hasFatal(messages)
                spec = struct();
                spec.lhScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiLHScalarFiles',{}));
                spec.lhAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiLHAnnotFiles',{}));
                spec.lhGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiLHGeometryFile',''));
                spec.rhScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiRHScalarFiles',{}));
                spec.rhAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiRHAnnotFiles',{}));
                spec.rhGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiRHGeometryFile',''));
                spec.scalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiScalarFiles',{}));
                spec.annotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiAnnotFiles',{}));
                spec.hemisphereMode = NMDataIOImageImportTools.fieldOr(IO2,'surfaceHemisphere','auto');
                spec.collapseMethod = NMDataIOImageImportTools.fieldOr(IO2,'surfaceRoiCollapseMethod','mean');
                [Ytmp, roiInfo, ~, readMessages] = NMDataIOSurfaceTools.readNativeSurfaceROIMatrix(spec);
                messages = [messages; readMessages];
                if ~NMDataIOMessageTools.hasFatal(messages)
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'surfaceRoi.probe', ...
                        sprintf('Native surface ROI stream accepted: %g subject(s), %g ROI feature(s), method=%s.', size(Ytmp,1), size(Ytmp,2), spec.collapseMethod), 0, 'green*')];
                end
            end
            preview.rows = rows;
            preview.nRows = n;
            probe = struct('datasource','surf','sourceType','surface-list','surfaceImportMode','roi_native', ...
                'surfaceTemplate',NMDataIOImageImportTools.fieldOr(IO2,'surfaceTemplate','native'), ...
                'surfaceHemisphere',NMDataIOImageImportTools.fieldOr(IO2,'surfaceHemisphere','auto'), ...
                'caseIds',{ids(:)}, 'nImages',double(n));
            allMessages = [messagesIn; messages];
            strip = NMDataIOMessageTools.highestPriorityStrip(allMessages, 'Native surface ROI check completed.');
            out = struct('ok',~strip.blocking,'readyToImport',~strip.blocking,'blocking',strip.blocking, ...
                'message',strip.text,'strip',strip,'messages',NMDataIOMessageTools.forDiagnosticsPanel(allMessages), ...
                'summary',probe,'probe',probe,'preview',preview,'stateEcho',state);
        end

        function [IO, messages] = resolveNativeSurfaceRoiFiles(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            lhS = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiLHScalarFiles',{}));
            lhA = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiLHAnnotFiles',{}));
            rhS = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiRHScalarFiles',{}));
            rhA = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiRHAnnotFiles',{}));
            gS = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiScalarFiles',{}));
            gA = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiAnnotFiles',{}));
            if isempty(lhS) && isempty(rhS) && ~isempty(gS)
                h = NMDataIOSurfaceTools.inferHemisphereList(gS, 'left');
                if strcmp(h,'right'), rhS = gS; rhA = gA; else, lhS = gS; lhA = gA; end
            end
            if isempty(lhS) && isempty(rhS)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.files', ...
                    'Native ROI surface import requires scalar and annotation lists. Provide LH scalar/LH annotation and optionally RH scalar/RH annotation lists.', 1, 'red*')];
                return;
            end
            useLH = ~isempty(lhS) || ~isempty(lhA);
            useRH = ~isempty(rhS) || ~isempty(rhA);
            if useLH && numel(lhS) ~= numel(lhA)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.lh.length', ...
                    sprintf('LH scalar/annotation list lengths differ: scalar=%g, annotation=%g.', numel(lhS), numel(lhA)), 1, 'red*')];
            end
            if useRH && numel(rhS) ~= numel(rhA)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.rh.length', ...
                    sprintf('RH scalar/annotation list lengths differ: scalar=%g, annotation=%g.', numel(rhS), numel(rhA)), 1, 'red*')];
            end
            if NMDataIOMessageTools.hasFatal(messages), return; end
            for i = 1:numel(lhS)
                if exist(lhS{i},'file') ~= 2, messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.lh.scalar', sprintf('LH scalar file does not exist: %s', lhS{i}), 1, 'red*')]; end %#ok<AGROW>
                if exist(lhA{i},'file') ~= 2, messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.lh.annot', sprintf('LH annotation file does not exist: %s', lhA{i}), 1, 'red*')]; end %#ok<AGROW>
            end
            for i = 1:numel(rhS)
                if exist(rhS{i},'file') ~= 2, messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.rh.scalar', sprintf('RH scalar file does not exist: %s', rhS{i}), 1, 'red*')]; end %#ok<AGROW>
                if exist(rhA{i},'file') ~= 2, messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.rh.annot', sprintf('RH annotation file does not exist: %s', rhA{i}), 1, 'red*')]; end %#ok<AGROW>
            end
            if NMDataIOMessageTools.hasFatal(messages), return; end
            refFiles = lhS; if isempty(refFiles), refFiles = rhS; end
            IO.surfaceRoiLHScalarFiles = lhS(:); IO.surfaceRoiLHAnnotFiles = lhA(:);
            IO.surfaceRoiRHScalarFiles = rhS(:); IO.surfaceRoiRHAnnotFiles = rhA(:);
            IO.files = refFiles(:);
            IO.imageFiles = refFiles(:);
            IO.PP = char(refFiles(:));
            IO.P = {char(refFiles(:))};
            IO.V = {refFiles(:)'};
            IO.n_samples = 1;
            IO.n_subjects = numel(refFiles);
            IO.n_subjects_all = numel(refFiles);
            IO.explicitCaseIDs = NMDataIOImageImportTools.resolveCaseIDSpec(IO.explicitCaseIDs);
            if isempty(IO.explicitCaseIDs)
                ids = NMDataIOSurfaceTools.subjectKeysFromFiles(refFiles);
                if all(cellfun(@isempty, ids))
                    [ids, idMessages] = NMDataIOImportTools.deriveCaseIDsFromFiles(refFiles, IO.caseIDMode, 'imageCaseIDs');
                    messages = [messages; idMessages];
                end
                IO.ID = ids(:);
            else
                if numel(IO.explicitCaseIDs) ~= numel(refFiles)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.caseIds', ...
                        sprintf('Number of explicit case IDs (%g) differs from number of native surface ROI subjects (%g).', numel(IO.explicitCaseIDs), numel(refFiles)), 1, 'red*')];
                    return;
                end
                IO.ID = IO.explicitCaseIDs(:);
                IO.caseIDMode = 'explicit';
            end
            [IO.selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(IO.selCases, numel(refFiles), 'surfaceRoi.selection');
            messages = [messages; selectionMessages];
            IO.datasource = 'surf';
            IO.sourceType = 'surface-list';
        end

        function [IO, messages] = readNativeSurfaceRoiPayload(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            spec = struct();
            spec.lhScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiLHScalarFiles',{}));
            spec.lhAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiLHAnnotFiles',{}));
            spec.lhGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiLHGeometryFile',''));
            spec.rhScalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiRHScalarFiles',{}));
            spec.rhAnnotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiRHAnnotFiles',{}));
            spec.rhGeometryFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiRHGeometryFile',''));
            spec.scalarFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiScalarFiles',{}));
            spec.annotFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiAnnotFiles',{}));
            spec.hemisphereMode = NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto');
            spec.collapseMethod = NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiCollapseMethod','mean');
            if NMDataIOImageImportTools.hasWeightingMaps(IO)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.weightingMaps', ...
                    ['Surface weighting/ranking maps for native subject-space ROI collapse are not enabled in this patch. ', ...
                     'Registered/template vertexwise surface weighting maps are supported; native ROI weighting is not available with this option.'], 1, 'red*')];
                return;
            end
            [Y, roiInfo, metas, readMessages] = NMDataIOSurfaceTools.readNativeSurfaceROIMatrix(spec);
            messages = [messages; readMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.Y = Y;
            IO.datasource = 'surf';
            IO.sourceType = 'surface-list';
            IO.Thresh = struct('threshop',{{'surface_roi'}}, 'Vml', double(roiInfo.roiIDs(:)'), 'Lm',{roiInfo.roiNames(:)'});
            IO.Vm = struct('datasource','surf', 'format',{{'surface_native_roi'}}, ...
                'nVertices',NaN, 'nROIs',double(size(Y,2)), 'files',{roiInfo.scalarFiles}, 'metadata',{metas}, ...
                'surfaceImportMode','roi_native', 'surfaceTemplate',NMDataIOImageImportTools.fieldOr(IO,'surfaceTemplate','native'), ...
                'surfaceHemisphere',NMDataIOImageImportTools.fieldOr(IO,'surfaceHemisphere','auto'), ...
                'surfaceGeometryFile',NMDataIOImageImportTools.fieldOr(IO,'surfaceGeometryFile', NMDataIOImageImportTools.fieldOr(IO,'surfaceDisplayMeshFile','')), ...
                'surfaceRoiInfo',roiInfo);
            IO.Vmvol = [];
            IO.brainmask = [];
            IO.featnames = roiInfo.roiNames(:)';
            IO.surfaceRoiInfo = roiInfo;
            IO.roiProvenance = NMDataIOROIProvenanceTools.fromSurfaceCollapse(roiInfo, size(Y,2));
            if ~IO.roiProvenance.ok
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.roiProvenance', ...
                    IO.roiProvenance.message, 1, 'red*')];
                return;
            end
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.surfaceImport = true;
            IO.importReport.surfaceImportMode = 'roi_native';
            IO.importReport.nROIs = double(size(Y,2));
            IO.importReport.surfaceRoiCollapseMethod = NMDataIOImageImportTools.fieldOr(IO,'surfaceRoiCollapseMethod','mean');
            IO.importReport.surfaceRoiInfo = roiInfo;
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'surfaceRoi.read', ...
                sprintf('Native surface ROI data read successfully: %g case(s), %g ROI feature(s), method=%s.', size(Y,1), size(Y,2), IO.importReport.surfaceRoiCollapseMethod), 0, 'green*')];
        end

    end

    methods (Static)
        function [IO, messages] = applySubjectSelectionToResolvedIO(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            ids = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'ID',{}));
            n = numel(ids);
            [selCases, selectionMessages] = NMDataIOImageImportTools.normalizeCaseSelection(NMDataIOImageImportTools.fieldOr(IO,'selCases',[]), n, 'imageFiles.selection.commit');
            messages = [messages; selectionMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            selCases = logical(selCases(:));
            if isempty(selCases) || all(selCases)
                IO.selCases = true(n,1);
                if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
                IO.importReport.subjectSelection = struct('applied',false,'nOriginal',double(n),'nIncluded',double(n),'nExcluded',0,'excludedCaseIDs',{{}},'originalCaseIDs',{ids(:)'});
                return;
            end

            originalIDs = ids(:);
            selectedIDs = originalIDs(selCases);
            excludedIDs = originalIDs(~selCases);
            nIncluded = numel(selectedIDs);
            nExcluded = numel(excludedIDs);

            if isfield(IO,'files') && ~isempty(IO.files)
                files = NMDataIOImageImportTools.asCellstr(IO.files);
            else
                files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}));
            end
            if numel(files) == n, files = files(selCases); end
            IO.files = files(:);
            IO.imageFiles = files(:);

            if isfield(IO,'PP') && ~isempty(IO.PP)
                pp = NMDataIOImageImportTools.asCellstr(IO.PP);
                if numel(pp) == n, IO.PP = char(pp(selCases)); end
            end
            if isfield(IO,'PPspm') && ~isempty(IO.PPspm)
                pp = NMDataIOImageImportTools.asCellstr(IO.PPspm);
                if numel(pp) == n, IO.PPspm = char(pp(selCases)); end
            end
            if isfield(IO,'explicitCaseIDs') && numel(IO.explicitCaseIDs) == n
                IO.explicitCaseIDs = IO.explicitCaseIDs(selCases);
            end
            IO.ID = selectedIDs(:);
            IO.s_ID = selectedIDs(:);
            if isfield(IO,'Y') && ~isempty(IO.Y)
                if isnumeric(IO.Y) || islogical(IO.Y)
                    if size(IO.Y,1) ~= n
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                            sprintf('Retained imaging matrix row count (%g) differs from the retained subject count (%g).', size(IO.Y,1), n), 1, 'red*')];
                        return;
                    end
                    IO.Y = IO.Y(selCases,:);
                elseif iscell(IO.Y)
                    for yi = 1:numel(IO.Y)
                        if isnumeric(IO.Y{yi}) && size(IO.Y{yi},1) == n
                            IO.Y{yi} = IO.Y{yi}(selCases,:);
                        end
                    end
                end
            end
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end

            IO = NMDataIOImageImportTools.filterCaseRows(IO, {'label','s_label','L','covars','g','Vinfo','Vvox','Vdim'}, selCases, n);
            if NMDataIOImageImportTools.isSurfaceIO(IO)
                if NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO)
                    roiFields = {'surfaceRoiLHScalarFiles','surfaceRoiLHAnnotFiles','surfaceRoiRHScalarFiles','surfaceRoiRHAnnotFiles','surfaceRoiScalarFiles','surfaceRoiAnnotFiles'};
                    for rf = 1:numel(roiFields)
                        f = roiFields{rf};
                        if isfield(IO,f) && numel(IO.(f)) == n
                            IO.(f) = IO.(f)(selCases);
                        end
                    end
                end
                IO.P = {char(files(:))};
                IO.V = {files(:)'};
                IO.n_samples = 1;
                IO.n_subjects = nIncluded;
                IO.n_subjects_all = nIncluded;
            elseif isfield(IO,'P') && isfield(IO,'V')
                [IO, groupMessages] = NMDataIOImageImportTools.rebuildImageGroupsAfterSelection(IO, selCases, n);
                messages = [messages; groupMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            else
                IO.n_samples = 1;
                IO.n_subjects = nIncluded;
                IO.n_subjects_all = nIncluded;
            end
            IO.selCasesOriginal = selCases;
            IO.selCases = true(nIncluded,1);
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.subjectSelection = struct('applied',true, 'nOriginal',double(n), 'nIncluded',double(nIncluded), ...
                'nExcluded',double(nExcluded), 'excludedCaseIDs',{excludedIDs(:)'}, 'originalCaseIDs',{originalIDs(:)'});
            if isfield(IO,'Vinfo') && ~isempty(IO.Vinfo) && size(IO.Vinfo,1) ~= nIncluded
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                    sprintf('Subject exclusion produced inconsistent Vinfo rows (%g) for %g included image subject(s). This would break the legacy ReadNifti report table.', size(IO.Vinfo,1), nIncluded), 1, 'red*')];
                return;
            end
            if isfield(IO,'Vvox') && ~isempty(IO.Vvox) && size(IO.Vvox,1) ~= nIncluded
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                    sprintf('Subject exclusion produced inconsistent Vvox rows (%g) for %g included image subject(s). This would break the legacy ReadNifti report table.', size(IO.Vvox,1), nIncluded), 1, 'red*')];
                return;
            end
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'imageFiles.selection.commit', ...
                sprintf('%g/%g imaging case(s) were excluded before import; %g case(s) remain in the imported modality.', nExcluded, n, nIncluded), 0, 'amber*')];
        end

    end

    methods (Static, Access = private)
        function IO = filterCaseRows(IO, fields, selCases, nRows)
            for i = 1:numel(fields)
                f = fields{i};
                if ~isfield(IO,f) || isempty(IO.(f)), continue; end
                v = IO.(f);
                try
                    if iscell(v) && numel(v) == nRows
                        IO.(f) = v(selCases);
                    elseif (isnumeric(v) || islogical(v)) && size(v,1) == nRows
                        IO.(f) = v(selCases,:);
                    end
                catch ME
                    error('NMDataIOImageImportTools:CaseSelectionFilter', 'Could not filter IO.%s using the subject-selection mask: %s', f, ME.message);
                end
            end
        end

        function [IO, messages] = rebuildImageGroupsAfterSelection(IO, selCases, nRows)
            messages = NMDataIOMessageTools.emptyMessages();
            nIncluded = sum(selCases);
            if iscell(IO.V)
                Vflat = [IO.V{:}];
            else
                Vflat = IO.V(:)';
            end
            if numel(Vflat) ~= nRows
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                    sprintf('Cannot apply subject exclusion: SPM image-header count (%g) differs from image subject count (%g).', numel(Vflat), nRows), 1, 'red*')];
                return;
            end
            files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'files',{}));
            if numel(files) ~= nIncluded
                files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}));
            end
            if NMDataIOImageImportTools.isLegacyGroupLabelMode(IO) && isfield(IO,'n_subjects') && numel(IO.n_subjects) > 1
                originalGroupSizes = round(double(IO.n_subjects(:)'));
                if sum(originalGroupSizes) ~= nRows
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                        sprintf('Cannot apply subject exclusion to auto-label image groups: group sizes sum to %g but %g image subjects are present.', sum(originalGroupSizes), nRows), 1, 'red*')];
                    return;
                end
                newCounts = zeros(size(originalGroupSizes));
                newP = cell(1,numel(originalGroupSizes));
                newV = cell(1,numel(originalGroupSizes));
                originalFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'PP',{}));
                if numel(originalFiles) ~= nRows
                    originalFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFilesSpec',{}));
                end
                pos = 1;
                for g = 1:numel(originalGroupSizes)
                    idx = pos:(pos + originalGroupSizes(g) - 1);
                    keep = selCases(idx);
                    newCounts(g) = sum(keep);
                    if newCounts(g) < 1
                        groupNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'desc_groups',{}));
                        groupName = sprintf('class/group %g', g);
                        if numel(groupNames) >= g && ~isempty(groupNames{g}), groupName = groupNames{g}; end
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFiles.selection.commit', ...
                            sprintf('Subject exclusion would remove all images from %s. At least one subject per auto-label class must remain included.', groupName), 1, 'red*')];
                        return;
                    end
                    selectedOriginalIdx = idx(keep);
                    newP{g} = char(originalFiles(selectedOriginalIdx));
                    newV{g} = Vflat(selectedOriginalIdx);
                    pos = pos + originalGroupSizes(g);
                end
                IO.P = newP;
                IO.V = newV;
                IO.n_samples = numel(newCounts);
                IO.n_subjects = newCounts;
                IO.n_subjects_all = nIncluded;
                IO.imageGroupSizes = newCounts;
                IO.importReport.imageGroupSizesAfterSubjectSelection = newCounts;
            else
                selectedV = Vflat(selCases);
                selectedFiles = files(:);
                if numel(selectedFiles) ~= nIncluded
                    selectedFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'PP',{}));
                    selectedFiles = selectedFiles(selCases);
                end
                IO.P = {char(selectedFiles)};
                IO.V = {selectedV(:)'};
                IO.n_samples = 1;
                IO.n_subjects = nIncluded;
                IO.n_subjects_all = nIncluded;
            end
        end

        function [IO, messages] = resolveGlobals(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            mode = lower(strrep(NMDataIOImageImportTools.asChar(IO.globalMode), ' ', '_'));
            switch mode
                case {'','none','no','off'}
                    IO.globalMode = 'none';
                    IO.globscale = 1;
                    IO.g = [];
                case {'proportional','proportional_scaling','scale'}
                    IO.globalMode = 'proportional';
                    [g, gMessages] = NMDataIOImportTools.globalVector(IO);
                    messages = [messages; gMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    IO.g = g(:);
                    if NMDataIOImportTools.isDerivedGlobalSource(IO.globalSource)
                        IO.globscale = 3;
                    else
                        IO.globscale = 2;
                    end
                case {'ancova','covariate'}
                    IO.globalMode = 'ancova';
                    [g, gMessages] = NMDataIOImportTools.globalVector(IO);
                    messages = [messages; gMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                    IO.globscale = 1;
                    IO.g = g(:);
                    IO.covars = g(:);
                    IO.covnames = {IO.globalName};
                otherwise
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'globals', ...
                        sprintf('Unsupported imaging global-scaling mode: %s.', IO.globalMode), 1, 'red*')];
            end
        end

        function [IO, messages] = applyPostReadAlignment(IO, targetContainer, importTarget, trainingNM)
            messages = NMDataIOMessageTools.emptyMessages();
            alignmentContainer = NMDataIOImportTools.alignmentReferenceContainer(trainingNM, targetContainer, importTarget);
            if NMDataIOImportTools.hasReferenceCases(alignmentContainer)
                opts = NMDataIOImportTools.caseAlignmentOptions(IO);
                opts = NMDataIOImageImportTools.imageReferenceAlignmentOptions(IO, opts, alignmentContainer, importTarget);
                opts.referenceLabel = NMDataIOImportTargetTools.caseReferenceLabel(importTarget);
                [IO, alignMessages] = NMDataIOImageImportTools.alignImageYToCases(IO, alignmentContainer.cases, opts, 'commit');
                messages = [messages; alignMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if isfield(targetContainer,'label') && ~isempty(targetContainer.label) && (~IO.oocvflag || IO.labels_known)
                    IO.label = targetContainer.label;
                    IO.s_label = targetContainer.label;
                    IO.L = targetContainer.label;
                elseif isfield(IO,'label')
                    IO = rmfield(IO,'label');
                    if isfield(IO,'s_label'), IO = rmfield(IO,'s_label'); end
                    if isfield(IO,'L'), IO = rmfield(IO,'L'); end
                end
                if ~NMDataIOImportTools.hasExplicitCovariateAssignment(IO, '?')
                    if isfield(IO,'covars'), IO = rmfield(IO,'covars'); end
                    if isfield(IO,'covnames'), IO = rmfield(IO,'covnames'); end
                end
            end
            if NMDataIOImportTargetTools.isOOCV(importTarget)
                messages = [messages; NMDataIOImageImportTools.validateOOCVFeatureSpace(IO, trainingNM, importTarget.varind)];
            end
        end

    end

    methods (Static, Access = private)
        function [IO, messages] = finalizeImageTransportContract(IO)
            % finalizeImageTransportContract  Normalize the image-file transport fields only.
            % Generic label canonicalization, transfer counts and auxiliary-role semantics are
            % owned by NMDataIOImportTools after the final case axis has been established.
            messages = NMDataIOMessageTools.emptyMessages();
            nIDs = numel(NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'ID',{})));
            IO.ID = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'ID',{}));
            IO.s_ID = IO.ID(:);
            if nIDs < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageTransfer.preflight', ...
                    'Transfer preflight failed: no imaging case IDs are defined.', 1, 'red*')];
                return;
            end
            if isfield(IO,'PP') && ~isempty(IO.PP)
                files = NMDataIOImageImportTools.asCellstr(IO.PP);
            elseif isfield(IO,'files') && ~isempty(IO.files)
                files = NMDataIOImageImportTools.asCellstr(IO.files);
            else
                files = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{}));
            end
            if numel(files) ~= nIDs
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageTransfer.preflight', ...
                    sprintf('Transfer preflight failed: %g image file row(s) but %g case ID(s).', numel(files), nIDs), 1, 'red*')];
                return;
            end
            IO.PP = char(files(:));
            IO.files = files(:);
            IO.imageFiles = files(:);
            IO.datasource = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'datasource','nifti'));
            IO.modeflag = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','classification'));
            IO.desc_data = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'desc_data','Imaging modality'));
        end

        function messages = validateReadNiftiReportDimensions(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            if isfield(IO,'PP') && ~isempty(IO.PP)
                nRows = size(char(IO.PP),1);
            elseif isfield(IO,'files') && ~isempty(IO.files)
                nRows = numel(NMDataIOImageImportTools.asCellstr(IO.files));
            else
                return;
            end
            fields = {'Vvox','Vinfo'};
            for i = 1:numel(fields)
                f = fields{i};
                if isfield(IO,f) && ~isempty(IO.(f)) && isnumeric(IO.(f)) && size(IO.(f),1) ~= nRows
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'ReadNifti.preflight', ...
                        sprintf('Legacy ReadNifti preflight failed: IO.%s has %g row(s), but the current image-file table has %g row(s). This usually indicates incomplete subject-selection filtering before ReadNifti.', f, size(IO.(f),1), nRows), 1, 'red*')]; %#ok<AGROW>
                end
            end
            if isfield(IO,'g') && ~isempty(IO.g) && numel(IO.g) ~= nRows
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'ReadNifti.preflight', ...
                    sprintf('Legacy ReadNifti preflight failed: global-scaling vector IO.g has %g value(s), but the current image-file table has %g row(s).', numel(IO.g), nRows), 1, 'red*')];
            end
        end

        function [IO, messages] = resolveLegacyGroupLabels(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            labelMode = lower(strrep(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'labelMode','metadata')), '-', '_'), ' ', '_'));
            if ~strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'modeflag','classification')), 'classification')
                return;
            end
            if ~logical(NMDataIOImageImportTools.fieldOr(IO,'labels_known',true))
                return;
            end
            if ~ismember(labelMode, {'legacy_groups','legacy_group','groups','group_blocks','classification_groups','auto_groups','sequential_groups'})
                return;
            end
            nImages = numel(NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'ID',{})));
            sizes = NMDataIOImageImportTools.numericVector(NMDataIOImageImportTools.fieldOr(IO,'imageGroupSizes',[]));
            if isempty(sizes)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageLabels.legacyGroups', ...
                    'Legacy classification label mode requires sequential image-group sizes, e.g. 5,5 for two classes in the current image-file order.', 1, 'red*')];
                return;
            end
            sizes = round(double(sizes(:)'));
            if any(~isfinite(sizes)) || any(sizes < 1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageLabels.legacyGroups', ...
                    'Sequential image-group sizes must be positive finite integers.', 1, 'red*')];
                return;
            end
            if sum(sizes) ~= nImages
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageLabels.legacyGroups', ...
                    sprintf('Sequential image-group sizes sum to %g, but %g image file(s) were supplied.', sum(sizes), nImages), 1, 'red*')];
                return;
            end
            label = [];
            for i = 1:numel(sizes)
                label = [label; i * ones(sizes(i), 1)]; %#ok<AGROW>
            end
            names = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageGroupNames',{}));
            if numel(names) < numel(sizes)
                for i = (numel(names)+1):numel(sizes)
                    names{i,1} = sprintf('Class_%d', i); %#ok<AGROW>
                end
            end
            IO.label = label;
            IO.s_label = label;
            IO.L = label;
            IO.n_samples = numel(sizes);
            IO.n_subjects = sizes(:)';
            IO.n_subjects_all = nImages;
            IO.desc_groups = names(1:numel(sizes));
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.labelMode = 'legacy_groups';
            IO.importReport.imageGroupSizes = sizes;
            IO.importReport.imageGroupNames = IO.desc_groups;
        end

        function [IO, messages] = alignImageYToCases(IO, referenceCases, opts, stage)
            messages = NMDataIOMessageTools.emptyMessages();
            incomingIDs = IO.ID;
            opts = NMDataIOImageImportTools.imageReferenceAlignmentOptions(IO, opts);
            [alignedIncomingRows, alignmentReport, alignMessages] = NMDataIOImportTools.alignRowsToReferenceCases((1:numel(incomingIDs))', incomingIDs, referenceCases, opts, stage);
            messages = [messages; alignMessages];
            messages = [messages; NMDataIOImageImportTools.referenceCaseImageAlignmentDiagnostics(alignmentReport, incomingIDs, referenceCases, stage)];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if iscell(IO.Y)
                alignedY = cell(size(IO.Y));
                for c = 1:numel(IO.Y)
                    alignedY{c} = NMDataIOImageImportTools.alignMatrixByIncomingRows(IO.Y{c}, alignedIncomingRows);
                end
                IO.Y = alignedY;
            else
                IO.Y = NMDataIOImageImportTools.alignMatrixByIncomingRows(IO.Y, alignedIncomingRows);
            end
            if isfield(IO,'covars') && ~isempty(IO.covars)
                IO.covars = NMDataIOImageImportTools.alignMatrixByIncomingRows(IO.covars, alignedIncomingRows);
            end
            rowMetadataFields = {'g','Vinfo','Vvox','Vdim'};
            for rowFieldIndex = 1:numel(rowMetadataFields)
                rowField = rowMetadataFields{rowFieldIndex};
                if isfield(IO,rowField) && ~isempty(IO.(rowField)) && size(IO.(rowField),1) == numel(incomingIDs)
                    IO.(rowField) = NMDataIOImageImportTools.alignMatrixByIncomingRows(IO.(rowField), alignedIncomingRows);
                end
            end
            [alignedFiles, ~] = NMDataIOImageImportTools.alignCellsByIncomingRows(NMDataIOImageImportTools.asCellstr(IO.PP), alignedIncomingRows);
            IO.PP = char(alignedFiles(:));
            IO.files = alignedFiles(:);
            IO.ID = NMDataIOImageImportTools.asCellstr(referenceCases(:));
            IO.s_ID = IO.ID(:);
            IO.n_samples = 1;
            IO.n_subjects = numel(IO.ID);
            IO.n_subjects_all = numel(IO.ID);
            IO.selCases = true(numel(IO.ID), 1);
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.caseAlignment = alignmentReport;
            IO.importReport.referenceCaseImport = true;
            if isfield(alignmentReport,'missingCases') && ~isempty(alignmentReport.missingCases) && ...
                    isfield(alignmentReport,'allowMissingCasesAsNaN') && alignmentReport.allowMissingCasesAsNaN
                IO.importReport.missingCasesFilledWithNaN = true;
                IO.importReport.requiresEarlyFusionImputation = isfield(IO,'oocvflag') && IO.oocvflag;
            else
                IO.importReport.missingCasesFilledWithNaN = false;
                IO.importReport.requiresEarlyFusionImputation = false;
            end
        end

        function messages = validateOOCVFeatureSpace(IO, NM, varind)
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOImageImportTools.isAtlasSplitMode(IO) && isfield(IO,'Y') && iscell(IO.Y)
                messages = NMDataIOImageImportTools.validateOOCVAtlasSplitFeatureSpace(IO, NM, varind);
                return;
            end
            expected = NMDataIOImageImportTools.expectedFeatureCount(NM, varind);
            if isnan(expected), return; end
            actual = NMDataIOImageImportTools.imageFeatureCount(IO.Y);
            if ~isnan(actual) && actual ~= expected
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageFeatureSpace', ...
                    sprintf('OOCV imaging modality %g has %g vectorized feature(s), but the trained modality expects %g.', double(varind), actual, expected), 1, 'red*')];
            end
        end

        function messages = validateOOCVAtlasSplitFeatureSpace(IO, NM, varind)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isstruct(NM) || ~isfield(NM,'Y') || ~iscell(NM.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.oocvFeatureSpace', ...
                    'NM2 cannot compare the OOCV atlas-split data with training because the required training modality data are unavailable.', 1, 'red*')];
                return;
            end
            nROI = numel(IO.Y);
            nChecked = 0;
            for r = 1:nROI
                actual = NaN;
                if isnumeric(IO.Y{r}) || islogical(IO.Y{r})
                    actual = double(size(IO.Y{r},2));
                end
                if ~isnan(actual) && actual == 0
                    continue;
                end
                targetVar = double(varind) + r - 1;
                if numel(NM.Y) < targetVar || isempty(NM.Y{targetVar})
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.oocvFeatureSpace', ...
                        sprintf('OOCV atlas splitting produced ROI modality %g, but the corresponding training modality %g does not exist. OOCV atlas splitting must match the training atlas split.', double(r), double(targetVar)), 1, 'red*')];
                    return;
                end
                nChecked = nChecked + 1;
                if isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= targetVar && isstruct(NM.datadescriptor{targetVar})
                    dd = NM.datadescriptor{targetVar};
                    if ~(isfield(dd,'atlasSplit') && logical(dd.atlasSplit))
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.oocvFeatureSpace', ...
                            sprintf('OOCV atlas split generated ROI modality %g for target modality %g, but the trained target modality is not marked as atlasSplit.', double(r), double(targetVar)), 1, 'red*')];
                        return;
                    end
                    if isfield(dd,'atlasSplitIndex') && ~isempty(dd.atlasSplitIndex) && double(dd.atlasSplitIndex) ~= double(r)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.oocvFeatureSpace', ...
                            sprintf('OOCV atlas ROI %g maps to training modality %g, but that training modality belongs to atlas ROI %g.', double(r), double(targetVar), double(dd.atlasSplitIndex)), 1, 'red*')];
                        return;
                    end
                end
                expected = NMDataIOImageImportTools.expectedFeatureCount(NM, targetVar);
                if isnan(expected)
                    continue;
                end
                if ~isnan(actual) && actual ~= expected
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.oocvFeatureSpace', ...
                        sprintf('OOCV atlas split ROI modality %g maps to trained modality %g and has %g feature(s), but the trained modality expects %g.', double(r), double(targetVar), actual, expected), 1, 'red*')];
                    return;
                end
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'atlasSplit.oocvFeatureSpace', ...
                sprintf('OOCV atlas-split features match %g non-empty training ROI modality/modalities starting at modality %g.', double(nChecked), double(varind)), 0, 'green*')];
        end


    end

    methods (Static)
        function [D, messages] = postprocessAtlasCollapseTransfer(D, IO, varind)
            % postprocessAtlasCollapseTransfer  Persist atlas-collapse provenance after the legacy image payload has been transferred.
            %
            % Consumes D, IO, varind; returns D, messages.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            [D, messages] = NMDataIOImageImportTools.postprocessAtlasCollapseTransfer_impl(D, IO, varind);
        end

        function [D, messages] = postprocessAtlasSplitTransfer(D, IO, varind)
            % postprocessAtlasSplitTransfer  Persist atlas-split provenance after the legacy image payload has been transferred.
            %
            % Consumes D, IO, varind; returns D, messages.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            [D, messages] = NMDataIOImageImportTools.postprocessAtlasSplitTransfer_impl(D, IO, varind);
        end

        function [D, messages] = postprocessSurfaceRoiTransfer(D, IO, varind)
            % postprocessSurfaceRoiTransfer  Persist surface-ROI provenance after the legacy surface payload has been transferred.
            %
            % Consumes D, IO, varind; returns D, messages.
            % It sits on the imaging/surface import path before modality metadata and provenance are committed to the target container.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            [D, messages] = NMDataIOImageImportTools.postprocessSurfaceRoiTransfer_impl(D, IO, varind);
        end
    end

    methods (Static, Access = private)
        function txt = shortCaseIDList(cases, maxN)
            if nargin < 2 || isempty(maxN), maxN = 8; end
            cases = NMDataIOImageImportTools.asCellstr(cases);
            if isempty(cases)
                txt = '<none>';
                return;
            end
            n = min(numel(cases), maxN);
            txt = strjoin(cases(1:n), ', ');
            if numel(cases) > n
                txt = sprintf('%s, ...', txt);
            end
        end

        function tf = isLegacyGroupLabelMode(IO)
            mode = lower(strrep(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'labelMode','metadata')), '-', '_'), ' ', '_'));
            tf = ismember(mode, {'legacy_groups','legacy_group','groups','group_blocks','classification_groups','auto_groups','sequential_groups'});
        end

        function messages = validateImageIOConsistency(IO, stage)
            if nargin < 2 || isempty(stage), stage = 'image import'; end
            messages = NMDataIOMessageTools.emptyMessages();
            nRows = NMDataIOImageImportTools.imageRowCount(NMDataIOImageImportTools.fieldOr(IO,'Y',[]));
            nIDs = numel(NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'ID',{})));
            nFiles = size(NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'PP',{})),1);
            if isnan(nRows), return; end
            if nIDs > 0 && nRows ~= nIDs
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageConsistency', ...
                    sprintf('Imaging import inconsistency %s: feature matrix has %g row(s), but %g case ID(s) are defined. Import is blocked to prevent partial NM state.', stage, nRows, nIDs), 1, 'red*')];
            end
            if nFiles > 0 && nRows ~= nFiles
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageConsistency', ...
                    sprintf('Imaging import inconsistency %s: feature matrix has %g row(s), but %g image file row(s) are defined. Import is blocked.', stage, nRows, nFiles), 1, 'red*')];
            end
            if isfield(IO,'label') && ~isempty(IO.label) && size(IO.label,1) ~= nRows
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageConsistency', ...
                    sprintf('Imaging import inconsistency %s: labels have %g row(s), but feature matrix has %g row(s). Import is blocked.', stage, size(IO.label,1), nRows), 1, 'red*')];
            end
            if isfield(IO,'covars') && ~isempty(IO.covars) && size(IO.covars,1) ~= nRows
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'imageConsistency', ...
                    sprintf('Imaging import inconsistency %s: covariates have %g row(s), but feature matrix has %g row(s). Import is blocked.', stage, size(IO.covars,1), nRows), 1, 'red*')];
            end
            if isfield(IO,'Yw') && ~isempty(IO.Yw)
                messages = [messages; NMDataIOImageImportTools.validateWeightingFeatureContract(IO.Y, IO.Yw, stage)];
            end
        end

        function messages = validateWeightingFeatureContract(Y, Yw, stage)
            if nargin < 3 || isempty(stage), stage = 'image import'; end
            messages = NMDataIOMessageTools.emptyMessages();
            if iscell(Y)
                if ~iscell(Yw) || numel(Yw) ~= numel(Y)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'weightingMaps.featureContract', ...
                        sprintf('Weighting/ranking map inconsistency %s: expected one weighting feature matrix per ROI modality (%g), but received %g.', stage, numel(Y), numel(Yw)), 1, 'red*')];
                    return;
                end
                for kk = 1:numel(Y)
                    if ~(isnumeric(Y{kk}) || islogical(Y{kk})) || ~(isnumeric(Yw{kk}) || islogical(Yw{kk})), continue; end
                    if size(Yw{kk},2) ~= size(Y{kk},2)
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'weightingMaps.featureContract', ...
                            sprintf('Weighting/ranking map inconsistency %s: ROI modality %g has %g image feature(s), but weighting map has %g feature(s).', stage, kk, size(Y{kk},2), size(Yw{kk},2)), 1, 'red*')];
                        return;
                    end
                end
            elseif isnumeric(Y) || islogical(Y)
                if ~(isnumeric(Yw) || islogical(Yw)) || size(Yw,2) ~= size(Y,2)
                    nYw = NaN;
                    if isnumeric(Yw) || islogical(Yw), nYw = size(Yw,2); end
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'weightingMaps.featureContract', ...
                        sprintf('Weighting/ranking map inconsistency %s: image modality has %g feature(s), but weighting map has %g feature(s).', stage, size(Y,2), nYw), 1, 'red*')];
                end
            end
        end

        function n = imageRowCount(Y)
            n = NaN;
            if iscell(Y) && ~isempty(Y)
                for i = 1:numel(Y)
                    if isnumeric(Y{i}) || islogical(Y{i})
                        n = size(Y{i},1);
                        return;
                    end
                end
            elseif isnumeric(Y) || islogical(Y)
                n = size(Y,1);
            end
        end


        function [IO, messages] = normalizeAtlasMode(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 1 || ~isstruct(IO), return; end
            st = lower(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'spaceDefType','brainmask')), '-', '_'));
            if isempty(st) || strcmp(st,'mask'), st = 'brainmask'; end
            if ismember(st, {'binary','binmask','brain_mask'}), st = 'brainmask'; end
            if ismember(st, {'roi','parcellation','parcellation_atlas'}), st = 'atlas'; end
            if ~ismember(st, {'brainmask','atlas'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasMode', ...
                    sprintf('Unknown space-defining image type ''%s''. Use brainmask or atlas.', st), 1, 'red*')];
                return;
            end
            IO.spaceDefType = st;
            mode = lower(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasImportMode','voxelwise')), '-', '_'));
            if isempty(mode), mode = 'voxelwise'; end
            if ismember(mode, {'brainmask','mask','voxel','voxelwise_image','voxelwise'}), mode = 'voxelwise'; end
            if ismember(mode, {'split','atlas_split','roi_split','split_modalities','voxelwise_split'}), mode = 'split'; end
            if ismember(mode, {'collapse','atlas_collapse','roi_collapse','roi_summary','summary'}), mode = 'collapse'; end
            if strcmp(st,'brainmask')
                mode = 'voxelwise';
            elseif ~ismember(mode, {'split','collapse','voxelwise'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasMode', ...
                    sprintf('Unknown atlas import mode ''%s''. Use split or collapse.', mode), 1, 'red*')];
                return;
            end
            IO.atlasImportMode = mode;
            method = lower(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseMethod','soft_mean')), '-', '_'));
            if isempty(method), method = 'soft_mean'; end
            if ismember(method, {'mean','weighted_mean'}), method = 'soft_mean'; end
            if ismember(method, {'median','weighted_median'}), method = 'soft_median'; end
            if ~ismember(method, {'soft_mean','soft_median'})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasMode', ...
                    sprintf('Unknown atlas collapse method ''%s''. Use soft_mean or soft_median.', method), 1, 'red*')];
                return;
            end
            IO.atlasCollapseMethod = method;
            if ~isfield(IO,'excludeSubjectZeros') || isempty(IO.excludeSubjectZeros)
                IO.excludeSubjectZeros = true;
            else
                IO.excludeSubjectZeros = logical(IO.excludeSubjectZeros);
            end
        end

        function tf = isSurfaceIO(IO)
            tf = isstruct(IO) && (strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'datasource','')), 'surf') || ...
                strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'sourceType','')), 'surface-list'));
        end

        function tf = isAtlasMode(IO)
            tf = isstruct(IO) && strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'spaceDefType','brainmask')), 'atlas');
        end

        function tf = isAtlasCollapseMode(IO)
            tf = NMDataIOImageImportTools.isAtlasMode(IO) && strcmpi(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasImportMode','voxelwise')), 'collapse');
        end

        function tf = isAtlasSplitMode(IO)
            mode = lower(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasImportMode','voxelwise')), '-', '_'));
            tf = NMDataIOImageImportTools.isAtlasMode(IO) && ismember(mode, {'split','voxelwise_split','split_rois','split_roi'});
        end

        function [IO, messages] = configureAtlasSpaceDefinition(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~NMDataIOImageImportTools.isAtlasMode(IO), return; end
            if ~isfield(IO,'Vmvol') || isempty(IO.Vmvol)
                % OOCV atlas collapse/split imports may intentionally start
                % without a live atlas volume because the trained atlas
                % contract is inherited from datadescriptor{x}.  In that
                % case threshold metadata can be reconstructed from the
                % stored training provenance; the actual atlas support image
                % is resolved later in discreteAtlasReferenceForRead.
                [atlasInfo0, provMessages] = NMDataIOImageImportTools.atlasInfoFromOOCVTrainingProvenance(IO);
                messages = [messages; provMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if ~isempty(atlasInfo0) && atlasInfo0.nROI > 0
                    IO.atlasInfo = atlasInfo0;
                    IO.Thresh = struct('nVml', atlasInfo0.nROI, 'Vml', atlasInfo0.roiIDs(:)', ...
                        'Lm', {atlasInfo0.roiNames(:)}, 'threshop', {{atlasInfo0.thresholdOperator}});
                    IO.threshop = {atlasInfo0.thresholdOperator};
                    IO.threshval = atlasInfo0.roiIDs(:)';
                    IO.threshlabels = atlasInfo0.roiNames(:);
                    return;
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSpace', ...
                    'Atlas mode requires a readable space-defining atlas volume before threshold construction.', 1, 'red*')];
                return;
            end
            [atlasInfo, infoMessages] = NMDataIOImageImportTools.atlasInfoFromIO(IO);
            messages = [messages; infoMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.atlasInfo = atlasInfo;
            IO.Thresh = struct('nVml', atlasInfo.nROI, 'Vml', atlasInfo.roiIDs(:)', ...
                'Lm', {atlasInfo.roiNames(:)}, 'threshop', {{atlasInfo.thresholdOperator}});
            IO.threshop = {atlasInfo.thresholdOperator};
            IO.threshval = atlasInfo.roiIDs(:)';
            IO.threshlabels = atlasInfo.roiNames(:);
            if strcmp(atlasInfo.kind, 'probabilistic4d') && ~NMDataIOImageImportTools.isAtlasCollapseMode(IO)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSpace', ...
                    'Probabilistic 4D atlas maps are currently supported only in atlas collapse mode. Use a discrete label atlas for split-into-modalities mode.', 1, 'red*')];
            end
        end

        function [atlasInfo, messages] = atlasInfoFromIO(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            atlasInfo = struct('kind','discrete3d','nROI',0,'roiIDs',[],'roiNames',{{}}, ...
                'thresholdOperator','eq','spaceDim',[],'usesWeights',false);
            V = NMDataIOImageImportTools.fieldOr(IO,'Vm',[]);
            A = NMDataIOImageImportTools.fieldOr(IO,'Vmvol',[]);
            if isempty(A)
                [atlasInfo0, provMessages] = NMDataIOImageImportTools.atlasInfoFromOOCVTrainingProvenance(IO);
                messages = [messages; provMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if ~isempty(atlasInfo0) && atlasInfo0.nROI > 0
                    atlasInfo = atlasInfo0;
                    return;
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasInfo', 'Atlas volume is empty.', 1, 'red*')];
                return;
            end
            if isstruct(V) && numel(V) > 1
                nROI = numel(V);
                atlasInfo.kind = 'probabilistic4d';
                atlasInfo.nROI = nROI;
                atlasInfo.roiIDs = 1:nROI;
                atlasInfo.thresholdOperator = 'soft4d';
                atlasInfo.usesWeights = true;
                atlasInfo.spaceDim = double(V(1).dim);
            elseif ndims(A) == 4 && size(A,4) > 1
                nROI = size(A,4);
                atlasInfo.kind = 'probabilistic4d';
                atlasInfo.nROI = nROI;
                atlasInfo.roiIDs = 1:nROI;
                atlasInfo.thresholdOperator = 'soft4d';
                atlasInfo.usesWeights = true;
                if isstruct(V), atlasInfo.spaceDim = double(V(1).dim); else, atlasInfo.spaceDim = size(A(:,:,:,1)); end
            else
                vals = unique(A(:));
                vals = vals(isfinite(vals) & vals ~= 0);
                vals = vals(:)';
                if isempty(vals)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasInfo', ...
                        'Atlas image contains no finite non-zero ROI labels.', 1, 'red*')];
                    return;
                end
                atlasInfo.kind = 'discrete3d';
                atlasInfo.nROI = numel(vals);
                atlasInfo.roiIDs = double(vals);
                atlasInfo.thresholdOperator = 'eq';
                atlasInfo.usesWeights = false;
                if isstruct(V), atlasInfo.spaceDim = double(V(1).dim); else, atlasInfo.spaceDim = size(A); end
            end
            [names, labelMessages, labelInfo] = NMDataIOImageImportTools.resolveAtlasLabelNames(IO, atlasInfo);
            messages = [messages; labelMessages];
            atlasInfo.roiNames = names;
            atlasInfo.labelDescriptor = labelInfo;
            atlasInfo.roiNameSource = NMDataIOImageImportTools.fieldOr(labelInfo,'roiNameSource','generated');
        end


        function [atlasInfo, messages] = atlasInfoFromOOCVTrainingProvenance(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            atlasInfo = [];
            if ~isstruct(IO) || ~isfield(IO,'oocvflag') || ~logical(IO.oocvflag) || ~NMDataIOImageImportTools.isAtlasMode(IO)
                return;
            end
            mode = lower(strrep(NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasImportMode','voxelwise')), '-', '_'));
            if ismember(mode, {'split','voxelwise_split','split_rois','split_roi'})
                prov = NMDataIOImageImportTools.fieldOr(IO,'atlasSplitTrainingProvenance',struct());
            elseif strcmp(mode, 'collapse')
                prov = NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseTrainingProvenance',struct());
            else
                return;
            end
            if ~isstruct(prov) || ~isfield(prov,'roiIDs') || isempty(prov.roiIDs)
                return;
            end
            roiIDs = double(prov.roiIDs(:)');
            roiIDs = roiIDs(isfinite(roiIDs));
            if isempty(roiIDs), return; end
            roiNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(prov,'roiNames',{}));
            if numel(roiNames) ~= numel(roiIDs)
                featNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(prov,'featureNames',{}));
                if numel(featNames) == numel(roiIDs)
                    roiNames = featNames;
                else
                    roiNames = arrayfun(@(x) sprintf('ROI_%g', x), roiIDs(:), 'UniformOutput', false);
                end
            end
            kind = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(prov,'kind','discrete3d'));
            if isempty(kind), kind = 'discrete3d'; end
            atlasInfo = struct('kind',kind, 'nROI',numel(roiIDs), 'roiIDs',roiIDs, 'roiNames',{roiNames(:)}, ...
                'thresholdOperator','eq', 'spaceDim',[], 'usesWeights',false, ...
                'roiNameSource',NMDataIOImageImportTools.fieldOr(prov,'roiNameSource','training_provenance'), ...
                'labelDescriptor',NMDataIOImageImportTools.fieldOr(prov,'atlasLabelDescriptor',struct()));
            if strcmpi(kind,'probabilistic4d')
                atlasInfo.thresholdOperator = 'soft4d';
                atlasInfo.usesWeights = true;
            end
            dim = NMDataIOImageImportTools.fieldOr(prov,'referenceImageDim',NMDataIOImageImportTools.fieldOr(prov,'voxelSpaceDim',[]));
            if ~isempty(dim), atlasInfo.spaceDim = double(dim); end
            messages = [messages; NMDataIOMessageTools.make('info', false, 'atlasInfo.oocvProvenance', ...
                sprintf('OOCV atlas %s import reused %g ROI threshold definition(s) from the training atlas.', mode, atlasInfo.nROI), 0, 'blue')];
        end

        function [names, messages, info] = resolveAtlasLabelNames(IO, atlasInfo)
            messages = NMDataIOMessageTools.emptyMessages();
            info = struct('roiNameSource','generated','atlasLabelFile','', 'message','');
            labelFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasLabelFile',''));
            if isempty(labelFile)
                cand = NMDataIOAtlasDescriptorTools.detectAtlasDescriptorCandidates(NMDataIOImageImportTools.fieldOr(IO,'maskFile',''));
                info.candidates = cand;
                if strcmp(cand.status,'single')
                    labelFile = cand.files{1};
                    info.roiNameSource = 'auto_detected_sidecar';
                elseif strcmp(cand.status,'multiple')
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasDescriptor', cand.message, 1, 'SystemCommands')];
                elseif strcmp(cand.status,'none')
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasDescriptor', cand.message, 1, 'SystemCommands')];
                end
            else
                info.roiNameSource = 'user_selected_sidecar';
            end
            if ~isempty(labelFile)
                opts = struct('roiIDs', atlasInfo.roiIDs(:)', ...
                    'delimiter', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelDelimiter','auto'), ...
                    'hasHeader', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelHasHeader','auto'), ...
                    'idColumn', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelIDColumn',''), ...
                    'nameColumn', NMDataIOImageImportTools.fieldOr(IO,'atlasLabelNameColumn',''));
                desc = NMDataIOAtlasDescriptorTools.inspectAtlasDescriptor(NMDataIOImageImportTools.fieldOr(IO,'maskFile',''), labelFile, opts);
                info = desc;
                if isfield(desc,'roiNamesByAtlasOrder') && numel(desc.roiNamesByAtlasOrder) == atlasInfo.nROI && ...
                        isfield(desc,'matchSummary') && ~strcmp(desc.matchSummary.status,'none')
                    names = desc.roiNamesByAtlasOrder(:);
                    if strcmp(desc.matchSummary.status,'partial')
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasDescriptor', desc.message, 1, 'SystemCommands')];
                    else
                        messages = [messages; NMDataIOMessageTools.make('ok', false, 'atlasDescriptor', desc.message, 0, 'green*')];
                    end
                    return;
                elseif isfield(desc,'matchSummary') && strcmp(desc.matchSummary.status,'none')
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasDescriptor', desc.message, 1, 'red*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasDescriptor', ...
                        'The ROI description file could not be matched completely to the atlas. NM2 will generate names for unmatched ROIs.', 1, 'SystemCommands')];
                end
            end
            names = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'atlasLabelNames',{}));
            if isempty(names), names = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'threshlabels',{})); end
            if numel(names) ~= atlasInfo.nROI || (numel(names)==1 && strcmpi(strtrim(names{1}), 'Bin Mask'))
                names = cell(atlasInfo.nROI,1);
                for r = 1:atlasInfo.nROI
                    if strcmp(atlasInfo.kind, 'discrete3d')
                        names{r} = sprintf('ROI_%g', atlasInfo.roiIDs(r));
                    else
                        names{r} = sprintf('ROI_%d', r);
                    end
                end
                if ~isfield(info,'roiNameSource') || isempty(info.roiNameSource), info.roiNameSource = 'generated'; end
            else
                names = names(:);
                info.roiNameSource = 'manual_state';
            end
        end

        function [IO, messages] = readAtlasSplitPayload(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            [atlasInfo, infoMessages] = NMDataIOImageImportTools.atlasInfoFromIO(IO);
            messages = [messages; infoMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.atlasInfo = atlasInfo;
            if ~strcmp(atlasInfo.kind, 'discrete3d')
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit', ...
                    'Fast atlas split supports discrete 3D ROI-label atlases only. Probabilistic/4D atlases must use ROI collapse or the legacy path.', 1, 'red*')];
                return;
            end
            if ~isfield(IO,'V') || isempty(IO.V)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit', 'No subject image volumes are available for atlas split.', 1, 'red*')];
                return;
            end

            Vflat = NMDataIOImageImportTools.flattenVolumeCells(IO.V);
            nSub = numel(Vflat);
            nROI = atlasInfo.nROI;
            if nSub == 0 || nROI == 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit', ...
                    sprintf('Atlas split requires at least one subject image and one ROI; found %g subject image(s), %g ROI(s).', nSub, nROI), 1, 'red*')];
                return;
            end

            [targetV, atlasInImageSpace, refMessages] = NMDataIOImageImportTools.discreteAtlasReferenceForRead(IO, Vflat, 'split');
            messages = [messages; refMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            splitPlan = NMDataIOImageImportTools.buildDiscreteAtlasSplitPlan(atlasInImageSpace, atlasInfo);
            if splitPlan.nSupportVoxels == 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit', ...
                    'Fast atlas split found no usable non-zero atlas support voxels after aligning the atlas to the subject-image grid.', 1, 'red*')];
                return;
            end

            missingSupport = find(splitPlan.nVoxelsPerROI == 0);
            if ~isempty(missingSupport)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasSplit.emptyROIs', ...
                    sprintf('Fast atlas split retained all atlas ROI definitions but %g ROI(s) have no voxels after atlas-to-image-space reslicing. Examples: %s', ...
                        numel(missingSupport), NMDataIOImageImportTools.shortNumericList(atlasInfo.roiIDs(missingSupport), 12)), 1, 'SystemCommands')];
            end
            if ~NMDataIOImageImportTools.allVolumesShareGrid(Vflat, targetV)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasSplit.geometry', ...
                    'Fast atlas split aligned the atlas once to the first subject-image grid, but at least one subject image has different dimensions or affine geometry; affected images will be sampled into the first subject grid.', 1, 'SystemCommands')];
            end

            Y = cell(1, nROI);
            for r = 1:nROI
                Y{r} = nan(nSub, splitPlan.nVoxelsPerROI(r));
            end
            gSF = ones(nSub,1);
            if isfield(IO,'globscale') && IO.globscale > 1
                [gSF, scaleMessages] = NMDataIOImageImportTools.proportionalGlobalScaleFactors(IO.g, IO.globnorm, nSub, 'globals.proportional');
                messages = [messages; scaleMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            fprintf('\nFast atlas ROI split: %g subject image(s), %g ROI-defined modality/modalities, %g total voxel feature(s).', ...
                nSub, nROI, splitPlan.nSupportVoxels);
            fprintf('\n\tPrepared atlas support in subject-image space once: %g voxel(s) across %g ROI(s).', splitPlan.nSupportVoxels, nROI);
            tStart = tic;
            progressEvery = max(1, floor(nSub / 20));
            for i = 1:nSub
                if i == 1 || i == nSub || mod(i, progressEvery) == 0
                    fprintf('\n\tSubject %g/%g', i, nSub);
                end
                Vi = Vflat(i);
                if isfield(Vi,'pinfo') && ~isempty(Vi.pinfo)
                    Vi.pinfo(1:2,:) = Vi.pinfo(1:2,:) * gSF(i);
                end
                d = double(NMDataIOImageImportTools.sampleSubjectInImageSpace(Vi, targetV));
                d = d(:);
                for r = 1:nROI
                    idx = splitPlan.roiVoxelIdx{r};
                    if ~isempty(idx)
                        Y{r}(i,:) = d(idx).';
                    end
                end
            end
            if NMDataIOImageImportTools.hasWeightingMaps(IO)
                [IO, weightMessages] = NMDataIOImageImportTools.readAtlasSplitWeightingPayload(IO, targetV, splitPlan);
                messages = [messages; weightMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            fprintf('\nFast atlas ROI split completed in %.1f s; generated %g modality/modalities from %g atlas ROI(s).', toc(tStart), nROI, nROI);

            IO.Y = Y;
            IO.VmvolOriginalAtlas = NMDataIOImageImportTools.fieldOr(IO,'Vmvol',[]);
            IO.VmOriginalAtlas = NMDataIOImageImportTools.fieldOr(IO,'Vm',[]);
            IO.Vmvol = atlasInImageSpace;
            IO.Vm = targetV;
            IO.Thresh = struct('nVml', nROI, 'Vml', atlasInfo.roiIDs(:)', 'Lm', {atlasInfo.roiNames(:)}, 'threshop', {{atlasInfo.thresholdOperator}});
            IO.threshop = {atlasInfo.thresholdOperator};
            IO.threshval = atlasInfo.roiIDs(:)';
            IO.threshlabels = atlasInfo.roiNames(:);
            IO.importReport.atlasSplit = true;
            IO.importReport.atlasImportMode = 'split';
            IO.importReport.atlasSplitFastPath = true;
            IO.importReport.atlasSplitTotalVoxelFeatures = splitPlan.nSupportVoxels;
            IO.importReport.atlasSplitVoxelsPerROI = splitPlan.nVoxelsPerROI(:)';
            IO.atlasSplitProvenance = struct();
            IO.atlasSplitProvenance.kind = atlasInfo.kind;
            IO.atlasSplitProvenance.originalImageFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFilesSpec',NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{})));
            IO.atlasSplitProvenance.brainmaskOrAtlasFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'maskFile',NMDataIOImageImportTools.fieldOr(IO,'brainmask','')));
            IO.atlasSplitProvenance.roiIDs = atlasInfo.roiIDs(:)';
            IO.atlasSplitProvenance.roiNames = atlasInfo.roiNames(:)';
            IO.atlasSplitProvenance.roiNameSource = NMDataIOImageImportTools.fieldOr(atlasInfo,'roiNameSource','generated');
            IO.atlasSplitProvenance.atlasLabelDescriptor = NMDataIOImageImportTools.fieldOr(atlasInfo,'labelDescriptor',struct());
            IO.atlasSplitProvenance.referenceImageFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(targetV,'fname',''));
            IO.atlasSplitProvenance.referenceImageDim = double(targetV.dim(1:3));
            IO.atlasSplitProvenance.referenceImageMat = targetV.mat;
            IO.atlasSplitProvenance.voxelsPerROI = splitPlan.nVoxelsPerROI(:)';
            IO.atlasSplitProvenance.resampling = 'Discrete atlas was resliced once into the first subject-image grid using nearest-neighbour interpolation and rounded ROI labels; subject images were then vectorized in that fixed image-space support.';
        end

        function [IO, messages] = readAtlasCollapsePayload(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            [atlasInfo, infoMessages] = NMDataIOImageImportTools.atlasInfoFromIO(IO);
            messages = [messages; infoMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            IO.atlasInfo = atlasInfo;
            if ~isfield(IO,'V') || isempty(IO.V)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse', 'No subject image volumes are available for atlas collapse.', 1, 'red*')];
                return;
            end
            Vflat = NMDataIOImageImportTools.flattenVolumeCells(IO.V);
            nSub = numel(Vflat);
            nROI = atlasInfo.nROI;
            if nSub == 0 || nROI == 0
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse', ...
                    sprintf('Atlas collapse requires at least one subject image and one ROI; found %g subject image(s), %g ROI(s).', nSub, nROI), 1, 'red*')];
                return;
            end
            Y = nan(nSub, nROI);
            gSF = ones(nSub,1);
            if isfield(IO,'globscale') && IO.globscale > 1
                [gSF, scaleMessages] = NMDataIOImageImportTools.proportionalGlobalScaleFactors(IO.g, IO.globnorm, nSub, 'globals.proportional');
                messages = [messages; scaleMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            fprintf('\nAtlas ROI collapse: %g subject image(s), %g ROI feature(s), method=%s, excludeSubjectZeros=%g', nSub, nROI, IO.atlasCollapseMethod, double(IO.excludeSubjectZeros));
            tStart = tic;

            if strcmp(atlasInfo.kind, 'discrete3d')
                [targetV, atlasInImageSpace, refMessages] = NMDataIOImageImportTools.discreteAtlasReferenceForRead(IO, Vflat, 'collapse');
                messages = [messages; refMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                collapsePlan = NMDataIOImageImportTools.buildDiscreteAtlasCollapsePlan(atlasInImageSpace, atlasInfo);
                if collapsePlan.nSupportVoxels == 0
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse', ...
                        'Atlas collapse found no usable non-zero atlas support voxels after aligning the atlas to the subject-image grid.', 1, 'red*')];
                    return;
                end
                fprintf('\n\tPrepared atlas support in subject-image space: %g voxel(s) across %g ROI(s).', collapsePlan.nSupportVoxels, nROI);
                if ~NMDataIOImageImportTools.allVolumesShareGrid(Vflat, targetV)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasCollapse.geometry', ...
                        'Atlas collapse aligned the atlas once to the first subject-image grid, but at least one subject image has different dimensions or affine geometry; affected images will be sampled into the first subject grid.', 1, 'SystemCommands')];
                end
                progressEvery = max(1, floor(nSub / 20));
                for i = 1:nSub
                    if i == 1 || i == nSub || mod(i, progressEvery) == 0
                        fprintf('\n\tSubject %g/%g', i, nSub);
                    end
                    Vi = Vflat(i);
                    if isfield(Vi,'pinfo') && ~isempty(Vi.pinfo)
                        Vi.pinfo(1:2,:) = Vi.pinfo(1:2,:) * gSF(i);
                    end
                    d = NMDataIOImageImportTools.sampleSubjectInImageSpace(Vi, targetV);
                    Y(i,:) = NMDataIOImageImportTools.collapseSubjectToDiscreteROIs(d, collapsePlan, IO.atlasCollapseMethod, IO.excludeSubjectZeros);
                end
                if NMDataIOImageImportTools.hasWeightingMaps(IO)
                    [IO, weightMessages] = NMDataIOImageImportTools.readAtlasCollapseWeightingPayload(IO, targetV, collapsePlan, atlasInfo);
                    messages = [messages; weightMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                end
                emptyReport = NMDataIOImageImportTools.atlasCollapseEmptyFeatureReport(Y, atlasInfo, logical(IO.excludeSubjectZeros));
                IO.importReport.atlasCollapseEmptyFeatureReport = emptyReport;
                IO.atlasCollapseEmptyFeatureReport = emptyReport;
                if emptyReport.nAllNaN > 0 || emptyReport.nAllZero > 0
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'atlasCollapse.emptyFeatures', ...
                        sprintf('Atlas ROI collapse retained all ROI columns but found %g all-NaN ROI feature(s) and %g all-zero ROI feature(s). Examples: %s', ...
                            emptyReport.nAllNaN, emptyReport.nAllZero, NMDataIOImageImportTools.shortNumericList(emptyReport.exampleProblemROIIDs, 12)), 1, 'SystemCommands')];
                end
            else
                A = IO.Vmvol;
                progressEvery = max(1, floor(nSub / 20));
                for i = 1:nSub
                    if i == 1 || i == nSub || mod(i, progressEvery) == 0
                        fprintf('\n\tSubject %g/%g', i, nSub);
                    end
                    Vi = Vflat(i);
                    if isfield(Vi,'pinfo') && ~isempty(Vi.pinfo)
                        Vi.pinfo(1:2,:) = Vi.pinfo(1:2,:) * gSF(i);
                    end
                    d = NMDataIOImageImportTools.sampleSubjectInAtlasSpace(Vi, IO.Vm(1));
                    d = double(d);
                    for r = 1:nROI
                        w = double(A(:,:,:,r));
                        Y(i,r) = NMDataIOImageImportTools.weightedRoiSummary(d, w, IO.atlasCollapseMethod, IO.excludeSubjectZeros);
                    end
                end
                if NMDataIOImageImportTools.hasWeightingMaps(IO)
                    [IO, weightMessages] = NMDataIOImageImportTools.readProbabilisticAtlasCollapseWeightingPayload(IO, atlasInfo);
                    messages = [messages; weightMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                end
            end
            fprintf('\nAtlas ROI collapse completed in %.1f s; retained %g/%g ROI feature(s).', toc(tStart), size(Y,2), nROI);
            IO.Y = Y;
            IO.featnames = atlasInfo.roiNames(:)';
            IO.Thresh = struct('nVml', nROI, 'Vml', atlasInfo.roiIDs(:)', 'Lm', {atlasInfo.roiNames(:)}, 'threshop', {{atlasInfo.thresholdOperator}});
            IO.importReport.atlasCollapse = true;
            IO.importReport.atlasImportMode = 'collapse';
            IO.importReport.atlasCollapseMethod = IO.atlasCollapseMethod;
            IO.importReport.excludeSubjectZeros = logical(IO.excludeSubjectZeros);
            IO.atlasCollapseProvenance = NMDataIOImageImportTools.atlasCollapseProvenance(IO, atlasInfo);
            IO.roiProvenance = NMDataIOROIProvenanceTools.fromAtlasCollapse(IO.atlasCollapseProvenance, size(Y,2));
            if ~IO.roiProvenance.ok
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse.roiProvenance', ...
                    IO.roiProvenance.message, 1, 'red*')];
                return;
            end
        end

        function tf = hasWeightingMaps(IO)
            tf = isstruct(IO) && ((isfield(IO,'Vw') && ~isempty(IO.Vw)) || ...
                (isfield(IO,'weightingFiles') && ~isempty(NMDataIOImageImportTools.asCellstr(IO.weightingFiles))));
        end

        function [IO, messages] = readAtlasSplitWeightingPayload(IO, targetV, splitPlan)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isfield(IO,'Vw') || isempty(IO.Vw), return; end
            Vw = IO.Vw(:)';
            nW = numel(Vw);
            nROI = splitPlan.nROI;
            Yw = cell(1, nROI);
            for r = 1:nROI
                Yw{r} = nan(nW, splitPlan.nVoxelsPerROI(r));
            end
            fprintf('\n\tReading %g weighting/ranking map(s) in fast atlas split feature space.', nW);
            for w = 1:nW
                d = double(NMDataIOImageImportTools.sampleSubjectInImageSpace(Vw(w), targetV));
                d = d(:);
                for r = 1:nROI
                    idx = splitPlan.roiVoxelIdx{r};
                    if ~isempty(idx)
                        Yw{r}(w,:) = d(idx).';
                    end
                end
            end
            IO.Yw = Yw;
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.hasWeightingMaps = true;
            IO.importReport.weightingMapMode = 'atlas_split_voxelwise';
            IO.importReport.nWeightingMaps = double(nW);
            messages = [messages; NMDataIOMessageTools.make('info', false, 'weightingMaps.atlasSplit', ...
                sprintf('Weighting/ranking maps projected into %g atlas-split ROI modality feature space(s).', nROI), 1, 'SystemCommands')];
        end

        function [IO, messages] = readAtlasCollapseWeightingPayload(IO, targetV, collapsePlan, atlasInfo)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isfield(IO,'Vw') || isempty(IO.Vw), return; end
            Vw = IO.Vw(:)';
            nW = numel(Vw);
            nROI = collapsePlan.nROI;
            Yw = nan(nW, nROI);
            fprintf('\n\tCollapsing %g weighting/ranking map(s) to atlas ROI feature space.', nW);
            for w = 1:nW
                d = NMDataIOImageImportTools.sampleSubjectInImageSpace(Vw(w), targetV);
                Yw(w,:) = NMDataIOImageImportTools.collapseSubjectToDiscreteROIs(d, collapsePlan, 'soft_mean', false);
            end
            IO.Yw = Yw;
            IO.atlasCollapseWeightingProvenance = NMDataIOImageImportTools.atlasWeightingProvenance(IO, atlasInfo, 'discrete_atlas_roi_mean');
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.hasWeightingMaps = true;
            IO.importReport.weightingMapMode = 'atlas_collapse_roi_mean';
            IO.importReport.nWeightingMaps = double(nW);
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'weightingMaps.atlasCollapse', ...
                'Weighting/ranking maps were collapsed to ROI-level mean values to match the atlas-collapse matrix feature space; zeros in weighting maps were retained.', 1, 'SystemCommands')];
        end

        function [IO, messages] = readProbabilisticAtlasCollapseWeightingPayload(IO, atlasInfo)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~isfield(IO,'Vw') || isempty(IO.Vw), return; end
            if ~isfield(IO,'Vmvol') || isempty(IO.Vmvol)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'weightingMaps.atlasCollapse', ...
                    'Cannot collapse weighting/ranking maps for probabilistic atlas mode because atlas probability volumes are unavailable.', 1, 'red*')];
                return;
            end
            Vw = IO.Vw(:)';
            A = IO.Vmvol;
            nW = numel(Vw);
            nROI = atlasInfo.nROI;
            Yw = nan(nW, nROI);
            fprintf('\n\tCollapsing %g weighting/ranking map(s) to probabilistic atlas ROI feature space.', nW);
            for w = 1:nW
                d = double(NMDataIOImageImportTools.sampleSubjectInAtlasSpace(Vw(w), IO.Vm(1)));
                for r = 1:nROI
                    Yw(w,r) = NMDataIOImageImportTools.weightedRoiSummary(d, double(A(:,:,:,r)), 'soft_mean', false);
                end
            end
            IO.Yw = Yw;
            IO.atlasCollapseWeightingProvenance = NMDataIOImageImportTools.atlasWeightingProvenance(IO, atlasInfo, 'probabilistic_atlas_weighted_mean');
            if ~isfield(IO,'importReport') || ~isstruct(IO.importReport), IO.importReport = struct(); end
            IO.importReport.hasWeightingMaps = true;
            IO.importReport.weightingMapMode = 'probabilistic_atlas_collapse_weighted_mean';
            IO.importReport.nWeightingMaps = double(nW);
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'weightingMaps.atlasCollapse', ...
                'Weighting/ranking maps were collapsed to ROI-level weighted means to match the probabilistic atlas-collapse matrix feature space; zeros in weighting maps were retained.', 1, 'SystemCommands')];
        end

        function prov = atlasWeightingProvenance(IO, atlasInfo, mode)
            prov = struct();
            prov.mode = mode;
            prov.weightingFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'weightingFiles',{}));
            if isempty(prov.weightingFiles) && isfield(IO,'Pw') && ~isempty(IO.Pw)
                prov.weightingFiles = NMDataIOImageImportTools.asCellstr(IO.Pw);
            end
            prov.roiIDs = atlasInfo.roiIDs(:)';
            prov.roiNames = atlasInfo.roiNames(:)';
            prov.zeroHandling = 'Zeros in weighting/ranking maps are retained during ROI-level weighting-map collapse; subject-image zero exclusion is not applied to weighting maps.';
        end

        function atlasImage = sampleAtlasInImageSpace(Vm, targetV)
            if NMDataIOImageImportTools.sameVolumeGrid(Vm, targetV)
                atlasImage = spm_read_vols(Vm);
            else
                atlasImage = zeros(targetV.dim(1:3));
                for sl = 1:targetV.dim(3)
                    M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                    % Role-swapped legacy nk_ReturnSubSpaces geometry: sample the
                    % space-defining atlas into the target subject-image grid.
                    % Use nearest-neighbour interpolation for discrete ROI labels;
                    % rounding is retained as a defensive guard against numeric noise.
                    M1 = Vm.mat \ targetV.mat * M;
                    atlasImage(:,:,sl) = spm_slice_vol(Vm, M1, targetV.dim(1:2), 0);
                end
            end
            atlasImage = round(double(atlasImage));
        end

        function [targetV, atlasImage, messages] = discreteAtlasReferenceForRead(IO, Vflat, mode)
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(mode), mode = 'split'; end
            targetV = Vflat(1);
            atlasImage = [];
            useTrainingReference = isfield(IO,'oocvflag') && logical(IO.oocvflag);
            prov = struct();
            if useTrainingReference
                if strcmpi(mode, 'split')
                    prov = NMDataIOImageImportTools.fieldOr(IO,'atlasSplitTrainingProvenance',struct());
                else
                    prov = NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseTrainingProvenance',struct());
                end
                refDim = NMDataIOImageImportTools.fieldOr(prov,'referenceImageDim',NMDataIOImageImportTools.fieldOr(prov,'voxelSpaceDim',[]));
                refMat = NMDataIOImageImportTools.fieldOr(prov,'referenceImageMat',NMDataIOImageImportTools.fieldOr(prov,'voxelSpaceMat',[]));
                if ~isstruct(prov) || isempty(refDim) || isempty(refMat)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasReference.oocv', ...
                        sprintf('OOCV atlas %s import cannot reconstruct the trained reference image grid. Re-import the training atlas modality with the current DataIO version before applying atlas-based OOCV data.', mode), 1, 'red*')];
                    return;
                end
                targetV = NMDataIOImageImportTools.volumeHeaderFromAtlasReferenceProvenance(prov, targetV);
                if isfield(IO,'Vmvol') && ~isempty(IO.Vmvol) && isequal(size(IO.Vmvol), double(targetV.dim(1:3)))
                    atlasImage = round(double(IO.Vmvol));
                    messages = [messages; NMDataIOMessageTools.make('info', false, 'atlasReference.oocv', ...
                        sprintf('OOCV atlas %s import uses the same reference image grid and atlas support as training so that feature ordering remains unchanged.', mode), 0, 'blue')];
                    return;
                end
                [atlasVm, atlasHeaderMessages] = NMDataIOImageImportTools.atlasHeaderFromMaskFile(IO);
                messages = [messages; atlasHeaderMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                if ~isempty(atlasVm)
                    atlasImage = NMDataIOImageImportTools.sampleAtlasInImageSpace(atlasVm(1), targetV);
                    messages = [messages; NMDataIOMessageTools.make('info', false, 'atlasReference.oocv', ...
                        sprintf('OOCV atlas %s import resampled the atlas file into the trained reference image grid to preserve feature ordering.', mode), 0, 'blue')];
                    return;
                end
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasReference.oocv', ...
                    sprintf('OOCV atlas %s import cannot access either the stored training atlas support volume or the original atlas file. Feature counts cannot be made comparable to training.', mode), 1, 'red*')];
                return;
            end
            if ~isfield(IO,'Vm') || isempty(IO.Vm)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasReference', ...
                    sprintf('Atlas %s import requires a readable atlas header.', mode), 1, 'red*')];
                return;
            end
            atlasImage = NMDataIOImageImportTools.sampleAtlasInImageSpace(IO.Vm(1), targetV);
        end

        function Vref = volumeHeaderFromAtlasReferenceProvenance(prov, fallbackV)
            Vref = fallbackV;
            dim = double(NMDataIOImageImportTools.fieldOr(prov,'referenceImageDim',NMDataIOImageImportTools.fieldOr(prov,'voxelSpaceDim',[])));
            mat = double(NMDataIOImageImportTools.fieldOr(prov,'referenceImageMat',NMDataIOImageImportTools.fieldOr(prov,'voxelSpaceMat',[])));
            if numel(dim) >= 3, Vref.dim = reshape(dim(1:3), 1, []); end
            if isequal(size(mat), [4 4]), Vref.mat = mat; end
            fname = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(prov,'referenceImageFile',''));
            if ~isempty(fname), Vref.fname = fname; end
            if ~isfield(Vref,'pinfo') || isempty(Vref.pinfo), Vref.pinfo = [1;0;0]; end
            if ~isfield(Vref,'dt') || isempty(Vref.dt), Vref.dt = [16 0]; end
        end

        function [Vm, messages] = atlasHeaderFromMaskFile(IO)
            messages = NMDataIOMessageTools.emptyMessages();
            Vm = [];
            atlasFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'maskFile',NMDataIOImageImportTools.fieldOr(IO,'brainmask','')));
            if isempty(atlasFile) || exist(atlasFile,'file') ~= 2
                return;
            end
            if ~NMDataIOImageImportTools.isFunctionAvailable('spm_vol')
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasReference.spm', ...
                    'SPM spm_vol is required to reopen the atlas file for OOCV atlas reference-space extraction.', 1, 'red*')];
                return;
            end
            try
                spmFiles = NMDataIOImageFileTools.resolveNiftiFilesForSPM({atlasFile}, 'atlasReference', true);
                if iscell(spmFiles), spmFile = spmFiles{1}; else, spmFile = spmFiles; end
                Vm = spm_vol(spmFile);
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'atlasReference.spm_vol')];
                Vm = [];
            end
        end

        function splitPlan = buildDiscreteAtlasSplitPlan(atlasImage, atlasInfo)
            labs = double(atlasImage(:));
            roiIDs = double(atlasInfo.roiIDs(:)');
            [tf, roiIdx] = ismember(labs, roiIDs);
            support = find(tf & roiIdx > 0 & isfinite(labs));
            splitPlan = struct('nROI', atlasInfo.nROI, 'supportIdx', support(:), ...
                'supportRoiIdx', roiIdx(support(:)), 'roiVoxelIdx', {cell(1, atlasInfo.nROI)}, ...
                'nSupportVoxels', numel(support), 'nVoxelsPerROI', zeros(1, atlasInfo.nROI));
            for r = 1:atlasInfo.nROI
                splitPlan.roiVoxelIdx{r} = support(splitPlan.supportRoiIdx == r);
                splitPlan.nVoxelsPerROI(r) = numel(splitPlan.roiVoxelIdx{r});
            end
        end

        function collapsePlan = buildDiscreteAtlasCollapsePlan(atlasImage, atlasInfo)
            labs = double(atlasImage(:));
            roiIDs = double(atlasInfo.roiIDs(:)');
            [tf, roiIdx] = ismember(labs, roiIDs);
            support = find(tf & roiIdx > 0 & isfinite(labs));
            collapsePlan = struct('nROI', atlasInfo.nROI, 'supportIdx', support(:), ...
                'supportRoiIdx', roiIdx(support(:)), 'roiVoxelIdx', {cell(1, atlasInfo.nROI)}, ...
                'nSupportVoxels', numel(support));
            for r = 1:atlasInfo.nROI
                collapsePlan.roiVoxelIdx{r} = support(collapsePlan.supportRoiIdx == r);
            end
        end

        function y = collapseSubjectToDiscreteROIs(d, collapsePlan, method, excludeZeros)
            d = double(d(:));
            y = nan(1, collapsePlan.nROI);
            method = lower(NMDataIOImageImportTools.asChar(method));
            if strcmp(method, 'soft_mean')
                vals = d(collapsePlan.supportIdx);
                ok = isfinite(vals);
                if excludeZeros, ok = ok & vals ~= 0; end
                if any(ok)
                    roi = collapsePlan.supportRoiIdx(ok);
                    vals = vals(ok);
                    num = accumarray(roi(:), vals(:), [collapsePlan.nROI 1], @sum, 0);
                    den = accumarray(roi(:), 1, [collapsePlan.nROI 1], @sum, 0);
                    yy = nan(collapsePlan.nROI,1);
                    good = den > 0;
                    yy(good) = num(good) ./ den(good);
                    y = yy(:)';
                end
                return;
            end
            for r = 1:collapsePlan.nROI
                idx = collapsePlan.roiVoxelIdx{r};
                if isempty(idx), continue; end
                vals = d(idx);
                ok = isfinite(vals);
                if excludeZeros, ok = ok & vals ~= 0; end
                if ~any(ok), continue; end
                vals = vals(ok);
                if strcmp(method, 'soft_median')
                    y(r) = median(vals);
                else
                    y(r) = mean(vals);
                end
            end
        end

        function d = sampleSubjectInImageSpace(Vi, targetV)
            if NMDataIOImageImportTools.sameVolumeGrid(Vi, targetV) && NMDataIOImageImportTools.isFunctionAvailable('spm_read_vols')
                d = spm_read_vols(Vi);
                if isequal(size(d), double(targetV.dim(1:3)))
                    return;
                end
            end
            d = zeros(targetV.dim(1:3));
            for sl = 1:targetV.dim(3)
                M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                M1 = targetV.mat \ Vi.mat * M;
                d(:,:,sl) = spm_slice_vol(Vi, M1, targetV.dim(1:2), 1);
            end
        end

        function tf = sameVolumeGrid(Va, Vb)
            tf = false;
            if ~isstruct(Va) || ~isstruct(Vb) || ~isfield(Va,'dim') || ~isfield(Vb,'dim') || ~isfield(Va,'mat') || ~isfield(Vb,'mat')
                return;
            end
            if numel(Va.dim) < 3 || numel(Vb.dim) < 3 || ~isequal(double(Va.dim(1:3)), double(Vb.dim(1:3)))
                return;
            end
            if ~isequal(size(Va.mat), [4 4]) || ~isequal(size(Vb.mat), [4 4])
                return;
            end
            tf = max(abs(double(Va.mat(:)) - double(Vb.mat(:)))) <= 1e-5;
        end

        function tf = allVolumesShareGrid(V, targetV)
            tf = true;
            for ii = 1:numel(V)
                if ~NMDataIOImageImportTools.sameVolumeGrid(V(ii), targetV)
                    tf = false;
                    return;
                end
            end
        end

        function report = atlasCollapseEmptyFeatureReport(Y, atlasInfo, zeroExcluded)
            allNaN = all(~isfinite(Y), 1);
            allZero = all(isfinite(Y) & Y == 0, 1);
            problem = allNaN | allZero;
            roiIDs = atlasInfo.roiIDs(:)';
            roiNames = NMDataIOImageImportTools.asCellstr(atlasInfo.roiNames);
            report = struct('nROI', size(Y,2), 'zeroExcluded', logical(zeroExcluded), ...
                'nAllNaN', sum(allNaN), 'nAllZero', sum(allZero), ...
                'allNaNROIIDs', roiIDs(allNaN), 'allZeroROIIDs', roiIDs(allZero), ...
                'exampleProblemROIIDs', roiIDs(problem), ...
                'allNaNROINames', {roiNames(allNaN)}, 'allZeroROINames', {roiNames(allZero)});
        end

        function Vflat = flattenVolumeCells(V)
            if iscell(V)
                Vflat = [];
                for j = 1:numel(V)
                    if isempty(V{j}), continue; end
                    Vflat = [Vflat V{j}(:)']; %#ok<AGROW>
                end
            else
                Vflat = V(:)';
            end
        end

        function d = sampleSubjectInAtlasSpace(Vi, Vm)
            d = zeros(Vm.dim(1:3));
            for sl = 1:Vm.dim(3)
                M = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                M1 = Vm.mat \ Vi.mat * M;
                d(:,:,sl) = spm_slice_vol(Vi, M1, Vm.dim(1:2), 1);
            end
        end

        function y = weightedRoiSummary(d, w, method, excludeZeros)
            d = double(d(:));
            w = double(w(:));
            ok = isfinite(d) & isfinite(w) & w > 0;
            if excludeZeros, ok = ok & d ~= 0; end
            if ~any(ok), y = NaN; return; end
            x = d(ok);
            ww = w(ok);
            switch lower(method)
                case 'soft_median'
                    y = NMDataIOImageImportTools.weightedMedian(x, ww);
                otherwise
                    sw = sum(ww);
                    if sw <= 0 || ~isfinite(sw), y = NaN; else, y = sum(x .* ww) ./ sw; end
            end
        end

        function y = weightedMedian(x, w)
            x = double(x(:)); w = double(w(:));
            ok = isfinite(x) & isfinite(w) & w > 0;
            x = x(ok); w = w(ok);
            if isempty(x), y = NaN; return; end
            [x, ord] = sort(x);
            w = w(ord);
            cw = cumsum(w);
            cutoff = 0.5 * sum(w);
            idx = find(cw >= cutoff, 1, 'first');
            if isempty(idx), y = NaN; else, y = x(idx); end
        end

        function prov = atlasCollapseProvenance(IO, atlasInfo)
            prov = struct();
            prov.kind = atlasInfo.kind;
            prov.originalImageFiles = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'imageFilesSpec',NMDataIOImageImportTools.fieldOr(IO,'imageFiles',{})));
            prov.brainmaskOrAtlasFile = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'maskFile',NMDataIOImageImportTools.fieldOr(IO,'brainmask','')));
            prov.roiIDs = atlasInfo.roiIDs(:)';
            prov.roiNames = atlasInfo.roiNames(:)';
            prov.roiNameSource = NMDataIOImageImportTools.fieldOr(atlasInfo,'roiNameSource','generated');
            prov.atlasLabelDescriptor = NMDataIOImageImportTools.fieldOr(atlasInfo,'labelDescriptor',struct());
            prov.atlasContentHash = '';
            if strcmp(atlasInfo.kind,'discrete3d') && isfield(IO,'Vmvol') && ~isempty(IO.Vmvol)
                prov.atlasContentHash = NMImagingContentIdentity.hashArray(IO.Vmvol,'double');
            end
            prov.voxelSpaceDim = atlasInfo.spaceDim;
            if isfield(IO,'Vm') && ~isempty(IO.Vm) && isfield(IO.Vm(1),'mat'), prov.voxelSpaceMat = IO.Vm(1).mat; end
            % Keep explicit referenceImage* aliases for parity with the
            % split-ROI provenance used by OOCV feature-space reconstruction.
            prov.referenceImageDim = prov.voxelSpaceDim;
            if isfield(prov,'voxelSpaceMat'), prov.referenceImageMat = prov.voxelSpaceMat; end
            if isfield(IO,'Vm') && ~isempty(IO.Vm) && isfield(IO.Vm(1),'fname')
                prov.referenceImageFile = NMDataIOImageImportTools.asChar(IO.Vm(1).fname);
            end
            prov.collapseMethod = NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseMethod','soft_mean'));
            prov.excludeSubjectZeros = logical(NMDataIOImageImportTools.fieldOr(IO,'excludeSubjectZeros',true));
            prov.roiWeighting = atlasInfo.kind;
            prov.columnToROI = atlasInfo.roiIDs(:)';
            prov.featureNames = atlasInfo.roiNames(:)';
            prov.resampling = 'Discrete atlas collapse aligns the atlas once to the subject-image grid using the role-swapped nk_ReturnSubSpaces geometry (M1 = Vm.mat \ targetV.mat * M), nearest-neighbour label interpolation, and rounding of resliced atlas values before ROI assignment; probabilistic atlases retain subject-to-atlas sampling.';
            prov.emptyFeatureReport = NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseEmptyFeatureReport',struct());
        end

        function [D, messages] = postprocessAtlasCollapseTransfer_impl(D, IO, varind)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~NMDataIOImageImportTools.isAtlasCollapseMode(IO), return; end
            if ~isstruct(D) || ~isfield(D,'Y') || numel(D.Y) < varind || isempty(D.Y{varind})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse.transfer', ...
                    'Atlas collapse transfer did not create the expected matrix modality.', 1, 'red*')];
                return;
            end
            nFeat = size(D.Y{varind},2);
            featnames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'featnames',{}));
            if numel(featnames) ~= nFeat
                featnames = arrayfun(@(i) sprintf('ROI_%d', i), 1:nFeat, 'UniformOutput', false);
            end
            D.featnames{varind} = featnames(:)';
            D.badcoords{varind} = false(1,nFeat);
            if isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind})
                D.datadescriptor{varind}.type = 0;
                D.datadescriptor{varind}.source = 'matrix';
                D.datadescriptor{varind}.desc = sprintf('%s [atlas ROI collapse]', NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'desc_data','Image-derived ROI matrix')));
                D.datadescriptor{varind}.desc_label = [];
                D.datadescriptor{varind}.atlasCollapse = true;
                D.datadescriptor{varind}.atlasCollapseProvenance = NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseProvenance',struct());
                D.datadescriptor{varind}.roiProvenance = NMDataIOImageImportTools.fieldOr(IO,'roiProvenance',struct());
                if isfield(IO,'Yw') && ~isempty(IO.Yw)
                    if size(IO.Yw,2) == size(D.Y{varind},2)
                        D.datadescriptor{varind}.Yw = IO.Yw;
                        D.datadescriptor{varind}.atlasCollapseWeightingProvenance = NMDataIOImageImportTools.fieldOr(IO,'atlasCollapseWeightingProvenance',struct());
                    else
                        messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasCollapse.weightingTransfer', ...
                            sprintf('Atlas-collapse weighting map transfer failed: weighting matrix has %g column(s), but ROI matrix modality has %g feature(s).', size(IO.Yw,2), size(D.Y{varind},2)), 1, 'red*')];
                    end
                end
            end
        end

        function [D, messages] = postprocessAtlasSplitTransfer_impl(D, IO, varind)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~NMDataIOImageImportTools.isAtlasSplitMode(IO), return; end
            if ~isstruct(D) || ~isfield(D,'Y') || ~iscell(D.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.transfer', ...
                    'Atlas split transfer did not create a valid modality cell array.', 1, 'red*')];
                return;
            end
            roiNames = {};
            roiIDs = [];
            if isfield(IO,'atlasSplitProvenance') && isstruct(IO.atlasSplitProvenance)
                roiNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO.atlasSplitProvenance,'roiNames',{}));
                roiIDs = double(NMDataIOImageImportTools.fieldOr(IO.atlasSplitProvenance,'roiIDs',[])); roiIDs = roiIDs(:)';
            elseif isfield(IO,'atlasInfo') && isstruct(IO.atlasInfo)
                roiNames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO.atlasInfo,'roiNames',{}));
                roiIDs = double(NMDataIOImageImportTools.fieldOr(IO.atlasInfo,'roiIDs',[])); roiIDs = roiIDs(:)';
            end
            nROI = max([numel(roiNames), numel(roiIDs), 1]);
            for r = 1:nROI
                v = varind + r - 1;
                if numel(D.Y) < v || isempty(D.Y{v}), continue; end
                nFeat = size(D.Y{v},2);
                if numel(roiNames) >= r && ~isempty(roiNames{r})
                    roiName = roiNames{r};
                elseif numel(roiIDs) >= r
                    roiName = sprintf('ROI_%g', roiIDs(r));
                else
                    roiName = sprintf('ROI_%03d', r);
                end
                if ~isfield(D,'featnames') || numel(D.featnames) < v || isempty(D.featnames{v}) || numel(D.featnames{v}) ~= nFeat
                    if ~isfield(D,'featnames') || isempty(D.featnames), D.featnames = cell(1,v); end
                    D.featnames{v} = arrayfun(@(k)sprintf('%s_vox%06d', roiName, k), 1:nFeat, 'UniformOutput', false);
                end
                if ~isfield(D,'badcoords') || numel(D.badcoords) < v || isempty(D.badcoords{v})
                    if ~isfield(D,'badcoords') || isempty(D.badcoords), D.badcoords = cell(1,v); end
                    D.badcoords{v} = false(1,nFeat);
                end
                if isfield(D,'datadescriptor') && numel(D.datadescriptor) >= v && isstruct(D.datadescriptor{v})
                    D.datadescriptor{v}.type = 2;
                    D.datadescriptor{v}.source = 'nifti';
                    D.datadescriptor{v}.atlasSplit = true;
                    D.datadescriptor{v}.atlasSplitIndex = r;
                    if numel(roiIDs) >= r, D.datadescriptor{v}.atlasSplitRoiID = roiIDs(r); end
                    D.datadescriptor{v}.atlasSplitRoiName = roiName;
                    D.datadescriptor{v}.atlasSplitProvenance = NMDataIOImageImportTools.fieldOr(IO,'atlasSplitProvenance',struct());
                    if isfield(IO,'Yw') && iscell(IO.Yw) && numel(IO.Yw) >= r && ~isempty(IO.Yw{r})
                        if size(IO.Yw{r},2) == nFeat
                            D.datadescriptor{v}.Yw = IO.Yw{r};
                            D.datadescriptor{v}.atlasSplitWeightingProvenance = NMDataIOImageImportTools.fieldOr(IO,'atlasSplitWeightingProvenance',struct());
                        else
                            messages = [messages; NMDataIOMessageTools.make('danger', true, 'atlasSplit.weightingTransfer', ...
                                sprintf('Atlas-split weighting map transfer failed for ROI %g: weighting matrix has %g column(s), but modality has %g feature(s).', r, size(IO.Yw{r},2), nFeat), 1, 'red*')];
                        end
                    end
                end
            end
        end

        function [D, messages] = postprocessSurfaceRoiTransfer_impl(D, IO, varind)
            messages = NMDataIOMessageTools.emptyMessages();
            if ~NMDataIOImageImportTools.isSurfaceNativeRoiMode(IO), return; end
            if ~isstruct(D) || ~isfield(D,'Y') || numel(D.Y) < varind || isempty(D.Y{varind})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'surfaceRoi.transfer', ...
                    'Native surface ROI transfer did not create the expected ROI matrix modality.', 1, 'red*')];
                return;
            end
            nFeat = size(D.Y{varind},2);
            featnames = NMDataIOImageImportTools.asCellstr(NMDataIOImageImportTools.fieldOr(IO,'featnames',{}));
            if numel(featnames) ~= nFeat && isfield(IO,'surfaceRoiInfo') && isstruct(IO.surfaceRoiInfo) && isfield(IO.surfaceRoiInfo,'roiNames')
                featnames = NMDataIOImageImportTools.asCellstr(IO.surfaceRoiInfo.roiNames);
            end
            if numel(featnames) ~= nFeat
                featnames = arrayfun(@(i) sprintf('SurfaceROI_%d', i), 1:nFeat, 'UniformOutput', false);
            end
            D.featnames{varind} = featnames(:)';
            D.badcoords{varind} = false(1,nFeat);
            if isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind})
                D.datadescriptor{varind}.type = 2;
                D.datadescriptor{varind}.source = 'surf';
                D.datadescriptor{varind}.desc = sprintf('%s [surface ROI collapse]', NMDataIOImageImportTools.asChar(NMDataIOImageImportTools.fieldOr(IO,'desc_data','Surface ROI matrix')));
                D.datadescriptor{varind}.desc_label = [];
                D.datadescriptor{varind}.surfaceRoiCollapse = true;
                if isfield(IO,'surfaceRoiInfo') && isstruct(IO.surfaceRoiInfo)
                    D.datadescriptor{varind}.surfaceRoiInfo = IO.surfaceRoiInfo;
                end
                D.datadescriptor{varind}.roiProvenance = NMDataIOImageImportTools.fieldOr(IO,'roiProvenance',struct());
                if isfield(IO,'Yw') && ~isempty(IO.Yw)
                    D.datadescriptor{varind}.surfaceWeightingProvenance = NMDataIOImageImportTools.fieldOr(IO,'surfaceWeightingProvenance',struct());
                end
            end
        end

        function Thresh = thresholdStruct(IO)
            op = IO.threshop;
            if ischar(op) || isstring(op), op = {char(op)}; end
            val = IO.threshval;
            if isempty(val), val = 0; end
            labels = IO.threshlabels;
            if ischar(labels) || isstring(labels), labels = cellstr(string(labels)); end
            if isempty(labels)
                labels = arrayfun(@(i) sprintf('Mask label %g', i), 1:numel(val), 'UniformOutput', false);
            end
            Thresh = struct();
            Thresh.nVml = numel(val);
            Thresh.Vml = double(val(:)');
            Thresh.threshop = op;
            Thresh.Lm = labels(:);
        end

        function [Vinfo, Vvox, Vdim] = volumeInfo(V)
            n = numel(V);
            Vinfo = nan(n,4);
            Vvox = nan(n,3);
            Vdim = nan(n,3);
            for i = 1:n
                if isfield(V(i),'dim') && isnumeric(V(i).dim) && numel(V(i).dim) >= 3
                    Vdim(i,:) = double(V(i).dim(1:3));
                end
                if isfield(V(i),'mat') && isnumeric(V(i).mat) && all(size(V(i).mat) >= [4 4])
                    Vvox(i,:) = sqrt(sum(V(i).mat(1:3,1:3).^2,1));
                    o = V(i).mat \ [0;0;0;1];
                    Vinfo(i,1:3) = o(1:3)';
                    Vinfo(i,4) = 1;
                end
            end
        end

        function ids = resolveCaseIDSpec(ids)
            ids = NMDataIOImageImportTools.asCellstr(ids);
            if isempty(ids)
                ids = {};
                return;
            end
            blankOrUnknown = cellfun(@(x) isempty(strtrim(x)) || strcmp(strtrim(x),'?'), ids(:));
            if all(blankOrUnknown)
                ids = {};
                return;
            end
            if numel(ids) == 1
                name = strtrim(ids{1});
                if ~isempty(name) && ~strcmp(name,'?') && isvarname(name) && ...
                        evalin('base', sprintf('exist(''%s'',''var'')', name))
                    ids = NMDataIOImageImportTools.asCellstr(evalin('base', name));
                    if isempty(ids)
                        ids = {};
                        return;
                    end
                    blankOrUnknown = cellfun(@(x) isempty(strtrim(x)) || strcmp(strtrim(x),'?'), ids(:));
                    if all(blankOrUnknown)
                        ids = {};
                        return;
                    end
                end
            end
            ids = ids(:);
        end

        function txt = rowText(v)
            if isempty(v), txt = ''; return; end
            try
                if iscell(v)
                    c = cellfun(@(x) char(string(x)), v(:)', 'UniformOutput', false);
                    txt = strjoin(c, ', ');
                elseif isnumeric(v) || islogical(v)
                    txt = strtrim(regexprep(num2str(double(v(:)')), '\s+', ', '));
                elseif ischar(v) || (isstring(v) && isscalar(v))
                    txt = char(string(v));
                elseif isstring(v)
                    txt = char(strjoin(string(v(:))', ', '));
                else
                    txt = char(string(v));
                end
            catch
                txt = sprintf('[%s]', class(v));
            end
        end

        function n = expectedFeatureCount(NM, varind)
            n = NaN;
            if isstruct(NM) && isfield(NM,'Y') && numel(NM.Y) >= varind && isnumeric(NM.Y{varind})
                n = double(size(NM.Y{varind},2)); return;
            end
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= varind && isstruct(NM.datadescriptor{varind})
                dd = NM.datadescriptor{varind};
                if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'modalityInfo') && ...
                        isstruct(dd.input_settings.modalityInfo) && isfield(dd.input_settings.modalityInfo,'nFeatures') && ...
                        isnumeric(dd.input_settings.modalityInfo.nFeatures) && isscalar(dd.input_settings.modalityInfo.nFeatures)
                    n = double(dd.input_settings.modalityInfo.nFeatures); return;
                end
            end
            if isstruct(NM) && isfield(NM,'badcoords') && numel(NM.badcoords) >= varind && ~isempty(NM.badcoords{varind})
                n = double(numel(NM.badcoords{varind}));
            end
        end

        function n = imageFeatureCount(Y)
            n = NaN;
            if iscell(Y) && ~isempty(Y) && isnumeric(Y{1}), n = double(size(Y{1},2));
            elseif isnumeric(Y) || islogical(Y), n = double(size(Y,2)); end
        end

        function v = pick(s, names, defaultValue)
            v = defaultValue;
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                if isfield(s,names{i}) && ~isempty(s.(names{i})), v = s.(names{i}); return; end
            end
        end

        function v = pick2(s1, s2, names, defaultValue)
            v = NMDataIOImageImportTools.pick(s2, names, []);
            if isempty(v), v = NMDataIOImageImportTools.pick(s1, names, defaultValue); end
            if isempty(v), v = defaultValue; end
        end

        function out = substructOrEmpty(s, names)
            out = struct();
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                if isfield(s,names{i}) && isstruct(s.(names{i})), out = s.(names{i}); return; end
            end
        end

        function nums = numericVector(v)
            if isempty(v), nums = []; return; end
            if isnumeric(v) || islogical(v)
                nums = double(v(:))';
                return;
            end
            if iscell(v)
                vals = [];
                for i = 1:numel(v)
                    vals = [vals, NMDataIOImageImportTools.numericVector(v{i})]; %#ok<AGROW>
                end
                nums = vals;
                return;
            end
            txt = char(string(v));
            txt = regexprep(txt, '[;\r\n\t]+', ',');
            parts = regexp(txt, ',', 'split');
            vals = nan(1,numel(parts));
            keep = false(1,numel(parts));
            for i = 1:numel(parts)
                t = strtrim(parts{i});
                if isempty(t), continue; end
                x = str2double(t);
                if isfinite(x)
                    vals(i) = x; keep(i) = true;
                end
            end
            nums = vals(keep);
        end

        function c = asCellstr(v)
            if isempty(v), c = {}; return; end
            if iscell(v)
                c = cell(numel(v),1);
                for i = 1:numel(v)
                    c{i} = NMDataIOImageImportTools.asChar(v{i});
                end
                return;
            end
            if ischar(v)
                if isvector(v)
                    c = {reshape(v, 1, [])};
                else
                    c = cellstr(v);
                end
            elseif isstring(v)
                vv = v(:);
                c = cell(numel(vv),1);
                miss = ismissing(vv);
                for i = 1:numel(vv)
                    if miss(i), c{i} = ''; else, c{i} = char(vv(i)); end
                end
            elseif isnumeric(v) || islogical(v)
                vv = v(:);
                c = cell(numel(vv),1);
                for i = 1:numel(vv)
                    if isnumeric(vv) && ~isfinite(double(vv(i)))
                        c{i} = '';
                    else
                        c{i} = char(string(vv(i)));
                    end
                end
            elseif iscategorical(v)
                vv = v(:);
                c = cellstr(vv);
                miss = ismissing(vv);
                c(miss) = {''};
            else
                vv = string(v(:));
                c = cell(numel(vv),1);
                miss = ismissing(vv);
                for i = 1:numel(vv)
                    if miss(i), c{i} = ''; else, c{i} = char(vv(i)); end
                end
            end
            c = c(:);
            for i = 1:numel(c)
                if isempty(c{i})
                    c{i} = '';
                elseif ischar(c{i})
                    c{i} = reshape(c{i}, 1, []);
                else
                    c{i} = reshape(char(string(c{i})), 1, []);
                end
            end
        end

        function s = asChar(v)
            if isempty(v)
                s = '';
            elseif ischar(v)
                if isvector(v), s = reshape(v, 1, []); else, s = strtrim(v(1,:)); end
            elseif isstring(v)
                vv = v(:);
                if isempty(vv) || ismissing(vv(1)), s = ''; else, s = char(vv(1)); end
            elseif iscell(v)
                c = NMDataIOImageImportTools.asCellstr(v);
                if isempty(c), s = ''; else, s = c{1}; end
            elseif isnumeric(v) || islogical(v)
                if ~isfinite(double(v(1))), s = ''; else, s = num2str(v(1)); end
            elseif iscategorical(v)
                vv = v(:);
                if isempty(vv) || ismissing(vv(1))
                    s = '';
                else
                    tmp = cellstr(vv(1));
                    s = tmp{1};
                end
            else
                vv = string(v(:));
                if isempty(vv) || ismissing(vv(1)), s = ''; else, s = char(vv(1)); end
            end
        end

        function v = fieldOr(S, fieldName, defaultValue)
            if nargin < 3, defaultValue = []; end
            if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName)), v = S.(fieldName); else, v = defaultValue; end
        end


        function txt = shortNumericList(v, n)
            if nargin < 2, n = 10; end
            v = double(v(:)');
            if isempty(v), txt = 'none'; return; end
            take = v(1:min(numel(v), n));
            txt = strjoin(arrayfun(@(x)sprintf('%g', x), take, 'UniformOutput', false), ', ');
            if numel(v) > n, txt = [txt ', ...']; end
        end

        function tf = isFunctionAvailable(name)
            if isempty(name), tf = false; return; end
            name = char(string(name));
            ex = exist(name, 'file');
            tf = any(ex == [2 3 5 6 8]) || ~isempty(which(name));
        end

        function v = opt(opts, name, defaultValue)
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name)), v = opts.(name); else, v = defaultValue; end
        end
    end
end
