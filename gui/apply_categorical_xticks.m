function apply_categorical_xticks(ax, labels, varargin)
% Ensure a non-repeating, discrete X axis for bar/grouped-bar plots.

p = inputParser;
addParameter(p,'MaxTicks',12,@(x)isnumeric(x)&&isscalar(x)&&x>=2);
parse(p,varargin{:});
MaxTicks = p.Results.MaxTicks;

if ischar(labels), labels = cellstr(labels); end
if isnumeric(labels), labels = arrayfun(@(x)sprintf('%g',x), labels, 'UniformOutput',false); end

N = numel(labels);
if N==0 || ~ishghandle(ax) || ~strcmp(get(ax,'Type'),'axes'), return; end

% 1) Fix axis to discrete bar centers
set(ax,'XLim',[0.5, N+0.5],'XLimMode','manual');

% 2) Choose a tick subset
step = max(1, ceil(N/MaxTicks));
idx = 1:step:N;
if idx(end) ~= N, idx = [idx N]; end  % always show last

% 3) Apply ticks/labels MANUALLY and keep them
xticks(ax, idx);
xticklabels(ax, labels(idx));
set(ax,'XTickMode','manual','XTickLabelMode','manual');

if numel(idx)>10, ax.XTickLabelRotation = 45; else, ax.XTickLabelRotation = 0; end
