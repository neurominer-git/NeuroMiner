classdef NMTrainConfigUI
% NMTrainConfigUI
% -------------------------------------------------------------------------
% Browser UI export/open helper for the modular training-configuration layer.
% v5 currently exposes the ML learner panel only, using the existing
% NMPreprocUI renderer assets plus the fixed-section-card layout declared by
% NMMLModule.configSpec().
% -------------------------------------------------------------------------

    methods (Static)
        function paths = export(orch, outDir, ctx)
            % export  Export the single-module training-configuration editor.
            %
            % Serializes the orchestrator module specification and state, writes the HTML renderer and
            % copies shared training-template assets. This UI edits one configuration module outside the
            % full template configurator.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_train_config_ui'); end
            if nargin < 3, ctx = struct(); end
            if nargin < 1 || isempty(orch)
                orch = NMTrainConfigOrchestrator.fromNM(struct(), [], ctx);
            end
            if ~isa(orch, 'NMTrainConfigOrchestrator')
                error('NMTrainConfigUI:invalidInput', 'Expected an NMTrainConfigOrchestrator object.');
            end

            dirs = NMUISessionTools.resolve(outDir, ctx, 'nm_train_config_ui');
            outDir = dirs.root; webRoot = dirs.webRoot; webDir = dirs.webDir;
            pyDir = dirs.pyDir; tmpDir = dirs.tmpDir;

            ui = orch.ui_configure(ctx);
            spec = ui.spec;
            state = ui.state;
            try
                workspace = NMWorkspaceTools.catalog('base', ctx);
            catch
                workspace = {};
            end

            specJson = NMConfigTools.writeJson(fullfile(tmpDir,'spec.json'), spec);
            stateJson = NMConfigTools.writeJsonAliases({ ...
                fullfile(tmpDir,'param.json'), ...
                fullfile(tmpDir,'current_config.json')}, state, 'ml state');
            workspaceJson = NMConfigTools.writeJson(fullfile(tmpDir,'workspace.json'), workspace);

            % The HTTP launcher now accepts a caller-specific HTML entry
            % point.  Keep the training-configuration page distinct from the
            % preprocessing page rather than relying on the preprocessing file
            % name as an alias.
            trainHtml  = fullfile(webDir,'nm_train_ml_ui.html');
            NMPreprocUI.writeHtmlFromJson(trainHtml, specJson, stateJson, workspaceJson);
            NMPreprocUI.writeBridge(fullfile(pyDir,'nm_bridge_server.py'));
            NMTrainConfigUI.copyRendererAssets(webDir);

            paths = struct('root',outDir,'webRoot',webRoot,'webDir',webDir,'tmpDir',tmpDir, ...
                'html',trainHtml, ...
                'trainHtml',trainHtml, ...
                'spec',fullfile(tmpDir,'spec.json'), ...
                'initialState',fullfile(tmpDir,'param.json'), ...
                'state',fullfile(tmpDir,'current_config.json'), ...
                'current',fullfile(tmpDir,'current_config.json'), ...
                'workspace',fullfile(tmpDir,'workspace.json'), ...
                'updated',fullfile(tmpDir,'current_config.json'));
        end

        function orch = importUpdated(orch, updatedPath, ctx)
            % importUpdated  Import edited training-module state into the orchestrator.
            %
            % Reads the browser output JSON and applies it to the provided module orchestrator when
            % available. If the browser produced no update, the original orchestrator is returned
            % unchanged.

            if nargin < 3, ctx = struct(); end
            if nargin < 1 || isempty(orch)
                orch = NMTrainConfigOrchestrator.fromNM(struct(), [], ctx);
            end
            if ~exist(updatedPath,'file')
                error('NMTrainConfigUI:missingFile','No updated UI state file: %s', updatedPath);
            end
            state = NMConfigTools.readJson(updatedPath);
            state = NMConfigTools.charifyStrings(state);
            [state, report] = orch.ML.validateConfig(state, orch.context(ctx), false);
            if ~report.ok
                error('NMTrainConfigUI:invalidState','Updated ML UI state is invalid:\n%s', strjoin(report.errors, newline));
            end
            orch.MLConfig = state;
        end

        function orch = open(orch, outDir, ctx, port)
            % open  Launch the single-module training-configuration editor.
            %
            % Exports the module editor, starts the browser bridge and imports edited state after
            % closure. This is the interactive wrapper around export/importUpdated for power users
            % editing a module directly.

            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_train_config_ui'); end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            paths = NMTrainConfigUI.export(orch, outDir, ctx);
            state = nm_open_ui(paths.webDir, port, 'nm_train_ml_ui.html');
            if ~isempty(state)
                NMConfigTools.writeJson(paths.updated, state);
                orch = NMTrainConfigUI.importUpdated(orch, paths.updated, ctx);
            end
        end

        function copyRendererAssets(webDir)
            % copyRendererAssets  Copy shared renderer assets for training configuration pages.
            %
            % Copies the JavaScript and CSS used by the training-config and template editors into the
            % exported web directory. It centralizes page packaging but does not affect module state.

            srcDir = fileparts(mfilename('fullpath'));
            assets = {'NMExpressionTools.js','NMPreprocUI_main.js','NMPreprocUI.css','NMSequenceBuilder.js','NMSequenceBuilder.css'};
            for i = 1:numel(assets)
                src = fullfile(srcDir, assets{i});
                if exist(src,'file') == 2
                    copyfile(src, fullfile(webDir, assets{i}), 'f');
                end
            end
        end
    end
end
