/**
 * NMResultsViewerCrossAnalysis
 * -------------------------------------------------------------------------
 * Purpose: Browser controller for the Cross-analysis Results Viewer workspace,
 * including Performance Tabulator, Statistical comparison, descriptive Visual
 * comparison and the shared multi-analysis Results Builder launcher.
 * Syntax: window.NMResultsViewerCrossAnalysis.render(options).
 * Inputs: Backend comparison workspace catalogue and shared UI/service callbacks.
 * Outputs: Analysis-set selection/query state plus backend-owned Performance,
 * Statistical and Visual comparison presentation/export/report request state.
 * Authority and flow: The reusable Analysis Set selector requests
 * NMResultsViewerScientificState analysis_set inventory. Performance/statistical/
 * visual scientific values are materialized only by NMResultsViewerCrossAnalysisTools. Report Builder and
 * direct export consume explicit caller state; this module never inspects NM.
 * Scientific/state contract: The last queried analysis_set Scientific State is
 * distinct from transient checkbox selection. Capabilities/CV groups are read only
 * from that State. Generated performance values/annotations remain backend-owned.
 * Invariants: Generate/report actions require a current queried inventory; common
 * source eligibility comes from backend source catalogues; Statistical and Visual
 * selectors remain distinct; Visual presentation never adds a CV-equivalence gate
 * or browser-side performance calculation; direct CSV/XLSX export serializes the
 * already-materialized table through the shared table-output API.
 * Materialization and performance: O(A+R) browser metadata/table work for analyses
 * A and returned metric rows R. Query and Generate are explicit MATLAB round trips;
 * no files/XML/atlas/mesh resources, voxel/vertex scans or feature-scale arrays are
 * created in JavaScript.
 * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays in the browser module.
 * Interactive/retained use: Designed for explicit user interaction; it does not trigger retained scientific rematerialization.
 * Failure semantics: Stale/unqueried selections block scientific consumers with an
 * actionable shared message. Backend failures remain explicit; no browser fallback
 * calculation is attempted.
 * Side effects: Mutates Cross-analysis DOM/module-local UI state only.
 * Consumers and dependencies: NMResultsViewerUI_main.js,
 * NMResultsViewerAnalysisSetSelector, NMResultsViewerCrossAnalysisTools, shared
 * Report Builder, generic Results Viewer table export and information controls.
 * -------------------------------------------------------------------------
 */
