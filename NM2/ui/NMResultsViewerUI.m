classdef NMResultsViewerUI
% NMResultsViewerUI
% -------------------------------------------------------------------------
% Browser alpha Results Viewer.  This is deliberately read-only and keeps the
% legacy MATLAB NM_Results_Viewer available as the complete fallback. % nm2-allow: NMResultsViewerUI.export explicitly preserves standalone MATLAB viewer routing and required browser asset contracts.
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(NM, outDir, ctx)
            % export  Create a read-only browser Results Viewer session.
            %
            % Writes the NM snapshot, initial Results Viewer state, HTML shell and plot/image/table
            % assets needed to inspect completed analyses. The method deliberately leaves modelling
            % results unchanged and preserves the legacy MATLAB Results Viewer as fallback. % nm2-allow: NMResultsViewerUI.export explicitly preserves standalone MATLAB viewer routing and required browser asset contracts.

            if nargin < 1 || isempty(NM), NM = struct(); end % nm2-allow: NMResultsViewerUI.export is a public standalone and NMAppUI entry point with established optional argument defaults.
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_results_viewer_alpha_ui'); end % nm2-allow: NMResultsViewerUI.export is a public standalone and NMAppUI entry point with established optional argument defaults.
            if nargin < 3, ctx = struct(); end % nm2-allow: NMResultsViewerUI.export is a public standalone and NMAppUI entry point with established optional argument defaults.
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_results_viewer_alpha_ui');
            NMDataIOUI.saveSessionNM(NM, dirs.tmpDir);
            if NMUISessionTools.fastChildOpen(ctx)
                state = NMResultsViewerUI.bootstrapState(ctx);
            else
                state = NMResultsViewerUI.stateFromNM(NM, ctx);
            end
            if isstruct(ctx) && isfield(ctx,'ReportExecutionRequest') && isstruct(ctx.ReportExecutionRequest) % nm2-allow: NMResultsViewerUI.export receives optional ReportExecutionRequest from MATLAB API or workbench context at the export boundary.
                state.reportExecutionRequest = ctx.ReportExecutionRequest;
            end
            stateJson = NMConfigTools.writeJsonAliases({fullfile(dirs.tmpDir,'results_viewer_alpha_state.json'), ...
                fullfile(dirs.tmpDir,'current_config.json'), fullfile(dirs.tmpDir,'param.json')}, state, 'Alpha Results Viewer state');
            htmlPath = fullfile(dirs.webDir, 'nm_results_viewer_alpha.html');
            % Install every script referenced by the generated shell before the
            % shell itself becomes visible to an already-running browser session.
            % This ordering prevents a new HTML contract from racing ahead of a
            % newly introduced asset during staged upgrades.
            NMResultsViewerUI.copyAssets(dirs.webDir);
            NMResultsViewerUI.writeTextFile(htmlPath, NMResultsViewerUI.htmlTextFromJson(stateJson));
            NMPreprocUI.writeBridge(fullfile(dirs.pyDir,'nm_bridge_server.py'));
            paths = struct('root',dirs.root, 'webRoot',dirs.webRoot, 'webDir',dirs.webDir, 'tmpDir',dirs.tmpDir, ...
                'html',htmlPath, 'resultsViewerAlphaHtml',htmlPath, 'entryHtml','nm_results_viewer_alpha.html', ...
                'entryHtmlPath',htmlPath, 'state',fullfile(dirs.tmpDir,'results_viewer_alpha_state.json'));
        end

        function [report, execution] = executeReport(NM, reportSpec, executionOptions)
            % executeReport  Execute one canonical Report Builder recipe through the shared adapters.
            %
            % MATLAB/tabular-only recipes are built directly. Recipes containing
            % FeaturePresentations run in a temporary browser process owned by the
            % MATLAB bridge. Headless execution and CLI progress reporting are the
            % API defaults; callers may disable either explicitly for debugging.
            if nargin < 1 || isempty(NM), NM=struct(); end % nm2-allow: NMResultsViewerUI.executeReport is a public MATLAB API whose existing omitted-argument defaults are supported.
            if nargin < 2 || isempty(reportSpec), reportSpec=NMResultsViewerReportTools.defaultReportSpec(NM,struct()); end % nm2-allow: NMResultsViewerUI.executeReport is a public MATLAB API whose existing omitted-argument defaults are supported.
            if nargin < 3 || isempty(executionOptions), executionOptions=struct(); end % nm2-allow: NMResultsViewerUI.executeReport is a public MATLAB API whose existing omitted-argument defaults are supported.
            if ~isstruct(executionOptions) || ~isscalar(executionOptions) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                error('NMResultsViewerUI:InvalidReportExecutionOptions','Report execution options must be one scalar struct.');
            end
            headless=true;
            verbose=true;
            if isfield(executionOptions,'Headless') && ~isempty(executionOptions.Headless) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                value=executionOptions.Headless;
                if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                    error('NMResultsViewerUI:InvalidReportExecutionHeadless','Report execution Headless must be a scalar logical/numeric value.');
                end
                headless=logical(value);
            end
            if isfield(executionOptions,'Verbose') && ~isempty(executionOptions.Verbose) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                value=executionOptions.Verbose;
                if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                    error('NMResultsViewerUI:InvalidReportExecutionVerbose','Report execution Verbose must be a scalar logical/numeric value.');
                end
                verbose=logical(value);
            end
            reportSpec=NMResultsViewerReportTools.planReportSpecForBrowser(NM,reportSpec);
            presentations=struct([]);
            for pp=1:numel(reportSpec.AnalysisPlans)
                if ~isempty(reportSpec.AnalysisPlans(pp).FeaturePresentations)
                    presentations=[presentations reportSpec.AnalysisPlans(pp).FeaturePresentations]; %#ok<AGROW>
                end
            end
            if isempty(presentations)
                if verbose, fprintf('[nm report] Building MATLAB/tabular report payload.\n'); end
                preparedSpec=reportSpec;
                report=NMResultsViewerReportTools.buildReport(NM,preparedSpec);
                if verbose, fprintf('[nm report] 100%% Report execution completed.\n'); end
                execution=struct('UsedBrowserAdapters',false,'PreparedReportSpec',preparedSpec, ...
                    'ReportHandle','','SessionRoot','');
                return;
            end

            if headless
                if ispc, defaultBrowserTarget='browser-edge'; else, defaultBrowserTarget='browser-chrome'; end
            else
                defaultBrowserTarget='browser-default';
            end
            browserTarget=NMResultsViewerUI.requestTextField(executionOptions,'BrowserTarget',defaultBrowserTarget);
            port=[];
            if isfield(executionOptions,'Port') && ~isempty(executionOptions.Port) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                rawPort=double(executionOptions.Port(1));
                if ~isfinite(rawPort) || rawPort < 1 || rawPort > 65535 || abs(rawPort-round(rawPort)) > eps(max(1,abs(rawPort)))
                    error('NMResultsViewerUI:InvalidReportExecutionPort','Report execution Port must be a positive integer from 1 to 65535.');
                end
                port=round(rawPort);
            end
            outDir='';
            if isfield(executionOptions,'SessionDirectory') && ~isempty(executionOptions.SessionDirectory) % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
                outDir=char(string(executionOptions.SessionDirectory)); % nm2-allow: NMResultsViewerUI.executeReport validates caller-supplied executionOptions at the public MATLAB API boundary.
            end
            if isempty(outDir), outDir=tempname; end
            progressTaskId=['report_api_' regexprep(char(java.util.UUID.randomUUID()),'-','')];
            ctx=struct('ReportExecutionRequest',struct('ReportSpec',reportSpec, ...
                'ProgressTaskId',progressTaskId,'ProgressConsole',logical(verbose)));
            paths=NMResultsViewerUI.export(NM,outDir,ctx);
            cleanup=onCleanup(@()NMDataIOUI.clearSessionNM(paths.tmpDir)); %#ok<NASGU>
            handler=@(req,tmpDir)NMResultsViewerUI.handleMatlabService(NM,req,tmpDir,struct());
            bridgeOptions=struct('Headless',logical(headless));
            if verbose
                modeLabel='visible'; if headless, modeLabel='headless'; end
                fprintf('[nm report] Starting %s browser-adapter session (%s).\n',modeLabel,browserTarget);
            end
            finalState=nm_open_ui(paths.webDir,port,paths.entryHtml,handler,browserTarget,bridgeOptions);
            result=struct();
            if isstruct(finalState) && isfield(finalState,'reportExecutionResult') && isstruct(finalState.reportExecutionResult) % nm2-allow: nm_open_ui returns browser-produced reportExecutionResult; executeReport validates external bridge output before cache access.
                result=finalState.reportExecutionResult;
            end
            if isempty(fieldnames(result))
                error('NMResultsViewerUI:MissingReportExecutionResult', ...
                    'The automatic Results Viewer report session closed without returning an execution result.');
            end
            if ~NMResultsViewerUI.structField(result,'ok',false)
                error('NMResultsViewerUI:ReportExecutionFailed','%s',char(string(NMResultsViewerUI.structField(result,'message','Automatic Report Builder execution failed.')))); % nm2-allow: nm_open_ui returns browser-produced reportExecutionResult; executeReport validates external bridge output before cache access.
            end
            handle=char(string(NMResultsViewerUI.structField(result,'reportHandle',''))); % nm2-allow: nm_open_ui returns browser-produced reportExecutionResult; executeReport validates external bridge output before cache access.
            entry=NMResultsViewerUI.reportCacheStore('get',handle,struct());
            if isempty(fieldnames(entry))
                error('NMResultsViewerUI:MissingExecutedReportCache', ...
                    'The automatic Report Builder session completed but its validated report cache entry is unavailable.');
            end
            report=entry.report;
            preparedSpec=entry.preparedSpec;
            execution=struct('UsedBrowserAdapters',true,'PreparedReportSpec',preparedSpec, ...
                'ReportHandle',handle,'SessionRoot',paths.root);
        end

        function NM = importUpdated(NM, pathsOrWebDir, ctx)
            % importUpdated  Complete the Results Viewer UI lifecycle without mutating results.
            %
            % Reloads the session NM if present and clears the temporary snapshot, matching the shared UI
            % lifecycle. Results Viewer actions are intended for inspection/export, so no analysis data
            % are modified here.

            if nargin < 1 || isempty(NM), NM = struct(); end % nm2-allow: NMResultsViewerUI.importUpdated is an existing public UI lifecycle API with optional caller arguments.
            if nargin < 2 || isempty(pathsOrWebDir), return; end % nm2-allow: NMResultsViewerUI.importUpdated is an existing public UI lifecycle API with optional caller arguments.
            tmpDir = NMDataIOUI.pathsTmpDir(pathsOrWebDir);
            if isempty(tmpDir), return; end
            [NM2, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            if ok, NM = NM2; end
            NMDataIOUI.clearSessionNM(tmpDir);
        end

        function state = stateFromNM(NM, ctx, spec)
            % stateFromNM  Build initial Results Viewer state from completed NM analyses.
            %
            % Delegates result-summary extraction to NMResultsViewerTools and attaches app navigation
            % context. The state describes available analyses, modalities, payload options and viewer
            % controls for browser-side rendering.

            if nargin < 3 || isempty(spec), spec = struct(); end % nm2-allow: NMResultsViewerUI.stateFromNM accepts optional browser-selected resultType and inspection scope before state construction.
            % Initial state construction is metadata-first even when the result
            % family is resolved only after the analysis catalogue is built.
            if ~isfield(spec,'featureInspectionPayloadScope') % nm2-allow: export and standalone state constructors supply partial state specifications with optional inspection scope.
                spec.featureInspectionPayloadScope = 'metadata';
            end
            doProfile = NMResultsViewerTools.profileEnabled(spec);
            tTotal = tic;
            t = tic;
            state = NMResultsViewerTools.buildInitialState(NM, spec);
            NMResultsViewerUI.profileLog(doProfile, '[nm-prof] results viewer state buildInitialState: %.3fs\n', toc(t));
            t = tic;
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'results_viewer_alpha');
            state.profileEnabled = logical(doProfile);
            NMResultsViewerUI.profileLog(doProfile, '[nm-prof] results viewer state attach context:   %.3fs\n', toc(t));
            NMResultsViewerUI.profileLog(doProfile, '[nm-prof] results viewer state TOTAL:            %.3fs\n', toc(tTotal));
        end

        function state = bootstrapState(ctx)
            % bootstrapState  Build the lightweight Results Viewer shell for workbench navigation.
            %
            % The workbench already owns fast child-page navigation. This state contains only the
            % browser/session contract required to display the shell; the authoritative Results Viewer
            % state is requested immediately through results_viewer_alpha_refresh after navigation.
            state = struct();
            state.page = 'results_viewer_alpha';
            state.title = 'New NM Results Viewer (alpha)';
            state.loading = true;
            state.profileEnabled = NMResultsViewerTools.profileEnabled(struct());
            state.message = 'Loading Results Viewer state from MATLAB.';
            state = NMUISessionTools.attachAppContextToState(ctx, state, 'results_viewer_alpha');
        end

        function [handled, out] = handleMatlabService(NM, req, tmpDir, ctx)
            % Purpose: Dispatch restricted browser-to-MATLAB Results Viewer service operations for one session request.
            % Syntax: [handled,out] = NMResultsViewerUI.handleMatlabService(NM,req,tmpDir,ctx)
            % Inputs: NM is the session workspace; req is the validated browser request; tmpDir is the session directory; ctx carries bridge context.
            % Outputs: handled indicates whether the operation belongs to this UI; out is the JSON-safe operation response.
            % Authority and flow: Operations delegate to existing backend authorities. Cross-analysis workspace payloads flow through NMResultsViewerTools.getPayload; explicit performance-table generation delegates to NMResultsViewerCrossAnalysisTools.performanceTable. Explicit analysis-set queries materialize Scientific State once at the Results Viewer session boundary and retain it by canonical set identity for Report Builder reuse. If a payload already carries a multi-context Scientific State, that state is returned directly rather than rebuilt as a single-context state.
            % Scientific/state contract: The service boundary transports authoritative Scientific State/Annotation and never derives scientific meaning from browser DOM state.
            % Invariants: Session NM remains the backend input authority; operation names are explicit; cross-analysis uses the same payload/report authorities as direct API consumers.
            % Materialization and performance: Per-operation cost is that of the delegated authority plus JSON-safe response construction. Queried analysis-set inventories are retained per Results Viewer session, so changing only the Report Builder analysis focus reuses O(A) capability and O(A^2) delegated CV-group work. The dispatcher itself reads no scientific source files, XML, atlases, annotations or meshes and performs no voxel/vertex scans or feature-scale allocations.
            % Resource declaration: The dispatcher itself reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; delegated operations retain their own resource contracts. The Cross-analysis route is safe for explicit interactive requests.
            % Failure semantics: Backend exceptions propagate through the established UI-service error route; no silent fallback to browser-derived state is introduced. % nm2-allow: NMResultsViewerUI.handleMatlabService documents propagation to the existing browser-service exception boundary.
            % Side effects: May read/write established session/bridge resources for operations that already require them; cross-analysis read operations do not mutate NM.
            % Consumers and dependencies: NMAppUI/bridge dispatch, NMResultsViewerTools, NMResultsViewerCrossAnalysisTools and other Results Viewer service authorities.
            handled = false; out = struct();
            op = NMResultsViewerUI.requestOperation(req); if isempty(op), return; end
            doProfile = NMResultsViewerTools.profileEnabled(req);
            tService = tic;
            serviceCleanup = onCleanup(@() NMResultsViewerUI.profileLog(doProfile, ...
                '[nm-prof] results viewer service TOTAL op=%s: %.3fs\n', op, toc(tService))); %#ok<NASGU>
            NMResultsViewerUI.profileLog(doProfile, '[nm-prof] results viewer service ENTER op=%s\n', op);
            switch lower(op)
                case {'results_viewer_alpha_refresh','results_viewer_alpha_state'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    state = NMResultsViewerUI.stateFromNM(sessionNM, ctx, spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer refresh stateFromNM: %.3fs\n', toc(t));
                    out = struct('ok',true,'message','Alpha Results Viewer state refreshed.','operation',op,'state',state);
                case {'results_viewer_alpha_payload','results_viewer_alpha_classification'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerTools.getPayload(sessionNM, spec);
                    payloadContext = NMResultsViewerTools.payloadContextFromSpec(spec, payload);
                    if isstruct(payload)&&isfield(payload,'scientificState')&&isstruct(payload.scientificState) % nm2-allow: NMResultsViewerTools.getPayload may supply authoritative multi-context scientificState or a single-context payload.
                        scientificState=payload.scientificState;
                    else
                        scientificState = NMResultsViewerScientificState.clientView( ...
                            NMResultsViewerScientificState.fromPayloads({payload},spec));
                    end
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer payload getPayload: %.3fs\n', toc(t));
                    out = struct('ok',true,'message',payload.message,'operation',op, ...
                        'payload',payload,'payloadContext',payloadContext,'scientificState',scientificState);
                case {'results_viewer_alpha_fractionated_decision'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    if ~strcmp(spec.resultType,'model_feature_inspection') || ~strcmp(spec.source,'cv')
                        error('NMResultsViewerUI:InvalidFractionatedDecisionSource', ...
                            'Fractionated decision scores require the CV Feature Inspection source.');
                    end
                    spec.featureInspectionPayloadScope = 'metadata';
                    spec.featureInspectionCatalogueScope = 'selected';
                    inspection = NMResultsViewerTools.getModelFeatureInspectionPayload(sessionNM,spec);
                    scores = NMResultsViewerTools.getModelFeatureInspectionFractionatedDecisionPayload(sessionNM,inspection,'all');
                    out = struct('ok',scores.ok,'message',scores.message,'operation',op,'payload',scores);
                case {'results_viewer_alpha_fractionated_clusters'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    if ~strcmp(spec.resultType,'model_feature_inspection') || ~strcmp(spec.source,'cv')
                        error('NMResultsViewerUI:InvalidFractionatedClusterSource', ...
                            'Subject clustering requires CV Feature Inspection.');
                    end
                    mode = char(string(req.clusterMode));
                    count = double(req.clusterCount);
                    if ~ismember(mode,{'raw','relative'}) || ~isscalar(count) || ...
                            ~isfinite(count) || count~=floor(count) || count<2 || count>8
                        error('NMResultsViewerUI:InvalidFractionatedClusterOptions', ...
                            'Cluster mode must be raw/relative and clusterCount an integer from 2 to 8.');
                    end
                    selection=[];
                    if isfield(req,'clusterSelection') && strcmp(char(string(req.clusterSelection)),'auto')
                        criterion=char(string(req.clusterCriterion));
                        minimum=double(req.clusterMin);
                        maximum=double(req.clusterMax);
                        bootstrapIterations=double(req.clusterBootstraps);
                        if ~ismember(criterion,{'silhouette','ari','pac','cophenetic'}) || ...
                                ~isscalar(minimum) || ~isscalar(maximum) || ...
                                ~isfinite(minimum) || ~isfinite(maximum) || ...
                                minimum~=floor(minimum) || maximum~=floor(maximum) || ...
                                minimum<2 || maximum<2 || minimum>maximum || ...
                                ~isscalar(bootstrapIterations) || ~isfinite(bootstrapIterations) || ...
                                bootstrapIterations~=floor(bootstrapIterations) || ...
                                bootstrapIterations<4 || bootstrapIterations>100
                            error('NMResultsViewerUI:InvalidFractionatedAutoOptions', ...
                                'Auto selection requires k bounds >=2 (min <= max) and 4..100 bootstrap iterations; k must not exceed the available subject count.');
                        end
                        selection=struct('criterion',criterion,'minClusters',minimum,'maxClusters',maximum, ...
                            'bootstrapIterations',bootstrapIterations);
                    end
                    [progressUI,progressCleanup]=NMResultsViewerUI.openReportProgressContext( ...
                        tmpDir,req,'Cluster selection'); %#ok<NASGU>
                    spec.featureInspectionPayloadScope = 'metadata';
                    spec.featureInspectionCatalogueScope = 'selected';
                    inspection = NMResultsViewerTools.getModelFeatureInspectionPayload(sessionNM,spec);
                    try
                        result = NMResultsViewerTools.getModelFeatureInspectionFractionatedClusters( ...
                            sessionNM,inspection,spec,mode,count,selection);
                        NMResultsViewerUI.finishReportProgress(progressUI,'Cluster selection completed.');
                    catch ME
                        NMResultsViewerUI.failReportProgress(progressUI,'Cluster selection',ME);
                        rethrow(ME);
                    end
                    out = struct('ok',true,'message',result.message,'operation',op,'payload',result);
                case {'results_viewer_cross_analysis_performance_table'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerCrossAnalysisTools.performanceTable(sessionNM,spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   cross-analysis performance table: %.3fs (contexts=%d)\n', ...
                        toc(t), double(NMResultsViewerUI.scalarField(payload,'materializedContextCount',0)));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_cross_analysis_statistical_comparison'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    indices = spec.analysisIndices;
                    t=tic;
                    [analysisSetState,inventoryCacheHit]=NMResultsViewerUI.analysisSetInventory(sessionNM,tmpDir,indices,spec);
                    payload=NMResultsViewerCrossAnalysisTools.statisticalComparison(sessionNM,spec,analysisSetState);
                    NMResultsViewerUI.profileLog(doProfile,'[nm-prof]   cross-analysis statistical comparison: %.3fs (analyses=%d cacheHit=%d)\n', ...
                        toc(t),double(numel(payload.selectedAnalysisIndices)),double(inventoryCacheHit));
                    out=struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload,'inventoryCacheHit',logical(inventoryCacheHit));
                case {'results_viewer_cross_analysis_visual_comparison'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    indices = spec.analysisIndices;
                    t=tic;
                    [analysisSetState,inventoryCacheHit]=NMResultsViewerUI.analysisSetInventory(sessionNM,tmpDir,indices,spec);
                    payload=NMResultsViewerCrossAnalysisTools.visualComparison(sessionNM,spec,analysisSetState);
                    NMResultsViewerUI.profileLog(doProfile,'[nm-prof]   cross-analysis visual comparison: %.3fs (analyses=%d metrics=%d cacheHit=%d)\n', ...
                        toc(t),double(numel(payload.selectedAnalysisIndices)),double(numel(payload.selectedMetricIds)),double(inventoryCacheHit));
                    out=struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload,'inventoryCacheHit',logical(inventoryCacheHit));
                case 'results_viewer_synth_inventory'
                    handled=true;
                    sessionNM=NMResultsViewerUI.loadSessionNMProfiled(NM,tmpDir,doProfile,op);
                    experiments=cell(1,0);
                    if isfield(sessionNM,'SYNTH') % nm2-allow: persisted optional NM2 domain is admitted at the session-load boundary.
                        for ii=1:numel(sessionNM.SYNTH.analysis)
                            parent=sessionNM.SYNTH.analysis{ii};
                            indices=parent.analysisIndices;
                            experiments{end+1}=struct('index',ii,'id',parent.id, ...
                                'status',parent.status,'analysisCount',numel(indices), ...
                                'analysisIndices',{num2cell(indices)}); %#ok<AGROW>
                        end
                    end
                    out=struct('ok',true,'operation',op,'experiments',{experiments});
                case 'results_viewer_synth_overview'
                    handled=true;
                    sessionNM=NMResultsViewerUI.loadSessionNMProfiled(NM,tmpDir,doProfile,op);
                    experimentIndex=double(req.experimentIndex);
                    validateattributes(experimentIndex,{'numeric'},{'scalar','integer','positive'});
                    payload=NMResultsViewerCrossAnalysisTools.synthOverview(sessionNM,experimentIndex);
                    % Explicit cell axis preserves JSON array shape for singleton rows/series.
                    payload.rows=num2cell(payload.rows);
                    payload.plotPayload.values=arrayfun(@(ii)num2cell(payload.plotPayload.values(ii,:)), ...
                        1:size(payload.plotPayload.values,1),'UniformOutput',false);
                    payload.plotPayload.xPositions=num2cell(payload.plotPayload.xPositions);
                    % Preserve row/column axes through MATLAB scalar-array JSON encoding.
                    for kk=1:numel(payload.contexts)
                        for field={'mean','sd','count'}
                            name=field{1};matrix=payload.contexts(kk).(name);
                            payload.contexts(kk).(name)=arrayfun(@(i)num2cell(matrix(i,:)), ...
                                1:size(matrix,1),'UniformOutput',false);
                        end
                    end
                    payload.contexts=num2cell(payload.contexts);
                    out=struct('ok',true,'operation',op,'payload',payload);
                case {'results_viewer_analysis_set_inventory'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    indices = spec.analysisIndices;
                    t = tic;
                    [scientificState, inventoryCacheHit] = NMResultsViewerUI.analysisSetInventory(sessionNM,tmpDir,indices,spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   analysis-set Scientific State inventory: %.3fs (analyses=%d cacheHit=%d)\n', ...
                        toc(t), double(numel(scientificState.scope.analysisIndices)), double(inventoryCacheHit));
                    out = struct('ok',true,'message',sprintf('Queried Results Viewer inventory for %d analysis(es).',numel(scientificState.scope.analysisIndices)), ...
                        'operation',op,'scientificState',NMResultsViewerScientificState.clientView(scientificState),'inventoryCacheHit',logical(inventoryCacheHit));
                case {'results_viewer_alpha_feature_relation'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerTools.getModelFeatureRelationPayload(sessionNM, spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer feature relation:    %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_connectivity_representation'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerConnectivityAdapter.resolve(sessionNM, spec, '', []);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer connectivity adapter: %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_connectivity_anatomy_assets'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerConnectivityAdapter.anatomyAssets(sessionNM,spec,tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer connectivity anatomy: %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_imaging_catalogue'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerImagingTools.getImagingCatalogue(sessionNM, spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer imaging catalogue:   %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_imaging_workspace'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerImagingTools.getImagingWorkspace(sessionNM, spec, tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer imaging workspace:   %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_imaging_feature_resource'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerImagingTools.getImagingFeatureResource(sessionNM, spec, tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer imaging feature:     %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_imaging_atlas'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerImagingTools.getImagingAtlasResource(sessionNM, spec, tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer imaging atlas:       %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_imaging_3d_assets'}
                    handled = true;
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerImagingTools.getImaging3DAssets([], spec, tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer imaging 3-D assets: %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_surface_atlas'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    payload = NMResultsViewerSurfaceTools.loadAnnotationAtlas(sessionNM, spec, tmpDir);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer surface atlas:     %.3fs\n', toc(t));
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload);
                case {'results_viewer_alpha_vector_options'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    t = tic;
                    out = NMResultsViewerTools.plotVectorOptions(sessionNM, req);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer vector options:      %.3fs\n', toc(t));
                    out.operation = op;
                case {'results_viewer_alpha_profile_events'}
                    handled = true;
                    eventCount = NMResultsViewerUI.printBrowserProfileEvents(req);
                    out = struct('ok',true,'message','Results Viewer browser profile events recorded.', ...
                        'operation',op,'eventCount',eventCount);
                case {'results_viewer_alpha_subject_feature_qc'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    out = NMResultsViewerTools.getSubjectFeatureQC(sessionNM, spec, tmpDir);
                    out.operation = op;
                case {'results_viewer_alpha_action','results_viewer_alpha_probability','results_viewer_alpha_calibration','results_viewer_alpha_dca'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    t = tic;
                    [payload, sessionNM, didPersist] = NMResultsViewerTools.getClassificationActionPayload(sessionNM, spec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   results viewer action payload:      %.3fs\n', toc(t));
                    if didPersist
                        NMDataIOUI.saveSessionNM(sessionNM, tmpDir);
                        sessionKey=NMDataIOUI.sessionKey(tmpDir);
                        NMResultsViewerUI.reportCacheStore('remove_session',sessionKey,struct());
                        NMResultsViewerUI.analysisSetInventoryCacheStore('remove_session',sessionKey,struct());
                    end
                    out = struct('ok',payload.ok,'message',payload.message,'operation',op,'payload',payload,'didPersistProbability',logical(didPersist));
                case {'results_viewer_output_export'}
                    handled = true;
                    out = NMResultsViewerExportTools.exportArtifactRequest(req, tmpDir);
                    out.operation = op;
                case {'results_viewer_report_execution_progress'}
                    handled = true;
                    percent = NMResultsViewerUI.scalarField(req,'percent',NaN);
                    if ~isfinite(percent) || percent < 0 || percent > 100
                        error('NMResultsViewerUI:InvalidReportExecutionProgress','Report execution progress percent must be finite and between 0 and 100.');
                    end
                    message = NMResultsViewerUI.requestTextField(req,'message','Report execution is in progress.');
                    phase = NMResultsViewerUI.requestTextField(req,'phase','');
                    fprintf('[nm report] %3.0f%% %s\n',percent,message);
                    out = struct('ok',true,'message',message,'operation',op,'percent',percent,'phase',phase);
                case {'results_viewer_report_catalogue','results_viewer_report_default'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    scopeContext = NMResultsViewerTools.reportAnalysisScope(sessionNM,spec);
                    analysisSetState=struct();inventoryCacheHit=false;
                    if any(strcmp(scopeContext.Scope,{'analysis_set','multi_analysis'}))
                        [analysisSetState,inventoryCacheHit]=NMResultsViewerUI.analysisSetInventory(sessionNM,tmpDir,scopeContext.AnalysisIndices,spec);
                    end
                    t = tic;
                    [components, featurePlanCatalogue, reportContext, featurePresentationPayload] = NMResultsViewerReportTools.listAvailableComponents(sessionNM, spec, analysisSetState);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   report builder listAvailableComponents: %.3fs (components=%d analysisSetCacheHit=%d)\n', toc(t), numel(components), double(inventoryCacheHit));
                    spec.analysisIndex = reportContext.SelectedAnalysisIndex;
                    t = tic; reportSpec = NMResultsViewerReportTools.defaultReportSpec(sessionNM, spec, components);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   report builder defaultReportSpec: %.3fs\n', toc(t));
                    out = struct('ok',true,'message','Results Viewer report components listed.', ...
                        'operation',op,'components',components,'reportSpec',reportSpec, ...
                        'featurePlanCatalogue',featurePlanCatalogue,'reportContext',reportContext, ...
                        'featurePresentationPayload',featurePresentationPayload);
                case {'results_viewer_report_plan'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    reportSpec = NMResultsViewerUI.requestReportSpec(req);
                    if isempty(fieldnames(reportSpec))
                        reportSpec = NMResultsViewerReportTools.defaultReportSpec(sessionNM, NMResultsViewerUI.requestSpec(req));
                    end
                    t = tic; plannedSpec = NMResultsViewerReportTools.planReportSpecForBrowser(sessionNM, reportSpec);
                    NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   report builder planReportSpecForBrowser: %.3fs (components=%d)\n', toc(t), numel(plannedSpec.Components));
                    out = struct('ok',true,'message','Results Viewer report specification planned.', ...
                        'operation',op,'plannedSpec',plannedSpec);
                case {'results_viewer_report_build'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    reportSpec = NMResultsViewerUI.requestReportSpec(req);
                    if isempty(fieldnames(reportSpec))
                        reportSpec = NMResultsViewerReportTools.defaultReportSpec(sessionNM, NMResultsViewerUI.requestSpec(req));
                    end
                    [progressUI, progressCleanup] = NMResultsViewerUI.openReportProgressContext(tmpDir, req, 'Report generation'); %#ok<NASGU>
                    try
                        NMResultsViewerUI.writeReportProgress('Report Builder', 'Preparing MATLAB report payload.', 58, 'prepare');
                        report = NMResultsViewerReportTools.buildReport(sessionNM, reportSpec);
                        [reportHandle, cacheInfo] = NMResultsViewerUI.storeReportCache(tmpDir, sessionNM, reportSpec, report);
                        reportSummary = NMResultsViewerUI.compactReportSummary(report);
                        if ~isstruct(reportSummary) || ~isscalar(reportSummary) % nm2-allow: NMResultsViewerReportTools summary is checked before browser response serialization across service boundary.
                            error('NMResultsViewerUI:InvalidReportSummaryShape', ...
                                ['Report Builder compact preview must be one scalar struct; ' ...
                                 'received %s with size %s.'], class(reportSummary), ...
                                mat2str(size(reportSummary)));
                        end
                        cacheStats = report.Metadata.ExecutionCache;
                        NMResultsViewerUI.profileLog(doProfile, ...
                            '[nm-prof]   report build cache payload hit/miss=%d/%d action hit/miss=%d/%d probability hit/miss=%d/%d persisted=%d\n', ...
                            cacheStats.payloadHits, cacheStats.payloadMisses, ...
                            cacheStats.actionHits, cacheStats.actionMisses, ...
                            cacheStats.probabilityHits, cacheStats.probabilityMisses, ...
                            cacheStats.probabilityPersistEvents);
                        NMResultsViewerUI.finishReportProgress(progressUI, 'Report payload built.');
                    catch ME
                        NMResultsViewerUI.failReportProgress(progressUI, 'Report Builder', ME);
                        rethrow(ME);
                    end
                    out = struct('ok',true,'message','Results Viewer report payload built and retained for export.', ...
                        'operation',op,'report',reportSummary,'reportHandle',reportHandle,'reportCache',cacheInfo);
                case {'results_viewer_report_script'}
                    handled = true;
                    reportSpec = NMResultsViewerUI.requestReportSpec(req);
                    [progressUI, progressCleanup] = NMResultsViewerUI.openReportProgressContext(tmpDir, req, 'Report script generation'); %#ok<NASGU>
                    try
                        NMResultsViewerUI.writeReportProgress('Report Builder', 'Generating editable MATLAB report recipe.', 92, 'script');
                        scriptSpec = NMResultsViewerUI.requestScriptSpec(req);
                        scriptText = NMResultsViewerReportTools.scriptFromReportSpec(reportSpec, scriptSpec);
                        settingsText = '';
                        settingsFunctionName = NMResultsViewerUI.requestTextField(scriptSpec,'SettingsFunctionName','NMResultsViewerReport_settings');
                        if NMResultsViewerUI.structField(scriptSpec,'IncludeSettingsCompanion',false)
                            settingsText = NMResultsViewerReportTools.settingsCompanionFromReportSpec(reportSpec, scriptSpec);
                        end
                        NMResultsViewerUI.finishReportProgress(progressUI, 'Report script generated.');
                    catch ME
                        NMResultsViewerUI.failReportProgress(progressUI, 'Report Builder', ME);
                        rethrow(ME);
                    end
                    out = struct('ok',true,'message','Results Viewer report script generated.', ...
                        'operation',op,'scriptText',scriptText,'settingsText',settingsText, ...
                        'settingsFunctionName',settingsFunctionName);
                case {'results_viewer_report_script_export'}
                    handled = true;
                    reportSpec = NMResultsViewerUI.requestReportSpec(req);
                    outputPath = NMResultsViewerUI.requestTextField(req,'outputPath','');
                    if isempty(outputPath)
                        error('NMResultsViewerUI:MissingReportScriptOutputPath','A MATLAB report-script output path is required.');
                    end
                    [folder,base,ext]=fileparts(outputPath);
                    if isempty(ext), ext='.m'; outputPath=fullfile(folder,[base ext]); end
                    if ~strcmpi(ext,'.m')
                        error('NMResultsViewerUI:InvalidReportScriptExtension','MATLAB report scripts must use the .m extension.');
                    end
                    if isempty(folder), folder=pwd; outputPath=fullfile(folder,[base ext]); end
                    scriptSpec = NMResultsViewerUI.requestScriptSpec(req);
                    includeSettings = NMResultsViewerUI.structField(scriptSpec,'IncludeSettingsCompanion',false);
                    suffix='_settings'; fnBase=matlab.lang.makeValidName(base);
                    maxBase=max(1,namelengthmax-numel(suffix)); if numel(fnBase)>maxBase, fnBase=fnBase(1:maxBase); end
                    settingsFunctionName=[fnBase suffix];
                    scriptSpec.SettingsFunctionName=settingsFunctionName;
                    scriptSpec.IncludeSettingsCompanion=logical(includeSettings);
                    scriptText=NMResultsViewerReportTools.scriptFromReportSpec(reportSpec,scriptSpec);
                    NMResultsViewerUI.writeTextFile(outputPath,scriptText);
                    settingsPath='';
                    if includeSettings
                        settingsText=NMResultsViewerReportTools.settingsCompanionFromReportSpec(reportSpec,scriptSpec);
                        settingsPath=fullfile(folder,[settingsFunctionName '.m']);
                        NMResultsViewerUI.writeTextFile(settingsPath,settingsText);
                    end
                    out=struct('ok',true,'message','MATLAB Report Builder files exported.', ...
                        'operation',op,'scriptPath',outputPath,'settingsPath',settingsPath, ...
                        'settingsFunctionName',settingsFunctionName);
                case {'results_viewer_report_export'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    reportSpec = NMResultsViewerUI.requestReportSpec(req);
                    exportSpec = NMResultsViewerUI.requestExportSpec(req);
                    requestedHandle = NMResultsViewerUI.requestTextField(req, 'reportHandle', '');
                    requestedSpecHash = NMResultsViewerUI.requestTextField(req, 'reportSpecHash', '');
                    [progressUI, progressCleanup] = NMResultsViewerUI.openReportProgressContext(tmpDir, req, 'Report export'); %#ok<NASGU>
                    try
                        NMResultsViewerUI.writeReportProgress('Report export', 'Preparing MATLAB report export.', 58, 'prepare_export');
                        cachedReport=struct(); cachedSpec=struct(); cacheHit=false; cacheMessage='No validated report cache identity was supplied.';
                        if ~isempty(strtrim(requestedHandle)) || ~isempty(strtrim(requestedSpecHash))
                            [cachedReport, cachedSpec, cacheHit, cacheMessage] = ...
                                NMResultsViewerUI.loadReportCache(tmpDir, sessionNM, requestedSpecHash, requestedHandle);
                        end
                        if cacheHit
                            NMResultsViewerUI.writeReportProgress('Report export', 'Reusing the validated report payload from the current Report Builder session.', 60, 'reuse_report');
                            effectiveSpec=cachedSpec;
                            effectiveSpecHash=requestedSpecHash;
                        elseif isempty(fieldnames(reportSpec)) && (~isempty(strtrim(requestedHandle)) || ~isempty(strtrim(requestedSpecHash)))
                            NMResultsViewerUI.finishReportProgress(progressUI, 'Report cache miss requires the prepared specification.');
                            out=struct('ok',true,'message',cacheMessage,'operation',op, ...
                                'reportHandle',requestedHandle,'reportSpecHash',requestedSpecHash, ...
                                'reportCacheHit',false,'reportCacheMessage',cacheMessage,'reportSpecRequired',true);
                            return;
                        else
                            if isempty(fieldnames(reportSpec))
                                reportSpec = NMResultsViewerReportTools.defaultReportSpec(sessionNM, NMResultsViewerUI.requestSpec(req));
                            end
                            NMResultsViewerUI.writeReportProgress('Report export', ['Report cache miss: ' cacheMessage ' Rebuilding explicitly from the supplied prepared specification.'], 60, 'rebuild_report');
                            cachedReport = NMResultsViewerReportTools.buildReport(sessionNM, reportSpec);
                            [requestedHandle, cacheInfo] = NMResultsViewerUI.storeReportCache(tmpDir, sessionNM, reportSpec, cachedReport);
                            effectiveSpec=reportSpec;
                            effectiveSpecHash=cacheInfo.specHash;
                        end
                        out = NMResultsViewerReportTools.exportReport(sessionNM, effectiveSpec, exportSpec, cachedReport);
                        out.reportHandle = requestedHandle;
                        out.reportSpecHash = effectiveSpecHash;
                        out.reportCacheHit = logical(cacheHit);
                        out.reportCacheMessage = cacheMessage;
                        out.reportSpecRequired = false;
                        NMResultsViewerUI.profileLog(doProfile, '[nm-prof]   report export payload cache hit=%d message=%s\n', double(cacheHit), cacheMessage);
                        NMResultsViewerUI.finishReportProgress(progressUI, 'Report export completed.');
                    catch ME
                        NMResultsViewerUI.failReportProgress(progressUI, 'Report export', ME);
                        rethrow(ME);
                    end
                    out.operation = op;
                case {'results_viewer_alpha_video_capabilities'}
                    handled = true;
                    out = NMResultsViewer3DVideoTools.capabilities();
                case {'results_viewer_alpha_video_prepare'}
                    handled = true;
                    out = NMResultsViewer3DVideoTools.prepare(tmpDir, req);
                case {'results_viewer_alpha_video_finalize'}
                    handled = true;
                    out = NMResultsViewer3DVideoTools.finalize(tmpDir, req);
                case {'results_viewer_alpha_video_cancel'}
                    handled = true;
                    out = NMResultsViewer3DVideoTools.cancel(tmpDir, req);
                case {'results_viewer_alpha_open_legacy'}
                    handled = true;
                    sessionNM = NMResultsViewerUI.loadSessionNMProfiled(NM, tmpDir, doProfile, op);
                    spec = NMResultsViewerUI.requestSpec(req);
                    idx = NMResultsViewerUI.scalarField(spec, 'analysisIndex', NaN);
                    if isnan(idx) || idx < 1, idx = NMResultsViewerUI.firstCompletedAnalysisIndex(sessionNM); end
                    if isnan(idx), error('NMResultsViewerUI:noCompletedAnalysis', 'Complete at least one analysis before opening the legacy NM Results Viewer.'); end
                    if exist('NM_Results_Viewer','file') ~= 2, error('NMResultsViewerUI:missingLegacyViewer', 'NM_Results_Viewer.m is not available on the MATLAB path.'); end % nm2-allow: NMResultsViewerUI verifies selected external MATLAB viewer and required deployed browser asset files exist.
                    NM_Results_Viewer('Analysis', idx, 'NM', sessionNM);
                    out = struct('ok',true,'message',sprintf('Legacy NM Results Viewer opened for analysis %d.', idx), ...
                        'operation',op,'analysisIndex',idx);
            end
        end

        function txt = htmlTextFromJson(stateJson)
            % htmlTextFromJson  Build the Results Viewer HTML shell and semantic UI regions.
            %
            % Creates regions for analysis selection, classification outputs, calibration/DCA, feature/QC
            % inspection, plots, tables and legacy fallback controls. JavaScript fills these regions from % nm2-allow: NMResultsViewerUI.export explicitly preserves standalone MATLAB viewer routing and required browser asset contracts.
            % state/payload service responses.

            jsState = NMPreprocUI.jsonTextForScript(stateJson);
            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NM2 Results Viewer</title>'
'<link rel="stylesheet" href="NMTrainTemplateUI.css">'
'<link rel="stylesheet" href="NMModuleNavigationRail.css">'
'<link rel="stylesheet" href="NMImageSliceViewer.css">'
'<link rel="stylesheet" href="NMModal.css">'
'<link rel="stylesheet" href="NMRuntimeProgressViewer.css">'
'<link rel="stylesheet" href="NMRuntimeGridPicker.css">'
'<link rel="stylesheet" href="NMResultsViewerUI.css">'
'<style>'
NMUIMessageTools.css()
'</style>'
'</head><body class="nmHasNavRail">'
'<header class="rvHeader"><div class="rvHeaderTitle"><div class="title">Results Viewer</div></div><div class="headerActions"><button id="finish" class="primary" type="button">Main menu</button></div></header>'
'<main class="rvShell">'
'  <section class="panel rvControls" id="rvAnalysisControlsPanel">'
'    <div class="rvControlsHeader"><span id="rvAnalysisControlsSummary" class="rvControlsSummary"></span><button id="toggleAnalysisControls" class="rvControlsCollapse" type="button" aria-expanded="true" aria-label="Collapse Results Viewer analysis controls" title="Collapse Results Viewer analysis controls"><img class="rvPanelIcon" src="NMResultsIconCollapse.svg" alt="" aria-hidden="true"></button></div>'
'    <div class="rvControlsBody">'
'      <div class="field" id="analysisField"><label for="analysisSelect">Analysis</label><div class="rvAnalysisSelectWrap"><select id="analysisSelect"></select></div></div>'
'      <div class="field" id="sourceField"><label for="sourceSelect">Source</label><select id="sourceSelect"></select></div>'
'      <div class="field" id="oocvSubgroupField"><label for="oocvSubgroupSelect">OOCV subgroup</label><select id="oocvSubgroupSelect"></select></div>'
'      <div class="field" id="modelSourceField"><label for="modelSourceSelect">Model source</label><select id="modelSourceSelect"></select></div>'
'      <div class="field" id="resultTypeField"><label for="resultTypeSelect">Result type</label><select id="resultTypeSelect"></select></div>'
'      <div class="field" id="classifierField"><label for="classifierSelect">Classifier / model</label><select id="classifierSelect"></select></div>'
'      <div class="field" id="targetField"><label for="targetSelect">Target</label><select id="targetSelect"></select></div>'
'      <div class="field rvHidden" id="featureContextField"><label for="featureContextSelect">Feature source</label><select id="featureContextSelect"></select></div>'
'      <div class="field rvHidden" id="backprojectionComponentField"><label for="backprojectionComponentSelect">Backprojected component</label><select id="backprojectionComponentSelect"></select></div>'
'    </div>'
'  </section>'
'  <section class="panel rvWorkspaceShell">'
'    <div class="rvWorkspaceTop"><div class="rvWorkspaceTitleRow"><h2 title="Move, resize, minimize, maximize or remove viewer panels. The auto-layout toggle keeps panels in non-overlapping positions.">Visual workspace</h2></div><div class="rvWorkspaceActions"><button id="openReportBuilder" type="button" title="Assemble an API-backed Results Viewer report">Report builder</button><button id="autoWorkspaceLayout" type="button" class="isActive" aria-pressed="true" title="Responsive dashboard is active; click to convert the current view to a manual free-canvas.">Dashboard layout</button><button id="saveWorkspaceLayout" type="button">Save view</button><button id="resetWorkspaceLayout" type="button">Reset layout</button></div></div>'
'    <div id="rvVisualWorkspace" class="rvVisualWorkspace"></div>'
'  </section>'
'</main>'
['<script>window.NM_RESULTS_VIEWER_ALPHA_STATE = ' jsState ';</script>']
'<script>window.NM_MODULE_NAV_CONTEXT = {currentModule:"results_alpha"};</script>'
'<script src="NMModuleIconSet.js"></script>'
'<script src="NMModuleNavigationRail.js"></script>'
'<script src="NMResultsViewerPrimitives.js"></script>'
'<script src="NMResultsPlotD3.js"></script>'
'<script src="NMResultsViewerModelOptimization.js"></script>'
'<script src="NMResultsViewerAnalysisSetSelector.js"></script>'
'<script src="NMRuntimeGridPicker.js"></script>'
'<script src="NMResultsViewerCrossAnalysis.js"></script>'
'<script src="NMExpressionTools.js"></script>'
'<script src="NMResultsViewerFeatureRibbon.js"></script>'
'<script src="NMResultsViewerFeatureGraphLabels.js"></script>'
'<script src="NMResultsViewerNodeLinkGraph.js"></script>'
'<script src="NMResultsViewerGraphPresentationControls.js"></script>'
'<script src="NMResultsViewerLightingControls.js"></script>'
'<script src="NMResultsViewerOutput.js"></script>'
'<script src="NMResultsViewerConnectivity3D.js"></script>'
'<script src="NMResultsViewerStructuralAnatomyControls.js"></script>'
'<script src="NMResultsViewerLabelledMatrix.js"></script>'
'<script src="NMResultsViewerPanelControls.js"></script>'
'<script src="NMResultsViewerControlHost.js"></script>'
'<script src="NMResultsViewerInteractionIdentity.js"></script>'
'<script src="NMResultsViewerFeatureRepresentations.js"></script>'
'<script src="NMImageSliceViewer.js"></script>'
'<script src="NMImagingVolumePrep.js"></script>'
'<script src="NMImagingVolumePrepClient.js"></script>'
'<script src="NMVolumeRaycastGL2.js"></script>'
'<script src="NMWebGLMeshPrograms.js"></script>'
'<script src="NMWebGLMeshRenderer.js"></script>'
'<script src="NMWebGLMeshInteraction.js"></script>'
'<script src="NMResultsViewerCommonMeshAdapter.js"></script>'
'<script src="NMResultsViewerSurfaceAdapter.js"></script>'
'<script src="NMImagingIsosurface.js"></script>'
'<script src="NMImagingDisplaySemantics.js"></script>'
'<script src="NMImagingVolumeRenderingContract.js"></script>'
'<script src="NMImagingExtrema.js"></script>'
'<script src="NMImagingFeatureSampling.js"></script>'
'<script src="NMImagingRoiRows.js"></script>'
'<script src="NMImagingThresholdEditor.js"></script>'
'<script src="NMImagingViewerState.js"></script>'
'<script src="NMImagingColorGradient.js"></script>'
'<script src="NMResultsViewerDisplayControls.js"></script>'
'<script src="NMResultsViewerViewControls.js"></script>'
'<script src="NMResultsViewerInformationControls.js"></script>'
'<script src="NMImaging2DWebGLRenderer.js"></script>'
'<script src="NMResultsViewer3DMontage.js"></script>'
'<script src="NMResultsViewer3DVideoMaker.js"></script>'
'<script src="NMResultsViewerImaging3DController.js"></script>'
'<script src="NMResultsViewerImagingViewer.js"></script>'
'<script src="NMModal.js"></script>'
'<script src="NMResultsViewerROIComparisonPlanner.js"></script>'
'<script src="NMResultsViewerROIMapper.js"></script>'
'<script src="NMRuntimeProgressViewer.js"></script>'
'<script>'
NMUIMessageTools.script()
'</script>'
'<script src="NMResultsViewerUI_main.js"></script>'
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function copyAssets(webDir)
            % Purpose: Copy the complete static Results Viewer browser asset set into a session web directory.
            % Syntax: NMResultsViewerUI.copyAssets(webDir)
            % Inputs: webDir is the destination directory for the active Results Viewer session.
            % Outputs: None; required JS/CSS/icon files are copied to webDir.
            % Authority and flow: The explicit asset list is the session packaging authority and includes the shared NMResultsViewerAnalysisSetSelector.js and NMResultsViewerCrossAnalysis.js modules with the existing Results Viewer modules.
            % Scientific/state contract: Static asset copying carries no scientific data and does not alter Scientific State/Annotation.
            % Invariants: Every listed required asset must exist; no directory scan or permissive missing-asset fallback is used. % nm2-allow: NMResultsViewerUI.export explicitly preserves standalone MATLAB viewer routing and required browser asset contracts.
            % Materialization and performance: O(number/size of static assets) file copies; does not parse XML, load scientific atlases/annotations/meshes, scan voxels/vertices, or create feature-scale arrays. Cold-session path only, not retained interaction.
            % Resource declaration: Reads and writes only static UI asset files; parses no XML; loads no scientific atlas/annotation/mesh resources; scans no voxels or vertices; creates no feature-scale arrays; cold-session setup only and not a retained interactive path.
            % Failure semantics: A missing required asset raises NMResultsViewerUI:MissingAsset.
            % Side effects: Writes static files into webDir only.
            % Consumers and dependencies: Results Viewer session bootstrap/browser HTML.
            src = fileparts(which('NMResultsViewerUI.m'));
            files = {'NMResultsViewerUI.css','NMResultsViewerUI_main.js','NMExpressionTools.js','NMResultsViewerFeatureRibbon.js','NMResultsViewerFeatureGraphLabels.js','NMResultsViewerNodeLinkGraph.js','NMResultsViewerGraphPresentationControls.js','NMResultsViewerLightingControls.js','NMResultsViewerOutput.js','NMResultsViewerConnectivity3D.js','NMResultsViewerStructuralAnatomyControls.js','NMResultsViewerLabelledMatrix.js','NMResultsViewerPanelControls.js','NMResultsViewerControlHost.js','NMResultsViewerInteractionIdentity.js','NMResultsViewerFeatureRepresentations.js','NMTrainTemplateUI.css', ...
                'NMModuleIconSet.js','NMModuleNavigationRail.js','NMModuleNavigationRail.css','NMResultsViewerPrimitives.js','NMResultsPlotD3.js','NMResultsViewerModelOptimization.js','NMResultsViewerAnalysisSetSelector.js','NMRuntimeGridPicker.js','NMRuntimeGridPicker.css','NMResultsViewerCrossAnalysis.js','NMImageSliceViewer.js','NMImageSliceViewer.css','NMWebGLMeshPrograms.js','NMWebGLMeshRenderer.js','NMWebGLMeshInteraction.js','NMResultsViewerCommonMeshAdapter.js','NMResultsViewerSurfaceAdapter.js','NMImagingVolumePrep.js','NMImagingVolumePrepClient.js','NMVolumeRaycastGL2.js','NMImagingVolumePrepWorker.js','NMImagingIsosurface.js','NMImagingIsosurfaceWorker.js','NMImagingDisplaySemantics.js','NMImagingVolumeRenderingContract.js','NMImagingExtrema.js','NMImagingFeatureSampling.js','NMImagingRoiRows.js','NMImagingThresholdEditor.js','NMImagingViewerState.js','NMImagingColorGradient.js','NMResultsViewerDisplayControls.js','NMResultsViewerViewControls.js','NMResultsViewerInformationControls.js','NMImaging2DWebGLRenderer.js','NMResultsViewer3DMontage.js','NMResultsViewer3DVideoMaker.js','NMResultsViewerImaging3DController.js','NMResultsViewerImagingViewer.js', ...
                'NMModal.js','NMModal.css','NMResultsViewerROIComparisonPlanner.js','NMResultsViewerROIMapper.js','NMRuntimeProgressViewer.js','NMRuntimeProgressViewer.css', ...
                'NMResultsIconExport.svg','NMResultsIconPrint.svg','NMResultsIconCollapse.svg','NMResultsIconRestore.svg','NMResultsIconMaximize.svg'};
            for i = 1:numel(files)
                s = fullfile(src, files{i});
                if exist(s,'file') ~= 2 % nm2-allow: NMResultsViewerUI verifies selected external MATLAB viewer and required deployed browser asset files exist.
                    error('NMResultsViewerUI:MissingAsset', ...
                        'Required Results Viewer asset is missing: %s',s);
                end
                copyfile(s, fullfile(webDir, files{i}), 'f');
            end
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the Results Viewer UI text-writer entry point.
            %
            %   NMResultsViewerUI.writeTextFile(path,txt) delegates generated Results Viewer shell output
            %   to NMSerializationTools. Result data exports remain handled by dedicated export tools.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMResultsViewerUI:writeFailed', 'Could not write %s', 'fwrite-input-char');
        end
    end

    methods (Static, Access = private)
        function op = requestOperation(req)
            op = '';
            if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation), op = char(string(req.operation)); % nm2-allow: NMResultsViewerUI.requestOperation and requestSpec validate optional browser-bridge request fields at the ingress boundary.
            elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action), op = char(string(req.action)); end % nm2-allow: NMResultsViewerUI.requestOperation and requestSpec validate optional browser-bridge request fields at the ingress boundary.
        end

        function spec = requestSpec(req)
            spec = struct();
            if ~isstruct(req), return; end % nm2-allow: NMResultsViewerUI.requestOperation and requestSpec validate optional browser-bridge request fields at the ingress boundary.
            if isfield(req,'spec') && isstruct(req.spec), spec = req.spec; end % nm2-allow: NMResultsViewerUI.requestOperation and requestSpec validate optional browser-bridge request fields at the ingress boundary.
            if isfield(spec,'selectionTransition')
                spec.selectionTransition = validatestring(spec.selectionTransition, ...
                    {'analysisSelect','resultTypeSelect','sourceSelect','modelSourceSelect', ...
                    'oocvSubgroupSelect','classifierSelect','targetSelect'}, ...
                    'NMResultsViewerUI.requestSpec','selectionTransition');
            end
            fields = {'analysisIndex','classifierIndex','targetIndex','source','resultType','graphType','plotSort','colorSwap','percentRank','probTransform','calibrationMethod','action','numBins','smoothCurve','calibrationMetric','maxProb','stepSize','selectedCaseIndex','multiClassModeIndex','binarizationThreshold','featureContextId','backprojectionComponentId','measureId','measureIds','displayGridPolicy','selectedTemplateId','selectedAtlasId','imagingModalityId','profile','profileEnabled','nmProfile'};
            for i=1:numel(fields)
                if isfield(req,fields{i}) && ~isempty(req.(fields{i})), spec.(fields{i}) = req.(fields{i}); end % nm2-allow: NMResultsViewerUI.requestOperation and requestSpec validate optional browser-bridge request fields at the ingress boundary.
            end
            % The QC browser service uses a raw outer envelope for these fields.
            % Canonicalize them once here; the nested viewer spec owns other selectors.
            if isfield(req,'operation') && strcmpi(req.operation,'results_viewer_alpha_subject_feature_qc')
                defaults = struct('caseId','','metricKey','subject_z', ...
                    'maxFeatures',200,'zThreshold',NaN,'sliceIndex',NaN);
                names = fieldnames(defaults);
                for j=1:numel(names)
                    name = names{j};
                    value = defaults.(name);
                    if isfield(req,name) && ~isempty(req.(name))
                        raw = req.(name);
                        if ischar(value)
                            value = char(string(raw));
                            if isempty(value), value = defaults.(name); end
                        elseif isnumeric(raw) || islogical(raw)
                            value = double(raw(1));
                        elseif ischar(raw) || isstring(raw)
                            value = str2double(string(raw(1)));
                        end
                        if isnumeric(value) && (~isscalar(value) || ~isfinite(value))
                            value = defaults.(name);
                        end
                    end
                    spec.(name) = value;
                end
            end
            % Browser analysis-set aliases converge at the registered ingress.
            if ~isfield(spec,'analysisIndices')
                spec.analysisIndices = [];
                if isfield(spec,'AnalysisIndices'), spec.analysisIndices = spec.AnalysisIndices; end
            end
            if ~isempty(spec.analysisIndices)
                if iscell(spec.analysisIndices)
                    spec.analysisIndices = cellfun(@double,spec.analysisIndices);
                end
                spec.analysisIndices = double(spec.analysisIndices(:)');
            end
            if strcmp(NMResultsViewerUI.requestOperation(req),'results_viewer_analysis_set_inventory') && isempty(spec.analysisIndices)
                error('NMResultsViewerUI:InvalidAnalysisSetIdentity', ...
                    'An explicit nonempty analysis set is required for the inventory request.');
            end

            % An omitted selector in a state refresh asks the scientific
            % catalogue for its first enabled entry. Do not turn omission into
            % an explicit classification/CV/target selection.
            operation = NMResultsViewerUI.requestOperation(req);
            stateRequest = any(strcmpi(operation, ...
                {'results_viewer_alpha_refresh','results_viewer_alpha_state'}));
            hadResultType = isfield(spec,'resultType') && ~isempty(spec.resultType);
            hadSource = isfield(spec,'source') && ~isempty(spec.source);
            hadTarget = isfield(spec,'targetIndex') && ~isempty(spec.targetIndex);
            % The browser cannot assert internal canonical materialization. Always
            % rebuild it from the received envelope at the registered ingress.
            if isfield(spec,'canonicalSpecVersion') % nm2-allow: requestSpec discards an untrusted browser-supplied internal specification marker.
                spec = rmfield(spec,'canonicalSpecVersion');
            end
            % State refresh materializes only selector/renderer metadata first;
            % explicit full requests retain their caller-selected scope.
            if stateRequest && ~isfield(spec,'featureInspectionPayloadScope')
                spec.featureInspectionPayloadScope = 'metadata';
            end
            % One browser ingress establishes the same typed plot coordinates as
            % the existing direct-MATLAB viewerPlotOptions producer. Empty
            % source/resultType during selector transitions must remain empty:
            % buildInitialState resolves them against the destination catalogue.
            [~, spec] = NMResultsViewerTools.viewerPlotOptions(spec);
            if stateRequest
                if ~hadResultType, spec.resultType = ''; end
                if ~hadSource, spec.source = ''; end
                if ~hadTarget, spec.targetIndex = NaN; end
            end

        end

        function reportSpec = requestReportSpec(req)
            % requestReportSpec  Extract a report specification from a browser request.
            %
            % req.reportSpec: component-based Results Viewer report specification
            %                 generated by the browser Report Builder or by an API
            %                 caller. The method returns an empty struct when absent
            %                 so the service dispatcher can request a default spec
            %                 explicitly instead of failing silently.
            reportSpec = struct();
            if isstruct(req) && isfield(req,'reportSpec') && ~isempty(req.reportSpec) % nm2-allow: NMResultsViewerUI.requestReportSpec validates optional browser Report Builder recipe at the service ingress.
                if ~isstruct(req.reportSpec) || ~isscalar(req.reportSpec) % nm2-allow: NMResultsViewerUI.requestReportSpec validates optional browser Report Builder recipe at the service ingress.
                    error('NMResultsViewerUI:InvalidReportSpecRequest','reportSpec must be one scalar struct.');
                end
                reportSpec = req.reportSpec;
            end
            % JSON transport encodes NaN as null, which decodes to []. Restore NaN in the numeric
            % fields of every component instance (componentInstanceTemplate) and in the captured
            % Feature Inspection component selection (serializeFeatureInspectionViewState), so report
            % code receives the same recipe schema as from MATLAB.
            if isfield(reportSpec,'Components') && isstruct(reportSpec.Components) % nm2-allow: NMResultsViewerUI.requestReportSpec restores the browser recipe at the service ingress.
                tmpl = NMResultsViewerReportTools.componentInstanceTemplate();
                names = fieldnames(tmpl);
                numericNames = names(structfun(@isnumeric,tmpl));
                capturedNames = {'selectedBackprojectionComponentIndex','selectedBackprojectionComponentColumn'};
                for ii = 1:numel(reportSpec.Components)
                    c = reportSpec.Components(ii);
                    for k = 1:numel(numericNames)
                        if isfield(c,'Instance') && isfield(c.Instance,numericNames{k}) && isempty(c.Instance.(numericNames{k}))
                            c.Instance.(numericNames{k}) = NaN;
                        end
                    end
                    for k = 1:numel(capturedNames)
                        if isfield(c,'Options') && isfield(c.Options,'BrowserFeatureInspectionViewState') && ...
                                isfield(c.Options.BrowserFeatureInspectionViewState,capturedNames{k}) && ...
                                isempty(c.Options.BrowserFeatureInspectionViewState.(capturedNames{k}))
                            c.Options.BrowserFeatureInspectionViewState.(capturedNames{k}) = NaN;
                        end
                    end
                    reportSpec.Components(ii) = c;
                end
            end
        end

    end

    methods (Static)
        function scriptSpec = requestScriptSpec(req)
            % Registered Results Viewer ingress: canonical report-script options.
            defaults = struct('NMVariableName','NM','ReportSpecVariableName','reportSpec', ...
                'ReportVariableName','report','ExecutionVariableName','execution', ...
                'OutputMatFile','','IncludeHeader',true,'FailIfNMNotFound',true, ...
                'ExportSpec',struct(),'ExportSpecVariableName','exportSpec', ...
                'ExportOutputVariableName','exportOut','IncludeSettingsCompanion',false, ...
                'SettingsFunctionName','NMResultsViewerReport_settings');
            input = struct();
            if isfield(req,'scriptSpec'),input=req.scriptSpec;end
            if ~isstruct(input) || ~isscalar(input)
                error('NMResultsViewerUI:InvalidReportScriptSpec','Script options must be a scalar struct.');
            end
            unknown=setdiff(fieldnames(input),fieldnames(defaults));
            if ~isempty(unknown)
                error('NMResultsViewerUI:UnknownReportScriptOption', ...
                    'Unknown script option(s): %s.',strjoin(unknown,', '));
            end
            names=fieldnames(input);
            for ii=1:numel(names)
                name=names{ii};defaults.(name)=input.(name);
            end
            scriptSpec=defaults;
            if ~isstruct(scriptSpec.ExportSpec) || ~isscalar(scriptSpec.ExportSpec)
                error('NMResultsViewerUI:InvalidReportScriptExport', ...
                    'Script ExportSpec must be a scalar struct.');
            end
        end

    end

    methods (Static, Access = private)
        function exportSpec = requestExportSpec(req)
            % requestExportSpec  Extract report-export options from a browser request.
            %
            % req.exportSpec.Format: requested report export format, for example html
            %                        or pdf.
            % req.exportSpec.OutputDirectory: target directory selected through the
            %                                 OS-native path picker.
            % req.exportSpec.IncludePayloadMat: optional MAT sidecar flag.
            exportSpec = struct();
            if isstruct(req) && isfield(req,'exportSpec') && ~isempty(req.exportSpec) % nm2-allow: NMResultsViewerUI.requestExportSpec validates optional browser export options at the service ingress.
                if ~isstruct(req.exportSpec) || ~isscalar(req.exportSpec) % nm2-allow: NMResultsViewerUI.requestExportSpec validates optional browser export options at the service ingress.
                    error('NMResultsViewerUI:InvalidExportSpecRequest','exportSpec must be one scalar struct.');
                end
                exportSpec = req.exportSpec;
            end
        end

        function taskId = requestProgressTaskId(req)
            % requestProgressTaskId  Extract the browser runtime-progress task id from a Report Builder request.
            %
            % The id is optional. When present, service operations write deterministic progress updates to tmpDir/progress/<taskId>.json so NMRuntimeProgressViewer can show the actual report component sequence.
            taskId = '';
            if ~isstruct(req), return; end % nm2-allow: NMResultsViewerUI.requestProgressTaskId validates and sanitizes browser task identifiers before writing files.
            if isfield(req,'progressTaskId') && ~isempty(req.progressTaskId) % nm2-allow: NMResultsViewerUI.requestProgressTaskId validates and sanitizes browser task identifiers before writing files.
                taskId = regexprep(char(string(req.progressTaskId)), '[^A-Za-z0-9_-]', ''); % nm2-allow: NMResultsViewerUI.requestProgressTaskId validates and sanitizes browser task identifiers before writing files.
            elseif isfield(req,'progress') && isstruct(req.progress) && isfield(req.progress,'taskId') && ~isempty(req.progress.taskId) % nm2-allow: NMResultsViewerUI.requestProgressTaskId validates and sanitizes browser task identifiers before writing files.
                taskId = regexprep(char(string(req.progress.taskId)), '[^A-Za-z0-9_-]', ''); % nm2-allow: NMResultsViewerUI.requestProgressTaskId validates and sanitizes browser task identifiers before writing files.
            end
            if numel(taskId) > 128, taskId = taskId(1:128); end
        end

        function [progressUI, cleanupObj] = openReportProgressContext(tmpDir, req, title)
            % openReportProgressContext  Activate the shared file-backed progress context for Report Builder service calls.
            %
            % The previous global UI context is restored automatically by the returned onCleanup object. This keeps report generation progress isolated from training/runtime progress state.
            progressUI = struct();
            cleanupObj = [];
            taskId = NMResultsViewerUI.requestProgressTaskId(req);
            if isempty(taskId)
                return;
            end
            global UI
            previousUI = UI;
            consoleEnabled = false;
            if isstruct(req) && isfield(req,'progressConsole') && ~isempty(req.progressConsole) % nm2-allow: NMResultsViewerUI.openReportProgressContext validates optional browser progress-console settings.
                value = req.progressConsole;
                if ~(islogical(value) || isnumeric(value)) || ~isscalar(value) % nm2-allow: NMResultsViewerUI.openReportProgressContext validates optional browser progress-console settings.
                    error('NMResultsViewerUI:InvalidReportProgressConsole','Report progressConsole must be a scalar logical/numeric value.');
                end
                consoleEnabled = logical(value);
            end
            opts = struct('source','results_report_builder', 'progressTitle',title, ...
                'progressLowerTitle','Current report component', 'chartEnabled',true, ...
                'chartMinIntervalSeconds',0, 'consoleEnabled',consoleEnabled, 'suppressNativeViewer',true);
            if strcmp(title,'Cluster selection'),opts.progressLowerTitle='Current k';end
            progressUI = NMRuntimeProgressTools.browserRuntimeContext(tmpDir, taskId, opts);
            UI = progressUI;
            cleanupObj = onCleanup(@() NMResultsViewerUI.restoreReportProgressContext(previousUI));
        end

        function restoreReportProgressContext(previousUI)
            % restoreReportProgressContext  Restore the global UI context after a Report Builder service call.
            global UI
            UI = previousUI;
        end

        function writeReportProgress(title, message, percent, phase)
            % writeReportProgress  Publish one deterministic Report Builder progress update if the shared progress context is active.
            NMRuntimeProgressTools.writeGenericProgressSafe(title, message, percent, phase);
        end

        function finishReportProgress(progressUI, message)
            % finishReportProgress  Mark the active Report Builder progress task as complete.
            if ~isempty(fieldnames(progressUI))
                NMRuntimeProgressTools.finish(progressUI, message, progressUI.progressTitle);
            end
        end

        function failReportProgress(progressUI, source, ME)
            % failReportProgress  Publish Report Builder progress failure details before rethrowing the real error.
            if ~isempty(fieldnames(progressUI))
                NMRuntimeProgressTools.fail(progressUI, source, ME);
            end
        end

        function count = printBrowserProfileEvents(req)
            % printBrowserProfileEvents  Print batched browser render timings under NM_UI_PROFILE.
            %
            % This profiling-only endpoint accepts fixed-schema event records from the Results Viewer
            % browser. It performs no NM reload, state construction, or scientific payload work.
            count = 0;
            if ~NMResultsViewerTools.profileEnabled(struct()) || ~isstruct(req) || ... % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                    ~isfield(req,'events') || isempty(req.events) % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                return;
            end
            events = req.events;
            if iscell(events) % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                for i = 1:numel(events)
                    count = count + NMResultsViewerUI.printOneBrowserProfileEvent(events{i});
                end
            elseif isstruct(events) % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                for i = 1:numel(events)
                    count = count + NMResultsViewerUI.printOneBrowserProfileEvent(events(i));
                end
            end
        end

        function printed = printOneBrowserProfileEvent(event)
            % printOneBrowserProfileEvent  Print one validated browser timing record.
            printed = 0;
            if ~isstruct(event) || ~isfield(event,'label') || ~isfield(event,'seconds') % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                return;
            end
            label = char(string(event.label)); % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
            seconds = double(event.seconds);
            if isempty(seconds) || ~isfinite(seconds(1)), return; end
            detail = '';
            if isfield(event,'detail') && ~isempty(event.detail) % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
                detail = char(string(event.detail)); % nm2-allow: NMResultsViewerUI.printBrowserProfileEvents parses optional browser-sent profiling records at the bridge boundary.
            end
            if isempty(detail)
                fprintf('[nm-prof] results viewer browser %s: %.3fs\n',label,seconds(1));
            else
                fprintf('[nm-prof] results viewer browser %s: %.3fs %s\n',label,seconds(1),detail);
            end
            printed = 1;
        end

        function sessionNM = loadSessionNMProfiled(NM, tmpDir, doProfile, op)
            % loadSessionNMProfiled  Profile the shared session loader, which returns NM on a cache miss.
            t = tic;
            [sessionNM, ok] = NMDataIOUI.loadSessionNM(NM, tmpDir);
            NMResultsViewerUI.profileLog(doProfile, ...
                '[nm-prof]   results viewer loadSessionNM op=%s: %.3fs (ok=%d)\n', ...
                op, toc(t), double(ok));
        end


        function profileLog(enabled, varargin)
            % profileLog  Emit Results Viewer timing diagnostics when the global profile switch is active.
            if ~enabled, return; end
            fprintf(varargin{:});
        end

        function txt = requestTextField(req, fieldName, fallback)
            % requestTextField  Read one scalar textual request field.
            txt = fallback;
            if isstruct(req) && isfield(req,fieldName) && ~isempty(req.(fieldName)) % nm2-allow: NMResultsViewerUI.requestTextField normalizes an optional field supplied by the browser or public API.
                txt = char(string(req.(fieldName))); % nm2-allow: NMResultsViewerUI.requestTextField normalizes an optional field supplied by the browser or public API.
            end
        end

        function summary = compactReportSummary(report)
            % compactReportSummary  Return one scalar Report Builder preview contract.
            %
            % The browser bridge accepts exactly one scalar report or report-summary
            % struct. Build this envelope through scalar initialization plus explicit
            % field assignments so array-valued component, context, warning or metadata
            % payloads cannot propagate their shape into the root summary. The complete
            % report remains in the request-local report cache and is not altered here.
            if ~isstruct(report) || ~isscalar(report) % nm2-allow: NMResultsViewerUI.compactReportSummary validates a report passed to the browser-service serialization boundary.
                error('NMResultsViewerUI:InvalidBuiltReportShape', ...
                    ['Report Builder compact preview requires one scalar built report; ' ...
                     'received %s with size %s.'], class(report), mat2str(size(report)));
            end

            compT = struct('Id','','Title','','Viewspace','','Status','unknown', ...
                'MissingReason','','TableNames',{{}},'Instance',struct());
            raw = report.Components;
            comps = repmat(compT,1,numel(raw));
            for ii=1:numel(raw)
                comps(ii).Id = raw(ii).Id;
                comps(ii).Title = raw(ii).Title;
                comps(ii).Viewspace = raw(ii).Viewspace;
                comps(ii).Status = raw(ii).Status;
                comps(ii).MissingReason = raw(ii).MissingReason;
                comps(ii).TableNames = fieldnames(raw(ii).Tables).';
                comps(ii).Instance = raw(ii).Instance;
            end

            summary = struct();
            summary.Kind = 'nm_results_viewer_report_summary';
            summary.SchemaVersion = 2;
            summary.Ok = report.Ok;
            summary.Title = report.Title;
            summary.Description = report.Description;
            summary.Context = NMResultsViewerUI.structField(report,'Context',struct());
            summary.Components = comps;
            summary.Warnings = report.Warnings;
            summary.Errors = report.Errors;
            summary.Metadata = report.Metadata;

            if ~isscalar(summary)
                error('NMResultsViewerUI:InvalidReportSummaryShape', ...
                    'Report Builder compact preview must remain scalar; received size %s.', ...
                    mat2str(size(summary)));
            end
        end

        function [state, cacheHit] = analysisSetInventory(NM,tmpDir,analysisIndices,spec)
            % Purpose: Return the authoritative Scientific State inventory for one canonical analysis set, reusing it within the active Results Viewer session.
            % Syntax: [state,cacheHit] = NMResultsViewerUI.analysisSetInventory(NM,tmpDir,analysisIndices,spec)
            % Inputs: NM is the current read-only session workspace; tmpDir identifies the Results Viewer session; analysisIndices is the requested set; spec carries selector defaults used by Scientific State inventory construction.
            % Outputs: state is the server-side Scientific State analysis_set inventory; cacheHit reports whether an already-resident inventory was reused.
            % Authority and flow: NMResultsViewerScientificState.forAnalysisSet remains the sole inventory constructor. This method owns only session residency keyed by canonical set identity and never reconstructs capabilities or CV equivalence.
            % Scientific/state contract: Resident state may be reused only inside the same Results Viewer session and for the exact canonical analysis set. Browser-provided Scientific State is never accepted as authority.
            % Invariants: At most one cached value per session/set key; cache entries contain authoritative server-built Scientific State; a changed NM session invalidates the session cache at the established persistence boundary.
            % Materialization and performance: Cache miss performs the documented O(A) capability inventory plus worst-case O(A^2) delegated CV grouping once. Cache hit performs only compact key lookup and O(A) identity validation; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans or feature-scale arrays are created here.
            % Resource declaration: Reads no files directly, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays. Suitable for retained Report Builder analysis switching after an explicit Query results action.
            % Failure semantics: Invalid sets fail in Scientific State construction; a resident entry whose Scientific State identity does not match its requested set fails explicitly rather than being silently reused or repaired.
            % Side effects: Updates only the bounded in-process Results Viewer analysis-set inventory cache.
            % Consumers and dependencies: results_viewer_analysis_set_inventory plus analysis_set/multi_analysis Report Builder catalogue requests; NMResultsViewerScientificState.forAnalysisSet and NMDataIOUI.sessionKey.
            cacheHit=false;
            % Scientific State validates and orders set membership on a cache miss;
            % a cache hit reuses the previously validated inventory by identity.
            canonical=NMResultsViewerUI.analysisSetIdentity(analysisIndices);
            sessionKey=NMDataIOUI.sessionKey(tmpDir);
            cacheKey=[sessionKey '|' canonical];
            entry=NMResultsViewerUI.analysisSetInventoryCacheStore('get',cacheKey,struct());
            if ~isempty(fieldnames(entry))
                % The cache owner verifies residency identity once. Report Builder
                % consumes the server-produced inventory without revalidating it.
                scope=entry.scientificState.scope;
                if ~strcmp(scope.type,'analysis_set') || ...
                        ~strcmp(scope.identity,canonical)
                    error('NMResultsViewerReportTools:AnalysisSetStateMismatch', ...
                        'The resident Scientific State inventory does not match the requested multi-analysis set. Query the analysis set again.');
                end
                state=entry.scientificState;cacheHit=true;return;
            end
            state=NMResultsViewerScientificState.forAnalysisSet(NM,analysisIndices,spec);
            canonical=state.scope.identity;
            cacheKey=[sessionKey '|' canonical];
            entry=struct('sessionKey',sessionKey,'analysisSetIdentity',canonical,'scientificState',state);
            NMResultsViewerUI.analysisSetInventoryCacheStore('set',cacheKey,entry);
        end

        function identity = analysisSetIdentity(analysisIndices)
            % Purpose: Build the deterministic cache identity for an unordered analysis set.
            % Syntax: identity = NMResultsViewerUI.analysisSetIdentity(analysisIndices)
            % Inputs: Numeric analysis indices.
            % Outputs: analysis_set:<comma-separated canonical ascending indices>.
            % Authority and flow: Identity normalizes only set membership; scientific availability remains owned by Scientific State.
            % Scientific/state contract: Set identity is cache/provenance metadata, not a CV or capability derivation.
            % Invariants: Input already has canonical unique completed indices; identity is deterministic.
            % Materialization and performance: O(A log A) compact numeric normalization; no scientific materialization or file/resource access.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; safe on retained service paths.
            % Failure semantics: Invalid indices are rejected by canonicalCompletedAnalysisSet before entry.
            % Side effects: None.
            % Consumers and dependencies: analysisSetInventory cache lookup only.
            indices=sort(analysisIndices(:)');
            identity=sprintf('analysis_set:%s',strjoin(arrayfun(@num2str,indices,'UniformOutput',false),','));
        end

        function value = analysisSetInventoryCacheStore(action,key,value)
            % Purpose: Maintain bounded session-resident Scientific State analysis-set inventories.
            % Syntax: value = NMResultsViewerUI.analysisSetInventoryCacheStore(action,key,value)
            % Inputs: action is set/get/remove/remove_session; key is a cache key or session key; value is the cache entry for set.
            % Outputs: Requested entry for get, otherwise the passed/default value.
            % Authority and flow: This is a residency mechanism only; NMResultsViewerScientificState.forAnalysisSet remains the scientific constructor and validation authority.
            % Scientific/state contract: Cached inventories are immutable server-built Scientific State values scoped to one Results Viewer session and canonical analysis set.
            % Invariants: Cache is bounded to eight inventories; session invalidation removes all matching entries; no cross-session reuse occurs.
            % Materialization and performance: O(1) map access except bounded O(8) eviction/session removal; no scientific materialization, file/resource access, or feature-scale allocations.
            % Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels/vertices and creates no feature-scale arrays; safe on retained service paths.
            % Failure semantics: Unknown actions fail explicitly; missing keys return the supplied default value.
            % Side effects: Mutates only this bounded process-local cache.
            % Consumers and dependencies: analysisSetInventory and NM session invalidation in handleMatlabService.
            persistent cache order
            if isempty(cache),cache=containers.Map('KeyType','char','ValueType','any');order=cell(1,0);end
            switch action
                case 'set'
                    if isKey(cache,key),order(strcmp(order,key))=[];end
                    cache(key)=value;order{end+1}=key;
                    while numel(order)>8
                        old=order{1};order(1)=[];remove(cache,old);
                    end
                case 'get'
                    if isKey(cache,key),value=cache(key);end
                case 'remove_session'
                    for ii=numel(order):-1:1
                        candidate=order{ii};
                        entry=cache(candidate);
                        if strcmp(entry.sessionKey,key)
                            remove(cache,candidate);order(ii)=[];
                        end
                    end
                otherwise
                    error('NMResultsViewerUI:InvalidAnalysisSetInventoryCacheAction','Unknown analysis-set inventory cache action "%s".',action);
            end
        end

        function [handle, info] = storeReportCache(tmpDir, NM, reportSpec, report)
            % Purpose: Retain one validated built report plus its exact prepared specification for subsequent export/API handoff.
            % Syntax: [handle,info] = NMResultsViewerUI.storeReportCache(tmpDir,NM,reportSpec,report)
            % Inputs: Session directory, read-only NM, already prepared Report Builder specification, and its built report payload.
            % Outputs: Opaque session-local handle plus compact cache metadata including the canonical spec identity hash.
            % Authority and flow: The prepared specification has already crossed the Report Builder planning/build trust boundary. Cache identity is derived once from the same specification after removing only rendered byte payloads; no scientific selector or representation is rediscovered here.
            % Scientific/state contract: Component/payload identities and admitted presentation bindings remain those validated during canonical planning/build. Browser-captured bytes are retained for the built report but are not themselves used as the cache key.
            % Invariants: One handle belongs to one Results Viewer session, one compact spec identity, and one NM revision fingerprint. The exact prepared specification is retained in-process for export/API reuse without JSON round-tripping.
            % Materialization and performance: O(C + compact presentation metadata) identity serialization; rendered dataUrl/svgText bytes are excluded, so cost is independent of captured artifact byte volume B. No scientific payload materialization or feature-scale scan occurs.
            % Resource declaration: Reads no files/resources and performs no atlas/mesh/voxel/vertex work; mutates only the bounded in-process report cache.
            % Failure semantics: Invalid report specifications fail in the canonical build path before this function; cache-store failures propagate explicitly.
            % Side effects: Replaces the current session's prior report-cache entry.
            % Consumers and dependencies: results_viewer_report_build/export and executeReport browser-adapter handoff.
            sessionKey = NMDataIOUI.sessionKey(tmpDir);
            identityJson = jsonencode(orderfields(NMResultsViewerUI.reportCacheIdentitySpec(reportSpec)));
            specHash = NMResultsViewerUI.hashText(identityJson);
            nmRevision = NMResultsViewerUI.reportNMRevision(NM, reportSpec);
            seed = sprintf('%s|%s|%s|%.17g',sessionKey,specHash,nmRevision,now);
            handle = ['rvrep_' NMResultsViewerUI.hashText(seed)];
            entry = struct('handle',handle,'sessionKey',sessionKey,'specHash',specHash, ...
                'preparedSpec',reportSpec,'nmRevision',nmRevision,'createdAt',now,'report',report);
            NMResultsViewerUI.reportCacheStore('remove_session',sessionKey,struct());
            NMResultsViewerUI.reportCacheStore('set',handle,entry);
            info = struct('handle',handle,'specHash',specHash,'nmRevisionHash',NMResultsViewerUI.hashText(nmRevision), ...
                'componentCount',numel(report.Components));
        end

        function [report, preparedSpec, ok, message] = loadReportCache(tmpDir, NM, requestedSpecHash, handle)
            % Purpose: Validate and retrieve one report cache entry without receiving or serializing the artifact-bearing prepared specification again.
            % Syntax: [report,preparedSpec,ok,message] = NMResultsViewerUI.loadReportCache(tmpDir,NM,requestedSpecHash,handle)
            % Inputs: Session directory, current NM, compact identity hash returned by the build, and opaque report handle.
            % Outputs: Cached report, exact prepared spec retained by MATLAB, cache-hit flag, and explicit status message.
            % Authority and flow: The caller-supplied hash is only a lookup assertion. MATLAB validates it against the hash computed during build and independently rechecks the current NM revision using the server-retained prepared spec.
            % Scientific/state contract: Browser state cannot authorize a scientific component or representation through this hash. Scientific/presentation admission occurred during the canonical plan/build path; cache reuse only proves identity with that already validated build.
            % Invariants: Handle, session, compact spec hash, and NM revision must all match. No artifact-bearing spec equality or browser-only bypass flag exists.
            % Materialization and performance: O(1) compact string comparison plus the established compact NM revision fingerprint; zero report-spec JSON serialization and zero rendered-artifact bridge transfer on a hit.
            % Resource declaration: Reads no report files/resources and performs no feature-scale work; accesses only in-process cache metadata and current NM revision metadata.
            % Failure semantics: Any mismatch returns ok=false with one deterministic reason; callers may rebuild only by supplying the canonical prepared specification explicitly.
            % Side effects: None.
            % Consumers and dependencies: results_viewer_report_export.
            report = struct(); preparedSpec = struct(); ok = false; message = '';
            if isempty(strtrim(handle))
                message = 'No report handle was supplied.';
                return;
            end
            if isempty(strtrim(requestedSpecHash))
                message = 'No report specification hash was supplied.';
                return;
            end
            entry = NMResultsViewerUI.reportCacheStore('get',handle,struct());
            if isempty(fieldnames(entry))
                message = 'The report handle is missing or has expired.';
                return;
            end
            sessionKey = NMDataIOUI.sessionKey(tmpDir);
            if ~strcmp(entry.sessionKey,sessionKey)
                message = 'The report handle belongs to a different Results Viewer session.';
                return;
            end
            if ~isfield(entry,'specHash') || ~strcmp(char(string(entry.specHash)),requestedSpecHash) % nm2-allow: NMResultsViewerUI.resolveReportCache checks optional cache entry specHash against canonical requested report identity.
                message = 'The report specification identity changed after the cached report was built.';
                return;
            end
            nmRevision = NMResultsViewerUI.reportNMRevision(NM, entry.preparedSpec);
            if ~strcmp(entry.nmRevision,nmRevision)
                message = 'The Results Viewer NM session changed after the cached report was built.';
                return;
            end
            report = entry.report;
            preparedSpec = entry.preparedSpec;
            ok = true;
            message = 'Validated report cache hit.';
        end

        function value = reportCacheStore(action, key, value)
            % reportCacheStore  Maintain a bounded in-process report payload cache.
            persistent cache order
            if isempty(cache)
                cache = containers.Map('KeyType','char','ValueType','any');
                order = cell(1,0);
            end
            switch action
                case 'set'
                    if isKey(cache,key)
                        order(strcmp(order,key)) = [];
                    end
                    cache(key) = value;
                    order{end+1} = key;
                    while numel(order) > 4
                        old = order{1}; order(1) = [];
                        remove(cache,old);
                    end
                case 'get'
                    if isKey(cache,key), value = cache(key); end
                case 'remove'
                    if isKey(cache,key), remove(cache,key); end
                    order(strcmp(order,key)) = [];
                case 'remove_session'
                    for ii=numel(order):-1:1
                        candidate = order{ii};
                        entry = cache(candidate);
                        if strcmp(entry.sessionKey,key)
                            remove(cache,candidate);
                            order(ii)=[];
                        end
                    end
                otherwise
                    error('NMResultsViewerUI:InvalidReportCacheAction','Unknown report cache action "%s".',action);
            end
        end

        function identity = reportCacheIdentitySpec(reportSpec)
            % Purpose: Derive the compact canonical Report Builder cache identity from one already prepared report specification.
            % Syntax: identity = NMResultsViewerUI.reportCacheIdentitySpec(reportSpec)
            % Inputs: Scalar prepared Report Builder specification after browser-adapter capture.
            % Outputs: Semantically identical specification metadata with rendered visual byte fields removed from ReportPresentationArtifact envelopes.
            % Authority and flow: This is cache identity only. It preserves component/payload ids, representation binding metadata, output ordering, analysis plans and artifact metadata/provenance while removing dataUrl/svgText byte payloads that are already retained in the cached built report/spec.
            % Scientific/state contract: No scientific or representation admissibility is inferred here; identity reflects the canonical plan/build result already validated upstream.
            % Invariants: Only rendered byte carriers are excluded. Changing component identity, payload coordinates, declared representation identity, artifact metadata/provenance, ordering, or layout changes the hash.
            % Materialization and performance: O(C) compact struct traversal and no O(B) rendered-byte serialization; MATLAB copy-on-write avoids copying unchanged artifact bytes before their fields are removed.
            % Resource declaration: Reads no files/resources and performs no scientific materialization.
            % Failure semantics: Non-scalar/non-struct report specs fail explicitly; malformed component/options shapes remain the responsibility of canonical Report Builder normalization/build.
            % Side effects: None.
            % Consumers and dependencies: storeReportCache only.
            if ~isstruct(reportSpec) || ~isscalar(reportSpec) % nm2-allow: NMResultsViewerUI.reportCacheIdentitySpec preserves optional ReportPresentationArtifact fields in normalized Report Builder specs.
                error('NMResultsViewerUI:InvalidReportCacheIdentitySpec', ...
                    'Report cache identity requires one scalar prepared report specification.');
            end
            identity = reportSpec;
            if ~isfield(identity,'Components') || ~isstruct(identity.Components), return; end % nm2-allow: NMResultsViewerUI.reportCacheIdentitySpec preserves optional ReportPresentationArtifact fields in normalized Report Builder specs.
            for ii=1:numel(identity.Components)
                if ~isfield(identity.Components(ii),'Options') || ~isstruct(identity.Components(ii).Options) || ... % nm2-allow: NMResultsViewerUI.reportCacheIdentitySpec preserves optional ReportPresentationArtifact fields in normalized Report Builder specs.
                        ~isscalar(identity.Components(ii).Options) || ...
                        ~isfield(identity.Components(ii).Options,'ReportPresentationArtifact') % nm2-allow: NMResultsViewerUI.reportCacheIdentitySpec preserves optional ReportPresentationArtifact fields in normalized Report Builder specs.
                    continue;
                end
                artifact = identity.Components(ii).Options.ReportPresentationArtifact;
                if ~isstruct(artifact) || ~isscalar(artifact), continue; end % nm2-allow: NMResultsViewerUI.reportCacheIdentitySpec preserves optional ReportPresentationArtifact fields in normalized Report Builder specs.
                removeFields = intersect({'dataUrl','svgText'},fieldnames(artifact),'stable');
                if ~isempty(removeFields), artifact = rmfield(artifact,removeFields); end
                identity.Components(ii).Options.ReportPresentationArtifact = artifact;
            end
        end

        function revision = reportNMRevision(NM, reportSpec)
            % reportNMRevision  Build a lightweight revision fingerprint for report inputs.
            idx = 1;
            if isstruct(reportSpec) && isfield(reportSpec,'AnalysisIndex') && ~isempty(reportSpec.AnalysisIndex) % nm2-allow: NMResultsViewerUI.reportNMRevision fingerprints user-loaded NM1.4 analysis structures and optional analysis focus.
                idx = max(1,round(double(reportSpec.AnalysisIndex(1))));
            end
            descriptor = struct('analysisCount',0,'analysisIndex',idx,'status',[], ...
                'gdSize',[],'visSize',[],'calibration',{{}},'oocvCalibration',{{}});
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis) % nm2-allow: NMResultsViewerUI.reportNMRevision fingerprints user-loaded NM1.4 analysis structures and optional analysis focus.
                descriptor.analysisCount = numel(NM.analysis);
                if idx <= numel(NM.analysis) && isstruct(NM.analysis{idx}) % nm2-allow: NMResultsViewerUI.reportNMRevision fingerprints user-loaded NM1.4 analysis structures and optional analysis focus.
                    A = NM.analysis{idx};
                    descriptor.status = NMResultsViewerUI.structField(A,'status',[]);
                    descriptor.gdSize = size(NMResultsViewerUI.structField(A,'GDdims',[]));
                    descriptor.visSize = size(NMResultsViewerUI.structField(A,'visdata',[]));
                    descriptor.calibration = NMResultsViewerUI.calibrationFingerprint(NMResultsViewerUI.structField(A,'GDdims',[]));
                    descriptor.oocvCalibration = NMResultsViewerUI.calibrationFingerprint(NMResultsViewerUI.structField(A,'OOCV',[]));
                end
            end
            revision = jsonencode(descriptor);
        end

        function rows = calibrationFingerprint(container)
            % calibrationFingerprint  Summarize persisted calibration artifacts without copying scores.
            nRows = NMResultsViewerUI.calibrationFingerprintCount(container);
            rows = cell(1,nRows);
            if nRows == 0, return; end
            [rows, written] = NMResultsViewerUI.calibrationFingerprintFill(container, '', rows, 0);
            rows = rows(1:written);
        end

        function n = calibrationFingerprintCount(container)
            % calibrationFingerprintCount  Count deterministic calibration fingerprint rows.
            n = 0;
            if iscell(container) % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                for ii=1:numel(container)
                    n = n + NMResultsViewerUI.calibrationFingerprintCount(container{ii});
                end
                return;
            end
            if ~isstruct(container), return; end % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
            for ii=1:numel(container)
                s = container(ii);
                if isfield(s,'Calibration') && isstruct(s.Calibration), n = n + 1; end % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                names = {'BinClass','BinResults'};
                for nn=1:numel(names)
                    if isfield(s,names{nn}) % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                        n = n + NMResultsViewerUI.calibrationFingerprintCount(s.(names{nn}));
                    end
                end
            end
        end

        function [rows, pos] = calibrationFingerprintFill(container, prefix, rows, pos)
            % calibrationFingerprintFill  Fill a preallocated calibration fingerprint buffer.
            if iscell(container) % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                for ii=1:numel(container)
                    childPrefix = sprintf('%s%d/',prefix,ii);
                    [rows,pos] = NMResultsViewerUI.calibrationFingerprintFill(container{ii},childPrefix,rows,pos);
                end
                return;
            end
            if ~isstruct(container), return; end % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
            for ii=1:numel(container)
                s = container(ii);
                structPrefix = prefix;
                if numel(container) > 1, structPrefix = sprintf('%s%d/',prefix,ii); end
                if isfield(s,'Calibration') && isstruct(s.Calibration) % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                    method = char(string(NMResultsViewerUI.structField(s.Calibration,'Method',''))); % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                    probs = NMResultsViewerUI.structField(s.Calibration,'Probabilities',[]);
                    pos = pos + 1;
                    rows{pos} = sprintf('%sCalibration:%s:%d',structPrefix,method,numel(probs));
                end
                names = {'BinClass','BinResults'};
                for nn=1:numel(names)
                    if isfield(s,names{nn}) % nm2-allow: NMResultsViewerUI.calibrationFingerprint traverses optional calibration containers persisted by NM1.4 model writers.
                        childPrefix = [structPrefix names{nn} '/'];
                        [rows,pos] = NMResultsViewerUI.calibrationFingerprintFill(s.(names{nn}),childPrefix,rows,pos);
                    end
                end
            end
        end

        function hash = hashText(txt)
            % hashText  Return a deterministic CRC-32 hexadecimal digest.
            bytes = unicode2native(txt,'UTF-8');
            crc = uint32(hex2dec('FFFFFFFF'));
            poly = uint32(hex2dec('EDB88320'));
            for ii=1:numel(bytes)
                crc = bitxor(crc,uint32(bytes(ii)));
                for bb=1:8
                    if bitand(crc,uint32(1)) ~= 0
                        crc = bitxor(bitshift(crc,-1),poly);
                    else
                        crc = bitshift(crc,-1);
                    end
                end
            end
            crc = bitcmp(crc);
            hash = lower(dec2hex(crc,8));
        end

        function value = structField(s, fieldName, fallback)
            % structField  Read a field from a scalar struct with an explicit fallback. % nm2-allow: NMResultsViewerUI.structField intentionally reads optional fields from persisted NM1.4 structures or browser execution responses.
            value = fallback;
            if isstruct(s) && ~isempty(s) && isfield(s,fieldName), value = s(1).(fieldName); end % nm2-allow: NMResultsViewerUI.structField and scalarField read optional persisted NM1.4 or external browser-result fields.
        end

        function x = scalarField(s, field, default)
            x = default;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field)) % nm2-allow: NMResultsViewerUI.structField and scalarField read optional persisted NM1.4 or external browser-result fields.
                v = double(s.(field)); if ~isempty(v), x = v(1); end
            end
        end

        function analind = firstCompletedAnalysisIndex(NM)
            analind = NaN;
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis), return; end % nm2-allow: NMResultsViewerUI.firstCompletedAnalysisIndex inspects user-loaded NM1.4 analyses with optional status.
            for ii = 1:numel(NM.analysis)
                A = NM.analysis{ii};
                if isstruct(A) && isfield(A,'status') && ~isempty(A.status) && any(double(A.status(:)) >= 1) % nm2-allow: NMResultsViewerUI.firstCompletedAnalysisIndex inspects user-loaded NM1.4 analyses with optional status.
                    analind = ii; return;
                end
            end
        end
    end
end
