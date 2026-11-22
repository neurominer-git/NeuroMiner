classdef NMDataIOMaterializationCache
% NMDataIOMaterializationCache
% Purpose / authority:
%   Ephemeral MATLAB-side cache for canonical DataIO materializations shared by Preview, QC and
%   Commit. It prevents unchanged sources from being read/materialized repeatedly.
%
% Persistence contract:
%   The cache is execution state only: it is never projected into NM, browser recovery STATE,
%   input_settings, recipes or generated API code. Matrix Inspector case/feature selection is a
%   late commit mask and is deliberately excluded from retained-materialization identity.

    methods (Static)
        function [hit, entry, key] = get(family, state, requestedKey, varargin)
            family = lower(char(string(family)));
            owner = '';
            if ~isempty(varargin), owner = varargin{1}; end
            if nargin >= 3 && ~isempty(requestedKey) && (~isstruct(state) || isempty(fieldnames(state)))
                requestedKey = char(string(requestedKey));
                prefix = [family ':'];
                if ~strncmp(requestedKey,prefix,numel(prefix))
                    hit = false; entry = []; key = requestedKey; return;
                end
                [hit,entry] = NMDataIOMaterializationCache.store('get', NMDataIOMaterializationCache.address(requestedKey, owner), []);
                key = requestedKey;
                return;
            end
            key = NMDataIOMaterializationCache.keyForState(family, state);
            [hit,entry] = NMDataIOMaterializationCache.store('get', NMDataIOMaterializationCache.address(key, owner), []);
        end

        function key = put(family, state, entry, varargin)
            owner = '';
            if ~isempty(varargin), owner = varargin{1}; end
            key = NMDataIOMaterializationCache.keyForState(family, state);
            NMDataIOMaterializationCache.store('put', NMDataIOMaterializationCache.address(key, owner), entry);
        end

        function clearFamily(family)
            NMDataIOMaterializationCache.store('clearFamily', lower(char(string(family))), []);
        end

        function clearFamilyForOwner(family, owner)
            NMDataIOMaterializationCache.store('clearFamily', family, struct('owner',owner));
        end

        function retireOwner(owner)
            NMDataIOMaterializationCache.store('clearOwner', '', struct('owner',owner));
        end

        function clearAll()
            NMDataIOMaterializationCache.store('clearAll', '', []);
        end

        function state2 = withoutMatrixItemSelection(state)
            % WITHOUTMATRIXITEMSELECTION  Remove late transfer masks and selector metadata before materialization.
            state2 = NMDataIOMaterializationCache.stripMatrixItemSelection(state);
        end

        function mask = caseSelection(state, nRows)
            % CASESELECTION  Resolve the late case mask from inline state or the selector package file.
            mask = NMDataIOMaterializationCache.selectionMask(state, nRows, 'cases');
            mask = mask(:);
        end

        function mask = featureSelection(state, nFeatures)
            % FEATURESELECTION  Resolve the late feature mask from inline state or the selector package file.
            mask = NMDataIOMaterializationCache.selectionMask(state, nFeatures, 'features');
            mask = mask(:)';
        end

        function key = keyForState(family, state)
            projection = NMDataIOMaterializationCache.identityProjection(state);
            payload = jsonencode(projection);
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(uint8(unicode2native(payload, 'UTF-8')));
            digest = typecast(md.digest(), 'uint8');
            hex = lower(reshape(dec2hex(digest,2).',1,[]));
            key = [lower(char(string(family))) ':' hex];
        end
    end

    methods (Static, Access=private)
        function value = address(key, owner)
            value = [key '#' num2str(numel(owner)) ':' owner];
        end

        function projection = identityProjection(state)
            projection = NMDataIOMaterializationCache.stripMatrixItemSelection(state);
            projection = NMDataIOMaterializationCache.stripTransient(projection);
        end

        function x = stripMatrixItemSelection(x)
            if ~isstruct(x) || isempty(x), return; end
            if numel(x) > 1
                for k = 1:numel(x), x(k) = NMDataIOMaterializationCache.stripMatrixItemSelection(x(k)); end
                return;
            end
            if isfield(x,'selection'), x = rmfield(x,'selection'); end
            for f = {'selCases','selFeats','selectedCases','selectedFeatures'}
                if isfield(x,f{1}), x = rmfield(x,f{1}); end
            end
            fn = fieldnames(x);
            for k = 1:numel(fn)
                v = x.(fn{k});
                if isstruct(v), x.(fn{k}) = NMDataIOMaterializationCache.stripMatrixItemSelection(v); end
            end
        end

        function mask = selectionMask(state, nItems, kind)
            nItems = max(0,double(nItems));
            mask = true(nItems,1);
            if nItems < 1 || ~isstruct(state), return; end
            selection = struct();
            if isfield(state,'selection') && isstruct(state.selection), selection = state.selection; end
            switch lower(char(string(kind)))
                case 'cases'
                    directNames = {'selCases','selectedCases'}; fileName = 'selCasesFile'; lengthId = 'caseSelectionLength'; label = 'case';
                case 'features'
                    directNames = {'selFeats','selectedFeatures'}; fileName = 'selFeatsFile'; lengthId = 'featureSelectionLength'; label = 'feature';
                otherwise
                    error('NMDataIOMaterializationCache:selectionKind','Unsupported late-selection kind: %s.',char(string(kind)));
            end
            candidate = [];
            for i = 1:numel(directNames)
                f = directNames{i};
                if isfield(selection,f) && ~isempty(selection.(f)), candidate = selection.(f); break; end
            end
            if isempty(candidate) && isfield(selection,fileName) && ~isempty(selection.(fileName))
                candidate = NMDataIOItemSelectorPackageTools.readMaskFile(char(string(selection.(fileName))),nItems);
            end
            if isempty(candidate) && isfield(state,'matrix') && isstruct(state.matrix)
                for i = 1:numel(directNames)
                    f = directNames{i};
                    if isfield(state.matrix,f) && ~isempty(state.matrix.(f)), candidate = state.matrix.(f); break; end
                end
            end
            if isempty(candidate)
                for i = 1:numel(directNames)
                    f = directNames{i};
                    if isfield(state,f) && ~isempty(state.(f)), candidate = state.(f); break; end
                end
            end
            if isempty(candidate), return; end
            candidate = logical(candidate(:));
            if numel(candidate) ~= nItems
                error(['NMDataIOMaterializationCache:' lengthId], ...
                    'The saved %s selection contains %g entries, but the current Preview contains %g %ss. Run Preview again.', ...
                    label,numel(candidate),nItems,label);
            end
            mask = candidate;
        end

        function x = stripTransient(x)
            if ~isstruct(x) || isempty(x), return; end
            if numel(x) > 1
                for k = 1:numel(x), x(k) = NMDataIOMaterializationCache.stripTransient(x(k)); end
                return;
            end
            drop = {'databasePassword','password','passwd','preview','probe','qc','qcReport', ...
                'messages','summary','strip','statePatch','previewPersisted','qcPersisted','draftDirty', ...
                'persistedInspection','persistedQC','lastProbe','lastPreview','materializationRevision', ...
                'materializationCacheKey','dataioPreparedCacheKey','dataioPreparedCacheHit','desc_data', ...
                'oocvScientificPolicy','existingCovariateNames','existingLabelAvailable','existingLabelColumns','oocvLabelsPresent'};
            for k = 1:numel(drop)
                if isfield(x,drop{k}), x = rmfield(x,drop{k}); end
            end
            % Browser UI mirrors are not independent scientific authorities. When the
            % canonical effective field is present, exclude the corresponding UI-only
            % selection from retained-materialization identity. activeClassIndex only
            % selects the visible class tab; classFileLists carries the scientific files.
            if isfield(x,'activeClassIndex'), x = rmfield(x,'activeClassIndex'); end
            mirrorPairs = {'uiLabelModeSelection','labelMode'; 'uiCaseIDModeSelection','caseIDMode'; ...
                'uiSpatialKindSelection','spatialKind'; 'uiGlobalModeSelection','globalMode'};
            for k = 1:size(mirrorPairs,1)
                if isfield(x,mirrorPairs{k,1}) && isfield(x,mirrorPairs{k,2}), x = rmfield(x,mirrorPairs{k,1}); end
            end
            fn = sort(fieldnames(x));
            y = struct();
            for k = 1:numel(fn)
                v = x.(fn{k});
                if isstruct(v), v = NMDataIOMaterializationCache.stripTransient(v); end
                y.(fn{k}) = v;
            end
            x = y;
        end

        function [hit, value] = store(action, key, value)
            persistent cache order
            if isempty(cache)
                cache = containers.Map('KeyType','char','ValueType','any');
                order = {};
            end
            hit = false;
            switch action
                case 'get'
                    hit = isKey(cache,key);
                    if hit
                        value = cache(key);
                        order(strcmp(order,key)) = [];
                        order{end+1} = key;
                    else
                        value = [];
                    end
                case 'put'
                    cache(key) = value;
                    order(strcmp(order,key)) = [];
                    order{end+1} = key;
                    maxEntries = 2;
                    while numel(order) > maxEntries
                        old = order{1}; order(1) = [];
                        if isKey(cache,old), remove(cache,old); end
                    end
                case {'clearFamily','clearOwner'}
                    keys = cache.keys;
                    suffix = '';
                    if ~isempty(value), suffix = NMDataIOMaterializationCache.address('',value.owner); end
                    for k = 1:numel(keys)
                        familyMatch = strcmp(action,'clearOwner') || startsWith(keys{k},[key ':']);
                        if familyMatch && (isempty(value) || endsWith(keys{k},suffix)), remove(cache,keys{k}); end
                    end
                    order = order(cellfun(@(s)isKey(cache,s),order));
                case 'clearAll'
                    cache = containers.Map('KeyType','char','ValueType','any');
                    order = {};
                otherwise
                    error('NMDataIOMaterializationCache:action','Unsupported prepared-data operation: %s. Close and reopen DataIO; if the problem persists, report this error.',action);
            end
        end
    end
end
