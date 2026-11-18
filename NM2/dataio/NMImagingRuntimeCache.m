classdef NMImagingRuntimeCache
% NMImagingRuntimeCache
% -------------------------------------------------------------------------
% Bounded process-local LRU cache for renderer-independent imaging
% objects. The cache stores only objects that have already been resolved by
% an authoritative scientific service; it never discovers modalities,
% changes values, resamples implicitly, or mutates NM.
%
% The deliberately small namespace-specific entry and byte bounds prevent a
% 160-300 modality analysis from retaining every modality or an excessive
% number of high-resolution display volumes in memory. A modality is
% loaded only after selection and remains cached only while it is among the
% most recently used entries.
%
% Documentation: docs/NMResultsViewerLazyPayloadContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function [value, hit] = get(namespace, key)
            % get  Return one cached value and update its LRU position.
            [value,hit] = NMImagingRuntimeCache.store('get',namespace,key,[]);
        end

        function put(namespace, key, value)
            % put  Insert or replace one authoritative value.
            NMImagingRuntimeCache.store('put',namespace,key,value);
        end

        function clear()
            % clear  Drop all process-local imaging cache entries.
            NMImagingRuntimeCache.store('clear','','',[]);
        end

        function stats = statistics()
            % statistics  Return entry counts without exposing cached values.
            [stats,~] = NMImagingRuntimeCache.store('statistics','','',[]);
        end
    end

    methods (Static, Access = private)
        function [out, hit] = store(action, namespace, key, value)
            persistent cache logicalClock
            if isempty(cache)
                cache = NMImagingRuntimeCache.emptyCache();
                logicalClock = uint64(0);
            end
            out = [];
            hit = false;
            action = lower(strtrim(char(string(action))));
            if strcmp(action,'clear')
                cache = NMImagingRuntimeCache.emptyCache();
                logicalClock = uint64(0);
                return;
            end
            if strcmp(action,'statistics')
                names = fieldnames(cache);
                stats = struct();
                for ii = 1:numel(names)
                    entries = cache.(names{ii});
                    stats.(names{ii}) = numel(entries);
                    byteField = [names{ii} '_bytes'];
                    stats.(byteField) = NMImagingRuntimeCache.totalBytes(entries);
                end
                out = stats;
                return;
            end
            namespace = NMImagingRuntimeCache.normalizeNamespace(namespace);
            key = char(string(key));
            if isempty(key)
                error('NMImagingRuntimeCache:EmptyKey','The prepared imaging-data reference is missing. Run Preview again.');
            end
            entries = cache.(namespace);
            index = 0;
            for ii = 1:numel(entries)
                if strcmp(entries{ii}.key,key)
                    index = ii;
                    break;
                end
            end
            switch action
                case 'get'
                    if index < 1, return; end
                    logicalClock = logicalClock + 1;
                    entry = entries{index};
                    entry.lastUsed = logicalClock;
                    entries{index} = entry;
                    cache.(namespace) = entries;
                    out = entry.value;
                    hit = true;
                case 'put'
                    logicalClock = logicalClock + 1;
                    entry = struct('key',key,'value',value,'lastUsed',logicalClock, ...
                        'bytes',NMImagingRuntimeCache.estimateBytes(value));
                    if index > 0
                        entries{index} = entry;
                    else
                        entries{end+1} = entry; %#ok<AGROW>
                    end
                    entryBound = NMImagingRuntimeCache.namespaceBound(namespace);
                    byteBound = NMImagingRuntimeCache.namespaceByteBound(namespace);
                    while numel(entries) > 1 && ...
                            (numel(entries) > entryBound || NMImagingRuntimeCache.totalBytes(entries) > byteBound)
                        stamps = zeros(1,numel(entries));
                        for ii = 1:numel(entries), stamps(ii) = double(entries{ii}.lastUsed); end
                        [~,evict] = min(stamps);
                        entries(evict) = [];
                    end
                    cache.(namespace) = entries;
                otherwise
                    error('NMImagingRuntimeCache:UnsupportedAction', ...
                        'Unsupported prepared-imaging-data operation "%s". Close and reopen DataIO; if the problem persists, report this error.',action);
            end
        end

        function cache = emptyCache()
            cache = struct( ...
                'structural',{{}}, ...
                'feature_space',{{}}, ...
                'display_scaffold',{{}}, ...
                'atlas',{{}}, ...
                'mask3d',{{}}, ...
                'mesh3d',{{}});
        end

        function namespace = normalizeNamespace(namespace)
            namespace = lower(strtrim(char(string(namespace))));
            allowed = {'structural','feature_space','display_scaffold','atlas','mask3d','mesh3d'};
            if ~any(strcmp(namespace,allowed))
                error('NMImagingRuntimeCache:UnsupportedNamespace', ...
                    'Unsupported prepared-imaging-data category "%s". Close and reopen DataIO; if the problem persists, report this error.',namespace);
            end
        end

        function bytes = estimateBytes(value)
            info = whos('value');
            bytes = double(info.bytes);
        end

        function bytes = totalBytes(entries)
            bytes = 0;
            for ii = 1:numel(entries)
                if isfield(entries{ii},'bytes') && isfinite(double(entries{ii}.bytes))
                    bytes = bytes + double(entries{ii}.bytes);
                end
            end
        end

        function bound = namespaceByteBound(namespace)
            mib = 1024 * 1024;
            switch namespace
                case 'structural', bound = 80 * mib;
                case 'feature_space', bound = 64 * mib;
                case 'display_scaffold', bound = 128 * mib;
                case 'atlas', bound = 64 * mib;
                case 'mask3d', bound = 32 * mib;
                case 'mesh3d', bound = 128 * mib;
                otherwise, bound = 32 * mib;
            end
        end

        function bound = namespaceBound(namespace)
            switch namespace
                case 'structural', bound = 3;
                case 'feature_space', bound = 6;
                case 'display_scaffold', bound = 6;
                case 'atlas', bound = 3;
                case 'mask3d', bound = 4;
                case 'mesh3d', bound = 4;
                otherwise, bound = 1;
            end
        end
    end
end
