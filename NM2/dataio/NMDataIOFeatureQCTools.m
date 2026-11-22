classdef NMDataIOFeatureQCTools
% NMDataIOFeatureQCTools
% -------------------------------------------------------------------------
% Generic DataIO feature-QC scoring for uncommitted import tasks.
% Computes per-subject outlierness from feature-wise population z-scores
% without mutating NM.  Matrix/table/database imports use the same selected
% feature matrix that the preview path uses.  Imaging imports sample each
% subject image into the selected brainmask space and aggregate z-scores
% over mask voxels in two passes.
% -------------------------------------------------------------------------

    methods (Static)
        function [qcForBrowser, messages] = computeFromMaterializedIO(IO, sourceType, opts, sourcePayload)
            % computeFromMaterializedIO  Compute mandatory QC from an already materialized DataIO payload.
            % This method never resolves or re-reads the scientific source.
            if nargin < 2 || isempty(sourceType), sourceType = 'matrix'; end
            if nargin < 3 || isempty(opts), opts = struct(); end
            if nargin < 4, sourcePayload = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            sourceType = lower(NMDataIOFeatureQCTools.asChar(sourceType));
            progressTask = NMDataIOFeatureQCTools.fieldOr(opts, 'ProgressTask', NMProgressTools.emptyTaskForLocalUse());
            opts.ProgressTask = progressTask;
            switch sourceType
                case 'connectivity'
                    [qc, qcMessages] = NMDataIOFeatureQCTools.computeConnectivityQCFromMaterializedIO(IO, sourcePayload, opts);
                case 'roi'
                    opts.featureSpace = 'roi_field';
                    opts.roiProvenance = NMDataIOFeatureQCTools.fieldOr(sourcePayload, 'roiProvenance', ...
                        NMDataIOFeatureQCTools.fieldOr(IO, 'roiProvenance', struct()));
                    [qc, qcMessages] = NMDataIOFeatureQCTools.computeMatrixQCFromIO(IO, opts);
                    qc.sourceType = 'roi';
                    qc.globalVolumeCorrection = NMDataIOFeatureQCTools.fieldOr(sourcePayload, 'globalVolumeCorrection', ...
                        NMDataIOFeatureQCTools.fieldOr(IO, 'globalVolumeCorrection', struct()));
                case 'surface-list'
                    [qc, qcMessages] = NMDataIOFeatureQCTools.computeSurfaceQCFromIO(IO, opts);
                case {'image-list','image'}
                    [qc, qcMessages] = NMDataIOFeatureQCTools.computeImageQCFromIO(IO, opts);
                otherwise
                    [qc, qcMessages] = NMDataIOFeatureQCTools.computeMatrixQCFromIO(IO, opts);
            end
            messages = [messages; qcMessages];
            audit = NMDataIOFeatureQCTools.fieldOr(IO, 'dataIOAudit', struct());
            if isstruct(audit) && ~isempty(fieldnames(audit)), qc.dataIOAudit = audit; end
            [qc, shiftMessages] = NMDataIOFeatureQCTools.attachOOCVReferenceShift(qc, IO, opts);
            messages = [messages; shiftMessages];
            if NMDataIOMessageTools.hasFatal(messages)
                qcForBrowser = struct();
                return;
            end
            [qcForBrowser, cacheMessages] = NMDataIOFeatureQCTools.prepareQCForBrowser(qc, opts);
            messages = [messages; cacheMessages];
        end

        function [qc, messages] = computeMatrixQCFromIO(IO, opts)
            messages = NMDataIOMessageTools.emptyMessages();
            qc = NMDataIOFeatureQCTools.emptyQC();
            try
                [M, featureNames, caseIds, labels] = NMDataIOImportTools.extractMatrixAxes(IO);
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.materializedMatrix')];
                return;
            end
            if isempty(M) || ~isnumeric(M)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.materializedMatrix', ...
                    'Feature QC requires numeric feature data from the current Preview.', 1, 'red*')];
                return;
            end
            opts.featureNames = NMDataIOFeatureQCTools.asCellstr(featureNames);
            featureSpace = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'featureSpace', 'tabular_matrix'));
            if isempty(featureSpace), featureSpace = 'tabular_matrix'; end
            opts.featureSpace = featureSpace;
            if strcmp(featureSpace, 'roi_field'), opts.roiLabels = labels; end
            [qc, scoreMessages] = NMDataIOFeatureQCTools.computeScoresFromMatrix(double(M), caseIds, 'matrix/table/database', opts);
            messages = [messages; scoreMessages];
            qc.featureNames = NMDataIOFeatureQCTools.asCellstr(featureNames);
            if ~isempty(labels), qc.labels = labels; end
        end

        function [qc, messages] = computeConnectivityQCFromMaterializedIO(IO, connOut, opts)
            % Connectivity QC uses the same post-alignment matrix and Case-ID axis as Preview and Commit.
            messages = NMDataIOMessageTools.emptyMessages();
            qc = NMDataIOFeatureQCTools.emptyQC();
            try
                [Y, edgeNames, caseIds] = NMDataIOImportTools.extractMatrixAxes(IO);
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.connectivity.materialized')];
                return;
            end
            if isempty(Y) || ~isnumeric(Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.connectivity', ...
                    'Connectivity QC requires numeric case-by-edge data from the prepared Preview.', 1, 'red*')];
                return;
            end
            Y = double(Y);
            edgeNames = NMDataIOFeatureQCTools.asCellstr(edgeNames, 'E', size(Y,2));
            caseIds = NMDataIOFeatureQCTools.asCellstr(caseIds, 'S', size(Y,1));
            opts.featureNames = edgeNames;
            opts.featureSpace = 'connectivity_edges';
            [qc, scoreMessages] = NMDataIOFeatureQCTools.computeScoresFromMatrix(Y, caseIds, 'connectivity', opts);
            messages = [messages; scoreMessages];
            qc.featureNames = edgeNames;
            qc.featureSpace = 'connectivity_edges';
            qc.sourceType = 'connectivity';
            prov = NMDataIOFeatureQCTools.fieldOr(connOut, 'provenance', struct());
            nNodes = double(NMDataIOFeatureQCTools.fieldOr(prov, 'nNodes', 0));
            edgeIndex = double(NMDataIOFeatureQCTools.fieldOr(prov, 'edgeIndex', []));
            if nNodes < 1 && ~isempty(edgeIndex), nNodes = max(edgeIndex(:)); end
            cstats = NMDataIOConnectivityTools.edgeMatrixStats(Y, edgeIndex, nNodes, prov);
            rawQC = NMDataIOConnectivityTools.rawConnectivityMatrixQC(struct('provenance',prov), opts);
            qc.connectivity = struct('schemaVersion',1,'nNodes',double(nNodes),'nEdges',double(size(Y,2)), ...
                'nodeLabels',{NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(prov, 'nodeLabels', {}), 'ROI', nNodes)}, ...
                'nodeIDs',double(NMDataIOFeatureQCTools.fieldOr(prov, 'nodeIDs', 1:nNodes)), 'edgeIndex',edgeIndex, ...
                'edgeNames',{edgeNames}, 'matrixType',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(prov, 'matrixType', 'undirected')), ...
                'includeDiagonal',logical(NMDataIOFeatureQCTools.fieldOr(prov, 'includeDiagonal', false)), ...
                'edgeMean',cstats.edgeMean,'edgeSD',cstats.edgeSD,'edgeValidN',cstats.edgeValidN,'edgeMissingRate',cstats.edgeMissingRate, ...
                'rawMatrixQC',rawQC,'edgeSpaceQC',cstats.edgeSpaceQC);
            qc.viewerOverlay = struct('available',true,'cacheToken','','method','connectivity_matrix_qc', ...
                'thresholdDefault',double(qc.outlierZThreshold),'modeDefault','signed', ...
                'metrics',{{'group_mean','group_sd','group_missing_rate','subject_value','subject_z','subject_abs_z','subject_missing'}}, ...
                'featureSpace','connectivity_edges', ...
                'description','Connectivity QC is displayed as ROI-by-ROI matrices built from the imported connectivity edges.');
        end

        function [qc, messages] = computeSurfaceQCFromIO(IO, opts)
            messages = NMDataIOMessageTools.emptyMessages();
            qc = NMDataIOFeatureQCTools.emptyQC();
            if ~isstruct(IO) || ~isfield(IO,'Y') || isempty(IO.Y) || ~isnumeric(IO.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.surface', ...
                    'Surface QC requires surface data from the current Preview.', 1, 'red*')];
                return;
            end
            ids = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO,'ID',{}));
            if isempty(ids), ids = NMDataIOFeatureQCTools.asCellstr({}, 'S', size(IO.Y,1)); end
            mode = lower(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'surfaceImportMode','vertex_template')));
            nativeROI = any(strcmp(mode, {'roi_native','native_roi','roi_collapse_native','roi_collapse'}));
            if nativeROI
                opts.featureSpace = 'roi_field';
                opts.roiProvenance = NMDataIOFeatureQCTools.fieldOr(IO,'roiProvenance',struct());
                if ~isstruct(opts.roiProvenance) || ~isfield(opts.roiProvenance,'ok') || ~logical(opts.roiProvenance.ok)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.surface.roiProvenance', ...
                        'Surface ROI QC requires the validated ROI annotation and display mesh from Preview.', 1, 'red*')];
                    return;
                end
            else
                opts.featureSpace = 'surface_vertex_registered';
            end
            opts.featureNames = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO,'featnames',{}));
            [qc, scoreMessages] = NMDataIOFeatureQCTools.computeScoresFromMatrix(double(IO.Y), ids, 'surface-list', opts);
            messages = [messages; scoreMessages];
            qc.featureNames = opts.featureNames;
            qc.surfaceImportMode = mode;
            qc.featureSpace = opts.featureSpace;
            if ~nativeROI
                qc.spatialMapping = struct('type',opts.featureSpace, ...
                    'surfaceTemplate',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'surfaceTemplate','')), ...
                    'surfaceHemisphere',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'surfaceHemisphere','')), ...
                    'surfaceGeometryFile',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'surfaceGeometryFile','')), ...
                    'surfaceInflatedGeometryFile',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'surfaceInflatedGeometryFile','')), ...
                    'surfaceGeometryContract',NMDataIOFeatureQCTools.fieldOr(IO,'surfaceGeometryContract',struct()));
                tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir',''));
                if ~isempty(tmpDir)
                    opts.cohortZWindow = qc.cohortZWindow;
                    [qc.viewerOverlay, overlayMessages] = NMDataIOFeatureQCTools.exportSurfaceViewerOverlayCache(double(IO.Y), tmpDir, opts);
                    messages = [messages; overlayMessages];
                end
            end
        end

        function [qc, messages] = computeImageQCFromIO(IO, opts)
            messages = NMDataIOMessageTools.emptyMessages();
            qc = NMDataIOFeatureQCTools.emptyQC();
            if ~isstruct(IO) || ~isfield(IO,'Y') || isempty(IO.Y) || ~isnumeric(IO.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.images', ...
                    'Imaging QC requires image data from the current Preview.', 1, 'red*')];
                return;
            end
            M = double(IO.Y);
            ids = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO,'ID',{}));
            if isempty(ids), ids = NMDataIOFeatureQCTools.asCellstr({}, 'S', size(M,1)); end
            opts.featureNames = NMDataIOFeatureQCTools.asCellstr({}, 'Voxel_', size(M,2));
            opts.featureSpace = 'image_voxel';
            [qc, scoreMessages] = NMDataIOFeatureQCTools.computeScoresFromMatrix(M, ids, 'image-list', opts);
            messages = [messages; scoreMessages];
            qc.featureSpace = 'image_voxel';
            qc.nImages = size(M,1);
            qc.maskFile = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'maskFile',''));
            qc.globalVolumeCorrection = struct('mode',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'globalMode','none')), ...
                'globalName',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO,'globalName','GlobalSignal')), ...
                'globalMultiplier',double(NMDataIOFeatureQCTools.fieldOr(IO,'globnorm',1)), ...
                'appliedBeforeQC',logical(isfield(IO,'globscale') && IO.globscale > 1));
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir',''));
            if ~isempty(tmpDir) && ~isempty(qc.maskFile)
                nSubjects = size(M,1);
                nFeatures = size(M,2);
                finiteMask = isfinite(M);
                countVec = sum(finiteMask,1);
                meanVec = nanmeanCompat(M,1);
                sdVec = nanstdCompat(M,0,1);
                m2Vec = (sdVec.^2) .* max(0,countVec-1);
                zeroTol = NMDataIOFeatureQCTools.qcOptionNumber(opts,'ZeroTolerance',0);
                zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts,'OutlierZThreshold',3);
                zeroCount = sum(finiteMask & abs(M) <= zeroTol,1);
                minVec = minWithNaN(M,1);
                maxVec = maxWithNaN(M,1);
                validFeature = countVec >= 2 & isfinite(sdVec) & sdVec > 0;
                outlierCount = zeros(1,nFeatures);
                absZCacheLimit = NMDataIOFeatureQCTools.qcOptionNumber(opts,'ViewerAbsZCacheMaxElements',5e7);
                storeAbsZCache = isfinite(absZCacheLimit) && absZCacheLimit > 0 && double(nSubjects)*double(nFeatures) <= absZCacheLimit;
                if storeAbsZCache, absZMatrix = single(nan(nSubjects,nFeatures)); else, absZMatrix = []; end
                for i=1:nSubjects
                    idx = validFeature & finiteMask(i,:);
                    if any(idx)
                        z = (M(i,idx)-meanVec(idx))./sdVec(idx);
                        outlierCount(idx) = outlierCount(idx) + double(abs(z) >= zThreshold);
                        if storeAbsZCache, absZMatrix(i,idx) = single(abs(z)); end
                    end
                end
                extraCache = struct('zeroCount',zeroCount(:),'minVec',minVec(:),'maxVec',maxVec(:),'outlierCount',outlierCount(:), ...
                    'nSubjects',double(nSubjects),'featureSpace','image_voxel','outlierZThreshold',double(zThreshold), ...
                    'zeroTolerance',double(zeroTol),'dynamicOutlierThresholdAvailable',logical(storeAbsZCache), ...
                    'viewerAbsZCacheMaxElements',double(absZCacheLimit),'cohortZWindow',qc.cohortZWindow);
                if storeAbsZCache, extraCache.absZMatrix = absZMatrix; end
                [qc.viewerOverlay, overlayMessages] = NMDataIOFeatureQCTools.exportViewerOverlayCache(meanVec, m2Vec, countVec, qc.maskFile, tmpDir, extraCache);
                messages = [messages; overlayMessages];
            end
        end

        function NM = normalizePersistedNMQC(NM)
            % Admit saved NM QC artifacts once before consumers access session NM.
            % Training and OOCV descriptors use the same persisted QC schema.
            nOOCV = 0;
            if isfield(NM,'OOCV') % nm2-allow: NM1.4 and NM2 structures without imported application data legitimately omit OOCV.
                nOOCV = numel(NM.OOCV);
            end
            for o = 0:nOOCV
                if o == 0
                    if ~isfield(NM,'datadescriptor'), continue; end % nm2-allow: NMDataIOAPITools.emptyNM and uninitialized startup NM may have no committed descriptors.
                    descriptors = NM.datadescriptor;
                else
                    D = NM.OOCV{o};
                    if ~isfield(D,'datadescriptor'), continue; end % nm2-allow: NMDataIOBrowserModeTools.createOOCVContainer may hold a draft without descriptors.
                    descriptors = D.datadescriptor;
                end
                for v = 1:numel(descriptors)
                    dd = descriptors{v};
                    if ~isstruct(dd) || ~isfield(dd,'QC') || ~isstruct(dd.QC) || ... % nm2-allow: NMDataIOUI.saveInspectionArtifactsToNM writes optional QC only after a saved QC run.
                            ~isfield(dd.QC,'payload') || ~isstruct(dd.QC.payload) % nm2-allow: NMDataIOUI also permits QC report-only descriptors without payload.
                        continue;
                    end
                    descriptors{v}.QC.payload = NMDataIOFeatureQCTools.normalizePersistedQC(dd.QC.payload);
                end
                if o == 0
                    NM.datadescriptor = descriptors;
                else
                    NM.OOCV{o}.datadescriptor = descriptors;
                end
            end
        end

        function qc = normalizePersistedQC(qc)
            % Upgrade numeric QC subject vectors from persisted pre-release NM structures.
            % Only the QC artifact is normalized; case order and scientific values are unchanged.
            names = NMDataIOFeatureQCTools.subjectNumericFields();
            persisted = fieldnames(qc);
            for k = 1:numel(names)
                name = names{k};
                if ~any(strcmp(name,persisted)), continue; end
                value = qc.(name);
                if ~iscell(value), continue; end
                if ~all(cellfun(@(x) (isnumeric(x) || islogical(x)) && isscalar(x),value))
                    error('NMDataIOFeatureQCTools:invalidPersistedQC', ...
                        'Persisted QC metric %s contains non-scalar or non-numeric cells.',name);
                end
                qc.(name) = reshape([value{:}],size(value));
            end
        end

        function fields = subjectNumericFields()
            % Numeric case-axis fields from the fixed NM2 QC producer contract.
            fields = {'rowIndex','score','rmsZ','meanAbsZ','meanZ','sdZ','maxAbsZ', ...
                'nValidFeaturesBySubject','nFiniteFeaturesBySubject','nMissingFeaturesBySubject','missingFeatureRateBySubject', ...
                'nZeroFeaturesBySubject','zeroFeatureRateBySubject','nOutlierFeaturesBySubject','outlierFeatureRateBySubject', ...
                'rowAllNaNFlag','rowConstantFlag'};
        end

        function [qcForBrowser, messages] = prepareQCForBrowser(qc, opts)
            % prepareQCForBrowser  Keep authoritative QC values numeric and browser-bounded.
            %
            % Subject-level QC vectors remain in their canonical top-level fields.
            % The central JSON bridge explicitly permits those bounded vectors;
            % subjectStats therefore carries summary metadata only and does not
            % duplicate the same case-level arrays as scalar-cell payloads.
            %
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 2 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            qcForBrowser = qc;
            if ~isstruct(qcForBrowser) || isempty(fieldnames(qcForBrowser))
                return;
            end
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'tmpDir', ''));
            maxSubjects = round(NMDataIOFeatureQCTools.qcOptionNumber(opts, 'MaxSubjectVectorsInResponse', 5000));
            if ~isfinite(maxSubjects) || maxSubjects < 0, maxSubjects = 5000; end
            nSubjects = double(NMDataIOFeatureQCTools.fieldOr(qcForBrowser, 'nSubjects', 0));
            subjectVectorsComplete = numel(NMDataIOFeatureQCTools.fieldOr(qcForBrowser,'rowIndex',[])) >= nSubjects && ...
                numel(NMDataIOFeatureQCTools.fieldOr(qcForBrowser,'caseIds',{})) >= nSubjects && ...
                numel(NMDataIOFeatureQCTools.fieldOr(qcForBrowser,'rmsZ',[])) >= nSubjects;
            fullCacheAvailable = false;
            if ~isempty(tmpDir) && subjectVectorsComplete
                try
                    cacheDir = fullfile(tmpDir, 'dataio_qc_cache');
                    if exist(cacheDir, 'dir') ~= 7
                        [ok,msg] = mkdir(cacheDir);
                        if ~ok, error('NMDataIOFeatureQCTools:qcCacheMkdir', 'Could not create the temporary folder for full QC results %s: %s', cacheDir, msg); end
                    end
                    token = NMDataIOFeatureQCTools.safeCacheToken('qc');
                    cacheFile = fullfile(cacheDir, [token '.mat']);
                    qcFull = qc; %#ok<NASGU>
                    save(cacheFile, 'qcFull', '-v7');
                    qcForBrowser.qcCacheToken = token;
                    qcForBrowser.qcCacheKind = 'matlab_tmp';
                    fullCacheAvailable = true;
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.cache', ...
                        'Full feature-QC results are available for report export and QC viewers.', 0, 'green*')];
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.cache', ...
                        sprintf('Could not save the full feature-QC results for report export: %s', ME.message), 2, 'orange')];
                end
            end
            if ~isfield(qcForBrowser,'subjectStats') || ~isstruct(qcForBrowser.subjectStats)
                qcForBrowser.subjectStats = struct();
            end
            qcForBrowser.subjectStats.maxSubjectsReturned = double(maxSubjects);
            if nSubjects <= maxSubjects
                qcForBrowser.subjectStats.fullReturned = logical(subjectVectorsComplete);
                if ~isfield(qcForBrowser.subjectStats,'omittedSubjectVectorsReason')
                    qcForBrowser.subjectStats.omittedSubjectVectorsReason = '';
                end
            elseif subjectVectorsComplete && fullCacheAvailable
                ids = NMDataIOFeatureQCTools.asCellstr(qcForBrowser.caseIds, 'S', nSubjects);
                rows = double(qcForBrowser.rowIndex(:)');
                rmsZ = double(qcForBrowser.rmsZ(:)');
                missingRate = double(qcForBrowser.missingFeatureRateBySubject(:)');
                outlierRate = double(qcForBrowser.outlierFeatureRateBySubject(:)');
                rankValues = rmsZ; rankValues(~isfinite(rankValues)) = -Inf;
                [~, order] = sort(rankValues, 'descend');
                order = order(1:min(20,numel(order))); order = order(isfinite(rmsZ(order)));
                topCases = repmat(struct('rowIndex',NaN,'caseId','','rmsZ',NaN,'missingFeatureRate',NaN,'outlierFeatureRate',NaN), numel(order), 1);
                for oi = 1:numel(order)
                    k = order(oi);
                    topCases(oi) = struct('rowIndex',rows(k),'caseId',ids{k},'rmsZ',rmsZ(k), ...
                        'missingFeatureRate',missingRate(k),'outlierFeatureRate',outlierRate(k));
                end
                qcForBrowser.subjectStats.topCases = topCases;
                qcForBrowser.subjectStats.omittedSubjectVectorsReason = sprintf( ...
                    ['Per-case QC vectors for %g cases were omitted from the browser payload because the configured limit is %g. ', ...
                     'The complete vectors remain available through the retained QC cache and QC report.'], nSubjects, maxSubjects);
                subjectFields = [{'caseIds'}, NMDataIOFeatureQCTools.subjectNumericFields()];
                for fi = 1:numel(subjectFields)
                    if isfield(qcForBrowser,subjectFields{fi}), qcForBrowser.(subjectFields{fi}) = []; end
                end
                qcForBrowser.subjectStats.fullReturned = false;
            elseif subjectVectorsComplete
                qcForBrowser.subjectStats.fullReturned = true;
                qcForBrowser.subjectStats.omittedSubjectVectorsReason = '';
            else
                qcForBrowser.subjectStats.fullReturned = false;
                if ~isfield(qcForBrowser.subjectStats,'omittedSubjectVectorsReason') || isempty(qcForBrowser.subjectStats.omittedSubjectVectorsReason)
                    qcForBrowser.subjectStats.omittedSubjectVectorsReason = ...
                        'Per-case QC vectors are not present in this persisted browser payload.';
                end
            end
        end

        function [qcOut, messages] = persistViewerOverlayCache(qcIn, tmpDir, persistRoot, opts)
            % persistViewerOverlayCache  Persist heavy QC overlay arrays outside transient UI state and attach cache metadata.
            %
            % Consumes qcIn, tmpDir, persistRoot, opts; returns qcOut, messages.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.ContainerIndex: configures optional container index behavior for this call.
            % opts.Force: configures optional force behavior for this call.
            % opts.ModalityIndex: selects one modality or the literal all when an export/import action can span modalities.
            % opts.Scope: configures optional scope behavior for this call.
            messages = NMDataIOMessageTools.emptyMessages();
            qcOut = qcIn;
            if nargin < 1 || ~isstruct(qcOut) || ~isfield(qcOut,'viewerOverlay') || ~isstruct(qcOut.viewerOverlay)
                return;
            end
            if nargin < 2, tmpDir = ''; end
            explicitRoot = nargin >= 3 && ~isempty(persistRoot);
            if ~explicitRoot
                try
                    persistRoot = NMUISessionTools.privateProcessTempRoot('qc_viewer');
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.privateRoot', ...
                        sprintf('Could not allocate temporary spatial QC viewer storage: %s', ME.message), 2, 'orange')];
                    qcOut.viewerOverlay.cacheStatus = 'unresolved';
                    return;
                end
            end
            if nargin < 4 || isempty(opts), opts = struct(); end
            persistRoot = NMDataIOFeatureQCTools.asChar(persistRoot);
            requestedRoot = persistRoot;
            modalityIndex = NaN;
            if isstruct(opts) && isfield(opts,'ModalityIndex') && ~isempty(opts.ModalityIndex)
                modalityIndex = double(opts.ModalityIndex);
                if ~isempty(modalityIndex), modalityIndex = modalityIndex(1); end
            end
            scopeLabel = '';
            if isstruct(opts) && isfield(opts,'Scope') && ~isempty(opts.Scope)
                scopeLabel = lower(strtrim(NMDataIOFeatureQCTools.asChar(opts.Scope)));
            end
            containerIndex = NaN;
            if isstruct(opts) && isfield(opts,'ContainerIndex') && ~isempty(opts.ContainerIndex)
                rawContainerIndex = double(opts.ContainerIndex);
                if ~isempty(rawContainerIndex), containerIndex = rawContainerIndex(1); end
            end
            if strcmp(scopeLabel,'oocv') && isfinite(containerIndex) && containerIndex >= 1
                containerIndex = round(containerIndex);
                persistRoot = fullfile(persistRoot, sprintf('oocv_%03d', containerIndex));
            end
            if isfinite(modalityIndex) && modalityIndex >= 1
                modalityIndex = round(modalityIndex);
                persistRoot = fullfile(persistRoot, sprintf('modality_%03d', modalityIndex));
            end
            force = false;
            if isstruct(opts) && isfield(opts,'Force') && ~isempty(opts.Force), force = logical(opts.Force); end
            token = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcOut.viewerOverlay,'cacheToken',''));
            if isempty(token), return; end
            if isempty(regexp(token, '^[A-Za-z0-9_\-]+$', 'once'))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.token', ...
                    'The QC viewer data could not be saved because their reference is invalid. Run Preview again if spatial QC viewing is needed.', 2, 'orange')];
                return;
            end

            dst = fullfile(persistRoot, [token '.mat']);
            existing = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcOut.viewerOverlay,'persistedCacheFile',''));
            if ~force && exist(existing,'file') == 2
                if ~explicitRoot && strcmp(qcOut.viewerOverlay.cacheDurability, 'user_selected')
                    return; % An automatic Preview must not replace an exported sidecar.
                end
                if strcmp(NMDataIOFeatureQCTools.normalizePath(fileparts(existing)), NMDataIOFeatureQCTools.normalizePath(persistRoot))
                    qcOut = NMDataIOFeatureQCTools.attachViewerOverlaySidecarMetadata(qcOut, existing, requestedRoot, persistRoot, token, modalityIndex, explicitRoot, scopeLabel, containerIndex);
                    return;
                end
            end

            tmpDir = NMDataIOFeatureQCTools.asChar(tmpDir);
            candidates = repmat({''}, 3, 1);
            cpos = 0;
            if ~isempty(tmpDir)
                [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
                if isempty(assetErr)
                    cpos = cpos + 1;
                    candidates{cpos} = fullfile(assetDir, [token '.mat']);
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.assetDir', assetErr, 2, 'orange')];
                end
            end
            rehydrated = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcOut.viewerOverlay,'rehydratedCacheFile',''));
            if ~isempty(rehydrated), cpos = cpos + 1; candidates{cpos} = rehydrated; end
            if ~isempty(existing), cpos = cpos + 1; candidates{cpos} = existing; end
            src = '';
            for ci = 1:cpos
                cand = NMDataIOFeatureQCTools.asChar(candidates{ci});
                if exist(cand,'file') == 2
                    src = cand;
                    break;
                end
            end
            if isempty(src)
                if explicitRoot
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.viewerCache.missing', ...
                        'Cannot export QC viewer data: the source cache is missing. Run Preview again.', 1, 'red*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.missing', ...
                        'The QC viewer data are no longer available. Run Preview again before exporting spatial QC data.', 2, 'orange')];
                end
                qcOut.viewerOverlay.cacheStatus = 'missing';
                return;
            end
            try
                if exist(persistRoot,'dir') ~= 7
                    [ok,msg] = mkdir(persistRoot);
                    if ~ok
                        error('NMDataIOFeatureQCTools:viewerCacheMkdir', 'Cannot create QC viewer folder %s: %s', persistRoot, msg);
                    end
                end
                if ~strcmp(NMDataIOFeatureQCTools.normalizePath(src), NMDataIOFeatureQCTools.normalizePath(dst))
                    copyfile(src, dst, 'f');
                end
                NMDataIOFeatureQCTools.appendViewerCacheCaseIds(dst, qcOut);
                qcOut = NMDataIOFeatureQCTools.attachViewerOverlaySidecarMetadata(qcOut, dst, requestedRoot, persistRoot, token, modalityIndex, explicitRoot, scopeLabel, containerIndex);
                NMDataIOFeatureQCTools.writeViewerOverlayManifest(qcOut.viewerOverlay, persistRoot, token);
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.viewerCache.persist', ...
                    sprintf('Saved QC viewer data: %s', dst), 0, 'green*')];
            catch ME
                if explicitRoot
                    messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.viewerCache.export')];
                else
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.persist', ...
                        sprintf('The optional spatial QC viewer cache could not be saved (%s: %s). Numerical QC is unaffected.', ME.identifier, ME.message), 2, 'orange')];
                end
                qcOut.viewerOverlay.cacheStatus = 'unresolved';
            end
        end

        function appendViewerCacheCaseIds(cacheFile, qcPayload)
            % appendViewerCacheCaseIds  Append case IDs to a persisted QC viewer cache file for later rehydration/reporting.
            %
            % CacheFile, qcPayload -> no explicit output.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            cacheFile = NMDataIOFeatureQCTools.asChar(cacheFile);
            if isempty(cacheFile) || exist(cacheFile,'file') ~= 2 || ~isstruct(qcPayload), return; end
            ids = NMDataIOFeatureQCTools.qcCaseIds(qcPayload);
            if isempty(ids), return; end
            cases = ids(:); %#ok<NASGU>
            caseIds = ids(:); %#ok<NASGU>
            save(cacheFile, 'cases', 'caseIds', '-append');
        end

        function ids = qcCaseIds(qcPayload)
            % qcCaseIds  Derive case IDs associated with a QC payload for viewer cache sidecars.
            %
            % QcPayload -> ids.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ids = {};
            if ~isstruct(qcPayload), return; end
            raw = [];
            if isfield(qcPayload,'caseIds') && ~isempty(qcPayload.caseIds)
                raw = qcPayload.caseIds;
            elseif isfield(qcPayload,'subjectStats') && isstruct(qcPayload.subjectStats) && ...
                    isfield(qcPayload.subjectStats,'caseIds') && ~isempty(qcPayload.subjectStats.caseIds)
                raw = qcPayload.subjectStats.caseIds;
            end
            if isempty(raw), return; end
            if iscell(raw)
                ids = cellfun(@(x) char(string(x)), raw(:), 'UniformOutput', false);
            elseif isstring(raw)
                ids = cellstr(raw(:));
            elseif ischar(raw)
                ids = cellstr(raw);
            else
                vals = raw(:);
                ids = cell(numel(vals),1);
                for ii = 1:numel(vals), ids{ii} = char(string(vals(ii))); end
            end
        end

        function qcOut = attachViewerOverlaySidecarMetadata(qcOut, cacheFile, requestedRoot, persistRoot, token, modalityIndex, explicitRoot, scopeLabel, containerIndex)
            % attachViewerOverlaySidecarMetadata  Attach cache paths, scope, and persistence provenance to a viewer-overlay QC payload.
            %
            % Consumes qcOut, cacheFile, requestedRoot, persistRoot, token, modalityIndex, explicitRoot, scopeLabel, containerIndex; returns qcOut.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Cache contents are an acceleration/rehydration artifact, not a new source of truth.
            cacheFile = NMDataIOFeatureQCTools.asChar(cacheFile);
            requestedRoot = NMDataIOFeatureQCTools.asChar(requestedRoot);
            persistRoot = NMDataIOFeatureQCTools.asChar(persistRoot);
            qcOut.viewerOverlay.persistedCacheFile = cacheFile;
            qcOut.viewerOverlay.persistedCacheToken = token;
            qcOut.viewerOverlay.persistedCacheSavedAt = datestr(now,30);
            qcOut.viewerOverlay.sidecarAbsPath = cacheFile;
            qcOut.viewerOverlay.sidecarRoot = requestedRoot;
            qcOut.viewerOverlay.sidecarCacheDir = persistRoot;
            if nargin < 8, scopeLabel = ''; end
            if nargin < 9, containerIndex = NaN; end
            scopeLabel = lower(strtrim(NMDataIOFeatureQCTools.asChar(scopeLabel)));
            qcOut.viewerOverlay.sidecarScope = scopeLabel;
            qcOut.viewerOverlay.sidecarContainerIndex = double(containerIndex);
            qcOut.viewerOverlay.sidecarModalityIndex = double(modalityIndex);
            relParts = {};
            if strcmp(scopeLabel,'oocv') && isfinite(containerIndex) && containerIndex >= 1
                relParts{end+1} = sprintf('oocv_%03d', round(containerIndex));
            end
            if isfinite(modalityIndex) && modalityIndex >= 1
                relParts{end+1} = sprintf('modality_%03d', round(modalityIndex));
            end
            if isempty(relParts)
                qcOut.viewerOverlay.sidecarRelPath = [token '.mat'];
            else
                qcOut.viewerOverlay.sidecarRelPath = fullfile(relParts{:}, [token '.mat']);
            end
            qcOut.viewerOverlay.cacheDurability = NMDataIOFeatureQCTools.ternaryChar(explicitRoot, 'user_selected', 'session_temp');
            qcOut.viewerOverlay.cacheStatus = 'available';
            qcOut.viewerOverlay.persistedCacheKind = NMDataIOFeatureQCTools.ternaryChar(explicitRoot, 'qc_sidecar', 'tempdir_cache');
        end

        function writeViewerOverlayManifest(viewerOverlay, persistRoot, token)
            % writeViewerOverlayManifest  Write a JSON manifest describing persisted QC viewer overlay cache files.
            %
            % ViewerOverlay, persistRoot, token -> no explicit output.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            if nargin < 1 || ~isstruct(viewerOverlay), return; end
            if nargin < 2 || isempty(persistRoot) || exist(persistRoot,'dir') ~= 7, return; end
            if nargin < 3 || isempty(token), token = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'persistedCacheToken','')); end
            manifest = struct();
            manifest.schemaVersion = 1;
            manifest.createdAt = datestr(now,30);
            manifest.cacheToken = token;
            manifest.cacheFile = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'persistedCacheFile',''));
            manifest.featureSpace = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'featureSpace',''));
            manifest.method = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'method',''));
            manifest.cacheDurability = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'cacheDurability',''));
            manifest.cacheStatus = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'cacheStatus',''));
            manifest.sidecarRoot = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'sidecarRoot',''));
            manifest.sidecarRelPath = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'sidecarRelPath',''));
            manifest.sidecarModalityIndex = double(NMDataIOFeatureQCTools.fieldOr(viewerOverlay,'sidecarModalityIndex', NaN));
            try
                save(fullfile(persistRoot, 'manifest.mat'), 'manifest', '-v7');
            catch
                % Sidecar manifests are auxiliary; the caller already reports
                % cache-copy failures through the message strip.
            end
        end

        function p = normalizePath(p)
            % normalizePath  Normalize caller input into the canonical representation used by the DataIO flow.
            %
            % P -> p.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            p = NMDataIOFeatureQCTools.asChar(p);
            if isempty(p), return; end
            try
                p = char(java.io.File(p).getCanonicalPath());
            catch
                p = char(string(p));
            end
            if ispc, p = lower(p); end
        end

        function txt = ternaryChar(condition, trueText, falseText)
            % ternaryChar  Select one of two QC manifest strings without changing numeric QC payloads.
            %
            % Consumes condition, trueText, falseText; returns txt.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if condition
                txt = trueText;
            else
                txt = falseText;
            end
        end

        function [qcOut, messages] = rehydrateViewerOverlayCache(qcIn, tmpDir)
            % rehydrateViewerOverlayCache  Reload persisted QC viewer overlay arrays when browser state is restored.
            %
            % Consumes qcIn, tmpDir; returns qcOut, messages.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            messages = NMDataIOMessageTools.emptyMessages();
            qcOut = qcIn;
            if nargin < 1 || ~isstruct(qcOut) || ~isfield(qcOut,'viewerOverlay') || ~isstruct(qcOut.viewerOverlay)
                return;
            end
            if nargin < 2 || isempty(tmpDir), return; end
            token = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcOut.viewerOverlay,'cacheToken',''));
            persistedFile = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcOut.viewerOverlay,'persistedCacheFile',''));
            if isempty(token), return; end
            if isempty(persistedFile)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.notPersisted', ...
                    'Saved QC results do not contain the spatial viewer data. Run Preview again before opening group or case spatial QC maps.', 2, 'orange')];
                return;
            end
            if isempty(regexp(token, '^[A-Za-z0-9_\-]+$', 'once'))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.token', ...
                    'Saved QC viewer data could not be restored. Run Preview again before opening spatial QC maps.', 2, 'orange')];
                return;
            end
            if exist(persistedFile,'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.persistedMissing', ...
                    sprintf('Saved QC viewer data file is missing: %s', persistedFile), 2, 'orange')];
                return;
            end
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.assetDir', assetErr, 2, 'orange')];
                return;
            end
            if exist(assetDir,'dir') ~= 7
                [ok,msg] = mkdir(assetDir);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.mkdir', ...
                        sprintf('Could not create viewer asset directory %s: %s', assetDir, msg), 2, 'orange')];
                    return;
                end
            end
            targetFile = fullfile(assetDir, [token '.mat']);
            if exist(targetFile,'file') == 2
                qcOut.viewerOverlay.rehydratedCacheFile = targetFile;
                return;
            end
            try
                copyfile(persistedFile, targetFile, 'f');
                qcOut.viewerOverlay.rehydratedCacheFile = targetFile;
                qcOut.viewerOverlay.rehydratedCacheAt = datestr(now,30);
            catch ME
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.viewerCache.rehydrate', ...
                    sprintf('Spatial QC viewer data could not be restored (%s: %s). Run Preview again if needed.', ME.identifier, ME.message), 2, 'orange')];
            end
        end

        function [qc, messages] = loadCachedQCForReport(qcPayload, tmpDir)
            % loadCachedQCForReport  Load cached QC arrays needed by the export/report path.
            %
            % Consumes qcPayload, tmpDir; returns qc, messages.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            messages = NMDataIOMessageTools.emptyMessages();
            qc = qcPayload;
            if nargin < 2 || isempty(tmpDir) || ~isstruct(qcPayload)
                return;
            end
            token = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(qcPayload, 'qcCacheToken', ''));
            if isempty(token), return; end
            if isempty(regexp(token, '^[A-Za-z0-9_\-]+$', 'once'))
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.cacheToken', ...
                    'The full QC results for the report are unavailable; using the compact QC summary shown in the browser.', 2, 'orange')];
                return;
            end
            cacheFile = fullfile(tmpDir, 'dataio_qc_cache', [token '.mat']);
            if exist(cacheFile, 'file') ~= 2
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.cacheMissing', ...
                    'The full QC results were not found; using the compact QC summary shown in the browser.', 2, 'orange')];
                return;
            end
            try
                S = load(cacheFile, 'qcFull');
                if isfield(S, 'qcFull') && isstruct(S.qcFull)
                    qc = S.qcFull;
                    if ~isfield(qc, 'qcCacheToken'), qc.qcCacheToken = token; end
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.cacheLoad', ...
                        'Loaded the full feature-QC results for report export.', 0, 'green*')];
                end
            catch ME
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.cacheLoad', ...
                    sprintf('Could not load the full feature-QC results; using the compact browser summary: %s', ME.message), 2, 'orange')];
            end
        end
    end

    methods (Static)
        function spec = subjectMetricHistogramSpec(values)
            % subjectMetricHistogramSpec  Build the canonical subject-level QC histogram specification used by browser diagnostics and QC reports.
            finite = double(values(:));
            finite = finite(isfinite(finite));
            spec = struct('available',false,'edges',[],'counts',[],'outlierThreshold',NaN,'outlierFraction',0.10);
            if isempty(finite), return; end
            nBins = min(20, max(5, ceil(sqrt(numel(finite)))));
            lo = min(finite); hi = max(finite);
            if hi <= lo
                lo = lo - 0.5; hi = hi + 0.5;
            end
            edges = linspace(lo, hi, nBins + 1);
            counts = histcounts(finite, edges);
            sorted = sort(finite, 'descend');
            k = max(1, ceil(numel(finite) * spec.outlierFraction));
            spec.available = true;
            spec.edges = double(edges(:)');
            spec.counts = double(counts(:)');
            spec.outlierThreshold = double(sorted(min(k, numel(sorted))));
        end

        function out = prepareMatrixFeatureProfile(NM, state, rowIndex, opts)
            % prepareMatrixFeatureProfile  Prepare one tabular non-imaging case profile from retained Preview data.
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(rowIndex), rowIndex = 1; end
            if nargin < 4 || isempty(opts), opts = struct(); end
            out = NMDataIOFeatureQCTools.emptyFeatureProfile();
            messages = NMDataIOMessageTools.emptyMessages();
            try
                identityState = NMDataIOImportTools.materializationIdentityState(NM,state);
                [cacheHit, entry] = NMDataIOMaterializationCache.get('matrix', identityState, '', NMDataIOUI.sessionKey(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir','')));
                if ~cacheHit || ~isstruct(entry) || ~isfield(entry,'IO') || ~isstruct(entry.IO)
                    messages = NMDataIOMessageTools.make('danger', true, 'featureQC.profile.matrix', ...
                        'Run Preview before opening tabular feature QC.', 1, 'red*');
                    out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
                    return;
                end
                [M, featureNames, caseIds, labels] = NMDataIOImportTools.extractMatrixAxes(entry.IO);
                out = NMDataIOFeatureQCTools.prepareFeatureProfileFromAxes(M, featureNames, caseIds, labels, rowIndex, opts, messages, 'featureQC.profile.matrix');
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'NMDataIOFeatureQCTools.prepareMatrixFeatureProfile')];
                out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
            end
        end

        function out = prepareROIFeatureProfile(cacheToken, rowIndex, opts)
            % prepareROIFeatureProfile  Prepare one ROI subject profile from the resident QC materialization.
            %
            % Purpose:
            %   Serve interactive subject switching after ROI QC has already been computed. The
            %   method consumes the immutable ROI-QC materialization produced by computeROIQC; it
            %   never re-enters raw ROI import, CAT12 parsing, atlas validation, or annotation IO.
            %
            % Syntax:
            %   out = NMDataIOFeatureQCTools.prepareROIFeatureProfile(cacheToken, rowIndex, opts)
            %
            % Inputs:
            %   cacheToken     Token returned in qc.viewerOverlay.cacheToken.
            %   rowIndex       One-based subject row in the materialized ROI matrix.
            %   opts.tmpDir    Browser-session temporary directory containing viewer assets.
            %   opts.maxPoints Maximum plotted ROI points before deterministic downsampling.
            %
            % Outputs:
            %   out            Standard feature-profile payload in canonical ROI-column order.
            %
            % Authority and flow:
            %   Raw ROI source -> prepareROIImportState -> computeROIQC -> ROI-QC materialization
            %   -> this method. Interactive consumers must not traverse this flow upstream.
            %
            % Invariants:
            %   ROI values, names and case IDs retain the canonical order established at import.
            %   Subject switching cannot read source files or alter ROI provenance.
            %
            % Materialization and performance:
            %   First use loads one already materialized ROI-QC MAT payload; subsequent switches
            %   reuse it in memory. No work scales with atlas voxel count.
            %
            % Failure semantics:
            %   Missing QC materialization is a blocking QC-state error. There is no fallback to
            %   raw ROI import or generic matrix source resolution.
            %
            % Side effects:
            %   Retains only the most recently used ROI-QC materialization in process memory.
            if nargin < 3 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            cacheToken = NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'tmpDir', ''));
            if isempty(cacheToken) || isempty(tmpDir)
                messages = NMDataIOMessageTools.make('danger', true, 'featureQC.profile.roi', ...
                    'Run Preview and compute ROI QC before opening an ROI feature profile.', 1, 'red*');
                out = NMDataIOFeatureQCTools.finishProfileOut(NMDataIOFeatureQCTools.emptyFeatureProfile(), messages);
                return;
            end
            [resident, residentMessage] = NMDataIOFeatureQCTools.residentROIViewerMaterialization(cacheToken, tmpDir);
            if ~isempty(residentMessage)
                messages = NMDataIOMessageTools.make('danger', true, 'featureQC.profile.roi', residentMessage, 1, 'red*');
                out = NMDataIOFeatureQCTools.finishProfileOut(NMDataIOFeatureQCTools.emptyFeatureProfile(), messages);
                return;
            end
            if ~isfield(resident, 'featureSpace') || ~strcmp(resident.featureSpace, 'roi_field')
                messages = NMDataIOMessageTools.make('danger', true, 'featureQC.profile.roi', ...
                    'The current QC data are not ROI data.', 1, 'red*');
                out = NMDataIOFeatureQCTools.finishProfileOut(NMDataIOFeatureQCTools.emptyFeatureProfile(), messages);
                return;
            end
            out = NMDataIOFeatureQCTools.prepareFeatureProfileFromAxes( ...
                resident.roiValues, resident.featureNames, resident.caseIds, resident.labels, ...
                rowIndex, opts, messages, 'featureQC.profile.roi');
        end

        function out = prepareROISubjectSpatialPayload(cacheToken, rowIndex, opts)
            % prepareROISubjectSpatialPayload  Prepare one raw ROI subject for the shared spatial viewer.
            %
            % Purpose:
            %   Serve the ordinary DataIO View action before or after QC from the resident ROI viewer
            %   materialization produced by Preview. The raw canonical ROI vector is expanded through
            %   the same atlas/annotation authority later used for QC overlays.
            %
            % Inputs/outputs:
            %   cacheToken identifies one resident ROI viewer materialization; rowIndex is one-based.
            %   opts.tmpDir and opts.sliceIndex follow the existing DataIO viewer contract. Output is
            %   the same volume/surface payload returned by prepareROIViewerPayload.
            %
            % Authority and flow:
            %   Preview materialization -> resident roiValues(row,:) -> prepareROIViewerPayload.
            %   No raw ROI source or scientific provenance is reconstructed here.
            %
            % Materialization and performance:
            %   Interactive-safe. Loads/reuses one session-local MAT materialization, performs O(P)
            %   row extraction plus exact atlas/annotation expansion, and writes browser binary assets.
            %   It does not parse CAT12/XML, load source ROI tables, or reopen atlas/annotation/mesh files.
            %
            % Failure semantics:
            %   Missing cache, invalid row identity, or spatial inconsistency fail explicitly; there is
            %   no fallback to prepareROIImportState or generic matrix inspection.
            if nargin < 3 || isempty(opts), opts=struct(); end
            cacheToken=NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir=NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir',''));
            [resident,msg]=NMDataIOFeatureQCTools.residentROIViewerMaterialization(cacheToken,tmpDir);
            if ~isempty(msg)
                out=struct('ok',false,'message',msg); return;
            end
            if ~isfield(resident,'featureSpace') || ~strcmp(resident.featureSpace,'roi_field') || ...
                    ~isfield(resident,'roiValues') || ~isnumeric(resident.roiValues)
                out=struct('ok',false,'message','The current Preview does not contain complete case-by-ROI data for spatial viewing.'); return;
            end
            rowIndex=round(double(rowIndex));
            if ~isscalar(rowIndex) || ~isfinite(rowIndex) || rowIndex<1 || rowIndex>size(resident.roiValues,1)
                out=struct('ok',false,'message',sprintf('ROI case %g is outside the available range 1..%g.',rowIndex,size(resident.roiValues,1))); return;
            end
            opts.metricKey='subject_raw'; opts.metricLabel='Subject ROI value'; opts.overlayKind='sequential';
            out=NMDataIOFeatureQCTools.prepareROIViewerPayload(cacheToken,double(resident.roiValues(rowIndex,:)),opts);
            if ~isstruct(out), out=struct('ok',false,'message','ROI subject data could not be prepared for viewing.'); return; end
            out.rowIndex=double(rowIndex);
            ids=NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(resident,'caseIds',{}));
            if numel(ids)>=rowIndex, out.caseId=ids{rowIndex}; else, out.caseId=''; end
            labels=NMDataIOFeatureQCTools.fieldOr(resident,'labels',[]);
            if isnumeric(labels) || islogical(labels)
                if size(labels,1)>=rowIndex, out.label=labels(rowIndex,:); else, out.label=[]; end
            elseif iscell(labels) && numel(labels)>=rowIndex
                out.label=labels{rowIndex};
            else
                out.label=[];
            end
        end

        function out = prepareROIViewerPayload(cacheToken, roiPayload, opts)
            % prepareROIViewerPayload  Project one canonical ROI payload through retained spatial provenance.
            %
            % Purpose:
            %   Transfer ROI-level values through the retained canonical spatial coordinate:
            %   static volumetric lookup plus compact ROI vector, or surface mesh overlay.
            %
            % Syntax:
            %   out = NMDataIOFeatureQCTools.prepareROIViewerPayload(cacheToken, roiPayload, opts)
            %
            % Inputs:
            %   cacheToken       Token of the resident ROI viewer materialization.
            %   roiPayload       Subject-level value per canonical ROI column when metricKey=subject_z;
            %                    empty for group-level metrics, which are resolved from resident QC moments/counts.
            %   opts.tmpDir      Browser-session temporary directory.
            %   opts.metricKey   subject_raw, subject_z, or one established group feature metric (missing rate,
            %                    mean, standard deviation, zero rate, or outlier rate).
            %   opts.metricLabel User-facing metric label.
            %   opts.overlayKind Display semantics (subject_z, sequential, rate).
            %   opts.zThreshold  Display threshold for signed z-score overlays.
            %   opts.sliceIndex  Optional initial axial slice for volumetric provenance.
            %
            % Outputs:
            %   out.representationFamily is volume or surface. Volume output carries an immutable
            %   ROI lookup asset and ROI-column overlay values; surface output uses mesh and overlay. Both retain canonical
            %   ROI IDs/names and report the exact number of mapped parcels.
            %
            % Authority and flow:
            %   Canonical ROI provenance -> resident spatial materialization -> one retained
            %   exact membership lookup. Subject maps consume the resident subject vector; group maps consume
            %   the resident feature moments/counts produced by the same QC computation. Volumetric
            %   identity is atlas label ID. Surface identity is hemisphere + source annotation ID.
            %   Geometry contributes coordinates/faces only.
            %
            % Scientific/state invariants:
            %   roiPayload(i) belongs only to canonical column i. No ROI-name matching, label
            %   interpolation, atlas reclassification, or surface-template inference is permitted.
            %   The labelled atlas and annotation-label vectors remain the spatial authorities;
            %   The canonical voxel-to-ROI lookup is retained once during Preview.
            %
            % Materialization and performance:
            %   Interactive-safe. Reads only the already materialized session MAT sidecar, reused in
            %   process memory. Group metrics are O(P) operations over resident ROI moments/counts;
            %   volumetric transport references the Preview-owned voxel-to-ROI mapping;
            %   its structural display background was sampled during explicit Preview materialization.
            %   Surface expansion performs one annotation-label membership pass per resident hemisphere
            %   and O(V+F) browser transport packaging. No atlas, annotation, geometry, structural
            %   template, CAT12/XML, or subject ROI source file is opened here.
            %
            % Failure semantics:
            %   Missing/inconsistent resident atlas, annotation labels, mesh geometry, QC moments when required, or canonical
            %   payload dimensions fail explicitly. There is no generic-profile or source-IO fallback.
            %
            % Side effects and consumers:
            %   Writes immutable anatomy/atlas/lookup assets once; ROI value vectors are
            %   returned through the bridge without dense voxel expansion.
            if nargin < 3 || isempty(opts), opts = struct(); end
            out = struct('ok',false,'message','ROI spatial viewer data could not be prepared.', ...
                'representationFamily','','volume',struct(),'mesh',struct(),'overlay',struct(), ...
                'roiIDs',[],'roiNames',{{}},'nMappedROIs',0);
            cacheToken = NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir',''));
            doProfile = NMDataIOProfileTools.enabled(struct(),struct(),opts);
            requestedMetric=lower(strtrim(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'metricKey','subject_z'))));
            tResident = tic;
            [resident, residentMessage] = NMDataIOFeatureQCTools.residentROIViewerMaterialization(cacheToken, tmpDir);
            NMDataIOProfileTools.log(doProfile, 'ROI viewer resident sidecar: %.3fs',toc(tResident));
            if ~isempty(residentMessage), out.message = residentMessage; return; end
            if ~isfield(resident,'featureSpace') || ~strcmp(resident.featureSpace,'roi_field') || ...
                    ~isfield(resident,'roiProvenance') || ~isstruct(resident.roiProvenance)
                out.message = 'The current Preview does not contain the complete ROI data needed for spatial viewing. Run Preview again.';
                return;
            end
            roiIDs = double(resident.roiProvenance.roiIDs(:)');
            roiNames = NMDataIOFeatureQCTools.asCellstr(resident.roiProvenance.roiNames);
            refs = NMDataIOFeatureQCTools.fieldOr(resident.roiProvenance,'spatialReferences',struct([]));
            if isempty(refs) || ~isstruct(refs)
                out.message = 'No validated ROI atlas or surface annotation is available for the current Preview.';
                return;
            end
            kinds = arrayfun(@(r)lower(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(r,'kind',''))),refs,'UniformOutput',false);
            supported = unique(kinds(ismember(kinds,{'volumetric_atlas','surface_annotation'})),'stable');
            if numel(supported) ~= 1
                out.message = sprintf('The ROI data contain conflicting spatial references. Exactly one atlas or surface representation is required; found: %s.',strjoin(supported,', '));
                return;
            end
            if strcmp(requestedMetric,'subject_raw')
                metricKey='subject_raw';
                metricInfo=struct('key','subject_raw','label','Subject ROI value','overlayKind','sequential');
            else
                metricKey = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(requestedMetric);
                metricInfo = NMDataIOFeatureQCTools.imageQCMetricInfo(metricKey);
            end
            threshold = NMDataIOFeatureQCTools.qcOptionNumber(opts,'zThreshold',NMDataIOFeatureQCTools.fieldOr(resident,'outlierZThreshold',3));
            appliedThreshold = double(threshold);
            metricWarning = '';
            if ismember(metricKey,{'subject_raw','subject_z'})
                roiPayload = double(roiPayload(:)');
                if numel(roiPayload) ~= numel(roiIDs)
                    out.message = sprintf('The ROI data contain %g values, but %g ROI columns are expected.',numel(roiPayload),numel(roiIDs));
                    return;
                end
                validCount = nnz(isfinite(roiPayload));
                valueWindow = NMDataIOFeatureQCTools.finiteValueWindow(roiPayload);
                if strcmp(metricKey,'subject_raw')
                    threshold=0; appliedThreshold=0;
                    metricLabel=NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'metricLabel','Subject ROI value'));
                    overlayKind='sequential';
                else
                    metricLabel = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'metricLabel','Subject ROI z-score'));
                    overlayKind = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'overlayKind','subject_z'));
                    valueWindow = resident.cohortZWindow;
                end
            else
                % ROI group maps use the same resident moment/count schema as voxel QC. The
                % resulting ROI-level vector is then expanded by this function through canonical
                % atlas/annotation identity; no second group-statistics implementation exists.
                [roiPayload, validCount, valueWindow, metricErr, appliedThreshold, metricWarning] = ...
                    NMDataIOFeatureQCTools.cachedImageQCMetricVector(resident, metricKey, threshold);
                if ~isempty(metricErr)
                    out.message = metricErr;
                    return;
                end
                if numel(roiPayload) ~= numel(roiIDs)
                    out.message = sprintf('The group ROI QC result contains %g values, but %g ROI columns are expected.',numel(roiPayload),numel(roiIDs));
                    return;
                end
                metricLabel = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'metricLabel',metricInfo.label));
                overlayKind = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'overlayKind',metricInfo.overlayKind));
            end
            if isempty(valueWindow) || numel(valueWindow)<2 || any(~isfinite(valueWindow)) || valueWindow(2)<=valueWindow(1)
                finitePayload = roiPayload(isfinite(roiPayload));
                if isempty(finitePayload), valueWindow=[0 1]; else, valueWindow=[min(finitePayload) max(finitePayload)]; end
                if valueWindow(2)<=valueWindow(1), valueWindow(2)=valueWindow(1)+eps; end
            end

            switch supported{1}
                case 'volumetric_atlas'
                    if ~isfield(resident,'roiAtlas') || ~isstruct(resident.roiAtlas) || ~isscalar(resident.roiAtlas) || ...
                            ~isfield(resident.roiAtlas,'data') || isempty(resident.roiAtlas.data) || ~isfield(resident.roiAtlas,'dimensions')
                        out.message = 'The labelled ROI atlas is not available in the current Preview. Run Preview again with the atlas available.';
                        return;
                    end
                    atlasData = resident.roiAtlas.data;
                    dims = double(resident.roiAtlas.dimensions(:)');
                    dataSize=size(atlasData); if numel(dataSize)<3, dataSize(end+1:3)=1; end
                    if numel(dims)~=3 || ~isequal(double(dataSize(1:3)),dims)
                        out.message = 'The stored ROI atlas no longer matches the current Preview data. Run Preview again.'; return;
                    end
                    mapping = resident.roiVolumeMapping;
                    if ~isequal(double(mapping.dimensions(:)'),dims) || ...
                            ~isequal(double(mapping.roiIDs(:)'),roiIDs)
                        error('NMDataIOFeatureQCTools:ROIViewerMappingMismatch', ...
                            'The retained ROI voxel mapping does not match the canonical atlas/feature coordinate.');
                    end

                    if ~isfield(resident,'roiStructural') || ~isstruct(resident.roiStructural) || ...
                            ~isfield(resident.roiStructural,'data') || isempty(resident.roiStructural.data) || ...
                            ~isfield(resident.roiStructural,'window') || numel(resident.roiStructural.window) < 2
                        out.message = ['The anatomical background needed for ROI inspection is not available. ' ...
                            'Run Preview or recompute ROI QC before opening volumetric ROI inspection.'];
                        return;
                    end
                    structuralSize=size(resident.roiStructural.data); if numel(structuralSize)<3, structuralSize(end+1:3)=1; end
                    if ~isequal(double(structuralSize(1:3)),dims)
                        out.message = 'The anatomical background no longer matches the ROI atlas. Run Preview again.'; return;
                    end

                    % The Preview-owned lookup is immutable. Only ROI-column values change
                    % between subjects/metrics; no dense value expansion belongs in this service.
                    viewDims = dims([2 1 3]);
                    displayWindow = double(resident.roiStructural.window(:)');
                    if numel(displayWindow) < 2 || any(~isfinite(displayWindow(1:2))) || displayWindow(2) <= displayWindow(1)
                        out.message = 'The saved anatomical display range is invalid. Run Preview again to recreate the ROI QC results.'; return;
                    end

                    tAssets = tic;
                    [assetDir,assetUrlBase,assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
                    if ~isempty(assetErr), out.message=assetErr; return; end
                    pkgToken=['roi_' cacheToken]; pkgDir=fullfile(assetDir,pkgToken);
                    if exist(pkgDir,'dir')~=7
                        [ok,msg]=mkdir(pkgDir); if ~ok, out.message=sprintf('Could not create ROI viewer asset directory %s: %s',pkgDir,msg); return; end
                    end
                    structuralName='structural_f32.bin';
                    atlasType = resident.atlasTransportType;
                    atlasName=['atlas_' atlasType '.bin'];
                    lookupType = mapping.lookupIndexClass;
                    lookupName=['roi_lookup_' lookupType '.bin'];
                    structuralPath=fullfile(pkgDir,structuralName); atlasPath=fullfile(pkgDir,atlasName);
                    lookupPath=fullfile(pkgDir,lookupName);
                    if ~NMDataIOFeatureQCTools.binaryAssetMatches(structuralPath,prod(dims)*4)
                        structuralView = NMDataIOFeatureQCTools.orientVolumeForViewer(single(resident.roiStructural.data));
                        NMDataIOImagePreviewTools.writeBinaryFile(structuralPath,structuralView(:),'single');
                    end
                    if ~NMDataIOFeatureQCTools.binaryAssetMatches(atlasPath,prod(dims)*resident.atlasTransportBytes)
                        if strcmp(atlasType,'float64')
                            atlasView = NMDataIOFeatureQCTools.orientVolumeForViewer(double(atlasData));
                            precision = 'double';
                        else
                            atlasView = NMDataIOFeatureQCTools.orientVolumeForViewer(cast(atlasData,atlasType));
                            precision = atlasType;
                        end
                        NMDataIOImagePreviewTools.writeBinaryFile(atlasPath,atlasView(:),precision);
                    end
                    % The mapping orientation is written once per Preview identity; subsequent
                    % requests send only the canonical ROI vector through the numeric bridge payload.
                    lookupBytes = numel(mapping.lookupIndex) * numel(typecast(cast(0,lookupType),'uint8'));
                    if ~NMDataIOFeatureQCTools.binaryAssetMatches(lookupPath,lookupBytes)
                        lookupView = NMDataIOFeatureQCTools.orientVolumeForViewer(mapping.lookupIndex);
                        NMDataIOImagePreviewTools.writeBinaryFile(lookupPath,lookupView(:),lookupType);
                    end
                    NMDataIOProfileTools.log(doProfile, 'ROI viewer immutable assets: %.3fs (ROI payload values=%d)', ...
                        toc(tAssets),numel(roiPayload));
                    sliceIndex=NMDataIOFeatureQCTools.qcOptionNumber(opts,'sliceIndex',NaN);
                    if ~isfinite(sliceIndex)||sliceIndex<1, sliceIndex=double(NMDataIOFeatureQCTools.fieldOr(resident,'atlasDefaultSlice',ceil(dims(3)/2))); end
                    sliceIndex=min(max(1,round(sliceIndex)),dims(3));
                    out.representationFamily='volume';
                    out.volume=struct('ok',true,'viewerMode','client_volume', ...
                        'imageVolumeUrl',[assetUrlBase '/' pkgToken '/' structuralName], ...
                        'maskVolumeUrl',[assetUrlBase '/' pkgToken '/' atlasName], ...
                        'roiLookupUrl',[assetUrlBase '/' pkgToken '/' lookupName], ...
                        'roiLookupType',lookupType, ...
                        'dataType','float32','maskDataType',atlasType,'overlayMode','atlas','maskOverlayVisible',false, ...
                        'dims',viewDims,'sliceIndex',double(sliceIndex),'nSlices',double(dims(3)), ...
                        'imageDim',dims,'maskDim',dims,'window',displayWindow(1:2), ...
                        'structuralFile',NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(resident.roiStructural,'structuralFile','')), ...
                        'structuralResampling',NMDataIOFeatureQCTools.fieldOr(resident.roiStructural,'resampling',struct()));
                    out.overlay=struct('ok',true,'roiValues',single(roiPayload(:)'), ...
                        'roiValueCount',double(numel(roiIDs)), ...
                        'dims',viewDims,'sliceIndex',double(sliceIndex),'nSlices',double(dims(3)), ...
                        'thresholdDefault',double(threshold),'thresholdApplied',double(appliedThreshold),'metricKey',metricKey, ...
                        'metricLabel',metricLabel,'overlayKind',overlayKind,'valueWindow',double(valueWindow), ...
                        'validFeatureCount',double(validCount),'dynamicOutlierThresholdAvailable',false,'warning',metricWarning);
                    if strcmp(metricKey,'subject_raw')
                        out.message=sprintf(['Displayed %g raw ROI value(s) using exact atlas-label matching without resampling; ' ...
                            'the standard NM structural reference was sampled onto the atlas grid for display only.'],numel(roiIDs));
                    elseif strcmp(metricKey,'subject_z')
                        out.message=sprintf(['Displayed %g ROI z-score(s) using exact atlas-label matching without resampling; ' ...
                            'the standard NM structural reference was sampled onto the atlas grid for display only.'],numel(roiIDs));
                    else
                        out.message=sprintf('Displayed group-level ROI QC metric "%s" across %g atlas parcels by matching ROI IDs to atlas labels.',metricLabel,numel(roiIDs));
                    end

                case 'surface_annotation'
                    if ~isfield(resident,'roiSurface') || ~isstruct(resident.roiSurface) || ...
                            ~isfield(resident.roiSurface,'parts') || isempty(resident.roiSurface.parts)
                        out.message = 'The surface annotation and display mesh are not available in the current Preview. Run Preview again with both files available.';
                        return;
                    end
                    hemi = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(resident.roiProvenance,'hemisphere',{}));
                    if numel(hemi) ~= numel(roiIDs)
                        out.message = 'The surface ROI data do not provide one hemisphere value for every ROI column.'; return;
                    end
                    parts = resident.roiSurface.parts;
                    verticesAll=single(zeros(0,3)); facesAll=uint32(zeros(0,3)); valuesAll=single(zeros(0,1));
                    mappedROI=false(1,numel(roiIDs)); vertexOffset=uint32(0);
                    for pp=1:numel(parts)
                        part=parts(pp); token=lower(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(part,'hemisphere','')));
                        labels=double(NMDataIOFeatureQCTools.fieldOr(part,'annotationLabels',[])); labels=labels(:);
                        vertices=single(NMDataIOFeatureQCTools.fieldOr(part,'vertices',[])); faces=uint32(NMDataIOFeatureQCTools.fieldOr(part,'faces',[]));
                        if ~ismember(token,{'lh','rh'}) || isempty(labels) || size(vertices,1)~=numel(labels) || size(vertices,2)~=3 || size(faces,2)~=3
                            out.message=sprintf('The %s surface ROI data are incomplete or do not match the selected surface.',upper(token)); return;
                        end
                        canonical=find(strcmp(hemi,token));
                        if isempty(canonical), continue; end
                        try
                            [expandedValues,isROI,canonicalColumns]=NMDataIOROIProvenanceTools.expandSurfaceValues( ...
                                resident.roiProvenance,roiPayload,token,labels);
                        catch ME
                            out.message=sprintf('The %s surface annotation does not match the ROI values: %s',upper(token),ME.message); return;
                        end
                        values=single(expandedValues);
                        mappedROI(canonicalColumns)=true;
                        verticesAll=[verticesAll;vertices]; %#ok<AGROW>
                        facesAll=[facesAll;faces+vertexOffset]; %#ok<AGROW>
                        valuesAll=[valuesAll;values]; %#ok<AGROW>
                        vertexOffset=vertexOffset+uint32(size(vertices,1));
                    end
                    if ~all(mappedROI)
                        out.message='The current surface ROI QC data do not contain every hemisphere and annotation ID required by this modality.'; return;
                    end
                    mesh=NMDataIOSurfaceTools.prepareSurfaceViewerArrays(verticesAll,facesAll,valuesAll,tmpDir,struct('valueWindow',valueWindow));
                    if ~isstruct(mesh)||~isfield(mesh,'ok')||~logical(mesh.ok)
                        out.message=NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(mesh,'message','Surface ROI browser assets could not be prepared.')); return;
                    end
                    out.representationFamily='surface'; out.mesh=mesh;
                    out.overlay=struct('ok',true,'valuesUrl',mesh.valuesUrl,'dataType','float32','nVertices',mesh.nVertices, ...
                        'thresholdDefault',double(threshold),'thresholdApplied',double(appliedThreshold),'metricKey',metricKey, ...
                        'metricLabel',metricLabel,'overlayKind',overlayKind,'valueWindow',double(valueWindow), ...
                        'validFeatureCount',double(validCount),'dynamicOutlierThresholdAvailable',false,'warning',metricWarning);
                    if strcmp(metricKey,'subject_raw')
                        out.message=sprintf('Displayed %g raw ROI value(s) on the annotation-labelled surface using exact hemisphere and annotation-ID matching.',numel(roiIDs));
                    elseif strcmp(metricKey,'subject_z')
                        out.message=sprintf('Displayed %g ROI z-score(s) on the annotation-labelled surface using exact hemisphere and annotation-ID matching.',numel(roiIDs));
                    else
                        out.message=sprintf('Displayed group-level ROI QC metric "%s" across %g surface parcels using exact hemisphere and annotation-ID matching.',metricLabel,numel(roiIDs));
                    end
            end
            out.roiIDs=roiIDs; out.roiNames=roiNames(:)'; out.nMappedROIs=double(numel(roiIDs)); out.ok=true;
        end

        function out = prepareImageViewerQCOverlay(imageFile, maskFile, cacheToken, opts)
            % prepareImageViewerQCOverlay  Prepare a per-subject image QC overlay for the browser viewer from cached metrics.
            %
            % Consumes imageFile, maskFile, cacheToken, opts; returns out.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.metricKey: configures optional metric key behavior for this call.
            % opts.ReferenceMode: configures optional reference mode behavior for this call.
            % opts.sliceIndex: selects the image/surface slice or subject index rendered for preview.
            % opts.spaceDefType: configures optional space def type behavior for this call.
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 4 || isempty(opts), opts = struct(); end
            metricKey = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(NMDataIOFeatureQCTools.fieldOr(opts, 'metricKey', 'subject_z'));
            metricInfo = NMDataIOFeatureQCTools.imageQCMetricInfo(metricKey);
            zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'zThreshold', NaN);
            if ~isfinite(zThreshold) || zThreshold < 0
                zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'OutlierZThreshold', 3);
            end
            referenceMode = lower(strtrim(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'ReferenceMode', 'leave_one_out'))));
            if any(strcmp(referenceMode, {'fixed','training_reference','reference'})), referenceMode = 'fixed_reference'; end
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            out = struct('ok',false,'message','QC overlay not prepared.', ...
                'overlayVolumeUrl','','dataType','float32','dims',[],'sliceIndex',NaN, ...
                'nSlices',NaN,'thresholdDefault',double(zThreshold),'modeDefault','signed', ...
                'thresholdApplied',double(zThreshold),'dynamicOutlierThresholdAvailable',false, ...
                'validFeatureCount',0,'warning','', 'metricKey',metricKey, ...
                'metricLabel',metricInfo.label, 'overlayKind',metricInfo.overlayKind, ...
                'valueWindow',[NaN NaN]);
            imageFile = NMDataIOFeatureQCTools.asChar(imageFile);
            maskFile = NMDataIOFeatureQCTools.asChar(maskFile);
            cacheToken = NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'tmpDir', ''));
            if strcmp(metricKey, 'subject_z') && isempty(imageFile)
                out.message = 'No image file was supplied for subject-specific QC z-score overlay preparation.';
                return;
            end
            if isempty(maskFile)
                out.message = 'No brainmask file was supplied for QC overlay preparation.';
                return;
            end
            if isempty(cacheToken)
                out.message = 'Imaging QC data are not available. Run Preview and compute Feature QC first.';
                return;
            end
            [assetDir, assetUrlBase, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                out.message = assetErr;
                return;
            end
            cacheFile = fullfile(assetDir, [cacheToken '.mat']);
            if exist(cacheFile, 'file') ~= 2
                out.message = sprintf('Imaging QC data are missing: %s. Run Preview again for the current import task.', cacheFile);
                return;
            end
            try
                S = load(cacheFile, '-mat');
            catch ME
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
                return;
            end
            requiredFields = {'meanVec','m2Vec','countVec'};
            for i = 1:numel(requiredFields)
                if ~isfield(S, requiredFields{i})
                    out.message = sprintf('Imaging QC data are incomplete; required information %s is missing.', requiredFields{i});
                    return;
                end
            end
            if strcmp(metricKey, 'subject_z')
                [spmImageFiles, imageMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({imageFile}, 'imageViewer.qcOverlay.imageFile', true);
                if NMDataIOMessageTools.hasFatal(imageMessages)
                    out.message = NMDataIOFeatureQCTools.firstMessageText(imageMessages, sprintf('Image file cannot be resolved for SPM: %s', imageFile));
                    out.messages = imageMessages;
                    return;
                end
            else
                spmImageFiles = {};
            end
            [spmMaskFiles, maskMessages] = NMDataIOImageFileTools.resolveNiftiFilesForSPM({maskFile}, 'imageViewer.qcOverlay.maskFile', true);
            if NMDataIOMessageTools.hasFatal(maskMessages)
                out.message = NMDataIOFeatureQCTools.firstMessageText(maskMessages, sprintf('Brainmask file cannot be resolved for SPM: %s', maskFile));
                out.messages = maskMessages;
                return;
            end
            required = {'spm_vol','spm_read_vols','spm_slice_vol','spm_matrix'};
            for i = 1:numel(required)
                if ~NMDataIOFeatureQCTools.functionAvailable(required{i})
                    out.message = sprintf('Required SPM function is not available: %s.', required{i});
                    return;
                end
            end
            try
                VmAll = spm_vol(spmMaskFiles{1});
                maskVol = spm_read_vols(VmAll);
                Vm = VmAll(1);
                dummyIO = struct('spaceDefType', NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'spaceDefType', 'brainmask')));
                [mask, maskMessages] = NMDataIOFeatureQCTools.supportMaskFromSpaceDef(maskVol, dummyIO, 'featureQC.viewerMask');
                if NMDataIOMessageTools.hasFatal(maskMessages)
                    out.message = NMDataIOFeatureQCTools.firstMessageText(maskMessages, 'The selected space-defining image is not usable for QC overlay preparation.');
                    out.messages = maskMessages;
                    return;
                end
                nFeatures = nnz(mask);
                meanVec = double(S.meanVec(:)');
                m2Vec = double(S.m2Vec(:)');
                countVec = double(S.countVec(:)');
                if numel(meanVec) ~= nFeatures || numel(m2Vec) ~= nFeatures || numel(countVec) ~= nFeatures
                    out.message = sprintf('Imaging QC data do not match the current image mask: QC contains %g feature(s), while the mask defines %g voxel feature(s). Run Preview again for this import task.', numel(meanVec), nFeatures);
                    return;
                end
                if strcmp(metricKey, 'subject_z')
                    Vi = spm_vol(spmImageFiles{1});
                    if numel(Vi) > 1, Vi = Vi(1); end
                    x = NMDataIOFeatureQCTools.sampleImageInMaskSpace(Vi, Vm, mask);
                    [overlayVec, validCount] = NMDataIOFeatureQCTools.computeSubjectZVector(x, meanVec, m2Vec, countVec, referenceMode);
                    valueWindow = S.cohortZWindow;
                    out.thresholdApplied = double(zThreshold);
                    out.dynamicOutlierThresholdAvailable = isfield(S,'absZMatrix');
                else
                    [overlayVec, validCount, valueWindow, metricErr, appliedThreshold, metricWarn] = NMDataIOFeatureQCTools.cachedImageQCMetricVector(S, metricKey, zThreshold);
                    out.thresholdApplied = double(appliedThreshold);
                    out.dynamicOutlierThresholdAvailable = isfield(S,'absZMatrix');
                    if ~isempty(metricWarn)
                        out.warning = metricWarn;
                    end
                    if ~isempty(metricErr)
                        out.message = metricErr;
                        return;
                    end
                end
                overlayVol = NMDataIOFeatureQCTools.vectorToViewerVolume(overlayVec, Vm, mask);
                if exist(assetDir,'dir') ~= 7
                    [ok,msg] = mkdir(assetDir);
                    if ~ok
                        out.message = sprintf('Could not create viewer asset directory %s: %s', assetDir, msg);
                        return;
                    end
                end
                token = NMDataIOImagePreviewTools.safeToken();
                pkgDir = fullfile(assetDir, token);
                [ok,msg] = mkdir(pkgDir);
                if ~ok
                    out.message = sprintf('Could not create QC overlay package directory %s: %s', pkgDir, msg);
                    return;
                end
                overlayBin = fullfile(pkgDir, 'qc_overlay_f32.bin');
                NMDataIOImagePreviewTools.writeBinaryFile(overlayBin, single(overlayVol(:)), 'single');
                out.overlayVolumeUrl = [assetUrlBase '/' token '/qc_overlay_f32.bin'];
                out.dims = double([size(overlayVol,1), size(overlayVol,2), size(overlayVol,3)]);
                out.nSlices = double(size(overlayVol,3));
                if isfield(opts,'sliceIndex') && ~isempty(opts.sliceIndex) && isfinite(double(opts.sliceIndex)) && double(opts.sliceIndex) > 0
                    sliceIndex = round(double(opts.sliceIndex));
                    sliceIndex = min(max(sliceIndex,1), out.nSlices);
                else
                    sliceIndex = round(out.nSlices/2);
                end
                out.sliceIndex = double(sliceIndex);
                out.validFeatureCount = double(validCount);
                out.valueWindow = double(valueWindow(:)');
                if numel(out.valueWindow) ~= 2, out.valueWindow = [NaN NaN]; end
                out.ok = true;
                out.message = sprintf('Prepared %s QC overlay for %g valid mask-space voxel feature(s).', metricInfo.label, validCount);
                if ~isempty(out.warning)
                    out.message = sprintf('%s %s', out.message, out.warning);
                end
            catch ME
                out.ok = false;
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function out = prepareSurfaceViewerQCOverlay(surfaceFile, cacheToken, opts)
            % prepareSurfaceViewerQCOverlay  Prepare a per-subject surface QC overlay for the browser viewer from cached metrics.
            %
            % Consumes surfaceFile, cacheToken, opts; returns out.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % Performs explicit file-system IO; diagnostics are returned as structured messages for explicit UI/API handling; cache contents are an acceleration/rehydration artifact, not a new source of truth.
            %
            % opts.metricKey: configures optional metric key behavior for this call.
            % opts.ReferenceMode: configures optional reference mode behavior for this call.
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 3 || isempty(opts), opts = struct(); end
            metricKey = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(NMDataIOFeatureQCTools.fieldOr(opts, 'metricKey', 'subject_z'));
            metricInfo = NMDataIOFeatureQCTools.surfaceQCMetricInfo(metricKey);
            zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'zThreshold', NaN);
            if ~isfinite(zThreshold) || zThreshold < 0
                zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'OutlierZThreshold', 3);
            end
            referenceMode = lower(strtrim(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'ReferenceMode', 'leave_one_out'))));
            if any(strcmp(referenceMode, {'fixed','training_reference','reference'})), referenceMode = 'fixed_reference'; end
            if isempty(referenceMode), referenceMode = 'leave_one_out'; end
            out = struct('ok',false,'message','Surface QC overlay not prepared.', ...
                'valuesUrl','','dataType','float32','nVertices',NaN, ...
                'thresholdApplied',double(zThreshold),'dynamicOutlierThresholdAvailable',false, ...
                'validFeatureCount',0,'warning','', 'metricKey',metricKey, ...
                'metricLabel',metricInfo.label, 'overlayKind',metricInfo.overlayKind, ...
                'valueWindow',[NaN NaN]);
            surfaceFile = NMDataIOFeatureQCTools.asChar(surfaceFile);
            cacheToken = NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'tmpDir', ''));
            if strcmp(metricKey, 'subject_z') && isempty(surfaceFile)
                out.message = 'No surface scalar file was supplied for subject-specific surface QC z-score overlay preparation.';
                return;
            end
            if isempty(cacheToken)
                out.message = 'Surface QC data are not available. Run Preview for the current surface import task first.';
                return;
            end
            [assetDir, assetUrlBase, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                out.message = assetErr;
                return;
            end
            cacheFile = fullfile(assetDir, [cacheToken '.mat']);
            if exist(cacheFile, 'file') ~= 2
                out.message = sprintf('Surface QC data are missing: %s. Run Preview again for the current import task.', cacheFile);
                return;
            end
            try
                S = load(cacheFile, '-mat');
            catch ME
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
                return;
            end
            requiredFields = {'meanVec','sdVec','countVec'};
            for i = 1:numel(requiredFields)
                if ~isfield(S, requiredFields{i})
                    out.message = sprintf('Surface QC data are incomplete; required information %s is missing.', requiredFields{i});
                    return;
                end
            end
            try
                meanVec = double(S.meanVec(:)');
                countVec = double(S.countVec(:)');
                nVertices = numel(meanVec);
                if strcmp(metricKey, 'subject_z')
                    [x, ~] = NMDataIOSurfaceTools.readSurfaceScalar(surfaceFile);
                    x = double(x(:)');
                    if numel(x) ~= nVertices
                        out.message = sprintf('Surface QC data do not match the selected scalar file: QC contains %g vertices, while the file contains %g vertices (%s). Run Preview again or select a matching registered surface file.', nVertices, numel(x), surfaceFile);
                        return;
                    end
                    if ~isfield(S,'m2Vec') || isempty(S.m2Vec)
                        out.message = 'Surface subject z-scores require the persisted M2 reference moments. Run Preview again for this modality.';
                        return;
                    end
                    [values, validCount] = NMDataIOFeatureQCTools.computeSubjectZVector(x, meanVec, double(S.m2Vec(:)'), countVec, referenceMode);
                    valueWindow = S.cohortZWindow;
                    out.thresholdApplied = double(zThreshold);
                    out.dynamicOutlierThresholdAvailable = isfield(S,'absZMatrix');
                else
                    [values, validCount, valueWindow, metricErr, appliedThreshold, metricWarn] = NMDataIOFeatureQCTools.cachedSurfaceQCMetricVector(S, metricKey, zThreshold);
                    out.thresholdApplied = double(appliedThreshold);
                    out.dynamicOutlierThresholdAvailable = isfield(S,'absZMatrix');
                    if ~isempty(metricWarn)
                        out.warning = metricWarn;
                    end
                    if ~isempty(metricErr)
                        out.message = metricErr;
                        return;
                    end
                end
                if exist(assetDir,'dir') ~= 7
                    [ok,msg] = mkdir(assetDir);
                    if ~ok
                        out.message = sprintf('Could not create viewer asset directory %s: %s', assetDir, msg);
                        return;
                    end
                end
                token = ['surfqc_' regexprep(NMDataIOImagePreviewTools.safeToken(), '^vol_', '')];
                pkgDir = fullfile(assetDir, token);
                [ok,msg] = mkdir(pkgDir);
                if ~ok
                    out.message = sprintf('Could not create surface QC package directory %s: %s', pkgDir, msg);
                    return;
                end
                valuesBin = fullfile(pkgDir, 'surface_qc_values_f32.bin');
                NMDataIOImagePreviewTools.writeBinaryFile(valuesBin, single(values(:)), 'single');
                out.valuesUrl = [assetUrlBase '/' token '/surface_qc_values_f32.bin'];
                out.nVertices = double(nVertices);
                out.validFeatureCount = double(validCount);
                out.valueWindow = double(valueWindow(:)');
                if numel(out.valueWindow) ~= 2 || ~all(isfinite(out.valueWindow)) || out.valueWindow(2) <= out.valueWindow(1)
                    out.valueWindow = NMDataIOFeatureQCTools.finiteValueWindow(values);
                end
                out.ok = true;
                out.message = sprintf('Prepared %s surface QC overlay for %g valid vertex feature(s).', metricInfo.label, validCount);
                if ~isempty(out.warning)
                    out.message = sprintf('%s %s', out.message, out.warning);
                end
            catch ME
                out.ok = false;
                out.message = sprintf('%s: %s', ME.identifier, ME.message);
                out.identifier = ME.identifier;
                out.error = ME.message;
            end
        end

        function key = normalizeImageQCMetricKey(key)
            % normalizeImageQCMetricKey  Normalize image QC metric aliases to the canonical metric key.
            %
            % Key -> key.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            key = lower(strtrim(NMDataIOFeatureQCTools.asChar(key)));
            key = strrep(key, '-', '_');
            key = strrep(key, ' ', '_');
            switch key
                case {'','z','subjectz','subject_z','subject_zscore','leave_one_out_population_zscore'}
                    key = 'subject_z';
                case {'missing','missing_rate','feature_missing','feature_missing_rate'}
                    key = 'feature_missing_rate';
                case {'mean','feature_mean'}
                    key = 'feature_mean';
                case {'std','sd','feature_std','feature_sd'}
                    key = 'feature_std';
                case {'zero','zero_rate','feature_zero','feature_zero_rate'}
                    key = 'feature_zero_rate';
                case {'outlier','outlier_rate','feature_outlier','feature_outlier_rate'}
                    key = 'feature_outlier_rate';
                otherwise
                    key = 'subject_z';
            end
        end

        function info = imageQCMetricInfo(key)
            % imageQCMetricInfo  Return display name, units, and scaling metadata for an image QC metric.
            %
            % Key -> info.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            key = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(key);
            switch key
                case 'subject_z'
                    info = struct('key',key,'label','Subject z-score','overlayKind','subject_z');
                case 'feature_missing_rate'
                    info = struct('key',key,'label','Group missing-rate','overlayKind','rate');
                case 'feature_mean'
                    info = struct('key',key,'label','Group mean','overlayKind','sequential');
                case 'feature_std'
                    info = struct('key',key,'label','Group standard deviation','overlayKind','sequential');
                case 'feature_zero_rate'
                    info = struct('key',key,'label','Group zero-rate','overlayKind','rate');
                case 'feature_outlier_rate'
                    info = struct('key',key,'label','Group outlier-rate','overlayKind','rate');
                otherwise
                    info = struct('key','subject_z','label','Subject z-score','overlayKind','subject_z');
            end
        end

        function metrics = imageQCMetricList()
            % imageQCMetricList  Return the supported image QC metric definitions for UI/report selection.
            %
            % No required inputs -> metrics.
            % It links import artifacts to QC viewers/reports while keeping heavy overlay arrays outside lightweight UI state.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            metrics = struct('key',{},'label',{},'overlayKind',{});
            keys = {'subject_z','feature_missing_rate','feature_mean','feature_std','feature_zero_rate','feature_outlier_rate'};
            for i = 1:numel(keys)
                metrics(end+1) = NMDataIOFeatureQCTools.imageQCMetricInfo(keys{i}); %#ok<AGROW>
            end
        end

        function [vec, validCount, valueWindow, err, appliedThreshold, warning] = cachedImageQCMetricVector(S, metricKey, varargin)
            % Resolve group voxel QC from the canonical cached moments.
            zThreshold = [];
            if ~isempty(varargin), zThreshold = varargin{1}; end
            [vec, validCount, valueWindow, err, appliedThreshold, warning] = ...
                NMDataIOFeatureQCTools.cachedGroupQCMetricVector(S, metricKey, zThreshold, false);
        end

        function [vec, validCount, valueWindow, err, appliedThreshold, warning] = cachedGroupQCMetricVector(S, metricKey, zThreshold, surface)
            % Shared image/surface/ROI group metric evaluation. Cache moments are produced by Preview.
            err = '';
            warning = '';
            metricKey = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(metricKey);
            if nargin < 3 || isempty(zThreshold) || ~isfinite(double(zThreshold)) || double(zThreshold) < 0
                zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(S, 'outlierZThreshold', 3);
            end
            zThreshold = double(zThreshold);
            appliedThreshold = double(zThreshold);
            countVec = double(S.countVec(:)');
            meanVec = double(S.meanVec(:)');
            if surface
                sdVec = double(S.sdVec(:)');
            else
                m2Vec = double(S.m2Vec(:)');
            end
            validCount = 0;
            valueWindow = [NaN NaN];
            vec = nan(size(meanVec));
            nFeatures = numel(meanVec);
            family = 'imaging';
            featureName = 'voxel-feature';
            if surface
                family = 'surface';
                featureName = 'vertex';
            end
            switch metricKey
                case 'feature_missing_rate'
                    if ~isfield(S,'nSubjects') || ~isfinite(double(S.nSubjects)) || double(S.nSubjects) < 1
                        err = sprintf('The %s missing-rate map requires the number of cases, which is unavailable in the current QC data. Run Preview again.', family);
                        return;
                    end
                    nSubjects = double(S.nSubjects);
                    vec = (nSubjects - countVec) ./ max(1, nSubjects);
                    valueWindow = [0 1];
                case 'feature_mean'
                    vec = meanVec;
                case 'feature_std'
                    if surface
                        vec = sdVec;
                    else
                        vec = sqrt(m2Vec ./ max(1, countVec - 1));
                    end
                    vec(countVec < 2) = NaN;
                case 'feature_zero_rate'
                    if ~isfield(S,'zeroCount')
                        err = sprintf('The %s zero-rate map requires zero counts, which are unavailable in the current QC data. Run Preview again.', family);
                        return;
                    end
                    zc = double(S.zeroCount(:)');
                    if surface
                        if numel(zc) ~= nFeatures
                            err = 'The surface zero-rate QC data do not match the current vertex count. Run Preview again.';
                            return;
                        end
                    end
                    vec = zc ./ max(1, countVec);
                    vec(countVec < 1) = NaN;
                    valueWindow = [0 1];
                case 'feature_outlier_rate'
                    if isfield(S,'absZMatrix')
                        absZ = double(S.absZMatrix);
                        if size(absZ,2) ~= nFeatures
                            err = sprintf('The %s outlier-rate QC data do not match the current %s count. Run Preview again.', family, featureName);
                            return;
                        end
                        oc = sum(isfinite(absZ) & absZ >= zThreshold, 1);
                    else
                        if ~isfield(S,'outlierCount')
                            err = sprintf('The %s outlier-rate map requires outlier counts, which are unavailable in the current QC data. Run Preview again.', family);
                            return;
                        end
                        cachedThreshold = NMDataIOFeatureQCTools.qcOptionNumber(S, 'outlierZThreshold', 3);
                        if abs(double(cachedThreshold) - zThreshold) > 1e-9
                            warning = sprintf('The outlier-rate threshold cannot be changed for this large %s dataset; using the Preview z-threshold %.6g.', family, double(cachedThreshold));
                            appliedThreshold = double(cachedThreshold);
                        end
                        oc = double(S.outlierCount(:)');
                        if numel(oc) ~= nFeatures
                            err = sprintf('The %s outlier-rate QC data do not match the current %s count. Run Preview again.', family, featureName);
                            return;
                        end
                    end
                    vec = oc ./ max(1, countVec);
                    vec(countVec < 1) = NaN;
                    valueWindow = NMDataIOFeatureQCTools.finiteValueWindow(vec);
                otherwise
                    if surface
                        err = sprintf('Unsupported surface QC metric: %s.', metricKey);
                    else
                        err = sprintf('This imaging QC metric is not available: %s.', metricKey);
                    end
                    return;
            end
            finite = isfinite(vec);
            validCount = nnz(finite);
            if surface && any(strcmp(metricKey, {'feature_mean','feature_std'}))
                valueWindow = NMDataIOFeatureQCTools.finiteValueWindow(vec);
            elseif validCount > 0 && any(isnan(valueWindow))
                valueWindow = [min(vec(finite)) max(vec(finite))];
                if valueWindow(1) == valueWindow(2)
                    pad = max(1e-6, abs(valueWindow(1)) * 0.05);
                    valueWindow = valueWindow + [-pad pad];
                end
            end
        end

        function [vec, validCount, valueWindow, err, appliedThreshold, warning] = cachedSurfaceQCMetricVectorForReport(S, metricKey, zThreshold)
            % cachedSurfaceQCMetricVectorForReport  Public report/export/test adapter for the private surface QC.
            %
            % cache vector resolver. Existing report callers request the
            % first four outputs; the additional outputs expose threshold
            % fallback diagnostics without making the private resolver public.
            if nargin < 3, zThreshold = []; end
            [vec, validCount, valueWindow, err, appliedThreshold, warning] = NMDataIOFeatureQCTools.cachedSurfaceQCMetricVector(S, metricKey, zThreshold);
        end

        function [z, validCount] = computeSubjectZVector(x, meanVec, m2Vec, countVec, referenceMode)
            % computeSubjectZVector  Compute one subject feature z-vector from canonical QC moments.
            %
            % Purpose:
            %   Provide the single subject-level standardisation authority shared by DataIO and
            %   Results Viewer feature-QC consumers.
            %
            % Inputs/outputs:
            %   x is one subject feature vector; meanVec/m2Vec/countVec are finite-observation
            %   reference moments in the same feature order. referenceMode is exactly
            %   'leave_one_out' or 'fixed_reference'. z preserves the input feature order and
            %   validCount reports its finite entries.
            %
            % Scientific/state contract:
            %   leave_one_out analytically removes an in-cohort subject from each feature's
            %   reference moments and requires at least two remaining observations. fixed_reference
            %   scores an external/OOCV subject against unchanged training/CV moments. Unknown
            %   modes fail explicitly; no population-z or fixed-reference fallback is permitted.
            %
            % Materialization and performance:
            %   Pure O(P) arithmetic over resident vectors. Reads no files, loads no atlas or
            %   annotation, scans no voxel/vertex geometry, and is safe on interactive subject
            %   navigation paths.
            %
            % Side effects / consumers:
            %   None. Consumed by imaging, surface, connectivity, ROI and generic feature-QC
            %   viewers wherever a persisted QC reference is interrogated.
            if nargin < 5 || isempty(referenceMode), referenceMode = 'leave_one_out'; end
            referenceMode = lower(strtrim(NMDataIOFeatureQCTools.asChar(referenceMode)));
            if ~any(strcmp(referenceMode, {'leave_one_out','fixed_reference'}))
                error('NMDataIOFeatureQCTools:QCReferenceMode', ...
                    'Unsupported feature-QC reference mode "%s". Expected leave_one_out or fixed_reference.', referenceMode);
            end
            x = double(x(:)');
            meanVec = double(meanVec(:)');
            m2Vec = double(m2Vec(:)');
            countVec = double(countVec(:)');
            if numel(meanVec) ~= numel(x) || numel(m2Vec) ~= numel(x) || numel(countVec) ~= numel(x)
                error('NMDataIOFeatureQCTools:QCReferenceShape', ...
                    'Subject vector and QC reference moments must have identical feature counts.');
            end
            z = nan(size(x));
            if strcmp(referenceMode, 'fixed_reference')
                finite = isfinite(x) & isfinite(meanVec) & isfinite(m2Vec) & isfinite(countVec) & countVec >= 2;
                sd = sqrt(m2Vec ./ max(1, countVec - 1));
                good = finite & isfinite(sd) & sd > 0;
                z(good) = (x(good) - meanVec(good)) ./ sd(good);
            else
                finite = isfinite(x) & isfinite(meanVec) & isfinite(m2Vec) & isfinite(countVec) & countVec >= 3;
                idx = find(finite);
                if ~isempty(idx)
                    n = countVec(idx);
                    mu = meanVec(idx);
                    M2 = m2Vec(idx);
                    xi = x(idx);
                    n2 = n - 1;
                    mu2 = (n .* mu - xi) ./ n2;
                    M2_2 = M2 - (xi - mu) .* (xi - mu2);
                    M2_2(M2_2 < 0 & M2_2 > -1e-12) = 0;
                    sd2 = sqrt(M2_2 ./ max(1, n2 - 1));
                    good = isfinite(mu2) & isfinite(sd2) & sd2 > 0 & n2 >= 2;
                    zidx = idx(good);
                    z(zidx) = (x(zidx) - mu2(good)) ./ sd2(good);
                end
            end
            validCount = nnz(isfinite(z));
        end
    end

    methods (Static, Access = private)
        function token = safeCacheToken(prefix)
            if nargin < 1 || isempty(prefix), prefix = 'cache'; end
            try
                u = char(java.util.UUID.randomUUID());
                u = strrep(u, '-', '_');
            catch
                u = regexprep(num2str(now, '%.12f'), '[^0-9]', '');
                u = [u '_' num2str(round(1e9*rand()))];
            end
            token = [char(prefix) '_' u];
        end

        function [resident, message] = residentROIViewerMaterialization(cacheToken, tmpDir)
            % residentROIViewerMaterialization  Load one persisted ROI viewer materialization into process memory.
            %
            % Purpose:
            %   Provide the single interactive access boundary for canonical ROI values, QC reference
            %   moments when available, provenance, and the resident spatial ROI materialization created during explicit Preview or QC.
            %   Volumetric provenance retains the labelled atlas and canonical indexed mapping; surface provenance retains the exact
            %   annotation-label vector plus its validated display-mesh vertices/faces per hemisphere.
            %
            % Materialization and performance:
            %   Reads one session-local MAT sidecar on first access for a cache token and then reuses
            %   it in memory. It never reads ROI source files, CAT12/XML, NIfTI atlas files, annotation
            %   files, or surface meshes. Safe for subject switching, viewer navigation, and teardown.
            %
            % Failure semantics:
            %   Missing/invalid cache state is returned explicitly; callers must not fall back to
            %   source rematerialization.
            resident = struct(); message = '';
            cacheToken = NMDataIOFeatureQCTools.asChar(cacheToken);
            tmpDir = NMDataIOFeatureQCTools.asChar(tmpDir);
            if isempty(cacheToken) || isempty(tmpDir)
                message = 'Run Preview before opening ROI spatial inspection.';
                return;
            end
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr), message = assetErr; return; end
            cacheFile = fullfile(assetDir,[cacheToken '.mat']);
            persistent residentKey residentValue
            key = [tmpDir '|' cacheToken];
            if isempty(residentKey) || ~strcmp(residentKey,key)
                if exist(cacheFile,'file') ~= 2
                    message = 'The ROI viewer data are no longer available. Run Preview again before opening case-level ROI inspection.';
                    return;
                end
                residentValue = load(cacheFile);
                residentKey = key;
            end
            resident = residentValue;
        end

        function info = surfaceQCMetricInfo(key)
            key = NMDataIOFeatureQCTools.normalizeImageQCMetricKey(key);
            switch key
                case 'subject_z'
                    info = struct('key',key,'label','Subject vertex z-score','overlayKind','subject_z');
                case 'feature_missing_rate'
                    info = struct('key',key,'label','Group vertex missing-rate','overlayKind','rate');
                case 'feature_mean'
                    info = struct('key',key,'label','Group vertex mean','overlayKind','sequential');
                case 'feature_std'
                    info = struct('key',key,'label','Group vertex standard deviation','overlayKind','sequential');
                case 'feature_zero_rate'
                    info = struct('key',key,'label','Group vertex zero-rate','overlayKind','rate');
                case 'feature_outlier_rate'
                    info = struct('key',key,'label','Group vertex outlier-rate','overlayKind','rate');
                otherwise
                    info = struct('key','subject_z','label','Subject vertex z-score','overlayKind','subject_z');
            end
        end

        function metrics = surfaceQCMetricList()
            metrics = struct('key',{},'label',{},'overlayKind',{});
            keys = {'subject_z','feature_missing_rate','feature_mean','feature_std','feature_zero_rate','feature_outlier_rate'};
            for i = 1:numel(keys)
                metrics(end+1) = NMDataIOFeatureQCTools.surfaceQCMetricInfo(keys{i}); %#ok<AGROW>
            end
        end

        function [vec, validCount, valueWindow, err, appliedThreshold, warning] = cachedSurfaceQCMetricVector(S, metricKey, zThreshold)
            % Surface vertices consume the upstream SD vector and percentile display window.
            [vec, validCount, valueWindow, err, appliedThreshold, warning] = ...
                NMDataIOFeatureQCTools.cachedGroupQCMetricVector(S, metricKey, zThreshold, true);
        end

        function [qc, messages] = computeScoresFromMatrix(M, caseIds, sourceLabel, opts)
            if nargin < 3 || isempty(sourceLabel), sourceLabel = 'matrix'; end
            if nargin < 4 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            nSubjects = size(M,1);
            nFeatures = size(M,2);
            progressTask = NMDataIOFeatureQCTools.fieldOr(opts, 'ProgressTask', NMProgressTools.emptyTaskForLocalUse());
            zeroTol = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'ZeroTolerance', 0);
            zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'OutlierZThreshold', 3);
            meanVec = nanmeanCompat(M, 1);
            sdVec = nanstdCompat(M, 0, 1);
            validFeature = isfinite(meanVec) & isfinite(sdVec) & sdVec > 0;
            if ~any(validFeature)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'featureQC.matrix', ...
                    'No variable finite feature survived z-score QC. Check feature assignments and missingness.', 1, 'red*')];
                qc = NMDataIOFeatureQCTools.emptyQC();
                return;
            end
            stats = NMDataIOFeatureQCTools.emptyScoreArrays(nSubjects);
            outlierCount = zeros(1, nFeatures);
            maxChunkElements = 2e6;
            rowsPerChunk = max(1, floor(maxChunkElements ./ max(1, nFeatures)));
            progressStride = max(rowsPerChunk, ceil(max(1,nSubjects) ./ 100));
            nextProgressRow = progressStride;
            for r1 = 1:rowsPerChunk:nSubjects
                r2 = min(nSubjects, r1 + rowsPerChunk - 1);
                rows = r1:r2;
                C = double(M(rows,:));
                finiteRaw = isfinite(C);
                Z = (C - meanVec) ./ sdVec;
                Z(:,~validFeature) = NaN;
                Z(~finiteRaw) = NaN;
                finiteZ = isfinite(Z);
                absZ = abs(Z);

                nValid = sum(finiteZ,2);
                nFinite = sum(finiteRaw,2);
                nMissing = nFeatures - nFinite;
                nZero = sum(finiteRaw & abs(C) <= zeroTol,2);
                nOutlier = sum(finiteZ & absZ >= zThreshold,2);

                rawFinite = C;
                rawFinite(~finiteRaw) = NaN;
                rowMin = min(rawFinite,[],2,'omitnan');
                rowMax = max(rawFinite,[],2,'omitnan');
                rowAllMissing = nFinite < 1;

                stats.nValidFeatures(rows) = nValid;
                stats.nFiniteFeatures(rows) = nFinite;
                stats.nMissingFeatures(rows) = nMissing;
                stats.missingFeatureRate(rows) = nMissing ./ max(1,nFeatures);
                stats.nZeroFeatures(rows) = nZero;
                stats.zeroFeatureRate(rows) = nZero ./ max(1,nFinite);
                stats.rowAllNaNFlag(rows) = rowAllMissing;
                stats.rowConstantFlag(rows) = ~rowAllMissing & rowMin == rowMax;
                stats.rmsZ(rows) = sqrt(sum(Z.^2,2,'omitnan') ./ max(1,nValid));
                stats.score(rows) = stats.rmsZ(rows);
                stats.meanAbsZ(rows) = sum(absZ,2,'omitnan') ./ max(1,nValid);
                stats.meanZ(rows) = sum(Z,2,'omitnan') ./ max(1,nValid);
                stats.sdZ(rows) = std(Z,0,2,'omitnan');
                stats.maxAbsZ(rows) = max(absZ,[],2,'omitnan');
                stats.nOutlierFeatures(rows) = nOutlier;
                stats.outlierFeatureRate(rows) = nOutlier ./ max(1,nValid);
                noValid = nValid < 1;
                if any(noValid)
                    rr = rows(noValid);
                    stats.rmsZ(rr) = NaN;
                    stats.score(rr) = NaN;
                    stats.meanAbsZ(rr) = NaN;
                    stats.meanZ(rr) = NaN;
                    stats.sdZ(rr) = NaN;
                    stats.maxAbsZ(rr) = NaN;
                    stats.outlierFeatureRate(rr) = NaN;
                end
                singleValid = nValid == 1;
                if any(singleValid)
                    stats.sdZ(rows(singleValid)) = 0;
                end
                outlierCount = outlierCount + sum(finiteZ & absZ >= zThreshold,1);

                if r2 >= nextProgressRow || r2 == nSubjects
                    progressTask = NMProgressTools.step(progressTask, r2, nSubjects, ...
                        sprintf('Scored %g of %g subjects.', r2, nSubjects));
                    nextProgressRow = r2 + progressStride;
                end
            end
            qc = NMDataIOFeatureQCTools.buildQCStruct(stats, caseIds, nFeatures, sum(validFeature), sourceLabel, opts);
            featureNames = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(opts, 'featureNames', {}), 'F', nFeatures);
            featureSpace = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'featureSpace', 'tabular_matrix'));
            [medianVec, madVec, robustAvailability, robustMessages] = NMDataIOFeatureQCTools.robustFeatureStatsFromMatrix(M, opts);
            messages = [messages; robustMessages];
            finiteMask = isfinite(M);
            validN = sum(finiteMask, 1);
            missingN = nSubjects - validN;
            zeroN = sum(finiteMask & abs(M) <= zeroTol, 1);
            minVec = minWithNaN(M, 1);
            maxVec = maxWithNaN(M, 1);
            m2Vec = (sdVec .^ 2) .* max(0, validN - 1);
            % Bounded, deterministic sampling of actual leave-one-out scores; no score is clipped.
            nSample = min(250000, numel(M));
            k = 0:nSample-1;
            sampleIdx = 1 + mod(floor(k .* (numel(M) / nSample)) + (nSample < numel(M)) .* mod(k,nSubjects),numel(M));
            sampleColumns = floor((sampleIdx - 1) ./ nSubjects) + 1;
            zSample = NMDataIOFeatureQCTools.computeSubjectZVector(M(sampleIdx),meanVec(sampleColumns),m2Vec(sampleColumns),validN(sampleColumns));
            zSample = zSample(isfinite(zSample));
            qc.cohortZWindow = [NaN NaN];
            if ~isempty(zSample)
                qc.cohortZWindow = prctile(zSample,[1 99]);
            end
            qc.featureStats = NMDataIOFeatureQCTools.buildFeatureStatsStruct(featureNames, validN, missingN, zeroN, ...
                meanVec, sdVec, medianVec, madVec, minVec, maxVec, outlierCount, nSubjects, featureSpace, opts, robustAvailability);
            qc.featureSpace = featureSpace;
            if strcmp(featureSpace, 'roi_field')
                roiProvenance = opts.roiProvenance;
                qc.roiProvenance = roiProvenance;
                spatialKinds = arrayfun(@(r)NMDataIOFeatureQCTools.asChar(r.kind), roiProvenance.spatialReferences, 'UniformOutput', false);
                qc.spatialMapping = struct('type','roi_field','spatialReferenceKinds',{spatialKinds}, ...
                    'materialization','exact_roi_parcel_expansion');
                roiQCStats = struct('meanVec',meanVec,'sdVec',sdVec,'countVec',validN, ...
                    'zeroCount',zeroN,'outlierCount',outlierCount,'nSubjects',nSubjects,'cohortZWindow',qc.cohortZWindow);
                [viewerOverlay, overlayMessages] = NMDataIOFeatureQCTools.exportROIViewerReferenceCache( ...
                    M, qc.caseIds, featureNames, NMDataIOFeatureQCTools.fieldOr(opts,'roiLabels',[]), ...
                    roiProvenance, opts, roiQCStats);
                qc.viewerOverlay = viewerOverlay;
                messages = [messages; overlayMessages];
            end
            qc = NMDataIOFeatureQCTools.attachReportPayload(qc);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.matrix', ...
                sprintf('Computed feature-QC outlier scores for %g subject(s) across %g/%g valid feature(s).', nSubjects, sum(validFeature), nFeatures), 0, 'green*')];
        end

        function [mask, messages] = supportMaskFromSpaceDef(maskVol, IO, messageSource)
            if nargin < 3 || isempty(messageSource), messageSource = 'featureQC.mask'; end
            messages = NMDataIOMessageTools.emptyMessages();
            mask = [];
            isAtlas = strcmpi(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(IO, 'spaceDefType', 'brainmask')), 'atlas');
            tol = 1e-6;
            if isAtlas
                if ndims(maskVol) > 3
                    mask = any(isfinite(maskVol) & maskVol > tol, 4);
                else
                    mask = isfinite(maskVol) & maskVol > tol;
                end
                if ~any(mask(:))
                    messages = [messages; NMDataIOMessageTools.make('danger', true, messageSource, ...
                        'Atlas mode feature QC could not derive a non-zero support mask from the selected atlas.', 1, 'red*')];
                    return;
                end
                messages = [messages; NMDataIOMessageTools.make('info', false, messageSource, ...
                    'Atlas mode: feature QC uses the non-zero atlas support mask; ROI extraction/collapse still uses the original atlas labels or weights.', 0, 'blue')];
            else
                finiteMask = maskVol(isfinite(maskVol));
                if isempty(finiteMask) || ~all(abs(finiteMask(:)) <= tol | abs(finiteMask(:) - 1) <= tol)
                    messages = [messages; NMDataIOMessageTools.make('danger', true, messageSource, ...
                        'Selected brainmask is not binary within tolerance 1e-6. Feature QC uses binary brainmask-space semantics unless atlas mode is enabled.', 1, 'red*')];
                    return;
                end
                mask = abs(maskVol - 1) <= tol;
            end
            if ndims(mask) > 3, mask = any(mask, 4); end
            mask = logical(mask);
        end

        function x = sampleImageInMaskSpace(Vi, Vm, mask)
            nVox = nnz(mask);
            x = nan(1, nVox);
            pos = 1;
            for sl = 1:Vm.dim(3)
                msk = mask(:,:,sl);
                n = nnz(msk);
                if n == 0, continue; end
                M0 = spm_matrix([0 0 sl 0 0 0 1 1 1]);
                M1 = Vm.mat \ Vi.mat \ M0;
                imgSlice = double(spm_slice_vol(Vi, M1, Vm.dim(1:2), 1));
                vals = imgSlice(msk);
                x(pos:(pos+n-1)) = vals(:)';
                pos = pos + n;
            end
        end

        function stats = emptyScoreArrays(nSubjects)
            stats.rowIndex = (1:nSubjects)';
            stats.score = nan(nSubjects,1);
            stats.rmsZ = nan(nSubjects,1);
            stats.meanAbsZ = nan(nSubjects,1);
            stats.meanZ = nan(nSubjects,1);
            stats.sdZ = nan(nSubjects,1);
            stats.maxAbsZ = nan(nSubjects,1);
            stats.nValidFeatures = zeros(nSubjects,1);
            stats.nFiniteFeatures = zeros(nSubjects,1);
            stats.nMissingFeatures = zeros(nSubjects,1);
            stats.missingFeatureRate = nan(nSubjects,1);
            stats.nZeroFeatures = zeros(nSubjects,1);
            stats.zeroFeatureRate = nan(nSubjects,1);
            stats.nOutlierFeatures = zeros(nSubjects,1);
            stats.outlierFeatureRate = nan(nSubjects,1);
            stats.rowAllNaNFlag = false(nSubjects,1);
            stats.rowConstantFlag = false(nSubjects,1);
        end

        function [qc, messages] = attachOOCVReferenceShift(qc, IO, opts)
            % attachOOCVReferenceShift  Compare an OOCV modality with its committed training reference.
            % Uses the retained OOCV matrix and persisted training QC moments; it never rereads training feature data or mutates source data.
            messages = NMDataIOMessageTools.emptyMessages();
            if nargin < 3 || ~isstruct(opts) || ~isfield(opts,'ReferenceNM') || ~isstruct(opts.ReferenceNM), return; end
            NM = opts.ReferenceNM;
            if ~isstruct(IO) || ~isfield(IO,'importTarget') || ~isstruct(IO.importTarget), return; end
            target = NMDataIOImportTargetTools.normalize(NM, IO.importTarget, NMDataIOFeatureQCTools.fieldOr(IO,'varind',1));
            if ~strcmpi(target.scope,'oocv'), return; end
            Y = NMDataIOFeatureQCTools.fieldOr(IO,'Y',[]);
            if ~(isnumeric(Y) || islogical(Y)) || ~ismatrix(Y) || isempty(Y), return; end
            Y = double(Y);
            nFeatures = size(Y,2);
            nPreparedCases = size(Y,1);
            paddingRows = false(nPreparedCases,1);
            importReport = NMDataIOFeatureQCTools.fieldOr(IO, 'importReport', struct());
            if isstruct(importReport) && logical(NMDataIOFeatureQCTools.fieldOr(importReport, 'missingCasesFilledWithNaN', false))
                alignmentReport = NMDataIOFeatureQCTools.fieldOr(importReport, 'caseAlignment', struct());
                missingCases = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(alignmentReport, 'missingCases', {}));
                alignedCaseIds = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO, 'ID', {}), 'S', nPreparedCases);
                if ~isempty(missingCases) && numel(alignedCaseIds) == nPreparedCases
                    paddingRows = ismember(alignedCaseIds(:), missingCases(:));
                end
            end
            observedRows = ~paddingRows;
            observedY = Y(observedRows,:);
            nObservedCases = nnz(observedRows);
            nAlignmentOnlyMissingCases = nnz(paddingRows);
            [trainMean, trainSD, trainMissing, trainOutlier, available] = NMDataIOFeatureQCTools.trainingReferenceMoments(NM, target.varind, nFeatures);
            if ~available
                messages = [messages; NMDataIOMessageTools.make('info', false, 'oocv.referenceShift', ...
                    sprintf('Training/OOCV distribution-shift QC was not computed for modality %d because compatible training reference moments are unavailable.', target.varind), 0, 'blue')];
                return;
            end
            oMean = nanmeanCompat(observedY,1);
            oSD = nanstdCompat(observedY,0,1);
            oMissing = sum(~isfinite(observedY),1) ./ max(1,nObservedCases);
            validMean = isfinite(trainMean) & isfinite(trainSD) & trainSD > 0 & isfinite(oMean);
            smd = nan(1,nFeatures); smd(validMean) = abs(oMean(validMean)-trainMean(validMean)) ./ trainSD(validMean);
            validVar = validMean & isfinite(oSD) & oSD >= 0;
            vr = nan(1,nFeatures); vr(validVar) = (oSD(validVar).^2) ./ (trainSD(validVar).^2);
            validMissing = isfinite(trainMissing) & isfinite(oMissing);
            missingIncrease = nan(1,nFeatures); missingIncrease(validMissing) = oMissing(validMissing)-trainMissing(validMissing);
            thresholds = struct('medianAbsSMD',0.5,'featureAbsSMD',0.8,'fractionAbsSMDGE08',0.10, ...
                'varianceRatioLow',0.5,'varianceRatioHigh',2,'fractionVarianceOutside',0.10, ...
                'meanMissingIncrease',0.05,'featureMissingIncrease',0.10,'fractionMissingIncrease',0.10, ...
                'outlierZ',3,'outlierAbsoluteIncrease',0.02,'outlierRatio',2);
            zThreshold = thresholds.outlierZ;
            outlierN = 0; finiteN = 0;
            outlierByFeatureN = zeros(1,nFeatures); finiteByFeatureN = zeros(1,nFeatures);
            caseMissingRate = nan(nPreparedCases,1);
            caseMissingRate(observedRows) = sum(~isfinite(Y(observedRows,:)),2) ./ max(1,nFeatures);
            caseOutlierRate = nan(nPreparedCases,1);
            observedIndex = find(observedRows(:));
            maxChunkElements = 2e6;
            rowsPerChunk = max(1, floor(maxChunkElements ./ max(1,nFeatures)));
            for q1 = 1:rowsPerChunk:numel(observedIndex)
                q2 = min(numel(observedIndex), q1 + rowsPerChunk - 1);
                rows = observedIndex(q1:q2);
                C = Y(rows,:);
                valid = isfinite(C) & validMean;
                Z = abs((C - trainMean) ./ trainSD);
                Z(~valid) = NaN;
                hits = valid & Z >= zThreshold;
                validN = sum(valid,2);
                hitN = sum(hits,2);
                outlierN = outlierN + nnz(hits);
                finiteN = finiteN + nnz(valid);
                outlierByFeatureN = outlierByFeatureN + sum(hits,1);
                finiteByFeatureN = finiteByFeatureN + sum(valid,1);
                caseOutlierRate(rows) = hitN ./ max(1,validN);
                caseOutlierRate(rows(validN < 1)) = NaN;
            end
            oOutlier = outlierN ./ max(1,finiteN);
            oOutlierByFeature = outlierByFeatureN ./ max(1,finiteByFeatureN);
            oOutlierByFeature(finiteByFeatureN < 1) = NaN;
            trainOutlierMean = meanWithNaN(trainOutlier(validMean));
            finiteSMD = smd(isfinite(smd));
            if isempty(finiteSMD), medSMD = NaN; else, medSMD = median(finiteSMD); end
            fracSMD = sum(smd >= thresholds.featureAbsSMD) ./ max(1,nnz(isfinite(smd)));
            fracVR = sum(vr < thresholds.varianceRatioLow | vr > thresholds.varianceRatioHigh) ./ max(1,nnz(isfinite(vr)));
            meanTrainMissing = meanWithNaN(trainMissing);
            meanOOCVMissing = meanWithNaN(oMissing);
            fracMissing = sum(missingIncrease >= thresholds.featureMissingIncrease) ./ max(1,nnz(isfinite(missingIncrease)));
            meanFlag = medSMD >= thresholds.medianAbsSMD || fracSMD >= thresholds.fractionAbsSMDGE08;
            varianceFlag = fracVR >= thresholds.fractionVarianceOutside;
            missingFlag = (meanOOCVMissing-meanTrainMissing) >= thresholds.meanMissingIncrease || fracMissing >= thresholds.fractionMissingIncrease;
            outlierFlag = isfinite(trainOutlierMean) && oOutlier >= max(trainOutlierMean + thresholds.outlierAbsoluteIncrease, thresholds.outlierRatio*trainOutlierMean);

            featureContributors = struct('available',false,'computed',false,'featureIndex',[],'featureNames',{{}},'criteria',{{}}, ...
                'absStandardizedMeanDifference',[],'varianceRatio',[],'trainingMissingRate',[],'oocvMissingRate',[], ...
                'missingRateIncrease',[],'trainingOutlierRate',[],'oocvOutlierRate',[]);
            lowDimensional = isfield(qc,'featureStats') && isstruct(qc.featureStats) && ...
                isfield(qc.featureStats,'fullReturned') && logical(qc.featureStats.fullReturned) && ...
                isfield(qc.featureStats,'featureNames') && numel(qc.featureStats.featureNames) == nFeatures;
            if lowDimensional && any([meanFlag varianceFlag missingFlag outlierFlag])
                featureContributors.computed = true;
                names = NMDataIOFeatureQCTools.asCellstr(qc.featureStats.featureNames, 'F', nFeatures);
                severity = zeros(1,nFeatures); criteria = repmat({''},1,nFeatures);
                if meanFlag
                    idx = isfinite(smd) & smd > 0;
                    severity(idx) = max(severity(idx), smd(idx) ./ thresholds.featureAbsSMD);
                    for j = find(idx), criteria{j} = 'mean shift'; end
                end
                if varianceFlag
                    idx = isfinite(vr) & (vr < thresholds.varianceRatioLow | vr > thresholds.varianceRatioHigh);
                    vscore = zeros(1,nFeatures);
                    hi = idx & vr > thresholds.varianceRatioHigh; lo = idx & vr < thresholds.varianceRatioLow & vr > 0;
                    vscore(hi) = vr(hi) ./ thresholds.varianceRatioHigh;
                    vscore(lo) = thresholds.varianceRatioLow ./ vr(lo);
                    severity(idx) = max(severity(idx), vscore(idx));
                    for j = find(idx), if isempty(criteria{j}), criteria{j} = 'variance'; else, criteria{j} = [criteria{j} ', variance']; end, end
                end
                if missingFlag
                    idx = isfinite(missingIncrease) & missingIncrease > 0;
                    severity(idx) = max(severity(idx), missingIncrease(idx) ./ thresholds.featureMissingIncrease);
                    for j = find(idx), if isempty(criteria{j}), criteria{j} = 'missingness'; else, criteria{j} = [criteria{j} ', missingness']; end, end
                end
                if outlierFlag
                    outlierIncrease = oOutlierByFeature - trainOutlier;
                    idx = isfinite(outlierIncrease) & outlierIncrease > 0;
                    denom = max(thresholds.outlierAbsoluteIncrease, trainOutlier);
                    denom(~isfinite(denom) | denom <= 0) = thresholds.outlierAbsoluteIncrease;
                    severity(idx) = max(severity(idx), outlierIncrease(idx) ./ denom(idx));
                    for j = find(idx), if isempty(criteria{j}), criteria{j} = 'outlier burden'; else, criteria{j} = [criteria{j} ', outlier burden']; end, end
                end
                hit = find(severity > 0 & isfinite(severity));
                if ~isempty(hit)
                    [~,ord] = sort(severity(hit),'descend'); hit = hit(ord(1:min(12,numel(ord))));
                    featureContributors.available = true;
                    featureContributors.featureIndex = double(hit(:)');
                    featureContributors.featureNames = names(hit);
                    featureContributors.criteria = criteria(hit);
                    featureContributors.absStandardizedMeanDifference = smd(hit);
                    featureContributors.varianceRatio = vr(hit);
                    featureContributors.trainingMissingRate = trainMissing(hit);
                    featureContributors.oocvMissingRate = oMissing(hit);
                    featureContributors.missingRateIncrease = missingIncrease(hit);
                    featureContributors.trainingOutlierRate = trainOutlier(hit);
                    featureContributors.oocvOutlierRate = oOutlierByFeature(hit);
                end
            end

            caseContributors = struct('available',false,'computed',false,'caseIndex',[],'caseIds',{{}},'criteria',{{}}, ...
                'missingRate',[],'excessMissingRate',[],'outlierRate',[],'excessOutlierRate',[]);
            if lowDimensional && (missingFlag || outlierFlag) && isfield(qc,'caseIds') && numel(qc.caseIds) == size(Y,1)
                caseContributors.computed = true;
                caseIds = NMDataIOFeatureQCTools.asCellstr(qc.caseIds, 'S', size(Y,1));
                severity = zeros(size(Y,1),1); criteria = repmat({''},size(Y,1),1);
                excessMissing = caseMissingRate - meanTrainMissing;
                excessOutlier = caseOutlierRate - trainOutlierMean;
                if missingFlag
                    idx = isfinite(excessMissing) & excessMissing > 0;
                    severity(idx) = max(severity(idx), excessMissing(idx) ./ thresholds.meanMissingIncrease);
                    for j = find(idx(:))', criteria{j} = 'missingness'; end
                end
                if outlierFlag && isfinite(trainOutlierMean)
                    idx = isfinite(excessOutlier) & excessOutlier > 0;
                    denom = max(thresholds.outlierAbsoluteIncrease, trainOutlierMean*(thresholds.outlierRatio-1));
                    severity(idx) = max(severity(idx), excessOutlier(idx) ./ denom);
                    for j = find(idx(:))', if isempty(criteria{j}), criteria{j} = 'outlier burden'; else, criteria{j} = [criteria{j} ', outlier burden']; end, end
                end
                hit = find(severity > 0 & isfinite(severity));
                if ~isempty(hit)
                    [~,ord] = sort(severity(hit),'descend'); hit = hit(ord(1:min(12,numel(ord))));
                    caseContributors.available = true;
                    caseContributors.caseIndex = double(hit(:)');
                    caseContributors.caseIds = caseIds(hit);
                    caseContributors.criteria = criteria(hit)';
                    caseContributors.missingRate = double(caseMissingRate(hit)');
                    caseContributors.excessMissingRate = double(excessMissing(hit)');
                    caseContributors.outlierRate = double(caseOutlierRate(hit)');
                    caseContributors.excessOutlierRate = double(excessOutlier(hit)');
                end
            end

            qc.referenceShift = struct('schemaVersion',2,'status',NMDataIOFeatureQCTools.ternaryChar(any([meanFlag varianceFlag missingFlag outlierFlag]),'warning','ok'), ...
                'meanFlag',meanFlag,'varianceFlag',varianceFlag,'missingnessFlag',missingFlag,'outliernessFlag',outlierFlag, ...
                'medianAbsStandardizedMeanDifference',medSMD,'fractionAbsStandardizedMeanDifferenceGE08',fracSMD, ...
                'fractionVarianceRatioOutsideHalfToTwo',fracVR,'meanTrainingMissingRate',meanTrainMissing, ...
                'meanOOCVMissingRate',meanOOCVMissing,'fractionMissingRateIncreaseGE10pp',fracMissing, ...
                'trainingOutlierRate',trainOutlierMean,'oocvOutlierRateAgainstTraining',oOutlier, ...
                'nPreparedCases',double(nPreparedCases),'nObservedCases',double(nObservedCases), ...
                'nAlignmentOnlyMissingCases',double(nAlignmentOnlyMissingCases), ...
                'nComparedFeatures',double(nnz(validMean)),'featureContributors',featureContributors,'caseContributors',caseContributors, ...
                'thresholds',thresholds);
            if isfield(qc,'reportPayload') && isstruct(qc.reportPayload) && isfield(qc.reportPayload,'summaryRows')
                rows = qc.reportPayload.summaryRows;
                rows(end+1).metric = 'OOCV median |standardized mean shift|'; rows(end).value = medSMD;
                rows(end+1).metric = 'OOCV features with >2x/<0.5x variance'; rows(end).value = fracVR;
                rows(end+1).metric = 'OOCV mean missingness'; rows(end).value = meanOOCVMissing;
                rows(end+1).metric = 'OOCV training-referenced outlier rate'; rows(end).value = oOutlier;
                qc.reportPayload.summaryRows = rows;
            end
            if any([meanFlag varianceFlag missingFlag outlierFlag])
                parts = {};
                if meanFlag, parts{end+1} = 'mean'; end %#ok<AGROW>
                if varianceFlag, parts{end+1} = 'variance'; end %#ok<AGROW>
                if missingFlag, parts{end+1} = 'missingness'; end %#ok<AGROW>
                if outlierFlag, parts{end+1} = 'outlier burden'; end %#ok<AGROW>
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'oocv.referenceShift', ...
                    sprintf('OOCV modality %d differs substantially from the training reference in %s. Review QC before model application; this warning does not block import.', target.varind, strjoin(parts, ', ')), 2, 'orange')];
            else
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'oocv.referenceShift', ...
                    sprintf('OOCV modality %d shows no substantial training-reference discrepancy in mean, variance, missingness, or outlier burden.', target.varind), 0, 'green*')];
            end
        end

    end

    methods (Static, Access = public)
        function rs = referenceShiftForBrowser(rs, trainQC, oocvQC)
            % referenceShiftForBrowser  Rehydrate compact OOCV attribution from persisted QC moments and return browser-safe vectors.
            % Existing referenceShift flags/thresholds remain authoritative; this method never rereads feature data or recomputes warning status.
            if ~isstruct(rs) || isempty(fieldnames(rs)), return; end
            if nargin < 2 || ~isstruct(trainQC), trainQC = struct(); end
            if nargin < 3 || ~isstruct(oocvQC), oocvQC = struct(); end
            thresholds = NMDataIOFeatureQCTools.fieldOr(rs,'thresholds',struct());
            meanFlag = logical(NMDataIOFeatureQCTools.fieldOr(rs,'meanFlag',false));
            varianceFlag = logical(NMDataIOFeatureQCTools.fieldOr(rs,'varianceFlag',false));
            missingFlag = logical(NMDataIOFeatureQCTools.fieldOr(rs,'missingnessFlag',false));

            haveFeatureContributors = isfield(rs,'featureContributors') && isstruct(rs.featureContributors) && ...
                logical(NMDataIOFeatureQCTools.fieldOr(rs.featureContributors,'available',false));
            featureAttributionComputed = isfield(rs,'featureContributors') && isstruct(rs.featureContributors) && ...
                logical(NMDataIOFeatureQCTools.fieldOr(rs.featureContributors,'computed',false));
            if ~haveFeatureContributors && any([meanFlag varianceFlag missingFlag]) && ...
                    isfield(trainQC,'featureStats') && isstruct(trainQC.featureStats) && ...
                    isfield(oocvQC,'featureStats') && isstruct(oocvQC.featureStats)
                tf = trainQC.featureStats; of = oocvQC.featureStats;
                fullTraining = logical(NMDataIOFeatureQCTools.fieldOr(tf,'fullReturned',false));
                fullOOCV = logical(NMDataIOFeatureQCTools.fieldOr(of,'fullReturned',false));
                required = {'mean','std','missingRate'};
                ready = fullTraining && fullOOCV;
                for k = 1:numel(required)
                    ready = ready && isfield(tf,required{k}) && isnumeric(tf.(required{k})) && ...
                        isfield(of,required{k}) && isnumeric(of.(required{k}));
                end
                if ready
                    nFeatures = min([numel(tf.mean),numel(tf.std),numel(tf.missingRate),numel(of.mean),numel(of.std),numel(of.missingRate)]);
                    if nFeatures > 0
                        trainMean = double(tf.mean(1:nFeatures)); trainSD = double(tf.std(1:nFeatures));
                        trainMissing = double(tf.missingRate(1:nFeatures));
                        oMean = double(of.mean(1:nFeatures)); oSD = double(of.std(1:nFeatures)); oMissing = double(of.missingRate(1:nFeatures));
                        smd = nan(1,nFeatures); validMean = isfinite(trainMean) & isfinite(trainSD) & trainSD > 0 & isfinite(oMean);
                        smd(validMean) = abs(oMean(validMean)-trainMean(validMean))./trainSD(validMean);
                        vr = nan(1,nFeatures); validVar = validMean & isfinite(oSD) & oSD >= 0;
                        vr(validVar) = (oSD(validVar).^2)./(trainSD(validVar).^2);
                        missingIncrease = oMissing-trainMissing;
                        severity = zeros(1,nFeatures); criteria = repmat({''},1,nFeatures);
                        if meanFlag
                            t = double(NMDataIOFeatureQCTools.fieldOr(thresholds,'featureAbsSMD',0.8));
                            if ~isfinite(t) || t <= 0, t = 0.8; end
                            idx = isfinite(smd) & smd > 0;
                            severity(idx) = max(severity(idx),smd(idx)./t);
                            for j=find(idx), criteria{j}='mean shift'; end
                        end
                        if varianceFlag
                            lo = double(NMDataIOFeatureQCTools.fieldOr(thresholds,'varianceRatioLow',0.5));
                            hi = double(NMDataIOFeatureQCTools.fieldOr(thresholds,'varianceRatioHigh',2));
                            idx = isfinite(vr) & (vr < lo | vr > hi);
                            vscore=zeros(1,nFeatures); ih=idx & vr>hi; il=idx & vr<lo & vr>0;
                            vscore(ih)=vr(ih)./hi; vscore(il)=lo./vr(il);
                            severity(idx)=max(severity(idx),vscore(idx));
                            for j=find(idx), if isempty(criteria{j}), criteria{j}='variance'; else, criteria{j}=[criteria{j} ', variance']; end, end
                        end
                        if missingFlag
                            t = double(NMDataIOFeatureQCTools.fieldOr(thresholds,'featureMissingIncrease',0.10));
                            if ~isfinite(t) || t <= 0, t = 0.10; end
                            idx = isfinite(missingIncrease) & missingIncrease > 0;
                            severity(idx)=max(severity(idx),missingIncrease(idx)./t);
                            for j=find(idx), if isempty(criteria{j}), criteria{j}='missingness'; else, criteria{j}=[criteria{j} ', missingness']; end, end
                        end
                        hit=find(severity>0 & isfinite(severity));
                        if ~isempty(hit)
                            [~,ord]=sort(severity(hit),'descend'); hit=hit(ord(1:min(12,numel(ord))));
                            names = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(of,'featureNames',{}),'F',nFeatures);
                            rs.featureContributors = struct('available',true,'computed',true,'featureIndex',double(hit(:)'), ...
                                'featureNames',{names(hit)},'criteria',{criteria(hit)}, ...
                                'absStandardizedMeanDifference',smd(hit),'varianceRatio',vr(hit), ...
                                'trainingMissingRate',trainMissing(hit),'oocvMissingRate',oMissing(hit), ...
                                'missingRateIncrease',missingIncrease(hit),'trainingOutlierRate',nan(1,numel(hit)), ...
                                'oocvOutlierRate',nan(1,numel(hit)),'source','persisted_qc_moments');
                        end
                    end
                end
            end

            haveCaseContributors = isfield(rs,'caseContributors') && isstruct(rs.caseContributors) && ...
                logical(NMDataIOFeatureQCTools.fieldOr(rs.caseContributors,'available',false));
            caseAttributionComputed = isfield(rs,'caseContributors') && isstruct(rs.caseContributors) && ...
                logical(NMDataIOFeatureQCTools.fieldOr(rs.caseContributors,'computed',false));
            lowDimensional = isfield(oocvQC,'featureStats') && isstruct(oocvQC.featureStats) && ...
                logical(NMDataIOFeatureQCTools.fieldOr(oocvQC.featureStats,'fullReturned',false));
            if ~haveCaseContributors && ~caseAttributionComputed && lowDimensional && missingFlag
                missingRate = []; caseIds = {};
                if isfield(oocvQC,'missingFeatureRateBySubject') && isnumeric(oocvQC.missingFeatureRateBySubject) && ...
                        isfield(oocvQC,'caseIds') && ~isempty(oocvQC.caseIds)
                    missingRate = double(oocvQC.missingFeatureRateBySubject(:));
                    caseIds = NMDataIOFeatureQCTools.asCellstr(oocvQC.caseIds,'S',numel(missingRate));
                elseif isfield(oocvQC,'subjectStats') && isstruct(oocvQC.subjectStats) && ...
                        isfield(oocvQC.subjectStats,'missingFeatureRate') && isnumeric(oocvQC.subjectStats.missingFeatureRate) && ...
                        isfield(oocvQC.subjectStats,'caseIds') && ~isempty(oocvQC.subjectStats.caseIds)
                    missingRate = double(oocvQC.subjectStats.missingFeatureRate(:));
                    caseIds = NMDataIOFeatureQCTools.asCellstr(oocvQC.subjectStats.caseIds,'S',numel(missingRate));
                end
                if ~isempty(missingRate) && ~isempty(caseIds)
                    baseline = double(NMDataIOFeatureQCTools.fieldOr(rs,'meanTrainingMissingRate',0));
                    excess = missingRate-baseline;
                    hit=find(isfinite(excess) & excess>0);
                    if ~isempty(hit)
                        [~,ord]=sort(excess(hit),'descend'); hit=hit(ord(1:min(12,numel(ord))));
                        rs.caseContributors = struct('available',true,'computed',true,'caseIndex',double(hit(:)'), ...
                            'caseIds',{caseIds(hit)},'criteria',{repmat({'missingness'},1,numel(hit))}, ...
                            'missingRate',double(missingRate(hit)'),'excessMissingRate',double(excess(hit)'), ...
                            'outlierRate',nan(1,numel(hit)),'excessOutlierRate',nan(1,numel(hit)), ...
                            'source','persisted_qc_moments');
                    end
                end
            end

            if isfield(rs,'featureContributors') && isstruct(rs.featureContributors)
                fc = rs.featureContributors;
                fields = {'featureIndex','absStandardizedMeanDifference','varianceRatio','trainingMissingRate','oocvMissingRate','missingRateIncrease','trainingOutlierRate','oocvOutlierRate'};
                for k=1:numel(fields)
                    if isfield(fc,fields{k}) && isnumeric(fc.(fields{k})) && numel(fc.(fields{k}))>1, fc.(fields{k})=num2cell(fc.(fields{k})(:)' ); end
                end
                rs.featureContributors=fc;
            end
            if isfield(rs,'caseContributors') && isstruct(rs.caseContributors)
                cc = rs.caseContributors;
                fields = {'caseIndex','missingRate','excessMissingRate','outlierRate','excessOutlierRate'};
                for k=1:numel(fields)
                    if isfield(cc,fields{k}) && isnumeric(cc.(fields{k})) && numel(cc.(fields{k}))>1, cc.(fields{k})=num2cell(cc.(fields{k})(:)' ); end
                end
                rs.caseContributors=cc;
            end
        end

    end

    methods (Static, Access = private)
        function [meanVec, sdVec, missingRate, outlierRate, available] = trainingReferenceMoments(NM, varind, nFeatures)
            meanVec = nan(1,nFeatures); sdVec = nan(1,nFeatures); missingRate = nan(1,nFeatures); outlierRate = nan(1,nFeatures); available = false;
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind}) || ~isfield(NM.datadescriptor{varind},'QC') || ...
                    ~isstruct(NM.datadescriptor{varind}.QC) || ~isfield(NM.datadescriptor{varind}.QC,'payload') || ...
                    ~isstruct(NM.datadescriptor{varind}.QC.payload)
                return;
            end
            q = NM.datadescriptor{varind}.QC.payload;
            if isfield(q,'featureStats') && isstruct(q.featureStats) && isfield(q.featureStats,'fullReturned') && q.featureStats.fullReturned && ...
                    isfield(q.featureStats,'mean') && numel(q.featureStats.mean) == nFeatures
                fs = q.featureStats;
                meanVec = double(fs.mean(:)'); sdVec = double(fs.std(:)'); missingRate = double(fs.missingRate(:)'); outlierRate = double(fs.outlierRate(:)');
                available = true;
                return;
            end
            if isfield(q,'viewerOverlay') && isstruct(q.viewerOverlay)
                cacheFile = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(q.viewerOverlay,'persistedCacheFile',''));
                if exist(cacheFile,'file') == 2
                    S = load(cacheFile, 'meanVec','sdVec','m2Vec','countVec','outlierCount','nSubjects');
                    if isfield(S,'meanVec') && isfield(S,'countVec') && numel(S.meanVec) == nFeatures && numel(S.countVec) == nFeatures
                        meanVec = double(S.meanVec(:)');
                        countVec = double(S.countVec(:)');
                        if isfield(S,'sdVec') && numel(S.sdVec) == nFeatures
                            sdVec = double(S.sdVec(:)');
                        elseif isfield(S,'m2Vec') && numel(S.m2Vec) == nFeatures
                            sdVec = sqrt(double(S.m2Vec(:)') ./ max(1, countVec - 1));
                            sdVec(countVec < 2) = NaN;
                        end
                        nSubjects = double(NMDataIOFeatureQCTools.fieldOr(S,'nSubjects', NMDataIOFeatureQCTools.fieldOr(q,'nSubjects',NaN)));
                        if isfinite(nSubjects) && nSubjects > 0
                            missingRate = (nSubjects - countVec) ./ nSubjects;
                        end
                        if isfield(S,'outlierCount') && numel(S.outlierCount) == nFeatures
                            outlierRate = double(S.outlierCount(:)') ./ max(1,countVec);
                            outlierRate(countVec < 1) = NaN;
                        end
                        available = numel(sdVec) == nFeatures && any(isfinite(meanVec) & isfinite(sdVec) & sdVec > 0);
                        if available, return; end
                    end
                end
            end
            if strcmp(q.sourceType,'connectivity')
                conn = q.connectivity;
                validateattributes(conn.edgeMean,{'numeric'},{'numel',nFeatures});
                validateattributes(conn.edgeSD,{'numeric'},{'numel',nFeatures});
                validateattributes(conn.edgeMissingRate,{'numeric'},{'numel',nFeatures});
                meanVec = conn.edgeMean(:)';
                sdVec = conn.edgeSD(:)';
                missingRate = conn.edgeMissingRate(:)';
                % Per-subject outlier burden is not a per-edge reference.
                available = any(isfinite(meanVec) & isfinite(sdVec) & sdVec > 0);
            end
        end

        function qc = buildQCStruct(stats, caseIds, nFeatures, nValidFeatures, sourceLabel, opts)
            if nargin < 6 || isempty(opts), opts = struct(); end
            qc = NMDataIOFeatureQCTools.emptyQC();
            qc.schemaVersion = 2;
            qc.sourceType = sourceLabel;
            qc.method = 'featurewise_population_zscore';
            qc.scoreName = 'RMS feature z-score';
            qc.primaryScore = 'rmsZ';
            qc.nSubjects = numel(stats.rowIndex);
            qc.nDataBearingSubjects = double(nnz(~stats.rowAllNaNFlag));
            qc.nFiniteScoreSubjects = double(nnz(isfinite(stats.rmsZ)));
            qc.nAllNaNSubjects = double(nnz(stats.rowAllNaNFlag));
            qc.nFeatures = double(nFeatures);
            qc.nValidFeatures = double(nValidFeatures);
            qc.rowIndex = stats.rowIndex(:)';
            qc.caseIds = NMDataIOFeatureQCTools.asCellstr(caseIds, 'S', qc.nSubjects);
            qc.score = stats.score(:)';
            qc.rmsZ = stats.rmsZ(:)';
            qc.rmsHistogram = NMDataIOFeatureQCTools.subjectMetricHistogramSpec(qc.rmsZ);
            qc.meanAbsZ = stats.meanAbsZ(:)';
            qc.meanZ = stats.meanZ(:)';
            qc.sdZ = stats.sdZ(:)';
            qc.maxAbsZ = stats.maxAbsZ(:)';
            qc.nValidFeaturesBySubject = stats.nValidFeatures(:)';
            qc.nFiniteFeaturesBySubject = stats.nFiniteFeatures(:)';
            qc.nMissingFeaturesBySubject = stats.nMissingFeatures(:)';
            qc.missingFeatureRateBySubject = stats.missingFeatureRate(:)';
            qc.nZeroFeaturesBySubject = stats.nZeroFeatures(:)';
            qc.zeroFeatureRateBySubject = stats.zeroFeatureRate(:)';
            qc.nOutlierFeaturesBySubject = stats.nOutlierFeatures(:)';
            qc.outlierFeatureRateBySubject = stats.outlierFeatureRate(:)';
            qc.rowAllNaNFlag = stats.rowAllNaNFlag(:)';
            qc.rowConstantFlag = stats.rowConstantFlag(:)';
            qc.outlierZThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'OutlierZThreshold', 3);
            qc.zeroTolerance = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'ZeroTolerance', 0);
            qc.subjectStats = NMDataIOFeatureQCTools.buildSubjectStatsStruct(stats, qc.caseIds, qc.outlierZThreshold);
            qc.description = 'Per-subject outlierness computed from feature-wise population z-scores. Primary score is RMS z across valid features; meanZ and sdZ summarize the signed z-score distribution over features. Enriched QC additionally reports missingness, zero rate, and outlier burden at subject and feature level where available.';
        end

        function subj = buildSubjectStatsStruct(stats, caseIds, zThreshold) %#ok<INUSD>
            subj = struct();
            subj.schemaVersion = 1;
            subj.level = 'subject';
            subj.fullReturned = false;
            subj.outlierZThreshold = double(zThreshold);
            subj.summary = struct('nAllNaNSubjects',double(nnz(stats.rowAllNaNFlag)), ...
                'nConstantSubjects',double(nnz(stats.rowConstantFlag)), ...
                'maxMissingFeatureRate',maxWithNaN(stats.missingFeatureRate(:)',2), ...
                'maxOutlierFeatureRate',maxWithNaN(stats.outlierFeatureRate(:)',2), ...
                'maxRmsZ',maxWithNaN(stats.rmsZ(:)',2));
        end

        function qc = emptyQC()
            qc = struct('schemaVersion',2,'sourceType','','featureSpace','','method','','scoreName','','primaryScore','', ...
                'nSubjects',0,'nDataBearingSubjects',0,'nFiniteScoreSubjects',0,'nAllNaNSubjects',0, ...
                'nFeatures',0,'nValidFeatures',0,'rowIndex',[], ...
                'caseIds',{{}},'score',[],'rmsZ',[],'meanAbsZ',[],'meanZ',[], ...
                'sdZ',[],'maxAbsZ',[],'cohortZWindow',[NaN NaN],'nValidFeaturesBySubject',[], 'nFiniteFeaturesBySubject',[], ...
                'nMissingFeaturesBySubject',[],'missingFeatureRateBySubject',[], ...
                'nZeroFeaturesBySubject',[],'zeroFeatureRateBySubject',[], ...
                'nOutlierFeaturesBySubject',[],'outlierFeatureRateBySubject',[], ...
                'rowAllNaNFlag',[],'rowConstantFlag',[], 'outlierZThreshold',3, 'zeroTolerance',0, ...
                'subjectStats',struct(), 'featureStats',struct(), 'referenceShift',struct(), 'rmsHistogram',struct(), 'reportPayload',struct(), 'dataIOAudit',struct(), 'description','', ...
                'viewerOverlay', struct('available',false,'cacheToken','','method','','thresholdDefault',3,'modeDefault','signed','metrics',{{}},'description',''));
        end

        function fs = buildFeatureStatsStruct(featureNames, validN, missingN, zeroN, meanVec, sdVec, medianVec, madVec, minVec, maxVec, outlierN, nSubjects, featureSpace, opts, availability)
            nFeatures = numel(validN);
            if isempty(medianVec), medianVec = nan(1,nFeatures); else, medianVec = double(medianVec(:)'); end
            if isempty(madVec), madVec = nan(1,nFeatures); else, madVec = double(madVec(:)'); end
            missingRate = missingN ./ max(1, double(nSubjects));
            zeroRate = zeroN ./ max(1, validN);
            outlierRate = outlierN ./ max(1, validN);
            constantFlag = validN > 0 & minVec == maxVec;
            nearConstTol = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'NearConstantSDTolerance', 1e-12);
            nearConstantFlag = validN > 1 & isfinite(sdVec) & sdVec <= nearConstTol;
            maxReturned = round(NMDataIOFeatureQCTools.qcOptionNumber(opts, 'MaxFeatureStatsInResponse', 5000));
            if ~isfinite(maxReturned) || maxReturned < 0, maxReturned = 5000; end
            fullReturned = nFeatures <= maxReturned;
            fs = struct();
            fs.schemaVersion = 1;
            fs.level = 'feature';
            fs.featureSpace = char(featureSpace);
            fs.nFeatures = double(nFeatures);
            fs.nSubjects = double(nSubjects);
            fs.fullReturned = fullReturned;
            fs.maxFeaturesReturned = double(maxReturned);
            fs.metricAvailability = NMDataIOFeatureQCTools.metricAvailability(availability, ~all(isnan(medianVec)), ~all(isnan(madVec)));
            fs.summary = struct('nFeatures',double(nFeatures), ...
                'nFeaturesWithMissing',double(nnz(missingN > 0)), ...
                'nAllMissingFeatures',double(nnz(validN == 0)), ...
                'meanMissingRate',meanWithNaN(missingRate), ...
                'maxMissingRate',maxWithNaN(missingRate,2), ...
                'nFeaturesWithZeros',double(nnz(zeroN > 0)), ...
                'meanZeroRate',meanWithNaN(zeroRate), ...
                'maxZeroRate',maxWithNaN(zeroRate,2), ...
                'nConstantFeatures',double(nnz(constantFlag)), ...
                'nNearConstantFeatures',double(nnz(nearConstantFlag)), ...
                'nFeaturesWithOutliers',double(nnz(outlierN > 0)), ...
                'meanOutlierRate',meanWithNaN(outlierRate), ...
                'maxOutlierRate',maxWithNaN(outlierRate,2), ...
                'meanRange',rangeStruct(meanVec), 'sdRange',rangeStruct(sdVec));
            fs.topMissing = NMDataIOFeatureQCTools.topFeatureSummary(featureNames, missingRate, missingN, 'missingRate', 20);
            fs.topOutlier = NMDataIOFeatureQCTools.topFeatureSummary(featureNames, outlierRate, outlierN, 'outlierRate', 20);
            fs.topZero = NMDataIOFeatureQCTools.topFeatureSummary(featureNames, zeroRate, zeroN, 'zeroRate', 20);
            if fullReturned
                fs.featureIndex = double(1:nFeatures);
                fs.featureNames = featureNames(:)';
                fs.validN = validN;
                fs.missingN = missingN;
                fs.missingRate = missingRate;
                fs.zeroN = zeroN;
                fs.zeroRate = zeroRate;
                fs.mean = meanVec;
                fs.median = medianVec;
                fs.std = sdVec;
                fs.mad = madVec;
                fs.min = minVec;
                fs.max = maxVec;
                fs.outlierN = outlierN;
                fs.outlierRate = outlierRate;
                fs.constantFlag = logical(constantFlag);
                fs.nearConstantFlag = logical(nearConstantFlag);
            else
                fs.omittedFeatureVectorsReason = sprintf('This dataset has %g features, which is above the browser detail limit of %g. Summary statistics and top-feature lists are shown; full spatial QC remains available in the image/surface viewer when supported.', nFeatures, maxReturned);
            end
        end

        function avail = metricAvailability(availability, hasMedian, hasMad)
            avail = struct();
            if isstruct(availability) && isfield(availability,'median')
                avail.median = availability.median;
            elseif hasMedian
                avail.median = 'computed';
            else
                avail.median = 'not_computed';
            end
            if isstruct(availability) && isfield(availability,'mad')
                avail.mad = availability.mad;
            elseif hasMad
                avail.mad = 'computed';
            else
                avail.mad = 'not_computed';
            end
            avail.mean = 'computed';
            avail.std = 'computed';
            avail.missingRate = 'computed';
            avail.zeroRate = 'computed';
            avail.outlierRate = 'computed_from_population_zscore';
        end

        function top = topFeatureSummary(featureNames, values, counts, valueName, k)
            if nargin < 5 || isempty(k), k = 20; end
            values = double(values(:));
            counts = double(counts(:));
            valid = find(isfinite(values) & values > 0);
            if isempty(valid)
                top = struct('featureIndex',[],'featureNames',{{}},'valueName',valueName,'values',[],'counts',[]);
                return;
            end
            [~,ord] = sort(values(valid), 'descend');
            idx = valid(ord(1:min(k,numel(ord))));
            top = struct('featureIndex',double(idx(:)'), 'featureNames',{featureNames(idx)'}, ...
                'valueName',valueName, 'values',double(values(idx)'), 'counts',double(counts(idx)'));
        end

        function [medianVec, madVec, availability, messages] = robustFeatureStatsFromMatrix(M, opts)
            messages = NMDataIOMessageTools.emptyMessages();
            maxElements = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'MaxRobustFeatureStatsElements', 1e7);
            nElem = double(numel(M));
            availability = struct('median','computed','mad','computed');
            if isfinite(maxElements) && nElem > maxElements
                medianVec = [];
                madVec = [];
                availability.median = sprintf('skipped_nElements_%g_exceeds_%g', nElem, maxElements);
                availability.mad = availability.median;
                messages = [messages; NMDataIOMessageTools.make('info', false, 'featureQC.robustStats', ...
                    sprintf('Feature median/MAD were not computed because %g data elements exceed MaxRobustFeatureStatsElements=%g. Mean/SD, missingness, zero rates, and z-score outlier rates were computed.', nElem, maxElements), 0, 'blue')];
                return;
            end
            medianVec = nanmedianCompat(M, 1);
            D = abs(M - medianVec);
            D(~isfinite(M)) = NaN;
            madVec = nanmedianCompat(D, 1);
        end

        function qc = attachReportPayload(qc)
            qc.reportPayload = struct();
            qc.reportPayload.schemaVersion = 1;
            qc.reportPayload.available = true;
            qc.reportPayload.title = 'DataIO feature quality-control report';
            qc.reportPayload.sourceType = qc.sourceType;
            qc.reportPayload.featureSpace = qc.featureSpace;
            qc.reportPayload.primaryScore = qc.primaryScore;
            qc.reportPayload.recommendedSections = {'overview','subject_qc_table','feature_qc_summary','top_problematic_features','spatial_qc_visualization_if_available'};
            rows = struct('metric',{},'value',{});
            rows(end+1).metric = 'Subjects'; rows(end).value = qc.nSubjects;
            rows(end+1).metric = 'Features'; rows(end).value = qc.nFeatures;
            rows(end+1).metric = 'Valid z-score features'; rows(end).value = qc.nValidFeatures;
            if isfield(qc,'subjectStats') && isstruct(qc.subjectStats) && isfield(qc.subjectStats,'summary')
                rows(end+1).metric = 'Max subject missing-feature rate'; rows(end).value = qc.subjectStats.summary.maxMissingFeatureRate;
                rows(end+1).metric = 'Max subject outlier-feature rate'; rows(end).value = qc.subjectStats.summary.maxOutlierFeatureRate;
                rows(end+1).metric = 'Max subject RMS z'; rows(end).value = qc.subjectStats.summary.maxRmsZ;
            end
            if isfield(qc,'featureStats') && isstruct(qc.featureStats) && isfield(qc.featureStats,'summary')
                rows(end+1).metric = 'Features with missing values'; rows(end).value = qc.featureStats.summary.nFeaturesWithMissing;
                rows(end+1).metric = 'Constant features'; rows(end).value = qc.featureStats.summary.nConstantFeatures;
                rows(end+1).metric = 'Features with outliers'; rows(end).value = qc.featureStats.summary.nFeaturesWithOutliers;
            end
            qc.reportPayload.summaryRows = rows;
            qc.reportPayload.subjectTableFields = {'caseIds','rmsZ','missingFeatureRate','zeroFeatureRate','outlierFeatureRate','rowAllNaNFlag','rowConstantFlag'};
            qc.reportPayload.featureTableFields = {'featureNames','missingRate','zeroRate','mean','median','std','mad','min','max','outlierRate','constantFlag','nearConstantFlag'};
            qc.reportPayload.notes = {'These QC results are ready for report export. HTML/PDF generation is handled by the report export step.', 'Spatial images or surface snapshots are added by the visualization/report export workflow.'};
        end

        function ids = caseIdsFromImageIO(IO, files, nSubjects)
            ids = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO, 'explicitCaseIDs', {}));
            if numel(ids) == nSubjects, ids = ids(:); return; end
            ids = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(IO, 'ID', {}));
            if numel(ids) == nSubjects, ids = ids(:); return; end
            ids = cell(nSubjects,1);
            for i = 1:nSubjects
                if i <= numel(files) && ~isempty(files{i})
                    [~,stem] = fileparts(regexprep(files{i}, '\.gz$', '', 'ignorecase'));
                    ids{i} = stem;
                else
                    ids{i} = sprintf('S%g', i);
                end
            end
        end

        function out = emptyFeatureProfile()
            out = struct('ok',false,'message','Tabular feature profile not prepared.', ...
                'rowIndex',NaN,'caseId','','label',[], 'nFeatures',0,'nValidFeatures',0, ...
                'nObservedFeatures',0,'nMissingFeatures',0,'nUnscorableFeatures',0, ...
                'featureIndex',[],'featureNames',{{}},'z',[],'raw',[], ...
                'plotMode','exact','highDimensional',false,'histCounts',[],'histEdges',[], ...
                'binStart',[],'binEnd',[],'binMinZ',[],'binMaxZ',[],'binMissingN',[],'binFeatureN',[], ...
                'topFeatureIndex',[],'topFeatureNames',{{}},'topRaw',[],'topZ',[],'topMissing',[], ...
                'detailOnly',false,'detailSource','','detailLabel','','detailTotal',0, ...
                'detailFeatureIndex',[],'detailFeatureNames',{{}},'detailRaw',[],'detailZ',[],'detailMissing',[], ...
                'meanAbsZ',NaN,'rmsZ',NaN,'maxAbsZ',NaN,'maxPoints',0,'downsampled',false);
        end

        function out = prepareFeatureProfileFromAxes(M, featureNames, caseIds, labels, rowIndex, opts, messages, messageSource)
            % prepareFeatureProfileFromAxes  Calculate one retained case profile and bounded tabular display payload.
            out = NMDataIOFeatureQCTools.emptyFeatureProfile();
            rowIndex = round(double(rowIndex));
            if ~isfinite(rowIndex) || rowIndex < 1
                messages = [messages; NMDataIOMessageTools.make('danger', true, messageSource, ...
                    'A valid one-based case row index is required for the tabular feature-QC viewer.', 1, 'red*')];
                out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
                return;
            end
            if isempty(M) || ~isnumeric(M) || ~ismatrix(M)
                messages = [messages; NMDataIOMessageTools.make('danger', true, messageSource, ...
                    'Tabular feature inspection requires a numeric two-dimensional feature matrix.', 1, 'red*')];
                out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
                return;
            end
            if rowIndex > size(M,1)
                messages = [messages; NMDataIOMessageTools.make('danger', true, messageSource, ...
                    sprintf('Requested row %g exceeds the available %g case row(s).', rowIndex, size(M,1)), 1, 'red*')];
                out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
                return;
            end
            featureNames = NMDataIOFeatureQCTools.asCellstr(featureNames, 'F', size(M,2));
            caseIds = NMDataIOFeatureQCTools.asCellstr(caseIds, 'S', size(M,1));
            M = double(M);
            meanVec = nanmeanCompat(M, 1);
            sdVec = nanstdCompat(M, 0, 1);
            raw = M(rowIndex,:);
            validFeature = isfinite(meanVec) & isfinite(sdVec) & sdVec > 0 & isfinite(raw);
            z = nan(1, size(M,2));
            z(validFeature) = (raw(validFeature) - meanVec(validFeature)) ./ sdVec(validFeature);

            out.rowIndex = rowIndex;
            out.caseId = caseIds{rowIndex};
            if ~isempty(labels)
                if isnumeric(labels) || islogical(labels)
                    if size(labels,1) >= rowIndex, out.label = labels(rowIndex,:); end
                elseif iscell(labels)
                    if numel(labels) >= rowIndex, out.label = labels{rowIndex}; end
                else
                    if size(labels,1) >= rowIndex, out.label = labels(rowIndex,:); end
                end
            end
            out.nFeatures = size(M,2);
            out.nValidFeatures = nnz(validFeature);
            out.nObservedFeatures = nnz(isfinite(raw));
            out.nMissingFeatures = nnz(~isfinite(raw));
            out.nUnscorableFeatures = nnz(isfinite(raw) & ~isfinite(z));
            finiteIdx = find(isfinite(z));
            if ~isempty(finiteIdx)
                finiteZ = z(finiteIdx);
                out.meanAbsZ = mean(abs(finiteZ));
                out.rmsZ = sqrt(mean(finiteZ.^2));
                out.maxAbsZ = max(abs(finiteZ));
            end

            query = strtrim(NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts, 'featureQuery', '')));
            zMin = double(NMDataIOFeatureQCTools.fieldOr(opts, 'featureZMin', NaN));
            zMax = double(NMDataIOFeatureQCTools.fieldOr(opts, 'featureZMax', NaN));
            if ~isempty(query) || isfinite(zMin) || isfinite(zMax)
                hitMask = true(1, size(M,2));
                detailSource = 'name'; detailLabel = query;
                if ~isempty(query)
                    hitMask = hitMask & reshape(contains(featureNames, query, 'IgnoreCase', true), 1, []);
                end
                if isfinite(zMin)
                    hitMask = hitMask & isfinite(z) & z >= zMin;
                    detailSource = 'zrange';
                end
                if isfinite(zMax)
                    hitMask = hitMask & isfinite(z) & z <= zMax;
                    detailSource = 'zrange';
                end
                hit = find(hitMask);
                out.detailTotal = double(numel(hit));
                limit = round(double(NMDataIOFeatureQCTools.fieldOr(opts, 'maxFeatureResults', 20)));
                if ~isfinite(limit) || limit < 1, limit = 20; end
                limit = min(limit, 100);
                if strcmp(detailSource, 'zrange') && ~isempty(hit)
                    [~,ord] = sort(abs(z(hit)), 'descend');
                    hit = hit(ord);
                    detailLabel = sprintf('z in [%g, %g]', zMin, zMax);
                end
                hit = hit(1:min(limit,numel(hit)));
                out.detailOnly = true;
                out.detailSource = detailSource;
                out.detailLabel = detailLabel;
                out.detailFeatureIndex = double(hit(:)');
                out.detailFeatureNames = featureNames(hit);
                out.detailRaw = double(raw(hit));
                out.detailZ = double(z(hit));
                out.detailMissing = logical(~isfinite(raw(hit)));
                messages = [messages; NMDataIOMessageTools.make('ok', false, [messageSource '.detail'], ...
                    sprintf('Prepared %g of %g matching tabular feature detail row(s).', numel(hit), out.detailTotal), 0, 'green*')];
                out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
                return;
            end

            maxPoints = round(double(NMDataIOFeatureQCTools.fieldOr(opts, 'maxPoints', 6000)));
            if ~isfinite(maxPoints) || maxPoints < 200, maxPoints = 6000; end
            maxBins = round(double(NMDataIOFeatureQCTools.fieldOr(opts, 'maxBins', 1000)));
            if ~isfinite(maxBins) || maxBins < 100, maxBins = 1000; end
            histBins = round(double(NMDataIOFeatureQCTools.fieldOr(opts, 'histBins', 48)));
            if ~isfinite(histBins) || histBins < 12, histBins = 48; end
            histBins = min(histBins, 100);
            profile = NMDataIOFeatureQCTools.featureProfilePlotPayload(z, raw, featureNames, maxPoints, maxBins, histBins);
            out.featureIndex = profile.featureIndex;
            out.featureNames = profile.featureNames;
            out.z = profile.z;
            out.raw = profile.raw;
            out.plotMode = profile.plotMode;
            out.highDimensional = profile.highDimensional;
            out.histCounts = profile.histCounts;
            out.histEdges = profile.histEdges;
            out.binStart = profile.binStart;
            out.binEnd = profile.binEnd;
            out.binMinZ = profile.binMinZ;
            out.binMaxZ = profile.binMaxZ;
            out.binMissingN = profile.binMissingN;
            out.binFeatureN = profile.binFeatureN;
            out.maxPoints = maxPoints;
            out.downsampled = profile.downsampled;
            if ~isempty(finiteIdx)
                [~,ord] = maxk(abs(z(finiteIdx)), min(12,numel(finiteIdx)));
                topIdx = finiteIdx(ord);
                out.topFeatureIndex = double(topIdx(:)');
                out.topFeatureNames = featureNames(topIdx);
                out.topRaw = double(raw(topIdx));
                out.topZ = double(z(topIdx));
                out.topMissing = logical(~isfinite(raw(topIdx)));
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, messageSource, ...
                sprintf('Prepared tabular feature QC for case row %g across %g/%g valid feature(s).', rowIndex, nnz(validFeature), size(M,2)), 0, 'green*')];
            out = NMDataIOFeatureQCTools.finishProfileOut(out, messages);
        end

        function profile = featureProfilePlotPayload(z, raw, featureNames, maxPoints, maxBins, histBins)
            nFeatures = numel(z);
            featureNames = NMDataIOFeatureQCTools.asCellstr(featureNames, 'F', nFeatures);
            profile = struct('plotMode','exact','highDimensional',false,'featureIndex',[],'featureNames',{{}},'z',[],'raw',[], ...
                'histCounts',[],'histEdges',[],'binStart',[],'binEnd',[],'binMinZ',[],'binMaxZ',[], ...
                'binMissingN',[],'binFeatureN',[],'downsampled',false);
            finiteZ = double(z(isfinite(z)));
            if ~isempty(finiteZ)
                maxAbs = max(abs(finiteZ));
                if ~isfinite(maxAbs) || maxAbs <= 0, maxAbs = 1; end
                profile.histEdges = linspace(-maxAbs, maxAbs, histBins + 1);
                profile.histCounts = histcounts(finiteZ, profile.histEdges);
            end
            if nFeatures <= maxPoints
                profile.featureIndex = double(1:nFeatures);
                profile.featureNames = featureNames;
                profile.z = double(z);
                profile.raw = double(raw);
                return;
            end
            profile.plotMode = 'histogram';
            profile.highDimensional = true;
            profile.downsampled = true;
            nBins = min([nFeatures, maxBins, maxPoints]);
            edges = round(linspace(0, nFeatures, nBins + 1));
            edges(1) = 0; edges(end) = nFeatures;
            profile.binStart = zeros(1,nBins);
            profile.binEnd = zeros(1,nBins);
            profile.binMinZ = nan(1,nBins);
            profile.binMaxZ = nan(1,nBins);
            profile.binMissingN = zeros(1,nBins);
            profile.binFeatureN = zeros(1,nBins);
            for b = 1:nBins
                i1 = edges(b) + 1;
                i2 = max(i1, edges(b+1));
                profile.binStart(b) = i1;
                profile.binEnd(b) = i2;
                profile.binFeatureN(b) = i2 - i1 + 1;
                zz = z(i1:i2);
                zz = zz(isfinite(zz));
                if ~isempty(zz)
                    profile.binMinZ(b) = min(zz);
                    profile.binMaxZ(b) = max(zz);
                end
                profile.binMissingN(b) = nnz(~isfinite(raw(i1:i2)));
            end
        end

        function out = finishProfileOut(out, messages)
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, out.message);
            out.strip = strip;
            out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
            out.summary = NMDataIOMessageTools.summarize(messages);
            out.blocking = strip.blocking;
            out.ok = ~strip.blocking;
            out.message = strip.text;
        end

    end

    methods (Static)
        function [viewerOverlay, messages] = exportROIViewerReferenceCache(roiValues, caseIds, featureNames, labels, roiProvenance, opts, qcStats)
            % exportROIViewerReferenceCache  Persist one canonical ROI inspection materialization.
            %
            % Purpose:
            %   Store the already resolved subject-by-ROI matrix and canonical spatial provenance once
            %   at Preview/QC producer time so the shared DataIO subject viewer can display raw ROI
            %   values before QC and, when QC is available, switch to subject/group QC maps without
            %   reopening ROI sources, atlases, annotations, meshes, or structural templates.
            %
            % Authority and flow:
            %   This is the public producer boundary used by Preview and Feature-QC after canonical
            %   ROI provenance has been resolved. Canonical ROI scoring owns creation after provenance
            %   validation. Volumetric ROI state retains the validated labelled atlas itself. Surface
            %   ROI state retains each used
            %   hemisphere's canonical annotation labels and explicitly matched display mesh.
            %
            % Scientific/state contract and invariants:
            %   ROI column i remains bound to roiProvenance.roiIDs(i); surface columns additionally
            %   remain bound to roiProvenance.hemisphere{i}. Atlas labels and annotation IDs are the
            %   parcel-membership authorities. Surface geometry supplies coordinates/faces only.
            %   Volumetric voxel-to-column membership is retained once; surface labels remain authoritative.
            %
            % Materialization and performance:
            %   YES. During explicit Preview or QC materialization the validated atlas, or one canonical annotation
            %   plus matching display mesh per used hemisphere, is read once and retained in this
            %   session-local MAT payload. For volumetric ROI inspection, the standard NM structural reference
            %   is also read once and linearly sampled onto the atlas grid as display-only anatomy.
            %   Interactive consumers never reopen atlas, annotation, geometry, structural template,
            %   CAT12/XML, or subject source files.
            %
            % Failure semantics and side effects:
            %   Numerical Preview/QC results remain valid if spatial retention fails; a non-blocking warning is
            %   returned and no atlas, annotation, hemisphere, or mesh is guessed. Writes one temporary
            %   viewer sidecar consumed by DataIO and Results Viewer spatial inspectors.
            if nargin < 7 || isempty(qcStats), qcStats = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            progressTask = NMProgressTools.emptyTaskForLocalUse();
            progressRange = [];
            if isstruct(opts) && isfield(opts,'ProgressTask') && isstruct(opts.ProgressTask) && ...
                    isfield(opts,'ROIViewerProgressRange') && isnumeric(opts.ROIViewerProgressRange) && numel(opts.ROIViewerProgressRange)==2
                progressTask = opts.ProgressTask;
                progressRange = double(opts.ROIViewerProgressRange(:)');
                progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_prepare', progressRange(1), ...
                    progressRange(1)+0.10*(progressRange(2)-progressRange(1)), 'Preparing ROI spatial-inspection data.');
            end
            spatialKinds = arrayfun(@(r)NMDataIOFeatureQCTools.asChar(r.kind), roiProvenance.spatialReferences, 'UniformOutput', false);
            requiredQC = {'meanVec','sdVec','countVec','zeroCount','outlierCount','nSubjects'};
            hasQC = isstruct(qcStats) && all(isfield(qcStats,requiredQC));
            roiMetrics = repmat(struct('key','','label','','overlayKind',''),1,0);
            method = 'roi_subject_reference';
            description = 'ROI values and their spatial reference are available for the case viewer.';
            if hasQC
                roiMetrics = NMDataIOFeatureQCTools.imageQCMetricList();
                if ~isempty(roiMetrics), roiMetrics(1).label = 'Subject ROI z-score'; end
                method = 'roi_qc_metric_reference';
                description = 'ROI values, their spatial reference and QC statistics are available for case and QC inspection.';
            end
            viewerOverlay = struct('available',false,'cacheToken','','method',method, ...
                'thresholdDefault',NMDataIOFeatureQCTools.qcOptionNumber(opts,'OutlierZThreshold',3), ...
                'modeDefault','signed','metrics',roiMetrics,'qcAvailable',logical(hasQC), ...
                'featureSpace','roi_field','spatialReferenceKinds',{spatialKinds},'spatialAvailable',false, ...
                'description',description);
            tmpDir = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'tmpDir',''));
            if isempty(tmpDir), return; end
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.roi.overlay', ...
                    sprintf('ROI viewer data could not be prepared: %s', assetErr), 0, 'amber*')];
                return;
            end
            if exist(assetDir,'dir') ~= 7
                [ok,msg] = mkdir(assetDir);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.roi.overlay', ...
                        sprintf('Could not create ROI viewer asset directory %s: %s', assetDir, msg), 0, 'amber*')];
                    return;
                end
            end
            if hasQC, tokenPrefix='roiqcstats'; else, tokenPrefix='roipreview'; end
            token = NMDataIOFeatureQCTools.safeCacheToken(tokenPrefix);
            cacheFile = fullfile(assetDir, [token '.mat']);
            cache = struct();
            cache.roiValues = double(roiValues);
            cache.caseIds = NMDataIOFeatureQCTools.asCellstr(caseIds, 'S', size(roiValues,1));
            cache.featureNames = NMDataIOFeatureQCTools.asCellstr(featureNames, 'ROI', size(roiValues,2));
            cache.labels = labels;
            cache.roiProvenance = roiProvenance;
            cache.hasQC = logical(hasQC);
            if hasQC
                countVec = double(qcStats.countVec(:));
                sdVec = double(qcStats.sdVec(:));
                cache.meanVec = double(qcStats.meanVec(:));
                cache.sdVec = sdVec;
                cache.m2Vec = (sdVec .^ 2) .* max(0, countVec - 1);
                cache.countVec = uint32(countVec);
                cache.zeroCount = uint32(double(qcStats.zeroCount(:)));
                cache.outlierCount = uint32(double(qcStats.outlierCount(:)));
                cache.nSubjects = double(qcStats.nSubjects);
                cache.cohortZWindow = qcStats.cohortZWindow;
            end
            cache.nROIs = double(size(roiValues,2));
            cache.featureSpace = 'roi_field';
            cache.columnKeys = roiProvenance.columnKeys(:);
            cache.spatialReferenceKinds = spatialKinds(:);
            cache.outlierZThreshold = double(viewerOverlay.thresholdDefault);
            cache.zeroTolerance = double(NMDataIOFeatureQCTools.qcOptionNumber(opts,'ZeroTolerance',0));
            cache.createdOn = now;
            if ~isempty(progressRange)
                progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_payload', ...
                    progressRange(1)+0.10*(progressRange(2)-progressRange(1)), ...
                    progressRange(1)+0.20*(progressRange(2)-progressRange(1)), 'Preparing ROI values and spatial reference.');
            end

            volumetricRef = find(strcmp(spatialKinds,'volumetric_atlas'),1,'first');
            if ~isempty(volumetricRef)
                try
                    ref = roiProvenance.spatialReferences(volumetricRef);
                    atlasFiles = NMDataIOFeatureQCTools.asCellstr(ref.sourceFiles);
                    if isempty(atlasFiles) || isempty(atlasFiles{1})
                        error('NMDataIOFeatureQCTools:ROIAtlasMissing','No labelled atlas file is defined for the volumetric ROI data.');
                    end
                    if exist('NMImagingVolumeAccess','class') ~= 8
                        error('NMDataIOFeatureQCTools:ROIAtlasReaderMissing','NMImagingVolumeAccess is unavailable on the MATLAB path.');
                    end
                    if ~isempty(progressRange)
                        progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_atlas', ...
                            progressRange(1)+0.20*(progressRange(2)-progressRange(1)), ...
                            progressRange(1)+0.46*(progressRange(2)-progressRange(1)), 'Reading the labelled ROI atlas for spatial inspection.');
                    end
                    roiAtlas = NMImagingVolumeAccess.read(atlasFiles{1},'roi_atlas_labels');
                    atlasData = double(roiAtlas.data);
                    nonBackground = isfinite(atlasData) & atlasData ~= 0;
                    labelDeviation = atlasData(nonBackground) - round(atlasData(nonBackground));
                    if any(abs(labelDeviation) > 1e-6)
                        error('NMDataIOFeatureQCTools:ROIAtlasNonDiscrete','The labelled ROI atlas contains non-integer ROI values.');
                    end
                    exactIntegerLabels = all(labelDeviation == 0);
                    roiVolumeMapping = NMDataIOROIProvenanceTools.prepareVolumetricMapping( ...
                        roiProvenance,atlasData,ref.identity);
                    minLabel = min(atlasData(:)); maxLabel = max(atlasData(:));
                    if exactIntegerLabels && isfinite(minLabel) && minLabel >= 0 && maxLabel <= double(intmax('uint8'))
                        atlasTransportType = 'uint8'; atlasTransportBytes = 1;
                    elseif exactIntegerLabels && isfinite(minLabel) && minLabel >= 0 && maxLabel <= double(intmax('uint16'))
                        atlasTransportType = 'uint16'; atlasTransportBytes = 2;
                    elseif exactIntegerLabels && isfinite(minLabel) && minLabel >= 0 && maxLabel <= double(intmax('uint32'))
                        atlasTransportType = 'uint32'; atlasTransportBytes = 4;
                    else
                        atlasTransportType = 'float64'; atlasTransportBytes = 8;
                    end
                    matchedVoxels = roiVolumeMapping.lookupIndex(:) > 1;
                    refDim = double(NMDataIOFeatureQCTools.fieldOr(ref,'referenceDim',[]));
                    if ~isempty(refDim) && ~isequal(double(refDim(:)'),double(roiAtlas.dimensions(:)'))
                        error('NMDataIOFeatureQCTools:ROIAtlasDimensionMismatch','The ROI atlas dimensions do not match the validated spatial reference.');
                    end
                    refMat = double(NMDataIOFeatureQCTools.fieldOr(ref,'referenceMat',[]));
                    if ~isempty(refMat) && ~isequal(size(refMat),[4 4])
                        error('NMDataIOFeatureQCTools:ROIAtlasAffineInvalid','The ROI atlas spatial transform must be a 4-by-4 matrix.');
                    end
                    if ~isempty(refMat) && ~isequaln(refMat,double(roiAtlas.spatialReference.affineVoxel1ToWorld))
                        error('NMDataIOFeatureQCTools:ROIAtlasAffineMismatch','The ROI atlas geometry does not match the validated spatial reference.');
                    end
                    structuralFile = NMDataIOFeatureQCTools.asChar(NMDataIOFeatureQCTools.fieldOr(opts,'structuralFile',''));
                    if isempty(structuralFile)
                        error('NMDataIOFeatureQCTools:ROIStructuralReferenceMissing', ...
                            'The standard NM structural reference is unavailable for volumetric ROI spatial QC.');
                    end
                    if ~isempty(progressRange)
                        progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_structural', ...
                            progressRange(1)+0.46*(progressRange(2)-progressRange(1)), ...
                            progressRange(1)+0.82*(progressRange(2)-progressRange(1)), 'Aligning structural reference to the ROI atlas.');
                    end
                    structuralVolume = NMImagingVolumeAccess.read(structuralFile,'structural');
                    [structuralOnAtlas, structuralResampling] = NMImagingResampling.resample( ...
                        structuralVolume,roiAtlas.spatialReference,'linear',NaN,'roi_qc_structural_display');
                    if ~isequal(double(structuralOnAtlas.dimensions(:)'),double(roiAtlas.dimensions(:)'))
                        error('NMDataIOFeatureQCTools:ROIStructuralGridMismatch', ...
                            'The standard anatomical background could not be aligned to the ROI atlas.');
                    end
                    finiteStructural = double(structuralOnAtlas.data(isfinite(structuralOnAtlas.data)));
                    if isempty(finiteStructural)
                        error('NMDataIOFeatureQCTools:ROIStructuralEmpty', ...
                            'The standard anatomical background contains no usable values in the ROI atlas space.');
                    end
                    if numel(finiteStructural)>1000000
                        take=unique(round(linspace(1,numel(finiteStructural),1000000))); finiteWindow=finiteStructural(take);
                    else
                        finiteWindow=finiteStructural;
                    end
                    lo=prctile(finiteWindow,1); hi=prctile(finiteWindow,99);
                    if ~isfinite(lo)||~isfinite(hi)||hi<=lo, lo=min(finiteStructural); hi=max(finiteStructural); end
                    if hi<=lo, hi=lo+eps; end
                    sliceCounts = squeeze(sum(sum(reshape(matchedVoxels,roiAtlas.dimensions),1),2));
                    [~,atlasDefaultSlice] = max(sliceCounts);
                    cache.roiAtlas = roiAtlas;
                    cache.roiVolumeMapping = roiVolumeMapping;
                    cache.atlasTransportType = atlasTransportType;
                    cache.atlasTransportBytes = atlasTransportBytes;
                    cache.roiStructural = struct('data',single(structuralOnAtlas.data), ...
                        'structuralFile',structuralFile,'resampling',structuralResampling,'window',[double(lo) double(hi)]);
                    cache.atlasDefaultSlice = double(atlasDefaultSlice);
                    viewerOverlay.spatialAvailable = true;
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.roi.spatial', ...
                        sprintf('Numerical ROI QC was computed, but the labelled atlas could not be prepared for spatial inspection: %s', ME.message), 2, 'orange')];
                end
            end
            surfaceRef = find(strcmp(spatialKinds,'surface_annotation'),1,'first');
            if ~isempty(surfaceRef)
                try
                    ref = roiProvenance.spatialReferences(surfaceRef);
                    hemi = NMDataIOFeatureQCTools.asCellstr(NMDataIOFeatureQCTools.fieldOr(roiProvenance,'hemisphere',{}));
                    canonicalIDs = double(roiProvenance.roiIDs(:)');
                    if numel(hemi) ~= numel(canonicalIDs)
                        error('NMDataIOFeatureQCTools:ROISurfaceHemisphereMissing','Surface ROI data require one hemisphere value for every ROI column.');
                    end
                    annotByHemi = NMDataIOFeatureQCTools.fieldOr(ref,'annotationFilesByHemisphere',struct());
                    geomByHemi = NMDataIOFeatureQCTools.fieldOr(ref,'surfaceGeometryFilesByHemisphere',struct());
                    partTemplate = struct('hemisphere','','annotationLabels',[],'vertices',single([]),'faces',uint32([]));
                    parts = repmat(partTemplate,1,0);
                    usedHemi = unique(hemi,'stable');
                    if ~isempty(progressRange)
                        progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_surface', ...
                            progressRange(1)+0.20*(progressRange(2)-progressRange(1)), ...
                            progressRange(1)+0.82*(progressRange(2)-progressRange(1)), 'Reading the ROI surface annotation and display mesh.');
                    end
                    for hh=1:numel(usedHemi)
                        token = lower(NMDataIOFeatureQCTools.asChar(usedHemi{hh}));
                        if ~ismember(token,{'lh','rh'})
                            error('NMDataIOFeatureQCTools:ROISurfaceHemisphereInvalid','Unsupported surface ROI hemisphere: %s.',token);
                        end
                        if ~isfield(annotByHemi,token) || ~isfield(geomByHemi,token)
                            error('NMDataIOFeatureQCTools:ROISurfaceDisplayReferenceMissing','The %s surface ROI data do not specify both an annotation and display mesh.',upper(token));
                        end
                        annotFiles = NMDataIOFeatureQCTools.asCellstr(annotByHemi.(token));
                        geomFiles = NMDataIOFeatureQCTools.asCellstr(geomByHemi.(token));
                        if numel(annotFiles) ~= 1 || numel(geomFiles) ~= 1
                            error('NMDataIOFeatureQCTools:ROISurfaceDisplayReferenceAmbiguous','Surface ROI spatial QC for %s requires exactly one annotation and one matching display mesh; found %g annotation(s) and %g mesh(es). Select one of each.',upper(token),numel(annotFiles),numel(geomFiles));
                        end
                        [labels,~] = NMDataIOSurfaceTools.readAnnotationLabels(annotFiles{1});
                        [vertices,faces,~] = NMDataIOSurfaceTools.readSurfaceGeometry(geomFiles{1});
                        labels = double(labels(:));
                        if numel(labels) ~= size(vertices,1)
                            error('NMDataIOFeatureQCTools:ROISurfaceVertexMismatch','%s annotation has %g labels but its explicit display mesh has %g vertices.',upper(token),numel(labels),size(vertices,1));
                        end
                        NMDataIOROIProvenanceTools.expandSurfaceValues( ...
                            roiProvenance,1:numel(canonicalIDs),token,labels);
                        parts(end+1) = struct('hemisphere',token,'annotationLabels',labels,'vertices',single(vertices),'faces',uint32(faces)); %#ok<AGROW>
                        if ~isempty(progressRange)
                            progressTask = NMProgressTools.step(progressTask, hh, max(1,numel(usedHemi)), ...
                                sprintf('Prepared %s ROI surface reference (%g of %g).',upper(token),hh,numel(usedHemi)), true);
                        end
                    end
                    cache.roiSurface = struct('parts',parts);
                    viewerOverlay.spatialAvailable = true;
                catch ME
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.roi.surfaceSpatial', ...
                        sprintf('Numerical ROI QC was computed, but the labelled surface could not be prepared for spatial inspection: %s',ME.message), 2, 'orange')];
                end
            end
            try
                if ~isempty(progressRange)
                    progressTask = NMProgressTools.phase(progressTask, 'roi_preview_cache_write', ...
                        progressRange(1)+0.82*(progressRange(2)-progressRange(1)), progressRange(2), ...
                        'Preparing ROI data for spatial inspection.');
                end
                save(cacheFile, '-struct', 'cache', '-v7');
                viewerOverlay.available = true;
                viewerOverlay.cacheToken = token;
                if hasQC, materializationLabel='QC/inspection'; else, materializationLabel='subject-inspection'; end
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.roi.overlay', ...
                    sprintf('Prepared ROI %s data for %g parcel(s).', materializationLabel, size(roiValues,2)), 0, 'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.roi.overlay')];
            end
        end

    end

    methods (Static, Access = private)
        function [viewerOverlay, messages] = exportSurfaceViewerOverlayCache(Y, tmpDir, opts)
            if nargin < 3 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            viewerOverlay = struct('available',false,'cacheToken','','method','surface_qc_metric_overlay', ...
                'thresholdDefault',3,'modeDefault','signed','metrics',{NMDataIOFeatureQCTools.surfaceQCMetricList()}, ...
                'featureSpace','surface_vertex_registered', 'description', ...
                'Vertexwise QC overlays for the surface viewer. Requires registered/homologous surface vertices across subjects. Run Preview first, then select a subject-specific vertex z-score or a feature-level QC statistic in the viewer.');
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.surface.overlay', ...
                    sprintf('Surface QC viewer data could not be prepared: %s', assetErr), 0, 'amber*')];
                return;
            end
            if exist(assetDir,'dir') ~= 7
                [ok,msg] = mkdir(assetDir);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.surface.overlay', ...
                        sprintf('Could not create surface viewer asset directory %s: %s', assetDir, msg), 0, 'amber*')];
                    return;
                end
            end
            try
                Y = double(Y);
                nSubjects = size(Y,1);
                zThreshold = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'OutlierZThreshold', 3);
                zeroTol = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'ZeroTolerance', 0);
                finiteMask = isfinite(Y);
                countVec = sum(finiteMask, 1);
                meanVec = nanmeanCompat(Y, 1);
                sdVec = nanstdCompat(Y, 0, 1);
                zeroCount = sum(finiteMask & abs(Y) <= zeroTol, 1);
                validFeature = isfinite(meanVec) & isfinite(sdVec) & sdVec > 0;
                outlierCount = zeros(1, size(Y,2));
                absZCacheLimit = NMDataIOFeatureQCTools.qcOptionNumber(opts, 'ViewerAbsZCacheMaxElements', 5e7);
                storeAbsZCache = isfinite(absZCacheLimit) && absZCacheLimit > 0 && double(nSubjects) * double(size(Y,2)) <= absZCacheLimit;
                if storeAbsZCache
                    absZMatrix = single(nan(nSubjects, size(Y,2)));
                else
                    absZMatrix = [];
                end
                for i = 1:nSubjects
                    idx = validFeature & isfinite(Y(i,:));
                    if any(idx)
                        z = (Y(i,idx) - meanVec(idx)) ./ sdVec(idx);
                        outlierCount(idx) = outlierCount(idx) + double(abs(z) >= zThreshold);
                        if storeAbsZCache
                            absZMatrix(i,idx) = single(abs(z));
                        end
                    end
                end
                token = ['surfqcstats_' regexprep(NMDataIOImagePreviewTools.safeToken(), '^vol_', '')];
                cacheFile = fullfile(assetDir, [token '.mat']);
                cache = struct();
                cache.meanVec = double(meanVec(:));
                cache.sdVec = double(sdVec(:));
                cache.m2Vec = double((sdVec(:) .^ 2) .* max(0, double(countVec(:)) - 1));
                cache.countVec = uint32(countVec(:));
                cache.zeroCount = uint32(zeroCount(:));
                cache.outlierCount = uint32(outlierCount(:));
                cache.cohortZWindow = opts.cohortZWindow;
                if storeAbsZCache
                    cache.absZMatrix = absZMatrix;
                end
                cache.nSubjects = double(nSubjects);
                cache.nVertices = double(size(Y,2));
                cache.featureSpace = 'surface_vertex_registered';
                cache.outlierZThreshold = double(zThreshold);
                cache.zeroTolerance = double(zeroTol);
                cache.dynamicOutlierThresholdAvailable = logical(storeAbsZCache);
                cache.viewerAbsZCacheMaxElements = double(absZCacheLimit);
                cache.createdOn = now;
                save(cacheFile, '-struct', 'cache', '-v7');
                viewerOverlay.available = true;
                viewerOverlay.cacheToken = token;
                viewerOverlay.method = 'surface_qc_metric_overlay';
                viewerOverlay.metrics = NMDataIOFeatureQCTools.surfaceQCMetricList();
                viewerOverlay.thresholdDefault = double(zThreshold);
                viewerOverlay.cachedOutlierZThreshold = double(zThreshold);
                viewerOverlay.dynamicOutlierThresholdAvailable = logical(storeAbsZCache);
                viewerOverlay.modeDefault = 'signed';
                viewerOverlay.nVertices = double(size(Y,2));
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.surface.overlay', ...
                    'Surface QC viewer data prepared for registered vertexwise surface features.', 0, 'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.surface.overlay.export')];
            end
        end

        function win = finiteValueWindow(values)
            values = double(values(:));
            values = values(isfinite(values));
            if isempty(values)
                win = [0 1];
                return;
            end
            try
                lo = prctile(values, 1);
                hi = prctile(values, 99);
            catch
                lo = min(values);
                hi = max(values);
            end
            if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                lo = min(values);
                hi = max(values);
            end
            if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
                hi = lo + eps;
            end
            win = [double(lo) double(hi)];
        end

        function [viewerOverlay, messages] = exportViewerOverlayCache(meanVec, m2Vec, countVec, maskFile, tmpDir, extraCache)
            if nargin < 6 || isempty(extraCache), extraCache = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            viewerOverlay = struct('available',false,'cacheToken','','method','image_qc_metric_overlay', ...
                'thresholdDefault',3,'cachedOutlierZThreshold',3,'dynamicOutlierThresholdAvailable',false, ...
                'modeDefault','signed','metrics',{NMDataIOFeatureQCTools.imageQCMetricList()},'description', ...
                'Voxelwise QC overlays for the imaging viewer. Run Preview first, then select a subject-specific z-score map or a feature-level QC statistic in the viewer.');
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.images.overlay', ...
                    sprintf('Imaging QC viewer data could not be prepared: %s', assetErr), 0, 'amber*')];
                return;
            end
            if exist(assetDir,'dir') ~= 7
                [ok,msg] = mkdir(assetDir);
                if ~ok
                    messages = [messages; NMDataIOMessageTools.make('warn', false, 'featureQC.images.overlay', ...
                        sprintf('Could not create imaging viewer asset directory %s: %s', assetDir, msg), 0, 'amber*')];
                    return;
                end
            end
            token = ['qcstats_' NMDataIOImagePreviewTools.safeToken()];
            cacheFile = fullfile(assetDir, [token '.mat']);
            try
                cache = struct();
                cache.meanVec = double(meanVec(:));
                cache.m2Vec = double(m2Vec(:));
                cache.countVec = uint32(countVec(:));
                cache.maskFile = maskFile;
                cache.createdOn = now;
                extraFields = fieldnames(extraCache);
                for f = 1:numel(extraFields)
                    cache.(extraFields{f}) = extraCache.(extraFields{f});
                end
                save(cacheFile, '-struct', 'cache', '-v7');
                viewerOverlay.available = true;
                viewerOverlay.cacheToken = token;
                viewerOverlay.method = 'image_qc_metric_overlay';
                viewerOverlay.metrics = NMDataIOFeatureQCTools.imageQCMetricList();
                if isfield(extraCache,'outlierZThreshold')
                    viewerOverlay.thresholdDefault = double(extraCache.outlierZThreshold);
                    viewerOverlay.cachedOutlierZThreshold = double(extraCache.outlierZThreshold);
                end
                if isfield(extraCache,'dynamicOutlierThresholdAvailable')
                    viewerOverlay.dynamicOutlierThresholdAvailable = logical(extraCache.dynamicOutlierThresholdAvailable);
                elseif isfield(extraCache,'absZMatrix')
                    viewerOverlay.dynamicOutlierThresholdAvailable = true;
                end
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'featureQC.images.overlay', ...
                    'Imaging QC viewer data prepared. The image viewer can now show case-specific z-score maps.', 0, 'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'featureQC.images.overlay.export')];
            end
        end

        function vol = vectorToViewerVolume(vec, Vm, mask)
            % vectorToViewerVolume  Reconstruct one masked feature vector and orient it for browser slices.
            %
            % Purpose / contract:
            %   vec must enumerate mask voxels in MATLAB linear order. The helper reconstructs the
            %   native-grid field once and applies the shared browser slice orientation without
            %   changing feature values or spatial membership.
            %
            % Materialization and performance:
            %   Pure O(Nvox) in-memory reconstruction. No files, atlases, annotations, or source data
            %   are read. Safe on interactive viewer paths for already resident feature vectors.
            native = nan(Vm.dim, 'single');
            mask = logical(mask);
            if nnz(mask) ~= numel(vec)
                error('NMDataIOFeatureQCTools:ViewerVectorShape', ...
                    'Viewer feature vector contains %g value(s), but the spatial support contains %g voxel(s).', ...
                    numel(vec),nnz(mask));
            end
            native(mask) = single(vec(:));
            vol = NMDataIOFeatureQCTools.orientVolumeForViewer(native);
        end

        function vol = orientVolumeForViewer(native)
            % orientVolumeForViewer  Apply the established axial browser orientation to a 3-D array.
            %
            % Scientific/state contract:
            %   Orientation changes array presentation only. Values and voxel membership are preserved
            %   exactly; this helper performs no interpolation, relabelling, or spatial inference.
            %
            % Materialization and performance:
            %   Pure O(Nvox) in-memory permutation/flip and safe for interactive display preparation.
            %   Input numeric class is preserved so labelled atlas IDs remain exact.
            dims = size(native);
            if numel(dims) < 3, dims(end+1:3) = 1; end
            if numel(dims) ~= 3
                error('NMDataIOFeatureQCTools:ViewerVolumeShape', ...
                    'Browser volume orientation requires a 3-D array.');
            end
            vol = flip(permute(reshape(native,dims),[2 1 3]),1);
        end

        function txt = firstMessageText(messages, fallback)
            txt = fallback;
            if isempty(messages), return; end
            if isstruct(messages)
                for i = 1:numel(messages)
                    if isfield(messages,'text') && ~isempty(messages(i).text)
                        txt = char(string(messages(i).text));
                        return;
                    end
                end
            end
        end

        function tf = functionAvailable(name)
            c = exist(name,'file');
            tf = any(c == [2 3 5 6 8]) || ~isempty(which(name));
        end

        function v = qcOptionNumber(opts, field, defaultValue)
            v = defaultValue;
            if isstruct(opts) && isfield(opts, field) && ~isempty(opts.(field))
                vv = double(opts.(field));
                if ~isempty(vv)
                    vv = vv(1);
                end
                if isfinite(vv)
                    v = vv;
                end
            end
        end

        function tf = binaryAssetMatches(pathName, expectedBytes)
            % binaryAssetMatches  Test whether an ephemeral browser binary already has the expected size.
            %
            % Purpose / contract:
            %   Avoid rewriting subject-invariant structural/atlas browser transport on every ROI
            %   subject switch. The scientific authorities remain the resident atlas and structural
            %   materialization; this check concerns only disposable browser assets.
            %
            % Materialization and performance:
            %   O(1) file metadata check. Reads no scientific source and is safe on interactive paths.
            tf = false;
            if isempty(pathName) || exist(pathName,'file') ~= 2, return; end
            info = dir(pathName);
            tf = ~isempty(info) && isfinite(double(expectedBytes)) && double(info(1).bytes) == double(expectedBytes);
        end

        function v = fieldOr(s, field, defaultValue)
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                v = s.(field);
            else
                v = defaultValue;
            end
        end

        function s = asChar(x)
            if isstring(x), x = char(x); end
            if iscell(x) && ~isempty(x), x = x{1}; end
            if isempty(x), s = ''; else, s = char(x); end
        end

        function c = asCellstr(x, prefix, n)
            if nargin < 2, prefix = ''; end
            if nargin < 3, n = []; end
            if isempty(x)
                if ~isempty(prefix) && ~isempty(n)
                    c = arrayfun(@(i) sprintf('%s%g', prefix, i), 1:n, 'UniformOutput', false)';
                else
                    c = {};
                end
                return;
            end
            if ischar(x)
                if size(x,1) > 1
                    c = cellstr(x);
                else
                    c = {x};
                end
            elseif isstring(x)
                c = cellstr(x(:));
            elseif iscell(x)
                c = cellfun(@NMDataIOFeatureQCTools.cellValueToChar, x(:), 'UniformOutput', false);
            elseif isnumeric(x) || islogical(x)
                c = arrayfun(@(v) num2str(v), x(:), 'UniformOutput', false);
            else
                c = cellstr(string(x(:)));
            end
            if ~isempty(n) && numel(c) ~= n && ~isempty(prefix)
                c = arrayfun(@(i) sprintf('%s%g', prefix, i), 1:n, 'UniformOutput', false)';
            end
        end

        function s = cellValueToChar(x)
            if isempty(x)
                s = '';
            elseif ischar(x)
                s = x;
            elseif isstring(x)
                s = char(x(1));
            elseif isnumeric(x) || islogical(x)
                s = num2str(x);
            else
                s = char(string(x));
            end
        end
    end
