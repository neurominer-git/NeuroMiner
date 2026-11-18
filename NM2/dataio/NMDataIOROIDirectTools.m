classdef NMDataIOROIDirectTools
% NMDataIOROIDirectTools
% -------------------------------------------------------------------------
% Direct ROI DataIO producer.  It resolves explicit ROI matrices or CAT12
% catROI XML/MAT files, validates them against a mandatory volumetric atlas or
% surface annotation, and emits the canonical NMDataIOROIProvenance contract.
%
% This class does not infer ROI semantics from feature names.  Tabular ROI
% input requires an explicit ROI sidecar; when table feature names are
% available, a dimension mismatch may be resolved only by exact ROI-name
% matching. CAT12 input requires explicit atlas-family and measurement
% selection.
% -------------------------------------------------------------------------

    methods (Static)
        function [out, messages] = resolvePayload(spec, progressTask)
            % resolvePayload  Materialize one canonical direct-ROI payload from explicit source/provenance state.
            %
            % Purpose and flow:
            %   Resolves CAT12 or tabular ROI input, canonical ROI/spatial provenance, subject-aligned
            %   labels, optional volumetric global correction, and ROI-level weighting. Explicit covariates
            %   remain generic auxiliary configuration until the ROI case axis is established.
            %   progressTask is an optional NMProgressTools task used only to report materialization progress.
            % Scientific/state contract:
            %   ROI column identity is explicit and canonical. For volumetric_atlas provenance, proportional
            %   global-volume scaling is applied to Y after subject metadata alignment and before Y reaches
            %   Feature-QC or model transfer. Surface_annotation ROI values are never volume-scaled.
            % Materialization and performance:
            %   Explicit import/QC materialization. Depending on source it may parse CAT12 files and validate
            %   atlas/annotation provenance; it is not permitted on interactive Results Viewer navigation,
            %   subject switching or teardown paths.
            % Failure semantics:
            %   Source, provenance, case-alignment and global-correction failures are explicit structured
            %   messages. No anatomical-name heuristics, global-value fallback or display-side repair is used.
            if nargin < 1 || isempty(spec), spec = struct(); end
            if nargin < 2 || ~isstruct(progressTask), progressTask = NMProgressTools.emptyTaskForLocalUse(); end
            messages = NMDataIOMessageTools.emptyMessages();
            out = NMDataIOROIDirectTools.emptyPayload();
            baseStart = progressTask.phaseStart;
            baseEnd = progressTask.phaseEnd;
            baseSpan = max(0, baseEnd - baseStart);
            pct = @(fraction) baseStart + baseSpan .* fraction;
            try
                progressTask = NMProgressTools.phase(progressTask, 'roi_resolve_normalize', pct(0), pct(0.04), ...
                    'Normalizing ROI source specification.');
                spec = NMDataIOROIDirectTools.normalizeSpec(spec);
                sourceRange = [pct(0.04) pct(0.72)];
                switch spec.sourceFormat
                    case 'cat12_files'
                        [out, sourceMessages] = NMDataIOROIDirectTools.resolveCAT12Files(spec,progressTask,sourceRange);
                    case {'workspace_matrix','workspace_table','table_file'}
                        [out, sourceMessages] = NMDataIOROIDirectTools.resolveTabular(spec,progressTask,sourceRange);
                    otherwise
                        sourceMessages = NMDataIOMessageTools.make('danger',true,'roi.sourceFormat', ...
                            sprintf('Unsupported direct ROI source format: %s.',spec.sourceFormat),1,'red*');
                end
                messages = [messages; sourceMessages];
                if NMDataIOMessageTools.hasFatal(messages), return; end
                progressTask = NMProgressTools.phase(progressTask, 'roi_resolve_metadata', pct(0.72), pct(0.86), ...
                    'Preparing ROI subject metadata.');
                if strcmp(spec.labelMode,'legacy_groups') && isempty(out.desc_groups)
                    out.desc_groups=spec.groupNames;
                end
                progressTask = NMProgressTools.phase(progressTask, 'roi_resolve_global_correction', pct(0.86), pct(0.91), ...
                    'Applying configured ROI global-volume correction.');
                [out,globalMessages] = NMDataIOROIDirectTools.applyGlobalVolumeCorrection(out,spec);
                messages=[messages;globalMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
                progressTask = NMProgressTools.phase(progressTask, 'roi_resolve_weighting', pct(0.91), pct(0.98), ...
                    'Resolving ROI weighting/ranking files.');
                [out.Yw,out.weightingProvenance,weightMessages] = NMDataIOROIDirectTools.resolveWeightingFiles(spec,out.roiProvenance,progressTask,[pct(0.91) pct(0.98)]);
                messages=[messages;weightMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
                progressTask = NMProgressTools.phase(progressTask, 'roi_resolve_finalize', pct(0.98), pct(1.00), ...
                    'Finalizing the ROI import summary.');
                resolvedGroupNames=out.desc_groups;
                if isempty(resolvedGroupNames), resolvedGroupNames=spec.groupNames; end
                resolvedGroupSizes=spec.groupSizes;
                if strcmp(spec.modeflag,'classification') && ~isempty(out.label) && isnumeric(out.label) && isvector(out.label)
                    [~,~,groupIndex]=unique(double(out.label(:)),'stable');
                    resolvedGroupSizes=accumarray(groupIndex,1)';
                end
                out.ok = true;
                out.importReport = struct('sourceFamily','roi','sourceFormat',spec.sourceFormat,'labelMode',spec.labelMode, ...
                    'nSubjects',double(size(out.Y,1)),'nROIs',double(size(out.Y,2)), ...
                    'groupNames',{resolvedGroupNames},'groupSizes',resolvedGroupSizes, ...
                    'producerKind',out.roiProvenance.producer.kind,'spatialKind',out.roiProvenance.spatialReferences(1).kind, ...
                    'auxiliaryAlignmentMode',spec.auxiliaryAlignmentMode,'globalMode',out.globalVolumeCorrection.mode, ...
                    'globalCorrectionApplied',logical(out.globalVolumeCorrection.appliedBeforeQC), ...
                    'nWeightingMaps',double(size(out.Yw,1)));
                if isfield(out.sourceMetadata,'sidecarMatchReport')
                    out.importReport.sidecarMatchReport=out.sourceMetadata.sidecarMatchReport;
                end
                messages = [messages; NMDataIOMessageTools.make('ok',false,'roi.resolve', ...
                    sprintf('Read ROI data successfully: %g case(s), %g ROI feature(s), %s spatial reference.', ...
                    size(out.Y,1),size(out.Y,2),out.roiProvenance.spatialReferences(1).kind),0,'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME,'NMDataIOROIDirectTools.resolvePayload')];
            end
        end

        function out = inspectCAT12(fileName)
            % inspectCAT12  List explicit CAT12 atlas-family and measurement choices.
            fileName = char(string(fileName));
            out = struct('ok',false,'file',fileName,'atlases',struct([]),'message','');
            if isempty(fileName) || exist(fileName,'file') ~= 2
                out.message = sprintf('CAT12 ROI file does not exist: %s',fileName);
                return;
            end
            try
                S = NMDataIOROIDirectTools.loadCAT12Struct(fileName);
                names = fieldnames(S);
                row = struct('name','','version','','nROIs',0,'measurements',{{}});
                atlases = repmat(row,numel(names),1);
                for ii=1:numel(names)
                    a = S.(names{ii});
                    NMDataIOROIDirectTools.assertCAT12Atlas(a,names{ii},fileName);
                    measures = fieldnames(a.data);
                    atlases(ii) = struct('name',names{ii},'version',char(string(a.version)), ...
                        'nROIs',double(numel(a.ids)),'measurements',{measures(:)'});
                end
                out.atlases = atlases;
                out.ok = true;
                out.message = sprintf('CAT12 ROI file contains %g atlas family/families.',numel(atlases));
            catch ME
                out.message = sprintf('%s (%s)',ME.message,ME.identifier);
            end
        end

        function [out, messages] = alignToTraining(out, trainingROI)
            % alignToTraining  Deterministically reorder OOCV ROI columns to the trained ROI identity.
            messages = NMDataIOMessageTools.emptyMessages();
            trainingROI = NMDataIOROIProvenanceTools.validate(trainingROI,[]);
            incoming = NMDataIOROIProvenanceTools.validate(out.roiProvenance,size(out.Y,2));
            if ~trainingROI.ok || ~incoming.ok
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.provenance', ...
                    'OOCV ROI matching requires valid ROI definitions for both the training and OOCV modalities.',1,'red*')];
                return;
            end
            trainKeys = trainingROI.columnKeys(:)';
            inKeys = incoming.columnKeys(:)';
            if numel(trainKeys) ~= numel(inKeys) || ~isempty(setxor(trainKeys,inKeys))
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.identity', ...
                    'OOCV ROI identities do not match the trained ROI feature space.',1,'red*')];
                return;
            end
            [matched,loc] = ismember(trainKeys,inKeys);
            if ~all(matched) || numel(unique(loc)) ~= numel(loc)
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.mapping', ...
                    'OOCV ROI identity mapping is incomplete or duplicated.',1,'red*')];
                return;
            end
            out.Y = out.Y(:,loc);
            if isfield(out,'Yw') && ~isempty(out.Yw)
                if size(out.Yw,2)~=numel(loc)
                    messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.oocv.weighting','OOCV ROI weighting maps do not match the number of incoming ROI features.',1,'red*')]; return;
                end
                out.Yw=out.Yw(:,loc);
            end
            incoming.columnIndex = 1:numel(loc);
            incoming.columnToROI = incoming.columnToROI(loc);
            incoming.columnKeys = incoming.columnKeys(loc);
            incoming.roiIDs = incoming.roiIDs(loc);
            incoming.roiNames = incoming.roiNames(loc);
            incoming.hemisphere = incoming.hemisphere(loc);
            incoming.mniCoordinates = incoming.mniCoordinates(loc,:);
            incoming = NMDataIOROIProvenanceTools.validate(incoming,numel(loc));
            if ~incoming.ok
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.reorder',incoming.message,1,'red*')];
                return;
            end
            if ~isequal(incoming.columnKeys(:)',trainingROI.columnKeys(:)') || ...
                    ~isequal(incoming.roiNames(:)',trainingROI.roiNames(:)')
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.names', ...
                    'OOCV ROI IDs match the training data, but the ROI names differ.',1,'red*')];
                return;
            end
            trainSpatial = NMDataIOROIDirectTools.spatialIdentityKeys(trainingROI.spatialReferences);
            incomingSpatial = NMDataIOROIDirectTools.spatialIdentityKeys(incoming.spatialReferences);
            if ~isequal(sort(trainSpatial),sort(incomingSpatial))
                messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.oocv.spatialReference', ...
                    'The OOCV ROI spatial reference does not match the atlas or annotation used for training.',1,'red*')];
                return;
            end
            out.roiProvenance = incoming;
            out.featnames = incoming.roiNames(:)';
            if isfield(out,'weightingProvenance') && isstruct(out.weightingProvenance) && ~isempty(fieldnames(out.weightingProvenance))
                out.weightingProvenance.roiIDs=incoming.roiIDs; out.weightingProvenance.roiNames=incoming.roiNames;
                if isfield(out.weightingProvenance,'hemisphere'), out.weightingProvenance.hemisphere=incoming.hemisphere; end
            end
            messages = [messages; NMDataIOMessageTools.make('ok',false,'roi.oocv.align', ...
                sprintf('Aligned %g OOCV ROI columns to the ROI order used for training.',numel(loc)),0,'green*')];
        end
    end

    methods (Static, Access = private)
        function keys = spatialIdentityKeys(refs)
            keys=cell(1,numel(refs));
            for ii=1:numel(refs)
                keys{ii}=sprintf('%s|%s',char(string(refs(ii).kind)),char(string(refs(ii).identity)));
            end
        end

        function spec = normalizeSpec(spec)
            if ~isstruct(spec) || ~isscalar(spec), error('NMDataIOROIDirectTools:BadSpec','ROI import spec must be one scalar struct.'); end
            spec.sourceFormat = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'sourceFormat'},'workspace_matrix')));
            spec.description = NMDataIOROIDirectTools.text(spec,{'description'},'ROI data');
            spec.modeflag = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'modeflag'},'classification')));
            labelMode = lower(strrep(strrep(NMDataIOROIDirectTools.text(spec,{'labelMode'},'metadata'),'-','_'),' ','_'));
            if any(strcmp(labelMode,{'legacy_groups','implicit','implicit_groups','auto','auto_groups'})), spec.labelMode='legacy_groups'; else, spec.labelMode='metadata'; end
            if ~strcmp(spec.sourceFormat,'cat12_files') || strcmp(spec.modeflag,'regression'), spec.labelMode='metadata'; end
            spec.files = NMDataIOROIDirectTools.cells(spec,{'files'});
            spec.vectorFiles = NMDataIOROIDirectTools.cells(spec,{'vectorFiles'});
            spec.classFileLists = NMDataIOROIDirectTools.value(spec,{'classFileLists','classLists'},{});
            spec.groupNames = NMDataIOROIDirectTools.cells(spec,{'groupNames','groupnames'});
            spec.groupSizes = double(NMDataIOROIDirectTools.value(spec,{'groupSizes'},[]));
            if strcmp(spec.labelMode,'metadata') && isempty(spec.files) && ~isempty(spec.vectorFiles), spec.files=spec.vectorFiles; end
            spec.dataVariable = NMDataIOROIDirectTools.text(spec,{'dataVariable'},'');
            spec.tableVariable = NMDataIOROIDirectTools.text(spec,{'tableVariable'},'');
            spec.tableFile = NMDataIOROIDirectTools.text(spec,{'tableFile'},'');
            spec.caseColumn = NMDataIOROIDirectTools.text(spec,{'caseColumn'},'');
            spec.featureColumns = NMDataIOROIDirectTools.value(spec,{'featureColumns'},[]);
            spec.caseIDs = NMDataIOROIDirectTools.cells(spec,{'caseIDs'});
            spec.caseIDsVariable = NMDataIOROIDirectTools.text(spec,{'caseIDsVariable'},'');
            caseMode=lower(strrep(strrep(NMDataIOROIDirectTools.text(spec,{'caseIDMode'},'legacy_spm'),'-','_'),' ','_'));
            if any(strcmp(caseMode,{'explicit','explicit_case_ids','caseids','case_ids','manual'})), spec.caseIDMode='explicit'; else, spec.caseIDMode='legacy_spm'; end
            if ~strcmp(spec.sourceFormat,'cat12_files'), spec.caseIDMode='explicit'; end
            spec.auxiliarySourceType = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'auxiliarySourceType'},'workspace')));
            spec.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOROIDirectTools.text(spec,{'auxiliaryAlignmentMode'},'case_id'));
            spec.auxiliaryVariableRoles = NMDataIOROIDirectTools.value(spec,{'auxiliaryVariableRoles'},struct());
            spec.auxiliaryTableFiles = NMDataIOROIDirectTools.cells(spec,{'auxiliaryTableFiles'});
            spec.roiSidecarFile = NMDataIOROIDirectTools.text(spec,{'roiSidecarFile'},'');
            spec.roiIDColumn = NMDataIOROIDirectTools.text(spec,{'roiIDColumn'},'');
            spec.roiNameColumn = NMDataIOROIDirectTools.text(spec,{'roiNameColumn'},'');
            spec.roiHemisphereColumn = NMDataIOROIDirectTools.text(spec,{'roiHemisphereColumn'},'');
            spec.roiXColumn = NMDataIOROIDirectTools.text(spec,{'roiXColumn'},'');
            spec.roiYColumn = NMDataIOROIDirectTools.text(spec,{'roiYColumn'},'');
            spec.roiZColumn = NMDataIOROIDirectTools.text(spec,{'roiZColumn'},'');
            spec.spatialKind = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'spatialKind'},'volumetric_atlas')));
            spec.atlasFile = NMDataIOROIDirectTools.text(spec,{'atlasFile'},'');
            spec.lhAnnotationFile = NMDataIOROIDirectTools.text(spec,{'lhAnnotationFile'},'');
            spec.rhAnnotationFile = NMDataIOROIDirectTools.text(spec,{'rhAnnotationFile'},'');
            spec.lhSurfaceGeometryFile = NMDataIOROIDirectTools.text(spec,{'lhSurfaceGeometryFile'},'');
            spec.rhSurfaceGeometryFile = NMDataIOROIDirectTools.text(spec,{'rhSurfaceGeometryFile'},'');
            spec.cat12Atlas = NMDataIOROIDirectTools.text(spec,{'cat12Atlas'},'');
            spec.cat12Measure = NMDataIOROIDirectTools.text(spec,{'cat12Measure'},'');
            spec.covariateNames = NMDataIOROIDirectTools.cells(spec,{'covariateNames'});
            spec.labelNames = NMDataIOROIDirectTools.cells(spec,{'labelNames','regressionLabelNames','desc_labels'});
            spec.uiGlobalModeSelection = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'uiGlobalModeSelection'},NMDataIOROIDirectTools.text(spec,{'globalMode'},'none'))));
            spec.globalMode = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'globalMode'},'none')));
            spec.globalName = NMDataIOROIDirectTools.text(spec,{'globalName'},'GlobalBrainVolume');
            spec.globnorm = double(NMDataIOROIDirectTools.value(spec,{'globnorm','globalMultiplier'},1));
            spec.globalSource = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'globalSource'},'user')));
            spec.globalUserSourceType = lower(strtrim(NMDataIOROIDirectTools.text(spec,{'globalUserSourceType'},'workspace')));
            spec.globalAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOROIDirectTools.text(spec,{'globalAlignmentMode'},'case_id'));
            spec.globalVariableRoles = NMDataIOROIDirectTools.value(spec,{'globalVariableRoles'},struct());
            spec.globalTableFiles = NMDataIOROIDirectTools.cells(spec,{'globalTableFiles'});
            spec.weightingFiles = NMDataIOROIDirectTools.cells(spec,{'weightingFiles'});
        end

        function [out, messages] = resolveCAT12Files(spec,progressTask,progressRange)
            if nargin < 2 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 3 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            messages = NMDataIOMessageTools.emptyMessages();
            out = NMDataIOROIDirectTools.emptyPayload();
            implicitLabels = [];
            sourceStart=double(progressRange(1)); sourceEnd=double(progressRange(2)); sourceSpan=max(0,sourceEnd-sourceStart);
            progressTask=NMProgressTools.phase(progressTask,'roi_cat12_subject_files',sourceStart,sourceStart+0.72*sourceSpan, ...
                'Reading CAT12 ROI subject files.');
            if strcmp(spec.labelMode,'legacy_groups')
                [files,implicitLabels,groupNames,groupSizes,classMessages] = NMDataIOROIDirectTools.classFilesAndLabels(spec.classFileLists);
                messages=[messages;classMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
                spec.files=files; spec.groupNames=groupNames; spec.groupSizes=groupSizes;
            end
            if isempty(spec.files)
                messages = NMDataIOMessageTools.make('danger',true,'roi.cat12.files','CAT12 ROI import requires at least one catROI XML or MAT file.',1,'red*'); return;
            end
            if isempty(spec.cat12Atlas) || isempty(spec.cat12Measure)
                messages = NMDataIOMessageTools.make('danger',true,'roi.cat12.selection','CAT12 ROI import requires explicit atlas-family and measurement selections.',1,'red*'); return;
            end
            if isempty(spec.atlasFile)
                messages = NMDataIOMessageTools.make('danger',true,'roi.cat12.atlas','CAT12 ROI import requires the corresponding volumetric atlas image.',1,'red*'); return;
            end
            Y = []; ids = []; names = {}; version = '';
            for ii=1:numel(spec.files)
                fileName = spec.files{ii};
                if exist(fileName,'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.cat12.file',sprintf('CAT12 ROI file does not exist: %s',fileName),1,'red*')]; return;
                end
                S = NMDataIOROIDirectTools.loadCAT12Struct(fileName);
                if ~isfield(S,spec.cat12Atlas)
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.cat12.atlasFamily',sprintf('CAT12 file %s does not contain atlas family %s.',fileName,spec.cat12Atlas),1,'red*')]; return;
                end
                a = S.(spec.cat12Atlas);
                NMDataIOROIDirectTools.assertCAT12Atlas(a,spec.cat12Atlas,fileName);
                if ~isfield(a.data,spec.cat12Measure)
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.cat12.measure',sprintf('CAT12 atlas %s in %s does not contain measurement %s.',spec.cat12Atlas,fileName,spec.cat12Measure),1,'red*')]; return;
                end
                thisIDs = double(a.ids(:)');
                thisNames = NMDataIOROIDirectTools.asCellstr(a.names);
                values = double(a.data.(spec.cat12Measure)(:))';
                if numel(values) ~= numel(thisIDs) || numel(thisNames) ~= numel(thisIDs)
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.cat12.dimension',sprintf('CAT12 ROI identity/value lengths disagree in %s.',fileName),1,'red*')]; return;
                end
                thisVersion = char(string(a.version));
                if ii==1
                    ids=thisIDs; names=thisNames; version=thisVersion; Y=nan(numel(spec.files),numel(ids));
                elseif ~isequal(thisIDs,ids) || ~isequal(thisNames,names) || ~strcmp(thisVersion,version)
                    messages = [messages; NMDataIOMessageTools.make('danger',true,'roi.cat12.contract',sprintf('CAT12 atlas identity, ROI order, or version differs in case file %s.',fileName),1,'red*')]; return;
                end
                Y(ii,:)=values;
                progressTask=NMProgressTools.step(progressTask,ii,numel(spec.files), ...
                    sprintf('Reading CAT12 ROI subject file %g of %g.',ii,numel(spec.files)),true);
            end
            atlasRange=[sourceStart+0.72*sourceSpan sourceEnd];
            [spatial,coords,spatialMessages] = NMDataIOROIDirectTools.validateVolumetricAtlas(spec.atlasFile,ids,progressTask,atlasRange);
            messages=[messages;spatialMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
            producer=NMDataIOROIProvenanceTools.directProducer('cat12_roi',spec.files,'');
            roi=NMDataIOROIProvenanceTools.fromDirectImport(ids,names,{},coords,spatial,producer,size(Y,2));
            if ~roi.ok, messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.cat12.provenance',roi.message,1,'red*')]; return; end
            out.Y=Y;
            [out.caseIDs,caseMessages]=NMDataIOROIDirectTools.caseIDs(spec,numel(spec.files),spec.files);
            messages=[messages;caseMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
            out.featnames=names; out.roiProvenance=roi; out.desc_groups=spec.groupNames;
            if strcmp(spec.labelMode,'legacy_groups'), out.label=implicitLabels; end
            out.sourceMetadata=struct('cat12Atlas',spec.cat12Atlas,'cat12Measure',spec.cat12Measure,'cat12Version',version, ...
                'labelMode',spec.labelMode,'groupNames',{spec.groupNames},'groupSizes',spec.groupSizes);
        end

        function [out, messages] = resolveTabular(spec,progressTask,progressRange)
            if nargin < 2 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 3 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            messages=NMDataIOMessageTools.emptyMessages(); out=NMDataIOROIDirectTools.emptyPayload();
            sourceStart=double(progressRange(1)); sourceEnd=double(progressRange(2)); sourceSpan=max(0,sourceEnd-sourceStart);
            progressTask=NMProgressTools.phase(progressTask,'roi_tabular_source',sourceStart,sourceStart+0.36*sourceSpan, ...
                'Reading ROI table/matrix source.');
            [Y,caseIDs,sourceFiles,dataFeatureNames,sourceMessages]=NMDataIOROIDirectTools.tabularMatrix(spec);
            messages=[messages;sourceMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
            if isempty(spec.roiSidecarFile)
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar','Tabular ROI import requires an ROI description file in the same order as the data columns.',1,'red*')]; return;
            end
            progressTask=NMProgressTools.phase(progressTask,'roi_tabular_sidecar',sourceStart+0.36*sourceSpan,sourceStart+0.52*sourceSpan, ...
                'Reading the ROI description file.');
            opts=struct('idColumn',spec.roiIDColumn,'nameColumn',spec.roiNameColumn,'hemisphereColumn',spec.roiHemisphereColumn, ...
                'xColumn',spec.roiXColumn,'yColumn',spec.roiYColumn,'zColumn',spec.roiZColumn);
            side=NMDataIOAtlasDescriptorTools.resolveROIFeatureDescriptor(spec.roiSidecarFile,opts);
            if ~side.ok
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar',side.message,1,'red*')]; return;
            end
            [Y,side,matchReport,matchMessages]=NMDataIOROIDirectTools.matchTabularSidecar(Y,dataFeatureNames,side);
            messages=[messages;matchMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
            spatialRange=[sourceStart+0.52*sourceSpan sourceEnd];
            progressTask=NMProgressTools.phase(progressTask,'roi_tabular_spatial_reference',spatialRange(1),spatialRange(2), ...
                'Validating ROI spatial reference.');
            switch spec.spatialKind
                case 'volumetric_atlas'
                    if any(~cellfun(@isempty,side.hemisphere))
                        messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar.hemisphere','A volumetric ROI description file must not assign left/right hemisphere identities.',1,'red*')]; return;
                    end
                    [spatial,atlasCoords,spatialMessages]=NMDataIOROIDirectTools.validateVolumetricAtlas(spec.atlasFile,side.roiIDs,progressTask,spatialRange);
                    coords=side.mniCoordinates; if any(~all(isfinite(coords),2)), coords=atlasCoords; end
                case 'surface_annotation'
                    [spatial,spatialMessages]=NMDataIOROIDirectTools.validateSurfaceAnnotations(spec,side.roiIDs,side.roiNames,side.hemisphere,progressTask,spatialRange);
                    coords=side.mniCoordinates;
                otherwise
                    spatialMessages=NMDataIOMessageTools.make('danger',true,'roi.spatialKind',sprintf('Unsupported ROI spatial reference kind: %s.',spec.spatialKind),1,'red*');
                    spatial=[]; coords=[];
            end
            messages=[messages;spatialMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
            producer=NMDataIOROIProvenanceTools.directProducer('roi_table',[sourceFiles(:);{spec.roiSidecarFile}], '');
            roi=NMDataIOROIProvenanceTools.fromDirectImport(side.roiIDs,side.roiNames,side.hemisphere,coords,spatial,producer,size(Y,2));
            if ~roi.ok, messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.table.provenance',roi.message,1,'red*')]; return; end
            out.Y=Y; out.caseIDs=caseIDs; out.featnames=side.roiNames; out.roiProvenance=roi;
            out.sourceMetadata=struct('roiSidecarFile',spec.roiSidecarFile,'spatialKind',spec.spatialKind,'sidecarMatchReport',matchReport);
        end

        function [Y,caseIDs,sourceFiles,featureNames,messages] = tabularMatrix(spec)
            messages=NMDataIOMessageTools.emptyMessages(); Y=[]; caseIDs={}; sourceFiles={}; featureNames={};
            switch spec.sourceFormat
                case 'workspace_matrix'
                    if isempty(spec.dataVariable), messages=NMDataIOMessageTools.make('danger',true,'roi.matrix.variable','Select the workspace ROI matrix variable.',1,'red*'); return; end
                    Y=NMDataIOROIDirectTools.workspace(spec.dataVariable);
                    if ~isnumeric(Y) || ndims(Y)~=2, messages=NMDataIOMessageTools.make('danger',true,'roi.matrix.numeric','Workspace ROI matrix must be numeric subjects-by-ROIs.',1,'red*'); return; end
                    sourceFiles={['workspace:' spec.dataVariable]};
                    [caseIDs,caseMessages]=NMDataIOROIDirectTools.caseIDs(spec,size(Y,1),{});
                    messages=[messages;caseMessages]; if NMDataIOMessageTools.hasFatal(messages), return; end
                case 'workspace_table'
                    if isempty(spec.tableVariable), messages=NMDataIOMessageTools.make('danger',true,'roi.table.variable','Select the workspace ROI table variable.',1,'red*'); return; end
                    T=NMDataIOROIDirectTools.workspace(spec.tableVariable);
                    if ~istable(T), messages=NMDataIOMessageTools.make('danger',true,'roi.table.type','Selected workspace ROI source is not a MATLAB table.',1,'red*'); return; end
                    [Y,caseIDs,featureNames,messages]=NMDataIOROIDirectTools.matrixFromTable(T,spec); sourceFiles={['workspace:' spec.tableVariable]};
                case 'table_file'
                    if isempty(spec.tableFile) || exist(spec.tableFile,'file')~=2, messages=NMDataIOMessageTools.make('danger',true,'roi.table.file',sprintf('ROI table file does not exist: %s',spec.tableFile),1,'red*'); return; end
                    T=readtable(spec.tableFile,'VariableNamingRule','preserve');
                    [Y,caseIDs,featureNames,messages]=NMDataIOROIDirectTools.matrixFromTable(T,spec); sourceFiles={spec.tableFile};
            end
            Y=double(Y);
            if isempty(Y) || size(Y,2)<1, messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.matrix.empty','ROI matrix contains no feature columns.',1,'red*')]; end
            if numel(caseIDs)~=size(Y,1), messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.caseIDs',sprintf('ROI case IDs=%g but data rows=%g.',numel(caseIDs),size(Y,1)),1,'red*')]; end
            if numel(unique(caseIDs))~=numel(caseIDs), messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.caseIDs.duplicate','ROI case IDs contain duplicates.',1,'red*')]; end
        end

        function [Y,caseIDs,featureNames,messages] = matrixFromTable(T,spec)
            messages=NMDataIOMessageTools.emptyMessages(); Y=[]; caseIDs={}; featureNames={}; names=T.Properties.VariableNames;
            cols=spec.featureColumns;
            if isempty(cols), messages=NMDataIOMessageTools.make('danger',true,'roi.table.features','Tabular ROI input requires explicit feature-column selection.',1,'red*'); return; end
            if iscell(cols) || isstring(cols)
                colNames=cellstr(string(cols)); [tf,idx]=ismember(colNames,names); if ~all(tf), messages=NMDataIOMessageTools.make('danger',true,'roi.table.features','One or more selected ROI feature columns are absent from the table.',1,'red*'); return; end
            else
                idx=double(cols(:)'); if any(idx<1|idx>width(T)|idx~=round(idx)) || numel(unique(idx))~=numel(idx), messages=NMDataIOMessageTools.make('danger',true,'roi.table.features','ROI feature-column indices must be unique valid table positions.',1,'red*'); return; end
            end
            featureNames=names(idx);
            try, Y=table2array(T(:,idx)); catch ME, messages=NMDataIOMessageTools.fromException(ME,'roi.table.numericFeatures'); return; end
            if ~isnumeric(Y), messages=NMDataIOMessageTools.make('danger',true,'roi.table.numericFeatures','Selected ROI table feature columns must form a numeric matrix.',1,'red*'); return; end
            if ~isempty(T.Properties.RowNames), caseIDs=T.Properties.RowNames(:); return; end
            if isempty(spec.caseColumn), messages=NMDataIOMessageTools.make('danger',true,'roi.table.caseColumn','ROI table without RowNames requires an explicit case-ID column.',1,'red*'); return; end
            hit=find(strcmp(names,spec.caseColumn),1); if isempty(hit), messages=NMDataIOMessageTools.make('danger',true,'roi.table.caseColumn',sprintf('ROI case-ID column was not found exactly: %s.',spec.caseColumn),1,'red*'); return; end
            caseIDs=NMDataIOROIDirectTools.asCellstr(T{:,hit});
        end

        function [Y,side,report,messages] = matchTabularSidecar(Y,dataFeatureNames,side)
            messages=NMDataIOMessageTools.emptyMessages();
            dataFeatureNames=NMDataIOROIDirectTools.asCellstr(dataFeatureNames);
            sideNames=NMDataIOROIDirectTools.asCellstr(side.roiNames);
            report=struct('mode','row_order','perfect',side.nRows==size(Y,2),'nDataColumns',double(size(Y,2)), ...
                'nSidecarRows',double(side.nRows),'nMatched',double(min(side.nRows,size(Y,2))), ...
                'unmatchedDataNames',{{}},'unmatchedSidecarNames',{{}});
            if side.nRows==size(Y,2)
                return;
            end
            if isempty(dataFeatureNames) || numel(dataFeatureNames)~=size(Y,2)
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar.dimension', ...
                    sprintf(['The ROI description file has %g row(s), but the data matrix has %g feature column(s). ', ...
                    'The data source does not provide one exact feature name per data column, so NM2 cannot determine which ROI rows belong to the selected data.'],side.nRows,size(Y,2)),1,'red*')]; return;
            end
            if numel(unique(dataFeatureNames))~=numel(dataFeatureNames)
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar.dataNames', ...
                    'ROI table feature names are duplicated, so they cannot be matched unambiguously to the ROI description file.',1,'red*')]; return;
            end
            if numel(sideNames)~=side.nRows || numel(unique(sideNames))~=numel(sideNames)
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar.names', ...
                    'ROI names in the ROI description file must be unique when the file and data have different numbers of rows/columns.',1,'red*')]; return;
            end
            [matchedSide,dataLoc]=ismember(sideNames,dataFeatureNames);
            sideLoc=find(matchedSide);
            dataLoc=dataLoc(matchedSide);
            if isempty(sideLoc)
                report.nMatched=0;
                report.unmatchedDataNames=dataFeatureNames;
                report.unmatchedSidecarNames=sideNames;
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.sidecar.match', ...
                    'The ROI description file and data have different sizes, and no exact ROI-name matches were found.',1,'red*')]; return;
            end
            unmatchedData=dataFeatureNames(~ismember(dataFeatureNames,sideNames));
            unmatchedSide=sideNames(~matchedSide);
            Y=Y(:,dataLoc);
            side=NMDataIOROIDirectTools.subsetSidecar(side,sideLoc);
            report.mode='matching_only';
            report.perfect=false;
            report.nMatched=double(numel(sideLoc));
            report.unmatchedDataNames=unmatchedData;
            report.unmatchedSidecarNames=unmatchedSide;
            messages=[messages;NMDataIOMessageTools.make('warn',false,'roi.sidecar.partialMatch', ...
                sprintf(['The ROI description file and selected data have different sizes (%g ROI rows vs %g selected data columns). ', ...
                'Import will use the %g exact ROI-name match(es) only; %g unmatched data column(s) and %g unmatched ROI-description row(s) are excluded.'], ...
                report.nSidecarRows,report.nDataColumns,report.nMatched,numel(unmatchedData),numel(unmatchedSide)),2,'orange*')];
        end

        function side = subsetSidecar(side,idx)
            idx=double(idx(:)');
            if isfield(side,'roiIDs'), side.roiIDs=side.roiIDs(idx); end
            if isfield(side,'roiNames'), side.roiNames=side.roiNames(idx); end
            if isfield(side,'hemisphere'), side.hemisphere=side.hemisphere(idx); end
            if isfield(side,'mniCoordinates') && ~isempty(side.mniCoordinates), side.mniCoordinates=side.mniCoordinates(idx,:); end
            side.nRows=double(numel(idx));
        end

        function [spatial,coords,messages] = validateVolumetricAtlas(atlasFile,roiIDs,progressTask,progressRange)
            if nargin < 3 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 4 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            messages=NMDataIOMessageTools.emptyMessages(); spatial=[]; coords=[];
            if isempty(atlasFile), messages=NMDataIOMessageTools.make('danger',true,'roi.atlas','Direct volumetric ROI import requires a labelled atlas image.',1,'red*'); return; end
            atlas=NMDataIOAtlasDescriptorTools.atlasNodeCoordinates(atlasFile,roiIDs,progressTask,progressRange);
            if ~atlas.ok || ~all(atlas.matchedMask)
                messages=NMDataIOMessageTools.make('danger',true,'roi.atlas.mapping',sprintf('ROI atlas validation failed: %s',atlas.message),1,'red*'); return;
            end
            coords=atlas.coordinates;
            opts=struct('labelModel','discrete3d','validationBasis','direct_labelled_atlas_membership', ...
                'identity',atlas.spatialIdentity,'referenceDim',atlas.referenceDim,'referenceMat',atlas.referenceMat);
            spatial=NMDataIOROIProvenanceTools.validatedSpatialReference('volumetric_atlas',{atlasFile},roiIDs,opts);
        end

        function [spatial,messages] = validateSurfaceAnnotations(spec,roiIDs,roiNames,hemi,progressTask,progressRange)
            % validateSurfaceAnnotations  Validate exact surface ROI identity and its display geometry.
            %
            % Purpose:
            %   Establish the canonical hemisphere + annotation-ID mapping for direct surface ROI
            %   input and, when spatial QC is requested, bind the annotation vertex order to the
            %   explicitly supplied native/display mesh for the same hemisphere.
            % Authority and flow:
            %   ROI sidecar identity -> explicit LH/RH annotation -> exact annotation membership;
            %   explicit LH/RH display mesh -> vertex-count validation against that annotation.
            % Scientific/state contract:
            %   Annotation files define parcel identity. Geometry files define vertex coordinates and
            %   faces only; they never infer ROI identity. No filename-derived atlas or template is used.
            % Materialization and performance:
            %   YES. Reads each configured annotation and display mesh once during explicit ROI import/
            %   QC preparation. This function is not permitted on interactive viewer/navigation paths.
            % Failure semantics:
            %   Missing annotations and ROI/name mismatches fail explicitly. A configured display mesh
            %   must match the annotation vertex count exactly; absent geometry leaves spatial QC unavailable
            %   but does not invalidate the scientific ROI import. No geometry fallback is guessed.
            if nargin < 5 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 6 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            messages=NMDataIOMessageTools.emptyMessages(); spatial=[];
            hemi=NMDataIOROIDirectTools.asCellstr(hemi); roiNames=NMDataIOROIDirectTools.asCellstr(roiNames);
            progressTask=NMProgressTools.phase(progressTask,'roi_surface_annotations',progressRange(1),progressRange(2), ...
                'Validating surface ROI annotations and display geometry.');
            if numel(hemi)~=numel(roiIDs) || numel(roiNames)~=numel(roiIDs) || any(cellfun(@isempty,hemi))
                messages=NMDataIOMessageTools.make('danger',true,'roi.surface.hemisphere','The surface ROI description file requires one hemisphere and one ROI name for every ROI row.',1,'red*'); return;
            end
            files=struct('lh',spec.lhAnnotationFile,'rh',spec.rhAnnotationFile);
            geometry=struct('lh',spec.lhSurfaceGeometryFile,'rh',spec.rhSurfaceGeometryFile);
            used={}; byHemi=struct('lh',{{}},'rh',{{}}); geometryByHemi=struct('lh',{{}},'rh',{{}});
            usedTokens={'lh','rh'};
            activeTokens=usedTokens(cellfun(@(token)any(strcmp(hemi,token)),usedTokens));
            for hi=1:numel(activeTokens)
                token=activeTokens{hi}; mask=strcmp(hemi,token); requested=roiIDs(mask); requestedNames=roiNames(mask);
                f=files.(token);
                if isempty(f), messages=[messages;NMDataIOMessageTools.make('danger',true,['roi.surface.' token],sprintf('Surface ROI data contain %s parcels but no %s annotation file was supplied.',upper(token),upper(token)),1,'red*')]; return; end
                g=geometry.(token);
                try, [labels,annotInfo]=NMDataIOSurfaceTools.readAnnotationLabels(f); catch ME, messages=[messages;NMDataIOMessageTools.fromException(ME,['roi.surface.' token '.annotation'])]; return; end
                [present,presentNames]=NMDataIOSurfaceTools.roiSetFromAnnotation(labels,annotInfo,token);
                missing=setdiff(double(requested(:)'),double(present(:)'),'stable');
                if ~isempty(missing), messages=[messages;NMDataIOMessageTools.make('danger',true,['roi.surface.' token '.mapping'],sprintf('%s annotation is missing ROI ID(s): %s.',upper(token),NMDataIOROIDirectTools.shortNumericList(missing,12)),1,'red*')]; return; end
                [~,loc]=ismember(double(requested(:)'),double(present(:)')); expected=presentNames(loc);
                if ~isequal(requestedNames(:)',expected(:)')
                    messages=[messages;NMDataIOMessageTools.make('danger',true,['roi.surface.' token '.names'],sprintf('%s ROI names in the ROI description file do not exactly match the selected annotation.',upper(token)),1,'red*')]; return;
                end
                if ~isempty(g)
                    try, [vertices,~,~]=NMDataIOSurfaceTools.readSurfaceGeometry(g); catch ME, messages=[messages;NMDataIOMessageTools.fromException(ME,['roi.surface.' token '.geometry'])]; return; end
                    if size(vertices,1)~=numel(labels)
                        messages=[messages;NMDataIOMessageTools.make('danger',true,['roi.surface.' token '.geometryVertexCount'], ...
                            sprintf('%s surface display mesh has %g vertices but the selected annotation has %g labels. Select the exact mesh corresponding to that annotation vertex order.',upper(token),size(vertices,1),numel(labels)),1,'red*')]; return;
                    end
                    geometryByHemi.(token)={g};
                end
                used{end+1}=f; byHemi.(token)={f}; %#ok<AGROW>
                progressTask=NMProgressTools.step(progressTask,hi,numel(activeTokens), ...
                    sprintf('Validated %s surface ROI annotation/geometry (%g of %g).',upper(token),hi,numel(activeTokens)),true);
            end
            identity=NMDataIOROIProvenanceTools.surfaceReferenceIdentity(roiIDs,roiNames,hemi);
            opts=struct('labelModel','annotation_labels','validationBasis','direct_surface_annotation_membership', ...
                'annotationFilesByHemisphere',byHemi,'surfaceGeometryFilesByHemisphere',geometryByHemi,'identity',identity);
            spatial=NMDataIOROIProvenanceTools.validatedSpatialReference('surface_annotation',used,roiIDs,opts);
        end

        function [out,messages] = applyGlobalVolumeCorrection(out,spec)
            % applyGlobalVolumeCorrection  Apply aligned volumetric ROI global-value semantics.
            %
            % Purpose:
            %   Resolve one subject-aligned global brain-volume variable for canonical volumetric ROI data.
            %   Proportional mode scales ROI values before QC; ANCOVA mode leaves ROI values unchanged and
            %   appends the global vector to the modelling covariates.
            % Inputs/outputs:
            %   out contains canonical Y, caseIDs, optional covariates and validated ROI provenance; spec contains
            %   the persisted generic global-role configuration. The returned out contains the configured effect.
            % Authority and flow:
            %   canonical ROI provenance determines eligibility; the generic auxiliary materializer owns source
            %   reading and subject matching; the existing CalcGlobals/spm_global authority owns derived volumetric globals;
            %   proportionalGlobalScaleFactors owns proportional scaling arithmetic.
            % Scientific/state contract:
            %   Only volumetric_atlas ROI provenance admits these global-volume modes. Proportional scaling changes
            %   feature values before QC. ANCOVA does not residualize or alter ROI values; it appends the aligned
            %   global measure as a covariate for downstream modelling. Surface ROI keeps effective mode None.
            % Invariants:
            %   Exactly one finite global value per subject and exact case alignment. Proportional mode additionally
            %   requires strictly positive global values. ROI identity/order and spatial provenance are unchanged.
            % Materialization and performance:
            %   Resolves one user-defined global source block or delegates derived volumetric globals to CalcGlobals/spm_global.
            %   Proportional mode performs O(N*P) row scaling; ANCOVA
            %   appends one O(N) covariate. No CAT12/XML, atlas, annotation or image data are reread here.
            % Failure semantics:
            %   Surface use, unsupported modes, missing/misaligned globals or invalid values fail explicitly.
            % Side effects: none outside returned out.
            messages=NMDataIOMessageTools.emptyMessages();
            correction=struct('mode','none','globalName',spec.globalName,'globalMultiplier',double(spec.globnorm), ...
                'appliedBeforeQC',false,'mapping',struct());
            if ~isstruct(out.roiProvenance) || ~isfield(out.roiProvenance,'spatialReferences') || isempty(out.roiProvenance.spatialReferences)
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.globals.provenance', ...
                    'Global-volume correction requires a valid volumetric ROI spatial reference.',1,'red*')];
                out.globalVolumeCorrection=correction; return;
            end
            spatialKind=char(string(out.roiProvenance.spatialReferences(1).kind));
            mode=lower(strrep(strrep(char(string(spec.globalMode)),'-','_'),' ','_'));
            if any(strcmp(mode,{'','none','no','off'}))
                out.globalVolumeCorrection=correction; return;
            end
            if ~strcmp(spatialKind,'volumetric_atlas')
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.globals.surface', ...
                    'Global brain-volume correction is defined only for volumetric ROI data. Surface-annotation ROI measures must use global mode None.',1,'red*')];
                out.globalVolumeCorrection=correction; return;
            end
            if ~any(strcmp(mode,{'proportional','proportional_scaling','scale','ancova','covariate'}))
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.globals.mode', ...
                    sprintf('Unsupported volumetric ROI global mode: %s.',char(string(spec.globalMode))),1,'red*')];
                out.globalVolumeCorrection=correction; return;
            end
            mapping=struct();
            if NMDataIOImportTools.isDerivedGlobalSource(spec.globalSource)
                globalIO=spec;
                globalIO.ID=out.caseIDs;
                globalIO.Y=out.Y;
                [globals,globalMessages]=NMDataIOImportTools.globalVector(globalIO);
                messages=[messages;globalMessages]; if NMDataIOMessageTools.hasFatal(messages), out.globalVolumeCorrection=correction; return; end
                mapping=struct('source','spm_global','derivedDuringRead',true);
            else
                globalIO=spec;
                [globalIO,globalMessages,mapping]=NMDataIOImportTools.materializeConfiguredGlobalRole(globalIO,out.caseIDs);
                messages=[messages;globalMessages]; if NMDataIOMessageTools.hasFatal(messages), out.globalVolumeCorrection=correction; return; end
                if ~isfield(globalIO,'g') || isempty(globalIO.g)
                    messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.globals.values', ...
                        'The selected volumetric ROI global mode requires exactly one assigned global-value input or spm_global derivation.',1,'red*')];
                    out.globalVolumeCorrection=correction; return;
                end
                globals=double(globalIO.g(:));
            end
            if numel(globals)~=size(out.Y,1) || any(~isfinite(globals))
                messages=[messages;NMDataIOMessageTools.make('danger',true,'roi.globals.values', ...
                    sprintf('Volumetric ROI global input must provide one finite value for each of the %g aligned case(s).',size(out.Y,1)),1,'red*')];
                out.globalVolumeCorrection=correction; return;
            end
            if any(strcmp(mode,{'proportional','proportional_scaling','scale'}))
                [factors,scaleMessages]=NMDataIOImageImportTools.proportionalGlobalScaleFactors( ...
                    globals,spec.globnorm,size(out.Y,1),'roi.globals.proportional');
                messages=[messages;scaleMessages]; if NMDataIOMessageTools.hasFatal(messages), out.globalVolumeCorrection=correction; return; end
                out.Y=bsxfun(@times,double(out.Y),factors(:));
                correction.mode='proportional'; correction.appliedBeforeQC=true;
            else
                out.covars=globals;
                out.covnames={spec.globalName};
                correction.mode='ancova';
            end
            correction.mapping=mapping;
            out.globalVolumeCorrection=correction;
        end

        function [Yw,prov,messages] = resolveWeightingFiles(spec,roi,progressTask,progressRange)
            % resolveWeightingFiles  Align explicit ROI-level weighting files to canonical ROI columns.
            %
            % Weighting input is already parcel-wise. No voxel/vertex resampling or
            % spatial collapse is permitted at this boundary. Each file is a table
            % with exact columns roi_id and weight; surface ROI files additionally
            % require hemisphere. Optional roi_name is verified but never used for
            % identity matching.
            if nargin < 3 || ~isstruct(progressTask), progressTask=NMProgressTools.emptyTaskForLocalUse(); end
            if nargin < 4 || numel(progressRange)~=2, progressRange=[progressTask.phaseStart progressTask.phaseEnd]; end
            messages=NMDataIOMessageTools.emptyMessages(); Yw=[]; prov=struct();
            files=spec.weightingFiles;
            if isempty(files), return; end
            progressTask=NMProgressTools.phase(progressTask,'roi_weighting_files',progressRange(1),progressRange(2), ...
                'Reading and aligning ROI weighting/ranking files.');
            if ~isstruct(roi) || ~isfield(roi,'ok') || ~roi.ok
                messages=NMDataIOMessageTools.make('danger',true,'roi.weighting.provenance', ...
                    'ROI weighting files require a valid ROI definition for this modality.',1,'red*'); return;
            end
            canonicalKeys=NMDataIOROIDirectTools.asCellstr(roi.columnKeys);
            canonicalNames=NMDataIOROIDirectTools.asCellstr(roi.roiNames);
            spatialKind=char(string(roi.spatialReferences(1).kind));
            Yw=nan(numel(files),numel(canonicalKeys));
            for w=1:numel(files)
                fileName=files{w};
                if exist(fileName,'file')~=2
                    messages=[messages;NMDataIOMessageTools.make('danger',true,sprintf('roi.weighting.file[%g]',w), ...
                        sprintf('ROI weighting file does not exist: %s',fileName),1,'red*')]; return;
                end
                try
                    T=readtable(fileName,'VariableNamingRule','preserve');
                    names=T.Properties.VariableNames;
                    idCol=find(strcmp(names,'roi_id'),1);
                    weightCol=find(strcmp(names,'weight'),1);
                    if isempty(idCol) || isempty(weightCol)
                        error('NMDataIOROIDirectTools:ROIWeightingSchema', ...
                            'ROI weighting file %s must contain exact columns roi_id and weight.',fileName);
                    end
                    ids=T{:,idCol}; weights=T{:,weightCol};
                    if ~isnumeric(ids) || ~isvector(ids) || any(~isfinite(double(ids(:))))
                        error('NMDataIOROIDirectTools:ROIWeightingIDs','ROI weighting file %s roi_id must be a finite numeric vector.',fileName);
                    end
                    if ~isnumeric(weights) || ~isvector(weights) || any(~isfinite(double(weights(:))))
                        error('NMDataIOROIDirectTools:ROIWeightingValues','ROI weighting file %s weight must be a finite numeric vector.',fileName);
                    end
                    ids=double(ids(:)); weights=double(weights(:));
                    if numel(ids)~=numel(weights)
                        error('NMDataIOROIDirectTools:ROIWeightingCount','ROI weighting file %s has inconsistent roi_id and weight lengths.',fileName);
                    end
                    if strcmp(spatialKind,'surface_annotation')
                        hemiCol=find(strcmp(names,'hemisphere'),1);
                        if isempty(hemiCol)
                            error('NMDataIOROIDirectTools:ROIWeightingHemisphere', ...
                                'Surface ROI weighting file %s must contain exact column hemisphere.',fileName);
                        end
                        hemi=lower(strtrim(string(T{:,hemiCol})));
                        if numel(hemi)~=numel(ids) || any(~ismember(hemi,["lh","rh"]))
                            error('NMDataIOROIDirectTools:ROIWeightingHemisphere', ...
                                'Surface ROI weighting file %s hemisphere values must be exactly lh or rh.',fileName);
                        end
                        fileKeys=arrayfun(@(i)sprintf('%s:%0.15g',char(hemi(i)),ids(i)),1:numel(ids),'UniformOutput',false);
                    elseif strcmp(spatialKind,'volumetric_atlas')
                        fileKeys=arrayfun(@(id)sprintf('volume:%0.15g',id),ids','UniformOutput',false);
                    else
                        error('NMDataIOROIDirectTools:ROIWeightingSpatialKind','Unsupported ROI weighting spatial kind: %s.',spatialKind);
                    end
                    if numel(unique(fileKeys))~=numel(fileKeys)
                        error('NMDataIOROIDirectTools:ROIWeightingDuplicate','ROI weighting file %s contains duplicate ROI identities.',fileName);
                    end
                    if numel(fileKeys)~=numel(canonicalKeys) || ~isempty(setxor(fileKeys,canonicalKeys))
                        error('NMDataIOROIDirectTools:ROIWeightingIdentity', ...
                            'ROI weighting file %s does not contain exactly the same ROI identities as this modality.',fileName);
                    end
                    [matched,loc]=ismember(canonicalKeys,fileKeys);
                    if ~all(matched) || numel(unique(loc))~=numel(loc)
                        error('NMDataIOROIDirectTools:ROIWeightingMapping','ROI weighting file %s could not be matched uniquely to the ROI order used by this modality.',fileName);
                    end
                    nameCol=find(strcmp(names,'roi_name'),1);
                    if ~isempty(nameCol)
                        fileNames=NMDataIOROIDirectTools.asCellstr(T{:,nameCol});
                        if numel(fileNames)~=numel(fileKeys) || ~isequal(fileNames(loc),canonicalNames)
                            error('NMDataIOROIDirectTools:ROIWeightingNames', ...
                                'ROI weighting file %s contains ROI names that do not exactly match this modality.',fileName);
                        end
                    end
                    Yw(w,:)=weights(loc)';
                    progressTask=NMProgressTools.step(progressTask,w,numel(files), ...
                        sprintf('Matched ROI weighting file %g of %g.',w,numel(files)),true);
                catch ME
                    messages=[messages;NMDataIOMessageTools.fromException(ME,sprintf('roi.weighting.file[%g]',w))]; return;
                end
            end
            prov=struct('mode','canonical_roi_file','weightingFiles',{files(:)'}, ...
                'roiIDs',double(roi.roiIDs(:)'),'roiNames',{canonicalNames(:)'},'hemisphere',{NMDataIOROIDirectTools.asCellstr(roi.hemisphere)}, ...
                'identityKeys',{canonicalKeys(:)'},'spatialKind',spatialKind, ...
                'schema','One row per ROI; exact columns roi_id, weight; surface additionally hemisphere; optional roi_name is verified.');
        end

        function S = loadCAT12Struct(fileName)
            [~,~,ext]=fileparts(fileName);
            switch lower(ext)
                case '.xml'
                    S=NMDataIOROIDirectTools.readCAT12XML(fileName);
                case '.mat'
                    d=load(fileName,'S');
                    if ~isfield(d,'S') || ~isstruct(d.S) || ~isscalar(d.S)
                        error('NMDataIOROIDirectTools:CAT12Structure','CAT12 ROI MAT file %s does not contain scalar struct S.',fileName);
                    end
                    S=d.S;
                otherwise
                    error('NMDataIOROIDirectTools:CAT12FileType', ...
                        'CAT12 ROI input must be a catROI XML file or compatible MAT file: %s',fileName);
            end
        end

        function S = readCAT12XML(fileName)
            % readCAT12XML  Read the narrow CAT12 catROI schema without CAT12/SPM dependencies.
            try
                doc=xmlread(fileName);
            catch ME
                error('NMDataIOROIDirectTools:CAT12XMLRead', ...
                    'Unable to read CAT12 ROI XML file %s: %s',fileName,ME.message);
            end
            root=doc.getDocumentElement();
            if isempty(root) || ~strcmp(char(root.getNodeName()),'S')
                error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                    'CAT12 ROI XML file %s must have root element S.',fileName);
            end
            S=struct();
            atlasNodes=root.getChildNodes();
            for ai=0:atlasNodes.getLength()-1
                atlasNode=atlasNodes.item(ai);
                if atlasNode.getNodeType()~=1, continue; end
                atlasName=char(atlasNode.getNodeName());
                if ~isvarname(atlasName) || isfield(S,atlasName)
                    error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                        'CAT12 ROI XML file %s has an invalid or duplicate atlas element %s.',fileName,atlasName);
                end
                idsNode=NMDataIOROIDirectTools.cat12SingleElement(atlasNode,'ids',atlasName,fileName);
                namesNode=NMDataIOROIDirectTools.cat12SingleElement(atlasNode,'names',atlasName,fileName);
                versionNode=NMDataIOROIDirectTools.cat12SingleElement(atlasNode,'version',atlasName,fileName);
                dataNode=NMDataIOROIDirectTools.cat12SingleElement(atlasNode,'data',atlasName,fileName);
                ids=NMDataIOROIDirectTools.cat12NumericText(char(idsNode.getTextContent()),'ids',atlasName,fileName);
                itemNodes=namesNode.getElementsByTagName('item');
                names=cell(itemNodes.getLength(),1);
                for ni=0:itemNodes.getLength()-1
                    names{ni+1}=strtrim(char(itemNodes.item(ni).getTextContent()));
                end
                data=struct();
                measureNodes=dataNode.getChildNodes();
                for mi=0:measureNodes.getLength()-1
                    measureNode=measureNodes.item(mi);
                    if measureNode.getNodeType()~=1, continue; end
                    measureName=char(measureNode.getNodeName());
                    if ~isvarname(measureName) || isfield(data,measureName)
                        error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                            'CAT12 ROI XML atlas %s in %s has an invalid or duplicate measurement %s.',atlasName,fileName,measureName);
                    end
                    data.(measureName)=NMDataIOROIDirectTools.cat12NumericText( ...
                        char(measureNode.getTextContent()),measureName,atlasName,fileName);
                end
                if isempty(fieldnames(data))
                    error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                        'CAT12 ROI XML atlas %s in %s contains no ROI measurements.',atlasName,fileName);
                end
                S.(atlasName)=struct('ids',ids(:),'names',{names}, ...
                    'version',strtrim(char(versionNode.getTextContent())),'data',data);
            end
            if isempty(fieldnames(S))
                error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                    'CAT12 ROI XML file %s contains no atlas families.',fileName);
            end
        end

        function node = cat12SingleElement(parent,name,atlasName,fileName)
            nodes=parent.getElementsByTagName(name);
            if nodes.getLength()~=1
                error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                    'CAT12 ROI XML atlas %s in %s must contain exactly one %s element.',atlasName,fileName,name);
            end
            node=nodes.item(0);
        end

        function values = cat12NumericText(text,label,atlasName,fileName)
            clean=regexprep(text,'[\[\];,]',' ');
            clean=strtrim(clean);
            if isempty(clean)
                error('NMDataIOROIDirectTools:CAT12XMLSchema', ...
                    'CAT12 ROI XML %s for atlas %s in %s is empty.',label,atlasName,fileName);
            end
            tokens=regexp(clean,'\s+','split');
            values=str2double(tokens);
            allowedNaN=strcmpi(tokens,'nan');
            if any(isnan(values) & ~allowedNaN)
                error('NMDataIOROIDirectTools:CAT12XMLNumeric', ...
                    'CAT12 ROI XML %s for atlas %s in %s contains non-numeric content.',label,atlasName,fileName);
            end
            values=values(:);
        end

        function assertCAT12Atlas(a,name,fileName)
            if ~isstruct(a) || ~isscalar(a) || ~all(isfield(a,{'ids','names','version','data'})) || ~isstruct(a.data)
                error('NMDataIOROIDirectTools:CAT12Atlas','CAT12 atlas %s in %s lacks ids/names/version/data.',name,fileName);
            end
            ids=double(a.ids(:)); names=NMDataIOROIDirectTools.asCellstr(a.names);
            if isempty(ids) || numel(ids)~=numel(names) || any(~isfinite(ids)) || numel(unique(ids))~=numel(ids)
                error('NMDataIOROIDirectTools:CAT12Identity','CAT12 atlas %s in %s has invalid or duplicate ROI identity.',name,fileName);
            end
        end

        function [files,labels,names,sizes,messages] = classFilesAndLabels(classLists)
            files={}; labels=zeros(0,1); names={}; sizes=[]; messages=NMDataIOMessageTools.emptyMessages();
            if isempty(classLists)
                messages=NMDataIOMessageTools.make('danger',true,'roi.labels.implicit','Implicit ROI label mode requires class-specific CAT12 file lists.',1,'red*'); return;
            end
            n=numel(classLists); names=cell(1,n); sizes=zeros(1,n);
            for ii=1:n
                if iscell(classLists), g=classLists{ii}; else, g=classLists(ii); end
                if ~isstruct(g) || ~isscalar(g)
                    messages=NMDataIOMessageTools.make('danger',true,'roi.labels.classList','Each implicit ROI class list must be one struct with name and files.',1,'red*'); return;
                end
                gf=NMDataIOROIDirectTools.asCellstr(NMDataIOROIDirectTools.value(g,{'files','roiFiles'},{}));
                if isempty(gf)
                    messages=NMDataIOMessageTools.make('danger',true,'roi.labels.emptyClass',sprintf('Implicit ROI class %g contains no CAT12 files.',ii),1,'red*'); return;
                end
                names{ii}=NMDataIOROIDirectTools.text(g,{'name'},sprintf('Class_%g',ii));
                sizes(ii)=numel(gf); files=[files gf]; labels=[labels;repmat(ii,numel(gf),1)]; %#ok<AGROW>
            end
            if numel(unique(files))~=numel(files)
                messages=NMDataIOMessageTools.make('danger',true,'roi.labels.duplicateFile','A CAT12 ROI subject file appears in more than one implicit classification list.',1,'red*');
            end
        end

        function [ids,messages] = caseIDs(spec,n,files)
            ids={}; messages=NMDataIOMessageTools.emptyMessages();
            if ~isempty(files) && strcmp(spec.caseIDMode,'legacy_spm')
                [ids,idMessages]=NMDataIOImportTools.deriveCaseIDsFromFiles(files,'legacy_spm','roiCaseIDs');
                messages=[messages;idMessages];
                if NMDataIOMessageTools.hasFatal(idMessages)
                    txt={idMessages.text}; txt=txt(~cellfun(@isempty,txt));
                    error('NMDataIOROIDirectTools:CaseIDDerivation','%s',strjoin(txt,' | '));
                end
            else
                ids=spec.caseIDs;
                if isempty(ids) && isfield(spec,'caseIDsVariable') && ~isempty(spec.caseIDsVariable)
                    raw=NMDataIOROIDirectTools.workspace(spec.caseIDsVariable);
                    if isstring(raw), ids=cellstr(raw(:));
                    elseif iscell(raw), ids=cellfun(@(x)char(string(x)),raw(:),'UniformOutput',false);
                    elseif ischar(raw), ids=cellstr(raw);
                    elseif isnumeric(raw), ids=arrayfun(@(x)char(string(x)),raw(:),'UniformOutput',false);
                    else, error('NMDataIOROIDirectTools:CaseIDType','ROI case-ID variable must resolve to text, cell, or numeric identifiers.'); end
                end
                if isempty(ids)
                    if ~isempty(files)
                        error('NMDataIOROIDirectTools:CaseIDsRequired','Explicit ROI case-ID mode requires one case-ID variable matching the file list.');
                    end
                    error('NMDataIOROIDirectTools:CaseIDsRequired','Direct ROI matrix import requires explicit case IDs.');
                end
            end
            ids=cellfun(@(x)char(string(x)),ids(:),'UniformOutput',false);
            if any(cellfun(@isempty,ids)) || numel(unique(ids))~=numel(ids)
                error('NMDataIOROIDirectTools:CaseIDIdentity','Direct ROI import case IDs must be non-empty and unique.');
            end
            if numel(ids)~=n, error('NMDataIOROIDirectTools:CaseIDCount','Direct ROI import has %g case IDs for %g rows.',numel(ids),n); end
        end

        function v = workspace(name)
            name=strtrim(char(string(name))); if isempty(name), v=[]; return; end
            if ~isvarname(name), error('NMDataIOROIDirectTools:WorkspaceVariable','Invalid MATLAB workspace variable name: %s.',name); end
            try, v=evalin('base',name); catch ME, error('NMDataIOROIDirectTools:WorkspaceVariable','Could not resolve workspace variable %s: %s',name,ME.message); end
        end

        function out = emptyPayload()
            out=struct('ok',false,'Y',[],'Yw',[],'weightingProvenance',struct(),'caseIDs',{{}},'featnames',{{}},'label',[],'desc_groups',{{}},'covars',[],'covnames',{{}}, ...
                'roiProvenance',NMDataIOROIProvenanceTools.template(),'globalVolumeCorrection',struct(),'sourceMetadata',struct(),'importReport',struct());
        end

        function v = value(s,names,defaultValue)
            v=defaultValue; for ii=1:numel(names), if isfield(s,names{ii}) && ~isempty(s.(names{ii})), v=s.(names{ii}); return; end, end
        end
        function t = text(s,names,defaultValue), v=NMDataIOROIDirectTools.value(s,names,defaultValue); t=strtrim(char(string(v))); end
        function c = cells(s,names), c=NMDataIOROIDirectTools.asCellstr(NMDataIOROIDirectTools.value(s,names,{})); end
        function c = asCellstr(v)
            if isempty(v), c={}; elseif ischar(v), c=cellstr(v); elseif isstring(v), c=cellstr(v(:)); elseif iscell(v), c=cellfun(@(x)char(string(x)),v(:),'UniformOutput',false); else, c=cellstr(string(v(:))); end; c=c(:)';
        end
        function txt = shortNumericList(v,nMax)
            v=double(v(:)'); k=min(numel(v),nMax); p=arrayfun(@(x)sprintf('%0.15g',x),v(1:k),'UniformOutput',false); txt=strjoin(p,', '); if numel(v)>k, txt=[txt ', ...']; end
        end
    end
end
