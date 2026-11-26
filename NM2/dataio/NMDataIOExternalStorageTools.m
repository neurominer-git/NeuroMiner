classdef NMDataIOExternalStorageTools
% NMDataIOExternalStorageTools
% -------------------------------------------------------------------------
% Non-interactive external storage operations for browser/API DataIO.
% Handles storage state transitions for training NM.Y{varind} and for
% explicit OOCV/application targets such as NM.OOCV{k}.Y{varind}.
% -------------------------------------------------------------------------

    methods (Static)
        function [NM, messages, outPath] = externalizeModality(NM, varind, outputDir, importTarget)
            % externalizeModality  Write a committed modality matrix to an external MAT file and replace in-struct data with a link.
            %
            % Consumes NM, varind, outputDir, importTarget; returns NM, messages, outPath.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Performs explicit file-system IO; callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            outPath = '';
            if nargin < 4 || isempty(importTarget)
                importTarget = struct('scope','training','mode','replace','varind',double(varind));
            else
                importTarget.varind = double(varind);
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, varind);
            [D, targetMessages] = NMDataIOExternalStorageTools.getTargetForStorage(NM, importTarget, 'externalizeModality');
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if nargin < 3 || isempty(outputDir) || ~(ischar(outputDir) || isstring(outputDir))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'externalizeModality', 'An output directory is required for externalizing a modality.', 1, 'red*')];
                return;
            end
            outputDir = char(outputDir);
            if exist(outputDir,'dir') ~= 7
                [mkOK, mkMsg] = mkdir(outputDir);
                if ~mkOK
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'externalizeModality', sprintf('Could not create output directory %s. %s', outputDir, mkMsg), 1, 'red*')];
                    return;
                end
            end
            [Y, hasY] = NMDataIOExternalStorageTools.getYCell(D, varind);
            if ~hasY || isempty(Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'externalizeModality', sprintf('%s has no loaded feature matrix to externalize.', NMDataIOImportTargetTools.targetLabel(importTarget)), 1, 'red*')];
                return;
            end
            if ischar(Y) || isstring(Y)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'externalizeModality', sprintf('%s is already stored as an external link.', NMDataIOImportTargetTools.targetLabel(importTarget)), 2, 'SystemCommands')];
                return;
            end
            if ~(isnumeric(Y) || islogical(Y))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'externalizeModality', sprintf('%s contains an unsupported in-memory feature-data type (%s).', NMDataIOImportTargetTools.targetLabel(importTarget), class(Y)), 1, 'red*')];
                return;
            end
            outPath = fullfile(outputDir, NMDataIOExternalStorageTools.defaultExternalFilename(D, varind, importTarget));
            try
                ExternalDataInfo = NMDataIOExternalStorageTools.writeExternalArtifact( ...
                    outPath, D, varind, importTarget, Y, 'NMDataIOExternalStorageTools.externalizeModality');
            catch ME
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'externalizeModality', ...
                    sprintf('Could not externalize %s to %s. %s (%s)', NMDataIOImportTargetTools.targetLabel(importTarget), outPath, ME.message, ME.identifier), 1, 'red*')];
                return;
            end
            D.Y{varind} = outPath;
            D = NMDataIOExternalStorageTools.refreshTargetModalityInfo(D, varind);
            D = NMDataIOExternalStorageTools.storeExternalCompatibilityInfo(D, varind, ExternalDataInfo);
            NM = NMDataIOImportTargetTools.setContainer(NM, importTarget, D);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'externalizeModality', sprintf('Moved %s to external storage: %s.', NMDataIOImportTargetTools.targetLabel(importTarget), outPath), 0, 'green*')];
        end

        function [D, messages] = finalizeReplacementStorage(existingD, D, varind)
            % finalizeReplacementStorage  Preserve one resolved container's storage representation after replacement Commit.
            %
            % Target routing is deliberately outside this routine. Scientific materialization and
            % TransferModality2NM operate on an already-resolved container; at the late commit
            % boundary, a valid external link is rewritten in place and retained as D.Y{varind},
            % while a stale link falls back explicitly to the resident committed matrix.
            messages = NMDataIOMessageTools.emptyMessages();
            [oldY, hasOldY] = NMDataIOExternalStorageTools.getYCell(existingD, varind);
            if ~hasOldY || ~(ischar(oldY) || isstring(oldY))
                return;
            end
            oldPath = char(string(oldY));
            [newY, hasNewY] = NMDataIOExternalStorageTools.getYCell(D, varind);
            if ~hasNewY || ~(isnumeric(newY) || islogical(newY))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeReplacementStorage', ...
                    sprintf('The replacement for modality %g did not produce a resident numeric feature matrix before storage finalization.', ...
                    double(varind)), 1, 'red*')];
                return;
            end

            if exist(oldPath,'file') ~= 2
                D = NMDataIOExternalStorageTools.clearExternalCompatibilityInfo(D, varind);
                D = NMDataIOExternalStorageTools.refreshTargetModalityInfo(D, varind);
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'finalizeReplacementStorage', ...
                    sprintf(['The previous external modality file no longer exists: %s. ' ...
                    'The updated modality has therefore been stored in the NM structure instead.'], ...
                    oldPath), 2, 'SystemCommands')];
                return;
            end

            oldDir = fileparts(oldPath);
            if isempty(oldDir), oldDir = pwd; end
            tmpPath = [tempname(oldDir) '.mat'];
            tmpCleanup = onCleanup(@()NMDataIOExternalStorageTools.deleteIfExists(tmpPath)); %#ok<NASGU>
            try
                artifactIdentity = NMDataIOExternalStorageTools.externalCompatibilityInfo(existingD, varind);
                if ~isfield(artifactIdentity,'scope') || isempty(artifactIdentity.scope)
                    error('NMDataIOExternalStorageTools:externalIdentityMissing', ...
                        'The existing externalized modality has no persisted storage identity.');
                end
                ExternalDataInfo = NMDataIOExternalStorageTools.writeExternalArtifact( ...
                    tmpPath, D, varind, artifactIdentity, newY, 'NMDataIOExternalStorageTools.finalizeReplacementStorage');
                info = whos('-file', tmpPath, 'Y');
                if numel(info) ~= 1 || ~isequal(double(info.size), double(size(newY))) || ~strcmp(info.class, class(newY))
                    error('NMDataIOExternalStorageTools:replacementArtifactValidation', ...
                        'Temporary external modality artifact failed matrix size/class validation.');
                end
                [moved, moveMessage, moveId] = movefile(tmpPath, oldPath, 'f');
                if ~moved
                    error('NMDataIOExternalStorageTools:replacementArtifactMove', ...
                        'Could not replace external modality file %s. %s (%s)', oldPath, moveMessage, moveId);
                end
            catch ME
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'finalizeReplacementStorage', ...
                    sprintf('Could not update external storage for modality %g at %s. %s (%s)', ...
                    double(varind), oldPath, ME.message, ME.identifier), 1, 'red*')];
                return;
            end
            D.Y{varind} = oldPath;
            D = NMDataIOExternalStorageTools.refreshTargetModalityInfo(D, varind);
            D = NMDataIOExternalStorageTools.storeExternalCompatibilityInfo(D, varind, ExternalDataInfo);
        end

        function [NM, messages] = relinkModality(NM, varind, matFile, importTarget)
            % relinkModality  Reconnect a modality to an existing external MAT feature file after compatibility validation.
            %
            % Consumes NM, varind, matFile, importTarget; returns NM, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 4 || isempty(importTarget)
                importTarget = struct('scope','training','mode','replace','varind',double(varind));
            else
                importTarget.varind = double(varind);
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, varind);
            [D, targetMessages] = NMDataIOExternalStorageTools.getTargetForStorage(NM, importTarget, 'relinkModality');
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            if nargin < 3 || isempty(matFile) || ~(ischar(matFile) || isstring(matFile))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'relinkModality', 'A MAT-file path is required for relinking a modality.', 1, 'red*')];
                return;
            end
            matFile = char(matFile);
            if exist(matFile,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'relinkModality', sprintf('Linked modality file does not exist: %s', matFile), 1, 'red*')];
                return;
            end
            [valid, detail, fileModality, externalInfo] = NMDataIOExternalStorageTools.validateMatFeatureFile(matFile, D, varind, importTarget);
            if ~valid
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'relinkModality', detail, 1, 'red*')];
                return;
            end
            if ~isnan(fileModality) && fileModality ~= double(varind)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'relinkModality', sprintf('MAT-file declares Modality=%g but will be linked to %s.', fileModality, NMDataIOImportTargetTools.targetLabel(importTarget)), 2, 'SystemCommands')];
            end
            D.Y{varind} = matFile;
            D = NMDataIOExternalStorageTools.refreshTargetModalityInfo(D, varind);
            if isstruct(externalInfo) && isfield(externalInfo,'compatibilityHash')
                D = NMDataIOExternalStorageTools.storeExternalCompatibilityInfo(D, varind, externalInfo);
            end
            NM = NMDataIOImportTargetTools.setContainer(NM, importTarget, D);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'relinkModality', sprintf('Linked %s to %s.', NMDataIOImportTargetTools.targetLabel(importTarget), matFile), 0, 'green*')];
        end

        function [NM, messages] = reimportLinkedModality(NM, varind, importTarget)
            % reimportLinkedModality  Load an externally linked modality back into the active NM target container.
            %
            % Consumes NM, varind, importTarget; returns NM, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || isempty(importTarget)
                importTarget = struct('scope','training','mode','replace','varind',double(varind));
            else
                importTarget.varind = double(varind);
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, varind);
            [D, targetMessages] = NMDataIOExternalStorageTools.getTargetForStorage(NM, importTarget, 'reimportLinkedModality');
            messages = [messages; targetMessages];
            if NMDataIOMessageTools.hasFatal(messages), return; end

            [Ylink, hasY] = NMDataIOExternalStorageTools.getYCell(D, varind);
            if ~hasY || ~(ischar(Ylink) || isstring(Ylink))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'reimportLinkedModality', sprintf('%s is not an external link.', NMDataIOImportTargetTools.targetLabel(importTarget)), 1, 'red*')];
                return;
            end
            Ylink = char(Ylink);
            if exist(Ylink,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'reimportLinkedModality', sprintf('Linked modality file does not exist: %s', Ylink), 1, 'red*')];
                return;
            end
            [valid, detail] = NMDataIOExternalStorageTools.validateMatFeatureFile(Ylink, D, varind, importTarget);
            if ~valid
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'reimportLinkedModality', detail, 1, 'red*')];
                return;
            end
            try
                S = load(Ylink);
            catch ME
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'reimportLinkedModality', ...
                    sprintf('Could not load linked modality file %s. %s (%s)', Ylink, ME.message, ME.identifier), 1, 'red*')];
                return;
            end
            if isfield(S,'Y')
                Y = S.Y;
            elseif isfield(S,'OOCV')
                Y = S.OOCV;
            else
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'reimportLinkedModality', sprintf('Linked file %s does not contain Y or OOCV.', Ylink), 1, 'red*')];
                return;
            end
            D.Y{varind} = Y;
            D = NMDataIOExternalStorageTools.refreshTargetModalityInfo(D, varind);
            NM = NMDataIOImportTargetTools.setContainer(NM, importTarget, D);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'reimportLinkedModality', sprintf('Re-imported linked data for %s into memory.', NMDataIOImportTargetTools.targetLabel(importTarget)), 0, 'green*')];
        end

        function [valid, detail, modality, externalInfo, archive] = validateMatFeatureFile(matFile, D, varind, importTarget, wholeContainer)
            % validateMatFeatureFile  Validate that an external MAT file matches the target modality schema and compatibility hash.
            %
            % Consumes matFile, D, varind, importTarget; returns valid, detail, modality, externalInfo.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            arguments
                matFile
                D = struct()
                varind = []
                importTarget = []
                wholeContainer = false
            end
            valid = false;
            detail = '';
            modality = NaN;
            externalInfo = struct();
            archive = [];
            try
                if wholeContainer && nargout >= 5
                    OOCV = nk_LoadLinkedData(struct('Y',matFile),[]);
                    vars = whos('OOCV');
                else
                    vars = whos('-file', matFile);
                end
            catch ME
                detail = sprintf('Could not inspect MAT-file %s. %s (%s)', matFile, ME.message, ME.identifier);
                return;
            end
            names = {vars.name};
            if wholeContainer
                entry = vars(strcmp(names,'OOCV'));
                valid = ~isempty(entry) && strcmp(entry.class,'struct') && prod(entry.size) == 1;
                if valid
                    if nargout >= 5, archive = OOCV; end
                    detail = 'MAT-file contains a scalar OOCV structure.';
                else
                    detail = sprintf('Linked archive %s must contain one scalar OOCV structure.',matFile);
                end
                return;
            end
            if ~any(strcmp(names,'Y')) && ~any(strcmp(names,'OOCV'))
                detail = sprintf('MAT-file %s does not contain a Y or OOCV variable.', matFile);
                return;
            end
            if any(strcmp(names,'Modality'))
                try
                    S = load(matFile, 'Modality');
                catch ME
                    detail = sprintf('Could not read Modality metadata from MAT-file %s. %s (%s)', matFile, ME.message, ME.identifier);
                    return;
                end
                if isfield(S,'Modality') && isnumeric(S.Modality) && isscalar(S.Modality)
                    modality = double(S.Modality);
                end
            end
            if any(strcmp(names,'ExternalDataInfo'))
                try
                    Sx = load(matFile, 'ExternalDataInfo');
                    externalInfo = Sx.ExternalDataInfo;
                catch ME
                    detail = sprintf('Could not read ExternalDataInfo metadata from MAT-file %s. %s (%s)', matFile, ME.message, ME.identifier);
                    return;
                end
            elseif nargin >= 2 && isstruct(D) && ~isempty(fieldnames(D))
                detail = sprintf('External MAT-file %s does not contain the compatibility information needed for safe reconnection. Re-export the modality or select the original compatible file.', matFile);
                return;
            end
            if nargin >= 2 && isstruct(D) && ~isempty(fieldnames(D))
                [okHash, hashDetail] = NMDataIOExternalStorageTools.validateExternalDataInfo(D, varind, importTarget, externalInfo);
                if ~okHash
                    detail = hashDetail;
                    return;
                end
            end
            valid = true;
            detail = 'MAT-file contains compatible modality data.';
        end

        function info = buildExternalDataInfo(D, varind, importTarget, Y, createdBy)
            % buildExternalDataInfo  Build the persistent descriptor describing an externally stored modality matrix.
            %
            % Consumes D, varind, importTarget, Y; returns info.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 4, Y = []; end
            if nargin < 5 || isempty(createdBy), createdBy = 'NMDataIOExternalStorageTools.externalizeModality'; end
            payload = NMDataIOExternalStorageTools.buildCompatibilityPayload(D, varind, importTarget, Y);
            info = struct();
            info.schemaVersion = 1;
            info.hashVersion = 1;
            info.createdBy = char(string(createdBy));
            info.createdAt = datestr(now, 30);
            info.scope = NMDataIOExternalStorageTools.fieldOr(importTarget, 'scope', 'training');
            info.containerField = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerField', '');
            info.containerIndex = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerIndex', []);
            info.modality = double(varind);
            info.sizeY = size(Y);
            info.classY = class(Y);
            info.compatibilityHash = NMDataIOExternalStorageTools.computeCompatibilityHash(payload);
            info.hashPayloadSummary = NMDataIOExternalStorageTools.payloadSummary(payload);
        end

        function payload = buildCompatibilityPayload(D, varind, importTarget, Y)
            % buildCompatibilityPayload  Assemble the invariant fields that define compatibility between NM metadata and external data.
            %
            % Consumes D, varind, importTarget, Y; returns payload.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 4, Y = []; end
            if nargin < 3 || isempty(importTarget)
                importTarget = struct('scope','training','varind',double(varind));
            end
            payload = struct();
            payload.hashVersion = 1;
            payload.scope = NMDataIOExternalStorageTools.fieldOr(importTarget, 'scope', 'training');
            payload.containerField = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerField', '');
            payload.containerIndex = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerIndex', []);
            payload.modality = double(varind);
            payload.modalitySource = 'unknown';
            payload.modalityType = NaN;
            payload.datasource = 'unknown';
            dd = struct();
            if isstruct(D) && isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind})
                dd = D.datadescriptor{varind};
                if isfield(dd,'source') && ~isempty(dd.source), payload.modalitySource = char(string(dd.source)); end
                if isfield(dd,'type') && ~isempty(dd.type) && isnumeric(dd.type), payload.modalityType = double(dd.type(1)); end
                if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'datasource') && ~isempty(dd.input_settings.datasource)
                    payload.datasource = char(string(dd.input_settings.datasource));
                end
            end
            cases = {};
            if isstruct(D) && isfield(D,'cases') && ~isempty(D.cases)
                cases = NMDataIOExternalStorageTools.asCellstr(D.cases);
            end
            payload.nCases = double(numel(cases));
            payload.caseHash = NMDataIOExternalStorageTools.hashValue(cases);
            if ~isempty(Y) && (isnumeric(Y) || islogical(Y))
                payload.ySize = double(size(Y));
                payload.nCases = double(size(Y,1));
                if ismatrix(Y), payload.nFeatures = double(size(Y,2)); else, szY = size(Y); payload.nFeatures = double(prod(szY(2:end))); end
            else
                payload.ySize = [];
                payload.nFeatures = NMDataIOExternalStorageTools.inferFeatureCount(D, varind);
            end
            featnames = {};
            if isstruct(D) && isfield(D,'featnames') && numel(D.featnames) >= varind && ~isempty(D.featnames{varind})
                featnames = NMDataIOExternalStorageTools.asCellstr(D.featnames{varind});
            end
            payload.featureNameHash = NMDataIOExternalStorageTools.hashValue(featnames);
            badcoords = [];
            if isstruct(D) && isfield(D,'badcoords') && numel(D.badcoords) >= varind && ~isempty(D.badcoords{varind})
                badcoords = D.badcoords{varind};
            end
            payload.badcoordsLength = double(numel(badcoords));
            payload.badcoordsHash = NMDataIOExternalStorageTools.hashValue(badcoords);
            brainmask = [];
            if isstruct(D) && isfield(D,'brainmask') && numel(D.brainmask) >= varind && ~isempty(D.brainmask{varind})
                brainmask = D.brainmask{varind};
            end
            payload.brainmaskHash = NMDataIOExternalStorageTools.hashValue(NMDataIOExternalStorageTools.maskIdentity(brainmask));
            payload.vmHash = NMDataIOExternalStorageTools.hashValue(NMDataIOExternalStorageTools.vmSummary(dd));
            if isfield(dd,'globscale'), payload.globscale = dd.globscale; else, payload.globscale = []; end
            if isfield(dd,'globnorm'), payload.globnorm = dd.globnorm; else, payload.globnorm = []; end
            if isfield(dd,'threshop'), payload.threshop = dd.threshop; else, payload.threshop = []; end
            if isfield(dd,'threshval'), payload.threshval = dd.threshval; else, payload.threshval = []; end
            if isfield(dd,'Yw') && ~isempty(dd.Yw)
                payload.weightingHash = NMDataIOExternalStorageTools.hashValue(struct('size',size(dd.Yw),'class',class(dd.Yw)));
            else
                payload.weightingHash = '';
            end
        end

        function D = storeExternalCompatibilityInfo(D, varind, info)
            % storeExternalCompatibilityInfo  Store external-data compatibility metadata in the modality datadescriptor.
            %
            % Consumes D, varind, info; returns D.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if ~isstruct(D) || ~isfield(D,'datadescriptor') || numel(D.datadescriptor) < varind || ~isstruct(D.datadescriptor{varind})
                return;
            end
            if ~isfield(D.datadescriptor{varind},'input_settings') || ~isstruct(D.datadescriptor{varind}.input_settings)
                D.datadescriptor{varind}.input_settings = struct();
            end
            D.datadescriptor{varind}.input_settings.externalDataInfo = info;
            if ~isfield(D.datadescriptor{varind}.input_settings,'modalityInfo') || ~isstruct(D.datadescriptor{varind}.input_settings.modalityInfo)
                D.datadescriptor{varind}.input_settings.modalityInfo = struct();
            end
            D.datadescriptor{varind}.input_settings.modalityInfo.externalCompatibilityHash = info.compatibilityHash;
            D.datadescriptor{varind}.input_settings.modalityInfo.externalHashVersion = info.hashVersion;
        end

        function [ok, detail] = validateExternalDataInfo(D, varind, importTarget, info)
            % validateExternalDataInfo  Check persisted external-link metadata against the current NM/datadescriptor state.
            %
            % Consumes D, varind, importTarget, info; returns ok, detail.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ok = false;
            detail = '';
            if nargin < 4 || ~isstruct(info) || ~isfield(info,'compatibilityHash') || isempty(info.compatibilityHash)
                detail = 'Externalized data file has no compatibilityHash. Reimport/relink is rejected.';
                return;
            end
            expected = NMDataIOExternalStorageTools.expectedCompatibilityHash(D, varind, importTarget);
            if isempty(expected)
                detail = 'Current NM modality has no expected external compatibility hash and cannot validate this externalized data file.';
                return;
            end
            if ~strcmp(char(info.compatibilityHash), char(expected))
                detail = sprintf('Externalized data hash mismatch for %s. Expected %s, found %s. Reimport/relink rejected.', ...
                    NMDataIOImportTargetTools.targetLabel(importTarget), char(expected), char(info.compatibilityHash));
                return;
            end
            ok = true;
            detail = 'Externalized data compatibility hash matches current NM metadata.';
        end

        function h = expectedCompatibilityHash(D, varind, importTarget)
            % expectedCompatibilityHash  Compute the compatibility hash expected for a given modality and target.
            %
            % Consumes D, varind, importTarget; returns h.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            h = '';
            info = NMDataIOExternalStorageTools.externalCompatibilityInfo(D, varind);
            if isfield(info,'compatibilityHash') && ~isempty(info.compatibilityHash)
                h = char(info.compatibilityHash); return;
            end
            if isstruct(D) && isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind}) && ...
                    isfield(D.datadescriptor{varind},'input_settings') && isstruct(D.datadescriptor{varind}.input_settings)
                is = D.datadescriptor{varind}.input_settings;
                if isfield(is,'modalityInfo') && isstruct(is.modalityInfo) && isfield(is.modalityInfo,'externalCompatibilityHash') && ~isempty(is.modalityInfo.externalCompatibilityHash)
                    h = char(is.modalityInfo.externalCompatibilityHash); return;
                end
            end
            [Y, hasY] = NMDataIOExternalStorageTools.getYCell(D, varind);
            if hasY && (isnumeric(Y) || islogical(Y))
                payload = NMDataIOExternalStorageTools.buildCompatibilityPayload(D, varind, importTarget, Y);
                h = NMDataIOExternalStorageTools.computeCompatibilityHash(payload);
            end
        end

        function h = computeCompatibilityHash(payload)
            % computeCompatibilityHash  Hash the canonical compatibility payload used to protect relinking.
            %
            % Payload -> h.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            txt = jsonencode(orderfields(payload));
            h = NMDataIOExternalStorageTools.hashText(txt);
        end

        function h = hashValue(v)
            % hashValue  Convert a compatibility value into stable hash text.
            %
            % V -> h.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            h = NMDataIOExternalStorageTools.hashText(jsonencode(v));
        end

        function h = hashText(txt)
            % hashText  Compute a compact hash from canonical compatibility text.
            %
            % Txt -> h.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(uint8(txt));
                raw = typecast(md.digest(), 'uint8');
                h = lower(reshape(dec2hex(raw)', 1, []));
            catch ME
                error('NMDataIOExternalStorageTools:hashUnavailable', 'Could not compute SHA-256 compatibility hash. %s (%s)', ME.message, ME.identifier);
            end
        end

        function s = payloadSummary(payload)
            % payloadSummary  Summarize compatibility payload components for diagnostics and relink checks.
            %
            % Payload -> s.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            s = struct();
            s.scope = payload.scope;
            s.containerField = payload.containerField;
            s.containerIndex = payload.containerIndex;
            s.modality = payload.modality;
            s.modalitySource = payload.modalitySource;
            s.modalityType = payload.modalityType;
            s.datasource = payload.datasource;
            s.nCases = payload.nCases;
            s.nFeatures = payload.nFeatures;
            s.badcoordsLength = payload.badcoordsLength;
        end

        function out = maskIdentity(mask)
            % maskIdentity  Summarize compatibility payload components for diagnostics and relink checks.
            %
            % Mask -> out.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            out = struct('class',class(mask),'value','');
            if isempty(mask), return; end
            if ischar(mask) || isstring(mask)
                out.value = char(mask);
            elseif isnumeric(mask) || islogical(mask)
                out.size = size(mask);
                out.hash = NMDataIOExternalStorageTools.hashValue(mask);
            else
                out.value = class(mask);
            end
        end

        function s = vmSummary(dd)
            % vmSummary  Summarize compatibility payload components for diagnostics and relink checks.
            %
            % Dd -> s.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            s = struct();
            if ~isstruct(dd), return; end
            Vm = [];
            if isfield(dd,'Vm') && ~isempty(dd.Vm), Vm = dd.Vm;
            elseif isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'Vm') && ~isempty(dd.input_settings.Vm), Vm = dd.input_settings.Vm; end
            if isstruct(Vm)
                if isfield(Vm,'fname'), s.fname = Vm.fname; end
                if isfield(Vm,'dim'), s.dim = Vm.dim; end
                if isfield(Vm,'dt'), s.dt = Vm.dt; end
                if isfield(Vm,'mat'), s.mat = Vm.mat; end
            end
            if isfield(dd,'Vmvol') && ~isempty(dd.Vmvol)
                s.VmvolSize = size(dd.Vmvol);
                s.VmvolHash = NMDataIOExternalStorageTools.hashValue(size(dd.Vmvol));
            end
        end

        function n = inferFeatureCount(D, varind)
            % inferFeatureCount  Infer feature count from NM/datadescriptor/input payloads.
            %
            % D, varind -> n.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = NaN;
            if isstruct(D) && isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind})
                dd = D.datadescriptor{varind};
                if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'modalityInfo') && isstruct(dd.input_settings.modalityInfo) && ...
                        isfield(dd.input_settings.modalityInfo,'nFeatures') && isnumeric(dd.input_settings.modalityInfo.nFeatures) && isscalar(dd.input_settings.modalityInfo.nFeatures)
                    n = double(dd.input_settings.modalityInfo.nFeatures); return;
                end
            end
            if isstruct(D) && isfield(D,'badcoords') && numel(D.badcoords) >= varind && ~isempty(D.badcoords{varind})
                n = double(numel(D.badcoords{varind}));
            end
        end

        function info = externalCompatibilityInfo(D, varind)
            % externalCompatibilityInfo  Return persisted external-artifact metadata for one resolved container modality.
            info = struct();
            if isstruct(D) && isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && ...
                    isstruct(D.datadescriptor{varind}) && isfield(D.datadescriptor{varind},'input_settings') && ...
                    isstruct(D.datadescriptor{varind}.input_settings) && ...
                    isfield(D.datadescriptor{varind}.input_settings,'externalDataInfo') && ...
                    isstruct(D.datadescriptor{varind}.input_settings.externalDataInfo)
                info = D.datadescriptor{varind}.input_settings.externalDataInfo;
            end
        end

        function ExternalDataInfo = writeExternalArtifact(outPath, D, varind, importTarget, Y, createdBy)
            % writeExternalArtifact  Write the canonical external modality MAT-file representation.
            if nargin < 6 || isempty(createdBy), createdBy = 'NMDataIOExternalStorageTools.externalizeModality'; end
            ExternalDataInfo = NMDataIOExternalStorageTools.buildExternalDataInfo(D, varind, importTarget, Y, createdBy); %#ok<NASGU>
            Modality = double(varind); %#ok<NASGU>
            DataScope = NMDataIOExternalStorageTools.fieldOr(importTarget, 'scope', 'training'); %#ok<NASGU>
            ContainerField = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerField', ''); %#ok<NASGU>
            ContainerIndex = NMDataIOExternalStorageTools.fieldOr(importTarget, 'containerIndex', []); %#ok<NASGU>
            save(outPath, 'Y', 'ExternalDataInfo', 'Modality', 'DataScope', 'ContainerField', 'ContainerIndex', '-v7.3');
        end

        function D = clearExternalCompatibilityInfo(D, varind)
            % clearExternalCompatibilityInfo  Remove stale external-link metadata after explicit fallback to resident storage.
            if ~isstruct(D) || ~isfield(D,'datadescriptor') || numel(D.datadescriptor) < varind || ~isstruct(D.datadescriptor{varind})
                return;
            end
            dd = D.datadescriptor{varind};
            if isfield(dd,'input_settings') && isstruct(dd.input_settings)
                if isfield(dd.input_settings,'externalDataInfo')
                    dd.input_settings = rmfield(dd.input_settings,'externalDataInfo');
                end
                if isfield(dd.input_settings,'modalityInfo') && isstruct(dd.input_settings.modalityInfo)
                    info = dd.input_settings.modalityInfo;
                    drop = intersect(fieldnames(info), {'externalPath','externalBasename','externalFileExists','externalCompatibilityHash','externalHashVersion'});
                    if ~isempty(drop), info = rmfield(info, drop); end
                    dd.input_settings.modalityInfo = info;
                end
            end
            D.datadescriptor{varind} = dd;
        end

        function deleteIfExists(pathName)
            % deleteIfExists  Remove an uncommitted temporary external-storage artifact.
            if ~isempty(pathName) && exist(pathName,'file') == 2
                delete(pathName);
            end
        end

        function name = defaultExternalFilename(NM, varind, importTarget)
            % defaultExternalFilename  Create a deterministic external MAT filename from the NM/modality/import target.
            %
            % Consumes NM, varind, importTarget; returns name.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3 || isempty(importTarget)
                importTarget = struct('scope','training','varind',double(varind));
            end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget, varind);
            tag = 'NM';
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id)
                tag = ['NM' NMDataIOExternalStorageTools.safeToken(NM.id)];
            end
            if NMDataIOImportTargetTools.isOOCV(importTarget)
                tag = sprintf('%s_%s%03d', tag, importTarget.containerField, double(importTarget.containerIndex));
            end
            desc = sprintf('M%03d', double(varind));
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= varind && ...
                    isstruct(NM.datadescriptor{varind}) && isfield(NM.datadescriptor{varind},'desc') && ~isempty(NM.datadescriptor{varind}.desc)
                desc = sprintf('M%03d_%s', double(varind), NMDataIOExternalStorageTools.safeToken(NM.datadescriptor{varind}.desc));
            end
            name = sprintf('%s_%s.mat', tag, desc);
        end

        function tok = safeToken(x)
            % safeToken  Create a filesystem/UI-safe token from user or metadata text.
            %
            % X -> tok.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tok = char(string(x));
            tok = regexprep(tok, '[^A-Za-z0-9_\-]+', '_');
            tok = regexprep(tok, '_+', '_');
            tok = regexprep(tok, '^_|_$', '');
            if isempty(tok), tok = 'NM'; end
        end

        function [Y, hasY] = getYCell(NM, varind)
            % getYCell  Return the in-memory modality matrix cell used before externalizing or relinking data.
            %
            % Consumes NM, varind; returns Y, hasY.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            Y = [];
            hasY = false;
            if ~isstruct(NM) || ~isfield(NM,'Y') || numel(NM.Y) < varind || isempty(NM.Y{varind})
                return;
            end
            Y = NM.Y{varind};
            hasY = true;
        end

        function [D, messages] = getTargetForStorage(NM, importTarget, source)
            % getTargetForStorage  Select the training or OOCV container that owns an external-storage operation.
            %
            % Consumes NM, importTarget, source; returns D, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 3 || isempty(source), source = 'externalStorage'; end
            importTarget = NMDataIOImportTargetTools.normalize(NM, importTarget);
            messages = NMDataIOMessageTools.emptyMessages();
            if NMDataIOImportTargetTools.isOOCV(importTarget)
                [D, targetMessages] = NMDataIOImportTargetTools.getContainer(NM, importTarget);
                messages = [messages; targetMessages];
                [~, wholeLink] = NMDataIOOOCVReadinessTools.storageEntries(D,0);
                if ~isempty(wholeLink)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, source, ...
                        'Individual modality storage operations are unavailable for a whole-container link.', 1, 'red*')];
                end
            else
                D = NM;
                [ok, msg] = NMDataIOModalityMutationTools.validateIndex(NM, importTarget.varind);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('danger', true, source, msg, 1, 'red*')];
                end
            end
        end

        function c = asCellstr(v)
            % asCellstr  Normalize text or cell input into a cell-string style representation.
            %
            % V -> c.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if isempty(v), c = {}; return; end
            if isstring(v), c = cellstr(v(:));
            elseif ischar(v), c = cellstr(v);
            elseif iscell(v)
                c = cell(size(v));
                for i = 1:numel(v), c{i} = char(string(v{i})); end
                c = c(:);
            elseif isnumeric(v) || islogical(v), c = cellstr(string(v(:)));
            else, c = cellstr(string(v(:)));
            end
            c = c(:);
        end

        function v = fieldOr(S, fieldName, defaultValue)
            % fieldOr  Read a struct field with a caller-specific default when the field is absent or empty.
            %
            % Consumes S, fieldName, defaultValue; returns v.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3, defaultValue = []; end
            if isstruct(S) && isfield(S, fieldName) && ~isempty(S.(fieldName))
                v = S.(fieldName);
            else
                v = defaultValue;
            end
        end

        function D = refreshTargetModalityInfo(D, varind)
            % refreshTargetModalityInfo  Recompute modality overview metadata after externalize/relink/reimport operations.
            %
            % D, varind -> D.
            % It protects externalized modality data with compatibility metadata so relinking cannot silently change feature semantics.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if exist('nk_GetNMModalityInfo','file') == 2 || exist('nk_GetNMModalityInfo','builtin') == 5
                info = nk_GetNMModalityInfo(D, varind, struct('ScanInMemory', false, 'MaxScanElements', 1e7));
                info.modalityIndex = double(varind);
                if exist('nk_UpdateNMModalityInfo','file') == 2
                    D = nk_UpdateNMModalityInfo(D, varind, info);
                elseif isfield(D,'datadescriptor') && numel(D.datadescriptor) >= varind && isstruct(D.datadescriptor{varind})
                    if ~isfield(D.datadescriptor{varind}, 'input_settings') || ~isstruct(D.datadescriptor{varind}.input_settings)
                        D.datadescriptor{varind}.input_settings = struct();
                    end
                    D.datadescriptor{varind}.input_settings.modalityInfo = info;
                end
            end
        end
    end
end
