(function(global){
  'use strict';

  /**
   * NMResultsViewerAnalysisSetSelector
   * -----------------------------------------------------------------------
   * Purpose: Render the shared, controlled analysis-set selector and queried
   *          Scientific State capability inventory used by analysis-set-aware
   *          Results Viewer consumers.
   * Syntax: NMResultsViewerAnalysisSetSelector.render(options).
   * Inputs: options.host; canonical completed-analysis rows; selectedIndices;
   *         optional Scientific State analysis_set inventory; busy/stale flags;
   *         onSelectionChange(indices) and onQuery(indices) callbacks.
   * Outputs: DOM for multi-selection, Select all/Deselect all, Query results,
   *          capability overview, CV-equivalence badges and set summary.
   * Authority and flow: Analysis identity/completion is supplied by the backend
   *         catalogue. Scientific capabilities are displayed only from
   *         Scientific State.inventory, whose per-analysis capabilities come
   *         from the same resultTypesForAnalysis authority used by Result type.
   *         CV groups are displayed only from Scientific State.cvGroup values,
   *         ultimately owned by nk_GetAnalysisStatus.
   * Scientific/state contract: Checkbox state is transient request state and is
   *         distinct from the last queried analysis_set Scientific State. The
   *         selector never infers capability or CV compatibility from NM data,
   *         labels, DOM state or result-container fields.
   * Invariants: Only supplied completed analyses are selectable; Query results
   *         is the sole state-materialization trigger; stale inventories remain
   *         visibly stale until explicitly re-queried; CV colour is always paired
   *         with a textual group identifier.
   * Materialization and performance: O(A) DOM work over compact analysis/state
   *         metadata. No files/XML/atlas/annotation/mesh resources, voxel/vertex
   *         scans or feature-scale arrays; safe on explicit selector interaction.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays in the browser module.
 * Interactive/retained use: Designed for explicit user interaction; it does not trigger retained scientific rematerialization.
 * Failure semantics: Missing host is a no-op. Missing/unqueried inventory shows
   *         an explicit prompt rather than fabricating capabilities.
   * Side effects: Replaces host DOM and installs local event listeners only.
   * Consumers and dependencies: Cross-analysis Performance Tabulator,
   *         Multi-analysis Results Builder launcher and future analysis_set-aware
   *         consumers; backend Scientific State analysis_set inventory.
   * -----------------------------------------------------------------------
   */

  const arr=v=>Array.isArray(v)?v:[];
  const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
  const analysisIndex=row=>Number(row&&((row.index!=null)?row.index:row.AnalysisIndex)||0);
  const analysisLabel=row=>String(row&&(row.title||row.Label||row.label||row.description||row.id)||`Analysis ${analysisIndex(row)}`);
  const analysisMode=row=>String(row&&(row.mode||row.task||row.ResultType)||'');
  const selectedSet=values=>new Set(arr(values).map(Number).filter(Number.isFinite));

  /**
   * Purpose: Test exact canonical analysis-set identity without relying on array position.
   * Syntax: stateMatchesSelection(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes only caller-supplied completed-analysis metadata and/or queried Scientific State analysis_set inventory; it does not inspect NM or derive scientific capability/CV semantics.
   * Scientific/state contract: Transient selection is request state; queried Scientific State remains the scientific availability authority until Query results is invoked again.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact analysis/inventory metadata and DOM only; no scientific numerical arrays are materialized. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Shared Analysis Set selector module and analysis_set-aware Results Viewer consumers.
   */
  function stateMatchesSelection(state,indices){
    const scope=state&&state.scope||{},have=arr(scope.analysisIndices).map(Number),want=arr(indices).map(Number);
    return String(scope.type||'')==='analysis_set'&&have.length===want.length&&have.every((v,i)=>v===want[i]);
  }

  /**
   * Purpose: Render one capability cell from authoritative Scientific State inventory.
   * Syntax: capabilityCell(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes only caller-supplied completed-analysis metadata and/or queried Scientific State analysis_set inventory; it does not inspect NM or derive scientific capability/CV semantics.
   * Scientific/state contract: Transient selection is request state; queried Scientific State remains the scientific availability authority until Query results is invoked again.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact analysis/inventory metadata and DOM only; no scientific numerical arrays are materialized. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Shared Analysis Set selector module and analysis_set-aware Results Viewer consumers.
   */
  function capabilityCell(value,label){return `<td class="rvAnalysisSetCapability ${value?'isAvailable':'isUnavailable'}" title="${esc(label)}: ${value?'available':'unavailable'}"><span aria-hidden="true">${value?'✓':'—'}</span><span class="rvSrOnly">${value?'Available':'Unavailable'}</span></td>`;}

  /**
   * Purpose: Render queried capability rows, including textual+colour CV group identity.
   * Syntax: capabilityTable(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes only caller-supplied completed-analysis metadata and/or queried Scientific State analysis_set inventory; it does not inspect NM or derive scientific capability/CV semantics.
   * Scientific/state contract: Transient selection is request state; queried Scientific State remains the scientific availability authority until Query results is invoked again.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact analysis/inventory metadata and DOM only; no scientific numerical arrays are materialized. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Shared Analysis Set selector module and analysis_set-aware Results Viewer consumers.
   */
  function capabilityTable(state,sharedOocvIndices){
    const rows=arr(state&&state.inventory);
    if(!rows.length)return '<div class="rvPanelNotice">Query the selected analyses to inspect available result spaces and CV structure.</div>';
    const body=rows.map(row=>{const caps=row.capabilities,g=Number(row.cvGroup),idx=Number(row.analysisIndex),criterion=row.optimizationCriterion;return `<tr><th scope="row">[${idx}] ${esc(row.label||row.analysisId||`Analysis ${idx}`)}</th>${capabilityCell(!!caps.modelPerformance,'Model performance')}${capabilityCell(sharedOocvIndices.has(idx),'OOCV result shared with another queried analysis')}${capabilityCell(!!caps.modelOptimization,'Model optimization')}<td title="${esc(criterion.key||'No optimization criterion')}">${esc(criterion.shortLabel||criterion.label||'—')}</td>${capabilityCell(!!caps.featureInspection,'Feature inspection')}${capabilityCell(!!caps.interpretation,'Interpretation')}<td><span class="rvAnalysisSetCvBadge rvAnalysisSetCv${((g-1)%8)+1}" title="Identical CV structure group ${g}">CV ${esc(String.fromCharCode(64+Math.min(g,26)))}${g>26?` (${g})`:''}</span></td></tr>`;}).join('');
    const summary=state.inventorySummary||{},shared=summary.sharedCapabilities||{},available=summary.availableCounts||{},n=Number(summary.analysisCount)||rows.length;
    const labels={modelPerformance:'Model performance',modelOptimization:'Model optimization',featureInspection:'Feature inspection',interpretation:'Interpretation'};
    const sharedLabels=Object.keys(labels).filter(k=>shared[k]===true).map(k=>labels[k]);
    const partialLabels=Object.keys(labels).filter(k=>!shared[k]&&Number(available[k]||0)>0).map(k=>`${labels[k]} (${Number(available[k])}/${n})`);
    const footer=`<div class="rvAnalysisSetSummary"><span><strong>Shared:</strong> ${esc(sharedLabels.join(' · ')||'none')}</span><span><strong>Available in some:</strong> ${esc(partialLabels.join(' · ')||'none')}</span><span><strong>CV structures:</strong> ${Number(summary.cvGroupCount||0)}</span></div>`;
    return `<div class="rvAnalysisSetCapabilityScroll"><table class="rvAnalysisSetCapabilityTable"><thead><tr><th>Analysis</th><th>Model performance</th><th>Shared OOCV</th><th>Optimization</th><th>Optimization criterion</th><th>Feature inspection</th><th>Interpretation</th><th>CV</th></tr></thead><tbody>${body}</tbody></table></div>${footer}`;
  }

  /**
   * Purpose: Render and bind the reusable controlled selector.
   * Syntax: render(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes only caller-supplied completed-analysis metadata and/or queried Scientific State analysis_set inventory; it does not inspect NM or derive scientific capability/CV semantics.
   * Scientific/state contract: Transient selection is request state; queried Scientific State remains the scientific availability authority until Query results is invoked again.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact analysis/inventory metadata and DOM only; no scientific numerical arrays are materialized. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Shared Analysis Set selector module and analysis_set-aware Results Viewer consumers.
   */
  function render(options){
    const opts=options||{},host=opts.host;if(!host)return;
    const analyses=arr(opts.analyses).filter(row=>row&&row.completed!==false),selected=selectedSet(opts.selectedIndices),indices=Array.from(selected).sort((a,b)=>a-b),state=opts.scientificState||{},current=stateMatchesSelection(state,indices)&&opts.stale!==true;
    const rows=analyses.map(row=>{const idx=analysisIndex(row),checked=selected.has(idx);return `<label class="rvAnalysisSetRow"><input type="checkbox" data-analysis-set-index="${idx}"${checked?' checked':''}><span class="rvAnalysisSetId">[${idx}]</span><span class="rvAnalysisSetLabel">${esc(analysisLabel(row))}</span><span class="rvAnalysisSetMode">${esc(analysisMode(row))}</span></label>`;}).join('');
    const status=opts.busy?'Querying Scientific State…':current?`Queried ${indices.length} analysis${indices.length===1?'':'es'}.`:opts.stale&&state&&state.scope?'Selection changed — Query results again.':'Select analyses and query their available results.';
    host.innerHTML=`<div class="rvAnalysisSetPanel"><section class="rvAnalysisSetSelector"><div class="rvAnalysisSetHead"><strong>Analysis set</strong><div class="rvAnalysisSetTools"><button type="button" data-analysis-set-bulk="all">Select all</button><button type="button" data-analysis-set-bulk="none">Deselect all</button></div></div><div class="rvAnalysisSetList">${rows||'<div class="rvPanelNotice">No completed analyses are available.</div>'}</div><div class="rvAnalysisSetQuery"><span class="${opts.stale?'isStale':''}">${esc(status)}</span><button type="button" class="primary" data-analysis-set-query${opts.busy||!indices.length?' disabled':''}>${opts.busy?'Querying…':'Query results'}</button></div></section><section class="rvAnalysisSetOverview"><div class="rvAnalysisSetHead"><strong>Capability overview</strong><span>${current?'Scientific State inventory':'Not queried'}</span></div>${current?capabilityTable(state,opts.sharedOocvIndices):'<div class="rvPanelNotice">Query the selected analyses to inspect Model performance, optimization, feature inspection, interpretation and CV-equivalence groups.</div>'}</section></div>`;
    host.querySelectorAll('[data-analysis-set-index]').forEach(node=>node.addEventListener('change',()=>{const next=selectedSet(indices),idx=Number(node.dataset.analysisSetIndex);if(node.checked)next.add(idx);else next.delete(idx);if(typeof opts.onSelectionChange==='function')opts.onSelectionChange(Array.from(next).sort((a,b)=>a-b));}));
    host.querySelectorAll('[data-analysis-set-bulk]').forEach(node=>node.addEventListener('click',()=>{const next=String(node.dataset.analysisSetBulk)==='all'?analyses.map(analysisIndex).filter(Boolean):[];if(typeof opts.onSelectionChange==='function')opts.onSelectionChange(next);}));
    const query=host.querySelector('[data-analysis-set-query]');if(query)query.addEventListener('click',()=>{if(typeof opts.onQuery==='function')opts.onQuery(indices);});
  }

  global.NMResultsViewerAnalysisSetSelector={render,stateMatchesSelection};
})(window);
