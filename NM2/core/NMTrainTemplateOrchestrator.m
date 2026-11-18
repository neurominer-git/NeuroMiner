classdef NMTrainTemplateOrchestrator < handle
% NMTrainTemplateOrchestrator
% -------------------------------------------------------------------------
% Minimal browser-shell backbone for the main NeuroMiner parameter-template
% menu. This class deliberately does not port nk_TrainClass_config in full.
% It coordinates fusion/modality selection and routes preprocessing plus ML
% configuration to the correct legacy TrainParam locations.
%
% Important legacy rule:
%   - Fusion flag 0/1/2: ML configuration is global and maps to
%       NM.TrainParam.SVM / NM.TrainParam.GRD
%   - Fusion flag 3: ML configuration is modality-specific and maps to
%       NM.TrainParam.STRAT{i}.SVM / NM.TrainParam.STRAT{i}.GRD
% -------------------------------------------------------------------------

    properties
        NM = struct()
        VarIndex = 1
        FusionFlag = 0
        FusionModalities = 1
        NumModalities = 1
        ModalityLabels = {}
        ModalityIsImaging = []
        Preproc = {}
        Stacking = struct('flag',2)
        StackingCandidates = struct('index',{},'label',{},'available',{},'nfeatures',{})
        StackingAvailable = false
        StackingPreproc
        MLGlobal
        MLStrat = {}
        AlternativeLabel = struct('flag',0)
        AlternativeLabelSourceVar = ''
        CVPartition = struct()
        Synth = struct()
        RFE = struct()
        Multi = struct()
        Vis = struct()
        MLI = struct()
        SAV = struct()
        CommittedConfigurators = {}
    end

    properties (Constant, Access = private)
        FusionChoices = struct('symbol', {'none','early','intermediate','late'}, ...
            'code', {0,1,2,3}, 'description', ...
            {'No fusion','Early fusion of selected modalities', ...
             'Intermediate fusion of selected modalities','Late fusion of modality-specific models'})
        StackingChoices = struct('symbol', {'enabled','disabled'}, ...
            'code', {1,2}, 'description', ...
            {'Enable stacking of predictions from other analyses','Disable stacking'})
    end

    methods (Static)
        function obj = fromNM(NM, varind, ctx)
            % FROMNM  Construct a train-template orchestrator from an existing NM workspace.
            %   Reads modality count, active modality, fusion/stacking context, CV/Synth/RFE/MULTI/VIS/MLI/SAV
            %   states and per-modality preprocessing/ML branches from NM.TrainParam. Returns a handle
            %   object that mirrors the legacy training template without running training.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2, varind = []; end
            if nargin < 3, ctx = struct(); end

            tFromNM = tic;
            t = tic;
            obj = NMTrainTemplateOrchestrator();
            constructDt = toc(t);
            doProfile = obj.profileEnabled(ctx);
            profileId = '-';
            if isstruct(ctx) && isfield(ctx,'NMProfileId') && ~isempty(ctx.NMProfileId)
                profileId = char(string(ctx.NMProfileId));
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s] fromNM ENTER\n', profileId);
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM object construction:       %.3fs\n', profileId, constructDt);
            fastChildOpen = NMUISessionTools.fastChildOpen(ctx);

            t = tic;
            obj.NM = NM;
            obj.NumModalities = obj.inferNumModalities(NM);
            obj.ModalityLabels = obj.inferModalityLabels(NM, obj.NumModalities);
            obj.ModalityIsImaging = obj.inferModalityIsImaging(NM, obj.NumModalities);
            % First entry must complete VIS/SAV defaults even if
            % DataIO has already supplied a partial TrainParam structure.
            if isfield(NM,'Y') % nm2-allow: DataIO creates Y on import; standalone template entry may have no observations.
                % nm2-allow: DataIO may supply partial TrainParam; nk_TrainClass_config initializes missing VIS and SAV on first entry.
                if ~isfield(NM,'TrainParam') || ~isfield(NM.TrainParam,'VIS') || ...
                        isempty(NM.TrainParam.VIS) || ...
                        ~isfield(NM.TrainParam,'SAV') || ... % nm2-allow: DataIO may supply partial TrainParam; nk_TrainClass_config initializes SAV on first entry.
                        isempty(NM.TrainParam.SAV)
                    NM = obj.ensureLegacyModuleDefaults(NM);
                    obj.NM = NM;
                end
            elseif ~isfield(NM,'TrainParam') % nm2-allow: No-data standalone entry has not passed the legacy nk_TrainClass_config initializer.
                NM.TrainParam = struct();
                obj.NM = NM;
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM NM/modality metadata:      %.3fs (modalities=%d)\n', ...
                profileId, toc(t), double(obj.NumModalities));

            t = tic;
            obj.AlternativeLabel = NMAlternativeLabelTools.extractLabel(NM);
            obj.AlternativeLabelSourceVar = '';
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM alternative label:         %.3fs\n', profileId, toc(t));

            t = tic;
            obj.StackingCandidates = obj.inferStackingCandidates(NM);
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM stacking candidates:       %.3fs (candidates=%d)\n', ...
                profileId, toc(t), double(numel(obj.StackingCandidates)));
            t = tic;
            obj.Stacking = obj.extractStackingState(NM);
            obj.Stacking = obj.completeStackingDefaults(obj.Stacking, obj.StackingCandidates, NM);
            obj.StackingAvailable = obj.inferStackingAvailable(NM, obj.Stacking, obj.StackingCandidates);
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM stacking state/availability: %.3fs (available=%d)\n', ...
                profileId, toc(t), double(obj.StackingAvailable));
            % Do not demote an explicit STACKING.flag == 1 merely because
            % the transient availability probe is negative. Availability is a
            % UI affordance; the active stacking state is carried by the
            % legacy STACKING flag and must survive canvas/menu refreshes.

            t = tic;
            obj.CVPartition = NMCVPartitionTools.stateFromNM(NM);
            obj.Synth = NMSynthTools.stateFromNM(NM);
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM CV/Synth:                   %.3fs\n', profileId, toc(t));

            t = tic;
            [flag, M, active] = obj.extractFusionState(NM, varind, obj.NumModalities);
            obj.FusionFlag = flag;
            obj.FusionModalities = M;
            obj.VarIndex = active;
            obj.normalizeFusionState();
            flag = obj.FusionFlag;
            active = obj.VarIndex;
            if obj.isStackingEnabled()
                obj.FusionFlag = 0;
                obj.FusionModalities = 1;
                obj.VarIndex = 1;
                flag = 0;
                active = 1;
            end
            obj.Preproc = cell(1, obj.NumModalities);
            if NMPreprocOrchestrator.isMissingLegacyPreproc(obj.extractLegacyPreproc(NM, active, flag))
                obj.materializePreprocBranch(active, false);
                NM = obj.NM;
            end
            obj.RFE = NMRFETools.stateFromNM(NM, active, flag);
            obj.Multi = NMMULTITools.stateFromNM(NM, active, flag);
            obj.Vis = NMVISTools.stateFromNM(NM, active, flag);
            obj.MLI = NMMLITools.stateFromNM(NM, active, flag);
            obj.SAV = NMSAVTools.stateFromNM(NM);
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM fusion + module states:     %.3fs\n', profileId, toc(t));

            tPreproc = tic;
            preprocSeconds = zeros(1, obj.NumModalities);
            if ~fastChildOpen
                for i = 1:obj.NumModalities
                    tBranch = tic;
                    obj.materializePreprocBranch(i, false);
                    preprocSeconds(i) = toc(tBranch);
                end
                NM = obj.NM;
            end
            preprocMax = 0;
            preprocMean = 0;
            if ~isempty(preprocSeconds) && ~fastChildOpen
                preprocMax = max(preprocSeconds);
                preprocMean = mean(preprocSeconds);
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM preprocessing branches:    %.3fs (n=%d mean=%.3fs max=%.3fs deferred=%d)\n', ...
                profileId, toc(tPreproc), double(obj.NumModalities), preprocMean, preprocMax, double(fastChildOpen));

            % Stacking gets its own explicit, non-imaging preprocessing branch.
            t = tic;
            if ~fastChildOpen
                stkPREPROC = obj.extractStackingPreproc(NM);
                NMstk = obj.withStackingFlag(NM, 1);
                obj.StackingPreproc = NMPreprocOrchestrator.fromNM(NMstk, 1, stkPREPROC, ...
                    'isImaging', false, 'isStackingInputLayer', true, ...
                    'isStackingAnalysisLayer', false, 'source', 'stacking');
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM stacking preprocessing:     %.3fs (deferred=%d)\n', ...
                profileId, toc(t), double(fastChildOpen));

            % Global ML maps to TrainParam.SVM/GRD outside late-fusion export.
            t = tic;
            if ~fastChildOpen
                obj.MLGlobal = NMTrainConfigOrchestrator.fromNM(obj.thinNMForML(NM, [], min(flag,2)), [], ctx);
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM global ML:                  %.3fs (deferred=%d)\n', ...
                profileId, toc(t), double(fastChildOpen));

            t = tic;
            obj.MLStrat = {};
            if flag == 3
                obj.MLStrat = cell(1, obj.NumModalities);
                if ~fastChildOpen
                    for i = 1:obj.NumModalities
                        obj.MLStrat{i} = NMTrainConfigOrchestrator.fromNM(obj.thinNMForML(NM, i, 3), i, ctx);
                    end
                end
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]   fromNM late-fusion ML:             %.3fs (deferred=%d)\n', ...
                profileId, toc(t), double(fastChildOpen));
            obj.profileLog(doProfile, '[nm-prof rid=%s] fromNM TOTAL: %.3fs\n', profileId, toc(tFromNM));
        end

        function nv = structToNameValues(s)
            % STRUCTTONAMEVALUES  Convert a scalar option struct into configure name/value pairs.
            %   Returns a 1-by-2N cell vector preserving field order. Non-scalar or non-struct
            %   inputs produce {}, allowing configure callers to pass optional structs safely.
            nv = {};
            if ~isstruct(s) || numel(s) ~= 1, return; end
            fn = fieldnames(s);
            nv = cell(1, 2*numel(fn));
            for ii = 1:numel(fn)
                nv{2*ii-1} = fn{ii};
                nv{2*ii} = s.(fn{ii});
            end
        end
    end

    methods
        function source = sequenceSourceCatalog(obj, module)
            % The stacking configuration owns the examination-node order.
            % Each selected analysis contributes its completed model sources.
            source = struct('node',{},'analysis',{},'part',{},'parts',{},'description',{},'completed',{});
            if strcmp(module,'ml_global') && obj.isStackingEnabled()
                selected = obj.Stacking.sel_anal;
                candidates = obj.StackingCandidates;
                for k = 1:numel(selected)
                    candidate = candidates([candidates.index] == selected(k));
                    n = candidate.nfeatures;
                    if ~isscalar(n) || ~isfinite(n) || n < 1 || n ~= fix(n)
                        error('NMTrainTemplateOrchestrator:invalidStackingSource', ...
                            'Invalid prediction-source count for analysis %d.',selected(k));
                    end
                    for part = 1:n
                        source(end+1) = struct('node',numel(source)+1, ... %#ok<AGROW>
                            'analysis',selected(k),'part',part,'parts',n, ...
                            'description',candidate.label,'completed',candidate.completed);
                    end
                end
            end
        end

        function paths = exportUI(obj, outDir, ctx)
            % EXPORTUI  Serialize this orchestrator into the browser training-template UI bundle.
            %   Synchronizes the active modality from NM, delegates asset/state export to NMTrainTemplateUI,
            %   and returns the generated path bundle. Side effect: writes browser files below outDir.
            if nargin < 3, ctx = struct(); end
            obj.syncActiveModalityFromNM();
            paths = NMTrainTemplateUI.export(obj, outDir, ctx);
        end

        function obj = importUpdatedUI(obj, pathsOrWebDir, ctx)
            % IMPORTUPDATEDUI  Rehydrate this handle from a browser-edited UI session.
            %   Delegates import to NMTrainTemplateUI.importUpdated and returns the possibly updated
            %   orchestrator object. Side effect: may mutate this handle from the serialized session state.
            if nargin < 3, ctx = struct(); end
            obj = NMTrainTemplateUI.importUpdated(obj, pathsOrWebDir, ctx);
        end

        function obj = openUI(obj, outDir, ctx, port)
            % OPENUI  Launch the browser training-template editor for this orchestrator.
            %   Exports the UI bundle, starts the local bridge on the optional port, and imports the
            %   session result when the browser closes. It edits configuration only; it does not train models.
            if nargin < 2 || isempty(outDir), outDir = fullfile(tempdir, 'nm_train_template_ui'); end
            if nargin < 3, ctx = struct(); end
            if nargin < 4, port = []; end
            obj = NMTrainTemplateUI.open(obj, outDir, ctx, port);
        end

        function NM = getNM(obj)
            % GETNM  Return the orchestrator's current MATLAB-side NM snapshot.
            %   Immediate UI actions update this snapshot while the browser session is open. Full legacy
            %   TrainParam materialization remains explicit through toNM().
            NM = obj.NM;
        end


        function [obj, report] = cli_configure(obj, varargin)
            % CLI_CONFIGURE  Compatibility wrapper for programmatic train-template configuration.
            %   Forwards all name/value or scalar-struct edits to configure() and returns the updated
            %   handle plus the configuration report. Side effect: same object mutations as configure().
            [obj, report] = obj.configure(varargin{:});
        end


        function [obj, report] = configure(obj, varargin)
            % CONFIGURE  Apply programmatic edits to modular training-template state.
            %   Accepts name/value pairs or a scalar option struct, validates module-specific payloads
            %   through their configure APIs, updates fusion/stacking/active-modality context, and persists
            %   lightweight context into obj.NM. It does not build CV artifacts or run training.
            report = struct('ok', true, 'errors', {{}}, 'warnings', {{}}, 'details', struct());
            if isempty(varargin), return; end
            stackingWasEnabled = obj.isStackingEnabled();
            if numel(varargin) == 1 && isstruct(varargin{1})
                varargin = NMTrainTemplateOrchestrator.structToNameValues(varargin{1});
            end
            if mod(numel(varargin),2) ~= 0
                error('NMTrainTemplateOrchestrator:badConfigureArgs', ...
                    'Configure arguments must be name/value pairs.');
            end
            for k = 1:2:numel(varargin)
                key = char(varargin{k});
                val = varargin{k+1};
                switch key
                    case 'VarIndex'
                        v = round(double(val));
                        if ~isfinite(v) || v < 1 || v > obj.NumModalities, v = 1; end
                        obj.VarIndex = v;
                    case 'FusionFlag'
                        obj.FusionFlag = obj.clampFusionFlag(val);
                    case 'FusionModalities'
                        obj.FusionModalities = obj.normalizeModalities(val, obj.NumModalities, obj.VarIndex);
                    case 'Stacking'
                        if isstruct(val)
                            obj.Stacking = obj.completeStackingDefaults(NMConfigTools.mergeStruct(obj.Stacking, val), obj.StackingCandidates, obj.NM);
                        end
                    case 'StackingFlag'
                        obj.Stacking.flag = obj.clampStackingFlag(val);
                    case 'AlternativeLabel'
                        src = obj.AlternativeLabelSourceVar;
                        [obj.NM, obj.AlternativeLabel, src, rep] = NMAlternativeLabelTools.cli_configure(obj.NM, val, 'VarIndex', obj.VarIndex);
                        obj.AlternativeLabelSourceVar = src;
                        report.details.alternativeLabel = rep;
                    case 'AlternativeLabelSourceVar'
                        obj.AlternativeLabelSourceVar = char(string(val));
                    case 'CVPartition'
                        [~, obj.CVPartition, rep] = NMCVPartitionTools.cli_configure(obj.NM, val, ...
                            'cvBuildRequested', false, 'cvLoadRequested', false, 'cvSaveRequested', false);
                        report.details.cv = rep;
                    case 'Synth'
                        [~, obj.Synth, rep] = NMSynthTools.cli_configure(obj.NM, val);
                        report.details.synth = rep;
                    case 'RFE'
                        [~, obj.RFE, rep] = NMRFETools.cli_configure(obj.NM, val, ...
                            'VarIndex', obj.VarIndex, 'FusionFlag', obj.FusionFlag);
                        report.details.rfe = rep;
                    case 'Multi'
                        [~, obj.Multi, rep] = NMMULTITools.cli_configure(obj.NM, val, ...
                            'VarIndex', obj.VarIndex, 'FusionFlag', obj.FusionFlag);
                        report.details.multi = rep;
                    case 'Vis'
                        [~, obj.Vis, rep] = NMVISTools.cli_configure(obj.NM, val, ...
                            'VarIndex', obj.VarIndex, 'FusionFlag', obj.FusionFlag);
                        report.details.vis = rep;
                    case 'MLI'
                        [~, obj.MLI, rep] = NMMLITools.cli_configure(obj.NM, val, ...
                            'VarIndex', obj.VarIndex, 'FusionFlag', obj.FusionFlag);
                        report.details.mli = rep;
                    case 'SAV'
                        [~, obj.SAV, rep] = NMSAVTools.cli_configure(obj.NM, val);
                        report.details.sav = rep;
                    case 'Preproc'
                        if iscell(val), obj.Preproc = val; else, error('NMTrainTemplateOrchestrator:badPreproc', 'Preproc must be a cell array of NMPreprocOrchestrator objects.'); end
                    case 'StackingPreproc'
                        obj.StackingPreproc = val;
                    case 'MLGlobal'
                        obj.MLGlobal = val;
                    case 'MLStrat'
                        obj.MLStrat = val;
                    otherwise
                        error('NMTrainTemplateOrchestrator:unknownConfigureOption', ...
                            'Unknown train-template configure option: %s.', varargin{k});
                end
            end
            if ~stackingWasEnabled && obj.isStackingEnabled() && ~obj.StackingAvailable
                obj.Stacking.flag = 2;
            end
            obj.normalizeStackingState();
            obj.normalizeFusionState();
            obj.persistContextToNM();
        end


        function h = cli_configureHelp(obj)
            % CLI_CONFIGUREHELP  Return CLI-compatible help for train-template configuration.
            %   Delegates to configureHelp() and appends the legacy cli_configureHelp syntax entry used
            %   by command-line callers. No orchestrator state is modified.
            h = obj.configureHelp();
            h.syntax{end+1} = 'h = orch.cli_configureHelp()';
        end


        function h = configureHelp(obj)
            % CONFIGUREHELP  Describe accepted programmatic configure() options.
            %   Returns a JSON/documentation-ready schema for modality selection, fusion, stacking,
            %   alternative labels, CV, preprocessing, ML, visualization, MLI and save/verbosity state.
            h = struct();
            h.className = 'NMTrainTemplateOrchestrator';
            h.title = 'Training-template orchestration';
            h.kind = 'configure-api-help';
            h.acceptsExistingConfiguration = true;
            h.syntax = {
                'orch = NMTrainTemplateOrchestrator.fromNM(NM, varind, ctx)';
                '[orch,report] = orch.configure(name, value, ...)';
                '[orch,report] = orch.configure(stateStruct)';
                'NM = orch.toNM(NM, ctx)';
                };
            h.description = 'Named-argument API for composing train-template subconfiguration states. It validates sub-states through their own configure() APIs and delegates legacy TrainParam generation to toNM().';
            h.options = {
                struct('name','VarIndex','description','Active modality index.');
                struct('name','FusionFlag','description','Fusion strategy; symbolic choices and legacy codes in h.choices.FusionFlag.');
                struct('name','FusionModalities','description','Selected modality indices for fusion.');
                struct('name','Stacking','description','Stacking state; flag accepts enabled (1) or disabled (2).');
                struct('name','StackingFlag','description','Stacking flag; symbolic choices and legacy codes in h.choices.StackingFlag.');
                struct('name','AlternativeLabel','description','Alternative-label LABEL struct validated by NMAlternativeLabelTools.cli_configure().');
                struct('name','CVPartition','description','CV state validated by NMCVPartitionTools.cli_configure().');
                struct('name','Synth','description','Synthetic-data state validated by NMSynthTools.cli_configure().');
                struct('name','RFE','description','RFE/ensemble state validated by NMRFETools.cli_configure().');
                struct('name','Multi','description','Multi-class state validated by NMMULTITools.cli_configure().');
                struct('name','Vis','description','Visualization state validated by NMVISTools.cli_configure().');
                struct('name','MLI','description','MLI state validated by NMMLITools.cli_configure().');
                struct('name','SAV','description','Saving/verbosity state validated by NMSAVTools.cli_configure().');
                struct('name','Preproc','description','Cell array of NMPreprocOrchestrator branches already rebuilt through preprocessing APIs.');
                struct('name','MLGlobal','description','NMTrainConfigOrchestrator for the global ML branch.');
                struct('name','MLStrat','description','Cell array of late-fusion NMTrainConfigOrchestrator branches.');
                };
            h.choices.FusionFlag = obj.FusionChoices;
            h.choices.StackingFlag = obj.StackingChoices;
            h.examples = {
                sprintf('orch = NMTrainTemplateOrchestrator.fromNM(NM, 1, ctx); [orch,rep] = orch.configure(''FusionFlag'',0, ''CVPartition'',cvState, ''SAV'',savState); NM = orch.toNM(NM, ctx);');
                sprintf('[orch,rep] = orch.configure(''Preproc'',preprocBranches, ''MLGlobal'',mlGlobal);');
                };
            h.validationRules = {
                'Subconfiguration validation is delegated to the specific configure() APIs.';
                'Legacy TrainParam generation remains centralized in toNM().';
                };
            h.notes = {'Use configureHelp() on each submodule for detailed option discovery.'};
        end

        function pp = materializePreprocBranch(obj, idx, isStacking)
            % MATERIALIZEPREPROCBRANCH  Construct one preprocessing authority on demand.
            if nargin < 3, isStacking = false; end
            if isStacking
                if ~isempty(obj.StackingPreproc), pp = obj.StackingPreproc; return; end
                stkPREPROC = obj.extractStackingPreproc(obj.NM);
                NMstk = obj.withStackingFlag(obj.NM, 1);
                obj.StackingPreproc = NMPreprocOrchestrator.fromNM(NMstk, 1, stkPREPROC, ...
                    'isImaging', false, 'isStackingInputLayer', true, ...
                    'isStackingAnalysisLayer', false, 'source', 'stacking');
                pp = obj.StackingPreproc;
                return;
            end
            idx = round(double(idx));
            if ~isfinite(idx) || idx < 1 || idx > obj.NumModalities
                error('NMTrainTemplateOrchestrator:badPreprocIndex', ...
                    'Invalid preprocessing modality index: %g.', double(idx));
            end
            if numel(obj.Preproc) < obj.NumModalities, obj.Preproc{obj.NumModalities} = []; end
            if ~isempty(obj.Preproc{idx}), pp = obj.Preproc{idx}; return; end
            PREPROC = obj.extractLegacyPreproc(obj.NM, idx, obj.FusionFlag);
            if NMPreprocOrchestrator.isMissingLegacyPreproc(PREPROC)
                PREPROC = NMPreprocOrchestrator.defaultSetting(obj.NM, idx);
                if ~isfield(obj.NM.TrainParam,'PREPROC') % nm2-allow: legacy nk_TrainClass_config writes PREPROC only after modality setup; an older template may omit this branch.
                    obj.NM.TrainParam.PREPROC = cell(1, obj.NumModalities);
                end
                if ~iscell(obj.NM.TrainParam.PREPROC)
                    error('NMTrainTemplateOrchestrator:invalidPreprocSchema', ...
                        'TrainParam.PREPROC must be a cell array indexed by modality.');
                end
                obj.NM.TrainParam.PREPROC{idx} = PREPROC;
            end
            obj.Preproc{idx} = NMPreprocOrchestrator.fromNM(obj.NM, idx, PREPROC);
            pp = obj.Preproc{idx};
        end

        function mlOrch = materializeMLBranch(obj, module, ctx)
            % MATERIALIZEMLBRANCH  Construct one ML authority on demand.
            if nargin < 3, ctx = struct(); end
            module = char(string(module));
            if isempty(module), module = 'ml_global'; end
            if strcmp(module,'ml_global')
                if ~isempty(obj.MLGlobal), mlOrch = obj.MLGlobal; return; end
                obj.MLGlobal = NMTrainConfigOrchestrator.fromNM( ...
                    obj.thinNMForML(obj.NM, [], min(obj.FusionFlag,2)), [], ctx);
                mlOrch = obj.MLGlobal;
                return;
            end
            if ~startsWith(module,'ml_var')
                error('NMTrainTemplateOrchestrator:badMLModule','Invalid ML module: %s.',module);
            end
            idx = str2double(extractAfter(module,'ml_var'));
            if ~isfinite(idx) || idx < 1 || idx > obj.NumModalities
                error('NMTrainTemplateOrchestrator:badMLModule','Invalid ML module: %s.',module);
            end
            if numel(obj.MLStrat) < obj.NumModalities, obj.MLStrat{obj.NumModalities} = []; end
            if ~isempty(obj.MLStrat{idx}), mlOrch = obj.MLStrat{idx}; return; end
            obj.MLStrat{idx} = NMTrainConfigOrchestrator.fromNM( ...
                obj.thinNMForML(obj.NM, idx, 3), idx, ctx);
            mlOrch = obj.MLStrat{idx};
        end

        function materializeOverviewChildren(obj, ctx)
            % MATERIALIZEOVERVIEWCHILDREN  Materialize only authorities used by the active analysis overview.
            if nargin < 2, ctx = struct(); end
            if obj.isStackingEnabled()
                obj.materializePreprocBranch(1,true);
                obj.materializeMLBranch('ml_global',ctx);
                return;
            end
            M = obj.VarIndex;
            if obj.FusionFlag > 0, M = obj.FusionModalities; end
            if obj.FusionFlag == 1
                obj.materializePreprocBranch(M(1),false);
            else
                for ii = 1:numel(M), obj.materializePreprocBranch(M(ii),false); end
            end
            if obj.FusionFlag == 3
                for ii = 1:numel(M), obj.materializeMLBranch(sprintf('ml_var%d',M(ii)),ctx); end
            else
                obj.materializeMLBranch('ml_global',ctx);
            end
        end

        function state = menuState(obj, opts)
            % menuState  Build the browser-facing training-template state model.
            %
            % Assembles lightweight module states, audit results, canvas graph, methods text, summary
            % strings and heavy-array references for the active NM context. The method is non-training;
            % it may refresh cached configurator state when the context changed.
            %
            % opts.includeCanvas: configures optional include canvas behavior for this call.
            if nargin < 2 || isempty(opts), opts = struct(); end
            includeCanvas = true;
            if isstruct(opts) && isfield(opts,'includeCanvas')
                try, includeCanvas = logical(opts.includeCanvas); catch, includeCanvas = true; end
            end
            doProfile = obj.profileEnabled(opts);
            profileId = '-';
            if isstruct(opts) && isfield(opts,'profileId') && ~isempty(opts.profileId)
                profileId = char(string(opts.profileId));
            elseif isstruct(opts) && isfield(opts,'NMProfileId') && ~isempty(opts.NMProfileId)
                profileId = char(string(opts.NMProfileId));
            end

            if includeCanvas, obj.materializeOverviewChildren(struct()); end
            childrenReady = includeCanvas || (numel(obj.Preproc) >= obj.NumModalities && ...
                ~any(cellfun(@isempty,obj.Preproc)) && ~isempty(obj.StackingPreproc) && ~isempty(obj.MLGlobal));
            if ~includeCanvas && obj.FusionFlag == 3
                childrenReady = childrenReady && numel(obj.MLStrat) >= obj.NumModalities && ...
                    ~any(cellfun(@isempty,obj.MLStrat));
            end
            tMenu = tic;
            state = struct();

            t = tic;
            state.fusionFlag = obj.FusionFlag;
            state.fusionModalities = obj.FusionModalities;
            state.activeModality = obj.VarIndex;
            state.numModalities = obj.NumModalities;
            state.modalityLabels = obj.ModalityLabels;
            state.modalityIsImaging = obj.ModalityIsImaging;
            % nm2-allow: NMSimulationTools writes fullySyntheticDefinition only for placeholder workspaces.
            state.fullySyntheticMode=isfield(obj.NM,'SYNTH') && isfield(obj.NM.SYNTH,'fullySyntheticDefinition');
            state.fullySyntheticMulticlass=false;
            if state.fullySyntheticMode
                d=obj.NM.SYNTH.fullySyntheticDefinition;
                state.fullySyntheticMulticlass=strcmp(d.modeflag,'classification') && d.classCount>2;
            end
            [state.atlasSplitFlags, state.atlasSplitFamilyKeys, state.atlasSplitRoiNames] = obj.atlasSplitMenuMetadata();
            state.isImaging = obj.activeModalityIsImaging();
            alt = NMAlternativeLabelTools.menuFields(obj.NM, obj.AlternativeLabel, obj.AlternativeLabelSourceVar);
            state = NMConfigTools.mergeStruct(state, alt);
            state = NMConfigTools.mergeStruct(state, obj.multiLabelMenuFields());
            state.cv = obj.CVPartition;
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState base/context:     %.3fs\n', profileId, toc(t));

            t = tic;
            [ppAllTxt, ppAllCount, ppAllSubjCount, ppAllCVCount, ppAllLabels] = obj.preprocSummariesForAll();
            state.preprocSummaries = ppAllTxt;
            state.preprocStepCounts = ppAllCount;
            state.preprocSubjectStepCounts = ppAllSubjCount;
            state.preprocCVStepCounts = ppAllCVCount;
            state.preprocStepLabelsByModality = ppAllLabels;
            state.preprocStoredByModality = obj.legacyPreprocPresence();
            if obj.isStackingEnabled()
                if isempty(obj.StackingPreproc)
                    ppTxt = 'STACKING.PREPROC details load on demand.';
                    ppCount = 0; ppSubjCount = 0; ppCVCount = 0; ppLabels = {};
                else
                    [ppTxt, ppCount, ppSubjCount, ppCVCount, ppLabels] = ...
                        obj.preprocSummaryForObject(obj.StackingPreproc, 'STACKING.PREPROC');
                end
            else
                ppIdx = obj.VarIndex;
                if obj.FusionFlag == 1 && ~isempty(obj.FusionModalities), ppIdx = obj.FusionModalities(1); end
                ppTxt = ppAllTxt{ppIdx}; ppCount = ppAllCount(ppIdx);
                ppSubjCount = ppAllSubjCount(ppIdx); ppCVCount = ppAllCVCount(ppIdx);
                ppLabels = ppAllLabels{ppIdx};
            end
            state.preprocSummary = ppTxt;
            state.preprocStepCount = ppCount;
            state.preprocSubjectStepCount = ppSubjCount;
            state.preprocCVStepCount = ppCVCount;
            state.preprocStepLabels = ppLabels;
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState preprocessing:     %.3fs\n', profileId, toc(t));
            t = tic;
            state.synth = obj.Synth;
            state.synthSummary = NMSynthTools.summary(obj.Synth);
            state.rfe = obj.RFE;
            state.rfeSummary = NMRFETools.summary(obj.RFE);
            state.multi = obj.Multi;
            [isMulti, nMultiClasses, multiClassLabels] = NMAlternativeLabelTools.effectiveClassInfo(obj.NM);
            state.isMultiClassProblem = isMulti;
            state.multiAvailable = isMulti;
            if isstruct(state.multi)
                state.multi.multiAvailable = isMulti;
                state.multi.multiClassCount = nMultiClasses;
                state.multi.multiClassLabels = multiClassLabels;
            end
            state.multiSummary = NMMULTITools.summary(state.multi);
            state.vis = obj.Vis;
            state.visSummary = NMVISTools.summary(obj.Vis);
            state.mli = obj.MLI;
            state.mliSummary = NMMLITools.summary(obj.MLI);
            state.sav = obj.SAV;
            state.savSummary = NMSAVTools.summarySaving(obj.SAV);
            state.verbosity = obj.SAV.verbosity;
            state.verbosityValue = obj.SAV.verbosityValue;
            state.verbositySummary = NMSAVTools.summaryVerbosity(obj.SAV);
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState module summaries:  %.3fs\n', profileId, toc(t));

            tStackingGuards = tic;
            t = tic;
            state.stackingAvailable = obj.StackingAvailable;
            state.stackingFlag = obj.Stacking.flag;
            state.stackingEnabled = obj.isStackingEnabled();
            state.seqoptStacking = obj.isSeqoptStacking();
            state.stackingPreprocModule = 'preproc_stacking';
            [idx, lab, av, nf] = obj.stackingCandidateArrays();
            state.stackingCandidateIndices = idx;
            state.stackingCandidateLabels = lab;
            state.stackingCandidateAvailable = av;
            state.stackingCandidateNFeatures = nf;
            obj.profileLog(doProfile, '[nm-prof rid=%s]       stacking candidate projection: %.3fs (n=%d)\n', profileId, toc(t), double(numel(idx)));

            t = tic;
            state.stackingSelectedAnalyses = obj.getStackingSelectedAnalyses();
            state.stackingFeatureNameMode = obj.getStackingNumericField('featname_mode', 1, [1 2]);
            state.stackingFeatureNameVariable = obj.getStackingCharField('featname_edit', '?');
            state.stackingPredictionMode = obj.getStackingNumericField('mode', 2, [1 2]);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       stacking selection/settings:  %.3fs\n', profileId, toc(t));

            t = tic;
            state.navigationPath = 'Define parameter template';
            state.mlScope = obj.currentMLScope();
            state.mlSummary = obj.mlSummaryForActive();
            obj.profileLog(doProfile, '[nm-prof rid=%s]       stacking ML scope/summary:     %.3fs\n', profileId, toc(t));

            t = tic;
            [badPP, badMsg, badSteps] = obj.mixedEarlyFusionPreprocGuard();
            state.preprocMixedEarlyFusionIllegal = badPP;
            state.preprocMixedEarlyFusionMessage = badMsg;
            state.preprocMixedEarlyFusionIllegalSteps = badSteps;
            obj.profileLog(doProfile, '[nm-prof rid=%s]       mixed-fusion preproc guard:    %.3fs\n', profileId, toc(t));

            t = tic;
            [ppIssues, ppIssueMsg] = obj.preprocAvailabilityIssues();
            state.preprocAvailabilityIssues = ppIssues;
            state.preprocAvailabilityInvalid = ~isempty(ppIssues) && any(strcmpi({ppIssues.severity}, 'error'));
            state.preprocAvailabilityMessage = ppIssueMsg;
            state.preprocNeedsReview = logical(state.preprocMixedEarlyFusionIllegal) || ~isempty(ppIssues);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       preproc availability guard:    %.3fs (issues=%d)\n', profileId, toc(t), double(numel(ppIssues)));
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState stacking/guards:   %.3fs\n', profileId, toc(tStackingGuards));

            t = tic;
            if childrenReady
                state.audit = obj.auditCurrentState(state);
                state.auditSummary = obj.auditSummary(state.audit);
            else
                state.audit = obj.auditEmptyItems();
                state.auditSummary = obj.auditSummary(state.audit);
                state.auditSummary.severity = 'info';
                state.auditSummary.displayText = 'Detailed preprocessing/ML audit loads on demand.';
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState audit:             %.3fs\n', profileId, toc(t));

            if includeCanvas
                t = tic;
                state.canvas = obj.canvasState(state, state.audit, opts);
                obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState canvas:            %.3fs\n', profileId, toc(t));
            else
                state.canvas = obj.canvasEmptyState();
            end
            obj.profileLog(doProfile, '[nm-prof rid=%s]     menuState TOTAL:             %.3fs\n', profileId, toc(tMenu));
        end

        function tf = profileEnabled(obj, opts) %#ok<INUSL>
            % profileEnabled  Determine whether menu-state profiling should be emitted.
            %
            % Checks opts/ProfileEnabled and environment switches used while profiling browser refresh
            % latency. Returns a logical flag and does not alter orchestrator or NM state.
            %
            % opts.nmProfile: configures optional nm profile behavior for this call.
            % opts.profile: configures optional profile behavior for this call.
            % opts.profileEnabled: configures optional profile enabled behavior for this call.
            tf = false;
            try
                env = getenv('NM_UI_PROFILE');
                if ~isempty(env)
                    tf = any(strcmpi(strtrim(env), {'1','true','on','yes'}));
                end
            catch
                tf = false;
            end
            try
                if nargin >= 2 && isstruct(opts)
                    if isfield(opts,'profile')
                        tf = logical(opts.profile);
                    elseif isfield(opts,'profileEnabled')
                        tf = logical(opts.profileEnabled);
                    elseif isfield(opts,'nmProfile')
                        tf = logical(opts.nmProfile);
                    end
                end
            catch
            end
        end

        function profileLog(obj, enabled, varargin) %#ok<INUSL>
            % PROFILELOG  Emit a formatted menu-state profiling line when enabled.
            %   Uses fprintf-style varargin only when the caller supplied a true profiling flag. This is
            %   diagnostic output only and has no effect on generated training-template state.
            if ~enabled, return; end
            try
                fprintf(varargin{:});
            catch
            end
        end

        function applyAlternativeLabelContext(obj, ctx)
            % APPLYALTERNATIVELABELCONTEXT  Materialize LABEL and rebuild dependent live configurator state.
            %   This is the single same-session transition from alternative-label editor state to the
            %   effective preprocessing/ML/Canvas context. It preserves this handle's identity because
            %   the browser service closure retains the original handle for the lifetime of the UI.
            if nargin < 2, ctx = struct(); end
            sourceVar = obj.AlternativeLabelSourceVar;
            [NM0, action] = NMAlternativeLabelTools.applyToNM(obj.NM, obj.AlternativeLabel, obj.VarIndex);
            rebuildVar = obj.VarIndex; if any(strcmp(action, {'reset','restore'})), rebuildVar = []; end
            rebuilt = NMTrainTemplateOrchestrator.fromNM(NM0, rebuildVar, ctx); rebuilt.AlternativeLabelSourceVar = sourceVar;
            props = properties(obj); for ii = 1:numel(props), obj.(props{ii}) = rebuilt.(props{ii}); end
        end

        function ctx = refreshContextSnapshot(obj)
            % REFRESHCONTEXTSNAPSHOT  Capture the context that invalidates cached module states.
            %   Returns active modality, fusion mode/modalities, stacking flag and related context fields
            %   used by refreshContextChanged() to decide whether configurator states must be rebuilt.
            ctx = struct('varIndex',obj.VarIndex, 'fusionFlag',obj.FusionFlag, ...
                'fusionModalities',obj.FusionModalities, 'stackingFlag',obj.Stacking.flag, ...
                'stackingSelectedAnalyses',obj.getStackingSelectedAnalyses());
        end

        function tf = refreshContextChanged(obj, a, b) %#ok<INUSL>
            % REFRESHCONTEXTCHANGED  Compare two refresh-context snapshots.
            %   Returns true when modality, fusion or stacking context changed enough that cached module
            %   browser states should be regenerated rather than reused.
            tf = true;
            try
                tf = ~isequal(a.varIndex, b.varIndex) || ...
                    ~isequal(a.fusionFlag, b.fusionFlag) || ...
                    ~isequal(a.fusionModalities, b.fusionModalities) || ...
                    ~isequal(a.stackingFlag, b.stackingFlag) || ...
                    ~isequal(a.stackingSelectedAnalyses, b.stackingSelectedAnalyses);
            catch
                tf = true;
            end
        end

        function src = menuHeavyFieldSource(obj)
            % MENUHEAVYFIELDSOURCE  Provide live MATLAB arrays for browser x_nmref restoration.
            %   Returns the authoritative CV indices and module substates that may have been stripped to
            %   lightweight descriptors before browser serialization. Used by applyMenuState before merging
            %   posted state so heavy arrays are not overwritten by their descriptors.
            src = struct();
            src.cv    = obj.CVPartition;
            src.synth = obj.Synth;
            src.rfe   = obj.RFE;
            src.multi = obj.Multi;
            src.vis   = obj.Vis;
            src.mli   = obj.MLI;
            src.sav   = obj.SAV;
        end

        function audit = auditCurrentState(obj, state)
            % AUDITCURRENTSTATE  Run the lightweight configuration audit for the current menu state.
            %   Combines fusion, preprocessing, ML, MULTI, RFE, VIS, MLI and saving checks into a fixed
            %   audit struct. The audit reads orchestrator state only and must not materialize TrainParam.
            if nargin < 2 || isempty(state) || ~isstruct(state)
                state = obj.auditMinimalState();
            end
            items = {};
            items = [items, obj.auditFusion(state)]; %#ok<AGROW>
            items = [items, obj.auditPreproc(state)]; %#ok<AGROW>
            items = [items, obj.auditML(state)]; %#ok<AGROW>
            items = [items, obj.auditMULTI(state)]; %#ok<AGROW>
            items = [items, obj.auditRFE(state)]; %#ok<AGROW>
            items = [items, obj.auditVIS(state)]; %#ok<AGROW>
            items = [items, obj.auditMLI(state)]; %#ok<AGROW>
            items = [items, obj.auditSaving(state)]; %#ok<AGROW>
            if isempty(items)
                audit = obj.auditEmptyItems();
            else
                audit = [items{:}];
            end
        end

        function summary = auditSummary(obj, audit) %#ok<INUSL>
            % AUDITSUMMARY  Collapse detailed audit items into browser summary counters.
            %   Counts errors, warnings and informational items and returns the highest severity label.
            %   Input audit items are not modified.
            if nargin < 2 || isempty(audit)
                audit = obj.auditEmptyItems();
            end
            if iscell(audit), audit = [audit{:}]; end
            summary = struct('severity','ok', 'nErrors',0, 'nWarnings',0, ...
                'nInfo',0, 'nOk',0, 'ok',true, 'topItem',struct(), ...
                'displayText','Configuration audit OK.', 'byConfigurator',struct());
            if isempty(audit)
                summary.displayText = 'Configuration audit OK: no audit items.';
                return;
            end
            sev = cell(1, numel(audit));
            for ii = 1:numel(audit)
                if isfield(audit(ii),'severity') && ~isempty(audit(ii).severity)
                    sev{ii} = lower(char(string(audit(ii).severity)));
                else
                    sev{ii} = 'info';
                end
            end
            summary.nErrors = sum(strcmp(sev,'error'));
            summary.nWarnings = sum(strcmp(sev,'warning'));
            summary.nInfo = sum(strcmp(sev,'info'));
            summary.nOk = sum(strcmp(sev,'ok'));
            summary.ok = summary.nErrors == 0;
            if summary.nErrors > 0
                summary.severity = 'error';
            elseif summary.nWarnings > 0
                summary.severity = 'warning';
            else
                summary.severity = 'ok';
            end
            rank = zeros(1,numel(audit));
            rank(strcmp(sev,'error')) = 4;
            rank(strcmp(sev,'warning')) = 3;
            rank(strcmp(sev,'info')) = 2;
            rank(strcmp(sev,'ok')) = 1;
            [~, ix] = max(rank);
            if ~isempty(ix) && ix >= 1, summary.topItem = audit(ix); end
            if summary.nErrors > 0
                summary.displayText = sprintf('Configuration audit found %d error(s) and %d warning(s).', summary.nErrors, summary.nWarnings);
            elseif summary.nWarnings > 0
                summary.displayText = sprintf('Configuration audit found %d warning(s) and %d informational item(s).', summary.nWarnings, summary.nInfo);
            else
                summary.displayText = sprintf('Configuration audit OK: no blocking warnings or errors (%d informational items).', summary.nInfo);
            end
            by = struct();
            for ii = 1:numel(audit)
                cfg = 'general';
                if isfield(audit(ii),'configurator') && ~isempty(audit(ii).configurator)
                    cfg = matlab.lang.makeValidName(char(string(audit(ii).configurator)));
                end
                if ~isfield(by,cfg)
                    by.(cfg) = struct('nErrors',0,'nWarnings',0,'nInfo',0,'nOk',0);
                end
                switch sev{ii}
                    case 'error', by.(cfg).nErrors = by.(cfg).nErrors + 1;
                    case 'warning', by.(cfg).nWarnings = by.(cfg).nWarnings + 1;
                    case 'ok', by.(cfg).nOk = by.(cfg).nOk + 1;
                    otherwise, by.(cfg).nInfo = by.(cfg).nInfo + 1;
                end
            end

            summary.byConfigurator = by;
        end

        function canvas = canvasState(obj, state, audit, opts)
            % canvasState  Build the browser flowchart model for the active analysis design.
            %
            % Uses the current fusion/stacking/preprocessing/learner state and audit status to produce
            % fixed-schema nodes, edges, legends and detail mode metadata. It renders the configured flow,
            % not every available configurator.
            %
            % state.audit: carries the audit value between browser/API state and legacy NeuroMiner structures.
            if nargin < 4 || isempty(opts), opts = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state)
                try
                    state = obj.auditMinimalState();
                catch
                    state = struct();
                end
            end
            if nargin < 3 || isempty(audit)
                if isfield(state,'audit')
                    audit = state.audit;
                else
                    audit = obj.auditCurrentState(state);
                end
            end
            if iscell(audit), audit = [audit{:}]; end

            doProfile = obj.profileEnabled(opts);
            profileId = '-';
            if isstruct(opts) && isfield(opts,'profileId') && ~isempty(opts.profileId)
                profileId = char(string(opts.profileId));
            elseif isstruct(opts) && isfield(opts,'NMProfileId') && ~isempty(opts.NMProfileId)
                profileId = char(string(opts.NMProfileId));
            end
            tCanvasReserve = tic;
            [nodeCapacity, edgeCapacity] = obj.canvasCapacityHint(state);
            nodes = obj.canvasPreallocateNodes(nodeCapacity);
            edges = obj.canvasPreallocateEdges(edgeCapacity);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       canvas prealloc:           %.3fs (nodes=%d, edges=%d)\n', ...
                profileId, toc(tCanvasReserve), nodeCapacity, edgeCapacity);

            tCanvasFlow = tic;
            flag = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            isStack = obj.canvasLogicalField(state,'stackingEnabled',obj.isStackingEnabled());
            if ~isStack
                isStack = obj.canvasGetScalar(state,'stackingFlag',obj.Stacking.flag) == 1;
            end
            synthActive = obj.canvasSynthEnabled(state) || obj.canvasHasAudit(audit,'synth');

            cvNode = obj.canvasNode('cross_validation','Cross-validation / partitioning', ...
                obj.canvasCVScopeCompactSummary(state), 'cv', obj.canvasCVScopeSummary(state), audit, 'cv', {}, false, ...
                'type','partition_scope','lane',20,'order',1,'shape','scope','group','execution','columnLabel','Partitioning scope');

            if isStack
                % K3i: cross-validation is rendered as an interactive scope
                % container rather than as an ordinary processing node.  In
                % stacking, first-tier analyses live inside this scope because
                % their prediction outputs are generated within the same CV
                % experiment.
                nodes = obj.canvasAppendNode(nodes, cvNode);
                [nodes, edges, terminalId] = obj.canvasAppendStackingFlowK3(nodes, edges, state, audit, synthActive);
            else
                showCovariates = obj.canvasShowCovariateCard();
                inputRowOffset = 1 + double(showCovariates);
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode('data_labels','Labels', ...
                    obj.canvasSubtitleFromState(state), 'altlabel', char(string(state.altLabelSummary)), audit, 'altlabel', {}, false, ...
                    'type','label','lane',10,'order',1,'row',0,'shape','roundbox','group','data','columnLabel','Input'));
                if showCovariates
                    nodes = obj.canvasAppendNode(nodes, obj.canvasNode('data_covariates','Covariates', ...
                        obj.canvasCovariateSubtitle(), 'covariates', obj.canvasCovariateSummary(), audit, 'covariates', {}, false, ...
                        'type','covariate','lane',10,'order',2,'row',1,'shape','roundbox','group','data','columnLabel','Input'));
                end
                nodes = obj.canvasAppendNode(nodes, cvNode);

                switch flag
                    case 1
                        [nodes, edges, terminalId] = obj.canvasAppendEarlyFusionFlowK3(nodes, edges, state, audit, synthActive, inputRowOffset);
                    case 3
                        [nodes, edges, terminalId] = obj.canvasAppendLateFusionFlowK3(nodes, edges, state, audit, synthActive, inputRowOffset);
                    case 2
                        [nodes, edges, terminalId] = obj.canvasAppendIntermediateFusionFlowK3(nodes, edges, state, audit, synthActive, inputRowOffset);
                    otherwise
                        [nodes, edges, terminalId] = obj.canvasAppendSingleModalityFlowK3(nodes, edges, state, audit, synthActive, inputRowOffset);
                end
                edges = obj.canvasAppendAuxiliaryDataEdges(nodes, edges);
            end

            [nodes, edges] = obj.canvasAppendOutputsK3(nodes, edges, state, audit, terminalId);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       canvas topology:           %.3fs\n', profileId, toc(tCanvasFlow));

            tCanvasCompact = tic;
            nodes = obj.canvasTrimNodes(nodes);
            edges = obj.canvasTrimEdges(edges);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       canvas compact:            %.3fs (nodes=%d, edges=%d)\n', ...
                profileId, toc(tCanvasCompact), numel(nodes), numel(edges));

            tCanvasDetails = tic;
            detailMode = obj.canvasDetailModeFromOpts(opts);
            nodes = obj.canvasAttachNodeDetails(nodes, state, audit, detailMode);
            obj.profileLog(doProfile, '[nm-prof rid=%s]       canvas details:            %.3fs (%s)\n', profileId, toc(tCanvasDetails), detailMode);

            canvas = struct();
            canvas.type = 'NMTrainTemplateCanvas';
            canvas.schemaVersion = 3;
            canvas.generatedAt = datestr(now, 30);
            canvas.mode = 'flowchart';
            canvas.nodes = nodes;
            canvas.edges = edges;
            canvas.auditSummary = obj.auditSummary(audit);
            canvas.activeModality = obj.canvasGetScalar(state,'activeModality',obj.VarIndex);
            canvas.relevantModalities = obj.canvasRelevantModalities(state);
            canvas.layout = struct('kind','column-dag','direction','left-to-right', ...
                'notes','K3: analysis-flow graph; utility controls are intentionally omitted from graph nodes.');
        end


        function detail = canvasNodeDetail(obj, node, state, audit)
            % CANVASNODEDETAIL  Return rich browser detail for one canvas node.
            %   Public service wrapper around the node-detail formatter. It keeps canvas inspection
            %   callable from the browser while leaving the internal formatter private.

            if nargin < 3 || isempty(state), state = struct(); end
            if nargin < 4 || isempty(audit), audit = obj.auditCurrentState(state); end
            detail = obj.canvasDetailForNode(node, state, audit);
            if isstruct(detail)
                detail.lazy = false;
                detail.mode = 'rich';
            end
        end


        function canvas = canvasEmptyState(obj)
            % CANVASEMPTYSTATE  Return an empty fixed-schema canvas payload.
            %   Used when no analysis graph can be rendered. The output contains empty node/edge arrays
            %   and standard metadata so browser code does not need special missing-field handling.
            canvas = struct();
            canvas.type = 'NMTrainTemplateCanvas';
            canvas.schemaVersion = 3;
            canvas.generatedAt = datestr(now, 30);
            canvas.mode = 'flowchart';
            canvas.nodes = obj.canvasEmptyNodes();
            canvas.edges = obj.canvasEmptyEdges();
            canvas.auditSummary = struct('highestSeverity','info','nErrors',0,'nWarnings',0,'nInfo',0,'messages',{{}});
            canvas.activeModality = obj.VarIndex;
            canvas.relevantModalities = obj.VarIndex;
            canvas.layout = struct('kind','column-dag','direction','left-to-right', ...
                'notes','Canvas generation was skipped for this menu-state refresh.');
        end

        function txt = canvasCVScopeSummary(obj, state)
            % CANVASCVSCOPESUMMARY  Format the cross-validation scope for canvas summaries.
            %   Reads the CV partition state and reports permutation/fold scope in a human-readable form
            %   for overview nodes and tooltips.
            base = obj.canvasSummary(state,'cvSummary','Default cross-validation settings.');
            if state.cv.cvHasStructure
                base = 'An existing cross-validation partition structure is available (NM.cv).';
            end
            base = char(string(base));
            if isempty(strtrim(base))
                base = 'Current NeuroMiner cross-validation settings.';
            end
            txt = sprintf('%s This box is a resampling context: preprocessing, model fitting, model selection and output generation are estimated within the configured partitions. It is not an additional processing step.', base);
        end

        function txt = canvasCVScopeCompactSummary(obj, state)
            % canvasCVScopeCompactSummary  Format compact CV text for canvas node subtitles.
            %
            % Converts the CV state into a short single-line summary suitable for constrained node labels.
            %
            % state.cv: carries the cv value between browser/API state and legacy NeuroMiner structures.
            cv = struct();
            if isstruct(state) && isfield(state,'cv') && isstruct(state.cv)
                cv = state.cv;
            elseif isstruct(obj.CVPartition)
                cv = obj.CVPartition;
            end
            cv2 = obj.canvasCVCompactOneLevel(cv, 'Outer', 10, 10, 'CV2');
            cv1 = obj.canvasCVCompactOneLevel(cv, 'Inner', 10, 10, 'CV1');
            txt = sprintf('CV2: %s | CV1: %s', cv2, cv1);
            if strcmp(txt, 'CV2: CV2 | CV1: CV1')
                base = obj.canvasSummary(state,'cvSummary','');
                base = char(string(base));
                if ~isempty(strtrim(base))
                    txt = obj.canvasCVScopeCompactFromSummary(base);
                else
                    txt = 'CV2: configured | CV1: configured';
                end
            end
        end

        function txt = canvasCVCompactOneLevel(obj, cv, levelName, defaultPerm, defaultFold, fallbackLabel) %#ok<INUSL>
            % CANVASCVCOMPACTONELEVEL  Format one CV hierarchy level for compact display.
            %   Reads permutation/fold counts from a level-specific CV struct, applies supplied defaults,
            %   and returns fallback text when counts are unavailable.
            txt = fallbackLabel;
            modeField = sprintf('cv%sMode', levelName);
            permField = sprintf('cv%sPerm', levelName);
            foldField = sprintf('cv%sFold', levelName);
            mode = 'kfold';
            if isstruct(cv) && isfield(cv, modeField)
                mode = lower(char(string(cv.(modeField))));
            end
            if contains(mode, 'loo')
                txt = 'LOO';
                return;
            end
            if contains(mode, 'group')
                txt = 'grouped';
                if isstruct(cv) && isfield(cv, permField)
                    perm = obj.canvasCVScalarNumber(cv.(permField), NaN);
                    if isfinite(perm) && perm > 0
                        txt = sprintf('%g x grouped', perm);
                    end
                end
                return;
            end
            perm = defaultPerm;
            fold = defaultFold;
            if isstruct(cv) && isfield(cv, permField)
                perm = obj.canvasCVScalarNumber(cv.(permField), defaultPerm);
            end
            if isstruct(cv) && isfield(cv, foldField)
                fold = obj.canvasCVScalarNumber(cv.(foldField), defaultFold);
            end
            if isfinite(perm) && isfinite(fold) && perm > 0 && fold > 0
                txt = sprintf('%g x %g', perm, fold);
            elseif isfinite(fold) && fold > 0
                txt = sprintf('%g folds', fold);
            elseif isfinite(perm) && perm > 0
                txt = sprintf('%g partitions', perm);
            end
        end

        function val = canvasCVScalarNumber(obj, raw, fallback) %#ok<INUSL>
            % CANVASCVSCALARNUMBER  Coerce a CV scalar to a finite numeric value.
            %   Returns the numeric scalar in raw when possible, otherwise the supplied fallback. This avoids
            %   propagating empty, nonnumeric or nonfinite values into compact CV text.
            val = fallback;
            if isnumeric(raw) || islogical(raw)
                x = double(raw(:));
                if ~isempty(x) && isfinite(x(1)), val = x(1); end
                return;
            end
            if ischar(raw) || isstring(raw)
                x = str2double(char(string(raw)));
                if isfinite(x), val = x; end
                return;
            end
            if iscell(raw) && ~isempty(raw)
                val = obj.canvasCVScalarNumber(raw{1}, fallback);
            end
        end

        function txt = canvasCVScopeCompactFromSummary(obj, base) %#ok<INUSL>
            % CANVASCVSCOPECOMPACTFROMSUMMARY  Condense a structured CV summary into display text.
            %   Extracts the relevant nested summary fields and returns a short browser-safe label; empty
            %   or malformed summaries collapse to a conservative fallback string.
            txt = char(string(base));
            m2 = regexp(txt, 'CV2\s+([0-9]+)\s+folds?', 'tokens', 'once');
            m1 = regexp(txt, 'CV1\s+([0-9]+)\s+folds?', 'tokens', 'once');
            if ~isempty(m2) && ~isempty(m1)
                txt = sprintf('CV2: %s folds | CV1: %s folds', m2{1}, m1{1});
            end
        end

        function node = canvasNode(obj, id, title, subtitle, configurator, summary, audit, deepLink, children, inactive, varargin) %#ok<INUSL>
            % CANVASNODE  Construct one fixed-schema canvas node.
            %   Normalizes identity, display text, configurator link, audit status, children, lane/order/row
            %   placement and optional metadata from varargin. Returns a scalar node struct for append-only
            %   canvas arrays.
            if nargin < 8, deepLink = configurator; end
            if nargin < 9 || isempty(children), children = {}; end
            if nargin < 10, inactive = false; end
            meta = struct('type','block','lane',10,'order',1,'shape','box','group','default', ...
                'columnLabel','','stepIndex',0,'accent','','row',NaN, ...
                'modalityIndex',NaN,'stage','','moduleId','','action','open','usesLabels',false,'usesCovariates',false);
            if ~isempty(varargin)
                if numel(varargin) == 1 && isstruct(varargin{1})
                    meta = NMConfigTools.mergeStruct(meta, varargin{1});
                elseif mod(numel(varargin),2) == 0
                    for kk = 1:2:numel(varargin)
                        try, meta.(char(string(varargin{kk}))) = varargin{kk+1}; catch, end
                    end
                end
            end
            items = obj.canvasAuditItemsForNode(audit, configurator, meta);
            commitKey = configurator;
            if isfinite(meta.modalityIndex) && meta.modalityIndex > 0
                scopedKey = sprintf('%s_var%d',configurator,meta.modalityIndex);
                if any(strcmp(obj.CommittedConfigurators,scopedKey)), commitKey = scopedKey; end
            end
            status = obj.canvasStatus(items, inactive, commitKey);
            node = struct('id',char(string(id)), 'title',char(string(title)), ...
                'subtitle',char(string(subtitle)), 'status',char(string(status)), ...
                'summary',char(string(summary)), 'auditItems',{items}, ...
                'configurator',char(string(configurator)), 'deepLink',char(string(deepLink)), ...
                'children',{children}, 'type',char(string(meta.type)), ...
                'lane',double(meta.lane), 'order',double(meta.order), ...
                'shape',char(string(meta.shape)), 'group',char(string(meta.group)), ...
                'columnLabel',char(string(meta.columnLabel)), ...
                'stepIndex',double(meta.stepIndex), 'accent',char(string(meta.accent)), ...
                'row',double(meta.row), 'modalityIndex',double(meta.modalityIndex), ...
                'stage',char(string(meta.stage)), 'moduleId',char(string(meta.moduleId)), ...
                'action',char(string(meta.action)), 'usesLabels',logical(meta.usesLabels), ...
                'usesCovariates',logical(meta.usesCovariates), 'detail',obj.canvasEmptyDetail());
        end

        function edge = canvasEdge(obj, source, target, kind, label) %#ok<INUSL>
            % CANVASEDGE  Construct one fixed-schema canvas edge.
            %   Normalizes source/target IDs, semantic edge kind and display label for browser rendering.
            %   The returned scalar edge is side-effect free and suitable for preallocated edge arrays.
            if nargin < 4 || isempty(kind), kind = 'flow'; end
            if nargin < 5 || isempty(label), label = ''; end
            edge = struct('source',char(string(source)), 'target',char(string(target)), ...
                'kind',char(string(kind)), 'label',char(string(label)));
        end

        function [nodes, edges, terminalId] = canvasAppendSingleModalityFlowK3(obj, nodes, edges, state, audit, synthActive, rowOffset)
            % CANVASAPPENDSINGLEMODALITYFLOWK3  Append the K3 graph for a single-modality analysis.
            %   Adds modality input, optional synthetic augmentation, the modality preprocessing chain,
            %   global learner/RFE block and terminal output nodes. Returns updated node/edge arrays and
            %   the terminal node ID.
            if nargin < 7 || isempty(rowOffset), rowOffset = 1; end
            M = obj.canvasRelevantModalities(state);
            idx = M(1);
            [nodes, edges, modId] = obj.canvasAppendModalityInputNode(nodes, edges, state, audit, idx, rowOffset);
            prevId = obj.canvasMaybeAppendSyntheticK3(nodes, edges, state, audit, synthActive, {modId}, 30);
            nodes = prevId.nodes; edges = prevId.edges; prev = prevId.id;
            [nodes, edges, ppEnd] = obj.canvasAppendPreprocChainK3(nodes, edges, audit, obj.canvasPreprocForModality(idx), idx, ...
                obj.canvasPreprocScopeForModality(idx,0), prev, rowOffset, 40);
            terminalId = obj.canvasAppendGlobalLearnerK3(nodes, edges, state, audit, ppEnd, 1, 'row', rowOffset);
            nodes = terminalId.nodes; edges = terminalId.edges; terminalId = terminalId.id;
        end

        function [nodes, edges, terminalId] = canvasAppendEarlyFusionFlowK3(obj, nodes, edges, state, audit, synthActive, rowOffset)
            % CANVASAPPENDEARLYFUSIONFLOWK3  Append the K3 graph for early fusion.
            %   Creates one input node per fused modality, merges raw inputs before preprocessing, uses the
            %   shared preprocessing branch from the first fused modality, then appends the global learner.
            if nargin < 7 || isempty(rowOffset), rowOffset = 1; end
            M = obj.canvasRelevantModalities(state);
            modIds = cell(1,numel(M));
            branchRows = rowOffset + (0:numel(M)-1);
            for mm = 1:numel(M)
                [nodes, edges, modIds{mm}] = obj.canvasAppendModalityInputNode(nodes, edges, state, audit, M(mm), branchRows(mm));
            end
            fusionId = 'early_fusion_merge';
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(fusionId,'Fusion / merge', obj.canvasFusionSubtitle(state), 'fusion', ...
                'Early fusion: selected modalities are concatenated first; the shared preprocessing chain is represented once.', audit, 'fusion', {}, false, ...
                'type','fusion','lane',30,'order',1,'row',mean(branchRows),'shape','diamond','group','fusion','columnLabel','Fusion / merge'));
            for mm = 1:numel(modIds)
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(modIds{mm}, fusionId, 'fusion_input', 'selected modality')); %#ok<AGROW>
            end
            firstIdx = M(1);
            syn = obj.canvasMaybeAppendSyntheticK3(nodes, edges, state, audit, synthActive, {fusionId}, 40);
            nodes = syn.nodes; edges = syn.edges; prev = syn.id;
            [nodes, edges, ppEnd] = obj.canvasAppendPreprocChainK3(nodes, edges, audit, obj.canvasPreprocForModality(firstIdx), firstIdx, ...
                sprintf('early-fusion shared PREPROC{%d}', firstIdx), prev, mean(branchRows), 50);
            learner = obj.canvasAppendGlobalLearnerK3(nodes, edges, state, audit, ppEnd, 1, 'row', mean(branchRows));
            nodes = learner.nodes; edges = learner.edges; terminalId = learner.id;
        end

        function [nodes, edges, terminalId] = canvasAppendIntermediateFusionFlowK3(obj, nodes, edges, state, audit, synthActive, rowOffset)
            % CANVASAPPENDINTERMEDIATEFUSIONFLOWK3  Append the K3 graph for intermediate fusion.
            %   Builds modality-specific preprocessing branches on aligned columns, merges the resulting
            %   feature representations, and connects them to the global learner. Shorter branches do not
            %   receive filler nodes; arrows project from the last occupied preprocessing step.
            if nargin < 7 || isempty(rowOffset), rowOffset = 1; end
            M = obj.canvasRelevantModalities(state);
            branchRows = rowOffset + (0:numel(M)-1);
            endIds = cell(1,numel(M));
            prevIds = cell(1,numel(M));
            scopes = cell(1,numel(M));
            stepLists = cell(1,numel(M));
            maxSteps = 0;
            for mm = 1:numel(M)
                idx = M(mm);
                [nodes, edges, modId] = obj.canvasAppendModalityInputNode(nodes, edges, state, audit, idx, branchRows(mm));
                syn = obj.canvasMaybeAppendSyntheticK3(nodes, edges, state, audit, synthActive, {modId}, 30);
                nodes = syn.nodes; edges = syn.edges; prevIds{mm} = syn.id;
                scopes{mm} = obj.canvasPreprocScopeForModality(idx,2);
                stepLists{mm} = obj.canvasPreprocStepSpecs(obj.canvasPreprocForModality(idx), idx, scopes{mm});
                maxSteps = max(maxSteps, numel(stepLists{mm}));
            end
            for mm = 1:numel(M)
                idx = M(mm);
                [nodes, edges, endIds{mm}] = obj.canvasAppendPreprocSpecsAtFixedColumnsK3(nodes, edges, audit, ...
                    stepLists{mm}, idx, scopes{mm}, prevIds{mm}, branchRows(mm), 40);
            end
            fusionLane = 40 + max(maxSteps, 1) * 10;
            fusionRow = mean(branchRows);
            fusionId = 'intermediate_fusion_merge';
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(fusionId,'Fusion / merge', obj.canvasFusionSubtitle(state), 'fusion', ...
                obj.canvasFusionSummary(state), audit, 'fusion', {}, false, ...
                'type','fusion','lane',fusionLane,'order',round((fusionRow+1)*100),'row',fusionRow, ...
                'shape','diamond','group','fusion','columnLabel','Fusion / merge'));
            for mm = 1:numel(endIds)
                if ~isempty(endIds{mm})
                    edges = obj.canvasAppendEdge(edges, obj.canvasEdge(endIds{mm}, fusionId, 'fusion_input', 'preprocessed modality')); %#ok<AGROW>
                end
            end
            learner = obj.canvasAppendGlobalLearnerK3(nodes, edges, state, audit, fusionId, 1, 'row', fusionRow);
            nodes = learner.nodes; edges = learner.edges; terminalId = learner.id;
        end

        function [nodes, edges, terminalId] = canvasAppendLateFusionFlowK3(obj, nodes, edges, state, audit, synthActive, rowOffset)
            % CANVASAPPENDLATEFUSIONFLOWK3  Append the K3 graph for late fusion.
            %   Builds modality-specific preprocessing and learner branches, optionally wraps each base
            %   learner in the ensemble/RFE block, and joins model outputs at the late-fusion decision node.
            if nargin < 7 || isempty(rowOffset), rowOffset = 1; end
            M = obj.canvasRelevantModalities(state);
            branchRows = rowOffset + (0:numel(M)-1);
            ppEndIds = cell(1,numel(M));
            for mm = 1:numel(M)
                idx = M(mm);
                [nodes, edges, modId] = obj.canvasAppendModalityInputNode(nodes, edges, state, audit, idx, branchRows(mm));
                syn = obj.canvasMaybeAppendSyntheticK3(nodes, edges, state, audit, synthActive, {modId}, 30);
                nodes = syn.nodes; edges = syn.edges; prev = syn.id;
                [nodes, edges, ppEndIds{mm}] = obj.canvasAppendPreprocChainK3(nodes, edges, audit, obj.canvasPreprocForModality(idx), idx, ...
                    obj.canvasPreprocScopeForModality(idx,3), prev, branchRows(mm), 40);
            end
            learnerLane = obj.canvasMaxLane(nodes) + 10;
            rfeActive = obj.canvasRFEActive(state);
            baseEndIds = cell(1,numel(M));
            for mm = 1:numel(M)
                idx = M(mm);
                mlId = sprintf('late_model_m%d', idx);
                branchEnd = mlId;
                if rfeActive
                    ensId = sprintf('ensemble_m%d', idx);
                    nodes = obj.canvasAppendNode(nodes, obj.canvasNode(ensId, 'Ensemble learning', sprintf('STRAT{%d}', idx), 'rfe', ...
                        obj.canvasSummary(state,'rfeSummary','Filter- and wrapper-based ensemble learning disabled.'), audit, 'rfe', {mlId}, false, ...
                        'type','model_selection','lane',learnerLane,'order',mm*100,'row',branchRows(mm), ...
                        'shape','container','group','learner','columnLabel','Learner', ...
                        'modalityIndex',idx,'action','open'));
                    edges = obj.canvasAppendEdge(edges, obj.canvasEdge(ppEndIds{mm}, ensId, 'model_selection', 'selection/ensemble')); %#ok<AGROW>
                    branchEnd = ensId;
                else
                    edges = obj.canvasAppendEdge(edges, obj.canvasEdge(ppEndIds{mm}, mlId, 'train', 'modality-specific features')); %#ok<AGROW>
                end
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(mlId, sprintf('Base learner: %s', obj.canvasModalityLabel(idx)), ...
                    sprintf('STRAT{%d}.SVM/GRD', idx), 'ml', obj.canvasMLSummaryForModality(idx), audit, 'ml', {}, false, ...
                    'type','learner','lane',learnerLane,'order',mm*100 + 1,'row',branchRows(mm), ...
                    'shape','box','group','learner','columnLabel','Learner', ...
                    'modalityIndex',idx,'action','open'));
                baseEndIds{mm} = branchEnd;
            end
            decisionLane = learnerLane + 10;
            decisionId = 'late_fusion_decision';
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(decisionId,'Late-fusion decision', obj.canvasFusionSubtitle(state), 'fusion', ...
                'Combines modality-specific base learner outputs; base learners remain visible in one Learner column.', audit, 'fusion', {}, false, ...
                'type','fusion','lane',decisionLane,'order',1,'row',mean(branchRows),'shape','diamond','group','fusion','columnLabel','Fusion / decision'));
            for mm = 1:numel(baseEndIds)
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(baseEndIds{mm}, decisionId, 'late_fusion', 'model output')); %#ok<AGROW>
            end
            terminalId = decisionId;
        end

        function [nodes, edges, terminalId] = canvasAppendStackingFlowK3(obj, nodes, edges, state, audit, synthActive)
            % CANVASAPPENDSTACKINGFLOWK3  Append the K3 graph for stacking analyses.
            %   Represents selected first-tier analyses, the stacking feature table, optional synthetic
            %   augmentation, stacking preprocessing, the second-tier learner and output nodes. Returns the
            %   terminal stacking node ID.
            selected = obj.canvasStackingSelectedAnalyses(state);
            if isempty(selected)
                inputId = 'stacking_inputs_unselected';
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(inputId, 'First-tier analyses', ...
                    'Stacking input layer', 'stacking', 'No completed first-tier analyses are currently selected for stacking.', audit, '', {}, false, ...
                    'type','stacking_input','lane',10,'order',1,'row',1,'shape','roundbox', ...
                    'group','stacking','columnLabel','Input','accent','stacking','action','noop'));
                prevIds = {inputId};
            else
                prevIds = cell(1,numel(selected));
                for ii = 1:numel(selected)
                    ana = selected(ii);
                    inputId = sprintf('stacking_input_%d', ana);
                    nodes = obj.canvasAppendNode(nodes, obj.canvasNode(inputId, sprintf('First-tier analysis %d', ana), ...
                        'Stacking base prediction source', 'stacking', obj.canvasStackingAnalysisSummary(ana), audit, '', {}, false, ...
                        'type','stacking_input','lane',10,'order',ii*100,'row',ii,'shape','roundbox', ...
                        'group','stacking','columnLabel','Input','accent','stacking','action','noop'));
                    prevIds{ii} = inputId;
                end
            end

            stackRow = max(1, (numel(prevIds)+1) / 2);
            mergeId = 'stacking_input_merge';
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(mergeId, 'Stacking feature table', ...
                'Base-model predictions/features', 'stacking', 'Constructs the second-tier learner input table from selected first-tier analyses.', audit, 'stacking', {}, false, ...
                'type','fusion','lane',30,'order',1,'row',stackRow, ...
                'shape','diamond','group','stacking','columnLabel','Stacking table'));
            for ii = 1:numel(prevIds)
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevIds{ii}, mergeId, 'stacking_input', 'fold-wise prediction outputs')); %#ok<AGROW>
            end
            syn = obj.canvasMaybeAppendSyntheticK3(nodes, edges, state, audit, synthActive, {mergeId}, 40);
            nodes = syn.nodes; edges = syn.edges; prev = syn.id;
            [nodes, edges, ppEnd] = obj.canvasAppendPreprocChainK3(nodes, edges, audit, obj.StackingPreproc, 0, 'STACKING.PREPROC', prev, stackRow, 50);
            learnerLane = obj.canvasMaxLane(nodes) + 10;
            mlId = 'stacking_second_tier_learner';
            if obj.canvasRFEActive(state)
                ensId = 'stacking_ensemble_learning';
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(ensId, 'Ensemble learning', 'Second-tier model selection', 'rfe', ...
                    obj.canvasSummary(state,'rfeSummary','Filter- and wrapper-based ensemble learning disabled.'), audit, 'rfe', {mlId}, false, ...
                    'type','model_selection','lane',learnerLane,'order',1,'row',stackRow, ...
                    'shape','container','group','learner','columnLabel','Learner'));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(ppEnd, ensId, 'model_selection', 'selection/ensemble'));
                terminalId = ensId;
            else
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(ppEnd, mlId, 'train', 'stacked feature table'));
                terminalId = mlId;
            end
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(mlId, 'Second-tier learner', ...
                'Stacker ML, not bagging', 'ml', obj.canvasSummary(state,'mlSummary','Global stacker machine-learning configuration.'), audit, 'ml', {}, false, ...
                'type','meta_learner','lane',learnerLane,'order',2,'row',stackRow, ...
                'shape','box','group','learner','columnLabel','Learner'));
        end

        function edges = canvasAppendAuxiliaryDataEdges(obj, nodes, edges)
            % CANVASAPPENDAUXILIARYDATAEDGES  Add non-primary canvas edges for auxiliary data flow.
            %   Connects covariate, label or other support nodes to learner/configuration nodes where the
            %   rendered graph needs explicit side inputs. Existing nodes are not modified.
            if obj.canvasHasNode(nodes, 'data_labels')
                learnerIds = obj.canvasExternalLearnerTargetIds(nodes);
                for ii = 1:numel(learnerIds)
                    edges = obj.canvasAppendEdge(edges, obj.canvasEdge('data_labels', learnerIds{ii}, 'label_input', 'labels'));
                end
                labelSteps = obj.canvasNodeIdsByUsage(nodes, 'usesLabels');
                for ii = 1:numel(labelSteps)
                    if ~obj.canvasNodeIsContainerChild(nodes, labelSteps{ii}) && ~strcmp(labelSteps{ii}, 'machine_learning')
                        edges = obj.canvasAppendEdge(edges, obj.canvasEdge('data_labels', labelSteps{ii}, 'label_input', 'labels'));
                    end
                end
            end
            if obj.canvasHasNode(nodes, 'data_covariates')
                covSteps = obj.canvasNodeIdsByUsage(nodes, 'usesCovariates');
                for ii = 1:numel(covSteps)
                    if ~obj.canvasNodeIsContainerChild(nodes, covSteps{ii})
                        edges = obj.canvasAppendEdge(edges, obj.canvasEdge('data_covariates', covSteps{ii}, 'covariate_input', 'covariates'));
                    end
                end
            end
        end

        function ids = canvasExternalLearnerTargetIds(obj, nodes)
            % CANVASEXTERNALLEARNERTARGETIDS  Identify learner nodes that should receive auxiliary inputs.
            %   Scans rendered canvas nodes and returns IDs for learner/model-selection nodes that are not
            %   already container-internal children.
            ids = cell(1, numel(nodes));
            nIds = 0;
            for ii = 1:numel(nodes)
                t = lower(char(string(nodes(ii).type)));
                if strcmp(t, 'model_selection') && strcmp(char(string(nodes(ii).shape)), 'container')
                    childIds = obj.canvasContainerChildIds(nodes(ii));
                    if obj.canvasAnyChildIsLearner(nodes, childIds)
                        nIds = nIds + 1;
                        ids{nIds} = char(string(nodes(ii).id));
                    end
                end
            end
            learnerIds = obj.canvasNodeIdsByType(nodes, {'ml','learner','meta_learner'});
            for ii = 1:numel(learnerIds)
                if obj.canvasNodeIsContainerChild(nodes, learnerIds{ii})
                    continue;
                end
                nIds = nIds + 1;
                ids{nIds} = learnerIds{ii};
            end
            ids = ids(1:nIds);
        end

        function tf = canvasAnyChildIsLearner(obj, nodes, childIds) %#ok<INUSL>
            % CANVASANYCHILDISLEARNER  Test whether a child list contains learner-type nodes.
            %   Used when deciding whether auxiliary or container links should target a parent node or one
            %   of its rendered child nodes.
            tf = false;
            if isempty(childIds), return; end
            childSet = childIds(:)';
            for ii = 1:numel(nodes)
                id = char(string(nodes(ii).id));
                if ~any(strcmp(childSet, id)), continue; end
                t = lower(char(string(nodes(ii).type)));
                if any(strcmp(t, {'ml','learner','meta_learner'}))
                    tf = true;
                    return;
                end
            end
        end

        function tf = canvasNodeIsContainerChild(obj, nodes, nodeId)
            % CANVASNODEISCONTAINERCHILD  Test whether a node ID appears inside another node's children list.
            %   Prevents duplicate external links to nodes that are rendered as children of a container node.
            tf = false;
            nodeId = char(string(nodeId));
            if isempty(nodeId), return; end
            for ii = 1:numel(nodes)
                if ~strcmp(char(string(nodes(ii).shape)), 'container'), continue; end
                childIds = obj.canvasContainerChildIds(nodes(ii));
                if any(strcmp(childIds, nodeId))
                    tf = true;
                    return;
                end
            end
        end

        function childIds = canvasContainerChildIds(obj, node) %#ok<INUSL>
            % CANVASCONTAINERCHILDIDS  Return normalized child IDs from a canvas container node.
            %   Accepts string, char or cell-array child specifications and returns a row cell array of IDs.
            raw = node.children;
            if ischar(raw) || isstring(raw)
                childIds = cellstr(string(raw));
            elseif iscell(raw)
                childIds = cell(1, numel(raw));
                for ii = 1:numel(raw)
                    childIds{ii} = char(string(raw{ii}));
                end
                childIds = childIds(~cellfun(@isempty, childIds));
            else
                childIds = cell(1, 0);
            end
        end

        function ids = canvasNodeIdsByType(obj, nodes, types) %#ok<INUSL>
            % CANVASNODEIDSBYTYPE  Return node IDs matching one or more canvas type values.
            %   Used by graph assembly helpers to find rendered learner, fusion, input or output nodes.
            if ischar(types) || isstring(types), types = cellstr(string(types)); end
            types = cellfun(@(x) lower(char(string(x))), types(:)', 'UniformOutput', false);
            ids = cell(1, numel(nodes));
            nIds = 0;
            for ii = 1:numel(nodes)
                try
                    t = lower(char(string(nodes(ii).type)));
                    if any(strcmp(t, types))
                        nIds = nIds + 1;
                        ids{nIds} = char(string(nodes(ii).id));
                    end
                catch
                end
            end
            ids = ids(1:nIds);
        end

        function ids = canvasNodeIdsByUsage(obj, nodes, fieldName) %#ok<INUSL>
            % CANVASNODEIDSBYUSAGE  Return node IDs with a truthy usage flag.
            %   Scans node metadata for fieldName and returns matching IDs, preserving rendered order.
            ids = cell(1, numel(nodes));
            nIds = 0;
            for ii = 1:numel(nodes)
                try
                    if isfield(nodes(ii), fieldName) && logical(nodes(ii).(fieldName))
                        nIds = nIds + 1;
                        ids{nIds} = char(string(nodes(ii).id));
                    end
                catch
                end
            end
            ids = ids(1:nIds);
        end

        function [nodes, edges, modId] = canvasAppendModalityInputNode(obj, nodes, edges, state, audit, idx, branchOrder) %#ok<INUSL>
            % CANVASAPPENDMODALITYINPUTNODE  Add one modality input node to the canvas.
            %   Uses modality label, imaging suffix, audit status and requested branch row to create a
            %   browser node representing the selected NM data modality.
            modId = sprintf('modality_%d', idx);
            info = NMModalityInfoTools.fromNM(obj.NM, idx, struct('ScanInMemory', false));
            switch info.sourceType
                case 'image-list'
                    provenance = 'Volumetric';
                case 'surface-list'
                    provenance = 'Surface';
                case 'roi'
                    provenance = 'ROI';
                case 'connectivity'
                    provenance = 'Connectivity';
                case {'workspace','matfile','tablefile','tablevar'}
                    provenance = ['Tabular · ' info.sourceTypeLabel];
                case 'database'
                    provenance = ['Tabular · ' info.sourceTypeLabel];
                otherwise
                    provenance = info.sourceTypeLabel;
            end
            subtitle = sprintf('%s [%s]', info.label, provenance);
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode(modId, sprintf('Modality #%d', idx), subtitle, 'data', ...
                'Analysis-scoped input modality. Unselected NM modalities are intentionally hidden.', audit, '', {}, false, ...
                'type','modality','lane',10,'order',branchOrder*100,'row',branchOrder, ...
                'shape','roundbox','group','modality','columnLabel','Input', ...
                'modalityIndex',idx,'action','setActiveModality'));
        end

        function row = canvasRowForNode(obj, nodes, id, fallback) %#ok<INUSL>
            % CANVASROWFORNODE  Look up the rendered row coordinate for a canvas node ID.
            %   Returns the node row when available and numeric; otherwise returns the provided fallback.
            if nargin < 4 || isempty(fallback), fallback = 1; end
            row = fallback;
            if isempty(nodes) || isempty(id), return; end
            for rr = 1:numel(nodes)
                if isfield(nodes(rr),'id') && strcmp(char(string(nodes(rr).id)), char(string(id)))
                    if isfield(nodes(rr),'row') && isnumeric(nodes(rr).row) && isfinite(nodes(rr).row)
                        row = double(nodes(rr).row);
                    end
                    return;
                end
            end
        end

        function row = canvasMeanRowForIds(obj, nodes, ids, fallback)
            % CANVASMEANROWFORIDS  Compute the mean rendered row for a set of canvas node IDs.
            %   Ignores missing IDs and nonnumeric row fields. The fallback is returned when no valid rows exist.
            if nargin < 4 || isempty(fallback), fallback = 1; end
            vals = [];
            if ~iscell(ids), ids = {ids}; end
            for rr = 1:numel(ids)
                v = obj.canvasRowForNode(nodes, ids{rr}, NaN);
                if isfinite(v), vals(end+1) = v; end %#ok<AGROW>
            end
            if isempty(vals)
                row = fallback;
            else
                row = mean(vals);
            end
        end

        function out = canvasMaybeAppendSyntheticK3(obj, nodes, edges, state, audit, synthActive, prevIds, lane)
            % CANVASMAYBEAPPENDSYNTHETICK3  Optionally insert the synthetic-data node into a K3 branch.
            %   When synthetic augmentation is active, appends a synthetic-data node at the requested lane and
            %   connects all previous IDs to it; otherwise passes through the first previous ID unchanged.
            if nargin < 8 || isempty(lane), lane = 30; end
            if synthActive
                synId = 'synthetic_data';
                if ~obj.canvasHasNode(nodes, synId)
                    rowHint = obj.canvasMeanRowForIds(nodes, prevIds, 1);
                    nodes = obj.canvasAppendNode(nodes, obj.canvasNode(synId,'Synthetic data', '', 'synth', ...
                        obj.canvasSummary(state,'synthSummary','Synthetic data generation disabled.'), audit, 'synth', {}, false, ...
                        'type','augmentation','lane',lane,'order',1,'row',rowHint, ...
                        'shape','box','group','execution','columnLabel','Synthetic data'));
                end
                for ii = 1:numel(prevIds)
                    if ~isempty(prevIds{ii})
                        edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevIds{ii}, synId, 'augmentation_input', 'training input')); %#ok<AGROW>
                    end
                end
                out = struct('nodes',nodes,'edges',edges,'id',synId);
            else
                out = struct('nodes',nodes,'edges',edges,'id',prevIds{1});
            end
        end

        function [nodes, edges, lastId] = canvasAppendPreprocChainK3(obj, nodes, edges, audit, pp, idx, scope, prevId, branchOrder, laneBase)
            % CANVASAPPENDPREPROCCHAINK3  Append preprocessing nodes for one modality branch.
            %   Extracts displayable preprocessing steps from a preproc orchestrator and appends them after
            %   prevId using the branch row, scope and lane base. Returns the last preprocessing node ID.
            steps = obj.canvasPreprocStepSpecs(pp, idx, scope);
            if isempty(steps)
                noId = sprintf('preproc_m%d_none_%d', idx, branchOrder);
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(noId, 'No preprocessing', scope, 'preproc', ...
                    sprintf('No canonical preprocessing step is configured for %s.', scope), audit, 'preproc', {}, false, ...
                    'type','preproc_empty','lane',laneBase,'order',branchOrder*100,'shape','box','group','preproc', ...
                    'columnLabel','Preprocessing','stepIndex',1,'row',branchOrder, ...
                    'modalityIndex',idx,'stage','cv','moduleId','','action','open'));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, noId, 'preproc', 'raw features'));
                lastId = noId;
                return;
            end
            lastId = prevId;
            for ss = 1:numel(steps)
                st = steps(ss);
                stepLane = laneBase + (ss-1)*10;
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(st.id, st.title, st.subtitle, 'preproc', st.summary, audit, 'preproc', {}, false, ...
                    'type','preproc_step','lane',stepLane,'order',branchOrder*100,'shape','box','group','preproc', ...
                    'columnLabel',sprintf('Preprocessing: Step %d', ss),'stepIndex',ss,'row',branchOrder, ...
                    'modalityIndex',idx,'stage',st.stage,'moduleId',st.moduleId,'action','focus', ...
                    'usesLabels',st.usesLabels,'usesCovariates',st.usesCovariates));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(lastId, st.id, 'preproc', st.stage));
                lastId = st.id;
            end
        end

        function [nodes, edges, lastId] = canvasAppendPreprocSpecsAtFixedColumnsK3(obj, nodes, edges, audit, steps, idx, scope, prevId, branchOrder, laneBase)
            % CANVASAPPENDPREPROCSPECSATFIXEDCOLUMNSK3  Append prepared preprocessing specs at fixed canvas columns.
            %   Places each step at a deterministic lane so parallel intermediate-fusion branches align
            %   visually, then links them sequentially from prevId.
            if nargin < 10 || isempty(laneBase), laneBase = 40; end
            lastId = prevId;
            if isempty(steps)
                return;
            end
            rowHint = max(0, double(branchOrder));
            for ss = 1:numel(steps)
                st = steps(ss);
                stepLane = laneBase + (ss-1)*10;
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(st.id, st.title, st.subtitle, 'preproc', st.summary, audit, 'preproc', {}, false, ...
                    'type','preproc_step','lane',stepLane,'order',branchOrder*100,'row',rowHint, ...
                    'shape','box','group','preproc','columnLabel',sprintf('Preprocessing: Step %d', ss), ...
                    'stepIndex',ss,'modalityIndex',idx,'stage',st.stage,'moduleId',st.moduleId,'action','focus', ...
                    'usesLabels',st.usesLabels,'usesCovariates',st.usesCovariates));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(lastId, st.id, 'preproc', st.stage));
                lastId = st.id;
            end
        end

        function tf = canvasVararginHasKey(obj, args, key) %#ok<INUSL>
            % CANVASVARARGINHASKEY  Test whether a node-construction varargin list contains a key.
            %   Performs case-insensitive name matching over alternating key/value pairs and is used before
            %   adding optional node metadata defaults.
            tf = false;
            try
                key = lower(char(string(key)));
                if isempty(args), return; end
                for ii = 1:2:numel(args)
                    if strcmp(lower(char(string(args{ii}))), key)
                        tf = true;
                        return;
                    end
                end
            catch
                tf = false;
            end
        end

        function out = canvasAppendGlobalLearnerK3(obj, nodes, edges, state, audit, prevId, order, varargin)
            % CANVASAPPENDGLOBALLEARNERK3  Append the shared learner block for non-late-fusion flows.
            %   Optionally creates an ensemble/RFE container before the learner, links it to prevId, and
            %   returns updated graph arrays plus the terminal learner ID.
            lane = obj.canvasMaxLane(nodes) + 10;
            mlId = 'machine_learning';
            if ~obj.canvasVararginHasKey(varargin, 'row')
                varargin = [varargin, {'row', obj.canvasRowForNode(nodes, prevId, max(1,double(order)))}];
            end
            rowVal = obj.canvasValueFromVarargin(varargin, 'row', obj.canvasRowForNode(nodes, prevId, max(1,double(order))));
            if obj.canvasRFEActive(state)
                ensId = 'ensemble_learning';
                ensArgs = [{'type','model_selection','lane',lane,'order',order,'shape','container','group','learner', ...
                    'columnLabel','Learner','row',rowVal}, varargin];
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(ensId,'Ensemble learning', obj.canvasRFESubtitle(state), 'rfe', ...
                    obj.canvasSummary(state,'rfeSummary','Filter- and wrapper-based ensemble learning disabled.'), audit, 'rfe', {mlId}, false, ensArgs{:}));
                nodeArgs = [{'type','learner','lane',lane,'order',order + 1,'shape','box','group','learner','columnLabel','Learner'}, varargin];
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(mlId,'Machine learning', obj.canvasMLSubtitle(state), 'ml', ...
                    obj.canvasSummary(state,'mlSummary','Machine-learning defaults.'), audit, 'ml', {}, false, nodeArgs{:}));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, ensId, 'model_selection', 'selection/ensemble'));
                out = struct('nodes',nodes,'edges',edges,'id',ensId);
            else
                nodeArgs = [{'type','learner','lane',lane,'order',order,'shape','box','group','learner','columnLabel','Learner'}, varargin];
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode(mlId,'Machine learning', obj.canvasMLSubtitle(state), 'ml', ...
                    obj.canvasSummary(state,'mlSummary','Machine-learning defaults.'), audit, 'ml', {}, false, nodeArgs{:}));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, mlId, 'train', 'training input'));
                out = struct('nodes',nodes,'edges',edges,'id',mlId);
            end
        end

        function [nodes, edges] = canvasAppendOutputsK3(obj, nodes, edges, state, audit, prevId)
            % CANVASAPPENDOUTPUTSK3  Append terminal output/result nodes to a K3 canvas flow.
            %   Adds model output, visualization, MLI and saving nodes when the current state/audit indicates
            %   that the corresponding blocks should be represented.
            if nargin < 6 || isempty(prevId), prevId = 'machine_learning'; end
            lane = obj.canvasMaxLane(nodes) + 10;
            modelRow = obj.canvasRowForNode(nodes, prevId, 1);
            if obj.canvasShouldShowMultiClass(state, audit)
                nodes = obj.canvasAppendNode(nodes, obj.canvasNode('multi_class','Multi-class', '', 'multi', ...
                    obj.canvasSummary(state,'multiSummary','Multi-class configuration unavailable.'), audit, 'multi', {}, false, ...
                    'type','post_model','lane',lane,'order',1,'row',modelRow, ...
                    'shape','box','group','downstream','columnLabel','Multi-class'));
                edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, 'multi_class', 'post_model', 'class decoding'));
                prevId = 'multi_class';
                lane = lane + 10;
            end
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode('visualization','Visualization', '', 'vis', ...
                obj.canvasSummary(state,'visSummary','Visualization defaults.'), audit, 'vis', {}, false, ...
                'type','output','lane',lane,'order',1,'row',modelRow, ...
                'shape','box','group','output','columnLabel','Outputs'));
            nodes = obj.canvasAppendNode(nodes, obj.canvasNode('interpretable_ml','Interpretable ML', '', 'mli', ...
                obj.canvasSummary(state,'mliSummary','Interpretable ML parameters are not configured.'), audit, 'mli', {}, false, ...
                'type','output','lane',lane,'order',2,'row',modelRow+1, ...
                'shape','box','group','output','columnLabel','Outputs'));
            edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, 'visualization', 'output', 'model output'));
            edges = obj.canvasAppendEdge(edges, obj.canvasEdge(prevId, 'interpretable_ml', 'output', 'model output'));
        end

        function tf = canvasShouldShowMultiClass(obj, state, audit) %#ok<INUSD>
            % CANVASSHOULDSHOWMULTICLASS  Decide whether the multi-class block belongs in the canvas.
            %   Combines task metadata, alternative-label state and audit evidence so multi-class handling is
            %   rendered only when it is relevant to the active analysis context.
            tf = obj.canvasLogicalField(state,'isMultiClassProblem',false) || ...
                 obj.canvasLogicalField(state,'multiAvailable',false);
        end

        function tf = canvasHasNode(obj, nodes, id) %#ok<INUSL>
            % CANVASHASNODE  Test whether the canvas already contains a node ID.
            %   Used during graph construction to avoid duplicate node insertion before adding dependent edges.
            tf = false;
            try
                ids = {nodes.id};
                tf = any(strcmp(ids, char(string(id))));
            catch
                tf = false;
            end
        end

        function m = canvasMaxLane(obj, nodes) %#ok<INUSL>
            % CANVASMAXLANE  Return the maximum occupied canvas lane.
            %   Reads numeric lane fields from existing nodes and returns zero when the graph is empty or lanes
            %   are unavailable.
            m = 10;
            try
                if isempty(nodes), return; end
                vals = [];
                for ii = 1:numel(nodes)
                    if isempty(nodes(ii).id), continue; end
                    if isfield(nodes(ii),'lane') && isnumeric(nodes(ii).lane) && isfinite(nodes(ii).lane)
                        vals(end+1) = double(nodes(ii).lane); %#ok<AGROW>
                    end
                end
                if ~isempty(vals), m = max(vals); end
            catch
                m = 10;
            end
        end

        function txt = methodsSummary(obj, state, canvas, audit)
            % methodsSummary  Build the browser methods/report text for the current configuration.
            %
            % Combines executive summary, CV, preprocessing, ML, audit, inventory and manuscript-scaffold
            % sections using the rendered canvas and audit context. Output is plain text for display/export.
            %
            % state.audit: carries the audit value between browser/API state and legacy NeuroMiner structures.
            if nargin < 2 || isempty(state) || ~isstruct(state), state = obj.menuState(); end
            if nargin < 4 || isempty(audit)
                if isfield(state,'audit'), audit = state.audit; else, audit = obj.auditCurrentState(state); end
            end
            if nargin < 3 || isempty(canvas)
                canvas = obj.canvasState(state, audit);
            end

            isStacking = obj.methodsIsStacking(state);
            modeLabel = obj.methodsAnalysisModeLabel(state);
            taskLabel = obj.methodsTaskTypeLabel(state);
            auditSummary = obj.auditSummary(audit);
            usedModalities = obj.methodsUsedModalities(state);
            selectedAnalyses = obj.methodsSelectedStackingAnalyses(state);
            L = {};

            L{end+1} = 'NeuroMiner training-template summary';
            L{end+1} = ['Generated: ' datestr(now, 'dd-mmm-yyyy HH:MM:SS')];
            L{end+1} = '';

            L{end+1} = '1. Report metadata';
            L{end+1} = sprintf('- Configuration environment: NeuroMiner training-template UI');
            L{end+1} = sprintf('- Analysis mode: %s', modeLabel);
            L{end+1} = sprintf('- Task type: %s', taskLabel);
            L{end+1} = sprintf('- Input modalities registered in NM: %d', obj.canvasGetScalar(state,'numModalities',obj.NumModalities));
            if isStacking
                L{end+1} = sprintf('- Selected first-tier analyses: %d', numel(selectedAnalyses));
            else
                L{end+1} = sprintf('- Modalities used by the active configuration: %s', obj.methodsIndexList(usedModalities));
            end
            L{end+1} = '';

            L{end+1} = '2. Executive configuration summary';
            L{end+1} = obj.methodsExecutiveSummary(state);
            L{end+1} = '';

            L{end+1} = '3. Analysis design';
            L{end+1} = sprintf('- Analysis type: %s', modeLabel);
            L{end+1} = sprintf('- Prediction target: %s', obj.methodsTargetLabel(state));
            L{end+1} = sprintf('- Learning framework: %s', taskLabel);
            if isStacking
                L{end+1} = '- Input structure: fold-wise prediction outputs from selected first-tier analyses are used to construct the second-tier stacking representation.';
                for ii = 1:numel(selectedAnalyses)
                    L{end+1} = sprintf('  - %s', obj.methodsStackingAnalysisLine(state, selectedAnalyses(ii))); %#ok<AGROW>
                end
            else
                L{end+1} = '- Input structure: selected NM modalities enter the configured single-modality or fusion pipeline.';
                for ii = 1:numel(usedModalities)
                    L{end+1} = sprintf('  - Modality %d: %s', usedModalities(ii), obj.methodsModalityLabel(state, usedModalities(ii))); %#ok<AGROW>
                end
            end
            L{end+1} = '';

            L{end+1} = '4. Partitioning and resampling';
            cvLines = obj.methodsCVLines(state);
            L = [L cvLines(:)']; %#ok<AGROW>
            L{end+1} = '';

            if obj.methodsSynthActive(state)
                L{end+1} = '5. Synthetic data generation';
                L{end+1} = ['- ' obj.methodsCleanSentence(obj.canvasSafeChar(state,'synthSummary','Synthetic data generation is enabled.'))];
                L{end+1} = '- Position in pipeline: before preprocessing and model fitting.';
                L{end+1} = '';
                nextSection = 6;
            else
                nextSection = 5;
            end

            L{end+1} = sprintf('%d. Preprocessing pipeline', nextSection); nextSection = nextSection + 1;
            preLines = obj.methodsPreprocLines(state);
            L = [L preLines(:)']; %#ok<AGROW>
            L{end+1} = '';

            L{end+1} = sprintf('%d. Machine-learning model configuration', nextSection); nextSection = nextSection + 1;
            mlLines = obj.methodsMLLines(state);
            L = [L mlLines(:)']; %#ok<AGROW>
            L{end+1} = '';

            L{end+1} = sprintf('%d. Ensemble/model-selection configuration', nextSection); nextSection = nextSection + 1;
            rfeTxt = obj.methodsCleanSentence(obj.canvasSafeChar(state,'rfeSummary','Ensemble/model-selection settings use the current NeuroMiner RFE configuration.'));
            L{end+1} = ['- ' rfeTxt];
            L{end+1} = '';

            L{end+1} = sprintf('%d. Visualization and interpretable machine learning', nextSection); nextSection = nextSection + 1;
            L{end+1} = ['- Visualization: ' obj.methodsCleanSentence(obj.canvasSafeChar(state,'visSummary','Visualization settings use the current NeuroMiner defaults.'))];
            L{end+1} = ['- Stored interpretable-ML parameters (not evidence of execution): ' obj.methodsCleanSentence(state.mliSummary)];
            L{end+1} = '';

            L{end+1} = sprintf('%d. Configuration consistency check', nextSection); nextSection = nextSection + 1;
            L = [L obj.methodsAuditLines(auditSummary, audit)]; %#ok<AGROW>
            L{end+1} = '';

            L{end+1} = sprintf('%d. Manuscript methods scaffold', nextSection); nextSection = nextSection + 1;
            L{end+1} = obj.methodsManuscriptScaffold(state);
            L{end+1} = '';

            L{end+1} = sprintf('%d. Appendix: technical configuration inventory', nextSection);
            invLines = obj.methodsInventoryLines(canvas);
            L = [L invLines(:)']; %#ok<AGROW>

            txt = strjoin(L, newline);
        end

        function tf = methodsIsStacking(obj, state)
            % methodsIsStacking  Report whether the current state represents active stacking.
            %
            % Reads stacking flags from the browser/menu state and normalizes legacy inactive/active values.
            %
            % state.stackingFlag: carries the stacking flag value between browser/API state and legacy NeuroMiner structures.
            tf = false;
            try
                tf = obj.isStackingEnabled() || (isstruct(state) && isfield(state,'stackingFlag') && double(state.stackingFlag) == 1);
            catch
                tf = false;
            end
        end

        function label = methodsAnalysisModeLabel(obj, state)
            % METHODSANALYSISMODELABEL  Return a human-readable analysis-mode label.
            %   Distinguishes single-modality, early/intermediate/late fusion and stacking modes for methods text.
            if obj.methodsIsStacking(state), label = 'Stacking'; return; end
            f = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            switch round(double(f))
                case 1, label = 'Early multimodal fusion';
                case 2, label = 'Intermediate multimodal fusion';
                case 3, label = 'Late multimodal fusion';
                otherwise, label = 'Single-modality analysis';
            end
        end

        function label = methodsTaskTypeLabel(obj, state)
            % methodsTaskTypeLabel  Return the supervised task label for methods text.
            %
            % Reads classification/regression information from the effective NM/state context and falls back to
            % a generic task label when the mode is not explicit.
            %
            % state.altLabelMode: carries the effective label mode published by the alternative-label authority.
            % state.isMultiClassProblem: carries the is multi class problem value between browser/API state and legacy NeuroMiner structures.
            label = 'classification';
            try
                if isfield(state,'altLabelMode') && ~isempty(state.altLabelMode)
                    label = char(string(state.altLabelMode));
                elseif isfield(obj.NM,'modeflag') && ~isempty(obj.NM.modeflag)
                    label = char(string(obj.NM.modeflag));
                end
            catch
            end
            if isfield(state,'isMultiClassProblem') && logical(state.isMultiClassProblem)
                label = 'multiclass classification';
            elseif contains(lower(label),'regress')
                label = 'regression';
            elseif contains(lower(label),'class')
                label = 'binary classification';
            end
        end

        function label = methodsTargetLabel(obj, state)
            % methodsTargetLabel  Describe the target variable used by the current analysis.
            %
            % Resolves alternative-label state, NM mode labels and available label metadata into one display string.
            %
            % state.altLabelEnabled: carries the alt label enabled value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelSourceVar: carries the alt label source var value between browser/API state and legacy NeuroMiner structures.
            label = 'default NeuroMiner label';
            try
                if isfield(state,'altLabelEnabled') && logical(state.altLabelEnabled)
                    if isfield(state,'altLabelSourceVar') && ~isempty(state.altLabelSourceVar)
                        label = sprintf('alternative label variable %s', char(string(state.altLabelSourceVar)));
                    else
                        label = 'alternative label configuration';
                    end
                elseif isfield(obj.NM,'modeflag') && ~isempty(obj.NM.modeflag)
                    label = sprintf('default NeuroMiner label (%s)', char(string(obj.NM.modeflag)));
                end
            catch
            end
        end

        function idx = methodsUsedModalities(obj, state)
            % methodsUsedModalities  Return modality indices participating in the active design.
            %
            % Handles stacking, single-modality and fusion states and normalizes indices to available NM modalities.
            %
            % state.fusionModalities: carries the fusion modalities value between browser/API state and legacy NeuroMiner structures.
            if obj.methodsIsStacking(state), idx = []; return; end
            f = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            if round(double(f)) == 0
                idx = obj.canvasGetScalar(state,'activeModality',obj.VarIndex);
            else
                try, idx = double(state.fusionModalities(:))'; catch, idx = obj.FusionModalities; end
            end
            idx = idx(isfinite(idx) & idx >= 1);
            if isempty(idx), idx = obj.VarIndex; end
            idx = unique(round(idx),'stable');
        end

        function txt = methodsModalityLabel(obj, state, idx)
            % methodsModalityLabel  Return a display label for one modality index.
            %
            % Combines modality numbering with inferred modality labels and imaging metadata when available.
            %
            % state.modalityIsImaging: carries the modality is imaging value between browser/API state and legacy NeuroMiner structures.
            % state.modalityLabels: carries the modality labels value between browser/API state and legacy NeuroMiner structures.
            txt = sprintf('Modality %d', idx);
            try
                labs = state.modalityLabels;
                if iscell(labs) && numel(labs) >= idx && ~isempty(labs{idx})
                    txt = char(string(labs{idx}));
                elseif isstring(labs) && numel(labs) >= idx
                    txt = char(labs(idx));
                end
                if isfield(state,'modalityIsImaging') && numel(state.modalityIsImaging) >= idx && logical(state.modalityIsImaging(idx))
                    txt = [txt ' [imaging]'];
                end
            catch
            end
        end

        function txt = methodsIndexList(obj, idx) %#ok<INUSL>
            % METHODSINDEXLIST  Format a numeric index vector as a compact list string.
            %   Returns a stable human-readable representation for modality and analysis index lists.
            if isempty(idx), txt = 'none selected'; return; end
            idx = double(idx(:))';
            txt = strjoin(arrayfun(@(x)sprintf('%d',round(x)), idx, 'UniformOutput', false), ', ');
        end

        function selected = methodsSelectedStackingAnalyses(obj, state)
            % methodsSelectedStackingAnalyses  Return selected first-tier analyses for stacking text.
            %
            % Reads browser state and orchestrator defaults, normalizes the selection, and removes unavailable analyses.
            %
            % state.stackingSelectedAnalyses: carries the stacking selected analyses value between browser/API state and legacy NeuroMiner structures.
            selected = [];
            try
                selected = obj.canvasStackingSelectedAnalyses(state);
            catch
                try, selected = double(state.stackingSelectedAnalyses(:))'; catch, selected = []; end
            end
        end

        function line = methodsStackingAnalysisLine(obj, state, idx)
            % methodsStackingAnalysisLine  Format one selected stacking input analysis.
            %
            % Produces a concise line containing the analysis index, label and availability information for methods text.
            %
            % state.stackingCandidateIndices: carries the stacking candidate indices value between browser/API state and legacy NeuroMiner structures.
            % state.stackingCandidateLabels: carries the stacking candidate labels value between browser/API state and legacy NeuroMiner structures.
            name = sprintf('Analysis %d', idx);
            try
                candIdx = double(state.stackingCandidateIndices(:))';
                k = find(candIdx == idx, 1, 'first');
                if ~isempty(k)
                    labs = state.stackingCandidateLabels;
                    if iscell(labs), name = char(string(labs{k})); else, name = char(string(labs(k))); end
                end
            catch
            end
            line = sprintf('Analysis %d: %s. Role: first-tier source analysis contributing fold-wise prediction outputs to the second-tier stacking representation.', idx, name);
        end

        function txt = methodsExecutiveSummary(obj, state)
            % METHODSEXECUTIVESUMMARY  Compose the top-level prose summary of the analysis design.
            %   Mentions task, target, modalities, fusion/stacking mode, preprocessing and learner summary without
            %   materializing legacy training structures.
            modeLabel = obj.methodsAnalysisModeLabel(state);
            if obj.methodsIsStacking(state)
                selected = obj.methodsSelectedStackingAnalyses(state);
                txt = sprintf(['This configuration defines a stacking analysis in which fold-wise prediction outputs from %d selected first-tier NeuroMiner analyses ', ...
                    'are used to construct the input representation for a second-tier learner. %s The second-tier model is summarized below with its configured hyperparameter grid.'], ...
                    numel(selected), obj.methodsPreprocExecutivePhrase(state));
            else
                used = obj.methodsUsedModalities(state);
                if numel(used) == 1, noun = 'modality'; else, noun = 'modalities'; end
                txt = sprintf('This configuration defines an analysis with %s using %d selected %s. %s The learner and downstream visualization settings are summarized below.', ...
                    lower(modeLabel), numel(used), noun, obj.methodsPreprocExecutivePhrase(state));
            end
        end

        function txt = methodsPreprocExecutivePhrase(obj, state)
            % METHODSPREPROCEXECUTIVEPHRASE  Produce a short preprocessing phrase for the executive summary.
            %   Summarizes active preprocessing counts and scope while avoiding long per-step detail.
            steps = obj.methodsCollectDisplayedPreprocSteps(state);
            if isempty(steps)
                txt = 'The pipeline uses the currently configured preprocessing settings.';
                return;
            end
            titles = {steps.title};
            titles = titles(~cellfun(@isempty,titles));
            if numel(titles) > 4
                txt = sprintf('The preprocessing sequence includes %s and %d additional step%s.', strjoin(titles(1:4), ', '), numel(titles)-4, obj.pluralSuffix(numel(titles)-4));
            else
                txt = sprintf('The preprocessing sequence includes %s.', strjoin(titles, ', '));
            end
        end

        function tf = methodsSynthActive(obj, state)
            % methodsSynthActive  Test whether synthetic-data augmentation is enabled in the state.
            %
            % Normalizes legacy and browser flag conventions and returns false when the state is absent or malformed.
            %
            % state.synth: carries the synth value between browser/API state and legacy NeuroMiner structures.
            tf = false;
            try
                if isfield(state,'synth') && isstruct(state.synth) && isfield(state.synth,'synthEnabled')
                    tf = logical(state.synth.synthEnabled);
                end
            catch
                tf = false;
            end
        end

        function lines = methodsCVLines(obj, state)
            % Describe the canonical CV state produced by NMCVPartitionTools.
            cv = state.cv;
            if cv.cvHasStructure
                lines = {'- An existing CV partition structure (NM.cv) is available; its source (loaded file versus generated) is not recorded.'};
            else
                lines = {'- CV generation settings are configured; no existing CV structure is available.'};
            end
            lines{end+1} = sprintf('- Framework code: %s', obj.methodsValueText(cv.cvFramework));
            lines{end+1} = sprintf('- Outer CV2 partitioning: %s', obj.methodsValueText(cv.cvOuterMode));
            lines{end+1} = sprintf('- Outer CV2 folds: %s', obj.methodsValueText(cv.cvOuterFold));
            lines{end+1} = sprintf('- Outer CV2 permutations: %s', obj.methodsValueText(cv.cvOuterPerm));
            lines{end+1} = sprintf('- Inner CV1 partitioning: %s', obj.methodsValueText(cv.cvInnerMode));
            lines{end+1} = sprintf('- Inner CV1 folds: %s', obj.methodsValueText(cv.cvInnerFold));
            lines{end+1} = sprintf('- Inner CV1 permutations: %s', obj.methodsValueText(cv.cvInnerPerm));
            if cv.cvEqEnabled
                lines{end+1} = '- CV1 training-partition equalization: enabled.';
            end
            lines{end+1} = '- Scope: partitioning defines the training/test separation for preprocessing, model training, model selection, and performance estimation.';
        end

        function lines = methodsPreprocLines(obj, state)
            % METHODSPREPROCLINES  Build methods-text lines for preprocessing configuration.
            %   Iterates over active modality branches or stacking preprocessing and expands displayable preprocessing steps.
            lines = {};
            if obj.methodsIsStacking(state)
                steps = obj.methodsPreprocStepsForBranch(obj.StackingPreproc, 1, 'STACKING.PREPROC');
                lines{end+1} = '- Stacking preprocessing: the second-tier stacking representation is processed before fitting the second-tier learner.';
                lines = obj.methodsAppendStepLines(lines, steps, '  ', obj.StackingPreproc);
                return;
            end
            f = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            used = obj.methodsUsedModalities(state);
            switch round(double(f))
                case 1
                    idx = used(1);
                    pp = obj.safePreprocAt(idx);
                    steps = obj.methodsPreprocStepsForBranch(pp, idx, sprintf('Shared early-fusion PREPROC{%d}', idx));
                    lines{end+1} = '- Early fusion: selected modalities are merged before entering one shared preprocessing sequence.';
                    lines = obj.methodsAppendStepLines(lines, steps, '  ', pp);
                case 2
                    lines{end+1} = '- Intermediate fusion: each selected modality is preprocessed separately before fusion.';
                    for ii = 1:numel(used)
                        idx = used(ii);
                        lines{end+1} = sprintf('  Modality %d: %s', idx, obj.methodsModalityLabel(state, idx)); %#ok<AGROW>
                        pp = obj.safePreprocAt(idx);
                        steps = obj.methodsPreprocStepsForBranch(pp, idx, sprintf('PREPROC{%d}', idx));
                        lines = obj.methodsAppendStepLines(lines, steps, '    ', pp);
                    end
                case 3
                    lines{end+1} = '- Late fusion: each selected modality is preprocessed and modelled separately before late-fusion decision aggregation.';
                    for ii = 1:numel(used)
                        idx = used(ii);
                        lines{end+1} = sprintf('  Modality %d: %s', idx, obj.methodsModalityLabel(state, idx)); %#ok<AGROW>
                        pp = obj.safePreprocAt(idx);
                        steps = obj.methodsPreprocStepsForBranch(pp, idx, sprintf('STRAT{%d}.PREPROC', idx));
                        lines = obj.methodsAppendStepLines(lines, steps, '    ', pp);
                    end
                otherwise
                    idx = used(1);
                    lines{end+1} = sprintf('- Single-modality preprocessing for Modality %d: %s', idx, obj.methodsModalityLabel(state, idx));
                    pp = obj.safePreprocAt(idx);
                    steps = obj.methodsPreprocStepsForBranch(pp, idx, sprintf('PREPROC{%d}', idx));
                    lines = obj.methodsAppendStepLines(lines, steps, '  ', pp);
            end
        end

        function pp = safePreprocAt(obj, idx)
            % SAFEPREPROCAT  Return a preprocessing orchestrator for a modality if available.
            %   Protects callers from missing, undersized or non-orchestrator Preproc cell entries by returning [] on failure.
            pp = [];
            try
                if idx >= 1 && idx <= numel(obj.Preproc), pp = obj.Preproc{idx}; end
            catch
                pp = [];
            end
        end

        function steps = methodsPreprocStepsForBranch(obj, pp, idx, scope)
            % METHODSPREPROCSTEPSFORBRANCH  Return displayable preprocessing steps for one branch.
            %   Uses the branch preprocessing orchestrator and fusion scope to select the relevant subject/CV preprocessing steps.
            steps = obj.canvasPreprocStepSpecs(pp, idx, scope);
        end

        function steps = methodsCollectDisplayedPreprocSteps(obj, state)
            % Gather all displayed branches; early fusion has only one shared branch.
            steps = struct('id',{}, 'title',{}, 'subtitle',{}, 'summary',{}, 'stage',{}, 'moduleId',{}, 'order',{}, 'usesLabels',{}, 'usesCovariates',{});
            if obj.methodsIsStacking(state)
                steps = obj.methodsPreprocStepsForBranch(obj.StackingPreproc, 1, 'STACKING.PREPROC');
            else
                idx = obj.methodsUsedModalities(state);
                if obj.FusionFlag == 1, idx = idx(1); end
                for k = idx
                    steps = [steps, obj.methodsPreprocStepsForBranch(obj.safePreprocAt(k), k, sprintf('PREPROC{%d}',k))]; %#ok<AGROW>
                end
            end
        end

        function lines = methodsAppendStepLines(obj, lines, steps, indent, pp)
            % Expand the configured steps using the existing canvas module inspectors.
            if isempty(steps)
                lines{end+1} = [indent '- No preprocessing steps are configured in this branch.'];
                return;
            end
            for ii = 1:numel(steps)
                st = obj.canvasPreprocStepFromOrchestrator(pp, ...
                    struct('stepIndex',steps(ii).order, 'stage',steps(ii).stage));
                if strcmp(st.moduleId,'correctnuis')
                    detail = {steps(ii).summary};
                    if strcmp(st.config.method,'combat')
                        m = st.config.methodConfig;
                        detail{end+1} = sprintf('Retain outcome-label variance: %s; unseen-batch handling: %s', ...
                            obj.canvasFormatBoolean(m.retainLabels), m.unseenBatchMode);
                    end
                else
                    seq = obj.canvasSequenceForPreprocNode(pp, steps(ii).stage);
                    module = seq.Registry.get(st.moduleId);
                    detail = obj.canvasPreprocConfigLinesForModule(st.moduleId, st.config, module.configSpec(seq.Context));
                end
                lines{end+1} = sprintf('%s%d. %s', indent, ii, steps(ii).title); %#ok<AGROW>
                lines{end+1} = sprintf('%s   - Scope: %s', indent, steps(ii).subtitle); %#ok<AGROW>
                for j = 1:numel(detail)
                    lines{end+1} = sprintf('%s   - %s', indent, obj.methodsCleanSentence(detail{j})); %#ok<AGROW>
                end
            end
        end

        function lines = methodsMLLines(obj, state)
            % METHODSMLLINES  Build methods-text lines for learner and ML settings.
            %   Resolves the active ML configuration, learner name and tuned hyperparameters into concise report lines.
            lines = {};
            [cfg, role] = obj.methodsActiveMLConfig(state);
            title = 'Machine-learning learner';
            try
                if isstruct(cfg) && isfield(cfg,'algorithm') && ~isempty(cfg.algorithm)
                    title = NMLearnerLibrary.title(char(string(cfg.algorithm)));
                end
            catch
                try, title = char(string(cfg.algorithm)); catch, end
            end
            lines{end+1} = sprintf('- Learner: %s', title);
            lines{end+1} = sprintf('- Role: %s', role);
            sections = {'criterion','learner','optimization','selection'};
            for i = 1:numel(sections)
                details = obj.canvasMLSectionLines(cfg, sections{i}, 12);
                for j = 1:numel(details)
                    lines{end+1} = ['  - ' details{j}]; %#ok<AGROW>
                end
            end
            hpLines = obj.methodsMLHyperparameterLines(cfg);
            if isempty(hpLines)
                lines{end+1} = '- Hyperparameters: fixed settings for the active learner.';
            else
                lines{end+1} = '- Hyperparameter grid:';
                for ii = 1:numel(hpLines)
                    lines{end+1} = ['  - ' hpLines{ii}]; %#ok<AGROW>
                end
            end
        end

        function [cfg, role] = methodsActiveMLConfig(obj, state)
            % METHODSACTIVEMLCONFIG  Resolve the ML configuration relevant to the current state.
            %   Returns the global learner for single/early/intermediate/stacking mode or a representative stratified branch
            %   for late-fusion mode, together with a role label.
            cfg = struct();
            if obj.methodsIsStacking(state)
                role = 'second-tier stacking learner combining prediction-derived first-tier outputs.';
                try, cfg = obj.MLGlobal.MLConfig; catch, end
            elseif obj.FusionFlag == 3 && numel(obj.MLStrat) >= obj.VarIndex && ~isempty(obj.MLStrat{obj.VarIndex})
                role = sprintf('late-fusion base learner for modality %d.', obj.VarIndex);
                cfg = obj.MLStrat{obj.VarIndex}.MLConfig;
            else
                role = 'learner for the configured single-modality or fusion representation.';
                try, cfg = obj.MLGlobal.MLConfig; catch, end
            end
        end

        function lines = methodsMLHyperparameterLines(obj, cfg)
            % methodsMLHyperparameterLines  Format optimized ML hyperparameters for methods text.
            %
            % Combines visible model-level fields and learner parameter grid rows into readable summary lines.
            %
            % cfg.hyperparameters: stores fixed or default hyperparameter values associated with the selected learner.
            lines = {};
            if ~isstruct(cfg) || ~isfield(cfg,'hyperparameters') || ~isstruct(cfg.hyperparameters), return; end
            hp = cfg.hyperparameters;
            fields = obj.visibleMLHyperparameterFields(cfg);
            for ii = 1:numel(fields)
                name = fields{ii};
                if strcmpi(name,'learnerParams')
                    if isfield(hp,'learnerParams')
                        lines = [lines obj.methodsLearnerParamGridLines(hp.learnerParams, cfg)]; %#ok<AGROW>
                    end
                elseif isfield(hp,name)
                    line = obj.methodsGridLine(obj.prettyHyperparameterName(name), hp.(name));
                    if ~isempty(line), lines{end+1} = line; end %#ok<AGROW>
                end
            end
        end

        function lines = methodsLearnerParamGridLines(obj, rows, cfg)
            % METHODSLEARNERPARAMGRIDLINES  Format learner parameter-grid rows for methods text.
            %   Filters visible/tuned learner parameters, computes cardinalities where possible, and returns compact lines.
            lines = {};
            mlModule = NMMLModule();
            mlCtx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
            visibleNames = mlModule.visibleLearnerParamNames(cfg, mlCtx);
            if isstruct(rows), rows = num2cell(rows); end
            if ~iscell(rows), return; end
            for rr = 1:numel(rows)
                r = rows{rr};
                if ~isstruct(r), continue; end
                pname = sprintf('learner parameter %d', rr);
                if isfield(r,'name') && ~isempty(r.name), pname = char(string(r.name)); end
                if ~isempty(visibleNames) && ~any(strcmp(visibleNames, pname)), continue; end
                if isfield(r,'range')
                    line = obj.methodsGridLine(obj.prettyHyperparameterName(pname), r.range);
                    if ~isempty(line), lines{end+1} = line; end %#ok<AGROW>
                end
            end
        end

        function line = methodsGridLine(obj, name, val)
            % METHODSGRIDLINE  Format one hyperparameter value or grid specification.
            %   Converts numeric, logical, char, string, cell and struct values into one stable methods-text line.
            line = '';
            [ok, n, mn, mx, valuesTxt] = obj.methodsNumericGridStats(val);
            if ~ok, return; end
            if n <= 1, return; end
            if ~isempty(valuesTxt)
                line = sprintf('%s: %d candidate values; minimum = %s; maximum = %s; values = %s.', name, n, obj.methodsValueText(mn), obj.methodsValueText(mx), valuesTxt);
            else
                line = sprintf('%s: %d candidate values; minimum = %s; maximum = %s.', name, n, obj.methodsValueText(mn), obj.methodsValueText(mx));
            end
        end

        function [ok, n, mn, mx, valuesTxt] = methodsNumericGridStats(obj, val) %#ok<INUSL>
            % METHODSNUMERICGRIDSTATS  Summarize a numeric hyperparameter grid.
            %   Returns validity, count, minimum, maximum and a compact value string for scalar/vector numeric grids.
            ok = false; n = 0; mn = []; mx = []; valuesTxt = '';
            try
                if isnumeric(val) || islogical(val)
                    v = double(val(:));
                elseif ischar(val) || isstring(val)
                    txt = strtrim(char(string(val)));
                    v = str2double(txt); 
                elseif iscell(val)
                    vv = [];
                    for ii = 1:numel(val)
                        if isnumeric(val{ii}) || islogical(val{ii}), vv = [vv; double(val{ii}(:))]; end %#ok<AGROW>
                    end
                    v = vv;
                else
                    return;
                end
                v = v(isfinite(v));
                if isempty(v), return; end
                u = unique(v(:))';
                n = numel(u); mn = min(u); mx = max(u); ok = true;
                if n <= 12
                    valuesTxt = mat2str(u, 6);
                end
            catch
                ok = false;
            end
        end

        function lines = methodsAuditLines(obj, summary, audit)
            % METHODSAUDITLINES  Append audit status lines to the methods/report text.
            %   Uses audit summary counts and detailed audit items to document blocking or warning-level configuration issues.
            lines = {};
            if summary.nErrors > 0
                lines{end+1} = sprintf('- Status: blocking issue detected (%d error%s, %d warning%s).', summary.nErrors, obj.pluralSuffix(summary.nErrors), summary.nWarnings, obj.pluralSuffix(summary.nWarnings));
            elseif summary.nWarnings > 0
                lines{end+1} = sprintf('- Status: review recommended (%d warning%s).', summary.nWarnings, obj.pluralSuffix(summary.nWarnings));
            else
                lines{end+1} = sprintf('- Status: ready. No blocking configuration errors were detected.');
            end
            try
                sev = {audit.severity};
                show = find(strcmp(sev,'error') | strcmp(sev,'warning'));
                if isempty(show), show = find(strcmp(sev,'info'), min(3,numel(sev)), 'first'); end
                for ii = 1:numel(show)
                    it = audit(show(ii));
                    lines{end+1} = sprintf('  - %s: %s', obj.methodsSeverityLabel(it.severity), obj.methodsCleanSentence(it.message)); %#ok<AGROW>
                end
            catch
            end
        end

        function label = methodsSeverityLabel(obj, sev) %#ok<INUSL>
            % METHODSSEVERITYLABEL  Map audit severity tokens to display labels.
            %   Normalizes error, warning, info and ok severities for methods-text output.
            switch lower(char(string(sev)))
                case 'error', label = 'Blocking issue';
                case 'warning', label = 'Review recommended';
                case 'ok', label = 'Ready';
                otherwise, label = 'Information';
            end
        end

        function txt = methodsManuscriptScaffold(obj, state)
            % METHODSMANUSCRIPTSCAFFOLD  Build a reusable methods-section scaffold.
            %   Produces prose fragments that describe data, validation, preprocessing, learning and reporting choices for
            %   manuscript or protocol documentation.
            if obj.methodsIsStacking(state)
                selected = obj.methodsSelectedStackingAnalyses(state);
                [cfg, ~] = obj.methodsActiveMLConfig(state);
                learner = obj.methodsLearnerName(cfg);
                hp = obj.methodsMLHyperparameterLines(cfg);
                if isempty(hp)
                    hpTxt = 'using the configured fixed hyperparameter settings';
                else
                    hpTxt = ['with hyperparameter optimization (' strjoin(hp, '; ') ')'];
                end
                txt = sprintf(['A stacking model was configured in NeuroMiner. %d previously defined first-tier analyses were selected as source models. ', ...
                    'Their fold-wise prediction outputs were used to construct the input representation for the second-tier learner. ', ...
                    'The stacking representation was processed using the configured stacking preprocessing sequence. ', ...
                    'The second-tier model was configured using %s, %s. Visualization settings and available MLI parameters were stored; the latter do not establish interpretation execution.'], ...
                    numel(selected), learner, hpTxt);
            else
                used = obj.methodsUsedModalities(state);
                [cfg, ~] = obj.methodsActiveMLConfig(state);
                learner = obj.methodsLearnerName(cfg);
                if numel(used) == 1, noun = 'modality'; else, noun = 'modalities'; end
                txt = sprintf(['An analysis with %s was configured in NeuroMiner using %d selected %s. ', ...
                    'The selected input representation was processed according to the configured preprocessing pipeline and passed to a %s learner. ', ...
                    'Cross-validation, ensemble/model-selection and visualization settings followed the NeuroMiner training-template configuration; stored MLI parameters do not establish execution.'], ...
                    lower(obj.methodsAnalysisModeLabel(state)), numel(used), noun, learner);
            end
        end

        function name = methodsLearnerName(obj, cfg) %#ok<INUSL>
            % methodsLearnerName  Resolve the display name of the active learner.
            %
            % Reads learner metadata from the ML configuration and falls back to stable internal identifiers when labels are absent.
            %
            % cfg.algorithm: stores the selected learner/preprocessing algorithm inside a normalized configuration.
            name = 'machine-learning';
            try
                if isstruct(cfg) && isfield(cfg,'algorithm') && ~isempty(cfg.algorithm)
                    name = NMLearnerLibrary.title(char(string(cfg.algorithm)));
                end
            catch
                try, name = char(string(cfg.algorithm)); catch, end
            end
        end

        function lines = methodsInventoryLines(obj, canvas)
            % METHODSINVENTORYLINES  Summarize rendered canvas nodes for methods documentation.
            %   Converts the browser flowchart into an inventory of active processing blocks and their display labels.
            lines = {};
            nodes = obj.canvasEmptyNodes();
            try, nodes = canvas.nodes; catch, end
            if isempty(nodes)
                lines{end+1} = '- No canvas inventory is available.';
                return;
            end
            for ii = 1:numel(nodes)
                title = obj.methodsCleanSentence(nodes(ii).title);
                cfg = obj.methodsCleanSentence(nodes(ii).configurator);
                sm = obj.methodsCleanSentence(nodes(ii).summary);
                if isempty(cfg), cfg = 'context'; end
                lines{end+1} = sprintf('- %s: %s (%s).', title, sm, cfg); %#ok<AGROW>
            end
        end

        function txt = methodsCleanSentence(obj, txt) %#ok<INUSL>
            % METHODSCLEANSENTENCE  Normalize whitespace and punctuation in generated prose.
            %   Returns a single-line sentence fragment suitable for methods text.
            txt = char(string(txt));
            txt = regexprep(txt, '\s+', ' ');
            txt = regexprep(txt, '\s*\[ok\]\s*', ' ');
            txt = strrep(txt, 'Patch H audit layer', 'configuration consistency check');
            txt = strrep(txt, 'Patch H', 'configuration consistency check');
            txt = strrep(txt, '1 feature(s); available.', 'contributes prediction-derived outputs.');
            txt = strtrim(txt);
            if isempty(txt), return; end
            if ~any(endsWith(txt, {'.',';'})), txt = [txt '.']; end
        end

        function txt = methodsValueText(obj, val) %#ok<INUSL>
            % METHODSVALUETEXT  Convert arbitrary configuration values to concise prose text.
            %   Handles numeric, logical, text, cell and struct values without exposing large raw arrays.
            try
                if isnumeric(val) || islogical(val)
                    if isscalar(val), txt = sprintf('%.6g', double(val)); else, txt = mat2str(double(val), 6); end
                elseif ischar(val) || isstring(val)
                    txt = char(string(val));
                else
                    txt = char(string(val));
                end
            catch
                txt = '?';
            end
        end

        function applyMenuState(obj, state, changedPaths)
            % applyMenuState  Merge browser-posted menu state into this orchestrator.
            % Optional changedPaths limits browser calls to the named nm2_state menu fields;
            % omitting it preserves the existing full-state API behavior.
            %
            % Restores x_nmref heavy-array descriptors, updates alternative labels, CV/Synth/RFE/MULTI/VIS/MLI/SAV,
            % stacking, fusion and active-modality fields, then persists lightweight context to obj.NM. It changes
            % configuration state only and does not execute training.
            %
            % state.activeModality: carries the active modality value between browser/API state and legacy NeuroMiner structures.
            % state.altLabelEnabled: carries the alt label enabled value between browser/API state and legacy NeuroMiner structures.
            % state.cv: carries the cv value between browser/API state and legacy NeuroMiner structures.
            % state.fusionFlag: carries the fusion flag value between browser/API state and legacy NeuroMiner structures.
            % state.fusionModalities: carries the fusion modalities value between browser/API state and legacy NeuroMiner structures.
            % state.isMultiClassProblem: carries the is multi class problem value between browser/API state and legacy NeuroMiner structures.
            % state.mli: carries the mli value between browser/API state and legacy NeuroMiner structures.
            % state.multi: carries the multi value between browser/API state and legacy NeuroMiner structures.
            % state.rfe: carries the rfe value between browser/API state and legacy NeuroMiner structures.
            % state.sav: carries the sav value between browser/API state and legacy NeuroMiner structures.
            % state.stackingEnabled: carries the stacking enabled value between browser/API state and legacy NeuroMiner structures.
            % state.stackingFeatureNameMode: carries the stacking feature name mode value between browser/API state and legacy NeuroMiner structures.
            % state.stackingFeatureNameVariable: carries the stacking feature name variable value between browser/API state and legacy NeuroMiner structures.
            % state.stackingFlag: carries the stacking flag value between browser/API state and legacy NeuroMiner structures.
            % state.stackingPredictionMode: carries the stacking prediction mode value between browser/API state and legacy NeuroMiner structures.
            % state.stackingSelectedAnalyses: carries the stacking selected analyses value between browser/API state and legacy NeuroMiner structures.
            % state.synth: carries the synth value between browser/API state and legacy NeuroMiner structures.
            % state.verbosity: carries the verbosity value between browser/API state and legacy NeuroMiner structures.
            % state.verbosityValue: carries the verbosity value value between browser/API state and legacy NeuroMiner structures.
            % state.vis: carries the vis value between browser/API state and legacy NeuroMiner structures.
            if nargin < 2 || isempty(state) || ~isstruct(state), return; end
            partial = nargin >= 3;
            changedRoots = {};
            if partial
                paths = cellstr(string(changedPaths(:)));
                paths = paths(~cellfun(@isempty,paths));
                if isempty(paths), return; end
                changedRoots = unique(cellfun(@(p) strtok(p,'.'),paths,'UniformOutput',false),'stable');
                keep = intersect(fieldnames(state),changedRoots,'stable');
                drop = setdiff(fieldnames(state),keep,'stable');
                if ~isempty(drop), state = rmfield(state,drop); end
            end
            contextChanged = ~partial || any(ismember(changedRoots, ...
                {'stackingFlag','stackingEnabled','fusionFlag','fusionModalities','activeModality'}));
            stackingChanged = ~partial || any(startsWith(changedRoots,'stacking'));
            rfeChanged = ~partial || any(strcmp(changedRoots,'rfe'));
            visChanged = ~partial || any(strcmp(changedRoots,'vis'));
            mliChanged = ~partial || any(strcmp(changedRoots,'mli'));
            stackingWasEnabled = obj.isStackingEnabled();
            % Restore any x_nmref descriptors that returned from the browser.
            % Heavy arrays (CV index cells, etc.) are stripped to metadata on
            % the way out and the browser POSTs the descriptor back. Reinstate
            % the live MATLAB-side values here so downstream merges (e.g.
            % NMCVPartitionTools.stateFromMenu, which blanket-copies incoming
            % fields) never overwrite a real array with its own descriptor.
            try
                state = NMConfigTools.restoreArrayRefs(state, obj.menuHeavyFieldSource());
            catch
                % If the live snapshot is unavailable, leave descriptors in
                % place: downstream code can still detect x_nmref and skip,
                % which is safer than aborting the whole apply.
            end
            menuNM = obj.NM;
            if isfield(state,'altLabelEnabled')
                [obj.AlternativeLabel, obj.AlternativeLabelSourceVar] = NMAlternativeLabelTools.labelFromMenu(obj.NM, obj.AlternativeLabel, obj.AlternativeLabelSourceVar, state);
                % The LABEL edit is not persisted until applyAlternativeLabelContext.
                % Project only the pending LABEL branch; A2 authorities resolve
                % effective mode/response from that branch.
                menuNM.TrainParam.LABEL = obj.AlternativeLabel;
            end
            obj.applyMultiLabelMenuState(state);
            % Refresh the effective global multi-class flag from the A2
            % authority before individual configurators inspect availability.
            [state.isMultiClassProblem, nMultiClasses, multiClassLabels] = NMAlternativeLabelTools.effectiveClassInfo(menuNM);
            if isfield(state,'multi') && isstruct(state.multi)
                state.multi.multiAvailable = state.isMultiClassProblem;
                state.multi.multiClassCount = nMultiClasses;
                state.multi.multiClassLabels = multiClassLabels;
            end
            fns = fieldnames(state);
            if isfield(state,'cv') || any(startsWith(fns, 'cv'))
                obj.CVPartition = NMCVPartitionTools.stateFromMenu(menuNM, obj.CVPartition, state);
            end
            if isfield(state,'synth') || any(startsWith(fns, 'synth'))
                obj.Synth = NMSynthTools.stateFromMenu(menuNM, obj.Synth, state);
            end
            if isfield(state,'rfe') || any(startsWith(fns, 'rfe'))
                obj.RFE = NMRFETools.stateFromMenu(menuNM, obj.RFE, state, obj.VarIndex, obj.FusionFlag);
            end
            if isfield(state,'multi') || any(startsWith(fns, 'multi'))
                obj.Multi = NMMULTITools.stateFromMenu(menuNM, obj.Multi, state, obj.VarIndex, obj.FusionFlag);
            end
            if isfield(state,'vis') || any(startsWith(fns, 'vis'))
                obj.Vis = NMVISTools.stateFromMenu(menuNM, obj.Vis, state, obj.VarIndex, obj.FusionFlag);
            end
            if isfield(state,'mli') || any(startsWith(fns, 'mli'))
                obj.MLI = NMMLITools.stateFromMenu(menuNM, obj.MLI, state, obj.VarIndex, obj.FusionFlag);
            end
            if isfield(state,'sav') || any(startsWith(fns, 'sav')) || isfield(state,'verbosity') || isfield(state,'verbosityValue')
                obj.SAV = NMSAVTools.stateFromMenu(menuNM, obj.SAV, state);
            end
            hasStackingFlag = isfield(state,'stackingFlag');
            if hasStackingFlag
                obj.Stacking.flag = obj.clampStackingFlag(state.stackingFlag);
            elseif isfield(state,'stackingEnabled')
                % stackingEnabled is a derived browser/UI convenience flag. It
                % may be stale immediately after the stacking dropdown changes,
                % so it is used only when the authoritative stackingFlag field
                % is absent.
                if logical(state.stackingEnabled)
                    obj.Stacking.flag = 1;
                else
                    obj.Stacking.flag = 2;
                end
            end
            % Do not clear an explicit active stacking state here.  The
            % browser may be synchronizing an already active stacker before the
            % availability/candidate display metadata has been refreshed.
            if isfield(state,'stackingSelectedAnalyses')
                previousSelection = obj.getStackingSelectedAnalyses();
                obj.Stacking.sel_anal = obj.normalizeStackingSelection(state.stackingSelectedAnalyses);
                if ~isequal(previousSelection, obj.Stacking.sel_anal) && obj.isStackingEnabled()
                    ml = obj.materializeMLBranch('ml_global', struct());
                    if strcmp(ml.MLConfig.algorithm, 'SEQOPT')
                        ml.MLConfig.fixedSettings.C = NaN;
                        obj.NM = ml.toNM(obj.NM);
                    end
                end
            end
            if isfield(state,'stackingFeatureNameMode')
                obj.Stacking.featname_mode = obj.getAllowedScalar(state.stackingFeatureNameMode, 1, [1 2]);
                if obj.Stacking.featname_mode == 1
                    obj.Stacking.featname_edit = 'Automatic definition';
                end
            end
            if isfield(state,'stackingFeatureNameVariable')
                obj.Stacking.featname_edit = char(string(state.stackingFeatureNameVariable));
            end
            if isfield(state,'stackingPredictionMode')
                obj.Stacking.mode = obj.getAllowedScalar(state.stackingPredictionMode, 2, [1 2]);
            end
            if isfield(state,'fusionFlag'), obj.FusionFlag = obj.clampFusionFlag(state.fusionFlag); end
            if isfield(state,'fusionModalities')
                obj.FusionModalities = obj.normalizeModalities(state.fusionModalities, obj.NumModalities, obj.VarIndex);
            end
            if isfield(state,'activeModality')
                v = round(double(state.activeModality));
                if ~isfinite(v) || v < 1 || v > obj.NumModalities, v = 1; end
                obj.VarIndex = v;
            end
            if ~stackingWasEnabled && obj.isStackingEnabled() && ~obj.StackingAvailable
                obj.Stacking.flag = 2;
            end
            if ~partial || stackingChanged || contextChanged
                obj.normalizeStackingState();
                obj.normalizeFusionState();
            end
            if contextChanged && ...
                    NMPreprocOrchestrator.isMissingLegacyPreproc(obj.extractLegacyPreproc(obj.NM, obj.VarIndex, obj.FusionFlag))
                obj.materializePreprocBranch(obj.VarIndex, false);
                menuNM.TrainParam.PREPROC = obj.NM.TrainParam.PREPROC;
            end
            if (rfeChanged || contextChanged) && ~isempty(obj.RFE) && isstruct(obj.RFE)
                obj.RFE = NMRFETools.normalizeState(menuNM, obj.RFE, obj.VarIndex, obj.FusionFlag);
            end
            if (visChanged || contextChanged) && ~isempty(obj.Vis) && isstruct(obj.Vis)
                obj.Vis = NMVISTools.normalizeState(menuNM, obj.Vis, obj.VarIndex, obj.FusionFlag);
            end
            if (mliChanged || contextChanged) && ~isempty(obj.MLI) && isstruct(obj.MLI)
                obj.MLI = NMMLITools.normalizeState(menuNM, obj.MLI, obj.VarIndex, obj.FusionFlag);
            end
            if ~partial || stackingChanged || contextChanged
                obj.persistContextToNM();
            end
        end

        function persistContextToNM(obj)
            % PERSISTCONTEXTTONM  Persist lightweight context into obj.NM.TrainParam.
            %   Writes fusion flag/modalities, active modality and stacking controls while preserving any stored
            %   STACKING.PREPROC branch. This keeps menu/canvas refreshes aligned with recent browser edits.
            if ~isfield(obj.NM,'TrainParam') || ~isstruct(obj.NM.TrainParam)
                obj.NM.TrainParam = struct();
            end
            obj.NM.TrainParam.FUSION.flag = obj.FusionFlag;
            obj.NM.TrainParam.FUSION.M = obj.FusionModalities;
            obj.NM.TrainParam.ActiveModality = obj.VarIndex;

            % Persist the lightweight stacking control state immediately.
            % Without this, a menu/canvas refresh can rebuild the browser state
            % from NM.TrainParam and lose a recently enabled STACKING.flag.
            if ~isfield(obj.NM.TrainParam,'STACKING') || ~isstruct(obj.NM.TrainParam.STACKING)
                obj.NM.TrainParam.STACKING = struct();
            end
            oldPREPROC = [];
            hasOldPREPROC = false;
            try
                hasOldPREPROC = isfield(obj.NM.TrainParam.STACKING,'PREPROC');
                if hasOldPREPROC
                    oldPREPROC = obj.NM.TrainParam.STACKING.PREPROC;
                end
            catch
                hasOldPREPROC = false;
            end
            if isstruct(obj.Stacking)
                f = fieldnames(obj.Stacking);
                for ii = 1:numel(f)
                    if strcmpi(f{ii},'PREPROC')
                        continue;
                    end
                    obj.NM.TrainParam.STACKING.(f{ii}) = obj.Stacking.(f{ii});
                end
            end
            if ~isfield(obj.NM.TrainParam.STACKING,'flag')
                obj.NM.TrainParam.STACKING.flag = 2;
            end
            obj.NM.TrainParam.STACKING.flag = obj.clampStackingFlag(obj.NM.TrainParam.STACKING.flag);
            if hasOldPREPROC
                obj.NM.TrainParam.STACKING.PREPROC = oldPREPROC;
            end
        end

        function refreshActiveConfiguratorStates(obj)
            % REFRESHACTIVECONFIGURATORSTATES  Rebuild state owned by the active context.
            obj.RFE = NMRFETools.stateFromNM(obj.NM, obj.VarIndex, obj.FusionFlag);
            obj.Multi = NMMULTITools.stateFromNM(obj.NM, obj.VarIndex, obj.FusionFlag);
            obj.Vis = NMVISTools.stateFromNM(obj.NM, obj.VarIndex, obj.FusionFlag);
            obj.MLI = NMMLITools.stateFromNM(obj.NM, obj.VarIndex, obj.FusionFlag);
            obj.Preproc = cell(1,obj.NumModalities);
            obj.StackingPreproc = [];
            obj.MLGlobal = [];
            obj.MLStrat = {};
            if obj.FusionFlag == 3, obj.MLStrat = cell(1,obj.NumModalities); end
        end

        function [summaries, counts, subjCounts, cvCounts, labelsByModality] = preprocSummariesForAll(obj)
            % PREPROCSUMMARIESFORALL  Summarize preprocessing for all modality branches.
            %   Returns per-modality text, total counts, subject/CV counts and label lists used by overview cards and canvas nodes.
            summaries = cell(1, obj.NumModalities);
            counts = zeros(1, obj.NumModalities);
            subjCounts = zeros(1, obj.NumModalities);
            cvCounts = zeros(1, obj.NumModalities);
            labelsByModality = cell(1, obj.NumModalities);
            for ii = 1:obj.NumModalities
                if obj.FusionFlag == 3
                    scope = sprintf('STRAT{%d}.PREPROC', ii);
                else
                    scope = sprintf('PREPROC{%d}', ii);
                end
                if ii <= numel(obj.Preproc) && ~isempty(obj.Preproc{ii})
                    [summaries{ii}, counts(ii), subjCounts(ii), cvCounts(ii), labelsByModality{ii}] = obj.preprocSummaryForObject(obj.Preproc{ii}, scope);
                else
                    labelsByModality{ii} = {};
                    summaries{ii} = sprintf('%s details load on demand.', scope);
                end
            end
        end

        function [txt, nTotal, nSubj, nCV, labels] = preprocSummaryForObject(obj, pp, scope)
            % PREPROCSUMMARYFOROBJECT  Summarize one preprocessing orchestrator and scope.
            %   Counts displayable subject-level and CV-level steps and formats a concise browser summary for one modality or stacker.
            nTotal = 0; nSubj = 0; nCV = 0; labels = {};
            try
                ssteps = obj.sequenceStepsFromPreprocObject(pp, 'subject');
                csteps = obj.sequenceStepsFromPreprocObject(pp, 'cv');
                nSubj = numel(ssteps);
                nCV = numel(csteps);
                nTotal = nSubj + nCV;
                labels = cell(1, nTotal);
                k = 0;
                for jj = 1:nSubj
                    k = k + 1; labels{k} = obj.preprocStepLabel(ssteps{jj}, 'subject');
                end
                for jj = 1:nCV
                    k = k + 1; labels{k} = obj.preprocStepLabel(csteps{jj}, 'cv');
                end
                if nTotal == 0
                    txt = sprintf('No preprocessing steps configured for %s.', scope);
                else
                    show = labels(1:min(numel(labels),5));
                    more = '';
                    if numel(labels) > numel(show), more = sprintf(' + %d more', numel(labels)-numel(show)); end
                    txt = sprintf('%d preprocessing step%s configured for %s (%d subject-specific, %d CV-bound): %s%s.', ...
                        nTotal, obj.pluralSuffix(nTotal), scope, nSubj, nCV, strjoin(show, ' -> '), more);
                end
            catch ME
                txt = sprintf('Preprocessing summary unavailable for %s: %s', scope, ME.message);
            end
        end

        function steps = sequenceStepsFromPreprocObject(obj, pp, stage) %#ok<INUSL>
            % SEQUENCESTEPSFROMPREPROCOBJECT  Extract ordered preprocessing steps from one orchestrator stage.
            %   Reads subject-level or CV-level sequence state and returns step structs suitable for display summarization.
            steps = {};
            if isempty(pp), return; end
            try
                if strcmpi(stage,'subject') && isprop(pp,'SubjectSequence') && ~isempty(pp.SubjectSequence) && isprop(pp.SubjectSequence,'Steps')
                    steps = pp.SubjectSequence.Steps;
                elseif isprop(pp,'CVSequence') && ~isempty(pp.CVSequence) && isprop(pp.CVSequence,'Steps')
                    steps = pp.CVSequence.Steps;
                end
            catch
                steps = {};
            end
            if isstruct(steps), steps = num2cell(steps); end
            if isempty(steps), steps = {}; end
        end

        function label = preprocStepLabel(obj, st, stage) %#ok<INUSL>
            % PREPROCSTEPLABEL  Format one preprocessing step label.
            %   Uses configured labels, IDs and stage context to produce stable browser/methods text for a preprocessing step.
            label = char(stage);
            try
                if isstruct(st) && isfield(st,'moduleId') && ~isempty(st.moduleId)
                    label = char(string(st.moduleId));
                end
            catch
                label = char(stage);
            end
        end

        function s = pluralSuffix(obj, n) %#ok<INUSL>
            % PLURALSUFFIX  Return an English plural suffix for count-sensitive labels.
            %   Returns '' for one item and 's' otherwise.
            if round(double(n)) == 1, s = ''; else, s = 's'; end
        end

        function tf = legacyPreprocPresence(obj)
            % LEGACYPREPROCPRESENCE  Report stored branches without constructing child authorities.
            tf = false(1,obj.NumModalities);
            for ii = 1:obj.NumModalities
                P = obj.extractLegacyPreproc(obj.NM, ii, obj.FusionFlag);
                tf(ii) = isstruct(P) && ~isempty(fieldnames(P));
            end
        end

        function scope = currentMLScope(obj)
            % CURRENTMLSCOPE  Return the ML scope implied by fusion and stacking state.
            %   Distinguishes global learner, modality-specific late-fusion branches and stacking second-tier learning.
            if obj.isStackingEnabled()
                scope = 'global_stacking';
            elseif obj.FusionFlag == 3
                scope = sprintf('strat_var%d', obj.VarIndex);
            else
                scope = 'global';
            end
        end

        function txt = mlSummaryForActive(obj)
            % MLSUMMARYFORACTIVE  Summarize the learner configuration for the active context.
            %   Resolves learner name and optimized hyperparameters from global, stratified or stacking ML state for browser cards.
            try
                deferred = (obj.FusionFlag == 3 && (numel(obj.MLStrat) < obj.VarIndex || isempty(obj.MLStrat{obj.VarIndex}))) || ...
                    (obj.FusionFlag ~= 3 && isempty(obj.MLGlobal));
                if deferred, txt = 'Machine-learning configuration details load on demand.'; return; end
                if obj.isStackingEnabled()
                    cfg = obj.MLGlobal.MLConfig;
                    scope = 'global stacker ML';
                elseif obj.FusionFlag == 3 && numel(obj.MLStrat) >= obj.VarIndex && ~isempty(obj.MLStrat{obj.VarIndex})
                    cfg = obj.MLStrat{obj.VarIndex}.MLConfig;
                    scope = sprintf('late-fusion STRAT{%d}', obj.VarIndex);
                else
                    cfg = obj.MLGlobal.MLConfig;
                    scope = 'global ML';
                end
                alg = '?';
                if isstruct(cfg) && isfield(cfg,'algorithm') && ~isempty(cfg.algorithm)
                    alg = char(string(cfg.algorithm));
                end
                title = alg;
                try
                    title = NMLearnerLibrary.title(alg);
                catch
                end
                [hpNames, nComb] = obj.optimizedMLHyperparameters(cfg);
                if isempty(hpNames)
                    txt = sprintf('%s configured for %s. All ML hyperparameters are fixed (1 combination).', title, scope);
                else
                    if isfinite(nComb)
                        combTxt = sprintf('%.0f', nComb);
                    else
                        combTxt = 'Inf';
                    end
                    txt = sprintf('%s configured for %s. Optimized hyperparameters: %s (%s combination%s).', ...
                        title, scope, strjoin(hpNames, ', '), combTxt, obj.pluralSuffix(nComb));
                end
            catch ME
                txt = sprintf('ML status unavailable: %s', ME.message);
            end
        end

        function [names, nComb] = optimizedMLHyperparameters(obj, cfg)
            % optimizedMLHyperparameters  List tuned model-level ML hyperparameters.
            %
            % Applies visibility rules to the ML configuration and returns parameter names plus the implied grid-combination count.
            %
            % cfg.hyperparameters: stores fixed or default hyperparameter values associated with the selected learner.
            names = {};
            nComb = 1;
            if ~isstruct(cfg) || ~isfield(cfg,'hyperparameters') || ~isstruct(cfg.hyperparameters)
                return;
            end

            % Only count hyperparameters that are active for the selected
            % learner and its current fixed/kernel settings. The ML config
            % state deliberately keeps ranges for many learners to support
            % lossless learner switching; counting every field in
            % cfg.hyperparameters therefore grossly overestimates the actual
            % optimization grid. The schema is the source of truth for dynamic
            % visibility, mirroring the ML configurator itself.
            hp = cfg.hyperparameters;
            activeFields = obj.visibleMLHyperparameterFields(cfg);

            for ii = 1:numel(activeFields)
                name = activeFields{ii};
                if strcmpi(name,'learnerParams')
                    if isfield(hp,'learnerParams')
                        [subNames, subComb] = obj.optimizedLearnerParamRows(hp.learnerParams, cfg);
                        if ~isempty(subNames)
                            names = [names, subNames]; %#ok<AGROW>
                            nComb = nComb * subComb;
                        end
                    end
                    continue;
                end
                if ~isfield(hp, name)
                    continue;
                end
                k = obj.hyperparameterCardinality(hp.(name));
                if k > 1
                    names{end+1} = obj.prettyHyperparameterName(name); %#ok<AGROW>
                    nComb = nComb * k;
                end
            end
        end

        function fields = visibleMLHyperparameterFields(obj, cfg)
            % VISIBLEMLHYPERPARAMETERFIELDS  Return ML hyperparameter fields visible for the current learner state.
            %   Visibility is delegated exclusively to NMMLModule under the effective A2 task mode.
            ctx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
            ml = NMMLModule();
            vf = ml.visibleUIFields(cfg, ctx);
            fields = {};
            for ii = 1:numel(vf)
                field = vf{ii};
                if ~isstruct(field) || ~isfield(field,'name') || isempty(field.name), continue; end
                name = char(string(field.name));
                if startsWith(name, 'hyperparameters.')
                    fields{end+1} = char(extractAfter(name, strlength('hyperparameters.'))); %#ok<AGROW>
                end
            end
            fields = obj.uniqueStableStrings(fields);
        end

        function tf = mlValueEquals(obj, a, b) %#ok<INUSL>
            % MLVALUEEQUALS  Compare two ML configuration values with type-tolerant semantics.
            %   Handles char/string, numeric and logical values without throwing on incompatible inputs.
            try
                if ischar(a) || isstring(a) || ischar(b) || isstring(b)
                    tf = strcmpi(char(string(a)), char(string(b)));
                elseif islogical(a) || islogical(b)
                    tf = isequal(logical(a), logical(b));
                else
                    tf = isequal(a, b);
                end
            catch
                tf = false;
            end
        end

        function val = mlNestedValue(obj, st, path, defaultVal) %#ok<INUSL>
            % MLNESTEDVALUE  Read a nested value from a struct using a path specification.
            %   Returns defaultVal when any path component is absent, non-struct, empty or otherwise inaccessible.
            val = defaultVal;
            try
                parts = strsplit(char(string(path)), '.');
                cur = st;
                for pp = 1:numel(parts)
                    key = parts{pp};
                    if ~isstruct(cur) || ~isfield(cur, key)
                        return;
                    end
                    cur = cur.(key);
                end
                if ~isempty(cur), val = cur; end
            catch
                val = defaultVal;
            end
        end

        function out = uniqueStableStrings(obj, in) %#ok<INUSL>
            % UNIQUESTABLESTRINGS  Return unique nonempty strings while preserving first occurrence order.
            %   Normalizes char/string/cell inputs to a row cell array and removes empty tokens.
            out = {};
            for ii = 1:numel(in)
                s = char(string(in{ii}));
                if isempty(s), continue; end
                if ~any(strcmp(out, s))
                    out{end+1} = s; %#ok<AGROW>
                end
            end
        end

        function [names, nComb] = optimizedLearnerParamRows(obj, rows, cfg)
            % OPTIMIZEDLEARNERPARAMROWS  Summarize tuned learner-parameter grid rows.
            %   Filters rows by visibility, computes parameter cardinalities and returns visible parameter names plus total grid size.
            names = {};
            nComb = 1;
            if nargin < 3, cfg = struct(); end
            if isempty(rows), return; end
            mlModule = NMMLModule();
            mlCtx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
            visibleNames = mlModule.visibleLearnerParamNames(cfg, mlCtx);
            if isstruct(rows)
                if numel(rows) == 1 && isfield(rows,'name') && isfield(rows,'range')
                    rows = num2cell(rows);
                elseif numel(rows) >= 1
                    rows = num2cell(rows);
                else
                    return;
                end
            elseif iscell(rows)
                % already row-like
            else
                return;
            end
            for rr = 1:numel(rows)
                r = rows{rr};
                if ~isstruct(r), continue; end
                pname = '';
                if isfield(r,'name') && ~isempty(r.name), pname = char(string(r.name)); end
                if isempty(pname), pname = sprintf('learner parameter %d', rr); end
                if ~isempty(visibleNames) && ~any(strcmp(visibleNames, pname))
                    continue;
                end
                if isfield(r,'range')
                    k = obj.hyperparameterCardinality(r.range);
                    if k > 1
                        names{end+1} = obj.prettyHyperparameterName(pname); %#ok<AGROW>
                        nComb = nComb * k;
                    end
                end
            end
        end

        function k = hyperparameterCardinality(obj, val) %#ok<INUSL>
            % HYPERPARAMETERCARDINALITY  Estimate how many candidate values a hyperparameter supplies.
            %   Counts vector/cell alternatives, treats scalar values as one, and returns one for opaque or empty values.
            k = 1;
            try
                if isempty(val), return; end
                if isnumeric(val) || islogical(val)
                    if isscalar(val), k = 1; else, k = numel(unique(val(:))); end
                elseif iscell(val)
                    % A learner-parameter cell array usually represents an
                    % explicit list of candidate values. Do not stringify nested
                    % numeric vectors here; the row-level learnerParams logic
                    % handles those separately.
                    k = max(1, numel(val));
                elseif ischar(val) || isstring(val)
                    v = string(val);
                    if isscalar(v)
                        txt = strtrim(char(v));
                        if isempty(txt), k = 1; return; end
                        % Treat a comma/space separated scalar string as one fixed
                        % setting unless it clearly encodes a MATLAB-like vector.
                        if startsWith(txt,'[') && endsWith(txt,']')
                            nums = str2num(txt); %#ok<ST2NM>
                            if ~isempty(nums), k = obj.hyperparameterCardinality(nums); end
                        else
                            k = 1;
                        end
                    else
                        k = numel(unique(v(:)));
                    end
                else
                    k = 1;
                end
            catch
                k = 1;
            end
            if ~isfinite(k) || k < 1, k = 1; end
        end

        function label = prettyHyperparameterName(obj, name) %#ok<INUSL>
            % PRETTYHYPERPARAMETERNAME  Convert an internal hyperparameter key into display text.
            %   Replaces underscores/camel-case fragments and preserves recognizable abbreviations for browser summaries.
            label = char(string(name));
            label = regexprep(label, 'params$', '', 'ignorecase');
            label = strrep(label, '_', ' ');
            if isempty(label), label = char(string(name)); end
        end

        function [tf, msg, labels, projection] = mixedEarlyFusionPreprocGuard(obj, projection)
            % MIXEDEARLYFUSIONPREPROCGUARD  Apply parent-owned mixed early-fusion preprocessing policy.
            %   RuleSet resolves preprocessing facts; this parent policy blocks only steps that
            %   require imaging/image-space semantics when the shared early-fusion branch mixes
            %   imaging and non-imaging modalities.
            tf = false; msg = ''; labels = {};
            if nargin < 2, projection = struct(); end
            if obj.FusionFlag ~= 1 || ~obj.selectedFusionMixesImaging() || isempty(obj.FusionModalities)
                return;
            end
            idx = obj.FusionModalities(1);
            if isempty(fieldnames(projection))
                if idx < 1 || idx > numel(obj.Preproc) || isempty(obj.Preproc{idx})
                    return;
                end
                projection = obj.Preproc{idx}.ruleProjection();
            end

            reasons = {};
            stages = {'subject','cv'};
            for ss = 1:numel(stages)
                stage = stages{ss};
                facts = projection.(stage).facts;
                for ii = 1:numel(facts)
                    fact = facts{ii};
                    if isfield(fact,'valid') && ~logical(fact.valid), continue; end
                    [bad, reason] = obj.mixedEarlyFusionFactReason(fact);
                    fact.mixedEarlyFusionBlocked = logical(bad);
                    fact.mixedEarlyFusionReason = reason;
                    projection.(stage).facts{ii} = fact;
                    if bad
                        reasons{end+1} = reason; %#ok<AGROW>
                        labels{end+1} = char(string(fact.moduleId)); %#ok<AGROW>
                    end
                end
            end
            tf = ~isempty(reasons);
            if tf
                labels = unique(labels, 'stable');
                projection.errors = unique([projection.errors reasons], 'stable');
                projection.ok = false;
                msg = sprintf('Mixed imaging/non-imaging early fusion: shared preprocessing branch PREPROC{%d} contains incompatible imaging-specific operation%s: %s. Open preprocessing and remove or replace the marked card%s.', ...
                    idx, obj.pluralSuffix(numel(labels)), strjoin(labels, ', '), obj.pluralSuffix(numel(labels)));
            end
        end

        function [bad, reason] = mixedEarlyFusionFactReason(obj, fact)
            % MIXEDEARLYFUSIONFACTREASON  Evaluate one RuleSet fact under the parent fusion policy.
            bad = false; reason = '';
            if obj.FusionFlag ~= 1 || ~obj.selectedFusionMixesImaging(), return; end
            if ~isstruct(fact) || (isfield(fact,'valid') && ~logical(fact.valid)), return; end
            bad = logical(fact.imagingOnly) || logical(fact.requiresImageSpace) || ...
                logical(fact.requiresSpatialFeatureExtractionAllowed) || ...
                logical(fact.isSpatialFeatureExtractor) || logical(fact.isImageSpaceTerminal);
            if ~bad, return; end
            label = char(string(fact.moduleId));
            if logical(fact.imagingOnly)
                reason = sprintf('%s is imaging-specific and cannot be used when an early-fusion preprocessing branch mixes imaging and non-imaging modalities.', label);
            else
                reason = sprintf('%s requires image-space geometry and cannot be used in mixed early fusion.', label);
            end
        end

        function [issues, msg] = preprocAvailabilityIssues(obj)
            % PREPROCAVAILABILITYISSUES  Audit preprocessing availability for the effective current context.
            %   Only branches used by the selected no-/early-/intermediate-/late-fusion or stacking
            %   configuration participate; stale PREPROC entries outside that context cannot invalidate it.
            parts = cell(1, max(1, obj.NumModalities) + 1);
            n = 0;
            cap = max(16, 4 * max(1, obj.NumModalities));
            issues = repmat(obj.preprocAvailabilityIssuePrototype(), 1, cap);
            if obj.isStackingEnabled()
                auditIdx = [];
            elseif obj.FusionFlag == 1 && ~isempty(obj.FusionModalities)
                auditIdx = obj.FusionModalities(1);
            elseif any(obj.FusionFlag == [2 3]) && ~isempty(obj.FusionModalities)
                auditIdx = obj.FusionModalities;
            else
                auditIdx = obj.VarIndex;
            end
            auditIdx = unique(round(double(auditIdx(:)')), 'stable');
            auditIdx = auditIdx(isfinite(auditIdx) & auditIdx >= 1 & auditIdx <= obj.NumModalities);
            for kk = 1:numel(auditIdx)
                ii = auditIdx(kk);
                pp = [];
                try
                    if ii <= numel(obj.Preproc), pp = obj.Preproc{ii}; end
                catch
                    pp = [];
                end
                [arr, localMsg] = obj.preprocAvailabilityIssuesForObject(pp, ii, obj.canvasPreprocScopeForModality(ii, obj.FusionFlag));
                if ~isempty(arr)
                    if n + numel(arr) > numel(issues)
                        issues(n + numel(arr) + cap) = obj.preprocAvailabilityIssuePrototype();
                    end
                    issues(n+1:n+numel(arr)) = arr;
                    n = n + numel(arr);
                    parts{min(numel(parts),ii)} = localMsg;
                end
            end
            if obj.isStackingEnabled()
                [arr, localMsg] = obj.preprocAvailabilityIssuesForObject(obj.StackingPreproc, 0, 'STACKING.PREPROC');
                if ~isempty(arr)
                    if n + numel(arr) > numel(issues)
                        issues(n + numel(arr) + cap) = obj.preprocAvailabilityIssuePrototype();
                    end
                    issues(n+1:n+numel(arr)) = arr;
                    n = n + numel(arr);
                    parts{end} = localMsg;
                end
            end
            issues = issues(1:n);
            parts = parts(~cellfun(@isempty, parts));
            if isempty(parts)
                msg = '';
            else
                msg = strjoin(parts, ' ');
            end
        end

        function proto = preprocAvailabilityIssuePrototype(obj) %#ok<MANU>
            % PREPROCAVAILABILITYISSUEPROTOTYPE  Return the fixed schema for preprocessing availability issues.
            %   The prototype prevents dynamic struct growth when issue rows are accumulated.
            proto = struct('modalityIndex',NaN,'scope','','stage','','stepIndex',NaN, ...
                'moduleId','','severity','warning','message','');
        end

        function [issues, msg] = preprocAvailabilityIssuesForObject(obj, pp, modalityIndex, scope)
            % PREPROCAVAILABILITYISSUESFOROBJECT  Audit preprocessing issues for one branch object.
            %   Checks the requested modality/scope for unavailable, incompatible or unsafe preprocessing steps and returns
            %   fixed-schema issue rows plus a summary message.
            issues = obj.preprocAvailabilityIssuePrototype();
            issues = issues([]);
            msg = '';
            if isempty(pp), return; end
            buf = repmat(struct('modalityIndex',NaN,'scope','','stage','','stepIndex',NaN, ...
                'moduleId','','severity','warning','message',''), 1, 16);
            n = 0;
            stages = {'subject','cv'};
            for ss = 1:numel(stages)
                stage = stages{ss};
                seq = [];
                try
                    if strcmp(stage,'subject'), seq = pp.SubjectSequence; else, seq = pp.CVSequence; end
                catch
                    seq = [];
                end
                if isempty(seq), continue; end
                nSteps = 0;
                try, nSteps = numel(seq.Steps); catch, nSteps = 0; end
                for kk = 1:nSteps
                    issue = seq.uiIssueForStep(kk);
                    if ~isstruct(issue) || ~isfield(issue,'hasIssue') || ~logical(issue.hasIssue), continue; end
                    n = n + 1;
                    if n > numel(buf), buf(n+16) = buf(1); end
                    moduleId = '';
                    try, moduleId = char(string(seq.Steps{kk}.moduleId)); catch, end
                    buf(n).modalityIndex = double(modalityIndex);
                    buf(n).scope = char(string(scope));
                    buf(n).stage = stage;
                    buf(n).stepIndex = double(kk);
                    buf(n).moduleId = moduleId;
                    sev = 'warning';
                    try
                        if strcmpi(char(string(issue.severity)), 'error'), sev = 'error'; end
                    catch
                    end
                    buf(n).severity = sev;
                    buf(n).message = char(string(issue.message));
                end
            end
            issues = buf(1:n);
            if ~isempty(issues)
                labels = cell(1,numel(issues));
                details = cell(1,numel(issues));
                for jj = 1:numel(issues)
                    labels{jj} = sprintf('%s step %d/%s', upper(issues(jj).stage), round(double(issues(jj).stepIndex)), char(string(issues(jj).moduleId)));
                    details{jj} = char(string(issues(jj).message));
                end
                msg = sprintf('%s contains preprocessing step%s that need review: %s. %s', ...
                    char(string(scope)), obj.pluralSuffix(numel(issues)), strjoin(labels, ', '), strjoin(details, ' | '));
            end
        end

        function target = preprocIssueTarget(obj, issue) %#ok<INUSL>
            % PREPROCISSUETARGET  Convert a preprocessing issue into a browser navigation target.
            %   Resolves modality/scope/stage metadata so the UI can focus the relevant configurator when the issue is selected.
            target = '';
            try
                target = sprintf('%s:%d:%s', lower(char(string(issue.stage))), round(double(issue.stepIndex)), lower(char(string(issue.moduleId))));
            catch
                target = '';
            end
        end

        function tf = selectedFusionMixesImaging(obj)
            % SELECTEDFUSIONMIXESIMAGING  Test whether selected fusion modalities mix imaging and non-imaging inputs.
            %   Uses inferred modality imaging flags and the current fusion selection to support fusion/preprocessing guards.
            tf = false;
            try
                M = obj.FusionModalities;
                if numel(M) < 2, return; end
                vals = false(1,numel(M));
                for ii = 1:numel(M)
                    idx = round(double(M(ii)));
                    if isfinite(idx) && idx >= 1 && idx <= numel(obj.ModalityIsImaging)
                        vals(ii) = logical(obj.ModalityIsImaging(idx));
                    end
                end
                tf = any(vals) && any(~vals);
            catch
                tf = false;
            end
        end

        function syncActiveModalityFromNM(obj)
            % SYNCACTIVEMODALITYFROMNM  Align stored active-modality state with the current fusion context.
            %   Reads ActiveModality when valid, then reapplies fusion normalization so early fusion remains anchored to FUSION.M(1).
            try
                if ~isfield(obj.NM,'TrainParam') || ~isstruct(obj.NM.TrainParam) || ...
                        ~isfield(obj.NM.TrainParam,'ActiveModality') || isempty(obj.NM.TrainParam.ActiveModality)
                    return;
                end
                v = obj.parseScalarIndex(obj.NM.TrainParam.ActiveModality, NaN);
                if isfinite(v) && v >= 1 && v <= obj.NumModalities
                    obj.VarIndex = v;
                    obj.normalizeFusionState();
                end
            catch
            end
        end

        function NM = toNM(obj, NM, ctx)
            % TONM  Materialize modular configuration back into legacy-compatible NM.TrainParam.
            %   Applies alternative labels, CV, Synth, preprocessing, ML, MULTI, RFE, VIS, MLI, SAV, fusion and stacking
            %   state to an NM struct. Side effect: refreshes this handle's module snapshots and obj.NM; it does not run training.
            if nargin < 2 || isempty(NM), NM = obj.NM; end
            if nargin < 3, ctx = struct(); end %#ok<NASGU>
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            NM = obj.ensureLegacyModuleDefaults(NM);
            altAction = 'none';
            hasMaterialLabel = isfield(NM.TrainParam,'LABEL') && isstruct(NM.TrainParam.LABEL);
            if obj.AlternativeLabel.flag == 1 || hasMaterialLabel
                [NM, altAction] = NMAlternativeLabelTools.applyToNM(NM, obj.AlternativeLabel, obj.VarIndex);
                if any(strcmp(altAction, {'reset','restore'}))
                    obj.NM = NM;
                    obj.FusionFlag = 0;
                    obj.FusionModalities = 1;
                    obj.VarIndex = 1;
                    return;
                end
            end
            NM = obj.applyMultiLabelToNM(NM);
            if ~isempty(obj.CVPartition) && isstruct(obj.CVPartition)
                NM = NMCVPartitionTools.applyToNM(NM, obj.CVPartition);
                obj.CVPartition = NMCVPartitionTools.stateFromNM(NM);
            end
            if ~isempty(obj.Synth) && isstruct(obj.Synth)
                NM = NMSynthTools.applyToNM(NM, obj.Synth);
                obj.Synth = NMSynthTools.stateFromNM(NM);
            end
            obj.normalizeStackingState();
            obj.normalizeFusionState();

            if obj.isStackingEnabled()
                obj.materializePreprocBranch(1, true);
                obj.materializeMLBranch('ml_global', ctx);
                % Explicit modular stacking mode. Fusion is suppressed for
                % compatibility with the legacy framework, but preprocessing is
                % no longer taken from PREPROC{1}; it is stored under STACKING.
                NM.TrainParam.STACKING = obj.finalizeStackingStateForExport(NM);
                NM.TrainParam.STACKING.flag = 1;
                NM.TrainParam.FUSION.flag = 0;
                NM.TrainParam.FUSION.M = 1;
                NM.TrainParam.ActiveModality = 1;
                try
                    NM.TrainParam.STACKING.PREPROC = obj.StackingPreproc.toLegacyPreproc();
                catch ME
                    warning('NMTrainTemplateOrchestrator:stackingPreprocExport', ...
                        'Could not export STACKING.PREPROC: %s', ME.message);
                end
                obj.MLGlobal.VarIndex = [];
                NM = obj.MLGlobal.toNM(NM);
                if ~isempty(obj.Multi) && isstruct(obj.Multi)
                    NM = NMMULTITools.applyToNM(NM, obj.Multi, obj.VarIndex, obj.FusionFlag);
                    obj.Multi = NMMULTITools.stateFromNM(NM, obj.VarIndex, obj.FusionFlag);
                end
                if ~isempty(obj.RFE) && isstruct(obj.RFE)
                    NM = NMRFETools.applyToNM(NM, obj.RFE, obj.VarIndex, obj.FusionFlag);
                    obj.RFE = NMRFETools.stateFromNM(NM, obj.VarIndex, obj.FusionFlag);
                end
                if ~isempty(obj.Vis) && isstruct(obj.Vis)
                    visWritten = (isfield(obj.Vis,'visPresent') && logical(obj.Vis.visPresent)) || ...
                        (isfield(obj.Vis,'visDirty') && logical(obj.Vis.visDirty));
                    NM = NMVISTools.applyToNM(NM, obj.Vis, obj.VarIndex, obj.FusionFlag);
                    if visWritten
                        obj.Vis = NMVISTools.normalizeState(NM, obj.Vis, obj.VarIndex, obj.FusionFlag);
                        obj.Vis.visPresent = true;
                        obj.Vis.visDirty = false;
                    end
                end
                if ~isempty(obj.MLI) && isstruct(obj.MLI)
                    mliWritten = (isfield(obj.MLI,'mliPresent') && logical(obj.MLI.mliPresent)) || ...
                        (isfield(obj.MLI,'mliDirty') && logical(obj.MLI.mliDirty));
                    NM = NMMLITools.applyToNM(NM, obj.MLI, obj.VarIndex, obj.FusionFlag);
                    if mliWritten
                        obj.MLI.mliPresent = true;
                        obj.MLI.mliDirty = false;
                    end
                end
                if ~isempty(obj.SAV) && isstruct(obj.SAV)
                    NM = NMSAVTools.applyToNM(NM, obj.SAV);
                    obj.SAV = NMSAVTools.stateFromNM(NM);
                end
                NM = obj.ensureLegacyModuleDefaults(NM);
                obj.NM = NM;
                return;
            else
                if ~isfield(NM.TrainParam,'STACKING') || ~isstruct(NM.TrainParam.STACKING)
                    NM.TrainParam.STACKING = obj.Stacking;
                else
                    NM.TrainParam.STACKING.flag = 2;
                end
            end

            NM.TrainParam.FUSION.flag = obj.FusionFlag;
            NM.TrainParam.FUSION.M = obj.FusionModalities;
            NM.TrainParam.ActiveModality = obj.VarIndex;

            if obj.FusionFlag == 3
                % Late fusion follows nk_TrainClass_config semantics:
                % each selected modality owns a full STRAT{i} branch, including
                % modality-specific PREPROC and SVM/GRD.
                NM = obj.ensureLegacyStratContainer(NM);
                for ii = 1:numel(obj.FusionModalities)
                    i = obj.FusionModalities(ii);
                    obj.materializePreprocBranch(i, false);
                    obj.materializeMLBranch(sprintf('ml_var%d',i), ctx);
                    if isempty(NM.TrainParam.STRAT{i}) || ~isstruct(NM.TrainParam.STRAT{i})
                        NM.TrainParam.STRAT{i} = struct();
                    end
                    try
                        NM.TrainParam.STRAT{i}.PREPROC = obj.Preproc{i}.toLegacyPreproc();
                    catch ME
                        warning('NMTrainTemplateOrchestrator:preprocExport', ...
                            'Could not export STRAT{%d}.PREPROC: %s', i, ME.message);
                    end
                    obj.MLStrat{i}.VarIndex = i;
                    NM = obj.MLStrat{i}.toNM(NM);
                end
            else
                % Non-late fusion has one global ML setup. PREPROC routing
                % follows the legacy fusion behaviour:
                %   flag 0: selected single modality
                %   flag 1: all fused modalities use PREPROC{FUSION.M(1)}
                %   flag 2: modality-specific PREPROC for each fused modality
                if ~isfield(NM.TrainParam,'PREPROC') || ~iscell(NM.TrainParam.PREPROC)
                    NM.TrainParam.PREPROC = cell(1, obj.NumModalities);
                end
                if numel(NM.TrainParam.PREPROC) < obj.NumModalities
                    NM.TrainParam.PREPROC{obj.NumModalities} = [];
                end

                switch obj.FusionFlag
                    case 1
                        % Early fusion follows the legacy convention that the
                        % shared preprocessing pipeline is stored only under the
                        % first fused modality. The remaining fused modalities do
                        % not receive duplicate PREPROC entries.
                        src = obj.FusionModalities(1);
                        obj.materializePreprocBranch(src, false);
                        try
                            NM.TrainParam.PREPROC{src} = obj.Preproc{src}.toLegacyPreproc();
                        catch ME
                            warning('NMTrainTemplateOrchestrator:preprocExport', ...
                                'Could not export early-fusion PREPROC{%d}: %s', src, ME.message);
                        end
                    otherwise
                        for ii = 1:numel(obj.FusionModalities)
                            i = obj.FusionModalities(ii);
                            obj.materializePreprocBranch(i, false);
                            try
                                NM.TrainParam.PREPROC{i} = obj.Preproc{i}.toLegacyPreproc();
                            catch ME
                                warning('NMTrainTemplateOrchestrator:preprocExport', ...
                                    'Could not export PREPROC{%d}: %s', i, ME.message);
                            end
                        end
                end

                obj.materializeMLBranch('ml_global', ctx);
                obj.MLGlobal.VarIndex = [];
                NM = obj.MLGlobal.toNM(NM);
            end
            if ~isempty(obj.Multi) && isstruct(obj.Multi)
                NM = NMMULTITools.applyToNM(NM, obj.Multi, obj.VarIndex, obj.FusionFlag);
                obj.Multi = NMMULTITools.stateFromNM(NM, obj.VarIndex, obj.FusionFlag);
            end
            if ~isempty(obj.RFE) && isstruct(obj.RFE)
                NM = NMRFETools.applyToNM(NM, obj.RFE, obj.VarIndex, obj.FusionFlag);
                obj.RFE = NMRFETools.stateFromNM(NM, obj.VarIndex, obj.FusionFlag);
            end
            if ~isempty(obj.Vis) && isstruct(obj.Vis)
                visWritten = (isfield(obj.Vis,'visPresent') && logical(obj.Vis.visPresent)) || ...
                    (isfield(obj.Vis,'visDirty') && logical(obj.Vis.visDirty));
                NM = NMVISTools.applyToNM(NM, obj.Vis, obj.VarIndex, obj.FusionFlag);
                if visWritten
                    obj.Vis = NMVISTools.normalizeState(NM, obj.Vis, obj.VarIndex, obj.FusionFlag);
                    obj.Vis.visPresent = true;
                    obj.Vis.visDirty = false;
                end
            end
            if ~isempty(obj.MLI) && isstruct(obj.MLI)
                mliWritten = (isfield(obj.MLI,'mliPresent') && logical(obj.MLI.mliPresent)) || ...
                    (isfield(obj.MLI,'mliDirty') && logical(obj.MLI.mliDirty));
                NM = NMMLITools.applyToNM(NM, obj.MLI, obj.VarIndex, obj.FusionFlag);
                if mliWritten
                    obj.MLI.mliPresent = true;
                    obj.MLI.mliDirty = false;
                end
            end
            if ~isempty(obj.SAV) && isstruct(obj.SAV)
                NM = NMSAVTools.applyToNM(NM, obj.SAV);
                obj.SAV = NMSAVTools.stateFromNM(NM);
            end
            NM = obj.ensureLegacyModuleDefaults(NM);
            obj.NM = NM;
        end

        function tf = isSeqoptStacking(obj)
            % The active stacking learner owns the SEQOPT constraint.
            tf = false;
            if ~obj.isStackingEnabled(), return; end
            if isempty(obj.MLGlobal)
                ml = NMTrainConfigOrchestrator.fromNM(obj.thinNMForML(obj.NM, [], min(obj.FusionFlag,2)), [], struct());
            else
                ml = obj.MLGlobal;
            end
            tf = strcmp(ml.MLConfig.algorithm,'SEQOPT');
        end

        function tf = isStackingEnabled(obj)
            tf = isstruct(obj.Stacking) && isfield(obj.Stacking,'flag') && isequal(round(double(obj.Stacking.flag)),1);
        end
    end

    methods (Access = private)

        function fields = multiLabelMenuFields(obj)
            fields = struct('multiLabelAvailable',false,'multiLabelSelection',[], ...
                'multiLabelLabels',{{}},'multiLabelCount',0);
            if ~isfield(obj.NM,'label') || isempty(obj.NM.label), return; end
            nLabels = size(obj.NM.label,2);
            labels = arrayfun(@(i) sprintf('Label %d',i),1:nLabels,'UniformOutput',false);
            if isfield(obj.NM,'labelnames') && numel(obj.NM.labelnames) >= nLabels
                labels = cellstr(string(obj.NM.labelnames(1:nLabels)));
            end
            fields.multiLabelLabels = labels;
            if nLabels <= 1, return; end
            fields.multiLabelSelection = obj.currentMultiLabelSelection(nLabels);
            fields.multiLabelCount = numel(fields.multiLabelSelection);
            fields.multiLabelAvailable = true;
        end

        function applyMultiLabelMenuState(obj, state)
            if ~isfield(obj.NM,'TrainParam') || ~isstruct(obj.NM.TrainParam)
                obj.NM.TrainParam = struct();
            end
            if ~isfield(obj.NM,'label') || isempty(obj.NM.label), return; end
            nLabels = size(obj.NM.label,2);
            altActive = isfield(obj.AlternativeLabel,'flag') && obj.AlternativeLabel.flag == 1;
            if nLabels <= 1 || altActive
                if isfield(obj.NM.TrainParam,'MULTILABEL')
                    obj.NM.TrainParam = rmfield(obj.NM.TrainParam,'MULTILABEL');
                end
                return;
            end
            if isfield(state,'multiLabelSelection')
                sel = obj.normalizeMultiLabelSelection(state.multiLabelSelection,nLabels,true);
            else
                sel = obj.currentMultiLabelSelection(nLabels);
            end
            obj.NM.TrainParam.MULTILABEL = struct('flag',true,'sel',sel,'dim',numel(sel));
        end

        function NM = applyMultiLabelToNM(obj, NM)
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            if ~isfield(NM,'label') || isempty(NM.label), return; end
            nLabels = size(NM.label,2);
            altActive = isfield(obj.AlternativeLabel,'flag') && obj.AlternativeLabel.flag == 1;
            if nLabels <= 1 || altActive
                if isfield(NM.TrainParam,'MULTILABEL')
                    NM.TrainParam = rmfield(NM.TrainParam,'MULTILABEL');
                end
                return;
            end
            sel = obj.currentMultiLabelSelection(nLabels);
            NM.TrainParam.MULTILABEL = struct('flag',true,'sel',sel,'dim',numel(sel));
        end

        function sel = currentMultiLabelSelection(obj, nLabels)
            raw = [];
            if isfield(obj.NM,'TrainParam') && isstruct(obj.NM.TrainParam) && ...
                    isfield(obj.NM.TrainParam,'MULTILABEL') && isstruct(obj.NM.TrainParam.MULTILABEL) && ...
                    isfield(obj.NM.TrainParam.MULTILABEL,'sel')
                raw = obj.NM.TrainParam.MULTILABEL.sel;
            elseif isfield(obj.AlternativeLabel,'OrigTrainParam') && isstruct(obj.AlternativeLabel.OrigTrainParam) && ...
                    isfield(obj.AlternativeLabel.OrigTrainParam,'MULTILABEL') && isstruct(obj.AlternativeLabel.OrigTrainParam.MULTILABEL) && ...
                    isfield(obj.AlternativeLabel.OrigTrainParam.MULTILABEL,'sel')
                raw = obj.AlternativeLabel.OrigTrainParam.MULTILABEL.sel;
            end
            sel = obj.normalizeMultiLabelSelection(raw,nLabels,false);
            if isempty(sel), sel = 1:nLabels; end
        end

        function sel = normalizeMultiLabelSelection(obj, raw, nLabels, requireNonempty) %#ok<INUSL>
            if nargin < 4, requireNonempty = false; end
            if isempty(raw)
                if requireNonempty
                    error('NMTrainTemplateOrchestrator:emptyMultiLabelSelection', ...
                        'At least one label must be selected in multi-label mode.');
                end
                sel = [];
                return;
            end
            if ~(isnumeric(raw) || islogical(raw))
                error('NMTrainTemplateOrchestrator:badMultiLabelSelection', ...
                    'Multi-label selection must contain numeric label indices.');
            end
            vals = double(raw(:)');
            if any(~isfinite(vals)) || any(vals ~= round(vals)) || any(vals < 1) || any(vals > nLabels)
                error('NMTrainTemplateOrchestrator:badMultiLabelSelection', ...
                    'Multi-label selection must contain integer indices between 1 and %d.', nLabels);
            end
            sel = unique(round(vals),'stable');
            if requireNonempty && isempty(sel)
                error('NMTrainTemplateOrchestrator:emptyMultiLabelSelection', ...
                    'At least one label must be selected in multi-label mode.');
            end
        end

        function NM = ensureLegacyModuleDefaults(obj, NM)
            if nargin < 2 || isempty(NM), NM = obj.NM; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            nY = obj.NumModalities;
            try
                if isfield(NM,'Y') && iscell(NM.Y) && ~isempty(NM.Y), nY = max(nY, numel(NM.Y)); end
            catch
            end
            if isempty(nY) || nY < 1, nY = 1; end
            nY = round(double(nY));

            NM.TrainParam = obj.ensureTrainParamScaffold(NM.TrainParam, NM, nY);
            NM = obj.ensureGlobalBranchDefaults(NM, nY);
            NM = obj.ensureStackingPreprocDefault(NM);
            if isfield(NM.TrainParam,'FUSION') && isstruct(NM.TrainParam.FUSION) && ...
                    isfield(NM.TrainParam.FUSION,'flag') && round(double(NM.TrainParam.FUSION.flag)) == 3
                NM = obj.ensureLateFusionBranchDefaults(NM, nY);
            end
        end

        function TP = ensureTrainParamScaffold(obj, TP, NM, nY)
            if nargin < 2 || isempty(TP) || ~isstruct(TP), TP = struct(); end
            if ~isfield(TP,'FUSION') || ~isstruct(TP.FUSION), TP.FUSION = struct(); end
            if ~isfield(TP.FUSION,'flag') || isempty(TP.FUSION.flag), TP.FUSION.flag = obj.FusionFlag; end
            TP.FUSION.flag = obj.clampFusionFlag(TP.FUSION.flag);
            if ~isfield(TP.FUSION,'M') || isempty(TP.FUSION.M)
                TP.FUSION.M = obj.FusionModalities;
            end
            TP.FUSION.M = obj.normalizeModalities(TP.FUSION.M, nY, obj.VarIndex);
            if any(TP.FUSION.M > nY)
                TP.FUSION.flag = 0;
                TP.FUSION.M = 1;
            end
            if ~isfield(TP,'ActiveModality') || isempty(TP.ActiveModality)
                TP.ActiveModality = obj.VarIndex;
            end
            TP.ActiveModality = max(1, min(nY, round(double(TP.ActiveModality))));

            if ~isfield(TP,'STACKING') || ~isstruct(TP.STACKING), TP.STACKING = struct(); end
            if ~isfield(TP.STACKING,'flag') || isempty(TP.STACKING.flag), TP.STACKING.flag = 2; end
            TP.STACKING.flag = obj.clampStackingFlag(TP.STACKING.flag);

            if obj.isMissingStructField(TP, 'RAND')
                TP.RAND = NMCVPartitionTools.defaultSetting(NM);
            end
            if obj.isMissingStructField(TP, 'SYNTH')
                TP.SYNTH = NMSynthTools.defaultSetting(NM);
            end
            if obj.isMissingStructField(TP, 'SAV')
                [TP.SAV, defVerbosity] = NMSAVTools.defaultSetting(NM);
            else
                [~, defVerbosity] = NMSAVTools.defaultSetting(NM);
            end
            if obj.isMissingStructField(TP, 'SVM') || obj.isMissingStructField(TP, 'GRD')
                [defSVM, defGRD] = NMTrainConfigOrchestrator.defaultSetting(NM, TP.ActiveModality, struct());
                if obj.isMissingStructField(TP, 'SVM'), TP.SVM = defSVM; end
                if obj.isMissingStructField(TP, 'GRD'), TP.GRD = defGRD; end
            end
            if ~isfield(TP,'verbosity') || isempty(TP.verbosity)
                TP.verbosity = defVerbosity;
            end
            if obj.isMissingStructField(TP, 'LABEL')
                TP.LABEL = struct('flag',0);
                if isfield(NM,'label'), TP.LABEL.origlabel = NM.label; else, TP.LABEL.origlabel = []; end
            elseif ~isfield(TP.LABEL,'flag') || isempty(TP.LABEL.flag)
                TP.LABEL.flag = 0;
            end
        end

        function NM = ensureGlobalBranchDefaults(obj, NM, nY)
            TP = NM.TrainParam;
            if obj.isMissingStructField(TP, 'MULTI')
                TP.MULTI = NMMULTITools.defaultSetting(NM, TP.ActiveModality, TP.FUSION.flag);
            end
            if obj.isMissingStructField(TP, 'RFE')
                TP.RFE = NMRFETools.defaultSetting(NM, TP.ActiveModality, TP.FUSION.flag);
            end

            if ~isfield(TP,'PREPROC') || isempty(TP.PREPROC)
                TP.PREPROC = cell(1, nY);
            elseif ~iscell(TP.PREPROC)
                TP.PREPROC = {TP.PREPROC};
            end
            if numel(TP.PREPROC) < nY, TP.PREPROC{nY} = []; end
            for ii = 1:nY
                if NMPreprocOrchestrator.isMissingLegacyPreproc(TP.PREPROC{ii})
                    TP.PREPROC{ii} = NMPreprocOrchestrator.defaultSetting(NM, ii);
                end
            end

            if ~isfield(TP,'VIS') || isempty(TP.VIS)
                TP.VIS = cell(1, nY);
            elseif ~iscell(TP.VIS)
                TP.VIS = {TP.VIS};
            end
            if numel(TP.VIS) < nY, TP.VIS{nY} = []; end
            for ii = 1:nY
                if obj.isMissingLegacyStruct(TP.VIS{ii})
                    TP.VIS{ii} = NMVISTools.defaultSetting(NM, TP.PREPROC{ii}, ii, TP.FUSION.flag);
                end
            end

            if obj.isMissingStructField(TP, 'MLI'), MLI = struct(); else, MLI = TP.MLI; end
            for ii = 1:nY
                MLI = NMMLITools.defaultSetting(NM, ii, TP.FUSION.flag, MLI);
            end
            TP.MLI = MLI;
            NM.TrainParam = TP;
        end

        function NM = ensureStackingPreprocDefault(obj, NM)
            if ~isfield(NM.TrainParam,'STACKING') || ~isstruct(NM.TrainParam.STACKING)
                NM.TrainParam.STACKING = struct('flag',2);
            end
            if ~isfield(NM.TrainParam.STACKING,'flag') || isempty(NM.TrainParam.STACKING.flag)
                NM.TrainParam.STACKING.flag = 2;
            end
            if ~isfield(NM.TrainParam.STACKING,'PREPROC') || ...
                    NMPreprocOrchestrator.isMissingLegacyPreproc(NM.TrainParam.STACKING.PREPROC)
                NMstk = obj.withStackingFlag(NM, 1);
                NM.TrainParam.STACKING.PREPROC = NMPreprocOrchestrator.defaultSetting(NMstk, 1, ...
                    'isImaging', false, 'isStackingInputLayer', true, ...
                    'isStackingAnalysisLayer', false, 'source', 'stacking');
            end
        end

        function NM = ensureLateFusionBranchDefaults(obj, NM, nY)
            TP = NM.TrainParam;
            if ~isfield(TP,'STRAT') || ~iscell(TP.STRAT), TP.STRAT = cell(1, nY); end
            if numel(TP.STRAT) < nY, TP.STRAT{nY} = []; end
            for ii = 1:nY
                if isempty(TP.STRAT{ii}) || ~isstruct(TP.STRAT{ii}), TP.STRAT{ii} = struct(); end
                preprocFallback = [];
                if isfield(TP,'PREPROC') && iscell(TP.PREPROC) && ~isempty(TP.PREPROC)
                    preprocFallback = TP.PREPROC{min(ii, numel(TP.PREPROC))};
                end
                if NMPreprocOrchestrator.isMissingLegacyPreproc(preprocFallback)
                    preprocFallback = NMPreprocOrchestrator.defaultSetting(NM, ii);
                end
                if NMPreprocOrchestrator.isMissingLegacyPreproc(obj.structFieldOr(TP.STRAT{ii}, 'PREPROC', []))
                    TP.STRAT{ii}.PREPROC = preprocFallback;
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'SVM') && isfield(TP,'SVM') && isstruct(TP.SVM)
                    TP.STRAT{ii}.SVM = TP.SVM;
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'GRD') && isfield(TP,'GRD') && isstruct(TP.GRD)
                    TP.STRAT{ii}.GRD = TP.GRD;
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'RFE')
                    if isfield(TP,'RFE') && isstruct(TP.RFE), TP.STRAT{ii}.RFE = TP.RFE;
                    else, TP.STRAT{ii}.RFE = NMRFETools.defaultSetting(NM, ii, 3);
                    end
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'MULTI')
                    if isfield(TP,'MULTI') && isstruct(TP.MULTI), TP.STRAT{ii}.MULTI = TP.MULTI;
                    else, TP.STRAT{ii}.MULTI = NMMULTITools.defaultSetting(NM, ii, 3);
                    end
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'VIS')
                    if isfield(TP,'VIS') && iscell(TP.VIS) && numel(TP.VIS) >= ii && isstruct(TP.VIS{ii}) && ~isempty(fieldnames(TP.VIS{ii}))
                        TP.STRAT{ii}.VIS = TP.VIS{ii};
                    elseif isfield(TP,'VIS') && iscell(TP.VIS) && ~isempty(TP.VIS) && isstruct(TP.VIS{1}) && ~isempty(fieldnames(TP.VIS{1}))
                        TP.STRAT{ii}.VIS = TP.VIS{1};
                    else
                        TP.STRAT{ii}.VIS = NMVISTools.defaultSetting(NM, TP.STRAT{ii}.PREPROC, ii, 3);
                    end
                end
                if obj.isMissingStructField(TP.STRAT{ii}, 'MLI')
                    if isfield(TP,'MLI') && isstruct(TP.MLI)
                        TP.STRAT{ii}.MLI = TP.MLI;
                        if isfield(TP.STRAT{ii}.MLI,'Modality') && iscell(TP.STRAT{ii}.MLI.Modality) && numel(TP.STRAT{ii}.MLI.Modality) >= ii
                            TP.STRAT{ii}.MLI.Modality = TP.STRAT{ii}.MLI.Modality(ii);
                        elseif isfield(TP.STRAT{ii}.MLI,'Modality') && iscell(TP.STRAT{ii}.MLI.Modality) && ~isempty(TP.STRAT{ii}.MLI.Modality)
                            TP.STRAT{ii}.MLI.Modality = TP.STRAT{ii}.MLI.Modality(1);
                        end
                    else
                        TP.STRAT{ii}.MLI = NMMLITools.defaultSetting(NM, ii, 3);
                    end
                end
                TP.STRAT{ii}.MLI = NMMLITools.defaultSetting(NM, ii, 3, TP.STRAT{ii}.MLI);
            end
            NM.TrainParam = TP;
        end

        function tf = isMissingStructField(obj, s, fieldName) %#ok<INUSL>
            tf = true;
            if ~isstruct(s) || ~isfield(s, fieldName), return; end
            tf = obj.isMissingLegacyStruct(s.(fieldName));
        end

        function tf = isMissingLegacyStruct(obj, val) %#ok<INUSL>
            tf = true;
            if nargin < 2 || isempty(val), return; end
            if ~isstruct(val), return; end
            if numel(val) ~= 1, tf = false; return; end
            tf = isempty(fieldnames(val));
        end

        function val = structFieldOr(obj, s, fieldName, defaultVal) %#ok<INUSL>
            val = defaultVal;
            try
                if isstruct(s) && isfield(s, fieldName), val = s.(fieldName); end
            catch
                val = defaultVal;
            end
        end

        function flag = clampStackingFlag(obj, flag)
            choices = obj.StackingChoices;
            try
                idx = find(strcmp(flag, {choices.symbol}), 1);
                if ~isempty(idx), flag = choices(idx).code; end
                idx = find([choices.code] == flag);
                assert(numel(idx)==1);
            catch
                error('NMTrainTemplateOrchestrator:invalidStackingFlag', ...
                    'Allowed: enabled (1), disabled (2).');
            end
        end


        function normalizeStackingState(obj)
            if ~isstruct(obj.Stacking), obj.Stacking = struct('flag',2); end
            obj.Stacking = obj.completeStackingDefaults(obj.Stacking, obj.StackingCandidates, obj.NM);
            obj.Stacking.flag = obj.clampStackingFlag(obj.Stacking.flag);
            % Keep STACKING.flag as the single source of truth for whether the
            % template is currently in stacking mode.  StackingAvailable only
            % controls whether the configurator is offered as a new action; it
            % must not silently switch an already active stacking template back
            % to no-stacking during menu/canvas synchronization.
            obj.Stacking.sel_anal = obj.normalizeStackingSelection(obj.Stacking.sel_anal);
            obj.Stacking.featname_mode = obj.getAllowedScalar(obj.Stacking.featname_mode, 1, [1 2]);
            obj.Stacking.mode = obj.getAllowedScalar(obj.Stacking.mode, 2, [1 2]);
            if obj.Stacking.featname_mode == 1
                if isempty(obj.Stacking.sel_anal)
                    obj.Stacking.featname_edit = '?';
                else
                    obj.Stacking.featname_edit = 'Automatic definition';
                end
            elseif ~isfield(obj.Stacking,'featname_edit') || isempty(obj.Stacking.featname_edit)
                obj.Stacking.featname_edit = '?';
            end
            if obj.isStackingEnabled()
                obj.FusionFlag = 0;
                obj.FusionModalities = 1;
                obj.VarIndex = 1;
            end
        end

        function STACKING = extractStackingState(obj, NM) %#ok<INUSL>
            STACKING = struct('flag',2);
            try
                if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'STACKING') && isstruct(NM.TrainParam.STACKING)
                    STACKING = NM.TrainParam.STACKING;
                end
            catch
                STACKING = struct('flag',2);
            end
            if ~isfield(STACKING,'flag'), STACKING.flag = 2; end
            STACKING.flag = obj.clampStackingFlag(STACKING.flag);
        end

        function tf = inferStackingAvailable(obj, NM, STACKING, candidates) %#ok<INUSL>
            % Legacy stacking gate: stacking can be configured only if at
            % least two completed analyses share an identical CV setup. The
            % status vectors are provided by nk_GetNMStatus via
            % completed_analyses and isequalcv_analyses.
            tf = false;
            try
                if isempty(candidates), return; end
                av = [candidates.available];
                tf = sum(logical(av)) >= 2;
            catch
                tf = false;
            end
        end

        function candidates = inferStackingCandidates(obj, NM) %#ok<INUSL>
            % Candidate analyses for stacking. Do not invent per-analysis
            % fields. Eligibility is taken from nk_GetNMStatus(NM):
            %   completed_analyses & isequalcv_analyses
            % Labels are read from NM.analysis{i} only for display.
            candidates = struct('index',{},'label',{},'available',{},'nfeatures',{},'completed',{},'equalcv',{});

            completed = [];
            equalcv = [];
            nfeatures = [];
            try
                s = nk_GetNMStatus(NM);
                if isfield(s,'completed_analyses') && ~isempty(s.completed_analyses)
                    completed = logical(s.completed_analyses(:))';
                end
                if isfield(s,'isequalcv_analyses') && ~isempty(s.isequalcv_analyses)
                    equalcv = logical(s.isequalcv_analyses(:))';
                end
                if isfield(s,'nmodal_analyses') && ~isempty(s.nmodal_analyses)
                    nfeatures = double(s.nmodal_analyses(:))';
                end
            catch ME
                % Do not infer availability from invented analysis fields. If
                % the legacy status function is unavailable or fails, stacking
                % remains unavailable. Store no error state here to keep the
                % template orchestrator side-effect free.
                completed = [];
                equalcv = [];
                nfeatures = [];
            end

            nAnal = max([numel(completed), numel(equalcv), numel(nfeatures), 0]);
            if nAnal == 0
                return;
            end

            if isempty(completed)
                completed = false(1,nAnal);
            else
                completed(end+1:nAnal) = false;
            end

            if isempty(equalcv)
                equalcv = false(1,nAnal);
            else
                equalcv(end+1:nAnal) = false;
            end

            if isempty(nfeatures)
                nfeatures = ones(1,nAnal);
            else
                nfeatures(end+1:nAnal) = 1;
            end

            for i = 1:nAnal
                lab = obj.analysisLabel(NM, i);
                candidates(end+1) = struct('index', i, 'label', lab, ... %#ok<AGROW>
                    'available', logical(completed(i) && equalcv(i)), ...
                    'nfeatures', double(nfeatures(i)), ...
                    'completed', logical(completed(i)), ...
                    'equalcv', logical(equalcv(i)));
            end
        end

        function lab = analysisLabel(obj, NM, i) %#ok<INUSL>
            lab = sprintf('Analysis %d', i);
            try
                if isfield(NM,'analysis') && iscell(NM.analysis) && numel(NM.analysis) >= i && isstruct(NM.analysis{i})
                    if isfield(NM.analysis{i},'id') && ~isempty(NM.analysis{i}.id)
                        lab = sprintf('Analysis %d: %s', i, char(string(NM.analysis{i}.id)));
                    elseif isfield(NM.analysis{i},'desc') && ~isempty(NM.analysis{i}.desc)
                        lab = sprintf('Analysis %d: %s', i, char(string(NM.analysis{i}.desc)));
                    end
                end
            catch
                lab = sprintf('Analysis %d', i);
            end
        end

        function STACKING = completeStackingDefaults(obj, STACKING, candidates, NM) %#ok<INUSL>
            if ~isstruct(STACKING), STACKING = struct(); end
            if ~isfield(STACKING,'flag'), STACKING.flag = 2; end
            STACKING.flag = obj.clampStackingFlag(STACKING.flag);
            nAnal = numel(candidates);
            if ~isfield(STACKING,'source_anal') || numel(STACKING.source_anal) ~= nAnal
                if nAnal > 0
                    if isfield(candidates,'completed')
                        STACKING.source_anal = [candidates.completed];
                    else
                        STACKING.source_anal = [candidates.available];
                    end
                else
                    STACKING.source_anal = [];
                end
            end
            if ~isfield(STACKING,'sel_anal') || isempty(STACKING.sel_anal)
                STACKING.sel_anal = [];
            else
                STACKING.sel_anal = obj.normalizeStackingSelection(STACKING.sel_anal);
            end
            if ~isfield(STACKING,'featname_mode'), STACKING.featname_mode = 1; end
            STACKING.featname_mode = obj.getAllowedScalar(STACKING.featname_mode, 1, [1 2]);
            if ~isfield(STACKING,'featname_edit') || isempty(STACKING.featname_edit)
                STACKING.featname_edit = '?';
            end
            if STACKING.featname_mode == 1
                if isempty(STACKING.sel_anal), STACKING.featname_edit = '?';
                else, STACKING.featname_edit = 'Automatic definition'; end
            end
            if ~isfield(STACKING,'featnames') || isempty(STACKING.featnames), STACKING.featnames = {[]}; end
            if ~isfield(STACKING,'mode'), STACKING.mode = 2; end
            STACKING.mode = obj.getAllowedScalar(STACKING.mode, 2, [1 2]);
        end

        function sel = normalizeStackingSelection(obj, sel)
            try, sel = double(sel(:))'; catch, sel = []; end
            sel = unique(round(sel(isfinite(sel))), 'stable');
            if isempty(obj.StackingCandidates), return; end
            idx = [obj.StackingCandidates.index];
            av = [obj.StackingCandidates.available];
            allowed = idx(av);
            sel = sel(ismember(sel, allowed));
        end

        function [idx, lab, av, nf] = stackingCandidateArrays(obj)
            idx = []; lab = {}; av = []; nf = [];
            for c = 1:numel(obj.StackingCandidates)
                idx(end+1) = obj.StackingCandidates(c).index; %#ok<AGROW>
                lab{end+1} = obj.StackingCandidates(c).label; %#ok<AGROW>
                av(end+1) = obj.StackingCandidates(c).available; %#ok<AGROW>
                nf(end+1) = obj.StackingCandidates(c).nfeatures; %#ok<AGROW>
            end
        end

        function sel = getStackingSelectedAnalyses(obj)
            if isstruct(obj.Stacking) && isfield(obj.Stacking,'sel_anal')
                sel = obj.normalizeStackingSelection(obj.Stacking.sel_anal);
            else
                sel = [];
            end
        end

        function val = getStackingNumericField(obj, field, defaultValue, allowed) %#ok<INUSL>
            val = defaultValue;
            try
                if isstruct(obj.Stacking) && isfield(obj.Stacking, field)
                    val = obj.getAllowedScalar(obj.Stacking.(field), defaultValue, allowed);
                end
            catch
                val = defaultValue;
            end
        end

        function val = getStackingCharField(obj, field, defaultValue) %#ok<INUSL>
            val = defaultValue;
            try
                if isstruct(obj.Stacking) && isfield(obj.Stacking, field) && ~isempty(obj.Stacking.(field))
                    val = char(string(obj.Stacking.(field)));
                end
            catch
                val = defaultValue;
            end
        end

        function val = getAllowedScalar(obj, val, defaultValue, allowed) %#ok<INUSL>
            try, val = round(double(val)); catch, val = defaultValue; end
            if isempty(val), val = defaultValue; else, val = val(1); end
            if ~isfinite(val) || ~ismember(val, allowed), val = defaultValue; end
        end

        function STACKING = finalizeStackingStateForExport(obj, NM)
            STACKING = obj.completeStackingDefaults(obj.Stacking, obj.StackingCandidates, NM);
            STACKING.flag = obj.clampStackingFlag(STACKING.flag);
            STACKING.sel_anal = obj.normalizeStackingSelection(STACKING.sel_anal);
            if STACKING.featname_mode == 1
                if isempty(STACKING.sel_anal)
                    STACKING.featname_edit = '?';
                    STACKING.featnames = {[]};
                else
                    STACKING.featname_edit = 'Automatic definition';
                    STACKING.featnames = obj.automaticStackingFeatureNames(NM, STACKING.sel_anal);
                end
            else
                if ~isfield(STACKING,'featname_edit') || isempty(STACKING.featname_edit)
                    STACKING.featname_edit = '?';
                end
                STACKING.featnames = {[]};
                if ~strcmp(STACKING.featname_edit,'?')
                    try
                        fn = evalin('base', STACKING.featname_edit);
                        if iscell(fn), STACKING.featnames = fn; end
                    catch
                    end
                end
            end
            STACKING.mode = obj.getAllowedScalar(STACKING.mode, 2, [1 2]);
        end

        function featnames = automaticStackingFeatureNames(obj, NM, sel) %#ok<INUSL>
            featnames = cell(1,numel(sel));
            for k = 1:numel(sel)
                i = sel(k);
                txt = sprintf('Analysis %d', i);
                try
                    if isfield(NM,'analysis') && iscell(NM.analysis) && numel(NM.analysis) >= i && isstruct(NM.analysis{i})
                        if isfield(NM.analysis{i},'id') && ~isempty(NM.analysis{i}.id)
                            txt = char(string(NM.analysis{i}.id));
                        elseif isfield(NM.analysis{i},'desc') && ~isempty(NM.analysis{i}.desc)
                            txt = char(string(NM.analysis{i}.desc));
                        end
                    end
                catch
                end
                featnames{k} = txt;
            end
        end

        function PREPROC = extractStackingPreproc(obj, NM) %#ok<INUSL>
            PREPROC = [];
            try
                if isfield(NM,'TrainParam') && isstruct(NM.TrainParam) && ...
                        isfield(NM.TrainParam,'STACKING') && isstruct(NM.TrainParam.STACKING) && ...
                        isfield(NM.TrainParam.STACKING,'PREPROC')
                    PREPROC = NM.TrainParam.STACKING.PREPROC;
                end
            catch
                PREPROC = [];
            end
        end

        function NM = withStackingFlag(obj, NM, flag) %#ok<INUSL>
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            if ~isfield(NM.TrainParam,'STACKING') || ~isstruct(NM.TrainParam.STACKING), NM.TrainParam.STACKING = struct(); end
            NM.TrainParam.STACKING.flag = flag;
        end

        function tf = activeModalityIsImaging(obj)
            tf = false;
            try
                idx = round(double(obj.VarIndex));
                if isfinite(idx) && idx >= 1 && idx <= numel(obj.ModalityIsImaging)
                    tf = logical(obj.ModalityIsImaging(idx));
                end
            catch
                tf = false;
            end
        end


        function [flags, keys, roiNames] = atlasSplitMenuMetadata(obj)
            flags = false(1, obj.NumModalities);
            keys = repmat({''}, 1, obj.NumModalities);
            roiNames = repmat({''}, 1, obj.NumModalities);
            try
                if ~isfield(obj.NM,'datadescriptor') || ~iscell(obj.NM.datadescriptor), return; end
                for ii = 1:min(obj.NumModalities, numel(obj.NM.datadescriptor))
                    dd = obj.NM.datadescriptor{ii};
                    if ~isstruct(dd), continue; end
                    isSplit = false;
                    try
                        isSplit = isfield(dd,'atlasSplit') && ~isempty(dd.atlasSplit) && logical(dd.atlasSplit);
                    catch
                        isSplit = false;
                    end
                    if ~isSplit, continue; end
                    flags(ii) = true;
                    key = 'atlas-split';
                    if isfield(dd,'atlasSplitProvenance') && isstruct(dd.atlasSplitProvenance)
                        prov = dd.atlasSplitProvenance;
                        if isfield(prov,'brainmaskOrAtlasFile') && ~isempty(prov.brainmaskOrAtlasFile)
                            key = char(string(prov.brainmaskOrAtlasFile));
                        elseif isfield(prov,'atlasFile') && ~isempty(prov.atlasFile)
                            key = char(string(prov.atlasFile));
                        elseif isfield(prov,'referenceImageFile') && ~isempty(prov.referenceImageFile)
                            key = char(string(prov.referenceImageFile));
                        end
                    end
                    keys{ii} = key;
                    if isfield(dd,'atlasSplitRoiName') && ~isempty(dd.atlasSplitRoiName)
                        roiNames{ii} = char(string(dd.atlasSplitRoiName));
                    elseif isfield(dd,'atlasSplitRoiID') && ~isempty(dd.atlasSplitRoiID)
                        roiNames{ii} = sprintf('ROI %s', char(string(dd.atlasSplitRoiID)));
                    end
                end
            catch
                flags = false(1, obj.NumModalities);
                keys = repmat({''}, 1, obj.NumModalities);
                roiNames = repmat({''}, 1, obj.NumModalities);
            end
        end

        function flags = inferModalityIsImaging(obj, NM, n) %#ok<INUSL>
            flags = false(1,n);
            for i = 1:n
                flags(i) = NMModalityInfoTools.isImaging(NM, i);
            end
        end

        function n = inferNumModalities(obj, NM) %#ok<INUSL>
            n = 1;
            if isstruct(NM) && isfield(NM,'Y')
                if iscell(NM.Y), n = max(1, numel(NM.Y));
                else, n = 1;
                end
            end
        end

        function labels = inferModalityLabels(obj, NM, n) %#ok<INUSL>
            labels = cell(1,n);
            for i = 1:n
                labels{i} = sprintf('Modality #%d', i);
                try
                    if isfield(NM,'datadescriptor') && numel(NM.datadescriptor) >= i && ...
                            isfield(NM.datadescriptor{i},'desc') && ~isempty(NM.datadescriptor{i}.desc)
                        labels{i} = sprintf('#%d: %s', i, char(NM.datadescriptor{i}.desc));
                    end
                catch
                end
            end
        end

        function v = parseScalarIndex(obj, x, fallback) %#ok<INUSL>
            if nargin < 3, fallback = NaN; end
            v = fallback;
            try
                if isnumeric(x) || islogical(x)
                    if ~isempty(x), v = round(double(x(1))); end
                elseif ischar(x) || isstring(x)
                    z = str2double(char(string(x)));
                    if isfinite(z), v = round(z); end
                end
            catch
                v = fallback;
            end
        end

        function [flag, M, active] = extractFusionState(obj, NM, varind, n) %#ok<INUSL>
            flag = 0; M = 1; active = 1;
            if isstruct(NM) && isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                TP = NM.TrainParam;
                if isfield(TP,'FUSION') && isstruct(TP.FUSION)
                    if isfield(TP.FUSION,'flag'), flag = obj.clampFusionFlag(TP.FUSION.flag); end
                    if isfield(TP.FUSION,'M'), M = obj.normalizeModalities(TP.FUSION.M, n, 1); end
                end
                hasStoredActive = false;
                if isfield(TP,'ActiveModality') && ~isempty(TP.ActiveModality)
                    active = obj.parseScalarIndex(TP.ActiveModality, NaN);
                    hasStoredActive = isfinite(active) && active >= 1 && active <= n;
                elseif ~isempty(M)
                    active = obj.parseScalarIndex(M(1), NaN);
                    hasStoredActive = isfinite(active) && active >= 1 && active <= n;
                end
            else
                hasStoredActive = false;
            end
            if nargin >= 3 && ~isempty(varind)
                v = obj.parseScalarIndex(varind, NaN);
                if isfinite(v) && v >= 1 && v <= n && (~hasStoredActive || v ~= 1)
                    active = v;
                end
            end
            if ~isfinite(active) || active < 1 || active > n, active = 1; end
            if flag == 0, M = active; else, M = obj.normalizeModalities(M, n, active); end
        end

        function PREPROC = extractLegacyPreproc(obj, NM, i, flag) %#ok<INUSL>
            PREPROC = [];
            try
                if flag == 3 && isfield(NM,'TrainParam') && isfield(NM.TrainParam,'STRAT') && ...
                        numel(NM.TrainParam.STRAT) >= i && isstruct(NM.TrainParam.STRAT{i}) && ...
                        isfield(NM.TrainParam.STRAT{i},'PREPROC')
                    PREPROC = NM.TrainParam.STRAT{i}.PREPROC;
                    return;
                end
                if isfield(NM,'TrainParam') && isfield(NM.TrainParam,'PREPROC') && ...
                        numel(NM.TrainParam.PREPROC) >= i
                    PREPROC = NM.TrainParam.PREPROC{i};
                end
            catch
                PREPROC = [];
            end
        end

        function lite = thinNMForML(obj, NM, varind, fusionFlag) %#ok<INUSL>
            lite = struct();
            if isfield(NM,'modeflag'), lite.modeflag = NM.modeflag; end
            if isfield(NM,'time'), lite.time = NM.time; end
            lite.TrainParam = struct();
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                TP = NM.TrainParam;
                if isfield(TP,'LABEL') && isstruct(TP.LABEL), lite.TrainParam.LABEL = TP.LABEL; end
                if isfield(TP,'SVM'), lite.TrainParam.SVM = TP.SVM; end
                if isfield(TP,'GRD'), lite.TrainParam.GRD = TP.GRD; end
            end
            lite.TrainParam.FUSION.flag = fusionFlag;
            if ~isempty(varind)
                lite.TrainParam.STRAT = cell(1, varind);
                lite.TrainParam.STRAT{varind} = obj.legacyStratForModality(NM, varind);
            end
        end

        function st = legacyStratForModality(obj, NM, i) %#ok<INUSL>
            st = struct();
            if isfield(NM,'TrainParam') && isstruct(NM.TrainParam)
                TP = NM.TrainParam;
                if isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= i && isstruct(TP.STRAT{i})
                    st = TP.STRAT{i};
                end
                if ~isfield(st,'SVM') && isfield(TP,'SVM'), st.SVM = TP.SVM; end
                if ~isfield(st,'GRD') && isfield(TP,'GRD'), st.GRD = TP.GRD; end
            end
        end

        function NM = ensureLegacyStratContainer(obj, NM)
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                NM.TrainParam.STRAT = cell(1, obj.NumModalities);
            end
            if numel(NM.TrainParam.STRAT) < obj.NumModalities
                NM.TrainParam.STRAT{obj.NumModalities} = [];
            end
        end

        function state = auditMinimalState(obj)
            state = struct();
            state.fusionFlag = obj.FusionFlag;
            state.fusionModalities = obj.FusionModalities;
            state.activeModality = obj.VarIndex;
            state.numModalities = obj.NumModalities;
            state.modalityLabels = obj.ModalityLabels;
            state.modalityIsImaging = obj.ModalityIsImaging;
            state.isImaging = obj.activeModalityIsImaging();
            try
                [badPP, badMsg, badSteps] = obj.mixedEarlyFusionPreprocGuard();
                state.preprocMixedEarlyFusionIllegal = badPP;
                state.preprocMixedEarlyFusionMessage = badMsg;
                state.preprocMixedEarlyFusionIllegalSteps = badSteps;
            catch
                state.preprocMixedEarlyFusionIllegal = false;
                state.preprocMixedEarlyFusionMessage = '';
                state.preprocMixedEarlyFusionIllegalSteps = {};
            end
            try
                [ppIssues, ppIssueMsg] = obj.preprocAvailabilityIssues();
                state.preprocAvailabilityIssues = ppIssues;
                state.preprocAvailabilityInvalid = ~isempty(ppIssues) && any(strcmpi({ppIssues.severity}, 'error'));
                state.preprocAvailabilityMessage = ppIssueMsg;
                state.preprocNeedsReview = logical(state.preprocMixedEarlyFusionIllegal) || ~isempty(ppIssues);
            catch
                state.preprocAvailabilityIssues = obj.preprocAvailabilityIssuePrototype();
                state.preprocAvailabilityIssues = state.preprocAvailabilityIssues([]);
                state.preprocAvailabilityInvalid = false;
                state.preprocAvailabilityMessage = '';
                state.preprocNeedsReview = logical(state.preprocMixedEarlyFusionIllegal);
            end
            try
                [~, n, ns, nc, labs] = obj.preprocSummariesForAll();
                state.preprocStepCounts = n;
                state.preprocSubjectStepCounts = ns;
                state.preprocCVStepCounts = nc;
                state.preprocStepLabelsByModality = labs;
            catch
                state.preprocStepCounts = [];
                state.preprocSubjectStepCounts = [];
                state.preprocCVStepCounts = [];
                state.preprocStepLabelsByModality = {};
            end
            try, state.mlSummary = obj.mlSummaryForActive(); catch, state.mlSummary = ''; end
            try, state.multi = obj.Multi; catch, state.multi = struct(); end
            try, state.rfe = obj.RFE; catch, state.rfe = struct(); end
            try, state.vis = obj.Vis; catch, state.vis = struct(); end
            try, state.mli = obj.MLI; catch, state.mli = struct(); end
            try, state.sav = obj.SAV; catch, state.sav = struct(); end
        end

        function items = auditFusion(obj, state)
            items = {};
            n = obj.NumModalities;
            active = obj.VarIndex;
            if isfield(state,'activeModality'), active = obj.parseScalarIndex(state.activeModality, active); end
            if ~isfinite(active) || active < 1 || active > n
                items{end+1} = obj.auditItem('fusion.active.invalid','fusion','error', ...
                    'Invalid active modality', sprintf('Active modality index %g is outside the available modality range 1..%d.', active, n), ...
                    'fusion','Select a valid active modality.','activeModality');
            else
                items{end+1} = obj.auditItem('fusion.active.ok','fusion','info', ...
                    'Active modality valid', sprintf('Active modality is %d.', active), 'fusion','','activeModality');
            end
            flag = obj.FusionFlag;
            if isfield(state,'fusionFlag'), flag = obj.clampFusionFlag(state.fusionFlag); end
            M = obj.FusionModalities;
            if isfield(state,'fusionModalities'), M = state.fusionModalities; end
            try, M = double(M(:))'; catch, M = []; end
            badM = isempty(M) || any(~isfinite(M)) || any(M < 1) || any(M > n);
            if badM
                items{end+1} = obj.auditItem('fusion.modalities.invalid','fusion','error', ...
                    'Invalid fusion modality set', 'FUSION.M contains missing or out-of-range modality indices.', ...
                    'fusion','Choose valid fusion modalities.','fusionModalities');
            elseif flag > 0 && numel(unique(M)) < 2
                items{end+1} = obj.auditItem('fusion.modalities.tooFew','fusion','warning', ...
                    'Fusion has fewer than two modalities', 'A fusion mode is selected but fewer than two modalities are included.', ...
                    'fusion','Select at least two modalities or disable fusion.','fusionModalities');
            else
                items{end+1} = obj.auditItem('fusion.modalities.ok','fusion','info', ...
                    'Fusion routing available', sprintf('Fusion flag=%d, modalities=%s.', flag, mat2str(M)), 'fusion','','fusionModalities');
            end
            if flag == 1 && ~isempty(M)
                items{end+1} = obj.auditItem('fusion.early.sharedPreproc','fusion','info', ...
                    'Early-fusion preprocessing branch', sprintf('Early fusion stores the shared pipeline in PREPROC{%d}.', M(1)), ...
                    'preproc','','preproc');
            end
            try
                if isfield(state,'preprocMixedEarlyFusionIllegal')
                    badPP = logical(state.preprocMixedEarlyFusionIllegal);
                    badMsg = obj.auditGetChar(state, 'preprocMixedEarlyFusionMessage', ...
                        'Mixed early fusion contains imaging-specific preprocessing steps.');
                    if isfield(state,'preprocMixedEarlyFusionIllegalSteps')
                        badSteps = state.preprocMixedEarlyFusionIllegalSteps;
                    else
                        badSteps = {};
                    end
                else
                    [badPP, badMsg, badSteps] = obj.mixedEarlyFusionPreprocGuard();
                end
                if badPP
                    if isempty(badMsg), badMsg = 'Mixed early fusion contains imaging-specific preprocessing steps.'; end
                    if ~isempty(badSteps)
                        badMsg = sprintf('%s Incompatible step(s): %s.', badMsg, strjoin(cellfun(@char, badSteps(:)', 'UniformOutput', false), ', '));
                    end
                    items{end+1} = obj.auditItem('fusion.mixedEarlyPreproc.warning','preproc','warning', ...
                        'Mixed early-fusion preprocessing needs review', badMsg, ...
                        'preproc','Open preprocessing and remove or replace incompatible imaging-specific steps.','preproc');
                end
            catch
            end
        end

        function items = auditPreproc(obj, state)
            items = {};
            counts = [];
            if isfield(state,'preprocStepCounts'), counts = state.preprocStepCounts; end
            total = 0;
            try, total = sum(double(counts(:))); catch, total = 0; end
            if total == 0
                items{end+1} = obj.auditItem('preproc.none','preproc','info', ...
                    'No preprocessing steps configured', 'The current training template contains no preprocessing steps.', ...
                    'preproc','Open preprocessing if transformations are required.','preproc');
            else
                nSub = 0; nCV = 0;
                try, nSub = sum(double(state.preprocSubjectStepCounts(:))); catch, end
                try, nCV = sum(double(state.preprocCVStepCounts(:))); catch, end
                items{end+1} = obj.auditItem('preproc.count','preproc','info', ...
                    'Preprocessing configured', sprintf('%d preprocessing step(s) configured across modalities (%d subject-specific, %d CV-bound).', total, nSub, nCV), ...
                    'preproc','','preproc');
            end
            if isfield(state,'preprocMixedEarlyFusionIllegal') && logical(state.preprocMixedEarlyFusionIllegal)
                msg = obj.auditGetChar(state, 'preprocMixedEarlyFusionMessage', 'Mixed early-fusion preprocessing contains incompatible steps.');
                items{end+1} = obj.auditItem('preproc.mixedEarlyFusion.illegal','preproc','warning', ...
                    'Incompatible mixed early-fusion preprocessing', msg, 'preproc','Review marked preprocessing cards.','preproc');
            end
            try
                if isfield(state,'preprocAvailabilityIssues') && ~isempty(state.preprocAvailabilityIssues)
                    ppIssues = state.preprocAvailabilityIssues;
                    if isstruct(ppIssues)
                        for jj = 1:numel(ppIssues)
                            sev = 'warning';
                            try
                                if strcmpi(char(string(ppIssues(jj).severity)), 'error'), sev = 'error'; end
                            catch
                            end
                            msg = '';
                            try, msg = char(string(ppIssues(jj).message)); catch, end
                            if isempty(strtrim(msg)), msg = 'A stored preprocessing step is not applicable in the current modality context.'; end
                            target = obj.preprocIssueTarget(ppIssues(jj));
                            items{end+1} = obj.auditItem(sprintf('preproc.availability.%d', jj),'preproc',sev, ...
                                'Preprocessing step currently not applicable', msg, 'preproc', ...
                                'Open preprocessing and review the marked card.', target); %#ok<AGROW>
                        end
                    end
                end
            catch
            end
        end

        function items = auditML(obj, state) %#ok<INUSL>
            items = {};
            msg = '';
            if isfield(state,'mlSummary')
                try, msg = char(string(state.mlSummary)); catch, msg = ''; end
            end
            if isempty(msg)
                try, msg = obj.mlSummaryForActive(); catch, end
            end
            if isempty(msg), msg = 'Machine-learning configuration summary is unavailable.'; end
            items{end+1} = obj.auditItem('ml.summary','ml','info', 'Machine-learning configuration', msg, 'ml','','ml');

            if obj.FusionFlag == 3
                if numel(obj.MLStrat) < obj.VarIndex || isempty(obj.MLStrat{obj.VarIndex}), return; end % nm2-allow: configure may switch fusion context before deferred MLStrat materialization.
                cfg = obj.MLStrat{obj.VarIndex}.MLConfig;
            else
                if isempty(obj.MLGlobal), return; end
                cfg = obj.MLGlobal.MLConfig;
            end
            ctx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
            mod = NMMLModule();
            [~, vrep] = mod.validateConfig(cfg, ctx, false);
            if ~vrep.ok
                errs = vrep.errors;
                if isempty(errs), errs = {'Machine-learning configuration did not pass validation.'}; end
                items{end+1} = obj.auditItem('ml.validation.error','ml','warning', ...
                    'Machine-learning validation warning', strjoin(errs(:)', newline), 'ml','Open machine-learning configuration.','ml');
            end
            if ~isempty(vrep.warnings)
                items{end+1} = obj.auditItem('ml.validation.warning','ml','warning', ...
                    'Machine-learning task compatibility warning', strjoin(vrep.warnings(:)', newline), ...
                    'ml','Open machine-learning configuration.','ml');
            end
        end

        function items = auditMULTI(obj, state)
            items = {};
            multi = obj.Multi;
            if isfield(state,'multi') && isstruct(state.multi), multi = state.multi; end
            flag = false; present = isstruct(multi) && ~isempty(fieldnames(multi));
            try
                if isfield(multi,'multiFlag'), flag = logical(multi.multiFlag); end
                if isfield(multi,'flag'), flag = flag || logical(multi.flag); end
            catch
                flag = false;
            end
            isMulti = false;
            try, isMulti = logical(state.multiAvailable); catch, end
            if ~isMulti && flag
                items{end+1} = obj.auditItem('multi.enabled.inactiveTask','multi','warning', ...
                    'MULTI is enabled outside a multi-class task', 'A MULTI configuration is active although the effective label is binary or regression.', ...
                    'multi','Disable MULTI or switch to a multi-class label.','multi');
            elseif ~isMulti && present
                items{end+1} = obj.auditItem('multi.legacy.inactive','multi','info', ...
                    'Inactive legacy MULTI block present', 'A legacy MULTI struct exists but MULTI.flag is inactive; the backend will not use it.', ...
                    'multi','','multi');
            elseif isMulti
                items{end+1} = obj.auditItem('multi.available','multi','info', 'MULTI availability', 'The effective label is multi-class.', 'multi','','multi');
            else
                items{end+1} = obj.auditItem('multi.unavailable','multi','info', 'MULTI inactive', 'The effective label is not multi-class.', 'multi','','multi');
            end
        end

        function items = auditRFE(obj, state)
            items = {};
            rfe = obj.RFE;
            if isfield(state,'rfe') && isstruct(state.rfe), rfe = state.rfe; end
            txt = 'Filter- and wrapper-based ensemble learning disabled.';
            try, txt = NMRFETools.summary(rfe); catch, end
            items{end+1} = obj.auditItem('rfe.summary','rfe','info','RFE / ensemble-learning configuration', txt, 'rfe','','rfe');
            if obj.isSeqoptStacking() && (rfe.Filter.flag || rfe.Wrapper.flag)
                items{end+1} = obj.auditItem('rfe.seqopt','rfe','error', ...
                    'Ensemble selection is incompatible with sequential optimization', ...
                    'Disable filter and wrapper ensembles before using SEQOPT. The sequence matrix selects prediction sources.', ...
                    'ml','Choose another learner or disable the ensemble settings.','ml'); %#ok<AGROW>
            end
            try
                if isfield(rfe,'rfeWrapperSubspace') && logical(rfe.rfeWrapperSubspace) && ...
                        isfield(rfe,'rfeFilterSubspace') && ~logical(rfe.rfeFilterSubspace)
                    items{end+1} = obj.auditItem('rfe.wrapperSubspace.withoutFilter','rfe','warning', ...
                        'Wrapper subspace without filter subspace', 'Wrapper subspace settings are only meaningful when filter subspace selection is active.', ...
                        'rfe','Enable filter subspace selection or disable wrapper subspace.','rfe');
                end
            catch
            end
        end

        function items = auditVIS(obj, state)
            items = {};
            vis = obj.Vis;
            if isfield(state,'vis') && isstruct(state.vis), vis = state.vis; end
            txt = 'Visualization defaults.';
            try, txt = NMVISTools.summary(vis); catch, end
            items{end+1} = obj.auditItem('vis.summary','vis','info','Visualization configuration', txt, 'vis','','vis');
            needProjection = isfield(vis,'visSigModelSpace') && logical(vis.visSigModelSpace);
            hasProjection = isfield(vis,'visProjectionAvailable') && logical(vis.visProjectionAvailable);
            if needProjection && ~hasProjection
                items{end+1} = obj.auditItem('vis.modelspace.noProjection','vis','warning', ...
                    'Model-space permutation lacks dimensionality-reference preprocessing', ...
                    'Model-space permutation requires dimensionality-reduction/reference preprocessing in the active branch.', ...
                    'vis','Add suitable preprocessing or disable model-space permutation.','vis');
            end
        end

        function items = auditMLI(obj, state)
            items = {};
            mli = obj.MLI;
            if isfield(state,'mli') && isstruct(state.mli), mli = state.mli; end
            txt = 'Interpretable ML parameters are not configured.';
            try, txt = NMMLITools.summary(mli); catch, end
            items{end+1} = obj.auditItem('mli.summary','mli','info','Interpretable ML configuration', txt, 'mli','','mli');
            isImg = obj.activeModalityIsImaging();
            try
                atlasOn = (isfield(mli,'mliAtlasFlag') && logical(mli.mliAtlasFlag)) || (isfield(mli,'atlas_flag') && logical(mli.atlas_flag));
                if atlasOn && ~isImg
                    items{end+1} = obj.auditItem('mli.atlas.nonimaging','mli','warning', ...
                        'Atlas binding on non-imaging modality', 'MLI atlas binding is only meaningful for imaging modalities.', ...
                        'mli','Disable atlas binding or switch to an imaging modality.','mli');
                end
                if isfield(mli,'mliAtlasFile') && ~isempty(mli.mliAtlasFile) && isfield(mli,'mliAtlasImported') && ~logical(mli.mliAtlasImported)
                    items{end+1} = obj.auditItem('mli.atlas.notImported','mli','warning', ...
                        'Atlas file selected but not imported', 'An atlas path is stored, but the atlas vector payload was not imported.', ...
                        'mli','Import the atlas vector in the MLI configurator.','mli');
                end
                if isfield(mli,'mliCsvFile') && ~isempty(mli.mliCsvFile) && isfield(mli,'mliCsvImported') && ~logical(mli.mliCsvImported)
                    items{end+1} = obj.auditItem('mli.descriptor.notImported','mli','warning', ...
                        'Descriptor file selected but not imported', 'A descriptor-table path is stored, but the descriptor payload was not imported.', ...
                        'mli','Import the descriptor table in the MLI configurator.','mli');
                end
            catch
            end
        end

        function items = auditSaving(obj, state)
            items = {};
            sav = obj.SAV;
            if isfield(state,'sav') && isstruct(state.sav), sav = state.sav; end
            txt = 'Saving and verbosity configuration unavailable.';
            try, txt = [NMSAVTools.summarySaving(sav) ' ' NMSAVTools.summaryVerbosity(sav)]; catch, end
            items{end+1} = obj.auditItem('sav.summary','sav','info','Saving / verbosity configuration', txt, 'sav','','sav');
            try
                enabled = false; prefix = '';
                if isfield(sav,'savemodel'), enabled = logical(sav.savemodel); end
                if isfield(sav,'matname'), prefix = char(string(sav.matname)); end
                if isfield(sav,'savMatName'), prefix = char(string(sav.savMatName)); end
                if enabled && isempty(strtrim(prefix))
                    items{end+1} = obj.auditItem('sav.emptyPrefix','sav','warning', ...
                        'Model saving prefix is empty', 'Model saving is enabled, but the output prefix is empty.', ...
                        'sav','Enter a non-empty output prefix.','sav');
                end
            catch
            end
        end

        function s = auditGetChar(obj, st, fieldName, defaultVal) %#ok<INUSL>
            s = defaultVal;
            try
                if isstruct(st) && isfield(st, fieldName) && ~isempty(st.(fieldName))
                    s = char(string(st.(fieldName)));
                end
            catch
                s = defaultVal;
            end
        end

        function item = auditItem(obj, id, scope, severity, title, message, configurator, action, target) %#ok<INUSL>
            if nargin < 8, action = ''; end
            if nargin < 9, target = ''; end
            item = struct('id',char(string(id)), 'scope',char(string(scope)), ...
                'severity',char(string(severity)), 'title',char(string(title)), ...
                'message',char(string(message)), 'configurator',char(string(configurator)), ...
                'action',char(string(action)), 'target',char(string(target)));
        end

        function items = auditEmptyItems(obj) %#ok<MANU>
            items = struct('id',{}, 'scope',{}, 'severity',{}, 'title',{}, ...
                'message',{}, 'configurator',{}, 'action',{}, 'target',{});
        end


        function nodes = canvasEmptyNodes(obj)
            proto = obj.canvasNodePrototype();
            nodes = proto([]);
        end

        function edges = canvasEmptyEdges(obj)
            proto = obj.canvasEdgePrototype();
            edges = proto([]);
        end

        function node = canvasNodePrototype(obj)
            node = struct('id','', 'title','', 'subtitle','', 'status','', ...
                'summary','', 'auditItems',{obj.auditEmptyItems()}, 'configurator','', 'deepLink','', ...
                'children',{{}}, 'type','', 'lane',NaN, 'order',NaN, 'shape','', 'group','', ...
                'columnLabel','', 'stepIndex',NaN, 'accent','', 'row',NaN, ...
                'modalityIndex',NaN, 'stage','', 'moduleId','', 'action','', ...
                'usesLabels',false, 'usesCovariates',false, ...
                'detail',obj.canvasEmptyDetail());
        end

        function edge = canvasEdgePrototype(obj) %#ok<MANU>
            edge = struct('source','', 'target','', 'kind','', 'label','');
        end

        function [nodeCapacity, edgeCapacity] = canvasCapacityHint(obj, state)
            % K3q: reserve a stable canvas struct schema before topology construction.
            % Dynamic struct-array growth is expensive in MATLAB because every
            % end+1 append can trigger field-wise copying.  The hint is deliberately
            % conservative and only falls back to block extension if an unusually
            % large analysis exceeds it.
            try
                nRelevant = max(1, numel(obj.canvasRelevantModalities(state)));
            catch
                nRelevant = max(1, double(obj.NumModalities));
            end
            try
                nSelected = max(0, numel(obj.canvasStackingSelectedAnalyses(state)));
            catch
                nSelected = 0;
            end
            scale = max([nRelevant, nSelected, 1]);
            nodeCapacity = max(64, 32 + 24 * scale);
            edgeCapacity = max(96, 48 + 32 * scale);
        end

        function nodes = canvasPreallocateNodes(obj, capacity)
            capacity = max(1, round(double(capacity)));
            nodes = repmat(obj.canvasNodePrototype(), 1, capacity);
        end

        function edges = canvasPreallocateEdges(obj, capacity)
            capacity = max(1, round(double(capacity)));
            edges = repmat(obj.canvasEdgePrototype(), 1, capacity);
        end

        function nodes = canvasAppendNode(obj, nodes, node)
            idx = 0;
            for ii = 1:numel(nodes)
                if isempty(nodes(ii).id)
                    idx = ii;
                    break;
                end
            end
            if idx == 0
                oldN = numel(nodes);
                growBy = max(16, ceil(max(1, oldN) / 2));
                nodes(oldN + growBy) = obj.canvasNodePrototype();
                idx = oldN + 1;
            end
            nodes(idx) = node;
        end

        function edges = canvasAppendEdge(obj, edges, edge)
            idx = 0;
            for ii = 1:numel(edges)
                if isempty(edges(ii).source) && isempty(edges(ii).target)
                    idx = ii;
                    break;
                end
            end
            if idx == 0
                oldN = numel(edges);
                growBy = max(16, ceil(max(1, oldN) / 2));
                edges(oldN + growBy) = obj.canvasEdgePrototype();
                idx = oldN + 1;
            end
            edges(idx) = edge;
        end

        function nodes = canvasTrimNodes(obj, nodes)
            if isempty(nodes), nodes = obj.canvasEmptyNodes(); return; end
            keep = false(1, numel(nodes));
            for ii = 1:numel(nodes)
                keep(ii) = ~isempty(nodes(ii).id);
            end
            nodes = nodes(keep);
            if isempty(nodes), nodes = obj.canvasEmptyNodes(); end
        end

        function edges = canvasTrimEdges(obj, edges)
            if isempty(edges), edges = obj.canvasEmptyEdges(); return; end
            keep = false(1, numel(edges));
            for ii = 1:numel(edges)
                keep(ii) = ~isempty(edges(ii).source) && ~isempty(edges(ii).target);
            end
            edges = edges(keep);
            if isempty(edges), edges = obj.canvasEmptyEdges(); end
        end

        function tf = canvasLogicalField(obj, state, fieldName, defaultVal) %#ok<INUSL>
            tf = logical(defaultVal);
            try
                if isstruct(state) && isfield(state, fieldName) && ~isempty(state.(fieldName))
                    tf = logical(state.(fieldName));
                end
            catch
                tf = logical(defaultVal);
            end
        end

        function tf = canvasSynthEnabled(obj, state) %#ok<INUSL>
            tf = false;
            try
                if isstruct(state) && isfield(state,'synth') && isstruct(state.synth) && ...
                        isfield(state.synth,'synthEnabled') && ~isempty(state.synth.synthEnabled)
                    tf = logical(state.synth.synthEnabled);
                elseif isstruct(state) && isfield(state,'synthEnabled')
                    tf = logical(state.synthEnabled);
                end
            catch
                tf = false;
            end
        end

        function tf = canvasHasAudit(obj, audit, configurator)
            tf = ~isempty(obj.canvasAuditItems(audit, configurator));
        end

        function tf = canvasShouldShowBlock(obj, state, audit, configurator, summaryField, inactiveToken)
            tf = obj.canvasHasAudit(audit, configurator);
            if tf, return; end
            s = obj.canvasSummary(state, summaryField, '');
            if isempty(s)
                tf = false;
                return;
            end
            if nargin < 6 || isempty(inactiveToken)
                tf = true;
            else
                tf = isempty(regexpi(s, inactiveToken, 'once'));
            end
        end

        function tf = canvasRFEActive(obj, state)
            tf = false;
            rfe = [];
            if nargin >= 2 && isstruct(state) && isfield(state,'rfe') && isstruct(state.rfe)
                rfe = state.rfe;
            elseif isstruct(obj.RFE)
                rfe = obj.RFE;
            end
            if ~isstruct(rfe), return; end
            try
                if isfield(rfe,'Filter') && isstruct(rfe.Filter) && isfield(rfe.Filter,'flag') && double(rfe.Filter.flag) == 1
                    tf = true;
                    return;
                end
            catch
                tf = false;
            end
            try
                if isfield(rfe,'Wrapper') && isstruct(rfe.Wrapper)
                    W = rfe.Wrapper;
                    if isfield(W,'flag') && double(W.flag) == 1
                        tf = true;
                        return;
                    end
                    if isfield(W,'flag') && isfield(W,'optflag') && double(W.flag) == 0 && double(W.optflag) == 1
                        tf = true;
                    end
                end
            catch
                tf = false;
            end
        end

        function value = canvasValueFromVarargin(obj, args, key, defaultValue) %#ok<INUSL>
            value = defaultValue;
            if isempty(args), return; end
            key = lower(char(string(key)));
            for ii = 1:2:numel(args)
                try
                    if strcmp(lower(char(string(args{ii}))), key)
                        value = args{ii+1};
                        return;
                    end
                catch
                end
            end
        end

        function s = canvasRFESubtitle(obj, state) %#ok<INUSL>
            rfe = struct();
            if nargin >= 2 && isstruct(state) && isfield(state,'rfe') && isstruct(state.rfe)
                rfe = state.rfe;
            end
            filterActive = false;
            wrapperActive = false;
            try, filterActive = isfield(rfe,'Filter') && isstruct(rfe.Filter) && isfield(rfe.Filter,'flag') && double(rfe.Filter.flag) == 1; catch, end
            try
                if isfield(rfe,'Wrapper') && isstruct(rfe.Wrapper)
                    W = rfe.Wrapper;
                    wrapperActive = (isfield(W,'flag') && double(W.flag) == 1) || ...
                        (isfield(W,'flag') && isfield(W,'optflag') && double(W.flag) == 0 && double(W.optflag) == 1);
                end
            catch
            end
            if filterActive && wrapperActive
                s = 'Filter and wrapper active';
            elseif filterActive
                s = 'Filter active';
            elseif wrapperActive
                s = 'Wrapper active';
            else
                s = 'Ensemble learning active';
            end
        end

        function M = canvasRelevantModalities(obj, state)
            % Return only modalities relevant to the current analysis context.
            % Do not enumerate every NM modality; that makes the canvas noisy.
            flag = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            active = obj.canvasGetScalar(state,'activeModality',obj.VarIndex);
            M = active;
            if flag > 0
                try
                    if isfield(state,'fusionModalities') && ~isempty(state.fusionModalities)
                        M = double(state.fusionModalities(:))';
                    else
                        M = double(obj.FusionModalities(:))';
                    end
                catch
                    M = active;
                end
            end
            M = round(M(:)');
            M = M(isfinite(M) & M >= 1 & M <= max(1,obj.NumModalities));
            if isempty(M), M = max(1,min(obj.NumModalities,active)); end
            M = unique(M,'stable');
            if flag == 0 && ~isempty(M)
                M = M(1);
            end
        end

        function label = canvasModalityLabel(obj, idx)
            label = sprintf('Modality %d', idx);
            try
                if idx >= 1 && idx <= numel(obj.ModalityLabels) && ~isempty(obj.ModalityLabels{idx})
                    label = char(string(obj.ModalityLabels{idx}));
                end
            catch
                label = sprintf('Modality %d', idx);
            end
        end

        function pp = canvasPreprocForModality(obj, idx)
            pp = [];
            try
                if idx >= 1 && idx <= numel(obj.Preproc)
                    pp = obj.Preproc{idx};
                end
            catch
                pp = [];
            end
        end

        function scope = canvasPreprocScopeForModality(obj, idx, fusionFlag)
            if nargin < 3, fusionFlag = obj.FusionFlag; end
            if fusionFlag == 3
                scope = sprintf('STRAT{%d}.PREPROC', idx);
            elseif fusionFlag == 1
                scope = sprintf('early-fusion PREPROC{%d}', idx);
            elseif fusionFlag == 2
                scope = sprintf('intermediate-fusion PREPROC{%d}', idx);
            else
                scope = sprintf('PREPROC{%d}', idx);
            end
        end

        function steps = canvasPreprocStepSpecs(obj, pp, idx, scope)
            empty = struct('id',{}, 'title',{}, 'subtitle',{}, 'summary',{}, 'stage',{}, 'moduleId',{}, 'order',{});
            if isempty(pp), steps = empty; return; end
            try
                subjectSteps = obj.sequenceStepsFromPreprocObject(pp, 'subject');
                cvSteps = obj.sequenceStepsFromPreprocObject(pp, 'cv');
                n = numel(subjectSteps) + numel(cvSteps);
                if n == 0, steps = empty; return; end
                buf = cell(1, n);
                k = 0;
                for jj = 1:numel(subjectSteps)
                    k = k + 1;
                    buf{k} = obj.canvasPreprocStepSpec(subjectSteps{jj}, idx, scope, 'subject', k);
                end
                for jj = 1:numel(cvSteps)
                    k = k + 1;
                    buf{k} = obj.canvasPreprocStepSpec(cvSteps{jj}, idx, scope, 'cv', k);
                end
                steps = [buf{:}];
            catch
                steps = empty;
            end
        end

        function spec = canvasPreprocStepSpec(obj, st, idx, scope, stage, order) %#ok<INUSL>
            moduleId = obj.preprocStepLabel(st, stage);
            title = obj.canvasPreprocModuleTitle(moduleId);
            subtitle = sprintf('%s · %s', scope, upper(stage));
            summary = obj.canvasBriefStructSummary(st.config, moduleId);
            if strcmp(st.moduleId, 'correctnuis')
                cfg = st.config;
                mcfg = cfg.methodConfig;
                names = obj.NM.covnames;
                switch cfg.method
                    case 'combat'
                        batch = 'none';
                        if mcfg.useBatch, batch = strjoin(names(mcfg.batchCovariate), ', '); end
                        additional = 'none';
                        if mcfg.includeCovariates && ~isempty(mcfg.covariates)
                            additional = strjoin(names(mcfg.covariates), ', ');
                        end
                        summary = sprintf('ComBat batch: %s; additional covariates: %s', batch, additional);
                    case 'partial'
                        summary = sprintf('Partial correlation covariates: %s', strjoin(names(mcfg.covariates), ', '));
                    case 'dir'
                        summary = sprintf('Disparate-impact covariates: %s', strjoin(names(mcfg.categoricalCovariates), ', '));
                end
            end
            safeMod = regexprep(lower(char(string(moduleId))), '[^a-z0-9]+', '_');
            if isempty(safeMod), safeMod = 'step'; end
            [usesLabels, usesCovariates] = obj.canvasPreprocStepDataUsage(st);
            spec = struct('id',sprintf('preproc_m%d_%02d_%s', idx, order, safeMod), ...
                'title',title, 'subtitle',subtitle, 'summary',summary, 'stage',stage, ...
                'moduleId',char(string(moduleId)), 'order',double(order), ...
                'usesLabels',logical(usesLabels), 'usesCovariates',logical(usesCovariates));
        end


        function mode = canvasDetailModeFromOpts(obj, opts) %#ok<INUSL>
            mode = 'summary';
            try
                if isstruct(opts)
                    if isfield(opts,'canvasDetailMode') && ~isempty(opts.canvasDetailMode)
                        mode = lower(char(string(opts.canvasDetailMode)));
                    elseif isfield(opts,'detailMode') && ~isempty(opts.detailMode)
                        mode = lower(char(string(opts.detailMode)));
                    end
                end
            catch
                mode = 'summary';
            end
            if ~any(strcmp(mode, {'summary','rich','none'}))
                mode = 'summary';
            end
        end

        function nodes = canvasAttachNodeDetails(obj, nodes, state, audit, mode)
            % K3r: default canvas refreshes attach only lightweight summaries.
            % Rich inspector details call module configSpec()/visibleUIFields()
            % and were the dominant canvas cost; they are now generated only on
            % demand, or when mode == 'rich'.
            if nargin < 5 || isempty(mode), mode = 'summary'; end
            mode = lower(char(string(mode)));
            for ii = 1:numel(nodes)
                try
                    if strcmp(mode,'rich')
                        nodes(ii).detail = obj.canvasDetailForNode(nodes(ii), state, audit);
                    elseif strcmp(mode,'none')
                        nodes(ii).detail = obj.canvasEmptyDetail();
                    else
                        nodes(ii).detail = obj.canvasLightweightDetailForNode(nodes(ii), audit);
                    end
                catch ME
                    nodes(ii).detail = obj.canvasMakeDetail(nodes(ii).title, nodes(ii).subtitle, ...
                        {obj.canvasDetailSection('Configuration', {obj.canvasCleanSentence(nodes(ii).summary)})}, ...
                        obj.canvasActionHint(nodes(ii)));
                    try, nodes(ii).detail.debugError = ME.message; catch, end
                    try, nodes(ii).detail.lazy = true; nodes(ii).detail.mode = 'summary'; catch, end
                end
            end
        end

        function detail = canvasLightweightDetailForNode(obj, node, audit)
            typ = '';
            if isstruct(node) && isfield(node,'type') && ~isempty(node.type)
                typ = lower(char(string(node.type)));
            end
            if any(strcmp(typ, {'modality','input'}))
                detail = obj.canvasDetailForInputNode(node, struct());
                if isstruct(detail)
                    detail.lazy = false;
                    detail.mode = 'summary';
                end
            else
                lines = obj.canvasGenericSummaryLines(node.summary);
                if isempty(lines), lines = {char(string(node.title))}; end
                detail = obj.canvasMakeDetail(node.title, node.subtitle, ...
                    {obj.canvasDetailSection('Configuration', lines)}, obj.canvasActionHint(node));
                detail.lazy = true;
                detail.mode = 'summary';
            end
            warn = obj.canvasReviewLinesForNode(node, audit);
            if ~isempty(warn), detail.warnings = warn; end
        end

        function detail = canvasEmptyDetail(obj) %#ok<MANU>
            detail = struct('title','','subtitle','','sections',struct('heading',{},'lines',{}), ...
                'warnings',{{}}, 'action','');
        end

        function detail = canvasMakeDetail(obj, title, subtitle, sections, action) %#ok<INUSL>
            if nargin < 5, action = ''; end
            if isempty(sections), sections = struct('heading',{},'lines',{}); end
            if iscell(sections), sections = [sections{:}]; end
            detail = struct('title',char(string(title)), 'subtitle',char(string(subtitle)), ...
                'sections',sections, 'warnings',{{}}, 'action',char(string(action)));
        end

        function sec = canvasDetailSection(obj, heading, lines) %#ok<INUSL>
            if nargin < 3 || isempty(lines), lines = {}; end
            if ischar(lines) || isstring(lines), lines = cellstr(string(lines)); end
            sec = struct('heading',char(string(heading)), 'lines',{cellfun(@(x) char(string(x)), lines(:)', 'UniformOutput', false)});
        end

        function detail = canvasDetailForNode(obj, node, state, audit)
            typ = lower(char(string(node.type)));
            cfg = lower(char(string(node.configurator)));
            switch typ
                case 'partition_scope'
                    detail = obj.canvasDetailForCVScope(node, state);
                case 'preproc_step'
                    detail = obj.canvasDetailForPreprocNode(node, audit);
                case {'learner','meta_learner'}
                    detail = obj.canvasDetailForMLNode(node, state);
                case 'model_selection'
                    detail = obj.canvasDetailForEnsembleNode(node);
                case 'output'
                    if strcmp(cfg,'mli')
                        detail = obj.canvasDetailForMLINode(node);
                    else
                        detail = obj.canvasDetailForVISNode(node);
                    end
                case {'modality','input'}
                    detail = obj.canvasDetailForInputNode(node, state);
                case 'stacking_input'
                    detail = obj.canvasDetailForStackingInput(node);
                case 'fusion'
                    detail = obj.canvasDetailForFusionNode(node, state);
                otherwise
                    detail = obj.canvasMakeDetail(node.title, node.subtitle, ...
                        {obj.canvasDetailSection('Configuration', obj.canvasGenericSummaryLines(node.summary))}, ...
                        obj.canvasActionHint(node));
            end
            warn = obj.canvasReviewLinesForNode(node, audit);
            if ~isempty(warn), detail.warnings = warn; end
        end

        function detail = canvasDetailForPreprocNode(obj, node, audit)
            [cfg, module, spec, ok] = obj.canvasPreprocConfigForNode(node); %#ok<ASGLU>
            subtitle = obj.canvasPreprocContextLine(node);
            if ok
                lines = obj.canvasPreprocConfigLinesForModule(char(string(node.moduleId)), cfg, spec);
            else
                lines = {};
            end
            if isempty(lines)
                lines = obj.canvasGenericSummaryLines(node.summary);
            end
            sectionTitle = obj.canvasPreprocConfigHeading(node);
            detail = obj.canvasMakeDetail(node.title, subtitle, ...
                {obj.canvasDetailSection(sectionTitle, lines)}, obj.canvasActionHint(node));
        end

        function heading = canvasPreprocConfigHeading(obj, node) %#ok<INUSL>
            stage = lower(char(string(node.stage)));
            if strcmp(stage,'subject')
                scope = 'subject-level';
            else
                scope = 'CV-bound';
            end
            idx = double(node.modalityIndex);
            if isfinite(idx) && idx > 0
                heading = sprintf('Configuration — %s, modality %d', scope, round(idx));
            else
                heading = sprintf('Configuration — %s stacking preprocessing', scope);
            end
        end

        function txt = canvasPreprocContextLine(obj, node) %#ok<INUSL>
            idx = double(node.modalityIndex);
            stage = lower(char(string(node.stage)));
            if strcmp(stage,'subject')
                st = 'Subject-level';
            else
                st = 'CV-bound';
            end
            if isfinite(idx) && idx > 0
                txt = sprintf('PREPROC{%d} · %s · step %d', round(idx), st, round(double(node.stepIndex)));
            else
                txt = sprintf('STACKING.PREPROC · %s · step %d', st, round(double(node.stepIndex)));
            end
        end

        function [cfg, module, spec, ok] = canvasPreprocConfigForNode(obj, node)
            cfg = struct(); module = []; spec = struct(); ok = false;
            try
                idx = double(node.modalityIndex);
                if ~isfinite(idx) || idx <= 0
                    pp = obj.StackingPreproc;
                else
                    pp = obj.canvasPreprocForModality(round(idx));
                end
                if isempty(pp), return; end
                st = obj.canvasPreprocStepFromOrchestrator(pp, node);
                if isempty(st) || ~isstruct(st), return; end
                cfg = st.config;
                seq = obj.canvasSequenceForPreprocNode(pp, node.stage);
                module = seq.Registry.get(st.moduleId);
                spec = obj.canvasModuleConfigSpec(module, seq.Context);
                ok = true;
            catch
                ok = false;
            end
        end

        function seq = canvasSequenceForPreprocNode(obj, pp, stage) %#ok<INUSL>
            st = lower(char(string(stage)));
            if strcmp(st,'subject')
                seq = pp.SubjectSequence;
            else
                seq = pp.CVSequence;
            end
        end

        function spec = canvasModuleConfigSpec(obj, module, ctx) %#ok<INUSL>
            % Robust accessor for module config schemas.  In current modules
            % configSpec is implemented as a method, but this helper keeps the
            % canvas inspector tolerant to future dependent-property variants.
            spec = struct();
            try
                if nargin < 3 || isempty(ctx), ctx = struct(); end
                if ismethod(module, 'configSpec')
                    try
                        spec = module.configSpec(ctx);
                    catch
                        try
                            spec = module.configSpec();
                        catch
                            spec = struct();
                        end
                    end
                elseif isprop(module, 'configSpec')
                    spec = module.configSpec;
                end
            catch
                spec = struct();
            end
        end

        function st = canvasPreprocStepFromOrchestrator(obj, pp, node) %#ok<INUSL>
            % Use the canonical MATLAB-side sequence directly.  The canvas
            % inspector must not depend on browser summary text and must not
            % materialize legacy PREPROC.  node.stepIndex is the visible
            % position in the displayed subject+CV chain, so CV indices are
            % offset by the number of subject-level steps.
            st = [];
            try
                targetOrder = round(double(node.stepIndex));
                targetStage = lower(char(string(node.stage)));
                subjectSteps = pp.SubjectSequence.Steps;
                cvSteps = pp.CVSequence.Steps;
                if ~iscell(subjectSteps), subjectSteps = num2cell(subjectSteps); end
                if ~iscell(cvSteps), cvSteps = num2cell(cvSteps); end
                if strcmp(targetStage,'subject')
                    if targetOrder >= 1 && targetOrder <= numel(subjectSteps)
                        st = subjectSteps{targetOrder};
                    end
                    return;
                end
                if strcmp(targetStage,'cv')
                    localIdx = targetOrder - numel(subjectSteps);
                    if localIdx >= 1 && localIdx <= numel(cvSteps)
                        st = cvSteps{localIdx};
                        return;
                    end
                    % Defensive fallback for nodes generated from older
                    % builds that used a stage-local step index.
                    if targetOrder >= 1 && targetOrder <= numel(cvSteps)
                        st = cvSteps{targetOrder};
                    end
                end
            catch
                st = [];
            end
        end

        function lines = canvasPreprocConfigLinesForModule(obj, moduleId, cfg, spec)
            m = lower(char(string(moduleId)));
            switch m
                case 'smoothing'
                    lines = obj.canvasLinesFromNames(cfg, spec, {'fwhm'}, {'Kernel/FWHM'}, {'mm'});
                    lines = [{'Operation: spatial smoothing'}, lines];
                case 'extdim'
                    lines = obj.canvasExtDimLines(cfg, spec);
                case 'reducedim'
                    lines = obj.canvasLinesFromNames(cfg, spec, {'method','fitDim','percMode','templateProcrustes','useAllTrainingForTemplate'}, ...
                        {'Method','Fitted projection dimensionality','Fitted dimensionality mode','Procrustes template alignment','Use all training data for template generation'}, {'','','','',''});
                    lines = [{'Operation: dimensionality reduction'}, lines];
                case 'standardize'
                    lines = obj.canvasLinesFromNames(cfg, spec, {'method','useIQR','winsorizeSD','zeroOutNonFinite','sourceIndex','destinationIndex'}, ...
                        {'Estimator','IQR scaling','Winsorization limits','Non-finite features','Source covariates','Destination covariates'}, {'','',' SD','','',''});
                    lines = [{'Operation: standardization'}, lines];
                case 'scale'
                    lines = obj.canvasLinesFromNames(cfg, spec, {'range','acrossMatrix','zeroOutNonFinite'}, ...
                        {'Scaling range','Scale across whole matrix','Non-finite values'}, {'','',''});
                    lines = [{'Operation: scaling'}, lines];
                case 'impute'
                    lines = obj.canvasImputeLines(cfg, spec);
                case 'rankfeat'
                    lines = obj.canvasRankFeatLines(cfg, spec);
                case 'extfeat'
                    lines = obj.canvasExtFeatLines(cfg, spec);
                case 'remvarcomp'
                    lines = obj.canvasRemVarCompLines(cfg, spec);
                otherwise
                    op = obj.canvasPreprocModuleTitle(moduleId);
                    lines = obj.canvasGenericConfigSpecLines(cfg, spec);
                    lines = [{sprintf('Operation: %s', lower(op))}, lines];
            end
            lines = obj.canvasCleanConfigLines(lines);
        end

        function lines = canvasExtDimLines(obj, cfg, spec)
            mode = lower(obj.canvasCfgString(cfg,'scheduleMode','user'));
            lines = obj.canvasLinesFromNames(cfg, spec, {'redMode','percMode','scheduleMode'}, ...
                {'Parent reduction method','Extraction mode','Extraction schedule'}, {'','',''});
            switch mode
                case 'user'
                    lines = [lines, obj.canvasLinesFromNames(cfg, spec, {'dims'}, {'Extracted dimensionalities'}, {''})];
                case 'geometric'
                    lines = [lines, obj.canvasLinesFromNames(cfg, spec, {'geoMin','geoMax','geoN'}, {'Geometric minimum','Geometric maximum','Geometric values'}, {'','',''})];
                case 'power'
                    lines = [lines, obj.canvasLinesFromNames(cfg, spec, {'powerMin','powerMax','powerN','powerAlpha'}, {'Power-law minimum','Power-law maximum','Power-law values','Power-law alpha'}, {'','','',''})];
                otherwise
                    lines = [lines, obj.canvasLinesFromNames(cfg, spec, {'rangeMin','rangeMax','rangeN'}, {'Schedule minimum','Schedule maximum','Number of scheduled values'}, {'','',''})];
            end
            lines = [{'Operation: extract dimensions'}, lines];
        end

        function lines = canvasImputeLines(obj, cfg, spec)
            method = lower(obj.canvasCfgString(cfg,'method',''));
            names = {'method','featureScope'};
            labels = {'Imputation method','Features to impute'};
            units = {'',''};
            if contains(method,'knn') || contains(method,'euclidean') || contains(method,'cityblock') || contains(method,'cosine') || contains(method,'seuclidean')
                names{end+1} = 'k'; labels{end+1} = 'Nearest neighbours'; units{end+1} = '';
            end
            if strcmp(method,'hybrid')
                names = [names {'hybridNominalMethod','hybridContinuousMethod','hybridCutoff'}];
                labels = [labels {'Hybrid nominal method','Hybrid continuous method','Nominal-value cutoff'}];
                units = [units {'','',''}];
            end
            lines = [{'Operation: imputation'}, obj.canvasLinesFromNames(cfg, spec, names, labels, units)];
        end

        function lines = canvasRankFeatLines(obj, cfg, spec)
            alg = lower(obj.canvasCfgString(cfg,'algorithm',''));
            names = {'algorithm','weightMethod','labelSource','rankType'};
            labels = {'Ranking algorithm','Ranking action','Ranking target source','Task induced by custom target'};
            units = {'','','',''};
            if startsWith(alg,'extern') || strcmp(alg,'extern') || strcmp(alg,'extern2')
                names = [names {'externalSource','externalWorkspaceVar','externalFile','externalNMWeightIndex','takeAbs','scaleWeights'}];
                labels = [labels {'External ranking source','Workspace variable','External ranking file','NM weighting image index','Use absolute weights','Scale weights to [0,1]'}];
                units = [units {'','','','','',''}];
            end
            lines = [{'Operation: feature ranking'}, obj.canvasLinesFromNames(cfg, spec, names, labels, units)];
        end

        function lines = canvasExtFeatLines(obj, cfg, spec)
            action = lower(obj.canvasCfgString(cfg,'action','soft_weight'));
            names = {'action'}; labels = {'Ranking action'}; units = {''};
            switch action
                case 'soft_weight'
                    names{end+1} = 'exponent'; labels{end+1} = 'Soft-weighting exponent'; units{end+1} = '';
                case 'percentile_threshold'
                    names{end+1} = 'percentiles'; labels{end+1} = 'Percentile thresholds'; units{end+1} = '%';
                case 'absolute_threshold'
                    names{end+1} = 'absoluteThresholds'; labels{end+1} = 'Absolute thresholds'; units{end+1} = '';
                case 'top_features'
                    names{end+1} = 'topFeatures'; labels{end+1} = 'Top feature counts'; units{end+1} = '';
                case 'operator_cutoff'
                    names = [names {'operator','cutoff'}]; labels = [labels {'Operator','Cutoff'}]; units = [units {'',''}];
            end
            if isfield(cfg,'clusterize')
                names{end+1} = 'clusterize'; labels{end+1} = 'Clusterize suprathreshold imaging features'; units{end+1} = '';
            end
            lines = [{'Operation: apply feature-ranking action'}, obj.canvasLinesFromNames(cfg, spec, names, labels, units)];
        end

        function lines = canvasRemVarCompLines(obj, cfg, spec)
            names = {'reductionMethod','targetSource','targetWorkspaceVar','covariateColumns','correlationMethod','criterion','correlationThreshold','operator','backProject','subgroupMode','subgroupPercent','dimensionMode','fitDim'};
            labels = {'Reduction method','Nuisance target source','Workspace nuisance target','NM.covars target columns','Association metric','Component-identification metric','Metric cutoff','Extraction operator','Back-projection to input space','Projection training data','Random subset percentage','Projection dimensionality mode','Projection dimensionality/variance retention'};
            units = {'','','','','','','','','','','%','',''};
            lines = [{'Operation: remove variance components'}, obj.canvasLinesFromNames(cfg, spec, names, labels, units)];
        end

        function lines = canvasLinesFromNames(obj, cfg, spec, names, labels, units)
            lines = {};
            for ii = 1:numel(names)
                name = names{ii};
                if ~isstruct(cfg) || ~isfield(cfg, name), continue; end
                val = cfg.(name);
                if ~obj.canvasValueIsDisplayable(val), continue; end
                fs = obj.canvasFieldSpecByName(spec, name);
                lab = labels{ii};
                if isempty(lab) && isstruct(fs) && isfield(fs,'label'), lab = char(string(fs.label)); end
                unit = '';
                if nargin >= 6 && numel(units) >= ii, unit = units{ii}; end
                txt = obj.canvasFormatConfigValue(lab, val, fs, unit);
                if ~isempty(txt), lines{end+1} = txt; end %#ok<AGROW>
            end
        end

        function lines = canvasGenericConfigSpecLines(obj, cfg, spec)
            lines = {};
            if ~isstruct(cfg) || ~isstruct(spec) || ~isfield(spec,'fields'), return; end
            fields = spec.fields;
            for ii = 1:numel(fields)
                fs = fields{ii};
                if ~isstruct(fs) || ~isfield(fs,'name'), continue; end
                if obj.canvasFieldIsHidden(fs), continue; end
                name = char(string(fs.name));
                if ~isfield(cfg, name), continue; end
                val = cfg.(name);
                if ~obj.canvasValueIsDisplayable(val), continue; end
                txt = obj.canvasFormatConfigValue(obj.canvasFieldLabel(fs), val, fs, '');
                if ~isempty(txt), lines{end+1} = txt; end %#ok<AGROW>
                if numel(lines) >= 8, break; end
            end
        end

        function fs = canvasFieldSpecByName(obj, spec, name) %#ok<INUSL>
            fs = struct();
            try
                if isstruct(spec) && isfield(spec,'fields')
                    for ii = 1:numel(spec.fields)
                        f = spec.fields{ii};
                        if isstruct(f) && isfield(f,'name') && strcmp(char(string(f.name)), char(string(name)))
                            fs = f; return;
                        end
                    end
                end
            catch
            end
        end

        function tf = canvasFieldIsHidden(obj, fs) %#ok<INUSL>
            tf = false;
            try
                if isfield(fs,'uiHidden') && logical(fs.uiHidden), tf = true; end
            catch
                tf = false;
            end
        end

        function lab = canvasFieldLabel(obj, fs) %#ok<INUSL>
            lab = '';
            try
                if isfield(fs,'label') && ~isempty(fs.label), lab = char(string(fs.label)); end
            catch
            end
            if isempty(lab) && isfield(fs,'name'), lab = char(string(fs.name)); end
        end

        function txt = canvasFormatConfigValue(obj, label, val, fs, unit)
            txt = '';
            if nargin < 5, unit = ''; end
            label = char(string(label));
            try
                typ = '';
                if isstruct(fs) && isfield(fs,'type'), typ = lower(char(string(fs.type))); end
                if strcmp(typ,'enum')
                    txt = sprintf('%s: %s', label, obj.canvasFormatEnumValue(val, fs));
                elseif strcmp(typ,'boolean')
                    txt = sprintf('%s: %s', label, obj.canvasFormatBoolean(val));
                elseif isnumeric(val) || islogical(val)
                    txt = sprintf('%s: %s', label, obj.canvasFormatCandidateVector(val, unit));
                elseif ischar(val) || isstring(val)
                    txt = sprintf('%s: %s', label, obj.canvasHumanValue(char(string(val))));
                elseif iscell(val)
                    txt = sprintf('%s: %s', label, obj.canvasCellValueText(val));
                elseif isstruct(val)
                    txt = sprintf('%s: configured', label);
                end
            catch
                txt = '';
            end
        end

        function txt = canvasFormatEnumValue(obj, val, fs)
            txt = '';
            try
                if isstruct(fs) && isfield(fs,'values') && ~isempty(fs.values)
                    vals = fs.values;
                    if isstruct(vals), vals = num2cell(vals); end
                    for ii = 1:numel(vals)
                        it = vals{ii};
                        if ~isstruct(it) || ~isfield(it,'value'), continue; end
                        if obj.mlValueEquals(val, it.value)
                            if isfield(it,'label') && ~isempty(it.label)
                                txt = char(string(it.label));
                            else
                                txt = char(string(it.value));
                            end
                            return;
                        end
                    end
                end
            catch
                txt = '';
            end
            if isempty(txt)
                if isnumeric(val) || islogical(val)
                    txt = obj.canvasFormatCandidateVector(val, '');
                else
                    txt = obj.canvasHumanValue(char(string(val)));
                end
            end
        end

        function txt = canvasFormatBoolean(obj, val) %#ok<INUSL>
            try
                tf = logical(val);
                if tf, txt = 'enabled'; else, txt = 'disabled'; end
            catch
                txt = char(string(val));
            end
        end

        function txt = canvasFormatCandidateVector(obj, val, unit)
            if nargin < 3, unit = ''; end
            unit = char(string(unit));
            try
                v = double(val(:));
                v = v(isfinite(v));
                if isempty(v), txt = ''; return; end
                u = unique(v(:))';
                n = numel(u);
                if n <= 3
                    txt = strjoin(arrayfun(@(x) obj.canvasNumberText(x), u, 'UniformOutput', false), ', ');
                    if ~isempty(unit), txt = [txt ' ' strtrim(unit)]; end
                else
                    mn = min(u); mx = max(u);
                    if ~isempty(unit)
                        txt = sprintf('%d candidates (min: %s %s, max: %s %s)', n, obj.canvasNumberText(mn), strtrim(unit), obj.canvasNumberText(mx), strtrim(unit));
                    else
                        txt = sprintf('%d candidates (min: %s, max: %s)', n, obj.canvasNumberText(mn), obj.canvasNumberText(mx));
                    end
                end
            catch
                txt = mat2str(val);
            end
        end

        function txt = canvasNumberText(obj, x) %#ok<INUSL>
            txt = sprintf('%.6g', double(x));
        end

        function txt = canvasCellValueText(obj, val) %#ok<INUSL>
            try
                c = cellfun(@(x) char(string(x)), val(:)', 'UniformOutput', false);
                txt = strjoin(c, ', ');
            catch
                txt = sprintf('%d entries', numel(val));
            end
        end

        function txt = canvasHumanValue(obj, txt) %#ok<INUSL>
            txt = char(string(txt));
            txt = strrep(txt, '_', ' ');
            txt = regexprep(txt, '\s+', ' ');
            txt = strtrim(txt);
        end

        function tf = canvasValueIsDisplayable(obj, val) %#ok<INUSL>
            tf = true;
            try
                if isempty(val), tf = false; return; end
                if ischar(val) || isstring(val)
                    tf = ~isempty(strtrim(char(string(val)))); return;
                end
                if isstruct(val)
                    tf = ~isempty(fieldnames(val)); return;
                end
            catch
                tf = false;
            end
        end

        function s = canvasCfgString(obj, cfg, name, default) %#ok<INUSL>
            if nargin < 4, default = ''; end
            s = default;
            try
                if isstruct(cfg) && isfield(cfg,name) && ~isempty(cfg.(name))
                    s = char(string(cfg.(name)));
                end
            catch
                s = default;
            end
        end

        function lines = canvasCleanConfigLines(obj, lines) %#ok<INUSL>
            if isempty(lines), lines = {}; return; end
            if ischar(lines) || isstring(lines), lines = cellstr(string(lines)); end
            out = {};
            seen = containers.Map('KeyType','char','ValueType','logical');
            for ii = 1:numel(lines)
                t = strtrim(char(string(lines{ii})));
                if isempty(t), continue; end
                key = lower(regexprep(t,'\s+',' '));
                if ~isKey(seen,key)
                    out{end+1} = t; seen(key) = true; %#ok<AGROW>
                end
            end
            lines = out;
        end

        function lines = canvasGenericSummaryLines(obj, summary) %#ok<INUSL>
            txt = strtrim(char(string(summary)));
            if isempty(txt), lines = {}; else, lines = {txt}; end
        end

        function txt = canvasCleanSentence(obj, txt) %#ok<INUSL>
            txt = strtrim(char(string(txt)));
            txt = regexprep(txt,'\s+',' ');
        end

        function detail = canvasDetailForMLNode(obj, node, state)
            [cfg, role] = obj.methodsActiveMLConfig(state);
            title = 'Machine learning';
            try
                if isstruct(cfg) && isfield(cfg,'algorithm') && ~isempty(cfg.algorithm)
                    title = NMLearnerLibrary.title(char(string(cfg.algorithm)));
                end
            catch
                try, title = char(string(cfg.algorithm)); catch, end
            end
            if strcmpi(node.type,'meta_learner'), sub = 'Second-tier learner'; else, sub = 'Learner'; end

            sections = {};
            lines = {sprintf('Learner: %s', title), sprintf('Scope: %s', obj.canvasCleanSentence(role))};
            sections{end+1} = obj.canvasDetailSection('Configuration', lines); %#ok<AGROW>

            critLines = obj.canvasMLSectionLines(cfg, 'criterion', 3);
            if ~isempty(critLines)
                sections{end+1} = obj.canvasDetailSection('Optimization criterion', critLines); %#ok<AGROW>
            end

            hp = obj.canvasMLHyperparameterLines(cfg);
            if ~isempty(hp)
                sections{end+1} = obj.canvasDetailSection('Hyperparameter optimization', hp); %#ok<AGROW>
            end

            if strcmp(cfg.algorithm,'SEQOPT')
                % The same stacking-source catalogue supplies the ML editor
                % and the canvas: sequence indices never denote NM analyses.
                C = cfg.fixedSettings.C;
                lengths = sum(isfinite(C),2);
                activeRows = find(lengths > 0);
                sources = obj.sequenceSourceCatalog('ml_global');
                if isempty(activeRows)
                    seqLines = {'No prediction sequences configured.'};
                else
                    seqLines = {sprintf('%d candidate sequences, %d–%d examinations', ...
                        numel(activeRows),min(lengths(activeRows)),max(lengths(activeRows)))};
                    showCount = min(24,numel(activeRows));
                    for q = 1:showCount
                        r = activeRows(q);
                        nodes = C(r,isfinite(C(r,:)));
                        if isempty(sources)
                            labels = arrayfun(@(n) sprintf('source %d',n), nodes, 'UniformOutput',false);
                        else
                            if any(nodes < 1 | nodes > numel(sources) | nodes ~= fix(nodes))
                                error('NMTrainTemplateOrchestrator:sequenceSourceAxis', ...
                                    'Sequence %d references a prediction source outside the selected stacking analyses.',r);
                            end
                            chosen = sources(nodes);
                            labels = arrayfun(@(t) sprintf('#%d',t.analysis),chosen,'UniformOutput',false);
                            for v = 1:numel(chosen)
                                if chosen(v).parts > 1
                                    labels{v} = sprintf('#%d.%d',chosen(v).analysis,chosen(v).part);
                                end
                            end
                        end
                        seqLines{end+1} = sprintf('S%d: %s',r,strjoin(labels,' → ')); %#ok<AGROW>
                    end
                    if numel(activeRows) > showCount
                        seqLines{end+1} = sprintf('Showing %d of %d sequences. Open the sequence builder to inspect all.', ...
                            showCount,numel(activeRows)); %#ok<AGROW>
                    end
                end
                sections{end+1} = obj.canvasDetailSection('Prognostic sequences',seqLines); %#ok<AGROW>
            end

            optLines = obj.canvasMLSectionLines(cfg, 'optimization', 8);
            if ~isempty(optLines)
                sections{end+1} = obj.canvasDetailSection('Model optimization', optLines); %#ok<AGROW>
            end

            selLines = obj.canvasMLSectionLines(cfg, 'selection', 8);
            if ~isempty(selLines)
                sections{end+1} = obj.canvasDetailSection('Model-selection strategy', selLines); %#ok<AGROW>
            end

            detail = obj.canvasMakeDetail(node.title, sub, sections, obj.canvasActionHint(node));
        end

        function lines = canvasMLSectionLines(obj, cfg, sectionId, maxLines)
            lines = {};
            if nargin < 4 || isempty(maxLines), maxLines = 6; end
            if ~isstruct(cfg), return; end
            try
                ctx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
                ml = NMMLModule();
                vf = ml.visibleUIFields(cfg, ctx);
                for ii = 1:numel(vf)
                    fs = vf{ii};
                    if ~isstruct(fs) || ~isfield(fs,'section') || ~strcmpi(char(string(fs.section)), char(string(sectionId)))
                        continue;
                    end
                    if ~isfield(fs,'name') || isempty(fs.name), continue; end
                    name = char(string(fs.name));
                    if startsWith(name,'hyperparameters.'), continue; end
                    val = obj.mlNestedValue(cfg, name, []);
                    if ~obj.canvasValueIsDisplayable(val), continue; end
                    lab = obj.canvasFieldLabel(fs);
                    txt = obj.canvasFormatConfigValue(lab, val, fs, '');
                    if ~isempty(txt), lines{end+1} = txt; end %#ok<AGROW>
                    if numel(lines) >= maxLines, break; end
                end
            catch
                lines = {};
            end
            lines = obj.canvasCleanConfigLines(lines);
        end

        function lines = canvasMLHyperparameterLines(obj, cfg)
            lines = {};
            cards = [];
            if ~isstruct(cfg) || ~isfield(cfg,'hyperparameters') || ~isstruct(cfg.hyperparameters), return; end
            hp = cfg.hyperparameters;
            fields = obj.visibleMLHyperparameterFields(cfg);
            for ii = 1:numel(fields)
                name = fields{ii};
                if strcmpi(name,'learnerParams')
                    if isfield(hp,'learnerParams')
                        [sub, subCards] = obj.canvasLearnerParamGridLines(hp.learnerParams, cfg);
                        lines = [lines sub]; %#ok<AGROW>
                        cards = [cards subCards]; %#ok<AGROW>
                    end
                elseif isfield(hp,name)
                    [line, k] = obj.canvasGridLine(obj.prettyHyperparameterName(name), hp.(name));
                    if ~isempty(line)
                        lines{end+1} = line; %#ok<AGROW>
                        cards(end+1) = k; %#ok<AGROW>
                    end
                end
            end
            cards = cards(cards > 1 & isfinite(cards));
            if numel(cards) > 1
                total = prod(double(cards));
                fac = arrayfun(@(x) sprintf('%.0f', x), cards, 'UniformOutput', false);
                lines{end+1} = sprintf('Hypergrid with %s = %.0f combinations', strjoin(fac, ' x '), total); %#ok<AGROW>
            end
        end

        function [lines, cards] = canvasLearnerParamGridLines(obj, rows, cfg)
            lines = {};
            cards = [];
            mlModule = NMMLModule();
            mlCtx = struct('modeflag', NMAlternativeLabelTools.effectiveMode(obj.NM));
            visibleNames = mlModule.visibleLearnerParamNames(cfg, mlCtx);
            if isstruct(rows), rows = num2cell(rows); end
            if ~iscell(rows), return; end
            for rr = 1:numel(rows)
                r = rows{rr};
                if ~isstruct(r), continue; end
                pname = sprintf('learner parameter %d', rr);
                if isfield(r,'name') && ~isempty(r.name), pname = char(string(r.name)); end
                if ~isempty(visibleNames) && ~any(strcmp(visibleNames, pname)), continue; end
                if isfield(r,'range')
                    [line, k] = obj.canvasGridLine(obj.prettyHyperparameterName(pname), r.range);
                    if ~isempty(line)
                        lines{end+1} = line; %#ok<AGROW>
                        cards(end+1) = k; %#ok<AGROW>
                    end
                end
            end
        end

        function [line, k] = canvasGridLine(obj, name, val)
            line = '';
            k = 1;
            try
                k = obj.hyperparameterCardinality(val);
                if k <= 1, return; end
                txt = obj.canvasFormatCandidateVector(val, '');
                if ~isempty(txt)
                    line = sprintf('%s: %s', name, txt);
                end
            catch
                line = '';
                k = 1;
            end
        end

        function n = canvasGridCardinalityFromLine(obj, line) %#ok<INUSL>
            n = 1;
            try
                tok = regexp(char(string(line)), ':\s*(\d+) candidates', 'tokens', 'once');
                if ~isempty(tok), n = str2double(tok{1}); end
            catch
                n = 1;
            end
        end

        function detail = canvasDetailForCVScope(obj, node, state)
            lines = obj.canvasCVConfigLines(state);
            if isempty(lines), lines = {'Current NeuroMiner cross-validation settings.'}; end
            lines{end+1} = 'Scope: resampling context for the enclosed preprocessing, model fitting, model selection and output generation.';
            detail = obj.canvasMakeDetail(node.title, 'Resampling context', {obj.canvasDetailSection('Configuration', lines)}, 'Double-click to edit cross-validation settings.');
        end

        function lines = canvasCVConfigLines(obj, state)
            lines = {};
            try
                cv = state.cv;
                if isfield(cv,'cvOuterMode'), lines{end+1} = sprintf('Outer CV2 partitioning: %s', obj.canvasHumanValue(char(string(cv.cvOuterMode)))); end
                if isfield(cv,'cvOuterFold'), lines{end+1} = sprintf('Outer CV2 folds: %s', obj.canvasFormatCandidateVector(cv.cvOuterFold,'')); end
                if isfield(cv,'cvOuterPerm'), lines{end+1} = sprintf('Outer CV2 permutations: %s', obj.canvasFormatCandidateVector(cv.cvOuterPerm,'')); end
                if isfield(cv,'cvInnerMode'), lines{end+1} = sprintf('Inner CV1 partitioning: %s', obj.canvasHumanValue(char(string(cv.cvInnerMode)))); end
                if isfield(cv,'cvInnerFold'), lines{end+1} = sprintf('Inner CV1 folds: %s', obj.canvasFormatCandidateVector(cv.cvInnerFold,'')); end
                if isfield(cv,'cvInnerPerm'), lines{end+1} = sprintf('Inner CV1 permutations: %s', obj.canvasFormatCandidateVector(cv.cvInnerPerm,'')); end
                if isfield(cv,'cvEqEnabled') && logical(cv.cvEqEnabled)
                    lines{end+1} = 'CV1 training-partition equalization: enabled';
                end
                if isfield(cv,'cvOuterGroupSummary') && ~isempty(cv.cvOuterGroupSummary)
                    lines{end+1} = sprintf('Outer grouping: %s', char(string(cv.cvOuterGroupSummary)));
                end
                if isfield(cv,'cvInnerGroupSummary') && ~isempty(cv.cvInnerGroupSummary)
                    lines{end+1} = sprintf('Inner grouping: %s', char(string(cv.cvInnerGroupSummary)));
                end
            catch
                lines = {};
            end
        end

        function detail = canvasDetailForEnsembleNode(obj, node)
            sections = {};
            try
                r = obj.RFE;
                flt = isfield(r,'Filter') && isstruct(r.Filter) && isfield(r.Filter,'flag') && logical(r.Filter.flag);
                wrp = isfield(r,'Wrapper') && isstruct(r.Wrapper) && isfield(r.Wrapper,'flag') && logical(r.Wrapper.flag);
                if flt
                    sections{end+1} = obj.canvasDetailSection('Filter', obj.canvasRFEFilterLines(r.Filter)); %#ok<AGROW>
                end
                if wrp
                    sections{end+1} = obj.canvasDetailSection('Wrapper', obj.canvasRFEWrapperLines(r.Wrapper)); %#ok<AGROW>
                end
                if flt && isfield(r.Filter,'SubSpaceFlag') && logical(r.Filter.SubSpaceFlag) && isfield(r.Filter,'EnsembleStrategy')
                    ens = obj.canvasRFEEnsembleLines(r.Filter.EnsembleStrategy, 'filter subspace');
                    if ~isempty(ens), sections{end+1} = obj.canvasDetailSection('Filter subspace ensemble', ens); end %#ok<AGROW>
                end
                if wrp && isfield(r.Wrapper,'SubSpaceFlag') && logical(r.Wrapper.SubSpaceFlag) && isfield(r.Wrapper,'EnsembleStrategy')
                    ens = obj.canvasRFEEnsembleLines(r.Wrapper.EnsembleStrategy, 'wrapper subspace');
                    if ~isempty(ens), sections{end+1} = obj.canvasDetailSection('Wrapper subspace ensemble', ens); end %#ok<AGROW>
                end
            catch
                sections = {};
            end
            if isempty(sections)
                sections = {obj.canvasDetailSection('Configuration', {obj.canvasCleanSentence(node.summary)})};
            end
            detail = obj.canvasMakeDetail(node.title, '', sections, obj.canvasActionHint(node));
        end

        function lines = canvasRFEFilterLines(obj, F)
            lines = {['Strategy: ' obj.canvasCleanSentence(obj.canvasRFEFilterLabel(F))]};
            try, if isfield(F,'MinNum'), lines{end+1} = sprintf('Minimum features: %s', obj.canvasFormatCandidateVector(F.MinNum,'')); end; catch, end %#ok<AGROW>
            try, if isfield(F,'CostFun'), lines{end+1} = ['Optimization criterion: ' obj.canvasRFECostFunctionLabel(F.CostFun)]; end; catch, end %#ok<AGROW>
            try
                if isfield(F,'RankThresh')
                    lines{end+1} = sprintf('Feature-rank threshold: %s', obj.canvasFormatCandidateVector(F.RankThresh,'%')); %#ok<AGROW>
                end
            catch, end
            try
                if isfield(F,'SubSpaceFlag') && logical(F.SubSpaceFlag)
                    lines{end+1} = ['Subspace search: ' obj.canvasRFESubspaceLabel(F)]; %#ok<AGROW>
                end
            catch, end
            lines = obj.canvasCleanConfigLines(lines);
        end

        function lines = canvasRFEWrapperLines(obj, W)
            lines = {['Strategy: ' obj.canvasCleanSentence(obj.canvasRFEWrapperLabel(W))]};
            try, if isfield(W,'optflag'), lines{end+1} = ['Optimization mode: ' obj.canvasRFEWrapperOptLabel(W.optflag)]; end; catch, end %#ok<AGROW>
            try, if isfield(W,'CostFun'), lines{end+1} = ['Optimization criterion: ' obj.canvasRFECostFunctionLabel(W.CostFun)]; end; catch, end %#ok<AGROW>
            try
                if isfield(W,'type') && round(double(W.type)) == 1 && isfield(W,'GreedySearch') && isstruct(W.GreedySearch)
                    G = W.GreedySearch;
                    if isfield(G,'Direction'), lines{end+1} = ['Greedy direction: ' obj.canvasRFEGreedyDirectionLabel(G.Direction)]; end %#ok<AGROW>
                    if isfield(G,'EarlyStop') && isstruct(G.EarlyStop) && isfield(G.EarlyStop,'Thresh')
                        lines{end+1} = sprintf('Early-stop threshold: %s', obj.canvasFormatCandidateVector(G.EarlyStop.Thresh,'%')); %#ok<AGROW>
                    end
                    if isfield(G,'WeightSort'), lines{end+1} = ['Weight sorting: ' obj.canvasRFEYesNo(G.WeightSort)]; end %#ok<AGROW>
                elseif isfield(W,'type') && round(double(W.type)) == 2 && isfield(W,'SA') && isstruct(W.SA)
                    lines{end+1} = sprintf('Simulated-annealing iterations: %s', obj.canvasFormatCandidateVector(W.SA.itt_max,'')); %#ok<AGROW>
                    lines{end+1} = sprintf('Cooling factor: %s', obj.canvasFormatCandidateVector(W.SA.c,'')); %#ok<AGROW>
                elseif isfield(W,'type') && round(double(W.type)) == 3 && isfield(W,'GA') && isstruct(W.GA)
                    lines{end+1} = sprintf('Genetic algorithm population: %s', obj.canvasFormatCandidateVector(W.GA.N,'')); %#ok<AGROW>
                    lines{end+1} = sprintf('Maximum iterations: %s', obj.canvasFormatCandidateVector(W.GA.max_Iter,'')); %#ok<AGROW>
                elseif isfield(W,'type') && round(double(W.type)) == 4 && isfield(W,'PSO') && isstruct(W.PSO)
                    lines{end+1} = sprintf('Particle-swarm particles: %s', obj.canvasFormatCandidateVector(W.PSO.N,'')); %#ok<AGROW>
                    lines{end+1} = sprintf('Maximum iterations: %s', obj.canvasFormatCandidateVector(W.PSO.max_Iter,'')); %#ok<AGROW>
                end
            catch, end
            try
                if isfield(W,'SubSpaceFlag') && logical(W.SubSpaceFlag)
                    lines{end+1} = ['Subspace search: ' obj.canvasRFESubspaceLabel(W)]; %#ok<AGROW>
                end
            catch, end
            lines = obj.canvasCleanConfigLines(lines);
        end

        function lines = canvasRFEEnsembleLines(obj, E, scope)
            lines = {};
            try
                if isfield(E,'ConstructMode'), lines{end+1} = ['Construction: ' obj.canvasRFEEnsembleConstructLabel(E.ConstructMode)]; end %#ok<AGROW>
                if isfield(E,'DivStr') && ~isempty(E.DivStr), lines{end+1} = ['Objective: ' obj.canvasCleanSentence(E.DivStr)]; end %#ok<AGROW>
                if isfield(E,'Metric'), lines{end+1} = ['Performance metric: ' obj.canvasRFECostFunctionLabel(E.Metric)]; end %#ok<AGROW>
                if isfield(E,'Perc'), lines{end+1} = sprintf('Percentile threshold: %s', obj.canvasFormatCandidateVector(E.Perc,'%')); end %#ok<AGROW>
                if isfield(E,'MinNum'), lines{end+1} = sprintf('Minimum models/features: %s', obj.canvasFormatCandidateVector(E.MinNum,'')); end %#ok<AGROW>
                if nargin >= 3 && ~isempty(scope), lines{end+1} = ['Scope: ' char(string(scope))]; end %#ok<AGROW>
            catch
                lines = {};
            end
            lines = obj.canvasCleanConfigLines(lines);
        end

        function label = canvasRFEFilterLabel(obj, F) %#ok<INUSL>
            label = 'configured';
            try
                map = containers.Map([1 2 3 4 5 7 9 10 11 12 13], {'FEAST','MRMR','Pearson/Spearman','Simba','Gflip','IMRelief','Increasing subspace cardinality','RGS','Random subspace sampling','Relief','FScore'});
                t = 3; if isfield(F,'type'), t = round(double(F.type)); end
                if isKey(map,t), label = map(t); else, label = sprintf('method %d', t); end
            catch
            end
        end

        function label = canvasRFEWrapperLabel(obj, W) %#ok<INUSL>
            label = 'configured';
            try
                names = {'Greedy search','Simulated annealing','Genetic algorithm','Particle swarm optimization','Path finder algorithm'};
                t = 1; if isfield(W,'type'), t = round(double(W.type)); end
                if t>=1 && t<=numel(names), label = names{t}; end
            catch
            end
        end


        function label = canvasRFECostFunctionLabel(obj, v) %#ok<INUSL>
            try
                m = containers.Map([1 2 3 4 5 6 7 9 10 11 13 14 15 16 17 18 19 20 21 22 23 24], ...
                    {'Accuracy','Balanced accuracy / NM default','AUC','Sensitivity','Specificity','MCC','AUC','Mean squared error','R^2','Normalized RMSD','Geometric mean','Balanced accuracy','F-score','Pearson R','Enhanced balanced accuracy','Mean absolute error','PSI','NNP','Expected calibration error','Positive likelihood ratio','Negative likelihood ratio','Tail-weighted MSE'});
                k = round(double(v));
                if isKey(m,k), label = m(k); else, label = sprintf('criterion %d', k); end
            catch
                label = char(string(v));
            end
        end

        function label = canvasRFEWrapperOptLabel(obj, v) %#ok<INUSL>
            try
                switch round(double(v))
                    case 1, label = 'single best node';
                    case 2, label = 'optimize across nodes';
                    case 3, label = 'ensemble/subspace optimization';
                    otherwise, label = sprintf('mode %d', round(double(v)));
                end
            catch, label = char(string(v)); end
        end

        function label = canvasRFEGreedyDirectionLabel(obj, v) %#ok<INUSL>
            try
                switch round(double(v))
                    case 1, label = 'forward selection';
                    case 2, label = 'backward elimination';
                    case 3, label = 'bidirectional search';
                    otherwise, label = sprintf('direction %d', round(double(v)));
                end
            catch, label = char(string(v)); end
        end

        function label = canvasRFESubspaceLabel(obj, B)
            label = 'enabled';
            try
                parts = {};
                if isfield(B,'SubSpaceStrategy'), parts{end+1} = ['strategy ' obj.canvasFormatCandidateVector(B.SubSpaceStrategy,'')]; end %#ok<AGROW>
                if isfield(B,'SubSpaceCrit'), parts{end+1} = ['criterion ' obj.canvasFormatCandidateVector(B.SubSpaceCrit,'')]; end %#ok<AGROW>
                if isfield(B,'SubSpaceStepping'), parts{end+1} = ['stepping ' obj.canvasFormatCandidateVector(B.SubSpaceStepping,'')]; end %#ok<AGROW>
                if ~isempty(parts), label = strjoin(parts, ', '); end
            catch
                label = 'enabled';
            end
        end

        function label = canvasRFEEnsembleConstructLabel(obj, v) %#ok<INUSL>
            try
                switch round(double(v))
                    case 0, label = 'disabled';
                    case 1, label = 'performance-filtered ensemble';
                    case 2, label = 'diversity-regularized ensemble';
                    case 4, label = 'weighted mean ensemble';
                    case 5, label = 'boosting ensemble';
                    otherwise, label = sprintf('mode %d', round(double(v)));
                end
            catch, label = char(string(v)); end
        end

        function label = canvasRFEYesNo(obj, v) %#ok<INUSL>
            try
                if logical(round(double(v))), label = 'enabled'; else, label = 'disabled'; end
            catch, label = char(string(v)); end
        end

        function detail = canvasDetailForVISNode(obj, node)
            lines = {};
            v = obj.Vis;
            if v.visSigModelSpace, lines{end+1} = sprintf('Model-space permutations: %s', obj.canvasFormatCandidateVector(v.visNPerms,'')); end
            if v.visPermutationInput
                lines{end+1} = sprintf('Input-space permutations: %s', obj.canvasFormatCandidateVector(v.visNPerms,''));
            end
            if isempty(lines), lines = {obj.canvasCleanSentence(node.summary)}; end
            detail = obj.canvasMakeDetail(node.title, '', {obj.canvasDetailSection('Configuration', lines)}, obj.canvasActionHint(node));
        end

        function detail = canvasDetailForMLINode(obj, node)
            lines = {};
            try
                m = obj.MLI;
                if isfield(m,'mliMethod'), lines{end+1} = ['Method: ' obj.canvasMLIMethodLabel(m.mliMethod)]; end
                if isfield(m,'mliNPermsIsInf') && logical(m.mliNPermsIsInf)
                    lines{end+1} = 'Iterations: automated stopping';
                elseif isfield(m,'mliNPermsText')
                    lines{end+1} = sprintf('Iterations: %s', char(string(m.mliNPermsText)));
                end
                if isfield(m,'mliAtlasFlag'), lines{end+1} = ['Atlas mode: ' obj.canvasFormatBoolean(m.mliAtlasFlag)]; end
                if isfield(m,'mliAtlasImported'), lines{end+1} = ['Atlas imported: ' obj.canvasFormatBoolean(m.mliAtlasImported)]; end
                if isfield(m,'mliMapFlag') && logical(m.mliMapFlag) && isfield(m,'mliMapMap')
                    lines{end+1} = ['Map restriction: ' char(string(m.mliMapMap))];
                end
            catch
            end
            if isempty(lines), lines = {obj.canvasCleanSentence(node.summary)}; end
            detail = obj.canvasMakeDetail(node.title, '', {obj.canvasDetailSection('Configuration', lines)}, obj.canvasActionHint(node));
        end

        function label = canvasMLIMethodLabel(obj, method) %#ok<INUSL>
            switch char(string(method))
                case 'posneg', label = 'Upper/lower percentile occlusion';
                case 'median', label = 'Median occlusion';
                case 'medianflip', label = 'Median-span flip occlusion';
                case 'medianmirror', label = 'Median-mirror occlusion';
                case 'random', label = 'Random-value occlusion';
                case 'shapley', label = 'Shapley values';
                otherwise, label = char(string(method));
            end
        end

        function detail = canvasDetailForInputNode(obj, node, state) %#ok<INUSD>
            lines = {obj.canvasCleanSentence(node.summary)};
            sections = {obj.canvasDetailSection('Configuration', lines)};
            [overview, rich] = obj.canvasModalityOverviewLines(node, obj.canvasNodeRequestsRichDetail(node));
            if ~isempty(overview)
                sections{end+1} = obj.canvasDetailSection('Committed modality overview', overview);
            end
            if ~isempty(rich)
                sections{end+1} = obj.canvasDetailSection('Detailed modality/QC metadata', rich);
            end
            detail = obj.canvasMakeDetail(node.title, node.subtitle, sections, obj.canvasActionHint(node));
        end

        function tf = canvasNodeRequestsRichDetail(obj, node) %#ok<INUSL>
            tf = isstruct(node) && isfield(node,'detailMode') && strcmpi(char(string(node.detailMode)), 'rich');
        end

        function [lines, rich] = canvasModalityOverviewLines(obj, node, includeRich)
            % canvasModalityOverviewLines  Read cached modalityInfo once for both input-node panels.
            %
            % Uses ScanInMemory=false to avoid opening/scanning large modality
            % containers during canvas navigation.

            lines = {};
            rich = {};
            if ~isstruct(node) || ~isfield(node,'modalityIndex') || isempty(node.modalityIndex)
                return;
            end
            idx = round(double(node.modalityIndex));
            if ~isfinite(idx) || idx < 1, return; end
            info = NMModalityInfoTools.fromNM(obj.NM, idx, struct('ScanInMemory', false));
            lines = NMModalityInfoTools.summaryLines(info);
            if includeRich
                rich = obj.canvasModalityRichOverviewLines(info);
            end
        end

        function lines = canvasModalityRichOverviewLines(obj, info)
            lines = {};
            fs = info.featureStats;
            if isfinite(info.nAlignedCases)
                lines{end+1} = sprintf('Aligned cases: %g', double(info.nAlignedCases));
            end
            if isfinite(info.nObservedCases)
                lines{end+1} = sprintf('Observed non-all-NaN cases: %g', double(info.nObservedCases));
            end
            if ~isempty(info.matrixClass)
                lines{end+1} = ['Matrix class: ' char(string(info.matrixClass))];
            end
            qc = {};
            counts = [fs.nCompleteCases, fs.nPartialMissingCases, fs.nAllNaNCases, ...
                fs.nAllNaNFeatures, fs.nConstantFeatures];
            descriptions = {'complete cases', 'partly missing cases', 'complete-NaN cases', ...
                'all-NaN features', 'constant features'};
            for k = 1:numel(counts)
                if isfinite(counts(k))
                    qc{end+1} = sprintf('%g %s', double(counts(k)), descriptions{k});
                end
            end
            if isfinite(fs.featureMeanMin) && isfinite(fs.featureMeanMax)
                qc{end+1} = sprintf('feature mean range %.4g to %.4g', double(fs.featureMeanMin), double(fs.featureMeanMax));
            end
            if isfinite(fs.featureSDMin) && isfinite(fs.featureSDMax)
                qc{end+1} = sprintf('feature SD range %.4g to %.4g', double(fs.featureSDMin), double(fs.featureSDMax));
            end
            if ~isempty(qc)
                lines{end+1} = ['QC summary: ' strjoin(qc, '; ')];
            else
                lines{end+1} = 'QC summary: cached feature-QC metadata are not available.';
            end
            if isequal(logical(info.featureNamesAvailable), true)
                lines{end+1} = sprintf('Feature names: %g available', double(info.nFeatureNames));
            end
            if isfinite(info.badcoordsCount)
                lines{end+1} = sprintf('Omitted coordinates/features: %g', double(info.badcoordsCount));
            end
            if ~isempty(info.diagnostics)
                lines{end+1} = sprintf('Recorded DataIO diagnostics: %g message(s)', double(numel(info.diagnostics)));
            end
        end

        function detail = canvasDetailForStackingInput(obj, node)
            lines = {obj.canvasCleanSentence(node.summary)};
            lines = regexprep(lines, ';\s*\d+ feature\(s\);\s*available\.', '');
            detail = obj.canvasMakeDetail(node.title, node.subtitle, {obj.canvasDetailSection('Configuration', lines)}, 'This source-analysis box is informational in the current UI.');
        end

        function detail = canvasDetailForFusionNode(obj, node, state)
            lines = {};
            try
                f = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
                switch round(double(f))
                    case 1, lines{end+1} = 'Fusion mode: early fusion';
                    case 2, lines{end+1} = 'Fusion mode: intermediate fusion';
                    case 3, lines{end+1} = 'Fusion mode: late fusion';
                    otherwise, lines{end+1} = 'Fusion mode: single modality';
                end
                M = obj.canvasRelevantModalities(state);
                if ~isempty(M), lines{end+1} = ['Selected modalities: ' obj.methodsIndexList(M)]; end
            catch
                lines = obj.canvasGenericSummaryLines(node.summary);
            end
            detail = obj.canvasMakeDetail(node.title, node.subtitle, {obj.canvasDetailSection('Configuration', lines)}, obj.canvasActionHint(node));
        end

        function warn = canvasReviewLinesForNode(obj, node, audit) %#ok<INUSD>
            warn = {};
            try
                items = node.auditItems;
                if isempty(items), return; end
                seen = containers.Map('KeyType','char','ValueType','logical');
                modId = lower(char(string(node.moduleId)));
                for ii = 1:numel(items)
                    sev = ''; msg = ''; ttl = '';
                    try, sev = lower(char(string(items(ii).severity))); catch, end
                    if ~any(strcmp(sev, {'warning','error'})), continue; end
                    try, msg = char(string(items(ii).message)); catch, end
                    try, ttl = char(string(items(ii).title)); catch, end
                    if isempty(msg), msg = ttl; end
                    if strcmpi(node.configurator,'preproc') && (contains(lower(msg),'configured across modalities') || contains(lower(msg),'preprocessing step(s) configured'))
                        continue;
                    end
                    if strcmpi(node.configurator,'preproc') && contains(lower(msg),'mixed imaging/non-imaging') && ~isempty(modId)
                        if ~contains(lower(msg), modId), continue; end
                        msg = sprintf('This %s step is incompatible with the current mixed imaging/non-imaging early-fusion setup.', lower(char(string(node.title))));
                    end
                    msg = obj.canvasCleanSentence(msg);
                    key = lower(msg);
                    if ~isempty(msg) && ~isKey(seen,key)
                        warn{end+1} = msg; seen(key) = true; %#ok<AGROW>
                    end
                end
            catch
                warn = {};
            end
        end

        function hint = canvasActionHint(obj, node) %#ok<INUSL>
            nodeType = '';
            if isstruct(node) && isfield(node,'type') && ~isempty(node.type)
                nodeType = lower(char(string(node.type)));
            end
            if strcmp(nodeType,'modality')
                hint = 'Double-click to open QC dashboard.';
            elseif strcmp(nodeType,'label')
                hint = 'Double-click to open label dashboard.';
            elseif strcmp(nodeType,'covariate')
                hint = 'Double-click to open covariate dashboard.';
            elseif isfield(node,'action') && strcmpi(node.action,'noop')
                hint = 'This canvas box is informational in the current UI.';
            elseif strcmpi(node.configurator,'preproc')
                hint = 'Double-click to edit this preprocessing card.';
            elseif strcmpi(node.configurator,'cv')
                hint = 'Double-click to edit cross-validation settings.';
            elseif ~isempty(node.configurator)
                hint = sprintf('Double-click to edit %s settings.', char(string(node.configurator)));
            else
                hint = '';
            end
        end

        function title = canvasPreprocModuleTitle(obj, moduleId) %#ok<INUSL>
            m = lower(char(string(moduleId)));
            switch m
                case {'impute','nmimputemodule'}, title = 'Imputation';
                case {'standardize','nmstandardizemodule'}, title = 'Standardization';
                case {'scale','nmscalemodule'}, title = 'Scaling';
                case {'elimzero','nmelimzeromodule'}, title = 'Zero-variance removal';
                case {'rankfeat','nmrankfeatmodule'}, title = 'Feature ranking';
                case {'extfeat','nmextfeatmodule'}, title = 'Feature extraction';
                case {'reducedim','nmreducedimmodule'}, title = 'Reduce dim.';
                case {'extdim','nmextdimmodule'}, title = 'Extract dim.';
                case {'remvarcomp','nmremvarcompmodule'}, title = 'Component removal';
                case {'correctnuis','nmcorrectnuismodule'}, title = 'Nuisance correction';
                case {'remmeandiff','nmremmeandiffmodule'}, title = 'Offset correction';
                case {'smoothing','nmsmoothingmodule'}, title = 'Spatial smoothing';
                case {'juspace','nmjuspacemodule'}, title = 'JuSpace';
                case {'roimeans','nmroimeansmodule'}, title = 'ROI means';
                case {'waveletspatial','nmwaveletspatialmodule'}, title = 'Wavelet spatial reconstruction';
                otherwise
                    title = strrep(char(string(moduleId)), '_', ' ');
                    if isempty(strtrim(title)), title = char(string(moduleId)); end
            end
        end

        function s = canvasBriefStructSummary(obj, cfg, fallback) %#ok<INUSL>
            s = char(string(fallback));
            try
                f = fieldnames(cfg);
                parts = {};
                for ii = 1:min(numel(f),4)
                    v = cfg.(f{ii});
                    if isnumeric(v) || islogical(v)
                        parts{end+1} = sprintf('%s=%s', f{ii}, mat2str(v)); %#ok<AGROW>
                    elseif ischar(v) || isstring(v)
                        parts{end+1} = sprintf('%s=%s', f{ii}, char(string(v))); %#ok<AGROW>
                    end
                end
                if ~isempty(parts), s = strjoin(parts, '; '); end
            catch
                s = char(string(fallback));
            end
        end

        function txt = canvasMLSummaryForModality(obj, idx)
            txt = sprintf('Late-fusion STRAT{%d} learner configuration.', idx);
            try
                if obj.FusionFlag == 3 && idx <= numel(obj.MLStrat) && ~isempty(obj.MLStrat{idx})
                    cfg = obj.MLStrat{idx}.MLConfig;
                else
                    cfg = obj.MLGlobal.MLConfig;
                end
                alg = '?';
                if isstruct(cfg) && isfield(cfg,'algorithm') && ~isempty(cfg.algorithm)
                    alg = char(string(cfg.algorithm));
                end
                title = alg;
                try, title = NMLearnerLibrary.title(alg); catch, end
                [hpNames, nComb] = obj.optimizedMLHyperparameters(cfg);
                if isempty(hpNames)
                    txt = sprintf('%s configured for STRAT{%d}; fixed hyperparameters.', title, idx);
                elseif isfinite(nComb)
                    txt = sprintf('%s configured for STRAT{%d}; optimized: %s (%d combinations).', title, idx, strjoin(hpNames, ', '), round(nComb));
                else
                    txt = sprintf('%s configured for STRAT{%d}; optimized: %s.', title, idx, strjoin(hpNames, ', '));
                end
            catch
            end
        end

        function selected = canvasStackingSelectedAnalyses(obj, state)
            selected = [];
            try
                if isstruct(state) && isfield(state,'stackingSelectedAnalyses') && ~isempty(state.stackingSelectedAnalyses)
                    selected = double(state.stackingSelectedAnalyses(:))';
                else
                    selected = double(obj.getStackingSelectedAnalyses());
                end
            catch
                selected = [];
            end
            % Canvas fallback: when stacking is enabled but no explicit
            % selection has yet been committed, show the available first-tier
            % analysis candidates instead of rendering an empty/stale graph.
            % This is a display fallback only; it does not mutate STACKING.
            if isempty(selected)
                try
                    if isstruct(obj.Stacking) && isfield(obj.Stacking,'source_anal') && ~isempty(obj.Stacking.source_anal)
                        idx = [obj.StackingCandidates.index];
                        av = [obj.StackingCandidates.available];
                        cand = idx(logical(av) & logical(obj.Stacking.source_anal(:)'));
                        selected = double(cand(:))';
                    end
                catch
                end
            end
            if isempty(selected)
                try
                    idx = [obj.StackingCandidates.index];
                    av = [obj.StackingCandidates.available];
                    selected = double(idx(logical(av)));
                catch
                end
            end
            selected = selected(isfinite(selected) & selected > 0);
            selected = unique(round(selected),'stable');
        end

        function txt = canvasStackingAnalysisSummary(obj, ana)
            txt = sprintf('Selected completed analysis %d contributes first-tier predictions/features to the stacker.', ana);
            try
                idx = [obj.StackingCandidates.index];
                k = find(idx == ana, 1, 'first');
                if ~isempty(k)
                    lab = char(string(obj.StackingCandidates(k).label));
                    av = logical(obj.StackingCandidates(k).available);
                    txt = sprintf('%s; first-tier source analysis contributing fold-wise prediction outputs (%s).', lab, obj.ifelseText(av,'available','unavailable'));
                end
            catch
            end
        end

        function txt = ifelseText(obj, cond, a, b) %#ok<INUSL>
            if cond, txt = a; else, txt = b; end
        end

        function items = canvasAuditItemsForNode(obj, audit, configurator, meta)
            items = obj.canvasAuditItems(audit, configurator);
            try
                cfg = lower(char(string(configurator)));
                if ~strcmp(cfg,'preproc') || isempty(items) || ~isfield(meta,'moduleId') || isempty(meta.moduleId)
                    return;
                end
                modId = lower(char(string(meta.moduleId)));
                if isempty(strtrim(modId)), return; end
                keep = true(1,numel(items));
                for ii = 1:numel(items)
                    sev = '';
                    msg = '';
                    ttl = '';
                    try, sev = lower(char(string(items(ii).severity))); catch, end
                    try, msg = lower(char(string(items(ii).message))); catch, end
                    try, ttl = lower(char(string(items(ii).title))); catch, end
                    txt = [ttl ' ' msg];
                    if any(strcmp(sev, {'warning','error'})) && contains(txt,'mixed early') && contains(txt,'incompatible')
                        % Mixed early-fusion warnings list the offending module ids.
                        % Attach this warning only to the offending preprocessing
                        % step node, not to the entire shared pipeline.
                        keep(ii) = contains(txt, modId);
                    end
                    try
                        iid = lower(char(string(items(ii).id)));
                        if startsWith(iid, 'preproc.availability.')
                            tgt = lower(char(string(items(ii).target)));
                            expected = sprintf('%s:%d:%s', lower(char(string(meta.stage))), round(double(meta.stepIndex)), modId);
                            keep(ii) = isempty(tgt) || strcmp(tgt, expected) || strcmp(tgt, modId);
                        end
                    catch
                    end
                end
                items = items(keep);
                if isempty(items), items = obj.auditEmptyItems(); end
            catch
            end
        end

        function items = canvasAuditItems(obj, audit, configurator) %#ok<INUSL>
            items = obj.auditEmptyItems();
            if nargin < 3 || isempty(configurator) || isempty(audit), return; end
            if iscell(audit), audit = [audit{:}]; end
            if isempty(audit), return; end
            keep = false(1,numel(audit));
            cfg = lower(char(string(configurator)));
            aliases = obj.canvasConfiguratorAliases(cfg);
            for ii = 1:numel(audit)
                a = '';
                s = '';
                try, a = lower(char(string(audit(ii).configurator))); catch, end
                try, s = lower(char(string(audit(ii).scope))); catch, end
                keep(ii) = any(strcmp(a, aliases)) || any(strcmp(s, aliases));
            end
            items = audit(keep);
            if isempty(items), items = obj.auditEmptyItems(); end
        end

        function aliases = canvasConfiguratorAliases(obj, cfg) %#ok<INUSL>
            aliases = {cfg};
            switch lower(cfg)
                case 'altlabel'
                    aliases = {'altlabel','alternative_label','label','data_labels'};
                case 'preproc'
                    aliases = {'preproc','preprocessing'};
                case 'ml'
                    aliases = {'ml','machine_learning','learner'};
                case 'sav'
                    aliases = {'sav','saving','verbosity'};
                case 'snapshot'
                    aliases = {'snapshot','save_load','compatibility'};
                case 'scaffold'
                    aliases = {'scaffold','api_export','export'};
                case 'data'
                    aliases = {'data','modality','modalities','data_labels'};
                case 'stacking'
                    aliases = {'stacking','stacker','meta_learning'};
                case 'fusion'
                    aliases = {'fusion','fusion_merge','late_fusion'};
                case 'cv'
                    aliases = {'cv','cross_validation','cvpartition'};
                case 'synth'
                    aliases = {'synth','synthetic','synthetic_data'};
                case 'multi'
                    aliases = {'multi','multiclass','multi_class'};
                case 'rfe'
                    aliases = {'rfe','ensemble','rfe_ensemble'};
                case 'vis'
                    aliases = {'vis','visualization'};
                case 'mli'
                    aliases = {'mli','interpretable_ml'};
            end
        end

        function status = canvasStatus(obj, items, inactive, configurator)
            if nargin >= 3 && logical(inactive)
                status = 'inactive';
                return;
            end
            status = 'ok';
            if isempty(items)
                if any(strcmp(obj.CommittedConfigurators,configurator)), status = 'committed'; end
                return;
            end
            sev = cell(1,numel(items));
            for ii = 1:numel(items)
                try, sev{ii} = lower(char(string(items(ii).severity))); catch, sev{ii} = 'info'; end
            end
            if any(strcmp(sev,'error'))
                status = 'error';
            elseif any(strcmp(sev,'warning'))
                status = 'warning';
            elseif any(strcmp(obj.CommittedConfigurators,configurator))
                status = 'committed';
            elseif any(strcmp(sev,'info'))
                status = 'info';
            end
        end

        function s = canvasSummary(obj, state, fieldName, defaultVal) %#ok<INUSL>
            s = defaultVal;
            try
                if isstruct(state) && isfield(state, fieldName) && ~isempty(state.(fieldName))
                    s = char(string(state.(fieldName)));
                end
            catch
                s = defaultVal;
            end
        end

        function val = canvasGetScalar(obj, state, fieldName, defaultVal) %#ok<INUSL>
            val = defaultVal;
            try
                if isstruct(state) && isfield(state, fieldName) && ~isempty(state.(fieldName))
                    x = double(state.(fieldName));
                    if isfinite(x(1)), val = x(1); end
                end
            catch
                val = defaultVal;
            end
        end

        function s = canvasSafeChar(obj, st, fieldName, defaultVal) %#ok<INUSL>
            s = defaultVal;
            try
                if isstruct(st) && isfield(st, fieldName) && ~isempty(st.(fieldName))
                    s = char(string(st.(fieldName)));
                end
            catch
                s = defaultVal;
            end
        end

        function s = canvasSubtitleFromState(obj, state)
            n = obj.canvasGetScalar(state,'numModalities',obj.NumModalities);
            s = sprintf('%d modality/modalities; %s', n, char(string(state.altLabelMode)));
        end

        function tf = canvasShowCovariateCard(obj)
            tf = false;
            try
                if ~isfield(obj.NM,'covars') || isempty(obj.NM.covars), return; end
                if ~isfield(obj.NM,'covnames') || isempty(obj.NM.covnames), return; end
                tf = obj.canvasPreprocUsesCovariates();
            catch
                tf = false;
            end
        end

        function txt = canvasCovariateSubtitle(obj)
            n = 0;
            try, n = size(obj.NM.covars, 2); catch, end
            txt = sprintf('%d covariate(s) available', double(n));
        end

        function txt = canvasCovariateSummary(~)
            txt = 'NM covariates are available; active preprocessing-step configurations specify their use.';
        end

        function tf = canvasPreprocUsesCovariates(obj)
            tf = false;
            try
                for ii = 1:numel(obj.Preproc)
                    if obj.canvasPreprocObjectUsesCovariates(obj.Preproc{ii}), tf = true; return; end
                end
            catch
                tf = false;
            end
        end

        function tf = canvasPreprocObjectUsesCovariates(obj, pp)
            tf = false;
            if isempty(pp), return; end
            try
                steps = [obj.sequenceStepsFromPreprocObject(pp, 'subject'), obj.sequenceStepsFromPreprocObject(pp, 'cv')];
                for ii = 1:numel(steps)
                    [~, usesCovariates] = obj.canvasPreprocStepDataUsage(steps{ii});
                    if usesCovariates, tf = true; return; end
                end
            catch
                tf = false;
            end
        end

        function [usesLabels, usesCovariates] = canvasPreprocStepDataUsage(obj, st)
            usesLabels = false; usesCovariates = false;
            moduleId = lower(char(string(obj.preprocStepLabel(st, ''))));
            cfg = st.config;

            switch moduleId
                case {'correctnuis','nmcorrectnuismodule','remmeandiff','nmremmeandiffmodule'}
                    usesCovariates = true;
                    return;
                case {'reducedim','nmreducedimmodule'}
                    usesLabels = obj.canvasDimReductionUsesLabels(cfg);
                    return;
                case {'rankfeat','nmrankfeatmodule'}
                    usesLabels = obj.canvasConfigSourceUsesToken(cfg, 'label');
                    return;
                case {'remvarcomp','nmremvarcompmodule'}
                    usesCovariates = obj.canvasConfigSourceUsesToken(cfg, 'cov') || ...
                        (isfield(cfg,'covariateColumns') && ~isempty(cfg.covariateColumns));
                    usesLabels = obj.canvasConfigSourceUsesToken(cfg, 'label');
                    return;
                otherwise
                    usesLabels = obj.canvasConfigSourceUsesToken(cfg, 'label');
                    usesCovariates = obj.canvasConfigSourceUsesToken(cfg, 'cov') || ...
                        (isfield(cfg,'covariateColumns') && ~isempty(cfg.covariateColumns));
            end
        end

        function tf = canvasConfigSourceUsesToken(obj, cfg, token) %#ok<INUSL>
            tf = false;
            if ~isstruct(cfg), return; end
            token = lower(char(string(token)));
            names = {'labelSource','targetSource'};
            for ii = 1:numel(names)
                name = names{ii};
                if ~isfield(cfg, name) || isempty(cfg.(name)), continue; end
                try
                    txt = lower(char(string(cfg.(name))));
                    if contains(txt, token), tf = true; return; end
                catch
                end
            end
        end

        function tf = canvasDimReductionUsesLabels(obj, cfg) %#ok<INUSL>
            tf = false;
            if ~isstruct(cfg), return; end
            mode = '';
            candidateNames = {'redMode','RedMode','method','reductionMethod'};
            for ii = 1:numel(candidateNames)
                name = candidateNames{ii};
                if isfield(cfg, name) && ~isempty(cfg.(name))
                    try
                        mode = lower(char(string(cfg.(name))));
                    catch
                        mode = '';
                    end
                    if ~isempty(mode), break; end
                end
            end
            supervisedModes = {'pls','lda','gda','nca','lmnn'};
            tf = any(strcmp(mode, supervisedModes));
        end

        function s = canvasActiveModalitySubtitle(obj, state)
            a = obj.canvasGetScalar(state,'activeModality',obj.VarIndex);
            s = sprintf('Active modality %d', a);
        end

        function s = canvasMLSubtitle(obj, state)
            flag = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            if flag == 3
                s = 'Late-fusion STRAT-specific learner';
            else
                s = 'Global learner';
            end
        end

        function s = canvasFusionSubtitle(obj, state)
            flag = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            labels = {'No fusion','Early fusion','Intermediate fusion','Late fusion'};
            if flag >= 0 && flag <= 3
                s = labels{flag+1};
            else
                s = 'Unknown fusion mode';
            end
        end

        function s = canvasFusionSummary(obj, state)
            flag = obj.canvasGetScalar(state,'fusionFlag',obj.FusionFlag);
            M = obj.FusionModalities;
            try
                if isfield(state,'fusionModalities') && ~isempty(state.fusionModalities)
                    M = double(state.fusionModalities(:))';
                end
            catch
                M = obj.FusionModalities;
            end
            s = sprintf('Fusion flag=%d; modalities=%s.', flag, mat2str(M));
        end

        function s = canvasPreprocSummary(obj, state)
            s = obj.canvasSummary(state,'preprocSummary','No preprocessing status available.');
            try
                idx = obj.canvasGetScalar(state,'activeModality',obj.VarIndex);
                if isfield(state,'preprocSummaries') && numel(state.preprocSummaries) >= idx && ~isempty(state.preprocSummaries{idx})
                    s = char(string(state.preprocSummaries{idx}));
                end
            catch
            end
        end

        function normalizeFusionState(obj)
            obj.FusionFlag = obj.clampFusionFlag(obj.FusionFlag);
            if obj.FusionFlag == 0
                v = round(double(obj.VarIndex));
                if ~isfinite(v) || v < 1 || v > obj.NumModalities, v = 1; end
                obj.VarIndex = v;
                obj.FusionModalities = v;
                return;
            end
            obj.FusionModalities = obj.normalizeModalities(obj.FusionModalities, obj.NumModalities, obj.VarIndex);
            if numel(obj.FusionModalities) < 2
                obj.FusionFlag = 0;
                obj.FusionModalities = obj.VarIndex;
            elseif obj.FusionFlag == 1 || ~any(obj.FusionModalities == obj.VarIndex)
                obj.VarIndex = obj.FusionModalities(1);
            end
        end

        function flag = clampFusionFlag(obj, flag)
            choices = obj.FusionChoices;
            try
                idx = find(strcmp(flag, {choices.symbol}), 1);
                if ~isempty(idx), flag = choices(idx).code; end
                idx = find([choices.code] == flag);
                assert(numel(idx)==1);
            catch
                error('NMTrainTemplateOrchestrator:invalidFusionFlag', ...
                    'Allowed: none (0), early (1), intermediate (2), late (3).');
            end
        end


        function M = normalizeModalities(obj, M, n, fallback) %#ok<INUSL>
            if nargin < 4 || isempty(fallback), fallback = 1; end
            try, M = double(M(:))'; catch, M = fallback; end
            M = unique(round(M(isfinite(M) & M >= 1 & M <= n)), 'stable');
            if isempty(M), M = fallback; end
        end
    end
end
