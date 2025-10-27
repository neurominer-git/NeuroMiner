function [dims, PercMode, act] = nk_ExtDim_config(RedMode, PercMode, dims, defaultsfl, parentstr)
% ==========================================================================================
% [dims, PercMode, act] = nk_ExtDim_config(RedMode, PercMode, dims, defaultsfl, parentstr)
% ==========================================================================================
%  Configure extraction dimensionalities for dimensionality reduction.
%
%   [dims, PercMode, act] = nk_ExtDim_config(RedMode, PercMode, dims, defaultsfl, parentstr)
%
%   This function defines the dimensionality schedule for feature extraction
%   methods such as PCA, t-SNE, SparsePCA, ICA, etc. Users can specify
%   extraction either as:
%       (1) Absolute number of dimensions
%       (2) Percentage of maximum possible dimensionality
%       (3) Energy (explained variance) ratio
%
%   Extended functionality:
%       Supports automated stepping schedules:
%           • Linear stepping:     linspace(min, max, N)
%           • Geometric stepping:  logspace(log10(min), log10(max), N)   (requires min,max > 0)
%           • Power-law stepping:  min + (max-min) * t.^alpha, t=linspace(0,1,N)
%
%   INPUTS:
%       RedMode     - Reduction mode (e.g., 'PCA','t-SNE','SparsePCA','LDA','ICA')
%       PercMode    - Extraction mode:
%                       1 = Absolute range (number of eigenvariates/components)
%                       2 = Percentage of maximum dimensionality
%                       3 = Energy range (explained variance ratio)
%                     If empty, user will be prompted.
%       dims        - Vector specifying extraction dimensionalities (if provided).
%                     If empty, defaults or user input will be used.
%       defaultsfl  - Flag (boolean). If true, return default settings without user interaction.
%                     If false (default), user is prompted to configure extraction.
%       parentstr   - String with parent menu title (used for navigation display).
%
%   OUTPUTS:
%       dims        - Vector of extraction dimensionalities (absolute numbers or percentages/ratios).
%       PercMode    - Extraction mode used (1=Absolute, 2=Percentage, 3=Energy).
%       act         - Action flag: 
%                       0 = no further action needed
%                       1 = mode selection performed
%                       2 = extraction range defined
%
%   NOTES:
%       • In Absolute mode (PercMode=1), output is rounded to unique integers.
%       • In Geometric stepping, if min/max are not > 0, the function falls back to Linear stepping.
%       • In Power-law stepping, exponent alpha > 1 emphasizes larger dimensions.
%
%   EXAMPLES:
%       % Absolute mode, linear stepping from 1 to 100 with 20 steps:
%       [dims, pm, act] = nk_ExtDim_config('PCA',1,[],false,'Main');
%       % User input: choose "Linear", enter [1 100 20]
%
%       % Geometric stepping between 5 and 500 (log-spaced, 15 points):
%       [dims, pm, act] = nk_ExtDim_config('PCA',1,[],false,'Main');
%       % User input: choose "Geometric", enter [5 500 15]
%
%       % Power-law stepping with alpha=2, from 10 to 300, 12 steps:
%       [dims, pm, act] = nk_ExtDim_config('PCA',1,[],false,'Main');
%       % User input: choose "Power-law", enter [10 300 12], then alpha=2
%
%   See also: linspace, logspace
% =========================================================================
% (c) Nikolaos Koutsouleris, 09/2025

global NM
if ~exist('defaultsfl','var') || isempty(defaultsfl); defaultsfl = false; end

