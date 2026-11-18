classdef NMWorkspaceTools
% NMWorkspaceTools
% Safe workspace-variable catalog and resolution helpers for the browser UI.
% The browser receives names/metadata only. Values are resolved inside MATLAB.

    methods (Static)
        function catalog = catalog(workspace, ctx)
            % catalog  Build a safe catalog of variables in the requested MATLAB workspace.
            %
            % Uses whos metadata from the base or caller workspace, enriches selected variables with bounded value hints, and returns names/types/sizes for browser or API selection. Full values are not exposed to the browser.
            if nargin < 1 || isempty(workspace), workspace = 'base'; end
            if nargin < 2, ctx = struct(); end
            switch lower(workspace)
                case 'base'
                    w = evalin('base','whos');
                case 'caller'
                    w = evalin('caller','whos');
                otherwise
                    error('NMWorkspaceTools:badWorkspace','workspace must be base or caller.');
            end
            catalog = NMWorkspaceTools.fromWhos(w, ctx);
            catalog = NMWorkspaceTools.enrichCatalogWithValueHints(catalog, workspace, ctx);
        end

        function catalog = fromWhos(w, ctx)
            % fromWhos  Convert MATLAB whos output into the fixed workspace-catalog schema.
            %
            % Normalizes variable names, classes, sizes and byte counts, then classifies candidate roles such as labels, covariates or feature matrices from metadata. It is read-only and does not resolve values.
            %
            % ctx.nFeatures: exposes the n features execution-context value to preprocessing/runtime code.
            if nargin < 2, ctx = struct(); end
            nFeatures = [];
            if isstruct(ctx) && isfield(ctx,'nFeatures') && ~isempty(ctx.nFeatures)
                nFeatures = ctx.nFeatures;
            end
            catalog = cell(1,numel(w));
            for i = 1:numel(w)
                sz = w(i).size;
                if isempty(sz), sz = [0 0]; end
                isNumeric = any(strcmp(w(i).class, {'double','single','logical','uint8','uint16','uint32','uint64','int8','int16','int32','int64'}));
                isVector = numel(sz) == 2 && (sz(1) == 1 || sz(2) == 1);
                nElem = prod(double(sz));
                dim2 = NaN;
                if numel(sz) >= 2, dim2 = sz(2); end
                featureVectorMatch = false;
                featureDim2Match = false;
                if ~isempty(nFeatures) && isfinite(nFeatures)
                    featureVectorMatch = isVector && nElem == nFeatures;
                    featureDim2Match = numel(sz) >= 2 && dim2 == nFeatures;
                end
                catalog{i} = struct( ...
                    'name', w(i).name, ...
                    'class', w(i).class, ...
                    'size', sz, ...
                    'bytes', w(i).bytes, ...
                    'ndims', numel(sz), ...
                    'numel', nElem, ...
                    'dim2', dim2, ...
                    'isNumeric', isNumeric, ...
                    'isStruct', strcmp(w(i).class,'struct'), ...
                    'isVector', isVector, ...
                    'featureVectorMatch', featureVectorMatch, ...
                    'featureDim2Match', featureDim2Match, ...
                    'featureCompatible', featureVectorMatch || featureDim2Match);
            end
        end

        function catalog = enrichCatalogWithValueHints(catalog, workspace, ctx)
            % enrichCatalogWithValueHints  Add bounded previews and role hints to workspace catalog entries.
            %
            % Resolves only small or metadata-safe values from MATLAB to improve browser selection quality. The method avoids exposing full feature matrices and keeps heavy data in the workspace.
            %
            % ctx.nSubjects: exposes the n subjects execution-context value to preprocessing/runtime code.
            if nargin < 2 || isempty(workspace), workspace = 'base'; end
            if nargin < 3, ctx = struct(); end
            nSubjects = [];
            if isstruct(ctx) && isfield(ctx,'nSubjects') && ~isempty(ctx.nSubjects)
                nSubjects = ctx.nSubjects;
            end
            for i = 1:numel(catalog)
                try
                    w = catalog{i};
                    w.validLabelVector = false;
                    w.subjectVectorMatch = false;
                    w.taskHint = '';
                    w.taskHintReason = '';
                    w.nUniqueNonMissing = [];
                    if ~isfield(w,'name') || isempty(w.name) || ~isvarname(w.name)
                        catalog{i} = w; continue;
                    end
                    % Value inspection is only used for label-vector hints.
                    % Without nSubjects this would resolve arbitrary numeric
                    % base-workspace variables, including large matrices.
                    if isempty(nSubjects)
                        catalog{i} = w; continue;
                    end
                    sz = w.size;
                    if ~(numel(sz) >= 2 && ((double(sz(1)) == double(nSubjects) && double(sz(2)) == 1) || ...
                            (double(sz(1)) == 1 && double(sz(2)) == double(nSubjects))))
                        catalog{i} = w; continue;
                    end
                    w.subjectVectorMatch = true;
                    if ~(isfield(w,'isNumeric') && w.isNumeric) && ~(isfield(w,'class') && any(strcmp(w.class,{'categorical','string','cell'})))
                        catalog{i} = w; continue;
                    end
                    val = NMWorkspaceTools.resolve(w.name, workspace);
                    info = NMWorkspaceTools.inferTaskType(val);
                    w.validLabelVector = info.validLabelVector;
                    w.taskHint = info.taskType;
                    w.taskHintReason = info.reason;
                    w.nUniqueNonMissing = info.nUniqueNonMissing;
                    w.isIntegerLike = info.isIntegerLike;
                    catalog{i} = w;
                catch
                    % Keep the catalog usable even if a workspace value cannot be
                    % inspected, e.g. because it is a handle object or otherwise
                    % expensive/problematic to evaluate.
                end
            end
        end

        function candidates = subjectVectorCandidates(catalog)
            % subjectVectorCandidates  Filter catalog entries to plausible subject-level vectors.
            %
            % Returns workspace variables whose shape and metadata match expected subject counts. Callers use these names for labels, covariates, grouping vectors or CV constraints before resolving actual values.
            candidates = {};
            for i = 1:numel(catalog)
                if iscell(catalog)
                    w = catalog{i};
                else
                    w = catalog(i);
                end
                if ~isstruct(w), continue; end
                if ~isfield(w,'name') || isempty(w.name), continue; end
                if ~isfield(w,'subjectVectorMatch') || ~logical(w.subjectVectorMatch), continue; end
                if ~isfield(w,'isNumeric') || ~logical(w.isNumeric)
                    if ~isfield(w,'class') || ~any(strcmp(w.class, {'logical','categorical','string','cell'}))
                        continue;
                    end
                end
                c = struct();
                c.name = w.name;
                c.class = w.class;
                c.size = w.size;
                c.nUniqueNonMissing = [];
                if isfield(w,'nUniqueNonMissing'), c.nUniqueNonMissing = w.nUniqueNonMissing; end
                candidates{end+1} = c; %#ok<AGROW>
            end
        end

        function info = inferTaskType(val)
            % inferTaskType  Infer whether a user-provided ranking target is likely to define.
            %
            % a classification or regression ranking problem. This mirrors the
            % old nk_Rank_config distinction between categorical and continuous
            % custom targets, but keeps the user override explicit.
            info = struct('taskType','ambiguous', ...
                'reason','could not infer target type', ...
                'nUniqueNonMissing',[], ...
                'isIntegerLike',false, ...
                'validLabelVector',false);
            try
                if isempty(val)
                    info.reason = 'empty target'; return;
                end
                if istable(val)
                    info.reason = 'tables are not accepted as direct ranking targets'; return;
                end
                if ~(isvector(val) || (ismatrix(val) && size(val,2) == 1))
                    info.reason = sprintf('target is not a vector (size %s)', mat2str(size(val))); return;
                end
                info.validLabelVector = true;
                y = val(:);
                if islogical(y)
                    info.taskType = 'classification';
                    info.reason = 'logical target';
                    info.nUniqueNonMissing = numel(unique(y));
                    info.isIntegerLike = true;
                    return;
                end
                if iscategorical(y) || isstring(y) || iscellstr(y)
                    if iscategorical(y), yy = y(~isundefined(y)); else, yy = y; yy = yy(~cellfun(@isempty, cellstr(yy))); end
                    info.taskType = 'classification';
                    info.reason = 'categorical/string target';
                    try, info.nUniqueNonMissing = numel(unique(yy)); catch, info.nUniqueNonMissing = []; end
                    info.isIntegerLike = false;
                    return;
                end
                if ~isnumeric(y)
                    info.reason = sprintf('unsupported target class: %s', class(y)); return;
                end
                y = y(isfinite(y));
                if isempty(y)
                    info.reason = 'all target values are missing/non-finite'; return;
                end
                n = numel(y);
                u = unique(y);
                nu = numel(u);
                info.nUniqueNonMissing = nu;
                tol = max(eps(max(abs(y))) * 32, 1e-12);
                info.isIntegerLike = all(abs(y - round(y)) <= tol);
                fewClassLimit = max(20, ceil(0.05 * n));
                if nu <= 2
                    info.taskType = 'classification';
                    info.reason = sprintf('%d unique values', nu);
                elseif info.isIntegerLike && nu <= fewClassLimit
                    info.taskType = 'classification';
                    info.reason = sprintf('integer-like target with %d unique values (limit %d)', nu, fewClassLimit);
                else
                    info.taskType = 'regression';
                    if info.isIntegerLike
                        info.reason = sprintf('integer-like target with many unique values (%d)', nu);
                    else
                        info.reason = 'continuous non-integer numeric target';
                    end
                end
            catch ME
                info.taskType = 'ambiguous';
                info.reason = ME.message;
            end
        end

        function val = resolve(varName, workspace)
            % resolve  Resolve a named variable from a MATLAB workspace after UI selection.
            %
            % Loads the actual value only inside MATLAB when a backend service needs it. This is the controlled counterpart to catalog, which exposes metadata only.
            if nargin < 2 || isempty(workspace), workspace = 'base'; end
            if isempty(varName), val = []; return; end
            if ~ischar(varName) && ~isstring(varName)
                error('NMWorkspaceTools:badVarName','Variable reference must be a name string.');
            end
            varName = char(varName);
            if ~isvarname(varName)
                error('NMWorkspaceTools:badVarName','Invalid MATLAB variable name: %s.', varName);
            end
            switch lower(workspace)
                case 'base'
                    val = evalin('base', varName);
                case 'caller'
                    val = evalin('caller', varName);
                otherwise
                    error('NMWorkspaceTools:badWorkspace','workspace must be base or caller.');
            end
        end

        function assertFeatureCompatible(val, nFeatures, label)
            % assertFeatureCompatible  Validate that a resolved value matches the expected feature dimension.
            %
            % Checks array/table orientation and feature count before using workspace data as imported features or metadata. It raises an explicit error when the shape is incompatible.
            if nargin < 3 || isempty(label), label = 'workspace variable'; end
            if isempty(nFeatures) || ~isfinite(nFeatures), return; end
            if ~isnumeric(val) && ~islogical(val)
                error('NMWorkspaceTools:notNumeric','%s must be numeric/logical.', label);
            end
            sz = size(val);
            isVec = isvector(val) && numel(val) == nFeatures;
            isMat = numel(sz) >= 2 && sz(2) == nFeatures;
            if ~(isVec || isMat)
                error('NMWorkspaceTools:featureDimMismatch', ...
                    '%s must be a vector with %d elements or a matrix with size(...,2) = %d. Current size: %s.', ...
                    label, nFeatures, nFeatures, mat2str(sz));
            end
        end
    end
end
