/* NMRuntimeGridPicker
 * -------------------------------------------------------------------------
 * Reusable browser CV2 GridAct picker.  The MATLAB source of truth for state
 * and validation is NMRuntimeGridTools; this component mirrors the same basic
 * editing actions client-side so runtime pages can stage selections before
 * submitting them to MATLAB for final validation.
 * ------------------------------------------------------------------------- */
(function(global){
  'use strict';

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
   * dims  Provide the dims helper used by shared CV grid selector embedded in runtime runners.
   * It supports shared CV grid selector embedded in runtime runners at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function dims(G){ return {ix: arr(G).length, jx: arr(G)[0] ? arr(G)[0].length : 0}; }
  /**
   * normalizeGrid  Normalize grid payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalizeGrid(ix, jx, G){
    const raw = arr(G);
    if(!raw.length) return Array.from({length:ix}, () => Array(jx).fill(false));
    const flat = (ix===1 || jx===1) && raw.every(v => typeof v === 'boolean');
    const rows = flat ? Array.from({length:ix}, (_,i) => raw.slice(i*jx,(i+1)*jx)) : raw;
    if(rows.length!==ix || rows.some(row => !Array.isArray(row) || row.length!==jx || row.some(v => typeof v!=='boolean')))
      throw new Error(`Invalid CV2 GridAct: expected ${ix} × ${jx} logical matrix.`);
    return rows.map(row => row.slice());
  }
  /**
   * selectedCount  Apply the ed count selection to browser state and dependent controls.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function selectedCount(G){ return arr(G).reduce((acc,row) => acc + arr(row).filter(Boolean).length, 0); }
  /**
   * makeLabels  Create the labels structure or markup used by the page.
   * It supports shared CV grid selector embedded in runtime runners at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function makeLabels(prefix, n){ return Array.from({length:n}, (_,i) => `${prefix} ${i+1}`); }

  /**
   * GridPicker  Provide the grid picker helper used by shared CV grid selector embedded in runtime runners.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.onChange: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * state.GridAct: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * state.columnLabels: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * state.ix: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * state.jx: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * state.requireAny: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * state.rowLabels: browser-side field consumed from state while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function GridPicker(root, state, opts){
    if(!root) throw new Error('NMRuntimeGridPicker requires a root element.');
    this.root = root;
    this.opts = opts || {};
    this.onChange = typeof this.opts.onChange === 'function' ? this.opts.onChange : function(){};
    this.update(state || {});
  }

  GridPicker.prototype.update = function(state){
    this.state = Object.assign({ix:0, jx:0, GridAct:[], rowLabels:[], columnLabels:[], requireAny:true}, state || {});
    const d = dims(this.state.GridAct);
    this.ix = Number(this.state.ix || d.ix || 0);
    this.jx = Number(this.state.jx || d.jx || 0);
    this.enabled = this.state.enabledMask == null
      ? Array.from({length:this.ix}, () => Array(this.jx).fill(true))
      : normalizeGrid(this.ix, this.jx, this.state.enabledMask);
    this.grid = normalizeGrid(this.ix, this.jx, this.state.GridAct || []);
    this.grid = this.grid.map((row,i) => row.map((cell,j) => cell && this.enabled[i][j]));
    this.cellTitles = arr(this.state.cellTitles).map(row => arr(row));
    this.readOnly = Boolean(this.state.readOnly);
    this.rowLabels = arr(this.state.rowLabels).length ? arr(this.state.rowLabels) : makeLabels('perm', this.ix);
    this.columnLabels = arr(this.state.columnLabels).length ? arr(this.state.columnLabels) : makeLabels('fold', this.jx);
    this.render();
  };

  GridPicker.prototype.getGridAct = function(){ return this.grid.map(row => row.slice()); };

  GridPicker.prototype.applyAction = function(actionSpec){
    const spec = actionSpec || {};
    const action = String(spec.action || spec.operation || '').trim();
    if(!action) throw new Error('Grid action is required.');
    const a = action.toLowerCase();
    if(a === 'selectall') this.forEachCell((i,j) => { this.grid[i][j] = true; });
    else if(a === 'deselectall') this.forEachCell((i,j) => { this.grid[i][j] = false; });
    else if(a === 'toggleall') this.forEachCell((i,j) => { this.grid[i][j] = !this.grid[i][j]; });
    else if(a === 'selectposition') this.setPosition(spec, true);
    else if(a === 'deselectposition') this.setPosition(spec, false);
    else if(a === 'toggleposition') this.togglePosition(spec);
    else if(a === 'selectrange') this.setRange(spec, true);
    else if(a === 'deselectrange') this.setRange(spec, false);
    else if(a === 'togglerange') this.toggleRange(spec);
    else if(a === 'togglerow') this.toggleRowSmart(spec);
    else if(a === 'togglecol' || a === 'togglecolumn') this.toggleColSmart(spec);
    else if(a === 'setmatrix') this.grid = normalizeGrid(this.ix, this.jx, spec.GridAct || spec.matrix || []);
    else throw new Error(`Unsupported GridAct action: ${action}`);
    this.grid = this.grid.map((row,i) => row.map((cell,j) => cell && this.enabled[i][j]));
    this.render();
    this.onChange(this.getGridAct(), this.summary());
  };

  GridPicker.prototype.summary = function(){
    const n = selectedCount(this.grid);
    const total=this.enabled.reduce((count,row) => count + row.filter(Boolean).length,0);
    return {selectedCount:n, totalCount:total, ok: !this.state.requireAny || n > 0};
  };

  GridPicker.prototype.forEachCell = function(fn){
    for(let i=0;i<this.ix;i++) for(let j=0;j<this.jx;j++) if(this.enabled[i][j]) fn(i,j);
  };

  GridPicker.prototype.position = function(spec){
    const p = Array.isArray(spec.position) ? Number(spec.position[0]) : Number(spec.perm || spec.permutation || spec.p);
    const f = Array.isArray(spec.position) ? Number(spec.position[1]) : Number(spec.fold || spec.f);
    if(!Number.isInteger(p) || p < 1 || p > this.ix || !Number.isInteger(f) || f < 1 || f > this.jx) throw new Error('Grid position is outside the valid range.');
    return {i:p-1, j:f-1};
  };

  GridPicker.prototype.range = function(spec){
    const r = Array.isArray(spec.range) ? spec.range.map(Number) : [spec.permStart || spec.pStart || spec.p1, spec.permEnd || spec.pEnd || spec.p2, spec.foldStart || spec.fStart || spec.f1, spec.foldEnd || spec.fEnd || spec.f2].map(Number);
    if(r.length !== 4 || r.some(v => !Number.isInteger(v))) throw new Error('Grid range must be [permStart permEnd foldStart foldEnd].');
    if(r[0] < 1 || r[1] > this.ix || r[2] < 1 || r[3] > this.jx || r[1] < r[0] || r[3] < r[2]) throw new Error('Grid range is outside the valid range.');
    return {p1:r[0]-1, p2:r[1]-1, f1:r[2]-1, f2:r[3]-1};
  };

  GridPicker.prototype.setPosition = function(spec, val){ const p = this.position(spec); if(this.enabled[p.i][p.j]) this.grid[p.i][p.j] = Boolean(val); };
  GridPicker.prototype.togglePosition = function(spec){ const p = this.position(spec); if(this.enabled[p.i][p.j]) this.grid[p.i][p.j] = !this.grid[p.i][p.j]; };
  GridPicker.prototype.setRange = function(spec, val){ const r = this.range(spec); for(let i=r.p1;i<=r.p2;i++) for(let j=r.f1;j<=r.f2;j++) if(this.enabled[i][j]) this.grid[i][j] = Boolean(val); };
  GridPicker.prototype.toggleRange = function(spec){ const r = this.range(spec); for(let i=r.p1;i<=r.p2;i++) for(let j=r.f1;j<=r.f2;j++) if(this.enabled[i][j]) this.grid[i][j] = !this.grid[i][j]; };

  // Smart row/column toggle: if every cell in the row/column is already
  // selected, clear it; otherwise fill it. 1-based perm/fold in the spec.
  GridPicker.prototype.rowIndex = function(spec){
    const p = Number(Array.isArray(spec.position) ? spec.position[0] : (spec.perm || spec.permutation || spec.p || spec.row));
    if(!Number.isInteger(p) || p < 1 || p > this.ix) throw new Error('Grid row is outside the valid range.');
    return p - 1;
  };
  GridPicker.prototype.colIndex = function(spec){
    const f = Number(Array.isArray(spec.position) ? spec.position[1] : (spec.fold || spec.f || spec.col || spec.column));
    if(!Number.isInteger(f) || f < 1 || f > this.jx) throw new Error('Grid column is outside the valid range.');
    return f - 1;
  };
  GridPicker.prototype.rowFull = function(i){ return this.enabled[i].some(Boolean) && this.enabled[i].every((cell,j) => !cell || this.grid[i][j]); };
  GridPicker.prototype.colFull = function(j){ return this.enabled.some(row => row[j]) && this.enabled.every((row,i) => !row[j] || this.grid[i][j]); };
  GridPicker.prototype.toggleRowSmart = function(spec){ const i = this.rowIndex(spec); const val = !this.rowFull(i); for(let j=0;j<this.jx;j++) if(this.enabled[i][j]) this.grid[i][j] = val; };
  GridPicker.prototype.toggleColSmart = function(spec){ const j = this.colIndex(spec); const val = !this.colFull(j); for(let i=0;i<this.ix;i++) if(this.enabled[i][j]) this.grid[i][j] = val; };


  GridPicker.prototype.render = function(){
    const s = this.summary();
    const allFull = s.selectedCount === s.totalCount && s.totalCount > 0;
    const disabled = this.readOnly ? ' disabled' : '';
    const colHeaders = this.columnLabels.map((label,j) =>
      `<button type="button" class="nmGridPickerColHead nmGridPickerHeadBtn ${this.colFull(j) ? 'is-full' : ''}" data-col="${j}" title="Toggle available cells in ${esc(label)}"${disabled}>${esc(label)}</button>`
    ).join('');
    const corner = `<button type="button" class="nmGridPickerCorner nmGridPickerHeadBtn ${allFull ? 'is-full' : ''}" data-corner="1" title="Toggle all available cells"${disabled}>\u25a6</button>`;
    let rows = '';
    for(let i=0;i<this.ix;i++){
      let cells = '';
      for(let j=0;j<this.jx;j++){
        const available=this.enabled[i][j];
        const title=this.cellTitles[i] && this.cellTitles[i][j] ? this.cellTitles[i][j] : `${this.rowLabels[i]}, ${this.columnLabels[j]}`;
        cells += `<button type="button" class="nmGridPickerCell ${this.grid[i][j] ? 'is-selected' : ''}${available ? '' : ' is-unavailable'}" data-i="${i}" data-j="${j}" title="${esc(title)}" aria-label="${esc(title)}" aria-pressed="${this.grid[i][j]}"${available ? disabled : ' aria-disabled="true" tabindex="-1"'}>${available ? (this.grid[i][j] ? '\u25cf' : '\u25cb') : '\u2014'}</button>`;
      }
      rows += `<div class="nmGridPickerRow"><button type="button" class="nmGridPickerRowHead nmGridPickerHeadBtn ${this.rowFull(i) ? 'is-full' : ''}" data-row="${i}" title="Toggle available results for ${esc(this.rowLabels[i])}"${disabled}>${esc(this.rowLabels[i])}</button>${cells}</div>`;
    }
    this.root.innerHTML = `<div class="nmGridPickerToolbar"><button data-act="selectAll" type="button"${disabled}>Select all</button><button data-act="deselectAll" type="button"${disabled}>Deselect all</button><button data-act="toggleAll" type="button"${disabled}>Toggle all</button><span>${s.selectedCount}/${s.totalCount} selected</span></div><div class="nmGridPickerTable" style="--nm-grid-cols:${this.jx}"><div class="nmGridPickerHeader">${corner}${colHeaders}</div>${rows}</div>`;
    this.root.querySelectorAll('.nmGridPickerToolbar button').forEach(btn => btn.addEventListener('click', () => this.applyAction({action:btn.dataset.act})));
    this.root.querySelectorAll('.nmGridPickerCell:not(.is-unavailable)').forEach(btn => btn.addEventListener('click', () => this.applyAction({action:'togglePosition', position:[Number(btn.dataset.i)+1, Number(btn.dataset.j)+1]})));
    this.root.querySelectorAll('.nmGridPickerRowHead').forEach(btn => btn.addEventListener('click', () => this.applyAction({action:'toggleRow', perm:Number(btn.dataset.row)+1})));
    this.root.querySelectorAll('.nmGridPickerColHead').forEach(btn => btn.addEventListener('click', () => this.applyAction({action:'toggleCol', fold:Number(btn.dataset.col)+1})));
    const cornerEl = this.root.querySelector('.nmGridPickerCorner');
    if(cornerEl) cornerEl.addEventListener('click', () => this.applyAction({action:allFull ? 'deselectAll' : 'selectAll'}));
  };

  // Project the canonical trained masks published with the analysis cards.
  function commonGrid(analyses, ix, jx){
    const G = Array.from({length:ix}, () => Array(jx).fill(true));
    for(const a of analyses){
      if(a.gridAct === undefined) throw new Error(`Trained CV2 GridAct metadata is missing for analysis ${a.index}.`);
      const mask = normalizeGrid(ix,jx,a.gridAct);
      for(let i=0;i<ix;i++) for(let j=0;j<jx;j++) G[i][j] = G[i][j] && mask[i][j];
    }
    return G;
  }

  // Preserve user GridAct across refreshes and mode changes. Reconcile against
  // trained partition availability only when the selected analysis set changes.
  function reconciler(initialSelection){
    const key = ids => Array.from(ids).map(Number).sort((a,b)=>a-b).join(',');
    let previous = key(initialSelection);
    return (current, info, selected) => {
      const next = key(selected), changed = next !== previous;
      if(!info.visible) return current;
      previous = next;
      const raw = arr(current);
      const valid = raw.length === info.ix && raw.every(row => Array.isArray(row) && row.length === info.jx) ||
        (info.ix===1 || info.jx===1) && raw.length===info.ix*info.jx && raw.every(v => typeof v==='boolean');
      if(!valid) return normalizeGrid(info.ix,info.jx,info.GridAct == null ? Array.from({length:info.ix},()=>Array(info.jx).fill(true)) : info.GridAct);
      const grid = normalizeGrid(info.ix,info.jx,current);
      if(!changed || info.GridAct == null) return grid;
      const allowed = normalizeGrid(info.ix, info.jx, info.GridAct);
      return grid.map((row,i) => row.map((cell,j) => cell && allowed[i][j]));
    };
  }

  // Artifact-only modes constrain executable cells without replacing the saved user mask.
  function permitted(G, ix, jx, available){
    const selected = normalizeGrid(ix,jx,G);
    if(available == null) return selected;
    const mask = normalizeGrid(ix,jx,available);
    return selected.map((row,i) => row.map((v,j) => v && mask[i][j]));
  }

  function renderSummary(host, spec){
    const total = Number(spec.ix) * Number(spec.jx);
    const executable = spec.executableCount;
    const status = executable == null || executable === spec.selectedCount ? '' : ` · ${executable} executable`;
    const detail = spec.detail ? ` <span class="muted">${esc(spec.detail)}</span>` : '';
    host.innerHTML = `<div class="nmGridSummary"><div class="nmGridSummaryText"><strong>${spec.selectedCount}/${total}</strong> CV2 partitions selected${status} <span class="muted">(${spec.ix} perms × ${spec.jx} folds)</span>${detail}</div><button type="button" class="nmGridSummaryEdit nmActionButton" id="${esc(spec.buttonId)}">Edit CV2 partitions…</button></div>`;
    const button = host.querySelector('.nmGridSummaryEdit');
    button.disabled = Boolean(spec.disabled);
    button.addEventListener('click', spec.onEdit);
    return button;
  }

  global.NMRuntimeGridPicker = { permitted, renderSummary, create:(root,state,opts) => new GridPicker(root,state,opts), GridPicker, reconciler, commonGrid, normalizeGrid };
})(window);
