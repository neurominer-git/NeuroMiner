(function(){
  'use strict';

  /**
   * finite  Provide the finite helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function finite(x){ return Number.isFinite(Number(x)); }
  /**
   * clamp  Provide the clamp helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function clamp(x, lo, hi){ x = Number(x); return Math.max(lo, Math.min(hi, Number.isFinite(x) ? x : lo)); }
  /**
   * esc  Escape text before inserting it into HTML markup.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  const {escapeHtml:esc,abbreviateLabel}=globalThis.NMResultsViewerPrimitives;
  /**
   * trimNumericText  Build the trim numeric text shown to users in the browser UI.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function trimNumericText(s){
    return String(s == null ? '' : s).replace(/(\.\d*?[1-9])0+(e[+\-]?\d+)$/i, '$1$2').replace(/\.0+(e[+\-]?\d+)$/i, '$1').replace(/(\.\d*?[1-9])0+$/,'$1').replace(/\.0+$/,'');
  }
  /**
   * approxTextWidth  Compute the approx text width layout value used by browser rendering.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function approxTextWidth(text, fontSize){
    const txt = String(text == null ? '' : text);
    const fs = Number(fontSize || 12);
    let units = 0;
    for(let i=0;i<txt.length;i++){
      const ch = txt.charAt(i);
      if('ilI.,:;|! '.indexOf(ch) >= 0) units += 0.42;
      else if('MW@#%&'.indexOf(ch) >= 0) units += 1.05;
      else if('0123456789'.indexOf(ch) >= 0) units += 0.68;
      else units += 0.72;
    }
    return Math.ceil(units * fs);
  }
  /**
   * measureTextWidth  Estimate or measure SVG text width for browser-side plot layout.
   * The helper first tries a hidden SVG text measurement so D3/browser plots can use content-aware margins; it falls back to approxTextWidth when a DOM measurement is unavailable.
   */
  function measureTextWidth(text, fontSize, fontFamily){
    const txt = String(text == null ? '' : text);
    const fs = Number(fontSize || 12);
    if(!txt) return 0;
    try{
      if(typeof document !== 'undefined' && document.body && document.createElementNS){
        let svg = document.getElementById('nmResultsPlotD3MeasureSvg');
        if(!svg){
          svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
          svg.setAttribute('id','nmResultsPlotD3MeasureSvg');
          svg.setAttribute('width','1');
          svg.setAttribute('height','1');
          svg.setAttribute('aria-hidden','true');
          svg.style.position = 'absolute';
          svg.style.left = '-10000px';
          svg.style.top = '-10000px';
          svg.style.overflow = 'hidden';
          document.body.appendChild(svg);
        }
        const node = document.createElementNS('http://www.w3.org/2000/svg','text');
        node.setAttribute('font-size', String(fs));
        node.setAttribute('font-family', fontFamily || 'Arial, Helvetica, sans-serif');
        node.textContent = txt;
        svg.appendChild(node);
        const box = node.getBBox ? node.getBBox() : null;
        svg.removeChild(node);
        if(box && Number.isFinite(Number(box.width))) return Math.ceil(Number(box.width));
      }
    }catch(err){
      if(window.console && typeof window.console.warn === 'function'){
        window.console.warn('NMResultsPlotD3.measureTextWidth failed; falling back to deterministic estimate:', err && (err.stack || err.message || String(err)));
      }
    }
    return approxTextWidth(txt, fs);
  }

  /**
   * fitLabel  Fit one categorical display label to a measured pixel width.
   *
   * Purpose: Apply the shared middle-abbreviation policy only when measured SVG text would exceed the caller's available width.
   * Syntax: fitLabel(text,maxWidth,fontSize,fontFamily).
   * Inputs: Display text, positive pixel width, and optional font settings.
   * Outputs: Full or abbreviated display label whose deterministic measured width fits the requested bound as closely as the eight-character minimum permits.
   * Authority and flow: Delegates all width decisions to measureTextWidth and all shortening to abbreviateLabel.
   * Scientific/state contract: Full labels remain authoritative outside this presentation projection.
   * Invariants: A fitting full label is never rotated or shortened by this function; shortening uses one shared policy.
   * Materialization and performance: O(label length squared) in the bounded worst case for short UI labels; no external resources or scientific arrays.
   * Failure semantics: Non-positive/invalid widths return the normalized full label rather than guessing a layout.
   * Side effects: Hidden SVG measurement may be reused by measureTextWidth.
   * Consumers and dependencies: Cross-analysis adaptive categorical-axis planning and other bounded plot labels.
   */
  function fitLabel(text, maxWidth, fontSize, fontFamily){
    const txt = String(text == null ? '' : text).replace(/\s+/g,' ').trim();
    const width = Number(maxWidth), fs = Number(fontSize || 12);
    if(!txt || !Number.isFinite(width) || width <= 0 || measureTextWidth(txt,fs,fontFamily) <= width) return txt;
    for(let n=Math.min(txt.length,80);n>=8;n--){
      const candidate=abbreviateLabel(txt,n);
      if(measureTextWidth(candidate,fs,fontFamily) <= width) return candidate;
    }
    return abbreviateLabel(txt,8);
  }

  /**
   * prettifyLabel  Convert backend/internal metric keys into compact human-facing axis labels.
   * It preserves already readable labels while normalizing snake_case/camelCase identifiers used by NM payloads.
   */
  function prettifyLabel(text){
    let txt = String(text == null ? '' : text).trim();
    if(!txt) return '';
    const explicit = {
      'cv_performance':'CV performance',
      'cv performance':'CV performance',
      'cv1':'CV1',
      'cv2':'CV2',
      'auc':'AUC',
      'bac':'BAC',
      'mcc':'MCC',
      'roc':'ROC',
      'lr probability':'LR probability',
      'lr_probability':'LR probability',
      'subject no.':'Subject no.',
      'subject no':'Subject no.',
      'generalization_error':'Generalization error',
      'selection_frequency':'Selection frequency',
      'probability_threshold':'Probability threshold',
      'net_benefit':'Net benefit'
    };
    const key = txt.toLowerCase().replace(/\s+/g,' ').trim();
    const compact = key
      .replace(/cv1[- ]test/g, 'cv1')
      .replace(/cv2[- ]test/g, 'cv2')
      .replace(/[–—]/g, '-')
      .replace(/\s+/g,' ')
      .trim();
    if(compact === 'generalization error [cv1 - cv2]' || compact === 'generalization error (cv1 - cv2)') return 'Generalization error (CV1−CV2)';
    if(compact === 'cv1/cv2 performance' || compact === 'cv1 / cv2 performance') return 'CV1/CV2 performance';
    if(explicit[key]) return explicit[key];
    txt = txt.replace(/[_]+/g,' ').replace(/([a-z])([A-Z])/g,'$1 $2').replace(/\s+/g,' ').trim();
    if(!txt) return '';
    txt = txt.charAt(0).toUpperCase() + txt.slice(1);
    txt = txt.replace(/\bCv\b/g,'CV').replace(/\bAuc\b/g,'AUC').replace(/\bBac\b/g,'BAC').replace(/\bMcc\b/g,'MCC').replace(/\bRoc\b/g,'ROC').replace(/\bLr\b/g,'LR').replace(/\bId\b/g,'ID');
    return txt;
  }

  /**
   * textBox  Estimate the bounding envelope for horizontal or rotated SVG text.
   * It is intentionally deterministic so all report/browser plot renderers can reserve comparable label space.
   */
  function textBox(text, fontSize, angleDeg){
    const fs = Number(fontSize || 12);
    const w = measureTextWidth(text, fs);
    const h = Math.ceil(fs * 1.25);
    const a = Math.abs(Number(angleDeg || 0)) * Math.PI / 180;
    return {width: Math.ceil(Math.abs(Math.cos(a))*w + Math.abs(Math.sin(a))*h), height: Math.ceil(Math.abs(Math.sin(a))*w + Math.abs(Math.cos(a))*h)};
  }

  /**
   * tickSampleIndexes  Select readable tick indexes for categorical heatmap-like axes.
   * Endpoints are retained and interior ticks are decimated according to available space.
   */
  function tickSampleIndexes(n, maxTicks){
    n = Math.max(0, Math.round(Number(n || 0)));
    maxTicks = Math.max(2, Math.round(Number(maxTicks || 8)));
    if(n <= maxTicks) return Array.from({length:n}, (_,i)=>i);
    const step = Math.max(1, Math.ceil((n - 1) / Math.max(1, maxTicks - 1)));
    const out = [];
    for(let i=0;i<n;i+=step) out.push(i);
    if(out[out.length-1] !== n-1) out.push(n-1);
    return out;
  }

  /**
   * cssColorToRgb  Convert common CSS color strings into RGB triples for contrast-aware text.
   * Supports hex and rgb()/rgba() strings generated by NM heatmap renderers; unknown colors return null so callers can fall back explicitly.
   */
  function cssColorToRgb(color){
    let txt = String(color || '').trim();
    if(!txt) return null;
    if(txt.charAt(0) === '#'){
      txt = txt.slice(1);
      if(txt.length === 3) txt = txt.split('').map(ch => ch + ch).join('');
      if(txt.length !== 6 || /[^0-9a-f]/i.test(txt)) return null;
      return {r:parseInt(txt.slice(0,2),16), g:parseInt(txt.slice(2,4),16), b:parseInt(txt.slice(4,6),16)};
    }
    const m = txt.match(/^rgba?\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$/i);
    if(m){
      return {
        r: Math.max(0, Math.min(255, Math.round(Number(m[1])))),
        g: Math.max(0, Math.min(255, Math.round(Number(m[2])))),
        b: Math.max(0, Math.min(255, Math.round(Number(m[3]))))
      };
    }
    const named = {
      black:{r:0,g:0,b:0}, white:{r:255,g:255,b:255},
      red:{r:255,g:0,b:0}, blue:{r:0,g:0,b:255}, green:{r:0,g:128,b:0},
      transparent:{r:255,g:255,b:255}
    };
    return Object.prototype.hasOwnProperty.call(named, txt.toLowerCase()) ? named[txt.toLowerCase()] : null;
  }

  /**
   * contrastTextColor  Choose black or white text for a colored heatmap cell.
   */
  function contrastTextColor(fill){
    return cellTextColor(fill, 1, '#ffffff');
  }

  /**
   * relativeLuminance  Compute WCAG-style relative luminance for an RGB triple.
   * It is used to choose readable black/white labels for heatmap cells without glow strokes.
   */
  function relativeLuminance(rgb){
    if(!rgb) return 1;
    function lin(v){
      v = Math.max(0, Math.min(1, Number(v) / 255));
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * lin(rgb.r) + 0.7152 * lin(rgb.g) + 0.0722 * lin(rgb.b);
  }

  /**
   * cellTextColor  Choose black or white text against a possibly transparent cell fill.
   * The fill is first composited over the plot background so low-opacity cells use dark text and high-intensity dark cells use white text.
   */
  function cellTextColor(fill, opacity, background){
    const fg = cssColorToRgb(fill);
    const bg = cssColorToRgb(background || '#ffffff') || {r:255,g:255,b:255};
    if(!fg) return '#0f172a';
    const a = Math.max(0, Math.min(1, Number.isFinite(Number(opacity)) ? Number(opacity) : 1));
    const rgb = {
      r: Math.round(a * fg.r + (1 - a) * bg.r),
      g: Math.round(a * fg.g + (1 - a) * bg.g),
      b: Math.round(a * fg.b + (1 - a) * bg.b)
    };
    const lum = relativeLuminance(rgb);
    const contrastBlack = (lum + 0.05) / 0.05;
    const contrastWhite = 1.05 / (lum + 0.05);
    return contrastWhite > contrastBlack ? '#ffffff' : '#0f172a';
  }

  /**
   * categoricalHeatmapLayout  Compute content-aware layout for categorical heatmaps and parameter-surface SVGs.
   * It centralizes tick sampling, rotated x tick envelopes, axis-title margins and y-label placement for browser result plots.
   */
  function categoricalHeatmapLayout(cfg){
    cfg = cfg || {};
    const w = Number(cfg.w || 1);
    const h = Number(cfg.h || 1);
    const xLabelsAll = (Array.isArray(cfg.xLabels) ? cfg.xLabels : []).map(v => String(v == null ? '' : v));
    const yLabelsAll = (Array.isArray(cfg.yLabels) ? cfg.yLabels : []).map(v => String(v == null ? '' : v));
    const cols = Math.max(1, Number(cfg.cols || xLabelsAll.length || 1));
    const rows = Math.max(1, Number(cfg.rows || yLabelsAll.length || 1));
    const tickFont = Number(cfg.tickFontSize || 11);
    const axisFont = Number(cfg.axisFontSize || 13);
    const titleFont = Number(cfg.titleFontSize || 12);
    const angle = Number.isFinite(Number(cfg.xTickAngle)) ? Number(cfg.xTickAngle) : -28;
    const maxXTicks = Math.max(2, Math.min(cols, Number(cfg.maxXTicks || Math.floor(Math.max(120,w) / 70))));
    const maxYTicks = Math.max(2, Math.min(rows, Number(cfg.maxYTicks || Math.floor(Math.max(100,h) / 28))));
    const xIdx = tickSampleIndexes(cols, maxXTicks);
    const yIdx = tickSampleIndexes(rows, maxYTicks);
    const xTickTexts = xIdx.map(i => xLabelsAll[i] || String(i+1));
    const yTickTexts = yIdx.map(i => yLabelsAll[i] || String(i+1));
    const xTickBox = xTickTexts.reduce((acc,lab) => { const b = textBox(lab, tickFont, angle); return {width:Math.max(acc.width,b.width), height:Math.max(acc.height,b.height)}; }, {width:0,height:0});
    const yTickWidth = yTickTexts.reduce((acc,lab) => Math.max(acc, measureTextWidth(lab, tickFont)), 0);
    const xAxis = prettifyLabel(cfg.xLabel || '');
    const yAxis = prettifyLabel(cfg.yLabel || '');
    const base = Object.assign({left:60,right:22,top:22,bottom:46}, cfg.m || {});
    const rightReserve = Math.max(0, Number(cfg.rightReserve || 0));
    const topReserve = Math.max(0, Number(cfg.topReserve || 0));
    const xAxisReserve = xAxis ? Math.ceil(axisFont * 1.8) : 0;
    const yAxisReserve = yAxis ? Math.ceil(axisFont * 1.9) : 0;
    const titleReserve = cfg.title ? Math.ceil(titleFont * 1.45) : 0;
    const m = {
      left: Math.max(base.left, yTickWidth + yAxisReserve + Math.ceil(tickFont * 1.1)),
      right: Math.max(base.right, rightReserve),
      top: Math.max(base.top, topReserve + titleReserve),
      bottom: Math.max(base.bottom, xTickBox.height + xAxisReserve + Math.ceil(tickFont * 0.8))
    };
    m.left = Math.min(m.left, Math.max(1, w * 0.42));
    m.bottom = Math.min(m.bottom, Math.max(1, h * 0.38));
    const plotW = Math.max(1, w - m.left - m.right);
    const plotH = Math.max(1, h - m.top - m.bottom);
    const cellW = plotW / cols;
    const cellH = plotH / rows;
    const yLabelX = yAxis ? Math.max(axisFont * 0.85, (m.left - yTickWidth - tickFont * 1.05) / 2) : 0;
    const xTickY = m.top + plotH + Math.max(12, tickFont * 1.25);
    const xAxisY = Math.min(h - Math.max(4, axisFont * 0.25), xTickY + xTickBox.height + Math.ceil(axisFont * 0.95));
    const xTicks = xIdx.map(i => {
      const x = m.left + (i + 0.5) * cellW;
      const lab = xLabelsAll[i] || String(i+1);
      if(Math.abs(angle) > 1){
        return `<text class="rvHeatmapTick" x="${x.toFixed(1)}" y="${xTickY.toFixed(1)}" text-anchor="end" transform="rotate(${angle} ${x.toFixed(1)} ${xTickY.toFixed(1)})">${esc(lab)}</text>`;
      }
      return `<text class="rvHeatmapTick" x="${x.toFixed(1)}" y="${xTickY.toFixed(1)}" text-anchor="middle">${esc(lab)}</text>`;
    }).join('');
    const yTicks = yIdx.map(i => {
      const y = m.top + (i + 0.5) * cellH + tickFont * 0.34;
      const lab = yLabelsAll[i] || String(i+1);
      return `<text class="rvHeatmapTick" x="${(m.left - Math.max(8, tickFont)).toFixed(1)}" y="${y.toFixed(1)}" text-anchor="end">${esc(lab)}</text>`;
    }).join('');
    const axisSvg = `${xAxis ? `<text class="rvHeatmapAxisLabel" x="${(m.left + plotW/2).toFixed(1)}" y="${xAxisY.toFixed(1)}" text-anchor="middle">${esc(xAxis)}</text>` : ''}` +
      `${yAxis ? `<text class="rvHeatmapAxisLabel" x="${yLabelX.toFixed(1)}" y="${(m.top + plotH/2).toFixed(1)}" text-anchor="middle" transform="rotate(-90 ${yLabelX.toFixed(1)} ${(m.top + plotH/2).toFixed(1)})">${esc(yAxis)}</text>` : ''}` +
      `<g class="rvHeatmapTicks">${xTicks}${yTicks}</g>`;
    return {m, plotW, plotH, cellW, cellH, xIdx, yIdx, xTicks, yTicks, axisSvg, yLabelX, xAxisY};
  }

  /**
   * formatPrecision  Format the precision value for labels, tables or status text.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function formatPrecision(v, precision){
    const x = Number(v);
    const p = Math.max(1, Math.min(12, Math.round(Number(precision || 4))));
    if(!Number.isFinite(x)) return '';
    return trimNumericText(x.toPrecision(p));
  }
  /**
   * uniqueTickFormatter  Provide the unique tick formatter helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function uniqueTickFormatter(tickValues, baseFormatter){
    const vals = (Array.isArray(tickValues) ? tickValues : []).map(Number).filter(Number.isFinite);
    if(!vals.length) return baseFormatter || formatNumber;
    const base = baseFormatter || formatNumber;
    const baseLabels = vals.map(v => String(base(v)));
    if(new Set(baseLabels).size === baseLabels.length) return base;
    for(let p=3; p<=10; p++){
      const labels = vals.map(v => formatPrecision(v, p));
      if(new Set(labels).size === labels.length) return v => formatPrecision(v, p);
    }
    return v => {
      const x = Number(v);
      return Number.isFinite(x) ? String(x) : '';
    };
  }
  /**
   * scaleLinear  Build the deterministic linear scale used by shared browser plots.
   */
  function scaleLinear(domain, range){
    const d0 = Number(domain[0]), d1 = Number(domain[1]), r0 = Number(range[0]), r1 = Number(range[1]);
    return function(v){
      v = Number(v);
      if(!Number.isFinite(v) || !Number.isFinite(d0) || !Number.isFinite(d1) || Math.abs(d1-d0) < 1e-12) return (r0+r1)/2;
      return r0 + ((v-d0)/(d1-d0))*(r1-r0);
    };
  }
  /**
   * ticks  Build deterministic readable linear-axis tick values.
   */
  function ticks(domain, n){
    let lo = Number(domain[0]), hi = Number(domain[1]); n = n || 6;
    if(!Number.isFinite(lo) || !Number.isFinite(hi)) return [];
    if(Math.abs(hi-lo) < 1e-12) return [lo];
    if(hi < lo){ const tmp = hi; hi = lo; lo = tmp; }
    const step0 = Math.abs(hi-lo) / Math.max(1,n-1);
    const pow10 = Math.pow(10, Math.floor(Math.log10(step0)));
    const err = step0 / pow10;
    const step = (err >= 7.5 ? 10 : err >= 3.5 ? 5 : err >= 1.5 ? 2 : 1) * pow10;
    const a = Math.ceil(lo / step) * step;
    const out = [];
    for(let v=a; v<=hi + step*0.5 && out.length < 50; v += step) out.push(Math.abs(v) < step*1e-10 ? 0 : v);
    return out;
  }
  /**
   * formatNumber  Format the number value for labels, tables or status text.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function formatNumber(v){
    const x = Number(v);
    if(!Number.isFinite(x)) return '';
    if(Math.abs(x) >= 100 || (Math.abs(x) < 0.01 && x !== 0)) return x.toPrecision(3);
    return Math.abs(x - Math.round(x)) < 1e-8 ? String(Math.round(x)) : x.toFixed(1).replace(/\.0$/,'');
  }
  /**
   * formatProb  Format the prob value for labels, tables or status text.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function formatProb(v){
    const x = Number(v);
    if(!Number.isFinite(x)) return '';
    if(Math.abs(x) < 1e-10) return '0';
    if(Math.abs(x-1) < 1e-10) return '1';
    return x.toFixed(1).replace(/\.0$/,'');
  }
  /**
   * pointString  Provide the point string helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function pointString(points, xFn, yFn){
    const pts = Array.isArray(points) ? points : [];
    return {type:'polyline', value:pts.map((p,i) => `${Number(xFn(p,i)).toFixed(1)},${Number(yFn(p,i)).toFixed(1)}`).join(' ')};
  }
  /**
   * lineElement  Provide the line element helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function lineElement(points, xFn, yFn, cls){
    const d = pointString(points, xFn, yFn);
    return `<polyline class="${esc(cls || '')}" points="${esc(d.value)}"/>`;
  }
  /**
   * areaString  Provide the area string helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function areaString(points, xFn, y0Fn, y1Fn){
    const pts = Array.isArray(points) ? points : [];
    const upper = pts.map((p,i) => `${Number(xFn(p,i)).toFixed(1)},${Number(y1Fn(p,i)).toFixed(1)}`);
    const lower = pts.slice().reverse().map((p,i) => `${Number(xFn(p, pts.length-1-i)).toFixed(1)},${Number(y0Fn(p, pts.length-1-i)).toFixed(1)}`);
    return {type:'polygon', value:upper.concat(lower).join(' ')};
  }
  /**
   * areaElement  Provide the area element helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function areaElement(points, xFn, y0Fn, y1Fn, cls){
    const d = areaString(points, xFn, y0Fn, y1Fn);
    return `<polygon class="${esc(cls || '')}" points="${esc(d.value)}"/>`;
  }
  /**
   * linePoints  Provide the line points helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function linePoints(points, xKey, yKey, ax){
    const pts = Array.isArray(points) ? points : [];
    return pointString(pts, p => ax.xPix(Number(p[xKey])), p => ax.yPix(Number(p[yKey]))).value;
  }
  /**
   * violinHalfWidth  Interpolate the shared backend KDE half-width at one value.
   * Density rows are presentation geometry supplied by NMResultsViewerTools.violinDensity; this helper performs no statistical calculation.
   */
  function violinHalfWidth(density, y, fallback){
    const rows = Array.isArray(density) ? density : [];
    const target = Number(y);
    if(!rows.length || !Number.isFinite(target)) return Number.isFinite(Number(fallback)) ? Number(fallback) : 0.18;
    let best = rows[0], distance = Math.abs(Number(best.y) - target);
    for(let i=1;i<rows.length;i++){
      const next = Math.abs(Number(rows[i].y) - target);
      if(next < distance){ best = rows[i]; distance = next; }
    }
    const width = Number(best && best.width);
    return Number.isFinite(width) && width > 0 ? width : (Number.isFinite(Number(fallback)) ? Number(fallback) : 0.18);
  }

  /**
   * violinPolygon  Render the single shared tapered KDE polygon used by OOCV and Cross-analysis.
   * The caller supplies axes and style only; scientific values, density and summaries remain backend-owned.
   */
  function violinPolygon(cfg){
    cfg = cfg || {};
    const density = Array.isArray(cfg.density) ? cfg.density : [];
    const center = Number(cfg.center), xPix = cfg.xPix, yPix = cfg.yPix;
    if(!density.length || !Number.isFinite(center) || typeof xPix !== 'function' || typeof yPix !== 'function') return '';
    const right = density.map(d => `${xPix(center + Number(d.width || 0)).toFixed(1)},${yPix(Number(d.y)).toFixed(1)}`).join(' ');
    const left = density.slice().reverse().map(d => `${xPix(center - Number(d.width || 0)).toFixed(1)},${yPix(Number(d.y)).toFixed(1)}`).join(' ');
    return `<polygon class="${esc(cfg.className || 'rvViolinDensity')}" points="${right} ${left}" fill="${esc(cfg.fill || '#64748b')}" opacity="${clamp(cfg.opacity == null ? 0.24 : cfg.opacity,0,1)}" stroke="${esc(cfg.stroke || cfg.fill || '#64748b')}" stroke-width="${Number(cfg.strokeWidth || 1.1)}"><title>${esc(cfg.title || '')}</title></polygon>`;
  }

  /**
   * violinStatisticLines  Render shared mean/median overlays extending to the local KDE boundary.
   * Mean and median values are supplied by the backend summary and are not recomputed here.
   */
  function violinStatisticLines(cfg){
    cfg = cfg || {};
    const center=Number(cfg.center),xPix=cfg.xPix,yPix=cfg.yPix,density=Array.isArray(cfg.density)?cfg.density:[];
    if(!Number.isFinite(center)||typeof xPix!=='function'||typeof yPix!=='function')return'';
    const rows=[{value:Number(cfg.mean),name:'Mean',color:cfg.meanColor||'#111827'},{value:Number(cfg.median),name:'Median',color:cfg.medianColor||'#dc2626'}];
    return rows.map(row=>{
      if(!Number.isFinite(row.value))return'';
      const half=Math.max(Number(cfg.minimumHalfWidth||0.06),Math.min(Number(cfg.maximumHalfWidth||0.34),violinHalfWidth(density,row.value,0.18)));
      const x1=xPix(center-half).toFixed(1),x2=xPix(center+half).toFixed(1),y=yPix(row.value).toFixed(1),title=`${cfg.title||''} ${row.name.toLowerCase()}: ${cfg.formatValue?cfg.formatValue(row.value):row.value}`;
      return `<g class="rvViolinStatLine rvViolinStat${row.name}"><line class="rvViolinStatUnderlay" x1="${x1}" x2="${x2}" y1="${y}" y2="${y}" style="stroke:#ffffff;stroke-width:5;stroke-opacity:.85;stroke-linecap:round"/><line x1="${x1}" x2="${x2}" y1="${y}" y2="${y}" style="stroke:${esc(row.color)};stroke-width:2.6;stroke-linecap:round"><title>${esc(title)}</title></line></g>`;
    }).join('');
  }
  /**
   * cartesianAxes  Provide the cartesian axes helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   * cfg.autoMargin: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.axisFontSize: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.h: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.lockLabelPositions: when true, explicit xLabelY/yLabelX values remain authoritative even with content-aware auto margins.
   * cfg.m: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.noPrettifyLabels: preserve caller-supplied axis-label text verbatim instead of applying shared label prettification.
   * cfg.tickFontSize: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.w: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.xFmt: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.xLabel: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.xLabelY: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.xLim: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.xTicks: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.yFmt: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.yLabel: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.yLabelX: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.yLim: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   * cfg.yTicks: browser-side field consumed from cfg while translating UI state to MATLAB-service requests.
   */
  function cartesianAxes(cfg){
    cfg = cfg || {};
    const w = Number(cfg.w || 1), h = Number(cfg.h || 1);
    const autoMargin = cfg.autoMargin !== false;
    const lockLabelPositions = cfg.lockLabelPositions === true;
    let m = Object.assign({left:48,right:18,top:18,bottom:44}, cfg.m || {});
    const xLim = cfg.xLim, yLim = cfg.yLim;
    let xTicks = (cfg.xTicks || ticks(xLim, 6)).filter(t => Number(t) >= Math.min(xLim[0],xLim[1])-1e-9 && Number(t) <= Math.max(xLim[0],xLim[1])+1e-9);
    let yTicks = (cfg.yTicks || ticks(yLim, 6)).filter(t => Number(t) >= Math.min(yLim[0],yLim[1])-1e-9 && Number(t) <= Math.max(yLim[0],yLim[1])+1e-9);
    const xFmt = cfg.xFmt || uniqueTickFormatter(xTicks, formatNumber);
    const yFmt = cfg.yFmt || uniqueTickFormatter(yTicks, formatNumber);
    const tickFont = Number(cfg.tickFontSize || 14);
    const axisFont = Number(cfg.axisFontSize || 17);
    const xLabelText = cfg.noPrettifyLabels ? String(cfg.xLabel || '') : prettifyLabel(cfg.xLabel || '');
    const yLabelText = cfg.noPrettifyLabels ? String(cfg.yLabel || '') : prettifyLabel(cfg.yLabel || '');
    const annotationLines = Array.isArray(cfg.annotationLines) ? cfg.annotationLines.map(v => String(v == null ? '' : v)).filter(Boolean) : [];
    const xTickLabels = xTicks.map(t => String(xFmt(t)));
    const yTickLabels = yTicks.map(t => String(yFmt(t)));
    const maxYTickWidth = yTickLabels.reduce((acc, lab) => Math.max(acc, measureTextWidth(lab, tickFont)), 0);
    const maxXTickWidth = xTickLabels.reduce((acc, lab) => Math.max(acc, measureTextWidth(lab, tickFont)), 0);
    let xTickAngle = Number.isFinite(Number(cfg.xTickAngle)) ? Number(cfg.xTickAngle) : 0;
    if(autoMargin && !Number.isFinite(Number(cfg.xTickAngle)) && xTickLabels.length > 2){
      const nominalPlotW = Math.max(1, w - Number(m.left || 0) - Number(m.right || 0));
      const required = maxXTickWidth * xTickLabels.length * 0.82;
      if(required > nominalPlotW * 1.08) xTickAngle = -28;
    }
    const xTickBox = xTickLabels.reduce((acc, lab) => { const b = textBox(lab, tickFont, xTickAngle); return {width:Math.max(acc.width,b.width), height:Math.max(acc.height,b.height)}; }, {width:0,height:Math.ceil(tickFont*1.25)});
    if(autoMargin){
      const yLabelReserve = yLabelText ? Math.ceil(axisFont * 1.9) : 0;
      const xLabelReserve = xLabelText ? Math.ceil(axisFont * 1.65) : 0;
      const annotationReserve = annotationLines.length ? Math.ceil((tickFont * 1.35) * annotationLines.length + tickFont * 0.6) : 0;
      const tickPadding = Math.ceil(tickFont * 1.05);
      m.left = Math.max(Number(m.left || 0), maxYTickWidth + yLabelReserve + tickPadding);
      m.bottom = Math.max(Number(m.bottom || 0), xTickBox.height + xLabelReserve + annotationReserve + Math.ceil(tickFont * 1.15));
      m.right = Math.max(Number(m.right || 0), Math.ceil(xTickBox.width / 2) + 4);
      m.top = Math.max(Number(m.top || 0), Math.ceil(tickFont * 1.2));
      m.left = Math.min(m.left, Math.max(1, w * 0.42));
      m.bottom = Math.min(m.bottom, Math.max(1, h * 0.42));
    }
    const xPix = scaleLinear(xLim, [m.left, w-m.right]);
    const yPix = scaleLinear(yLim, [h-m.bottom, m.top]);
    const plotW = Math.max(1, w - m.left - m.right);
    const plotH = Math.max(1, h - m.top - m.bottom);
    const grid = [
      ...xTicks.map(t => `<line class="rvGridLine" x1="${xPix(t).toFixed(1)}" y1="${m.top}" x2="${xPix(t).toFixed(1)}" y2="${h-m.bottom}"/>`),
      ...yTicks.map(t => `<line class="rvGridLine" x1="${m.left}" y1="${yPix(t).toFixed(1)}" x2="${w-m.right}" y2="${yPix(t).toFixed(1)}"/>`)
    ].join('');
    const xTickY = h - m.bottom + Math.max(14, tickFont * 1.45);
    const tickSvg = [
      ...xTicks.map(t => {
        const x = xPix(t).toFixed(1);
        const lab = esc(xFmt(t));
        if(Math.abs(xTickAngle) > 1){
          return `<g class="rvPanelTick"><line x1="${x}" y1="${h-m.bottom}" x2="${x}" y2="${h-m.bottom+6}"/><text x="${x}" y="${xTickY.toFixed(1)}" text-anchor="end" transform="rotate(${xTickAngle} ${x} ${xTickY.toFixed(1)})">${lab}</text></g>`;
        }
        return `<g class="rvPanelTick"><line x1="${x}" y1="${h-m.bottom}" x2="${x}" y2="${h-m.bottom+6}"/><text x="${x}" y="${xTickY.toFixed(1)}" text-anchor="middle">${lab}</text></g>`;
      }),
      ...yTicks.map(t => `<g class="rvPanelTick"><line x1="${m.left-6}" y1="${yPix(t).toFixed(1)}" x2="${m.left}" y2="${yPix(t).toFixed(1)}"/><text x="${m.left-10}" y="${yPix(t)+4}" text-anchor="end">${esc(yFmt(t))}</text></g>`)
    ].join('');
    const defaultYLabelX = yLabelText ? Math.max(axisFont * 0.75, (m.left - maxYTickWidth - tickFont * 1.05) / 2) : 0;
    const yLabelX = (!autoMargin || lockLabelPositions) && Number.isFinite(Number(cfg.yLabelX)) ? Number(cfg.yLabelX) : defaultYLabelX;
    const xLabelYDefault = h - Math.max(8, axisFont * 0.45) - (annotationLines.length ? Math.ceil(annotationLines.length * tickFont * 1.25) : 0);
    const xLabelY = (!autoMargin || lockLabelPositions) && Number.isFinite(Number(cfg.xLabelY)) ? Number(cfg.xLabelY) : xLabelYDefault;
    const annotationSvg = annotationLines.length ? `<g class="rvPanelAnnotation">${annotationLines.map((line,i) => `<text x="${m.left + plotW/2}" y="${(h - Math.max(4, tickFont * 0.45) - (annotationLines.length-1-i)*tickFont*1.25).toFixed(1)}" text-anchor="middle">${esc(line)}</text>`).join('')}</g>` : '';
    const labels = `<text class="rvPanelAxisLabel" x="${m.left + plotW/2}" y="${xLabelY}" text-anchor="middle">${esc(xLabelText)}</text>` +
      `<text class="rvPanelAxisLabel" x="${yLabelX}" y="${m.top + plotH/2}" text-anchor="middle" transform="rotate(-90 ${yLabelX} ${m.top + plotH/2})">${esc(yLabelText)}</text>`;
    return {xPix, yPix, xTicks, yTicks, xFmt, yFmt, m, plotW, plotH, svg:`<g class="rvGrid">${grid}</g><g class="rvPanelAxes"><line x1="${m.left}" y1="${h-m.bottom}" x2="${w-m.right}" y2="${h-m.bottom}"/><line x1="${m.left}" y1="${m.top}" x2="${m.left}" y2="${h-m.bottom}"/></g>${tickSvg}${labels}${annotationSvg}`};
  }
  /**
   * rocAreaBetweenCurveAndDiagonal  Provide the roc area between curve and diagonal helper used by shared D3-based plotting helper library for scientific result displays.
   * It supports shared D3-based plotting helper library for scientific result displays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function rocAreaBetweenCurveAndDiagonal(points, ax){
    let pts = (Array.isArray(points) ? points : []).map(p => ({fpr:clamp(p.fpr,0,1), tpr:clamp(p.tpr,0,1)})).filter(p => finite(p.fpr) && finite(p.tpr));
    pts.sort((a,b) => a.fpr - b.fpr || a.tpr - b.tpr);
    if(!pts.length) pts = [{fpr:0,tpr:0},{fpr:1,tpr:1}];
    if(pts[0].fpr > 0 || pts[0].tpr > 0) pts.unshift({fpr:0,tpr:0});
    const last = pts[pts.length-1];
    if(last.fpr < 1 || last.tpr < 1) pts.push({fpr:1,tpr:1});
    const roc = pts.map(p => `${ax.xPix(p.fpr).toFixed(1)},${ax.yPix(p.tpr).toFixed(1)}`);
    const diag = pts.slice().reverse().map(p => `${ax.xPix(p.fpr).toFixed(1)},${ax.yPix(p.fpr).toFixed(1)}`);
    return roc.concat(diag).join(' ');
  }
  window.NMResultsPlotD3 = {
    scaleLinear,
    ticks,
    formatNumber,
    formatProb,
    uniqueTickFormatter,
    prettifyLabel,
    measureTextWidth,
    abbreviateLabel,
    fitLabel,
    textBox,
    contrastTextColor,
    cellTextColor,
    cssColorToRgb,
    categoricalHeatmapLayout,
    cartesianAxes,
    linePoints,
    lineElement,
    areaElement,
    violinHalfWidth,
    violinPolygon,
    violinStatisticLines,
    rocAreaBetweenCurveAndDiagonal
  };
})();
