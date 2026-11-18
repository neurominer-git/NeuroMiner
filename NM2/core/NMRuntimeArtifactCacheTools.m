classdef NMRuntimeArtifactCacheTools
% Retain independent bounded artifact caches for MLI, VIS, and runtime actions.
    methods (Static)
        function info = info(enabled, hit, key)
            info = struct('enabled',logical(enabled),'hit',logical(hit),'keyLength',numel(key));
        end

        function txt = hitMissText(hit)
            if hit, txt = 'hit'; else, txt = 'miss'; end
        end

        function [hit, value] = cache(scope, action, key, input)
            persistent groups
            if isempty(groups)
                groups = containers.Map('KeyType','char','ValueType','any');
            end
            hit = false;
            value = struct();
            if isempty(key), return; end
            if ~isKey(groups,scope)
                groups(scope) = struct('entries',containers.Map('KeyType','char','ValueType','any'), 'order',{{}});
            end
            group = groups(scope);
            entries = group.entries;
            switch action
                case 'get'
                    if isKey(entries,key)
                        hit = true;
                        value = entries(key);
                    end
                case 'put'
                    if ~isKey(entries,key)
                        group.order{end+1} = key;
                    end
                    entries(key) = input;
                    while numel(group.order) > 96
                        remove(entries,group.order{1});
                        group.order(1) = [];
                    end
            end
            groups(scope) = group;
        end
    end
end
