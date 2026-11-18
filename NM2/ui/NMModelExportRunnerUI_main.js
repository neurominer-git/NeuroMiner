(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_MODEL_EXPORT_RUNNER_STATE || {};
  let SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite));
  let GRID_ACT = (STATE.grid && STATE.grid.GridAct) || [];
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler(SELECTED);
  let SELECTION_LOADED = !(STATE.loading || STATE.analysesLoading);
  let GRID_PICKER = null;
  let ANALYSIS_SELECTOR = null;
  let RUNTIME_PROGRESS_VIEWER = null;
  let RUNTIME_JOB_CLIENT = null;
  let RUNTIME_JOB_ACTIVE = false;
  const RUNTIME_PROGRESS_POLL_MS = 80;
  const RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS = 0.15;

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
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function appContext(){ return (STATE && STATE.appContext) || {}; }
  /**
   * isWorkbenchChild  Return whether the is workbench child condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isWorkbenchChild(){ return String(appContext().caller || '').toLowerCase() === 'workbench'; }
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
    return obj;
  }
  /**
   * matlabService  Send a MATLAB-service request through the browser bridge.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function matlabService(payload){ return postJson('/api/matlabservice', payload); }
  /** Return the shared durable MATLAB-job client for model-export execution. */
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT, storageKey:`nm2_model_export_runtime_job_${PORT}`, pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }
  /**
   * createRuntimeProgressTaskId  Create the runtime progress task id component or browser-side state object.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createRuntimeProgressTaskId(prefix){
    if(window.NMRuntimeProgressViewer && typeof window.NMRuntimeProgressViewer.createTaskId === 'function'){
      return window.NMRuntimeProgressViewer.createTaskId(prefix || 'model_export');
    }
    return `${prefix || 'model_export'}_${Date.now()}_${Math.random().toString(36).slice(2,9)}`.replace(/[^A-Za-z0-9_-]/g, '');
  }
  /**
   * runtimeProgressViewer  Provide the runtime progress viewer helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeProgressViewer(){
    if(!RUNTIME_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      RUNTIME_PROGRESS_VIEWER = new window.NMRuntimeProgressViewer({port:PORT, title:'Model export progress', lowerTitle:'Model export progress', pollMs:RUNTIME_PROGRESS_POLL_MS});
    }
    return RUNTIME_PROGRESS_VIEWER;
  }
  /**
   * showRuntimeProgress  Provide the show runtime progress helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function showRuntimeProgress(taskId){ const viewer = runtimeProgressViewer(); if(viewer) viewer.open(taskId, 'Running model export in MATLAB...'); }
  /**
   * finishRuntimeProgress  Provide the finish runtime progress helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function finishRuntimeProgress(){ const viewer = runtimeProgressViewer(); if(viewer) viewer.scheduleAutoClose(550); }
  /**
   * setMsg  Route a status message to the page message strip.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * serviceMessage  Provide the service message helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceMessage(out, fallback){
    return (out && out.strip && out.strip.text) || (out && (out.message || out.error)) || fallback || 'Operation failed.';
  }
  /**
   * serviceSeverity  Provide the service severity helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceSeverity(out, fallback){
    return (out && out.strip && out.strip.severity) || fallback || ((out && out.ok) ? 'ok' : 'danger');
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
   * analyses  Provide the analyses helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analyses(){ return normalizedAnalyses(); }
  /**
   * selectedAnalyses  Apply the ed analyses selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedAnalyses(){ return analyses().filter(a => a.enabled && SELECTED.has(Number(a.index))); }
  /**
   * isLoadingState  Return whether the is loading state condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLoadingState(){ return !!(STATE.loading || STATE.analysesLoading || STATE.artifactsLoading); }
  /**
   * analysisEmptyText  Build the analysis empty text shown to users in the browser UI.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisEmptyText(finalText){ return isLoadingState() ? 'Loading analyses...' : finalText; }
  /**
   * selectedCount  Apply the ed count selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedCount(G){ return arr(G).reduce((acc,row) => acc + arr(row).filter(Boolean).length, 0); }
  /**
   * fullGrid  Resolve the full grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function fullGrid(ix,jx){ return Array.from({length:ix}, () => Array.from({length:jx}, () => true)); }

  /**
   * renderStatus  Render the status UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderStatus(){
    const s = el('modelExportStatus');
    if(s){
      const total = analyses().length;
      const runn = analyses().filter(a => !!a.enabled).length;
      s.innerHTML = `<span>Analyses: ${runn}/${total} trained</span><span>Mode: model export</span>`;
    }
  }

  /**
   * renderAnalyses  Render the analyses UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderAnalyses(){
    const root = el('analysisList'); if(!root) return;
    const a = analyses();
    if(window.NMAnalysisCardSelector && typeof window.NMAnalysisCardSelector.create === 'function'){
      const selected = window.NMAnalysisCardSelector.eligibleSelection(a, Array.from(SELECTED));
      SELECTED = new Set(selected);
      if(!ANALYSIS_SELECTOR){
        ANALYSIS_SELECTOR = window.NMAnalysisCardSelector.create(root, a, {
          selected,
          multiSelect:true,
          expandMode:'doubleClick',
          emptyText:analysisEmptyText('No analyses are configured. Create and train an analysis first.'),
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
   * sameSelectedGrid  Resolve the same selected grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sameSelectedGrid(){
    const sel = selectedAnalyses();
    if(!sel.length) return {ok:false, visible:false, reason:'Select at least one trained analysis.'};
    const first = sel[0]; const ix = Number(first.ix || 0), jx = Number(first.jx || 0);
    if(ix < 1 || jx < 1) return {ok:false, visible:false, reason:'Selected analysis has no valid CV2 grid.'};
    const same = sel.every(a => Number(a.ix || 0) === ix && Number(a.jx || 0) === jx);
    if(!same) return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'Selected analyses have different CV2 grid sizes. Each analysis will use its trained CV2 partitions.'};
    const G = window.NMRuntimeGridPicker.commonGrid(sel, ix, jx);
    return {ok:true, visible:true, hiddenByLegacyRule:false, ix, jx, reason:'Select trained CV2 partitions to export.', GridAct:G};
  }

  /**
   * artifactSummaryForIndex  Provide the artifact summary for index helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactSummaryForIndex(index){
    const s = arr(STATE.artifactSummary).find(x => Number(x.analysisIndex) === Number(index));
    if(s) return s;
    const a = analyses().find(x => Number(x.index) === Number(index));
    return (a && a.artifactSummary) || {};
  }

  /**
   * renderArtifactSummary  Render the artifact summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderArtifactSummary(){
    const host = el('artifactSummary'); if(!host) return;
    const sel = selectedAnalyses();
    if(STATE.artifactsLoading){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Loading export artifact availability...</div>'; return; }
    if(!sel.length){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Select trained analyses to inspect existing exported artifacts.</div>'; return; }
    const rows = sel.map(a => {
      const S = artifactSummaryForIndex(a.index);
      const expected = Number.isFinite(Number(S.nExpected)) ? Number(S.nExpected) : 0;
      const modelText = expected > 0 ? `${Number(S.nOptModelFiles || 0)}/${expected} CV2 partitions` : `${Number(S.nOptModelFiles || 0)} file(s)`;
      const preprocText = expected > 0 ? `${Number(S.nOptPreprocFiles || 0)}/${expected} CV2 partitions` : `${Number(S.nOptPreprocFiles || 0)} file(s)`;
      return `<tr title="${esc(S.message || '')}"><td>Analysis ${esc(a.index)}</td><td>${esc(modelText)}</td><td>${esc(preprocText)}</td><td class="nmRuntimeArtifactPath">${esc(S.exportDir || '')}</td></tr>`;
    });
    host.innerHTML = '<div class="nmRuntimeArtifactTitle">Model export artifact inventory</div>' +
      `<table class="nmRuntimeArtifactTable modelExportArtifactTable"><thead><tr><th>Analysis</th><th>OptModel coverage</th><th>OptPreproc coverage</th><th>Output directory</th></tr></thead><tbody>${rows.join('')}</tbody></table>`;
  }

  /**
   * renderDynamicControls  Render the dynamic controls UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderDynamicControls(){
    const saveCV1Row = el('saveCV1Row');
    if(saveCV1Row) saveCV1Row.classList.toggle('hidden', !(el('exportOptPreproc') && el('exportOptPreproc').checked));
  }

  /**
   * renderGridSummary  Render the grid summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderGridSummary(gridInfo){
    const host = el('gridPicker'); if(!host || !gridInfo.visible) return;
    window.NMRuntimeGridPicker.renderSummary(host, {
      ix:gridInfo.ix, jx:gridInfo.jx,
      selectedCount:selectedCount(GRID_ACT),
      buttonId:'editGrid', onEdit:()=>openGridModal(gridInfo)
    });
  }

  /**
   * openGridModal  Open the grid modal panel, dialog or linked UI target.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function openGridModal(gridInfo){
    if(!window.NMModal || !window.NMRuntimeGridPicker){ setMsg('Grid picker components are not available.', 'error'); return; }
    let working = GRID_ACT || gridInfo.GridAct || fullGrid(gridInfo.ix, gridInfo.jx);
    window.NMModal.open({
      title:'Select CV2 partitions',
      className:'modelExportGridModal',
      render:(bodyEl)=>{
        const host = document.createElement('div');
        bodyEl.appendChild(host);
        GRID_PICKER = window.NMRuntimeGridPicker.create(host, {ix:gridInfo.ix, jx:gridInfo.jx, GridAct:working, requireAny:true}, {onChange:(G)=>{ working = G; }});
      },
      actions:[
        {label:'Cancel', onClick:(m)=>m.close()},
        {label:'Apply', variant:'primary', onClick:(m)=>{ GRID_ACT = working; GRID_PICKER = null; renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); m.close(); }}
      ],
      onClose:()=>{ GRID_PICKER = null; }
    });
  }

  /**
   * validateRunState  Provide the validate run state helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function validateRunState(){
    const sel = selectedAnalyses();
    if(STATE.artifactsLoading) return {ok:false, message:'Loading export artifact availability...'};
    if(!sel.length) return {ok:false, message:'Select at least one trained analysis.'};
    const grid = sameSelectedGrid();
    if(grid.visible && !selectedCount(GRID_ACT)) return {ok:false, message:'Select at least one CV2 partition.'};
    const exportModel = !!(el('exportOptModel') && el('exportOptModel').checked);
    const exportPreproc = !!(el('exportOptPreproc') && el('exportOptPreproc').checked);
    if(!exportModel && !exportPreproc) return {ok:false, message:'Select optimized ML models, optimized preprocessing parameters, or both.'};
    return {ok:true, message:'Ready to export trained model artifacts.'};
  }

  /**
   * renderRunState  Render the run state UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRunState(){
    const hint = el('runHint'); const run = el('runModelExport'); const gen = el('generateRuntimeScript');
    const v = validateRunState();
    const running = RUNTIME_JOB_ACTIVE;
    if(run) run.disabled = !v.ok || running;
    if(gen) gen.disabled = !v.ok || running;
    const finish = el('finish'); if(finish) finish.disabled = running;
    if(hint) hint.textContent = running ? 'Model export is running in MATLAB. Close the browser tab to detach safely.' : v.message;
  }

  /**
   * renderOptions  Render the options UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderOptions(){
    const summary = el('selectedSummary'); if(summary) summary.textContent = SELECTED.size ? `${SELECTED.size} analysis/analyses selected` : 'No analysis selected';
    renderArtifactSummary(); renderDynamicControls();
    const gridInfo = sameSelectedGrid();
    GRID_ACT = reconcileGrid(GRID_ACT, gridInfo, SELECTED);
    const gridSection = el('gridSection'); const hiddenNote = el('gridHiddenNote'); const reason = el('gridReason');
    if(gridSection) gridSection.classList.toggle('hidden', !gridInfo.visible);
    if(hiddenNote){
      hiddenNote.classList.toggle('hidden', !!gridInfo.visible || !gridInfo.hiddenByLegacyRule);
      const help = hiddenNote.querySelector('.help');
      if(help) help.textContent = gridInfo.reason || 'Each selected analysis will use its trained CV2 partitions.';
    }
    if(reason) reason.textContent = gridInfo.reason || '';
    if(gridInfo.visible){
      renderGridSummary(gridInfo);
    }
    renderRunState();
  }

  /**
   * collectOptions  Collect options values into a request or rendering model.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectOptions(){
    return {
      exportOptModel: !!(el('exportOptModel') && el('exportOptModel').checked),
      exportOptPreproc: !!(el('exportOptPreproc') && el('exportOptPreproc').checked),
      overwrite: !!(el('overwriteExisting') && el('overwriteExisting').checked),
      saveCV1: !!(el('saveCV1') && el('saveCV1').checked)
    };
  }

  /**
   * collectPlan  Collect plan values into a request or rendering model.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectPlan(){
    const gridInfo = sameSelectedGrid();
    return {analysisIndices:Array.from(SELECTED.values()), gridAction:GRID_ACT, gridVisible:!!gridInfo.visible, gridHiddenByLegacyRule:!!gridInfo.hiddenByLegacyRule, options:collectOptions()};
  }

  /**
   * runModelExport  Provide the run model export helper used by model-export runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function applyModelExportJobResult(out){
    if(out && out.ok){
      if(out.state){ STATE = out.state; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
      setMsg(out.message || 'Model export completed.', 'success');
      finishRuntimeProgress();
      return;
    }
    if(RUNTIME_PROGRESS_VIEWER) RUNTIME_PROGRESS_VIEWER.hide();
    throw new Error(serviceMessage(out, 'Running model export failed.'));
  }

  async function runModelExport(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const client = runtimeJobClient();
    if(!client){ setMsg('The durable MATLAB runtime-job client is unavailable.', 'danger'); return; }
    try{ if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow(); }
    catch(err){ setMsg(`Model export cannot start because its runner setup could not be saved: ${err.message || String(err)}`, 'danger'); return; }
    const progressTaskId = createRuntimeProgressTaskId('model_export');
    showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const servicePayload = {operation:'model_export_runner_run', plan:collectPlan(), progressTaskId, progressChartMinIntervalSeconds:RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS};
      const out = await client.run(servicePayload, {jobId:progressTaskId, progressTaskId});
      await applyModelExportJobResult(out);
    } catch(err){
      setMsg(`Running model export failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
  }

  async function resumeRuntimeJobIfPresent(){
    const client = runtimeJobClient();
    if(!client) return false;
    const pending = await client.find('model_export_runner_run');
    if(!pending || !pending.jobId) return false;
    const progressTaskId = String(pending.progressTaskId || '');
    if(progressTaskId) showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const out = await client.wait(pending.jobId);
      await applyModelExportJobResult(out);
    } catch(err){
      setMsg(`Running model export failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
    return true;
  }

  /**
   * generateRuntimeScript  Provide the generate runtime script helper used by model-export runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function generateRuntimeScript(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const out = await matlabService({operation:'model_export_runner_generate_script', plan:collectPlan(), timeout:120});
    if(out && out.ok) setMsg(out.message || 'Model-export runtime script generated.', 'success');
    else setMsg(serviceMessage(out, 'Generating the runtime script failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * refreshLight  Refresh the light page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refreshLight(){
    const out = await matlabService({operation:'model_export_runner_refresh_light'});
    if(out && out.ok && out.state){ STATE = out.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
    else setMsg(serviceMessage(out, 'Analysis-list refresh failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(){
    const out = await matlabService({operation:'model_export_runner_refresh'});
    if(out && out.ok && out.state){ STATE = out.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
    else setMsg(serviceMessage(out, 'Refresh failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * workbenchReturnUrl  Provide the workbench return url helper used by model-export runtime runner page.
   * It supports model-export runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workbenchReturnUrl(){
    const target = appContext().returnPage || 'nm_workbench.html';
    const sep = target.includes('?') ? '&' : '?';
    return `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`;
  }

  /**
   * finish  Provide the finish helper used by model-export runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){ setMsg('Model export is still running in MATLAB. Close this browser tab to detach; do not finish the bridge session.', 'warning'); return; }
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      if(isWorkbenchChild()){
        const out = await matlabService({operation:'app_child_return', source:'model_export_runner', timeout:120});
        if(out && out.ok){ window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(workbenchReturnUrl()) : workbenchReturnUrl()); return; }
        throw new Error((out && (out.message || out.error)) || 'Returning to the workbench failed.');
      }
      await postJson('/api/close', {source:'model_export_runner'});
      document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">Model export runner state saved. You can close this tab.</p>';
    } catch(err){ setMsg(`ERROR while closing model export runner: ${err.message || String(err)}`, 'error'); }
  }

  /**
   * inspectInAnalysisManager  Provide the inspect in analysis manager helper used by model-export runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function inspectInAnalysisManager(index){
    if(!isWorkbenchChild()){ setMsg('Open the Analysis Manager from the workbench to inspect this analysis.', 'info'); return; }
    const out = await matlabService({operation:'app_prepare_page', page:'analysis_manager', targetAnalysisIndex:index, timeout:240});
    if(out && out.ok && out.entryHtml){ window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`${out.entryHtml}?port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}&analysis=${encodeURIComponent(index)}`) : `${out.entryHtml}?port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}&analysis=${encodeURIComponent(index)}`); }
    else setMsg(serviceMessage(out, 'Could not open Analysis Manager.'), serviceSeverity(out, 'danger'));
  }

  /**
   * bind  Register event handlers for the bind controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function bind(){
    const f = el('finish'); if(f) f.addEventListener('click', () => finish().catch(e => setMsg(e.message,'error')));
    ['exportOptModel','exportOptPreproc','overwriteExisting','saveCV1'].forEach(id => { const x=el(id); if(x) x.addEventListener('change', renderOptions); });
    const run = el('runModelExport'); if(run) run.addEventListener('click', () => runModelExport().catch(e => setMsg(e.message,'error')));
    const gen = el('generateRuntimeScript'); if(gen) gen.addEventListener('click', () => generateRuntimeScript().catch(e => setMsg(e.message,'error')));
  }
  /**
   * renderAll  Render the all UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderAll(){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close'); renderStatus(); renderAnalyses(); renderOptions(); if(window.NMModuleNavigationRail && typeof window.NMModuleNavigationRail.refresh === 'function') window.NMModuleNavigationRail.refresh(); }
  function installRunnerStateAdapter(){
    if(!window.NMRunnerStateManager) return;
    window.NMRunnerStateManager.registerAdapter({
      key:'model_export_runner',
      snapshot:()=>{ const p=collectPlan(); return {analysisIndices:p.analysisIndices, gridAction:p.gridAction, options:p.options}; },
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object') return;
        const available=new Set(analyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        SELECTED=new Set(arr(saved.analysisIndices).map(Number).filter(i=>available.has(i)));
        if(Array.isArray(saved.gridAction)) GRID_ACT=saved.gridAction;
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        if(typeof o.exportOptModel==='boolean'&&el('exportOptModel')) el('exportOptModel').checked=o.exportOptModel;
        if(typeof o.exportOptPreproc==='boolean'&&el('exportOptPreproc')) el('exportOptPreproc').checked=o.exportOptPreproc;
        if(typeof o.overwrite==='boolean'&&el('overwriteExisting')) el('overwriteExisting').checked=o.overwrite;
        if(typeof o.saveCV1==='boolean'&&el('saveCV1')) el('saveCV1').checked=o.saveCV1;
        ANALYSIS_SELECTOR=null; GRID_PICKER=null; renderAll();
      },
      report:(message)=>setMsg(message,'error')
    });
  }
  installRunnerStateAdapter();
  document.addEventListener('DOMContentLoaded', () => {
    bind();
    renderAll();
    (async()=>{
      const resumed = await resumeRuntimeJobIfPresent();
      if(resumed) return;
      if(STATE.loading || STATE.analysesLoading){
        await refreshLight();
        await refresh();
      } else if(appContext().fastChildOpen){
        await refresh();
      }
    })().then(()=>window.NMRunnerStateManager?window.NMRunnerStateManager.markReady():undefined).catch(err=>setMsg(`Model export runner refresh failed: ${err.message || String(err)}`, 'error'));
  });
})();
