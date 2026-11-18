classdef NMResultsViewerReportFigureTools
% NMResultsViewerReportFigureTools
% -------------------------------------------------------------------------
% Static SVG figure builders for NM2 Results Viewer static reports.
%
% This utility class converts report payload structures into deterministic,
% self-contained SVG fragments for HTML/PDF report rendering. The methods are
% read-only: they do not inspect browser DOM state, do not write files, and do
% not mutate NM, reportSpec, exportSpec, or component payloads. The primitives
% intentionally mirror the Results Viewer D3 semantics where possible while
% remaining dependency-free for MATLAB-side static report generation.
% -------------------------------------------------------------------------

    methods (Static)
        function html = confusionSvg(confusion)
            % confusionSvg  Render a K-by-K observed/predicted confusion heatmap.
            html = '';
            if ~confusion.ok, return; end
            M = NMResultsViewerReportFigureTools.numericMatrix(confusion.matrix);
            if isempty(M), return; end
            K = min(size(M,1), size(M,2));
            M = double(M(1:K,1:K));
            P = NMResultsViewerReportFigureTools.numericMatrix(confusion.percentMatrix);
            P = double(P(1:K,1:K));
            labels = NMResultsViewerReportFigureTools.cellstrSafe(confusion.labels);
            for kk=(numel(labels)+1):K, labels{kk} = sprintf('Class %d', kk); end %#ok<AGROW>
            w = 520; h = 420; left = 118; top = 40; plotW = 300; plotH = 300;
            cellW = plotW / K; cellH = plotH / K;
            finiteVals = M(isfinite(M)); if isempty(finiteVals), finiteVals = 0; end
            hi = max(1, max(finiteVals));
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Confusion matrix'), ...
                sprintf('<text x="%d" y="20" font-size="13" font-weight="700">Confusion matrix</text>', left)};
            for rr = 1:K
                for cc = 1:K
                    v = M(rr,cc); pct = P(rr,cc);
                    t = max(0,min(1,v/hi));
                    col = NMResultsViewerReportFigureTools.mixHex('#ffffff', '#2563eb', 0.18 + 0.72*t);
                    x = left + (cc-1)*cellW; y = top + (rr-1)*cellH;
                    parts{end+1} = sprintf(['<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="#fff" stroke-width="1"/>' ...
                        '<text x="%.1f" y="%.1f" text-anchor="middle" font-size="13" font-weight="700" fill="#0f172a">%s</text>' ...
                        '<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#334155">%s%%</text>'], ...
                        x,y,max(1,cellW-1),max(1,cellH-1),col,x+cellW/2,y+cellH/2-3,NMResultsViewerReportSvgLayout.formatNumber(v), ...
                        x+cellW/2,y+cellH/2+13,NMResultsViewerReportSvgLayout.formatNumber(pct)); %#ok<AGROW>
                end
            end
            for kk = 1:K
                tx = left + (kk-0.5)*cellW;
                ty = top + (kk-0.5)*cellH;
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#475569">%s</text>', tx, top+plotH+18, NMResultsViewerReportSvgLayout.escape(labels{kk})); %#ok<AGROW>
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="10" fill="#475569">%s</text>', left-8, ty+4, NMResultsViewerReportSvgLayout.escape(labels{kk})); %#ok<AGROW>
            end
            parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11" fill="#334155">Predicted class</text>', left+plotW/2, top+plotH+42);
            parts{end+1} = sprintf('<text x="16" y="%.1f" transform="rotate(-90 16 %.1f)" text-anchor="middle" font-size="11" fill="#334155">Observed class</text>', top+plotH/2, top+plotH/2);
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = rocSvg(roc)
            % rocSvg  Render binary or overlaid multi-class ROC curves.
            html = '';
            if ~roc.ok, return; end
            curves = roc.curves;
            if roc.multi && ~isempty(curves)
                w = 620; h = 380; left = 56; right = 190; top = 28; bottom = 46;
                plotW = w-left-right; plotH = h-top-bottom;
                parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'ROC curve')};
                parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,[0 1],[0 1],'False-positive rate','True-positive rate');
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg([0 1],[0 1],[0 1],[0 1],left,top,plotW,plotH,'#94a3b8',1.15,'4 4');
                legendRows = cell(0,4);
                for ii=1:numel(curves)
                    if ~logical(curves(ii).ok), continue; end
                    [x,y] = NMResultsViewerReportFigureTools.pointsXY(curves(ii).points,'fpr','tpr');
                    if nnz(isfinite(x) & isfinite(y)) < 2, continue; end
                    col = curves(ii).color;
                    parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(x,y,[0 1],[0 1],left,top,plotW,plotH,col,2.2,''); %#ok<AGROW>
                    label = NMResultsViewerReportFigureTools.compactLegendLabel(curves(ii).label);
                    auc = double(curves(ii).auc);
                    if isfinite(auc), label = sprintf('%s (%.3f)',label,auc); end
                    legendRows(end+1,:) = {label,col,'','line'}; %#ok<AGROW>
                end
                if isempty(legendRows), return; end
                parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(w-right+10,top+8,legendRows,right-24);
                parts{end+1} = '</svg>';
                html = ['<div class="viz">' strjoin(parts,'') '</div>'];
                return;
            end
            pts = roc.points;
            [x,y] = NMResultsViewerReportFigureTools.pointsXY(pts,'fpr','tpr');
            good = isfinite(x) & isfinite(y); x = x(good); y = y(good);
            if numel(x) < 2, return; end
            w = 520; h = 360; left = 56; right = 18; top = 28; bottom = 46;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'ROC curve')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,w-left-right,h-top-bottom,[0 1],[0 1],'False-positive rate','True-positive rate');
            parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#94a3b8" stroke-dasharray="4 4"/>', ...
                NMResultsViewerReportSvgLayout.mapX(0,[0 1],left,w-left-right), NMResultsViewerReportSvgLayout.mapY(0,[0 1],top,h-top-bottom), ...
                NMResultsViewerReportSvgLayout.mapX(1,[0 1],left,w-left-right), NMResultsViewerReportSvgLayout.mapY(1,[0 1],top,h-top-bottom));
            tc = roc.trainingCurve;
            if tc.ok
                [tx,ty] = NMResultsViewerReportFigureTools.pointsXY(tc.points,'fpr','tpr');
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(tx,ty,[0 1],[0 1],left,top,w-left-right,h-top-bottom,tc.color,1.4,'5 3'); %#ok<AGROW>
            end
            parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(x,y,[0 1],[0 1],left,top,w-left-right,h-top-bottom,'#2563eb',2.2,'');
            auc = double(roc.auc);
            aucTxt = 'AUC unavailable'; if isfinite(auc), aucTxt = sprintf('AUC %.3f', auc); end
            parts{end+1} = sprintf('<rect x="%d" y="%d" width="150" height="42" rx="8" fill="#f8fafc" stroke="#dbe4ef"/><line x1="%d" y1="%d" x2="%d" y2="%d" stroke="#2563eb" stroke-width="2.2"/><text x="%d" y="%d" font-size="11" fill="#0f172a">%s</text>', ...
                w-178, top+10, w-166, top+28, w-132, top+28, w-122, top+32, NMResultsViewerReportSvgLayout.escape(aucTxt));
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = scoreDistributionSvg(scoreRows, scoreColumns, pies)
            % scoreDistributionSvg  Render class-stratified score/probability histograms.
            %#ok<INUSD> scoreColumns is reserved for future column-label passthrough.
            html = '';
            if isempty(scoreRows)
                if pies.ok
                    html = NMResultsViewerReportFigureTools.probabilityPieFallbackSvg(pies);
                end
                return;
            end
            field = NMResultsViewerReportFigureTools.firstFiniteField(scoreRows, {'probability','ensembleProbability','score','stdScore','percentRank','predicted'});
            if isempty(field), return; end
            vals = NMResultsViewerReportFigureTools.structNumericArray(scoreRows, field);
            groups = NMResultsViewerReportFigureTools.structTextArray(scoreRows, 'expected');
            if all(cellfun(@isempty, groups)), groups = NMResultsViewerReportFigureTools.structTextArray(scoreRows, 'predicted'); end
            good = isfinite(vals); vals = vals(good); groups = groups(good);
            if isempty(vals), return; end
            for ii=1:numel(groups), if isempty(groups{ii}), groups{ii} = 'Cases'; end, end
            uGroups = unique(groups,'stable');
            if numel(uGroups) > 4, uGroups = uGroups(1:4); end
            lo = min(vals); hi = max(vals); if abs(hi-lo) < 1e-12, lo = lo - 0.5; hi = hi + 0.5; end
            nBins = min(24, max(8, round(sqrt(numel(vals)))));
            edges = linspace(lo, hi, nBins+1);
            counts = zeros(numel(uGroups), nBins);
            for gg=1:numel(uGroups)
                gv = vals(strcmp(groups,uGroups{gg}));
                counts(gg,:) = histcounts(gv, edges);
            end
            maxC = max(1, max(counts(:)));
            w = 620; h = 330; left = 56; right = 18; top = 28; bottom = 48;
            plotW = w-left-right; plotH = h-top-bottom;
            colors = {'#2563eb','#dc2626','#16a34a','#9333ea'};
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Score distribution')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,[lo hi],[0 maxC],field,'Count');
            bw = plotW / nBins / max(1,numel(uGroups));
            for gg=1:numel(uGroups)
                for bb=1:nBins
                    x0 = left + (bb-1)*plotW/nBins + (gg-1)*bw;
                    bh = counts(gg,bb) / maxC * plotH;
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.72"/>', x0, top+plotH-bh, max(1,bw-1), bh, colors{gg}); %#ok<AGROW>
                end
            end
            if lo < 0 && hi > 0
                zx = NMResultsViewerReportSvgLayout.mapX(0,[lo hi],left,plotW);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#0f172a" stroke-dasharray="4 3"/><text x="%.1f" y="%d" font-size="10" fill="#0f172a">decision line</text>', zx, top, zx, top+plotH, zx+4, top+12); %#ok<AGROW>
            end
            parts{end+1} = NMResultsViewerReportFigureTools.legendSvg(w-180, top+8, uGroups, colors);
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = classPlotSvg(plotPayload)
            % classPlotSvg  Render the primary binary-classification score plot.
            html = '';
            if ~plotPayload.ok, return; end
            if strcmp(plotPayload.mode,'oocv_violin')
                html = NMResultsViewerReportFigureTools.oocvViolinSvg(plotPayload);
                return;
            end
            pts = plotPayload.points;
            [x,y] = NMResultsViewerReportFigureTools.pointsXY(pts,'x','y');
            good = isfinite(x) & isfinite(y); x = x(good); y = y(good); pts = pts(good);
            if isempty(x), return; end
            xLim = NMResultsViewerReportFigureTools.limitField(plotPayload,'xLim',x);
            yLim = NMResultsViewerReportFigureTools.limitField(plotPayload,'yLim',y);
            w = 760; h = 420;
            opts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            opts.MinLeft = 72;
            opts.MinBottom = 62;
            opts.MinRight = 22;
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,xLim,yLim, ...
                plotPayload.xLabel, ...
                plotPayload.yLabel, ...
                'Classification plot', opts);
            left = layout.left; top = layout.top; plotW = layout.plotW; plotH = layout.plotH;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Classification plot')};
            patches = plotPayload.backgroundPatches;
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvg(layout);
            if ~isempty(patches)
                for ii=1:numel(patches)
                    px = double(patches(ii).x); py = double(patches(ii).y);
                    pw = double(patches(ii).w); ph = double(patches(ii).h);
                    if ~all(isfinite([px py pw ph])), continue; end
                    x0 = NMResultsViewerReportSvgLayout.mapX(px,xLim,left,plotW); x1 = NMResultsViewerReportSvgLayout.mapX(px+pw,xLim,left,plotW);
                    y0 = NMResultsViewerReportSvgLayout.mapY(py+ph,yLim,top,plotH); y1 = NMResultsViewerReportSvgLayout.mapY(py,yLim,top,plotH);
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="%.3f"/>', min(x0,x1), min(y0,y1), abs(x1-x0), abs(y1-y0), patches(ii).color, double(patches(ii).alpha)); %#ok<AGROW>
                end
            end
            z = plotPayload.zeroLine;
            if ~isempty(z.x) && ~isempty(z.y)
                zx = double(z.x(:)); zy = double(z.y(:));
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(zx,zy,xLim,yLim,left,top,plotW,plotH,'#0f172a',1.4,'4 3'); %#ok<AGROW>
            end
            maxPts = min(numel(x), 1500);
            idx = unique(round(linspace(1,numel(x),maxPts)));
            for jj=1:numel(idx)
                ii = idx(jj);
                cx = NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW);
                cy = NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH);
                col = pts(ii).color;
                if logical(pts(ii).misclassified)
                    parts{end+1} = sprintf('<path d="M %.1f %.1f L %.1f %.1f M %.1f %.1f L %.1f %.1f" stroke="%s" stroke-width="1.8"/>', cx-3,cy-3,cx+3,cy+3,cx-3,cy+3,cx+3,cy-3,col); %#ok<AGROW>
                else
                    parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="3" fill="%s" opacity="0.80"/>', cx,cy,col); %#ok<AGROW>
                end
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = oocvViolinSvg(plotPayload)
            % Static presentation of the producer-owned OOCV violin groups.
            % Density, mean, median, group order and case coordinates are not recomputed.
            groups = plotPayload.violinGroups;
            xLim = double(plotPayload.xLim);
            yLim = double(plotPayload.yLim);
            w = 920; h = 560;
            opts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            opts.MinLeft = 78;
            opts.MinBottom = 75;
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,xLim,yLim, ...
                plotPayload.xLabel,plotPayload.yLabel,plotPayload.title,opts);
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,plotPayload.title), ...
                NMResultsViewerReportSvgLayout.axesSvg(layout)};
            for ii = 1:numel(groups)
                group = groups(ii);
                density = group.density;
                if isempty(density), continue; end
                v = double([density.y]);
                half = double([density.width]);
                x = double(group.x);
                outlineX = [x + half, fliplr(x - half)];
                outlineY = [v, fliplr(v)];
                px = arrayfun(@(a)NMResultsViewerReportSvgLayout.mapX(a,xLim,layout.left,layout.plotW),outlineX);
                py = arrayfun(@(a)NMResultsViewerReportSvgLayout.mapY(a,yLim,layout.top,layout.plotH),outlineY);
                vertices = strtrim(sprintf('%.1f,%.1f ',[px(:),py(:)]'));
                parts{end+1} = sprintf('<polygon points="%s" fill="%s" fill-opacity="%.2f" stroke="%s"><title>%s</title></polygon>', ...
                    vertices,NMResultsViewerReportSvgLayout.escape(group.color),double(group.alpha), ...
                    NMResultsViewerReportSvgLayout.escape(group.color),NMResultsViewerReportSvgLayout.escape(group.label)); %#ok<AGROW>
                stats = [double(group.meanValue),double(group.medianValue)];
                colors = {'#111827','#dc2626'};
                for jj = 1:2
                    if ~isfinite(stats(jj)), continue; end
                    [~,near] = min(abs(v-stats(jj)));
                    dx = max(0.045,half(near)*0.92);
                    x0 = NMResultsViewerReportSvgLayout.mapX(x-dx,xLim,layout.left,layout.plotW);
                    x1 = NMResultsViewerReportSvgLayout.mapX(x+dx,xLim,layout.left,layout.plotW);
                    yy = NMResultsViewerReportSvgLayout.mapY(stats(jj),yLim,layout.top,layout.plotH);
                    parts{end+1} = sprintf('<line x1="%.1f" x2="%.1f" y1="%.1f" y2="%.1f" stroke="%s" stroke-width="2"/>', ...
                        x0,x1,yy,yy,colors{jj}); %#ok<AGROW>
                end
            end
            z = plotPayload.zeroLine;
            if ~isempty(z.x) && ~isempty(z.y)
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(double(z.x),double(z.y), ...
                    xLim,yLim,layout.left,layout.top,layout.plotW,layout.plotH,'#0f172a',1.2,'4 3'); %#ok<AGROW>
            end
            points = plotPayload.points;
            [px,py] = NMResultsViewerReportFigureTools.pointsXY(points,'x','y');
            good = find(isfinite(px) & isfinite(py));
            good = good(1:min(1500,numel(good)));
            for jj = good(:)'
                x = NMResultsViewerReportSvgLayout.mapX(px(jj),xLim,layout.left,layout.plotW);
                y = NMResultsViewerReportSvgLayout.mapY(py(jj),yLim,layout.top,layout.plotH);
                parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="0.72"/>', ...
                    x,y,double(points(jj).radius),NMResultsViewerReportSvgLayout.escape(points(jj).color)); %#ok<AGROW>
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = regressionScatterSvg(plotPayload)
            % regressionScatterSvg  Render observed-vs-predicted or x-axis regression scatter.
            %
            % The static report follows the same browser payload coordinates
            % (points.x / points.y and xLim/yLim) instead of recomputing common limits
            % from raw observed/predicted fields. This preserves target-rescaling and
            % alternative x-axis semantics established by the main Results Viewer.
            html = '';
            if ~plotPayload.ok, return; end
            pts = plotPayload.points;
            if isempty(pts), return; end
            [x,y] = NMResultsViewerReportFigureTools.pointsXY(pts,'x','y');
            xLabel = plotPayload.xLabel;
            yLabel = plotPayload.yLabel;
            if ~any(isfinite(x)) || ~any(isfinite(y))
                x = NMResultsViewerReportFigureTools.structNumericArray(pts,'observed');
                y = NMResultsViewerReportFigureTools.structNumericArray(pts,'predicted');
                xLabel = 'Observed target';
                yLabel = 'Predicted target';
            end
            good = isfinite(x) & isfinite(y); x = x(good); y = y(good); pts = pts(good);
            if isempty(x), return; end
            xLim = NMResultsViewerReportFigureTools.limitField(plotPayload,'xLim',x);
            yLim = NMResultsViewerReportFigureTools.limitField(plotPayload,'yLim',y);
            xLim = double(xLim); yLim = double(yLim);
            w = 620; h = 430;
            layoutOpts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            layoutOpts.MinLeft = 82;
            layoutOpts.MinBottom = 76;
            layoutOpts.MinRight = 28;
            layoutOpts.MaxXTicks = 12;
            layoutOpts.MaxYTicks = 12;
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,xLim,yLim,xLabel,yLabel,'Regression scatter',layoutOpts);
            left = layout.left; top = layout.top; plotW = layout.plotW; plotH = layout.plotH;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Regression scatter')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvg(layout);
            % The static report intentionally does not add an identity line here.
            % The browser view exposes a single regression fit for the complete point
            % cloud; adding a second y=x reference line made the PDF plot ambiguous
            % and diverged from the browser rendering.
            fit = plotPayload.fit;
            if fit.ok
                [fx,fy] = NMResultsViewerReportFigureTools.pointsXY(fit.line,'x','y');
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(fx,fy,xLim,yLim,left,top,plotW,plotH,'#c2410c',1.8,''); %#ok<AGROW>
            end
            maxPts = min(numel(x), 1500); idx = unique(round(linspace(1,numel(x),maxPts)));
            for jj=1:numel(idx)
                ii = idx(jj);
                cx = NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW);
                cy = NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH);
                col = '#2563eb'; if logical(pts(ii).error), col = '#dc2626'; end
                tip = pts(ii).tooltip;
                parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="3.4" fill="%s" opacity="0.76"><title>%s</title></circle>', cx,cy,col,NMResultsViewerReportSvgLayout.escape(tip)); %#ok<AGROW>
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = calibrationSvg(calibration)
            % calibrationSvg  Render a browser-aligned calibration reliability curve.
            html = '';
            if ~calibration.ok, return; end
            curves = NMResultsViewerReportFigureTools.curveList(calibration, 'calibration');
            if isempty(curves), return; end
            w = 620; h = 380; left = 82; right = 26; top = 26; bottom = 70;
            plotW = w-left-right; plotH = h-top-bottom;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Calibration curve')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,[0 1],[0 1],'Mean predicted value','Fraction of positives');
            parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg([0 1],[0 1],[0 1],[0 1],left,top,plotW,plotH,'#94a3b8',1.15,'4 3');
            legendRows = cell(0,4);
            for ii=1:numel(curves)
                col = curves(ii).color;
                [x,y] = NMResultsViewerReportFigureTools.calibrationXY(curves(ii).points);
                if nnz(isfinite(x) & isfinite(y)) >= 2
                    dash = ''; opacity = 1.0; width = 2.05;
                    if ii > 1 && curves(ii).isReference
                        dash = ''; opacity = 0.58; width = 1.55;
                    end
                    parts{end+1} = NMResultsViewerReportFigureTools.polylineSvgWithOpacity(x,y,[0 1],[0 1],left,top,plotW,plotH,col,width,dash,opacity); %#ok<AGROW>
                end
                [rx,ry] = NMResultsViewerReportFigureTools.calibrationXY(curves(ii).rawPoints);
                if nnz(isfinite(rx) & isfinite(ry)) >= 1 && length(curves) <= 4
                    parts{end+1} = NMResultsViewerReportFigureTools.circleSeriesSvg(rx,ry,[0 1],[0 1],left,top,plotW,plotH,col,3.6,0.88); %#ok<AGROW>
                end
                legendRows(end+1,:) = {NMResultsViewerReportFigureTools.compactLegendLabel(curves(ii).label), col, '', 'line'}; %#ok<AGROW>
            end
            metricName = calibration.metric;
            metricValue = double(calibration.metricValue);
            if ~isempty(metricName) && isfinite(metricValue)
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" font-size="10" fill="#475569">%s: %s</text>', left, h-12, NMResultsViewerReportSvgLayout.escape(metricName), NMResultsViewerReportSvgLayout.formatNumber(metricValue));
            end
            legendW = 150;
            parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(w-right-legendW-8,top+8,legendRows,legendW);
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = dcaSvg(dca)
            % dcaSvg  Render browser-aligned decision-curve net-benefit curves.
            html = '';
            if ~dca.ok, return; end
            curves = NMResultsViewerReportFigureTools.curveList(dca, 'dca');
            if isempty(curves), return; end
            allX = []; allY = [];
            for ii=1:numel(curves)
                [x,y] = NMResultsViewerReportFigureTools.dcaModelXY(curves(ii).points);
                allX=[allX;x(:)]; allY=[allY;y(:)]; %#ok<AGROW>
                if ii==1
                    [txa,ta] = NMResultsViewerReportFigureTools.pointsXY(curves(ii).points,'threshold','treatAll'); allX=[allX;txa(:)]; allY=[allY;ta(:)]; %#ok<AGROW>
                    [txn,tn] = NMResultsViewerReportFigureTools.pointsXY(curves(ii).points,'threshold','treatNone'); allX=[allX;txn(:)]; allY=[allY;tn(:)]; %#ok<AGROW>
                end
            end
            good = isfinite(allX) & isfinite(allY); if ~any(good), return; end
            maxProb = double(dca.maxProb);
            if ~isfinite(maxProb) || maxProb <= 0, maxProb = max(allX(isfinite(allX))); end
            if ~isfinite(maxProb) || maxProb <= 0, maxProb = 1; end
            xLim = [0 max(0.05,min(1,maxProb))];
            yLim = [min(allY(good)) max(allY(good))];
            if abs(yLim(2)-yLim(1)) < 1e-12, yLim = yLim + [-0.05 0.05]; end
            yPad = max(0.02, 0.04*abs(diff(yLim))); yLim = [yLim(1)-yPad yLim(2)+yPad];
            w = 620; h = 380; left = 82; right = 26; top = 26; bottom = 70;
            plotW = w-left-right; plotH = h-top-bottom;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Decision curve')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,xLim,yLim,'Probability threshold','Net benefit');
            legendRows = cell(0,4);
            for ii=1:numel(curves)
                [x,y] = NMResultsViewerReportFigureTools.dcaModelXY(curves(ii).points);
                col = curves(ii).color;
                if nnz(isfinite(x) & isfinite(y)) >= 2
                    opacity = 1.0; width = 2.05;
                    if ii > 1 && curves(ii).isReference
                        opacity = 0.58; width = 1.55;
                    end
                    parts{end+1} = NMResultsViewerReportFigureTools.polylineSvgWithOpacity(x,y,xLim,yLim,left,top,plotW,plotH,col,width,'',opacity); %#ok<AGROW>
                    lbl = NMResultsViewerReportFigureTools.compactLegendLabel(curves(ii).label);
                    if numel(curves) <= 2
                        lbl = ['Model (' lbl ')'];
                    end
                    legendRows(end+1,:) = {lbl, col, '', 'line'}; %#ok<AGROW>
                end
            end
            if ~isempty(curves(1).points)
                [x,ta] = NMResultsViewerReportFigureTools.pointsXY(curves(1).points,'threshold','treatAll');
                [~,tn] = NMResultsViewerReportFigureTools.pointsXY(curves(1).points,'threshold','treatNone');
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvgWithOpacity(x,ta,xLim,yLim,left,top,plotW,plotH,'#64748b',1.20,'4 3',0.82); %#ok<AGROW>
                parts{end+1} = NMResultsViewerReportFigureTools.polylineSvgWithOpacity(x,tn,xLim,yLim,left,top,plotW,plotH,'#111827',1.15,'2 3',0.82); %#ok<AGROW>
                legendRows(end+1,:) = {'Treat all','#64748b','4 3','line'}; %#ok<AGROW>
                legendRows(end+1,:) = {'Treat none','#111827','2 3','line'}; %#ok<AGROW>
            end
            legendW = 176; legendH = 12 + 18*size(legendRows,1);
            legendX = left + 18;
            legendY = max(top + 14, top + plotH - legendH - 12);
            parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(legendX,legendY,legendRows,legendW);
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = multiClassPlotSvg(plotPayload)
            % multiClassPlotSvg  Render the browser-aligned multi-class probability plot for reports.
            html = '';
            if ~plotPayload.ok, return; end

            probPts = plotPayload.points;
            predPts = plotPayload.predictedPoints;
            if isempty(predPts) && ~isempty(probPts)
                predPts = probPts;
                probPts = struct([]);
            end
            if isempty(predPts), return; end

            [xPred,yPred] = NMResultsViewerReportFigureTools.pointsXY(predPts,'x','y');
            predGood = isfinite(xPred) & isfinite(yPred);
            xPred = xPred(predGood); yPred = yPred(predGood); predPts = predPts(predGood);
            [xProb,yProb] = NMResultsViewerReportFigureTools.pointsXY(probPts,'x','y');
            probGood = isfinite(xProb) & isfinite(yProb);
            xProb = xProb(probGood); yProb = yProb(probGood); probPts = probPts(probGood);
            if isempty(xPred) && isempty(xProb), return; end

            xAll = [xPred(:); xProb(:)];
            xLim = NMResultsViewerReportFigureTools.limitField(plotPayload,'xLim',xAll);
            yLim = double(plotPayload.yLim);
            if any(~isfinite(yLim)) || yLim(1) == yLim(2), yLim = [0 1]; end

            w = 940; h = 620;
            left = 82; right = 28; top = 26; bottom = 64;
            plotW = w-left-right; plotH = h-top-bottom;
            xLabel = plotPayload.xLabel;
            yLabel = plotPayload.yLabel;
            if strcmp(xLabel,'Subject No.'), xLabel = 'Subject no.'; end

            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,'Multi-class probability plot')};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,xLim,yLim,xLabel,yLabel); %#ok<AGROW>

            patches = plotPayload.backgroundPatches;
            if ~isempty(patches)
                for ii=1:numel(patches)
                    px = double(patches(ii).x);
                    py = double(patches(ii).y);
                    pw = double(patches(ii).w);
                    ph = double(patches(ii).h);
                    if ~all(isfinite([px py pw ph])), continue; end
                    x0 = NMResultsViewerReportSvgLayout.mapX(px,xLim,left,plotW);
                    x1 = NMResultsViewerReportSvgLayout.mapX(px+pw,xLim,left,plotW);
                    y0 = NMResultsViewerReportSvgLayout.mapY(py,yLim,top,plotH);
                    y1 = NMResultsViewerReportSvgLayout.mapY(py+ph,yLim,top,plotH);
                    rx = min(x0,x1); ry = min(y0,y1); rw = abs(x1-x0); rh = abs(y1-y0);
                    col = patches(ii).color;
                    alpha = double(patches(ii).alpha);
                    if ~isfinite(alpha), alpha = 0.10; end
                    label = patches(ii).label;
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="%.3f"><title>%s</title></rect>', ...
                        rx,ry,rw,rh,NMResultsViewerReportSvgLayout.escape(col),max(0,min(1,alpha)),NMResultsViewerReportSvgLayout.escape(label)); %#ok<AGROW>
                end
            end

            zeroLine = double(plotPayload.zeroLine);
            if isfinite(zeroLine)
                zy = NMResultsViewerReportSvgLayout.mapY(zeroLine,yLim,top,plotH);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1" opacity="0.62"/>', left,zy,left+plotW,zy); %#ok<AGROW>
            end

            if ~isempty(probPts)
                maxProb = min(numel(probPts), 5000);
                probIdx = unique(round(linspace(1,numel(probPts),maxProb)));
                for jj=1:numel(probIdx)
                    ii = probIdx(jj);
                    cx = NMResultsViewerReportSvgLayout.mapX(xProb(ii),xLim,left,plotW);
                    cy = NMResultsViewerReportSvgLayout.mapY(yProb(ii),yLim,top,plotH);
                    col = probPts(ii).color;
                    dimmed = logical(probPts(ii).dimmed);
                    op = 0.50; if dimmed, op = 0.22; end
                    className = probPts(ii).className;
                    prob = double(probPts(ii).probability);
                    tip = strtrim(sprintf('%s %s', className, NMResultsViewerReportSvgLayout.formatNumber(prob)));
                    parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="3.2" fill="%s" opacity="%.2f"><title>%s</title></circle>', ...
                        cx,cy,NMResultsViewerReportSvgLayout.escape(col),op,NMResultsViewerReportSvgLayout.escape(tip)); %#ok<AGROW>
                end
            end

            maxPred = min(numel(predPts), 2500);
            predIdx = unique(round(linspace(1,numel(predPts),maxPred)));
            for jj=1:numel(predIdx)
                ii = predIdx(jj);
                cx = NMResultsViewerReportSvgLayout.mapX(xPred(ii),xLim,left,plotW);
                cy = NMResultsViewerReportSvgLayout.mapY(yPred(ii),yLim,top,plotH);
                col = predPts(ii).color;
                marker = predPts(ii).marker;
                dimmed = logical(predPts(ii).dimmed);
                op = 0.92; if dimmed, op = 0.42; end
                tip = predPts(ii).tooltip;
                if isempty(tip)
                    tip = sprintf('%s; expected: %s; predicted: %s', ...
                        predPts(ii).caseId, ...
                        predPts(ii).expected, ...
                        predPts(ii).predicted);
                end
                if strcmp(marker,'x')
                    parts{end+1} = sprintf(['<g opacity="%.2f"><title>%s</title>' ...
                        '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2.2"/>' ...
                        '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2.2"/></g>'], ...
                        op,NMResultsViewerReportSvgLayout.escape(tip),cx-6,cy-6,cx+6,cy+6,NMResultsViewerReportSvgLayout.escape(col),cx-6,cy+6,cx+6,cy-6,NMResultsViewerReportSvgLayout.escape(col)); %#ok<AGROW>
                else
                    parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="6.8" fill="%s" stroke="%s" stroke-width="1" opacity="%.2f"><title>%s</title></circle>', ...
                        cx,cy,NMResultsViewerReportSvgLayout.escape(col),NMResultsViewerReportSvgLayout.escape(col),op,NMResultsViewerReportSvgLayout.escape(tip)); %#ok<AGROW>
                end
            end

            parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#0f172a" stroke-width="1.1"/>', left,top,plotW,plotH); %#ok<AGROW>

            names = NMResultsViewerReportFigureTools.cellstrSafe(plotPayload.groupNames);
            cols = NMResultsViewerReportFigureTools.cellstrSafe(plotPayload.colors);
            selectedClass = double(plotPayload.selectedClassIndex);
            legendRows = cell(0,4);
            if selectedClass >= 1
                col = cols{selectedClass};
                legendRows(end+1,:) = {names{selectedClass}, col, '', 'point'}; %#ok<AGROW>
                legendRows(end+1,:) = {'REST', '#9ca3af', '', 'point'}; %#ok<AGROW>
            else
                nLegend = min(8,numel(names));
                for ii=1:nLegend
                    col = cols{ii};
                    legendRows(end+1,:) = {names{ii}, col, '', 'point'}; %#ok<AGROW>
                end
            end
            if ~isempty(legendRows)
                legendW = 82;
                for ii=1:size(legendRows,1), legendW = max(legendW, 46 + 5.8*numel(legendRows{ii,1})); end
                legendW = min(max(legendW,82), max(100,plotW-28));
                legendX = max(left+12, left + plotW - legendW - 30);
                legendY = top + 22;
                parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(legendX,legendY,legendRows,legendW); %#ok<AGROW>
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz reportMulticlassBrowserAligned">' strjoin(parts,'') '</div>'];
        end


        function html = featureInspectionBarsSvg(rows, opts)
            % featureInspectionBarsSvg  Render one browser-state-faithful feature bar panel.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.featureInspectionBarsSvg(rows, opts)
            %
            % Inputs:
            %   rows  Fixed-schema projected feature rows after feature-index selection,
            %         threshold-display handling, alternative labelling, and sorting.
            %   opts  Scalar renderer-options struct. ShowAllRows, MaxRows,
            %         MaxSvgHeight, MinLabelFontPt, TargetSvgHeight, BarWidth,
            %         BarEdge, colours, threshold
            %         settings, metric-field names, title, and axis label are consumed.
            %
            % Outputs:
            %   html  One .featureBarPanel wrapper containing exactly one SVG, or an
            %         empty character vector when no finite feature values are available.
            %
            % State contract:
            %   ShowAllRows is an authoritative browser content choice. When true, every
            %   supplied finite row is rendered in one continuous panel; stored page-size
            %   values and generic preview-height caps do not subdivide or truncate it.
            %   When false, MaxRows and MaxSvgHeight define the ordinary report preview.
            %
            % Geometry contract:
            %   A single shared x-axis is computed from all displayed values and finite
            %   uncertainty limits. Feature-row centres are determined solely by the
            %   displayed row count and plotting rectangle. Bar width never changes those
            %   centres and is capped to preserve at least a 1 pt gap between adjacent
            %   rows. TargetSvgHeight may enlarge the plotting rectangle but cannot shrink
            %   a taller all-row plot. The compact legend occupies the lower-left margin.
            %
            % Errors and diagnostics:
            %   Invalid or empty input returns an empty result. Non-finite feature values
            %   are excluded deterministically; scientific values are never recomputed.
            %
            % Side effects:
            %   None.
            html = '';
            if isempty(rows), return; end
            valueField = NMResultsViewerReportFigureTools.optionField(opts,'ValueField','displayValue');
            errorField = NMResultsViewerReportFigureTools.optionField(opts,'ErrorField','displaySE');
            labelField = NMResultsViewerReportFigureTools.optionField(opts,'LabelField','featureName');
            titleText = NMResultsViewerReportFigureTools.optionField(opts,'Title','Feature metric');
            xLabel = NMResultsViewerReportFigureTools.optionField(opts,'XLabel',titleText);
            requestedRows = NMResultsViewerReportFigureTools.optionScalar(opts,'MaxRows',50);
            if ~isfinite(requestedRows) || requestedRows < 1, requestedRows = min(numel(rows),50); end
            requestedRows = max(1, min(numel(rows), round(requestedRows)));
            minFont = NMResultsViewerReportFigureTools.optionScalar(opts,'MinLabelFontPt',9);
            if ~isfinite(minFont) || minFont < 7, minFont = 9; end
            maxSvgHeight = NMResultsViewerReportFigureTools.optionScalar(opts,'MaxSvgHeight',760);
            if ~isfinite(maxSvgHeight) || maxSvgHeight < 360, maxSvgHeight = 760; end
            top = 42;
            % Reserve enough vertical space for x ticks, the x-axis title, and a
            % legend placed below the axis title. This mirrors scientific plotting
            % libraries that solve plot-area and legend layout together rather than
            % allowing the legend to occlude axis text.
            bottom = NMResultsViewerReportFigureTools.featureBarBottomReserve(3, true);
            barWidthPt = NMResultsViewerReportFigureTools.optionScalar(opts,'BarWidth',12);
            if ~isfinite(barWidthPt), barWidthPt = 12; end
            barWidthPt = max(5,min(24,round(barWidthPt)));
            barEdge = NMResultsViewerReportFigureTools.optionLogical(opts,'BarEdge');
            pointToSvg = 96 / 72;
            requestedBarWidth = barWidthPt * pointToSvg;
            minimumGap = 1 * pointToSvg;
            rowPitch = max(25, ceil(1.55 * minFont));
            maxRowsByHeight = max(8, floor((maxSvgHeight - top - bottom) / rowPitch));
            showAllRows = NMResultsViewerReportFigureTools.optionLogical(opts,'ShowAllRows');
            if showAllRows
                maxRows = requestedRows;
            else
                maxRows = max(1, min(requestedRows, maxRowsByHeight));
            end
            % In static reports all plotted feature rows should be labelled. The
            % number of plotted rows is already capped above from the minimum readable
            % font size and available SVG height, so an additional top-N label cap
            % would replace real feature labels by rank numbers and make the plot
            % less interpretable.
            labelTopN = maxRows;
            rows = rows(1:maxRows);
            vals = NMResultsViewerReportFigureTools.structNumericArray(rows, valueField);
            if isempty(errorField)
                se = NaN(size(vals));
            else
                se = NMResultsViewerReportFigureTools.structNumericArray(rows, errorField);
                if numel(se) ~= numel(vals), se = NaN(size(vals)); end
            end
            labels = NMResultsViewerReportFigureTools.structTextArray(rows, labelField);
            passed = NMResultsViewerReportFigureTools.structLogicalArray(rows, 'thresholdPassed');
            if numel(passed) ~= numel(vals), passed = true(size(vals)); end
            good = isfinite(vals);
            vals = vals(good); se = se(good); labels = labels(good); passed = passed(good); rows = rows(good);
            if isempty(vals), return; end
            hiVals = vals; loVals = vals;
            seGood = isfinite(se) & se >= 0;
            hiVals(seGood) = vals(seGood) + se(seGood);
            loVals(seGood) = vals(seGood) - se(seGood);
            lo = min([0; loVals(:)]); hi = max([0; hiVals(:)]);
            if abs(hi-lo) < 1e-12, lo = lo - 0.5; hi = hi + 0.5; end
            pad = 0.06 * max(eps, hi-lo); xLim = [lo-pad hi+pad];
            n = numel(vals); w = 820; left = 270; right = 58;
            plotW = w-left-right; plotH = n*rowPitch;
            contract = NMResultsViewerReportFigureTools.optionsDisplayContract(opts);
            subColor = NMResultsViewerReportFigureTools.optionField(opts,'SubthresholdColor','#cbd5e1');
            hasBelowThreshold = any(~passed(:));
            if strcmp(contract.polarity.kind,'signed')
                legendRows = {'Positive value',contract.colorStops(end).color,'','swatch';'Negative value',contract.colorStops(1).color,'','swatch'};
            else
                legendRows = {'Metric magnitude',contract.colorStops(end).color,'','swatch'};
            end
            if hasBelowThreshold
                legendRows(end+1,:) = {'Below metric threshold',subColor,'','swatch'};
            end
            thresholdLegendRows = NMResultsViewerReportFigureTools.thresholdLegendRows(opts);
            if ~isempty(thresholdLegendRows)
                legendRows = [legendRows; thresholdLegendRows];
            end
            bottom = NMResultsViewerReportFigureTools.featureBarBottomReserve(size(legendRows,1), requestedRows > n);
            h = top + plotH + bottom;
            % Report-layout contract: a metric bar plot shares one grid row
            % with the histogram-plus-statistics stack. When the panel renderer
            % supplies TargetSvgHeight, preserve the total panel height and assign
            % all reclaimed legend space to the plotting rectangle. Row centres
            % expand with that rectangle; requested bar width remains independently
            % capped by the resulting centre-to-centre pitch.
            targetSvgHeight = NMResultsViewerReportFigureTools.optionScalar(opts,'TargetSvgHeight',NaN);
            if isfinite(targetSvgHeight) && targetSvgHeight > h
                plotH = plotH + (targetSvgHeight - h);
                h = targetSvgHeight;
            end
            zeroX = NMResultsViewerReportSvgLayout.mapX(0, xLim, left, plotW);
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,titleText)};
            parts{end+1} = NMResultsViewerReportFigureTools.barXAxisSvg(left,top,plotW,plotH,xLim,xLabel); %#ok<AGROW>
            parts{end+1} = sprintf('<text x="%.1f" y="20" text-anchor="middle" font-size="13" font-weight="700" fill="#0f172a">%s</text>', left+plotW/2, NMResultsViewerReportSvgLayout.escape(titleText)); %#ok<AGROW>
            parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1.1"/>', zeroX, top, zeroX, top+plotH); %#ok<AGROW>
            effectiveRowPitch = plotH / max(1,n);
            barWidth = max(1,min(requestedBarWidth,effectiveRowPitch-minimumGap));
            for ii=1:n
                cy = top + (ii-0.5)*effectiveRowPitch;
                y = cy - barWidth/2;
                xVal = NMResultsViewerReportSvgLayout.mapX(vals(ii), xLim, left, plotW);
                x0 = min(zeroX, xVal); bw = max(1.2, abs(xVal-zeroX));
                [fill, stroke, errColor] = NMResultsViewerReportFigureTools.featureMetricBarColor(vals(ii), passed(ii), opts);
                if barEdge
                    stroke = NMResultsViewerReportFigureTools.mixHex(fill, '#000000', 0.28);
                    strokeWidth = 1;
                else
                    stroke = 'none';
                    strokeWidth = 0;
                end
                txtColor = '#0f172a'; if ~passed(ii) || ii > labelTopN, txtColor = '#94a3b8'; end
                tooltip = NMResultsViewerReportFigureTools.featureInspectionTooltipText(rows(ii), valueField, errorField);
                labelTxt = NMResultsViewerReportFigureTools.shortText(labels{ii}, 34);
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="%.1f" fill="%s">%s</text>', left-8, cy+3, minFont, txtColor, NMResultsViewerReportSvgLayout.escape(labelTxt)); %#ok<AGROW>
                parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="2" fill="%s" stroke="%s" stroke-width="%.1f" vector-effect="non-scaling-stroke"><title>%s</title></rect>', x0, y, bw, barWidth, fill, stroke, strokeWidth, NMResultsViewerReportSvgLayout.escape(tooltip)); %#ok<AGROW>
                if isfinite(se(ii)) && se(ii) >= 0
                    xe1 = NMResultsViewerReportSvgLayout.mapX(vals(ii)-se(ii), xLim, left, plotW);
                    xe2 = NMResultsViewerReportSvgLayout.mapX(vals(ii)+se(ii), xLim, left, plotW);
                    parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.1"><title>%s</title></line><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.1"/><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.1"/>', xe1, cy, xe2, cy, errColor, NMResultsViewerReportSvgLayout.escape(tooltip), xe1, cy-3, xe1, cy+3, errColor, xe2, cy-3, xe2, cy+3, errColor); %#ok<AGROW>
                end
            end
            parts{end+1} = NMResultsViewerReportFigureTools.featureMetricThresholdLinesSvg(opts, xLim, left, top, plotW, plotH, false); %#ok<AGROW>
            legendY = NMResultsViewerReportFigureTools.legendBelowXAxisY(top, plotH);
            parts{end+1} = NMResultsViewerReportFigureTools.compactInlineLegendSvg(14,legendY,legendRows,w-28); %#ok<AGROW>
            parts{end+1} = '</svg>';
            html = ['<div class="viz featureBarPanel">' strjoin(parts,'') '</div>'];
        end



        function html = featureInspectionMetricPanelSvg(barRows, distributionRows, opts)
            % featureInspectionMetricPanelSvg  Compose one feature metric report panel.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.featureInspectionMetricPanelSvg(barRows, distributionRows, opts)
            %
            % Inputs:
            %   barRows           Projected rows selected for the feature-bar figure.
            %   distributionRows  Complete projected rows used for the histogram and
            %                     distribution summary.
            %   opts              Scalar normalized renderer-options struct.
            %
            % Outputs:
            %   html  Two-column report layout containing one bar SVG and one top-aligned
            %         histogram-plus-distribution-summary stack.
            %
            % Layout contract:
            %   MetricPanelBarSvgHeight/TargetSvgHeight defines the minimum ordinary bar
            %   height required to align with the companion column. A ShowAllRows bar may
            %   exceed that minimum and elongate the shared grid row; it is never split,
            %   shrunk, or duplicated. The companion column remains top-aligned.
            %
            % Errors and diagnostics:
            %   Empty renderers produce empty child content without recomputing metrics.
            %
            % Side effects:
            %   None.

            panelTitle = NMResultsViewerReportFigureTools.optionField(opts,'Title','Feature metric');
            barOpts = opts;
            barOpts.Title = 'Feature bar plot';
            histOpts = opts;
            histOpts.Title = 'Distribution';
            histOpts.XLabel = panelTitle;
            histOpts.SvgHeight = 330;
            % The default viewBox height is calibrated to the 1.25:0.75 report
            % column ratio and the fixed eight-row distribution summary. CSS then
            % stretches the outer grid items to the same row height without
            % distorting scientific coordinates or text.
            targetBarHeight = NMResultsViewerReportFigureTools.optionScalar(opts,'MetricPanelBarSvgHeight',520);
            if ~isfinite(targetBarHeight) || targetBarHeight < 420, targetBarHeight = 520; end
            barOpts.TargetSvgHeight = targetBarHeight;
            barHtml = NMResultsViewerReportFigureTools.featureInspectionBarsSvg(barRows, barOpts);
            histHtml = NMResultsViewerReportFigureTools.featureInspectionHistogramSvg(distributionRows, 'displayValue', histOpts);
            statsHtml = NMResultsViewerReportFigureTools.featureInspectionDistributionStatsHtml(distributionRows, 'displayValue');
            html = ['<div class="featureMetricPanelGrid">' barHtml '<div class="featureMetricPanelAside">' histHtml statsHtml '</div></div>'];
        end

        function html = featureInspectionHistogramSvg(rows, fieldName, opts)
            % featureInspectionHistogramSvg  Render a compact distribution histogram.
            %
            % html = NMResultsViewerReportFigureTools.featureInspectionHistogramSvg(rows, fieldName, opts)
            % creates a deterministic static histogram from one numeric field of the
            % normalized Model feature inspection payload. The method is read-only and
            % is intended for report/export use; browser interactivity is implemented
            % separately by the shared D3 toolbox on the same payload contract.
            html = '';
            if isempty(rows), return; end
            vals0 = NMResultsViewerReportFigureTools.structNumericArray(rows, fieldName);
            finite0 = isfinite(vals0);
            vals = vals0(finite0);
            if isempty(vals), return; end
            contract = NMResultsViewerReportFigureTools.optionsDisplayContract(opts);
            pass0 = NMResultsViewerDisplaySemanticsTools.eligibilityMask( ...
                vals0,contract,true(size(vals0)));
            pass = pass0(finite0);
            titleText = NMResultsViewerReportFigureTools.optionField(opts,'Title','Feature distribution');
            xLabel = NMResultsViewerReportFigureTools.optionField(opts,'XLabel',fieldName);
            lo = min(vals); hi = max(vals);
            if abs(hi-lo) < 1e-12, lo = lo - 0.5; hi = hi + 0.5; end
            nBins = NMResultsViewerReportFigureTools.optionScalar(opts,'HistogramBins',NaN);
            if ~isfinite(nBins), nBins = min(30, max(8, round(sqrt(numel(vals))))); end
            nBins = max(3, min(80, round(nBins)));
            edges = linspace(lo, hi, nBins+1);
            counts = histcounts(vals, edges);
            maxC = max(1, max(counts));
            w = 620; h = NMResultsViewerReportFigureTools.optionScalar(opts,'SvgHeight',330);
            if ~isfinite(h) || h < 240, h = 330; end
            h = round(h);
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,[lo hi],[0 maxC],xLabel,'Count',titleText,struct());
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,titleText), NMResultsViewerReportSvgLayout.axesSvg(layout)};
            for bb=1:nBins
                if bb < nBins
                    inBin = vals >= edges(bb) & vals < edges(bb+1);
                else
                    inBin = vals >= edges(bb) & vals <= edges(bb+1);
                end
                totalN = nnz(inBin);
                if totalN == 0, continue; end
                passN = nnz(pass(inBin));
                failN = totalN - passN;
                x1 = NMResultsViewerReportSvgLayout.mapX(edges(bb), [lo hi], layout.left, layout.plotW);
                x2 = NMResultsViewerReportSvgLayout.mapX(edges(bb+1), [lo hi], layout.left, layout.plotW);
                barW = max(1,x2-x1-1);
                baseY = layout.top + layout.plotH;
                if failN > 0
                    failTop = NMResultsViewerReportSvgLayout.mapY(failN, [0 maxC], layout.top, layout.plotH);
                    failH = baseY - failTop;
                    subColor = NMResultsViewerReportFigureTools.optionField(opts,'SubthresholdColor','#cbd5e1');
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.72" stroke="none"><title>%s to %s: %d subthreshold feature(s)</title></rect>', x1, failTop, barW, max(0,failH), subColor, NMResultsViewerReportSvgLayout.formatNumber(edges(bb)), NMResultsViewerReportSvgLayout.formatNumber(edges(bb+1)), failN); %#ok<AGROW>
                end
                if passN > 0
                    passTop = NMResultsViewerReportSvgLayout.mapY(totalN, [0 maxC], layout.top, layout.plotH);
                    passBottom = NMResultsViewerReportSvgLayout.mapY(failN, [0 maxC], layout.top, layout.plotH);
                    passH = passBottom - passTop;
                    binCenter = 0.5 .* (edges(bb) + edges(bb+1));
                    [histFill, ~, ~] = NMResultsViewerReportFigureTools.featureMetricBarColor(binCenter, true, opts);
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" opacity="0.82" stroke="none"><title>%s to %s: %d feature(s)</title></rect>', x1, passTop, barW, max(0,passH), histFill, NMResultsViewerReportSvgLayout.formatNumber(edges(bb)), NMResultsViewerReportSvgLayout.formatNumber(edges(bb+1)), passN); %#ok<AGROW>
                end
            end
            parts{end+1} = NMResultsViewerReportFigureTools.featureMetricThresholdLinesSvg(opts, [lo hi], layout.left, layout.top, layout.plotW, layout.plotH, false); %#ok<AGROW>
            thresholdLegendRows = NMResultsViewerReportFigureTools.thresholdLegendRows(opts);
            if ~isempty(thresholdLegendRows)
                parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(layout.left + layout.plotW - 220, layout.top + 8, thresholdLegendRows, 212); %#ok<AGROW>
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz featureMetricHistogram">' strjoin(parts,'') '</div>'];
        end

        function html = featureInspectionDistributionStatsHtml(rows, fieldName)
            % featureInspectionDistributionStatsHtml  Render compact distribution metrics below a histogram.
            html = '';
            if isempty(rows), return; end
            vals = NMResultsViewerReportFigureTools.structNumericArray(rows, fieldName);
            vals = vals(isfinite(vals));
            if isempty(vals), return; end
            valsSorted = sort(vals(:));
            q = [NMResultsViewerReportFigureTools.percentileValue(valsSorted,25) NMResultsViewerReportFigureTools.percentileValue(valsSorted,75)];
            labels = {'N'; 'Min'; 'Q1'; 'Median'; 'Q3'; 'Max'; 'Mean'; 'SD'};
            values = {sprintf('%d', numel(vals)); NMResultsViewerReportSvgLayout.formatNumber(min(vals)); NMResultsViewerReportSvgLayout.formatNumber(q(1)); NMResultsViewerReportSvgLayout.formatNumber(median(vals)); NMResultsViewerReportSvgLayout.formatNumber(q(2)); NMResultsViewerReportSvgLayout.formatNumber(max(vals)); NMResultsViewerReportSvgLayout.formatNumber(mean(vals)); NMResultsViewerReportSvgLayout.formatNumber(std(vals))};
            tr = cell(1,numel(labels)+1);
            tr{1} = '<tr><th>Metric</th><th>Value</th></tr>';
            for ii = 1:numel(labels)
                tr{ii+1} = sprintf('<tr><td>%s</td><td>%s</td></tr>', NMResultsViewerReportSvgLayout.escape(labels{ii}), NMResultsViewerReportSvgLayout.escape(values{ii}));
            end
            html = ['<div class="featureMetricDistributionStats"><div class="small">Distribution metrics</div><table>' strjoin(tr,'') '</table></div>'];
        end


        function html = featureInspectionRelationshipSvg(rows, opts)
            % featureInspectionRelationshipSvg  Render a generic relationship between two feature-level metrics.
            %
            % html = NMResultsViewerReportFigureTools.featureInspectionRelationshipSvg(rows, opts)
            % renders one feature per point using generic xValue/yValue rows. Any pair of feature-level metrics
            % can be supplied through the same payload contract. Threshold state is
            % recomputed from the metric descriptors at render time so that points
            % below either metric threshold are not lost when table-side state fields
            % are missing or stale. Legends are placed below the x-axis title, matching
            % the feature-bar layout and avoiding marker occlusion inside the plot.
            arguments
                rows
                opts.XMetricSpec = struct()
                opts.YMetricSpec = struct()
                opts.Title = 'Feature metric relationship'
                opts.XLabel = 'X metric'
                opts.YLabel = 'Y metric'
                opts.PlotTitle = 'Relationship plot'
            end
            html = '';
            if isempty(rows), return; end
            x = NMResultsViewerReportFigureTools.structNumericArray(rows, 'xValue');
            y = NMResultsViewerReportFigureTools.structNumericArray(rows, 'yValue');
            xSpec = opts.XMetricSpec;
            ySpec = opts.YMetricSpec;
            xContract = NMResultsViewerReportFigureTools.metricDisplayContract(xSpec);
            yContract = NMResultsViewerReportFigureTools.metricDisplayContract(ySpec);
            xPass = NMResultsViewerDisplaySemanticsTools.eligibilityMask(x,xContract,true(size(x)));
            yPass = NMResultsViewerDisplaySemanticsTools.eligibilityMask(y,yContract,true(size(y)));
            bothPass = xPass & yPass;
            good = isfinite(x) & isfinite(y); x = x(good); y = y(good); xPass = xPass(good); yPass = yPass(good); bothPass = bothPass(good); rows = rows(good);
            if numel(x) < 2, return; end
            titleText = opts.Title; %#ok<NASGU>
            xLabel = opts.XLabel;
            yLabel = opts.YLabel;
            xLim = NMResultsViewerReportFigureTools.paddedLim(x, true);
            yLim = NMResultsViewerReportFigureTools.paddedLim(y, false);
            legendRows = {'Positive x-metric value',xContract.colorStops(end).color,'','circle'};
            if strcmp(xContract.polarity.kind,'signed')
                legendRows(end+1,:) = {'Negative x-metric value',xContract.colorStops(1).color,'','circle'};
            end
            if any(~bothPass(:))
                legendRows(end+1,:) = {'Subthreshold','#cbd5e1','','circle'};
            end
            xThresholdRows = NMResultsViewerReportFigureTools.thresholdLegendRows(struct('DisplayContract',xSpec.displayContract,'ThresholdLabel',xSpec.thresholdLabel));
            yThresholdRows = NMResultsViewerReportFigureTools.thresholdLegendRows(struct('DisplayContract',ySpec.displayContract,'ThresholdLabel',ySpec.thresholdLabel));
            legendRows = NMResultsViewerReportFigureTools.uniqueLegendRows([legendRows; xThresholdRows; yThresholdRows]);
            legendH = 12 + 18 * size(legendRows,1);
            w = 700;
            h = max(470, 440 + legendH);
            layoutOpts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            layoutOpts.MinBottom = 78 + legendH;
            layoutOpts.MinRight = 24;
            layoutOpts.MinLeft = 72;
            layoutOpts.MaxXTicks = 12;
            layoutOpts.MaxYTicks = 9;
            plotTitle = opts.PlotTitle;
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,xLim,yLim,xLabel,yLabel,plotTitle,layoutOpts);
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,plotTitle), NMResultsViewerReportSvgLayout.axesSvg(layout)};
            drawOrder = [find(~bothPass(:)); find(bothPass(:))];
            pointColors = NMResultsViewerDisplaySemanticsTools.sampleColorHexArray(x,xContract,'#cbd5e1');
            for kk=1:numel(drawOrder)
                ii = drawOrder(kk);
                if ~bothPass(ii)
                    col = '#cbd5e1'; op = 0.66;
                else
                    col = pointColors{ii}; op = 0.88;
                end
                tooltip = NMResultsViewerReportFigureTools.relationshipTooltipText(rows(ii), xLabel, yLabel);
                parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="4.1" fill="%s" opacity="%.2f" stroke="#fff" stroke-width="0.7"><title>%s</title></circle>', NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,layout.left,layout.plotW), NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,layout.top,layout.plotH), col, op, NMResultsViewerReportSvgLayout.escape(tooltip)); %#ok<AGROW>
            end
            parts{end+1} = NMResultsViewerReportFigureTools.featureMetricVerticalThresholdLinesSvg(xSpec, xLim, layout.left, layout.top, layout.plotW, layout.plotH); %#ok<AGROW>
            parts{end+1} = NMResultsViewerReportFigureTools.featureMetricHorizontalThresholdLinesSvg(ySpec, yLim, layout.left, layout.top, layout.plotW, layout.plotH); %#ok<AGROW>
            legendW = min(max(280, 8 + 5.8 * max(cellfun(@numel, legendRows(:,1))) + 46), max(280, layout.plotW));
            legendY = min(layout.xTitleY + 18, h - legendH - 10);
            parts{end+1} = NMResultsViewerReportFigureTools.reportLegendSvg(layout.left,legendY,legendRows,legendW); %#ok<AGROW>
            parts{end+1} = '</svg>';
            html = ['<div class="viz featureMetricRelationship">' strjoin(parts,'') '</div>'];
        end


        function html = componentShareSvg(rows, opts)
            % componentShareSvg  Render normalized component or modality bars with optional intervals.
            %
            % Value annotations are positioned beyond the outermost bar/interval
            % endpoint and the numeric axis reserves explicit annotation space. This
            % mirrors the browser fusion-panel contract and prevents the largest value
            % or a 95% interval from colliding with its label in static reports.
            arguments
                rows
                opts.ValueField = 'meanShare'
                opts.LabelField = 'componentLabel'
                opts.XLabel
                opts.YAxisLabel = 'Component'
                opts.Title = 'Component contribution'
                opts.CategoricalY = false
                opts.BaseColor = '#dc2626'
                opts.MaxRows = 24
                opts.LoField = ''
                opts.HiField = ''
                opts.IntervalLabel = '95% interval'
                opts.SelectedComponentIndex = NaN
            end
            html = '';
            if isempty(rows), return; end
            valueField = opts.ValueField;
            labelField = opts.LabelField;
            xLabel = opts.XLabel;
            yLabel = opts.YAxisLabel;
            titleText = opts.Title;
            categoricalY = opts.CategoricalY;
            baseColor = opts.BaseColor;
            if isempty(regexp(baseColor,'^#[0-9A-Fa-f]{6}$','once')), baseColor='#dc2626'; end
            maxRows = opts.MaxRows;
            if ~isfinite(maxRows) || maxRows < 1, maxRows = 24; end
            rows = rows(1:min(numel(rows),max(1,round(maxRows))));
            vals = NMResultsViewerReportFigureTools.structNumericArray(rows,valueField);
            labels = NMResultsViewerReportFigureTools.structTextArray(rows,labelField);
            loField = opts.LoField;
            hiField = opts.HiField;
            ciLo = NaN(numel(rows),1); ciHi = NaN(numel(rows),1);
            if ~isempty(loField), ciLo = NMResultsViewerReportFigureTools.structNumericArray(rows,loField); end
            if ~isempty(hiField), ciHi = NMResultsViewerReportFigureTools.structNumericArray(rows,hiField); end
            good = isfinite(vals); vals=vals(good); labels=labels(good); rows=rows(good); ciLo=ciLo(good); ciHi=ciHi(good);
            if isempty(vals), return; end
            outerLo=vals(:); outerHi=vals(:);
            bothCi=isfinite(ciLo)&isfinite(ciHi);
            outerLo(bothCi)=min(outerLo(bothCi),ciLo(bothCi));
            outerHi(bothCi)=max(outerHi(bothCi),ciHi(bothCi));
            dataLo=min([0;outerLo]); dataHi=max([0;outerHi]);
            if abs(dataHi-dataLo)<1e-12
                half=max(0.5,0.25*max(1,abs(dataHi))); dataLo=dataLo-half; dataHi=dataHi+half;
            end
            span=max(eps,dataHi-dataLo);
            labelPad=0.14*span;
            xLim=[dataLo dataHi];
            if dataLo<0, xLim(1)=dataLo-labelPad; else, xLim(1)=0; end
            if dataHi>0, xLim(2)=dataHi+labelPad; else, xLim(2)=0; end
            if abs(xLim(2)-xLim(1))<1e-12, xLim=xLim+[-0.5 0.5]; end
            w=760; rowH=27; n=numel(vals); left=220; top=38; right=28; bottom=42; plotW=w-left-right; plotH=n*rowH;
            if categoricalY, h=max(140,top+plotH+bottom); else, h=max(220,76+n*rowH); end
            zeroX=NMResultsViewerReportSvgLayout.mapX(0,xLim,left,plotW);
            parts={NMResultsViewerReportFigureTools.svgOpen(w,h,titleText)};
            if categoricalY
                parts{end+1}=NMResultsViewerReportFigureTools.barXAxisSvg(left,top,plotW,plotH,xLim,xLabel); %#ok<AGROW>
            else
                parts{end+1}=NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,xLim,[0 n+1],xLabel,yLabel); %#ok<AGROW>
            end
            parts{end+1}=sprintf('<text x="%.1f" y="20" text-anchor="middle" font-size="13" font-weight="700" fill="#0f172a">%s</text>', left+plotW/2, NMResultsViewerReportSvgLayout.escape(titleText)); %#ok<AGROW>
            parts{end+1}=sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#0f172a" stroke-width="1"/>', zeroX, top, zeroX, top+plotH); %#ok<AGROW>
            selectedIndex = opts.SelectedComponentIndex;
            for ii=1:n
                y=top+(ii-0.72)*rowH; cy=y+11; xVal=NMResultsViewerReportSvgLayout.mapX(vals(ii),xLim,left,plotW); x0=min(zeroX,xVal); bw=max(1.2,abs(xVal-zeroX));
                col=baseColor; if vals(ii)<0, col='#2563eb'; end
                if categoricalY
                    isSelected = false;
                    isInactive = false;
                else
                    componentIndex = double(rows(ii).componentIndex);
                    isSelected = isfinite(selectedIndex) && isfinite(componentIndex) && selectedIndex == componentIndex;
                    isInactive = ~rows(ii).kept || ~rows(ii).thresholdPassed;
                end
                if isInactive, col='#cbd5e1'; elseif isSelected, col='#059669'; end
                labelWeight='400'; if isSelected, labelWeight='700'; end
                ciText=''; ciX1=NaN; ciX2=NaN;
                if bothCi(ii)
                    ciX1=NMResultsViewerReportSvgLayout.mapX(ciLo(ii),xLim,left,plotW); ciX2=NMResultsViewerReportSvgLayout.mapX(ciHi(ii),xLim,left,plotW);
                    ciText=sprintf('; %s %s to %s',opts.IntervalLabel,NMResultsViewerReportSvgLayout.formatNumber(ciLo(ii)),NMResultsViewerReportSvgLayout.formatNumber(ciHi(ii)));
                end
                endpoint=vals(ii); if vals(ii)>=0, endpoint=max(endpoint,outerHi(ii)); else, endpoint=min(endpoint,outerLo(ii)); end
                valueX=NMResultsViewerReportSvgLayout.mapX(endpoint,xLim,left,plotW)+(vals(ii)>=0)*7-(vals(ii)<0)*7;
                anchor='start'; if vals(ii)<0, anchor='end'; end
                valueX=max(left+4,min(left+plotW-4,valueX));
                valueText=NMResultsViewerReportSvgLayout.formatNumber(vals(ii));
                tooltip=[labels{ii} ': ' valueText ciText];
                parts{end+1}=sprintf('<text class="reportFusionBarLabel" x="%.1f" y="%.1f" text-anchor="end" font-size="9" font-weight="%s" fill="#0f172a">%s</text><rect class="reportFusionBar" x="%.1f" y="%.1f" width="%.1f" height="14" rx="2" fill="%s"><title>%s</title></rect>', ...
                    left-8,cy+1,labelWeight,NMResultsViewerReportSvgLayout.escape(NMResultsViewerReportFigureTools.shortText(labels{ii},30)),x0,y,bw,col,NMResultsViewerReportSvgLayout.escape(tooltip)); %#ok<AGROW>
                if bothCi(ii)
                    parts{end+1}=sprintf('<line class="reportFusionCi" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#475569" stroke-width="1.2"/><line class="reportFusionCi" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#475569"/><line class="reportFusionCi" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#475569"/>',ciX1,cy,ciX2,cy,ciX1,cy-4,ciX1,cy+4,ciX2,cy-4,ciX2,cy+4); %#ok<AGROW>
                end
                parts{end+1}=sprintf('<text class="reportFusionBarValue" x="%.1f" y="%.1f" text-anchor="%s" font-size="9" fill="#0f172a">%s</text>', ...
                    valueX,cy+1,anchor,NMResultsViewerReportSvgLayout.escape(valueText)); %#ok<AGROW>
            end
            parts{end+1}='</svg>';
            html=['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function html = continuousMatrixHtml(values, rowLabels, columnLabels, opts)
            % Continuous print-matrix authority shared by subject Dx and cluster signatures.
            % HTML rows flow at physical page boundaries; column headings repeat.
            nRows=size(values,1);nCols=size(values,2);
            finiteValues=values(isfinite(values));
            span=max([abs(finiteValues(:));eps]);
            signed=opts.Signed;
            if signed
                lowColor=NMResultsViewerReportFigureTools.divergingHex(-span,span);
                zeroColor=NMResultsViewerReportFigureTools.divergingHex(0,span);
                highColor=NMResultsViewerReportFigureTools.divergingHex(span,span);
                lowLabel=['-' NMResultsViewerReportSvgLayout.formatNumber(span)];
            else
                lowColor='#ffffff';zeroColor='#ffffff';highColor='#2563eb';lowLabel='0';
            end
            classes='reportMatrixFigure';
            if opts.DisplayValues,classes=[classes ' reportClusterMatrix'];end
            labelChars=max([numel(opts.RowHeading);cellfun('length',rowLabels(:))]);
            labelWidth=max(51,min(180,ceil(5*labelChars)));
            if opts.DisplayValues,labelWidth=max(105,labelWidth);end
            parts={sprintf(['<div class="%s"><div class="reportMatrixKey">%s: ' ...
                '<span class="reportMatrixKeySwatch" style="background:%s"></span>%s' ...
                '<span class="reportMatrixKeySwatch" style="background:%s"></span>0' ...
                '<span class="reportMatrixKeySwatch" style="background:%s"></span>%s' ...
                '<span class="reportMatrixKeySwatch" style="background:#cbd5e1"></span>NaN' ...
                '<span class="reportMatrixColumnNote">Columns: %s</span></div>'], ...
                classes,NMResultsViewerReportSvgLayout.escape(opts.ValueLabel), ...
                lowColor,lowLabel,zeroColor,highColor, ...
                NMResultsViewerReportSvgLayout.formatNumber(span), ...
                NMResultsViewerReportSvgLayout.escape(opts.ColumnHeading))};
            parts{end+1}=sprintf('<table class="reportMatrixTable"><colgroup><col style="width:%dpx"></colgroup><thead><tr><th class="reportMatrixRowHeader" scope="col">%s</th>', ...
                labelWidth,NMResultsViewerReportSvgLayout.escape(opts.RowHeading));
            for cc=1:nCols
                parts{end+1}=sprintf('<th class="reportMatrixColumnHeader" scope="col" title="%s">%s</th>', ...
                    NMResultsViewerReportSvgLayout.escape(columnLabels{cc}), ...
                    NMResultsViewerReportSvgLayout.escape(strrep(strrep(columnLabels{cc},'Component ',''),'Cluster ',''))); %#ok<AGROW>
            end
            parts{end+1}='</tr></thead><tbody>';
            for rr=1:nRows
                rowLabel=NMResultsViewerReportSvgLayout.escape(rowLabels{rr});
                highlight='';
                if rr==opts.HighlightRow,highlight=' style="border-left:3px solid #059669;color:#047857;font-weight:700"';end
                parts{end+1}=['<tr><th class="reportMatrixRowHeader" scope="row"' highlight '>' rowLabel '</th>']; %#ok<AGROW>
                for cc=1:nCols
                    v=values(rr,cc);
                    if isfinite(v)
                        if signed
                            color=NMResultsViewerReportFigureTools.divergingHex(v,span);
                        else
                            color=NMResultsViewerReportFigureTools.mixHex('#ffffff','#2563eb',min(1,max(0,v/span)));
                        end
                    else
                        color='#cbd5e1';
                    end
                    label=NMResultsViewerReportSvgLayout.formatNumber(v);
                    if opts.DisplayValues && isfinite(v),cellText=label;else,cellText='';end
                    parts{end+1}=sprintf('<td style="background:%s" title="%s / %s: %s">%s</td>', ...
                        color,rowLabel,NMResultsViewerReportSvgLayout.escape(columnLabels{cc}), ...
                        label,cellText); %#ok<AGROW>
                end
                parts{end+1}='</tr>'; %#ok<AGROW>
            end
            parts{end+1}='</tbody></table></div>';
            html=strjoin(parts,'');
        end

        function html = sequenceDiagnosticsSvg(rows)
            % Render already-normalized examination-stage means and SDs, one metric per figure.
            ids=unique({rows.metricId},'stable');
            parts=cell(1,numel(ids));
            for ii=1:numel(ids)
                data=rows(strcmp({rows.metricId},ids{ii}));
                x=double([data.stage]);y=double([data.mean]);sd=abs(double([data.sd]));
                good=isfinite(y);
                if ~any(good),parts{ii}='';continue;end
                lo=min(y(good));hi=max(y(good));
                band=good & isfinite(sd);
                if any(band),lo=min([lo min(y(band)-sd(band))]);hi=max([hi max(y(band)+sd(band))]);end
                pad=max(0.1,0.1*(hi-lo));yLim=[lo-pad hi+pad];
                xLim=[1 max(2,numel(x))];
                w=760;h=310;left=88;top=38;plotW=610;plotH=205;
                txt=NMResultsViewerReportSvgLayout.escape(data(1).metricLabel);
                svg={NMResultsViewerReportFigureTools.svgOpen(w,h,data(1).metricLabel), ...
                    sprintf('<text x="%d" y="20" font-size="14" font-weight="700">%s (mean +/- SD)</text>',left,txt), ...
                    NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,xLim,yLim, ...
                    'Examination stage',data(1).unit)};
                if any(band) && nnz(band)>1
                    indices=find(band);xx=x(indices);
                    upper=y(indices)+sd(indices);lower=y(indices)-sd(indices);
                    xp=arrayfun(@(v)NMResultsViewerReportSvgLayout.mapX(v,xLim,left,plotW),[xx fliplr(xx)]);
                    yp=arrayfun(@(v)NMResultsViewerReportSvgLayout.mapY(v,yLim,top,plotH),[upper fliplr(lower)]);
                    coords=sprintf('%.2f,%.2f ',[xp;yp]);
                    svg{end+1}=sprintf('<polygon points="%s" fill="#93c5fd" fill-opacity="0.32"/>',coords);
                end
                svg{end+1}=NMResultsViewerReportFigureTools.polylineSvg(x(good),y(good),xLim,yLim,left,top,plotW,plotH,'#2563eb',2.5,'');
                svg{end+1}=NMResultsViewerReportFigureTools.circleSeriesSvg(x(good),y(good),xLim,yLim,left,top,plotW,plotH,'#2563eb',4,1);
                svg{end+1}='</svg>';
                parts{ii}=['<div class="viz">' strjoin(svg,'') '</div>'];
            end
            html=strjoin(parts,'');
        end

        function html = optimizationCurveSvg(metricValues, titleText, selectedPoints)
            % optimizationCurveSvg  Render full-index, gap-aware optimization series.
            %
            % Unvisited parameter combinations are represented by non-finite values
            % and are hard topological breaks. Lines and uncertainty bands therefore
            % connect only consecutive original model indices with finite values.
            % Every visited combination is rendered as a symbol, including isolated
            % points without visited neighbours. selectedPoints is materialized by
            % NMResultsViewerReportTools from the same long-format rows and is used
            % only to identify the highlighted authoritative point.
            html = '';
            % nm2-allow: report figure API permits omitted selected-point overlay presentation state
            if nargin < 3, selectedPoints = struct([]); end
            if isempty(metricValues), return; end
            labels = NMResultsViewerReportFigureTools.structTextArray(metricValues, 'seriesLabel');
            for ii=1:numel(labels), if isempty(labels{ii}), labels{ii} = 'Series'; end, end
            uLabels = unique(labels, 'stable');
            if isempty(uLabels), return; end
            xAll = NMResultsViewerReportFigureTools.structNumericArray(metricValues, 'modelIndex');
            yAll = NMResultsViewerReportFigureTools.structNumericArray(metricValues, 'value');
            semAll = NMResultsViewerReportFigureTools.structNumericArray(metricValues, 'sem');
            finiteX = isfinite(xAll);
            goodAll = finiteX & isfinite(yAll);
            if ~any(goodAll), return; end
            xMax = max(xAll(finiteX));
            if ~isfinite(xMax) || xMax <= 1, xMax = max(1, numel(unique(xAll(goodAll)))); end
            yBand = yAll(goodAll);
            finiteSem = isfinite(semAll) & semAll > 0 & goodAll;
            if any(finiteSem)
                yBand = [yBand; yAll(finiteSem)-semAll(finiteSem); yAll(finiteSem)+semAll(finiteSem)];
            end
            yLim = [min(yBand) max(yBand)];
            if abs(yLim(2)-yLim(1)) < 1e-12, yLim = yLim + [-0.5 0.5]; end
            pad = 0.06 * max(eps, yLim(2)-yLim(1));
            yLim = yLim + [-pad pad];
            w = 760; h = 260; left = 58; right = 150; top = 28; bottom = 48;
            plotW = w-left-right; plotH = h-top-bottom;
            colors = {'#2563eb','#c2410c','#16a34a','#9333ea'};
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,titleText)};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,[1 xMax],yLim,'Model / parameter-combination index','Metric value');
            legendLabels = cell(1,0); legendColors = cell(1,0);
            direction = metricValues(1).directionSign;
            selectedLabels = NMResultsViewerReportFigureTools.structTextArray(selectedPoints,'seriesLabel');
            selectedModels = NMResultsViewerReportFigureTools.structNumericArray(selectedPoints,'modelIndex');
            selectedValues = NMResultsViewerReportFigureTools.structNumericArray(selectedPoints,'value');
            lineWidth = NMResultsViewerReportFigureTools.optimizationLineWidth(xMax, plotW);
            markerRadius = NMResultsViewerReportFigureTools.optimizationMarkerRadius(xMax);
            for ss = 1:numel(uLabels)
                idx = find(strcmp(labels, uLabels{ss}));
                x = xAll(idx); y = yAll(idx); sem = semAll(idx);
                validX = isfinite(x);
                x = x(validX); y = y(validX); sem = sem(validX);
                if isempty(x) || ~any(isfinite(y)), continue; end
                [x,ord] = sort(x); y = y(ord); sem = sem(ord);
                col = colors{min(ss,numel(colors))};

                semValid = isfinite(y) & isfinite(sem) & sem > 0;
                bandRuns = NMResultsViewerReportFigureTools.optimizationContiguousRunIndices(x, semValid);
                for rr = 1:numel(bandRuns)
                    run = bandRuns{rr};
                    if numel(run) < 2, continue; end
                    xr = x(run); yr = y(run); sr = abs(sem(run));
                    xb = [xr; flipud(xr)];
                    yb = [yr+sr; flipud(yr-sr)];
                    pts = NMResultsViewerReportFigureTools.pointList(xb, yb, [1 xMax], yLim, left, top, plotW, plotH);
                    parts{end+1} = sprintf('<polygon class="reportOptimizationBand" data-index-start="%.0f" data-index-end="%.0f" points="%s" fill="%s" opacity="0.15" stroke="none"/>', ...
                        xr(1), xr(end), pts, col); %#ok<AGROW>
                end

                lineRuns = NMResultsViewerReportFigureTools.optimizationContiguousRunIndices(x, isfinite(y));
                for rr = 1:numel(lineRuns)
                    run = lineRuns{rr};
                    if numel(run) < 2, continue; end
                    parts{end+1} = NMResultsViewerReportFigureTools.optimizationPolylineSegmentSvg( ...
                        x(run), y(run), [1 xMax], yLim, left, top, plotW, plotH, col, lineWidth); %#ok<AGROW>
                end

                finitePointIdx = find(isfinite(y));
                for pp = 1:numel(finitePointIdx)
                    ii = finitePointIdx(pp);
                    px = NMResultsViewerReportSvgLayout.mapX(x(ii), [1 xMax], left, plotW);
                    py = NMResultsViewerReportSvgLayout.mapY(y(ii), yLim, top, plotH);
                    parts{end+1} = sprintf('<circle class="reportOptimizationPoint" data-model-index="%.0f" data-series-index="%d" cx="%.1f" cy="%.1f" r="%.2f" fill="%s" opacity="0.82"><title>%s: model %.0f, value %s</title></circle>', ...
                        x(ii), ss, px, py, markerRadius, col, NMResultsViewerReportSvgLayout.escape(uLabels{ss}), x(ii), NMResultsViewerReportSvgLayout.formatNumber(y(ii))); %#ok<AGROW>
                end

                bi = NaN;
                selectedHit = find(strcmp(selectedLabels,uLabels{ss}) & isfinite(selectedModels) & isfinite(selectedValues),1,'first');
                if ~isempty(selectedHit)
                    tol = max(1e-10, 1e-8 * max(1,abs(selectedValues(selectedHit))));
                    bi = find(isfinite(y) & x == selectedModels(selectedHit) & abs(y-selectedValues(selectedHit)) <= tol,1,'first');
                end
                if ~isfinite(bi)
                    valid = find(isfinite(y));
                    if direction > 0, [~,jj] = max(y(valid)); else, [~,jj] = min(y(valid)); end
                    bi = valid(jj);
                end
                bx = NMResultsViewerReportSvgLayout.mapX(x(bi), [1 xMax], left, plotW);
                by = NMResultsViewerReportSvgLayout.mapY(y(bi), yLim, top, plotH);
                parts{end+1} = sprintf('<circle class="reportOptimizationSelectedPoint" data-model-index="%.0f" data-series-index="%d" cx="%.1f" cy="%.1f" r="4.2" fill="%s" stroke="#0f172a" stroke-width="1.2"><title>Best %s: model %.0f, value %s</title></circle><text x="%.1f" y="%.1f" font-size="9" fill="#0f172a">M%.0f</text>', ...
                    x(bi), ss, bx, by, col, NMResultsViewerReportSvgLayout.escape(uLabels{ss}), x(bi), NMResultsViewerReportSvgLayout.formatNumber(y(bi)), min(w-70,bx+6), max(12,by-6), x(bi)); %#ok<AGROW>
                legendLabels{end+1} = uLabels{ss}; legendColors{end+1} = col; %#ok<AGROW>
            end
            if ~isempty(legendLabels)
                parts{end+1} = NMResultsViewerReportFigureTools.legendSvg(w-right+12, top+4, legendLabels, legendColors);
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

        function width = optimizationLineWidth(nPoints, plotWidth)
            % optimizationLineWidth  Scale visible optimization-line width by rendered point spacing.
            %
            % Dense optimization plots may contain thousands of parameter-combination
            % positions in a few hundred SVG units. The width is therefore derived from
            % the rendered horizontal spacing rather than a coarse row-count tier. The
            % formula mirrors NMResultsViewerUI.modelOptimizationDensePlotStyle and is
            % bounded so sparse plots remain legible while dense plots do not visually
            % bridge missing-combination gaps.

            n = max(1,double(nPoints));
            spacing = max(1,double(plotWidth)) / max(1,n-1);
            width = max(0.22, min(2.60, 0.75 * sqrt(spacing)));
        end

        function radius = optimizationMarkerRadius(nPoints)
            % optimizationMarkerRadius  Scale static optimization symbols by grid density.
            n = max(1,double(nPoints));
            if n > 3000
                radius = 0.75;
            elseif n > 1800
                radius = 0.90;
            elseif n > 1200
                radius = 1.05;
            elseif n > 700
                radius = 1.35;
            elseif n > 400
                radius = 1.70;
            elseif n > 200
                radius = 2.20;
            elseif n > 100
                radius = 2.80;
            else
                radius = 3.40;
            end
        end

        function runs = optimizationContiguousRunIndices(x, validMask)
            % optimizationContiguousRunIndices  Return maximal valid runs over consecutive original indices.
            % A non-finite value, missing row or jump larger than one model index
            % terminates the current run. Isolated valid points are retained as
            % one-element runs so callers can render symbols without false edges.
            x = double(x(:));
            validMask = logical(validMask(:));
            if numel(x) ~= numel(validMask)
                error('NMResultsViewerReportFigureTools:OptimizationRunShapeMismatch', ...
                    'Optimization x coordinates and validity mask must have identical lengths.');
            end
            buffer = cell(1,numel(x));
            nRuns = 0;
            startIdx = 0;
            previousX = NaN;
            for ii = 1:numel(x)
                valid = validMask(ii) && isfinite(x(ii));
                consecutive = valid && startIdx > 0 && isfinite(previousX) && abs((x(ii)-previousX)-1) <= 1e-9;
                if valid && startIdx == 0
                    startIdx = ii;
                elseif valid && ~consecutive
                    nRuns = nRuns + 1;
                    buffer{nRuns} = startIdx:(ii-1);
                    startIdx = ii;
                elseif ~valid && startIdx > 0
                    nRuns = nRuns + 1;
                    buffer{nRuns} = startIdx:(ii-1);
                    startIdx = 0;
                end
                if valid, previousX = x(ii); else, previousX = NaN; end
            end
            if startIdx > 0
                nRuns = nRuns + 1;
                buffer{nRuns} = startIdx:numel(x);
            end
            runs = buffer(1:nRuns);
        end

        function html = optimizationPolylineSegmentSvg(x,y,xLim,yLim,left,top,plotW,plotH,color,width)
            % optimizationPolylineSegmentSvg  Render one complete consecutive optimization run without decimation.
            x = double(x(:)); y = double(y(:));
            if length(x) < 2
                html = '';
                return;
            end
            pts = cell(1,numel(x));
            for ii=1:numel(x)
                pts{ii} = sprintf('%.1f,%.1f', ...
                    NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW), ...
                    NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH));
            end
            html = sprintf('<polyline class="reportOptimizationSegment" data-index-start="%.0f" data-index-end="%.0f" points="%s" fill="none" stroke="%s" stroke-width="%.3f" stroke-linecap="butt" stroke-linejoin="round" shape-rendering="geometricPrecision"/>', ...
                x(1), x(end), strjoin(pts,' '), color, width);
        end

        function html = partitionHeatmapsSvg(cvRows, kind)
            % Reuse the numeric-grid renderer for CV partition and selected-k consensus figures.
            arguments
                cvRows
                kind = 'cv'
            end
            html = '';
            if isempty(cvRows), return; end
            if strcmp(kind,'cluster_consensus')
                html=['<div class="viz">' NMResultsViewerReportFigureTools.partitionHeatmapOneSvg(cvRows,kind) '</div>'];
                return;
            end
            kinds = NMResultsViewerReportFigureTools.structTextArray(cvRows, 'partitionKind');
            uKinds = unique(kinds, 'stable');
            preferred = {'cv1','cv2','complexity','error'};
            ordered = {};
            for ii=1:numel(preferred)
                if any(strcmp(uKinds, preferred{ii})), ordered{end+1} = preferred{ii}; end %#ok<AGROW>
            end
            for ii=1:numel(uKinds)
                if ~any(strcmp(ordered, uKinds{ii})), ordered{end+1} = uKinds{ii}; end %#ok<AGROW>
            end
            chunks = cell(1,0);
            for kk=1:numel(ordered)
                mask = strcmp(kinds, ordered{kk});
                chunks{end+1} = NMResultsViewerReportFigureTools.partitionHeatmapOneSvg(cvRows(mask), ordered{kk}); %#ok<AGROW>
            end
            html = ['<div class="viz reportHeatmapGrid">' strjoin(chunks, '') '</div>'];
        end

        function html = parameterSurfaceSvg(surfaceRows)
            % parameterSurfaceSvg  Render model-optimization 2D parameter surfaces with axes and colorbars.
            html = '';
            if isempty(surfaceRows), return; end
            labels = NMResultsViewerReportFigureTools.structTextArray(surfaceRows,'seriesLabel');
            for ii=1:numel(labels), if isempty(labels{ii}), labels{ii} = 'Series'; end, end
            uLabels = unique(labels, 'stable');
            chunks = cell(1,0);
            for ss=1:min(2,numel(uLabels))
                mask = strcmp(labels, uLabels{ss});
                chunks{end+1} = NMResultsViewerReportFigureTools.surfaceOneSvg(surfaceRows(mask), uLabels{ss}); %#ok<AGROW>
            end
            html = ['<div class="viz reportSurfaceGrid">' strjoin(chunks,'') '</div>'];
        end

        function html = scatterParetoSvg(scatterRows, associationRows, paretoRows, titleText)
            % scatterParetoSvg  Render metric-vs-metric scatter and optional Pareto frontier.
            html = '';
            if isempty(scatterRows), return; end
            xAll = NMResultsViewerReportFigureTools.structNumericArray(scatterRows,'xValue');
            yAll = NMResultsViewerReportFigureTools.structNumericArray(scatterRows,'yValue');
            goodAll = isfinite(xAll) & isfinite(yAll);
            if nnz(goodAll) < 2, return; end
            xLim = [min(xAll(goodAll)) max(xAll(goodAll))];
            yLim = [min(yAll(goodAll)) max(yAll(goodAll))];
            if abs(xLim(2)-xLim(1)) < 1e-12, xLim = xLim + [-0.5 0.5]; end
            if abs(yLim(2)-yLim(1)) < 1e-12, yLim = yLim + [-0.5 0.5]; end
            xPad = 0.06 * max(eps, xLim(2)-xLim(1)); yPad = 0.06 * max(eps, yLim(2)-yLim(1));
            xLim = xLim + [-xPad xPad]; yLim = yLim + [-yPad yPad];
            labels = NMResultsViewerReportFigureTools.structTextArray(scatterRows,'seriesLabel');
            for ii=1:numel(labels), if isempty(labels{ii}), labels{ii} = 'Series'; end, end
            uLabels = unique(labels,'stable');
            colors = {'#2563eb','#c2410c','#16a34a','#9333ea'};
            xMetric = scatterRows(1).xMetric;
            yMetric = scatterRows(1).yMetric;
            cap = NMResultsViewerReportFigureTools.associationCaption(associationRows, paretoRows);
            w = 760; h = 470;
            opts = NMResultsViewerReportSvgLayout.defaultAxesOptions();
            opts.MinLeft = 82;
            opts.MinRight = 178;
            opts.MinBottom = 86;
            opts.LegendWidth = 168;
            if ~isempty(cap)
                opts.AnnotationRows = {cap};
            end
            layout = NMResultsViewerReportSvgLayout.axesLayout(w,h,xLim,yLim,xMetric,yMetric,titleText,opts);
            left = layout.left; top = layout.top; plotW = layout.plotW; plotH = layout.plotH;
            parts = {NMResultsViewerReportFigureTools.svgOpen(w,h,titleText)};
            parts{end+1} = NMResultsViewerReportSvgLayout.axesSvg(layout);
            legendLabels = cell(1,0); legendColors = cell(1,0);
            for ss=1:min(4,numel(uLabels))
                mask = strcmp(labels,uLabels{ss});
                rows = scatterRows(mask);
                x = NMResultsViewerReportFigureTools.structNumericArray(rows,'xValue');
                y = NMResultsViewerReportFigureTools.structNumericArray(rows,'yValue');
                isFront = NMResultsViewerReportFigureTools.structLogicalArray(rows,'isParetoFrontier');
                col = colors{min(ss,numel(colors))};
                if numel(x) > 1200
                    sel = unique(round(linspace(1,numel(x),1200))); x = x(sel); y = y(sel); isFront = isFront(sel);
                end
                for ii=1:numel(x)
                    if ~isfinite(x(ii)) || ~isfinite(y(ii)), continue; end
                    cx = NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW);
                    cy = NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH);
                    if isFront(ii)
                        parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="4.0" fill="%s" opacity="0.90" stroke="#0f172a" stroke-width="1"><title>Pareto/frontier model</title></circle>', cx, cy, col); %#ok<AGROW>
                    else
                        parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="2.1" fill="%s" opacity="0.42"/>', cx, cy, col); %#ok<AGROW>
                    end
                end
                front = isFront & isfinite(x) & isfinite(y);
                if nnz(front) >= 2
                    xf = x(front); yf = y(front); [xf,ord] = sort(xf); yf = yf(ord);
                    parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(xf,yf,xLim,yLim,left,top,plotW,plotH,col,2.0,'3 3'); %#ok<AGROW>
                end
                if length(associationRows) >= ss
                    a = associationRows(ss);
                    slope = double(a.slope);
                    intercept = double(a.intercept);
                    if isfinite(slope) && isfinite(intercept)
                        xx = xLim(:); yy = intercept + slope .* xx;
                        parts{end+1} = NMResultsViewerReportFigureTools.polylineSvg(xx,yy,xLim,yLim,left,top,plotW,plotH,col,1.2,'5 3'); %#ok<AGROW>
                    end
                end
                legendLabels{end+1} = uLabels{ss}; legendColors{end+1} = col; %#ok<AGROW>
            end
            if ~isempty(legendLabels)
                parts{end+1} = NMResultsViewerReportFigureTools.legendSvg(layout.left+layout.plotW+12, layout.top+4, legendLabels, legendColors);
            end
            parts{end+1} = '</svg>';
            html = ['<div class="viz">' strjoin(parts,'') '</div>'];
        end

    end

    methods (Static)
        function html = featureInspectionRelationMatrixSvg(relationPayload, opts)
            % featureInspectionRelationMatrixSvg  Render the captured relation-matrix page with discrete pattern overlays.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.featureInspectionRelationMatrixSvg(relationPayload,opts)
            %
            % Inputs:
            %   relationPayload  Canonical output of getModelFeatureRelationPayload.
            %   opts             Optional Title and ShowPatternLegend presentation fields.
            %
            % Outputs:
            %   html  Self-contained SVG fragment showing the selected numerical layer,
            %         a separate value colorbar, and edge-pattern boundary annotations.
            %
            % Scientific contract:
            %   Cell colour represents only the selected physical relation layer. Pattern
            %   identity is encoded by cell outlines and a discrete legend; it never replaces
            %   correlation/evidence colour. The report emits the lower triangle including
            %   the diagonal, matching the browser and avoiding duplicated symmetric evidence.
            %   Pattern overlays are projections of canonical retained graph edges onto that
            %   exact lower-triangular displayed matrix page.
            %
            % Invariants and mutability:
            %   Stable feature indices resolve graph endpoints. Matrix values, feature order,
            %   pagination, labels, and graph membership are not recomputed or mutated.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment when no available bounded matrix is present.
            %
            % Side effects:
            %   None.
            arguments
                relationPayload
                opts.Title = 'Feature-correlation matrix'
                opts.ShowPatternLegend = false
                opts.DisplayContract
            end
            html = '';
            if ~relationPayload.ok, return; end
            view=relationPayload.view;
            if ~view.available, return; end
            M=NMResultsViewerReportFigureTools.matrixPayloadValues(struct('values',{view.values}));
            if isempty(M), return; end
            n=min(size(M,1),size(M,2)); M=double(M(1:n,1:n));
            labels=NMResultsViewerReportFigureTools.cellstrSafe(view.displayLabels);
            for ii=(numel(labels)+1):n, labels{ii}=sprintf('Feature %d',ii); end %#ok<AGROW>
            displayIdx=double(view.displayFeatureIndices); displayIdx=displayIdx(:)';
            if numel(displayIdx)<n, displayIdx=1:n; else, displayIdx=displayIdx(1:n); end
            graph=view.graph;
            edges=graph.edgeRows;
            edgePattern=zeros(n,n);
            [~,sourceIndex]=ismember([edges.sourceFeatureIndex],displayIdx);
            [~,targetIndex]=ismember([edges.targetFeatureIndex],displayIdx);
            for ee=1:numel(edges)
                rr=sourceIndex(ee); cc=targetIndex(ee);
                if rr==0 || cc==0, continue; end
                pid=round(double(edges(ee).relationClusterId));
                if pid>0, overlayId=pid; else, overlayId=-1; end
                edgePattern(rr,cc)=overlayId; edgePattern(cc,rr)=overlayId;
            end
            patternIds=unique(round(double([edges(sourceIndex>0 & targetIndex>0).relationClusterId])));
            patternIds=patternIds(patternIds>0);
            unassignedVisible=any(edgePattern(:)<0);
            distinguishPatterns=length(patternIds)>=2 || (length(patternIds)>=1 && unassignedVisible);
            showLegend=opts.ShowPatternLegend || distinguishPatterns;
            if ~showLegend, edgePattern(:)=0; end
            titleText=opts.Title;
            contract=NMResultsViewerReportFigureTools.optionsDisplayContract(opts);
            matrixColors=NMResultsViewerDisplaySemanticsTools.sampleColorHexArray(M,contract,'#d1d5db');
            missingCells=~isfinite(M);
            matrixColors(missingCells)=repmat({'#eef2f7'},nnz(missingCells),1);
            left=max(115,min(250,65+7*max(cellfun(@numel,labels)))); top=52; bottom=max(135,min(245,55+6*max(cellfun(@numel,labels))));
            plotSize=max(330,min(690,24*n)); cellSize=plotSize/n;
            legendW=0; if showLegend, legendW=185; end
            w=left+plotSize+85+legendW; h=top+plotSize+bottom;
            parts={NMResultsViewerReportFigureTools.svgOpen(w,h,titleText), ...
                sprintf('<text x="%d" y="22" font-size="14" font-weight="700" fill="#0f172a">%s</text>',left,NMResultsViewerReportSvgLayout.escape(titleText)), ...
                sprintf('<text x="%d" y="40" font-size="10" fill="#475569">%s · page %d of %d</text>',left,NMResultsViewerReportSvgLayout.escape(view.primaryLayerLabel),round(double(view.currentPage)),round(double(view.pageCount)))};
            % Browser/report parity: render only the lower triangle, including
            % the diagonal. The symmetric upper triangle intentionally emits no
            % cell, outline, tooltip target, or duplicate numerical evidence.
            for rr=1:n
                for cc=1:rr
                    v=M(rr,cc); x=left+(cc-1)*cellSize; y=top+(rr-1)*cellSize;
                    col=matrixColors{rr,cc};
                    parts{end+1}=sprintf('<rect class="relationMatrixCell" data-row="%d" data-column="%d" x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" stroke="#ffffff" stroke-width="0.35"/>',rr,cc,x,y,cellSize,cellSize,col); %#ok<AGROW>
                    pid=edgePattern(rr,cc);
                    if pid~=0
                        if pid>0, stroke=NMResultsViewerReportFigureTools.patternHex(pid); dash=''; else, stroke='#64748b'; dash=' stroke-dasharray="3 2"'; end
                        parts{end+1}=sprintf('<rect class="relationPatternOutline" data-row="%d" data-column="%d" x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="%s" stroke-width="%.2f"%s/>',rr,cc,x+0.8,y+0.8,max(0,cellSize-1.6),max(0,cellSize-1.6),stroke,max(1.2,min(2.4,cellSize*0.10)),dash); %#ok<AGROW>
                    end
                end
            end
            for ii=1:n
                tx=left+(ii-0.5)*cellSize; ty=top+(ii-0.5)*cellSize;
                parts{end+1}=sprintf('<text x="%.1f" y="%.1f" text-anchor="end" font-size="9" fill="#334155">%s</text>',left-7,ty+3,NMResultsViewerReportSvgLayout.escape(labels{ii})); %#ok<AGROW>
                parts{end+1}=sprintf('<text x="%.1f" y="%.1f" transform="rotate(-55 %.1f %.1f)" text-anchor="end" font-size="9" fill="#334155">%s</text>',tx,top+plotSize+13,tx,top+plotSize+13,NMResultsViewerReportSvgLayout.escape(labels{ii})); %#ok<AGROW>
            end
            cbx=left+plotSize+20; cby=top; cbh=min(230,plotSize);
            parts{end+1}=NMResultsViewerReportFigureTools.displayContractColorbarSvg(cbx,cby,14,cbh,contract); %#ok<AGROW>
            parts{end+1}=sprintf('<text x="%.1f" y="%.1f" transform="rotate(90 %.1f %.1f)" text-anchor="middle" font-size="9" fill="#334155">%s</text>',cbx+48,cby+cbh/2,cbx+48,cby+cbh/2,NMResultsViewerReportSvgLayout.escape(view.primaryLayerLabel)); %#ok<AGROW>
            if showLegend
                lx=left+plotSize+85; ly=top;
                parts{end+1}=sprintf('<text x="%.1f" y="%.1f" font-size="11" font-weight="700" fill="#0f172a">Relation patterns</text>',lx,ly+10); %#ok<AGROW>
                for pp=1:numel(patternIds)
                    pid=patternIds(pp); yy=ly+14+pp*22;
                    parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="15" height="15" fill="none" stroke="%s" stroke-width="2"/><text x="%.1f" y="%.1f" font-size="9.5" fill="#334155">Pattern %d</text>',lx,yy,NMResultsViewerReportFigureTools.patternHex(pid),lx+23,yy+11,pid); %#ok<AGROW>
                end
                if unassignedVisible
                    yy=ly+14+(numel(patternIds)+1)*22;
                    parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="15" height="15" fill="none" stroke="#64748b" stroke-width="2" stroke-dasharray="3 2"/><text x="%.1f" y="%.1f" font-size="9.5" fill="#334155">Unassigned retained edges</text>',lx,yy,lx+23,yy+11); %#ok<AGROW>
                end
                parts{end+1}=sprintf('<text x="%.1f" y="%.1f" font-size="8.5" fill="#64748b">Cell fill = numerical relation value</text><text x="%.1f" y="%.1f" font-size="8.5" fill="#64748b">Outline = discrete edge-pattern membership</text>',lx,min(h-42,ly+70+(numel(patternIds)+1)*22),lx,min(h-27,ly+85+(numel(patternIds)+1)*22)); %#ok<AGROW>
            end
            parts{end+1}='</svg>';
            html=['<div class="viz relationMatrixReportFigure">' strjoin(parts,'') '</div>'];
        end

        function [html, contextMarkup, edgeColors] = featureInspectionCanonicalGraphSvg(graph, opts)
            % featureInspectionCanonicalGraphSvg  Render the full pruned graph or one pattern in shared geometry.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.featureInspectionCanonicalGraphSvg(graph,opts)
            %
            % Inputs:
            %   graph  Canonical graph contract from NMResultsViewerFeatureGraphTools.
            %   opts   PatternId (0 for full graph), Title, Compact, LabelMode,
            %          MaxLabels, ShowVisibleTitle, ShowSummary, ContextGraph, and
            %          AllowLabelSuppression presentation fields.
            %
            % Outputs:
            %   html  Deterministic SVG using backend layout coordinates.
            %
            % Scientific contract:
            %   Node coordinates are reused unchanged across the full graph and every pattern.
            %   Pattern tiles retain those coordinates without a per-pattern layout pass. Edge colour encodes the selected relation-layer value through the canonical display contract;
            %   edge width encodes selected-layer magnitude. A pattern tile draws the
            %   complete graph faintly as spatial context and then emphasizes only the
            %   selected pattern. Pattern filtering never changes layout, edge values,
            %   node identities, or scientific membership.
            %
            % Label contract:
            %   Report labels are planned against the final static viewport. The planner
            %   tries all canonical nodes (or all participating pattern nodes), multiple
            %   anchor positions, and progressively smaller readable fonts. Main-graph
            %   labels may be suppressed only when every candidate overlaps; pattern-tile
            %   callers can prohibit suppression. A white SVG text halo separates labels
            %   from the edge field without introducing opaque annotation boxes.
            %
            % Invariants and mutability:
            %   Stable node IDs resolve endpoints. Backend layout coordinates and the graph
            %   contract are read-only. Context geometry uses the same canonical display contract and magnitude scale as the emphasized pattern.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment when graph topology is unavailable. Label
            %   suppression is represented in nonvisual SVG metadata for regression tests.
            %
            % Side effects:
            %   None.
            arguments
                graph
                opts.PatternId = 0
                opts.Compact = false
                opts.ShowVisibleTitle = true
                opts.ShowSummary = true
                opts.ContextGraph
                opts.AllowLabelSuppression = true
                opts.Title
                opts.LabelMode = 'auto'
                opts.MaxLabels = 20
                opts.DisplayContract
                opts.ContextMarkup = ''
                opts.EdgeColors = {}
            end
            html='';
            contextMarkup=opts.ContextMarkup;
            edgeColors=opts.EdgeColors;
            if ~graph.available,return;end
            contract=NMResultsViewerReportFigureTools.optionsDisplayContract(opts);
            allNodes=graph.nodeRows;
            allEdges=graph.edgeRows;
            if isempty(allNodes),return;end
            patternId=round(opts.PatternId);
            selectedEdgeIdx=1:numel(allEdges);
            activeNodes=allNodes;
            if patternId>0
                selectedEdgeIdx=find(round(double([allEdges.relationClusterId]))==patternId);
                activeIds=unique([{allEdges(selectedEdgeIdx).sourceNodeId},{allEdges(selectedEdgeIdx).targetNodeId}]);
                nodeKeep=ismember({allNodes.nodeId},activeIds);
                activeNodes=allNodes(nodeKeep);
            end
            compact=opts.Compact;
            if compact
                w=410;h=300;left=14;right=14;top=14+14*opts.ShowVisibleTitle;bottom=10+16*opts.ShowSummary;
            else
                w=900;h=610;left=30;right=30;top=20+22*opts.ShowVisibleTitle;bottom=18+27*opts.ShowSummary;
            end
            plotW=w-left-right;plotH=h-top-bottom;
            % nm2-allow: Graph title option is intentionally optional; default uses selected graph layer label.
            titleText=opts.Title;
            parts={NMResultsViewerReportFigureTools.svgOpen(w,h,titleText)};
            if opts.ShowVisibleTitle
                parts{end+1}=sprintf('<text x="%d" y="%d" font-size="%d" font-weight="700" fill="#0f172a">%s</text>',left,compact*4+18,11+2*(~compact),NMResultsViewerReportSvgLayout.escape(titleText)); %#ok<AGROW>
            end
            mags=double([allEdges.magnitude]);
            finiteM=mags(isfinite(mags));if isempty(finiteM),magLo=0;magHi=1;else,magLo=min(finiteM);magHi=max(finiteM);if magHi<=magLo,magHi=magLo+1;end,end
            nodeIds={allNodes.nodeId};
            [~,sourceIdx]=ismember({allEdges.sourceNodeId},nodeIds);
            [~,targetIdx]=ismember({allEdges.targetNodeId},nodeIds);
            if isempty(edgeColors)
                edgeColors=NMResultsViewerDisplaySemanticsTools.sampleColorHexArray( ...
                    [allEdges.weight],contract,'#94a3b8');
            end
            nodeX=left+plotW*max(0,min(1,double([allNodes.layoutX])));
            nodeY=top+plotH*max(0,min(1,double([allNodes.layoutY])));
            allStrengths=double([allNodes.absoluteStrength]);
            fS=allStrengths(isfinite(allStrengths));if isempty(fS),sLo=0;sHi=1;else,sLo=min(fS);sHi=max(fS);if sHi<=sLo,sHi=sLo+1;end,end
            allRadii=(compact*1.2+3.2)+(compact*0.8+3.0)*max(0,min(1,(allStrengths-sLo)/(sHi-sLo)));
            if opts.ContextGraph
                if isempty(contextMarkup)
                    startContext=numel(parts)+1;
                    valid=find(sourceIdx>0 & targetIdx>0);
                    widths=0.35+0.75*max(0,min(1,(mags(valid)-magLo)/(magHi-magLo)));
                    parts=[parts reshape(cellstr(compose('<line class="graphContextEdge" x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" stroke-opacity="0.14"/>', ...
                        nodeX(sourceIdx(valid)).',nodeY(sourceIdx(valid)).',nodeX(targetIdx(valid)).',nodeY(targetIdx(valid)).',string(edgeColors(valid)).',widths.')),1,[])];
                    parts=[parts reshape(cellstr(compose('<circle class="graphContextNode" cx="%.2f" cy="%.2f" r="%.2f" fill="#f8fafc" fill-opacity="0.72" stroke="#94a3b8" stroke-opacity="0.48" stroke-width="0.7"/>', ...
                        nodeX(:),nodeY(:),max(1.5,0.55*allRadii(:)))),1,[])];
                    contextMarkup=strjoin(parts(startContext:end),'');
                else
                    parts{end+1}=contextMarkup;
                end
            end
            selected=selectedEdgeIdx(sourceIdx(selectedEdgeIdx)>0 & targetIdx(selectedEdgeIdx)>0);
            widths=0.55+2.7*max(0,min(1,(mags(selected)-magLo)/(magHi-magLo)));
            parts=[parts reshape(cellstr(compose('<line class="graphEmphasizedEdge" x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" stroke-opacity="0.78"/>', ...
                nodeX(sourceIdx(selected)).',nodeY(sourceIdx(selected)).',nodeX(targetIdx(selected)).',nodeY(targetIdx(selected)).',string(edgeColors(selected)).',widths.')),1,[])];
            activeIds={activeNodes.nodeId};
            [~,activeGlobalIdx]=ismember(activeIds,nodeIds);
            activeX=nodeX(activeGlobalIdx);activeY=nodeY(activeGlobalIdx);activeR=allRadii(activeGlobalIdx);
            for nn=1:numel(activeNodes)
                parts{end+1}=sprintf('<circle class="graphEmphasizedNode" data-node-id="%s" cx="%.2f" cy="%.2f" r="%.2f" fill="#f8fafc" stroke="#334155" stroke-width="1.1"/>',NMResultsViewerReportSvgLayout.escape(activeIds{nn}),activeX(nn),activeY(nn),activeR(nn)); %#ok<AGROW>
            end
            labelEligible=true(1,numel(activeNodes));
            if strcmpi(opts.LabelMode,'none')
                labelEligible(:)=false;
            elseif strcmpi(opts.LabelMode,'top_n')||strcmpi(opts.LabelMode,'auto')
                strengths=arrayfun(@(n)double(n.absoluteStrength),activeNodes);
                [~,ord]=sort(strengths,'descend');labelEligible(:)=false;labelEligible(ord(1:min(round(opts.MaxLabels),numel(ord))))=true;
            end
            labelPlan=NMResultsViewerReportFigureTools.graphReportLabelPlan(activeNodes,activeX,activeY,activeR,[left top left+plotW top+plotH], ...
                'Compact',compact,'Eligible',labelEligible,'AllowSuppression',opts.AllowLabelSuppression);
            visibleLabels=0;
            if compact,haloWidth=1.35;else,haloWidth=1.8;end
            for nn=1:numel(activeNodes)
                if ~labelPlan(nn).visible,continue;end
                visibleLabels=visibleLabels+1;
                parts{end+1}=sprintf('<text class="graphNodeLabel" data-node-id="%s" x="%.2f" y="%.2f" text-anchor="%s" font-size="%.2f" fill="#0f172a" style="paint-order:stroke fill;stroke:#fff;stroke-width:%.2fpx;stroke-linejoin:round">%s</text>', ...
                    NMResultsViewerReportSvgLayout.escape(activeIds{nn}),labelPlan(nn).x,labelPlan(nn).y,labelPlan(nn).anchor,labelPlan(nn).fontSize,haloWidth,NMResultsViewerReportSvgLayout.escape(activeNodes(nn).label)); %#ok<AGROW>
            end
            parts{end+1}=sprintf('<g class="graphLabelPlanMetadata" data-requested-label-count="%d" data-visible-label-count="%d" data-suppressed-label-count="%d"></g>',nnz(labelEligible),visibleLabels,nnz(labelEligible)-visibleLabels); %#ok<AGROW>
            if opts.ShowSummary
                parts{end+1}=sprintf('<text x="%d" y="%d" font-size="9" fill="#475569">%d node(s) · %d retained edge(s)%s</text>',left,h-10,numel(activeNodes),numel(selectedEdgeIdx),NMResultsViewerReportFigureTools.graphPatternSuffix(patternId)); %#ok<AGROW>
            end
            parts{end+1}='</svg>';
            html=['<div class="viz canonicalFeatureGraphFigure">' strjoin(parts,'') '</div>'];
        end

        function html = featureInspectionRobustnessSvg(result, opts)
            % featureInspectionRobustnessSvg  Render an identity-valid fixed-density stability trajectory.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.featureInspectionRobustnessSvg(result,opts)
            %
            % Inputs:
            %   result  Captured stability result validated against the
            %           freshly materialized exported graph identity.
            %   opts    Optional Title presentation field.
            %
            % Outputs:
            %   html  SVG fragment showing realized density, stability score, accepted
            %         plateau, eligibility threshold, and selected representative density.
            %
            % Scientific contract:
            %   The plot reports sparsification sensitivity only. It does not represent
            %   sampling uncertainty, statistical significance, causality, cross-validation
            %   stability, or predictive feature importance.
            %
            % Invariants and mutability:
            %   Missing settings remain gaps and no values are interpolated. The input result
            %   is read-only and is not recomputed by the report renderer.
            %
            % Errors and diagnostics:
            %   Returns an empty fragment for unavailable, disabled, or non-finite trajectories.
            %
            % Side effects:
            %   None.
            arguments
                result
                opts.Title = 'Robust graph setting identified'
            end
            html='';if ~result.available||~result.enabled,return;end
            rows=result.settingRows;if isempty(rows),return;end
            x=arrayfun(@(r)100*double(r.realizedDensity),rows);
            y=arrayfun(@(r)double(r.stabilityScore),rows);good=isfinite(x)&isfinite(y);if nnz(good)<2,return;end
            x=x(good);y=y(good);rows=rows(good);w=760;h=350;left=60;right=26;top=40;bottom=52;plotW=w-left-right;plotH=h-top-bottom;
            xlim=[min(x) max(x)];if diff(xlim)<1e-9,xlim=xlim+[-1 1];end;ylim=[0 1];
            titleText=opts.Title;
            parts={NMResultsViewerReportFigureTools.svgOpen(w,h,titleText),sprintf('<text x="%d" y="22" font-size="14" font-weight="700" fill="#0f172a">%s</text>',left,NMResultsViewerReportSvgLayout.escape(titleText)),NMResultsViewerReportSvgLayout.axesSvgFixed(left,top,plotW,plotH,xlim,ylim,'Realized graph density [%]','Stability score')};
            plateau=arrayfun(@(r)logical(r.stablePlateau),rows);
            if any(plateau)
                px=x(plateau);x1=NMResultsViewerReportSvgLayout.mapX(min(px),xlim,left,plotW);x2=NMResultsViewerReportSvgLayout.mapX(max(px),xlim,left,plotW);
                parts{end+1}=sprintf('<rect x="%.2f" y="%d" width="%.2f" height="%d" fill="#dbeafe" opacity="0.55"/>',x1,top,max(2,x2-x1),plotH); %#ok<AGROW>
            end
            threshold=double(result.stabilityThreshold);if isfinite(threshold),yy=NMResultsViewerReportSvgLayout.mapY(threshold,ylim,top,plotH);parts{end+1}=sprintf('<line x1="%d" y1="%.2f" x2="%d" y2="%.2f" stroke="#64748b" stroke-dasharray="4 3"/><text x="%d" y="%.2f" font-size="8.5" fill="#475569">eligibility threshold %.2f</text>',left,yy,left+plotW,yy,left+4,yy-5,threshold);end %#ok<AGROW>
            parts{end+1}=NMResultsViewerReportFigureTools.polylineSvg(x,y,xlim,ylim,left,top,plotW,plotH,'#2563eb',2.1,'');
            for ii=1:numel(x)
                selected=logical(rows(ii).selected);r=selected*2+3;fill='#ffffff';if selected,fill='#dc2626';end
                xx=NMResultsViewerReportSvgLayout.mapX(x(ii),xlim,left,plotW);yy=NMResultsViewerReportSvgLayout.mapY(y(ii),ylim,top,plotH);
                parts{end+1}=sprintf('<circle cx="%.2f" cy="%.2f" r="%d" fill="%s" stroke="#1d4ed8" stroke-width="1.4"/>',xx,yy,r,fill); %#ok<AGROW>
            end
            sel=double(result.selectedDensity);score=double(result.selectedStabilityScore);
            parts{end+1}=sprintf('<text x="%d" y="%d" font-size="9.5" fill="#334155">Selected density: %.1f%% · stability score: %.3f. This is a sparsification-sensitivity diagnostic.</text>',left,h-12,100*sel,score); %#ok<AGROW>
            parts{end+1}='</svg>';html=['<div class="viz graphRobustnessReportFigure">' strjoin(parts,'') '</div>'];
        end

    end

    methods (Static, Access = private)
        function html = svgOpen(w,h,titleText)
            html = sprintf('<svg viewBox="0 0 %d %d" role="img" aria-label="%s" xmlns="http://www.w3.org/2000/svg"><title>%s</title>', w,h,NMResultsViewerReportSvgLayout.escape(titleText),NMResultsViewerReportSvgLayout.escape(titleText));
        end

        function html = barXAxisSvg(left,top,plotW,plotH,xLim,xLabel)
            % barXAxisSvg  Render a categorical-y bar-plot frame with optimized x ticks.
            %
            % This report-specific axis deliberately suppresses numeric y-rank ticks:
            % each plotted feature row is labelled directly. X ticks are computed from
            % the available pixel width with a compact nice-number algorithm so the
            % static report keeps enough tick labels without overlap.

            ticks = NMResultsViewerReportFigureTools.niceTicks(xLim, max(5, floor(plotW ./ 60)));
            parts = cell(1,0);
            parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#fff" stroke="#cbd5e1"/>', left, top, plotW, plotH); %#ok<AGROW>
            for kk = 1:numel(ticks)
                x = NMResultsViewerReportSvgLayout.mapX(ticks(kk), xLim, left, plotW);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#e2e8f0"/>', x, top, x, top+plotH); %#ok<AGROW>
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="10" fill="#475569">%s</text>', x, top+plotH+17, NMResultsViewerReportSvgLayout.escape(NMResultsViewerReportSvgLayout.formatNumber(ticks(kk)))); %#ok<AGROW>
            end
            parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="11" fill="#334155">%s</text>', left+plotW/2, top+plotH+42, NMResultsViewerReportSvgLayout.escape(xLabel)); %#ok<AGROW>
            html = strjoin(parts,'');
        end

        function ticks = niceTicks(lim, targetN)
            % niceTicks  Compute readable linear tick positions for static SVG axes.
            if ~isfinite(targetN) || targetN < 2, targetN = 5; end
            if any(~isfinite(lim))
                ticks = [0 1]; return;
            end
            lo = min(lim); hi = max(lim);
            if abs(hi-lo) < eps(max(1,abs(hi)))
                delta = max(1,abs(hi)); lo = lo - 0.5*delta; hi = hi + 0.5*delta;
            end
            rawStep = (hi-lo) ./ max(1,targetN-1);
            step = NMResultsViewerReportFigureTools.niceStep(rawStep);
            firstTick = ceil(lo ./ step) .* step;
            lastTick = floor(hi ./ step) .* step;
            if ~isfinite(firstTick) || ~isfinite(lastTick) || firstTick > lastTick
                ticks = [lo hi]; return;
            end
            ticks = firstTick:step:lastTick;
            if numel(ticks) < 2
                ticks = [lo hi];
            end
            ticks(abs(ticks) < 5e-13) = 0;
        end

        function step = niceStep(rawStep)
            % niceStep  Return 1/2/2.5/5/10-scaled step for readable tick spacing.
            rawStep = abs(double(rawStep));
            if ~isfinite(rawStep) || rawStep <= 0, step = 1; return; end
            exponent = floor(log10(rawStep));
            fraction = rawStep ./ 10.^exponent;
            if fraction <= 1
                niceFraction = 1;
            elseif fraction <= 2
                niceFraction = 2;
            elseif fraction <= 2.5
                niceFraction = 2.5;
            elseif fraction <= 7
                niceFraction = 5;
            else
                niceFraction = 10;
            end
            step = niceFraction .* 10.^exponent;
        end

        function html = polylineSvg(x,y,xLim,yLim,left,top,plotW,plotH,color,width,dash)
            % polylineSvg  Render a bounded generic SVG polyline.
            html = '';
            x = double(x(:)); y = double(y(:)); good = isfinite(x) & isfinite(y); x = x(good); y = y(good);
            if numel(x) < 2, return; end
            if numel(x) > 1500
                idx = unique(round(linspace(1,numel(x),1500))); x = x(idx); y = y(idx);
            end
            pts = cell(1,numel(x));
            for ii=1:numel(x)
                pts{ii} = sprintf('%.1f,%.1f', NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW), NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH));
            end
            dashTxt = ''; if ~isempty(dash), dashTxt = sprintf(' stroke-dasharray="%s"', dash); end
            html = sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="%.2f"%s/>', strjoin(pts,' '), color, width, dashTxt);
        end

        function html = legendSvg(x,y,labels,colors)
            parts = {sprintf('<rect x="%d" y="%d" width="168" height="%d" rx="8" fill="#f8fafc" stroke="#dbe4ef"/>', x,y,18+18*numel(labels))};
            for ii=1:numel(labels)
                col = colors{min(ii,numel(colors))};
                parts{end+1} = sprintf('<line x1="%d" y1="%d" x2="%d" y2="%d" stroke="%s" stroke-width="2"/><text x="%d" y="%d" font-size="10" fill="#0f172a">%s</text>', x+10,y+14+18*(ii-1),x+32,y+14+18*(ii-1),col,x+40,y+18+18*(ii-1),NMResultsViewerReportSvgLayout.escape(labels{ii})); %#ok<AGROW>
            end
            html = strjoin(parts,'');
        end



        function html = partitionHeatmapOneSvg(rows, kind)
            consensus=strcmp(kind,'cluster_consensus');
            if consensus
                titleText='Selected-k co-clustering frequency';
                perms=[rows.rowBin]';folds=[rows.columnBin]';vals=[rows.frequency]';
            else
                titleText=rows(1).title;
                perms=double([rows.permutation]');
                folds=double([rows.fold]');
                vals=double([rows.value]');
            end
            finite = isfinite(perms) & isfinite(folds) & isfinite(vals);
            if ~any(finite), html = ''; return; end
            nP = max(perms(finite)); nF = max(folds(finite));
            if ~isfinite(nP) || nP < 1, nP = 1; end
            if ~isfinite(nF) || nF < 1, nF = 1; end
            if consensus, computed=finite; else, computed=NMResultsViewerReportFigureTools.computedMaskFromRows(rows, kind); end
            validVals = vals(finite & computed(:));
            if isempty(validVals), validVals = vals(finite); end
            lo = min(validVals); hi = max(validVals); if abs(hi-lo) < 1e-12, hi = lo + 1; end
            w = 440; h = 300;
            if consensus, lo=0;hi=1;w=600;h=580;end
            foldLabels = cell(1,nF); for ff=1:nF, foldLabels{ff} = sprintf('%d', ff); end
            permLabels = cell(1,nP); for pp=1:nP, permLabels{pp} = sprintf('%d', pp); end
            xLabel='Fold';yLabel='Permutation';
            if consensus,xLabel='Subjects (optimal leaf order)';yLabel=xLabel;end
            layout = NMResultsViewerReportSvgLayout.heatmapLayout(w,h,foldLabels,permLabels,xLabel,yLabel,titleText,true);
            x0 = layout.left; y0 = layout.top; plotW = layout.plotW; plotH = layout.plotH; cellW = plotW/nF; cellH = plotH/nP;
            baseColor = '#2563eb';
            if contains(lower(kind),'cv2'), baseColor = '#c2410c'; elseif contains(lower(kind),'complex'), baseColor = '#16a34a'; elseif contains(lower(kind),'error'), baseColor = '#9333ea'; end
            widthPct=48;ariaType='partition heatmap';
            if consensus,widthPct=100;ariaType='heatmap';end
            parts = {sprintf('<svg viewBox="0 0 %d %d" class="reportPanelSvg" style="max-width:%d%%;display:inline-block;margin:0 10px 12px 0;vertical-align:top" role="img" aria-label="%s %s" xmlns="http://www.w3.org/2000/svg"><title>%s</title>', w,h,widthPct,NMResultsViewerReportSvgLayout.escape(titleText),ariaType,NMResultsViewerReportSvgLayout.escape(titleText)), ...
                sprintf('<text x="%.1f" y="18" font-size="12" font-weight="700">%s</text>', x0, NMResultsViewerReportSvgLayout.escape(NMResultsViewerReportSvgLayout.prettifyLabel(titleText)))};
            for ii=1:numel(vals)
                if ~finite(ii), continue; end
                x = x0 + (folds(ii)-1)*cellW; y = y0 + (perms(ii)-1)*cellH;
                if computed(ii)
                    t = max(0,min(1,(vals(ii)-lo)/(hi-lo)));
                    if contains(lower(kind),'error'), t = 1 - t; end
                    if consensus, strength=t;else,strength=0.18+0.72*t;end
                    col = NMResultsViewerReportFigureTools.mixHex('#ffffff', baseColor, strength);
                    txtCol = NMResultsViewerReportSvgLayout.contrastText(col);
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="#fff" stroke-width=".6"><title>%s P%d/F%d: %s</title></rect>', ...
                        x,y,max(1,cellW-.8),max(1,cellH-.8),col,NMResultsViewerReportSvgLayout.escape(kind),round(perms(ii)),round(folds(ii)),NMResultsViewerReportSvgLayout.formatNumber(vals(ii))); %#ok<AGROW>
                    if nP*nF <= 144
                        parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="7" fill="%s">%s</text>', x+cellW/2, y+cellH/2+2, txtCol, NMResultsViewerReportSvgLayout.formatNumber(vals(ii))); %#ok<AGROW>
                    end
                else
                    parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#f8fafc" stroke="#cbd5e1" stroke-width=".6"><title>%s P%d/F%d: uncomputed/missing</title></rect><line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#cbd5e1" stroke-width=".7"/>', ...
                        x,y,max(1,cellW-.8),max(1,cellH-.8),NMResultsViewerReportSvgLayout.escape(kind),round(perms(ii)),round(folds(ii)),x,y+cellH,x+cellW,y); %#ok<AGROW>
                end
            end
            parts{end+1} = NMResultsViewerReportSvgLayout.heatmapAxesSvg(layout,false);
            parts{end+1} = NMResultsViewerReportFigureTools.colorbarSvg(x0+plotW+18,y0,16,plotH,baseColor,lo,hi,contains(lower(kind),'error'));
            nMissing = nnz(finite & ~computed(:));
            if nMissing > 0
                parts{end+1} = sprintf('<text x="%d" y="%d" font-size="10" fill="#9a3412">%d cells masked as missing/uncomputed</text>', x0, h-10, nMissing);
            end
            parts{end+1} = '</svg>';
            html = strjoin(parts,'');
        end

        function html = surfaceOneSvg(rows, titleText)
            xVals = NMResultsViewerReportFigureTools.sortedUniqueText(NMResultsViewerReportFigureTools.structTextArray(rows,'xValue'));
            yVals = NMResultsViewerReportFigureTools.sortedUniqueText(NMResultsViewerReportFigureTools.structTextArray(rows,'yValue'));
            vals = NMResultsViewerReportFigureTools.structNumericArray(rows,'aggregateValue');
            finite = isfinite(vals);
            if isempty(xVals) || isempty(yVals) || ~any(finite), html = ''; return; end
            lo = min(vals(finite)); hi = max(vals(finite)); if abs(hi-lo) < 1e-12, hi = lo + 1; end
            direction = rows(1).directionSign;
            xParam = rows(1).xParameter;
            yParam = rows(1).yParameter;
            w = 500; h = 360;
            layout = NMResultsViewerReportSvgLayout.heatmapLayout(w,h,xVals,yVals,xParam,yParam,titleText,true);
            x0 = layout.left; y0 = layout.top; plotW = layout.plotW; plotH = layout.plotH;
            cellW = plotW/numel(xVals); cellH = plotH/numel(yVals);
            parts = {sprintf('<svg viewBox="0 0 %d %d" class="reportPanelSvg" style="max-width:48%%;display:inline-block;margin:0 10px 12px 0;vertical-align:top" role="img" aria-label="%s parameter surface" xmlns="http://www.w3.org/2000/svg"><title>%s</title>', w,h,NMResultsViewerReportSvgLayout.escape(titleText),NMResultsViewerReportSvgLayout.escape(titleText)), ...
                sprintf('<text x="%.1f" y="18" font-size="12" font-weight="700">%s</text>', x0, NMResultsViewerReportSvgLayout.escape(NMResultsViewerReportSvgLayout.prettifyLabel(titleText)))};
            bestScore = -Inf; bestRow = 0; bestXi = NaN; bestYi = NaN;
            for ii=1:numel(rows)
                v = double(rows(ii).aggregateValue);
                if ~isfinite(v), continue; end
                score = direction * v;
                if score > bestScore
                    bestScore = score; bestRow = ii;
                end
            end
            for ii=1:numel(rows)
                xv = rows(ii).xValue;
                yv = rows(ii).yValue;
                xi = find(strcmp(xVals,xv),1); yi = find(strcmp(yVals,yv),1);
                v = double(rows(ii).aggregateValue);
                if isempty(xi) || isempty(yi) || ~isfinite(v), continue; end
                normVal = max(0,min(1,(v-lo)/(hi-lo)));
                if direction < 0, normVal = 1 - normVal; end
                col = NMResultsViewerReportFigureTools.hotColorHex(1-normVal);
                txtCol = NMResultsViewerReportSvgLayout.contrastText(col);
                x = x0 + (xi-1)*cellW; y = y0 + (yi-1)*cellH;
                parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="#fff" stroke-width=".7"><title>%s=%s, %s=%s, value=%s</title></rect>', ...
                    x,y,max(1,cellW-.8),max(1,cellH-.8),col,NMResultsViewerReportSvgLayout.escape(xParam),NMResultsViewerReportSvgLayout.escape(xv),NMResultsViewerReportSvgLayout.escape(yParam),NMResultsViewerReportSvgLayout.escape(yv),NMResultsViewerReportSvgLayout.formatNumber(v)); %#ok<AGROW>
                fz = 8; fw = '400';
                if ii == bestRow
                    fz = 10; fw = '700'; bestXi = x; bestYi = y;
                end
                parts{end+1} = sprintf('<text x="%.1f" y="%.1f" text-anchor="middle" font-size="%d" font-weight="%s" fill="%s">%s</text>', ...
                    x+cellW/2, y+cellH/2+3, fz, fw, txtCol, NMResultsViewerReportSvgLayout.formatNumber(v)); %#ok<AGROW>
            end
            if isfinite(bestXi)
                bestModel = double(rows(bestRow).bestModelIndex);
                parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#0f172a" stroke-width="2.4"><title>Best model %s, value %s</title></rect>', ...
                    bestXi,bestYi,max(1,cellW-.8),max(1,cellH-.8),NMResultsViewerReportSvgLayout.formatNumber(bestModel),NMResultsViewerReportSvgLayout.formatNumber(double(rows(bestRow).aggregateValue)));
            end
            parts{end+1} = NMResultsViewerReportSvgLayout.heatmapAxesSvg(layout,true);
            parts{end+1} = NMResultsViewerReportFigureTools.hotColorbarSvg(x0+plotW+20,y0,16,plotH,lo,hi,direction);
            parts{end+1} = '</svg>';
            html = strjoin(parts,'');
        end

        function mask = computedMaskFromRows(rows, ~)
            % computedMaskFromRows  Consume the fixed report partition-row mask.
            raw = [rows.computed];
            mask = logical(raw(:));
        end

        function html = colorbarSvg(x,y,w,h,baseColor,lo,hi,invert)
            parts = cell(1,0);
            n = 24;
            for ii=1:n
                t = (ii-1)/(n-1); if invert, t = 1 - t; end
                col = NMResultsViewerReportFigureTools.mixHex('#ffffff', baseColor, 0.18+0.72*t);
                yy = y + (n-ii)*h/n;
                parts{end+1} = sprintf('<rect x="%d" y="%.1f" width="%d" height="%.1f" fill="%s" stroke="none"/>', x, yy, w, h/n+0.5, col); %#ok<AGROW>
            end
            parts{end+1} = sprintf('<rect x="%d" y="%d" width="%d" height="%d" fill="none" stroke="#94a3b8"/><text x="%d" y="%d" font-size="8" fill="#475569">%s</text><text x="%d" y="%d" font-size="8" fill="#475569">%s</text>', x,y,w,h,x+w+4,y+8,NMResultsViewerReportSvgLayout.formatNumber(hi),x+w+4,y+h,NMResultsViewerReportSvgLayout.formatNumber(lo));
            html = strjoin(parts,'');
        end

        function html = hotColorbarSvg(x,y,w,h,lo,hi,direction)
            parts = cell(1,0); n = 24;
            for ii=1:n
                normVal = (ii-1)/(n-1);
                if direction < 0, normVal = 1 - normVal; end
                col = NMResultsViewerReportFigureTools.hotColorHex(1-normVal);
                yy = y + (n-ii)*h/n;
                parts{end+1} = sprintf('<rect x="%d" y="%.1f" width="%d" height="%.1f" fill="%s" stroke="none"/>', x, yy, w, h/n+0.5, col); %#ok<AGROW>
            end
            parts{end+1} = sprintf('<rect x="%d" y="%d" width="%d" height="%d" fill="none" stroke="#94a3b8"/><text x="%d" y="%d" font-size="8" fill="#475569">%s</text><text x="%d" y="%d" font-size="8" fill="#475569">%s</text>', x,y,w,h,x+w+4,y+8,NMResultsViewerReportSvgLayout.formatNumber(hi),x+w+4,y+h,NMResultsViewerReportSvgLayout.formatNumber(lo));
            html = strjoin(parts,'');
        end

        function pts = pointList(x,y,xLim,yLim,left,top,plotW,plotH)
            x = double(x(:)); y = double(y(:));
            good = isfinite(x) & isfinite(y); x = x(good); y = y(good);
            ptsCell = cell(1,numel(x));
            for ii=1:numel(x)
                ptsCell{ii} = sprintf('%.1f,%.1f', NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW), NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH));
            end
            pts = strjoin(ptsCell,' ');
        end


        function vals = structLogicalArray(rows,fieldName)
            if isempty(rows), vals = false(0,1); return; end
            raw = [rows.(fieldName)];
            vals = logical(raw(:));
        end

        function vals = sortedUniqueText(vals)
            vals = vals(:)';
            vals = vals(~cellfun(@isempty, vals));
            vals = unique(vals, 'stable');
            if isempty(vals), return; end
            nums = NaN(1,numel(vals));
            for ii=1:numel(vals), nums(ii) = str2double(vals{ii}); end
            if all(isfinite(nums))
                [~,ord] = sort(nums);
            else
                lowerVals = cellfun(@lower, vals, 'UniformOutput', false);
                [~,ord] = sort(lowerVals);
            end
            vals = vals(ord);
        end

        function cap = associationCaption(associationRows, paretoRows)
            cap = '';
            if ~isempty(associationRows)
                a = associationRows(1);
                r = double(a.pearsonR);
                p = double(a.pValue);
                n = double(a.n);
                cap = sprintf('Association: r=%s, p=%s, n=%s', NMResultsViewerReportSvgLayout.formatNumber(r), NMResultsViewerReportSvgLayout.formatNumber(p), NMResultsViewerReportSvgLayout.formatNumber(n));
            end
            if ~isempty(paretoRows)
                nf = double(paretoRows(1).nFrontier);
                if isfinite(nf), cap = strtrim([cap sprintf(' | Pareto/frontier models: %s', NMResultsViewerReportSvgLayout.formatNumber(nf))]); end
            end
        end

        function hex = hotColorHex(t)
            t = max(0,min(1,double(t)));
            r = round(255 * min(1, 2.8*t));
            g = round(255 * max(0,min(1,2.8*t - 0.9)));
            b = round(255 * max(0,min(1,2.8*t - 1.8)));
            hex = sprintf('#%02x%02x%02x', r, g, b);
        end

        function mat = numericMatrix(values)
            % numericMatrix  Consume a canonical numeric matrix.
            mat = double(values);
        end

        function [x,y] = pointsXY(points, xName, yName)
            % pointsXY  Read fixed point coordinates from a canonical point array.
            rawX = [points.(xName)];
            rawY = [points.(yName)];
            x = double(rawX(:));
            y = double(rawY(:));
        end

        function vals = structNumericArray(rows, fieldName)
            % structNumericArray  Read one scalar-numeric field from canonical rows.
            if isempty(rows), vals = zeros(0,1); return; end
            raw = [rows.(fieldName)];
            vals = double(raw(:));
        end

        function vals = structTextArray(rows, fieldName)
            % structTextArray  Read one text field from canonical rows.
            if isempty(rows), vals = cell(0,1); return; end
            vals = reshape({rows.(fieldName)}, [], 1);
        end

        function labels = cellstrSafe(values)
            % cellstrSafe  Consume canonical cell-array text labels.
            labels = reshape(values,1,[]);
        end

        function val = optionField(opts, name, default)
            % nm2-allow: static report presentation request boundary owns optional figure options
            if isfield(opts,name) && ~isempty(opts.(name))
                val = opts.(name);
            else
                val = default;
            end
        end

        function x = optionScalar(opts, name, default)
            % nm2-allow: static report presentation request boundary owns optional scalar figure options
            if isfield(opts,name) && ~isempty(opts.(name))
                x = double(opts.(name));
            else
                x = double(default);
            end
        end

        function tf = optionLogical(opts, name)
            % nm2-allow: static report presentation request boundary owns optional logical figure options
            tf = isfield(opts,name) && ~isempty(opts.(name)) && logical(opts.(name));
        end

        function fieldName = firstFiniteField(rows,candidates)
            fieldName = '';
            for cc=1:numel(candidates)
                vals = NMResultsViewerReportFigureTools.structNumericArray(rows,candidates{cc});
                if any(isfinite(vals)), fieldName = candidates{cc}; return; end
            end
        end

        function lim = limitField(s, name, data)
            % limitField  Consume canonical limits; derive only from values when non-finite.
            lim = double(s.(name));
            if any(~isfinite(lim)) || lim(1) == lim(2)
                d = double(data(:)); d = d(isfinite(d));
                if isempty(d), lim = [0 1]; else, lim = [min(d) max(d)]; end
                if abs(lim(2)-lim(1)) < 1e-12, lim = lim + [-0.5 0.5]; end
            end
        end

        function curves = curveList(payload, kind)
            % curveList  Project fixed calibration/DCA payloads to one local curve schema.
            tmpl = struct('label','','points',[],'rawPoints',[],'color','','isReference',false);
            curves = tmpl([]);
            if strcmp(kind,'calibration')
                useSmooth = logical(payload.smoothCurve);
                if payload.multi
                    raw = payload.curves;
                    for ii=1:numel(raw)
                        if ~raw(ii).ok, continue; end
                        pts = raw(ii).points;
                        if useSmooth && ~isempty(raw(ii).smoothPoints), pts = raw(ii).smoothPoints; end
                        curves(end+1) = struct('label',raw(ii).label,'points',pts,'rawPoints',raw(ii).points, ...
                            'color',raw(ii).color,'isReference',false); %#ok<AGROW>
                    end
                else
                    pts = payload.points;
                    if useSmooth && ~isempty(payload.smoothPoints), pts = payload.smoothPoints; end
                    curves = struct('label',payload.activeLabel,'points',pts,'rawPoints',payload.points, ...
                        'color','#2563eb','isReference',false);
                    if payload.hasReferenceCurve && payload.referenceCurve.ok
                        ref = payload.referenceCurve; refPts = ref.points;
                        if useSmooth && ~isempty(ref.smoothPoints), refPts = ref.smoothPoints; end
                        curves(end+1) = struct('label',ref.label,'points',refPts,'rawPoints',ref.points, ...
                            'color',ref.color,'isReference',true); %#ok<AGROW>
                    end
                end
                return;
            end

            if payload.multi
                raw = payload.curves;
                for ii=1:numel(raw)
                    if ~raw(ii).ok || isempty(raw(ii).points), continue; end
                    curves(end+1) = struct('label',raw(ii).label,'points',raw(ii).points, ...
                        'rawPoints',raw(ii).points,'color',raw(ii).color,'isReference',false); %#ok<AGROW>
                end
            else
                if ~isempty(payload.active.points)
                    curves(end+1) = struct('label',payload.active.label,'points',payload.active.points, ...
                        'rawPoints',payload.active.points,'color','#2563eb','isReference',false); %#ok<AGROW>
                end
                if ~isempty(payload.reference.points)
                    curves(end+1) = struct('label',payload.reference.label,'points',payload.reference.points, ...
                        'rawPoints',payload.reference.points,'color','#808080','isReference',true); %#ok<AGROW>
                end
            end
        end

        function [x,y] = calibrationXY(points)
            [x,y] = NMResultsViewerReportFigureTools.pointsXY(points,'meanPredicted','fractionPositive');
        end

        function [x,y] = dcaModelXY(points)
            [x,y] = NMResultsViewerReportFigureTools.pointsXY(points,'threshold','model');
        end

        function label = compactLegendLabel(label)
            label = strtrim(label);
            if isempty(label), label = 'Curve'; end
            label = strrep(label, ' vs. REST', ' vs REST');
            label = strrep(label, 'Discovery / CV', 'Discovery/CV');
            maxChars = 24;
            if numel(label) > maxChars
                label = [label(1:maxChars-1) '...'];
            end
        end

        function html = polylineSvgWithOpacity(x,y,xLim,yLim,left,top,plotW,plotH,color,width,dash,opacity)
            html = '';
            x = double(x(:)); y = double(y(:)); good = isfinite(x) & isfinite(y); x = x(good); y = y(good);
            if numel(x) < 2, return; end
            if numel(x) > 1500
                idx = unique(round(linspace(1,numel(x),1500))); x = x(idx); y = y(idx);
            end
            pts = cell(1,numel(x));
            for ii=1:numel(x)
                pts{ii} = sprintf('%.1f,%.1f', NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW), NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH));
            end
            dashTxt = ''; if ~isempty(dash), dashTxt = sprintf(' stroke-dasharray="%s"', dash); end
            html = sprintf('<polyline points="%s" fill="none" stroke="%s" stroke-width="%.2f" opacity="%.2f"%s/>', strjoin(pts,' '), color, width, opacity, dashTxt);
        end

        function html = circleSeriesSvg(x,y,xLim,yLim,left,top,plotW,plotH,color,radius,opacity)
            html = '';
            x = double(x(:)); y = double(y(:)); good = isfinite(x) & isfinite(y); x = x(good); y = y(good);
            if isempty(x), return; end
            maxPts = min(numel(x), 200); idx = unique(round(linspace(1,numel(x),maxPts)));
            parts = cell(1,numel(idx));
            for jj=1:numel(idx)
                ii = idx(jj);
                parts{jj} = sprintf('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="%s" opacity="%.2f" stroke="#fff" stroke-width="0.7"/>', ...
                    NMResultsViewerReportSvgLayout.mapX(x(ii),xLim,left,plotW), NMResultsViewerReportSvgLayout.mapY(y(ii),yLim,top,plotH), radius, color, opacity);
            end
            html = strjoin(parts,'');
        end

        function reserve = featureBarBottomReserve(nLegendRows, hasNote)
            % featureBarBottomReserve  Reserve the minimal lower margin for axes and key.
            %
            % The feature-bar key is a small unboxed row anchored to the panel's
            % lower-left corner. Four ordinary entries fit on one line at report scale;
            % additional lines are reserved only when the active threshold semantics
            % require them. hasNote is retained as presentation state and does not add
            % a separate visual block.
            legendLines = max(1,ceil(double(nLegendRows)./4));
            reserve = 72 + 12 .* legendLines;
        end

        function y = legendBelowXAxisY(top, plotH)
            % legendBelowXAxisY  Return the compact key origin below the x-axis title.
            %
            % barXAxisSvg places the title at top+plotH+42. The returned origin keeps
            % a small fixed gap and lets compactInlineLegendSvg draw its baseline near
            % the lower-left panel edge without covering ticks or axis text.
            y = top + plotH + 53;
        end

        function html = reportLegendSvg(x,y,rows,width)
            html = '';
            if isempty(rows), return; end
            nRows = size(rows,1);
            height = 12 + 18*nRows;
            parts = {sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" rx="8" fill="#f8fafc" stroke="#dbe4ef" opacity="0.96"/>', x,y,width,height)};
            for ii=1:nRows
                yy = y + 14 + 18*(ii-1);
                label = NMResultsViewerReportSvgLayout.escape(rows{ii,1});
                col = rows{ii,2}; dash = rows{ii,3}; itemType = 'line';
                if ~isempty(rows{ii,4}), itemType = rows{ii,4}; end
                dashTxt = ''; if ~isempty(dash), dashTxt = sprintf(' stroke-dasharray="%s"', dash); end
                if strcmp(itemType,'point') || strcmp(itemType,'circle')
                    parts{end+1} = sprintf('<circle cx="%.1f" cy="%.1f" r="5.2" fill="%s"/><text x="%.1f" y="%.1f" font-size="9" fill="#0f172a">%s</text>', ...
                        x+20,yy,col,x+40,yy+4,label); %#ok<AGROW>
                else
                    parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="2"%s/><text x="%.1f" y="%.1f" font-size="9" fill="#0f172a">%s</text>', ...
                        x+10,yy,x+32,yy,col,dashTxt,x+40,yy+4,label); %#ok<AGROW>
                end
            end
            html = strjoin(parts,'');
        end

        function plan = graphReportLabelPlan(nodes,x,y,r,bounds,opts)
            % graphReportLabelPlan  Plan collision-aware labels for static graph reports.
            %
            % Syntax:
            %   plan = NMResultsViewerReportFigureTools.graphReportLabelPlan(nodes,x,y,r,bounds,opts)
            %
            % Inputs:
            %   nodes   Canonical node rows in the order represented by x, y, and r.
            %   x,y,r   Static SVG node centres and radii.
            %   bounds  [left top right bottom] label-placement rectangle.
            %   opts    Compact, Eligible, and AllowSuppression fields.
            %
            % Outputs:
            %   plan  Fixed-schema rows with visible, x, y, anchor, fontSize, and box.
            %
            % Presentation contract:
            %   Labels are attempted in descending node-strength order. Each label tries
            %   multiple anchors and progressively smaller fonts. A candidate is valid only
            %   when its estimated halo-expanded box is inside the plot, avoids prior labels,
            %   and avoids other node symbols. When suppression is prohibited, the lowest-
            %   conflict candidate is used so every participating pattern node remains named.
            %
            % Invariants and mutability:
            %   Node coordinates and labels are read-only. The planner is deterministic and
            %   does not alter graph topology, scientific values, or backend layout.
            %
            % Errors and diagnostics:
            %   Invalid dimensions return invisible plan rows rather than raising a layout error.
            %
            % Side effects:
            %   None.
            arguments
                nodes
                x
                y
                r
                bounds
                opts.Compact = false
                opts.Eligible = true(1,numel(nodes))
                opts.AllowSuppression = false
            end
            template=struct('visible',false,'x',NaN,'y',NaN,'anchor','start','fontSize',NaN,'box',[NaN NaN NaN NaN]);
            plan=repmat(template,1,numel(nodes));
            if isempty(nodes),return;end
            compact=opts.Compact;
            eligible=opts.Eligible;
            eligible=logical(eligible(:)');if numel(eligible)~=numel(nodes),eligible=true(1,numel(nodes));end
            allowSuppression=opts.AllowSuppression;
            if compact,fontSizes=[7.0 6.2 5.5];else,fontSizes=[9.5 8.5 7.5 6.8];end
            strengths=arrayfun(@(n)double(n.absoluteStrength),nodes);
            strengths(~isfinite(strengths))=-Inf;[~,order]=sort(strengths,'descend');
            placed=zeros(0,4);
            for oo=1:numel(order)
                idx=order(oo);if ~eligible(idx),continue;end
                label=nodes(idx).label;
                best=template;bestConflict=Inf;found=false;
                for ff=1:numel(fontSizes)
                    fontSize=fontSizes(ff);
                    for candidateIndex=1:8
                        candidate=NMResultsViewerReportFigureTools.graphReportLabelCandidate(label,x(idx),y(idx),r(idx),fontSize,candidateIndex);
                        conflict=NMResultsViewerReportFigureTools.graphReportLabelConflict(candidate.box,placed,x,y,r,idx,bounds);
                        if conflict<bestConflict
                            best=candidate;bestConflict=conflict;
                        end
                        if conflict<=0
                            best=candidate;found=true;break;
                        end
                    end
                    if found,break;end
                end
                if found||~allowSuppression
                    best.visible=true;plan(idx)=best;placed(end+1,:)=best.box; %#ok<AGROW>
                end
            end
        end

        function candidate = graphReportLabelCandidate(label,x,y,r,fontSize,candidateIndex)
            % graphReportLabelCandidate  Build one halo-expanded graph-label candidate box.
            %
            % Candidate order is right, left, above, below, upper-right, upper-left,
            % lower-right, and lower-left. Width is estimated deterministically from
            % label length and font size because browser text metrics are unavailable in
            % MATLAB's static SVG generator.
            textWidth=max(2.0*fontSize,0.56*fontSize*numel(label));
            textHeight=1.18*fontSize;gap=max(3,0.45*fontSize);halo=1.5;
            anchor='start';tx=x+r+gap;ty=y+0.34*fontSize;
            switch candidateIndex
                case 2
                    anchor='end';tx=x-r-gap;ty=y+0.34*fontSize;
                case 3
                    anchor='middle';tx=x;ty=y-r-gap;
                case 4
                    anchor='middle';tx=x;ty=y+r+gap+fontSize;
                case 5
                    anchor='start';tx=x+r+gap;ty=y-r-gap+0.25*fontSize;
                case 6
                    anchor='end';tx=x-r-gap;ty=y-r-gap+0.25*fontSize;
                case 7
                    anchor='start';tx=x+r+gap;ty=y+r+gap+fontSize;
                case 8
                    anchor='end';tx=x-r-gap;ty=y+r+gap+fontSize;
            end
            if strcmp(anchor,'start'),x1=tx;x2=tx+textWidth;elseif strcmp(anchor,'end'),x1=tx-textWidth;x2=tx;else,x1=tx-textWidth/2;x2=tx+textWidth/2;end
            y1=ty-textHeight;y2=ty+0.24*fontSize;
            candidate=struct('visible',false,'x',tx,'y',ty,'anchor',anchor,'fontSize',fontSize,'box',[x1-halo y1-halo x2+halo y2+halo]);
        end

        function conflict = graphReportLabelConflict(box,placed,x,y,r,selfIndex,bounds)
            % graphReportLabelConflict  Score clipping and overlaps for one label box.
            %
            % Zero denotes a valid non-overlapping candidate. Positive scores combine
            % clipped area, overlap with previously accepted labels, and intersection
            % with node symbols. Label-label conflicts dominate candidate order.
            conflict=0;
            if any(~isfinite(box)),conflict=Inf;return;end
            if box(1)<bounds(1),conflict=conflict+1e5*(bounds(1)-box(1));end
            if box(2)<bounds(2),conflict=conflict+1e5*(bounds(2)-box(2));end
            if box(3)>bounds(3),conflict=conflict+1e5*(box(3)-bounds(3));end
            if box(4)>bounds(4),conflict=conflict+1e5*(box(4)-bounds(4));end
            for ii=1:size(placed,1)
                conflict=conflict+1000*NMResultsViewerReportFigureTools.graphRectangleOverlapArea(box,placed(ii,:));
            end
            for ii=1:numel(x)
                if ii==selfIndex,continue;end
                if NMResultsViewerReportFigureTools.graphBoxCircleOverlap(box,x(ii),y(ii),r(ii)+1.5)
                    conflict=conflict+5000;
                end
            end
        end

        function area = graphRectangleOverlapArea(a,b)
            % graphRectangleOverlapArea  Return intersection area for two SVG boxes.
            width=max(0,min(a(3),b(3))-max(a(1),b(1)));
            height=max(0,min(a(4),b(4))-max(a(2),b(2)));
            area=width*height;
        end

        function tf = graphBoxCircleOverlap(box,cx,cy,radius)
            % graphBoxCircleOverlap  Test whether a label rectangle intersects a node circle.
            qx=min(max(cx,box(1)),box(3));qy=min(max(cy,box(2)),box(4));
            tf=(qx-cx).^2+(qy-cy).^2 < radius.^2;
        end

        function html = compactInlineLegendSvg(x,y,rows,maxWidth)
            % compactInlineLegendSvg  Render a minimal lower-left scientific key.
            %
            % Items use six-pixel swatches or short line samples and 7.5-point text.
            % The key starts at the caller-supplied lower-left panel coordinate and
            % wraps only when necessary. It is deliberately unboxed and has no effect
            % on row selection, axis limits, or threshold semantics.
            html = '';
            if isempty(rows), return; end
            parts = cell(1,0);
            cursorX = x; cursorY = y + 7;
            lineH = 12; gap = 10; swatch = 6;
            for ii=1:size(rows,1)
                label = rows{ii,1};
                col = rows{ii,2};
                dash=rows{ii,3};
                itemType=rows{ii,4};
                itemWidth = 18 + max(28,4.6*numel(label)) + gap;
                if cursorX > x && cursorX + itemWidth > x + maxWidth
                    cursorX = x; cursorY = cursorY + lineH;
                end
                if any(strcmp(itemType,{'point','circle'}))
                    parts{end+1}=sprintf('<circle class="featureBarLegendPoint" cx="%.1f" cy="%.1f" r="3" fill="%s"/>',cursorX+4,cursorY-2.5,col); %#ok<AGROW>
                elseif any(strcmp(itemType,{'line','threshold'}))
                    dashTxt='';if ~isempty(dash),dashTxt=sprintf(' stroke-dasharray="%s"',dash);end
                    parts{end+1}=sprintf('<line class="featureBarLegendLine" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="1.4"%s/>',cursorX,cursorY-2.5,cursorX+11,cursorY-2.5,col,dashTxt); %#ok<AGROW>
                else
                    parts{end+1}=sprintf('<rect class="featureBarLegendSwatch" x="%.1f" y="%.1f" width="%d" height="%d" rx="1" fill="%s"/>',cursorX,cursorY-5.5,swatch,swatch,col); %#ok<AGROW>
                end
                parts{end+1}=sprintf('<text class="featureBarLegendLabel" x="%.1f" y="%.1f" font-size="7.5" fill="#334155">%s</text>',cursorX+15,cursorY,NMResultsViewerReportSvgLayout.escape(label)); %#ok<AGROW>
                cursorX = cursorX + itemWidth;
            end
            html = strjoin(parts,'');
        end

        function html = probabilityPieFallbackSvg(pies)
            %#ok<INUSD>
            html = '<div class="note">Probability distribution payload contains probability pie-chart data, but no score-row histogram payload was exposed for static rendering.</div>';
        end

        function txt = featureInspectionTooltipText(row, valueField, errorField)
            % featureInspectionTooltipText  Compose compact SVG title text for feature bars.
            title = row.tooltipTitle;
            metricLabel = row.tooltipMetricPrimaryLabel;
            v = double(row.(valueField));
            if ~isempty(errorField)
                se = double(row.(errorField));
            else
                se = NaN;
            end
            thr = row.tooltipThresholdLabel;
            kind = row.featureKind;
            parts = {title, sprintf('%s: %s', metricLabel, NMResultsViewerReportSvgLayout.formatNumber(v))};
            if isfinite(se), parts{end+1} = sprintf('SE: %s', NMResultsViewerReportSvgLayout.formatNumber(se)); end %#ok<AGROW>
            if ~isempty(thr) && ~strcmp(thr,'No threshold'), parts{end+1} = ['Threshold: ' thr]; end %#ok<AGROW>
            if ~isempty(kind), parts{end+1} = ['Feature type: ' kind]; end %#ok<AGROW>
            txt = strjoin(parts, newline);
        end

        function txt = shortText(txt, maxChars)
            % shortText  Truncate long biological/feature labels for compact SVG axes.
            txt = regexprep(txt,'\s+',' ');
            if numel(txt) > maxChars
                head = ceil((maxChars-3)*0.58);
                tail = maxChars-head-3;
                txt = [txt(1:head) '...' txt(end-tail+1:end)];
            end
        end

        function [fill, stroke, errColor] = featureMetricBarColor(value, passed, opts)
            subColor = NMResultsViewerReportFigureTools.optionField(opts,'SubthresholdColor','#cbd5e1');
            if ~passed || ~isfinite(value)
                fill = subColor; stroke = subColor; errColor = subColor; return;
            end
            contract = NMResultsViewerReportFigureTools.optionsDisplayContract(opts);
            fill = NMResultsViewerDisplaySemanticsTools.sampleColorHex(value,contract);
            stroke = fill;
            errColor = fill;
        end

        function rows = thresholdLegendRows(metricSpec)
            % thresholdLegendRows  Build user-facing legend rows for metric threshold guide lines.
            rows = cell(0,4);
            vals = NMResultsViewerDisplaySemanticsTools.thresholdValues(metricSpec.DisplayContract);
            vals = vals(isfinite(vals));
            if isempty(vals), return; end
            label = NMResultsViewerReportFigureTools.thresholdLegendLabel(metricSpec);
            if isempty(label), return; end
            rows = {label, '#dc2626', '5 3', 'line'};
        end

        function label = thresholdLegendLabel(metricSpec)
            % thresholdLegendLabel  Summarize a threshold in one compact legend entry.
            label = '';
            contract = NMResultsViewerReportFigureTools.optionsDisplayContract(metricSpec);
            mode = contract.threshold.mode;
            values = NMResultsViewerDisplaySemanticsTools.thresholdValues(metricSpec.DisplayContract);
            if strcmp(mode,'none'), return; end
            raw = metricSpec.ThresholdLabel;
            if ~isempty(strtrim(raw)) && ~strcmpi(strtrim(raw),'No threshold')
                label = raw;
            elseif strcmp(mode,'above_abs')
                label = ['|metric| >= ' NMResultsViewerReportSvgLayout.formatNumber(values(2))];
            elseif strcmp(mode,'above')
                label = ['metric >= ' NMResultsViewerReportSvgLayout.formatNumber(values(1))];
            elseif strcmp(mode,'below')
                label = ['metric <= ' NMResultsViewerReportSvgLayout.formatNumber(values(1))];
            elseif strcmp(mode,'outside_interval')
                label = ['outside [' NMResultsViewerReportSvgLayout.formatNumber(values(1)) ', ' NMResultsViewerReportSvgLayout.formatNumber(values(2)) ']'];
            end
            label = strrep(label, '-log10(P) >= -log10(0.05)', 'P <= 0.05');
            label = strrep(label, '-log10(q) >= -log10(0.05)', 'q <= 0.05');
            label = strrep(label, '|cross-validation ratio| >= 2', '|CVR| >= 2');
            label = strrep(label, '|reliability probability| >= 0.5', '|reliability| >= 0.5');
            label = strrep(label, '>=', '≥');
            label = strrep(label, '<=', '≤');
            label = ['Cutoff: ' label];
        end

        function rows = uniqueLegendRows(rowsIn)
            % uniqueLegendRows  Keep legend entries unique while preserving order.
            rows = cell(0,4);
            if isempty(rowsIn), return; end
            seen = {};
            for ii = 1:size(rowsIn,1)
                key = rowsIn{ii,1};
                if isempty(key) || any(strcmp(seen,key)), continue; end
                seen{end+1} = key; %#ok<AGROW>
                rows(end+1,1:4) = rowsIn(ii,1:4); %#ok<AGROW>
            end
        end

        function html = featureMetricVerticalThresholdLinesSvg(metricSpec, xLim, left, top, plotW, plotH)
            html = '';
            vals = NMResultsViewerDisplaySemanticsTools.thresholdValues(metricSpec.displayContract);
            if isempty(vals), return; end
            parts = cell(1,0);
            for ii = 1:numel(vals)
                v = vals(ii);
                if ~isfinite(v) || v < min(xLim) || v > max(xLim), continue; end
                x = NMResultsViewerReportSvgLayout.mapX(v, xLim, left, plotW);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#dc2626" stroke-width="1.3" stroke-dasharray="5 3"/>', x, top, x, top+plotH); %#ok<AGROW>
            end
            html = strjoin(parts,'');
        end

        function html = featureMetricHorizontalThresholdLinesSvg(metricSpec, yLim, left, top, plotW, plotH)
            html = '';
            vals = NMResultsViewerDisplaySemanticsTools.thresholdValues(metricSpec.displayContract);
            if isempty(vals), return; end
            parts = cell(1,0);
            for ii = 1:numel(vals)
                v = vals(ii);
                if ~isfinite(v) || v < min(yLim) || v > max(yLim), continue; end
                y = NMResultsViewerReportSvgLayout.mapY(v, yLim, top, plotH);
                parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#dc2626" stroke-width="1.3" stroke-dasharray="5 3"/>', left, y, left+plotW, y); %#ok<AGROW>
            end
            html = strjoin(parts,'');
        end

        function contract = optionsDisplayContract(opts)
            % optionsDisplayContract  Read the report-options display contract.
            contract = opts.DisplayContract;
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
        end

        function contract = metricDisplayContract(metricSpec)
            % metricDisplayContract  Read the canonical metric descriptor contract.
            contract = metricSpec.displayContract;
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
        end

        function html = featureMetricThresholdLinesSvg(opts, lim, left, top, plotW, plotH, transposeAxes)
            % featureMetricThresholdLinesSvg  Render threshold guide lines for selected feature metric axes.
            html = '';
            vals = NMResultsViewerDisplaySemanticsTools.thresholdValues(opts.DisplayContract);
            vals = vals(isfinite(vals));
            if isempty(vals), return; end
            parts = cell(1,0);
            for ii=1:numel(vals)
                if vals(ii) <= lim(1) || vals(ii) >= lim(2), continue; end
                if transposeAxes
                    yy = NMResultsViewerReportSvgLayout.mapY(vals(ii),lim,left,plotW);
                    parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#dc2626" stroke-dasharray="5 3" stroke-width="1.3"/>', top, yy, top+plotH, yy); %#ok<AGROW>
                else
                    xx = NMResultsViewerReportSvgLayout.mapX(vals(ii),lim,left,plotW);
                    parts{end+1} = sprintf('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#dc2626" stroke-dasharray="5 3" stroke-width="1.3"/>', xx, top, xx, top+plotH); %#ok<AGROW>
                end
            end
            html = strjoin(parts,'');
        end




        function lim = paddedLim(vals, signedAroundZero)
            % paddedLim  Compute a stable padded axis limit for report figures.
            vals = vals(isfinite(vals));
            if isempty(vals), lim = [0 1]; return; end
            if signedAroundZero && min(vals) < 0 && max(vals) > 0
                m = max(abs(vals)); if m < 1e-12, m = 1; end
                lim = [-1.08*m 1.08*m]; return;
            end
            lo = min(vals); hi = max(vals);
            if abs(hi-lo) < 1e-12, lo = lo - 0.5; hi = hi + 0.5; end
            pad = 0.08*(hi-lo);
            lim = [lo-pad hi+pad];
            if all(vals >= 0), lim(1) = min(0, lim(1)); end
        end

        function txt = relationshipTooltipText(row, xLabel, yLabel)
            % relationshipTooltipText  Tooltip for generic feature metric relationship points.
            name = row.featureName;
            xv = double(row.xValue);
            yv = double(row.yValue);
            xp = logical(row.xThresholdPassed);
            yp = logical(row.yThresholdPassed);
            prov = row.tooltipProvenanceSummary;
            parts = {name, [xLabel ': ' NMResultsViewerReportSvgLayout.formatNumber(xv)], [yLabel ': ' NMResultsViewerReportSvgLayout.formatNumber(yv)], ...
                ['X threshold: ' mat2str(xp)], ['Y threshold: ' mat2str(yp)]};
            if ~isempty(prov), parts{end+1} = ['Provenance: ' prov]; end %#ok<AGROW>
            txt = strjoin(parts, newline);
        end


        function M = matrixPayloadValues(payload)
            % matrixPayloadValues  Reconstruct the fixed H12 row-cell matrix representation.
            M = [];
            if ~isscalar(payload)
                error('NMResultsViewer:InvalidMatrixPayload', ...
                    'matrixPayloadValues requires one scalar canonical matrix payload.');
            end
            raw = payload.values;
            if isempty(raw), return; end
            nRows = length(raw);
            nCols = length(raw{1});
            M = NaN(nRows,nCols);
            for rr=1:nRows
                row = double(raw{rr});
                if length(row) ~= nCols
                    error('NMResultsViewer:InvalidMatrixPayload', ...
                        'Canonical matrix row %d has %d values; expected %d.', rr, length(row), nCols);
                end
                M(rr,:) = row(:)';
            end
        end

        function svg = displayContractColorbarSvg(x,y,w,h,contract)
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            n=96;
            parts=cell(1,n+4);
            for ii=1:n
                coordinate=1-(ii-1)/(n-1);
                color=NMResultsViewerDisplaySemanticsTools.sampleColorCoordinateHex(coordinate,contract);
                yy=y+(ii-1)*h/n;
                parts{ii}=sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s"/>',x,yy,w,h/n+0.25,color);
            end
            lower=contract.shownRange.lower; upper=contract.shownRange.upper;
            parts{n+1}=sprintf('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#475569" stroke-width="0.6"/>',x,y,w,h);
            parts{n+2}=sprintf('<text x="%.2f" y="%.2f" font-size="8.5" fill="#334155">%.4g</text>',x+w+5,y+8,upper);
            parts{n+3}=sprintf('<text x="%.2f" y="%.2f" font-size="8.5" fill="#334155">%.4g</text>',x+w+5,y+h,lower);
            parts{n+4}='';
            svg=strjoin(parts,'');
        end

        function hex = sequentialEvidenceHex(v, lim)
            % sequentialEvidenceHex  Map one nonnegative evidence value to the report colour scale.
            %
            % Syntax:
            %   hex = NMResultsViewerReportFigureTools.sequentialEvidenceHex(v,lim)
            %
            % Inputs:
            %   v    Numerical evidence-layer value.
            %   lim  Two-element finite display range.
            %
            % Outputs:
            %   hex  Deterministic white-to-purple hexadecimal colour.
            %
            % Scientific contract:
            %   This is presentation-only. It does not transform, threshold, or rank evidence.
            %
            % Invariants and mutability:
            %   Values are clamped to the supplied display range; inputs are not mutated.
            %
            % Errors and diagnostics:
            %   Invalid ranges use [0,1].
            %
            % Side effects:
            %   None.
            if ~all(isfinite(lim))||lim(2)<=lim(1),lim=[0 1];end
            t=max(0,min(1,(double(v)-lim(1))/(lim(2)-lim(1))));
            hex=NMResultsViewerReportFigureTools.mixHex('#ffffff','#7e22ce',0.12+0.82*t);
        end

        function html = sequentialColorbarSvg(x,y,w,h,lo,hi)
            % sequentialColorbarSvg  Render the numerical colour bar for a nonnegative evidence layer.
            %
            % Syntax:
            %   html = NMResultsViewerReportFigureTools.sequentialColorbarSvg(x,y,w,h,lo,hi)
            %
            % Inputs:
            %   x,y,w,h  SVG geometry.
            %   lo,hi    Numerical scale endpoints.
            %
            % Outputs:
            %   html  SVG rectangles, border, and endpoint labels.
            %
            % Scientific contract:
            %   The colour bar explains matrix cell fill only and is independent of the
            %   discrete relation-pattern legend.
            %
            % Invariants and mutability:
            %   Endpoint labels preserve the supplied numerical scale; inputs are read-only.
            %
            % Errors and diagnostics:
            %   Range normalization is delegated to sequentialEvidenceHex.
            %
            % Side effects:
            %   None.
            parts=cell(1,0);n=36;
            for ii=1:n
                t=1-(ii-1)/(n-1);col=NMResultsViewerReportFigureTools.sequentialEvidenceHex(lo+t*(hi-lo),[lo hi]);yy=y+(ii-1)*h/n;
                parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="none"/>',x,yy,w,h/n+0.5,col); %#ok<AGROW>
            end
            parts{end+1}=sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#94a3b8"/><text x="%.1f" y="%.1f" font-size="8" fill="#475569">%s</text><text x="%.1f" y="%.1f" font-size="8" fill="#475569">%s</text>',x,y,w,h,x+w+4,y+8,NMResultsViewerReportSvgLayout.formatNumber(hi),x+w+4,y+h,NMResultsViewerReportSvgLayout.formatNumber(lo));
            html=strjoin(parts,'');
        end

        function hex = patternHex(patternId)
            % patternHex  Resolve a deterministic discrete outline colour for relation-pattern identity.
            %
            % Syntax:
            %   hex = NMResultsViewerReportFigureTools.patternHex(patternId)
            %
            % Inputs:
            %   patternId  Positive graph-local relation-pattern identifier.
            %
            % Outputs:
            %   hex  Reproducible high-contrast hexadecimal outline colour.
            %
            % Scientific contract:
            %   Pattern colour encodes membership only; it never replaces relation-value
            %   colour or implies continuity between graph reconstructions.
            %
            % Invariants and mutability:
            %   IDs cycle through a fixed palette without mutating graph state.
            %
            % Errors and diagnostics:
            %   Non-positive or non-integer values are normalized to the first palette entry.
            %
            % Side effects:
            %   None.
            palette={'#7c3aed','#0891b2','#ea580c','#16a34a','#db2777','#4f46e5','#ca8a04','#0f766e','#be123c','#6d28d9','#0369a1','#65a30d'};
            idx=mod(max(1,round(double(patternId)))-1,numel(palette))+1;hex=palette{idx};
        end

        function v = clamp01(v)
            % clamp01  Bound one backend layout coordinate to the normalized SVG viewport.
            %
            % Syntax:
            %   v = NMResultsViewerReportFigureTools.clamp01(v)
            %
            % Inputs:
            %   v  Candidate scalar layout coordinate.
            %
            % Outputs:
            %   v  Finite scalar in [0,1].
            %
            % Scientific contract:
            %   Clamping protects rendering geometry; it does not rerun or optimize layout.
            %
            % Invariants and mutability:
            %   The returned coordinate is finite and bounded; graph state is not mutated.
            %
            % Errors and diagnostics:
            %   Invalid values resolve to the neutral coordinate 0.5.
            %
            % Side effects:
            %   None.
            v=max(0,min(1,double(v)));
        end

        function suffix = graphPatternSuffix(patternId)
            % graphPatternSuffix  Format the graph-local pattern identity for a report footer.
            %
            % Syntax:
            %   suffix = NMResultsViewerReportFigureTools.graphPatternSuffix(patternId)
            %
            % Inputs:
            %   patternId  Zero for the full graph or a positive local pattern ID.
            %
            % Outputs:
            %   suffix  Empty text for the full graph or a Pattern N suffix.
            %
            % Scientific contract:
            %   The suffix identifies the current graph slice and makes no cross-graph claim.
            %
            % Invariants and mutability:
            %   Formatting is deterministic and does not alter graph identity or pattern state.
            %
            % Errors and diagnostics:
            %   Zero or negative IDs return empty text.
            %
            % Side effects:
            %   None.
            if patternId>0,suffix=sprintf(' · Pattern %d',round(patternId));else,suffix='';end
        end

        function hex = divergingHex(v, lim)
            % divergingHex  Blue-white-red diverging color for signed feature matrices.
            if ~isfinite(lim) || lim <= 0, lim = 1; end
            t = max(-1,min(1,double(v)./lim));
            if t >= 0
                hex = NMResultsViewerReportFigureTools.mixHex('#ffffff','#dc2626',0.18 + 0.74*t);
            else
                hex = NMResultsViewerReportFigureTools.mixHex('#ffffff','#2563eb',0.18 + 0.74*abs(t));
            end
        end

        function html = divergingColorbarSvg(x,y,w,h,lo,hi)
            % divergingColorbarSvg  Render a signed blue-white-red colorbar.
            parts = cell(1,0); n = 36; lim = max(abs([lo hi])); if lim <= 0, lim = 1; end
            for ii=1:n
                t = 1 - 2*(ii-1)/(n-1);
                col = NMResultsViewerReportFigureTools.divergingHex(t*lim, lim);
                yy = y + (ii-1)*h/n;
                parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" stroke="none"/>', x, yy, w, h/n+0.5, col); %#ok<AGROW>
            end
            parts{end+1} = sprintf('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="none" stroke="#94a3b8"/><text x="%.1f" y="%.1f" font-size="8" fill="#475569">%s</text><text x="%.1f" y="%.1f" font-size="8" fill="#475569">0</text><text x="%.1f" y="%.1f" font-size="8" fill="#475569">%s</text>', x,y,w,h,x+w+4,y+8,NMResultsViewerReportSvgLayout.formatNumber(hi),x+w+4,y+h/2+3,x+w+4,y+h,NMResultsViewerReportSvgLayout.formatNumber(lo));
            html = strjoin(parts,'');
        end

        function v = percentileValue(valsSorted, pct)
            % percentileValue  Dependency-free percentile interpolation for compact report statistics.
            valsSorted = double(valsSorted(:));
            valsSorted = valsSorted(isfinite(valsSorted));
            if isempty(valsSorted), v = NaN; return; end
            if numel(valsSorted) == 1, v = valsSorted(1); return; end
            p = max(0,min(100,double(pct))) ./ 100;
            pos = 1 + (numel(valsSorted)-1) .* p;
            lo = floor(pos); hi = ceil(pos);
            if lo == hi
                v = valsSorted(lo);
            else
                v = valsSorted(lo) + (pos-lo) .* (valsSorted(hi)-valsSorted(lo));
            end
        end

        function hex = mixHex(a,b,t)
            t = max(0,min(1,double(t)));
            av = sscanf(a(2:end),'%2x%2x%2x',[1 3]); bv = sscanf(b(2:end),'%2x%2x%2x',[1 3]);
            cv = round((1-t).*double(av) + t.*double(bv));
            hex = sprintf('#%02x%02x%02x', cv(1), cv(2), cv(3));
        end

    end
end
