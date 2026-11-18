classdef NMSAVTools
% NMSAVTools
% -------------------------------------------------------------------------
% Browser-port helper for legacy nk_SavingOptions_config.m and the adjacent
% TrainParam verbosity toggle from nk_TrainClass_config.m.
%
% Legacy targets:
%   NM.TrainParam.SAV.savemodel
%   NM.TrainParam.SAV.matname
%   NM.TrainParam.verbosity
% -------------------------------------------------------------------------

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the saving/verbosity branch.
            %
            % Merges state/name-value inputs with stateFromNM, applies aliases and normalization, then materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the documented legacy target NM.TrainParam.SAV and NM.TrainParam.verbosity and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            
            defaultState = NMSAVTools.stateFromNM(NM);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.savDirty = true; end
            try
                NM = NMSAVTools.applyToNM(NM, state);
                if isempty(report.message), report.message = 'NMSAVTools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public saving/verbosity configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMSAVTools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted saving/verbosity configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.SAV and NM.TrainParam.verbosity. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.savSaveModel = 'Logical true/false: save trained model files (TrainParam.SAV.savemodel).';
            opts.savMatName = 'Text output filename prefix (TrainParam.SAV.matname).';
            opts.verbosity = 'Logical true/false: show training messages (TrainParam.verbosity).';
            h = NMConfigureAPITools.helpStruct('NMSAVTools.cli_configure', ...
                '[NM, state, report] = NMSAVTools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMSAVTools.configure(NM, ''savSaveModel'',true, ''verbosity'',true);'}, struct());
            h.validationRules = {'Saving/verbosity are logical settings; no additional symbolic category mapping.'};
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the saving/verbosity branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMSAVTools.cli_configureHelp();
        end

        function state = stateFromNM(NM)
            % stateFromNM  Reconstruct saving/verbosity browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.SAV and NM.TrainParam.verbosity and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            state = struct();
            defaultName = NMSAVTools.defaultMatName(NM);
            savemodel = 0;
            matname = defaultName;
            verbosity = 1;
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                if isfield(NM.TrainParam,'SAV') && isstruct(NM.TrainParam.SAV)
                    SAV = NM.TrainParam.SAV;
                    if isfield(SAV,'savemodel') && ~isempty(SAV.savemodel)
                        savemodel = NMSAVTools.logical01(SAV.savemodel, 0);
                    end
                    if isfield(SAV,'matname') && ~isempty(SAV.matname)
                        matname = char(string(SAV.matname));
                    end
                end
                if isfield(NM.TrainParam,'verbosity') && ~isempty(NM.TrainParam.verbosity)
                    verbosity = NMSAVTools.logical01(NM.TrainParam.verbosity, 1);
                end
            end
            state.savSaveModel = logical(savemodel);
            state.savMatName = matname;
            state.savDefaultMatName = defaultName;
            state.verbosity = logical(verbosity);
            state.verbosityValue = double(logical(verbosity));
            state.savDirty = false;
            state.savSummary = NMSAVTools.summarySaving(state);
            state.verbositySummary = NMSAVTools.summaryVerbosity(state);
        end


        function [SAV, verbosity] = defaultSetting(NM)
            % defaultSetting  Public legacy default for nk_SavingOptions_config plus the.
            %
            % adjacent TrainParam.verbosity flag.
            if nargin < 1 || isempty(NM), NM = struct(); end
            state = NMSAVTools.stateFromNM(NM);
            SAV = struct('savemodel', double(logical(state.savSaveModel)), ...
                         'matname', char(string(state.savMatName)));
            verbosity = double(logical(state.verbosity));
        end

        function state = stateFromMenu(NM, current, menuState)
            % stateFromMenu  Translate browser saving/verbosity controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            if nargin < 1, NM = struct(); end
            if nargin < 2 || isempty(current) || ~isstruct(current)
                current = NMSAVTools.stateFromNM(NM);
            end
            state = current;
            if nargin < 3 || isempty(menuState) || ~isstruct(menuState)
                state = NMSAVTools.finalizeState(NM, state);
                return;
            end
            src = menuState;
            if isfield(menuState,'sav') && isstruct(menuState.sav)
                src = menuState.sav;
            end
            if isfield(src,'savSaveModel')
                state.savSaveModel = logical(NMSAVTools.logical01(src.savSaveModel, state.savSaveModel));
            end
            if isfield(src,'savMatName')
                state.savMatName = char(string(src.savMatName));
            end
            if isfield(src,'verbosity')
                state.verbosity = logical(NMSAVTools.logical01(src.verbosity, state.verbosity));
            elseif isfield(src,'verbosityValue')
                state.verbosity = logical(NMSAVTools.logical01(src.verbosityValue, state.verbosity));
            end
            if isfield(src,'savDirty')
                state.savDirty = logical(src.savDirty);
            end
            state = NMSAVTools.finalizeState(NM, state);
        end

        function NM = applyToNM(NM, state)
            % applyToNM  Materialize saving/verbosity settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.SAV and NM.TrainParam.verbosity at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.savMatName: carries the sav mat name value between browser/API state and legacy NeuroMiner structures.
            % state.savSaveModel: carries the sav save model value between browser/API state and legacy NeuroMiner structures.
            % state.verbosity: carries the verbosity value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state)
                state = NMSAVTools.stateFromNM(NM);
            else
                state = NMSAVTools.finalizeState(NM, state);
            end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam)
                NM.TrainParam = struct();
            end
            if ~isfield(NM.TrainParam,'SAV') || ~isstruct(NM.TrainParam.SAV)
                NM.TrainParam.SAV = struct();
            end
            NM.TrainParam.SAV.savemodel = double(logical(state.savSaveModel));
            NM.TrainParam.SAV.matname = char(string(state.savMatName));
            NM.TrainParam.verbosity = double(logical(state.verbosity));
        end

        function state = finalizeState(NM, state)
            % finalizeState  Normalize saving and verbosity state before TrainParam writing.
            %
            % Coerces save-model flags, resolves empty model filenames and validates verbosity state so applyToNM can write a complete SAV branch.
            %
            % state.savDefaultMatName: carries the sav default mat name value between browser/API state and legacy NeuroMiner structures.
            % state.savDirty: carries the sav dirty value between browser/API state and legacy NeuroMiner structures.
            % state.savMatName: carries the sav mat name value between browser/API state and legacy NeuroMiner structures.
            % state.savSaveModel: carries the sav save model value between browser/API state and legacy NeuroMiner structures.
            % state.savSummary: carries the sav summary value between browser/API state and legacy NeuroMiner structures.
            % state.verbosity: carries the verbosity value between browser/API state and legacy NeuroMiner structures.
            % state.verbositySummary: carries the verbosity summary value between browser/API state and legacy NeuroMiner structures.
            % state.verbosityValue: carries the verbosity value value between browser/API state and legacy NeuroMiner structures.
            def = NMSAVTools.defaultMatName(NM);
            state.savDefaultMatName = def;
            if ~isfield(state,'savMatName') || isempty(strtrim(char(string(state.savMatName))))
                state.savMatName = def;
            else
                state.savMatName = char(string(state.savMatName));
            end
            if ~isfield(state,'savSaveModel') || isempty(state.savSaveModel)
                state.savSaveModel = false;
            else
                state.savSaveModel = logical(NMSAVTools.logical01(state.savSaveModel, 0));
            end
            if ~isfield(state,'verbosity') || isempty(state.verbosity)
                state.verbosity = true;
            else
                state.verbosity = logical(NMSAVTools.logical01(state.verbosity, 1));
            end
            state.verbosityValue = double(logical(state.verbosity));
            if ~isfield(state,'savDirty'), state.savDirty = false; end
            state.savSummary = NMSAVTools.summarySaving(state);
            state.verbositySummary = NMSAVTools.summaryVerbosity(state);
        end

        function txt = summarySaving(state)
            % summarySaving  Render a concise saving-options summary.
            %
            % Formats savemodel and model filename settings for browser cards and diagnostics. It is read-only and does not inspect the filesystem.
            %
            % state.savMatName: carries the sav mat name value between browser/API state and legacy NeuroMiner structures.
            % state.savSaveModel: carries the sav save model value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                txt = 'Model saving options unavailable.';
                return;
            end
            nm = '';
            if isfield(state,'savMatName') && ~isempty(state.savMatName)
                nm = char(string(state.savMatName));
            end
            if isfield(state,'savSaveModel') && logical(state.savSaveModel)
                txt = sprintf('Model saving enabled. Output prefix: %s.', nm);
            else
                txt = sprintf('Model saving disabled. Output prefix: %s.', nm);
            end
        end

        function txt = summaryVerbosity(state)
            % summaryVerbosity  Render a concise training-verbosity summary.
            %
            % Formats NM.TrainParam.verbosity state for user-facing cards and reports. It is read-only and not used for backend control flow.
            %
            % state.verbosity: carries the verbosity value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(state) || ~isstruct(state) || ~isfield(state,'verbosity')
                txt = 'Detailed output.';
                return;
            end
            if logical(state.verbosity)
                txt = 'Detailed output.';
            else
                txt = 'No output.';
            end
        end

        function name = defaultMatName(NM)
            % defaultMatName  Derive a default optimized-model filename stem from the effective target.
            %
            % Complete native targets reproduce nk_SavingOptions_config naming.
            % Active alternative targets use LABEL.newgroupnames (classification)
            % or LABEL.newlabelname (regression). Generic/partial configurator
            % contexts may omit display-name metadata; those contexts retain the
            % established neutral NM2 prefix instead of blocking unrelated state
            % construction. User-entered SAV.matname values are never rewritten.
            if isempty(fieldnames(NM))
                name = 'ClassModel_Group';
                return;
            end
            mode = lower(char(NMAlternativeLabelTools.effectiveMode(NM)));
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            useAlternative = isfield(LABEL,'flag') && LABEL.flag == 1;

            switch mode
                case 'classification'
                    pref = 'ClassModel';
                    groupNames = {};
                    if useAlternative
                        if isfield(LABEL,'newgroupnames') && ~isempty(LABEL.newgroupnames)
                            groupNames = cellstr(string(LABEL.newgroupnames));
                        end
                    elseif isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                        groupNames = cellstr(string(NM.groupnames));
                    end
                    if numel(groupNames) > 2
                        targetName = 'Multi';
                    elseif numel(groupNames) >= 2
                        targetName = sprintf('%s-%s', groupNames{1}, groupNames{2});
                    else
                        targetName = 'Classification';
                    end

                case 'regression'
                    pref = 'RegrModel';
                    if useAlternative && isfield(LABEL,'newlabelname') && ~isempty(LABEL.newlabelname)
                        targetName = char(string(LABEL.newlabelname));
                    elseif ~useAlternative && isfield(NM,'groupnames') && ~isempty(NM.groupnames)
                        targetName = char(string(NM.groupnames{1}));
                    else
                        targetName = 'Regression';
                    end

                otherwise
                    name = 'ClassModel_Group';
                    return;
            end

            targetName = regexprep(targetName, ' ', '_');
            name = sprintf('%s_%s', pref, targetName);
        end

        function v = logical01(x, defaultVal)
            % logical01  Coerce a value to legacy 0/1 logical representation.
            %
            % Normalizes empty, logical and numeric inputs to the scalar convention used in SAV and TrainParam branches. Invalid inputs fall back to the caller-provided default.
            if nargin < 2, defaultVal = 0; end
            v = defaultVal;
            try
                if islogical(x)
                    v = double(any(x(:)));
                elseif isnumeric(x)
                    v = double(any(x(:) ~= 0));
                else
                    s = lower(strtrim(char(string(x))));
                    if any(strcmp(s, {'1','true','yes','on','detailed','detailed output'}))
                        v = 1;
                    elseif any(strcmp(s, {'0','false','no','off','none','no output'}))
                        v = 0;
                    end
                end
            catch
                v = defaultVal;
            end
        end
    end
end
