classdef NMDataIOStateTools
% NMDataIOStateTools
% -------------------------------------------------------------------------
% Purpose:
%   Canonical translation authority between browser/public-API DataIO state and the IO/state
%   contracts consumed by DataIO materializers. It also owns the supported provenance vocabulary.
%
% Authority and persistence:
%   Source identity, role assignments, alignment mode, filters, import-target context and resumable
%   scientific settings round-trip through this class. Transient credentials, live catalogues and
%   materialization caches are deliberately excluded from persisted state.
%
% Invariants:
%   Translation must preserve scientific meaning and must not invent keys, labels, filters or
%   provenance-specific fallbacks. Browser and API callers converge on the same state contract.
% -------------------------------------------------------------------------

    methods (Static)
        function state = defaultMatrixState(NM, varind)
            % DEFAULTMATRIXSTATE  Build a browser/API default state for matrix-like DataIO imports.
            %
            %   state = NMDataIOStateTools.defaultMatrixState(NM, varind) returns
            %   a scalar state struct with matrix/table, connectivity, selection,
            %   NaN-mapper, case-alignment, and import-target defaults.  NM is
            %   inspected only to infer the next modality index and modeflag; the
            %   function is non-mutating and does not probe external data sources.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = NMDataIOStateTools.defaultVarind(NM); end
            state = struct();
            state.datasource = 'matrix';
            state.sourceType = 'workspace';
            state.groupmode = 1;
            state.varind = varind;
            state.modeflag = NMDataIOStateTools.inferModeflag(NM);
            state.labels_known = true;
            state.oocvflag = false;
            state.desc_data = '?';
            state.desc_groups = {'?'};
            state.matrix = struct();
            state.matrix.sourceType = 'workspace';
            state.matrix.M_edit = '?';
            state.matrix.matrix_edit = '?';
            state.matrix.tableVariable = '?';
            state.matrix.tableVariables = {};
            state.matrix.matFiles = {};
            state.matrix.tableFiles = {};
            state.matrix.tabularFilters = struct('sourceType',{},'sourcePath',{},'sourceObject',{},'sourceName',{},'match',{},'caseSensitive',{},'rules',{});
            state.matrix.variableRoles = struct('caseId',{{}},'labels',{{}},'features',{{}},'featureNames',{{}},'covariates',{{}},'covariateNames',{{}});
            state.matrix.labelDefinition = struct('kind','','manualNames',{{}},'nameSourceRef',struct(),'sourceCodes',{{}},'count',0);
            state.matrix.metadataAlignmentMode = 'key_per_block';
            state.matrix.featureMappingMode = 'automatic';
            state.matrix.caseAxisPolicy = 'complete_case';
            state.matrix.databaseConnector = 'sqlite_file';
            state.matrix.databaseUrl = '?';
            state.matrix.databaseFile = '?';
            state.matrix.databaseUser = '?';
            state.matrix.databaseName = '?';
            state.matrix.databaseSchema = '?';
            state.matrix.databaseTable = '?';
            state.matrix.databaseUseQuery = false;
            state.matrix.databaseQuery = '?';
            state.matrix.label_edit = '?';
            state.matrix.case_edit = '?';
            state.matrix.col_edit = '?';
            state.matrix.covnames_edit = '?';
            state.matrix.covariateNameList = {};
            state.matrix.requireFeatureNames = false;
            state.matrix.requireCovariateNames = false;
            state.matrix.delimit = 'tab';
            state.matrix.sheet = '?';
            state.matrix.sheets = {};
            state.matrix.headerRow = [];
            state.matrix.headerAutoDetect = true;
            state.matrix.uniquelim = 15;
            state.matrix.covar_edit = {};
            state.matrix.ignore_edit = {};
            state.matrix.feature_edit = {};
            state.covmanage_edit = 1;
            state.matrix.compatibilityMode = 'legacy';
            state.matrix.nanMapper = struct();
            state.matrix.nanMapper.enabled = false;
            state.matrix.nanMapper.tokens = {'NA','N/A','n/a','na','.','-','','missing','Missing','MISSING'};
            state.matrix.nanMapper.applyToFeatures = true;
            state.matrix.nanMapper.applyToCovariates = true;
            state.matrix.nanMapper.applyToLabels = false;
            state.matrix.nanMapper.applyToCaseIds = false;
            state.matrix.nanMapper.caseInsensitive = true;
            state.matrix.nanMapper.trimWhitespace = true;
            state.matrix.caseAlignment = struct();
            state.matrix.caseAlignment.missingCasePolicy = 'fill_nan';
            state.matrix.caseAlignment.allowMissingCasesAsNaN = true;
            state.matrix.caseAlignment.idMappingMode = 'direct';
            state.matrix.caseAlignment.mappingApproved = false;
            state.caseAlignment = state.matrix.caseAlignment;
            state.connectivity = struct();
            state.connectivity.sourceFormat = 'file_per_subject';
            state.connectivity.dataVariable = '?';
            state.connectivity.tableVariable = '?';
            state.connectivity.caseColumn = '';
            state.connectivity.edgeColumns = '';
            state.connectivity.files = {};
            state.connectivity.classFileLists = {};
            state.connectivity.matVariable = '';
            state.connectivity.caseIDMode = 'filename';
            state.connectivity.caseIds = {};
            state.connectivity.auxiliarySourceType = 'workspace';
            state.connectivity.auxiliaryAlignmentMode = 'case_id';
            state.connectivity.auxiliaryVariableRoles = struct('caseId',{{}},'labels',{{}},'features',{{}},'featureNames',{{}},'covariates',{{}},'covariateNames',{{}});
            state.connectivity.auxiliaryTableFiles = {};
            state.connectivity.labelMode = 'metadata';
            state.connectivity.matrixType = 'undirected';
            state.connectivity.triangle = 'upper';
            state.connectivity.includeDiagonal = false;
            state.connectivity.subjectDim = 1;
            state.connectivity.symmetryTolerance = 1e-8;
            state.connectivity.atlasFile = '';
            state.connectivity.atlasLabelFile = '';
            state.connectivity.atlasLabelDelimiter = 'auto';
            state.connectivity.atlasLabelHasHeader = 'auto';
            state.connectivity.atlasLabelIDColumn = '';
            state.connectivity.atlasLabelNameColumn = '';
            state.connectivity.atlasLabelXColumn = '';
            state.connectivity.atlasLabelYColumn = '';
            state.connectivity.atlasLabelZColumn = '';
            state.connectivity.nodeCoordinateSpace = 'MNI';
            state.connectivity.nodeCoordinateUnits = 'mm';
            state.connectivity.weightingMatrices = '';
            state.connectivity.weightingFiles = {};
            state.connectivity.weightingNames = {};
            state.connectivity.weightingNodeOrder = 'training';
            state.connectivity.weightingEdgeMode = 'auto';
            state.selection = struct();
            state.selection.selFeats = [];
            state.selection.selCases = [];
            state.importTarget = struct('scope','training','mode','add','varind',double(varind));
        end

        function IO = stateToIO(state, NM, varind)
            % stateToIO  Translate browser/API DataIO state into the legacy IO contract.
            %
            % IO = NMDataIOStateTools.stateToIO(state, NM, varind) starts from
            % defaultIO and overlays matrix/table, image/surface, connectivity,
            % selection, direct-payload, and import-target fields expected by the
            % legacy ReadTabular/TransferModality2NM import path.  The conversion
            % preserves transient resolved payloads where present and does not mutate NM.
            %
            % state.caseAlignment: stores the case-alignment decision and diagnostics used before commit.
            % state.datasource: records the source family selected in the DataIO browser/API state.
            % state.importTarget: identifies whether the DataIO operation targets training, OOCV/application data, or a specific container.
            % state.modeflag: carries the classification/regression task mode into legacy-compatible state.
            % state.preview: stores the latest non-committing preview/probe payload associated with the browser state.
            % state.sourceType: records the concrete input-source type selected by the user or API.
            % state.tableColumnRoles: stores column-role assignments for table/database imports.
            % state.varind: selects the active modality index represented by the browser/API state.
            %
            % state.dataSourceType: sourceType alias accepted from browser/API matrix or imaging state.
            % state.sourceMode: groupmode/source-mode alias used for backward-compatible matrix source inference.
            % state.mode: classification/regression task-mode alias used when modeflag is absent.
            % state.label: modality description alias used when desc_data/description is absent.
            % state.groupNames: group-label names alias used when desc_groups/groupnames are absent.
            % state.labelsKnown: logical alias for labels_known.
            % state.oocvFlag: logical alias for oocvflag when importTarget is not explicit.
            if nargin < 1 || isempty(state), state = struct(); end
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(varind)
                if isstruct(state) && isfield(state,'varind') && ~isempty(state.varind)
                    varind = state.varind;
                else
                    varind = NMDataIOStateTools.defaultVarind(NM);
                end
            end

            defaults = NMDataIOStateTools.defaultIO(NM, varind);
            IO = defaults;
            IO.datasource = char(NMDataIOStateTools.pick(state, {'datasource'}, IO.datasource));
            m = NMDataIOStateTools.substructOrEmpty(state, {'matrix','matrixSource','source'});
            fallbackGroupmode = NMDataIOStateTools.pick(state, {'groupmode','sourceMode'}, IO.groupmode);
            topSourceType = NMDataIOStateTools.pick(state, {'sourceType','dataSourceType'}, '');
            matrixSourceType = NMDataIOStateTools.pick(m, {'sourceType','dataSourceType'}, '');
            fallbackGm = NMDataIOStateTools.groupmodeValue(fallbackGroupmode);
            sourceType = topSourceType;

            % Backward compatibility: older tests/callers can set only
            % state.groupmode: legacy/source-mode compatibility field. defaultMatrixState already contains
            % sourceType='workspace' at both levels; do not let those default
            % values override an explicit non-workspace groupmode.
            topIsDefaultWorkspace = NMDataIOStateTools.isUnknownString(topSourceType) || strcmp(NMDataIOStateTools.normalizeSourceType(topSourceType, 1), 'workspace');
            matrixIsDefaultWorkspace = NMDataIOStateTools.isUnknownString(matrixSourceType) || strcmp(NMDataIOStateTools.normalizeSourceType(matrixSourceType, 1), 'workspace');
            if fallbackGm ~= 1 && topIsDefaultWorkspace && matrixIsDefaultWorkspace
                sourceType = '';
            elseif NMDataIOStateTools.isUnknownString(sourceType)
                sourceType = matrixSourceType;
            end
            IO.sourceType = NMDataIOStateTools.normalizeSourceType(sourceType, fallbackGroupmode);
            IO.groupmode = NMDataIOStateTools.groupmodeFromSourceType(IO.sourceType, fallbackGroupmode);
            IO.modeflag = char(NMDataIOStateTools.pick(state, {'modeflag','mode'}, IO.modeflag));
            IO.labels_known = logical(NMDataIOStateTools.pick(state, {'labels_known','labelsKnown'}, IO.labels_known));
            IO.oocvflag = logical(NMDataIOStateTools.pick(state, {'oocvflag','oocvFlag'}, IO.oocvflag));
            if isfield(state,'importTarget') && isstruct(state.importTarget)
                IO.importTarget = NMDataIOImportTargetTools.normalize(NM, state, varind);
                IO.varind = IO.importTarget.varind;
                IO.oocvflag = strcmpi(IO.importTarget.scope, 'oocv');
            end
            IO.desc_data = char(NMDataIOStateTools.pick(state, {'desc_data','description','label'}, IO.desc_data));
            IO.desc_groups = NMDataIOStateTools.pick(state, {'desc_groups','groupNames'}, IO.desc_groups);

            IO.M_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'M_edit','matrixPath','file','workspaceVariable','workspaceMatrix','featureVariable','tableVariable'}, IO.M_edit));
            IO.matrix_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'matrix_edit','matrixVariable','matVariable','featureVariable'}, IO.matrix_edit));
            IO.tableVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'tableVariable'}, '?'));
            IO.tableVariables = NMDataIOStateTools.pick2(state, m, {'tableVariables'}, {});
            IO.matFiles = NMDataIOStateTools.pick2(state, m, {'matFiles','files'}, {});
            IO.tableFiles = NMDataIOStateTools.pick2(state, m, {'tableFiles'}, {});
            IO.tabularFilters = NMDataIOStateTools.pick2(state, m, {'tabularFilters'}, struct([]));
            IO.variableRoles = NMDataIOStateTools.pick2(state, m, {'variableRoles'}, struct());
            IO.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'auxiliarySourceType'}, NMDataIOStateTools.fieldOr(IO,'auxiliarySourceType','workspace')));
            IO.auxiliaryAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(NMDataIOStateTools.pick2(state, m, {'auxiliaryAlignmentMode'}, NMDataIOStateTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id')));
            IO.auxiliaryVariableRoles = NMDataIOStateTools.pick2(state, m, {'auxiliaryVariableRoles'}, NMDataIOStateTools.fieldOr(IO,'auxiliaryVariableRoles',struct()));
            IO.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, m, {'auxiliaryTableFiles','auxiliaryTableFile'}, NMDataIOStateTools.fieldOr(IO,'auxiliaryTableFiles',{})));
            IO.labelDefinition = NMDataIOStateTools.pick2(state, m, {'labelDefinition'}, struct());
            IO.metadataAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode( ...
                NMDataIOStateTools.pick2(state, m, {'metadataAlignmentMode','alignmentMode'}, 'case_id'));
            IO.featureMappingMode = lower(strtrim(NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'featureMappingMode'}, 'automatic'))));
            if ~strcmp(IO.featureMappingMode,'manual'), IO.featureMappingMode = 'automatic'; end
            IO.variableRoles = NMDataIOStateTools.normalizeVariableRoleKeyRefs(IO.variableRoles, IO, IO.metadataAlignmentMode);
            IO.caseAxisPolicy = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'caseAxisPolicy'}, 'complete_case'));
            IO.databaseConnector = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseConnector','connector','databaseType'}, 'sqlite_file'));
            IO.databaseUrl = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseUrl'}, '?'));
            IO.databaseFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseFile'}, '?'));
            IO.databaseUser = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseUser'}, '?'));
            IO.databasePassword = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databasePassword'}, '?'));
            IO.databaseName = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseName','database'}, '?'));
            IO.databaseSchema = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseSchema','schema'}, '?'));
            IO.databaseTable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseTable'}, '?'));
            IO.databaseUseQuery = logical(NMDataIOStateTools.pick2(state, m, {'databaseUseQuery','useSqlQuery'}, false));
            IO.databaseQuery = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'databaseQuery','sqlQuery','query'}, '?'));
            if IO.groupmode == 5
                if isempty(IO.tableVariables) && ~strcmp(IO.tableVariable, '?'), IO.tableVariables = {IO.tableVariable}; end
                if ~isempty(IO.tableVariables), IO.tableVariable = char(string(IO.tableVariables{1})); IO.M_edit = IO.tableVariable; end
            end
            labelEdit = NMDataIOStateTools.pick2(state, m, {'label_edit','labelVariable','labelColumn'}, IO.label_edit);
            if ismember(IO.groupmode, [1 2])
                IO.label_edit = NMDataIOStateTools.toChar(labelEdit);
            else
                IO.label_edit = labelEdit;
            end
            IO.case_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'case_edit','caseVariable','caseColumn','idVariable','idColumn'}, IO.case_edit));
            IO.col_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'col_edit','featureNamesVariable','featureNameVariable','featureNamesVariableName','featureColumn'}, IO.col_edit));
            IO.covnames_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'covnames_edit','covariateNamesVariable','covariateNameVariable','covarNamesVariable'}, IO.covnames_edit));
            IO.covariateNameList = NMDataIOStateTools.pick2(state, m, {'covariateNameList','manualCovariateNames'}, NMDataIOStateTools.fieldOr(IO,'covariateNameList',{}));
            IO.delimit = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'delimit','delimiter'}, IO.delimit));
            IO.sheet = NMDataIOStateTools.pick2(state, m, {'sheet','sheetName'}, IO.sheet);
            IO.sheets = NMDataIOStateTools.pick2(state, m, {'sheets'}, IO.sheets);
            IO.headerRow = NMDataIOStateTools.pick2(state, m, {'headerRow','tableHeaderRow','variableNamesLine'}, []);
            IO.headerAutoDetect = logical(NMDataIOStateTools.pick2(state, m, {'headerAutoDetect','autoDetectHeaderRow'}, false));
            IO.uniquelim = NMDataIOStateTools.pick2(state, m, {'uniquelim','uniqueLimit'}, IO.uniquelim);
            IO.covar_edit = NMDataIOStateTools.pick2(state, m, {'covar_edit','covariateColumns','covarColumns'}, IO.covar_edit);
            IO.ignore_edit = NMDataIOStateTools.pick2(state, m, {'ignore_edit','ignoreColumns','ignoredColumns'}, IO.ignore_edit);
            IO.feature_edit = NMDataIOStateTools.pick2(state, m, {'feature_edit','featureColumns','features','selectedFeatureColumns'}, IO.feature_edit);
            IO.covmanage_edit = NMDataIOStateTools.pick(state, {'covmanage_edit'}, NMDataIOStateTools.pick(m, {'covmanage_edit','covariateMode'}, NMDataIOStateTools.fieldOr(IO,'covmanage_edit',1)));
            IO.compatibilityMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, m, {'compatibilityMode'}, 'legacy'));
            IO.requireFeatureNames = logical(NMDataIOStateTools.pick2(state, m, {'requireFeatureNames'}, ismember(IO.groupmode, [1 2])));
            IO.requireCovariateNames = logical(NMDataIOStateTools.pick2(state, m, {'requireCovariateNames'}, ismember(IO.groupmode, [1 2]) && ~isempty(IO.covar_edit)));
            IO.nanMapper = NMDataIOStateTools.pick2(state, m, {'nanMapper'}, struct());
            if isfield(state,'tableColumnRoles') && isstruct(state.tableColumnRoles)
                IO.tableColumnRoles = state.tableColumnRoles;
            elseif isfield(m,'tableColumnRoles') && isstruct(m.tableColumnRoles)
                IO.tableColumnRoles = m.tableColumnRoles;
            end
            if isfield(state,'caseAlignment') && isstruct(state.caseAlignment)
                IO.caseAlignment = state.caseAlignment;
            elseif isfield(m,'caseAlignment') && isstruct(m.caseAlignment)
                IO.caseAlignment = m.caseAlignment;
            end
            if isfield(state,'preview') && isstruct(state.preview)
                IO.preview = state.preview;
            elseif isfield(m,'preview') && isstruct(m.preview)
                IO.preview = m.preview;
            end

            sel = NMDataIOStateTools.substructOrEmpty(state, {'selection'});
            IO.selFeats = NMDataIOStateTools.pick2(state, sel, {'selFeats','selectedFeatures'}, []);
            IO.selCases = NMDataIOStateTools.pick2(state, sel, {'selCases','selectedCases'}, []);
            if isempty(IO.selFeats) && isfield(sel,'selFeatsFile') && ~isempty(sel.selFeatsFile) && ...
                    (exist('NMDataIOItemSelectorPackageTools','class') == 8 || exist('NMDataIOItemSelectorPackageTools','file') == 2)
                try
                    IO.selFeats = NMDataIOItemSelectorPackageTools.readMaskFile(char(string(sel.selFeatsFile)), []);
                    IO.selFeats = IO.selFeats(:)';
                catch ME
                    warning('NMDataIOStateTools:MaskReadFailed', ...
                        'Could not read item-selector feature mask file %s. %s (%s)', char(string(sel.selFeatsFile)), ME.message, ME.identifier);
                    IO.selFeats = [];
                end
            end
            if isempty(IO.selCases) && isfield(sel,'selCasesFile') && ~isempty(sel.selCasesFile) && ...
                    (exist('NMDataIOItemSelectorPackageTools','class') == 8 || exist('NMDataIOItemSelectorPackageTools','file') == 2)
                try
                    IO.selCases = NMDataIOItemSelectorPackageTools.readMaskFile(char(string(sel.selCasesFile)), []);
                    IO.selCases = IO.selCases(:);
                catch ME
                    warning('NMDataIOStateTools:MaskReadFailed', ...
                        'Could not read item-selector case mask file %s. %s (%s)', char(string(sel.selCasesFile)), ME.message, ME.identifier);
                    IO.selCases = [];
                end
            end
            IO.reread_mat = logical(NMDataIOStateTools.pick2(state, m, {'reread_mat','reread'}, false));

            % API/browser callers may provide an already resolved matrix
            % payload (subjects-by-features plus case/feature metadata).
            % Preserve it here so the commit path can reuse the existing
            % TransferModality2NM machinery without round-tripping through
            % temporary workspace variables.
            directFields = {'Y','ID','s_ID','featnames','s_featnames','label','s_label','L', ...
                'covars','covnames','globalMode','n_subjects','n_subjects_all','n_samples', ...
                'connectivityProvenance','roiProvenance','importReport','input_settings'};
            for df = 1:numel(directFields)
                f = directFields{df};
                if isfield(m, f) && ~isempty(m.(f))
                    IO.(f) = m.(f);
                elseif isfield(state, f) && ~isempty(state.(f))
                    IO.(f) = state.(f);
                end
            end
            if isfield(IO,'Y') && ~isempty(IO.Y)
                if isfield(IO,'ID') && ~isempty(IO.ID) && (~isfield(IO,'s_ID') || isempty(IO.s_ID))
                    IO.s_ID = IO.ID;
                end
                if isfield(IO,'featnames') && ~isempty(IO.featnames) && (~isfield(IO,'s_featnames') || isempty(IO.s_featnames))
                    IO.s_featnames = IO.featnames;
                end
            end

            if NMDataIOStateTools.isConnectivityState(state)
                spec = NMDataIOStateTools.stateToConnectivitySpec(state, NM);
                IO.datasource = 'matrix';
                IO.sourceType = 'connectivity';
                IO.groupmode = 1;
                IO.sourceFamily = 'connectivity';
                IO.connectivitySpec = spec;
                IO.desc_data = spec.description;
                IO.input_settings = struct('sourceFamily','connectivity', ...
                    'sourceType','connectivity', 'datasource','matrix', ...
                    'groupmode',1, 'connectivitySpec',spec);
                if isfield(m,'Yw') && ~isempty(m.Yw), IO.Yw = m.Yw; end
                if isfield(m,'weightingNames') && ~isempty(m.weightingNames), IO.weightingNames = m.weightingNames; end
            end

            if NMDataIOStateTools.isROIState(state)
                spec = NMDataIOStateTools.stateToROISpec(state, NM);
                IO.datasource = 'matrix';
                IO.sourceType = 'roi';
                IO.groupmode = 1;
                IO.sourceFamily = 'roi';
                IO.roiSpec = spec;
                IO.desc_data = spec.description;
                roiSettings = NMDataIOStateTools.fieldOr(m,'input_settings',struct());
                if ~isstruct(roiSettings) || ~isscalar(roiSettings), roiSettings = struct(); end
                roiSettings.sourceFamily = 'roi';
                roiSettings.sourceType = 'roi';
                roiSettings.datasource = 'matrix';
                roiSettings.groupmode = 1;
                roiSettings.roiSpec = spec;
                IO.input_settings = roiSettings;
                if isfield(m,'roiProvenance') && ~isempty(m.roiProvenance)
                    IO.roiProvenance = m.roiProvenance;
                    IO.input_settings.roiProvenance = m.roiProvenance;
                end
                if isfield(m,'globalVolumeCorrection') && isstruct(m.globalVolumeCorrection)
                    IO.globalVolumeCorrection = m.globalVolumeCorrection;
                end
                if isfield(m,'roiWeightingProvenance') && isstruct(m.roiWeightingProvenance)
                    IO.roiWeightingProvenance = m.roiWeightingProvenance;
                end
                if isfield(m,'Yw') && ~isempty(m.Yw), IO.Yw = m.Yw; end
            end

            % Source identity was normalized above; do not rediscover it from the raw state.
            isSurfaceState = strcmpi(IO.sourceType, 'surface-list') || strcmpi(IO.datasource, 'surf');
            isImageState = isSurfaceState || strcmpi(IO.sourceType, 'image-list') || ...
                any(strcmpi(IO.datasource, {'nifti','spm','image'}));
            if isImageState
                img = NMDataIOStateTools.substructOrEmpty(state, {'image','imaging','imageSource'});
                if isSurfaceState
                    IO.datasource = 'surf';
                    IO.sourceType = 'surface-list';
                else
                    IO.datasource = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'datasource','imageDatasource'}, 'nifti'));
                    if isempty(IO.datasource) || strcmp(IO.datasource,'?') || strcmpi(IO.datasource,'image'), IO.datasource = 'nifti'; end
                    IO.sourceType = 'image-list';
                end
                IO.groupmode = -2;

                classLists = NMDataIOStateTools.fieldOr(img, 'classFileLists', {});
                if isempty(classLists), classLists = NMDataIOStateTools.fieldOr(img, 'classLists', {}); end
                IO.classFileLists = classLists;

                imageFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'imageFiles','files','P','PP'}, {}));
                classNames = {};
                classSizes = [];
                if ~isempty(classLists)
                    classSizes = zeros(1, numel(classLists));
                    flatFiles = {};
                    classNames = cell(1, numel(classLists));
                    for ci = 1:numel(classLists)
                        if iscell(classLists)
                            g = classLists{ci};
                        else
                            g = classLists(ci);
                        end
                        if isstruct(g)
                            gf = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(g, 'files', NMDataIOStateTools.fieldOr(g, 'imageFiles', {})));
                            classSizes(ci) = numel(gf);
                            flatFiles = [flatFiles; gf(:)]; %#ok<AGROW>
                            classNames{ci} = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(g, 'name', sprintf('Class_%d', ci)));
                        else
                            classSizes(ci) = 0;
                            classNames{ci} = sprintf('Class_%d', ci);
                        end
                    end
                    if isempty(imageFiles), imageFiles = flatFiles; end
                end
                IO.imageFiles = imageFiles(:);
                IO.imageFilesSpec = IO.imageFiles;
                IO.PP = IO.imageFiles;

                IO.maskFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'maskFile','brainmask','spaceDefiningImage','spacedefimg'}, ''));
                IO.brainmask = IO.maskFile;
                IO.caseIDMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'caseIDMode','caseIdMode','caseIdSource','caseIDSource'}, 'legacy_spm'));
                if strcmpi(strrep(IO.caseIDMode,'-','_'), 'explicit')
                    IO.imageCaseIDSpec = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'caseIds','caseIDs','cases','ID'}, {}));
                    IO.explicitCaseIDs = IO.imageCaseIDSpec;
                else
                    IO.imageCaseIDSpec = {};
                    IO.explicitCaseIDs = {};
                end

                IO.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'auxiliarySourceType','auxSourceType'}, 'workspace'));
                IO.auxiliaryAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'auxiliaryAlignmentMode'}, 'case_id'));
                IO.auxiliaryVariableRoles = NMDataIOStateTools.pick2(state, img, {'auxiliaryVariableRoles'}, struct());
                IO.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'auxiliaryTableFiles','auxiliaryTableFile'}, {}));
                IO.labelMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'labelMode','imageLabelMode','labelsMode'}, ''));

                groupSizes = NMDataIOStateTools.numericVector(NMDataIOStateTools.pick2(state, img, {'groupSizes','imageGroupSizes','classGroupSizes','n_subjects'}, []));
                if isempty(groupSizes) && ~isempty(classSizes), groupSizes = classSizes; end
                groupNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'groupNames','imageGroupNames','classGroupNames','desc_groups'}, {}));
                if isempty(groupNames) && ~isempty(classNames), groupNames = classNames(:); end
                IO.imageGroupSizes = groupSizes;
                IO.groupSizes = groupSizes;
                IO.imageGroupNames = groupNames;
                IO.groupNames = groupNames;
                if ~isempty(groupNames), IO.desc_groups = groupNames; end
                if isempty(IO.labelMode) || strcmp(IO.labelMode,'?')
                    mf = lower(IO.modeflag);
                    if strcmp(mf,'classification') && (~isempty(groupSizes) || ~isempty(classLists))
                        IO.labelMode = 'legacy_groups';
                    else
                        IO.labelMode = 'metadata';
                    end
                end

                IO.preserveExistingLabel = logical(NMDataIOStateTools.pick2(state, img, {'preserveExistingLabel'}, false));
                % Keep regression label display names in the state->IO draft
                % path.  prepareImageIO already reads these fields for
                % probe/preview/commit, but draft persistence goes through
                % stateToIO directly; omitting them causes Modify/Resume to
                % fall back to Label_001/Label_1.
                IO.labelNamesSpec = NMDataIOStateTools.pick2(state, img, {'labelNames','regressionLabelNames','labelnames','desc_labels'}, {});
                IO.labelNames = NMDataIOStateTools.asCaseCell(IO.labelNamesSpec);
                IO.regressionLabelNames = IO.labelNames;
                IO.labelNamesSource = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'labelNamesSource','regressionLabelNamesSource'}, 'manual'));
                if ~isempty(IO.labelNames)
                    IO.desc_labels = IO.labelNames;
                    IO.labelnames = IO.labelNames;
                end
                IO.preserveExistingCovariates = logical(NMDataIOStateTools.pick2(state, img, {'preserveExistingCovariates'}, false));
                IO.covariateNames = NMDataIOStateTools.pick2(state, img, {'covariateNames','covnames','covnames_edit'}, {});
                IO.covmanage_edit = NMDataIOStateTools.pick(state, {'covmanage_edit'}, NMDataIOStateTools.pick(img, {'covmanage_edit','covariateMode'}, IO.covmanage_edit));
                IO.uiGlobalModeSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'uiGlobalModeSelection'}, NMDataIOStateTools.pick2(state, img, {'globalMode','globalScaling','globalsMode'}, 'none')));
                IO.globalMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'globalMode','globalScaling','globalsMode'}, 'none'));
                IO.globalSource = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'globalSource','globalsSource'}, 'user'));
                IO.globalUserSourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'globalUserSourceType'}, 'workspace'));
                IO.globalAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'globalAlignmentMode'}, 'case_id'));
                IO.globalVariableRoles = NMDataIOStateTools.pick2(state, img, {'globalVariableRoles'}, struct());
                IO.globalTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'globalTableFiles','globalTableFile'}, {}));
                IO.globalName = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'globalName','globalsName'}, 'GlobalSignal'));
                IO.globnorm = double(NMDataIOStateTools.pick2(state, img, {'globnorm','globalNorm','globalMultiplier'}, 1));
                IO.threshop = NMDataIOStateTools.pick2(state, img, {'threshop','thresholdOperator'}, {'gt'});
                IO.threshval = NMDataIOStateTools.pick2(state, img, {'threshval','thresholdValue','Vml'}, 0);
                IO.threshlabels = NMDataIOStateTools.pick2(state, img, {'threshlabels','maskLabels','Lm'}, {'Bin Mask'});
                IO.weightingFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'weightingFiles','weightingMaps','Pw'}, {}));
                IO.surfaceImportMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceImportMode','surfaceMode','surfaceSpaceMode'}, 'vertex_template'));
                IO.surfaceTemplate = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceTemplate','surfaceTemplateSpace','templateSpace'}, 'unknown'));
                IO.surfaceHemisphere = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceHemisphere','hemisphere','hemi'}, 'auto'));
                IO.surfaceGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceGeometryFile','surfaceDisplayMeshFile','surfaceTemplateFile','geometryFile'}, ''));
                IO.surfaceInflatedGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceInflatedGeometryFile','inflatedSurfaceGeometryFile','surfaceInflatedTemplateFile'}, ''));
                IO.surfaceGeometryContract = NMDataIOStateTools.pick2(state, img, {'surfaceGeometryContract'}, struct());
                IO.surfaceGeometryIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceGeometryIdentity'}, ''));
                IO.surfaceInflatedGeometryIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceInflatedGeometryIdentity'}, ''));
                IO.surfaceTopologyIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceTopologyIdentity'}, ''));
                IO.surfaceVertexOrderIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceVertexOrderIdentity'}, ''));
                IO.surfaceInflatedValidated = logical(NMDataIOStateTools.pick2(state, img, {'surfaceInflatedValidated'}, false));
                IO.surfaceRoiCollapseMethod = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceRoiCollapseMethod','surfaceCollapseMethod','roiCollapseMethod'}, 'mean'));
                IO.surfaceRoiLHScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiLHScalarFiles','surfaceLHScalarFiles','lhScalarFiles'}, {}));
                IO.surfaceRoiLHAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiLHAnnotFiles','surfaceLHAnnotFiles','lhAnnotFiles'}, {}));
                IO.surfaceRoiLHGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceRoiLHGeometryFile','surfaceLHGeometryFile'}, ''));
                IO.surfaceRoiRHScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiRHScalarFiles','surfaceRHScalarFiles','rhScalarFiles'}, {}));
                IO.surfaceRoiRHAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiRHAnnotFiles','surfaceRHAnnotFiles','rhAnnotFiles'}, {}));
                IO.surfaceRoiRHGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, img, {'surfaceRoiRHGeometryFile','surfaceRHGeometryFile'}, ''));
                IO.surfaceRoiScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiScalarFiles','surfaceScalarFiles','roiScalarFiles'}, {}));
                IO.surfaceRoiAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, img, {'surfaceRoiAnnotFiles','surfaceAnnotationFiles','roiAnnotationFiles','annotFiles'}, {}));
            end

            % Convert JSON/string arrays to MATLAB cellstr where legacy code expects cell arrays.
            if isa(IO.label_edit,'string'), IO.label_edit = cellstr(IO.label_edit); end
            if isa(IO.covar_edit,'string'), IO.covar_edit = cellstr(IO.covar_edit); end
            if isa(IO.ignore_edit,'string'), IO.ignore_edit = cellstr(IO.ignore_edit); end
            if isa(IO.feature_edit,'string'), IO.feature_edit = cellstr(IO.feature_edit); end
            if ischar(IO.covar_edit) && ~isempty(strfind(IO.covar_edit, ',')), IO.covar_edit = regexp(IO.covar_edit, '\s*,\s*', 'split'); end
            if ischar(IO.ignore_edit) && ~isempty(strfind(IO.ignore_edit, ',')), IO.ignore_edit = regexp(IO.ignore_edit, '\s*,\s*', 'split'); end
            if ischar(IO.feature_edit) && ~isempty(strfind(IO.feature_edit, ',')), IO.feature_edit = regexp(IO.feature_edit, '\s*,\s*', 'split'); end
            if isa(IO.desc_groups,'string'), IO.desc_groups = cellstr(IO.desc_groups); end
            if ischar(IO.desc_groups), IO.desc_groups = cellstr(IO.desc_groups); end
        end

        function spec = stateToROISpec(state, NM, scope)
            % stateToROISpec  Convert an explicit ROI browser/API state into the direct-import contract.
            %
            % ROI semantics are never inferred from feature names or matrix shape.
            % The source-specific ROI state supplies an explicit source format,
            % ROI sidecar identity columns, and a mandatory volumetric atlas or
            % surface annotation reference. Canonical volumetric provenance activates
            % the persisted global-volume selection; surface provenance forces the
            % effective mode to none while retaining inactive UI selections for resume.
            % This adapter does not read ROI/global data or compute scaling/QC; those
            % materialization steps belong to NMDataIOROIDirectTools.resolvePayload.
            if nargin < 1 || isempty(state), state = struct(); end
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(scope)
                scope = 'training';
                if isfield(state,'importTarget') && isstruct(state.importTarget) && ...
                        isfield(state.importTarget,'scope') && strcmpi(char(string(state.importTarget.scope)),'oocv')
                    scope = 'oocv';
                end
            end
            scope = lower(strtrim(char(string(scope))));
            roi = NMDataIOStateTools.substructOrEmpty(state, {'roi','roiSource'});
            spec = struct();
            spec.scope = scope;
            if isfield(state,'importTarget') && isstruct(state.importTarget)
                tgt = NMDataIOImportTargetTools.normalize(NM, state, NMDataIOStateTools.pick(state, {'varind'}, []));
                spec.varind = tgt.varind;
                spec.importTarget = tgt;
                spec.targetMode = tgt.mode;
                if strcmpi(tgt.scope,'oocv')
                    spec.scope = 'oocv';
                    spec.containerField = tgt.containerField;
                    spec.containerIndex = tgt.containerIndex;
                    spec.labelsKnown = logical(NMDataIOStateTools.fieldOr(tgt,'labels_known',false));
                end
            else
                spec.varind = NMDataIOStateTools.pick(state, {'varind'}, NMDataIOStateTools.defaultVarind(NM));
                spec.targetMode = 'add';
            end
            spec.modeflag = NMDataIOStateTools.toChar(NMDataIOStateTools.pick(state, {'modeflag','mode'}, NMDataIOStateTools.inferModeflag(NM)));
            spec.description = NMDataIOStateTools.toChar(NMDataIOStateTools.pick(state, {'desc_data','description','label'}, 'ROI data'));
            spec.desc_data = spec.description;
            spec.sourceFormat = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'sourceFormat'}, 'workspace_matrix'));
            spec.uiLabelModeSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'uiLabelModeSelection'}, ''));
            spec.labelMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'labelMode'}, 'metadata'));
            if ~strcmpi(spec.sourceFormat,'cat12_files') || strcmpi(spec.modeflag,'regression'), spec.labelMode = 'metadata'; end
            spec.files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'files'}, {}));
            spec.vectorFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'vectorFiles'}, {}));
            spec.classFileLists = NMDataIOStateTools.pick2(state, roi, {'classFileLists','classLists'}, {});
            spec.groupNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'groupNames'}, {}));
            spec.groupSizes = NMDataIOStateTools.pick2(state, roi, {'groupSizes'}, []);
            spec.activeClassIndex = NMDataIOStateTools.pick2(state, roi, {'activeClassIndex'}, 0);
            spec.dataVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'dataVariable'}, ''));
            spec.tableVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'tableVariable'}, ''));
            spec.tableFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'tableFile'}, ''));
            spec.caseColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'caseColumn'}, ''));
            spec.featureColumns = NMDataIOStateTools.pick2(state, roi, {'featureColumns'}, []);
            spec.caseIDs = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'caseIDs'}, {}));
            spec.uiCaseIDModeSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'uiCaseIDModeSelection'}, ''));
            spec.caseIDMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'caseIDMode'}, 'legacy_spm'));
            spec.fileCaseIDsVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'fileCaseIDsVariable'}, ''));
            spec.matrixCaseIDsVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'matrixCaseIDsVariable'}, ''));
            spec.caseIDsVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'caseIDsVariable'}, ''));
            if strcmpi(spec.sourceFormat,'cat12_files') && isempty(spec.caseIDsVariable), spec.caseIDsVariable=spec.fileCaseIDsVariable; end
            if strcmpi(spec.sourceFormat,'workspace_matrix') && isempty(spec.caseIDsVariable), spec.caseIDsVariable=spec.matrixCaseIDsVariable; end
            spec.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'auxiliarySourceType'}, 'workspace'));
            spec.auxiliaryAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'auxiliaryAlignmentMode'}, 'case_id'));
            spec.auxiliaryVariableRoles = NMDataIOStateTools.pick2(state, roi, {'auxiliaryVariableRoles'}, struct());
            spec.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'auxiliaryTableFiles'}, {}));
            spec.roiSidecarFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiSidecarFile'}, ''));
            spec.roiIDColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiIDColumn'}, ''));
            spec.roiNameColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiNameColumn'}, ''));
            spec.roiHemisphereColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiHemisphereColumn'}, ''));
            spec.roiXColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiXColumn'}, ''));
            spec.roiYColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiYColumn'}, ''));
            spec.roiZColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'roiZColumn'}, ''));
            spec.uiSpatialKindSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'uiSpatialKindSelection'}, ''));
            spec.spatialKind = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'spatialKind'}, 'volumetric_atlas'));
            spec.atlasFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'atlasFile'}, ''));
            spec.lhAnnotationFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'lhAnnotationFile'}, ''));
            spec.rhAnnotationFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'rhAnnotationFile'}, ''));
            spec.lhSurfaceGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'lhSurfaceGeometryFile'}, ''));
            spec.rhSurfaceGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'rhSurfaceGeometryFile'}, ''));
            spec.cat12Atlas = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'cat12Atlas'}, ''));
            spec.cat12Measure = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'cat12Measure'}, ''));
            spec.covariateNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'covariateNames'}, {}));
            spec.covmanage_edit = NMDataIOStateTools.pick(state, {'covmanage_edit'}, NMDataIOStateTools.pick(roi, {'covmanage_edit','covariateMode'}, 1));
            spec.labelNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'labelNames','regressionLabelNames','desc_labels'}, {}));
            spec.uiGlobalModeSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'uiGlobalModeSelection'}, NMDataIOStateTools.pick2(state, roi, {'globalMode'}, 'none')));
            volumetricROI = strcmpi(spec.sourceFormat,'cat12_files') || strcmpi(spec.spatialKind,'volumetric_atlas');
            if volumetricROI, spec.globalMode = spec.uiGlobalModeSelection; else, spec.globalMode = 'none'; end
            spec.globalName = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'globalName'}, 'GlobalBrainVolume'));
            spec.globnorm = double(NMDataIOStateTools.pick2(state, roi, {'globnorm','globalMultiplier'}, 1));
            spec.globalSource = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'globalSource'}, 'user'));
            spec.globalUserSourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'globalUserSourceType'}, 'workspace'));
            spec.globalAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, roi, {'globalAlignmentMode'}, 'case_id'));
            spec.globalVariableRoles = NMDataIOStateTools.pick2(state, roi, {'globalVariableRoles'}, struct());
            spec.globalTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'globalTableFiles'}, {}));
            spec.weightingFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, roi, {'weightingFiles'}, {}));
            spec.caseAlignment = NMDataIOStateTools.pick(state, {'caseAlignment'}, struct());
            if ~isstruct(spec.caseAlignment), spec.caseAlignment = struct(); end
            if strcmp(spec.scope,'oocv')
                if ~isfield(spec,'labelsKnown')
                    labelRefs = {};
                    if isstruct(spec.auxiliaryVariableRoles) && isfield(spec.auxiliaryVariableRoles,'labels')
                        labelRefs = NMDataIOStateTools.roleRefCell(spec.auxiliaryVariableRoles.labels);
                    end
                    spec.labelsKnown = strcmpi(spec.labelMode,'legacy_groups') || ~isempty(labelRefs);
                end
                if ~isfield(spec,'containerField') || isempty(spec.containerField)
                    spec.containerField = NMDataIOStateTools.toChar(NMDataIOStateTools.pick(state, {'containerField'}, 'OOCV'));
                end
                if ~isfield(spec,'containerIndex') || isempty(spec.containerIndex)
                    spec.containerIndex = NMDataIOStateTools.pick(state, {'containerIndex'}, 1);
                end
            else
                spec.labelsKnown = true;
            end
        end

        function spec = stateToConnectivitySpec(state, NM, scope)
            % stateToConnectivitySpec  Convert browser connectivity state into backend import spec.
            %
            % spec = NMDataIOStateTools.stateToConnectivitySpec(state, NM, scope)
            % normalizes the connectivity source format, atlas/sidecar metadata,
            % labels, covariates, case-alignment, weighting-map settings, and
            % import target for NMDataIOConnectivityTools.  Workspace payloads are
            % kept as variable names; this adapter does not read matrix contents.
            %
            % state.importTarget: identifies whether the DataIO operation targets training, OOCV/application data, or a specific container.
            %
            % state.varind: target modality index used when no normalized importTarget supplies one.
            % state.caseAlignment: case-alignment contract and diagnostics propagated to the connectivity importer.
            % state.mode: classification/regression task-mode alias used when modeflag is absent.
            % state.label: connectivity modality description alias used when desc_data/description is absent.
            if nargin < 1 || isempty(state), state = struct(); end
            if nargin < 2 || isempty(NM), NM = struct(); end %#ok<INUSD>
            if nargin < 3 || isempty(scope)
                scope = 'training';
                if isfield(state,'importTarget') && isstruct(state.importTarget) && isfield(state.importTarget,'scope') && strcmpi(char(string(state.importTarget.scope)), 'oocv')
                    scope = 'oocv';
                end
            end
            scope = lower(strtrim(char(string(scope))));
            conn = NMDataIOStateTools.substructOrEmpty(state, {'connectivity','connectivitySource'});
            spec = struct();
            spec.scope = scope;
            if isfield(state,'importTarget') && isstruct(state.importTarget)
                tgt = NMDataIOImportTargetTools.normalize(NM, state, NMDataIOStateTools.pick(state, {'varind'}, []));
                spec.varind = tgt.varind;
                spec.importTarget = tgt;
                spec.targetMode = tgt.mode;
                if strcmpi(tgt.scope, 'oocv')
                    spec.scope = 'oocv';
                    spec.containerField = tgt.containerField;
                    spec.containerIndex = tgt.containerIndex;
                    spec.labelsKnown = logical(NMDataIOStateTools.fieldOr(tgt, 'labels_known', false));
                end
            else
                spec.varind = NMDataIOStateTools.pick(state, {'varind'}, NMDataIOStateTools.defaultVarind(NM));
                spec.targetMode = 'add';
            end
            spec.modeflag = NMDataIOStateTools.toChar(NMDataIOStateTools.pick(state, {'modeflag','mode'}, NMDataIOStateTools.inferModeflag(NM)));
            spec.description = NMDataIOStateTools.toChar(NMDataIOStateTools.pick(state, {'desc_data','description','label'}, 'Connectivity matrix modality'));
            spec.desc_data = spec.description;
            spec.sourceFormat = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'sourceFormat','connectivitySourceFormat','inputFormat'}, 'file_per_subject'));
            spec.matrixType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'matrixType','connectivityType'}, 'undirected'));
            spec.triangle = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'triangle','vectorizationTriangle'}, 'upper'));
            spec.includeDiagonal = logical(NMDataIOStateTools.pick2(state, conn, {'includeDiagonal','keepDiagonal'}, false));
            spec.subjectDim = double(NMDataIOStateTools.pick2(state, conn, {'subjectDim','subjectDimension'}, 1));
            spec.symmetryTolerance = double(NMDataIOStateTools.pick2(state, conn, {'symmetryTolerance','symmetricTolerance'}, 1e-8));
            spec.atlasFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasFile','atlas','nodeAtlasFile'}, ''));
            spec.atlasLabelFile = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelFile','atlasDescriptorFile','atlasSidecarFile','roiLabelFile','nodeSidecarFile'}, ''));
            spec.atlasLabelDelimiter = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelDelimiter','atlasDescriptorDelimiter','roiLabelDelimiter','nodeSidecarDelimiter'}, 'auto'));
            spec.atlasLabelHasHeader = NMDataIOStateTools.pick2(state, conn, {'atlasLabelHasHeader','atlasDescriptorHasHeader','roiLabelHasHeader','nodeSidecarHasHeader'}, 'auto');
            spec.atlasLabelIDColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelIDColumn','atlasDescriptorIDColumn','roiIDColumn','nodeIDColumn'}, ''));
            spec.atlasLabelNameColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelNameColumn','atlasDescriptorNameColumn','roiNameColumn','nodeNameColumn'}, ''));
            spec.atlasLabelXColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelXColumn','atlasDescriptorXColumn','roiXColumn','nodeXColumn','xColumn'}, ''));
            spec.atlasLabelYColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelYColumn','atlasDescriptorYColumn','roiYColumn','nodeYColumn','yColumn'}, ''));
            spec.atlasLabelZColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'atlasLabelZColumn','atlasDescriptorZColumn','roiZColumn','nodeZColumn','zColumn'}, ''));
            spec.nodeCoordinateSpace = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'nodeCoordinateSpace','coordinateSpace'}, 'MNI'));
            spec.nodeCoordinateUnits = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'nodeCoordinateUnits','coordinateUnits'}, 'mm'));
            spec.atlasNodeIDs = NMDataIOStateTools.pick2(state, conn, {'atlasNodeIDs','nodeIDs','roiIDs','atlasROIIDs'}, []);

            fmt = lower(strrep(strrep(spec.sourceFormat, '-', '_'), ' ', '_'));
            dataVar = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'dataVariable','dataVar','connectivityVariable','Y','data'}, ''));
            switch fmt
                case {'array3d','array_3d','3d'}
                    spec.sourceFormat = 'array3d';
                    spec.data = dataVar;
                case {'vectorized','edge_matrix','edges'}
                    spec.sourceFormat = 'vectorized';
                    spec.edgeMatrix = dataVar;
                    spec.nNodes = NMDataIOStateTools.pick2(state, conn, {'nNodes','numNodes'}, []);
                case {'table','edge_table'}
                    spec.sourceFormat = 'table';
                    tableVar = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'tableVariable','tableVar','dataVariable'}, dataVar));
                    spec.table = tableVar;
                    spec.caseColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'caseColumn','caseIDColumn','tableCaseIDColumn','case_edit'}, ''));
                    spec.edgeColumns = NMDataIOStateTools.pick2(state, conn, {'edgeColumns','featureColumns','features','feature_edit'}, {});
                    spec.nNodes = NMDataIOStateTools.pick2(state, conn, {'nNodes','numNodes'}, []);
                otherwise
                    spec.sourceFormat = 'file_per_subject';
                    spec.files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, conn, {'files','matrixFiles','connectivityFiles'}, {}));
                    spec.classFileLists = NMDataIOStateTools.pick2(state, conn, {'classFileLists','classFiles'}, {});
                    spec.matVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'matVariable','matrixVariable','variable'}, ''));
            end

            spec.caseIDMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'caseIDMode','caseIdMode','caseMode'}, 'filename'));
            if strcmpi(strrep(spec.caseIDMode,'-','_'), 'explicit')
                spec.caseIds = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, conn, {'caseIds','caseIDs','explicitCaseIDs'}, {}));
            else
                spec.caseIds = {};
            end
            spec.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'auxiliarySourceType'}, 'workspace'));
            spec.auxiliaryAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'auxiliaryAlignmentMode'}, 'case_id'));
            spec.auxiliaryVariableRoles = NMDataIOStateTools.pick2(state, conn, {'auxiliaryVariableRoles'}, struct());
            spec.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, conn, {'auxiliaryTableFiles'}, {}));
            spec.labelMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'labelMode','labelsMode'}, 'metadata'));
            spec.groupSizes = NMDataIOStateTools.pick2(state, conn, {'groupSizes','imageGroupSizes','classGroupSizes'}, []);
            spec.groupNames = NMDataIOStateTools.pick2(state, conn, {'groupNames','imageGroupNames','classGroupNames','desc_groups'}, {});
            spec.covariateNames = NMDataIOStateTools.pick2(state, conn, {'covariateNames','covnames','covnames_edit'}, {});
            spec.covmanage_edit = NMDataIOStateTools.pick(state, {'covmanage_edit'}, NMDataIOStateTools.pick(conn, {'covmanage_edit','covariateMode'}, 1));
            spec.labelNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, conn, {'labelNames','regressionLabelNames','desc_labels'}, {}));
            spec.caseAlignment = NMDataIOStateTools.pick(state, {'caseAlignment'}, struct());
            if ~isstruct(spec.caseAlignment), spec.caseAlignment = struct(); end
            if ~isfield(spec.caseAlignment,'missingCasePolicy') || isempty(spec.caseAlignment.missingCasePolicy), spec.caseAlignment.missingCasePolicy = 'fill_nan'; end
            if ~isfield(spec.caseAlignment,'allowMissingCasesAsNaN') || isempty(spec.caseAlignment.allowMissingCasesAsNaN), spec.caseAlignment.allowMissingCasesAsNaN = true; end
            if ~isfield(spec.caseAlignment,'idMappingMode') || isempty(spec.caseAlignment.idMappingMode), spec.caseAlignment.idMappingMode = 'direct'; end
            if ~isfield(spec.caseAlignment,'mappingApproved') || isempty(spec.caseAlignment.mappingApproved), spec.caseAlignment.mappingApproved = false; end

            spec.weightingMatrices = NMDataIOStateTools.pick2(state, conn, {'weightingMatrices','weightingMaps','Yw','weightingVariable'}, []);
            spec.weightingFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.pick2(state, conn, {'weightingFiles','weightingFileList'}, {}));
            spec.weightingMatVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'weightingMatVariable','weightingMATVariable','weightingFileVariable'}, ''));
            spec.weightingNames = NMDataIOStateTools.pick2(state, conn, {'weightingNames','weightingMapNames'}, {});
            spec.weightingNodeOrder = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'weightingNodeOrder','weightingOrder'}, 'training'));
            spec.weightingEdgeMode = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'weightingEdgeMode','edgeWeightingMode'}, 'auto'));
            spec.weightingOrientation = NMDataIOStateTools.toChar(NMDataIOStateTools.pick2(state, conn, {'weightingOrientation'}, 'maps_by_edges'));
            spec.subspace = NMDataIOStateTools.pick2(state, conn, {'subspace','connectivitySubspace','edgeSubspace','nodeSelection'}, struct('enabled',false));
            if ~isstruct(spec.subspace), spec.subspace = struct('enabled',false); end
        end

        function IO = defaultIO(NM, varind)
            % DEFAULTIO  Create a scalar legacy IO struct with DataIO import defaults.
            %
            %   IO = NMDataIOStateTools.defaultIO(NM, varind) defines the fixed
            %   field schema consumed by legacy DataIO code for matrix/table imports
            %   and seeds only session-level group/count/mode context from NM.
            %   Case-indexed labels, covariates, and case IDs belong to the current
            %   source state and are never inherited from the resident NM container.
            %   The explicit assignments avoid MATLAB
            %   struct-array expansion with nested structs and cell-valued defaults.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = NMDataIOStateTools.defaultVarind(NM); end

            % Build as plain scalar struct assignments rather than as one
            % large struct(...) constructor.  This avoids MATLAB struct-array
            % expansion edge cases when fields contain nested structs and
            % cell-valued defaults (covar_edit, ignore_edit, desc_groups).
            IO = struct();
            IO.varind = varind;
            IO.datasource = 'matrix';
            IO.sourceType = 'workspace';
            IO.groupmode = 1;
            IO.spm_file = '?';
            IO.spm_cov_avail = 0;
            IO.labelmanage_edit = '?';
            IO.nangroup = 2;
            IO.nan_subjects = 0;
            IO.survanal_flag = 2;
            IO.survanal_time = '?';
            IO.M_edit = '?';
            IO.badcoords = [];
            IO.brainmask = [];
            IO.surfaceImportMode = 'vertex_template';
            IO.surfaceTemplate = 'unknown';
            IO.surfaceHemisphere = 'auto';
            IO.surfaceGeometryFile = '';
            IO.surfaceInflatedGeometryFile = '';
            IO.surfaceGeometryContract = struct();
            IO.wfu_flag = 2;
            IO.globscale = 1;
            IO.globnorm = 1;
            IO.globvar_edit = '?';
            IO.matrix_edit = '?';
            IO.tableVariable = '?';
            IO.matFiles = {};
            IO.variableRoles = struct('caseId',{{}},'labels',{{}},'features',{{}},'featureNames',{{}},'covariates',{{}},'covariateNames',{{}});
            IO.metadataAlignmentMode = 'case_id';
            IO.featureMappingMode = 'automatic';
            IO.databaseConnector = 'sqlite_file';
            IO.databaseUrl = '?';
            IO.databaseFile = '?';
            IO.databaseUser = '?';
            IO.databasePassword = '?';
            IO.databaseName = '?';
            IO.databaseSchema = '?';
            IO.databaseTable = '?';
            IO.databaseUseQuery = false;
            IO.databaseQuery = '?';
            IO.label_edit = '?';
            IO.case_edit = '?';
            IO.col_edit = '?';
            IO.covnames_edit = '?';
            IO.requireFeatureNames = false;
            IO.requireCovariateNames = false;
            IO.delimit = 'tab';
            IO.sheet = '?';
            IO.sheets = {};
            IO.headerRow = [];
            IO.headerAutoDetect = false;
            IO.reread_mat = false;
            IO.uniquelim = 15;
            IO.covar_edit = {};
            IO.ignore_edit = {};
            IO.feature_edit = {};
            IO.covmanage_edit = 1;
            IO.nanMapper = NMDataIOStateTools.defaultNaNMapper();
            IO.compatibilityMode = 'legacy';
            IO.completed = false;
            IO.modeflag = NMDataIOStateTools.inferModeflag(NM);
            IO.labels_known = true;
            IO.oocvflag = false;
            IO.desc_data = '?';
            IO.desc_groups = {'?'};

            if isfield(NM,'Y') && ~isempty(NM.Y)
                if isfield(NM,'n_subjects'), IO.n_samples = numel(NM.n_subjects); IO.n_subjects = NM.n_subjects; end
                if isfield(NM,'n_subjects_all'), IO.n_subjects_all = NM.n_subjects_all; end
                if isfield(NM,'groupnames'), IO.desc_groups = NM.groupnames; end
                if isfield(NM,'modeflag'), IO.modeflag = NM.modeflag; end
            end
        end

        function state = ioToState(IO)
            % IOTOSTATE  Reconstruct browser/API DataIO state from a legacy IO struct.
            %
            %   state = NMDataIOStateTools.ioToState(IO) maps legacy IO fields back
            %   into matrix, connectivity, image/surface, selection, preview,
            %   case-alignment, and import-target state sections.  It also repairs
            %   stale connectivity-draft markers when matrix/table evidence shows the
            %   saved draft is not a real connectivity import.  No NM data are mutated.
            if nargin < 1 || isempty(IO), IO = struct(); end

            % Build with explicit assignments.  Do not use struct(...) with
            % cell-valued defaults here: in several MATLAB releases this can
            % accidentally create struct arrays or trigger constructor edge
            % cases when {} is used as a field value.
            state = struct();
            state.datasource = NMDataIOStateTools.fieldOr(IO,'datasource','matrix');
            state.sourceType = NMDataIOStateTools.normalizeSourceType(NMDataIOStateTools.fieldOr(IO,'sourceType',''), NMDataIOStateTools.fieldOr(IO,'groupmode',1));
            state.groupmode = NMDataIOStateTools.fieldOr(IO,'groupmode',1);
            state.varind = NMDataIOStateTools.fieldOr(IO,'varind',1);
            state.modeflag = NMDataIOStateTools.fieldOr(IO,'modeflag','classification');
            state.labels_known = NMDataIOStateTools.fieldOr(IO,'labels_known',true);
            state.oocvflag = NMDataIOStateTools.fieldOr(IO,'oocvflag',false);
            if isfield(IO,'importTarget') && isstruct(IO.importTarget)
                state.importTarget = IO.importTarget;
            else
                state.importTarget = NMDataIOImportTargetTools.normalize(struct(), state, state.varind);
            end
            state.desc_data = NMDataIOStateTools.fieldOr(IO,'desc_data','?');
            state.desc_groups = NMDataIOStateTools.fieldOr(IO,'desc_groups',{'?'});

            if NMDataIOStateTools.isConnectivityMatrixDraftCorruption(IO)
                repairedSourceType = NMDataIOStateTools.inferMatrixSourceTypeFromIO(IO);
                state.datasource = 'matrix';
                state.sourceType = repairedSourceType;
                state.groupmode = NMDataIOStateTools.groupmodeFromSourceType(repairedSourceType, NMDataIOStateTools.fieldOr(IO,'groupmode',4));
            end

            % Rehydrate the complete current matrix-state schema once, using
            % its existing producer. Historical IO supplies only populated
            % overrides; absent and empty persisted fields retain their
            % original rehydration defaults (not new-editor defaults).
            matrixDefaults = NMDataIOStateTools.defaultMatrixState(struct(), state.varind);
            state.matrix = matrixDefaults.matrix;
            state.matrix.headerAutoDetect = false;
            state.matrix.tabularFilters = struct([]);
            state.matrix.caseAlignment = struct();
            matrixFields = fieldnames(state.matrix);
            for k = 1:numel(matrixFields)
                name = matrixFields{k};
                % nm2-allow: persisted NM1.4 settings omit keys or store empty values; restore the original defaults
                if isfield(IO,name) && ~isempty(IO.(name))
                    state.matrix.(name) = IO.(name);
                end
            end
            state.matrix.sourceType = state.sourceType;
            state.matrix.variableRoles = NMDataIOStateTools.variableRoleKeyRefsForState(state.matrix.variableRoles);
            state.matrix.metadataAlignmentMode = NMDataIOStateTools.normalizeSourceBlockAlignmentMode(state.matrix.metadataAlignmentMode);
            % nm2-allow: historical feature mapping values retain the original case and whitespace normalization
            state.matrix.featureMappingMode = lower(strtrim(NMDataIOStateTools.toChar(state.matrix.featureMappingMode)));
            if ~strcmp(state.matrix.featureMappingMode,'manual'), state.matrix.featureMappingMode = 'automatic'; end
            if strcmp(state.sourceType,'database') || state.groupmode == 6
                dbInfo = NMDataIODatabaseTools.connectionInfo(IO);
                state.matrix.databaseConnector = dbInfo.connector;
                state.matrix.databaseUrl = dbInfo.url;
                state.matrix.databaseFile = dbInfo.file;
                state.matrix.databaseUser = dbInfo.user;
                state.matrix.databaseName = dbInfo.database;
                state.matrix.databaseSchema = dbInfo.schema;
                state.matrix.databaseTable = dbInfo.table;
                state.matrix.databaseUseQuery = dbInfo.useQuery;
                state.matrix.databaseQuery = dbInfo.query;
            end
            state.covmanage_edit = NMDataIOStateTools.fieldOr(IO,'covmanage_edit',1);
            state.caseAlignment = state.matrix.caseAlignment;
            if isfield(IO,'preview') && isstruct(IO.preview)
                state.preview = IO.preview;
                state.matrix.preview = state.preview;
            end

            state.selection = struct();
            state.selection.selFeats = NMDataIOStateTools.fieldOr(IO,'selFeats',[]);
            state.selection.selCases = NMDataIOStateTools.fieldOr(IO,'selCases',[]);

            if NMDataIOStateTools.isConnectivityIO(IO)
                spec = struct();
                if isfield(IO,'connectivitySpec') && isstruct(IO.connectivitySpec)
                    spec = IO.connectivitySpec;
                elseif isfield(IO,'input_settings') && isstruct(IO.input_settings) && ...
                        isfield(IO.input_settings,'connectivitySpec') && isstruct(IO.input_settings.connectivitySpec)
                    spec = IO.input_settings.connectivitySpec;
                else
                    spec = IO;
                end
                state.datasource = 'matrix';
                state.sourceType = 'connectivity';
                state.groupmode = 1;
                state.matrix.sourceType = 'connectivity';
                state.matrix.M_edit = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'data', ...
                    NMDataIOStateTools.fieldOr(spec,'edgeMatrix', NMDataIOStateTools.fieldOr(spec,'table','?'))));
                if isfield(spec,'description') && ~isempty(spec.description)
                    state.desc_data = NMDataIOStateTools.toChar(spec.description);
                elseif isfield(spec,'desc_data') && ~isempty(spec.desc_data)
                    state.desc_data = NMDataIOStateTools.toChar(spec.desc_data);
                end
                conn = struct();
                conn.sourceFormat = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'sourceFormat','file_per_subject'));
                conn.matrixType = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'matrixType','undirected'));
                conn.triangle = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'triangle','upper'));
                conn.includeDiagonal = logical(NMDataIOStateTools.fieldOr(spec,'includeDiagonal',false));
                conn.subjectDim = NMDataIOStateTools.fieldOr(spec,'subjectDim',1);
                conn.nNodes = NMDataIOStateTools.fieldOr(spec,'nNodes',[]);
                conn.symmetryTolerance = NMDataIOStateTools.fieldOr(spec,'symmetryTolerance',1e-8);
                fmt = lower(strrep(strrep(conn.sourceFormat,'-','_'),' ', '_'));
                if any(strcmp(fmt, {'array3d','array_3d','3d'}))
                    conn.sourceFormat = 'array3d';
                    conn.dataVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'data', NMDataIOStateTools.fieldOr(spec,'dataVariable','')));
                elseif any(strcmp(fmt, {'vectorized','edge_matrix','edges'}))
                    conn.sourceFormat = 'vectorized';
                    conn.dataVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'edgeMatrix', NMDataIOStateTools.fieldOr(spec,'dataVariable','')));
                elseif any(strcmp(fmt, {'table','edge_table'}))
                    conn.sourceFormat = 'table';
                    conn.tableVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'table', NMDataIOStateTools.fieldOr(spec,'tableVariable','')));
                    conn.caseColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'caseColumn',''));
                    conn.edgeColumns = NMDataIOStateTools.fieldOr(spec,'edgeColumns',{});
                else
                    conn.sourceFormat = 'file_per_subject';
                    conn.files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'files',{}));
                    conn.classFileLists = NMDataIOStateTools.fieldOr(spec,'classFileLists',{});
                    conn.matVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'matVariable',''));
                end
                conn.atlasFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasFile',''));
                conn.atlasLabelFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelFile',''));
                conn.atlasLabelDelimiter = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelDelimiter','auto'));
                conn.atlasLabelHasHeader = NMDataIOStateTools.fieldOr(spec,'atlasLabelHasHeader','auto');
                conn.atlasLabelIDColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelIDColumn',''));
                conn.atlasLabelNameColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelNameColumn',''));
                conn.atlasLabelXColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelXColumn',''));
                conn.atlasLabelYColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelYColumn',''));
                conn.atlasLabelZColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasLabelZColumn',''));
                conn.nodeCoordinateSpace = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'nodeCoordinateSpace','MNI'));
                conn.nodeCoordinateUnits = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'nodeCoordinateUnits','mm'));
                conn.caseIDMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'caseIDMode','filename'));
                conn.caseIds = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'caseIds',{}));
                conn.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'auxiliarySourceType','workspace'));
                conn.auxiliaryAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'auxiliaryAlignmentMode','case_id'));
                conn.auxiliaryVariableRoles = NMDataIOStateTools.fieldOr(spec,'auxiliaryVariableRoles',struct());
                conn.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'auxiliaryTableFiles',{}));
                conn.labelMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'labelMode','metadata'));
                if isempty(conn.labelMode) || strcmp(conn.labelMode,'?')
                    if isfield(conn,'classFileLists') && ~isempty(conn.classFileLists), conn.labelMode = 'legacy_groups'; else, conn.labelMode = 'metadata'; end
                end
                conn.groupSizes = NMDataIOStateTools.fieldOr(spec,'groupSizes',[]);
                conn.groupNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'groupNames',{}));
                conn.covariateNames = NMDataIOStateTools.fieldOr(spec,'covariateNames',{});
                conn.labelNames = NMDataIOStateTools.fieldOr(spec,'labelNames',{});
                conn.weightingMatrices = NMDataIOStateTools.fieldOr(spec,'weightingMatrices','');
                conn.weightingFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'weightingFiles',{}));
                conn.weightingMatVariable = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'weightingMatVariable',''));
                conn.weightingNames = NMDataIOStateTools.fieldOr(spec,'weightingNames',{});
                conn.weightingNodeOrder = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'weightingNodeOrder','training'));
                conn.weightingEdgeMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'weightingEdgeMode','auto'));
                state.connectivity = conn;
                state.importTarget = NMDataIOStateTools.fieldOr(IO,'importTarget', state.importTarget);
            end

            if NMDataIOStateTools.hasExplicitROISource(IO) || ...
                    (isfield(IO,'input_settings') && isstruct(IO.input_settings) && isfield(IO.input_settings,'roiSpec'))
                if isfield(IO,'roiSpec') && isstruct(IO.roiSpec)
                    spec=IO.roiSpec;
                elseif isfield(IO,'input_settings') && isstruct(IO.input_settings) && ...
                        isfield(IO.input_settings,'roiSpec') && isstruct(IO.input_settings.roiSpec)
                    spec=IO.input_settings.roiSpec;
                else
                    spec=struct();
                end
                state.datasource='matrix'; state.sourceType='roi'; state.groupmode=1; state.matrix.sourceType='roi';
                roi=struct();
                roi.sourceFamily='roi'; roi.sourceType='roi';
                roi.sourceFormat=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'sourceFormat','workspace_matrix'));
                roi.uiLabelModeSelection=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'uiLabelModeSelection',''));
                roi.labelMode=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'labelMode','metadata'));
                roi.files=NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'files',{}));
                roi.vectorFiles=NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'vectorFiles',{}));
                roi.classFileLists=NMDataIOStateTools.fieldOr(spec,'classFileLists',{});
                roi.groupNames=NMDataIOStateTools.fieldOr(spec,'groupNames',{});
                roi.groupSizes=NMDataIOStateTools.fieldOr(spec,'groupSizes',[]);
                roi.activeClassIndex=NMDataIOStateTools.fieldOr(spec,'activeClassIndex',0);
                roi.dataVariable=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'dataVariable',''));
                roi.tableVariable=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'tableVariable',''));
                roi.tableFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'tableFile',''));
                roi.uiCaseIDModeSelection=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'uiCaseIDModeSelection',''));
                roi.caseIDMode=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'caseIDMode','legacy_spm'));
                roi.fileCaseIDsVariable=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'fileCaseIDsVariable',''));
                roi.matrixCaseIDsVariable=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'matrixCaseIDsVariable',''));
                roi.caseIDsVariable=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'caseIDsVariable',''));
                roi.auxiliarySourceType=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'auxiliarySourceType','workspace'));
                roi.auxiliaryAlignmentMode=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'auxiliaryAlignmentMode','case_id'));
                roi.auxiliaryVariableRoles=NMDataIOStateTools.fieldOr(spec,'auxiliaryVariableRoles',struct());
                roi.auxiliaryTableFiles=NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'auxiliaryTableFiles',{}));
                roi.caseColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'caseColumn',''));
                roi.featureColumns=NMDataIOStateTools.fieldOr(spec,'featureColumns',[]);
                roi.roiSidecarFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiSidecarFile',''));
                roi.roiIDColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiIDColumn',''));
                roi.roiNameColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiNameColumn',''));
                roi.roiHemisphereColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiHemisphereColumn',''));
                roi.roiXColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiXColumn',''));
                roi.roiYColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiYColumn',''));
                roi.roiZColumn=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'roiZColumn',''));
                roi.uiSpatialKindSelection=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'uiSpatialKindSelection',''));
                roi.spatialKind=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'spatialKind','volumetric_atlas'));
                roi.atlasFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'atlasFile',''));
                roi.lhAnnotationFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'lhAnnotationFile',''));
                roi.rhAnnotationFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'rhAnnotationFile',''));
                roi.lhSurfaceGeometryFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'lhSurfaceGeometryFile',''));
                roi.rhSurfaceGeometryFile=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'rhSurfaceGeometryFile',''));
                roi.cat12Atlas=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'cat12Atlas',''));
                roi.cat12Measure=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'cat12Measure',''));
                roi.covariateNames=NMDataIOStateTools.fieldOr(spec,'covariateNames',{});
                roi.labelNames=NMDataIOStateTools.fieldOr(spec,'labelNames',{});
                roi.uiGlobalModeSelection=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'uiGlobalModeSelection',NMDataIOStateTools.fieldOr(spec,'globalMode','none')));
                roi.globalMode=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'globalMode','none'));
                roi.globalName=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'globalName','GlobalBrainVolume'));
                roi.globnorm=NMDataIOStateTools.fieldOr(spec,'globnorm',1);
                roi.globalSource=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'globalSource','user'));
                roi.globalUserSourceType=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'globalUserSourceType','workspace'));
                roi.globalAlignmentMode=NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(spec,'globalAlignmentMode','case_id'));
                roi.globalVariableRoles=NMDataIOStateTools.fieldOr(spec,'globalVariableRoles',struct());
                roi.globalTableFiles=NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'globalTableFiles',{}));
                roi.weightingFiles=NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(spec,'weightingFiles',{}));
                state.roi=roi;
                if isfield(IO,'roiProvenance') && ~isempty(IO.roiProvenance), state.matrix.roiProvenance=IO.roiProvenance; end
                state.importTarget=NMDataIOStateTools.fieldOr(IO,'importTarget',state.importTarget);
            end

            if NMDataIOStateTools.isImageIO(IO)
                state.datasource = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'datasource','nifti'));
                if strcmpi(state.datasource,'image'), state.datasource = 'nifti'; end
                state.sourceType = 'image-list';
                state.groupmode = -2;
                img = struct();
                img.imageFiles = NMDataIOStateTools.imageFilesFromIO(IO);
                img.maskFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'maskFile', NMDataIOStateTools.fieldOr(IO,'brainmask','')));
                img.brainmask = img.maskFile;
                img.caseIDMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'caseIDMode','legacy_spm'));
                if strcmpi(strrep(img.caseIDMode,'-','_'),'explicit')
                    img.caseIds = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'caseIds', NMDataIOStateTools.fieldOr(IO,'imageCaseIDSpec', NMDataIOStateTools.fieldOr(IO,'explicitCaseIDs',{}))));
                else
                    img.caseIds = {};
                end
                img.auxiliarySourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'auxiliarySourceType','workspace'));
                img.auxiliaryAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'auxiliaryAlignmentMode','case_id'));
                img.auxiliaryVariableRoles = NMDataIOStateTools.fieldOr(IO,'auxiliaryVariableRoles',struct());
                img.auxiliaryTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'auxiliaryTableFiles',{}));
                img.groupSizes = NMDataIOStateTools.numericVector(NMDataIOStateTools.fieldOr(IO,'groupSizes', NMDataIOStateTools.fieldOr(IO,'imageGroupSizes', NMDataIOStateTools.fieldOr(IO,'n_subjects',[]))));
                img.imageGroupSizes = img.groupSizes;
                img.groupNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'groupNames', NMDataIOStateTools.fieldOr(IO,'imageGroupNames', NMDataIOStateTools.fieldOr(IO,'desc_groups',{}))));
                img.imageGroupNames = img.groupNames;
                img.classFileLists = NMDataIOStateTools.imageClassFileListsFromIO(IO, img.imageFiles, img.groupNames, img.groupSizes);
                storedLabelMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'labelMode',''));
                if isempty(storedLabelMode) || strcmp(storedLabelMode,'?')
                    mf = lower(NMDataIOStateTools.toChar(state.modeflag));
                    if strcmp(mf,'classification') && (~isempty(img.groupSizes) || ~isempty(img.classFileLists))
                        storedLabelMode = 'legacy_groups';
                    else
                        storedLabelMode = 'metadata';
                    end
                end
                img.labelMode = storedLabelMode;
                img.labelNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'labelNames', NMDataIOStateTools.fieldOr(IO,'regressionLabelNames', NMDataIOStateTools.fieldOr(IO,'desc_labels', NMDataIOStateTools.fieldOr(IO,'labelnames',{})))));
                img.regressionLabelNames = img.labelNames;
                img.labelNamesSource = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'labelNamesSource','manual'));
                img.covariateNames = NMDataIOStateTools.fieldOr(IO,'covariateNames', NMDataIOStateTools.fieldOr(IO,'covnames',{}));
                img.uiGlobalModeSelection = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'uiGlobalModeSelection',NMDataIOStateTools.fieldOr(IO,'globalMode','none')));
                img.globalMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'globalMode','none'));
                img.globalSource = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'globalSource','user'));
                img.globalUserSourceType = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'globalUserSourceType','workspace'));
                img.globalAlignmentMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'globalAlignmentMode','case_id'));
                img.globalVariableRoles = NMDataIOStateTools.fieldOr(IO,'globalVariableRoles',struct());
                img.globalTableFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'globalTableFiles',{}));
                img.globalName = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'globalName','GlobalSignal'));
                img.globnorm = NMDataIOStateTools.fieldOr(IO,'globnorm',1);
                img.threshop = NMDataIOStateTools.fieldOr(IO,'threshop',{'gt'});
                img.threshval = NMDataIOStateTools.fieldOr(IO,'threshval',0);
                img.threshlabels = NMDataIOStateTools.fieldOr(IO,'threshlabels',{'Bin Mask'});
                img.weightingFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'weightingFiles', NMDataIOStateTools.fieldOr(IO,'Pw',{})));
                img.spaceDefType = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'spaceDefType','brainmask'));
                img.atlasImportMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasImportMode','voxelwise'));
                img.atlasCollapseMethod = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasCollapseMethod','soft_mean'));
                img.excludeSubjectZeros = logical(NMDataIOStateTools.fieldOr(IO,'excludeSubjectZeros',true));
                img.atlasLabelNames = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'atlasLabelNames',{}));
                img.atlasLabelFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasLabelFile', NMDataIOStateTools.fieldOr(IO,'atlasDescriptorFile', NMDataIOStateTools.fieldOr(IO,'roiLabelFile',''))));
                img.atlasLabelDelimiter = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasLabelDelimiter', NMDataIOStateTools.fieldOr(IO,'atlasDescriptorDelimiter','auto')));
                img.atlasLabelHasHeader = NMDataIOStateTools.fieldOr(IO,'atlasLabelHasHeader', NMDataIOStateTools.fieldOr(IO,'atlasDescriptorHasHeader','auto'));
                img.atlasLabelIDColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasLabelIDColumn', NMDataIOStateTools.fieldOr(IO,'atlasDescriptorIDColumn','')));
                img.atlasLabelNameColumn = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'atlasLabelNameColumn', NMDataIOStateTools.fieldOr(IO,'atlasDescriptorNameColumn','')));
                img.atlasLabelDescriptor = NMDataIOStateTools.fieldOr(IO,'atlasLabelDescriptor', NMDataIOStateTools.fieldOr(IO,'atlasInfo',struct()));
                img.surfaceImportMode = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceImportMode','vertex_template'));
                img.surfaceTemplate = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceTemplate','unknown'));
                img.surfaceHemisphere = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceHemisphere','auto'));
                img.surfaceGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceGeometryFile', NMDataIOStateTools.fieldOr(IO,'surfaceDisplayMeshFile','')));
                img.surfaceInflatedGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceInflatedGeometryFile',''));
                img.surfaceGeometryContract = NMDataIOStateTools.fieldOr(IO,'surfaceGeometryContract',struct());
                img.surfaceGeometryIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceGeometryIdentity',''));
                img.surfaceInflatedGeometryIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceInflatedGeometryIdentity',''));
                img.surfaceTopologyIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceTopologyIdentity',''));
                img.surfaceVertexOrderIdentity = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceVertexOrderIdentity',''));
                img.surfaceInflatedValidated = logical(NMDataIOStateTools.fieldOr(IO,'surfaceInflatedValidated',false));
                img.surfaceRoiCollapseMethod = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceRoiCollapseMethod','mean'));
                img.surfaceRoiLHScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiLHScalarFiles',{}));
                img.surfaceRoiLHAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiLHAnnotFiles',{}));
                img.surfaceRoiLHGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceRoiLHGeometryFile',''));
                img.surfaceRoiRHScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiRHScalarFiles',{}));
                img.surfaceRoiRHAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiRHAnnotFiles',{}));
                img.surfaceRoiRHGeometryFile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'surfaceRoiRHGeometryFile',''));
                img.surfaceRoiScalarFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiScalarFiles',{}));
                img.surfaceRoiAnnotFiles = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'surfaceRoiAnnotFiles',{}));
                state.image = img;
                if strcmpi(state.datasource,'surf')
                    state.sourceType = 'surface-list';
                    state.matrix.sourceType = 'surface-list';
                else
                    state.matrix.sourceType = 'image-list';
                end
            end
        end

        function tf = isROIState(state)
            % isROIState  Test whether a browser/API state explicitly declares direct ROI input.
            tf = false;
            if nargin < 1 || ~isstruct(state), return; end
            tf = NMDataIOStateTools.hasExplicitROISource(state);
            if ~tf && isfield(state,'input_settings') && isstruct(state.input_settings)
                tf = NMDataIOStateTools.hasExplicitROISource(state.input_settings) || ...
                    isfield(state.input_settings,'roiSpec');
            end
        end

        function tf = isConnectivityState(state)
            % isConnectivityState  Test whether a browser/API state encodes connectivity input.
            %
            % tf = NMDataIOStateTools.isConnectivityState(state) returns true for
            % explicit connectivity source markers at the state level or for nested
            % input_settings that satisfy the legacy connectivity-IO detector.
            %
            % state.input_settings: stores persisted DataIO provenance used for resume, diagnostics and code export.
            tf = false;
            if nargin < 1 || ~isstruct(state), return; end
            if NMDataIOStateTools.hasExplicitConnectivitySource(state)
                tf = true;
                return;
            end
            if isfield(state,'input_settings') && isstruct(state.input_settings)
                tf = NMDataIOStateTools.isConnectivityIO(state.input_settings);
            end
        end

        function tf = isConnectivityIO(IO)
            % ISCONNECTIVITYIO  Test whether a legacy IO-like struct represents connectivity input.
            %
            %   tf = NMDataIOStateTools.isConnectivityIO(IO) recognizes explicit
            %   connectivity source markers, connectivitySpec fields, or nested
            %   input_settings connectivity specs.  Stale matrix/table drafts with
            %   corrupted connectivity markers are deliberately excluded.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            if NMDataIOStateTools.isConnectivityMatrixDraftCorruption(IO)
                return;
            end
            if NMDataIOStateTools.hasExplicitConnectivitySource(IO) || isfield(IO,'connectivitySpec')
                tf = true;
                return;
            end
            if isfield(IO,'input_settings') && isstruct(IO.input_settings)
                tf = NMDataIOStateTools.isConnectivityIO(IO.input_settings);
            end
        end

        function tf = hasExplicitROISource(s)
            tf = false;
            if nargin < 1 || ~isstruct(s), return; end
            candidates = {s};
            if isfield(s,'matrix') && isstruct(s.matrix), candidates{end+1}=s.matrix; end %#ok<AGROW>
            if isfield(s,'roi') && isstruct(s.roi), candidates{end+1}=s.roi; end %#ok<AGROW>
            for ii=1:numel(candidates)
                c=candidates{ii};
                for f={'sourceFamily','sourceType'}
                    if isfield(c,f{1}) && ~isempty(c.(f{1})) && strcmpi(strtrim(NMDataIOStateTools.toChar(c.(f{1}))),'roi')
                        tf=true;
                        return;
                    end
                end
            end
        end

        function tf = hasExplicitConnectivitySource(s)
            % HASEXPLICITCONNECTIVITYSOURCE  Detect explicit connectivity source markers.
            %
            %   tf = NMDataIOStateTools.hasExplicitConnectivitySource(s) checks the
            %   top-level, matrix substate, and connectivity substate sourceFamily or
            %   sourceType fields for the canonical value 'connectivity'.
            tf = false;
            if nargin < 1 || ~isstruct(s), return; end
            if NMDataIOStateTools.fieldEqualsConnectivity(s, 'sourceFamily') || ...
                    NMDataIOStateTools.fieldEqualsConnectivity(s, 'sourceType')
                tf = true;
                return;
            end
            if isfield(s,'matrix') && isstruct(s.matrix) && ...
                    (NMDataIOStateTools.fieldEqualsConnectivity(s.matrix, 'sourceFamily') || ...
                     NMDataIOStateTools.fieldEqualsConnectivity(s.matrix, 'sourceType'))
                tf = true;
                return;
            end
            if isfield(s,'connectivity') && isstruct(s.connectivity) && ...
                    (NMDataIOStateTools.fieldEqualsConnectivity(s.connectivity, 'sourceFamily') || ...
                     NMDataIOStateTools.fieldEqualsConnectivity(s.connectivity, 'sourceType'))
                tf = true;
                return;
            end
        end

        function tf = fieldEqualsConnectivity(s, fieldName)
            % FIELDEQUALSCONNECTIVITY  Compare one struct field with the connectivity source token.
            %
            %   tf = NMDataIOStateTools.fieldEqualsConnectivity(s, fieldName)
            %   returns true only when the named field exists, is non-empty, and
            %   normalizes to the lowercase token 'connectivity'.
            tf = false;
            if ~isstruct(s) || ~isfield(s, fieldName) || isempty(s.(fieldName)), return; end
            v = lower(strtrim(NMDataIOStateTools.toChar(s.(fieldName))));
            tf = strcmp(v, 'connectivity');
        end

        function tf = isConnectivityMatrixDraftCorruption(IO)
            % ISCONNECTIVITYMATRIXDRAFTCORRUPTION  Identify stale connectivity-marked matrix drafts.
            %
            %   tf = NMDataIOStateTools.isConnectivityMatrixDraftCorruption(IO)
            %   flags IO structs that carry connectivity markers but no meaningful
            %   connectivity payload while still containing matrix/table source
            %   evidence.  Callers use this to restore the matrix source family.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            if ~(NMDataIOStateTools.hasExplicitConnectivitySource(IO) || isfield(IO,'connectivitySpec'))
                return;
            end
            if NMDataIOStateTools.hasMeaningfulConnectivityPayload(IO)
                return;
            end
            tf = NMDataIOStateTools.hasMatrixTableEvidence(IO);
        end

        function tf = hasMeaningfulConnectivityPayload(IO)
            % HASMEANINGFULCONNECTIVITYPAYLOAD  Check for substantive connectivity spec content.
            %
            %   tf = NMDataIOStateTools.hasMeaningfulConnectivityPayload(IO)
            %   scans connectivitySpec, input_settings.connectivitySpec, or IO itself
            %   for files, matrices, atlas metadata, generic auxiliary-role configuration, cases,
            %   weighting data, or edge descriptors that are not placeholder values.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            specs = {};
            if isfield(IO,'connectivitySpec') && isstruct(IO.connectivitySpec)
                specs{end+1} = IO.connectivitySpec; %#ok<AGROW>
            end
            if isfield(IO,'input_settings') && isstruct(IO.input_settings) && ...
                    isfield(IO.input_settings,'connectivitySpec') && isstruct(IO.input_settings.connectivitySpec)
                specs{end+1} = IO.input_settings.connectivitySpec; %#ok<AGROW>
            end
            if isempty(specs)
                specs = {IO};
            end
            fields = {'files','classFileLists','data','edgeMatrix','table','atlasFile','atlasLabelFile', ...
                'auxiliaryVariableRoles','auxiliaryTableFiles','caseIds','weightingFiles','weightingMatrices', ...
                'matVariable','edgeColumns'};
            for si = 1:numel(specs)
                spec = specs{si};
                if ~isstruct(spec), continue; end
                for fi = 1:numel(fields)
                    f = fields{fi};
                    if isfield(spec, f) && NMDataIOStateTools.valueIsMeaningful(spec.(f))
                        tf = true;
                        return;
                    end
                end
            end
        end

        function tf = hasMatrixTableEvidence(IO)
            % HASMATRIXTABLEEVIDENCE  Detect matrix/table source fields inside an IO draft.
            %
            %   tf = NMDataIOStateTools.hasMatrixTableEvidence(IO) checks database,
            %   table-variable, and matrix/table file indicators and falls back to
            %   inferMatrixSourceTypeFromIO to recognize non-workspace table sources.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            if NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseFile','')) || ...
                    NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseTable','')) || ...
                    NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseQuery',''))
                tf = true;
                return;
            end
            if NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'tableVariable',''))
                tf = true;
                return;
            end
            src = NMDataIOStateTools.inferMatrixSourceTypeFromIO(IO);
            tf = any(strcmp(src, {'tablefile','matfile','tablevar','database'}));
        end

        function sourceType = inferMatrixSourceTypeFromIO(IO)
            % INFERMATRIXSOURCETYPEFROMIO  Infer the canonical matrix/table source type from IO fields.
            %
            %   sourceType = NMDataIOStateTools.inferMatrixSourceTypeFromIO(IO)
            %   returns workspace, matfile, tablefile, tablevar, or database based on
            %   populated database/table fields, M_edit file extensions, and
            %   matrix_edit.  Placeholder strings such as '?' are ignored.
            sourceType = 'workspace';
            if nargin < 1 || ~isstruct(IO), return; end
            if NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseFile','')) || ...
                    NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseTable','')) || ...
                    NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'databaseQuery',''))
                sourceType = 'database';
                return;
            end
            if NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'tableVariable',''))
                sourceType = 'tablevar';
                return;
            end
            mfile = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'M_edit',''));
            if NMDataIOStateTools.valueIsMeaningful(mfile)
                [~,~,ext] = fileparts(mfile);
                ext = lower(ext);
                if any(strcmp(ext, {'.csv','.tsv','.txt','.xls','.xlsx','.xlsm'}))
                    sourceType = 'tablefile';
                    return;
                elseif strcmp(ext, '.mat')
                    sourceType = 'matfile';
                    return;
                end
            end
            if NMDataIOStateTools.valueIsMeaningful(NMDataIOStateTools.fieldOr(IO,'matrix_edit',''))
                sourceType = 'matfile';
            end
        end

        function tf = valueIsMeaningful(v)
            % VALUEISMEANINGFUL  Determine whether a value carries non-placeholder content.
            %
            %   tf = NMDataIOStateTools.valueIsMeaningful(v) treats empty values,
            %   '?', 'none', and '[]' strings as absent; cells are checked
            %   recursively, structs are meaningful when they have fields, and
            %   numeric/logical arrays are meaningful when non-empty.
            tf = false;
            if isempty(v), return; end
            if ischar(v) || isstring(v)
                c = strtrim(char(string(v(1))));
                tf = ~isempty(c) && ~strcmp(c,'?') && ~strcmpi(c,'none') && ~strcmp(c,'[]');
            elseif iscell(v)
                for ii = 1:numel(v)
                    if NMDataIOStateTools.valueIsMeaningful(v{ii})
                        tf = true;
                        return;
                    end
                end
            elseif isstruct(v)
                tf = ~isempty(fieldnames(v));
            elseif isnumeric(v) || islogical(v)
                tf = ~isempty(v);
            else
                tf = true;
            end
        end

        function tf = isImageIO(IO)
            % ISIMAGEIO  Test whether a legacy IO struct describes image or surface files.
            %
            %   tf = NMDataIOStateTools.isImageIO(IO) recognizes NIfTI/SPM/surface
            %   datasource values, image-list or surface-list source types, and the
            %   legacy image file/mask fields used by voxel and surface import drafts.
            tf = false;
            if nargin < 1 || ~isstruct(IO), return; end
            ds = lower(strtrim(NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'datasource',''))));
            st = lower(strtrim(NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'sourceType',''))));
            tf = ismember(ds, {'nifti','spm','surf','image'}) || ismember(st, {'image-list','surface-list'}) || isfield(IO,'imageFiles') || isfield(IO,'maskFile') || isfield(IO,'PP') && isfield(IO,'brainmask');
        end

        function files = imageFilesFromIO(IO)
            % IMAGEFILESFROMIO  Normalize image or surface file lists from legacy IO fields.
            %
            %   files = NMDataIOStateTools.imageFilesFromIO(IO) collects imageFiles,
            %   PP, files, or grouped P entries into a column cell array of file names
            %   without checking file-system readability.
            files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'imageFiles',{}));
            if isempty(files), files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'PP',{})); end
            if isempty(files), files = NMDataIOStateTools.asCaseCell(NMDataIOStateTools.fieldOr(IO,'files',{})); end
            if isempty(files) && isfield(IO,'P') && iscell(IO.P)
                for i = 1:numel(IO.P)
                    files = [files; NMDataIOStateTools.asCaseCell(IO.P{i})]; %#ok<AGROW>
                end
            end
            files = files(:);
        end

        function lists = imageClassFileListsFromIO(IO, files, names, sizes)
            % IMAGECLASSFILELISTSFROMIO  Rebuild grouped image file-list metadata for UI state.
            %
            %   lists = NMDataIOStateTools.imageClassFileListsFromIO(IO, files, names, sizes)
            %   partitions a flat file list by group sizes and assigns class names.
            %   If sizes are absent but legacy IO.P contains grouped files, the groups
            %   are reconstructed from IO.P before building the state-friendly structs.
            files = NMDataIOStateTools.asCaseCell(files);
            names = NMDataIOStateTools.asCaseCell(names);
            sizes = NMDataIOStateTools.numericVector(sizes);
            lists = {};
            if isempty(sizes) && isfield(IO,'P') && iscell(IO.P)
                sizes = zeros(1,numel(IO.P));
                files = {};
                for i = 1:numel(IO.P)
                    pf = NMDataIOStateTools.asCaseCell(IO.P{i});
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
                if numel(names) >= i && ~isempty(names{i})
                    nm = names{i};
                else
                    nm = sprintf('Class_%d', i);
                end
                lists{end+1,1} = struct('name', char(string(nm)), 'files', {files(idx)}); %#ok<AGROW>
                pos = pos + n;
            end
        end

        function c = asCaseCell(v)
            % ASCASECELL  Convert heterogeneous scalar/vector input to a column cellstr array.
            %
            %   c = NMDataIOStateTools.asCaseCell(v) accepts char matrices, strings,
            %   cells, numeric arrays, and logical arrays and returns cellstr-style
            %   case/file/name tokens.  Unsupported conversion failures return an
            %   empty cell array, preserving legacy permissive state normalization.
            if isempty(v)
                c = {};
            elseif ischar(v)
                c = cellstr(v);
            elseif isstring(v)
                c = cellstr(v(:));
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v)
                    if isempty(v{i}), c{i} = ''; else, c{i} = char(string(v{i})); end
                end
            elseif isnumeric(v) || islogical(v)
                c = cellstr(num2str(v(:)));
            else
                try
                    c = cellstr(string(v(:)));
                catch
                    c = {};
                end
            end
            c = c(:);
        end

        function x = numericVector(v)
            % NUMERICVECTOR  Convert numeric, cell, or delimited text input to a finite row vector.
            %
            %   x = NMDataIOStateTools.numericVector(v) returns double values from
            %   numeric/logical input, cell tokens, or comma/semicolon/whitespace
            %   delimited text.  Non-finite conversion results are discarded.
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

        function gm = groupmodeValue(v)
            % GROUPMODEVALUE  Normalize legacy source-mode labels to numeric groupmode codes.
            %
            %   gm = NMDataIOStateTools.groupmodeValue(v) maps workspace, MAT-file,
            %   text, spreadsheet, MATLAB-table, and database source labels to the
            %   legacy DataIO groupmode integers 1..6.  Unknown labels default to 1.
            if isnumeric(v) && isscalar(v), gm = double(v); return; end
            s = lower(strtrim(NMDataIOStateTools.toChar(v)));
            switch s
                case {'1','workspace','matlab workspace','base','workspace-variables'}
                    gm = 1;
                case {'2','mat','matfile','mat-file','matlab file','mat-file variables','matfile-variables'}
                    gm = 2;
                case {'3','text','txt','csv','tsv','text-file'}
                    gm = 3;
                case {'4','spreadsheet','xls','xlsx','xlsm','excel','table-file','text/spreadsheet','text/spreadsheet table','text/spreadsheet table file','text/csv/excel files'}
                    gm = 4;
                case {'5','table','tablevar','table-variable','matlab table','matlab table variable','matlab tables'}
                    gm = 5;
                case {'6','database','database connector'}
                    gm = 6;
                otherwise
                    gm = 1;
            end
        end

        function name = groupmodeName(gm)
            % GROUPMODENAME  Render a legacy groupmode value as a source label.
            %
            %   name = NMDataIOStateTools.groupmodeName(gm) converts numeric or
            %   textual groupmode input to the user-facing source family name used in
            %   DataIO summaries and diagnostics.
            switch NMDataIOStateTools.groupmodeValue(gm)
                case 1, name = 'workspace';
                case 2, name = 'mat-file';
                case 3, name = 'text-file';
                case 4, name = 'spreadsheet';
                case 5, name = 'MATLAB tables';
                case 6, name = 'database connector';
                otherwise, name = 'unknown';
            end
        end


        function catalogue = sourceTypeCatalogue()
            % SOURCETYPECATALOGUE  Return the authoritative DataIO source-type dictionary.
            %
            %   catalogue = NMDataIOStateTools.sourceTypeCatalogue() returns the
            %   canonical source-type ids, user-facing labels, and provenance help-file
            %   names used by DataIO. This is the single DataIO owner of the browser/API
            %   source vocabulary and provenance-help identity; downstream modules must
            %   query it rather than duplicate those mappings.
            catalogue = [ ...
                struct('id','workspace','label','MATLAB workspace variables','helpFile','workspace.html') ...
                struct('id','matfile','label','MAT-file variables','helpFile','matfile.html') ...
                struct('id','tablevar','label','MATLAB tables','helpFile','tablevar.html') ...
                struct('id','tablefile','label','Text/CSV/Excel files','helpFile','tablefile.html') ...
                struct('id','database','label','Database connector','helpFile','database.html') ...
                struct('id','image-list','label','3D image files (NIfTI)','helpFile','image-list.html') ...
                struct('id','connectivity','label','Connectivity data: ROI-anchored matrices','helpFile','connectivity.html') ...
                struct('id','surface-list','label','Surface/vertex scalar files','helpFile','surface-list.html') ...
                struct('id','roi','label','ROI/parcellated image files/tables','helpFile','roi.html')];
        end

        function label = sourceTypeLabel(sourceType)
            % SOURCETYPELABEL  Resolve one canonical DataIO source id to its label.
            %
            %   Unknown source ids remain explicit and are returned as their literal
            %   token rather than being coerced to a known DataIO provenance type.
            sourceType = lower(strtrim(NMDataIOStateTools.toChar(sourceType)));
            catalogue = NMDataIOStateTools.sourceTypeCatalogue();
            hit = find(strcmp({catalogue.id},sourceType),1,'first');
            if isempty(hit)
                if isempty(sourceType) || strcmp(sourceType,'unknown'), label = 'Unknown'; else, label = sourceType; end
            else
                label = catalogue(hit).label;
            end
        end

        function sourceType = normalizeSourceType(sourceType, groupmode)
            % NORMALIZESOURCETYPE  Canonicalize browser/API source-type aliases.
            %
            %   sourceType = NMDataIOStateTools.normalizeSourceType(sourceType, groupmode)
            %   maps workspace, matfile, tablefile, tablevar, and database aliases to
            %   canonical tokens.  Empty or '?' source types are inferred from the
            %   legacy groupmode fallback.
            st = lower(strtrim(NMDataIOStateTools.toChar(sourceType)));
            if isempty(st) || strcmp(st,'?')
                switch NMDataIOStateTools.groupmodeValue(groupmode)
                    case 1, sourceType = 'workspace';
                    case 2, sourceType = 'matfile';
                    case {3,4}, sourceType = 'tablefile';
                    case 5, sourceType = 'tablevar';
                    case 6, sourceType = 'database';
                    otherwise, sourceType = 'workspace';
                end
                return;
            end
            switch st
                case {'workspace','matlab workspace','workspace variables','workspace-variables'}
                    sourceType = 'workspace';
                case {'matfile','mat-file','mat file','mat-file variables','matfile-variables'}
                    sourceType = 'matfile';
                case {'tablevar','table-variable','matlab table','matlab table variable','matlab tables'}
                    sourceType = 'tablevar';
                case {'tablefile','table-file','text/spreadsheet','text/spreadsheet table','text/spreadsheet table file','text/csv/excel files','text file','text-table','spreadsheet','spreadsheet table','csv','tsv','txt','excel','xls','xlsx','xlsm'}
                    sourceType = 'tablefile';
                case {'database','database connector'}
                    sourceType = 'database';
                case {'roi','roi data','roi-data','parcel','parcel-wise','parcel-wise data'}
                    sourceType = 'roi';
                otherwise
                    sourceType = st;
            end
        end

        function gm = groupmodeFromSourceType(sourceType, fallback)
            % GROUPMODEFROMSOURCETYPE  Map a canonical sourceType back to legacy groupmode.
            %
            %   gm = NMDataIOStateTools.groupmodeFromSourceType(sourceType, fallback)
            %   returns the DataIO groupmode for workspace, matfile, tablevar,
            %   database, or tablefile sources.  Table files preserve a valid text vs
            %   spreadsheet fallback when available.
            st = NMDataIOStateTools.normalizeSourceType(sourceType, fallback);
            switch st
                case 'workspace'
                    gm = 1;
                case 'matfile'
                    gm = 2;
                case 'tablevar'
                    gm = 5;
                case 'database'
                    gm = 6;
                case 'roi'
                    gm = 1;
                case 'tablefile'
                    gm = NMDataIOStateTools.groupmodeValue(fallback);
                    if ~ismember(gm,[3 4]), gm = 4; end
                otherwise
                    gm = NMDataIOStateTools.groupmodeValue(fallback);
            end
        end

        function varind = defaultVarind(NM)
            % DEFAULTVARIND  Infer the next training-modality index for DataIO state.
            %
            %   varind = NMDataIOStateTools.defaultVarind(NM) returns one plus the
            %   current number of NM.Y modalities when available, otherwise 1.  It
            %   does not inspect OOCV/application containers.
            varind = 1;
            if isstruct(NM) && isfield(NM,'Y') && ~isempty(NM.Y)
                varind = numel(NM.Y) + 1;
            end
        end

        function modeflag = inferModeflag(NM)
            % INFERMODEFLAG  Obtain the active NM learning mode for DataIO defaults.
            %
            %   modeflag = NMDataIOStateTools.inferModeflag(NM) returns NM.modeflag
            %   as a character scalar when present and defaults to 'classification'.
            modeflag = 'classification';
            if isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                modeflag = NMDataIOStateTools.toChar(NM.modeflag);
            end
        end

        function nanMapper = defaultNaNMapper()
            % DEFAULTNANMAPPER  Return the standard disabled missing-token mapper config.
            %
            %   nanMapper = NMDataIOStateTools.defaultNaNMapper() creates the fixed
            %   schema used by matrix/table imports to optionally map textual missing
            %   tokens in features, covariates, labels, and case IDs.
            nanMapper = struct();
            nanMapper.enabled = false;
            nanMapper.tokens = {'NA','N/A','n/a','na','.','-','','missing','Missing','MISSING'};
            nanMapper.applyToFeatures = true;
            nanMapper.applyToCovariates = true;
            nanMapper.applyToLabels = false;
            nanMapper.applyToCaseIds = false;
            nanMapper.caseInsensitive = true;
            nanMapper.trimWhitespace = true;
        end


        function tf = isUnknownString(v)
            % ISUNKNOWNSTRING  Test whether a value is an empty or '?' string placeholder.
            %
            %   tf = NMDataIOStateTools.isUnknownString(v) returns true for empty
            %   input or char/string values that normalize to an empty string or '?'.
            %   Non-string values are not treated as unknown placeholders.
            if isempty(v)
                tf = true;
                return;
            end
            if ischar(v) || isa(v,'string')
                c = strtrim(NMDataIOStateTools.toChar(v));
                tf = isempty(c) || strcmp(c,'?');
            else
                tf = false;
            end
        end

        function s = toChar(v)
            % TOCHAR  Scalarize common MATLAB value types to a character vector.
            %
            %   s = NMDataIOStateTools.toChar(v) returns v for char input, the first
            %   element for strings, cells, numeric arrays, and logical arrays, and an
            %   empty character vector for unsupported or empty values.
            if ischar(v)
                s = v;
            elseif isa(v,'string')
                if isempty(v)
                    s = '';
                else
                    s = char(v(1));
                end
            elseif iscell(v)
                if isempty(v)
                    s = '';
                else
                    s = NMDataIOStateTools.toChar(v{1});
                end
            elseif isnumeric(v) || islogical(v)
                if isempty(v)
                    s = '';
                else
                    s = num2str(v(1));
                end
            else
                s = '';
            end
        end

        function out = substructOrEmpty(s, names)
            % SUBSTRUCTOREMPTY  Return the first available named struct subfield.
            %
            %   out = NMDataIOStateTools.substructOrEmpty(s, names) scans names in
            %   order and returns the first corresponding struct-valued field of s,
            %   or an empty scalar struct if none is available.
            out = struct();
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                if isfield(s, names{i}) && isstruct(s.(names{i}))
                    out = s.(names{i});
                    return;
                end
            end
        end

        function v = pick(s, names, defaultValue)
            % PICK  Read the first non-empty field from a struct using alias names.
            %
            %   v = NMDataIOStateTools.pick(s, names, defaultValue) returns the
            %   first non-empty s.(name) for name in names.  If s is not a struct or
            %   no candidate field is populated, defaultValue is returned.
            v = defaultValue;
            if ~isstruct(s), return; end
            for i = 1:numel(names)
                if isfield(s,names{i}) && ~isempty(s.(names{i}))
                    v = s.(names{i});
                    return;
                end
            end
        end

        function v = pick2(s1, s2, names, defaultValue)
            % PICK2  Read aliased fields with nested-state precedence.
            %
            %   v = NMDataIOStateTools.pick2(s1, s2, names, defaultValue) first
            %   probes the nested/source-specific struct s2, then falls back to s1,
            %   and finally to defaultValue.  Empty candidate values are ignored.
            v = NMDataIOStateTools.pick(s2, names, []);
            if isempty(v)
                v = NMDataIOStateTools.pick(s1, names, defaultValue);
            end
            if isempty(v), v = defaultValue; end
        end

        function mode = normalizeSourceBlockAlignmentMode(value)
            % NORMALIZESOURCEBLOCKALIGNMENTMODE  Canonicalize generic source-block alignment assignment.
            %
            % The browser's historical case_id token denotes the generic
            % key-per-block mechanism. Shared-key assignment is a configuration
            % convenience only: row-bearing blocks still carry expanded ordered
            % key-component references and use the same matcher as key-per-block.
            mode = lower(strtrim(NMDataIOStateTools.toChar(value)));
            switch mode
                case {'case_id','key_per_block'}
                    mode = 'key_per_block';
                case 'shared_key'
                    mode = 'shared_key';
                case 'row_order'
                    mode = 'row_order';
                otherwise
                    error('NMDataIOStateTools:sourceBlockAlignmentMode', ...
                        'Unsupported source-block alignment mode: %s.', mode);
            end
        end

        function roles = normalizeVariableRoleKeyRefs(roles, IO, alignmentMode)
            % NORMALIZEVARIABLEROLEKEYREFS  Convert row-bearing source blocks to ordered caseKeyRefs.
            %
            % Legacy scalar caseIdRef and top-level per-source Case-ID
            % assignments are consumed here so scientific materialization sees one
            % canonical block contract. The standalone caseId role remains only for
            % explicit row-order mode.
            if ~isstruct(roles), roles = struct(); end
            roleNames = {'caseId','labels','features','featureNames','covariates','covariateNames','globals'};
            for i = 1:numel(roleNames)
                role = roleNames{i};
                if ~isfield(roles,role) || isempty(roles.(role)), roles.(role) = {}; end
            end
            if strcmp(alignmentMode,'row_order'), return; end

            caseRefs = NMDataIOStateTools.roleRefCell(roles.caseId);
            rowRoles = {'labels','features','covariates','globals'};
            for r = 1:numel(rowRoles)
                role = rowRoles{r};
                refs = NMDataIOStateTools.roleRefCell(roles.(role));
                for i = 1:numel(refs)
                    ref = refs{i};
                    keyRefs = {};
                    if isstruct(ref) && isfield(ref,'caseKeyRefs') && ~isempty(ref.caseKeyRefs)
                        keyRefs = NMDataIOStateTools.roleRefCell(ref.caseKeyRefs);
                    elseif isstruct(ref) && isfield(ref,'caseIdRef') && ~isempty(ref.caseIdRef)
                        keyRefs = NMDataIOStateTools.roleRefCell(ref.caseIdRef);
                    else
                        sourceKey = NMDataIOStateTools.variableRefSourceIdentity(ref, IO);
                        hits = {};
                        for j = 1:numel(caseRefs)
                            if strcmp(NMDataIOStateTools.variableRefSourceIdentity(caseRefs{j}, IO), sourceKey)
                                hits{end+1,1} = caseRefs{j}; %#ok<AGROW>
                            end
                        end
                        if numel(hits) == 1, keyRefs = hits; end
                    end
                    if isstruct(ref)
                        if isfield(ref,'caseIdRef'), ref = rmfield(ref,'caseIdRef'); end
                        if ~isempty(keyRefs), ref.caseKeyRefs = keyRefs(:)'; end
                    end
                    refs{i} = ref;
                end
                roles.(role) = refs;
            end
            roles.caseId = {};
        end

        function roles = variableRoleKeyRefsForState(roles)
            % VARIABLEROLEKEYREFSFORSTATE  Persist one ordered source-block key representation.
            % Legacy scalar caseIdRef is accepted on ingress but new state is written
            % with ordered caseKeyRefs for both scalar and composite keys.
            if ~isstruct(roles), return; end
            rowRoles = {'labels','features','covariates','globals'};
            for r = 1:numel(rowRoles)
                role = rowRoles{r};
                if ~isfield(roles,role), continue; end
                refs = NMDataIOStateTools.roleRefCell(roles.(role));
                for i = 1:numel(refs)
                    ref = refs{i};
                    if ~isstruct(ref), continue; end
                    if isfield(ref,'caseIdRef') && ~isempty(ref.caseIdRef) && ...
                            (~isfield(ref,'caseKeyRefs') || isempty(ref.caseKeyRefs))
                        ref.caseKeyRefs = NMDataIOStateTools.roleRefCell(ref.caseIdRef);
                    end
                    if isfield(ref,'caseIdRef'), ref = rmfield(ref,'caseIdRef'); end
                    if isfield(ref,'caseKeyRefs') && ~isempty(ref.caseKeyRefs)
                        ref.caseKeyRefs = NMDataIOStateTools.roleRefCell(ref.caseKeyRefs)';
                    end
                    refs{i} = ref;
                end
                roles.(role) = refs;
            end
        end

        function refs = roleRefCell(raw)
            % ROLEREFCELL  Normalize source-reference containers without changing reference content.
            refs = {};
            if isempty(raw), return; end
            if iscell(raw)
                refs = raw(:);
            elseif isstruct(raw)
                refs = arrayfun(@(x) x, raw(:), 'UniformOutput', false);
            elseif ischar(raw) || isstring(raw)
                refs = cellstr(string(raw(:)));
            else
                error('NMDataIOStateTools:variableRoleContract', ...
                    'The saved label/covariate/global column selections are invalid.');
            end
            for i = 1:numel(refs)
                if ischar(refs{i}) || isstring(refs{i})
                    refs{i} = struct('name',char(string(refs{i})));
                elseif ~isstruct(refs{i})
                    error('NMDataIOStateTools:variableRoleReference', 'Saved label/covariate/global selection %g is invalid.', i);
                end
            end
        end

        function key = variableRefSourceIdentity(ref, IO)
            % VARIABLEREFSOURCEIDENTITY  Identify the provenance container of one variable reference.
            defaultType = lower(strtrim(NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'sourceType','workspace'))));
            sourceType = lower(strtrim(NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourceType',defaultType))));
            if strcmp(sourceType,'matfile')
                sourcePath = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourcePath',''));
                if isempty(sourcePath)
                    files = NMDataIOStateTools.fieldOr(IO,'matFiles',{});
                    if ischar(files) || isstring(files), files = cellstr(string(files(:))); end
                    if iscell(files) && numel(files) == 1
                        sourcePath = NMDataIOStateTools.toChar(files{1});
                    elseif iscell(files) && numel(files) > 1
                        error('NMDataIOStateTools:missingMatProvenance', ...
                            'A selected MAT-file variable must identify its MAT file when more than one MAT file is selected.');
                    end
                end
                key = ['matfile|' sourcePath];
            elseif strcmp(sourceType,'tablefile')
                sourcePath = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourcePath',''));
                sourceObject = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourceObject',''));
                key = ['tablefile|' sourcePath '|' sourceObject];
            elseif strcmp(sourceType,'tablevar')
                sourceName = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourceName',''));
                if isempty(sourceName)
                    error('NMDataIOStateTools:missingTableProvenance', ...
                        'A selected MATLAB-table column must identify its workspace table.');
                end
                key = ['tablevar|' sourceName];
            elseif strcmp(sourceType,'database')
                sourcePath = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourcePath',''));
                sourceObject = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(ref,'sourceObject',''));
                if isempty(sourcePath)
                    sourcePath = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'databaseFile',''));
                    if NMDataIOStateTools.isUnknownString(sourcePath)
                        sourcePath = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'databaseUrl',''));
                    end
                end
                if isempty(sourceObject)
                    error('NMDataIOStateTools:missingDatabaseProvenance', ...
                        'A selected database column must identify its table or view.');
                end
                connector = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'databaseConnector',''));
                databaseName = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'databaseName',''));
                schemaName = NMDataIOStateTools.toChar(NMDataIOStateTools.fieldOr(IO,'databaseSchema',''));
                key = sprintf('database|%s|%s|%s|%s|%s',connector,sourcePath,databaseName,schemaName,sourceObject);
            else
                key = [sourceType '|workspace'];
            end
        end

        function v = fieldOr(s, name, defaultValue)
            % FIELDOR  Return one populated struct field or a default value.
            %
            %   v = NMDataIOStateTools.fieldOr(s, name, defaultValue) returns
            %   s.(name) only when s is a struct, the field exists, and the field is
            %   non-empty; otherwise it returns defaultValue.
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = defaultValue;
            end
        end
    end
end
