(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_ANALYSIS_MANAGER_STATE || {};
  let SELECTED = null;
  let INSPECTION = null;
  let RUNTIME_SELECTION = {preprocess:false, trainML:false, preprocessOverwrite:false, trainOverwrite:false, trainStage:'auto'};
  let REQUEST_IN_FLIGHT = false;
  let RUNTIME_PROGRESS_VIEWER = null;
  let RUNTIME_JOB_CLIENT = null;
  // Mini-canvas node lookup. Popovers use the node.detail payload generated
  // by NMTrainTemplateOrchestrator, not a raw dump of SVG/card fields.
  let CANVAS_NODES = new Map();
  const CANVAS_DETAIL_IN_FLIGHT = new Set();

  /**
   * API  Build an absolute local HTTP bridge URL for a browser request.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function API(path){ return `${API_BASE}${path}`; }
  /**
   * appContext  Build the app context shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function appContext(){ return (STATE && STATE.appContext) || {}; }
  /**
   * isWorkbenchChild  Return whether the is workbench child condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isWorkbenchChild(){ const c = appContext(); return !!c.returnToWorkbench || String(c.caller || '').toLowerCase() === 'workbench'; }
  /**
   * workbenchReturnUrl  Provide the workbench return url helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workbenchReturnUrl(){ const c = appContext(); const page = c.returnPage || 'nm_workbench.html'; return page.includes('?') ? page : `${page}?port=${encodeURIComponent(PORT)}`; }
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
   * descText  Build the desc text shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function descText(x){ return Array.isArray(x) ? x.map((v)=>String(v == null ? '' : v)).join(' ') : String(x == null ? '' : x); }
  /**
   * truthy  Provide the truthy helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function truthy(x){ return !!x; }

  /**
   * setMsg  Route a status message to the page message strip.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * setDisabled  Provide the set disabled helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setDisabled(id, tf, title){
    const x = el(id);
    if(!x) return;
    x.disabled = !!tf;
    if(title) x.title = title;
    else x.removeAttribute('title');
  }
  /**
   * isLocked  Return whether the is locked condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function isLocked(){ return !!((STATE.defs || {}).analyses_locked); }
  /**
   * canEdit  Return whether the can edit condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function canEdit(){ return !!STATE.canEditTrainingAnalyses; }
  /**
   * selectedIndex  Apply the ed index selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedIndex(){ return SELECTED == null ? null : Number(SELECTED); }
  /**
   * statusLabel  Build the status label shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function statusLabel(v){
    if(v == null || Number.isNaN(Number(v))) return 'unknown';
    return Number(v) >= 1 ? 'completed' : 'configured/not completed';
  }
  /**
   * analysisArrays  Provide the analysis arrays helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function analysisArrays(){
    const a = STATE.analyses || {};
    return {idx: arr(a.indices), ids: arr(a.ids), desc: arr(a.descriptions), roots: arr(a.rootdirs), rootExists: arr(a.rootExists), status: arr(a.status)};
  }
  /**
   * maxTargetAnalysisIndex  Provide the max target analysis index helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function maxTargetAnalysisIndex(){
    const n = Number(((STATE.analyses || {}).count));
    if(Number.isFinite(n) && n >= 0) return Math.floor(n) + 1;
    const idx = analysisArrays().idx.map((v)=>Number(v)).filter((v)=>Number.isFinite(v));
    return (idx.length ? Math.max.apply(null, idx) : 0) + 1;
  }
  /**
   * updateAnalysisIndexBounds  Update analysis index bounds state or markup after user interaction or bridge refresh.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function updateAnalysisIndexBounds(){
    const x = el('analysisIndex');
    if(!x) return;
    const maxIdx = maxTargetAnalysisIndex();
    x.max = String(maxIdx);
    x.title = `Leave empty for next available index, or use an existing index up to ${maxIdx} to overwrite without creating gaps.`;
  }

  /**
   * postJson  Send a JSON request to the local MATLAB bridge and parse the JSON response.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postJson(path, payload, timeoutSec){
    const opts = {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload || {})};
    let timer = null;
    if(Number.isFinite(Number(timeoutSec)) && Number(timeoutSec) > 0 && typeof AbortController !== 'undefined') {
      const controller = new AbortController();
      opts.signal = controller.signal;
      timer = setTimeout(()=>controller.abort(), Math.max(1000, Math.round(Number(timeoutSec) * 1000)));
    }
    try{
      const response = await fetch(API(path), opts);
      const txt = await response.text();
      let obj = {};
      try { obj = JSON.parse(txt || '{}'); }
      catch(err) { throw new Error(`Browser bridge returned non-JSON for ${path}: ${(txt || '').slice(0,300)}`); }
      if(obj && typeof obj === 'object' && !obj.httpStatus) obj.httpStatus = response.status;
      return obj;
    } catch(err){
      if(err && err.name === 'AbortError') throw new Error(`Browser request to ${path} timed out before MATLAB returned a result.`);
      throw err;
    } finally {
      if(timer) clearTimeout(timer);
    }
  }
  /**
   * matlabService  Send a MATLAB-service request through the browser bridge.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function matlabService(operation, extra){
    const body = Object.assign({operation, timeout:120}, extra || {});
    const clientTimeout = Math.max(10, Number(body.timeout || 120) + 10);
    return postJson('/api/matlabservice', body, clientTimeout);
  }
  function runtimeJobClient(){
    if(!RUNTIME_JOB_CLIENT && window.NMRuntimeJobClient){
      RUNTIME_JOB_CLIENT = new window.NMRuntimeJobClient({
        port:PORT, storageKey:`nm2_analysis_manager_runtime_job_${PORT}`, pollMs:750
      });
    }
    return RUNTIME_JOB_CLIENT;
  }
  function runtimeProgressViewer(){
    if(!RUNTIME_PROGRESS_VIEWER && window.NMRuntimeProgressViewer){
      RUNTIME_PROGRESS_VIEWER = new window.NMRuntimeProgressViewer({
        port:PORT, title:'NM Runtime Progress Viewer',
        overallTitle:'Overall CV2 progress', lowerTitle:'Runtime progress', pollMs:80
      });
    }
    return RUNTIME_PROGRESS_VIEWER;
  }
  /**
   * syncCurrent  Synchronize the current browser state with related controls.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function syncCurrent(){ await postJson('/api/current', STATE, 30); }

  /**
   * defaultSpec  Provide the default spec helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function defaultSpec(){ return STATE.defaultCreateSpec || {}; }
  /**
   * fillDefaults  Provide the fill defaults helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function fillDefaults(){
    const d = defaultSpec();
    // Interactive analysis creation intentionally keeps ID and description empty.
    // Programmatic API defaults must not leak into the browser form.
    if(el('analysisParentDir') && !el('analysisParentDir').value) el('analysisParentDir').value = d.parentdir || '';
  }
  /**
   * createSpec  Create the spec component or browser-side state object.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createSpec(){
    const spec = {};
    spec.id = el('analysisId') ? el('analysisId').value.trim() : '';
    if(!spec.id) throw new Error('Analysis ID is required.');
    const desc = el('analysisDescription') ? el('analysisDescription').value.trim() : '';
    if(!desc) throw new Error('Analysis description is required.');
    spec.description = desc.split(/\n+/);
    const pd = el('analysisParentDir') ? el('analysisParentDir').value.trim() : '';
    if(!pd) throw new Error('Analysis parent directory is required.');
    spec.parentdir = pd;
    const idxRaw = el('analysisIndex') ? el('analysisIndex').value.trim() : '';
    const idx = idxRaw ? Number(idxRaw) : NaN;
    if(idxRaw && (!Number.isFinite(idx) || idx < 1)) throw new Error('Target analysis index must be a positive integer.');
    if(idxRaw && Math.round(idx) > maxTargetAnalysisIndex()) throw new Error(`Target analysis index cannot exceed ${maxTargetAnalysisIndex()}; larger values would create gaps in NM.analysis.`);
    if(Number.isFinite(idx) && idx >= 1) spec.analdim = Math.round(idx);
    spec.overwrite = 'complete_reset';
    return spec;
  }

  /**
   * createDisabledReason  Create the disabled reason component or browser-side state object.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createDisabledReason(){
    if(STATE.canCreate) return '';
    const defs = STATE.defs || {};
    if(!defs.import_finished) return 'Cannot create analysis: finalize the training data import first.';
    if(defs.analyses_locked) return 'Cannot create analysis: application/OOCV mode is active and training analyses are locked.';
    return 'Cannot create analysis: the current NM state is not in editable training-configuration mode.';
  }

  /**
   * formCreateDisabledReason  Provide the form create disabled reason helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function formCreateDisabledReason(){
    const id = el('analysisId') ? el('analysisId').value.trim() : '';
    const desc = el('analysisDescription') ? el('analysisDescription').value.trim() : '';
    const pd = el('analysisParentDir') ? el('analysisParentDir').value.trim() : '';
    if(!id) return 'Enter a non-empty analysis ID.';
    if(!desc) return 'Enter a non-empty analysis description.';
    if(!pd) return 'Select or enter a parent directory.';
    const idxRaw = el('analysisIndex') ? el('analysisIndex').value.trim() : '';
    const idx = idxRaw ? Number(idxRaw) : NaN;
    if(idxRaw && (!Number.isFinite(idx) || idx < 1)) return 'Target analysis index must be a positive integer.';
    if(idxRaw && Math.round(idx) > maxTargetAnalysisIndex()) return `Target analysis index cannot exceed ${maxTargetAnalysisIndex()}; larger values would create gaps in NM.analysis.`;
    return '';
  }

  /**
   * setCreateFeedback  Provide the set create feedback helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setCreateFeedback(){
    const stateReason = createDisabledReason();
    const formReason = stateReason ? '' : formCreateDisabledReason();
    const reason = stateReason || formReason;
    if(el('createHint')) el('createHint').textContent = stateReason || 'Creates or overwrites an analysis snapshot from the current training template.';
    const title = REQUEST_IN_FLIGHT ? 'A MATLAB analysis-manager request is already running.' :
      (reason ? (stateReason || 'Complete the mandatory analysis-creation fields and use a target index that does not create NM.analysis gaps.') :
      'Create or overwrite an analysis snapshot at the selected target index.');
    setDisabled('createAnalysis', !!reason || REQUEST_IN_FLIGHT, title);
    return reason;
  }

  /**
   * setBusy  Provide the set busy helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setBusy(tf, message){
    REQUEST_IN_FLIGHT = !!tf;
    ['createAnalysis','pickAnalysisParentDir','activateApplicationMode','finish'].forEach((id)=>{
      const x = el(id);
      if(!x) return;
      x.disabled = REQUEST_IN_FLIGHT;
      if(REQUEST_IN_FLIGHT) x.title = message || 'A MATLAB analysis-manager request is already running.';
      else if(id !== 'createAnalysis') x.title = '';
    });
    setCreateFeedback();
  }

  /**
   * actionButton  Provide the action button helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function actionButton(label, action, disabled, title, cssClass){
    const tt = title ? ` title="${esc(title)}"` : '';
    const cls = cssClass ? ` class="${esc(cssClass)}"` : '';
    return `<button type="button" data-action="${esc(action)}" ${disabled?'disabled':''}${tt}${cls}>${esc(label)}</button>`;
  }

  /**
   * updateLayoutState  Update layout state state or markup after user interaction or bridge refresh.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function updateLayoutState(){
    const open = !!INSPECTION;
    const panel = el('analysisManagerPanel');
    const layout = document.querySelector('.amLayout');
    if(panel) panel.classList.toggle('amInspectionOpen', open);
    if(layout) layout.classList.toggle('amInspectionOpen', open);
  }

  /**
   * renderApplicationTransition  Render the application transition UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderApplicationTransition(defs){
    const block = el('applicationTransitionBlock');
    if(!block) return;
    const show = !!STATE.showApplicationTransition;
    block.hidden = !show;
    block.classList.toggle('hidden', !show);
    if(el('applicationSummary')) {
      el('applicationSummary').textContent = defs.analyses_locked ?
        'Application/OOCV mode is already active.' :
        (STATE.canActivateApplicationMode ? 'At least one completed analysis is available. Application/OOCV mode can be activated.' : 'Completed analysis detected, but application/OOCV activation is currently not available.');
    }
    setDisabled('activateApplicationMode', !STATE.canActivateApplicationMode,
      STATE.canActivateApplicationMode ? '' : 'Requires finalized training import, unlocked training configuration mode, and at least one completed analysis.');
  }

  /**
   * renderAnalysisCard  Render the analysis card UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * data.desc: browser-side field consumed from data while translating UI state to MATLAB-service requests.
   * data.ids: browser-side field consumed from data while translating UI state to MATLAB-service requests.
   * data.rootExists: browser-side field consumed from data while translating UI state to MATLAB-service requests.
   * data.roots: browser-side field consumed from data while translating UI state to MATLAB-service requests.
   * data.status: browser-side field consumed from data while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderAnalysisCard(index, i, data){
    const card = document.createElement('article');
    const expanded = Number(index) === Number(SELECTED);
    const completed = Number(data.status[i]) >= 1;
    const hasRoot = !!data.roots[i];
    const rootExists = data.rootExists[i] === true || data.rootExists[i] === 1 || data.rootExists[i] === 'true';
    const rootStale = hasRoot && !rootExists;
    const labels = STATE.actionLabels || {};
    const locked = isLocked();
    card.className = 'amAnalysisCard' + (rootStale ? ' staleRoot' : '');
    card.tabIndex = 0;
    card.dataset.analysisIndex = String(index);
    card.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    const staleBadge = rootStale ? '<span class="amStaleBadge">stale path</span>' : '';
    const header = `<div class="amAnalysisCardHeader"><div class="amAnalysisCardHeaderInner"><b class="amAnalysisTitle">Analysis ${esc(index)}: ${esc(data.ids[i] || '')}</b>${staleBadge}</div></div>`;
    const body = `<div class="amAnalysisCardBody"><div class="amAnalysisCardBodyInner">` +
      `<div class="amCardSummary"><div><span class="muted">Status:</span> ${esc(statusLabel(data.status[i]))}</div>` +
      `<div><span class="muted">Description:</span> ${esc(descText(data.desc[i]) || '(not set)')}</div>` +
      `<div><span class="muted">Output path:</span> ${esc(data.roots[i] || '(not set)')}</div>` +
      `${rootStale ? '<div class="amPathWarning">Stored analysis path is stale. Runtime runners are disabled until the analysis root is relinked.</div>' : ''}</div>` +
      `<div class="actions inlineActions amActionRow">` +
      actionButton(labels.inspect || 'Inspect analysis configuration', 'inspect', false, '') +
      actionButton(labels.methodsSummary, 'export_methods', false, 'Save a Methods summary from the selected analysis snapshot.') +
      actionButton(labels.reset || 'Reset using current NM parameter template', 'reset', !canEdit() || !hasRoot || rootStale, rootStale ? 'Stored analysis root is stale. Relink the analysis before resetting parameters.' : (!hasRoot ? 'No analysis root is recorded. Relink the analysis before resetting parameters.' : (canEdit() ? '' : 'Requires finalized training import and unlocked training configuration mode.'))) +
      actionButton(labels.restoreTemplate || 'Reset current NM parameter template from this analysis', 'restore_template', locked, locked ? 'Disabled in application/OOCV mode.' : 'Overwrite the active NM TrainParam/CV template with this analysis snapshot.') +
      actionButton(labels.delete || 'Delete', 'delete', locked, locked ? 'Disabled in application/OOCV mode.' : '') +
      actionButton(labels.deleteWipe || 'Delete and wipe from disk', 'delete_wipe', locked || !hasRoot || rootStale, locked ? 'Disabled in application/OOCV mode.' : (rootStale ? 'Analysis root path is stale. Relink before wiping from disk.' : (hasRoot ? '' : 'No analysis output folder is recorded.'))) +
      (rootStale ? actionButton(labels.relinkRoot || 'Relink analysis root', 'relink_root', false, 'Select either the exact relocated analysis folder or its immediate parent. NeuroMiner will resolve and report the interpretation.') : '') +
      `<span class="amRuntimeHint muted">Runtime actions are selected in the inspection panel.</span>` +
      `</div></div></div>`;
    card.innerHTML = header + body;
    if(expanded) card.classList.add('amPendingSelected');
    card.onclick = (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest('button[data-action]') : null;
      if(btn) return;
      toggleAnalysisCard(index, card);
    };
    card.onkeydown = (ev)=>{ if(ev.key === 'Enter' || ev.key === ' '){ toggleAnalysisCard(index, card); ev.preventDefault(); } };
    return card;
  }

  /**
   * clearBodyAnim  Clear the body anim UI state, cache or rendered content.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function clearBodyAnim(body){
    if(body && body._amAnimEnd){
      body.removeEventListener('transitionend', body._amAnimEnd);
      body._amAnimEnd = null;
    }
  }

  /**
   * expandAnalysisCard  Provide the expand analysis card helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function expandAnalysisCard(card){
    if(!card) return;
    const body = card.querySelector('.amAnalysisCardBody');
    card.setAttribute('aria-expanded', 'true');
    if(!body){ card.classList.add('selected'); return; }

    clearBodyAnim(body);
    // Render the body so it can be measured at its true wrapped height.
    card.classList.add('amAnimating');
    card.classList.add('selected');
    body.style.maxHeight = '0px';
    // Force a reflow so the browser registers the 0px starting point,
    // then animate to the measured natural height on the next frame.
    void body.offsetHeight;
    window.requestAnimationFrame(()=>{
      const target = body.scrollHeight;
      body.style.maxHeight = target + 'px';
      /**
       * onEnd  Provide the on end helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
       * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
       * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
       */
      const onEnd = (ev)=>{
        if(ev.target !== body || ev.propertyName !== 'max-height') return;
        // Release the cap so later text/layout changes never get clipped.
        body.style.maxHeight = 'none';
        card.classList.remove('amAnimating');
        clearBodyAnim(body);
      };
      body._amAnimEnd = onEnd;
      body.addEventListener('transitionend', onEnd);
    });
    // Keep the expanded card visible by scrolling the LIST only — never the
    // page. Nudge after the open animation so the measured height is settled.
    window.setTimeout(()=>{ scrollCardIntoList(card); }, 340);
  }

  // Scrolls the analysis list (not the page) so the card's header is visible
  // and, if it fits, its body too. Does nothing if already in view.
  /**
   * scrollCardIntoList  Provide the scroll card into list helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function scrollCardIntoList(card){
    const list = el('analysisList');
    if(!list || !card) return;
    const cardTop = card.offsetTop;                     // relative to list content
    const cardBottom = cardTop + card.offsetHeight;
    const viewTop = list.scrollTop;
    const viewBottom = viewTop + list.clientHeight;
    if(cardTop < viewTop){
      list.scrollTo({ top: cardTop - 8, behavior: 'smooth' });
    } else if(cardBottom > viewBottom){
      // Prefer showing the whole card; if too tall, pin its top.
      const target = (card.offsetHeight + 16 <= list.clientHeight)
        ? cardBottom - list.clientHeight + 8
        : cardTop - 8;
      list.scrollTo({ top: target, behavior: 'smooth' });
    }
  }

  /**
   * collapseAnalysisCard  Provide the collapse analysis card helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function collapseAnalysisCard(card){
    if(!card) return;
    const body = card.querySelector('.amAnalysisCardBody');
    card.setAttribute('aria-expanded', 'false');
    if(!body){ card.classList.remove('selected'); return; }

    clearBodyAnim(body);
    card.classList.add('amAnimating');
    // Pin the current height (it may be 'none'), then animate down to 0.
    body.style.maxHeight = body.scrollHeight + 'px';
    void body.offsetHeight;
    card.classList.remove('selected');
    window.requestAnimationFrame(()=>{
      body.style.maxHeight = '0px';
      /**
       * onEnd  Provide the on end helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
       * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
       * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
       */
      const onEnd = (ev)=>{
        if(ev.target !== body || ev.propertyName !== 'max-height') return;
        card.classList.remove('amAnimating');  // display:none reasserts; body is hidden
        body.style.maxHeight = '';
        clearBodyAnim(body);
      };
      body._amAnimEnd = onEnd;
      body.addEventListener('transitionend', onEnd);
    });
  }

  /**
   * toggleAnalysisCard  Toggle the analysis card UI state and keep dependent controls synchronized.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function toggleAnalysisCard(index, card){
    const ix = Number(index);
    if(Number(SELECTED) === ix){
      SELECTED = null;
      collapseAnalysisCard(card);
      return;
    }
    SELECTED = ix;
    render();
  }

  /**
   * renderAnalysisList  Render the analysis list UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderAnalysisList(){
    const list = el('analysisList');
    if(!list) return;
    const data = analysisArrays();
    list.innerHTML = '';
    if(!data.idx.length){
      list.innerHTML = '<div class="amEmptyState muted">No analyses are configured.</div>';
      return;
    }
    data.idx.forEach((v,i)=>list.appendChild(renderAnalysisCard(v, i, data)));
    const selectedCard = list.querySelector('.amPendingSelected');
    if(selectedCard){
      selectedCard.classList.remove('amPendingSelected');
      expandAnalysisCard(selectedCard);
    }
  }

  /**
   * renderInspectionPanel  Render the inspection panel UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderInspectionPanel(){
    const panel = el('analysisInspectionPanel');
    const content = el('analysisInspectionContent');
    if(!panel || !content) return;
    const show = !!INSPECTION;
    panel.hidden = !show;
    panel.classList.toggle('hidden', !show);
    updateLayoutState();
    if(!INSPECTION){
      content.innerHTML = '<div class="muted">Select an analysis and click Inspect analysis configuration.</div>';
      return;
    }
    const s = INSPECTION.summary || {};
    const cfg = INSPECTION.configuration || {};
    const res = INSPECTION.results || {};
    const canvas = INSPECTION.canvas || {};
    const pathWarning = res.rootExists === false ? '<div class="amPathWarning">Stored analysis path is stale. NM Results Viewer remains available for completed analyses, but runtime runners are disabled until the root is relinked.</div>' : '';
    content.innerHTML =
      `<section class="amInspectSection"><h3>Configuration summary</h3>${keyValueGrid([
        ['Analysis', `${s.index || ''}: ${s.id || ''}`],
        ['Description', s.description || '(not set)'],
        ['Status', s.statusLabel || statusLabel(s.status)],
        ['Label', `${s.labelname || '?'} (${s.modeflag || '?'})`],
        ['Modalities', cfg.modalities],
        ['Root directory', s.rootdir || '(not set)']
      ])}${keyValueGrid([
        ['Fusion', cfg.fusion], ['Preprocessing', cfg.preprocessing], ['Learner', cfg.machineLearning],
        ['Ensemble/RFE', cfg.ensemble], ['Visualization', cfg.visualization], ['MLI', cfg.mli], ['Saving', cfg.saving]
      ])}</section>` +
      `${renderRuntimePanel(INSPECTION.runtime || {})}` +
      `<section class="amInspectSection"><h3>Read-only configuration canvas</h3>${renderMiniCanvas(canvas)}</section>` +
      `<section class="amInspectSection"><h3>Results overview</h3>${pathWarning}${keyValueGrid([
        ['Completed', yesNo(res.completed)], ['Root folder exists', yesNo(res.rootExists)],
        ['Parameter file exists', yesNo(res.paramFileExists)], ['Log file exists', yesNo(res.logFileExists)],
        ['Model results', res.modelPerformanceSummary || yesNo(res.hasGDdims)], ['Visualization data', yesNo(res.hasVisdata)],
        ['MLI data', yesNo(res.hasMLI)], ['Model export data', yesNo(res.hasModelData)], ['OOCV results', yesNo(res.hasOOCV)]
      ])}<div class="actions amResultsActions">${actionButton('Open NM2 Results Viewer', 'open_results_viewer', !res.canOpenResultsViewer, res.resultsViewerReason || '')}</div></section>`;
  }
  /**
   * keyValueGrid  Resolve the key value grid identifier used to connect UI state with NeuroMiner payload metadata.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function keyValueGrid(rows){
    return `<div class="amKeyValueGrid">${rows.map((r)=>`<div>${esc(r[0])}</div><div>${esc(r[1] == null ? '' : r[1])}</div>`).join('')}</div>`;
  }
  /**
   * yesNo  Provide the yes no helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function yesNo(v){ return truthy(v) ? 'yes' : 'no'; }

  /**
   * runtimeAction  Provide the runtime action helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeAction(runtime, key){
    const actions = runtime && runtime.actions ? runtime.actions : {};
    return actions[key] || {};
  }

  /**
   * renderRuntimePanel  Render the runtime panel UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRuntimePanel(runtime){
    const prep = runtimeAction(runtime, 'preprocess');
    const train = runtimeAction(runtime, 'trainML');
    const prepSelected = !!RUNTIME_SELECTION.preprocess && !!prep.enabled;
    const trainSelected = !!RUNTIME_SELECTION.trainML && !!train.enabled;
    const prepOverwriteNeeded = !!(prepSelected && prep.requiresOverwrite && !RUNTIME_SELECTION.preprocessOverwrite);
    const trainOverwriteNeeded = !!(trainSelected && train.requiresOverwrite && !RUNTIME_SELECTION.trainOverwrite);
    const combinedPlan = prepSelected && trainSelected;
    const trainMode = runtimeTrainMode(runtime);
    const trainStage = runtimeTrainStageState(runtime);
    const trainStageValid = !trainSelected || trainStage.valid;
    const trainStageBlocked = trainSelected && !trainStage.valid;
    const trainModeLabel = trainMode === 'results' ? 'existing CVresults' : (trainMode === 'datamat' ? 'existing CVdatamat' : (trainMode === 'preproc' ? 'existing PreprocData' : 'compute from scratch'));
    const canRun = (prepSelected || trainSelected) && !prepOverwriteNeeded && !trainOverwriteNeeded && !trainStageBlocked;
    const prepOverwriteHtml = prep.hasExistingResults ?
      `<label class="amRuntimeOverwrite"><input id="runtimePreprocessOverwrite" type="checkbox" ${RUNTIME_SELECTION.preprocessOverwrite ? 'checked' : ''}> Allow overwrite existing PreprocData artifacts</label>` : '';
    const trainOverwriteHtml = train.hasExistingResults ?
      `<label class="amRuntimeOverwrite"><input id="runtimeTrainOverwrite" type="checkbox" ${RUNTIME_SELECTION.trainOverwrite ? 'checked' : ''}> Allow overwrite existing training results</label>` : '';
    const runTitle = canRun ? 'Run selected runtime actions.' :
      (combinedPlan ? 'Run preprocessing first, then Train ML from refreshed PreprocData in one chained runtime plan.' :
      (trainStageBlocked ? trainStage.reason :
      (prepOverwriteNeeded ? 'Existing PreprocData artifacts require explicit overwrite confirmation.' :
      (trainOverwriteNeeded ? 'Existing model results require explicit overwrite confirmation.' : 'Select at least one feasible runtime action.'))));
    return `<section class="amInspectSection amRuntimeSection"><h3>Runtime actions</h3>` +
      `<div class="amRuntimePlanNote">Runtime action state is shared by the browser session and delegates to NMRuntimeActionTools. Train ML can use existing CVresults, CVdatamat or PreprocData artifacts when available. Combined Preprocessing → Train ML runs preprocessing first and then trains from refreshed PreprocData.</div>` +
      renderRuntimeArtifacts(runtime.artifacts || {}) +
      `<div class="amRuntimeActions">` +
      renderRuntimeToggle('preprocess', prep, RUNTIME_SELECTION.preprocess) +
      renderRuntimeToggle('trainML', train, RUNTIME_SELECTION.trainML) +
      `</div>${prepOverwriteHtml}${trainOverwriteHtml}` +
      renderRuntimeTrainStageSelector(runtime, trainStage) +
      `<div class="amRuntimeOptions"><span><b>Preprocessing grid action:</b> all CV2 grids</span><span><b>Train ML grid action:</b> all CV2 grids</span><span><b>Train ML mode:</b> ${esc(trainModeLabel)}</span><span><b>Artifact recommendation:</b> ${esc((runtime.artifacts || {}).recommendedTrainEntryPoint || 'scratch')}</span></div>` +
      `${combinedPlan ? `<div class="amRuntimeReason ok">Combined Preprocessing → Train ML. Combined plan: preprocessing will run first; Train ML will then use refreshed PreprocData.</div>` : ''}` +
      `${trainStageBlocked ? `<div class="amRuntimeReason muted">Train ML input stage unavailable: ${esc(trainStage.reason)}</div>` : ''}` +
      `<div class="actions amRuntimeRunRow"><button type="button" class="amRunSelectedButton" data-action="run_runtime_plan" ${canRun ? '' : 'disabled'} title="${esc(runTitle)}">Run selected runtime actions</button></div>` +
      `${prep.disabledReason && !prep.enabled ? `<div class="amRuntimeReason muted">Preprocessing disabled: ${esc(prep.disabledReason)}</div>` : ''}` +
      `${train.disabledReason && !train.enabled ? `<div class="amRuntimeReason muted">Train ML disabled: ${esc(train.disabledReason)}</div>` : ''}` +
      `</section>`;
  }

  /**
   * renderRuntimeArtifacts  Render the runtime artifacts UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRuntimeArtifacts(artifacts){
    const rows = [
      artifactRow('PreprocData', artifacts.preprocData),
      artifactRow('CVdatamat', artifacts.cvDatamat),
      artifactRow('CVresults', artifacts.cvResults),
      artifactRow('CVdimanalysis', artifacts.cvDimAnalysis)
    ].join('');
    return `<div class="amRuntimeArtifacts"><div class="amRuntimeArtifactsTitle">Runtime artifacts</div>${rows}</div>`;
  }

  /**
   * artifactRow  Provide the artifact row helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function artifactRow(label, artifact){
    artifact = artifact || {};
    const status = artifact.available ? (artifact.coverageText || 'available') : 'not found';
    const title = artifact.reason || '';
    return `<div class="amRuntimeArtifactRow" title="${esc(title)}"><span>${esc(label)}</span><span>${esc(status)}</span></div>`;
  }

  /**
   * renderRuntimeToggle  Render the runtime toggle UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRuntimeToggle(key, action, selected){
    action = action || {};
    const enabled = !!action.enabled && !!action.wired;
    const label = action.label || key;
    const reason = enabled ? (action.enabledReason || '') : (action.disabledReason || 'Runtime action is not available.');
    const checked = selected && enabled ? 'checked' : '';
    const disabled = enabled ? '' : 'disabled';
    return `<label class="amRuntimeToggle ${enabled ? '' : 'disabled'}" title="${esc(reason)}">` +
      `<input type="checkbox" name="runtimeAction_${esc(key)}" data-runtime-action="${esc(key)}" ${checked} ${disabled}>` +
      `<span class="amRuntimeToggleLabel">${esc(label)}</span>` +
      `<span class="amRuntimeToggleReason">${esc(reason)}</span>` +
      `</label>`;
  }

  /**
   * renderRuntimeTrainStageSelector  Render the runtime train stage selector UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderRuntimeTrainStageSelector(runtime, stageState){
    stageState = stageState || runtimeTrainStageState(runtime);
    const opts = [
      {value:'auto', label:'Auto', enabled:true, reason:'Use the best available artifact stage.'},
      {value:'scratch', label:'Scratch / on-the-fly', enabled:true, reason:'Compute from raw analysis inputs.'},
      {value:'preproc', label:'Existing PreprocData', enabled:!!stageState.available.preproc, reason:stageState.available.preproc ? 'Complete PreprocData artifacts are available.' : 'PreprocData artifacts are not complete.'},
      {value:'datamat', label:'Existing CVdatamat', enabled:!!stageState.available.datamat, reason:stageState.available.datamat ? 'Complete CVdatamat artifacts are available.' : 'CVdatamat artifacts are not complete.'},
      {value:'results', label:'Existing CVresults', enabled:!!stageState.available.results, reason:stageState.available.results ? 'Complete CVresults artifacts are available.' : 'CVresults artifacts are not complete.'}
    ];
    const optionHtml = opts.map((o)=>`<option value="${esc(o.value)}" ${RUNTIME_SELECTION.trainStage === o.value ? 'selected' : ''} ${o.enabled ? '' : 'disabled'} title="${esc(o.reason)}">${esc(o.label)}</option>`).join('');
    return `<label class="amRuntimeStageSelector"><span>Train ML input stage</span><select id="runtimeTrainStage">${optionHtml}</select><em>${esc(stageState.reason || 'Select which existing artifact stage Train ML should use.')}</em></label>`;
  }

  /**
   * runtimeTrainStageState  Provide the runtime train stage state helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeTrainStageState(runtime){
    runtime = runtime || {};
    const artifacts = runtime.artifacts || {};
    const available = {
      preproc: !!(artifacts.preprocData && artifacts.preprocData.available),
      datamat: !!(artifacts.cvDatamat && artifacts.cvDatamat.available),
      results: !!(artifacts.cvResults && artifacts.cvResults.available)
    };
    const selected = RUNTIME_SELECTION.trainStage || 'auto';
    const autoMode = runtimeAutoTrainMode(runtime);
    const mode = selected === 'auto' ? autoMode : selected;
    let valid = true;
    let reason = selected === 'auto' ? `Auto-selected ${runtimeTrainStageLabel(autoMode)}.` : `Selected ${runtimeTrainStageLabel(mode)}.`;
    if(mode === 'preproc' && !available.preproc) { valid = false; reason = 'PreprocData artifacts are not complete.'; }
    if(mode === 'datamat' && !available.datamat) { valid = false; reason = 'CVdatamat artifacts are not complete.'; }
    if(mode === 'results' && !available.results) { valid = false; reason = 'CVresults artifacts are not complete.'; }
    if(mode === 'scratch') { valid = true; reason = selected === 'auto' ? 'Auto-selected scratch/on-the-fly training.' : 'Selected scratch/on-the-fly training.'; }
    return {selected, mode, valid, reason, available};
  }

  /**
   * runtimeTrainStageLabel  Build the runtime train stage label shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeTrainStageLabel(mode){
    if(mode === 'datamat') return 'existing CVdatamat';
    if(mode === 'preproc') return 'existing PreprocData';
    if(mode === 'results') return 'existing CVresults';
    return 'scratch/on-the-fly';
  }

  /**
   * runtimeAutoTrainMode  Provide the runtime auto train mode helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeAutoTrainMode(runtime){
    const train = runtimeAction(runtime || {}, 'trainML');
    if(train && train.recommendedOperationMode === 'results') return 'results';
    if(train && train.recommendedOperationMode === 'datamat') return 'datamat';
    if(train && train.recommendedOperationMode === 'preproc') return 'preproc';
    const artifacts = runtime && runtime.artifacts ? runtime.artifacts : {};
    if(artifacts.cvResults && artifacts.cvResults.available) return 'results';
    if(artifacts.cvDatamat && artifacts.cvDatamat.available) return 'datamat';
    return artifacts.preprocData && artifacts.preprocData.available ? 'preproc' : 'scratch';
  }

  /**
   * runtimeTrainMode  Provide the runtime train mode helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimeTrainMode(runtime){
    return runtimeTrainStageState(runtime).mode;
  }

  /**
   * runtimePlanFromSelection  Provide the runtime plan from selection helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runtimePlanFromSelection(index){
    const actions = [];
    if(RUNTIME_SELECTION.preprocess) actions.push('preprocess');
    if(RUNTIME_SELECTION.trainML) actions.push('trainML');
    const runtime = INSPECTION && INSPECTION.runtime ? INSPECTION.runtime : {};
    let trainMode = runtimeTrainMode(runtime);
    if(actions.includes('preprocess') && actions.includes('trainML')) trainMode = 'preproc';
    return {analysisIndex:Number(index), actions, options:{preprocess:{gridAction:'all', useExisting:true, overwrite:!!RUNTIME_SELECTION.preprocessOverwrite, savePreproc:true, writeParameters:false, useExistingParameters:true, hideGrid:true}, trainML:{gridAction:'all', operationMode:trainMode, useExisting:true, requireComplete:true, overwrite:!!RUNTIME_SELECTION.trainOverwrite, update:true, hideGrid:true}}};
  }

  /**
   * renderMiniCanvas  Render the mini canvas UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderMiniCanvas(canvas){
    const rawNodes = arr(canvas.nodes).filter((n)=>n && n.id);
    const edges = arr(canvas.edges).filter((e)=>e && e.source && e.target);
    CANVAS_NODES = new Map();
    rawNodes.forEach((n)=>CANVAS_NODES.set(String(n.id || ''), n));
    const msg = canvas.message ? `<div class="muted amCanvasMessage">${esc(canvas.message)}</div>` : '';
    if(!rawNodes.length) return `<div class="amMiniCanvas empty">No canvas nodes available.</div>${msg}`;
    const layout = miniCanvasLayout(rawNodes);
    const defs = '<defs><marker id="amMiniArrow" markerWidth="10" markerHeight="10" refX="9" refY="5" orient="auto-start-reverse" viewBox="0 0 10 10"><path d="M0,0 L10,5 L0,10 z"></path></marker></defs>';
    const scopeSvg = layout.scopeNodes.map((n)=>{
      const b = layout.scopeBounds.get(String(n.id || ''));
      if(!b) return '';
      const rawTitle = String(n.title || n.columnLabel || '').trim();
      const title = rawTitle || (String(n.id || '').toLowerCase().includes('cv') ? 'Cross-validation / partitioning' : 'Configuration scope');
      const sub = String(n.subtitle || n.summary || '').trim();
      const headerW = Math.min(Math.max(230, title.length * 7.2 + 34), Math.max(180, b.w - 44));
      const header = `<rect x="${b.x + 18}" y="${b.y + 12}" width="${headerW}" height="24" rx="7" ry="7" class="amMiniScopeHeaderBox"></rect>` +
        miniSvgTextLines(title, b.x + 30, b.y + 28, 'amMiniScopeTitle', headerW - 24, 1, 13, 11.5) +
        miniSvgTextLines(sub, b.x + 30, b.y + 49, 'amMiniScopeSub', b.w - 60, 1, 12, 10);
      return `<g class="amMiniScope amMiniStatus-${miniStatus(n.status)}"><rect x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" rx="22" ry="22"></rect>${header}</g>`;
    }).join('');
    const containerSvg = layout.flowNodes.map((n)=>{
      if(String(n.shape || '') !== 'container') return '';
      const b = layout.containerBounds.get(String(n.id || ''));
      if(!b) return '';
      const title = miniSvgTextLines(n.title || 'Ensemble learning', b.x + 18, b.y + 28, 'amMiniContainerTitle', b.w - 36, 1, 13, 11.5);
      const sub = miniSvgTextLines(n.subtitle || '', b.x + 18, b.y + 46, 'amMiniContainerSub', b.w - 36, 1, 12, 10);
      return `<g class="amMiniContainer amMiniNode amMiniStatus-${miniStatus(n.status)}" data-node-id="${esc(String(n.id || ''))}" tabindex="0" role="button"><rect x="${b.x}" y="${b.y}" width="${b.w}" height="${b.h}" rx="18" ry="18"></rect>${title}${sub}</g>`;
    }).join('');
    const edgeSvg = edges.map((e)=>{
      if(String(e.kind || '') === 'cv_context') return '';
      const d = miniCanvasEdgePath(e, layout);
      if(!d) return '';
      return `<path class="amMiniEdge ${esc(String(e.kind || 'flow'))}" d="${d}" marker-end="url(#amMiniArrow)"></path>`;
    }).join('');
    const nodeSvg = layout.flowNodes.map((n)=>{
      if(String(n.shape || '') === 'container') return '';
      const p = layout.pos.get(String(n.id || ''));
      if(!p) return '';
      const shape = String(n.shape || 'box');
      const status = miniStatus(n.status);
      const accent = esc(String(n.accent || n.group || '').replace(/[^a-zA-Z0-9_-]/g,''));
      let body = '';
      if(shape === 'diamond'){
        const pts = `${p.x + p.w/2},${p.y} ${p.x + p.w},${p.y + p.h/2} ${p.x + p.w/2},${p.y + p.h} ${p.x},${p.y + p.h/2}`;
        body += `<polygon points="${pts}" class="amMiniNodeBox"></polygon>`;
        body += `<line x1="${p.x + 22}" y1="${p.y + p.h - 14}" x2="${p.x + p.w - 22}" y2="${p.y + p.h - 14}" class="amMiniNodeStripe"></line>`;
      } else {
        const rx = shape === 'roundbox' ? 18 : 10;
        body += `<rect x="${p.x}" y="${p.y}" width="${p.w}" height="${p.h}" rx="${rx}" ry="${rx}" class="amMiniNodeBox"></rect>`;
        body += `<line x1="${p.x + 6}" y1="${p.y + 12}" x2="${p.x + 6}" y2="${p.y + p.h - 12}" class="amMiniNodeStripe"></line>`;
      }
      const txt = miniCanvasNodeText(n);
      let ty = p.y + 20;
      if(txt.title){ body += miniSvgTextLines(txt.title, p.x + 18, ty, 'amMiniNodeTitle', p.w - 34, 1, 12, 11); ty += 17; }
      if(txt.subtitle){ body += miniSvgTextLines(txt.subtitle, p.x + 18, ty, 'amMiniNodeSub', p.w - 34, 1, 11, 10); ty += 16; }
      if(txt.detail){ body += miniSvgTextLines(txt.detail, p.x + 18, ty, 'amMiniNodeSummary', p.w - 34, 1, 11, 9.6); }
      return `<g class="amMiniNode amMiniStatus-${status} ${esc(shape)} ${accent}" data-node-id="${esc(String(n.id || ''))}" tabindex="0" role="button">${body}</g>`;
    }).join('');
    return `<div class="amMiniCanvas" id="amMiniCanvasHost"><svg viewBox="0 0 ${layout.width} ${layout.height}" width="${layout.width}" height="${layout.height}" role="img" aria-label="Read-only analysis configuration canvas">${defs}${scopeSvg}${containerSvg}${edgeSvg}${nodeSvg}</svg><div id="amNodeInfo" class="amNodeInfo hidden" role="dialog" aria-label="Node details"></div></div>${msg}`;
  }

  /**
   * miniNodeSize  Compute the mini node size layout value used by browser rendering.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniNodeSize(n){
    const txt = miniCanvasNodeText(n);
    const lines = [txt.title, txt.subtitle, txt.detail].filter((s)=>String(s || '').trim());
    const longest = lines.reduce((m, s)=>Math.max(m, String(s).length), 0);
    const textW = Math.ceil(longest * 7.1);
    const w = Math.min(250, Math.max(140, textW + 40));
    const h = Math.max(46, 22 + Math.max(1, lines.length) * 18 + 6);
    return {w, h};
  }

  /**
   * nodeDetailPayload  Provide the node detail payload helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function nodeDetailPayload(n){
    if(!n || !n.detail || typeof n.detail !== 'object') return null;
    return n.detail;
  }

  /**
   * miniCanvasPopoverText  Build the mini canvas popover text shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasPopoverText(value){
    const txt = String(value == null ? '' : value).trim();
    if(!txt) return '';
    // The compact Analysis Manager mini-canvas is inspection-only.  Double-click
    // navigation exists only in the full training-template canvas, so do not
    // expose those action hints in mini-canvas popovers.
    if(/double[-\s]?click/i.test(txt)) return '';
    return txt;
  }

  /**
   * renderNodeDetailPopoverContent  Render the node detail popover content UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderNodeDetailPopoverContent(n){
    const d = nodeDetailPayload(n);
    const title = (d && d.title) || n.title || n.label || n.id || 'Node';
    const sub = (d && d.subtitle) || n.subtitle || '';
    const sections = d ? arr(d.sections).filter((sec)=>sec && typeof sec === 'object') : [];
    const warnings = d ? arr(d.warnings).filter((w)=>String(w || '').trim()) : [];
    let parts = [`<div class="amNodeInfoMainTitle">${esc(title)}</div>`];
    if(sub) parts.push(`<div class="amNodeInfoSubtitle">${esc(sub)}</div>`);
    if(sections.length){
      sections.forEach((sec)=>{
        const h = sec.heading ? String(sec.heading) : 'Configuration';
        const lines = arr(sec.lines).map(miniCanvasPopoverText).filter((x)=>String(x || '').trim());
        if(!lines.length) return;
        parts.push(`<div class="amNodeInfoSection"><div class="amNodeInfoSectionTitle">${esc(h)}</div>${lines.map((x)=>`<div class="amNodeInfoLine">${esc(x)}</div>`).join('')}</div>`);
      });
    } else if(n.summary) {
      parts.push(`<div class="amNodeInfoLine">${esc(n.summary)}</div>`);
    } else {
      parts.push('<div class="muted">No user-facing node details are available.</div>');
    }
    if(warnings.length){
      parts.push(`<div class="amNodeInfoSection"><div class="amNodeInfoSectionTitle warningText">Warnings</div>${warnings.map((w)=>`<div class="amNodeInfoLine warningText">${esc(w)}</div>`).join('')}</div>`);
    }
    const action = miniCanvasPopoverText(d && d.action ? String(d.action) : '');
    if(action) parts.push(`<div class="amNodeInfoAction">${esc(action)}</div>`);
    return parts.join('');
  }

  /**
   * showNodeInfo  Provide the show node info helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function showNodeInfo(nodeId, gEl){
    const host = el('amMiniCanvasHost');
    const box = el('amNodeInfo');
    const n = CANVAS_NODES.get(String(nodeId || ''));
    if(!host || !box || !n || !gEl) return;
    box.innerHTML = `<div class="amNodeInfoHead"><span class="amNodeInfoTitle">Node details</span>` +
      `<button type="button" class="amNodeInfoClose" aria-label="Close node details">×</button></div>` +
      renderNodeDetailPopoverContent(n);
    box.classList.remove('hidden');
    box.dataset.nodeId = n.id;
    const hostRect = host.getBoundingClientRect();
    const gRect = gEl.getBoundingClientRect();
    let left = (gRect.right - hostRect.left) + host.scrollLeft + 12;
    let top = (gRect.top - hostRect.top) + host.scrollTop;
    box.style.left = left + 'px';
    box.style.top = top + 'px';
    const overflowR = left + box.offsetWidth - (host.scrollWidth - 6);
    if(overflowR > 0){
      const flip = (gRect.left - hostRect.left) + host.scrollLeft - box.offsetWidth - 12;
      box.style.left = Math.max(6, flip) + 'px';
    }
    const analysisIndex = Number(INSPECTION.analysisIndex);
    const detailKey = `${analysisIndex}:${n.id}`;
    if(n.detail && n.detail.mode === 'summary' && !CANVAS_DETAIL_IN_FLIGHT.has(detailKey)){
      CANVAS_DETAIL_IN_FLIGHT.add(detailKey);
      matlabService('analysis_manager_canvas_detail', {analysisIndex, nodeId:n.id}).then((res)=>{
        if(res.ok !== true) throw new Error(res.message);
        if(!INSPECTION || Number(INSPECTION.analysisIndex) !== analysisIndex) return;
        n.detail = res.detail;
        if(!box.classList.contains('hidden') && box.dataset.nodeId === n.id && CANVAS_NODES.get(n.id) === n && gEl.isConnected)
          showNodeInfo(n.id, gEl);
      }).catch((err)=>setMsg(`Canvas details: ${err.message || String(err)}`, 'danger'))
        .finally(()=>CANVAS_DETAIL_IN_FLIGHT.delete(detailKey));
    }
  }

  /**
   * hideNodeInfo  Provide the hide node info helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function hideNodeInfo(){
    const box = el('amNodeInfo');
    if(box){ box.classList.add('hidden'); box.innerHTML = ''; }
  }

  /**
   * miniCanvasLayout  Provide the mini canvas layout helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasLayout(nodes){
    const scopeNodes = nodes.filter((n)=>String(n.shape || '') === 'scope' || String(n.type || '') === 'partition_scope');
    const flowNodes = nodes.filter((n)=>!(String(n.shape || '') === 'scope' || String(n.type || '') === 'partition_scope'));
    const groups = {};
    flowNodes.forEach((n)=>{
      let lane = Number(n.lane || 10);
      if(!Number.isFinite(lane)) lane = 10;
      if(!groups[lane]) groups[lane] = [];
      groups[lane].push(n);
    });
    const lanes = Object.keys(groups).map(Number).sort((a,b)=>a-b);
    lanes.forEach((lane)=>groups[lane].sort((a,b)=>Number(a.order || 0)-Number(b.order || 0) || String(a.title || '').localeCompare(String(b.title || ''))));
    const pos = new Map();
    const marginX = 64, marginY = 60, dx = 280, dy = 150;
    let maxRow = 0;
    /**
     * explicitRow  Provide the explicit row helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
     * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function explicitRow(n){
      const r = Number(n && n.row);
      return n && n.row !== null && n.row !== undefined && n.row !== '' && Number.isFinite(r) ? r : null;
    }
    lanes.forEach((lane, col)=>{
      const g = groups[lane] || [];
      g.forEach((n, autoRow)=>{
        const rr = explicitRow(n);
        const row = rr === null ? autoRow : rr;
        maxRow = Math.max(maxRow, row);
        const sz = miniNodeSize(n);
        const isDiamond = String(n.shape || '') === 'diamond';
        const w = isDiamond ? Math.max(sz.w, 150) : sz.w;
        const h = isDiamond ? Math.max(sz.h, 90) : sz.h;
        pos.set(String(n.id || ''), {x: marginX + row * dx, y: marginY + col * dy, w, h, lane, col, row});
      });
    });
    let width = Math.max(900, marginX * 2 + (maxRow + 1) * dx + 250);
    let height = Math.max(560, marginY * 2 + Math.max(1, lanes.length) * dy + 124);
    const scopeBounds = new Map();
    scopeNodes.forEach((sn)=>{
      const vals = flowNodes.filter((n)=>{
        const g = String(n.group || '').toLowerCase();
        const t = String(n.type || '').toLowerCase();
        return !(g === 'data' || g === 'modality' || t === 'input' || t === 'modality');
      }).map((n)=>pos.get(String(n.id || ''))).filter(Boolean);
      if(!vals.length) return;
      const minX = Math.max(10, Math.min(...vals.map((v)=>v.x)) - 34);
      const minY = Math.max(20, Math.min(...vals.map((v)=>v.y)) - 70);
      const maxX = Math.max(...vals.map((v)=>v.x + v.w)) + 28;
      const maxY = Math.max(...vals.map((v)=>v.y + v.h)) + 28;
      scopeBounds.set(String(sn.id || ''), {x:minX, y:minY, w:Math.max(200, maxX-minX), h:Math.max(120, maxY-minY)});
      width = Math.max(width, maxX + marginX);
      height = Math.max(height, maxY + marginY);
    });
    const containerBounds = new Map();
    flowNodes.forEach((n)=>{
      if(String(n.shape || '') !== 'container') return;
      const childIds = arr(n.children).map((x)=>String(x || '')).filter(Boolean);
      const childPos = childIds.map((id)=>pos.get(id)).filter(Boolean);
      if(!childPos.length) return;
      const minX = Math.min(...childPos.map((p)=>p.x)) - 16;
      const minY = Math.min(...childPos.map((p)=>p.y)) - 36;
      const maxX = Math.max(...childPos.map((p)=>p.x + p.w)) + 16;
      const maxY = Math.max(...childPos.map((p)=>p.y + p.h)) + 16;
      containerBounds.set(String(n.id || ''), {x:minX, y:minY, w:Math.max(200, maxX-minX), h:Math.max(110, maxY-minY)});
      width = Math.max(width, maxX + marginX);
      height = Math.max(height, maxY + marginY);
    });
    return {flowNodes, scopeNodes, pos, scopeBounds, containerBounds, width, height};
  }

  /**
   * miniCanvasEdgePath  Provide the mini canvas edge path helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasEdgePath(e, layout){
    const sourceId = String(e.source || '');
    const targetId = String(e.target || '');
    const s = layout.pos.get(sourceId);
    const t = layout.pos.get(targetId);
    const sourceContainer = layout.containerBounds.get(sourceId) || null;
    const targetContainer = layout.containerBounds.get(targetId) || null;
    if((!s && !sourceContainer) || (!t && !targetContainer)) return '';
    const isAuxInput = ['label_input','covariate_input'].includes(String(e.kind || ''));
    const sb = sourceContainer || s;
    const tb = targetContainer || t;
    if(isAuxInput){
      const x1 = sb.x + sb.w / 2;
      const y1 = sb.y + sb.h;
      const x2 = tb.x - 12;
      const y2 = tb.y + tb.h / 2;
      return `M ${x1} ${y1} L ${x1} ${y2} L ${x2} ${y2}`;
    }
    const x1 = sb.x + sb.w / 2;
    const y1 = sb.y + sb.h;
    const x2 = tb.x + tb.w / 2;
    const y2 = tb.y - 12;
    let mid = y1 + Math.max(32, (y2 - y1) / 2);
    if(y2 < y1) mid = y1 + 42;
    return `M ${x1} ${y1} L ${x1} ${mid} L ${x2} ${mid} L ${x2} ${y2}`;
  }

  /**
   * miniCanvasNodeText  Build the mini canvas node text shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasNodeText(n){
    let title = miniCanvasShortTitle(n.title || n.label || n.id || 'Node');
    const id = String(n.id || '').toLowerCase();
    const group = String(n.group || '').toLowerCase();
    const type = String(n.type || '').toLowerCase();
    const shape = String(n.shape || '').toLowerCase();
    const all = `${n.title || ''} ${n.subtitle || ''} ${n.summary || ''} ${n.configurator || ''}`.toLowerCase();
    let subtitle = '';
    let detail = '';
    if(id.includes('label') || group === 'label' || type === 'label_input'){
      subtitle = all.includes('regression') ? 'regression labels' : (all.includes('classification') ? 'classification labels' : 'label input');
    } else if(id.includes('covar') || group === 'covariate' || type === 'covariate_input'){
      subtitle = 'covariate input';
    } else if(group === 'data' || group === 'modality' || type === 'input' || type === 'modality' || id.startsWith('modality')){
      title = miniCanvasModalityTitle(n);
      if(all.includes('non-imaging')) subtitle = 'non-imaging modality';
      else if(all.includes('imaging')) subtitle = 'imaging modality';
      else subtitle = 'input modality';
    } else if(shape === 'diamond' || id.includes('fusion') || title.toLowerCase().includes('fusion')){
      subtitle = all.includes('late fusion') ? 'late fusion' : (all.includes('intermediate fusion') ? 'intermediate fusion' : (all.includes('early fusion') ? 'early fusion' : 'fusion / merge'));
    } else if(group === 'preproc' || type.includes('preproc') || id.includes('preproc')){
      const step = Number(n.stepIndex);
      subtitle = Number.isFinite(step) && step > 0 ? `preprocessing step ${step}` : 'preprocessing';
    } else if(group === 'learner' || type.includes('learner') || id.includes('ml')){
      subtitle = miniCanvasCompactPhrase(n.subtitle || 'machine-learning step', 32);
    } else if(group === 'output' || type.includes('output') || id.includes('vis') || id.includes('mli')){
      subtitle = 'output module';
    } else if(n.subtitle){
      subtitle = miniCanvasCompactPhrase(n.subtitle, 34);
    }
    if(String(n.status || '').toLowerCase().includes('warning')) detail = 'warning';
    if(String(n.status || '').toLowerCase().includes('error') || String(n.status || '').toLowerCase().includes('danger')) detail = 'error';
    return {title, subtitle, detail};
  }

  /**
   * miniCanvasShortTitle  Provide the mini canvas short title helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasShortTitle(value){
    let t = String(value == null ? '' : value).replace(/\s+/g,' ').trim();
    if(!t) return 'Node';
    t = t.replace(/\s+·\s+.*$/, '');
    return miniCanvasCompactPhrase(t, 34);
  }

  /**
   * miniCanvasModalityTitle  Provide the mini canvas modality title helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasModalityTitle(n){
    const raw = String((n && (n.title || n.label || n.id)) || '').replace(/\s+/g,' ').trim();
    if(!raw) return 'Modality';
    let t = raw.replace(/\s+·\s+.*$/, '');
    t = t.replace(/\s+data$/i, '');
    const maxChars = 46;
    return t.length > maxChars ? `${t.slice(0, maxChars - 1).trim()}…` : t;
  }

  /**
   * miniCanvasCompactPhrase  Provide the mini canvas compact phrase helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasCompactPhrase(value, maxChars){
    let t = String(value == null ? '' : value).replace(/\s+/g,' ').trim();
    if(!t) return '';
    t = t.replace(/\s*\.\.\.$/, '');
    t = t.replace(/\s*[.;:]\s+.*$/, '');
    t = t.replace(/\s+\(.*?\)\s*$/, '');
    const n = Math.max(8, Number(maxChars) || 30);
    return t.length > n ? `${t.slice(0, n - 1).trim()}…` : t;
  }

  /**
   * miniSvgTextLines  Provide the mini svg text lines helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniSvgTextLines(text, x, y, cls, maxWidthPx, maxLines, lineHeight, fontPx){
    const raw = String(text == null ? '' : text).trim();
    if(!raw) return '';
    const charLimit = miniCanvasCharLimit(maxWidthPx, fontPx || 12);
    const words = raw.split(/\s+/).filter(Boolean);
    const lines = [];
    let cur = '';
    words.forEach((word)=>{
      let w = word;
      if(w.length > charLimit){
        w = `${w.slice(0, Math.max(1, charLimit - 1))}…`;
      }
      const trial = cur ? `${cur} ${w}` : w;
      if(trial.length > charLimit && cur){
        lines.push(cur);
        cur = w;
      } else {
        cur = trial;
      }
    });
    if(cur) lines.push(cur);
    const maxN = Math.max(1, maxLines || 1);
    const clipped = lines.slice(0, maxN);
    if(lines.length > clipped.length) clipped[clipped.length - 1] = `${clipped[clipped.length - 1].replace(/\.*$/,'')}…`;
    return clipped.map((ln,i)=>`<text x="${x}" y="${y + i * (lineHeight || 14)}" class="${cls}">${esc(ln)}</text>`).join('');
  }

  /**
   * miniCanvasCharLimit  Provide the mini canvas char limit helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniCanvasCharLimit(maxWidthPx, fontPx){
    const w = Number(maxWidthPx);
    const f = Number(fontPx);
    const usableWidth = Number.isFinite(w) && w > 24 ? w : 180;
    const charWidth = Math.max(6.2, (Number.isFinite(f) && f > 0 ? f : 12) * 0.74);
    return Math.max(7, Math.floor(usableWidth / charWidth));
  }

  /**
   * miniStatus  Provide the mini status helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function miniStatus(s){
    s = String(s || 'ok').toLowerCase();
    return ['ok','info','warning','warn','error','danger','inactive'].includes(s) ? s : 'ok';
  }

  /**
   * svgText  Build the svg text shown to users in the browser UI.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function svgText(s, maxChars){
    const t = String(s == null ? '' : s);
    return esc(t.length > maxChars ? `${t.slice(0, Math.max(1, maxChars-1))}…` : t);
  }

  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function render(){ window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');
    fillDefaults();
    updateAnalysisIndexBounds();
    const defs = STATE.defs || {};
    const summary = el('analysisStatus');
    if(summary) {
      summary.textContent = STATE.statusMessage;
      summary.classList.toggle('hidden', !STATE.statusMessage);
    }
    renderApplicationTransition(defs);
    renderAnalysisList();
    renderInspectionPanel();
    setCreateFeedback();
  }

  /**
   * run  Provide the run helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * opts.inspectResponse: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.runtimeResponse: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.selectCreated: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.syncBefore: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function run(operation, extra, opts){
    opts = opts || {};
    if(REQUEST_IN_FLIGHT) { setMsg('A MATLAB analysis-manager request is already running. Wait for the success/error message before starting another action.', 'warn'); return null; }
    setBusy(true, `MATLAB is processing ${operation}.`);
    try{
      setMsg('MATLAB is processing the analysis-manager request.', 'info');
      if(opts.syncBefore) await syncCurrent();
      let res;
      if(opts.runtimeResponse){
        const client = runtimeJobClient();
        const viewer = runtimeProgressViewer();
        if(!client || !viewer || !window.NMRuntimeProgressViewer)
          throw new Error('The shared NM runtime progress infrastructure is unavailable.');
        let progressTaskId = window.NMRuntimeProgressViewer.createTaskId('analysis_manager');
        viewer.open(progressTaskId, 'Preparing analysis runtime plan.');
        const payload = Object.assign({operation}, extra || {}, {progressTaskId});
        res = await client.run(payload, {
          progressTaskId, jobId:progressTaskId,
          onAccepted:(job)=>{
            const acceptedTaskId = String((job && job.progressTaskId) || progressTaskId);
            if(acceptedTaskId && acceptedTaskId !== progressTaskId){
              progressTaskId = acceptedTaskId;
              viewer.open(progressTaskId, 'Reattached to analysis runtime plan.');
            }
          }
        });
        if(res && res.ok === false) viewer.hide();
      } else {
        res = await matlabService(operation, extra || {});
      }
      if(res && res.state) STATE = res.state;
      if(res && res.ok && opts.inspectResponse) INSPECTION = res;
      if(res && res.ok && opts.runtimeResponse && res.inspection) INSPECTION = res.inspection;
      if(res && res.ok && opts.selectCreated && res.analysisIndex) SELECTED = Number(res.analysisIndex);
      const sev = res && res.strip && res.strip.severity ? res.strip.severity : (res && res.ok ? 'ok' : 'danger');
      setMsg((res && (res.message || res.error)) || (res && res.ok ? 'Operation completed.' : 'Operation failed.'), sev === 'error' ? 'danger' : sev);
      render();
      // The MATLAB service response is authoritative for the browser state.
      // Persist current_config.json opportunistically, but do not keep the UI
      // busy after a completed create/reset action just to write this JSON file.
      syncCurrent().catch((err)=>{ try { console.warn('Analysis-manager state sync failed:', err); } catch(_) {} });
      return res || null;
    } catch(err){
      setMsg(`ERROR in ${operation}: ${err.message || String(err)}`, 'danger');
      return null;
    } finally {
      setBusy(false);
    }
  }
  /**
   * runCardAction  Provide the run card action helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It supports Analysis Manager browser page and miniature analysis-canvas inspector at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function runCardAction(action, index){
    if(action === 'inspect') { SELECTED = Number(index); RUNTIME_SELECTION = {preprocess:false, trainML:false, preprocessOverwrite:false, trainOverwrite:false, trainStage:'auto'}; run('analysis_manager_inspect', {analysisIndex:index}, {inspectResponse:true}); return; }
    if(action === 'export_methods') { exportAnalysisMethods(index); return; }
    if(action === 'reset') { if(window.confirm(`Completely reset analysis ${index} from the current NM parameter template? Existing runtime/result fields in the analysis entry will be cleared.`)) run('analysis_manager_reset', {analysisIndex:index}); return; }
    if(action === 'restore_template') { if(window.confirm(`Reset the current NM parameter template from analysis ${index}? This overwrites the active TrainParam/CV template with the selected analysis snapshot.`)) run('analysis_manager_restore_template', {analysisIndex:index}); return; }
    if(action === 'delete') { if(window.confirm(`Delete analysis ${index} from NM? Output files remain on disk.`)) run('analysis_manager_delete', {analysisIndex:index, wipe:false}); return; }
    if(action === 'delete_wipe') { if(window.confirm(`Delete analysis ${index} and remove its output folder from disk?`)) run('analysis_manager_delete', {analysisIndex:index, wipe:true}); return; }
    if(action === 'open_results_viewer') { openResultsViewer(index); return; }
    if(action === 'relink_root') { relinkAnalysisRoot(index); return; }
    if(action === 'run_runtime_plan') {
      const plan = runtimePlanFromSelection(index);
      if(!plan.actions.length) { setMsg('Select at least one feasible runtime action.', 'warn'); return; }
      if(plan.actions.includes('preprocess') && plan.options.preprocess.overwrite) {
        if(!window.confirm(`Run preprocessing for analysis ${index} and overwrite existing PreprocData artifacts?`)) return;
      }
      if(plan.actions.includes('trainML') && plan.options.trainML.overwrite) {
        if(!window.confirm(`Run Train ML for analysis ${index} and overwrite existing training results?`)) return;
      }
      run('analysis_manager_run_runtime_plan', {analysisIndex:index, runtimePlan:plan, timeout:86400}, {runtimeResponse:true});
      return;
    }
  }

  function openResultsViewer(index){
    if(REQUEST_IN_FLIGHT) return;
    setBusy(true, 'Opening NM2 Results Viewer.');
    return matlabService('app_prepare_page', {page:'results_alpha',moduleKey:'results_alpha',timeout:240})
      .then(res=>{
        if(res.ok !== true) throw new Error(res.message);
        const route = `${res.entryHtml}?port=${encodeURIComponent(PORT)}&analysisIndex=${encodeURIComponent(index)}&_nmcb=${Date.now()}`;
        window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(route) : route);
      })
      .catch(err=>setMsg(`Cannot open NM2 Results Viewer: ${err.message}`, 'danger'))
      .finally(()=>setBusy(false));
  }

  async function exportAnalysisMethods(index){
    if(REQUEST_IN_FLIGHT) return;
    try{
      const pick = await postJson('/api/pickpath', {kind:'directory', multiple:false, initial:'', timeout:240});
      if(pick.error) throw new Error(pick.error);
      const paths = arr(pick.paths);
      if(!paths.length) { setMsg('Methods-summary export cancelled.', 'info'); return; }
      const result = await run('analysis_manager_export_methods', {analysisIndex:index, exportRoot:paths[0]});
      if(result && result.ok) setMsg(`${result.message}\n${result.file}`, 'ok');
    } catch(err){ console.error('Analysis Methods export failed:', err); setMsg(`Methods-summary export failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * relinkAnalysisRoot  Provide the relink analysis root helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * The selected folder may be either the exact analysis root or its immediate parent; MATLAB resolves the interpretation and rejects ambiguous parents.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function relinkAnalysisRoot(index){
    if(REQUEST_IN_FLIGHT) { setMsg('A MATLAB analysis-manager request is already running. Wait for the success/error message before relinking paths.', 'warn'); return; }
    const data = analysisArrays();
    const k = data.idx.findIndex((v)=>Number(v) === Number(index));
    const currentRoot = k >= 0 ? String(data.roots[k] || '') : '';
    try{
      setMsg(`Stored root: ${currentRoot || '(not recorded)'}. Select the new analysis root folder or its parent directory. NeuroMiner will inspect the selection and reject ambiguous matches.`, 'info');
      const initial = (k >= 0 && (data.rootExists[k] === true || data.rootExists[k] === 1 || data.rootExists[k] === 'true')) ? currentRoot : '';
      const pick = await postJson('/api/pickpath', {kind:'directory', multiple:false, initial, timeout:240});
      const paths = arr(pick.paths);
      if(!paths.length) { setMsg('Analysis root relink cancelled.', 'warn'); return; }
      run('analysis_manager_relink_root', {analysisIndex:index, newRootDir:paths[0], selectionKind:'auto'}, {inspectResponse:true});
    } catch(err){ setMsg(`Analysis root relink failed: ${err.message || String(err)}`, 'danger'); }
  }

  /**
   * pickAnalysisParentDir  Provide the pick analysis parent dir helper used by Analysis Manager browser page and miniature analysis-canvas inspector.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function pickAnalysisParentDir(){
    try{
      setMsg('Waiting for MATLAB directory picker.', 'info');
      const initial = el('analysisParentDir') ? el('analysisParentDir').value.trim() : '';
      const pick = await postJson('/api/pickpath', {kind:'directory', multiple:false, initial, timeout:240});
      const paths = arr(pick.paths);
      if(paths.length && el('analysisParentDir')) {
        el('analysisParentDir').value = paths[0];
        setMsg('Parent directory selected.', 'ok');
      } else {
        setMsg('Directory selection cancelled.', 'warn');
      }
    } catch(err){ setMsg(`Directory picker failed: ${err.message || String(err)}`, 'danger'); }
  }

  function installNMUIDraftAdapter(){
    if(!window.NMUIDraftManager) return;
    const copy=(x)=>JSON.parse(JSON.stringify(x==null?null:x));
    window.NMUIDraftManager.registerAdapter({
      snapshot:()=>({selected:SELECTED,runtimeSelection:copy(RUNTIME_SELECTION),inspectionIndex:(INSPECTION&&INSPECTION.analysisIndex)||null}),
      restore:async(saved)=>{if(!saved||typeof saved!=='object')return;if(Number.isFinite(Number(saved.selected)))SELECTED=Number(saved.selected);if(saved.runtimeSelection&&typeof saved.runtimeSelection==='object')RUNTIME_SELECTION=Object.assign({preprocess:false,trainML:false,preprocessOverwrite:false,trainOverwrite:false,trainStage:'auto'},copy(saved.runtimeSelection));render();if(Number.isFinite(Number(saved.inspectionIndex)))setTimeout(()=>run('analysis_manager_inspect',{analysisIndex:Number(saved.inspectionIndex)},{inspectResponse:true}),0);},
      reconcile:async()=>{await syncCurrent();}
    });
  }
  installNMUIDraftAdapter();
  document.addEventListener('DOMContentLoaded', ()=>{
    const finish = el('finish'); if(finish) {
      window.NMModuleNavigationRail.updateReturnButton(appContext(),'Finish / close');
      finish.onclick = async ()=>{
        if(REQUEST_IN_FLIGHT) { setMsg('A MATLAB analysis-manager request is still running. Wait for the success/error message before returning to the main menu.', 'warn'); return; }
        try{
          setMsg('Returning to the NeuroMiner workbench...', 'info');
          await syncCurrent();
          try {
            const res = await postJson('/api/matlabservice', {operation:'app_child_return', source:'analysis_manager', timeout:120}, 130);
            if(res && res.ok === true) {
              window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(workbenchReturnUrl()) : workbenchReturnUrl());
              return;
            }
            if(isWorkbenchChild()) throw new Error((res && (res.message || res.error)) || 'Returning to the workbench failed.');
          } catch(returnErr) {
            if(isWorkbenchChild()) throw returnErr;
          }
          await postJson('/api/close', {closed:true, source:'analysis_manager'});
          document.body.innerHTML = '<p style="font-family:system-ui;padding:20px">Analysis-manager state saved. You can close this tab.</p>';
        } catch(err){ setMsg(`ERROR while closing analysis manager: ${err.message || String(err)}`, 'danger'); }
      };
    }
    const create = el('createAnalysis'); if(create) create.onclick = ()=>{
      const reason = createDisabledReason();
      if(reason) { setMsg(reason, 'warn'); return; }
      let spec;
      try { spec = createSpec(); }
      catch(err) { setMsg(`Cannot create analysis: ${err.message || String(err)}`, 'danger'); return; }
      run('analysis_manager_create', {analysisSpec:spec}, {selectCreated:true});
    };
    ['analysisId','analysisDescription','analysisParentDir','analysisIndex'].forEach((id)=>{ const x = el(id); if(x) x.addEventListener('input', setCreateFeedback); });
    const pick = el('pickAnalysisParentDir'); if(pick) pick.onclick = pickAnalysisParentDir;
    const app = el('activateApplicationMode'); if(app) app.onclick = ()=>{
      if(!window.confirm('Activate Application/OOCV mode?\n\nThis locks training-analysis editing. Treat the transition as irreversible to prevent information leakage between discovery/training data and external validation/application data.')) return;
      run('analysis_manager_activate_application_mode');
    };
    const help = el('applicationHelpButton'); if(help) help.onclick = ()=>{ const h = el('applicationHelpText'); if(h) h.classList.toggle('hidden'); };
    const closeInspection = el('closeInspectionPanel'); if(closeInspection) closeInspection.onclick = ()=>{ INSPECTION = null; render(); };
    const list = el('analysisList'); if(list) list.onclick = (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest('button[data-action]') : null;
      if(!btn || btn.disabled) return;
      const card = btn.closest('[data-analysis-index]');
      const index = card ? Number(card.dataset.analysisIndex) : selectedIndex();
      runCardAction(btn.dataset.action, index);
      ev.stopPropagation();
    };
    const panel = el('analysisInspectionPanel'); if(panel) panel.onclick = (ev)=>{
      const tgt = ev.target;
      if(tgt && tgt.closest && tgt.closest('.amNodeInfoClose')){ hideNodeInfo(); ev.stopPropagation(); return; }
      const nodeG = tgt && tgt.closest ? tgt.closest('.amMiniNode[data-node-id]') : null;
      if(nodeG){ showNodeInfo(nodeG.getAttribute('data-node-id'), nodeG); ev.stopPropagation(); return; }
      if(tgt && tgt.closest && tgt.closest('#amMiniCanvasHost') && !tgt.closest('#amNodeInfo')){ hideNodeInfo(); }
      const btn = tgt && tgt.closest ? tgt.closest('button[data-action]') : null;
      if(!btn || btn.disabled) return;
      const index = INSPECTION && INSPECTION.analysisIndex ? Number(INSPECTION.analysisIndex) : selectedIndex();
      runCardAction(btn.dataset.action, index);
      ev.stopPropagation();
    };
    if(panel) panel.onkeydown = (ev)=>{
      if(ev.key !== 'Enter' && ev.key !== ' ') return;
      const nodeG = ev.target && ev.target.closest ? ev.target.closest('.amMiniNode[data-node-id]') : null;
      if(nodeG){ showNodeInfo(nodeG.getAttribute('data-node-id'), nodeG); ev.preventDefault(); }
    };
    if(panel) panel.onchange = (ev)=>{
      const target = ev.target;
      if(!target) return;
      const action = target.getAttribute ? target.getAttribute('data-runtime-action') : '';
      if(action === 'preprocess') { RUNTIME_SELECTION.preprocess = !!target.checked; renderInspectionPanel(); return; }
      if(action === 'trainML') { RUNTIME_SELECTION.trainML = !!target.checked; renderInspectionPanel(); return; }
      if(target.id === 'runtimePreprocessOverwrite') { RUNTIME_SELECTION.preprocessOverwrite = !!target.checked; renderInspectionPanel(); return; }
      if(target.id === 'runtimeTrainOverwrite') { RUNTIME_SELECTION.trainOverwrite = !!target.checked; renderInspectionPanel(); return; }
      if(target.id === 'runtimeTrainStage') { RUNTIME_SELECTION.trainStage = String(target.value || 'auto'); renderInspectionPanel(); return; }
    };
    render();
    // Deep-link: when opened from another runner with ?analysis=N, select that
    // analysis and open its inspection canvas automatically. The inspect call
    // validates the index server-side.
    const preselect = Number(PARAMS.get('analysis'));
    if(Number.isFinite(preselect) && preselect >= 1){
      SELECTED = preselect;
      RUNTIME_SELECTION = {preprocess:false, trainML:false, preprocessOverwrite:false, trainOverwrite:false, trainStage:'auto'};
      run('analysis_manager_inspect', {analysisIndex:preselect}, {inspectResponse:true});
    }
    if(window.NMUIDraftManager)window.NMUIDraftManager.markReady();
  });
})();
