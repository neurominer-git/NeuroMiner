(function(){
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  let STATE = window.NM_WORKBENCH_STATE || {};
  const NM_UI_CLIENT_PROFILE = ["1","true","on","yes"].includes(String(PARAMS.get("profile") || "").toLowerCase());
  let NM_UI_PROFILE_SEQ = 0;
  function nmProfileNow(){ return (typeof performance !== "undefined" && performance.now) ? performance.now() : Date.now(); }
  function nmProfileId(label){
    NM_UI_PROFILE_SEQ += 1;
    return `${String(label || "action").replace(/[^A-Za-z0-9_-]/g,"_")}_${Date.now()}_${NM_UI_PROFILE_SEQ}`;
  }
  function nmProfileLog(rid, message){
    if(!NM_UI_CLIENT_PROFILE) return;
    console.log(`[nm-client-prof rid=${rid || "-"}] ${message}`);
  }
  const NM_UI_NAV_PROFILE_ID = PARAMS.get("nmprofid") || "";
  const NM_UI_NAV_PROFILE_START = Number(PARAMS.get("nmprofstart") || 0);
  if(NM_UI_CLIENT_PROFILE && NM_UI_NAV_PROFILE_ID && NM_UI_NAV_PROFILE_START){
    window.addEventListener("DOMContentLoaded", () => nmProfileLog(NM_UI_NAV_PROFILE_ID, `workbench DOMContentLoaded ${(Date.now()-NM_UI_NAV_PROFILE_START)/1000}s after navigation start`));
    window.addEventListener("load", () => nmProfileLog(NM_UI_NAV_PROFILE_ID, `workbench window load ${(Date.now()-NM_UI_NAV_PROFILE_START)/1000}s after navigation start`));
  }

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
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>\"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','\"':'&quot;',"'":'&#39;'}[c])); }
  /**
   * setMsg  Route a status message to the page message strip.
   * It supports NM 2.0 workbench landing page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setMsg(text, sev){
    window.NMUIMessageTools.setMessage(text || "", sev || "info");
  }
  /**
   * postJson  Send a JSON request to the local MATLAB bridge and parse the JSON response.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postJson(path, payload){
    let req = payload && typeof payload === 'object' ? Object.assign({}, payload) : {};
    const rid = req.profileId || (NM_UI_CLIENT_PROFILE ? nmProfileId(req.operation || path) : "");
    if(NM_UI_CLIENT_PROFILE){
      req.profile = true;
      req.profileId = rid;
    }
    const t0 = nmProfileNow();
    const body = JSON.stringify(req);
    const serializeSeconds = (nmProfileNow() - t0) / 1000;
    const tFetch = nmProfileNow();
    const response = await fetch(API(path), {method:'POST', headers:{'Content-Type':'application/json'}, body}).catch(error => {
      throw new Error(`NM2 bridge fetch failed: operation=${req.operation || path}, rid=${rid || '-'}, transport=${window.NM_HTML_RELAY ? 'uihtml-relay' : 'HTTP'}, port=${PORT}, runId=${window.NM_BRIDGE_RUNID || '-'}\n${error.stack || error}`);
    });
    const headersSeconds = (nmProfileNow() - tFetch) / 1000;
    const tRead = nmProfileNow();
    const txt = await response.text();
    const bodyReadSeconds = (nmProfileNow() - tRead) / 1000;
    const tParse = nmProfileNow();
    let obj = {};
    try { obj = JSON.parse(txt || '{}'); }
    catch(err) { throw new Error(`Browser bridge returned non-JSON for ${path}: ${(txt || '').slice(0,300)}`); }
    const parseSeconds = (nmProfileNow() - tParse) / 1000;
    if(obj && typeof obj === 'object' && !obj.httpStatus) obj.httpStatus = response.status;
    if(NM_UI_CLIENT_PROFILE){
      const b = obj && obj._nmProfileBridge;
      const bridge = b ? ` bridge(inboundRead=${Number(b.inboundReadSeconds||0).toFixed(3)}s inboundDecode=${Number(b.inboundDecodeSeconds||0).toFixed(3)}s requestPersist=${Number(b.requestPersistSeconds||0).toFixed(3)}s waitMATLAB=${Number(b.waitMATLABSeconds||0).toFixed(3)}s resultRead=${Number(b.resultReadSeconds||0).toFixed(3)}s)` : "";
      nmProfileLog(rid, `browser request ${req.operation || path} serialize=${serializeSeconds.toFixed(3)}s fetchHeaders=${headersSeconds.toFixed(3)}s bodyRead=${bodyReadSeconds.toFixed(3)}s parse=${parseSeconds.toFixed(3)}s total=${((nmProfileNow()-t0)/1000).toFixed(3)}s${bridge}`);
    }
    return obj;
  }
  /**
   * matlabService  Send a MATLAB-service request through the browser bridge.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function matlabService(payload){
    return postJson('/api/matlabservice', payload);
  }

  /**
   * stateIcon  Render a compact browser-only workflow-state icon.
   * It projects existing workbench state and does not define workflow authority.
   */
  function stateIcon(kind){
    const common = 'class="wbStateIconSvg" viewBox="0 0 24 24" aria-hidden="true"';
    if(kind === 'locked') return `<svg ${common}><rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>`;
    if(kind === 'ready') return `<svg ${common}><circle cx="12" cy="12" r="9"/><path d="M8 12.2l2.5 2.5L16.5 9"/></svg>`;
    if(kind === 'future') return `<svg ${common}><path d="M7.2 18h10.1a4.2 4.2 0 0 0 .6-8.35A6.2 6.2 0 0 0 6.1 8.2 4.9 4.9 0 0 0 7.2 18z"/></svg>`;
    return `<svg ${common}><path d="M18.8 7.2A8.5 8.5 0 0 0 5.6 5.6L3.7 7.5"/><path d="M3.7 3.8v3.7h3.7"/><path d="M5.2 16.8a8.5 8.5 0 0 0 13.2 1.6l1.9-1.9"/><path d="M20.3 20.2v-3.7h-3.7"/><circle cx="12" cy="12" r="2.6"/><path d="M12 7.7v1.2M12 15.1v1.2M7.7 12h1.2M15.1 12h1.2M8.95 8.95l.85.85M14.2 14.2l.85.85M15.05 8.95l-.85.85M9.8 14.2l-.85.85"/></svg>`;
  }

  /**
   * milestoneState  Project the three workbench progress milestones from existing state authorities.
   * Only cards that advance a workbench checkpoint receive completion check marks.
   */
  function milestoneState(m){
    const key = String((m && m.key) || '');
    if(key === 'dataio'){
      return {complete:Number(STATE.committedModalityCount || 0) > 0, title:'At least one training modality has been loaded'};
    }
    if(key === 'mltrain'){
      return {complete:!!STATE.hasCompletedAnalysis || Number(STATE.completedAnalysisCount || 0) > 0, title:'At least one analysis has completed successfully'};
    }
    if(key === 'model_export'){
      const exportState = STATE.exportState || {};
      return {complete:!!exportState.export_finished, title:'At least one complete analysis export has finished'};
    }
    return null;
  }

  /**
   * renderStatus  Render the status UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderStatus(){
    const grid = el('statusGrid');
    if(!grid) return;
    grid.innerHTML = '';
    arr(STATE.summary).forEach(item => {
      const card = document.createElement('div');
      card.className = 'wbStatusCard';
      card.innerHTML = `<div class="wbStatusLabel">${esc(item.label)}</div><div class="wbStatusValue">${esc(item.value)}</div>`;
      grid.appendChild(card);
    });
    const msg = el('workbenchMessage');
    if(msg) msg.textContent = STATE.message || '';
  }

  /**
   * moduleCard  Provide the module card helper used by NM 2.0 workbench landing page.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function moduleCard(m){
    const card = document.createElement('article');
    const kind = String(m.kind || 'module');
    const kindClasses = kind.split(/\s+/).filter(Boolean).map(k => 'wbModuleKind-' + k).join(' ');
    card.className = 'wbModuleCard ' + kindClasses + (m.enabled ? '' : ' disabled');
    const reason = m.enabled || (m.key === 'analysis_manager' && !m.disabledReason) || (['preprocess','mltrain'].includes(m.key) && m.disabledReason === 'SYNTH placeholders cannot be trained directly.') ? '' : `<div class="wbDisabledReason">${esc(m.disabledReason || 'Not available yet.')}</div>`;
    const statusKey = String(m.statusLabel || '').toLowerCase();
    const milestone = milestoneState(m);
    let status = '';
    if(milestone){
      if(milestone.complete) status = `<span class="wbInlineStateIcon wbInline-ready" title="${esc(milestone.title)}">${stateIcon('ready')}</span>`;
      else if(m.enabled) status = `<span class="wbInlineStateIcon wbInline-active" title="In progress">${stateIcon('active')}</span>`;
    } else if((m.group || '') !== 'results' && statusKey !== 'destructive' && !['active','finalized','exported','ready'].includes(statusKey) && m.statusLabel){
      status = `<span class="wbStatusPill wbStatus-${esc(m.statusTone || 'neutral')}">${esc(m.statusLabel)}</span>`;
    }
    const iconKey = m.icon || (m.title || '?').slice(0,1);
    const icon = window.NMModuleIconSet ? window.NMModuleIconSet.svg(iconKey) : esc(iconKey);
    const buttonDisabled = m.enabled ? '' : 'disabled';
    const buttonClass = m.enabled ? 'primary' : '';
    const buttonLabel = esc(m.buttonLabel || 'Open');
    card.innerHTML = `
      <div class="wbModuleTop"><div class="wbModuleIcon" data-icon="${esc(iconKey)}">${icon}</div><div class="wbModuleCopy"><div class="wbModuleTitleRow"><h3>${esc(m.title)}</h3>${status}</div><p>${esc(m.description)}</p></div></div>
      ${reason}
      <button type="button" class="${buttonClass}" ${buttonDisabled} aria-label="${buttonLabel}">${buttonLabel}</button>`;
    const btn = card.querySelector('button');
    if(btn && m.enabled) btn.addEventListener('click', () => openModule(m));
    return card;
  }

  function stateModule(key){
    return arr(STATE.modules).find(m => m && String(m.key || '') === key) || null;
  }

  function renderModuleList(modules, containerId){
    const box = el(containerId);
    if(!box) return;
    box.innerHTML = '';
    modules.forEach(m => box.appendChild(moduleCard(m)));
  }

  /**
   * renderModuleGroup  Render the module group UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderModuleGroup(group, containerId, omitKeys){
    const omit = new Set(omitKeys || []);
    const visibleModules = arr(STATE.modules).filter(m => m && !m.hidden && (m.group || '') === group && !omit.has(String(m.key || '')));
    renderModuleList(visibleModules, containerId);
  }

  function renderGate(key, containerId, complete){
    const m0 = stateModule(key);
    if(!m0){ renderModuleList([], containerId); return; }
    const m = Object.assign({}, m0, {hidden:false});
    if(complete){
      m.enabled = false;
      m.disabledReason = '';
    }
    renderModuleList([m], containerId);
    const card = el(containerId) ? el(containerId).querySelector('.wbModuleCard') : null;
    if(card && complete){
      card.classList.add('wbGateComplete');
      const reason = card.querySelector('.wbDisabledReason');
      if(reason) reason.remove();
    }
  }

  /**
   * placeModelExport  Move the existing model-export card container with the active workflow regime.
   * This is presentation-only; model-export availability remains defined by the MATLAB workbench state.
   */
  function placeModelExport(applicationMode){
    const box = el('modelExportModules');
    const stage2Modules = el('trainingAnalysisModules');
    const stage3Modules = el('applicationModules');
    if(!box || !stage2Modules || !stage3Modules) return;
    const stage2 = stage2Modules.closest('.wbWorkflowSection');
    const stage3 = stage3Modules.closest('.wbWorkflowSection');
    const target = applicationMode ? stage3 : stage2;
    if(!target || box.parentNode === target) return;
    if(applicationMode) target.insertBefore(box, stage3Modules);
    else target.appendChild(box);
  }

  /**
   * renderModules  Render the modules UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   */
  function renderModules(){
    const defs = STATE.defs || {};
    placeModelExport(!!defs.analyses_locked);
    renderModuleGroup('training_data', 'trainingDataModules', ['lock_data']);
    renderGate('lock_data', 'trainingLockModules', !!defs.import_finished);
    renderModuleGroup('training_analysis', 'trainingAnalysisModules');
    renderModuleGroup('model_export', 'modelExportModules');
    renderModuleGroup('results', 'resultsModules');
    renderGate('lock_models', 'modelLockModules', !!defs.analyses_locked);
    const applicationModules = arr(STATE.modules).filter(m => m && !m.hidden && (m.group || '') === 'application');
    const scramble = stateModule('scramble_lock_models');
    if(defs.analyses_locked && !defs.data_scrambled && scramble){
      applicationModules.push(Object.assign({}, scramble, {group:'application', hidden:false}));
    }
    renderModuleList(applicationModules, 'applicationModules');
    renderModuleGroup('utilities', 'utilityModules');
  }

  function setHeaderState(section, state){
    if(!section) return;
    section.classList.remove('wbStage-active','wbStage-completed','wbStage-future');
    section.classList.add(`wbStage-${state}`);
    const marker = section.querySelector('.wbStageStateIcon');
    const iconKind = state === 'completed' ? 'locked' : (state === 'future' ? 'future' : 'active');
    marker.innerHTML = stateIcon(iconKind);
    marker.title = state === 'completed' ? 'Stage locked' : (state === 'future' ? 'Stage not yet activated' : 'Stage in progress');
  }

  function setGateState(section, complete, ready){
    if(!section) return;
    section.hidden = false;
    section.classList.toggle('wbGate-complete', complete);
    section.classList.toggle('wbGate-ready', !complete && ready);
    section.classList.toggle('wbGate-blocked', !complete && !ready);
    const marker = section.querySelector('.wbGateStateIcon');
    const kind = complete ? 'locked' : (ready ? 'ready' : 'future');
    marker.innerHTML = stateIcon(kind);
    marker.title = complete ? 'Checkpoint passed' : (ready ? 'Checkpoint ready' : 'Checkpoint not yet available');
  }

  function renderStagePresentation(){
    const defs = STATE.defs || {};
    const imported = !!defs.import_finished;
    const locked = !!defs.analyses_locked;
    const stage1 = el('trainingDataModules') ? el('trainingDataModules').closest('.wbWorkflowSection') : null;
    const stage2 = el('trainingAnalysisModules') ? el('trainingAnalysisModules').closest('.wbWorkflowSection') : null;
    const stage3 = el('applicationModules') ? el('applicationModules').closest('.wbWorkflowSection') : null;
    setHeaderState(stage1, imported ? 'completed' : 'active');
    setHeaderState(stage2, !imported ? 'future' : (locked ? 'completed' : 'active'));
    setHeaderState(stage3, locked ? 'active' : 'future');
    const shell = document.querySelector('.wbShell');
    if(shell){
      shell.classList.remove('wbActiveStage1','wbActiveStage2','wbActiveStage3');
      shell.classList.add(!imported ? 'wbActiveStage1' : (locked ? 'wbActiveStage3' : 'wbActiveStage2'));
    }
    const lockData = stateModule('lock_data');
    const lockModels = stateModule('lock_models');
    setGateState(el('trainingLockSection'), imported, !!(lockData && lockData.enabled));
    const modelGate = el('modelLockModules') ? el('modelLockModules').closest('.wbGateSection') : null;
    setGateState(modelGate, locked, !!(lockModels && lockModels.enabled));
  }

  /**
   * renderWorkflowDividers  Render the workflow dividers UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderWorkflowDividers(){
    const defs = STATE.defs || {};
    const importDivider = el('importFinalizedDivider');
    const appDivider = el('applicationStageDivider');
    const imported = !!defs.import_finished;
    const locked = !!defs.analyses_locked;
    const scrambled = !!defs.data_scrambled;
    if(importDivider) importDivider.hidden = !imported;
    if(appDivider){
      appDivider.hidden = !locked;
      appDivider.classList.toggle('wbApplicationDividerPrivacy', locked && scrambled);
      appDivider.classList.toggle('wbApplicationDividerStandard', locked && !scrambled);
      const label = appDivider.querySelector('span');
      if(label) label.textContent = scrambled ? 'Privacy Preserving OOCV Mode Activated' : 'OOCV Mode Activated';
    }
  }

  /**
   * render  Render the render UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function render(){
    renderStatus();
    renderModules();
    renderWorkflowDividers();
    renderStagePresentation();
    window.NM_WORKBENCH_STATE = STATE;
    if(window.NMModuleNavigationRail && typeof window.NMModuleNavigationRail.refresh === 'function') window.NMModuleNavigationRail.refresh();
  }

  /**
   * refresh  Refresh the refresh page region after state or artifact availability changes.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function refresh(){
    try{
      const res = await matlabService({operation:'app_workbench_refresh', timeout:120});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Workbench refresh failed.');
      if(res.state) STATE = res.state;
      render();
    } catch(err){
      setMsg(`Workbench refresh failed: ${err.message || String(err)}`, 'danger');
    }
  }


  /**
   * normalizedPage  Normalize d page payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI state.
   */
  function normalizedPage(page){
    const p = String(page == null ? '' : page).trim().toLowerCase();
    const map = {
      'nm_dataio_overview.html':'dataio',
      'nm_train_template_menu.html':'template',
      'nm_analysis_manager.html':'analysis_manager',
      'nm_preprocess_runner.html':'preprocess',
      'nm_ml_train_runner.html':'mltrain',
      'nm_vis_runner.html':'visualization',
      'nm_mli_runner.html':'mli',
      'nm_model_export_runner.html':'model_export',
      'results_viewer':'results',
      'results_alpha':'results_alpha',
      'nm_results_viewer_alpha.html':'results_alpha'
    };
    return map[p] || p;
  }

  /**
   * openResultsViewer  Open the results viewer panel, dialog or linked UI target.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function openResultsViewer(){
    try{
      setMsg('Opening NM Results Viewer...', 'info');
      const res = await matlabService({operation:'app_open_results_viewer', timeout:120});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Opening NM Results Viewer failed.');
      setMsg(res.message || 'NM Results Viewer opened.', 'ok');
    } catch(err){
      setMsg(`Cannot open NM Results Viewer: ${err.message || String(err)}`, 'danger');
    }
  }

  /**
   * runWorkbenchGate  Provide the run workbench gate helper used by NM 2.0 workbench landing page.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function runWorkbenchGate(moduleOrPage){
    const key = (moduleOrPage && typeof moduleOrPage === 'object') ? String(moduleOrPage.key || '') : String(moduleOrPage || '');
    let operation = '';
    let confirmText = '';
    if(key === 'lock_data'){
      operation = 'app_workbench_lock_training_data';
      confirmText = 'Lock training data now? Structural training-data edits will be disabled after this gate.';
    } else if(key === 'lock_models'){
      operation = 'app_workbench_lock_models';
      confirmText = 'Lock trained models and activate Application/OOCV mode? This transition is intended to be irreversible to avoid discovery/external-validation information leakage.';
    } else if(key === 'scramble_lock_models'){
      operation = 'app_workbench_scramble_lock_models';
      confirmText = (STATE.defs || {}).analyses_locked
        ? 'Destructive sharing action: replace all training input features by same-dimensional random double matrices? Continue only after model export has completed.'
        : 'Destructive sharing action: replace all training input features by same-dimensional random double matrices, then lock trained models and activate Application/OOCV mode? Continue only after model export has completed.';
    }
    if(!operation) return false;
    if(confirmText && !window.confirm(confirmText)){
      setMsg('Workflow gate action cancelled.', 'info');
      return true;
    }
    try{
      setMsg('Applying workflow gate...', 'info');
      const res = await matlabService({operation, timeout:240});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Workflow gate action failed.');
      if(res.state) STATE = res.state;
      render();
      setMsg(res.message || 'Workflow gate applied.', 'ok');
    } catch(err){
      setMsg(`Cannot apply workflow gate: ${err.message || String(err)}`, 'danger');
    }
    return true;
  }

  /**
   * openModule  Open the module panel, dialog or linked UI target.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function openModule(moduleOrPage){
    if(await runWorkbenchGate(moduleOrPage)) return;
    const moduleKey = (moduleOrPage && typeof moduleOrPage === 'object') ? String(moduleOrPage.key || '') : '';
    const rawPage = (moduleOrPage && typeof moduleOrPage === 'object') ? (moduleOrPage.page || moduleOrPage.key || '') : moduleOrPage;
    const page = normalizedPage(rawPage);
    if(page === 'results'){ await openResultsViewer(); return; }
    try{
      const profileId = NM_UI_CLIENT_PROFILE ? nmProfileId(`open_${page}`) : "";
      const navStartEpoch = Date.now();
      const res = await matlabService({operation:'app_prepare_page', page, moduleKey, profileId, timeout:240});
      if(!res || res.ok === false) throw new Error((res && (res.message || res.error)) || 'Page preparation failed.');
      const target = res.entryHtml || res.page || '';
      if(!target) throw new Error('Prepared page did not return an entry HTML file.');
      const sep = target.includes('?') ? '&' : '?';
      const moduleQuery = moduleKey ? `&moduleKey=${encodeURIComponent(moduleKey)}` : '';
      const profileQuery = NM_UI_CLIENT_PROFILE ? `&profile=1&nmprofid=${encodeURIComponent(profileId)}&nmprofstart=${encodeURIComponent(navStartEpoch)}` : '';
      const route = `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}${moduleQuery}${profileQuery}`;
      nmProfileLog(profileId, `workbench navigation commit after ${((Date.now()-navStartEpoch)/1000).toFixed(3)}s`);
      window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(route) : route);
    } catch(err){
      setMsg(`Cannot open module: ${err.message || String(err)}`, 'danger');
    }
  }

  function openLicense(){
    const modal = NMModal.open({title:'NeuroMiner LICENSE',size:'wide',html:'<pre class="wbLicenseText">Loading license...</pre>'});
    modal.dialog.classList.add('wbLicenseDialog');
    fetch('LICENCE.txt').then(response => {
      if(!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.text();
    }).then(text => { modal.body.querySelector('pre').textContent = text; })
      .catch(error => { modal.body.querySelector('pre').textContent = `Unable to load LICENCE.txt: ${error.message}`; });
  }

  function openContributors(){
    const modal = NMModal.open({title:'Contributors',html:`
      <div class="wbCreditsLogo"><span class="wbCreditsBrain" aria-hidden="true"></span><div class="wbCreditsMark"><div class="wbCreditsWordmark"><span class="wbBrandNM">NM</span><span class="wbBrandTwo">2</span></div><div class="wbCreditsCodename">OLORIN</div></div></div>
      <div class="wbCreditsNames"><div>Nikolaos Koutsouleris</div><div>Clara Vetter</div><div>Lisa Hahn</div><div>Ariane Wiegand</div><div>Sergio Mena</div></div>`,
      actions:[{label:'Open LICENSE',variant:'primary',onClick:m => { m.close(); openLicense(); }}]});
    modal.dialog.classList.add('wbCreditsDialog');
  }

  document.addEventListener('DOMContentLoaded', () => {
    const f = el('finish'); if(f){ f.insertAdjacentHTML('afterbegin', window.NMModuleIconSet.svg('quit_nm')); f.onclick = () => window.NMModuleNavigationRail.workspaceAction('quit').catch(err => setMsg(`ERROR while closing workbench: ${err.message || String(err)}`, 'danger')); }
    el('wbContributors').onclick = openContributors;
    const load = el('loadNM'); if(load){ load.insertAdjacentHTML('afterbegin', window.NMModuleIconSet.svg('load_nm')); load.onclick = () => window.NMModuleNavigationRail.workspaceAction('load'); }
    const save = el('saveNM'); if(save){ save.insertAdjacentHTML('afterbegin', window.NMModuleIconSet.svg('save_nm')); save.onclick = () => window.NMModuleNavigationRail.workspaceAction('save'); }
    render();
    refresh();
  });
})();