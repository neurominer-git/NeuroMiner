% =========================================================================
% FORMAT: [sY, IN] = nk_PerfSkewCorrObj(Y, IN)
% =========================================================================
% Correct skewness in each feature of Y.
%
% USAGE:
%   [sY, IN] = nk_SkewCorrObj(Y, IN)
%
% DESCRIPTION:
%   This function identifies skewed features (columns) in the input data
%   matrix Y and applies one of the following transformations:
%     - 'log'         : Log transform (with offset if min(Y)<0)
%     - 'boxcox'      : Box-Cox transform (auto or manual lambda)
%     - 'yeojohnson'  : Yeo-Johnson transform (auto or manual lambda)
%
%   The choice of transformation and thresholding is controlled by fields
%   within the structure IN. If a transform is applied, offset and lambda
%   parameters are stored in IN for later use (e.g., reversion or applying
%   the same transform to test data).
%
%   If IN.revertflag is true, the function reverts any previously applied 
%   skew-correction transforms instead of applying new ones.
%
%   See also: nk_SkewCorr_config, nk_PerfScaleObj, nk_Preproc_config
%
% INPUT ARGUMENTS:
%   Y  : M x N matrix of data (M observations, N features).
%        - If some columns are heavily skewed, the function will identify
%          them according to a threshold (e.g., IN.SkewThr).
%        - If Y has non-finite values (NaN, Inf), you may want to handle 
%          them beforehand or ensure your code can handle them appropriately.
%
%   IN : struct controlling the skew-correction logic. The relevant fields are:
%
%        .revertflag        - (logical) If true, revert a previous transform.
%        .transformMethod   - (char) 'log' | 'boxcox' | 'yeojohnson' (default 'log')
%        .SkewThr           - (numeric) scalar or vector; threshold for 
%                             abs(skewness). Columns exceeding this are corrected.
%        .SkewApplied       - (logical array, size 1 x N) whether each feature
%                             has been transformed (used if reversion is needed).
%
%        % -- For Box–Cox
%        .BoxCoxLambdaType  - (char) 'auto' or 'manual'
%        .BoxCoxLambdaVal   - (numeric vector/scalar) either a single lambda 
%                             for all features or one lambda per feature (length N)
%        .BoxCoxLambda      - (numeric array, size 1 x N) used to store final 
%                             per-feature lambdas if discovered automatically 
%                             or applied manually.
%
%        % -- For Yeo–Johnson
%        .YJLambdaType      - (char) 'auto' or 'manual'
%        .YJLambdaVal       - (numeric vector/scalar), same logic as BoxCoxLambdaVal
%        .YJLambda          - (numeric array, size 1 x N) final per-feature lambdas.
%
%        .SkewOffset        - (numeric array, size 1 x N) storing offsets if data 
%                             needed shifting (e.g., for log or Box–Cox).
%
% OUTPUT ARGUMENTS:
%   sY : M x N matrix of data after skew correction (or reversion).
%        - If IN.revertflag == true, sY is the data reverted back 
%          to the original scale.
%        - Otherwise, sY is the transformed data.
%
%   IN : Updated struct with the final transform parameters (per-feature 
%        lambdas, offsets, etc.) for future reference.
%
% =========================================================================
% (c) Nikolaos Koutsouleris, 03/2025

function [sY, IN] = nk_PerfSkewCorrObj(Y, IN)

% ------------- Defaults / Setup ----------------------------------
if ~exist('IN','var'), IN = []; end
if iscell(Y) && exist('IN','var') && ~isempty(IN)
    sY = cell(1,numel(Y)); 
    for i=1:numel(Y)
        sY{i} = SkewCorrMain(Y{i}, IN);
    end
else
    [sY, IN] = SkewCorrMain(Y, IN);
end

end % nk_SkewCorrObj wrapper
% -------------------------------------------------------------------------

function [sY, IN] = SkewCorrMain(Y, IN)

% If no revertflag, assume forward transform
if ~isfield(IN,'revertflag'),      IN.revertflag = false; end
if ~isfield(IN,'transformMethod'), IN.transformMethod = 'log'; end
if ~isfield(IN,'SkewThr'),         IN.SkewThr = 2; end
if ~isfield(IN,'trained'),         IN.trained = false; end

