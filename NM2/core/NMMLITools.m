classdef NMMLITools
% NMMLITools
% -------------------------------------------------------------------------
% Browser-port helper for nk_MLI_config.m. The helper keeps UI-only fields
% out of NM.TrainParam.MLI and writes only the legacy MLI structure consumed
% by nk_MLInterpreter* and nk_CreateData4MLInterpreter.m. Atlas and atlas-
% descriptor import are exposed as explicit MATLAB-side service calls so that
% image/vectorization work happens immediately when the user selects/imports
% resources, not at browser shutdown.
% -------------------------------------------------------------------------

    properties (Constant, Access = private)
        MethodChoices = struct('symbol',{'posneg','median','medianflip','medianmirror','random','shapley'}, ...
            'description',{'Upper/lower percentile occlusion','Median occlusion', ...
            'Median-span flip occlusion','Median-mirror occlusion','Random-value occlusion','Shapley values'})
        MapChoices = struct('symbol',{'cvr','p_sgn','p_FDR_sgn'}, ...
            'description',{'Cross-validation ratio','Uncorrected sign-consistency P value','FDR-corrected sign-consistency P value'})
        PercentChoices = struct('symbol',{'absolute','percentile'}, ...
            'description',{'Absolute cutoff','Percentile cutoff'})
        DelimiterChoices = struct('symbol',{';',',','tab','space'}, ...
            'description',{'Semicolon','Comma','Tab','Whitespace'})
        NormalizationChoices = struct('symbol',{'group_only','center_case','zscore_case','unit_range_case'}, ...
            'code',{1,2,3,4},'description',{'Group-level normalization only','Case-level mean centering', ...
            'Case-level Z normalization','Case-level scaling to [-1,1]'})
    end

    methods (Static)

        function [NM, state, report] = cli_configure(NM, varargin)
            % cli_configure  Programmatically configure the ML-interpretation branch.
            %
            % Merges state/name-value inputs with stateFromNM, applies aliases and normalization, then materializes the result through applyToNM. This is an API-facing entry point; it mutates NM only through the documented legacy target NM.TrainParam.MLI and returns a structured report.
            if nargin < 1 || isempty(NM), NM = struct(); end
            varind = NMConfigureAPITools.optionValue(varargin, 'VarIndex', 1);
            fusionFlag = NMConfigureAPITools.optionValue(varargin, 'FusionFlag', []);
            if isempty(fusionFlag), fusionFlag = NMFusionStateTools.flagFromNM(NM); end
            defaultState = NMMLITools.stateFromNM(NM, varind, fusionFlag);
            [state, ~, report] = NMConfigureAPITools.parseState(defaultState, varargin, {'VarIndex','FusionFlag'}, true);
            if ~report.ok, return; end
            if NMConfigureAPITools.hasModifications(varargin), state.mliDirty = true; end
            try
                state = NMConfigureAPITools.normalizeChoices(state, NMMLITools.apiChoices(), 'MATLAB:assertion:failed');
                state = NMMLITools.normalizeState(NM, state, varind, fusionFlag);
                NM = NMMLITools.applyToNM(NM, state, varind, fusionFlag);
                if isempty(report.message), report.message = 'NMMLITools configuration applied.'; end
            catch ME
                report = NMConfigureAPITools.appendException(report, ME);
            end
        end

        function [NM, state, report] = configure(NM, varargin)
            % configure  Alias the public ML-interpretation configure API to cli_configure.
            %
            % Keeps browser/scaffold and scripted callers on one noninteractive code path. The method has the same side effects and report semantics as cli_configure.
            [NM, state, report] = NMMLITools.cli_configure(NM, varargin{:});
        end

        function h = cli_configureHelp()
            % cli_configureHelp  Describe the scripted ML-interpretation configuration interface.
            %
            % Returns syntax, supported options and examples for configuring NM.TrainParam.MLI. The result is read-only metadata for help displays, scaffold export and RAG extraction.
            opts = struct();
            opts.existingState = 'Optional existing state/configuration struct; following name/value pairs override it.';
            opts.VarIndex = 'Modality/strategy index where applicable.';
            opts.FusionFlag = 'Fusion flag where applicable.';
            opts.mliMethod = 'Canonical interpretation method; see h.choices.mliMethod.';
            opts.mliMapMap = 'Canonical map type; see h.choices.mliMapMap.';
            opts.mliMapPercentMode = 'Absolute or percentile cutoff.';
            opts.mliCsvDelim = 'Atlas descriptor delimiter.';
            opts.mliMapOperator = 'Numeric, depends on cutoff count. One cutoff: 1=<, 2=<=, 3=>, 4=>=, 5===, 6=~=; two cutoffs: 1=< or >, 2=<= or >=, 3=> or <, 4=>= or <=.';
            h = NMConfigureAPITools.helpStruct('NMMLITools.cli_configure', ...
                '[NM, state, report] = NMMLITools.cli_configure(NM, existingState, name, value, ...)', opts, ...
                {'[NM, state, report] = NMMLITools.configure(NM, ''mliMethod'',''shapley'', ''mliZNormData'',''group_only'');'}, NMMLITools.apiChoices());
            h.validationRules = {'mliMapOperator depends on the number of cutoff values and remains numeric.'; ...
                'Atlas/descriptor options require imaging modality provenance and explicit resource import.'};
        end

        function choices = apiChoices()
            choices.mliZNormData = NMMLITools.NormalizationChoices;
            choices.mliMethod = NMMLITools.MethodChoices;
            choices.mliMapMap = NMMLITools.MapChoices;
            choices.mliMapPercentMode = NMMLITools.PercentChoices;
            choices.mliCsvDelim = NMMLITools.DelimiterChoices;
            for key = {'mliMethod','mliMapMap','mliMapPercentMode','mliCsvDelim'}
                c = choices.(key{1});
                for k = 1:numel(c), c(k).code = c(k).symbol; end
                choices.(key{1}) = c;
            end
        end

        function h = configureHelp()
            % configureHelp  Return browser/API help metadata for the ML-interpretation branch.
            %
            % Provides a compact help struct for configuration surfaces without invoking legacy menus or changing NM.
            h = NMMLITools.cli_configureHelp();
        end

        function config = scientificConfig(NM, state, varind, fusionFlag)
            % scientificConfig  Effective method, mapping, and resource choices.
            % The owning MLI API excludes preview data and inactive atlas/map
            % settings; imported atlas vectors and descriptor tables are rebuilt
            % through importAtlasFile/importDescriptorFile, never serialized.
            defaults = NMMLITools.stateFromMLI( ...
                NMMLITools.defaultSetting(NM, varind, fusionFlag), ...
                NM, varind, fusionFlag, true);
            keys = {'mliMethod','mliNPermsText','mliMapFlag'};
            if strcmp(state.mliMethod,'shapley')
                keys{end+1} = 'mliSampleFrac';
            else
                keys = [keys, {'mliFeatureFrac','mliZNormData'}];
                if strcmp(state.mliMethod,'posneg')
                    keys = [keys, {'mliUpperThresh','mliLowerThresh'}];
                end
                if strcmpi(state.mliNPermsText,'Inf')
                    keys = [keys, {'mliMaxIter','mliNVisited'}];
                end
            end
            if state.mliMapFlag
                keys = [keys, {'mliMapMap','mliMapCutoffText', ...
                    'mliMapPercentMode','mliMapOperator'}];
            end
            if state.mliIsImaging
                keys{end+1} = 'mliAtlasFlag';
                if state.mliAtlasFlag && ~isempty(state.mliAtlasFile)
                    assert(state.mliAtlasImported,'NMMLITools:scientificAtlas', ...
                        'The selected atlas must be imported before exporting its configuration.');
                    keys{end+1} = 'mliAtlasFile';
                end
                if state.mliAtlasFlag && ~isempty(state.mliCsvFile)
                    assert(state.mliCsvImported,'NMMLITools:scientificDescriptor', ...
                        'The selected descriptor must be imported before exporting its configuration.');
                    keys = [keys, {'mliCsvFile','mliCsvDelim','mliCsvId','mliCsvCol'}];
                end
            end
            config = struct();
            if all(cellfun(@(k)isequaln(state.(k),defaults.(k)),keys)), return; end
            choices = NMMLITools.apiChoices();
            for k = 1:numel(keys)
                name = keys{k};
                value = state.(name);
                if ismember(name,fieldnames(choices))
                    available = choices.(name);
                    match = find(arrayfun(@(c)isequaln(c.code,value),available));
                    assert(isscalar(match),'NMMLITools:scientificSymbol', ...
                        'No unique symbolic MLI choice for %s.',name);
                    value = available(match).symbol;
                end
                config.(name) = value;
            end
        end

        function state = stateFromNM(NM, varind, fusionFlag)
            % stateFromNM  Reconstruct ML-interpretation browser/API state from the current NM workspace.
            %
            % Reads NM.TrainParam.MLI and related modality/fusion context, applies defaults and returns a fixed-schema state. The method is read-only and is the starting point for editing or scripted updates.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            [MLI, present] = NMMLITools.extractLegacyMLI(NM, varind, fusionFlag);
            MLI = NMMLITools.completeDefaults(MLI, NM, varind, fusionFlag);
            state = NMMLITools.stateFromMLI(MLI, NM, varind, fusionFlag, true);
            state.mliPresent = present;
            state.mliDirty = false;
        end


        function MLI = defaultSetting(NM, varind, fusionFlag, MLI)
            % defaultSetting  Public legacy default used by NMTrainTemplateOrchestrator when.
            %
            % an MLI branch is absent or does not cover all modalities.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(varind), varind = 1; end
            if nargin < 4 || isempty(MLI), MLI = struct(); end
            MLI = NMMLITools.completeDefaults(MLI, NM, varind, fusionFlag);
        end

        function MLI = completeDefaults(MLI, NM, varind, fusionFlag)
            % completeDefaults  Fill missing legacy MLI fields with modular defaults.
            %
            % Normalizes an existing MLI struct before it is converted to browser/API state or written back to NM. Defaults are chosen to preserve legacy NeuroMiner behavior unless the caller explicitly changes them.
            if nargin < 1 || isempty(MLI), MLI = struct(); end
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(varind), varind = 1; end
            if ~isstruct(MLI), MLI = struct(); end
            M = NMMLITools.modalityIndex(varind, fusionFlag);
            if ~isfield(MLI,'method') || isempty(MLI.method), MLI.method = 'posneg'; end
            MLI.method = NMMLITools.allowedChar(MLI.method, 'posneg', {NMMLITools.MethodChoices.symbol});
            if ~isfield(MLI,'nperms') || isempty(MLI.nperms), MLI.nperms = 1024; end
            if ~isfield(MLI,'upper_thresh') || isempty(MLI.upper_thresh), MLI.upper_thresh = 95; end
            if ~isfield(MLI,'lower_thresh') || isempty(MLI.lower_thresh), MLI.lower_thresh = 5; end
            if ~isfield(MLI,'max_iter') || isempty(MLI.max_iter), MLI.max_iter = 1000; end
            if ~isfield(MLI,'n_visited') || isempty(MLI.n_visited), MLI.n_visited = 100; end
            if ~isfield(MLI,'znormdata') || isempty(MLI.znormdata), MLI.znormdata = 1; end
            if ~isfield(MLI,'frac') || isempty(MLI.frac), MLI.frac = 0.25; end
            MLI.nperms = NMMLITools.iterOrInf(MLI.nperms, 1024);
            MLI.upper_thresh = NMMLITools.scalarOrDefault(MLI.upper_thresh, 95);
            MLI.lower_thresh = NMMLITools.scalarOrDefault(MLI.lower_thresh, 5);
            MLI.max_iter = max(1, round(NMMLITools.scalarOrDefault(MLI.max_iter, 1000)));
            MLI.n_visited = max(1, round(NMMLITools.scalarOrDefault(MLI.n_visited, 100)));
            MLI.znormdata = NMMLITools.allowedScalar(MLI.znormdata, 1, 1:4);
            MLI.frac = NMMLITools.clampFraction(MLI.frac, 0.25);

            if ~isfield(MLI,'Modality') || ~iscell(MLI.Modality), MLI.Modality = cell(1, max(1,M)); end
            if numel(MLI.Modality) < M, MLI.Modality{M} = []; end
            if isempty(MLI.Modality{M}) || ~isstruct(MLI.Modality{M}), MLI.Modality{M} = struct(); end
            MOD = MLI.Modality{M};
            if ~isfield(MOD,'frac') || isempty(MOD.frac), MOD.frac = 0.1; end
            MOD.frac = NMMLITools.clampFraction(MOD.frac, 0.1);
            if ~isfield(MOD,'MAP') || ~isstruct(MOD.MAP), MOD.MAP = struct(); end
            if ~isfield(MOD.MAP,'flag') || isempty(MOD.MAP.flag), MOD.MAP.flag = 0; end
            if ~isfield(MOD.MAP,'map') || isempty(MOD.MAP.map), MOD.MAP.map = 'cvr'; end
            if ~isfield(MOD.MAP,'cutoff') || isempty(MOD.MAP.cutoff), MOD.MAP.cutoff = [-2 2]; end
            if ~isfield(MOD.MAP,'percentmode') || isempty(MOD.MAP.percentmode), MOD.MAP.percentmode = 'absolute'; end
            if ~isfield(MOD.MAP,'operator') || isempty(MOD.MAP.operator), MOD.MAP.operator = 1; end
            MOD.MAP.flag = double(logical(MOD.MAP.flag));
            MOD.MAP.map = NMMLITools.allowedChar(MOD.MAP.map, 'cvr', {NMMLITools.MapChoices.symbol});
            MOD.MAP.cutoff = NMMLITools.numericVectorOrDefault(MOD.MAP.cutoff, [-2 2]);
            MOD.MAP.percentmode = NMMLITools.allowedChar(MOD.MAP.percentmode, 'absolute', {NMMLITools.PercentChoices.symbol});
            maxOp = 6;
            if numel(MOD.MAP.cutoff) > 1, maxOp = 4; end
            MOD.MAP.operator = NMMLITools.allowedScalar(MOD.MAP.operator, 1, 1:maxOp);

            if NMModalityInfoTools.isImaging(NM, varind)
                if ~isfield(MOD,'imgops') || ~isstruct(MOD.imgops), MOD.imgops = struct(); end
                if ~isfield(MOD.imgops,'flag') || isempty(MOD.imgops.flag), MOD.imgops.flag = 1; end
                if ~isfield(MOD.imgops,'atlasfile'), MOD.imgops.atlasfile = []; end
                if ~isfield(MOD.imgops,'atlasvec'), MOD.imgops.atlasvec = []; end
                if ~isfield(MOD.imgops,'atlasvec_unique'), MOD.imgops.atlasvec_unique = unique(MOD.imgops.atlasvec); end
                if ~isfield(MOD.imgops,'csvfile'), MOD.imgops.csvfile = []; end
                if ~isfield(MOD.imgops,'csvdelim') || isempty(MOD.imgops.csvdelim), MOD.imgops.csvdelim = 'space'; end
                if ~isfield(MOD.imgops,'csvid') || isempty(MOD.imgops.csvid), MOD.imgops.csvid = 'ROIid'; end
                if ~isfield(MOD.imgops,'csvcol') || isempty(MOD.imgops.csvcol), MOD.imgops.csvcol = 'ROIdesc'; end
                if ~isfield(MOD.imgops,'csvdesc'), MOD.imgops.csvdesc = []; end
                if ~isfield(MOD.imgops,'csvnum'), MOD.imgops.csvnum = []; end
                MOD.imgops.flag = double(logical(MOD.imgops.flag));
                MOD.imgops.csvdelim = NMMLITools.allowedChar(MOD.imgops.csvdelim, 'space', {NMMLITools.DelimiterChoices.symbol});
                MOD.imgops.csvid = char(string(MOD.imgops.csvid));
                MOD.imgops.csvcol = char(string(MOD.imgops.csvcol));
                if isempty(MOD.imgops.atlasvec)
                    MOD.imgops.atlasvec_unique = [];
                else
                    MOD.imgops.atlasvec_unique = unique(MOD.imgops.atlasvec);
                end
            else
                MOD.imgops = [];
            end
            MLI.Modality{M} = MOD;
        end

        function state = stateFromMLI(MLI, NM, varind, fusionFlag, normalized)
            % stateFromMLI  Project a legacy MLI branch into browser/API state.
            %
            % The public four-argument form accepts an unnormalized legacy branch. Internal
            % callers may pass normalized=true after an authoritative normalization boundary.
            if nargin < 2 || isempty(NM), NM = struct(); end
            if nargin < 3 || isempty(varind), varind = 1; end
            if nargin < 5 || isempty(normalized) || ~logical(normalized)
                MLI = NMMLITools.completeDefaults(MLI, NM, varind, fusionFlag);
            end
            M = NMMLITools.modalityIndex(varind, fusionFlag);
            MOD = MLI.Modality{M};
            state = struct();
            state.mliScope = NMMLITools.scopeLabel(NM, varind, fusionFlag);
            state.mliActiveModality = double(varind);
            state.mliModalityIndex = double(M);
            state.mliIsImaging = NMModalityInfoTools.isImaging(NM, varind);
            state.mliModalityLabel = NMMLITools.modalityLabel(NM, varind);
            state.mliMethod = char(MLI.method);
            state.mliNPermsText = NMMLITools.iterText(MLI.nperms);
            state.mliNPermsIsInf = isinf(MLI.nperms);
            state.mliMaxIter = double(MLI.max_iter);
            state.mliNVisited = double(MLI.n_visited);
            state.mliUpperThresh = double(MLI.upper_thresh);
            state.mliLowerThresh = double(MLI.lower_thresh);
            state.mliFeatureFrac = double(MOD.frac);
            state.mliSampleFrac = double(MLI.frac);
            state.mliZNormData = double(MLI.znormdata);
            state.mliMapFlag = logical(MOD.MAP.flag);
            state.mliMapMap = char(MOD.MAP.map);
            state.mliMapCutoffText = NMMLITools.vectorText(MOD.MAP.cutoff);
            state.mliMapPercentMode = char(MOD.MAP.percentmode);
            state.mliMapOperator = double(MOD.MAP.operator);
            if state.mliIsImaging
                io = MOD.imgops;
                state.mliAtlasFlag = logical(io.flag);
                state.mliAtlasFile = NMMLITools.pathText(io.atlasfile);
                state.mliAtlasVectorN = double(numel(io.atlasvec));
                state.mliAtlasUniqueCount = double(numel(io.atlasvec_unique));
                state.mliAtlasImported = ~isempty(io.atlasvec);
                state.mliAtlasImportSummary = NMMLITools.atlasSummary(io);
                state.mliCsvFile = NMMLITools.pathText(io.csvfile);
                state.mliCsvDelim = char(io.csvdelim);
                state.mliCsvId = char(io.csvid);
                state.mliCsvCol = char(io.csvcol);
                state.mliCsvImported = isfield(io,'T') && ~isempty(io.T) && ~isempty(io.csvnum) && ~isempty(io.csvdesc);
                state.mliCsvNumCount = double(numel(io.csvnum));
                state.mliCsvDescCount = double(numel(io.csvdesc));
                state.mliCsvImportSummary = NMMLITools.csvSummary(io);
            else
                state.mliAtlasFlag = false;
                state.mliAtlasFile = '';
                state.mliAtlasVectorN = 0;
                state.mliAtlasUniqueCount = 0;
                state.mliAtlasImported = false;
                state.mliAtlasImportSummary = 'Atlas binding is available only for imaging modalities.';
                state.mliCsvFile = '';
                state.mliCsvDelim = 'space';
                state.mliCsvId = 'ROIid';
                state.mliCsvCol = 'ROIdesc';
                state.mliCsvImported = false;
                state.mliCsvNumCount = 0;
                state.mliCsvDescCount = 0;
                state.mliCsvImportSummary = '';
            end
        end

        function state = stateFromMenu(NM, current, menuState, varind, fusionFlag)
            % stateFromMenu  Translate browser ML-interpretation controls into normalized state.
            %
            % Combines current state with UI selections and marks the branch dirty when values change. The method prepares state for applyToNM and does not directly modify NM.
            if nargin < 2 || isempty(current) || ~isstruct(current)
                current = NMMLITools.stateFromNM(NM, varind, fusionFlag);
            end
            if nargin < 4 || isempty(varind), varind = 1; end
            state = current;
            if isfield(menuState,'mli') && isstruct(menuState.mli)
                src = menuState.mli;
            else
                src = menuState;
            end
            if ~isstruct(src), state = NMMLITools.normalizeState(NM, state, varind, fusionFlag); return; end
            if isfield(src,'mliActiveModality') && ~isempty(src.mliActiveModality)
                try
                    if round(double(src.mliActiveModality)) ~= round(double(varind))
                        state = NMMLITools.stateFromNM(NM, varind, fusionFlag);
                        return;
                    end
                catch
                end
            end
            fn = fieldnames(src);
            for i = 1:numel(fn)
                if startsWith(fn{i}, 'mli')
                    state.(fn{i}) = src.(fn{i});
                end
            end
            state = NMMLITools.normalizeState(NM, state, varind, fusionFlag);
        end

        function state = normalizeState(NM, state, varind, fusionFlag)
            % normalizeState  Enforce valid ML-interpretation state values before legacy materialization.
            %
            % Coerces booleans/enums/numeric options, repairs invalid or unavailable choices and derives context-sensitive defaults. applyToNM expects this normalized state.
            %
            % state.mliDirty: carries the mli dirty value between browser/API state and legacy NeuroMiner structures.
            % state.mliPresent: carries the mli present value between browser/API state and legacy NeuroMiner structures.
            % state.mliScope: carries the mli scope value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            MLI = NMMLITools.mliFromState(NM, state, varind, fusionFlag);
            keepPresent = isfield(state,'mliPresent') && logical(state.mliPresent);
            keepDirty = isfield(state,'mliDirty') && logical(state.mliDirty);
            state = NMMLITools.stateFromMLI(MLI, NM, varind, fusionFlag, true);
            state.mliPresent = keepPresent;
            state.mliDirty = keepDirty;
            state.mliScope = NMMLITools.scopeLabel(NM, varind, fusionFlag);
        end

        function MLI = mliFromState(NM, state, varind, fusionFlag)
            % mliFromState  Convert normalized ML-interpretation state into legacy MLI struct.
            %
            % Builds the backend NM.TrainParam.MLI branch consumed by ML-interpretation routines, including modality/fusion-dependent resource fields. Browser-only fields such as dirty flags and preview text are omitted.
            %
            % state.mliAtlasFile: carries the mli atlas file value between browser/API state and legacy NeuroMiner structures.
            % state.mliAtlasFlag: carries the mli atlas flag value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvCol: carries the mli csv col value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvDelim: carries the mli csv delim value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvFile: carries the mli csv file value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvId: carries the mli csv id value between browser/API state and legacy NeuroMiner structures.
            % state.mliFeatureFrac: carries the mli feature frac value between browser/API state and legacy NeuroMiner structures.
            % state.mliLowerThresh: carries the mli lower thresh value between browser/API state and legacy NeuroMiner structures.
            % state.mliMapCutoffText: carries the mli map cutoff text value between browser/API state and legacy NeuroMiner structures.
            % state.mliMapFlag: carries the mli map flag value between browser/API state and legacy NeuroMiner structures.
            % state.mliMapMap: carries the mli map map value between browser/API state and legacy NeuroMiner structures.
            % state.mliMapOperator: carries the mli map operator value between browser/API state and legacy NeuroMiner structures.
            % state.mliMapPercentMode: carries the mli map percent mode value between browser/API state and legacy NeuroMiner structures.
            % state.mliMaxIter: carries the mli max iter value between browser/API state and legacy NeuroMiner structures.
            % state.mliMethod: carries the mli method value between browser/API state and legacy NeuroMiner structures.
            % state.mliNPermsText: carries the mli nperms text value between browser/API state and legacy NeuroMiner structures.
            % state.mliNVisited: carries the mli nvisited value between browser/API state and legacy NeuroMiner structures.
            % state.mliSampleFrac: carries the mli sample frac value between browser/API state and legacy NeuroMiner structures.
            % state.mliUpperThresh: carries the mli upper thresh value between browser/API state and legacy NeuroMiner structures.
            % state.mliZNormData: carries the mli znorm data value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state), state = struct(); end
            if nargin < 3 || isempty(varind), varind = 1; end
            [base, ~] = NMMLITools.extractLegacyMLI(NM, varind, fusionFlag);
            MLI = NMMLITools.completeDefaults(base, NM, varind, fusionFlag);
            M = NMMLITools.modalityIndex(varind, fusionFlag);
            if isfield(state,'mliMethod'), MLI.method = NMMLITools.allowedChar(state.mliMethod, MLI.method, {'posneg','median','medianflip','medianmirror','random','shapley'}); end
            if isfield(state,'mliNPermsText'), MLI.nperms = NMMLITools.iterOrInf(state.mliNPermsText, MLI.nperms); end
            if isfield(state,'mliMaxIter'), MLI.max_iter = max(1, round(NMMLITools.scalarOrDefault(state.mliMaxIter, MLI.max_iter))); end
            if isfield(state,'mliNVisited'), MLI.n_visited = max(1, round(NMMLITools.scalarOrDefault(state.mliNVisited, MLI.n_visited))); end
            if isfield(state,'mliUpperThresh'), MLI.upper_thresh = NMMLITools.scalarOrDefault(state.mliUpperThresh, MLI.upper_thresh); end
            if isfield(state,'mliLowerThresh'), MLI.lower_thresh = NMMLITools.scalarOrDefault(state.mliLowerThresh, MLI.lower_thresh); end
            if isfield(state,'mliSampleFrac'), MLI.frac = NMMLITools.clampFraction(state.mliSampleFrac, MLI.frac); end
            if isfield(state,'mliZNormData'), MLI.znormdata = NMMLITools.allowedScalar(state.mliZNormData, MLI.znormdata, 1:4); end
            MOD = MLI.Modality{M};
            if isfield(state,'mliFeatureFrac'), MOD.frac = NMMLITools.clampFraction(state.mliFeatureFrac, MOD.frac); end
            if isfield(state,'mliMapFlag'), MOD.MAP.flag = double(logical(state.mliMapFlag)); end
            if isfield(state,'mliMapMap'), MOD.MAP.map = NMMLITools.allowedChar(state.mliMapMap, MOD.MAP.map, {'cvr','p_sgn','p_FDR_sgn'}); end
            if isfield(state,'mliMapCutoffText'), MOD.MAP.cutoff = NMMLITools.numericVectorOrDefault(state.mliMapCutoffText, MOD.MAP.cutoff); end
            if isfield(state,'mliMapPercentMode'), MOD.MAP.percentmode = NMMLITools.allowedChar(state.mliMapPercentMode, MOD.MAP.percentmode, {'absolute','percentile'}); end
            maxOp = 6;
            if numel(MOD.MAP.cutoff) > 1, maxOp = 4; end
            if isfield(state,'mliMapOperator'), MOD.MAP.operator = NMMLITools.allowedScalar(state.mliMapOperator, MOD.MAP.operator, 1:maxOp); end
            if NMModalityInfoTools.isImaging(NM, varind)
                if ~isfield(MOD,'imgops') || ~isstruct(MOD.imgops), MOD.imgops = struct(); end
                if isfield(state,'mliAtlasFlag'), MOD.imgops.flag = double(logical(state.mliAtlasFlag)); end
                if isfield(state,'mliAtlasFile')
                    newAtlas = NMMLITools.cleanPath(state.mliAtlasFile);
                    oldAtlas = NMMLITools.cleanPath(MOD.imgops.atlasfile);
                    if ~strcmpi(newAtlas, oldAtlas)
                        MOD.imgops.atlasvec = [];
                        MOD.imgops.atlasvec_unique = [];
                    end
                    MOD.imgops.atlasfile = newAtlas;
                end
                if isfield(state,'mliCsvFile'), MOD.imgops.csvfile = NMMLITools.cleanPath(state.mliCsvFile); end
                if isfield(state,'mliCsvDelim'), MOD.imgops.csvdelim = NMMLITools.allowedChar(state.mliCsvDelim, 'space', {';',',','tab','space'}); end
                if isfield(state,'mliCsvId')
                    MOD.imgops.csvid = char(string(state.mliCsvId));
                    if isempty(MOD.imgops.csvid), MOD.imgops.csvid = 'ROIid'; end
                end
                if isfield(state,'mliCsvCol')
                    MOD.imgops.csvcol = char(string(state.mliCsvCol));
                    if isempty(MOD.imgops.csvcol), MOD.imgops.csvcol = 'ROIdesc'; end
                end
                if ~isfield(MOD.imgops,'atlasvec') || isempty(MOD.imgops.atlasvec)
                    MOD.imgops.atlasvec_unique = [];
                else
                    MOD.imgops.atlasvec_unique = unique(MOD.imgops.atlasvec);
                end
            else
                MOD.imgops = [];
            end
            MLI.Modality{M} = MOD;
        end

        function NM = applyToNM(NM, state, varind, fusionFlag)
            % applyToNM  Materialize ML-interpretation settings into the NM training template.
            %
            % Writes the normalized configuration to NM.TrainParam.MLI at the correct global or modality-specific location. This is the public writer for the branch and preserves browser-only metadata outside the legacy NM structure.
            %
            % state.mliDirty: carries the mli dirty value between browser/API state and legacy NeuroMiner structures.
            % state.mliPresent: carries the mli present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(state) || ~isstruct(state), return; end
            if nargin < 3 || isempty(varind), varind = 1; end
            present = isfield(state,'mliPresent') && logical(state.mliPresent);
            dirty = isfield(state,'mliDirty') && logical(state.mliDirty);
            if ~(present || dirty), return; end
            MLI = NMMLITools.mliFromState(NM, state, varind, fusionFlag);
            NM = NMMLITools.applyLegacyToNM(NM, MLI, varind, fusionFlag);
        end

        function NM = applyLegacyToNM(NM, MLI, varind, fusionFlag)
            % applyLegacyToNM  Store a fully materialized legacy MLI struct in NM without.
            %
            % rebuilding it from the flattened browser state. This is required
            % for immediate atlas/descriptor imports because atlasvec,
            % atlasvec_unique, csvnum, csvdesc, and T are backend objects that
            % are intentionally not serialized through the JSON UI state.
            if nargin < 1 || isempty(NM), NM = struct(); end
            if nargin < 2 || isempty(MLI) || ~isstruct(MLI), return; end
            if nargin < 3 || isempty(varind), varind = 1; end
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), NM.TrainParam = struct(); end
            MLI = NMMLITools.completeDefaults(MLI, NM, varind, fusionFlag);
            if round(double(fusionFlag)) == 3
                if ~isfield(NM.TrainParam,'STRAT') || ~iscell(NM.TrainParam.STRAT)
                    NM.TrainParam.STRAT = cell(1, max(1,varind));
                end
                if numel(NM.TrainParam.STRAT) < varind, NM.TrainParam.STRAT{varind} = []; end
                if isempty(NM.TrainParam.STRAT{varind}) || ~isstruct(NM.TrainParam.STRAT{varind})
                    NM.TrainParam.STRAT{varind} = struct();
                end
                NM.TrainParam.STRAT{varind}.MLI = MLI;
            else
                NM.TrainParam.MLI = MLI;
            end
        end

        function [state, MLI] = importAtlasFile(NM, state, varind, fusionFlag, atlasFile)
            % importAtlasFile  Import an atlas resource for ML-interpretation and update MLI state.
            %
            % Validates the selected atlas path, performs the MATLAB-side resource import needed by legacy MLI code, and returns both updated browser state and legacy MLI fields. This service call does not wait for browser shutdown to do vectorization work.
            %
            % state.mliAtlasFile: carries the mli atlas file value between browser/API state and legacy NeuroMiner structures.
            % state.mliDirty: carries the mli dirty value between browser/API state and legacy NeuroMiner structures.
            % state.mliPresent: carries the mli present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            if nargin < 5 || isempty(atlasFile)
                if isfield(state,'mliAtlasFile'), atlasFile = state.mliAtlasFile; else, atlasFile = ''; end
            end
            atlasFile = NMMLITools.cleanPath(atlasFile);
            if isempty(atlasFile) || exist(atlasFile,'file') ~= 2
                error('NMMLITools:atlasFileNotFound', 'Atlas imaging file not found: %s', atlasFile);
            end
            if ~NMModalityInfoTools.isImaging(NM, varind)
                error('NMMLITools:notImaging', 'Atlas binding is available only for imaging modalities.');
            end
            MLI = NMMLITools.mliFromState(NM, state, varind, fusionFlag);
            M = NMMLITools.modalityIndex(varind, fusionFlag);
            imgtype = NMMLITools.imageType(NM, varind);
            switch lower(char(imgtype))
                case {'spm','nifti'}
                    if ~NMMLITools.functionExists('spm_vol')
                        error('NMMLITools:noSPM', 'SPM is required to import NIfTI/SPM atlas images.');
                    end
                    if ~NMMLITools.functionExists('nk_ReturnSubSpaces')
                        error('NMMLITools:noReturnSubSpaces', 'nk_ReturnSubSpaces is required to vectorize atlas images in the active NM mask.');
                    end
                    F = atlasFile;
                    if NMMLITools.functionExists('nk_CheckComprFile')
                        F = nk_CheckComprFile(F);
                    end
                    V0 = spm_vol(F);
                    brainmask = NMMLITools.resolveBrainmask(NM, varind);
                    Vm = spm_vol(brainmask);
                    Thresh = NMMLITools.resolveThreshold(NM, varind);
                    avec = round(nk_ReturnSubSpaces({V0}, Vm, 1, 1, Thresh),0);
                case 'surf'
                    if NMMLITools.functionExists('SurfaceReader')
                        V0 = SurfaceReader(atlasFile);
                        if isfield(V0,'cdata'), avec = V0.cdata; else, avec = V0; end
                    elseif NMMLITools.functionExists('MRIread')
                        V0 = MRIread(atlasFile);
                        if isstruct(V0) && isfield(V0,'vol'), avec = V0.vol;
                        elseif isstruct(V0) && isfield(V0,'cdata'), avec = V0.cdata;
                        else, avec = V0;
                        end
                    else
                        error('NMMLITools:noSurfaceReader', 'Surface atlas import requires SurfaceReader or MRIread on the MATLAB path.');
                    end
                    avec = round(avec,0);
                otherwise
                    error('NMMLITools:badImageType', 'Unsupported atlas image type: %s.', char(imgtype));
            end
            if iscell(avec), avec = avec{1}; end
            avec = avec(:)';
            MLI.Modality{M}.imgops.flag = 1;
            MLI.Modality{M}.imgops.atlasfile = atlasFile;
            MLI.Modality{M}.imgops.atlasvec = avec;
            MLI.Modality{M}.imgops.atlasvec_unique = unique(avec);
            state = NMMLITools.stateFromMLI(MLI, NM, varind, fusionFlag, true);
            state.mliPresent = true;
            state.mliDirty = true;
        end

        function [state, MLI] = importDescriptorFile(NM, state, varind, fusionFlag, csvFile)
            % importDescriptorFile  Import an atlas descriptor table for ML-interpretation.
            %
            % Reads the selected descriptor CSV, validates its mapping to the current MLI atlas context and updates state/legacy MLI metadata used by downstream ML-interpretation displays.
            %
            % state.mliCsvCol: carries the mli csv col value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvDelim: carries the mli csv delim value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvFile: carries the mli csv file value between browser/API state and legacy NeuroMiner structures.
            % state.mliCsvId: carries the mli csv id value between browser/API state and legacy NeuroMiner structures.
            % state.mliDirty: carries the mli dirty value between browser/API state and legacy NeuroMiner structures.
            % state.mliPresent: carries the mli present value between browser/API state and legacy NeuroMiner structures.
            if nargin < 3 || isempty(varind), varind = 1; end
            if nargin < 5 || isempty(csvFile)
                if isfield(state,'mliCsvFile'), csvFile = state.mliCsvFile; else, csvFile = ''; end
            end
            csvFile = NMMLITools.cleanPath(csvFile);
            if isempty(csvFile) || exist(csvFile,'file') ~= 2
                error('NMMLITools:descriptorFileNotFound', 'Atlas descriptor file not found: %s', csvFile);
            end
            if ~NMModalityInfoTools.isImaging(NM, varind)
                error('NMMLITools:notImaging', 'Atlas descriptors are available only for imaging modalities.');
            end
            MLI = NMMLITools.mliFromState(NM, state, varind, fusionFlag);
            M = NMMLITools.modalityIndex(varind, fusionFlag);
            io = MLI.Modality{M}.imgops;
            if isfield(state,'mliCsvDelim'), io.csvdelim = NMMLITools.allowedChar(state.mliCsvDelim, io.csvdelim, {';',',','tab','space'}); end
            if isfield(state,'mliCsvId'), io.csvid = char(string(state.mliCsvId)); end
            if isfield(state,'mliCsvCol'), io.csvcol = char(string(state.mliCsvCol)); end
            T = readtable(csvFile, 'Delimiter', io.csvdelim);
            cols = T.Properties.VariableNames;
            coltxt = NMMLITools.columnListText(cols);
            if ~ismember(io.csvid, cols)
                error('NMMLITools:descriptorMissingId', ...
                    'Column ''%s'' was not found in the atlas descriptor table. Available MATLAB table columns with delimiter ''%s'': %s', ...
                    io.csvid, io.csvdelim, coltxt);
            end
            if ~ismember(io.csvcol, cols)
                error('NMMLITools:descriptorMissingLabel', ...
                    'Column ''%s'' was not found in the atlas descriptor table. Available MATLAB table columns with delimiter ''%s'': %s', ...
                    io.csvcol, io.csvdelim, coltxt);
            end
            io.csvfile = csvFile;
            io.T = T;
            io.csvnum = T.(io.csvid);
            io.csvdesc = T.(io.csvcol);
            io.flag = 1;
            MLI.Modality{M}.imgops = io;
            state = NMMLITools.stateFromMLI(MLI, NM, varind, fusionFlag, true);
            state.mliPresent = true;
            state.mliDirty = true;
        end

        function state = previewDescriptorFile(csvFile, delim, maxLines)
            % previewDescriptorFile  Read a small preview of an MLI atlas-descriptor CSV file.
            %
            % Parses the file header and a bounded number of rows for browser inspection before import. It is read-only and does not alter NM or the active MLI branch.
            if nargin < 2 || isempty(delim), delim = 'space'; end
            if nargin < 3 || isempty(maxLines), maxLines = 2; end
            csvFile = NMMLITools.cleanPath(csvFile);
            if isempty(csvFile) || exist(csvFile,'file') ~= 2
                error('NMMLITools:descriptorFileNotFound', 'Atlas descriptor file not found: %s', csvFile);
            end
            delim = NMMLITools.allowedChar(delim, 'space', {NMMLITools.DelimiterChoices.symbol});
            raw = NMMLITools.firstTextLines(csvFile, maxLines);
            rawCols = {};
            if ~isempty(raw)
                rawCols = NMMLITools.splitPreviewLine(raw{1}, delim);
            end
            tableCols = {};
            tableErr = '';
            try
                T = readtable(csvFile, 'Delimiter', delim);
                tableCols = T.Properties.VariableNames;
            catch ME
                tableErr = ME.message;
            end
            state = struct();
            state.mliCsvFile = csvFile;
            state.mliCsvDelim = delim;
            state.mliCsvPreviewRawLines = raw;
            state.mliCsvPreviewRawColumns = rawCols;
            state.mliCsvPreviewTableColumns = tableCols;
            state.mliCsvPreviewReadError = tableErr;
            state.mliCsvPreviewSummary = NMMLITools.descriptorPreviewSummary(csvFile, delim, raw, rawCols, tableCols, tableErr);
        end

        function text = summary(state)
            % summary  Render a concise human-readable ML-interpretation configuration summary.
            %
            % Uses the normalized state to produce text for browser cards, logs or diagnostic reports. It is read-only and should not be used as a source of backend configuration.
            if nargin < 1 || isempty(state) || ~isstruct(state)
                text = 'Interpretable ML parameters are not configured.';
                return;
            end
            method = NMMLITools.methodLabel(NMMLITools.getField(state,'mliMethod','posneg'));
            parts = {method};
            if NMMLITools.getLogical(state,'mliMapFlag',false)
                parts{end+1} = sprintf('map-restricted: %s', char(NMMLITools.getField(state,'mliMapMap','cvr'))); %#ok<AGROW>
            end
            if NMMLITools.getLogical(state,'mliIsImaging',false) && NMMLITools.getLogical(state,'mliAtlasFlag',false)
                if NMMLITools.getLogical(state,'mliAtlasImported',false)
                    parts{end+1} = sprintf('atlas-bound (%g regions)', double(NMMLITools.getField(state,'mliAtlasUniqueCount',0))); %#ok<AGROW>
                else
                    parts{end+1} = 'atlas-bound, atlas not imported'; %#ok<AGROW>
                end
            end
            if NMMLITools.getLogical(state,'mliNPermsIsInf',false)
                parts{end+1} = 'automated stopping'; %#ok<AGROW>
            else
                parts{end+1} = sprintf('%s iterations', char(NMMLITools.getField(state,'mliNPermsText','1024'))); %#ok<AGROW>
            end
            text = strjoin(parts, '; ');
            text = [upper(text(1)) text(2:end) '.'];
        end

    end

    methods (Static, Access = private)
        function [MLI, present] = extractLegacyMLI(NM, varind, fusionFlag)
            MLI = struct(); present = false;
            if ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam), return; end
            TP = NM.TrainParam;
            if round(double(fusionFlag)) == 3 && isfield(TP,'STRAT') && iscell(TP.STRAT) && numel(TP.STRAT) >= varind && ...
                    isstruct(TP.STRAT{varind}) && isfield(TP.STRAT{varind},'MLI') && isstruct(TP.STRAT{varind}.MLI)
                MLI = TP.STRAT{varind}.MLI; present = true; return;
            end
            if isfield(TP,'MLI') && isstruct(TP.MLI)
                MLI = TP.MLI; present = true;
            end
        end


        function M = modalityIndex(varind, fusionFlag)
            if round(double(fusionFlag)) == 3
                M = 1;
            else
                M = max(1, round(double(varind)));
            end
        end

        function label = modalityLabel(NM, varind)
            label = sprintf('Modality #%d', varind);
            if isfield(NM,'datadescriptor') && iscell(NM.datadescriptor) && numel(NM.datadescriptor) >= varind && ...
                    isstruct(NM.datadescriptor{varind}) && isfield(NM.datadescriptor{varind},'desc') && ~isempty(NM.datadescriptor{varind}.desc)
                label = sprintf('#%d: %s', varind, char(NM.datadescriptor{varind}.desc));
            end
        end

        function scope = scopeLabel(NM, varind, fusionFlag)
            if round(double(fusionFlag)) == 3
                scope = sprintf('NM.TrainParam.STRAT{%d}.MLI.Modality{1}', varind);
            else
                scope = sprintf('NM.TrainParam.MLI.Modality{%d}', varind);
            end
        end

        function val = allowedChar(val, default, allowed)
            if isempty(val), val = default; return; end
            val = char(string(val));
            if ~any(strcmpi(val, allowed)), val = default; return; end
            idx = find(strcmpi(val, allowed), 1, 'first');
            val = allowed{idx};
        end

        function val = allowedScalar(val, default, allowed)
            val = round(double(NMMLITools.scalarOrDefault(val, default)));
            if ~isfinite(val) || ~ismember(val, allowed), val = default; end
        end

        function val = scalarOrDefault(val, default)
            try
                if ischar(val) || isstring(val), val = str2double(char(val)); end
                val = double(val);
                if isempty(val), val = default; else, val = val(1); end
                if ~isfinite(val), val = default; end
            catch
                val = default;
            end
        end

        function val = iterOrInf(val, default)
            try
                if ischar(val) || isstring(val)
                    s = strtrim(char(val));
                    if any(strcmpi(s, {'inf','+inf','infinity'})), val = Inf; return; end
                    val = str2double(s);
                end
                val = double(val);
                if isempty(val), val = default; else, val = val(1); end
                if isnan(val) || val <= 0, val = default; end
                if ~isinf(val), val = max(1, round(val)); end
            catch
                val = default;
            end
        end

        function txt = iterText(val)
            if isinf(val), txt = 'Inf'; else, txt = sprintf('%g', double(val)); end
        end

        function val = clampFraction(val, default)
            val = NMMLITools.scalarOrDefault(val, default);
            if val <= 0 || val > 1, val = default; end
        end

        function vec = numericVectorOrDefault(val, default)
            try
                if ischar(val) || isstring(val)
                    s = char(val);
                    s = regexprep(s, '[\[\],;]', ' ');
                    parts = regexp(strtrim(s), '\s+', 'split');
                    parts(cellfun(@isempty, parts)) = [];
                    vec = cellfun(@str2double, parts);
                else
                    vec = double(val(:))';
                end
                vec = vec(isfinite(vec));
                if isempty(vec), vec = default; end
            catch
                vec = default;
            end
        end

        function txt = vectorText(vec)
            if isempty(vec), txt = ''; return; end
            try
                txt = strtrim(sprintf('%g ', double(vec(:))'));
            catch
                txt = '';
            end
        end

        function txt = pathText(p)
            if isempty(p), txt = ''; return; end
            try
                if iscell(p), p = p{1}; end
                txt = char(string(p));
            catch
                txt = '';
            end
        end

        function p = cleanPath(p)
            if isempty(p), p = ''; return; end
            if iscell(p), p = p{1}; end
            p = char(string(p));
            p = deblank(p);
            if size(p,1) > 1, p = deblank(p(1,:)); end
            p = regexprep(p, ',\d+$', '');
        end

        function txt = atlasSummary(io)
            try
                if ~isfield(io,'atlasfile') || isempty(io.atlasfile)
                    txt = 'No atlas image imported.'; return;
                end
                [~,nm,ext] = fileparts(char(io.atlasfile));
                if isfield(io,'atlasvec') && ~isempty(io.atlasvec)
                    txt = sprintf('%s%s imported: %g features, %g unique atlas labels.', nm, ext, numel(io.atlasvec), numel(unique(io.atlasvec)));
                else
                    txt = sprintf('%s%s selected, not yet imported.', nm, ext);
                end
            catch
                txt = 'Atlas import status unavailable.';
            end
        end

        function txt = csvSummary(io)
            try
                if ~isfield(io,'csvfile') || isempty(io.csvfile)
                    txt = 'No atlas descriptor file imported.'; return;
                end
                [~,nm,ext] = fileparts(char(io.csvfile));
                if isfield(io,'csvnum') && ~isempty(io.csvnum) && isfield(io,'csvdesc') && ~isempty(io.csvdesc)
                    txt = sprintf('%s%s imported: %g ROI IDs and %g descriptors.', nm, ext, numel(io.csvnum), numel(io.csvdesc));
                else
                    txt = sprintf('%s%s selected, descriptor columns not imported.', nm, ext);
                end
            catch
                txt = 'Atlas descriptor import status unavailable.';
            end
        end

        function txt = descriptorPreviewSummary(csvFile, delim, raw, rawCols, tableCols, tableErr)
            [~,nm,ext] = fileparts(char(csvFile));
            lines = {sprintf('Descriptor preview: %s%s', nm, ext), sprintf('Delimiter: %s', char(delim))};
            if isempty(raw)
                lines{end+1} = 'First two raw lines: <file is empty or unreadable>'; %#ok<AGROW>
            else
                lines{end+1} = 'First two raw lines:'; %#ok<AGROW>
                for i = 1:numel(raw)
                    lines{end+1} = sprintf('%d: %s', i, NMMLITools.truncateText(raw{i}, 400)); %#ok<AGROW>
                end
            end
            if ~isempty(rawCols)
                lines{end+1} = sprintf('Raw header tokens with current delimiter: %s', NMMLITools.columnListText(rawCols)); %#ok<AGROW>
            end
            if ~isempty(tableCols)
                lines{end+1} = sprintf('MATLAB table column names: %s', NMMLITools.columnListText(tableCols)); %#ok<AGROW>
            elseif ~isempty(tableErr)
                lines{end+1} = sprintf('readtable preview error: %s', NMMLITools.truncateText(tableErr, 500)); %#ok<AGROW>
            end
            txt = strjoin(lines, newline);
        end

        function lines = firstTextLines(filePath, maxLines)
            lines = {};
            fid = fopen(filePath, 'r');
            if fid < 0
                error('NMMLITools:descriptorOpenFailed', 'Could not open atlas descriptor file: %s', filePath);
            end
            cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
            for i = 1:maxLines
                t = fgetl(fid);
                if ~ischar(t), break; end
                lines{end+1} = t; %#ok<AGROW>
            end
        end

        function cols = splitPreviewLine(line, delim)
            line = char(string(line));
            switch char(delim)
                case 'tab'
                    cols = regexp(line, '\t', 'split');
                case 'space'
                    cols = regexp(strtrim(line), '\s+', 'split');
                otherwise
                    cols = regexp(line, regexptranslate('escape', char(delim)), 'split');
            end
            cols = cols(~cellfun(@isempty, cols));
        end

        function txt = columnListText(cols)
            if isempty(cols), txt = '<none>'; return; end
            if isstring(cols), cols = cellstr(cols); end
            if isnumeric(cols), cols = arrayfun(@num2str, cols, 'UniformOutput', false); end
            try
                cols = cellfun(@char, cols(:)', 'UniformOutput', false);
            catch
                cols = {'<unavailable>'};
            end
            if numel(cols) > 20
                cols = [cols(1:20) {sprintf('... +%d more', numel(cols)-20)}];
            end
            txt = strjoin(cols, ', ');
        end

        function txt = truncateText(txt, n)
            txt = char(string(txt));
            if numel(txt) > n
                txt = [txt(1:n) ' ...'];
            end
        end

        function imgtype = imageType(NM, varind)
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind}) || ~isfield(NM.datadescriptor{varind},'input_settings') || ...
                    ~isstruct(NM.datadescriptor{varind}.input_settings) || ...
                    ~isfield(NM.datadescriptor{varind}.input_settings,'datasource') || ...
                    isempty(NM.datadescriptor{varind}.input_settings.datasource)
                error('NMMLITools:missingDatasource', ...
                    'MLI atlas import requires NM.datadescriptor{%d}.input_settings.datasource.', varind);
            end
            dd = NM.datadescriptor{varind};
            imgtype = lower(char(dd.input_settings.datasource));
            if ~any(strcmp(imgtype, {'spm','nifti','surf'}))
                error('NMMLITools:badImageType', ...
                    'Unsupported imaging datasource for MLI atlas import: %s.', imgtype);
            end
        end

        function brainmask = resolveBrainmask(NM, varind)
            if ~isfield(NM,'brainmask') || ~iscell(NM.brainmask) || numel(NM.brainmask) < varind || isempty(NM.brainmask{varind})
                error('NMMLITools:noBrainmask', ...
                    'Vectorizing an atlas image requires NM.brainmask{%d}.', varind);
            end
            brainmask = NMMLITools.cleanPath(NM.brainmask{varind});
        end

        function Thresh = resolveThreshold(NM, varind)
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || numel(NM.datadescriptor) < varind || ...
                    ~isstruct(NM.datadescriptor{varind}) || ~isfield(NM.datadescriptor{varind},'input_settings') || ...
                    ~isstruct(NM.datadescriptor{varind}.input_settings) || ...
                    ~isfield(NM.datadescriptor{varind}.input_settings,'Thresh')
                error('NMMLITools:missingThreshold', ...
                    'MLI atlas import requires NM.datadescriptor{%d}.input_settings.Thresh.', varind);
            end
            Thresh = NM.datadescriptor{varind}.input_settings.Thresh;
        end

        function tf = functionExists(name)
            tf = exist(name, 'file') == 2 || exist(name, 'builtin') == 5;
        end

        function label = methodLabel(method)
            switch char(method)
                case 'posneg', label = 'Upper/lower percentile occlusion';
                case 'median', label = 'Median occlusion';
                case 'medianflip', label = 'Median-span flip occlusion';
                case 'medianmirror', label = 'Median-mirror occlusion';
                case 'random', label = 'Random-value occlusion';
                case 'shapley', label = 'Shapley values';
                otherwise, label = char(method);
            end
        end

        function v = getField(s, name, default)
            if isstruct(s) && isfield(s,name), v = s.(name); else, v = default; end
        end

        function tf = getLogical(s, name, default)
            if isstruct(s) && isfield(s,name), tf = logical(s.(name)); else, tf = default; end
        end
    end
end
