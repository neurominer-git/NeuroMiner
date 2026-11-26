(function(){
  'use strict';
  const PARAMS = new URLSearchParams(window.location.search || '');
  const PORT = PARAMS.get('port') || window.NM_UI_PORT || '4821';
  const API_BASE = `http://127.0.0.1:${PORT}`;
  const STORAGE_KEY = 'NM2.navRail.expanded';
  const ROLLED_STORAGE_KEY = 'NM2.navRail.rolled';
  const STATE_CACHE_KEY = 'NM2.navRail.workbenchState';

  /**
   * api  Provide the api helper used by shared module navigation rail.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function api(path){ return `${API_BASE}${path}`; }
  /**
   * esc  Escape text before inserting it into HTML markup.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  /**
   * arr  Normalize a nullable scalar or array-like value to an array.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function arr(x){ return x == null ? [] : (Array.isArray(x) ? x : [x]); }
  /**
   * icon  Provide the icon helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function icon(id){ return window.NMModuleIconSet ? window.NMModuleIconSet.svg(id) : ''; }
  /**
   * context  Build the context shown to users in the browser UI.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function context(){ return window.NM_MODULE_NAV_CONTEXT || {}; }
  /**
   * currentModule  Provide the current module helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function currentModule(){ return String(context().currentModule || '').trim().toLowerCase(); }
  /**
   * rawPageState  Provide the raw page state helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function rawPageState(){ return window.NM_WORKBENCH_STATE || window.NM_DATAIO_STATE || window.NM_MENU_STATE || window.NM_ANALYSIS_MANAGER_STATE || window.NM_PREPROCESS_RUNNER_STATE || window.NM_ML_TRAIN_RUNNER_STATE || window.NM_VIS_RUNNER_STATE || window.NM_MLI_RUNNER_STATE || window.NM_MODEL_EXPORT_RUNNER_STATE || window.NM_SYNTH_COORDINATOR_STATE || {}; }
  /**
   * hasModuleList  Return whether the has module list condition holds for the current UI state.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function hasModuleList(S){ return !!(S && Array.isArray(S.modules) && S.modules.length); }
  /**
   * readCachedWorkbenchState  Provide the read cached workbench state helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function readCachedWorkbenchState(){
    try{
      const raw = window.localStorage.getItem(STATE_CACHE_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch(err) { return null; }
  }
  /**
   * writeCachedWorkbenchState  Provide the write cached workbench state helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function writeCachedWorkbenchState(S){
    if(!hasModuleList(S)) return;
    try{
      const minimal = {
        modules: S.modules || [],
        workflowStatus: S.workflowStatus || {},
        defs: S.defs || {},
        analysisCount: S.analysisCount || 0,
        analyses: S.analyses || [],
        analysisList: S.analysisList || []
      };
      window.localStorage.setItem(STATE_CACHE_KEY, JSON.stringify(minimal));
    } catch(err) {}
  }
  /**
   * globalState  Provide the global state helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function globalState(){
    const local = rawPageState() || {};
    if(hasModuleList(local)){
      writeCachedWorkbenchState(local);
      return local;
    }
    const cached = readCachedWorkbenchState();
    if(!cached) return local;
    return Object.assign({}, cached, local, {
      modules: cached.modules || local.modules || [],
      workflowStatus: Object.assign({}, cached.workflowStatus || {}, local.workflowStatus || {}),
      defs: Object.assign({}, cached.defs || {}, local.defs || {})
    });
  }
  /**
   * postJson  Send a JSON request to the local MATLAB bridge and parse the JSON response.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function postJson(path, payload){
    const response = await fetch(api(path), {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload || {})});
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
  /**
   * moduleByPage  Provide the module by page helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function moduleByPage(page){
    const S = globalState();
    const modules = arr(S.modules).filter(Boolean);
    return modules.find(m => String(m.page || '').toLowerCase() === page) || modules.find(m => String(m.key || '').toLowerCase() === page) || null;
  }
  /**
   * workflowFlags  Provide the workflow flags helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function workflowFlags(){
    const S = globalState();
    const workflow = S.workflowStatus || {};
    const defs = S.defs || {};
    const completed = arr(workflow.completed_analyses);
    const analysisCount = Number(S.analysisCount || arr(S.analyses).length || arr(S.analysisList).length || 0);
    const trained = !!workflow.analyses_ready || completed.some(Boolean) || arr(S.analyses).some(a => a && a.enabled !== false);
    return {
      importFinished: !!defs.import_finished || !!workflow.import_finished,
      analysesLocked: !!defs.analyses_locked || !!workflow.analyses_locked,
      setupOk: !!workflow.setup_ok || analysisCount > 0,
      analysesExist: !!workflow.analyses_exist || analysisCount > 0,
      trained
    };
  }
  /**
   * itemFromWorkbench  Provide the item from workbench helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function itemFromWorkbench(page, fallback){
    const m = moduleByPage(page);
    if(!m) return fallback;
    return Object.assign({}, fallback, { enabled: !!m.enabled, disabledReason: m.disabledReason || fallback.disabledReason || '', status: m.statusLabel || '', tone: m.statusTone || '' });
  }
  /**
   * navItems  Provide the nav items helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function navItems(){
    const f = workflowFlags();
    const base = [
      {id:'workbench', label:'Workbench', icon:'workbench', page:'workbench', enabled:true},
      {id:'load_nm', label:'Load NM', icon:'load_nm', page:'load_nm', enabled:true},
      {id:'save_nm', label:'Save NM', icon:'save_nm', page:'save_nm', enabled:true},
      itemFromWorkbench('dataio', {id:'data_manager', label:'Data manager', icon:'data_manager', page:'dataio', enabled:true}),
      itemFromWorkbench('template', {id:'template', label:'Template', icon:'template', page:'template', enabled:f.importFinished && !f.analysesLocked, disabledReason:'Requires finalized training data and discovery mode.'}),
      itemFromWorkbench('analysis_manager', {id:'analysis_manager', label:'Analysis manager', icon:'analysis_manager', page:'analysis_manager', enabled:f.importFinished && f.setupOk, disabledReason:'Requires a configured NM workspace.'}),
      itemFromWorkbench('preprocess', {id:'preprocess', label:'Preprocessing', icon:'preprocessing', page:'preprocess', enabled:f.importFinished && !f.analysesLocked && f.setupOk && f.analysesExist, disabledReason:'Requires initialized discovery analyses.'}),
      itemFromWorkbench('mltrain', {id:'mltrain', label:'ML training', icon:'ml_training', page:'mltrain', enabled:f.importFinished && !f.analysesLocked && f.setupOk && f.analysesExist, disabledReason:'Requires initialized discovery analyses.'}),
      itemFromWorkbench('visualization', {id:'visualization', label:'Visualization', icon:'visualization', page:'visualization', enabled:f.trained && !f.analysesLocked, disabledReason:'Requires at least one trained analysis.'}),
      itemFromWorkbench(f.analysesLocked ? 'oocv_mli' : 'mli', {id:'mli', label:f.analysesLocked ? 'OOCV ML interpretation' : 'ML interpretation', icon:'mli', page:'mli', enabled:f.trained, disabledReason:'Requires at least one trained analysis.'}),
      itemFromWorkbench('model_export', {id:'model_export', label:'Model export', icon:'model_export', page:'model_export', enabled:f.trained, disabledReason:'Requires at least one trained analysis.'}),
      itemFromWorkbench('oocv_runner', {id:'oocv', label:'OOCV / application', icon:'oocv_model_application', page:'oocv_runner', enabled:false, disabledReason:'OOCV runner availability is determined in Workbench.'}),
      itemFromWorkbench('results_alpha', {id:'results', label:'Results viewer', icon:'results', page:'results_alpha', enabled:f.trained, disabledReason:'Requires at least one completed analysis.'}),
      itemFromWorkbench('synth_coordinator', {id:'synth_coordinator', label:'SYNTH coordinator', icon:'synth_coordinator', page:'synth_coordinator', enabled:f.importFinished && !f.analysesLocked, disabledReason:'Requires finalized existing training data.'}),
    ];
    const cur = currentModule();
    return base.map(x => Object.assign({}, x, {active: cur === x.id || cur === x.page || (x.id === 'results' && (cur === 'results_alpha' || cur === 'results_viewer_alpha'))}));
  }
  /**
   * setExpanded  Provide the set expanded helper used by shared module navigation rail.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setExpanded(rail, on){
    rail.classList.toggle('isExpanded', !!on);
    rail.setAttribute('aria-expanded', on ? 'true' : 'false');
    const btn = rail.querySelector('.nmNavToggle');
    if(btn){
      btn.setAttribute('aria-label', on ? 'Collapse navigation rail' : 'Expand navigation rail');
      btn.setAttribute('title', on ? 'Collapse navigation rail' : 'Expand navigation rail');
      btn.innerHTML = icon(on ? 'chevron_left' : 'chevron_right');
    }
    try { window.localStorage.setItem(STORAGE_KEY, on ? '1' : '0'); } catch(err) {}
  }
  /**
   * initialExpanded  Provide the initial expanded helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function initialExpanded(){ return false; }
  /**
   * initialRolled  Provide the initial rolled helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function initialRolled(){
    try { return window.localStorage.getItem(ROLLED_STORAGE_KEY) === '1'; } catch(err) { return false; }
  }
  /**
   * setRolled  Provide the set rolled helper used by shared module navigation rail.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function setRolled(rail, on){
    const rolled = !!on;
    document.body.classList.toggle('nmNavRailRolled', rolled);
    rail.classList.toggle('isRolled', rolled);
    rail.setAttribute('aria-hidden', 'false');
    const btn = rail.querySelector('.nmNavRollToggle');
    if(btn){
      btn.setAttribute('aria-label', rolled ? 'Show navigation rail' : 'Hide navigation rail');
      btn.setAttribute('title', rolled ? 'Show navigation rail' : 'Hide navigation rail');
      btn.innerHTML = icon(rolled ? 'chevron_down' : 'chevron_up');
    }
    const expandBtn = rail.querySelector('.nmNavToggle');
    if(expandBtn){
      expandBtn.disabled = rolled;
      expandBtn.setAttribute('aria-disabled', rolled ? 'true' : 'false');
      expandBtn.setAttribute('title', rolled ? 'Show the navigation rail before expanding it.' : (rail.classList.contains('isExpanded') ? 'Collapse navigation rail' : 'Expand navigation rail'));
    }
    const restore = document.querySelector('.nmNavRestoreToggle');
    if(restore){ restore.style.display = 'none'; }
    try { window.localStorage.setItem(ROLLED_STORAGE_KEY, rolled ? '1' : '0'); } catch(err) {}
  }
  /**
   * collapseForNavigation  Provide the collapse for navigation helper used by shared module navigation rail.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function collapseForNavigation(rail){
    const target = rail || document.querySelector('.nmNavRail');
    if(target && target.classList.contains('isExpanded')) setExpanded(target, false);
  }
  /**
   * openWorkbench  Open the workbench panel, dialog or linked UI target.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function openWorkbench(){
    try{
      const out = await matlabService({operation:'app_child_return', source:'nav_rail', timeout:120});
      if(out && out.ok === false) throw new Error(out.message || out.error || 'Workbench return failed.');
    } catch(err) {
      /* Direct navigation is acceptable when no child-return handler is active. */
    }
    window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`nm_workbench.html?port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`) : `nm_workbench.html?port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`);
  }
  /**
   * openPage  Open the page panel, dialog or linked UI target.
   * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
   * item.active: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   * item.enabled: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   * item.label: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   * item.page: browser-side field consumed from item while translating UI state to MATLAB-service requests.
   * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
   */
  async function openPage(item){
    if(!item || !item.enabled || item.active) return;
    if(item.page === 'load_nm' || item.page === 'save_nm'){
      await workspaceAction(item.page === 'load_nm' ? 'load' : 'save');
      return;
    }
    collapseForNavigation();
    if(item.page === 'workbench'){ await openWorkbench(); return; }
    const out = await matlabService({operation:'app_prepare_page', page:item.page, timeout:240});
    if(!out || out.ok === false) throw new Error((out && (out.message || out.error)) || `Could not prepare ${item.label}.`);
    const target = out.entryHtml || out.page || '';
    if(!target) throw new Error(`Prepared ${item.label} did not return an entry HTML file.`);
    const sep = target.includes('?') ? '&' : '?';
    window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(`${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`) : `${target}${sep}port=${encodeURIComponent(PORT)}&_nmcb=${Date.now()}`);
  }
  /** Confirm quitting with the MATLAB-persisted user preference. */
  async function confirmQuit(){
    const preference = await matlabService({operation:'quit_preference_get'});
    if(preference.ok !== true) throw new Error(preference.message);
    if(preference.skipConfirmation) return true;
    const choice = await new Promise(resolve => {
      const dialog = document.createElement('dialog');
      dialog.className = 'nmNavDialog';
      dialog.setAttribute('aria-labelledby', 'nmNavQuitDialogTitle');
      dialog.innerHTML = `<form method="dialog"><h2 id="nmNavQuitDialogTitle">Quit NM?</h2><label><input type="checkbox" name="skipConfirmation"> Don't ask again</label><div class="nmNavQuitDialogActions"><button type="submit" value="cancel" autofocus>Cancel</button><button type="submit" value="quit">Quit NM</button></div></form>`;
      document.body.appendChild(dialog);
      dialog.addEventListener('close', () => {
        const choice = {confirmed:dialog.returnValue === 'quit', remember:dialog.querySelector('[name="skipConfirmation"]').checked};
        dialog.remove();
        resolve(choice);
      }, {once:true});
      dialog.showModal();
    });
    if(choice.confirmed && choice.remember){
      const saved = await matlabService({operation:'quit_preference_set'});
      if(saved.ok !== true) throw new Error(saved.message);
    }
    return choice.confirmed;
  }
  /**
   * workspaceAction  Shared header/sidebar entry for NM MAT-file persistence.
   */
  async function workspaceAction(action){
    if(action === 'quit'){
      if(!await confirmQuit())return;
      const source=currentModule();
      const returned=source==='workbench' ? await postJson('/api/current',rawPageState()) : await matlabService({operation:'app_child_return',source:source==='data_manager'?'dataio':source,timeout:120});
      if(source==='workbench' ? returned.status!=='ok' : returned.ok!==true)throw new Error(returned.message);
      if((await postJson('/api/close',{closed:true,source:'workbench'})).status !== 'closed') throw new Error('NM2 session close was rejected by the bridge.');
      document.body.innerHTML = '<main role="status" style="max-width:36rem;margin:12vh auto;padding:2rem;background:#fff;border:1px solid #cbd5e1;border-radius:12px;font:15px system-ui;color:#1f2937"><h2>NeuroMiner session closed</h2><p>You may close this browser tab if it did not close automatically.</p></main>';
      return window.close();
    }
    if(action === 'save' && currentModule() !== 'workbench' &&
       !window.confirm('Save the last committed NM workspace? Unapplied changes on this page are not included.')) return;
    const picked = await postJson('/api/pickpath', {
      kind:action === 'load' ? 'file' : 'save', filter:'*.mat',
      initial:action === 'save' ? 'NM.mat' : '',
      title:action === 'load' ? 'Load NeuroMiner structure' : 'Save NeuroMiner structure', timeout:600
    });
    if(picked.error) throw new Error(picked.error);
    const path = arr(picked.paths)[0];
    if(!path) return;
    if(!window.NMModal) await import('./NMModal.js');
    if(!window.NMRuntimeProgressViewer) await import('./NMRuntimeProgressViewer.js');
    const viewer = new window.NMRuntimeProgressViewer({port:PORT,title:action === 'load' ? 'Loading NM structure...' : 'Saving NM structure...',lowerTitle:'File operation',singleIndeterminate:true});
    viewer.open('',`${action === 'load' ? 'Loading' : 'Saving'} NM structure: ${path.split(/[\\/]/).pop()}`);
    try {
      const out = await matlabService({operation:action === 'load' ? 'app_workbench_load_nm' : 'app_workbench_save_nm',path,timeout:600});
      if(out.ok === false) return reportError(out.message || out.error);
      if(action === 'load') await (currentModule() === 'workbench' ? window.NMWorkbenchUIRefresh() : openWorkbench());
      else window.NMUIMessageTools.setMessage(out.message, 'ok');
    } finally {
      viewer.hide();
    }
  }
  /**
   * reportError  Provide the report error helper used by shared module navigation rail.
   * It supports shared module navigation rail at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function reportError(text){
    const msg = String(text || 'Navigation failed.');
    window.NMUIMessageTools.setMessage(msg, 'danger');
  }
  /**
   * renderItems  Render the items UI region from current browser state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function renderItems(rail){
    const list = rail && rail.querySelector('.nmNavList');
    if(!list) return;
    list.innerHTML = '';
    navItems().forEach(item => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'nmNavItem' + (item.active ? ' isActive' : '') + (!item.enabled ? ' isDisabled' : '') + (item.planned ? ' isPlanned' : '');
      b.setAttribute('data-page', item.page || '');
      b.setAttribute('title', item.enabled ? item.label : `${item.label}: ${item.disabledReason || 'Not available.'}`);
      b.disabled = !item.enabled;
      b.innerHTML = `<span class="nmNavIcon">${icon(item.icon)}</span><span class="nmNavLabel">${esc(item.label)}</span>${item.planned ? '<span class="nmNavBadge">planned</span>' : ''}`;
      if(item.enabled){ b.addEventListener('click', () => openPage(item).catch(err => reportError(err.message || String(err)))); }
      list.appendChild(b);
    });
  }
  /**
   * buildRail  Build the rail structure or markup used by the page.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function buildRail(){
    document.body.classList.add('nmHasNavRail');
    let rail = document.querySelector('.nmNavRail');
    if(!rail){
      rail = document.createElement('nav');
      rail.className = 'nmNavRail';
      rail.setAttribute('aria-label', 'NeuroMiner module navigation');
      rail.innerHTML = `<div class="nmNavHeader"><div class="nmNavBrand">NM2</div><div class="nmNavHeaderControls"><button class="nmNavRollToggle" type="button"></button><button class="nmNavToggle" type="button"></button></div></div><div class="nmNavList" role="list"></div><div class="nmNavFooter"><button class="nmNavItem nmNavQuit" type="button" title="Quit NM" aria-label="Quit NM"><span class="nmNavIcon">${icon('quit_nm')}</span></button></div>`;
      document.body.insertBefore(rail, document.body.firstChild);
      const roll = rail.querySelector('.nmNavRollToggle');
      if(roll) roll.addEventListener('click', () => setRolled(rail, !rail.classList.contains('isRolled')));
      const t = rail.querySelector('.nmNavToggle');
      if(t) t.addEventListener('click', () => setExpanded(rail, !rail.classList.contains('isExpanded')));
      rail.querySelector('.nmNavQuit').addEventListener('click', () => workspaceAction('quit').catch(err => reportError(err.message || String(err))));
      let restore = document.querySelector('.nmNavRestoreToggle');
      if(!restore){
        restore = document.createElement('button');
        restore.type = 'button';
        restore.className = 'nmNavRestoreToggle';
        restore.addEventListener('click', () => setRolled(rail, false));
        document.body.appendChild(restore);
      }
      setExpanded(rail, initialExpanded());
      setRolled(rail, initialRolled());
    }
    renderItems(rail);
    window.requestAnimationFrame(() => document.body.classList.add('nmNavReady'));
  }
  /**
   * decorateHeader  Provide the decorate header helper used by shared module navigation rail.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function decorateHeader(){
    const cur = currentModule();
    if(!cur || document.querySelector('.nmHeaderModuleIcon')) return;
    const title = document.querySelector('header .title, .wbHeader .title');
    if(!title) return;
    const span = document.createElement('span');
    span.className = 'nmHeaderModuleIcon';
    span.innerHTML = icon(cur);
    title.insertBefore(span, title.firstChild);
  }
  function updateReturnButton(ctx, standaloneLabel){
    const button = document.getElementById('finish');
    if(!button) return;
    if(ctx && ctx.returnPage === 'nm_synth_coordinator.html') button.textContent = 'Return to SYNTH';
    else if(ctx && (ctx.returnToWorkbench || ctx.caller === 'workbench')) button.textContent = '← To Workbench';
    else if(standaloneLabel) button.textContent = standaloneLabel;
  }
  document.addEventListener('DOMContentLoaded', () => { updateReturnButton((window.NM_RESULTS_VIEWER_ALPHA_STATE || window.NM_OOCV_RUNNER_STATE || rawPageState()).appContext); buildRail(); decorateHeader(); });
  window.NMModuleNavigationRail = { rebuild: buildRail, refresh: buildRail, items: navItems, workspaceAction, updateReturnButton };
})();

/* NM2 shared visual-theme layer. Presentation preference only: it never reads or mutates NM scientific/workflow state. */
(function(){
  'use strict';
  const THEME_STORAGE_KEY = 'NM2.ui.theme';
  const STYLE_ID = 'nm2SharedThemeStyles';
  const THEMES = [
    {id:'neutral', label:'Neutral'},
    {id:'cool-slate', label:'Cool Slate'},
    {id:'warm-neutral', label:'Warm Neutral'},
    {id:'dark-navy', label:'Dark Navy'}
  ];

  function normalizeTheme(value){
    const id = String(value || '').trim().toLowerCase();
    return THEMES.some(t => t.id === id) ? id : 'neutral';
  }

  function storedTheme(){
    try { return normalizeTheme(window.localStorage.getItem(THEME_STORAGE_KEY)); }
    catch(err) { return 'neutral'; }
  }

  function applyTheme(value, persist){
    const id = normalizeTheme(value);
    document.documentElement.setAttribute('data-nm-theme', id);
    if(persist !== false){
      try { window.localStorage.setItem(THEME_STORAGE_KEY, id); } catch(err) {}
    }
    const select = document.querySelector('.nmNavThemeSelect');
    if(select && select.value !== id) select.value = id;
    return id;
  }

  function installThemeStyles(){
    if(document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
:root{
  --nm-page-bg:#F4F5F6;--nm-surface:#FFFFFF;--nm-surface-soft:#F8F9FA;--nm-surface-elevated:#FFFFFF;
  --nm-border:#D6DDE3;--nm-text:#20242A;--nm-muted:#65717D;--nm-accent:#456B8A;--nm-accent-hover:#355A78;--nm-accent-soft:#E8EFF5;--nm-disabled:#87939E;
  --nm-header-bg:#17202A;--nm-header-text:#F7FAFC;--nm-header-muted:#C9D2DC;--nm-nav-bg:#111827;--nm-nav-bg2:#17202A;--nm-nav-ink:#E5EDF6;--nm-nav-muted:#9AA8B8;--nm-nav-active:#67A4D3;
  --nm-success:#19724B;--nm-success-soft:#E8F6EE;--nm-success-border:#A9D8BF;--nm-warning:#9A5C13;--nm-warning-soft:#FFF4E6;--nm-warning-border:#E9C78F;
  --nm-danger:#9B3030;--nm-danger-soft:#FCEDED;--nm-danger-border:#E3AAAA;--nm-future:#55779A;--nm-future-soft:#EEF4FA;--nm-future-border:#C5D5E5;
  --nm-stage-active-bg:#F1FAF6;--nm-stage-active-border:#ADD9C7;--nm-stage-done-bg:#FFF7ED;--nm-stage-done-border:#EDC083;--nm-stage-future-bg:#F2F7FF;--nm-stage-future-border:#BFD2EE;--nm-gate-bg:#F4EFF8;--nm-gate-border:#C8B6D8;--nm-gate-ink:#6B4A7D;--nm-gate-card-bg:#E8DDF0;--nm-gate-card-border:#B79DCB;--nm-gate-card-ink:#57386D;--nm-gate-passed-bg:#F0EDF2;--nm-gate-passed-border:#CFC7D3;--nm-gate-passed-ink:#786F7E;--nm-gate-passed-card-bg:#E5E1E7;--nm-gate-passed-card-border:#C3BCC8;
  --nm-toolbar-bg:#F2F3D2;--nm-toolbar-border:#CAD06F;--nm-toolbar-card:#DEE29A;--nm-toolbar-card-border:#B8C04F;--nm-toolbar-card-hover:#E5E8AA;--nm-toolbar-disabled-bg:#DADCCB;--nm-toolbar-disabled-border:#C1C5A0;
  --nm-shadow:0 8px 24px rgba(15,23,42,.07);
}
html[data-nm-theme="cool-slate"]{
  --nm-page-bg:#EDF2F6;--nm-surface:#F9FBFC;--nm-surface-soft:#F1F5F8;--nm-surface-elevated:#FFFFFF;--nm-border:#C7D3DE;--nm-text:#1D2A33;--nm-muted:#60717E;
  --nm-accent:#376B91;--nm-accent-hover:#285A7E;--nm-accent-soft:#DFEAF2;--nm-disabled:#83919D;--nm-header-bg:#162431;--nm-header-muted:#C2CFDA;--nm-nav-bg:#0F1923;--nm-nav-bg2:#162431;--nm-nav-active:#5E9BC7;
  --nm-stage-active-bg:#EDF8F3;--nm-stage-active-border:#A5D3C1;--nm-stage-done-bg:#FBF2E7;--nm-stage-done-border:#DFB77E;--nm-stage-future-bg:#EAF1F8;--nm-stage-future-border:#B5C9DC;--nm-gate-bg:#EEF0F7;--nm-gate-border:#C2BCD4;--nm-gate-ink:#62577A;--nm-gate-card-bg:#E0DDEC;--nm-gate-card-border:#ABA3C1;--nm-gate-card-ink:#504664;--nm-gate-passed-bg:#EBEDF1;--nm-gate-passed-border:#C4C7CD;--nm-gate-passed-ink:#73767D;--nm-gate-passed-card-bg:#DDE0E5;--nm-gate-passed-card-border:#B7BBC2;
  --nm-toolbar-bg:#E3E8D3;--nm-toolbar-border:#B6C18F;--nm-toolbar-card:#CDD9B3;--nm-toolbar-card-border:#9EAF78;--nm-toolbar-card-hover:#D5DFC0;--nm-toolbar-disabled-bg:#D4D8D0;--nm-toolbar-disabled-border:#B9C0AE;
}
html[data-nm-theme="warm-neutral"]{
  --nm-page-bg:#F5F1EB;--nm-surface:#FFFCF8;--nm-surface-soft:#F8F3EC;--nm-surface-elevated:#FFFFFF;--nm-border:#DDD3C6;--nm-text:#2D2925;--nm-muted:#746C63;
  --nm-accent:#5C7180;--nm-accent-hover:#465D6D;--nm-accent-soft:#E8ECEE;--nm-disabled:#938B82;--nm-header-bg:#2D3136;--nm-header-muted:#D2CEC7;--nm-nav-bg:#22282F;--nm-nav-bg2:#2D333A;--nm-nav-active:#7EA5BE;
  --nm-stage-active-bg:#F2F8F3;--nm-stage-active-border:#B5D2BC;--nm-stage-done-bg:#FFF4E5;--nm-stage-done-border:#E2BB80;--nm-stage-future-bg:#EFF3F6;--nm-stage-future-border:#C5D0D7;--nm-gate-bg:#F4EFF7;--nm-gate-border:#CDBDD3;--nm-gate-ink:#705374;--nm-gate-card-bg:#E9DEE9;--nm-gate-card-border:#BDA6BF;--nm-gate-card-ink:#5D415F;--nm-gate-passed-bg:#F0ECEF;--nm-gate-passed-border:#CEC6CA;--nm-gate-passed-ink:#7B7277;--nm-gate-passed-card-bg:#E4DEE2;--nm-gate-passed-card-border:#C2B9BF;
  --nm-toolbar-bg:#F0EAC7;--nm-toolbar-border:#CEBF7D;--nm-toolbar-card:#DED1A0;--nm-toolbar-card-border:#BFA95E;--nm-toolbar-card-hover:#E5D9AE;--nm-toolbar-disabled-bg:#DDD7C8;--nm-toolbar-disabled-border:#C6BDA5;
}
html[data-nm-theme="dark-navy"]{
  color-scheme:dark;
  --nm-page-bg:#0E1A2B;--nm-surface:#14233A;--nm-surface-soft:#172840;--nm-surface-elevated:#1A2D49;--nm-border:#2A4263;--nm-text:#F2F6FA;--nm-muted:#AEB9C8;
  --nm-accent:#70A8D5;--nm-accent-hover:#8ABBE1;--nm-accent-soft:#193653;--nm-disabled:#66758A;--nm-header-bg:#0A1422;--nm-header-text:#F4F7FB;--nm-header-muted:#9FAFC1;--nm-nav-bg:#07111D;--nm-nav-bg2:#0A1422;--nm-nav-ink:#E6EEF7;--nm-nav-muted:#90A0B3;--nm-nav-active:#70B7E8;
  --nm-success:#63C99A;--nm-success-soft:#12362E;--nm-success-border:#2F6E5B;--nm-warning:#E4B46E;--nm-warning-soft:#342817;--nm-warning-border:#765A30;
  --nm-danger:#EE8B8B;--nm-danger-soft:#3A2025;--nm-danger-border:#7D4048;--nm-future:#8AAACB;--nm-future-soft:#142943;--nm-future-border:#355277;
  --nm-stage-active-bg:#102C28;--nm-stage-active-border:#2F6E5B;--nm-stage-done-bg:#302418;--nm-stage-done-border:#765A30;--nm-stage-future-bg:#142943;--nm-stage-future-border:#355277;--nm-gate-bg:#252039;--nm-gate-border:#574A72;--nm-gate-ink:#C7B4E2;--nm-gate-card-bg:#332A48;--nm-gate-card-border:#735D91;--nm-gate-card-ink:#E0D4F0;--nm-gate-passed-bg:#23242F;--nm-gate-passed-border:#484855;--nm-gate-passed-ink:#9C96A7;--nm-gate-passed-card-bg:#2C2B36;--nm-gate-passed-card-border:#55525F;
  --nm-toolbar-bg:#17243A;--nm-toolbar-border:#66623C;--nm-toolbar-card:#0F2035;--nm-toolbar-card-border:#526884;--nm-toolbar-card-hover:#142943;--nm-toolbar-disabled-bg:#30363B;--nm-toolbar-disabled-border:#5E604D;
  --nm-shadow:0 10px 28px rgba(0,0,0,.28);
}

html[data-nm-theme]{
  --bg:var(--nm-page-bg);--panel:var(--nm-surface);--line:var(--nm-border);--text:var(--nm-text);--muted:var(--nm-muted);--primary:var(--nm-accent);--ok:var(--nm-success);--warn:var(--nm-warning);--danger:var(--nm-danger);
  --nmNavBg:var(--nm-nav-bg);--nmNavBg2:var(--nm-nav-bg2);--nmNavInk:var(--nm-nav-ink);--nmNavMuted:var(--nm-nav-muted);--nmNavActive:var(--nm-nav-active);--nmNavBorder:color-mix(in srgb,var(--nm-nav-ink) 12%,transparent);
  --wb-bg:var(--nm-page-bg);--wb-card:var(--nm-surface);--wb-border:var(--nm-border);--wb-ink:var(--nm-text);--wb-muted:var(--nm-muted);--wb-accent:var(--nm-accent);--wb-soft:var(--nm-accent-soft);
  --wb-active-bg:var(--nm-stage-active-bg);--wb-active-border:var(--nm-stage-active-border);--wb-done-bg:var(--nm-stage-done-bg);--wb-done-border:var(--nm-stage-done-border);--wb-future-bg:var(--nm-stage-future-bg);--wb-future-border:var(--nm-stage-future-border);
  --wb-lock:var(--nm-warning);--wb-lock-dark:var(--nm-warning);--wb-lock-soft:var(--nm-warning-soft);--wb-lock-border:var(--nm-warning-border);--wb-disabled:var(--nm-disabled);
  --wb-gate-bg:var(--nm-gate-bg);--wb-gate-border:var(--nm-gate-border);--wb-gate-ink:var(--nm-gate-ink);--wb-gate-card-bg:var(--nm-gate-card-bg);--wb-gate-card-border:var(--nm-gate-card-border);--wb-gate-card-ink:var(--nm-gate-card-ink);--wb-gate-passed-bg:var(--nm-gate-passed-bg);--wb-gate-passed-border:var(--nm-gate-passed-border);--wb-gate-passed-ink:var(--nm-gate-passed-ink);--wb-gate-passed-card-bg:var(--nm-gate-passed-card-bg);--wb-gate-passed-card-border:var(--nm-gate-passed-card-border);
}

html[data-nm-theme] body{background:var(--nm-page-bg);color:var(--nm-text);}
html[data-nm-theme] header,html[data-nm-theme] .wbHeader,html[data-nm-theme] .rvHeader{background:var(--nm-header-bg);color:var(--nm-header-text);border-color:var(--nm-border);}
html[data-nm-theme] header .crumb,html[data-nm-theme] .wbHeader .crumb,html[data-nm-theme] .rvHeader .crumb{color:var(--nm-header-muted);}
html[data-nm-theme] .panel,html[data-nm-theme] .card,html[data-nm-theme] .summaryCard,html[data-nm-theme] .canvasDetails,html[data-nm-theme] .canvasNodeInfo,html[data-nm-theme] .rfeMini,html[data-nm-theme] .prGridSummary,html[data-nm-theme] .rvModalCard,html[data-nm-theme] .rvFloatingPanel{background-color:var(--nm-surface);border-color:var(--nm-border);color:var(--nm-text);box-shadow:var(--nm-shadow);}
html[data-nm-theme] .muted,html[data-nm-theme] .help,html[data-nm-theme] .summaryLabel,html[data-nm-theme] .detailKey,html[data-nm-theme] .rvIntro p,html[data-nm-theme] .rvControls label,html[data-nm-theme] .rvModalCard label{color:var(--nm-muted);}
html[data-nm-theme] input:not([type="checkbox"]):not([type="radio"]):not([type="range"]),html[data-nm-theme] select,html[data-nm-theme] textarea{background:var(--nm-surface-elevated);color:var(--nm-text);border-color:var(--nm-border);}
html[data-nm-theme] select option{background:var(--nm-surface);color:var(--nm-text);}
html[data-nm-theme] button:not(.primary):not(.danger):not(.prGenerateButton):not(.nmNavItem):not(.nmNavToggle):not(.nmNavRollToggle):not(.nmNavRestoreToggle){background:var(--nm-surface-elevated);color:var(--nm-text);border-color:var(--nm-border);}
html[data-nm-theme] button:not(.primary):not(.danger):not(.prGenerateButton):not(.nmNavItem):not(.nmNavToggle):not(.nmNavRollToggle):not(.nmNavRestoreToggle):hover:not(:disabled){background:var(--nm-accent-soft);border-color:var(--nm-accent);color:var(--nm-accent-hover);}
/* Pressed/selected buttons use one theme-owned state grammar. These selectors
   deliberately match the state tokens already used across NM2 and outrank
   the normalized neutral button rule above without provenance-specific fixes. */
html[data-nm-theme] button:is([aria-pressed="true"],[aria-selected="true"],.isActive,.active,.is-selected,.is-full):not(.primary):not(.danger):not(.prGenerateButton):not(.nmNavItem):not(.nmNavToggle):not(.nmNavRollToggle):not(.nmNavRestoreToggle):not(:disabled){background:var(--nm-header-bg);border-color:var(--nm-header-bg);color:#fff;}
html[data-nm-theme] button:is([aria-pressed="true"],[aria-selected="true"],.isActive,.active,.is-selected,.is-full):not(.primary):not(.danger):not(.prGenerateButton):not(.nmNavItem):not(.nmNavToggle):not(.nmNavRollToggle):not(.nmNavRestoreToggle):hover:not(:disabled){background:color-mix(in srgb,var(--nm-header-bg) 86%,var(--nm-accent) 14%);border-color:var(--nm-accent);color:#fff;}
html[data-nm-theme] button.primary,html[data-nm-theme] .tab.active,html[data-nm-theme] .appMenuStrip button.analysisBtn,html[data-nm-theme] .rfeTab.active,html[data-nm-theme] .prGridEditButton{background:var(--nm-accent);border-color:var(--nm-accent);color:#fff;}
html[data-nm-theme] button.primary:hover,html[data-nm-theme] .tab.active:hover,html[data-nm-theme] .appMenuStrip button.analysisBtn:hover,html[data-nm-theme] .rfeTab.active:hover,html[data-nm-theme] .prGridEditButton:hover{background:var(--nm-accent-hover);border-color:var(--nm-accent-hover);}
html[data-nm-theme] button:disabled:not(.prGenerateButton){background:var(--nm-surface-soft);border-color:var(--nm-border);color:var(--nm-disabled);box-shadow:none;}
html[data-nm-theme] a{color:var(--nm-accent);}
html[data-nm-theme] code{background:var(--nm-surface-soft);color:var(--nm-text);}
html[data-nm-theme] .appMenuStrip,html[data-nm-theme] .tableWrap,html[data-nm-theme] .rvTableWrap,html[data-nm-theme] .rvLegacyPlotToolbar{background:var(--nm-surface);border-color:var(--nm-border);}
html[data-nm-theme] th,html[data-nm-theme] .rvTable th{background:var(--nm-surface-soft);color:var(--nm-text);border-color:var(--nm-border);}
html[data-nm-theme] td,html[data-nm-theme] .rvTable td{color:var(--nm-text);border-color:var(--nm-border);}


html[data-nm-theme] .notice,html[data-nm-theme] .message.warn,html[data-nm-theme] .pill.warn{background:var(--nm-warning-soft);border-color:var(--nm-warning-border);color:var(--nm-warning);}
html[data-nm-theme] .message,html[data-nm-theme] .pill,html[data-nm-theme] .rolePanel{background:var(--nm-surface-soft);border-color:var(--nm-border);color:var(--nm-text);}
html[data-nm-theme] .message.ok,html[data-nm-theme] .pill.ok{background:var(--nm-success-soft);border-color:var(--nm-success-border);color:var(--nm-success);}
html[data-nm-theme] .message.danger,html[data-nm-theme] .pill.danger{background:var(--nm-danger-soft);border-color:var(--nm-danger-border);color:var(--nm-danger);}
html[data-nm-theme] .pill.info,html[data-nm-theme] .tab{background:var(--nm-accent-soft);border-color:var(--nm-border);color:var(--nm-accent);}
html[data-nm-theme] .pill.oocvPotential{display:inline-block;white-space:nowrap;border-radius:999px;padding:2px 8px;font-size:12px;border:1px solid #D4B544;background:#FFF2A6;color:#624C00;}
html[data-nm-theme] tr.modalityRow:hover{background:var(--nm-accent-soft);}
html[data-nm-theme] tr.oocvRow:hover{background:var(--nm-success-soft);}
html[data-nm-theme] tr.modalityRow.selected{background:var(--nm-accent-soft);box-shadow:inset 4px 0 0 var(--nm-accent);}
html[data-nm-theme] tr.oocvRow.selected{background:var(--nm-success-soft);box-shadow:inset 4px 0 0 var(--nm-success);}
html[data-nm-theme] .formGrid label,html[data-nm-theme] .oocvLabelCheck span{color:var(--nm-text);}

html[data-nm-theme] .wbHero{background:var(--nm-surface);border-color:var(--nm-border);box-shadow:var(--nm-shadow);}
html[data-nm-theme] .wbStatusCard{background:var(--nm-surface-soft);border-color:var(--nm-border);}
html[data-nm-theme] .wbStage-active{background:var(--nm-stage-active-bg)!important;border-color:var(--nm-stage-active-border)!important;}
html[data-nm-theme] .wbStage-completed{background:var(--nm-stage-done-bg)!important;border-color:var(--nm-stage-done-border)!important;}
html[data-nm-theme] .wbStage-future{background:var(--nm-stage-future-bg)!important;border-color:var(--nm-stage-future-border)!important;}
html[data-nm-theme] .wbModuleCard{background:var(--nm-surface-soft);border-color:var(--nm-border);}
html[data-nm-theme] .wbModuleCard:has(>button:not(:disabled)):hover{background:var(--nm-surface-elevated);border-color:var(--nm-accent);}
html[data-nm-theme] .wbGateSection{background:var(--nm-gate-bg);border-color:var(--nm-gate-border);}
html[data-nm-theme] .wbGate-blocked{background:color-mix(in srgb,var(--nm-gate-passed-bg) 72%,var(--nm-surface-soft) 28%);border-color:var(--nm-gate-passed-border);}
html[data-nm-theme] .wbGate-complete{background:var(--nm-gate-passed-bg);border-color:var(--nm-gate-passed-border);}
html[data-nm-theme] .wbBottomToolbar{background:var(--nm-toolbar-bg);border-color:var(--nm-toolbar-border);box-shadow:0 -8px 24px rgba(76,82,18,.12);}
html[data-nm-theme] body .wbBottomToolbar .wbModuleCard{background:var(--nm-toolbar-card)!important;border-color:var(--nm-toolbar-card-border)!important;}
html[data-nm-theme] body .wbBottomToolbar .wbModuleCard:has(>button:not(:disabled)):hover{background:var(--nm-toolbar-card-hover)!important;border-color:var(--nm-toolbar-card-border)!important;}
html[data-nm-theme] body .wbBottomToolbar .wbModuleCard.disabled{background:var(--nm-toolbar-disabled-bg)!important;border-color:var(--nm-toolbar-disabled-border)!important;}
html[data-nm-theme="dark-navy"] .wbBottomToolbar{box-shadow:0 -8px 24px rgba(0,0,0,.30);}

html[data-nm-theme] .rvShell>.panel,html[data-nm-theme] .rvIntro,html[data-nm-theme] .rvControls,html[data-nm-theme] .rvLegacyPlotToolbar,html[data-nm-theme] .rvModalCard,html[data-nm-theme] .rvFloatingPanel{background:var(--nm-surface);border-color:var(--nm-border);color:var(--nm-text);}
html[data-nm-theme] .rvIntro h1,html[data-nm-theme] .rvPanelHead h2,html[data-nm-theme] .rvModalCard h3{color:var(--nm-text);}
html[data-nm-theme] .rvIntro h1 span,html[data-nm-theme] .rvBadge,html[data-nm-theme] .rvMetricBadge{background:var(--nm-accent-soft);border-color:var(--nm-border);color:var(--nm-accent);}
html[data-nm-theme] .rvBadge b{color:var(--nm-text);}
html[data-nm-theme] .rvControls select,html[data-nm-theme] .rvLegacyPlotToolbar select,html[data-nm-theme] .rvLegacyPlotToolbar input,html[data-nm-theme] .rvModalCard select,html[data-nm-theme] .rvPanelControls input[type="number"],html[data-nm-theme] .rvPanelControls select{background:var(--nm-surface-elevated);border-color:var(--nm-border);color:var(--nm-text);}
html[data-nm-theme] .rvLegacyPlotToolbar button,html[data-nm-theme] .rvPanelControls button{background:var(--nm-accent-soft);border-color:var(--nm-border);color:var(--nm-accent);}
html[data-nm-theme] .rvLegacyPlotToolbar button.isActive{background:var(--nm-accent);border-color:var(--nm-accent);color:#fff;}
html[data-nm-theme] .rvFloatingPanelHead{background:var(--nm-header-bg);color:var(--nm-header-text);}
html[data-nm-theme] .rvPanelNotice{background:var(--nm-warning-soft);border-color:var(--nm-warning-border);color:var(--nm-warning);}

html[data-nm-theme] .nmNavRail,html[data-nm-theme] body.nmHasNavRail:not(.nmNavReady)::before{background:linear-gradient(180deg,var(--nm-nav-bg2),var(--nm-nav-bg));color:var(--nm-nav-ink);}
html[data-nm-theme] .nmNavItem{color:var(--nm-nav-muted);}
html[data-nm-theme] .nmNavItem:hover:not(:disabled){background:rgba(255,255,255,.08);color:var(--nm-nav-ink);}
html[data-nm-theme] .nmNavItem.isActive{background:color-mix(in srgb,var(--nm-nav-active) 18%,transparent);color:var(--nm-nav-ink);box-shadow:inset 3px 0 0 var(--nm-nav-active);}
html[data-nm-theme] .nmHeaderModuleIcon{color:var(--nm-nav-active);}
.nmNavThemePicker{display:none;align-items:center;gap:8px;padding:7px;border:1px solid rgba(255,255,255,.10);border-radius:10px;background:rgba(0,0,0,.12);}
.nmNavRail.isExpanded:not(.isRolled) .nmNavThemePicker{display:flex;}
.nmNavThemeLabel{flex:0 0 auto;font-size:9px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;color:var(--nm-nav-muted);}
.nmNavThemeSelect{min-width:0;flex:1 1 auto;height:28px;border:1px solid rgba(255,255,255,.16);border-radius:7px;background:var(--nm-nav-bg);color:var(--nm-nav-ink);font:600 11px/1 system-ui,-apple-system,Segoe UI,Arial,sans-serif;padding:3px 6px;}
`;
    document.head.appendChild(style);
  }

  function installThemePicker(){
    const rail = document.querySelector('.nmNavRail');
    if(!rail) return;
    let picker = rail.querySelector('.nmNavThemePicker');
    if(!picker){
      picker = document.createElement('label');
      picker.className = 'nmNavThemePicker';
      picker.innerHTML = `<span class="nmNavThemeLabel">Colour</span><select class="nmNavThemeSelect" aria-label="NM2 colour style">${THEMES.map(t => `<option value="${t.id}">${t.label}</option>`).join('')}</select>`;
      rail.querySelector('.nmNavFooter').appendChild(picker);
      const select = picker.querySelector('.nmNavThemeSelect');
      if(select) select.addEventListener('change', () => applyTheme(select.value, true));
    }
    const select = picker.querySelector('.nmNavThemeSelect');
    if(select) select.value = normalizeTheme(document.documentElement.getAttribute('data-nm-theme'));
  }

  installThemeStyles();
  applyTheme(storedTheme(), false);
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', installThemePicker);
  else installThemePicker();
  window.NM2Theme = { get: () => normalizeTheme(document.documentElement.getAttribute('data-nm-theme')), set: value => applyTheme(value, true), options: THEMES.slice() };
})();