% Box–Cox settings
if ~isfield(IN,'BoxCoxLambdaType'), IN.BoxCoxLambdaType = 'auto'; end
if ~isfield(IN,'BoxCoxLambdaVal'),  IN.BoxCoxLambdaVal  = 0; end

% Yeo–Johnson settings
if ~isfield(IN,'YJLambdaType'), IN.YJLambdaType = 'auto'; end
if ~isfield(IN,'YJLambdaVal'),  IN.YJLambdaVal  = 0; end

% If revertflag => revert transforms
if IN.revertflag
    sY = revertTransform(Y, IN);
    return;
end

n = size(Y,2);

if ~IN.trained

    % 1) Compute skewness, figure out which columns exceed threshold
    IN.skvals = featureSkewness(Y);
    
    % 2) Loop over columns that are "too skewed"
    IN.idxTooSkewed = abs(IN.skvals) > IN.SkewThr;
    
    % 3) Initialize parameter vectors
    switch lower(IN.transformMethod)
        case 'log'
            IN.SkewOffset = zeros(1,n);
        case 'boxcox'
            IN.SkewOffset = zeros(1,n);
            IN.BoxCoxLambda = zeros(1,n);
        case 'yeojohnson'
            IN.YJLambda = zeros(1,n);
    end
    
    % 4) Loop through skewed features and compute correction params
    for f = find(IN.idxTooSkewed)
    
        switch lower(IN.transformMethod)
        
            case 'log'
                IN.SkewOffset(f) = computeLogOffset(Y(:,f));

            case 'boxcox'
                IN.SkewOffset(f) = computeBoxCoxOffset(Y(:,f));
                IN.BoxCoxLambda(f) = pickBoxCoxLambda(IN, f, Y(:,f));

            case 'yeojohnson'
               IN.YJLambda(f) = pickYJLambda(IN, f, Y(:,f));
               
        end
    end
    IN.trained = true;
end

sY = Y;

for f = find(IN.idxTooSkewed)
    
    switch lower(IN.transformMethod)
    
        case 'log'

           sY(:,f) = logTransform(Y(:,f), IN.SkewOffset(f));

        case 'boxcox'

           sY(:,f) = forwardBoxCox(Y(:,f), IN.BoxCoxLambda(f), IN.SkewOffset(f));

        case 'yeojohnson'
            
            sY(:,f) = forwardYJ(Y(:,f), IN.YJLambda(f) );

        otherwise
            warning('Unknown transformMethod: %s. Skipping transform.', IN.transformMethod);
    end
end

end

%% ========================= HELPER: pickBoxCoxLambda =====================
function lamF = pickBoxCoxLambda(IN, f, x)
% If "auto", do MLE for col x. If "manual", read from .BoxCoxLambdaVal
if strcmpi(IN.BoxCoxLambdaType, 'auto')
    lamF = mleBoxCox(x);
else
    % 'manual'
    if isscalar(IN.BoxCoxLambdaVal)
        lamF = IN.BoxCoxLambdaVal;
    else
        lamF = IN.BoxCoxLambdaVal(f);
    end
end
end

%% ========================= HELPER: pickYJLambda =========================
function lamF = pickYJLambda(IN, f, x)
if strcmpi(IN.YJLambdaType, 'auto')
    lamF = mleYeoJohnson(x);
else
    % 'manual'
    if isscalar(IN.YJLambdaVal)
        lamF = IN.YJLambdaVal;
    else
        lamF = IN.YJLambdaVal(f);
    end
end
end

%% ========================= HELPER: computeLogOffset =====================
function offVal = computeLogOffset(x)
mn = min(x);
offVal = 0;
if mn <= 0
    offVal = abs(mn) + 1e-9;
end
end

%% ========================= HELPER: logTransform =========================
function y = logTransform(x, offset)
tx = x + offset;
% Safety belt if the test data contains negative
mn = min(tx);
if mn <=0    
    offVal = abs(mn) + 1e-9;
    tx = tx + offVal;
    warning(sprintf('\n[nk_PerfSkewnessCorr:logTransform] Offset added to the data to avoid complex numbers! Check your settings!'));
