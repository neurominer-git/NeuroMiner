(function(root){
  'use strict';

  /** Create one browser Model Optimization controller bound to the Results Viewer runtime authorities. */
  function create(dependencies){
    const deps=dependencies&&typeof dependencies==='object'?dependencies:{};
    ['getPayload','activeScientificStateHas','arr','el','esc','fmtMatrixCell','fmtMetric','fmtTick','niceTicks','plotTools','profileLog','tableHtml','workspace','onContentChanged'].forEach(name=>{if(typeof deps[name]!=='function')throw new Error(`NMResultsViewerModelOptimization requires dependency ${name}.`);});
    const {getPayload:currentPayload,activeScientificStateHas,arr,el,esc,fmtMatrixCell,fmtMetric,fmtTick,niceTicks,plotTools,profileLog,tableHtml,workspace,onContentChanged}=deps;
    let MODEL_OPT_SELECTED_INDEX=0,MODEL_OPT_MATRIX_VIEW='matrix',MODEL_OPT_DASHBOARD_METRIC_IDS=[];
    const SEQUENCE_DIAGNOSTIC_VIEW={scope:'CV2', cohort:0, sequenceKey:'', group:'performance', metrics:['criterion','sens','spec']};
    const MODEL_OPT_SURFACE_STATE={metricId:'',seriesIndex:0,xParam:0,yParam:1,aggregation:'mean'};
    const MODEL_OPT_COMPARISON_STATE={xMetricId:'',xSeriesIndex:0,yMetricId:'',ySeriesIndex:0,paretoMode:'exact'};
    const MODEL_OPT_COMPARISON_CACHE={payload:null,metric:new WeakMap(),pair:new Map(),pareto:new Map()};

    /**
     * modelOptimizationNumericValue  Decode one JSON numeric value without converting missing MATLAB values to zero.
     * MATLAB NaN values reach the browser as JSON null; null/undefined/empty values therefore remain NaN, while legitimate numeric zero is preserved.
     */
    function modelOptimizationNumericValue(raw){
      if(raw === null || raw === undefined || raw === '') return NaN;
      const value = Number(raw);
      return Number.isFinite(value) ? value : NaN;
    }

    /**
     * modelOptimizationMatrix  Normalize a JSON-decoded metric or partition matrix.
     * It preserves missing/unvisited optimization entries as NaN so plots, surfaces and comparisons cannot reinterpret JSON null as a measured zero.
     */
    function modelOptimizationMatrix(raw){
      if(raw == null) return [];
      if(Array.isArray(raw)){
        if(!raw.length) return [];
        if(Array.isArray(raw[0])) return raw.map(r => arr(r).map(modelOptimizationNumericValue));
        return raw.map(v => [modelOptimizationNumericValue(v)]);
      }
      const x = modelOptimizationNumericValue(raw);
      return Number.isFinite(x) ? [[x]] : [];
    }

    /**
     * modelOptimizationContiguousSegments  Split sampled optimization values at missing parameter-combination indices.
     * The original one-based x coordinates are retained and no segment is allowed to bridge an unvisited combination.
     */
    function modelOptimizationContiguousSegments(samples){
      const segments = [];
      let current = [];
      arr(samples).forEach(sample => {
        if(sample){
          current.push(sample);
        }else if(current.length){
          segments.push(current);
          current = [];
        }
      });
      if(current.length) segments.push(current);
      return segments;
    }

    /**
     * modelOptimizationSeriesGeometry  Build finite points plus gap-aware line and uncertainty-band segments for one optimization series.
     * Missing performance values break both the line and uncertainty band; missing SEM values break only the band.
     */
    function modelOptimizationSeriesGeometry(values, sem, seriesIndex){
      const points = [];
      const lineSamples = [];
      const bandSamples = [];
      for(let i=0;i<values.length;i++){
        const y = modelOptimizationNumericValue(values[i] && values[i][seriesIndex]);
        const x = i + 1;
        if(Number.isFinite(y)){
          const point = {x,y,index:x};
          points.push(point);
          lineSamples.push(point);
          const se = modelOptimizationNumericValue(sem[i] && sem[i][seriesIndex]);
          bandSamples.push(Number.isFinite(se) ? {x,y0:y-Math.abs(se),y1:y+Math.abs(se),index:x} : null);
        }else{
          lineSamples.push(null);
          bandSamples.push(null);
        }
      }
      return {
        points,
        lineSegments:modelOptimizationContiguousSegments(lineSamples),
        bandSegments:modelOptimizationContiguousSegments(bandSamples)
      };
    }

    /**
     * selectedModelOptimizationMetric  Resolve the currently selected optimization metric.
     * It reads the Optimization metric selector and falls back to the first available metric so invalid UI states do not produce empty silent plots.
     */
    function selectedModelOptimizationMetric(){
      const metrics = arr(currentPayload() && currentPayload().metrics);
      const sel = el('yAxisSelect');
      const requested = sel ? Math.round(Number(sel.value || 0)) : 0;
      if(requested >= 1 && requested <= metrics.length && metrics[requested-1] && metrics[requested-1].available) return metrics[requested-1];
      return metrics.find(m => m && m.available) || metrics[0] || null;
    }

    /**
     * modelOptimizationMetricColumns  Return table columns for optimization metric availability.
     * It keeps the Stage 2 model-optimization table read-only and aligned with the backend metric registry.
     */
    function modelOptimizationMetricColumns(){
      return [
        {key:'metric',label:'Metric'},
        {key:'value',label:'Availability'},
        {key:'source',label:'Source'}
      ];
    }

    /**
     * modelOptimizationGridColumns  Return table columns for parameter-combination metadata.
     * It shows legacy GDdims.Model parameter rows without trying to reinterpret hyperparameter semantics in the browser.
     */
    function modelOptimizationGridColumns(){
      return [
        {key:'index',label:'Index'},
        {key:'label',label:'Model'},
        {key:'parameters',label:'Parameters'},
        {key:'firstMetric',label:'First metric'},
        {key:'firstValue',label:'Value'}
      ];
    }

    /**
     * modelOptimizationSeriesLabels  Resolve plotted series labels for a metric.
     * It preserves backend labels where available and creates only local generic labels for unlabeled extra numeric columns.
     */
    function modelOptimizationSeriesLabels(metric, nSeries){
      const labels = arr(metric && metric.seriesLabels).map(x => String(x || '')).filter(Boolean);
      while(labels.length < nSeries) labels.push(labels.length ? `Series ${labels.length + 1}` : String(metric && metric.label || 'Metric'));
      return labels.slice(0, nSeries);
    }

    /**
     * modelOptimizationPointTooltipText  Compose legacy-style hover text for one optimization-grid point.
     * It uses only the Stage 1/2 model-optimization payload fields and reports SEM/error-band bounds when available without recomputing optimization statistics.
     * metric.label: selected optimization metric label.
     * row.tooltip: backend parameter-combination description shown as the final tooltip detail when available.
     */
    function modelOptimizationPointTooltipText(metric, seriesLabel, modelIndex, value, semValue, row){
      const lines = [];
      lines.push(String(seriesLabel || metric && metric.label || 'Optimization metric'));
      lines.push(`Metric: ${String(metric && metric.label || 'Optimization metric')}`);
      lines.push(`Model index: ${modelIndex}`);
      lines.push(`Value: ${fmtMetric(value,4)}`);
      const se = Number(semValue);
      if(Number.isFinite(se)){
        const d = Math.abs(se);
        lines.push(`SEM/error: ${fmtMetric(d,4)}`);
        lines.push(`Band: ${fmtMetric(Number(value)-d,4)} – ${fmtMetric(Number(value)+d,4)}`);
      }
      const ctx = currentPayload() && currentPayload().context || {};
      const source = currentPayload() && (currentPayload().subtitle || currentPayload().modelSourceLabel) || ctx.modelSourceLabel || '';
      if(source) lines.push(`Source: ${source}`);
      if(ctx.classifierLabel) lines.push(`Learner: ${ctx.classifierLabel}`);
      if(ctx.targetLabel) lines.push(`Target: ${ctx.targetLabel}`);
      if(row && row.tooltip) lines.push(String(row.tooltip));
      return lines.join('\n');
    }

    /**
     * modelOptimizationDensePlotStyle  Scale marker radius and line width for dense optimization grids.
     * It follows the legacy Results Viewer convention that parameter-grid plots with many combinations should use smaller symbols and thinner lines so hover inspection remains usable and adjacent CV1/CV2 series are visually separable.
     * Visible points are rendered above transparent hit targets so a hovered marker keeps its own series-specific tooltip even when another series has a nearby hit target.
     * nRows: number of legacy parameter-combination rows displayed on the x-axis.
     */
    function modelOptimizationDensePlotStyle(nRows, plotWidth){
      const n = Math.max(1, Number(nRows) || 1);
      const widthPx = Math.max(1, Number(plotWidth) || 1);
      const pointSpacing = widthPx / Math.max(1, n - 1);
      const lineWidth = Math.max(0.22, Math.min(2.6, 0.75 * Math.sqrt(pointSpacing)));
      if(n > 3000) return {radius:0.75,lineWidth,hitRadius:3.0};
      if(n > 1800) return {radius:0.9,lineWidth,hitRadius:3.1};
      if(n > 1200) return {radius:1.05,lineWidth,hitRadius:3.2};
      if(n > 700) return {radius:1.35,lineWidth,hitRadius:3.8};
      if(n > 400) return {radius:1.7,lineWidth,hitRadius:4.4};
      if(n > 200) return {radius:2.2,lineWidth,hitRadius:5.0};
      if(n > 100) return {radius:2.8,lineWidth,hitRadius:5.6};
      return {radius:3.4,lineWidth,hitRadius:6.2};
    }

    /**
     * modelOptimizationSegmentSvg  Render one complete visited run with explicit topology metadata.
     * The segment contains only consecutive original parameter-combination indices. Butt line caps
     * prevent the visual stroke from bridging a subpixel missing-combination gap in dense plots.
     */
    function modelOptimizationSegmentSvg(segment, ax, className, lineWidth){
      const pts = arr(segment);
      if(pts.length < 2) return '';
      const pointText = pts.map(p => `${ax.xPix(p.x).toFixed(2)},${ax.yPix(p.y).toFixed(2)}`).join(' ');
      return `<polyline class="${esc(className || '')}" data-index-start="${esc(pts[0].index)}" data-index-end="${esc(pts[pts.length-1].index)}" points="${esc(pointText)}" style="fill:none;stroke-width:${Number(lineWidth).toFixed(3)};stroke-linecap:butt;stroke-linejoin:round;shape-rendering:geometricPrecision"/>`;
    }

    /**
     * modelOptimizationPointAttributes  Build SVG attributes shared by visible and hover-hit optimization markers.
     * metricId: stable metric identifier used to avoid highlighting both CV1 and CV2 markers for the same metric when only one series is hovered.
     * seriesIndex: one-based series index from the plotted metric values.
     */
    function modelOptimizationPointAttributes(metricId, modelIndex, seriesIndex, tooltipText){
      return `data-rv-index="${esc(modelIndex)}" data-rv-series="${esc(seriesIndex)}" data-rv-metric="${esc(metricId || '')}" data-rv-tooltip="${esc(tooltipText || '')}"`;
    }

    /**
     * showModelOptimizationTooltip  Position and fill the optimization-plot hover box.
     * It updates only browser DOM state and keeps the payload and NM result structures read-only.
     */
    function showModelOptimizationTooltip(container, target, evt){
      const tip = container && container.querySelector('.rvModelOptTooltip');
      if(!tip || !target) return;
      const text = String(target.getAttribute('data-rv-tooltip') || '');
      if(!text) return;
      const lines = text.split(/\n/);
      const title = lines.shift() || 'Optimization point';
      tip.innerHTML = `<div class="rvModelOptTooltipTitle">${esc(title)}</div>${lines.map(x => `<div>${esc(x)}</div>`).join('')}`;
      const rect = container.getBoundingClientRect();
      const x = Math.max(8, Math.min(rect.width - 260, (evt && evt.clientX ? evt.clientX - rect.left : 12) + 14));
      const y = Math.max(8, Math.min(rect.height - 110, (evt && evt.clientY ? evt.clientY - rect.top : 12) + 14));
      tip.style.left = `${x}px`;
      tip.style.top = `${y}px`;
      tip.classList.add('isVisible');
    }

    /**
     * bindModelOptimizationTooltip  Attach hover handlers to optimization plot points.
     * It provides legacy-equivalent point inspection for the Stage 2/3 optimization plot and highlights the same parameter-combination index across series.
     * Side effects: adds event listeners and transient CSS classes to SVG point elements.
     */
    function bindModelOptimizationTooltip(container){
      bindModelOptimizationPointSet(container, '.rvModelOptPointHit,.rvModelOptPoint');
    }

    /**
     * renderModelOptimizationPlot  Render the selected metric over the legacy parameter grid.
     * It uses the shared NMResultsPlotD3 cartesian-axis, line and area helpers and does not compute new optimization statistics.
     */
    function renderModelOptimizationPlot(){
      const renderStartedAt = performance.now();
      const node = el('modelOptimizationPlot');
      if(!node) return;
      const metric = selectedModelOptimizationMetric();
      if(!currentPayload() || currentPayload().ok === false){
        node.innerHTML = `<div class="rvEmpty">${esc(currentPayload() && currentPayload().message || 'Model optimization payload unavailable.')}</div>`;
        return;
      }
      if(!metric || !metric.available){
        node.innerHTML = `<div class="rvEmpty">${esc(metric && metric.missingReason || 'No available optimization metric for the selected model source.')}</div>`;
        return;
      }
      if(metric.plotKind === 'sequence_curve'){
        const grid=currentPayload().grid;
        const chooser=Number(grid.nCombinations)>1?`<label class="rvModelOptSequenceTopPicker">CV2 combination <select data-rv-sequence-combination><option value="">Select a combination</option>${arr(grid.parameterRows).map((row,i)=>`<option value="${i+1}"${MODEL_OPT_SELECTED_INDEX===i+1?' selected':''}>${esc(row.label)} · ${esc(row.tooltip)}</option>`).join('')}</select></label>`:'';
        const ready=Number(grid.nCombinations)===1||MODEL_OPT_SELECTED_INDEX>0;
        node.innerHTML=chooser+(ready?renderModelOptimizationSequenceStageSvg(metric):'<div class="rvPanelNotice">Select a hyperparameter combination to display its stage-wise SEQOPT diagnostic metrics.</div>');
        bindModelOptimizationSequenceCombination(node);
        if(ready) bindModelOptimizationSequenceControls(node);
        return;
      }
      const decodeStartedAt = performance.now();
      const values = modelOptimizationMatrix(metric.values);
      if(!values.length){
        node.innerHTML = `<div class="rvEmpty">Selected optimization metric has no numeric values.</div>`;
        return;
      }
      const sem = modelOptimizationMatrix(metric.sem);
      profileLog('model optimization selected decode', decodeStartedAt, `rows=${values.length}`);
      const nRows = values.length;
      const nSeries = values.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      const labels = modelOptimizationSeriesLabels(metric, nSeries);
      const metricKey = metric && (metric.id || metric.label) || 'selected_metric';
      let yVals = [];
      for(let i=0;i<nRows;i++){
        for(let j=0;j<nSeries;j++){
          const y = modelOptimizationNumericValue(values[i] && values[i][j]);
          const se = modelOptimizationNumericValue(sem[i] && sem[i][j]);
          if(Number.isFinite(y)) yVals.push(y);
          if(Number.isFinite(y) && Number.isFinite(se)){ yVals.push(y - Math.abs(se), y + Math.abs(se)); }
        }
      }
      yVals = yVals.filter(Number.isFinite);
      if(!yVals.length){
        node.innerHTML = `<div class="rvEmpty">Selected optimization metric contains no finite values.</div>`;
        return;
      }
      let yMin = Math.min(...yVals), yMax = Math.max(...yVals);
      if(Math.abs(yMax - yMin) < 1e-12){ yMin -= 0.5; yMax += 0.5; }
      else { const pad = (yMax - yMin) * 0.08; yMin -= pad; yMax += pad; }
      const w = 1180, h = 560;
      const denseStyle = modelOptimizationDensePlotStyle(nRows, w - 88 - 28);
      const ax = plotTools().cartesianAxes({w,h,m:{left:88,right:28,top:30,bottom:72},xLim:[1,Math.max(1,nRows)],yLim:[yMin,yMax],xTicks:niceTicks(1,Math.max(1,nRows),Math.min(8,nRows)),yTicks:niceTicks(yMin,yMax,6),xFmt:v => String(Math.round(Number(v))),yFmt:fmtTick,xLabel:metric.xLabel || 'Parameter-combination index',yLabel:metric.yLabel || metric.label || 'Metric',autoMargin:true});
      const P = plotTools();
      const seriesSvg = [];
      const hitSvg = [];
      const pointSvg = [];
      const legendRows = [];
      const geometryStartedAt = performance.now();
      let segmentCount = 0;
      let pointCount = 0;
      for(let j=0;j<nSeries;j++){
        const geometry = modelOptimizationSeriesGeometry(values, sem, j);
        segmentCount += geometry.lineSegments.length;
        pointCount += geometry.points.length;
        geometry.bandSegments.forEach(segment => {
          seriesSvg.push(P.areaElement(segment, p => ax.xPix(p.x), p => ax.yPix(p.y0), p => ax.yPix(p.y1), `rvModelOptBand rvModelOptSeries${j%6}`));
        });
        geometry.lineSegments.forEach(segment => {
          seriesSvg.push(modelOptimizationSegmentSvg(segment, ax, `rvModelOptLine rvModelOptSeries${j%6}`, denseStyle.lineWidth));
        });
        geometry.points.forEach(p => {
          const row = currentPayload().grid && currentPayload().grid.parameterRows && currentPayload().grid.parameterRows[p.index-1] ? currentPayload().grid.parameterRows[p.index-1] : null;
          const se = modelOptimizationNumericValue(sem[p.index-1] && sem[p.index-1][j]);
          const tip = modelOptimizationPointTooltipText(metric, labels[j], p.index, p.y, se, row);
          const attrs = modelOptimizationPointAttributes(metricKey, p.index, j+1, tip);
          const cx = ax.xPix(p.x).toFixed(1);
          const cy = ax.yPix(p.y).toFixed(1);
          hitSvg.push(`<circle class="rvModelOptPointHit" cx="${cx}" cy="${cy}" r="${denseStyle.hitRadius.toFixed(1)}" tabindex="0" ${attrs}></circle>`);
          pointSvg.push(`<circle class="rvModelOptPoint rvModelOptSeries${j%6}" cx="${cx}" cy="${cy}" r="${denseStyle.radius.toFixed(1)}" ${attrs}></circle>`);
        });
        legendRows.push(`<span class="rvModelOptLegendItem rvModelOptSeries${j%6}"><i></i>${esc(labels[j])}</span>`);
      }
      profileLog('model optimization selected geometry', geometryStartedAt, `series=${nSeries} segments=${segmentCount} points=${pointCount}`);
      const subtitle = currentPayload().subtitle || (currentPayload().context && currentPayload().context.modelSourceLabel) || '';
      const domStartedAt = performance.now();
      node.innerHTML = `<div class="rvModelOptPlotTitle"><strong>${esc(metric.label || 'Optimization metric')}</strong><span>${esc(subtitle)}</span></div><svg class="rvSvg rvModelOptSvg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="${esc(metric.label || 'Model optimization metric')}">${ax.svg}<g class="rvModelOptSeriesLayer">${seriesSvg.join('')}</g><g class="rvModelOptHitLayer">${hitSvg.join('')}</g><g class="rvModelOptPointLayer">${pointSvg.join('')}</g></svg><div class="rvModelOptTooltip" role="status" aria-live="polite"></div><div class="rvModelOptLegend">${legendRows.join('')}</div>`;
      profileLog('model optimization selected DOM', domStartedAt, `svgPoints=${pointCount} hitTargets=${pointCount}`);
      const bindStartedAt = performance.now();
      bindModelOptimizationTooltip(node);
      profileLog('model optimization selected bind', bindStartedAt, `points=${pointCount}`);
      profileLog('model optimization selected TOTAL', renderStartedAt, `rows=${nRows} series=${nSeries}`);
    }

    /**
     * modelOptimizationAvailablePanelMetrics  Select optimization metrics for the concurrent dashboard.
     * It keeps Stage 4 bounded by using the backend metric registry and filtering to metrics that have finite values on the current parameter grid.
     * metric.supportsPanel: browser-side field consumed from the model-optimization metric registry when deciding if a metric belongs in the dashboard.
     */
    function modelOptimizationAvailablePanelMetrics(){
      if(!activeScientificStateHas('visualization','optimization_metric_dashboard')) return [];
      return arr(currentPayload() && currentPayload().metrics).filter(m => {
        if(!m || !m.available || m.supportsPanel === false) return false;
        const mat = modelOptimizationMatrix(m.values);
        return m.plotKind === 'sequence_curve' || mat.some(r => arr(r).some(v => Number.isFinite(Number(v))));
      });
    }

    /**
     * setModelOptimizationLinkedIndex  Highlight the same parameter-combination index across optimization plots.
     * It updates only transient browser classes and the Stage 4 dashboard inspector; it does not change the selected metric or NeuroMiner result state.
     * index: one-based legacy parameter-combination index shared by all model-optimization panels.
     */
    function setModelOptimizationLinkedIndex(index, activePoint){
      const idx = String(index || '');
      const activeSeries = activePoint ? String(activePoint.getAttribute('data-rv-series') || '') : '';
      const activeMetric = activePoint ? String(activePoint.getAttribute('data-rv-metric') || '') : '';
      const ws = workspace();
      const pts = ws ? Array.from(ws.querySelectorAll('.rvModelOptPoint,.rvModelOptPointHit,.rvModelOptDashPoint,.rvModelOptDashPointHit,.rvModelOptScatterPoint')) : [];
      pts.forEach(p => {
        const sameIndex = idx && String(p.getAttribute('data-rv-index') || '') === idx;
        const pointSeries = String(p.getAttribute('data-rv-series') || '');
        const pointMetric = String(p.getAttribute('data-rv-metric') || '');
        const sameMetric = activeMetric && pointMetric && activeMetric === pointMetric;
        const sameSeries = !sameMetric || !activeSeries || !pointSeries || activeSeries === pointSeries;
        const same = sameIndex && sameSeries;
        p.classList.toggle('isPeerHovered', same && p !== activePoint);
        if(p !== activePoint) p.classList.remove('isHovered');
      });
      if(activePoint) activePoint.classList.add('isHovered');
      const inspector = el('modelOptimizationDashboardInspector');
      if(inspector && idx){
        const row = currentPayload() && currentPayload().grid && currentPayload().grid.parameterRows ? currentPayload().grid.parameterRows[Number(idx)-1] : null;
        const txt = row && row.tooltip ? row.tooltip : (row && row.label ? row.label : `Parameter-combination index ${idx}`);
        inspector.textContent = `Linked selection: ${txt}`;
      }
    }

    /**
     * clearModelOptimizationLinkedIndex  Clear transient linked highlighting across optimization panels.
     * It keeps persistent selectors and payload data unchanged and hides only hover-specific visual state.
     */
    function clearModelOptimizationLinkedIndex(){
      const ws = workspace();
      if(!ws) return;
      Array.from(ws.querySelectorAll('.rvModelOptPoint,.rvModelOptPointHit,.rvModelOptDashPoint,.rvModelOptDashPointHit,.rvModelOptScatterPoint')).forEach(p => p.classList.remove('isHovered','isPeerHovered'));
      const tips = Array.from(ws.querySelectorAll('.rvModelOptTooltip'));
      tips.forEach(t => t.classList.remove('isVisible'));
      applyModelOptimizationSelectedIndex();
    }

    /**
     * applyModelOptimizationSelectedIndex  Reapply persistent model-optimization point selection after rendering or hover clearing.
     * It stores only a browser-side one-based parameter-combination index and does not alter MATLAB state, payload contents or selected metric controls.
     */
    function applyModelOptimizationSelectedIndex(){
      const ws = workspace();
      if(!ws) return;
      const idx = String(MODEL_OPT_SELECTED_INDEX || '');
      Array.from(ws.querySelectorAll('.rvModelOptPoint,.rvModelOptPointHit,.rvModelOptDashPoint,.rvModelOptDashPointHit,.rvModelOptScatterPoint')).forEach(p => {
        const same = idx && String(p.getAttribute('data-rv-index') || '') === idx;
        p.classList.toggle('isSelectedIndex', !!same);
      });
    }

    /**
     * selectModelOptimizationIndex  Persist the selected parameter-combination index in the browser dashboard.
     * This supports Stage 4 linked selection without mutating NeuroMiner result containers or forcing a MATLAB round-trip.
     */
    function selectModelOptimizationIndex(index){
      const n = Math.max(0, Math.round(Number(index || 0)));
      const maxN = Math.max(0, Number(currentPayload() && currentPayload().grid && currentPayload().grid.nCombinations) || 0);
      MODEL_OPT_SELECTED_INDEX = n > 0 && (!maxN || n <= maxN) ? n : 0;
      setModelOptimizationLinkedIndex(MODEL_OPT_SELECTED_INDEX, null);
      renderModelOptimizationDashboard();
      if(selectedModelOptimizationMetric().plotKind === 'sequence_curve') renderModelOptimizationPlot();
      applyModelOptimizationSelectedIndex();
      onContentChanged();
    }

    /**
     * bindModelOptimizationPointSet  Attach linked hover/focus handlers to a set of model-optimization points.
     * It is shared by the selected metric plot and the Stage 4 concurrent dashboard so all panels highlight the same parameter-combination index.
     */
    function bindModelOptimizationPointSet(container, selector){
      if(!container) return;
      const points = Array.from(container.querySelectorAll(selector || '.rvModelOptPoint'));
      points.forEach(pt => {
        if(pt.dataset.rvTooltipBound === '1') return;
        pt.dataset.rvTooltipBound = '1';
        pt.addEventListener('mouseenter', evt => {
          setModelOptimizationLinkedIndex(pt.getAttribute('data-rv-index'), pt);
          showModelOptimizationTooltip(container, pt, evt);
        });
        pt.addEventListener('mousemove', evt => showModelOptimizationTooltip(container, pt, evt));
        pt.addEventListener('click', () => selectModelOptimizationIndex(pt.getAttribute('data-rv-index')));
        pt.addEventListener('mouseleave', clearModelOptimizationLinkedIndex);
        pt.addEventListener('focus', evt => {
          setModelOptimizationLinkedIndex(pt.getAttribute('data-rv-index'), pt);
          showModelOptimizationTooltip(container, pt, evt);
        });
        pt.addEventListener('blur', clearModelOptimizationLinkedIndex);
      });
    }

    /**
     * modelOptimizationMetricKey  Resolve a stable browser key for one optimization metric.
     * metric.id: backend metric identifier consumed from the Stage 1 metric registry.
     */
    function modelOptimizationMetricKey(metric, fallbackIndex){
      const id = String(metric && metric.id || '').trim();
      if(id) return id;
      return `metric_${Math.max(1, Number(fallbackIndex || 0) + 1)}`;
    }

    /**
     * modelOptimizationDashboardMetricPool  Return dashboard-eligible metrics excluding the primary selected metric.
     * The top Optimization metric panel already displays the selected metric; the dashboard therefore shows only additional metrics to avoid duplicated scientific content.
     */
    function modelOptimizationDashboardMetricPool(metrics){
      const selected = selectedModelOptimizationMetric();
      const selectedId = String(selected && selected.id || '').trim();
      return arr(metrics).filter(m => {
        if(!m || m === selected) return false;
        if(m.plotKind === 'sequence_curve') return true;
        const id = String(m.id || '').trim();
        return !(selectedId && id && id === selectedId);
      });
    }

    /**
     * modelOptimizationDashboardVisibleMetrics  Resolve metrics selected in the dashboard toggle strip.
     * It keeps the Stage 4 dashboard browser-local: the metric selection controls only visible DOM panels and never changes NM result structures.
     * The selected primary metric is intentionally absent because it is rendered in the top Optimization metric panel.
     */
    function modelOptimizationDashboardVisibleMetrics(metrics){
      const list = modelOptimizationDashboardMetricPool(metrics);
      const validKeys = list.map((m,i) => modelOptimizationMetricKey(m,i));
      MODEL_OPT_DASHBOARD_METRIC_IDS = arr(MODEL_OPT_DASHBOARD_METRIC_IDS).filter(id => validKeys.indexOf(String(id)) >= 0);
      if(!MODEL_OPT_DASHBOARD_METRIC_IDS.length){
        MODEL_OPT_DASHBOARD_METRIC_IDS = validKeys.slice(0, Math.min(4, validKeys.length));
        const sequence = list.find(m => m.plotKind === 'sequence_curve');
        if(sequence){
          const key = modelOptimizationMetricKey(sequence, list.indexOf(sequence));
          if(!MODEL_OPT_DASHBOARD_METRIC_IDS.includes(key)){
            MODEL_OPT_DASHBOARD_METRIC_IDS.pop();
            MODEL_OPT_DASHBOARD_METRIC_IDS.unshift(key);
          }
        }
      }
      const chosen = new Set(MODEL_OPT_DASHBOARD_METRIC_IDS.map(String));
      return list.filter((m,i) => chosen.has(modelOptimizationMetricKey(m,i)));
    }

    /**
     * renderModelOptimizationDashboardToggleStrip  Render metric-panel visibility toggles for the optimization dashboard.
     * It mirrors the Model performance calibration/DCA pattern by making automatically discovered model-optimization panels user-selectable.
     */
    function renderModelOptimizationDashboardToggleStrip(metrics, visibleMetrics){
      const list = modelOptimizationDashboardMetricPool(metrics);
      const visible = new Set(arr(visibleMetrics).map((m,i) => modelOptimizationMetricKey(m, i)));
      return `<div class="rvModelOptMetricToggleStrip" role="group" aria-label="Visible optimization panels">${list.map((m,i) => {
        const key = modelOptimizationMetricKey(m,i);
        const on = visible.has(key);
        return `<button type="button" class="${on ? 'isActive' : ''}" data-rv-modelopt-metric="${esc(key)}" aria-pressed="${on ? 'true' : 'false'}">${esc(m.label || `Metric ${i+1}`)}</button>`;
      }).join('')}</div>`;
    }

    /**
     * bindModelOptimizationDashboardToggles  Attach dashboard metric-panel toggle handlers.
     * Side effects: updates browser-local dashboard metric visibility and re-renders the model-optimization dashboard panels.
     */
    function bindModelOptimizationDashboardToggles(metrics){
      const node = el('modelOptimizationDashboard');
      if(!node) return;
      const pool = modelOptimizationDashboardMetricPool(metrics);
      const valid = pool.map((m,i) => modelOptimizationMetricKey(m,i));
      Array.from(node.querySelectorAll('[data-rv-modelopt-metric]')).forEach(btn => {
        if(btn.dataset.rvMetricToggleBound === '1') return;
        btn.dataset.rvMetricToggleBound = '1';
        btn.addEventListener('click', () => {
          const key = String(btn.getAttribute('data-rv-modelopt-metric') || '');
          if(!key) return;
          const current = new Set(arr(MODEL_OPT_DASHBOARD_METRIC_IDS).map(String).filter(id => valid.indexOf(id) >= 0));
          if(current.has(key) && current.size > 1) current.delete(key);
          else current.add(key);
          MODEL_OPT_DASHBOARD_METRIC_IDS = valid.filter(id => current.has(id));
          renderModelOptimizationDashboard();
          applyModelOptimizationSelectedIndex();
          onContentChanged();
        });
      });
    }

    /**
     * renderModelOptimizationDashboardMetricSvg  Render a full-width optimization metric plot for one dashboard metric.
     * It preserves the selected metric plot semantics while allowing multiple full-sized metric panels below the primary performance panel.
     */
    function renderModelOptimizationDashboardMetricSvg(metric, panelIndex){
      const renderStartedAt = performance.now();
      const values = modelOptimizationMatrix(metric && metric.values);
      if(!values.length) return '';
      const sem = modelOptimizationMatrix(metric && metric.sem);
      const nRows = values.length;
      const nSeries = values.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      const labels = modelOptimizationSeriesLabels(metric, nSeries);
      const metricKey = metric && (metric.id || metric.label) || `dashboard_${panelIndex || 0}`;
      let yVals = [];
      for(let i=0;i<nRows;i++){
        for(let j=0;j<nSeries;j++){
          const y = modelOptimizationNumericValue(values[i] && values[i][j]);
          const se = modelOptimizationNumericValue(sem[i] && sem[i][j]);
          if(Number.isFinite(y)) yVals.push(y);
          if(Number.isFinite(y) && Number.isFinite(se)) yVals.push(y - Math.abs(se), y + Math.abs(se));
        }
      }
      yVals = yVals.filter(Number.isFinite);
      if(!yVals.length) return '';
      let yMin = Math.min(...yVals), yMax = Math.max(...yVals);
      if(Math.abs(yMax - yMin) < 1e-12){ yMin -= 0.5; yMax += 0.5; }
      else { const pad = (yMax - yMin) * 0.08; yMin -= pad; yMax += pad; }
      const w = 900, h = 430;
      const denseStyle = modelOptimizationDensePlotStyle(nRows, w - 82 - 28);
      const ax = plotTools().cartesianAxes({w,h,m:{left:82,right:28,top:24,bottom:62},xLim:[1,Math.max(1,nRows)],yLim:[yMin,yMax],xTicks:niceTicks(1,Math.max(1,nRows),Math.min(8,nRows)),yTicks:niceTicks(yMin,yMax,5),xFmt:v => String(Math.round(Number(v))),yFmt:fmtTick,xLabel:metric.xLabel || 'Parameter-combination index',yLabel:metric.yLabel || metric.label || 'Metric',autoMargin:true});
      const P = plotTools();
      const seriesSvg = [];
      const hitSvg = [];
      const pointSvg = [];
      const legendRows = [];
      let segmentCount = 0;
      let pointCount = 0;
      for(let j=0;j<nSeries;j++){
        const geometry = modelOptimizationSeriesGeometry(values, sem, j);
        segmentCount += geometry.lineSegments.length;
        pointCount += geometry.points.length;
        geometry.bandSegments.forEach(segment => {
          seriesSvg.push(P.areaElement(segment, p => ax.xPix(p.x), p => ax.yPix(p.y0), p => ax.yPix(p.y1), `rvModelOptDashBand rvModelOptSeries${j%6}`));
        });
        geometry.lineSegments.forEach(segment => {
          seriesSvg.push(modelOptimizationSegmentSvg(segment, ax, `rvModelOptDashLine rvModelOptSeries${j%6}`, denseStyle.lineWidth));
        });
        geometry.points.forEach(p => {
          const row = currentPayload() && currentPayload().grid && currentPayload().grid.parameterRows ? currentPayload().grid.parameterRows[p.index-1] : null;
          const se = modelOptimizationNumericValue(sem[p.index-1] && sem[p.index-1][j]);
          const tip = modelOptimizationPointTooltipText(metric, labels[j], p.index, p.y, se, row);
          const attrs = modelOptimizationPointAttributes(metricKey, p.index, j+1, tip);
          const cx = ax.xPix(p.x).toFixed(1);
          const cy = ax.yPix(p.y).toFixed(1);
          hitSvg.push(`<circle class="rvModelOptDashPointHit" cx="${cx}" cy="${cy}" r="${denseStyle.hitRadius.toFixed(1)}" tabindex="0" ${attrs}></circle>`);
          pointSvg.push(`<circle class="rvModelOptDashPoint rvModelOptSeries${j%6}" cx="${cx}" cy="${cy}" r="${denseStyle.radius.toFixed(1)}" ${attrs}></circle>`);
        });
        legendRows.push(`<span class="rvModelOptLegendItem rvModelOptSeries${j%6}"><i></i>${esc(labels[j])}</span>`);
      }
      profileLog('model optimization dashboard metric', renderStartedAt, `metric=${metricKey} rows=${nRows} series=${nSeries} segments=${segmentCount} points=${pointCount}`);
      return `<div class="rvModelOptDashPlot"><svg class="rvModelOptDashSvg" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(metric.label || 'Optimization metric')}">${ax.svg}<g class="rvModelOptSeriesLayer">${seriesSvg.join('')}</g><g class="rvModelOptHitLayer">${hitSvg.join('')}</g><g class="rvModelOptPointLayer">${pointSvg.join('')}</g></svg><div class="rvModelOptTooltip" role="status" aria-live="polite"></div><div class="rvModelOptLegend">${legendRows.join('')}</div></div>`;
    }

    /** Plot saved mean ± SD by grid combination or applied OOCV sequence. */
    function renderModelOptimizationDiagnosticSvg(metric){
      const payload=currentPayload(),data=payload.sequenceDiagnostics,grid=payload.grid;
      const original=modelOptimizationMatrix(metric.values);
      const criterionSd=modelOptimizationMatrix(metric.sem);
      const combination=MODEL_OPT_SELECTED_INDEX || original.findIndex(row=>arr(row).some(Number.isFinite))+1;
      const cohorts=[...new Set(arr(data.records).filter(r=>r.scope==='OOCV').map(r=>r.cohort))];
      if(SEQUENCE_DIAGNOSTIC_VIEW.scope==='OOCV' && !cohorts.includes(SEQUENCE_DIAGNOSTIC_VIEW.cohort)){
        SEQUENCE_DIAGNOSTIC_VIEW.cohort=cohorts[0];
        if(!cohorts.length) SEQUENCE_DIAGNOSTIC_VIEW.scope='CV2';
      }
      const scoped=arr(data.records).filter(r=>r.scope===SEQUENCE_DIAGNOSTIC_VIEW.scope &&
        (r.scope==='CV2'||r.cohort===SEQUENCE_DIAGNOSTIC_VIEW.cohort));
      const key=r=>arr(r.sequenceCols).join(',');
      const choices=[...new Map(scoped.map(r=>[key(r),r])).values()];
      const activeCV=scoped.find(r=>Number(r.combination)===combination);
      const selectedKey=SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?(activeCV?key(activeCV):''):
        (choices.some(r=>key(r)===SEQUENCE_DIAGNOSTIC_VIEW.sequenceKey)?SEQUENCE_DIAGNOSTIC_VIEW.sequenceKey:(choices[0]?key(choices[0]):''));
      SEQUENCE_DIAGNOSTIC_VIEW.sequenceKey=selectedKey;
      const record=SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?activeCV:scoped.find(r=>key(r)===selectedKey);
      const scopePicker=`<label><span>Evaluation</span><select data-rv-seq-scope><option value="CV2"${SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?' selected':''}>CV2</option>${cohorts.map(cohort=>`<option value="OOCV:${cohort}"${SEQUENCE_DIAGNOSTIC_VIEW.scope==='OOCV'&&SEQUENCE_DIAGNOSTIC_VIEW.cohort===cohort?' selected':''}>OOCV ${cohort}</option>`).join('')}</select></label>`;
      const combPicker=SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'&&record?`<label><span>Selected CV2 combination</span><strong>${esc(grid.parameterRows[combination-1].label)}</strong></label>`:'';
      const sourceCatalogue=new Map();
      choices.forEach(r=>arr(r.sequenceCols).forEach((source,i)=>sourceCatalogue.set(source,arr(r.sourceNames)[i])));
      const sequencePicker=SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?`<label><span>Sequence of selected combination</span><strong>${esc(record?arr(record.sequenceCols).map(source=>`S${source}`).join(' → '):'')}</strong></label>`:`<label><span>Ordered examination sequence</span><select data-rv-seq-sequence title="${esc(record?arr(record.sourceNames).join(' → '):'')}">${choices.map(r=>`<option value="${key(r)}"${key(r)===selectedKey?' selected':''}>${esc(arr(r.sequenceCols).map(source=>`S${source}`).join(' → '))}</option>`).join('')}</select></label>`;
      const sourceKey=`<details class="rvModelOptSequenceSourceKey"><summary>Source key</summary><div>${[...sourceCatalogue].sort((a,b)=>a[0]-b[0]).map(([source,name])=>`<span><strong>S${source}</strong> = ${esc(name)}</span>`).join('')}</div></details>`;
      const groupLabels={performance:'Diagnostic performance',yield:'Diagnostic yield',propagation:'Case propagation'};
      const groupPicker=`<label><span>Metric family</span><select data-rv-seq-group>${Object.keys(groupLabels).map(g=>`<option value="${g}"${g===SEQUENCE_DIAGNOSTIC_VIEW.group?' selected':''}>${groupLabels[g]}</option>`).join('')}</select></label>`;
      const toolbar=`<div class="rvModelOptSequenceControls${SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?' rvModelOptSequenceControlsCV2':''}">${combPicker}${scopePicker}${sequencePicker}${groupPicker}</div>`;
      if(!record) return `<div class="rvModelOptDashPlot">${toolbar}<div class="rvPanelNotice">No ${esc(SEQUENCE_DIAGNOSTIC_VIEW.scope)} SEQOPT diagnostic summary is available for this selection.</div></div>`;
      const selectionContext=SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?
        `CV2: this plot shows only the selected complete parameter combination, including its examination sequence and deferral settings; no aggregation across grid rows. <strong>Selected settings:</strong> ${esc(grid.parameterRows[combination-1].tooltip)}`:
        'OOCV: models sharing the selected ordered sequence are pooled within each CV2 partition (including distinct deferral settings); mean and SD are then computed across partitions.';
      const selectionNote=`<div class="rvModelOptSequenceSelectionNote">${selectionContext}</div>`;
      const catalog=arr(data.metrics).filter(m=>m.group===SEQUENCE_DIAGNOSTIC_VIEW.group);
      const available=SEQUENCE_DIAGNOSTIC_VIEW.group==='performance' && SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?
        [{id:'criterion',label:'Optimization criterion (CV2 grid summary)',unit:'criterion'},...catalog]:catalog;
      const selected=new Set(SEQUENCE_DIAGNOSTIC_VIEW.metrics);
      const checks=`<div class="rvModelOptMetricToggleStrip rvModelOptSequenceMetricToggles" role="group" aria-label="Sequence diagnostic metrics">${available.map(m=>`<button type="button" class="rvModelOptSequenceMetric${selected.has(m.id)?' isActive':''}" data-rv-seq-metric="${esc(m.id)}" aria-pressed="${selected.has(m.id)?'true':'false'}">${esc(m.label)}</button>`).join('')}</div>`;
      const metricGroups=new Map();
      available.filter(m=>selected.has(m.id)).forEach(m=>{
        const axis=m.unit==='%'?'percent':m.id==='criterion'?'criterion':m.unit==='ratio'?m.id:m.unit;
        if(!metricGroups.has(axis)) metricGroups.set(axis,[]);
        metricGroups.get(axis).push(m);
      });
      const names=arr(record.sourceNames),stages=arr(record.sequenceCols).length;
      const makePlot=(items,axis)=>{
        const series=items.map(m=>{
          const raw=m.id==='criterion'?arr(original[combination-1]):arr(record.values[m.id]);
          const err=m.id==='criterion'?arr(criterionSd[combination-1]):arr(record.sd[m.id]);
          return {metric:m,points:Array.from({length:stages},(_,i)=>{
            const y=modelOptimizationNumericValue(raw[i]);
            if(!Number.isFinite(y)) return null;
            return {x:i+1,y,sd:modelOptimizationNumericValue(err[i])};
          })};
        });
        const all=series.flatMap(s=>s.points.filter(Boolean).flatMap(p=>Number.isFinite(p.sd)?[p.y-Math.abs(p.sd),p.y+Math.abs(p.sd)]:[p.y]));
        if(!all.length) return `<div class="rvPanelNotice">${esc(items.map(x=>x.label).join(', '))}: no labeled scores or valid denominators.</div>`;
        let lo=axis==='percent'?0:Math.min(...all),hi=axis==='percent'?100:Math.max(...all);
        if(hi-lo<1e-10){lo-=0.5;hi+=0.5;}
        else if(axis!=='percent'){const pad=(hi-lo)*0.08;lo-=pad;hi+=pad;}
        const w=900,h=320;
        const ax=plotTools().cartesianAxes({w,h,m:{left:82,right:28,top:26,bottom:64},
          xLim:[1,Math.max(2,stages)],yLim:[lo,hi],
          xTicks:Array.from({length:stages},(_,i)=>i+1),yTicks:niceTicks(lo,hi,5),
          xFmt:v=>String(Math.round(Number(v))),yFmt:fmtTick,
          xLabel:'Examination stage',yLabel:axis==='percent'?'Percentage (%)':axis==='criterion'?payload.optimizationCriterion.label:items[0].unit,autoMargin:true});
        const svg=[],legend=[];
        series.forEach((s,i)=>{
          const bands=s.points.map(p=>p&&Number.isFinite(p.sd)?{
            x:p.x,y0:Math.max(lo,p.y-Math.abs(p.sd)),y1:Math.min(hi,p.y+Math.abs(p.sd))}:null);
          modelOptimizationContiguousSegments(bands).forEach(segment=>svg.push(plotTools().areaElement(segment,p=>ax.xPix(p.x),p=>ax.yPix(p.y0),p=>ax.yPix(p.y1),`rvModelOptDashBand rvModelOptSeries${i%6}`)));
          modelOptimizationContiguousSegments(s.points).forEach(segment=>svg.push(modelOptimizationSegmentSvg(segment,ax,`rvModelOptDashLine rvModelOptSeries${i%6}`,2.2)));
          s.points.filter(Boolean).forEach(point=>{
            const sd=Number.isFinite(point.sd)?` ± SD ${fmtMetric(point.sd,4)}`:'';
            svg.push(`<circle class="rvModelOptDashPoint rvModelOptSeries${i%6}" cx="${ax.xPix(point.x).toFixed(2)}" cy="${ax.yPix(point.y).toFixed(2)}" r="4"><title>${esc(s.metric.label)} · ${esc(names[point.x-1]||`Examination ${point.x}`)}: mean ${esc(fmtMetric(point.y,4))}${esc(sd)}</title></circle>`);
          });
          legend.push(`<span class="rvModelOptLegendItem rvModelOptSeries${i%6}"><i></i>${esc(s.metric.label)} (mean ± SD)</span>`);
        });
        const title=axis==='criterion'?`Optimization criterion — ${payload.optimizationCriterion.label}`:items.map(m=>m.label).join(' / ');
        const context=axis==='criterion'?'CV2 grid summary':SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?'CV2 diagnostics':`OOCV ${SEQUENCE_DIAGNOSTIC_VIEW.cohort} sequence summary`;
        return `<div class="rvModelOptDashPlot rvModelOptSequenceChart"><div class="rvModelOptSequenceChartHeader"><strong>${esc(title)}</strong><span>${esc(context)} · Mean ± SD</span></div><div class="rvModelOptLegend rvModelOptSequenceChartLegend">${legend.join('')}</div><svg class="rvModelOptDashSvg" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(title)}; ${esc(context)}; mean and standard deviation">${ax.svg}${svg.join('')}</svg></div>`;
      };
      const charts=Array.from(metricGroups,([axis,items])=>makePlot(items,axis)).join('');
      return `<div class="rvModelOptDashPlot">${toolbar}${selectionNote}${sourceKey}${checks}${charts||'<div class="rvPanelNotice">Select one or more metrics.</div>'}</div>`;
    }

    function redrawModelOptimizationSequencePanels(){
      if(selectedModelOptimizationMetric().plotKind==='sequence_curve') renderModelOptimizationPlot();
      refreshModelOptimizationSequenceStage();
    }

    function bindModelOptimizationSequenceControls(root){
      const scope=root.querySelector('[data-rv-seq-scope]');
      if(scope) scope.addEventListener('change',()=>{
        SEQUENCE_DIAGNOSTIC_VIEW.scope=scope.value==='CV2'?'CV2':'OOCV';
        SEQUENCE_DIAGNOSTIC_VIEW.cohort=scope.value==='CV2'?0:Number(scope.value.slice(5));
        SEQUENCE_DIAGNOSTIC_VIEW.sequenceKey='';
        if(SEQUENCE_DIAGNOSTIC_VIEW.scope==='OOCV') SEQUENCE_DIAGNOSTIC_VIEW.metrics=SEQUENCE_DIAGNOSTIC_VIEW.metrics.filter(id=>id!=='criterion');
        redrawModelOptimizationSequencePanels();
      });
      const sequence=root.querySelector('[data-rv-seq-sequence]');
      if(sequence) sequence.addEventListener('change',()=>{
        SEQUENCE_DIAGNOSTIC_VIEW.sequenceKey=sequence.value;
        redrawModelOptimizationSequencePanels();
      });
      const group=root.querySelector('[data-rv-seq-group]');
      if(group) group.addEventListener('change',()=>{
        SEQUENCE_DIAGNOSTIC_VIEW.group=group.value;
        SEQUENCE_DIAGNOSTIC_VIEW.metrics=group.value==='performance'?(SEQUENCE_DIAGNOSTIC_VIEW.scope==='CV2'?['criterion','sens','spec']:['sens','spec']):group.value==='yield'?['targetPrevalenceReached']:['percentReached','nReached'];
        redrawModelOptimizationSequencePanels();
      });
      Array.from(root.querySelectorAll('[data-rv-seq-metric]')).forEach(button=>button.addEventListener('click',()=>{
        const id=button.getAttribute('data-rv-seq-metric'),chosen=new Set(SEQUENCE_DIAGNOSTIC_VIEW.metrics);
        if(button.getAttribute('aria-pressed')==='true') chosen.delete(id);else chosen.add(id);
        SEQUENCE_DIAGNOSTIC_VIEW.metrics=Array.from(chosen);
        redrawModelOptimizationSequencePanels();
      }));
    }

    /**
     * renderModelOptimizationSequenceStageSvg  Plot the chosen grid row along its examination-stage axis.
     * The values are already computed and saved by the SEQOPT CV2 producer; stage is not the grid axis.
     */
    function renderModelOptimizationSequenceStageSvg(metric){
      if(currentPayload().sequenceDiagnostics && currentPayload().sequenceDiagnostics.available){
        return renderModelOptimizationDiagnosticSvg(metric);
      }
      const values = modelOptimizationMatrix(metric.values);
      const defaultIndex = values.findIndex(row => arr(row).some(Number.isFinite)) + 1;
      const selected = MODEL_OPT_SELECTED_INDEX || defaultIndex;
      if(!selected) return '<div class="rvPanelNotice">No CV2 sequence-performance values were recorded for any parameter combination.</div>';
      const grid=currentPayload().grid;
      const sequenceColumn=arr(grid.parameterNames).indexOf('Sequence');
      const options=arr(grid.parameterRows).map((entry,i) => {
        const seq=sequenceColumn>=0 ? ` · Sequence ${entry.values[sequenceColumn]}` : '';
        return `<option value="${i+1}"${i+1===selected?' selected':''}>${esc(entry.label)}${esc(seq)}</option>`;
      }).join('');
      const chooser=`<label class="rvModelOptSequenceCaption">Parameter combination <select data-rv-sequence-combination aria-label="Sequence parameter combination">${options}</select></label>`;
      const row = values[selected-1];
      const points = arr(row).map((y,i) => ({x:i+1,y})).filter(p => Number.isFinite(p.y));
      if(!points.length) return `<div class="rvModelOptDashPlot">${chooser}<div class="rvPanelNotice">This parameter combination has no recorded CV2 sequence-performance values.</div></div>`;
      let low = Math.min(...points.map(p=>p.y)), high = Math.max(...points.map(p=>p.y));
      if(high-low < 1e-12){low-=0.5;high+=0.5;}
      else {const pad=(high-low)*0.08;low-=pad;high+=pad;}
      const w=900,h=420, nStages=row.length;
      const ax=plotTools().cartesianAxes({w,h,m:{left:82,right:28,top:26,bottom:64},
        xLim:[1,Math.max(2,nStages)],yLim:[low,high],
        xTicks:Array.from({length:nStages},(_,i)=>i+1),yTicks:niceTicks(low,high,5),
        xFmt:v=>String(Math.round(Number(v))),yFmt:fmtTick,
        xLabel:'Examination stage',yLabel:metric.yLabel,autoMargin:true});
      const samples=arr(row).map((y,i)=>Number.isFinite(y)?{x:i+1,y,index:i+1}:null);
      const segments=modelOptimizationContiguousSegments(samples);
      const lines=segments.map(seg=>modelOptimizationSegmentSvg(seg,ax,'rvModelOptDashLine rvModelOptSeries0',2.2));
      const dots=points.map(p=>`<circle class="rvModelOptDashPoint rvModelOptSeries0" cx="${ax.xPix(p.x).toFixed(2)}" cy="${ax.yPix(p.y).toFixed(2)}" r="4"><title>Examination ${p.x}: ${esc(fmtMetric(p.y,4))}</title></circle>`);
      const selection=grid.parameterRows[selected-1];
      const sequenceLabel=sequenceColumn>=0 ? ` · Sequence ${esc(selection.values[sequenceColumn])}` : '';
      const initial=MODEL_OPT_SELECTED_INDEX ? '' : ' · first recorded combination';
      return `<div class="rvModelOptDashPlot">${chooser}<div class="rvModelOptSequenceCaption">${esc(selection.label)}${sequenceLabel}${initial} · CV2-test performance across examination stages</div><svg class="rvModelOptDashSvg" viewBox="0 0 ${w} ${h}" role="img" aria-label="Stage-wise sequence performance for ${esc(selection.label)}">${ax.svg}${lines.join('')}${dots.join('')}</svg></div>`;
    }

    /**
     * refreshModelOptimizationSequenceStage  Update only the selected-row view, without redrawing the optimization grid.
     */
    function refreshModelOptimizationSequenceStage(){
      const node=el('modelOptimizationDashboard');
      if(!node) return;
      const slot=node.querySelector('[data-metric-id="sequence_node_performance"] .rvModelOptDashCardBody > div:first-child');
      if(!slot) return;
      const metric=arr(currentPayload().metrics).find(m=>m.id==='sequence_node_performance');
      slot.innerHTML=renderModelOptimizationSequenceStageSvg(metric);
      bindModelOptimizationSequenceCombination(slot);
      bindModelOptimizationSequenceControls(slot);
    }

    /** Use the existing linked grid-row selection for the sequence panel selector. */
    function bindModelOptimizationSequenceCombination(root){
      const select=root.querySelector('[data-rv-sequence-combination]');
      if(select) select.addEventListener('change', () => selectModelOptimizationIndex(select.value));
    }

    /**
     * renderModelOptimizationDashboardPanel  Render one full-width metric panel for the Stage 4a dashboard.
     * It pairs each automatically discovered optimization plot with the CV partition matrices that legacy display_modelperf exposes for that metric family.
     */
    function renderModelOptimizationDashboardPanel(metric, panelIndex){
      const plot = metric.plotKind === 'sequence_curve' ?
        renderModelOptimizationSequenceStageSvg(metric) : renderModelOptimizationDashboardMetricSvg(metric, panelIndex);
      if(!plot) return '';
      const matrices = modelOptimizationPartitionForMetric(metric);
      const matrixHtml = matrices.length ? `<div class="rvModelOptDashMatrices">${matrices.map((m,i) => renderModelOptimizationPartitionDisplay(m,i,{dashboard:true})).join('')}</div>` : '';
      const bodyClass = matrices.length ? 'rvModelOptDashCardBody' : 'rvModelOptDashCardBody rvModelOptDashCardBodyFull';
      return `<section class="rvModelOptDashCard" data-metric-id="${esc(metric.id || '')}"><div class="rvModelOptDashTitle"><strong>${esc(metric.label || 'Optimization metric')}</strong></div><div class="${bodyClass}"><div>${plot}</div>${matrixHtml}</div></section>`;
    }

    /**
     * bindModelOptimizationDashboard  Activate linked hover inspection for all Stage 4a dashboard points and matrix cells.
     * It keeps all interactions local to the browser viewspace and reuses the same tooltip contract as the selected metric plot.
     */
    function bindModelOptimizationDashboard(){
      const node = el('modelOptimizationDashboard');
      if(!node) return;
      Array.from(node.querySelectorAll('.rvModelOptDashPlot')).forEach(panel => {
        if(!panel.closest('[data-metric-id="sequence_node_performance"]')) bindModelOptimizationPointSet(panel, '.rvModelOptDashPointHit,.rvModelOptDashPoint');
      });
      Array.from(node.querySelectorAll('.rvModelOptHeatmap,.rvModelOptHistogram')).forEach(panel => bindModelOptimizationPartitionTooltips(panel));
      bindModelOptimizationMatrixViewToggles(node);
      bindModelOptimizationSequenceCombination(node);
    }

    /**
     * renderModelOptimizationDashboard  Render user-selectable full-width optimization metric panels.
     * It uses a responsive Stage 4 chart grid so the curve keeps the intended 2/3 width and the corresponding matrix keeps the intended 1/3 width when the panel is wide enough.
     */
    function renderModelOptimizationDashboard(){
      const renderStartedAt = performance.now();
      const node = el('modelOptimizationDashboard');
      if(!node) return;
      if(!currentPayload() || currentPayload().ok === false){
        node.innerHTML = `<div class="rvPanelNotice">${esc(currentPayload() && currentPayload().message || 'Model optimization payload unavailable.')}</div>`;
        return;
      }
      if(Number(currentPayload().grid.nCombinations)===1){
        const metric=arr(currentPayload().metrics).find(m=>m.available && m.plotKind==='sequence_curve');
        node.innerHTML=metric && currentPayload().sequenceDiagnostics && currentPayload().sequenceDiagnostics.available ?
          `<section class="rvModelOptDashCard" data-metric-id="sequence_node_performance"><div class="rvModelOptDashTitle"><strong>Sequence diagnostics</strong></div><div class="rvModelOptDashCardBody rvModelOptDashCardBodyFull"><div>${renderModelOptimizationSequenceStageSvg(metric)}</div></div></section>` : '';
        bindModelOptimizationSequenceControls(node);
        return;
      }
      const allMetrics = modelOptimizationAvailablePanelMetrics();
      const metrics = modelOptimizationDashboardMetricPool(allMetrics);
      if(!metrics.length){
        node.innerHTML = '<div class="rvPanelNotice">No additional optimization metrics can be displayed in the dashboard. The selected metric is already shown in the top Optimization metric panel.</div>';
        return;
      }
      const shown = modelOptimizationDashboardVisibleMetrics(allMetrics);
      const toggle = renderModelOptimizationDashboardToggleStrip(allMetrics, shown);
      const hidden = metrics.length > shown.length ? `<div class="rvModelOptDashboardNote">Showing ${shown.length} of ${metrics.length} additional metrics. Use the toggle strip to add or remove panels.</div>` : '';
      const displayMetrics=shown.filter(m=>m.plotKind!=='sequence_curve'||MODEL_OPT_SELECTED_INDEX>0||SEQUENCE_DIAGNOSTIC_VIEW.scope==='OOCV');
      displayMetrics.sort((a,b)=>Number(b.plotKind==='sequence_curve')-Number(a.plotKind==='sequence_curve'));
      const selectionHint=SEQUENCE_DIAGNOSTIC_VIEW.scope==='OOCV'?'OOCV diagnostics aggregate applied models by ordered sequence, independently of the selected CV2 grid row.':MODEL_OPT_SELECTED_INDEX>0?`Selected ${esc(currentPayload().grid.parameterRows[MODEL_OPT_SELECTED_INDEX-1].label)} — the CV2 stage-wise diagnostics below use exactly this grid row.`:'Select a hyperparameter combination by clicking a point in the Optimization metric plot above to inspect its stage-wise SEQOPT diagnostics.';
      const inspectorText=MODEL_OPT_SELECTED_INDEX>0?`Selected: ${esc(currentPayload().grid.parameterRows[MODEL_OPT_SELECTED_INDEX-1].tooltip)}`:'No linked selection.';
      node.innerHTML = `<div class="rvModelOptDashboardHeader"><div><strong>Selected-combination diagnostics and additional metrics</strong><span>${selectionHint}</span></div><div id="modelOptimizationDashboardInspector" class="rvModelOptDashboardInspector">${inspectorText}</div></div>${toggle}<div class="rvModelOptMatrixViewStrip">${renderModelOptimizationMatrixViewToggle()}</div><div class="rvModelOptDashboardGrid">${displayMetrics.map((m,i) => renderModelOptimizationDashboardPanel(m,i)).join('')}</div>${hidden}`;
      bindModelOptimizationDashboardToggles(metrics);
      bindModelOptimizationDashboard();
      bindModelOptimizationSequenceControls(node);
      profileLog('model optimization dashboard TOTAL', renderStartedAt, `available=${allMetrics.length} visible=${shown.length}`);
    }

    /**
     * modelOptimizationPartitionForMetric  Select CV-partition matrices relevant to the active metric.
     * It mirrors the legacy display_modelperf behavior: CV performance has CV1/CV2 matrices, complexity has complexity, and generalization error has error.
     */
    function modelOptimizationPartitionForMetric(metric){
      const p = currentPayload() && currentPayload().partitions || {};
      const field = String(metric && metric.partitionField || '');
      if(field === 'cv_performance') return [p.cv1, p.cv2].filter(x => x && x.ok);
      if(field === 'complexity') return [p.complexity].filter(x => x && x.ok);
      if(field === 'error') return [p.error].filter(x => x && x.ok);
      return [];
    }

    /**
     * renderModelOptimizationMatrixViewToggle  Build matrix/histogram toggle controls for CV partition summaries.
     * It switches only browser rendering of already-loaded partition matrices and does not recompute or mutate NeuroMiner results.
     */
    function renderModelOptimizationMatrixViewToggle(){
      const view = MODEL_OPT_MATRIX_VIEW === 'histogram' ? 'histogram' : 'matrix';
      return `<div class="rvModelOptMatrixToggle" role="group" aria-label="CV partition display"><button type="button" class="${view === 'matrix' ? 'isActive' : ''}" data-rv-matrix-view="matrix" aria-pressed="${view === 'matrix' ? 'true' : 'false'}">Matrix</button><button type="button" class="${view === 'histogram' ? 'isActive' : ''}" data-rv-matrix-view="histogram" aria-pressed="${view === 'histogram' ? 'true' : 'false'}">Histogram</button></div>`;
    }

    /**
     * bindModelOptimizationMatrixViewToggles  Attach matrix/histogram display toggle handlers.
     * Side effects: updates browser-local display mode and re-renders partition/dashboard matrix summaries.
     */
    function bindModelOptimizationMatrixViewToggles(root){
      const scope = root || document;
      Array.from(scope.querySelectorAll('[data-rv-matrix-view]')).forEach(btn => {
        if(btn.dataset.rvMatrixToggleBound === '1') return;
        btn.dataset.rvMatrixToggleBound = '1';
        btn.addEventListener('click', () => {
          const next = String(btn.getAttribute('data-rv-matrix-view') || 'matrix').toLowerCase();
          MODEL_OPT_MATRIX_VIEW = next === 'histogram' ? 'histogram' : 'matrix';
          renderModelOptimizationPartitions();
          renderModelOptimizationDashboard();
          applyModelOptimizationSelectedIndex();
          onContentChanged();
        });
      });
    }

    /**
     * modelOptimizationPartitionTooltipText  Compose hover text for one CV partition cell or histogram bin.
     * matrixPayload.valueLabel: backend value label for the displayed partition matrix.
     */
    function modelOptimizationPartitionTooltipText(matrixPayload, parts){
      const label = String(matrixPayload && matrixPayload.title || 'CV partition value');
      const rows = [label];
      arr(parts).forEach(x => { if(x) rows.push(String(x)); });
      return rows.join('\n');
    }

    /**
     * bindModelOptimizationPartitionTooltips  Attach hover/focus handlers to CV partition cells and histogram bars.
     * Side effects: updates transient browser tooltip and highlight CSS classes only.
     */
    function bindModelOptimizationPartitionTooltips(container){
      if(!container) return;
      const items = Array.from(container.querySelectorAll('.rvModelOptHeatCell,.rvModelOptHistBar,.rvModelOptSurfaceCell,.rvModelPermutationBar'));
      items.forEach(item => {
        if(item.dataset.rvTooltipBound === '1') return;
        item.dataset.rvTooltipBound = '1';
        item.addEventListener('mouseenter', evt => { item.classList.add('isHovered'); showModelOptimizationTooltip(container, item, evt); });
        item.addEventListener('mousemove', evt => showModelOptimizationTooltip(container, item, evt));
        item.addEventListener('mouseleave', () => {
          item.classList.remove('isHovered');
          const tip = container.querySelector('.rvModelOptTooltip');
          if(tip) tip.classList.remove('isVisible');
        });
        item.addEventListener('focus', evt => { item.classList.add('isHovered'); showModelOptimizationTooltip(container, item, evt); });
        item.addEventListener('blur', () => {
          item.classList.remove('isHovered');
          const tip = container.querySelector('.rvModelOptTooltip');
          if(tip) tip.classList.remove('isVisible');
        });
      });
    }

    /**
     * modelOptimizationFiniteMatrixValues  Flatten finite numeric values from one partition matrix.
     * It is used by the histogram toggle without altering the source matrix or its CV1/CV2 interpretation.
     */
    function modelOptimizationFiniteMatrixValues(mat, missingMask){
      const vals = [];
      arr(mat).forEach((r,ri) => arr(r).forEach((v,ci) => {
        if(missingMask && missingMask[ri] && missingMask[ri][ci]) return;
        const x = Number(v);
        if(Number.isFinite(x)) vals.push(x);
      }));
      return vals;
    }

    /**
     * modelOptimizationMissingCellMask  Infer uncomputed CV-partition cells for browser heatmaps.
     * Legacy partition matrices may encode not-run fold/permutation slots as exact trailing zeros. These cells must not be rendered as valid zero-valued criteria because that is scientifically misleading and inconsistent with the static report export. The heuristic is intentionally conservative: it masks only exact zero cells that occur after the final non-zero finite entry in row-major order and only when the matrix contains both non-zero values and more than one zero cell.
     */
    function modelOptimizationMissingCellMask(mat){
      const rows = arr(mat);
      const R = rows.length;
      const C = rows.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      const mask = Array.from({length:R}, () => Array.from({length:C}, () => false));
      if(R < 1 || C < 1) return {mask, count:0};
      let zeroCount = 0;
      let nonZeroCount = 0;
      let lastNonZeroLinear = -1;
      for(let r=0;r<R;r++){
        for(let c=0;c<C;c++){
          const v = Number(rows[r] && rows[r][c]);
          if(!Number.isFinite(v)) continue;
          if(Math.abs(v) <= 1e-12){
            zeroCount += 1;
          }else{
            nonZeroCount += 1;
            lastNonZeroLinear = Math.max(lastNonZeroLinear, r*C + c);
          }
        }
      }
      if(zeroCount < 2 || nonZeroCount < 1 || lastNonZeroLinear < 0) return {mask, count:0};
      let count = 0;
      for(let r=0;r<R;r++){
        for(let c=0;c<C;c++){
          const v = Number(rows[r] && rows[r][c]);
          if(Number.isFinite(v) && Math.abs(v) <= 1e-12 && (r*C + c) > lastNonZeroLinear){
            mask[r][c] = true;
            count += 1;
          }
        }
      }
      return {mask, count};
    }

    /**
     * modelOptimizationIsMissingCell  Return whether a CV partition cell is inferred to be uncomputed.
     * The separate accessor keeps the rendering loop explicit and avoids dynamic assumptions about missing-mask dimensions.
     */
    function modelOptimizationIsMissingCell(missingInfo, r, c){
      return !!(missingInfo && missingInfo.mask && missingInfo.mask[r] && missingInfo.mask[r][c]);
    }

    /**
     * modelOptimizationSeriesCssColor  Infer the display color for CV-partition matrices and histograms.
     * It aligns matrix and histogram colors with the corresponding optimization-curve series so CV1 and CV2 remain visually consistent across the model-optimization workspace.
     * matrixPayload.title: legacy matrix title that may encode CV1/CV2 semantics.
     * idx: zero-based matrix index used only as a conservative fallback when the title is not informative.
     */
    function modelOptimizationSeriesCssColor(matrixPayload, idx){
      const title = String(matrixPayload && matrixPayload.title || '');
      const head = title.split(/\s+at\s+/i, 1)[0].toLowerCase();
      if(/(^|\W)cv1(\W|$)|mean\s+cv1|cross-validation/.test(head)) return '#2563eb';
      if(/(^|\W)cv2(\W|$)|mean\s+cv2|test performance/.test(head)) return '#c2410c';
      return Number(idx) === 1 ? '#c2410c' : '#2563eb';
    }

    /**
     * modelOptimizationDisplayMatrix  Orient partition matrices using the shared NM convention.
     * Rows are permutations and columns are folds, matching legacy Results Viewer axes and runner action grids; a single-column multi-row matrix is treated as a transposed one-permutation fold vector.
     */
    function modelOptimizationDisplayMatrix(mat){
      const src = modelOptimizationMatrix(mat);
      if(!src.length) return src;
      const rows = src.length;
      const cols = src.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      if(cols === 1 && rows > 1){
        return [src.map(r => Number(arr(r)[0]))];
      }
      return src;
    }

    /**
     * modelOptimizationHistogramBins  Bin finite optimization-criterion values for the histogram view.
     * The histogram x-axis is the displayed performance/criterion value and the y-axis is the empirical probability of each bin.
     */
    function modelOptimizationHistogramBins(values, maxBins){
      const vals = arr(values).map(Number).filter(Number.isFinite);
      if(!vals.length) return [];
      const lo = Math.min(...vals), hi = Math.max(...vals);
      const nBins = Math.max(1, Math.min(Number(maxBins || 8), Math.ceil(Math.sqrt(vals.length)) || 1));
      if(Math.abs(hi - lo) < 1e-12) return [{lo,hi,count:vals.length,probability:1,density:1}];
      const step = (hi - lo) / nBins;
      const bins = [];
      for(let i=0;i<nBins;i++) bins.push({lo:lo+i*step,hi:i === nBins-1 ? hi : lo+(i+1)*step,count:0,probability:0,density:0});
      vals.forEach(v => {
        let idx = Math.floor((v - lo) / step);
        if(idx >= nBins) idx = nBins - 1;
        if(idx < 0) idx = 0;
        bins[idx].count += 1;
      });
      bins.forEach(b => {
        b.probability = vals.length ? b.count / vals.length : 0;
        b.density = step > 0 ? b.probability / step : b.probability;
      });
      return bins;
    }

    /**
     * renderModelOptimizationHeatmap  Render one read-only CV-partition matrix in a fixed-height viewport.
     * It visualizes legacy partition values using the shared rows=permutations and columns=folds convention.
     * The cell width and height are scaled independently so the matrix uses the available panel area without changing the fixed panel height for one-permutation/many-fold or many-permutation/few-fold designs.
     */
    function renderModelOptimizationHeatmap(matrixPayload, idx, opts){
      const isDashboardMatrix = !!(opts && opts.dashboard);
      const mat = modelOptimizationDisplayMatrix(matrixPayload && matrixPayload.matrix);
      if(!mat.length) return '';
      const rows = mat.length;
      const cols = mat.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      if(rows < 1 || cols < 1) return '';
      const w = 520, h = isDashboardMatrix ? 410 :
        Math.min(860,Math.max(175,Math.round(74+402*(rows/cols)*.835)));
      const P = plotTools();
      const xLabelsAll = Array.from({length:cols}, (_,i) => String(i+1));
      const yLabelsAll = Array.from({length:rows}, (_,i) => String(i+1));
      const heatLayout = P.categoricalHeatmapLayout({
        w, h, rows, cols,
        xLabels:xLabelsAll,
        yLabels:yLabelsAll,
        xLabel:currentPayload().partitions && currentPayload().partitions.xLabel || 'Folds',
        yLabel:currentPayload().partitions && currentPayload().partitions.yLabel || 'Permutations',
        m:isDashboardMatrix ? {left:58,right:18,top:16,bottom:52} : {left:86,right:32,top:18,bottom:56},
        tickFontSize:11,
        axisFontSize:isDashboardMatrix ? 13 : 16,
        xTickAngle:0,
        maxXTicks:Math.min(cols,10),
        maxYTicks:Math.min(rows,10)
      });
      const m = heatLayout.m;
      const plotW = heatLayout.plotW;
      const plotH = heatLayout.plotH;
      const cellW = heatLayout.cellW;
      const cellH = heatLayout.cellH;
      const gap = Math.min(1.2, Math.max(0.25, Math.min(cellW, cellH) * 0.045));
      const x0 = m.left;
      const y0 = m.top;
      const missingInfo = modelOptimizationMissingCellMask(mat);
      const vals = modelOptimizationFiniteMatrixValues(mat, missingInfo.mask);
      const lo = vals.length ? Math.min(...vals) : (Number.isFinite(Number(matrixPayload && matrixPayload.min)) ? Number(matrixPayload.min) : 0);
      const hi = vals.length ? Math.max(...vals) : (Number.isFinite(Number(matrixPayload && matrixPayload.max)) ? Number(matrixPayload.max) : 1);
      const span = Math.abs(hi - lo) < 1e-12 ? 1 : hi - lo;
      const tone = modelOptimizationSeriesCssColor(matrixPayload, idx);
      const labelCells = rows * cols <= 144 && cellW >= 22 && cellH >= 14;
      const cells = [];
      for(let r=0;r<rows;r++){
        for(let c=0;c<cols;c++){
          const v = Number(mat[r] && mat[r][c]);
          const missingCell = modelOptimizationIsMissingCell(missingInfo, r, c);
          const alpha = Number.isFinite(v) && !missingCell ? 0.16 + 0.74 * Math.max(0, Math.min(1, (v - lo) / span)) : 0.04;
          const x = x0 + c * cellW;
          const y = y0 + r * cellH;
          const cellX = x + gap/2;
          const cellY = y + gap/2;
          const rectW = Math.max(1, cellW-gap);
          const rectH = Math.max(1, cellH-gap);
          const tip = missingCell
            ? modelOptimizationPartitionTooltipText(matrixPayload, [`Permutation: ${r+1}`, `Fold: ${c+1}`, 'Value: uncomputed/missing'])
            : modelOptimizationPartitionTooltipText(matrixPayload, [`Permutation: ${r+1}`, `Fold: ${c+1}`, `${matrixPayload.valueLabel || 'Value'}: ${fmtMetric(v,4)}`]);
          if(missingCell){
            cells.push(`<rect class="rvModelOptHeatCell rvModelOptHeatCellMissing" x="${cellX.toFixed(1)}" y="${cellY.toFixed(1)}" width="${rectW.toFixed(1)}" height="${rectH.toFixed(1)}" tabindex="0" data-rv-tooltip="${esc(tip)}"></rect>`);
            cells.push(`<line class="rvModelOptHeatStrike" x1="${cellX.toFixed(1)}" y1="${(cellY + rectH).toFixed(1)}" x2="${(cellX + rectW).toFixed(1)}" y2="${cellY.toFixed(1)}"></line>`);
            continue;
          }
          cells.push(`<rect class="rvModelOptHeatCell" x="${cellX.toFixed(1)}" y="${cellY.toFixed(1)}" width="${rectW.toFixed(1)}" height="${rectH.toFixed(1)}" tabindex="0" data-rv-tooltip="${esc(tip)}" style="fill:${esc(tone)};fill-opacity:${alpha.toFixed(3)}"></rect>`);
          if(labelCells && Number.isFinite(v)){
            const cellText = fmtMatrixCell(v);
            const fontSize = Math.min(12.5, Math.max(8, Math.min(cellH * 0.42, cellW / Math.max(3.5, String(cellText).length * 0.62))));
            if(fontSize >= 8 && P.measureTextWidth(cellText, fontSize) <= Math.max(1, cellW - 4)){
              const textColor = P.cellTextColor(tone, alpha, '#ffffff');
              cells.push(`<text class="rvModelOptHeatCellValue" x="${(x + cellW/2).toFixed(1)}" y="${(y + cellH/2 + fontSize*0.34).toFixed(1)}" text-anchor="middle" style="fill:${textColor};font-size:${fontSize.toFixed(1)}px">${esc(cellText)}</text>`);
            }
          }
        }
      }
      const axisSvg = heatLayout.axisSvg;
      const missingNote = missingInfo.count > 0 ? `; ${missingInfo.count} cells marked uncomputed/missing` : '';
      return `<div class="rvModelOptHeatmap${isDashboardMatrix ? ' rvModelOptHeatmapDashboard' : ''}" data-rv-rows="${rows}" data-rv-cols="${cols}"><div class="rvModelOptHeatTitle">${esc(matrixPayload.title || `Partition matrix ${idx+1}`)}</div><svg class="rvModelOptHeatSvg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMin meet" role="img" aria-label="${esc(matrixPayload.title || 'CV partition matrix')}">${cells.join('')}${axisSvg}</svg><div class="rvModelOptTooltip" role="status" aria-live="polite"></div><div class="rvModelOptHeatRange">${esc(matrixPayload.valueLabel || 'Value')}: ${fmtMetric(lo,4)} – ${fmtMetric(hi,4)}${esc(missingNote)}</div></div>`;
    }

    /**
     * renderModelOptimizationHistogram  Render a histogram of finite optimization-criterion values from one CV matrix.
     * Bins are over the performance/criterion values stored in the matrix; bar height is empirical probability, not a partition index or mean partition value.
     */
    function renderModelOptimizationHistogram(matrixPayload, idx, opts){
      const isDashboardMatrix = !!(opts && opts.dashboard);
      const mat = modelOptimizationDisplayMatrix(matrixPayload && matrixPayload.matrix);
      const missingInfo = modelOptimizationMissingCellMask(mat);
      const vals = modelOptimizationFiniteMatrixValues(mat, missingInfo.mask);
      const bins = modelOptimizationHistogramBins(vals, 8);
      if(!bins.length) return '';
      const xVals = bins.flatMap(b => [Number(b.lo), Number(b.hi)]).filter(Number.isFinite);
      let xMin = xVals.length ? Math.min(...xVals) : 0;
      let xMax = xVals.length ? Math.max(...xVals) : 1;
      if(Math.abs(xMax - xMin) < 1e-12){ xMin -= 0.5; xMax += 0.5; }
      const pVals = bins.map(b => Number(b.probability)).filter(Number.isFinite);
      let yMax = Math.max(0.05, ...pVals);
      yMax = Math.min(1, yMax * 1.12);
      const w = isDashboardMatrix ? 520 : 640, h = isDashboardMatrix ? 410 : 340;
      const ax = plotTools().cartesianAxes({w,h,m:{left:76,right:28,top:34,bottom:62},xLim:[xMin,xMax],yLim:[0,yMax],xTicks:niceTicks(xMin,xMax,6),yTicks:niceTicks(0,yMax,5),xFmt:fmtTick,yFmt:fmtTick,xLabel:matrixPayload.valueLabel || 'Optimization criterion',yLabel:'Probability',autoMargin:true});
      const tone = modelOptimizationSeriesCssColor(matrixPayload, idx);
      const bars = bins.map((b,i) => {
        const xA = ax.xPix(Number(b.lo));
        const xB = ax.xPix(Number(b.hi));
        const x = Math.min(xA,xB) + 1;
        const barW = Math.max(3, Math.abs(xB - xA) - 2);
        const y = ax.yPix(Number.isFinite(b.probability) ? b.probability : 0);
        const y0 = ax.yPix(0);
        const hBar = Math.max(1, Math.abs(y0 - y));
        const top = Math.min(y,y0);
        const tip = modelOptimizationPartitionTooltipText(matrixPayload, [`${matrixPayload.valueLabel || 'Criterion'} bin: ${fmtMetric(b.lo,4)} – ${fmtMetric(b.hi,4)}`, `Probability: ${fmtMetric(b.probability,4)}`, `Density: ${fmtMetric(b.density,4)}`, `Cells: ${b.count}`]);
        return `<rect class="rvModelOptHistBar" x="${x.toFixed(1)}" y="${top.toFixed(1)}" width="${barW.toFixed(1)}" height="${hBar.toFixed(1)}" tabindex="0" data-rv-tooltip="${esc(tip)}" style="fill:${esc(tone)}"></rect>`;
      }).join('');
      const missingNote = missingInfo.count > 0 ? ` ${missingInfo.count} inferred uncomputed cells were excluded.` : '';
      return `<div class="rvModelOptHistogram${isDashboardMatrix ? ' rvModelOptHistogramDashboard' : ''}" data-rv-rows="${mat.length}" data-rv-cols="${mat[0].length}"><div class="rvModelOptHeatTitle">${esc(matrixPayload.title || `Partition matrix ${idx+1}`)} — criterion histogram</div><svg class="rvModelOptHistSvg" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(matrixPayload.title || 'CV criterion histogram')}">${ax.svg}${bars}</svg><div class="rvModelOptTooltip" role="status" aria-live="polite"></div><div class="rvModelOptHeatRange">Histogram bins are finite ${esc(matrixPayload.valueLabel || 'optimization criterion')} values; bar height is empirical probability across CV cells.${esc(missingNote)}</div></div>`;
    }

    /**
     * renderModelOptimizationPartitionDisplay  Render one CV partition matrix in the active matrix/histogram mode.
     * It centralizes the Stage 4a matrix toggle so selected-metric and dashboard panels stay synchronized.
     */
    function renderModelOptimizationPartitionDisplay(matrixPayload, idx, opts){
      return MODEL_OPT_MATRIX_VIEW === 'histogram' ? renderModelOptimizationHistogram(matrixPayload, idx, opts) : renderModelOptimizationHeatmap(matrixPayload, idx, opts);
    }

    /**
     * renderModelOptimizationPartitions  Render the partition panel for the selected metric.
     * It shows only matrices whose legacy fields are available and reports explicit reasons when no partition plot applies.
     */
    function renderModelOptimizationPartitions(){
      const node = el('modelOptimizationPartitions');
      if(!node) return;
      const metric = selectedModelOptimizationMetric();
      if(!metric || !metric.available){
        node.innerHTML = `<div class="rvEmpty">No selected optimization metric is available.</div>`;
        return;
      }
      if(!metric.supportsPartitionHeatmap){
        node.innerHTML = `<div class="rvModelOptPartitionToolbar">${renderModelOptimizationMatrixViewToggle()}</div><div class="rvPanelNotice">${esc(metric.label || 'Selected metric')} has no legacy CV-partition heatmap in display_modelperf.</div>`;
        bindModelOptimizationMatrixViewToggles(node);
        return;
      }
      const matrices = modelOptimizationPartitionForMetric(metric);
      if(!matrices.length){
        node.innerHTML = `<div class="rvModelOptPartitionToolbar">${renderModelOptimizationMatrixViewToggle()}</div><div class="rvPanelNotice">Partition matrices for ${esc(metric.label || 'selected metric')} were not present in the selected GDdims container.</div>`;
        bindModelOptimizationMatrixViewToggles(node);
        return;
      }
      node.innerHTML = `<div class="rvModelOptPartitionToolbar">${renderModelOptimizationMatrixViewToggle()}</div><div class="rvModelOptPartitionGrid">${matrices.map((m,i) => renderModelOptimizationPartitionDisplay(m,i)).join('')}</div>`;
      bindModelOptimizationMatrixViewToggles(node);
      Array.from(node.querySelectorAll('.rvModelOptHeatmap,.rvModelOptHistogram')).forEach(panel => bindModelOptimizationPartitionTooltips(panel));
    }

    /**
     * modelOptimizationMetricFiniteSeriesChoices  List finite series choices for one optimization metric.
     * metric.values: Stage 1 metric value matrix indexed by parameter combination and metric series.
     * metric.seriesLabels: optional backend labels retained for user-facing selectors and tooltips.
     */
    function modelOptimizationMetricFiniteSeriesChoices(metric){
      const values = modelOptimizationMatrix(metric && metric.values);
      const nSeries = values.reduce((acc,r) => Math.max(acc, arr(r).length), 0);
      const labels = modelOptimizationSeriesLabels(metric, nSeries);
      const out = [];
      for(let j=0;j<nSeries;j++){
        let finite = 0;
        for(let i=0;i<values.length;i++) if(Number.isFinite(Number(values[i] && values[i][j]))) finite++;
        if(finite > 0) out.push({index:j, label:labels[j] || `Series ${j+1}`, finiteCount:finite});
      }
      return out;
    }

    /**
     * modelOptimizationSurfaceMetricPool  Return metrics eligible for 2D parameter surface views.
     * It reuses the Stage 1 metric registry and requires only finite values on the active parameter grid; it does not request or compute new MATLAB results.
     */
    function modelOptimizationSurfaceMetricPool(){
      return modelOptimizationAvailablePanelMetrics().filter(m => m.plotKind !== 'sequence_curve' && modelOptimizationMetricFiniteSeriesChoices(m).length > 0);
    }

    /**
     * modelOptimizationSurfaceSelectedMetric  Resolve the active metric for the 2D parameter view.
     * The resolver prefers the browser-local surface selection, then the top optimization metric, and finally the first finite registry metric.
     */
    function modelOptimizationSurfaceSelectedMetric(metrics){
      const list = arr(metrics);
      if(!list.length) return null;
      const wanted = String(MODEL_OPT_SURFACE_STATE.metricId || '');
      let metric = wanted ? list.find((m,i) => modelOptimizationMetricKey(m,i) === wanted || String(m && m.id || '') === wanted) : null;
      if(!metric){
        const selected = selectedModelOptimizationMetric();
        metric = list.find(m => m === selected || (m && selected && String(m.id || '') && String(m.id || '') === String(selected.id || ''))) || null;
      }
      metric = metric || list[0];
      const idx = list.indexOf(metric);
      MODEL_OPT_SURFACE_STATE.metricId = modelOptimizationMetricKey(metric, idx < 0 ? 0 : idx);
      return metric;
    }

    /**
     * modelOptimizationParameterValueText  Return one display-safe parameter value for a grid row and parameter column.
     * row.values: backend parameter-combination values copied from legacy Model.ParamCombs without scientific reinterpretation.
     */
    function modelOptimizationParameterValueText(row, paramIndex){
      const values = arr(row && row.values);
      const raw = values[paramIndex];
      const txt = String(raw == null ? '' : raw).trim();
      return txt || '(empty)';
    }

    /**
     * modelOptimizationNaturalSortValues  Sort categorical or numeric parameter levels for 2D heatmap axes.
     * Numeric-looking levels are sorted numerically; otherwise labels are sorted lexically without changing the displayed values.
     */
    function modelOptimizationNaturalSortValues(values){
      const unique = Array.from(new Set(arr(values).map(v => String(v == null ? '' : v)))).filter(v => v !== '');
      const numeric = unique.map(v => Number(String(v).replace(',', '.')));
      if(unique.length && numeric.every(Number.isFinite)){
        return unique.map((v,i) => ({v, n:numeric[i]})).sort((a,b) => a.n - b.n || a.v.localeCompare(b.v)).map(x => x.v);
      }
      return unique.sort((a,b) => a.localeCompare(b, undefined, {numeric:true, sensitivity:'base'}));
    }

    /**
     * modelOptimizationParameterAxes  Discover varying legacy hyperparameter columns for 2D parameter views.
     * It operates on payload.grid.parameterRows only and therefore keeps the Results Viewer non-mutating and independent of GUIDE handle state.
     */
    function modelOptimizationParameterAxes(grid){
      const rows = arr(grid.parameterRows);
      const names = arr(grid.parameterNames);
      const nParams = Math.max(names.length, rows.reduce((acc,row) => Math.max(acc, arr(row && row.values).length), 0));
      const axes = [];
      for(let p=0;p<nParams;p++){
        const values = rows.map(row => modelOptimizationParameterValueText(row, p));
        const levels = modelOptimizationNaturalSortValues(values);
        axes.push({
          index:p,
          label:String(names[p] || `Parameter ${p+1}`),
          levels,
          varying:levels.length > 1,
          completeCount:values.filter(v => v !== '(empty)').length
        });
      }
      return axes.filter(a => a.varying);
    }

    /**
     * modelOptimizationResolveSurfaceState  Normalize the browser-local 2D parameter-view state against the current payload.
     * It prevents invalid selector states by snapping to finite metrics, finite series and two distinct varying parameter axes.
     */
    function modelOptimizationResolveSurfaceState(){
      const metrics = modelOptimizationSurfaceMetricPool();
      const metric = modelOptimizationSurfaceSelectedMetric(metrics);
      const series = modelOptimizationMetricFiniteSeriesChoices(metric);
      if(!series.some(s => Number(s.index) === Number(MODEL_OPT_SURFACE_STATE.seriesIndex))){
        MODEL_OPT_SURFACE_STATE.seriesIndex = series.length ? Number(series[0].index) : 0;
      }
      const axes = modelOptimizationParameterAxes(currentPayload().grid);
      const axisIndexes = axes.map(a => Number(a.index));
      if(axisIndexes.indexOf(Number(MODEL_OPT_SURFACE_STATE.xParam)) < 0){
        MODEL_OPT_SURFACE_STATE.xParam = axisIndexes.length ? axisIndexes[0] : 0;
      }
      if(axisIndexes.indexOf(Number(MODEL_OPT_SURFACE_STATE.yParam)) < 0 || Number(MODEL_OPT_SURFACE_STATE.yParam) === Number(MODEL_OPT_SURFACE_STATE.xParam)){
        const alt = axisIndexes.find(x => Number(x) !== Number(MODEL_OPT_SURFACE_STATE.xParam));
        MODEL_OPT_SURFACE_STATE.yParam = Number.isFinite(Number(alt)) ? Number(alt) : (axisIndexes.length > 1 ? axisIndexes[1] : 1);
      }
      const aggs = ['mean','median','best','max','min'];
      if(aggs.indexOf(String(MODEL_OPT_SURFACE_STATE.aggregation || '')) < 0) MODEL_OPT_SURFACE_STATE.aggregation = 'mean';
      return {metrics, metric, series, axes, xAxis:axes.find(a => Number(a.index) === Number(MODEL_OPT_SURFACE_STATE.xParam)) || null, yAxis:axes.find(a => Number(a.index) === Number(MODEL_OPT_SURFACE_STATE.yParam)) || null};
    }

    /**
     * modelOptimizationAggregateValues  Aggregate metric values contributing to one 2D parameter heatmap cell.
     * aggregation: browser-selected rule; "best" respects higherIsBetter/lowerIsBetter metadata when available and never changes model selection in NM.
     */
    function modelOptimizationAggregateValues(values, aggregation, metric){
      const vals = arr(values).map(Number).filter(Number.isFinite);
      if(!vals.length) return NaN;
      const mode = String(aggregation || 'mean').toLowerCase();
      if(mode === 'min') return Math.min(...vals);
      if(mode === 'max') return Math.max(...vals);
      if(mode === 'best'){
        if(metric && metric.lowerIsBetter) return Math.min(...vals);
        return Math.max(...vals);
      }
      if(mode === 'median'){
        const sorted = vals.slice().sort((a,b) => a-b);
        const mid = Math.floor(sorted.length/2);
        return sorted.length % 2 ? sorted[mid] : (sorted[mid-1] + sorted[mid]) / 2;
      }
      return vals.reduce((a,b) => a+b, 0) / vals.length;
    }

    /**
     * modelOptimizationSurfaceCellStats  Summarize values contributing to one parameter-surface cell.
     * The returned statistics are shown in tooltips only; they do not replace or mutate the backend metric registry.
     */
    function modelOptimizationSurfaceCellStats(values, indices, metric){
      const vals = arr(values).map(Number).filter(Number.isFinite);
      if(!vals.length) return {count:0, mean:NaN, sd:NaN, min:NaN, max:NaN, bestIndex:0};
      const mean = vals.reduce((a,b) => a+b, 0) / vals.length;
      const sd = vals.length > 1 ? Math.sqrt(vals.reduce((a,b) => a + Math.pow(b - mean, 2), 0) / (vals.length - 1)) : 0;
      const min = Math.min(...vals), max = Math.max(...vals);
      let bestPos = 0;
      for(let i=1;i<vals.length;i++){
        const better = metric && metric.lowerIsBetter ? vals[i] < vals[bestPos] : vals[i] > vals[bestPos];
        if(better) bestPos = i;
      }
      return {count:vals.length, mean, sd, min, max, bestIndex:Number(arr(indices)[bestPos] || 0)};
    }

    /**
     * modelOptimizationSurfaceData  Aggregate one metric series across two selected hyperparameter dimensions.
     * It creates a read-only browser-side matrix where columns are X-parameter levels and rows are Y-parameter levels.
     */
    function modelOptimizationSurfaceData(metric, seriesIndex, xAxis, yAxis, aggregation){
      const values = modelOptimizationMatrix(metric && metric.values);
      const rows = arr(currentPayload() && currentPayload().grid && currentPayload().grid.parameterRows);
      if(!metric || !xAxis || !yAxis || !values.length || !rows.length) return {ok:false, message:'2D parameter surface cannot be built for the current payload.'};
      const xLevels = arr(xAxis.levels);
      const yLevels = arr(yAxis.levels);
      const groups = new Map();
      let finitePairs = 0;
      for(let i=0;i<rows.length;i++){
        const v = Number(values[i] && values[i][seriesIndex]);
        if(!Number.isFinite(v)) continue;
        const xVal = modelOptimizationParameterValueText(rows[i], Number(xAxis.index));
        const yVal = modelOptimizationParameterValueText(rows[i], Number(yAxis.index));
        if(xLevels.indexOf(xVal) < 0 || yLevels.indexOf(yVal) < 0) continue;
        const key = `${xVal}\u0001${yVal}`;
        if(!groups.has(key)) groups.set(key, {xVal, yVal, values:[], indices:[]});
        const g = groups.get(key);
        g.values.push(v);
        g.indices.push(i+1);
        finitePairs++;
      }
      const matrix = [];
      const cells = [];
      for(let r=0;r<yLevels.length;r++){
        const row = [];
        for(let c=0;c<xLevels.length;c++){
          const key = `${xLevels[c]}\u0001${yLevels[r]}`;
          const g = groups.get(key) || {xVal:xLevels[c], yVal:yLevels[r], values:[], indices:[]};
          const agg = modelOptimizationAggregateValues(g.values, aggregation, metric);
          const stats = modelOptimizationSurfaceCellStats(g.values, g.indices, metric);
          row.push(agg);
          cells.push(Object.assign({row:r, col:c, xVal:xLevels[c], yVal:yLevels[r], value:agg, indices:g.indices.slice(0)}, stats));
        }
        matrix.push(row);
      }
      return {ok:finitePairs > 0, message:finitePairs > 0 ? '' : 'No finite metric values matched the selected parameter axes.', xLevels, yLevels, matrix, cells, finitePairs};
    }

    /**
     * modelOptimizationSurfaceControlHtml  Build selectors for the 2D parameter heatmap panel.
     * It exposes metric, two parameter axes and aggregation rule without adding MATLAB bridge calls or mutating NM; all available series are rendered side by side so CV1/CV2 surfaces can be inspected together.
     */
    function modelOptimizationSurfaceControlHtml(ctx){
      const metricOptions = arr(ctx.metrics).map((m,i) => {
        const key = modelOptimizationMetricKey(m,i);
        const on = key === MODEL_OPT_SURFACE_STATE.metricId;
        return `<option value="${esc(key)}"${on ? ' selected' : ''}>${esc(m.label || `Metric ${i+1}`)}</option>`;
      }).join('');
      const paramOptions = arr(ctx.axes).map(a => `<option value="${esc(a.index)}">${esc(a.label)} (${esc(a.levels.length)} levels)</option>`).join('');
      const agg = String(MODEL_OPT_SURFACE_STATE.aggregation || 'mean');
      const aggOptions = [
        ['mean','Mean'], ['median','Median'], ['best','Best, direction-aware'], ['max','Maximum'], ['min','Minimum']
      ].map(x => `<option value="${x[0]}"${agg === x[0] ? ' selected' : ''}>${esc(x[1])}</option>`).join('');
      const seriesNote = arr(ctx.series).length > 1 ? `<span class="rvModelOptSurfaceSeriesNote">${esc(arr(ctx.series).length)} series shown side by side</span>` : '';
      return `<div class="rvModelOptSurfaceControls"><label>Metric <select id="modelOptSurfaceMetricSelect">${metricOptions}</select></label><label>X parameter <select id="modelOptSurfaceXParamSelect">${paramOptions}</select></label><label>Y parameter <select id="modelOptSurfaceYParamSelect">${paramOptions}</select></label><label>Aggregation <select id="modelOptSurfaceAggSelect">${aggOptions}</select></label>${seriesNote}</div>`;
    }

    /**
     * modelOptimizationSurfaceTooltipText  Compose hover text for a 2D parameter heatmap cell.
     * It reports contributing model-grid rows and summary statistics so aggregation is auditable in the browser UI.
     */
    function modelOptimizationSurfaceTooltipText(metric, seriesLabel, xAxis, yAxis, cell, aggregation){
      const lines = [];
      lines.push('2D parameter cell');
      lines.push(`${xAxis.label}: ${cell.xVal}`);
      lines.push(`${yAxis.label}: ${cell.yVal}`);
      lines.push(`Metric: ${metric && metric.label || 'Optimization metric'}`);
      if(seriesLabel) lines.push(`Series: ${seriesLabel}`);
      lines.push(`Aggregation: ${aggregation}`);
      lines.push(`Aggregated value: ${fmtMetric(cell.value,4)}`);
      lines.push(`Contributing models: ${cell.count}`);
      lines.push(`Mean / SD: ${fmtMetric(cell.mean,4)} / ${fmtMetric(cell.sd,4)}`);
      lines.push(`Min / Max: ${fmtMetric(cell.min,4)} / ${fmtMetric(cell.max,4)}`);
      if(cell.bestIndex) lines.push(`Best contributing model index: ${cell.bestIndex}`);
      if(cell.indices && cell.indices.length) lines.push(`Model indices: ${cell.indices.slice(0,12).join(', ')}${cell.indices.length > 12 ? ', …' : ''}`);
      return lines.join('\n');
    }

    /**
     * modelOptimizationSurfaceHotColor  Map normalized 2D parameter-surface values to a hot-style color ramp.
     * The surface color map is intentionally distinct from the blue CV-partition matrices because parameter surfaces encode hyperparameter-response structure rather than fold/permutation partition values.
     * norm: finite value in [0,1] after metric-range normalization.
     */
    function modelOptimizationSurfaceHotColor(norm){
      const t = Math.max(0, Math.min(1, Number(norm)));
      const r = Math.round(255 * Math.min(1, 2.8 * t));
      const g = Math.round(255 * Math.max(0, Math.min(1, 2.8 * t - 0.9)));
      const b = Math.round(255 * Math.max(0, Math.min(1, 2.8 * t - 1.8)));
      return `rgb(${r},${g},${b})`;
    }

    /**
     * modelOptimizationSurfaceColorNorm  Convert a metric value to the hot-ramp coordinate used by 2D parameter surfaces.
     * The visual invariant is that darker cells indicate better optimization values: high-performing metrics are inverted before color mapping, while lower-is-better metrics keep the ordinary low-to-dark hot coordinate.
     * metric.higherIsBetter: explicit backend/API flag for metrics whose larger values are preferable.
     * metric.lowerIsBetter: explicit backend/API flag for metrics whose smaller values are preferable.
     * value: finite aggregate cell value from the 2D parameter surface.
     * sharedLo/sharedHi: shared range across simultaneously displayed series so paired CV1/CV2 surfaces are comparable.
     */
    function modelOptimizationSurfaceColorNorm(metric, value, sharedLo, sharedHi){
      const v = Number(value);
      const lo = Number(sharedLo);
      const hi = Number(sharedHi);
      if(!Number.isFinite(v) || !Number.isFinite(lo) || !Number.isFinite(hi)) return NaN;
      const span = Math.abs(hi - lo) < 1e-12 ? 1 : hi - lo;
      const norm = Math.max(0, Math.min(1, (v - lo) / span));
      return modelOptimizationObjectiveDirection(metric) === 'min' ? norm : 1 - norm;
    }

    /**
     * modelOptimizationSurfaceColorbarStyle  Return the direction-aware hot colorbar gradient for 2D parameter surfaces.
     * The labels remain low-to-high from left to right, while the gradient direction changes so the better end of the selected metric appears darker.
     */
    function modelOptimizationSurfaceColorbarStyle(metric){
      const forward = 'linear-gradient(90deg,#0b0b0b 0%,#7f0000 25%,#ff0000 50%,#ffff00 75%,#fff 100%)';
      const inverted = 'linear-gradient(90deg,#fff 0%,#ffff00 25%,#ff0000 50%,#7f0000 75%,#0b0b0b 100%)';
      return modelOptimizationObjectiveDirection(metric) === 'min' ? forward : inverted;
    }

    /**
     * renderModelOptimizationSurfaceHeatmap  Render the Stage 5a 2D hyperparameter heatmap.
     * Columns are X-parameter levels, rows are Y-parameter levels, and each cell is an aggregation over all remaining parameter dimensions.
     */
    function renderModelOptimizationSurfaceHeatmap(surface, ctx, seriesLabel, colorRange){
      const xLevels = arr(surface.xLevels);
      const yLevels = arr(surface.yLevels);
      if(!surface.ok || !xLevels.length || !yLevels.length) return `<div class="rvPanelNotice">${esc(surface.message || 'No finite 2D parameter-surface values are available.')}</div>`;
      const w = 980, h = 570;
      const P = plotTools();
      const heatLayout = P.categoricalHeatmapLayout({
        w, h,
        rows:yLevels.length,
        cols:xLevels.length,
        xLabels:xLevels,
        yLabels:yLevels,
        xLabel:ctx.xAxis && ctx.xAxis.label || 'X parameter',
        yLabel:ctx.yAxis && ctx.yAxis.label || 'Y parameter',
        m:{left:112,right:34,top:24,bottom:82},
        tickFontSize:11,
        axisFontSize:16,
        xTickAngle:-28,
        maxXTicks:12,
        maxYTicks:10
      });
      const m = heatLayout.m;
      const plotW = heatLayout.plotW;
      const plotH = heatLayout.plotH;
      const cellW = heatLayout.cellW;
      const cellH = heatLayout.cellH;
      const vals = arr(surface.cells).map(c => Number(c.value)).filter(Number.isFinite);
      const localLo = vals.length ? Math.min(...vals) : 0;
      const localHi = vals.length ? Math.max(...vals) : 1;
      const sharedLo = colorRange && Number.isFinite(Number(colorRange.lo)) ? Number(colorRange.lo) : localLo;
      const sharedHi = colorRange && Number.isFinite(Number(colorRange.hi)) ? Number(colorRange.hi) : localHi;
      const direction = modelOptimizationObjectiveDirection(ctx.metric);
      const bestValue = vals.length ? (direction === 'min' ? Math.min(...vals) : Math.max(...vals)) : NaN;
      const showCellLabels = xLevels.length * yLevels.length <= 120 && cellW >= 30 && cellH >= 18;
      const cells = arr(surface.cells).map(cell => {
        const v = Number(cell.value);
        const norm = modelOptimizationSurfaceColorNorm(ctx.metric, v, sharedLo, sharedHi);
        const fill = Number.isFinite(norm) ? modelOptimizationSurfaceHotColor(norm) : '#f8fafc';
        const x = m.left + Number(cell.col) * cellW;
        const y = m.top + Number(cell.row) * cellH;
        const isBest = Number.isFinite(v) && Number.isFinite(bestValue) && Math.abs(v - bestValue) <= Math.max(1e-10, Math.abs(bestValue) * 1e-10);
        const tip = modelOptimizationSurfaceTooltipText(ctx.metric, seriesLabel, ctx.xAxis, ctx.yAxis, cell, MODEL_OPT_SURFACE_STATE.aggregation);
        const fillOpacity = Number.isFinite(norm) ? 0.96 : 0.10;
        const textColor = P.cellTextColor(fill, fillOpacity, '#ffffff');
        const rect = `<rect class="rvModelOptSurfaceCell${isBest ? ' isBestSurfaceCell' : ''}" x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${Math.max(1,cellW-1).toFixed(1)}" height="${Math.max(1,cellH-1).toFixed(1)}" tabindex="0" data-rv-tooltip="${esc(tip)}" style="fill:${fill};fill-opacity:${fillOpacity.toFixed(2)}"></rect>`;
        if(!showCellLabels || !Number.isFinite(v)) return rect;
        const cellText = fmtMatrixCell(v);
        const fontSize = isBest ? Math.min(15, Math.max(10, Math.min(cellH * 0.46, cellW / Math.max(3.5, String(cellText).length * 0.56)))) : Math.min(13, Math.max(8.5, Math.min(cellH * 0.38, cellW / Math.max(3.8, String(cellText).length * 0.62))));
        if(fontSize < 8.5 || P.measureTextWidth(cellText, fontSize) > Math.max(1, cellW - 5)) return rect;
        const valueText = `<text class="rvModelOptSurfaceCellValue${isBest ? ' isBestSurfaceText' : ''}" x="${(x + cellW/2).toFixed(1)}" y="${(y + cellH/2 + fontSize*0.34).toFixed(1)}" text-anchor="middle" style="fill:${textColor};font-size:${fontSize.toFixed(1)}px">${esc(cellText)}</text>`;
        const bestOutline = isBest ? `<rect class="rvModelOptSurfaceBestOutline" x="${(x+1.6).toFixed(1)}" y="${(y+1.6).toFixed(1)}" width="${Math.max(1,cellW-4.2).toFixed(1)}" height="${Math.max(1,cellH-4.2).toFixed(1)}"></rect>` : '';
        return rect + bestOutline + valueText;
      }).join('');
      const axisSvg = heatLayout.axisSvg;
      const note = `Cells aggregate ${esc(ctx.metric && ctx.metric.label || 'optimization metric')} over non-displayed parameters; finite model rows used: ${esc(surface.finitePairs)}.`;
      const title = seriesLabel ? `${esc(seriesLabel)} — ${esc(ctx.metric && ctx.metric.label || 'Metric')}` : esc(ctx.metric && ctx.metric.label || 'Metric');
      const rampStyle = modelOptimizationSurfaceColorbarStyle(ctx.metric);
      const colorbar = `<div class="rvModelOptSurfaceColorbar" aria-label="Shared color range"><span>${fmtMetric(sharedLo,4)}</span><div class="rvModelOptSurfaceColorbarRamp" style="background:${esc(rampStyle)}"></div><span>${fmtMetric(sharedHi,4)}</span></div>`;
      return `<div class="rvModelOptSurfaceHeatmap"><div class="rvModelOptSurfacePanelTitle">${title}</div><svg class="rvModelOptSurfaceSvg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMin meet" role="img" aria-label="2D parameter heatmap">${cells}${axisSvg}</svg>${colorbar}<div class="rvModelOptTooltip" role="status" aria-live="polite"></div><div class="rvModelOptSurfaceRange">${esc(ctx.metric && ctx.metric.label || 'Metric')}: local ${fmtMetric(localLo,4)} – ${fmtMetric(localHi,4)}; shared color range ${fmtMetric(sharedLo,4)} – ${fmtMetric(sharedHi,4)}. ${note}</div></div>`;
    }

    /**
     * bindModelOptimizationSurfaceControls  Attach 2D parameter-view selector handlers.
     * Side effects: updates browser-local surface controls and re-renders the Stage 5a panel only; no MATLAB round-trip is performed.
     */
    function bindModelOptimizationSurfaceControls(){
      const metricSel = el('modelOptSurfaceMetricSelect');
      const xSel = el('modelOptSurfaceXParamSelect');
      const ySel = el('modelOptSurfaceYParamSelect');
      const aggSel = el('modelOptSurfaceAggSelect');
      if(metricSel) metricSel.addEventListener('change', () => { MODEL_OPT_SURFACE_STATE.metricId = String(metricSel.value || ''); MODEL_OPT_SURFACE_STATE.seriesIndex = 0; renderModelOptimizationSurface(); });
      if(xSel) { xSel.value = String(MODEL_OPT_SURFACE_STATE.xParam); xSel.addEventListener('change', () => { MODEL_OPT_SURFACE_STATE.xParam = Math.max(0, Math.round(Number(xSel.value || 0))); if(Number(MODEL_OPT_SURFACE_STATE.xParam) === Number(MODEL_OPT_SURFACE_STATE.yParam)) MODEL_OPT_SURFACE_STATE.yParam = -1; renderModelOptimizationSurface(); }); }
      if(ySel) { ySel.value = String(MODEL_OPT_SURFACE_STATE.yParam); ySel.addEventListener('change', () => { MODEL_OPT_SURFACE_STATE.yParam = Math.max(0, Math.round(Number(ySel.value || 0))); if(Number(MODEL_OPT_SURFACE_STATE.xParam) === Number(MODEL_OPT_SURFACE_STATE.yParam)) MODEL_OPT_SURFACE_STATE.xParam = -1; renderModelOptimizationSurface(); }); }
      if(aggSel) aggSel.addEventListener('change', () => { MODEL_OPT_SURFACE_STATE.aggregation = String(aggSel.value || 'mean'); renderModelOptimizationSurface(); });
      [metricSel,xSel,ySel,aggSel].filter(Boolean).forEach(control=>control.addEventListener('change',onContentChanged));
    }

    /**
     * bindModelOptimizationSurfaceTooltips  Activate hover inspection for 2D parameter-surface cells.
     * It reuses the model-optimization tooltip contract and applies only transient browser classes.
     */
    function bindModelOptimizationSurfaceTooltips(){
      const node = el('modelOptimizationSurface');
      if(!node) return;
      Array.from(node.querySelectorAll('.rvModelOptSurfaceHeatmap')).forEach(panel => bindModelOptimizationPartitionTooltips(panel));
    }

    /**
     * renderModelOptimizationSurface  Render the Stage 5a 2D parameter heatmap view.
     * The panel is a browser-only aggregation of existing metric registry values across two selected Model.ParamCombs columns and does not mutate NM.
     */
    function renderModelOptimizationSurface(){
      const node = el('modelOptimizationSurface');
      if(!node) return;
      if(!currentPayload() || currentPayload().ok === false){
        node.innerHTML = `<div class="rvPanelNotice">${esc(currentPayload() && currentPayload().message || 'Model optimization payload unavailable.')}</div>`;
        return;
      }
      const ctx = modelOptimizationResolveSurfaceState();
      if(!ctx.metric){
        node.innerHTML = '<div class="rvPanelNotice">No finite optimization metric is available for a 2D parameter view.</div>';
        return;
      }
      if(ctx.axes.length < 2){
        node.innerHTML = '<div class="rvPanelNotice">The selected model grid has fewer than two varying hyperparameters; a 2D parameter view is not defined.</div>';
        return;
      }
      const controls = modelOptimizationSurfaceControlHtml(ctx);
      const seriesList = arr(ctx.series).length ? arr(ctx.series) : [{index:0,label:''}];
      const surfaceItems = seriesList.map(s => {
        const idx = Math.max(0, Math.round(Number(s.index || 0)));
        const surface = modelOptimizationSurfaceData(ctx.metric, idx, ctx.xAxis, ctx.yAxis, MODEL_OPT_SURFACE_STATE.aggregation);
        return {surface, label: s.label || `Series ${idx+1}`};
      });
      const sharedValues = surfaceItems.flatMap(item => arr(item.surface && item.surface.cells).map(c => Number(c.value)).filter(Number.isFinite));
      const sharedRange = sharedValues.length ? {lo: Math.min(...sharedValues), hi: Math.max(...sharedValues)} : null;
      const heatmaps = surfaceItems.map(item => renderModelOptimizationSurfaceHeatmap(item.surface, ctx, item.label, sharedRange)).join('');
      node.innerHTML = `<div class="rvModelOptSurfaceHeader"><div><strong>2D parameter view</strong><span>Aggregate one optimization metric over two legacy Model.ParamCombs dimensions. Multi-series metrics are shown side by side.</span></div></div>${controls}<div class="rvModelOptSurfaceSeriesGrid">${heatmaps}</div>`;
      bindModelOptimizationSurfaceControls();
      bindModelOptimizationSurfaceTooltips();
    }

    /**
     * modelOptimizationComparisonCache  Return the comparison cache for the current model-optimization payload.
     * The cache is invalidated by payload object identity, so derived arrays cannot leak across analyses, targets, sources, or refreshed NM state.
     */
    function modelOptimizationComparisonCache(){
      if(MODEL_OPT_COMPARISON_CACHE.payload !== currentPayload()){
        MODEL_OPT_COMPARISON_CACHE.payload = currentPayload();
        MODEL_OPT_COMPARISON_CACHE.metric = new WeakMap();
        MODEL_OPT_COMPARISON_CACHE.pair = new Map();
        MODEL_OPT_COMPARISON_CACHE.pareto = new Map();
      }
      return MODEL_OPT_COMPARISON_CACHE;
    }

    /**
     * modelOptimizationComparisonMetricData  Decode one optimization metric and its uncertainty matrix once per payload.
     * The returned matrices preserve missing values as NaN through modelOptimizationMatrix and are read-only browser derivatives.
     */
    function modelOptimizationComparisonMetricData(metric){
      if(!metric || (typeof metric !== 'object' && typeof metric !== 'function')){
        return {values:modelOptimizationMatrix(metric && metric.values), sem:modelOptimizationMatrix(metric && metric.sem), uniqueCounts:new Map()};
      }
      const cache = modelOptimizationComparisonCache();
      let out = cache.metric.get(metric);
      if(!out){
        out = {values:modelOptimizationMatrix(metric.values), sem:modelOptimizationMatrix(metric.sem), uniqueCounts:new Map()};
        cache.metric.set(metric, out);
      }
      return out;
    }

    /**
     * modelOptimizationComparisonPairCacheKey  Build a stable cache key for one selected metric pair within the current payload.
     * Series pairing is derived deterministically from the selected metric descriptors, so the two metric keys fully identify the paired point set.
     */
    function modelOptimizationComparisonPairCacheKey(ctx){
      return `${String(ctx && ctx.xKey || '')}::${String(ctx && ctx.yKey || '')}`;
    }

    /**
     * modelOptimizationComparisonSeriesUniqueCount  Count distinct finite values in one metric series.
     * metric: Stage 1 optimization metric registry entry; seriesIndex: zero-based series column used by the browser plot.
     * Returns the exact finite-value uniqueness count so constant criteria can be excluded from scatter comparison controls.
     */
    function modelOptimizationComparisonSeriesUniqueCount(metric, seriesIndex){
      const data = modelOptimizationComparisonMetricData(metric);
      const idx = Math.max(0, Math.round(Number(seriesIndex || 0)));
      if(data.uniqueCounts.has(idx)) return data.uniqueCounts.get(idx);
      const seen = new Set();
      for(let i=0;i<data.values.length;i++){
        const row = arr(data.values[i]);
        const v = Number(row[idx]);
        if(Number.isFinite(v)) seen.add(v);
      }
      const count = seen.size;
      data.uniqueCounts.set(idx, count);
      return count;
    }

    /**
     * modelOptimizationMetricVariableSeriesChoices  List finite, non-constant series for one comparison metric.
     * It implements the NM2 rule that scatter-comparison selectors should omit criteria with numel(unique(value)) == 1.
     */
    function modelOptimizationMetricVariableSeriesChoices(metric){
      return modelOptimizationMetricFiniteSeriesChoices(metric).map(s => {
        const uniqueCount = modelOptimizationComparisonSeriesUniqueCount(metric, s.index);
        return Object.assign({}, s, {uniqueCount});
      }).filter(s => Number(s.uniqueCount) > 1);
    }

    /**
     * modelOptimizationComparisonMetricPool  Return non-constant metrics for metric-vs-metric optimization scatter plots.
     * It reuses the Stage 1 metric registry and requires at least one finite, variable series on the same parameter-combination grid.
     */
    function modelOptimizationComparisonMetricPool(){
      return modelOptimizationAvailablePanelMetrics().filter(m => m.plotKind !== 'sequence_curve' && modelOptimizationMetricVariableSeriesChoices(m).length > 0);
    }

    /**
     * modelOptimizationComparisonMetricByKey  Resolve a comparison metric from its stable browser key.
     * metrics: finite Stage 1 optimization metrics currently available in the browser payload.
     */
    function modelOptimizationComparisonMetricByKey(metrics, key){
      const wanted = String(key || '');
      if(!wanted) return null;
      return arr(metrics).find((m,i) => modelOptimizationMetricKey(m,i) === wanted || String(m && m.id || '') === wanted) || null;
    }

    /**
     * modelOptimizationComparisonPreferredMetric  Choose a scientifically useful default metric for one comparison axis.
     * role: "x" prefers complexity/error/diversity style criteria; "y" prefers performance or the selected optimization metric.
     */
    function modelOptimizationComparisonPreferredMetric(metrics, role, avoidMetric){
      const list = arr(metrics);
      if(!list.length) return null;
      const avoidId = avoidMetric ? String(avoidMetric.id || '') : '';
      const selected = selectedModelOptimizationMetric();
      if(role === 'y' && selected){
        const chosen = list.find(m => m === selected || (m && selected && String(m.id || '') && String(m.id || '') === String(selected.id || '')));
        if(chosen) return chosen;
      }
      const terms = role === 'x'
        ? ['complexity','generalization_error','error','diversity','selection_frequency','frequency']
        : ['performance','cv_performance','test','accuracy','bac'];
      for(let i=0;i<terms.length;i++){
        const t = terms[i];
        const hit = list.find(m => {
          const hay = `${String(m && m.id || '')} ${String(m && m.family || '')} ${String(m && m.label || '')}`.toLowerCase();
          const okAvoid = !avoidId || String(m && m.id || '') !== avoidId || list.length === 1;
          return okAvoid && hay.indexOf(t) >= 0;
        });
        if(hit) return hit;
      }
      return list.find(m => !avoidId || String(m && m.id || '') !== avoidId) || list[0];
    }

    /**
     * modelOptimizationComparisonResolveState  Normalize browser-local scatter metric selections against the current registry.
     * Series are not exposed as controls: multi-series metrics such as CV1/CV2 are plotted concurrently with stable viewspace colors.
     */
    function modelOptimizationComparisonResolveState(){
      const metrics = modelOptimizationComparisonMetricPool();
      if(metrics.length < 2) return {ok:false, metrics, message:'At least two finite, non-constant optimization metrics are required for metric-vs-metric comparison.'};
      let xMetric = modelOptimizationComparisonMetricByKey(metrics, MODEL_OPT_COMPARISON_STATE.xMetricId);
      let yMetric = modelOptimizationComparisonMetricByKey(metrics, MODEL_OPT_COMPARISON_STATE.yMetricId);
      if(!yMetric) yMetric = modelOptimizationComparisonPreferredMetric(metrics, 'y', null);
      if(!xMetric) xMetric = modelOptimizationComparisonPreferredMetric(metrics, 'x', yMetric);
      if(xMetric && yMetric && xMetric === yMetric){
        const alt = metrics.find(m => m !== yMetric) || null;
        if(alt) xMetric = alt;
      }
      if(!xMetric || !yMetric) return {ok:false, metrics, message:'No compatible non-constant optimization metric pair is available.'};
      const xKey = modelOptimizationMetricKey(xMetric, metrics.indexOf(xMetric));
      const yKey = modelOptimizationMetricKey(yMetric, metrics.indexOf(yMetric));
      MODEL_OPT_COMPARISON_STATE.xMetricId = xKey;
      MODEL_OPT_COMPARISON_STATE.yMetricId = yKey;
      const xSeries = modelOptimizationMetricVariableSeriesChoices(xMetric);
      const ySeries = modelOptimizationMetricVariableSeriesChoices(yMetric);
      return {ok:true, metrics, xMetric, yMetric, xSeries, ySeries, xKey, yKey};
    }

    /**
     * modelOptimizationComparisonMetricSelectHtml  Build one metric selector for the Stage 5b comparison panel.
     * name: control suffix used for DOM IDs; selectedKey: current stable metric key.
     */
    function modelOptimizationComparisonMetricSelectHtml(metrics, name, selectedKey){
      const opts = arr(metrics).map((m,i) => {
        const key = modelOptimizationMetricKey(m,i);
        return `<option value="${esc(key)}"${key === String(selectedKey || '') ? ' selected' : ''}>${esc(m.label || `Metric ${i+1}`)}</option>`;
      }).join('');
      return `<select id="modelOptComparison${name}MetricSelect">${opts}</select>`;
    }

    /**
     * modelOptimizationComparisonControlHtml  Render controls for the metric-vs-metric scatter comparison.
     * Only metric selectors are shown; available non-constant series are rendered together to preserve CV1/CV2 identity without extra drop-downs.
     */
    function modelOptimizationComparisonControlHtml(ctx){
      const mode = String(MODEL_OPT_COMPARISON_STATE.paretoMode || 'exact');
      const paretoOptions = [
        ['exact','Pareto frontier'],
        ['sem','Pareto, 1 SEM tolerance'],
        ['off','No frontier overlay']
      ].map(x => `<option value="${x[0]}"${mode === x[0] ? ' selected' : ''}>${esc(x[1])}</option>`).join('');
      return `<div class="rvModelOptComparisonControls"><label>X metric ${modelOptimizationComparisonMetricSelectHtml(ctx.metrics,'X',ctx.xKey)}</label><label>Y metric ${modelOptimizationComparisonMetricSelectHtml(ctx.metrics,'Y',ctx.yKey)}</label><label>Frontier <select id="modelOptComparisonParetoSelect">${paretoOptions}</select></label></div>`;
    }

    /**
     * modelOptimizationComparisonSeriesPairs  Pair non-constant X/Y series for concurrent scatter display.
     * If one metric has one series and the other has several, the single series is reused; if both have equal series counts, ordinal pairs are used.
     */
    function modelOptimizationComparisonSeriesPairs(ctx){
      const xSeries = arr(ctx && ctx.xSeries);
      const ySeries = arr(ctx && ctx.ySeries);
      if(!xSeries.length || !ySeries.length) return [];
      if(xSeries.length === 1 && ySeries.length >= 1) return ySeries.map((ys,i) => ({xSeries:xSeries[0], ySeries:ys, label:ys.label || `Series ${i+1}`}));
      if(ySeries.length === 1 && xSeries.length >= 1) return xSeries.map((xs,i) => ({xSeries:xs, ySeries:ySeries[0], label:xs.label || `Series ${i+1}`}));
      if(xSeries.length === ySeries.length) return xSeries.map((xs,i) => ({xSeries:xs, ySeries:ySeries[i], label:ysLabelPair(xs, ySeries[i], i)}));
      const out = [];
      xSeries.forEach((xs,xi) => ySeries.forEach((ys,yi) => out.push({xSeries:xs, ySeries:ys, label:`${xs.label || `X${xi+1}`} vs ${ys.label || `Y${yi+1}`}`})));
      return out;
    }

    /**
     * ysLabelPair  Compose a compact paired-series label for equal-cardinality multi-series comparison metrics.
     * It avoids duplicating identical CV1/CV2 labels while keeping the legend traceable.
     */
    function ysLabelPair(xs, ys, idx){
      const xl = String(xs && xs.label || '');
      const yl = String(ys && ys.label || '');
      if(xl && yl && xl === yl) return xl;
      if(yl) return yl;
      if(xl) return xl;
      return `Series ${idx+1}`;
    }

    /**
     * modelOptimizationComparisonTooltipText  Compose hover text for one metric-vs-metric scatter point.
     * It includes parameter-combination metadata and uncertainty values where available so the point remains traceable to the legacy optimization grid.
     */
    function modelOptimizationComparisonTooltipText(ctx, point){
      const row = point && point.row || null;
      const lines = [];
      lines.push('Optimization comparison point');
      lines.push(`Model index: ${point.index}`);
      lines.push(`Series: ${point.pairLabel}`);
      lines.push(`X: ${ctx.xMetric.label || 'Metric'} / ${point.xSeriesLabel}: ${fmtMetric(point.x,4)}`);
      if(Number.isFinite(point.xSem)) lines.push(`X SEM: ${fmtMetric(point.xSem,4)}`);
      lines.push(`Y: ${ctx.yMetric.label || 'Metric'} / ${point.ySeriesLabel}: ${fmtMetric(point.y,4)}`);
      if(Number.isFinite(point.ySem)) lines.push(`Y SEM: ${fmtMetric(point.ySem,4)}`);
      const source = currentPayload() && (currentPayload().subtitle || currentPayload().modelSourceLabel) || '';
      if(source) lines.push(`Source: ${source}`);
      const pctx = currentPayload() && currentPayload().context || {};
      if(pctx.classifierLabel) lines.push(`Learner: ${pctx.classifierLabel}`);
      if(pctx.targetLabel) lines.push(`Target: ${pctx.targetLabel}`);
      if(row && row.tooltip) lines.push(String(row.tooltip));
      return lines.join('\n');
    }

    /**
     * modelOptimizationComparisonPoints  Build finite paired metric values for all visible comparison series.
     * A point is included only when both metric-series values are finite; exclusions are counted and reported explicitly.
     */
    function modelOptimizationComparisonPoints(ctx){
      const startedAt = performance.now();
      const cache = modelOptimizationComparisonCache();
      const cacheKey = modelOptimizationComparisonPairCacheKey(ctx);
      if(cache.pair.has(cacheKey)){
        const cached = cache.pair.get(cacheKey);
        profileLog('model optimization comparison point assembly', startedAt, `cache=1 rows=${cached.rowTotal} pairs=${cached.pairCount} points=${cached.points.length}`);
        return cached;
      }
      const decodeStartedAt = performance.now();
      const xData = modelOptimizationComparisonMetricData(ctx.xMetric);
      const yData = modelOptimizationComparisonMetricData(ctx.yMetric);
      const xValues = xData.values;
      const yValues = yData.values;
      const xSem = xData.sem;
      const ySem = yData.sem;
      profileLog('model optimization comparison matrix decode', decodeStartedAt, `xRows=${xValues.length} yRows=${yValues.length}`);

      const pointStartedAt = performance.now();
      const gridRows = arr(currentPayload() && currentPayload().grid && currentPayload().grid.parameterRows);
      const nGrid = Math.max(Number(currentPayload() && currentPayload().grid && currentPayload().grid.nCombinations) || 0, gridRows.length);
      const nRows = Math.max(nGrid, xValues.length, yValues.length);
      const pairs = modelOptimizationComparisonSeriesPairs(ctx);
      const groups = [];
      let excluded = 0;
      pairs.forEach((pair, pairIndex) => {
        const xIdx = Math.max(0, Math.round(Number(pair && pair.xSeries && pair.xSeries.index || 0)));
        const yIdx = Math.max(0, Math.round(Number(pair && pair.ySeries && pair.ySeries.index || 0)));
        const group = {pairIndex, label:pair.label || `Series ${pairIndex+1}`, xSeriesIndex:xIdx, ySeriesIndex:yIdx, points:[], association:null};
        for(let i=0;i<nRows;i++){
          const xRow = xValues[i] || [];
          const yRow = yValues[i] || [];
          const x = Number(xRow[xIdx]);
          const y = Number(yRow[yIdx]);
          if(!Number.isFinite(x) || !Number.isFinite(y)){ excluded++; continue; }
          const xSemRow = xSem[i] || [];
          const ySemRow = ySem[i] || [];
          const xs = Math.abs(Number(xSemRow[xIdx]));
          const ys = Math.abs(Number(ySemRow[yIdx]));
          const row = gridRows[i] || null;
          group.points.push({index:i+1, x, y, row, pairIndex, pairLabel:group.label, xSem:Number.isFinite(xs)?xs:NaN, ySem:Number.isFinite(ys)?ys:NaN, xSeriesLabel:pair.xSeries && pair.xSeries.label || `Series ${xIdx+1}`, ySeriesLabel:pair.ySeries && pair.ySeries.label || `Series ${yIdx+1}`});
        }
        if(group.points.length) groups.push(group);
      });
      const points = groups.reduce((acc,g) => acc.concat(g.points), []);
      profileLog('model optimization comparison point assembly', pointStartedAt, `cache=0 rows=${nRows} pairs=${pairs.length} points=${points.length} excluded=${excluded}`);

      const associationStartedAt = performance.now();
      groups.forEach(group => { group.association = modelOptimizationLinearAssociation(group.points); });
      profileLog('model optimization comparison association', associationStartedAt, `series=${groups.length} points=${points.length}`);

      const out = {cacheKey, points, groups, excluded, total:nRows * Math.max(1, pairs.length), rowTotal:nRows, pairCount:pairs.length, xLength:xValues.length, yLength:yValues.length};
      cache.pair.set(cacheKey, out);
      return out;
    }

    /**
     * modelOptimizationExpandedRange  Expand an axis range for a finite vector of scatter values.
     * It avoids zero-width axes while preserving the original optimization criterion values in tooltips and table payloads.
     */
    function modelOptimizationExpandedRange(values){
      const finite = arr(values).map(Number).filter(Number.isFinite);
      if(!finite.length) return [0,1];
      let lo = Math.min(...finite), hi = Math.max(...finite);
      if(Math.abs(hi - lo) < 1e-12){
        const pad = Math.max(1e-6, Math.abs(lo) * 0.08 || 0.08);
        lo -= pad; hi += pad;
      }else{
        const pad = (hi - lo) * 0.08;
        lo -= pad; hi += pad;
      }
      return [lo, hi];
    }

    /**
     * modelOptimizationTickPrecision  Choose decimal precision that prevents duplicate numeric tick labels.
     * ticks: finite numeric axis ticks returned by the shared D3 plotting helper; returns a bounded fixed-decimal precision.
     */
    function modelOptimizationTickPrecision(ticks){
      const vals = Array.from(new Set(arr(ticks).map(Number).filter(Number.isFinite))).sort((a,b) => a-b);
      if(vals.length <= 1) return 0;
      let minGap = Infinity;
      for(let i=1;i<vals.length;i++){
        const gap = Math.abs(vals[i] - vals[i-1]);
        if(gap > 0 && gap < minGap) minGap = gap;
      }
      if(!Number.isFinite(minGap) || minGap <= 0) return 0;
      let decimals = Math.max(0, Math.ceil(-Math.log10(minGap)) + 1);
      decimals = Math.min(7, Math.max(0, decimals));
      while(decimals < 7){
        const labels = vals.map(v => v.toFixed(decimals));
        if(new Set(labels).size === labels.length) break;
        decimals += 1;
      }
      return decimals;
    }

    /**
     * modelOptimizationTickFormatter  Format scatter-axis ticks with enough precision to avoid repeated labels.
     * ticks: finite numeric tick list; returns a formatter used by the shared cartesian axis renderer without mutating plot state.
     */
    function modelOptimizationTickFormatter(ticks){
      const precision = modelOptimizationTickPrecision(ticks);
      return function(v){
        const x = Number(v);
        if(!Number.isFinite(x)) return '';
        if(Math.abs(x) >= 10000 || (Math.abs(x) > 0 && Math.abs(x) < 0.001)) return x.toExponential(Math.min(3, Math.max(1, precision)));
        return precision > 0 ? x.toFixed(precision) : String(Math.round(x));
      };
    }

    /**
     * modelOptimizationDynamicRangeNotice  Warn when a selected scatter axis has very limited numeric spread.
     * values: finite metric values used for one scatter axis; label: user-facing metric label returned in the notice.
     */
    function modelOptimizationDynamicRangeNotice(values, label){
      const vals = arr(values).map(Number).filter(Number.isFinite);
      if(vals.length < 3) return '';
      const lo = Math.min(...vals), hi = Math.max(...vals);
      const range = hi - lo;
      const centre = Math.max(1, Math.abs((hi + lo) / 2));
      if(range > 0 && range / centre < 0.05){
        return `${label || 'Selected metric'} has limited dynamic range; association estimates may be visually compressed.`;
      }
      return '';
    }

    /**
     * modelOptimizationLogGamma  Approximate log-gamma for Student-t significance calculations.
     * It is browser-local and used only for tooltip/panel annotation; it does not alter optimization results.
     */
    function modelOptimizationLogGamma(z){
      const p = [676.5203681218851,-1259.1392167224028,771.32342877765313,-176.61502916214059,12.507343278686905,-0.13857109526572012,9.9843695780195716e-6,1.5056327351493116e-7];
      if(z < 0.5) return Math.log(Math.PI) - Math.log(Math.sin(Math.PI * z)) - modelOptimizationLogGamma(1 - z);
      z -= 1;
      let x = 0.99999999999980993;
      for(let i=0;i<p.length;i++) x += p[i] / (z + i + 1);
      const t = z + p.length - 0.5;
      return 0.5 * Math.log(2 * Math.PI) + (z + 0.5) * Math.log(t) - t + Math.log(x);
    }

    /**
     * modelOptimizationBetaContinuedFraction  Evaluate the incomplete-beta continued fraction.
     * The implementation follows the standard Numerical Recipes recurrence and is restricted to association p-value annotation.
     */
    function modelOptimizationBetaContinuedFraction(a,b,x){
      const maxIter = 100;
      const eps = 3e-7;
      const fpmin = 1e-30;
      let qab = a + b;
      let qap = a + 1;
      let qam = a - 1;
      let c = 1;
      let d = 1 - qab * x / qap;
      if(Math.abs(d) < fpmin) d = fpmin;
      d = 1 / d;
      let h = d;
      for(let m=1;m<=maxIter;m++){
        const m2 = 2 * m;
        let aa = m * (b - m) * x / ((qam + m2) * (a + m2));
        d = 1 + aa * d;
        if(Math.abs(d) < fpmin) d = fpmin;
        c = 1 + aa / c;
        if(Math.abs(c) < fpmin) c = fpmin;
        d = 1 / d;
        h *= d * c;
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
        d = 1 + aa * d;
        if(Math.abs(d) < fpmin) d = fpmin;
        c = 1 + aa / c;
        if(Math.abs(c) < fpmin) c = fpmin;
        d = 1 / d;
        const del = d * c;
        h *= del;
        if(Math.abs(del - 1) < eps) break;
      }
      return h;
    }

    /**
     * modelOptimizationRegularizedBeta  Compute a regularized incomplete beta value for Student-t p-values.
     * It is used to annotate scatter associations and reports NaN when the numeric inputs are outside the supported domain.
     */
    function modelOptimizationRegularizedBeta(x,a,b){
      if(!(x >= 0 && x <= 1) || !(a > 0) || !(b > 0)) return NaN;
      if(x === 0 || x === 1) return x;
      const bt = Math.exp(modelOptimizationLogGamma(a + b) - modelOptimizationLogGamma(a) - modelOptimizationLogGamma(b) + a * Math.log(x) + b * Math.log(1 - x));
      if(x < (a + 1) / (a + b + 2)) return bt * modelOptimizationBetaContinuedFraction(a,b,x) / a;
      return 1 - bt * modelOptimizationBetaContinuedFraction(b,a,1 - x) / b;
    }

    /**
     * modelOptimizationStudentTCdf  Approximate Student-t CDF for scatter association significance.
     * t: signed t statistic; df: degrees of freedom. The returned value is used for display only.
     */
    function modelOptimizationStudentTCdf(t, df){
      const tt = Number(t), d = Number(df);
      if(!Number.isFinite(tt) || !(d > 0)) return NaN;
      const x = d / (d + tt * tt);
      const ib = modelOptimizationRegularizedBeta(x, d / 2, 0.5);
      if(!Number.isFinite(ib)) return NaN;
      return tt >= 0 ? 1 - 0.5 * ib : 0.5 * ib;
    }

    /**
     * modelOptimizationLinearAssociation  Estimate slope, Pearson r, and two-sided p for one visible scatter series.
     * No model is changed; the result is a visual diagnostic for the currently selected metric pair only.
     */
    function modelOptimizationLinearAssociation(points){
      const pts = arr(points).filter(p => Number.isFinite(p && p.x) && Number.isFinite(p && p.y));
      const n = pts.length;
      if(n < 3) return {ok:false, n, message:'n < 3'};
      const mx = pts.reduce((a,p) => a + p.x, 0) / n;
      const my = pts.reduce((a,p) => a + p.y, 0) / n;
      let sxx = 0, syy = 0, sxy = 0;
      pts.forEach(p => { const dx = p.x - mx; const dy = p.y - my; sxx += dx * dx; syy += dy * dy; sxy += dx * dy; });
      if(sxx <= 0 || syy <= 0) return {ok:false, n, message:'constant axis'};
      const slope = sxy / sxx;
      const intercept = my - slope * mx;
      const r = Math.max(-1, Math.min(1, sxy / Math.sqrt(sxx * syy)));
      const df = n - 2;
      let pValue = NaN;
      if(Math.abs(r) >= 1) pValue = 0;
      else{
        const t = Math.abs(r) * Math.sqrt(df / Math.max(1e-300, 1 - r * r));
        const cdf = modelOptimizationStudentTCdf(t, df);
        pValue = Number.isFinite(cdf) ? Math.max(0, Math.min(1, 2 * (1 - cdf))) : NaN;
      }
      return {ok:true, n, slope, intercept, r, pValue, xMin:Math.min(...pts.map(p => p.x)), xMax:Math.max(...pts.map(p => p.x))};
    }

    /**
     * modelOptimizationPValueLabel  Format an association p-value for compact panel annotation.
     * It avoids overstating numeric precision for very small probabilities.
     */
    function modelOptimizationPValueLabel(p){
      const v = Number(p);
      if(!Number.isFinite(v)) return 'p = n/a';
      if(v < 1e-4) return 'p < 1e-4';
      if(v < 0.001) return `p = ${v.toExponential(2)}`;
      return `p = ${v.toFixed(3)}`;
    }

    /**
     * modelOptimizationAssociationSummaryHtml  Render slope and correlation diagnostics for all visible scatter series.
     * The statistics are calculated from the displayed finite points after missing values and constant series have been excluded.
     */
    function modelOptimizationAssociationSummaryHtml(groups){
      const rows = arr(groups).map((g,i) => {
        const stat = g && g.association ? g.association : modelOptimizationLinearAssociation(g.points);
        if(!stat.ok) return `<span class="rvModelOptAssocItem rvModelOptSeries${i%6}"><i></i>${esc(g.label || `Series ${i+1}`)}: association unavailable (${esc(stat.message || 'insufficient data')})</span>`;
        return `<span class="rvModelOptAssocItem rvModelOptSeries${i%6}"><i></i>${esc(g.label || `Series ${i+1}`)}: slope ${esc(fmtMetric(stat.slope,4))}, r ${esc(fmtMetric(stat.r,4))}, ${esc(modelOptimizationPValueLabel(stat.pValue))}, n ${esc(stat.n)}</span>`;
      }).join('');
      return rows ? `<div class="rvModelOptAssocSummary">${rows}</div>` : '';
    }

    /**
     * modelOptimizationObjectiveDirection  Resolve the optimization direction for one Stage 1 metric descriptor.
     * The function uses explicit metric metadata first and only falls back to family/label heuristics for older payloads that lack higherIsBetter/lowerIsBetter flags.
     */
    function modelOptimizationObjectiveDirection(metric){
      if(metric && metric.lowerIsBetter) return 'min';
      if(metric && metric.higherIsBetter) return 'max';
      const hay = `${String(metric && metric.id || '')} ${String(metric && metric.family || '')} ${String(metric && metric.label || '')}`.toLowerCase();
      if(hay.indexOf('complexity') >= 0 || hay.indexOf('error') >= 0 || hay.indexOf('loss') >= 0) return 'min';
      return 'max';
    }

    /**
     * modelOptimizationObjectiveLabel  Return a compact objective-direction label for Pareto diagnostics.
     * It keeps the frontend annotation auditable without changing the backend metric registry.
     */
    function modelOptimizationObjectiveLabel(dir){
      return String(dir || 'max') === 'min' ? 'minimized' : 'maximized';
    }

    /**
     * modelOptimizationParetoTolerance  Return the numerical dominance tolerance for one point and axis.
     * mode: 'exact' uses zero tolerance; 'sem' uses the maximum available SEM of the two compared points on that axis.
     */
    function modelOptimizationParetoTolerance(a, b, axisName, mode){
      if(String(mode || 'exact') !== 'sem') return 0;
      const key = String(axisName || 'x') === 'y' ? 'ySem' : 'xSem';
      const vals = [Number(a && a[key]), Number(b && b[key])].filter(Number.isFinite).map(Math.abs);
      return vals.length ? Math.max(...vals) : 0;
    }

    /**
     * modelOptimizationParetoNoWorse  Test whether value a is no worse than value b under one objective direction.
     * The optional tolerance supports uncertainty-aware frontier highlighting without modifying the underlying metric values.
     */
    function modelOptimizationParetoNoWorse(a, b, dir, tol){
      const aa = Number(a), bb = Number(b), t = Math.max(0, Number(tol || 0));
      if(!Number.isFinite(aa) || !Number.isFinite(bb)) return false;
      return String(dir || 'max') === 'min' ? aa <= bb + t : aa >= bb - t;
    }

    /**
     * modelOptimizationParetoStrictBetter  Test whether value a is strictly better than value b under one objective direction.
     * Differences within the active SEM tolerance are treated as ties for the purpose of Pareto dominance.
     */
    function modelOptimizationParetoStrictBetter(a, b, dir, tol){
      const aa = Number(a), bb = Number(b), t = Math.max(0, Number(tol || 0));
      if(!Number.isFinite(aa) || !Number.isFinite(bb)) return false;
      return String(dir || 'max') === 'min' ? aa < bb - t : aa > bb + t;
    }

    /**
     * modelOptimizationParetoDominates  Decide whether point a dominates point b in the active scatter comparison.
     * A point dominates when it is no worse on both axes and strictly better on at least one axis, respecting metric direction and optional SEM tolerance.
     */
    function modelOptimizationParetoDominates(a, b, xDir, yDir, mode){
      const tx = modelOptimizationParetoTolerance(a, b, 'x', mode);
      const ty = modelOptimizationParetoTolerance(a, b, 'y', mode);
      const noWorseX = modelOptimizationParetoNoWorse(a.x, b.x, xDir, tx);
      const noWorseY = modelOptimizationParetoNoWorse(a.y, b.y, yDir, ty);
      const betterX = modelOptimizationParetoStrictBetter(a.x, b.x, xDir, tx);
      const betterY = modelOptimizationParetoStrictBetter(a.y, b.y, yDir, ty);
      return !!(noWorseX && noWorseY && (betterX || betterY));
    }

    /**
     * modelOptimizationParetoExactDominatedIndexes  Compute exact two-objective dominance in O(n log n).
     * Objective values are transformed to maximization coordinates, sorted by X, and swept by the best prior Y value.
     * Equal X/Y duplicates remain jointly non-dominated because exact duplicates are not strictly better on either axis.
     */
    function modelOptimizationParetoExactDominatedIndexes(points, xDir, yDir){
      const transformed = arr(points).map((p, originalIndex) => ({
        originalIndex,
        x:String(xDir || 'max') === 'min' ? -Number(p && p.x) : Number(p && p.x),
        y:String(yDir || 'max') === 'min' ? -Number(p && p.y) : Number(p && p.y)
      })).filter(p => Number.isFinite(p.x) && Number.isFinite(p.y));
      transformed.sort((a,b) => (b.x - a.x) || (b.y - a.y) || (a.originalIndex - b.originalIndex));
      const dominated = new Set();
      let priorMaxY = -Infinity;
      let start = 0;
      while(start < transformed.length){
        let end = start + 1;
        while(end < transformed.length && transformed[end].x === transformed[start].x) end++;
        let groupMaxY = -Infinity;
        for(let i=start;i<end;i++) if(transformed[i].y > groupMaxY) groupMaxY = transformed[i].y;
        for(let i=start;i<end;i++){
          const row = transformed[i];
          if(priorMaxY >= row.y || groupMaxY > row.y) dominated.add(row.originalIndex);
        }
        if(groupMaxY > priorMaxY) priorMaxY = groupMaxY;
        start = end;
      }
      return dominated;
    }

    /**
     * modelOptimizationParetoDiagnostics  Compute non-dominated frontier membership for all visible scatter series.
     * The calculation is browser-local, read-only, and uses the already displayed finite point pairs from the comparison panel.
     */
    function modelOptimizationParetoDiagnostics(ctx, pair){
      const cacheStartedAt = performance.now();
      const mode = String(MODEL_OPT_COMPARISON_STATE.paretoMode || 'exact');
      const xDir = modelOptimizationObjectiveDirection(ctx && ctx.xMetric);
      const yDir = modelOptimizationObjectiveDirection(ctx && ctx.yMetric);
      const byPoint = new Map();
      const series = [];
      if(mode === 'off') return {enabled:false, mode, xDir, yDir, byPoint, series};
      const cache = modelOptimizationComparisonCache();
      const cacheKey = `${String(pair && pair.cacheKey || modelOptimizationComparisonPairCacheKey(ctx))}::${mode}::${xDir}::${yDir}`;
      if(cache.pareto.has(cacheKey)){
        const cached = cache.pareto.get(cacheKey);
        profileLog('model optimization comparison Pareto', cacheStartedAt, `cache=1 mode=${mode} points=${arr(pair && pair.points).length}`);
        return cached;
      }
      const startedAt = performance.now();
      let pairwiseComparisons = 0;
      arr(pair && pair.groups).forEach((g, gi) => {
        const pts = arr(g && g.points);
        let dominated;
        if(mode === 'exact'){
          dominated = modelOptimizationParetoExactDominatedIndexes(pts, xDir, yDir);
        }else{
          dominated = new Set();
          for(let i=0;i<pts.length;i++){
            for(let j=0;j<pts.length;j++){
              if(i === j) continue;
              pairwiseComparisons++;
              if(modelOptimizationParetoDominates(pts[j], pts[i], xDir, yDir, mode)){ dominated.add(i); break; }
            }
          }
        }
        const frontier = [];
        pts.forEach((p, i) => {
          const isDominated = dominated.has(i);
          const state = {seriesIndex:gi, isPareto:!isDominated, isDominated, mode};
          byPoint.set(`${gi}:${p.index}`, state);
          if(!isDominated) frontier.push(p);
        });
        series.push({label:g && g.label || `Series ${gi+1}`, total:pts.length, frontier, dominated:dominated.size, seriesIndex:gi});
      });
      const out = {enabled:true, mode, xDir, yDir, byPoint, series};
      cache.pareto.set(cacheKey, out);
      profileLog('model optimization comparison Pareto', startedAt, `cache=0 mode=${mode} algorithm=${mode === 'exact' ? 'sort-sweep' : 'pairwise'} points=${arr(pair && pair.points).length} comparisons=${pairwiseComparisons}`);
      return out;
    }

    /**
     * modelOptimizationParetoStatusText  Compose one-line tooltip text for a Pareto-tagged scatter point.
     * It reports only the visual diagnostic status and avoids recommending or mutating a selected NeuroMiner model.
     */
    function modelOptimizationParetoStatusText(state){
      if(!state) return '';
      if(state.isPareto) return 'Pareto status: non-dominated frontier point';
      if(state.isDominated) return 'Pareto status: dominated point';
      return '';
    }

    /**
     * modelOptimizationParetoSummaryHtml  Render read-only Pareto/frontier diagnostics for the active scatter comparison.
     * The summary reports objective directions, tolerance mode, and frontier model indices for auditability; it never changes model selection.
     */
    function modelOptimizationParetoSummaryHtml(diag){
      if(!diag || !diag.enabled) return '';
      const tolerance = diag.mode === 'sem' ? '1 SEM tolerance' : 'exact dominance';
      const head = `<div class="rvModelOptParetoHead">Pareto frontier: X ${esc(modelOptimizationObjectiveLabel(diag.xDir))}, Y ${esc(modelOptimizationObjectiveLabel(diag.yDir))}; ${esc(tolerance)}.</div>`;
      const rows = arr(diag.series).map((s,i) => {
        const idx = arr(s.frontier).map(p => p.index).slice(0, 14).join(', ');
        const more = arr(s.frontier).length > 14 ? ', …' : '';
        return `<span class="rvModelOptParetoItem rvModelOptSeries${i%6}"><i></i>${esc(s.label || `Series ${i+1}`)}: frontier ${esc(arr(s.frontier).length)} / ${esc(s.total)}, dominated ${esc(s.dominated)}; indices ${esc(idx || 'none')}${more}</span>`;
      }).join('');
      return `<div class="rvModelOptParetoSummary">${head}<div class="rvModelOptParetoRows">${rows}</div></div>`;
    }

    /**
     * renderModelOptimizationComparisonSvg  Render the metric-vs-metric scatter plot for Stage 5b.
     * Each point is one legacy parameter-combination index; multi-series metrics are overlaid as separate colored series with fitted association lines.
     */
    function renderModelOptimizationComparisonSvg(ctx, pair){
      const startedAt = performance.now();
      const groups = arr(pair && pair.groups);
      const pts = arr(pair && pair.points);
      if(!pts.length) return '<div class="rvPanelNotice">No finite paired optimization metric values are available for the selected comparison.</div>';
      const w = 980, h = 560, m = {left:102,right:34,top:34,bottom:70};
      const xLim = modelOptimizationExpandedRange(pts.map(p => p.x));
      const yLim = modelOptimizationExpandedRange(pts.map(p => p.y));
      const xTicks = niceTicks(xLim[0], xLim[1], 7);
      const yTicks = niceTicks(yLim[0], yLim[1], 7);
      const ax = plotTools().cartesianAxes({w,h,m,xLim,yLim,xTicks,yTicks,xFmt:modelOptimizationTickFormatter(xTicks),yFmt:modelOptimizationTickFormatter(yTicks),xLabel:ctx.xMetric.yLabel || ctx.xMetric.label || 'X metric',yLabel:ctx.yMetric.yLabel || ctx.yMetric.label || 'Y metric',xLabelY:h-18,autoMargin:true,lockLabelPositions:true});
      const pareto = modelOptimizationParetoDiagnostics(ctx, pair);
      const seriesSvg = [];
      const legendRows = [];
      groups.forEach((g,gi) => {
        const stat = g && g.association ? g.association : modelOptimizationLinearAssociation(g.points);
        if(stat.ok){
          const x1 = Math.max(xLim[0], Math.min(xLim[1], stat.xMin));
          const x2 = Math.max(xLim[0], Math.min(xLim[1], stat.xMax));
          const y1 = stat.intercept + stat.slope * x1;
          const y2 = stat.intercept + stat.slope * x2;
          seriesSvg.push(`<line class="rvModelOptScatterFit rvModelOptSeries${gi%6}" x1="${ax.xPix(x1).toFixed(1)}" y1="${ax.yPix(y1).toFixed(1)}" x2="${ax.xPix(x2).toFixed(1)}" y2="${ax.yPix(y2).toFixed(1)}"></line>`);
        }
        arr(g.points).forEach(p => {
          const pState = pareto && pareto.byPoint ? pareto.byPoint.get(`${gi}:${p.index}`) : null;
          const pTip = [modelOptimizationComparisonTooltipText(ctx, p), modelOptimizationParetoStatusText(pState)].filter(Boolean).join('\n');
          const paretoCls = pState && pState.isPareto ? ' isParetoPoint' : (pState && pState.isDominated ? ' isDominatedPoint' : '');
          const cls = `rvModelOptScatterPoint rvModelOptSeries${gi%6}${paretoCls}${Number(MODEL_OPT_SELECTED_INDEX) === Number(p.index) ? ' isSelectedIndex' : ''}`;
          seriesSvg.push(`<circle class="${cls}" cx="${ax.xPix(p.x).toFixed(1)}" cy="${ax.yPix(p.y).toFixed(1)}" r="5.4" tabindex="0" data-rv-index="${esc(p.index)}" data-rv-tooltip="${esc(pTip)}"></circle>`);
        });
        legendRows.push(`<span class="rvModelOptLegendItem rvModelOptSeries${gi%6}"><i></i>${esc(g.label || `Series ${gi+1}`)}</span>`);
      });
      if(pareto && pareto.enabled){
        legendRows.push('<span class="rvModelOptLegendItem rvModelOptParetoLegend"><i></i>Pareto frontier</span>');
        legendRows.push('<span class="rvModelOptLegendItem rvModelOptDominatedLegend"><i></i>Dominated points faded</span>');
      }
      const lineX = ax.xPix(0);
      const lineY = ax.yPix(0);
      const xZero = xLim[0] < 0 && xLim[1] > 0 ? `<line class="rvModelOptScatterZero" x1="${lineX.toFixed(1)}" y1="${m.top}" x2="${lineX.toFixed(1)}" y2="${h-m.bottom}"/>` : '';
      const yZero = yLim[0] < 0 && yLim[1] > 0 ? `<line class="rvModelOptScatterZero" x1="${m.left}" y1="${lineY.toFixed(1)}" x2="${w-m.right}" y2="${lineY.toFixed(1)}"/>` : '';
      const rangeNotices = [
        modelOptimizationDynamicRangeNotice(pts.map(p => p.x), ctx.xMetric.label || 'X metric'),
        modelOptimizationDynamicRangeNotice(pts.map(p => p.y), ctx.yMetric.label || 'Y metric')
      ].filter(Boolean);
      const rangeNoticeHtml = rangeNotices.length ? `<div class="rvModelOptScatterRangeNotice">${rangeNotices.map(esc).join(' ')}</div>` : '';
      const html = `<div class="rvModelOptScatterPlot"><svg class="rvModelOptScatterSvg" viewBox="0 0 ${w} ${h}" preserveAspectRatio="xMidYMid meet" role="img" aria-label="Optimization metric comparison scatter plot"><rect class="rvPlotBg" x="${m.left}" y="${m.top}" width="${w-m.left-m.right}" height="${h-m.top-m.bottom}"/>${ax.svg}${xZero}${yZero}<g>${seriesSvg.join('')}</g></svg><div class="rvModelOptTooltip" role="status" aria-live="polite"></div></div><div class="rvModelOptLegend">${legendRows.join('')}</div>${rangeNoticeHtml}${modelOptimizationAssociationSummaryHtml(groups)}${modelOptimizationParetoSummaryHtml(pareto)}`;
      profileLog('model optimization comparison SVG construction', startedAt, `series=${groups.length} points=${pts.length}`);
      return html;
    }

    /**
     * bindModelOptimizationComparisonControls  Attach selector handlers for the Stage 5b scatter-comparison panel.
     * Side effects: updates browser-local comparison state and re-renders the comparison panel only; no MATLAB round-trip is issued.
     */
    function bindModelOptimizationComparisonControls(){
      const xMetric = el('modelOptComparisonXMetricSelect');
      const yMetric = el('modelOptComparisonYMetricSelect');
      const paretoMode = el('modelOptComparisonParetoSelect');
      if(xMetric) xMetric.addEventListener('change', () => { MODEL_OPT_COMPARISON_STATE.xMetricId = String(xMetric.value || ''); renderModelOptimizationComparison(); });
      if(yMetric) yMetric.addEventListener('change', () => { MODEL_OPT_COMPARISON_STATE.yMetricId = String(yMetric.value || ''); renderModelOptimizationComparison(); });
      if(paretoMode) paretoMode.addEventListener('change', () => { MODEL_OPT_COMPARISON_STATE.paretoMode = String(paretoMode.value || 'exact'); renderModelOptimizationComparison(); });
    }

    /**
     * bindModelOptimizationComparison  Activate tooltip and linked-index behavior for Stage 5b scatter points.
     * It uses the same transient highlight state as the optimization curves and dashboard, preserving one selected parameter-combination index across views.
     */
    function bindModelOptimizationComparison(){
      const node = el('modelOptimizationComparison');
      if(!node) return;
      Array.from(node.querySelectorAll('.rvModelOptScatterPlot')).forEach(panel => bindModelOptimizationPointSet(panel, '.rvModelOptScatterPoint'));
    }

    /**
     * renderModelOptimizationComparison  Render the Stage 5b metric-vs-metric optimization comparison panel.
     * The scatter plot is entirely browser-side: points are paired finite values from selected non-constant metrics on the existing parameter-combination grid.
     */
    function renderModelOptimizationComparison(){
      const startedAt = performance.now();
      const node = el('modelOptimizationComparison');
      if(!node) return;
      if(!currentPayload() || currentPayload().ok === false){
        node.innerHTML = `<div class="rvPanelNotice">${esc(currentPayload() && currentPayload().message || 'Model optimization payload unavailable.')}</div>`;
        return;
      }
      const ctx = modelOptimizationComparisonResolveState();
      if(!ctx.ok){
        node.innerHTML = `<div class="rvPanelNotice">${esc(ctx.message || 'Metric comparison is unavailable for this optimization payload.')}</div>`;
        return;
      }
      const pair = modelOptimizationComparisonPoints(ctx);
      const controls = modelOptimizationComparisonControlHtml(ctx);
      const mismatch = pair.xLength !== pair.yLength ? ` Metric length mismatch: X has ${pair.xLength} rows, Y has ${pair.yLength} rows; paired finite rows were used only where both indices exist.` : '';
      const note = `Showing ${pair.points.length} plotted points across ${pair.pairCount} visible series pair(s); ${pair.excluded} excluded paired entries because one or both selected metric values were missing.${mismatch}`;
      const svgHtml = renderModelOptimizationComparisonSvg(ctx,pair);
      const domStartedAt = performance.now();
      node.innerHTML = `<div class="rvModelOptComparisonHeader"><div><strong>Metric-vs-metric comparison</strong><span>Each point is one legacy parameter-combination index. Multi-series metrics such as CV1/CV2 are overlaid with viewspace colors; constant series are omitted.</span></div><div class="rvModelOptComparisonNotice">${esc(note)}</div></div>${controls}${svgHtml}`;
      profileLog('model optimization comparison DOM', domStartedAt, `points=${pair.points.length} series=${pair.groups.length}`);
      const bindStartedAt = performance.now();
      bindModelOptimizationComparisonControls();
      bindModelOptimizationComparison();
      applyModelOptimizationSelectedIndex();
      profileLog('model optimization comparison bind', bindStartedAt, `points=${pair.points.length}`);
      profileLog('model optimization comparison TOTAL', startedAt, `points=${pair.points.length} series=${pair.groups.length} mode=${String(MODEL_OPT_COMPARISON_STATE.paretoMode || 'exact')}`);
    }
    /**
     * renderModelOptimizationTables  Render the metric registry and parameter-grid tables.
     * These are read-only Stage 2 diagnostics that make the backend registry auditable while the export path remains deferred.
     */
    function renderModelOptimizationTables(){
      const mt = el('modelOptimizationMetricsTable');
      if(mt) mt.innerHTML = tableHtml(currentPayload() && currentPayload().summaryRows, modelOptimizationMetricColumns(), 'No model-optimization metric registry available.');
      const gt = el('modelOptimizationGridTable');
      if(gt) gt.innerHTML = tableHtml(currentPayload() && currentPayload().optimizationRows, modelOptimizationGridColumns(), 'No parameter-combination rows available.');
    }

    /**
     * renderModelOptimizationViewspace  Render the minimal Stage 2 model-optimization workspace.
     * It displays one selected optimization metric, CV-partition matrices, dashboard panels, 2D parameter views, scatter comparison, and read-only Pareto/frontier diagnostics without export-side effects.
     */
    function renderModelOptimizationViewspace(){
      const totalStartedAt = performance.now();
      let startedAt = performance.now();
      renderModelOptimizationPlot();
      profileLog('model optimization primary panel', startedAt);
      startedAt = performance.now();
      renderModelOptimizationPartitions();
      profileLog('model optimization partition panels', startedAt);
      startedAt = performance.now();
      renderModelOptimizationDashboard();
      profileLog('model optimization dashboard panels', startedAt);
      startedAt = performance.now();
      renderModelOptimizationSurface();
      profileLog('model optimization surface panel', startedAt);
      startedAt = performance.now();
      renderModelOptimizationComparison();
      profileLog('model optimization comparison panel', startedAt);
      startedAt = performance.now();
      renderModelOptimizationTables();
      profileLog('model optimization tables', startedAt);
      applyModelOptimizationSelectedIndex();
      profileLog('model optimization viewspace TOTAL', totalStartedAt);
    }

    /** Return Report Builder options owned by the active Model Optimization browser state. */
    function currentReportOptions(componentId){
      const id=String(componentId||''),opts={};
      if(id==='model_optimization.sequence_diagnostics'){if(MODEL_OPT_SELECTED_INDEX>0)opts.CandidateIndex=MODEL_OPT_SELECTED_INDEX;}
      else if(id==='model_optimization.selected_metric'){const metric=selectedModelOptimizationMetric();if(metric&&metric.id)opts.MetricId=metric.id;}
      else if(id==='model_optimization.parameter_surface'){const metricId=String(MODEL_OPT_SURFACE_STATE.metricId||'');if(metricId)opts.MetricId=metricId;opts.Aggregation=String(MODEL_OPT_SURFACE_STATE.aggregation||'mean');opts.XParameterIndex=Math.max(1,Number(MODEL_OPT_SURFACE_STATE.xParam||0)+1);opts.YParameterIndex=Math.max(1,Number(MODEL_OPT_SURFACE_STATE.yParam||0)+1);}
      else if(id==='model_optimization.scatter_comparison'||id==='model_optimization.pareto_summary'){if(MODEL_OPT_COMPARISON_STATE.xMetricId)opts.XMetricId=String(MODEL_OPT_COMPARISON_STATE.xMetricId);if(MODEL_OPT_COMPARISON_STATE.yMetricId)opts.YMetricId=String(MODEL_OPT_COMPARISON_STATE.yMetricId);opts.FrontierMode=String(MODEL_OPT_COMPARISON_STATE.paretoMode||'exact');}
      return opts;
    }

    return Object.freeze({renderViewspace:renderModelOptimizationViewspace,bindPartitionTooltips:bindModelOptimizationPartitionTooltips,currentReportOptions,parameterAxes:modelOptimizationParameterAxes,aggregateCellStats:modelOptimizationSurfaceCellStats});
  }

  root.NMResultsViewerModelOptimization=Object.freeze({create});
})(typeof globalThis!=='undefined'?globalThis:this);
