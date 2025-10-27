classdef nm_shapley
    % SHAPLEY Explain model predictions using Shapley values
    %   SHAPLEY creates an explainer that can be used to compute Shapley
    %   values for all predictors. Shapley values are fair allocations, to
    %   individual players, of the total gain generated from a cooperative
    %   game. In the context of machine learning prediction, the deviation of
    %   a prediction from the average prediction can be explained using
    %   Shapley values. Specifically, Shapley values for all predictors, of
    %   an instance of interest, together sum up to the deviation of this
    %   instance's predicted score/response from the average score/response.
    %
    %   EXPLAINER = SHAPLEY(BLACKBOX) initializes a shapley explainer EXPLAINER
    %   using a supervised learning model BLACKBOX. If this model is a full
    %   classification/regression model, then the predictor data, X need not be
    %   specified.
    %
    %   EXPLAINER = SHAPLEY(BLACKBOX,X) initializes a shapley explainer
    %   EXPLAINER using a supervised learning model BLACKBOX and predictor data
    %   X. If BLACKBOX is a compact model or a model without data, then X is
    %   required. X is also required when BLACKBOX is a function handle.
    %   Optionally, if X is specified for a full model, SHAPLEY uses this
    %   specified X instead of the training data stored in the model itself.
    %
    %   EXPLAINER = SHAPLEY(BLACKBOX,'QueryPoint',QUERYPOINT) uses the
    %   'QueryPoint' name-value pair argument to compute shapley values for a
    %   query point, QUERYPOINT and returns a fitted explainer EXPLAINER.
    %
    %   EXPLAINER = fit(EXPLAINER,QUERYPOINT) returns a new fitted explainer
    %   for a new query point QUERYPOINT, using the already initialized
    %   explainer EXPLAINER.
    %
    %   plot(EXPLAINER) produces a bar chart for a fitted shapley explainer
    %   EXPLAINER.
    %
    %   shapley Properties:
    %      BlackboxModel          - Model to be explained
    %      BlackboxFitted         - Query point prediction computed by the model
    %      QueryPoint             - Observation whose prediction is to be explained
    %      ShapleyValues          - Shapley values for the query point
    %      NumSubsets             - Total number of subsets of predictors
    %      X                      - Predictor data of the blackbox model
    %      Y                      - Label data of the blackbox model's predictor data
    %      CategoricalPredictors  - Categorical predictor indices
    %      Method                 - Shapley computation technique
    %      Intercept              - Intercept Shapley value or the average model evaluation
    %      Type                   - Model type
    %      Algorithm              - Model algorithm
    %      isModelObject          - Classification/regression model object
    %   shapley Methods:
    %      shapley - Initialize a shapley explainer
    %      fit     - Compute Shapley values for a new query point
    %      plot    - Visualize Shapley value
    %   Example:
    %      % Train a classification tree and explain its predictions
    %      load fisheriris
    %      mdl = fitctree(meas,species);
    %      q1 = meas(1,:);
    %      % Explain this query point and plot the results
    %      explainer = shapley(mdl,'QueryPoint', q1);
    %      plot(explainer);
    %      % Explain another query point and examine the Shapley values
    %      q2 = meas(2,:);
    %      explainer = fit(explainer, q2);
    %      explainer.ShapleyValues

    %   Copyright 2020-2021 The MathWorks Inc.

    properties (SetAccess =protected , GetAccess=public)
        %BLACKBOXMODEL - Model to be explained
        %   The  BlackboxModel property is either a
        %   regression/classification model or a function handle.
        BlackboxModel

        %QUERYPOINT - Observation whose prediction is to be explained
        %    The QueryPoint property is a row vector or a single-row table
        %    containing predictors of a query point.
        QueryPoint

        % BLACKBOXFITTED - Prediction for the query point computed by the model
        %   The BlackboxFitted property is a scalar that is the first
        %   output of either the predict() function or the function handle
        %   evaluation.
        BlackboxFitted

        % SHAPLEYVALUES - Shapley values for the query point
        %   The ShapleyValues property is a table of shapley values
        %   containing shapley values for every predictor.
        ShapleyValues

        % NUMSUBSETS - Total number of subsets of predictors used by the algorithm
        %    The NumSubsets property is a scalar integer.
        NumSubsets = 1024

        % X - Predictor data, specified as a numeric matrix or table
        %    Each row of X corresponds to one observation, and each column
        %    corresponds to one variable.
        X

        % Y - Label data, specified as a numeric vector
        %    Each row of Y corresponds to the labels of one observation
        Y

        % CATEGORICALPREDICTORS - Indices of categorical predictors
        %   The CategoricalPredictors property is an array with indices of
        %   categorical predictors. The indices are in the range from 1 to the
        %   number of predictors in X.
        CategoricalPredictors = []

        % METHOD - Shapley computation technique
        %   The Method property is character vector with a value of either
        %   'interventional-kernel' or 'conditional-kernel'.
        Method = 'interventional-kernel'

        % INTERCEPT - Intercept Shapley value or the average model evaluation
        %   The Intercept property is a vector of average classification
        %   scores or probabilities, averaged over X, for classification
        %   and a scalar average response/function evaluation for
        %   regression/function handles. The Shapley values for all predictors
        %   when added to the intercept equal the model evaluation
        %   (score/response/function handle evaluation) at the query point.
        Intercept

        % MODELTYPE - char vector defining model type
        %   The ModelType property is character vector with a value of either
        %   'classification' or 'regression'.
        Type = 'classification'

        % ALGORITHM - char vector defining classification or regression
        % algorithm
        %   The Algorithm property is character vector with a value of either
        %   'libsvm312' or 'liblin244'.
        Algorithm = 'svmtrain312'

        % ISMODELOBJECT - boolean defining whether model is classification/regression model object
        %   The isModelObject property is logical indicating whether the
        %   model is a classification/regression model object (TRUE) or not
        %   (FALSE) i.e. a LIBSVM or LIBLINEAR model
        isModelObject

    end

    % cache some values that are used in multiple places
    properties (Access=protected)
        NumClasses % scalar : is populated for classification problems
        TableInput % boolean:  whether X is table
        IsFunctionHandle % boolean : whether BlackboxModel is a function handle
    end

    properties (Hidden) % debugging related properties
        UseParallel = false
    end


    methods
        function this = nm_shapley(mdl,varargin)
            %SHAPLEY Initialize a shapley explainer
            %   EXPLAINER = SHAPLEY(BLACKBOX) initializes a shapley explainer
            %   EXPLAINER using a supervised learning model BLACKBOX. If this model is
            %   a full classification/regression model, then the predictor data, X
            %   need not be specified.
            %
            %   EXPLAINER = SHAPLEY(BLACKBOX,X) initializes a shapley explainer
            %   EXPLAINER using a supervised learning model BLACKBOX and predictor
            %   data X. If BLACKBOX is a compact model or a model without data, then X
            %   is required. X is also required when BLACKBOX is a function handle.
            %   Optionally, if X is specified for a full model, SHAPLEY uses this
            %   specified X instead of the training data stored in the model itself.
            %
            %
            %   EXPLAINER = SHAPLEY(...,'Name1',Value1,'Name2',Value2,...) specifies
            %   any of the following optional name-value arguments:
            %
            %   'QueryPoint'    - A data instance for which an explanation is to be provided.
            %                     It is specified either as a row vector of numeric
            %                     values or a single-row table. When QueryPoint is
            %                     specified, SHAPLEY also computes the shapley values
            %                     and stores them in the ShapleyValues property of the
            %                     explainer.
            %
            %   'Method'        - Underlying shapley computation algorithm.
            %                     Choices are as follows:
            %                     'interventional-kernel'- Uses the kernelSHAP algorithm,
            %                         (default)            with an interventional value function,
            %                                              proposed by Lundberg and
            %                                              Lee (2017).
            %                     'conditional-kernel'   - Uses the extension to kernelSHAP,
            %                                              with a conditional value function,
            %                                              proposed by Aas et al.
            %                                              (2019).
            %
            %   'MaxNumSubsets' - Maximum number of predictor subsets to use.
            %                     Default: min(2^M, 1024), where M is the total number
            %                     of predictors.
            %
            %   'UseParallel'   - Use parpool to parallelize computation.
            %                     Choices are logical scalars : false (default), true.
            %
            %   'CategoricalPredictors'  -  List of categorical predictors.
            %                     Pass 'CategoricalPredictors' as one of:
            %                     * A numeric vector with indices between 1 and P,
            %                       where P is the number of predictor variables.
            %                     * A logical vector of length P, where a true
            %                       entry means that the corresponding predictor is a
            %                       categorical variable.
            %                     * 'all', meaning all predictors are categorical.
            %                     * A string array or cell array of character
            %                       vectors, where each element in the array is the
            %                       name of a predictor variable. The names must match
            %                       the variable names in table X.
            %                     Default: for a matrix X, no categorical predictors; for
            %                     a table X, predictors are treated as categorical if
            %                     they are strings, cell arrays of character vectors,
            %                     logical, or of type 'categorical'.

            % ============ validate mdl ==============
            isAClassificationModel = isa(mdl,'classreg.learning.classif.ClassificationModel');
            isARegressionModel = isa(mdl,'classreg.learning.regr.RegressionModel');
            isFunctionHandle = isa(mdl, 'function_handle');

            isValidModel = isAClassificationModel || isARegressionModel || isFunctionHandle;
            this.isModelObject = isValidModel;
            %             if ~isValidModel
            %                 if Type == "classification"
            %                     isAClassificationModel = true;
            %                 elseif Type == "regression"
            %                     isARegressionModel = true;
            %                 else
            %                     error(message('stats:lime:InvalidBlackboxModel'));
            %                 end
            %             else
            % valid model, assign type for internal use
            if isAClassificationModel
                this.Type = "classification";
            elseif isARegressionModel
                this.Type = "regression";
            elseif isValidModel % function handle treated like a regression problem always, we expect the user to provide us with the scoring function
                this.Type = "regression";
            end


            this.BlackboxModel = mdl; % assign the model to the object
            this.IsFunctionHandle = isFunctionHandle;

            % NumClasses is a property so that we evaluate the size once,
            % empty for regression and function handles
            if ~isValidModel
                this.NumClasses = mdl.nr_class;
            else
                if this.Type =="classification"
                    this.NumClasses = numel(mdl.ClassSummary.ClassNames);
                end
            end

            if ~isFunctionHandle
                if ~isValidModel
                    defaultCategoricals = []; %could be adjusted if this information is made available in NM
                else
                    defaultCategoricals = mdl.CategoricalPredictors;
                end
            else
                defaultCategoricals = [];
            end

            % ============ parse optional inputs ==============
            shapparser = inputParser;
            shapparser.KeepUnmatched = true;
            % add size and type checks
            shapparser.addOptional('X',[], @(arg)validateattributes(arg,{'double','single','table'},{'2d','nonempty'}));
            
            
            shapparser.addParameter('QueryPoint',[],...
                @(arg)validateattributes(arg, {'double','single','table'},{'row','nonempty'}));

            shapparser.addParameter('Y',[], ...
                @(arg)validateattributes(arg,{'double','single'}, {'2d','nonempty'}));

            shapparser.addParameter('Type',[],...
                @(arg)validateattributes(arg,{'char','string'}, {'2d','nonempty'}));
            
            shapparser.addParameter('Algorithm',[],...
                @(arg)validateattributes(arg,{'char','string'}, {'2d','nonempty'}));

            shapparser.addParameter('CategoricalPredictors',defaultCategoricals,...
                @(arg)validateattributes(arg,{'numeric','logical','char','string','cell'}, {'2d','nonempty'})); % just do a type check here, the validation will be done further down
            
            shapparser.parse(varargin{:});
            parsedResults = shapparser.Results;
            if ~isValidModel %alternative: if ~isempty(parsedResults.Type)
                this.Type = parsedResults.Type;
                this.Algorithm = parsedResults.Algorithm;
            end
            Xin = parsedResults.X;
            Yin = parsedResults.Y;
            this.Y = Yin;
            
            if isempty(Xin)
                if ~isa(mdl, "classreg.learning.FullClassificationRegressionModel")
                    error(message('stats:shapley:NoPredictorData'));
                else
                    modelX = mdl.X; % for a full model assign to training data
                    this.TableInput = istable(modelX);
                    this.X = modelX;
                end
            end

            if isFunctionHandle
                f = mdl;
            else
                if ~isValidModel
                    if this.Algorithm == "svmtrain312"
                        f = @(x)svmpredict312(Yin, sparse(x), mdl); 
                    elseif this.Algorithm == "liblin244"
                        f = @(x)predict_liblin244(Yin, sparse(x), mdl);
                    else
                        error('Unknown learning algorithm')
                    end
                else
                    f = @(x)predict(mdl,x);
                end
            end
            % ============ validate X only if passed ==============

            if ~isempty(Xin) % user specifies X
                try % check if bad data was provided
                    if ~isValidModel
                         [~,~,out] = f(Xin);
                         %this is not exactly correct -> it needs to be
                         %likelihood but the output is the decision scores
                         out(:,2) = out;
                         out(:,1) = -out(:,1);
                    else
                        if this.Type =="classification"
                            [~,out] = f(Xin);
                        else
                            out = f(Xin);
                        end
                    end
                catch ME
                    baseException = MException(message('stats:lime:BlackboxPredictError'));
                    throw(addCause(baseException,ME));
                end
                if isFunctionHandle
                    validateattributes(out,{'double','single'}, {'column','nonempty'}, mfilename,getString(message('stats:shapley:FunctionHandleOutput')));
                end
                tableinput = isa(Xin, 'table');
                this.X = Xin;
                this.TableInput = tableinput;
                varargin = varargin(2:end); % remove X from varargin
            else
                if this.Type =="classification"
                    [~,out] = f(modelX);
                else
                    out = f(modelX);
                end
            end
            this.Intercept = mean(out,1, 'omitnan'); % use nanmean
            thisX = this.X;

            % ============= validate CategoricalPredictors ============
            catpreds = parsedResults.CategoricalPredictors;
            if ~isempty(catpreds)
                catpreds  = convertStringsToChars(catpreds);% for string arrays and scalar "all"
                M = numPredictors(this);
                if isFunctionHandle % for function handles, all table variables are predictor names
                    if istable(thisX)
                        % for tables, there are implicit assumptions about which
                        % types are treated as categorical, catch conflicts that
                        % arise from such assumptions
                        prednames = thisX.Properties.VariableNames;
                        try
                            classreg.learning.internal.table2FitMatrix(thisX(1,:),[], ...
                                'cat', catpreds); % try this to catch bad CategoricalPredictors early
                        catch ME
                            throwAsCaller(ME);
                        end
                    else
                        prednames = M;
                        if (ischar(catpreds) && ~strcmpi('all',catpreds)) || iscellstr(catpreds) % for function handles if char/cellstr CategoricalPredictors are provided error out early
                            error(message('stats:classreg:regr:plotPartialDependence:MatrixFuncHandleCatPreds')); % throw an informative error message that partial dependence uses
                        end
                    end
                else
                    prednames = mdl.PredictorNames;
                end
                % validate categorical predictors, use an existing utility
                % from the semisupervised package, it has the same error
                % checking as classreg
                try
                    catpreds = semisupervised.Model.validateCategoricalPredictors(catpreds,prednames,M);
                catch ME
                    throwAsCaller(ME);
                end
                % ensure that the categorical predictors inside the model
                % match with the user input
                if ~isFunctionHandle && (numel(catpreds)~=numel(mdl.CategoricalPredictors) || any(~ismember(catpreds, mdl.CategoricalPredictors)))
                    error(message('stats:lime:DiffBBandNVP'));
                end
            end

            isOrdinal = false; % check for ordinal predictors too

            if isFunctionHandle && istable(thisX) % there might be more predictors inferred as categorical for table inputs and function handles
                x = thisX(1,:); % thisX is non-empty for function handles, just take one row out for type inference
                [~,~,~,~,args] = classreg.learning.internal.table2FitMatrix(x,[], 'CategoricalPredictors', catpreds);
                catpreds = args{2}; % this is the superset of all categorical predictors both numeric and inferred ones
                isOrdinal = any(args{6});
                catpreds = find(catpreds); % convert to indices
                if isempty(catpreds)
                    catpreds = []; % avoid the [1x0] display
                end
            end


            if ~isFunctionHandle && isValidModel %maybe in future this can be done if variable type known in NM
                dataSummary = mdl.DataSummary;
                if isfield(dataSummary,'OrdinalPredictors')
                    isOrdinal = any(dataSummary.OrdinalPredictors);
                end
            end
            this.CategoricalPredictors = catpreds;

            % ============ do a fit if necessary ==============
            % parse q and delegate the rest of the parsing and validating to fit()
            q = parsedResults.QueryPoint;
            if ~isempty(q) % if the user passes q, return a fitted object
                % remove the QueryPoint from the passed arguments, fit does not accept it as a name-value parameter.
                % but a positional argument
                [varargin{:}] = convertStringsToChars(varargin{:}); % parseArgs expects cellstrs
                %remove arguments 'Type' and 'Algorithm from varargin
                index = false(1, numel(varargin));
                for k = 1:numel(varargin)
                    if ischar([varargin{k}])
                        index(k) = or(([varargin{k}] == "Type"), or(([varargin{k}] == "Algorithm"), ([varargin{k}] == "Y")));
                    end
                end
                index2 = [false,index(1:end-1)];
                varargin(index)=[];
                index2(index)=[];
                varargin(index2)=[];
                [~,~,~,fitArgs] = internal.stats.parseArgs({'QueryPoint','CategoricalPredictors'},{[]}, varargin{:});

                % pass the rest of the parameters to fit, q and the rest of the parameters will also be
                % validated in fit(), also fit() will throw an error for
                % ordinals and conditional because distance cannot be
                % calculated for ordinals
                this = fit(this,q,fitArgs{:});
            else % if no query point is specified parse other arguments that modify object properties
                [varargin{:}] = convertStringsToChars(varargin{:}); % parseArgs expects cellstrs
    % TODO? further arguments needed to pass to function? Such as 
    % isValidModel (see above)? -> isValidModel is saved in
    % this.isModelObject
    % ToDo: get rid of Type, Algorithm, Y, because these are already stored 
    % in this and might complicate things in downstream functions -> see
    % above
                [~,~,fitArgs] = internal.stats.parseArgs({'CategoricalPredictors'},{[]}, varargin{:}); % weed out categorical predictors
                [method,numsubsets] = parseAndValidateFitArgs(this,fitArgs{:});
                % ======assign properties======
                this.NumSubsets = numsubsets;
                this.Method = char(method); % ensure that this property is always stored as char

                % if ordinal predictors are present and conditional method
                % is used, error out
                if method=="conditional-kernel"
                    shapley.checkForOrdinalsInData(thisX,isOrdinal); % this check is the same as the one done in fit() because the user can also modify "method" in fit()
                end
            end
        end

        function this = fit(this, q, varargin)
            %FIT Compute Shapley values for a new query point
            %   EXPLAINER = FIT(EXPLAINER,QUERYPOINT) modifies explainer EXPLAINER by
            %   computing Shapley values and writing them to the ShapleyValues
            %   property of the explainer.
            %
            %   EXPLAINER = FIT(EXPLAINER,QUERYPOINT,'Name1',Value1,'Name2',Value2,...)
            %   specifies any of the following optional name-value arguments:
            %
            %   'Method'       - Underlying shapley computation algorithm.
            %                    Default value is EXPLAINER.Method.
            %                    Choices are as follows:
            %                    'interventional-kernel'- Uses the kernelSHAP algorithm,
            %                                             with an interventional value function,
            %                                             proposed by Lundberg and Lee
            %                                             (2017).
            %                    'conditional-kernel'   - Uses the extension to kernelSHAP,
            %                                             with a conditional value function,
            %                                             proposed by Aas et al.
            %                                             (2019).
            %
            %   'MaxNumSubsets'- Maximum number of predictor subsets to use.
            %                    Default value is EXPLAINER.NumSubsets.
            %
            %   'UseParallel'  - Use parpool to parallelize computation.
            %                    Choices are logical scalars : false (default), true.
            %
            %   'Y'            - Label data
            %                    Needed if this.isModelObect is false


            mdl = this.BlackboxModel;
            isValidModel = this.isModelObject;
            if this.IsFunctionHandle
                f = mdl;
            else
                if ~isValidModel
                    if this.Algorithm == "svmtrain312"
                        f = @(x)svmpredict312(0, sparse(x), mdl); %Y set to 0
                    elseif this.Algorithm == "liblin244"
                        f = @(x)predict_liblin244(0, sparse(x), mdl); %Y set to 0
                    else
                        error('Unknown learning algorithm')
                    end
                else
                    f = @(x)predict(mdl,x);
                end
            end
            % ========== validate q ==========
            validateattributes(q, {'double','single','table'},{'row','nonempty'},'fit','queryPoint');
            if ~isempty(q) % can be true for any mdl
                try
                    out = f(q);
                catch ME
                    baseException = MException(message('stats:lime:BadQueryPoint'));
                    throw(addCause(baseException,ME));
                end
                if this.IsFunctionHandle
                    validateattributes(out,{'double','single'}, {'scalar','nonempty'}, mfilename,getString(message('stats:shapley:FunctionHandleOutput')));
                end
            end
            this.QueryPoint = q;

            [method,numsubsets,useparallel,M] = parseAndValidateFitArgs(this,varargin{:});

            % ======reassign/assign properties======
            this.NumSubsets = numsubsets;
            this.Method = char(method); % the property value is always stored as a char
            this.BlackboxFitted = out;

            % if blackbox score/response is nan, set shapley values to nan
            % and return early
            if this.Type == "classification"
                if isValidModel
                    [~,s] = f(q);
                else
