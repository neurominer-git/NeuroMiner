classdef NMDataIOLabelStatsTools
% NMDataIOLabelStatsTools
% -------------------------------------------------------------------------
% Purpose / authority:
%   Canonical DataIO label normalization plus workspace-level label summaries for overview,
%   NM canvas and parameter configurator consumption.
%
% Classification invariant:
%   Training establishes the raw source value -> canonical NM class mapping once. Labelled OOCV
%   data apply that persisted training map exactly; OOCV encounter order, class frequency or a
%   missing training class must never define a new class axis. NaN remains missing and an unseen
%   OOCV raw class is explicit/blocking.
% -------------------------------------------------------------------------

    methods (Static)
        function stats = emptySummary()
            % emptySummary  Create the fixed-schema empty label summary used by overview cards.
            %
            % No required inputs -> stats.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            stats = struct();
            stats.schemaVersion = 1;
            stats.createdBy = 'NMDataIOLabelStatsTools';
            stats.mode = 'unknown';
            stats.nCases = NaN;
            stats.hasLabels = false;
            stats.nLabelColumns = NaN;
            stats.nValidLabels = NaN;
            stats.nMissingLabels = NaN;
            stats.missingFraction = NaN;
            stats.labelImputationNeeded = false;
            stats.message = 'Labels are not available.';
            stats.classDistribution = struct('name', {}, 'value', {}, 'count', {});
            stats.nClasses = NaN;
            stats.regression = struct('min', NaN, 'max', NaN, 'median', NaN, 'mean', NaN);
        end

        function [labels, groupNames, messages, classMap] = normalizeForTransfer(rawLabels, modeflag, groupNamesIn, sourceTag, classMapIn)
            % normalizeForTransfer  Canonical explicit-label materializer for DataIO transfer paths.
            %
            % Classification accepts one label per subject represented as numeric/logical,
            % char rows, string, cell, or categorical values. Training imports establish one
            % deterministic source-label -> canonical 1..K map. OOCV/application imports may
            % supply that persisted map through classMapIn so represented class subsets retain
            % the exact training class IDs and never derive a new local class order.
            %
            % Numeric NaN is retained as a missing target value; +/-Inf remains invalid.
            if nargin < 2 || isempty(modeflag), modeflag = 'classification'; end
            if nargin < 3, groupNamesIn = {}; end
            if nargin < 4 || isempty(sourceTag), sourceTag = 'labels.transfer'; end
            if nargin < 5, classMapIn = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            labels = [];
            groupNames = {};
            classMap = struct();
            mode = lower(strtrim(char(string(modeflag))));
            if contains(mode,'reg')
                if ~(isnumeric(rawLabels) || islogical(rawLabels)) || ~isreal(rawLabels)
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        sprintf('Regression labels must be a real numeric/logical array; received %s.', class(rawLabels)), 1, 'red*');
                    return;
                end
                labels = double(rawLabels);
                if any(isinf(labels(:)))
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        'Regression labels contain infinite values. Replace +/-Inf before import; NaN is allowed for missing target observations.', 1, 'red*');
                    labels = [];
                end
                return;
            end

            if isstruct(classMapIn) && ~isempty(fieldnames(classMapIn))
                [labels, groupNames, messages, classMap] = NMDataIOLabelStatsTools.applyClassificationMap(rawLabels, classMapIn, sourceTag);
                return;
            end

            if isnumeric(rawLabels) || islogical(rawLabels)
                if ~isreal(rawLabels) || ~isvector(rawLabels)
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        'Classification requires exactly one real label value per subject.', 1, 'red*');
                    return;
                end
                sourceLabels = double(rawLabels(:));
                if any(isinf(sourceLabels))
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        'Classification labels contain infinite values. Replace +/-Inf before import; NaN is allowed for missing target observations.', 1, 'red*');
                    return;
                end
                missing = isnan(sourceLabels);
                finiteLabels = sourceLabels(~missing);
                classValues = unique(finiteLabels);
                labels = nan(size(sourceLabels));
                for i = 1:numel(classValues)
                    labels(sourceLabels == classValues(i)) = i;
                end
                groupNames = NMDataIOLabelStatsTools.asGroupNameCell(groupNamesIn);
                if isempty(groupNames) || (numel(groupNames)==1 && strcmp(strtrim(groupNames{1}),'?')) || numel(groupNames) ~= numel(classValues)
                    groupNames = cellstr(string(classValues(:)));
                end
                groupNames = groupNames(:)';
                classMap = NMDataIOLabelStatsTools.makeClassificationMap('numeric', classValues(:)', groupNames);
                if any(classValues(:)' ~= 1:numel(classValues))
                    messages = [messages; NMDataIOMessageTools.make('info', false, sourceTag, ...
                        sprintf('Numeric classification codes were normalized to contiguous NM class IDs 1..%g.', numel(classValues)), 0, 'blue')];
                end
                if any(missing)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, sourceTag, ...
                        sprintf('Classification labels contain %g missing value(s). These labels remain missing and must be handled before model fitting.', nnz(missing)), 2, 'orange')];
                end
                return;
            end

            try
                if iscategorical(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    textLabels = cellstr(string(rawLabels(:)));
                elseif isstring(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    textLabels = cellstr(rawLabels(:));
                elseif ischar(rawLabels)
                    textLabels = cellstr(rawLabels);
                elseif iscell(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    textLabels = cell(numel(rawLabels),1);
                    for i = 1:numel(rawLabels)
                        value = rawLabels{i};
                        if isempty(value)
                            textLabels{i} = '';
                        elseif ischar(value)
                            textLabels{i} = value;
                        elseif (isstring(value) || iscategorical(value) || isnumeric(value) || islogical(value)) && isscalar(value)
                            textLabels{i} = char(string(value));
                        else
                            error('NMDataIO:LabelCellValue','Classification label cells must contain scalar text, numeric, logical, or categorical values.');
                        end
                    end
                else
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        sprintf('Unsupported classification label type: %s. Use numeric/logical, char, string, cell, or categorical labels.', class(rawLabels)), 1, 'red*');
                    return;
                end
            catch ME
                if strcmp(ME.identifier,'NMDataIO:LabelShape')
                    msg = ME.message;
                else
                    msg = sprintf('Classification labels of type %s could not be converted to a label vector.', class(rawLabels));
                end
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, msg, 1, 'red*');
                return;
            end
            textLabels = textLabels(:);
            labelStrings = string(textLabels);
            missing = ismissing(labelStrings) | strlength(strtrim(labelStrings)) == 0 | strcmp(strtrim(labelStrings),'?');
            if any(missing)
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                    sprintf('Classification labels contain %g empty/unknown value(s). Remove or recode missing labels before import.', nnz(missing)), 1, 'red*');
                return;
            end
            % Intrinsic text classes follow first occurrence on the aligned training case axis.
            % Textual numeric codes retain their numeric-code order.
            sourceValues = unique(textLabels, 'stable');
            numericSourceValues = cellfun(@str2double, sourceValues);
            if all(isfinite(numericSourceValues)) && numel(unique(numericSourceValues)) == numel(sourceValues)
                [~, sourceOrder] = sort(numericSourceValues);
                sourceValues = sourceValues(sourceOrder);
            end
            labels = nan(numel(textLabels),1);
            for i = 1:numel(sourceValues)
                labels(strcmp(textLabels, sourceValues{i})) = i;
            end
            groupNames = NMDataIOLabelStatsTools.asGroupNameCell(groupNamesIn);
            if isempty(groupNames) || (numel(groupNames)==1 && strcmp(strtrim(groupNames{1}),'?')) || numel(groupNames) ~= numel(sourceValues)
                groupNames = sourceValues(:)';
            end
            groupNames = groupNames(:)';
            classMap = NMDataIOLabelStatsTools.makeClassificationMap('text', sourceValues(:)', groupNames);
            messages = [messages; NMDataIOMessageTools.make('info', false, sourceTag, ...
                sprintf('Text classification source values were encoded to numeric NM class IDs (%g class(es)).', numel(groupNames)), 0, 'blue')];
        end

        function [labels, groupNames, messages, classMap] = applyClassificationMap(rawLabels, classMapIn, sourceTag)
            % applyClassificationMap  Apply one persisted training class map to classification labels.
            %
            % OOCV/application imports may represent any subset of trained classes. The
            % canonical IDs always remain those established by training; unknown source
            % values are blocking and missing numeric labels remain NaN.
            if nargin < 3 || isempty(sourceTag), sourceTag = 'labels.classMap'; end
            messages = NMDataIOMessageTools.emptyMessages();
            labels = [];
            groupNames = {};
            classMap = NMDataIOLabelStatsTools.normalizeClassificationMap(classMapIn);
            if isempty(fieldnames(classMap))
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                    'Classification label mapping is missing or invalid.', 1, 'red*');
                return;
            end
            groupNames = classMap.groupNames;
            K = numel(classMap.canonicalIds);

            if isnumeric(rawLabels) || islogical(rawLabels)
                if ~isreal(rawLabels) || ~isvector(rawLabels)
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        'Classification requires exactly one real label value per subject.', 1, 'red*');
                    return;
                end
                values = double(rawLabels(:));
                if any(isinf(values))
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        'Classification labels contain infinite values. Replace +/-Inf before import; NaN is allowed for missing target observations.', 1, 'red*');
                    return;
                end
                missing = isnan(values);
                labels = nan(size(values));
                if strcmp(classMap.sourceKind,'numeric')
                    sourceValues = classMap.sourceValues;
                else
                    sourceValues = cellfun(@str2double, classMap.sourceValues);
                    if any(~isfinite(sourceValues)) || numel(unique(sourceValues)) ~= K
                        messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                            'Numeric OOCV class labels cannot be matched to the persisted text source values of the training class map.', 1, 'red*');
                        return;
                    end
                end
                for i = 1:K
                    labels(values == sourceValues(i)) = classMap.canonicalIds(i);
                end
                unknown = ~missing & isnan(labels);
                if any(unknown)
                    bad = unique(values(unknown),'stable');
                    messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                        sprintf('OOCV classification labels contain source value(s) not present in the training label map: %s.', NMDataIOLabelStatsTools.previewValues(bad)), 1, 'red*');
                    labels = [];
                    return;
                end
                if any(missing)
                    messages = [messages; NMDataIOMessageTools.make('warn', false, sourceTag, ...
                        sprintf('Classification labels contain %g missing value(s). These labels remain missing and must be handled before model fitting.', nnz(missing)), 2, 'orange')];
                end
                return;
            end

            try
                if iscategorical(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    values = cellstr(string(rawLabels(:)));
                elseif isstring(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    values = cellstr(rawLabels(:));
                elseif ischar(rawLabels)
                    values = cellstr(rawLabels);
                elseif iscell(rawLabels)
                    if ~isvector(rawLabels), error('NMDataIO:LabelShape','Classification requires exactly one label value per subject.'); end
                    values = cell(numel(rawLabels),1);
                    for i = 1:numel(rawLabels), values{i} = char(string(rawLabels{i})); end
                else
                    error('NMDataIO:LabelType','Unsupported classification label type.');
                end
            catch ME
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, ME.message, 1, 'red*');
                return;
            end
            values = values(:);
            missing = cellfun(@(x)isempty(strtrim(x)) || strcmp(strtrim(x),'?'), values);
            if any(missing)
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                    sprintf('Classification labels contain %g empty/unknown value(s). Remove or recode missing labels before import.', nnz(missing)), 1, 'red*');
                return;
            end
            labels = nan(numel(values),1);
            numericMissing = false(numel(values),1);
            if strcmp(classMap.sourceKind,'text')
                for i = 1:K, labels(strcmp(values,classMap.sourceValues{i})) = classMap.canonicalIds(i); end
            elseif strcmp(classMap.sourceKind,'numeric')
                numericValues = cellfun(@str2double,values);
                numericMissing = strcmpi(strtrim(values),'nan');
                for i = 1:K, labels(numericValues == classMap.sourceValues(i)) = classMap.canonicalIds(i); end
            end
            unknown = isnan(labels) & ~numericMissing;
            if any(unknown)
                bad = unique(values(unknown),'stable');
                messages = NMDataIOMessageTools.make('danger', true, sourceTag, ...
                    sprintf('OOCV classification labels contain source value(s) not present in the training label map: %s.', strjoin(bad(1:min(numel(bad),8)), ', ')), 1, 'red*');
                labels = [];
                return;
            end
            if any(numericMissing)
                messages = [messages; NMDataIOMessageTools.make('warn', false, sourceTag, ...
                    sprintf('Classification labels contain %g missing value(s). These labels remain missing and must be handled before model fitting.', nnz(numericMissing)), 2, 'orange')];
            end
        end

        function map = makeClassificationMap(sourceKind, sourceValues, groupNames)
            % makeClassificationMap  Create the fixed-schema persisted training label map.
            map = struct();
            map.schemaVersion = 1;
            map.sourceKind = lower(strtrim(char(string(sourceKind))));
            if strcmp(map.sourceKind,'numeric')
                map.sourceValues = double(sourceValues(:)');
            else
                map.sourceKind = 'text';
                map.sourceValues = NMDataIOLabelStatsTools.asGroupNameCell(sourceValues);
            end
            map.canonicalIds = 1:numel(map.sourceValues);
            map.groupNames = NMDataIOLabelStatsTools.asGroupNameCell(groupNames);
            if numel(map.groupNames) ~= numel(map.canonicalIds)
                map = struct();
            end
        end

        function map = normalizeClassificationMap(mapIn)
            % normalizeClassificationMap  Validate and normalize a persisted classification map.
            map = struct();
            if ~isstruct(mapIn) || numel(mapIn) ~= 1 || ...
                    ~isfield(mapIn,'sourceKind') || ~isfield(mapIn,'sourceValues') || ...
                    ~isfield(mapIn,'canonicalIds') || ~isfield(mapIn,'groupNames')
                return;
            end
            kind = lower(strtrim(char(string(mapIn.sourceKind))));
            ids = double(mapIn.canonicalIds(:)');
            groups = NMDataIOLabelStatsTools.asGroupNameCell(mapIn.groupNames);
            if isempty(ids) || ~isequal(ids,1:numel(ids)) || numel(groups) ~= numel(ids), return; end
            if strcmp(kind,'numeric')
                values = double(mapIn.sourceValues(:)');
                if numel(values) ~= numel(ids) || any(~isfinite(values)) || numel(unique(values)) ~= numel(values), return; end
            elseif strcmp(kind,'text')
                values = NMDataIOLabelStatsTools.asGroupNameCell(mapIn.sourceValues);
                if numel(values) ~= numel(ids) || numel(unique(values)) ~= numel(values) || any(cellfun(@isempty,values)), return; end
            else
                return;
            end
            map = struct('schemaVersion',1,'sourceKind',kind,'sourceValues',{values}, ...
                'canonicalIds',ids,'groupNames',{groups});
            if strcmp(kind,'numeric'), map.sourceValues = values; end
        end

        function stats = summarizeWorkspace(NM)
            % summarizeWorkspace  Summarize label availability and class/regression statistics across the NM workspace.
            %
            % NM -> stats.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            stats = NMDataIOLabelStatsTools.emptySummary();
            stats.mode = NMDataIOLabelStatsTools.modeName(NM);
            stats.nCases = NMDataIOLabelStatsTools.caseCount(NM);
            if ~(isstruct(NM) && isfield(NM,'label') && ~isempty(NM.label))
                return;
            end

            L = NM.label;
            stats.hasLabels = true;
            stats.nLabelColumns = double(size(L,2));
            missingRows = NMDataIOLabelStatsTools.missingLabelRows(L);
            if isnan(stats.nCases)
                stats.nCases = double(size(L,1));
            end
            stats.nMissingLabels = double(nnz(missingRows));
            stats.nValidLabels = double(numel(missingRows) - nnz(missingRows));
            stats.missingFraction = stats.nMissingLabels / max(1, numel(missingRows));
            stats.labelImputationNeeded = stats.nMissingLabels > 0;

            if strcmpi(stats.mode, 'regression')
                stats = NMDataIOLabelStatsTools.addRegressionStats(stats, L, missingRows);
            else
                stats = NMDataIOLabelStatsTools.addClassificationStats(stats, NM, L, missingRows);
            end

            if stats.labelImputationNeeded
                stats.message = sprintf('Missing labels: %g. Label imputation will be needed before model training.', stats.nMissingLabels);
            else
                stats.message = 'Missing labels: 0.';
            end
        end

        function stats = addRegressionStats(stats, L, missingRows)
            % addRegressionStats  Attach regression-label descriptive statistics and missingness to a label summary.
            %
            % Consumes stats, L, missingRows; returns stats.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            x = L;
            if ~isnumeric(x) && ~islogical(x)
                stats.message = 'Regression labels are not numeric.';
                return;
            end
            if size(x,2) > 1
                x = x(:,1);
            end
            x = double(x(:));
            valid = ~missingRows(:) & isfinite(x);
            xv = x(valid);
            stats.nValidLabels = double(numel(xv));
            stats.nMissingLabels = double(numel(x) - numel(xv));
            stats.missingFraction = stats.nMissingLabels / max(1, numel(x));
            stats.labelImputationNeeded = stats.nMissingLabels > 0;
            if ~isempty(xv)
                stats.regression.min = double(min(xv));
                stats.regression.max = double(max(xv));
                stats.regression.median = double(median(xv));
                stats.regression.mean = double(mean(xv));
            end
        end

        function stats = addClassificationStats(stats, NM, L, missingRows)
            % addClassificationStats  Attach classification counts and group labels to a label summary.
            %
            % Consumes stats, NM, L, missingRows; returns stats.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            values = NMDataIOLabelStatsTools.classVector(L, missingRows);
            valid = ~missingRows(:) & ~isnan(values(:));
            classValues = values(valid);
            u = unique(classValues, 'stable');
            names = NMDataIOLabelStatsTools.classNames(NM, numel(u));
            dist = struct('name', {}, 'value', {}, 'count', {});
            for i = 1:numel(u)
                dist(i).name = names{i}; %#ok<AGROW>
                dist(i).value = double(u(i)); %#ok<AGROW>
                dist(i).count = double(nnz(classValues == u(i))); %#ok<AGROW>
            end
            stats.classDistribution = dist;
            stats.nClasses = double(numel(u));
        end

        function mode = modeName(NM)
            % modeName  Return the normalized NM analysis mode name for label-summary logic.
            %
            % NM -> mode.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            mode = 'unknown';
            if ~(isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)), return; end
            mf = NM.modeflag;
            if isnumeric(mf) && isscalar(mf)
                if double(mf) == 2
                    mode = 'regression';
                else
                    mode = 'classification';
                end
                return;
            end
            s = lower(strtrim(char(string(mf))));
            if contains(s, 'reg')
                mode = 'regression';
            elseif contains(s, 'class') || strcmp(s,'1')
                mode = 'classification';
            else
                mode = s;
            end
        end

        function n = caseCount(NM)
            % caseCount  Return the number of workspace cases represented by labels or NM fields.
            %
            % NM -> n.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            if isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                n = double(numel(NM.cases));
            elseif isstruct(NM) && isfield(NM,'label') && ~isempty(NM.label)
                n = double(size(NM.label,1));
            end
        end

        function missingRows = missingLabelRows(L)
            % missingLabelRows  Return row indices whose label entries are missing or unusable.
            %
            % L -> missingRows.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isnumeric(L) || islogical(L)
                missingRows = all(isnan(double(L)), 2);
            elseif iscell(L)
                missingRows = false(size(L,1),1);
                for i = 1:size(L,1)
                    row = L(i,:);
                    missingRows(i) = all(cellfun(@NMDataIOLabelStatsTools.isMissingCell, row));
                end
            else
                S = string(L);
                missingRows = all(ismissing(S) | strlength(strtrim(S)) == 0, 2);
            end
        end

        function tf = isMissingCell(x)
            % isMissingCell  Identify empty or NaN-like cell entries when summarizing label missingness.
            %
            % X -> tf.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(x)
                tf = true;
            elseif isnumeric(x) || islogical(x)
                tf = all(isnan(double(x(:))));
            elseif ischar(x) || isstring(x)
                tf = strlength(strtrim(string(x))) == 0 || ismissing(string(x));
            else
                tf = false;
            end
        end

        function values = classVector(L, missingRows)
            % classVector  Return the non-missing class labels used for classification counts.
            %
            % L, missingRows -> values.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isnumeric(L) || islogical(L)
                X = double(L);
                if size(X,2) == 1
                    values = X(:);
                else
                    values = nan(size(X,1),1);
                    for i = 1:size(X,1)
                        if missingRows(i), continue; end
                        [mx, idx] = max(X(i,:));
                        if isfinite(mx)
                            values(i) = idx;
                        end
                    end
                end
            else
                S = string(L(:,1));
                values = nan(size(S,1),1);
                valid = ~missingRows(:);
                u = unique(S(valid), 'stable');
                for i = 1:numel(u)
                    values(valid & S == u(i)) = i;
                end
            end
        end

        function names = classNames(NM, n)
            % classNames  Return display names for classification groups from NM or generated fallbacks.
            %
            % NM, n -> names.
            % It feeds workspace-level DataIO overview summaries without changing label vectors.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            names = cell(1,n);
            for i = 1:n
                names{i} = sprintf('Class %d', i);
            end
            if isstruct(NM) && isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                g = NM.groupnames;
                if ischar(g), g = cellstr(g); end
                if isstring(g), g = cellstr(g); end
                if iscell(g)
                    for i = 1:min(n, numel(g))
                        names{i} = char(string(g{i}));
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function txt = previewValues(values)
            values = values(:)';
            n = min(numel(values),8);
            parts = arrayfun(@(x)sprintf('%.17g',x),values(1:n),'UniformOutput',false);
            txt = strjoin(parts,', ');
            if numel(values) > n, txt = [txt ', ...']; end
        end

        function names = asGroupNameCell(value)
            % asGroupNameCell  Normalize an optional class-name axis without inventing names.
            if isempty(value), names = {}; return; end
            if ischar(value)
                names = cellstr(value);
            elseif isstring(value) || iscategorical(value)
                names = cellstr(string(value(:)));
            elseif iscell(value)
                names = cell(size(value));
                for i = 1:numel(value), names{i} = char(string(value{i})); end
            elseif isnumeric(value) || islogical(value)
                names = cellstr(string(value(:)));
            else
                error('NMDataIOLabelStatsTools:groupNamesType', ...
                    'Group names must be supplied as text-like or numeric scalar values; received %s.', class(value));
            end
            names = names(:)';
        end
    end
end
