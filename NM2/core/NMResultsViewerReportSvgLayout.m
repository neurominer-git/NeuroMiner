classdef NMResultsViewerReportSvgLayout
% NMRESULTSVIEWERREPORTSVGLAYOUT Deterministic SVG layout helpers for NM reports.
%   NMResultsViewerReportSvgLayout centralizes axis, tick-label, axis-title,
%   annotation, colorbar and heatmap layout for MATLAB-generated static SVGs
%   used by the NM Results Viewer report exporter. The class deliberately uses
%   dependency-free text-extent estimates rather than browser-side DOM
%   measurement so that generated HTML/PDF sidecars remain self-contained and
%   reproducible in non-interactive MATLAB contexts.
%
%   Public methods return fixed-schema structs and SVG fragments. They are not
%   intended as a general graphics framework; their scope is report figures
%   produced by NMResultsViewerReportFigureTools.

    methods (Static)
        function opts = defaultAxesOptions()
            % defaultAxesOptions Return fixed-schema default axis-layout options.
            opts = struct( ...
                'MinLeft', 58, ...
                'MinRight', 18, ...
                'MinTop', 28, ...
                'MinBottom', 52, ...
                'OuterPad', 10, ...
                'TickFontSize', 10, ...
                'LabelFontSize', 11, ...
                'TitleFontSize', 12, ...
                'MaxXTicks', 5, ...
                'MaxYTicks', 5, ...
                'TickLabelGap', 7, ...
                'TickToTitleGap', 18, ...
                'AxisTitleGap', 11, ...
                'AnnotationGap', 22, ...
                'LegendWidth', 0, ...
                'ColorbarWidth', 0, ...
                'AnnotationRows', {{}});
        end

        function layout = axesLayout(width, height, xLim, yLim, xLabel, yLabel, titleText, opts)
            % axesLayout Compute a content-aware axis layout for one SVG panel.
            if nargin < 7, titleText = ''; end
            if nargin < 8 || ~isstruct(opts), opts = struct(); end
            opt = NMResultsViewerReportSvgLayout.mergeOptions(NMResultsViewerReportSvgLayout.defaultAxesOptions(), opts);
            xTicks = NMResultsViewerReportSvgLayout.niceTicks(xLim, opt.MaxXTicks);
            yTicks = NMResultsViewerReportSvgLayout.niceTicks(yLim, opt.MaxYTicks);
            xTickLabels = NMResultsViewerReportSvgLayout.formatTickLabels(xTicks);
            yTickLabels = NMResultsViewerReportSvgLayout.formatTickLabels(yTicks);
            xLabel = NMResultsViewerReportSvgLayout.prettifyLabel(xLabel);
            yLabel = NMResultsViewerReportSvgLayout.prettifyLabel(yLabel);
            titleText = NMResultsViewerReportSvgLayout.prettifyLabel(titleText);
            yTickWidth = NMResultsViewerReportSvgLayout.maxTextWidth(yTickLabels, opt.TickFontSize);
            xTickWidth = NMResultsViewerReportSvgLayout.maxTextWidth(xTickLabels, opt.TickFontSize);
            xTickHeight = opt.TickFontSize + 4;
            if xTickWidth > 58
                xTickHeight = min(68, 0.72*xTickWidth + 8);
            end
            annotationRows = NMResultsViewerReportSvgLayout.annotationRows(opt.AnnotationRows);
            annotationHeight = numel(annotationRows) * 14;
            left = max(opt.MinLeft, opt.OuterPad + opt.LabelFontSize*1.35 + opt.AxisTitleGap + yTickWidth + opt.TickLabelGap);
            right = max(opt.MinRight, opt.OuterPad + opt.LegendWidth + opt.ColorbarWidth);
            top = max(opt.MinTop, opt.OuterPad + (~isempty(titleText))*(opt.TitleFontSize + 8));
            bottom = max(opt.MinBottom, opt.TickLabelGap + xTickHeight + opt.TickToTitleGap + opt.LabelFontSize + annotationHeight + (~isempty(annotationRows))*opt.AnnotationGap);
            minPlotW = 120; minPlotH = 100;
            if left + right + minPlotW > width
                left = max(opt.MinLeft, width - right - minPlotW);
            end
            if top + bottom + minPlotH > height
                bottom = max(opt.MinBottom, height - top - minPlotH);
            end
            plotW = max(minPlotW, width - left - right);
            plotH = max(minPlotH, height - top - bottom);
            xTitleY = top + plotH + opt.TickLabelGap + xTickHeight + opt.TickToTitleGap;
            yTitleX = max(10, left - opt.TickLabelGap - yTickWidth - opt.AxisTitleGap - opt.LabelFontSize*0.55);
            tmpl = struct( ...
                'width', double(width), ...
                'height', double(height), ...
                'left', double(left), ...
                'top', double(top), ...
                'plotW', double(plotW), ...
                'plotH', double(plotH), ...
                'right', double(right), ...
                'bottom', double(bottom), ...
                'xLim', double(xLim(:)'), ...
                'yLim', double(yLim(:)'), ...
                'xTicks', double(xTicks(:)'), ...
                'yTicks', double(yTicks(:)'), ...
                'xTickLabels', {xTickLabels(:)'}, ...
                'yTickLabels', {yTickLabels(:)'}, ...
                'xLabel', char(string(xLabel)), ...
                'yLabel', char(string(yLabel)), ...
                'titleText', char(string(titleText)), ...
                'xTitleY', double(xTitleY), ...
                'yTitleX', double(yTitleX), ...
                'annotationRows', {annotationRows(:)'}, ...
                'annotationY', double(xTitleY + opt.AnnotationGap), ...
                'tickFontSize', double(opt.TickFontSize), ...
                'labelFontSize', double(opt.LabelFontSize), ...
                'titleFontSize', double(opt.TitleFontSize));
            layout = tmpl;
        end

        function html = axesSvg(layout)
            % axesSvg Render axes, grid, tick labels, titles and annotations.
            parts = {sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff" stroke="#cbd5e1"/>', layout.left, layout.top, layout.plotW, layout.plotH)};
            for ii = 1:numel(layout.xTicks)
                x = NMResultsViewerReportSvgLayout.mapX(layout.xTicks(ii), layout.xLim, layout.left, layout.plotW);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2e8f0"/><text x="%.1f" y="%.1f" text-anchor="middle" font-size="%.0f" fill="#475569">%s</text>', ...
                    x, layout.top, x, layout.top+layout.plotH, x, layout.top+layout.plotH+17, layout.tickFontSize, NMResultsViewerReportSvgLayout.escape(layout.xTickLabels{ii})); %#ok<AGROW>
            end
            for ii = 1:numel(layout.yTicks)
                y = NMResultsViewerReportSvgLayout.mapY(layout.yTicks(ii), layout.yLim, layout.top, layout.plotH);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2e8f0"/><text x="%.1f" y="%.1f" text-anchor="end" font-size="%.0f" fill="#475569">%s</text>', ...
                    layout.left, y, layout.left+layout.plotW, y, layout.left-7, y+3, layout.tickFontSize, NMResultsViewerReportSvgLayout.escape(layout.yTickLabels{ii})); %#ok<AGROW>
            end
            if ~isempty(layout.xLabel)
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="%.0f" fill="#334155">%s</text>', layout.left+layout.plotW/2, layout.xTitleY, layout.labelFontSize, NMResultsViewerReportSvgLayout.escape(layout.xLabel));
            end
            if ~isempty(layout.yLabel)
                cy = layout.top + layout.plotH/2;
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" transform="rotate(-90 %.1f %.1f)" text-anchor="middle" font-size="%.0f" fill="#334155">%s</text>', layout.yTitleX, cy, layout.yTitleX, cy, layout.labelFontSize, NMResultsViewerReportSvgLayout.escape(layout.yLabel));
            end
            if ~isempty(layout.titleText)
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="%.0f" font-weight="700" fill="#0f172a">%s</text>', layout.left+layout.plotW/2, max(16,layout.top-10), layout.titleFontSize, NMResultsViewerReportSvgLayout.escape(layout.titleText));
            end
            for ii = 1:numel(layout.annotationRows)
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="#475569">%s</text>', layout.left, layout.annotationY+14*(ii-1), NMResultsViewerReportSvgLayout.escape(layout.annotationRows{ii})); %#ok<AGROW>
            end
            html = strjoin(parts, '');
        end

        function html = axesSvgFixed(left, top, plotW, plotH, xLim, yLim, xLabel, yLabel)
            % axesSvgFixed Render axes for legacy callers with fixed plot boxes.
            opts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            opts.MinLeft = left;
            opts.MinTop = top;
            opts.MinRight = 18;
            opts.MinBottom = 48;
            layout = NMResultsViewerReportSvgLayout.axesLayout(left+plotW+opts.MinRight, top+plotH+opts.MinBottom, xLim, yLim, xLabel, yLabel, '', opts);
            layout.left = left;
            layout.top = top;
            layout.plotW = plotW;
            layout.plotH = plotH;
            layout.xTitleY = top + plotH + 40;
            yTickLabels = layout.yTickLabels;
            yTickWidth = NMResultsViewerReportSvgLayout.maxTextWidth(yTickLabels, layout.tickFontSize);
            layout.yTitleX = max(10, left - 7 - yTickWidth - 12 - layout.labelFontSize*0.55);
            html = NMResultsViewerReportSvgLayout.axesSvg(layout);
        end

        function layout = heatmapLayout(width, height, xVals, yVals, xLabel, yLabel, titleText, hasColorbar)
            % heatmapLayout Compute plot geometry for categorical heatmap panels.
            if nargin < 8, hasColorbar = true; end
            xVals = cellstr(string(xVals)); yVals = cellstr(string(yVals));
            xLabel = NMResultsViewerReportSvgLayout.prettifyLabel(xLabel);
            yLabel = NMResultsViewerReportSvgLayout.prettifyLabel(yLabel);
            yTickWidth = NMResultsViewerReportSvgLayout.maxTextWidth(yVals, 9);
            xTickWidth = NMResultsViewerReportSvgLayout.maxTextWidth(xVals, 8);
            xTickHeight = min(70, max(16, 0.70*xTickWidth + 10));
            left = max(54, 10 + 13 + 12 + yTickWidth + 8);
            right = 16 + hasColorbar * 58;
            top = max(30, 26 + ~isempty(titleText)*6);
            bottom = max(54, xTickHeight + 28);
            plotW = max(120, width-left-right);
            plotH = max(100, height-top-bottom);
            tmpl = struct('width',double(width),'height',double(height),'left',double(left),'top',double(top), ...
                'plotW',double(plotW),'plotH',double(plotH),'right',double(right),'bottom',double(bottom), ...
                'xVals',{xVals(:)'},'yVals',{yVals(:)'},'xLabel',xLabel,'yLabel',yLabel, ...
                'titleText',NMResultsViewerReportSvgLayout.prettifyLabel(titleText), ...
                'maxXTicks',8,'maxYTicks',8,'tickRotation',-45,'xTitleOffset',58);
            layout = tmpl;
        end

        function html = heatmapAxesSvg(layout, rotateX)
            % heatmapAxesSvg Render categorical heatmap ticks and labels.
            if nargin < 2, rotateX = false; end
            parts = cell(1,0);
            nX = max(1,numel(layout.xVals)); nY = max(1,numel(layout.yVals));
            maxXTicks = min(nX,layout.maxXTicks); maxYTicks = min(nY,layout.maxYTicks);
            xt = unique(round(linspace(1,nX,maxXTicks)));
            yt = unique(round(linspace(1,nY,maxYTicks)));
            for ii = 1:numel(xt)
                k = xt(ii); x = layout.left + (k-0.5)*layout.plotW/nX;
                txt = NMResultsViewerReportSvgLayout.escape(layout.xVals{k});
                if rotateX
                    y = layout.top + layout.plotH + 18;
                    parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="end" transform="rotate(%.1f %.1f %.1f)" font-size="8" fill="#475569">%s</text>', x,y,layout.tickRotation,x,y,txt); %#ok<AGROW>
                else
                    parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="9" fill="#475569">%s</text>', x,layout.top+layout.plotH+14,txt); %#ok<AGROW>
                end
            end
            for ii = 1:numel(yt)
                k = yt(ii); y = layout.top + (k-0.5)*layout.plotH/nY;
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="9" fill="#475569">%s</text>', layout.left-6,y+3,NMResultsViewerReportSvgLayout.escape(layout.yVals{k})); %#ok<AGROW>
            end
            xTitleY = layout.top + layout.plotH + (rotateX*layout.xTitleOffset + ~rotateX*32);
            yTitleX = max(10, layout.left - 6 - NMResultsViewerReportSvgLayout.maxTextWidth(layout.yVals,9) - 14);
            parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#334155">%s</text>', layout.left+layout.plotW/2, xTitleY, NMResultsViewerReportSvgLayout.escape(layout.xLabel));
            cy = layout.top + layout.plotH/2;
            parts{end+1} = sprintf('<text x="%.1f" y="%.1f" transform="rotate(-90 %.1f %.1f)" text-anchor="middle" font-size="10" fill="#334155">%s</text>', yTitleX, cy, yTitleX, cy, NMResultsViewerReportSvgLayout.escape(layout.yLabel));
            html = strjoin(parts,'');
        end

        function txt = prettifyLabel(txt)
            % prettifyLabel Convert internal variable labels into report labels.
            txt = char(string(txt));
            txt = strrep(txt, '_', ' ');
            txt = regexprep(txt, '\s+', ' ');
            txt = strtrim(txt);
            if isempty(txt), return; end
            words = strsplit(lower(txt));
            acronyms = {'cv','cv1','cv2','lr','roc','auc','dca','mcc','bac','r2','nm','sem'};
            for ii = 1:numel(words)
                if any(strcmp(words{ii}, acronyms))
                    words{ii} = upper(words{ii});
                elseif ii == 1
                    words{ii} = [upper(words{ii}(1)) words{ii}(2:end)];
                end
            end
            txt = strjoin(words, ' ');
        end

        function txt = formatNumber(x)
            % formatNumber Format numeric tick labels compactly for SVG reports.
            if ~isnumeric(x) || isempty(x) || ~isfinite(double(x(1)))
                txt = 'NA'; return;
            end
            v = double(x(1));
            if abs(v) < 5e-13, v = 0; end
            av = abs(v);
            if av >= 1e4 || (av > 0 && av < 1e-3)
                txt = sprintf('%.3g', v);
            elseif av >= 100
                txt = sprintf('%.0f', v);
            elseif av >= 10
                txt = sprintf('%.2f', v);
            elseif av >= 1
                txt = sprintf('%.3g', v);
            else
                txt = sprintf('%.4g', v);
            end
            if contains(txt,'.') && ~contains(lower(txt),'e')
                txt = regexprep(txt, '0+$', '');
                txt = regexprep(txt, '\.$', '');
            end
            if strcmp(char(string(txt)), '-0'), txt = '0'; end
        end

        function vals = niceTicks(lim, maxTicks)
            % niceTicks Generate compact deterministic axis ticks.
            lim = double(lim(:)');
            if numel(lim) < 2 || any(~isfinite(lim)) || lim(1) == lim(2)
                lim = [0 1];
            end
            if lim(2) < lim(1), lim = fliplr(lim); end
            if nargin < 2 || ~isfinite(maxTicks) || maxTicks < 2, maxTicks = 5; end
            span = lim(2)-lim(1);
            rawStep = span / max(1,maxTicks-1);
            magnitude = 10.^floor(log10(rawStep));
            ratio = rawStep ./ magnitude;
            if ratio <= 1
                nice = 1;
            elseif ratio <= 2
                nice = 2;
            elseif ratio <= 5
                nice = 5;
            else
                nice = 10;
            end
            step = nice .* magnitude;
            firstTick = ceil(lim(1)./step).*step;
            lastTick = floor(lim(2)./step).*step;
            vals = firstTick:step:lastTick;
            if numel(vals) < 2
                vals = linspace(lim(1),lim(2),maxTicks);
            elseif numel(vals) > maxTicks + 2
                vals = vals(unique(round(linspace(1,numel(vals),maxTicks))));
            end
            vals = double(vals(:)');
        end

        function labels = formatTickLabels(vals)
            labels = cell(1,numel(vals));
            for ii = 1:numel(vals)
                labels{ii} = NMResultsViewerReportSvgLayout.formatNumber(vals(ii));
            end
        end

        function width = maxTextWidth(labels, fontSize)
            if isempty(labels), width = 0; return; end
            labels = cellstr(string(labels));
            vals = zeros(1,numel(labels));
            for ii = 1:numel(labels)
                vals(ii) = NMResultsViewerReportSvgLayout.textWidth(labels{ii}, fontSize);
            end
            width = max(vals);
        end

        function width = textWidth(txt, fontSize)
            txt = char(string(txt));
            if nargin < 2 || ~isfinite(fontSize), fontSize = 10; end
            width = 0;
            for ii = 1:numel(txt)
                ch = txt(ii);
                if ch == ' '
                    factor = 0.32;
                elseif any(ch == 'ilI.,:;|')
                    factor = 0.34;
                elseif any(ch == 'mwMW@#%')
                    factor = 0.86;
                elseif any(ch == '-+0123456789')
                    factor = 0.56;
                else
                    factor = 0.62;
                end
                width = width + fontSize .* factor;
            end
        end

        function color = contrastText(hex)
            % contrastText Return black/white text for legibility on a fill color.
            lum = NMResultsViewerReportSvgLayout.hexLuminance(hex);
            if lum < 0.43
                color = '#ffffff';
            else
                color = '#0f172a';
            end
        end

        function lum = hexLuminance(hex)
            hex = char(string(hex));
            if numel(hex) < 7 || hex(1) ~= '#'
                lum = 1; return;
            end
            rgb = sscanf(hex(2:7),'%2x%2x%2x',[1 3]);
            if numel(rgb) ~= 3
                lum = 1; return;
            end
            rgb = double(rgb)./255;
            lum = 0.2126*rgb(1) + 0.7152*rgb(2) + 0.0722*rgb(3);
        end

        function x = mapX(v, lim, left, plotW)
            x = left + (double(v)-lim(1))./max(eps,lim(2)-lim(1)).*plotW;
        end

        function y = mapY(v, lim, top, plotH)
            y = top + (lim(2)-double(v))./max(eps,lim(2)-lim(1)).*plotH;
        end

        function txt = escape(txt)
            txt = char(string(txt));
            txt = strrep(txt,'&','&amp;');
            txt = strrep(txt,'<','&lt;');
            txt = strrep(txt,'>','&gt;');
            txt = strrep(txt,'"','&quot;');
            txt = strrep(txt,'''','&#39;');
        end
    end

    methods (Static, Access = private)
        function out = mergeOptions(defaults, overrides)
            out = defaults;
            names = fieldnames(overrides);
            for ii = 1:numel(names)
                out.(names{ii}) = overrides.(names{ii});
            end
        end

        function rows = annotationRows(raw)
            rows = {};
            if isempty(raw), return; end
            if ischar(raw) || isstring(raw)
                rows = cellstr(string(raw));
            elseif iscell(raw)
                rows = cell(1,numel(raw));
                for ii = 1:numel(raw), rows{ii} = char(string(raw{ii})); end
            end
            rows = rows(~cellfun(@isempty, rows));
        end
    end
end
