function [ok, info] = nk_AssertValidBatch(vec, name, varargin)
%NK_ASSERTVALIDBATCH  Validate that a vector is a *categorical batch factor*.
%
% [ok, info] = nk_AssertValidBatch(vec, name, 'Mode', 'warn', 'MaxUniqueFraction', 0.2, ...)
%
% PURPOSE
%   Guard against accidentally using continuous variables (e.g., age) as a
%   ComBat batch. Detects "continuous-like" vectors and non-integer numeric
%   categories. Works with numeric, logical, string, char, cellstr, or categorical.
%
% INPUTS
%   vec   : batch vector (Nx1 or 1xN). NaNs are ignored for diagnostics.
%   name  : char/string label used in messages (e.g., 'Constraint' or 'HarmonizerBatch').
%   varargin (name–value pairs), supported options:
%       'Mode'                  : 'error' | 'warn' | 'silent'  (default 'error')
%       'MaxUniqueFraction'     : fraction N where > means "continuous-like" (default 0.25)
%       'MaxUniqueAbsolute'     : absolute unique-count threshold (default 50)
%       'RequireIntegerNumeric' : true/false; numeric levels must be integer-like (default true)
%       'EpsTol'                : tolerance for integer-likeness (default 1e-9)
%       'MinNumLevels'          : minimum number of levels required (default 2)
%       'SuggestBins'           : true/false; if true & continuous-like, propose bin edges (default true)
%       'TargetBins'            : desired number of bins for suggestion (default 8)
%
%   Backward compatibility: if the first varargin is a struct, it is treated
%   as a legacy opts struct and merged before applying any name–value pairs.
%
% OUTPUTS
%   ok   : logical, true if vec looks like a valid batch factor.
%   info : struct with diagnostics:
%       .N, .nLevels, .uniqueFraction
%       .isNumeric, .isIntegerLike, .looksContinuous
%       .levelsSample (up to first 20 levels)
%       .binEdges (if suggested), .reason (text)
%
% EXAMPLES
%   [ok,info] = nk_AssertValidBatch(Age,'Age');                          % likely fails
%   [ok,info] = nk_AssertValidBatch(Constraint,'Constraint');            % categorical pass
%   [ok,info] = nk_AssertValidBatch(vec,'Constraint','Mode','warn');     % non-fatal
%
% (c) 2025, NeuroMiner/NK utils. MIT license.

    % ----- defaults
    defaults = struct( ...
        'Mode',                  'error', ...
        'MaxUniqueFraction',     0.25, ...
        'MaxUniqueAbsolute',     50, ...
        'RequireIntegerNumeric', true, ...
        'EpsTol',                1e-9, ...
        'MinNumLevels',          2, ...
        'SuggestBins',           true, ...
        'TargetBins',            8);

    % ----- parse varargin with backward compatibility for struct opts
    opts = defaults;

    v = varargin;
    if ~isempty(v) && isstruct(v{1})
        s = v{1};
        fn = fieldnames(s);
        for k = 1:numel(fn)
            if isfield(opts, fn{k}) && ~isempty(s.(fn{k}))
                opts.(fn{k}) = s.(fn{k});
            end
        end
        v = v(2:end); % consume legacy struct
    end

    % Apply name–value pairs
    if ~isempty(v)
        if mod(numel(v),2) ~= 0
            error('nk_AssertValidBatch:BadNameValue', 'Name–value pairs must come in pairs.');
        end
        for k = 1:2:numel(v)
            namek = char(string(v{k}));
            if ~isfield(opts, namek)
                error('nk_AssertValidBatch:UnknownOption', 'Unknown option "%s".', namek);
            end
            opts.(namek) = v{k+1};
        end
    end

    % Normalize inputs
    name = char(string(name));
    vec  = vec(:); % column

    info = struct('N',numel(vec), 'nLevels',NaN, 'uniqueFraction',NaN, ...
                  'isNumeric',false, 'isIntegerLike',true, 'looksContinuous',false, ...
                  'levelsSample',[], 'binEdges',[], 'reason','');

    % Handle empty
    if isempty(vec)
        [ok,info.reason] = deal(false, sprintf('"%s" is empty.', name));
        returnOrAct(opts, ok, info, name); return;
    end

    % Determine type & normalize for uniqueness
    isNum  = isnumeric(vec) || islogical(vec);
    isCat  = iscategorical(vec);
    isStr  = isstring(vec) || ischar(vec) || iscellstr(vec);

    info.isNumeric = isNum;

    % Strip NaNs / <missing>
    if isNum
        mask = ~isnan(vec);
        vclean = vec(mask);
    elseif isCat
        mask = ~ismissing(vec);
        vclean = vec(mask);
    elseif isStr
        vclean = vec; % treat empty strings as levels
    else
        vclean = string(vec); isStr = true;
    end

    % Unique levels
    try
        if isCat
            u = categories(categorical(vclean));
        elseif isStr
            u = unique(string(vclean),'stable');
        else
            u = unique(vclean,'stable');
        end
    catch
        u = unique(vclean);
    end
    nU = numel(u);
    info.nLevels = nU;
    info.uniqueFraction = nU / max(1, countNonMissing(vec, isNum, isCat));

    % Sample of levels
    maxShow = min(20,nU);
    if isNum
        info.levelsSample = u(1:maxShow);
    else
        info.levelsSample = cellstr(string(u(1:maxShow)));
    end

    % Minimum level requirement
    if nU < opts.MinNumLevels
        ok = false;
        info.reason = sprintf('"%s" has too few levels (%d < %d).', name, nU, opts.MinNumLevels);
        returnOrAct(opts, ok, info, name); return;
    end

    % Integer-likeness for numeric vectors
    if isNum && opts.RequireIntegerNumeric
        if isempty(vclean)
            info.isIntegerLike = true;
        else
            info.isIntegerLike = all(abs(vclean - round(vclean)) <= opts.EpsTol);
        end
        if ~info.isIntegerLike
            ok = false;
            info.reason = sprintf('"%s" numeric levels are not integer-like (consider categorical coding).', name);
            returnOrAct(opts, ok, info, name); return;
        end
    end

    % Continuous-like heuristic (primarily for numeric vectors)
    looksContinuous = false;
    if isNum
        highUnique   = nU > max(opts.MaxUniqueAbsolute, ceil(opts.MaxUniqueFraction * info.N));
        manyDistinct = (nU > 0.8 * countNonMissing(vec, isNum, isCat)); % guardrail
        looksContinuous = highUnique && manyDistinct;
    end
    info.looksContinuous = looksContinuous;

    if looksContinuous
        ok = false;
        info.reason = sprintf('"%s" looks continuous (%d unique out of %d).', ...
                              name, nU, info.N);
        if opts.SuggestBins && isNum && ~isempty(vclean)
            info.binEdges = suggestBins(vclean, opts.TargetBins);
        end
        returnOrAct(opts, ok, info, name); return;
    end

    % Accept as batch factor
    ok = true;
    info.reason = 'OK';
