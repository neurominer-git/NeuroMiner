classdef NMModalityInfoTools
% NMModalityInfoTools
% -------------------------------------------------------------------------
% Purpose:
%   Lightweight modality-metadata authority for browser/API consumers and persisted import summaries.
%
% Contract:
%   Read existing NM/datadescriptor/input_settings metadata safely; prefer persisted
%   input_settings.modalityInfo when present; derive only facts supported by in-memory containers or
%   cached import metadata; represent unknown facts as []/NaN rather than false; and write canonical
%   import-time modalityInfo for TransferModality2NM.
%
% Persistence:
%   Import-time modalityInfo is stored in NM.datadescriptor{i}.input_settings.modalityInfo.
% -------------------------------------------------------------------------

    methods (Static)
        function info = emptyInfo()
            % emptyInfo  Return the canonical lightweight modality-info schema.
            %
            %   info = NMModalityInfoTools.emptyInfo() returns a scalar struct
            %   with all supported metadata fields initialized to unknown/empty
            %   values. It has no side effects.

            info = struct();
            info.schemaVersion = 1;
            info.createdBy = 'NMModalityInfoTools';
            info.createdAt = '';
            info.modalityIndex = NaN;
            info.label = '';
            info.description = '';
            info.datasource = 'unknown';
            info.source = 'unknown';
            info.sourceType = 'unknown';
            info.sourceTypeLabel = 'Unknown';
            info.typeCode = NaN;
            info.isImaging = [];
            info.isSurface = [];
            info.storageMode = 'unknown';
            info.externalPath = '';
            info.externalBasename = '';
            info.externalFileExists = [];
            info.externalCompatibilityHash = '';
            info.externalHashVersion = NaN;
            info.nSubjects = NaN;
            info.nObservedCases = NaN;
            info.nAlignedCases = NaN;
            info.nFeatures = NaN;
            info.matrixClass = '';
            info.hasMissing = [];              % Compatibility alias for NaN missingness
            info.missingnessKnown = false;
            info.nMissing = NaN;               % Compatibility alias for nNaN
            info.missingFraction = NaN;        % Compatibility alias for nanFraction
            info.hasNaN = [];
            info.nNaN = NaN;
            info.nanFraction = NaN;
            info.hasInf = [];
            info.nInf = NaN;
            info.infFraction = NaN;
            info.hasNonFinite = [];
            info.nNonFinite = NaN;
            info.nonFiniteFraction = NaN;
            info.nSubjectsWithNaN = NaN;
            info.nFeaturesWithNaN = NaN;
            info.maxNaNBySubject = NaN;
            info.maxNaNByFeature = NaN;
            info.nRawSubjects = NaN;
            info.nRawFeatures = NaN;
            info.nSelectedSubjects = NaN;
            info.nSelectedFeatures = NaN;
            info.featureNamesAvailable = [];
            info.nFeatureNames = NaN;
            info.badcoordsAvailable = [];
            info.badcoordsLength = NaN;
            info.badcoordsCount = NaN;           % Number of omitted coordinates/features (badcoords ~= 0)
            info.nValidCoords = NaN;             % Number of valid coordinates/features (badcoords == 0)
            info.maskAvailable = [];
            info.maskPath = '';
            info.maskBasename = '';
            info.maskSummary = '';
            info.sourceFilesKnown = [];
            info.nSourceFiles = NaN;
            info.metadataCompleteness = 'unknown';
            info.completenessScore = NaN;
            info.requiresRecommit = false;
            info.featureStats = NMDataIOFeatureStatsTools.emptyStats();
            info.caseAlignment = struct();
            info.missingCasesFilledWithNaN = false;
            info.nMissingCasesFilledWithNaN = 0;
            info.missingCasesFilledWithNaNIDs = {};
            info.requiresEarlyFusionImputation = false;
            info.imputationRequiredForEarlyFusionOOCV = false;
            info.earlyFusionImputationReason = '';
            info.diagnostics = {};
        end

        function info = fromNM(NM, varind, opts)
            % fromNM  Read cached and lightweight inferred metadata for one NM modality.
            %
            % info = NMModalityInfoTools.fromNM(NM,varind,opts) reads
            % NM.datadescriptor{varind}.input_settings.modalityInfo when
            % available, supplements it with lightweight NM fields, and avoids
            % loading external feature containers. opts.ScanInMemory controls
            % whether in-memory numeric feature matrices are scanned.
            %
            % opts.MaxScanElements: configures optional max scan elements behavior for this call.
            %
            % opts.ScanInMemory: when true, scan in-memory numeric NM.Y matrices for lightweight feature statistics; external containers are not loaded.

            if nargin < 3 || isempty(opts), opts = struct(); end
            scanInMemory = NMModalityInfoTools.getOpt(opts, 'ScanInMemory', true);
            maxScanElements = NMModalityInfoTools.getOpt(opts, 'MaxScanElements', Inf);

            info = NMModalityInfoTools.emptyInfo();
            info.modalityIndex = double(varind);
            diagnostics = {};

            dd = struct();
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= varind && ...
                    ~isempty(NM.datadescriptor{varind}) && isstruct(NM.datadescriptor{varind})
                dd = NM.datadescriptor{varind};
            end

            input = struct();
            if isfield(dd,'input_settings') && isstruct(dd.input_settings)
                input = dd.input_settings;
                if isfield(input,'modalityInfo') && isstruct(input.modalityInfo)
                    info = NMModalityInfoTools.mergeKnown(info, input.modalityInfo);
                end
                if isfield(input,'requiresRecommit') && isequal(input.requiresRecommit,true)
                    info.requiresRecommit = true;
                end
            end

            if isfield(dd,'desc') && ~isempty(dd.desc)
                info.label = NMModalityInfoTools.asChar(dd.desc);
                info.description = info.label;
            elseif isfield(dd,'description') && ~isempty(dd.description)
                info.label = NMModalityInfoTools.asChar(dd.description);
                info.description = info.label;
            elseif isfield(input,'desc_data') && ~isempty(input.desc_data)
                info.label = NMModalityInfoTools.asChar(input.desc_data);
                info.description = info.label;
            elseif isempty(info.label)
                info.label = sprintf('Modality %d', varind);
                info.description = info.label;
            end

            if isfield(input,'datasource') && ~isempty(input.datasource)
                info.datasource = lower(NMModalityInfoTools.asChar(input.datasource));
            end
            if isfield(dd,'source') && ~isempty(dd.source)
                info.source = lower(NMModalityInfoTools.asChar(dd.source));
            end
            if isfield(dd,'type') && ~isempty(dd.type) && isnumeric(dd.type)
                info.typeCode = double(dd.type(1));
            end
            groupmode = 1;
            if isfield(input,'groupmode') && ~isempty(input.groupmode), groupmode = input.groupmode; end
            if isfield(input,'sourceType') && ~isempty(input.sourceType)
                info.sourceType = NMDataIOStateTools.normalizeSourceType(input.sourceType,groupmode);
            elseif strcmp(info.source,'connectivity')
                info.sourceType = 'connectivity';
            elseif strcmp(info.datasource,'surf')
                info.sourceType = 'surface-list';
            elseif any(strcmp(info.datasource,{'nifti','spm','image'})) || strcmp(info.source,'image')
                info.sourceType = 'image-list';
            elseif isfield(input,'groupmode') && ~isempty(input.groupmode)
                info.sourceType = NMDataIOStateTools.normalizeSourceType('',groupmode);
            end
            info.sourceTypeLabel = NMDataIOStateTools.sourceTypeLabel(info.sourceType);

            [Y, hasY] = NMModalityInfoTools.getCellField(NM, 'Y', varind);
            hasCommittedFeatureData = hasY && ~isempty(Y);
            if hasY
                if isnumeric(Y) || islogical(Y)
                    info.storageMode = 'memory';
                    info.matrixClass = class(Y);
                    if ismatrix(Y)
                        info.nSubjects = double(size(Y,1));
                        info.nFeatures = double(size(Y,2));
                    else
                        sz = size(Y);
                        info.nSubjects = double(sz(1));
                        info.nFeatures = double(prod(sz(2:end)));
                    end
                    if scanInMemory
                        info = NMDataIOFeatureStatsTools.applyToInfo(info, Y, opts);
                    elseif ~info.missingnessKnown
                        info = NMModalityInfoTools.setMissingnessUnknown(info);
                        diagnostics{end+1} = sprintf('Missingness was not scanned because in-memory feature-stat scanning is disabled for NM.Y{%d}.', varind); %#ok<AGROW>
                    end
                elseif ischar(Y) || isstring(Y)
                    info.storageMode = 'external';
                    info.externalPath = char(Y);
                    info.externalBasename = NMModalityInfoTools.basename(char(Y));
                    info.externalFileExists = exist(info.externalPath,'file') == 2;
                    if ~info.missingnessKnown
                        info = NMModalityInfoTools.setMissingnessUnknown(info);
                        diagnostics{end+1} = 'Feature data are externalized; missingness was not inspected during UI-state export.'; %#ok<AGROW>
                    end
                else
                    info.storageMode = 'unknown';
                    diagnostics{end+1} = sprintf('NM.Y{%d} has unsupported class for lightweight metadata: %s.', varind, class(Y)); %#ok<AGROW>
                end
            else
                diagnostics{end+1} = sprintf('NM.Y{%d} is unavailable.', varind); %#ok<AGROW>
            end

            if isnan(info.nSubjects)
                info.nSubjects = NMModalityInfoTools.inferSubjectCount(NM, input);
            end
            if isnan(info.nFeatures)
                info.nFeatures = NMModalityInfoTools.inferFeatureCount(NM, input, varind);
            end

            inputSubjectCount = NaN;
            if isfield(input,'n_subjects') && ~isempty(input.n_subjects) && isnumeric(input.n_subjects)
                inputSubjectCount = NMModalityInfoTools.subjectCountFromInputVector(input.n_subjects);
            elseif isfield(input,'n_samples') && ~isempty(input.n_samples) && isnumeric(input.n_samples)
                inputSubjectCount = NMModalityInfoTools.subjectCountFromInputVector(input.n_samples);
            end
            if ~isnan(inputSubjectCount)
                if ~hasY || isnan(info.nSubjects)
                    info.nSubjects = double(inputSubjectCount);
                elseif double(info.nSubjects) ~= double(inputSubjectCount)
                    diagnostics{end+1} = sprintf(['Imported data contain %g case(s), while the saved import settings report %g; ', ...
                        'the imported data count is shown in the modality overview.'], double(info.nSubjects), double(inputSubjectCount)); %#ok<AGROW>
                end
            end

            [featnames, hasFeatNames] = NMModalityInfoTools.getCellField(NM, 'featnames', varind);
            if hasFeatNames && ~isempty(featnames)
                info.featureNamesAvailable = true;
                if iscell(featnames) || isstring(featnames)
                    info.nFeatureNames = double(numel(featnames));
                elseif ischar(featnames)
                    info.nFeatureNames = double(size(featnames,1));
                else
                    info.nFeatureNames = double(numel(featnames));
                end
                if isnan(info.nFeatures)
                    info.nFeatures = info.nFeatureNames;
                end
            elseif isfield(input,'featnames') && ~isempty(input.featnames)
                info.featureNamesAvailable = true;
                info.nFeatureNames = double(numel(input.featnames));
            else
                info.featureNamesAvailable = false;
                info.nFeatureNames = 0;
            end

            [badcoords, hasBadcoords] = NMModalityInfoTools.getCellField(NM, 'badcoords', varind);
            if hasBadcoords && ~isempty(badcoords)
                info = NMModalityInfoTools.applyBadcoordsInfo(info, badcoords);
                if isnan(info.nFeatures) && isfield(info,'nValidCoords') && ...
                        isnumeric(info.nValidCoords) && isscalar(info.nValidCoords) && ~isnan(info.nValidCoords)
                    info.nFeatures = double(info.nValidCoords);
                end
            elseif isfield(input,'badcoords') && ~isempty(input.badcoords)
                info = NMModalityInfoTools.applyBadcoordsInfo(info, input.badcoords);
                if isnan(info.nFeatures) && isfield(info,'nValidCoords') && ...
                        isnumeric(info.nValidCoords) && isscalar(info.nValidCoords) && ~isnan(info.nValidCoords)
                    info.nFeatures = double(info.nValidCoords);
                end
            else
                info.badcoordsAvailable = false;
            end

            [brainmask, hasBrainmask] = NMModalityInfoTools.getCellField(NM, 'brainmask', varind);
            if hasBrainmask && ~isempty(brainmask)
                info.maskAvailable = true;
                if ischar(brainmask) || isstring(brainmask)
                    info.maskPath = char(brainmask);
                    info.maskBasename = NMModalityInfoTools.basename(char(brainmask));
                    info.maskSummary = info.maskBasename;
                elseif isnumeric(brainmask) || islogical(brainmask)
                    info.maskSummary = sprintf('in-memory mask [%s]', NMModalityInfoTools.sizeString(size(brainmask)));
                    if isnan(info.nFeatures)
                        try, info.nFeatures = double(nnz(brainmask)); catch, end
                    end
                else
                    info.maskSummary = sprintf('mask class %s', class(brainmask));
                end
            elseif isfield(input,'brainmask') && ~isempty(input.brainmask)
                info.maskAvailable = true;
                info.maskPath = NMModalityInfoTools.asChar(input.brainmask);
                info.maskBasename = NMModalityInfoTools.basename(info.maskPath);
                info.maskSummary = info.maskBasename;
            else
                info.maskAvailable = false;
            end

            [files, hasFiles] = NMModalityInfoTools.getCellField(NM, 'files', varind);
            if hasFiles && ~isempty(files)
                info.sourceFilesKnown = true;
                info.nSourceFiles = double(NMModalityInfoTools.safeRowCount(files));
            elseif isfield(input,'PP') && ~isempty(input.PP)
                info.sourceFilesKnown = true;
                info.nSourceFiles = double(NMModalityInfoTools.safeRowCount(input.PP));
            elseif isfield(input,'P') && ~isempty(input.P)
                info.sourceFilesKnown = true;
                info.nSourceFiles = double(NMModalityInfoTools.safeRowCount(input.P));
            else
                info.sourceFilesKnown = false;
                info.nSourceFiles = NaN;
            end

            info = NMModalityInfoTools.normalizeMissingnessAliases(info);
            info = NMModalityInfoTools.deriveCaseCountAliases(info);
            info.isSurface = NMModalityInfoTools.deriveIsSurface(info);
            info.isImaging = NMModalityInfoTools.deriveIsImaging(info);
            if isempty(info.source) || strcmp(info.source,'unknown')
                if isequal(info.isImaging,true), info.source = 'image';
                elseif strcmp(info.storageMode,'memory') || strcmp(info.datasource,'matrix'), info.source = 'matrix';
                end
            end

            info = NMModalityInfoTools.checkBadcoordsConsistency(info);
            info = NMModalityInfoTools.finalizeCompleteness(info);
            if isequal(info.requiresRecommit, true)
                info.metadataCompleteness = 'incomplete';
                info.completenessScore = min(info.completenessScore, 0.69);
                diagnostics{end+1} = sprintf('Modality %d is under modification and requires Preview/QC and Commit before it is complete.', varind); %#ok<AGROW>
            end
            if hasCommittedFeatureData && isfield(info,'diagnostics') && ~isempty(info.diagnostics)
                cachedDiagnostics = NMModalityInfoTools.asCell(info.diagnostics);
                retainedDiagnostics = {};
                for d = 1:numel(cachedDiagnostics)
                    msg = NMModalityInfoTools.asChar(cachedDiagnostics{d});
                    msgLower = lower(msg);
                    if contains(msgLower, 'feature data have not been committed') || ...
                            contains(msgLower, 'incomplete imaging dataio import contract') || ...
                            contains(msgLower, 'incomplete dataio import contract')
                        continue;
                    end
                    retainedDiagnostics{end+1} = msg; %#ok<AGROW>
                end
                info.diagnostics = retainedDiagnostics;
            end
            diagAll = [NMModalityInfoTools.asCell(info.diagnostics), diagnostics];
            for d = 1:numel(diagAll)
                diagAll{d} = NMModalityInfoTools.asChar(diagAll{d});
            end
            diagAll = diagAll(~cellfun(@isempty, diagAll));
            info.diagnostics = unique(diagAll, 'stable');
        end

        function tf = isImaging(NM, varind)
            % isImaging  Return canonical imaging status for one modality.
            %
            % Current NM2 metadata wins when present. Otherwise use the
            % inherited descriptor type written by TransferModality2NM:
            % 0 = matrix, 1 = volumetric image, 2 = surface image.
            dd = NMModalityInfoTools.modalityDescriptor(NM, varind);
            if ~isempty(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings) && ...
                    isfield(dd.input_settings,'modalityInfo') && isstruct(dd.input_settings.modalityInfo) && ...
                    isfield(dd.input_settings.modalityInfo,'isImaging') && ~isempty(dd.input_settings.modalityInfo.isImaging)
                value = dd.input_settings.modalityInfo.isImaging;
                if ~(islogical(value) && isscalar(value))
                    error('NMModalityInfoTools:invalidImagingStatus', ...
                        'modalityInfo.isImaging for modality %d must be a scalar logical.', varind);
                end
                tf = value;
                return;
            end
            if ~isempty(dd) && isfield(dd,'type') && ~isempty(dd.type)
                typeCode = dd.type;
                if ~(isnumeric(typeCode) && isscalar(typeCode) && isfinite(typeCode) && ismember(double(typeCode),[0 1 2]))
                    error('NMModalityInfoTools:invalidTypeCode', ...
                        'NM.datadescriptor{%d}.type must be one of 0, 1, or 2.', varind);
                end
                tf = double(typeCode) > 0;
                return;
            end
            [Y, hasY] = NMModalityInfoTools.getCellField(NM, 'Y', varind);
            if hasY && ~isempty(Y)
                error('NMModalityInfoTools:unknownImagingStatus', ...
                    'Imaging status is unresolved for committed modality %d.', varind);
            end
            tf = false;
        end

        function info = preprocContextInfo(NM, varind)
            % preprocContextInfo  Return only modality facts required by preprocessing configuration.
            %
            % This focused query avoids constructing the full DataIO overview. Current NM2
            % modalityInfo metadata is authoritative when data are external; resident NM.Y
            % dimensions are read directly because they are the committed in-memory payload.
            info = struct('isImaging',NMModalityInfoTools.isImaging(NM,varind), ...
                'nSubjects',NaN,'nFeatures',NaN,'storageMode','unknown','datasource','unknown');
            dd = NMModalityInfoTools.modalityDescriptor(NM, varind);
            input = struct();
            if ~isempty(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings)
                input = dd.input_settings;
                if isfield(input,'modalityInfo') && isstruct(input.modalityInfo)
                    cached = input.modalityInfo;
                    info.nSubjects = NMModalityInfoTools.cachedCount(cached,'nSubjects',varind);
                    info.nFeatures = NMModalityInfoTools.cachedCount(cached,'nFeatures',varind);
                    if isfield(cached,'storageMode') && ~isempty(cached.storageMode)
                        info.storageMode = NMModalityInfoTools.storageModeToken(cached.storageMode,varind);
                    end
                    if isfield(cached,'datasource') && ~isempty(cached.datasource)
                        info.datasource = NMModalityInfoTools.textToken(cached.datasource,'datasource',varind);
                    end
                end
                if strcmp(info.datasource,'unknown') && isfield(input,'datasource') && ~isempty(input.datasource)
                    info.datasource = NMModalityInfoTools.textToken(input.datasource,'datasource',varind);
                end
            end

            [Y, hasY] = NMModalityInfoTools.getCellField(NM, 'Y', varind);
            if hasY && ~isempty(Y)
                if isnumeric(Y) || islogical(Y)
                    if ~ismatrix(Y)
                        error('NMModalityInfoTools:invalidFeatureMatrix', ...
                            'NM.Y{%d} must be a two-dimensional feature matrix.', varind);
                    end
                    info.storageMode = 'memory';
                    info.nSubjects = double(size(Y,1));
                    info.nFeatures = double(size(Y,2));
                elseif ischar(Y) || (isstring(Y) && isscalar(Y))
                    info.storageMode = 'external';
                else
                    error('NMModalityInfoTools:unsupportedFeatureStorage', ...
                        'NM.Y{%d} has unsupported storage type %s.', varind, class(Y));
                end
            end
        end

        function tf = predictorNaNStatus(NM, varind, maxScanElements)
            % predictorNaNStatus  Return true/false/unknown NaN status without full feature statistics.
            if nargin < 3, maxScanElements = 1e7; end
            dd = NMModalityInfoTools.modalityDescriptor(NM, varind);
            if ~isempty(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings) && ...
                    isfield(dd.input_settings,'modalityInfo') && isstruct(dd.input_settings.modalityInfo)
                info = dd.input_settings.modalityInfo;
                if isfield(info,'missingnessKnown') && isequal(info.missingnessKnown,true)
                    if ~isfield(info,'hasNaN') || ~(islogical(info.hasNaN) && isscalar(info.hasNaN))
                        error('NMModalityInfoTools:invalidMissingness', ...
                            'Known missingness for modality %d lacks a scalar logical hasNaN value.', varind);
                    end
                    tf = info.hasNaN;
                    return;
                end
            end
            [Y, hasY] = NMModalityInfoTools.getCellField(NM, 'Y', varind);
            if ~hasY || isempty(Y)
                tf = false;
            elseif ~(isnumeric(Y) || islogical(Y)) || numel(Y) > maxScanElements
                tf = [];
            else
                tf = any(isnan(Y(:)));
            end
        end

        function state = overviewState(NM, opts)
            % overviewState  Build a lightweight modality overview for browser/API consumers.
            %
            %   state = NMModalityInfoTools.overviewState(NM,opts) returns
            %   modalityInfo entries and aggregate summary information without
            %   transferring full feature matrices across the browser bridge.

            if nargin < 2 || isempty(opts), opts = struct(); end
            n = NMModalityInfoTools.numModalities(NM);
            infos = repmat(NMModalityInfoTools.emptyInfo(), 1, max(1,n));
            if n == 0
                infos = NMModalityInfoTools.emptyInfo();
                infos = infos([]);
            else
                for i = 1:n
                    infos(i) = NMModalityInfoTools.fromNM(NM, i, opts);
                end
            end
            state = struct();
            state.kind = 'dataio-overview';
            state.phase = 'E-modality-management-overview';
            state.title = 'NeuroMiner DataIO overview';
            state.numModalities = double(n);
            state.modalityInfo = infos;
            state.summary = NMModalityInfoTools.summaryFromInfos(infos);
            state.workspaceSummary = NMDataIOLabelStatsTools.summarizeWorkspace(NM);
            state.labelSummary = state.workspaceSummary;
            state.totalSubjects = state.workspaceSummary.nCases;
            state.totalCases = state.workspaceSummary.nCases;
            state.totalFeatures = state.summary.totalFeatures;
            state.nExternalized = state.summary.numExternal;
            % Do not surface internal implementation notes as user-facing
            % overview messages.  The general message strip is reserved for
            % actionable diagnostics, warnings, errors, and operation results.
            state.messages = {};
        end

        function n = numModalities(NM)
            % numModalities  Return the number of committed NM modalities visible from metadata.
            %
            %   n = NMModalityInfoTools.numModalities(NM) inspects NM.Y and
            %   NM.datadescriptor and returns the largest committed modality
            %   count. The method is read-only.

            n = 0;
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = max(n, numel(NM.Y));
            end
            if isstruct(NM) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor)
                n = max(n, numel(NM.datadescriptor));
            end
        end

        function state = sanitizeStateForUI(state)
            % sanitizeStateForUI  Remove path-heavy or bridge-unsafe fields from modality overview state.
            %
            % state = NMModalityInfoTools.sanitizeStateForUI(state) returns a
            % copy suitable for JSON/browser transfer. Full external paths are
            % withheld unless specifically represented as basenames.
            %
            % state.modalityInfo: carries the modality info value between browser/API state and legacy NeuroMiner structures.

            if isfield(state,'modalityInfo')
                for i = 1:numel(state.modalityInfo)
                    state.modalityInfo(i) = NMModalityInfoTools.sanitizeInfoForUI(state.modalityInfo(i));
                end
            end
        end

        function info = sanitizeInfoForUI(info)
            % sanitizeInfoForUI  Sanitize a single modality-info struct for browser transfer.
            %
            %   info = NMModalityInfoTools.sanitizeInfoForUI(info) removes or
            %   truncates fields that are path-heavy, large, or not actionable in
            %   the UI. The method does not alter NM.

            if isfield(info,'externalPath') && ~isempty(info.externalPath)
                info.externalPath = ''; % expose basename by default only
            end
            if isfield(info,'maskPath') && ~isempty(info.maskPath)
                info.maskPath = '';
            end
        end

        function lines = summaryLines(info)
            % summaryLines  Format canonical modalityInfo as concise user-facing lines.
            % The sole caller supplies NMModalityInfoTools.fromNM output.
            lines = {};
            if ~isempty(info.label)
                lines{end+1} = ['Description: ' info.label]; %#ok<AGROW>
            end

            typeLabel = 'matrix/table';
            if isequal(info.isSurface,true)
                typeLabel = 'surface/vertex';
            elseif isequal(info.isImaging,true)
                typeLabel = 'image/voxel';
            elseif isfinite(info.typeCode)
                switch round(info.typeCode)
                    case 1, typeLabel = 'image/voxel';
                    case 2, typeLabel = 'surface/vertex';
                end
            end
            lines{end+1} = sprintf('Type: %s; data source: %s; input: %s; format: %s', ...
                typeLabel, info.sourceTypeLabel, info.datasource, info.source); %#ok<AGROW>

            dims = {};
            if isfinite(info.nSubjects)
                dims{end+1} = sprintf('%g subjects', info.nSubjects); %#ok<AGROW>
            end
            if isfinite(info.nObservedCases)
                dims{end+1} = sprintf('%g observed cases', info.nObservedCases); %#ok<AGROW>
            end
            if isfinite(info.nFeatures)
                dims{end+1} = sprintf('%g features', info.nFeatures); %#ok<AGROW>
            elseif isfinite(info.nValidCoords)
                dims{end+1} = sprintf('%g valid coordinates/features', info.nValidCoords); %#ok<AGROW>
            end
            if ~isempty(dims), lines{end+1} = ['Dimensions: ' strjoin(dims, '; ')]; end %#ok<AGROW>

            if ~isempty(info.externalBasename)
                lines{end+1} = sprintf('Storage: %s (%s)', info.storageMode, info.externalBasename); %#ok<AGROW>
            else
                lines{end+1} = sprintf('Storage: %s', info.storageMode); %#ok<AGROW>
            end

            if info.missingnessKnown
                miss = {};
                if isfinite(info.nNaN)
                    miss{end+1} = sprintf('%g NaN value(s)', info.nNaN); %#ok<AGROW>
                end
                if isfinite(info.nanFraction)
                    miss{end+1} = sprintf('%.3g%% of matrix', 100*info.nanFraction); %#ok<AGROW>
                end
                if isfinite(info.nSubjectsWithNaN)
                    miss{end+1} = sprintf('%g subject(s) affected', info.nSubjectsWithNaN); %#ok<AGROW>
                end
                if isempty(miss)
                    lines{end+1} = 'Missingness: scanned; no detailed counts available.'; %#ok<AGROW>
                else
                    lines{end+1} = ['Missingness: ' strjoin(miss, '; ')]; %#ok<AGROW>
                end
            else
                lines{end+1} = 'Missingness: not scanned in this lightweight overview.'; %#ok<AGROW>
            end

            if info.missingCasesFilledWithNaN
                lines{end+1} = sprintf('Case alignment: %g missing case(s) were filled with NaN.', ...
                    info.nMissingCasesFilledWithNaN); %#ok<AGROW>
            end
            if info.requiresEarlyFusionImputation
                reason = '';
                if ~isempty(info.earlyFusionImputationReason)
                    reason = [' because ' info.earlyFusionImputationReason];
                end
                lines{end+1} = ['Imputation: required for early-fusion use' reason]; %#ok<AGROW>
            end
            if ~isempty(info.maskSummary)
                lines{end+1} = ['Mask/space: ' info.maskSummary]; %#ok<AGROW>
            end
            if isfinite(info.nSourceFiles) && info.nSourceFiles > 0
                lines{end+1} = sprintf('Source files: %g', info.nSourceFiles); %#ok<AGROW>
            end
        end

        function info = fromImportIO(I, NM, varind, Y, opts)
            % fromImportIO  Build modalityInfo during a controlled DataIO commit.
            %
            % info = NMModalityInfoTools.fromImportIO(I,NM,varind,Y,opts)
            % derives cached metadata from the normalized import_settings
            % struct and the committed feature matrix or external pointer. The
            % caller stores the result in input_settings.modalityInfo.
            %
            % fromImportIO
            % Build clean lightweight metadata at the point of legacy DataIO
            % import, when the feature matrix for this modality is already in
            % memory. This method does not retain I.Y and does not load any
            % external feature container.
            %
            % opts.MaxStatElements: configures optional max stat elements behavior for this call.
            % opts.ModalityCounter: configures optional modality counter behavior for this call.
            if nargin < 5 || isempty(opts), opts = struct(); end
            if nargin < 4, Y = []; end
            if nargin < 3 || isempty(varind), varind = 1; end
            if nargin < 2 || isempty(NM), NM = struct(); end

            scanOpts = struct('ScanInMemory', false, 'MaxScanElements', NMModalityInfoTools.getOpt(opts, 'MaxStatElements', Inf));
            info = NMModalityInfoTools.fromNM(NM, varind, scanOpts);
            info.schemaVersion = 1;
            info.createdBy = 'TransferModality2NM';
            info.createdAt = datestr(now, 30);
            info.modalityIndex = double(varind);

            if isstruct(I)
                if isfield(I,'datasource') && ~isempty(I.datasource)
                    info.datasource = lower(NMModalityInfoTools.asChar(I.datasource));
                end
                if isfield(I,'sourceType') && ~isempty(I.sourceType)
                    groupmode = 1;
                    if isfield(I,'groupmode') && ~isempty(I.groupmode), groupmode = I.groupmode; end
                    info.sourceType = NMDataIOStateTools.normalizeSourceType(I.sourceType,groupmode);
                    info.sourceTypeLabel = NMDataIOStateTools.sourceTypeLabel(info.sourceType);
                end
                if isfield(I,'desc_data') && ~isempty(I.desc_data)
                    if isempty(info.label) || startsWith(info.label, 'Modality ')
                        info.label = NMModalityInfoTools.asChar(I.desc_data);
                    end
                    if isempty(info.description)
                        info.description = NMModalityInfoTools.asChar(I.desc_data);
                    end
                end
                if isfield(I,'n_samples') && isnumeric(I.n_samples) && ~isempty(I.n_samples)
                    info.nRawSubjects = double(I.n_samples(1));
                elseif isfield(I,'ID') && ~isempty(I.ID)
                    try, info.nRawSubjects = double(size(I.ID,1)); catch, end
                end
            end

            if ~isempty(Y) && (isnumeric(Y) || islogical(Y))
                info.nSelectedSubjects = double(size(Y,1));
                if ismatrix(Y)
                    info.nSelectedFeatures = double(size(Y,2));
                else
                    sz = size(Y);
                    info.nSelectedFeatures = double(prod(sz(2:end)));
                end
                info.nSubjects = info.nSelectedSubjects;
                info.nFeatures = info.nSelectedFeatures;
                info.storageMode = 'memory';
                info.matrixClass = class(Y);
                info = NMDataIOFeatureStatsTools.applyToInfo(info, Y, opts);
            end

            if isstruct(I) && isfield(I,'Y') && ~isempty(I.Y)
                try
                    if iscell(I.Y)
                        cnt = NMModalityInfoTools.getOpt(opts, 'ModalityCounter', 1);
                        if cnt <= numel(I.Y) && ~isempty(I.Y{cnt})
                            info.nRawSubjects = double(size(I.Y{cnt},1));
                            if ismatrix(I.Y{cnt})
                                info.nRawFeatures = double(size(I.Y{cnt},2));
                            else
                                sz = size(I.Y{cnt});
                                info.nRawFeatures = double(prod(sz(2:end)));
                            end
                        end
                    elseif isnumeric(I.Y) || islogical(I.Y)
                        info.nRawSubjects = double(size(I.Y,1));
                        if ismatrix(I.Y)
                            info.nRawFeatures = double(size(I.Y,2));
                        else
                            sz = size(I.Y);
                            info.nRawFeatures = double(prod(sz(2:end)));
                        end
                    end
                catch
                end
            end

            info = NMModalityInfoTools.normalizeMissingnessAliases(info);
            info = NMModalityInfoTools.deriveCaseCountAliases(info);
            info = NMModalityInfoTools.finalizeCompleteness(info);
        end

        function info = scanNumericMissingness(info, Y)
            % scanNumericMissingness  Compute case/feature missingness metrics from a numeric modality matrix.
            %
            % Info, Y -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            info = NMDataIOFeatureStatsTools.applyToInfo(info, Y, struct('MaxStatElements', Inf));
            info = NMModalityInfoTools.normalizeMissingnessAliases(info);
            info = NMModalityInfoTools.deriveCaseCountAliases(info);
        end

        function info = setMissingnessUnknown(info)
            % setMissingnessUnknown  Mark missingness statistics as unknown when data are unavailable or too large.
            %
            % Info -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            info.hasMissing = [];
            info.nMissing = NaN;
            info.missingFraction = NaN;
            info.hasNaN = [];
            info.nNaN = NaN;
            info.nanFraction = NaN;
            info.hasInf = [];
            info.nInf = NaN;
            info.infFraction = NaN;
            info.hasNonFinite = [];
            info.nNonFinite = NaN;
            info.nonFiniteFraction = NaN;
            info.nSubjectsWithNaN = NaN;
            info.nFeaturesWithNaN = NaN;
            info.maxNaNBySubject = NaN;
            info.maxNaNByFeature = NaN;
            info.missingnessKnown = false;
        end

        function info = normalizeMissingnessAliases(info)
            % normalizeMissingnessAliases  Synchronize legacy and UI-facing missingness field aliases.
            %
            % Info -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isfield(info,'hasNaN') && islogical(info.hasNaN) && isscalar(info.hasNaN)
                info.hasMissing = info.hasNaN;
            elseif isfield(info,'hasMissing') && islogical(info.hasMissing) && isscalar(info.hasMissing)
                info.hasNaN = info.hasMissing;
            end
            if isfield(info,'nNaN') && isnumeric(info.nNaN) && isscalar(info.nNaN) && ~isnan(info.nNaN)
                info.nMissing = info.nNaN;
            elseif isfield(info,'nMissing') && isnumeric(info.nMissing) && isscalar(info.nMissing) && ~isnan(info.nMissing)
                info.nNaN = info.nMissing;
            end
            if isfield(info,'nanFraction') && isnumeric(info.nanFraction) && isscalar(info.nanFraction) && ~isnan(info.nanFraction)
                info.missingFraction = info.nanFraction;
            elseif isfield(info,'missingFraction') && isnumeric(info.missingFraction) && isscalar(info.missingFraction) && ~isnan(info.missingFraction)
                info.nanFraction = info.missingFraction;
            end
            if isfield(info,'hasNonFinite') && islogical(info.hasNonFinite) && isscalar(info.hasNonFinite) && isequal(info.hasNonFinite,true)
                if isfield(info,'hasInf') && isequal(info.hasInf,true) && ~(isfield(info,'hasNaN') && isequal(info.hasNaN,true))
                    % Non-finite values due to Inf alone are not imputation
                    % missingness; keep hasMissing tied to NaN.
                    if ~(isfield(info,'hasNaN') && islogical(info.hasNaN))
                        info.hasNaN = false;
                        info.hasMissing = false;
                    end
                end
            end
        end

        function info = deriveCaseCountAliases(info)
            % deriveCaseCountAliases  Synchronize legacy and UI-facing case-count field aliases.
            %
            % Info -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isfield(info,'nSubjects') && isnumeric(info.nSubjects) && isscalar(info.nSubjects) && ~isnan(info.nSubjects)
                info.nAlignedCases = double(info.nSubjects);
            end
            nMissingFilled = NaN;
            if isfield(info,'missingCasesFilledWithNaN') && isequal(info.missingCasesFilledWithNaN,true) && ...
                    isfield(info,'nMissingCasesFilledWithNaN') && isnumeric(info.nMissingCasesFilledWithNaN) && isscalar(info.nMissingCasesFilledWithNaN) && ~isnan(info.nMissingCasesFilledWithNaN)
                nMissingFilled = double(info.nMissingCasesFilledWithNaN);
            elseif info.featureStats.computed && ~isnan(info.featureStats.nAllNaNCases)
                nMissingFilled = double(info.featureStats.nAllNaNCases);
            end
            if isfield(info,'nAlignedCases') && isnumeric(info.nAlignedCases) && isscalar(info.nAlignedCases) && ~isnan(info.nAlignedCases)
                if ~isnan(nMissingFilled)
                    info.nObservedCases = max(0, double(info.nAlignedCases) - nMissingFilled);
                elseif isfield(info,'nRawSubjects') && isnumeric(info.nRawSubjects) && isscalar(info.nRawSubjects) && ~isnan(info.nRawSubjects)
                    info.nObservedCases = double(info.nRawSubjects);
                else
                    info.nObservedCases = double(info.nAlignedCases);
                end
            end
        end

        function info = applyBadcoordsInfo(info, badcoords)
            % applyBadcoordsInfo  NeuroMiner convention: badcoords == 0 denotes usable.
            %
            % coordinates/features; non-zero entries denote omitted
            % coordinates/features. Count omitted entries explicitly rather
            % than reporting the vector length as the bad-coordinate count.
            info.badcoordsAvailable = true;
            try
                info.badcoordsLength = double(numel(badcoords));
            catch
                info.badcoordsLength = NaN;
            end
            if isnumeric(badcoords) || islogical(badcoords)
                try
                    omitted = badcoords ~= 0;
                    info.badcoordsCount = double(nnz(omitted));
                    info.nValidCoords = double(nnz(~omitted));
                catch
                    info.badcoordsCount = NaN;
                    info.nValidCoords = NaN;
                end
            else
                info.badcoordsCount = NaN;
                info.nValidCoords = NaN;
            end
        end

        function info = checkBadcoordsConsistency(info)
            % checkBadcoordsConsistency  Check whether bad-coordinate metadata is internally consistent with feature counts.
            %
            % Info -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if ~isfield(info,'badcoordsAvailable') || ~isequal(info.badcoordsAvailable,true)
                return;
            end
            if ~isfield(info,'nFeatures') || ~isfield(info,'nValidCoords')
                return;
            end
            if ~(isnumeric(info.nFeatures) && isscalar(info.nFeatures) && ~isnan(info.nFeatures) && ...
                 isnumeric(info.nValidCoords) && isscalar(info.nValidCoords) && ~isnan(info.nValidCoords))
                return;
            end
            if info.nFeatures ~= info.nValidCoords
                msg = sprintf(['Feature count (%g) differs from valid-coordinate count (%g) derived from NM.badcoords. ', ...
                               'This may be expected after feature selection or if badcoords encodes a broader vectorization domain.'], ...
                               info.nFeatures, info.nValidCoords);
                if isfield(info,'diagnostics') && iscell(info.diagnostics)
                    info.diagnostics{end+1} = msg;
                else
                    info.diagnostics = {msg};
                end
            end
        end

        function info = finalizeCompleteness(info)
            % finalizeCompleteness  Derive final completeness and warning fields for a modality-info record.
            %
            % Info -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            known = 0; total = 0;
            fields = {'nSubjects','nFeatures','storageMode','isImaging','missingnessKnown'};
            for i = 1:numel(fields)
                total = total + 1;
                f = fields{i};
                v = info.(f);
                if islogical(v) && isscalar(v)
                    known = known + 1;
                elseif isnumeric(v) && isscalar(v) && ~isnan(v)
                    known = known + 1;
                elseif ischar(v) && ~isempty(v) && ~strcmp(v,'unknown')
                    known = known + 1;
                end
            end
            if total == 0
                score = NaN;
            else
                score = known / total;
            end
            info.completenessScore = score;
            if isnan(score)
                info.metadataCompleteness = 'unknown';
            elseif score >= 0.95
                info.metadataCompleteness = 'complete';
            elseif score >= 0.70
                info.metadataCompleteness = 'partial';
            else
                info.metadataCompleteness = 'incomplete';
            end
        end

        function summary = summaryFromInfos(infos)
            % summaryFromInfos  Aggregate canonical fromNM modality-info records.
            summary = struct();
            summary.numModalities = double(numel(infos));
            summary.numExternal = 0;
            summary.numImaging = 0;
            summary.numMissingKnown = 0;
            summary.numMissingUnknown = 0;
            summary.numIncomplete = 0;
            summary.totalFeatures = 0;
            summary.totalAllNaNCases = 0;
            summary.totalPartlyMissingCases = 0;
            for i = 1:numel(infos)
                if strcmpi(infos(i).storageMode,'external')
                    summary.numExternal = summary.numExternal + 1;
                end
                if isequal(infos(i).isImaging,true)
                    summary.numImaging = summary.numImaging + 1;
                end
                if infos(i).missingnessKnown
                    summary.numMissingKnown = summary.numMissingKnown + 1;
                else
                    summary.numMissingUnknown = summary.numMissingUnknown + 1;
                end
                if any(strcmpi(infos(i).metadataCompleteness, {'partial','incomplete','unknown'}))
                    summary.numIncomplete = summary.numIncomplete + 1;
                end
                if ~isnan(infos(i).nFeatures)
                    summary.totalFeatures = summary.totalFeatures + double(infos(i).nFeatures);
                end
                if ~isnan(infos(i).featureStats.nAllNaNCases)
                    summary.totalAllNaNCases = summary.totalAllNaNCases + double(infos(i).featureStats.nAllNaNCases);
                end
                if ~isnan(infos(i).featureStats.nPartialMissingCases)
                    summary.totalPartlyMissingCases = summary.totalPartlyMissingCases + double(infos(i).featureStats.nPartialMissingCases);
                end
            end
        end

        function msg = phaseMessage()
            % phaseMessage  Return the current DataIO phase message shown in modality overview state.
            %
            % No required inputs -> msg.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            msg = ['Read-only DataIO overview: imported modality information is summarized without loading externally stored feature data. ', ...
                   'In-memory data are scanned in feature chunks so cases containing only missing imaging values remain visible in the overview.'];
        end

        function info = mergeKnown(info, src)
            % mergeKnown  Merge known metadata fields without overwriting populated target values.
            %
            % Info, src -> info.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if ~isstruct(src), return; end
            names = fieldnames(src);
            for i = 1:numel(names)
                f = names{i};
                % Keep the UI metadata schema stable. Additional
                % future fields can be promoted deliberately by adding them to
                % emptyInfo(), rather than leaking arbitrary provenance fields
                % into struct arrays / JSON state.
                if ~isfield(info, f), continue; end
                if strcmp(f,'featureStats')
                    cachedStats = src.featureStats;
                    if ~isempty(cachedStats)
                        known = intersect(fieldnames(cachedStats), fieldnames(info.featureStats));
                        for k = 1:numel(known)
                            key = known{k};
                            info.featureStats.(key) = cachedStats.(key);
                        end
                    end
                    continue;
                end
                try
                    v = src.(f);

                    % Cached modalityInfo fields created by older or partial
                    % import paths may contain [] for facts that can be
                    % inferred cheaply from the committed container (e.g.
                    % nSubjects from D.cases or size(D.Y{v},1)).  Do not let
                    % empty cached values mask those fallbacks.  Scalar false
                    % and numeric zero are not empty and are preserved.
                    if isempty(v)
                        continue;
                    end
                    info.(f) = v;
                catch
                end
            end
        end

        function tf = deriveIsImaging(info)
            % deriveIsImaging  Infer whether a modality-info record represents voxel/ROI imaging data.
            %
            % Info -> tf.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isfield(info,'isImaging') && islogical(info.isImaging) && isscalar(info.isImaging)
                tf = info.isImaging; return;
            end
            ds = lower(NMModalityInfoTools.asChar(NMModalityInfoTools.getField(info,'datasource','')));
            src = lower(NMModalityInfoTools.asChar(NMModalityInfoTools.getField(info,'source','')));
            typ = NMModalityInfoTools.getField(info,'typeCode',NaN);
            tf = [];
            if any(strcmp(ds, {'nifti','spm','surf','image'})) || any(strcmp(src, {'image','surf'}))
                tf = true;
            elseif isnumeric(typ) && isscalar(typ) && ~isnan(typ)
                tf = typ > 0;
            elseif any(strcmp(ds, {'matrix','vector'})) || strcmp(src,'matrix')
                tf = false;
            end
        end

        function tf = deriveIsSurface(info)
            % deriveIsSurface  Infer whether a modality-info record represents surface-based data.
            %
            % Info -> tf.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isfield(info,'isSurface') && islogical(info.isSurface) && isscalar(info.isSurface)
                tf = info.isSurface; return;
            end
            ds = lower(NMModalityInfoTools.asChar(NMModalityInfoTools.getField(info,'datasource','')));
            typ = NMModalityInfoTools.getField(info,'typeCode',NaN);
            tf = [];
            if strcmp(ds,'surf') || (isnumeric(typ) && isscalar(typ) && typ == 2)
                tf = true;
            elseif any(strcmp(ds, {'matrix','nifti','spm','vector'})) || (isnumeric(typ) && isscalar(typ) && ~isnan(typ))
                tf = false;
            end
        end

        function n = inferSubjectCount(NM, input)
            % inferSubjectCount  Infer subject count from NM fields or an import input payload.
            %
            % NM, input -> n.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            if nargin >= 2 && isstruct(input)
                cand = {'n_subjects','n_samples','n_subjects_all'};
                for i = 1:numel(cand)
                    if isfield(input,cand{i}) && isnumeric(input.(cand{i})) && ~isempty(input.(cand{i}))
                        n = double(input.(cand{i})(1)); return;
                    end
                end
            end
            if isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                try, n = double(numel(NM.cases)); return; catch, end
            end
            if isstruct(NM) && isfield(NM,'label') && ~isempty(NM.label)
                try, n = double(size(NM.label,1)); return; catch, end
            end
        end

        function n = subjectCountFromInputVector(x)
            % subjectCountFromInputVector  Infer subject count from labels, cases, files, or matrix-like vectors.
            %
            % X -> n.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            if nargin < 1 || isempty(x) || ~isnumeric(x), return; end
            vals = double(x(:));
            vals = vals(isfinite(vals));
            if isempty(vals), return; end
            if numel(vals) > 1
                % Legacy DataIO stores class-wise counts in n_subjects for
                % labelled imports, e.g. [10 10].  The case axis is the sum,
                % not the first class count.
                n = sum(vals);
            else
                n = vals(1);
            end
        end

        function n = inferFeatureCount(NM, input, varind)
            % inferFeatureCount  Infer feature count from NM/datadescriptor/input payloads.
            %
            % Consumes NM, input, varind; returns n.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            if nargin >= 2 && isstruct(input)
                cand = {'n_features','nFeatures','numFeatures','featdim'};
                for i = 1:numel(cand)
                    if isfield(input,cand{i}) && isnumeric(input.(cand{i})) && ~isempty(input.(cand{i}))
                        n = double(input.(cand{i})(1)); return;
                    end
                end
                if isfield(input,'featnames') && ~isempty(input.featnames)
                    try, n = double(numel(input.featnames)); return; catch, end
                end
            end
            [featnames, hasFeatNames] = NMModalityInfoTools.getCellField(NM, 'featnames', varind);
            if hasFeatNames && ~isempty(featnames)
                try, n = double(numel(featnames)); return; catch, end
            end
            [badcoords, hasBadcoords] = NMModalityInfoTools.getCellField(NM, 'badcoords', varind);
            if hasBadcoords && ~isempty(badcoords)
                try, n = double(numel(badcoords)); return; catch, end
            end
        end

        function value = cachedCount(info, fieldName, varind)
            value = NaN;
            if ~isfield(info,fieldName) || isempty(info.(fieldName)), return; end
            candidate = info.(fieldName);
            if ~(isnumeric(candidate) && isreal(candidate) && isscalar(candidate) && (isnan(candidate) || (isfinite(candidate) && candidate >= 0)))
                error('NMModalityInfoTools:invalidCachedCount', ...
                    'modalityInfo.%s for modality %d must be a nonnegative scalar or NaN.', fieldName, varind);
            end
            value = double(candidate);
        end

        function token = storageModeToken(value, varind)
            token = NMModalityInfoTools.textToken(value,'storageMode',varind);
            if ~any(strcmp(token,{'memory','external','unknown'}))
                error('NMModalityInfoTools:invalidStorageMode', ...
                    'modalityInfo.storageMode for modality %d must be memory, external, or unknown.', varind);
            end
        end

        function token = textToken(value, fieldName, varind)
            if isstring(value)
                if ~isscalar(value)
                    error('NMModalityInfoTools:invalidMetadataText', ...
                        'Modality %d metadata field %s must be scalar text.', varind, fieldName);
                end
                value = char(value);
            end
            if ~ischar(value) || size(value,1) ~= 1
                error('NMModalityInfoTools:invalidMetadataText', ...
                    'Modality %d metadata field %s must be scalar text.', varind, fieldName);
            end
            token = lower(strtrim(value));
            if isempty(token), token = 'unknown'; end
        end

        function dd = modalityDescriptor(NM, varind)
            % modalityDescriptor  Return one persisted descriptor or empty when the modality is absent.
            dd = [];
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || ...
                    numel(NM.datadescriptor) < varind || isempty(NM.datadescriptor{varind})
                return;
            end
            if ~isstruct(NM.datadescriptor{varind}) || numel(NM.datadescriptor{varind}) ~= 1
                error('NMModalityInfoTools:invalidDescriptor', ...
                    'NM.datadescriptor{%d} must be a scalar struct.', varind);
            end
            dd = NM.datadescriptor{varind};
        end

        function [value, ok] = getCellField(S, field, idx)
            % getCellField  Read one cell-array field entry with bounds checking.
            %
            % Consumes S, field, idx; returns value, ok.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            value = [];
            ok = false;
            if ~isstruct(S) || ~isfield(S,field), return; end
            x = S.(field);
            if iscell(x)
                if numel(x) >= idx
                    value = x{idx}; ok = true;
                end
            elseif idx == 1
                value = x; ok = true;
            end
        end

        function v = getOpt(opts, name, default)
            % getOpt  Read an option field with a caller-specific default without changing option semantics.
            %
            % Consumes opts, name, default; returns v.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = default;
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            end
        end

        function v = getField(S, name, default)
            % getField  Read a struct field with a caller-specific default for message/metadata normalization.
            %
            % Consumes S, name, default; returns v.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = default;
            if isstruct(S) && isfield(S,name) && ~isempty(S.(name))
                v = S.(name);
            end
        end

        function c = asChar(x)
            % asChar  Normalize a value into character text for legacy/DataIO metadata fields.
            %
            % X -> c.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if ischar(x), c = x; return; end
            if isstring(x), c = char(x); return; end
            if isnumeric(x) || islogical(x)
                if isscalar(x), c = num2str(x); else, c = mat2str(x); end
                return;
            end
            try
                c = char(x);
            catch
                c = '';
            end
        end

        function c = asCell(x)
            % asCell  Normalize text or cell input into a cell-string style representation.
            %
            % X -> c.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(x), c = {}; return; end
            if iscell(x), c = x; return; end
            if ischar(x) || isstring(x), c = {char(x)}; return; end
            c = {x};
        end

        function b = basename(p)
            % basename  Return the terminal filename/path token used in modality overview summaries.
            %
            % P -> b.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            b = '';
            if isempty(p), return; end
            p = char(p);
            try
                [~,nam,ext] = fileparts(p);
                b = [nam ext];
            catch
                b = p;
            end
        end

        function n = safeRowCount(x)
            % safeRowCount  Return row count for matrix/table/cell payloads without throwing on unsupported input.
            %
            % X -> n.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            try
                if ischar(x)
                    n = size(x,1);
                elseif isstring(x) || iscell(x)
                    n = numel(x);
                else
                    n = size(x,1);
                end
            catch
            end
        end

        function s = sizeString(sz)
            % sizeString  Format a MATLAB size vector for overview and diagnostics text.
            %
            % Sz -> s.
            % It feeds DataIO overview cards and diagnostics and should not mutate NM or modality matrices.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(sz), s = ''; return; end
            s = sprintf('%dx', double(sz));
            if ~isempty(s), s = s(1:end-1); end
        end
    end
end
