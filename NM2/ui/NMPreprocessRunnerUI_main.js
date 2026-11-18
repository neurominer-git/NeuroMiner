(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_PREPROCESS_RUNNER_STATE || {};
  let SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number));
  let GRID_PICKER = null;
  let ANALYSIS_SELECTOR = null;
  let GRID_ACT = (STATE.grid && STATE.grid.GridAct) || [];
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler(SELECTED);
  let SELECTION_LOADED = !(STATE.loading || STATE.analysesLoading);
  let PREPROCESS_PROGRESS_VIEWER = null;
  let RUNTIME_JOB_CLIENT = null;
  let RUNTIME_JOB_ACTIVE = false;

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
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function appContext(){ return (STATE && STATE.appContext) || {}; }
  /**
   * isWorkbenchChild  Return whether the is workbench child condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isWorkbenchChild(){ const c = appContext(); return !!c.returnToWorkbench || String(c.caller || '').toLowerCase() === 'workbench'; }
  /**
   * isLoadingState  Return whether the is loading state condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLoadingState(){ return !!(STATE.loading || STATE.analysesLoading || STATE.artifactsLoading); }
  /**
   * analysisEmptyText  Build the analysis empty text shown to users in the browser UI.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisEmptyText(finalText){ return isLoadingState() ? 'Loading analyses...' : finalText; }
  /**
   * workbenchReturnUrl  Provide the workbench return url helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workbenchReturnUrl(){ const c = appContext(); const page = c.returnPage || 'nm_workbench.html'; return page.includes('?') ? page : `${page}?port=${encodeURIComponent(PORT)}`; }


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
   * setMsg  Route a status message to the page message strip.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * serviceMessage  Provide the service message helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceMessage(out, fallback){
    return (out && out.strip && out.strip.text) || (out && (out.message || out.error)) || fallback || 'Operation failed.';
  }
  /**
   * serviceSeverity  Provide the service severity helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceSeverity(out, fallback){
    return (out && out.strip && out.strip.severity) || fallback || ((out && out.ok) ? 'ok' : 'danger');
  }
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
    catch(err) { throw new Error(`Browser bridge returned non-JSON for ${path}: ${(txt || '').slice(0,300)}`); }
    if(obj && typeof obj === 'object' && !obj.httpStatus) obj.httpStatus = response.status;
    return obj;
  }
  /**
   * matlabService  Send a MATLAB-service request through the browser bridge.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function matlabService(payload){ return postJson('/api/matlabservice', payload); }
  /** Return the shared durable MATLAB-job client for preprocessing execution. */
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT, storageKey:`nm2_preprocess_runtime_job_${PORT}`, pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }

  /**
   * analyses  Provide the analyses helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analyses(){ return normalizedAnalyses(); }
  /**
   * selectedAnalyses  Apply the ed analyses selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedAnalyses(){ return analyses().filter(a => a.enabled && SELECTED.has(Number(a.index))); }
  /**
   * enabledAnalysisIndices  Provide the enabled analysis indices helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function enabledAnalysisIndices(){ return analyses().filter(a => !!a.enabled).map(a => Number(a.index)); }
  /**
   * sameSelectedGrid  Resolve the same selected grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sameSelectedGrid(){
    const sel = selectedAnalyses();
    if(!sel.length) return {ok:false, visible:false, reason:'Select at least one executable analysis.'};
    const first = sel[0];
    const ix = Number(first.ix || 0), jx = Number(first.jx || 0);
    if(ix < 1 || jx < 1) return {ok:false, visible:false, reason:'Selected analysis has no valid CV2 TrainInd grid.'};
    const same = sel.every(a => Number(a.ix || 0) === ix && Number(a.jx || 0) === jx);
    if(!same) return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'Selected analyses have different CV2 grid sizes. Each analysis will run all CV2 cells.'};
    return {ok:true, visible:true, hiddenByLegacyRule:false, ix, jx, reason:'Select the CV2 permutation/fold cells to preprocess.'};
  }
  /**
   * fullGrid  Resolve the full grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function fullGrid(ix,jx){ return Array.from({length:ix}, () => Array.from({length:jx}, () => true)); }
  /**
   * selectedCount  Apply the ed count selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedCount(G){ return arr(G).reduce((acc,row) => acc + arr(row).filter(Boolean).length, 0); }

  /**
   * renderAnalyses  Render the analyses UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderAnalyses(){
    const root = el('analysisList');
    if(!root) return;
    const analyses = normalizedAnalyses();
    if(window.NMAnalysisCardSelector && typeof window.NMAnalysisCardSelector.create === 'function'){
      const selected = window.NMAnalysisCardSelector.eligibleSelection(analyses, Array.from(SELECTED));
      SELECTED = new Set(selected);
      if(!ANALYSIS_SELECTOR){
        ANALYSIS_SELECTOR = window.NMAnalysisCardSelector.create(root, analyses, {
          selected,
          multiSelect:true,
          expandMode:'doubleClick',
          emptyText:analysisEmptyText('No analyses are configured. Create an analysis first.'),
          inspectLabel:'Inspect in Analysis Manager',
          onInspect:(index)=>{ inspectInAnalysisManager(index); },
          onChange:(indices)=>{ SELECTED = new Set(indices.map(Number)); GRID_PICKER = null; renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
        });
      } else {
        ANALYSIS_SELECTOR.update(analyses, {selected});
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
    const useExisting = el('useExistingParameters');
    const writeField = el('writeParametersField');
    if(writeField && useExisting) writeField.classList.toggle('hidden', !!useExisting.checked);
    const sel = Array.from(SELECTED.values());
    const summary = el('selectedSummary');
    if(summary) summary.textContent = sel.length ? `${sel.length} analysis/analyses selected` : 'No analysis selected';
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
   * renderGridSummary  Render the grid summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderGridSummary(gridInfo){
    const root = el('gridPicker');
    if(!root) return;
    window.NMRuntimeGridPicker.renderSummary(root, {
      ix:gridInfo.ix, jx:gridInfo.jx, selectedCount:selectedCount(GRID_ACT),
      buttonId:'editGridButton', onEdit:openGridModal
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
    // Edit a working copy so Cancel discards changes.
    let working = (arr(GRID_ACT).length ? GRID_ACT : fullGrid(gridInfo.ix, gridInfo.jx)).map((row)=>arr(row).map(Boolean));
    NMModal.open({
      title: 'Select CV2 partitions',
      size: 'wide',
      render: (bodyEl, modal)=>{
        const host = document.createElement('div');
        bodyEl.appendChild(host);
        const state = {ix:gridInfo.ix, jx:gridInfo.jx, GridAct:working, requireAny:true};
        GRID_PICKER = window.NMRuntimeGridPicker.create(host, state, {
          onChange:(G)=>{
            working = G;
            const n = selectedCount(G);
            modal.setActionDisabled('Apply', n < 1);
          }
        });
      },
      actions: [
        { label:'Cancel', onClick:(m)=>m.close() },
        { label:'Apply', variant:'primary', onClick:(m)=>{
            GRID_ACT = working;
            GRID_PICKER = null;
            renderOptions();
            if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged();
            m.close();
          }
        }
      ],
      onClose: ()=>{ GRID_PICKER = null; }
    });
  }

  /**
   * renderRunState  Render the run state UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRunState(){
    const btn = el('runPreprocessing');
    const hint = el('runHint');
    const gridInfo = sameSelectedGrid();
    let ok = SELECTED.size > 0 && gridInfo.ok && !STATE.artifactsLoading;
    let msg = '';
    if(STATE.artifactsLoading) msg = 'Loading runtime feasibility and artifact availability...';
    else if(!SELECTED.size) msg = 'Select at least one executable analysis.';
    else if(gridInfo.visible && selectedCount(GRID_ACT) < 1){ ok = false; msg = 'Select at least one CV2 partition.'; }
    else if(gridInfo.hiddenByLegacyRule) msg = 'Selected analyses have different CV2 grid sizes; all CV2 cells will be processed per analysis.';
    else msg = 'Ready to run preprocessing.';
    if(RUNTIME_JOB_ACTIVE){ ok = false; msg = 'Preprocessing is running in MATLAB.'; }
    if(btn) btn.disabled = !ok;
    const genBtn = el('generateRuntimeScript');
    if(genBtn) genBtn.disabled = !ok;
    const finish = el('finish'); if(finish) finish.disabled = RUNTIME_JOB_ACTIVE;
    if(hint) hint.textContent = RUNTIME_JOB_ACTIVE ? 'Preprocessing is running in MATLAB. Close the browser tab to detach safely.' : msg;
  }

  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');  renderAnalyses(); renderOptions(); if(window.NMModuleNavigationRail && typeof window.NMModuleNavigationRail.refresh === 'function') window.NMModuleNavigationRail.refresh(); }

  /**
   * currentPlan  Provide the current plan helper used by preprocessing runtime runner page.
   * It supports preprocessing runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentPlan(){
    const useExisting = !!(el('useExistingParameters') && el('useExistingParameters').checked);
    const gridInfo = sameSelectedGrid();
    return {
      analysisIndices: Array.from(SELECTED.values()),
      options: {
        overwrite: !!(el('overwriteExisting') && el('overwriteExisting').checked),
        useExistingParameters: useExisting,
        writeParameters: !useExisting && !!(el('writeParameters') && el('writeParameters').checked)
      },
      gridVisible: !!gridInfo.visible,
      gridHiddenByLegacyRule: !!gridInfo.hiddenByLegacyRule,
      GridAct: gridInfo.visible ? GRID_ACT : []
    };
  }

  /**
   * refreshLight  Refresh the light page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refreshLight(){
    try{
      const res = await matlabService({operation:'preprocess_runner_refresh_light', timeout:120});
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
      const res = await matlabService({operation:'preprocess_runner_refresh', timeout:120});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Refresh failed.');
      if(res.state){ STATE = res.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; }
      render();
    } catch(err){ setMsg(`Refresh failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * runPreprocessing  Provide the run preprocessing helper used by preprocessing runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  function ensurePreprocessingProgressViewer(){
    if(!PREPROCESS_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      PREPROCESS_PROGRESS_VIEWER = new window.NMRuntimeProgressViewer({
        port:PORT, title:'NM Preprocessing Progress Viewer',
        overallTitle:'Overall preprocessing progress',
        lowerTitle:'Preprocessing progress', pollMs:80
      });
    }
    return PREPROCESS_PROGRESS_VIEWER;
  }

  async function applyPreprocessingJobResult(res){
    if(res.ok === false) throw new Error(res.message);
    if(res.state){ STATE = res.state; ANALYSIS_SELECTOR = null; GRID_PICKER = null; }
    render();
    if(PREPROCESS_PROGRESS_VIEWER) PREPROCESS_PROGRESS_VIEWER.scheduleAutoClose(550);
  }

  function showPreprocessingJobFailure(err){
    const message = `Preprocessing failed: ${err.message || String(err)}`;
    setMsg(message, 'danger');
    if(PREPROCESS_PROGRESS_VIEWER) PREPROCESS_PROGRESS_VIEWER.hide();
  }

  async function runPreprocessing(){
    let progressTaskId = '';
    const client = runtimeJobClient();
    if(!client){ setMsg('The durable MATLAB runtime-job client is unavailable.', 'danger'); return; }
    try{
      const plan = currentPlan();
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      const viewer = ensurePreprocessingProgressViewer();
      if(viewer && window.NMRuntimeProgressViewer){
        progressTaskId = window.NMRuntimeProgressViewer.createTaskId('preproc');
        viewer.open(progressTaskId, 'Preparing preprocessing runtime.');
      }
      RUNTIME_JOB_ACTIVE = true;
      renderRunState();
      const payload = {operation:'preprocess_runner_run', plan};
      if(progressTaskId) payload.progressTaskId = progressTaskId;
      const options = {progressTaskId};
      if(progressTaskId) options.jobId = progressTaskId;
      const res = await client.run(payload, options);
      await applyPreprocessingJobResult(res);
    } catch(err){
      showPreprocessingJobFailure(err);
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
  }

  async function resumeRuntimeJobIfPresent(){
    const client = runtimeJobClient();
    if(!client) return false;
    const pending = await client.find('preprocess_runner_run');
    if(!pending || !pending.jobId) return false;
    const progressTaskId = String(pending.progressTaskId || '');
    const viewer = ensurePreprocessingProgressViewer();
    if(viewer && progressTaskId) viewer.open(progressTaskId, 'Reattached to preprocessing runtime.');
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const res = await client.wait(pending.jobId);
      await applyPreprocessingJobResult(res);
    } catch(err){
      showPreprocessingJobFailure(err);
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
    return true;
  }

  /**
   * inspectInAnalysisManager  Provide the inspect in analysis manager helper used by preprocessing runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function inspectInAnalysisManager(index){
    const idx = Number(index);
    if(!Number.isFinite(idx) || idx < 1) return;
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      const res = await matlabService({operation:'app_prepare_page', page:'analysis_manager', timeout:240});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Could not prepare the Analysis Manager page.');
      const target = res.entryHtml || res.page || 'nm_analysis_manager.html';
      const sep = target.includes('?') ? '&' : '?';
      window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`${target}${sep}port=${encodeURIComponent(PORT)}&analysis=${encodeURIComponent(idx)}&_nmcb=${Date.now()}`) : `${target}${sep}port=${encodeURIComponent(PORT)}&analysis=${encodeURIComponent(idx)}&_nmcb=${Date.now()}`);
    } catch(err){
      setMsg(`Cannot open Analysis Manager: ${err.message || String(err)}`, 'danger');
    }
  }

  /**
   * generateRuntimeScript  Provide the generate runtime script helper used by preprocessing runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function generateRuntimeScript(){
    try{
      const plan = currentPlan();
      const res = await matlabService({operation:'preprocess_runner_generate_script', plan, timeout:240});
      if(!res || res.ok === false) throw new Error((res && (res.diagnostic || res.message || res.error)) || 'Script generation failed.');
      const scripts = arr(res.scripts);
      if(scripts.length){
        const paths = scripts.map(s => (s && s.path) ? s.path : '').filter(Boolean);
        const summary = paths.length === 1
          ? `Runtime script written to: ${paths[0]}`
          : `${paths.length} runtime scripts written — ${paths.join('  ·  ')}`;
        setMsg(summary, 'ok');
      } else {
        setMsg(res.message || 'No runtime scripts were generated.', 'warn');
      }
    } catch(err){ setMsg(`Script generation failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * finish  Provide the finish helper used by preprocessing runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){ setMsg('Preprocessing is still running in MATLAB. Close this browser tab to detach; do not finish the bridge session.', 'warn'); return; }
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      try{
        const res = await matlabService({operation:'app_child_return', source:'preprocess_runner', timeout:120});
        if(res && res.ok === true){
          window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(workbenchReturnUrl()) : workbenchReturnUrl());
          return;
        }
        if(isWorkbenchChild()) throw new Error((res && (res.message || res.error)) || 'Returning to the workbench failed.');
      } catch(returnErr){
        if(isWorkbenchChild()) throw returnErr;
      }
      await postJson('/api/close', {closed:true, source:'preprocess_runner'});
      document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">Preprocessing-runner state saved. You can close this tab.</p>';
    } catch(err){ setMsg(`ERROR while closing preprocessing runner: ${err.message || String(err)}`, 'danger'); }
  }

  function installRunnerStateAdapter(){
    if(!window.NMRunnerStateManager) return;
    window.NMRunnerStateManager.registerAdapter({
      key:'preprocess_runner',
      snapshot:()=>{ const p=currentPlan(); return {analysisIndices:p.analysisIndices, options:p.options, GridAct:p.GridAct}; },
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object') return;
        const available=new Set(analyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        SELECTED=new Set(arr(saved.analysisIndices).map(Number).filter(i=>available.has(i)));
        if(Array.isArray(saved.GridAct)) GRID_ACT=saved.GridAct;
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        if(typeof o.overwrite==='boolean'&&el('overwriteExisting')) el('overwriteExisting').checked=o.overwrite;
        if(typeof o.useExistingParameters==='boolean'&&el('useExistingParameters')) el('useExistingParameters').checked=o.useExistingParameters;
        if(typeof o.writeParameters==='boolean'&&el('writeParameters')) el('writeParameters').checked=o.writeParameters;
        ANALYSIS_SELECTOR=null; GRID_PICKER=null; render();
      },
      report:(message)=>setMsg(message,'danger')
    });
  }
  installRunnerStateAdapter();
  document.addEventListener('DOMContentLoaded', () => {
    const f = el('finish'); if(f){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close'); f.onclick = finish; }
    const run = el('runPreprocessing'); if(run) run.onclick = runPreprocessing;
    const gen = el('generateRuntimeScript'); if(gen) gen.onclick = generateRuntimeScript;
    ['overwriteExisting','useExistingParameters','writeParameters'].forEach(id => { const x = el(id); if(x) x.onchange = renderOptions; });
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
    })().then(()=>window.NMRunnerStateManager?window.NMRunnerStateManager.markReady():undefined).catch(err=>setMsg(`Preprocessing runner refresh failed: ${err.message || String(err)}`, 'danger'));
  });
})();
