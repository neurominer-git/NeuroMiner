(function(){
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
   * clampPct  Provide the clamp pct helper used by shared runtime-progress viewer.
   * It supports shared runtime-progress viewer at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function clampPct(x){ const v = Number(x); return Number.isFinite(v) ? Math.max(0, Math.min(100, v)) : 0; }
  /**
   * createTaskId  Create the task id component or browser-side state object.
   * It supports shared runtime-progress viewer at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function createTaskId(prefix){ return `${prefix || 'runtime'}_${Date.now()}_${Math.random().toString(36).slice(2,9)}`.replace(/[^A-Za-z0-9_-]/g, ''); }

  /**
   * html  Build the html inserted into the browser UI.
   * It supports shared runtime-progress viewer at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   * opts.lowerTitle: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   */
  function html(opts){
    const stageOnly = !!(opts && opts.stageOnly);
    return [
      '<div id="nmRuntimeProgressPanel" class="nmRuntimeProgressPanel">',
      `  <section id="nmRuntimeProgressStageSection" class="nmRuntimeProgressSection" style="${stageOnly?'':'display:none'}">`,
      `    <div class="nmRuntimeProgressLabel">${stageOnly?esc(opts.stageUnit):'Processing stage'}</div>`,
      '    <div class="nmRuntimeProgressHead"><div id="nmRuntimeProgressStageText" class="nmRuntimeProgressText"></div><span id="nmRuntimeProgressStagePercent" class="nmRuntimeProgressPercent"></span></div>',
      '    <div class="nmRuntimeProgressTrack"><div id="nmRuntimeProgressStageBar" class="nmRuntimeProgressBar nmRuntimeProgressBarStage" style="width:0%"></div></div>',
      '  </section>',
      `  <section class="nmRuntimeProgressSection" style="${stageOnly || opts.singleIndeterminate ? 'display:none' : ''}">`,
      `    <div class="nmRuntimeProgressLabel">${esc(opts.overallTitle)}</div>`,
      '    <div class="nmRuntimeProgressHead"><div id="nmRuntimeProgressOverallText" class="nmRuntimeProgressText">Waiting for the first update.</div><span id="nmRuntimeProgressOverallPercent" class="nmRuntimeProgressPercent">0%</span></div>',
      '    <div class="nmRuntimeProgressTrack"><div id="nmRuntimeProgressOverallBar" class="nmRuntimeProgressBar" style="width:0%"></div></div>',
      '  </section>',
      `  <section class="nmRuntimeProgressSection" style="${stageOnly?'display:none':''}">`,
      `    <div id="nmRuntimeProgressLowerLabel" class="nmRuntimeProgressLabel">${esc(opts.lowerTitle)}</div>`,
      '    <div class="nmRuntimeProgressHead"><div id="nmRuntimeProgressLowerText" class="nmRuntimeProgressText">Preparing runtime task.</div><span id="nmRuntimeProgressLowerPercent" class="nmRuntimeProgressPercent">0%</span></div>',
      '    <div class="nmRuntimeProgressTrack"><div id="nmRuntimeProgressLowerBar" class="nmRuntimeProgressBar nmRuntimeProgressBarLower" style="width:0%"></div></div>',
      '    <div id="nmRuntimeProgressMeta" class="nmRuntimeProgressMeta"></div>',
      '  </section>',
      '</div>'
    ].join('');
  }

  /**
   * RuntimeProgressViewer  Provide the runtime progress viewer helper used by shared runtime-progress viewer.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.lowerTitle: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.pollMs: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.port: local HTTP bridge port used by the browser page.
   * opts.title: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function RuntimeProgressViewer(opts){
    this.port = (opts && opts.port) || '4821';
    this.apiBase = `http://127.0.0.1:${this.port}`;
    this.title = (opts && opts.title) || 'Runtime progress';
    this.lowerTitle = (opts && opts.lowerTitle) || 'Runtime progress';
    this.overallTitle = (opts && opts.overallTitle) || 'Overall CV2 progress';
    this.stageOnly = false;
    this.singleIndeterminate = !!(opts && opts.singleIndeterminate);
    this.stageTotal = 0;
    this.stageUnit = opts && opts.stageUnit;
    this.pollMs = Math.max(25, Number((opts && opts.pollMs) || 80));
    this.taskId = '';
    this.timer = null;
    this.closeTimer = null;
    this.modal = null;
  }
  RuntimeProgressViewer.createTaskId = createTaskId;
  RuntimeProgressViewer.prototype.api = function(path){ return `${this.apiBase}${path}`; };
  RuntimeProgressViewer.prototype.open = function(taskId, message){
    this.taskId = taskId || '';
    this.cancelAutoClose();
    if(window.NMModal && typeof window.NMModal.open === 'function'){
      if(this.modal && !this.modal.closed) this.modal.close();
      this.modal = window.NMModal.open({
        title:this.title,
        size:'wide',
        dismissOnBackdrop:false,
        dismissOnEscape:false,
        closeLabel:'Hide viewer',
        closeGlyph:'\u2212',
        render:(body)=>{ body.innerHTML = html({lowerTitle:this.lowerTitle,overallTitle:this.overallTitle,stageOnly:this.stageOnly,stageUnit:this.stageUnit,singleIndeterminate:this.singleIndeterminate}); },
        onClose:()=>{ this.modal = null; }
      });
      // Progress reports its own status; it must not become the global message owner.
      this.modal.dialog.setAttribute('data-nm-message-skip', '');
    }
    let openingMessage = message;
    if (!openingMessage) openingMessage = 'Preparing runtime task.';
    this.update({percent:0, message:openingMessage, active:true, chart:{available:true, title:this.lowerTitle, message:openingMessage, percent:0, indeterminate:this.singleIndeterminate}});
    this.startPolling();
  };
  RuntimeProgressViewer.prototype.cancelAutoClose = function(){ if(this.closeTimer){ window.clearTimeout(this.closeTimer); this.closeTimer = null; } };
  RuntimeProgressViewer.prototype.hide = function(){ this.stopPolling(); this.cancelAutoClose(); if(this.modal && !this.modal.closed){ this.modal.close(); this.modal = null; } };
  RuntimeProgressViewer.prototype.scheduleAutoClose = function(delayMs){ this.cancelAutoClose(); this.closeTimer = window.setTimeout(()=>this.hide(), Math.max(0, Number(delayMs)||0)); };
  RuntimeProgressViewer.prototype.startPolling = function(){
    this.stopPolling();
    if(!this.taskId) return;
    /**
     * tick  Provide the tick helper used by shared runtime-progress viewer.
     * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
     * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
     */
    const tick = async()=>{
      try{
        const response = await fetch(this.api(`/api/progress/${encodeURIComponent(this.taskId)}`), {method:'GET', cache:'no-store'});
        if(!response.ok) return;
        const payload = await response.json();
        if(!payload || payload.taskId !== this.taskId || payload.transient) return;
        if(payload.percent == null && !payload.chart && !payload.overall && payload.active === false && !payload.done && !payload.failed && !payload.cancelled) return;
        if(payload.failed || payload.cancelled){ this.hide(); return; }
        this.update(payload);
        if(payload.done){ this.stopPolling(); this.scheduleAutoClose(550); }
      } catch(_err){
        // Transient locks or partial reads can occur while MATLAB overwrites the JSON file.
      }
    };
    tick();
    this.timer = window.setInterval(tick, this.pollMs);
  };
  RuntimeProgressViewer.prototype.stopPolling = function(){ if(this.timer){ window.clearInterval(this.timer); this.timer = null; } };
  RuntimeProgressViewer.prototype.update = function(payload){
    const panel = document.getElementById('nmRuntimeProgressPanel');
    if(panel) panel.classList.toggle('nmRuntimeProgressFailed', !!(payload && payload.failed));
    const stage = payload && payload.stage && typeof payload.stage === 'object' && payload.stage.available ? payload.stage : null;
    const stageSection = document.getElementById('nmRuntimeProgressStageSection');
    if(stageSection) stageSection.style.display = stage || this.stageOnly ? '' : 'none';
    if(stage || this.stageOnly){
      const stagePct = stage ? clampPct(stage.percent) : 0;
      const stageText = this.stageOnly
        ? `${stage ? stage.current-Number(!stage.completed) : 0} / ${stage ? stage.total : this.stageTotal} completed`
        : stage.message || `${stage.label || 'Runtime stage'} [ ${stage.current || 0} / ${stage.total || 0} steps ]`;
      setText('nmRuntimeProgressStageText', stageText);
      setText('nmRuntimeProgressStagePercent', `${stagePct.toFixed(0)}%`);
      setWidth('nmRuntimeProgressStageBar', stagePct);
    }
    const overall = payload && payload.overall && typeof payload.overall === 'object' ? payload.overall : null;
    const overallPct = clampPct(overall && Number.isFinite(Number(overall.percent)) ? overall.percent : (payload && payload.percent));
    const overallText = (overall && overall.message) || (payload && (payload.message || payload.phase)) || 'Waiting for progress update.';
    setText('nmRuntimeProgressOverallText', overallText);
    setText('nmRuntimeProgressOverallPercent', `${overallPct.toFixed(0)}%`);
    setWidth('nmRuntimeProgressOverallBar', overallPct);

    const chart = payload && payload.chart && typeof payload.chart === 'object' ? payload.chart : null;
    const lowerTitle = (chart && chart.title) || this.lowerTitle;
    const lowerMsg = (chart && (chart.message || chart.progressText)) || (payload && payload.message) || 'Runtime operation is in progress.';
    const lowerPct = clampPct(chart && Number.isFinite(Number(chart.percent)) ? chart.percent : (payload && payload.percent));
    const lowerBar = document.getElementById('nmRuntimeProgressLowerBar');
    if(lowerBar) lowerBar.classList.toggle('nmRuntimeProgressIndeterminate', !!(chart && chart.indeterminate));
    setText('nmRuntimeProgressLowerLabel', lowerTitle);
    setText('nmRuntimeProgressLowerText', lowerMsg);
    setText('nmRuntimeProgressLowerPercent', chart && chart.indeterminate ? '' : `${lowerPct.toFixed(0)}%`);
    setWidth('nmRuntimeProgressLowerBar', lowerPct);
    const meta = [];
    if(chart && chart.phase) meta.push(chart.phase);
    if(overall && overall.currentPartition) meta.push(overall.currentPartition);
    setText('nmRuntimeProgressMeta', meta.join(' · '));
  };
  /**
   * setText  Build the set text shown to users in the browser UI.
   * It supports shared runtime-progress viewer at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setText(id, text){ const node = document.getElementById(id); if(node) node.textContent = text || ''; }
  /**
   * setWidth  Compute the set width layout value used by browser rendering.
   * It supports shared runtime-progress viewer at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function setWidth(id, pct){ const node = document.getElementById(id); if(node) node.style.width = `${clampPct(pct)}%`; }
  window.NMRuntimeProgressViewer = RuntimeProgressViewer;
})();
