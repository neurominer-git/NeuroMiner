classdef NMNuisanceSubconfigLibrary
% NMNuisanceSubconfigLibrary
% -------------------------------------------------------------------------
% Nested schema and legacy-code helpers for NeuroMiner nuisance correction
% (legacy command: correctnuis; legacy configurator: nk_UnivCorrProcs_config).
%
% The library is deliberately separate from NMCorrectNuisModule because the
% same ComBat / residualisation / fairness-correction semantics may later be
% reused outside CV preprocessing.
% -------------------------------------------------------------------------

    methods (Static)
        function specMap = specs(ctx)
            % specs  Return the nested subconfiguration schema map for supported methods.
            %   Used by parent modules, UI builders, and documentation extraction so method-specific
            %   options remain centralized in this library.

            % Return a struct map keyed by canonical method name. This is the
            % format expected by the generic browser subconfig renderer.
            if nargin < 1 || isempty(ctx), ctx = struct(); end
            specMap = struct();
            specMap.partial = NMNuisanceSubconfigLibrary.partialSpec(ctx);
            specMap.combat  = NMNuisanceSubconfigLibrary.combatSpec(ctx);
            specMap.dir     = NMNuisanceSubconfigLibrary.dirSpec(ctx);
        end

        function specs = all(ctx)
            % all  Return all nuisance-correction method schemas as a cell/list-friendly collection.
            %   Used by UI/API callers that need to enumerate methods without relying on struct
            %   field names.

            % Cell-array form retained for legacy tests and helper code.
            % Browser UI modules should use specs(ctx), not all(ctx).
            if nargin < 1 || isempty(ctx), ctx = struct(); end
            specs = { ...
                NMNuisanceSubconfigLibrary.partialSpec(ctx), ...
                NMNuisanceSubconfigLibrary.combatSpec(ctx), ...
                NMNuisanceSubconfigLibrary.dirSpec(ctx) };
        end

        function spec = byMethod(method, ctx)
            % byMethod  Return the schema for one canonical nuisance-correction method.
            %   Normalizes method aliases first so partial/ComBat/DIR callers share the same
            %   downstream validation path.

            if nargin < 2 || isempty(ctx), ctx = struct(); end
            switch NMNuisanceSubconfigLibrary.canonMethod(method)
                case 'partial'
                    spec = NMNuisanceSubconfigLibrary.partialSpec(ctx);
                case 'combat'
                    spec = NMNuisanceSubconfigLibrary.combatSpec(ctx);
                case 'dir'
                    spec = NMNuisanceSubconfigLibrary.dirSpec(ctx);
                otherwise
                    spec = struct('id','unknown','title','Unknown nuisance method','fields',{{}});
            end
        end

        function spec = partialSpec(ctx)
            % partialSpec  Build the partial-correlation/residualization schema.
            %   Defines the covariate, intercept, external beta, and subgroup options that
            %   NMCorrectNuisModule later exports to ACTPARAM.

            if nargin < 1 || isempty(ctx), ctx = struct(); end %#ok<NASGU>
            spec = struct();
            spec.id = 'partial';
            spec.title = 'Partial correlations / residualization';
            spec.description = ['Regress nuisance covariates out of the feature matrix, or add previously ', ...
                'estimated covariate effects back in.'];
            spec.legacyConfigurator = 'nk_UnivCorrProcs_config: METHOD=1';
            spec.fields = { ...
                struct('name','covariates','type','covariate_indices','default',1,'label','Nuisance covariates', ...
                    'allowEmpty',false,'multiple',true, ...
                    'help','Select one or more covariates to regress from the feature matrix.'), ...
                struct('name','includeIntercept','type','boolean','default',true,'label','Use intercept', ...
                    'help','Include a constant term in the nuisance-regression model.'), ...
                struct('name','covariateDirection','type','enum','default','attenuate','label','Covariate-effect direction', ...
                    'values',{{'attenuate','increase'}}, ...
                    'help','Attenuate removes estimated covariate effects; increase adds them back.'), ...
                struct('name','useExternalBeta','type','boolean','default',false,'label','Use externally computed beta coefficients', ...
                    'help','If enabled, beta coefficients are supplied rather than estimated within the training fold.'), ...
                struct('name','externalBetaSource','type','enum','default','workspace','label','External beta source', ...
                    'values',{{'workspace','legacy'}}, ...
                    'visibleIf',struct('field','useExternalBeta','equals',true), ...
                    'help','Choose a workspace matrix or preserve coefficients imported with an existing configuration.'), ...
                struct('name','externalBetaWorkspaceVar','type','workspace_var','default','','label','Workspace beta matrix', ...
                    'visibleIf',struct('all',{{struct('field','useExternalBeta','equals',true),struct('field','externalBetaSource','equals','workspace')}}), ...
                    'workspaceFilter',struct('numericOnly',true), ...
                    'help','Matrix with rows matching the nuisance-design columns, including intercept if enabled, and columns matching features.'), ...
                struct('name','externalBetaMatrix','type','any','default',[],'label','Imported legacy beta matrix','uiHidden',true, ...
                    'help','Imported nuisance-regression beta coefficients retained when using legacy external beta data.'), ...
                struct('name','subgroupSource','type','enum','default','none','label','Training subgroup for beta computation', ...
                    'values',{{'none','workspace','legacy'}}, ...
                    'visibleIf',struct('field','useExternalBeta','equals',false), ...
                    'help','Optionally restrict beta estimation to a subset of training cases.'), ...
                struct('name','subgroupWorkspaceVar','type','workspace_var','default','','label','Workspace subgroup vector', ...
                    'visibleIf',struct('field','subgroupSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Logical/numeric vector with one row per subject/case.'), ...
                struct('name','subgroupVector','type','any','default',[],'label','Imported legacy subgroup vector','uiHidden',true, ...
                    'help','Imported legacy subgroup indicator vector retained for the selected nuisance-correction method.') };
        end

        function spec = combatSpec(ctx)
            % combatSpec  Build the ComBat/CovBat harmonization schema.
            %   Defines batch, covariate, EB, distribution, reference batch, and CovBat mode fields
            %   used by nuisance legacy export.

            if nargin < 1 || isempty(ctx), ctx = struct(); end %#ok<NASGU>
            spec = struct();
            spec.id = 'combat';
            spec.title = 'ComBat / CovBat harmonization';
            spec.description = ['Batch harmonization with optional biological covariate preservation/removal, ', ...
                'GAM/spline handling and CovBat covariance harmonization.'];
            spec.legacyConfigurator = 'nk_UnivCorrProcs_config: METHOD=2';
            spec.fields = { ...
                struct('name','useBatch','type','boolean','default',true,'label','Correct for batch effects using ComBat', ...
                    'help','Enable batch-effect correction and select a categorical batch covariate.'), ...
                struct('name','batchCovariate','type','covariate_index','default',[],'label','Batch covariate', ...
                    'allowEmpty',true,'multiple',false,'visibleIf',struct('field','useBatch','equals',true), ...
                    'help','Select the categorical covariate that identifies acquisition site or batch.'), ...
                struct('name','referenceBatch','type','number','default',[],'allowEmpty',true,'label','Reference batch label', ...
                    'visibleIf',struct('field','useBatch','equals',true), ...
                    'help','Leave empty to use the pooled/default reference batch.'), ...
                struct('name','retainLabels','type','boolean','default',true,'label','Retain outcome-label variance', ...
                    'help','Preserve outcome-label variance in the ComBat model. This is independent of additional ComBat covariates.'), ...
                struct('name','includeCovariates','type','boolean','default',true,'label','Include covariates in ComBat equation', ...
                    'help','Include selected biological or nuisance covariates in the ComBat model.'), ...
                struct('name','covariates','type','covariate_indices','default',[],'allowEmpty',true,'multiple',true,'label','Additional covariates', ...
                    'uiHidden',true, ...
                    'help','Internal selected-covariate vector synchronized from the visible covariate table.'), ...
                struct('name','covariateDetails','type','combat_covariate_table','default',struct(),'label','Additional covariates', ...
                    'visibleIf',struct('field','includeCovariates','equals',true), ...
                    'help','Select ComBat covariates, choose whether their variance is retained or removed, and adjust measurement scale or spline degrees of freedom when needed.'), ...
                struct('name','removeCovariatePositions','type','numeric_vector','default',[],'allowEmpty',true,'label','Covariates to remove (positions in selected list)', ...
                    'uiHidden',true, ...
                    'help','Positions in the selected covariate vector whose effects should be removed rather than retained.'), ...
                struct('name','covariateTypes','type','string','default','','label','Measurement scales for selected covariates', ...
                    'uiHidden',true, ...
                    'help','Measurement-scale values aligned to the selected covariates; empty entries are inferred automatically.'), ...
                struct('name','splineDF','type','numeric_vector','default',[],'allowEmpty',true,'label','Spline df per selected covariate', ...
                    'uiHidden',true, ...
                    'help','Spline degrees of freedom aligned to the selected covariates; none or values 2 through 5 are supported.'), ...
                struct('name','combatVariant','type','enum','default','combat','label','ComBat variant', ...
                    'values',{{'combat','covbat'}}, ...
                    'help','Choose standard ComBat mean/variance harmonization or CovBat covariance harmonization.'), ...
                struct('name','covbatK','type','number','default',[],'allowEmpty',true,'label','CovBat K', ...
                    'visibleIf',struct('field','combatVariant','equals','covbat'), ...
                    'help','Integer number of PCs for CovBat. Empty uses cumulative variance.'), ...
                struct('name','covbatVar','type','number','default',0.95,'allowEmpty',true,'min',0,'max',1,'label','CovBat cumulative variance', ...
                    'visibleIf',struct('field','combatVariant','equals','covbat'), ...
                    'help','Cumulative variance threshold in [0,1] used when the number of CovBat components is left empty.'), ...
                struct('name','unseenBatchMode','type','enum','default','eb','label','Unseen-batch mode', ...
                    'values',{{'eb','no_shrink','strong_shrink'}}, ...
                    'help','Choose how previously unseen batches are handled during application.'), ...
                struct('name','unseenBatchAlpha','type','number','default',0.7,'min',0,'max',1,'label','Strong-shrink alpha', ...
                    'visibleIf',struct('field','unseenBatchMode','equals','strong_shrink'), ...
                    'help','Extra shrinkage alpha used only for strong-shrink unseen-batch mode.'), ...
                struct('name','subgroupSource','type','enum','default','none','label','Training subgroup for ComBat estimator', ...
                    'values',{{'none','workspace','legacy'}}, ...
                    'help','Optionally restrict ComBat parameter estimation to a subset of training cases.'), ...
                struct('name','subgroupWorkspaceVar','type','workspace_var','default','','label','Workspace subgroup vector', ...
                    'visibleIf',struct('field','subgroupSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Logical/numeric vector with one row per subject/case.'), ...
                struct('name','subgroupVector','type','any','default',[],'label','Imported legacy subgroup vector','uiHidden',true, ...
                    'help','Imported legacy subgroup indicator vector retained for the selected nuisance-correction method.') };
        end

        function spec = dirSpec(ctx)
            % dirSpec  Build the Disparate Impact Removal schema.
            %   Defines lambda and protected attribute options that NMCorrectNuisModule maps to the
            %   legacy DIR branch.

            if nargin < 1 || isempty(ctx), ctx = struct(); end %#ok<NASGU>
            spec = struct();
            spec.id = 'dir';
            spec.title = 'Disparate Impact Removal';
            spec.description = ['Fairness-oriented feature repair using categorical covariates and a tunable ', ...
                'correction-strength parameter.'];
            spec.legacyConfigurator = 'nk_UnivCorrProcs_config: METHOD=3';
            spec.fields = { ...
                struct('name','categoricalCovariates','type','covariate_indices','default',1,'allowEmpty',false,'multiple',true,'label','Categorical covariates', ...
                    'help','Select one or more categorical/protected covariates used for the fairness correction.'), ...
                struct('name','distribution','type','enum','default','median','label','Target distribution statistic', ...
                    'values',{{'median','mean'}}, ...
                    'help','Choose whether repaired feature distributions are aligned using the median or mean.'), ...
                struct('name','lambda','type','numeric_vector','default',0.8,'minItems',1,'allowEmpty',false,'label','Correction strength / optimization grid', ...
                    'help','Correction strength in [0,1]. A scalar fixes the strength; multiple values define candidates for optimization.'), ...
                struct('name','subgroupSource','type','enum','default','none','label','Training subgroup for DIR distributions', ...
                    'values',{{'none','workspace','legacy'}}, ...
                    'help','Optionally restrict distribution estimation to a subset of training cases.'), ...
                struct('name','subgroupWorkspaceVar','type','workspace_var','default','','label','Workspace subgroup vector', ...
                    'visibleIf',struct('field','subgroupSource','equals','workspace'), ...
                    'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Logical/numeric vector with one row per subject/case.'), ...
                struct('name','subgroupVector','type','any','default',[],'label','Imported legacy subgroup vector','uiHidden',true, ...
                    'help','Imported legacy subgroup indicator vector retained for the selected nuisance-correction method.') };
        end

        function method = canonMethod(method)
            % canonMethod  Normalize method aliases to canonical library tokens.
            %   Keeps UI labels, legacy command names, and power-user shorthand on the same
            %   validation/export path.

            if isempty(method), method = 'partial'; return; end
            method = lower(char(method));
            switch method
                case {'partial','partialcorr','partial_correlation','residualization','residualisation','pc'}
                    method = 'partial';
                case {'combat','covbat','combat_covbat','harmonization','harmonisation'}
                    method = 'combat';
                case {'dir','disparate','disparateimpact','disparate_impact'}
                    method = 'dir';
                otherwise
                    method = lower(char(method));
            end
        end

        function code = methodCode(method)
            % methodCode  Return the legacy numeric code for a nuisance-correction method.
            %   Used by NMCorrectNuisModule.toLegacy to fill ACTPARAM fields expected by
            %   nk_UnivCorrProcs.

            switch NMNuisanceSubconfigLibrary.canonMethod(method)
                case 'partial', code = 1;
                case 'combat', code = 2;
                case 'dir', code = 3;
                otherwise, error('NMNuisanceSubconfigLibrary:badMethod','Unknown nuisance method: %s', char(method));
            end
        end

        function method = methodName(code)
            % methodName  Return the canonical method name for a legacy nuisance method code.
            %   Used by legacy import and UI labels when old numeric flags must be made readable.

            switch double(code)
                case 1, method = 'partial';
                case 2, method = 'combat';
                case 3, method = 'dir';
                otherwise, method = 'partial';
            end
        end

        function code = yesNo(tf)
            % yesNo  Convert a logical value to legacy yes/no code.
            %   Small public mapper retained for compatibility with legacy code translation.

            if tf, code = 1; else, code = 2; end
        end

        function tf = fromYesNo(code, defaultVal)
            % fromYesNo  Convert a legacy yes/no code to logical form.
            %   Used during fromLegacy import to present old flags as canonical booleans.

            if nargin < 2, defaultVal = true; end
            if isempty(code), tf = defaultVal; return; end
            tf = code == 1 || isequal(code,true);
        end

        function code = distributionCode(name)
            % distributionCode  Return the legacy ComBat distribution code for a named distribution.
            %   Used by harmonization export so UI strings become backend-compatible numeric flags.

            switch lower(char(name))
                case 'median', code = 1;
                case 'mean', code = 2;
                otherwise, error('NMNuisanceSubconfigLibrary:badDistribution','Unknown DIR distribution: %s', char(name));
            end
        end

        function name = distributionName(code)
            % distributionName  Return the canonical ComBat distribution name for a legacy code.
            %   Used by legacy import to display prior settings in UI/API form.

            if double(code) == 2, name = 'mean'; else, name = 'median'; end
        end

        function code = covbatModeCode(name)
            % covbatModeCode  Return the legacy CovBat mode code for a named mode.
            %   Used when exporting CovBat options from the nuisance method config.

            switch lower(char(name))
                case {'combat','simple','simple_combat'}, code = 1;
                case {'covbat','combat+covbat','combat_covbat'}, code = 2;
                otherwise, code = 1;
            end
        end

        function name = covbatModeName(code)
            % covbatModeName  Return the canonical CovBat mode name for a legacy code.
            %   Used when importing legacy CovBat settings into canonical config fields.

            if double(code) == 2, name = 'covbat'; else, name = 'combat'; end
        end

        function code = unseenBatchModeCode(name)
            % unseenBatchModeCode  Return the legacy mode code for unseen batches.
            %   Used during ComBat/CovBat export when application/OOCV behavior is configured.

            switch lower(char(name))
                case {'eb','empirical_bayes','empiricalbayes'}, code = 1;
                case {'no_shrink','noshrink','no-shrink'}, code = 2;
                case {'strong_shrink','strongshrink','strong-shrink'}, code = 3;
                otherwise, code = 1;
            end
        end

        function name = unseenBatchModeName(code)
            % unseenBatchModeName  Return the canonical unseen-batch mode name for a legacy code.
            %   Used during import so old numeric application-mode flags are readable and editable.

            switch double(code)
                case 2, name = 'no_shrink';
                case 3, name = 'strong_shrink';
                otherwise, name = 'eb';
            end
        end

        function types = parseCovariateTypes(x)
            % parseCovariateTypes  Parse covariate-type specifications into canonical type tokens.
            %   Normalizes strings, cells, or arrays from UI/API state before ComBat covariate
            %   details are exported.

            if isempty(x), types = {}; return; end
            if iscell(x)
                types = cellfun(@NMNuisanceSubconfigLibrary.canonCovType, x, 'UniformOutput', false);
                return;
            end
            if isstring(x), x = char(strjoin(x(:)', ',')); end
            if ischar(x)
                parts = regexp(x, '[,;\s]+', 'split');
                parts = parts(~cellfun(@isempty, parts));
                types = cellfun(@NMNuisanceSubconfigLibrary.canonCovType, parts, 'UniformOutput', false);
                return;
            end
            types = {};
        end

        function t = canonCovType(t)
            % canonCovType  Normalize one covariate measurement-scale token.
            %   Maps aliases to continuous/categorical/ordinal categories used by ComBat/CovBat
            %   schemas.

            t = lower(strtrim(char(t)));
            switch t
                case {'c','cont','continuous'}, t = 'continuous';
                case {'b','bin','binary'}, t = 'categorical';
                case {'o','ord','ordinal'}, t = 'ordinal';
                case {'k','cat','categorical'}, t = 'categorical';
                otherwise, t = 'continuous';
            end
        end
    end
end
