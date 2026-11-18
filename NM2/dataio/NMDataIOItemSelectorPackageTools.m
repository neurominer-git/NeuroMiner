classdef NMDataIOItemSelectorPackageTools
% NMDataIOItemSelectorPackageTools
% -------------------------------------------------------------------------
% Binary transport package for the browser-based DataIO item selector.
%
% The selector must inspect candidate import matrices without JSON-ising
% numeric arrays.  This class writes a producer-authorized package into the
% active bridge tmpDir and exposes only a small JSON manifest.  The Python
% bridge serves files from this package only if the manifest explicitly lists
% the requested asset.
% -------------------------------------------------------------------------

    methods (Static)
        function out = preparePackage(NM, state, tmpDir, opts)
            % preparePackage  Build the transient item-selector package consumed by the browser-side selector UI.
            %
            % Consumes NM, state, tmpDir, opts; returns out.
            % It transfers item-selector state through temporary files so the UI can handle large masks safely.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling.
            %
            % opts.ExactElementLimit: sets the element threshold below which browser responses may carry exact tabular values.
            % opts.HardElementLimit: sets the hard maximum size for browser-side preview/export payloads.
            % opts.ProfileLabel: names the profiling segment so nested timing diagnostics can be traced to the caller.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 4 || isempty(opts), opts = struct(); end

            doProfile = NMDataIOProfileTools.enabled([], [], opts);
            profileLabel = char(string(NMDataIOItemSelectorPackageTools.opt(opts, 'ProfileLabel', 'itemselector.prepare')));
            tTotal = tic;
            NMDataIOProfileTools.log(doProfile, '%s preparePackage ENTER', profileLabel);
            exactLimit = NMDataIOItemSelectorPackageTools.opt(opts, 'ExactElementLimit', 2e6);
            hardLimit  = NMDataIOItemSelectorPackageTools.opt(opts, 'HardElementLimit', 1e7);
            token = NMDataIOItemSelectorPackageTools.newToken();
            pkgDir = fullfile(tmpDir, ['itemselector_' token]);
            if ~exist(pkgDir,'dir'), mkdir(pkgDir); end

            out = struct('ok',false, 'token',token, 'packageDir',pkgDir, ...
                'messages',NMDataIOMessageTools.emptyMessages(), 'manifest',struct());

            try
                materializationOpts = struct('ProfileEnabled',doProfile,'ProfileLabel',[profileLabel '.materializeMatrixImport']);
                cacheKeyHint = char(string(NMDataIOItemSelectorPackageTools.opt(opts,'MaterializationCacheKey','')));
                if ~isempty(cacheKeyHint)
                    materializationOpts.MaterializationCacheKey = cacheKeyHint;
                    materializationOpts.RequireRetainedMaterialization = true;
                end
                tPrepare = tic;
                [entry, cacheHit, cacheKey] = NMDataIOImportTools.materializeMatrixImport(NM, state, materializationOpts);
                NMDataIOProfileTools.log(doProfile, '%s materializeMatrixImport(cacheHit=%g): %.3fs', profileLabel, double(cacheHit), toc(tPrepare));
                IO = entry.IO;
                messages = entry.messages;
                out.materializationCacheHit = logical(cacheHit);
                out.materializationCacheKey = cacheKey;
                out.messages = messages;
                if NMDataIOMessageTools.hasFatal(messages)
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector package preparation blocked by DataIO diagnostics.');
                    return;
                end

                tExtract = tic;
                [M, featNames, caseNames, labels, IO] = NMDataIOImportTools.extractMatrixAxes(IO);
                NMDataIOProfileTools.log(doProfile, '%s extractMatrixAxes: %.3fs', profileLabel, toc(tExtract));
                if ~(isnumeric(M) || islogical(M))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'itemSelector.prepare', ...
                        'Item selector requires numeric/logical feature data after role resolution.', 1, 'red*')];
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector package could not be prepared.');
                    return;
                end
                M = double(M);
                nCases = size(M,1);
                nFeatures = size(M,2);
                nElements = nCases * nFeatures;
                if nCases == 0 || nFeatures == 0
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'itemSelector.prepare', ...
                        'Item selector cannot open because no candidate cases/features are available.', 1, 'red*')];
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector package could not be prepared.');
                    return;
                end

                casesLocked = NMDataIOItemSelectorPackageTools.casesLockedForState(NM, IO, state);
                selCases = NMDataIOMaterializationCache.caseSelection(state,nCases);
                selFeats = NMDataIOMaterializationCache.featureSelection(state,nFeatures);
                if casesLocked, selCases(:) = true; end

                manifest = struct();
                manifest.kind = 'NMDataIOItemSelectorPackage';
                manifest.schemaVersion = 1;
                manifest.token = token;
                manifest.createdBy = 'dataio_itemselector_prepare';
                manifest.createdAt = datestr(now, 30);
                manifest.nCases = nCases;
                manifest.nFeatures = nFeatures;
                manifest.nElements = nElements;
                manifest.dtype = 'float32';
                manifest.layout = 'rowmajor';
                manifest.casesLocked = logical(casesLocked);
                manifest.labelsAvailable = ~isempty(labels);
                manifest.exactElementLimit = double(exactLimit);
                manifest.hardElementLimit = double(hardLimit);
                manifest.allowedFiles = struct();
                manifest.allowedFiles.cases = 'cases.txt';
                manifest.allowedFiles.features = 'features.txt';
                manifest.allowedFiles.selCases = 'selCases_u8.bin';
                manifest.allowedFiles.selFeats = 'selFeats_u8.bin';
                manifest.allowedFiles.labels = 'labels.txt';

                NMDataIOItemSelectorPackageTools.writeNames(fullfile(pkgDir, manifest.allowedFiles.cases), caseNames, nCases, 'S');
                NMDataIOItemSelectorPackageTools.writeNames(fullfile(pkgDir, manifest.allowedFiles.features), featNames, nFeatures, 'F');
                if ~isempty(labels)
                    NMDataIOItemSelectorPackageTools.writeNames(fullfile(pkgDir, manifest.allowedFiles.labels), labels, nCases, 'L');
                else
                    manifest.allowedFiles = rmfield(manifest.allowedFiles, 'labels');
                end
                NMDataIOItemSelectorPackageTools.writeMask(fullfile(pkgDir, manifest.allowedFiles.selCases), selCases);
                NMDataIOItemSelectorPackageTools.writeMask(fullfile(pkgDir, manifest.allowedFiles.selFeats), selFeats);

                if nElements <= exactLimit
                    manifest.transferMode = 'exactBinary';
                    manifest.allowedFiles.matrix = 'matrix_f32_rowmajor.bin';
                    tWriteMatrix = tic;
                    NMDataIOItemSelectorPackageTools.writeMatrixRowMajor(fullfile(pkgDir, manifest.allowedFiles.matrix), M);
                    NMDataIOProfileTools.log(doProfile, '%s writeMatrixRowMajor %.0fx%.0f: %.3fs', profileLabel, size(M,1), size(M,2), toc(tWriteMatrix));
                elseif nElements <= hardLimit
                    manifest.transferMode = 'metadataOnly';
                    manifest.skipReason = sprintf('Matrix contains %g elements; exact browser transfer limit is %g.', double(nElements), double(exactLimit));
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'itemSelector.prepare', ...
                        manifest.skipReason, 2, 'SystemCommands')];
                else
                    manifest.transferMode = 'blockedBySize';
                    manifest.skipReason = sprintf('Matrix contains %g elements; hard item-selector limit is %g.', double(nElements), double(hardLimit));
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'itemSelector.prepare', ...
                        manifest.skipReason, 1, 'red*')];
                    NMDataIOItemSelectorPackageTools.writeManifest(fullfile(pkgDir,'manifest.json'), manifest);
                    out.manifest = manifest;
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'This matrix is too large to inspect interactively in the browser.');
                    return;
                end

                tManifest = tic;
                NMDataIOItemSelectorPackageTools.writeManifest(fullfile(pkgDir,'manifest.json'), manifest);
                NMDataIOProfileTools.log(doProfile, '%s writeManifest: %.3fs', profileLabel, toc(tManifest));
                out.ok = true;
                out.blocking = false;
                out.readyToInspect = strcmpi(manifest.transferMode, 'exactBinary');
                out.message = 'Matrix Inspector data prepared.';
                out.manifest = manifest;
                out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
                out.summary = NMDataIOMessageTools.summarize(messages);
                out.strip = NMDataIOMessageTools.highestPriorityStrip(messages, out.message);
                out.endpoints = NMDataIOItemSelectorPackageTools.endpoints(token, manifest);
                NMDataIOProfileTools.log(doProfile, '%s preparePackage TOTAL: %.3fs', profileLabel, toc(tTotal));
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'itemSelector.prepare');
                out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector package preparation failed.');
            end
        end

        function out = applyMasks(state, tmpDir, token, opts)
            % applyMasks  Read browser-selected item masks and return a masked selector package.
            %
            % Consumes state, tmpDir, token, opts; returns out.
            % It transfers item-selector state through temporary files so the UI can handle large masks safely.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            %
            % state.selection: carries the selection value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state), state = struct(); end
            if nargin < 2 || isempty(tmpDir), tmpDir = tempdir; end
            if nargin < 3 || isempty(token), token = ''; end
            if nargin < 4 || isempty(opts), opts = struct(); end %#ok<NASGU>
            out = struct('ok',false, 'blocking',true, 'message','Item selector selection was not applied.', ...
                'messages',NMDataIOMessageTools.emptyMessages(), 'statePatch',struct());
            try
                token = NMDataIOItemSelectorPackageTools.cleanToken(token);
                manifest = NMDataIOItemSelectorPackageTools.readManifest(tmpDir, token);
                pkgDir = fullfile(tmpDir, ['itemselector_' token]);
                fMask = fullfile(pkgDir, manifest.allowedFiles.selFeats);
                cMask = fullfile(pkgDir, manifest.allowedFiles.selCases);
                selFeats = NMDataIOItemSelectorPackageTools.readMask(fMask, manifest.nFeatures);
                selCases = NMDataIOItemSelectorPackageTools.readMask(cMask, manifest.nCases);
                if ~any(selFeats)
                    messages = NMDataIOMessageTools.make('danger', true, 'itemSelector.apply', ...
                        'Item selector cannot apply an empty feature selection.', 1, 'red*');
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector selection was not applied.');
                    return;
                end
                if ~manifest.casesLocked && ~any(selCases)
                    messages = NMDataIOMessageTools.make('danger', true, 'itemSelector.apply', ...
                        'Select at least one case before applying the Matrix Inspector selection.', 1, 'red*');
                    out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector selection was not applied.');
                    return;
                end
                if manifest.casesLocked
                    selCases(:) = true;
                    NMDataIOItemSelectorPackageTools.writeMask(cMask, selCases);
                end

                if ~isstruct(state), state = struct(); end
                state.selection = struct();
                state.selection.itemSelectorToken = token;
                state.selection.selFeatsFile = fMask;
                state.selection.selCasesFile = cMask;
                state.selection.nSelectedFeatures = sum(selFeats);
                state.selection.nSelectedCases = sum(selCases);
                state.selection.nAvailableFeatures = manifest.nFeatures;
                state.selection.nAvailableCases = manifest.nCases;
                state.selection.casesLocked = logical(manifest.casesLocked);
                state.selection.transferMode = manifest.transferMode;

                messages = NMDataIOMessageTools.make('ok', false, 'itemSelector.apply', ...
                    sprintf('Applied item-selector masks: %g/%g feature(s), %g/%g case(s).', sum(selFeats), manifest.nFeatures, sum(selCases), manifest.nCases), 0, 'green*');
                out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector selection applied.');
                out.ok = true;
                out.blocking = false;
                out.statePatch = state;
                out.selectionSummary = state.selection;
            catch ME
                messages = NMDataIOMessageTools.fromException(ME, 'itemSelector.apply');
                out = NMDataIOItemSelectorPackageTools.finishOut(out, messages, 'Item selector selection was not applied.');
            end
        end

        function out = closePackage(tmpDir, token)
            % closePackage  Delete transient selector package files after the browser session finishes.
            %
            % TmpDir, token -> out.
            % It transfers item-selector state through temporary files so the UI can handle large masks safely.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            token = NMDataIOItemSelectorPackageTools.cleanToken(token);
            pkgDir = fullfile(tmpDir, ['itemselector_' token]);
            out = struct('ok', true, 'message', 'Item selector package closed.');
            if exist(pkgDir,'dir')
                try
                    rmdir(pkgDir, 's');
                catch ME
                    out.ok = false;
                    out.message = sprintf('Could not remove item selector package: %s (%s)', ME.message, ME.identifier);
                end
            end
        end

        function manifest = readManifest(tmpDir, token)
            % readManifest  Read the selector package manifest from disk.
            %
            % TmpDir, token -> manifest.
            % It transfers item-selector state through temporary files so the UI can handle large masks safely.
            % Throws on invalid preconditions instead of returning an ambiguous partial result.
            token = NMDataIOItemSelectorPackageTools.cleanToken(token);
            manifestFile = fullfile(tmpDir, ['itemselector_' token], 'manifest.json');
            if exist(manifestFile,'file') ~= 2
                error('NMDataIOItemSelectorPackageTools:noManifest', 'The Matrix Inspector data are no longer available. Close and reopen the Matrix Inspector.', token);
            end
            manifest = jsondecode(fileread(manifestFile));
            if ~isstruct(manifest) || ~isfield(manifest,'kind') || ~strcmp(char(manifest.kind), 'NMDataIOItemSelectorPackage')
                error('NMDataIOItemSelectorPackageTools:badManifest', 'The saved Matrix Inspector data are invalid. Close and reopen the Matrix Inspector.', token);
            end
        end

        function mask = readMaskFile(path, expectedN)
            % readMaskFile  Read and validate a selector mask file against an expected feature count.
            %
            % Path, expectedN -> mask.
            % It transfers item-selector state through temporary files so the UI can handle large masks safely.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 2, expectedN = []; end
            mask = NMDataIOItemSelectorPackageTools.readMask(path, expectedN);
        end
    end

    methods (Static, Access = private)
        function v = opt(opts, name, default)
            v = default;
            if isstruct(opts) && isfield(opts,name) && ~isempty(opts.(name))
                v = opts.(name);
            end
        end

        function token = newToken()
            token = char(java.util.UUID.randomUUID());
            token = strrep(token, '-', '');
        end

        function token = cleanToken(token)
            token = char(string(token));
            token = regexprep(token, '[^A-Za-z0-9_\-]', '');
            if isempty(token) || isempty(regexp(token, '^[A-Za-z0-9_\-]+$', 'once'))
                error('NMDataIOItemSelectorPackageTools:badToken', 'The Matrix Inspector session reference is invalid. Close and reopen the Matrix Inspector.');
            end
        end

        function endpoints = endpoints(token, manifest)
            base = ['/api/itemselector/' token];
            endpoints = struct();
            endpoints.header = [base '/header'];
            endpoints.cases = [base '/cases'];
            endpoints.features = [base '/features'];
            endpoints.selCases = [base '/mask?kind=cases'];
            endpoints.selFeats = [base '/mask?kind=features'];
            if isfield(manifest.allowedFiles, 'matrix')
                endpoints.matrix = [base '/matrix'];
            else
                endpoints.matrix = '';
            end
            if isfield(manifest.allowedFiles, 'labels')
                endpoints.labels = [base '/labels'];
            else
                endpoints.labels = '';
            end
        end

        function tf = casesLockedForState(NM, IO, state)
            tf = false;
            try
                k = double(IO.varind);
                if k > 1 && isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                    tf = true;
                end
                if isstruct(state) && isfield(state,'importTarget') && isstruct(state.importTarget)
                    mode = '';
                    if isfield(state.importTarget,'mode'), mode = lower(char(string(state.importTarget.mode))); end
                    if any(strcmp(mode, {'add','replace','resume'})) && k > 1
                        tf = true;
                    end
                end
            catch
                tf = false;
            end
        end

        function writeNames(path, names, n, prefix)
            names = NMDataIOItemSelectorPackageTools.cellstrWithFallback(names, n, prefix);
            fid = fopen(path, 'w');
            if fid < 0, error('NMDataIOItemSelectorPackageTools:writeNames', 'Could not write %s.', path); end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            for i = 1:numel(names)
                fprintf(fid, '%s\n', char(names{i}));
            end
        end

        function names = cellstrWithFallback(names, n, prefix)
            if nargin < 3 || isempty(prefix), prefix = 'I'; end
            try
                if isstring(names), names = cellstr(names(:));
                elseif isnumeric(names) || islogical(names), names = cellstr(string(names(:)));
                elseif iscell(names), names = cellfun(@(x) char(string(x)), names(:), 'UniformOutput', false);
                else, names = cellstr(string(names(:)));
                end
            catch
                names = {};
            end
            if numel(names) ~= n
                names = arrayfun(@(i) sprintf('%s%g', prefix, i), (1:n)', 'UniformOutput', false);
            end
        end

        function writeMask(path, mask)
            fid = fopen(path, 'w');
            if fid < 0, error('NMDataIOItemSelectorPackageTools:writeMask', 'Could not write %s.', path); end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, uint8(logical(mask(:))), 'uint8');
        end

        function mask = readMask(path, expectedN)
            if exist(path,'file') ~= 2
                error('NMDataIOItemSelectorPackageTools:noMask', 'Mask file not found: %s.', path);
            end
            fid = fopen(path, 'r');
            if fid < 0, error('NMDataIOItemSelectorPackageTools:readMask', 'Could not read %s.', path); end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            v = fread(fid, inf, '*uint8');
            mask = logical(v(:));
            if nargin >= 2 && ~isempty(expectedN) && numel(mask) ~= expectedN
                error('NMDataIOItemSelectorPackageTools:maskSize', 'Mask length is %g; expected %g.', numel(mask), expectedN);
            end
        end

        function writeMatrixRowMajor(path, M)
            fid = fopen(path, 'w');
            if fid < 0, error('NMDataIOItemSelectorPackageTools:writeMatrix', 'Could not write %s.', path); end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, single(M.'), 'single');
        end

        function writeManifest(path, manifest)
            txt = jsonencode(manifest);
            fid = fopen(path, 'w');
            if fid < 0, error('NMDataIOItemSelectorPackageTools:manifest', 'Could not write %s.', path); end
            c = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fwrite(fid, txt, 'char');
        end

        function out = finishOut(out, messages, fallback)
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, fallback);
            out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
            out.summary = NMDataIOMessageTools.summarize(messages);
            out.strip = strip;
            out.message = strip.text;
            out.blocking = strip.blocking;
            out.ok = ~strip.blocking;
        end
    end
end
