classdef NMAnalysisManagerTools
% NMAnalysisManagerTools
% -------------------------------------------------------------------------
% Public API for NM.analysis lifecycle management.  This is the non-UI
% counterpart of the legacy nk_InitAnalysisPrep analysis manager.  Scripts
% and browser callbacks must call this API instead of mutating NM.analysis,
% NM.TrainParam or NM.cv directly.
% -------------------------------------------------------------------------

    methods (Static)
        function spec = defaultCreateSpec()
            % defaultCreateSpec  Return defaults for public analysis creation.
            %
            %   spec = NMAnalysisManagerTools.defaultCreateSpec() returns the
            %   scalar struct accepted by createAnalysis. It is read-only and
            %   does not alter NM or create output folders.

            spec = struct('id','API_ANALYSIS', 'description',{{'API-created analysis'}}, ...
                'parentdir',pwd, 'analdim',[], 'overwrite','complete_reset');
        end

        function state = listAnalyses(NM)
            % listAnalyses  Summarize NM.analysis entries for API and browser UI callers.
            %
            %   state = NMAnalysisManagerTools.listAnalyses(NM) returns counts,
            %   indices, identifiers, descriptions, root directories and status
            %   values. It does not modify NM.

            state = struct('count',0,'indices',[],'ids',{{}},'descriptions',{{}},'rootdirs',{{}},'rootExists',[],'status',[]);
            if ~isstruct(NM) || ~isfield(NM,'analysis') || isempty(NM.analysis) || ~iscell(NM.analysis), return; end
            state.count = numel(NM.analysis);
            state.indices = 1:state.count;
            state.ids = cell(1,state.count);
            state.descriptions = cell(1,state.count);
            state.rootdirs = cell(1,state.count);
            state.rootExists = false(1,state.count);
            state.status = nan(1,state.count);
            for i = 1:state.count
                A = NM.analysis{i};
                state.ids{i} = NMAnalysisManagerTools.scalarText( ...
                    NMAnalysisManagerTools.fieldOr(A,'id',sprintf('Analysis_%d',i)), sprintf('Analysis_%d',i));
                state.descriptions{i} = NMAnalysisManagerTools.descriptionText( ...
                    NMAnalysisManagerTools.fieldOr(A,'desc',''));
                state.rootdirs{i} = NMAnalysisManagerTools.scalarText( ...
                    NMAnalysisManagerTools.fieldOr(A,'rootdir',''), '');
                state.rootExists(i) = ~isempty(state.rootdirs{i}) && exist(state.rootdirs{i},'dir') == 7;
                if isstruct(A) && isfield(A,'status') && ~isempty(A.status)
                    state.status(i) = NMAnalysisManagerTools.scalarDouble(A.status, NaN);
                end
            end
        end

        function mask = trainedRootMask(list)
            mask = isfinite(list.status) & list.status >= 1 & list.rootExists;
        end

        function out = inspectAnalysis(NM, analind, spec)
            % inspectAnalysis  Return a read-only analysis inspection payload.
            %
            %   out = NMAnalysisManagerTools.inspectAnalysis(NM, analind, spec)
            %   summarizes one analysis for browser/API inspection without
            %   modifying NM. The payload contains a compact configuration
            %   summary, a lightweight non-interactive canvas model, and result
            %   availability flags for downstream viewer actions.
            %
            %   This method deliberately does not move feature matrices or other
            %   large training containers across the browser bridge.

            if nargin < 3 || isempty(spec), spec = struct(); end %#ok<NASGU>
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            A = NM.analysis{analind};
            out = struct();
            out.ok = true;
            out.message = sprintf('Analysis %d inspected.', analind);
            out.analysisIndex = analind;
            out.summary = NMAnalysisManagerTools.analysisSummary(NM, A, analind);
            out.configuration = NMAnalysisManagerTools.configurationSummary(A);
            out.results = NMAnalysisManagerTools.resultsSummary(A);
            out.canvas = NMAnalysisManagerTools.analysisCanvasPayload(NM, A);
            if exist('NMRuntimeActionTools','class') == 8
                out.runtime = NMRuntimeActionTools.runtimeState(NM, struct('analysisIndex',analind,'entryPoint','analysis_manager'));
            else
                out.runtime = struct('ok',false,'message','NMRuntimeActionTools is not available.');
            end
        end

        function out = inspectCanvasNodeDetail(NM, analind, nodeId)
            % Reuse the training-template detail authority for one snapshot node.
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            NMlite = NMAnalysisManagerTools.lightweightNMFromAnalysis(NM, NM.analysis{analind});
            orch = NMTrainTemplateOrchestrator.fromNM(NMlite, 1, struct('NMAppFastChildOpen',true));
            state = orch.menuState(struct('includeCanvas',true,'canvasDetailMode','summary'));
            nodes = state.canvas.nodes;
            idx = find(strcmp({nodes.id}, nodeId), 1);
            if isempty(idx)
                error('NMAnalysisManagerTools:UnknownCanvasNode', 'Unknown analysis canvas node: %s', nodeId);
            end
            detail = orch.canvasNodeDetail(nodes(idx), state, state.audit);
            out = struct('ok',true,'analysisIndex',analind,'nodeId',nodeId,'detail',detail);
        end

        function out = exportMethodsSummary(NM, analind, outputDir)
            % Export the selected analysis snapshot through the existing Methods generator.
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            if exist(outputDir,'dir') ~= 7
                error('NMAnalysisManagerTools:invalidMethodsDirectory', ...
                    'Methods-summary destination directory does not exist: %s', outputDir);
            end
            analysis = NM.analysis{analind};
            NMlite = NMAnalysisManagerTools.lightweightNMFromAnalysis(NM, analysis);
            orch = NMTrainTemplateOrchestrator.fromNM(NMlite, 1, struct());
            file = fullfile(outputDir, sprintf('NMAnalysis_%03d_MethodsSummary_%s.txt', ...
                analind, datestr(now,'yyyymmdd_HHMMSS')));
            [~, file] = nm_train_template_export_methods_summary(orch, file, struct());
            out = struct('ok',true, 'message',sprintf('Analysis %d methods summary exported.',analind), ...
                'analysisIndex',analind,'file',file);
        end

        function [NM, out] = createAnalysis(NM, spec)
            % createAnalysis  Create a NeuroMiner analysis by snapshotting the current public API template.
            %
            % [NM, out] = NMAnalysisManagerTools.createAnalysis(NM, spec)
            % creates or overwrites an NM.analysis entry, initializes its
            % output directory/log fields, and snapshots the current
            % TrainParam/CV/template state. Use this API instead of directly
            % assigning NM.analysis or calling legacy analysis managers.
            %
            % spec is a scalar struct. Common fields are:
            % id           Short analysis identifier used in the analysis
            % root-directory name. Required after defaults.
            % description  Character vector or cellstr description.
            % parentdir    Existing or creatable parent directory for
            % analysis outputs. Default: pwd.
            % analdim      Optional target analysis index. If empty, the
            % next available index is used.
            % overwrite    Use 'complete_reset', 'reset' or 'overwrite'
            % to replace an existing analysis at analdim.
            %
            % out.analysisIndex is the created analysis index. The analysis
            % status is initialized to 0; call NMRunTools.trainAnalysis to run
            % model training.
            %
            % Example:
            % spec = struct('id','API_TEST','description',{{'API test'}}, ...
            % 'parentdir','D:\NM_API_Tests');
            % [NM, out] = NMAnalysisManagerTools.createAnalysis(NM, spec);
            %
            % spec.analdim: supplies the analdim value in the public API/import specification.
            % spec.description: provides the human-readable action description embedded in generated scripts or reports.
            % spec.id: supplies the id value in the public API/import specification.
            % spec.parentdir: supplies the parentdir value in the public API/import specification.

            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(spec), spec = struct(); end
            NMStatusGuardTools.assertScientificTrainingData(NM);
            readiness = NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMAnalysisManagerTools.createAnalysis');
            if ~readiness.setup_ok
                error('NMAnalysisManagerTools:incompleteTrainingConfiguration', ...
                    'Analysis initialization blocked: %s', strjoin(cellstr(readiness.paramstr), '; '));
            end
            spec = NMAnalysisManagerTools.normalizeCreateSpec(NM, spec);
            NM = NMAnalysisManagerTools.ensureProjectDefaults(NM);
            idx = spec.analdim;
            if isempty(idx)
                idx = NMAnalysisManagerTools.nextAnalysisIndex(NM);
            end
            replacingExisting = isfield(NM,'analysis') && iscell(NM.analysis) && ...
                numel(NM.analysis) >= idx && ~isempty(NM.analysis{idx});
            if ~isfield(NM,'analysis') || isempty(NM.analysis) || ~iscell(NM.analysis)
                NM.analysis = cell(1,idx);
            elseif numel(NM.analysis) < idx
                NM.analysis{idx} = [];
            end

            NM = NMAnalysisManagerTools.ensureRuntimeDefaults(NM);

            analysis = struct();
            analysis.id = spec.id;
            analysis.desc = spec.description;
            analysis.parentdir = spec.parentdir;
            analysis.rootdir = fullfile(analysis.parentdir, sprintf('NM_ID%s_A%d_%s', NM.id, idx, analysis.id));
            if ~exist(analysis.rootdir,'dir'), mkdir(analysis.rootdir); end
            analysis = NMAnalysisManagerTools.snapshotCurrentTemplate(NM, analysis);
            analysis.status = 0;
            analysis = NMAnalysisManagerTools.initLogFileIfAvailable(NM, analysis);
            NM.analysis{idx} = analysis;
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);

            if replacingExisting
                msg = sprintf('Analysis %d overwritten from current NM template. Output directory: %s', idx, analysis.rootdir);
            else
                msg = sprintf('Analysis %d created from current NM template. Output directory: %s', idx, analysis.rootdir);
            end
            out = struct('ok',true, 'message',msg, ...
                'analysisIndex',idx, 'analysis',analysis, 'overwritten',replacingExisting, ...
                'rootdir',analysis.rootdir);
        end

        function [NM, out] = resetParameters(NM, analind, spec)
            % resetParameters  Reset an existing analysis snapshot from the current template.
            %
            % [NM,out] = NMAnalysisManagerTools.resetParameters(NM, analind, spec)
            % resets the selected NM.analysis entry through the public
            % lifecycle API. Scripts and browser callbacks should call this
            % method instead of editing NM.analysis directly.
            %
            % spec.resetMode: controls the legacy-compatible reset semantics:
            % 'parameter_reset'  Keep existing non-parameter fields and
            % replace params/meta/status from the
            % current NM template. This mirrors the
            % legacy "parameter reset" option and is
            % the default for backwards compatibility.
            % 'complete_reset'   Clear the analysis object first, preserve
            % id/description/path identity, then
            % snapshot the current NM template. This
            % mirrors the safer legacy "complete reset"
            % operation used by the browser button.
            %
            % spec.mode: supplies the mode value in the public API/import specification.

            if nargin < 3 || isempty(spec), spec = struct(); end
            if exist('NMStatusGuardTools','class') == 8
                NMStatusGuardTools.assertTrainingConfigurationMode(NM, 'NMAnalysisManagerTools.resetParameters');
            end
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            analysis0 = NM.analysis{analind};
            storedRoot = char(string(NMAnalysisManagerTools.fieldOr(analysis0,'rootdir','')));
            if isempty(storedRoot)
                error('NMAnalysisManagerTools:missingAnalysisRoot', ...
                    ['Analysis %d cannot be reset because it has no stored analysis root. ' ...
                     'Relink the analysis root before resetting parameters.'], analind);
            end
            if exist(storedRoot,'dir') ~= 7
                error('NMAnalysisManagerTools:staleAnalysisRoot', ...
                    ['Analysis %d cannot be reset because its stored analysis root does not exist:\n%s\n' ...
                     'Relink the analysis root before resetting parameters.'], analind, storedRoot);
            end
            resetMode = 'parameter_reset';
            if isstruct(spec) && isfield(spec,'resetMode') && ~isempty(spec.resetMode)
                resetMode = lower(strtrim(char(string(spec.resetMode))));
            elseif isstruct(spec) && isfield(spec,'mode') && ~isempty(spec.mode)
                resetMode = lower(strtrim(char(string(spec.mode))));
            end
            if any(strcmp(resetMode, {'complete','complete_reset','reset','overwrite'}))
                resetMode = 'complete_reset';
            elseif any(strcmp(resetMode, {'parameter','parameters','parameter_reset'}))
                resetMode = 'parameter_reset';
            else
                error('NMAnalysisManagerTools:badResetMode', 'Unsupported resetMode ''%s''.', resetMode);
            end

            NM = NMAnalysisManagerTools.ensureRuntimeDefaults(NM);
            if strcmp(resetMode, 'complete_reset')
                analysis = struct();
                analysis.id = NMAnalysisManagerTools.fieldOr(analysis0,'id',sprintf('Analysis_%d',analind));
                analysis.desc = NMAnalysisManagerTools.fieldOr(analysis0,'desc',{sprintf('Analysis %d',analind)});
                analysis.parentdir = NMAnalysisManagerTools.fieldOr(analysis0,'parentdir',pwd);
                analysis.rootdir = NMAnalysisManagerTools.fieldOr(analysis0,'rootdir','');
                if isempty(analysis.rootdir)
                    error('NMAnalysisManagerTools:missingAnalysisRoot', ...
                        'Analysis %d has no root directory. Relink the analysis root before resetting parameters.', analind);
                end
            else
                analysis = analysis0;
            end
            analysis = NMAnalysisManagerTools.snapshotCurrentTemplate(NM, analysis);
            analysis.status = 0;
            analysis = NMAnalysisManagerTools.initLogFileIfAvailable(NM, analysis);
            NM.analysis{analind} = analysis;
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);
            out = struct('ok',true, 'message',sprintf('Analysis %d reset from current NM template using %s.', analind, resetMode), ...
                'analysisIndex',analind, 'resetMode',resetMode);
        end

        function [NM, out] = restoreTemplateFromAnalysis(NM, analind, spec)
            % restoreTemplateFromAnalysis  Restore the active NM TrainParam/CV template from an analysis snapshot.
            %
            %   [NM,out] = NMAnalysisManagerTools.restoreTemplateFromAnalysis(...) performs the
            %   named analysis-manager operation through the controlled API.
            %   The method returns an updated NM struct and a scalar report;
            %   callers should not mutate NM.analysis directly.

            if nargin < 3, spec = struct(); end %#ok<NASGU>
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            A = NM.analysis{analind};
            if ~isfield(A,'params') || ~isstruct(A.params)
                error('NMAnalysisManagerTools:missingAnalysisParams', 'Analysis %d does not contain a params snapshot.', analind);
            end
            if isfield(A.params,'TrainParam'), NM.TrainParam = A.params.TrainParam; end
            if isfield(A.params,'cv'), NM.cv = A.params.cv; end
            out = struct('ok',true, 'message',sprintf('Current NM template restored from analysis %d.', analind), 'analysisIndex',analind);
        end

        function [NM, out] = deleteAnalyses(NM, analind, spec)
            % deleteAnalyses  Delete one or more NM.analysis entries through the public lifecycle API.
            %
            % [NM,out] = NMAnalysisManagerTools.deleteAnalyses(...) performs the
            % named analysis-manager operation through the controlled API.
            % The method returns an updated NM struct and a scalar report;
            % callers should not mutate NM.analysis directly.
            %
            % spec.wipe: supplies the wipe value in the public API/import specification.

            if nargin < 3, spec = struct(); end
            wipe = false;
            if isstruct(spec) && isfield(spec,'wipe') && ~isempty(spec.wipe), wipe = logical(spec.wipe); end
            if isempty(analind), error('NMAnalysisManagerTools:missingAnalysisIndex', 'No analysis index specified.'); end
            analind = unique(round(double(analind(:)')));
            for i = 1:numel(analind), NMAnalysisManagerTools.assertAnalysisIndex(NM, analind(i)); end
            % NM2 SYNTH children are owned by their experiment. Generic
            % deletion cannot retire a managed child independently.
            % nm2-allow: Older NM analyses lack the NM2 SYNTH registry.
            if isfield(NM,'SYNTH')
                for x=1:numel(NM.SYNTH.analysis)
                    assert(~any(ismember(analind,NM.SYNTH.analysis{x}.analysisIndices)), ...
                        'NMAnalysisManagerTools:managedSYNTHChild', ...
                        'Delete managed SYNTH children through the SYNTH Coordinator.');
                end
            end
            if wipe
                for i = 1:numel(analind)
                    rd = NMAnalysisManagerTools.fieldOr(NM.analysis{analind(i)}, 'rootdir', '');
                    if ~isempty(rd) && exist(rd,'dir') == 7, rmdir(rd,'s'); end
                end
            end
            NM.analysis(sort(analind,'descend')) = [];
            if isempty(NM.analysis), NM = rmfield(NM,'analysis'); end
            % Analysis Manager is the single owner of analysis-index rebasing.
            % nm2-allow: Older NM analyses lack the NM2 SYNTH registry.
            if isfield(NM,'SYNTH')
                for x=1:numel(NM.SYNTH.analysis)
                    indices=NM.SYNTH.analysis{x}.analysisIndices;
                    NM.SYNTH.analysis{x}.analysisIndices=indices- ...
                        arrayfun(@(i)nnz(analind<i),indices);
                end
            end
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);
            out = struct('ok',true, 'message',sprintf('%d analysis entry/entries deleted.', numel(analind)), 'analysisIndex',analind);
        end

        function [NM, out] = updatePathsAndDescriptors(NM, analind, spec)
            % updatePathsAndDescriptors  Update user-facing analysis description and output paths.
            %
            % [NM,out] = NMAnalysisManagerTools.updatePathsAndDescriptors(...) performs the
            % named analysis-manager operation through the controlled API.
            % The method returns an updated NM struct and a scalar report;
            % callers should not mutate NM.analysis directly.
            %
            % spec.description: provides the human-readable action description embedded in generated scripts or reports.
            % spec.parentdir: supplies the parentdir value in the public API/import specification.

            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            if nargin < 3 || isempty(spec), spec = struct(); end
            A = NM.analysis{analind};
            if isfield(spec,'description') && ~isempty(spec.description), A.desc = NMAnalysisManagerTools.normalizeDescription(spec.description); end
            if isfield(spec,'parentdir') && ~isempty(spec.parentdir)
                A.parentdir = char(string(spec.parentdir));
                if ~exist(A.parentdir,'dir'), mkdir(A.parentdir); end
                A.rootdir = fullfile(A.parentdir, sprintf('NM_ID%s_A%d_%s', NMAnalysisManagerTools.fieldOr(A.params,'id',NM.id), analind, A.id));
                if ~exist(A.rootdir,'dir'), mkdir(A.rootdir); end
                A.paramdir = fullfile(A.rootdir,'params');
                A.logfile = fullfile(A.rootdir, sprintf('NM_Analysis_%s.log', A.id));
            end
            NM.analysis{analind} = A;
            out = struct('ok',true, 'message',sprintf('Analysis %d paths/descriptors updated.', analind), 'analysisIndex',analind);
        end

        function [NM, out] = relinkAnalysisRoot(NM, analind, spec)
            % relinkAnalysisRoot  Resolve and update a relocated analysis root.
            %
            % [NM,out] = NMAnalysisManagerTools.relinkAnalysisRoot(NM, analind, spec)
            % accepts either the exact relocated analysis directory or its immediate
            % parent. selectionKind='auto' asks NMAnalysisPathTools to inspect the
            % selection and reject ambiguous matches. Explicit 'root' and 'parent'
            % modes remain available to programmatic callers.
            %
            % spec.newRootDir: selected directory supplied by browser/API callers.
            % spec.newParentDir: compatibility alias for the selected directory.
            % spec.selectionKind: 'auto' (default), 'root', 'parent', or 'bulk_parent' (index vector).

            if nargin < 3 || isempty(spec), spec = struct(); end
            selectedDir = NMAnalysisManagerTools.fieldOr(spec,'newRootDir','');
            if isempty(selectedDir)
                selectedDir = NMAnalysisManagerTools.fieldOr(spec,'newParentDir','');
            end
            selectionKind = NMAnalysisManagerTools.fieldOr(spec,'selectionKind','auto');
            if exist('NMAnalysisPathTools','class') ~= 8
                error('NMAnalysisManagerTools:missingAnalysisPathTools', ...
                    'NMAnalysisPathTools is required for portable analysis-root relinking.');
            end
            if strcmp(selectionKind,'bulk_parent')
                [NM, out] = NMAnalysisPathTools.relinkAnalysisRoots(NM, analind, selectedDir);
                return;
            end
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            [NM, out] = NMAnalysisPathTools.relinkAnalysisRoot(NM, analind, selectedDir, selectionKind);
        end

        function out = openResultsViewer(NM, analind, spec)
            % openResultsViewer  Open the legacy MATLAB NM Results Viewer for one analysis.
            %
            %   out = NMAnalysisManagerTools.openResultsViewer(NM, analind, spec)
            %   validates that the selected analysis exists, has completed
            %   training, and that NM_Results_Viewer is available on the MATLAB
            %   path. It then launches the existing MATLAB results GUI with
            %   NM and AnalysisIndex name-value inputs.
            %
            %   The method does not modify NM and does not replace the legacy
            %   Results Viewer internals.

            if nargin < 3 || isempty(spec), spec = struct(); end %#ok<NASGU>
            NMAnalysisManagerTools.assertAnalysisIndex(NM, analind);
            A = NM.analysis{analind};
            if ~isfield(A,'status') || isempty(A.status) || double(A.status) < 1
                error('NMAnalysisManagerTools:analysisNotCompleted', 'Analysis %d is not completed. Results Viewer requires status >= 1.', analind);
            end
            if exist('NM_Results_Viewer','file') ~= 2
                error('NMAnalysisManagerTools:missingResultsViewer', 'NM_Results_Viewer.m is not available on the MATLAB path.');
            end
            NM_Results_Viewer('Analysis', analind, 'NM', NM);
            out = struct('ok',true, 'message',sprintf('NM Results Viewer opened for analysis %d.', analind), ...
                'analysisIndex',analind);
        end

        function NM = reconcileOOCVAnalysisUse(NM)
            % reconcileOOCVAnalysisUse  Synchronize persisted OOCV analysis-use state with retained analysis results.
            %
            % NM.OOCV{o}.analysis_used is true exactly when at least one retained
            % NM.analysis{a}.OOCV{o} result exists. This method is the migration/
            % reconciliation authority used after analysis ownership is removed or
            % when legacy OOCV containers predate the persisted flag.
            if ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV), return; end
            for o = 1:numel(NM.OOCV)
                if isempty(NM.OOCV{o}) || ~isstruct(NM.OOCV{o}), continue; end
                NM.OOCV{o}.analysis_used = NMAnalysisManagerTools.hasRetainedOOCVResult(NM, o);
            end
        end

        function used = oocvAnalysisUsed(NM, oocvind)
            % oocvAnalysisUsed  Return the persisted use state, deriving legacy missing state from retained results.
            oocvind = round(double(oocvind));
            used = false;
            if ~isscalar(oocvind) || ~isfinite(oocvind) || oocvind < 1 || ...
                    ~isstruct(NM) || ~isfield(NM,'OOCV') || ~iscell(NM.OOCV) || ...
                    numel(NM.OOCV) < oocvind || isempty(NM.OOCV{oocvind}) || ~isstruct(NM.OOCV{oocvind})
                return;
            end
            D = NM.OOCV{oocvind};
            if isfield(D,'analysis_used') && isscalar(D.analysis_used) && ...
                    (islogical(D.analysis_used) || isnumeric(D.analysis_used)) && isfinite(double(D.analysis_used))
                used = logical(D.analysis_used);
                return;
            end
            used = NMAnalysisManagerTools.hasRetainedOOCVResult(NM, oocvind);
        end

        function [NM, out] = activateApplicationMode(NM, spec)
            % activateApplicationMode  Lock completed training analyses and enable OOCV/application import.
            %
            %   [NM, out] = NMAnalysisManagerTools.activateApplicationMode(NM, spec)
            %   switches the project into application/OOCV mode by setting
            %   NM.defs.analyses_locked = true after validating that training
            %   import has been finalized and at least one analysis is completed.
            %
            %   spec is currently reserved for future options and may be empty.
            %
            %   This method does not import OOCV data and does not train models.
            %   It only performs the guarded mode transition required before
            %   NMDataIOAPITools.importOOCVMatrix/importOOCVImages and
            %   NMRunTools.applyOOCV.
            %
            %   out.ok is true on success; out.analysesLocked indicates the new
            %   state. Errors are raised if training import is not finalized or
            %   no completed analysis is available.
            %
            %   Example:
            %       [NM, out] = NMAnalysisManagerTools.activateApplicationMode(NM, struct());

            if nargin < 2 || isempty(spec), spec = struct(); end %#ok<NASGU>
            if exist('NMStatusGuardTools','class') ~= 8
                error('NMAnalysisManagerTools:missingNMStatusGuardTools', ...
                    'NMStatusGuardTools is required to activate application/OOCV mode safely.');
            end
            NMStatusGuardTools.assertTrainingImportFinalized(NM, 'NMAnalysisManagerTools.activateApplicationMode');
            NMStatusGuardTools.assertCompletedAnalysisAvailable(NM, 'NMAnalysisManagerTools.activateApplicationMode');
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            NM.defs.analyses_locked = true;
            NM = NMAnalysisManagerTools.reconcileOOCVAnalysisUse(NM);
            out = struct('ok',true, 'message','Application/OOCV mode activated after detecting at least one completed analysis.', ...
                'analysesLocked',true, 'hasCompletedAnalysis',true);
        end
    end

    methods (Static, Access = private)
        function tf = hasRetainedOOCVResult(NM, oocvind)
            tf = false;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis), return; end
            for a = 1:numel(NM.analysis)
                A = NM.analysis{a};
                if isstruct(A) && isfield(A,'OOCV') && iscell(A.OOCV) && ...
                        numel(A.OOCV) >= oocvind && ~isempty(A.OOCV{oocvind})
                    tf = true;
                    return;
                end
            end
        end

        function spec = normalizeCreateSpec(NM, spec)
            d = NMAnalysisManagerTools.defaultCreateSpec();
            spec = NMAnalysisManagerTools.mergeStruct(d, spec);
            spec.id = char(string(spec.id));
            spec.id = regexprep(spec.id, '[^A-Za-z0-9_\-.]', '');
            if isempty(spec.id), error('NMAnalysisManagerTools:missingID', 'Analysis identifier is required.'); end
            spec.description = NMAnalysisManagerTools.normalizeDescription(spec.description);
            spec.parentdir = char(string(spec.parentdir));
            if isempty(spec.parentdir), error('NMAnalysisManagerTools:missingParentdir', 'Analysis parent directory is required.'); end
            if ~exist(spec.parentdir,'dir'), mkdir(spec.parentdir); end
            if isfield(spec,'analdim') && ~isempty(spec.analdim)
                spec.analdim = max(1, round(double(spec.analdim)));
                maxAllowed = NMAnalysisManagerTools.nextAnalysisIndex(NM);
                if spec.analdim > maxAllowed
                    error('NMAnalysisManagerTools:analysisIndexGap', ...
                        'Target analysis index %d exceeds the maximum allowed index %d. Larger indices would create gaps in NM.analysis.', ...
                        spec.analdim, maxAllowed);
                end
            else
                spec.analdim = [];
            end
            if ~isempty(spec.analdim) && isfield(NM,'analysis') && iscell(NM.analysis) && numel(NM.analysis) >= spec.analdim && ~isempty(NM.analysis{spec.analdim})
                ow = lower(strtrim(char(string(spec.overwrite))));
                if ~any(strcmp(ow, {'complete_reset','reset','overwrite'}))
                    error('NMAnalysisManagerTools:analysisExists', 'Analysis %d already exists. Use overwrite=''complete_reset'' to replace it.', spec.analdim);
                end
            end
        end

        function desc = normalizeDescription(desc)
            if isempty(desc), error('NMAnalysisManagerTools:missingDescription', 'Analysis description is required.'); end
            if ischar(desc) || isstring(desc), desc = cellstr(string(desc)); end
            if ~iscell(desc), desc = {desc}; end
            desc = cellfun(@(x) strtrim(char(string(x))), desc(:)', 'UniformOutput', false);
            desc = desc(~cellfun(@isempty, desc));
            if isempty(desc), error('NMAnalysisManagerTools:missingDescription', 'Analysis description is required.'); end
        end

        function NM = ensureProjectDefaults(NM)
            if ~isfield(NM,'id') || isempty(NM.id), NM.id = genID; end
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            if ~isfield(NM.defs,'NM_ver') || isempty(NM.defs.NM_ver), NM.defs.NM_ver = 'NM modular API'; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), error('NMAnalysisManagerTools:missingTrainParam', 'Current NM template has no TrainParam. Configure the training template first.'); end
            if ~isfield(NM,'cv') || isempty(NM.cv), error('NMAnalysisManagerTools:missingCV', 'Current NM template has no CV structure. Configure/build CV first.'); end
            if ~isfield(NM,'datadescriptor') || isempty(NM.datadescriptor), error('NMAnalysisManagerTools:missingDataDescriptor', 'Current NM has no datadescriptor. Import data first.'); end
        end

        function idx = nextAnalysisIndex(NM)
            idx = 1;
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis), idx = numel(NM.analysis) + 1; end
        end

        function analysis = snapshotCurrentTemplate(NM, analysis)
            % New token for every initialization/reset; unchanged while resuming.
            analysis.init_token = char(java.util.UUID.randomUUID());
            analysis.params = struct();
            analysis.params.TrainParam = NM.TrainParam;
            analysis.params.datadescriptor = NM.datadescriptor;
            analysis.params.cv = NM.cv;
            analysis.params.id = NM.id;
            analysis.params.label = NMAnalysisManagerTools.labelSnapshot(NM);
            analysis.meta = NMAnalysisManagerTools.metaSnapshot(NM);
            if isfield(NM,'C'), analysis.C = NM.C; end
        end

        function label = labelSnapshot(NM)
            % Purpose: Snapshot the target/label contract persisted with a newly created analysis.
            % Syntax: label = NMAnalysisManagerTools.labelSnapshot(NM)
            % Inputs: NM is the active workspace whose native or alternative-label configuration is being frozen.
            % Outputs: label is the analysis-local label struct stored under analysis.params.label.
            % Authority and flow: Native target values/names come from NM.label, NM.modeflag and NM.labelnames; an enabled TrainParam.LABEL block is the sole authority for an alternative-label analysis.
            % Scientific/state contract: Native target names are copied from canonical NM.labelnames. DataIO editing expressions such as input_settings.label_edit are operational metadata and are never promoted to scientific target identity.
            % Invariants: Alternative-label and native-label naming paths remain distinct; labelnames preserve canonical target order; a missing native name remains unresolved rather than inferred from unrelated metadata.
            % Materialization and performance: Metadata-only O(number of target names); reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices, and creates no feature-scale arrays. Safe on analysis-management paths.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; metadata-only analysis-management work and safe on interactive metadata paths; it is not a retained renderer path.
            % Failure semantics: Missing optional label metadata yields the established placeholders/default mode; malformed structures are not repaired from DataIO descriptors.
            % Side effects: None; NM is not mutated.
            % Consumers and dependencies: Analysis creation/snapshot code; downstream Results Viewer target-name resolution.
            label = struct('label',[], 'modeflag','classification', 'labelname','?', 'labelnames',{{}}, 'altlabelflag',0);
            if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'LABEL') && isstruct(NM.TrainParam.LABEL) && isfield(NM.TrainParam.LABEL,'flag') && NM.TrainParam.LABEL.flag
                L = NM.TrainParam.LABEL;
                label.label = NMAnalysisManagerTools.fieldOr(L,'newlabel',[]);
                label.modeflag = NMAnalysisManagerTools.fieldOr(L,'newmode','classification');
                label.altlabelflag = NMAnalysisManagerTools.fieldOr(L,'flag',1);
                label.labelname = NMAnalysisManagerTools.fieldOr(L,'newlabelname','?');
                if strcmp(label.modeflag,'classification'), label.altgroupnames = NMAnalysisManagerTools.fieldOr(L,'newgroupnames',{}); end
            else
                label.label = NMAnalysisManagerTools.fieldOr(NM,'label',[]);
                label.modeflag = NMAnalysisManagerTools.fieldOr(NM,'modeflag','classification');
                label.labelnames = NMAnalysisManagerTools.defaultLabelNames(NM);
                label.labelname = NMAnalysisManagerTools.defaultLabelName(label.labelnames);
                if strcmp(label.modeflag,'classification'), label.altgroupnames = NMAnalysisManagerTools.fieldOr(NM,'groupnames',{}); end
            end
        end

        function names = defaultLabelNames(NM)
            % Purpose: Return canonical native target names from the workspace.
            % Syntax: names = NMAnalysisManagerTools.defaultLabelNames(NM)
            % Inputs: NM is the active workspace.
            % Outputs: names is a cell array projected only from NM.labelnames, or empty when unavailable.
            % Authority and flow: NM.labelnames is the native target-name authority; no DataIO descriptor or label-edit expression is consulted.
            % Scientific/state contract: This helper exposes names only and does not infer target identity.
            % Invariants: Stored order is preserved exactly.
            % Materialization and performance: Metadata-only O(number of names); no file/resource reads or feature-scale work.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; metadata-only analysis-management work and safe on interactive metadata paths; it is not a retained renderer path.
            % Failure semantics: Absent/empty NM.labelnames returns {}.
            % Side effects: None.
            % Consumers and dependencies: labelSnapshot and analysisLabelName.
            names = {};
            if isstruct(NM) && isfield(NM,'labelnames') && ~isempty(NM.labelnames)
                names = cellstr(string(NM.labelnames));
            end
        end

        function name = defaultLabelName(names)
            % Purpose: Project a single canonical native target name when exactly one target name exists.
            % Syntax: name = NMAnalysisManagerTools.defaultLabelName(names)
            % Inputs: names is the canonical target-name cell/string sequence.
            % Outputs: name is the trimmed sole name or '?' when the sequence is empty, multi-target, or blank.
            % Authority and flow: Consumes names already resolved by defaultLabelNames; performs no independent metadata lookup.
            % Scientific/state contract: Multi-target identity must remain indexed and is therefore not collapsed to one arbitrary labelname.
            % Invariants: Never derives a name from DataIO label-edit state.
            % Materialization and performance: O(1) metadata normalization; no file/resource reads or large allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; metadata-only analysis-management work and safe on interactive metadata paths; it is not a retained renderer path.
            % Failure semantics: Invalid/empty naming input leaves the established '?' placeholder.
            % Side effects: None.
            % Consumers and dependencies: labelSnapshot.
            name = '?';
            if nargin < 1 || isempty(names), return; end
            if numel(names)==1
                candidate=strtrim(char(string(names{1})));
                if ~isempty(candidate), name=candidate; end
            end
        end

        function meta = metaSnapshot(NM)
            meta = struct();
            meta.TIME = datestr(now);
            try
                meta.USER = char(java.lang.System.getProperty('user.name'));
                meta.OS.name = char(java.lang.System.getProperty('os.name'));
                meta.OS.version = char(java.lang.System.getProperty('os.version'));
                meta.OS.arch = char(java.lang.System.getProperty('os.arch'));
            catch
                meta.USER = 'NA';
            end
            try, meta.MATLAB.ver = ver; catch, meta.MATLAB.ver = []; end
            try, meta.NM.ver = NM.defs.NM_ver; catch, meta.NM.ver = 'NA'; end
        end

        function analysis = initLogFileIfAvailable(NM, analysis)
            if exist('nk_NMLogFileManager','file') == 2
                [~, analysis] = nk_NMLogFileManager('init', NM, analysis);
            else
                analysis.paramdir = fullfile(analysis.rootdir,'params');
                if ~exist(analysis.paramdir,'dir'), mkdir(analysis.paramdir); end
                analysis.paramfile = fullfile(analysis.paramdir, sprintf('NM_Analysis_%s_params.mat', analysis.id));
                analysis.logfile = fullfile(analysis.rootdir, sprintf('NM_Analysis_%s.log', analysis.id));
            end
        end

        function NM = ensureRuntimeDefaults(NM)
            if exist('NMSAVTools','class') ~= 8
                error('NMAnalysisManagerTools:missingNMSAVTools', 'NMSAVTools is required to ensure TrainParam.SAV and TrainParam.verbosity before analysis snapshotting.');
            end
            needsSav = ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam) || ...
                ~isfield(NM.TrainParam,'SAV') || ~isstruct(NM.TrainParam.SAV) || ...
                ~isfield(NM.TrainParam.SAV,'savemodel') || ...
                ~isfield(NM.TrainParam.SAV,'matname') || isempty(strtrim(char(string(NM.TrainParam.SAV.matname)))) || ...
                ~isfield(NM.TrainParam,'verbosity') || isempty(NM.TrainParam.verbosity);
            if needsSav
                [NM, ~, report] = NMSAVTools.configure(NM, 'savMatName', NMSAVTools.defaultMatName(NM));
                if isfield(report,'ok') && ~report.ok
                    error('NMAnalysisManagerTools:savDefaultsFailed', 'Failed to apply TrainParam.SAV/verbosity defaults: %s', NMAnalysisManagerTools.reportText(report));
                end
            end
            auxSpec = struct('varind', NMAnalysisManagerTools.activeVarIndex(NM), ...
                'fusionFlag', NMAnalysisManagerTools.fusionFlag(NM));
            if NMAnalysisManagerTools.runtimeAuxiliaryDefaultsComplete(NM, auxSpec.varind, auxSpec.fusionFlag)
                return;
            end
            if exist('NMTrainTemplateAPITools','class') ~= 8
                error('NMAnalysisManagerTools:missingNMTrainTemplateAPITools', ...
                    'NMTrainTemplateAPITools is required to ensure RFE/VIS/MLI/OOCV runtime defaults before analysis snapshotting.');
            end
            [NM, auxOut] = NMTrainTemplateAPITools.configureAuxiliaryDefaults(NM, auxSpec); %#ok<ASGLU>
        end

        function tf = runtimeAuxiliaryDefaultsComplete(NM, varind, fusionFlag)
            % Fast path for create/reset after restoring an existing analysis
            % template. Re-running configureAuxiliaryDefaults needlessly
            % rebuilds RFE/VIS/MLI/OOCV branches that are already materialized
            % in TrainParam and makes browser analysis initialization sluggish.
            tf = false;
            if nargin < 2 || isempty(varind), varind = 1; end
            if nargin < 3 || isempty(fusionFlag), fusionFlag = 0; end
            if ~isstruct(NM) || ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if round(double(fusionFlag)) == 3
                if ~isfield(TP,'STRAT') || ~iscell(TP.STRAT) || numel(TP.STRAT) < varind || ...
                        isempty(TP.STRAT{varind}) || ~isstruct(TP.STRAT{varind})
                    return;
                end
                S = TP.STRAT{varind};
                hasRFE = isfield(S,'RFE') && isstruct(S.RFE);
                hasVIS = isfield(S,'VIS') && isstruct(S.VIS);
                hasMLI = isfield(S,'MLI') && isstruct(S.MLI);
            else
                hasRFE = isfield(TP,'RFE') && isstruct(TP.RFE);
                hasVIS = isfield(TP,'VIS') && ...
                    ((iscell(TP.VIS) && numel(TP.VIS) >= varind && isstruct(TP.VIS{varind})) || isstruct(TP.VIS));
                hasMLI = isfield(TP,'MLI') && isstruct(TP.MLI);
            end
            hasOOCV = isfield(TP,'OOCV') && isstruct(TP.OOCV);
            tf = hasRFE && hasVIS && hasMLI && hasOOCV;
        end

        function v = activeVarIndex(NM)
            v = 1;
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'ActiveModality') && ~isempty(NM.TrainParam.ActiveModality)
                v = max(1, round(double(NM.TrainParam.ActiveModality)));
            end
        end

        function f = fusionFlag(NM)
            f = 0;
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'FUSION') && isstruct(NM.TrainParam.FUSION) && ...
                    isfield(NM.TrainParam.FUSION,'flag') && ~isempty(NM.TrainParam.FUSION.flag)
                f = round(double(NM.TrainParam.FUSION.flag));
            end
        end

        function summary = analysisSummary(NM, A, analind)
            summary = struct();
            summary.index = analind;
            summary.id = NMAnalysisManagerTools.fieldOr(A,'id',sprintf('Analysis_%d',analind));
            summary.description = NMAnalysisManagerTools.descriptionText(NMAnalysisManagerTools.fieldOr(A,'desc',''));
            summary.status = NMAnalysisManagerTools.fieldOr(A,'status',NaN);
            summary.statusLabel = NMAnalysisManagerTools.statusLabel(summary.status);
            summary.parentdir = NMAnalysisManagerTools.fieldOr(A,'parentdir','');
            summary.rootdir = NMAnalysisManagerTools.fieldOr(A,'rootdir','');
            summary.paramfile = NMAnalysisManagerTools.fieldOr(A,'paramfile','');
            summary.logfile = NMAnalysisManagerTools.fieldOr(A,'logfile','');
            summary.modeflag = NMAnalysisManagerTools.analysisModeFlag(NM, A);
            summary.labelname = NMAnalysisManagerTools.analysisLabelName(NM, A);
            summary.nModalities = numel(A.params.TrainParam.FUSION.M);
        end

        function cfg = configurationSummary(A)
            cfg = struct('fusion','not configured','modalities','not available','preprocessing','not available', ...
                'machineLearning','not available','ensemble','inactive','visualization','not configured', ...
                'mli','not configured','saving','not configured');
            if ~isstruct(A) || ~isfield(A,'params') || ~isstruct(A.params) || ~isfield(A.params,'TrainParam') || ~isstruct(A.params.TrainParam)
                return;
            end
            TP = A.params.TrainParam;
            M = TP.FUSION.M;
            f = round(double(TP.FUSION.flag));
            cfg.fusion = NMAnalysisManagerTools.fusionLabel(f);
            if isfield(TP,'PREPROC')
                nBranches = numel(M);
                if f == 1, nBranches = 1; end
                cfg.preprocessing = sprintf('%d active preprocessing branch(es)', nBranches);
            end
            if isfield(TP,'SVM') || isfield(TP,'GRD')
                cfg.machineLearning = 'global learner configured';
            elseif isfield(TP,'STRAT')
                cfg.machineLearning = 'fusion-specific learners configured';
            end
            if isfield(TP,'RFE') && isstruct(TP.RFE)
                cfg.ensemble = NMAnalysisManagerTools.rfeSummary(TP.RFE);
            end
            if isfield(TP,'VIS'), cfg.visualization = 'configured'; end
            if isfield(TP,'MLI'), cfg.mli = 'configured'; end
            if isfield(TP,'SAV') && isstruct(TP.SAV)
                cfg.saving = NMAnalysisManagerTools.savSummary(TP.SAV);
            end
            cfg.modalities = sprintf('%d active; modality indices %s', numel(M), mat2str(M));
        end

        function results = resultsSummary(A)
            status = NMAnalysisManagerTools.fieldOr(A,'status',NaN);
            statusValue = NMAnalysisManagerTools.scalarDouble(status, NaN);
            completed = ~isnan(statusValue) && statusValue >= 1;
            rootdir = NMAnalysisManagerTools.fieldOr(A,'rootdir','');
            paramfile = NMAnalysisManagerTools.fieldOr(A,'paramfile','');
            logfile = NMAnalysisManagerTools.fieldOr(A,'logfile','');
            results = struct();
            results.completed = completed;
            results.status = statusValue;
            results.statusLabel = NMAnalysisManagerTools.statusLabel(status);
            results.rootExists = ~isempty(rootdir) && exist(rootdir,'dir') == 7;
            results.pathState = 'ok';
            if isempty(rootdir) || ~results.rootExists, results.pathState = 'stale'; end
            results.paramFileExists = ~isempty(paramfile) && exist(paramfile,'file') == 2;
            results.logFileExists = ~isempty(logfile) && exist(logfile,'file') == 2;
            results.hasGDdims = isfield(A,'GDdims') && ~isempty(A.GDdims);
            results.modelPerformanceSummary = NMAnalysisManagerTools.modelPerformanceSummary(A);
            results.hasVisdata = isfield(A,'visdata') && ~isempty(A.visdata);
            results.hasMLI = (isfield(A,'MLI') && ~isempty(A.MLI)) || (isfield(A,'mli') && ~isempty(A.mli));
            results.hasModelData = isfield(A,'ModelData') && ~isempty(A.ModelData);
            results.hasOOCV = isfield(A,'OOCV') && ~isempty(A.OOCV);
            results.resultsViewerAvailable = true;
            results.canOpenResultsViewer = completed && results.resultsViewerAvailable;
            if ~completed
                results.resultsViewerReason = 'Results Viewer requires a completed analysis with status >= 1.';
            else
                results.resultsViewerReason = '';
            end
        end

        function txt = modelPerformanceSummary(A)
            txt = '';
            if ~isstruct(A) || ~(isfield(A,'GDdims') && ~isempty(A.GDdims))
                return;
            end
            parts = {};
            trainMulti = NMAnalysisManagerTools.numericSummaryText(A, 'TrainPerformanceMulti');
            testMulti = NMAnalysisManagerTools.numericSummaryText(A, 'TestPerformanceMulti');
            multiTxt = NMAnalysisManagerTools.performancePairText('multi', trainMulti, testMulti);
            if ~isempty(multiTxt)
                parts{end+1} = multiTxt; %#ok<AGROW>
            end
            trainMean = NMAnalysisManagerTools.numericSummaryText(A, 'TrainPerformanceMean');
            testMean = NMAnalysisManagerTools.numericSummaryText(A, 'TestPerformanceMean');
            meanTxt = NMAnalysisManagerTools.performancePairText('mean', trainMean, testMean);
            if ~isempty(meanTxt)
                parts{end+1} = meanTxt; %#ok<AGROW>
            end
            permMean = NMAnalysisManagerTools.numericSummaryText(A, 'TestPerformanceMeanPermAggr');
            if ~isempty(permMean)
                parts{end+1} = ['CV2 perm-aggr mean ' permMean]; %#ok<AGROW>
            end
            binTest = NMAnalysisManagerTools.numericSummaryText(A, 'TestPerformanceBin');
            if isempty(parts) && ~isempty(binTest)
                parts{end+1} = ['CV2 binary ' binTest]; %#ok<AGROW>
            end
            if isempty(parts)
                txt = 'yes; performance fields not populated';
            else
                txt = strjoin(parts, '; ');
            end
        end

        function txt = numericSummaryText(A, field)
            txt = '';
            if ~isstruct(A) || ~isfield(A, field) || isempty(A.(field)) || ~isnumeric(A.(field))
                return;
            end
            x = double(A.(field)(:));
            x = x(isfinite(x) & x ~= 0);
            if isempty(x)
                return;
            end
            if numel(x) == 1
                txt = NMAnalysisManagerTools.formatMetricValue(x);
            else
                txt = sprintf('%s [%s-%s]', NMAnalysisManagerTools.formatMetricValue(mean(x)), ...
                    NMAnalysisManagerTools.formatMetricValue(min(x)), NMAnalysisManagerTools.formatMetricValue(max(x)));
            end
        end

        function txt = formatMetricValue(x)
            if isempty(x) || ~isfinite(double(x(1)))
                txt = 'n/a';
            else
                txt = sprintf('%.3g', double(x(1)));
            end
        end

        function txt = performancePairText(label, cv1Text, cv2Text)
            txt = '';
            item = {};
            if ~isempty(cv1Text), item{end+1} = ['CV1 ' label ' ' cv1Text]; end %#ok<AGROW>
            if ~isempty(cv2Text), item{end+1} = ['CV2 ' label ' ' cv2Text]; end %#ok<AGROW>
            if ~isempty(item), txt = strjoin(item, ', '); end
        end

        function canvas = analysisCanvasPayload(NM, A)
            canvas = struct('ok',false,'type','AnalysisManagerMiniCanvas','nodes',{{}},'edges',{{}},'message','No analysis canvas is available.');
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'TrainParam') && isstruct(A.params.TrainParam) && ...
                    isfield(A.params.TrainParam,'canvasObj') && isstruct(A.params.TrainParam.canvasObj)
                canvas = A.params.TrainParam.canvasObj;
                if ~isfield(canvas,'ok'), canvas.ok = true; end
                if ~isfield(canvas,'type'), canvas.type = 'AnalysisManagerMiniCanvas'; end
                return;
            end
            try
                NMlite = NMAnalysisManagerTools.lightweightNMFromAnalysis(NM, A);
                obj = NMTrainTemplateOrchestrator.fromNM(NMlite, 1, struct('NMAppFastChildOpen',true));
                st = obj.menuState(struct('includeCanvas',true,'canvasDetailMode','summary'));
                if isfield(st,'canvas') && isstruct(st.canvas)
                    canvas = NMAnalysisManagerTools.compactCanvas(st.canvas);
                    canvas.ok = true;
                    canvas.message = 'Canvas generated from the analysis parameter snapshot.';
                    return;
                end
            catch ME
                canvas.message = sprintf('Could not generate the train-template canvas from this analysis snapshot: %s (%s)', ME.message, ME.identifier);
            end
            canvas = NMAnalysisManagerTools.fallbackCanvas(A, canvas.message);
        end

        function NMlite = lightweightNMFromAnalysis(NM, A)
            if ~isstruct(A) || ~isfield(A,'params') || ~isstruct(A.params)
                error('NMAnalysisManagerTools:missingAnalysisParams', 'Analysis has no params snapshot.');
            end
            P = A.params;
            NMlite = struct();
            if isfield(P,'TrainParam'), NMlite.TrainParam = P.TrainParam; else, NMlite.TrainParam = struct(); end
            if isfield(P,'datadescriptor'), NMlite.datadescriptor = P.datadescriptor; else, NMlite.datadescriptor = {}; end
            if isfield(P,'cv'), NMlite.cv = P.cv; else, NMlite.cv = struct(); end
            if isfield(P,'id'), NMlite.id = P.id; else, NMlite.id = 'INSPECT'; end
            if isfield(P,'label') && isstruct(P.label)
                L = P.label;
                NMlite.label = NMAnalysisManagerTools.fieldOr(L,'label',[]);
                NMlite.modeflag = NMAnalysisManagerTools.fieldOr(L,'modeflag','classification');
                NMlite.labelnames = {NMAnalysisManagerTools.fieldOr(L,'labelname','?')};
                if isfield(L,'altgroupnames'), NMlite.groupnames = L.altgroupnames; end
            end
            nMod = NMAnalysisManagerTools.analysisModalityCount(A);
            NMlite.Y = cell(1,nMod);
            NMlite.files = cell(1,nMod);
            NMlite.brainmask = cell(1,nMod);
            NMlite.badcoords = cell(1,nMod);
            NMlite.featnames = cell(1,nMod);
            NMlite.defs = struct('import_finished',true,'analyses_locked',false,'NM_ver','NM analysis inspection');
            % Optional DataIO covariate block belongs to the live workspace, not the analysis snapshot.
            if isfield(NM,'covars') && ~isempty(NM.covars) % nm2-allow: DataIO only creates workspace covariates when auxiliary variables exist.
                NMlite.covars = NM.covars;
                NMlite.covnames = NM.covnames;
            end
            if isfield(A,'C'), NMlite.C = A.C; end
        end

        function canvas = compactCanvas(raw)
            % The training-template canvas already owns the typed node/edge schema.
            % Remove editor-only fields; preserve details and their lazy state.
            canvas = struct('ok',true,'type','AnalysisManagerMiniCanvas', ...
                'generatedAt',datestr(now,30),'auditSummary',raw.auditSummary, ...
                'nodes',rmfield(raw.nodes,{'auditItems','deepLink'}),'edges',raw.edges);
        end

        function canvas = fallbackCanvas(A, message)
            nodes = repmat(struct('id','','title','','subtitle','','status','ok','lane',0,'row',0,'order',0,'group',''), 1, 5);
            nodes(1) = struct('id','labels','title','Labels','subtitle',NMAnalysisManagerTools.analysisLabelName(struct(), A),'status','ok','lane',10,'row',0,'order',1,'group','data');
            nodes(2) = struct('id','cv','title','Cross-validation','subtitle','Analysis snapshot','status','ok','lane',20,'row',0,'order',1,'group','cv');
            nodes(3) = struct('id','preproc','title','Preprocessing','subtitle','Snapshot summary','status','ok','lane',30,'row',0,'order',1,'group','preproc');
            nodes(4) = struct('id','ml','title','Machine learning','subtitle','Learner snapshot','status','ok','lane',40,'row',0,'order',1,'group','ml');
            nodes(5) = struct('id','results','title','Results','subtitle',NMAnalysisManagerTools.statusLabel(NMAnalysisManagerTools.fieldOr(A,'status',NaN)),'status','ok','lane',50,'row',0,'order',1,'group','output');
            edges = repmat(struct('source','','target','','kind','flow','label',''), 1, 4);
            edges(1) = struct('source','labels','target','cv','kind','flow','label','');
            edges(2) = struct('source','cv','target','preproc','kind','flow','label','');
            edges(3) = struct('source','preproc','target','ml','kind','flow','label','');
            edges(4) = struct('source','ml','target','results','kind','flow','label','');
            canvas = struct('ok',false,'type','AnalysisManagerMiniCanvas','nodes',nodes,'edges',edges,'message',message,'generatedAt',datestr(now,30));
        end

        function n = analysisModalityCount(A)
            n = 1;
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'datadescriptor') && ~isempty(A.params.datadescriptor)
                n = max(1, numel(A.params.datadescriptor));
            end
        end

        function txt = analysisModeFlag(NM, A)
            txt = NMAnalysisManagerTools.fieldOr(NM,'modeflag','classification');
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'label') && isstruct(A.params.label)
                txt = NMAnalysisManagerTools.fieldOr(A.params.label,'modeflag',txt);
            end
        end

        function txt = analysisLabelName(NM, A)
            % Purpose: Resolve a human-facing single-target analysis name without leaking operational DataIO metadata.
            % Syntax: txt = NMAnalysisManagerTools.analysisLabelName(NM,A)
            % Inputs: NM is the workspace; A is one analysis snapshot.
            % Outputs: txt is one canonical target name when the analysis has exactly one resolvable target, otherwise '?'.
            % Authority and flow: Analysis-local labelnames are preferred; alternative-label labelname is accepted only when altlabelflag is active; canonical NM.labelnames is the native fallback.
            % Scientific/state contract: Native labelname is not recovered from input_settings.label_edit or other descriptors. Alternative-label scientific identity remains analysis-local.
            % Invariants: Multi-target analyses are not assigned an arbitrary single label; operational placeholders cannot become scientific target labels.
            % Materialization and performance: Metadata-only; no files, XML, atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; metadata-only analysis-management work and safe on interactive metadata paths; it is not a retained renderer path.
            % Failure semantics: Missing valid single-target metadata returns '?'.
            % Side effects: None.
            % Consumers and dependencies: Analysis catalogue/card presentation and Results Viewer metadata consumers.
            txt = '?';
            if isstruct(A) && isfield(A,'params') && isstruct(A.params) && isfield(A.params,'label') && isstruct(A.params.label)
                L=A.params.label;
                isAlternative=isfield(L,'altlabelflag') && ~isempty(L.altlabelflag) && logical(L.altlabelflag(1));
                if isfield(L,'labelnames') && ~isempty(L.labelnames)
                    names=cellstr(string(L.labelnames));
                    if numel(names)==1 && ~isempty(strtrim(names{1})), txt=strtrim(names{1}); return; end
                elseif isAlternative && isfield(L,'labelname') && ~isempty(L.labelname)
                    candidate=strtrim(char(string(L.labelname)));if ~isempty(candidate),txt=candidate;return;end
                end
            end
            names=NMAnalysisManagerTools.defaultLabelNames(NM);
            if numel(names)==1 && ~isempty(strtrim(names{1})),txt=strtrim(names{1});end
        end

        function txt = descriptionText(desc)
            % descriptionText  Flatten legacy multi-line descriptions to one UI string.
            %
            %   Legacy analyses may store A.desc as a cellstr, string array or
            %   character matrix. Browser analysis-list and card payloads require
            %   one scalar text value per analysis, so non-empty entries are
            %   joined in their stored order without changing NM.

            if isempty(desc)
                txt = '';
            elseif iscell(desc)
                parts = cellfun(@(x) NMAnalysisManagerTools.descriptionText(x), ...
                    desc(:)', 'UniformOutput', false);
                parts = parts(~cellfun(@isempty, parts));
                txt = strjoin(parts, ' ');
            elseif isstring(desc)
                values = desc(:);
                values = values(~ismissing(values) & strlength(values) > 0);
                txt = strjoin(cellstr(values), ' ');
            elseif ischar(desc)
                if size(desc,1) == 1
                    txt = desc;
                else
                    parts = strtrim(cellstr(desc));
                    parts = parts(~cellfun(@isempty, parts));
                    txt = strjoin(parts, ' ');
                end
            elseif isnumeric(desc) || islogical(desc)
                txt = strjoin(cellstr(string(desc(:))), ' ');
            else
                txt = '';
            end
        end

        function txt = scalarText(value, defaultValue)
            % scalarText  Normalize scalar analysis metadata for list/card payloads.
            %
            %   txt = scalarText(value, defaultValue) returns one character row.
            %   Legacy analysis identifiers and paths are expected to be scalar;
            %   when malformed container metadata is encountered, the first
            %   non-empty item is used so browser list construction remains
            %   scalar and deterministic.

            txt = char(string(defaultValue));
            if isempty(value), return; end
            if ischar(value)
                if size(value,1) == 1
                    txt = value;
                else
                    rows = cellstr(value);
                    rows = rows(~cellfun(@isempty, rows));
                    if ~isempty(rows), txt = rows{1}; end
                end
                return;
            end
            if isstring(value)
                values = value(:);
                values = values(~ismissing(values) & strlength(values) > 0);
                if ~isempty(values), txt = char(values(1)); end
                return;
            end
            if iscell(value)
                for k = 1:numel(value)
                    candidate = NMAnalysisManagerTools.scalarText(value{k}, '');
                    if ~isempty(candidate)
                        txt = candidate;
                        return;
                    end
                end
                return;
            end
            if isnumeric(value) || islogical(value)
                txt = char(string(value(1)));
            end
        end

        function txt = statusLabel(v)
            dv = NMAnalysisManagerTools.scalarDouble(v, NaN);
            if isnan(dv)
                txt = 'unknown';
            elseif dv >= 1
                txt = 'completed';
            else
                txt = 'configured/not completed';
            end
        end

        function v = scalarDouble(x, defaultValue)
            v = defaultValue;
            if isempty(x), return; end
            if isnumeric(x) || islogical(x)
                x = double(x);
                v = x(1);
            end
        end

        function txt = fusionLabel(flag)
            switch round(double(flag))
                case 1, txt = 'early fusion';
                case 2, txt = 'intermediate fusion';
                case 3, txt = 'late fusion';
                otherwise, txt = 'single-modality / no fusion';
            end
        end

        function txt = rfeSummary(RFE)
            txt = 'inactive';
            filterFlag = isfield(RFE,'Filter') && isstruct(RFE.Filter) && isfield(RFE.Filter,'flag') && ...
                NMAnalysisManagerTools.scalarDouble(RFE.Filter.flag,0) == 1;
            wrapperFlag = isfield(RFE,'Wrapper') && isstruct(RFE.Wrapper) && isfield(RFE.Wrapper,'flag') && ...
                NMAnalysisManagerTools.scalarDouble(RFE.Wrapper.flag,0) == 1;
            wrapperOpt = isfield(RFE,'Wrapper') && isstruct(RFE.Wrapper) && isfield(RFE.Wrapper,'flag') && isfield(RFE.Wrapper,'optflag') && ...
                NMAnalysisManagerTools.scalarDouble(RFE.Wrapper.flag,0) == 0 && NMAnalysisManagerTools.scalarDouble(RFE.Wrapper.optflag,0) == 1;
            if filterFlag || wrapperFlag || wrapperOpt, txt = 'active'; end
        end

        function txt = savSummary(SAV)
            txt = 'configured';
            if isstruct(SAV) && isfield(SAV,'matname') && ~isempty(SAV.matname)
                txt = char(string(SAV.matname));
            end
        end

        function assertAnalysisIndex(NM, analind)
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis) || isempty(analind) || analind < 1 || analind > numel(NM.analysis) || isempty(NM.analysis{analind})
                error('NMAnalysisManagerTools:badAnalysisIndex', 'Analysis %d does not exist.', analind);
            end
        end

        function v = fieldOr(s, field, defaultValue)
            v = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)), v = s.(field); end
        end

        function txt = reportText(report)
            txt = '';
            if isstruct(report) && isfield(report,'errors') && ~isempty(report.errors)
                try, txt = strjoin(cellstr(string(report.errors)), '; '); catch, txt = 'see report.errors'; end
            elseif isstruct(report) && isfield(report,'message') && ~isempty(report.message)
                txt = char(string(report.message));
            end
        end

        function s = mergeStruct(a, b)
            s = a;
            if ~isstruct(b), return; end
            fn = fieldnames(b);
            for i = 1:numel(fn), s.(fn{i}) = b.(fn{i}); end
        end
    end

end
