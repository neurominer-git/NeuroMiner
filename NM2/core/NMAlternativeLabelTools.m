classdef NMAlternativeLabelTools
% NMAlternativeLabelTools
% -------------------------------------------------------------------------
% Browser-UI port of the legacy cv_Label_config / nk_TrainClass_config
% alternative-label branch. The class keeps the backend contract unchanged:
% only NM.TrainParam.LABEL fields known to NM 1.4 are written to NM.
% Workspace-variable names and browser hints remain UI state only.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        ModeChoices = struct('symbol', {'classification','regression'}, ...
            'code', {'classification','regression'}, ...
            'description', {'Binary classification (alternative-label branch)', ...
                            'Regression with a continuous response'})
    end

    methods (Static)
        function LABEL = extractLabel(NM)
            % extractLabel  Return the normalized legacy alternative-label branch from NM.
            %
            % Reads NM.TrainParam.LABEL when present and guarantees a scalar struct with a flag field. The method is read-only and is the common entry point for UI/API code before effective-mode, menu-state and validation logic inspect alternative label settings.
            LABEL = struct('flag', 0);
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                    isfield(NM.TrainParam,'LABEL') && isstruct(NM.TrainParam.LABEL)
                LABEL = NM.TrainParam.LABEL;
            end
            if ~isfield(LABEL,'flag') || isempty(LABEL.flag), LABEL.flag = 0; end
        end

        function mode = effectiveMode(NM)
            % effectiveMode  Determine the label mode that downstream training configuration should see.
            %
            % Starts from NM.modeflag and overrides it with LABEL.newmode only when the alternative-label branch is active. This read-only resolver lets multi-class, learner and validation logic reason over the effective task without mutating NM.
            mode = '';
            if isfield(NM,'modeflag') && ~isempty(NM.modeflag), mode = char(NM.modeflag); end
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            if isfield(LABEL,'flag') && LABEL.flag == 1 && isfield(LABEL,'newmode') && ~isempty(LABEL.newmode)
                mode = char(LABEL.newmode);
            end
        end

        function lab = activeLabel(NM)
            % activeLabel  Resolve the currently active response vector for validation and availability checks.
            %
            % Returns LABEL.Y when the alternative-label branch is active and falls back to NM.label otherwise. The method does not impute or reorder labels; it only mirrors the branch selection used by TrainParam.LABEL.
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            if isfield(LABEL,'flag') && LABEL.flag == 1 && isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel)
                lab = LABEL.newlabel;
            else
                lab = NM.label;
            end
        end

        function [tf, nClasses, classes] = effectiveClassInfo(NM)
            % effectiveClassInfo  Resolve class structure from the effective training target.
            %
            % The alternative-label branch is authoritative when enabled; otherwise
            % NM.modeflag/NM.label define the task. This is the shared class-count
            % and multiclass authority for training configurators.
            mode = NMAlternativeLabelTools.effectiveMode(NM);
            lab = NMAlternativeLabelTools.activeLabel(NM);
            classes = {};
            if isnumeric(lab) || islogical(lab)
                values = lab(:);
                values = unique(values(isfinite(double(values))));
                classes = cellstr(string(values(:)'));
            elseif iscell(lab)
                values = lab(:);
                values = unique(values(~cellfun(@isempty, values)));
                classes = cellfun(@char, values(:)', 'UniformOutput', false);
            elseif ~isempty(lab)
                values = string(lab(:));
                values = unique(values(~ismissing(values) & strlength(values) > 0));
                classes = cellstr(values(:)');
            end
            nClasses = numel(classes);
            tf = strcmpi(mode,'classification') && nClasses > 2;
        end

        function fields = menuFields(NM, LABEL, sourceVar)
            % menuFields  Build browser-facing alternative-label controls from NM and legacy LABEL state.
            %
            % Combines legacy LABEL fields, effective mode, workspace-source hints and current source variable name into a fixed UI state. Browser-only source metadata stays outside NM and is later interpreted by labelFromMenu/applyToNM.
            if nargin < 2 || isempty(LABEL), LABEL = NMAlternativeLabelTools.extractLabel(NM); end
            if nargin < 3, sourceVar = ''; end
            originalMode = '';
            if isfield(NM,'modeflag') && ~isempty(NM.modeflag), originalMode = char(NM.modeflag); end
            enabled = isfield(LABEL,'flag') && LABEL.flag == 1;
            mode = originalMode;
            if isfield(LABEL,'newmode') && ~isempty(LABEL.newmode), mode = char(LABEL.newmode); end
            name = '';
            if isfield(LABEL,'newlabelname') && ~isempty(LABEL.newlabelname), name = char(string(LABEL.newlabelname)); end
            groupNames = {};
            if isfield(LABEL,'newgroupnames') && ~isempty(LABEL.newgroupnames), groupNames = cellstr(string(LABEL.newgroupnames)); end
            lab = NMAlternativeLabelTools.activeLabelForSummary(NM, LABEL);
            nUnique = NMAlternativeLabelTools.nUniqueNonMissing(lab);
            isMultiClass = strcmpi(mode,'classification') && ~isempty(nUnique) && nUnique > 2;
            fields = struct();
            fields.altLabelAvailable = ~isMultiClass || enabled;
            fields.altLabelEnabled = enabled;
            fields.altLabelSourceVar = char(string(sourceVar));
            fields.altLabelName = name;
            fields.altLabelMode = mode;
            fields.altLabelGroupNames = groupNames;
            fields.altLabelNValues = nUnique;
            % One MATLAB-published summary feeds both the main menu and Canvas label node;
            % browser code must not reconstruct a competing label/task description.
            if enabled
                labelName = name;
                if isempty(labelName), labelName = char(string(sourceVar)); end
                if isempty(labelName), labelName = 'Alternative label'; end
                fields.altLabelSummary = sprintf('%s -> %s', labelName, mode);
            else
                fields.altLabelSummary = 'Default NM.label is used.';
            end
        end

        function candidates = workspaceCandidates(workspaceCatalog)
            % workspaceCandidates  Filter a workspace catalog to plausible alternative-label vectors.
            %
            % Accepts the metadata catalog produced by NMWorkspaceTools and returns scalar/vector candidates that can supply labels. Values are not resolved here, keeping workspace inspection safe for browser payload construction.
            candidates = {};
            for i = 1:numel(workspaceCatalog)
                if iscell(workspaceCatalog)
                    w = workspaceCatalog{i};
                else
                    w = workspaceCatalog(i);
                end
                if ~isstruct(w) || ~isfield(w,'validLabelVector') || ~w.validLabelVector, continue; end
                c = struct();
                c.name = w.name;
                c.class = w.class;
                c.size = w.size;
                c.nUniqueNonMissing = [];
                c.taskHint = '';
                c.reason = '';
                if isfield(w,'nUniqueNonMissing'), c.nUniqueNonMissing = w.nUniqueNonMissing; end
                if isfield(w,'taskHint'), c.taskHint = w.taskHint; end
                if isfield(w,'taskHintReason'), c.reason = w.taskHintReason; end
                candidates{end+1} = c; %#ok<AGROW>
            end
        end

        function [LABEL, sourceVar] = labelFromMenu(NM, currentLabel, currentSourceVar, state)
            % labelFromMenu  Translate browser alternative-label state into the legacy LABEL struct.
            %
            % Reads the current menu state, resolves optional workspace vectors through NMWorkspaceTools, and constructs the LABEL branch expected by NeuroMiner. It preserves source-variable information separately for the UI and does not write to NM; applyToNM performs materialization.
            %
            % state.altLabelEnabled: carries the alt label enabled value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelGroupNames: carries the alt label group names value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelMode: carries the alt label mode value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelName: carries the alt label name value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelSourceVar: carries the alt label source var value between browser/API state and legacy NeuroMiner structures.
            LABEL = currentLabel;
            if isempty(LABEL) || ~isstruct(LABEL), LABEL = struct('flag',0); end
            sourceVar = currentSourceVar;
            if ~isfield(state,'altLabelEnabled') || ~logical(state.altLabelEnabled)
                LABEL.flag = 0;
                return;
            end

            LABEL.flag = 1;
            if ~isfield(LABEL,'OrigTrainParam')
                LABEL.OrigTrainParam = NM.TrainParam;
            end
            if ~isfield(LABEL,'origlabel')
                LABEL.origlabel = NM.label;
            end

            if isfield(state,'altLabelSourceVar') && ~isempty(state.altLabelSourceVar)
                sourceVar = char(string(state.altLabelSourceVar));
                LABEL.newlabel = NMWorkspaceTools.resolve(sourceVar, 'base');
            end
            if ~isfield(LABEL,'newlabel') || isempty(LABEL.newlabel)
                error('NMAlternativeLabelTools:missingLabel', 'Alternative label is enabled but no label vector is available.');
            end
            LABEL.newlabel = LABEL.newlabel(:);
            if numel(LABEL.newlabel) ~= double(NM.n_subjects_all)
                error('NMAlternativeLabelTools:labelSize', 'Alternative label must have %d rows.', double(NM.n_subjects_all));
            end

            if isfield(state,'altLabelName') && ~isempty(state.altLabelName)
                LABEL.newlabelname = char(string(state.altLabelName));
            elseif ~isfield(LABEL,'newlabelname') || isempty(LABEL.newlabelname)
                LABEL.newlabelname = sourceVar;
            end

            if isfield(state,'altLabelMode') && ~isempty(state.altLabelMode)
                LABEL.newmode = char(string(state.altLabelMode));
            else
                LABEL.newmode = NMAlternativeLabelTools.inferMode(LABEL.newlabel);
            end
            if ~any(strcmpi(LABEL.newmode, {NMAlternativeLabelTools.ModeChoices.symbol}))
                error('NMAlternativeLabelTools:badMode', 'Alternative label mode must be classification or regression.');
            end

            if strcmpi(LABEL.newmode,'classification')
                nUnique = NMAlternativeLabelTools.nUniqueNonMissing(LABEL.newlabel);
                if nUnique > 2
                    error('NMAlternativeLabelTools:multiclassAlternativeLabel', ...
                        'Alternative-label classification currently supports binary labels only.');
                end
                if isfield(state,'altLabelGroupNames') && ~isempty(state.altLabelGroupNames)
                    LABEL.newgroupnames = cellstr(string(state.altLabelGroupNames));
                elseif isfield(NM,'groupnames') && numel(NM.groupnames) == nUnique
                    LABEL.newgroupnames = NM.groupnames;
                else
                    LABEL.newgroupnames = arrayfun(@(x) sprintf('Group %d', x), 1:nUnique, 'UniformOutput', false);
                end
            elseif isfield(LABEL,'newgroupnames')
                LABEL = rmfield(LABEL,'newgroupnames');
            end
        end

        function [NM, action] = applyToNM(NM, LABEL, varind)
            % applyToNM  Materialize alternative-label state into NM.TrainParam.LABEL.
            %
            % Writes only the legacy LABEL branch and returns an action summary for the caller. The method intentionally leaves browser workspace-source hints out of NM and does not alter imported training data.
            action = 'none';
            if isempty(LABEL) || ~isstruct(LABEL) || ~isfield(LABEL,'flag')
                return;
            end
            if LABEL.flag == 1
                if ~isfield(LABEL,'OrigTrainParam'), LABEL.OrigTrainParam = NM.TrainParam; end
                if ~isfield(LABEL,'origlabel'), LABEL.origlabel = NM.label; end
                if isfield(NM.TrainParam,'MULTILABEL')
                    NM.TrainParam = rmfield(NM.TrainParam,'MULTILABEL');
                end
                NM = NMAlternativeLabelTools.updateCV(NM, LABEL);
                if NMAlternativeLabelTools.needsDefaultReset(NM, LABEL)
                    NM = NMAlternativeLabelTools.resetTrainParamForMode(NM, LABEL, varind);
                    action = 'reset';
                else
                    NM.TrainParam.LABEL = LABEL;
                    action = 'updated';
                end
                return;
            end

            old = LABEL;
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && isfield(NM.TrainParam,'LABEL') && isstruct(NM.TrainParam.LABEL)
                old = NM.TrainParam.LABEL;
            end
            if isfield(old,'OrigTrainParam') && isfield(old,'newmode') && ...
                    ~isempty(old.newmode) && isfield(NM,'modeflag') && ~strcmpi(char(old.newmode), char(NM.modeflag))
                NM.TrainParam = old.OrigTrainParam;
                action = 'restore';
            elseif isfield(NM,'TrainParam') && isfield(NM.TrainParam,'LABEL')
                NM.TrainParam = rmfield(NM.TrainParam, 'LABEL');
                if isfield(NM,'label') && size(NM.label,2) > 1
                    if isfield(old,'OrigTrainParam') && isstruct(old.OrigTrainParam) && ...
                            isfield(old.OrigTrainParam,'MULTILABEL') && isstruct(old.OrigTrainParam.MULTILABEL)
                        NM.TrainParam.MULTILABEL = old.OrigTrainParam.MULTILABEL;
                    else
                        nLabels = size(NM.label,2);
                        NM.TrainParam.MULTILABEL = struct('flag',true,'sel',1:nLabels,'dim',nLabels);
                    end
                elseif isfield(NM.TrainParam,'MULTILABEL')
                    NM.TrainParam = rmfield(NM.TrainParam,'MULTILABEL');
                end
                action = 'removed';
            end
        end

        function tf = needsDefaultReset(NM, LABEL)
            % needsDefaultReset  Decide whether a changed alternative-label branch invalidates dependent defaults.
            %
            % Compares the incoming LABEL state against the active NM settings to flag transitions that can affect task mode or class structure. Callers use the result before rebuilding dependent template branches.
            tf = false;
            if ~isfield(LABEL,'flag') || LABEL.flag ~= 1 || ~isfield(LABEL,'newmode') || isempty(LABEL.newmode), return; end
            if strcmpi(char(LABEL.newmode), char(NM.modeflag)), return; end
            if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'LABEL') && isstruct(NM.TrainParam.LABEL) && ...
                    isfield(NM.TrainParam.LABEL,'flag') && NM.TrainParam.LABEL.flag == 1 && ...
                    isfield(NM.TrainParam.LABEL,'newmode') && strcmpi(char(NM.TrainParam.LABEL.newmode), char(LABEL.newmode))
                return;
            end
            tf = true;
        end


        function [NM, LABEL, sourceVar, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure alternative labels without the browser UI.
            %
            % Parses an optional existing state and name/value modifications, resolves workspace-supplied labels when requested, applies the resulting LABEL branch through applyToNM, and returns a report. This is an API-facing entry point and mutates NM only through the documented legacy TrainParam.LABEL branch.
            [NM, LABEL, sourceVar, report] = NMAlternativeLabelTools.configure(NM, varargin{:});
        end


        function [NM, LABEL, sourceVar, report] = configure(NM, varargin)
            % configure  Public programmatic API for alternative-label setup.
            %
            % Usage:
            % [NM,LABEL,src,rep] = NMAlternativeLabelTools.configure(NM, 'Enabled',false);
            % [NM,LABEL,src,rep] = NMAlternativeLabelTools.configure(NM, existingLABEL, 'Label',y, 'Mode','classification');
            if nargin < 1 || isempty(NM), NM = struct(); end
            LABEL = NMAlternativeLabelTools.extractLabel(NM);
            sourceVar = '';
            [LABEL, sourceVar, varind, args] = NMAlternativeLabelTools.consumeConfigureBase(NM, LABEL, sourceVar, varargin{:});
            [LABEL, sourceVar, varind] = NMAlternativeLabelTools.applyConfigureArgs(NM, LABEL, sourceVar, varind, args{:});
            report = NMAlternativeLabelTools.validateState(NM, LABEL);
            if ~report.ok
                error('NMAlternativeLabelTools:invalidConfiguration', '%s', strjoin(report.errors, newline));
            end
            [NM, action] = NMAlternativeLabelTools.applyToNM(NM, LABEL, varind);
            report.action = action;
        end


        function source = importedLabelSource(NM, label)
            % Identify an alternative response solely from imported NM columns.
            source = '';
            matches = 0;
            for k = 1:size(NM.label,2)
                if isequaln(label(:),NM.label(:,k))
                    matches = matches + 1;
                    source = sprintf('NM.label:%d',k);
                end
            end
            for k = 1:numel(NM.covnames)
                if isequaln(label(:),NM.covars(:,k))
                    matches = matches + 1;
                    source = ['NM.covars:' char(NM.covnames{k})];
                end
            end
            assert(matches==1,'NMAlternativeLabelTools:importedSource', ...
                'Alternative target must uniquely match a named imported NM label or covariate.');
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted alternative-label configuration interface.
            %
            % Returns a structured help object with syntax, supported options and examples for cli_configure. It is read-only and intended for scaffold export, user documentation and RAG extraction.
            h = NMAlternativeLabelTools.configureHelp();
            h.syntax{end+1} = 'h = NMAlternativeLabelTools.cli_configureHelp()';
        end


        function h = configureHelp()
            % configureHelp  Return programmatic help for NMAlternativeLabelTools.configure().
            h = struct();
            h.className = 'NMAlternativeLabelTools';
            h.title = 'Alternative-label configuration';
            h.kind = 'configure-api-help';
            h.acceptsExistingConfiguration = true;
            h.syntax = {
                '[NM,LABEL,sourceVar,report] = NMAlternativeLabelTools.configure(NM, name, value, ...)';
                '[NM,LABEL,sourceVar,report] = NMAlternativeLabelTools.configure(NM, existingLABEL, name, value, ...)';
                'h = NMAlternativeLabelTools.configureHelp()';
                };
            h.description = 'Named-argument API for NM.TrainParam.LABEL generation. Existing LABEL structs can be passed first and modified incrementally.';
            h.options = {
                struct('name','Enabled','description','Enable or disable alternative labels.');
                struct('name','Label','description','Alternative label vector.');
                struct('name','SourceVar','description','Workspace variable name or imported NM.covars:<name> / NM.label:<column> selector.');
                struct('name','Mode','description','Learning framework; if omitted, inferred from the label vector (see h.choices.Mode).');
                struct('name','Name','description','Display/name metadata for the alternative label.');
                struct('name','GroupNames','description','Class/group labels for binary classification.');
                struct('name','VarIndex','description','Legacy modality index used only if a mode-change reset is required.');
                };
            h.choices.Mode = NMAlternativeLabelTools.ModeChoices;
            h.examples = {
                sprintf('[NM,LABEL,src,rep] = NMAlternativeLabelTools.configure(NM, ''Enabled'',true, ''Label'',y, ''Mode'',''classification'', ''Name'',''OutcomeY'');');
                sprintf('[NM,LABEL,src,rep] = NMAlternativeLabelTools.configure(NM, LABEL, ''Enabled'',false);');
                };
            h.validationRules = {
                'Enabled labels require a non-empty newlabel vector.';
                'Classification labels may currently be binary only in this alternative-label branch.';
                'If the effective task mode changes, legacy reset/restore behavior remains delegated to applyToNM.';
                };
            h.notes = {'First struct argument after NM is treated as an existing LABEL struct to modify.'; ...
                'The returned report.ok field indicates whether the validator accepted the configuration.'};
        end

        function report = validateState(NM, LABEL)
            % validateState  Validate alternative-label consistency against the current NM workspace.
            %
            % Checks mode, response vector shape and task-specific constraints after menu/API translation. The returned report lets callers block inconsistent label configurations before analysis creation or training.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(LABEL), LABEL = NMAlternativeLabelTools.extractLabel(NM); end
            report = struct('ok', true, 'errors', {{}}, 'warnings', {{}});
            try
                if ~isstruct(LABEL)
                    report.errors{end+1} = 'LABEL configuration must be a struct.';
                elseif isfield(LABEL,'flag') && double(LABEL.flag) == 1
                    if ~isfield(LABEL,'newlabel') || isempty(LABEL.newlabel)
                        report.errors{end+1} = 'Alternative label is enabled but newlabel is empty.';
                    else
                        n = numel(LABEL.newlabel(:));
                        nExpected = [];
                        if isfield(NM,'n_subjects_all') && ~isempty(NM.n_subjects_all)
                            nExpected = double(NM.n_subjects_all);
                        elseif isfield(NM,'label') && ~isempty(NM.label)
                            nExpected = numel(NM.label(:));
                        end
                        if ~isempty(nExpected) && n ~= nExpected
                            report.errors{end+1} = sprintf('Alternative label must have %d rows, but has %d.', nExpected, n);
                        end
                    end
                    if isfield(LABEL,'newmode') && ~isempty(LABEL.newmode)
                        mode = char(string(LABEL.newmode));
                        if ~any(strcmpi(mode, {NMAlternativeLabelTools.ModeChoices.symbol}))
                            report.errors{end+1} = 'Alternative label mode must be classification or regression.';
                        elseif strcmpi(mode,'classification') && isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel)
                            nUnique = NMAlternativeLabelTools.nUniqueNonMissing(LABEL.newlabel);
                            if ~isempty(nUnique) && nUnique > 2
                                report.errors{end+1} = 'Alternative-label classification currently supports binary labels only.';
                            end
                        end
                    end
                end
            catch ME
                report.errors{end+1} = ME.message;
            end
            report.ok = isempty(report.errors);
        end
    end

    methods (Static, Access = private)
        function [LABEL, sourceVar, varind, args] = consumeConfigureBase(NM, LABEL, sourceVar, varargin)
            varind = 1;
            args = varargin;
            if ~isempty(args) && isstruct(args{1})
                LABEL = NMConfigTools.mergeStruct(LABEL, args{1});
                args = args(2:end);
            end
            try
                if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'ActiveModality') && ~isempty(NM.TrainParam.ActiveModality)
                    varind = round(double(NM.TrainParam.ActiveModality));
                end
            catch
                varind = 1;
            end
        end

        function [LABEL, sourceVar, varind] = applyConfigureArgs(NM, LABEL, sourceVar, varind, varargin)
            if isempty(varargin)
                LABEL = NMAlternativeLabelTools.completeConfigureDefaults(NM, LABEL);
                return;
            end
            if numel(varargin) == 1 && isstruct(varargin{1})
                LABEL = NMConfigTools.mergeStruct(LABEL, varargin{1});
                LABEL = NMAlternativeLabelTools.completeConfigureDefaults(NM, LABEL);
                return;
            end
            if mod(numel(varargin),2) ~= 0
                error('NMAlternativeLabelTools:badConfigureArgs', 'Configure arguments must be name/value pairs after the optional LABEL struct.');
            end
            for k = 1:2:numel(varargin)
                key = char(varargin{k});
                val = varargin{k+1};
                switch key
                    case 'Enabled'
                        if logical(val), LABEL.flag = 1; else, LABEL.flag = 0; end
                    case 'Label'
                        LABEL.newlabel = val(:);
                        LABEL.flag = 1;
                    case 'SourceVar'
                        sourceVar = char(string(val));
                        if ~isempty(sourceVar) && (~isfield(LABEL,'newlabel') || isempty(LABEL.newlabel))
                            try
                                if startsWith(sourceVar,'NM.covars:')
                                    name = sourceVar(11:end);
                                    col = find(strcmp(NM.covnames,name));
                                    assert(isscalar(col),'NMAlternativeLabelTools:importedSource', ...
                                        'Alternative target covariate %s must occur exactly once.',name);
                                    LABEL.newlabel = NM.covars(:,col);
                                elseif startsWith(sourceVar,'NM.label:')
                                    col = str2double(sourceVar(10:end));
                                    assert(isfinite(col) && col==fix(col) && col>=1 && col<=size(NM.label,2), ...
                                        'NMAlternativeLabelTools:importedSource','Invalid imported label column %s.',sourceVar);
                                    LABEL.newlabel = NM.label(:,col);
                                else
                                    LABEL.newlabel = NMWorkspaceTools.resolve(sourceVar, 'base');
                                end
                                LABEL.newlabel = LABEL.newlabel(:);
                                LABEL.flag = 1;
                            catch ME
                                error('NMAlternativeLabelTools:sourceResolveFailed', 'Could not resolve alternative-label source variable %s: %s', sourceVar, ME.message);
                            end
                        end
                    case 'Mode'
                        LABEL.newmode = char(string(val));
                    case 'Name'
                        LABEL.newlabelname = char(string(val));
                    case 'GroupNames'
                        LABEL.newgroupnames = cellstr(string(val));
                    case 'VarIndex'
                        varind = round(double(val));
                    otherwise
                        error('NMAlternativeLabelTools:unknownConfigureOption', 'Unknown alternative-label configure option: %s.', varargin{k});
                end
            end
            LABEL = NMAlternativeLabelTools.completeConfigureDefaults(NM, LABEL);
        end

        function LABEL = completeConfigureDefaults(NM, LABEL)
            if isempty(LABEL) || ~isstruct(LABEL), LABEL = struct('flag',0); end
            if ~isfield(LABEL,'flag') || isempty(LABEL.flag), LABEL.flag = 0; end
            if double(LABEL.flag) == 1
                if ~isfield(LABEL,'OrigTrainParam') && isfield(NM,'TrainParam')
                    LABEL.OrigTrainParam = NM.TrainParam;
                end
                if ~isfield(LABEL,'origlabel') && isfield(NM,'label')
                    LABEL.origlabel = NM.label;
                end
                if isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel)
                    LABEL.newlabel = LABEL.newlabel(:);
                    if ~isfield(LABEL,'newmode') || isempty(LABEL.newmode)
                        LABEL.newmode = NMAlternativeLabelTools.inferMode(LABEL.newlabel);
                    end
                    if ~isfield(LABEL,'newlabelname') || isempty(LABEL.newlabelname)
                        LABEL.newlabelname = 'Alternative label';
                    end
                    if strcmpi(char(LABEL.newmode), 'classification') && (~isfield(LABEL,'newgroupnames') || isempty(LABEL.newgroupnames))
                        nUnique = NMAlternativeLabelTools.nUniqueNonMissing(LABEL.newlabel);
                        LABEL.newgroupnames = arrayfun(@(x) sprintf('Group %d', x), 1:max(1,nUnique), 'UniformOutput', false);
                    end
                end
            end
        end

        function lab = activeLabelForSummary(NM, LABEL)
            if isfield(LABEL,'flag') && LABEL.flag == 1 && isfield(LABEL,'newlabel') && ~isempty(LABEL.newlabel)
                lab = LABEL.newlabel;
            else
                lab = NM.label;
            end
        end

        function mode = inferMode(label)
            nUnique = NMAlternativeLabelTools.nUniqueNonMissing(label);
            if ~isempty(nUnique) && nUnique <= 2
                mode = 'classification';
            else
                mode = 'regression';
            end
        end

        function n = nUniqueNonMissing(label)
            n = [];
            if isempty(label), return; end
            if isnumeric(label) || islogical(label)
                y = label(:);
                y = y(isfinite(double(y)));
            else
                y = label(:);
            end
            if isempty(y), n = 0; else, n = numel(unique(y)); end
        end

        function NM = resetTrainParamForMode(NM, LABEL, varind)
            origMode = NM.modeflag;
            NM.modeflag = LABEL.newmode;
            NM.TrainParam.STACKING.flag = 2;
            NM.TrainParam.FUSION.flag = 0;
            NM.TrainParam.FUSION.M = 1;
            [~, NM.TrainParam.SVM] = nk_LIBSVM_config(NM, [], 1);
            NM.TrainParam.SVM.prog = 'LIBSVM';
            NM.TrainParam.SVM = nk_Kernel_config(NM.TrainParam.SVM, 1);
            NM.TrainParam.SVM.GridParam = 1;
            if strcmpi(NM.modeflag, 'regression'), NM.TrainParam.SVM.GridParam = 18; end
            NM.TrainParam.MULTI.flag = 0;
            NM.TrainParam = nk_Grid_config(NM.TrainParam, NM.TrainParam.SVM, varind, true);
            [~, NM.TrainParam.RFE] = nk_RFE_config([], NM.TrainParam, NM.TrainParam.SVM, NM.modeflag, NM.TrainParam.MULTI, NM.TrainParam.GRD, 1);
            NM.TrainParam.verbosity = 1;
            if isfield(NM.TrainParam,'PREPROC'), NM.TrainParam = rmfield(NM.TrainParam,'PREPROC'); end
            NM.TrainParam.LABEL = LABEL;
            NM.modeflag = origMode;
        end

        function NM = updateCV(NM, LABEL)
            if ~isfield(NM,'cv') || ~isstruct(NM.cv), return; end
            if strcmpi(LABEL.newmode,'regression')
                if isfield(NM.cv,'class'), NM.cv = rmfield(NM.cv,'class'); end
                if isfield(NM.cv,'classnew'), NM.cv = rmfield(NM.cv,'classnew'); end
                return;
            end
            if ~strcmpi(LABEL.newmode,'classification'), return; end
            if iscell(LABEL.newlabel)
                [~,newlabel] = nk_MakeDummyVariables(LABEL.newlabel);
            else
                newlabel = double(LABEL.newlabel(:));
            end
            newgroups = unique(newlabel(isfinite(newlabel)));
            if ~NMAlternativeLabelTools.checkCVClass(NM.cv, newlabel, newgroups)
                error('NMAlternativeLabelTools:cvIncompatible', 'Alternative label and current CV structure are incompatible.');
            end
            cv = NM.cv;
            [ix, jx] = size(cv.TrainInd);
            appendfl = 3;
            decomposeflag = 1;
            Eq = [];
            auto_adjust = false;
            [InPerms, InFolds] = size(cv.cvin{1,1}.TrainInd);
            cv2frame = false;
            [ulb, Label, NaNflag, g, nclass] = nk_Prep4CV(newlabel, 'classification', decomposeflag, newgroups, LABEL.newgroupnames);
            cv.class = cell(ix,jx);
            cv.classnew = cv.class;
            for i = 1:ix
                for j = 1:jx
                    cvin = NM.cv.cvin{i,j};
                    cv.class{i,j} = nk_GenClass(g, ulb, nclass, Label(cv.TrainInd{i,j}), decomposeflag, NaNflag);
                    [cv.class{i,j}, cv.cvin{i,j}, InFolds] = nk_MakeFolds(Label(cv.TrainInd{i,j}), ...
                        cv.class{i,j}, InFolds, InPerms, decomposeflag, [], appendfl, cvin, Eq, [], auto_adjust, cv2frame);
                    cv.classnew{i,j} = nk_GenClass(g, ulb, nclass, Label(cv.TestInd{i,j}), decomposeflag, NaNflag);
                end
            end
            NM.cv = cv;
        end

        function compat = checkCVClass(cv, label, groups)
            compat = true;
            for i = 1:numel(groups)
                indi = find(label == groups(i));
                containsCases = cellfun(@(cvin) NMAlternativeLabelTools.containsGroup(cvin, indi), cv.cvin);
                if ~any(containsCases, 'all')
                    compat = false;
                    return;
                end
            end
        end

        function cc = containsGroup(cvin, groupind)
            testfolds = cvin.TestInd;
            emptyFolds = cellfun(@(testf) isempty(intersect(testf, groupind)), testfolds);
            cc = ~any(emptyFolds, 'all');
        end
    end
end
