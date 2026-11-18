function [Y_mapped, Y_mapped_ciu, Y_mapped_cil, Y_mapped_std] = nk_MapModelPredictions(n, O, R, I, MapIdx, Method, NormRange, ZnormData, progressFcn)
% nk_MapModelPredictions - Map perturbation prediction changes to features.
%
% Progress contract
%   progressFcn is optional and has signature progressFcn(stage, fraction).
%   The helper reports local mapping, feature summarization, and case-level
%   normalization/scaling progress. It has no NM2 UI/runtime dependency.
%
% Materialization/performance
%   Existing feature-scale materialization is unchanged. Progress reporting is
%   throttled to at most approximately 100 updates per major feature loop.
%
if ~exist('ZnormData','var') || isempty('ZnormData'), ZnormData = 1; end
if nargin < 9
    progressFcn = [];
elseif ~isempty(progressFcn) && ~isa(progressFcn,'function_handle')
    error('progressFcn must be empty or a function handle.')
end
localProgress(progressFcn, 'initializing', 0);

m = size(R,1);
tY_mapped       = zeros(m,n);
Y_mapped        = zeros(1,n);
Y_mapped_ciu    = zeros(1,n);
Y_mapped_cil    = zeros(1,n);
Y_mapped_std    = zeros(1,n);

switch Method
    case 'posneg'
        RangeD = (R(:,1) - R(:,2)) - O;
    case {'median','medianflip','medianmirror','random', 'shapley'}
        RangeD = R - O;
        if strcmp(Method,'shapley')
            %For shapley, I is a coalition matrix,i.e. "1" means a feature is
            %part of the coalition and "0" means it's not part of it and hence
            %will be replaced. For the other MLI methods it's the other way
            %round, therefore we invert the values of the binary matrix I here
            I = ~I;
        end
end

% Loop through perturbations and map normalized prediction changes.
localProgress(progressFcn, 'mapping_perturbation_effects', 0.02);
progressStep = max(1, ceil(max(m,1)/100));
for i=1:m
    tY_mapped(i,MapIdx(I(i,:))) = RangeD(i)*100/NormRange;
    if i == m || mod(i,progressStep) == 0
        localProgress(progressFcn, 'mapping_perturbation_effects', ...
            0.02 + 0.38*i/max(m,1));
    end
end

% Summarize feature-wise relevance distributions.
localProgress(progressFcn, 'summarizing_feature_relevance', 0.40);
featureStep = max(1, ceil(max(n,1)/100));
for i=1:n
    idx = tY_mapped(:,i)~=0 & isfinite(tY_mapped(:,i)) ;
    if isempty(idx), continue; end
    ci = nm_95confint(tY_mapped(idx,i));
    Y_mapped_cil(i) = ci(1,:);
    Y_mapped_ciu(i) = ci(2,:);
    Y_mapped_std(i) = std(tY_mapped(idx,i));
    Y_mapped(i) = median(tY_mapped(idx,i));
    if i == n || mod(i,featureStep) == 0
        localProgress(progressFcn, 'summarizing_feature_relevance', ...
            0.40 + 0.50*i/max(n,1));
    end
end

% Case-level centering/normalization/scaling operations
if ZnormData > 1, idx = isfinite(Y_mapped); end

switch ZnormData 
    case 2
        % mean centering 
        localProgress(progressFcn, 'median_centering', 0.92);
        fprintf(' ... median centering')
        mYmapped = median(Y_mapped(idx));
        Y_mapped(idx) = Y_mapped(idx) -  mYmapped ; 
        Y_mapped_cil(idx) =  Y_mapped_cil(idx) - mYmapped;
        Y_mapped_ciu(idx) =  Y_mapped_ciu(idx) - mYmapped;
        Y_mapped_std(idx) = Y_mapped_std(idx) - mYmapped; 
    case 3
        % z-normalisation
        localProgress(progressFcn, 'z_normalizing', 0.92);
        fprintf(' ... z-normalizing')
        mYmapped = median(Y_mapped(idx));
        sdYmapped = std(Y_mapped(idx));
        Y_mapped(idx) = ( Y_mapped(idx) -  mYmapped ) / sdYmapped;
        Y_mapped_cil(idx) = ( Y_mapped_cil(idx) -  mYmapped ) / sdYmapped;
        Y_mapped_ciu(idx) = ( Y_mapped_ciu(idx) -  mYmapped ) / sdYmapped;
        Y_mapped_std(idx) = ( Y_mapped_std(idx) -  mYmapped ) / sdYmapped;
	case 4
        % scaling to [-1, 1]
        localProgress(progressFcn, 'scaling_relevance', 0.92);
        fprintf(' ... scaling to [-1, 1]')
        IN = struct('AcMatFl', true, 'ZeroOne', 2);
        [Y_mapped(idx), IN] = nk_PerfScaleObj( Y_mapped(idx), IN );
        Y_mapped_cil(idx) = nk_PerfScaleObj( Y_mapped_cil(idx), IN );
        Y_mapped_ciu(idx) = nk_PerfScaleObj( Y_mapped_ciu(idx), IN );
        Y_mapped_std(idx) = nk_PerfScaleObj( Y_mapped_std(idx), IN );
end
localProgress(progressFcn, 'finalizing', 0.98);
Y_mapped(~isfinite(Y_mapped)) = 0;
Y_mapped_cil(~isfinite(Y_mapped)) = 0;
Y_mapped_ciu(~isfinite(Y_mapped)) = 0;
Y_mapped_std(~isfinite(Y_mapped)) = 0;
localProgress(progressFcn, 'complete', 1);

function localProgress(progressFcn, stage, fraction)
if isempty(progressFcn), return; end
progressFcn(stage, max(0,min(1,double(fraction))));
