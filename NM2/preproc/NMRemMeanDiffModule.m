classdef NMRemMeanDiffModule < NMPreprocModule
% NMRemMeanDiffModule
% -------------------------------------------------------------------------
% Canonical adapter for NeuroMiner group-wise offset correction
% (legacy cmd: remmeandiff; legacy configurator embedded in nk_Preproc_config).
%
% sIND/dIND are persisted scalar covariate-column selectors. The legacy
% preprocessing builder dereferences those columns for training/CV/test/OOCV
% cases before nk_PerfRemMeanDiffObj receives the resulting group-code vectors.
% -------------------------------------------------------------------------

    methods
        function obj = NMRemMeanDiffModule()
            % NMRemMeanDiffModule  Construct the Offset correction preprocessing adapter.

            obj@NMPreprocModule('remmeandiff','','Offset correction');
        end

        function spec = configSpec(obj, ctx)
            % configSpec  Return covariate selectors for legacy sIND/dIND semantics.

            if nargin < 2, ctx = struct(); end
            spec = configSpec@NMPreprocModule(obj, ctx);
            spec.description = ['Correct group-wise offsets from the global mean. The source grouping ', ...
                'covariate defines the groups used to estimate global/group-specific means; the ', ...
                'destination grouping covariate defines where those corrections are applied.'];
            spec.legacyConfigurator = 'nk_Preproc_config/config_remmeandiff';
            defaultIndex = obj.defaultCovariateIndex(ctx);
            allowEmpty = true;
            spec.fields = { ...
                struct('name','sourceGroupCovariate','type','covariate_index','default',defaultIndex, ...
                    'allowEmpty',allowEmpty,'multiple',false,'label','Source grouping covariate', ...
                    'help','Covariate column defining groups used to compute global and group-specific means. Cases coded as 0 are skipped.'), ...
                struct('name','destinationGroupCovariate','type','covariate_index','default',defaultIndex, ...
                    'allowEmpty',allowEmpty,'multiple',false,'label','Destination grouping covariate', ...
                    'help','Covariate column defining the groups/cases to which the global and group-specific mean correction is applied. Cases coded as 0 are skipped.') };
        end

        function [cfg, report] = validateConfig(obj, cfg, ctx, strict)
            % validateConfig  Validate covariate-column selectors against current context.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(strict), strict = true; end
            fields = {'sourceGroupCovariate','destinationGroupCovariate'};
            labels = {'Source grouping covariate','Destination grouping covariate'};
            legacyFields = {'legacySourceGroupCovariates','legacyDestinationGroupCovariates'};
            for i = 1:numel(fields)
                if isfield(cfg,legacyFields{i}) && obj.isScalarIndex(cfg.(fields{i}))
                    cfg = rmfield(cfg,legacyFields{i});
                end
            end
            [cfg, report] = validateConfig@NMPreprocModule(obj, cfg, ctx, strict);
            nCovars = obj.contextNCovars(ctx);
            for i = 1:numel(fields)
                value = cfg.(fields{i});
                if isempty(value)
                    if isfield(cfg,legacyFields{i}) && ~isempty(cfg.(legacyFields{i}))
                        report.errors{end+1} = sprintf( ...
                            'Legacy %s used multiple covariate columns %s. Select one covariate to migrate this offset-correction step.', ...
                            lower(labels{i}), mat2str(cfg.(legacyFields{i}))); %#ok<AGROW>
                    elseif strict && ~isempty(nCovars) && nCovars > 0
                        report.errors{end+1} = sprintf('%s must be selected when covariates are available.',labels{i}); %#ok<AGROW>
                    end
                    continue;
                end
                if ~obj.isScalarIndex(value)
                    report.errors{end+1} = sprintf('%s must be one positive integer covariate index.',labels{i}); %#ok<AGROW>
                    continue;
                end
                cfg.(fields{i}) = double(value);
                if ~isempty(nCovars) && nCovars >= 0 && value > nCovars
                    report.errors{end+1} = sprintf('%s index exceeds the %d available covariate(s).',labels{i},nCovars); %#ok<AGROW>
                end
            end
            report.ok = isempty(report.errors);
        end

        function legacy = toLegacy(obj, cfg, ctx)
            % toLegacy  Materialize canonical selectors to inherited sIND/dIND fields.

            if nargin < 3, ctx = struct(); end
            if nargin < 2 || isempty(cfg), cfg = obj.defaultConfig(ctx); end
            [cfg, report] = obj.validateConfig(cfg, ctx, true);
            if ~report.ok
                error('NMRemMeanDiffModule:invalidConfig','%s',strjoin(report.errors,newline));
            end
            legacy = struct('sIND',obj.toLegacyIndex(cfg.sourceGroupCovariate), ...
                'dIND',obj.toLegacyIndex(cfg.destinationGroupCovariate),'cmd',obj.Id);
        end

        function cfg = fromLegacy(obj, legacy, ctx)
            % fromLegacy  Import inherited remmeandiff ACTPARAM fields losslessly.

            if nargin < 2 || isempty(legacy), legacy = struct(); end
            if nargin < 3, ctx = struct(); end
            cfg = obj.defaultConfig(ctx);
            if isfield(legacy,'sIND')
                [cfg.sourceGroupCovariate, legacyValue] = obj.fromLegacyIndex(legacy.sIND,'sIND');
                if ~isempty(legacyValue), cfg.legacySourceGroupCovariates = legacyValue; end
            end
            if isfield(legacy,'dIND')
                [cfg.destinationGroupCovariate, legacyValue] = obj.fromLegacyIndex(legacy.dIND,'dIND');
                if ~isempty(legacyValue), cfg.legacyDestinationGroupCovariates = legacyValue; end
            end
            [cfg, report] = obj.validateConfig(cfg, ctx, false);
            if ~report.ok
                warning('NMRemMeanDiffModule:legacyConfigInvalid', ...
                    'Legacy remmeandiff configuration did not validate cleanly: %s',strjoin(report.errors,'; '));
            end
        end
    end

    methods (Access = private)
        function idx = defaultCovariateIndex(obj, ctx)
            n = obj.contextNCovars(ctx);
            if ~isempty(n) && n >= 1, idx = 1; else, idx = []; end
        end

        function n = contextNCovars(~, ctx)
            n = [];
            if isstruct(ctx) && isfield(ctx,'nCovars') && ~isempty(ctx.nCovars)
                n = double(ctx.nCovars);
            end
        end

        function value = toLegacyIndex(~, value)
            if isempty(value), value = 'NA'; end
        end

        function tf = isScalarIndex(~, value)
            tf = isnumeric(value) && isscalar(value) && isfinite(value) && value == round(value) && value >= 1;
        end

        function [value, legacyVector] = fromLegacyIndex(obj, value, fieldName)
            legacyVector = [];
            if isempty(value) || ((ischar(value) || isstring(value)) && strcmpi(strtrim(char(value)),'NA'))
                value = [];
                return;
            end
            if obj.isScalarIndex(value)
                value = double(value);
                return;
            end
            if isnumeric(value) && isvector(value) && numel(value) > 1 && ...
                    all(isfinite(value(:))) && all(value(:) == round(value(:))) && all(value(:) >= 1)
                legacyVector = double(value(:).');
                value = [];
                return;
            end
            error('NMRemMeanDiffModule:legacyIndexInvalid', ...
                'Legacy remmeandiff %s must contain positive integer covariate-column indices or ''NA''.',fieldName);
        end
    end
end