end

function m = nanmeanCompat(X, dim)
if nargin < 2, dim = 1; end
finite = isfinite(X);
if all(finite(:))
    m = mean(X, dim);
else
    Y = X;
    Y(~finite) = NaN;
    m = mean(Y, dim, 'omitnan');
end
end

function s = nanstdCompat(X, flag, dim)
if nargin < 2 || isempty(flag), flag = 0; end
if nargin < 3, dim = 1; end
finite = isfinite(X);
cnt = sum(finite, dim);
if all(finite(:))
    s = std(X, flag, dim);
else
    Y = X;
    Y(~finite) = NaN;
    s = std(Y, flag, dim, 'omitnan');
end
s(cnt < 2) = NaN;
end

function med = nanmedianCompat(X, dim)
if nargin < 2, dim = 1; end
if dim ~= 1
    X = X';
end
nFeat = size(X,2);
med = nan(1,nFeat);
for j = 1:nFeat
    v = X(:,j);
    v = v(isfinite(v));
    if ~isempty(v)
        med(j) = median(v);
    end
end
if dim ~= 1
    med = med';
end
end

function v = meanWithNaN(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x), v = NaN; else, v = mean(x); end
end

function v = minWithNaN(X, dim)
if nargin < 2, dim = 1; end
if isempty(X), v = NaN; return; end
Y = double(X);
Y(~isfinite(Y)) = Inf;
v = min(Y, [], dim);
v(~isfinite(v)) = NaN;
end

function v = maxWithNaN(X, dim)
if nargin < 2, dim = 1; end
if isempty(X), v = NaN; return; end
Y = double(X);
Y(~isfinite(Y)) = -Inf;
v = max(Y, [], dim);
v(~isfinite(v)) = NaN;
end

function r = rangeStruct(x)
x = double(x(:));
x = x(isfinite(x));
if isempty(x)
    r = struct('min',NaN,'max',NaN);
else
    r = struct('min',double(min(x)),'max',double(max(x)));
end
end