end
y = log(tx);
end

%% ========================= HELPER: computeBoxCoxOffset ==================
function offVal = computeBoxCoxOffset(x)
mn = min(x);
offVal = 0;
if mn <= 0
    offVal = abs(mn) + 1e-9;
end
end

%% ========================= HELPER: forwardBoxCox ========================
function y = forwardBoxCox(x, lambda, offset)
tx = x + offset; % ensure positivity (based on training data!)
% Safety belt if the test data contains negative
mn = min(tx);
if mn <=0    
    offVal = abs(mn) + 1e-9;
    tx = tx + offVal;
    warning(sprintf('\n[nk_PerfSkewnessCorr:forwardBoxCox] Offset added to the data to avoid complex numbers! Check your settings!'));
end
if abs(lambda) < 1e-8
    y = log(tx);
else
    y = (tx.^lambda - 1) ./ lambda;
end
end

%% ========================= HELPER: featureSkewness ======================
function skvals = featureSkewness(Y)
[~, n] = size(Y);
skvals = zeros(1, n);

for j = 1:n
    colData = Y(~isnan(Y(:,j)), j);
    if ~isempty(colData)
        mu  = mean(colData);
        sdv = std(colData);
        if sdv > 0
            m3 = mean((colData - mu).^3);
            skvals(j) = m3 / (sdv^3);
        else
            skvals(j) = 0;
        end
    end
end
end

%% ========================= HELPER: MLE for BoxCox/YJ ====================
function lambdaOpt = mleBoxCox(x)
% remove NaNs
x = x(~isnan(x));
if isempty(x) || numel(x) < 2
    lambdaOpt = 0;
    return;
end

% shift if min<=0
mn = min(x);
if mn<=0
    x = x + abs(mn) + 1e-9;
end
initGuess = 0;
lambdaOpt = fminsearch(@(L) boxcoxNLL(L, x), initGuess);
end
% -------------------------------------------------------------------------
function nll = boxcoxNLL(lambda, x)
n = numel(x);
y = bcTransform(x, lambda);
yVar = var(y,1);
nll = (n/2)*log(yVar) - (lambda-1)*sum(log(x));
end
% -------------------------------------------------------------------------
function y = bcTransform(x, lambda)
if abs(lambda)<1e-8
    y = log(x);
else
    y = (x.^lambda -1)./lambda;
end
end
% -------------------------------------------------------------------------
% Yeo–Johnson
function lambdaOpt = mleYeoJohnson(x)
x = x(~isnan(x));
if isempty(x) || numel(x)<2
    lambdaOpt = 0;
    return;
end
initGuess = 0;
lambdaOpt = fminsearch(@(L) yjNLL(L, x), initGuess);
end
% -------------------------------------------------------------------------
function nll = yjNLL(lambda, x)
n = numel(x);
y = forwardYJ(x, lambda);
yVar = var(y,1);
% log Abs Derivative
logDer = yjLogDeriv(lambda, x);
nll = (n/2)*log(yVar) - sum(logDer);
end
% -------------------------------------------------------------------------
function y = forwardYJ(x, lambda)
y = zeros(size(x));
for i=1:numel(x)
    if x(i)>=0
        if abs(lambda)<1e-8
            y(i) = log(x(i)+1);
        else
            y(i) = ((x(i)+1)^lambda -1)/lambda;
        end
    else
        if abs(lambda-2)<1e-8
            y(i) = -log(1-x(i));
        else
            y(i) = -(((1 - x(i))^(2-lambda)-1)/(2-lambda));
        end
    end
end
end
% -------------------------------------------------------------------------
function lDer = yjLogDeriv(lambda, x)
lDer=zeros(size(x));
for i=1:numel(x)
    xi = x(i);
    if xi>=0
        if abs(lambda)<1e-8
            lDer(i) = -log(xi+1);
        else
            lDer(i) = (lambda-1)*log(xi+1);
        end
    else
        if abs(lambda-2)<1e-8
            lDer(i) = -log(1-xi);
        else
            lDer(i) = (1-lambda)*log(1-xi);
        end
    end
end
end