end

% ===== local helpers =====

function n = countNonMissing(v, isNum, isCat)
    if isNum
        n = sum(~isnan(v));
    elseif isCat
        n = sum(~ismissing(v));
    else
        n = numel(v);
    end
end

function edges = suggestBins(x, targetBins)
    x = x(~isnan(x));
    if isempty(x), edges = []; return; end
    q25 = quantile(x,0.25);
    q75 = quantile(x,0.75);
    iqrX = max(eps, q75 - q25);
    h = 2*iqrX / max(1, numel(x)^(1/3));  % Freedman–Diaconis
    if ~isfinite(h) || h<=0
        h = (max(x)-min(x)) / max(3, targetBins);
    end
    nb = max(3, min(50, round((max(x)-min(x))/h)));
    if ~isempty(targetBins) && isfinite(targetBins) && targetBins>1
        nb = min( max(nb, round(0.5*targetBins)), round(1.5*targetBins) );
    end
    edges = linspace(min(x), max(x), nb+1);
end

function returnOrAct(opts, ok, info, name)
    switch lower(char(opts.Mode))
        case 'error'
            if ~ok
                baseMsg = sprintf('[nk_AssertValidBatch] %s', info.reason);
                if ~isempty(info.levelsSample)
                    baseMsg = sprintf('%s | levels sample: %s', baseMsg, levelsToString(info.levelsSample));
                end
                error('nk_AssertValidBatch:InvalidBatch', baseMsg);
            end
        case 'warn'
            if ~ok
                if ~isempty(info.binEdges)
                    be = sprintf(' (suggested binEdges: [%s])', num2str(info.binEdges, '%.3g '));
                else
                    be = '';
                end
                warning('[nk_AssertValidBatch] %s%s', info.reason, be);
            end
        otherwise % 'silent'
            % no-op
    end
end

function s = levelsToString(levels)
    if iscell(levels)
        s = strjoin(levels, ', ');
    elseif isnumeric(levels) || islogical(levels)
        s = strtrim(num2str(levels(:).', '%g '));
    else
        s = '<levels>';
    end
end
