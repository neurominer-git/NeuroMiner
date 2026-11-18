(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_VIS_RUNNER_STATE || {};
  let SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number).filter(Number.isFinite));
  let GRID_ACT = (STATE.grid && STATE.grid.GridAct) || [];
  const reconcileGrid = window.NMRuntimeGridPicker.reconciler(SELECTED);
  let SELECTION_LOADED = !(STATE.loading || STATE.analysesLoading);
  let GRID_PICKER = null;
  let ANALYSIS_SELECTOR = null;
  let MANUAL_FILES = {};
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
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
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
  /** Return the shared durable MATLAB-job client for visualization execution. */
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({port:PORT, storageKey:`nm2_vis_runtime_job_${PORT}`, pollMs:750});
    }
    return RUNTIME_JOB_CLIENT;
  }
  /**
   * createRuntimeProgressTaskId  Create the runtime progress task id component or browser-side state object.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createRuntimeProgressTaskId(prefix){
    if(window.NMRuntimeProgressViewer && typeof window.NMRuntimeProgressViewer.createTaskId === 'function'){
      return window.NMRuntimeProgressViewer.createTaskId(prefix || 'nmvis');
    }
    return `${prefix || 'nmvis'}_${Date.now()}_${Math.random().toString(36).slice(2,9)}`.replace(/[^A-Za-z0-9_-]/g, '');
  }
  /**
   * runtimeProgressViewer  Provide the runtime progress viewer helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeProgressViewer(){
    if(!RUNTIME_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      RUNTIME_PROGRESS_VIEWER = new window.NMRuntimeProgressViewer({port:PORT, title:'Model visualization progress', lowerTitle:'Visualization progress', pollMs:RUNTIME_PROGRESS_POLL_MS});
    }
    return RUNTIME_PROGRESS_VIEWER;
  }
  /**
   * showRuntimeProgress  Provide the show runtime progress helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function showRuntimeProgress(taskId){
    const viewer = runtimeProgressViewer();
    if(viewer) viewer.open(taskId, 'Running model visualization in MATLAB...');
  }
  /**
   * finishRuntimeProgress  Provide the finish runtime progress helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function finishRuntimeProgress(){
    const viewer = runtimeProgressViewer();
    if(viewer) viewer.scheduleAutoClose(550);
  }
  /**
   * setMsg  Route a status message to the page message strip.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * serviceMessage  Provide the service message helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceMessage(out, fallback){
    return (out && out.strip && out.strip.text) || (out && (out.message || out.error)) || fallback || 'Operation failed.';
  }
  /**
   * serviceSeverity  Provide the service severity helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function serviceSeverity(out, fallback){
    return (out && out.strip && out.strip.severity) || fallback || ((out && out.ok) ? 'ok' : 'danger');
  }
  /**
   * analyses  Return authoritative visualization-runner analysis records.
   * Shared analysis cards normalize their own display copy; runner logic must retain
   * decomp/imaging/permutation fields that control visualization configuration.
   */
  function analyses(){ return arr(STATE.analyses); }
  /**
   * selectedAnalyses  Apply the ed analyses selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedAnalyses(){ return analyses().filter(a => a.enabled && SELECTED.has(Number(a.index))); }
  /**
   * currentMode  Provide the current mode helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentMode(){ const x = el('operationMode'); return x ? String(x.value || 'auto') : 'auto'; }
  /**
   * manualMode  Provide the manual mode helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualMode(){ const x = el('manualArtifactMode'); return x ? String(x.value || 'none') : 'none'; }
  /**
   * effectiveMode  Provide the effective mode helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function effectiveMode(){ const m = manualMode(); return m !== 'none' ? m : currentMode(); }
  /**
   * isLoadingState  Return whether the is loading state condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLoadingState(){ return !!(STATE.loading || STATE.analysesLoading || STATE.artifactsLoading); }
  /**
   * analysisEmptyText  Build the analysis empty text shown to users in the browser UI.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisEmptyText(finalText){ return isLoadingState() ? 'Loading analyses...' : finalText; }
  /**
   * modeLabel  Build the mode label shown to users in the browser UI.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function modeLabel(mode){ return ({auto:'Auto', scratch:'Scratch/resume', visdatamat:'VISdatamat'})[mode] || mode; }
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
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function sameSelectedGrid(){
    const sel = selectedAnalyses();
    if(!sel.length) return {ok:false, visible:false, reason:'Select at least one trained analysis.'};
    const first = sel[0]; const ix = Number(first.ix || 0), jx = Number(first.jx || 0);
    if(ix < 1 || jx < 1) return {ok:false, visible:false, reason:'Selected analysis has no valid CV2 grid.'};
    const same = sel.every(a => Number(a.ix || 0) === ix && Number(a.jx || 0) === jx);
    if(!same) return {ok:true, visible:false, hiddenByLegacyRule:true, reason:'Selected analyses have different CV2 grid sizes. Each analysis will use its trained CV2 cells.'};
    const G = window.NMRuntimeGridPicker.commonGrid(sel, ix, jx);
    return {ok:true, visible:true, hiddenByLegacyRule:false, ix, jx, reason:'Select trained CV2 permutation/fold cells to visualize.', GridAct:G};
  }

  /**
   * artifactSummaryForIndex  Provide the artifact summary for index helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
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
    if(STATE.artifactsLoading){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Loading VISdatamat artifact availability...</div>'; return; }
    if(!sel.length){ host.innerHTML = '<div class="nmRuntimeArtifactEmpty">Select trained analyses to inspect existing VISdatamat artifacts.</div>'; return; }
    const rows = sel.map(a => {
      const S = artifactSummaryForIndex(a.index);
      const rec = currentMode() === 'visdatamat' ? 'visdatamat' : 'scratch';
      const stage = currentMode() === 'auto' ? autoStageText(S) : modeLabel(rec);
      return `<tr title="${esc(S.message || '')}"><td>Analysis ${esc(a.index)}</td><td>${esc(stage)}</td><td>${esc(S.coverageText || 'not found')}</td><td class="nmRuntimeArtifactPath">${esc(S.rootdir || '')}</td></tr>`;
    });
    host.innerHTML = '<div class="nmRuntimeArtifactTitle">VISdatamat artifact inventory</div>' +
      `<table class="nmRuntimeArtifactTable visArtifactTable"><thead><tr><th>Analysis</th><th>Input stage</th><th>VISdatamat coverage</th><th>Artifact directory</th></tr></thead><tbody>${rows.join('')}</tbody></table>`;
  }

  /**
   * renderModeHelp  Render the mode help UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderModeHelp(){
    const help = el('modeHelp'); if(!help) return;
    const mode = currentMode();
    if(mode === 'auto') help.textContent = 'Auto uses the legacy scratch/resume path: existing VISdatamat files are reused when overwrite is off, and missing selected CV2 cells are computed.';
    else if(mode === 'scratch') help.textContent = 'Compute visualization outputs from trained CVresults/GDdims state. With overwrite off, existing VISdatamat files are reused and only missing selected cells are computed.';
    else help.textContent = 'Use a VISdataMaster file or individual CV2-level VISdatamats. Missing selected cells block execution in this mode.';
  }

  /**
   * manualVisPaths  Provide the manual vis paths helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function manualVisPaths(){ return arr(MANUAL_FILES.visDataMasterFile || MANUAL_FILES.visDataFiles).filter(Boolean); }
  /**
   * renderManualArtifactSummary  Render the manual artifact summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderManualArtifactSummary(){
    const msg = el('manualArtifactSummary'); if(!msg) return;
    if(manualMode() === 'none'){
      MANUAL_FILE_LIST = null;
      msg.innerHTML = '<div class="nmManualFileList empty"><div class="nmManualFileEmpty">No manual VISdata artifact selected. The runner will use the automatic resolver.</div></div>';
      return;
    }
    const paths = manualVisPaths();
    const listOpts = {
      paths,
      title:'VISdataMaster / VISdatamat override files',
      emptyText:'No VISdata artifact selected yet. Use Pick file(s)… to add files.',
      onChange:(nextPaths)=>{ MANUAL_FILES = visArtifactFileSpec(nextPaths); renderOptions(); if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged(); }
    };
    if(window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.create === 'function'){
      if(!MANUAL_FILE_LIST){
        msg.innerHTML = '';
        MANUAL_FILE_LIST = window.NMManualArtifactFileList.create(msg, listOpts);
      } else {
        MANUAL_FILE_LIST.update(paths, listOpts);
      }
    } else {
      msg.textContent = paths.length ? `Selected ${paths.length} VISdata artifact file(s).` : 'No VISdata artifact selected yet.';
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
    const sel = selectedAnalyses();
    const map = el('mapOptions'); if(map) map.classList.toggle('hidden', !(sel.length === 1 && !!sel[0].containsImagingData));
    const decomp = el('decompOptions');
    const anyDecomp = sel.some(a => !!a.decompAvailable);
    if(decomp) decomp.classList.toggle('hidden', !anyDecomp);
    const adv = el('decompAdvanced'); if(adv) adv.classList.toggle('hidden', !(el('decompMode') && el('decompMode').checked && anyDecomp));
    const low = el('lowMemoryField'); if(low) low.classList.toggle('hidden', !sel.some(a => a.lowMemoryVisible !== false));
    const extra = el('extraLabelNote'); if(extra) extra.classList.toggle('hidden', !sel.some(a => !!a.permfl));
  }

  /**
   * renderGridSummary  Render the grid summary UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function artifactGrid(gridInfo){
    if(effectiveMode() !== 'visdatamat') return null;
    const selected = selectedAnalyses();
    const masks = selected.map(a => ({index:a.index,gridAct:artifactSummaryForIndex(a.index).availableGrid}));
    if(masks.some(a => !arr(a.gridAct).length)) return null;
    return window.NMRuntimeGridPicker.commonGrid(masks,gridInfo.ix,gridInfo.jx);
  }
  function executableGrid(gridInfo){
    return window.NMRuntimeGridPicker.permitted(GRID_ACT,gridInfo.ix,gridInfo.jx,artifactGrid(gridInfo));
  }

  function renderGridSummary(gridInfo){
    const host = el('gridPicker'); if(!host) return;
    window.NMRuntimeGridPicker.renderSummary(host, {
      ix:gridInfo.ix, jx:gridInfo.jx, selectedCount:selectedCount(executableGrid(gridInfo)),
      buttonId:'editGrid', onEdit:()=>openGridModal(gridInfo)
    });
  }
  /**
   * openGridModal  Open the grid modal panel, dialog or linked UI target.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function openGridModal(gridInfo){
    if(!window.NMModal || !window.NMRuntimeGridPicker) return;
    const available = artifactGrid(gridInfo);
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
   * autoStageText  Build the auto stage text shown to users in the browser UI.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function autoStageText(S){
    const nA = Number(S && S.nAvailable);
    const nE = Number(S && S.nExpected);
    if(Number.isFinite(nA) && Number.isFinite(nE) && nE > 0){
      if(nA >= nE) return 'Scratch/resume: all selected cells already available';
      if(nA > 0) return `Scratch/resume: compute ${Math.max(0,nE-nA)} missing cells`;
      return 'Scratch/resume: compute selected cells';
    }
    return 'Scratch/resume';
  }

  /**
   * selectedArtifactSummaries  Apply the ed artifact summaries selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedArtifactSummaries(){
    return selectedAnalyses().map(a => artifactSummaryForIndex(a.index));
  }

  /**
   * artifactComplete  Provide the artifact complete helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactComplete(S, grid){
    if(!S) return false;
    if(arr(S.availableGrid).length){
      const selected = executableGrid(grid);
      const available = window.NMRuntimeGridPicker.permitted(selected,grid.ix,grid.jx,S.availableGrid);
      return selectedCount(selected) === selectedCount(available);
    }
    if(S.available === true) return true;
    const nA = Number(S.nAvailable);
    const nE = Number(S.nExpected);
    return Number.isFinite(nA) && Number.isFinite(nE) && nE > 0 && nA >= nE;
  }

  /**
   * validateRunState  Provide the validate run state helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function validateRunState(){
    const sel = selectedAnalyses();
    if(STATE.artifactsLoading) return {ok:false, message:'Loading VISdatamat artifact availability...'};
    if(!sel.length) return {ok:false, message:'Select at least one trained analysis.'};
    const grid = sameSelectedGrid();
    if(grid.visible && !selectedCount(executableGrid(grid))) return {ok:false, message:'Select at least one available CV2 cell.'};
    const mode = effectiveMode();
    if(mode === 'visdatamat' && manualMode() === 'none'){
      const incomplete = selectedArtifactSummaries().filter(S => !artifactComplete(S,grid));
      if(incomplete.length) return {ok:false, message:'Use existing VISdatamat requires complete VISdatamat artifacts for all selected analyses and CV2 cells. Choose Auto/Scratch or reduce the CV2 selection.'};
    }
    if(manualMode() !== 'none' && !manualVisPaths().length) return {ok:false, message:'Pick a VISdataMaster or CV2-level VISdatamat artifact, or set manual override to None.'};
    return {ok:true, message:'Ready to run model visualization.'};
  }

  /**
   * renderRunState  Render the run state UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRunState(){
    const hint = el('runHint'); const run = el('runVisualization'); const gen = el('generateRuntimeScript');
    const v = validateRunState();
    const running = RUNTIME_JOB_ACTIVE;
    if(run) run.disabled = !v.ok || running;
    if(gen) gen.disabled = !v.ok || running;
    const finish = el('finish'); if(finish) finish.disabled = running;
    if(hint) hint.textContent = running ? 'Model visualization is running in MATLAB. Close the browser tab to detach safely.' : v.message;
  }

  /**
   * renderOptions  Render the options UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderOptions(){
    const summary = el('selectedSummary'); if(summary) summary.textContent = SELECTED.size ? `${SELECTED.size} analysis/analyses selected` : 'No analysis selected';
    renderArtifactSummary(); renderModeHelp(); renderManualArtifactSummary(); renderDynamicControls();
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

  /**
   * collectOptions  Collect options values into a request or rendering model.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectOptions(){
    return {
      operationMode: currentMode(),
      manualArtifactMode: manualMode(),
      manualFiles: MANUAL_FILES,
      overwrite: !!(el('overwriteExisting') && el('overwriteExisting').checked),
      operateAtCV1: !!(el('operateAtCV1') && el('operateAtCV1').checked),
      saveParameters: !!(el('saveParameters') && el('saveParameters').checked),
      loadParameters: !!(el('loadParameters') && el('loadParameters').checked),
      writeCV2Maps: !!(el('writeCV2Maps') && el('writeCV2Maps').checked),
      cvrNorm: el('cvrNorm') ? el('cvrNorm').value : 'sd',
      decompMode: !!(el('decompMode') && el('decompMode').checked),
      lowMemory: !!(el('lowMemory') && el('lowMemory').checked),
      simCorrMethod: el('simCorrMethod') ? el('simCorrMethod').value : 'spearman',
      simCorrThresh: el('simCorrThresh') ? Number(el('simCorrThresh').value) : 0.5,
      corrCompCutoff: el('corrCompCutoff') ? Number(el('corrCompCutoff').value) : 0.3,
      selCompCutoff: el('selCompCutoff') ? Number(el('selCompCutoff').value) : 0.1,
      pruneMode: el('pruneMode') ? el('pruneMode').value : 'fraction',
      pruneFraction: el('pruneFraction') ? Number(el('pruneFraction').value) : 0.30
    };
  }

  /**
   * collectPlan  Collect plan values into a request or rendering model.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function collectPlan(){
    const gridInfo = sameSelectedGrid();
    return {analysisIndices:Array.from(SELECTED.values()), gridAction:gridInfo.visible ? executableGrid(gridInfo) : GRID_ACT, gridVisible:!!gridInfo.visible, gridHiddenByLegacyRule:!!gridInfo.hiddenByLegacyRule, options:collectOptions()};
  }

  /**
   * runVisualization  Provide the run visualization helper used by visualization runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function applyVisualizationJobResult(out){
    if(out && out.ok){
      if(out.state){ STATE = out.state; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
      finishRuntimeProgress();
      return;
    }
    if(RUNTIME_PROGRESS_VIEWER) RUNTIME_PROGRESS_VIEWER.hide();
    throw new Error(serviceMessage(out, 'Running visualization failed.'));
  }

  async function runVisualization(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const client = runtimeJobClient();
    if(!client){ setMsg('The durable MATLAB runtime-job client is unavailable.', 'danger'); return; }
    try{ if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow(); }
    catch(err){ setMsg(`Visualization cannot start because its runner setup could not be saved: ${err.message || String(err)}`, 'danger'); return; }
    const progressTaskId = createRuntimeProgressTaskId('nmvis');
    showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const servicePayload = {operation:'vis_runner_run', plan:collectPlan(), progressTaskId, progressChartMinIntervalSeconds:RUNTIME_PROGRESS_WRITE_INTERVAL_SECONDS};
      const out = await client.run(servicePayload, {jobId:progressTaskId, progressTaskId});
      await applyVisualizationJobResult(out);
    } catch(err){
      setMsg(`Running visualization failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
  }

  async function resumeRuntimeJobIfPresent(){
    const client = runtimeJobClient();
    if(!client) return false;
    const pending = await client.find('vis_runner_run');
    if(!pending || !pending.jobId) return false;
    const progressTaskId = String(pending.progressTaskId || '');
    if(progressTaskId) showRuntimeProgress(progressTaskId);
    RUNTIME_JOB_ACTIVE = true;
    renderRunState();
    try{
      const out = await client.wait(pending.jobId);
      await applyVisualizationJobResult(out);
    } catch(err){
      setMsg(`Running visualization failed: ${err.message || String(err)}`, 'danger');
    } finally {
      RUNTIME_JOB_ACTIVE = false;
      renderRunState();
    }
    return true;
  }

  /**
   * generateRuntimeScript  Provide the generate runtime script helper used by visualization runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function generateRuntimeScript(){
    const v = validateRunState();
    if(!v.ok){ setMsg(v.message, 'warning'); return; }
    const out = await matlabService({operation:'vis_runner_generate_script', plan:collectPlan(), timeout:120});
    if(out && out.ok) setMsg(out.message || 'Visualization runtime script generated.', 'success');
    else setMsg(serviceMessage(out, 'Generating the runtime script failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * refreshLight  Refresh the light page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refreshLight(){
    const out = await matlabService({operation:'vis_runner_refresh_light'});
    if(out && out.ok && out.state){ STATE = out.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
    else setMsg(serviceMessage(out, 'Analysis-list refresh failed.'), serviceSeverity(out, 'danger'));
  }

  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(){
    const out = await matlabService({operation:'vis_runner_refresh'});
    if(out && out.ok && out.state){ STATE = out.state; if(!SELECTION_LOADED) SELECTED = new Set(arr(STATE.selectedAnalysisIndices).map(Number)); SELECTION_LOADED = true; ANALYSIS_SELECTOR = null; GRID_PICKER = null; renderAll(); }
    else setMsg(serviceMessage(out, 'Refresh failed.'), serviceSeverity(out, 'danger'));
  }
  /**
   * cleanDataId  Resolve the clean data id identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function cleanDataId(id){ return String(id == null ? '' : id).trim().replace(/^ID/i, ''); }
  /**
   * visPickerFilter  Provide the vis picker filter helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function visPickerFilter(analysis){
    const summary = artifactSummaryForIndex(analysis && analysis.index);
    const id = cleanDataId((summary && summary.dataId) || (analysis && analysis.id) || '');
    const names = ['VISdataMaster','VISdatamat'];
    const parts = [];
    names.forEach(name => {
      if(id){ parts.push(`*${name}*ID${id}*.mat`, `*${name}*_ID${id}*.mat`, `*${name}*${id}*.mat`); }
      parts.push(`*${name}*.mat`);
    });
    parts.push('*.mat');
    return Array.from(new Set(parts.filter(Boolean))).join(';');
  }
  /**
   * visArtifactFileSpec  Provide the vis artifact file spec helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function visArtifactFileSpec(paths){
    const files = arr(paths).filter(Boolean);
    const spec = {};
    if(!files.length) return spec;
    const firstName = String(files[0]).split(/[\/]/).pop();
    if(files.length === 1 && /VISdataMaster/i.test(firstName)) spec.visDataMasterFile = files[0];
    else spec.visDataFiles = files;
    return spec;
  }
  /**
   * pickArtifact  Provide the pick artifact helper used by visualization runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function pickArtifact(){
    const sel = selectedAnalyses();
    if(sel.length !== 1){ setMsg('Manual VISdata artifact override is available for one selected analysis at a time.', 'warning'); return; }
    const a = sel[0];
    const summary = artifactSummaryForIndex(a.index) || {};
    const id = cleanDataId(summary.dataId || a.id || '');
    const initial = summary.rootdir || a.rootdir || '';
    const filter = visPickerFilter(a);
    const title = id ? `Select VISdataMaster or CV2-level VISdatamats for ID${id}` : 'Select VISdataMaster or CV2-level VISdatamats';
    const out = await postJson('/api/pickpath', {kind:'file', multiple:true, initial, filter, title, timeout:600});
    const picked = arr(out && (out.paths || out.files || out.path || out.file)).filter(Boolean);
    if(picked.length){
      const current = manualVisPaths();
      const paths = window.NMManualArtifactFileList && typeof window.NMManualArtifactFileList.uniquePaths === 'function' ?
        window.NMManualArtifactFileList.uniquePaths(current.concat(picked)) : current.concat(picked);
      MANUAL_FILES = visArtifactFileSpec(paths);
      if(window.NMRunnerStateManager) window.NMRunnerStateManager.markChanged();
      const m = el('manualArtifactMode'); if(m) m.value = 'visdatamat';
      renderOptions();
    }
  }
  /**
   * workbenchReturnUrl  Provide the workbench return url helper used by visualization runtime runner page.
   * It supports visualization runtime runner page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workbenchReturnUrl(){
    const target = appContext().returnPage || 'nm_workbench.html';
    const sep = target.includes('?') ? '&' : '?';
    return `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`;
  }

  /**
   * finish  Provide the finish helper used by visualization runtime runner page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function finish(){
    if(RUNTIME_JOB_ACTIVE){ setMsg('Model visualization is still running in MATLAB. Close this browser tab to detach; do not finish the bridge session.', 'warning'); return; }
    try{
      if(window.NMRunnerStateManager) await window.NMRunnerStateManager.syncNow();
      if(isWorkbenchChild()){
        const out = await matlabService({operation:'app_child_return', source:'vis_runner', timeout:120});
        if(out && out.ok){ window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(workbenchReturnUrl()) : workbenchReturnUrl()); return; }
        throw new Error((out && (out.message || out.error)) || 'Returning to the workbench failed.');
      }
      await postJson('/api/close', {source:'vis_runner'});
      document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">Visualization-runner state saved. You can close this tab.</p>';
    } catch(err){ setMsg(`ERROR while closing visualization runner: ${err.message || String(err)}`, 'error'); }
  }
  /**
   * inspectInAnalysisManager  Provide the inspect in analysis manager helper used by visualization runtime runner page.
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
    ['operationMode','manualArtifactMode','cvrNorm','decompMode','overwriteExisting','operateAtCV1','saveParameters','loadParameters','writeCV2Maps','lowMemory'].forEach(id => { const x=el(id); if(x) x.addEventListener('change', renderOptions); });
    const p = el('pickArtifactFile'); if(p) p.addEventListener('click', () => pickArtifact().catch(e => setMsg(e.message,'error')));
    const run = el('runVisualization'); if(run) run.addEventListener('click', () => runVisualization().catch(e => setMsg(e.message,'error')));
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
      key:'vis_runner',
      snapshot:()=>{ const p=collectPlan(); return {analysisIndices:p.analysisIndices, gridAction:GRID_ACT, options:p.options}; },
      restore:async(saved)=>{
        if(!saved||typeof saved!=='object') return;
        const available=new Set(analyses().filter(a=>a.enabled!==false).map(a=>Number(a.index)));
        SELECTED=new Set(arr(saved.analysisIndices).map(Number).filter(i=>available.has(i)));
        if(Array.isArray(saved.gridAction)) GRID_ACT=saved.gridAction;
        const o=saved.options&&typeof saved.options==='object'?saved.options:{};
        const setValue=(id,value)=>{const x=el(id);if(x&&value!==undefined&&value!==null)x.value=String(value);};
        const setCheck=(id,value)=>{const x=el(id);if(x&&typeof value==='boolean')x.checked=value;};
        setValue('operationMode',o.operationMode); setValue('manualArtifactMode',o.manualArtifactMode);
        MANUAL_FILES=o.manualFiles&&typeof o.manualFiles==='object'?o.manualFiles:{}; MANUAL_FILE_LIST=null;
        setCheck('overwriteExisting',o.overwrite); setCheck('operateAtCV1',o.operateAtCV1); setCheck('saveParameters',o.saveParameters);
        setCheck('loadParameters',o.loadParameters); setCheck('writeCV2Maps',o.writeCV2Maps); setCheck('decompMode',o.decompMode); setCheck('lowMemory',o.lowMemory);
        setValue('cvrNorm',o.cvrNorm); setValue('simCorrMethod',o.simCorrMethod); setValue('simCorrThresh',o.simCorrThresh);
        setValue('corrCompCutoff',o.corrCompCutoff); setValue('selCompCutoff',o.selCompCutoff); setValue('pruneMode',o.pruneMode); setValue('pruneFraction',o.pruneFraction);
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
      // Workbench child pages may be exported with a lightweight bootstrap state.
      // Load the cheap analysis list first, then resolve slower VISdatamat scans.
      if(STATE.loading || STATE.analysesLoading){
        await refreshLight();
        await refresh();
      } else if(appContext().fastChildOpen){
        await refresh();
      }
    })().then(()=>window.NMRunnerStateManager?window.NMRunnerStateManager.markReady():undefined).catch(err=>setMsg(`Visualization runner refresh failed: ${err.message || String(err)}`, 'error'));
  });
})();