(function(global){
  'use strict';

  const STATE={signature:'',selected:new Set(),aliases:new Map(),aliasEditorOpen:true,orderMode:'original',exportIconMarkup:'Export',source:'cv',metricIds:new Set(),result:null,busy:false,statisticalResult:null,statisticalBusy:false,statistical:{targetIndex:null,modelSource:'',classifierIndex:null,referenceAnalysisIndex:0,plotMode:'performance_violin',colormap:'legacy',showHeatValues:true},visualResult:null,visualBusy:false,visual:{targetIndex:null,modelSource:'',classifierIndex:null,multiClassModeIndex:null,metricIds:new Set(),plotMode:'bar',separateAxis:new Set(),colors:new Map()},inventoryState:null,inventoryBusy:false,activeTab:'performance',batchCells:new Set(),batchModalOpen:false,batchBusy:false,batchMessage:''};
  const VISUAL_DEFAULT_COLORS=['#2563eb','#c2410c','#059669','#7c3aed','#ca8a04','#0891b2','#be123c','#4f46e5'];
  const arr=v=>Array.isArray(v)?v:(v==null?[]:[v]);
  const esc=v=>String(v==null?'':v).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const plotTools=()=>{const tools=global.NMResultsPlotD3,required=['ticks','formatNumber','measureTextWidth','fitLabel','cellTextColor','cartesianAxes','violinPolygon','violinStatisticLines'];const missing=required.filter(name=>!tools||typeof tools[name]!=='function');if(missing.length)throw new Error(`Shared Results Viewer plotting authority is unavailable: ${missing.join(', ')}.`);return tools;};
  const analysisIndex=a=>Number(a&&a.index||0);
  const completedAnalyses=payload=>arr(payload&&payload.analyses).filter(a=>a&&a.completed!==false&&analysisIndex(a)>0);
  const signature=payload=>completedAnalyses(payload).map(a=>`${analysisIndex(a)}:${String(a.title||a.id||'')}`).join('|');
  const selectedIndices=()=>Array.from(STATE.selected).sort((a,b)=>a-b);
  const selectedMetricIds=()=>Array.from(STATE.metricIds);
  const selectionMatchesInventory=()=>!!(global.NMResultsViewerAnalysisSetSelector&&global.NMResultsViewerAnalysisSetSelector.stateMatchesSelection(STATE.inventoryState,selectedIndices()));
  const optionalPositiveInteger=(value,label)=>{if(value==null||value==='')return null;const n=Number(value);if(!Number.isInteger(n)||n<1)throw new Error(`${label} must be one finite positive integer.`);return n;};

  /**
   * Purpose: Convert one display-oriented header/row matrix into the keyed generic Results Viewer table-artifact schema.
   * Syntax: tableArtifactProjection(header,rows).
   * Inputs: header is an ordered array of display labels; rows is an ordered array of positional row arrays already materialized by Cross-analysis.
   * Outputs: columns with stable MATLAB-safe key/label pairs plus keyed row objects carrying the unchanged cell values.
   * Authority and flow: This is the Cross-analysis producer-side adaptation into the existing NMResultsViewerOutput table contract; it does not normalize or interpret scientific values.
   * Scientific/state contract: Column order, labels and cell values are preserved exactly from the already-materialized Performance/Visual comparison table.
   * Invariants: Every column has one non-empty stable key; every output row is an object keyed by those columns; no export writer or Report Builder logic is duplicated here.
   * Materialization and performance: O(rows*columns) compact table projection at explicit export time only; no scientific rematerialization or feature-scale allocation occurs.
   * Interactive/retained use: Invoked only for explicit direct table export from resident Cross-analysis results; it does not trigger MATLAB or alter retained scientific state.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Non-array inputs normalize to empty arrays; missing positional cells remain empty rather than shifting later columns.
   * Side effects: None.
   * Consumers and dependencies: performanceTableArtifact and visualTableArtifact before NMResultsViewerOutput.table.
   */
  function tableArtifactProjection(header,rows){
    const labels=arr(header),columns=labels.map((label,i)=>({key:`column_${i+1}`,label:String(label==null?'':label)}));
    const keyedRows=arr(rows).map(row=>{const values=arr(row),out={};columns.forEach((column,i)=>{out[column.key]=i<values.length&&values[i]!==undefined?values[i]:'';});return out;});
    return {columns,rows:keyedRows};
  }

  /**
   * Purpose: Intersect backend-enabled result sources across the transient selected analysis set.
   * Syntax: commonSourceOptions(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function commonSourceOptions(payload){
    const indices=selectedIndices(),catalogue=arr(payload&&payload.analysisSourceOptions);if(!indices.length)return[];
    const lists=indices.map(idx=>{const row=catalogue.find(x=>Number(x&&x.analysisIndex)===idx);return arr(row&&row.options).filter(x=>x&&x.enabled!==false);});
    if(!lists.length)return[];
    return lists[0].filter(source=>lists.slice(1).every(list=>list.some(candidate=>String(candidate.id||'')===String(source.id||''))));
  }

  // OOCV presentation matrix: all availability and descriptions are taken from
  // sourceOptionsByAnalysis -> NMResultsViewerTools.sourcesForAnalysis.
  function resultSpaceMatrix(payload){
    const indices=selectedIndices(),catalogue=arr(payload.analysisSourceOptions),byAnalysis=new Map(),sources=new Map();
    indices.forEach(idx=>{
      const row=catalogue.find(entry=>Number(entry.analysisIndex)===idx);
      const available=new Map();
      arr(row.options).forEach(option=>{
        if(option.enabled!==true)return;
        const id=String(option.id);
        if(id!=='cv'&&!/^oocv:[1-9]\d*$/.test(id))return;
        available.set(id,option);
        if(!sources.has(id))sources.set(id,{id,label:String(option.label)});
      });
      byAnalysis.set(idx,available);
    });
    const columns=Array.from(sources.values()).sort((a,b)=>a.id==='cv'?-1:b.id==='cv'?1:Number(a.id.split(':')[1])-Number(b.id.split(':')[1]));
    const participants=new Map(columns.map(source=>[source.id,indices.filter(idx=>byAnalysis.get(idx).has(source.id))]));
    const shared=new Set(columns.filter(source=>source.id!=='cv'&&participants.get(source.id).length>=2).flatMap(source=>participants.get(source.id)));
    return {indices,columns,byAnalysis,participants,shared};
  }

  function batchCellKey(idx,id){return `${idx}|${id}`;}

  function batchModalHtml(payload,matrix){
    if(!STATE.batchModalOpen)return '';
    const n=STATE.batchCells.size,busy=STATE.batchBusy;
    return `<div class="rvModalOverlay rvCrossBatchOverlay"><section class="rvModalCard rvCrossBatchModal" role="dialog" aria-modal="true" aria-labelledby="rvCrossBatchTitle"><div class="rvCrossBatchHead"><div><h3 id="rvCrossBatchTitle">Performance result spaces</h3><p>Select OOCV columns, analysis rows, individual available cells, or all/none. Hover for the complete analysis and container description.</p></div><button type="button" data-batch-close aria-label="Close"${busy?' disabled':''}>×</button></div><div class="rvCrossBatchActions"><button type="button" data-batch-shared${busy?' disabled':''}>Shared OOCV</button><span data-batch-count>${n} selected result${n===1?'':'s'}</span></div><div class="rvCrossBatchScroll"><div id="rvCrossBatchGrid"></div></div><p class="rvCrossBatchHint">Unavailable cells cannot be selected. Each result source is exported with exactly its selected analyses and the Performance table metrics.</p><div class="rvCrossBatchFooter"><span role="status" data-batch-status>${esc(STATE.batchMessage||(!STATE.metricIds.size?'Generate a performance table and select metrics before batch export.':''))}</span><button type="button" data-batch-close${busy?' disabled':''}>Cancel</button><button type="button" class="primary" data-batch-export${busy||!n||!STATE.metricIds.size?' disabled':''}>${busy?'Preparing…':'Export selected results'}</button></div></section></div>`;
  }

  /**
   * Purpose: Keep source selection within the common backend source catalogue.
   * Syntax: normalizeSelectedSource(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function normalizeSelectedSource(payload){const sources=commonSourceOptions(payload),hit=sources.find(s=>String(s.id||'')===STATE.source);if(!hit)STATE.source=String(sources[0]&&sources[0].id||'');return sources;}

  /**
   * Purpose: Initialize transient analysis-set state only when the backend catalogue identity changes.
   * Syntax: resetFromPayload(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function resetFromPayload(payload){
    const sig=signature(payload);if(sig===STATE.signature)return;
    STATE.signature=sig;STATE.selected=new Set();STATE.aliases=new Map();STATE.aliasEditorOpen=true;STATE.orderMode='original';STATE.metricIds=new Set();STATE.result=null;STATE.statisticalResult=null;STATE.statistical={targetIndex:null,modelSource:'',classifierIndex:null,referenceAnalysisIndex:0,plotMode:'performance_violin',colormap:'legacy',showHeatValues:true};STATE.visualResult=null;STATE.visual={targetIndex:null,modelSource:'',classifierIndex:null,multiClassModeIndex:null,metricIds:new Set(),plotMode:'bar',separateAxis:new Set(),colors:new Map()};STATE.inventoryState=null;STATE.activeTab='performance';STATE.batchCells=new Set();STATE.batchModalOpen=false;STATE.batchMessage='';
    completedAnalyses(payload).forEach(a=>{const idx=analysisIndex(a);STATE.selected.add(idx);STATE.aliases.set(idx,String(a.title||a.id||`Analysis ${idx}`));});
    STATE.source=String(payload&&payload.selectedSource||'cv');normalizeSelectedSource(payload);
  }

  /**
   * Purpose: Serialize presentation aliases without replacing numeric scientific analysis identity.
   * Syntax: aliasRows(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function aliasRows(){return selectedIndices().map(idx=>({analysisIndex:idx,alias:String(STATE.aliases.get(idx)||'')}));}

  /**
   * Purpose: Serialize the fixed caller-owned analysis set for the one shared multi-analysis Report Builder.
   * Syntax: invocationContext(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function invocationContext(){return {Scope:'multi_analysis',AnalysisIndices:selectedIndices()};}

  /**
   * Purpose: Serialize Cross-analysis selectors explicitly for backend/report consumers.
   * Syntax: requestOverrides(consumer).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices. Consumer='statistical' serializes only statistical coordinates, consumer='visual' only visual coordinates, and the default combined form is reserved for shared Report Builder state.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State. Unset optional target/classifier coordinates are omitted, never coerced from null to numeric zero; one consumer never validates another consumer's inactive selector state.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function requestOverrides(consumer){
    consumer=String(consumer||'all');
    const includeStatistical=consumer==='all'||consumer==='statistical',includeVisual=consumer==='all'||consumer==='visual';
    const indices=selectedIndices(),out={resultType:'comparison',analysisIndices:indices,crossAnalysisSource:STATE.source,analysisAliases:aliasRows(),subgroupExpression:''};
    if(consumer==='all')out.visualContextMode='per_analysis_default';
    if(indices.length)out.analysisIndex=indices[0];
    const metrics=selectedMetricIds();if(metrics.length)out.metricIds=metrics;
    if(includeStatistical){
      const statisticalTarget=optionalPositiveInteger(STATE.statistical.targetIndex,'Statistical targetIndex');if(statisticalTarget!=null)out.targetIndex=statisticalTarget;
      if(STATE.statistical.modelSource)out.modelSource=String(STATE.statistical.modelSource);
      const statisticalClassifier=optionalPositiveInteger(STATE.statistical.classifierIndex,'Statistical classifierIndex');if(statisticalClassifier!=null)out.classifierIndex=statisticalClassifier;
      if(Number(STATE.statistical.referenceAnalysisIndex)>0)out.referenceAnalysisIndex=Number(STATE.statistical.referenceAnalysisIndex);
      out.statisticalPlotMode=STATE.statistical.plotMode;out.statisticalOrderMode=STATE.orderMode;out.statisticalColormap=STATE.statistical.colormap;out.statisticalShowHeatValues=STATE.statistical.showHeatValues!==false;
    }
    if(includeVisual){
      const visualTarget=optionalPositiveInteger(STATE.visual.targetIndex,'Visual targetIndex');if(visualTarget!=null)out.visualTargetIndex=visualTarget;
      if(STATE.visual.modelSource)out.visualModelSource=String(STATE.visual.modelSource);
      const visualClassifier=optionalPositiveInteger(STATE.visual.classifierIndex,'Visual classifierIndex');if(visualClassifier!=null)out.visualClassifierIndex=visualClassifier;
      const visualMode=optionalPositiveInteger(STATE.visual.multiClassModeIndex,'Visual multiClassModeIndex');if(visualMode!=null)out.visualMultiClassModeIndex=visualMode;
      const visualMetrics=Array.from(STATE.visual.metricIds);if(visualMetrics.length)out.visualMetricIds=visualMetrics;
      out.visualPlotMode=STATE.visual.plotMode;out.visualSort=STATE.orderMode!=='original';out.visualOrderMode=STATE.orderMode;out.visualSeparateAxisMetricIds=Array.from(STATE.visual.separateAxis);out.visualMetricColors=Array.from(STATE.visual.colors.entries()).map(([metricId,color])=>({metricId,color}));
    }
    return out;
  }

  /**
   * Purpose: Query authoritative Scientific State analysis_set inventory for the current selection.
   * Syntax: queryAnalysisSet(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  async function queryAnalysisSet(opts){
    if(STATE.inventoryBusy)return;const indices=selectedIndices();if(!indices.length){opts.setMessage('Select at least one completed analysis before querying results.','warn');return;}
    STATE.inventoryBusy=true;render(opts);
    try{
      const spec={analysisIndices:indices};if(indices.length)spec.analysisIndex=indices[0];
      const out=await opts.matlabService({operation:'results_viewer_analysis_set_inventory',spec});if(!out||out.ok===false||!out.scientificState)throw new Error(out&&out.message||'Analysis-set Scientific State query failed.');
      STATE.inventoryState=out.scientificState;STATE.batchModalOpen=false;STATE.batchCells=new Set();STATE.result=null;STATE.statisticalResult=null;STATE.visualResult=null;STATE.metricIds=new Set();STATE.visual.metricIds=new Set();
    }catch(err){opts.setMessage(`Analysis-set query failed: ${err&&err.message?err.message:String(err)}`,'danger');}
    finally{STATE.inventoryBusy=false;render(opts);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}
  }

  /**
   * Purpose: Update transient selection without silently rebuilding Scientific State.
   * Syntax: updateSelection(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function updateSelection(indices,payload,opts){STATE.batchModalOpen=false;STATE.batchCells=new Set();STATE.batchMessage='';STATE.selected=new Set(arr(indices).map(Number).filter(Number.isFinite));STATE.result=null;STATE.statisticalResult=null;STATE.statistical={targetIndex:null,modelSource:'',classifierIndex:null,referenceAnalysisIndex:0,plotMode:'performance_violin',colormap:'legacy',showHeatValues:true};STATE.metricIds=new Set();normalizeSelectedSource(payload);render(opts);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}

  /**
   * Purpose: Render presentation aliases for the currently selected analyses.
   * Syntax: aliasControlsHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function aliasControlsHtml(payload){
    const byIndex=new Map(completedAnalyses(payload).map(row=>[analysisIndex(row),row]));
    const rows=selectedIndices().map(idx=>{const row=byIndex.get(idx)||{},label=String(row.title||row.id||`Analysis ${idx}`);return `<label class="rvCrossAliasRow"><span>[${idx}] ${esc(label)}</span><input type="text" data-cross-analysis-alias="${idx}" value="${esc(STATE.aliases.get(idx)||label)}"></label>`;}).join('');
    return `<details class="rvCrossAliases"${STATE.aliasEditorOpen?' open':''}><summary>Analysis aliases</summary><div>${rows||'<span>No analyses selected.</span>'}</div></details>`;
  }

  /**
   * Purpose: Render the one Cross-analysis-wide presentation tool for aliases and analysis ordering.
   * Syntax: crossAnalysisToolsHtml(payload).
   * Inputs: Completed-analysis catalogue plus resident presentation-only aliases/order.
   * Outputs: Persistent alias editor and original/ascending/descending order selector shared by every Cross-analysis method.
   * Authority and flow: Numeric analysis identity remains authoritative; aliases and ordering are caller-owned presentation state consumed by Performance, Statistical, Visual and Report Builder projections.
   * Scientific/state contract: Ordering never changes matched matrices, test inputs, metric values, or analysis ids.
   * Invariants: Exactly one alias editor and one order control exist in the Cross-analysis shell; panel renderers do not create competing copies.
   * Materialization and performance: O(A) compact DOM text only; no service call, files, scientific arrays, or retained resource creation.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe on every retained Cross-analysis render; it projects resident presentation state and triggers no scientific rematerialization.
   * Failure semantics: Missing analyses produce an explicit empty editor while preserving the original-order default.
   * Side effects: Returns markup only; bindControls owns state changes.
   * Consumers and dependencies: shellHtml and every Cross-analysis panel renderer.
   */
  function crossAnalysisToolsHtml(payload){
    return `<section class="rvCrossSharedTools"><div class="rvCrossSectionHead"><strong>Cross-analysis presentation</strong><span>Aliases and order apply to every method.</span></div><div class="rvCrossSharedToolsBody">${aliasControlsHtml(payload)}<label class="rvCrossOrderControl">Analysis order<select id="rvCrossOrder"><option value="original"${STATE.orderMode==='original'?' selected':''}>Original</option><option value="ascending"${STATE.orderMode==='ascending'?' selected':''}>Performance ascending</option><option value="descending"${STATE.orderMode==='descending'?' selected':''}>Performance descending</option></select></label></div></section>`;
  }

  /**
   * Purpose: Render common CV/OOCV source options from backend source authorities.
   * Syntax: sourceOptionsHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function sourceOptionsHtml(payload){return commonSourceOptions(payload).map(s=>`<option value="${esc(s.id||'')}"${String(s.id||'')===STATE.source?' selected':''}>${esc(s.label||s.id||'')}</option>`).join('');}

  /**
   * Purpose: Render metric-selection controls over backend metricOptions only.
   * Syntax: metricControlsHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function metricControlsHtml(){
    const options=arr(STATE.result&&STATE.result.metricOptions);if(!options.length)return'';
    return `<div class="rvCrossMetricControls"><div class="rvCrossSectionHead"><strong>Performance metrics</strong><div class="rvCrossSectionTools"><button type="button" data-cross-metric-bulk="all">Select all</button><button type="button" data-cross-metric-bulk="none">Deselect all</button></div></div><div class="rvCrossMetricGrid">${options.map(m=>`<label><input type="checkbox" data-cross-metric="${esc(m.id)}"${STATE.metricIds.has(String(m.id))?' checked':''}> ${esc(m.label||m.id)}</label>`).join('')}</div></div>`;
  }

  /**
   * Purpose: Define deterministic context identity for pivoting already-materialized long-form backend rows.
   * Syntax: contextKey(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function contextKey(r){return [r.analysisIndex,r.analysis,r.alias,r.task,r.source,r.target,r.modelSource,r.classifier].map(v=>String(v==null?'':v)).join('\u001f');}

  /**
   * Purpose: Pivot selected backend metrics for display/export without recomputing values.
   * Syntax: filteredPivot(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function filteredPivot(result,ids){
    const allRows=arr(result.allRows),options=arr(result.metricOptions),labels=new Map(options.map(m=>[String(m.id),String(m.label||m.id)])),groups=new Map();
    allRows.forEach(r=>{if(!ids.includes(String(r.metricId)))return;const key=contextKey(r);if(!groups.has(key))groups.set(key,{meta:r,metrics:new Map()});groups.get(key).metrics.set(String(r.metricId),r.value);});
    const header=['Analysis','Alias','Task','Source','Target','Model source','Classifier'].concat(ids.map(id=>labels.get(id)||id));
    const ordered=Array.from(groups.values()),direction=STATE.orderMode==='descending'?-1:1;
    if(STATE.orderMode==='ascending'||STATE.orderMode==='descending')ordered.sort((a,b)=>{const score=g=>{const values=ids.map(id=>Number(g.metrics.get(id))).filter(Number.isFinite);return values.length?values.reduce((sum,value)=>sum+value,0)/values.length:NaN;},av=score(a),bv=score(b);if(!Number.isFinite(av)||!Number.isFinite(bv))return Number.isFinite(av)?-1:Number.isFinite(bv)?1:Number(a.meta.analysisIndex)-Number(b.meta.analysisIndex);return direction*(av-bv)||Number(a.meta.analysisIndex)-Number(b.meta.analysisIndex);});
    const rows=ordered.map(g=>[g.meta.analysis,String(STATE.aliases.get(Number(g.meta.analysisIndex))||g.meta.alias||''),g.meta.task,g.meta.source,g.meta.target,g.meta.modelSource,g.meta.classifier].concat(ids.map(id=>g.metrics.has(id)?g.metrics.get(id):'')));
    if(rows.some(row=>row[4]==='')){header.splice(4,1);rows.forEach(row=>row.splice(4,1));}
    return {header,rows,metricIds:ids,metricLabels:ids.map(id=>labels.get(id)||id)};
  }

  // Export-only grouping by the established performance result families.
  // Each family consumes the same table projection as the on-screen tabulator.
  function performanceExportSections(result,ids,sourceLabel){
    const families=[['classification','Binary'],['multiclass','MultiClass'],['regression','Regression']];
    const sections=[];
    let metricLabels=[];
    for(const [task,family] of families){
      const familyRows=arr(result.allRows).filter(row=>row.task===task);
      if(!familyRows.length)continue;
      const table=filteredPivot({allRows:familyRows,metricOptions:result.metricOptions},ids);
      metricLabels=table.metricLabels;
      const targetIndex=table.header.indexOf('Target');
      const classifierIndex=table.header.indexOf('Classifier');
      const header=table.header.map((label,i)=>i===targetIndex?'Outcome':i===classifierIndex?(task==='regression'?'Model':'Classifier / contrast'):label);
      const projected=tableArtifactProjection(header,table.rows);
      const title=`${sourceLabel} - ${family}`;
      sections.push({sheetName:title,title,columns:projected.columns,rows:projected.rows});
    }
    if(!sections.length)throw new Error('The selected source has no recognized performance result family.');
    return {sections,metricLabels};
  }

  /**
   * Purpose: Build one generic table artefact from the authoritative materialized Performance Tabulator result.
   * Syntax: performanceTableArtifact(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function performanceTableArtifact(){
    if(!STATE.result||STATE.result.ok===false)throw new Error('Generate the performance table before exporting it.');if(!STATE.metricIds.size)throw new Error('Select at least one performance metric before exporting the table.');
    const output=global.NMResultsViewerOutput;if(!output)throw new Error('The generic Results Viewer table output API is unavailable.');const exportTables=performanceExportSections(STATE.result,selectedMetricIds(),STATE.source==='cv'?'CV':STATE.source.replace('oocv:','OOCV ')),sections=exportTables.sections;
    return output.table({representationId:'cross_analysis.performance_table',title:'Cross-analysis performance table',columns:sections[0].columns,rows:sections[0].rows,tables:sections,metadataRows:[['Analysis indices',selectedIndices().join(', ')],['Result source',STATE.source],['Metrics',exportTables.metricLabels.join(' · ')]],provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices(),scientificAnnotations:arr(STATE.result.scientificAnnotations)}});
  }

  // Explicit export: one existing single-source performance request per selected column.
  // Every request contains only the checked analysis indices for that source.
  async function exportBatch(opts,payload){
    if(STATE.batchBusy)return;
    if(!selectionMatchesInventory())throw new Error('Query the selected analysis set again before exporting.');
    if(!STATE.metricIds.size)throw new Error('Generate a performance table and select export metrics first.');
    const matrix=resultSpaceMatrix(payload),ids=selectedMetricIds(),sections=[];
    const selected=matrix.columns.map(source=>({source,indices:matrix.participants.get(source.id).filter(idx=>STATE.batchCells.has(batchCellKey(idx,source.id)))})).filter(group=>group.indices.length);
    if(!selected.length)throw new Error('Select at least one available analysis/result-source cell.');
    STATE.batchBusy=true;STATE.batchMessage='Materializing selected performance results…';render(opts);
    try{
      const annotations=[],selectionRows=[];
      for(const {source,indices} of selected){
        const spec=requestOverrides('performance');
        spec.analysisIndices=indices;spec.analysisIndex=indices[0];spec.crossAnalysisSource=source.id;
        delete spec.metricIds;
        const response=await opts.matlabService({operation:'results_viewer_cross_analysis_performance_table',spec});
        if(!response||response.ok===false||!response.payload||response.payload.ok===false)throw new Error(`Source ${source.id}: ${response&&response.message||'performance request failed'}`);
        const result=response.payload,available=new Set(arr(result.metricOptions).map(option=>String(option.id)));
        const missing=ids.filter(id=>!available.has(id));
        if(missing.length)throw new Error(`Source ${source.id} does not provide selected metric(s): ${missing.join(', ')}. Change the metric selection before exporting.`);
        sections.push(...performanceExportSections(result,ids,source.id==='cv'?'CV':source.id.replace('oocv:','OOCV ')).sections);
        annotations.push(...arr(result.scientificAnnotations));
        indices.forEach(idx=>selectionRows.push({analysisIndex:idx,analysis:STATE.aliases.get(idx),source:source.id,description:matrix.byAnalysis.get(idx).get(source.id).label}));
      }
      sections.unshift({sheetName:'Selected result spaces',title:'Selected result spaces',columns:[{key:'analysisIndex',label:'Analysis index'},{key:'analysis',label:'Analysis'},{key:'source',label:'Result source'},{key:'description',label:'OOCV container description'}],rows:selectionRows});
      const output=global.NMResultsViewerOutput;
      if(!output)throw new Error('The generic Results Viewer output API is unavailable.');
      const artifact=output.table({representationId:'cross_analysis.batch_performance',title:'Cross-analysis CV and OOCV performance',columns:sections[0].columns,rows:sections[0].rows,tables:sections,metadataRows:[['Queried analyses',selectedIndices().join(', ')],['Exported result sources',selected.map(group=>group.source.id).join(', ')],['Selected metrics',ids.join(', ')]],provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices(),scientificAnnotations:annotations}});
      // The shared export dialog must not open beneath the result-space modal.
      STATE.batchModalOpen=false;render(opts);
      try {
        const outcome=await opts.exportTableArtifact(artifact);
        if(!outcome)STATE.batchModalOpen=true;
      } catch(err) {
        STATE.batchModalOpen=true;
        throw err;
      }
    }finally{
      STATE.batchBusy=false;render(opts);
    }
  }

  /**
   * Purpose: Render generated performance-table state and metric controls.
   * Syntax: resultHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function resultHtml(){
    if(!STATE.result)return '<div class="rvPanelNotice">Query the analysis set, then generate the performance table. Scientific values are materialized only when requested.</div>';
    if(STATE.result.ok===false)return `<div class="rvPanelNotice warn">${esc(STATE.result.message||'Performance table unavailable.')}</div>`;
    if(!STATE.metricIds.size)return `${metricControlsHtml()}<div class="rvPanelNotice">No performance metrics are selected.</div>`;
    const table=filteredPivot(STATE.result,selectedMetricIds()),head=`<tr>${table.header.map(h=>`<th>${esc(h)}</th>`).join('')}</tr>`,body=table.rows.map(row=>`<tr>${row.map(v=>`<td>${esc(v)}</td>`).join('')}</tr>`).join(''),warnings=arr(STATE.result.warnings).filter(Boolean);
    return `${metricControlsHtml()}<div class="rvCrossTableMeta"><span>${esc(STATE.result.message||'')}</span>${warnings.length?`<span title="${esc(warnings.join('\n'))}">${warnings.length} unavailable context${warnings.length===1?'':'s'}</span>`:''}</div><div class="rvCrossTableScroll"><table class="rvCrossPerformanceTable"><thead>${head}</thead><tbody>${body||'<tr><td colspan="7">No rows match the selected metrics.</td></tr>'}</tbody></table></div>`;
  }

  /** Resolve Statistical-comparison admission exclusively from the queried analysis-set Scientific State. */
  /**
   * Purpose: Admit a selected analysis set to statistical comparison before numerical materialization.
   * Syntax: statisticalEligibility().
   * Inputs: Queried resident Scientific State inventory and the controlled selected analysis indices.
   * Outputs: Explicit ok/message result plus the shared optimization-criterion identity when eligible.
   * Authority and flow: Consumes only Scientific State capability, CV-group and optimizationCriterion fields.
   * Scientific/state contract: Statistical comparison requires Model Optimization availability, one CV-equivalence group and one exact criterion key across every selected analysis.
   * Invariants: No target payload, CV2 matrix or performance vector is requested or inspected here.
   * Materialization and performance: O(A) compact metadata inspection on an explicit UI action; no scientific arrays are created.
   * Interactive/retained use: Safe for retained presentation because it reads only the already-queried analysis_set inventory.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Stale, incomplete, CV-incompatible or criterion-incompatible sets return a specific non-eligible message.
   * Side effects: None.
   * Consumers and dependencies: statisticalPanelHtml and generateStatistical; depends on Scientific State inventory identity only.
   */
  function statisticalEligibility(){
    if(!selectionMatchesInventory())return {ok:false,message:'Query the selected analysis set before statistical comparison.'};
    const rows=arr(STATE.inventoryState&&STATE.inventoryState.inventory),wanted=new Set(selectedIndices()),selected=rows.filter(row=>wanted.has(Number(row.analysisIndex)));
    if(selected.length<2)return {ok:false,message:'Select at least two completed analyses.'};
    if(selected.some(row=>!(row.capabilities&&row.capabilities.modelOptimization)))return {ok:false,message:'Every selected analysis must expose Model Optimization.'};
    const cv=new Set(selected.map(row=>Number(row.cvGroup)));
    if(cv.size!==1)return {ok:false,message:'Only analyses with identical CV structure are eligible for statistical comparison.'};
    const keys=selected.map(row=>String(row.optimizationCriterion&&row.optimizationCriterion.key||''));
    if(keys.some(key=>!key))return {ok:false,message:'Optimization-criterion identity is missing from the queried Scientific State.'};
    if(new Set(keys).size!==1)return {ok:false,message:'Only analyses sharing the same optimization criterion are eligible for statistical comparison.'};
    const criterion=selected[0].optimizationCriterion||{};
    return {ok:true,criterion,message:`Eligible shared criterion: ${String(criterion.label||'Optimization criterion')}.`};
  }


  /**
   * Purpose: Render the statistical-comparison controls and canonical backend plot payload without scientific recomputation.
   * Syntax: statisticalPanelHtml().
   * Inputs: Resident statistical result/selector presentation state returned by the MATLAB authority.
   * Outputs: Controls, numerical summary and SVG visualizations for Quade/reference Wilcoxon; exactly-two paired Wilcoxon remains table-only.
   * Authority and flow: Values, KDE rows, deltas, summaries, confidence intervals and FDR probabilities come from cross_analysis.statistical_comparison. JavaScript computes SVG coordinates only and delegates violin geometry to NMResultsPlotD3.
   * Scientific/state contract: Browser code never derives pairwise performance deltas, inferential p-values, FDR corrections or confidence intervals.
   * Invariants: Original order is the backend payload order; user ordering and aliases are presentation-only; the selected optional reference is singular; no dedicated two-analysis plot is invented.
   * Materialization and performance: O(B*A) presentation geometry over compact returned statistical vectors; no MATLAB rematerialization except explicit Generate and no files/XML/atlas/mesh/voxel/vertex work.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices and creates no feature-scale arrays; safe for explicit Cross-analysis rendering.
   * Failure semantics: Missing/failed payload displays the backend diagnostic; unsupported plot types are shown as unavailable rather than substituted.
   * Side effects: Returns markup only.
   * Consumers and dependencies: activePanelHtml, bindControls and generateStatistical.
   * Interactive/retained use: Presentation-only or explicit Generate behavior; no hidden retained scientific rematerialization is introduced.
   */
  function statisticalPanelHtml(payload){
    void payload;const r=STATE.statisticalResult,eligibility=statisticalEligibility(),eligibilityNotice=eligibility.ok?'':`<div class="rvPanelNotice warn">${esc(eligibility.message)}</div>`;
    if(!r)return `<div class="rvCrossFunctionPanel"><h3>Statistical comparison</h3><p class="rvHelpText">Uses matched CV2 optimization-criterion matrices from Model Optimization. Exactly two analyses use paired Wilcoxon; more than two use Quade unless one reference analysis is selected.</p><div class="rvCrossActions"><button id="rvCrossStatGenerate" type="button" class="primary"${STATE.statisticalBusy||!eligibility.ok?' disabled':''}>${STATE.statisticalBusy?'Computing…':'Generate statistical comparison'}</button></div>${eligibilityNotice}</div>`;
    if(r.ok===false)return `<div class="rvCrossFunctionPanel"><h3>Statistical comparison</h3><div class="rvCrossActions"><button id="rvCrossStatGenerate" type="button" class="primary"${STATE.statisticalBusy||!eligibility.ok?' disabled':''}>Retry</button></div>${eligibilityNotice}<div class="rvPanelNotice warn">${esc(r.message||'Statistical comparison unavailable.')}</div></div>`;
    const o=r.selectorOptions||{},targets=arr(o.targets),sources=arr(o.modelSources),classifiers=arr(o.classifiers),refs=arr(o.referenceOptions);
    const targetOpts=targets.map(x=>`<option value="${Number(x.resultIndex)}"${Number(x.resultIndex)===Number(STATE.statistical.targetIndex)?' selected':''}>${esc(x.label||`Target ${x.resultIndex}`)}</option>`).join('');
    const sourceOpts=sources.map(x=>`<option value="${esc(x.id)}"${String(x.id)===String(STATE.statistical.modelSource)?' selected':''}>${esc(x.label||x.id)}</option>`).join('');
    const classifierOpts=classifiers.map(x=>`<option value="${Number(x.index)}"${Number(x.index)===Number(STATE.statistical.classifierIndex)?' selected':''}>${esc(x.label||`Model ${x.index}`)}</option>`).join('');
    const refOpts=refs.map(x=>`<option value="${Number(x.analysisIndex)}"${Number(x.analysisIndex)===Number(STATE.statistical.referenceAnalysisIndex)?' selected':''}>${esc(x.label)}</option>`).join('');
    const targetControl=targets.length>1?`<label>Target<select id="rvCrossStatTarget">${targetOpts}</select></label>`:'';
    const controls=`<div class="rvCrossOptions">${targetControl}<label>Model source<select id="rvCrossStatSource">${sourceOpts}</select></label><label>Classifier/model<select id="rvCrossStatClassifier">${classifierOpts}</select></label>${selectedIndices().length>2?`<label>Reference model<select id="rvCrossStatReference">${refOpts}</select></label>`:''}</div>`;
    const summary=`<div class="rvCrossTableMeta"><span>Test: ${esc(r.testType)}</span><span>Criterion: ${esc(r.optimizationCriterion&&r.optimizationCriterion.label||'')}</span><span>Matched CV2 cells: ${Number(r.matchedCV2&&r.matchedCV2.blockCount||0)}</span></div>`;
    return `<div class="rvCrossFunctionPanel"><h3>Statistical comparison</h3>${controls}<div class="rvCrossActions"><button id="rvCrossStatGenerate" type="button" class="primary"${STATE.statisticalBusy||!eligibility.ok?' disabled':''}>${STATE.statisticalBusy?'Computing…':'Update comparison'}</button></div>${summary}${eligibilityNotice}<div class="rvCrossStatPlots">${statisticalPlotsHtml(r)}</div>${statisticalTablesHtml(r)}</div>`;
  }

  /**
   * Purpose: Serialize backend statistical tables for browser inspection only.
   * Syntax: statisticalTablesHtml(result).
   * Inputs: Canonical statistical table payload.
   * Outputs: Compact HTML tables.
   * Authority and flow: Pure rendering of backend tables; no statistics are computed.
   * Scientific/state contract: Values are unchanged projections of the backend artefact.
   * Invariants: No numerical recomputation or scientific reordering.
   * Materialization and performance: O(table cells) DOM string work.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation because it serializes resident compact table values only.
   * Failure semantics: Empty tables are omitted.
   * Side effects: None.
   * Consumers and dependencies: statisticalPanelHtml.
   */
  function statisticalTablesHtml(r){const tables=r&&r.tables||{},spec=[['testSummary','omnibus','Omnibus statistics'],['postHoc','pairwise','Pairwise statistics']];return spec.map(([name,id,title])=>{const rows=statisticalTableMatrix(tables,name);if(!rows.length)return'';return `<section class="rvCrossStatPanel" data-cross-stat-panel="${id}"><header><h4>${title}</h4>${statisticalPanelActions(id,true)}</header><div class="rvCrossTableScroll"><table class="rvCrossPerformanceTable"><tbody>${rows.map((row,ri)=>`<tr>${row.map(v=>ri===0?`<th>${esc(v)}</th>`:`<td>${esc(v)}</td>`).join('')}</tr>`).join('')}</tbody></table></div></section>`;}).join('');}

  /**
   * Purpose: Render the backend-owned statistical plot family.
   * Syntax: statisticalPlotsHtml(result).
   * Inputs: Canonical backend plotPayload.
   * Outputs: SVG markup for the applicable statistical-comparison views.
   * Authority and flow: Plot selection follows backend test type; no alternate statistics are computed.
   * Scientific/state contract: Quade/reference plot semantics remain legacy-compatible.
   * Invariants: Two-analysis type none yields no invented plot.
   * Materialization and performance: Compact SVG geometry only.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of an already-materialized statistical artefact.
   * Failure semantics: Unknown types render an explicit notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPanelHtml.
   */
  function statisticalAlias(index,fallback){return String(STATE.aliases.get(Number(index))||fallback||`Analysis ${Number(index)}`);}
  function statisticalOrder(p){const base=arr(p&&p.performance),order=base.map((_,i)=>i),mode=STATE.orderMode;if(mode==='ascending'||mode==='descending')order.sort((a,b)=>{const av=Number(base[a]&&base[a].summary&&base[a].summary.median),bv=Number(base[b]&&base[b].summary&&base[b].summary.median);if(!Number.isFinite(av)||!Number.isFinite(bv))return Number.isFinite(av)?-1:Number.isFinite(bv)?1:a-b;const delta=av-bv;return (mode==='descending'?-delta:delta)||(a-b);});return order;}
  function orderedSeries(p,key,order){return order.map(i=>{const source=arr(p&&p[key])[i]||{};return Object.assign({},source,{label:statisticalAlias(source.analysisIndex,source.label)});});}
  function orderedMatrix(matrix,order){const rows=arr(matrix).map(arr);return order.map(i=>order.map(j=>rows[i]&&rows[i][j]));}
  function statisticalPairs(p,order){const indices=arr(p&&p.performance).map(s=>Number(s.analysisIndex)),rank=new Map(arr(order).map((position,i)=>[indices[position],i]));return arr(p&&p.oneVsOne).map(pair=>Object.assign({},pair,{label:`${statisticalAlias(pair.fromIndex,'')} − ${statisticalAlias(pair.toIndex,'')}`})).sort((a,b)=>(rank.get(Number(a.fromIndex))||0)-(rank.get(Number(b.fromIndex))||0)||(rank.get(Number(a.toIndex))||0)-(rank.get(Number(b.toIndex))||0));}
  function statisticalPlotControls(){return `<div class="rvCrossStatFigureControls"><label>Upper plot<select id="rvCrossStatPlotMode"><option value="performance_violin"${STATE.statistical.plotMode==='performance_violin'?' selected':''}>Performance violins</option><option value="one_vs_all_violin"${STATE.statistical.plotMode==='one_vs_all_violin'?' selected':''}>One-vs-all violins</option><option value="one_vs_one_box"${STATE.statistical.plotMode==='one_vs_one_box'?' selected':''}>One-vs-one boxplots</option><option value="median_iqr"${STATE.statistical.plotMode==='median_iqr'?' selected':''}>Median + IQR</option></select></label><label>Heatmap<select id="rvCrossStatColormap"><option value="legacy"${STATE.statistical.colormap==='legacy'?' selected':''}>Legacy spectrum</option><option value="viridis"${STATE.statistical.colormap==='viridis'?' selected':''}>Viridis</option><option value="grayscale"${STATE.statistical.colormap==='grayscale'?' selected':''}>Grayscale</option></select></label><label class="rvCrossStatValueToggle"><input id="rvCrossStatHeatValues" type="checkbox"${STATE.statistical.showHeatValues!==false?' checked':''}> Cell values</label></div>`;}
  function statisticalPanelActions(id,hasData){return `<div class="rvCrossStatPanelActions"><button type="button" class="rvPanelExport rvCrossStatExportButton" data-cross-stat-export="${esc(id)}" title="Export panel" aria-label="Export panel"${hasData?'':' disabled'}>${STATE.exportIconMarkup}</button></div>`;}
  function statisticalPlotsHtml(r){const p=r&&r.plotPayload||{};if(p.type==='none')return `<div class="rvPanelNotice">${esc(p.message||'No dedicated plot for this test.')}</div>`;if(p.type==='reference_bar')return `<section class="rvCrossStatPanel" data-cross-stat-panel="reference"><header><h4>Reference-model comparison</h4>${statisticalPanelActions('reference',true)}</header><div class="rvCrossStatFigureSvg">${referenceBarSvg(p)}</div></section>`;if(p.type!=='quade')return '<div class="rvPanelNotice warn">Statistical plot payload is unavailable.</div>';const order=statisticalOrder(p),performance=orderedSeries(p,'performance',order),oneVsAll=orderedSeries(p,'oneVsAll',order),medianIqr=orderedSeries(p,'medianIqr',order),pairs=statisticalPairs(p,order),labels=performance.map(s=>s.label),criterion=p.criterion||{},randomReference=p.randomPerformanceReference||{},plotMode=STATE.statistical.plotMode;let upper='';if(plotMode==='one_vs_all_violin')upper=violinSvg(oneVsAll,`Difference in ${p.criterionLabel||'optimization criterion'}`,criterion,true,randomReference);else if(plotMode==='one_vs_one_box')upper=verticalBoxSvg(pairs,`Difference in ${p.criterionLabel||'optimization criterion'}`);else if(plotMode==='median_iqr')upper=medianIqrSvg(medianIqr,p.criterionLabel,criterion,randomReference);else upper=violinSvg(performance,p.criterionLabel,criterion,false,randomReference);const heat=matrixSvg(orderedMatrix(p.negLog10FdrMatrix,order),labels);return `<section class="rvCrossStatPanel rvCrossStatLegacyFigure" data-cross-stat-panel="main"><header><h4>Statistical performance comparison</h4>${statisticalPanelActions('main',true)}</header>${statisticalPlotControls()}<div class="rvCrossStatFigureSvg" data-cross-stat-figure="main">${upper}${heat}</div></section><section class="rvCrossStatPanel" data-cross-stat-panel="intervals"><header><h4>One-vs-one horizontal interval plot</h4>${statisticalPanelActions('intervals',true)}</header><div class="rvCrossStatFigureSvg">${boxSvg(pairs,`Difference in ${p.criterionLabel||'optimization criterion'}`)}</div></section>`;}

  /**
   * Purpose: Convert supplied canonical values to violin outline geometry only.
   * Syntax: violinSvg(series,yLabel).
   * Inputs: Backend canonical series values, summaries and labels.
   * Outputs: SVG violin shapes.
   * Authority and flow: Backend KDE rows are rendered exclusively through the shared NMResultsPlotD3 violin primitive; scientific values and deltas originate in the backend.
   * Scientific/state contract: No inferential or pairwise-delta calculation occurs here.
   * Invariants: Criterion-aware vertical scale and requested presentation order are preserved; no browser KDE implementation exists.
   * Materialization and performance: O(values) browser geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of resident statistical vectors.
   * Failure semantics: Empty data yields an explicit notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPlotsHtml.
   */
  function summaryPlotValues(summary){const q=summary||{};return [q.min,q.q1,q.mean,q.median,q.q3,q.max].map(Number).filter(Number.isFinite);}
  function criterionLimits(series,criterion,isDelta){const finite=arr(series).flatMap(s=>arr(s&&s.values).map(Number).filter(Number.isFinite).concat(summaryPlotValues(s&&s.summary)));if(!finite.length)return[-1,1];if(isDelta){const ext=Math.max(...finite.map(Math.abs),1e-9);return[-ext*1.08,ext*1.08];}const scale=criterion&&criterion.scale||{},mode=String(scale.mode||'data');let lo=Math.min(...finite),hi=Math.max(...finite);if(mode==='bounded'&&Number.isFinite(Number(scale.minimum))&&Number.isFinite(Number(scale.maximum))){lo=Math.min(lo,Number(scale.minimum));hi=Math.max(hi,Number(scale.maximum));}else if(mode==='nonnegative')lo=Math.min(0,lo);if(!(hi>lo)){const pad=Math.max(.5,Math.abs(lo)*.05);lo-=pad;hi+=pad;}else if(mode!=='bounded'){const pad=(hi-lo)*.07;lo-=pad;hi+=pad;}return[lo,hi];}
  const STAT_ANALYSIS_GRID={width:920,left:190,right:92};
  function categoricalTickPlan(labels,plotWidth,fontSize){const labs=arr(labels).map(value=>String(value==null?'':value)),tools=plotTools(),font=Number(fontSize||11),slot=Math.max(1,Number(plotWidth||1)/Math.max(1,labs.length)),horizontalWidth=Math.max(28,slot*.78),horizontal=labs.every(label=>tools.measureTextWidth(label,font)<=horizontalWidth);if(horizontal)return{labels:labs,angle:0};const fitted=labs.map(label=>tools.fitLabel(label,Math.max(54,Math.min(170,slot*1.55)),font));return{labels:fitted,angle:-32};}
  function violinSvg(series,yLabel,criterion,isDelta,randomReference){const finite=series.flatMap(s=>arr(s.values).map(Number).filter(Number.isFinite));if(!finite.length)return'<div class="rvPanelNotice">No finite plot values.</div>';const tools=plotTools(),W=STAT_ANALYSIS_GRID.width,H=430,n=series.length,lim=criterionLimits(series,criterion,isDelta),ticks=Array.from({length:n},(_,i)=>i+1),fullLabels=series.map(s=>String(s.label)),labelPlan=categoricalTickPlan(fullLabels,W-STAT_ANALYSIS_GRID.left-STAT_ANALYSIS_GRID.right,11),ax=tools.cartesianAxes({w:W,h:H,m:{left:STAT_ANALYSIS_GRID.left,right:STAT_ANALYSIS_GRID.right,top:30,bottom:labelPlan.angle===0?62:132},autoMargin:false,xLim:[.5,n+.5],yLim:lim,xTicks:ticks,xFmt:v=>labelPlan.labels[Math.round(v)-1],xTickAngle:labelPlan.angle,xLabel:'Analyses',yLabel:(yLabel ? yLabel : 'Value'),noPrettifyLabels:true,tickFontSize:11,axisFontSize:13,yLabelX:STAT_ANALYSIS_GRID.left-58}),clipId='rvCrossStatViolinClip';let body=ax.svg,marks='';const reference=isDelta?0:(randomReference&&randomReference.available?Number(randomReference.value):NaN),referenceLabel=isDelta?'No difference':String((randomReference&&randomReference.label ? randomReference.label : 'Random performance'));if(Number.isFinite(reference)&&reference>=lim[0]&&reference<=lim[1])marks+=`<line class="rvCrossStatReference" x1="${ax.m.left}" x2="${W-ax.m.right}" y1="${ax.yPix(reference).toFixed(1)}" y2="${ax.yPix(reference).toFixed(1)}"/><text x="${W-ax.m.right-4}" y="${(ax.yPix(reference)-5).toFixed(1)}" text-anchor="end" font-size="10">${esc(referenceLabel)}</text>`;series.forEach((s,i)=>{const center=i+1,density=arr(s.density),title=String(s.label ? s.label : `Analysis ${i+1}`);marks+=tools.violinPolygon({density,center,xPix:ax.xPix,yPix:ax.yPix,fill:'#2f5597',stroke:'#1e3a67',opacity:.32,title});marks+=tools.violinStatisticLines({density,center,xPix:ax.xPix,yPix:ax.yPix,mean:Number(s.summary&&s.summary.mean),median:Number(s.summary&&s.summary.median),title,formatValue:v=>Number(v).toFixed(3)});});body+=`<defs><clipPath id="${clipId}"><rect x="${ax.m.left}" y="${ax.m.top}" width="${ax.plotW}" height="${ax.plotH}"/></clipPath></defs><g clip-path="url(#${clipId})">${marks}</g><g class="rvCrossStatLegend"><line x1="${W-190}" x2="${W-166}" y1="17" y2="17" stroke="#111827" stroke-width="3"/><text x="${W-160}" y="21" font-size="10">Mean</text><line x1="${W-105}" x2="${W-81}" y1="17" y2="17" stroke="#dc2626" stroke-width="3"/><text x="${W-75}" y="21" font-size="10">Median</text></g>`;return `<svg class="rvCrossStatSvg" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc((yLabel ? yLabel : 'Statistical violin plot'))}">${body}</svg>`;}

  /**
   * Purpose: Draw backend-computed one-vs-one box summaries.
   * Syntax: boxSvg(pairs,yLabel).
   * Inputs: Canonical pair summaries and axis label.
   * Outputs: SVG box summaries.
   * Authority and flow: Quartiles and whiskers are backend-owned; browser computes coordinates only.
   * Scientific/state contract: No quartile or delta recomputation occurs here.
   * Invariants: Pair order and summary values are preserved.
   * Materialization and performance: O(pairs) presentation geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of resident summaries.
   * Failure semantics: Empty input yields an explicit notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPlotsHtml.
   */
  function pairLimits(pairs){const vals=pairs.flatMap(p=>summaryPlotValues(p.summary)),ext=Math.max(...vals.map(Math.abs),1e-9);return[-ext*1.08,ext*1.08];}
  function boxSvg(pairs,yLabel){if(!pairs.length)return'<div class="rvPanelNotice">No post-hoc delta distributions.</div>';const W=920,H=Math.max(330,105+pairs.length*28),lim=pairLimits(pairs),tools=plotTools(),pairLabels=pairs.map(pair=>tools.fitLabel(String(pair.label),220,10)),ax=tools.cartesianAxes({w:W,h:H,m:{left:250,right:30,top:24,bottom:58},xLim:lim,yLim:[.5,pairs.length+.5],yTicks:Array.from({length:pairs.length},(_,i)=>i+1),yFmt:v=>pairLabels[Math.round(v)-1],xLabel:yLabel,yLabel:'',noPrettifyLabels:true,tickFontSize:10,axisFontSize:12});let body=ax.svg+`<line class="rvCrossStatReference" x1="${ax.xPix(0).toFixed(1)}" x2="${ax.xPix(0).toFixed(1)}" y1="${ax.m.top}" y2="${H-ax.m.bottom}"/>`;pairs.forEach((p,i)=>{const q=p.summary,cy=ax.yPix(i+1),x1=ax.xPix(Number(q.min)),x2=ax.xPix(Number(q.max)),q1=ax.xPix(Number(q.q1)),q3=ax.xPix(Number(q.q3)),med=ax.xPix(Number(q.median));body+=`<line x1="${x1.toFixed(1)}" x2="${x2.toFixed(1)}" y1="${cy.toFixed(1)}" y2="${cy.toFixed(1)}" stroke="#334155"/><rect x="${Math.min(q1,q3).toFixed(1)}" y="${(cy-7).toFixed(1)}" width="${Math.max(1,Math.abs(q3-q1)).toFixed(1)}" height="14" fill="#9fb7d7" stroke="#334155"/><line x1="${med.toFixed(1)}" x2="${med.toFixed(1)}" y1="${(cy-9).toFixed(1)}" y2="${(cy+9).toFixed(1)}" stroke="#dc2626" stroke-width="2"/>`;});return `<svg class="rvCrossStatSvg" viewBox="0 0 ${W} ${H}" role="img">${body}</svg>`;}

  function verticalBoxSvg(pairs,yLabel){if(!pairs.length)return'<div class="rvPanelNotice">No post-hoc delta distributions.</div>';const W=920,H=440,n=pairs.length,lim=pairLimits(pairs),tools=plotTools(),labels=pairs.map(pair=>String(pair&&pair.label||'')),labelPlan=categoricalTickPlan(labels,W-106,10),ax=tools.cartesianAxes({w:W,h:H,m:{left:78,right:28,top:28,bottom:68},xLim:[.5,n+.5],yLim:lim,xTicks:Array.from({length:n},(_,i)=>i+1),xFmt:v=>labelPlan.labels[Math.round(v)-1]||'',xTickAngle:labelPlan.angle,xLabel:'Analysis pair',yLabel, noPrettifyLabels:true,tickFontSize:10,axisFontSize:12});let body=ax.svg+`<line class="rvCrossStatReference" x1="${ax.m.left}" x2="${W-ax.m.right}" y1="${ax.yPix(0).toFixed(1)}" y2="${ax.yPix(0).toFixed(1)}"/>`;pairs.forEach((p,i)=>{const q=p.summary||{},cx=ax.xPix(i+1),y1=ax.yPix(Number(q.min)),y2=ax.yPix(Number(q.max)),q1=ax.yPix(Number(q.q1)),q3=ax.yPix(Number(q.q3)),med=ax.yPix(Number(q.median)),bw=Math.min(34,ax.plotW/Math.max(2,n)*.52);body+=`<line x1="${cx.toFixed(1)}" x2="${cx.toFixed(1)}" y1="${y1.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="#334155"/><rect x="${(cx-bw/2).toFixed(1)}" y="${Math.min(q1,q3).toFixed(1)}" width="${bw.toFixed(1)}" height="${Math.max(1,Math.abs(q3-q1)).toFixed(1)}" fill="#9fb7d7" stroke="#334155"/><line x1="${(cx-bw/2).toFixed(1)}" x2="${(cx+bw/2).toFixed(1)}" y1="${med.toFixed(1)}" y2="${med.toFixed(1)}" stroke="#dc2626" stroke-width="2"/>`;});return `<svg class="rvCrossStatSvg" viewBox="0 0 ${W} ${H}" role="img">${body}</svg>`;}

  /**
   * Purpose: Draw backend median/IQR summaries.
   * Syntax: medianIqrSvg(series,yLabel).
   * Inputs: Supplied canonical summaries and axis label.
   * Outputs: SVG median/IQR plot.
   * Authority and flow: Summary values are backend-owned; this helper adapts them to box geometry.
   * Scientific/state contract: No summary recomputation occurs.
   * Invariants: Series order and median/IQR values are preserved.
   * Materialization and performance: O(A) presentation geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of resident summaries.
   * Failure semantics: Empty data yields an explicit notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPlotsHtml.
   */
  function medianIqrSvg(series,yLabel,criterion,randomReference){if(!series.length)return'<div class="rvPanelNotice">No median/IQR summaries.</div>';const W=STAT_ANALYSIS_GRID.width,H=420,n=series.length,lim=criterionLimits(series,criterion,false),tools=plotTools(),labels=series.map(s=>String(s.label)),labelPlan=categoricalTickPlan(labels,W-STAT_ANALYSIS_GRID.left-STAT_ANALYSIS_GRID.right,11),ax=tools.cartesianAxes({w:W,h:H,m:{left:STAT_ANALYSIS_GRID.left,right:STAT_ANALYSIS_GRID.right,top:28,bottom:labelPlan.angle===0?62:132},autoMargin:false,xLim:[.5,n+.5],yLim:lim,xTicks:Array.from({length:n},(_,i)=>i+1),xFmt:v=>labelPlan.labels[Math.round(v)-1],xTickAngle:labelPlan.angle,xLabel:'Analyses',yLabel:(yLabel ? yLabel : 'Performance'),noPrettifyLabels:true,tickFontSize:11,axisFontSize:13,yLabelX:STAT_ANALYSIS_GRID.left-58});const points=series.map((s,i)=>`${ax.xPix(i+1).toFixed(1)},${ax.yPix(Number(s.summary&&s.summary.median)).toFixed(1)}`).join(' ');let body=ax.svg+`<polyline points="${points}" fill="none" stroke="#2f5597" stroke-width="2"/>`;const reference=randomReference&&randomReference.available?Number(randomReference.value):NaN;if(Number.isFinite(reference)&&reference>=lim[0]&&reference<=lim[1])body+=`<line class="rvCrossStatReference" x1="${ax.m.left}" x2="${W-ax.m.right}" y1="${ax.yPix(reference).toFixed(1)}" y2="${ax.yPix(reference).toFixed(1)}"/><text x="${W-ax.m.right-4}" y="${(ax.yPix(reference)-5).toFixed(1)}" text-anchor="end" font-size="10">${esc((randomReference.label ? randomReference.label : 'Random performance'))}</text>`;series.forEach((s,i)=>{const q=s.summary,cx=ax.xPix(i+1),q1=ax.yPix(Number(q.q1)),q3=ax.yPix(Number(q.q3)),med=ax.yPix(Number(q.median));body+=`<line x1="${cx.toFixed(1)}" x2="${cx.toFixed(1)}" y1="${q1.toFixed(1)}" y2="${q3.toFixed(1)}" stroke="#2f5597" stroke-width="2"/><line x1="${(cx-6).toFixed(1)}" x2="${(cx+6).toFixed(1)}" y1="${q1.toFixed(1)}" y2="${q1.toFixed(1)}" stroke="#2f5597"/><line x1="${(cx-6).toFixed(1)}" x2="${(cx+6).toFixed(1)}" y1="${q3.toFixed(1)}" y2="${q3.toFixed(1)}" stroke="#2f5597"/><circle cx="${cx.toFixed(1)}" cy="${med.toFixed(1)}" r="4" fill="#dc2626"/>`;});return `<svg class="rvCrossStatSvg" viewBox="0 0 ${W} ${H}" role="img">${body}</svg>`;}

  /**
   * Purpose: Draw the legacy reference-Wilcoxon median-difference bars plus nm_95confint offsets.
   * Syntax: referenceBarSvg(payload).
   * Inputs: Canonical backend bar records.
   * Outputs: SVG bars and error bars.
   * Authority and flow: Median, CI and p values are backend-owned; browser computes coordinates only.
   * Scientific/state contract: Exact legacy median-difference plus nm_95confint visualization semantics are retained.
   * Invariants: The reference analysis is not plotted as a comparison bar.
   * Materialization and performance: O(A) presentation geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of the resident reference comparison payload.
   * Failure semantics: No bars yields an explicit notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPlotsHtml.
   */
  function referenceBarSvg(p){const bars=arr(p.bars).slice();if(STATE.orderMode!=='original')bars.sort((a,b)=>{const av=Number(a&&a.median),bv=Number(b&&b.median),missingA=!Number.isFinite(av),missingB=!Number.isFinite(bv);if(missingA!==missingB)return missingA?1:-1;if(missingA&&missingB)return 0;return STATE.orderMode==='ascending'?av-bv:bv-av;});if(!bars.length)return'<div class="rvPanelNotice">No reference comparisons.</div>';const ext=bars.flatMap(b=>[Number(b.median)+Number(b.ciLowOffset),Number(b.median)+Number(b.ciHighOffset),Number(b.median),0].filter(Number.isFinite)),rawLo=Math.min(...ext),rawHi=Math.max(...ext),span=Math.max(1e-9,rawHi-rawLo,Math.max(...ext.map(Math.abs))*.15),lim=[rawLo-span*.08,rawHi+span*.08],W=920,H=430,labels=bars.map(b=>statisticalAlias(b.analysisIndex,b.label)),tools=plotTools(),labelPlan=categoricalTickPlan(labels,W-108,10),ticks=Array.from({length:bars.length},(_,i)=>i+1),referenceLabel=statisticalAlias(p.referenceAnalysisIndex,p.referenceLabel||''),ax=tools.cartesianAxes({w:W,h:H,m:{left:80,right:28,top:28,bottom:70},xLim:[.5,bars.length+.5],yLim:lim,xTicks:ticks,xFmt:v=>labelPlan.labels[Math.round(v)-1]||'',xTickAngle:labelPlan.angle,xLabel:'Analyses',yLabel:`Difference in ${p.criterionLabel||'optimization criterion'}`,annotationLines:[`Reference: ${referenceLabel}`],noPrettifyLabels:true,tickFontSize:10,axisFontSize:12}),zero=ax.yPix(0),slot=ax.plotW/bars.length;let body=ax.svg+`<line class="rvCrossStatReference" x1="${ax.m.left}" y1="${zero.toFixed(1)}" x2="${W-ax.m.right}" y2="${zero.toFixed(1)}"/>`;bars.forEach((b,i)=>{const cx=ax.xPix(i+1),med=Number(b.median),yl=ax.yPix(med),top=Math.min(yl,zero),h=Math.abs(zero-yl),low=ax.yPix(med+Number(b.ciLowOffset)),high=ax.yPix(med+Number(b.ciHighOffset)),label=labels[i];body+=`<rect x="${(cx-slot*.28).toFixed(1)}" y="${top.toFixed(1)}" width="${Math.max(2,slot*.56).toFixed(1)}" height="${Math.max(1,h).toFixed(1)}" fill="#9fb7d7" stroke="#334155"><title>${esc(label)} · median difference ${esc(med)}</title></rect><line x1="${cx.toFixed(1)}" y1="${low.toFixed(1)}" x2="${cx.toFixed(1)}" y2="${high.toFixed(1)}" stroke="#334155" stroke-width="2"/><line x1="${(cx-6).toFixed(1)}" y1="${low.toFixed(1)}" x2="${(cx+6).toFixed(1)}" y2="${low.toFixed(1)}" stroke="#334155"/><line x1="${(cx-6).toFixed(1)}" y1="${high.toFixed(1)}" x2="${(cx+6).toFixed(1)}" y2="${high.toFixed(1)}" stroke="#334155"/>`;});return `<svg class="rvCrossStatSvg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Reference-model comparison">${body}</svg>`;}

  /**
   * Purpose: Draw the backend FDR-adjusted -log10(P) comparison matrix.
   * Syntax: matrixSvg(matrix,labels).
   * Inputs: Corrected backend matrix and labels.
   * Outputs: SVG comparison matrix.
   * Authority and flow: Browser only scales supplied values.
   * Scientific/state contract: No FDR or -log10 calculation occurs here.
   * Invariants: Cells correspond exactly to backend ordering.
   * Materialization and performance: O(A^2) presentation geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained presentation of the resident corrected matrix.
   * Failure semantics: Absent post-hoc matrix yields an explanatory notice.
   * Side effects: None.
   * Consumers and dependencies: statisticalPlotsHtml.
   */
  function rgbMix(a,b,t){const parse=h=>[1,3,5].map(i=>parseInt(h.slice(i,i+2),16)),x=parse(a),y=parse(b),v=x.map((n,i)=>Math.round(n+(y[i]-n)*t));return`#${v.map(n=>n.toString(16).padStart(2,'0')).join('')}`;}
  function heatColor(value){const v=Math.max(1.3,Math.min(7,Number(value))),t=(v-1.3)/5.7,mode=STATE.statistical.colormap;if(mode==='grayscale')return rgbMix('#e5e7eb','#111827',t);if(mode==='viridis'){const stops=['#440154','#3b528b','#21918c','#5ec962','#fde725'],p=t*(stops.length-1),i=Math.min(stops.length-2,Math.floor(p));return rgbMix(stops[i],stops[i+1],p-i);}const stops=['#d7f0ff','#2463eb','#20b7b0','#f3df32','#f28e2b','#c91c1c'],p=t*(stops.length-1),i=Math.min(stops.length-2,Math.floor(p));return rgbMix(stops[i],stops[i+1],p-i);}
  function matrixSvg(matrix,labels){const rows=arr(matrix).map(arr),labs=arr(labels).map(String),numeric=v=>v==null||v===''?NaN:Number(v);if(!rows.length)return'<div class="rvPanelNotice">No pairwise post-hoc matrix: the Quade omnibus test did not trigger post-hoc comparisons.</div>';const n=rows.length,W=STAT_ANALYSIS_GRID.width,left=STAT_ANALYSIS_GRID.left,right=STAT_ANALYSIS_GRID.right,top=28,cell=(W-left-right)/Math.max(1,n),gridW=cell*n,tools=plotTools(),labelPlan=categoricalTickPlan(labs,gridW,10),rowLabels=labs.map(label=>tools.fitLabel(label,left-18,10)),bottom=labelPlan.angle===0?58:Math.max(86,Math.min(150,tools.textBox?tools.textBox(labelPlan.labels.reduce((a,b)=>a.length>b.length?a:b,''),10,labelPlan.angle).height+48:105)),H=Math.ceil(top+gridW+bottom),stripeId='rvCrossStatDiagonalStripe';let body=`<defs><pattern id="${stripeId}" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="8" height="8" fill="#e5e7eb"/><rect width="3" height="8" fill="#cbd5e1"/></pattern></defs><text x="${left}" y="17" font-size="12" font-weight="700">FDR-adjusted pairwise significance · −log10(P<tspan baseline-shift="sub" font-size="9">FDR</tspan>)</text>`;rows.forEach((row,i)=>row.forEach((raw,j)=>{const v=numeric(raw),x=left+j*cell,y=top+i*cell,diagonal=i===j,finite=Number.isFinite(v),below=finite&&v<1.3,fill=diagonal?`url(#${stripeId})`:(!finite||below?'#ffffff':heatColor(v)),text=below?'#a8b0bb':tools.cellTextColor(fill,1,'#ffffff'),value=!diagonal&&STATE.statistical.showHeatValues&&finite?v.toFixed(2):'';body+=`<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${cell.toFixed(1)}" height="${cell.toFixed(1)}" fill="${fill}" stroke="#d7dce3"/><text x="${(x+cell/2).toFixed(1)}" y="${(y+cell/2+4).toFixed(1)}" text-anchor="middle" font-size="10" fill="${diagonal?'#64748b':text}">${value}</text>`;}));labs.forEach((full,i)=>{const cy=top+i*cell+cell/2,cx=left+i*cell+cell/2,rowLabel=rowLabels[i],columnLabel=labelPlan.labels[i],axisY=top+gridW+14,rotation=labelPlan.angle;body+=`<text x="${left-9}" y="${(cy+4).toFixed(1)}" text-anchor="end" font-size="10">${esc(rowLabel)}<title>${esc(full)}</title></text>${rotation===0?`<text x="${cx.toFixed(1)}" y="${axisY.toFixed(1)}" text-anchor="middle" font-size="10">${esc(columnLabel)}<title>${esc(full)}</title></text>`:`<text x="${cx.toFixed(1)}" y="${axisY.toFixed(1)}" text-anchor="end" font-size="10" transform="rotate(${rotation} ${cx.toFixed(1)} ${axisY.toFixed(1)})">${esc(columnLabel)}<title>${esc(full)}</title></text>`}`;});const barX=left+gridW+28,barH=gridW,segments=80;for(let k=0;k<segments;k++){const t=k/(segments-1),v=7-t*5.7,segmentH=barH/segments;body+=`<rect x="${barX.toFixed(1)}" y="${(top+k*segmentH).toFixed(2)}" width="18" height="${segmentH.toFixed(2)}" fill="${heatColor(v)}"/>`;}[1.3,2,3,4,5,6,7].forEach(v=>{const y=top+(7-v)/5.7*barH;body+=`<line x1="${barX+18}" x2="${barX+23}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}" stroke="#475569"/><text x="${barX+27}" y="${(y+4).toFixed(1)}" font-size="9">${v===7?'≥7':v.toFixed(v===1.3?1:0)}</text>`;});body+=`<rect x="${barX}" y="${top}" width="18" height="${barH}" fill="none" stroke="#475569"/>`;return `<svg class="rvCrossStatSvg rvCrossStatHeatmap" viewBox="0 0 ${W} ${H}" role="img" aria-label="FDR-adjusted pairwise significance heatmap">${body}</svg>`;}

  /**
   * Purpose: Reconstruct one MATLAB-authored statistical cell matrix from explicit backend column-count metadata.
   * Syntax: statisticalTableMatrix(tables,name).
   * Inputs: Canonical tables payload and one table field name.
   * Outputs: Row-major browser matrix preserving every cell value and the backend-declared column count.
   * Authority and flow: NMResultsViewerCrossAnalysisTools.statisticalTables owns dimensions; this browser helper only reverses MATLAB JSON's column-major flattening when nested rows were not retained.
   * Scientific/state contract: No statistic, label, order, or numeric value is inferred or recalculated.
   * Invariants: Already nested matrices pass through unchanged; flat payloads require an exact positive column count and divisible cell count.
   * Materialization and performance: O(cells) compact presentation/export reshaping only; no service, file, or scientific materialization.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained rendering and explicit export of an already-materialized statistical payload.
   * Failure semantics: Missing/inconsistent dimension metadata throws explicitly instead of displaying a malformed one-column table.
   * Side effects: None.
   * Consumers and dependencies: Statistical HTML, visual-table capture and CSV/XLSX export.
  */
  function statisticalTableMatrix(tables,name){const raw=arr(tables&&tables[name]);if(!raw.length)return[];if(raw.every(Array.isArray))return raw.map(arr);const cols=Number(tables&&tables.columnCounts&&tables.columnCounts[name]);if(!Number.isInteger(cols)||cols<1||raw.length%cols!==0)throw new Error(`Statistical table ${name} has no valid backend column dimensions.`);const rows=raw.length/cols;return Array.from({length:rows},(_,r)=>Array.from({length:cols},(_,c)=>raw[c*rows+r]));}

  /**
   * Purpose: Select the already-materialized two-column numerical table belonging to one statistical summary panel.
   * Syntax: statisticalTableCells(id).
   * Inputs: Omnibus or pairwise panel identity plus resident statisticalResult tables.
   * Outputs: Row-major cell matrix reconstructed by statisticalTableMatrix.
   * Authority and flow: Backend table names and dimensions remain authoritative; this helper performs only the fixed panel-to-table mapping.
   * Scientific/state contract: No statistic, label, numeric value, significance result, or ordering is recomputed.
   * Invariants: Omnibus maps only to testSummary and pairwise only to postHoc; unknown panels return an empty matrix.
   * Materialization and performance: O(cells) compact resident-table projection.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for retained rendering and explicit export; it issues no service request.
   * Failure semantics: Invalid backend dimension metadata propagates from statisticalTableMatrix.
   * Side effects: None.
   * Consumers and dependencies: Statistical HTML and statisticalTableVisualArtifact.
   */
  function statisticalTableCells(id){const tables=STATE.statisticalResult&&STATE.statisticalResult.tables||{},name=id==='omnibus'?'testSummary':id==='pairwise'?'postHoc':'';return name?statisticalTableMatrix(tables,name):[];}

  /**
   * Purpose: Capture the visible omnibus or pairwise table as the same generic SVG artifact used by the standard panel export dialog.
   * Syntax: statisticalTableVisualArtifact(id).
   * Inputs: Statistical table panel identity and its resident backend-authored cell matrix.
   * Outputs: NMResultsViewerOutput SVG artifact with table cells, title and analysis-set provenance.
   * Authority and flow: statisticalTableCells owns table selection; NMResultsViewerOutput.fromSvg owns the artifact boundary.
   * Scientific/state contract: Capture reproduces supplied cells and does not calculate or transform statistics.
   * Invariants: Column count is the maximum resident row width; the header is the first backend row.
   * Materialization and performance: O(cells) compact SVG geometry for an explicit export action.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Invoked only from the user-facing export action over retained statistical state.
   * Failure semantics: Missing cells or output authority throws an explicit error.
   * Side effects: Creates and returns an in-memory artifact only; writing remains delegated.
   * Consumers and dependencies: statisticalVisualArtifact and the generic Results Viewer export dialog.
   */
  function statisticalTableVisualArtifact(id){const cells=statisticalTableCells(id);if(!cells.length)throw new Error('No rendered statistical table is available for this panel.');const cols=Math.max(...cells.map(row=>row.length),1),W=920,titleH=38,rowH=30,H=titleH+rowH*cells.length+12,colW=W/cols,title=id==='omnibus'?'Omnibus statistics':'Pairwise statistics';let body=`<rect width="${W}" height="${H}" fill="#ffffff"/><text x="12" y="24" font-family="Arial,Helvetica,sans-serif" font-size="15" font-weight="700" fill="#1e293b">${title}</text>`;cells.forEach((row,ri)=>{for(let ci=0;ci<cols;ci++){const x=ci*colW,y=titleH+ri*rowH,header=ri===0,value=ci<row.length?row[ci]:'';body+=`<rect x="${x.toFixed(1)}" y="${y}" width="${colW.toFixed(1)}" height="${rowH}" fill="${header?'#e8eef6':'#ffffff'}" stroke="#cbd5e1"/><text x="${(x+7).toFixed(1)}" y="${y+19}" font-family="Arial,Helvetica,sans-serif" font-size="10"${header?' font-weight="700"':''} fill="#1e293b">${esc(value)}</text>`;}});const svg=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}">${body}</svg>`,output=global.NMResultsViewerOutput;if(!output||typeof output.fromSvg!=='function')throw new Error('The generic Results Viewer SVG output API is unavailable.');return output.fromSvg(svg,{representationId:`cross_analysis.statistical.${id}`,captureVariant:'current',title,width:W,height:H,provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices()}});}

  /**
   * Purpose: Capture the current rendered statistical plot panel, or delegate a statistical table panel to its table-specific visual capture.
   * Syntax: statisticalVisualArtifact(root,id).
   * Inputs: Current Cross-analysis DOM root and a fixed statistical panel identity.
   * Outputs: One generic SVG artifact containing every SVG shown in that panel and current presentation metadata.
   * Authority and flow: The live renderer owns plot geometry; this helper clones it without rebuilding scientific values, then delegates artifact creation to NMResultsViewerOutput.
   * Scientific/state contract: The captured SVG is the current view of the resident backend statistical artifact; no inference or FDR calculation occurs.
   * Invariants: Multiple SVGs retain their order and are stacked at a common width; table panels use statisticalTableVisualArtifact.
   * Materialization and performance: O(rendered SVG nodes) in-memory cloning on an explicit export action.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Explicit user export only; retained statistical state is consumed without rematerialization.
   * Failure semantics: Missing rendered SVG or output authority throws explicitly.
   * Side effects: Allocates detached DOM nodes and returns an artifact; no file is written here.
   * Consumers and dependencies: Statistical panel export binding and NMResultsViewerOutput.fromSvg.
   */
  function statisticalVisualArtifact(root,id){if(id==='omnibus'||id==='pairwise')return statisticalTableVisualArtifact(id);const panel=root.querySelector(`[data-cross-stat-panel="${id}"]`),nodes=panel?Array.from(panel.querySelectorAll('.rvCrossStatFigureSvg svg')):[];if(!nodes.length)throw new Error('No rendered SVG is available for this panel.');const ns='http://www.w3.org/2000/svg',outer=document.createElementNS(ns,'svg'),width=920,gap=18,dimensions=nodes.map(node=>{const values=String(node.getAttribute('viewBox')||'0 0 920 400').trim().split(/\s+/).map(Number);return {node,w:Number.isFinite(values[2])?values[2]:920,h:Number.isFinite(values[3])?values[3]:400};}),height=dimensions.reduce((sum,d)=>sum+d.h*width/d.w,0)+gap*Math.max(0,dimensions.length-1);outer.setAttribute('xmlns',ns);outer.setAttribute('viewBox',`0 0 ${width} ${Math.ceil(height)}`);const style=document.createElementNS(ns,'style');style.textContent='text{font-family:Arial,Helvetica,sans-serif}.rvPanelAxes line{stroke:#334155;stroke-width:1}.rvGridLine{stroke:#e2e8f0;stroke-width:1}.rvPanelTick line{stroke:#64748b}.rvPanelTick text{font-size:11px}.rvPanelAxisLabel{font-size:13px;font-weight:600}.rvCrossStatReference{stroke:#64748b;stroke-dasharray:5 4;opacity:.75}';outer.appendChild(style);const background=document.createElementNS(ns,'rect');background.setAttribute('width','100%');background.setAttribute('height','100%');background.setAttribute('fill','#ffffff');outer.appendChild(background);let y=0;dimensions.forEach(d=>{const clone=d.node.cloneNode(true),scaled=d.h*width/d.w;clone.setAttribute('x','0');clone.setAttribute('y',String(y));clone.setAttribute('width',String(width));clone.setAttribute('height',String(scaled));outer.appendChild(clone);y+=scaled+gap;});const output=global.NMResultsViewerOutput;if(!output||typeof output.fromSvg!=='function')throw new Error('The generic Results Viewer SVG output API is unavailable.');const titles={main:'Statistical performance comparison',intervals:'One-vs-one horizontal interval plot',reference:'Reference-model comparison'};return output.fromSvg(outer,{representationId:`cross_analysis.statistical.${id}`,captureVariant:'current',title:titles[id]||'Cross-analysis statistical plot',width,height:Math.ceil(height),metadata:{plotMode:STATE.statistical.plotMode,orderMode:STATE.orderMode,colormap:STATE.statistical.colormap,showHeatValues:STATE.statistical.showHeatValues!==false},provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices()}});}

  /**
   * Purpose: Project one backend statistical cell matrix into a named generic numerical export section.
   * Syntax: statisticalTableSection(title,tables,key).
   * Inputs: Presentation title, canonical tables payload and exact backend field key.
   * Outputs: Null for absent data or a title/columns/rows section retaining the supplied cells.
   * Authority and flow: statisticalTableMatrix owns dimension reconstruction; tableArtifactProjection owns generic column projection.
   * Scientific/state contract: No statistics, labels, ordering, or numerical values are calculated.
   * Invariants: The first row remains the header and all remaining rows retain backend order.
   * Materialization and performance: O(cells) compact in-memory table projection.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Safe for explicit export of retained statistical state; no service request occurs.
   * Failure semantics: Invalid dimension metadata propagates; an absent table returns null.
   * Side effects: None.
   * Consumers and dependencies: statisticalDataArtifact and generic table output.
   */
  function statisticalTableSection(title,tables,key){const matrix=statisticalTableMatrix(tables,key);if(!matrix.length)return null;const projected=tableArtifactProjection(matrix[0],matrix.slice(1));return {title,columns:projected.columns,rows:projected.rows};}

  /**
   * Purpose: Build the numerical companion artifact offered by the single statistical-panel export control.
   * Syntax: statisticalDataArtifact(id).
   * Inputs: Fixed panel identity plus the resident canonical statistical result/tables.
   * Outputs: Generic table artifact containing only the numerical sections belonging to that panel.
   * Authority and flow: Backend statisticalTables owns all values and dimensions; NMResultsViewerOutput.table owns the artifact schema and downstream CSV/TSV/XLSX writing.
   * Scientific/state contract: Export never recomputes inference, pairwise deltas, corrected p values, aliases, or analysis identity.
   * Invariants: Each panel maps to a fixed table-field list and preserves analysis-set provenance.
   * Materialization and performance: O(exported cells) compact artifact projection on explicit user action.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Interactive/retained use: Explicit user export only; it consumes retained statistical state without rematerialization.
   * Failure semantics: Missing result, sections, or output authority throws an explicit error.
   * Side effects: Returns an in-memory artifact; generic output code performs any later file write.
   * Consumers and dependencies: Statistical panel export binding and NMResultsViewerOutput.table.
   */
  function statisticalDataArtifact(id){const result=STATE.statisticalResult;if(!result||result.ok===false)throw new Error('Generate the statistical comparison before exporting data.');const tables=result.tables||{},names=id==='main'?[['Performance summaries','plotSummary'],['One-vs-all summaries','oneVsAllSummary'],['One-vs-one summaries','oneVsOneSummary'],['FDR matrix','fdrMatrix']]:id==='intervals'?[['One-vs-one summaries','oneVsOneSummary']]:id==='reference'?[['Reference comparisons','testSummary'],['Reference differences','referenceDifferences']]:id==='omnibus'?[['Omnibus statistics','testSummary']]:id==='pairwise'?[['Pairwise statistics','postHoc']]:[];const sections=names.map(([title,key])=>statisticalTableSection(title,tables,key)).filter(Boolean);if(!sections.length)throw new Error('No numerical table is available for this panel.');const output=global.NMResultsViewerOutput;if(!output||typeof output.table!=='function')throw new Error('The generic Results Viewer table output API is unavailable.');return output.table({representationId:`cross_analysis.statistical.${id}.data`,title:`Cross-analysis ${id} statistics`,columns:sections[0].columns,rows:sections[0].rows,tables:sections,metadataRows:[['Analysis indices',selectedIndices().join(', ')],['Optimization criterion',String(result.optimizationCriterion&&result.optimizationCriterion.label||result.optimizationCriterion||'')]],provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices(),scientificAnnotations:arr(result.scientificAnnotations)}});}

  /**
   * Purpose: Execute one statistical comparison through the MATLAB service after validating current queried analysis-set identity.
   * Syntax: generateStatistical(opts).
   * Inputs: Shared service/message/render callbacks and resident selector choices.
   * Outputs: Stores one canonical cross_analysis.statistical_comparison payload and updates selector defaults from its authoritative catalogue.
   * Authority and flow: Calls only results_viewer_cross_analysis_statistical_comparison; all scientific calculations remain server-side.
   * Scientific/state contract: No browser fallback statistic exists; stale selections are blocked before materialization.
   * Invariants: Multiple-reference state cannot be represented by the single select control.
   * Materialization and performance: One explicit MATLAB round trip and compact statistical payload hydration; no file/spatial work.
   * Resource declaration: Reads no files/resources and creates no feature-scale arrays.
   * Failure semantics: Service errors are shown through shared message and retained as failed statisticalResult.
   * Side effects: Updates module-local statistical state and DOM through render.
   * Consumers and dependencies: Statistical comparison action button.
   * Interactive/retained use: Presentation-only or explicit Generate behavior; no hidden retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   */
  async function generateStatistical(opts){if(STATE.statisticalBusy)return;const eligibility=statisticalEligibility();if(!eligibility.ok){opts.setMessage(eligibility.message,'warn');return;}STATE.statisticalBusy=true;render(opts);try{const spec=requestOverrides('statistical');delete spec.metricIds;const out=await opts.matlabService({operation:'results_viewer_cross_analysis_statistical_comparison',spec});if(!out||out.ok===false)throw new Error(out&&out.message||'Statistical comparison request failed.');STATE.statisticalResult=out.payload||{};const o=STATE.statisticalResult.selectorOptions||{};STATE.statistical.targetIndex=Number(o.selectedTargetIndex);STATE.statistical.modelSource=String(o.selectedModelSource||'');STATE.statistical.classifierIndex=Number(o.selectedClassifierIndex);STATE.statistical.referenceAnalysisIndex=Number(STATE.statisticalResult.referenceAnalysisIndex||0);}catch(err){STATE.statisticalResult={ok:false,message:err&&err.message?err.message:String(err)};opts.setMessage(`Statistical comparison failed: ${STATE.statisticalResult.message}`,'danger');}finally{STATE.statisticalBusy=false;render(opts);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}}

  /**
   * Purpose: Render and control the legacy descriptive Visual Comparator from one canonical backend aggregate-performance payload.
   * Interactive/retained use: Runs only for explicit Visual comparison display/Generate actions and introduces no hidden scientific rematerialization.
   * Syntax: visualPanelHtml().
   * Inputs: Resident visualResult plus presentation-only metric/sort/line/right-axis/color state.
   * Outputs: Selector controls, metric controls, descriptive SVG and numerical table.
   * Authority and flow: Scientific values and selector catalogues originate only from cross_analysis.visual_comparison; browser work is limited to display selection, ordering and SVG geometry.
   * Scientific/state contract: No metric formula, matched-CV operation or inferential statistic exists in this renderer.
   * Invariants: Classification retains the legacy 17 measures; regression metric identities come from the backend Model Performance rows; bar/line/sort/separate-axis/colors are presentation state only.
   * Materialization and performance: O(A*M) over compact backend metric values; no files/resources or feature-scale arrays.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing/failed backend payload is shown explicitly; invalid presentation selections are normalized to resident metric options.
   * Side effects: Returns markup only.
   * Consumers and dependencies: activePanelHtml/bindControls/generateVisual.
   */
  function visualPanelHtml(){
    const r=STATE.visualResult;
    if(!r)return `<div class="rvCrossFunctionPanel"><h3>Visual comparison</h3><p class="rvHelpText">Compares aggregate OOT performance measures across the queried analyses. Classification retains the legacy measure catalogue; regression uses the measures exposed by Model Performance. This is descriptive only: it does not require CV-equivalent folds and does not run a statistical test.</p><div class="rvCrossActions"><button id="rvCrossVisualGenerate" type="button" class="primary"${STATE.visualBusy||!selectionMatchesInventory()?' disabled':''}>${STATE.visualBusy?'Generating…':'Generate visual comparison'}</button></div></div>`;
    if(r.ok===false)return `<div class="rvCrossFunctionPanel"><h3>Visual comparison</h3><div class="rvCrossActions"><button id="rvCrossVisualGenerate" type="button" class="primary"${STATE.visualBusy||!selectionMatchesInventory()?' disabled':''}>Retry</button></div><div class="rvPanelNotice warn">${esc(r.message||'Visual comparison unavailable.')}</div></div>`;
    const o=r.selectorOptions||{},targets=arr(o.targets),sources=arr(o.modelSources),classifiers=arr(o.classifiers),modes=arr(o.multiClassModes),metrics=arr(r.metricOptions);
    const opts=(xs,value,key,label)=>xs.map(x=>`<option value="${esc(x[key])}"${String(x[key])===String(value)?' selected':''}>${esc(x[label]||x[key])}</option>`).join('');
    const modeControl=modes.length?`<label>Class contrast<select id="rvCrossVisualMode">${opts(modes,STATE.visual.multiClassModeIndex,'index','label')}</select></label>`:'';
    const targetControl=targets.length>1?`<label>Target<select id="rvCrossVisualTarget">${opts(targets,STATE.visual.targetIndex,'resultIndex','label')}</select></label>`:'';
    const controls=`<div class="rvCrossOptions">${targetControl}<label>First analysis · Model source<select id="rvCrossVisualSource">${opts(sources,STATE.visual.modelSource,'id','label')}</select></label><label>First analysis · Classifier/model<select id="rvCrossVisualClassifier">${opts(classifiers,STATE.visual.classifierIndex,'index','label')}</select></label>${modeControl}<label>Plot<select id="rvCrossVisualPlotMode"><option value="bar"${STATE.visual.plotMode==='bar'?' selected':''}>Bar plots</option><option value="line"${STATE.visual.plotMode==='line'?' selected':''}>Line plots</option></select></label></div>`;
    const metricControls=`<div class="rvCrossMetricControls"><div class="rvCrossSectionHead"><strong>Performance measures</strong><span>${STATE.visual.plotMode==='line'?'Right axis may be assigned per measure.':'Grouped bars use one axis.'}</span></div><div class="rvCrossVisualMetricGrid">${metrics.map((m,i)=>{const id=String(m.id),selected=STATE.visual.metricIds.has(id),right=STATE.visual.separateAxis.has(id),color=STATE.visual.colors.get(id)||VISUAL_DEFAULT_COLORS[i%VISUAL_DEFAULT_COLORS.length];return `<div class="rvCrossVisualMetricRow"><label><input type="checkbox" data-cross-visual-metric="${esc(id)}"${selected?' checked':''}> ${esc(m.label||id)}</label><input type="color" data-cross-visual-color="${esc(id)}" value="${esc(color)}" title="Series colour"><label class="rvCrossVisualRightAxis"><input type="checkbox" data-cross-visual-axis="${esc(id)}"${right?' checked':''}${STATE.visual.plotMode==='line'&&selected?'':' disabled'}> Right axis</label></div>`;}).join('')}</div></div>`;
    const table=visualSelectedTable(r),body=table.rows.map(row=>`<tr>${row.map((v,j)=>`<td>${j>=2&&Number.isFinite(Number(v))?esc(Number(v).toPrecision(5)):esc(v)}</td>`).join('')}</tr>`).join('');
    return `<div class="rvCrossFunctionPanel"><h3>Visual comparison</h3>${controls}<div class="rvCrossActions"><button id="rvCrossVisualGenerate" type="button" class="primary"${STATE.visualBusy||!selectionMatchesInventory()?' disabled':''}>${STATE.visualBusy?'Generating…':'Refresh scientific context'}</button><button id="rvCrossVisualExport" type="button"${STATE.visual.metricIds.size?'':' disabled'}>Export CSV/XLSX</button></div>${metricControls}<div class="rvCrossTableMeta"><span>${esc(r.message||'')}</span><span>Aggregate OOT source: CV · no CV-equivalence restriction</span></div><div class="rvCrossVisualPlot">${visualPlotSvg(r)}</div><div class="rvCrossTableScroll"><table class="rvCrossPerformanceTable"><thead><tr>${table.header.map(h=>`<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${body||'<tr><td>No selected performance measures.</td></tr>'}</tbody></table></div></div>`;
  }

  /** Visual Comparator palette is presentation-only and stable across retained renders. */
  /**
   * Purpose: Project currently selected visual metrics from the canonical backend matrix without recomputing values.
   * Interactive/retained use: Runs only for explicit Visual comparison display/Generate actions and introduces no hidden scientific rematerialization.
   * Syntax: visualSelectedTable(result).
   * Inputs: cross_analysis.visual_comparison result and presentation metric selection.
   * Outputs: Header/rows/metric positions for plot and export.
   * Authority and flow: Exact columns are selected from result.values/result.metricOptions.
   * Scientific/state contract: Values are unchanged backend Model Performance values.
   * Invariants: Analysis row order remains backend order before optional plot-only sorting.
   * Materialization and performance: O(A*M) compact array projection.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Unknown metric ids are ignored; empty selection yields analysis columns only.
   * Side effects: None.
   * Consumers and dependencies: visualPanelHtml, visualPlotSvg and visualTableArtifact.
   */
  function visualSelectedTable(r){const options=arr(r&&r.metricOptions),ids=Array.from(STATE.visual.metricIds).filter(id=>options.some(m=>String(m.id)===id)),pos=ids.map(id=>options.findIndex(m=>String(m.id)===id)),labels=ids.map(id=>String(options.find(m=>String(m.id)===id).label||id)),vals=arr(r&&r.values).map(arr),analysis=arr(r&&r.analysisLabels),indices=arr(r&&r.selectedAnalysisIndices),backendDisplay=arr(r&&r.analysisDisplayLabels),display=analysis.map((a,i)=>String(STATE.aliases.get(Number(indices[i]))||backendDisplay[i]||a));return {ids,pos,labels,header:['Analysis','Alias'].concat(labels),rows:analysis.map((a,i)=>[a,display[i]||a].concat(pos.map(j=>Number(vals[i]&&vals[i][j])))),values:analysis.map((a,i)=>pos.map(j=>Number(vals[i]&&vals[i][j]))),analysis,display};}

  /**
   * Purpose: Draw grouped bars or line series using only canonical aggregate performance values.
   * Interactive/retained use: Runs only for explicit Visual comparison display/Generate actions and introduces no hidden scientific rematerialization.
   * Syntax: visualPlotSvg(result).
   * Inputs: Backend result plus presentation state.
   * Outputs: Inline SVG.
   * Authority and flow: Sorting, colours and right-axis placement are legacy presentation semantics; scientific values are never transformed except coordinate scaling.
   * Scientific/state contract: No performance or inferential calculation is performed.
   * Invariants: Sort is ascending by mean of selected displayed measures, matching legacy Visual Comparator behavior.
   * Materialization and performance: O(A*M) SVG geometry.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Empty selected metrics/finite values yields a notice.
   * Side effects: None.
   * Consumers and dependencies: visualPanelHtml; consumes visualSelectedTable and resident presentation state only.
   */
  function visualPlotSvg(r){
    const aggregate=r&&r.type==='aggregate_performance';
    const t=aggregate?{ids:arr(r.metricIds),labels:arr(r.metricLabels),analysis:arr(r.displayLabels),
      display:arr(r.displayLabels),values:arr(r.values).map(row=>arr(row).map(v=>v===null?NaN:Number(v)))}:visualSelectedTable(r);
    if(!t.ids.length)return '<div class="rvPanelNotice">Select at least one performance measure.</div>';
    const mode=aggregate?r.plotMode:STATE.visual.plotMode;
    const separate=aggregate?new Set(arr(r.separateAxisMetricIds)):STATE.visual.separateAxis;
    const colors=aggregate?new Map(arr(r.metricColors).map(c=>[String(c.metricId),String(c.color)])):STATE.visual.colors;
    let order=t.analysis.map((_,i)=>i);
    if(!aggregate&&(STATE.orderMode==='ascending'||STATE.orderMode==='descending'))order.sort((a,b)=>{
      const mean=i=>{const v=t.values[i].filter(Number.isFinite);return v.length?v.reduce((x,y)=>x+y,0)/v.length:NaN;};
      const av=mean(a),bv=mean(b);if(!Number.isFinite(av)||!Number.isFinite(bv))return Number.isFinite(av)?-1:Number.isFinite(bv)?1:a-b;
      const delta=av-bv;return (STATE.orderMode==='descending'?-delta:delta)||(a-b);
    });
    const vals=order.map(i=>t.values[i]),labs=order.map(i=>t.display[i]||t.analysis[i]);
    const learning=aggregate&&arr(r.bandLower).length>0;
    const lower=learning?arr(r.bandLower).map(v=>v===null?NaN:Number(v)):[];
    const upper=learning?arr(r.bandUpper).map(v=>v===null?NaN:Number(v)):[];
    const W=aggregate&&r.numericXAxis?1080:920,H=learning?456:440,m=learning?{l:64,r:16,t:12,b:62}:{l:72,r:72,t:28,b:118};
    const pw=W-m.l-m.r,ph=H-m.t-m.b,labelPlan=categoricalTickPlan(labs,pw,9);
    const rightMask=t.ids.map(id=>mode==='line'&&separate.has(id));
    const finite=mask=>vals.flatMap(row=>row.filter((v,j)=>mask(j)&&Number.isFinite(v)));
    const lim=a=>{if(!a.length)return[0,1];let lo=learning?Math.min(...a):Math.min(0,...a),hi=learning?Math.max(...a):Math.max(0,...a);
      if(!(hi>lo)){const pad=Math.max(.5,Math.abs(lo)*.03);lo-=pad;hi+=pad;}
      else if(learning){const pad=(hi-lo)*.12;lo-=pad;hi+=pad;}return[lo,hi];};
    const leftRange=finite(j=>!rightMask[j]);
    if(learning){leftRange.push(...lower.filter(Number.isFinite),...upper.filter(Number.isFinite));}
    const leftLim=lim(leftRange),rightLim=lim(finite(j=>rightMask[j]));
    const y=(v,L)=>m.t+(L[1]-v)/(L[1]-L[0])*ph;
    const x=i=>m.l+(aggregate?(learning?.025+.95*Number(r.xPositions[order[i]]):Number(r.xPositions[order[i]])):(i+.5)/Math.max(1,labs.length))*pw;
    let body=`<rect x="${m.l}" y="${m.t}" width="${pw}" height="${ph}" fill="none" stroke="currentColor" opacity=".25"/>`;
    if(learning)for(let k=0;k<=4;k++){const yy=m.t+k*ph/4;body+=`<line x1="${m.l}" y1="${yy.toFixed(1)}" x2="${m.l+pw}" y2="${yy.toFixed(1)}" stroke="currentColor" opacity=".12"/>`;}
    if(learning&&mode==='line'&&lower.length===vals.length&&upper.length===vals.length){
      let segment=[];
      const flush=()=>{if(segment.length<2){segment=[];return;}
        const upperPts=segment.map(i=>`${x(i).toFixed(1)},${y(upper[order[i]],leftLim).toFixed(1)}`);
        const lowerPts=segment.slice().reverse().map(i=>`${x(i).toFixed(1)},${y(lower[order[i]],leftLim).toFixed(1)}`);
        const c=colors.get(t.ids[0])||VISUAL_DEFAULT_COLORS[0];
        body+=`<polygon points="${upperPts.concat(lowerPts).join(' ')}" fill="${esc(c)}" fill-opacity=".20" stroke="none"/>`;segment=[];};
      vals.forEach((row,i)=>{if(Number.isFinite(row[0])&&Number.isFinite(lower[order[i]])&&Number.isFinite(upper[order[i]]))segment.push(i);else flush();});flush();
    }
    if(mode==='bar'){
      const slot=pw/Math.max(1,labs.length),bw=slot*.76/Math.max(1,t.ids.length),z=y(0,leftLim);
      vals.forEach((row,i)=>row.forEach((v,j)=>{if(!Number.isFinite(v))return;
        const xx=m.l+i*slot+slot*.12+j*bw,yy=y(v,leftLim),c=colors.get(t.ids[j])||VISUAL_DEFAULT_COLORS[j%VISUAL_DEFAULT_COLORS.length];
        body+=`<rect x="${xx.toFixed(1)}" y="${Math.min(z,yy).toFixed(1)}" width="${Math.max(1,bw*.9).toFixed(1)}" height="${Math.max(1,Math.abs(z-yy)).toFixed(1)}" fill="${esc(c)}"><title>${esc(labs[i])} · ${esc(t.labels[j])}: ${esc(v)}</title></rect>`;}));
    }else t.ids.forEach((id,j)=>{
      const c=colors.get(id)||VISUAL_DEFAULT_COLORS[j%VISUAL_DEFAULT_COLORS.length];let pts=[];
      const flush=()=>{if(pts.length)body+=`<polyline points="${pts.join(' ')}" fill="none" stroke="${esc(c)}" stroke-width="2.5"/>`;pts=[];};
      vals.forEach((row,i)=>{const v=row[j];if(Number.isFinite(v))pts.push(`${x(i).toFixed(1)},${y(v,rightMask[j]?rightLim:leftLim).toFixed(1)}`);else if(learning)flush();});flush();
      vals.forEach((row,i)=>{const v=row[j];if(Number.isFinite(v))body+=`<circle cx="${x(i).toFixed(1)}" cy="${y(v,rightMask[j]?rightLim:leftLim).toFixed(1)}" r="3.5" fill="${esc(c)}"><title>${esc(labs[i])} · ${esc(t.labels[j])}: ${esc(v)}</title></circle>`;});
    });
    for(let k=0;k<=4;k++){const frac=k/4,v=leftLim[0]+frac*(leftLim[1]-leftLim[0]),yy=y(v,leftLim);
      body+=`<line x1="${m.l-4}" y1="${yy.toFixed(1)}" x2="${m.l}" y2="${yy.toFixed(1)}" stroke="currentColor" opacity=".55"/><text x="${m.l-7}" y="${(yy+3).toFixed(1)}" text-anchor="end" font-size="11">${esc(Number(v).toPrecision(3))}</text>`;}
    if(rightMask.some(Boolean))for(let k=0;k<=4;k++){const frac=k/4,v=rightLim[0]+frac*(rightLim[1]-rightLim[0]),yy=y(v,rightLim),xx=m.l+pw;
      body+=`<line x1="${xx}" y1="${yy.toFixed(1)}" x2="${xx+4}" y2="${yy.toFixed(1)}" stroke="currentColor" opacity=".55"/><text x="${xx+7}" y="${(yy+3).toFixed(1)}" text-anchor="start" font-size="9">${esc(Number(v).toPrecision(3))}</text>`;}
    labs.forEach((full,i)=>{const xx=x(i).toFixed(1),yy=m.t+ph+18,label=labelPlan.labels[i];
      if(label)body+=labelPlan.angle===0?`<text x="${xx}" y="${yy}" text-anchor="middle" font-size="11">${esc(label)}<title>${esc(full)}</title></text>`:`<text x="${xx}" y="${yy}" text-anchor="end" font-size="9" transform="rotate(${labelPlan.angle} ${xx} ${yy})">${esc(label)}<title>${esc(full)}</title></text>`;});
    if(!learning){let lx=m.l;t.ids.forEach((id,j)=>{const c=colors.get(id)||VISUAL_DEFAULT_COLORS[j%VISUAL_DEFAULT_COLORS.length],tag=rightMask[j]?' (right axis)':'';
      body+=`<rect x="${lx}" y="${H-25}" width="10" height="10" fill="${esc(c)}"/><text x="${lx+14}" y="${H-16}" font-size="9">${esc(t.labels[j]+tag)}</text>`;lx+=Math.max(115,(t.labels[j].length+tag.length)*6+30);});}
    body+=`<text x="16" y="${m.t+ph/2}" transform="rotate(-90 16 ${m.t+ph/2})" text-anchor="middle" font-size="12">${esc(aggregate?r.yLabel:'Performance Measure(s)')}</text><text x="${m.l+pw/2}" y="${H-(learning?20:58)}" text-anchor="middle" font-size="12">${esc(aggregate?r.xLabel:'Analyses')}</text>`;
    return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(aggregate?r.yLabel:'Cross-analysis visual comparison')}">${body}</svg>`;
  }

  /**
   * Purpose: Build a generic numeric export artefact from the resident Visual Comparator values.
   * Syntax: visualTableArtifact().
   * Inputs: Current visual result and presentation metric selection.
   * Outputs: NMResultsViewerOutput table artefact.
   * Authority and flow: Exports exact backend aggregate values; generic Results Viewer output remains the writer authority.
   * Scientific/state contract: No metric calculation occurs in export.
   * Invariants: Analysis identity/provenance are retained separately from aliases.
   * Materialization and performance: O(A*M) compact table projection.
   * Resource declaration: Reads no files directly, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; file writing is delegated to the output authority.
   * Failure semantics: Missing result/metric selection fails explicitly.
   * Side effects: None until delegated export is invoked by the caller.
   * Consumers and dependencies: direct Visual Comparator export action and the generic NMResultsViewerOutput table authority.
   */
  function visualTableArtifact(){if(!STATE.visualResult||STATE.visualResult.ok===false)throw new Error('Generate the visual comparison before exporting it.');const table=visualSelectedTable(STATE.visualResult);if(!table.ids.length)throw new Error('Select at least one performance measure before exporting.');const output=global.NMResultsViewerOutput;if(!output)throw new Error('The generic Results Viewer table output API is unavailable.');const artifactTable=tableArtifactProjection(table.header,table.rows);return output.table({representationId:'cross_analysis.visual_comparison',title:'Cross-analysis visual comparison',columns:artifactTable.columns,rows:artifactTable.rows,metadataRows:[['Analysis indices',selectedIndices().join(', ')],['Result source','cv'],['Metrics',table.labels.join(' · ')]],provenance:{scientificStateScope:'analysis_set',analysisIndices:selectedIndices(),scientificAnnotations:arr(STATE.visualResult.scientificAnnotations)}});}

  /**
   * Purpose: Explicitly materialize the Visual Comparator scientific context through MATLAB.
   * Interactive/retained use: Runs only for explicit Visual comparison display/Generate actions and introduces no hidden scientific rematerialization.
   * Syntax: generateVisual(opts).
   * Inputs: Shared MATLAB/message/render callbacks and resident selector/presentation state.
   * Outputs: Stores one canonical cross_analysis.visual_comparison payload.
   * Authority and flow: Calls only results_viewer_cross_analysis_visual_comparison; browser supplies presentation selections but computes no scientific value.
   * Scientific/state contract: Current queried analysis_set identity is mandatory; no CV-equivalence condition is imposed in JavaScript.
   * Invariants: Result metric selection is normalized from backend common metric options.
   * Materialization and performance: One explicit compact MATLAB round trip.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays in browser.
   * Failure semantics: Service failure remains explicit in visualResult/shared message.
   * Side effects: Updates module-local visual state and rerenders.
   * Consumers and dependencies: Visual comparison Generate action, MATLAB service boundary and visualPanelHtml.
   */
  async function generateVisual(opts){if(STATE.visualBusy)return;if(!selectionMatchesInventory()){opts.setMessage('Query the selected analysis set before visual comparison.','warn');return;}if(selectedIndices().length<2){opts.setMessage('Select at least two completed analyses.','warn');return;}STATE.visualBusy=true;render(opts);try{const spec=requestOverrides('visual');delete spec.metricIds;const out=await opts.matlabService({operation:'results_viewer_cross_analysis_visual_comparison',spec});if(!out||out.ok===false)throw new Error(out&&out.message||'Visual comparison request failed.');STATE.visualResult=out.payload||{};const o=STATE.visualResult.selectorOptions||{};STATE.visual.targetIndex=Number(o.selectedTargetIndex);STATE.visual.modelSource=String(o.selectedModelSource||'');STATE.visual.classifierIndex=Number(o.selectedClassifierIndex);STATE.visual.multiClassModeIndex=o.selectedMultiClassModeIndex===null?null:Number(o.selectedMultiClassModeIndex);STATE.visual.metricIds=new Set(arr(STATE.visualResult.selectedMetricIds).map(String));arr(STATE.visualResult.metricOptions).forEach((m,i)=>{const id=String(m.id);if(!STATE.visual.colors.has(id))STATE.visual.colors.set(id,VISUAL_DEFAULT_COLORS[i%VISUAL_DEFAULT_COLORS.length]);});}catch(err){STATE.visualResult={ok:false,message:err&&err.message?err.message:String(err)};opts.setMessage(`Visual comparison failed: ${STATE.visualResult.message}`,'danger');}finally{STATE.visualBusy=false;render(opts);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}}

  /**
   * Purpose: Render the active Cross-analysis function panel while reusing one analysis-set selector above it.
   * Syntax: activePanelHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function activePanelHtml(payload){
    if(STATE.activeTab==='statistical')return statisticalPanelHtml(payload);
    if(STATE.activeTab==='visual')return visualPanelHtml();
    return `<div class="rvCrossFunctionPanel"><div class="rvCrossOptions"><label>Result source<select id="rvCrossSource">${sourceOptionsHtml(payload)}</select></label><button type="button" id="rvCrossOpenBatch"${selectionMatchesInventory()&&resultSpaceMatrix(payload).shared.size?'':' disabled'}>OOCV matrix / batch export</button></div><div class="rvCrossActions"><button id="rvCrossGenerate" type="button" class="primary"${STATE.busy||!selectionMatchesInventory()?' disabled':''}>${STATE.busy?'Generating…':'Generate performance table'}</button><button id="rvCrossExportTable" type="button"${STATE.result&&STATE.result.ok!==false&&STATE.metricIds.size?'':' disabled'}>Export CSV/XLSX</button></div><div id="rvCrossResult" class="rvCrossResult">${resultHtml()}</div></div>`;
  }

  /**
   * Purpose: Render the complete workspace shell and the shared analysis-set selector mount.
   * Syntax: shellHtml(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function shellHtml(payload){
    return `<div class="rvCrossAnalysisShell"><div class="rvCrossToolbar"><div class="rvCrossTabs" role="tablist"><button type="button" data-cross-tab="performance" class="${STATE.activeTab==='performance'?'isActive':''}" aria-selected="${STATE.activeTab==='performance'}">Performance table</button><button type="button" data-cross-tab="statistical" class="${STATE.activeTab==='statistical'?'isActive':''}" aria-selected="${STATE.activeTab==='statistical'}">Statistical comparison</button><button type="button" data-cross-tab="visual" class="${STATE.activeTab==='visual'?'isActive':''}" aria-selected="${STATE.activeTab==='visual'}">Visual comparison</button></div></div><div id="rvCrossAnalysisSetSelector"></div>${crossAnalysisToolsHtml(payload)}<div id="rvCrossFunctionPanel">${activePanelHtml(payload)}</div>${batchModalHtml(payload,resultSpaceMatrix(payload))}</div>`;
  }

  /**
   * Purpose: Bind source, alias, metric, tab and action controls after each deterministic render.
   * Syntax: bindControls(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function bindControls(root,opts,payload){
    const selectorHost=root.querySelector('#rvCrossAnalysisSetSelector'),selector=global.NMResultsViewerAnalysisSetSelector;
    if(selector&&selectorHost)selector.render({host:selectorHost,analyses:completedAnalyses(payload),selectedIndices:selectedIndices(),scientificState:STATE.inventoryState,busy:STATE.inventoryBusy,stale:!!STATE.inventoryState&&!selectionMatchesInventory(),sharedOocvIndices:resultSpaceMatrix(payload).shared,onSelectionChange:indices=>updateSelection(indices,payload,opts),onQuery:()=>queryAnalysisSet(opts)});
    root.querySelectorAll('[data-cross-tab]').forEach(node=>node.addEventListener('click',()=>{STATE.activeTab=String(node.dataset.crossTab||'performance');render(opts);}));
    const matrix=resultSpaceMatrix(payload);
    const openBatch=root.querySelector('#rvCrossOpenBatch');if(openBatch)openBatch.addEventListener('click',()=>{STATE.batchModalOpen=true;STATE.batchMessage='';render(opts);});
    root.querySelectorAll('[data-batch-close]').forEach(button=>button.addEventListener('click',()=>{STATE.batchModalOpen=false;render(opts);}));
    const gridHost=root.querySelector('#rvCrossBatchGrid');
    if(gridHost){
      // Scientific eligibility and descriptions come solely from the backend source catalogue.
      const analyses=completedAnalyses(payload);
      const availability=matrix.indices.map(idx=>matrix.columns.map(source=>matrix.byAnalysis.get(idx).has(source.id)));
      const selection=matrix.indices.map((idx,i)=>matrix.columns.map((source,j)=>availability[i][j]&&STATE.batchCells.has(batchCellKey(idx,source.id))));
      const titles=matrix.indices.map(idx=>{
        const analysis=analyses.find(row=>analysisIndex(row)===idx);
        const name=String(analysis.title||analysis.id||`Analysis ${idx}`);
        return matrix.columns.map(source=>{
          const option=matrix.byAnalysis.get(idx).get(source.id);
          return option?`Analysis ${idx}: ${name} | ${source.id}: ${option.label}`:`Analysis ${idx}: ${name} | ${source.id}: no stored performance result`;
        });
      });
      const picker=global.NMRuntimeGridPicker.create(gridHost,{
        ix:matrix.indices.length,jx:matrix.columns.length,GridAct:selection,enabledMask:availability,
        cellTitles:titles,requireAny:false,readOnly:STATE.batchBusy,
        rowLabels:matrix.indices.map(idx=>`Analysis ${idx}`),
        columnLabels:matrix.columns.map(source=>`${source.id==='cv'?'CV':source.id.replace('oocv:','OOCV ')} (${matrix.participants.get(source.id).length}/${matrix.indices.length})`)
      },{onChange:G=>{
        STATE.batchCells=new Set(G.flatMap((row,i)=>row.flatMap((checked,j)=>checked?[batchCellKey(matrix.indices[i],matrix.columns[j].id)]:[])));
        STATE.batchMessage='';
        const n=STATE.batchCells.size;
        root.querySelector('[data-batch-count]').textContent=`${n} selected result${n===1?'':'s'}`;
        root.querySelector('[data-batch-export]').disabled=!n||!STATE.metricIds.size;
        root.querySelector('[data-batch-status]').textContent='';
      }});
      const shared=root.querySelector('[data-batch-shared]');
      if(shared)shared.addEventListener('click',()=>picker.applyAction({action:'setMatrix',GridAct:matrix.indices.map(idx=>matrix.columns.map(source=>source.id!=='cv'&&matrix.participants.get(source.id).length>=2&&matrix.byAnalysis.get(idx).has(source.id)))}));
    }
    const batchExport=root.querySelector('[data-batch-export]');
    if(batchExport)batchExport.addEventListener('click',()=>{exportBatch(opts,payload).catch(err=>{STATE.batchMessage=`Batch export failed: ${err.message||String(err)}`;STATE.batchBusy=false;render(opts);});});
    const aliasEditor=root.querySelector('.rvCrossAliases');if(aliasEditor)aliasEditor.addEventListener('toggle',()=>{STATE.aliasEditorOpen=!!aliasEditor.open;});
    root.querySelectorAll('[data-cross-analysis-alias]').forEach(node=>{node.addEventListener('input',()=>{STATE.aliases.set(Number(node.dataset.crossAnalysisAlias),String(node.value||''));});node.addEventListener('change',()=>render(opts));});
    const crossOrder=root.querySelector('#rvCrossOrder');if(crossOrder)crossOrder.addEventListener('change',()=>{STATE.orderMode=String(crossOrder.value||'original');render(opts);});
    const source=root.querySelector('#rvCrossSource');if(source)source.addEventListener('change',()=>{STATE.source=String(source.value||'cv');STATE.result=null;STATE.metricIds=new Set();render(opts);});
    root.querySelectorAll('[data-cross-metric]').forEach(node=>node.addEventListener('change',()=>{const id=String(node.dataset.crossMetric||'');if(node.checked)STATE.metricIds.add(id);else STATE.metricIds.delete(id);render(opts);}));
    root.querySelectorAll('[data-cross-metric-bulk]').forEach(node=>node.addEventListener('click',()=>{STATE.metricIds=new Set(String(node.dataset.crossMetricBulk)==='all'?arr(STATE.result&&STATE.result.metricOptions).map(m=>String(m.id)):[]);render(opts);}));
    const generateButton=root.querySelector('#rvCrossGenerate');if(generateButton)generateButton.addEventListener('click',()=>generate(opts));
    const statGenerate=root.querySelector('#rvCrossStatGenerate');if(statGenerate)statGenerate.addEventListener('click',()=>generateStatistical(opts));
    const statTarget=root.querySelector('#rvCrossStatTarget');if(statTarget)statTarget.addEventListener('change',()=>{STATE.statistical.targetIndex=Number(statTarget.value);STATE.statisticalResult=null;render(opts);});
    const statSource=root.querySelector('#rvCrossStatSource');if(statSource)statSource.addEventListener('change',()=>{STATE.statistical.modelSource=String(statSource.value||'');STATE.statisticalResult=null;render(opts);});
    const statClassifier=root.querySelector('#rvCrossStatClassifier');if(statClassifier)statClassifier.addEventListener('change',()=>{STATE.statistical.classifierIndex=Number(statClassifier.value);STATE.statisticalResult=null;render(opts);});
    const statReference=root.querySelector('#rvCrossStatReference');if(statReference)statReference.addEventListener('change',()=>{STATE.statistical.referenceAnalysisIndex=Number(statReference.value||0);STATE.statisticalResult=null;render(opts);});
    const statPlotMode=root.querySelector('#rvCrossStatPlotMode');if(statPlotMode)statPlotMode.addEventListener('change',()=>{STATE.statistical.plotMode=String(statPlotMode.value||'performance_violin');render(opts);});
    const statColormap=root.querySelector('#rvCrossStatColormap');if(statColormap)statColormap.addEventListener('change',()=>{STATE.statistical.colormap=String(statColormap.value||'legacy');render(opts);});
    const statHeatValues=root.querySelector('#rvCrossStatHeatValues');if(statHeatValues)statHeatValues.addEventListener('change',()=>{STATE.statistical.showHeatValues=!!statHeatValues.checked;render(opts);});
    root.querySelectorAll('[data-cross-stat-export]').forEach(node=>node.addEventListener('click',()=>{if(typeof opts.exportStatisticalPanel!=='function')return;try{const id=String(node.dataset.crossStatExport||''),visual=statisticalVisualArtifact(root,id),data=statisticalDataArtifact(id);Promise.resolve(opts.exportStatisticalPanel(visual,data)).catch(err=>opts.setMessage(`Panel export failed: ${err&&err.message?err.message:String(err)}`,'danger'));}catch(err){opts.setMessage(`Panel export failed: ${err&&err.message?err.message:String(err)}`,'danger');}}));
    const visualGenerate=root.querySelector('#rvCrossVisualGenerate');if(visualGenerate)visualGenerate.addEventListener('click',()=>generateVisual(opts));
    const visualTarget=root.querySelector('#rvCrossVisualTarget');if(visualTarget)visualTarget.addEventListener('change',()=>{STATE.visual.targetIndex=Number(visualTarget.value);STATE.visualResult=null;render(opts);});
    const visualSource=root.querySelector('#rvCrossVisualSource');if(visualSource)visualSource.addEventListener('change',()=>{STATE.visual.modelSource=String(visualSource.value||'');STATE.visualResult=null;render(opts);});
    const visualClassifier=root.querySelector('#rvCrossVisualClassifier');if(visualClassifier)visualClassifier.addEventListener('change',()=>{STATE.visual.classifierIndex=Number(visualClassifier.value);STATE.visualResult=null;render(opts);});
    const visualMode=root.querySelector('#rvCrossVisualMode');if(visualMode)visualMode.addEventListener('change',()=>{STATE.visual.multiClassModeIndex=Number(visualMode.value);STATE.visualResult=null;render(opts);});
    const visualPlotMode=root.querySelector('#rvCrossVisualPlotMode');if(visualPlotMode)visualPlotMode.addEventListener('change',()=>{STATE.visual.plotMode=String(visualPlotMode.value||'bar');render(opts);});
    root.querySelectorAll('[data-cross-visual-metric]').forEach(node=>node.addEventListener('change',()=>{const id=String(node.dataset.crossVisualMetric||'');if(node.checked)STATE.visual.metricIds.add(id);else{STATE.visual.metricIds.delete(id);STATE.visual.separateAxis.delete(id);}render(opts);}));
    root.querySelectorAll('[data-cross-visual-axis]').forEach(node=>node.addEventListener('change',()=>{const id=String(node.dataset.crossVisualAxis||'');if(node.checked)STATE.visual.separateAxis.add(id);else STATE.visual.separateAxis.delete(id);render(opts);}));
    root.querySelectorAll('[data-cross-visual-color]').forEach(node=>node.addEventListener('input',()=>{STATE.visual.colors.set(String(node.dataset.crossVisualColor||''),String(node.value||''));render(opts);}));
    const visualExport=root.querySelector('#rvCrossVisualExport');if(visualExport)visualExport.addEventListener('click',()=>{if(typeof opts.exportTableArtifact==='function')opts.exportTableArtifact(visualTableArtifact()).catch(err=>opts.setMessage(`Table export failed: ${err&&err.message?err.message:String(err)}`,'danger'));});
    const exportButton=root.querySelector('#rvCrossExportTable');if(exportButton)exportButton.addEventListener('click',()=>{if(typeof opts.exportTableArtifact==='function')opts.exportTableArtifact(performanceTableArtifact()).catch(err=>opts.setMessage(`Table export failed: ${err&&err.message?err.message:String(err)}`,'danger'));});
  }

  /**
   * Purpose: Materialize the Performance Tabulator from existing Model Performance authorities after an explicit analysis-set query.
   * Syntax: generate(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  async function generate(opts){
    if(STATE.busy)return;if(!selectionMatchesInventory()){opts.setMessage('Query the selected analysis set before generating the performance table.','warn');return;}if(!selectedIndices().length){opts.setMessage('Select at least one completed analysis.','warn');return;}
    STATE.busy=true;render(opts);
    try{const spec=requestOverrides();delete spec.metricIds;const out=await opts.matlabService({operation:'results_viewer_cross_analysis_performance_table',spec});if(!out||out.ok===false)throw new Error(out&&out.message||'Cross-analysis performance table request failed.');STATE.result=out.payload||{};STATE.metricIds=new Set(arr(STATE.result.metricOptions).map(m=>String(m.id)));}
    catch(err){STATE.result={ok:false,message:err&&err.message?err.message:String(err)};opts.setMessage(`Cross-analysis performance table failed: ${STATE.result.message}`,'danger');}
    finally{STATE.busy=false;render(opts);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}
  }

  /**
   * Purpose: Render and wire the Cross-analysis workspace from backend catalogue plus resident controlled state.
   * Syntax: render(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function render(opts){opts=opts||{};const payload=opts.payload||{};resetFromPayload(payload);if(opts.exportIconMarkup)STATE.exportIconMarkup=String(opts.exportIconMarkup);const root=opts.root||document.getElementById('crossAnalysisView');if(!root)return;root.innerHTML=shellHtml(payload);bindControls(root,opts,payload);if(typeof opts.refreshScientificInfo==='function')opts.refreshScientificInfo();}

  /**
   * Purpose: Expose authoritative analysis-set/table scientific metadata to the shared information control.
   * Syntax: scientificInfo(...).
   * Inputs: Function arguments and resident module state are explicit browser-side request/presentation inputs.
   * Outputs: Deterministic browser metadata, DOM, request state, or an already-materialized table artefact as implied by the function purpose.
   * Authority and flow: Consumes backend Results Viewer catalogues, queried Scientific State analysis_set inventory, or already-materialized Cross-analysis payloads; no browser-side NM/result-container discovery or scientific recalculation is permitted.
   * Scientific/state contract: Analysis-set identity and capabilities come from Scientific State; module-local state contains only transient selection/presentation/report-request choices.
   * Invariants: Scientific identities are explicit and stable; stale analysis-set selection never silently replaces the last queried Scientific State.
   * Materialization and performance: Operates on compact metadata and returned table rows; no files/XML/atlas/annotation/mesh resources, voxel/vertex scans, or feature-scale arrays are created in JavaScript. Safe for its explicit UI interaction; no retained scientific rematerialization is introduced.
   * Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays.
   * Failure semantics: Missing required state/service capability is surfaced explicitly; no permissive scientific fallback is fabricated.
   * Side effects: Limited to module-local UI state, DOM/event handling, or the explicitly delegated user action.
   * Consumers and dependencies: Cross-analysis workspace actions, shared Analysis Set selector, direct table export, Scientific Info and the single flexible Report Builder.
   */
  function scientificInfo(){
    const statResult=STATE.statisticalResult;if(STATE.activeTab==='statistical'&&statResult&&statResult.ok!==false)return {message:String(statResult.message||'Cross-analysis statistical comparison materialized.'),scientificAnnotations:arr(statResult.scientificAnnotations),scientificDirectory:statResult.scientificDirectory||{},scientificState:statResult.scientificState||{}};const visualResult=STATE.visualResult;if(STATE.activeTab==='visual'&&visualResult&&visualResult.ok!==false)return {message:String(visualResult.message||'Cross-analysis visual comparison materialized.'),scientificAnnotations:arr(visualResult.scientificAnnotations),scientificDirectory:visualResult.scientificDirectory||{},scientificState:visualResult.scientificState||{}};
    const result=STATE.result;if(result&&result.ok!==false)return {message:String(result.message||'Cross-analysis performance table materialized.'),scientificAnnotations:arr(result.scientificAnnotations),scientificDirectory:result.scientificDirectory||{},scientificState:result.scientificState||{}};
    if(selectionMatchesInventory())return {message:'Analysis-set Scientific State inventory is materialized; no cross-analysis performance table has been generated yet.',scientificAnnotations:[],scientificDirectory:STATE.inventoryState.directory||{},scientificState:STATE.inventoryState};
    return {message:'Select completed analyses and use Query results to materialize an analysis-set Scientific State inventory.',scientificAnnotations:[],scientificDirectory:{},scientificState:{}};
  }

  global.NMResultsViewerCrossAnalysis={render,renderAggregatePlot:visualPlotSvg,invocationContext,requestOverrides,selectedAnalysisIndices:selectedIndices,selectedMetricIds,hasPerformanceResult:()=>!!(STATE.result&&STATE.result.ok!==false),hasStatisticalResult:()=>!!(STATE.statisticalResult&&STATE.statisticalResult.ok!==false),hasVisualResult:()=>!!(STATE.visualResult&&STATE.visualResult.ok!==false),hasCurrentAnalysisSetInventory:selectionMatchesInventory,performanceTableArtifact,scientificInfo};
})(window);
