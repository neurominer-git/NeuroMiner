classdef NMDataIOImportTargetTools
% NMDataIOImportTargetTools
% -------------------------------------------------------------------------
% Purpose / authority:
%   Canonical training-versus-OOCV write-target normalization for browser and API imports.
%   The legacy importer separates OOCV/application import by passing an OOCV subcontainer into
%   TransferModality2NM while setting IO.oocvflag=true; this class makes that target explicit.
%
% Invariant:
%   Import-target semantics are independent of provenance retrieval. No provenance-specific
%   layer may decide training/OOCV write location or reconstruct a competing target state.
% -------------------------------------------------------------------------

    methods (Static)
        function target = normalize(NM, stateOrTarget, varind)
            % normalize  Normalize a state/spec/target description into the canonical import-target structure.
            %
            % Consumes NM, stateOrTarget, varind; returns target.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers should pass already-normalized NM/state/spec inputs and inspect returned diagnostics.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            if nargin < 1 || isempty(NM), NM = struct(); end %#ok<INUSD>
            if nargin < 2 || isempty(stateOrTarget), stateOrTarget = struct(); end
            if nargin < 3 || isempty(varind), varind = []; end

            src = struct();
            if isstruct(stateOrTarget) && isfield(stateOrTarget,'importTarget') && isstruct(stateOrTarget.importTarget)
                src = stateOrTarget.importTarget;
            elseif isstruct(stateOrTarget)
                src = stateOrTarget;
            end

            target = struct();
            target.scope = NMDataIOImportTargetTools.pickChar(src, stateOrTarget, {'scope','importScope'}, 'training');
            stateSaysOOCV = isstruct(stateOrTarget) && ...
                NMDataIOImportTargetTools.pickLogical(struct(), stateOrTarget, {'oocvflag','oocvFlag'}, false);
            if stateSaysOOCV && (~isfield(src,'scope') || isempty(src.scope) || strcmpi(char(string(src.scope)), 'training'))
                target.scope = 'oocv';
            end
            target.scope = lower(strtrim(char(string(target.scope))));
            if any(strcmp(target.scope, {'application','validation','independent','independent_test','independent-test'}))
                target.scope = 'oocv';
            end
            if isempty(target.scope), target.scope = 'training'; end

            target.mode = lower(strtrim(NMDataIOImportTargetTools.pickChar(src, stateOrTarget, {'mode','targetMode'}, 'add')));
            if isempty(target.mode), target.mode = 'add'; end

            if isempty(varind)
                varind = NMDataIOImportTargetTools.pickNumeric(src, stateOrTarget, {'varind','modalityIndex','modality','currmodal'}, 1);
            else
                varind = NMDataIOImportTargetTools.pickNumeric(src, stateOrTarget, {'varind','modalityIndex','modality','currmodal'}, varind);
            end
            if isempty(varind) || ~isfinite(double(varind)), varind = 1; end
            target.varind = max(1, round(double(varind)));

            if strcmp(target.scope,'oocv')
                target.containerField = NMDataIOImportTargetTools.pickChar(src, stateOrTarget, {'containerField','fldnam','field'}, 'OOCV');
                target.containerField = char(string(target.containerField));
                if isempty(target.containerField) || strcmp(target.containerField,'?')
                    target.containerField = 'OOCV';
                end
                if ~any(strcmp(target.containerField, {'OOCV','C'}))
                    target.containerField = 'OOCV';
                end
                target.containerIndex = NMDataIOImportTargetTools.pickNumeric(src, stateOrTarget, {'containerIndex','oocvind','ind','index'}, 1);
                if isempty(target.containerIndex) || ~isfinite(double(target.containerIndex))
                    target.containerIndex = 1;
                end
                target.containerIndex = max(1, round(double(target.containerIndex)));
                target.labels_known = NMDataIOImportTargetTools.pickLogical(src, stateOrTarget, {'labels_known','labelsKnown','label_known','labelsKnownFlag'}, true);
                target.description = NMDataIOImportTargetTools.pickChar(src, stateOrTarget, {'description','desc','desc_data'}, 'OOCV/application data');
            else
                target.scope = 'training';
                target.containerField = '';
                target.containerIndex = [];
                target.labels_known = NMDataIOImportTargetTools.pickLogical(src, stateOrTarget, {'labels_known','labelsKnown'}, true);
                target.description = NMDataIOImportTargetTools.pickChar(src, stateOrTarget, {'description','desc','desc_data'}, 'Training data');
            end
        end

        function tf = isOOCV(target)
            % isOOCV  Return whether an import target points to an OOCV/application container.
            %
            % Target -> tf.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            tf = isstruct(target) && isfield(target,'scope') && strcmpi(char(string(target.scope)), 'oocv');
        end

        function tf = currentImportDefinesLabels(NM, target)
            % CURRENTIMPORTDEFINESLABELS  Return whether this import operation owns label definition.
            %
            % The first training modality defines the training target. For OOCV,
            % labels may be defined only when the selected container is labelled
            % and does not yet contain its canonical label vector. Later modalities
            % align to the established target axis instead of recreating labels.
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if ~NMDataIOImportTargetTools.isOOCV(target)
                tf = target.varind == 1;
                return;
            end
            labelsKnown = logical(target.labels_known);
            D = struct();
            field = char(string(target.containerField));
            idx = double(target.containerIndex);
            if isstruct(NM) && isfield(NM,field) && iscell(NM.(field)) && numel(NM.(field)) >= idx && ...
                    isstruct(NM.(field){idx})
                D = NM.(field){idx};
                if isfield(D,'labels_known') && ~isempty(D.labels_known), labelsKnown = logical(D.labels_known); end
            end
            if ~labelsKnown
                tf = false;
                return;
            end
            labelsPresent = (isfield(D,'label') && ~isempty(D.label)) || ...
                (isfield(D,'s_label') && ~isempty(D.s_label)) || (isfield(D,'L') && ~isempty(D.L));
            tf = ~labelsPresent;
        end

        function [NM, target, messages] = ensureContainer(NM, target)
            % ensureContainer  Ensure the selected OOCV/application container exists before import.
            %
            % Consumes NM, target; returns NM, target, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers must use the returned NM value as the authoritative mutated container; diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            messages = NMDataIOMessageTools.emptyMessages();
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if ~NMDataIOImportTargetTools.isOOCV(target)
                return;
            end
            if ~isfield(NM, target.containerField) || isempty(NM.(target.containerField))
                NM.(target.containerField) = cell(1, target.containerIndex);
            elseif ~iscell(NM.(target.containerField))
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                    sprintf('The saved %s OOCV/application dataset list is invalid and cannot be used for import.', target.containerField), 1, 'red*')];
                return;
            elseif numel(NM.(target.containerField)) < target.containerIndex
                NM.(target.containerField){target.containerIndex} = [];
            end
            newContainer = isempty(NM.(target.containerField){target.containerIndex}) || ~isstruct(NM.(target.containerField){target.containerIndex});
            if newContainer
                D = struct();
                D.analysis_used = false;
            else
                D = NM.(target.containerField){target.containerIndex};
            end
            if ~isfield(D,'desc') || isempty(D.desc)
                D.desc = char(string(target.description));
            end
            if ~isfield(D,'date') || isempty(D.date)
                D.date = datestr(now);
            end
            if ~isfield(D,'labels_known') || isempty(D.labels_known) || D.labels_known ~= target.labels_known
                D.labels_known = logical(target.labels_known);
            end
            if ~logical(D.labels_known)
                for roleField = {'label','s_label','L'}
                    if isfield(D, roleField{1})
                        D = rmfield(D, roleField{1});
                    end
                end
            end
            if ~isfield(D,'n_subjects_all') || isempty(D.n_subjects_all)
                D.n_subjects_all = Inf;
            end
            NM.(target.containerField){target.containerIndex} = D;
        end

        function [D, messages] = getContainer(NM, target)
            % getContainer  Return the NM sub-container that owns a target import operation.
            %
            % Consumes NM, target; returns D, messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            messages = NMDataIOMessageTools.emptyMessages();
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if ~NMDataIOImportTargetTools.isOOCV(target)
                D = NM;
                return;
            end
            D = struct();
            if ~isfield(NM, target.containerField) || ~iscell(NM.(target.containerField)) || ...
                    numel(NM.(target.containerField)) < target.containerIndex || ...
                    isempty(NM.(target.containerField){target.containerIndex}) || ...
                    ~isstruct(NM.(target.containerField){target.containerIndex})
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                    sprintf('OOCV/application dataset %g does not exist.', target.containerField, double(target.containerIndex)), 1, 'red*')];
                return;
            end
            D = NM.(target.containerField){target.containerIndex};
        end

        function NM = setContainer(NM, target, D)
            % setContainer  Write a modified training or OOCV container back into NM.
            %
            % Consumes NM, target, D; returns NM.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Callers must use the returned NM value as the authoritative mutated container.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if ~NMDataIOImportTargetTools.isOOCV(target)
                NM = D;
                return;
            end
            if ~isfield(NM, target.containerField) || ~iscell(NM.(target.containerField))
                NM.(target.containerField) = cell(1, target.containerIndex);
            end
            if numel(NM.(target.containerField)) < target.containerIndex
                NM.(target.containerField){target.containerIndex} = [];
            end
            if isfield(D,'datadescriptor') && iscell(D.datadescriptor) && numel(D.datadescriptor) >= target.varind && ...
                    isstruct(D.datadescriptor{target.varind}) && isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && ...
                    numel(NM.datadescriptor) >= target.varind && isstruct(NM.datadescriptor{target.varind}) && ...
                    isfield(NM.datadescriptor{target.varind},'desc') && ~isempty(NM.datadescriptor{target.varind}.desc)
                D.datadescriptor{target.varind}.desc = NM.datadescriptor{target.varind}.desc;
            end
            NM.(target.containerField){target.containerIndex} = D;
        end

        function messages = validateForImport(NM, target)
            % validateForImport  Validate target-level preconditions before a commit path mutates NM.
            %
            % Consumes NM, target; returns messages.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            % API note: this public method is suitable for scripted workflows when callers preserve the documented state/spec contract.
            messages = NMDataIOMessageTools.emptyMessages();
            target = NMDataIOImportTargetTools.normalize(NM, target);
            if ~NMDataIOImportTargetTools.isOOCV(target)
                if target.varind < 1
                    messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', 'Training import requires a positive modality index.', 1, 'red*')];
                end
                return;
            end
            if ~isstruct(NM) || ~isfield(NM,'Y') || isempty(NM.Y) || ~iscell(NM.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', 'OOCV/application import requires an existing training NM workspace with at least one modality.', 1, 'red*')];
                return;
            end
            if target.varind > numel(NM.Y)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                    sprintf('OOCV modality %g has no matching training modality. Import one OOCV modality per trained modality.', double(target.varind)), 1, 'red*')];
            end
            if NMAnalysisManagerTools.oocvAnalysisUsed(NM, target.containerIndex)
                messages = [messages; NMDataIOMessageTools.make('danger', true, 'importTarget', ...
                    sprintf('OOCV/application dataset %d is locked because it is referenced by retained analysis results.', target.containerIndex), 1, 'red*')];
            end
        end

        function tf = hasTargetModality(NM, target, varind)
            % hasTargetModality  Check whether a target container contains a selected modality index.
            %
            % Consumes NM, target, varind; returns tf.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % Diagnostics are returned as structured messages for explicit UI/API handling.
            if nargin < 3 || isempty(varind)
                target = NMDataIOImportTargetTools.normalize(NM, target);
                varind = target.varind;
            end
            [D, messages] = NMDataIOImportTargetTools.getContainer(NM, target);
            if NMDataIOMessageTools.hasFatal(messages)
                tf = false;
                return;
            end
            tf = isstruct(D) && isfield(D,'Y') && iscell(D.Y) && numel(D.Y) >= varind && ~isempty(D.Y{varind});
        end

        function label = targetLabel(target)
            % targetLabel  Return the human-readable target label used in diagnostics and reports.
            %
            % Target -> label.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            target = NMDataIOImportTargetTools.normalize(struct(), target);
            if NMDataIOImportTargetTools.isOOCV(target)
                label = sprintf('%s dataset %g modality %g', target.containerField, double(target.containerIndex), double(target.varind));
            else
                label = sprintf('training modality %g', double(target.varind));
            end
        end

        function ref = caseReferenceLabel(target)
            % caseReferenceLabel  Return the label describing which case list is authoritative for alignment.
            %
            % Target -> ref.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            target = NMDataIOImportTargetTools.normalize(struct(), target);
            if NMDataIOImportTargetTools.isOOCV(target)
                ref = sprintf('NM.%s{%g}.cases', target.containerField, double(target.containerIndex));
            else
                ref = 'NM.cases';
            end
        end

        function n = nTrainingModalities(NM)
            % nTrainingModalities  Return the number of committed training modalities in NM.
            %
            % NM -> n.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            n = 0;
            if isstruct(NM) && isfield(NM,'Y') && iscell(NM.Y)
                n = numel(NM.Y);
            end
        end

        function v = pickAny(src, fallback, names, defaultValue)
            % pickAny  Select the first meaningful value from one or more candidate fields.
            %
            % Consumes src, fallback, names, defaultValue; returns v.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = defaultValue;
            for k = 1:numel(names)
                f = names{k};
                if isstruct(src) && isfield(src,f) && ~isempty(src.(f))
                    v = src.(f);
                    return;
                end
            end
            for k = 1:numel(names)
                f = names{k};
                if isstruct(fallback) && isfield(fallback,f) && ~isempty(fallback.(f))
                    v = fallback.(f);
                    return;
                end
            end
        end


        function v = pickLogical(src, fallback, names, defaultValue)
            % pickLogical  Select and normalize a logical option from candidate fields.
            %
            % Consumes src, fallback, names, defaultValue; returns v.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = NMDataIOImportTargetTools.pickAny(src, fallback, names, defaultValue);
            if iscell(v)
                if isempty(v), v = defaultValue; else, v = v{1}; end
            end
            if ischar(v) || isa(v,'string')
                t = lower(strtrim(char(string(v))));
                if any(strcmp(t, {'true','1','yes','y','known','on'}))
                    v = true;
                elseif any(strcmp(t, {'false','0','no','n','unknown','off'}))
                    v = false;
                else
                    v = logical(defaultValue);
                end
            elseif isnumeric(v) || islogical(v)
                if isempty(v)
                    v = logical(defaultValue);
                else
                    v = logical(v(1));
                end
            else
                v = logical(defaultValue);
            end
        end

        function v = pickChar(src, fallback, names, defaultValue)
            % pickChar  Normalize a value into character text for legacy/DataIO metadata fields.
            %
            % Consumes src, fallback, names, defaultValue; returns v.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = NMDataIOImportTargetTools.pickAny(src, fallback, names, defaultValue);
            if isempty(v)
                v = defaultValue;
            end
            if iscell(v)
                if isempty(v), v = defaultValue; else, v = v{1}; end
            end
            v = char(string(v));
        end

        function v = pickNumeric(src, fallback, names, defaultValue)
            % pickNumeric  Normalize numeric scalar or vector input for DataIO state/spec fields.
            %
            % Consumes src, fallback, names, defaultValue; returns v.
            % It participates in target-aware import flow by distinguishing training NM from OOCV/application containers.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            v = NMDataIOImportTargetTools.pickAny(src, fallback, names, defaultValue);
            if iscell(v)
                if isempty(v), v = defaultValue; else, v = v{1}; end
            end
            if ischar(v) || isa(v,'string')
                n = str2double(char(string(v)));
                if isfinite(n), v = n; else, v = defaultValue; end
            end
        end
    end
end
