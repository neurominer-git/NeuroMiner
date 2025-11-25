function [handles, ystyle] = get_metric_axis_style(handles, ctx, dataVec)
% ctx: result of get_modelperf_context(handles)
% dataVec: vector of the *metric* values currently plotted (e.g., mPerf(:))
% Returns struct with YLim, YTick, YTickLabel, YLabel

ys = struct('YLim',[], 'YTick',[], 'YTickLabel',[], 'YLabel','');

% 1) Label (same string you already use everywhere)
ys.YLabel = ctx.ylb;  % e.g., 'CV1/CV2-test performance [BAC]' etc.
ys.PerfLabel = ctx.pardesc;

% 2) Limits & ticks based on metric type (heuristics consistent with your code)
meas = ctx.meastype;
dv   = dataVec(:); dv = dv(isfinite(dv));

% helper: padded min/max
pad = @(a,b,p) [a - p*(b-a), b + p*(b-a)];

if isempty(dv)
    dv = 0; % fallback
end

switch meas
    case {'Cross-validation performances','Multi-class cross-validation performance'}
        % percentages in [0,100]
        mn = min(dv); mx = max(dv);
        if ~isfinite(mn) || ~isfinite(mx) || mn==mx
            mn = 0; mx = max(1, mx);
        end
        ys.YLim  = pad(mn, mx, 0.05);
        ys.YTick = linspace(ys.YLim(1), ys.YLim(2), 10);
        ys.YTickLabel = arrayfun(@(x)sprintf('%1.1f',x), ys.YTick, 'UniformOutput',false);

    case {'Generalization error','Multi-class generalization error'}
        % difference -> symmetric around zero
        M = max(abs(dv));
        if ~isfinite(M) || M==0, M = 1; end
        M = ceil(M); % nicer tick locations
        ys.YLim  = [-M M];
        % choose ~5 ticks including 0
        ys.YTick = linspace(-M, M, 5);
        ys.YTickLabel = arrayfun(@(x)sprintf('%g',x), ys.YTick, 'UniformOutput',false);

    case {'Model complexity','Multi-class model complexity', ...
          'Model selection frequency','Multi-class model selection frequency', ...
          'Examination frequencies'}
       mn = min(dv); mx = max(dv);
        if ~isfinite(mn) || ~isfinite(mx) || mn==mx
            mn = 0; mx = max(1, mx);
        end
        ys.YLim  = pad(mn, mx, 0.05);
        ys.YTick = linspace(ys.YLim(1), ys.YLim(2), 10);
        ys.YTickLabel = arrayfun(@(x)sprintf('%1.2f',x), ys.YTick, 'UniformOutput',false);

    case {'Ensemble diversity','Multi-class ensemble diversity'}
        % entropy units: let data drive, but pad a bit
        mn = min(dv); mx = max(dv);
        if ~isfinite(mn) || ~isfinite(mx) || mn==mx
            mn = 0; mx = max(1, mx);
        end
        ys.YLim  = pad(mn, mx, 0.05);
        ys.YTick = linspace(ys.YLim(1), ys.YLim(2), 5);
        ys.YTickLabel = arrayfun(@(x)sprintf('%.3g',x), ys.YTick, 'UniformOutput',false);

    case {'Overall sequence gain'}
        % could be in same units as performance; derive from data but include zero
        mn = min([dv; 0]); mx = max([dv; 0]);
        if mn==mx, mn = mn-1; mx = mx+1; end
        ys.YLim  = pad(mn, mx, 0.05);
        ys.YTick = linspace(ys.YLim(1), ys.YLim(2), 5);
        ys.YTickLabel = arrayfun(@(x)sprintf('%.3g',x), ys.YTick, 'UniformOutput',false);

    case {'Case propagation thresholds'}
        % your code uses +/- 100 bands
        ys.YLim  = [-100 100];
        ys.YTick = -100:20:100;
        ys.YTickLabel = arrayfun(@(x)sprintf('%g',x), ys.YTick, 'UniformOutput',false);

    otherwise
        % safe fallback from data with small padding
        mn = min(dv); mx = max(dv);
        if ~isfinite(mn) || ~isfinite(mx) || mn==mx
            mn = 0; mx = max(1, mx);
        end
        ys.YLim  = pad(mn, mx, 0.05);
        ys.YTick = linspace(ys.YLim(1), ys.YLim(2), 5);
        ys.YTickLabel = arrayfun(@(x)sprintf('%.3g',x), ys.YTick, 'UniformOutput',false);
end

ystyle = ys;
handles.lastYStyle = ys; % stash for later restores
end
