classdef NMStatusGuardTools
% NMStatusGuardTools
% -------------------------------------------------------------------------
% Shared guard/status layer for NM workflow state flags.
%
% Legacy NeuroMiner state transitions are owned by nk_GetNMStatus. Browser
% pages should therefore use workflowStatus(NM) where module availability is
% being derived. defsState remains a small low-level normalizer for the two
% persistent transition flags that are stored in NM.defs.
% -------------------------------------------------------------------------

    methods (Static)
        function defs = defsState(NM)
            % defsState  Return normalized persistent NM workflow flags.
            %
            %   defs = NMStatusGuardTools.defsState(NM) returns only the two
            %   flags persisted in NM.defs. It intentionally does not infer
            %   full menu availability; use workflowStatus for that.

            defs = struct('import_finished', false, 'analyses_locked', false);
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs)
                if isfield(NM.defs,'import_finished') && ~isempty(NM.defs.import_finished)
                    defs.import_finished = logical(NM.defs.import_finished);
                end
                if isfield(NM.defs,'analyses_locked') && ~isempty(NM.defs.analyses_locked)
                    defs.analyses_locked = logical(NM.defs.analyses_locked);
                end
            end
        end

        function status = workflowStatus(NM)
            % workflowStatus  Return legacy-compatible main-menu state.
            %
            %   status = NMStatusGuardTools.workflowStatus(NM) delegates to
            %   nk_GetNMStatus(NM) when that legacy function is available. The
            %   returned fixed-schema structure is the authoritative source for
            %   browser workbench/module gating. Errors in nk_GetNMStatus
            %   propagate rather than being replaced by inferred readiness.

            status = NMStatusGuardTools.statusTemplate(NM);
            [legacyStatus, paramstr] = nk_GetNMStatus(NM);
            status = NMStatusGuardTools.mergeLegacyStatus(status, legacyStatus, paramstr);
            status.source = 'nk_GetNMStatus';
            status.ok = true;
            status.message = 'Workflow state derived from nk_GetNMStatus.';
            status = NMStatusGuardTools.finalizeStatus(NM, status);
        end

        function assertTrainingImportFinalized(NM, callerName)
            % assertTrainingImportFinalized  Require finalized training import before an operation.

            if nargin < 2 || isempty(callerName), callerName = 'this operation'; end
            status = NMStatusGuardTools.workflowStatus(NM);
            if ~status.import_finished
                error('NMStatusGuardTools:trainingImportNotFinalized', ...
                    ['Training-data import has not been finalized. ', ...
                     'Finalize training data import before calling %s.'], char(string(callerName)));
            end
        end

        function assertScientificTrainingData(NM)
            % nm2-allow: Only NMSimulationTools.createSyntheticTemplate creates this optional marker.
            if isfield(NM,'SYNTH') && isfield(NM.SYNTH,'fullySyntheticDefinition')
                error('NMStatusGuardTools:syntheticPlaceholder', ...
                    'SYNTH configuration placeholders are not trainable observations.');
            end
        end

        function status = assertTrainingConfigurationMode(NM, callerName)
            % assertTrainingConfigurationMode  Require editable discovery/training mode.

            if nargin < 2 || isempty(callerName), callerName = 'this operation'; end
            status = NMStatusGuardTools.workflowStatus(NM);
            if ~status.import_finished
                error('NMStatusGuardTools:trainingImportNotFinalized', ...
                    'Finalize training data import before calling %s.', callerName);
            end
            if status.analyses_locked
                error('NMStatusGuardTools:applicationModeActive', ...
                    ['%s cannot modify or run discovery-stage training modules because application/OOCV mode is active. ', ...
                     'Training-stage modules are locked once NM.defs.analyses_locked=true.'], char(string(callerName)));
            end
        end

        function assertApplicationMode(NM, callerName)
            % assertApplicationMode  Require locked application/OOCV mode.

            if nargin < 2 || isempty(callerName), callerName = 'this operation'; end
            status = NMStatusGuardTools.workflowStatus(NM);
            if ~status.import_finished
                error('NMStatusGuardTools:trainingImportNotFinalized', ...
                    ['Training-data import has not been finalized. ', ...
                     'Application/OOCV data management requires finalized training data before %s.'], char(string(callerName)));
            end
            if ~status.analyses_locked
                error('NMStatusGuardTools:applicationModeInactive', ...
                    ['Application/OOCV mode is not active. ', ...
                     'The main app must set NM.defs.analyses_locked=true after at least one analysis has finished before %s.'], char(string(callerName)));
            end
        end

        function tf = hasCompletedAnalysis(NM)
            % hasCompletedAnalysis  Return true if at least one analysis status is >= 1.
            %
            % This follows the legacy main-menu semantics: visualization and
            % application-mode entry become meaningful only after at least one
            % CV2 partition was trained successfully, represented by analysis
            % status >= 1.

            status = NMStatusGuardTools.workflowStatus(NM);
            tf = logical(status.analyses_ready) || logical(status.analyses_completed) || ...
                any(logical(status.completed_analyses));
        end

        function assertCompletedAnalysisAvailable(NM, callerName)
            % assertCompletedAnalysisAvailable  Require at least one trained analysis.

            if nargin < 2 || isempty(callerName), callerName = 'this operation'; end
            if ~NMStatusGuardTools.hasCompletedAnalysis(NM)
                error('NMStatusGuardTools:noCompletedAnalysis', ...
                    ['No completed analysis is available. ', ...
                     'Application/OOCV mode can only be entered after at least one analysis has status >= 1 before %s.'], char(string(callerName)));
            end
        end

        function tf = analysisStatusAtLeast(NM, analind, minStatus)
            % analysisStatusAtLeast  True if selected analysis status reaches threshold.

            if nargin < 3 || isempty(minStatus), minStatus = 1; end
            tf = false;
            v = NMStatusGuardTools.analysisStatusVector(NM);
            if analind >= 1 && analind <= numel(v)
                tf = isfinite(v(analind)) && v(analind) >= double(minStatus);
            end
        end

        function v = analysisStatusVector(NM)
            % analysisStatusVector  Return numeric status vector from NM.analysis.

            v = zeros(1,0);
            if ~isstruct(NM) || ~isfield(NM,'analysis') || ~iscell(NM.analysis), return; end
            v = NaN(1,numel(NM.analysis));
            for i = 1:numel(NM.analysis)
                A = NM.analysis{i};
                if isstruct(A) && isfield(A,'status') && ~isempty(A.status)
                    try
                        val = double(A.status);
                        v(i) = max(val(:));
                    catch
                        v(i) = NaN;
                    end
                end
            end
        end
    end

    methods (Static, Access = private)
        function status = statusTemplate(NM)
            defs = NMStatusGuardTools.defsState(NM);
            n = NMStatusGuardTools.analysisCount(NM);
            status = struct();
            status.ok = true;
            status.source = 'uninitialized';
            status.message = '';
            status.statusError = '';
            status.statusErrorIdentifier = '';
            status.paramstr = '';
            status.import_finished = defs.import_finished;
            status.setup_ok = false;
            status.analyses_locked = defs.analyses_locked;
            status.analyses_exist = false;
            status.analyses_ready = false;
            status.analyses_nondeterministic = false;
            status.analyses_completed = false;
            status.completed_analyses = false(1,n);
            status.ready_analyses = false(1,n);
            status.status_analyses = NaN(1,n);
            status.isequalcv_analyses = false(1,n);
            status.nmodal_analyses = NaN(1,n);
            status.oocv_data_ready = false;
            status.oocv_anal_ready = false;
            status.data_scrambled = false;
            if isstruct(NM) && isfield(NM,'defs') && isstruct(NM.defs) && ...
                    isfield(NM.defs,'data_scrambled') && ~isempty(NM.defs.data_scrambled)
                status.data_scrambled = logical(NM.defs.data_scrambled);
            end
        end

        function status = mergeLegacyStatus(status, legacyStatus, paramstr)
            if ~isstruct(legacyStatus)
                error('NMStatusGuardTools:badLegacyStatus', 'nk_GetNMStatus did not return a status struct.');
            end
            % nk_GetNMStatus returns numeric [] when no configuration parameters are missing.
            % Collapse its textual diagnostic only at this projection authority.
            status.paramstr = '';
            if ~isempty(paramstr)
                status.paramstr = strjoin(cellstr(paramstr), '; ');
            end
            fields = fieldnames(legacyStatus);
            for i = 1:numel(fields)
                status.(fields{i}) = legacyStatus.(fields{i});
            end
        end

        function status = finalizeStatus(NM, status)
            defs = NMStatusGuardTools.defsState(NM);
            status.import_finished = NMStatusGuardTools.logicalField(status, 'import_finished', defs.import_finished);
            status.analyses_locked = NMStatusGuardTools.logicalField(status, 'analyses_locked', defs.analyses_locked);
            status.setup_ok = NMStatusGuardTools.logicalField(status, 'setup_ok', false);
            status.analyses_exist = NMStatusGuardTools.logicalField(status, 'analyses_exist', false);
            status.analyses_ready = NMStatusGuardTools.logicalField(status, 'analyses_ready', false);
            status.analyses_nondeterministic = NMStatusGuardTools.logicalField(status, 'analyses_nondeterministic', false);
            status.analyses_completed = NMStatusGuardTools.logicalField(status, 'analyses_completed', false);
            status.oocv_data_ready = NMStatusGuardTools.logicalField(status, 'oocv_data_ready', false);
            status.oocv_anal_ready = NMStatusGuardTools.logicalField(status, 'oocv_anal_ready', false);
            status.data_scrambled = NMStatusGuardTools.logicalField(status, 'data_scrambled', false);

            v = NMStatusGuardTools.analysisStatusVector(NM);
            n = numel(v);
            status.status_analyses = NMStatusGuardTools.numericVectorField(status, 'status_analyses', v, n, NaN);
            completedDefault = isfinite(status.status_analyses) & status.status_analyses >= 1;
            status.completed_analyses = NMStatusGuardTools.logicalVectorField(status, 'completed_analyses', completedDefault, n);
            status.ready_analyses = NMStatusGuardTools.logicalVectorField(status, 'ready_analyses', status.completed_analyses, n);
            status.isequalcv_analyses = NMStatusGuardTools.logicalVectorField(status, 'isequalcv_analyses', false(1,n), n);
            status.nmodal_analyses = NMStatusGuardTools.numericVectorField(status, 'nmodal_analyses', NaN(1,n), n, NaN);

            if n > 0
                status.analyses_exist = true;
                status.analyses_ready = status.analyses_ready || any(status.ready_analyses) || any(status.completed_analyses);
                status.analyses_completed = status.analyses_completed || any(status.completed_analyses);
            end
        end

        function n = analysisCount(NM)
            n = 0;
            if isstruct(NM) && isfield(NM,'analysis') && iscell(NM.analysis)
                n = numel(NM.analysis);
            end
        end

        function out = logicalField(s, field, defaultValue)
            out = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
                try
                    val = s.(field);
                    if islogical(val) || isnumeric(val)
                        out = logical(val(1));
                    else
                        out = logical(str2double(char(string(val))));
                    end
                catch
                    out = defaultValue;
                end
            end
        end

        function out = logicalVectorField(s, field, defaultValue, n)
            out = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
                try
                    out = logical(s.(field));
                    out = out(:)';
                catch
                    out = defaultValue;
                end
            end
            out = NMStatusGuardTools.fitLogicalVector(out, defaultValue, n);
        end

        function out = numericVectorField(s, field, defaultValue, n, fillValue)
            out = defaultValue;
            if isstruct(s) && isfield(s,field) && ~isempty(s.(field))
                try
                    out = double(s.(field));
                    out = out(:)';
                catch
                    out = defaultValue;
                end
            end
            out = NMStatusGuardTools.fitNumericVector(out, defaultValue, n, fillValue);
        end

        function out = fitLogicalVector(out, defaultValue, n)
            if numel(out) < n
                d = defaultValue;
                if numel(d) < n, d(end+1:n) = false; end
                out(end+1:n) = d(numel(out)+1:n);
            elseif numel(out) > n
                out = out(1:n);
            end
            if isempty(out) && n > 0, out = false(1,n); end
        end

        function out = fitNumericVector(out, defaultValue, n, fillValue)
            if numel(out) < n
                d = defaultValue;
                if numel(d) < n, d(end+1:n) = fillValue; end
                out(end+1:n) = d(numel(out)+1:n);
            elseif numel(out) > n
                out = out(1:n);
            end
            if isempty(out) && n > 0, out = repmat(fillValue,1,n); end
        end
    end
end
