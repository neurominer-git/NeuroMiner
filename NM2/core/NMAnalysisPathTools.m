classdef NMAnalysisPathTools
% NMAnalysisPathTools
% -------------------------------------------------------------------------
% Focused portability adapter for NM.analysis filesystem paths. The class
% resolves either an exact relocated analysis root or its immediate parent,
% delegates standard path rewriting to nk_UpdateRootPaths, and rebases any
% remaining selected-analysis paths that still carry the stale root prefix.
%
% It does not create, delete, or mutate analysis result files on disk.
% -------------------------------------------------------------------------

    methods (Static)
        function [NM, out] = relinkAnalysisRoot(NM, analind, selectedDir, selectionKind)
            % relinkAnalysisRoot  Relink one analysis across directories or operating systems.
            %
            % [NM,out] = NMAnalysisPathTools.relinkAnalysisRoot(NM, analind,
            % selectedDir, selectionKind) accepts an exact analysis root or its
            % immediate parent. selectionKind may be 'auto', 'root', or 'parent'.
            % Auto mode validates directory contents and rejects ambiguous parents.
            % Stored path basenames are parsed using both slash conventions so a
            % Windows-created NM structure can be relinked on Linux/macOS and vice
            % versa.

            if nargin < 4 || isempty(selectionKind), selectionKind = 'auto'; end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || ...
                    isempty(analind) || analind < 1 || analind > numel(NM.analysis) || ...
                    isempty(NM.analysis{analind})
                error('NMAnalysisPathTools:badAnalysisIndex', 'Analysis %d does not exist.', analind);
            end
            selectedDir = NMAnalysisPathTools.validateRelinkDirectory(selectedDir);
            [NM, out] = NMAnalysisPathTools.relinkOne(NM,analind,selectedDir,selectionKind,false);
        end

        function [NM, out] = relinkAnalysisRoots(NM, indices, selectedDir)
            % Strict common-parent relinking; only recorded basenames may match.
            list = NMAnalysisManagerTools.listAnalyses(NM);
            validateattributes(indices, {'numeric'}, {'vector','nonempty','real','finite','integer','positive','<=',list.count});
            indices = unique(indices(:)','stable');
            selectedDir = NMAnalysisPathTools.validateRelinkDirectory(selectedDir);
            listing = dir(selectedDir);
            names = {listing([listing.isdir] & ~ismember({listing.name},{'.','..'})).name};
            [found, pos] = ismember(cellfun(@NMAnalysisPathTools.pathBasename,list.rootdirs(indices),'UniformOutput',false), names);
            targets = repmat({''},size(indices));
            targets(found) = cellfun(@(name) fullfile(selectedDir,name),names(pos(found)),'UniformOutput',false);
            canonical = @(path) char(java.io.File(path).getCanonicalPath());
            keys = targets;
            keys(found) = cellfun(canonical,targets(found),'UniformOutput',false);
            owners = cellfun(canonical,list.rootdirs(list.rootExists),'UniformOutput',false);
            if ispc
                keys = cellfun(@lower,keys,'UniformOutput',false);
                owners = cellfun(@lower,owners,'UniformOutput',false);
            end
            reasons = repmat({'No child directory matches the stored analysis name.'},size(indices));
            reasons(found) = {''};
            for k = find(found)
                if nnz(strcmp(keys,keys{k})) > 1 || any(strcmp(owners,keys{k}) & (list.indices(list.rootExists) ~= indices(k)))
                    reasons{k} = 'Destination is shared with another retained analysis.';
                end
            end
            for k = find(cellfun(@isempty,reasons))
                i = indices(k);
                [NM, result] = NMAnalysisPathTools.relinkOne(NM,i,targets{k},'root',true);
                if ~result.ok
                    reasons{k} = result.message;
                end
            end
            success = cellfun(@isempty,reasons);
            out = struct('ok',true,'succeededIndices',indices(success),'failedIndices',indices(~success), ...
                'failedMessages',{reasons(~success)},'newRootDirs',{targets(success)}, ...
                'message',sprintf('Relinked %d of %d selected analyses.',nnz(success),numel(indices)));
        end
    end

    methods (Static, Access=private)
        function selectedDir = validateRelinkDirectory(selectedDir)
            selectedDir = NMAnalysisPathTools.trimTrailingSeparators(char(string(selectedDir)));
            if isempty(selectedDir) || exist(selectedDir,'dir') ~= 7
                error('NMAnalysisManagerTools:badRelinkDirectory', ...
                    'Selected relink directory does not exist: %s', selectedDir);
            end
        end

        function [NM, out] = relinkOne(NM, analind, selectedDir, selectionKind, bulk)
            selectionKind = lower(strtrim(char(string(selectionKind))));
            if isempty(selectionKind), selectionKind = 'auto'; end
            if ~any(strcmp(selectionKind, {'auto','root','parent'}))
                error('NMAnalysisManagerTools:badRelinkSelectionKind', ...
                    'Unsupported relink selectionKind ''%s''. Use auto, root, or parent.', selectionKind);
            end
            if exist('nk_UpdateRootPaths','file') ~= 2
                error('NMAnalysisManagerTools:missingRootPathUpdater', ...
                    'Legacy nk_UpdateRootPaths.m is required for analysis root relinking.');
            end

            A = NM.analysis{analind};
            oldRoot = NMAnalysisPathTools.trimTrailingSeparators(char(string(NMAnalysisPathTools.fieldOr(A,'rootdir',''))));
            oldAnalysisDir = NMAnalysisPathTools.pathBasename(oldRoot);
            if isempty(oldAnalysisDir)
                oldAnalysisDir = sprintf('NM_ID%s_A%d_%s', ...
                    NMAnalysisPathTools.fieldOr(NM,'id',''), analind, ...
                    NMAnalysisPathTools.fieldOr(A,'id',sprintf('Analysis_%d',analind)));
            end
            if bulk
                resolution = NMAnalysisPathTools.makeRelinkResolution(selectedDir,'exact_root','matched stored directory name');
            else
                resolution = NMAnalysisPathTools.resolveRelinkTarget(A, analind, selectedDir, oldAnalysisDir, selectionKind);
            end
            resolvedRootDir = resolution.rootdir;
            resolvedParentDir = resolution.parentdir;

            NM.analysis{analind}.rootdir = resolvedRootDir;
            oldParamFile = char(string(NMAnalysisPathTools.fieldOr(A,'paramfile','')));
            if ~isempty(oldParamFile)
                [paramBase, paramExt] = NMAnalysisPathTools.portableFileNameParts(oldParamFile);
                NM.analysis{analind}.paramfile = fullfile(resolvedRootDir,'params',[paramBase paramExt]);
            end
            [NM, pathReport] = nk_UpdateRootPaths(NM, analind, resolvedParentDir, struct('showDialog',false));
            if bulk && pathReport.ok && ~strcmp(NM.analysis{analind}.rootdir,resolvedRootDir)
                pathReport.ok = false;
                pathReport.message = 'Backend resolved a different analysis directory.';
            end
            if ~pathReport.ok
                if bulk
                    NM.analysis{analind} = A;
                    out = pathReport;
                    return;
                end
                error('NMAnalysisManagerTools:rootRelinkFailed', '%s', pathReport.message);
            end

            updatedA = NM.analysis{analind};
            if ~isempty(oldRoot)
                updatedA = NMAnalysisPathTools.rebaseStoredPaths(updatedA, oldRoot, resolvedRootDir);
            end
            updatedA.parentdir = resolvedParentDir;
            updatedA.rootdir = resolvedRootDir;
            NM.analysis{analind} = updatedA;
            newAnalysisDir = resolvedRootDir;
            if exist(newAnalysisDir,'dir') ~= 7
                if bulk
                    NM.analysis{analind} = A;
                    out = struct('ok',false,'message','Resolved directory disappeared during relinking.');
                    return;
                end
                error('NMAnalysisManagerTools:missingRelinkAnalysisDir', ...
                    'Resolved analysis directory does not exist after relinking: %s', newAnalysisDir);
            end

            out = struct('ok',true, ...
                'message',sprintf('Analysis %d root path relinked to %s (%s).', ...
                    analind, newAnalysisDir, resolution.userDescription), ...
                'analysisIndex',analind, ...
                'selectedDirectory',selectedDir, ...
                'selectionKindRequested',selectionKind, ...
                'selectionInterpretation',resolution.interpretation, ...
                'resolutionReason',resolution.reason, ...
                'rootdir',newAnalysisDir, ...
                'parentdir',resolvedParentDir, ...
                'pathReport',pathReport);
        end

        function resolution = resolveRelinkTarget(A, analind, selectedDir, oldAnalysisDir, selectionKind)
            % resolveRelinkTarget  Resolve an exact analysis root from a root/parent selection.
            if strcmp(selectionKind,'parent')
                childInfos = NMAnalysisPathTools.analysisRootChildCandidates(A, analind, selectedDir, oldAnalysisDir);
                resolution = NMAnalysisPathTools.resolveParentSelection(childInfos, selectedDir, oldAnalysisDir);
                return;
            end
            exactInfo = NMAnalysisPathTools.analysisRootCandidateInfo(A, analind, selectedDir, oldAnalysisDir);

            if strcmp(selectionKind,'root')
                if ~exactInfo.valid
                    error('NMAnalysisManagerTools:invalidRelinkRoot', ...
                        ['The selected directory does not contain recognizable analysis-root markers:\n%s\n' ...
                         'Markers inspected: %s'], selectedDir, NMAnalysisPathTools.markerText(exactInfo.markers));
                end
                resolution = NMAnalysisPathTools.makeRelinkResolution(selectedDir, 'exact_root', ...
                    sprintf('exact analysis root; markers: %s', NMAnalysisPathTools.markerText(exactInfo.markers)));
                return;
            end

            if exactInfo.valid && strcmp(exactInfo.basename, oldAnalysisDir)
                resolution = NMAnalysisPathTools.makeRelinkResolution(selectedDir, 'exact_root', ...
                    'selected directory basename matches the stored analysis directory');
                return;
            end
            childInfos = NMAnalysisPathTools.analysisRootChildCandidates(A, analind, selectedDir, oldAnalysisDir);
            if exactInfo.valid && isempty(childInfos)
                resolution = NMAnalysisPathTools.makeRelinkResolution(selectedDir, 'exact_root', ...
                    sprintf('selected directory contains analysis-root markers: %s', NMAnalysisPathTools.markerText(exactInfo.markers)));
                return;
            end
            if ~exactInfo.valid && ~isempty(childInfos)
                resolution = NMAnalysisPathTools.resolveParentSelection(childInfos, selectedDir, oldAnalysisDir);
                return;
            end
            if exactInfo.valid && ~isempty(childInfos)
                childText = strjoin({childInfos.path}, '\n  ');
                error('NMAnalysisManagerTools:ambiguousRelinkDirectory', ...
                    ['The selected directory could be interpreted both as an analysis root and as a parent containing analysis roots.\n' ...
                     'Selected directory: %s\nCandidate child roots:\n  %s\n' ...
                     'Select the exact analysis root or use selectionKind=''root'' or ''parent''.'], ...
                    selectedDir, childText);
            end
            error('NMAnalysisManagerTools:unresolvedRelinkDirectory', ...
                ['Could not identify an analysis root from the selected directory.\n' ...
                 'Selected directory: %s\nExpected previous folder name: %s\n' ...
                 'Select the exact relocated analysis folder or its immediate parent.'], selectedDir, oldAnalysisDir);
        end

        function resolution = resolveParentSelection(childInfos, selectedDir, oldAnalysisDir)
            % resolveParentSelection  Resolve one authoritative child root from a parent selection.
            if isempty(childInfos)
                error('NMAnalysisManagerTools:missingRelinkAnalysisDir', ...
                    ['No recognizable analysis root was found directly below the selected parent directory:\n%s\n' ...
                     'Expected previous folder name: %s'], selectedDir, oldAnalysisDir);
            end
            names = {childInfos.basename};
            oldMatch = find(strcmp(names, oldAnalysisDir));
            if numel(oldMatch) == 1
                info = childInfos(oldMatch);
                resolution = NMAnalysisPathTools.makeRelinkResolution(info.path, 'parent_directory', ...
                    'selected parent contains a child with the stored analysis-directory name');
                return;
            end
            if numel(childInfos) == 1
                info = childInfos(1);
                resolution = NMAnalysisPathTools.makeRelinkResolution(info.path, 'parent_directory', ...
                    sprintf('selected parent contains one recognizable analysis root; markers: %s', ...
                    NMAnalysisPathTools.markerText(info.markers)));
                return;
            end
            childText = strjoin({childInfos.path}, '\n  ');
            error('NMAnalysisManagerTools:ambiguousRelinkParent', ...
                ['The selected parent contains multiple recognizable analysis roots:\n  %s\n' ...
                 'Select the exact relocated analysis root instead.'], childText);
        end

        function resolution = makeRelinkResolution(rootdir, interpretation, reason)
            % makeRelinkResolution  Build the normalized relink-resolution record.
            [parentdir, ~] = fileparts(rootdir);
            if isempty(parentdir) || exist(parentdir,'dir') ~= 7
                error('NMAnalysisManagerTools:badRelinkParent', ...
                    'Resolved parent directory does not exist: %s', parentdir);
            end
            if exist(rootdir,'dir') ~= 7
                error('NMAnalysisManagerTools:missingRelinkAnalysisDir', ...
                    'Resolved analysis directory does not exist: %s', rootdir);
            end
            if strcmp(interpretation,'exact_root')
                userDescription = 'selected folder interpreted as the exact analysis root';
            else
                userDescription = 'selected folder interpreted as the parent directory';
            end
            resolution = struct('rootdir',rootdir, 'parentdir',parentdir, ...
                'interpretation',interpretation, 'reason',reason, 'userDescription',userDescription);
        end

        function infos = analysisRootChildCandidates(A, analind, parentDir, oldAnalysisDir)
            % analysisRootChildCandidates  Return validated direct child analysis roots.
            listing = dir(parentDir);
            infos = repmat(NMAnalysisPathTools.analysisRootCandidateTemplate(), 1, numel(listing));
            for i = 1:numel(listing)
                if ~listing(i).isdir || any(strcmp(listing(i).name,{'.','..'})), continue; end
                candidatePath = fullfile(parentDir, listing(i).name);
                infos(i) = NMAnalysisPathTools.analysisRootCandidateInfo(A, analind, candidatePath, oldAnalysisDir);
            end
            infos = infos([infos.valid]);
        end

        function info = analysisRootCandidateInfo(A, analind, candidateDir, oldAnalysisDir)
            % analysisRootCandidateInfo  Validate one directory using analysis-root markers.
            info = NMAnalysisPathTools.analysisRootCandidateTemplate();
            info.path = candidateDir;
            info.basename = NMAnalysisPathTools.pathBasename(candidateDir);
            info.exists = exist(candidateDir,'dir') == 7;
            if ~info.exists, return; end

            exactOldName = strcmp(info.basename, oldAnalysisDir);
            namingPattern = ~isempty(regexp(info.basename, '^NM_ID.*_A[0-9]+_', 'once'));

            paramsDir = fullfile(candidateDir,'params');
            hasParamsDir = exist(paramsDir,'dir') == 7;

            hasParamFile = false;
            oldParamFile = char(string(NMAnalysisPathTools.fieldOr(A,'paramfile','')));
            if ~isempty(oldParamFile)
                [paramBase, paramExt] = NMAnalysisPathTools.portableFileNameParts(oldParamFile);
                if isempty(paramExt), paramExt = '.mat'; end
                hasParamFile = exist(fullfile(paramsDir,[paramBase paramExt]),'file') == 2;
            elseif hasParamsDir
                paramListing = dir(fullfile(paramsDir,'*.mat'));
                hasParamFile = ~isempty(paramListing);
            end

            algorithm = '';
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && ...
                    isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'SVM') && isstruct(A.params.TrainParam.SVM)
                algorithm = char(string(NMAnalysisPathTools.fieldOr(A.params.TrainParam.SVM,'prog','')));
            end
            hasAlgorithmDir = ~isempty(algorithm) && exist(fullfile(candidateDir,algorithm),'dir') == 7;

            hasLogFile = false;
            oldLog = char(string(NMAnalysisPathTools.fieldOr(A,'logfile','')));
            if ~isempty(oldLog)
                [logBase, logExt] = NMAnalysisPathTools.portableFileNameParts(oldLog);
                hasLogFile = exist(fullfile(candidateDir,[logBase logExt]),'file') == 2;
            end
            if ~hasLogFile
                logListing = dir(fullfile(candidateDir,'NM_Analysis*.log'));
                hasLogFile = ~isempty(logListing);
            end

            analysisToken = sprintf('A%d_', analind);
            indexToken = contains(info.basename, analysisToken);
            markers = {'stored directory name', 'NeuroMiner analysis-directory pattern', ...
                'params directory', 'parameter MAT-file', 'algorithm results directory', ...
                'analysis log', 'analysis index token'};
            info.markers = markers([exactOldName, namingPattern, hasParamsDir, ...
                hasParamFile, hasAlgorithmDir, hasLogFile, indexToken]);
            info.valid = exactOldName || hasParamFile || ...
                (hasParamsDir && (hasAlgorithmDir || hasLogFile || namingPattern || indexToken)) || ...
                (hasAlgorithmDir && (hasLogFile || namingPattern || indexToken)) || ...
                (hasLogFile && (namingPattern || indexToken));
        end

        function info = analysisRootCandidateTemplate()
            % analysisRootCandidateTemplate  Return a normalized candidate record.
            info = struct('path','', 'basename','', 'exists',false, 'valid',false, 'markers',{{}});
        end

        function value = rebaseStoredPaths(value, oldRoot, newRoot)
            % rebaseStoredPaths  Rewrite stale-root-prefixed paths inside one analysis value.
            if isstruct(value)
                for idx = 1:numel(value)
                    fields = fieldnames(value(idx));
                    for i = 1:numel(fields)
                        value(idx).(fields{i}) = NMAnalysisPathTools.rebaseStoredPaths(value(idx).(fields{i}), oldRoot, newRoot);
                    end
                end
            elseif iscell(value)
                for i = 1:numel(value)
                    value{i} = NMAnalysisPathTools.rebaseStoredPaths(value{i}, oldRoot, newRoot);
                end
            elseif ischar(value) && (isrow(value) || isempty(value))
                value = NMAnalysisPathTools.rebasePathText(value, oldRoot, newRoot);
            elseif isstring(value)
                for i = 1:numel(value)
                    value(i) = string(NMAnalysisPathTools.rebasePathText(char(value(i)), oldRoot, newRoot));
                end
            end
        end

        function txt = rebasePathText(txt, oldRoot, newRoot)
            % rebasePathText  Replace an authoritative stale-root prefix in one text scalar.
            if isempty(txt) || isempty(oldRoot), return; end
            n = numel(oldRoot);
            if numel(txt) < n, return; end
            if ispc
                prefixMatch = strncmpi(txt, oldRoot, n);
            else
                prefixMatch = strncmp(txt, oldRoot, n);
            end
            if ~prefixMatch, return; end
            if numel(txt) > n
                nextChar = txt(n+1);
                if nextChar ~= filesep && nextChar ~= '/' && nextChar ~= '\'
                    return;
                end
            end
            suffix = txt(n+1:end);
            suffix(suffix == '/' | suffix == '\') = filesep;
            txt = [newRoot suffix];
        end

        function txt = trimTrailingSeparators(txt)
            % trimTrailingSeparators  Remove non-root trailing path separators.
            while numel(txt) > 1 && any(txt(end) == ['/' '\'])
                if ispc && numel(txt) == 3 && txt(2) == ':', break; end
                txt(end) = [];
            end
        end

        function name = pathBasename(pathText)
            % pathBasename  Return a basename independent of stored OS separators.
            pathText = NMAnalysisPathTools.trimTrailingSeparators(char(string(pathText)));
            separators = find(pathText == '/' | pathText == '\');
            if isempty(separators)
                name = pathText;
            else
                name = pathText(separators(end)+1:end);
            end
        end

        function [base, ext] = portableFileNameParts(pathText)
            % portableFileNameParts  Parse a stored filename from either slash convention.
            name = NMAnalysisPathTools.pathBasename(pathText);
            dotPos = find(name == '.', 1, 'last');
            if isempty(dotPos) || dotPos == 1
                base = name;
                ext = '';
            else
                base = name(1:dotPos-1);
                ext = name(dotPos:end);
            end
        end

        function txt = markerText(markers)
            % markerText  Format candidate-validation markers for diagnostics.
            if isempty(markers)
                txt = 'none';
            else
                txt = strjoin(markers, ', ');
            end
        end

        function v = fieldOr(s, field, defaultValue)
            % fieldOr  Read a non-empty struct field with an explicit fallback.
            v = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end
    end
end