if ~defaultsfl
    
    if (~exist('dims','var') || isempty(dims)) || (~exist('PercMode','var') || isempty(PercMode))
         [PercMode, dims] = nk_ExtDim_config(RedMode, [], [], 1);
    end
    defdims = dims; if size(defdims,2)==1 && numel(defdims)>1, defdims=defdims'; end
    mn_str = []; PercModeStr = {'Absolute range','Percentage range','Energy range'}; mn_act=[];
    switch RedMode
        case {'PCA', 't-SNE', 'SparsePCA'}
            mn_str = [mn_str sprintf('Define extaction mode for %s [ %s ]|',RedMode, PercModeStr{PercMode})]; mn_act = 1;
        case {'LDA', 'GDA'}
            PercMode = 1; L = NM.label; L(isnan(L))=[]; dims = numel(unique(L)); act=0; return
        otherwise
            PercMode = 1;
    end
    
    mn_str = [mn_str sprintf('Define extraction range [ %s ]',nk_ConcatParamstr(dims))]; mn_act = [mn_act 2];
    if numel(mn_act)>1
        nk_PrintLogo
        mestr = 'Extraction of components from reduced data projections'; navistr = [parentstr ' >>> ' mestr]; fprintf('\nYou are here: %s >>> ',parentstr); 
        act = nk_input(mestr,0,'mq',mn_str,mn_act);
    else
        act = 2;
    end
    
    switch act
        case 1
            PercMode = nk_input(sprintf('Define %s decomposition',RedMode),0,'m', ...
                            ['Absolute number range [ 1 ... n ] of eigenvectors|' ...
                             'Percentage range [ 0 ... 1 ] of max dimensionality|' ...
                             'Energy range [ 0 ... 1 ]of maximum decomposition'],1:3, PercMode);   
            switch PercMode 
                case {2,3}
                    dims = 0.8;
                case 1
                    dims = floor(size(NM.Y{NM.TrainParam.FUSION.M(1)},2)*0.8);
            end
            
        case 2
            % ---- NEW: stepping modes with [min max N], defaults derived from 'dims' ----
            switch PercMode
                case 1
                    inpstr = 'Absolute: choose stepping (Linear/Geometric/Power-law)';
                case 2
                    inpstr = 'Percentage: choose stepping (Linear/Geometric/Power-law)';
                case 3
                    inpstr = 'Energy: choose stepping (Linear/Geometric/Power-law)';
            end
            
            StepMode = nk_input(inpstr,0,'m',...
                ['User-defined|'...
                 'Linear (equal steps)|' ...
                 'Geometric (log-spaced)|' ...
                 'Power-law (t.^\alpha)'],1:4,1);

            % --- Compute defaults from current 'dims'
            maxDimAbs = size(NM.Y{NM.TrainParam.FUSION.M(1)},2);
            [def_min, def_max, def_N] = i_compute_defaults_from_dims(dims, PercMode, maxDimAbs);

            % --- Build the grid
            switch StepMode

                case 1 % User-defined
                    dims = nk_input(sprintf('Define range of dimensionalities to be extracted from projection (min: %g, max: %g)', def_min, def_max), 0, 'e', defdims);
                    
                case {2,3,4} % Linear
                    params = nk_input(sprintf('Enter [min max N] (default: %.6g %.6g %d)',def_min,def_max,def_N),0,'e',[def_min def_max def_N]);
                    if numel(params) < 3, params = [def_min def_max def_N]; end
                    mnv = params(1); mxv = params(2); N = max(1, round(params(3)));
        
                    if StepMode == 3
                        alpha = nk_input('Enter power exponent ''alpha'' (>1 faster growth; default 2):',0,'e',2);
                        if isempty(alpha); alpha = 2; end
                    else
                        alpha = [];
                    end

                    switch StepMode
                        case 2
                            grid = linspace(mnv, mxv, N);
        
                        case 3 % Geometric
                            if (mnv <= 0) || (mxv <= 0)
                                fprintf(2,'[nk_ExtDim_config] Geometric stepping requires min>0 and max>0. Falling back to Linear.\n');
                                grid = linspace(max(eps,mnv), max(eps,mxv), N);
                            else
                                grid = logspace(log10(mnv), log10(mxv), N);
                            end
        
                        case 4 % Power-law
                            t = linspace(0,1,N);
                            if isempty(alpha) || alpha<=0, alpha = 2; end
                            grid = mnv + (mxv - mnv) * (t .^ alpha);
                    end
                    % --- Finalize dims based on PercMode
                    switch PercMode
                        case 1 % Absolute
                            dims = unique(max(1, round(grid)));
                            dims = unique([dims(:).' round(mxv)]);
                        otherwise % Percent/Energy
                            dims = grid;
                            dims = max(min(dims, mxv), mnv);
                    end
            end

        case 3
            % Manual entry kept for backwards compatibility
            inpstr = 'Dimensionalities to project data on (e.g: 1 5 10 or Start:Step:Stop)';
            dims = nk_input(inpstr, 0, 'e', defdims); 
    end
    if numel(mn_act)<2, act = 0; end

else
    switch RedMode
        case {'PCA', 't-SNE'}
            dims = 0.8; PercMode = 3;
        case 'SparsePCA'
            dims = floor(numel(NM.cases)/10); PercMode = 1;
        case 'PLS'
            dims = 1;
        case {'LDA','GDA'}
            L = NM.label; L(isnan(L))=[]; dims = numel(unique(L)); 
        case {'fastICA'}
            dims = floor(size(NM.Y{NM.TrainParam.FUSION.M(1)},2)/10); PercMode = 1; 
        otherwise
            dims = floor(size(NM.Y{NM.TrainParam.FUSION.M(1)},2)/10); PercMode = 1;
    end
    act = 0;
end

end

% ===========================
% Local helper
% ===========================
function [def_min, def_max, def_N] = i_compute_defaults_from_dims(dims, PercMode, maxDimAbs)
% Derive [min max N] from existing 'dims'.
% - If 'dims' is a vector with >1 element: use span and length.
% - If scalar/empty: infer sensible defaults per PercMode.

    if nargin < 3 || isempty(maxDimAbs), maxDimAbs = 1e6; end

    if isempty(dims)
        switch PercMode
            case 1  % Absolute
                def_min = 1;
                def_max = max(5, floor(0.8 * maxDimAbs));
                % N heuristic: more points for larger ranges, but capped
                def_N   = min(30, max(10, round(sqrt(max(1, def_max-def_min+1)))));
            case 2  % Percentage
                def_min = 0.05; def_max = 1.0; def_N = 20;
            case 3  % Energy
                def_min = 0.50; def_max = 0.99; def_N = 12;
        end
        return
    end

    if numel(dims) > 1
        switch PercMode
            case 1  % Absolute
                v = unique(max(1, round(dims(:))));
                def_min = max(1, min(v));
                def_max = min(maxDimAbs, max(v));
                def_N   = numel(v);
            otherwise % Percentage/Energy
                v = dims(:)';
                % If user accidentally passed absolute numbers, normalize
                if any(v > 1.001) && maxDimAbs > 1
                    v = v ./ maxDimAbs;
                end
                v = max(0, min(1, v));
                def_min = min(v);
                def_max = max(v);
                def_N   = numel(unique(round(v,6))); % collapse near-duplicates
        end
    else
        % Scalar 'dims' — infer a reasonable window and count
        d = dims(1);
        switch PercMode
            case 1 % Absolute
                if d < 1, d = floor(0.8 * maxDimAbs); end
                d = round(d);
                def_min = 1;
                def_max = min(maxDimAbs, max(5, d));
                span    = max(1, def_max - def_min + 1);
                def_N   = min(30, max(10, round(sqrt(span))));
            otherwise % Percentage/Energy
                % If absolute slipped in, convert to percent of max
                if d > 1.001 && maxDimAbs > 1, d = d / maxDimAbs; end
                d = max(0, min(1, d));
                % Center a default window around d, respecting typical ranges
                if PercMode == 3
                    base_min = 0.50; base_max = 0.99;
                else
                    base_min = 0.05; base_max = 1.00;
                end
                w        = 0.25;                   % 25% window around d
                def_min  = max(base_min, max(0, d - w*(base_max-base_min)));
                def_max  = min(base_max, min(1, d + w*(base_max-base_min)));
                def_N    = 12;
        end
    end
end