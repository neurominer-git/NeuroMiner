(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_ML_TRAIN_RUNNER_STATE || {};
  let SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite));
  let GRID_ACT = (STATE.grid && STATE.grid.GridAct) || [];
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler(SELECTED);
  let SELECTION_LOADED = !(STATE.loading || STATE.analysesLoading);
  let GRID_PICKER = null;
  let ANALYSIS_SELECTOR = null;
  let MANUAL_FILES = {};
  let MANUAL_FILE_LIST = null;
  let LAST_MANUAL_MODE = manualMode();
  let RUNTIME_PROGRESS_TIMER = null;
  let RUNTIME_PROGRESS_TASK_ID = '';
  let RUNTIME_PROGRESS_MODAL = null;
  let LAST_RUNTIME_CHART_STAMP = '';
  let RUNTIME_PROGRESS_CLOSE_TIMER = null;
  let RUNTIME_JOB_CLIENT = null;
  let RUNTIME_JOB_ACTIVE = false;
  const RUNTIME_PROGRESS_POLL_MS = 50;
  const RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS = 0;

  /**
   * API  Build an absolute local HTTP bridge URL for a browser request.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function API(path){ return `${API_BASE}${path}`; }
  /**
   * el  Return a DOM element by id for the current UI page.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function el(id){ return document.getElementById(id); }
  /**
   * arr  Normalize a nullable scalar or array-like value to an array.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function arr(x){ return x == null ? [] : (Array.isArray(x) ? x : [x]); }
  /**
   * esc  Escape text before inserting it into HTML markup.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  /**
   * appContext  Build the app context shown to users in the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function appContext(){ return (STATE && STATE.appContext) || {}; }
  /**
   * isWorkbenchChild  Return whether the is workbench child condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isWorkbenchChild(){ return String(appContext().caller || '').toLowerCase() === 'workbench'; }
  /**
   * isLoadingState  Return whether the is loading state condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLoadingState(){ return !!(STATE.loading || STATE.analysesLoading || STATE.artifactsLoading); }
  /**
   * analysisEmptyText  Build the analysis empty text shown to users in the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisEmptyText(finalText){ return isLoadingState() ? 'Loading analyses...' : finalText; }

  /**
   * postJson  Send a JSON request to the local MATLAB bridge and parse the JSON response.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postJson(path, payload){
    const response = await fetch(API(path), {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload || {})});
    const txt = await response.text();
    let obj = {};
    try { obj = JSON.parse(txt || '{}'); }
    catch(err){ throw new Error(`Browser bridge returned non-JSON for ${path}: ${(txt || '').slice(0,300)}`); }
    if(obj && typeof obj === 'object' && !obj.httpStatus) obj.httpStatus = response.status;
    return obj;
  }
  /**
   * matlabService  Send a MATLAB-service request through the browser bridge.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function matlabService(payload){ return postJson('/api/matlabservice', payload); }
  /**
   * runtimeJobClient  Return the shared durable MATLAB-job client for runner execution.
   *
   * Long-running runner operations use file-backed job status/result state and therefore have no
   * wall-clock transport timeout. Short configuration/refresh services remain synchronous.
   */
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT, storageKey:`nm2_ml_train_runtime_job_${PORT}`, pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }
  /**
   * createProgressTaskId  Create the progress task id component or browser-side state object.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createProgressTaskId(prefix){
    const rand = Math.random().toString(36).slice(2, 9);
    return `${prefix || 'task'}_${Date.now()}_${rand}`.replace(/[^A-Za-z0-9_-]/g, '');
  }
  /**
   * progressModalHtml  Build the progress modal html inserted into the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function progressModalHtml(){
    return [
      '<div id="mlRuntimeProgressPanel" class="mlrProgressPanel mlrProgressPanelModal">',
      '  <section class="mlrProgressSection mlrProgressSectionOverall">',
      '    <div class="mlrProgressLabel">Overall CV2 progress</div>',
      '    <div class="mlrProgressHead"><div id="mlRuntimeProgressText" class="help">Waiting for the first update.</div><span id="mlRuntimeProgressPercent" class="mlrProgressPercent">0%</span></div>',
      '    <div class="mlrProgressTrack"><div id="mlRuntimeProgressBar" class="mlrProgressBar" style="width:0%"></div></div>',
      '  </section>',
      '  <section id="mlRuntimeOptimizerPanel" class="mlrProgressSection mlrProgressSectionOptimizer mlrOptimizerCollapsed">',
      '    <div id="mlRuntimeOptimizerLabel" class="mlrProgressLabel">Optimization progress</div>',
      '    <div class="mlrOptimizerHead"><div id="mlRuntimeOptimizerText" class="mlrOptimizerText">Optimizer inactive for the current CV2 partition.</div><span id="mlRuntimeOptimizerPercent" class="mlrProgressPercent mlrOptimizerPercent">0%</span></div>',
      '    <div class="mlrProgressTrack mlrOptimizerTrack"><div id="mlRuntimeOptimizerBar" class="mlrProgressBar mlrOptimizerBar" style="width:0%"></div></div>',
      '    <div id="mlRuntimeChart" class="mlrLegacyChart"></div>',
      '  </section>',
      '</div>'
    ].join('');
  }
  /**
   * showRuntimeProgressPanel  Provide the show runtime progress panel helper used by machine-learning optimization runner page.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function showRuntimeProgressPanel(taskId){
    RUNTIME_PROGRESS_TASK_ID = taskId || '';
    LAST_RUNTIME_CHART_STAMP = '';
    cancelRuntimeProgressAutoClose();
    if(window.NMModal && typeof window.NMModal.open === 'function'){
      if(RUNTIME_PROGRESS_MODAL && !RUNTIME_PROGRESS_MODAL.closed){ RUNTIME_PROGRESS_MODAL.close(); }
      RUNTIME_PROGRESS_MODAL = window.NMModal.open({
        title:'NM Training Progress Viewer',
        size:'wide',
        dismissOnBackdrop:false,
        dismissOnEscape:false,
        closeLabel:'Hide viewer',
        closeGlyph:'\u2212',
        render:(body)=>{ body.innerHTML = progressModalHtml(); },
        onClose:()=>{ RUNTIME_PROGRESS_MODAL = null; }
      });
    } else {
      const host = el('mlRuntimeProgressHost');
      if(host){ host.innerHTML = progressModalHtml(); host.classList.remove('hidden'); }
    }
    updateRuntimeProgressPayload({percent:0, title:'NM Training Progress Viewer', message:'Preparing CV2 partition processing.', active:true, chart:{available:false, message:'Optimizer inactive for the current CV2 partition.'}});
    startRuntimeProgressPolling(taskId);
  }
  /**
   * cancelRuntimeProgressAutoClose  Return whether the cancel runtime progress auto close condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function cancelRuntimeProgressAutoClose(){
    if(RUNTIME_PROGRESS_CLOSE_TIMER){ window.clearTimeout(RUNTIME_PROGRESS_CLOSE_TIMER); RUNTIME_PROGRESS_CLOSE_TIMER = null; }
  }
  /**
   * hideRuntimeProgressPanel  Provide the hide runtime progress panel helper used by machine-learning optimization runner page.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function hideRuntimeProgressPanel(){
    stopRuntimeProgressPolling();
    cancelRuntimeProgressAutoClose();
    if(RUNTIME_PROGRESS_MODAL && !RUNTIME_PROGRESS_MODAL.closed){ RUNTIME_PROGRESS_MODAL.close(); RUNTIME_PROGRESS_MODAL = null; }
    const host = el('mlRuntimeProgressHost');
    if(host){ host.classList.add('hidden'); host.innerHTML = ''; }
  }
  /**
   * scheduleRuntimeProgressAutoClose  Provide the schedule runtime progress auto close helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function scheduleRuntimeProgressAutoClose(delayMs){
    cancelRuntimeProgressAutoClose();
    RUNTIME_PROGRESS_CLOSE_TIMER = window.setTimeout(()=>{
      RUNTIME_PROGRESS_CLOSE_TIMER = null;
      hideRuntimeProgressPanel();
    }, Math.max(0, Number(delayMs) || 0));
  }
  /**
   * startRuntimeProgressPolling  Provide the start runtime progress polling helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function startRuntimeProgressPolling(taskId){
    stopRuntimeProgressPolling();
    if(!taskId) return;
    /**
     * tick  Provide the tick helper used by machine-learning optimization runner page.
     * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
     * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
     */
    const tick = async ()=>{
      try{
        const response = await fetch(API(`/api/progress/${encodeURIComponent(taskId)}`), {method:'GET', cache:'no-store'});
        if(!response.ok) return;
        const payload = await response.json();
        if(!payload || payload.taskId !== taskId || payload.transient) return;
        if(payload.failed || payload.cancelled){ hideRuntimeProgressPanel(); return; }
        updateRuntimeProgressPayload(payload);
        if(payload.done){ stopRuntimeProgressPolling(); scheduleRuntimeProgressAutoClose(450); }
      } catch(_err){
        // Transient locks or partial reads are expected while MATLAB overwrites progress JSON.
      }
    };
    tick();
    RUNTIME_PROGRESS_TIMER = window.setInterval(tick, RUNTIME_PROGRESS_POLL_MS);
  }
  /**
   * stopRuntimeProgressPolling  Provide the stop runtime progress polling helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function stopRuntimeProgressPolling(){
    if(RUNTIME_PROGRESS_TIMER){ window.clearInterval(RUNTIME_PROGRESS_TIMER); RUNTIME_PROGRESS_TIMER = null; }
  }
  /**
   * updateRuntimeProgressPayload  Update runtime progress payload state or markup after user interaction or bridge refresh.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   * payload.message: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   * payload.overall: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   * payload.percent: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   * payload.phase: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   */
  function updateRuntimeProgressPayload(payload){
    const overall = (payload && payload.overall && typeof payload.overall === 'object') ? payload.overall : null;
    const pctRaw = overall && Number.isFinite(Number(overall.percent)) ? overall.percent : (payload && payload.percent);
    const pct = Number.isFinite(Number(pctRaw)) ? Math.max(0, Math.min(100, Number(pctRaw))) : 0;
    const text = el('mlRuntimeProgressText');
    const pctEl = el('mlRuntimeProgressPercent');
    const bar = el('mlRuntimeProgressBar');
    const overallMessage = (overall && overall.message) || (payload && (payload.message || payload.phase)) || 'Waiting for progress update.';
    if(text) renderPlainProgressMessageText(text, overallMessage);
    if(pctEl) pctEl.textContent = `${pct.toFixed(0)}%`;
    if(bar) bar.style.width = `${pct}%`;
    renderOptimizerProgressPanel(payload);
  }
  /**
   * svgEsc  Provide the svg esc helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function svgEsc(s){ return esc(s).replace(/`/g, '&#96;'); }
  /**
   * numericArray  Provide the numeric array helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function numericArray(x){ return arr(x).map(v => Number(v)).filter(v => Number.isFinite(v)); }
  /**
   * matrixRows  Provide the matrix rows helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function matrixRows(x){
    if(!Array.isArray(x) || !x.length) return [];
    if(Array.isArray(x[0])) return x.map(row => arr(row).map(v => Number(v)));
    return [x.map(v => Number(v))];
  }
  /**
   * matrixValue  Provide the matrix value helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function matrixValue(M, r, c){
    if(!M || !M.length) return 0;
    if(!Array.isArray(M[r])) return 0;
    const v = Number(M[r][c]);
    return Number.isFinite(v) ? v : 0;
  }
  /**
   * axisLimits  Provide the axis limits helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function axisLimits(axis, values){
    const ylm = numericArray(axis && axis.ylim);
    if(ylm.length >= 2 && Number.isFinite(ylm[0]) && Number.isFinite(ylm[1]) && ylm[1] > ylm[0]) return [ylm[0], ylm[1]];
    const vals = [];
    matrixRows(values).forEach(row => row.forEach(v => { if(Number.isFinite(v)) vals.push(v); }));
    if(!vals.length) return [0, 1];
    let lo = Math.min(...vals), hi = Math.max(...vals);
    if(lo === hi){ lo -= 0.5; hi += 0.5; }
    return [lo, hi];
  }
  /**
   * chartColor  Provide the chart color helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function chartColor(axis, index, preferSeriesPalette){
    const pal = ['#2563eb','#dc2626','#16a34a','#f59e0b','#7c3aed','#0891b2','#db2777','#65a30d','#ea580c','#475569'];
    const idx = Math.max(0, Math.round(Number(index) || 0));
    if(preferSeriesPalette) return pal[idx % pal.length];
    const raw = String((axis && axis.faceColor) || '').trim();
    return raw || pal[idx % pal.length];
  }
  /**
   * latexish  Provide the latexish helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function latexish(s){
    return String(s == null ? '' : s)
      .replace(/_\{1\}/g, '₁')
      .replace(/_\{2\}/g, '₂')
      .replace(/_\{LGO\}/g, 'LGO')
      .replace(/[{}]/g, '');
  }
  /**
   * renderPlainProgressMessageText  Render the plain progress message text UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderPlainProgressMessageText(node, message){
    if(!node) return;
    node.innerHTML = '';
    const main = document.createElement('div');
    main.textContent = message || 'Waiting for progress update.';
    node.appendChild(main);
  }
  /**
   * renderOptimizerProgressPanel  Render the optimizer progress panel UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * payload.chart: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   * payload.updatedAtDatenum: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderOptimizerProgressPanel(payload){
    const panel = el('mlRuntimeOptimizerPanel');
    const txt = el('mlRuntimeOptimizerText');
    const pctEl = el('mlRuntimeOptimizerPercent');
    const bar = el('mlRuntimeOptimizerBar');
    const chartHost = el('mlRuntimeChart');
    const chart = payload && payload.chart ? payload.chart : null;
    const active = !!(chart && chart.available);
    const optimizing = active && chart.optimizerActive;
    const pct = active && Number.isFinite(Number(chart.percent)) ? Math.max(0, Math.min(100, Number(chart.percent))) : 0;
    if(panel) panel.classList.toggle('mlrOptimizerCollapsed', !active);
    const label = el('mlRuntimeOptimizerLabel');
    if(label) label.textContent = active && !optimizing ? chart.title : 'Optimization progress';
    if(txt){
      const params = active && optimizing ? String(chart.parameterText || '').trim() : '';
      txt.textContent = active && !optimizing ? chart.message : active ? (params ? `Hyperparameters: ${params}` : 'Hyperparameters: current combination') : ((chart && chart.message) || 'Optimizer inactive for the current CV2 partition.');
    }
    if(pctEl) pctEl.textContent = active ? `${pct.toFixed(0)}%` : '';
    if(bar) bar.style.width = `${pct}%`;
    if(optimizing){
      const stamp = `${payload.updatedAtDatenum || ''}|${chart.percent || ''}|${chart.parameterText || ''}`;
      if(stamp !== LAST_RUNTIME_CHART_STAMP){ LAST_RUNTIME_CHART_STAMP = stamp; renderLegacyCV2Chart(chart); }
    } else if(active){
      LAST_RUNTIME_CHART_STAMP = '';
      if(chartHost) chartHost.innerHTML = '';
    } else if(chartHost){
      LAST_RUNTIME_CHART_STAMP = '';
      chartHost.innerHTML = `<div class="mlrLegacyChartEmpty">${esc((chart && chart.message) || 'Optimizer inactive for the current CV2 partition.')}</div>`;
    }
  }
  /**
   * niceNumber  Provide the nice number helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function niceNumber(range, round){
    const r = Math.abs(Number(range));
    if(!Number.isFinite(r) || r <= 0) return 1;
    const exponent = Math.floor(Math.log10(r));
    const fraction = r / Math.pow(10, exponent);
    let niceFraction;
    if(round){
      if(fraction < 1.5) niceFraction = 1;
      else if(fraction < 3) niceFraction = 2;
      else if(fraction < 7) niceFraction = 5;
      else niceFraction = 10;
    } else {
      if(fraction <= 1) niceFraction = 1;
      else if(fraction <= 2) niceFraction = 2;
      else if(fraction <= 5) niceFraction = 5;
      else niceFraction = 10;
    }
    return niceFraction * Math.pow(10, exponent);
  }
  /**
   * formatTick  Format the tick value for labels, tables or status text.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function formatTick(tick, step){
    const absStep = Math.abs(Number(step));
    let digits = 0;
    if(Number.isFinite(absStep) && absStep > 0 && absStep < 1){
      digits = Math.min(3, Math.max(1, Math.ceil(-Math.log10(absStep))));
    } else if(Math.abs(tick) < 2 && absStep < 0.5){
      digits = 2;
    }
    return Number(tick).toFixed(digits);
  }
  /**
   * niceTicks  Provide the nice ticks helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function niceTicks(ymin, ymax, targetIntervals){
    let lo = Number(ymin), hi = Number(ymax);
    if(!Number.isFinite(lo) || !Number.isFinite(hi) || hi <= lo) return {ticks:[0, 1], step:1};
    const target = Math.max(2, Math.round(Number(targetIntervals) || 10));
    const range = niceNumber(hi - lo, false);
    const step = niceNumber(range / target, true);
    const start = Math.ceil(lo / step) * step;
    const end = Math.floor(hi / step) * step;
    const ticks = [];
    for(let t=start, guard=0; t <= end + step*1e-8 && guard < 50; t += step, guard++){
      const v = Math.abs(t) < step*1e-10 ? 0 : t;
      if(v >= lo - step*1e-8 && v <= hi + step*1e-8) ticks.push(v);
    }
    if(!ticks.length || ticks[0] > lo + step*1e-8) ticks.unshift(lo);
    if(ticks[ticks.length-1] < hi - step*1e-8) ticks.push(hi);
    return {ticks, step};
  }
  /**
   * vectorFromMatrix  Provide the vector from matrix helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function vectorFromMatrix(x, dims){
    const flat = [];
    /**
     * walk  Provide the walk helper used by machine-learning optimization runner page.
     * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function walk(v){ if(Array.isArray(v)) v.forEach(walk); else { const n = Number(v); flat.push(Number.isFinite(n) ? n : 0); } }
    walk(x);
    const d = numericArray(dims);
    if(d.length >= 2 && d[0] > 0 && d[1] > 0){
      const rows = Math.max(1, Math.round(d[0]));
      const cols = Math.max(1, Math.round(d[1]));
      const M = [];
      let k = 0;
      for(let r=0;r<rows;r++){
        const row = [];
        for(let c=0;c<cols;c++) row.push(k < flat.length ? flat[k++] : 0);
        M.push(row);
      }
      return M;
    }
    if(Array.isArray(x) && x.length && Array.isArray(x[0])) return x.map(row => arr(row).map(v => Number(v)));
    return flat.length ? flat.map(v => [v]) : [];
  }
  /**
   * progressMetricRailCount  Count independent x-axis metric rails rather than bars.
   * In the binary row, matrix columns are classifier series; in aggregate multi-class axes,
   * a serialized 1-by-N vector without a series legend represents N metric rails.
   */
  function progressMetricRailCount(axis, seriesPalette){
    const labels = arr(axis && axis.labels).filter(label => String(label == null ? '' : label).trim());
    const values = vectorFromMatrix(axis && axis.values, axis && axis.valueSize);
    const rows = Math.max(1, values.length);
    const cols = Math.max(1, ...values.map(row => Array.isArray(row) ? row.length : 1));
    if(seriesPalette) return Math.max(1, labels.length || rows);
    if(labels.length > 1) return labels.length;
    if(rows === 1 && cols > 1) return cols;
    return Math.max(1, labels.length || rows);
  }
  /**
   * layoutProgressAxisRow  Lay out one logical progress-chart row according to metric-rail density.
   * An optional firstWidth locks corresponding performance panels to the same width across rows.
   */
  function layoutProgressAxisRow(row, bottom, height, seriesPalette, firstWidth){
    const items = arr(row).filter(axis => axis && typeof axis === 'object');
    if(!items.length) return [];
    const gap = items.length > 1 ? 0.018 : 0;
    const usable = Math.max(0.1, 1 - gap * Math.max(0, items.length - 1));
    const weights = items.map(axis => progressMetricRailCount(axis, seriesPalette));
    const widths = new Array(items.length).fill(0);
    if(items.length > 1 && Number.isFinite(Number(firstWidth)) && Number(firstWidth) > 0 && Number(firstWidth) < usable){
      widths[0] = Number(firstWidth);
      const restUsable = Math.max(0.05, usable - widths[0]);
      const restTotal = Math.max(1, weights.slice(1).reduce((sum, value) => sum + value, 0));
      for(let i=1;i<items.length;i++) widths[i] = restUsable * weights[i] / restTotal;
    } else {
      const total = Math.max(1, weights.reduce((sum, value) => sum + value, 0));
      for(let i=0;i<items.length;i++) widths[i] = usable * weights[i] / total;
    }
    let left = 0;
    return items.map((axis, index) => {
      const out = Object.assign({}, axis, {position:[left, bottom, widths[index], height]});
      left += widths[index] + gap;
      return out;
    });
  }
  /**
   * multiClassProgressAxes  Pack binary-decomposition and aggregate multi-class axes into two
   * dense rows. Performance panels share one width; the remaining width follows the number of
   * metric rails (Complexity 1, Binary Diversity 2, Multi-Class Diversity 3).
   */
  function multiClassProgressAxes(axes, multiAxes){
    const binary = arr(axes).filter(axis => axis && typeof axis === 'object').map(axis => Object.assign({}, axis));
    const aggregate = arr(multiAxes).filter(axis => axis && typeof axis === 'object').map(axis => Object.assign({}, axis));
    if(binary.length) binary[0].title = 'Binary Performance';
    const complexity = binary.find(axis => String(axis.title || '').trim().toLowerCase() === 'complexity');
    if(complexity){
      const values = vectorFromMatrix(complexity.values, complexity.valueSize);
      const errors = vectorFromMatrix(complexity.errors, complexity.errorSize);
      if(values.length > 1 && values[0].length){
        complexity.values = values[0].slice();
        complexity.valueSize = [1, values[0].length];
        complexity.errors = errors.length ? arr(errors[0]).slice() : [];
        complexity.errorSize = errors.length ? [1, complexity.errors.length] : [0, 0];
        complexity.labels = arr(complexity.labels).slice(0, 1);
      }
    }
    if(binary.length && aggregate.length && arr(binary[0].labels).length){
      aggregate[0].labels = arr(binary[0].labels).slice();
    }
    if(aggregate.length > 1){
      const diversityValues = vectorFromMatrix(aggregate[1].values, aggregate[1].valueSize);
      const diversityCols = diversityValues.length === 1 && Array.isArray(diversityValues[0]) ? diversityValues[0].length : 0;
      if(diversityCols === 3) aggregate[1].labels = ['Tr Div','CV_{1} Div','CV_{2} Div'];
    }
    const rowGap = 0.025;
    const rowHeight = (1 - rowGap) / 2;
    const lower = layoutProgressAxisRow(aggregate, 0, rowHeight, false);
    const performanceWidth = lower.length ? lower[0].position[2] : NaN;
    const upper = layoutProgressAxisRow(binary, rowHeight + rowGap, rowHeight, true, performanceWidth);
    upper.forEach(axis => { axis.progressSeriesPalette = true; });
    return upper.concat(lower);
  }

  /**
   * normalizeAxisPositions  Normalize axis positions payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalizeAxisPositions(allAxes){
    const raw = allAxes.map((axis, axisIndex) => {
      let pos = numericArray(axis && axis.position);
      if(pos.length < 4) pos = [0.10, 0.10 + axisIndex * 0.22, 0.85, 0.18];
      return {axis, pos};
    });
    let minBottom = 1, maxTop = 0, minLeft = 1, maxRight = 0;
    raw.forEach(item => {
      const l = Number(item.pos[0]);
      const b = Number(item.pos[1]);
      const w = Number(item.pos[2]);
      const h = Number(item.pos[3]);
      if(Number.isFinite(l)) minLeft = Math.min(minLeft, l);
      if(Number.isFinite(l) && Number.isFinite(w)) maxRight = Math.max(maxRight, l + w);
      if(Number.isFinite(b)) minBottom = Math.min(minBottom, b);
      if(Number.isFinite(b) && Number.isFinite(h)) maxTop = Math.max(maxTop, b + h);
    });
    if(!(maxTop > minBottom)){ minBottom = 0; maxTop = 1; }
    if(!(maxRight > minLeft)){ minLeft = 0; maxRight = 1; }
    const xSpan = Math.max(0.01, maxRight - minLeft);
    const xPad = Math.max(0, (1 - xSpan) / 2);
    return {items: raw, minBottom, maxTop, span: Math.max(0.01, maxTop - minBottom), minLeft, maxRight, xSpan, xPad};
  }
  /**
   * renderLegacyCV2Chart  Render the legacy cv2 chart UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderLegacyCV2Chart(chart){
    const host = el('mlRuntimeChart');
    if(!host) return;
    const axes = arr(chart.axes);
    const multiAxes = arr(chart.multiAxes);
    const allAxes = multiAxes.length ? multiClassProgressAxes(axes, multiAxes)
      : axes.length > 1 ? layoutProgressAxisRow(axes, 0, 1, true) : axes;
    if(!allAxes.length){ host.innerHTML = '<div class="mlrLegacyChartEmpty">No chart axes are available yet.</div>'; return; }
    const W = 1040;
    const hostWidth = Math.max(640, Number(host.clientWidth) || W);
    const hostHeight = Math.max(260, Number(host.clientHeight) || (chart.hasMultiPanels ? 520 : 440));
    // Match the SVG viewBox aspect ratio to the actual flex-constrained host.
    // This preserves readable text while compressing one or several legacy
    // bar-plot axes into the modal's available height without body scrolling.
    const H = Math.max(260, Math.round(hostHeight * W / hostWidth));
    const layout = normalizeAxisPositions(allAxes);
    const area = {x: 0, y: 4, w: W, h: H - 8};
    let svg = `<svg class="mlrLegacyChartSvg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Legacy CV2 progress chart">`;
    layout.items.forEach(({axis, pos}) => {
      const centeredLeft = ((pos[0] - layout.minLeft) + layout.xPad) / Math.max(0.01, layout.xSpan + 2 * layout.xPad);
      const centeredWidth = pos[2] / Math.max(0.01, layout.xSpan + 2 * layout.xPad);
      const x = area.x + centeredLeft * area.w;
      const y = area.y + ((layout.maxTop - (pos[1] + pos[3])) / layout.span) * area.h;
      const w = Math.max(80, centeredWidth * area.w);
      const h = Math.max(80, (pos[3] / layout.span) * area.h);
      let values = vectorFromMatrix(axis.values, axis.valueSize);
      let errors = vectorFromMatrix(axis.errors, axis.errorSize);
      if(!values.length) return;
      const labels = arr(axis.labels);
      const legend = arr(axis.legend).filter(Boolean);
      const categoryColumns = !axis.progressSeriesPalette && values.length === 1 && values[0].length > 1 && labels.length === values[0].length;
      if(categoryColumns){
        values = values[0].map(value => [value]);
        const errorRow = errors.length ? errors[0] : [];
        errors = values.map((_row, index) => [Number(errorRow[index]) || 0]);
      }
      const rows = values.length;
      const cols = Math.max(...values.map(row => row.length), 1);
      const binaryLegend = !!axis.progressSeriesPalette && String(axis.title || '') === 'Binary Performance';
      const legendFontSize = legend.length > 60 ? 8 : legend.length > 30 ? 9 : legend.length > 20 ? 10 : legend.length > 12 ? 11 : legend.length > 8 ? 12 : 14;
      const legendRowStep = Math.max(10, legendFontSize + 2);
      const legendAreaW0 = Math.max(80, w - 24);
      const legendTargetItemW = legendFontSize <= 8 ? 58 : legendFontSize <= 10 ? 74 : legendFontSize <= 12 ? 92 : 116;
      const legendMaxCols = Math.max(1, Math.floor(legendAreaW0 / legendTargetItemW));
      const legendPreferredCols = legend.length <= 8 ? 3 : legend.length <= 16 ? 4 : legend.length <= 30 ? 5 : legend.length <= 60 ? 6 : 8;
      const legendCols = legend.length && cols > 1 ? Math.min(legend.length, Math.max(1, Math.min(legendPreferredCols, legendMaxCols))) : 0;
      const legendRows = legendCols ? Math.ceil(legend.length / legendCols) : 0;
      const m = {l:66, r:24, t:legendRows ? 41 + legendRowStep * legendRows : 36, b:42};
      const px = x + m.l, py = y + m.t, pw = Math.max(20, w - m.l - m.r), ph = Math.max(20, h - m.t - m.b);
      const [ymin, ymax] = axisLimits(axis, values);
      /**
       * ymap  Provide the ymap helper used by machine-learning optimization runner page.
       * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
       * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
       */
      const ymap = (v)=> py + ph - ((Number(v) - ymin) / (ymax - ymin)) * ph;
      svg += `<g class="mlrLegacyAxis">`;
      svg += `<text x="${(x+w/2).toFixed(1)}" y="${(y+22).toFixed(1)}" text-anchor="middle" class="mlrLegacyAxisTitle">${svgEsc(axis.title || '')}</text>`;
      svg += `<rect x="${px.toFixed(1)}" y="${py.toFixed(1)}" width="${pw.toFixed(1)}" height="${ph.toFixed(1)}" class="mlrLegacyPlotBox"/>`;
      svg += `<line x1="${px.toFixed(1)}" y1="${py.toFixed(1)}" x2="${px.toFixed(1)}" y2="${(py+ph).toFixed(1)}" class="mlrLegacyAxisLine"/>`;
      svg += `<line x1="${px.toFixed(1)}" y1="${(py+ph).toFixed(1)}" x2="${(px+pw).toFixed(1)}" y2="${(py+ph).toFixed(1)}" class="mlrLegacyAxisLine"/>`;
      const tickInfo = niceTicks(ymin, ymax, 10);
      tickInfo.ticks.forEach((tick)=>{
        const ty = ymap(tick);
        svg += `<line x1="${(px-8).toFixed(1)}" y1="${ty.toFixed(1)}" x2="${px.toFixed(1)}" y2="${ty.toFixed(1)}" class="mlrLegacyAxisLine"/>`;
        svg += `<line x1="${(px+pw).toFixed(1)}" y1="${ty.toFixed(1)}" x2="${(px+pw+8).toFixed(1)}" y2="${ty.toFixed(1)}" class="mlrLegacyAxisLine"/>`;
        svg += `<text x="${(px-12).toFixed(1)}" y="${(ty+4).toFixed(1)}" text-anchor="end" class="mlrLegacyTick">${formatTick(tick, tickInfo.step)}</text>`;
      });
      if(axis.ylabel) svg += `<text transform="translate(${(x+16).toFixed(1)} ${(py+ph/2).toFixed(1)}) rotate(-90)" text-anchor="middle" class="mlrLegacyYLabel">${svgEsc(axis.ylabel)}</text>`;
      const groupW = pw / Math.max(rows, 1);
      const groupGap = Math.min(10, groupW * 0.04);
      const slotW = Math.max(0.5, (groupW - groupGap) / Math.max(cols, 1));
      const minBarW = cols >= 32 ? 1 : cols >= 16 ? 1.5 : cols >= 8 ? 2.5 : 6;
      const barW = Math.max(minBarW, slotW * (cols === 1 ? 0.88 : 0.82));
      const useSeriesPalette = (!!axis.progressSeriesPalette || categoryColumns) && rows * cols > 1;
      if(binaryLegend && rows > 1){
        for(let rail=1; rail<rows; rail++){
          const sx = px + rail * groupW;
          svg += `<line x1="${sx.toFixed(1)}" y1="${py.toFixed(1)}" x2="${sx.toFixed(1)}" y2="${(py+ph).toFixed(1)}" class="mlrLegacyRailSeparator"/>`;
        }
      }
      for(let r=0;r<rows;r++){
        const gx = px + r*groupW + groupW/2;
        for(let c=0;c<cols;c++){
          const v = matrixValue(values, r, c);
          const e = Math.abs(matrixValue(errors, r, c));
          const bx = gx - (cols*slotW)/2 + c*slotW + (slotW-barW)/2;
          const by = Math.min(ymap(v), ymap(0));
          const bh = Math.max(1, Math.abs(ymap(v) - ymap(0)));
          const colorIndex = cols > 1 ? c : r;
          svg += `<rect x="${bx.toFixed(1)}" y="${by.toFixed(1)}" width="${barW.toFixed(1)}" height="${bh.toFixed(1)}" fill="${chartColor(axis,colorIndex,useSeriesPalette)}" class="mlrLegacyBar"/>`;
          if(e > 0){
            const ey1 = ymap(v - e), ey2 = ymap(v + e), ex = bx + barW/2;
            const cap = Math.min(5, Math.max(1, barW * 0.45));
            svg += `<line x1="${ex.toFixed(1)}" y1="${ey1.toFixed(1)}" x2="${ex.toFixed(1)}" y2="${ey2.toFixed(1)}" class="mlrLegacyErr"/>`;
            svg += `<line x1="${(ex-cap).toFixed(1)}" y1="${ey1.toFixed(1)}" x2="${(ex+cap).toFixed(1)}" y2="${ey1.toFixed(1)}" class="mlrLegacyErr"/>`;
            svg += `<line x1="${(ex-cap).toFixed(1)}" y1="${ey2.toFixed(1)}" x2="${(ex+cap).toFixed(1)}" y2="${ey2.toFixed(1)}" class="mlrLegacyErr"/>`;
          }
        }
        const lab = latexish(labels[r] || '');
        svg += `<text x="${gx.toFixed(1)}" y="${(py+ph+26).toFixed(1)}" text-anchor="middle" class="mlrLegacyXLabel">${svgEsc(lab)}</text>`;
      }
      if(legendRows){
        const legendAreaX = x + 12;
        const legendAreaW = Math.max(80, w - 24);
        const legendItemW = legendAreaW / legendCols;
        const legendSwatch = Math.max(6, Math.min(8, legendFontSize - 2));
        legend.forEach((lg, i)=>{
          const lc = i % legendCols;
          const lr = Math.floor(i / legendCols);
          const lx = legendAreaX + lc * legendItemW;
          const ly = y + 39 + lr * legendRowStep;
          svg += `<rect x="${lx.toFixed(1)}" y="${(ly-legendSwatch).toFixed(1)}" width="${legendSwatch.toFixed(1)}" height="${legendSwatch.toFixed(1)}" fill="${chartColor(axis,i,useSeriesPalette)}"/>`;
          svg += `<text x="${(lx+legendSwatch+4).toFixed(1)}" y="${ly.toFixed(1)}" class="mlrLegacyLegend" style="font-size:${legendFontSize}px">${svgEsc(latexish(lg))}</text>`;
        });
      }
      svg += `</g>`;
    });
    svg += '</svg>';
    host.innerHTML = svg;
  }

  /**
   * setMsg  Route a status message to the page message strip.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * normalizedAnalyses  Normalize d analyses payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalizedAnalyses(){
    if(window.NMAnalysisCardSelector && typeof window.NMAnalysisCardSelector.normalizeAnalyses === 'function'){
      const primary = window.NMAnalysisCardSelector.normalizeAnalyses(STATE.analyses || []);
      if(primary.length) return primary;
      return window.NMAnalysisCardSelector.normalizeAnalyses(STATE.analysisList || []);
    }
    return arr(STATE.analyses);
  }
  /**
   * analyses  Provide the analyses helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analyses(){ return normalizedAnalyses(); }
  /**
   * preserveSelectionAfterStateUpdate  Provide the preserve selection after state update helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function preserveSelectionAfterStateUpdate(previousSelection){
    const fallback = arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite);
    const valid = new Set(analyses().map(a => Number(a.index)).filter(Number.isFinite));
    const keep = arr(previousSelection).map(Number).filter(idx => Number.isFinite(idx) && valid.has(idx));
    SELECTED = new Set(keep.length ? keep : fallback);
  }
  /**
   * selectedAnalyses  Apply the ed analyses selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedAnalyses(){ return analyses().filter(a => a.enabled && SELECTED.has(Number(a.index))); }
  /**
   * currentMode  Provide the current mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentMode(){ const x = el('operationMode'); return x ? String(x.value || 'auto') : 'auto'; }
  /**
   * manualMode  Provide the manual mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualMode(){ const x = el('manualArtifactMode'); return x ? String(x.value || 'none') : 'none'; }
  /**
   * effectiveModeForUI  Provide the effective mode for ui helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function effectiveModeForUI(){ const mm = manualMode(); return mm && mm !== 'none' ? mm : currentMode(); }
  /**
   * modeLabel  Build the mode label shown to users in the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function modeLabel(mode){ return ({auto:'Auto', scratch:'Scratch', preproc:'PreprocData', datamat:'CVdatamat', results:'CVresults'})[mode] || mode; }
  /**
   * manualOptionLabel  Build the manual option label shown to users in the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualOptionLabel(mode){ return ({none:'None — use automatic resolver', preproc:'Select PreprocMaster or CV2 PreprocData', datamat:'Select CVdataMaster or CV2 CVdatamats', results:'Select CVresultsMaster or CVresults'})[mode] || modeLabel(mode); }
  /**
   * isArtifactMode  Return whether the is artifact mode condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isArtifactMode(mode){ return ['preproc','datamat','results'].includes(String(mode || '')); }
  /**
   * manualOptionsForOperationMode  Provide the manual options for operation mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualOptionsForOperationMode(mode){
    mode = String(mode || 'auto');
    if(mode === 'scratch') return ['none'];
    if(isArtifactMode(mode)) return ['none', mode];
    return ['none','preproc','datamat','results'];
  }
  /**
   * modeForAnalysis  Provide the mode for analysis helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function modeForAnalysis(a, gridInfo){
    const mm = manualMode();
    if(mm && mm !== 'none') return mm;
    const mode = currentMode();
    if(mode === 'auto') return resolveAutoModeForSelection(gridInfo || sameSelectedGrid()).mode;
    return mode;
  }
  /**
   * clearManualFiles  Clear the manual files UI state, cache or rendered content.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function clearManualFiles(){ MANUAL_FILES = {}; MANUAL_FILE_LIST = null; }
  /**
   * updateManualModeDropdown  Update manual mode dropdown state or markup after user interaction or bridge refresh.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function updateManualModeDropdown(){
    const x = el('manualArtifactMode');
    if(!x) return 'none';
    const allowed = manualOptionsForOperationMode(currentMode());
    const current = String(x.value || 'none');
    if(x.dataset.allowedModes !== allowed.join('|')){
      x.innerHTML = allowed.map(mode => `<option value="${esc(mode)}">${esc(manualOptionLabel(mode))}</option>`).join('');
      x.dataset.allowedModes = allowed.join('|');
    }
    if(!allowed.includes(current)){
      clearManualFiles();
      x.value = 'none';
      LAST_MANUAL_MODE = 'none';
      return 'none';
    }
    x.value = current;
    if(!allowed.includes(LAST_MANUAL_MODE)) LAST_MANUAL_MODE = current;
    return current;
  }
  /**
   * syncManualModeToOperationMode  Synchronize the manual mode to operation mode browser state with related controls.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function syncManualModeToOperationMode(){
    return updateManualModeDropdown();
  }
  /**
   * artifactItem  Provide the artifact item helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactItem(summary, key){
    if(summary && summary[key] && typeof summary[key] === 'object') return summary[key];
    return {available:false, coverageText:'not found', reason:'', nAvailable:0, nExpected:NaN, nLogicalAvailable:0, nLogicalExpected:NaN, cellAvailableMask:[]};
  }
  /**
   * artifactStatus  Provide the artifact status helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   * item.available: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   * item.coverageText: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   */
  function artifactStatus(item){
    if(!item) return 'not found';
    if(item.coverageText && item.coverageText !== 'not found') return item.coverageText;
    return item.available ? 'available' : 'not found';
  }

  /**
   * selectedCount  Apply the ed count selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedCount(G){ return arr(G).reduce((acc,row) => acc + arr(row).filter(Boolean).length, 0); }
  /**
   * fullGrid  Resolve the full grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function fullGrid(ix,jx){ return Array.from({length:ix}, () => Array.from({length:jx}, () => true)); }
  /**
   * copyGrid  Resolve the copy grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function copyGrid(G){ return arr(G).map(row => arr(row).map(Boolean)); }
  /**
   * artifactFieldForMode  Provide the artifact field for mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactFieldForMode(mode){
    if(mode === 'preproc') return 'preprocData';
    if(mode === 'datamat') return 'cvDatamat';
    if(mode === 'results') return 'cvResults';
    return '';
  }
  /**
   * artifactItemForMode  Provide the artifact item for mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactItemForMode(a, mode){
    const field = artifactFieldForMode(mode);
    return field ? artifactItem((a && a.artifactSummary) || {}, field) : null;
  }
  /**
   * artifactUsableForMode  Provide the artifact usable for mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactUsableForMode(a, mode){
    if(!isArtifactMode(mode)) return true;
    const item = artifactItemForMode(a, mode);
    if(!item) return false;
    const hasFile = !!item.firstFile || arr(item.files).length > 0;
    const hasMaster = !!item.masterFile || arr(item.masterFiles).length > 0;
    if(mode === 'results') return !!item.available || Number(item.nLogicalAvailable || 0) > 0 || Number(item.nAvailable || 0) > 0 || hasFile || hasMaster;
    return !!item.available || Number(item.nLogicalAvailable || 0) > 0 || Number(item.nAvailable || 0) > 0 || hasFile;
  }
  /**
   * combinedArtifactMaskForSelection  Provide the combined artifact mask for selection helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function combinedArtifactMaskForSelection(mode, gridInfo){
    if(manualOverrideActive() || !['preproc','datamat'].includes(mode) || !gridInfo || !gridInfo.visible) return null;
    const cards = selectedAnalyses().map(a => ({index:a.index,gridAct:artifactItemForMode(a,mode).cellAvailableMask}));
    if(!cards.length || cards.some(a => !arr(a.gridAct).length)) return null;
    return window.NMRuntimeGridPicker.commonGrid(cards,gridInfo.ix,gridInfo.jx);
  }
  /**
   * selectedGridMask  Apply the ed grid mask selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedGridMask(gridInfo){
    if(!gridInfo || !gridInfo.visible) return null;
    const G = arr(GRID_ACT).length ? copyGrid(GRID_ACT) : fullGrid(gridInfo.ix, gridInfo.jx);
    return G;
  }

  /**
   * gridMaskOverlapStats  Provide the grid mask overlap stats helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function gridMaskOverlapStats(mask, gridInfo){
    if(!gridInfo || !gridInfo.visible || !mask) return {known:false, selected:0, overlap:0, missing:0};
    const G = selectedGridMask(gridInfo) || fullGrid(gridInfo.ix, gridInfo.jx);
    let selected = 0;
    let overlap = 0;
    for(let i=0;i<G.length;i++){
      for(let j=0;j<arr(G[i]).length;j++){
        if(G[i][j]){
          selected += 1;
          if(mask[i] && mask[i][j]) overlap += 1;
        }
      }
    }
    return {known:true, selected, overlap, missing:Math.max(0, selected - overlap)};
  }

  /**
   * stageCoverageForSelection  Provide the stage coverage for selection helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function stageCoverageForSelection(mode, gridInfo){
    const modeStr = String(mode || '');
    if(!['preproc','datamat'].includes(modeStr) || manualOverrideActive()){
      const selected = gridInfo && gridInfo.visible ? selectedCount(selectedGridMask(gridInfo) || GRID_ACT) : 0;
      return {ok:true, known:false, selected, overlap:selected, missing:0, mask:null, mode:modeStr};
    }
    const mask = combinedArtifactMaskForSelection(modeStr, gridInfo);
    if(mask){
      const st = gridMaskOverlapStats(mask, gridInfo);
      return Object.assign(st, {ok:st.overlap > 0, mask, mode:modeStr});
    }
    const sel = selectedAnalyses();
    const usable = sel.length > 0 && sel.every(a => artifactUsableForMode(a, modeStr));
    const selected = gridInfo && gridInfo.visible ? selectedCount(selectedGridMask(gridInfo) || fullGrid(gridInfo.ix, gridInfo.jx)) : 0;
    return {ok:usable, known:false, selected, overlap:usable ? Math.max(1, selected) : 0, missing:0, mask:null, mode:modeStr};
  }

  /**
   * allAnalysesHaveArtifact  Provide the all analyses have artifact helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function allAnalysesHaveArtifact(mode){
    const sel = selectedAnalyses();
    return sel.length > 0 && sel.every(a => artifactUsableForMode(a, mode));
  }

  /**
   * resolveAutoModeForSelection  Resolve the auto mode for selection value from UI state, payload metadata or defaults.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function resolveAutoModeForSelection(gridInfo){
    const sel = selectedAnalyses();
    if(!sel.length) return {ok:false, mode:'scratch', message:'Select at least one executable analysis.', coverage:null};
    if(allAnalysesHaveArtifact('results')){
      return {ok:true, mode:'results', message:'Ready: Auto will reuse available CVresults artifacts.', coverage:null};
    }
    for(const candidate of ['datamat','preproc']){
      const cov = stageCoverageForSelection(candidate, gridInfo);
      if(cov.ok){
        const label = modeLabel(candidate);
        const msg = cov.known && cov.selected > cov.overlap ?
          `Ready: Auto will start from ${label} for ${cov.overlap}/${cov.selected} selected CV2 partitions with matching artifacts.` :
          `Ready: Auto will start from ${label}.`;
        return {ok:true, mode:candidate, message:msg, coverage:cov};
      }
    }
    const bad = sel.find(a => !scratchAllowed(a));
    if(bad){
      return {ok:false, mode:'scratch', message:stackingSelectionStatus(bad).message, coverage:null};
    }
    return {ok:true, mode:'scratch', message:'Ready: Auto will train from scratch/resume for the selected CV2 partitions.', coverage:null};
  }

  /**
   * resolvedModeForUI  Resolve the d mode for ui value from UI state, payload metadata or defaults.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function resolvedModeForUI(gridInfo){
    const mm = manualMode();
    if(mm && mm !== 'none') return mm;
    const mode = currentMode();
    if(mode === 'auto') return resolveAutoModeForSelection(gridInfo || sameSelectedGrid()).mode;
    return mode;
  }

  /**
   * selectedGridArtifactCoverage  Apply the ed grid artifact coverage selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedGridArtifactCoverage(gridInfo, mode){
    return stageCoverageForSelection(mode, gridInfo);
  }

  /**
   * artifactAvailable  Provide the artifact available helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactAvailable(a, mode){ return artifactUsableForMode(a, mode); }
  /**
   * stackingSelectionStatus  Provide the stacking selection status helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function stackingSelectionStatus(a){
    const S = (a && a.artifactSummary && a.artifactSummary.stacking) || {};
    if(!S.enabled) return {ok:true, message:'Not a stacking analysis.'};
    const mask = arr(S.cellAvailableMask).map(row => arr(row).map(Boolean));
    const gridInfo = sameSelectedGrid();
    if(!mask.length || !mask[0] || !mask[0].length || !gridInfo.visible){
      return {ok: !!S.scratchAvailable, message: S.message || 'Stacking first-tier CVdatamat input completeness could not be determined.'};
    }
    const G = arr(GRID_ACT).length ? arr(GRID_ACT).map(row => arr(row).map(Boolean)) : fullGrid(gridInfo.ix, gridInfo.jx);
    let selected = 0;
    let missing = 0;
    for(let i=0;i<G.length;i++){
      for(let j=0;j<arr(G[i]).length;j++){
        if(G[i][j]){
          selected += 1;
          if(!mask[i] || !mask[i][j]) missing += 1;
        }
      }
    }
    if(selected < 1) return {ok:false, message:'Select at least one CV2 partition for this stacking analysis.'};
    if(missing > 0){
      return {ok:false, message:`Stacking first-tier CVdatamat inputs are missing for ${missing}/${selected} selected CV2 partitions. Select only complete CV2 partitions or generate the missing first-tier CVdatamats first.`};
    }
    return {ok:true, message:`Stacking first-tier CVdatamat inputs are complete for ${selected}/${selected} selected CV2 partitions.`};
  }
  /**
   * scratchAllowed  Return whether the selected analysis has every external scratch prerequisite.
   * Ordinary analyses materialize their stream/preprocessing context in MATLAB and are always eligible.
   * Stacking alone depends on pre-existing first-tier CVdatamats for the selected CV2 cells.
   */
  function scratchAllowed(a){
    return !a || !a.isStackingAnalysis || stackingSelectionStatus(a).ok;
  }
  /**
   * manualOverrideActive  Provide the manual override active helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualOverrideActive(){ return manualMode() !== 'none'; }
  /**
   * hasManualFile  Return whether the has manual file condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function hasManualFile(mode){
    if(mode === 'preproc') return !!(MANUAL_FILES.preprocMasterFile || arr(MANUAL_FILES.preprocDataFiles).length);
    if(mode === 'datamat') return !!(MANUAL_FILES.cvDataMasterFile || arr(MANUAL_FILES.cvDataMatFiles).length);
    if(mode === 'results') return !!(MANUAL_FILES.cvResultsMasterFile || arr(MANUAL_FILES.gdanalmat).length);
    return false;
  }

  /**
   * sameSelectedGrid  Resolve the same selected grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sameSelectedGrid(){
    const sel = selectedAnalyses();
    const mode = effectiveModeForUI();
    if(!sel.length) return {ok:false, visible:false, reason:'Select at least one executable analysis.'};
    if(mode === 'results') return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'CVresults mode reuses the grid stored in the selected CVresults artifacts.'};
    const first = sel[0];
    const ix = Number(first.ix || 0), jx = Number(first.jx || 0);
    if(ix < 1 || jx < 1) return {ok:false, visible:false, reason:'Selected analysis has no valid CV2 TrainInd grid.'};
    const same = sel.every(a => Number(a.ix || 0) === ix && Number(a.jx || 0) === jx);
    if(!same) return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'Selected analyses have different CV2 grid sizes. Each analysis will run all CV2 partitions.'};
    return {ok:true, visible:true, hiddenByLegacyRule:false, ix, jx, reason:'Select the CV2 permutation/fold cells to train.'};
  }

  /**
   * validateModeSelection  Provide the validate mode selection helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function validateModeSelection(){
    const sel = selectedAnalyses();
    if(STATE.artifactsLoading) return {ok:false, message:'Loading artifact availability and ML-runtime feasibility...'};
    if(!sel.length) return {ok:false, message:'Select at least one executable analysis.'};
    if(manualOverrideActive() && sel.length > 1) return {ok:false, message:'Manual artifact override is available for one selected analysis at a time.'};
    const gridInfo = sameSelectedGrid();
    const mode = currentMode();
    const mm = manualMode();
    if(mm !== 'none' && !hasManualFile(mm)) return {ok:false, message:`Pick a ${modeLabel(mm)} artifact file or set manual override to None.`};

    let eff = effectiveModeForUI();
    let message = 'Ready to run ML training.';
    if(mode === 'auto' && !manualOverrideActive()){
      const auto = resolveAutoModeForSelection(gridInfo);
      if(!auto.ok) return {ok:false, message:auto.message};
      eff = auto.mode;
      message = auto.message || message;
    }

    if(eff === 'scratch'){
      const bad = sel.find(a => !scratchAllowed(a));
      if(bad){
        return {ok:false, message:stackingSelectionStatus(bad).message};
      }
    }

    if(['preproc','datamat','results'].includes(eff) && !manualOverrideActive()){
      const bad = sel.find(a => !artifactAvailable(a, eff));
      if(bad) return {ok:false, message:`${modeLabel(eff)} mode requires at least one matching auto-discovered artifact for each selected analysis, or a manual artifact override for one analysis.`};
      const cov = selectedGridArtifactCoverage(gridInfo, eff);
      if(['preproc','datamat'].includes(eff) && gridInfo.visible){
        if(cov.selected < 1) return {ok:false, message:`Select at least one CV2 partition to intersect with available ${modeLabel(eff)} artifacts.`};
        if(cov.known && cov.overlap < 1){
          return {ok:false, message:`The selected CV2 grid has no overlap with auto-discovered ${modeLabel(eff)} artifacts. Select at least one covered cell or choose another input stage.`};
        }
        if(cov.known && cov.missing > 0){
          message = `${message.replace(/\.$/,'')}: ${cov.overlap}/${cov.selected} selected CV2 partitions overlap with available ${modeLabel(eff)} artifacts; non-overlapping cells will be skipped.`;
        }
      }
    }

    if(manualOverrideActive() && ['preproc','datamat'].includes(eff) && gridInfo.visible){
      message = `Ready: selected CV2 partitions will be intersected with the manually selected ${modeLabel(eff)} artifacts where partition indices can be resolved.`;
    }

    const needsOverwrite = sel.some(a => !!a.requiresOverwrite && modeForAnalysis(a, gridInfo) === 'scratch');
    const overwrite = !!(el('overwriteExisting') && el('overwriteExisting').checked);
    if(needsOverwrite && !overwrite) return {ok:false, message:'At least one selected scratch/resume run already contains trained results. Select overwrite to recompute from scratch.'};
    return {ok:true, message};
  }

  /**
   * renderAnalyses  Render the analyses UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderAnalyses(){
    const root = el('analysisList');
    if(!root) return;
    const a = normalizedAnalyses();
    if(window.NMAnalysisCardSelector && typeof window.NMAnalysisCardSelector.create === 'function'){
      const selected = window.NMAnalysisCardSelector.eligibleSelection(a, Array.from(SELECTED));
      SELECTED = new Set(selected);
      if(!ANALYSIS_SELECTOR){
        ANALYSIS_SELECTOR = window.NMAnalysisCardSelector.create(root, a, {
          selected,
          multiSelect:true,
          expandMode:'doubleClick',
          emptyText:analysisEmptyText('No analyses are configured. Create an analysis first.'),
          inspectLabel:'Inspect in Analysis Manager',
          onInspect:(index)=>{ inspectInAnalysisManager(index); },
          onChange:(indices)=>{ SELECTED = new Set(indices.map(Number)); GRID_PICKER = null; renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
        });
      } else {
        ANALYSIS_SELECTOR.update(a, {selected});
      }
      return;
    }
    root.innerHTML = '<div class="amEmptyState">Analysis selector component is not available.</div>';
  }

  /**
   * renderOptions  Render the options UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderOptions(){
    syncManualModeToOperationMode();
    const sel = Array.from(SELECTED.values());
    const summary = el('selectedSummary');
    if(summary) summary.textContent = sel.length ? `${sel.length} analysis/analyses selected` : 'No analysis selected';
    const debug = el('debugOptions');
    if(debug) debug.classList.toggle('hidden', !(STATE.debugOptionsVisible === true));
    renderModeHelp();
    renderArtifactSummary();
    renderManualArtifactSummary();
    const gridInfo = sameSelectedGrid();
    GRID_ACT = reconcileGrid(GRID_ACT, gridInfo, SELECTED);
    const gridSection = el('gridSection');
    const hiddenNote = el('gridHiddenNote');
    const reason = el('gridReason');
    if(gridSection) gridSection.classList.toggle('hidden', !gridInfo.visible);
    if(hiddenNote) hiddenNote.classList.toggle('hidden', !!gridInfo.visible || !gridInfo.hiddenByLegacyRule);
    if(reason) reason.textContent = gridInfo.reason || '';
    if(gridInfo.visible){
      renderGridSummary(gridInfo);
    } else {
      GRID_PICKER = null;
    }
    renderRunState();
  }

  /**
   * renderModeHelp  Render the mode help UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderModeHelp(){
    const help = el('modeHelp');
    const mode = currentMode();
    if(!help) return;
    if(mode === 'auto') help.textContent = 'Auto selects the highest complete input stage from which the selected CV2 grid can be completed. Existing downstream artifacts are reused when overwrite is off; missing downstream artifacts are computed.';
    else if(mode === 'scratch') help.textContent = 'Compute CVdatamat and CVresults from the analysis data. With overwrite off, existing downstream files are reused and only missing selected outputs are generated.';
    else if(mode === 'preproc') help.textContent = 'Start from complete PreprocData input artifacts and complete missing downstream CVdatamat/CVresults while reusing existing outputs when overwrite is off.';
    else if(mode === 'datamat') help.textContent = 'Start from complete CVdatamat input artifacts and complete missing CVresults/aggregation while reusing existing outputs when overwrite is off.';
    else if(mode === 'results') help.textContent = 'Start from existing CVresults and refresh final analysis summaries; the CV2 grid selector is hidden.';
  }

  /**
   * renderArtifactSummary  Render the artifact summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderArtifactSummary(){
    const host = el('artifactSummary');
    if(!host) return;
    const sel = selectedAnalyses();
    if(STATE.artifactsLoading){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Loading artifact availability...</div>'; return; }
    if(!sel.length){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Select one or more analyses to inspect available runtime artifacts.</div>'; return; }
    const rows = [];
    sel.forEach((a)=>{
      const S = a.artifactSummary || {};
      const stack = S.stacking || {};
      if(stack.enabled){
        const children = arr(stack.childInputs);
        if(children.length){
          rows.push(`<tr class="mlrArtifactStackHeader"><td colspan="5">Stacking input CVdatamats for Analysis ${esc(a.index)}</td></tr>`);
          children.forEach((c)=>{
            const txt = c.coverageText || c.message || 'not found';
            const label = `↳ First-tier analysis ${c.analysisIndex || ''}`;
            const title = c.description || c.analysisId || c.message || '';
            rows.push(`<tr class="mlrArtifactChildRow" title="${esc(title)}"><td>${esc(label)}</td><td>Stacking input</td><td>—</td><td>${esc(txt)}</td><td>—</td></tr>`);
          });
        } else if(stack.message){
          rows.push(`<tr class="mlrArtifactChildRow"><td>↳ Stacking input</td><td>Stacking input</td><td>—</td><td>${esc(stack.message)}</td><td>—</td></tr>`);
        }
      }
      const pre = artifactItem(S, 'preprocData');
      const dat = artifactItem(S, 'cvDatamat');
      const res = artifactItem(S, 'cvResults');
      const rec = S.recommended || a.recommendedOperationMode || 'scratch';
      const stackNote = stack.enabled && stack.coverageText ? ` Stacking input: ${stack.coverageText}` : '';
      const title = [stackNote, pre.reason, dat.reason, res.reason].filter(Boolean).join(' | ');
      const role = stack.enabled ? 'Stacking output' : 'Analysis';
      rows.push(`<tr class="mlrArtifactMainRow" title="${esc(title)}"><td>${esc(role)} ${esc(a.index)}</td><td>${esc(autoTrainingStageText(a, S, rec))}</td><td>${esc(artifactStatus(res))}</td><td>${esc(artifactStatus(dat))}</td><td>${esc(artifactStatus(pre))}</td></tr>`);
    });
    host.innerHTML = `<div class="nmRuntimeArtifactTitle">ML training artifact inventory</div>` +
      `<table class="nmRuntimeArtifactTable mlrArtifactTable"><thead><tr><th>Analysis / role</th><th>Input stage</th><th>CVresults coverage</th><th>CVdatamat coverage</th><th>PreprocData coverage</th></tr></thead><tbody>${rows.join('')}</tbody></table>`;
  }


  /**
   * autoTrainingStageText  Build the auto training stage text shown to users in the browser UI.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function autoTrainingStageText(a, S, rec){
    const mode = currentMode();
    const manual = manualMode();
    if(manual && manual !== 'none') return `${modeLabel(manual)} override`;
    if(mode !== 'auto') return modeLabel(mode);
    const res = artifactItem(S, 'cvResults');
    const dat = artifactItem(S, 'cvDatamat');
    const pre = artifactItem(S, 'preprocData');
    if(rec === 'results') return 'CVresults complete';
    if(rec === 'datamat'){
      if(res && res.coverageText && res.coverageText !== 'not found') return 'CVdatamat → complete missing CVresults';
      return 'CVdatamat → compute CVresults';
    }
    if(rec === 'preproc'){
      if(dat && dat.coverageText && dat.coverageText !== 'not found') return 'PreprocData → complete missing CVdatamat/CVresults';
      return 'PreprocData → compute CVdatamat/CVresults';
    }
    if(a && a.isStackingAnalysis) return 'Stacking scratch/resume';
    return 'Scratch/resume';
  }

  /**
   * manualPathsForMode  Provide the manual paths for mode helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualPathsForMode(mode){
    if(mode === 'preproc') return arr(MANUAL_FILES.preprocMasterFile || MANUAL_FILES.preprocDataFiles).filter(Boolean);
    if(mode === 'datamat') return arr(MANUAL_FILES.cvDataMasterFile || MANUAL_FILES.cvDataMatFiles).filter(Boolean);
    if(mode === 'results') return arr(MANUAL_FILES.cvResultsMasterFile || MANUAL_FILES.gdanalmat).filter(Boolean);
    return [];
  }

  /**
   * renderManualArtifactSummary  Render the manual artifact summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderManualArtifactSummary(){
    const mm = syncManualModeToOperationMode();
    const btn = el('pickArtifactFile');
    if(btn) btn.disabled = (mm === 'none');
    const s = el('manualArtifactSummary');
    if(!s) return;
    if(mm === 'none'){
      MANUAL_FILE_LIST = null;
      s.innerHTML = '<div class="nmManualFileList empty"><div class="nmManualFileEmpty">No manual artifact file selected. The runner will use the automatic resolver.</div></div>';
      return;
    }
    const paths = manualPathsForMode(mm);
    const listOpts = {
      paths,
      title: `${modeLabel(mm)} override files`,
      emptyText: `No ${modeLabel(mm)} file selected yet. Use Pick file(s)… to add files.`,
      onChange:(nextPaths)=>{ MANUAL_FILES = artifactFileSpec(mm, nextPaths); renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
    };
    if(window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.create === 'function'){
      if(!MANUAL_FILE_LIST){
        s.innerHTML = '';
        MANUAL_FILE_LIST = window.NMManualArtifactFileList.create(s, listOpts);
      } else {
        MANUAL_FILE_LIST.update(paths, listOpts);
      }
    } else {
      s.textContent = paths.length ? `${modeLabel(mm)} override selected: ${paths.length} file(s).` : `No ${modeLabel(mm)} file selected yet.`;
    }
  }

  /**
   * renderGridSummary  Render the grid summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function executableGrid(gridInfo){
    const mode = resolvedModeForUI(gridInfo);
    const available = combinedArtifactMaskForSelection(mode,gridInfo);
    return window.NMRuntimeGridPicker.permitted(GRID_ACT,gridInfo.ix,gridInfo.jx,available);
  }

  function renderGridSummary(gridInfo){
    const root = el('gridPicker');
    if(!root) return;
    const mode = resolvedModeForUI(gridInfo);
    const cov = selectedGridArtifactCoverage(gridInfo, mode);
    const detail = ['preproc','datamat'].includes(mode) && !manualOverrideActive() && cov.selected > 0
      ? `(${cov.overlap}/${cov.selected} selected partitions overlap with ${modeLabel(mode)})` : '';
    window.NMRuntimeGridPicker.renderSummary(root, {
      ix:gridInfo.ix, jx:gridInfo.jx, selectedCount:selectedCount(executableGrid(gridInfo)),
      detail, buttonId:'editGridButton', onEdit:openGridModal
    });
  }

  /**
   * openGridModal  Open the grid modal panel, dialog or linked UI target.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function openGridModal(){
    const gridInfo = sameSelectedGrid();
    if(!gridInfo.visible || !window.NMModal || !window.NMRuntimeGridPicker) return;
    const available = combinedArtifactMaskForSelection(resolvedModeForUI(gridInfo),gridInfo);
    let working = executableGrid(gridInfo);
    NMModal.open({
      title:'Select CV2 partitions',
      size:'wide',
      render:(bodyEl, modal)=>{
        const host = document.createElement('div');
        bodyEl.appendChild(host);
        GRID_PICKER = window.NMRuntimeGridPicker.create(host, {ix:gridInfo.ix, jx:gridInfo.jx, GridAct:working, enabledMask:available, requireAny:true}, {
          onChange:(G)=>{ working = G; modal.setActionDisabled('Apply', selectedCount(G) < 1); }
        });
      },
      actions:[
        {label:'Cancel', onClick:(m)=>m.close()},
        {label:'Apply', variant:'primary', onClick:(m)=>{ GRID_ACT = working; GRID_PICKER = null; renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); m.close(); }}
      ],
      onClose:()=>{ GRID_PICKER = null; }
    });
  }

  /**
   * renderRunState  Render the run state UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRunState(){
    const btn = el('runMLTraining');
    const genBtn = el('generateRuntimeScript');
    const hint = el('runHint');
    const gridInfo = sameSelectedGrid();
    const modeVal = validateModeSelection();
    let ok = SELECTED.size > 0 && gridInfo.ok && modeVal.ok;
    let msg = modeVal.message;
    if(ok && gridInfo.visible && selectedCount(executableGrid(gridInfo)) < 1){ ok = false; msg = 'Select at least one available CV2 partition.'; }
    if(ok && gridInfo.hiddenByLegacyRule) msg = gridInfo.reason;
    if(RUNTIME_JOB_ACTIVE){ ok = false; msg = 'ML training is running in MATLAB.'; }
    if(btn) btn.disabled = !ok;
    if(genBtn) genBtn.disabled = !ok;
    const finish = el('finish'); if(finish) finish.disabled = RUNTIME_JOB_ACTIVE;
    if(hint) hint.textContent = RUNTIME_JOB_ACTIVE ? 'ML training is running in MATLAB. Close the browser tab to detach safely.' : msg;
  }

  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');  renderAnalyses(); renderOptions(); if(window.NMModuleNavigationRail && typeof window.NMModuleNavigationRail.refresh === 'function') window.NMModuleNavigationRail.refresh(); }

  /**
   * currentPlan  Provide the current plan helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentPlan(){
    const gridInfo = sameSelectedGrid();
    return {
      analysisIndices:Array.from(SELECTED.values()),
      options:{
        operationMode:currentMode(),
        manualArtifactMode:manualMode(),
        manualFiles:MANUAL_FILES,
        overwrite:!!(el('overwriteExisting') && el('overwriteExisting').checked),
        update:!!(el('updateExisting') && el('updateExisting').checked),
        debugall:!!(el('debugAll') && el('debugAll').checked),
        debugopt:!!(el('debugOpt') && el('debugOpt').checked)
      },
      gridVisible:!!gridInfo.visible,
      gridHiddenByLegacyRule:!!gridInfo.hiddenByLegacyRule,
      GridAct:gridInfo.visible ? executableGrid(gridInfo) : []
    };
  }

  /**
   * refreshLight  Refresh the light page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refreshLight(){
    try{
      const res = await matlabService({operation:'ml_train_runner_refresh_light', timeout:120});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Analysis-list refresh failed.');
      if(res.state){ STATE = res.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; }
      render();
    } catch(err){ setMsg(`Analysis-list refresh failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(){
    try{
      const res = await matlabService({operation:'ml_train_runner_refresh', timeout:120});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Refresh failed.');
      if(res.state){ STATE = res.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; }
      render();
    } catch(err){ setMsg(`Refresh failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * shouldOpenRuntimeProgress  Provide the should open runtime progress helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   * plan.analysisIndices: one-based analysis indices selected in a runner page.
   */
  function shouldOpenRuntimeProgress(plan){
    const mode = resolvedModeForUI(sameSelectedGrid());
    if(mode === 'results') return false;
    return arr(plan && plan.analysisIndices).length > 0;
  }

  /**
   * runTraining  Provide the run training helper used by machine-learning optimization runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function applyTrainingJobResult(res, selectionBeforeRun){
    if(!res || res.ok === false){
      hideRuntimeProgressPanel();
      throw new Error((res && (res.message || res.error)) || 'ML training failed.');
    }
    if(res.state){
      STATE = res.state;
      if(selectionBeforeRun && selectionBeforeRun.length) preserveSelectionAfterStateUpdate(selectionBeforeRun);
      else SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite));
      ANALYSIS_SELECTOR = null;
      GRID_PICKER = null;
    }
    render();
    scheduleRuntimeProgressAutoClose(450);
  }

  async function runTraining(){
    let progressTaskId = '';
    const selectionBeforeRun = Array.from(SELECTED.values());
    const client = runtimeJobClient();
    if(!client){ setMsg('The durable MATLAB runtime-job client is unavailable.', 'danger'); return; }
    try{
      const plan = currentPlan();
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      const useProgressViewer = shouldOpenRuntimeProgress(plan);
      if(useProgressViewer){
        progressTaskId = createProgressTaskId('mltrain');
        showRuntimeProgressPanel(progressTaskId);
      }
      RUNTIME_JOB_ACTIVE = true;
      renderRunState();
      const servicePayload = {operation:'ml_train_runner_run', plan, progressChartMinIntervalSeconds:RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS};
      if(progressTaskId) servicePayload.progressTaskId = progressTaskId;
      const options = {
        progressTaskId,
      };
      if(progressTaskId) options.jobId = progressTaskId;
      const res = await client.run(servicePayload, options);
      await applyTrainingJobResult(res, selectionBeforeRun);
    } catch(err){
      setMsg(`ML training failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
  }

  async function resumeRuntimeJobIfPresent(){
    const client = runtimeJobClient();
    if(!client) return false;
    const pending = await client.find('ml_train_runner_run');
    if(!pending || !pending.jobId) return false;
    const progressTaskId = String(pending.progressTaskId || '');
    if(progressTaskId) showRuntimeProgressPanel(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const res = await client.wait(pending.jobId);
      await applyTrainingJobResult(res, null);
    } catch(err){
      setMsg(`ML training failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
    return true;
  }

  /**
   * generateScript  Provide the generate script helper used by machine-learning optimization runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function generateScript(){
    try{
      const plan = currentPlan();
      const res = await matlabService({operation:'ml_train_runner_generate_script', plan, timeout:300});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Script generation failed.');
      const scripts = arr(res.scripts).map(s => s.path).join('; ');
      setMsg((res.message || 'Runtime script generated.') + (scripts ? ` ${scripts}` : ''), 'ok');
    } catch(err){ setMsg(`Script generation failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * cleanDataId  Resolve the clean data id identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function cleanDataId(id){
    return String(id == null ? '' : id).trim().replace(/^ID/i, '');
  }

  /**
   * artifactPickerFilter  Provide the artifact picker filter helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactPickerFilter(mode, analysis){
    const summary = (analysis && analysis.artifactSummary) || {};
    const id = cleanDataId(summary.dataId || analysis.id || '');
    /**
     * patterns  Provide the patterns helper used by machine-learning optimization runner page.
     * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function patterns(names){
      const out = [];
      names.forEach(name => {
        if(id){
          out.push(`*${name}*ID${id}*.mat`, `*${name}*_ID${id}*.mat`, `*${name}*${id}*.mat`);
        }
        out.push(`*${name}*.mat`);
      });
      out.push('*.mat');
      return Array.from(new Set(out.filter(Boolean)));
    }
    if(mode === 'preproc') return patterns(['PreprocMaster','PreprocData']).join(';');
    if(mode === 'datamat') return patterns(['CVdataMaster','CVdatamat']).join(';');
    if(mode === 'results') return patterns(['CVresultsMaster','CVresults']).join(';');
    return '*.mat';
  }

  /**
   * artifactPickerTitle  Provide the artifact picker title helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactPickerTitle(mode, analysis){
    const summary = (analysis && analysis.artifactSummary) || {};
    const id = cleanDataId(summary.dataId || analysis.id || '');
    const base = mode === 'preproc' ? 'Select PreprocMaster or CV2 PreprocData artifacts' : (mode === 'datamat' ? 'Select CVdataMaster or CV2 CVdatamats' : 'Select CVresultsMaster or CVresults artifacts');
    return id ? `${base} for ID${id}` : base;
  }

  /**
   * artifactFileSpec  Provide the artifact file spec helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactFileSpec(mode, paths){
    const files = arr(paths).filter(Boolean);
    const spec = {};
    if(!files.length) return spec;
    const firstName = String(files[0]).split(/[\/]/).pop();
    if(mode === 'preproc'){
      if(files.length === 1 && /PreprocMaster/i.test(firstName)) spec.preprocMasterFile = files[0];
      else spec.preprocDataFiles = files;
    } else if(mode === 'datamat'){
      if(files.length === 1 && /CVdataMaster/i.test(firstName)) spec.cvDataMasterFile = files[0];
      else spec.cvDataMatFiles = files;
    } else if(mode === 'results'){
      if(files.length === 1 && /CVresultsMaster/i.test(firstName)) spec.cvResultsMasterFile = files[0];
      else spec.gdanalmat = files;
    }
    return spec;
  }

  /**
   * dirname  Provide the dirname helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function dirname(path){
    const txt = String(path == null ? '' : path);
    const idx = Math.max(txt.lastIndexOf('/'), txt.lastIndexOf('\\'));
    return idx > 0 ? txt.slice(0, idx) : '';
  }

  /**
   * artifactPickerInitialDir  Provide the artifact picker initial dir helper used by machine-learning optimization runner page.
   * It supports machine-learning optimization runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactPickerInitialDir(mode, analysis){
    const S = (analysis && analysis.artifactSummary) || {};
    const item = mode === 'preproc' ? artifactItem(S, 'preprocData') : (mode === 'datamat' ? artifactItem(S, 'cvDatamat') : artifactItem(S, 'cvResults'));
    const fromFile = dirname(item.masterFile || item.firstFile || '');
    if(fromFile) return fromFile;
    if(mode === 'preproc') return S.preprocRootdir || S.rootdir || analysis.rootdir || '';
    if(mode === 'datamat') return S.cvDataRootdir || S.algorithmRootdir || S.rootdir || analysis.rootdir || '';
    if(mode === 'results') return S.cvResultsRootdir || S.algorithmRootdir || S.rootdir || analysis.rootdir || '';
    return S.rootdir || analysis.rootdir || '';
  }

  /**
   * pickArtifact  Provide the pick artifact helper used by machine-learning optimization runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function pickArtifact(){
    syncManualModeToOperationMode();
    const mm = manualMode();
    if(mm === 'none') return;
    const sel = selectedAnalyses();
    if(sel.length !== 1){ setMsg('Manual artifact override is available for one selected analysis at a time.', 'warn'); return; }
    try{
      const a = sel[0];
      const initial = artifactPickerInitialDir(mm, a);
      const filter = artifactPickerFilter(mm, a);
      const title = artifactPickerTitle(mm, a);
      const res = await postJson('/api/pickpath', {kind:'file', multiple:true, initial, filter, title, timeout:600});
      const picked = arr(res && (res.paths || res.files || res.path || res.file)).filter(Boolean);
      if(!picked.length) return;
      const current = manualPathsForMode(mm);
      const paths = window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.uniquePaths === 'function' ?
        window.NMManualArtifactFileList.uniquePaths(current.concat(picked)) : current.concat(picked);
      MANUAL_FILES = artifactFileSpec(mm, paths);
      renderOptions();
      if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged();
    } catch(err){ setMsg(`File selection failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * inspectInAnalysisManager  Provide the inspect in analysis manager helper used by machine-learning optimization runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function inspectInAnalysisManager(index){
    try{
      const res = await matlabService({operation:'app_prepare_page', page:'analysis_manager', timeout:240});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Could not prepare Analysis Manager.');
      const target = res.entryHtml || 'nm_analysis_manager.html';
      const sep = target.includes('?') ? '&' : '?';
      window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`${target}${sep}port=${encodeURIComponent(PORT)}&analysis=${encodeURIComponent(index)}&_nmcb=${Date.now()}`) : `${target}${sep}port=${encodeURIComponent(PORT)}&analysis=${encodeURIComponent(index)}&_nmcb=${Date.now()}`);
    } catch(err){ setMsg(`Cannot open Analysis Manager: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * finish  Provide the finish helper used by machine-learning optimization runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){ setMsg('ML training is still running in MATLAB. Close this browser tab to detach; do not finish the bridge session.', 'warn'); return; }
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      if(isWorkbenchChild()){
        const res = await matlabService({operation:'app_child_return', source:'ml_train_runner', timeout:120});
        if(res && res.ok !== false){
          const target = (appContext().returnPage || 'nm_workbench.html');
          const sep = target.includes('?') ? '&' : '?';
          window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`) : `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`);
          return;
        }
      }
      await postJson('/api/close', {closed:true, source:'ml_train_runner'});
      document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">ML training runner state saved. You can close this tab.</p>';
    } catch(err){ setMsg(`ERROR while closing: ${err.message || String(err)}`, 'danger'); }
  }

  function installRunnerStateAdapter(){
    if(!window.NMRunnerStateManager) return;
    window.NMRunnerStateManager.registerAdapter({
      key:'ml_train_runner',
      snapshot:()=>{ const p=currentPlan(); return {analysisIndices:p.analysisIndices, options:p.options, GridAct:GRID_ACT}; },
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object') return;
        const available=new Set(analyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        SELECTED=new Set(arr(saved.analysisIndices).map(Number).filter(i=>available.has(i)));
        if(Array.isArray(saved.GridAct)) GRID_ACT=saved.GridAct;
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        const mode=el('operationMode');
        if(mode&&typeof o.operationMode==='string'&&Array.from(mode.options).some(x=>x.value===o.operationMode)) mode.value=o.operationMode;
        updateManualModeDropdown();
        const manual=el('manualArtifactMode');
        if(manual&&typeof o.manualArtifactMode==='string'&&Array.from(manual.options).some(x=>x.value===o.manualArtifactMode)) manual.value=o.manualArtifactMode;
        MANUAL_FILES=o.manualFiles&&typeof o.manualFiles==='object'?o.manualFiles:{};
        LAST_MANUAL_MODE=manualMode();
        if(typeof o.overwrite==='boolean'&&el('overwriteExisting')) el('overwriteExisting').checked=o.overwrite;
        if(typeof o.update==='boolean'&&el('updateExisting')) el('updateExisting').checked=o.update;
        if(typeof o.debugall==='boolean'&&el('debugAll')) el('debugAll').checked=o.debugall;
        if(typeof o.debugopt==='boolean'&&el('debugOpt')) el('debugOpt').checked=o.debugopt;
        ANALYSIS_SELECTOR=null; GRID_PICKER=null; MANUAL_FILE_LIST=null; render();
      },
      report:(message)=>setMsg(message,'danger')
    });
  }
  installRunnerStateAdapter();
  document.addEventListener('DOMContentLoaded', () => {
    const f = el('finish'); if(f) f.onclick = finish;
    const run = el('runMLTraining'); if(run) run.onclick = runTraining;
    const gen = el('generateRuntimeScript'); if(gen) gen.onclick = generateScript;
    const mode = el('operationMode'); if(mode) mode.onchange = () => { GRID_PICKER = null; syncManualModeToOperationMode(); renderOptions(); };
    const manual = el('manualArtifactMode'); if(manual) manual.onchange = () => { const mm = manualMode(); if(mm !== LAST_MANUAL_MODE){ clearManualFiles(); LAST_MANUAL_MODE = mm; } renderOptions(); };
    const pick = el('pickArtifactFile'); if(pick) pick.onclick = pickArtifact;
    ['overwriteExisting','updateExisting','debugAll','debugOpt'].forEach(id => { const x = el(id); if(x) x.onchange = renderOptions; });
    render();
    (async()=>{
      const resumed = await resumeRuntimeJobIfPresent();
      if(resumed) return;
      // Workbench child pages may be exported with a lightweight bootstrap state.
      // Load the cheap analysis list first, then resolve slower artifact/runtime state.
      if(STATE.loading || STATE.analysesLoading){
        await refreshLight();
        await refresh();
      } else if(appContext().fastChildOpen){
        await refresh();
      }
    })().then(()=>window.NMRunnerStateManager?window.NMRunnerStateManager.markReady():undefined).catch(err=>setMsg(`ML training runner refresh failed: ${err.message || String(err)}`, 'danger'));
  });
})();
