(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_MLI_RUNNER_STATE || {};
  let SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite));
  let GRID_ACT = (STATE.grid && STATE.grid.GridAct) || [];
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler(SELECTED);
  let SELECTION_LOADED = !(STATE.loading || STATE.analysesLoading);
  let SELECTED_OOCV = null;
  let GRID_PICKER = null;
  let ANALYSIS_SELECTOR = null;
  let MANUAL_FILES = {mliDataMasterFile:'',mliDataFiles:[]};
  let MANUAL_FILE_LIST = null;
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
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
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
  /**
   * runtimeJobClient  Return the durable MATLAB runtime-job transport for long MLI execution.
   *
   * The client polls file-backed bridge status without a wall-clock deadline and persists the
   * accepted job id across browser reloads. Short MATLAB-service requests continue to use the
   * synchronous matlabService boundary above.
   */
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT, storageKey:`nm2_mli_runtime_job_${PORT}`, pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }
  /**
   * createRuntimeProgressTaskId  Create the runtime progress task id component or browser-side state object.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createRuntimeProgressTaskId(prefix){
    if(window.NMRuntimeProgressViewer && typeof window.NMRuntimeProgressViewer.createTaskId === 'function'){
      return window.NMRuntimeProgressViewer.createTaskId(prefix || 'mli');
    }
    return `${prefix || 'mli'}_${Date.now()}_${Math.random().toString(36).slice(2,9)}`.replace(/[^A-Za-z0-9_-]/g, '');
  }
  /**
   * runtimeProgressViewer  Provide the runtime progress viewer helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeProgressViewer(){
    if(!RUNTIME_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      RUNTIME_PROGRESS_VIEWER = new window.NMRuntimeProgressViewer({port:PORT, title:'ML interpretation progress', lowerTitle:'Interpretation progress', pollMs:RUNTIME_PROGRESS_POLL_MS});
    }
    return RUNTIME_PROGRESS_VIEWER;
  }
  /**
   * showRuntimeProgress  Provide the show runtime progress helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function showRuntimeProgress(taskId){
    const viewer = runtimeProgressViewer();
    if(viewer) viewer.open(taskId, 'Running ML interpretation in MATLAB...');
  }
  /**
   * finishRuntimeProgress  Provide the finish runtime progress helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function finishRuntimeProgress(){
    const viewer = runtimeProgressViewer();
    if(viewer) viewer.scheduleAutoClose(550);
  }
  /**
   * setMsg  Route a status message to the page message strip.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * serviceMessage  Provide the service message helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceMessage(out, fallback){
    return (out && out.strip && out.strip.text) || (out && (out.message || out.error)) || fallback || 'Operation failed.';
  }
  /**
   * serviceSeverity  Provide the service severity helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
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
   * selectedAnalyses  Apply the ed analyses selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedAnalyses(){ return normalizedAnalyses().filter(a => a.enabled && SELECTED.has(Number(a.index))); }
  /**
   * currentMode  Provide the current mode helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentMode(){ const x = el('operationMode'); return x ? String(x.value || 'auto') : 'auto'; }
  /**
   * manualMode  Provide the manual mode helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualMode(){ const x = el('manualArtifactMode'); return x ? String(x.value || 'none') : 'none'; }
  /**
   * isLoadingState  Return whether the is loading state condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLoadingState(){ return !!(STATE.loading || STATE.analysesLoading || STATE.artifactsLoading); }
  /**
   * analysisEmptyText  Build the analysis empty text shown to users in the browser UI.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisEmptyText(finalText){ return isLoadingState() ? 'Loading analyses...' : finalText; }
  /**
   * modeLabel  Build the mode label shown to users in the browser UI.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function modeLabel(mode){ return ({auto:'Auto', scratch:'Scratch/resume', mlidatamat:'MLIdatamat'})[mode] || mode; }
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
    const root = el('analysisList'); if(!root) return;
    const a = normalizedAnalyses();
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
          onChange:(indices)=>{ SELECTED = new Set(indices.map(Number)); GRID_PICKER = null; renderOptions(); refresh(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
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
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sameSelectedGrid(){
    const sel = selectedAnalyses();
    if(!sel.length) return {ok:false, visible:false, reason:'Select at least one trained analysis.'};
    const first = sel[0]; const ix = Number(first.ix || 0), jx = Number(first.jx || 0);
    if(ix < 1 || jx < 1) return {ok:false, visible:false, reason:'Selected analysis has no valid CV2 grid.'};
    const same = sel.every(a => Number(a.ix || 0) === ix && Number(a.jx || 0) === jx);
    if(!same) return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'Selected analyses have different CV2 grid sizes. Each analysis will use its trained CV2 partitions.'};
    const G = window.NMRuntimeGridPicker.commonGrid(sel, ix, jx);
    return {ok:true, visible:true, hiddenByLegacyRule:false, ix, jx, reason:'Select trained CV2 partitions to interpret.', GridAct:G};
  }

  /**
   * artifactSummaryForIndex  Provide the artifact summary for index helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactSummaryForIndex(index){
    const s = arr(STATE.artifactSummary).find(x => Number(x.analysisIndex) === Number(index));
    if(s) return s;
    const a = normalizedAnalyses().find(x => Number(x.index) === Number(index));
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
    if(STATE.artifactsLoading){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Loading MLIdatamat artifact availability...</div>'; return; }
    if(!sel.length){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Select trained analyses to inspect existing MLIdatamat artifacts.</div>'; return; }
    const rows = sel.map(a => {
      const S = artifactSummaryForIndex(a.index);
      const rec = currentMode() === 'mlidatamat' ? 'mlidatamat' : 'scratch';
      const stage = currentMode() === 'auto' ? autoStageText(S) : modeLabel(rec);
      return `<tr title="${esc(S.message || '')}"><td>Analysis ${esc(a.index)}</td><td>${esc(stage)}</td><td>${esc(S.coverageText || 'not found')}</td><td class="nmRuntimeArtifactPath">${esc(S.inputDir || '')}</td><td class="nmRuntimeArtifactPath">${esc(S.resultDir || '')}</td></tr>`;
    });
    host.innerHTML = '<div class="nmRuntimeArtifactTitle">MLIdatamat artifact inventory</div>' +
      `<table class="nmRuntimeArtifactTable mliArtifactTable"><thead><tr><th>Analysis</th><th>Input stage</th><th>MLIdatamat coverage</th><th>Artifact directory</th><th>Output directory</th></tr></thead><tbody>${rows.join('')}</tbody></table>`;
  }

  /**
   * manualMLIPaths  Provide the manual mlipaths helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualMLIPaths(){ return arr(MANUAL_FILES.mliDataMasterFile || MANUAL_FILES.mliDataFiles).filter(Boolean); }
  /**
   * renderManualArtifactSummary  Render the manual artifact summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderManualArtifactSummary(){
    const msg = el('manualArtifactSummary'); if(!msg) return;
    if(manualMode() === 'none'){
      MANUAL_FILE_LIST = null;
      msg.innerHTML = '<div class="nmManualFileList empty"><div class="nmManualFileEmpty">No manual MLIdatamat artifact selected. The runner will use the automatic resolver.</div></div>';
      return;
    }
    const paths = manualMLIPaths();
    const listOpts = {
      paths,
      title:'MLIdatamat master / CV2 MLIdatamat override files',
      emptyText:'No MLIdatamat artifact selected yet. Use Pick file(s)… to add files.',
      onChange:(nextPaths)=>{ MANUAL_FILES = mliArtifactFileSpec(nextPaths); renderOptions(); refresh(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
    };
    if(window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.create === 'function'){
      if(!MANUAL_FILE_LIST){
        msg.innerHTML = '';
        MANUAL_FILE_LIST = window.NMManualArtifactFileList.create(msg, listOpts);
      } else {
        MANUAL_FILE_LIST.update(paths, listOpts);
      }
    } else {
      msg.textContent = paths.length ? `Selected ${paths.length} MLIdatamat artifact file(s).` : 'No MLIdatamat artifact selected yet.';
    }
  }

  /**
   * renderDynamicControls  Render the dynamic controls UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderDynamicControls(){
    const mode = currentMode();
    const scratchLike = mode === 'auto' || mode === 'scratch';
    const scratch = el('scratchOptions'); if(scratch) scratch.classList.toggle('hidden', !scratchLike);
    const sampleIDs = el('sampleIDs'); if(sampleIDs) sampleIDs.classList.toggle('hidden', !(el('sampleMode') && el('sampleMode').value === 'selected'));
    const spatial = selectedAnalyses().some(a => a.spatialMapsAvailable);
    const field = el('spatialMapsField'); if(field) field.classList.toggle('hidden', !spatial);
    const surfaceFormat = el('surfaceExportFormat'); if(surfaceFormat) surfaceFormat.disabled = !spatial || !(el('writeRelevanceMaps') && el('writeRelevanceMaps').checked);
  }

  /**
   * renderGridSummary  Render the grid summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function artifactGrid(gridInfo){
    if(currentMode() !== 'mlidatamat' && manualMode() !== 'mlidatamat') return null;
    const selected = selectedAnalyses();
    if(!selected.length) return null;
    const masks = selected.map(a => ({index:a.index,gridAct:artifactSummaryForIndex(a.index).availableGrid}));
    if(masks.some(a => a.gridAct == null)) return null;
    return window.NMRuntimeGridPicker.commonGrid(masks,gridInfo.ix,gridInfo.jx);
  }
  function effectiveGrid(gridInfo){
    return window.NMRuntimeGridPicker.permitted(GRID_ACT,gridInfo.ix,gridInfo.jx,artifactGrid(gridInfo));
  }

  function renderGridSummary(gridInfo){
    const host = el('gridPicker'); if(!host || !gridInfo.visible) return;
    window.NMRuntimeGridPicker.renderSummary(host, {
      ix:gridInfo.ix, jx:gridInfo.jx, selectedCount:selectedCount(effectiveGrid(gridInfo)),
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
    const available = artifactGrid(gridInfo);
    let working = effectiveGrid(gridInfo);
    window.NMModal.open({
      title:'Select CV2 partitions',
      className:'mliGridModal',
      render:(bodyEl, modal)=>{
        const host = document.createElement('div');
        bodyEl.appendChild(host);
        GRID_PICKER = window.NMRuntimeGridPicker.create(host, {ix:gridInfo.ix, jx:gridInfo.jx, GridAct:working, enabledMask:available, requireAny:true}, {onChange:(G)=>{ working = G; }});
      },
      actions:[
        {label:'Cancel', onClick:(m)=>m.close()},
        {label:'Apply', variant:'primary', onClick:(m)=>{ GRID_ACT = working; GRID_PICKER = null; renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); m.close(); }}
      ],
      onClose:()=>{ GRID_PICKER = null; }
    });
  }

  /**
   * autoStageText  Build the auto stage text shown to users in the browser UI.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function autoStageText(S){
    const nA = Number(S && S.nAvailable);
    const nE = Number(S && S.nExpected);
    if(Number.isFinite(nA) && Number.isFinite(nE) && nE > 0){
      if(nA >= nE) return 'Scratch/resume: all selected partitions already have MLIdatamat coverage';
      if(nA > 0) return `Scratch/resume: MLIdatamat overlap ${nA}/${nE}`;
      return 'Scratch/resume: compute selected partitions';
    }
    return 'Scratch/resume';
  }

  /**
   * artifactOverlap  Provide the artifact overlap helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactOverlap(S){
    const nA = Number(S.nAvailable);
    return Number.isFinite(nA) && nA > 0;
  }

  /**
   * validateRunState  Provide the validate run state helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function validateRunState(){
    const sel = selectedAnalyses();
    if(RUNTIME_JOB_ACTIVE) return {ok:false, message:'ML interpretation is already running in MATLAB.'};
    if(STATE.artifactsLoading) return {ok:false, message:'Loading MLIdatamat artifact availability...'};
    if(!sel.length) return {ok:false, message:'Select at least one trained analysis.'};
    if(STATE.oocvMode && !eligibleOOCV().some(c=>Number(c.index)===Number(SELECTED_OOCV)))
      return {ok:false, message:'Choose an OOCV dataset that is ready for every selected analysis.'};
    const grid = sameSelectedGrid();
    if(grid.visible && !selectedCount(effectiveGrid(grid))) return {ok:false, message:'Select at least one CV2 partition with available input artifacts.'};
    const selectedMode = manualMode();
    const mode = selectedMode === 'none' ? currentMode() : selectedMode;
    if(mode === 'mlidatamat' && manualMode() === 'none'){
      const empty = selectedAnalyses().map(a => artifactSummaryForIndex(a.index)).filter(S => !artifactOverlap(S));
      if(empty.length) return {ok:false, message:'Use existing MLIdatamat requires a non-empty artifact overlap with the selected CV2 partitions. Choose Auto/Scratch or reduce the CV2 selection.'};
    }
    if(manualMode() !== 'none' && !manualMLIPaths().length) return {ok:false, message:'Pick an MLIdatamat master or CV2-level MLIdatamat artifact, or set manual override to None.'};
    if(el('sampleMode') && el('sampleMode').value === 'selected' && !sampleIDList().length) return {ok:false, message:'Provide at least one sample ID or select All samples.'};
    return {ok:true, message:'Ready to run ML interpretation.'};
  }

  /**
   * renderRunState  Render the run state UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRunState(){
    const hint = el('runHint'); const run = el('runMLI'); const gen = el('generateRuntimeScript');
    const v = validateRunState();
    const running = RUNTIME_JOB_ACTIVE;
    if(run) run.disabled = !v.ok || running;
    if(gen) gen.disabled = !v.ok || running;
    const finish = el('finish'); if(finish) finish.disabled = running;
    if(hint) hint.textContent = running ? 'ML interpretation is running in MATLAB. Close the browser tab to detach safely.' : v.message;
  }

  /**
   * renderOptions  Render the options UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderOptions(){
    const oocv = STATE.oocvMode;
    el('oocvDatasetField').classList.toggle('hidden',!oocv);
    el('artifactSummary').classList.remove('hidden');
    if(oocv) renderOOCVSelection();
    const summary = el('selectedSummary'); if(summary) summary.textContent = SELECTED.size ? `${SELECTED.size} analysis/analyses selected` : 'No analysis selected';
    renderArtifactSummary(); renderManualArtifactSummary();
    renderDynamicControls();
    const gridInfo = sameSelectedGrid();
    GRID_ACT = reconcileGrid(GRID_ACT, gridInfo, SELECTED);
    const gridSection = el('gridSection'); const hiddenNote = el('gridHiddenNote'); const reason = el('gridReason');
    if(gridSection) gridSection.classList.toggle('hidden', !gridInfo.visible);
    if(hiddenNote) hiddenNote.classList.toggle('hidden', !!gridInfo.visible || !gridInfo.hiddenByLegacyRule);
    if(reason) reason.textContent = gridInfo.reason || '';
    if(gridInfo.visible){
      renderGridSummary(gridInfo);
    }
    renderRunState();
  }

  function eligibleOOCV(){
    return arr(STATE.oocv.containers).filter(c=>selectedAnalyses().length && selectedAnalyses().every(a=>
      arr(STATE.readiness).some(r=>r.analysisIndex===a.index && r.oocvIndex===c.index && r.ready)));
  }
  function renderOOCVSelection(){
    const rows=eligibleOOCV();
    if(rows.length===1) SELECTED_OOCV=Number(rows[0].index);
    else if(!rows.some(c=>Number(c.index)===Number(SELECTED_OOCV))) SELECTED_OOCV=null;
    window.NMOOCVContainerSelector.renderControl(el('oocvDatasetField'),{
      containers:rows,selectedIndex:SELECTED_OOCV,label:'Independent OOCV dataset',
      emptyText:'Select an OOCV dataset',unavailableText:'No suitable OOCV dataset available',
      detail:'',disabled:RUNTIME_JOB_ACTIVE,onClick:openOOCVDatasetSelector
    });
  }
  function openOOCVDatasetSelector(){
    window.NMOOCVContainerSelector.open({
      containers:eligibleOOCV(), selectedIndex:SELECTED_OOCV,
      title:'Select OOCV data for ML interpretation',
      intro:'Select one independent dataset that is ready for every selected analysis.',
      confirmLabel:'Use selected OOCV data',pendingStatus:'not ready',isReady:()=>true,
      onSelect:index=>{SELECTED_OOCV=index;renderOptions();refresh();if(window.NMRunnerStateManager)window.NMRunnerStateManager.markChanged();}
    });
  }

  /**
   * sampleIDList  Provide the sample idlist helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sampleIDList(){
    const ta = el('sampleIDs');
    if(!ta) return [];
    return String(ta.value || '').split(/[,;\n\r]+/).map(s => s.trim()).filter(Boolean);
  }

  /**
   * collectOptions  Collect options values into a request or rendering model.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectOptions(){
    return {
      operationMode: currentMode(),
      manualArtifactMode: manualMode(),
      manualFiles: MANUAL_FILES,
      overwrite: !!(el('overwriteExisting') && el('overwriteExisting').checked),
      overwritePermutations: !!(el('overwritePermutations') && el('overwritePermutations').checked),
      recomputeEstimates: !!(el('recomputeEstimates') && el('recomputeEstimates').checked),
      saveParameters: !!(el('saveParameters') && el('saveParameters').checked),
      loadParameters: !!(el('loadParameters') && el('loadParameters').checked),
      saveCV1: !!(el('saveCV1') && el('saveCV1').checked),
      exportRelevanceMaps: selectedAnalyses().some(a => a.spatialMapsAvailable) && !!(el('writeRelevanceMaps') && el('writeRelevanceMaps').checked),
      surfaceExportFormat: el('surfaceExportFormat') ? el('surfaceExportFormat').value : 'source',
      selectSamples: el('sampleMode') ? el('sampleMode').value : 'all',
      sampleIDs: sampleIDList()
    };
  }

  /**
   * collectPlan  Collect plan values into a request or rendering model.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectPlan(){
    const gridInfo = sameSelectedGrid();
    const plan = {analysisIndices:Array.from(SELECTED.values()), gridAction:gridInfo.visible ? effectiveGrid(gridInfo) : GRID_ACT, gridVisible:!!gridInfo.visible, gridHiddenByLegacyRule:!!gridInfo.hiddenByLegacyRule, options:collectOptions()};
    if(STATE.oocvMode) plan.oocvIndex=SELECTED_OOCV;
    return plan;
  }

  /**
   * runMLI  Provide the run mli helper used by MLI runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function applyRuntimeJobResult(out){
    if(out && out.ok){
      if(out.state){
        STATE = out.state;
        renderAll();
      }
      const exportErrors=Number(out.relevanceMapErrorCount||0);
      if(exportErrors > 0) setMsg(out.message || `ML interpretation completed, but ${exportErrors} relevance-map export(s) failed.`, 'warning');
      finishRuntimeProgress();
    } else {
      if(RUNTIME_PROGRESS_VIEWER) RUNTIME_PROGRESS_VIEWER.hide();
      setMsg(serviceMessage(out, 'Running ML interpretation failed.'), serviceSeverity(out, 'danger'));
    }
  }

  /**
   * runMLI  Submit ML interpretation as a durable MATLAB runtime job.
   *
   * Submission returns immediately from the HTTP bridge. This function then waits only on the
   * file-backed job-status endpoint; it deliberately has no wall-clock timeout. The job continues
   * if the browser is reloaded or the initiating network request disappears.
   */
  async function runMLI(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const client = runtimeJobClient();
    if(!client){ setMsg('The durable MATLAB runtime-job client is unavailable.', 'danger'); return; }
    try{ if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow(); }
    catch(err){ setMsg(`ML interpretation cannot start because its runner setup could not be saved: ${err.message || String(err)}`, 'error'); return; }
    const progressTaskId = createRuntimeProgressTaskId('mli');
    showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const servicePayload = {operation:'mli_runner_run', plan:collectPlan(), progressTaskId, progressChartMinIntervalSeconds:RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS};
      const out = await client.run(servicePayload, {jobId:progressTaskId, progressTaskId});
      await applyRuntimeJobResult(out);
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
  }

  /**
   * resumeRuntimeJobIfPresent  Reattach this page to an accepted MLI job after browser reload.
   *
   * Reattachment uses persisted job identity and progress-task identity only. It does not issue a
   * synchronous MATLAB-service request while MATLAB is owned by the running job.
   */
  async function resumeRuntimeJobIfPresent(){
    const client = runtimeJobClient();
    if(!client) return false;
    const pending = await client.find('mli_runner_run');
    if(!pending || !pending.jobId) return false;
    const progressTaskId = String(pending.progressTaskId || '');
    if(progressTaskId) showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const out = await client.wait(pending.jobId);
      await applyRuntimeJobResult(out);
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
    return true;
  }

  /**
   * generateRuntimeScript  Provide the generate runtime script helper used by MLI runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function generateRuntimeScript(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const out = await matlabService({operation:'mli_runner_generate_script', plan:collectPlan(), timeout:120});
    if(out && out.ok) setMsg(out.message || 'ML-interpretation runtime script generated.', 'success');
    else setMsg(serviceMessage(out, 'Generating the runtime script failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * refreshLight  Refresh the light page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(light=false){
    const plan = collectPlan();
    plan.gridAction = GRID_ACT;
    const out = await matlabService({operation:light?'mli_runner_refresh_light':'mli_runner_refresh',plan});
    if(out && out.ok && out.state){
      STATE = out.state;
      if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number));
      SELECTION_LOADED = true;
      ANALYSIS_SELECTOR = null;
      GRID_PICKER = null;
      renderAll();
      if(!light && STATE.oocvMode && SELECTED_OOCV && SELECTED_OOCV !== STATE.options.oocvIndex)
        await refresh();
    }
    else setMsg(serviceMessage(out, light?'Analysis-list refresh failed.':'Refresh failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * cleanDataId  Resolve the clean data id identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function cleanDataId(id){ return String(id == null ? '' : id).trim().replace(/^ID/i, ''); }
  /**
   * mliPickerFilter  Provide the mli picker filter helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mliPickerFilter(analysis){
    const summary = artifactSummaryForIndex(analysis && analysis.index);
    const id = cleanDataId((summary && summary.dataId) || (analysis && analysis.id) || '');
    const names = ['MLIdatamatMaster','MLIdatamat'];
    const parts = [];
    names.forEach(name => {
      if(id){ parts.push(`*${name}*ID${id}*.mat`, `*${name}*_ID${id}*.mat`, `*${name}*${id}*.mat`); }
      parts.push(`*${name}*.mat`);
    });
    parts.push('*.mat');
    return Array.from(new Set(parts.filter(Boolean))).join(';');
  }
  /**
   * mliArtifactFileSpec  Provide the mli artifact file spec helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function mliArtifactFileSpec(paths){
    const files = arr(paths).filter(Boolean);
    const spec = {mliDataMasterFile:'',mliDataFiles:[]};
    if(!files.length) return spec;
    const firstName = String(files[0]).split(/[\\/]/).pop();
    if(files.length === 1 && /MLIdatamatMaster/i.test(firstName)) spec.mliDataMasterFile = files[0];
    else spec.mliDataFiles = files;
    return spec;
  }
  /**
   * pickArtifact  Provide the pick artifact helper used by MLI runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function pickArtifact(){
    const sel = selectedAnalyses();
    if(sel.length !== 1){ setMsg('Manual MLIdatamat artifact override is available for one selected analysis at a time.', 'warning'); return; }
    const a = sel[0];
    const summary = artifactSummaryForIndex(a.index) || {};
    const id = cleanDataId(summary.dataId || a.id || '');
    const initial = summary.inputDir || a.rootdir || '';
    const filter = mliPickerFilter(a);
    const title = id ? `Select MLIdatamat master or CV2-level MLIdatamats for ID${id}` : 'Select MLIdatamat master or CV2-level MLIdatamats';
    const out = await postJson('/api/pickpath', {kind:'file', multiple:true, initial, filter, title, timeout:600});
    const picked = arr(out && (out.paths || out.files || out.path || out.file)).filter(Boolean);
    if(picked.length){
      const current = manualMLIPaths();
      const paths = window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.uniquePaths === 'function' ?
        window.NMManualArtifactFileList.uniquePaths(current.concat(picked)) : current.concat(picked);
      MANUAL_FILES = mliArtifactFileSpec(paths);
      if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged();
      const m = el('manualArtifactMode'); if(m) m.value = 'mlidatamat';
      renderOptions();
      await refresh();
    }
  }

  /**
   * workbenchReturnUrl  Provide the workbench return url helper used by MLI runtime runner page.
   * It supports MLI runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workbenchReturnUrl(){
    const target = appContext().returnPage || 'nm_workbench.html';
    const sep = target.includes('?') ? '&' : '?';
    return `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`;
  }

  /**
   * finish  Provide the finish helper used by MLI runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){ setMsg('ML interpretation is still running in MATLAB. Close this browser tab to detach; do not finish the bridge session.', 'warning'); return; }
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      if(isWorkbenchChild()){
        const out = await matlabService({operation:'app_child_return', source:'mli_runner', timeout:120});
        if(out && out.ok){ window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(workbenchReturnUrl()) : workbenchReturnUrl()); return; }
        throw new Error((out && (out.message || out.error)) || 'Returning to the workbench failed.');
      }
      await postJson('/api/close', {source:'mli_runner'});
      document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">ML-interpretation runner state saved. You can close this tab.</p>';
    } catch(err){ setMsg(`ERROR while closing ML-interpretation runner: ${err.message || String(err)}`, 'error'); }
  }
  /**
   * inspectInAnalysisManager  Provide the inspect in analysis manager helper used by MLI runtime runner page.
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
    ['operationMode','manualArtifactMode','overwriteExisting','overwritePermutations','recomputeEstimates','saveParameters','loadParameters','saveCV1','writeRelevanceMaps','surfaceExportFormat','sampleMode','sampleIDs'].forEach(id => { const x=el(id); if(x) x.addEventListener(id === 'sampleIDs' ? 'input' : 'change', renderOptions); });
    const p = el('pickArtifactFile'); if(p) p.addEventListener('click', () => pickArtifact().catch(e => setMsg(e.message,'error')));
    const run = el('runMLI'); if(run) run.addEventListener('click', () => runMLI().catch(e => setMsg(e.message,'error')));
    const gen = el('generateRuntimeScript'); if(gen) gen.addEventListener('click', () => generateRuntimeScript().catch(e => setMsg(e.message,'error')));
  }
  /**
   * renderAll  Render the all UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderAll(){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');  renderAnalyses(); renderOptions(); if(window.NMModuleNavigationRail && typeof window.NMModuleNavigationRail.refresh === 'function') window.NMModuleNavigationRail.refresh(); }
  function installRunnerStateAdapter(){
    if(!window.NMRunnerStateManager) return;
    window.NMRunnerStateManager.registerAdapter({
      key:'mli_runner',
      snapshot:()=>{const p=collectPlan();p.gridAction=GRID_ACT;return p;},
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object') return;
        const available=new Set(normalizedAnalyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        SELECTED=new Set(arr(saved.analysisIndices).map(Number).filter(i=>available.has(i)));
        if(Array.isArray(saved.gridAction)) GRID_ACT=saved.gridAction;
        if(STATE.oocvMode){ const index=Number(saved.oocvIndex); SELECTED_OOCV=Number.isInteger(index)&&index>0?index:null; }
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        const setValue=(id,value)=>{const x=el(id);if(x&&value!==undefined&&value!==null)x.value=String(value);};
        const setCheck=(id,value)=>{const x=el(id);if(x&&typeof value==='boolean')x.checked=value;};
        setValue('operationMode',o.operationMode); setValue('manualArtifactMode',o.manualArtifactMode);
        MANUAL_FILES=o.manualFiles&&typeof o.manualFiles==='object'?mliArtifactFileSpec(arr(o.manualFiles.mliDataMasterFile || o.manualFiles.mliDataFiles)) : mliArtifactFileSpec([]); MANUAL_FILE_LIST=null;
        setCheck('overwriteExisting',o.overwrite); setCheck('overwritePermutations',o.overwritePermutations);
        setCheck('recomputeEstimates',o.recomputeEstimates); setCheck('saveParameters',o.saveParameters);
        setCheck('loadParameters',o.loadParameters); setCheck('saveCV1',o.saveCV1); setCheck('writeRelevanceMaps',o.exportRelevanceMaps);
        setValue('surfaceExportFormat',o.surfaceExportFormat); setValue('sampleMode',o.selectSamples);
        if(el('sampleIDs')&&Array.isArray(o.sampleIDs)) el('sampleIDs').value=o.sampleIDs.join('\n');
        ANALYSIS_SELECTOR=null; GRID_PICKER=null; renderAll();
        if((STATE.oocvMode && SELECTED_OOCV) || manualMode() === 'mlidatamat') await refresh();
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
        await refresh(true);
        await refresh();
      } else if(appContext().fastChildOpen || (STATE.oocvMode && SELECTED_OOCV)){
        await refresh();
      }
    })().then(()=>window.NMRunnerStateManager?window.NMRunnerStateManager.markReady():undefined).catch(err=>setMsg(`ML-interpretation runner refresh failed: ${err.message || String(err)}`, 'error'));
  });
})();
