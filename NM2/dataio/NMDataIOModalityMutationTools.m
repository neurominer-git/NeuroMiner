classdef NMDataIOModalityMutationTools
% NMDataIOModalityMutationTools
% -------------------------------------------------------------------------
% Browser/API modality mutation boundary.
% Committed-modality mutation authority remains with DeleteModalityInNM/DeleteAll;
% DataIO-owned uncommitted draft descriptor slots are removed locally before commit.
% -------------------------------------------------------------------------

    methods (Static)
        function [NM, messages] = deleteModality(NM, varind)
            % deleteModality  Delete one training modality or uncommitted trailing DataIO draft.
            %
            % Consumes NM, varind; returns NM, messages.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            [ok, msg] = NMDataIOModalityMutationTools.validateIndex(NM, varind);
            if ~ok
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteModality', msg, 1, 'red*')];
                return;
            end
            if NMDataIOModalityMutationTools.isUncommittedDraftModality(NM, varind)
                [NM, removed, draftMessage] = NMDataIOModalityMutationTools.deleteTrailingDraftModality(NM, varind);
                if removed
                    messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteModality', draftMessage, 0, 'green*')];
                else
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteModality', draftMessage, 1, 'red*')];
                end
                return;
            end
            NMDataIOModalityMutationTools.assertLegacyDeletePath();
            nBefore = NMModalityInfoTools.numModalities(NM);
            if nBefore <= 1
                if ~isfield(NM,'defs') || isempty(NM.defs), NM.defs = struct(); end
                NM = DeleteAll(NM);
                messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteModality', 'Deleted the only modality; NM workspace was reset except for NM.defs.', 0, 'green*')];
                return;
            end
            NM = DeleteModalityInNM(NM, varind);
            NM = NMDataIOModalityMutationTools.refreshModalityInfoIndices(NM);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteModality', sprintf('Deleted modality %g. Remaining modality indices were compacted.', double(varind)), 0, 'green*')];
        end

        function [NM, messages] = deleteCovariates(NM, columnIndices)
            % Remove selected global columns only while training import is open.
            messages = NMDataIOMessageTools.emptyMessages();
            defs = NMDataIOBrowserModeTools.defsState(NM);
            mode = NMDataIOBrowserModeTools.dataIOModeFromDefs(defs);
            permissions = NMDataIOBrowserModeTools.permissionsFromMode(mode, defs);
            if ~permissions.canModifyTrainingModalities
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteCovariates', ...
                    'Covariates cannot be changed after training data import is finalized.', 1, 'red*')];
                return;
            end

            % TransferModality2NM persists both fields when covariates are present.
            % The overview enables this action only for a populated covariate matrix.
            nCov = size(NM.covars,2);
            if numel(NM.covnames) ~= nCov
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteCovariates', ...
                    'NM.covnames does not match NM.covars columns.', 1, 'red*')];
                return;
            end
            validateattributes(columnIndices, {'numeric'}, ...
                {'vector','integer','finite','positive','nonempty'});
            if any(columnIndices > nCov)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteCovariates', ...
                    'Covariate column index exceeds the number of covariates.', 1, 'red*')];
                return;
            end
            if numel(unique(columnIndices)) ~= numel(columnIndices)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'deleteCovariates', ...
                    'Covariate column indices must be distinct.', 1, 'red*')];
                return;
            end
            keep = true(1,nCov);
            keep(columnIndices) = false;
            if any(keep)
                NM.covars = NM.covars(:,keep);
                NM.covnames = NM.covnames(keep);
            else
                NM = rmfield(NM,{'covars','covnames'});
            end
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteCovariates', ...
                sprintf('Deleted %d covariate(s); %d remain.', numel(columnIndices), nnz(keep)), 0, 'green*')];
        end

        function [NM, messages] = deleteAll(NM)
            % deleteAll  Remove all committed training modalities and reset DataIO-maintained modality metadata.
            %
            % NM -> NM, messages.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            messages = NMDataIOMessageTools.emptyMessages();
            NMDataIOModalityMutationTools.assertLegacyDeletePath();
            if ~isfield(NM,'defs') || isempty(NM.defs), NM.defs = struct(); end
            NM = DeleteAll(NM);
            messages = [messages; NMDataIOMessageTools.make('ok', false, 'deleteAllModalities', 'Deleted all modalities; NM.defs was preserved.', 0, 'green*')];
        end

        function [ok, msg] = validateIndex(NM, varind)
            % validateIndex  Validate a requested modality index before delete/replace/resume operations.
            %
            % Consumes NM, varind; returns ok, msg.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            ok = false;
            msg = '';
            n = NMModalityInfoTools.numModalities(NM);
            if isempty(varind) || ~isnumeric(varind) || ~isscalar(varind) || ~isfinite(varind)
                msg = 'A valid numeric modality index is required.';
                return;
            end
            if varind < 1 || varind > n || round(varind) ~= varind
                msg = sprintf('Modality index %g is outside the valid range 1..%g.', double(varind), double(n));
                return;
            end
            ok = true;
        end

        function state = prepareAddState(NM)
            % prepareAddState  Create browser state for adding a new training modality.
            %
            % NM -> state.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            varind = NMDataIOStateTools.defaultVarind(NM);
            state = NMDataIOStateTools.defaultMatrixState(NM, varind);
            state.importTarget = struct('mode', 'add', 'varind', double(varind));
        end

        function [state, messages] = prepareReplaceState(NM, varind)
            % prepareReplaceState  Create browser state for replacing an existing training modality.
            [state, messages] = NMDataIOModalityMutationTools.prepareExistingState(NM, varind, 'replace');
        end

        function [state, messages] = prepareResumeState(NM, varind)
            % prepareResumeState  Create browser state for resuming a partially configured modality import.
            [state, messages] = NMDataIOModalityMutationTools.prepareExistingState(NM, varind, 'resume');
        end

        function [state, messages] = prepareExistingState(NM, varind, mode)
            % prepareExistingState  Rehydrate one existing modality through one authoritative state flow.
            %
            % Modify and Resume intentionally differ only in mutation intent. Provenance, role,
            % key, naming and alignment reconstruction all come from the same saved input_settings.
            messages = NMDataIOMessageTools.emptyMessages();
            [ok, msg] = NMDataIOModalityMutationTools.validateIndex(NM, varind);
            if ~ok
                state = struct();
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareExistingModality', msg, 1, 'red*')];
                return;
            end
            mode = lower(strtrim(char(string(mode))));
            if ~any(strcmp(mode, {'replace','resume'}))
                error('NMDataIOModalityMutationTools:existingMode', 'Unsupported existing-modality preparation mode: %s.', mode);
            end

            state = NMDataIOStateTools.defaultMatrixState(NM, varind);
            restored = false;
            if isstruct(NM) && isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= varind && ...
                    isstruct(NM.datadescriptor{varind}) && isfield(NM.datadescriptor{varind},'input_settings') && ...
                    isstruct(NM.datadescriptor{varind}.input_settings)
                try
                    state = NMDataIOStateTools.ioToState(NM.datadescriptor{varind}.input_settings);
                    state = NMDataIOModalityMutationTools.fillRegressionLabelNamesFromNM(NM, state, varind);
                    restored = true;
                catch ME
                    state = struct();
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'prepareExistingModality', ...
                        sprintf('Could not restore saved input settings for modality %g. %s (%s)', ...
                        double(varind), ME.message, ME.identifier), 1, 'red*')];
                    return;
                end
            end
            state = NMDataIOModalityMutationTools.fillLabelReferenceFromNM(NM, state, varind);
            state = NMDataIOModalityMutationTools.fillCovariateNamesFromNM(NM, state);
            state.varind = double(varind);
            state.importTarget = struct('mode', mode, 'varind', double(varind), 'prefilledFromInputSettings', restored);
            if ~isfield(state,'desc_data') || isempty(state.desc_data)
                if strcmp(mode,'replace')
                    state.desc_data = sprintf('Modification of modality %g', double(varind));
                else
                    state.desc_data = sprintf('Resume import for modality %g', double(varind));
                end
            end
            if strcmp(mode,'replace') && varind == 1
                messages = [messages; NMDataIOMessageTools.make('warn', false, 'prepareExistingModality', ...
                    'Modifying modality 1 may change the training Case-ID list. If it changes, later modalities that depend on this case list must be reset. NM2 will ask for confirmation before doing so.', 2, 'SystemCommands')];
            elseif strcmp(mode,'replace')
                messages = [messages; NMDataIOMessageTools.make('info', false, 'prepareExistingModality', ...
                    'The saved import settings have been restored. The modified modality must still match the existing NM2 Case-ID list.', 0, 'blue')];
            else
                messages = [messages; NMDataIOMessageTools.make('info', false, 'prepareExistingModality', ...
                    sprintf('Prepared resume import target for modality %g.', double(varind)), 0, 'blue')];
            end
        end



        function [NM, messages] = beginModification(NM, varind)
            % beginModification  Invalidate the active completion/QC certification before editing a committed modality.
            %
            % The committed feature container is retained until replacement Commit so existing case-axis
            % context remains available.  Active QC/preview certification is invalidated immediately;
            % the prior QC object is archived as a historical trace.  The descriptor remains explicitly
            % draft/recommit-required until a successful Commit clears that state.
            messages = NMDataIOMessageTools.emptyMessages();
            [ok, msg] = NMDataIOModalityMutationTools.validateIndex(NM, varind);
            if ~ok
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'beginModification', msg, 1, 'red*')];
                return;
            end
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'beginModification', ...
                    sprintf('Cannot modify modality %g because its saved import information is unavailable.', double(varind)), 1, 'red*')];
                return;
            end

            dd = NM.datadescriptor{varind};
            archivedQC = false;
            if isfield(dd,'QC') && isstruct(dd.QC) && ~isempty(fieldnames(dd.QC))
                item = struct('archivedAt', datestr(now,30), 'reason', 'modify_requires_recommit', 'QC', dd.QC);
                if ~isfield(dd,'QC_history') || isempty(dd.QC_history)
                    dd.QC_history = {item};
                elseif iscell(dd.QC_history)
                    dd.QC_history{end+1} = item;
                else
                    dd.QC_history = {dd.QC_history, item};
                end
                dd = rmfield(dd,'QC');
                archivedQC = true;
            end
            if ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings)
                dd.input_settings = struct();
            end
            if isfield(dd.input_settings,'preview')
                dd.input_settings = rmfield(dd.input_settings,'preview');
            end
            if isfield(dd.input_settings,'modalityInfo')
                dd.input_settings = rmfield(dd.input_settings,'modalityInfo');
            end
            dd.input_settings.completed = false;
            dd.input_settings.draft = true;
            dd.input_settings.requiresRecommit = true;
            dd.input_settings.modificationStartedAt = datestr(now,30);
            NM.datadescriptor{varind} = dd;

            suffix = '';
            if archivedQC
                suffix = ' The previous QC object was archived in QC_history.';
            end
            messages = [messages; NMDataIOMessageTools.make('warn', false, 'beginModification', ...
                sprintf('Modality %g is now incomplete and requires Preview/QC and Commit before it is complete again.%s', double(varind), suffix), 2, 'SystemCommands')];
        end

        function tf = requiresRecommit(NM, varind)
            % requiresRecommit  Return the explicit DataIO modification-invalidation state.
            tf = false;
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || ...
                    isempty(varind) || ~isfinite(double(varind)) || varind < 1 || varind > numel(NM.datadescriptor)
                return;
            end
            dd = NM.datadescriptor{round(double(varind))};
            tf = isstruct(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings) && ...
                isfield(dd.input_settings,'requiresRecommit') && isequal(dd.input_settings.requiresRecommit,true);
        end

        function NM = markCommitted(NM, varind)
            % markCommitted  Clear explicit modification invalidation after a successful replacement Commit.
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || ...
                    isempty(varind) || ~isfinite(double(varind)) || varind < 1 || varind > numel(NM.datadescriptor)
                return;
            end
            varind = round(double(varind));
            dd = NM.datadescriptor{varind};
            if ~isstruct(dd), return; end
            if ~isfield(dd,'input_settings') || ~isstruct(dd.input_settings), dd.input_settings = struct(); end
            dd.input_settings.completed = true;
            dd.input_settings.draft = false;
            if isfield(dd.input_settings,'requiresRecommit'), dd.input_settings = rmfield(dd.input_settings,'requiresRecommit'); end
            if isfield(dd.input_settings,'modificationStartedAt'), dd.input_settings = rmfield(dd.input_settings,'modificationStartedAt'); end
            dd.input_settings.recommittedAt = datestr(now,30);
            NM.datadescriptor{varind} = dd;
        end


        function state = fillRegressionLabelNamesFromNM(NM, state, varind)
            % fillRegressionLabelNamesFromNM  Seed browser state with existing regression label names for replace/resume flows.
            %
            % Consumes NM, state, varind; returns state.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % state.image: carries the image value between browser/API state and legacy NeuroMiner structures.
            % state.modeflag: carries the classification/regression task mode into legacy-compatible state.
            if nargin < 2 || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = NaN; end
            if ~isfinite(double(varind)) || double(varind) ~= 1
                return;
            end
            modeflag = '';
            if isfield(state,'modeflag') && ~isempty(state.modeflag)
                modeflag = lower(char(string(state.modeflag)));
            elseif isstruct(NM) && isfield(NM,'modeflag') && ~isempty(NM.modeflag)
                modeflag = lower(char(string(NM.modeflag)));
            end
            if ~strcmp(modeflag, 'regression')
                return;
            end
            haveNames = false;
            if isfield(state,'image') && isstruct(state.image)
                candidates = {'labelNames','regressionLabelNames','desc_labels','labelnames'};
                for k = 1:numel(candidates)
                    if isfield(state.image, candidates{k}) && ~isempty(state.image.(candidates{k}))
                        haveNames = true;
                        break;
                    end
                end
            end
            if haveNames || ~isstruct(NM) || ~isfield(NM,'labelnames') || isempty(NM.labelnames)
                return;
            end
            names = NMDataIOStateTools.asCaseCell(NM.labelnames);
            if isempty(names), return; end
            if ~isfield(state,'image') || ~isstruct(state.image), state.image = struct(); end
            state.image.labelNames = names(:)';
            state.image.regressionLabelNames = names(:)';
            state.image.labelNamesSource = 'manual';
        end

        function state = fillLabelReferenceFromNM(NM, state, varind)
            % fillLabelReferenceFromNM  Seed browser state with existing label vectors and group names.
            %
            % Consumes NM, state, varind; returns state.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % state.existingLabelAvailable: carries the existing label available value between browser/API state and legacy NeuroMiner structures.
            % state.existingLabelColumns: carries the existing label columns value between browser/API state and legacy NeuroMiner structures.
            % state.existingLabelReference: carries the existing label reference value between browser/API state and legacy NeuroMiner structures.
            % state.existingLabelRows: carries the existing label rows value between browser/API state and legacy NeuroMiner structures.
            % state.image: carries the image value between browser/API state and legacy NeuroMiner structures.
            % state.preserveExistingLabel: carries the preserve existing label value between browser/API state and legacy NeuroMiner structures.
            if nargin < 2 || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = NaN; end
            if ~isfinite(double(varind)) || double(varind) ~= 1
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'label') || isempty(NM.label)
                return;
            end
            nRows = size(NM.label, 1);
            nCols = 1;
            if isnumeric(NM.label) || islogical(NM.label) || iscell(NM.label) || isstring(NM.label) || ischar(NM.label)
                if isvector(NM.label)
                    nRows = numel(NM.label);
                    nCols = 1;
                else
                    nCols = size(NM.label, 2);
                end
            end
            state.existingLabelReference = 'NM.label';
            state.existingLabelAvailable = true;
            state.existingLabelRows = double(nRows);
            state.existingLabelColumns = double(nCols);
            state.preserveExistingLabel = true;
            if ~isfield(state,'image') || ~isstruct(state.image)
                state.image = struct();
            end
            state.image.existingLabelReference = 'NM.label';
            state.image.existingLabelAvailable = true;
            state.image.existingLabelRows = double(nRows);
            state.image.existingLabelColumns = double(nCols);
            state.image.preserveExistingLabel = true;
        end


        function state = fillCovariateNamesFromNM(NM, state)
            % fillCovariateNamesFromNM  Seed browser state with existing covariate names for role-managed imports.
            %
            % NM, state -> state.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % state.existingCovariateCount: carries the existing covariate count value between browser/API state and legacy NeuroMiner structures.
            % state.existingCovariateNames: carries the existing covariate names value between browser/API state and legacy NeuroMiner structures.
            % state.existingCovariateReference: carries the existing covariate reference value between browser/API state and legacy NeuroMiner structures.
            % state.image: carries the image value between browser/API state and legacy NeuroMiner structures.
            % state.matrix: carries the matrix value between browser/API state and legacy NeuroMiner structures.
            % state.preserveExistingCovariates: carries the preserve existing covariates value between browser/API state and legacy NeuroMiner structures.
            if nargin < 2 || ~isstruct(state), return; end
            if ~isstruct(NM) || ~isfield(NM,'covnames') || isempty(NM.covnames)
                return;
            end
            names = NMDataIOStateTools.asCaseCell(NM.covnames);
            names = names(:)';
            if isempty(names), return; end
            nCov = numel(names);
            if isfield(NM,'covars') && isnumeric(NM.covars) && ~isempty(NM.covars)
                nCov = size(NM.covars, 2);
                if numel(names) < nCov
                    return;
                end
                if numel(names) > nCov
                    names = names(1:nCov);
                end
            end

            % On modify/resume, top-level NM.covnames is the authoritative
            % covariate-name source.  Saved input_settings may be stale
            % snapshots from earlier DataIO passes; do not let generic
            % Covariate_### entries from that snapshot repopulate the
            % frontend when the current NM workspace carries semantic names.
            state.existingCovariateReference = 'NM.covars';
            state.existingCovariateNames = names;
            state.existingCovariateCount = double(nCov);
            state.preserveExistingCovariates = true;
            if ~isfield(state,'image') || ~isstruct(state.image)
                state.image = struct();
            end
            state.image.covariateNames = names;
            state.image.covnames = names;
            state.image.existingCovariateReference = 'NM.covars';
            state.image.existingCovariateNames = names;
            state.image.existingCovariateCount = double(nCov);
            if ~isfield(state,'matrix') || ~isstruct(state.matrix)
                state.matrix = struct();
            end
            state.matrix.existingCovariateNames = names;
            state.matrix.existingCovariateCount = double(nCov);
        end

        function tf = isUncommittedDraftModality(NM, varind)
            % isUncommittedDraftModality  Identify the explicit DataIO draft state, not committed/external modalities.
            tf = false;
            if ~isstruct(NM) || ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || ...
                    varind < 1 || varind > numel(NM.datadescriptor)
                return;
            end
            hasY = isfield(NM,'Y') && iscell(NM.Y) && varind <= numel(NM.Y) && ~isempty(NM.Y{varind});
            dd = NM.datadescriptor{varind};
            tf = ~hasY && isstruct(dd) && isfield(dd,'input_settings') && isstruct(dd.input_settings) && ...
                isfield(dd.input_settings,'draft') && isequal(dd.input_settings.draft,true) && ...
                (~isfield(dd.input_settings,'completed') || ~isequal(dd.input_settings.completed,true));
        end

        function [NM, removed, message] = deleteTrailingDraftModality(NM, varind)
            % deleteTrailingDraftModality  Remove a DataIO-owned uncommitted trailing descriptor slot.
            removed = false;
            if varind ~= numel(NM.datadescriptor)
                message = sprintf(['The unfinished import for modality %g is not the last modality entry. ' ...
                    'NM2 did not delete it because doing so could change the numbering of existing modalities.'], double(varind));
                return;
            end
            NM.datadescriptor(varind) = [];
            if isempty(NM.datadescriptor), NM = rmfield(NM,'datadescriptor'); end
            cellFields = {'Y','featnames','badcoords','brainmask','files'};
            for ii = 1:numel(cellFields)
                f = cellFields{ii};
                if isfield(NM,f) && iscell(NM.(f)) && numel(NM.(f)) == varind && isempty(NM.(f){varind})
                    NM.(f)(varind) = [];
                    if isempty(NM.(f)), NM = rmfield(NM,f); end
                end
            end
            removed = true;
            message = sprintf('Deleted unfinished modality import %g.', double(varind));
        end

        function NM = refreshModalityInfoIndices(NM)
            % refreshModalityInfoIndices  Refresh cached modality-info indices after deletion or reordering.
            %
            % NM -> NM.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % Callers must use the returned NM value as the authoritative mutated container.
            n = NMModalityInfoTools.numModalities(NM);
            for i = 1:n
                info = nk_GetNMModalityInfo(NM, i, struct('ScanInMemory', false, 'MaxScanElements', 1e7));
                info.modalityIndex = double(i);
                NM = nk_UpdateNMModalityInfo(NM, i, info);
            end
        end

        function assertLegacyDeletePath()
            % assertLegacyDeletePath  Fail early if legacy modality-delete support is unavailable on the MATLAB path.
            %
            % No required inputs -> no explicit output.
            % It prepares controlled DataIO mutations while preserving workspace case and label invariants.
            % Throws on invalid preconditions instead of returning an ambiguous partial result.
            if exist('DeleteModalityInNM','file') ~= 2 || exist('DeleteAll','file') ~= 2
                error('NMDataIOModalityMutationTools:missingLegacyDeletePath', ...
                    'Legacy DataIO functions DeleteModalityInNM.m and DeleteAll.m must be on the MATLAB path.');
            end
        end
    end
end
