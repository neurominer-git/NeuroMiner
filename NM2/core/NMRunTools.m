classdef NMRunTools
% NMRunTools
% -------------------------------------------------------------------------
% Expandable public runtime facade.  It currently wraps controlled
% preprocessing, ML training/optimization and OOCV application runners.  Future
% runners such as nk_VisModelsPrep and nk_MLIinterpreterPrep should be added
% as new public methods and registry entries without exposing legacy action
% codes or runtime inp structs to callers.
% -------------------------------------------------------------------------

    methods (Static)
        function runners = availableRunners()
            % availableRunners  List public runtime runners exposed by NMRunTools.
            %
            %   runners = NMRunTools.availableRunners() returns method names
            %   for supported controlled runtime calls. The list is read-only
            %   and currently includes preprocessing, training and OOCV application.

            runners = {'preprocessAnalysis','trainAnalysis','visualizeModels','interpretModels','exportModels','applyOOCV'};
        end

        function [NM, out] = preprocessAnalysis(NM, analind, spec)
            % preprocessAnalysis  Run NeuroMiner preprocessing for an analysis through the public API.
            %
            % [NM, out] = NMRunTools.preprocessAnalysis(NM, analind, spec)
            % prepares the legacy preprocessing runtime context and calls
            % nk_PreprocessPrep for the selected analysis. Use this API
            % instead of calling nk_PreprocessPrep directly from browser or
            % script-level code.
            %
            % spec is a scalar struct. Common fields are:
            % gridAction              Required. 'all' runs all CV2 grid
            % cells; alternatively pass an explicit
            % logical GridAct matrix.
            % overwrite               Logical overwrite flag for existing
            % PreprocData/parameter files.
            % savePreproc             Logical; save PreprocData files.
            % Default: true.
            % writeParameters         Logical; write preprocessing
            % parameter files. Default: false.
            % useExistingParameters   Logical; reuse existing parameter
            % files when available. Default: true.
            % hideGrid                Logical; suppress grid UI where
            % supported. Default: true.
            % devMode                 Optional scalar logical replacement
            % for the legacy global DEV flag.
            %
            % The method is intentionally a standalone preprocessing action.
            % It does not make Train ML consume the generated PreprocData
            % files; that artifact-aware handoff is staged separately.
            %
            % spec.GridAct: supplies the grid act value in the public API/import specification.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMRunTools.preprocessAnalysis');
            end
            NMRunTools.assertFunction('nk_PreprocessPrep');
            NMRunTools.assertAnalysisReady(NM, analind, false);
            spec = NMRunTools.normalizePreprocessSpec(NM, analind, spec);
            p = NMRunTools.preprocessP(NM, analind, spec);
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            [act, analdim, pOut, GridAct] = nk_PreprocessPrep(6, analind, spec.GridAct, p, 'NM API');
            pSummary = pOut;
            if isfield(pSummary,'NM'), pSummary = rmfield(pSummary,'NM'); end
            if isfield(pSummary,'CV'), pSummary = rmfield(pSummary,'CV'); end
            artifactState = [];
            if exist('NMRuntimeActionTools','class') == 8
                artifactState = NMRuntimeActionTools.artifactState(NM, struct('analysisIndex',analind));
            end
            out = struct('ok',true, ...
                'message',sprintf('Preprocessing runner completed for analysis %d.', analind), ...
                'runner','preprocessAnalysis', 'act',act, 'analdim',analdim, ...
                'analysisIndex',analind, 'GridAct',GridAct, 'p',pSummary, ...
                'artifactState',artifactState);
        end

        function [NM, out] = trainAnalysis(NM, analind, spec)
            % trainAnalysis  Run NeuroMiner training/optimization for an analysis through the public API.
            %
            % [NM, out] = NMRunTools.trainAnalysis(NM, analind, spec)
            % prepares the legacy training runtime context and calls the
            % NeuroMiner optimizer backend for the selected analysis. Use this
            % API instead of calling nk_MLOptimizerPrep directly.
            %
            % analind is the analysis index created by
            % NMAnalysisManagerTools.createAnalysis. Default: 1.
            %
            % spec is a scalar struct. Common fields are:
            % gridAction     Required. 'all' runs all CV2 grid cells;
            % alternatively pass a logical GridAct matrix.
            % operationMode  'scratch' (default), 'preproc', 'datamat' or
            % 'results' style runtime mode.
            % overwrite      Logical overwrite flag for legacy runtime.
            % update         Logical update flag. Default: true.
            % hideGrid       Logical; suppress grid UI where supported.
            % debugall       Logical debug flag.
            % debugopt       Logical optimizer debug flag.
            % devMode        Optional scalar logical replacement for the
            % legacy global DEV flag.
            %
            % out contains the runner name, legacy act/inp payloads,
            % analysis index, analysis status and a hasGDdims flag.
            %
            % Example:
            % [NM, out] = NMRunTools.trainAnalysis(NM, 1, ...
            % struct('gridAction','all','operationMode','scratch'));
            %
            % spec.cvDataMasterFile: supplies the cv data master file value in the public API/import specification.
            % spec.cvDataMatFiles: supplies the cv data mat files value in the public API/import specification.
            % spec.cvResultsMasterFile: supplies the cv results master file value in the public API/import specification.
            % spec.gdanalmat: supplies the gdanalmat value in the public API/import specification.
            % spec.gdmat: supplies the gdmat value in the public API/import specification.
            % spec.gridAction: selects the CV-grid action that the runtime/script generator should encode.
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.preprocDataFiles: supplies the preproc data files value in the public API/import specification.
            % spec.preprocMasterFile: supplies the preproc master file value in the public API/import specification.
            % spec.preprocmat: supplies the preprocmat value in the public API/import specification.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertScientificTrainingData(NM);
            NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMRunTools.trainAnalysis');
            end
            NMRunTools.assertFunction('nk_MLOptimizerPrep');
            NMRunTools.assertAnalysisReady(NM, analind, false);
            NM = NMRunTools.disableUnsupportedOptRegul(NM, analind);
            spec = NMRunTools.normalizeTrainSpec(NM, analind, spec);
            inp = NMRunTools.trainInp(NM, analind, spec);
            preprocMatReport = [];
            cvDataMatReport = [];
            cvResultsReport = [];
            if strcmpi(char(string(spec.operationMode)), 'preproc') || strcmpi(char(string(spec.operationMode)), 'preprocdata')
                preprocSpec = struct('gridAction',spec.gridAction, 'requireComplete',true);
                if isfield(spec,'preprocmat'), preprocSpec.preprocmat = spec.preprocmat; end
                if isfield(spec,'preprocMasterFile'), preprocSpec.preprocMasterFile = spec.preprocMasterFile; end
                if isfield(spec,'preprocDataFiles'), preprocSpec.preprocDataFiles = spec.preprocDataFiles; end
                [inp.preprocmat, preprocMatReport] = NMRunTools.resolvePreprocMat(NM, analind, preprocSpec);
            elseif strcmpi(char(string(spec.operationMode)), 'datamat') || strcmpi(char(string(spec.operationMode)), 'cvdatamat')
                cvDataSpec = struct('gridAction',spec.gridAction, 'requireComplete',true);
                if isfield(spec,'gdmat'), cvDataSpec.gdmat = spec.gdmat; end
                if isfield(spec,'cvDataMasterFile'), cvDataSpec.cvDataMasterFile = spec.cvDataMasterFile; end
                if isfield(spec,'cvDataMatFiles'), cvDataSpec.cvDataMatFiles = spec.cvDataMatFiles; end
                [inp.gdmat, cvDataMatReport] = NMRunTools.resolveCVDataMat(NM, analind, cvDataSpec);
            elseif strcmpi(char(string(spec.operationMode)), 'results') || strcmpi(char(string(spec.operationMode)), 'cvresults')
                cvResultsSpec = struct('requireComplete',true);
                if isfield(spec,'gdanalmat'), cvResultsSpec.gdanalmat = spec.gdanalmat; end
                if isfield(spec,'cvResultsMasterFile'), cvResultsSpec.cvResultsMasterFile = spec.cvResultsMasterFile; end
                [inp.gdanalmat, cvResultsReport] = NMRunTools.resolveCVResults(NM, analind, cvResultsSpec);
            end
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            [act, inp, NMo] = nk_MLOptimizerPrep(6, inp, 'NM API');
            if ~isempty(NMo), NM = NMo; end
            NM = NMRunTools.disableUnsupportedOptRegul(NM, analind);
            status = NMRunTools.analysisStatus(NM, analind);
            out = struct('ok',true, 'message',sprintf('Training runner completed for analysis %s.', mat2str(analind)), ...
                'runner','trainAnalysis', 'act',act, 'inp',inp, 'analysisIndex',analind, ...
                'analysisStatus',status, 'hasGDdims',NMRunTools.analysisHasField(NM, analind, 'GDdims'), ...
                'preprocMatReport',preprocMatReport, 'cvDataMatReport',cvDataMatReport, 'cvResultsReport',cvResultsReport);
        end



        function [preprocmat, report] = resolvePreprocMat(NM, analind, spec)
            % resolvePreprocMat  Build legacy preprocmat cells without opening file selectors.
            %
            % [preprocmat, report] = NMRunTools.resolvePreprocMat(NM, analind, spec)
            % reconstructs the preprocmat payload expected by
            % nk_MLOptimizerPrep when Train ML is entered from existing
            % PreprocData files (operationMode = 'preproc'). The resolver is
            % read-only, noninteractive, and does not call nk_GenPreprocMaster2
            % because that legacy generator may open an interactive file selector when no
            % master file is supplied.
            %
            % The returned preprocmat follows the legacy shape:
            % preprocmat{i}{perm,fold} = filepath
            % for non-concatenated streams and
            % preprocmat{1}{perm,fold} = char(filepath_mod1, filepath_mod2, ...)
            % for concatenated multi-modality streams.
            %
            % spec.gridAction: required and validated against the
            % analysis CV2 grid. Optional fields:
            % preprocMasterFile   readable PreprocMaster MAT file. If
            % supplied, featmat is loaded and
            % validated instead of scanning files.
            % preprocmat          caller-supplied preprocmat payload to
            % validate and return.
            % requireComplete     require all selected CV2 cells. Default true.
            %
            % spec.GridAct: supplies the grid act value in the public API/import specification.
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.preprocDataFiles: supplies the preproc data files value in the public API/import specification.
            % spec.preprocMasterFile: supplies the preproc master file value in the public API/import specification.
            % spec.preprocmat: supplies the preprocmat value in the public API/import specification.
            % spec.requireComplete: requires the artifact resolver to return a complete executable selection.
            %

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            NMRunTools.assertAnalysisReady(NM, analind, false);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                error('NMRunTools:missingGridAction', 'resolvePreprocMat requires spec.gridAction so CV2-cell completeness can be validated.');
            end
            spec.operationMode = NMRunTools.fieldOr(spec,'operationMode','preproc');
            spec.requireComplete = NMRunTools.fieldOr(spec,'requireComplete',true);
            spec = NMRunTools.normalizeTrainSpec(NM, analind, spec);
            inp = NMRunTools.trainInp(NM, analind, spec);
            dataId = NMRunTools.dataId(NM, NM.analysis{analind});
            rootdir = NMRunTools.analysisRootDir(NM.analysis{analind});
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                error('NMRunTools:badAnalysisRootDir', 'Analysis %d has no readable root directory for PreprocData resolution.', analind);
            end
            if isempty(dataId)
                error('NMRunTools:missingDataId', 'Analysis %d has no NM.id/data ID for PreprocData resolution.', analind);
            end
            if isfield(spec,'preprocmat') && ~isempty(spec.preprocmat)
                preprocmat = spec.preprocmat;
                source = 'caller-supplied preprocmat';
            elseif isfield(spec,'preprocDataFiles') && ~isempty(spec.preprocDataFiles)
                files = cellstr(spec.preprocDataFiles);
                [preprocmat, source] = NMRunTools.scanPreprocDataFiles(rootdir, dataId, inp, spec.GridAct, files);
            elseif isfield(spec,'preprocMasterFile') && ~isempty(spec.preprocMasterFile)
                mf = char(string(spec.preprocMasterFile));
                if exist(mf,'file') ~= 2
                    error('NMRunTools:missingPreprocMasterFile', 'Preproc master file is not readable: %s', mf);
                end
                S = load(mf,'featmat');
                if ~isfield(S,'featmat') || isempty(S.featmat)
                    error('NMRunTools:badPreprocMasterFile', 'Preproc master file does not contain a nonempty featmat variable: %s', mf);
                end
                preprocmat = S.featmat;
                source = mf;
            else
                [preprocmat, source] = NMRunTools.scanPreprocDataFiles(rootdir, dataId, inp, spec.GridAct);
            end
            report = NMRunTools.validatePreprocMatShape(preprocmat, inp, spec.GridAct, logical(spec.requireComplete), source);
        end

        function [gdmat, report] = resolveCVDataMat(NM, analind, spec)
            % resolveCVDataMat  Build legacy gdmat cells without opening UI selectors.
            %
            % [gdmat, report] = NMRunTools.resolveCVDataMat(NM, analind, spec)
            % reconstructs the gdmat payload expected by nk_MLOptimizerPrep
            % when Train ML is entered from existing CVdatamat files
            % (operationMode = 'datamat'). The resolver is read-only and
            % noninteractive; it does not call the legacy CVdata master generator because
            % that generator may enter an interactive selection path
            % when no master file is supplied.
            %
            % The returned gdmat follows the legacy CVdatamat master shape:
            % gdmat{i}{ofold,operm} = filepath
            % for non-concatenated streams and
            % gdmat{1}{ofold,operm} = char(filepath_mod1, filepath_mod2, ...)
            % for concatenated multi-modality streams.
            %
            % spec.gridAction: required and validated against the
            % analysis CV2 grid. Optional fields:
            % cvDataMasterFile   readable CVdataMaster MAT file. If
            % supplied, featmat is loaded and
            % validated instead of scanning files.
            % gdmat              caller-supplied gdmat payload to
            % validate and return.
            % requireComplete    require all selected CV2 cells. Default true.
            %
            % spec.cvDataMasterFile: supplies the cv data master file value in the public API/import specification.
            % spec.cvDataMatFiles: supplies the cv data mat files value in the public API/import specification.
            % spec.gdmat: supplies the gdmat value in the public API/import specification.
            % spec.GridAct: supplies the grid act value in the public API/import specification.
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.requireComplete: requires the artifact resolver to return a complete executable selection.
            %

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            NMRunTools.assertAnalysisReady(NM, analind, false);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                error('NMRunTools:missingGridAction', 'resolveCVDataMat requires spec.gridAction so CV2-cell completeness can be validated.');
            end
            spec.operationMode = NMRunTools.fieldOr(spec,'operationMode','datamat');
            spec.requireComplete = NMRunTools.fieldOr(spec,'requireComplete',true);
            spec = NMRunTools.normalizeTrainSpec(NM, analind, spec);
            inp = NMRunTools.trainInp(NM, analind, spec);
            dataId = NMRunTools.dataId(NM, NM.analysis{analind});
            rootdir = NMRunTools.analysisRootDir(NM.analysis{analind});
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                error('NMRunTools:badAnalysisRootDir', 'Analysis %d has no readable root directory for CVdatamat resolution.', analind);
            end
            if isempty(dataId)
                error('NMRunTools:missingDataId', 'Analysis %d has no NM.id/data ID for CVdatamat resolution.', analind);
            end
            if isfield(spec,'gdmat') && ~isempty(spec.gdmat)
                gdmat = spec.gdmat;
                source = 'caller-supplied gdmat';
            elseif isfield(spec,'cvDataMatFiles') && ~isempty(spec.cvDataMatFiles)
                files = cellstr(spec.cvDataMatFiles);
                [gdmat, source] = NMRunTools.scanCVDataMatFiles(rootdir, dataId, inp, spec.GridAct, files);
            elseif isfield(spec,'cvDataMasterFile') && ~isempty(spec.cvDataMasterFile)
                mf = char(string(spec.cvDataMasterFile));
                if exist(mf,'file') ~= 2
                    error('NMRunTools:missingCVDataMasterFile', 'CVdata master file is not readable: %s', mf);
                end
                S = load(mf,'featmat');
                if ~isfield(S,'featmat') || isempty(S.featmat)
                    error('NMRunTools:badCVDataMasterFile', 'CVdata master file does not contain a nonempty featmat variable: %s', mf);
                end
                gdmat = S.featmat;
                source = mf;
            else
                [gdmat, source] = NMRunTools.scanCVDataMatFiles(rootdir, dataId, inp, spec.GridAct);
            end
            report = NMRunTools.validateCVDataMatShape(gdmat, inp, spec.GridAct, logical(spec.requireComplete), source);
        end

        function [gdanalmat, report] = resolveCVResults(NM, analind, spec)
            % resolveCVResults  Build legacy gdanalmat cellstr without opening UI selectors.
            %
            % [gdanalmat, report] = NMRunTools.resolveCVResults(NM, analind, spec)
            % reconstructs the gdanalmat payload expected by nk_MLOptimizerPrep
            % when Train ML is entered from existing CVresults files
            % (operationMode = 'results'). The resolver is read-only and
            % noninteractive; it does not call the legacy CVresults master
            % generator because that generator may enter an interactive
            % selection path when no master file is supplied.
            %
            % The returned gdanalmat follows the legacy CVresults master shape:
            % gdanalmat{i} = filepath
            % where i indexes the fusion/result stream consumed in the
            % nk_MLOptimizerPrep fusion loop. Optional fields:
            % cvResultsMasterFile  readable CVresultsMaster MAT file. If
            % supplied, featmat is loaded and
            % validated instead of scanning files.
            % gdanalmat            caller-supplied gdanalmat payload to
            % validate and return.
            % requireComplete      require all expected streams. Default true.
            %
            % spec.cvResultsMasterFile: supplies the cv results master file value in the public API/import specification.
            % spec.gdanalmat: supplies the gdanalmat value in the public API/import specification.
            % spec.gridAction: selects the CV-grid action that the runtime/script generator should encode.
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.requireComplete: requires the artifact resolver to return a complete executable selection.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            NMRunTools.assertAnalysisReady(NM, analind, false);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                spec.gridAction = NM.analysis{analind}.GDdims{1}.GridAct;
            end
            spec.operationMode = NMRunTools.fieldOr(spec,'operationMode','results');
            spec.requireComplete = NMRunTools.fieldOr(spec,'requireComplete',true);
            spec = NMRunTools.normalizeTrainSpec(NM, analind, spec);
            inp = NMRunTools.trainInp(NM, analind, spec);
            dataId = NMRunTools.dataId(NM, NM.analysis{analind});
            rootdir = NMRunTools.analysisRootDir(NM.analysis{analind});
            if isempty(rootdir) || exist(rootdir,'dir') ~= 7
                error('NMRunTools:badAnalysisRootDir', 'Analysis %d has no readable root directory for CVresults resolution.', analind);
            end
            if isempty(dataId)
                error('NMRunTools:missingDataId', 'Analysis %d has no NM.id/data ID for CVresults resolution.', analind);
            end
            if isfield(spec,'gdanalmat') && ~isempty(spec.gdanalmat)
                gdanalmat = spec.gdanalmat;
                source = 'caller-supplied gdanalmat';
            elseif isfield(spec,'cvResultsMasterFile') && ~isempty(spec.cvResultsMasterFile)
                mf = char(string(spec.cvResultsMasterFile));
                if exist(mf,'file') ~= 2
                    error('NMRunTools:missingCVResultsMasterFile', 'CVresults master file is not readable: %s', mf);
                end
                S = load(mf,'featmat');
                if ~isfield(S,'featmat') || isempty(S.featmat)
                    error('NMRunTools:badCVResultsMasterFile', 'CVresults master file does not contain a nonempty featmat variable: %s', mf);
                end
                gdanalmat = S.featmat;
                source = mf;
            else
                [gdanalmat, source] = NMRunTools.scanCVResultsFiles(rootdir, dataId, inp);
            end
            report = NMRunTools.validateCVResultsShape(gdanalmat, inp, logical(spec.requireComplete), source);
        end


        function [vismat, report] = resolveVISDataMat(NM, analind, spec)
            % resolveVISDataMat  Build legacy VISdatamat cell payload without opening UI selectors.
            %
            % [vismat, report] = NMRunTools.resolveVISDataMat(NM, analind, spec)
            % reconstructs the vismat payload expected by nk_VisModelsPrep
            % when visualization is entered from existing VISdatamat files
            % (legacy lfl = 2).  The resolver is read-only and noninteractive;
            % browser pages may still provide a manual VISdatamat file picked
            % by MATLAB, but this method never opens a selector itself.
            %
            % Optional fields:
            % vismat              caller-supplied legacy vismat payload
            % visDataMasterFile   readable VISdataMaster MAT file containing featmat
            % or a legacy vismat variable
            % visDataFiles        one or more individual CV2-level VISdatamat files
            % gridAction          logical GridAct matrix or 'all'
            % requireComplete     require all selected CV2 cells. Default true.
            %
            % spec.gridAction: selects the CV-grid action that the runtime/script generator should encode.
            % spec.requireComplete: requires the artifact resolver to return a complete executable selection.
            % spec.visDataFile: supplies the vis data file value in the public API/import specification.
            % spec.visDataFiles: supplies the vis data files value in the public API/import specification.
            % spec.visDataMasterFile: supplies the vis data master file value in the public API/import specification.
            % spec.vismat: supplies the vismat value in the public API/import specification.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                if isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && ...
                        isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'all';
                end
            end
            spec.requireComplete = NMRunTools.fieldOr(spec,'requireComplete',true);
            G = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            source = '';
            if isfield(spec,'vismat') && ~isempty(spec.vismat)
                vismat = spec.vismat;
                source = 'caller-supplied vismat';
            elseif isfield(spec,'visDataMasterFile') && ~isempty(spec.visDataMasterFile)
                mf = char(string(spec.visDataMasterFile));
                if exist(mf,'file') ~= 2
                    error('NMRunTools:missingVISDataMasterFile', 'VISdatamat master file is not readable: %s', mf);
                end
                S = load(mf);
                if isfield(S,'featmat') && ~isempty(S.featmat)
                    vismat = S.featmat;
                elseif isfield(S,'vismat') && ~isempty(S.vismat)
                    vismat = S.vismat;
                else
                    error('NMRunTools:badVISDataMasterFile', 'VISdatamat master file does not contain featmat or vismat: %s', mf);
                end
                source = mf;
            else
                state = NMVisRuntimeTools.visArtifactSummary(NM, analind, struct(), struct('GridAct',G));
                files = {};
                if isstruct(state) && isfield(state,'files'), files = state.files; end
                if isfield(spec,'visDataFiles') && ~isempty(spec.visDataFiles)
                    files = cellstr(spec.visDataFiles);
                elseif isfield(spec,'visDataFile') && ~isempty(spec.visDataFile)
                    % Backward-compatible API alias for older browser states;
                    % the current explicit contract is visDataFiles for one or
                    % more individual CV2-level VISdatamats.
                    vf = char(string(spec.visDataFile));
                    if exist(vf,'file') ~= 2
                        error('NMRunTools:missingVISDataFile', 'VISdatamat file is not readable: %s', vf);
                    end
                    S = load(vf);
                    if isfield(S,'featmat') && ~isempty(S.featmat)
                        vismat = S.featmat;
                        source = vf;
                        report = NMRunTools.validateVISDataMatShape(vismat, G, logical(spec.requireComplete), source);
                        return;
                    elseif isfield(S,'vismat') && ~isempty(S.vismat)
                        vismat = S.vismat;
                        source = vf;
                        report = NMRunTools.validateVISDataMatShape(vismat, G, logical(spec.requireComplete), source);
                        return;
                    end
                    files = {vf};
                end
                vismat = cell(size(G));
                selected = find(G(:));
                nAssign = min(numel(selected), numel(files));
                for ii = 1:nAssign
                    vismat{selected(ii)} = files{ii};
                end
                source = sprintf('%d scanned VISdatamat file(s)', numel(files));
            end
            report = NMRunTools.validateVISDataMatShape(vismat, G, logical(spec.requireComplete), source);
        end



        function [mlimat, report] = resolveMLIDataMat(NM, analind, spec)
            % Reconstruct CV2 MLIdatamat cells from the coordinates stored in each artifact.
            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                spec.gridAction = NM.analysis{analind}.GDdims{1}.GridAct;
            end
            spec.requireComplete = NMRunTools.fieldOr(spec,'requireComplete',false);
            G = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            options = NMMLIRuntimeTools.defaultOptions();
            oocvDir = '';
            if NM.defs.analyses_locked
                options.oocvIndex = spec.oocvIndex;
                oocvDir = NMMLIRuntimeTools.mliResultDir(NM.analysis{analind},spec.oocvIndex);
            end
            mlimat = [];
            files = {};
            source = '';
            if isfield(spec,'mlimat') && ~isempty(spec.mlimat)
                mlimat = spec.mlimat;
                source = 'caller-supplied mlimat';
            elseif isfield(spec,'mliDataMasterFile') && ~isempty(spec.mliDataMasterFile)
                source = spec.mliDataMasterFile;
                S = load(source,'featmat','datid');
                if ~strcmp(S.datid,NM.id)
                    error('NMRunTools:wrongMLIDataMasterId','MLIdatamat master does not match NM.id: %s',source);
                end
                mlimat = S.featmat;
                if ~isempty(oocvDir) && ~strcmpi(strrep(fileparts(source),'\','/'),strrep(oocvDir,'\','/'))
                    error('NMRunTools:wrongOOCVMaster','MLIdatamat master is outside the selected OOCV directory: %s',source);
                end
            else
                if isfield(spec,'mliDataFiles') && ~isempty(spec.mliDataFiles)
                    files = cellstr(spec.mliDataFiles);
                elseif isfield(spec,'mliDataFile') && ~isempty(spec.mliDataFile)
                    files = {spec.mliDataFile};
                else
                    state = NMMLIRuntimeTools.mliArtifactSummary(NM,analind,options,struct('GridAct',G));
                    files = state.files;
                end
            end
            id = NMMLIRuntimeTools.dataId(NM,NM.analysis{analind});
            if ~isempty(mlimat)
                NMRunTools.validateMLIDataMatShape(mlimat,G,false,source);
                mapped = NMRuntimeGridTools.fileGrid(mlimat(~cellfun(@isempty,mlimat)),G,id,oocvDir,'MLIdatamat');
                if ~isequal(mapped(G),mlimat(G))
                    error('NMRunTools:MLIPartitionMismatch','MLIdatamat entries do not match their stored CV2 coordinates.');
                end
                mlimat = mapped;  % Only selected CV2 cells enter interpretation.
            else
                mlimat = NMRuntimeGridTools.fileGrid(files,G,id,oocvDir,'MLIdatamat');
                source = sprintf('%d mapped MLIdatamat file(s)',numel(files));
            end
            report = NMRunTools.validateMLIDataMatShape(mlimat,G,logical(spec.requireComplete),source);
        end

        function [oocvmat, report] = resolveOOCVDataMat(NM, analind, oocvind, root, manual, options)
            % One CV2 path grid is reused across modality/target iterations.
            A = NM.analysis{analind};
            G = logical(A.GDdims{1}.GridAct);
            id = NMMLIRuntimeTools.dataId(NM,A);
            if ~manual.enabled || ~strcmp(options.operationMode,'precomputed')
                manual.oocvDataMasterFile = '';
            end
            files = manual.oocvDataFiles;
            if strcmp(options.operationMode,'precomputed') && ~isempty(manual.oocvDataMasterFile)
                S = load(manual.oocvDataMasterFile,'datid','featmat');
                if ~strcmp(S.datid,id), error('NMRunTools:wrongOOCVDataId','Wrong OOCV master ID: %s',manual.oocvDataMasterFile); end
                validateattributes(S.featmat,{'cell'},{'size',size(G)});
                files = S.featmat(~cellfun(@isempty,S.featmat));
            elseif ~manual.enabled || ~strcmp(options.operationMode,'precomputed')
                D = dir(fullfile(root,sprintf('*OOCVdatamat*_ID%s.mat',id)));
                D = D(~[D.isdir] & ~contains({D.name},'OOCVdatamatMaster'));
                files = fullfile({D.folder},{D.name});
            end
            nTarget = size(A.params.label.label,2);
            supported = (A.params.TrainParam.FUSION.flag ~= 3 || isscalar(A.params.TrainParam.FUSION.M)) && ...
                (A.params.label.altlabelflag || nTarget == 1);
            oocvmat = cell(size(G));
            report = struct('analysisIndex',analind,'oocvIndex',oocvind,'directory',root, ...
                'dataId',id,'masterFile',manual.oocvDataMasterFile,'availableGrid',false(size(G)), ...
                'precomputedSupported',supported,'permutationTest',logical(options.permutationTest), ...
                'nPerms',options.nPerms,'nExpected',nnz(G),'nAvailable',0,'nFiles',numel(files));
            if ~supported
                report.coverageText = sprintf('%d OOCVdatamat files found; multistream precomputed replay is not supported by the legacy single-grid input.',numel(files));
                return;
            end
            if ~strcmp(options.operationMode,'precomputed')
                [report.availableGrid,report.nAvailable] = NMRuntimeActionTools.cvCellCoverageMaskFromFiles( ...
                    files,'oocvDataMat',1,size(G));
                report.coverageText = sprintf('%d/%d trained CV2 cells have coordinate-matched OOCVdatamats (%d files); payloads unverified in scratch mode.', ...
                    nnz(G & report.availableGrid),report.nExpected,numel(files));
                return;
            end
            oocvmat = NMRuntimeGridTools.fileGrid(files,G,id,root,'OOCVdatamat');
            if ~isempty(manual.oocvDataMasterFile) && ~isequal(oocvmat(G),S.featmat(G))
                error('NMRunTools:OOCVMasterMismatch','OOCV master has mismatched CV2 coordinates: %s',manual.oocvDataMasterFile);
            end
            expected = {'binOOCVDh','cntOOCVDh','cntCV1OOCVdh','binOOCVWh'};
            if options.permutationTest, expected{end+1} = 'binOOCVDh_perm'; end
            if strcmp(A.params.TrainParam.SVM.prog,'SEQOPT') && strcmp(A.params.label.modeflag,'classification'), expected{end+1} = 'seqOOCVDh'; end
            nCases = numel(NM.OOCV{oocvind}.cases);
            for k = find(~cellfun(@isempty,oocvmat(:)))'
                file = oocvmat{k};
                P = load(file,expected{:});
                validateattributes(P.binOOCVDh,{'cell'},{'nonempty'});
                validateattributes(P.cntCV1OOCVdh,{'cell'},{'size',size(P.binOOCVDh)});
                validateattributes(P.binOOCVWh,{'cell'},{'size',size(P.binOOCVDh)});
                validateattributes(P.cntOOCVDh,{'numeric'},{'nonempty'});
                if any(strcmp(expected,'seqOOCVDh')), validateattributes(P.seqOOCVDh,{'cell'},{'size',size(P.binOOCVDh)}); end
                if options.permutationTest
                    validateattributes(P.binOOCVDh_perm,{'cell'},{'size',size(P.binOOCVDh)});
                end
                for h = 1:numel(P.binOOCVDh)
                    validateattributes(P.binOOCVDh{h},{'numeric'},{'nonempty','size',[nCases NaN]});
                    validateattributes(P.binOOCVWh{h},{'numeric'},{});
                    validateattributes(P.cntCV1OOCVdh{h},{'numeric'},{});
                    if options.permutationTest
                        validateattributes(P.binOOCVDh_perm{h},{'numeric'}, ...
                            {'size',[nCases,size(P.binOOCVDh{h},2),options.nPerms]});
                    end
                end
            end
            report.availableGrid = ~cellfun(@isempty,oocvmat);
            report.nAvailable = nnz(G & report.availableGrid);
            report.coverageText = sprintf('%d/%d trained CV2 cells have structurally validated OOCVdatamats (%d files).', ...
                report.nAvailable,report.nExpected,report.nFiles);
        end

        function [NM, out] = visualizeModels(NM, analind, spec)
            % visualizeModels  Run NeuroMiner model visualization through the public API.
            %
            % [NM, out] = NMRunTools.visualizeModels(NM, analind, spec)
            % prepares the legacy visualization runtime context and calls
            % nk_VisModelsPrep noninteractively. Browser and script callers
            % must use this public API instead of calling nk_VisModelsPrep.
            %
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.requestedOperationMode: records the user-requested runner mode before resolver fallback/normalization.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMRunTools.visualizeModels');
            end
            NMRunTools.assertFunction('nk_VisModelsPrep');
            if numel(analind) > 1
                results = cell(1,numel(analind));
                for ii = 1:numel(analind)
                    [NM, results{ii}] = NMRunTools.visualizeModels(NM, analind(ii), spec);
                end
                out = struct('ok',true, 'message',sprintf('Visualization completed for %d analysis/analyses.', numel(analind)), ...
                    'runner','visualizeModels', 'analysisIndex',analind(:)', 'results',{results});
                return;
            end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            spec = NMRunTools.normalizeVisualizeSpec(NM, analind, spec);
            [inp, resolveReport] = NMRunTools.visualizeInp(NM, analind, spec);
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            [NM, act, inpOut] = NMRunTools.callVisModelsPrep(inp);
            status = NMRunTools.analysisStatus(NM, analind);
            out = struct('ok',true, 'message',sprintf('Visualization runner completed for analysis %d.', analind), ...
                'runner','visualizeModels', 'act',act, 'inp',inpOut, 'analysisIndex',analind, ...
                'analysisStatus',status, 'hasVisdata',NMRunTools.analysisHasField(NM, analind, 'visdata'), ...
                'visDataMatReport',resolveReport, 'operationMode',spec.operationMode, ...
                'requestedOperationMode',NMRunTools.fieldOr(spec,'requestedOperationMode',spec.operationMode));
        end


        function [NM, out] = interpretModels(NM, analind, spec)
            % interpretModels  Run NeuroMiner ML interpretation through the public API.
            %
            % [NM, out] = NMRunTools.interpretModels(NM, analind, spec)
            % prepares the legacy ML-interpretation runtime context and calls
            % nk_MLInterpreterPrep noninteractively. Browser and script callers
            % must use this public API instead of calling nk_MLInterpreterPrep.
            %
            % spec.operationMode: selects the runner operation mode to materialize for script generation or execution.
            % spec.requestedOperationMode: records the user-requested runner mode before resolver fallback/normalization.
            % spec.exportRelevanceMaps: optional logical; after MLI is persisted, materialize native voxel/vertex relevance maps to disk. Default: false.
            % spec.surfaceExportFormat: source|gii|mgh|mgz for native vertex output. Default: source (follow DataIO provenance).
            % spec.relevanceMapOutputDir: optional explicit export directory; otherwise use the MLI result root/relevance_maps.
            %
            % Authority and flow:
            %   nk_MLInterpreterPrep owns MLI computation/persistence. Optional relevance-map export
            %   starts only after that call returns and reads NM.analysis{analind}.MLI through
            %   NMMLIMapExportTools; the legacy interpreter writer is suppressed on the NM2 path.
            % Scientific/state contract:
            %   Export never changes MLI selection/results. Shapley exports ShapleyValues; other
            %   methods export Y_mapped. DataIO provenance alone determines voxel versus vertex output.
            % Materialization/performance:
            %   MLI runtime cost is unchanged when exportRelevanceMaps=false. Requested export is
            %   O(E*F) for E subject/context maps and materializes one feature row at a time.
            % Failure semantics:
            %   MLI computation failures propagate normally. Post-run export failures are returned
            %   separately in relevanceMapExportReport and do not invalidate persisted MLI results.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            if NM.defs.analyses_locked
                NMStatusGuardTools.assertApplicationMode(NM, 'NMRunTools.interpretModels');
            else
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMRunTools.interpretModels');
            end
            NMRunTools.assertFunction('nk_MLInterpreterPrep');
            NMRunTools.assertFunction('nk_GetAnalModalInfo_config');
            if numel(analind) > 1
                results = cell(1,numel(analind));
                for ii = 1:numel(analind)
                    [NM, results{ii}] = NMRunTools.interpretModels(NM, analind(ii), spec);
                end
                out = struct('ok',true, 'message',sprintf('ML interpretation completed for %d analysis/analyses.', numel(analind)), ...
                    'runner','interpretModels', 'analysisIndex',analind(:)', 'results',{results});
                return;
            end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            spec = NMRunTools.normalizeMLISpec(NM, analind, spec);
            materialized = [];
            if NM.defs.analyses_locked
                validateattributes(spec.oocvIndex, {'numeric'}, {'scalar','integer','positive'});
                [readiness, materialized] = NMRunTools.oocvReadiness(NM, analind, spec.oocvIndex, true);
                if ~readiness.ready
                    error('NMRunTools:mliOOCVNotReady', 'OOCV dataset %d is not ready for MLI analysis %d: %s', spec.oocvIndex, analind, readiness.message);
                end
            end
            [inp, resolveReport] = NMRunTools.mliInp(NM, analind, spec);
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            if ~isempty(materialized)
                original = NM.OOCV{spec.oocvIndex};
                NM.OOCV{spec.oocvIndex} = materialized;
            end
            [act, NM, inpOut] = nk_MLInterpreterPrep(NM, 12, inp, 'NM API');
            if ~isempty(materialized)
                NM.OOCV{spec.oocvIndex} = original;
            end
            exportReport = struct('ok',true,'message','Relevance-map export was not requested.', ...
                'analysisIndex',analind,'nFiles',0,'nErrors',0,'nSkipped',0,'files',struct([]),'errors',{{}},'skipped',{{}});
            if logical(spec.exportRelevanceMaps)
                if exist('NMRuntimeProgressTools','class') == 8 || exist('NMRuntimeProgressTools','file') == 2
                    NMRuntimeProgressTools.writeGenericProgressSafe('Relevance-map export', ...
                        'Writing subject-level model-interpretation relevance maps.',97,'mli_relevance_map_export',true);
                end
                try
                    exportReport = NMMLIMapExportTools.exportRelevanceMaps(NM, analind, spec);
                catch ME
                    exportReport = struct('ok',false,'message',sprintf('MLI completed, but relevance-map export failed: %s: %s',ME.identifier,ME.message), ...
                        'analysisIndex',analind,'nFiles',0,'nErrors',1,'nSkipped',0,'files',struct([]),'errors',{{ME.message}},'skipped',{{}});
                end
                if exist('NMRuntimeProgressTools','class') == 8 || exist('NMRuntimeProgressTools','file') == 2
                    NMRuntimeProgressTools.writeGenericProgressSafe('Relevance-map export', ...
                        exportReport.message,99,'mli_relevance_map_export',false);
                end
            end
            status = NMRunTools.analysisStatus(NM, analind);
            message = sprintf('ML-interpretation runner completed for analysis %d.', analind);
            if logical(spec.exportRelevanceMaps)
                message = sprintf('%s %s',message,exportReport.message);
            end
            out = struct('ok',true, 'message',message, ...
                'runner','interpretModels', 'act',act, 'inp',inpOut, 'analysisIndex',analind, ...
                'analysisStatus',status, 'hasMLI',NMRunTools.analysisHasField(NM, analind, 'MLI'), ...
                'mliDataMatReport',resolveReport, 'relevanceMapExportReport',exportReport, ...
                'operationMode',spec.operationMode, ...
                'requestedOperationMode',NMRunTools.fieldOr(spec,'requestedOperationMode',spec.operationMode));
            if NM.defs.analyses_locked
                out.oocvIndex = spec.oocvIndex;
                out.hasMLI = ~isempty(NM.analysis{analind}.OOCV{spec.oocvIndex}.MLI);
            end
        end


        function [NM, out] = exportModels(NM, analind, spec)
            % exportModels  Export optimized NeuroMiner model/application artifacts through the public API.
            %
            % [NM, out] = NMRunTools.exportModels(NM, analind, spec)
            % prepares the legacy model-export runtime context and calls
            % cv_ExportModelsPrep noninteractively. Browser and script callers
            % must use this public API instead of calling cv_ExportModelsPrep.
            %
            % spec.exportOptModel: supplies the export opt model value in the public API/import specification.
            % spec.exportOptPreproc: supplies the export opt preproc value in the public API/import specification.

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingImportFinalized(NM, 'NMRunTools.exportModels');
            end
            NMRunTools.assertFunction('cv_ExportModelsPrep');
            NMRunTools.assertFunction('nk_GetAnalModalInfo_config');
            if numel(analind) > 1
                results = cell(1,numel(analind));
                for ii = 1:numel(analind)
                    [NM, results{ii}] = NMRunTools.exportModels(NM, analind(ii), spec);
                end
                NM = NMRunTools.updateExportState(NM, analind(:)', spec, results);
                out = struct('ok',true, 'message',sprintf('Model export completed for %d analysis/analyses.', numel(analind)), ...
                    'runner','exportModels', 'analysisIndex',analind(:)', 'results',{results}, ...
                    'exportState',NMRunTools.fieldOr(NM.defs,'export_state',struct()));
                return;
            end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            spec = NMRunTools.normalizeExportSpec(NM, analind, spec);
            inp = NMRunTools.exportInp(NM, analind, spec);
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            [act, NM, inpOut] = cv_ExportModelsPrep(NM, 10, inp, 'NM API');
            NM = NMRunTools.updateExportState(NM, analind, spec, {struct('ok',true)});
            status = NMRunTools.analysisStatus(NM, analind);
            out = struct('ok',true, 'message',sprintf('Model export completed for analysis %d.', analind), ...
                'runner','exportModels', 'act',act, 'inp',inpOut, 'analysisIndex',analind, ...
                'analysisStatus',status, 'operationMode','export', ...
                'exportOptModel',logical(spec.exportOptModel), 'exportOptPreproc',logical(spec.exportOptPreproc), ...
                'exportState',NMRunTools.fieldOr(NM.defs,'export_state',struct()));
        end

        function [out, materialized] = oocvReadiness(NM, analind, oocvind, inspectArchive)
            % oocvReadiness  Validate one trained-analysis/OOCV-dataset application pair.
            %
            % This is the public runtime projection of DataIO's OOCV readiness
            % authority. Required modality identity remains derived from the
            % selected trained analysis; dataset integrity remains validated by
            % NMDataIOOOCVReadinessTools. Optional materialized output is
            % execution-local; never include it in the readiness report.
            arguments
                NM
                analind = 1
                oocvind = 1
                inspectArchive = false
            end
            if isempty(analind), analind = 1; end
            if isempty(oocvind), oocvind = 1; end
            NMRunTools.assertAnalysisReady(NM, analind, true);
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || ...
                    oocvind < 1 || oocvind > numel(NM.OOCV) || isempty(NM.OOCV{oocvind})
                error('NMRunTools:badOOCVIndex', 'OOCV/application dataset %d does not exist.', oocvind);
            end
            if exist('NMOOCVApplicationPreprocTools','class') ~= 8 && exist('NMOOCVApplicationPreprocTools','file') ~= 2
                error('NMRunTools:oocvApplicationPreprocUnavailable', ...
                    'NMOOCVApplicationPreprocTools is not available on the MATLAB path.');
            end
            required = NMOOCVApplicationPreprocTools.requiredModalities(NM, analind);
            target = struct('scope','oocv','containerField','OOCV','containerIndex',oocvind,'varind',1);
            if exist('NMDataIOOOCVReadinessTools','class') ~= 8 && exist('NMDataIOOOCVReadinessTools','file') ~= 2
                error('NMRunTools:oocvReadinessUnavailable', 'NMDataIOOOCVReadinessTools is not available on the MATLAB path.');
            end
            [report, messages, resolvedY, materialized] = NMDataIOOOCVReadinessTools.validate(NM, target, required, inspectArchive);
            TP = NM.analysis{analind}.params.TrainParam;
            if TP.STACKING.flag == 1
                sources = TP.STACKING.sel_anal;
                missingSources = sources(~arrayfun(@(a)NMRunTools.analysisHasOOCVResult(NM,a,oocvind),sources));
                if ~isempty(missingSources)
                    names = arrayfun(@(a)NM.analysis{a}.id,missingSources,'UniformOutput',false);
                    messages = [NMDataIOMessageTools.make('danger',true,'OOCVStackingReadiness', ...
                        sprintf('Stacking requires OOCV predictions from %s. Apply these first-level analyses to OOCV dataset %d before applying the stacker.', ...
                        strjoin(names,', '),oocvind),1,'red*'); messages];
                    report.ready = false;
                end
            end
            ready = isstruct(report) && isfield(report,'ready') && logical(report.ready);
            if ~ready, materialized = []; end
            message = NMRunTools.reportMessage(report);
            if exist('NMDataIOMessageTools','class') == 8 || exist('NMDataIOMessageTools','file') == 2
                strip = NMDataIOMessageTools.highestPriorityStrip(messages, message);
                if isstruct(strip) && isfield(strip,'text') && ~isempty(strip.text), message = strip.text; end
            end
            applicationPreproc = [];
            structuralBlock = ~isempty(NMRunTools.fieldOr(report,'missingModalities',[])) || ...
                ~isempty(NMRunTools.fieldOr(report,'unresolvedExternalLinks',{})) || ...
                ~isempty(NMRunTools.fieldOr(report,'externalHashMismatches',{})) || ...
                isempty(NMRunTools.fieldOr(report,'nCases',[]));
            if ~structuralBlock && (~report.partlyCompatible || (inspectArchive && report.ready))
                if report.partlyCompatible
                    NM.OOCV{oocvind}.Y = resolvedY;
                end
                applicationPreproc = NMOOCVApplicationPreprocTools.assess(NM, analind, oocvind);
            end
            out = struct('ok',true,'ready',ready,'message',message,'analysisIndex',analind, ...
                'oocvIndex',oocvind,'requiredModalities',required,'report',report,'messages',{messages}, ...
                'labelsKnown',NMRunTools.fieldOr(report,'labelsKnown',[]), ...
                'nCases',NMRunTools.fieldOr(report,'nCases',[]), ...
                'applicationPreproc',applicationPreproc);
        end

        function [NM, out] = applyOOCV(NM, analind, oocvind, spec)
            % applyOOCV  Apply a trained NeuroMiner analysis to an imported OOCV/application dataset.
            %
            %   [NM, out] = NMRunTools.applyOOCV(NM, analind, oocvind, spec)
            %   validates OOCV readiness, binds the current OOCV container into
            %   the selected trained analysis runtime context, and calls the
            %   legacy OOCV backend. Use this API instead of calling nk_OOCVPrep
            %   directly.
            %
            %   analind is the trained analysis index. The analysis must contain
            %   GDdims/trained results. oocvind is the NM.OOCV container index.
            %   Defaults are 1 and 1.
            %
            %   spec is a scalar struct. Common fields are:
            %       gridAction       'analysis' (default) reuses the trained
            %                        analysis grid selection; 'all' or a logical
            %                        matrix can be supplied where appropriate.
            %       operationMode    'scratch' (default) or 'precomputed'.
            %       overwrite        Logical overwrite flag.
            %       saveparam        Logical legacy parameter-save flag.
            %       saveCV1          Logical CV1-save flag.
            %       loadparam        Logical legacy parameter-load flag.
            %       permutationTest  Logical; request OOCV permutation testing
            %                        where supported by the backend.
            %       nPerms           Number of permutations. Default: 1000.
            %       hideGrid         Logical; suppress grid UI where supported.
            %       devMode          Optional scalar logical DEV flag.
            %
            %   out.hasOOCVResults indicates whether the analysis now contains
            %   an OOCV result entry for the selected container.
            %
            %   Example:
            %       [NM, out] = NMRunTools.applyOOCV(NM, 1, 1, ...
            %           struct('gridAction','analysis','overwrite',true));

            if nargin < 2 || isempty(analind), analind = 1; end
            if nargin < 3 || isempty(oocvind), oocvind = 1; end
            if nargin < 4 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertApplicationMode(NM, 'NMRunTools.applyOOCV');
            end
            NMRunTools.assertFunction('nk_OOCVPrep');
            NMRunTools.assertAnalysisReady(NM, analind, true);
            spec = NMRunTools.normalizeOOCVSpec(NM, analind, oocvind, spec);
            [ready, materialized] = NMRunTools.oocvReadiness(NM, analind, oocvind, true);
            if ~logical(ready.ready)
                error('NMRunTools:oocvNotReady', 'OOCV dataset %d is not ready for analysis %d: %s', oocvind, analind, ready.message);
            end
            NM = NMRunTools.bindOOCVRuntimeContext(NM, analind, oocvind);
            inp = NMRunTools.oocvInp(NM, analind, oocvind, spec);
            inp = NMRunTools.attachOOCVApplicationPreproc( ...
                inp, NM, analind, oocvind, ready.applicationPreproc);
            NMRunTools.establishLegacyRuntimeContext(NM, spec);
            if ~isempty(materialized)
                original = NM.OOCV{oocvind};
                NM.OOCV{oocvind} = materialized;
            end
            [act, NM, inp] = nk_OOCVPrep(NM, 10, inp, 'NM API');
            if ~isempty(materialized)
                original.analysis_used = NM.OOCV{oocvind}.analysis_used;
                NM.OOCV{oocvind} = original;
            end
            status = NMRunTools.analysisStatus(NM, analind);
            out = struct('ok',true, 'message',sprintf('OOCV runner completed for analysis %d / OOCV %d.', analind, oocvind), ...
                'runner','applyOOCV', 'act',act, 'inp',inp, 'analysisIndex',analind, 'oocvIndex',oocvind, ...
                'analysisStatus',status, 'hasOOCVResults',NMRunTools.analysisHasOOCVResult(NM, analind, oocvind));
        end
    end

    methods (Static, Access = private)



        function spec = normalizeExportSpec(NM, analind, spec)
            if ~isstruct(spec), spec = struct(); end
            spec.exportOptModel = logical(NMRunTools.fieldOr(spec,'exportOptModel',true));
            spec.exportOptPreproc = logical(NMRunTools.fieldOr(spec,'exportOptPreproc',true));
            if ~spec.exportOptModel && ~spec.exportOptPreproc
                error('NMRunTools:noExportTarget', 'Select optimized ML models, optimized preprocessing parameters, or both before exporting.');
            end
            spec.overwrite = logical(NMRunTools.fieldOr(spec,'overwrite',false));
            spec.saveCV1 = logical(NMRunTools.fieldOr(spec,'saveCV1',false));
            spec.loadParameters = logical(NMRunTools.fieldOr(spec,'loadParameters',false));
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.hideGrid = logical(NMRunTools.fieldOr(spec,'hideGrid',false));
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                if isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if ischar(spec.gridAction) || isstring(spec.gridAction)
                if strcmpi(char(string(spec.gridAction)),'analysis') && isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.GridAct = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
                end
            else
                spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            end
            if ~any(spec.GridAct(:))
                error('NMRunTools:noExportCV2Partitions', 'Select at least one CV2 partition before exporting model artifacts.');
            end
        end

        function inp = exportInp(NMlocal, analind, spec)
            inp = struct('analind',analind, 'oocvind',1, 'lfl',1, ...
                'ovrwrt',NMRunTools.yesNoCode(spec.overwrite), ...
                'saveparam',NMRunTools.yesNoCode(spec.exportOptPreproc), ...
                'saveCV1',NMRunTools.yesNoCode(spec.saveCV1), ...
                'loadparam',NMRunTools.yesNoCode(spec.loadParameters), ...
                'HideGridAct',logical(spec.hideGrid), 'batchflag',1, ...
                'GridAct',logical(spec.GridAct), ...
                'exportOptModel',logical(spec.exportOptModel), ...
                'exportOptPreproc',logical(spec.exportOptPreproc), ...
                'overwriteExport',logical(spec.overwrite));
            if isfield(spec,'optpreprocmat'), inp.optpreprocmat = spec.optpreprocmat; end
            if isfield(spec,'optmodelmat'), inp.optmodelmat = spec.optmodelmat; end
            if isfield(NMlocal,'analysis') && iscell(NMlocal.analysis) && analind >= 1 && analind <= numel(NMlocal.analysis) && ...
                    isstruct(NMlocal.analysis{analind}) && isfield(NMlocal.analysis{analind},'id')
                inp.analysis_id = NMlocal.analysis{analind}.id;
            end
        end

        function NM = updateExportState(NM, analind, spec, results) %#ok<INUSD>
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            old = struct();
            if isfield(NM.defs,'export_state') && isstruct(NM.defs.export_state)
                old = NM.defs.export_state;
            end
            exportModel = logical(NMRunTools.fieldOr(spec,'exportOptModel',false));
            exportPreproc = logical(NMRunTools.fieldOr(spec,'exportOptPreproc',false));
            E = struct('models_exported',false, 'preproc_exported',false, ...
                'export_finished',false, 'timestamp','', 'analyses',[], ...
                'runner','NMRunTools.exportModels');
            if isfield(old,'models_exported'), E.models_exported = logical(old.models_exported); end
            if isfield(old,'preproc_exported'), E.preproc_exported = logical(old.preproc_exported); end
            if isfield(old,'analyses') && ~isempty(old.analyses), E.analyses = double(old.analyses(:)'); end
            if exportModel, E.models_exported = true; end
            if exportPreproc, E.preproc_exported = true; end
            E.analyses = unique([E.analyses double(analind(:)')]);
            E.export_finished = logical(E.models_exported) && logical(E.preproc_exported);
            E.timestamp = datestr(now, 30);
            NM.defs.export_state = E;
        end

        function spec = normalizeMLISpec(NM, analind, spec)
            if ~isstruct(spec), spec = struct(); end
            spec.operationMode = char(string(NMRunTools.fieldOr(spec,'operationMode','auto')));
            spec.requestedOperationMode = NMRunTools.fieldOr(spec,'requestedOperationMode',spec.operationMode);
            spec.overwrite = NMRunTools.fieldOr(spec,'overwrite',false);
            spec.overwritePermutations = NMRunTools.fieldOr(spec,'overwritePermutations',false);
            spec.recomputeEstimates = NMRunTools.fieldOr(spec,'recomputeEstimates',false);
            spec.saveParameters = NMRunTools.fieldOr(spec,'saveParameters',false);
            spec.loadParameters = NMRunTools.fieldOr(spec,'loadParameters',false);
            spec.saveCV1 = NMRunTools.fieldOr(spec,'saveCV1',false);
            spec.exportRelevanceMaps = logical(NMRunTools.fieldOr(spec,'exportRelevanceMaps',false));
            spec.surfaceExportFormat = lower(strtrim(char(string(NMRunTools.fieldOr(spec,'surfaceExportFormat','source')))));
            if ~any(strcmp(spec.surfaceExportFormat,{'source','gii','mgh','mgz'}))
                error('NMRunTools:badMLISurfaceExportFormat', ...
                    'surfaceExportFormat must be source, gii, mgh, or mgz.');
            end
            if isfield(spec,'relevanceMapOutputDir') && ~isempty(spec.relevanceMapOutputDir)
                spec.relevanceMapOutputDir = char(string(spec.relevanceMapOutputDir));
            end
            spec.selectSamples = char(string(NMRunTools.fieldOr(spec,'selectSamples','all')));
            spec.sampleIDs = NMRunTools.normalizeMLISampleIDs(NMRunTools.fieldOr(spec,'sampleIDs',{}));
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.hideGrid = logical(NMRunTools.fieldOr(spec,'hideGrid',false));
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                if isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if ischar(spec.gridAction) || isstring(spec.gridAction)
                if strcmpi(char(string(spec.gridAction)),'analysis') && isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.GridAct = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
                end
            else
                spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            end
        end

        function [inp, resolveReport] = mliInp(NMlocal, analind, spec)
            mode = lower(strtrim(char(string(spec.operationMode))));
            if NMlocal.defs.analyses_locked && strcmp(mode,'auto'), mode = 'scratch'; end
            resolveReport = [];
            if strcmp(mode,'auto')
                mliSpec = struct('gridAction',spec.GridAct,'requireComplete',false);
                if isfield(spec,'mliDataMasterFile'), mliSpec.mliDataMasterFile = spec.mliDataMasterFile; end
                if isfield(spec,'mliDataFiles'), mliSpec.mliDataFiles = spec.mliDataFiles; end
                try
                    [~, resolveReport] = NMRunTools.resolveMLIDataMat(NMlocal, analind, mliSpec);
                catch ME
                    resolveReport = struct('ok',false,'message',ME.message,'identifier',ME.identifier);
                end
                mode = 'scratch';
            elseif any(strcmp(mode,{'mlidatamat','mlidata','mli'}))
                mliSpec = struct('gridAction',spec.GridAct,'requireComplete',false);
                if isfield(spec,'mlimat'), mliSpec.mlimat = spec.mlimat; end
                if isfield(spec,'mliDataMasterFile'), mliSpec.mliDataMasterFile = spec.mliDataMasterFile; end
                if isfield(spec,'mliDataFiles'), mliSpec.mliDataFiles = spec.mliDataFiles; end
                if NMlocal.defs.analyses_locked
                    mliSpec.oocvIndex = spec.oocvIndex;
                end
                [spec.mlimat, resolveReport] = NMRunTools.resolveMLIDataMat(NMlocal, analind, mliSpec);
                if isstruct(resolveReport) && isfield(resolveReport,'nPresent') && resolveReport.nPresent < 1
                    error('NMRunTools:noMLIDataMatOverlap', 'No MLIdatamat overlap exists for the selected CV2 partitions.');
                end
                mode = 'mlidatamat';
            elseif ~strcmp(mode,'scratch')
                error('NMRunTools:badMLIMode', 'Unsupported ML-interpretation operationMode: %s', mode);
            end
            if logical(spec.loadParameters) && (~isfield(spec,'optpreprocmat') || isempty(spec.optpreprocmat) || ~isfield(spec,'optmodelmat') || isempty(spec.optmodelmat))
                error('NMRunTools:missingMLIParameterFiles', 'Loading saved preprocessing/model parameters requires optpreprocmat and optmodelmat payloads.');
            end
            selectSamples = 1;
            if any(strcmpi(strtrim(char(string(spec.selectSamples))), {'selected','user','user-defined','user_defined'}))
                selectSamples = 2;
                if isempty(spec.sampleIDs)
                    error('NMRunTools:missingMLISampleIDs', 'User-defined ML interpretation requires at least one sample ID.');
                end
            end
            oocvind = []; OO = [];
            if NMlocal.defs.analyses_locked
                oocvind = spec.oocvIndex;
                OO = NMlocal.OOCV{oocvind};
            end
            inp = struct('analind',analind, 'oocvflag',NMlocal.defs.analyses_locked, 'oocvind',oocvind, 'OO',OO, 'lfl',1, ...
                'ovrwrt',NMRunTools.yesNoCode(spec.overwrite), 'saveparam',NMRunTools.yesNoCode(spec.saveParameters), ...
                'ovrwrtperm',NMRunTools.yesNoCode(spec.overwritePermutations), ...
                'recompute_estimates',NMRunTools.yesNoCode(spec.recomputeEstimates), ...
                'saveCV1',NMRunTools.yesNoCode(spec.saveCV1), 'loadparam',NMRunTools.yesNoCode(spec.loadParameters), ...
                'selectsamples',selectSamples, 'sampleID',{{}}, ...
                'HideGridAct',logical(spec.hideGrid), 'batchflag',1, 'datatype','MLIdatamat');
            inp.sampleID = spec.sampleIDs;
            inp.GridAct = logical(spec.GridAct);
            % NM2 owns relevance-map export after persisted MLI aggregation.
            % Suppress the legacy in-interpreter writer so computation cannot
            % depend on a voxel/surface file-format implementation.
            inp.suppressLegacyMapExport = true;
            if strcmp(mode,'mlidatamat')
                inp.lfl = 2;
                inp.matfiles = spec.mlimat;
                if isstruct(resolveReport) && isfield(resolveReport,'presentMask') && isequal(size(resolveReport.presentMask), size(inp.GridAct))
                    inp.GridAct = logical(inp.GridAct) & logical(resolveReport.presentMask);
                end
            else
                inp.lfl = 1;
            end
            if isfield(spec,'optpreprocmat'), inp.optpreprocmat = spec.optpreprocmat; end
            if isfield(spec,'optmodelmat'), inp.optmodelmat = spec.optmodelmat; end
        end

        function ids = normalizeMLISampleIDs(x)
            if isempty(x), ids = {}; return; end
            if ischar(x) || isstring(x)
                parts = regexp(char(string(x)),'[,;\n\r]+','split');
                ids = strtrim(parts(:));
                ids = ids(~cellfun('isempty',ids));
            elseif iscell(x)
                ids = cellstr(x(:));
                ids = strtrim(ids);
                ids = ids(~cellfun('isempty',ids));
            else
                ids = {};
            end
        end


        function spec = normalizeVisualizeSpec(NM, analind, spec)
            if ~isstruct(spec), spec = struct(); end
            spec.operationMode = char(string(NMRunTools.fieldOr(spec,'operationMode','auto')));
            spec.requestedOperationMode = NMRunTools.fieldOr(spec,'requestedOperationMode',spec.operationMode);
            spec.overwrite = NMRunTools.fieldOr(spec,'overwrite',false);
            spec.operateAtCV1 = NMRunTools.fieldOr(spec,'operateAtCV1',false);
            spec.saveParameters = NMRunTools.fieldOr(spec,'saveParameters',false);
            spec.loadParameters = NMRunTools.fieldOr(spec,'loadParameters',false);
            spec.writeCV2Maps = NMRunTools.fieldOr(spec,'writeCV2Maps',false);
            spec.cvrNorm = char(string(NMRunTools.fieldOr(spec,'cvrNorm','sd')));
            spec.decompMode = NMRunTools.fieldOr(spec,'decompMode',false);
            spec.lowMemory = NMRunTools.fieldOr(spec,'lowMemory',true);
            spec.simCorrMethod = char(string(NMRunTools.fieldOr(spec,'simCorrMethod','spearman')));
            spec.simCorrThresh = double(NMRunTools.fieldOr(spec,'simCorrThresh',0.5));
            spec.corrCompCutoff = double(NMRunTools.fieldOr(spec,'corrCompCutoff',0.3));
            spec.selCompCutoff = double(NMRunTools.fieldOr(spec,'selCompCutoff',0.1));
            spec.pruneMode = char(string(NMRunTools.fieldOr(spec,'pruneMode','fraction')));
            spec.pruneFraction = double(NMRunTools.fieldOr(spec,'pruneFraction',0.30));
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.hideGrid = logical(NMRunTools.fieldOr(spec,'hideGrid',false));
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                if isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.gridAction = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.gridAction = 'analysis';
                end
            end
            if ischar(spec.gridAction) || isstring(spec.gridAction)
                if strcmpi(char(string(spec.gridAction)),'analysis') && isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                    spec.GridAct = logical(NM.analysis{analind}.GDdims{1}.GridAct);
                else
                    spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
                end
            else
                spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            end
        end

        function [inp, resolveReport] = visualizeInp(NMlocal, analind, spec)
            mode = lower(strtrim(char(string(spec.operationMode))));
            resolveReport = [];
            if strcmp(mode,'auto')
                % NM-Modular Auto intentionally maps to the legacy scratch/resume
                % path (lfl=1). With overwrite=false, nk_VisModelsPrep reuses
                % existing VISdatamat files and computes only missing selected
                % CV2 cells. The resolver is called read-only here only to
                % report existing coverage; it must not switch Auto to lfl=2.
                visSpec = struct('gridAction',spec.GridAct,'requireComplete',false);
                if isfield(spec,'visDataMasterFile'), visSpec.visDataMasterFile = spec.visDataMasterFile; end
                if isfield(spec,'visDataFiles'), visSpec.visDataFiles = spec.visDataFiles; end
                try
                    [~, resolveReport] = NMRunTools.resolveVISDataMat(NMlocal, analind, visSpec);
                catch ME
                    resolveReport = struct('ok',false,'message',ME.message,'identifier',ME.identifier);
                end
                mode = 'scratch';
            elseif any(strcmp(mode,{'visdatamat','visdata','vis'}))
                visSpec = struct('gridAction',spec.GridAct,'requireComplete',true);
                if isfield(spec,'vismat'), visSpec.vismat = spec.vismat; end
                if isfield(spec,'visDataMasterFile'), visSpec.visDataMasterFile = spec.visDataMasterFile; end
                if isfield(spec,'visDataFiles'), visSpec.visDataFiles = spec.visDataFiles; end
                [spec.vismat, resolveReport] = NMRunTools.resolveVISDataMat(NMlocal, analind, visSpec);
                mode = 'visdatamat';
            elseif ~strcmp(mode,'scratch')
                error('NMRunTools:badVisualizationMode', 'Unsupported visualization operationMode: %s', mode);
            end
            if logical(spec.loadParameters) && (~isfield(spec,'optpreprocmat') || isempty(spec.optpreprocmat) || ~isfield(spec,'optmodelmat') || isempty(spec.optmodelmat))
                error('NMRunTools:missingVisualizationParameterFiles', 'Loading saved preprocessing/model parameters requires optpreprocmat and optmodelmat payloads.');
            end
            inp = struct('analind',analind, 'lfl',1, 'extraL',[], 'ovrwrt',NMRunTools.yesNoCode(spec.overwrite), ...
                'multiflag',2, 'CV1',NMRunTools.yesNoCode(spec.operateAtCV1), ...
                'saveparam',NMRunTools.yesNoCode(spec.saveParameters), 'loadparam',NMRunTools.yesNoCode(spec.loadParameters), ...
                'writeCV2',NMRunTools.yesNoCode(spec.writeCV2Maps), 'CVRnorm',NMRunTools.cvrNormCode(spec.cvrNorm), ...
                'DecompMode',NMRunTools.yesNoCode(spec.decompMode), 'simCorrThresh',spec.simCorrThresh, ...
                'simCorrMethod',spec.simCorrMethod, 'CorrCompCutOff',spec.corrCompCutoff, 'SelCompCutOff',spec.selCompCutoff, ...
                'PruneMode',spec.pruneMode, 'PruneFraction',spec.pruneFraction, 'HideGridAct',logical(spec.hideGrid), ...
                'batchflag',1, 'lowmem',NMRunTools.yesNoCode(spec.lowMemory), 'datatype','VISdatamat');
            inp.GridAct = logical(spec.GridAct);
            if strcmp(mode,'visdatamat')
                inp.lfl = 2;
                inp.vismat = spec.vismat;
            else
                inp.lfl = 1;
            end
            if isfield(spec,'optpreprocmat'), inp.optpreprocmat = spec.optpreprocmat; end
            if isfield(spec,'optmodelmat'), inp.optmodelmat = spec.optmodelmat; end
        end

        function code = cvrNormCode(x)
            if ischar(x) || isstring(x)
                if strcmpi(char(string(x)),'sem'), code = 2; else, code = 1; end
            elseif isequal(x,2)
                code = 2;
            else
                code = 1;
            end
        end

        function [NMout, act, inpOut] = callVisModelsPrep(inp)
            global NM
            [act, inpOut] = nk_VisModelsPrep(99, inp, 'NM API');
            NMout = NM;
        end

        function report = validateVISDataMatShape(vismat, GridAct, requireComplete, source)
            if nargin < 4, source = ''; end
            if ~iscell(vismat)
                error('NMRunTools:badVISDataMatShape', 'VISdatamat payload must be a cell array. Source: %s', source);
            end
            if ~isequal(size(vismat), size(GridAct))
                error('NMRunTools:badVISDataMatSize', 'VISdatamat has size %s, but GridAct has size %s. Source: %s', ...
                    mat2str(size(vismat)), mat2str(size(GridAct)), source);
            end
            selected = logical(GridAct);
            present = false(size(GridAct));
            for ii = 1:numel(vismat)
                v = vismat{ii};
                if isempty(v), continue; end
                if ischar(v) || isstring(v)
                    present(ii) = exist(char(string(v)), 'file') == 2;
                else
                    present(ii) = true;
                end
            end
            nSelected = nnz(selected);
            nPresent = nnz(present & selected);
            missing = nSelected - nPresent;
            if requireComplete && missing > 0
                error('NMRunTools:incompleteVISDataMat', ...
                    'VISdatamat payload is incomplete for selected CV2 cells: %d/%d present. Source: %s', nPresent, nSelected, source);
            end
            report = struct('ok',missing==0 || ~requireComplete, 'message',sprintf('%d/%d selected VISdatamat entries present.', nPresent, nSelected), ...
                'source',source, 'nSelected',nSelected, 'nPresent',nPresent, 'nMissing',missing);
        end

        function report = validateMLIDataMatShape(mlimat, GridAct, requireComplete, source)
            if nargin < 4, source = ''; end
            if ~iscell(mlimat)
                error('NMRunTools:badMLIDataMatShape', 'MLIdatamat payload must be a cell array. Source: %s', source);
            end
            if ~isequal(size(mlimat), size(GridAct))
                error('NMRunTools:badMLIDataMatSize', 'MLIdatamat has size %s, but GridAct has size %s. Source: %s', ...
                    mat2str(size(mlimat)), mat2str(size(GridAct)), source);
            end
            selected = logical(GridAct);
            present = false(size(GridAct));
            for ii = 1:numel(mlimat)
                v = mlimat{ii};
                if isempty(v), continue; end
                if ischar(v) || isstring(v)
                    present(ii) = exist(char(string(v)), 'file') == 2;
                else
                    present(ii) = true;
                end
            end
            nSelected = nnz(selected);
            nPresent = nnz(present & selected);
            missing = nSelected - nPresent;
            if requireComplete && missing > 0
                error('NMRunTools:incompleteMLIDataMat', ...
                    'MLIdatamat payload is incomplete for selected CV2 partitions: %d/%d present. Source: %s', nPresent, nSelected, source);
            end
            report = struct('ok',missing==0 || ~requireComplete, 'message',sprintf('%d/%d selected MLIdatamat entries present.', nPresent, nSelected), ...
                'source',source, 'nSelected',nSelected, 'nPresent',nPresent, 'nMissing',missing, 'presentMask',present);
        end


        function NM = disableUnsupportedOptRegul(NM, analind)
            % OptRegul remains unavailable in the browser ML configurator.
            % Enforce the temporary hard-disable at the public training
            % boundary as well as during configuration export so resumed or
            % pre-existing analysis snapshots cannot reactivate it.
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'GRD') && isstruct(NM.TrainParam.GRD) && ...
                    isfield(NM.TrainParam.GRD,'OptRegul') && isstruct(NM.TrainParam.GRD.OptRegul) && ...
                    ~isempty(NM.TrainParam.GRD.OptRegul)
                or = NM.TrainParam.GRD.OptRegul;
                if numel(or) > 1, or = or(1); end
                or.flag = false;
                NM.TrainParam.GRD.OptRegul = or;
            end
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && ...
                    analind >= 1 && analind <= numel(NM.analysis) && isstruct(NM.analysis{analind}) && ...
                    isfield(NM.analysis{analind},'params') && isstruct(NM.analysis{analind}.params) && ...
                    isfield(NM.analysis{analind}.params,'TrainParam') && isstruct(NM.analysis{analind}.params.TrainParam) && ...
                    isfield(NM.analysis{analind}.params.TrainParam,'GRD') && isstruct(NM.analysis{analind}.params.TrainParam.GRD) && ...
                    isfield(NM.analysis{analind}.params.TrainParam.GRD,'OptRegul') && ...
                    isstruct(NM.analysis{analind}.params.TrainParam.GRD.OptRegul) && ...
                    ~isempty(NM.analysis{analind}.params.TrainParam.GRD.OptRegul)
                or = NM.analysis{analind}.params.TrainParam.GRD.OptRegul;
                if numel(or) > 1, or = or(1); end
                or.flag = false;
                NM.analysis{analind}.params.TrainParam.GRD.OptRegul = or;
            end
        end

        function spec = normalizePreprocessSpec(NM, analind, spec)
            if ~isstruct(spec), spec = struct(); end
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                error('NMRunTools:missingGridAction', ...
                    ['No default grid action is inferred for preprocessAnalysis. ', ...
                     'Pass gridAction=''all'' or an explicit logical GridAct matrix.']);
            end
            spec.overwrite = NMRunTools.fieldOr(spec,'overwrite',false);
            spec.savePreproc = NMRunTools.fieldOr(spec,'savePreproc',true);
            spec.writeParameters = NMRunTools.fieldOr(spec,'writeParameters',false);
            spec.useExistingParameters = NMRunTools.fieldOr(spec,'useExistingParameters',true);
            spec.hideGrid = NMRunTools.fieldOr(spec,'hideGrid',true);
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.analind = analind;
            spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
        end

        function spec = normalizeTrainSpec(NM, analind, spec)
            if ~isstruct(spec), spec = struct(); end
            spec.operationMode = NMRunTools.fieldOr(spec,'operationMode','scratch');
            spec.overwrite = NMRunTools.fieldOr(spec,'overwrite',false);
            spec.update = NMRunTools.fieldOr(spec,'update',true);
            if ~isfield(spec,'gridAction') || isempty(spec.gridAction)
                error('NMRunTools:missingGridAction', ...
                    ['No default grid action is inferred for trainAnalysis. ', ...
                     'nk_MLOptimizerPrep initializes GridAct as false and requires explicit CV2-grid selection before proceeding; ', ...
                     'pass gridAction=''all'' or an explicit logical GridAct matrix.']);
            end
            spec.gridAction = spec.gridAction;
            spec.hideGrid = NMRunTools.fieldOr(spec,'hideGrid',false);
            spec.debugall = NMRunTools.fieldOr(spec,'debugall',false);
            spec.debugopt = NMRunTools.fieldOr(spec,'debugopt',false);
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.analind = analind;
            spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
        end

        function spec = normalizeOOCVSpec(NM, analind, oocvind, spec)
            if ~isstruct(spec), spec = struct(); end
            spec.operationMode = NMRunTools.fieldOr(spec,'operationMode','scratch');
            spec.overwrite = NMRunTools.fieldOr(spec,'overwrite',false);
            spec.saveparam = NMRunTools.fieldOr(spec,'saveparam',false);
            spec.saveCV1 = NMRunTools.fieldOr(spec,'saveCV1',false);
            spec.loadparam = NMRunTools.fieldOr(spec,'loadparam',false);
            spec.permutationTest = NMRunTools.fieldOr(spec,'permutationTest',false);
            spec.nPerms = NMRunTools.fieldOr(spec,'nPerms',1000);
            spec.devMode = NMRunTools.resolveDevMode(spec);
            spec.gridAction = NMRunTools.fieldOr(spec,'gridAction','analysis');
            spec.hideGrid = NMRunTools.fieldOr(spec,'hideGrid',false);
            spec.analind = analind;
            spec.oocvind = oocvind;
            if (ischar(spec.gridAction) || isstring(spec.gridAction)) && ...
                    strcmpi(char(string(spec.gridAction)),'analysis') && ...
                    isfield(NM.analysis{analind},'GDdims') && ~isempty(NM.analysis{analind}.GDdims) && ...
                    isfield(NM.analysis{analind}.GDdims{1},'GridAct')
                spec.GridAct = logical(NM.analysis{analind}.GDdims{1}.GridAct);
            else
                spec.GridAct = NMRunTools.gridActFromSpec(NM.analysis{analind}.params.cv, spec.gridAction);
            end
        end

        function p = preprocessP(NMlocal, analind, spec)
            CVlocal = NMlocal.analysis{analind}.params.cv;
            p = struct('saveproc',logical(spec.savePreproc), ...
                'ovrwrtfl',NMRunTools.yesNoCode(spec.overwrite), ...
                'writefl',NMRunTools.yesNoCode(spec.writeParameters), ...
                'useparamfl',NMRunTools.yesNoCode(spec.useExistingParameters), ...
                'HideGridAct',logical(spec.hideGrid), ...
                'batchflag',2, ...
                'NM',NMlocal, ...
                'CV',CVlocal);
        end

        function inp = trainInp(NMlocal, analind, spec)
            % Defaults below mirror the default inp struct in
            % nk_MLOptimizerPrep.m.  Modality-derived runtime fields such as
            % nF, F, varind and related names are not defaults; they are
            % populated by nk_GetAnalModalInfo_config.  That legacy
            % configurator calls nk_SetupGlobalVariables and therefore must
            % run with the same global NM/CV context that the original CLI
            % runtime manager establishes before execution.
            inp = struct('analind',analind, 'lfl',NMRunTools.lflValue(spec.operationMode), ...
                'preprocmat',[], 'gdmat',[], 'gdanalmat',[], 'varstr',[], 'concatfl',[], ...
                'ovrwrt',NMRunTools.yesNoCode(spec.overwrite), 'update',logical(spec.update), ...
                'HideGridAct',logical(spec.hideGrid), 'batchflag',2, 'debugall',logical(spec.debugall), 'debugopt',logical(spec.debugopt));
            inp.GridAct = spec.GridAct;
            NMRunTools.assertFunction('nk_GetAnalModalInfo_config');
            try
                NMRunTools.establishLegacyRuntimeContext(NMlocal, spec);
                inp = nk_GetAnalModalInfo_config(NMlocal, inp);
            catch ME
                detail = ME.message;
                if exist('getReport','file') == 2
                    detail = getReport(ME, 'extended', 'hyperlinks', 'off');
                end
                error('NMRunTools:analysisModalInfoFailed', ...
                    ['nk_GetAnalModalInfo_config failed while preparing trainAnalysis. Exact diagnostic:' char(10) '%s'], detail);
            end
            required = {'nF','varind'};
            missing = {};
            for ii = 1:numel(required)
                if ~isfield(inp, required{ii}) || isempty(inp.(required{ii}))
                    missing{end+1} = required{ii}; %#ok<AGROW>
                end
            end
            if ~isempty(missing)
                error('NMRunTools:analysisModalInfoIncomplete', ...
                    ['nk_GetAnalModalInfo_config did not populate required runtime field(s) for trainAnalysis: %s. ', ...
                     'The runtime API cannot infer these fields without the legacy modality-info configurator.'], ...
                    strjoin(missing, ', '));
            end
            [ix,jx] = size(NMlocal.analysis{analind}.params.cv.TrainInd);
            if isempty(inp.GridAct)
                inp.GridAct = spec.GridAct;
            end
            if isempty(inp.GridAct)
                error('NMRunTools:missingGridAction', ...
                    'No CV2 grid selection is available. Pass gridAction=''all'' or an explicit logical GridAct matrix.');
            end
            inp.GridAct = logical(inp.GridAct);
            if ~isequal(size(inp.GridAct), [ix jx])
                error('NMRunTools:badGridActSize', ...
                    'GridAct has size %s, but selected analysis CV requires size [%d %d].', ...
                    mat2str(size(inp.GridAct)), ix, jx);
            end
            inp.NM = NMlocal;
            inp.CV = NMlocal.cv;
        end

        function inp = oocvInp(NM, analind, oocvind, spec)
            inp = struct('analind',analind, 'oocvind',oocvind, 'OO',NM.OOCV{oocvind}, ...
                'lfl',NMRunTools.oocvLFLValue(spec.operationMode), 'oocvmat',[], ...
                'ovrwrt',NMRunTools.yesNoCode(spec.overwrite), ...
                'saveparam',NMRunTools.yesNoCode(spec.saveparam), ...
                'saveCV1',NMRunTools.yesNoCode(spec.saveCV1), ...
                'loadparam',NMRunTools.yesNoCode(spec.loadparam), ...
                'PERM',struct('flag',NMRunTools.yesNoCode(spec.permutationTest), 'nperms',double(spec.nPerms)), ...
                'HideGridAct',logical(spec.hideGrid), 'batchflag',1);
            inp.GridAct = spec.GridAct;
            if strcmp(spec.operationMode,'precomputed'), inp.oocvmat = spec.oocvmat; end
        end

        function inp = attachOOCVApplicationPreproc(inp, NM, analind, oocvind, assessment)
            % Attach only configured P8D runtime projections. The branch
            % assessment remains the scientific authority for applicability;
            % the legacy backend receives a preproc-indexed transient plan.
            if isempty(assessment) || ~isstruct(assessment) || ...
                    ~isfield(assessment,'assessmentSupported') || ...
                    ~logical(assessment.assessmentSupported) || ...
                    ~isfield(assessment,'branches') || isempty(assessment.branches)
                return;
            end
            branches = assessment.branches;
            preprocIndex = [branches.preprocIndex];
            if isempty(preprocIndex), return; end
            runtimeByIndex = cell(1,max(preprocIndex));
            configured = false;
            for ii = 1:numel(branches)
                p = branches(ii).preprocIndex;
                projection = NMOOCVApplicationPreprocTools.runtimeProjection( ...
                    NM, analind, oocvind, p);
                if isempty(projection.featureActIndex), continue; end
                if ~logical(branches(ii).specialFeatureImputationAvailable)
                    error('NMRunTools:oocvApplicationPreprocNotApplicable', ...
                        ['Stored OOCV application preprocessing exists for branch %d, ', ...
                         'but the current training/OOCV discrepancy no longer permits ', ...
                         'OOCV-only feature imputation. Reopen the OOCV application ', ...
                         'preprocessing configurator before running the model.'], p);
                end
                runtimeByIndex{p} = projection;
                configured = true;
            end
            if configured
                inp.OOCVApplicationPreprocByIndex = runtimeByIndex;
            end
        end

        function NM = bindOOCVRuntimeContext(NM, analind, oocvind)
            % nk_OOCVPrep initializes modality-independent globals from the
            % selected analysis snapshot while nk_SetupGlobalVariables obtains
            % OOCV runtime settings from the active NM.TrainParam.OOCV branch.
            % analysis.params.OOCV is reserved for persistent analysis-specific
            % application preprocessing and must never carry imported NM.OOCV
            % data. Pre-P8B copied carrier state is normalized on entry.
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || ...
                    numel(NM.OOCV) < oocvind || isempty(NM.OOCV{oocvind}) || ...
                    ~isstruct(NM.OOCV{oocvind})
                error('NMRunTools:missingOOCVContainer', ...
                    'NM.OOCV{%d} does not exist. Import OOCV/application data before calling applyOOCV.', oocvind);
            end
            if ~isfield(NM.OOCV{oocvind},'Y') || isempty(NM.OOCV{oocvind}.Y)
                error('NMRunTools:emptyOOCVContainer', ...
                    'NM.OOCV{%d} contains no imported modality data.', oocvind);
            end
            if ~isfield(NM.analysis{analind},'params') || ~isstruct(NM.analysis{analind}.params)
                error('NMRunTools:missingAnalysisParams', ...
                    'Analysis %d has no params snapshot for OOCV runtime binding.', analind);
            end
            if ~isfield(NM.analysis{analind}.params,'TrainParam') || ...
                    ~isstruct(NM.analysis{analind}.params.TrainParam)
                error('NMRunTools:missingAnalysisTrainParam', ...
                    'Analysis %d has no TrainParam snapshot for OOCV runtime binding.', analind);
            end
            NM = NMOOCVApplicationPreprocTools.normalizeAnalysisState(NM, analind);
            if ~isfield(NM.analysis{analind}.params.TrainParam,'OOCV') || ...
                    ~isstruct(NM.analysis{analind}.params.TrainParam.OOCV)
                if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'OOCV') && isstruct(NM.TrainParam.OOCV)
                    NM.analysis{analind}.params.TrainParam.OOCV = NM.TrainParam.OOCV;
                elseif exist('NMOOCVTools','class') == 8
                    NMtmp = struct('TrainParam', NM.analysis{analind}.params.TrainParam);
                    NMtmp = NMOOCVTools.applyToNM(NMtmp, []);
                    NM.analysis{analind}.params.TrainParam.OOCV = NMtmp.TrainParam.OOCV;
                else
                    error('NMRunTools:missingOOCVRuntimeConfig', ...
                        ['Analysis %d has no TrainParam.OOCV runtime branch and ', ...
                         'NMOOCVTools is not on the MATLAB path.'], analind);
                end
            end
        end

        function status = analysisStatus(NM, analind)
            status = NaN;
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && ...
                    numel(NM.analysis) >= analind && isstruct(NM.analysis{analind}) && ...
                    isfield(NM.analysis{analind},'status') && ~isempty(NM.analysis{analind}.status)
                status = NM.analysis{analind}.status;
            end
        end

        function tf = analysisHasField(NM, analind, fieldName)
            tf = isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && ...
                numel(NM.analysis) >= analind && isstruct(NM.analysis{analind}) && ...
                isfield(NM.analysis{analind}, fieldName) && ~isempty(NM.analysis{analind}.(fieldName));
        end

        function tf = analysisHasOOCVResult(NM, analind, oocvind)
            tf = isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) && ...
                numel(NM.analysis) >= analind && isstruct(NM.analysis{analind}) && ...
                isfield(NM.analysis{analind},'OOCV') && iscell(NM.analysis{analind}.OOCV) && ...
                numel(NM.analysis{analind}.OOCV) >= oocvind && ...
                ~isempty(NM.analysis{analind}.OOCV{oocvind});
        end

        function val = lflValue(mode)
            switch lower(strtrim(char(string(mode))))
                case {'scratch','fromscratch','compute_from_scratch'}, val = 1;
                case {'preproc','preprocdata'}, val = 2;
                case {'cvdatamat','datamat'}, val = 3;
                case {'cvresults','results'}, val = 4;
                otherwise, val = 1;
            end
        end

        function val = oocvLFLValue(mode)
            switch lower(strtrim(char(string(mode))))
                case {'precomputed','oocvdatamat'}, val = 2;
                otherwise, val = 1;
            end
        end

        function code = yesNoCode(tf)
            if ischar(tf) || isstring(tf)
                tf = any(strcmpi(strtrim(char(string(tf))), {'yes','true','1','on','overwrite','save','load'}));
            end
            if logical(tf), code = 1; else, code = 2; end
        end

        function GridAct = gridActFromSpec(CV, gridAction)
            if islogical(gridAction) || isnumeric(gridAction)
                GridAct = logical(gridAction);
                return;
            end
            [ix,jx] = size(CV.TrainInd);
            switch lower(strtrim(char(string(gridAction))))
                case {'all','true','run_all','analysis'}
                    GridAct = true(ix,jx);
                otherwise
                    GridAct = true(ix,jx);
            end
        end

        function devMode = resolveDevMode(spec)
            % DEV is not a modelling default.  It is a legacy global runtime
            % flag initialized by nm.m as false and set to true only when NM
            % is launched with the 'dev' option.  The API must provide a
            % scalar logical value before entering legacy Prep managers,
            % because they use expressions such as "~isdeployed && DEV".
            if isstruct(spec) && isfield(spec,'devMode') && ~isempty(spec.devMode)
                raw = spec.devMode;
            else
                global DEV
                if isempty(DEV)
                    raw = false;
                elseif (islogical(DEV) || isnumeric(DEV)) && isscalar(DEV)
                    raw = DEV;
                else
                    error('NMRunTools:invalidDEVGlobal', ...
                        ['The legacy global DEV exists but is not a scalar logical/numeric value. ', ...
                         'This cannot be passed safely to nk_MLOptimizerPrep. ', ...
                         'Pass spec.devMode as true/false or clear/reset the legacy global context.']);
                end
            end
            if ~(islogical(raw) || isnumeric(raw)) || ~isscalar(raw)
                error('NMRunTools:badDevModeSpec', 'spec.devMode must be a scalar logical or numeric value.');
            end
            devMode = logical(raw);
        end

        function establishLegacyRuntimeContext(NMlocal, spec)
            % The Prep runtime managers are legacy-global aware.  The public
            % API wrapper therefore establishes the complete noninteractive
            % scalar/global context required by those managers before the
            % backend is entered.  Scientific and modality parameters remain
            % authoritative in NM / nk_GetAnalModalInfo_config; this method
            % only materializes legacy runtime metadata and scalar flags.
            global NM CV DEV DEBUG JSMEM simFlag UI NMinfo EXPERT SPMAVAIL OCTAVE
            NM = NMlocal;
            if isfield(NMlocal,'cv')
                CV = NMlocal.cv;
            else
                CV = [];
            end
            DEV = logical(spec.devMode);
            EXPERT = NMRunTools.normalizeLegacyLogicalGlobal(EXPERT,false,'EXPERT');
            SPMAVAIL = NMRunTools.normalizeLegacyLogicalGlobal( ...
                SPMAVAIL,exist('spm','file')==2,'SPMAVAIL');
            OCTAVE = NMRunTools.normalizeLegacyLogicalGlobal( ...
                OCTAVE,exist('OCTAVE_VERSION','builtin')~=0,'OCTAVE');
            NMinfo = NMRunTools.establishLegacyInfoContext(NMlocal,NMinfo);
            DEBUG = [];
            JSMEM = [];
            simFlag = 0;
            if isstruct(spec) && isfield(spec,'UI') && isstruct(spec.UI)
                UI = spec.UI;
            elseif isempty(UI) || ~isstruct(UI)
                UI = NMRuntimeProgressTools.appUIContext(false, struct('source','legacy_runtime'));
            end
        end

        function NMinfo = establishLegacyInfoContext(NMlocal, NMinfo)
            % Legacy visualization/report functions access NMinfo.info
            % directly.  Public API calls must therefore work without a prior
            % nm.m session, while preserving a valid initialized installation
            % context when one already exists.
            if isempty(NMinfo)
                NMinfo = struct();
            elseif ~isstruct(NMinfo) || ~isscalar(NMinfo)
                error('NMRunTools:invalidNMinfoGlobal', ...
                    ['The legacy global NMinfo is nonempty but is not a scalar structure. ', ...
                     'Clear or repair the legacy runtime context before invoking an NMRunTools runner.']);
            end
            if ~isfield(NMinfo,'info') || isempty(NMinfo.info)
                NMinfo.info = struct();
            elseif ~isstruct(NMinfo.info) || ~isscalar(NMinfo.info)
                error('NMRunTools:invalidNMinfoInfo', ...
                    'The legacy global NMinfo.info must be a scalar structure.');
            end

            info = NMinfo.info;
            defaults = struct( ...
                'name','NeuroMiner', ...
                'ver','', ...
                'author','', ...
                'affil','', ...
                'dep','', ...
                'inst','', ...
                'datever','', ... %'timestamp',''
                'email','');
            if ~isfield(info,'ver') || isempty(info.ver)
                if ~isstruct(NMlocal) || ~isfield(NMlocal,'defs') || ...
                        ~isstruct(NMlocal.defs) || ~isfield(NMlocal.defs,'NM_ver') || ...
                        isempty(NMlocal.defs.NM_ver)
                    error('NMRunTools:missingLegacyRuntimeVersion', ...
                        ['NMinfo.info.ver is unavailable and NM.defs.NM_ver is missing. ', ...
                         'The public runtime cannot fabricate an installation/version identity.']);
                end
                defaults.ver = NMRunTools.normalizeLegacyInfoText( ...
                    NMlocal.defs.NM_ver,'NM.defs.NM_ver');
            else
                defaults.ver = NMRunTools.normalizeLegacyInfoText(info.ver,'NMinfo.info.ver');
            end

            names = fieldnames(defaults);
            for ii = 1:numel(names)
                fieldName = names{ii};
                if ~isfield(info,fieldName) || isempty(info.(fieldName))
                    info.(fieldName) = defaults.(fieldName);
                else
                    info.(fieldName) = NMRunTools.normalizeLegacyInfoText( ...
                        info.(fieldName),['NMinfo.info.' fieldName]);
                end
            end
            NMinfo.info = info;
        end

        function value = normalizeLegacyLogicalGlobal(raw, fallback, globalName)
            if isempty(raw)
                value = logical(fallback);
                return;
            end
            if ~(islogical(raw) || isnumeric(raw)) || ~isscalar(raw) || ~isfinite(double(raw))
                error('NMRunTools:invalidLegacyLogicalGlobal', ...
                    'The legacy global %s must be empty or a finite scalar logical/numeric value.', ...
                    globalName);
            end
            value = logical(raw);
        end

        function text = normalizeLegacyInfoText(raw, fieldName)
            if isstring(raw) && isscalar(raw)
                text = char(raw);
            elseif ischar(raw) && (isempty(raw) || isrow(raw))
                text = raw;
            else
                error('NMRunTools:invalidLegacyInfoField', ...
                    '%s must be a character row vector or scalar string.',fieldName);
            end
        end

        function assertFunction(fname)
            if exist(fname,'file') ~= 2
                error('NMRunTools:missingLegacyRunner', 'Legacy runtime function %s.m is not on the MATLAB path.', fname);
            end
        end

        function assertAnalysisReady(NM, analind, requireTrained)
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || analind < 1 || analind > numel(NM.analysis) || isempty(NM.analysis{analind})
                error('NMRunTools:badAnalysisIndex', 'Analysis %d does not exist.', analind);
            end
            A = NM.analysis{analind};
            roots = NMAnalysisManagerTools.listAnalyses(NM);
            if ~roots.rootExists(analind)
                error('NMRunTools:staleAnalysisRoot', 'Analysis %d root path is missing. Relink it before execution.', analind);
            end
            if ~isfield(A,'params') || ~isfield(A.params,'TrainParam') || ~isfield(A.params,'cv')
                error('NMRunTools:analysisNotInitialized', 'Analysis %d has no parameter/CV snapshot.', analind);
            end
            if requireTrained && (~isfield(A,'GDdims') || isempty(A.GDdims))
                error('NMRunTools:analysisNotTrained', 'Analysis %d does not contain GDdims. Train the analysis before applying OOCV data.', analind);
            end
        end

        function msg = reportMessage(report)
            msg = 'see readiness report';
            if isfield(report,'message') && ~isempty(report.message), msg = char(string(report.message)); end
        end


        function rootdir = analysisRootDir(A)
            rootdir = '';
            if isstruct(A) && isfield(A,'rootdir') && ~isempty(A.rootdir)
                rootdir = char(string(A.rootdir));
            elseif isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'rootdir') && ~isempty(A.params.rootdir)
                rootdir = char(string(A.params.rootdir));
            end
        end

        function id = dataId(NM, A)
            id = '';
            if isstruct(NM) && isfield(NM,'id') && ~isempty(NM.id)
                id = char(string(NM.id)); return;
            end
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'id') && ~isempty(A.params.id)
                id = char(string(A.params.id)); return;
            end
            if isstruct(A) && isfield(A,'id') && ~isempty(A.id)
                id = char(string(A.id));
            end
        end

        function [preprocmat, source] = scanPreprocDataFiles(rootdir, dataId, inp, GridAct, files)
            meta = strcmp(inp.metastr,'_META');
            if nargin < 5 || isempty(files)
                files = NMRunTools.collectPreprocDataFiles(rootdir, dataId, meta);
                source = sprintf('scanned PreprocData files below %s', rootdir);
            else
                files = cellstr(files);
                source = sprintf('%d manually selected PreprocData file(s)', numel(files));
            end
            if isempty(files)
                error('NMRunTools:noPreprocDataFiles', 'No PreprocData files for ID %s were found below %s.', dataId, rootdir);
            end
            nStreams = NMRunTools.preprocStreamCount(inp);
            if meta
                labels = {'PreprocDataMeta_ID'};
            else
                labels = NMRunTools.preprocStreamLabels(inp, nStreams);
            end
            cvsz = size(GridAct);
            perStream = cell(nStreams,1);
            for ss = 1:nStreams
                perStream{ss} = cell(cvsz);
            end
            for ff = 1:numel(files)
                fpath = files{ff};
                [outperm,outfold] = NMRunTools.readPreprocCVIndex(fpath);
                if isempty(outperm) || isempty(outfold) || outperm < 1 || outfold < 1 || outperm > cvsz(1) || outfold > cvsz(2)
                    continue;
                end
                fname = NMRunTools.fileBaseName(fpath);
                for ss = 1:nStreams
                    if NMRunTools.filenameMatchesStream(fname, labels{ss})
                        perStream{ss}{outperm,outfold} = fpath;
                    end
                end
            end
            if NMRunTools.isConcatPreproc(inp) && nStreams > 1
                F = cell(cvsz);
                for pp = 1:cvsz(1)
                    for dd = 1:cvsz(2)
                        rows = cell(nStreams,1);
                        ok = true;
                        for ss = 1:nStreams
                            rows{ss} = perStream{ss}{pp,dd};
                            if isempty(rows{ss}), ok = false; end
                        end
                        if ok
                            F{pp,dd} = char(rows{:});
                        end
                    end
                end
                preprocmat = {F};
            else
                preprocmat = perStream;
            end
        end

        function files = collectPreprocDataFiles(rootdir, dataId, meta)
            rootdir = char(string(rootdir));
            dataId = char(string(dataId));
            files = {};
            dirs = strsplit(genpath(rootdir), pathsep);
            for dd = 1:numel(dirs)
                if isempty(dirs{dd}), continue; end
                D = dir(fullfile(dirs{dd}, sprintf('*PreprocData*ID%s*.mat', dataId)));
                for ii = 1:numel(D)
                    if ~D(ii).isdir && isempty(regexp(D(ii).name, 'PreprocDataParam', 'once')) && ...
                            (contains(D(ii).name,'PreprocDataMeta') == meta)
                        files{end+1,1} = fullfile(D(ii).folder,D(ii).name); %#ok<AGROW>
                    end
                end
            end
        end

        function [outperm,outfold] = readPreprocCVIndex(fpath)
            outperm = []; outfold = [];
            try
                S = load(fpath,'outperm','outfold','datid'); %#ok<NASGU>
                if isfield(S,'outperm') && isfield(S,'outfold')
                    outperm = double(S.outperm);
                    outfold = double(S.outfold);
                end
            catch ME
                error('NMRunTools:badPreprocDataFile', 'Cannot read outperm/outfold from PreprocData file %s: %s', fpath, ME.message);
            end
        end

        function n = preprocStreamCount(inp)
            n = 1;
            if isfield(inp,'varind') && ~isempty(inp.varind)
                n = numel(inp.varind);
            elseif isfield(inp,'nF') && ~isempty(inp.nF)
                n = double(inp.nF);
            end
            n = max(1, round(double(n)));
        end

        function labels = preprocStreamLabels(inp, nStreams)
            labels = cell(nStreams,1);
            raw = [];
            if isfield(inp,'varstr') && ~isempty(inp.varstr), raw = inp.varstr; end
            for ss = 1:nStreams
                labels{ss} = '';
                if iscell(raw) && numel(raw) >= ss && ~isempty(raw{ss})
                    labels{ss} = char(string(raw{ss}));
                elseif (ischar(raw) || isstring(raw)) && ~isempty(raw)
                    labels{ss} = char(string(raw));
                elseif isfield(inp,'varind') && numel(inp.varind) >= ss
                    labels{ss} = sprintf('var%g', double(inp.varind(ss)));
                else
                    labels{ss} = sprintf('var%g', ss);
                end
            end
        end

        function tf = filenameMatchesStream(fname, label)
            fname = char(string(fname));
            label = char(string(label));
            if isempty(label)
                tf = true;
            else
                tf = ~isempty(regexp(fname, regexptranslate('escape', label), 'once'));
                if ~tf && strcmpi(label,'Meta')
                    tf = ~isempty(regexp(fname,'Meta','once'));
                end
            end
        end

        function tf = isConcatPreproc(inp)
            tf = isfield(inp,'concatfl') && ~isempty(inp.concatfl) && logical(inp.concatfl);
        end

        function report = validatePreprocMatShape(preprocmat, inp, GridAct, requireComplete, source)
            if ~iscell(preprocmat) || isempty(preprocmat)
                error('NMRunTools:badPreprocMatShape', 'preprocmat must be a nonempty cell array.');
            end
            cvsz = size(GridAct);
            nExpected = NMRunTools.preprocStreamCount(inp);
            concatfl = NMRunTools.isConcatPreproc(inp) && nExpected > 1;
            if concatfl
                expectedOuter = 1;
            else
                expectedOuter = nExpected;
            end
            if numel(preprocmat) < expectedOuter
                error('NMRunTools:badPreprocMatShape', 'preprocmat has %d outer stream(s), expected %d.', numel(preprocmat), expectedOuter);
            end
            missing = false(cvsz);
            present = false(cvsz);
            for ss = 1:expectedOuter
                C = preprocmat{ss};
                if ~iscell(C) || ~isequal(size(C), cvsz)
                    error('NMRunTools:badPreprocMatShape', 'preprocmat{%d} has size %s, expected %s.', ss, mat2str(size(C)), mat2str(cvsz));
                end
                for pp = 1:cvsz(1)
                    for dd = 1:cvsz(2)
                        if ~GridAct(pp,dd), continue; end
                        item = C{pp,dd};
                        ok = NMRunTools.preprocItemReadable(item, concatfl, nExpected);
                        present(pp,dd) = present(pp,dd) || ok;
                        missing(pp,dd) = missing(pp,dd) || ~ok;
                    end
                end
            end
            nSelected = nnz(GridAct);
            nMissing = nnz(missing & GridAct);
            if requireComplete && nMissing > 0
                error('NMRunTools:incompletePreprocMat', 'PreprocData is incomplete for %d/%d selected CV2 cells (%s).', nMissing, nSelected, char(string(source)));
            end
            report = struct('ok', nMissing == 0, 'source',source, 'analysisEntryPoint','preproc', ...
                'concatfl',logical(concatfl), 'nExpectedStreams',nExpected, 'nOuterStreams',expectedOuter, ...
                'gridSize',cvsz, 'selectedCells',nSelected, 'presentCells',nnz(present & GridAct), ...
                'missingCells',nMissing, 'GridAct',logical(GridAct));
        end

        function ok = preprocItemReadable(item, concatfl, nExpected)
            ok = false;
            if isempty(item), return; end
            if concatfl
                rows = cellstr(item);
                rows = rows(~cellfun(@isempty, strtrim(rows)));
                if numel(rows) ~= nExpected, return; end
                ok = all(cellfun(@(x) exist(strtrim(x),'file') == 2, rows));
            elseif ischar(item) || isstring(item)
                ok = exist(strtrim(char(string(item))),'file') == 2;
            end
        end

        function name = fileBaseName(fpath)
            [~,name,ext] = fileparts(fpath);
            name = [name ext];
        end

        function [gdmat, source] = scanCVDataMatFiles(rootdir, dataId, inp, GridAct, files)
            if nargin < 5 || isempty(files)
                files = NMRunTools.collectCVDataMatFiles(rootdir, dataId);
                source = sprintf('scanned CVdatamat files below %s', rootdir);
            else
                files = cellstr(files);
                source = sprintf('%d manually selected CVdatamat file(s)', numel(files));
            end
            if isempty(files)
                error('NMRunTools:noCVDataMatFiles', 'No CVdatamat files for ID %s were found below %s.', dataId, rootdir);
            end
            nStreams = NMRunTools.preprocStreamCount(inp);
            labels = NMRunTools.preprocStreamLabels(inp, nStreams);
            cvsz = size(GridAct);
            perStream = cell(nStreams,1);
            for ss = 1:nStreams
                perStream{ss} = cell(cvsz);
            end
            for ff = 1:numel(files)
                fpath = files{ff};
                [ofold,operm] = NMRunTools.readCVDataCVIndex(fpath);
                if isempty(operm) || isempty(ofold) || operm < 1 || ofold < 1 || ofold > cvsz(1) || operm > cvsz(2)
                    continue;
                end
                fname = NMRunTools.fileBaseName(fpath);
                for ss = 1:nStreams
                    if NMRunTools.filenameMatchesStream(fname, labels{ss})
                        perStream{ss}{ofold,operm} = fpath;
                    end
                end
            end
            if NMRunTools.isConcatPreproc(inp) && nStreams > 1
                F = cell(cvsz);
                for pp = 1:cvsz(1)
                    for dd = 1:cvsz(2)
                        rows = cell(nStreams,1);
                        ok = true;
                        for ss = 1:nStreams
                            rows{ss} = perStream{ss}{pp,dd};
                            if isempty(rows{ss}), ok = false; end
                        end
                        if ok
                            F{pp,dd} = char(rows{:});
                        end
                    end
                end
                gdmat = {F};
            else
                gdmat = perStream;
            end
        end

        function files = collectCVDataMatFiles(rootdir, dataId)
            rootdir = char(string(rootdir));
            dataId = char(string(dataId));
            files = {};
            dirs = strsplit(genpath(rootdir), pathsep);
            for dd = 1:numel(dirs)
                if isempty(dirs{dd}), continue; end
                D = dir(fullfile(dirs{dd}, sprintf('*CVdatamat*ID%s*.mat', dataId)));
                for ii = 1:numel(D)
                    if ~D(ii).isdir && isempty(regexp(D(ii).name, 'CVdataMaster|CVdatamatParam|CVdatamatMeta', 'once'))
                        files{end+1,1} = fullfile(D(ii).folder,D(ii).name); %#ok<AGROW>
                    end
                end
            end
        end

        function [ofold,operm] = readCVDataCVIndex(fpath)
            ofold = []; operm = [];
            try
                S = load(fpath,'ofold','operm','datid'); %#ok<NASGU>
                if isfield(S,'ofold') && isfield(S,'operm')
                    ofold = double(S.ofold);
                    operm = double(S.operm);
                end
            catch ME
                error('NMRunTools:badCVDataMatFile', 'Cannot read ofold/operm from CVdatamat file %s: %s', fpath, ME.message);
            end
        end

        function report = validateCVDataMatShape(gdmat, inp, GridAct, requireComplete, source)
            if ~iscell(gdmat) || isempty(gdmat)
                error('NMRunTools:badCVDataMatShape', 'gdmat must be a nonempty cell array.');
            end
            cvsz = size(GridAct);
            nExpected = NMRunTools.preprocStreamCount(inp);
            concatfl = NMRunTools.isConcatPreproc(inp) && nExpected > 1;
            if concatfl
                expectedOuter = 1;
            else
                expectedOuter = nExpected;
            end
            if numel(gdmat) < expectedOuter
                error('NMRunTools:badCVDataMatShape', 'gdmat has %d outer stream(s), expected %d.', numel(gdmat), expectedOuter);
            end
            missing = false(cvsz);
            present = false(cvsz);
            for ss = 1:expectedOuter
                C = gdmat{ss};
                if ~iscell(C) || ~isequal(size(C), cvsz)
                    error('NMRunTools:badCVDataMatShape', 'gdmat{%d} has size %s, expected %s.', ss, mat2str(size(C)), mat2str(cvsz));
                end
                for pp = 1:cvsz(1)
                    for dd = 1:cvsz(2)
                        if ~GridAct(pp,dd), continue; end
                        item = C{pp,dd};
                        ok = NMRunTools.cvDataItemReadable(item, concatfl, nExpected);
                        present(pp,dd) = present(pp,dd) || ok;
                        missing(pp,dd) = missing(pp,dd) || ~ok;
                    end
                end
            end
            nSelected = nnz(GridAct);
            nMissing = nnz(missing & GridAct);
            if requireComplete && nMissing > 0
                error('NMRunTools:incompleteCVDataMat', 'CVdatamat is incomplete for %d/%d selected CV2 cells (%s).', nMissing, nSelected, char(string(source)));
            end
            report = struct('ok', nMissing == 0, 'source',source, 'analysisEntryPoint','datamat', ...
                'concatfl',logical(concatfl), 'nExpectedStreams',nExpected, 'nOuterStreams',expectedOuter, ...
                'gridSize',cvsz, 'selectedCells',nSelected, 'presentCells',nnz(present & GridAct), ...
                'missingCells',nMissing, 'GridAct',logical(GridAct));
        end

        function ok = cvDataItemReadable(item, concatfl, nExpected)
            ok = false;
            if isempty(item), return; end
            if concatfl
                rows = cellstr(item);
                rows = rows(~cellfun(@isempty, strtrim(rows)));
                if numel(rows) ~= nExpected, return; end
                ok = all(cellfun(@(x) exist(strtrim(x),'file') == 2, rows));
            elseif ischar(item) || isstring(item)
                ok = exist(strtrim(char(string(item))),'file') == 2;
            end
        end

        function [gdanalmat, source] = scanCVResultsFiles(rootdir, dataId, inp)
            files = NMRunTools.collectCVResultsFiles(rootdir, dataId);
            if isempty(files)
                error('NMRunTools:noCVResultsFiles', 'No CVresults files for ID %s were found below %s.', dataId, rootdir);
            end
            nStreams = NMRunTools.cvResultsStreamCount(inp);
            labels = NMRunTools.preprocStreamLabels(inp, nStreams);
            perStream = cell(nStreams,1);
            for ff = 1:numel(files)
                fpath = files{ff};
                NMRunTools.assertCVResultsFileReadable(fpath);
                fname = NMRunTools.fileBaseName(fpath);
                assigned = false;
                streamIdx = NMRunTools.cvResultsStreamIndexFromName(fname);
                if ~isempty(streamIdx) && streamIdx >= 1 && streamIdx <= nStreams
                    perStream{streamIdx} = fpath;
                    assigned = true;
                end
                if ~assigned
                    for ss = 1:nStreams
                        if isempty(perStream{ss}) && NMRunTools.filenameMatchesStream(fname, labels{ss})
                            perStream{ss} = fpath;
                            assigned = true;
                            break;
                        end
                    end
                end
                if ~assigned && nStreams == 1 && isempty(perStream{1})
                    perStream{1} = fpath;
                end
            end
            gdanalmat = perStream;
            source = sprintf('scanned CVresults files below %s', rootdir);
        end

        function files = collectCVResultsFiles(rootdir, dataId)
            rootdir = char(string(rootdir));
            dataId = char(string(dataId));
            files = {};
            dirs = strsplit(genpath(rootdir), pathsep);
            for dd = 1:numel(dirs)
                if isempty(dirs{dd}), continue; end
                D = dir(fullfile(dirs{dd}, sprintf('*CVresults*ID%s*.mat', dataId)));
                for ii = 1:numel(D)
                    if ~D(ii).isdir && isempty(regexp(D(ii).name, 'CVresultsMaster|CVresultsParam|CVresultsMeta', 'once'))
                        files{end+1,1} = fullfile(D(ii).folder,D(ii).name); %#ok<AGROW>
                    end
                end
            end
        end

        function idx = cvResultsStreamIndexFromName(fname)
            idx = [];
            tok = regexp(char(string(fname)), '_var(\d+)(?:_|\.)', 'tokens', 'once');
            if ~isempty(tok)
                idx = str2double(tok{1});
                if isnan(idx), idx = []; end
            end
        end

        function n = cvResultsStreamCount(inp)
            n = 1;
            if isfield(inp,'nF') && ~isempty(inp.nF)
                n = double(inp.nF);
            elseif isfield(inp,'varind') && ~isempty(inp.varind)
                n = numel(inp.varind);
            end
            n = max(1, round(double(n)));
        end

        function assertCVResultsFileReadable(fpath)
            try
                S = load(fpath,'GDanalysis');
                if ~isfield(S,'GDanalysis') || isempty(S.GDanalysis)
                    error('missingGDanalysis');
                end
            catch ME
                error('NMRunTools:badCVResultsFile', 'Cannot read GDanalysis from CVresults file %s: %s', fpath, ME.message);
            end
        end

        function report = validateCVResultsShape(gdanalmat, inp, requireComplete, source)
            if ischar(gdanalmat) || isstring(gdanalmat)
                gdanalmat = cellstr(gdanalmat);
            end
            if ~iscell(gdanalmat) || isempty(gdanalmat)
                error('NMRunTools:badCVResultsShape', 'gdanalmat must be a nonempty cell/cellstr array.');
            end
            gdanalmat = gdanalmat(:);
            nExpected = NMRunTools.cvResultsStreamCount(inp);
            if numel(gdanalmat) < nExpected
                error('NMRunTools:badCVResultsShape', 'gdanalmat has %d stream file(s), expected %d.', numel(gdanalmat), nExpected);
            end
            present = false(nExpected,1);
            for ss = 1:nExpected
                item = gdanalmat{ss};
                if ischar(item) || isstring(item)
                    fpath = strtrim(char(string(item)));
                    present(ss) = exist(fpath,'file') == 2;
                    if present(ss), NMRunTools.assertCVResultsFileReadable(fpath); end
                end
            end
            nMissing = nnz(~present);
            if requireComplete && nMissing > 0
                error('NMRunTools:incompleteCVResults', 'CVresults is incomplete for %d/%d expected stream(s) (%s).', nMissing, nExpected, char(string(source)));
            end
            report = struct('ok', nMissing == 0, 'source',source, 'analysisEntryPoint','results', ...
                'nExpectedStreams',nExpected, 'presentStreams',nnz(present), 'missingStreams',nMissing, ...
                'streamPresent',present);
        end

        function v = fieldOr(s, field, defaultValue)
            v = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end
    end
end
