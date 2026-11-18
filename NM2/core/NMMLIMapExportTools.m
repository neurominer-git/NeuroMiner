classdef NMMLIMapExportTools
% NMMLIMapExportTools
% -------------------------------------------------------------------------
% Optional, provenance-aware export of subject-level model-interpretation
% relevance maps after the authoritative MLI result has been computed and
% persisted in NM.analysis{a}.MLI or NM.analysis{a}.OOCV{o}.MLI.
%
% Purpose
%   Materialize spatial MLI relevance vectors to disk without making the MLI
%   computation itself depend on a particular imaging/surface file format.
%
% Syntax
%   report = NMMLIMapExportTools.exportRelevanceMaps(NM,analysisIndex,spec)
%
% Inputs
%   NM            Active NeuroMiner state containing DataIO provenance and
%                 persisted MLI results.
%   analysisIndex Scalar analysis index.
%   spec          Normalized MLI runner spec. Relevant fields are:
%                   exportRelevanceMaps   logical
%                   surfaceExportFormat   source|gii|mgh|mgz
%                   relevanceMapOutputDir optional explicit directory
%                   GridAct               selected CV2 cells
%                   selectSamples         all|selected
%                   sampleIDs             selected case IDs
%
% Outputs
%   report        Fixed export report containing written files, skipped
%                 non-spatial contexts and per-file export errors.
%
% Authority and flow
%   The selected CV or OOCV persisted MLI branch owns relevance. Its method in the
%   trained analysis determines the exported quantity: ShapleyValues for
%   Shapley, Y_mapped otherwise. DataIO datadescriptors determine whether the
%   selected feature block is voxel or native surface material and determine
%   the surface source format. Export never re-runs MLI, preprocessing, atlas
%   discovery or feature-space inference.
%
% Scientific/state contract
%   Only native voxel and native vertex feature spaces are exported here. ROI
%   and tabular MLI remain stored as feature vectors and are skipped rather
%   than being silently expanded to another scientific representation. Voxel
%   reconstruction follows the authoritative mask/badcoords selection.
%   Surface export preserves the existing vertex order exactly.
%
% Invariants
%   - Export is an optional side effect after MLI result persistence.
%   - Subject identity comes from the selected CV/OOCV canonical case axis.
%   - CV2 bounds discovery rows; OOCV selects cases on its immutable axis.
%   - Shapley export uses ShapleyValues; all other methods use Y_mapped.
%   - Source-format mode is deterministic from DataIO provenance; mixed
%     surface formats require an explicit output format.
%
% Materialization and performance
%   Time is O(E*F), where E is the number of exported subject/context maps and
%   F is the corresponding feature count. Exactly one relevance row and one
%   output map are materialized at a time. The exporter never concatenates the
%   subject-by-feature MLI matrix or loads subject source maps.
%
% Failure semantics
%   Per-map failures are recorded in report.errors and do not invalidate the
%   already-completed MLI computation. Unsupported/missing writer dependencies
%   are explicit. No MAT fallback or format substitution is performed.
%
% Side effects
%   Creates relevance-map directories and writes NIfTI/GIFTI/MGH/MGZ files.
%
% Consumers and dependencies
%   NMRunTools.interpretModels is the runner owner. Voxel export uses
%   NMResultsViewerImagingDescriptorAdapter + nk_WriteVol. Surface export uses
%   NMDataIOSurfaceTools.writeSurfaceScalar.
% -------------------------------------------------------------------------

    methods (Static)
        function report = exportRelevanceMaps(NM, analysisIndex, spec)
            report = NMMLIMapExportTools.reportTemplate();
            report.analysisIndex = double(analysisIndex);
            if nargin < 3 || ~isstruct(spec), spec = struct(); end
            if ~NMMLIMapExportTools.logicalField(spec,'exportRelevanceMaps',false)
                report.ok = true;
                report.message = 'Relevance-map export was not requested.';
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || ...
                    analysisIndex < 1 || analysisIndex > numel(NM.analysis) || ...
                    ~isstruct(NM.analysis{analysisIndex})
                report.message = 'The selected analysis is unavailable for relevance-map export.';
                report.errors = {report.message};
                return;
            end
            A = NM.analysis{analysisIndex};
            oocvIndex = 0;
            if NM.defs.analyses_locked
                oocvIndex = spec.oocvIndex;
                MLI = A.OOCV{oocvIndex}.MLI;
                cases = NM.OOCV{oocvIndex}.cases(:);
            else
                MLI = A.MLI;
                cases = NM.cases(:);
            end
            if isempty(MLI.Label)
                report.message = 'The selected analysis has no persisted MLI result to export.';
                report.errors = {report.message};
                return;
            end
            subjectRows = NMMLIMapExportTools.exportSubjectRows(NM,A,spec,cases);
            if isempty(subjectRows)
                report.ok = true;
                report.message = 'No subject rows are selected for relevance-map export.';
                return;
            end

            method = NMMLIMapExportTools.methodForAnalysis(A);
            if strcmp(method,'shapley'), relevanceField = 'ShapleyValues'; else, relevanceField = 'Y_mapped'; end
            report.method = method;
            report.relevanceField = relevanceField;
            fusionMode = NMMLIMapExportTools.fusionMode(A);
            isRegression = NMMLIMapExportTools.isRegression(NM,A);
            targetCount = size(MLI.Label,2);
            if targetCount < 1, targetCount = 1; end

            for targetIndex = 1:targetCount
                if strcmp(fusionMode,'late')
                    rowCount = max(1,size(MLI.Label,1));
                    for labelRow = 1:rowCount
                        L = NMMLIMapExportTools.labelEntry(MLI,targetIndex,labelRow);
                        report = NMMLIMapExportTools.exportLabelBranch(report,NM,A,L,isRegression, ...
                            analysisIndex,targetIndex,labelRow,relevanceField,method,cases,subjectRows,spec,oocvIndex);
                    end
                else
                    L = NMMLIMapExportTools.labelEntry(MLI,targetIndex,1);
                    report = NMMLIMapExportTools.exportLabelBranch(report,NM,A,L,isRegression, ...
                        analysisIndex,targetIndex,1,relevanceField,method,cases,subjectRows,spec,oocvIndex);
                end
            end

            report.nFiles = numel(report.files);
            report.nErrors = numel(report.errors);
            report.nSkipped = numel(report.skipped);
            report.ok = report.nErrors == 0;
            if report.ok
                report.message = sprintf('Wrote %d subject relevance map(s).',report.nFiles);
            else
                report.message = sprintf('MLI completed, but relevance-map export wrote %d file(s) with %d error(s).', ...
                    report.nFiles,report.nErrors);
            end
        end
    end

    methods (Static, Access = private)
        function report = exportLabelBranch(report,NM,A,L,isRegression,analysisIndex,targetIndex,labelRow,relevanceField,method,cases,subjectRows,spec,oocvIndex)
            if isRegression
                if ~isfield(L,'RegrResults') || isempty(L.RegrResults)
                    report.errors{end+1} = sprintf('Target %d has no RegrResults MLI branch.',targetIndex); %#ok<AGROW>
                    return;
                end
                branches = {L.RegrResults(1)};
                classifierIndices = 0;
            else
                if ~isfield(L,'BinResults') || isempty(L.BinResults)
                    report.errors{end+1} = sprintf('Target %d has no BinResults MLI branch.',targetIndex); %#ok<AGROW>
                    return;
                end
                branches = arrayfun(@(x)x,L.BinResults,'UniformOutput',false);
                classifierIndices = 1:numel(branches);
            end
            for bi = 1:numel(branches)
                branch = branches{bi};
                classifierIndex = classifierIndices(bi);
                if ~isfield(branch,'Modality') || isempty(branch.Modality)
                    report.errors{end+1} = sprintf('Target %d classifier %d has no MLI modality result.',targetIndex,classifierIndex); %#ok<AGROW>
                    continue;
                end
                if strcmp(NMMLIMapExportTools.fusionMode(A),'late')
                    modalityIndices = 1;
                else
                    modalityIndices = 1:numel(branch.Modality);
                end
                for mi = modalityIndices
                    entry = branch.Modality(mi);
                    if ~isfield(entry,'modality_num') || isempty(entry.modality_num)
                        report.errors{end+1} = sprintf('Target %d classifier %d modality %d has no modality_num identity.',targetIndex,classifierIndex,mi); %#ok<AGROW>
                        continue;
                    end
                    varind = round(double(entry.modality_num(1)));
                    if strcmp(method,'shapley')
                        values = entry.ShapleyValues;
                    else
                        values = entry.Y_mapped;
                    end
                    if isempty(values)
                        report.errors{end+1} = sprintf('Target %d classifier %d modality %d has no %s matrix.',targetIndex,classifierIndex,varind,relevanceField); %#ok<AGROW>
                        continue;
                    end
                    if size(values,1) ~= numel(cases)
                        report.errors{end+1} = sprintf(['Stored %s matrix for modality %d contains %d subject row(s), ' ...
                            'but the selected case axis contains %d.'],relevanceField,varind,size(values,1),numel(cases)); %#ok<AGROW>
                        continue;
                    end
                    descriptor = NMResultsViewerImagingDescriptorAdapter.resolve(NM,varind,struct());
                    if ~descriptor.ok
                        report.errors{end+1} = sprintf('Modality %d DataIO provenance is unavailable: %s',varind,descriptor.message); %#ok<AGROW>
                        continue;
                    end
                    if ~any(strcmp(descriptor.featureKind,{'voxel','surface_vertex'}))
                        report.skipped{end+1} = sprintf('Skipped modality %d (%s): relevance-map export supports native voxel/vertex feature spaces only.', ...
                            varind,descriptor.featureKind); %#ok<AGROW>
                        continue;
                    end
                    outDir = NMMLIMapExportTools.outputDirectory(A,spec,labelRow,oocvIndex);
                    if exist(outDir,'dir') ~= 7, mkdir(outDir); end
                    for rr = reshape(subjectRows,1,[])
                        row = double(values(rr,:));
                        if ~any(isfinite(row))
                            report.skipped{end+1} = sprintf('Skipped %s: selected MLI row contains no finite relevance value.',cases{rr}); %#ok<AGROW>
                            continue;
                        end
                        try
                            [outFile,format] = NMMLIMapExportTools.writeOneMap(NM,A,descriptor,row,outDir,cases{rr}, ...
                                varind,targetIndex,classifierIndex,method,spec);
                            rec = struct('file',outFile,'format',format,'caseId',cases{rr},'subjectIndex',double(rr), ...
                                'targetIndex',double(targetIndex),'classifierIndex',double(classifierIndex), ...
                                'varind',double(varind),'method',method,'relevanceField',relevanceField);
                            report.files(end+1) = rec; %#ok<AGROW>
                        catch ME
                            report.errors{end+1} = sprintf('Could not export case %s / modality %d / target %d / classifier %d: %s: %s', ...
                                cases{rr},varind,targetIndex,classifierIndex,ME.identifier,ME.message); %#ok<AGROW>
                        end
                    end
                end
            end
        end

        function [outFile,format] = writeOneMap(NM,A,descriptor,row,outDir,caseId,varind,targetIndex,classifierIndex,method,spec)
            base = NMMLIMapExportTools.fileBase(A,caseId,varind,targetIndex,classifierIndex,method);
            switch descriptor.featureKind
                case 'voxel'
                    if isempty(descriptor.featureSpaceFile) || exist(descriptor.featureSpaceFile,'file') ~= 2
                        error('NMMLIMapExportTools:VoxelFeatureSpaceFileUnavailable', ...
                            ['Voxel relevance-map export requires the file-backed authoritative feature-space image. ' ...
                             'The Results Viewer may use embedded metadata, but disk export must not invoke an interactive mask selector.']);
                    end
                    sel = descriptor.maskSelection;
                    outBase = fullfile(outDir,base);
                    nk_WriteVol(row,outBase,1,descriptor.featureSpaceFile,descriptor.badcoords, ...
                        sel.threshold,sel.operator,[],sel.roundBeforeComparison,false);
                    outFile = [outBase '.nii'];
                    format = 'nii';
                case 'surface_vertex'
                    format = NMMLIMapExportTools.surfaceFormat(NM,varind,spec);
                    switch format
                        case 'gii', ext = '.func.gii';
                        case 'mgh', ext = '.mgh';
                        case 'mgz', ext = '.mgz';
                        otherwise, error('NMMLIMapExportTools:UnsupportedSurfaceFormat','Unsupported surface output format: %s',format);
                    end
                    outFile = fullfile(outDir,[base ext]);
                    NMDataIOSurfaceTools.writeSurfaceScalar(row,outFile,format);
                otherwise
                    error('NMMLIMapExportTools:UnsupportedFeatureKind','Unsupported export feature kind: %s',descriptor.featureKind);
            end
        end

        function format = surfaceFormat(NM,varind,spec)
            requested = lower(strtrim(char(string(NMMLIMapExportTools.fieldOr(spec,'surfaceExportFormat','source')))));
            allowed = {'source','gii','mgh','mgz'};
            if ~any(strcmp(requested,allowed))
                error('NMMLIMapExportTools:UnsupportedSurfaceFormat','surfaceExportFormat must be source, gii, mgh, or mgz.');
            end
            if ~strcmp(requested,'source'), format = requested; return; end
            files = {};
            if isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && varind <= numel(NM.datadescriptor) && isstruct(NM.datadescriptor{varind})
                dd = NM.datadescriptor{varind};
                if isfield(dd,'input_settings') && isstruct(dd.input_settings) && isfield(dd.input_settings,'imageFiles')
                    files = cellstr(string(dd.input_settings.imageFiles(:)));
                end
            end
            if isempty(files) && isfield(NM,'files') && iscell(NM.files) && varind <= numel(NM.files) && ~isempty(NM.files{varind})
                files = cellstr(string(NM.files{varind}(:)));
            end
            if isempty(files)
                error('NMMLIMapExportTools:SurfaceSourceFormatUnavailable', ...
                    'Source-format surface export requires persisted DataIO surface source files or an explicit GIFTI/MGH/MGZ override.');
            end
            formats = NMDataIOSurfaceTools.surfaceFormats(files);
            formats = unique(formats(:)','stable');
            supported = formats(ismember(formats,{'gii','mgh','mgz'}));
            if numel(supported) == 1 && numel(formats) == 1
                format = supported{1};
                return;
            end
            if isempty(supported)
                % FreeSurfer native morphometry sources have intentionally
                % unconstrained suffixes. MGH is the canonical writable
                % FreeSurfer scalar container for source-format export.
                format = 'mgh';
                return;
            end
            error('NMMLIMapExportTools:MixedSurfaceSourceFormats', ...
                'Surface source files contain mixed formats (%s). Select an explicit GIFTI, MGH, or MGZ export format.',strjoin(formats,', '));
        end

        function rows = exportSubjectRows(NM,A,spec,cases)
            nSubjects = numel(cases);
            rows = false(nSubjects,1);
            if NM.defs.analyses_locked
                rows(:) = true;
            end
            G = [];
            if isfield(spec,'GridAct') && ~isempty(spec.GridAct), G = logical(spec.GridAct); end
            if isempty(G) && isfield(A,'GDdims') && iscell(A.GDdims) && ~isempty(A.GDdims) && isfield(A.GDdims{1},'GridAct')
                G = logical(A.GDdims{1}.GridAct);
            end
            if ~NM.defs.analyses_locked
                T = A.params.cv.TestInd;
                if isempty(G), G = true(size(T)); end
                if ~isequal(size(G),size(T))
                    error('NMMLIMapExportTools:GridSizeMismatch','Selected GridAct does not match the analysis CV2 TestInd grid.');
                end
                for f = 1:size(T,1)
                    for d = 1:size(T,2)
                        if ~G(f,d), continue; end
                        idx = double(T{f,d}(:));
                        idx = idx(isfinite(idx) & idx >= 1 & idx <= nSubjects & idx == round(idx));
                        rows(idx) = true;
                    end
                end
            end
            if any(strcmpi(strtrim(char(string(NMMLIMapExportTools.fieldOr(spec,'selectSamples','all')))),{'selected','user','user-defined','user_defined'}))
                requested = cellstr(string(NMMLIMapExportTools.fieldOr(spec,'sampleIDs',{})));
                requested = requested(:);
                caseIDs = cases;
                selected = false(nSubjects,1);
                for i = 1:numel(requested)
                    hit = find(strcmp(requested{i},caseIDs));
                    if numel(hit) ~= 1
                        error('NMMLIMapExportTools:SampleIdNotUnique','Requested MLI sample ID "%s" does not resolve to exactly one row on the selected case axis.',requested{i});
                    end
                    selected(hit) = true;
                end
                rows = rows & selected;
            end
            rows = find(rows);
        end

        function outDir = outputDirectory(A,spec,labelRow,oocvIndex)
            if oocvIndex > 0
                outDir = NMMLIRuntimeTools.mliResultDir(A,oocvIndex);
                return;
            end
            explicit = strtrim(char(string(NMMLIMapExportTools.fieldOr(spec,'relevanceMapOutputDir',''))));
            if ~isempty(explicit)
                outDir = explicit;
                return;
            end
            root = '';
            if isfield(A,'MLI') && isstruct(A.MLI) && isfield(A.MLI,'RootPath') && ~isempty(A.MLI.RootPath)
                rp = A.MLI.RootPath;
                if iscell(rp)
                    ix = min(max(1,labelRow),numel(rp));
                    root = char(string(rp{ix}));
                else
                    root = char(string(rp));
                end
            end
            if isempty(root)
                root = NMMLIMapExportTools.analysisMLIRoot(A);
            end
            outDir = fullfile(root,'relevance_maps');
        end

        function root = analysisMLIRoot(A)
            if ~isfield(A,'rootdir') || isempty(A.rootdir)
                root = fullfile(pwd,'MLI');
                return;
            end
            prog = '';
            if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'SVM') && isstruct(A.params.TrainParam.SVM) && isfield(A.params.TrainParam.SVM,'prog')
                prog = char(string(A.params.TrainParam.SVM.prog));
            end
            if isempty(prog), root = fullfile(A.rootdir,'MLI'); else, root = fullfile(A.rootdir,prog,'MLI'); end
        end

        function base = fileBase(A,caseId,varind,targetIndex,classifierIndex,method)
            normCode = NMMLIMapExportTools.normalizationCode(A);
            safeCase = regexprep(char(string(caseId)),'[^A-Za-z0-9._-]+','_');
            safeMethod = regexprep(lower(char(string(method))),'[^A-Za-z0-9_-]+','_');
            base = sprintf('mli%s_%s_%s_var%d_t%d',normCode,safeMethod,safeCase,varind,targetIndex);
            if classifierIndex > 0, base = sprintf('%s_cl%d',base,classifierIndex); end
        end

        function code = normalizationCode(A)
            z = 1;
            if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'MLI') && isstruct(A.params.TrainParam.MLI) && isfield(A.params.TrainParam.MLI,'znormdata')
                z = round(double(A.params.TrainParam.MLI.znormdata(1)));
            end
            ids = {'R','MC','Z','S'};
            if z < 1 || z > numel(ids), z = 1; end
            code = ids{z};
        end

        function method = methodForAnalysis(A)
            method = '';
            if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'MLI') && isstruct(A.params.TrainParam.MLI) && isfield(A.params.TrainParam.MLI,'method')
                method = lower(strtrim(char(string(A.params.TrainParam.MLI.method))));
            end
            if isempty(method), method = 'posneg'; end
        end

        function mode = fusionMode(A)
            mode = 'none';
            if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'FUSION') && isstruct(A.params.TrainParam.FUSION) && isfield(A.params.TrainParam.FUSION,'flag') && ~isempty(A.params.TrainParam.FUSION.flag)
                switch round(double(A.params.TrainParam.FUSION.flag(1)))
                    case 1, mode = 'early';
                    case 2, mode = 'intermediate';
                    case 3, mode = 'late';
                end
            end
        end

        function tf = isRegression(NM,A)
            mode = '';
            if isfield(A,'params') && isstruct(A.params) && isfield(A.params,'label') && isstruct(A.params.label) && isfield(A.params.label,'modeflag')
                mode = char(string(A.params.label.modeflag));
            elseif isfield(NM,'modeflag')
                mode = char(string(NM.modeflag));
            end
            tf = contains(lower(mode),'regress');
        end

        function L = labelEntry(root,targetIndex,rowIndex)
            if size(root.Label,1) >= rowIndex && size(root.Label,2) >= targetIndex
                L = root.Label(rowIndex,targetIndex);
            elseif rowIndex == 1 && numel(root.Label) >= targetIndex
                L = root.Label(targetIndex);
            else
                error('NMMLIMapExportTools:InvalidLabelCoordinates','MLI has no Label(%d,%d).',rowIndex,targetIndex);
            end
        end

        function report = reportTemplate()
            fileTemplate = struct('file','','format','','caseId','','subjectIndex',NaN,'targetIndex',NaN, ...
                'classifierIndex',NaN,'varind',NaN,'method','','relevanceField','');
            report = struct('ok',false,'message','','analysisIndex',NaN,'method','','relevanceField','', ...
                'nFiles',0,'nErrors',0,'nSkipped',0,'files',repmat(fileTemplate,0,1),'errors',{{}},'skipped',{{}});
        end

        function v = fieldOr(s,name,default)
            v = default;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), v = s.(name); end
        end

        function tf = logicalField(s,name,default)
            v = NMMLIMapExportTools.fieldOr(s,name,default);
            tf = logical(v(1));
        end
    end
end
