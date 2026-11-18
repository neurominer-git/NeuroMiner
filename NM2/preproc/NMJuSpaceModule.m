classdef NMJuSpaceModule < NMPreprocModule
% NMJuSpaceModule
% -------------------------------------------------------------------------
% Dual-stage adapter for JuSpace neuromap co-localisation. The module can be
% selected either before CV splitting or inside the CV-bound pipeline, but
% only once globally. Resource installation/download is deliberately kept in
% nk_Utilities; this module only stores parameter choices and exports the
% legacy JUSPACE structure.
% -------------------------------------------------------------------------

    methods
        function obj = NMJuSpaceModule()
            % NMJuSpaceModule  Construct the JuSpace neuromap correlations preprocessing adapter.
            %   Registers module id 'JuSpace' with legacy branch 'JUSPACE' and sets
            %   capability/sequence flags used by NMModuleRegistry, NMPreprocRuleSet,
            %   NMPreprocSequence, and UI/API schema generation.

            obj@NMPreprocModule('JuSpace','JUSPACE','JuSpace neuromap correlations');
            obj.Category = 'imaging-preprocessing';
            obj.Aliases = {'juspace','neuromap','neuromaps'};
            obj.Capabilities.executionStages = {'subject','cv'};
            obj.Capabilities.imagingOnly = true;
            obj.Capabilities.requiresImageSpace = true;
            obj.Capabilities.isImageSpaceTerminal = true;
            obj.Capabilities.requiresSpatialFeatureExtractionAllowed = true;
            obj.Capabilities.spatialFeatureExtractionFlagEffect = 'disable';
            obj.Capabilities.invalidatesImageSpace = true;
            obj.Capabilities.isSpatialFeatureExtractor = true;
            obj.Capabilities.isDimensionalityReductionLike = true;
            obj.Capabilities.uniqueAcrossStages = true;
            obj.Capabilities.changesFeatureSpace = true;
            obj.Capabilities.requiresJuSpaceDirectory = true;
            obj.Capabilities.legacySubjectTarget = 'PREPROC.SPATIAL';
            obj.Capabilities.legacyCVTarget = 'ACTPARAM';
            obj.Sequence.allowMultiple = false;
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return the canonical API/UI schema for JuSpace neuromap correlations.
            %   Defines editable fields for the module that computes JuSpace
            %   receptor/neurotransmitter-map correlations from imaging-derived features. The schema
            %   feeds defaultConfig, validateConfig, browser rendering, CLI/API help, and RAG
            %   documentation extraction.

            if nargin < 2 || isempty(ctx), ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            jsroot = obj.contextString(ctx,'juSpaceRoot','');
            if isempty(jsroot), jsroot = '<JuSpace directory not detected>'; end
            spec.description = ['Compute spatial correlations between subject maps and JuSpace/neuromaps brain maps. ', ...
                'Required JuSpace resources must be installed first. Atlas and brain-map paths are selected here; ', ...
                'resource preparation is completed before execution.'];
            readyRule = struct('all',{{struct('nonEmptyField','atlasPath'),struct('nonEmptyField','brainMapsDir')}});
            spec.fields = { ...
                struct('name','juSpaceRoot','type','readonly','default',jsroot,'label','Detected JuSpace directory', ...
                    'help','The module is available only when the JuSpace resources have been installed in NeuroMiner.'), ...
                struct('name','atlasPath','type','file_path','default','','label','Atlas image path(s)', ...
                    'selectorMode','file','multiple',true,'fileFilter','*.nii;*.nii.gz', ...
                    'help','Select one or more atlas NIfTI images used for regional summarization.'), ...
                struct('name','atlasNames','type','string','default','','label','Alternative atlas name(s)', ...
                    'visibleIf',struct('nonEmptyField','atlasPath'), ...
                    'help','Optional comma-separated labels for the selected atlas image(s).'), ...
                struct('name','brainMapsDir','type','directory_path','default',obj.defaultBrainMapsDir(ctx),'label','Brain maps directory', ...
                    'selectorMode','directory','multiple',false, ...
                    'help','Directory containing JuSpace/neuromaps NIfTI brain maps. The browser table is populated by scanning this directory.'), ...
                struct('name','scanStatus','type','readonly','default','','label','Brain-map scan status', ...
                    'visibleIf',struct('nonEmptyField','brainMapsDir'), ...
                    'help','Read-only status reported by the brain-map directory scan.'), ...
                struct('name','brainMapRows','type','juspace_brainmap_table','default',{{}},'label','Brain map selection', ...
                    'visibleIf',readyRule, ...
                    'help','Checked rows define the JuSpace brain maps used by this step; optional alternative names can be assigned.'), ...
                struct('name','availableBrainMaps','type','any','default',{{}},'label','Available brain-map rows','uiHidden',true, ...
                    'help','Read-only brain-map rows discovered in the selected brain-map directory.'), ...
                struct('name','brainMapNames','type','any','default',{{}},'label','Selected brain-map names','uiHidden',true, ...
                    'help','Retained names of the selected JuSpace brain maps.'), ...
                struct('name','correlationType','type','enum','default','spearman','label','Correlation type', ...
                    'visibleIf',readyRule, ...
                    'values',{{struct('value','spearman','label','Spearman correlation'),struct('value','pearson','label','Pearson correlation')}}, ...
                    'help','Choose Spearman rank correlation or Pearson correlation between subject maps and JuSpace reference maps.'), ...
                struct('name','adjustSpatialAutocorrelation','type','boolean','default',true,'label','Adjust for spatial autocorrelation', ...
                    'visibleIf',readyRule, ...
                    'help','Enable the inherited JuSpace spatial-autocorrelation correction; the optional TPM path applies when enabled.'), ...
                struct('name','tpmPath','type','file_path','default','','label','TPM image path', ...
                    'selectorMode','file','multiple',false,'fileFilter','*.nii;*.nii.gz', ...
                    'visibleIf',struct('all',{{readyRule,struct('field','adjustSpatialAutocorrelation','equals',true)}}), ...
                    'help','Optional tissue-probability image used when autocorrelation correction is enabled.'), ...
                struct('name','complete','type','boolean','default',false,'label','JuSpace import/precomputation complete', ...
                    'visibleIf',readyRule, ...
                    'help','Changing the atlas or brain-map selection normally requires resource preparation before execution.'), ...
                struct('name','legacyJUSPACE','type','struct','default',struct(),'label','Raw legacy JUSPACE structure','uiHidden',true, ...
                    'help','Preserved imported JUSPACE settings for legacy configuration round trips.'), ...
                struct('name','legacyPX','type','struct','default',struct(),'label','Raw legacy PX structure','uiHidden',true, ...
                    'help','Preserved imported PX parameters for legacy configuration round trips.') };
        end

        function legacy = toLegacy(obj, cfg, ctx) %#ok<INUSD>
            % toLegacy  Convert JuSpace neuromap correlations config to legacy preprocessing fields.
            %
            % Validates/normalizes canonical cfg and materializes legacy branch 'JUSPACE' for the
            % CV-bound PREPROC/ACTPARAM path consumed by legacy training backends.
            %
            % cfg.legacyPX: preserves legacy PX parameters when a module cannot yet express every field canonically.

            cfg = obj.validateOrError(cfg);
            J = obj.configToJUSPACE(cfg);
            legacy = struct('cmd',obj.Id,'JUSPACE',J);
            if isfield(cfg,'legacyPX') && isstruct(cfg.legacyPX) && ~isempty(fieldnames(cfg.legacyPX))
                legacy.PX = cfg.legacyPX;
            end
        end

        function legacy = toLegacySubject(obj, cfg, ctx)
            % toLegacySubject  Convert JuSpace configuration to a subject-level legacy SPATIAL step.
            %   Used for imaging-derived neuromap correlation workflows where spatial extraction
            %   occurs before CV ACTPARAM preprocessing.

            act = obj.toLegacy(cfg, ctx);
            legacy = struct();
            legacy.cmd = obj.Id;
            legacy.cubetype = uint8(5);
            legacy.JUSPACE = act.JUSPACE;
            if isfield(act,'PX'), legacy.PX = act.PX; end
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import legacy JuSpace neuromap correlations settings into canonical config form.
            %   Reads historical ACTPARAM/SPATIAL fields, preserves raw metadata where needed, and
            %   returns config suitable for UI display, API editing, and re-export.

            if nargin < 3, ctx = struct(); end %#ok<INUSD>
            cfg = obj.defaultConfig(ctx);
            if isempty(legacy), return; end
            if isfield(legacy,'JUSPACE'), J = legacy.JUSPACE; else, J = legacy; end
            cfg.legacyJUSPACE = J;
            if isfield(legacy,'PX') && isstruct(legacy.PX), cfg.legacyPX = legacy.PX; end
            if isfield(J,'Atlas') && ~isempty(J.Atlas), cfg.atlasPath = obj.pathListToString(J.Atlas); end
            if isfield(J,'AtlasNames') && ~isempty(J.AtlasNames), cfg.atlasNames = obj.anyToString(J.AtlasNames); end
            if isfield(J,'NTDir') && ~isempty(J.NTDir), cfg.brainMapsDir = char(J.NTDir); end
            if isfield(J,'cortype') && ~isempty(J.cortype)
                if J.cortype == 2, cfg.correlationType = 'pearson'; else, cfg.correlationType = 'spearman'; end
            end
            if isfield(J,'autocorcorrect') && ~isempty(J.autocorcorrect), cfg.adjustSpatialAutocorrelation = J.autocorcorrect == 1; end
            if isfield(J,'TPMpath') && ~isempty(J.TPMpath), cfg.tpmPath = char(J.TPMpath); end
            if isfield(J,'completeflag') && ~isempty(J.completeflag), cfg.complete = logical(J.completeflag); end
            cfg.brainMapRows = obj.rowsFromLegacy(J);
            if isfield(J,'NTNames') && ~isempty(J.NTNames)
                cfg.brainMapRows = obj.applyNamesToRows(cfg.brainMapRows, J.NTNames);
            end
            cfg = obj.validateOrError(cfg);
        end

        function [cfg, legacy, act, aux] = cli_configure(obj, cfg, ctx)
            % cli_configure  Configure JuSpace neuromap correlations for scripted or legacy CLI workflows.
            %   The non-interactive path validates cfg and returns legacyParam/act/aux; when ctx
            %   permits, subclasses may delegate to legacy nk_input configurators while preserving
            %   canonical config output.

            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(); end
            if nargin < 3, ctx = struct(); end
            legacy = obj.toLegacy(cfg, ctx); aux = [];
            if obj.shouldCallLegacyCLI(ctx) && obj.functionExists('JuSpace_config')
                parentstr = obj.getParentString(ctx);
                brainmask = ctx.brainmask;
                Thresh = ctx.spatialThresh;
                J = legacy.JUSPACE;
                act = 1;
                while act > 0
                    [J, act] = JuSpace_config(J, brainmask, Thresh, parentstr);
                end
                legacy = struct('cmd',obj.Id,'JUSPACE',J);
                cfg = obj.fromLegacy(legacy, ctx);
            else
                act = 0;
            end
        end
    end

    methods (Access = private)
        function cfg = validateOrError(obj, cfg)
            [cfg, report] = obj.validateConfig(cfg, struct(), false);
            if ~report.ok, error('NMJuSpaceModule:invalidConfig','%s',strjoin(report.errors,newline)); end
        end

        function J = configToJUSPACE(obj, cfg)
            if isfield(cfg,'legacyJUSPACE') && isstruct(cfg.legacyJUSPACE) && ~isempty(fieldnames(cfg.legacyJUSPACE))
                J = cfg.legacyJUSPACE;
            else
                J = struct();
            end

            atlasList = obj.stringToPathList(obj.getcfg(cfg,'atlasPath',''));
            if ~isempty(atlasList)
                if numel(atlasList) == 1, J.Atlas = atlasList{1}; else, J.Atlas = char(atlasList(:)); end
                [J.AtlasDir,~,~] = fileparts(atlasList{1});
            end
            if isfield(cfg,'atlasNames') && ~isempty(cfg.atlasNames), J.AtlasNames = obj.stringToCell(cfg.atlasNames); end
            if isfield(cfg,'brainMapsDir') && ~isempty(cfg.brainMapsDir), J.NTDir = char(cfg.brainMapsDir); end
            if isfield(cfg,'correlationType') && strcmpi(cfg.correlationType,'pearson'), J.cortype = 2; else, J.cortype = 1; end
            if isfield(cfg,'adjustSpatialAutocorrelation') && cfg.adjustSpatialAutocorrelation, J.autocorcorrect = 1; else, J.autocorcorrect = 2; end
            if isfield(cfg,'tpmPath') && ~isempty(cfg.tpmPath), J.TPMpath = char(cfg.tpmPath); end

            [NTList, NTind, NTNames] = obj.selectedRowsToLegacy(cfg);
            if ~isempty(NTList)
                J.NTList = NTList;
                J.NTind = NTind;
                J.NTNames = NTNames;
            end
            if isfield(cfg,'availableBrainMaps') && ~isempty(cfg.availableBrainMaps)
                J.NT_Table = obj.rowsToTable(cfg.availableBrainMaps);
            end
            if isfield(cfg,'brainMapsDir') && ~isempty(cfg.brainMapsDir) && isfield(J,'NT_Table') && isempty(J.NT_Table)
                J = rmfield(J,'NT_Table');
            end
            if isfield(cfg,'complete'), J.completeflag = logical(cfg.complete); end
        end

        function [NTList, NTind, NTNames] = selectedRowsToLegacy(obj, cfg)
            NTList = {}; NTind = []; NTNames = {};
            rows = obj.getcfg(cfg,'brainMapRows',{});
            rows = obj.normalizeRows(rows);
            if isempty(rows), return; end
            k = 0;
            for i = 1:numel(rows)
                r = rows{i};
                if ~obj.rowSelected(r), continue; end
                k = k + 1;
                file = obj.rowField(r,'file','');
                if isempty(file)
                    p = obj.rowField(r,'path',''); [~,nm,ex] = fileparts(p); file = [nm ex];
                end
                id = obj.rowField(r,'id','');
                if isempty(id)
                    id = obj.rowField(r,'name','');
                    if isempty(id), [~,id] = fileparts(file); end
                end
                listidx = obj.rowField(r,'listidx',[]);
                if isempty(listidx), listidx = i; end
                NTList{k} = struct('id',char(id),'listidx',listidx,'file',char(file)); %#ok<AGROW>
                NTind(k) = listidx; %#ok<AGROW>
                alt = obj.rowField(r,'altName','');
                if isempty(alt), alt = id; end
                NTNames{k} = char(alt); %#ok<AGROW>
            end
        end

        function rows = rowsFromLegacy(obj, J)
            rows = {};
            if ~isfield(J,'NTList') || isempty(J.NTList), return; end
            NTList = J.NTList;
            if isstruct(NTList), NTList = num2cell(NTList); end
            for i = 1:numel(NTList)
                r0 = NTList{i};
                if isempty(r0), continue; end
                r = struct(); r.selected = true;
                if isstruct(r0)
                    if isfield(r0,'id'), r.id = char(r0.id); else, r.id = sprintf('map_%d',i); end
                    if isfield(r0,'file'), r.file = char(r0.file); else, r.file = ''; end
                    if isfield(r0,'listidx'), r.listidx = r0.listidx; else, r.listidx = i; end
                else
                    r.id = char(r0); r.file = char(r0); r.listidx = i;
                end
                if isfield(J,'NTDir') && ~isempty(J.NTDir) && isfield(r,'file') && ~isempty(r.file)
                    r.path = fullfile(char(J.NTDir), char(r.file));
                end
                r.name = r.id; r.altName = r.id;
                rows{end+1} = r; %#ok<AGROW>
            end
        end

        function rows = applyNamesToRows(~, rows, names)
            if isempty(rows), return; end
            if ischar(names) || isstring(names), names = cellstr(names); end
            if ~iscell(names), return; end
            for i = 1:min(numel(rows),numel(names))
                rows{i}.altName = char(names{i});
            end
        end

        function T = rowsToTable(obj, rows)
            rows = obj.normalizeRows(rows);
            if isempty(rows), T = []; return; end
            NT = cell(numel(rows),1); tracer = NT; N = NT; source = NT; file = NT; filenames = NT;
            for i = 1:numel(rows)
                r = rows{i};
                NT{i} = obj.rowField(r,'NT',obj.rowField(r,'id',obj.rowField(r,'name','')));
                tracer{i} = obj.rowField(r,'tracer','NA');
                N{i} = obj.rowField(r,'N','NA');
                source{i} = obj.rowField(r,'source','NA');
                file{i} = obj.rowField(r,'file','');
                filenames{i} = file{i};
            end
            try
                T = table(NT,tracer,N,source,file,filenames);
            catch
                T = [];
            end
        end

        function rows = normalizeRows(~, rows)
            if isempty(rows), rows = {}; return; end
            if isstruct(rows), rows = num2cell(rows); end
            if ~iscell(rows), rows = {}; end
        end

        function tf = rowSelected(~, r)
            tf = false;
            if isstruct(r) && isfield(r,'selected') && ~isempty(r.selected), tf = logical(r.selected); end
        end

        function val = rowField(~, r, field, defaultVal)
            val = defaultVal;
            if isstruct(r) && isfield(r,field) && ~isempty(r.(field)), val = r.(field); end
        end

        function c = stringToCell(~, s)
            if iscell(s), c = s; return; end
            if isstring(s), s = char(s); end
            if isempty(s), c = {}; return; end
            c = regexp(char(s), '\s*,\s*', 'split');
            c = c(~cellfun('isempty', c));
        end

        function paths = stringToPathList(~, s)
            paths = {};
            if isempty(s), return; end
            if iscell(s), paths = cellfun(@char, s(:)', 'UniformOutput', false); return; end
            if isstring(s), s = strjoin(cellstr(s(:))', ';'); end
            s = char(s);
            paths = regexp(s, '\s*[;\n]\s*', 'split');
            paths = paths(~cellfun('isempty', paths));
        end

        function s = pathListToString(~, x)
            if isempty(x), s = ''; return; end
            if iscell(x), s = strjoin(cellfun(@char, x(:)', 'UniformOutput', false), '; '); return; end
            if isstring(x), s = strjoin(cellstr(x(:))', '; '); return; end
            if ischar(x)
                if size(x,1) > 1, s = strjoin(cellstr(x), '; '); else, s = strtrim(x); end
                return;
            end
            s = '';
        end

        function s = anyToString(~, x)
            if ischar(x), s = strtrim(x); return; end
            if isstring(x), s = strjoin(cellstr(x(:))', ', '); return; end
            if iscell(x), s = strjoin(cellfun(@char, x(:)', 'UniformOutput', false), ', '); return; end
            s = '';
        end

        function s = defaultBrainMapsDir(~, ctx)
            s = '';
            try
                if isstruct(ctx) && isfield(ctx,'juSpaceRoot') && ~isempty(ctx.juSpaceRoot)
                    p = fullfile(char(ctx.juSpaceRoot),'NT','JuSpace');
                    if exist(p,'dir'), s = p; end
                end
            catch
                s = '';
            end
        end

        function s = contextString(~, ctx, field, defaultVal)
            s = defaultVal;
            try
                if isstruct(ctx) && isfield(ctx,field) && ~isempty(ctx.(field)), s = char(ctx.(field)); end
            catch
                s = defaultVal;
            end
        end

        function v = getcfg(~, cfg, field, defaultVal)
            v = defaultVal;
            if isstruct(cfg) && isfield(cfg,field) && ~isempty(cfg.(field)), v = cfg.(field); end
        end
    end
end
