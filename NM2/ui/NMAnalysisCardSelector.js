/* NMAnalysisCardSelector.js
 * Shared runner-page analysis selector.
 *
 * This component intentionally reuses the Analysis Manager card classes instead
 * of creating a parallel selector. It accepts both the runner-specific analysis
 * array and the field-wise payload returned by NMAnalysisManagerTools.listAnalyses.
 */
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
   * asNumber  Convert the supplied value into the as number representation expected by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function asNumber(x, fallback){ const n = Number(x); return Number.isFinite(n) ? n : fallback; }
  /**
   * fieldArray  Provide the field array helper used by shared analysis-card selector used by runtime runner pages.
   * It supports shared analysis-card selector used by runtime runner pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function fieldArray(obj, key){ return obj && Object.prototype.hasOwnProperty.call(obj,key) ? arr(obj[key]) : []; }

  /**
   * normalizeAnalyses  Normalize analyses payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   * payload.map: browser-side field consumed from payload while translating UI state to MATLAB-service requests.
   */
  function normalizeAnalyses(payload){
    if(!payload) return [];
    if(Array.isArray(payload)) return payload.map(normalizeOne).filter(Boolean);
    if(typeof payload === 'object'){
      const idx = fieldArray(payload, 'indices');
      const hasFieldWise = idx.length || fieldArray(payload,'ids').length || fieldArray(payload,'descriptions').length || fieldArray(payload,'rootdirs').length;
      if(hasFieldWise){
        const ids = fieldArray(payload,'ids');
        const desc = fieldArray(payload,'descriptions');
        const roots = fieldArray(payload,'rootdirs');
        const status = fieldArray(payload,'status');
        const enabled = fieldArray(payload,'enabled');
        const rootExists = fieldArray(payload,'rootExists');
        const disabledReason = fieldArray(payload,'disabledReason');
        const requiresOverwrite = fieldArray(payload,'requiresOverwrite');
        const ix = fieldArray(payload,'ix');
        const jx = fieldArray(payload,'jx');
        const gridAct = fieldArray(payload,'gridAct');
        const recommendedOperationMode = fieldArray(payload,'recommendedOperationMode');
        const preprocAvailable = fieldArray(payload,'preprocAvailable');
        const cvDatamatAvailable = fieldArray(payload,'cvDatamatAvailable');
        const cvResultsAvailable = fieldArray(payload,'cvResultsAvailable');
        const artifactSummary = fieldArray(payload,'artifactSummary');
        const n = Math.max(idx.length, ids.length, desc.length, roots.length, status.length, enabled.length, ix.length, jx.length);
        const out = [];
        for(let k=0;k<n;k++){
          out.push(normalizeOne({
            index: idx[k] == null ? k+1 : idx[k],
            id: ids[k],
            description: desc[k],
            rootdir: roots[k],
            status: status[k],
            enabled: enabled[k],
            rootExists: rootExists[k],
            disabledReason: disabledReason[k],
            requiresOverwrite: requiresOverwrite[k],
            ix: ix[k],
            jx: jx[k],
            gridAct: gridAct[k],
            recommendedOperationMode: recommendedOperationMode[k],
            preprocAvailable: preprocAvailable[k],
            cvDatamatAvailable: cvDatamatAvailable[k],
            cvResultsAvailable: cvResultsAvailable[k],
            artifactSummary: artifactSummary[k]
          }));
        }
        return out.filter(Boolean);
      }
      return [normalizeOne(payload)].filter(Boolean);
    }
    return [];
  }

  /**
   * normalizeOne  Normalize one payloads into the browser-side model used by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function normalizeOne(a){
    if(!a || typeof a !== 'object') return null;
    const index = asNumber(a.index != null ? a.index : a.analysisIndex, NaN);
    if(!Number.isFinite(index) || index < 1) return null;
    const id = a.id != null ? a.id : (a.name != null ? a.name : `Analysis_${index}`);
    const desc0 = a.description != null ? a.description : (a.desc != null ? a.desc : '');
    const description = Array.isArray(desc0) ? desc0.map(x=>String(x == null ? '' : x)).join(' ') : String(desc0 == null ? '' : desc0);
    const status = asNumber(a.status, NaN);
    const ix = asNumber(a.ix, 0);
    const jx = asNumber(a.jx, 0);
    const enabled = (a.enabled === undefined || !!a.enabled) && a.rootExists !== false;
    return {
      index,
      id:String(id == null ? '' : id),
      description,
      rootdir:String(a.rootdir == null ? '' : a.rootdir),
      status,
      enabled,
      disabledReason:String(a.disabledReason || a.reason || ''),
      enabledReason:String(a.enabledReason || ''),
      requiresOverwrite:!!a.requiresOverwrite,
      ix,
      jx,
      gridAct:a.gridAct === undefined ? undefined : window.NMRuntimeGridPicker.normalizeGrid(ix,jx,a.gridAct),
      recommendedOperationMode:String(a.recommendedOperationMode || ''),
      preprocAvailable:!!a.preprocAvailable,
      cvDatamatAvailable:!!a.cvDatamatAvailable,
      cvResultsAvailable:!!a.cvResultsAvailable,
      artifactSummary:(a.artifactSummary && typeof a.artifactSummary === 'object') ? a.artifactSummary : null
    };
  }

  /**
   * statusText  Build the status text shown to users in the browser UI.
   * It supports shared analysis-card selector used by runtime runner pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function eligibleSelection(analyses, selected){
    const ids = new Set(arr(selected).map(Number));
    return analyses.filter(a => a.enabled && ids.has(a.index)).map(a => a.index);
  }

  function statusText(a){
    if(!Number.isFinite(a.status)) return 'unknown';
    return Number(a.status) >= 1 ? `status ${a.status} — trained` : `status ${a.status} — configured`;
  }
  /**
   * gridText  Build the grid text shown to users in the browser UI.
   * It supports shared analysis-card selector used by runtime runner pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function gridText(a){
    return a.ix > 0 && a.jx > 0 ? `${a.ix} × ${a.jx} CV2 grid` : 'CV2 grid unavailable';
  }

  /**
   * create  Create the create component or browser-side state object.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * options.expandMode: browser-side field consumed from options while translating UI state to MATLAB-service requests.
   * options.multiSelect: browser-side field consumed from options while translating UI state to MATLAB-service requests.
   * options.onChange: browser-side field consumed from options while translating UI state to MATLAB-service requests.
   * options.selected: browser-side field consumed from options while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function create(root, payload, options){
    const api = {
      root,
      analyses: normalizeAnalyses(payload),
      selected: new Set(arr(options && options.selected).map(Number).filter(Number.isFinite)),
      expanded: new Set(),
      _clickTimer:null,
      options: Object.assign({multiSelect:true, expandMode:'selected', emptyText:'No analyses are configured.', onChange:null, onInspect:null, inspectLabel:'Inspect in Analysis Manager'}, options || {}),
      _signature:null,
      update(nextPayload, nextOptions){
        this.analyses = normalizeAnalyses(nextPayload);
        if(nextOptions){
          if(Object.prototype.hasOwnProperty.call(nextOptions,'selected')) this.selected = new Set(arr(nextOptions.selected).map(Number).filter(Number.isFinite));
          this.options = Object.assign(this.options, nextOptions);
        }
        this.render();
      },
      getSelected(){ return Array.from(this.selected.values()).sort((a,b)=>a-b); },
      setSelected(indices, notify){
        this.selected = new Set(arr(indices).map(Number).filter(Number.isFinite));
        this.render();
        if(notify !== false && typeof this.options.onChange === 'function') this.options.onChange(this.getSelected());
      },
      cardFor(index){ return this.root ? this.root.querySelector(`.nmAnalysisSelectorCard[data-analysis-index="${index}"]`) : null; },
      toggle(index){
        const a = this.analyses.find(x=>x.index === index);
        if(!a || !a.enabled) return;
        const wasSelected = this.selected.has(index);
        if(this.options.multiSelect){
          if(wasSelected) this.selected.delete(index); else this.selected.add(index);
        } else {
          if(wasSelected) this.selected.delete(index);
          else {
            this.selected.forEach((other)=>{ if(other !== index){ this.expanded.delete(other); const c = this.cardFor(other); if(c) this.collapseCard(c); } });
            this.selected = new Set([index]);
          }
        }
        const nowSelected = this.selected.has(index);
        if(this.options.expandMode === 'selected'){
          if(nowSelected) this.expanded.add(index); else this.expanded.delete(index);
        } else if(!nowSelected) {
          this.expanded.delete(index);
        }
        const card = this.cardFor(index);
        if(card){
          card.setAttribute('aria-pressed', nowSelected ? 'true' : 'false');
          card.classList.toggle('selected', nowSelected);
          if(this.options.expandMode === 'selected'){
            if(nowSelected) this.expandCard(card); else this.collapseCard(card);
          } else if(!nowSelected) {
            this.collapseCard(card);
          }
        } else {
          this.render();
        }
        if(typeof this.options.onChange === 'function') this.options.onChange(this.getSelected());
      },
      selectWithoutToggle(index){
        const a = this.analyses.find(x=>x.index === index);
        if(!a || !a.enabled || this.selected.has(index)) return false;
        if(this.options.multiSelect) this.selected.add(index);
        else {
          this.selected.forEach((other)=>{ if(other !== index){ this.expanded.delete(other); const c = this.cardFor(other); if(c) this.collapseCard(c); } });
          this.selected = new Set([index]);
        }
        const card = this.cardFor(index);
        if(card){
          card.setAttribute('aria-pressed', 'true');
          card.classList.add('selected');
        } else this.render();
        if(typeof this.options.onChange === 'function') this.options.onChange(this.getSelected());
        return true;
      },
      toggleExpanded(index, noSelect){
        const a = this.analyses.find(x=>x.index === index);
        if(!a || !a.enabled) return;
        if(!noSelect && !this.selected.has(index)) this.selectWithoutToggle(index);
        const open = this.expanded.has(index);
        if(open) this.expanded.delete(index); else this.expanded.add(index);
        const card = this.cardFor(index);
        if(card){ if(open) this.collapseCard(card, true); else this.expandCard(card); }
        else this.render();
      },
      // --- measured-height expand/collapse (mirrors Analysis Manager cards) ---
      _clearAnim(body){ if(body && body._animEnd){ body.removeEventListener('transitionend', body._animEnd); body._animEnd = null; } },
      expandCard(card){
        if(!card) return;
        const body = card.querySelector('.amAnalysisCardBody');
        if(!body){ card.classList.add('expanded'); return; }
        this._clearAnim(body);
        card.classList.add('amAnimating');
        card.classList.add('expanded');
        body.style.maxHeight = '0px';
        void body.offsetHeight;
        window.requestAnimationFrame(()=>{
          body.style.maxHeight = body.scrollHeight + 'px';
          /**
           * onEnd  Provide the on end helper used by shared analysis-card selector used by runtime runner pages.
           * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
           * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
           */
          const onEnd = (ev)=>{ if(ev.target !== body || ev.propertyName !== 'max-height') return; body.style.maxHeight = 'none'; card.classList.remove('amAnimating'); this._clearAnim(body); };
          body._animEnd = onEnd;
          body.addEventListener('transitionend', onEnd);
        });
      },
      collapseCard(card, keepSelected){
        if(!card) return;
        const body = card.querySelector('.amAnalysisCardBody');
        if(!body){ if(!keepSelected) card.classList.remove('selected'); card.classList.remove('expanded'); return; }
        this._clearAnim(body);
        card.classList.add('amAnimating');
        // A card that was open at initial render carries inline display/opacity/
        // padding from the render template. Drop those so only JS-managed
        // max-height drives the animation and CSS reclaims the collapsed state.
        body.style.removeProperty('display');
        body.style.removeProperty('opacity');
        body.style.removeProperty('padding');
        body.style.maxHeight = body.scrollHeight + 'px';
        void body.offsetHeight;
        if(!keepSelected) card.classList.remove('selected');
        card.classList.remove('expanded');
        window.requestAnimationFrame(()=>{
          body.style.maxHeight = '0px';
          /**
           * onEnd  Provide the on end helper used by shared analysis-card selector used by runtime runner pages.
           * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
           * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
           */
          const onEnd = (ev)=>{
            if(ev.target !== body || ev.propertyName !== 'max-height') return;
            card.classList.remove('amAnimating');
            // Fully reset to the CSS-governed collapsed state (display:none etc).
            body.removeAttribute('style');
            this._clearAnim(body);
          };
          body._animEnd = onEnd;
          body.addEventListener('transitionend', onEnd);
        });
      },
      render(){
        this.selected = new Set(eligibleSelection(this.analyses, Array.from(this.selected)));
        if(!this.root) return;
        if(!this.analyses.length){
          this.root.innerHTML = `<div class="amEmptyState">${esc(this.options.emptyText)}</div>`;
          this._signature = null;
          return;
        }
        /**
         * showBodyFor  Provide the show body for helper used by shared analysis-card selector used by runtime runner pages.
         * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
         * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
         */
        const showBodyFor = (a)=> this.options.expandMode === 'selected' ? this.selected.has(a.index) : this.expanded.has(a.index);
        const inspectable = typeof this.options.onInspect === 'function';
        this.root.innerHTML = this.analyses.map((a)=>{
          const selected = this.selected.has(a.index);
          const bodyOpen = showBodyFor(a);
          const disabled = !a.enabled;
          const reason = disabled ? (a.disabledReason || 'Not executable in the current NM state.') : (a.enabledReason || (a.requiresOverwrite ? 'Existing artifacts detected; overwrite may be required.' : 'Executable'));
          const desc = a.description ? `<div><strong>Description:</strong> ${esc(a.description)}</div>` : '';
          const rootLine = a.rootdir ? `<div><strong>Root:</strong> ${esc(a.rootdir)}</div>` : '';
          const inspectBtn = inspectable
            ? `<div class="nmSelectorActions"><button type="button" class="nmSelectorInspectButton" data-inspect-index="${a.index}">${esc(this.options.inspectLabel)}</button></div>`
            : '';
          const openStyle = bodyOpen ? ' style="display:block;max-height:none;opacity:1;padding:12px"' : '';
          const chevron = this.options.expandMode === 'doubleClick'
            ? `<button type="button" class="nmSelectorChevron" data-expand-index="${a.index}" aria-label="${bodyOpen ? 'Collapse details' : 'Expand details'}" aria-expanded="${bodyOpen ? 'true' : 'false'}"><svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M4 6l4 4 4-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg></button>`
            : '';
          return `<article class="amAnalysisCard nmAnalysisSelectorCard ${selected ? 'selected' : ''} ${bodyOpen ? 'expanded' : ''} ${this.options.expandMode === 'doubleClick' ? 'nmSelectorDoubleClickMode' : ''} ${disabled ? 'disabled' : ''}" data-analysis-index="${a.index}" tabindex="0" role="button" aria-pressed="${selected ? 'true' : 'false'}">` +
            `<div class="amAnalysisCardHeader"><div><b>Analysis ${esc(a.index)}: ${esc(a.id || '')}</b><span class="nmSelectorHeaderRight"><span class="nmSelectorGridText">${esc(gridText(a))}</span></span>${chevron}</div>${disabled ? `<p class="amPathWarning" style="margin-bottom:0">${esc(reason)}</p>` : ''}</div>` +
            `<div class="amAnalysisCardBody"${openStyle}><div class="amAnalysisCardBodyInner"><div class="amCardSummary">` +
            `<div><strong>Status:</strong> ${esc(statusText(a))}</div>${desc}${rootLine}<div>${esc(reason)}</div>` +
            `</div>${inspectBtn}</div></div></article>`;
        }).join('');
        this.root.querySelectorAll('.nmAnalysisSelectorCard').forEach((card)=>{
          const idx = Number(card.dataset.analysisIndex);
          card.addEventListener('click', (ev)=>{
            // Inspect button must not toggle selection.
            const insp = ev.target && ev.target.closest ? ev.target.closest('.nmSelectorInspectButton') : null;
            if(insp){ ev.preventDefault(); ev.stopPropagation(); if(typeof this.options.onInspect === 'function') this.options.onInspect(Number(insp.dataset.inspectIndex)); return; }
            // Chevron disclosure toggles expansion only, never selection.
            const chev = ev.target && ev.target.closest ? ev.target.closest('.nmSelectorChevron') : null;
            if(chev){
              ev.preventDefault(); ev.stopPropagation();
              if(this._clickTimer){ window.clearTimeout(this._clickTimer); this._clickTimer = null; }
              this.toggleExpanded(idx, true);
              const open = this.expanded.has(idx);
              chev.setAttribute('aria-expanded', open ? 'true' : 'false');
              chev.setAttribute('aria-label', open ? 'Collapse details' : 'Expand details');
              return;
            }
            ev.preventDefault();
            if(this.options.expandMode === 'doubleClick'){
              if(this._clickTimer) window.clearTimeout(this._clickTimer);
              this._clickTimer = window.setTimeout(()=>{ this._clickTimer = null; this.toggle(idx); }, 220);
            } else this.toggle(idx);
          });
          card.addEventListener('keydown', (ev)=>{
            if(ev.key === 'Enter' || ev.key === ' '){ if(ev.target && ev.target.closest && ev.target.closest('.nmSelectorInspectButton')) return; ev.preventDefault(); this.toggle(idx); }
          });
          if(this.options.expandMode === 'doubleClick'){
            card.addEventListener('dblclick', (ev)=>{
              ev.preventDefault();
              if(this._clickTimer){ window.clearTimeout(this._clickTimer); this._clickTimer = null; }
              this.toggleExpanded(idx);
            });
          }
        });
      }
    };
    api.render();
    return api;
  }

  window.NMAnalysisCardSelector = {create, normalizeAnalyses, eligibleSelection};
})();
