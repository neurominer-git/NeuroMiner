classdef NMDimRedSubconfigLibrary
% NMDimRedSubconfigLibrary
% -------------------------------------------------------------------------
% Nested configuration schemas and legacy mappings for dimensionality
% reduction methods.  The mappings intentionally mirror
% nk_DimRed_main_config.m and its subconfigurators, while keeping the method
% specific options on separate UI pages.
% -------------------------------------------------------------------------

    methods (Static)
        function specMap = specs(ctx)
            % specs  Return the nested subconfiguration schema map for supported methods.
            %   Used by parent modules, UI builders, and documentation extraction so method-specific
            %   options remain centralized in this library.

            if nargin < 1, ctx = struct(); end
            ids = NMDimRedSubconfigLibrary.methodIds();
            specMap = struct();
            for i = 1:numel(ids)
                specMap.(NMDimRedSubconfigLibrary.safeField(ids{i})) = NMDimRedSubconfigLibrary.spec(ids{i}, ctx);
            end
        end

        function ids = methodIds()
            % methodIds  Return supported dimensionality-reduction method identifiers.
            %   Used by UI selectors, validation messages, and power-user scripts before
            %   method-specific defaults are requested.

            ids = {'PCA','RobPCA','NNMF','optNMF','NeNMF','PLS','SparsePCA','ProbPCA', ...
                   'FactorAnalysis','LPP','LLTSA','LMNN','LDA','NCA','fastICA','GDA','Laplacian','LLE'};
        end

        function spec = spec(method, ctx)
            % spec  Return the schema for one nested method/algorithm.
            %   The returned schema drives defaultParams, validateParams, UI rendering, and legacy
            %   conversion for the parent preprocessing module.

            if nargin < 2, ctx = struct(); end %#ok<INUSD>
            method = NMDimRedSubconfigLibrary.canonicalMethod(method);
            spec = struct();
            spec.id = method;
            spec.kind = 'dimred-method-subconfig';
            spec.title = NMDimRedSubconfigLibrary.title(method);
            spec.description = NMDimRedSubconfigLibrary.description(method);
            spec.fields = {};
            spec.cliConfigurator = '';
            spec.status = 'ported';

            switch method
                case {'PCA','RobPCA','FactorAnalysis','LDA','GDA','LMNN'}
                    spec.fields = {};
                    spec.status = 'no-extra-parameters';

                case 'optNMF'
                    % return_dimred lists this method but does not implement
                    % a dedicated switch branch. Preserve it as a selectable
                    % legacy method without inventing options.
                    spec.status = 'legacy-listed-no-extra-parameters';
                    spec.fields = {struct('name','legacyNotice','type','readonly','default', ...
                        'optNMF is listed by nk_DimRed_main_config but has no dedicated legacy option branch. The method name is preserved without additional parameters.', ...
                        'label','Status', ...
                    'help','Read-only notice describing the legacy method and its unsupported or absent additional settings.')};

                case 'NNMF'
                    spec.fields = { ...
                        struct('name','nmfMethod','type','enum','default','nmf','label','NMF method', ...
                            'values',{{'nmf','sparsenmf','convexnmf','orthnmf'}}, ...
                            'help','Choose the non-negative matrix factorization update method.'), ...
                        struct('name','display','type','boolean','default',false,'label','Display NNMF optimization output', ...
                    'help','Display progress and optimization messages from the NNMF algorithm.')};

                case 'NeNMF'
                    spec.fields = { ...
                        struct('name','nmfMethod','type','enum','default','RPI_NeNMF','label','NeNMF method', ...
                            'values',{{'RPI_NeNMF','RSI_NeNMF','VANILLA_NeNMF'}}, ...
                    'help','Select the NeNMF solver method from the existing method options.'), ...
                        struct('name','tmax','type','number','default',60,'min',0,'label','Maximum runtime in seconds', ...
                    'help','Maximum NeNMF optimization runtime in seconds.')};

                case 'SparsePCA'
                    spec.fields = { ...
                        struct('name','lambda','type','numeric_vector','default',Inf,'allowInf',true,'allowEmpty',false, ...
                            'label','Lambda parameter(s)', ...
                            'help','Positive ridge-term coefficient. Inf selects the high-dimensional default.'), ...
                        struct('name','stop','type','numeric_vector','default',[0.1 0.2 0.3 0.4 0.5], ...
                            'allowEmpty',false,'label','Stop parameter(s)', ...
                    'help','Stopping-criterion candidate(s) passed to the selected dimensionality-reduction method.'), ...
                        struct('name','maxiter','type','numeric_vector','default',300,'allowEmpty',false, ...
                            'label','Maximum iteration value(s)', ...
                    'help','Maximum optimization-iteration candidate(s).')};

                case 'ProbPCA'
                    spec.fields = { ...
                        struct('name','iter','type','numeric_vector','default',200,'allowEmpty',false, ...
                            'label','Iteration value(s)', ...
                    'help','Iteration-count candidate(s) for the chosen projection method.')};

                case 'LPP'
                    spec.fields = { ...
                        struct('name','sigma','type','numeric_vector','default',1,'allowEmpty',false, ...
                            'label','Gaussian bandwidth Sigma', ...
                    'help','Gaussian bandwidth or sigma candidate(s) for the selected manifold method.'), ...
                        struct('name','k','type','numeric_vector','default',12,'allowEmpty',false, ...
                            'label','Number(s) of nearest neighbours', ...
                    'help','Nearest-neighbour count candidate(s) for the selected local-manifold method.')};

                case 'LLTSA'
                    spec.fields = { ...
                        struct('name','k','type','numeric_vector','default',12,'allowEmpty',false, ...
                            'label','Number(s) of nearest neighbours', ...
                    'help','Nearest-neighbour count candidate(s) for the selected local-manifold method.')};

                case 'Laplacian'
                    spec.fields = { ...
                        struct('name','k','type','numeric_vector','default',12,'allowEmpty',false, ...
                            'label','Number(s) of nearest neighbours', ...
                    'help','Nearest-neighbour count candidate(s) for the selected local-manifold method.'), ...
                        struct('name','sigma','type','numeric_vector','default',1,'allowEmpty',false, ...
                            'label','Sigma value(s)', ...
                    'help','Gaussian bandwidth or sigma candidate(s) for the selected manifold method.')};

                case 'LLE'
                    spec.fields = { ...
                        struct('name','k','type','numeric_vector','default',12,'allowEmpty',false, ...
                            'label','Number(s) of nearest neighbours', ...
                    'help','Nearest-neighbour count candidate(s) for the selected local-manifold method.')};

                case 'NCA'
                    spec.fields = { ...
                        struct('name','lambda','type','numeric_vector','default',0.5,'allowEmpty',false, ...
                            'label','Lambda value(s)', ...
                    'help','Regularization lambda candidate(s) for the selected method.')};

                case 'PLS'
                    spec.cliConfigurator = 'nk_PLS_config';
                    spec.fields = { ...
                        struct('name','method','type','enum','default','pls','label','PLS method', ...
                            'values',{{'pls','spls'}}, ...
                    'help','Select the partial least-squares variant used for dimensionality reduction.'), ...
                        struct('name','labelMatrixSource','type','enum','default','nm_labels','label','V matrix source', ...
                            'values',{{'nm_labels','nm_covars','workspace','legacy'}}, ...
                    'help','Select the source of the PLS response/design matrix V.'), ...
                        struct('name','covariateColumns','type','numeric_vector','default',[],'label','Covariate column indices', ...
                            'allowEmpty',true, 'visibleIf',struct('field','labelMatrixSource','equals','nm_covars'), ...
                    'help','Covariate column indices used to form the PLS response/design matrix V.'), ...
                        struct('name','workspaceMatrixVar','type','workspace_var','default','','label','Workspace V matrix variable', ...
                            'visibleIf',struct('field','labelMatrixSource','equals','workspace'), ...
                            'workspaceFilter',struct('numericOnly',true,'rowCountFromContext','nSubjects'), ...
                    'help','Workspace variable containing the PLS response/design matrix V.'), ...
                        struct('name','cu','type','numeric_vector','default',1,'label','Sparse PLS U constraint(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','method','equals','spls'), ...
                    'help','Sparsity constraint candidate(s) for the PLS U projection.'), ...
                        struct('name','cv','type','numeric_vector','default',1,'label','Sparse PLS V constraint(s)', ...
                            'allowEmpty',false, 'visibleIf',struct('field','method','equals','spls'), ...
                    'help','Sparsity constraint candidate(s) for the PLS V projection.')};

                case 'fastICA'
                    spec.cliConfigurator = 'cv_fastICA_config';
                    spec.fields = { ...
                        struct('name','tolerance','type','numeric_vector','default',1e-4,'allowEmpty',false, ...
                            'label','Tolerance parameter(s)', ...
                    'help','Convergence tolerance candidate(s) supplied to fastICA.'), ...
                        struct('name','max_iters','type','numeric_vector','default',200,'allowEmpty',false, ...
                            'label','Maximum iteration value(s)', ...
                    'help','Maximum iteration-count candidate(s) supplied to fastICA.'), ...
                        struct('name','algorithm_opt','type','enum','default','parallel','label','fastICA algorithm', ...
                            'values',{{'parallel','deflation'}}, ...
                    'help','Choose parallel or deflationary fastICA component estimation.'), ...
                        struct('name','whiten_opt','type','enum','default','unit-variance','label','Whitening strategy', ...
                            'values',{{'unit-variance','arbitrary-variance'}}, ...
                    'help','Choose the fastICA whitening normalization strategy.'), ...
                        struct('name','fun_opt','type','enum','default','logcosh','label','G-function', ...
                            'values',{{'logcosh','exp','cube'}}, ...
                    'help','Choose the contrast/nonlinearity function used by fastICA.')};

                otherwise
                    spec.status = 'unknown';
                    spec.fields = {};
            end
        end

        function cfg = defaultParams(method, ctx)
            % defaultParams  Return default parameters for a nested method/algorithm.
            %   Defaults come from the method schema and are normalized before parent modules embed
            %   them into canonical configs.

            if nargin < 2, ctx = struct(); end
            cfg = NMConfigTools.defaultsFromSpec(NMDimRedSubconfigLibrary.spec(method, ctx));
        end

        function [cfg, report] = validateParams(method, cfg, ctx, strict)
            % validateParams  Validate nested method/algorithm parameters.
            %   Returns normalized params and a report so parent modules can distinguish strict API
            %   errors from permissive legacy import repair.

            if nargin < 3, ctx = struct(); end
            if nargin < 4, strict = false; end
            spec = NMDimRedSubconfigLibrary.spec(method, ctx);
            [cfg, report] = NMConfigTools.validateConfig(spec, cfg, ctx, strict);
        end

        function params = normalizeParams(method, params, ctx)
            % normalizeParams  Normalize nested parameters or raise if validation fails.
            %   Used immediately before legacy export so generated ACTPARAM branches use canonical,
            %   backend-compatible values.

            if nargin < 2 || isempty(params) || ~isstruct(params), params = struct(); end
            if nargin < 3, ctx = struct(); end
            [params, report] = NMDimRedSubconfigLibrary.validateParams(method, params, ctx, false);
            if ~report.ok
                error('NMDimRedSubconfigLibrary:invalidParams', '%s', strjoin(report.errors, newline));
            end
        end

        function [DR, PX] = applyToLegacy(DR, cfg, ctx, pxAddFcn)
            % applyToLegacy  Write nested method parameters into an existing legacy branch.
            %
            % Parent modules call this while materializing ACTPARAM fields so algorithm-specific
            % translation stays isolated here.
            %
            % cfg.method: stores the selected algorithmic method inside a normalized module configuration.
            % cfg.methodParams: stores the normalized method params value in the module configuration.

            if nargin < 3, ctx = struct(); end
            if nargin < 4 || isempty(pxAddFcn)
                error('NMDimRedSubconfigLibrary:missingPxAddFcn','PX construction helper is required.');
            end
            method = NMDimRedSubconfigLibrary.canonicalMethod(cfg.method);
            params = struct();
            if isfield(cfg,'methodParams') && isstruct(cfg.methodParams)
                params = cfg.methodParams;
            end
            params = NMDimRedSubconfigLibrary.normalizeParams(method, params, ctx);
            PX = [];

            switch method
                case 'PCA'
                    DR.DRsoft = 1;
                    PX = pxAddFcn([], [], [], [], 'reset');

                case {'RobPCA','FactorAnalysis','LDA','GDA','LMNN','optNMF'}
                    PX = pxAddFcn([], [], [], [], 'reset');

                case 'NNMF'
                    PX = pxAddFcn([], [], [], [], 'reset');
                    DR.NMFmethod = params.nmfMethod;
                    DR.options.dis = double(logical(params.display));

                case 'NeNMF'
                    DR.NMFmethod = params.nmfMethod;
                    DR.tmax = params.tmax;
                    PX = pxAddFcn([], [], [], [], 'reset');

                case 'SparsePCA'
                    DR.DRsoft = 1;
                    DR.SparsePCA.lambda = params.lambda;
                    DR.SparsePCA.stop = params.stop;
                    DR.SparsePCA.maxiter = params.maxiter;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.SparsePCA.lambda, 'SparsePCA-Lambda', 1, 'replace');
                    PX = pxAddFcn(PX, DR.SparsePCA.stop,   'SparsePCA-Stop',   1, '');
                    PX = pxAddFcn(PX, DR.SparsePCA.maxiter,'SparsePCA-Iter',   1, '');

                case 'ProbPCA'
                    DR.ProbPCA.iter = params.iter;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.ProbPCA.iter, 'ProbPCA-Iter', 1, 'replace');

                case 'LPP'
                    DR.LPP.Sigma = params.sigma;
                    DR.LPP.k = params.k;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.LPP.Sigma, 'LPP-Sigma', 1, 'replace');
                    PX = pxAddFcn(PX, DR.LPP.k,     'LPP-K',     1, '');

                case 'LLTSA'
                    DR.LLTSA.k = params.k;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.LLTSA.k, 'LLTSA-K', 1, 'replace');

                case 'Laplacian'
                    DR.Laplacian.k = params.k;
                    DR.Laplacian.s = params.sigma;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.Laplacian.k, 'Laplacian-K',     1, 'replace');
                    PX = pxAddFcn(PX, DR.Laplacian.s, 'Laplacian-Sigma', 1, '');

                case 'LLE'
                    DR.LLE.k = params.k;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.LLE.k, 'LLE-K', 1, 'replace');

                case 'NCA'
                    DR.NCA.lambda = params.lambda;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.NCA.lambda, 'NCA-Lambda', 1, 'replace');

                case 'PLS'
                    [DR.PLS, PX] = NMDimRedSubconfigLibrary.plsToLegacy(params, ctx, pxAddFcn);

                case 'fastICA'
                    DR.DRsoft = 1;
                    DR.dimmode = 1;
                    DR.tolerance = params.tolerance;
                    DR.max_iters = params.max_iters;
                    DR.algorithm_opt = params.algorithm_opt;
                    DR.whiten_opt = params.whiten_opt;
                    DR.fun_opt = params.fun_opt;
                    PX = pxAddFcn([], [], [], [], 'reset');
                    PX = pxAddFcn(PX, DR.tolerance, 'FastICA_tol',      1, '');
                    PX = pxAddFcn(PX, DR.max_iters, 'FastICA_max_iter', 1, '');

                otherwise
                    PX = pxAddFcn([], [], [], [], 'reset');
            end
        end

        function params = fromLegacy(method, DR, ctx)
            % fromLegacy  Import nested method parameters from a legacy payload.
            %   Preserves older ACTPARAM fields while returning canonical params suitable for UI
            %   display and later re-export.

            if nargin < 3, ctx = struct(); end
            params = NMDimRedSubconfigLibrary.defaultParams(method, ctx);
            if isempty(DR) || ~isstruct(DR), return; end
            method = NMDimRedSubconfigLibrary.canonicalMethod(method);

            switch method
                case 'NNMF'
                    if isfield(DR,'NMFmethod'), params.nmfMethod = DR.NMFmethod; end
                    if isfield(DR,'options') && isstruct(DR.options) && isfield(DR.options,'dis')
                        params.display = logical(DR.options.dis);
                    end
                case 'NeNMF'
                    if isfield(DR,'NMFmethod'), params.nmfMethod = DR.NMFmethod; end
                    if isfield(DR,'tmax'), params.tmax = DR.tmax; end
                case 'SparsePCA'
                    if isfield(DR,'SparsePCA') && isstruct(DR.SparsePCA)
                        if isfield(DR.SparsePCA,'lambda'),  params.lambda = DR.SparsePCA.lambda; end
                        if isfield(DR.SparsePCA,'stop'),    params.stop = DR.SparsePCA.stop; end
                        if isfield(DR.SparsePCA,'maxiter'), params.maxiter = DR.SparsePCA.maxiter; end
                    end
                case 'ProbPCA'
                    if isfield(DR,'ProbPCA') && isfield(DR.ProbPCA,'iter'), params.iter = DR.ProbPCA.iter; end
                case 'LPP'
                    if isfield(DR,'LPP')
                        if isfield(DR.LPP,'Sigma'), params.sigma = DR.LPP.Sigma; end
                        if isfield(DR.LPP,'k'),     params.k = DR.LPP.k; end
                    end
                case 'LLTSA'
                    if isfield(DR,'LLTSA') && isfield(DR.LLTSA,'k'), params.k = DR.LLTSA.k; end
                case 'Laplacian'
                    if isfield(DR,'Laplacian')
                        if isfield(DR.Laplacian,'k'), params.k = DR.Laplacian.k; end
                        if isfield(DR.Laplacian,'s'), params.sigma = DR.Laplacian.s; end
                    end
                case 'LLE'
                    if isfield(DR,'LLE') && isfield(DR.LLE,'k'), params.k = DR.LLE.k; end
                case 'NCA'
                    if isfield(DR,'NCA') && isfield(DR.NCA,'lambda'), params.lambda = DR.NCA.lambda; end
                case 'PLS'
                    if isfield(DR,'PLS'), params = NMDimRedSubconfigLibrary.plsFromLegacy(DR.PLS, ctx); end
                case 'fastICA'
                    if isfield(DR,'tolerance'),     params.tolerance = DR.tolerance; end
                    if isfield(DR,'max_iters'),     params.max_iters = DR.max_iters; end
                    if isfield(DR,'algorithm_opt'), params.algorithm_opt = DR.algorithm_opt; end
                    if isfield(DR,'whiten_opt'),    params.whiten_opt = DR.whiten_opt; end
                    if isfield(DR,'fun_opt'),       params.fun_opt = DR.fun_opt; end
            end
            try
                params = NMDimRedSubconfigLibrary.normalizeParams(method, params, ctx);
            catch
                % Keep imported legacy values permissive.
            end
        end

        function [PLS, PX] = plsToLegacy(params, ctx, pxAddFcn)
            % plsToLegacy  Translate PLS-specific dimensionality-reduction parameters to legacy fields.
            %
            % Used by applyToLegacy for PLS variants because their label/source and component
            % options differ from generic reduction settings.
            %
            % ctx.NM: provides the current NeuroMiner structure to preprocessing execution helpers without direct global access.
            % params.covariateColumns: provides the covariate columns setting consumed by this configuration step.
            % params.cu: provides the cu setting consumed by this configuration step.
            % params.cv: provides the cv setting consumed by this configuration step.
            % params.labelMatrixSource: provides the label matrix source setting consumed by this configuration step.
            % params.method: provides the method setting consumed by this configuration step.
            % params.workspaceMatrixVar: provides the workspace matrix var setting consumed by this configuration step.

            PLS = struct();
            PLS.algostr = params.method;
            PLS.uselabel = 1;
            if strcmp(params.labelMatrixSource,'nm_covars')
                PLS.uselabel = 2;
                if isfield(params,'covariateColumns'), PLS.covsel = params.covariateColumns; end
                if isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'covars') && ~isempty(params.covariateColumns)
                    try, PLS.V = ctx.NM.covars(:,params.covariateColumns); catch, end
                end
            elseif strcmp(params.labelMatrixSource,'workspace')
                PLS.uselabel = 3;
                if ~isempty(params.workspaceMatrixVar)
                    PLS.V = NMDimRedSubconfigLibrary.resolveWorkspaceVar(params.workspaceMatrixVar);
                end
            elseif strcmp(params.labelMatrixSource,'legacy')
                PLS.uselabel = 3;
            else
                PLS.uselabel = 1;
                if isfield(ctx,'NM') && isstruct(ctx.NM) && isfield(ctx.NM,'label')
                    try
                        if exist('nk_MakeDummyVariables','file') == 2
                            PLS.V = nk_MakeDummyVariables(ctx.NM.label);
                        else
                            PLS.V = ctx.NM.label;
                        end
                    catch
                        PLS.V = ctx.NM.label;
                    end
                end
            end
            PLS.cu = params.cu;
            PLS.cv = params.cv;
            PX = pxAddFcn([], [], [], [], 'reset');
            if strcmp(PLS.algostr,'spls')
                PX = pxAddFcn(PX, PLS.cu, 'SPLS-cu', 1, '');
                PX = pxAddFcn(PX, PLS.cv, 'SPLS-cv', 1, '');
            else
                PX = pxAddFcn([], [], [], [], 'reset');
            end
        end

        function params = plsFromLegacy(PLS, ctx)
            % plsFromLegacy  Recover PLS-specific dimensionality-reduction parameters from legacy fields.
            %   Complements plsToLegacy so imported projects can be represented in canonical nested
            %   config form.

            if nargin < 2, ctx = struct(); end
            params = NMDimRedSubconfigLibrary.defaultParams('PLS', ctx);
            if isempty(PLS) || ~isstruct(PLS), return; end
            if isfield(PLS,'algostr'), params.method = PLS.algostr; end
            if isfield(PLS,'uselabel')
                switch PLS.uselabel
                    case 2, params.labelMatrixSource = 'nm_covars';
                    case 3, params.labelMatrixSource = 'legacy';
                    otherwise, params.labelMatrixSource = 'nm_labels';
                end
            end
            if isfield(PLS,'covsel'), params.covariateColumns = PLS.covsel; end
            if isfield(PLS,'cu'), params.cu = PLS.cu; end
            if isfield(PLS,'cv'), params.cv = PLS.cv; end
        end

        function val = resolveWorkspaceVar(name)
            % resolveWorkspaceVar  Resolve a named MATLAB workspace variable for nested config export.
            %   Used when power-user configs reference matrices/vectors by name rather than
            %   embedding large arrays in module configs.

            val = [];
            if isempty(name), return; end
            try
                val = evalin('base', char(name));
            catch ME
                error('NMDimRedSubconfigLibrary:workspaceVar', 'Could not resolve workspace variable %s: %s', char(name), ME.message);
            end
        end

        function sf = safeField(id)
            % safeField  Convert an arbitrary id to a valid lower-case MATLAB struct field.
            %   Used to build schema maps whose fields are stable even when method ids contain mixed
            %   case or punctuation.

            sf = lower(regexprep(char(id),'[^A-Za-z0-9_]','_'));
            if isempty(sf) || ~isletter(sf(1)), sf = ['m_' sf]; end
        end



        function method = canonicalMethod(method)
            % canonicalMethod  Normalize dimensionality-reduction method aliases.
            %   Accepts UI/API/legacy spellings and returns the canonical token used by schemas and
            %   legacy translation.

            s = lower(char(method));
            switch s
                case 'pca', method = 'PCA';
                case 'robpca', method = 'RobPCA';
                case 'nnmf', method = 'NNMF';
                case 'optnmf', method = 'optNMF';
                case 'nenmf', method = 'NeNMF';
                case 'pls', method = 'PLS';
                case 'sparsepca', method = 'SparsePCA';
                case 'probpca', method = 'ProbPCA';
                case {'factoranalysis','factor_analysis'}, method = 'FactorAnalysis';
                case 'lpp', method = 'LPP';
                case 'lltsa', method = 'LLTSA';
                case 'lmnn', method = 'LMNN';
                case 'lda', method = 'LDA';
                case 'nca', method = 'NCA';
                case 'fastica', method = 'fastICA';
                case 'gda', method = 'GDA';
                case 'laplacian', method = 'Laplacian';
                case 'lle', method = 'LLE';
                otherwise, method = char(method);
            end
        end

        function t = title(method)
            % title  Return a readable title for a nested method/algorithm.
            %   Used by config schemas, UI controls, and RAG documentation instead of exposing raw
            %   legacy command ids.

            method = NMDimRedSubconfigLibrary.canonicalMethod(method);
            switch char(method)
                case 'PCA', t = 'Principal Component Analysis';
                case 'RobPCA', t = 'Robust Principal Component Analysis';
                case 'NNMF', t = 'Non-negative Matrix Factorization';
                case 'optNMF', t = 'Orthogonal Projective NNMF';
                case 'NeNMF', t = 'Nesterov NNMF';
                case 'PLS', t = 'Partial Least Squares';
                case 'SparsePCA', t = 'Sparse PCA';
                case 'ProbPCA', t = 'Probabilistic PCA';
                case 'FactorAnalysis', t = 'Factor analysis';
                case 'LPP', t = 'Locality Preserving Projections';
                case 'LLTSA', t = 'Linear Local Tangent Space Alignment';
                case 'LMNN', t = 'Large-Margin Nearest Neighbour';
                case 'LDA', t = 'Linear Discriminant Analysis';
                case 'NCA', t = 'Neighborhood Component Analysis';
                case 'fastICA', t = 'Independent Component Analysis';
                case 'GDA', t = 'General Discriminant Analysis';
                case 'Laplacian', t = 'Laplacian Eigenmaps';
                case 'LLE', t = 'Local Linear Embedding';
                otherwise, t = char(method);
            end
        end

        function d = description(method)
            % description  Return explanatory text for a nested method/algorithm.
            %   Provides human-readable method context for UI help, API users, and documentation
            %   extraction.

            method = NMDimRedSubconfigLibrary.canonicalMethod(method);
            switch char(method)
                case {'PCA','RobPCA','FactorAnalysis','LDA','GDA','LMNN'}
                    d = 'This method has no additional method-specific options in the legacy dimensionality-reduction configurator.';
                case 'fastICA'
                    d = 'fastICA parameters mirror cv_fastICA_config; extraction dimensionality is controlled by the parent reducedim/extdim dimensionality fields.';
                case 'PLS'
                    d = 'PLS configuration mirrors nk_PLS_config and is shared conceptually with ranking/ML configurations.';
                otherwise
                    d = sprintf('Method-specific options for %s, mapped to the legacy DR structure and PX shelf where applicable.', char(method));
            end
        end
    end
end