%ToDo: check whether this is correct, compare lines 326-330
                    [~,~,s] = f(q);
                    s = [-s, s];
                end
            else
                s = out;
            end
            if any(isnan(s))
                this = makeNaNShapley(this);
                return;
            end

            % ======for the univariate edge case======
            if M ==1
                % attribute all deviation to that single feature
                phi = s - this.Intercept;
                this = makeShapleyValuesTable(this,phi);
            else
                % ======do the actual fitting======
                switch method
                    case "interventional-kernel"
                        doConditional = false;
                    case "conditional-kernel"
                        doConditional = true;
                end
                this = fitKernelSHAP(this, q, M, numsubsets, useparallel, doConditional); % SHAP stands for SHapley Additive exPlanations, as proposed by Lundberg and Lee 2017
            end
        end

        function b = plot(this, varargin)
            %PLOT Visualize Shapley values
            %   PLOT(EXPLAINER) produces a bar chart of Shapley values stored in EXPLAINER.
            %
            %   PLOT(EXPLAINER,'Name1',Value1,'Name2',Value2) specifies any of the
            %   following optional name-value arguments.
            %
            %   B = PLOT(...) produces a bar chart of Shapley values and returns a bar
            %   object or an array of bar objects.
            %
            %   'NumImportantPredictors' - Number of predictors with the highest
            %                              absolute Shapley values to show on the bar
            %                              chart. Default: min(M,10), where M is the
            %                              total number of predictors
            %   'ClassNames'             - Class names for which Shapley values need
            %                              to be plotted (only valid for
            %                              classification models). Default: Predicted
            %                              class for the query point from the Blackbox
            %                              model

            if isempty(this.ShapleyValues)
                error(message('stats:shapley:UnfittedPlot'));
            end
            plotparser = inputParser;
            mdl = this.BlackboxModel;
            if ~this.IsFunctionHandle
                prednames = mdl.PredictorNames;
                M = numel(prednames);
            else
                M = size(this.X,2);
            end
            if this.Type == "classification"
                if this.isModelObject
                    cnames = mdl.ClassSummary.ClassNames;
                else
                    cnames = mdl.ClassNames;
                end
            end
            plotparser.addParameter('NumImportantPredictors',min(M,10),...
                @(x)validateattributes(x,{'numeric'},...
                {'scalar','positive','finite', 'integer','<=',M}));
            plotparser.addParameter('ClassNames',this.BlackboxFitted,...
                @(x) validateattributes(x,{'numeric','categorical', 'char', 'string','logical', 'numeric', 'cell'},...
                {'vector','2d'})); % need 2d for char arrays
            plotparser.parse(varargin{:});

            m = plotparser.Results.NumImportantPredictors;
            userPassedClassNames = ~ismember('ClassNames', plotparser.UsingDefaults);
            isRegression = this.Type == "regression";

            if isRegression
                if userPassedClassNames % if the user specifies ClassNames
                    error(message('stats:shapley:ClassNamesInvalidForRegression'));
                end
                colidx = 1; % for regression and function handles there is only one column
            else % Classification
                userClassNames = classreg.learning.internal.ClassLabel(plotparser.Results.ClassNames);
                if  this.isModelObject
                    [~,colidx] = ismember(userClassNames,cnames);
                else 
                    [~,colidx] = ismember(cellstr(userClassNames),cnames);
                end
                if any(colidx==0)
                    error(message('stats:classreg:learning:classif:FullClassificationModel:prepareData:ClassNamesNotFound'));
                end
            end

            k = numel(colidx);
            offset = 1; % first column is features
            phi = this.ShapleyValues{:,colidx+offset};
            absolutePhi = abs(phi);
            if k == 1 % when there is only one column of phis to be plotted
                [~,predictorOrder] = sort(absolutePhi,'descend');
            else
                sums = sum(absolutePhi,2);
                [~,predictorOrder] = sort(sums,'descend');
            end
            predidx = predictorOrder(1:m);
            % bar plots from the bottom, flip the values, so that the top
            % values appear at the top
            phiToPlot = flipud(phi(predidx,:));
            preds = flipud(this.ShapleyValues.Predictor(predidx)); % top m predictors
            barObject = barh(phiToPlot);
            yticks(1:m);
            yticklabels(preds);

            % add title, labels, subtitle and if necessary, legend
            title(getString(message('stats:shapley:PlotTitle')));
            set(gca, 'TickLabelInterpreter', 'none'); % set the tick label interpreter to none
            xlabel(getString(message('stats:shapley:XLabel')));
            ylabel(getString(message('stats:shapley:YLabel')));
            if isRegression
                queryPointPrediction = num2str(this.BlackboxFitted); % for regression, this is the response
                averagePrediction = num2str(this.Intercept);
                subtitle(sprintf(getString(message('stats:shapley:PlotSubtitleForRegression',  queryPointPrediction, averagePrediction))), 'Interpreter','none');
            else % for classification use the score of the predicted class
                predictedClass = this.BlackboxFitted;
                [~,predictedClassIdx] = ismember(classreg.learning.internal.ClassLabel(predictedClass), cnames);
                [~,scores] = predict(this.BlackboxModel, this.QueryPoint);
                queryPointPrediction = num2str(scores(:,predictedClassIdx));
                averagePrediction = num2str(this.Intercept(:, predictedClassIdx));
                predictedClassString = string(predictedClass);
                subtitle(sprintf(getString(message('stats:shapley:PlotSubtitleForClassification', predictedClassString,  queryPointPrediction, averagePrediction))),'Interpreter','none');
                if userPassedClassNames % include the legend only when classnames are passed
                    l = legend(string(labels(userClassNames)),'Location','best','Interpreter','none'); % set the legend interepreter to none
                    title(l,getString(message('stats:shapley:LegendTitle')));
                end
            end

            if nargout == 1
                b = barObject;
            end
        end
    end

    methods (Hidden)

        function this = fitKernelSHAP(this,q,M,numsubsets, useParallel, doConditional)

            % coalition matrix, Z and weights for each row in Z
            [Z,wts] = nm_shapley.coalitionMatrix(M,numsubsets);

            if isempty(Z) % if no subsets besides the infinite weight subsets exist, return NaN
                this = makeNaNShapley(this);
                return;
            end

            wts = wts./sum(wts); % normalize the weights

            [thisX, q, Xmat, qmat, f, tableinput, returnNaNShapleyValues] = prepareData(this,q, doConditional);

            if returnNaNShapleyValues
                % this implies one of the following
                % (1) the query point had nans as continuous predictors and distance computation was needed
                % (2) X has NaNs in all rows and the model cannot predict for NaN data i.e. non-tree models
                % return NaN Shapley values early
                this = makeNaNShapley(this);
                return;
            end
            type = this.Type;
            if type =="classification"
                K = this.NumClasses;
            else % regression and function handle
                K = 1;
            end
            categcols = this.CategoricalPredictors;
            % the expected value computation (the most expensive step) has
            % a complexity of computing size(thisX,1)*NumSubsets
            % predictions, this scales up pretty fast e.g. for a 4
            % predictor X with a 1000 observations, this amounts to 16000
            % predictions.
            % suggest the user either downsampling or using the
            % 'UseParallel' flag
            if size(thisX,1) > 1000
                if ~useParallel
                    warning(message('stats:shapley:BigXSlowComputation'));
                else
                    warning(message('stats:shapley:BigXSlowComputationSuggestSubsample'));
                end
            end
            ev = nm_shapley.expectedValues(f, Z, type, K, thisX, q, Xmat, qmat, tableinput,categcols, useParallel, doConditional, this.isModelObject); % first column of Z is all ones (intercept)

            % account for the subsets of size M and 0 using variable
            % elimination and satisfying the sum constraint

            % 1. compute v0 and vM
            if type =="classification"
                if this.isModelObject
                    [~,scoreQueryPoint] = f(q);
                else
                    [~,~,scoreQueryPoint] = f(q);
                    scoreQueryPoint = [-scoreQueryPoint, scoreQueryPoint];
                end
                v0 = this.Intercept; % the intercept (AW: the mean of all predictions from the training sample, see line 356)
                vM = scoreQueryPoint;
            else
                v0 = this.Intercept; % the intercept
                vM = this.BlackboxFitted;
            end

            % 2. Subtract the intercept from the ev
            v = ev - v0;
            fx = vM - v0;

            % 3. solve the least squares problem
            % min (Z*phi - v)*W*(Z*phi - v) s.t sum(phi) = fx
            v = v.*sqrt(wts); % make weighted v
            Z = Z.*sqrt(wts); % make weighted Z
            % explicitly remove the constraint
            zM = Z(:,end);
            Z = Z(:,1:end-1);
            Z = Z - zM;
            phiExceptLast = pinv(Z)*(v - zM.*fx);
            phi = [phiExceptLast;fx - sum(phiExceptLast,1)]; % do not forget to add 1 to the call in sum for the edge case where phiExceptLast is a row-vector (bivariate)
            this = makeShapleyValuesTable(this,phi);

            % set the internal property UseParallel for debugging
            this.UseParallel = useParallel;
        end

        function this = makeShapleyValuesTable(this,phi)
            % ======= make a table of shapley values =========
            mdl = this.BlackboxModel;
            if ~this.IsFunctionHandle
                predictorNames = string(mdl.PredictorNames');
            else
                if this.TableInput
                    predictorNames = string(this.X.Properties.VariableNames'); % use table variable names as predictor names
                else
                    D = size(this.X,2);
                    predictorNames = string(classreg.learning.internal.defaultPredictorNames(D)');
                end
            end
            if this.Type=="classification" % ====== CLASSIFICATION ========
                classNames = string(mdl.ClassNames');
                predictorNamesTable = table(predictorNames, 'VariableNames', {'Predictor'}); % predictor
                phiTable = array2table(phi, 'VariableNames',classNames);
                this.ShapleyValues = [predictorNamesTable phiTable];
            else % ====== REGRESSION ========
                this.ShapleyValues = table(predictorNames,phi, 'VariableNames',{'Predictor',...
                    'ShapleyValue'});
            end
        end

        function [thisX, q, Xmat, qmat, f, tableinput, returnNaNShapleyValues] = prepareData(this, q, doConditional)
            % This method is used for converting tabular data and removing
            % NaN data if necessary.
            %
            % thisX and q are inputs to scoring, these are the variables used for function handle evaluation or model evaluation
            % qmat and Xmat are vector/matrix forms of thisX and q
            %
            % These are used only when needed otherwise, they remain empty.
            % e.g. vanilla kernel shap with matrix data will not lead to creation of qmat and Xmat but for table inputs and vanilla kernel shap, Xmat and qmat are still needed for faster prediction
            %
            % However, conditional kernel shap needs some preprocessing on the data for distance computation.
            % Hence, for such cases, Xmat and qmat are always needed for modification before distance computation.

            Xmat = [];
            qmat = [];
            isFunctionHandle = this.IsFunctionHandle;
            tableinput = this.TableInput;
            thisX = this.X;
            removedXNaNsAlready = false;
            categcols = this.CategoricalPredictors;
            % for tables, we must convert the original data to matrices for
            % the following purposes:
            % 1. Function handle input : if distance computation is needed i.e. the conditional approach
            % 2. Classreg model : in all cases, convert to matrices for speedy prediction

            isNonEmptyXmat = tableinput; % when Xmat is needed e.g. when the original input is a table

            isValidModel = this.isModelObject;
            if isFunctionHandle
                f = this.BlackboxModel;
            else
                mdl = this.BlackboxModel;
                if ~isValidModel
                    if this.Algorithm == "svmtrain312"
                        f = @(x)svmpredict312(zeros(size(x,1),1), sparse(x), mdl); %Y set to 0
                    elseif this.Algorithm == "liblin244"
                        f = @(x)predict_liblin244(zeros(size(x,1),1), sparse(x), mdl); %Y set to 0
                    else
                        error('Unknown learning algorithm')
                    end
                else
                    f = @(x)predict(mdl,x);
                end
            end
                

            istableq = istable(q);
            if tableinput % ============= TABLE X =========
                if isFunctionHandle
                    if ~doConditional % vanilla kernel shap
                        % Note that for vanilla kernel shap, Xmat need not be
                        % created unless q is not a table (then the function
                        % handle can evaluate on numeric matrices). For such
                        % cases convert thisX to a matrix for faster indexing.
                        % In all other cases for vanilla shap, the tables are
                        % directly passed to the evaluation.
                        if ~istable(q) % all-numeric q
                            Xmat = table2array(thisX); % table2array must be used because f can evaluate the numeric X as is and not with the encoded categories
                            % if q is a numeric matrix (and since f can predict on q, a numeric row)
                            thisX = Xmat; % this means X is an all-numeric table and can be used as a matrix to predict on matrix,
                            tableinput = false;
                        end
                    else % doConditional
                        % For the conditional method Xmat and qmat must be
                        % created for distance computation
                        %
                        % Note however, for function handles, we cannot use
                        % this  matrix for prediction, because if function
                        % handles were passed with tables, they are
                        % supposed to work with tables alone, not an
                        % encoding we use in the Statistics and Machine
                        % Learning Toolbox
                        [Xmat,~,vrange,~,args] = classreg.learning.internal.table2FitMatrix(thisX,[], 'CategoricalPredictors', categcols);
                        % For distance computation specifically we need
                        % to ensure that ordinals are not included
                        % (because no distance computation recipe
                        % exists), and throw an error for those
                        ords = args{6};
                        if any(ords)
                            error(message('stats:shapley:OrdinalsNotSupportedForConditional'));
                        end
                        prednames = args{4};

                        % the any(categcols) is not needed for function
                        % handles, it is just being added in the rarest of
                        % rare case where someone uses a classreg-like
                        % scoring function as a function handle and trains
                        % the model on a table, uses X as a table, and X
                        % has all numeric data but the user wishes to treat
                        % some of these numeric columns as categorical.
                        % Then this model will be able to predict on
                        % numeric matrices too (depends on the classreg
                        % function, but this is kind of an undocumented
                        % workflow, supported in classreg).
                        qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                            vrange,categcols, prednames,true);
                    end
                else %  A classreg model, we know the behavior of predict() and how to convert such tables
                    if doConditional
                        dataSummary = mdl.DataSummary;
                        if isfield(dataSummary,'OrdinalPredictors')
                            isOrdinal = any(dataSummary.OrdinalPredictors);
                        end
                        shapley.checkForOrdinalsInData(thisX,isOrdinal); % this check is the same as the one done in fit() because the user can also modify "method" in fit()
                    end
                    % ===== MODEL TRAINED ON A MATRIX =====
                    if ~mdl.TableInput % remember this matrix could also have categoricals in it
                        % when trained on a matrix, and a valid table is
                        % passed i.e. a table with {'x1','x2',...} as its
                        % variable names,
                        % it must be an all-numeric table,
                        % convert it to a matrix for faster operations
                        Xmat = table2array(thisX(:,mdl.PredictorNames));
                        thisX = Xmat; % for faster prediction
                        if istableq
                            qmat = table2array(q(:,mdl.PredictorNames));
                            q = qmat; % for faster prediction
                        end
                        if doConditional % encode categories if computing distances
                            qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                                mdl.DataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);
                            Xmat = classreg.learning.internal.table2PredictMatrix(thisX,[],[],...
                                mdl.DataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);
                        end
                        tableinput = false;
                    else % ===== MODEL TRAINED ON A TABLE =====
                        if all(cellfun(@isempty, mdl.DataSummary.VariableRange)) % means all-numeric table, do not do extra work of converting both the table and model
                            Xmat = table2array(thisX(:,mdl.PredictorNames));
                            thisX = Xmat; % for faster prediction
                            if istableq
                                qmat = table2array(q(:,mdl.PredictorNames));
                                q = qmat; % for faster prediction
                            end
                            tableinput = false;
                        else
                            if ~istableq % means it is an all-numeric table with some categorical predictors
                                thisX = table2array(thisX(:,mdl.PredictorNames));
                                if doConditional % encode categories if computing distances
                                    qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                                        mdl.DataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);
                                    Xmat = classreg.learning.internal.table2PredictMatrix(thisX,[],[],...
                                        mdl.DataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);
                                end
                                tableinput = false;
                            else % the following case is when the data is not all-numeric and has some categorical predictors
                                qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                                    mdl.DataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);
                                % for most tables, we should be able to convert both the table and the model itself
                                % since the model was trained on heterogeneous tables, the model needs to be modified to work with numeric matrices
                                % the following utility will help convert the model using toStruct/fromStruct
                                % this conversion is a MAJOR boost for performance for tabular data in some cases it is as high as 20X
                                [Xmat, mdl, status] = shapley.table2MatrixForShapley(thisX, mdl); % returns a compact model with a numeric variable range for categorical predictors
                                if status > 0 % model conversion was successful, use the converted matrices for everything
                                    f = @(x)predict(mdl,x); % update the predict call to use the modified model
                                    thisX = Xmat;
                                    q = qmat;
                                    tableinput = false;
                                else % for status == -1, the rare cases in which toStruct/fromStruct cannot help convert the model
                                    % heterogeneous table, shrink it to just the predictor names
                                    prednames = this.BlackboxModel.PredictorNames;
                                    % shrink the tables to just predictor names
                                    if istableq
                                        q = q(:,prednames);
                                        % if a numeric value is passed, it means data was an all-numeric table (since the model can predict on q)
                                    end
                                    thisX = thisX(:,prednames);
                                end
                            end
                        end
                    end
                end
            else % ============ MATRIX X ===============
                if istableq % if X was not a table, and model can predict on q that means, q is an all numeric table with {'x1','x2', 'x3' .....}
                    if ~isFunctionHandle
                        qmat = table2array(q(:,mdl.PredictorNames));
                        q = qmat;
                    else
                        qmat = table2array(q); % when q is a table, we will need to create a copy into a vector qmat anyways
                        q = qmat;
                    end
                end
                if doConditional
                    % qmat is a vector which is used in distance
                    % computation
                    % Xmat is a matrix which is used in distance
                    % computation
                    % Ensure that their categories are encoded correctly
                    % for distance computation
                    if ~isFunctionHandle
                        % for classreg models with numeric matrices, use
                        % table2PredictMatrix to encode categories as
                        % integers, needed by internal.stats.heteropdist2
                        prednames = mdl.PredictorNames;
                        vrange = mdl.DataSummary.VariableRange;
                        Xmat = classreg.learning.internal.table2PredictMatrix(thisX,[],[],...
                            vrange,categcols, prednames,true);
                        qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                            vrange,categcols, prednames,true);
                    else
                        % We need not support the workflow for passing
                        % numeric matrices with categorical inputs for
                        % function handles
                        % We can always have the user pass tables for such
                        % use cases.
                        % However, just to be consistent with classreg, in
                        % case someone tries to pass purely numeric
                        % matrices with some columns to be treated as
                        % "categorical", do the same thing as classreg and
                        % encode the categories before distance
                        % computation for the "conditional" method.
                        % Ofcourse, for such use cases, we are assuming
                        % that the function handle will be written in a
                        % way, that it can treat these columns as
                        % "categorical" in the function evaluation too i.e.
                        % the user is responsible for how the categories
                        % are handled in f, and we are responsible for how
                        % they are handled in the distance computation.
                        %
                        % To get the variable range, convert this matrix
                        % "thisX" to a table, and pass it to
                        % table2FitMatrix : this will populate the relevant
                        % arguments we can use immediately after to convert q
                        % Note that we are in the branch where thisX is a
                        % matrix, so we can call array2table on it.
                        [Xmat,~,vrange,~,args] = classreg.learning.internal.table2FitMatrix(array2table(thisX),[], 'CategoricalPredictors', categcols);
                        % For distance computation specifically we need
                        % to ensure that ordinals are not included
                        % (because no distance computation recipe
                        % exists), and throw an error for those
                        prednames = args{4};
                        qmat = classreg.learning.internal.table2PredictMatrix(q,[],[],...
                            vrange,categcols, prednames,true);
                    end
                end
            end

            returnNaNShapleyValues = false;
            % ===== score related NaN checks ====
            % for non-trees, remove rows with any NaNs in them
            % this is because those models do not know how to
            % predict with missing data and would produce NaN
            % values in the expected value computation
            % (remove NaN values for function handles too)
            if isFunctionHandle || (~isFunctionHandle && ~nm_shapley.isTreeEnsembleGAMOrECOC(mdl))
                if isFunctionHandle % for function handles, remove NaN rows ONLY if they produce NaN scores
                    scoresWithPossibleNaNs = f(thisX);
                    nanrows = isnan(scoresWithPossibleNaNs);
                    if isNonEmptyXmat % for function handles, there might still exist continuous predictors that are NaN and distance computation is needed (which should be later removed
                        Xmat(nanrows,:) = [];
                    end
                    thisX(nanrows,:) = [];
                    removedXNaNsAlready = false;
                else % for non-tree models in the toolbox e.g. SVM
                    if isNonEmptyXmat
                        nans = isnan(Xmat);
                    else
                        nans = isnan(thisX);
                    end
                    nanrows = sum(nans,2)~=0;
                    if isNonEmptyXmat
                        Xmat(nanrows,:) = [];
                    end
                    thisX(nanrows,:) = [];
                    removedXNaNsAlready = true;
                end
            end
            if isempty(thisX)
                returnNaNShapleyValues = true;% all rows have nans, return NaN shapley values
                return;
            end

            % ===== distance calculation related NaN checks ====
            %
            % Xmat and qmat are used in distance calculation for the
            % conditional approach,
            %
            % only internal.stats.heteropdist2 knows how to handle nan
            % categories for categorical predictors,
            %
            % for any continuous predictor, nan rows must be removed
            % because continuous predictor distance calculation functions
            % (pdist2 and heteropdist2, continuous part) do not know how to
            % handle NaNs.
            %
            if doConditional
                if isempty(qmat) % if a numeric vector was passed for q
                    qnan = isnan(q);
                else
                    qnan = isnan(qmat); % for function handles we do not know if a nan query point actually results in a nan score, so we cannot say that we already checked for it
                end
                M = numPredictors(this);
                contidx = setdiff(1:M,categcols);
                if ~isempty(contidx) % remove rows with NaN continuous predictors
                    if doConditional && any(qnan(contidx))
                        % in this case the score is non-NaN for a query point with NaN continuous predictors, for such query points we cannot do distance calculation
                        returnNaNShapleyValues = true;% all rows have nans, return NaN shapley values
                        return;
                    end
                    if ~removedXNaNsAlready % for tree based models, still remove continuous predictors that have NaNs
                        if isNonEmptyXmat
                            nans = isnan(Xmat);
                        else
                            nans = isnan(thisX); % X is a matrix
                        end
                        nans = nans(:,contidx);
                        nanrows = sum(nans,2)~=0;
                        if isNonEmptyXmat
                            Xmat(nanrows,:) = [];
                        end
                        thisX(nanrows,:) = [];
                        if isempty(thisX)
                            returnNaNShapleyValues = true; % all rows have nans, return NaN shapley values
                            return;
                        end
                    end
                end
                % for all continuous data, standardize the data
                % for distance computation: (standardized euclidean distance)
                if all(~categcols)
                    M = numPredictors(this);
                    isCategorical = false(1,M);
                    if isNonEmptyXmat
                        [Xmat,mu,sigma] = semisupervised.Model.standardizeData(Xmat,isCategorical); % if the original data is a table
                    else
                        [Xmat,mu,sigma] = semisupervised.Model.standardizeData(thisX,isCategorical); % if the original data is a matrix
                    end
                    if ~isempty(qmat)
                        qmat = semisupervised.Model.standardizePredictData(qmat,mu,sigma);
                    else
                        qmat = semisupervised.Model.standardizePredictData(q,mu,sigma);
                    end
                end
            end
        end

        function [method,numsubsets,useparallel,M] = parseAndValidateFitArgs(this, varargin)
            % ========== parse all the fit args ==========
            thisFileName = mfilename;
            fitparser = inputParser;
            % validate types
            validateStringScalar= @(x) validateattributes(x,{'string', 'char'}, ...
                {'scalartext','nonempty'});
            % OPTIMIZE WITH EDGE CASES FOR M (single feature, two features,
            % non-varying feature)
            fitparser.addParameter('Method', this.Method ,validateStringScalar);
            fitparser.addParameter('MaxNumSubsets', this.NumSubsets, @(x)validateattributes(x,{'numeric'},...
                {'scalar','>',1,'finite', 'integer'}));
            fitparser.addParameter('UseParallel', false, @(x)validateattributes(x,{'logical','double','string','char'},{'vector'}));
            
%             %the following three arguments are only necessary if
%             %this.isModelObject is false
%             %not anymore, since the arguments have been removed from
%             %varargin in fit()
%             fitparser.addParameter('Y',[], ...
%                 @(arg)validateattributes(arg,{'double','single'}, {'2d','nonempty'}));
%             fitparser.addParameter('Type',[],...
%                 @(arg)validateattributes(arg,{'char','string'}, {'2d','nonempty'}));
%             fitparser.addParameter('Algorithm',[],...
%                 @(arg)validateattributes(arg,{'char','string'}, {'2d','nonempty'}));

            M = numPredictors(this);
            % ========== parse all the fit args ==========
            fitparser.parse(varargin{:});
            parsedResults = fitparser.Results;
            method = parsedResults.Method;
            numsubsets = min(parsedResults.MaxNumSubsets,2^M);
            useparallel = parsedResults.UseParallel;
            % ======validate some of these inputs ========
            % 1.method
            validMethods = ["interventional-kernel", "conditional-kernel"];
            method = validatestring(method,validMethods, thisFileName);

            % 2. allow 0 and 1 as UseParallel
            useparallel = internal.stats.parseOnOff(useparallel,'UseParallel');
        end

        function M = numPredictors(this)
            if ~this.IsFunctionHandle && this.isModelObject
                M = numel(this.BlackboxModel.PredictorNames); % M is the number of features, N is the number of observations     
            else
                M = size(this.X,2);
            end
        end

        function this = makeNaNShapley(this)
            M = numPredictors(this);
            if this.Type == "classification"
                phi = nan(M,this.NumClasses);
                this = makeShapleyValuesTable(this,phi);
            else
                phi = nan(M,1);
                this = makeShapleyValuesTable(this,phi);
            end
        end

    end

    % helper methods: use static, hidden methods to keep these utilities
    % contained in this file (easy to maintain) and be tested independently
    methods (Static, Hidden)
        function ev = expectedValues(f, Z, type, K, thisX, q, Xmat, qmat, tableinput,categcols, useParallel, doConditional, isValidModel)
            % EXPECTEDVALUES returns the expected value of the scores for
            % all subsets The MOST EXPENSIVE STEP BY FAR in computing
            % Shapley Values (99% of the time is spent here for most
            % problems).
            %
            % ev is the expected value of the prediction of artificial
            % samples created for the query point. These artificial samples
            % are created in such a way that if a feature is included in a
            % subset => it is taken from the query point if a feature is
            % not included in a subset, it is taken from the training set
            %
            % f is the scoring/response function
            % Z is the coalition matrix
            % type is either 'classification' or 'regression'
            % K is the number of classes/columns in ShapleyValues
            % thisX is the value of X stored on the object
            % q is the query point
            % Xmat is the output matrix from table conversion of X
            % qmat is the output vector from table conversion of q
            % tableinput is true if the user originally passed X as a table
            % categcols is a vector of indices of categorical predictors
            % useParallel is a logical scalar that determines if parfor be used over for
            % doConditional is a logical scalar that determines if the conditional expected values are computed
            if isempty(Xmat)
                isNonEmptyXmat = false;
            else
                isNonEmptyXmat = true;
            end
            numsubsets = size(Z,1);
            N = size(thisX,1);

            % parfor needs the following variable to be declared, even for the non-conditional
            % approach
            numNeighbors = ceil(0.1*N);  % consider 10% of the neighbors for the conditional approach
            allContinuous  = all(~categcols);

            % ==== A NOTE on the Parallelization Scheme ====
            %
            % Though the total number of atomic operations involved are the
            % same, i.e we need to predict on numsubsets*numobservations
            % samples, it is still known that predict for classreg
            % functions can predict on multiple samples at once, we must
            % try to minimize the number of predict() calls made in our
            % loops.
            %
            % Profiling reveals that predict calls in the for loop are the
            % most expensive operation, and reducing the number of these
            % predict calls shows better performance. For example, a
            % problem with 4 features will have a coalition matrix of size
            % (2^4) i.e. numsubsets would be 16, and yet it can have any
            % number of observations, likely to be much higher than 16, say
            % 2000, for such cases it makes sense to predict on a matrix of
            % size 2000-by-4 inside the loop.
            %
            % On the other hand, we had 50 features, the exact problem of
            % size 2^50 is not feasible to solve, but the numsubsets
            % allocated should still be high to get good accuracy on
            % shapley values and let's say the numsubsets is about 10,000,
            % and the number of observations is much fewer say 2000. For
            % this case, we should predict on a matrix of size 10000-by-50.
            %
            % Note that this strategy benefits both serial and parallel
            % versions: doing more work for each iteration makes each
            % worker do more work in parallel, and for serial, it reduces
            % the calling overhead due to multiple predict() calls.

            loopOverSubsets = tableinput || (numsubsets < N) || doConditional ; % a boolean that is set to true when the strategy of looping over subsets is used
            % it is false when looping over observations, only used for vanilla kernel shap using small matrices of observations with many subsets
            if ~useParallel % ======== SERIAL IMPLEMENTATION ========
                if loopOverSubsets %  ========== table input, small budget many observations ============
                    meanScore = zeros(numsubsets,K);
                    for coalition = 1:numsubsets
                        meanScore(coalition,:) = shapley.meanScoreForLoopOverSubsets(f,coalition,N, type,Z,thisX,q,isNonEmptyXmat, Xmat,qmat,categcols,doConditional, numNeighbors, allContinuous, isValidModel);
                    end
                    ev = meanScore;
                else  % ========== matrix input, big budget small number of observations ============
                    Q = repmat(q,numsubsets,1);
                    QZ = Q(Z);
                    sumScoresForAllCombinations = zeros(numsubsets,K);
                    for obsidx = 1:N
                        sumScoresForAllCombinations = sumScoresForAllCombinations + nm_shapley.scoresForLoopOverObservations(f,obsidx,numsubsets,type, thisX, QZ,Z, isValidModel);
                    end
                    ev = sumScoresForAllCombinations/N; % take the average
                end

            else % ======== PARALLEL IMPLEMENTATION ==========
                if loopOverSubsets %  ========== table input, small budget many observations ============
                    meanScore = zeros(numsubsets,K);
                    parfor coalition = 1:numsubsets
                        meanScore(coalition,:) = shapley.meanScoreForLoopOverSubsets(f,coalition,N, type,Z,thisX,q,isNonEmptyXmat, Xmat,qmat,categcols,doConditional, numNeighbors, allContinuous, isValidModel);
                    end
                    ev = meanScore;
                else  % ========== matrix input, big budget small number of observations ============
                    Q = repmat(q,numsubsets,1);
                    QZ = Q(Z);
                    sumScoresForAllCombinations = zeros(numsubsets,K);
                    parfor obsidx = 1:N
                        sumScoresForAllCombinations = sumScoresForAllCombinations + nm_shapley.scoresForLoopOverObservations(f,obsidx,numsubsets,type, thisX, QZ,Z, isValidModel);
                    end
                    ev = sumScoresForAllCombinations/N; % take the average
                    %AW: The ev is calculated from modified data. However,
                    %for each subset/coalition the data are modified
                    %multiple times, i.e. for each modification using the
                    %data of one of the training samples if they are not
                    %part of the coalition. Then the mean over all the
                    %scores is taken as ev.
                end
            end
        end

        function meanScore = meanScoreForLoopOverSubsets(f,coalition,N, type,Z,thisX,q,isNonEmptyXmat, Xmat,qmat,categcols,doConditional,numNeighbors, allContinuous, isValidModel)
            % LOOP BODY FOR LOOPING OVER SUBSETS
            % Useful for the following cases:
            % 1. matrix with large number of observations and small number
            %    of subsets
            % 2. the conditional approach
            % 3. table inputs
            z = Z(coalition,:);
            % where a predictor is chosen, take its value from Q => Q(z) must survive
            % where it is not chosen, take its value from X => X(~z) must survive
            Xprime = thisX;
            Xprime(:,z) = repmat(q(:,z), N, 1);
            if doConditional
                if allContinuous % purely continuous data, already standardized, in prepareData, Xmat will always exist for all continuous predictors because it will be the standardized values in X
                    distances = pdist2(Xmat(:,z),qmat(z));
                else % heterogeneous data
                    % scan the subspace to see if there are any
                    % categorical columns in the subspace, and
                    % pass those indices to heterpdist2
                    subspaceidx = find(z);
                    [~,categoricalsForSubspace] = ismember(categcols,subspaceidx);
                    categoricalsForSubspace = categoricalsForSubspace(categoricalsForSubspace~=0);
                    if isNonEmptyXmat
                        distances = internal.stats.heteropdist2(Xmat(:,z),qmat(z), 'goodall3',categoricalsForSubspace); % use goodall for speed
                    else % will be used for matrices with numeric categorical predictors
                        distances = internal.stats.heteropdist2(thisX(:,z),q(z), 'goodall3',categoricalsForSubspace); % use goodall for speed
                    end
                end
                [~, neighboridx] = mink(distances, numNeighbors);
                Xprime = Xprime(neighboridx,:); % include only neighbors for scoring for the conditional approach
            end
            % not conditional, vanilla kernel shap
            if type=="classification" %  ========== CLASSIFICATION ==========
                if isValidModel
                    [~, scores] = f(Xprime);
                else
%ToDo: check whether this is correct, compare lines 326-330
                    [~, ~, scores] = f(Xprime);
                    scores = [-scores, scores];
                end
            else % ========== REGRESSION ============
                scores = f(Xprime);
            end
            meanScore = mean(scores,1); % add this one for the edge case of X being of size 1 (mean will shrink it to a scalar)
        end

        function scores = scoresForLoopOverObservations(f,obsidx,numsubsets,type, thisX, QZ,Z, isValidModel)
            % LOOP BODY FOR LOOPING OVER OBSERVATIONS
            % Useful only for the following case:
            % matrix input with small number of observations and a large
            % number of numsubsets (wide data)
            Xprime = repmat(thisX(obsidx,:),numsubsets,1);
            % where a predictor is chosen, take its value from Q => Q(Z) must survive
            % where it is not chosen, take its value from X => X(~Z) must survive
            Xprime(Z) = QZ;
            if type=="classification" %  ========== CLASSIFICATION ==========
                if isValidModel
                    [~, scores] = f(Xprime);
                else
%ToDo: check whether this is correct, compare lines 326-330
                    [~, ~, scores] = f(Xprime);
                    scores = [-scores, scores];
                end
            else % ========== REGRESSION ============
                scores = f(Xprime);
            end
        end


        function [Z, subsetWeights] = coalitionMatrix(M, numsubsets)
            % The purpose of this function is to return an appropriately sized
            % coalition matrix of trues and falses (0s and 1s).
            %
            % The performance of this function is NOT CRITICAL at all (99% of
            % the time is spent in the expected value computation). Hence, the
            % UseParallel flag has no implications for this helper.
            %
            % Z is a NumSubsets-by-M coalition matrix, where M is the
            % actual number of DIMENSIONS in the problem numsubsets is the number of
            % subsets to consider for this problem.
            %
            % The NumSubsets property can also be interpreted as the level of
            % approximation. The solution for an exact Shapley value
            % computation will require Z to be of size 2^M-by-M.

            if numsubsets ==2  % numsubsets is always greater than 1 (already validated in fit())
                % there are two subsets with infinite weights, they will be added to Z before solving the least squares
                % return early for this case of a budget of only two coalitions
                Z = [];
                subsetWeights = [];
                warning(message('stats:shapley:MaxNumSubsetsTooSmall'));
                return;
            end

            if M==2 % only two features, spell out Z
                switch numsubsets
                    case 3
                        Z = [true false];
                        subsetWeights = 1/2;
                    case 4
                        Z = [true false
                            false true];
                        subsetWeights = [1/2; 1/2];
                end
            else
                numsubsetsLargeEnough = false; % numsubsets is large enough to enumerate all subsets (2^M - 2 subsets)
                hasOddNumDimensions = mod(M,2)==1; % for odd number of features every single coalition has a complement e.g. (3choose0) + (3choose1) | (3choose2) + (3chose3)
                halfNumDimensions = floor(M/2); % symmetric problem
                featureSubsetSizes = uint64(1:halfNumDimensions)'; % a column of size halfNumDimensions
                binomialCoefficientsHalf= arrayfun(@(k)nchoosek(M,k), featureSubsetSizes); % a column of size halfNumDimensions
                INFINITY = intmax("uint64");
                cumulativeEnumerationsHalf = cumsum(binomialCoefficientsHalf); % same size as halfNumDimensions,
                % can contain overflown integers but that is ok, as long as the budget is reasonable, but if the specified budget also exceeds intmax, throw an error
% COMMENT AW: budget not known! First expression evaluates false although,
% f.e., cumulativeEnumerationsHalf(15) == INFINITY is true
                if any(cumulativeEnumerationsHalf) == INFINITY && budget > INFINITY
                    error(message('stats:shapley:InfiniteNumSubsets'));
                end
                % ideally we want to enumerate all the subsets,
                totalSubsetsWhole = 2^M; % this is the total number of subsets
                if numsubsets >= totalSubsetsWhole  % if the numsubsets exceeds the total number of enumerations to solve this problem, we can obtain an exact solution
                    numsubsetsLargeEnough = true;
                else % numsubsets is less than required for enumeration of all possible subsets
                    if numsubsets == 2*M + 2 % the case when subsets of size 1 can be enumerated
                        featureSubsetSizeExact = 1;
                    elseif numsubsets > 2*M + 2 % the case when more subsets than just size 1 can be enumerated
                        for ind = 1:halfNumDimensions
                            if numsubsets < 2*cumulativeEnumerationsHalf(ind) + 2
                                featureSubsetSizeExact = featureSubsetSizes(ind-1); % number of pairs of subsets we can fully enumerate within the numsubsets
                                break;
                            end
                        end
                    else % for numsubsets less than 2*M + 2, here not all subsets of size 1 can be enumerated
                        numSubsetsMinus2 = numsubsets-2;
                        Z = false(numSubsetsMinus2,M);
                        subsetWeights = zeros(numSubsetsMinus2,1);
                        if numSubsetsMinus2 <= M % numsubsets are in the range (2, M+2]
                            Z(1:numSubsetsMinus2+1:numSubsetsMinus2*numSubsetsMinus2) = true;
                            subsetWeights(1:numSubsetsMinus2) = 1/M;
                        else % numsubsets in the range (M+2, 2M+2)
                            Z(1:numSubsetsMinus2+1:end) = true;
                            remainingSubsets = numSubsetsMinus2 - M;
                            Z(M+1:M+remainingSubsets,:) = ~Z(1:remainingSubsets,:); % fill the remaining with as many complements as you can
                            subsetWeights = (1/M)*(ones(numSubsetsMinus2,1));
                        end
                        warning(message('stats:shapley:MaxNumSubsetsTooSmall'));
                        return;
                    end
                end

                kernelWeightsHalf = zeros(halfNumDimensions,1);
                binomialCoefficientsHalf = double(binomialCoefficientsHalf); % cast to double for weight calculation
                for ind = 1:halfNumDimensions % here ind is |z| and allPossibleSubsetSizesHalf is values of (M choose |z|) computed apriori, essentially make a hashtable of kernel weights
                    kernelWeightsHalf(ind)= (M-1)/(binomialCoefficientsHalf(ind)*ind*(M-ind)); % (M-1)/((M choose |z|)*(|z|)*(M-|z|), where is z is the subset, and |z| is the subset size
                end

                if numsubsetsLargeEnough % we can fully enumerate all the subsets if the numsubsets is large enough to accomodate the size
                    exactSize = 2^M-2; % there two subsets which have all features included and none of the features included, handle them separately
                    % coalition matrix, Z (exactSize-by-M)
                    %
                    % +----------------------------------------+
                    % |        subsets of size 1               |
                    % |                                        |
                    % +----------------------------------------+
                    % |        subsets of size 2               |
                    % |                                        |
                    % +----------------------------------------+
                    % |                 .                      |
                    % |                 .                      |
                    % |       goes on exactSize/2 times        |
                    % |                 .                      |
                    % |                 .                      |
                    % +----------------------------------------+
                    % |        subsets of size M-1             |
                    % |       (complements of above)           |
                    % +----------------------------------------+
                    % |         subsets of size M-2            |
                    % |         (complements of above)         |
                    % +----------------------------------------+
                    % |                 .                      |
                    % |                 .                      |
                    % |       goes on exactSize/2 times        |
                    % |                 .                      |
                    % |                 .                      |
                    % +----------------------------------------+
                    Z = false(exactSize, M);
                    subsetWeights = zeros(exactSize,1);
                    % work on subsets of size 1 through ceil(M/2) (illustrated in the top half of the picture above)
                    % the rest will be complements of what you populate

                    % as written, every iteration of the following for-loop is independent i.e. we can obtain these enumerations for a given subset size independently
                    % however, parfor has very restrictive indexing, so the following for-loop cannot be changed to "parfor" right away
                    % a parallel approach to this problem needs to be thought out

                    for featureSubsetSize = 1:halfNumDimensions
                        hotIndices = nchoosek(1:M, featureSubsetSize); % hot indices are of size n-by-M where n = M-choose-featureSubsetSize
                        rowSize = binomialCoefficientsHalf(featureSubsetSize);
                        if featureSubsetSize ==1
                            rowOffset = 0; % avoid zero indexing into cumulativeEnumerations
                        else
                            rowOffset = cumulativeEnumerationsHalf(featureSubsetSize-1); % totalPossibleEnumerations are the cumulative sum so far
                        end

                        kw = kernelWeightsHalf(featureSubsetSize);
                        for row = 1:rowSize
                            Z(row+rowOffset, hotIndices(row,:)) = true; % flip the false bits in this subset
                            subsetWeights(row+rowOffset) = kw; % kernel weights are symmetric so fill all of them out
                        end
                    end
                    % for the subsets of size M-1 through M-ceil(M/2), do not do any work except taking the complement (bottom half of the above picture)
                    if hasOddNumDimensions % for odd number of dimensions every subset has its complement
                        Z(exactSize/2+1:end,:) = ~Z(1:exactSize/2,:); % add the complements to Z
                        subsetWeights(exactSize/2+1:end) = subsetWeights(1:exactSize/2); % the weights are the same
                    else
                        % for even number of dimensions, subsets of size ceil(M/2) do not have a complement
                        % the interval of these asymmetric indices is as follows:
                        rowEndSymmetryIdx = cumulativeEnumerationsHalf(end-1);
                        rowBeginSymmetryAgainIdx = cumulativeEnumerationsHalf(end)+1;
                        Z(rowBeginSymmetryAgainIdx:end,:) = ~Z(1:rowEndSymmetryIdx,:); % add the complements to Z
                        subsetWeights(rowBeginSymmetryAgainIdx:end) = subsetWeights(1:rowEndSymmetryIdx); % add the complements to Z
                    end

                else % do budgeted shap, remember that we can enumerate featureSubsetSizeExact fully but the rest can only be partially enumerated

                    % Use a deterministic approach to make the coalition matrix, we know
                    % that the highest weighted subsets are the most important, so try to
                    % put as many highest weighted subsets in the coalition matrix as we
                    % can. There is no random sampling going on here for this reason. The
                    % highest weighted subsets contribute most to the shapley sum. The SHAP
                    % package uses a combination of this deterministic approach and random
                    % sampling for the last remaining subsets. It is just faster to not
                    % randomly sample even for the last few remaining subsets.

                    % coalition matrix, Z (numsubsets-by-M),
                    %
                    % +----------------------------------------+
                    % |        subsets of size 1               |
                    % |                                        |
                    % +----------------------------------------+
                    % |        subsets of size 2               |
                    % |                                        |
                    % +----------------------------------------+
                    % |                 .                      |
                    % |                 .                      |
                    % | goes on featureSubsetSizeExact/2 times |
                    % |                 .                      |
                    % |                 .                      |
                    % +----------------------------------------+
                    % |--   full subset enumerations above   --|
                    % +----------------------------------------+
                    % |                                        |
                    % |leftover numsubsets: partial enumeration|
                    % |                                        |
                    % |                                        |
                    % +----------------------------------------+
                    % |--       complements below            --|
                    % +----------------------------------------+
                    % |        subsets of size M-1             |
                    % |       (complements of above)           |
                    % +----------------------------------------+
                    % |         subsets of size M-2            |
                    % |         (complements of above)         |
                    % +----------------------------------------+
                    % |                 .                      |
                    % |                 .                      |
                    % | goes on featureSubsetSizeExact/2 times |
                    % |                 .                      |
                    % |                 .                      |
                    % +----------------------------------------+
                    numSubsetsMinus2 = numsubsets-2; % exclude the two trivial subsets (taking all features or taking none), will be added later by fitKernelSHAP
                    Z = false(numSubsetsMinus2, M);
                    subsetWeights = zeros(numSubsetsMinus2,1);

                    for featureSubsetSize = 1:featureSubsetSizeExact
                        hotIndices = nchoosek(1:M, featureSubsetSize); % hot indices are of size n-by-M where n = M-choose-featureSubsetSize
                        rowSize = binomialCoefficientsHalf(featureSubsetSize);
                        if featureSubsetSize ==1
                            rowOffset = 0; % avoid zero indexing into cumulativeEnu
                        else
                            rowOffset = cumulativeEnumerationsHalf(featureSubsetSize-1); % totalPossibleEnumerations are the cumulative sum so far
                        end
                        kw = kernelWeightsHalf(featureSubsetSize);
                        for row = 1:rowSize
                            Z(row+rowOffset, hotIndices(row,:)) = true; % flip the false bits in this subset
                            subsetWeights(row+rowOffset) = kw; % kernel weights are symmetric so fill all of them out
                        end
                    end

                    % now do partial enumeration for the next subset in line that would have been fully enumerated if we had more numsubsets
                    halfBudget = ceil(numSubsetsMinus2/2);
                    rowEndSymmetryIdx = floor(numSubsetsMinus2/2); % take complements of subsets upto here
                    rowBeginSymmetryAgainIdx = halfBudget+1; % populate complements starting at this index
                    partialEnumerationBlock = row+rowOffset+1:halfBudget;
                    hotIndices = shapley.partiallyEnumeratedSubsets(1:M,featureSubsetSizeExact+1,numel(partialEnumerationBlock)); % this is the subset next in line to enumerate

                    for row = 1:numel(partialEnumerationBlock)
                        Z(partialEnumerationBlock(row), hotIndices(row,:)) = true;
                        subsetWeights(partialEnumerationBlock(row)) = kernelWeightsHalf(featureSubsetSizeExact+1);
                    end

                    Z(rowBeginSymmetryAgainIdx:end,:) = ~Z(1:rowEndSymmetryIdx,:); % add the complements to Z
                    subsetWeights(rowBeginSymmetryAgainIdx:end) = subsetWeights(1:rowEndSymmetryIdx); % add the complements to Z
                end
            end
        end

        function P = partiallyEnumeratedSubsets(predictoridx,subsetSize, numCombinations)
            %   partiallyEnumeratedSubset returns only upto numCombinations combinations instead of all combinations
            % This helper is used only to fill out the partialEnumerationBlock in the coalition matrix
            % For example, let's say we have 10 features and MaxNumSubsets is chosen to be 25
            % We know that with that budget, we can fully enumerate 22 subsets
            % i.e. the highest weighted subsets (of size zero, and complements, of size 1 and complements):
            % include all predictors, exclude all predictors, include only one predictor, exclude only one predictor
            % For the remaining 3 subsets, we will enumerate the NEXT subset size (subsets of size 2 and complements)
            % For this example the NEXT subset size, (featureSubsetSizeExact+1), is 2.
            % Since the partially enumerated size will be a subset of this known size, kernelWeightsHalf(featureSubsetSizeExact+1)

            predictoridx = predictoridx(:).'; % Make sure it is a row vector
            n = length(predictoridx);

            P = zeros(numCombinations, subsetSize, 'like', predictoridx);

            % Compute P one row at a time:
            ind = 1:subsetSize;
            P(1, :) = predictoridx(1:subsetSize);
            for i=2:numCombinations
                % Find right-most index to increase
                % j = find(ind < n-k+1:n, 1, 'last');
                for j = subsetSize:-1:1
                    if ind(j)<n-subsetSize+j
                        break;
                    end
                end

                % Increase index j, initialize all indices to j's right.
                % ind(j:k) = (ind(j) + 1) : (ind(j) + 1 + k - j);
                % P(i, :) = v(ind);
                for t=1:j-1
                    P(i, t) = predictoridx(ind(t));
                end
                indj = ind(j) - j + 1;
                for t = j:subsetSize
                    ind(t) = indj + t;
                    P(i, t) = predictoridx(indj + t);
                end
            end
        end

        function [Xmat,modifiedModel,status] = table2MatrixForShapley(X,mdl)
            % table2MatrixForShapley converts a heterogeneous (containing multiple datatypes) table to a numeric matrix
            % For classreg models, making this change can result in a HUGE performance improvement
            % For example, for a classification tree trained on the adult dataset with 100 samples, and 14 predictors, a 20X speed improvement was observed
            % For ensembles this improvement was close to 10X.
            % This is probably because indexing operations are much faster for matrices
            % Further, the type inference need not be done for matrices
            % However, since the models were trained on heterogeneous tables, these models cannot directly predict on numeric matrices
            % To enable prediction on numeric matrices, these models must be reconstructed with the VariableRange in their DataSummary modified
            % Calling constructors is cumbersome because (1) classreg models do not have the same signature for constructors, and
            % (2) some of the inputs passed to these constructors are not already available in the trained model that needs to be reconstructed
            % The best solution is to use the codegen utilities toStruct and fromStruct (which run in MATLAB), with categorical data as well as 'categorical' type labels supported for codegen in 21a
            dataSummary = mdl.DataSummary;
            Xmat = classreg.learning.internal.table2PredictMatrix(X,[],[],...
                dataSummary.VariableRange,mdl.CategoricalPredictors, mdl.PredictorNames,true);

            if nargout>1
                try
                    % an earlier version of this software used
                    % table2FitMatrix, however it is recommended to use the
                    % information already in the model instead, to account
                    % for the edge case that the model has seen more
                    % categories in training than the X that is passed by
                    % the user, this is useful for models that dummify
                    % based on the total number of categories present in
                    % the dataSummary e.g. svm
                    variableRangeCategorical = dataSummary.VariableRange;
                    numpreds = numel(variableRangeCategorical);
                    variableRangeNumeric = cell(size(variableRangeCategorical)); % though the orientation row or column should not matter, make sure it is stored as a row just like it is in classreg models
                    for idx = 1:numpreds
                        vrangepred = variableRangeCategorical{idx};
                        numCategories = numel(vrangepred);
                        if numCategories == 0
                            variableRangeNumeric{idx} = vrangepred; % empty
                        else
                            variableRangeNumeric{idx} = (1:numCategories)'; % encode as the model would have
                        end
                    end
                    % for gam, use its constructor, for all other models, call to/fromStruct methods
                    if isa(mdl, 'ClassificationGAM')
                        % ClassificationGAM for example does not have a
                        % toStruct/fromStruct, but it does allow post-fit
                        % parameters to be passed to reconstruct the
                        % object.
                        % Use this modified/retrained object that
                        % knows how to predict on numeric matrices for
                        % speed on table inputs classification kernel does
                        % not allow that, so shapley uses tables for
                        % prediction using kernel classifier/regressor.
                        %
                        % Note that it is still faster to do this operation
                        % instead of using predict on a table in a loop.
                        % For 100 samples from the census1994 dataset for
                        % example, doing this operation is 25X faster than
                        % using a table inside.
                        %
                        % The constructor for the compact classes is
                        % protected, otherwise, using the compact
                        % constructor would make more sense
                        dataSummary.VariableRange = variableRangeNumeric;
                        modifiedModel = ClassificationGAM(mdl.PrivX, mdl.PrivY,mdl.W, mdl.ModelParams,...
                            dataSummary,mdl.ClassSummary,...
                            mdl.PrivScoreTransform);
                        modifiedModel = compact(modifiedModel);
                    elseif isa(mdl, 'RegressionGAM')
                        dataSummary.VariableRange = variableRangeNumeric;
                        modifiedModel = RegressionGAM(mdl.PrivX, mdl.PrivY,mdl.W, mdl.ModelParams,...
                            dataSummary,mdl.PrivResponseTransform);
                        modifiedModel = compact(modifiedModel);
                    elseif isa(mdl, 'ClassificationECOC')
                        dataSummary.VariableRange = variableRangeNumeric;
                        modifiedModel = ClassificationECOC(mdl.PrivX, mdl.PrivY,mdl.W, mdl.ModelParams,...
                            dataSummary,mdl.ClassSummary, mdl.PrivResponseTransform);
                        modifiedModel = compact(modifiedModel);
                    else
                        % call toStruct to convert it to a struct
                        mdlst = mdl.toStruct;
                        % modify the dataSummary VariableRange
                        dataSummary = mdlst.DataSummary;
                        % do the same operations as classifToStruct to use a struct for
                        % Variable range because fromStruct expects a struct variable range
                        cellVariableRange = variableRangeNumeric;
                        for ii = 1:numel(cellVariableRange)
                            fn = strcat('X',num2str(ii));
                            dataSummary.VariableRange.(fn) = cellVariableRange{ii};
                        end
                        dataSummary.TableInput = false; % this model now predicts on numeric matrices
                        mdlst.DataSummary = dataSummary;
                        struct2object = str2func(mdlst.FromStructFcn);
                        modifiedModel = struct2object(mdlst); % convert it back to a classreg object
                    end
                    status = 1;
                catch % classification kernel does not support to/fromStruct, nor does it support the constructor call for a fitted object like say ClassificationSVM, ClassificationGAM
                    status = -1;
                    modifiedModel = mdl; % return the unmodified model
                end
            end
        end

        function tf = isTreeEnsembleGAMOrECOC(mdl)
            % status is zero, so just need to check for compact models
            isclassif = @(mdl) isa(mdl,'classreg.learning.classif.CompactClassificationTree') || isa(mdl,'ClassificationTree') ... % tree
                || isa(mdl, 'ClassificationECOC')|| isa(mdl, 'classreg.learning.classif.CompactClassificationECOC')... % ecoc
                || isa(mdl, 'ClassificationGAM') || isa(mdl,'classreg.learning.classif.CompactClassificationGAM')... % gam uses trees
                || ( isa(mdl,'classreg.learning.classif.CompactClassificationEnsemble') || isa(mdl,'classreg.learning.classif.ClassificationEnsemble') ... %
                && ~isempty(mdl.Trained) && ... % if non empty inspect the learners for trees
                isa(mdl.Trained{1}, 'classreg.learning.classif.CompactClassificationTree'));

            isregr = @(mdl) isa(mdl,'classreg.learning.regr.CompactRegressionTree') || isa(mdl,'RegressionTree')...
                || isa(mdl, 'classreg.learning.regr.CompactRegressionGAM') || isa(mdl, 'RegressionGAM')...
                || ( isa(mdl,'classreg.learning.regr.CompactRegressionEnsemble') || isa(mdl,'classreg.learning.regr.RegressionEnsemble')...
                && ~isempty(mdl.Trained) && ... % if non empty inspect the learners for trees
                isa(mdl.Trained{1}, 'classreg.learning.regr.CompactRegressionTree'));
            tf = isclassif(mdl) || isregr(mdl);
        end

        function checkForOrdinalsInData(thisX,isOrdinal)
            % this additional check is only performed for
            % conditional-kernel because distances cannot be computed for
            % such data
            % also note that models such as trees, gam do not identify
            % ordinal predictors in the data summary so the data needs to
            % be further probed for ordinals (the else branch)
            if isOrdinal
                error(message('stats:shapley:OrdinalsNotSupportedForConditional'));
            else % for models such as gam, trees OrdinalPredictors are not identified in DataSummary
                x = thisX(1,:); % thisX is non-empty for function handles, just take one row out for type inference
                if istable(x) % ordinals are only possible in tables, ensure non-empty args
                    [~,~,~,~,args] = classreg.learning.internal.table2FitMatrix(x,[]); % for a matrix, args is empty
                    if any(args{6}) % these are the ordinal predictor indices
                        error(message('stats:shapley:OrdinalsNotSupportedForConditional'));
                    end
                end
            end
        end
    end
end