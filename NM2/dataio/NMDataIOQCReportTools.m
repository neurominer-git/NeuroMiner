classdef NMDataIOQCReportTools
% NMDataIOQCReportTools
% -------------------------------------------------------------------------
% Cross-modality DataIO QC report/export bundle generator.
% Consumes the enriched QC payload produced by NMDataIOFeatureQCTools and
% writes a reproducible local report bundle without mutating NM or import
% state. Spatial exports reuse existing QC viewer caches; voxel map writing
% uses nk_WriteVol when available.
% -------------------------------------------------------------------------

    methods (Static)
        function out = generateFromImportState(NM, state, qc, diagnostics, opts) %#ok<INUSD>
            % generateFromImportState  Generate a QC report artifact from an import state, QC payload, and diagnostics.
            %
            % Consumes NM, state, qc, diagnostics, opts; returns out.
            % It consumes already prepared QC/diagnostic artifacts and creates report output without redefining import semantics.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            %
            % opts.outputDir: configures optional output dir behavior for this call.
            % opts.subjectMetric: configures optional subject metric behavior for this call.
            % opts.tmpDir: sets the temporary directory for generated scripts or runtime sidecar files.
            if nargin < 2 || isempty(state), state = struct(); end
            if nargin < 3 || isempty(qc), qc = struct(); end
            if nargin < 4 || isempty(diagnostics), diagnostics = struct(); end
            if nargin < 5 || isempty(opts), opts = struct(); end
            messages = NMDataIOMessageTools.emptyMessages();
            progressTask = NMProgressTools.fromOptions(opts, 'Generating QC report', 'Preparing QC report bundle.');
            out = struct('ok',false,'blocking',true,'message','QC report was not generated.', ...
                'strip',NMDataIOMessageTools.highestPriorityStrip([], 'QC report was not generated.'), ...
                'messages',messages,'outputDir','','bundleDir','','htmlFile','','pdfFile','', ...
                'subjectCsvFile','','subjectXlsxFile','','featureCsvFile','','featureXlsxFile','', ...
                'featureMatFile','','dataIOFilterCsvFile','','dataIOFilterXlsxFile','','dataIOAxisCsvFile','','dataIOAxisXlsxFile','', ...
                'dataIOBlockCsvFile','','dataIOBlockXlsxFile','','dataIODuplicateCsvFile','','dataIODuplicateXlsxFile','', ...
                'qcHistoryCsvFile','','qcHistoryXlsxFile','','qcMapFiles',{{}},'snapshotFiles',{{}},'operation','qcReport');
            try
                outputDir = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(opts, 'outputDir', ''));
                if isempty(outputDir) || exist(outputDir,'dir') ~= 7
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'qcReport.outputDir', ...
                        sprintf('A valid output directory is required for QC report generation. Received: %s', outputDir), 1, 'red*')];
                    out = NMDataIOQCReportTools.finish(out, messages);
                    NMProgressTools.finish(progressTask, out.message);
                    return;
                end
                if ~isstruct(qc) || ~isfield(qc,'nSubjects') || double(NMDataIOQCReportTools.fieldOr(qc,'nSubjects',0)) < 1
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'qcReport.qcPayload', ...
                        'QC report generation requires QC results from Preview. Run Preview first.', 1, 'red*')];
                    out = NMDataIOQCReportTools.finish(out, messages);
                    NMProgressTools.finish(progressTask, out.message);
                    return;
                end

                progressTask = NMProgressTools.phase(progressTask, 'prepare_report_bundle', 0, 10, 'Creating QC report output folders.');
                stamp = datestr(now, 'yyyymmdd_HHMMSS');
                bundleDir = fullfile(outputDir, ['NM_DataIO_QC_Report_' stamp]);
                qcMapDir = fullfile(bundleDir, 'qc_maps');
                figDir = fullfile(bundleDir, 'figures');
                NMDataIOQCReportTools.ensureDir(bundleDir);
                NMDataIOQCReportTools.ensureDir(qcMapDir);
                NMDataIOQCReportTools.ensureDir(figDir);
                out.outputDir = outputDir;
                out.bundleDir = bundleDir;

                subjectMetric = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(opts, 'subjectMetric', 'rmsZ'));
                zThreshold = NMDataIOQCReportTools.optionNumber(opts, 'zThreshold', NMDataIOQCReportTools.optionNumber(qc, 'outlierZThreshold', 3));
                tmpDir = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(opts, 'tmpDir', ''));
                featureLimit = NMDataIOQCReportTools.optionNumber(opts, 'FeatureTableExportLimit', 10000);
                if ~isfinite(featureLimit) || featureLimit < 1, featureLimit = 10000; end

                progressTask = NMProgressTools.phase(progressTask, 'write_subject_qc_tables', 10, 25, 'Writing subject-level QC tables.');
                subj = NMDataIOQCReportTools.subjectTable(qc);
                [subjCsv, subjMsg] = NMDataIOQCReportTools.writeTablePair(subj, bundleDir, 'subject_qc_metrics');
                messages = [messages; subjMsg];
                out.subjectCsvFile = subjCsv.csv;
                out.subjectXlsxFile = subjCsv.xlsx;

                progressTask = NMProgressTools.phase(progressTask, 'write_feature_qc_tables', 25, 45, 'Writing feature-level QC tables or compact MAT export.');
                featureExport = NMDataIOQCReportTools.exportFeatureTables(qc, bundleDir, featureLimit);
                messages = [messages; featureExport.messages];
                out.featureCsvFile = featureExport.csv;
                out.featureXlsxFile = featureExport.xlsx;
                out.featureMatFile = featureExport.mat;

                progressTask = NMProgressTools.phase(progressTask, 'write_dataio_audit_tables', 45, 58, 'Writing data-source and case-accounting tables.');
                audit = NMDataIOQCReportTools.fieldOr(qc, 'dataIOAudit', struct());
                auditTables = NMDataIOQCReportTools.dataIOAuditTables(audit);
                [out, auditMessages] = NMDataIOQCReportTools.writeDataIOAuditTables(out, auditTables, bundleDir);
                messages = [messages; auditMessages];
                historyTable = NMDataIOQCReportTools.qcHistoryTable(NM, state);
                if ~isempty(historyTable) && height(historyTable) > 0
                    [historyFiles, historyMessages] = NMDataIOQCReportTools.writeTablePair(historyTable, bundleDir, 'qc_history');
                    messages = [messages; historyMessages];
                    out.qcHistoryCsvFile = historyFiles.csv;
                    out.qcHistoryXlsxFile = historyFiles.xlsx;
                end

                progressTask = NMProgressTools.phase(progressTask, 'write_spatial_qc_artifacts', 58, 78, 'Writing spatial/connectivity QC maps and snapshots when available.');
                spatial = NMDataIOQCReportTools.exportSpatialArtifacts(state, qc, tmpDir, qcMapDir, figDir, zThreshold);
                messages = [messages; spatial.messages];
                out.qcMapFiles = spatial.qcMapFiles;
                out.snapshotFiles = spatial.snapshotFiles;

                progressTask = NMProgressTools.phase(progressTask, 'write_html_report', 78, 90, 'Writing QC report HTML.');
                htmlFile = fullfile(bundleDir, 'report.html');
                html = NMDataIOQCReportTools.buildHTMLReport(state, qc, diagnostics, subj, featureExport, spatial, audit, auditTables, historyTable, subjectMetric, zThreshold, out);
                NMDataIOQCReportTools.writeTextFile(htmlFile, html);
                out.htmlFile = htmlFile;
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'qcReport.html', sprintf('QC report HTML written: %s', htmlFile), 0, 'green*')];

                progressTask = NMProgressTools.phase(progressTask, 'write_pdf_report', 90, 97, 'Trying optional PDF export.');
                [pdfFile, pdfMessages] = NMDataIOQCReportTools.tryWritePDF(htmlFile, bundleDir);
                messages = [messages; pdfMessages];
                out.pdfFile = pdfFile;

                if NMDataIOQCReportTools.optionBool(opts, 'openHtml', true)
                    [openOk, openMsg] = NMDataIOQCReportTools.tryOpenHTML(htmlFile);
                    if openOk
                        messages = [messages; NMDataIOMessageTools.make('ok', false, 'qcReport.open', 'QC report opened in the system browser.', 0, 'green*')];
                    else
                        messages = [messages; NMDataIOMessageTools.make('warn', false, 'qcReport.open', openMsg, 2, 'orange')];
                    end
                end

                messages = [messages; NMDataIOMessageTools.make('ok', false, 'qcReport.done', sprintf('QC report bundle generated in: %s', bundleDir), 0, 'green*')];
                out = NMDataIOQCReportTools.finish(out, messages);
                NMProgressTools.finish(progressTask, out.message);
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, 'NMDataIOQCReportTools.generateFromImportState')];
                out = NMDataIOQCReportTools.finish(out, messages);
                NMProgressTools.fail(progressTask, 'NMDataIOQCReportTools.generateFromImportState', ME);
            end
        end
    end

    methods (Static, Access = private)
        function out = finish(out, messages)
            strip = NMDataIOMessageTools.highestPriorityStrip(messages, 'QC report generation completed.');
            out.messages = NMDataIOMessageTools.forDiagnosticsPanel(messages);
            out.strip = strip;
            out.message = strip.text;
            out.blocking = strip.blocking;
            out.ok = ~strip.blocking;
        end

        function T = subjectTable(qc)
            n = double(NMDataIOQCReportTools.fieldOr(qc, 'nSubjects', 0));
            ids = NMDataIOQCReportTools.asCellstr(NMDataIOQCReportTools.fieldOr(qc, 'caseIds', {}), 'S', n);
            T = table();
            T.RowIndex = (1:n)';
            T.CaseID = ids(:);
            T.RMSZ = NMDataIOQCReportTools.col(qc, 'rmsZ', n);
            T.MeanAbsZ = NMDataIOQCReportTools.col(qc, 'meanAbsZ', n);
            T.MeanZ = NMDataIOQCReportTools.col(qc, 'meanZ', n);
            T.SDZ = NMDataIOQCReportTools.col(qc, 'sdZ', n);
            T.MaxAbsZ = NMDataIOQCReportTools.col(qc, 'maxAbsZ', n);
            T.ValidZFeatureN = NMDataIOQCReportTools.col(qc, 'nValidFeaturesBySubject', n);
            T.FiniteFeatureN = NMDataIOQCReportTools.col(qc, 'nFiniteFeaturesBySubject', n);
            T.MissingFeatureN = NMDataIOQCReportTools.col(qc, 'nMissingFeaturesBySubject', n);
            T.MissingFeatureRate = NMDataIOQCReportTools.col(qc, 'missingFeatureRateBySubject', n);
            T.ZeroFeatureN = NMDataIOQCReportTools.col(qc, 'nZeroFeaturesBySubject', n);
            T.ZeroFeatureRate = NMDataIOQCReportTools.col(qc, 'zeroFeatureRateBySubject', n);
            T.OutlierFeatureN = NMDataIOQCReportTools.col(qc, 'nOutlierFeaturesBySubject', n);
            T.OutlierFeatureRate = NMDataIOQCReportTools.col(qc, 'outlierFeatureRateBySubject', n);
            T.RowAllNaN = logical(NMDataIOQCReportTools.col(qc, 'rowAllNaNFlag', n) ~= 0);
            T.RowConstant = logical(NMDataIOQCReportTools.col(qc, 'rowConstantFlag', n) ~= 0);
        end

        function featureExport = exportFeatureTables(qc, bundleDir, limit)
            featureExport = struct('allowed',false,'reason','','csv','','xlsx','','mat','','topTable',table(), ...
                'rankingMetric','','messages',NMDataIOMessageTools.emptyMessages());
            fsName = lower(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(qc, 'featureSpace', '')));
            allowed = any(strcmp(fsName, {'tabular_matrix','image_roi','surface_roi','connectivity_edges','connectivity_matrix'}));
            nFeatures = double(NMDataIOQCReportTools.fieldOr(qc, 'nFeatures', 0));
            if ~allowed
                featureExport.reason = sprintf('Full feature QC table export is skipped for high-dimensional spatial feature space "%s". Spatial QC maps are exported instead where available.', fsName);
                featureExport.messages = [featureExport.messages; NMDataIOMessageTools.make('info', false, 'qcReport.featureTable.skipSpatial', featureExport.reason, 0, 'blue')];
                return;
            end
            featureExport.allowed = true;
            T = NMDataIOQCReportTools.featureTable(qc);
            if isempty(T) || height(T) < 1
                if nFeatures > limit && isfield(qc,'featureStats')
                    matFile = fullfile(bundleDir, 'feature_qc_metrics.mat');
                    featureStats = qc.featureStats; %#ok<NASGU>
                    featureSpace = fsName; %#ok<NASGU>
                    save(matFile, 'featureStats', 'featureSpace', '-v7');
                    featureExport.mat = matFile;
                    featureExport.reason = sprintf('The complete feature-level QC table was not kept because %g features exceed the table limit; compact feature statistics and the highest-ranked features were exported as a MAT-file instead.', nFeatures);
                    featureExport.messages = [featureExport.messages; NMDataIOMessageTools.make('ok', false, 'qcReport.featureTable.compactMat', sprintf('Feature QC metrics exported as compact MAT: %s', matFile), 0, 'green*')];
                else
                    featureExport.reason = 'Feature QC table export was skipped because complete feature-level QC results are not available. Run Preview again if this dataset has 10,000 features or fewer.';
                    featureExport.messages = [featureExport.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.featureTable.noVectors', featureExport.reason, 2, 'orange')];
                end
                return;
            end
            [metric, topT] = NMDataIOQCReportTools.rankFeatureTable(T, 10);
            featureExport.rankingMetric = metric;
            featureExport.topTable = topT;
            if nFeatures <= limit
                [files, msgs] = NMDataIOQCReportTools.writeTablePair(T, bundleDir, 'feature_qc_metrics');
                featureExport.messages = [featureExport.messages; msgs];
                featureExport.csv = files.csv;
                featureExport.xlsx = files.xlsx;
            else
                matFile = fullfile(bundleDir, 'feature_qc_metrics.mat');
                featureTable = T; %#ok<NASGU>
                featureSpace = fsName; %#ok<NASGU>
                save(matFile, 'featureTable', 'featureSpace', '-v7');
                featureExport.mat = matFile;
                featureExport.messages = [featureExport.messages; NMDataIOMessageTools.make('ok', false, 'qcReport.featureTable.mat', sprintf('Feature QC metrics exported as MAT because %g features exceed the CSV/XLSX limit of %g: %s', nFeatures, limit, matFile), 0, 'green*')];
            end
        end

        function T = featureTable(qc)
            T = table();
            if ~isfield(qc,'featureStats') || ~isstruct(qc.featureStats), return; end
            fs = qc.featureStats;
            n = double(NMDataIOQCReportTools.fieldOr(fs, 'nFeatures', 0));
            if n < 1 || ~isfield(fs,'fullReturned') || ~logical(fs.fullReturned), return; end
            names = NMDataIOQCReportTools.asCellstr(NMDataIOQCReportTools.fieldOr(fs, 'featureNames', {}), 'F', n);
            T.FeatureIndex = (1:n)';
            T.FeatureName = names(:);
            T.ValidN = NMDataIOQCReportTools.col(fs, 'validN', n);
            T.MissingN = NMDataIOQCReportTools.col(fs, 'missingN', n);
            T.MissingRate = NMDataIOQCReportTools.col(fs, 'missingRate', n);
            T.ZeroN = NMDataIOQCReportTools.col(fs, 'zeroN', n);
            T.ZeroRate = NMDataIOQCReportTools.col(fs, 'zeroRate', n);
            T.Mean = NMDataIOQCReportTools.col(fs, 'mean', n);
            T.Median = NMDataIOQCReportTools.col(fs, 'median', n);
            T.Std = NMDataIOQCReportTools.col(fs, 'std', n);
            T.MAD = NMDataIOQCReportTools.col(fs, 'mad', n);
            T.Min = NMDataIOQCReportTools.col(fs, 'min', n);
            T.Max = NMDataIOQCReportTools.col(fs, 'max', n);
            T.OutlierN = NMDataIOQCReportTools.col(fs, 'outlierN', n);
            T.OutlierRate = NMDataIOQCReportTools.col(fs, 'outlierRate', n);
            T.Constant = logical(NMDataIOQCReportTools.col(fs, 'constantFlag', n) ~= 0);
            T.NearConstant = logical(NMDataIOQCReportTools.col(fs, 'nearConstantFlag', n) ~= 0);
        end

        function spatial = exportSpatialArtifacts(state, qc, tmpDir, qcMapDir, figDir, zThreshold)
            spatial = struct('featureMetric','','featureMetricLabel','','mostAbnormalIndex',NaN,'mostAbnormalValue',NaN, ...
                'qcMapFiles',{{}},'snapshotFiles',{{}},'messages',NMDataIOMessageTools.emptyMessages());
            fsName = lower(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(qc, 'featureSpace', '')));
            if strcmp(fsName, 'image_voxel')
                img = NMDataIOQCReportTools.exportVoxelQCMaps(state, qc, tmpDir, qcMapDir, figDir, zThreshold);
                spatial = img;
            elseif strcmp(fsName, 'surface_vertex_registered')
                surf = NMDataIOQCReportTools.exportSurfaceQCMaps(state, qc, tmpDir, qcMapDir, figDir, zThreshold);
                spatial = surf;
            end
        end

        function spatial = exportVoxelQCMaps(state, qc, tmpDir, qcMapDir, figDir, zThreshold)
            spatial = NMDataIOQCReportTools.emptySpatialResult();
            try
                [S, cacheFile] = NMDataIOQCReportTools.loadViewerCache(qc, tmpDir, 'image_qc_metric_overlay');
                spatial.messages = [spatial.messages; NMDataIOMessageTools.make('info', false, 'qcReport.voxel.cache', sprintf('Using the imaging QC data prepared by Preview: %s', cacheFile), 0, 'blue')];
                maskFile = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(S, 'maskFile', NMDataIOQCReportTools.fieldOr(qc, 'maskFile', '')));
                if isempty(maskFile) || exist(maskFile,'file') ~= 2
                    spatial.messages = [spatial.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.voxel.mask', 'Voxel QC map export skipped because the mask/space-defining image file is unavailable.', 2, 'orange')];
                    return;
                end
                metrics = {'feature_missing_rate','feature_mean','feature_std','feature_zero_rate','feature_outlier_rate'};
                names = {'qc_missing_rate','qc_mean','qc_sd','qc_zero_rate', ['qc_outlier_rate_z' NMDataIOQCReportTools.zTag(zThreshold)]};
                vecs = struct();
                for i = 1:numel(metrics)
                    [vec, ~, ~, err] = NMDataIOFeatureQCTools.cachedImageQCMetricVector(S, metrics{i}, zThreshold);
                    if ~isempty(err)
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.voxel.metric', err, 2, 'orange')];
                        continue;
                    end
                    vecs.(metrics{i}) = vec;
                    fbase = fullfile(qcMapDir, names{i});
                    mapFile = NMDataIOQCReportTools.writeVoxelVector(vec, fbase, maskFile, state);
                    spatial.qcMapFiles{end+1} = mapFile;
                    spatial.messages = [spatial.messages; NMDataIOMessageTools.make('ok', false, 'qcReport.voxel.map', sprintf('Wrote voxel QC map: %s', mapFile), 0, 'green*')];
                end
                [metric, vec] = NMDataIOQCReportTools.chooseSpatialFeatureVector(vecs);
                spatial.featureMetric = metric;
                spatial.featureMetricLabel = NMDataIOQCReportTools.metricLabel(metric);
                if ~isempty(vec)
                    [idx, val] = NMDataIOQCReportTools.maxFiniteIndex(vec);
                    spatial.mostAbnormalIndex = idx;
                    spatial.mostAbnormalValue = val;
                    png = fullfile(figDir, 'most_abnormal_voxel.png');
                    [pngOk, pngMsg] = NMDataIOQCReportTools.writeVoxelSnapshot(vec, idx, maskFile, state, png, spatial.featureMetricLabel);
                    if pngOk
                        spatial.snapshotFiles{end+1} = png;
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('ok', false, 'qcReport.voxel.snapshot', sprintf('Wrote most-abnormal voxel snapshot: %s', png), 0, 'green*')];
                    else
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.voxel.snapshot', pngMsg, 2, 'orange')];
                    end
                end
            catch ME
                spatial.messages = [spatial.messages; NMDataIOMessageTools.fromException(ME, 'qcReport.voxel')];
            end
        end

        function spatial = exportSurfaceQCMaps(state, qc, tmpDir, qcMapDir, figDir, zThreshold)
            spatial = NMDataIOQCReportTools.emptySpatialResult();
            try
                [S, cacheFile] = NMDataIOQCReportTools.loadViewerCache(qc, tmpDir, 'surface_qc_metric_overlay');
                spatial.messages = [spatial.messages; NMDataIOMessageTools.make('info', false, 'qcReport.surface.cache', sprintf('Using the surface QC data prepared by Preview: %s', cacheFile), 0, 'blue')];
                metrics = {'feature_missing_rate','feature_mean','feature_std','feature_zero_rate','feature_outlier_rate'};
                names = {'qc_missing_rate','qc_mean','qc_sd','qc_zero_rate', ['qc_outlier_rate_z' NMDataIOQCReportTools.zTag(zThreshold)]};
                vecs = struct();
                for i = 1:numel(metrics)
                    [vec, ~, ~, err] = NMDataIOFeatureQCTools.cachedSurfaceQCMetricVectorForReport(S, metrics{i}, zThreshold);
                    if ~isempty(err)
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.surface.metric', err, 2, 'orange')];
                        continue;
                    end
                    vecs.(metrics{i}) = vec;
                    [mapFile, mapMsg] = NMDataIOQCReportTools.writeSurfaceVector(vec, fullfile(qcMapDir, [names{i} '.func.gii']), fullfile(qcMapDir, [names{i} '.mat']), metrics{i});
                    spatial.qcMapFiles{end+1} = mapFile;
                    spatial.messages = [spatial.messages; mapMsg];
                end
                [metric, vec] = NMDataIOQCReportTools.chooseSpatialFeatureVector(vecs);
                spatial.featureMetric = metric;
                spatial.featureMetricLabel = NMDataIOQCReportTools.metricLabel(metric);
                if ~isempty(vec)
                    [idx, val] = NMDataIOQCReportTools.maxFiniteIndex(vec);
                    spatial.mostAbnormalIndex = idx;
                    spatial.mostAbnormalValue = val;
                    geomFile = NMDataIOQCReportTools.surfaceGeometryFile(state, qc);
                    png = fullfile(figDir, 'most_abnormal_vertex.png');
                    [pngOk, pngMsg] = NMDataIOQCReportTools.writeSurfaceSnapshot(vec, idx, geomFile, png, spatial.featureMetricLabel);
                    if pngOk
                        spatial.snapshotFiles{end+1} = png;
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('ok', false, 'qcReport.surface.snapshot', sprintf('Wrote most-abnormal vertex snapshot: %s', png), 0, 'green*')];
                    else
                        spatial.messages = [spatial.messages; NMDataIOMessageTools.make('warn', false, 'qcReport.surface.snapshot', pngMsg, 2, 'orange')];
                    end
                end
            catch ME
                spatial.messages = [spatial.messages; NMDataIOMessageTools.fromException(ME, 'qcReport.surface')];
            end
        end

        function spatial = emptySpatialResult()
            spatial = struct('featureMetric','','featureMetricLabel','','mostAbnormalIndex',NaN,'mostAbnormalValue',NaN, ...
                'qcMapFiles',{{}},'snapshotFiles',{{}},'messages',NMDataIOMessageTools.emptyMessages());
        end

        function [S, cacheFile] = loadViewerCache(qc, tmpDir, expectedMethod)
            if ~isfield(qc,'viewerOverlay') || ~isstruct(qc.viewerOverlay)
                error('NMDataIOQCReportTools:MissingViewerOverlay', 'The saved QC results do not contain the data needed to create spatial QC maps. Run Preview again.');
            end
            ov = qc.viewerOverlay;
            method = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(ov, 'method', ''));
            if ~strcmp(method, expectedMethod)
                error('NMDataIOQCReportTools:WrongViewerOverlay', 'Expected viewer overlay method %s but found %s.', expectedMethod, method);
            end
            token = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(ov, 'cacheToken', ''));
            if isempty(token)
                error('NMDataIOQCReportTools:MissingCacheToken', 'The saved QC results cannot locate the spatial QC data. Run Preview again.');
            end
            [assetDir, ~, assetErr] = NMDataIOImagePreviewTools.viewerAssetDir(tmpDir);
            if ~isempty(assetErr), error('NMDataIOQCReportTools:ViewerAssetDir', '%s', assetErr); end
            cacheFile = fullfile(assetDir, [token '.mat']);
            if exist(cacheFile,'file') ~= 2
                error('NMDataIOQCReportTools:MissingCacheFile', 'The spatial QC data file cannot be found: %s. Run Preview again.', cacheFile);
            end
            S = load(cacheFile, '-mat');
        end

        function mapFile = writeVoxelVector(vec, fnameNoExt, maskFile, state)
            % writeVoxelVector  Materialize one QC feature vector on the authoritative voxel support mask.
            %
            % Authority and flow:
            %   The original mask path is resolved through NMDataIOImageFileTools before legacy
            %   nk_WriteVol is called, so .nii and .nii.gz follow the same SPM-readable path contract.
            %
            % Materialization and performance:
            %   May gunzip a compressed NIfTI mask into the existing deterministic DataIO cache and
            %   writes one output NIfTI. It is a report/export materialization path, not interactive
            %   viewer navigation.
            %
            % Failure semantics:
            %   An unreadable or unresolvable mask fails explicitly before output materialization.
            if exist('nk_WriteVol','file') ~= 2 && isempty(which('nk_WriteVol'))
                error('NMDataIOQCReportTools:MissingWriteVol', 'nk_WriteVol.m is required to write voxel QC maps.');
            end
            vec = double(vec(:)');
            spaceType = lower(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(state, 'spaceDefType', NMDataIOQCReportTools.fieldOr(state, 'imageSpaceType', 'brainmask'))));
            if strcmp(spaceType,'atlas')
                label = 0; labelop = 'gt';
            else
                label = 0.5; labelop = 'gt';
            end
            [maskFileSPM, maskMessages] = NMDataIOImageFileTools.resolveNiftiFileForSPM(maskFile, 'qcReport.writeVoxelVector.maskFile', true);
            if ~NMDataIOImageFileTools.existsForSPM(maskFileSPM)
                detail = NMDataIOMessageTools.highestPriorityStrip(maskMessages, 'Could not resolve QC mask for SPM.');
                error('NMDataIOQCReportTools:UnreadableMask', '%s', detail.text);
            end
            nk_WriteVol(vec, fnameNoExt, 1, maskFileSPM, [], label, labelop, [], false, false);
            mapFile = [fnameNoExt '.nii'];
        end

        function [ok, msg] = writeVoxelSnapshot(vec, idx, maskFile, state, pngFile, metricLabel)
            % writeVoxelSnapshot  Render a QC snapshot from a voxel vector and its support mask.
            %
            % Authority and flow:
            %   Resolves the support mask through NMDataIOImageFileTools before SPM reads it. This
            %   keeps .nii.gz report rendering aligned with Probe, Import, Preview, and Feature-QC.
            %
            % Materialization and performance:
            %   May gunzip a compressed mask into the existing NIfTI cache, reads one mask volume,
            %   and writes one PNG. It is report generation, not an interactive navigation path.
            %
            % Failure semantics:
            %   Missing SPM support or an unresolvable mask returns an explicit snapshot-skip message;
            %   other rendering failures remain captured by the established report helper semantics.
            ok = false; msg = '';
            try
                if exist('spm_vol','file') ~= 2 || exist('spm_read_vols','file') ~= 2
                    msg = 'Voxel snapshot skipped because SPM spm_vol/spm_read_vols are not available.'; return;
                end
                [maskFileSPM, maskMessages] = NMDataIOImageFileTools.resolveNiftiFileForSPM(maskFile, 'qcReport.writeVoxelSnapshot.maskFile', true);
                if ~NMDataIOImageFileTools.existsForSPM(maskFileSPM)
                    strip = NMDataIOMessageTools.highestPriorityStrip(maskMessages, 'Could not resolve QC mask for SPM.');
                    msg = strip.text; return;
                end
                Vm = spm_vol(maskFileSPM); if numel(Vm) > 1, Vm = Vm(1); end
                maskVol = spm_read_vols(Vm);
                spaceType = lower(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(state, 'spaceDefType', 'brainmask')));
                if strcmp(spaceType,'atlas')
                    mask = isfinite(maskVol) & maskVol > 0;
                else
                    mask = isfinite(maskVol) & maskVol > 0.5;
                end
                vol = nan(Vm.dim(1:3));
                vol(mask) = double(vec(:));
                if ~isfinite(idx) || idx < 1
                    msg = 'Voxel snapshot skipped because no finite abnormal voxel was found.'; return;
                end
                inds = find(mask);
                if idx > numel(inds), msg = 'Voxel snapshot skipped because the abnormal voxel index exceeds the support mask.'; return; end
                [x,y,z] = ind2sub(Vm.dim(1:3), inds(round(idx)));
                sl = squeeze(vol(:,:,z));
                finite = sl(isfinite(sl));
                if isempty(finite), msg = 'Voxel snapshot skipped because selected slice contains no finite QC values.'; return; end
                lo = min(finite); hi = max(finite); if hi <= lo, hi = lo + eps; end
                img = (sl - lo) ./ (hi - lo);
                img(~isfinite(img)) = 0;
                rgb = ind2rgb(uint8(max(0,min(1,img))*255), parula(256));
                rgb = rot90(rgb);
                sz0 = size(rgb);
                yy = sz0(1) - y + 1; xx = x;
                yy = min(max(yy,1),sz0(1)); xx = min(max(xx,1),sz0(2));
                scale = max(1, min(8, floor(520 / max(1, min(sz0(1), sz0(2))))));
                if scale > 1
                    rgb = repelem(rgb, scale, scale, 1);
                    yy = round((yy - 0.5) * scale + 0.5);
                    xx = round((xx - 0.5) * scale + 0.5);
                end
                sz = size(rgb);
                yy = min(max(yy,1),sz(1)); xx = min(max(xx,1),sz(2));
                radius = max(6, round(0.035 * min(sz(1), sz(2))));
                thickness = max(1, round(radius * 0.10));
                [rr, cc] = ndgrid(1:sz(1), 1:sz(2));
                ring = abs(sqrt((rr - yy).^2 + (cc - xx).^2) - radius) <= thickness;
                markerColor = [1 0 1];
                for ch = 1:3
                    plane = rgb(:,:,ch);
                    plane(ring) = markerColor(ch);
                    rgb(:,:,ch) = plane;
                end
                imwrite(rgb, pngFile, 'png');
                ok = true;
                msg = sprintf('Most abnormal voxel by %s: feature %g, mask-space voxel [%g %g %g].', metricLabel, idx, x, y, z);
            catch ME
                msg = sprintf('Voxel snapshot failed: %s: %s', ME.identifier, ME.message);
            end
        end

        function [mapFile, message] = writeSurfaceVector(vec, giiFile, matFile, metricKey)
            vec = double(vec(:));
            mapFile = '';
            try
                if exist('gifti','file') == 2 || exist('gifti','class') == 8 || ~isempty(which('gifti'))
                    g = gifti;
                    g.cdata = single(vec);
                    save(g, giiFile);
                    mapFile = giiFile;
                    message = NMDataIOMessageTools.make('ok', false, 'qcReport.surface.gii', sprintf('Wrote surface QC GIFTI map: %s', giiFile), 0, 'green*');
                    return;
                end
                metric = metricKey; values = vec; %#ok<NASGU>
                save(matFile, 'values', 'metric', '-v7');
                mapFile = matFile;
                message = NMDataIOMessageTools.make('warn', false, 'qcReport.surface.matFallback', sprintf('GIFTI writer unavailable; wrote surface QC MAT fallback: %s', matFile), 2, 'orange');
            catch ME
                metric = metricKey; values = vec; %#ok<NASGU>
                save(matFile, 'values', 'metric', '-v7');
                mapFile = matFile;
                message = NMDataIOMessageTools.make('warn', false, 'qcReport.surface.matFallback', sprintf('Surface GIFTI export failed (%s: %s); wrote MAT fallback: %s', ME.identifier, ME.message, matFile), 2, 'orange');
            end
        end

        function [ok, msg] = writeSurfaceSnapshot(vec, idx, geometryFile, pngFile, metricLabel)
            ok = false; msg = '';
            try
                if isempty(geometryFile) || exist(geometryFile,'file') ~= 2
                    msg = 'Surface snapshot skipped because no valid shared Surface display mesh is available.'; return;
                end
                [vertices, faces] = NMDataIOSurfaceTools.readSurfaceGeometry(geometryFile);
                if size(vertices,1) ~= numel(vec)
                    msg = sprintf('Surface snapshot skipped: QC vector has %g vertices but display mesh has %g vertices.', numel(vec), size(vertices,1)); return;
                end
                f = figure('Visible','off','Color','w','Position',[100 100 1000 780]);
                cleanup = onCleanup(@() close(f)); %#ok<NASGU>
                finite = vec(isfinite(vec));
                if isempty(finite), msg = 'Surface snapshot skipped because QC vector has no finite values.'; return; end
                p = patch('Vertices',vertices,'Faces',faces,'FaceVertexCData',double(vec(:)), ...
                    'FaceColor','interp','EdgeColor','none','FaceAlpha',1);
                axis equal off; camlight('headlight'); lighting gouraud; colormap(parula(256)); colorbar;
                title(sprintf('Most abnormal vertex by %s', metricLabel), 'Interpreter','none');
                if isfinite(idx) && idx >= 1 && idx <= size(vertices,1)
                    hold on;
                    v = vertices(round(idx),:);
                    scatter3(v(1),v(2),v(3),120,'r','filled','MarkerEdgeColor','k','LineWidth',1.5);
                end
                view(90,0);
                if exist('exportgraphics','file') == 2
                    exportgraphics(f, pngFile, 'Resolution', 150);
                else
                    saveas(f, pngFile);
                end
                ok = true;
                msg = sprintf('Most abnormal vertex by %s: vertex %g.', metricLabel, idx);
            catch ME
                msg = sprintf('Surface snapshot failed: %s: %s', ME.identifier, ME.message);
            end
        end

        function geomFile = surfaceGeometryFile(state, qc)
            geomFile = '';
            if isstruct(qc) && isfield(qc,'spatialMapping') && isstruct(qc.spatialMapping)
                geomFile = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(qc.spatialMapping, 'surfaceGeometryFile', ''));
            end
            if isempty(geomFile)
                geomFile = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(state, 'surfaceGeometryFile', ''));
            end
        end

        function [metric, vec] = chooseSpatialFeatureVector(vecs)
            candidates = {'feature_outlier_rate','feature_missing_rate','feature_zero_rate','feature_std'};
            metric = ''; vec = [];
            for i = 1:numel(candidates)
                key = candidates{i};
                if isfield(vecs, key)
                    v = double(vecs.(key));
                    finite = v(isfinite(v));
                    if ~isempty(finite) && max(finite) > 0
                        metric = key; vec = v; return;
                    end
                end
            end
            if isfield(vecs,'feature_mean')
                metric = 'feature_mean'; vec = double(vecs.feature_mean);
            end
        end

        function [idx, val] = maxFiniteIndex(vec)
            vec = double(vec(:));
            valid = find(isfinite(vec));
            if isempty(valid), idx = NaN; val = NaN; return; end
            [~, pos] = max(abs(vec(valid)));
            idx = double(valid(pos));
            val = double(vec(valid(pos)));
        end

        function [metric, topT] = rankFeatureTable(T, k)
            if nargin < 2, k = 10; end
            orderFields = {'OutlierRate','MissingRate','ZeroRate','Std'};
            metric = '';
            vals = [];
            for i = 1:numel(orderFields)
                fld = orderFields{i};
                if ismember(fld, T.Properties.VariableNames)
                    v = double(T.(fld));
                    if any(isfinite(v) & v > 0)
                        metric = fld; vals = v; break;
                    end
                end
            end
            if isempty(metric)
                metric = 'FeatureIndex'; vals = double(T.FeatureIndex);
            end
            vals(~isfinite(vals)) = -Inf;
            [~,ord] = sort(vals, 'descend');
            ord = ord(1:min(k,numel(ord)));
            topT = T(ord,:);
        end

        function [files, messages] = writeTablePair(T, outDir, stem)
            files = struct('csv','','xlsx','');
            messages = NMDataIOMessageTools.emptyMessages();
            csvFile = fullfile(outDir, [stem '.csv']);
            xlsxFile = fullfile(outDir, [stem '.xlsx']);
            try
                writetable(T, csvFile);
                files.csv = csvFile;
                messages = [messages; NMDataIOMessageTools.make('ok', false, ['qcReport.' stem '.csv'], sprintf('Wrote CSV table: %s', csvFile), 0, 'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.fromException(ME, ['qcReport.' stem '.csv'])];
            end
            try
                writetable(T, xlsxFile);
                files.xlsx = xlsxFile;
                messages = [messages; NMDataIOMessageTools.make('ok', false, ['qcReport.' stem '.xlsx'], sprintf('Wrote XLSX table: %s', xlsxFile), 0, 'green*')];
            catch ME
                messages = [messages; NMDataIOMessageTools.make('warn', false, ['qcReport.' stem '.xlsx'], sprintf('XLSX export failed for %s: %s: %s', xlsxFile, ME.identifier, ME.message), 2, 'orange')];
            end
        end

        function [out, messages] = writeDataIOAuditTables(out, tables, bundleDir)
            % writeDataIOAuditTables  Export backend-derived DataIO attrition ledgers without recomputing import semantics.
            messages = NMDataIOMessageTools.emptyMessages();
            specs = { ...
                'filters','dataio_source_filtering','dataIOFilterCsvFile','dataIOFilterXlsxFile'; ...
                'axis','dataio_case_axis','dataIOAxisCsvFile','dataIOAxisXlsxFile'; ...
                'blocks','dataio_source_blocks','dataIOBlockCsvFile','dataIOBlockXlsxFile'; ...
                'duplicates','dataio_duplicate_keys','dataIODuplicateCsvFile','dataIODuplicateXlsxFile'};
            for i = 1:size(specs,1)
                T = tables.(specs{i,1});
                if isempty(T) || ~istable(T) || height(T) < 1, continue; end
                [files, tableMessages] = NMDataIOQCReportTools.writeTablePair(T, bundleDir, specs{i,2});
                messages = [messages; tableMessages]; %#ok<AGROW>
                out.(specs{i,3}) = files.csv;
                out.(specs{i,4}) = files.xlsx;
            end
        end

        function tables = dataIOAuditTables(audit)
            % dataIOAuditTables  Flatten the observational materialisation ledger for report/export use.
            tables = struct('filters',table(),'axis',table(),'blocks',table(),'duplicates',table());
            if ~isstruct(audit) || isempty(fieldnames(audit)), return; end

            sourceObject = {}; applied = []; matchMode = {}; ruleIndex = []; scope = {}; scopeId = {}; column = {}; operator = {}; criterion = {};
            inputRows = []; ruleMatches = []; retainedAfterRule = []; finalRows = [];
            objects = NMDataIOQCReportTools.fieldOr(audit,'sourceObjects',{});
            if isstruct(objects), objects = num2cell(objects); elseif ~iscell(objects), objects = {}; end
            if ~isempty(objects)
                for i = 1:numel(objects)
                    obj = objects{i};
                    label = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(obj,'sourceLabel',''));
                    if isempty(label), label = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(obj,'sourceObject','')); end
                    if isempty(label), label = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(obj,'sourcePath','')); end
                    rules = NMDataIOQCReportTools.fieldOr(obj,'rules',struct([]));
                    if ~isstruct(rules), rules = struct([]); end
                    if isempty(rules)
                        sourceObject{end+1,1}=label; applied(end+1,1)=double(logical(NMDataIOQCReportTools.fieldOr(obj,'applied',false))); %#ok<AGROW>
                        matchMode{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(obj,'match','')); ruleIndex(end+1,1)=0; %#ok<AGROW>
                        scope{end+1,1}=''; scopeId{end+1,1}=''; column{end+1,1}=''; operator{end+1,1}=''; criterion{end+1,1}=''; %#ok<AGROW>
                        inputRows(end+1,1)=double(NMDataIOQCReportTools.fieldOr(obj,'nInput',NaN)); ruleMatches(end+1,1)=NaN; retainedAfterRule(end+1,1)=NaN; finalRows(end+1,1)=double(NMDataIOQCReportTools.fieldOr(obj,'nOutput',NaN)); %#ok<AGROW>
                    else
                        for r = 1:numel(rules)
                            rule = rules(r);
                            sourceObject{end+1,1}=label; applied(end+1,1)=double(logical(NMDataIOQCReportTools.fieldOr(obj,'applied',false))); %#ok<AGROW>
                            matchMode{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(obj,'match','')); ruleIndex(end+1,1)=double(NMDataIOQCReportTools.fieldOr(rule,'index',r)); %#ok<AGROW>
                            scope{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rule,'scope','object')); scopeId{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rule,'scopeId','')); %#ok<AGROW>
                            column{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rule,'column','')); operator{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rule,'operator','')); criterion{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rule,'value','')); %#ok<AGROW>
                            inputRows(end+1,1)=double(NMDataIOQCReportTools.fieldOr(obj,'nInput',NaN)); ruleMatches(end+1,1)=double(NMDataIOQCReportTools.fieldOr(rule,'nMatched',NaN)); retainedAfterRule(end+1,1)=double(NMDataIOQCReportTools.fieldOr(rule,'nRetainedAfterRule',NaN)); finalRows(end+1,1)=double(NMDataIOQCReportTools.fieldOr(obj,'nOutput',NaN)); %#ok<AGROW>
                        end
                    end
                end
            end
            if ~isempty(sourceObject)
                tables.filters = table(sourceObject,applied,matchMode,ruleIndex,scope,scopeId,column,operator,criterion,inputRows,ruleMatches,retainedAfterRule,finalRows, ...
                    'VariableNames',{'SourceObject','FilterApplied','CombineMode','RuleIndex','Scope','ScopeID','Column','Operator','Criterion','InputRows','RuleMatches','RowsRetainedAfterRule','FinalRows'});
            end

            steps = NMDataIOQCReportTools.fieldOr(NMDataIOQCReportTools.fieldOr(audit,'caseAxis',struct()),'steps',{});
            if isstruct(steps), steps = num2cell(steps); elseif ~iscell(steps), steps = {}; end
            if ~isempty(steps)
                n = numel(steps); order=zeros(n,1); operation=cell(n,1); role=cell(n,1); block=cell(n,1); before=zeros(n,1); incoming=zeros(n,1); after=zeros(n,1); removed=zeros(n,1); added=zeros(n,1);
                for i=1:n
                    order(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'order',i)); operation{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(steps{i},'operation','')); role{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(steps{i},'role','')); block{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(steps{i},'blockName',''));
                    before(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'nBefore',NaN)); incoming(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'nIncoming',NaN)); after(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'nAfter',NaN)); removed(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'nRemoved',NaN)); added(i)=double(NMDataIOQCReportTools.fieldOr(steps{i},'nAdded',NaN));
                end
                tables.axis = table(order,operation,role,block,before,incoming,after,removed,added,'VariableNames',{'Step','Operation','Role','Block','Before','Incoming','After','Removed','Added'});
            end

            blocks = NMDataIOQCReportTools.fieldOr(audit,'blocks',{});
            if isstruct(blocks), blocks = num2cell(blocks); elseif ~iscell(blocks), blocks = {}; end
            if ~isempty(blocks)
                n=numel(blocks); role=cell(n,1); block=cell(n,1); source=cell(n,1); sourceRows=zeros(n,1); columns=zeros(n,1); keyRows=zeros(n,1); uniqueKeys=zeros(n,1); duplicateTuples=zeros(n,1); duplicateRows=zeros(n,1); matchedAxis=zeros(n,1); missingAxis=zeros(n,1); unmatchedSource=zeros(n,1); finiteSource=zeros(n,1); sourceNaN=zeros(n,1); conversionFailures=zeros(n,1); finiteAligned=zeros(n,1); alignedNaN=zeros(n,1); alignmentNaN=zeros(n,1);
                for i=1:n
                    b=blocks{i}; role{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'role','')); block{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'name','')); source{i}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'sourceLabel',NMDataIOQCReportTools.fieldOr(b,'sourceKey','')));
                    sourceRows(i)=double(NMDataIOQCReportTools.fieldOr(b,'nSourceRows',NaN)); columns(i)=double(NMDataIOQCReportTools.fieldOr(b,'nColumns',NaN)); keyRows(i)=double(NMDataIOQCReportTools.fieldOr(b,'nKeyRows',NaN)); uniqueKeys(i)=double(NMDataIOQCReportTools.fieldOr(b,'nUniqueKeys',NaN)); duplicateTuples(i)=double(NMDataIOQCReportTools.fieldOr(b,'nDuplicateTuples',NaN)); duplicateRows(i)=double(NMDataIOQCReportTools.fieldOr(b,'nDuplicateRows',NaN));
                    matchedAxis(i)=double(NMDataIOQCReportTools.fieldOr(b,'nMatchedReferenceCases',NaN)); missingAxis(i)=double(NMDataIOQCReportTools.fieldOr(b,'nMissingReferenceCases',NaN)); unmatchedSource(i)=double(NMDataIOQCReportTools.fieldOr(b,'nUnmatchedSourceCases',NaN)); finiteSource(i)=double(NMDataIOQCReportTools.fieldOr(b,'nFiniteSourceValues',NaN)); sourceNaN(i)=double(NMDataIOQCReportTools.fieldOr(b,'nSourceNaNValues',NaN)); conversionFailures(i)=double(NMDataIOQCReportTools.fieldOr(b,'nConversionFailures',NaN)); finiteAligned(i)=double(NMDataIOQCReportTools.fieldOr(b,'nFiniteAlignedValues',NaN)); alignedNaN(i)=double(NMDataIOQCReportTools.fieldOr(b,'nAlignedNaNValues',NaN)); alignmentNaN(i)=double(NMDataIOQCReportTools.fieldOr(b,'nAlignmentInducedNaNValues',NaN));
                end
                tables.blocks = table(role,block,source,sourceRows,columns,keyRows,uniqueKeys,duplicateTuples,duplicateRows,matchedAxis,missingAxis,unmatchedSource,finiteSource,sourceNaN,conversionFailures,finiteAligned,alignedNaN,alignmentNaN, ...
                    'VariableNames',{'Role','Block','SourceObject','SourceRows','Columns','KeyRows','UniqueKeys','DuplicateTuples','DuplicateRows','MatchedAxisCases','MissingAxisCases','UnmatchedSourceCases','FiniteSourceValues','SourceNaNValues','ConversionFailures','FiniteAlignedValues','AlignedNaNValues','AlignmentInducedNaNValues'});
            end

            dRole={}; dBlock={}; dSource={}; dKey={}; dRows={};
            if ~isempty(blocks)
                for i=1:numel(blocks)
                    b=blocks{i}; examples=NMDataIOQCReportTools.fieldOr(b,'duplicateKeys',struct([]));
                    if ~isstruct(examples), continue; end
                    for e=1:numel(examples)
                        dRole{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'role','')); dBlock{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'name','')); dSource{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(b,'sourceLabel',NMDataIOQCReportTools.fieldOr(b,'sourceKey',''))); %#ok<AGROW>
                        dKey{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(examples(e),'keyText','')); rows=double(NMDataIOQCReportTools.fieldOr(examples(e),'rows',[])); dRows{end+1,1}=strtrim(sprintf('%g, ',rows)); if ~isempty(dRows{end}), dRows{end}=regexprep(dRows{end},',\s*$',''); end %#ok<AGROW>
                    end
                end
            end
            if ~isempty(dRole), tables.duplicates=table(dRole,dBlock,dSource,dKey,dRows,'VariableNames',{'Role','Block','SourceObject','KeyTuple','SourceRows'}); end
        end

        function T = qcHistoryTable(NM, state)
            % qcHistoryTable  Summarize already archived QC objects for the selected import target.
            T = table();
            if ~isstruct(NM) || ~isstruct(state), return; end
            varind = double(NMDataIOQCReportTools.fieldOr(state,'varind',1));
                target = NMDataIOImportTargetTools.normalize(NM, state, varind);
                [D, messages] = NMDataIOImportTargetTools.getContainer(NM, target);
                if NMDataIOMessageTools.hasFatal(messages) || ~isstruct(D) || ~isfield(D,'datadescriptor') || ~iscell(D.datadescriptor) || numel(D.datadescriptor)<target.varind || ~isstruct(D.datadescriptor{target.varind}), return; end
                dd=D.datadescriptor{target.varind}; history=NMDataIOQCReportTools.fieldOr(dd,'QC_history',{});
                if isempty(history), return; end
                if ~iscell(history), history={history}; end
                archivedAt={}; reason={}; sourceType={}; featureSpace={}; subjects=[]; features=[]; validFeatures=[]; auditStatus={}; finalCases=[]; finalFeatures=[];
                for i=1:numel(history)
                    item=history{i}; if ~isstruct(item), continue; end
                    qObj=NMDataIOQCReportTools.fieldOr(item,'QC',struct()); payload=NMDataIOQCReportTools.fieldOr(qObj,'payload',struct()); if ~isstruct(payload), payload=struct(); end
                    a=NMDataIOQCReportTools.fieldOr(payload,'dataIOAudit',struct());
                    archivedAt{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(item,'archivedAt','')); reason{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(item,'reason','')); sourceType{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(payload,'sourceType','')); featureSpace{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(payload,'featureSpace','')); %#ok<AGROW>
                    subjects(end+1,1)=double(NMDataIOQCReportTools.fieldOr(payload,'nSubjects',NaN)); features(end+1,1)=double(NMDataIOQCReportTools.fieldOr(payload,'nFeatures',NaN)); validFeatures(end+1,1)=double(NMDataIOQCReportTools.fieldOr(payload,'nValidFeatures',NaN)); %#ok<AGROW>
                    auditStatus{end+1,1}=NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(a,'status','')); finalCases(end+1,1)=double(NMDataIOQCReportTools.fieldOr(a,'nFinalCases',NaN)); finalFeatures(end+1,1)=double(NMDataIOQCReportTools.fieldOr(a,'nFinalFeatures',NaN)); %#ok<AGROW>
                end
            if ~isempty(archivedAt), T=table(archivedAt,reason,sourceType,featureSpace,subjects,features,validFeatures,auditStatus,finalCases,finalFeatures,'VariableNames',{'ArchivedAt','Reason','SourceType','FeatureSpace','Subjects','Features','ValidFeatures','DataIOAuditStatus','FinalCases','FinalFeatures'}); end
        end

        function html = buildHTMLReport(state, qc, diagnostics, subj, featureExport, spatial, audit, auditTables, historyTable, subjectMetric, zThreshold, out)
            titleTxt = 'NeuroMiner DataIO QC Report';
            featureSpace = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(qc,'featureSpace',''));
            sourceType = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(qc,'sourceType',''));
            topK = max(1, ceil(height(subj) * 0.10));
            subjTop = NMDataIOQCReportTools.topSubjects(subj, subjectMetric, topK);
            parts = {};
            parts{end+1} = '<!doctype html><html><head><meta charset="utf-8"><title>NeuroMiner DataIO QC Report</title>';
            parts{end+1} = ['<style>' NMDataIOQCReportTools.reportCSS() '</style></head><body>'];
            parts{end+1} = '<button class="printBtn" onclick="window.print()">Print / Save as PDF</button>';
            parts{end+1} = ['<h1>' NMDataIOQCReportTools.esc(titleTxt) '</h1>'];
            parts{end+1} = ['<p class="muted">Generated ' NMDataIOQCReportTools.esc(datestr(now)) '</p>'];
            parts{end+1} = '<h2>Import/QC overview</h2>';
            overview = table({'Source type';'Feature space';'Subjects';'Features';'Valid z-score features';'Outlier z-threshold'}, ...
                {sourceType;featureSpace;double(NMDataIOQCReportTools.fieldOr(qc,'nSubjects',0));double(NMDataIOQCReportTools.fieldOr(qc,'nFeatures',0));double(NMDataIOQCReportTools.fieldOr(qc,'nValidFeatures',0));zThreshold}, ...
                'VariableNames',{'Metric','Value'});
            parts{end+1} = NMDataIOQCReportTools.tableToHTML(overview, 50);
            parts{end+1} = NMDataIOQCReportTools.summaryRowsHTML(qc);
            parts{end+1} = '<h2>Subject-level QC distribution</h2>';
            parts{end+1} = ['<p>Ranked by selected subject-level metric: <b>' NMDataIOQCReportTools.esc(subjectMetric) '</b>. The vertical marker denotes the 90th percentile / top-10% abnormality threshold.</p>'];
            parts{end+1} = NMDataIOQCReportTools.subjectMetricHistogramHTML(subj, subjectMetric);
            parts{end+1} = '<h2>Top 10% most abnormal subjects</h2>';
            parts{end+1} = NMDataIOQCReportTools.tableToHTML(subjTop, max(1, height(subjTop)));
            parts{end+1} = '<h2>Subject-level metric exports</h2><ul>';
            parts{end+1} = NMDataIOQCReportTools.pathListItem('CSV', out.subjectCsvFile);
            parts{end+1} = NMDataIOQCReportTools.pathListItem('XLSX', out.subjectXlsxFile);
            parts{end+1} = '</ul>';
            parts{end+1} = '<h2>Feature-level QC</h2>';
            if featureExport.allowed
                parts{end+1} = ['<p>Top abnormal features ranked by: <b>' NMDataIOQCReportTools.esc(featureExport.rankingMetric) '</b>.</p>'];
                parts{end+1} = NMDataIOQCReportTools.tableToHTML(featureExport.topTable, 10);
                parts{end+1} = '<ul>';
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Feature CSV', featureExport.csv);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Feature XLSX', featureExport.xlsx);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Feature MAT', featureExport.mat);
                parts{end+1} = '</ul>';
            else
                parts{end+1} = ['<p>' NMDataIOQCReportTools.esc(featureExport.reason) '</p>'];
            end
            parts{end+1} = '<h2>Data source and case accounting</h2>';
            if isstruct(audit) && ~isempty(fieldnames(audit))
                parts{end+1} = ['<p class="note">Counts calculated during Preview after filtering and Case-ID matching. Use these tables to document how rows and cases were retained or excluded, for example in CONSORT/TRIPOD-AI flow reporting. The report does not repeat the import.</p>' ...
                    '<p><b>Status:</b> ' NMDataIOQCReportTools.esc(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(audit,'status',''))) ...
                    ' &nbsp; <b>Alignment:</b> ' NMDataIOQCReportTools.esc(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(audit,'alignmentMode',''))) ...
                    ' &nbsp; <b>Case-list policy:</b> ' NMDataIOQCReportTools.esc(NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(audit,'caseAxisPolicy',''))) '</p>'];
                parts{end+1} = '<h3>Row filtering</h3>';
                parts{end+1} = NMDataIOQCReportTools.tableToHTML(auditTables.filters, 500);
                parts{end+1} = '<h3>Case list construction</h3>';
                parts{end+1} = NMDataIOQCReportTools.tableToHTML(auditTables.axis, 500);
                parts{end+1} = '<h3>Case-ID matching and data preparation</h3>';
                parts{end+1} = NMDataIOQCReportTools.tableToHTML(auditTables.blocks, 500);
                if ~isempty(auditTables.duplicates) && height(auditTables.duplicates) > 0
                    parts{end+1} = '<h3>Duplicate Case-ID combinations</h3><p class="note">Each duplicated Case-ID combination is shown on a separate row with its source row numbers when available. Correct the duplicates or refine the Case-ID key before Commit.</p>';
                    parts{end+1} = NMDataIOQCReportTools.tableToHTML(auditTables.duplicates, 500);
                end
                parts{end+1} = '<h3>Case-accounting exports</h3><ul>';
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Source filtering CSV', out.dataIOFilterCsvFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Source filtering XLSX', out.dataIOFilterXlsxFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Case list CSV', out.dataIOAxisCsvFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Case list XLSX', out.dataIOAxisXlsxFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Input matching CSV', out.dataIOBlockCsvFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Input matching XLSX', out.dataIOBlockXlsxFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Duplicate Case-ID CSV', out.dataIODuplicateCsvFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('Duplicate Case-ID XLSX', out.dataIODuplicateXlsxFile);
                parts{end+1} = '</ul>';
            else
                parts{end+1} = '<p class="muted">No tabular data-source and case-accounting information is available for these QC results.</p>';
            end
            parts{end+1} = '<h2>Historical QC trace</h2>';
            if ~isempty(historyTable) && height(historyTable) > 0
                parts{end+1} = '<p class="muted">Previous QC results saved before this modality was modified or re-imported.</p>';
                parts{end+1} = NMDataIOQCReportTools.tableToHTML(historyTable, 200);
                parts{end+1} = '<ul>';
                parts{end+1} = NMDataIOQCReportTools.pathListItem('QC history CSV', out.qcHistoryCsvFile);
                parts{end+1} = NMDataIOQCReportTools.pathListItem('QC history XLSX', out.qcHistoryXlsxFile);
                parts{end+1} = '</ul>';
            else
                parts{end+1} = '<p class="muted">No previous QC results are associated with this modality.</p>';
            end
            if ~isempty(spatial.qcMapFiles) || ~isempty(spatial.snapshotFiles)
                parts{end+1} = '<h2>Spatial QC artifacts</h2>';
                if strcmp(featureSpace,'surface_vertex_registered')
                    parts{end+1} = '<p class="note">Surface group QC maps are rendered/exported in the registered/template vertex feature space and displayed on the shared Surface display mesh, not on individual subject morphology.</p>';
                end
                parts{end+1} = '<ul>';
                for i = 1:numel(spatial.qcMapFiles), parts{end+1} = NMDataIOQCReportTools.pathListItem('QC map', spatial.qcMapFiles{i}); end
                parts{end+1} = '</ul>';
                for i = 1:numel(spatial.snapshotFiles)
                    [~,nm,ext] = fileparts(spatial.snapshotFiles{i});
                    rel = ['figures/' nm ext];
                    parts{end+1} = ['<figure><img src="' NMDataIOQCReportTools.esc(rel) '" alt="Spatial QC snapshot"><figcaption>Most abnormal spatial feature by ' NMDataIOQCReportTools.esc(spatial.featureMetricLabel) ', index ' num2str(spatial.mostAbnormalIndex) ', value ' num2str(spatial.mostAbnormalValue) '.</figcaption></figure>'];
                end
            end
            parts{end+1} = '<h2>Diagnostics</h2>';
            parts{end+1} = NMDataIOQCReportTools.diagnosticsHTML(diagnostics);
            parts{end+1} = '</body></html>';
            html = strjoin(parts, sprintf('\n'));
        end

        function html = subjectMetricHistogramHTML(T, metric)
            html = '<p class="muted">No finite subject-level QC values were available for the selected metric.</p>';
            if isempty(T) || height(T) < 1, return; end
            field = NMDataIOQCReportTools.subjectMetricField(metric);
            if ~ismember(field, T.Properties.VariableNames), field = 'RMSZ'; end
            spec = NMDataIOFeatureQCTools.subjectMetricHistogramSpec(T.(field));
            if ~isstruct(spec) || ~isfield(spec,'available') || ~spec.available, return; end
            edges = double(spec.edges(:)'); counts = double(spec.counts(:)');
            nbins = numel(counts); lo = edges(1); hi = edges(end); thr = double(spec.outlierThreshold);
            w = 760; h = 220; left = 48; right = 18; top = 18; bottom = 36;
            plotW = w - left - right; plotH = h - top - bottom;
            maxCount = max(counts); if maxCount < 1, maxCount = 1; end
            parts = {};
            parts{end+1} = sprintf('<svg class="qcHistogram" width="%g" height="%g" viewBox="0 0 %g %g" role="img" aria-label="Subject-level QC histogram">', w, h, w, h);
            parts{end+1} = '<rect x="0" y="0" width="100%" height="100%" fill="#ffffff"/>';
            parts{end+1} = sprintf('<line x1="%g" y1="%g" x2="%g" y2="%g" stroke="#667085" stroke-width="1"/>', left, top+plotH, left+plotW, top+plotH);
            for b = 1:nbins
                x0 = left + (b-1) * plotW / nbins;
                bw = max(1, plotW / nbins - 2);
                bh = counts(b) / maxCount * plotH;
                y0 = top + plotH - bh;
                binLo = edges(b); binHi = edges(b+1);
                if binHi <= thr
                    parts{end+1} = sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#cbd5e1"/>', x0, y0, bw, bh);
                elseif binLo >= thr
                    parts{end+1} = sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#ef4444"/>', x0, y0, bw, bh);
                else
                    xSplit = left + (thr - lo) / (hi - lo) * plotW;
                    xSplit = max(x0, min(x0 + bw, xSplit));
                    greyW = max(0, xSplit - x0);
                    redW = max(0, x0 + bw - xSplit);
                    if greyW > 0
                        parts{end+1} = sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#cbd5e1"/>', x0, y0, greyW, bh);
                    end
                    if redW > 0
                        parts{end+1} = sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="#ef4444"/>', xSplit, y0, redW, bh);
                    end
                end
            end
            xThr = left + (thr - lo) / (hi - lo) * plotW;
            parts{end+1} = sprintf('<line x1="%.2f" y1="%g" x2="%.2f" y2="%g" stroke="#b91c1c" stroke-width="2"/>', xThr, top, xThr, top+plotH);
            parts{end+1} = sprintf('<text x="%g" y="%g" font-size="11" fill="#334155">%s</text>', left, h-12, NMDataIOQCReportTools.esc(sprintf('min %.4g', lo)));
            parts{end+1} = sprintf('<text x="%g" y="%g" font-size="11" fill="#334155" text-anchor="end">%s</text>', left+plotW, h-12, NMDataIOQCReportTools.esc(sprintf('max %.4g', hi)));
            parts{end+1} = sprintf('<text x="%.2f" y="%g" font-size="11" fill="#b91c1c" text-anchor="middle">top 10%% threshold %.4g</text>', xThr, top+12, thr);
            parts{end+1} = '</svg>';
            html = strjoin(parts, '');
        end

        function T = topSubjects(T, metric, k)
            if nargin < 3, k = 20; end
            field = NMDataIOQCReportTools.subjectMetricField(metric);
            if ~ismember(field, T.Properties.VariableNames), field = 'RMSZ'; end
            vals = double(T.(field)); vals(~isfinite(vals)) = -Inf;
            [~,ord] = sort(vals, 'descend');
            ord = ord(1:min(k,numel(ord)));
            T = T(ord,:);
            T.Rank = (1:height(T))';
            T = movevars(T, 'Rank', 'Before', 1);
        end

        function field = subjectMetricField(metric)
            switch char(metric)
                case 'meanAbsZ', field = 'MeanAbsZ';
                case 'maxAbsZ', field = 'MaxAbsZ';
                case 'missingFeatureRateBySubject', field = 'MissingFeatureRate';
                case 'zeroFeatureRateBySubject', field = 'ZeroFeatureRate';
                case 'outlierFeatureRateBySubject', field = 'OutlierFeatureRate';
                case 'nMissingFeaturesBySubject', field = 'MissingFeatureN';
                case 'nZeroFeaturesBySubject', field = 'ZeroFeatureN';
                case 'nOutlierFeaturesBySubject', field = 'OutlierFeatureN';
                case 'nValidFeaturesBySubject', field = 'ValidZFeatureN';
                case 'nFiniteFeaturesBySubject', field = 'FiniteFeatureN';
                otherwise, field = 'RMSZ';
            end
        end

        function html = summaryRowsHTML(qc)
            html = '';
            if ~isfield(qc,'reportPayload') || ~isstruct(qc.reportPayload) || ~isfield(qc.reportPayload,'summaryRows'), return; end
            rows = qc.reportPayload.summaryRows;
            if isempty(rows), return; end
            metric = cell(numel(rows),1); value = cell(numel(rows),1);
            for i = 1:numel(rows)
                metric{i} = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(rows(i),'metric',''));
                v = NMDataIOQCReportTools.fieldOr(rows(i),'value','');
                if isnumeric(v), value{i} = num2str(v); else, value{i} = NMDataIOQCReportTools.asChar(v); end
            end
            T = table(metric, value, 'VariableNames', {'Metric','Value'});
            html = ['<h3>QC summary</h3>' NMDataIOQCReportTools.tableToHTML(T, 100)];
        end

        function html = diagnosticsHTML(diagnostics)
            msgs = [];
            if isstruct(diagnostics) && isfield(diagnostics,'messages'), msgs = diagnostics.messages; end
            if isempty(msgs) || ~isstruct(msgs)
                html = '<p class="muted">No diagnostics supplied to the report generator.</p>'; return;
            end
            level = cell(numel(msgs),1); source = cell(numel(msgs),1); text = cell(numel(msgs),1);
            for i = 1:numel(msgs)
                level{i} = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(msgs(i),'level',''));
                source{i} = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(msgs(i),'source',''));
                text{i} = NMDataIOQCReportTools.asChar(NMDataIOQCReportTools.fieldOr(msgs(i),'text',''));
            end
            T = table(level, source, text, 'VariableNames', {'Level','Source','Text'});
            html = NMDataIOQCReportTools.tableToHTML(T, 200);
        end

        function html = tableToHTML(T, maxRows)
            if isempty(T) || height(T) < 1
                html = '<p class="muted">No rows.</p>'; return;
            end
            if nargin < 2 || isempty(maxRows), maxRows = height(T); end
            T = T(1:min(maxRows,height(T)),:);
            vars = T.Properties.VariableNames;
            rows = {'<table><thead><tr>'};
            for j = 1:numel(vars), rows{end+1} = ['<th>' NMDataIOQCReportTools.esc(vars{j}) '</th>']; end %#ok<AGROW>
            rows{end+1} = '</tr></thead><tbody>';
            for i = 1:height(T)
                rows{end+1} = '<tr>'; %#ok<AGROW>
                for j = 1:numel(vars)
                    v = T{i,j};
                    if iscell(v), v = v{1}; end
                    if isnumeric(v) || islogical(v)
                        if isscalar(v), s = num2str(v); else, s = mat2str(v); end
                    else
                        s = char(string(v));
                    end
                    rows{end+1} = ['<td>' NMDataIOQCReportTools.esc(s) '</td>']; %#ok<AGROW>
                end
                rows{end+1} = '</tr>'; %#ok<AGROW>
            end
            rows{end+1} = '</tbody></table>';
            html = strjoin(rows, '');
        end

        function item = pathListItem(label, path)
            if isempty(path), item = ''; return; end
            item = ['<li><b>' NMDataIOQCReportTools.esc(label) ':</b> <code>' NMDataIOQCReportTools.esc(path) '</code></li>'];
        end

        function [pdfFile, messages] = tryWritePDF(htmlFile, bundleDir)
            messages = NMDataIOMessageTools.emptyMessages();
            pdfFile = fullfile(bundleDir, 'report.pdf');
            exe = NMDataIOQCReportTools.findChromiumExecutable();
            if isempty(exe)
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'qcReport.pdf.noBackend', 'Automatic PDF export was skipped because NM2 could not find a supported Chrome, Chromium, or Edge installation. Open report.html and use the browser''s Print / Save as PDF command.', 2, 'orange')];
                pdfFile = '';
                return;
            end
            cmd = sprintf('"%s" --headless --disable-gpu --print-to-pdf="%s" "file:///%s"', exe, pdfFile, strrep(htmlFile, '\\', '/'));
            [status, txt] = system(cmd);
            if status == 0 && exist(pdfFile,'file') == 2
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'qcReport.pdf', sprintf('PDF report written: %s', pdfFile), 0, 'green*')];
            else
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'qcReport.pdf.failed', sprintf('Automatic PDF export failed using %s: %s', exe, strtrim(txt)), 2, 'orange')];
                pdfFile = '';
            end
        end

        function exe = findChromiumExecutable()
            candidates = {};
            if ispc
                candidates = {fullfile(getenv('ProgramFiles'),'Microsoft','Edge','Application','msedge.exe'), fullfile(getenv('ProgramFiles(x86)'),'Microsoft','Edge','Application','msedge.exe'), fullfile(getenv('ProgramFiles'),'Google','Chrome','Application','chrome.exe'), fullfile(getenv('ProgramFiles(x86)'),'Google','Chrome','Application','chrome.exe')};
            elseif ismac
                candidates = {'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome','/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge'};
            else
                names = {'chromium-browser','chromium','google-chrome','microsoft-edge','msedge'};
                for i = 1:numel(names)
                    [st,out] = system(['command -v ' names{i}]);
                    if st == 0 && ~isempty(strtrim(out)), candidates{end+1} = strtrim(out); end %#ok<AGROW>
                end
            end
            exe = '';
            for i = 1:numel(candidates)
                if exist(candidates{i},'file') == 2
                    exe = candidates{i}; return;
                end
            end
        end

        function [ok, msg] = tryOpenHTML(htmlFile)
            ok = false; msg = '';
            try
                web(htmlFile, '-browser');
                ok = true;
            catch ME
                msg = sprintf('Could not open report.html automatically: %s: %s', ME.identifier, ME.message);
            end
        end

        function ensureDir(d)
            if exist(d,'dir') == 7, return; end
            [ok,msg] = mkdir(d);
            if ~ok, error('NMDataIOQCReportTools:MkdirFailed', 'Could not create directory %s: %s', d, msg); end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the QC-report text-writer entry point.
            %
            %   NMDataIOQCReportTools.writeTextFile(path,txt) delegates HTML/QC-report text output to
            %   NMSerializationTools while keeping the historical QC-report error identifier and message.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMDataIOQCReportTools:WriteFailed', 'Could not write text file: %s', 'fwrite-input-char');
        end
        function v = col(s, field, n)
            v = nan(n,1);
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                x = s.(field);
                if isstruct(x) && isscalar(x) && isfield(x,'x_nmref') && isequal(logical(x.x_nmref), true)
                    return;
                end
                if iscell(x)
                    y = nan(numel(x),1);
                    for ii = 1:numel(x)
                        xi = x{ii};
                        if islogical(xi), xi = double(xi); end
                        if isnumeric(xi) && isscalar(xi)
                            y(ii) = double(xi);
                        else
                            yi = str2double(char(string(xi)));
                            if isfinite(yi), y(ii) = yi; end
                        end
                    end
                    x = y;
                end
                if islogical(x), x = double(x); end
                if isnumeric(x)
                    x = double(x(:));
                    m = min(n, numel(x));
                    v(1:m) = x(1:m);
                end
            end
        end

        function c = asCellstr(v, prefix, n)
            if nargin < 2, prefix = 'X'; end
            if nargin < 3, n = 0; end
            if isempty(v), c = {}; else
                if iscell(v), c = v(:); elseif isstring(v), c = cellstr(v(:)); elseif ischar(v), c = cellstr(v); else, c = cellstr(string(v(:))); end
                c = cellfun(@(x) char(string(x)), c, 'UniformOutput', false);
            end
            if n > 0
                if numel(c) < n
                    for i = (numel(c)+1):n, c{i,1} = sprintf('%s%g', prefix, i); end
                elseif numel(c) > n
                    c = c(1:n);
                end
            end
        end

        function txt = asChar(v)
            if isempty(v), txt = ''; return; end
            if ischar(v), txt = strtrim(v); return; end
            if isstring(v), txt = strtrim(char(v)); return; end
            if isnumeric(v) || islogical(v), txt = strtrim(num2str(v)); return; end
            txt = strtrim(char(string(v)));
        end

        function v = fieldOr(s, field, default)
            v = default;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field)), v = s.(field); end
        end

        function v = optionNumber(s, field, default)
            v = default;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                x = double(s.(field));
                if ~isempty(x) && isfinite(x(1)), v = x(1); end
            end
        end

        function tf = optionBool(s, field, default)
            tf = default;
            if isstruct(s) && isfield(s, field) && ~isempty(s.(field))
                x = s.(field);
                if islogical(x), tf = logical(x); return; end
                if isnumeric(x), tf = x ~= 0; return; end
                tf = any(strcmpi(char(string(x)), {'1','true','yes','on'}));
            end
        end

        function s = esc(txt)
            s = char(string(txt));
            s = strrep(s,'&','&amp;'); s = strrep(s,'<','&lt;'); s = strrep(s,'>','&gt;');
            s = strrep(s,'"','&quot;'); s = strrep(s,'''','&#39;');
        end

        function css = reportCSS()
            css = ['body{font-family:Arial,Helvetica,sans-serif;margin:28px;color:#1f2933;background:#fff;}' ...
                'h1,h2,h3{color:#102a43;} table{border-collapse:collapse;width:100%;margin:12px 0;font-size:13px;}' ...
                'th,td{border:1px solid #d9e2ec;padding:5px 7px;text-align:left;vertical-align:top;} th{background:#f0f4f8;}' ...
                '.muted{color:#627d98}.note{background:#f0f4f8;border-left:4px solid #627d98;padding:8px 10px;}' ...
                'code{background:#f0f4f8;padding:1px 3px;} figure{margin:16px 0;} img{max-width:900px;width:100%;border:1px solid #d9e2ec;}.qcHistogram{max-width:100%;border:1px solid #d9e2ec;border-radius:8px;background:#fff;}' ...
                '.printBtn{float:right;padding:8px 12px;} @media print{.printBtn{display:none;} body{margin:12mm;} img{max-width:100%;}}'];
        end

        function lbl = metricLabel(key)
            switch char(key)
                case 'feature_outlier_rate', lbl = 'group outlier-rate';
                case 'feature_missing_rate', lbl = 'group missing-rate';
                case 'feature_zero_rate', lbl = 'group zero-rate';
                case 'feature_std', lbl = 'group standard deviation';
                case 'feature_mean', lbl = 'group mean';
                otherwise, lbl = char(key);
            end
        end

        function tag = zTag(z)
            tag = strrep(sprintf('%.3g', double(z)), '.', 'p');
            tag = strrep(tag, '-', 'm');
        end
    end
end
