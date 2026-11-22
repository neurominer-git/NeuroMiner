classdef NMPreprocUI
% NMPreprocUI
% Generic browser UI export/open helper for NMPreprocSequence.
% The UI is schema-driven: it knows nothing about individual preprocessing
% modules beyond the moduleSpecs supplied by the registry.

    methods (Static)
        function paths = export(seq, outDir, ctx)
            % export  Export the standalone preprocessing-sequence editor.
            %
            % Serializes module specification, current sequence state and workspace catalog, writes the
            % browser editor shell and copies renderer assets. This is the UI adapter around
            % NMPreprocSequence, not a preprocessing executor.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_preproc_ui'); end
            if nargin < 3 || isempty(ctx), ctx = NMPreprocUI.sequenceContext(seq); end
            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_preproc_ui');
            outDir = dirs.root; webRoot = dirs.webRoot; webDir = dirs.webDir;
            pyDir = dirs.pyDir; tmpDir = dirs.tmpDir;
            spec = seq.toUISpec(ctx);
            state = seq.toUIState();
            try
                workspace = NMWorkspaceTools.catalog('base', ctx);
            catch
                workspace = {};
            end
            specJson = NMConfigTools.writeJson(fullfile(tmpDir,'spec.json'), spec);
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(tmpDir,'param.json'), ...              % immutable launch snapshot
                fullfile(tmpDir,'current_config.json')}, ...    % authoritative live UI state
                state, 'preproc state');
            workspaceJson = NMConfigTools.writeJson(fullfile(tmpDir,'workspace.json'), workspace);
            NMPreprocUI.writeHtmlFromJson(fullfile(webDir,'nm_preproc_pipeline_ui.html'), ...
                specJson, stateJson, workspaceJson);
            NMPreprocUI.writeBridge(fullfile(pyDir,'nm_bridge_server.py'));
            paths = struct('root',outDir,'webRoot',webRoot,'webDir',webDir,'tmpDir',tmpDir, ...
                'html',fullfile(webDir,'nm_preproc_pipeline_ui.html'), ...
                'spec',fullfile(tmpDir,'spec.json'), ...
                'initialState',fullfile(tmpDir,'param.json'), ...
                'state',fullfile(tmpDir,'current_config.json'), ...
                'current',fullfile(tmpDir,'current_config.json'), ...
                'workspace',fullfile(tmpDir,'workspace.json'), ...
                'updated',fullfile(tmpDir,'current_config.json'));
        end

        function updatedSeq = importUpdated(seq, updatedPath, ctx)
            % importUpdated  Import an edited preprocessing sequence from browser output.
            %
            % Reads the updated JSON state produced by the editor and converts it back into an
            % NMPreprocSequence object. If no update is present, the original sequence is returned
            % unchanged.

            if nargin < 3 || isempty(ctx), ctx = NMPreprocUI.sequenceContext(seq); end
            if ~exist(updatedPath,'file')
                error('NMPreprocUI:missingFile','No updated UI state file: %s', updatedPath);
            end
            state = NMConfigTools.readJson(updatedPath);
            state = NMConfigTools.charifyStrings(state);
            seq.applyUIState(state, ctx);
            updatedSeq = seq;
        end

        function seq = open(seq, outDir, ctx, port)
            % open  Export this UI and launch it through the local browser bridge.
            %
            % Combines export, bridge startup and post-close import so callers can use the component
            % interactively from MATLAB without manually managing temporary UI directories.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_preproc_ui'); end
            if nargin < 3 || isempty(ctx), ctx = NMPreprocUI.sequenceContext(seq); end
            if nargin < 4, port = []; end
            paths = NMPreprocUI.export(seq, outDir, ctx);
            handler = @(req, tmpDir) NMPreprocUI.handleMatlabService(req, tmpDir, ctx, seq.Registry, seq.RuleSet);
            state = nm_open_ui(paths.webDir, port, 'nm_preproc_pipeline_ui.html', handler);
            if ~isempty(state)
                seq.applyUIState(state, ctx);
            end
        end

        function [handled, out] = handleMatlabService(req, tmpDir, ctx, registry, ruleset)
            % handleMatlabService  Supply MATLAB-owned preprocessing context to browser services.
            if nargin < 4 || isempty(registry), registry = NMModuleRegistry.default(); end
            if nargin < 5 || isempty(ruleset), ruleset = NMPreprocRuleSet.default(); end
            handled = false;
            out = struct();
            op = '';
            if isstruct(req) && isfield(req,'operation') && ~isempty(req.operation)
                op = char(string(req.operation));
            elseif isstruct(req) && isfield(req,'action') && ~isempty(req.action)
                op = char(string(req.action));
            end
            switch lower(op)
                case 'rankfeat_import_external_file'
                    handled = true;
                    cfg = struct();
                    if isfield(req,'config') && isstruct(req.config), cfg = NMConfigTools.charifyStrings(req.config); end
                    mod = NMRankFeatModule();
                    out = mod.importExternalRankingForUI(cfg, ctx, tmpDir);
                case 'preproc_resolve_rule_state'
                    handled = true;
                    if ~isfield(req,'state') || ~isstruct(req.state)
                        error('NMPreprocUI:missingRuleState','Rule projection requires the current preprocessing STATE.');
                    end
                    state = NMConfigTools.charifyStrings(req.state);
                    pp = NMPreprocOrchestrator(registry,ruleset,ctx);
                    pp.applyUIState(state,ctx);
                    out = struct('ok',true,'ruleProjection',pp.ruleProjection(~isfield(req,'draft') || ~req.draft));
                otherwise
                    return;
            end
        end

        function ctx = sequenceContext(seq)
            % sequenceContext  Build context metadata for a preprocessing sequence editor session.
            %
            % Extracts module labels, workspace information and launch metadata used while rendering the
            % module form. It keeps UI context separate from the sequence object itself.

            ctx = struct();
            try
                if isobject(seq) && isprop(seq,'Context') && ~isempty(seq.Context)
                    ctx = seq.Context;
                elseif isstruct(seq) && isfield(seq,'Context') && ~isempty(seq.Context)
                    ctx = seq.Context;
                end
            catch
                ctx = struct();
            end
        end

        function writeHtml(path, spec, state, workspace)
            % writeHtml  Write the preprocessing editor HTML from MATLAB values.
            %
            % Serializes the module spec, sequence state and workspace catalog to JSON strings, then
            % delegates to writeHtmlFromJson. This method is used when callers have MATLAB structs rather
            % than prewritten JSON files.

            if nargin < 2, spec = struct(); end
            if nargin < 3, state = struct(); end
            if nargin < 4, workspace = {}; end
            NMPreprocUI.writeHtmlFromJson(path, ...
                NMConfigTools.encodeJson(spec, 'embedded spec'), ...
                NMConfigTools.encodeJson(state, 'embedded state'), ...
                NMConfigTools.encodeJson(workspace, 'embedded workspace'));
        end

        function writeHtmlFromJson(path, specJson, stateJson, workspaceJson)
            % writeHtmlFromJson  Write the preprocessing editor HTML from JSON payloads.
            %
            % Embeds already serialized spec/state/workspace payloads into the standalone editor shell.
            % It is the low-level writer used by export and by template child-page preparation.

            if nargin < 2 || isempty(specJson), specJson = '{}'; end
            if nargin < 3 || isempty(stateJson), stateJson = '{}'; end
            if nargin < 4 || isempty(workspaceJson), workspaceJson = '[]'; end

            webDir = fileparts(path);
            assets = {'NMPreprocUI.css','NMExpressionTools.js','NMPreprocUI_main.js', ...
                'NMSequenceBuilder.js','NMSequenceBuilder.css','NMContextHelp.js','ML_Context_Help.html','Preproc_Context_Help.html'};
            for i = 1:numel(assets)
                NMPreprocUI.writeTextFile(fullfile(webDir,assets{i}),NMPreprocUI.assetText(assets{i}));
            end

            txt = NMPreprocUI.htmlText();
            [~, pageName] = fileparts(path);
            loadingKind = 'preprocessing';
            if strcmp(pageName, 'nm_train_ml_ui')
                loadingKind = 'ML';
            end
            txt = strrep(txt, '__NM_EDITOR_LABEL__', loadingKind);
            txt = strrep(txt, '__NM_SPEC_JSON__', NMPreprocUI.jsonTextForScript(specJson));
            txt = strrep(txt, '__NM_STATE_JSON__', NMPreprocUI.jsonTextForScript(stateJson));
            txt = strrep(txt, '__NM_WORKSPACE_JSON__', NMPreprocUI.jsonTextForScript(workspaceJson));
            NMPreprocUI.writeTextFile(path, txt);
        end

        function writeBridge(path)
            % writeBridge  Write the Python bridge server used by NM browser pages.
            %
            % Copies the embedded bridge implementation to the session python directory so
            % MATLAB-launched browser pages can communicate with MATLAB services. It does not start the
            % bridge itself.

            nm_ui_bridge_write_server(path);
        end

        function txt = jsonForScript(value)
            % jsonForScript  Serialize a MATLAB value for safe JavaScript embedding.
            %
            % Converts MATLAB state/spec structs to JSON and applies escaping expected by the HTML shell.
            % It is used only for bootstrap data, not for persistent NM storage.

            txt = NMPreprocUI.jsonTextForScript(NMConfigTools.encodeJson(value, 'embedded UI JSON'));
        end

        function txt = jsonTextForScript(txt)
            % jsonTextForScript  Escape an existing JSON string for script embedding.
            %
            % Normalizes slashes and script-ending sequences so JSON can be embedded inside generated
            % HTML without prematurely closing the script block.

            txt = strrep(char(txt), '</', '<\/');
        end

        function txt = htmlText()
            % htmlText  Return the standalone preprocessing editor HTML template.
            %
            % Provides the static browser document used by the renderer after JSON payload placeholders
            % are inserted. Dynamic module fields are rendered by JavaScript from the serialized
            % spec/state.

            nl = newline;
            L = { ...
'<!doctype html>'
'<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
'<title>NeuroMiner preprocessing pipeline</title>'
'<link rel="stylesheet" href="NMPreprocUI.css">'
'<link rel="stylesheet" href="NMSequenceBuilder.css">'
'<style>'
NMUIMessageTools.css()
'body.editor-loading > header, body.editor-loading > .layout { display:none; }'
'#editorLoading { padding:32px 24px; color:#475569; font:16px system-ui; }'
'body:not(.editor-loading) > #editorLoading { display:none; }'
'</style>'
'</head><body class="editor-loading">'
'<div id="editorLoading" role="status">Loading __NM_EDITOR_LABEL__ configurator...</div>'
'<header><div><b>NeuroMiner preprocessing pipeline</b></div><div class="row"><button id="exportMatrixScaffold">Export MATLAB scaffold</button><button id="finish" class="primary">Finish / close module</button></div></header>'
'<div class="layout"><aside><div class="stagepanel" id="globalPanel"><h3>Label / target preprocessing</h3><div class="stagehint">Global label and target transformations that are applied outside the ordered preprocessing steps.</div><div id="globalOptions"></div></div><div class="stagepanel" id="subjectPanel"><h3>Subject-specific preprocessing</h3><div class="stagehint">Applied once per subject before cross-validation splitting.</div><div class="row"><select id="subjectModuleSelect"></select><button id="subjectAddBtn">Add</button><button id="subjectInsertBtn">Insert</button></div><div id="subjectSteps"></div></div><div class="stagepanel" id="cvPanel"><h3>CV-bound preprocessing</h3><div class="stagehint">Estimated and/or applied independently within the cross-validation training process.</div><div class="row"><select id="cvModuleSelect"></select><button id="cvAddBtn">Add</button><button id="cvInsertBtn">Insert</button></div><div id="cvSteps"></div></div></aside><main><div id="editorGrid" class="editorgrid nohelp"><div><div id="breadcrumb" class="crumb"></div><div id="editor"></div></div></div></main></div>'
'<script>'
'window.NM_EMBEDDED_SPEC = __NM_SPEC_JSON__;'
'window.NM_EMBEDDED_STATE = __NM_STATE_JSON__;'
'window.NM_EMBEDDED_WORKSPACE = __NM_WORKSPACE_JSON__;'
'</script>'
'<script>'
NMUIMessageTools.script()
'</script>'
'<script src="NMExpressionTools.js"></script>'
'<script src="NMSequenceBuilder.js"></script>'
'<script src="NMContextHelp.js"></script>'
'<script src="NMPreprocUI_main.js"></script>'
'</body></html>'};
            txt = strjoin(L, nl);
        end

        function txt = assetText(fileName)
            % assetText  Read a preprocessing editor asset from the UI directory.
            %
            % Loads JavaScript or CSS text used by the standalone renderer when embedding assets
            % directly. Missing files raise normal MATLAB file errors rather than being silently ignored.

            classDir = fileparts(mfilename('fullpath'));
            assetPath = fullfile(classDir, fileName);
            if ~exist(assetPath, 'file')
                error('NMPreprocUI:missingAsset', ...
                    'Required UI asset not found: %s. Keep %s next to NMPreprocUI.m.', assetPath, fileName);
            end
            txt = fileread(assetPath);
        end

        function writeTextFile(path, txt)
            % writeTextFile  Preserve the preprocessing configurator UI text-writer entry point.
            %
            %   NMPreprocUI.writeTextFile(path,txt) delegates generated HTML, JavaScript and bridge text
            %   output to NMSerializationTools while keeping NMPreprocUI:writeFile diagnostics.
            NMSerializationTools.writeTextFile(path, txt, ...
                'NMPreprocUI:writeFile', 'Could not write %s.', 'fwrite-input-char');
        end
    end
end
