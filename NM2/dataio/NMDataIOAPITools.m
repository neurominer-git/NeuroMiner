classdef NMDataIOAPITools
% NMDataIOAPITools
% -------------------------------------------------------------------------
% Purpose:
%   Public programmatic DataIO API for scripts, browser services and generated workflows.
%
% Authority and flow:
%   This class hides browser-state layout and importTarget mechanics from callers, normalizes
%   public specs, and delegates scientific materialization/commit to the same DataIO authorities
%   used by the browser. Callers must not configure imports by directly mutating NM scientific
%   fields. Training and OOCV methods share provenance, alignment and label contracts.
%
% Failure semantics:
%   Invalid or incomplete public specs are explicit errors/diagnostics; the API does not invent
%   missing source identity, Case-ID mappings or OOCV class semantics.
% -------------------------------------------------------------------------

    methods (Static)
        function NM = emptyNM()
            % emptyNM  Return an empty NeuroMiner container for public DataIO scripts.
            %
            %   NM = NMDataIOAPITools.emptyNM() returns struct(), providing a
            %   named entry point for generated DataIO API recipes that should
            %   not construct or mutate core NM fields directly.

            NM = struct();
        end

        function [NM, out] = importTrainingMatrix(NM, spec)
            % importTrainingMatrix  Import or add a matrix/table-like training modality through the public DataIO API.
            %
            % [NM, out] = NMDataIOAPITools.importTrainingMatrix(NM, spec)
            % commits a subjects-by-features training modality without exposing
            % the browser import-state layout or directly editing NM.Y,
            % NM.cases, NM.datadescriptor or related training fields.
            %
            % NM is an existing NeuroMiner struct. Pass [] or struct() to
            % create a new training container.
            %
            % spec is a scalar struct. Common fields are:
            % varind                  Target modality index. Default: 1.
            % modeflag                'classification' or 'regression'.
            % description             User-facing modality description.
            % groupnames              Class/group names for classification.
            % sourceType              Matrix source family; usually
            % 'workspace', 'mat', 'table',
            % 'csv', 'xlsx' or 'database' as
            % supported by the DataIO backend.
            % Y                       Workspace variable name containing
            % subjects-by-features data.
            % cases                   Workspace variable name containing
            % case IDs in row order.
            % features                Workspace variable name containing
            % feature names in column order.
            % label                   Workspace variable name containing
            % training labels.
            % covariates              Optional covariate variable name(s).
            % covariateNames          Optional covariate-name variable.
            % caseAlignment           Struct with missing-case policy and
            % ID-mapping options. Defaults allow
            % missing added-modality cases as NaN
            % after successful partial mapping.
            % For sourceType='database', databaseTable selects one ordinary
            % table/view, cases names its Case-ID column, label names the
            % label column, and featureColumns lists feature columns. The API
            % hydrates canonical database source references before entering
            % the generic tabular role/key/alignment materializer.
            % databasePassword remains a transient runtime credential.
            % Advanced multi-object tabular imports may supply variableRoles,
            % metadataAlignmentMode, caseAxisPolicy, tableVariables/tableFiles,
            % sheets and tabularFilters using the canonical generic DataIO contract.
            % finalizeTrainingImport  Logical. If true, finalizes training
            % import and disables later structural
            % training-modality changes.
            %
            % out contains the backend commit report, including out.ok,
            % out.message, out.NM and, when requested, finalization fields.
            %
            % Use this method before CV/template/analysis configuration.
            % Use importOOCVMatrix only after application mode is activated.
            %
            % Example:
            % spec = struct('varind',1,'Y','Y','cases','caseIDs', ...
            % 'features','featureNames','label','label');
            % [NM, out] = NMDataIOAPITools.importTrainingMatrix([], spec);
            %
            % spec.finalizeTrainingImport: requests finalization of the training import after a successful DataIO API import.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            spec = NMDataIOAPITools.normalizeSpec(spec, 'training');
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished) && ...
                    logical(NM.defs.import_finished)
                error('NMDataIOAPITools:trainingImportFinalized', ...
                    ['Training data import has already been finalized. ', ...
                     'Structural training import/add/replace operations are disabled after NM.defs.import_finished=true.']);
            end
            state = NMDataIOAPITools.stateFromMatrixSpec(NM, spec, 'training');
            out = NMDataIOImportTools.commitMatrixImport(NM, state);
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importTrainingMatrix');
            NM = out.NM;
            out.finalizedTrainingImport = false;
            if logical(spec.finalizeTrainingImport)
                if exist('NMDataIOBrowserModeTools','class') ~= 8
                    error('NMDataIOAPITools:missingBrowserModeTools', ...
                        'NMDataIOBrowserModeTools is required to finalize training import through the public DataIO API.');
                end
                [NM, finalizeMessages] = NMDataIOBrowserModeTools.finalizeTrainingImport(NM);
                if exist('NMDataIOMessageTools','class') == 8 && NMDataIOMessageTools.hasFatal(finalizeMessages)
                    error('NMDataIOAPITools:finalizeTrainingImportFailed', ...
                        'Training data were imported, but finalizeTrainingImport reported fatal diagnostics.');
                end
                out.NM = NM;
                out.finalizedTrainingImport = true;
                out.finalizeMessages = finalizeMessages;
            end
        end

        function [NM, out] = importTrainingConnectivity(NM, spec, opts)
            % importTrainingConnectivity  Import ROI-anchored connectivity matrices as a structured matrix modality.
            %
            % [NM, out] = NMDataIOAPITools.importTrainingConnectivity(NM, spec)
            % resolves connectivity inputs through NMDataIOConnectivityTools,
            % commits the resulting subjects-by-edges matrix through the
            % existing matrix DataIO pathway, and stores connectivity
            % provenance in NM.datadescriptor{varind}.connectivity.
            %
            % Supported backend inputs are those normalized by
            % NMDataIOConnectivityTools: 3-D arrays, vectorized edge matrices,
            % edge-column tables, and file-per-subject MAT/CSV square matrices.
            % The ROI sidecar defines node IDs, names and row order. Valid MNI
            % coordinate columns localize nodes directly; atlasFile is required
            % only as a discrete labelled fallback for unresolved coordinates.
            % For table input, nonempty T.Properties.RowNames are used as case
            % IDs without removing any feature variable. If row names are empty,
            % spec.caseColumn must name the case-ID variable at its actual position.
            % Optional manual sidecar mappings are atlasLabelIDColumn,
            % atlasLabelNameColumn, atlasLabelXColumn, atlasLabelYColumn and
            % atlasLabelZColumn (MNI millimetres).
            %
            % This method is training-only. Use a later OOCV connectivity API
            % method for application/OOCV containers.
            %
            % spec.finalizeTrainingImport: requests finalization of the training import after a successful DataIO API import.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMProgressTools.fromOptions(opts, 'Committing connectivity import', 'Reading and validating connectivity data.');
            spec = NMDataIOAPITools.normalizeConnectivitySpec(spec, 'training');
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished) && ...
                    logical(NM.defs.import_finished)
                error('NMDataIOAPITools:trainingImportFinalized', ...
                    ['Training data import has already been finalized. ', ...
                     'Structural training import/add/replace operations are disabled after NM.defs.import_finished=true.']);
            end
            if exist('NMDataIOConnectivityTools','class') ~= 8 && exist('NMDataIOConnectivityTools','file') ~= 2
                error('NMDataIOAPITools:missingConnectivityTools', ...
                    'NMDataIOConnectivityTools.m is required for connectivity imports.');
            end

            progressTask = NMProgressTools.phase(progressTask, 'connectivity_commit_payload', 10, 35, 'Reading and validating connectivity data.');
            [connOut, payloadMessages] = NMDataIOConnectivityTools.resolveConnectivityPayload(spec);
            NMDataIOAPITools.assertMessagesOK(payloadMessages, 'NMDataIOAPITools.importTrainingConnectivity.payload');
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_commit_weighting', 50, 60, 'Reading connectivity weighting maps.');
            [connOut, weightingMessages] = NMDataIOConnectivityTools.resolveWeightingMaps(connOut, spec);
            NMDataIOAPITools.assertMessagesOK(weightingMessages, 'NMDataIOAPITools.importTrainingConnectivity.weighting');
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_commit_subspace', 60, 70, 'Applying connectivity edge subspace selection.');
            [connOut, subspaceMessages] = NMDataIOConnectivityTools.applySubspaceSelection(connOut, spec);
            NMDataIOAPITools.assertMessagesOK(subspaceMessages, 'NMDataIOAPITools.importTrainingConnectivity.subspace');
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_commit_transfer', 70, 90, 'Transferring connectivity edge matrix into NM.');
            state = NMDataIOAPITools.stateFromConnectivitySpec(NM, spec, connOut, 'training');
            out = NMDataIOImportTools.commitMatrixImport(NM, state, struct('ProfileLabel','importTrainingConnectivity'));
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importTrainingConnectivity');
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_commit_descriptor', 90, 98, 'Finalizing connectivity import metadata.');
            out.connectivity = connOut.provenance;
            out.connectivityImportReport = connOut.importReport;
            NM = out.NM;
            out.finalizedTrainingImport = false;
            if logical(spec.finalizeTrainingImport)
                if exist('NMDataIOBrowserModeTools','class') ~= 8
                    error('NMDataIOAPITools:missingBrowserModeTools', ...
                        'NMDataIOBrowserModeTools is required to finalize training import through the public DataIO API.');
                end
                [NM, finalizeMessages] = NMDataIOBrowserModeTools.finalizeTrainingImport(NM);
                if exist('NMDataIOMessageTools','class') == 8 && NMDataIOMessageTools.hasFatal(finalizeMessages)
                    error('NMDataIOAPITools:finalizeTrainingImportFailed', ...
                        'Training data were imported, but finalizeTrainingImport reported fatal diagnostics.');
                end
                out.NM = NM;
                out.finalizedTrainingImport = true;
                out.finalizeMessages = finalizeMessages;
            end
        end

        function [NM, out] = importOOCVConnectivity(NM, spec, opts)
            % importOOCVConnectivity  Import ROI-anchored connectivity matrices into an OOCV/application container.
            %
            % [NM, out] = NMDataIOAPITools.importOOCVConnectivity(NM, spec)
            % resolves OOCV connectivity inputs through
            % NMDataIOConnectivityTools, verifies and reorders the edge space
            % against the selected trained connectivity modality, commits the
            % resulting subjects-by-edges matrix through the existing OOCV
            % matrix DataIO pathway, and stores connectivity provenance in the
            % OOCV datadescriptor.
            %
            % Required fields are the same ROI-sidecar connectivity fields
            % used by importTrainingConnectivity, plus varind and
            % containerIndex/containerField for the OOCV target. OOCV labels
            % are optional; set labelsKnown=false or omit labels for unlabeled
            % application data.
            %
            % spec.varind: selects the modality index addressed by the runner or configuration operation.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            progressTask = NMProgressTools.fromOptions(opts, 'Committing OOCV connectivity import', 'Reading and validating OOCV connectivity data.');
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertApplicationMode(NM, 'NMDataIOAPITools.importOOCVConnectivity');
            end
            spec = NMDataIOAPITools.normalizeConnectivitySpec(spec, 'oocv');
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            if exist('NMDataIOConnectivityTools','class') ~= 8 && exist('NMDataIOConnectivityTools','file') ~= 2
                error('NMDataIOAPITools:missingConnectivityTools', ...
                    'NMDataIOConnectivityTools.m is required for connectivity imports.');
            end

            progressTask = NMProgressTools.phase(progressTask, 'oocv_connectivity_training_contract', 10, 20, 'Loading the training connectivity node and edge definition.');
            trainProv = NMDataIOAPITools.trainingConnectivityProvenance(NM, spec.varind);
            progressTask = NMProgressTools.phase(progressTask, 'oocv_connectivity_payload', 20, 45, 'Reading and validating OOCV connectivity data.');
            [connOut, payloadMessages] = NMDataIOConnectivityTools.resolveConnectivityPayload(spec);
            NMDataIOAPITools.assertMessagesOK(payloadMessages, 'NMDataIOAPITools.importOOCVConnectivity.payload');
            progressTask = NMProgressTools.phase(progressTask, 'oocv_connectivity_edge_alignment', 60, 75, 'Matching OOCV connectivity edges to the training edge definition.');
            [connOut, compatMessages, compatReport] = NMDataIOConnectivityTools.alignToTrainingConnectivity(connOut, trainProv, spec);
            NMDataIOAPITools.assertMessagesOK(compatMessages, 'NMDataIOAPITools.importOOCVConnectivity.edgeSpace');

            progressTask = NMProgressTools.phase(progressTask, 'oocv_connectivity_transfer', 75, 92, 'Transferring OOCV connectivity edge matrix into NM.');
            state = NMDataIOAPITools.stateFromConnectivitySpec(NM, spec, connOut, 'oocv');
            out = NMDataIOImportTools.commitMatrixImport(NM, state, struct('ProfileLabel','importOOCVConnectivity'));
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importOOCVConnectivity');
            progressTask = NMProgressTools.phase(progressTask, 'oocv_connectivity_descriptor', 92, 98, 'Finalizing OOCV connectivity import metadata.');
            out.connectivity = connOut.provenance;
            out.connectivityImportReport = connOut.importReport;
            out.connectivityCompatibility = compatReport;
            NM = out.NM;
        end

        function [NM, out] = importTrainingROI(NM, spec, opts)
            % importTrainingROI  Import explicit parcel-wise ROI data with mandatory spatial provenance.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished) && logical(NM.defs.import_finished)
                error('NMDataIOAPITools:trainingImportFinalized', ...
                    'Training data import has already been finalized. Structural training import/add/replace operations are disabled.');
            end
            if isfield(opts,'ProgressTask') && isstruct(opts.ProgressTask)
                progressTask = opts.ProgressTask;
            else
                progressTask = NMProgressTools.fromOptions(opts, 'Committing ROI import', 'Reading ROI data and validating the spatial reference.');
            end
            spec = NMDataIOAPITools.normalizeROISpec(spec,'training');
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            progressTask = NMProgressTools.phase(progressTask,'roi_commit_payload',10,65,'Reading ROI data and validating the spatial reference.');
            [roiOut,messages] = NMDataIOROIDirectTools.resolvePayload(spec,progressTask);
            NMDataIOAPITools.assertROIMessagesOK(messages,'NMDataIOAPITools.importTrainingROI.payload');
            if (~isstruct(NM) || ~isfield(NM,'cases') || isempty(NM.cases)) && isempty(roiOut.label)
                labelRefs = {};
                if isfield(spec,'auxiliaryVariableRoles') && isstruct(spec.auxiliaryVariableRoles) && isfield(spec.auxiliaryVariableRoles,'labels')
                    labelRefs = NMDataIOStateTools.roleRefCell(spec.auxiliaryVariableRoles.labels);
                end
                if isempty(labelRefs)
                    error('NMDataIOAPITools:roiLabelsRequired', ...
                        'The first training ROI modality requires labels. Assign labels through auxiliaryVariableRoles or use class-specific CAT12 file lists.');
                end
            end
            progressTask = NMProgressTools.phase(progressTask,'roi_commit_transfer',65,90,'Transferring the ROI matrix into NM.');
            state = NMDataIOAPITools.stateFromROISpec(NM,spec,roiOut,'training');
            out = NMDataIOImportTools.commitMatrixImport(NM,state,struct('ProfileLabel','importTrainingROI'));
            NMDataIOAPITools.assertOutOK(out,'NMDataIOAPITools.importTrainingROI');
            progressTask = NMProgressTools.phase(progressTask,'roi_commit_descriptor',90,98,'Saving the ROI spatial definition.');
            out.roiProvenance = out.NM.datadescriptor{spec.varind}.roiProvenance;
            out.globalVolumeCorrection = out.NM.datadescriptor{spec.varind}.globalVolumeCorrection;
            out.roiImportReport = roiOut.importReport;
            NM = out.NM;
            out.finalizedTrainingImport = false;
            if logical(spec.finalizeTrainingImport)
                [NM,finalizeMessages] = NMDataIOBrowserModeTools.finalizeTrainingImport(NM);
                if NMDataIOMessageTools.hasFatal(finalizeMessages)
                    error('NMDataIOAPITools:finalizeTrainingImportFailed', ...
                        'Training ROI data were imported, but finalizing the training import failed.');
                end
                out.NM = NM;
                out.finalizedTrainingImport = true;
                out.finalizeMessages = finalizeMessages;
            end
        end

        function [NM, out] = importOOCVROI(NM, spec, opts)
            % importOOCVROI  Import ROI data into an OOCV container using the trained canonical ROI order.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertApplicationMode(NM,'NMDataIOAPITools.importOOCVROI');
            end
            if isfield(opts,'ProgressTask') && isstruct(opts.ProgressTask)
                progressTask = opts.ProgressTask;
            else
                progressTask = NMProgressTools.fromOptions(opts,'Committing OOCV ROI import','Reading OOCV ROI data and matching ROIs to the training definition.');
            end
            spec = NMDataIOAPITools.normalizeROISpec(spec,'oocv');
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            trainROI = NMDataIOAPITools.trainingROIProvenance(NM,spec.varind);
            contractMessages = NMDataIOAPITools.validateTrainingROIScientificContract(NM,spec.varind,spec);
            NMDataIOAPITools.assertROIMessagesOK(contractMessages,'NMDataIOAPITools.importOOCVROI.scientificContract');
            progressTask = NMProgressTools.phase(progressTask,'oocv_roi_payload',15,55,'Reading OOCV ROI data and validating the spatial reference.');
            [roiOut,messages] = NMDataIOROIDirectTools.resolvePayload(spec,progressTask);
            NMDataIOAPITools.assertROIMessagesOK(messages,'NMDataIOAPITools.importOOCVROI.payload');
            [roiOut,alignMessages] = NMDataIOROIDirectTools.alignToTraining(roiOut,trainROI);
            NMDataIOAPITools.assertROIMessagesOK(alignMessages,'NMDataIOAPITools.importOOCVROI.identity');
            progressTask = NMProgressTools.phase(progressTask,'oocv_roi_transfer',55,90,'Transferring the aligned OOCV ROI matrix into NM.');
            state = NMDataIOAPITools.stateFromROISpec(NM,spec,roiOut,'oocv');
            out = NMDataIOImportTools.commitMatrixImport(NM,state,struct('ProfileLabel','importOOCVROI'));
            NMDataIOAPITools.assertOutOK(out,'NMDataIOAPITools.importOOCVROI');
            [oocvContainer,oocvMessages] = NMDataIOImportTargetTools.getContainer(out.NM,out.importTarget);
            NMDataIOAPITools.assertROIMessagesOK(oocvMessages,'NMDataIOAPITools.importOOCVROI.descriptor');
            out.roiProvenance = oocvContainer.datadescriptor{spec.varind}.roiProvenance;
            out.globalVolumeCorrection = oocvContainer.datadescriptor{spec.varind}.globalVolumeCorrection;
            out.roiImportReport = roiOut.importReport;
            NM = out.NM;
        end

        function [NM, out] = importOOCVMatrix(NM, spec)
            % importOOCVMatrix  Import matrix/table-like OOCV data through the public DataIO API.
            %
            %   [NM, out] = NMDataIOAPITools.importOOCVMatrix(NM, spec)
            %   commits an independent/application dataset into NM.OOCV{k}
            %   without directly editing the OOCV container. The method requires
            %   application/OOCV mode and validates feature/case alignment against
            %   the corresponding trained modality.
            %
            %   Required workflow:
            %       1. Import/finalize training data.
            %       2. Configure and train at least one analysis.
            %       3. Call NMAnalysisManagerTools.activateApplicationMode.
            %       4. Import OOCV data with this method.
            %
            %   spec is a scalar struct. Common fields are:
            %       varind          Target trained modality index.
            %       containerIndex  OOCV container index. Default: 1.
            %       containerField  OOCV container field. Default: 'OOCV'.
            %       labelsKnown     Logical; whether OOCV labels are supplied.
            %                       If omitted, inferred from whether labels are supplied.
            %       description     OOCV container/modality description.
            %       sourceType      Matrix/table/database source family.
            %       Y               Workspace variable name with OOCV data.
            %       cases           Workspace variable name with OOCV case IDs.
            %       features        Workspace variable name with feature names.
            %                       Feature names are mapped to the trained
            %                       feature space; no-overlap mappings block.
            %       label           Optional label variable; labelsKnown is inferred true when supplied.
            %       covariates      Optional covariate variable name(s).
            %       caseAlignment   Struct with missing-case / mapping options.
            %       For sourceType='database', databaseTable selects one ordinary
            %       table/view, cases names its Case-ID column, label optionally
            %       names the known OOCV label column, and featureColumns lists
            %       feature columns. The same generic OOCV materializer is used.
            %       Advanced multi-object tabular imports may supply variableRoles,
            %       metadataAlignmentMode, caseAxisPolicy, tableVariables/tableFiles,
            %       sheets and tabularFilters using the canonical generic DataIO contract.
            %
            %   out contains the backend commit report. On success, NM.OOCV{k}
            %   contains the imported data aligned to the trained modality.
            %
            %   Example:
            %       spec = struct('varind',1,'containerIndex',1, ...
            %           'Y','Ytest','cases','caseIDs_test', ...
            %           'features','featureNames','labelsKnown',false);
            %       [NM, out] = NMDataIOAPITools.importOOCVMatrix(NM, spec);

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertApplicationMode(NM, 'NMDataIOAPITools.importOOCVMatrix');
            end
            spec = NMDataIOAPITools.normalizeSpec(spec, 'oocv');
            state = NMDataIOAPITools.stateFromMatrixSpec(NM, spec, 'oocv');
            out = NMDataIOImportTools.commitMatrixImport(NM, state);
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importOOCVMatrix');
            NM = out.NM;
        end

        function [NM, out] = importTrainingImages(NM, spec)
            % importTrainingImages  Import voxel or surface training data through the public DataIO API.
            %
            % [NM, out] = NMDataIOAPITools.importTrainingImages(NM, spec)
            % commits image-like training data through the same backend used by
            % the browser DataIO workflow. It supports voxel/NIfTI-like inputs
            % and registered surface scalar streams via spec.datasource.
            %
            % spec is a scalar struct. Common fields are:
            % varind          Target modality index. Default: 1.
            % datasource      'nifti' for voxel/image input or 'surf' for
            % registered surface scalar input.
            % imageFiles      Cellstr/char/string array of subject files.
            % caseIds         Optional case IDs. If omitted, case IDs may
            % be derived according to caseIDMode.
            % caseIDMode      Case-ID extraction mode. Default:
            % 'legacy_spm'.
            % maskFile        Brainmask or atlas/ROI-label space-defining file.
            % When atlasFile is supplied, maskFile is
            % inferred from atlasFile and a separate
            % brainmask is not required.
            % atlasFile       Alias for maskFile when spaceDefType='atlas'.
            % spaceDefType    'brainmask' or 'atlas'. If atlasFile is
            % supplied, defaults to 'atlas'.
            % atlasImportMode 'voxelwise', 'collapse' or 'split'.
            % atlasCollapseMethod
            % 'soft_mean' or 'soft_median' for ROI
            % collapse; zero-valued subject voxels are
            % excluded by default.
            % atlasLabelFile  Optional atlas descriptor/sidecar table.
            % threshop        Mask threshold operator(s). Default: {'gt'}.
            % threshval       Mask threshold value(s). Default: 0.
            % threshlabels    Mask/atlas labels.
            % weightingFiles  Optional weighting/ranking maps. Voxel maps
            % and registered surface scalar maps are stored
            % in NM.datadescriptor{varind}.Yw.
            % labelMode       'metadata' or auto-label mode supported by DataIO.
            % auxiliaryVariableRoles Generic Case-ID/label/covariate role assignments.
            % auxiliarySourceType / auxiliaryAlignmentMode / auxiliaryTableFiles
            %                 Generic auxiliary source and alignment configuration.
            % globalMode      'none', 'proportional' or 'ancova' for
            % volumetric and surface-scalar imaging imports.
            % caseAlignment   Struct with missing-case / mapping options.
            % finalizeTrainingImport  Logical finalization flag.
            %
            % out contains the image-import commit report. This method does
            % not bypass legacy reading/transfer logic; it materializes the
            % browser import state and delegates to commitImageImport.
            % Use importOOCVImages for independent/application data after
            % application mode has been activated.
            %
            % Example voxel import:
            % spec = struct('datasource','nifti','imageFiles',{files}, ...
            % 'maskFile',brainmask,'caseIds',{ids}, ...
            % 'auxiliaryVariableRoles',auxRoles);
            % [NM, out] = NMDataIOAPITools.importTrainingImages([], spec);
            %
            % Example surface import:
            % spec = struct('datasource','surf','imageFiles',{giiFiles}, ...
            % 'caseIds',{ids},'auxiliaryVariableRoles',auxRoles);
            % [NM, out] = NMDataIOAPITools.importTrainingImages([], spec);
            %
            % spec.finalizeTrainingImport: requests finalization of the training import after a successful DataIO API import.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            spec = NMDataIOAPITools.normalizeImageSpec(spec, 'training');
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished) && ...
                    logical(NM.defs.import_finished)
                error('NMDataIOAPITools:trainingImportFinalized', ...
                    ['Training data import has already been finalized. ', ...
                     'Structural training import/add/replace operations are disabled after NM.defs.import_finished=true.']);
            end
            state = NMDataIOAPITools.stateFromImageSpec(NM, spec, 'training');
            out = NMDataIOImportTools.commitImageImport(NM, state);
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importTrainingImages');
            NM = out.NM;
            out.finalizedTrainingImport = false;
            if logical(spec.finalizeTrainingImport)
                if exist('NMDataIOBrowserModeTools','class') ~= 8
                    error('NMDataIOAPITools:missingBrowserModeTools', ...
                        'NMDataIOBrowserModeTools is required to finalize training import through the public DataIO API.');
                end
                [NM, finalizeMessages] = NMDataIOBrowserModeTools.finalizeTrainingImport(NM);
                if exist('NMDataIOMessageTools','class') == 8 && NMDataIOMessageTools.hasFatal(finalizeMessages)
                    error('NMDataIOAPITools:finalizeTrainingImportFailed', ...
                        'Training imaging data were imported, but finalizeTrainingImport reported fatal diagnostics.');
                end
                out.NM = NM;
                out.finalizedTrainingImport = true;
                out.finalizeMessages = finalizeMessages;
            end
        end

        function [NM, out] = importOOCVImages(NM, spec)
            % importOOCVImages  Import voxel or surface OOCV data through the public DataIO API.
            %
            %   [NM, out] = NMDataIOAPITools.importOOCVImages(NM, spec)
            %   commits independent/application image-like data into NM.OOCV{k}
            %   using the target-aware DataIO backend. The method requires
            %   application/OOCV mode and validates the imported feature space
            %   against the corresponding trained modality.
            %
            %   spec is a scalar struct. Common fields are:
            %       varind          Target trained modality index.
            %       containerIndex  OOCV container index. Default: 1.
            %       containerField  OOCV container field. Default: 'OOCV'.
            %       labelsKnown     Logical; whether OOCV labels are supplied.
            %                       Default for image OOCV is false.
            %       datasource      'nifti' or 'surf'.
            %       imageFiles      OOCV subject voxel/surface files.
            %       caseIds         Optional OOCV case IDs.
            %       caseIDMode      Case-ID extraction mode.
            %       maskFile        Optional for OOCV voxel imports when the
            %                       trained modality provides stored spatial
            %                       metadata; otherwise required by backend.
            %       auxiliaryVariableRoles Generic OOCV Case-ID/label/covariate role assignments.
            %       auxiliarySourceType / auxiliaryAlignmentMode / auxiliaryTableFiles
            %                       Generic auxiliary source and alignment configuration.
            %       globalMode      Global-signal handling for volumetric or
            %                       surface-scalar OOCV imports.
            %       caseAlignment   Struct with missing-case / mapping options.
            %
            %   out contains the commit report. On success, NM.OOCV{k}.Y{varind}
            %   is aligned to the trained feature space and can be used by
            %   NMRunTools.applyOOCV.
            %
            %   Example:
            %       spec = struct('varind',1,'containerIndex',1, ...
            %           'datasource','nifti','imageFiles',{testFiles}, ...
            %           'caseIds',{testIDs},'labelsKnown',false);
            %       [NM, out] = NMDataIOAPITools.importOOCVImages(NM, spec);

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertApplicationMode(NM, 'NMDataIOAPITools.importOOCVImages');
            end
            spec = NMDataIOAPITools.normalizeImageSpec(spec, 'oocv');
            state = NMDataIOAPITools.stateFromImageSpec(NM, spec, 'oocv');
            out = NMDataIOImportTools.commitImageImport(NM, state);
            NMDataIOAPITools.assertOutOK(out, 'NMDataIOAPITools.importOOCVImages');
            NM = out.NM;
        end

        function spec = trainingMatrixSpec(varargin)
            % trainingMatrixSpec  Build a training matrix import spec from name/value pairs.
            %
            %   spec = NMDataIOAPITools.trainingMatrixSpec(''Y'',''Y'',...)
            %   returns a scalar struct accepted by importTrainingMatrix. The
            %   function performs no import and has no side effects.

            spec = NMDataIOAPITools.nameValuesToStruct(varargin{:});
            spec.scope = 'training';
            spec = NMDataIOAPITools.normalizeSpec(spec, 'training');
        end

        function spec = oocvMatrixSpec(varargin)
            % oocvMatrixSpec  Build an OOCV/application matrix import spec.
            %
            %   spec = NMDataIOAPITools.oocvMatrixSpec(...) returns a scalar
            %   struct accepted by importOOCVMatrix. The function performs no
            %   import and has no side effects.

            spec = NMDataIOAPITools.nameValuesToStruct(varargin{:});
            spec.scope = 'oocv';
            spec = NMDataIOAPITools.normalizeSpec(spec, 'oocv');
        end


        function spec = trainingImageSpec(varargin)
            % trainingImageSpec  Build a training image/surface import spec.
            %
            %   spec = NMDataIOAPITools.trainingImageSpec(...) returns a scalar
            %   struct accepted by importTrainingImages. The function performs
            %   no import and has no side effects.

            spec = NMDataIOAPITools.nameValuesToStruct(varargin{:});
            spec.scope = 'training';
            spec = NMDataIOAPITools.normalizeImageSpec(spec, 'training');
        end

        function spec = oocvImageSpec(varargin)
            % oocvImageSpec  Build an OOCV/application image/surface import spec.
            %
            %   spec = NMDataIOAPITools.oocvImageSpec(...) returns a scalar
            %   struct accepted by importOOCVImages. The function performs no
            %   import and has no side effects.

            spec = NMDataIOAPITools.nameValuesToStruct(varargin{:});
            spec.scope = 'oocv';
            spec = NMDataIOAPITools.normalizeImageSpec(spec, 'oocv');
        end
        function [roiOut, state, messages, spec] = prepareROIImportState(NM, inputStateOrSpec, opts)
            % prepareROIImportState  Materialize raw ROI input into one validated canonical ROI payload.
            %
            % Purpose:
            %   Own raw direct-ROI source resolution for probe, preview, explicit QC computation,
            %   and commit preparation. It converts user-facing ROI specifications into canonical
            %   subject-by-ROI data and provenance, then prepares the legacy matrix transfer state.
            %
            % Inputs:
            %   NM                Current NeuroMiner container used for import-target context.
            %   inputStateOrSpec  Browser/API ROI state or normalized ROI specification.
            %   opts              Import/materialization options and optional progress task.
            %
            % Outputs:
            %   roiOut    Canonical resolved ROI payload, including Y, caseIDs, featnames and
            %             validated roiProvenance.
            %   state     Matrix-transfer state for probe/preview/commit compatibility.
            %   messages  Structured DataIO diagnostics.
            %   spec      Normalized raw ROI input specification.
            %
            % Authority and flow:
            %   Raw ROI source -> NMDataIOROIDirectTools.resolvePayload -> canonical roiOut ->
            %   downstream import/QC materialization. Canonical consumers must use roiOut or a
            %   persisted materialization derived from it; they must not reconstruct provenance.
            %
            % Materialization and performance:
            %   YES. Depending on source type, this method may parse all subject CAT12 files, read
            %   ROI tables, load labelled atlases/annotations, and scan atlas voxels for validation
            %   and coordinates. Cost can scale with subject count and spatial-reference size.
            %   It must never run during interactive subject switching, Results Viewer navigation,
            %   QC viewer refresh, or UI teardown.
            %
            % Failure semantics:
            %   Malformed source/provenance is returned as explicit blocking diagnostics. There is
            %   no heuristic ROI inference and no fallback to generic matrix source lookup.
            %
            % Side effects:
            %   None on NM. Source files are read; temporary image resolution may occur in lower
            %   DataIO file utilities according to their documented contracts.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(inputStateOrSpec), inputStateOrSpec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if NMDataIOStateTools.isROIState(inputStateOrSpec) || isfield(inputStateOrSpec,'matrix')
                spec = NMDataIOStateTools.stateToROISpec(inputStateOrSpec,NM);
            else
                spec = inputStateOrSpec;
            end
            scope = NMDataIOAPITools.getChar(opts,{'scope','Scope'},'');
            if isempty(scope) && isstruct(spec) && isfield(spec,'scope') && ~isempty(spec.scope), scope=char(string(spec.scope)); end
            if isempty(scope), scope='training'; end
            spec = NMDataIOAPITools.normalizeROISpec(spec,scope);
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            progressTask = NMProgressTools.emptyTaskForLocalUse();
            if isstruct(opts)
                if isfield(opts,'ProgressTask') && isstruct(opts.ProgressTask)
                    progressTask = opts.ProgressTask;
                elseif isfield(opts,'progressTask') && isstruct(opts.progressTask)
                    progressTask = opts.progressTask;
                end
            end
            baseStart = progressTask.phaseStart;
            baseEnd = progressTask.phaseEnd;
            baseSpan = max(0, baseEnd - baseStart);
            trainROI = struct();
            if strcmp(spec.scope,'oocv')
                trainROI = NMDataIOAPITools.trainingROIProvenance(NM,spec.varind);
                contractMessages = NMDataIOAPITools.validateTrainingROIScientificContract(NM,spec.varind,spec);
                if NMDataIOMessageTools.hasFatal(contractMessages)
                    roiOut = struct(); state = struct(); messages = contractMessages; return;
                end
            end
            progressTask = NMProgressTools.phase(progressTask, 'roi_prepare_payload', baseStart, baseStart + 0.90*baseSpan, ...
                'Reading ROI data and validating the spatial reference.');
            [roiOut,messages] = NMDataIOROIDirectTools.resolvePayload(spec,progressTask);
            state = struct();
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if strcmp(spec.scope,'oocv')
                progressTask = NMProgressTools.phase(progressTask, 'roi_prepare_oocv_alignment', baseStart + 0.90*baseSpan, baseStart + 0.96*baseSpan, ...
                    'Matching ROI IDs and order to the training ROI features.');
                [roiOut,alignMessages] = NMDataIOROIDirectTools.alignToTraining(roiOut,trainROI);
                messages=[messages;alignMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            progressTask = NMProgressTools.phase(progressTask, 'roi_prepare_state', baseStart + 0.96*baseSpan, baseStart + 0.99*baseSpan, ...
                'Preparing ROI transfer state.');
            state = NMDataIOAPITools.stateFromROISpec(NM,spec,roiOut,spec.scope);
        end

        function [connOut, state, messages, spec, compatReport] = prepareConnectivityImportState(NM, inputStateOrSpec, opts)
            % prepareConnectivityImportState  Resolve connectivity input into DataIO commit state.
            %
            % [connOut,state,messages,spec] =
            % NMDataIOAPITools.prepareConnectivityImportState(NM,input,opts)
            % normalizes a connectivity spec or browser state, resolves the
            % edge matrix/metadata payload, and returns the matrix DataIO state
            % used by the commit path. It does not commit into NM.
            %
            % prepareConnectivityImportState  Resolve connectivity DataIO without committing.
            % Shared by probe, preview, feature-QC and connectivity viewers so that
            % each path uses the same connectivity edge-space, weighting and
            % subspace-selection contract as importTrainingConnectivity. Case-ID
            % matching and auxiliary roles remain owned by generic DataIO.
            %
            % opts.progressTask: configures optional progress task behavior for this call.
            % opts.ProgressTask: passes the current progress-task handle through nested UI/API operations.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(inputStateOrSpec), inputStateOrSpec = struct(); end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if isfield(inputStateOrSpec, 'sourceType') || isfield(inputStateOrSpec, 'connectivity') || isfield(inputStateOrSpec, 'matrix')
                spec = NMDataIOStateTools.stateToConnectivitySpec(inputStateOrSpec, NM);
            else
                spec = inputStateOrSpec;
            end
            scope = NMDataIOAPITools.getChar(opts, {'scope','Scope'}, '');
            if isempty(scope) && isstruct(spec) && isfield(spec,'scope') && ~isempty(spec.scope)
                scope = char(string(spec.scope));
            end
            if isempty(scope), scope = 'training'; end
            spec = NMDataIOAPITools.normalizeConnectivitySpec(spec, scope);
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            messages = NMDataIOMessageTools.emptyMessages();
            state = struct();
            connOut = struct();
            compatReport = struct();
            progressTask = NMProgressTools.emptyTaskForLocalUse();
            if isstruct(opts)
                if isfield(opts,'ProgressTask') && isstruct(opts.ProgressTask)
                    progressTask = opts.ProgressTask;
                elseif isfield(opts,'progressTask') && isstruct(opts.progressTask)
                    progressTask = opts.progressTask;
                end
            end
            if exist('NMDataIOConnectivityTools','class') ~= 8 && exist('NMDataIOConnectivityTools','file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'NMDataIOAPITools.prepareConnectivityImportState', ...
                    'NMDataIOConnectivityTools.m is required for connectivity import preparation.', 1, 'red*')];
                return;
            end
            baseStart = progressTask.phaseStart;
            baseEnd = progressTask.phaseEnd;
            baseSpan = max(0, baseEnd - baseStart);
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_prepare_payload', baseStart, baseStart + 0.80*baseSpan, 'Reading and validating connectivity data.');
            [connOut, payloadMessages] = NMDataIOConnectivityTools.resolveConnectivityPayload(spec, progressTask);
            messages = [messages; payloadMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end
            if strcmpi(char(string(spec.scope)), 'oocv')
                progressTask = NMProgressTools.phase(progressTask, 'connectivity_prepare_oocv_alignment', baseStart + 0.80*baseSpan, baseStart + 0.95*baseSpan, 'Matching OOCV connectivity edges to the training edge definition.');
                trainProv = NMDataIOAPITools.trainingConnectivityProvenance(NM,spec.varind);
                [connOut, compatMessages, compatReport] = NMDataIOConnectivityTools.alignToTrainingConnectivity(connOut, trainProv, spec);
                messages = [messages; compatMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            else
                resolveWeighting = NMDataIOAPITools.getLogical(opts, {'ResolveWeighting','resolveWeighting'}, true);
                if resolveWeighting
                    progressTask = NMProgressTools.phase(progressTask, 'connectivity_prepare_weighting', baseStart + 0.80*baseSpan, baseStart + 0.88*baseSpan, 'Reading connectivity weighting maps.');
                    [connOut, weightingMessages] = NMDataIOConnectivityTools.resolveWeightingMaps(connOut, spec);
                    messages = [messages; weightingMessages];
                    if NMDataIOMessageTools.hasFatal(messages), return; end
                end
                progressTask = NMProgressTools.phase(progressTask, 'connectivity_prepare_subspace', baseStart + 0.88*baseSpan, baseStart + 0.95*baseSpan, 'Applying connectivity edge subspace selection.');
                [connOut, subspaceMessages] = NMDataIOConnectivityTools.applySubspaceSelection(connOut, spec);
                messages = [messages; subspaceMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
            end
            progressTask = NMProgressTools.phase(progressTask, 'connectivity_prepare_state', baseStart + 0.95*baseSpan, baseStart + 0.99*baseSpan, 'Preparing connectivity DataIO state.');
            state = NMDataIOAPITools.stateFromConnectivitySpec(NM, spec, connOut, spec.scope);
        end


    end

    methods (Static, Access = private)
        function spec = normalizeSpec(spec, scope)
            if nargin < 2 || isempty(scope)
                if isfield(spec,'scope') && ~isempty(spec.scope), scope = char(string(spec.scope)); else, scope = 'training'; end
            end
            if ~isstruct(spec), error('NMDataIOAPITools:badSpec', 'DataIO import spec must be a scalar struct.'); end
            if numel(spec) ~= 1, error('NMDataIOAPITools:badSpecArray', 'DataIO import spec must be scalar.'); end
            rawSpec = spec;
            spec.scope = lower(strtrim(char(string(scope))));
            if ~ismember(spec.scope, {'training','oocv'})
                error('NMDataIOAPITools:badScope', 'Unsupported DataIO import scope: %s.', spec.scope);
            end
            spec.varind = NMDataIOAPITools.getNumber(spec, {'varind','modalityIndex','modality'}, 1);
            spec.varind = max(1, round(double(spec.varind)));
            spec.modeflag = NMDataIOAPITools.getChar(spec, {'modeflag','mode'}, 'classification');
            spec.description = NMDataIOAPITools.getChar(spec, {'description','desc','desc_data'}, sprintf('%s modality %d', spec.scope, spec.varind));
            spec.groupnames = NMDataIOAPITools.getAny(spec, {'groupnames','groupNames','desc_groups'}, {'Class_1','Class_2'});
            spec.sourceType = NMDataIOAPITools.getChar(spec, {'sourceType','dataSourceType'}, 'workspace');
            spec.groupmode = NMDataIOAPITools.getNumber(spec, {'groupmode','sourceMode'}, ...
                NMDataIOStateTools.groupmodeFromSourceType(spec.sourceType, 1));
            spec.Y = NMDataIOAPITools.getChar(spec, {'Y','matrix','matrixVariable','workspaceVariable','M_edit'}, '?');
            spec.cases = NMDataIOAPITools.getChar(spec, {'cases','caseIds','caseIDs','caseVariable','case_edit'}, '?');
            spec.features = NMDataIOAPITools.getChar(spec, {'features','featureNames','featureNamesVariable','featureVariable','col_edit'}, '?');
            spec.label = NMDataIOAPITools.getChar(spec, {'label','labels','labelVariable','label_edit'}, '?');
            spec.covariates = NMDataIOAPITools.getAny(spec, {'covariates','covars','covariateVariables','covar_edit'}, {});
            spec.covariateNames = NMDataIOAPITools.getChar(spec, {'covariateNames','covarNames','covnames_edit'}, '?');
            spec.featureColumns = NMDataIOAPITools.getAny(spec, {'featureColumns','featureColumnNames','feature_edit'}, {});
            spec.ignoreColumns = NMDataIOAPITools.getAny(spec, {'ignoreColumns','ignoredColumns','ignore_edit'}, {});
            spec.tableColumnRoles = NMDataIOAPITools.getAny(spec, {'tableColumnRoles'}, struct());
            if isstruct(spec.tableColumnRoles)
                if isempty(spec.featureColumns) && isfield(spec.tableColumnRoles,'features')
                    spec.featureColumns = spec.tableColumnRoles.features;
                end
                if isempty(spec.ignoreColumns) && isfield(spec.tableColumnRoles,'ignore')
                    spec.ignoreColumns = spec.tableColumnRoles.ignore;
                end
                if isempty(spec.covariates) && isfield(spec.tableColumnRoles,'covariates')
                    spec.covariates = spec.tableColumnRoles.covariates;
                end
            end
            spec.tableVariable = NMDataIOAPITools.getChar(spec, {'tableVariable'}, '?');
            spec.databaseConnector = NMDataIOAPITools.getChar(spec, {'databaseConnector','connector','databaseType'}, 'sqlite_file');
            spec.databaseUrl = NMDataIOAPITools.getChar(spec, {'databaseUrl'}, '?');
            spec.databaseFile = NMDataIOAPITools.getChar(spec, {'databaseFile'}, '?');
            spec.databaseUser = NMDataIOAPITools.getChar(spec, {'databaseUser'}, '?');
            spec.databasePassword = NMDataIOAPITools.getChar(spec, {'databasePassword'}, '?');
            spec.databaseName = NMDataIOAPITools.getChar(spec, {'databaseName','database'}, '?');
            spec.databaseSchema = NMDataIOAPITools.getChar(spec, {'databaseSchema','schema'}, '?');
            spec.databaseTable = NMDataIOAPITools.getChar(spec, {'databaseTable'}, '?');
            spec.databaseUseQuery = NMDataIOAPITools.getLogical(spec, {'databaseUseQuery','useSqlQuery'}, false);
            spec.databaseQuery = NMDataIOAPITools.getChar(spec, {'databaseQuery','sqlQuery','query'}, '?');
            if strcmpi(NMDataIOStateTools.normalizeSourceType(spec.sourceType, spec.groupmode),'database')
                dbInfo = NMDataIODatabaseTools.connectionInfo(spec);
                spec.databaseConnector = dbInfo.connector;
                spec.databaseUrl = dbInfo.url;
                spec.databaseFile = dbInfo.file;
                spec.databaseUser = dbInfo.user;
                spec.databaseName = dbInfo.database;
                spec.databaseSchema = dbInfo.schema;
                spec.databaseTable = dbInfo.table;
                spec.databaseUseQuery = dbInfo.useQuery;
                spec.databaseQuery = dbInfo.query;
            end
            spec.delimit = NMDataIOAPITools.getChar(spec, {'delimit','delimiter'}, 'tab');
            spec.sheet = NMDataIOAPITools.getAny(spec, {'sheet','sheetName'}, '?');
            spec.sheets = NMDataIOAPITools.getAny(spec, {'sheets'}, {});
            spec.headerRow = NMDataIOAPITools.getAny(spec, {'headerRow'}, []);
            spec.headerAutoDetect = NMDataIOAPITools.getLogical(spec, {'headerAutoDetect','headerRowAutoDetect'}, isempty(spec.headerRow));
            spec.uniquelim = NMDataIOAPITools.getNumber(spec, {'uniquelim','dummyCodingUniqueLimit'}, 15);
            spec.covmanage_edit = NMDataIOAPITools.getNumber(spec, {'covmanage_edit','covariateHandling'}, 1);
            spec.nanMapper = NMDataIOAPITools.getAny(spec, {'nanMapper'}, struct());
            spec.caseAlignment = NMDataIOAPITools.getAny(spec, {'caseAlignment','caseAlignmentOptions'}, struct());
            if ~isstruct(spec.caseAlignment), error('NMDataIOAPITools:badCaseAlignment', 'caseAlignment must be a struct when supplied.'); end
            % Advanced generic tabular API contract. These fields expose the same canonical
            % source-block state used by the browser after provenance hydration; scientific
            % matching/materialization remains owned by NMDataIOStateTools/ImportTools.
            spec.variableRoles = NMDataIOAPITools.getAny(spec, {'variableRoles'}, struct());
            if ~isstruct(spec.variableRoles), error('NMDataIOAPITools:badVariableRoles', 'variableRoles must be a struct when supplied.'); end
            spec.metadataAlignmentMode = NMDataIOAPITools.getChar(spec, {'metadataAlignmentMode','alignmentMode'}, 'key_per_block');
            spec.caseAxisPolicy = NMDataIOAPITools.getChar(spec, {'caseAxisPolicy'}, 'complete_case');
            spec.tabularFilters = NMDataIOAPITools.getAny(spec, {'tabularFilters'}, struct([]));
            spec.tableVariables = NMDataIOAPITools.getAny(spec, {'tableVariables'}, {});
            spec.tableFiles = NMDataIOAPITools.getAny(spec, {'tableFiles'}, {});
            if ~isfield(spec.caseAlignment,'missingCasePolicy') || isempty(spec.caseAlignment.missingCasePolicy)
                spec.caseAlignment.missingCasePolicy = 'fill_nan';
            end
            if ~isfield(spec.caseAlignment,'allowMissingCasesAsNaN') || isempty(spec.caseAlignment.allowMissingCasesAsNaN)
                spec.caseAlignment.allowMissingCasesAsNaN = true;
            end
            if ~isfield(spec.caseAlignment,'idMappingMode') || isempty(spec.caseAlignment.idMappingMode)
                spec.caseAlignment.idMappingMode = 'direct';
            end
            if ~isfield(spec.caseAlignment,'mappingApproved') || isempty(spec.caseAlignment.mappingApproved)
                spec.caseAlignment.mappingApproved = false;
            end
            if strcmp(spec.scope,'oocv')
                labelsKnownExplicit = NMDataIOAPITools.hasAnyField(rawSpec, {'labelsKnown','labels_known'});
                labelsSupplied = NMDataIOAPITools.hasLabelPayload(rawSpec, {'label','labels','labelVariable','label_edit'});
                if labelsKnownExplicit
                    spec.labelsKnown = NMDataIOAPITools.getLogical(rawSpec, {'labelsKnown','labels_known'}, false);
                    if ~spec.labelsKnown && labelsSupplied
                        error('NMDataIOAPITools:inconsistentOOCVLabels', ...
                            'OOCV labels were supplied but labelsKnown=false. Set labelsKnown=true or omit the OOCV labels.');
                    end
                else
                    spec.labelsKnown = labelsSupplied;
                end
                spec.containerField = NMDataIOAPITools.getChar(spec, {'containerField','field'}, 'OOCV');
                spec.containerIndex = NMDataIOAPITools.getNumber(spec, {'containerIndex','oocvind','index'}, 1);
                spec.containerIndex = max(1, round(double(spec.containerIndex)));
                spec.finalizeTrainingImport = false;
            else
                spec.labelsKnown = true;
                spec.containerField = '';
                spec.containerIndex = [];
                spec.finalizeTrainingImport = NMDataIOAPITools.getLogical(spec, {'finalizeTrainingImport','finalizeImport','FinalizeTrainingImport'}, false);
            end
        end

        function spec = normalizeImageSpec(spec, scope)
            if ~isstruct(spec), error('NMDataIOAPITools:badSpec', 'Imaging DataIO import spec must be a scalar struct.'); end
            if numel(spec) ~= 1, error('NMDataIOAPITools:badSpecArray', 'Imaging DataIO import spec must be scalar.'); end
            rawSpec = spec;
            spec.scope = lower(strtrim(char(string(scope))));
            if ~ismember(spec.scope, {'training','oocv'})
                error('NMDataIOAPITools:badScope', 'Unsupported imaging DataIO import scope: %s.', spec.scope);
            end
            spec.varind = NMDataIOAPITools.getNumber(spec, {'varind','modalityIndex','modality'}, 1);
            spec.varind = max(1, round(double(spec.varind)));
            spec.modeflag = NMDataIOAPITools.getChar(spec, {'modeflag','mode'}, 'classification');
            spec.description = NMDataIOAPITools.getChar(spec, {'description','desc','desc_data'}, sprintf('%s imaging modality %d', spec.scope, spec.varind));
            spec.groupnames = NMDataIOAPITools.getAny(spec, {'groupnames','groupNames','desc_groups'}, {'Class_1','Class_2'});
            spec.datasource = lower(NMDataIOAPITools.getChar(spec, {'datasource','imageDatasource'}, 'nifti'));
            spec.imageFiles = NMDataIOAPITools.getAny(spec, {'imageFiles','files','P','PP'}, {});
            spec.caseIds = NMDataIOAPITools.getAny(spec, {'caseIds','caseIDs','cases','ID'}, {});
            spec.caseIDMode = NMDataIOAPITools.getChar(spec, {'caseIDMode','caseIdMode','caseIdSource','caseIDSource'}, 'legacy_spm');
            spec.maskFile = NMDataIOAPITools.getChar(spec, {'maskFile','brainmask','spaceDefiningImage','spacedefimg'}, '');
            spec.atlasFile = NMDataIOAPITools.getChar(spec, {'atlasFile','atlas','roiAtlas','roiAtlasFile','parcellationFile'}, '');
            spec.spaceDefType = lower(strrep(NMDataIOAPITools.getChar(spec, {'spaceDefType','spaceDefinitionType','maskType'}, ''), '-', '_'));
            if isempty(spec.maskFile) && ~isempty(spec.atlasFile)
                spec.maskFile = spec.atlasFile;
            end
            if isempty(spec.spaceDefType)
                if ~isempty(spec.atlasFile)
                    spec.spaceDefType = 'atlas';
                else
                    spec.spaceDefType = 'brainmask';
                end
            end
            spec.atlasImportMode = lower(strrep(NMDataIOAPITools.getChar(spec, {'atlasImportMode','spaceDefImportMode','roiImportMode'}, 'voxelwise'), '-', '_'));
            spec.atlasCollapseMethod = lower(strrep(NMDataIOAPITools.getChar(spec, {'atlasCollapseMethod','collapseMethod','roiSummaryMethod'}, 'soft_mean'), '-', '_'));
            spec.excludeSubjectZeros = NMDataIOAPITools.getLogical(spec, {'excludeSubjectZeros','zeroExclusion','excludeZeros'}, true);
            spec.atlasLabelFile = NMDataIOAPITools.getChar(spec, {'atlasLabelFile','atlasDescriptorFile','atlasSidecarFile','roiLabelFile'}, '');
            spec.atlasLabelDelimiter = NMDataIOAPITools.getChar(spec, {'atlasLabelDelimiter','atlasDescriptorDelimiter','roiLabelDelimiter'}, 'auto');
            spec.atlasLabelHasHeader = NMDataIOAPITools.getHeaderFlagChar(spec, {'atlasLabelHasHeader','atlasDescriptorHasHeader','roiLabelHasHeader'}, 'auto');
            spec.atlasLabelIDColumn = NMDataIOAPITools.getChar(spec, {'atlasLabelIDColumn','atlasDescriptorIDColumn','roiIDColumn'}, '');
            spec.atlasLabelNameColumn = NMDataIOAPITools.getChar(spec, {'atlasLabelNameColumn','atlasDescriptorNameColumn','roiNameColumn'}, '');
            spec.threshop = NMDataIOAPITools.getAny(spec, {'threshop','thresholdOperator'}, {'gt'});
            spec.threshval = NMDataIOAPITools.getAny(spec, {'threshval','thresholdValue','Vml'}, 0);
            spec.threshlabels = NMDataIOAPITools.getAny(spec, {'threshlabels','maskLabels','Lm'}, {'Bin Mask'});
            spec.weightingFiles = NMDataIOAPITools.getAny(spec, {'weightingFiles','weightingMaps','Pw'}, {});
            spec.surfaceGeometryFile = NMDataIOAPITools.getChar(spec, {'surfaceGeometryFile'}, '');
            spec.surfaceInflatedGeometryFile = NMDataIOAPITools.getChar(spec, {'surfaceInflatedGeometryFile'}, '');
            spec.auxiliarySourceType = NMDataIOAPITools.getChar(spec, {'auxiliarySourceType'}, 'workspace');
            spec.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOAPITools.getChar(spec, {'auxiliaryAlignmentMode'}, 'case_id'));
            spec.auxiliaryVariableRoles = NMDataIOAPITools.getAny(spec, {'auxiliaryVariableRoles'}, struct());
            if ~isstruct(spec.auxiliaryVariableRoles), error('NMDataIOAPITools:badAuxiliaryVariableRoles', 'auxiliaryVariableRoles must be a struct when supplied.'); end
            spec.auxiliaryTableFiles = NMDataIOAPITools.getAny(spec, {'auxiliaryTableFiles'}, {});
            spec.labelMode = NMDataIOAPITools.getChar(spec, {'labelMode','imageLabelMode','labelsMode'}, 'metadata');
            spec.groupSizes = NMDataIOAPITools.getAny(spec, {'groupSizes','imageGroupSizes','classGroupSizes','n_subjects'}, []);
            spec.groupNames = NMDataIOAPITools.getAny(spec, {'groupNames','imageGroupNames','classGroupNames','desc_groups'}, spec.groupnames);
            spec.covariateNames = NMDataIOAPITools.getAny(spec, {'covariateNames','covnames','covnames_edit'}, {});
            spec.labelNames = NMDataIOAPITools.getAny(spec, {'labelNames','regressionLabelNames','desc_labels'}, {});
            spec.globalMode = NMDataIOAPITools.getChar(spec, {'globalMode','globalScaling','globalsMode'}, 'none');
            spec.globalSource = NMDataIOAPITools.getChar(spec, {'globalSource','globalsSource'}, 'user');
            spec.globalUserSourceType = NMDataIOAPITools.getChar(spec, {'globalUserSourceType'}, 'workspace');
            spec.globalAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOAPITools.getChar(spec, {'globalAlignmentMode'}, 'case_id'));
            spec.globalVariableRoles = NMDataIOAPITools.getAny(spec, {'globalVariableRoles'}, struct());
            if ~isstruct(spec.globalVariableRoles), error('NMDataIOAPITools:badGlobalVariableRoles', 'globalVariableRoles must be a struct when supplied.'); end
            spec.globalTableFiles = NMDataIOAPITools.getAny(spec, {'globalTableFiles'}, {});
            spec.globalName = NMDataIOAPITools.getChar(spec, {'globalName','globalsName'}, 'GlobalSignal');
            spec.globnorm = NMDataIOAPITools.getNumber(spec, {'globnorm','globalNorm','globalMultiplier'}, 1);
            spec.caseAlignment = NMDataIOAPITools.getAny(spec, {'caseAlignment','caseAlignmentOptions'}, struct());
            if ~isstruct(spec.caseAlignment), error('NMDataIOAPITools:badCaseAlignment', 'caseAlignment must be a struct when supplied.'); end
            if ~isfield(spec.caseAlignment,'missingCasePolicy') || isempty(spec.caseAlignment.missingCasePolicy)
                spec.caseAlignment.missingCasePolicy = 'fill_nan';
            end
            if ~isfield(spec.caseAlignment,'allowMissingCasesAsNaN') || isempty(spec.caseAlignment.allowMissingCasesAsNaN)
                spec.caseAlignment.allowMissingCasesAsNaN = true;
            end
            if ~isfield(spec.caseAlignment,'idMappingMode') || isempty(spec.caseAlignment.idMappingMode)
                spec.caseAlignment.idMappingMode = 'direct';
            end
            if ~isfield(spec.caseAlignment,'mappingApproved') || isempty(spec.caseAlignment.mappingApproved)
                spec.caseAlignment.mappingApproved = false;
            end
            if strcmp(spec.scope,'oocv')
                labelsKnownExplicit = NMDataIOAPITools.hasAnyField(rawSpec, {'labelsKnown','labels_known'});
                labelRefs = {};
                if isstruct(spec.auxiliaryVariableRoles) && isfield(spec.auxiliaryVariableRoles,'labels')
                    labelRefs = NMDataIOStateTools.roleRefCell(spec.auxiliaryVariableRoles.labels);
                end
                legacyGroupLabels = strcmpi(spec.labelMode,'legacy_groups') && ~isempty(spec.groupSizes);
                labelsSupplied = ~isempty(labelRefs) || legacyGroupLabels;
                if labelsKnownExplicit
                    spec.labelsKnown = NMDataIOAPITools.getLogical(rawSpec, {'labelsKnown','labels_known'}, false);
                    if ~spec.labelsKnown && labelsSupplied
                        error('NMDataIOAPITools:inconsistentOOCVLabels', ...
                            'OOCV label roles were assigned but labelsKnown=false. Set labelsKnown=true or remove the OOCV label assignment.');
                    end
                else
                    spec.labelsKnown = labelsSupplied;
                end
                spec.containerField = NMDataIOAPITools.getChar(spec, {'containerField','field'}, 'OOCV');
                spec.containerIndex = NMDataIOAPITools.getNumber(spec, {'containerIndex','oocvind','index'}, 1);
                spec.containerIndex = max(1, round(double(spec.containerIndex)));
                spec.finalizeTrainingImport = false;
            else
                spec.labelsKnown = true;
                spec.containerField = '';
                spec.containerIndex = [];
                spec.finalizeTrainingImport = NMDataIOAPITools.getLogical(spec, {'finalizeTrainingImport','finalizeImport','FinalizeTrainingImport'}, false);
            end
        end

        function state = stateFromImageSpec(NM, spec, scope)
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            state = NMDataIOStateTools.defaultMatrixState(NM, spec.varind);
            state.datasource = spec.datasource;
            state.sourceType = 'image-list';
            state.groupmode = -2;
            state.modeflag = spec.modeflag;
            effectiveLabelsKnown = logical(spec.labelsKnown);
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                effectiveLabelsKnown = NMDataIOAPITools.existingOOCVLabelsKnownInNM(NM, spec);
            end
            state.labels_known = effectiveLabelsKnown;
            state.oocvflag = strcmp(scope,'oocv');
            state.desc_data = spec.description;
            state.desc_groups = spec.groupnames;
            state.caseAlignment = spec.caseAlignment;
            state.image = struct();
            state.image.imageFiles = spec.imageFiles;
            state.image.caseIds = spec.caseIds;
            state.image.caseIDMode = spec.caseIDMode;
            state.image.maskFile = spec.maskFile;
            state.image.atlasFile = spec.atlasFile;
            state.image.spaceDefType = spec.spaceDefType;
            state.image.atlasImportMode = spec.atlasImportMode;
            state.image.atlasCollapseMethod = spec.atlasCollapseMethod;
            state.image.excludeSubjectZeros = spec.excludeSubjectZeros;
            state.image.atlasLabelFile = spec.atlasLabelFile;
            state.image.atlasLabelDelimiter = spec.atlasLabelDelimiter;
            state.image.atlasLabelHasHeader = spec.atlasLabelHasHeader;
            state.image.atlasLabelIDColumn = spec.atlasLabelIDColumn;
            state.image.atlasLabelNameColumn = spec.atlasLabelNameColumn;
            state.image.threshop = spec.threshop;
            state.image.threshval = spec.threshval;
            state.image.threshlabels = spec.threshlabels;
            state.image.weightingFiles = spec.weightingFiles;
            state.image.surfaceGeometryFile = spec.surfaceGeometryFile;
            state.image.surfaceInflatedGeometryFile = spec.surfaceInflatedGeometryFile;
            state.image.auxiliarySourceType = spec.auxiliarySourceType;
            state.image.auxiliaryAlignmentMode = spec.auxiliaryAlignmentMode;
            state.image.auxiliaryVariableRoles = spec.auxiliaryVariableRoles;
            state.image.auxiliaryTableFiles = spec.auxiliaryTableFiles;
            state.image.labelMode = spec.labelMode;
            state.image.groupSizes = spec.groupSizes;
            state.image.groupNames = spec.groupNames;
            state.image.covariateNames = spec.covariateNames;
            state.image.labelNames = spec.labelNames;
            state.image.globalMode = spec.globalMode;
            state.image.globalSource = spec.globalSource;
            state.image.globalUserSourceType = spec.globalUserSourceType;
            state.image.globalAlignmentMode = spec.globalAlignmentMode;
            state.image.globalVariableRoles = spec.globalVariableRoles;
            state.image.globalTableFiles = spec.globalTableFiles;
            state.image.globalName = spec.globalName;
            state.image.globnorm = spec.globnorm;
            if strcmp(scope,'oocv')
                state.importTarget = struct('scope','oocv', 'mode','add', 'varind',spec.varind, ...
                    'containerField',spec.containerField, 'containerIndex',spec.containerIndex, ...
                    'labels_known',effectiveLabelsKnown, 'description',spec.description);
            else
                targetMode = NMDataIOAPITools.getChar(spec, {'targetMode','mode'}, 'add');
                if isfield(spec,'importTarget') && isstruct(spec.importTarget) && isfield(spec.importTarget,'mode') && ~isempty(spec.importTarget.mode)
                    targetMode = char(string(spec.importTarget.mode));
                end
                targetMode = lower(strtrim(char(string(targetMode))));
                if isempty(targetMode), targetMode = 'add'; end
                state.importTarget = struct('scope','training', 'mode',targetMode, 'varind',spec.varind);
            end
        end

        function state = stateFromMatrixSpec(NM, spec, scope)
            spec = NMDataIOAPITools.applyCurrentLabelAuthority(NM,spec);
            state = NMDataIOStateTools.defaultMatrixState(NM, spec.varind);
            state.datasource = 'matrix';
            state.sourceType = spec.sourceType;
            state.groupmode = spec.groupmode;
            state.modeflag = spec.modeflag;
            effectiveLabelsKnown = logical(spec.labelsKnown);
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                effectiveLabelsKnown = NMDataIOAPITools.existingOOCVLabelsKnownInNM(NM, spec);
            end
            state.labels_known = effectiveLabelsKnown;
            state.oocvflag = strcmp(scope,'oocv');
            state.desc_data = spec.description;
            state.desc_groups = spec.groupnames;
            state.matrix.sourceType = spec.sourceType;
            state.matrix.M_edit = spec.Y;
            state.matrix.matrix_edit = spec.Y;
            state.matrix.tableVariable = spec.tableVariable;
            state.matrix.databaseConnector = spec.databaseConnector;
            state.matrix.databaseUrl = spec.databaseUrl;
            state.matrix.databaseFile = spec.databaseFile;
            state.matrix.databaseUser = spec.databaseUser;
            state.matrix.databasePassword = spec.databasePassword; % transient runtime credential; persistence authorities strip it
            state.matrix.databaseName = spec.databaseName;
            state.matrix.databaseSchema = spec.databaseSchema;
            state.matrix.databaseTable = spec.databaseTable;
            state.matrix.databaseUseQuery = spec.databaseUseQuery;
            state.matrix.databaseQuery = spec.databaseQuery;
            state.matrix.case_edit = spec.cases;
            state.matrix.col_edit = spec.features;
            state.matrix.label_edit = spec.label;
            state.matrix.covar_edit = spec.covariates;
            state.matrix.covnames_edit = spec.covariateNames;
            state.matrix.feature_edit = spec.featureColumns;
            state.matrix.ignore_edit = spec.ignoreColumns;
            state.matrix.delimit = spec.delimit;
            state.matrix.sheet = spec.sheet;
            state.matrix.sheets = spec.sheets;
            state.matrix.headerRow = spec.headerRow;
            state.matrix.headerAutoDetect = spec.headerAutoDetect;
            state.matrix.uniquelim = spec.uniquelim;
            state.covmanage_edit = spec.covmanage_edit;
            state.matrix.nanMapper = spec.nanMapper;
            state.matrix.caseAlignment = spec.caseAlignment;
            state.caseAlignment = spec.caseAlignment;
            state.matrix.metadataAlignmentMode = spec.metadataAlignmentMode;
            state.matrix.caseAxisPolicy = spec.caseAxisPolicy;
            state.matrix.tabularFilters = spec.tabularFilters;
            state.matrix.tableVariables = spec.tableVariables;
            state.matrix.tableFiles = spec.tableFiles;
            state.matrix.requireFeatureNames = ismember(double(spec.groupmode), [1 2]);
            if ~isempty(fieldnames(spec.variableRoles))
                state.matrix.variableRoles = spec.variableRoles;
            elseif strcmpi(NMDataIOStateTools.normalizeSourceType(spec.sourceType, spec.groupmode),'database')
                [state.matrix.variableRoles, databaseObjects] = NMDataIOAPITools.databaseVariableRolesFromSpec(spec);
                if isempty(state.matrix.sheets), state.matrix.sheets = databaseObjects; end
                if isempty(state.matrix.sheet) || strcmp(char(string(state.matrix.sheet)),'?'), state.matrix.sheet = databaseObjects{1}; end
            end
            if isstruct(spec.tableColumnRoles) && ~isempty(fieldnames(spec.tableColumnRoles))
                state.tableColumnRoles = spec.tableColumnRoles;
                state.matrix.tableColumnRoles = spec.tableColumnRoles;
            end
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                state.matrix.label_edit = '?';
            end
            if strcmp(scope,'oocv')
                state.importTarget = struct('scope','oocv', 'mode','add', 'varind',spec.varind, ...
                    'containerField',spec.containerField, 'containerIndex',spec.containerIndex, ...
                    'labels_known',effectiveLabelsKnown, 'description',spec.description);
            else
                targetMode = NMDataIOAPITools.getChar(spec, {'targetMode','mode'}, 'add');
                if isfield(spec,'importTarget') && isstruct(spec.importTarget) && isfield(spec.importTarget,'mode') && ~isempty(spec.importTarget.mode)
                    targetMode = char(string(spec.importTarget.mode));
                end
                targetMode = lower(strtrim(char(string(targetMode))));
                if isempty(targetMode), targetMode = 'add'; end
                state.importTarget = struct('scope','training', 'mode',targetMode, 'varind',spec.varind);
            end
        end

        function [roles, databaseObjects] = databaseVariableRolesFromSpec(spec)
            % databaseVariableRolesFromSpec  Hydrate one DB table/view into canonical generic source refs.
            % Provenance-specific work ends here; downstream scientific role,
            % key, case-axis and alignment semantics remain generic.
            if logical(spec.databaseUseQuery)
                error('NMDataIOAPITools:databaseQueryRolesRequired', ...
                    'Automatic database API role hydration is defined for ordinary tables/views, not custom SQL.');
            end
            objectName = strtrim(char(string(spec.databaseTable)));
            caseColumn = strtrim(char(string(spec.cases)));
            if isempty(objectName) || strcmp(objectName,'?')
                error('NMDataIOAPITools:databaseTableRequired', ...
                    'Database API import requires databaseTable to name one table/view.');
            end
            if isempty(caseColumn) || strcmp(caseColumn,'?')
                error('NMDataIOAPITools:databaseCaseColumnRequired', ...
                    'Database API import requires cases to name the Case-ID column.');
            end
            featureColumns = cellstr(string(spec.featureColumns));
            featureColumns = featureColumns(:)';
            featureColumns = featureColumns(~cellfun(@(x)isempty(strtrim(x)) || strcmp(strtrim(x),'?'),featureColumns));
            if isempty(featureColumns)
                error('NMDataIOAPITools:databaseFeatureColumnsRequired', ...
                    'Database API import requires featureColumns to list at least one feature column.');
            end
            covariateColumns = cellstr(string(spec.covariates));
            covariateColumns = covariateColumns(:)';
            covariateColumns = covariateColumns(~cellfun(@(x)isempty(strtrim(x)) || strcmp(strtrim(x),'?'),covariateColumns));
            labelColumn = strtrim(char(string(spec.label)));
            if ~logical(spec.labelsKnown) || strcmp(labelColumn,'?'), labelColumn = ''; end

            probeIO = struct('datasource','matrix','sourceType','database','groupmode',6, ...
                'databaseConnector',spec.databaseConnector,'databaseUrl',spec.databaseUrl, ...
                'databaseFile',spec.databaseFile,'databaseUser',spec.databaseUser, ...
                'databasePassword',spec.databasePassword,'databaseName',spec.databaseName, ...
                'databaseSchema',spec.databaseSchema,'databaseTable',objectName, ...
                'databaseUseQuery',false,'databaseQuery','?','sheets',{{objectName}});
            inventory = NMDataIODatabaseTools.probeHeaders(probeIO,struct());
            if ~isstruct(inventory) || ~isfield(inventory,'ok') || ~inventory.ok
                msg = 'Database source hydration failed.';
                if isstruct(inventory) && isfield(inventory,'message') && ~isempty(inventory.message), msg = inventory.message; end
                error('NMDataIOAPITools:databaseSourceHydrationFailed','%s',msg);
            end
            vars = inventory.sourceVariables;
            objectVars = vars(strcmp({vars.sourceObject},objectName));
            objectColumns = {objectVars.name};
            requestedColumns = [{caseColumn} featureColumns covariateColumns];
            if ~isempty(labelColumn), requestedColumns{end+1} = labelColumn; end
            [available,columnIndex] = ismember(requestedColumns,objectColumns);
            if any(~available)
                error('NMDataIOAPITools:databaseColumnUnavailable', ...
                    'Database table/view %s does not contain requested column(s): %s.', ...
                    objectName,strjoin(requestedColumns(~available),', '));
            end

            cursor = 1;
            caseRef = objectVars(columnIndex(cursor)); cursor = cursor + 1;
            nFeatures = numel(featureColumns);
            featureRefs = arrayfun(@(x)x,objectVars(columnIndex(cursor:cursor+nFeatures-1)),'UniformOutput',false)';
            cursor = cursor + nFeatures;
            nCovariates = numel(covariateColumns);
            if nCovariates
                covariateRefs = arrayfun(@(x)x,objectVars(columnIndex(cursor:cursor+nCovariates-1)),'UniformOutput',false)';
            else
                covariateRefs = cell(0,1);
            end
            cursor = cursor + nCovariates;
            labelRefs = cell(0,1);
            if ~isempty(labelColumn), labelRefs = {objectVars(columnIndex(cursor))}; end

            % Supply the canonical Case-ID role once. NMDataIOStateTools then
            % expands it onto each same-source row-bearing block as ordered
            % caseKeyRefs through the existing generic key authority.
            roles = struct('caseId',{{caseRef}},'labels',{labelRefs},'features',{featureRefs}, ...
                'featureNames',{{}},'covariates',{covariateRefs},'covariateNames',{{}});
            databaseObjects = {objectName};
        end

        function spec = normalizeROISpec(spec, scope)
            if nargin < 2 || isempty(scope), scope='training'; end
            if ~isstruct(spec) || ~isscalar(spec)
                error('NMDataIOAPITools:badROISpec','ROI DataIO import spec must be one scalar struct.');
            end
            rawSpec=spec;
            spec.scope=lower(strtrim(char(string(scope))));
            if ~ismember(spec.scope,{'training','oocv'})
                error('NMDataIOAPITools:badROIScope','Unsupported ROI DataIO import scope: %s.',spec.scope);
            end
            spec.varind=NMDataIOAPITools.getNumber(spec,{'varind'},1);
            spec.varind=max(1,round(double(spec.varind)));
            spec.modeflag=NMDataIOAPITools.getChar(spec,{'modeflag'},'classification');
            spec.description=NMDataIOAPITools.getChar(spec,{'description'},sprintf('%s ROI modality %d',spec.scope,spec.varind));
            spec.desc_data=spec.description;
            spec.groupnames=NMDataIOAPITools.getAny(spec,{'groupNames','groupnames'},{'Class_1','Class_2'});
            spec.auxiliarySourceType=NMDataIOAPITools.getChar(spec,{'auxiliarySourceType'},'workspace');
            spec.auxiliaryAlignmentMode=NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOAPITools.getChar(spec,{'auxiliaryAlignmentMode'},'case_id'));
            spec.auxiliaryVariableRoles=NMDataIOAPITools.getAny(spec,{'auxiliaryVariableRoles'},struct());
            if ~isstruct(spec.auxiliaryVariableRoles), error('NMDataIOAPITools:badROIAuxiliaryRoles','ROI auxiliaryVariableRoles must be a struct.'); end
            spec.auxiliaryTableFiles=NMDataIOAPITools.getAny(spec,{'auxiliaryTableFiles'},{});
            spec.covariateNames=NMDataIOAPITools.getAny(spec,{'covariateNames','covnames'},{});
            spec.covmanage_edit=NMDataIOAPITools.getNumber(spec,{'covmanage_edit','covariateHandling'},1);
            spec.labelNames=NMDataIOAPITools.getAny(spec,{'labelNames','regressionLabelNames','desc_labels'},{});
            spec.globalUserSourceType=NMDataIOAPITools.getChar(spec,{'globalUserSourceType'},'workspace');
            spec.globalAlignmentMode=NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOAPITools.getChar(spec,{'globalAlignmentMode'},'case_id'));
            spec.globalVariableRoles=NMDataIOAPITools.getAny(spec,{'globalVariableRoles'},struct());
            if ~isstruct(spec.globalVariableRoles), error('NMDataIOAPITools:badROIGlobalRoles','ROI globalVariableRoles must be a struct.'); end
            spec.globalTableFiles=NMDataIOAPITools.getAny(spec,{'globalTableFiles'},{});
            spec.caseAlignment=NMDataIOAPITools.getAny(spec,{'caseAlignment'},struct());
            if ~isstruct(spec.caseAlignment), error('NMDataIOAPITools:badROICaseAlignment','ROI caseAlignment must be a struct.'); end
            if ~isfield(spec.caseAlignment,'missingCasePolicy'), spec.caseAlignment.missingCasePolicy='fill_nan'; end
            if ~isfield(spec.caseAlignment,'allowMissingCasesAsNaN'), spec.caseAlignment.allowMissingCasesAsNaN=true; end
            if ~isfield(spec.caseAlignment,'idMappingMode'), spec.caseAlignment.idMappingMode='direct'; end
            if ~isfield(spec.caseAlignment,'mappingApproved'), spec.caseAlignment.mappingApproved=false; end
            if strcmp(spec.scope,'oocv')
                explicit=NMDataIOAPITools.hasAnyField(rawSpec,{'labelsKnown'});
                labelMode=lower(strrep(strrep(NMDataIOAPITools.getChar(rawSpec,{'labelMode'},'metadata'),'-','_'),' ','_'));
                implicitSupplied=any(strcmp(labelMode,{'legacy_groups','implicit','implicit_groups','auto','auto_groups'})) && ...
                    isfield(rawSpec,'classFileLists') && ~isempty(rawSpec.classFileLists);
                labelRefs={};
                if isfield(rawSpec,'auxiliaryVariableRoles') && isstruct(rawSpec.auxiliaryVariableRoles) && isfield(rawSpec.auxiliaryVariableRoles,'labels')
                    labelRefs=NMDataIOStateTools.roleRefCell(rawSpec.auxiliaryVariableRoles.labels);
                end
                supplied=~isempty(labelRefs) || implicitSupplied;
                if explicit
                    spec.labelsKnown=NMDataIOAPITools.getLogical(rawSpec,{'labelsKnown'},false);
                    if ~spec.labelsKnown && supplied
                        error('NMDataIOAPITools:inconsistentOOCVLabels','OOCV ROI labels were supplied but labelsKnown=false.');
                    end
                else
                    spec.labelsKnown=supplied;
                end
                spec.containerField=NMDataIOAPITools.getChar(spec,{'containerField'},'OOCV');
                spec.containerIndex=max(1,round(double(NMDataIOAPITools.getNumber(spec,{'containerIndex'},1))));
                spec.finalizeTrainingImport=false;
            else
                spec.labelsKnown=true;
                spec.containerField='';
                spec.containerIndex=[];
                spec.finalizeTrainingImport=NMDataIOAPITools.getLogical(spec,{'finalizeTrainingImport'},false);
            end
        end

        function state = stateFromROISpec(NM,spec,roiOut,scope)
            if nargin < 4 || isempty(scope), scope='training'; end
            state=NMDataIOStateTools.defaultMatrixState(NM,spec.varind);
            state.datasource='matrix';
            state.sourceType='roi';
            state.groupmode=1;
            state.modeflag=spec.modeflag;
            effectiveLabelsKnown=logical(spec.labelsKnown);
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown, effectiveLabelsKnown=NMDataIOAPITools.existingOOCVLabelsKnownInNM(NM,spec); end
            state.labels_known=effectiveLabelsKnown;
            state.oocvflag=strcmp(scope,'oocv');
            state.desc_data=spec.description;
            if isfield(roiOut,'desc_groups') && ~isempty(roiOut.desc_groups)
                state.desc_groups=roiOut.desc_groups;
            else
                state.desc_groups=spec.groupnames;
            end
            state.roi=NMDataIOAPITools.stripHeavyROISpec(spec);
            state.roi.sourceFamily='roi';
            state.roi.sourceType='roi';
            state.matrix.sourceType='roi';
            state.matrix.Y=roiOut.Y;
            if isfield(roiOut,'Yw') && ~isempty(roiOut.Yw), state.matrix.Yw=roiOut.Yw; end
            state.matrix.ID=roiOut.caseIDs(:);
            state.matrix.s_ID=state.matrix.ID;
            state.matrix.featnames=roiOut.featnames(:)';
            state.matrix.s_featnames=state.matrix.featnames;
            state.matrix.M_edit='<resolved-roi-payload>';
            state.matrix.matrix_edit='<resolved-roi-payload>';
            state.matrix.case_edit='<resolved-roi-case-ids>';
            state.matrix.col_edit='<canonical-roi-names>';
            state.matrix.label_edit='?';
            state.matrix.covar_edit={};
            state.matrix.covnames_edit='?';
            state.matrix.auxiliarySourceType=spec.auxiliarySourceType;
            state.matrix.auxiliaryAlignmentMode=spec.auxiliaryAlignmentMode;
            auxiliaryRoles=spec.auxiliaryVariableRoles;
            for roleName={'globals','features','featureNames'}
                if isfield(auxiliaryRoles,roleName{1}), auxiliaryRoles.(roleName{1})={}; end
            end
            state.matrix.auxiliaryVariableRoles=auxiliaryRoles;
            state.matrix.auxiliaryTableFiles=spec.auxiliaryTableFiles;
            state.matrix.covariateNameList=spec.covariateNames;
            state.matrix.desc_labels=spec.labelNames;
            state.matrix.labelNames=spec.labelNames;
            state.matrix.regressionLabelNames=spec.labelNames;
            state.covmanage_edit=spec.covmanage_edit;
            if ~isempty(roiOut.label)
                state.matrix.label=roiOut.label; state.matrix.s_label=roiOut.label; state.matrix.L=roiOut.label;
                state.matrix.label_edit='<resolved-roi-labels>';
            end
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                for f={'label','s_label','L'}, if isfield(state.matrix,f{1}), state.matrix=rmfield(state.matrix,f{1}); end, end
                state.matrix.label_edit='?';
            end
            if isfield(roiOut,'globalVolumeCorrection') && isstruct(roiOut.globalVolumeCorrection)
                state.matrix.globalMode=NMDataIOAPITools.getChar(roiOut.globalVolumeCorrection,{'mode'},'none');
            end
            if ~isempty(roiOut.covars)
                state.matrix.covars=roiOut.covars; state.matrix.covnames=roiOut.covnames;
            end
            roiProvenance=roiOut.roiProvenance;
            if strcmp(scope,'oocv')
                trainROI=NMDataIOAPITools.trainingROIProvenance(NM,spec.varind);
                roiProvenance.trainingModality=spec.varind;
                roiProvenance.trainingIdentityMatched=true;
                roiProvenance.trainingColumnKeys=trainROI.columnKeys;
            end
            state.matrix.roiProvenance=roiProvenance;
            if isfield(roiOut,'globalVolumeCorrection') && isstruct(roiOut.globalVolumeCorrection)
                state.matrix.globalVolumeCorrection=roiOut.globalVolumeCorrection;
            end
            if isfield(roiOut,'weightingProvenance') && isstruct(roiOut.weightingProvenance)
                state.matrix.roiWeightingProvenance=roiOut.weightingProvenance;
            end
            state.matrix.importReport=roiOut.importReport;
            state.matrix.input_settings=NMDataIOAPITools.roiInputSettings(roiOut,spec);
            state.matrix.input_settings.roiProvenance=roiProvenance;
            state.caseAlignment=spec.caseAlignment;
            state.matrix.caseAlignment=spec.caseAlignment;
            state.matrix.requireFeatureNames=false;
            if strcmp(scope,'oocv')
                state.importTarget=struct('scope','oocv','mode','add','varind',spec.varind, ...
                    'containerField',spec.containerField,'containerIndex',spec.containerIndex, ...
                    'labels_known',effectiveLabelsKnown,'description',spec.description);
            else
                targetMode=NMDataIOAPITools.getChar(spec,{'targetMode'},'add');
                if isfield(spec,'importTarget') && isstruct(spec.importTarget) && isfield(spec.importTarget,'mode') && ~isempty(spec.importTarget.mode)
                    targetMode=char(string(spec.importTarget.mode));
                end
                state.importTarget=struct('scope','training','mode',lower(strtrim(targetMode)),'varind',spec.varind);
            end
        end

        function settings = roiInputSettings(roiOut,spec)
            settings=struct('sourceFamily','roi','sourceType','roi','groupmode',1,'datasource','matrix', ...
                'roiSpec',NMDataIOAPITools.stripHeavyROISpec(spec),'roiProvenance',roiOut.roiProvenance, ...
                'importReport',roiOut.importReport);
            if isfield(roiOut,'weightingProvenance') && isstruct(roiOut.weightingProvenance) && ~isempty(fieldnames(roiOut.weightingProvenance)), settings.roiWeightingProvenance=roiOut.weightingProvenance; end
        end

        function S = stripHeavyROISpec(S)
            if ~isstruct(S), return; end
            for f={'caseIDs'}
                name=f{1};
                if ~isfield(S,name), continue; end
                v=S.(name);
                if ischar(v) || (isstring(v)&&isscalar(v))
                    if strlength(string(v))==0 || strcmp(strtrim(char(string(v))),'?'), S=rmfield(S,name); end
                else
                    S=rmfield(S,name);
                end
            end
        end

        function trainROI = trainingROIProvenance(NM,varind)
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor)<varind || ~isstruct(NM.datadescriptor{varind})
                error('NMDataIOAPITools:missingROITrainingModality','OOCV ROI import requires training modality %g.',double(varind));
            end
            dd=NM.datadescriptor{varind};
            nColumns=[];
            if isfield(NM,'Y') && numel(NM.Y)>=varind && ~isempty(NM.Y{varind}), nColumns=size(NM.Y{varind},2); end
            trainROI=NMDataIOROIProvenanceTools.normalizeDescriptor(dd,nColumns);
            if ~trainROI.ok
                error('NMDataIOAPITools:missingROIProvenance','Training modality %g does not contain a valid ROI definition: %s',double(varind),trainROI.message);
            end
        end

        function messages = validateTrainingROIScientificContract(NM,varind,spec)
            % validateTrainingROIScientificContract  Enforce the trained ROI settings that OOCV must not redefine.
            %
            % Purpose:
            %   Provide one owner-level API guard for scientific settings that are fixed by the
            %   training ROI modality while leaving OOCV subject values/source representation free.
            %
            % Authority and flow:
            %   The persisted training datadescriptor is authoritative. Canonical ROI identity and
            %   atlas/annotation parity are validated separately by NMDataIOROIDirectTools.alignToTraining.
            %   This guard covers global-volume correction semantics and forbids OOCV-specific
            %   weighting/ranking definitions, which belong to the trained model feature space.
            %
            % Materialization and performance:
            %   No files or workspace variables are read and no feature-scale arrays are created.
            %
            % Failure semantics:
            %   Scientific divergence is returned as an explicit blocking DataIO diagnostic.
            messages = NMDataIOMessageTools.emptyMessages();
            weightingFiles = NMDataIOAPITools.getAny(spec,{'weightingFiles','weightingMaps','Pw'},{});
            if ~isempty(weightingFiles)
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.weighting', ...
                    'OOCV ROI weighting/ranking files cannot be selected independently. The OOCV data must use the ROI weighting defined by the training modality.',1,'red*')];
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind}) || ~isfield(NM.datadescriptor{varind},'globalVolumeCorrection') || ...
                    ~isstruct(NM.datadescriptor{varind}.globalVolumeCorrection) || ~isscalar(NM.datadescriptor{varind}.globalVolumeCorrection)
                return;
            end
            correction = NM.datadescriptor{varind}.globalVolumeCorrection;
            if ~isfield(correction,'mode') || isempty(correction.mode), return; end
            expectedMode = lower(strrep(strrep(char(string(correction.mode)),'-','_'),' ','_'));
            actualMode = lower(strrep(strrep(NMDataIOAPITools.getChar(spec,{'globalMode','uiGlobalModeSelection'},'none'),'-','_'),' ','_'));
            if any(strcmp(expectedMode, {'','no','off'})), expectedMode = 'none'; end
            if any(strcmp(actualMode, {'','no','off'})), actualMode = 'none'; end
            if any(strcmp(expectedMode, {'proportional_scaling','scale'})), expectedMode = 'proportional'; end
            if any(strcmp(actualMode, {'proportional_scaling','scale'})), actualMode = 'proportional'; end
            if ~strcmp(actualMode, expectedMode)
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.globalCorrection.mode', ...
                    sprintf('OOCV ROI global-volume correction mode (%s) does not match the training modality (%s).',actualMode,expectedMode),1,'red*')];
                return;
            end
            if ~strcmp(expectedMode,'proportional'), return; end
            actualName = NMDataIOAPITools.getChar(spec,{'globalName'},'GlobalBrainVolume');
            if isfield(correction,'globalName') && ~isempty(correction.globalName) && ~strcmp(actualName,char(string(correction.globalName)))
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.globalCorrection.name', ...
                    sprintf('OOCV ROI global-volume name (%s) does not match the training modality (%s).',actualName,char(string(correction.globalName))),1,'red*')];
                return;
            end
            actualMultiplier = NMDataIOAPITools.getNumber(spec,{'globnorm','globalMultiplier'},1);
            if isfield(correction,'globalMultiplier') && isnumeric(correction.globalMultiplier) && isscalar(correction.globalMultiplier) && ...
                    (~isfinite(actualMultiplier) || double(actualMultiplier) ~= double(correction.globalMultiplier))
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.globalCorrection.multiplier', ...
                    sprintf('OOCV ROI global-volume multiplier (%g) does not match the training modality (%g).',double(actualMultiplier),double(correction.globalMultiplier)),1,'red*')];
            end
        end

        function assertROIMessagesOK(messages,source)
            if nargin<2, source='NMDataIOAPITools'; end
            if NMDataIOMessageTools.hasFatal(messages)
                msg='ROI import failed.';
                if isstruct(messages) && isfield(messages,'text')
                    txt={messages.text}; txt=txt(~cellfun(@isempty,txt)); if ~isempty(txt), msg=strjoin(txt,' | '); end
                end
                error('NMDataIOAPITools:roiImportFailed','%s %s',source,msg);
            end
        end

        function spec = normalizeConnectivitySpec(spec, scope)
            if nargin < 2 || isempty(scope), scope = 'training'; end
            if ~isstruct(spec), error('NMDataIOAPITools:badSpec', 'Connectivity DataIO import spec must be a scalar struct.'); end
            if numel(spec) ~= 1, error('NMDataIOAPITools:badSpecArray', 'Connectivity DataIO import spec must be scalar.'); end
            rawSpec = spec;
            spec.scope = lower(strtrim(char(string(scope))));
            if ~ismember(spec.scope, {'training','oocv'})
                error('NMDataIOAPITools:badConnectivityScope', 'Unsupported connectivity DataIO import scope: %s.', spec.scope);
            end
            spec.varind = NMDataIOAPITools.getNumber(spec, {'varind','modalityIndex','modality'}, 1);
            spec.varind = max(1, round(double(spec.varind)));
            spec.modeflag = NMDataIOAPITools.getChar(spec, {'modeflag','mode'}, 'classification');
            spec.description = NMDataIOAPITools.getChar(spec, {'description','desc','desc_data'}, sprintf('%s connectivity modality %d', spec.scope, spec.varind));
            spec.desc_data = spec.description;
            spec.groupnames = NMDataIOAPITools.getAny(spec, {'groupnames','groupNames','desc_groups'}, {'Class_1','Class_2'});
            spec.groupNames = NMDataIOAPITools.getAny(spec, {'groupNames','imageGroupNames','classGroupNames','desc_groups'}, spec.groupnames);
            spec.auxiliarySourceType = NMDataIOAPITools.getChar(spec, {'auxiliarySourceType'}, 'workspace');
            spec.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOAPITools.getChar(spec, {'auxiliaryAlignmentMode'}, 'case_id'));
            spec.auxiliaryVariableRoles = NMDataIOAPITools.getAny(spec, {'auxiliaryVariableRoles'}, struct());
            if ~isstruct(spec.auxiliaryVariableRoles), error('NMDataIOAPITools:badConnectivityAuxiliaryRoles', 'Connectivity auxiliaryVariableRoles must be a struct.'); end
            spec.auxiliaryTableFiles = NMDataIOAPITools.getAny(spec, {'auxiliaryTableFiles'}, {});
            spec.covariateNames = NMDataIOAPITools.getAny(spec, {'covariateNames','covnames'}, {});
            spec.covmanage_edit = NMDataIOAPITools.getNumber(spec, {'covmanage_edit','covariateHandling'}, 1);
            spec.labelNames = NMDataIOAPITools.getAny(spec, {'labelNames','regressionLabelNames','desc_labels'}, {});
            spec.caseAlignment = NMDataIOAPITools.getAny(spec, {'caseAlignment','caseAlignmentOptions'}, struct());
            if ~isstruct(spec.caseAlignment), error('NMDataIOAPITools:badCaseAlignment', 'caseAlignment must be a struct when supplied.'); end
            if ~isfield(spec.caseAlignment,'missingCasePolicy') || isempty(spec.caseAlignment.missingCasePolicy)
                spec.caseAlignment.missingCasePolicy = 'fill_nan';
            end
            if ~isfield(spec.caseAlignment,'allowMissingCasesAsNaN') || isempty(spec.caseAlignment.allowMissingCasesAsNaN)
                spec.caseAlignment.allowMissingCasesAsNaN = true;
            end
            if ~isfield(spec.caseAlignment,'idMappingMode') || isempty(spec.caseAlignment.idMappingMode)
                spec.caseAlignment.idMappingMode = 'direct';
            end
            if ~isfield(spec.caseAlignment,'mappingApproved') || isempty(spec.caseAlignment.mappingApproved)
                spec.caseAlignment.mappingApproved = false;
            end
            if strcmp(spec.scope,'oocv')
                labelsKnownExplicit = NMDataIOAPITools.hasAnyField(rawSpec, {'labelsKnown','labels_known'});
                labelRefs = {};
                if isfield(rawSpec,'auxiliaryVariableRoles') && isstruct(rawSpec.auxiliaryVariableRoles) && isfield(rawSpec.auxiliaryVariableRoles,'labels')
                    labelRefs = NMDataIOStateTools.roleRefCell(rawSpec.auxiliaryVariableRoles.labels);
                end
                labelMode = lower(strrep(strrep(NMDataIOAPITools.getChar(rawSpec, {'labelMode'}, 'metadata'),'-','_'),' ','_'));
                legacyGroupLabels = strcmp(labelMode,'legacy_groups') && isfield(rawSpec,'classFileLists') && ~isempty(rawSpec.classFileLists);
                labelsSupplied = ~isempty(labelRefs) || legacyGroupLabels;
                if labelsKnownExplicit
                    spec.labelsKnown = NMDataIOAPITools.getLogical(rawSpec, {'labelsKnown','labels_known'}, false);
                    if ~spec.labelsKnown && labelsSupplied
                        error('NMDataIOAPITools:inconsistentOOCVLabels', ...
                            'OOCV label roles were assigned but labelsKnown=false. Set labelsKnown=true or remove the OOCV label assignment.');
                    end
                else
                    spec.labelsKnown = labelsSupplied;
                end
                spec.containerField = NMDataIOAPITools.getChar(spec, {'containerField','field'}, 'OOCV');
                spec.containerIndex = NMDataIOAPITools.getNumber(spec, {'containerIndex','oocvind','index'}, 1);
                spec.containerIndex = max(1, round(double(spec.containerIndex)));
                spec.finalizeTrainingImport = false;
            else
                spec.labelsKnown = true;
                spec.containerField = '';
                spec.containerIndex = [];
                spec.finalizeTrainingImport = NMDataIOAPITools.getLogical(spec, {'finalizeTrainingImport','finalizeImport','FinalizeTrainingImport'}, false);
            end
        end

        function state = stateFromConnectivitySpec(NM, spec, connOut, scope)
            if nargin < 4 || isempty(scope), scope = 'training'; end
            scope = lower(strtrim(char(string(scope))));
            state = NMDataIOStateTools.defaultMatrixState(NM, spec.varind);
            state.datasource = 'matrix';
            state.sourceType = 'connectivity';
            state.groupmode = 1;
            state.modeflag = spec.modeflag;
            effectiveLabelsKnown = logical(spec.labelsKnown);
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                effectiveLabelsKnown = NMDataIOAPITools.existingOOCVLabelsKnownInNM(NM, spec);
            end
            state.labels_known = effectiveLabelsKnown;
            state.oocvflag = strcmp(scope,'oocv');
            state.desc_data = spec.description;
            if isfield(connOut,'desc_groups') && ~isempty(connOut.desc_groups)
                state.desc_groups = connOut.desc_groups;
            else
                state.desc_groups = spec.groupnames;
            end
            state.connectivity = NMDataIOImportTools.stripHeavyConnectivitySpec(spec);
            state.connectivity.sourceFamily = 'connectivity';
            state.connectivity.sourceType = 'connectivity';
            state.matrix.sourceType = 'connectivity';
            state.matrix.Y = connOut.Y;
            state.matrix.ID = connOut.caseIDs(:);
            state.matrix.s_ID = state.matrix.ID;
            state.matrix.featnames = connOut.featnames(:)';
            state.matrix.s_featnames = state.matrix.featnames;
            state.matrix.M_edit = '<resolved-connectivity-payload>';
            state.matrix.matrix_edit = '<resolved-connectivity-payload>';
            state.matrix.case_edit = '<resolved-connectivity-case-ids>';
            state.matrix.col_edit = '<resolved-connectivity-edge-names>';
            state.matrix.label_edit = '?';
            state.matrix.covar_edit = {};
            state.matrix.covnames_edit = '?';
            state.matrix.auxiliarySourceType = spec.auxiliarySourceType;
            state.matrix.auxiliaryAlignmentMode = spec.auxiliaryAlignmentMode;
            state.matrix.auxiliaryVariableRoles = spec.auxiliaryVariableRoles;
            state.matrix.auxiliaryTableFiles = spec.auxiliaryTableFiles;
            state.matrix.covariateNameList = spec.covariateNames;
            if ~isempty(spec.labelNames), state.matrix.labelDefinition = struct('kind','manual','manualNames',{NMDataIOStateTools.asCaseCell(spec.labelNames)},'nameSourceRef',struct(),'sourceCodes',{{}},'count',numel(spec.labelNames)); end
            state.covmanage_edit = spec.covmanage_edit;
            if isfield(connOut,'label') && ~isempty(connOut.label)
                state.matrix.label = connOut.label;
                state.matrix.s_label = connOut.label;
                state.matrix.L = connOut.label;
                state.matrix.label_edit = '<resolved-connectivity-labels>';
            end
            if strcmp(scope,'oocv') && ~effectiveLabelsKnown
                state.matrix.label_edit = '?';
                if isfield(state.matrix,'label'), state.matrix = rmfield(state.matrix,'label'); end
                if isfield(state.matrix,'s_label'), state.matrix = rmfield(state.matrix,'s_label'); end
                if isfield(state.matrix,'L'), state.matrix = rmfield(state.matrix,'L'); end
            end
            state.matrix.connectivityProvenance = connOut.provenance;
            state.matrix.importReport = NMDataIOAPITools.connectivityImportReport(connOut);
            state.matrix.input_settings = NMDataIOAPITools.connectivityInputSettings(connOut, spec);
            if isfield(connOut,'Yw') && ~isempty(connOut.Yw), state.matrix.Yw = connOut.Yw; end
            if isfield(connOut,'weightingNames') && ~isempty(connOut.weightingNames), state.matrix.weightingNames = connOut.weightingNames; end
            state.caseAlignment = spec.caseAlignment;
            state.matrix.caseAlignment = spec.caseAlignment;
            state.matrix.requireFeatureNames = false;
            if strcmp(scope,'oocv')
                state.importTarget = struct('scope','oocv', 'mode','add', 'varind',spec.varind, ...
                    'containerField',spec.containerField, 'containerIndex',spec.containerIndex, ...
                    'labels_known',effectiveLabelsKnown, 'description',spec.description);
            else
                targetMode = NMDataIOAPITools.getChar(spec, {'targetMode','mode'}, 'add');
                if isfield(spec,'importTarget') && isstruct(spec.importTarget) && isfield(spec.importTarget,'mode') && ~isempty(spec.importTarget.mode)
                    targetMode = char(string(spec.importTarget.mode));
                end
                targetMode = lower(strtrim(char(string(targetMode))));
                if isempty(targetMode), targetMode = 'add'; end
                state.importTarget = struct('scope','training', 'mode',targetMode, 'varind',spec.varind);
            end
        end

        function report = connectivityImportReport(connOut)
            report = struct();
            if isfield(connOut,'importReport') && isstruct(connOut.importReport)
                report = connOut.importReport;
            end
            report.connectivity = connOut.provenance;
        end

        function inputSettings = connectivityInputSettings(connOut, spec)
            inputSettings = struct();
            inputSettings.sourceFamily = 'connectivity';
            inputSettings.sourceType = 'connectivity';
            inputSettings.groupmode = 1;
            inputSettings.datasource = 'matrix';
            inputSettings.connectivitySpec = NMDataIOImportTools.stripHeavyConnectivitySpec(spec);
            inputSettings.connectivityProvenance = connOut.provenance;
            inputSettings.importReport = NMDataIOAPITools.connectivityImportReport(connOut);
        end

        function trainProv = trainingConnectivityProvenance(NM, varind)
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind})
                error('NMDataIOAPITools:missingConnectivityTrainingModality', ...
                    'OOCV connectivity import requires an existing training connectivity modality %g.', double(varind));
            end
            dd = NM.datadescriptor{varind};
            if ~isfield(dd,'source') || ~strcmpi(char(string(dd.source)), 'connectivity')
                error('NMDataIOAPITools:targetNotConnectivity', ...
                    'Training modality %g is not a connectivity modality and cannot define the OOCV connectivity feature space.', double(varind));
            end
            if ~isfield(dd,'connectivity') || ~isstruct(dd.connectivity)
                error('NMDataIOAPITools:missingConnectivityProvenance', ...
                    'Training connectivity modality %g does not contain its saved node/edge definition.', double(varind), double(varind));
            end
            trainProv = dd.connectivity;
            if ~isfield(trainProv,'edgeIndex') || isempty(trainProv.edgeIndex) || ...
                    ~isfield(trainProv,'nodeIDs') || isempty(trainProv.nodeIDs)
                error('NMDataIOAPITools:incompleteConnectivityProvenance', ...
                    'Training connectivity modality %g has an incomplete node/edge definition.', double(varind));
            end
        end

        function assertMessagesOK(messages, source)
            if nargin < 2 || isempty(source), source = 'NMDataIOAPITools'; end
            if exist('NMDataIOMessageTools','class') == 8 && NMDataIOMessageTools.hasFatal(messages)
                msg = 'Connectivity import failed.';
                if isstruct(messages) && isfield(messages, 'text')
                    txt = {messages.text};
                    txt = txt(~cellfun(@isempty, txt));
                    if ~isempty(txt), msg = strjoin(txt, ' | '); end
                end
                error('NMDataIOAPITools:connectivityImportFailed', '%s %s', source, msg);
            end
        end

        function assertOutOK(out, source)
            if nargin < 2 || isempty(source), source = 'NMDataIOAPITools'; end
            if ~isstruct(out) || ~isfield(out,'ok') || ~out.ok
                msg = 'DataIO API import failed.';
                if isstruct(out) && isfield(out,'message') && ~isempty(out.message), msg = out.message; end
                error('NMDataIOAPITools:importFailed', '%s %s', source, msg);
            end
        end

        function s = nameValuesToStruct(varargin)
            if nargin == 1 && isstruct(varargin{1}), s = varargin{1}; return; end
            if mod(nargin,2) ~= 0, error('NMDataIOAPITools:badNameValues', 'Arguments must be name/value pairs.'); end
            s = struct();
            for i = 1:2:nargin
                key = char(string(varargin{i}));
                s.(key) = varargin{i+1};
            end
        end

        function tf = hasAnyField(s, names)
            tf = false;
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                if isfield(s, names{i})
                    tf = true;
                    return;
                end
            end
        end

        function tf = hasLabelPayload(s, names)
            tf = false;
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                f = names{i};
                if ~isfield(s,f) || isempty(s.(f))
                    continue;
                end
                v = s.(f);
                if ischar(v) || isstring(v)
                    txt = strtrim(char(string(v)));
                    if isempty(txt) || strcmp(txt,'?') || strcmp(txt,'-')
                        continue;
                    end
                    tf = true;
                    return;
                end
                if iscell(v)
                    for j = 1:numel(v)
                        if isempty(v{j}), continue; end
                        txt = strtrim(char(string(v{j})));
                        if ~isempty(txt) && ~strcmp(txt,'?') && ~strcmp(txt,'-')
                            tf = true;
                            return;
                        end
                    end
                    continue;
                end
                tf = true;
                return;
            end
        end

        function spec = applyCurrentLabelAuthority(NM, spec)
            % APPLYCURRENTLABELAUTHORITY  Remove label-source instructions when the target axis already owns labels.
            if ~isstruct(spec) || ~isscalar(spec), return; end
            target = NMDataIOImportTargetTools.normalize(NM,spec,NMDataIOAPITools.getNumber(spec,{'varind'},1));
            if NMDataIOImportTargetTools.isOOCV(target) && NMDataIOAPITools.existingOOCVLabelsKnownInNM(NM,spec)
                spec.labelsKnown = true;
                target.labels_known = true;
            end
            if NMDataIOImportTargetTools.currentImportDefinesLabels(NM,target)
                if NMDataIOImportTargetTools.isOOCV(target) && logical(NMDataIOAPITools.getAny(spec,{'labelsKnown','labels_known'},false)) && ...
                        strcmpi(NMDataIOAPITools.getChar(spec,{'modeflag'},'classification'),'classification')
                    spec.trainingClassificationLabelMap = NMDataIOImportTools.trainingClassificationLabelMap(NM);
                end
                return;
            end
            spec.labelMode = 'metadata';
            if isfield(spec,'classFileLists'), spec.classFileLists = {}; end
            if isfield(spec,'groupSizes'), spec.groupSizes = []; end
            if isfield(spec,'label'), spec.label = '?'; end
            if isfield(spec,'auxiliaryVariableRoles') && isstruct(spec.auxiliaryVariableRoles)
                spec.auxiliaryVariableRoles.labels = {};
            end
            if isfield(spec,'variableRoles') && isstruct(spec.variableRoles)
                spec.variableRoles.labels = {};
            end
            mode = lower(strtrim(NMDataIOAPITools.getChar(spec,{'modeflag'},'classification')));
            if strcmp(mode,'classification') && isstruct(NM) && isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                spec.groupnames = NM.groupnames;
                spec.groupNames = NM.groupnames;
            elseif strcmp(mode,'regression') && isstruct(NM) && isfield(NM,'labelnames') && ~isempty(NM.labelnames)
                spec.labelNames = NM.labelnames;
            end
        end

        function tf = existingOOCVLabelsKnownInNM(NM, spec)
            tf = false;
            if ~isstruct(NM) || ~isstruct(spec) || ~isfield(spec,'containerField') || isempty(spec.containerField) || ...
                    ~isfield(spec,'containerIndex') || isempty(spec.containerIndex)
                return;
            end
            field = char(string(spec.containerField));
            idx = max(1, round(double(spec.containerIndex)));
            if isfield(NM, field) && iscell(NM.(field)) && numel(NM.(field)) >= idx && ...
                    isstruct(NM.(field){idx}) && isfield(NM.(field){idx}, 'labels_known') && ...
                    logical(NM.(field){idx}.labels_known)
                tf = true;
            end
        end

        function v = getAny(s, names, defaultValue)
            v = defaultValue;
            for i = 1:numel(names)
                f = names{i};
                if isfield(s,f) && ~isempty(s.(f)), v = s.(f); return; end
            end
        end

        function v = getChar(s, names, defaultValue)
            v = NMDataIOAPITools.getAny(s, names, defaultValue);
            if isstring(v), v = char(v); end
            if ~(ischar(v) || iscellstr(v) || iscell(v))
                error('NMDataIOAPITools:badStringField', 'Expected a workspace variable name or character value.');
            end
            if iscellstr(v) || iscell(v)
                % Keep cell arrays only for legacy covariate-role fields.
                return;
            end
            v = char(v);
        end


        function v = getHeaderFlagChar(s, names, defaultValue)
            v = NMDataIOAPITools.getAny(s, names, defaultValue);
            if isempty(v)
                v = defaultValue;
                return;
            end
            if islogical(v)
                v = NMDataIOAPITools.logicalHeaderFlagToChar(v(1));
                return;
            end
            if isnumeric(v)
                if isempty(v) || ~isfinite(double(v(1)))
                    v = defaultValue;
                else
                    v = NMDataIOAPITools.logicalHeaderFlagToChar(logical(v(1)));
                end
                return;
            end
            if isstring(v)
                v = char(v(1));
            end
            if ~ischar(v)
                error('NMDataIOAPITools:badAtlasHeaderFlag', ...
                    'atlasLabelHasHeader must be logical/numeric or one of yes/no/auto.');
            end
            t = lower(strtrim(v));
            if any(strcmp(t, {'true','1','yes','y','on'}))
                v = 'yes';
            elseif any(strcmp(t, {'false','0','no','n','off'}))
                v = 'no';
            elseif isempty(t) || strcmp(t, 'auto')
                v = 'auto';
            else
                error('NMDataIOAPITools:badAtlasHeaderFlag', ...
                    'atlasLabelHasHeader must be logical/numeric or one of yes/no/auto.');
            end
        end

        function v = logicalHeaderFlagToChar(tf)
            if tf
                v = 'yes';
            else
                v = 'no';
            end
        end

        function v = getNumber(s, names, defaultValue)
            v = NMDataIOAPITools.getAny(s, names, defaultValue);
            if ischar(v) || isstring(v), v = str2double(char(string(v))); end
            if isempty(v) || ~isnumeric(v) || ~isfinite(double(v(1))), v = defaultValue; end
            v = double(v(1));
        end

        function v = getLogical(s, names, defaultValue)
            v = NMDataIOAPITools.getAny(s, names, defaultValue);
            if ischar(v) || isstring(v)
                t = lower(strtrim(char(string(v))));
                v = any(strcmp(t, {'true','1','yes','y','known','on'}));
            else
                v = logical(v(1));
            end
        end
    end
end
