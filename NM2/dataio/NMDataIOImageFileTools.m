classdef NMDataIOImageFileTools
% NMDataIOImageFileTools
% -------------------------------------------------------------------------
% Shared compressed-NIfTI path handling for browser/API imaging DataIO.
% SPM/NM legacy image readers operate on uncompressed .nii/.img paths in
% many installations.  This utility resolves selected .nii.gz files to a
% usable SPM path while preserving the original user-selected path for case
% ID extraction, provenance and UI display.
% -------------------------------------------------------------------------

    methods (Static)
        function [resolvedFiles, messages, report, progressTask] = resolveNiftiFilesForSPM(files, sourceName, allowGunzip, opts)
            % resolveNiftiFilesForSPM  Resolve image paths into SPM-readable NIfTI files with optional gzip decompression.
            %
            % Consumes files, sourceName, allowGunzip, opts; returns resolvedFiles, messages, report, progressTask.
            % It is part of nIfTI/SPM file-resolution layer that normalizes image paths and optional decompression before spatial import.
            % Diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.ProgressMessage: overrides the progress text emitted while the method processes multiple items.
            % opts.ProgressTask: passes the current progress-task handle through nested UI/API operations.
            if nargin < 2 || isempty(sourceName), sourceName = 'imageFiles'; end
            if nargin < 3 || isempty(allowGunzip), allowGunzip = true; end
            if nargin < 4 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            files = NMDataIOStateTools.asCaseCell(files);
            files = files(:);
            files = files(~cellfun(@isempty, files));
            progressTask = NMDataIOImageFileTools.fieldOr(opts, 'ProgressTask', NMProgressTools.emptyTaskForLocalUse());
            progressLabel = NMDataIOImageFileTools.fieldOr(opts, 'ProgressMessage', 'Resolving image file %g of %g.');
            resolvedFiles = files;
            report = repmat(struct('input','','resolved','','usedExistingPair',false,'gunzipped',false,'usedCached',false,'cacheReused',false,'cacheRefreshed',false,'message',''), numel(files), 1);
            for i = 1:numel(files)
                if NMProgressTools.isEnabled(progressTask)
                    try
                        progressTask = NMProgressTools.step(progressTask, i, max(numel(files),1), sprintf(progressLabel, i, max(numel(files),1)));
                    catch
                        progressTask = NMProgressTools.step(progressTask, i, max(numel(files),1), sprintf('Resolving image file %g of %g.', i, max(numel(files),1)));
                    end
                end
                [resolvedFiles{i}, msg, rep] = NMDataIOImageFileTools.resolveNiftiFileForSPM(files{i}, sourceName, allowGunzip);
                messages = [messages; msg]; %#ok<AGROW>
                report(i) = rep;
            end
        end

        function tf = existsForSPM(fileName)
            % existsForSPM  Check whether a path or paired NIfTI form can be opened by SPM-oriented code.
            %
            % FileName -> tf.
            % It is part of nIfTI/SPM file-resolution layer that normalizes image paths and optional decompression before spatial import.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            fileName = NMDataIOStateTools.toChar(fileName);
            if isempty(fileName)
                tf = false;
                return;
            end
            [basePath, ~] = NMDataIOImageFileTools.splitVolumeSuffix(fileName);
            tf = exist(basePath,'file') == 2;
        end

        function [resolvedFile, messages, report] = resolveNiftiFileForSPM(fileName, sourceName, allowGunzip)
            % resolveNiftiFileForSPM  Resolve one image path into a concrete file that downstream SPM calls can read.
            %
            % Consumes fileName, sourceName, allowGunzip; returns resolvedFile, messages, report.
            % It is part of nIfTI/SPM file-resolution layer that normalizes image paths and optional decompression before spatial import.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if nargin < 2 || isempty(sourceName), sourceName = 'imageFile'; end
            if nargin < 3 || isempty(allowGunzip), allowGunzip = true; end
            messages = NMDataIOMessageTools.emptyMessages();
            fileName = NMDataIOStateTools.toChar(fileName);
            resolvedFile = fileName;
            report = struct('input',fileName,'resolved',resolvedFile,'usedExistingPair',false,'gunzipped',false,'usedCached',false,'cacheReused',false,'cacheRefreshed',false,'message','');
            if isempty(fileName)
                messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, 'Empty image filename supplied.', 1, 'red*')];
                report.message = 'empty filename';
                return;
            end

            [basePath, volSuffix] = NMDataIOImageFileTools.splitVolumeSuffix(fileName);
            [isGz, pairedNii] = NMDataIOImageFileTools.isGzippedNifti(basePath);
            if ~isGz
                if exist(basePath,'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('Image file does not exist: %s.', basePath), 1, 'red*')];
                    report.message = 'missing file';
                end
                resolvedFile = [basePath volSuffix];
                report.resolved = resolvedFile;
                return;
            end

            if exist(pairedNii,'file') == 2
                resolvedFile = [pairedNii volSuffix];
                report.resolved = resolvedFile;
                report.usedExistingPair = true;
                report.message = 'using existing uncompressed .nii pair';
                return;
            end

            if exist(basePath,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('Compressed NIfTI does not exist and no paired uncompressed .nii was found: %s.', basePath), 1, 'red*')];
                report.message = 'missing compressed and paired uncompressed files';
                return;
            end

            if ~allowGunzip
                messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('SPM-readable .nii counterpart is required for compressed NIfTI: %s.', basePath), 1, 'red*')];
                report.message = 'gunzip disabled';
                return;
            end

            cacheDir = NMUISessionTools.privateProcessTempRoot('nifti');
            [~, stem] = fileparts(pairedNii);
            info = dir(basePath);
            sourceKey = sprintf('%s|%0.0f|%.17g', basePath, double(info(1).bytes), double(info(1).datenum));
            targetFile = fullfile(cacheDir, sprintf('%s_%s.nii', NMDataIOImageFileTools.safeStem(stem), NMDataIOImageFileTools.shortHash(sourceKey)));
            if exist(targetFile,'file') ~= 2
                stageDir = tempname(cacheDir);
                [ok,msg] = mkdir(stageDir);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('Could not create NIfTI decompression staging directory (%s): %s.', stageDir, msg), 1, 'red*')];
                    report.message = msg;
                    return;
                end
                stageCleanup = onCleanup(@() NMUISessionTools.cleanupMaterializationStage(stageDir)); %#ok<NASGU>
                try
                    outFiles = gunzip(basePath, stageDir);
                catch ME
                    messages = [messages; NMDataIOMessageTools.fromException(ME, sprintf('%s.gunzip', sourceName))];
                    report.message = sprintf('%s: %s', ME.identifier, ME.message);
                    return;
                end
                if isempty(outFiles) || exist(outFiles{1},'file') ~= 2
                    messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('gunzip did not create a readable .nii file for %s.', basePath), 1, 'red*')];
                    report.message = 'gunzip returned no readable file';
                    return;
                end
                [ok,msg] = movefile(outFiles{1}, targetFile);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, sourceName, sprintf('Could not publish decompressed NIfTI %s: %s.', targetFile, msg), 1, 'red*')];
                    report.message = msg;
                    return;
                end
                clear stageCleanup;
                report.cacheRefreshed = true;
            else
                report.cacheReused = true;
            end
            resolvedFile = [targetFile volSuffix];
            report.resolved = resolvedFile;
            report.gunzipped = true;
            report.usedCached = true;
            report.message = 'using a previously prepared uncompressed .nii copy';
        end
    end

    methods (Static, Access = private)
        function val = fieldOr(s, name, defaultVal)
            val = defaultVal;
            if nargin < 3, defaultVal = []; val = defaultVal; end
            if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
                val = s.(name);
            end
        end

        function [basePath, volSuffix] = splitVolumeSuffix(fileName)
            fileName = NMDataIOStateTools.toChar(fileName);
            tok = regexp(fileName, '^(.*\.(?:nii|img|hdr)(?:\.gz)?)(,\d+)$', 'tokens', 'once', 'ignorecase');
            if isempty(tok)
                basePath = fileName;
                volSuffix = '';
            else
                basePath = tok{1};
                volSuffix = tok{2};
            end
        end

        function [tf, pairedNii] = isGzippedNifti(fileName)
            fileName = NMDataIOStateTools.toChar(fileName);
            tf = ~isempty(regexpi(fileName, '\.nii\.gz$', 'once'));
            if tf
                pairedNii = regexprep(fileName, '\.gz$', '', 'ignorecase');
            else
                pairedNii = fileName;
            end
        end


        function s = safeStem(stem)
            stem = regexprep(NMDataIOStateTools.toChar(stem), '[^A-Za-z0-9_\-]', '_');
            if isempty(stem), stem = 'nifti'; end
            if numel(stem) > 48, stem = stem(1:48); end
            s = stem;
        end

        function h = shortHash(txt)
            md = java.security.MessageDigest.getInstance('SHA-256');
            md.update(uint8(NMDataIOStateTools.toChar(txt)));
            digest = typecast(md.digest(),'uint8');
            h = lower(reshape(dec2hex(digest)',1,[]));
            h = h(1:24);
        end

    end
end
