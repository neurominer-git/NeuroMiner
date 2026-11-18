classdef NMRuntimeGridTools
% NMRuntimeGridTools
% -------------------------------------------------------------------------
% Shared noninteractive CV2 GridAct selector logic for browser/runtime pages.
%
% This class mirrors the action semantics of legacy nk_CVGridSelector without
% opening nk_input menus.  It is intentionally generic and should be reused by
% preprocessing, ML training, visualization, MLI, OOCV and export pages where
% a perm x fold CV2 GridAct matrix must be edited or validated.
% -------------------------------------------------------------------------

    methods (Static)
        function state = state(ix, jx, GridAct, spec)
            % state  Build a fixed-schema GridAct picker state.
            %
            % state = NMRuntimeGridTools.state(ix,jx,GridAct,spec) returns a
            % normalized read/write state for a CV2 perm x fold grid.  Empty
            % GridAct defaults to false(ix,jx), matching nk_CVGridSelector.
            %
            % spec.proceedAllowed: supplies the proceed allowed value in the public API/import specification.
            % spec.requireAny: supplies the require any value in the public API/import specification.

            if nargin < 3, GridAct = []; end
            if nargin < 4 || isempty(spec), spec = struct(); end
            [ix, jx] = NMRuntimeGridTools.normalizeDims(ix, jx);
            G = NMRuntimeGridTools.normalize(ix, jx, GridAct);
            requireAny = NMRuntimeGridTools.fieldOr(spec, 'requireAny', true);
            proceedAllowed = NMRuntimeGridTools.fieldOr(spec, 'proceedAllowed', true);
            [ok, msg] = NMRuntimeGridTools.validate(G, logical(requireAny));

            state = NMRuntimeGridTools.template();
            state.ok = ok;
            state.message = msg;
            state.ix = ix;
            state.jx = jx;
            state.GridAct = G;
            state.selectedCount = double(sum(G(:)));
            state.totalCount = double(numel(G));
            state.requireAny = logical(requireAny);
            state.proceedAllowed = logical(proceedAllowed) && state.selectedCount > 0;
            state.rowLabels = NMRuntimeGridTools.labels('perm', ix);
            state.columnLabels = NMRuntimeGridTools.labels('fold', jx);
            state.symbolMatrix = NMRuntimeGridTools.symbolMatrix(G);
            state.actions = NMRuntimeGridTools.actionKeys();
        end

        function [state, out] = applyAction(stateIn, actionSpec)
            % applyAction  Apply a noninteractive nk_CVGridSelector-style action.
            %
            %   actionSpec.action supports:
            %       selectAll, selectPosition, selectRange,
            %       deselectAll, deselectPosition, deselectRange,
            %       toggleAll, togglePosition, toggleRange, setMatrix

            if nargin < 2 || isempty(actionSpec), actionSpec = struct(); end
            if ~isstruct(stateIn) || ~isfield(stateIn,'ix') || ~isfield(stateIn,'jx') || ~isfield(stateIn,'GridAct')
                error('NMRuntimeGridTools:badState', 'stateIn must be a state struct returned by NMRuntimeGridTools.state.');
            end
            action = NMRuntimeGridTools.actionFromSpec(actionSpec);
            ix = double(stateIn.ix);
            jx = double(stateIn.jx);
            G = NMRuntimeGridTools.normalize(ix, jx, stateIn.GridAct);

            switch lower(action)
                case 'selectall'
                    G(:) = true;
                case 'selectposition'
                    [p, f] = NMRuntimeGridTools.positionFromSpec(actionSpec, ix, jx);
                    G(p,f) = true;
                case 'selectrange'
                    [p1, p2, f1, f2] = NMRuntimeGridTools.rangeFromSpec(actionSpec, ix, jx);
                    G(p1:p2, f1:f2) = true;
                case 'deselectall'
                    G(:) = false;
                case 'deselectposition'
                    [p, f] = NMRuntimeGridTools.positionFromSpec(actionSpec, ix, jx);
                    G(p,f) = false;
                case 'deselectrange'
                    [p1, p2, f1, f2] = NMRuntimeGridTools.rangeFromSpec(actionSpec, ix, jx);
                    G(p1:p2, f1:f2) = false;
                case 'toggleall'
                    G = ~G;
                case 'toggleposition'
                    [p, f] = NMRuntimeGridTools.positionFromSpec(actionSpec, ix, jx);
                    G(p,f) = ~G(p,f);
                case 'togglerange'
                    [p1, p2, f1, f2] = NMRuntimeGridTools.rangeFromSpec(actionSpec, ix, jx);
                    G(p1:p2, f1:f2) = ~G(p1:p2, f1:f2);
                case 'setmatrix'
                    G = NMRuntimeGridTools.matrixFromSpec(actionSpec, ix, jx);
                otherwise
                    error('NMRuntimeGridTools:unsupportedAction', 'Unsupported GridAct action: %s', action);
            end

            spec = struct('requireAny',logical(stateIn.requireAny), 'proceedAllowed',true);
            state = NMRuntimeGridTools.state(ix, jx, G, spec);
            out = struct('ok',state.ok, 'message',state.message, 'action',action, ...
                'selectedCount',state.selectedCount, 'totalCount',state.totalCount, 'GridAct',state.GridAct);
        end

        function GridAct = normalize(ix, jx, GridAct)
            % normalize  Return a logical GridAct matrix of exact size ix x jx.

            [ix, jx] = NMRuntimeGridTools.normalizeDims(ix, jx);
            if nargin < 3 || isempty(GridAct)
                GridAct = false(ix,jx);
                return;
            end
            if islogical(GridAct) || isnumeric(GridAct)
                GridAct = logical(GridAct);
            else
                error('NMRuntimeGridTools:badGridActType', 'GridAct must be logical or numeric.');
            end
            if ~isequal(size(GridAct), [ix jx])
                error('NMRuntimeGridTools:badGridActSize', ...
                    'GridAct size is %s, expected [%d %d].', mat2str(size(GridAct)), ix, jx);
            end
        end

        function [ok, msg] = validate(GridAct, requireAny)
            % validate  Validate GridAct noninteractively.

            if nargin < 2 || isempty(requireAny), requireAny = true; end
            ok = true;
            msg = 'GridAct is valid.';
            if isempty(GridAct) || ~(islogical(GridAct) || isnumeric(GridAct)) || ~ismatrix(GridAct)
                ok = false;
                msg = 'GridAct must be a nonempty logical or numeric matrix.';
                return;
            end
            if logical(requireAny) && ~any(logical(GridAct(:)))
                ok = false;
                msg = 'At least one CV2 partition must be selected.';
                return;
            end
        end

        function gridFiles = fileGrid(files, G, dataId, root, kind)
            % Canonical CV2 file mapping; caller owns artifact discovery.
            gridFiles = cell(size(G));
            for i = 1:numel(files)
                file = char(files{i});
                [parent,name,ext] = fileparts(file);
                if ~contains(name,kind) || ~endsWith([name ext],sprintf('_ID%s.mat',dataId))
                    error('NMRuntimeGridTools:artifactIdentity','%s does not match data ID %s: %s',kind,dataId,file);
                end
                if ~isempty(root) && ~strcmpi(strrep(parent,'\','/'),strrep(root,'\','/'))
                    error('NMRuntimeGridTools:artifactDirectory','%s is outside the required directory: %s',kind,file);
                end
                [row,col] = NMRuntimeGridTools.fileCoordinates(file,kind);
                validateattributes(row,{'numeric'},{'scalar','integer','>=',1,'<=',size(G,1)});
                validateattributes(col,{'numeric'},{'scalar','integer','>=',1,'<=',size(G,2)});
                if ~G(row,col), continue; end
                if ~isempty(gridFiles{row,col})
                    error('NMRuntimeGridTools:duplicateArtifact','Duplicate %s CV2 [%d,%d].',kind,row,col);
                end
                gridFiles{row,col} = file;
            end
        end

        function [row,col] = fileCoordinates(file,kind)
            % Artifact writers own the coordinate convention selected by kind.
            switch kind
                case 'CVdatamat'
                    S = load(file,'ofold','operm'); row = S.ofold; col = S.operm;
                case 'PreprocData'
                    S = load(file,'outperm','outfold'); row = S.outperm; col = S.outfold;
                otherwise
                    S = load(file,'operm','ofold'); row = S.operm; col = S.ofold;
            end
        end

        function keys = actionKeys()
            % actionKeys  Return the noninteractive action vocabulary.

            keys = {'selectAll','selectPosition','selectRange', ...
                'deselectAll','deselectPosition','deselectRange', ...
                'toggleAll','togglePosition','toggleRange','setMatrix'};
        end
    end

    methods (Static, Access = private)
        function s = template()
            s = struct('ok',false, 'message','', 'ix',0, 'jx',0, 'GridAct',false(0,0), ...
                'selectedCount',0, 'totalCount',0, 'requireAny',true, 'proceedAllowed',false, ...
                'rowLabels',{{}}, 'columnLabels',{{}}, 'symbolMatrix',{{}}, 'actions',{{}});
        end

        function [ix, jx] = normalizeDims(ix, jx)
            if nargin < 1 || isempty(ix) || nargin < 2 || isempty(jx)
                error('NMRuntimeGridTools:missingDims', 'Grid dimensions ix and jx are required.');
            end
            ix = double(ix);
            jx = double(jx);
            if ~isscalar(ix) || ~isscalar(jx) || ~isfinite(ix) || ~isfinite(jx) || ix < 1 || jx < 1 || ix ~= round(ix) || jx ~= round(jx)
                error('NMRuntimeGridTools:badDims', 'Grid dimensions must be positive integer scalars.');
            end
        end

        function val = fieldOr(s, field, defaultValue)
            val = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
                val = s.(field);
            end
        end

        function labels = labels(prefix, n)
            labels = cell(1,n);
            for i = 1:n
                labels{i} = sprintf('%s %d', prefix, i);
            end
        end

        function C = symbolMatrix(G)
            C = cell(size(G));
            for i = 1:size(G,1)
                for j = 1:size(G,2)
                    if G(i,j)
                        C{i,j} = '*';
                    else
                        C{i,j} = 'o';
                    end
                end
            end
        end

        function action = actionFromSpec(actionSpec)
            if ~isstruct(actionSpec)
                error('NMRuntimeGridTools:badActionSpec', 'actionSpec must be a scalar struct.');
            end
            if isfield(actionSpec,'action') && ~isempty(actionSpec.action)
                action = char(string(actionSpec.action));
            elseif isfield(actionSpec,'operation') && ~isempty(actionSpec.operation)
                action = char(string(actionSpec.operation));
            else
                error('NMRuntimeGridTools:missingAction', 'actionSpec.action is required.');
            end
            action = strtrim(action);
        end

        function [p, f] = positionFromSpec(actionSpec, ix, jx)
            if isfield(actionSpec,'position') && ~isempty(actionSpec.position)
                pos = double(actionSpec.position);
                if numel(pos) ~= 2
                    error('NMRuntimeGridTools:badPosition', 'position must contain [perm fold].');
                end
                p = pos(1);
                f = pos(2);
            else
                p = NMRuntimeGridTools.requiredScalar(actionSpec, {'perm','permutation','p'}, 'perm');
                f = NMRuntimeGridTools.requiredScalar(actionSpec, {'fold','f'}, 'fold');
            end
            p = NMRuntimeGridTools.boundIndex(p, ix, 'perm');
            f = NMRuntimeGridTools.boundIndex(f, jx, 'fold');
        end

        function [p1, p2, f1, f2] = rangeFromSpec(actionSpec, ix, jx)
            if isfield(actionSpec,'range') && ~isempty(actionSpec.range)
                r = double(actionSpec.range);
                if numel(r) ~= 4
                    error('NMRuntimeGridTools:badRange', 'range must contain [permStart permEnd foldStart foldEnd].');
                end
                p1 = r(1); p2 = r(2); f1 = r(3); f2 = r(4);
            else
                p1 = NMRuntimeGridTools.requiredScalar(actionSpec, {'permStart','pStart','p1'}, 'permStart');
                p2 = NMRuntimeGridTools.requiredScalar(actionSpec, {'permEnd','pEnd','p2'}, 'permEnd');
                f1 = NMRuntimeGridTools.requiredScalar(actionSpec, {'foldStart','fStart','f1'}, 'foldStart');
                f2 = NMRuntimeGridTools.requiredScalar(actionSpec, {'foldEnd','fEnd','f2'}, 'foldEnd');
            end
            p1 = NMRuntimeGridTools.boundIndex(p1, ix, 'permStart');
            p2 = NMRuntimeGridTools.boundIndex(p2, ix, 'permEnd');
            f1 = NMRuntimeGridTools.boundIndex(f1, jx, 'foldStart');
            f2 = NMRuntimeGridTools.boundIndex(f2, jx, 'foldEnd');
            if p2 < p1 || f2 < f1
                error('NMRuntimeGridTools:badRangeOrder', 'Range end indices must be greater than or equal to start indices.');
            end
        end

        function G = matrixFromSpec(actionSpec, ix, jx)
            if isfield(actionSpec,'GridAct') && ~isempty(actionSpec.GridAct)
                G = actionSpec.GridAct;
            elseif isfield(actionSpec,'matrix') && ~isempty(actionSpec.matrix)
                G = actionSpec.matrix;
            else
                error('NMRuntimeGridTools:missingMatrix', 'setMatrix requires actionSpec.GridAct or actionSpec.matrix.');
            end
            G = NMRuntimeGridTools.normalize(ix, jx, G);
        end

        function v = requiredScalar(s, names, label)
            v = [];
            for i = 1:numel(names)
                if isfield(s,names{i}) && ~isempty(s.(names{i}))
                    v = double(s.(names{i}));
                    break;
                end
            end
            if isempty(v)
                error('NMRuntimeGridTools:missingIndex', 'Missing %s index.', label);
            end
            if ~isscalar(v) || ~isfinite(v)
                error('NMRuntimeGridTools:badIndex', '%s must be a finite scalar.', label);
            end
        end

        function idx = boundIndex(idx, upper, label)
            idx = double(idx);
            if ~isscalar(idx) || ~isfinite(idx) || idx ~= round(idx) || idx < 1 || idx > upper
                error('NMRuntimeGridTools:indexOutOfRange', '%s index %g is outside the valid range 1..%d.', label, idx, upper);
            end
        end
    end
end
