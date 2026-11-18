classdef NMDataIOTableRoleTools
% NMDataIOTableRoleTools
% -------------------------------------------------------------------------
% Purpose:
%   Canonical table-column role resolver for case IDs, labels, features, covariates, globals and
%   ignored columns after a tabular source has been retrieved as a MATLAB table.
%
% Authority and invariants:
%   This class maps explicit DataIO role selections onto existing ReadTabular/CheckTabFile contracts.
%   It does not choose scientific roles heuristically and does not own row filtering or Case-ID
%   alignment. Original and internal table-column names remain traceable through the role contract.
% -------------------------------------------------------------------------

    methods (Static)
        function roles = resolveRoles(T, IO)
            % resolveRoles  Resolve selected table columns into DataIO feature/label/covariate/global roles.
            %
            % Consumes T, IO; returns roles.
            % It feeds the matrix import path by separating feature columns from label, covariate, global, case-ID, and inclusion roles.
            % Callers should pass already-normalized NM/state/spec inputs and inspect returned diagnostics.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            names = T.Properties.VariableNames;
            displayNames = NMDataIOTableRoleTools.originalColumnNames(T);
            roles = struct();
            roles.internalColumns = names;
            roles.allColumns = displayNames;
            roles.columnNameMap = struct('internalNames',{names}, 'originalNames',{displayNames});
            roles.caseColumn = NMDataIOTableRoleTools.firstExistingColumn(names, displayNames, NMDataIOTableRoleTools.valueAsCell(NMDataIOTableRoleTools.fieldOr(IO,'case_edit','?')));
            roles.labelColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, NMDataIOTableRoleTools.fieldOr(IO,'label_edit',{}));
            roles.covariateColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, NMDataIOTableRoleTools.pickFirst(IO, {'covar_edit','covariateColumns','covarColumns'}, {}));
            roles.ignoreColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, NMDataIOTableRoleTools.pickFirst(IO, {'ignore_edit','ignoreColumns','ignoredColumns'}, {}));
            if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles)
                r = IO.tableColumnRoles;
                if isfield(r,'caseId'), roles.caseColumn = NMDataIOTableRoleTools.firstExistingColumn(names, displayNames, NMDataIOTableRoleTools.valueAsCell(r.caseId)); end
                if isfield(r,'labels'), roles.labelColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, r.labels); end
                if isfield(r,'covariates'), roles.covariateColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, r.covariates); end
                if isfield(r,'ignore'), roles.ignoreColumns = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, r.ignore); end
            end
            roles.caseColumnName = NMDataIOTableRoleTools.displayForColumns(names, displayNames, roles.caseColumn);
            roles.labelColumnNames = NMDataIOTableRoleTools.displayForColumns(names, displayNames, roles.labelColumns);
            roles.covariateColumnNames = NMDataIOTableRoleTools.displayForColumns(names, displayNames, roles.covariateColumns);
            roles.ignoreColumnNames = NMDataIOTableRoleTools.displayForColumns(names, displayNames, roles.ignoreColumns);

            roleCols = [NMDataIOTableRoleTools.valueAsCell(roles.caseColumn) roles.labelColumns(:)' roles.covariateColumns(:)' roles.ignoreColumns(:)'];
            roleMask = ismember(names, roleCols);
            candidates = names(~roleMask);

            explicitFeatures = {};
            modernFeatureRoles = false;
            if isfield(IO,'feature_edit')
                explicitFeatures = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, IO.feature_edit);
            end
            if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'features')
                modernFeatureRoles = true;
                explicitFeatures = NMDataIOTableRoleTools.resolveColumnList(names, displayNames, IO.tableColumnRoles.features);
            end
            if modernFeatureRoles || ~isempty(explicitFeatures)
                candidates = explicitFeatures;
            end

            [ordered, fmap] = NMDataIOTableRoleTools.applyDiscoveryFeatureMap(candidates, IO, names, displayNames);
            roles.featureColumns = ordered;
            roles.featureColumnNames = NMDataIOTableRoleTools.displayForColumns(names, displayNames, ordered);
            roles.explicitFeatureColumns = explicitFeatures;
            roles.explicitFeatureColumnNames = NMDataIOTableRoleTools.displayForColumns(names, displayNames, explicitFeatures);
            roles.featureMap = fmap;
            roles.hasCovariates = ~isempty(roles.covariateColumns);
            roles.hasIgnoredColumns = ~isempty(roles.ignoreColumns);
            roles.hasCaseColumn = ~isempty(roles.caseColumn);
            roles.hasLabelColumns = ~isempty(roles.labelColumns);
        end

        function [IO, featureTable, mess] = prepareReadTabular(IO, T, mess)
            % prepareReadTabular  Prepare a table import by resolving roles and constructing the feature table.
            %
            % Consumes IO, T, mess; returns IO, featureTable, mess.
            % It feeds the matrix import path by separating feature columns from label, covariate, global, case-ID, and inclusion roles.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 3, mess = []; end
            roles = NMDataIOTableRoleTools.resolveRoles(T, IO);
            [mess, hasMissingRole] = NMDataIOTableRoleTools.validateRequestedColumns(T, IO, roles, mess);
            if hasMissingRole
                featureTable = table(); return;
            end

            mapperOpts = NMDataIOTableRoleTools.nanMapperOptionsFromIO(IO);
            mapColumns = {};
            if mapperOpts.applyToFeatures, mapColumns = [mapColumns roles.featureColumns]; end
            if mapperOpts.applyToCovariates, mapColumns = [mapColumns roles.covariateColumns]; end
            [T2, nanReport] = NMDataIOTableRoleTools.applyNaNMapperToColumns(T, mapColumns, mapperOpts);

            [T2, numericReport, mess] = NMDataIOTableRoleTools.convertRoleColumnsToNumeric(T2, roles, mess);
            if ~isempty(numericReport.badColumns)
                featureTable = table(); return;
            end

            if isempty(roles.caseColumn)
                mess = GenerateMessageEntry(mess, 'No valid Case-ID column was selected for this table. Select the column that identifies each case.', 1, 'red*');
                featureTable = table(); return;
            end
            IO.s_ID = NMDataIOTableRoleTools.tableColumnAsCell(T2, roles.caseColumn);
            if NMDataIOTableRoleTools.labelsRequired(IO)
                if isempty(roles.labelColumns)
                    mess = GenerateMessageEntry(mess, 'No valid label column was selected for this table. Select the label column before continuing.', 1, 'red*');
                    featureTable = table(); return;
                end
                mode = lower(strtrim(char(string(NMDataIOTableRoleTools.fieldOr(IO,'modeflag','classification')))));
                if ~contains(mode,'reg') && numel(roles.labelColumns) ~= 1
                    mess = GenerateMessageEntry(mess, 'Classification requires exactly one label column. Multiple target columns are supported only for regression.', 1, 'red*');
                    featureTable = table(); return;
                end
                IO.s_label = table2array(T2(:, roles.labelColumns));
            end

            if roles.hasCovariates
                [covars, covnames, covReport, mess] = NMDataIOTableRoleTools.extractNumericCovariates(T2, roles.covariateColumns, mess);
                if ~isempty(covars)
                    IO.covars = covars;
                    IO.covnames = covnames;
                    if ~isfield(IO,'covmanage_edit') || NMDataIOTableRoleTools.isUnknown(IO.covmanage_edit)
                        IO.covmanage_edit = 1;
                    end
                end
            else
                covReport = struct('nCovariates',0,'covariateColumns',{{}},'nonNumericColumns',{{}});
            end

            featureTable = T2(:, roles.featureColumns);
            IO.s_featnames = roles.featureColumnNames;
            IO.featnames = roles.featureColumnNames;
            IO.tableColumnRoles = roles;
            IO.nanMapperReport = nanReport;
            IO.importReport = NMDataIOTableRoleTools.buildImportReport(IO, T, roles, nanReport, covReport);
            IO.importReport.numericConversion = numericReport;

            if roles.hasCovariates
                mess = GenerateMessageEntry(mess, sprintf('* Mapped %g source-table column(s) to NM.covars: %s.', numel(roles.covariateColumns), strjoin(roles.covariateColumnNames, ', ')), 0, 'blue');
            end
            if mapperOpts.enabled
                mess = GenerateMessageEntry(mess, sprintf('Mapped %g configured missing-value text occurrence(s) to NaN in feature/covariate columns.', nanReport.nMappedTotal), 0, 'blue');
                if ~isempty(nanReport.unresolvedColumns)
                    mess = GenerateMessageEntry(mess, sprintf('Some feature/covariate columns still contain text that cannot be converted to numeric values: %s. Add missing-value text to Missing-value tokens or correct the source values.', strjoin(nanReport.unresolvedColumns, ', ')), 2, 'SystemCommands');
                end
            end
            if roles.featureMap.reordered
                mess = GenerateMessageEntry(mess, 'OOCV/application feature columns were reordered to match the discovery feature order.', 0, 'blue');
            end
            if ~isempty(roles.featureMap.extraColumns)
                mess = GenerateMessageEntry(mess, sprintf('Ignoring %g table column(s) that are not assigned as features, labels, covariates or Case IDs: %s.', numel(roles.featureMap.extraColumns), strjoin(roles.featureMap.extraColumns, ', ')), 2, 'SystemCommands');
            end
            if ~isempty(roles.featureMap.ambiguousColumns)
                mess = GenerateMessageEntry(mess, sprintf('OOCV feature correspondence is ambiguous because more than one source column matches training feature(s): %s.', strjoin(roles.featureMap.ambiguousColumns, ', ')), 1, 'red*');
            elseif ~isempty(roles.featureMap.missingColumns)
                mess = GenerateMessageEntry(mess, sprintf('OOCV source leaves %g training feature(s) unassigned: %s. Missing targets are retained on the trained feature axis and require OOCV-level feature imputation before model application.', numel(roles.featureMap.missingColumns), strjoin(roles.featureMap.missingColumns, ', ')), 2, 'SystemCommands');
            end
        end

        function [M, featureNames, report, mess] = featureMatrixForCheck(IO, T, mess)
            % featureMatrixForCheck  Extract numeric feature matrix and feature names from a role-resolved table.
            %
            % Consumes IO, T, mess; returns M, featureNames, report, mess.
            % It feeds the matrix import path by separating feature columns from label, covariate, global, case-ID, and inclusion roles.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 3, mess = []; end
            [IO2, featureTable, mess] = NMDataIOTableRoleTools.prepareReadTabular(IO, T, mess);
            report = NMDataIOTableRoleTools.fieldOr(IO2,'importReport',struct());
            featureNames = NMDataIOTableRoleTools.fieldOr(IO2,'s_featnames',{});
            if isempty(featureTable)
                M = [];
                return;
            end
            if isfield(IO2,'cellcols') && any(IO2.cellcols) && exist('nk_ScopeCellRetDummyFromTable','file') == 2
                featureTable = nk_ScopeCellRetDummyFromTable('replace', featureTable, IO2.uniquelim);
                featureNames = featureTable.Properties.VariableNames;
            end
            M = table2array(featureTable);
        end

        function tf = labelsRequired(IO)
            % labelsRequired  Return whether the current table role configuration requires label assignment.
            %
            % IO -> tf.
            % It feeds the matrix import path by separating feature columns from label, covariate, global, case-ID, and inclusion roles.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = true;
            if nargin < 1 || ~isstruct(IO), return; end

            labelsKnown = NMDataIOTableRoleTools.fieldOr(IO,'labels_known',true);
            oocv = NMDataIOTableRoleTools.fieldOr(IO,'oocvflag',false);
            hasExistingCases = isfield(IO,'ID') && ~isempty(IO.ID);
            referenceCaseImport = isfield(IO,'referenceCaseImport') && ~isempty(IO.referenceCaseImport) && logical(IO.referenceCaseImport);
            caseAxisEstablished = isfield(IO,'caseAxisEstablishing') && ~isempty(IO.caseAxisEstablishing) && ~logical(IO.caseAxisEstablishing);

            % Once the target case axis is established, labels belong to that
            % target container. The incoming source contributes cases/features
            % only and is aligned to the established axis downstream. Do not
            % require a second source-local label assignment merely because the
            % alignment read has not yet set referenceCaseImport.
            if referenceCaseImport || hasExistingCases || caseAxisEstablished
                tf = false;
                return;
            end

            tf = (~logical(oocv)) || logical(labelsKnown);
        end


        function report = featureCorrespondence(sourceNames, targetNames, sourceFallbackNames, explicitTargetIndices)
            % featureCorrespondence  Resolve source columns onto the immutable training feature axis.
            %
            % Automatic mode uses exact source/training names. Manual expert mode supplies
            % one explicit training-target index per assigned source column; source names then
            % remain descriptive only and do not regain correspondence authority.
            sourceNames = NMDataIOTableRoleTools.valueAsCell(sourceNames);
            targetNames = NMDataIOTableRoleTools.valueAsCell(targetNames);
            if nargin < 3 || isempty(sourceFallbackNames), sourceFallbackNames = sourceNames; end
            sourceFallbackNames = NMDataIOTableRoleTools.valueAsCell(sourceFallbackNames);
            if numel(sourceFallbackNames) ~= numel(sourceNames)
                error('NMDataIOTableRoleTools:FeatureCorrespondenceFallback', ...
                    'Feature correspondence fallback names must match the source-name count.');
            end
            manualMode = nargin >= 4 && ~isempty(explicitTargetIndices);
            nTarget = numel(targetNames);
            targetSourceIndices = cell(1,nTarget);
            targetSourceIndex = nan(1,nTarget);
            targetStatus = repmat({'missing'},1,nTarget);
            usedSource = false(1,numel(sourceNames));
            duplicateTargets = {};
            targetUnique = unique(targetNames,'stable');
            for i = 1:numel(targetUnique)
                if sum(strcmp(targetNames,targetUnique{i})) > 1
                    duplicateTargets{end+1} = targetUnique{i}; %#ok<AGROW>
                end
            end
            if manualMode
                explicitTargetIndices = double(explicitTargetIndices(:)');
                if numel(explicitTargetIndices) ~= numel(sourceNames)
                    error('NMDataIOTableRoleTools:ManualFeatureCorrespondenceCount', ...
                        'Manual feature correspondence requires one target index per assigned source column.');
                end
                if any(~isfinite(explicitTargetIndices) | explicitTargetIndices < 1 | explicitTargetIndices > nTarget | ...
                        explicitTargetIndices ~= round(explicitTargetIndices))
                    error('NMDataIOTableRoleTools:ManualFeatureTargetIndex', ...
                        'Manual feature correspondence contains an invalid training-target index.');
                end
                for s = 1:numel(sourceNames)
                    t = explicitTargetIndices(s);
                    targetSourceIndices{t}(end+1) = s; %#ok<AGROW>
                    usedSource(s) = true;
                end
                for t = 1:nTarget
                    hits = targetSourceIndices{t};
                    if numel(hits) == 1
                        targetSourceIndex(t) = hits;
                        targetStatus{t} = 'matched';
                    elseif numel(hits) > 1
                        targetStatus{t} = 'ambiguous';
                    end
                end
            else
                for i = 1:nTarget
                    hits = find(strcmp(sourceNames,targetNames{i}));
                    if isempty(hits)
                        hits = find(strcmp(sourceFallbackNames,targetNames{i}));
                    end
                    targetSourceIndices{i} = hits(:)';
                    if numel(hits) == 1
                        targetSourceIndex(i) = hits;
                        targetStatus{i} = 'matched';
                        usedSource(hits) = true;
                    elseif numel(hits) > 1
                        targetStatus{i} = 'ambiguous';
                        usedSource(hits) = true;
                    end
                end
            end
            missingMask = strcmp(targetStatus,'missing');
            ambiguousMask = strcmp(targetStatus,'ambiguous');
            matchedMask = strcmp(targetStatus,'matched');
            matchedIndex = targetSourceIndex(matchedMask);
            report = struct();
            report.enabled = ~isempty(targetNames);
            if manualMode, report.mode = 'manual'; else, report.mode = 'automatic'; end
            report.sourceNames = sourceNames;
            report.targetNames = targetNames;
            report.targetSourceIndices = targetSourceIndices;
            report.targetSourceIndex = targetSourceIndex;
            report.targetStatus = targetStatus;
            report.missingColumns = targetNames(missingMask);
            report.ambiguousColumns = targetNames(ambiguousMask);
            report.duplicateTargetColumns = duplicateTargets;
            report.extraColumns = sourceNames(~usedSource);
            report.matchedTargetIndices = find(matchedMask);
            report.unresolvedTargetIndices = find(missingMask);
            report.ambiguousTargetIndices = find(ambiguousMask);
            report.complete = isempty(report.missingColumns) && isempty(report.ambiguousColumns) && isempty(duplicateTargets);
            report.reordered = report.complete && ~isequal(matchedIndex(:)',1:nTarget);

        end

        function [num, report] = numericSourceColumn(IO, col, roleName)
            % numericSourceColumn  Convert one assigned numeric-role column while retaining cell-level diagnostics.
            % Intrinsic MATLAB missing values are always missing; the optional NaN mapper is only for textual tokens.
            if nargin < 3 || isempty(roleName), roleName = 'Source'; end
            opts = NMDataIOTableRoleTools.nanMapperOptionsFromIO(IO);
            roleKey = lower(strtrim(char(string(roleName))));
            applyMapper = opts.enabled;
            if contains(roleKey,'feature'), applyMapper = applyMapper && opts.applyToFeatures;
            elseif contains(roleKey,'covariate'), applyMapper = applyMapper && opts.applyToCovariates;
            elseif contains(roleKey,'target') || contains(roleKey,'label'), applyMapper = applyMapper && opts.applyToLabels;
            elseif contains(roleKey,'case'), applyMapper = applyMapper && opts.applyToCaseIds;
            end
            mapped = col;
            mapReport = struct('name','', 'nValues',numel(col), 'nMapped',0, 'convertedToNumeric',false, 'unresolvedNonNumeric',false);
            if applyMapper, [mapped, mapReport] = NMDataIOTableRoleTools.mapNaNMapperColumn(col, opts); end
            [num, ok, detail] = NMDataIOTableRoleTools.columnToNumeric(mapped);
            report = struct('role',char(roleName),'nanMapper',mapReport,'ok',ok,'detail',detail, ...
                'mapperEnabled',logical(applyMapper),'mapperTokens',{opts.tokens});
            num = double(num);
        end
    end

    methods (Static, Access = private)
        function [mess, hasMissing] = validateRequestedColumns(T, IO, roles, mess)
            hasMissing = false;
            displayNames = roles.allColumns;
            internalNames = roles.internalColumns;
            if nargin < 4, mess = []; end

            caseReq = NMDataIOTableRoleTools.requestedColumnValues(IO, 'case');
            [missing, requested] = NMDataIOTableRoleTools.missingRequestedColumns(displayNames, caseReq, internalNames);
            if ~isempty(missing)
                mess = GenerateMessageEntry(mess, sprintf('Case-ID column ''%s'' was not found in the selected table. Choose one of the available columns: %s.', missing{1}, NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            elseif ~isempty(requested) && isempty(roles.caseColumn)
                mess = GenerateMessageEntry(mess, sprintf('The selected Case-ID column (%s) could not be matched to this table. Choose one of the available columns: %s.', strjoin(requested, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            end

            labelsRequired = NMDataIOTableRoleTools.labelsRequired(IO);
            labelReq = NMDataIOTableRoleTools.requestedColumnValues(IO, 'label');
            [missing, requested] = NMDataIOTableRoleTools.missingRequestedColumns(displayNames, labelReq, internalNames);
            if labelsRequired && ~isempty(missing)
                mess = GenerateMessageEntry(mess, sprintf('Label column(s) were not found in the selected table: %s. Choose from the available columns: %s.', strjoin(missing, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            elseif labelsRequired && ~isempty(requested) && isempty(roles.labelColumns)
                mess = GenerateMessageEntry(mess, sprintf('The selected label column(s) (%s) could not be matched to this table. Choose from the available columns: %s.', strjoin(requested, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            end

            featureReq = NMDataIOTableRoleTools.requestedColumnValues(IO, 'feature');
            [missing, requested] = NMDataIOTableRoleTools.missingRequestedColumns(displayNames, featureReq, internalNames);
            if ~isempty(missing)
                mess = GenerateMessageEntry(mess, sprintf('Feature column(s) were not found in the selected table: %s. Check the table or select from the available columns: %s.', strjoin(missing, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            elseif ~isempty(requested) && isempty(roles.featureColumns)
                mess = GenerateMessageEntry(mess, sprintf('The selected feature column(s) (%s) could not be matched to this table. Choose from the available columns: %s.', strjoin(requested, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            elseif isempty(roles.featureColumns)
                mess = GenerateMessageEntry(mess, 'No feature columns are selected for this table. Select at least one feature column.', 1, 'red*');
                hasMissing = true;
            end

            covReq = NMDataIOTableRoleTools.requestedColumnValues(IO, 'covariate');
            [missing, ~] = NMDataIOTableRoleTools.missingRequestedColumns(displayNames, covReq, internalNames);
            if ~isempty(missing)
                mess = GenerateMessageEntry(mess, sprintf('Covariate column(s) were not found in the selected table: %s. Choose from the available columns: %s.', strjoin(missing, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            end

            ignoreReq = NMDataIOTableRoleTools.requestedColumnValues(IO, 'ignore');
            [missing, ~] = NMDataIOTableRoleTools.missingRequestedColumns(displayNames, ignoreReq, internalNames);
            if ~isempty(missing)
                mess = GenerateMessageEntry(mess, sprintf('Column(s) selected to be ignored were not found in the table: %s. Available columns: %s.', strjoin(missing, ', '), NMDataIOTableRoleTools.readableColumnList(displayNames)), 1, 'red*');
                hasMissing = true;
            end
        end

        function values = requestedColumnValues(IO, role)
            values = {};
            switch role
                case 'case'
                    values = NMDataIOTableRoleTools.fieldOr(IO, 'case_edit', {});
                    if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'caseId')
                        values = IO.tableColumnRoles.caseId;
                    end
                case 'label'
                    values = NMDataIOTableRoleTools.fieldOr(IO, 'label_edit', {});
                    if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'labels')
                        values = IO.tableColumnRoles.labels;
                    end
                case 'feature'
                    values = NMDataIOTableRoleTools.fieldOr(IO, 'feature_edit', {});
                    if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'features')
                        values = IO.tableColumnRoles.features;
                    end
                case 'covariate'
                    values = NMDataIOTableRoleTools.pickFirst(IO, {'covar_edit','covariateColumns','covarColumns'}, {});
                    if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'covariates')
                        values = IO.tableColumnRoles.covariates;
                    end
                case 'ignore'
                    values = NMDataIOTableRoleTools.pickFirst(IO, {'ignore_edit','ignoreColumns','ignoredColumns'}, {});
                    if isfield(IO,'tableColumnRoles') && isstruct(IO.tableColumnRoles) && isfield(IO.tableColumnRoles,'ignore')
                        values = IO.tableColumnRoles.ignore;
                    end
            end
            values = NMDataIOTableRoleTools.valueAsCell(values);
            values = values(~cellfun(@(x) NMDataIOTableRoleTools.isUnknown(x), values));
            values = unique(values, 'stable');
        end

        function [missing, requested] = missingRequestedColumns(displayNames, requested, internalNames)
            if nargin < 3, internalNames = {}; end
            requested = NMDataIOTableRoleTools.valueAsCell(requested);
            requested = requested(~cellfun(@(x) NMDataIOTableRoleTools.isUnknown(x), requested));
            requested = unique(requested, 'stable');
            known = [displayNames(:); internalNames(:)];
            missing = requested(~ismember(requested, known));
        end

        function [T, report, mess] = convertRoleColumnsToNumeric(T, roles, mess)
            report = struct('convertedColumns',{{}}, 'badColumns',{{}}, 'badDetails', struct('role',{},'column',{},'row',{},'value',{}));
            if nargin < 3, mess = []; end
            [T, report, mess] = NMDataIOTableRoleTools.convertColumnsByRole(T, roles.featureColumns, 'Feature', report, mess);
            [T, report, mess] = NMDataIOTableRoleTools.convertColumnsByRole(T, roles.covariateColumns, 'Covariate', report, mess);
        end

        function [T, report, mess] = convertColumnsByRole(T, columns, roleName, report, mess)
            for c = 1:numel(columns)
                nm = columns{c};
                [num, ok, detail] = NMDataIOTableRoleTools.columnToNumeric(T.(nm));
                if ok
                    T.(nm) = num;
                    report.convertedColumns{end+1} = nm; %#ok<AGROW>
                else
                    report.badColumns{end+1} = nm; %#ok<AGROW>
                    detail.role = roleName;
                    detail.column = nm;
                    report.badDetails(end+1,1) = detail; %#ok<AGROW>
                    displayName = NMDataIOTableRoleTools.displayForColumns(T.Properties.VariableNames, NMDataIOTableRoleTools.originalColumnNames(T), nm);
                    if iscell(displayName), displayName = displayName{1}; end
                    if isfield(detail,'row') && ~isnan(detail.row)
                        mess = GenerateMessageEntry(mess, sprintf('%s column ''%s'' must contain numeric values after missing-value conversion. First unsupported value ''%s'' is at row %g. If this text represents missing data, add it to Missing-value tokens; otherwise correct the source value.', roleName, displayName, detail.value, detail.row), 1, 'red*');
                    else
                        mess = GenerateMessageEntry(mess, sprintf('%s column ''%s'' must contain numeric values after missing-value conversion. If text values represent missing data, add them to Missing-value tokens; otherwise correct the source values.', roleName, displayName), 1, 'red*');
                    end
                end
            end
        end

        function txt = readableColumnList(names)
            if isempty(names)
                txt = '<none>';
            else
                txt = strjoin(names, ', ');
            end
        end

        function [ordered, fmap] = applyDiscoveryFeatureMap(candidates, IO, internalNames, displayNames)
            if nargin < 3 || isempty(internalNames), internalNames = candidates; end
            if nargin < 4 || isempty(displayNames), displayNames = internalNames; end
            target = NMDataIOTableRoleTools.discoveryFeatureNames(IO);
            candidateDisplay = NMDataIOTableRoleTools.displayForColumns(internalNames, displayNames, candidates);
            fmap = NMDataIOTableRoleTools.featureCorrespondence(candidateDisplay, target, candidates);
            fmap.targetSource = 'IO.featnames/IO.featnames_cv';
            fmap.incomingFeatureColumns = candidateDisplay;
            fmap.incomingInternalColumns = candidates;
            fmap.orderedFeatureColumns = candidateDisplay;
            fmap.orderedInternalColumns = candidates;
            fmap.incomingColumnIndex = [];
            ordered = candidates;
            if isempty(target), return; end
            if isempty(fmap.ambiguousColumns) && isempty(fmap.duplicateTargetColumns)
                idx = fmap.targetSourceIndex(~isnan(fmap.targetSourceIndex));
                ordered = candidates(idx);
                fmap.incomingColumnIndex = idx;
                fmap.orderedInternalColumns = ordered;
                fmap.orderedFeatureColumns = candidateDisplay(idx);
                fmap.reordered = ~isempty(idx) && ~isequal(idx(:)',1:numel(idx));
            end
        end

        function target = discoveryFeatureNames(IO)
            target = {};
            if isfield(IO,'oocvflag') && IO.oocvflag
                if isfield(IO,'featnames_cv') && ~isempty(IO.featnames_cv)
                    target = NMDataIOTableRoleTools.valueAsCell(IO.featnames_cv);
                elseif isfield(IO,'featnames') && ~isempty(IO.featnames)
                    target = NMDataIOTableRoleTools.valueAsCell(IO.featnames);
                end
            end
        end

        function [covars, covnames, report, mess] = extractNumericCovariates(T, covariateColumns, mess)
            if nargin < 3, mess = []; end
            covnames = NMDataIOTableRoleTools.displayForColumns(T.Properties.VariableNames, NMDataIOTableRoleTools.originalColumnNames(T), covariateColumns);
            covars = [];
            report = struct('nCovariates',numel(covariateColumns),'covariateColumns',{covnames},'internalCovariateColumns',{covariateColumns(:)'},'nonNumericColumns',{{}});
            if isempty(covariateColumns), return; end
            C = nan(height(T), numel(covariateColumns));
            bad = {};
            for j = 1:numel(covariateColumns)
                col = T.(covariateColumns{j});
                [num, ok] = NMDataIOTableRoleTools.columnToNumeric(col);
                if ~ok
                    bad{end+1} = covnames{j}; %#ok<AGROW>
                else
                    C(:,j) = num(:);
                end
            end
            report.nonNumericColumns = bad;
            if ~isempty(bad)
                mess = GenerateMessageEntry(mess, sprintf('Covariate column(s) must contain numeric values after missing-value conversion: %s. If text values represent missing data, add them to Missing-value tokens; otherwise correct the source values.', strjoin(bad, ', ')), 1, 'red*');
                return;
            end
            covars = C;
        end

        function report = buildImportReport(IO, T, roles, nanReport, covReport)
            report = struct();
            report.schemaVersion = 1;
            report.createdBy = 'ReadTabular';
            report.createdAt = datestr(now, 30);
            report.sourceType = 'table';
            report.groupmode = NMDataIOTableRoleTools.fieldOr(IO,'groupmode',NaN);
            report.source = NMDataIOTableRoleTools.fieldOr(IO,'M_edit','');
            report.sourceBasename = NMDataIOTableRoleTools.basename(report.source);
            report.nRowsRaw = height(T);
            report.nColumnsRaw = width(T);
            report.columnRoles = struct();
            report.columnRoles.allColumns = roles.allColumns;
            report.columnRoles.internalColumns = roles.internalColumns;
            report.columnRoles.caseId = roles.caseColumnName;
            report.columnRoles.caseIdInternal = roles.caseColumn;
            report.columnRoles.labels = roles.labelColumnNames;
            report.columnRoles.labelsInternal = roles.labelColumns;
            report.columnRoles.covariates = roles.covariateColumnNames;
            report.columnRoles.covariatesInternal = roles.covariateColumns;
            report.columnRoles.ignore = roles.ignoreColumnNames;
            report.columnRoles.ignoreInternal = roles.ignoreColumns;
            report.columnRoles.features = roles.featureColumnNames;
            report.columnRoles.featuresInternal = roles.featureColumns;
            report.columnRoles.explicitFeatures = roles.explicitFeatureColumnNames;
            report.columnRoles.explicitFeaturesInternal = roles.explicitFeatureColumns;
            report.columnNameMap = roles.columnNameMap;
            report.nanMapper = nanReport;
            report.covariates = covReport;
            report.oocvFeatureMap = roles.featureMap;
            report.userSelections = struct('selCasesPresent',isfield(IO,'selCases') && ~isempty(IO.selCases),'selFeatsPresent',isfield(IO,'selFeats') && ~isempty(IO.selFeats));
        end

        function [num, ok, detail] = columnToNumeric(col)
            ok = true;
            detail = struct('row',NaN,'value','','rows',[],'values',{{}},'nOffending',0);
            if isnumeric(col) || islogical(col)
                num = double(col); return;
            end
            [s, textOk, intrinsicMissing] = NMDataIOTableRoleTools.columnToText(col);
            if ~textOk
                num = nan(size(col));
                ok = false;
                detail.value = 'Column values could not be converted to text for numeric validation.';
                return;
            end
            s = s(:);
            intrinsicMissing = intrinsicMissing(:);
            num = str2double(s);
            num(intrinsicMissing) = NaN;
            trimmed = strtrim(s);
            nonEmpty = ~cellfun(@isempty, trimmed);
            bad = ~intrinsicMissing & nonEmpty & isnan(num);
            rows = find(bad);
            ok = isempty(rows);
            if ~ok
                detail.rows = rows(:)';
                detail.values = trimmed(rows(:))';
                detail.nOffending = numel(rows);
                detail.row = rows(1);
                detail.value = trimmed{rows(1)};
            end
        end

        function c = tableColumnAsCell(T, name)
            v = T.(name);
            if isnumeric(v)
                c = cellstr(num2str(v(:)));
            elseif iscell(v)
                c = v(:);
                for i = 1:numel(c)
                    if isnumeric(c{i}) && isscalar(c{i}), c{i} = num2str(c{i}); else, c{i} = char(string(c{i})); end
                end
            else
                c = cellstr(string(v(:)));
            end
        end

        function cols = resolveColumnList(internalNames, displayNames, v)
            raw = NMDataIOTableRoleTools.valueAsCell(v);
            raw = raw(~cellfun(@(x) NMDataIOTableRoleTools.isUnknown(x), raw));
            cols = {};
            for i = 1:numel(raw)
                hit = find(strcmp(displayNames, raw{i}), 1);
                if isempty(hit)
                    hit = find(strcmp(internalNames, raw{i}), 1);
                end
                if ~isempty(hit)
                    cols{end+1} = internalNames{hit}; %#ok<AGROW>
                end
            end
            cols = unique(cols, 'stable');
        end

        function out = firstExistingColumn(internalNames, displayNames, raw)
            out = '';
            raw = raw(~cellfun(@(x) NMDataIOTableRoleTools.isUnknown(x), raw));
            for i = 1:numel(raw)
                hit = find(strcmp(displayNames, raw{i}), 1);
                if isempty(hit)
                    hit = find(strcmp(internalNames, raw{i}), 1);
                end
                if ~isempty(hit)
                    out = internalNames{hit}; return;
                end
            end
        end

        function names = originalColumnNames(T)
            if exist('NMDataIOTableReadTools','class') == 8 || exist('NMDataIOTableReadTools','file') == 2
                names = NMDataIOTableReadTools.originalColumnNames(T);
            else
                names = T.Properties.VariableNames(:)';
            end
        end

        function display = displayForColumns(internalNames, displayNames, columns)
            returnChar = ischar(columns) || (isstring(columns) && isscalar(columns));
            columns = NMDataIOTableRoleTools.valueAsCell(columns);
            display = cell(size(columns));
            for i = 1:numel(columns)
                hit = find(strcmp(internalNames, columns{i}), 1);
                if isempty(hit) || hit > numel(displayNames)
                    display{i} = columns{i};
                else
                    display{i} = displayNames{hit};
                end
            end
            display = display(:)';
            if returnChar && ~isempty(display)
                display = display{1};
            end
        end

        function c = valueAsCell(v)
            if isempty(v), c = {}; return; end
            if isstring(v), c = cellstr(v(:));
            elseif ischar(v)
                if strcmp(v,'?'), c = {}; elseif contains(v, ','), c = regexp(v, '\s*,\s*', 'split'); else, c = cellstr(v); end
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v), c{i} = char(string(v{i})); end
                c = c(:);
            elseif isnumeric(v)
                c = cellstr(string(v(:)));
            else
                c = cellstr(string(v(:)));
            end
            c = c(:)';
        end

        function v = pickFirst(IO, names, defaultValue)
            v = defaultValue;
            if ~isstruct(IO), return; end
            for i = 1:numel(names)
                if isfield(IO,names{i}) && ~isempty(IO.(names{i}))
                    v = IO.(names{i}); return;
                end
            end
        end

        function tf = isUnknown(v)
            if isempty(v), tf = true; return; end
            if iscell(v), tf = isempty(v) || all(cellfun(@NMDataIOTableRoleTools.isUnknown, v)); return; end
            try
                s = strtrim(char(string(v)));
                tf = isempty(s) || strcmp(s,'?');
            catch
                tf = false;
            end
        end

        function opts = nanMapperOptionsFromIO(IO)
            opts = struct();
            opts.enabled = false;
            opts.tokens = {'NA','N/A','n/a','na','.','-','','missing','Missing','MISSING'};
            opts.caseInsensitive = true;
            opts.trimWhitespace = true;
            opts.applyToFeatures = true;
            opts.applyToCovariates = true;
            opts.applyToLabels = false;
            opts.applyToCaseIds = false;

            if nargin < 1 || ~isstruct(IO), return; end

            if isfield(IO,'nanMapper') && isstruct(IO.nanMapper)
                nm = IO.nanMapper;
                opts.enabled = NMDataIOTableRoleTools.fieldOr(nm,'enabled',opts.enabled);
                opts.tokens = NMDataIOTableRoleTools.nanTokensFromValue(NMDataIOTableRoleTools.fieldOr(nm,'tokens',opts.tokens));
                opts.caseInsensitive = NMDataIOTableRoleTools.fieldOr(nm,'caseInsensitive',opts.caseInsensitive);
                opts.trimWhitespace = NMDataIOTableRoleTools.fieldOr(nm,'trimWhitespace',opts.trimWhitespace);
                opts.applyToFeatures = NMDataIOTableRoleTools.fieldOr(nm,'applyToFeatures',opts.applyToFeatures);
                opts.applyToCovariates = NMDataIOTableRoleTools.fieldOr(nm,'applyToCovariates',opts.applyToCovariates);
                opts.applyToLabels = NMDataIOTableRoleTools.fieldOr(nm,'applyToLabels',opts.applyToLabels);
                opts.applyToCaseIds = NMDataIOTableRoleTools.fieldOr(nm,'applyToCaseIds',opts.applyToCaseIds);
            end
            if isfield(IO,'nanMapperEnabled')
                opts.enabled = logical(IO.nanMapperEnabled);
            end
            if isfield(IO,'nanTokens')
                opts.tokens = NMDataIOTableRoleTools.nanTokensFromValue(IO.nanTokens);
            end
            opts.enabled = logical(opts.enabled);
            opts.caseInsensitive = logical(opts.caseInsensitive);
            opts.trimWhitespace = logical(opts.trimWhitespace);
            opts.applyToFeatures = logical(opts.applyToFeatures);
            opts.applyToCovariates = logical(opts.applyToCovariates);
            opts.applyToLabels = logical(opts.applyToLabels);
            opts.applyToCaseIds = logical(opts.applyToCaseIds);
        end

        function [T, report] = applyNaNMapperToColumns(T, columnNames, opts)
            if nargin < 3 || isempty(opts), opts = NMDataIOTableRoleTools.nanMapperOptionsFromIO(struct()); end
            report = NMDataIOTableRoleTools.emptyNaNMapperReport(opts);
            if ~istable(T) || isempty(columnNames) || ~isfield(opts,'enabled') || ~opts.enabled
                return;
            end
            names = T.Properties.VariableNames;
            columnNames = NMDataIOTableRoleTools.resolveNaNMapperColumns(names, columnNames);
            report.columnsRequested = columnNames(:)';
            if isempty(columnNames), return; end
            for i = 1:numel(columnNames)
                nm = columnNames{i};
                if ~ismember(nm, names), continue; end
                [newCol, colReport] = NMDataIOTableRoleTools.mapNaNMapperColumn(T.(nm), opts);
                T.(nm) = newCol;
                colReport.name = nm;
                report.byColumn(end+1,1) = colReport; %#ok<AGROW>
                report.nMappedTotal = report.nMappedTotal + colReport.nMapped;
                if colReport.convertedToNumeric
                    report.nColumnsConvertedToNumeric = report.nColumnsConvertedToNumeric + 1;
                end
                if colReport.unresolvedNonNumeric
                    report.unresolvedColumns{end+1} = nm; %#ok<AGROW>
                end
            end
            report.enabled = opts.enabled;
        end

        function [newCol, report] = mapNaNMapperColumn(col, opts)
            report = struct('name','', 'nValues', numel(col), 'nMapped', 0, ...
                'convertedToNumeric', false, 'unresolvedNonNumeric', false);
            newCol = col;
            if isnumeric(col) || islogical(col)
                return;
            end
            [txt, ok, intrinsicMissing] = NMDataIOTableRoleTools.columnToText(col);
            if ~ok, return; end
            txt = txt(:);
            intrinsicMissing = intrinsicMissing(:);
            cmpTxt = txt;
            if opts.trimWhitespace
                cmpTxt = strtrim(cmpTxt);
            end
            toks = NMDataIOTableRoleTools.nanTokensFromValue(opts.tokens);
            if opts.trimWhitespace
                toks = strtrim(toks);
            end
            tokenMask = false(size(cmpTxt));
            for t = 1:numel(toks)
                if opts.caseInsensitive
                    tokenMask = tokenMask | (~intrinsicMissing & strcmpi(cmpTxt, toks{t}));
                else
                    tokenMask = tokenMask | (~intrinsicMissing & strcmp(cmpTxt, toks{t}));
                end
            end
            report.nMapped = nnz(tokenMask);
            numVals = str2double(txt);
            numVals(intrinsicMissing) = NaN;
            nonEmpty = ~cellfun(@isempty, strtrim(txt));
            badNumeric = ~intrinsicMissing & nonEmpty & ~tokenMask & isnan(numVals);
            if ~any(badNumeric)
                numVals(tokenMask) = NaN;
                newCol = reshape(numVals, size(col));
                report.convertedToNumeric = true;
            else
                report.unresolvedNonNumeric = true;
                if report.nMapped > 0 || any(intrinsicMissing)
                    if iscell(col)
                        c = col;
                    else
                        c = cellstr(string(col));
                    end
                    c(tokenMask | intrinsicMissing) = {NaN};
                    newCol = reshape(c, size(col));
                end
            end
        end

        function report = emptyNaNMapperReport(opts)
            if nargin < 1 || isempty(opts), opts = struct('enabled',false,'tokens',{{}}); end
            report = struct();
            report.enabled = isfield(opts,'enabled') && logical(opts.enabled);
            if isfield(opts,'tokens'), report.tokens = opts.tokens; else, report.tokens = {}; end
            report.columnsRequested = {};
            report.nMappedTotal = 0;
            report.nColumnsConvertedToNumeric = 0;
            report.unresolvedColumns = {};
            report.byColumn = struct('name',{}, 'nValues',{}, 'nMapped',{}, ...
                'convertedToNumeric',{}, 'unresolvedNonNumeric',{});
        end

        function columns = resolveNaNMapperColumns(names, columns)
            if isempty(columns), columns = {}; return; end
            if isnumeric(columns)
                ii = columns(columns >= 1 & columns <= numel(names));
                columns = names(ii);
                return;
            end
            columns = NMDataIOTableRoleTools.nanTokensFromValue(columns);
            keep = false(size(columns));
            for i = 1:numel(columns)
                keep(i) = any(strcmp(names, columns{i}));
            end
            columns = columns(keep);
        end

        function tokens = nanTokensFromValue(v)
            if isempty(v), tokens = {}; return; end
            if isstring(v), tokens = cellstr(v(:));
            elseif ischar(v)
                if contains(v, ',')
                    tokens = regexp(v, '\s*,\s*', 'split');
                else
                    tokens = cellstr(v);
                end
            elseif iscell(v)
                tokens = cell(size(v));
                for i = 1:numel(v), tokens{i} = char(string(v{i})); end
                tokens = tokens(:);
            else
                tokens = cellstr(string(v(:)));
            end
            tokens = tokens(:)';
        end

        function [txt, ok, intrinsicMissing] = columnToText(col)
            % columnToText  Normalize heterogeneous tabular values while retaining intrinsic missingness.
            ok = true;
            intrinsicMissing = false(size(col));
            try
                if iscell(col)
                    txt = cell(size(col));
                    intrinsicMissing = false(size(col));
                    for i = 1:numel(col)
                        v = col{i};
                        if isempty(v)
                            txt{i} = '';
                            intrinsicMissing(i) = true;
                        elseif isnumeric(v) || islogical(v)
                            if isscalar(v)
                                if isnumeric(v) && isnan(v)
                                    txt{i} = '';
                                    intrinsicMissing(i) = true;
                                else
                                    txt{i} = num2str(v);
                                end
                            else
                                txt{i} = '<non-scalar numeric cell>';
                            end
                        else
                            missingValue = false;
                            try
                                miss = ismissing(v);
                                missingValue = isscalar(miss) && logical(miss);
                            catch
                                missingValue = false;
                            end
                            if missingValue
                                txt{i} = '';
                                intrinsicMissing(i) = true;
                            else
                                txt{i} = char(string(v));
                            end
                        end
                    end
                elseif ischar(col)
                    txt = cellstr(col);
                    intrinsicMissing = cellfun(@(x) isempty(strtrim(x)), txt);
                else
                    s = string(col);
                    intrinsicMissing = ismissing(s);
                    s(intrinsicMissing) = "";
                    txt = cellstr(s);
                    intrinsicMissing = reshape(logical(intrinsicMissing), size(txt));
                end
            catch
                txt = {};
                intrinsicMissing = false(size(col));
                ok = false;
            end
        end

        function b = basename(p)
            b = '';
            try
                if isempty(p), return; end
                [~,n,e] = fileparts(char(string(p))); b = [n e];
            catch
                b = '';
            end
        end

        function v = fieldOr(s, name, defaultValue)
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = defaultValue;
            end
        end
    end
end
