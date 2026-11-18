(function(){
  'use strict';

  const {clamp,text,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  const RUNTIME_CACHE = new Map();
  const RUNTIME_CACHE_LIMIT = 8;
  const ROOT_RUNTIME = new WeakMap();
  const VIEW_TAB_SESSIONS = new WeakMap();
  const MOUNT_SEQUENCES = new Map();
  let VIEW_TAB_SESSION_SEQUENCE = 0, THREE_D_SESSION_DISABLED = false;
  const PLANES = ['axial','coronal','sagittal'];
  const DEFAULT_COLORS = {negative:'#0000ff', midpoint:'#ffffff', positive:'#ff0000'};
  const IMAGING_CONTROL_TOOLTIPS = Object.freeze({
    overlayPage:'Overlay page\nSelect this enabled metric as the active imaging page. In dual-overlay mode, selection also determines which overlay slot receives subsequent display edits.',
    view2d:'2-D orthogonal planes\nShow synchronized axial, coronal, and sagittal planes. Coordinates, thresholds, and display settings are shared with the 3-D view.',
    view3dSurface:'3-D surface\nOpen the 3-D viewer directly in surface-projection mode. The anatomical mesh is required immediately.',
    view3dVolume:'3-D volume\nOpen the 3-D viewer directly in volume-raycast mode. The first volume frame uses mask-only anatomy support; the surface mesh is prepared later.',
    dualOverlay:'Two overlays\nDisplay two enabled feature maps simultaneously. Volumetric data use filled overlay A and polarity-specific overlay B silhouettes in 2-D; native-surface data attach both authoritative vertex arrays to the shared 3-D mesh stream. Volume-derived 3-D modes remain single-overlay.',
    silhouetteColors:'Silhouette colours\nSet the negative and positive colours used only for overlay B silhouettes in 2-D dual-overlay mode. Feature values, thresholds and the overlay B colour scale are unchanged.',
    viewerState:'Viewer state files\nSave, load, or reset a versioned .nmivstate presentation file. Loading validates scientific identities and spatial compatibility before applying coordinates or overlay references.',
    saveState:'Save viewer state\nWrite the current navigation and presentation state to a deterministic .nmivstate JSON file. Hydrated arrays, GPU resources, and runtime caches are excluded.',
    loadState:'Load viewer state\nLoad a .nmivstate file and validate metric, modality, grid, affine, template, and atlas compatibility. Incompatible scientific references are reported rather than silently substituted.',
    resetState:'Reset viewer state\nRestore source-derived viewer defaults for the current imaging payload. This does not modify the underlying NeuroMiner results.',
    template:'Structural template\nChoose the anatomical background used for display. This changes only the selected reference image and does not alter feature-map values.',
    gridPolicy:'Display grid\nChoose whether planes are sampled on the structural-reference grid or the feature-reference grid. Coordinates are interpreted only through the selected grid contract.',
    anatomyInterpolation:'Anatomy interpolation\nControls display-only reconstruction of the structural background. High quality smooths anatomy; it does not change aligned voxel values or coordinates.',
    featureInterpolation:'Feature interpolation\nVoxel-faithful preserves native active support exactly. Support-aware linear interpolates only supported, suprathreshold, same-sign contributors and cannot create new active support.',
    renderer2d:'2-D renderer\nAuto prefers the shared WebGL2 high-resolution renderer when capability and memory checks pass, otherwise it retains the responsive CPU-compatible renderer.',
    atlas:'Atlas\nSelect an atlas for nearest-neighbour anatomical labels, ROI boundaries, and ROI statistics. Atlas substitution is never performed silently.',
    atlasLabel:'Anatomical label\nShows the nearest-neighbour atlas label at the selected coordinate or, while hovering, at the pointer location.',
    atlasBoundaries:'Atlas boundaries\nOverlay atlas parcel boundaries on the anatomical planes. Boundary rendering is presentation-only and does not modify ROI identities.',
    boundaryColor:'Boundary colour\nSet the display colour of atlas parcel boundaries.',
    boundaryOpacity:'Boundary opacity\nAdjust atlas-boundary visibility without changing the atlas labels or feature overlay.',
    roiTable:'ROI Tabulator\nOpen atlas-wise suprathreshold feature statistics for the focused overlay. Statistics use authoritative values and support, not colour normalization.',
    crosshairs:'Crosshairs\nShow or hide the synchronized selected-coordinate crosshairs in all three planes.',
    negativeColor:'Negative colour\nSet the colour used for negative suprathreshold feature values. Values and thresholds are unchanged.',
    midpointColor:'Low or midpoint colour\nSet the low-end colour for one-sided maps or the neutral midpoint colour for signed maps.',
    positiveColor:'Positive colour\nSet the colour used for positive suprathreshold feature values. Values and thresholds are unchanged.',
    threshold:'Feature threshold\nControls which native feature values are displayed as active. The − and + buttons change the value by 1% of the full exact feature-map range. Manual text is committed only with Enter or when focus leaves the field; display-range changes do not alter this threshold.',
    colorScale:'Colour scale\nControls colour normalization only. Robust signed uses separate robust negative and positive endpoints; Full range uses exact extrema; Symmetric |value| uses equal absolute endpoints; Manual uses explicit limits. Saturated values remain present.',
    manualLower:'Manual lower endpoint\nSet the lower colour-normalization endpoint. Values below it are saturated, not removed.',
    manualUpper:'Manual upper endpoint\nSet the upper colour-normalization endpoint. Values above it are saturated, not removed.',
    opacity:'Overlay opacity\nAdjust transparency of the focused feature overlay. Underlying feature values, support, and thresholds are unchanged.',
    brightness:'Anatomy brightness\nAdjust display brightness of the structural background only. Feature values and colour normalization are unchanged.',
    voxelReadout:'Voxel coordinate\nOne-based voxel coordinate on the active display grid. The three planes and 3-D target use the same selected location.',
    worldReadout:'World coordinate\nWorld-space coordinate in millimetres computed from the authoritative voxel-to-world affine of the active display grid.',
    valueReadout:'Feature value\nExact focused-overlay value at the selected voxel. This readout is independent of the active colour-display range.',
    roiReadout:'ROI label\nNearest-neighbour atlas label at the selected coordinate. A dash indicates that no atlas label is available.',
    minimum:'Minimum\nMove all three planes to the exact global minimum of the focused overlay inside finite authoritative support.',
    maximum:'Maximum\nMove all three planes to the exact global maximum of the focused overlay inside finite authoritative support.',
    strongest:'Maximum absolute value\nMove all three planes to the supported voxel with the strongest absolute feature value, preserving its original sign.',
    zoomOut:'Zoom out\nReduce magnification of the active plane, or all planes when synchronization is enabled.',
    zoomIn:'Zoom in\nIncrease magnification of the active plane, or all planes when synchronization is enabled.',
    fit:'Fit view\nReset pan and zoom for the active plane, or all planes when synchronization is enabled. The selected coordinate is preserved.',
    resetView:'Reset 2-D view\nReset pan and zoom in all planes and return to the payload initial coordinate. Thresholds, colours, and saved-state files are not changed.',
    syncViews:'Synchronize views\nApply zoom and pan changes to all planes and maintain one shared selected voxel across axial, coronal, and sagittal views.',
    multislice:'Multi-slice montage\nOpen the configurable mosaic viewer for the active plane using the current feature, threshold, colour-scale, atlas, and interpolation settings.',
    roiMapper:'ROI Mapper\nCompare ROI-projected feature signatures from the current Feature Inspection viewspace using the active authoritative parcellation. Canonical ROI payloads use their provenance atlas or annotation automatically. The mapper inherits enabled payloads and never changes the underlying scientific results.',
    copyVoxel:'Copy voxel coordinate\nCopy the selected one-based voxel coordinate on the active display grid to the clipboard.',
    copyWorld:'Copy world coordinate\nCopy the selected world-space coordinate in millimetres using the authoritative active-grid affine.',
    copyValue:'Copy feature value\nCopy the exact focused-overlay value at the selected voxel. Colour normalization does not affect the copied value.',
    setThreshold:'Set threshold from selected value\nUse the exact focused-overlay value as the applicable positive, negative, or absolute threshold. This is an explicit scientific display-threshold change.',
    exactRange:'Exact data range\nMinimum and maximum finite values inside authoritative feature support. This range is scientific metadata and does not change when colour normalization changes.',
    shownRange:'Shown colour range\nActive lower and upper endpoints used for colour normalization. Values outside these endpoints are saturated rather than discarded.',
    clippedRange:'Saturated values\nNumber of supported displayed values below and above the active colour endpoints. These values remain part of the overlay and all scientific calculations.'
  });

  function profileEnabled(opts){ return !!(opts&&opts.profileEnabled); }
  function profile(opts,label,startedAt,detail){
    if(!profileEnabled(opts)||typeof opts.profileLog!=='function')return;
    opts.profileLog(`imaging ${String(label||'')}`,startedAt,detail||'');
  }

  function arr(v){ return Array.isArray(v) ? v : (v == null ? [] : [v]); }
  function smoothstep(edge0,edge1,value){const t=clamp((finite(value,0)-edge0)/Math.max(Number.EPSILON,edge1-edge0),0,1);return t*t*(3-2*t);}
  function supportCoverageAlpha(coverage){return smoothstep(.34,.66,clamp(finite(coverage,0),0,1));}
  function finite(v,d){ if(v===null||v===undefined||v===''||typeof v==='boolean'||Array.isArray(v)||(typeof v==='object'&&v!==null))return d;const n=Number(v);return Number.isFinite(n)?n:d; }
  function copy(v){ try{return JSON.parse(JSON.stringify(v));}catch(err){return v;} }
  function tooltipText(key){return text(IMAGING_CONTROL_TOOLTIPS[key]||'');}
  function tooltipAttributesFromText(value,escapeFn){const esc=typeof escapeFn==='function'?escapeFn:escapeHtml,t=text(value);return t?` data-imaging-tooltip="${esc(t)}" aria-description="${esc(t.replace(/\s*\n\s*/g,' '))}"`:'';}
  function tooltipAttributes(key,escapeFn){return tooltipAttributesFromText(tooltipText(key),escapeFn);}
  function uniqueText(values){ return Array.from(new Set(arr(values).map(text).filter(Boolean))); }
  function runtimeCacheSet(key,value){
    if(RUNTIME_CACHE.has(key))RUNTIME_CACHE.delete(key);
    RUNTIME_CACHE.set(key,value);
    while(RUNTIME_CACHE.size>RUNTIME_CACHE_LIMIT){
      const oldest=RUNTIME_CACHE.keys().next().value;
      RUNTIME_CACHE.delete(oldest);
    }
  }
  function hexToRgb(hex){
    let h=text(hex).trim().replace(/^#/,'');
    if(h.length===3) h=h.split('').map(c=>c+c).join('');
    if(!/^[0-9a-f]{6}$/i.test(h)) return [255,255,255];
    return [parseInt(h.slice(0,2),16),parseInt(h.slice(2,4),16),parseInt(h.slice(4,6),16)];
  }
  function fmt(v,digits){
    const n=finite(v,NaN); if(!Number.isFinite(n)) return '—';
    const d=Number.isFinite(Number(digits))?Number(digits):3;
    if(Math.abs(n)>=10000||(Math.abs(n)>0&&Math.abs(n)<Math.pow(10,-d))) return n.toExponential(Math.max(1,d-1));
    return n.toFixed(d).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');
  }

  function displaySemantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api)throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');return api;}
  function displayControls(){const api=window.NMResultsViewerDisplayControls;if(!api||typeof api.html!=='function'||typeof api.bind!=='function'||typeof api.applyCommand!=='function')throw new Error('The pathway-neutral Results Viewer display controls are unavailable.');return api;}
  function anatomyControls(){const api=window.NMResultsViewerStructuralAnatomyControls;if(!api||typeof api.html!=='function'||typeof api.bind!=='function')throw new Error('The shared structural-anatomy controls are unavailable.');return api;}
  function viewControls(){const api=window.NMResultsViewerViewControls;if(!api||typeof api.toolbarHtml!=='function'||typeof api.bind!=='function')throw new Error('The pathway-neutral Results Viewer view controls are unavailable.');return api;}
  function informationControls(){const api=window.NMResultsViewerInformationControls;if(!api||typeof api.html!=='function'||typeof api.bind!=='function'||typeof api.update!=='function')throw new Error('The pathway-neutral Results Viewer information controls are unavailable.');return api;}
  function interactionIdentity(){const api=window.NMResultsViewerInteractionIdentity;if(!api||typeof api.createVoxel!=='function'||typeof api.createSurfaceVertex!=='function'||typeof api.assertIdentity!=='function'||typeof api.createState!=='function')throw new Error('The canonical Results Viewer interaction-identity authority is unavailable.');return api;}
  function featureRepresentationDefinition(id){const api=window.NMResultsViewerFeatureRepresentations,definition=api&&typeof api.definition==='function'?api.definition(text(id)):null;if(!definition||!['imaging.2d','imaging.3d'].includes(text(definition.adapterId)))throw new Error(`Unknown imaging representation: ${text(id)||'(empty)'}.`);return definition;}
  function imaging3DController(){const api=window.NMResultsViewerImaging3DController;if(!api)throw new Error('The specialized 3-D imaging controller is unavailable.');return api;}
  function colorGradient(){const api=window.NMImagingColorGradient;if(!api||typeof api.resolvedStops!=='function'||typeof api.sampleContractRgb255!=='function')throw new Error('The canonical imaging colour-gradient authority is unavailable.');return api;}
  function displayContract(display){return displaySemantics().contractForDisplay(display);}


  function surfaceAdapter(){const api=window.NMResultsViewerSurfaceAdapter;if(!api||typeof api.isSurfaceRuntime!=='function')throw new Error('The authoritative native-surface adapter is unavailable.');return api;}
  function isSurfaceRuntime(runtime){return !!surfaceAdapter().isSurfaceRuntime(runtime);}
  function workspaceCapability(runtime,name,fallback=true){const c=runtime&&runtime.payload&&runtime.payload.capabilities||{};return Object.prototype.hasOwnProperty.call(c,name)?c[name]!==false:fallback;}
  function effectiveFeatureInterpolation(runtime,state){return workspaceCapability(runtime,'featureInterpolation',true)&&text(state&&state.featureInterpolation)==='support_aware_linear'?'support_aware_linear':'voxel_faithful';}
  function normalizeWorkspaceCapabilities(state,runtime){
    const c=runtime&&runtime.payload&&runtime.payload.capabilities||{},sourceDomain=text(c.sourceDomain).toLowerCase(),canonicalROI=c.canonicalROI===true;
    state.render3D=imaging3DController().normalizeState(state.render3D);
    if(sourceDomain==='volume'){
      state.displayGridPolicy=text(runtime.payload.displayGridPolicy);
      state.render3D.overlay.surfaceSamplingMode=canonicalROI?'audit_voxel_faithful':'continuous_signed_trilinear';
      state.render3D.overlay.projectionAlphaMode=canonicalROI?'uniform':'threshold_free_local_support';
      state.render3D.overlay.volumeFeaturePresentation=canonicalROI?'native_voxel_audit':'reconstructed';
    }
    if(!canonicalROI)return state;
    state.selectedAtlasId=text(runtime.payload&&runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.atlasId);state.volumeAtlasPath='';state.surfaceAtlasPaths={selectedPath:'',lhPath:'',rhPath:''};state.render3D.overlay.surfaceFeatureSmoothingMm=0;if(sourceDomain==='volume')state.render3D.anatomy.volumeBoundarySmoothingMm=0;return state;
  }
  function measuresAreSurface(measures){const list=arr(measures);return list.length>0&&list.every(m=>{const kind=text(m&&m.mapKind).toLowerCase(),domain=text(m&&m.roiSpatialDomain).toLowerCase();return kind==='surface_vertex'||(kind==='roi'&&domain==='surface');});}

  function availableMeasures(payload){
    const selectedContextId=text(payload&&payload.selectedFeatureContextId);
    const selectedSpatial=arr(payload&&payload.spatialMaps).filter(sp=>{
      const kind=text(sp&&sp.mapKind).toLowerCase();
      return (kind==='voxel'||kind==='surface_vertex'||kind==='roi'||kind==='connectivity_edge')&&(!selectedContextId||text(sp&&sp.contextId)===selectedContextId)&&((kind==='surface_vertex'||kind==='connectivity_edge'||(kind==='roi'&&text(sp&&sp.roiSpatialDomain).toLowerCase()==='surface'))||sp.enabled!==false);
    });
    const spatialIds=new Set(selectedSpatial.map(sp=>text(sp.measureId)).filter(Boolean));
    const selectedContextKind=text(payload&&payload.selectedFeatureContext&&payload.selectedFeatureContext.featureKind).toLowerCase();
    const connectivityContext=selectedContextKind==='connectivity_edge'||selectedSpatial.some(sp=>text(sp&&sp.mapKind).toLowerCase()==='connectivity_edge');
    const connectivityBase=connectivityContext?(selectedSpatial.find(sp=>text(sp&&sp.mapKind).toLowerCase()==='connectivity_edge')||{}):{};
    return arr(payload&&payload.measures).filter(m=>{
      if(selectedContextId&&text(m&&m.contextId)!==selectedContextId)return false;
      return spatialIds.has(text(m&&m.measureId))||connectivityContext;
    }).map(m=>{
      const spatial=selectedSpatial.find(sp=>text(sp&&sp.measureId)===text(m.measureId))||connectivityBase,mapKind=text(spatial&&spatial.mapKind).toLowerCase();
      const measureEnabled=!m||m.enabled!==false,spatialEnabled=mapKind==='surface_vertex'||(mapKind==='roi'&&text(spatial&&spatial.roiSpatialDomain).toLowerCase()==='surface')||!spatial||spatial.enabled!==false;
      const disabledReason=!measureEnabled?text(m&&m.disabledReason):(!spatialEnabled?text(spatial&&spatial.disabledReason):'');
      return Object.assign({},m,spatial,{measureId:text(m.measureId),label:text(m.label||m.measureId),sourceField:text(m.sourceField),valuePolarity:text(m.valuePolarity||'signed'),mapKind:text(spatial&&spatial.mapKind||(connectivityContext?'connectivity_edge':'')),enabled:measureEnabled&&spatialEnabled,disabledReason});
    });
  }

  function planeState(){ return {zoom:1,panX:0,panY:0,voxel:[NaN,NaN,NaN]}; }
  function defaultState(measures){
    const ids=arr(measures).filter(m=>m&&m.enabled!==false).map(m=>text(m.measureId)).filter(Boolean);
    const first=ids[0]||'',surface=measuresAreSurface(measures);
    return {
      schema:'NMImagingViewState',schemaVersion:5,contractVersion:'C18e1',
      enabledMetricIds:first?[first]:[],activePageMetricId:first,activeViewMode:surface?'three_dimensional':'orthogonal',
      dualOverlayEnabled:false,overlayAId:first,overlayBId:'',focusedOverlaySlot:'A',
      dualOverlayMode:'filled_plus_contour',displayGridPolicy:surface?'surface_native':'structural_reference',
      selectedTemplateId:surface?'native':'',selectedAtlasId:'',volumeAtlasPath:'',volumeAtlasDelimiter:'auto',volumeAtlasNameColumn:'',volumeAtlasDescriptorFile:'',surfaceAtlasPaths:{selectedPath:'',lhPath:'',rhPath:''},
      currentVoxel:[NaN,NaN,NaN],currentWorldMm:[NaN,NaN,NaN],crosshairVisible:false,
      backgroundBrightness:1,anatomyGamma:1,anatomyInterpolation:'high_quality',featureInterpolation:'voxel_faithful',displayInterpolation:'high_quality',interactive2DRendererMode:'auto',tooltipsEnabled:false,atlasBoundariesVisible:false,
      atlasBoundaryColor:'#202020',atlasBoundaryOpacity:0.82,dualOverlaySilhouetteNegativeColor:DEFAULT_COLORS.negative,dualOverlaySilhouettePositiveColor:DEFAULT_COLORS.positive,
      syncViews:true,zoomLinkMode:'synchronized',lastPlaneId:'axial',roiMinPct:0,
      multiSlice:{planeId:'axial',rows:2,columns:2,startSlice:1,endSlice:NaN,gapPx:3,labelMode:'world',labelPosition:'top_left',fitMode:'full',labelFontPx:14},
      planes:{axial:planeState(),coronal:planeState(),sagittal:planeState()},
      perMetricDisplayState:{},extremumMarker:null,render3D:imaging3DController().defaultState(),contentId:'',stateFileName:'',stateCompatibilityStatus:'',stateCompatibilitySummary:null
    };
  }

  function normalizeMultiSlice(value){
    const ms=value&&typeof value==='object'?value:{};
    return {planeId:PLANES.includes(ms.planeId)?ms.planeId:'axial',rows:clamp(Math.round(finite(ms.rows,2)),1,6),columns:clamp(Math.round(finite(ms.columns,2)),1,6),startSlice:Math.max(1,Math.round(finite(ms.startSlice,1))),endSlice:finite(ms.endSlice,NaN),gapPx:clamp(Math.round(finite(ms.gapPx,3)),0,24),labelMode:['world','index','both','none'].includes(text(ms.labelMode))?text(ms.labelMode):(ms.includeLabels===false?'none':'world'),labelPosition:['top_left','top_right','bottom_left','bottom_right'].includes(text(ms.labelPosition))?text(ms.labelPosition):'top_left',fitMode:text(ms.fitMode)==='tight'?'tight':'full',labelFontPx:clamp(Math.round(finite(ms.labelFontPx,14)),9,28)};
  }

  function normalizeState(state,measures){
    const valid=arr(measures).filter(m=>m&&m.enabled!==false).map(m=>text(m.measureId)).filter(Boolean);
    const out=state&&typeof state==='object'?state:defaultState(measures);
    out.schema='NMImagingViewState'; out.schemaVersion=5; out.contractVersion='C18e1';
    const surface=measuresAreSurface(measures);
    out.activeViewMode=surface?'three_dimensional':(out.activeViewMode==='three_dimensional'?'three_dimensional':'orthogonal');
    out.enabledMetricIds=uniqueText(out.enabledMetricIds).filter(id=>valid.includes(id));
    if(!out.enabledMetricIds.length&&valid.length) out.enabledMetricIds=[valid[0]];
    if(!out.activePageMetricId||!out.enabledMetricIds.includes(text(out.activePageMetricId))) out.activePageMetricId=out.enabledMetricIds[0]||'';
    out.overlayAId=text(out.overlayAId);
    if(!out.enabledMetricIds.includes(out.overlayAId)) out.overlayAId=out.activePageMetricId;
    out.overlayBId=text(out.overlayBId);
    if(!out.enabledMetricIds.includes(out.overlayBId)||out.overlayBId===out.overlayAId) out.overlayBId='';
    out.focusedOverlaySlot=out.focusedOverlaySlot==='B'?'B':'A';
    out.dualOverlayEnabled=!!out.dualOverlayEnabled;
    out.dualOverlayMode='filled_plus_contour';
    out.displayGridPolicy=surface?'surface_native':(out.displayGridPolicy==='feature_reference'?'feature_reference':'structural_reference');
    out.selectedTemplateId=text(out.selectedTemplateId);
    out.selectedAtlasId=text(out.selectedAtlasId);out.volumeAtlasPath=text(out.volumeAtlasPath);
    out.volumeAtlasDelimiter=text(out.volumeAtlasDelimiter);out.volumeAtlasNameColumn=text(out.volumeAtlasNameColumn);out.volumeAtlasDescriptorFile=text(out.volumeAtlasDescriptorFile);
    const atlasPaths=out.surfaceAtlasPaths&&typeof out.surfaceAtlasPaths==='object'?out.surfaceAtlasPaths:{};out.surfaceAtlasPaths={selectedPath:text(atlasPaths.selectedPath),lhPath:text(atlasPaths.lhPath),rhPath:text(atlasPaths.rhPath)};
    out.crosshairVisible=!!out.crosshairVisible;
    out.backgroundBrightness=clamp(finite(out.backgroundBrightness,1),0,2);out.anatomyGamma=clamp(finite(out.anatomyGamma,out.render3D&&out.render3D.anatomy&&out.render3D.anatomy.gamma||1),.25,4);
    const legacyInterpolation=['nearest','linear','high_quality'].includes(text(out.displayInterpolation))?text(out.displayInterpolation):'high_quality';
    out.anatomyInterpolation=['nearest','linear','high_quality'].includes(text(out.anatomyInterpolation))?text(out.anatomyInterpolation):legacyInterpolation;
    out.featureInterpolation=text(out.featureInterpolation)==='support_aware_linear'?'support_aware_linear':'voxel_faithful';
    out.displayInterpolation=out.anatomyInterpolation;
    out.interactive2DRendererMode=['auto','gpu','cpu'].includes(text(out.interactive2DRendererMode))?text(out.interactive2DRendererMode):'auto';
    if(typeof out.tooltipsEnabled==='boolean')out.tooltipsEnabled=out.tooltipsEnabled;
    else if(typeof out.tipsEnabled==='boolean')out.tooltipsEnabled=out.tipsEnabled;
    else if(typeof out.tips==='boolean')out.tooltipsEnabled=out.tips;
    else out.tooltipsEnabled=false;
    out.atlasBoundariesVisible=!!out.atlasBoundariesVisible;
    out.atlasBoundaryColor=/^#[0-9a-f]{6}$/i.test(text(out.atlasBoundaryColor))?text(out.atlasBoundaryColor):'#202020';
    out.atlasBoundaryOpacity=clamp(finite(out.atlasBoundaryOpacity,.82),0,1);
    out.dualOverlaySilhouetteNegativeColor=/^#[0-9a-f]{6}$/i.test(text(out.dualOverlaySilhouetteNegativeColor))?text(out.dualOverlaySilhouetteNegativeColor):DEFAULT_COLORS.negative;
    out.dualOverlaySilhouettePositiveColor=/^#[0-9a-f]{6}$/i.test(text(out.dualOverlaySilhouettePositiveColor))?text(out.dualOverlaySilhouettePositiveColor):DEFAULT_COLORS.positive;
    out.syncViews=out.syncViews!==false;
    out.zoomLinkMode=out.syncViews?'synchronized':'independent';
    out.roiMinPct=Math.max(0,finite(out.roiMinPct,0));
    if(out.extremumMarker&&typeof out.extremumMarker==='object'){
      const em=out.extremumMarker,nav=em.navigation&&typeof em.navigation==='object'?em.navigation:{};out.extremumMarker={kind:text(em.kind),measureId:text(em.measureId),linearIndex:Math.max(0,Math.round(finite(em.linearIndex,0))),vertexIndex:Number.isFinite(Number(em.vertexIndex))?Math.max(0,Math.round(Number(em.vertexIndex))):NaN,voxel:arr(em.voxel).slice(0,3).map(Number),worldMm:arr(em.worldMm).slice(0,3).map(Number),value:finite(em.value,NaN),atlasCode:Math.max(0,Math.round(finite(em.atlasCode,0))),atlasLabel:text(em.atlasLabel),visible:em.visible!==false,navigation:{mode:text(nav.mode),direction:arr(nav.direction).slice(0,3).map(Number),exitDistanceMm:finite(nav.exitDistanceMm,NaN),intersectionCount:Math.max(0,Math.round(finite(nav.intersectionCount,0))),rotationRad:finite(nav.rotationRad,NaN),customPlane:[]}};
      const validWorld=out.extremumMarker.worldMm.length===3&&out.extremumMarker.worldMm.every(Number.isFinite),validVoxel=out.extremumMarker.voxel.length===3&&out.extremumMarker.voxel.every(Number.isFinite),validVertex=Number.isFinite(out.extremumMarker.vertexIndex);if(!validWorld||(!validVoxel&&!validVertex))out.extremumMarker=null;
    }else out.extremumMarker=null;
    out.multiSlice=normalizeMultiSlice(out.multiSlice);
    out.lastPlaneId=PLANES.includes(out.lastPlaneId)?out.lastPlaneId:'axial';
    out.planes=out.planes&&typeof out.planes==='object'?out.planes:{};
    PLANES.forEach(p=>{
      const src=out.planes[p]&&typeof out.planes[p]==='object'?out.planes[p]:planeState();
      let voxel=arr(src.voxel).slice(0,3).map(x=>finite(x,NaN));while(voxel.length<3)voxel.push(NaN);
      out.planes[p]={zoom:clamp(finite(src.zoom,1),0.25,8),panX:finite(src.panX,0),panY:finite(src.panY,0),voxel};
    });
    out.currentVoxel=arr(out.currentVoxel).slice(0,3).map(x=>finite(x,NaN)); while(out.currentVoxel.length<3)out.currentVoxel.push(NaN);
    out.currentWorldMm=arr(out.currentWorldMm).slice(0,3).map(x=>finite(x,NaN)); while(out.currentWorldMm.length<3)out.currentWorldMm.push(NaN);
    out.perMetricDisplayState=out.perMetricDisplayState&&typeof out.perMetricDisplayState==='object'?out.perMetricDisplayState:{};
    out.stateFileName=text(out.stateFileName);out.stateCompatibilityStatus=text(out.stateCompatibilityStatus);out.stateCompatibilitySummary=out.stateCompatibilitySummary&&typeof out.stateCompatibilitySummary==='object'?out.stateCompatibilitySummary:null;
    out.render3D=imaging3DController().normalizeState(out.render3D);out.anatomyGamma=out.render3D.anatomy.gamma;
    return out;
  }

  function metricById(measures,id){ return arr(measures).find(m=>text(m.measureId)===text(id))||null; }


  function viewTabKind(state){return state&&state.activeViewMode==='three_dimensional'?'three_dimensional':'orthogonal';}
  function scientificTabSignature(state){return [requestedMetricIds(state).join(','),state&&state.dualOverlayEnabled?1:0,text(state&&state.displayGridPolicy),text(state&&state.selectedTemplateId),text(state&&state.selectedAtlasId),text(state&&state.volumeAtlasPath),text(state&&state.volumeAtlasDelimiter),text(state&&state.volumeAtlasNameColumn),text(state&&state.volumeAtlasDescriptorFile)].join('|');}
  function disposeRootRuntime(root){
    if(!root)return;const prior=ROOT_RUNTIME.get(root);
    if(prior){if(prior.controlHost&&typeof prior.controlHost.dispose==='function')prior.controlHost.dispose();if(typeof prior.cancel==='function')try{prior.cancel();}catch(err){}ROOT_RUNTIME.delete(root);}
  }
  function tabSessionForRoot(root,state){
    const parent=root&&root.parentNode;if(!parent)return null;let session=VIEW_TAB_SESSIONS.get(parent);
    if(!session){session={id:`nm-imaging-tabs-${++VIEW_TAB_SESSION_SEQUENCE}`,parent,roots:{orthogonal:null,three_dimensional:null},activeKind:viewTabKind(state)};VIEW_TAB_SESSIONS.set(parent,session);}
    return session;
  }
  function registerTabRoot(root,state){
    const session=tabSessionForRoot(root,state);if(!session)return null;const kind=viewTabKind(state),previous=session.roots[kind];
    if(previous&&previous!==root){disposeRootRuntime(previous);if(previous.isConnected)previous.remove();}
    session.roots[kind]=root;session.activeKind=kind;root.dataset.imagingTabSessionId=session.id;root.dataset.imagingTabKind=kind;return session;
  }
  function invalidatePeerTabs(root,state){
    const session=tabSessionForRoot(root,state);if(!session)return;const current=text(root&&root.dataset&&root.dataset.imagingTabKind)||viewTabKind(state);Object.keys(session.roots).forEach(kind=>{const peer=session.roots[kind];if(peer&&kind!==current){disposeRootRuntime(peer);if(peer.isConnected)peer.remove();session.roots[kind]=null;}});
  }
  function unmount(rootOrId){
    const root=typeof rootOrId==='string'?document.getElementById(rootOrId):rootOrId;
    if(!root)return false;
    const rootId=text(root.id||'');if(rootId)MOUNT_SEQUENCES.delete(rootId);
    const parent=root.parentNode,session=parent&&VIEW_TAB_SESSIONS.get(parent);
    if(session){
      Object.keys(session.roots).forEach(kind=>{const peer=session.roots[kind];if(peer){disposeRootRuntime(peer);if(peer.isConnected)peer.remove();session.roots[kind]=null;}});
      VIEW_TAB_SESSIONS.delete(parent);
    }else{
      disposeRootRuntime(root);if(root.isConnected)root.remove();
    }
    return true;
  }
  function shellElement(measures,state,escapeFn,rootId){const template=document.createElement('template');template.innerHTML=shellHtml(measures,state,escapeFn,rootId).trim();return template.content.firstElementChild;}
  function synchronizeFeatureInterpolationControl(root,state){if(!root)return;const value=text(state&&state.featureInterpolation)==='support_aware_linear'?'support_aware_linear':'voxel_faithful';Array.from(root.querySelectorAll('[data-imaging-feature-interpolation]')).forEach(node=>{node.value=value;});}
  function synchronizeAtlasDependentControls(root,runtime,state){if(!root)return false;const available=!!(runtime&&runtime.atlas&&runtime.atlas.data);if(!available&&state)state.atlasBoundariesVisible=false;Array.from(root.querySelectorAll('[data-imaging-boundaries]')).forEach(node=>{node.disabled=!available;node.checked=available&&!!(state&&state.atlasBoundariesVisible);});Array.from(root.querySelectorAll('[data-imaging-boundary-color],[data-imaging-boundary-opacity]')).forEach(node=>{node.disabled=!available;});Array.from(root.querySelectorAll('[data-imaging-roi-table],[data-imaging-roi-mapper]')).forEach(node=>{node.disabled=!available;node.setAttribute('aria-disabled',available?'false':'true');node.classList.toggle('isAtlasUnavailable',!available);if(available)node.removeAttribute('tabindex');else node.setAttribute('tabindex','-1');});
    Array.from(root.querySelectorAll('[data-imaging-atlas]')).forEach(node=>{const selected=runtime.payload.selectedAtlas,id=text(selected&&selected.atlasId);if(available&&id&&!Array.from(node.options).some(option=>option.value===id))node.add(new Option(text(selected.label),id),node.options[node.options.length-1]);node.value=available?id:'none';});
    Array.from(root.querySelectorAll('[data-imaging-atlas-descriptor]')).forEach(node=>{node.innerHTML=viewControls().atlasDescriptorControlsHtml(runtime,state,escapeHtml);});return available;}
  async function activateRetainedViewTab(currentRoot,targetView,targetRendering,opts,state,measures,commitNow){
    const startedAt=performance.now(),currentKind=viewTabKind(state),targetKind=targetView==='three_dimensional'?'three_dimensional':'orthogonal',session=registerTabRoot(currentRoot,state);
    if(!session)return {retained:false,reason:'tab_session_unavailable'};
    if(currentKind==='three_dimensional')imaging3DController().suspend(currentRoot,'view_tab_switch');
    const requested3DMode=targetRendering==='volume_raycast'?'volume_raycast':'surface_projection';let targetRoot=session.roots[targetKind],targetRecord=targetRoot&&ROOT_RUNTIME.get(targetRoot);state.activeViewMode=targetKind;state.render3D=state.render3D||{};
    if(targetKind!=='three_dimensional'&&typeof commitNow==='function')commitNow('view_mode');
    const signature=scientificTabSignature(state);
    if(targetRoot&&targetRecord&&targetRecord.scientificSignature!==signature){
      if(typeof targetRecord.refreshScientificPayload==='function'){currentRoot.replaceWith(targetRoot);session.activeKind=targetKind;const result=await targetRecord.refreshScientificPayload('tab_resume');if(!result||!result.retained){targetRoot.replaceWith(currentRoot);session.activeKind=currentKind;targetRoot=null;targetRecord=null;}else targetRecord.scientificSignature=signature;}
      else{disposeRootRuntime(targetRoot);session.roots[targetKind]=null;targetRoot=null;targetRecord=null;}
    }
    if(targetRoot&&targetRecord){
      if(currentRoot.isConnected)currentRoot.replaceWith(targetRoot);session.activeKind=targetKind;applyViewportHeight(targetRoot);
      if(targetKind==='three_dimensional'){const controller=imaging3DController();controller.resume(targetRoot,'view_tab_switch');await controller.setRenderingMode(targetRoot,requested3DMode,'view_tab_switch');if(typeof commitNow==='function')commitNow('view_mode');}
      else{redraw(targetRecord.runtime,state,targetRoot,opts,false,PLANES);requestAnimationFrame(()=>{if(targetRoot.isConnected){applyViewportHeight(targetRoot);redraw(targetRecord.runtime,state,targetRoot,opts,false,PLANES);}});}
      synchronizeMetricShell(targetRoot,state,measures);synchronizeFeatureInterpolationControl(targetRoot,state);resetImagingScrollPositions(targetRoot);profile(opts,'view tab switch retained',startedAt,`session=${session.id} from=${currentKind} to=${targetKind} rendererRetained=${targetKind==='three_dimensional'?1:0} rootRetained=1`);return {retained:true,root:targetRoot,sessionId:session.id};
    }
    if(targetKind==='three_dimensional'){state.render3D.renderingMode=requested3DMode;if(typeof commitNow==='function')commitNow('view_mode');}
    const next=shellElement(measures,state,opts&&opts.escape,currentRoot.id);if(!next)throw new Error('Imaging tab shell could not be created.');session.roots[currentKind]=currentRoot;session.roots[targetKind]=next;session.activeKind=targetKind;currentRoot.replaceWith(next);
    const mounted=await mount(Object.assign({},opts,{root:next,state,preservePeerTabs:true}),false);profile(opts,'view tab switch initialize',startedAt,`session=${session.id} from=${currentKind} to=${targetKind} rendererRetained=0 rootRetained=0`);return {retained:false,root:mounted||document.getElementById(currentRoot.id),sessionId:session.id};
  }

  function toolbarHtml(payload,state,escapeFn,supplementalHtml,options){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml;
    const cfg=options&&typeof options==='object'?options:{};
    const selectionOnly=!!cfg.selectionOnly;
    const measures=availableMeasures(payload); normalizeState(state,measures);
    const toggles=measures.map(m=>{
      const selectable=m&&m.enabled!==false;
      const enabled=selectable&&state.enabledMetricIds.includes(m.measureId);
      const page=selectable&&state.activePageMetricId===m.measureId;
      const active=selectionOnly?page:enabled;
      const action=selectable?(selectionOnly?'Select this payload category for the current representation.':(enabled?'Remove this metric from the enabled imaging pages.':'Add this metric as an imaging page.')):text(m&&m.disabledReason||'This payload category is unavailable.');
      return `<button type="button" class="rvFeatureToolbarToggle rvPanelToolbarToggle rvImagingMetricToggle${active?' isActive':''}${page?' isCurrent':''}${selectable?'':' isUnavailable'}" data-imaging-overlay-toggle="${esc(m.measureId)}" aria-pressed="${active?'true':'false'}" aria-disabled="${selectable?'false':'true'}"${selectable?'':' disabled'}${tooltipAttributesFromText(`${selectionOnly?'Payload category':'Feature overlay'}\n${action}${selectable?' The underlying result payload is not modified.':''}`,esc)}>${esc(m.label)}</button>`;
    }).join('');
    const supplemental=typeof supplementalHtml==='string'?supplementalHtml:'';
    const label=text(cfg.label||'Feature panels');
    const empty=text(cfg.emptyLabel||(selectionOnly?'No connectivity payload categories available.':'No voxel metrics available.'));
    return `<div class="rvFeatureMetricToolbar rvPanelToggleToolbar rvImagingMetricToolbar${selectionOnly?' rvImagingMetricToolbar--selection':''}" role="toolbar" aria-label="${esc(label)}"><span>${esc(label)}</span>${toggles||`<span class="muted">${esc(empty)}</span>`}${supplemental}</div>`;
  }

  function toggleMetric(state,metricId,measures){
    normalizeState(state,measures); const id=text(metricId),metric=metricById(measures,id); if(!id||!metric||metric.enabled===false) return state;
    const has=state.enabledMetricIds.includes(id);
    if(has){
      if(state.enabledMetricIds.length<=1) return state;
      state.enabledMetricIds=state.enabledMetricIds.filter(x=>x!==id);
      if(state.overlayAId===id) state.overlayAId=state.enabledMetricIds[0]||'';
      if(state.overlayBId===id) state.overlayBId='';
      if(state.activePageMetricId===id) state.activePageMetricId=state.overlayAId||state.enabledMetricIds[0]||'';
    }else{
      state.enabledMetricIds.push(id);
      state.activePageMetricId=id;
      if(!state.dualOverlayEnabled){
        state.overlayAId=id;state.overlayBId='';state.focusedOverlaySlot='A';
      }else{
        if(!state.overlayAId) state.overlayAId=id;
        else if(!state.overlayBId&&id!==state.overlayAId) state.overlayBId=id;
        else if(state.focusedOverlaySlot==='A') state.overlayAId=id;
        else state.overlayBId=id;
      }
    }
    normalizeState(state,measures); return state;
  }

  function activateMetric(state,metricId,measures){
    normalizeState(state,measures); const id=text(metricId),metric=metricById(measures,id); if(!metric||metric.enabled===false||!state.enabledMetricIds.includes(id))return state;
    state.activePageMetricId=id;
    if(!state.dualOverlayEnabled){ state.overlayAId=id; state.overlayBId=''; state.focusedOverlaySlot='A'; }
    else if(id===state.overlayAId) state.focusedOverlaySlot='A';
    else if(id===state.overlayBId) state.focusedOverlaySlot='B';
    else if(state.focusedOverlaySlot==='A') state.overlayAId=id;
    else state.overlayBId=id;
    normalizeState(state,measures); return state;
  }

  function volumetricDualOverlayDisabledAttribute(state){return state.activeViewMode==='three_dimensional'||state.enabledMetricIds.length<2?' disabled':'';}

  function viewModeBarHtml(items,escapeFn,options){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml;
    const cfg=options&&typeof options==='object'?options:{};
    const buttons=arr(items).map(item=>{
      const id=text(item&&item.id),label=text(item&&item.label||id),active=!!(item&&item.active),disabled=!!(item&&item.disabled);
      const attributeName=text(cfg.attributeName||`data-${text(cfg.dataPrefix||'representation')}-view`);
      const attrs=[`${attributeName}="${esc(id)}"`,`aria-selected="${active?'true':'false'}"`];
      if(item&&item.extraAttributes)attrs.push(String(item.extraAttributes));
      if(disabled)attrs.push('disabled','aria-disabled="true"');
      const title=text(item&&item.tooltip||'');
      return `<button type="button" class="${active?'isActive':''}" ${attrs.join(' ')}${title?tooltipAttributesFromText(title,esc):''}>${esc(label)}</button>`;
    }).join('');
    return `<div class="rvImagingViewModeBar${cfg.inline===false?'':' rvImagingViewModeBar--inline'}${cfg.className?' '+esc(cfg.className):''}" role="tablist" aria-label="${esc(cfg.ariaLabel||'View mode')}">${buttons}</div>`;
  }

  function shellHtml(measures,state,escapeFn,rootId){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml,id=esc(text(rootId||'rvImagingViewerRoot')); normalizeState(state,measures);
    const surface=measuresAreSurface(measures),volumeDisabled=volumetricDualOverlayDisabledAttribute(state),dualUnavailable=surface?state.enabledMetricIds.length<2:!!volumeDisabled,threeDDisabled=THREE_D_SESSION_DISABLED;
    const tabs=metricTabsHtml(measures,state,esc),representationIds=surface?['imaging.3d.surface_data']:['imaging.2d','imaging.3d.surface','imaging.3d.volume'],representationItems=representationIds.map(representationId=>{const definition=featureRepresentationDefinition(representationId),twoDimensional=definition.adapterId==='imaging.2d',active=twoDimensional?state.activeViewMode==='orthogonal':state.activeViewMode==='three_dimensional'&&text(state.render3D&&state.render3D.renderingMode)===text(definition.entryMode),tooltip=representationId==='imaging.2d'?tooltipText('view2d'):(definition.entryMode==='volume_raycast'?tooltipText('view3dVolume'):tooltipText('view3dSurface'));return {id:definition.id,label:definition.label,active,disabled:!twoDimensional&&threeDDisabled,tooltip};});
    return `<div class="rvImagingViewer" id="${id}" data-imaging-status="loading">
      <div class="rvImagingTopbar">
        <div class="rvImagingPages" role="tablist" aria-label="Enabled imaging metric pages">${tabs}</div>
        ${viewModeBarHtml(representationItems,esc,{attributeName:'data-imaging-view-mode',ariaLabel:'Imaging view mode'})}
        <label class="rvImagingCheck rvImagingDualOverlayControl${dualUnavailable?' isUnavailable':''}" aria-disabled="${dualUnavailable?'true':'false'}"${tooltipAttributes('dualOverlay',esc)}><input type="checkbox" data-imaging-dual-toggle${state.dualOverlayEnabled?' checked':''}${dualUnavailable?' disabled':''}> Two overlays</label>
        <span class="rvImagingModeNote">${state.dualOverlayEnabled?(surface?'Two native vertex overlays':'A filled · B silhouettes'):'Single filled overlay'}</span>
        <details class="rvImagingStateControls" data-imaging-state-menu><summary${tooltipAttributes('viewerState',esc)}>Viewer state</summary><div class="rvImagingStateMenu" role="group" aria-label="Imaging viewer state files"><button type="button" data-imaging-state-save${tooltipAttributes('saveState',esc)}>Save viewer state</button><button type="button" data-imaging-state-load${tooltipAttributes('loadState',esc)}>Load viewer state</button><button type="button" data-imaging-state-reset${tooltipAttributes('resetState',esc)}>Reset viewer state</button><input type="file" accept=".nmivstate,application/json" data-imaging-state-file hidden></div></details>
      </div>
      <div class="rvImagingLoading" data-imaging-loading role="status">Preparing structural and feature-map assets…</div>
      <div class="rvImagingBody" data-imaging-body hidden></div>
    </div>`;
  }

  function metricTabsHtml(measures,state,escapeFn){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml;
    return state.enabledMetricIds.map(id=>{
      const m=metricById(measures,id)||{label:id},slot=id===state.overlayAId?'A':(id===state.overlayBId?'B':''),current=id===state.activePageMetricId;
      return `<button type="button" class="rvImagingPageTab${current?' isActive':''}${slot?' isSlot'+slot:''}" data-imaging-page="${esc(id)}" aria-selected="${current?'true':'false'}"${tooltipAttributesFromText(`Overlay page\nSelect ${m.label||id} as the active imaging metric.${slot?` It currently occupies overlay slot ${slot}.`:''}`,esc)}><span>${esc(m.label)}</span>${slot?`<b>${slot}</b>`:''}</button>`;
    }).join('');
  }

  function synchronizeMetricShell(root,state,measures){
    if(!root)return;
    const pages=root.querySelector('.rvImagingPages'),expected=state.enabledMetricIds.map(text),actual=pages?Array.from(pages.querySelectorAll('[data-imaging-page]')).map(btn=>text(btn.getAttribute('data-imaging-page'))):[];
    if(pages&&(actual.length!==expected.length||actual.some((id,index)=>id!==expected[index])))pages.innerHTML=metricTabsHtml(measures,state,escapeHtml);
    Array.from(root.querySelectorAll('[data-imaging-page]')).forEach(btn=>{
      const id=text(btn.getAttribute('data-imaging-page')),slot=id===state.overlayAId?'A':(id===state.overlayBId?'B':''),current=id===state.activePageMetricId;
      btn.classList.toggle('isActive',current);btn.classList.toggle('isSlotA',slot==='A');btn.classList.toggle('isSlotB',slot==='B');btn.setAttribute('aria-selected',current?'true':'false');
      let badge=btn.querySelector('b');if(slot){if(!badge){badge=document.createElement('b');btn.appendChild(badge);}badge.textContent=slot;}else if(badge)badge.remove();
    });
    const surface=measuresAreSurface(measures);
    const threeDDisabled=THREE_D_SESSION_DISABLED;Array.from(root.querySelectorAll('[data-imaging-view-mode]')).forEach(btn=>{const definition=featureRepresentationDefinition(btn.getAttribute('data-imaging-view-mode')),active=definition.adapterId==='imaging.2d'?state.activeViewMode==='orthogonal':state.activeViewMode==='three_dimensional'&&text(definition.entryMode)===text(state.render3D&&state.render3D.renderingMode),disabled=definition.adapterId!=='imaging.2d'&&threeDDisabled;btn.classList.toggle('isActive',active);btn.disabled=disabled;btn.setAttribute('aria-disabled',disabled?'true':'false');btn.setAttribute('aria-selected',active?'true':'false');});
    const dual=root.querySelector('[data-imaging-dual-toggle]'),dualUnavailable=state.enabledMetricIds.length<2||(!surface&&state.activeViewMode==='three_dimensional');if(dual){dual.checked=!!state.dualOverlayEnabled;dual.disabled=dualUnavailable;const label=dual.closest('.rvImagingDualOverlayControl');if(label){label.classList.toggle('isUnavailable',dualUnavailable);label.setAttribute('aria-disabled',dualUnavailable?'true':'false');}}
    const note=root.querySelector('.rvImagingModeNote');if(note)note.textContent=state.dualOverlayEnabled?(surface?'Two native vertex overlays':'A filled · B silhouettes'):'Single filled overlay';
  }

  function requestedMetricIds(state){
    const ids=[];
    if(state.dualOverlayEnabled){
      if(state.overlayAId)ids.push(text(state.overlayAId));
      if(state.overlayBId&&state.overlayBId!==state.overlayAId)ids.push(text(state.overlayBId));
    }else{
      const active=text(state.activePageMetricId||state.overlayAId);
      if(active)ids.push(active);
    }
    return uniqueText(ids);
  }

  function workspaceKey(spec,state){
    const measureKey=uniqueText(arr(spec&&spec.measureIds).map(text).filter(Boolean)).join(',')||requestedMetricIds(state).join(','),resultType=text(spec&&spec.resultType).toLowerCase(),subjectKey=resultType==='mli'?text(spec&&spec.subjectCaseId):'',templateId=text(spec&&spec.selectedTemplateId)||text(state&&state.selectedTemplateId),atlasId=text(spec&&spec.selectedAtlasId)||text(state&&state.selectedAtlasId);return ['C18d4.7b',resultType,spec.analysisIndex,spec.source,spec.targetIndex,spec.classifierIndex,spec.featureContextId,spec.backprojectionComponentId,subjectKey,measureKey,state.displayGridPolicy,templateId,atlasId,text(state.volumeAtlasPath),text(state.volumeAtlasDelimiter),text(state.volumeAtlasNameColumn),text(state.volumeAtlasDescriptorFile)].join('|');
  }

  function assetContentIdentity(meta){return text(meta&&(meta.contentHash||meta.dataHash||meta.hash||meta.cacheKey||meta.signatureHash));}
  /* Structural reuse is content-addressed and reference-sensitive. Feature
   * support is a separate scientific resource and does not define anatomy. */
  function workspaceStructuralIdentity(payload,dims){
    const p=payload||{},structural=p.structural||{},reference=p.spatialReference||{};
    return ['structural:volume:v2',assetContentIdentity(structural),arr(dims).join('x'),JSON.stringify(reference.affineVoxel1ToWorld||[])].join('|');
  }
  function workspaceStructuralReuseCompatible(previousRuntime,nextPayload,nextDims){const previousPayload=previousRuntime&&previousRuntime.payload||{},structuralHash=assetContentIdentity(nextPayload&&nextPayload.structural);return !!previousRuntime&&!!structuralHash&&assetContentIdentity(previousPayload.structural)===structuralHash&&workspaceStructuralIdentity(previousPayload,previousRuntime.dims)===workspaceStructuralIdentity(nextPayload,nextDims);}
  function reusableAsset(previousMeta,nextMeta,previousData,expectedLength){const left=assetContentIdentity(previousMeta),right=assetContentIdentity(nextMeta);return !!previousData&&previousData.length===expectedLength&&!!left&&left===right;}

  function retainedFeatureResourceReason(reason){const value=text(reason);return ['metric','metric_toggle','dual_overlay','mli_subject'].includes(value)||value==='scientific_selection';}

  /* loadFeatureResource  Replace only mutable feature materialization in a mounted imaging workspace.
   * Purpose: keep anatomy, display grid, atlas, native support and surface geometry resident while a compatible scientific or measure selection changes.
   * Authority and flow: the browser sends explicit identities from the mounted runtime to the MATLAB feature-resource authority; it never derives or substitutes scientific identity locally.
   * Invariants: a feature resource may change only feature overlays (and surface feature support). Structural/grid/geometry disagreement is reported as requiresWorkspace and is the only route back to full workspace construction.
   * Materialization and performance: no structural/atlas asset is fetched here. Volumetric native support is reused by exact content identity; native-surface geometry and all geometry-derived caches remain resident.
   * Failure semantics: malformed resource payloads fail explicitly. A controlled requiresWorkspace response is not an error and invokes the authoritative full-workspace lifecycle.
   * Side effects: updates the browser runtime cache for the requested scientific-selection key.
   * Consumers and dependencies: refreshScientificPayload; NMImagingFeatureSampling; NMResultsViewerSurfaceAdapter runtime contract. */
  async function loadFeatureResource(opts,root,measures,state,previousRuntime,reason){
    if(!previousRuntime)return {requiresWorkspace:true,message:'No resident imaging workspace is available.'};
    const totalStarted=performance.now(),previousPayload=previousRuntime.payload||{},requestedIds=requestedMetricIds(state),selectedTemplate=previousPayload.selectedTemplate||{},selectedAtlas=previousPayload.selectedAtlas||{},resident=previousPayload.residentMaterialization||{},nativeRuntime=previousRuntime.nativeFeatureSampling,nativeDescriptor=nativeRuntime&&nativeRuntime.descriptor||previousPayload.nativeFeatureSampling||{},surface=previousPayload.surface||{},nativeSurface=surface.native||{};
    const spec=opts.selectedSpec({
      measureIds:requestedIds,
      displayGridPolicy:text(previousPayload.displayGridPolicy||state.displayGridPolicy),
      selectedTemplateId:text(selectedTemplate.templateId||state.selectedTemplateId),
      selectedAtlasId:text(state.selectedAtlasId),
      residentDisplayGridId:text(previousPayload.spatialReference&&previousPayload.spatialReference.gridId),
      residentStructuralKey:text(resident.structuralKey),
      residentStructuralContentHash:assetContentIdentity(previousPayload.structural),
      residentSupportContentHash:assetContentIdentity(previousPayload.support),
      residentFeatureSpaceKey:text(resident.featureSpaceKey),
      residentDisplayScaffoldKey:text(resident.displayScaffoldKey),
      residentFeatureMappingId:text(resident.featureMappingId),
      residentAtlasId:text(selectedAtlas.available?selectedAtlas.atlasId:''),
      residentAtlasContentHash:assetContentIdentity(selectedAtlas),
      residentNativeGridId:text(nativeRuntime&&nativeRuntime.gridId||nativeDescriptor.gridId),
      residentNativeMappingId:text(nativeRuntime&&nativeRuntime.mappingId||nativeDescriptor.mappingId),
      residentNativeSupportContentHash:assetContentIdentity(nativeDescriptor.support),
      residentSurfaceVertexCount:Number(nativeSurface.nVertices||previousRuntime.surfaceRuntime&&previousRuntime.surfaceRuntime.nVertices||NaN),
      residentSurfaceGeometryIdentity:text(nativeSurface.geometryId),
      residentSurfaceTopologyIdentity:text(surface.topologyIdentity),
      residentSurfaceVertexOrderIdentity:text(surface.vertexOrderIdentity)
    });
    const key=workspaceKey(spec,state);
    if(RUNTIME_CACHE.has(key)){
      const cacheStarted=performance.now(),cached=RUNTIME_CACHE.get(key);runtimeCacheSet(key,cached);profile(opts,'feature resource cache lookup',cacheStarted,`hit=1 pending=${cached&&typeof cached.then==='function'?1:0} key=${key}`);
      try{const runtime=await cached;runtime.catalogueMeasures=measures;profile(opts,'feature resource cache wait',cacheStarted,`hit=1 overlays=${Object.keys(runtime&&runtime.overlays||{}).length}`);profile(opts,'feature resource load TOTAL',totalStarted,'cacheHit=1');return {runtime,requiresWorkspace:false};}catch(err){RUNTIME_CACHE.delete(key);throw err;}
    }
    profile(opts,'feature resource cache lookup',totalStarted,`hit=0 key=${key}`);
    const promise=(async()=>{
      const serviceStarted=performance.now(),res=await opts.matlabService({operation:'results_viewer_alpha_imaging_feature_resource',spec}),p=res&&res.payload;
      profile(opts,'MATLAB feature resource roundtrip',serviceStarted,`ok=${res&&res.ok!==false?1:0} requiresWorkspace=${p&&p.requiresWorkspace?1:0}`);
      if(p&&p.requiresWorkspace===true)return {requiresWorkspace:true,message:text(p.message)};
      if(!res||res.ok===false||!p||p.ok===false)throw new Error(p&&p.message||res&&res.message||'Imaging feature resource is unavailable.');
      if(text(p.schema)!=='NMImagingFeatureResourcePayload')throw new Error('Imaging feature-resource schema is invalid.');
      const contract=p.residentContract||{},requestedContext=text(spec&&spec.featureContextId),responseContext=text(p.selectedFeatureContextId);
      if(requestedContext&&responseContext!==requestedContext)throw new Error('Imaging feature resource does not match the requested scientific context.');
      if(text(p.sourceDomain)==='surface'){
        if(!isSurfaceRuntime(previousRuntime))throw new Error('A surface feature resource cannot update a volumetric runtime.');
        const sr=previousRuntime.surfaceRuntime,n=sr.nVertices,g=sr.geometries&&sr.geometries.native;
        if(Number(contract.vertexCount)!==n||text(contract.geometryIdentity)!==text(g&&g.geometryId)||text(contract.topologyIdentity)!==text(sr.topologyIdentity)||text(contract.vertexOrderIdentity)!==text(sr.vertexOrderIdentity))throw new Error('Surface feature resource geometry identity differs from the resident runtime.');
        const priorSupport=sr.support,priorSupportMeta=sr.supportMeta||previousPayload.support||{},supportMeta=p.support||{},support=reusableAsset(priorSupportMeta,supportMeta,priorSupport,n)?priorSupport:await opts.fetchArray(supportMeta.url,'uint8',n),overlays={};
        for(const meta of arr(p.overlays)){const id=text(meta.measureId),prior=sr.overlays&&sr.overlays[id],data=reusableAsset(prior&&prior.meta,meta,prior&&prior.data,n)?prior.data:await opts.fetchArray(meta.url,'float32',n);overlays[id]={meta,data};}
        const nextSurfaceRuntime=Object.assign({},sr,{support,supportMeta,overlays,canonicalROI:p.capabilities&&p.capabilities.canonicalROI===true,capabilities:p.capabilities||sr.capabilities});
        const nextPayload=Object.assign({},previousPayload,p,{surface:previousPayload.surface,selectedTemplate:previousPayload.selectedTemplate,templateCatalogue:previousPayload.templateCatalogue,selectedAtlas:previousPayload.selectedAtlas,atlasCatalogue:previousPayload.atlasCatalogue,spatialReference:previousPayload.spatialReference,dimensions:previousPayload.dimensions,initialVoxel:previousPayload.initialVoxel,initialWorldMm:previousPayload.initialWorldMm});
        return {runtime:{payload:nextPayload,dims:[n,1,1],structural:null,support,overlays,atlas:previousRuntime.atlas,nativeFeatureSampling:null,surfaceRuntime:nextSurfaceRuntime,key,catalogueMeasures:measures},requiresWorkspace:false};
      }
      if(text(p.sourceDomain)!=='volume'||isSurfaceRuntime(previousRuntime))throw new Error('Volumetric feature resource domain does not match the resident runtime.');
      const n=previousRuntime.dims[0]*previousRuntime.dims[1]*previousRuntime.dims[2];
      if(text(contract.structuralKey)!==text(resident.structuralKey)||text(contract.displayGridId)!==text(previousPayload.spatialReference&&previousPayload.spatialReference.gridId)||text(contract.structuralContentHash)!==assetContentIdentity(previousPayload.structural))throw new Error('Volumetric feature resource physical-space identity differs from the resident runtime.');
      const supportMeta=p.support,overlays={};for(const meta of arr(p.overlays)){const id=text(meta.measureId);overlays[id]={meta};}
      const nextNativePayload=Object.assign({},p.nativeFeatureSampling),samplingHelper=featureSamplingApi();if(typeof samplingHelper.prepareNativeFeatureSampling!=='function')throw new Error('Native feature sampling preparation is unavailable in the canonical browser authority.');
      const nextNative=samplingHelper.prepareNativeFeatureSampling(nextNativePayload,arr(p.overlays));if(!nextNative)throw new Error('Native feature resource did not provide the required sampling descriptor.');
      if(nativeRuntime&&typeof nextNative.reuseFrom==='function')nextNative.reuseFrom(nativeRuntime);
      const nextResident=p.residentMaterialization||{structuralKey:text(contract.structuralKey),featureSpaceKey:text(contract.featureSpaceKey),displayScaffoldKey:text(contract.displayScaffoldKey),featureMappingId:text(contract.featureMappingId),catalogueRevision:''};
      const nextPayload=Object.assign({},previousPayload,p,{structural:previousPayload.structural,support:supportMeta,residentMaterialization:nextResident,selectedTemplate:previousPayload.selectedTemplate,templateCatalogue:previousPayload.templateCatalogue,selectedAtlas:previousPayload.selectedAtlas,atlasCatalogue:previousPayload.atlasCatalogue,spatialReference:previousPayload.spatialReference,planeConvention:previousPayload.planeConvention,dimensions:previousPayload.dimensions,initialVoxel:previousPayload.initialVoxel,initialWorldMm:previousPayload.initialWorldMm,nativeFeatureSampling:nextNativePayload});
      return {runtime:{payload:nextPayload,dims:previousRuntime.dims.slice(),structural:previousRuntime.structural,support:null,overlays,atlas:previousRuntime.atlas,nativeFeatureSampling:nextNative,surfaceRuntime:null,key,catalogueMeasures:measures},requiresWorkspace:false};
    })();
    try{
      const result=await promise;
      if(result.requiresWorkspace){RUNTIME_CACHE.delete(key);profile(opts,'feature resource load TOTAL',totalStarted,`cacheHit=0 requiresWorkspace=1 reason=${text(result.message)}`);return result;}
      bindCanonicalROIStatistics(result.runtime);
      runtimeCacheSet(key,result.runtime);profile(opts,'feature resource load TOTAL',totalStarted,`cacheHit=0 overlays=${Object.keys(result.runtime.overlays).length}`);return result;
    }catch(err){RUNTIME_CACHE.delete(key);profile(opts,'feature resource load TOTAL',totalStarted,'cacheHit=0 failed=1');throw err;}
  }

  async function loadWorkspace(opts,root,measures,state,reuseRuntime,measureIdsOverride){
    const totalStarted=performance.now(),explicitMeasureIds=uniqueText(arr(measureIdsOverride).map(text).filter(Boolean));
    const spec=opts.selectedSpec({measureIds:explicitMeasureIds.length?explicitMeasureIds:requestedMetricIds(state),displayGridPolicy:state.displayGridPolicy,selectedTemplateId:state.selectedTemplateId,selectedAtlasId:state.selectedAtlasId,volumeAtlasPath:state.volumeAtlasPath,volumeAtlasDelimiter:state.volumeAtlasDelimiter,volumeAtlasNameColumn:state.volumeAtlasNameColumn,volumeAtlasDescriptorFile:state.volumeAtlasDescriptorFile});
    const key=workspaceKey(spec,state);
    if(RUNTIME_CACHE.has(key)){
      const cacheStarted=performance.now();
      const cached=RUNTIME_CACHE.get(key);
      runtimeCacheSet(key,cached);
      profile(opts,'workspace cache lookup',cacheStarted,`hit=1 pending=${cached&&typeof cached.then==='function'?1:0} key=${key}`);
      try{
        const runtime=await cached;runtime.catalogueMeasures=measures;
        profile(opts,'workspace cache wait',cacheStarted,`hit=1 overlays=${Object.keys(runtime&&runtime.overlays||{}).length}`);
        profile(opts,'workspace load TOTAL',totalStarted,'cacheHit=1');
        return runtime;
      }catch(err){
        RUNTIME_CACHE.delete(key);
        profile(opts,'workspace cache wait',cacheStarted,'hit=1 failed=1');
        throw err;
      }
    }
    profile(opts,'workspace cache lookup',totalStarted,`hit=0 key=${key}`);
    const promise=(async()=>{
      const serviceStarted=performance.now();
      const res=await opts.matlabService({operation:'results_viewer_alpha_imaging_workspace',spec});
      profile(opts,'MATLAB workspace roundtrip',serviceStarted,`ok=${res&&res.ok!==false?1:0}`);
      const p=res&&res.payload;
      if(!res||res.ok===false||!p||p.ok===false){
        const diagnostic=arr(p&&p.diagnostics)[0]||null;
        const parts=[];
        if(diagnostic&&diagnostic.source)parts.push(`Source: ${diagnostic.source}`);
        if(diagnostic&&diagnostic.exceptionIdentifier)parts.push(`Identifier: ${diagnostic.exceptionIdentifier}`);
        const primary=(p&&p.message)||(res&&res.message)||'Imaging workspace is unavailable.';
        parts.push(`Message: ${primary}`);
        if(diagnostic&&arr(diagnostic.stack).length)parts.push(`Stack: ${arr(diagnostic.stack).join(' <- ')}`);
        throw new Error(parts.join(' | '));
      }
      const dims=arr(p.dimensions).map(x=>Math.max(1,Math.round(Number(x))));
      if(dims.length!==3) throw new Error('Imaging payload dimensions are invalid.');
      const surfaceApi=surfaceAdapter();
      if(surfaceApi&&typeof surfaceApi.isSurfacePayload==='function'&&surfaceApi.isSurfacePayload(p)){
        const surfaceRuntime=await surfaceApi.hydrate(p,opts,reuseRuntime);let surfaceAtlas=null;
        if(p.selectedAtlas&&p.selectedAtlas.available&&p.selectedAtlas.url){stageStarted=performance.now();const n=surfaceRuntime.nVertices,prior=reuseRuntime&&reuseRuntime.atlas,data=reusableAsset(prior&&prior.meta,p.selectedAtlas,prior&&prior.data,n)?prior.data:await opts.fetchArray(p.selectedAtlas.url,'uint32',n);surfaceAtlas={meta:p.selectedAtlas,data};surfaceRuntime.atlas=surfaceAtlas;profile(opts,'surface provenance atlas hydrate',stageStarted,`atlas=${text(p.selectedAtlas.atlasId)} elements=${data.length}`);}
        const runtime={payload:p,dims:[surfaceRuntime.nVertices,1,1],structural:null,support:surfaceRuntime.support,overlays:surfaceRuntime.overlays,atlas:surfaceAtlas,nativeFeatureSampling:null,surfaceRuntime,key,catalogueMeasures:measures};
        return runtime;
      }
      const samplingHelper=featureSamplingApi();
      if(typeof samplingHelper.prepareNativeFeatureSampling!=='function')throw new Error('Native feature sampling preparation is unavailable in the canonical browser authority.');
      const nativeFeatureSampling=samplingHelper.prepareNativeFeatureSampling(p.nativeFeatureSampling,arr(p.overlays));
      if(nativeFeatureSampling&&reuseRuntime&&reuseRuntime.nativeFeatureSampling&&typeof nativeFeatureSampling.reuseFrom==='function'){const reused=nativeFeatureSampling.reuseFrom(reuseRuntime.nativeFeatureSampling);profile(opts,'native feature asset reuse',totalStarted,`support=${reused.support?1:0} overlays=${reused.overlays||0} loaded=${reused.loaded?1:0}`);}
      const n=dims[0]*dims[1]*dims[2];
      const hydrationStarted=performance.now();
      const priorPayload=reuseRuntime&&reuseRuntime.payload||{},sameStructural=workspaceStructuralReuseCompatible(reuseRuntime,p,dims);
      const support=null,overlays={};for(const ov of arr(p.overlays)){const id=text(ov.measureId);overlays[id]={meta:ov};}
      const structuralStarted=performance.now(),reusedStructural=sameStructural&&reuseRuntime.structural&&reuseRuntime.structural.length===n;
      const structuralPromise=(reusedStructural?Promise.resolve(reuseRuntime.structural):opts.fetchArray(p.structural.url,'float32',n)).then(structural=>{profile(opts,'structural asset hydrate',structuralStarted,`elements=${structural.length} bytes=${structural.byteLength||0} reused=${reusedStructural?1:0}`);return structural;});
      const selectedAtlas=p.selectedAtlas,nativeAtlasEncoding=selectedAtlas.available&&text(selectedAtlas.storageEncoding)==='native_nearest_v1';
      let nativePromise=Promise.resolve(nativeFeatureSampling);
      if(nativeFeatureSampling&&(state.activeViewMode==='orthogonal'||state.activeViewMode==='three_dimensional'||nativeAtlasEncoding)){
        if(typeof nativeFeatureSampling.load!=='function')throw new Error('The authoritative native-grid feature source required by the imaging viewer is unavailable.');
        const nativeStarted=performance.now();nativePromise=nativeFeatureSampling.load(opts.fetchArray).then(runtime=>{profile(opts,'native feature assets preload',nativeStarted,`view=${state.activeViewMode} grid=${text(runtime.gridId)} overlays=${Object.keys(runtime.overlays).length}`);return runtime;});
      }
      let atlasPromise=Promise.resolve(null);
      if(selectedAtlas.available&&selectedAtlas.url){
        const atlasStarted=performance.now(),prior=reuseRuntime&&reuseRuntime.atlas,reusedAtlas=reusableAsset(prior&&prior.meta,selectedAtlas,prior&&prior.data,n);
        if(reusedAtlas)atlasPromise=Promise.resolve({meta:selectedAtlas,data:prior.data});
        else if(nativeAtlasEncoding){
          if(text(selectedAtlas.sourceGridId)!==text(nativeFeatureSampling&&nativeFeatureSampling.gridId))throw new Error('Compact canonical ROI atlas source grid does not match the authoritative native feature grid.');
          const sourceCount=Number(selectedAtlas.elementCount),sourcePromise=opts.fetchArray(selectedAtlas.url,text(selectedAtlas.dataType),sourceCount);
          atlasPromise=Promise.all([sourcePromise,nativePromise]).then(values=>{const source=values[0],native=values[1],materializeStarted=performance.now();if(typeof samplingHelper.materializeNearestLabels!=='function')throw new Error('Canonical nearest-neighbour atlas materialization is unavailable.');const data=samplingHelper.materializeNearestLabels(dims,p.spatialReference,native,source);profile(opts,'native atlas asset hydrate',atlasStarted,`atlas=${text(selectedAtlas.atlasId)} elements=${source.length} bytes=${source.byteLength||0}`);profile(opts,'display atlas nearest materialization',materializeStarted,`elements=${data.length}`);return {meta:selectedAtlas,data};});
        }else atlasPromise=opts.fetchArray(selectedAtlas.url,'uint32',n).then(data=>{profile(opts,'atlas asset hydrate',atlasStarted,`atlas=${text(selectedAtlas.atlasId)} elements=${data.length} bytes=${data.byteLength||0} reused=0`);return {meta:selectedAtlas,data};});
      }
      const hydrated=await Promise.all([structuralPromise,atlasPromise,nativePromise]),structural=hydrated[0],atlas=hydrated[1];
      profile(opts,'display feature asset hydrate',hydrationStarted,`skipped=1 authority=native_feature_grid overlays=${Object.keys(overlays).length}`);
      profile(opts,'all binary assets hydrate TOTAL',hydrationStarted,`elementsPerVolume=${n} overlays=${Object.keys(overlays).length} atlas=${atlas?1:0}`);
      return {payload:p,dims,structural,support,overlays,atlas,nativeFeatureSampling,key,catalogueMeasures:measures};
    })();
    runtimeCacheSet(key,promise);
    try{
      const runtime=await promise;
      bindCanonicalROIStatistics(runtime);
      const resolvedAtlas=runtime.payload&&runtime.payload.selectedAtlas;
      const resolvedSpec=Object.assign({},spec,{
        selectedTemplateId:text(runtime.payload&&runtime.payload.selectedTemplate&&runtime.payload.selectedTemplate.templateId)||text(spec.selectedTemplateId),
        selectedAtlasId:resolvedAtlas&&resolvedAtlas.available?text(resolvedAtlas.atlasId):text(spec.selectedAtlasId)
      }),resolvedKey=workspaceKey(resolvedSpec,state);
      runtime.key=resolvedKey;
      if(resolvedKey!==key){
        RUNTIME_CACHE.delete(key);
        profile(opts,'workspace cache canonical rekey',totalStarted,`provisional=${key} resolved=${resolvedKey}`);
      }
      runtimeCacheSet(resolvedKey,runtime);
      profile(opts,'workspace load TOTAL',totalStarted,`cacheHit=0 overlays=${Object.keys(runtime.overlays).length} atlas=${runtime.atlas?1:0}`);
      return runtime;
    }catch(err){
      RUNTIME_CACHE.delete(key);
      profile(opts,'workspace load TOTAL',totalStarted,'cacheHit=0 failed=1');
      throw err;
    }
  }


  async function pickSurfaceAtlasPath(initial,surface=true){
    const response=await fetch('/api/pickpath',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({kind:'file',multiple:false,initial:text(initial),filter:surface?'*.annot':'*.nii;*.nii.gz;*.img;*.hdr',title:surface?'Select one lh.*.annot or rh.*.annot surface atlas file':'Select a volumetric ROI atlas',timeout:600})});
    if(!response.ok)throw new Error(`Imaging atlas file picker failed: HTTP ${response.status}`);
    const out=await response.json();if(out&&out.error)throw new Error(out.error);const paths=arr(out&&out.paths);return paths.length?text(paths[0]):'';
  }

  async function loadSurfaceAtlas(runtime,state,opts,selectedPath){
    if(!isSurfaceRuntime(runtime))throw new Error('Surface atlas loading requires a mounted native-surface runtime.');
    const path=text(selectedPath);if(!path)throw new Error('No surface annotation file was selected.');
    const sr=runtime.surfaceRuntime,spec=opts.selectedSpec({surfaceAtlasPath:path,surfaceVertexCount:sr.nVertices,varind:Number(runtime.payload&&runtime.payload.surfaceModalityIndex||0),selectedTemplateId:state.selectedTemplateId});
    const response=await opts.matlabService({operation:'results_viewer_alpha_surface_atlas',spec}),payload=response&&response.payload;
    if(!response||response.ok===false||!payload||payload.ok===false)throw new Error(payload&&payload.message||response&&response.message||'The selected surface atlas is incompatible.');
    if(text(payload.topologyIdentity)!==text(sr.topologyIdentity)||text(payload.vertexOrderIdentity)!==text(sr.vertexOrderIdentity))throw new Error('The surface atlas was resolved against a different topology or vertex order.');
    const data=await opts.fetchArray(payload.url,'uint32',sr.nVertices);if(data.length!==sr.nVertices)throw new Error('The surface atlas label vector has an invalid vertex count.');
    payload.selectionId='surface_annot_file';runtime.atlas={meta:payload,data};sr.atlas=runtime.atlas;
    runtime.payload.selectedAtlas=Object.assign({},payload,{selectionId:'surface_annot_file',available:true,labelMessage:`Viewer-local FreeSurfer annotation pair: ${text(payload.lhPath)} | ${text(payload.rhPath)}`});
    state.selectedAtlasId=text(payload.atlasId);state.surfaceAtlasPaths={selectedPath:text(payload.selectedPath||path),lhPath:text(payload.lhPath),rhPath:text(payload.rhPath)};
    return runtime.atlas;
  }

  function featureSamplingApi(){const api=window.NMImagingFeatureSampling;if(!api)throw new Error('The canonical imaging feature-sampling authority is unavailable.');return api;}
  function nativeFeatureRuntime(runtime){
    if(isSurfaceRuntime(runtime))return runtime.surfaceRuntime;
    const native=runtime&&runtime.nativeFeatureSampling;
    if(!native||!native.loaded||!native.support)throw new Error('The authoritative native-grid feature source is not hydrated.');
    return native;
  }
  function nativeFeatureSupport(runtime){return nativeFeatureRuntime(runtime).support;}
  function nativeFeatureOverlay(runtime,measureId){
    const id=text(measureId);if(isSurfaceRuntime(runtime)){const record=surfaceAdapter().overlay(runtime,id);return record?{meta:record.meta,data:record.data,statisticsData:record.statisticsData}:null;}
    const native=nativeFeatureRuntime(runtime),record=native.overlay(id),display=runtime&&runtime.overlays&&runtime.overlays[id];
    if(!record||!display)return null;
    native._authorityOverlays=native._authorityOverlays||{};
    let overlay=native._authorityOverlays[id];
    if(!overlay||overlay.data!==record.data){
      const legacyDefaults=display.meta&&display.meta.displayDefaults||{},nativeDefaults=Object.assign({},legacyDefaults);if(display.statisticsData==null){nativeDefaults.thresholdProvenance='native_supported_nonzero_polarity_quantile';delete nativeDefaults.thresholdLow;delete nativeDefaults.thresholdHigh;delete nativeDefaults.thresholdValue;}
      overlay={meta:Object.assign({},display.meta||{},record.meta||{},{measureId:id,displayDefaults:nativeDefaults}),data:record.data,statisticsData:display.statisticsData};
      native._authorityOverlays[id]=overlay;
    }
    return overlay;
  }
  function focusedEditingOverlayId(state){return state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId);}
  function editingOverlay(runtime,state){const id=focusedEditingOverlayId(state),native=nativeFeatureOverlay(runtime,id);return native||(runtime&&runtime.overlays&&runtime.overlays[id]||null);}
  function editingSupport(runtime,state){const native=nativeFeatureRuntime(runtime);return native&&native.loaded&&native.support?native.support:(runtime&&runtime.support||null);}

  function nativeDisplayTransform(runtime){
    const native=nativeFeatureRuntime(runtime),api=featureSamplingApi();
    if(typeof api.displayToNativeVoxelMatrix!=='function')throw new Error('Native-grid coordinate transform support is unavailable.');
    if(!native._displayVoxel1ToNativeVoxel1)native._displayVoxel1ToNativeVoxel1=api.displayToNativeVoxelMatrix(runtime.payload.spatialReference,native);
    return native._displayVoxel1ToNativeVoxel1;
  }
  function nativeVoxelAtDisplayVoxel0(runtime,displayVoxel0){
    const api=featureSamplingApi();if(typeof api.displayVoxel0ToNativeVoxel1!=='function')throw new Error('Native-grid point transformation support is unavailable.');
    return api.displayVoxel0ToNativeVoxel1(nativeDisplayTransform(runtime),displayVoxel0);
  }

  function metricDisplayState(state,overlay,support){
    const id=text(overlay&&overlay.meta&&overlay.meta.measureId),defaults=overlay&&overlay.meta&&overlay.meta.displayDefaults||{};let st=state.perMetricDisplayState[id];if(!st||typeof st!=='object')st={};
    st.thresholdProvenance=text(st.thresholdProvenance||defaults.thresholdProvenance||'supported_nonzero_polarity_quantile');
    const resolved=displaySemantics().resolveDisplayState(st,overlay,support,{defaultOpacity:.85},{measureId:id,pathway:'imaging'});st=resolved.state;state.perMetricDisplayState[id]=st;return st;
  }





  function volumeIndex(dims,i,j,k){ return i+dims[0]*(j+dims[1]*k); }
  function fallbackPlaneDefinition(dims,plane){
    if(plane==='axial')return {planeId:'axial',displayLabel:'Axial (native K)',conventionMode:'legacy_fallback',normalVoxelAxis:3,horizontalVoxelAxis:2,verticalVoxelAxis:1,horizontalDirection:1,verticalDirection:1,width:dims[1],height:dims[0],maxSlice:dims[2],orientationLabels:{left:'-J',right:'+J',top:'-I',bottom:'+I'},sliceDirectionLabels:{low:'-K',high:'+K'}};
    if(plane==='coronal')return {planeId:'coronal',displayLabel:'Coronal (native J)',conventionMode:'legacy_fallback',normalVoxelAxis:2,horizontalVoxelAxis:1,verticalVoxelAxis:3,horizontalDirection:1,verticalDirection:-1,width:dims[0],height:dims[2],maxSlice:dims[1],orientationLabels:{left:'-I',right:'+I',top:'+K',bottom:'-K'},sliceDirectionLabels:{low:'-J',high:'+J'}};
    return {planeId:'sagittal',displayLabel:'Sagittal (native I)',conventionMode:'legacy_fallback',normalVoxelAxis:1,horizontalVoxelAxis:2,verticalVoxelAxis:3,horizontalDirection:1,verticalDirection:-1,width:dims[1],height:dims[2],maxSlice:dims[0],orientationLabels:{left:'-J',right:'+J',top:'+K',bottom:'-K'},sliceDirectionLabels:{low:'-I',high:'+I'}};
  }
  function planeDefinition(runtime,plane){
    const dims=runtime.dims;
    const candidate=arr(runtime.payload&&runtime.payload.planeConvention&&runtime.payload.planeConvention.planes).find(p=>text(p&&p.planeId)===plane);
    if(!candidate)return fallbackPlaneDefinition(dims,plane);
    const n=clamp(Math.round(finite(candidate.normalVoxelAxis,1)),1,3),h=clamp(Math.round(finite(candidate.horizontalVoxelAxis,1)),1,3),v=clamp(Math.round(finite(candidate.verticalVoxelAxis,1)),1,3);
    if(new Set([n,h,v]).size!==3)return fallbackPlaneDefinition(dims,plane);
    return Object.assign({},candidate,{normalVoxelAxis:n,horizontalVoxelAxis:h,verticalVoxelAxis:v,horizontalDirection:finite(candidate.horizontalDirection,1)<0?-1:1,verticalDirection:finite(candidate.verticalDirection,1)<0?-1:1,width:dims[h-1],height:dims[v-1],maxSlice:dims[n-1],orientationLabels:candidate.orientationLabels||{},sliceDirectionLabels:candidate.sliceDirectionLabels||{}});
  }
  function planeGeometry(runtime,plane){ const d=planeDefinition(runtime,plane);return {w:d.width,h:d.height,max:d.maxSlice,definition:d}; }
  function pixelToVoxel0(runtime,plane,col,row,currentVoxel1){
    const dims=runtime.dims,d=planeDefinition(runtime,plane),voxel=arr(currentVoxel1).slice(0,3).map(x=>clamp(Math.round(finite(x,1))-1,0,Number.MAX_SAFE_INTEGER));
    const h=d.horizontalVoxelAxis-1,v=d.verticalVoxelAxis-1,n=d.normalVoxelAxis-1;
    voxel[h]=d.horizontalDirection>0?col:dims[h]-1-col;
    voxel[v]=d.verticalDirection>0?row:dims[v]-1-row;
    voxel[n]=clamp(Math.round(finite(currentVoxel1[n],1))-1,0,dims[n]-1);
    return voxel;
  }
  function validVoxel(v){return arr(v).length===3&&arr(v).every(x=>Number.isFinite(Number(x)));}
  function planeVoxel(state,runtime,plane){
    const local=state.planes&&state.planes[plane]&&state.planes[plane].voxel;
    const source=state.syncViews||!validVoxel(local)?state.currentVoxel:local;
    return arr(source).slice(0,3).map((x,i)=>clamp(Math.round(finite(x,1)),1,runtime.dims[i]));
  }
  function setPlaneVoxel(state,runtime,plane,voxel){
    const v=arr(voxel).slice(0,3).map((x,i)=>clamp(Math.round(finite(x,1)),1,runtime.dims[i]));
    if(state.syncViews){state.currentVoxel=v.slice();PLANES.forEach(p=>state.planes[p].voxel=v.slice());}
    else{state.planes[plane].voxel=v.slice();state.currentVoxel=v.slice();}
  }
  function currentSlice(state,runtime,plane){ const d=planeDefinition(runtime,plane);return planeVoxel(state,runtime,plane)[d.normalVoxelAxis-1]; }
  function setPlaneSlice(state,runtime,plane,value){ const d=planeDefinition(runtime,plane),axis=d.normalVoxelAxis-1,v=planeVoxel(state,runtime,plane);v[axis]=clamp(Math.round(value),1,runtime.dims[axis]);setPlaneVoxel(state,runtime,plane,v); }
  function crosshairPosition(runtime,state,plane){
    const d=planeDefinition(runtime,plane),dims=runtime.dims,h=d.horizontalVoxelAxis-1,v=d.verticalVoxelAxis-1,pv=planeVoxel(state,runtime,plane);
    const hv=clamp(Math.round(pv[h]),1,dims[h]),vv=clamp(Math.round(pv[v]),1,dims[v]);
    return {x:d.horizontalDirection>0?hv-.5:dims[h]-hv+.5,y:d.verticalDirection>0?vv-.5:dims[v]-vv+.5};
  }
  function voxelToWorld(reference,voxel){
    const m=reference&&reference.affineVoxel1ToWorld;
    if(!Array.isArray(m)||m.length!==4) return [NaN,NaN,NaN];
    const v=[Number(voxel[0]),Number(voxel[1]),Number(voxel[2]),1];
    return [0,1,2].map(r=>arr(m[r]).slice(0,4).reduce((sum,x,c)=>sum+Number(x)*v[c],0));
  }

  /** Build one typed interaction identity from the current imaging selection without owning selection state. */
  function currentInteractionIdentity(runtime,state,options){
    if(!runtime||!state)return null;
    const cfg=options&&typeof options==='object'?options:{},threeDimensional=state.activeViewMode==='three_dimensional',renderingMode=text(state.render3D&&state.render3D.renderingMode),representation=isSurfaceRuntime(runtime)?'surface':(threeDimensional?(renderingMode==='volume_raycast'?'volume':'surface_projection'):'orthogonal'),source={pathway:'imaging',representation,contextId:text(runtime.payload&&runtime.payload.selectedFeatureContextId||runtime.payload&&runtime.payload.contentId),measureId:text(state.activePageMetricId)};
    if(isSurfaceRuntime(runtime)){
      const selection=state.render3D&&state.render3D.selection||{},candidate=Number.isInteger(Number(selection.vertexIndex))?Number(selection.vertexIndex):Math.round(finite(state.currentVoxel&&state.currentVoxel[0],NaN))-1,world=arr(selection.sourceWorldMm&&selection.sourceWorldMm.length===3?selection.sourceWorldMm:state.currentWorldMm).slice(0,3).map(Number);
      if(!Number.isInteger(candidate)||candidate<0||world.length!==3||!world.every(Number.isFinite))return null;
      const api=surfaceAdapter(),geometry=api.geometry(runtime,state),hemisphere=text(api.hemisphereAtVertex(runtime,candidate));
      return interactionIdentity().createSurfaceVertex({source,vertexIndex:candidate,worldMm:world,sourceVoxel:[candidate+1,1,1],sourceWorldMm:world,topologyIdentity:text(runtime.surfaceRuntime&&runtime.surfaceRuntime.topologyIdentity),vertexOrderIdentity:text(runtime.surfaceRuntime&&runtime.surfaceRuntime.vertexOrderIdentity),geometryId:text(geometry&&geometry.geometryId||state.selectedTemplateId||'native'),hemisphere});
    }
    const selection=threeDimensional&&state.render3D&&state.render3D.selection||{},voxel=arr(cfg.voxel||selection.sourceVoxel&&selection.sourceVoxel.length===3&&selection.sourceVoxel||state.currentVoxel).slice(0,3).map(x=>Math.round(Number(x))),worldCandidate=arr(cfg.worldMm||selection.sourceWorldMm&&selection.sourceWorldMm.length===3&&selection.sourceWorldMm||state.currentWorldMm).slice(0,3).map(Number),world=worldCandidate.length===3&&worldCandidate.every(Number.isFinite)?worldCandidate:voxelToWorld(runtime.payload&&runtime.payload.spatialReference,voxel);
    if(voxel.length!==3||!voxel.every(Number.isFinite)||world.length!==3||!world.every(Number.isFinite))return null;
    return interactionIdentity().createVoxel({source,voxel,worldMm:world,planeId:text(cfg.planeId||state.lastPlaneId),gridId:text(runtime.payload&&runtime.payload.spatialReference&&runtime.payload.spatialReference.gridId||runtime.payload&&runtime.payload.gridId||runtime.payload&&runtime.payload.contentId)});
  }


  function overlayColor(value,klass,display,range){
    void klass;void range;
    const rgb=colorGradient().sampleContractRgb255(value,displayContract(display));return [rgb[0],rgb[1],rgb[2],255];
  }

  function activeDisplayRange(overlay,display,support){void overlay;void support;const contract=displayContract(display);return [contract.shownRange.lower,contract.shownRange.upper];}


  function atlasLookupAtVoxel(runtime,voxel1){
    if(!runtime||!runtime.atlas||!runtime.atlas.data) return {code:0,label:'No atlas selected',status:'unavailable'};
    const v=arr(voxel1).slice(0,3).map(x=>Math.round(Number(x))-1);
    if(v.length!==3||v.some((x,i)=>!Number.isFinite(x)||x<0||x>=runtime.dims[i])) return {code:0,label:'Outside atlas',status:'outside'};
    const code=Number(runtime.atlas.data[volumeIndex(runtime.dims,v[0],v[1],v[2])]);
    if(!code) return {code:0,label:'Unlabelled',status:'unlabelled'};
    const labels=runtime.atlas.meta.roiLabels||{};
    return {code,label:text(labels['roi_'+code]||('ROI '+code)),status:'labelled'};
  }

  function atlasLabel(runtime,state){
    return atlasLookupAtVoxel(runtime,planeVoxel(state,runtime,state.lastPlaneId)).label;
  }

  function updateAtlasReadout(root,runtime,state,voxel1,isHover){
    const lookup=atlasLookupAtVoxel(runtime,voxel1||planeVoxel(state,runtime,state.lastPlaneId)),shown=lookup.status==='labelled'?lookup.label:'—',source=isHover?'Pointer location':'Selected coordinate';
    informationControls().update(root,{fields:[{id:'roi',value:shown,ariaLabel:lookup.label,tooltip:`${tooltipText('roiReadout')}\n${source}: ${lookup.label}`} ]});
    const footerNode=root.querySelector('[data-rv-information-field="roi"]');
    footerNode.dataset.roiCode=String(lookup.code||0);footerNode.dataset.roiStatus=lookup.status;footerNode.dataset.roiSource=isHover?'hover':'selected';
  }

  function eventVoxel1(runtime,state,plane,event,canvas){
    const rect=canvas.getBoundingClientRect();
    if(rect.width<=0||rect.height<=0||event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)return null;
    const g=planeGeometry(runtime,plane);
    const sourceW=Math.max(1,Math.round(finite(canvas.dataset.sourceWidth,g.w)));
    const sourceH=Math.max(1,Math.round(finite(canvas.dataset.sourceHeight,g.h)));
    const col=clamp(Math.floor((event.clientX-rect.left)/rect.width*sourceW),0,sourceW-1);
    const row=clamp(Math.floor((event.clientY-rect.top)/rect.height*sourceH),0,sourceH-1);
    return pixelToVoxel0(runtime,plane,col,row,planeVoxel(state,runtime,plane)).map(x=>x+1);
  }

  function normalizedDisplayInterpolation(value){
    const mode=text(value).toLowerCase();
    return ['nearest','linear','high_quality'].includes(mode)?mode:'high_quality';
  }

  function configureCanvasInterpolation(ctx,mode){
    if(!ctx)return;
    mode=normalizedDisplayInterpolation(mode);
    ctx.imageSmoothingEnabled=mode!=='nearest';
    if('imageSmoothingQuality' in ctx)ctx.imageSmoothingQuality=mode==='high_quality'?'high':'low';
  }

  function drawPlaneCrosshair(ctx,runtime,state,plane,width,height){
    if(!ctx||!state.crosshairVisible)return;
    const g=planeGeometry(runtime,plane),point=crosshairPosition(runtime,state,plane);
    const x=point.x/g.w*width,y=point.y/g.h*height;
    ctx.save();ctx.lineWidth=Math.max(1,.9/Math.max(1,state.planes[plane].zoom));ctx.strokeStyle='rgba(0,153,255,.82)';
    ctx.beginPath();ctx.moveTo(0,y);ctx.lineTo(width,y);ctx.moveTo(x,0);ctx.lineTo(x,height);ctx.stroke();ctx.restore();
  }

  function planeIndexPlan(runtime,plane){
    runtime._interactive2D=runtime._interactive2D||{plans:{},rasters:{}};
    if(runtime._interactive2D.plans[plane])return runtime._interactive2D.plans[plane];
    const dims=runtime.dims,g=planeGeometry(runtime,plane),d=g.definition,h=d.horizontalVoxelAxis-1,v=d.verticalVoxelAxis-1,n=d.normalVoxelAxis-1,strides=[1,dims[0],dims[0]*dims[1]],offsets=new Uint32Array(g.w*g.h);
    for(let row=0;row<g.h;row++){
      const vv=d.verticalDirection>0?row:dims[v]-1-row,rowOffset=vv*strides[v];
      for(let col=0;col<g.w;col++){
        const hv=d.horizontalDirection>0?col:dims[h]-1-col;
        offsets[row*g.w+col]=rowOffset+hv*strides[h];
      }
    }
    const plan={w:g.w,h:g.h,max:g.max,normalAxis:n,normalStride:strides[n],offsets};
    runtime._interactive2D.plans[plane]=plan;return plan;
  }

  function displayRasterSignature(display){
    if(!display)return '';
    const contract=displayContract(display),threshold=contract.threshold||{},range=contract.shownRange||{},stops=arr(contract.colorStops).map(stop=>`${text(stop&&stop.position)}@${text(stop&&stop.color)}`).join(',');
    return [threshold.mode,threshold.lower,threshold.upper,threshold.value,contract.opacity,range.lower,range.upper,stops].map(text).join(':');
  }

  function planeStructuralRasterSignature(runtime,state,plane){
    return ['anatomy',workspaceStructuralIdentity(runtime&&runtime.payload,runtime&&runtime.dims),assetContentIdentity(runtime&&runtime.payload&&runtime.payload.structural),Math.round(currentSlice(state,runtime,plane)),state.backgroundBrightness,state.anatomyGamma].map(text).join('|');
  }
  function planeFeatureRasterSignature(runtime,state,plane){
    const support=nativeFeatureSupport(runtime),a=nativeFeatureOverlay(runtime,state.overlayAId)||nativeFeatureOverlay(runtime,state.activePageMetricId),b=state.dualOverlayEnabled?nativeFeatureOverlay(runtime,state.overlayBId):null,aDisplay=a?metricDisplayState(state,a,support):null,bDisplay=b?metricDisplayState(state,b,support):null,native=nativeFeatureRuntime(runtime),atlasIdentity=runtime&&runtime.atlas?assetContentIdentity(runtime.atlas.meta):'';
    return ['feature',native.gridId,native.mappingId,Math.round(currentSlice(state,runtime,plane)),effectiveFeatureInterpolation(runtime,state),a&&a.meta&&a.meta.measureId||'',displayRasterSignature(aDisplay),b&&b.meta&&b.meta.measureId||'',displayRasterSignature(bDisplay),state.dualOverlaySilhouetteNegativeColor,state.dualOverlaySilhouettePositiveColor,state.atlasBoundariesVisible?1:0,atlasIdentity,state.atlasBoundaryColor,state.atlasBoundaryOpacity].map(text).join('|');
  }

  function ensurePlaneRaster(runtime,plane){
    runtime._interactive2D=runtime._interactive2D||{plans:{},rasters:{}};
    const plan=planeIndexPlan(runtime,plane);let cache=runtime._interactive2D.rasters[plane];
    if(!cache||cache.w!==plan.w||cache.h!==plan.h){
      const scratch=document.createElement('canvas');scratch.width=plan.w;scratch.height=plan.h;const ctx=scratch.getContext('2d',{alpha:false}),featureScratch=document.createElement('canvas');featureScratch.width=plan.w;featureScratch.height=plan.h;const featureCtx=featureScratch.getContext('2d',{alpha:true});
      cache={w:plan.w,h:plan.h,scratch,ctx,image:ctx?ctx.createImageData(plan.w,plan.h):null,featureScratch,featureCtx,featureImage:featureCtx?featureCtx.createImageData(plan.w,plan.h):null,aClass:new Int8Array(plan.w*plan.h),bClass:new Int8Array(plan.w*plan.h),aCoverage:new Float32Array(plan.w*plan.h),bCoverage:new Float32Array(plan.w*plan.h),atlasSlice:new Uint32Array(plan.w*plan.h),signature:'',structuralSignature:'',featureSignature:'',renderCount:0,structuralRenderCount:0,featureRenderCount:0};
      runtime._interactive2D.rasters[plane]=cache;
    }
    return cache;
  }

  function planeNativeSamplingPlan(runtime,plane,slice1){
    runtime._interactive2D=runtime._interactive2D||{plans:{},rasters:{},nativePlans:{}};
    runtime._interactive2D.nativePlans=runtime._interactive2D.nativePlans||{};
    const native=nativeFeatureRuntime(runtime),key=[plane,Math.round(slice1),native.gridId,native.mappingId].join('|');
    if(runtime._interactive2D.nativePlans[key])return runtime._interactive2D.nativePlans[key];
    const api=featureSamplingApi();if(typeof api.transformPoint!=='function')throw new Error('Native-grid plane transformation support is unavailable.');
    const definition=planeDefinition(runtime,plane),dims=runtime.dims,h=definition.horizontalVoxelAxis-1,v=definition.verticalVoxelAxis-1,n=definition.normalVoxelAxis-1,matrix=nativeDisplayTransform(runtime),base=[1,1,1];
    base[h]=definition.horizontalDirection>0?1:dims[h];base[v]=definition.verticalDirection>0?1:dims[v];base[n]=clamp(Math.round(slice1),1,dims[n]);
    const nextH=base.slice(),nextV=base.slice();nextH[h]+=definition.horizontalDirection;nextV[v]+=definition.verticalDirection;
    const nativeBase=api.transformPoint(matrix,base),nativeH=api.transformPoint(matrix,nextH),nativeV=api.transformPoint(matrix,nextV);
    if([nativeBase,nativeH,nativeV].some(point=>point.some(value=>!Number.isFinite(value))))throw new Error('The display-to-native feature transform produced a non-finite plane coordinate.');
    const plan={base:nativeBase,stepH:nativeH.map((value,index)=>value-nativeBase[index]),stepV:nativeV.map((value,index)=>value-nativeBase[index])};
    runtime._interactive2D.nativePlans[key]=plan;return plan;
  }

  function updatePlanePresentation(runtime,state,plane,canvas){
    if(!canvas)return;
    const g=planeGeometry(runtime,plane),frame=canvas.closest('.rvImagingPlaneFrame'),raster=canvas.closest('[data-imaging-raster]'),ps=state.planes[plane],mode=normalizedDisplayInterpolation(state.anatomyInterpolation);
    canvas.dataset.sourceWidth=String(g.w);canvas.dataset.sourceHeight=String(g.h);canvas.dataset.displayInterpolation=mode;canvas.style.imageRendering=mode==='nearest'?'pixelated':'auto';
    if(canvas.width!==g.w)canvas.width=g.w;if(canvas.height!==g.h)canvas.height=g.h;
    const featureCanvas=canvas.parentElement&&canvas.parentElement.querySelector(`[data-imaging-feature-canvas="${plane}"]`);if(featureCanvas){featureCanvas.width=g.w;featureCanvas.height=g.h;featureCanvas.dataset.sourceWidth=String(g.w);featureCanvas.dataset.sourceHeight=String(g.h);const interpolation=effectiveFeatureInterpolation(runtime,state);featureCanvas.dataset.featureInterpolation=interpolation;featureCanvas.style.imageRendering=interpolation==='support_aware_linear'?'auto':'pixelated';}
    if(frame&&raster){
      const fit=Math.min(Math.max(1,frame.clientWidth-4)/g.w,Math.max(1,frame.clientHeight-4)/g.h),cssW=Math.max(1,Math.floor(g.w*Math.max(.05,fit))),cssH=Math.max(1,Math.floor(g.h*Math.max(.05,fit)));
      raster.style.width=`${cssW}px`;raster.style.height=`${cssH}px`;raster.style.transform=`translate(-50%,-50%) translate(${ps.panX}px,${ps.panY}px) scale(${ps.zoom})`;
      raster.dataset.cssWidth=String(cssW);raster.dataset.cssHeight=String(cssH);
    }else{
      canvas.style.width='';canvas.style.height='';
    }
  }

  function updatePlaneCrosshairOverlay(root,runtime,state,plane){
    if(!root)return;
    const raster=root.querySelector(`[data-imaging-raster="${plane}"]`),horizontal=root.querySelector(`[data-imaging-crosshair-h="${plane}"]`),vertical=root.querySelector(`[data-imaging-crosshair-v="${plane}"]`);
    if(!raster||!horizontal||!vertical)return;
    const visible=!!state.crosshairVisible,g=planeGeometry(runtime,plane),point=crosshairPosition(runtime,state,plane);
    horizontal.hidden=!visible;vertical.hidden=!visible;
    if(!visible)return;
    horizontal.style.top=`${clamp(point.y/g.h*100,0,100)}%`;vertical.style.left=`${clamp(point.x/g.w*100,0,100)}%`;
  }

  function updatePlaneCrosshairs(root,runtime,state,planes){
    arr(planes&&planes.length?planes:PLANES).forEach(plane=>updatePlaneCrosshairOverlay(root,runtime,state,plane));
  }

  // Anatomy remains on the display grid, while feature values and
  // support are sampled directly from the authoritative native feature grid.
  // Threshold classification occurs only after native-grid sampling. Anatomy
  // and feature rasters have independent invalidation so a feature-only change
  // never recomputes the unchanged structural background.
  function drawPlane(runtime,state,plane,canvas,forceRaster){
    if(!canvas)return;
    const plan=planeIndexPlan(runtime,plane),cache=ensurePlaneRaster(runtime,plane),structuralSignature=planeStructuralRasterSignature(runtime,state,plane),featureSignature=planeFeatureRasterSignature(runtime,state,plane),refreshStructural=!!forceRaster||cache.structuralSignature!==structuralSignature,refreshFeature=!!forceRaster||cache.featureSignature!==featureSignature,live=!!canvas.closest('.rvImagingPlaneFrame');
    updatePlanePresentation(runtime,state,plane,canvas);
    if(refreshStructural){
      const out=cache.image&&cache.image.data;if(!out||!cache.ctx)return;
      const windowVals=arr(runtime.payload.structural.window).map(Number);let wLo=windowVals[0],wHi=windowVals[1];
      if(!Number.isFinite(wLo)||!Number.isFinite(wHi)||wHi<=wLo){const range=arr(runtime.payload.structural.valueRange).map(Number);wLo=range[0];wHi=range[1];}
      if(!Number.isFinite(wLo)||!Number.isFinite(wHi)||wHi<=wLo){wLo=0;wHi=1;}
      const slice=Math.round(currentSlice(state,runtime,plane)),normalOffset=(slice-1)*plan.normalStride,den=Math.max(Number.EPSILON,wHi-wLo),brightness=state.backgroundBrightness,gamma=clamp(finite(state.anatomyGamma,1),.25,4);
      for(let p=0;p<plan.offsets.length;p++){
        const idx=plan.offsets[p]+normalOffset,sv=runtime.structural[idx],gray=clamp(Math.round(Math.pow(clamp((sv-wLo)/den,0,1),1/gamma)*255*brightness),0,255),q=p*4;
        out[q]=gray;out[q+1]=gray;out[q+2]=gray;out[q+3]=255;
      }
      cache.ctx.putImageData(cache.image,0,0);cache.structuralSignature=structuralSignature;cache.structuralRenderCount+=1;
    }
    if(refreshFeature){
      const featureOut=cache.featureImage&&cache.featureImage.data;if(!featureOut||!cache.featureCtx)return;
      const native=nativeFeatureRuntime(runtime),support=native.support,api=featureSamplingApi(),interpolation=effectiveFeatureInterpolation(runtime,state),a=nativeFeatureOverlay(runtime,state.overlayAId)||nativeFeatureOverlay(runtime,state.activePageMetricId),b=state.dualOverlayEnabled?nativeFeatureOverlay(runtime,state.overlayBId):null,aDisplay=a?metricDisplayState(state,a,support):null,bDisplay=b?metricDisplayState(state,b,support):null,aContract=a?displayContract(aDisplay):null,bContract=b?displayContract(bDisplay):null,aClass=cache.aClass,bClass=cache.bClass,aCoverage=cache.aCoverage,bCoverage=cache.bCoverage,atlasData=runtime.atlas&&state.atlasBoundariesVisible?runtime.atlas.data:null,atlasSlice=cache.atlasSlice;
      if(!api||typeof api.sample!=='function')throw new Error('Native-grid feature sampling support is unavailable.');
      aClass.fill(0);bClass.fill(0);aCoverage.fill(0);bCoverage.fill(0);atlasSlice.fill(0);featureOut.fill(0);
      const slice=Math.round(currentSlice(state,runtime,plane)),nativePlan=planeNativeSamplingPlan(runtime,plane,slice),normalOffset=(slice-1)*plan.normalStride,aRange=a?activeDisplayRange(a,aDisplay,support):null;
      for(let row=0;row<plan.h;row++)for(let col=0;col<plan.w;col++){
        const p=row*plan.w+col,q=p*4,nativeVoxel=[nativePlan.base[0]+col*nativePlan.stepH[0]+row*nativePlan.stepV[0],nativePlan.base[1]+col*nativePlan.stepH[1]+row*nativePlan.stepV[1],nativePlan.base[2]+col*nativePlan.stepH[2]+row*nativePlan.stepV[2]];
        if(a){const sampled=api.sample(native,a.data,nativeVoxel,aContract,interpolation),displayKlass=sampled.displayKlass||sampled.klass,coverage=interpolation==='support_aware_linear'?clamp(finite(sampled.coverage,0),0,1):(displayKlass?1:0);aClass[p]=displayKlass;aCoverage[p]=coverage;if(displayKlass&&coverage>0){const fg=overlayColor(sampled.value,displayKlass,aDisplay,aRange),alpha=clamp(Number(aDisplay.opacity),0,1)*supportCoverageAlpha(coverage);featureOut[q]=fg[0];featureOut[q+1]=fg[1];featureOut[q+2]=fg[2];featureOut[q+3]=Math.round(alpha*255);}}
        if(b){const sampled=api.sample(native,b.data,nativeVoxel,bContract,interpolation);bClass[p]=sampled.displayKlass||sampled.klass;bCoverage[p]=interpolation==='support_aware_linear'?clamp(finite(sampled.coverage,0),0,1):(bClass[p]?1:0);}
        if(atlasData)atlasSlice[p]=atlasData[plan.offsets[p]+normalOffset];
      }
      function markContour(classes,coverage,positiveColor,negativeColor,opacity){
        if(!classes||!coverage)return;const positive=hexToRgb(positiveColor),negative=hexToRgb(negativeColor),baseAlpha=clamp(finite(opacity,1),0,1),w=plan.w,h=plan.h;
        for(let row=0;row<h;row++)for(let col=0;col<w;col++){
          const p=row*w+col,klass=classes[p],cov=coverage[p];if(!klass||!(cov>0))continue;
          let edgeStrength=Math.max(0,1-Math.abs(cov-.5)/.5),edge=false;
          const neighbours=[];if(col>0)neighbours.push(p-1);if(col<w-1)neighbours.push(p+1);if(row>0)neighbours.push(p-w);if(row<h-1)neighbours.push(p+w);
          for(const n of neighbours){if(classes[n]!==klass||((cov-.5)*(coverage[n]-.5)<=0)){edge=true;edgeStrength=Math.max(edgeStrength,1-Math.min(1,Math.abs(cov-coverage[n]))*.25);}}
          if(edge||edgeStrength>.15){const color=klass>0?positive:negative,q=p*4,alpha=baseAlpha*clamp(edgeStrength,0,1);featureOut[q]=color[0];featureOut[q+1]=color[1];featureOut[q+2]=color[2];featureOut[q+3]=Math.max(featureOut[q+3],Math.round(alpha*255));}
        }
      }
      if(b)markContour(bClass,bCoverage,state.dualOverlaySilhouettePositiveColor,state.dualOverlaySilhouetteNegativeColor,bDisplay.opacity);
      if(atlasData){
        const color=hexToRgb(state.atlasBoundaryColor),alpha=clamp(finite(state.atlasBoundaryOpacity,.82),0,1),w=plan.w,h=plan.h;
        for(let row=0;row<h;row++)for(let col=0;col<w;col++){
          const p=row*w+col,code=atlasSlice[p];if(!code)continue;
          const edge=(col>0&&atlasSlice[p-1]!==code)||(col<w-1&&atlasSlice[p+1]!==code)||(row>0&&atlasSlice[p-w]!==code)||(row<h-1&&atlasSlice[p+w]!==code);
          if(edge){const q=p*4;featureOut[q]=color[0];featureOut[q+1]=color[1];featureOut[q+2]=color[2];featureOut[q+3]=Math.max(featureOut[q+3],Math.round(alpha*255));}
        }
      }
      cache.featureCtx.putImageData(cache.featureImage,0,0);cache.featureSignature=featureSignature;cache.featureRenderCount+=1;
    }
    if(refreshStructural||refreshFeature){cache.signature=`${cache.structuralSignature}||${cache.featureSignature}`;cache.renderCount+=1;}
    const ctx=canvas.getContext('2d',{alpha:false});if(!ctx)return;
    if(canvas!==cache.scratch){ctx.clearRect(0,0,canvas.width,canvas.height);ctx.drawImage(cache.scratch,0,0);}canvas.dataset.rasterRenderCount=String(cache.renderCount);canvas.dataset.structuralRasterRenderCount=String(cache.structuralRenderCount);
    const featureCanvas=live&&canvas.parentElement?canvas.parentElement.querySelector(`[data-imaging-feature-canvas="${plane}"]`):null;
    if(featureCanvas){const featureCtx=featureCanvas.getContext('2d',{alpha:true});featureCtx.clearRect(0,0,featureCanvas.width,featureCanvas.height);featureCtx.drawImage(cache.featureScratch,0,0);featureCanvas.dataset.rasterRenderCount=String(cache.renderCount);featureCanvas.dataset.featureRasterRenderCount=String(cache.featureRenderCount);}else ctx.drawImage(cache.featureScratch,0,0);
    if(!live)drawPlaneCrosshair(ctx,runtime,state,plane,canvas.width,canvas.height);
  }


  function gpuRuntimeRecord(root){return root?ROOT_RUNTIME.get(root)||null:null;}
  function setGpuCanvasActive(root,active,statusText,statusKind){
    if(!root)return;const canvas=root.querySelector('[data-imaging-shared-gpu-canvas]'),status=root.querySelector('[data-imaging-2d-renderer-status]');
    if(canvas)canvas.hidden=!active;root.classList.toggle('rvImagingGpuActive',!!active);
    Array.from(root.querySelectorAll('[data-imaging-canvas],[data-imaging-feature-canvas]')).forEach(c=>{c.style.opacity=active?'0':'1';c.dataset.renderer=active?'webgl2-shared':'cpu-native';});
    if(status){status.textContent=statusText||'';status.dataset.status=statusKind||'';}
  }
  function gpuOverlayModel(runtime,state,id){
    const overlay=id&&nativeFeatureOverlay(runtime,id);if(!overlay)return null;
    const support=nativeFeatureSupport(runtime),display=metricDisplayState(state,overlay,support);return {id,range:activeDisplayRange(overlay,display,support),display,contract:displayContract(display)};
  }
  function gpuRenderModel(runtime,state,root){
    let windowRange=arr(runtime.payload&&runtime.payload.structural&&runtime.payload.structural.window).map(Number);
    if(windowRange.length<2||!Number.isFinite(windowRange[0])||!Number.isFinite(windowRange[1])||windowRange[1]<=windowRange[0])windowRange=arr(runtime.payload&&runtime.payload.structural&&runtime.payload.structural.valueRange).map(Number);
    if(windowRange.length<2||!Number.isFinite(windowRange[0])||!Number.isFinite(windowRange[1])||windowRange[1]<=windowRange[0])windowRange=[0,1];
    const aId=state.overlayAId||state.activePageMetricId,bId=state.dualOverlayEnabled?state.overlayBId:'';
    const planes={};PLANES.forEach(plane=>{planes[plane]={frame:root.querySelector(`[data-imaging-frame="${plane}"]`),raster:root.querySelector(`[data-imaging-raster="${plane}"]`),definition:planeDefinition(runtime,plane),slice:currentSlice(state,runtime,plane)};});
    return {structuralWindow:windowRange,brightness:state.backgroundBrightness,gamma:state.anatomyGamma,anatomyInterpolation:state.anatomyInterpolation,featureInterpolation:effectiveFeatureInterpolation(runtime,state),overlayA:gpuOverlayModel(runtime,state,aId),overlayB:gpuOverlayModel(runtime,state,bId),silhouetteNegativeColor:state.dualOverlaySilhouetteNegativeColor,silhouettePositiveColor:state.dualOverlaySilhouettePositiveColor,atlasBoundaries:!!state.atlasBoundariesVisible,atlasColor:state.atlasBoundaryColor,atlasOpacity:state.atlasBoundaryOpacity,planes};
  }
  function renderWithGpu(runtime,state,root,planes){
    const record=gpuRuntimeRecord(root),session=record&&record.gpuSession;if(!session||session.state!=='ready')return false;
    updatePlanePresentations(runtime,state,root,planes);
    try{return session.render(planes,gpuRenderModel(runtime,state,root));}catch(err){session.state='fallback';session.reason='render_failed';session.error=err;setGpuCanvasActive(root,false,'Standard display','fallback');return false;}
  }

  function shared2DOverlayControlsHtml(runtime,state,escapeFn){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml,focusedId=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),focused=nativeFeatureOverlay(runtime,focusedId)||nativeFeatureOverlay(runtime,state.activePageMetricId);
    if(!focused)return '';
    const featureSupport=nativeFeatureSupport(runtime),display=metricDisplayState(state,focused,featureSupport);
    return displayControls().html({overlay:focused,display,support:featureSupport,capabilities:['threshold','colourbar','displayRange','opacity'],escape:esc,tooltipAttributes:key=>tooltipAttributes(key,esc)}).html;
  }
  function replace2DOverlayControls(root,runtime,state,escapeFn){const holder=root&&root.querySelector('[data-imaging-2d-overlay-controls]');if(!holder)return false;holder.innerHTML=shared2DOverlayControlsHtml(runtime,state,escapeFn);return true;}

  function controlBodyHtml(runtime,state,measures,escapeFn){
    const esc=typeof escapeFn==='function'?escapeFn:escapeHtml;
    if(state.activeViewMode==='three_dimensional'){
      return imaging3DController().bodyHtml(runtime,state,esc);
      return '<div class="rvImagingLoading rvImagingError">3-D controller asset is unavailable.</div>';
    }
    const sharedDisplayControls=shared2DOverlayControlsHtml(runtime,state,esc);
    const selectedTemplateId=text(runtime.payload.selectedTemplate&&runtime.payload.selectedTemplate.templateId)||state.selectedTemplateId;
    const templateControl=anatomyControls().html({capabilities:['template'],templateCatalogue:runtime.payload.templateCatalogue,state:{templateId:selectedTemplateId},escape:esc,className:'rvImagingTemplateControl'});
    const anatomyPresentationControls=anatomyControls().html({capabilities:['brightness','gamma'],state:{brightness:state.backgroundBrightness,gamma:state.anatomyGamma},escape:esc,className:'rvImaging2DAnatomyControls'});
    const atlasAvailable=!!(runtime&&runtime.atlas&&runtime.atlas.data);
    const atlasNoneSelected=!(runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.available);
    const atlasOptions=[`<option value="none"${atlasNoneSelected?' selected':''}>No atlas</option>`].concat(arr(runtime.payload.atlasCatalogue).map(a=>`<option value="${esc(a.atlasId)}"${text(a.atlasId)===text(runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.atlasId)?' selected':''}${a.enabled===false?' disabled':''}>${esc(a.label||a.atlasId)}</option>`)).concat('<option value="choose_volume_atlas">Choose ROI atlas file…</option>').join('');
    const conventionMode=text(runtime.payload&&runtime.payload.planeConvention&&runtime.payload.planeConvention.mode);
    const oblique=conventionMode==='native_oblique'||!!(runtime.payload.spatialReference&&runtime.payload.spatialReference.isOblique);
    const planeHtml=PLANES.map(p=>{
      const g=planeGeometry(runtime,p),d=g.definition,orientation=d.orientationLabels||{},sliceLabels=d.sliceDirectionLabels||{},slice=Math.round(currentSlice(state,runtime,p));
      return `<section class="rvImagingPlane" data-imaging-plane="${p}">
        <header><b>${esc(d.displayLabel||p)}</b><span data-imaging-slice-label="${p}">${slice} / ${g.max}</span></header>
        <div class="rvImagingPlaneFrame" data-imaging-frame="${p}">
          <div class="rvImagingPlaneRaster" data-imaging-raster="${p}">
            <canvas data-imaging-canvas="${p}" aria-label="${esc(d.displayLabel||p)} structural anatomy"></canvas><canvas data-imaging-feature-canvas="${p}" class="rvImagingFeatureCanvas" aria-hidden="true"></canvas>
            <span class="rvImagingCrosshair rvImagingCrosshair--horizontal" data-imaging-crosshair-h="${p}" hidden></span>
            <span class="rvImagingCrosshair rvImagingCrosshair--vertical" data-imaging-crosshair-v="${p}" hidden></span>
          </div>
          <span class="rvImagingOrientation rvImagingOrientation--left">${esc(orientation.left||'')}</span>
          <span class="rvImagingOrientation rvImagingOrientation--right">${esc(orientation.right||'')}</span>
          <span class="rvImagingOrientation rvImagingOrientation--top">${esc(orientation.top||'')}</span>
          <span class="rvImagingOrientation rvImagingOrientation--bottom">${esc(orientation.bottom||'')}</span>
        </div>
        <div class="rvImagingSliceControl">
          <span>${esc(sliceLabels.low||'')}</span>
          <input type="range" min="1" max="${g.max}" step="1" value="${slice}" data-imaging-slice="${p}" aria-label="${esc(d.displayLabel||p)} slice"${tooltipAttributesFromText(`${d.displayLabel||p} slice\nMove through the ${d.displayLabel||p} stack. With synchronized views enabled, the shared selected voxel and the other planes update to the corresponding location.`,esc)}>
          <output data-imaging-slice-output="${p}">${slice}</output>
          <span>${esc(sliceLabels.high||'')}</span>
        </div>
      </section>`;
    }).join('');
    const silhouetteColorsHtml=state.dualOverlayEnabled?`<section class="rvImagingSideSection rvImagingSilhouetteColours"${tooltipAttributes('silhouetteColors',esc)}><h3>Overlay B silhouettes</h3><div class="rvImagingSilhouetteColorbar" style="--rv-silhouette-negative:${esc(state.dualOverlaySilhouetteNegativeColor)};--rv-silhouette-positive:${esc(state.dualOverlaySilhouettePositiveColor)}"><label><span>Negative</span><input type="color" value="${esc(state.dualOverlaySilhouetteNegativeColor)}" data-imaging-silhouette-negative aria-label="Negative silhouette colour"></label><i aria-hidden="true"></i><label><span>Positive</span><input type="color" value="${esc(state.dualOverlaySilhouettePositiveColor)}" data-imaging-silhouette-positive aria-label="Positive silhouette colour"></label></div></section>`:'';
    const atlasMessage=text(runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.labelMessage);
    const gridControl=workspaceCapability(runtime,'displayGridSelection',true)?`<label${tooltipAttributes('gridPolicy',esc)}>Display grid<select data-imaging-grid-policy><option value="structural_reference"${state.displayGridPolicy==='structural_reference'?' selected':''}>Structural reference</option><option value="feature_reference"${state.displayGridPolicy==='feature_reference'?' selected':''}>Feature reference</option></select></label>`:'';
    const featureInterpolationControl=workspaceCapability(runtime,'featureInterpolation',true)?`<label${tooltipAttributes('featureInterpolation',esc)}>Feature interpolation<select data-imaging-feature-interpolation><option value="voxel_faithful"${state.featureInterpolation==='voxel_faithful'?' selected':''}>Voxel-faithful</option><option value="support_aware_linear"${state.featureInterpolation==='support_aware_linear'?' selected':''}>Support-aware linear</option></select></label>`:'';
    const atlasControl=workspaceCapability(runtime,'atlasFileSelection',true)?`<label${tooltipAttributes('atlas',esc)}>Atlas<select data-imaging-atlas>${atlasOptions}</select></label><div data-imaging-atlas-descriptor>${viewControls().atlasDescriptorControlsHtml(runtime,state,esc)}</div>`:'';
    const roiTableControl=workspaceCapability(runtime,'roiTable',true)?`<button type="button" class="rvImagingRoiTableButton${atlasAvailable?'':' isAtlasUnavailable'}" data-imaging-roi-table aria-disabled="${atlasAvailable?'false':'true'}"${atlasAvailable?'':' disabled tabindex="-1"'}${tooltipAttributes('roiTable',esc)}>ROI Tabulator</button>`:'';
    const roiMapperControl=workspaceCapability(runtime,'roiMapper',true)?`<button type="button" class="rvImagingRoiMapperButton${atlasAvailable?'':' isAtlasUnavailable'}" data-imaging-roi-mapper aria-disabled="${atlasAvailable?'false':'true'}"${atlasAvailable?'':' disabled tabindex="-1"'}${tooltipAttributes('roiMapper',esc)}>ROI Mapper</button>`:'';
    const navigationFooter=informationControls().html({
      capabilities:['informationFooter','extrema'],
      fields:[
        {id:'voxel',label:'Voxel',tooltip:tooltipText('voxelReadout')},
        {id:'world',label:'World (mm)',tooltip:tooltipText('worldReadout')},
        {id:'value',label:'Value',tooltip:tooltipText('valueReadout')},
        {id:'roi',label:'ROI',value:atlasAvailable?atlasLabel(runtime,state):'—',className:'rvImagingLocationField--roi',tooltip:tooltipText('roiReadout')}
      ],
      extrema:[
        {kind:'minimum',label:'Min',tooltip:tooltipText('minimum')},
        {kind:'maximum',label:'Max',tooltip:tooltipText('maximum')},
        {kind:'strongest_absolute',label:'Max |x|',tooltip:tooltipText('strongest')}
      ],
      viewHtml:viewControls().toolbarHtml({
        items:[
          {command:'view.zoom',direction:'out',label:'−',legacyAttribute:'data-imaging-zoom="out"',tooltip:tooltipText('zoomOut'),ariaLabel:'Zoom out',tooltipAttributes:tip=>tooltipAttributesFromText(tip,esc)},
          {command:'view.zoom',direction:'in',label:'+',legacyAttribute:'data-imaging-zoom="in"',tooltip:tooltipText('zoomIn'),ariaLabel:'Zoom in',tooltipAttributes:tip=>tooltipAttributesFromText(tip,esc)},
          {command:'view.fit',label:'Fit',legacyAttribute:'data-imaging-zoom="fit"',tooltip:tooltipText('fit'),tooltipAttributes:tip=>tooltipAttributesFromText(tip,esc)},
          {command:'view.reset',label:'Reset',legacyAttribute:'data-imaging-zoom="reset"',tooltip:tooltipText('resetView'),tooltipAttributes:tip=>tooltipAttributesFromText(tip,esc)}
        ],escape:esc,trailingHtml:`<label class="rvImagingCheck"${tooltipAttributes('syncViews',esc)}><input type="checkbox" data-rv-view-sync data-imaging-view-sync${state.syncViews?' checked':''}> Sync</label>`
      }),
      trailingHtml:`<label class="rvImagingCheck rvImagingTipsToggle"><input type="checkbox" data-imaging-tooltips-enabled${state.tooltipsEnabled!==false?' checked':''}> Tooltips</label>`
    });
    return `<div class="rvImagingLayout">
      <aside class="rvImagingSide rvImagingSide--left">
        ${templateControl}
        ${gridControl}
        <label${tooltipAttributes('anatomyInterpolation',esc)}>Anatomy interpolation<select data-imaging-anatomy-interpolation><option value="nearest"${state.anatomyInterpolation==='nearest'?' selected':''}>Nearest</option><option value="linear"${state.anatomyInterpolation==='linear'?' selected':''}>Linear</option><option value="high_quality"${state.anatomyInterpolation==='high_quality'?' selected':''}>High quality</option></select></label>${featureInterpolationControl}
        <label${tooltipAttributes('renderer2d',esc)}>2-D renderer<select data-imaging-2d-renderer><option value="auto"${state.interactive2DRendererMode==='auto'?' selected':''}>Auto (GPU preferred)</option><option value="gpu"${state.interactive2DRendererMode==='gpu'?' selected':''}>GPU high resolution</option><option value="cpu"${state.interactive2DRendererMode==='cpu'?' selected':''}>CPU compatible</option></select></label>
        <div class="rvImagingRendererStatus" data-imaging-2d-renderer-status>Standard display</div>
        ${atlasControl}
        ${atlasMessage?`<div class="rvImagingAtlasMessage"${tooltipAttributesFromText(`Atlas provenance\n${atlasMessage}`,esc)}>${esc(atlasMessage)}</div>`:''}
        <label class="rvImagingCheck"${tooltipAttributes('atlasBoundaries',esc)}><input type="checkbox" data-imaging-boundaries${state.atlasBoundariesVisible?' checked':''}${atlasAvailable?'':' disabled'}> Atlas boundaries</label>
        <label${tooltipAttributes('boundaryColor',esc)}>Boundary colour<input type="color" data-imaging-boundary-color value="${esc(state.atlasBoundaryColor)}"${atlasAvailable?'':' disabled'}></label>
        <label${tooltipAttributes('boundaryOpacity',esc)}>Boundary opacity<input type="range" min="0" max="1" step="0.01" data-imaging-boundary-opacity value="${esc(state.atlasBoundaryOpacity)}"${atlasAvailable?'':' disabled'}><output data-imaging-boundary-opacity-output>${esc(fmt(state.atlasBoundaryOpacity,2))}</output></label>
        ${roiTableControl}
        ${roiMapperControl}
        <section class="rvImagingSideSection rvImagingAdvancedViewOptions"><h3>Advanced view options</h3><button type="button" class="rvImaging2DMontageButton" data-imaging-multislice${tooltipAttributes('multislice',esc)}>Montage Viewer</button></section>
        <label class="rvImagingCheck"${tooltipAttributes('crosshairs',esc)}><input type="checkbox" data-imaging-crosshair${state.crosshairVisible?' checked':''}> Crosshairs</label>
        ${oblique?'<div class="rvImagingSpatialNote">Oblique affine: explicit native I/J/K planes are shown rather than misleading anatomical labels.</div>':''}
      </aside>
      <main class="rvImagingPlanes"><canvas class="rvImagingSharedGpuCanvas" data-imaging-shared-gpu-canvas hidden aria-hidden="true"></canvas>${planeHtml}</main>
      <aside class="rvImagingSide rvImagingSide--right">
        ${state.dualOverlayEnabled?`<div class="rvImagingOverlayEditContext"><small>Editing overlay ${esc(state.focusedOverlaySlot)}</small></div>`:''}
        <div data-imaging-2d-overlay-controls>${sharedDisplayControls}</div>
        ${silhouetteColorsHtml}
        ${anatomyPresentationControls}
      </aside>
      ${navigationFooter}
      <div class="rvImagingContextMenu" data-imaging-context-menu hidden role="menu"><button type="button" data-imaging-context-action="minimum"${tooltipAttributes('minimum',esc)}>Go to minimum</button><button type="button" data-imaging-context-action="maximum"${tooltipAttributes('maximum',esc)}>Go to maximum</button><button type="button" data-imaging-context-action="strongest_absolute"${tooltipAttributes('strongest',esc)}>Go to strongest |value|</button><hr><button type="button" data-imaging-context-action="copy_voxel"${tooltipAttributes('copyVoxel',esc)}>Copy voxel coordinate</button><button type="button" data-imaging-context-action="copy_world"${tooltipAttributes('copyWorld',esc)}>Copy world coordinate</button><button type="button" data-imaging-context-action="copy_value"${tooltipAttributes('copyValue',esc)}>Copy value</button><button type="button" data-imaging-context-action="set_threshold"${tooltipAttributes('setThreshold',esc)}>Set threshold from focused value</button></div>
    </div>`;
  }

  function extremaApi(){const api=window.NMImagingExtrema;if(!api||typeof api.selectNative!=='function')throw new Error('The canonical imaging extrema authority is unavailable.');return api;}
  function extremumFor(runtime,state,kind){const api=extremaApi(),id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),native=nativeFeatureRuntime(runtime),ov=nativeFeatureOverlay(runtime,id);if(!ov)throw new Error('No focused native feature overlay is available.');const display=metricDisplayState(state,ov,native.support);return api.selectNative(runtime,native,ov,displayContract(display),kind);}
  function inactiveExtremumRevealState(){return {active:false,markerSignature:'',snapshot:null,plan:null};}
  function restoreAutomaticExtremumViewState(state){const render3D=state&&state.render3D,reveal=render3D&&render3D.extremumReveal;if(!render3D)return false;if(reveal&&reveal.active&&reveal.snapshot){render3D.camera=copy(reveal.snapshot.camera);render3D.clipping=copy(reveal.snapshot.clipping);render3D.selectedPreset=text(reveal.snapshot.selectedPreset||'right');}render3D.extremumReveal=inactiveExtremumRevealState();return !!(reveal&&reveal.active);}
  function clearExtremumSelection(state){restoreAutomaticExtremumViewState(state);state.extremumMarker=null;}
  function applyExtremumSelection(runtime,state,descriptor){
    restoreAutomaticExtremumViewState(state);
    const voxel=arr(descriptor&&descriptor.voxel).slice(0,3).map((x,i)=>clamp(Math.round(Number(x)),1,runtime.dims[i])),world=arr(descriptor&&descriptor.worldMm).slice(0,3).map(Number),vertexIndex=Number.isFinite(Number(descriptor&&descriptor.vertexIndex))?Math.max(0,Math.round(Number(descriptor.vertexIndex))):-1;
    state.currentVoxel=voxel.slice();PLANES.forEach(p=>{if(state.planes&&state.planes[p])state.planes[p].voxel=voxel.slice();});state.currentWorldMm=world.slice();state.crosshairVisible=true;state.extremumMarker=Object.assign({},descriptor,{visible:true,navigation:{mode:'automatic_pending'}});
    if(state.render3D&&typeof state.render3D==='object')state.render3D.selection={vertexIndex,surfaceWorldMm:world.slice(),surfaceVoxel:voxel.slice(),sourceVoxel:voxel.slice(),sourceWorldMm:world.slice(),roiCode:Math.max(0,Math.round(finite(descriptor&&descriptor.atlasCode,0))),roiLabel:text(descriptor&&descriptor.atlasLabel||'Unlabelled'),featureValue:finite(descriptor&&descriptor.value,NaN),nativeFeatureValue:finite(descriptor&&descriptor.nativeValue,finite(descriptor&&descriptor.value,NaN)),displaySmoothingMm:clamp(finite(descriptor&&descriptor.displaySmoothingMm,0),0,12),hitType:'feature extremum'};
    return voxel;
  }
  function highlightExtremum(root){if(!root)return;root.classList.remove('rvImagingExtremumFlash');void root.offsetWidth;root.classList.add('rvImagingExtremumFlash');setTimeout(()=>{if(root&&root.isConnected)root.classList.remove('rvImagingExtremumFlash');},1100);}
  function applyControlWidthClass(root){const controls=root&&root.querySelector('[data-rv-information-footer]');if(!controls)return;const width=controls.getBoundingClientRect().width;controls.classList.toggle('isNarrow',width<980);controls.classList.toggle('isVeryNarrow',width<720);root.style.setProperty('--rv-imaging-controls-width',Math.max(0,Math.round(width))+'px');}
  function clipboardText(value){const s=text(value);if(navigator.clipboard&&typeof navigator.clipboard.writeText==='function')return navigator.clipboard.writeText(s);const area=document.createElement('textarea');area.value=s;area.style.position='fixed';area.style.left='-10000px';document.body.appendChild(area);area.select();try{document.execCommand('copy');}finally{area.remove();}return Promise.resolve();}
  function focusedValue(runtime,state){
    const id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),overlay=nativeFeatureOverlay(runtime,id);if(!overlay)return NaN;
    if(isSurfaceRuntime(runtime)){const selection=state.render3D&&state.render3D.selection||{},marker=state.extremumMarker||{},index=Number.isFinite(Number(selection.vertexIndex))?Number(selection.vertexIndex):Number(marker.vertexIndex);return Number.isInteger(index)&&index>=0&&index<overlay.data.length?Number(overlay.data[index]):NaN;}
    const native=nativeFeatureRuntime(runtime),record=native.overlay(id),api=featureSamplingApi(),display=metricDisplayState(state,overlay,native.support),displayVoxel0=planeVoxel(state,runtime,state.lastPlaneId).map(value=>Math.round(value)-1),nativeVoxel=nativeVoxelAtDisplayVoxel0(runtime,displayVoxel0),sampled=record&&typeof api.nativeDescriptor==='function'?api.nativeDescriptor(native,record.data,nativeVoxel,displayContract(display)):null;
    return Number(sampled&&sampled.value);
  }
  function setThresholdFromFocusedValue(runtime,state){
    const id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),overlay=nativeFeatureOverlay(runtime,id);if(!overlay)return false;
    const value=focusedValue(runtime,state);if(!Number.isFinite(value))return false;const support=nativeFeatureSupport(runtime),display=metricDisplayState(state,overlay,support),mode=text(display.thresholdMode).toLowerCase();let patch=null;if(mode==='outside_interval'){if(value<0)patch={thresholdLow:value};else if(value>0)patch={thresholdHigh:value};else return false;}else if(mode==='above_abs')patch={thresholdValue:Math.abs(value)};else if(mode==='above'||mode==='below')patch={thresholdValue:value};else if(mode==='none')return false;else throw new Error(`Unknown threshold mode: ${mode}`);
    displayControls().applyCommand({command:'display.threshold.update',capability:'threshold',detail:{patch,reason:'threshold_from_focused_value',phase:'commit'}},{getOverlay:()=>overlay,getSupport:()=>support,getDisplay:()=>display,defaultOpacity:.85,identity:{measureId:text(overlay&&overlay.meta&&overlay.meta.measureId),pathway:'imaging'}});return true;
  }
  function imagingControlTooltipNode(){let node=document.getElementById('rvImagingControlTooltip');if(!node){node=document.createElement('div');node.id='rvImagingControlTooltip';node.className='rvImagingControlTooltip';node.hidden=true;node.setAttribute('role','tooltip');document.body.appendChild(node);}return node;}
  function hideImagingControlTooltip(){if(typeof document==='undefined')return;const node=document.getElementById('rvImagingControlTooltip');if(node){node.hidden=true;node.replaceChildren();node.removeAttribute('data-source-control');}}
  function positionImagingControlTooltip(node,event,anchor){if(!node||node.hidden)return;const viewportW=Math.max(320,window.innerWidth||document.documentElement.clientWidth||320),viewportH=Math.max(240,window.innerHeight||document.documentElement.clientHeight||240),gap=10;let x=Number(event&&event.clientX),y=Number(event&&event.clientY);if((!Number.isFinite(x)||!Number.isFinite(y))&&anchor&&typeof anchor.getBoundingClientRect==='function'){const r=anchor.getBoundingClientRect();x=r.left+r.width*.5;y=r.bottom;}if(!Number.isFinite(x)||!Number.isFinite(y)){x=16;y=16;}const width=node.offsetWidth||340,height=node.offsetHeight||90;let left=x+gap,top=y+gap;if(left+width+8>viewportW)left=Math.max(8,x-width-gap);if(top+height+8>viewportH)top=Math.max(8,y-height-gap);node.style.left=Math.max(8,left)+'px';node.style.top=Math.max(8,top)+'px';}
  function showImagingControlTooltip(control,event,state){if(state&&state.tooltipsEnabled===false)return;const value=text(control&&control.getAttribute&&control.getAttribute('data-imaging-tooltip')).trim();if(!value)return;const node=imagingControlTooltipNode(),lines=value.split(/\n+/).map(x=>x.trim()).filter(Boolean);node.replaceChildren();const heading=document.createElement('strong');heading.textContent=lines.shift()||'Imaging control';node.appendChild(heading);if(lines.length){const body=document.createElement('span');body.textContent=lines.join(' ');node.appendChild(body);}node.hidden=false;node.setAttribute('data-source-control',text(control.dataset&&control.dataset.imagingTooltipId));positionImagingControlTooltip(node,event,control);}
  function bindImagingControlTooltips(root,state){if(!root)return;hideImagingControlTooltip();Array.from(root.querySelectorAll('[data-imaging-tooltip]')).forEach((control,index)=>{if(control.dataset.imagingTooltipBound==='1')return;control.dataset.imagingTooltipBound='1';control.dataset.imagingTooltipId=String(index+1);control.addEventListener('pointerenter',event=>showImagingControlTooltip(control,event,state));control.addEventListener('pointermove',event=>{if(!state||state.tooltipsEnabled!==false)positionImagingControlTooltip(imagingControlTooltipNode(),event,control);});control.addEventListener('pointerleave',hideImagingControlTooltip);control.addEventListener('focusin',event=>showImagingControlTooltip(control,event,state));control.addEventListener('focusout',event=>{if(!control.contains(event.relatedTarget))hideImagingControlTooltip();});});root.addEventListener('pointerleave',event=>{if(event.relatedTarget&&!root.contains(event.relatedTarget))hideImagingControlTooltip();});}

  function hideContextMenu(root){const menu=root&&root.querySelector('[data-imaging-context-menu]');if(menu)menu.hidden=true;}
  function showContextMenu(root,event){const menu=root&&root.querySelector('[data-imaging-context-menu]');if(!menu)return;event.preventDefault();const box=root.getBoundingClientRect();menu.hidden=false;const x=clamp(event.clientX-box.left,4,Math.max(4,box.width-menu.offsetWidth-4)),y=clamp(event.clientY-box.top,4,Math.max(4,box.height-menu.offsetHeight-4));menu.style.left=x+'px';menu.style.top=y+'px';}

  function updateReadouts(runtime,state,root){
    const activeVoxel=planeVoxel(state,runtime,state.lastPlaneId);state.currentVoxel=activeVoxel.slice();
    state.currentWorldMm=voxelToWorld(runtime.payload.spatialReference,activeVoxel);
    informationControls().update(root,{fields:[{id:'voxel',value:activeVoxel.map(v=>Math.round(v)).join(', ')},{id:'world',value:state.currentWorldMm.map(v=>fmt(v,2)).join(', ')},{id:'value',value:fmt(focusedValue(runtime,state),4)}]});
    updateAtlasReadout(root,runtime,state,activeVoxel,false);
    PLANES.forEach(p=>{
      const g=planeGeometry(runtime,p),slice=Math.round(currentSlice(state,runtime,p));
      const node=root.querySelector(`[data-imaging-slice-label="${p}"]`);if(node)node.textContent=`${slice} / ${g.max}`;
      const slider=root.querySelector(`[data-imaging-slice="${p}"]`);if(slider)slider.value=String(slice);
      const output=root.querySelector(`[data-imaging-slice-output="${p}"]`);if(output)output.textContent=String(slice);
    });
    updatePlaneCrosshairs(root,runtime,state,PLANES);
  }


  function roiRowsPreparationInput(runtime,state,includeGeometry,includeInactive,activeOnly){
    if(!runtime.atlas)return null;if(isSurfaceRuntime(runtime)){const id=focusedEditingOverlayId(state),overlay=nativeFeatureOverlay(runtime,id),display=overlay?metricDisplayState(state,overlay,runtime.surfaceRuntime.support):null;return {sourceDomain:'surface',runtime,state,displayContract:displayContract(display),includeGeometry:includeGeometry===true,includeInactive:includeInactive===true};}
    const id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),overlay=nativeFeatureOverlay(runtime,id);if(!overlay)return null;
    if(workspaceCapability(runtime,'canonicalROI',false)&&includeGeometry){const original=canonicalROIRowsForMeasures(runtime,state,[id],{includeInactive:true})[0].rows;return {displayDims:runtime.dims.slice(),atlasData:runtime.atlas.data,atlasLabels:Object.fromEntries(original.map(row=>[`roi_${row.roiCode}`,row.roiName])),affineVoxel1ToWorld:runtime.payload.spatialReference.affineVoxel1ToWorld,includeGeometry:true,includeInactive:true,canonicalRows:original};}
    const native=nativeFeatureRuntime(runtime),display=metricDisplayState(state,overlay,native.support);
    return {displayDims:runtime.dims.slice(),atlasData:runtime.atlas.data,atlasLabels:runtime.atlas.meta&&runtime.atlas.meta.roiLabels||{},nativeRuntime:{dims:native.dims.slice(),support:native.support},featureData:overlay.data,displayToNativeMatrix:nativeDisplayTransform(runtime),displayContract:displayContract(display),interpolation:effectiveFeatureInterpolation(runtime,state),minPct:Math.max(0,finite(state.roiMinPct,0)),includeGeometry:includeGeometry===true,includeInactive:includeInactive===true,activeOnly:activeOnly===true,affineVoxel1ToWorld:runtime.payload&&runtime.payload.spatialReference&&runtime.payload.spatialReference.affineVoxel1ToWorld};
  }

  function computeROIRows(runtime,state,options){
    const opts=options&&typeof options==='object'?options:{},input=roiRowsPreparationInput(runtime,state,opts.includeGeometry,opts.includeInactive,opts.activeOnly);if(!input)return [];if(input.sourceDomain==='surface'){
      const rows=surfaceAdapter().roiRows(runtime,state,input.displayContract,{includeGeometry:input.includeGeometry,includeInactive:input.includeInactive,minPct:Math.max(0,finite(state.roiMinPct,0))});
      if(input.includeGeometry&&workspaceCapability(runtime,'canonicalROI',false)){const id=focusedEditingOverlayId(state),original=canonicalROIRowsForMeasures(runtime,state,[id],{includeInactive:true})[0].rows;return window.NMImagingRoiRows.mergeCanonical(original,rows);}
      return rows;
    }
    const module=window.NMImagingRoiRows;if(!module||typeof module.compute!=='function')throw new Error('Shared ROI aggregation module is unavailable.');
    return module.compute(input);
  }

  /**
   * Validate the compact canonical ROI materialization retained by DataIO.
   * Authority: canonical column identity and original measure vectors only;
   * atlas data, expanded feature fields and geometry are deliberately absent.
   * This O(R*M) metadata check performs no IO and has no side effects. Missing,
   * duplicate or dimensionally inconsistent identity fails explicitly. ROI
   * Mapper and display-statistics binding consume this materialization; ordinary atlas tabulation remains unchanged.
   */
  function canonicalROIMaterialization(runtime){
    if(!workspaceCapability(runtime,'canonicalROI',false))return null;
    const payload=runtime&&runtime.payload&&runtime.payload.canonicalROI||{},columns=arr(payload.columns),overlays=arr(payload.overlays),n=Number(payload.nColumns),domain=text(payload.spatialDomain),identityModel=text(payload.identityModel),spatialIdentity=text(payload.spatialReferenceIdentity);
    if(text(payload.schema)!=='NMCanonicalROIViewerMaterialization'||Number(payload.schemaVersion)!==1||payload.available!==true)throw new Error('Canonical ROI workspace materialization is missing or incompatible.');
    if(!Number.isInteger(n)||n<1||columns.length!==n||!['volume','surface'].includes(domain)||!spatialIdentity)throw new Error('Canonical ROI workspace identity is incomplete.');
    if((domain==='volume'&&identityModel!=='atlas_label_id')||(domain==='surface'&&identityModel!=='hemisphere_annotation_id'))throw new Error('Canonical ROI workspace identity model disagrees with its spatial domain.');
    const columnKeys=new Set();columns.forEach((column,index)=>{const columnIndex=Number(column&&column.columnIndex),columnKey=text(column&&column.columnKey),roiId=Number(column&&column.roiId),roiName=text(column&&column.roiName),hemisphere=text(column&&column.hemisphere);if(columnIndex!==index+1||!columnKey||!Number.isFinite(roiId)||!roiName||domain==='surface'&&!['lh','rh'].includes(hemisphere))throw new Error(`Canonical ROI column ${index+1} is invalid.`);if(columnKeys.has(columnKey))throw new Error(`Canonical ROI column identity is duplicated: ${columnKey}.`);columnKeys.add(columnKey);});
    const byMeasure=new Map();overlays.forEach(overlay=>{const measureId=text(overlay&&overlay.measureId),values=arr(overlay&&overlay.values);if(!measureId||byMeasure.has(measureId)||values.length!==n)throw new Error(`Canonical ROI measure ${measureId||'(empty)'} is invalid.`);byMeasure.set(measureId,values.map(value=>value===null?NaN:Number(value)));});
    return {domain,identityModel,spatialIdentity,n,columns,byMeasure};
  }

  // Bind producer-retained one-value-per-ROI vectors to display overlays without altering rendered voxel/vertex arrays.
  function bindCanonicalROIStatistics(runtime){
    const materialization=canonicalROIMaterialization(runtime);if(!materialization)return runtime;
    const overlays=runtime&&runtime.overlays||{};Object.keys(overlays).forEach(id=>{const values=materialization.byMeasure.get(id);if(!values)throw new Error(`Canonical ROI display statistics are unavailable for feature measure ${id}.`);overlays[id].statisticsData=values;});
    return runtime;
  }

  function canonicalROIMeasureOverlay(runtime,measureId,materialization){
    const id=text(measureId),values=materialization&&materialization.byMeasure.get(id);if(!values)throw new Error(`Canonical ROI measure ${id||'(empty)'} is unavailable.`);if(values.some(value=>!Number.isFinite(value)&&!Number.isNaN(value)))throw new Error(`Canonical ROI measure ${id} contains an infinite value.`);const spatial=runtime&&runtime.overlays&&runtime.overlays[id],meta=spatial&&spatial.meta||spatial||{};return {meta:Object.assign({},meta,{measureId:id}),data:values};
  }

  function canonicalROIRowsForMeasures(runtime,state,measureIds,options){
    const materialization=canonicalROIMaterialization(runtime),opts=options&&typeof options==='object'?options:{},includeInactive=opts.includeInactive===true,minPct=Math.max(0,finite(state&&state.roiMinPct,0));if(!materialization)return null;
    return arr(measureIds).map(text).filter(Boolean).map(id=>{const overlay=canonicalROIMeasureOverlay(runtime,id,materialization),contract=displayContract(metricDisplayState(state,overlay,null)),classify=displaySemantics().prepareClassificationSign(contract),rows=[];materialization.columns.forEach((column,index)=>{const value=overlay.data[index],klass=Number.isNaN(value)?0:classify(value,true),pct=klass?100:0;if(!includeInactive&&(!klass||pct<minPct))return;rows.push({columnIndex:Number(column.columnIndex),columnKey:text(column.columnKey),roiCode:Number(column.roiId),roiName:text(column.roiName),hemisphere:text(column.hemisphere),activeMeanValue:klass?value:NaN,pctPositive:klass>0?100:0,pctNegative:klass<0?100:0,pctSuprathreshold:pct});});return {id,rows};});
  }

  function roiRowsForMeasure(runtime,state,measureId,options){
    const id=text(measureId),one=copy(state);if(!id)throw new Error('ROI Mapper requires an explicit feature measure.');one.enabledMetricIds=[id];one.activePageMetricId=id;one.overlayAId=id;one.overlayBId='';one.dualOverlayEnabled=false;one.focusedOverlaySlot='A';normalizeState(one,runtime&&runtime.catalogueMeasures||[]);if(!metricById(runtime&&runtime.catalogueMeasures||[],id))throw new Error(`Feature measure ${id} is not available in the current imaging catalogue.`);const canonical=canonicalROIRowsForMeasures(runtime,one,[id],options);return canonical?canonical[0].rows:computeROIRows(runtime,one,options);
  }

  function roiRowsForMeasures(runtime,state,measureIds,options){
    const ids=arr(measureIds).map(text).filter(Boolean),opts=options&&typeof options==='object'?options:{};if(!ids.length)return [];const canonical=canonicalROIRowsForMeasures(runtime,state,ids,opts);if(canonical)return canonical;if(isSurfaceRuntime(runtime))return ids.map(id=>({id,rows:roiRowsForMeasure(runtime,state,id,opts)}));
    const module=window.NMImagingRoiRows;if(!module||typeof module.computeActiveBatch!=='function')throw new Error('Batched ROI aggregation support is unavailable.');const native=nativeFeatureRuntime(runtime),series=ids.map(id=>{const overlay=nativeFeatureOverlay(runtime,id);if(!overlay)throw new Error(`Feature measure ${id} is unavailable for batched ROI aggregation.`);const display=metricDisplayState(state,overlay,native.support);return {id,featureData:overlay.data,displayContract:displayContract(display)};});
    return module.computeActiveBatch({displayDims:runtime.dims.slice(),atlasData:runtime.atlas.data,atlasLabels:runtime.atlas.meta&&runtime.atlas.meta.roiLabels||{},nativeRuntime:{dims:native.dims.slice(),support:native.support},displayToNativeMatrix:nativeDisplayTransform(runtime),interpolation:effectiveFeatureInterpolation(runtime,state),minPct:Math.max(0,finite(state.roiMinPct,0)),includeInactive:opts.includeInactive===true,series});
  }

  function roiMapperAtlasDescriptor(runtime){
    const atlas=runtime&&runtime.atlas,meta=atlas&&atlas.meta||{},canonical=canonicalROIMaterialization(runtime);if(canonical){const id=text(meta.atlasId||meta.selectionId||canonical.spatialIdentity),label=text(meta.label||meta.atlasLabel||meta.name||id||'Canonical ROI provenance'),axis=canonical.columns.map(column=>text(column.columnKey)).join('|');return {id,label,identity:['canonical_roi',canonical.domain,canonical.identityModel,canonical.spatialIdentity,axis].join('|'),sourceDomain:canonical.domain};}if(!atlas||!atlas.data)return null;const surface=isSurfaceRuntime(runtime),id=text(meta.atlasId||meta.selectionId),label=text(meta.label||meta.atlasLabel||meta.name||id||'Current atlas'),topology=surface?text(runtime.surfaceRuntime&&runtime.surfaceRuntime.topologyIdentity):text(runtime.payload&&runtime.payload.spatialReference&&runtime.payload.spatialReference.gridId),content=text(meta.contentHash||meta.dataHash||meta.hash||meta.cacheKey||meta.sourcePath||[meta.lhPath,meta.rhPath].filter(Boolean).join('|'));return {id:id||label,label,identity:[surface?'surface':'voxel',id||label,topology,content,atlas.data.length].join('|'),sourceDomain:surface?'surface':'voxel'};
  }

  async function roiMapperRuntimeFor(runtime,state,measures,opts,componentId,measureIds){
    const component=text(componentId),ids=uniqueText(arr(measureIds).map(text).filter(Boolean)),one=copy(state);one.enabledMetricIds=ids.slice();one.activePageMetricId=ids[0]||text(state.activePageMetricId);one.overlayAId=one.activePageMetricId;one.overlayBId='';one.dualOverlayEnabled=false;one.focusedOverlaySlot='A';normalizeState(one,measures);const componentOpts=Object.assign({},opts,{selectedSpec:overrides=>opts.selectedSpec(Object.assign({},overrides||{},{backprojectionComponentId:component}))}),next=await loadWorkspace(componentOpts,null,measures,one,runtime,ids);
    if(isSurfaceRuntime(next)){
      if(!runtime.atlas||!runtime.atlas.data)throw new Error('The selected surface annotation is unavailable.');const left=runtime.surfaceRuntime||{},right=next.surfaceRuntime||{};if(text(left.topologyIdentity)!==text(right.topologyIdentity)||text(left.vertexOrderIdentity)!==text(right.vertexOrderIdentity)||Number(left.nVertices)!==Number(right.nVertices))throw new Error('The selected surface atlas cannot be reused because component backprojection changed the authoritative surface topology or vertex order.');next.atlas=runtime.atlas;next.surfaceRuntime.atlas=runtime.atlas;
    }else if(!workspaceCapability(next,'canonicalROI',false)){
      if(!next.nativeFeatureSampling||typeof next.nativeFeatureSampling.load!=='function')throw new Error('The authoritative native-grid feature source required by ROI Mapper is unavailable.');await next.nativeFeatureSampling.load(opts.fetchArray);
    }
    if(!next.atlas||!next.atlas.data)throw new Error('The selected atlas is unavailable for this signature.');return {runtime:next,state:one};
  }

  function roiMapperDisplayContract(runtime,state,measureId){
    const canonical=canonicalROIMaterialization(runtime),overlay=canonical?canonicalROIMeasureOverlay(runtime,measureId,canonical):nativeFeatureOverlay(runtime,measureId);if(!overlay)throw new Error(`Feature measure ${text(measureId)||'(empty)'} is unavailable for ROI Mapper display semantics.`);
    const support=canonical?null:(isSurfaceRuntime(runtime)?runtime.surfaceRuntime&&runtime.surfaceRuntime.support:nativeFeatureRuntime(runtime).support),display=metricDisplayState(state,overlay,support);return displayContract(display);
  }

  function roiMapperConfig(runtime,state,measures,opts,overrides){
    const cfg=overrides&&typeof overrides==='object'?overrides:{},api=window.NMResultsViewerROIMapper;if(!api)throw new Error('ROI Mapper presentation module is unavailable.');const atlas=roiMapperAtlasDescriptor(runtime);if(!atlas)throw new Error('ROI Mapper requires a selected atlas or surface annotation.');const components=arr(opts&&opts.payload&&opts.payload.backprojectionComponents||[]),selectedComponentId=text(cfg.selectedComponentId||opts&&opts.payload&&opts.payload.selectedBackprojectionComponentId),selectedIds=arr(cfg.selectedMeasureIds&&cfg.selectedMeasureIds.length?cfg.selectedMeasureIds:requestedMetricIds(state)).map(text).filter(id=>metricById(measures,id)),activeMeasureId=text(cfg.activeMeasureId||state.activePageMetricId||state.overlayAId||selectedIds[0]),roiCache=new Map(),cacheKey=spec=>[text(spec.componentId),text(spec.measureId)].join('|');
    return {measures,components,selectedMeasureIds:selectedIds.length?selectedIds:[activeMeasureId].filter(Boolean),selectedComponentId,activeMeasureId,selectedComponentIds:arr(cfg.selectedComponentIds),mode:text(cfg.mode||'payloads_within_component'),atlas,minExtentPct:Math.max(0,finite(cfg.minExtentPct,state.roiMinPct)),presentationState:cfg.presentationState||null,setMessage:opts.setMessage,exportArtifact:opts.exportArtifact,selectExportDirectory:opts.selectExportDirectory,exportDirectory:text(opts.exportDirectory),loadSignatures:async request=>{
      const mode=text(request&&request.mode),specs=[];if(mode==='payloads_within_component'){const componentId=text(request.componentId),ids=arr(request.measureIds).map(text).filter(Boolean);if(!ids.length)throw new Error('ROI Mapper requires at least one selected payload.');ids.forEach(measureId=>specs.push({measureId,componentId}));}
      else if(mode==='components_within_payload'){const measureId=text(request.measureId),ids=arr(request.componentIds).map(text).filter(Boolean);if(!measureId||!ids.length)throw new Error('ROI Mapper component comparison requires one payload and at least one component.');ids.forEach(componentId=>specs.push({measureId,componentId}));}
      else throw new Error(`Unsupported ROI Mapper comparison mode: ${mode||'(empty)'}.`);
      const makeResult=(spec,loaded,error,rowsOverride)=>{const measure=metricById(measures,spec.measureId),component=components.find(item=>text(item&&item.componentId)===spec.componentId),measureLabel=text(measure&&measure.label||spec.measureId),componentName=text(component&&component.selectionLabel||component&&component.label||component&&component.componentId||spec.componentId),base={signatureId:cacheKey(spec),measureId:spec.measureId,measureLabel,componentId:spec.componentId,componentLabel:componentName};if(error)return Object.assign(base,{ok:false,error:error&&error.message||String(error)});try{const descriptor=roiMapperAtlasDescriptor(loaded.runtime),roiStarted=performance.now(),rows=Array.isArray(rowsOverride)?rowsOverride:roiRowsForMeasure(loaded.runtime,loaded.state,spec.measureId,{includeInactive:true,activeOnly:true}),contract=roiMapperDisplayContract(loaded.runtime,loaded.state,spec.measureId);if(!Array.isArray(rowsOverride))profile(opts,'ROI Mapper ROI aggregate',roiStarted,`metric=${spec.measureId} component=${spec.componentId||'current'} rois=${rows.length}`);return Object.assign(base,{ok:true,atlas:descriptor,displayContract:contract,rows});}catch(inner){return Object.assign(base,{ok:false,error:inner&&inner.message||String(inner)});}};
      const pending=specs.filter(spec=>!roiCache.has(cacheKey(spec)));
      if(pending.length&&mode==='payloads_within_component'){
        let loaded=null,error=null,batch=null;try{loaded=await roiMapperRuntimeFor(runtime,state,measures,opts,pending[0].componentId,pending.map(spec=>spec.measureId));const started=performance.now();batch=roiRowsForMeasures(loaded.runtime,loaded.state,pending.map(spec=>spec.measureId),{includeInactive:true,activeOnly:true});profile(opts,'ROI Mapper ROI aggregate batch',started,`metrics=${pending.length} component=${pending[0].componentId||'current'}`);}catch(caught){error=caught;}const byId=new Map(arr(batch).map(item=>[text(item&&item.id),item&&item.rows]));pending.forEach(spec=>roiCache.set(cacheKey(spec),makeResult(spec,loaded,error,byId.get(spec.measureId))));
      }else if(pending.length)for(const spec of pending){let loaded=null,error=null;try{loaded=await roiMapperRuntimeFor(runtime,state,measures,opts,spec.componentId,[spec.measureId]);}catch(caught){error=caught;}roiCache.set(cacheKey(spec),makeResult(spec,loaded,error));}
      return specs.map(spec=>{const record=roiCache.get(cacheKey(spec));return Object.assign({},record,{label:mode==='payloads_within_component'?record.measureLabel:record.componentLabel});});
    }};
  }

  function openROIMapper(runtime,state,measures,opts){
    const api=window.NMResultsViewerROIMapper;if(!api||typeof api.open!=='function')throw new Error('ROI Mapper presentation module is unavailable.');return api.open(roiMapperConfig(runtime,state,measures,opts));
  }

  async function roiMapperPublicationOptions(opts,state,selectedMeasureIds,overrides){
    const measures=availableMeasures(opts&&opts.payload),one=normalizeState(copy(state||defaultState(measures)),measures),runtime=await loadWorkspace(opts,null,measures,one,null);
    if(!isSurfaceRuntime(runtime)){
      if(!runtime.nativeFeatureSampling||typeof runtime.nativeFeatureSampling.load!=='function')throw new Error('The authoritative native-grid feature source required by ROI Mapper is unavailable.');await runtime.nativeFeatureSampling.load(opts.fetchArray);
    }else if(one.surfaceAtlasPaths&&(one.surfaceAtlasPaths.selectedPath||one.surfaceAtlasPaths.lhPath||one.surfaceAtlasPaths.rhPath)&&(!runtime.atlas||!runtime.atlas.data))await loadSurfaceAtlas(runtime,one,opts,one.surfaceAtlasPaths.selectedPath||one.surfaceAtlasPaths.lhPath||one.surfaceAtlasPaths.rhPath);
    return roiMapperConfig(runtime,one,measures,opts,Object.assign({},overrides||{},{selectedMeasureIds:arr(selectedMeasureIds).map(text).filter(Boolean)}));
  }

  function downloadBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  async function exportROITable(runtime,state,opts){const output=window.NMResultsViewerOutput;if(!output)throw new Error('The generic Results Viewer output API is unavailable.');if(typeof opts.exportArtifact!=='function')throw new Error('No generic artifact exporter was supplied.');const fields=['roiCode','roiName','totalVox','supportedVox','nPositive','nNegative','pctPositive','pctNegative','pctSuprathreshold','meanValue','stdValue','minValue','maxValue'],columns=fields.map(key=>({key,label:key.replace(/([A-Z])/g,' $1').replace(/^./,c=>c.toUpperCase())})),artifact=output.table({representationId:'imaging.roi_statistics',title:'Imaging ROI statistics',columns,rows:computeROIRows(runtime,state),provenance:{viewerState:copy(state)}});await opts.exportArtifact(artifact,{format:'csv'});}

  function elementIsVisible(el){
    if(!el)return false;
    const r=el.getBoundingClientRect(),cs=window.getComputedStyle?window.getComputedStyle(el):null;
    return r.width>0&&r.height>0&&(!cs||cs.display!=='none'&&cs.visibility!=='hidden');
  }

  function imagingModalViewportRect(){
    let left=0,top=0,right=window.innerWidth,bottom=window.innerHeight;
    const header=document.querySelector('.rvHeader,body>header,.wbHeader');
    if(elementIsVisible(header)){
      const r=header.getBoundingClientRect();
      if(r.top<=2&&r.bottom>0)top=Math.max(top,Math.ceil(r.bottom));
    }
    const rail=document.querySelector('.nmNavRail');
    if(elementIsVisible(rail)){
      const r=rail.getBoundingClientRect();
      const vertical=r.height>=window.innerHeight*.5;
      if(r.left<=2&&r.width<window.innerWidth*.5&&window.innerWidth>760)left=Math.max(left,Math.ceil(r.right));
      else if(!vertical&&r.bottom>=window.innerHeight-2)bottom=Math.min(bottom,Math.floor(r.top));
    }else if(document.body&&document.body.classList.contains('nmHasNavRail')&&!document.body.classList.contains('nmNavRailRolled')&&window.innerWidth>760){
      const css=getComputedStyle(document.documentElement).getPropertyValue('--nmNavRailCollapsed');
      const fallback=parseFloat(css);if(Number.isFinite(fallback))left=Math.max(left,Math.ceil(fallback));
    }
    return {left,top,right,bottom,width:Math.max(0,right-left),height:Math.max(0,bottom-top)};
  }

  function applyImagingModalViewport(modal){
    if(!modal||!modal.isConnected)return;
    const r=imagingModalViewportRect();
    modal.style.setProperty('--rv-imaging-modal-left',`${r.left}px`);
    modal.style.setProperty('--rv-imaging-modal-top',`${r.top}px`);
    modal.style.setProperty('--rv-imaging-modal-right',`${Math.max(0,window.innerWidth-r.right)}px`);
    modal.style.setProperty('--rv-imaging-modal-bottom',`${Math.max(0,window.innerHeight-r.bottom)}px`);
    modal.dataset.viewportWidth=String(r.width);modal.dataset.viewportHeight=String(r.height);
  }

  function bindImagingModalLifecycle(modal,onResize){
    const resize=()=>{applyImagingModalViewport(modal);if(typeof onResize==='function')onResize();};
    const close=()=>{window.removeEventListener('resize',resize);document.removeEventListener('keydown',key);modal.remove();};
    const key=e=>{if(e.key==='Escape')close();};
    applyImagingModalViewport(modal);window.addEventListener('resize',resize);document.addEventListener('keydown',key);
    const closeButton=modal.querySelector('[data-imaging-modal-close]');if(closeButton)closeButton.addEventListener('click',close);
    modal.addEventListener('click',e=>{if(e.target===modal)close();});
    return {close,resize};
  }

  function imagingModalCloseButtonHtml(label){
    return `<button type="button" class="rvImagingModalClose" data-imaging-modal-close aria-label="${escapeHtml(label)}" title="Close"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M6 6l12 12M18 6L6 18"></path></svg></button>`;
  }

  function imagingStateApi(){const api=window.NMImagingViewerState;if(!api||typeof api.apply!=='function'||typeof api.build!=='function'||typeof api.parse!=='function')throw new Error('The canonical imaging-viewer state authority is unavailable.');return api;}
  function replaceState(target,source){Object.keys(target).forEach(key=>delete target[key]);Object.keys(source||{}).forEach(key=>{target[key]=source[key];});return target;}
  function stateSummaryRows(summary){const groups=[['Applied',summary.applied],['Remapped',summary.remapped],['Skipped',summary.skipped],['Incompatible',summary.incompatible]];return groups.map(group=>`<tr><th>${escapeHtml(group[0])}</th><td>${arr(group[1]).length?arr(group[1]).map(escapeHtml).join('<br>'):'—'}</td></tr>`).join('');}
  function showStateCompatibilitySummary(summary){const modal=document.createElement('div');modal.className='rvImagingModal rvImagingStateSummaryModal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.innerHTML=`<div class="rvImagingModalCard"><header><h3>Viewer-state compatibility: ${escapeHtml(summary.outcome||'Unknown')}</h3>${imagingModalCloseButtonHtml('Close viewer-state compatibility')}</header><div class="rvImagingStateSummary"><p><b>Source file:</b> ${escapeHtml(summary.sourceFile||'unnamed')}</p><p><b>Reference grid compatible:</b> ${summary.gridCompatible?'Yes':'No'}</p><table><tbody>${stateSummaryRows(summary)}</tbody></table></div></div>`;document.body.appendChild(modal);bindImagingModalLifecycle(modal);}
  function resetViewerState(runtime,state,measures){
    const current=text(state.activePageMetricId||state.overlayAId),fresh=defaultState(measures),chosen=metricById(measures,current)?current:text(measures[0]&&measures[0].measureId);
    fresh.enabledMetricIds=chosen?[chosen]:[];fresh.activePageMetricId=chosen;fresh.overlayAId=chosen;
    if(isSurfaceRuntime(runtime)){
      fresh.currentVoxel=[1,1,1];fresh.currentWorldMm=surfaceAdapter().vertexWorld(runtime,fresh,0);fresh.selectedTemplateId='native';fresh.selectedAtlasId='';fresh.surfaceAtlasPaths={selectedPath:'',lhPath:'',rhPath:''};
    }else{
      const initial=arr(runtime.payload&&runtime.payload.initialVoxel).slice(0,3).map(Number);fresh.currentVoxel=initial;fresh.currentWorldMm=voxelToWorld(runtime.payload.spatialReference,initial);PLANES.forEach(plane=>{fresh.planes[plane].voxel=initial.slice();});fresh.selectedTemplateId=text(runtime.payload.selectedTemplate&&runtime.payload.selectedTemplate.templateId);fresh.selectedAtlasId=text(runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.atlasId||'none');
    }
    return normalizeState(fresh,measures);
  }

  async function applyStateFile(rootOrId,file,opts,remount){
    const root=typeof rootOrId==='string'?document.getElementById(rootOrId):rootOrId,record=root&&ROOT_RUNTIME.get(root),api=imagingStateApi();if(!record)throw new Error('No mounted imaging viewer is available for state application.');const result=api.apply(file,record.runtime,record.state);replaceState(record.state,result.state);normalizeState(record.state,availableMeasures(record.runtime.payload));if(remount!==false)await mount(opts,true);return result;
  }

  function showROITable(runtime,state,opts){
    const rows=computeROIRows(runtime,state),modal=document.createElement('div');modal.className='rvImagingModal';
    const body=rows.length?`<table><thead><tr><th>ROI</th><th>Code</th><th>Supra %</th><th>Positive</th><th>Negative</th><th>Mean</th><th>SD</th></tr></thead><tbody>${rows.map(r=>`<tr><td>${escapeHtml(r.roiName)}</td><td>${r.roiCode}</td><td>${fmt(r.pctSuprathreshold,2)}</td><td>${r.nPositive}</td><td>${r.nNegative}</td><td>${fmt(r.meanValue,4)}</td><td>${fmt(r.stdValue,4)}</td></tr>`).join('')}</tbody></table>`:'<p>No ROI meets the current threshold/minimum-percentage criterion.</p>';
    const roiElementLabel=isSurfaceRuntime(runtime)?'vertices':'voxels';
    modal.innerHTML=`<div class="rvImagingModalCard"><header><h3>ROI statistics</h3>${imagingModalCloseButtonHtml('Close ROI statistics')}</header><div class="rvImagingModalControls"><label>Minimum suprathreshold ${roiElementLabel} (%) <input type="number" min="0" step="0.1" value="${state.roiMinPct}" data-imaging-roi-min></label><button type="button" class="primary" data-imaging-roi-export>Export CSV</button></div><div class="rvImagingRoiTable">${body}</div></div>`;
    document.body.appendChild(modal);const lifecycle=bindImagingModalLifecycle(modal);
    modal.querySelector('[data-imaging-roi-export]').addEventListener('click',()=>exportROITable(runtime,state,opts).catch(err=>opts.setMessage&&opts.setMessage(`ROI Tabulator export failed: ${err.message||String(err)}`,'danger')));
    modal.querySelector('[data-imaging-roi-min]').addEventListener('change',e=>{state.roiMinPct=Math.max(0,finite(e.target.value,0));lifecycle.close();showROITable(runtime,state,opts);});
  }

  function exportMetadata(runtime,state,label){
    const id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),ov=nativeFeatureOverlay(runtime,id),support=nativeFeatureSupport(runtime),ds=ov?metricDisplayState(state,ov,support):{},tpl=runtime.payload.selectedTemplate||{},atlas=runtime.payload.selectedAtlas||{},surface=isSurfaceRuntime(runtime);
    const sourceLine=surface?'Feature source: authoritative surface vertices':'Feature source: authoritative native grid';
    const locationLine=surface?`Vertex: ${Math.max(1,Math.round(finite(state.currentVoxel&&state.currentVoxel[0],1)))}`:`Voxel: ${planeVoxel(state,runtime,state.lastPlaneId).join(', ')}`;
    return [label,text(ov&&ov.meta.label||''),`${surface?'Geometry':'Template'}: ${surface?text(state.selectedTemplateId||'native'):text(tpl.label||tpl.templateId)}`,`Atlas: ${surface?text(runtime.surfaceRuntime&&runtime.surfaceRuntime.atlas&&runtime.surfaceRuntime.atlas.label||'none'):text(atlas.available?(atlas.label||atlas.atlasId):'none')}`,surface?'':`Anatomy interpolation: ${normalizedDisplayInterpolation(state.anatomyInterpolation)}`,sourceLine,surface?'':`Feature interpolation: ${effectiveFeatureInterpolation(runtime,state).replace(/_/g,' ')}`,`Data range: ${fmt(ds.exactDataRange&&ds.exactDataRange[0],4)} … ${fmt(ds.exactDataRange&&ds.exactDataRange[1],4)}`,`Display range (${text(ds.displayRangeMode).replace(/_/g,' ')}): ${fmt(ds.activeDisplayRange&&ds.activeDisplayRange[0],4)} … ${fmt(ds.activeDisplayRange&&ds.activeDisplayRange[1],4)}`,state.stateFileName?`Viewer state: ${state.stateFileName} · ${state.stateCompatibilityStatus||'unclassified'}`:'',locationLine,`Thresholds: ${fmt(ds.thresholdLow,4)} / ${fmt(ds.thresholdHigh,4)} / ${fmt(ds.thresholdValue,4)}`].filter(Boolean);
  }
  function decoratedPlaneCanvas(source,runtime,plane,state){
    const out=document.createElement('canvas');out.width=source.width;out.height=source.height;const ctx=out.getContext('2d');ctx.drawImage(source,0,0);const featureCanvas=source.parentElement&&source.parentElement.querySelector(`[data-imaging-feature-canvas="${plane}"]`);if(featureCanvas&&featureCanvas.width&&featureCanvas.height)ctx.drawImage(featureCanvas,0,0,out.width,out.height);
    if(state&&state.crosshairVisible)drawPlaneCrosshair(ctx,runtime,state,plane,out.width,out.height);
    const labels=planeDefinition(runtime,plane).orientationLabels||{},font=Math.max(12,Math.round(Math.min(out.width,out.height)*.035));
    ctx.font=`bold ${font}px Arial`;ctx.textBaseline='middle';ctx.lineWidth=Math.max(2,font*.18);ctx.strokeStyle='rgba(0,0,0,.9)';ctx.fillStyle='#fff';
    const draw=(value,x,y,align)=>{if(!value)return;ctx.textAlign=align;ctx.strokeText(String(value),x,y);ctx.fillText(String(value),x,y);};
    draw(labels.left,6,out.height/2,'left');draw(labels.right,out.width-6,out.height/2,'right');draw(labels.top,out.width/2,font*.7,'center');draw(labels.bottom,out.width/2,out.height-font*.7,'center');return out;
  }
  function exportLegend(runtime,state){
    const id=state.focusedOverlaySlot==='B'&&state.dualOverlayEnabled&&state.overlayBId?state.overlayBId:(state.overlayAId||state.activePageMetricId),ov=nativeFeatureOverlay(runtime,id);if(!ov)return null;const support=nativeFeatureSupport(runtime),display=metricDisplayState(state,ov,support),model=displaySemantics().colorbarModel(ov,display,support),range=arr(ov.meta.valueRange).map(Number),kind=model?model.kind:'signed';
    return {label:text(ov.meta.label||ov.meta.measureId),kind,negative:display.negativeColor||DEFAULT_COLORS.negative,midpoint:display.midpointColor||DEFAULT_COLORS.midpoint,positive:display.positiveColor||DEFAULT_COLORS.positive,colorStops:colorGradient().resolvedStops(display,kind),min:model?model.min:finite(range[0],NaN),max:model?model.max:finite(range[1],NaN),rangeMode:model.displayRangeMode,thresholdValues:model.thresholds,thresholds:kind==='signed'?`${fmt(display.thresholdLow,4)} / ${fmt(display.thresholdHigh,4)}`:fmt(display.thresholdValue,4)};
  }
  function fillLegendGradient(ctx,gradient,legend){legend.colorStops.forEach(stop=>gradient.addColorStop(stop.position,stop.color));}
  function composedCanvas(canvases,labels,legend){
    const pad=16,legendHeight=legend?46:0,header=legendHeight,maxH=Math.max(...canvases.map(c=>c.height)),width=canvases.reduce((sum,c)=>sum+c.width,0)+pad*(canvases.length+1),height=header+maxH+48,out=document.createElement('canvas');out.width=width;out.height=height;const ctx=out.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,width,height);
    if(legend){const y=8,barW=Math.min(360,Math.max(180,width*.35)),gradient=ctx.createLinearGradient(pad,0,pad+barW,0);fillLegendGradient(ctx,gradient,legend);ctx.fillStyle=gradient;ctx.fillRect(pad,y,barW,13);ctx.strokeStyle='#555';ctx.strokeRect(pad,y,barW,13);ctx.fillStyle='#111';ctx.font='12px Arial';ctx.textAlign='left';ctx.fillText(fmt(legend.min,4),pad,y+29);ctx.textAlign='right';ctx.fillText(fmt(legend.max,4),pad+barW,y+29);ctx.textAlign='left';ctx.fillText(`Thresholds: ${legend.thresholds}`,pad+barW+16,y+11);}
    let x=pad;canvases.forEach((c,i)=>{ctx.fillStyle='#111';ctx.textAlign='left';ctx.font='bold 14px Arial';ctx.fillText(labels[i]||'',x,header+16);ctx.drawImage(c,x,header+24);x+=c.width+pad;});return out;
  }
  function capture2D(root,runtime,state,kind,options){
    const output=window.NMResultsViewerOutput;if(!output)throw new Error('The generic Results Viewer output API is unavailable.');const opts=options||{},viewMode=text(opts.viewMode||'current'),captureState=copy(state);
    if(viewMode==='montage'&&opts.montageState&&typeof opts.montageState==='object')captureState.multiSlice=normalizeMultiSlice(Object.assign({},captureState.multiSlice||{},opts.montageState));
    let canvas,label;if(viewMode==='montage'||kind==='multi_slice'){
      canvas=montageCanvas(runtime,captureState);label='Multi-slice imaging overlay';kind='multi_slice';
    }else{
      const requested=viewMode==='canonical'?arr(opts.canonicalViews).map(text).filter(plane=>PLANES.includes(plane)):[],planes=requested.length?requested:(kind==='active'?[captureState.lastPlaneId||'axial']:PLANES.filter(plane=>root.querySelector(`[data-imaging-canvas="${plane}"]`)));planes.forEach(plane=>drawPlane(runtime,captureState,plane,root.querySelector(`[data-imaging-canvas="${plane}"]`),true));
      if(planes.length===1){const plane=planes[0],source=root.querySelector(`[data-imaging-canvas="${plane}"]`);if(!source)throw new Error('The requested imaging plane is unavailable.');label=viewMode==='canonical'?`${planeDefinition(runtime,plane).displayLabel} imaging view`:'Active imaging plane';canvas=composedCanvas([decoratedPlaneCanvas(source,runtime,plane,captureState)],[planeDefinition(runtime,plane).displayLabel],exportLegend(runtime,captureState));}
      else{label=viewMode==='canonical'?'Canonical imaging planes':'Tri-planar imaging overlay';const canvases=planes.map(plane=>decoratedPlaneCanvas(root.querySelector(`[data-imaging-canvas="${plane}"]`),runtime,plane,captureState));canvas=composedCanvas(canvases,planes.map(plane=>planeDefinition(runtime,plane).displayLabel),exportLegend(runtime,captureState));}
    }
    return output.fromCanvas(canvas,{representationId:'imaging.2d',captureVariant:viewMode==='canonical'?'canonical':kind,title:label,metadata:{viewerState:copy(captureState),presentation:{lines:exportMetadata(runtime,captureState,label),legend:exportLegend(runtime,captureState)}},provenance:opts.provenance||{}});
  }
  async function capture(rootOrId,options){const root=typeof rootOrId==='string'?document.getElementById(rootOrId):rootOrId,record=root&&ROOT_RUNTIME.get(root);if(!record)throw new Error('No published imaging representation is available.');const kind=String(options&&options.captureVariant||'triplanar');if(record.state.activeViewMode==='three_dimensional')return imaging3DController().capture(root,Object.assign({},options,{captureVariant:kind}));return capture2D(root,record.runtime,record.state,kind,options);}
  async function publish(request,host){const opts=Object.assign({},request&&request.mountOptions||request||{},{root:host}),live=await mount(opts,!!(request&&request.forceReload)),record=live&&ROOT_RUNTIME.get(live);if(record&&record.presentationReady)await record.presentationReady;return {host:live||host};}
  async function exportPublished(root,opts,kind){try{const artifact=await capture(root,{captureVariant:kind});if(typeof opts.exportArtifact!=='function')throw new Error('No generic artifact exporter was supplied.');await opts.exportArtifact(artifact);}catch(err){if(typeof opts.setMessage==='function')opts.setMessage(`Viewer export failed: ${err.message||String(err)}`,'danger');}}

  function multiSliceIndices(runtime,state){const ms=state.multiSlice,g=planeGeometry(runtime,ms.planeId),count=ms.rows*ms.columns,start=clamp(Math.round(finite(ms.startSlice,1)),1,g.max),end=clamp(Math.round(finite(ms.endSlice,g.max)),start,g.max);if(count===1)return[start];return Array.from({length:count},(_,i)=>Math.round(start+i*(end-start)/(count-1)));}

  function montageSliceLabel(runtime,state,plane,slice){
    const mode=state.multiSlice.labelMode||'world';if(mode==='none')return '';
    const def=planeDefinition(runtime,plane),voxel=runtime.dims.map(d=>Math.round((d+1)/2));voxel[def.normalVoxelAxis-1]=slice;
    const world=voxelToWorld(runtime.payload.spatialReference,voxel),axis=plane==='sagittal'?0:(plane==='coronal'?1:2),axisName=plane==='sagittal'?'x':(plane==='coronal'?'y':'z');
    const worldText=Number.isFinite(world[axis])?`${axisName} = ${fmt(world[axis],1)} mm`:`slice ${slice}`;
    if(mode==='index')return `slice ${slice}`;
    if(mode==='both')return `${worldText} · ${slice}`;
    return worldText;
  }

  function montageAxisBounds(counts,tailFraction){
    const total=Array.from(counts).reduce((sum,value)=>sum+value,0);
    if(!(total>0))return null;
    const tail=Math.max(0,total*clamp(finite(tailFraction,.0025),0,.05));
    let cumulative=0,low=0,high=counts.length-1;
    for(let i=0;i<counts.length;i++){cumulative+=counts[i];if(cumulative>=tail){low=i;break;}}
    cumulative=0;
    for(let i=counts.length-1;i>=0;i--){cumulative+=counts[i];if(cumulative>=tail){high=i;break;}}
    return high>=low?[low,high]:null;
  }

  function commonMontageCrop(runtime,state,plane,indices){
    if(state.multiSlice.fitMode!=='tight')return null;
    const g=planeGeometry(runtime,plane),d=planeDefinition(runtime,plane),dims=runtime.dims,windowVals=arr(runtime.payload.structural.window).map(Number),lo=finite(windowVals[0],0),hi=finite(windowVals[1],lo+1),threshold=lo+Math.max(Number.EPSILON,(hi-lo)*.03),h=d.horizontalVoxelAxis-1,v=d.verticalVoxelAxis-1,n=d.normalVoxelAxis-1;
    const columnCounts=new Float64Array(g.w),rowCounts=new Float64Array(g.h);
    indices.forEach(slice=>{for(let row=0;row<g.h;row++)for(let col=0;col<g.w;col++){const voxel=[0,0,0];voxel[h]=d.horizontalDirection>0?col:dims[h]-1-col;voxel[v]=d.verticalDirection>0?row:dims[v]-1-row;voxel[n]=slice-1;const idx=volumeIndex(dims,voxel[0],voxel[1],voxel[2]),sv=Number(runtime.structural[idx]);if(Number.isFinite(sv)&&sv>threshold){columnCounts[col]+=1;rowCounts[row]+=1;}}});
    const xb=montageAxisBounds(columnCounts,.0025),yb=montageAxisBounds(rowCounts,.0025);
    if(!xb||!yb)return null;
    const base=Math.max(xb[1]-xb[0]+1,yb[1]-yb[0]+1),margin=Math.max(2,Math.round(base*.035));
    const minX=Math.max(0,xb[0]-margin),minY=Math.max(0,yb[0]-margin),maxX=Math.min(g.w-1,xb[1]+margin),maxY=Math.min(g.h-1,yb[1]+margin);
    return {x:minX,y:minY,w:maxX-minX+1,h:maxY-minY+1};
  }

  function drawMontageLabel(canvas,label,state,ratio){
    if(!label)return canvas;
    const ctx=canvas.getContext('2d'),requested=state.multiSlice.labelFontPx*ratio,font=Math.max(6*ratio,Math.min(requested,Math.round(Math.min(canvas.width,canvas.height)*.18))),pad=Math.max(2*ratio,Math.round(font*.3));ctx.save();ctx.font=`600 ${font}px Arial`;ctx.textBaseline='top';const width=Math.ceil(ctx.measureText(label).width)+2*pad,height=Math.ceil(font*1.25)+2*pad;let x=5*ratio,y=5*ratio;const pos=state.multiSlice.labelPosition;if(pos.includes('right'))x=Math.max(5*ratio,canvas.width-width-5*ratio);if(pos.includes('bottom'))y=Math.max(5*ratio,canvas.height-height-5*ratio);ctx.fillStyle='rgba(0,0,0,.62)';ctx.fillRect(x,y,width,height);ctx.lineWidth=Math.max(2,font*.15);ctx.strokeStyle='rgba(0,0,0,.95)';ctx.fillStyle='#fff';ctx.strokeText(label,x+pad,y+pad);ctx.fillText(label,x+pad,y+pad);ctx.restore();return canvas;
  }

  function composeMontageCanvas(canvases,columns,gap,legend,ratio){
    const pad=16*ratio,cols=Math.max(1,columns),rows=Math.ceil(canvases.length/cols);
    const cellW=Math.max(...canvases.map(c=>c.width)),cellH=Math.max(...canvases.map(c=>c.height));
    const gridWidth=pad*2+cols*cellW+(cols-1)*gap,height=pad*2+rows*cellH+(rows-1)*gap;
    const scale=Math.max(gridWidth/1500,height/780),out=document.createElement('canvas');out.width=gridWidth+(legend?Math.ceil(176*scale):0);out.height=height;
    const ctx=out.getContext('2d');ctx.fillStyle='#000';ctx.fillRect(0,0,out.width,height);
    canvases.forEach((c,i)=>{const row=Math.floor(i/cols),col=i%cols;ctx.drawImage(c,pad+col*(cellW+gap)+(cellW-c.width)/2,pad+row*(cellH+gap)+(cellH-c.height)/2);});
    if(legend)colorGradient().drawMontageColorbar(ctx,legend,gridWidth,height,scale,{text:'#fff',border:'#ddd',threshold:'#ffe082'});
    return out;
  }

  function montageCanvas(runtime,state,viewport){
    const plane=state.multiSlice.planeId,ids=multiSliceIndices(runtime,state),crop=commonMontageCrop(runtime,state,plane,ids),ms=state.multiSlice,g=planeGeometry(runtime,plane),legend=exportLegend(runtime,state);
    const width=32+ms.columns*(crop?crop.w:g.w)+(ms.columns-1)*ms.gapPx,height=32+ms.rows*(crop?crop.h:g.h)+(ms.rows-1)*ms.gapPx;
    const totalWidth=width+(legend?Math.ceil(176*Math.max(width/1500,height/780)):0),ratio=viewport?Math.max(1,Math.min(6,Math.ceil(Math.min(viewport.clientWidth/totalWidth,viewport.clientHeight/height)*window.devicePixelRatio))):1;
    const canvases=ids.map(slice=>{
      const raw=document.createElement('canvas'),tile=document.createElement('canvas'),one=copy(state);setPlaneSlice(one,runtime,plane,slice);drawPlane(runtime,one,plane,raw,true);
      const sx=crop?crop.x:0,sy=crop?crop.y:0,sw=crop?crop.w:raw.width,sh=crop?crop.h:raw.height;
      tile.width=sw*ratio;tile.height=sh*ratio;
      const ctx=tile.getContext('2d');configureCanvasInterpolation(ctx,state.displayInterpolation);
      ctx.drawImage(raw,sx,sy,sw,sh,0,0,tile.width,tile.height);return drawMontageLabel(tile,montageSliceLabel(runtime,state,plane,slice),state,ratio);
    });
    return composeMontageCanvas(canvases,ms.columns,ms.gapPx*ratio,legend,ratio);
  }

  function multiSliceControlsHtml(runtime,state,options){
    const opts=options||{},ms=normalizeMultiSlice(state&&state.multiSlice!==undefined?state.multiSlice:state),disabled=opts.disabled?' disabled':'',planeLabel=plane=>runtime?planeDefinition(runtime,plane).displayLabel:(plane.charAt(0).toUpperCase()+plane.slice(1)),endSlice=Number.isFinite(ms.endSlice)?ms.endSlice:(runtime?planeGeometry(runtime,ms.planeId).max:'');
    return `<label>Plane<select data-ms-plane${disabled}>${PLANES.map(p=>`<option value="${p}"${ms.planeId===p?' selected':''}>${escapeHtml(planeLabel(p))}</option>`).join('')}</select></label><label>Rows<input type="number" min="1" max="6" value="${ms.rows}" data-ms-rows${disabled}></label><label>Columns<input type="number" min="1" max="6" value="${ms.columns}" data-ms-cols${disabled}></label><label>Start<input type="number" min="1" value="${ms.startSlice}" data-ms-start${disabled}></label><label>End<input type="number" min="1" value="${endSlice}" data-ms-end${disabled}></label><label>Gap (px)<input type="number" min="0" max="24" value="${ms.gapPx}" data-ms-gap${disabled}></label><label>Slice labels<select data-ms-label${disabled}><option value="world"${ms.labelMode==='world'?' selected':''}>World coordinate</option><option value="index"${ms.labelMode==='index'?' selected':''}>Slice index</option><option value="both"${ms.labelMode==='both'?' selected':''}>World + index</option><option value="none"${ms.labelMode==='none'?' selected':''}>Off (hide labels)</option></select></label><label>Fit<select data-ms-fit${disabled}><option value="full"${ms.fitMode==='full'?' selected':''}>Full field</option><option value="tight"${ms.fitMode==='tight'?' selected':''}>Tight anatomy</option></select></label><label>Label position<select data-ms-label-position${disabled}><option value="top_left"${ms.labelPosition==='top_left'?' selected':''}>Top left</option><option value="top_right"${ms.labelPosition==='top_right'?' selected':''}>Top right</option><option value="bottom_left"${ms.labelPosition==='bottom_left'?' selected':''}>Bottom left</option><option value="bottom_right"${ms.labelPosition==='bottom_right'?' selected':''}>Bottom right</option></select></label><label>Label size<input type="number" min="9" max="28" value="${ms.labelFontPx}" data-ms-label-size${disabled}></label>`;
  }

  function readMultiSliceControls(root,value,runtime){
    if(!root||typeof root.querySelector!=='function')throw new Error('The Montage Maker control host is unavailable.');
    const current=normalizeMultiSlice(value&&value.multiSlice!==undefined?value.multiSlice:value),plane=root.querySelector('[data-ms-plane]'),rows=root.querySelector('[data-ms-rows]'),columns=root.querySelector('[data-ms-cols]'),start=root.querySelector('[data-ms-start]'),end=root.querySelector('[data-ms-end]'),gap=root.querySelector('[data-ms-gap]'),label=root.querySelector('[data-ms-label]'),fit=root.querySelector('[data-ms-fit]'),labelPosition=root.querySelector('[data-ms-label-position]'),labelSize=root.querySelector('[data-ms-label-size]');
    if(![plane,rows,columns,start,end,gap,label,fit,labelPosition,labelSize].every(Boolean))throw new Error('The Montage Maker control set is incomplete.');
    current.planeId=plane.value;current.rows=rows.value;current.columns=columns.value;current.startSlice=start.value;current.endSlice=end.value;current.gapPx=gap.value;current.labelMode=label.value;current.fitMode=fit.value;current.labelPosition=labelPosition.value;current.labelFontPx=labelSize.value;
    const normalized=normalizeMultiSlice(current);
    if(runtime&&!Number.isFinite(normalized.endSlice))normalized.endSlice=planeGeometry(runtime,normalized.planeId).max;
    return normalized;
  }

  function showMultiSlice(root,runtime,state,opts){
    const modal=document.createElement('div');modal.className='rvImagingModal rvImagingMultiSliceModal';modal.setAttribute('role','dialog');modal.setAttribute('aria-modal','true');modal.setAttribute('aria-label','Multi-slice view');
    modal.innerHTML=`<div class="rvImagingModalCard"><header><h3>Multi-slice view</h3>${imagingModalCloseButtonHtml('Close multi-slice view')}</header><div class="rvImagingModalControls rvImagingMultiSliceControls">${multiSliceControlsHtml(runtime,state)}<button type="button" class="primary" data-ms-export>Export montage</button></div><div class="rvImagingMultiSliceGrid" data-ms-grid></div></div>`;
    document.body.appendChild(modal);const grid=modal.querySelector('[data-ms-grid]');
    const render=()=>{if(modal.isConnected)grid.replaceChildren(montageCanvas(runtime,state,grid));};
    const sync=()=>{state.multiSlice=readMultiSliceControls(modal,state.multiSlice,runtime);notify(opts,state,'multi_slice');render();};
    Array.from(modal.querySelectorAll('select,input')).forEach(x=>{x.addEventListener('change',sync);if(x.type==='number')x.addEventListener('keydown',event=>{if(event.key==='Enter')x.blur();});});
    bindImagingModalLifecycle(modal);
    modal.querySelector('[data-ms-export]').addEventListener('click',()=>exportPublished(root,opts,'multi_slice'));
    render();
  }

  function notify(opts,state,reason,identity){const canonical=identity?interactionIdentity().assertIdentity(identity):null;if(typeof opts.onStateChange==='function')opts.onStateChange(state,reason||'state',canonical);}

  function planeSliceSnapshot(runtime,state){
    const out={};PLANES.forEach(plane=>{out[plane]=Math.round(currentSlice(state,runtime,plane));});return out;
  }

  function changedSlicePlanes(runtime,state,before){
    return PLANES.filter(plane=>!before||Math.round(currentSlice(state,runtime,plane))!==before[plane]);
  }

  function updatePlanePresentations(runtime,state,root,planes){
    arr(planes&&planes.length?planes:PLANES).forEach(plane=>updatePlanePresentation(runtime,state,plane,root.querySelector(`[data-imaging-canvas="${plane}"]`)));
    updatePlaneCrosshairs(root,runtime,state,planes&&planes.length?planes:PLANES);
  }

  function redraw(runtime,state,root,opts,profileInitial,planes){
    if(state.activeViewMode==='three_dimensional'){
      imaging3DController().redraw(root);
      return;
    }
    const targets=arr(planes&&planes.length?planes:PLANES).filter(p=>PLANES.includes(p)),totalStarted=profileInitial?performance.now():0;
    const gpuRendered=renderWithGpu(runtime,state,root,targets);
    if(!gpuRendered){
      targets.forEach(p=>{
        const planeStarted=profileInitial?performance.now():0;
        drawPlane(runtime,state,p,root.querySelector(`[data-imaging-canvas="${p}"]`));
        if(profileInitial)profile(opts,`first ${p} canvas draw`,planeStarted,`slice=${Math.round(currentSlice(state,runtime,p))}`);
      });
    }else if(profileInitial)profile(opts,'first shared WebGL plane draw',totalStarted,`planes=${targets.length}`);
    const readoutStarted=profileInitial?performance.now():0;updateReadouts(runtime,state,root);
    if(profileInitial){
      profile(opts,'first readout update',readoutStarted,'voxel/world/atlas/value=1');
      profile(opts,'first canvas render TOTAL',totalStarted,`planes=${targets.length}`);
    }
  }

  function resetImagingScrollPositions(root){
    if(!root)return;
    const nodes=[root,root.querySelector('[data-imaging-body]')].concat(Array.from(root.querySelectorAll('.rvImagingSide,.rvImaging3DControls,.rvImaging3DPresentation')));
    let ancestor=root.parentElement,depth=0;
    while(ancestor&&ancestor!==document.body&&depth<8){
      const style=window.getComputedStyle?window.getComputedStyle(ancestor):null,scrollable=ancestor.scrollHeight>ancestor.clientHeight+1||ancestor.scrollWidth>ancestor.clientWidth+1||style&&/(auto|scroll)/.test(`${style.overflow} ${style.overflowY} ${style.overflowX}`);
      if(scrollable)nodes.push(ancestor);
      ancestor=ancestor.parentElement;depth++;
    }
    Array.from(new Set(nodes.filter(Boolean))).forEach(node=>{node.scrollTop=0;node.scrollLeft=0;});
  }

  function viewportGeometrySignature(root){
    if(!root)return '';
    if(root.querySelector('[data-imaging-3d-viewport]'))return `3d:${imaging3DController().geometrySignature(root)}`;
    const parts=[root.clientWidth,root.clientHeight];
    PLANES.forEach(p=>{const frame=root.querySelector(`[data-imaging-frame="${p}"]`);parts.push(frame?frame.clientWidth:0,frame?frame.clientHeight:0);});
    return parts.join('x');
  }

  function bindRuntime(opts,root,runtime,state,measures){
    const bindStarted=performance.now(),pendingPlanes=new Set();let renderRaf=0,commitTimer=0,gpuSession=null,gpuInitHandle=0,displayControlBinding=null,scientificRefreshSequence=0,controlHost=null,contextMenuDocumentListener=null,lastGeometry='';
    const rebindScientificContext=(payload,bindings)=>{const previous={payload:opts.payload,selectedSpec:opts.selectedSpec,onStateChange:opts.onStateChange,measures};const next=bindings&&typeof bindings==='object'?bindings:{};if(next.state)replaceState(state,next.state);if(payload){opts.payload=payload;measures=availableMeasures(payload);normalizeState(state,measures);}if(typeof next.selectedSpec==='function')opts.selectedSpec=next.selectedSpec;if(typeof next.onStateChange==='function')opts.onStateChange=next.onStateChange;return previous;};
    const restoreScientificContext=(previous,previousState)=>{if(!previous)return;opts.payload=previous.payload;opts.selectedSpec=previous.selectedSpec;opts.onStateChange=previous.onStateChange;measures=previous.measures;replaceState(state,previousState);normalizeState(state,measures);};
    const flushRender=()=>{renderRaf=0;if(!root.isConnected)return;const targets=Array.from(pendingPlanes);pendingPlanes.clear();if(targets.length)redraw(runtime,state,root,opts,false,targets);};
    const scheduleRender=planes=>{arr(planes).forEach(p=>{if(PLANES.includes(p))pendingPlanes.add(p);});if(!renderRaf)renderRaf=requestAnimationFrame(flushRender);};
    const scheduleCommit=(reason,delay,identitySource)=>{if(commitTimer)clearTimeout(commitTimer);commitTimer=setTimeout(()=>{commitTimer=0;const identity=typeof identitySource==='function'?identitySource():identitySource;notify(opts,state,reason,identity||null);},Math.max(0,finite(delay,120)));};
    const commitNow=(reason,identity)=>{if(commitTimer){clearTimeout(commitTimer);commitTimer=0;}notify(opts,state,reason,identity);};
    const refreshReadouts=()=>updateReadouts(runtime,state,root);
    const synchronizeTopbar=()=>synchronizeMetricShell(root,state,measures);
    const setRepresentationPending=(representationId,pending)=>{Array.from(root.querySelectorAll('[data-imaging-view-mode]')).forEach(btn=>{const match=text(btn.getAttribute('data-imaging-view-mode'))===text(representationId);btn.classList.toggle('isPending',!!pending&&match);if(match){if(pending)btn.setAttribute('aria-busy','true');else btn.removeAttribute('aria-busy');}});};
    const browserFamily=()=>{const ua=String(navigator&&navigator.userAgent||'');if(/Firefox\//i.test(ua))return 'firefox';if(/Edg\//i.test(ua))return 'edge';const uaData=navigator&&navigator.userAgentData,brands=uaData&&Array.isArray(uaData.brands)?uaData.brands.map(item=>String(item&&item.brand||'')):[];if(brands.includes('Google Chrome'))return 'chrome';if(!brands.length&&/Chrome\//i.test(ua)&&String(navigator&&navigator.vendor||'')==='Google Inc.'&&!(navigator&&navigator.brave)&&!/OPR\/|Vivaldi\//i.test(ua))return 'chrome';return '';};
    const requestHardGpuHostRestart=async()=>{const relay=window.NM_HTML_RELAY===true,family=relay?'':browserFamily(),warning=relay?'This will close and recreate the active NM2 embedded graphics window. Continue?':'This will close the entire browser, including all open windows and tabs, then restart NM2 from MATLAB. Continue?';if(!window.confirm(warning))return false;if(!relay&&!family)throw new Error('Automatic full-browser restart is unavailable for this browser. Close the browser completely and restart NM2 from MATLAB.');const response=await fetch('/api/close',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({closed:true,reason:'gpu_host_restart',gpuHostRestart:true,gpuHostTransport:relay?'html-relay':'browser',browserFamily:family})});if(!response.ok)throw new Error(`The graphics-host restart request was rejected (${response.status}).`);return true;};
    const refreshOverlayPresentation=(redraw3D=true)=>{
      if(state.activeViewMode==='three_dimensional'){const controller=imaging3DController();controller.replaceOverlayControls(root,runtime,state,opts.escape);if(displayControlBinding&&typeof displayControlBinding.refresh==='function')displayControlBinding.refresh();if(redraw3D)controller.redraw(root);refreshReadouts();return;}
      replace2DOverlayControls(root,runtime,state,opts.escape);if(displayControlBinding&&typeof displayControlBinding.refresh==='function')displayControlBinding.refresh();scheduleRender(PLANES);refreshReadouts();
    };
    /* Purpose: replace scientific payload resources in the mounted imaging view.
     * Authority and flow: the workspace/feature-resource services own scientific
     * materialization; this boundary retains browser presentation resources whose
     * content identity is unchanged. In 2-D, structural arrays, CPU anatomy
     * rasters, WebGL context/program and structural texture are retained.
     * Invariants: a structural-identity change requires the existing full mount;
     * feature/support/atlas resources may change without rematerializing anatomy.
     * Materialization/performance: no source discovery occurs here; only changed
     * binary feature assets are hydrated/uploaded on a retained payload switch.
     * Failure semantics: incompatible retained state falls back to full mount;
     * failed updates restore the previous scientific selection. */
    async function refreshScientificPayload(reason,rollbackState){
      const sequence=++scientificRefreshSequence,startedAt=performance.now(),threeDimensional=state.activeViewMode==='three_dimensional',viewLabel=threeDimensional?'3-D':'2-D',controller=threeDimensional?imaging3DController():null;
      root.dataset.imagingStatus='updating';
      try{
        const previousRuntime=runtime,previousAtlas=previousRuntime.payload.selectedAtlas,residentAtlasId=previousAtlas.available?text(previousAtlas.atlasId):'',requestedAtlasId=text(state.selectedAtlasId)==='none'?'':text(state.selectedAtlasId),destinationWorkspaceRequired=reason==='scientific_selection'&&residentAtlasId!==requestedAtlasId;let nextRuntime,featureResource=null;if(retainedFeatureResourceReason(reason)&&!destinationWorkspaceRequired){featureResource=await loadFeatureResource(opts,root,measures,state,previousRuntime,reason);if(featureResource.requiresWorkspace){profile(opts,`${viewLabel} retained feature resource requires workspace`,startedAt,`reason=${reason} detail=${text(featureResource.message)}`);nextRuntime=await loadWorkspace(opts,root,measures,state,previousRuntime);}else nextRuntime=featureResource.runtime;}else nextRuntime=await loadWorkspace(opts,root,measures,state,previousRuntime);if(sequence!==scientificRefreshSequence||!root.isConnected)return {retained:false,reason:'stale_viewer_request'};
        if(!isSurfaceRuntime(nextRuntime)){
          if(!nextRuntime.nativeFeatureSampling||typeof nextRuntime.nativeFeatureSampling.load!=='function')throw new Error(`The authoritative native-grid feature source required by the ${viewLabel} viewer is unavailable.`);
          if(previousRuntime&&previousRuntime.nativeFeatureSampling&&typeof nextRuntime.nativeFeatureSampling.reuseFrom==='function')nextRuntime.nativeFeatureSampling.reuseFrom(previousRuntime.nativeFeatureSampling);
          await nextRuntime.nativeFeatureSampling.load(opts.fetchArray);
        }
        if(isSurfaceRuntime(nextRuntime)){
          const atlasPath=state.surfaceAtlasPaths.selectedPath||state.surfaceAtlasPaths.lhPath||state.surfaceAtlasPaths.rhPath;
          if(atlasPath&&(!nextRuntime.atlas||!nextRuntime.atlas.data||text(nextRuntime.payload.selectedAtlas.selectedPath)!==text(atlasPath)))await loadSurfaceAtlas(nextRuntime,state,opts,atlasPath);
        }
        if(sequence!==scientificRefreshSequence||!root.isConnected)return {retained:false,reason:'stale_viewer_request'};
        state.contentId=text(nextRuntime.payload&&nextRuntime.payload.contentId);if(!state.selectedTemplateId&&nextRuntime.payload.selectedTemplate&&nextRuntime.payload.selectedTemplate.available)state.selectedTemplateId=text(nextRuntime.payload.selectedTemplate.templateId);if(!state.selectedAtlasId&&nextRuntime.payload.selectedAtlas&&nextRuntime.payload.selectedAtlas.available)state.selectedAtlasId=text(nextRuntime.payload.selectedAtlas.atlasId);normalizeState(state,measures);normalizeWorkspaceCapabilities(state,nextRuntime);
        let result;if(destinationWorkspaceRequired){result={retained:false,reason:'destination_scientific_state_changed'};}else
        if(threeDimensional){
          result=controller&&typeof controller.updateRuntime==='function'?await controller.updateRuntime({root,runtime:nextRuntime,state,reason,escape:opts.escape}):{retained:false,reason:'update_contract_unavailable'};
        }else{
          if(isSurfaceRuntime(nextRuntime)||(!featureResource&&!workspaceStructuralReuseCompatible(previousRuntime,nextRuntime.payload,nextRuntime.dims)))result={retained:false,reason:'structural_identity_changed'};
          else{
            const n=nextRuntime.dims[0]*nextRuntime.dims[1]*nextRuntime.dims[2];nextRuntime.structural=previousRuntime.structural;if(!featureResource)nextRuntime.support=previousRuntime.support;if(previousRuntime._interactive2D)nextRuntime._interactive2D=previousRuntime._interactive2D;if(nextRuntime.atlas&&previousRuntime.atlas&&reusableAsset(previousRuntime.atlas.meta,nextRuntime.atlas.meta,previousRuntime.atlas.data,n))nextRuntime.atlas.data=previousRuntime.atlas.data;
            result=gpuSession&&typeof gpuSession.updateRuntime==='function'?gpuSession.updateRuntime(nextRuntime):{retained:true,rendererReady:false,structuralRetained:true,featureChanged:true,atlasChanged:nextRuntime.atlas!==previousRuntime.atlas};
          }
        }
        if(sequence!==scientificRefreshSequence||!root.isConnected)return {retained:false,reason:'stale_viewer_request'};
        if(!result||!result.retained){profile(opts,`${viewLabel} scientific payload update fallback`,startedAt,`reason=${reason} fallback=${text(result&&result.reason||'unknown')}`);await mount(opts,threeDimensional);return result||{retained:false};}
        runtime=nextRuntime;const record=ROOT_RUNTIME.get(root);if(record){record.runtime=runtime;record.scientificSignature=scientificTabSignature(state);}synchronizeTopbar();synchronizeAtlasDependentControls(root,runtime,state);if(!threeDimensional)replace2DOverlayControls(root,runtime,state,opts.escape);if(displayControlBinding&&typeof displayControlBinding.refresh==='function')displayControlBinding.refresh();
        if(!threeDimensional){updatePlanePresentations(runtime,state,root,PLANES);redraw(runtime,state,root,opts,false,PLANES);}
        root.dataset.imagingStatus='ready';
        profile(opts,`${viewLabel} scientific payload update TOTAL`,startedAt,`reason=${reason} structuralRetained=${result.structuralRetained?1:0} featureChanged=${result.featureChanged?1:0} atlasChanged=${result.atlasChanged?1:0}${threeDimensional?` rendererSessionId=${text(result.rendererSessionId)}`:''}`);return result;
      }catch(err){
        if(sequence!==scientificRefreshSequence)return {retained:false,reason:'stale_viewer_request'};
        if(rollbackState)replaceState(state,rollbackState);normalizeState(state,measures);normalizeWorkspaceCapabilities(state,runtime);synchronizeTopbar();root.dataset.imagingStatus='ready';notify(opts,state,'scientific_payload_rollback');if(typeof opts.setMessage==='function')opts.setMessage(`The ${viewLabel} view could not be updated. The previous view remains active.`,'danger');profile(opts,`${viewLabel} scientific payload update failure`,startedAt,`reason=${reason} message=${err&&err.message||String(err)}`);return {retained:false,reason:'update_failed',error:err};
      }
    }
    function applyViewportResize(detail){
      if(!root.isConnected)return;
      applyViewportHeight(root);applyControlWidthClass(root);
      const nextGeometry=viewportGeometrySignature(root);
      if(state.activeViewMode==='three_dimensional'){
        const controller=imaging3DController();
        if(controller&&typeof controller.resize==='function')controller.resize(root,detail||{});
      }else if(lastGeometry&&nextGeometry!==lastGeometry){updatePlanePresentations(runtime,state,root,PLANES);scheduleRender(PLANES);}
      lastGeometry=nextGeometry;
    }
    async function handleControlCommand(envelope){
      const detail=envelope&&envelope.detail||{};
      if(envelope.command==='payload.activate'){
        const id=text(detail.payloadId);if(id===state.activePageMetricId&&!state.dualOverlayEnabled)return;
        const before=copy(state);activateMetric(state,id,measures);commitNow('page');synchronizeTopbar();await refreshScientificPayload('metric',before);return;
      }
      if(envelope.command==='payload.toggle'){
        const dualToggle=root.querySelector('[data-imaging-dual-toggle]');
        if(state.activeViewMode==='three_dimensional'&&!isSurfaceRuntime(runtime)){if(dualToggle)dualToggle.checked=!!state.dualOverlayEnabled;return;}
        const before=copy(state);state.dualOverlayEnabled=!!detail.enabled;if(state.dualOverlayEnabled&&!state.overlayBId)state.overlayBId=state.enabledMetricIds.find(id=>id!==state.overlayAId)||'';if(!state.dualOverlayEnabled){state.overlayAId=state.activePageMetricId;state.overlayBId='';state.focusedOverlaySlot='A';}normalizeState(state,measures);commitNow('dual');synchronizeTopbar();await refreshScientificPayload('dual_overlay',before);return;
      }
      if(envelope.command==='representation.select'){
        const startedAt=performance.now(),definition=featureRepresentationDefinition(detail.representationId),targetView=definition.adapterId==='imaging.2d'?'orthogonal':'three_dimensional',targetRendering=definition.entryMode==='volume_raycast'?'volume_raycast':'surface_projection',previous=state.activeViewMode,previousRendering=state.render3D&&state.render3D.renderingMode||'surface_projection';if(targetView===state.activeViewMode&&(targetView!=='three_dimensional'||targetRendering===previousRendering))return;if(targetView==='three_dimensional'&&THREE_D_SESSION_DISABLED)return;setRepresentationPending(definition.id,true);resetImagingScrollPositions(root);try{if(targetView==='three_dimensional'&&state.activeViewMode==='three_dimensional'){await imaging3DController().setRenderingMode(root,targetRendering,'topbar_direct_entry');synchronizeTopbar();commitNow('view_mode');profile(opts,'view mode dispatch',startedAt,`representation=${definition.id} from=${previous}:${previousRendering} to=${targetView}:${targetRendering} remount=0 direct3d=1`);return;}await activateRetainedViewTab(root,targetView,targetRendering,opts,state,measures,commitNow);profile(opts,'view mode dispatch',startedAt,`representation=${definition.id} from=${previous}:${previousRendering} to=${targetView}:${targetView==='three_dimensional'?targetRendering:'none'} retainedTab=1 direct3d=${targetView==='three_dimensional'?1:0}`);}finally{setRepresentationPending(definition.id,false);}return;
      }
      if(envelope.command==='view.sync.toggle'){
        state.syncViews=!!detail.enabled;state.zoomLinkMode=state.syncViews?'synchronized':'independent';
        if(state.syncViews&&state.activeViewMode==='orthogonal'){const before=planeSliceSnapshot(runtime,state),v=planeVoxel(state,runtime,state.lastPlaneId);setPlaneVoxel(state,runtime,state.lastPlaneId,v);scheduleRender(changedSlicePlanes(runtime,state,before));}
        commitNow('sync_views');refreshReadouts();return;
      }
      if(envelope.command==='extrema.select'){const kind=text(detail.kind);if(state.activeViewMode==='three_dimensional')return imaging3DController().executeExtremaCommand(root,envelope);return goExtremum(kind);}
      if(['view.zoom','view.fit','view.reset'].includes(envelope.command)){
        if(state.activeViewMode==='three_dimensional'){
          const controller=imaging3DController();if(!controller||typeof controller.executeViewCommand!=='function')throw new Error('The specialized 3-D view-command executor is unavailable.');
          return controller.executeViewCommand(root,envelope);
        }
        const targets=state.syncViews?PLANES:[state.lastPlaneId];
        if(envelope.command==='view.reset'){
          clearExtremumSelection(state);PLANES.forEach(p=>{state.planes[p].zoom=1;state.planes[p].panX=0;state.planes[p].panY=0;});state.currentVoxel=arr(runtime.payload.initialVoxel).map(Number);PLANES.forEach(p=>state.planes[p].voxel=state.currentVoxel.slice());state.lastPlaneId='axial';scheduleRender(PLANES);
        }else if(envelope.command==='view.fit')targets.forEach(p=>{state.planes[p].zoom=1;state.planes[p].panX=0;state.planes[p].panY=0;});
        else{const direction=text(detail.direction);if(!['in','out'].includes(direction))throw new Error(`Unsupported 2-D zoom direction: ${direction||'(empty)'}.`);targets.forEach(p=>{const ps=state.planes[p];ps.zoom=clamp(direction==='in'?ps.zoom*1.2:ps.zoom/1.2,.25,8);});}
        commitNow(envelope.command==='view.reset'?'reset':'zoom');updatePlanePresentations(runtime,state,root,PLANES);scheduleRender(PLANES);refreshReadouts();return;
      }
      if(envelope.command==='geometry.variant.select'){
        if(!isSurfaceRuntime(runtime))throw new Error('Geometry-variant commands require a native-surface imaging context.');
        const variantId=text(detail.variantId),before=copy(state);state.selectedTemplateId=variantId;
        try{commitNow('surface_geometry');const result=await imaging3DController().updateSurfaceGeometry(root,state,'surface_geometry_switch');if(!result||result.retained!==true)await mount(opts,true);}catch(err){replaceState(state,before);normalizeState(state,measures);const template=root.querySelector('[data-rv-geometry-variant]');if(template)template.value=state.selectedTemplateId||'native';throw new Error(`Switching surface geometry failed: ${err&&err.message||String(err)}`);}return;
      }
      if(['camera.preset.select','camera.projection.select','clipping.mode.select','clipping.link.toggle','clipping.position.useSelection','clipping.position.update','clipping.side.select','surface.visibility.select','presentation3d.montage.open','presentation3d.video.open'].includes(envelope.command)){
        if(state.activeViewMode!=='three_dimensional')throw new Error(`Command ${envelope.command} requires the active 3-D imaging representation.`);
        const controller=imaging3DController();if(!controller||typeof controller.executeViewCommand!=='function')throw new Error('The specialized 3-D view-command executor is unavailable.');
        return controller.executeViewCommand(root,envelope);
      }
      if(String(envelope.command||'').indexOf('display.')===0){
        const result=displayControls().applyCommand(envelope,{getOverlay:()=>editingOverlay(runtime,state),getSupport:()=>editingSupport(runtime,state),getDisplay:(overlay,support)=>metricDisplayState(state,overlay,support),defaultOpacity:.85,identity:overlay=>({measureId:text(overlay&&overlay.meta&&overlay.meta.measureId),pathway:'imaging'})});
        scheduleRender(PLANES);
        if(result.capability==='displayRange'){commitNow(result.reason);refreshOverlayPresentation();return;}
        if(result.phase==='preview'){if(result.capability==='opacity')scheduleCommit(result.reason,140);return;}
        commitNow(result.reason);return;
      }
      if(envelope.command==='viewport.resize'){applyViewportResize(detail);return;}
      throw new Error(`Unsupported imaging control command: ${text(envelope.command)}.`);
    }
    function mountControlHost(){
      const api=window.NMResultsViewerControlHost;if(!api||typeof api.mount!=='function')throw new Error('The pathway-neutral Results Viewer control host is unavailable.');
      const viewCapabilities=['zoom','fit','reset','viewSync'];if(state.activeViewMode==='three_dimensional')viewCapabilities.push('camera','presentation3D');if(isSurfaceRuntime(runtime))viewCapabilities.push('geometryVariant','surfaceVisibility');else if(state.activeViewMode==='three_dimensional')viewCapabilities.push('clipping');
      const informationCapabilities=['informationFooter','extrema'];
      const host=api.mount({root,capabilities:['payloadSelection','representationSelection','viewportResize','threshold','colourbar','displayRange','opacity'].concat(viewCapabilities,informationCapabilities),onCommand:handleControlCommand,onError:error=>{profile(opts,'Results Viewer control failure',performance.now(),`message=${error&&error.message||String(error)}`);if(typeof opts.setMessage==='function')opts.setMessage('The requested viewer action could not be completed.','danger');else setTimeout(()=>{throw error;},0);}});
      try{
        const pageStrip=root.querySelector('.rvImagingPages');if(!pageStrip)throw new Error('The imaging payload-page control region is missing.');
        host.registerRegion({id:'imaging-payload-pages',capability:'payloadSelection',element:pageStrip,eventType:'click',selector:'[data-imaging-page]',command:'payload.activate',detail:target=>({payloadId:text(target.getAttribute('data-imaging-page'))})});
        host.registerRegion({id:'imaging-dual-overlay',capability:'payloadSelection',element:root,eventType:'change',selector:'[data-imaging-dual-toggle]',command:'payload.toggle',detail:target=>({enabled:!!target.checked})});
        host.registerRegion({id:'imaging-representation',capability:'representationSelection',element:root,eventType:'click',selector:'[data-imaging-view-mode]',command:'representation.select',detail:target=>({representationId:text(target.getAttribute('data-imaging-view-mode'))})});
        const viewportTarget=state.activeViewMode==='three_dimensional'?(root.querySelector('[data-imaging-3d-viewport]')||root):root;
        host.registerViewport({id:'imaging-viewport',capability:'viewportResize',element:root,observeElement:viewportTarget,includeWindow:true,immediate:true});
        host.registerController({id:'imaging-view-controls',capabilities:viewCapabilities,mount:controller=>viewControls().bind(root,{dispatch:controller.dispatch,capabilities:controller.capabilities})});
        host.registerController({id:'imaging-information-controls',capabilities:informationCapabilities,mount:controller=>informationControls().bind(root,{dispatch:controller.dispatch,capabilities:controller.capabilities})});
      }catch(error){host.dispose();throw error;}
      return host;
    }
    function mountDisplayControlBinding(){
      const api=displayControls();
      displayControlBinding=controlHost.registerController({id:'imaging-display-controls',capabilities:['threshold','colourbar','displayRange','opacity'],mount:controller=>api.bind(root,{dispatch:controller.dispatch,capabilities:controller.capabilities,getOverlay:()=>editingOverlay(runtime,state),getSupport:()=>editingSupport(runtime,state),getDisplay:(overlay,support)=>metricDisplayState(state,overlay,support),onWarning:message=>{if(typeof opts.setMessage==='function')opts.setMessage(message,'warning');}})});
      return displayControlBinding;
    }
    async function handleGpuRecoveryAction(action){
      const controller=imaging3DController();
      if(action==='disable'){THREE_D_SESSION_DISABLED=true;controller.dispose(root,{destroyRenderer:true,reason:'user_disable_3d'});await activateRetainedViewTab(root,'orthogonal','surface_projection',opts,state,measures,commitNow);const live=document.getElementById(root.id);if(live)synchronizeMetricShell(live,state,measures);return;}
      if(action==='retry'){THREE_D_SESSION_DISABLED=false;controller.dispose(root,{destroyRenderer:true,reason:'user_gpu_retry'});await mount(Object.assign({},opts,{root}),false);return;}
      if(action==='restart'){await requestHardGpuHostRestart();return;}
      throw new Error(`Unsupported GPU recovery action: ${text(action)}.`);
    }
    function mountThreeDimensionalLifecycle(){
      if(state.activeViewMode!=='three_dimensional')return null;
      const controller=imaging3DController();
      return controlHost.registerController({id:'imaging-3d-lifecycle',capabilities:['viewportResize'],mount:()=>controller.mountLifecycle({root,runtime,state,opts,notify:(s,reason,identity)=>{synchronizeMetricShell(root,s,measures);notify(opts,s,reason,identity);},currentInteractionIdentity,computeROIRows,roiRowsPreparationInput,refreshOverlayPresentation:()=>refreshOverlayPresentation(false),remount:()=>mount(opts),onGpuRecoveryAction:handleGpuRecoveryAction})});
    }


    const body=root.querySelector('[data-imaging-body]'),bodyStarted=performance.now();
    root.classList.add('rvImagingPreparing');root.dataset.imagingStatus='preparing';
    if(body){body.innerHTML=controlBodyHtml(runtime,state,measures,opts.escape);body.hidden=false;resetImagingScrollPositions(root);requestAnimationFrame(()=>resetImagingScrollPositions(root));}
    synchronizeAtlasDependentControls(root,runtime,state);
    bindImagingControlTooltips(root,state);
    const tipsToggle=root.querySelector('[data-imaging-tooltips-enabled]');if(tipsToggle)tipsToggle.addEventListener('change',()=>{state.tooltipsEnabled=!!tipsToggle.checked;if(!state.tooltipsEnabled)hideImagingControlTooltip();commitNow('tooltips_enabled');});
    const loading=root.querySelector('[data-imaging-loading]');if(loading){loading.hidden=true;loading.style.display='none';}
    applyViewportHeight(root);root.getBoundingClientRect();profile(opts,'control body HTML/DOM materialization',bodyStarted,`metrics=${state.enabledMetricIds.length}`);
    controlHost=mountControlHost();mountDisplayControlBinding();const presentationLifecycle=mountThreeDimensionalLifecycle();
    const templateRegion=root.querySelector('.rvImagingTemplateControl');if(templateRegion&&!isSurfaceRuntime(runtime))anatomyControls().bind(templateRegion,{capabilities:['template'],onChange:change=>{state.selectedTemplateId=String(change.value||'');state.selectedAtlasId='';commitNow('template');mount(opts,true);}});
    const grid=root.querySelector('[data-imaging-grid-policy]');if(grid)grid.addEventListener('change',()=>{state.displayGridPolicy=grid.value;commitNow('grid');mount(opts,true);});
    const anatomyInterpolation=root.querySelector('[data-imaging-anatomy-interpolation]');if(anatomyInterpolation)anatomyInterpolation.addEventListener('change',()=>{state.anatomyInterpolation=normalizedDisplayInterpolation(anatomyInterpolation.value);state.displayInterpolation=state.anatomyInterpolation;commitNow('anatomy_interpolation');updatePlanePresentations(runtime,state,root,PLANES);scheduleRender(PLANES);});
    const featureInterpolation=root.querySelector('[data-imaging-feature-interpolation]');if(featureInterpolation)featureInterpolation.addEventListener('change',()=>{state.featureInterpolation=featureInterpolation.value==='support_aware_linear'?'support_aware_linear':'voxel_faithful';commitNow('feature_interpolation');scheduleRender(PLANES);});
    const rendererMode=root.querySelector('[data-imaging-2d-renderer]');if(rendererMode)rendererMode.addEventListener('change',()=>{state.interactive2DRendererMode=['auto','gpu','cpu'].includes(rendererMode.value)?rendererMode.value:'auto';commitNow('interactive_2d_renderer');mount(opts);});
    async function applyRetainedAtlasRuntime(nextRuntime,reason){
      const startedAt=performance.now(),controller=imaging3DController();if(!nextRuntime)throw new Error('Atlas update did not return a runtime.');
      if(!isSurfaceRuntime(nextRuntime)&&!workspaceStructuralReuseCompatible(runtime,nextRuntime.payload,nextRuntime.dims))throw new Error('Atlas update unexpectedly changed the mounted structural workspace.');
      if(state.activeViewMode==='three_dimensional'){const result=await controller.updateRuntime({root,runtime:nextRuntime,state,reason:reason||'atlas',escape:opts.escape});if(!result||!result.retained)throw new Error(`Atlas update could not retain the mounted 3-D context (${text(result&&result.reason||'unknown')}).`);}
      runtime=nextRuntime;state.contentId=text(runtime.payload&&runtime.payload.contentId||state.contentId);normalizeState(state,measures);normalizeWorkspaceCapabilities(state,runtime);if(gpuSession&&typeof gpuSession.setAtlas==='function')gpuSession.setAtlas(runtime.atlas||null);const record=ROOT_RUNTIME.get(root);if(record){record.runtime=runtime;record.scientificSignature=scientificTabSignature(state);}synchronizeTopbar();synchronizeAtlasDependentControls(root,runtime,state);if(displayControlBinding&&typeof displayControlBinding.refresh==='function')displayControlBinding.refresh();refreshReadouts();if(state.activeViewMode!=='three_dimensional')scheduleRender(PLANES);root.dataset.imagingStatus='ready';profile(opts,'retained atlas update TOTAL',startedAt,`surface=${isSurfaceRuntime(runtime)?1:0} atlas=${text(state.selectedAtlasId||'none')}`);return runtime;
    }
    async function refreshVoxelAtlasRetained(before){
      if(before.selectedAtlasId!==state.selectedAtlasId){state.volumeAtlasDescriptorFile='';state.volumeAtlasDelimiter='auto';state.volumeAtlasNameColumn='';}
      if(state.selectedAtlasId){const selected=arr(runtime.payload.atlasCatalogue).find(a=>a.atlasId===state.selectedAtlasId);state.volumeAtlasPath=selected&&selected.provenance==='viewer_local_atlas'?text(selected.file):'';}
      const startedAt=performance.now();root.dataset.imagingStatus='updating';try{
        let nextRuntime;
        if((!state.selectedAtlasId||state.selectedAtlasId==='none')&&!state.volumeAtlasPath){
          nextRuntime=Object.assign({},runtime,{atlas:null,payload:Object.assign({},runtime.payload,{selectedAtlas:{available:false,atlasId:'none'}})});
        }else{
          const ids=requestedMetricIds(state),reference=runtime&&runtime.payload&&runtime.payload.spatialReference;
          if(!reference||!text(reference.gridId))throw new Error('The mounted display spatial reference required for atlas loading is unavailable.');
          const spec=opts.selectedSpec({measureId:ids[0]||text(state.activePageMetricId),measureIds:ids,displayGridPolicy:state.displayGridPolicy,selectedTemplateId:state.selectedTemplateId,selectedAtlasId:state.selectedAtlasId,volumeAtlasPath:state.volumeAtlasPath,volumeAtlasDelimiter:state.volumeAtlasDelimiter,volumeAtlasNameColumn:state.volumeAtlasNameColumn,volumeAtlasDescriptorFile:state.volumeAtlasDescriptorFile,atlasTargetReference:reference,atlasTargetGridId:text(reference.gridId)}),serviceStarted=performance.now(),response=await opts.matlabService({operation:'results_viewer_alpha_imaging_atlas',spec}),payload=response&&response.payload;
          profile(opts,'MATLAB atlas-only roundtrip',serviceStarted,`ok=${response&&response.ok!==false?1:0}`);
          if(!response||response.ok===false||!payload||payload.ok===false)throw new Error(payload&&payload.message||response&&response.message||'The selected atlas is unavailable.');
          if(text(payload.targetGridId)!==text(reference.gridId))throw new Error('The returned atlas resource targets a different display grid.');
          const selected=payload.selectedAtlas;if(!selected||selected.available!==true||!selected.url)throw new Error('The atlas service returned no selected atlas asset.');
          const n=runtime.dims[0]*runtime.dims[1]*runtime.dims[2],data=await opts.fetchArray(selected.url,'uint32',n);if(data.length!==n)throw new Error('The selected atlas asset has an invalid element count.');
          state.selectedAtlasId=text(selected.atlasId);
          nextRuntime=Object.assign({},runtime,{atlas:{meta:selected,data},payload:Object.assign({},runtime.payload,{selectedAtlas:selected,atlasCatalogue:payload.atlasCatalogue})});
        }
        await applyRetainedAtlasRuntime(nextRuntime,'atlas');return true;
      }catch(err){replaceState(state,before);normalizeState(state,measures);root.dataset.imagingStatus='ready';if(typeof opts.setMessage==='function')opts.setMessage('The atlas could not be updated. The previous atlas remains active.','danger');profile(opts,'retained atlas update failure',startedAt,`message=${err&&err.message||String(err)}`);return false;}
    }
    const atlasPicker=root.querySelector('[data-imaging-atlas]');
    if(atlasPicker)atlasPicker.addEventListener('change',event=>{
      if(atlasPicker.value!=='choose_volume_atlas')return;
      event.stopImmediatePropagation();atlasPicker.value=state.selectedAtlasId;const before=copy(state);
      pickSurfaceAtlasPath(state.volumeAtlasPath,false).then(async path=>{
        if(!path)return;
        state.volumeAtlasPath=path;state.selectedAtlasId='';
        state.volumeAtlasDelimiter='auto';state.volumeAtlasNameColumn='';state.volumeAtlasDescriptorFile='';
        if(await refreshVoxelAtlasRetained(before))commitNow('atlas');
      }).catch(err=>{replaceState(state,before);if(typeof opts.setMessage==='function')opts.setMessage(`Loading atlas failed: ${err.message}`,'danger');});
    });
    const atlas=root.querySelector('[data-imaging-atlas]');if(atlas)atlas.addEventListener('change',async()=>{const before=copy(state),requested=atlas.value,api=surfaceAdapter(),activeSurfaceAtlas=api.activeAtlasId(runtime);try{if(isSurfaceRuntime(runtime)){if(requested==='none'){api.clearAtlas(runtime);state.selectedAtlasId='';state.surfaceAtlasPaths={selectedPath:'',lhPath:'',rhPath:''};commitNow('atlas');await applyRetainedAtlasRuntime(runtime,'atlas');return;}if(requested===activeSurfaceAtlas){atlas.value=activeSurfaceAtlas||'none';return;}if(requested==='surface_annot_file'){atlas.value=activeSurfaceAtlas||'none';const selectedPath=await pickSurfaceAtlasPath(state.surfaceAtlasPaths&&state.surfaceAtlasPaths.selectedPath);if(!selectedPath)return;const candidate=copy(state);candidate.selectedAtlasId='';candidate.surfaceAtlasPaths={selectedPath,lhPath:'',rhPath:''};await loadSurfaceAtlas(runtime,candidate,opts,selectedPath);replaceState(state,candidate);normalizeState(state,measures);commitNow('atlas');await applyRetainedAtlasRuntime(runtime,'atlas');return;}throw new Error('Unsupported native-surface atlas selection.');}state.selectedAtlasId=requested;commitNow('atlas');await refreshVoxelAtlasRetained(before);}catch(err){replaceState(state,before);normalizeState(state,measures);atlas.value=activeSurfaceAtlas||'none';root.dataset.imagingStatus='ready';if(typeof opts.setMessage==='function')opts.setMessage(`Loading atlas failed: ${err.message||String(err)}`,'danger');}});
    root.addEventListener('change',async event=>{
      const name=event.target&&event.target.getAttribute('data-imaging-atlas-name-column'),delim=event.target&&event.target.getAttribute('data-imaging-atlas-delimiter'),descriptor=event.target&&event.target.getAttribute('data-imaging-atlas-descriptor-file');
      if(name===null&&delim===null&&descriptor===null)return;
      const before=copy(state);
      if(descriptor!==null){state.volumeAtlasDescriptorFile=event.target.value;state.volumeAtlasDelimiter='auto';state.volumeAtlasNameColumn='';}
      else if(delim!==null){state.volumeAtlasDelimiter=event.target.value;state.volumeAtlasNameColumn='';}
      else state.volumeAtlasNameColumn=event.target.value;
      if(await refreshVoxelAtlasRetained(before))commitNow('atlas_descriptor');
    });
    const boundaries=root.querySelector('[data-imaging-boundaries]');if(boundaries)boundaries.addEventListener('change',()=>{state.atlasBoundariesVisible=!!boundaries.checked;commitNow('boundaries');scheduleRender(PLANES);});
    const cross=root.querySelector('[data-imaging-crosshair]');if(cross)cross.addEventListener('change',()=>{state.crosshairVisible=!!cross.checked;commitNow('crosshair');updatePlaneCrosshairs(root,runtime,state,PLANES);});
    const bc=root.querySelector('[data-imaging-boundary-color]');if(bc)bc.addEventListener('change',()=>{state.atlasBoundaryColor=bc.value;commitNow('boundary_color');scheduleRender(PLANES);});
    const bo=root.querySelector('[data-imaging-boundary-opacity]');if(bo){const apply=()=>{state.atlasBoundaryOpacity=clamp(finite(bo.value,.82),0,1);const o=root.querySelector('[data-imaging-boundary-opacity-output]');if(o)o.textContent=fmt(state.atlasBoundaryOpacity,2);scheduleRender(PLANES);};bo.addEventListener('input',()=>{apply();scheduleCommit('boundary_opacity',140);});bo.addEventListener('change',()=>{apply();commitNow('boundary_opacity');});}
    const roi=root.querySelector('[data-imaging-roi-table]');if(roi)roi.addEventListener('click',()=>{if(roi.disabled||roi.getAttribute('aria-disabled')==='true')return;showROITable(runtime,state,opts);});
    Array.from(root.querySelectorAll('[data-imaging-roi-mapper]')).forEach(button=>button.addEventListener('click',()=>{if(button.disabled||button.getAttribute('aria-disabled')==='true')return;try{openROIMapper(runtime,state,measures,opts);}catch(error){if(typeof opts.setMessage==='function')opts.setMessage(`ROI Mapper failed: ${error&&error.message||String(error)}`,'danger');}}));
    Array.from(root.querySelectorAll('[data-imaging-multislice]')).forEach(ms=>ms.addEventListener('click',()=>showMultiSlice(root,runtime,state,opts)));
    const stateApi=imagingStateApi(),stateMenu=root.querySelector('[data-imaging-state-menu]'),closeStateMenu=()=>{if(stateMenu)stateMenu.open=false;},stateSave=root.querySelector('[data-imaging-state-save]'),stateLoad=root.querySelector('[data-imaging-state-load]'),stateReset=root.querySelector('[data-imaging-state-reset]'),stateFile=root.querySelector('[data-imaging-state-file]');
    if(stateSave)stateSave.addEventListener('click',()=>{try{if(!stateApi)throw new Error('Imaging-viewer state module is unavailable.');const name=stateApi.filename(runtime,state),serialized=stateApi.canonicalStringify(stateApi.build(runtime,state));downloadBlob(new Blob([serialized],{type:'application/json;charset=utf-8'}),name);state.stateFileName=name;state.stateCompatibilityStatus='Exact match';state.stateCompatibilitySummary={outcome:'Exact match',sourceFile:name,applied:['current viewer state'],remapped:[],skipped:[],incompatible:[],gridCompatible:true};commitNow('viewer_state_saved');closeStateMenu();if(typeof opts.setMessage==='function')opts.setMessage(`Imaging viewer state saved as ${name}.`,'info');}catch(err){if(typeof opts.setMessage==='function')opts.setMessage(`Saving imaging viewer state failed: ${err.message||String(err)}`,'danger');}});
    if(stateLoad&&stateFile)stateLoad.addEventListener('click',()=>{stateFile.value='';closeStateMenu();stateFile.click();});
    if(stateFile)stateFile.addEventListener('change',async()=>{const file=stateFile.files&&stateFile.files[0];if(!file)return;const before=copy(state);try{if(!stateApi)throw new Error('Imaging-viewer state module is unavailable.');const serialized=typeof file.text==='function'?await file.text():await new Promise((resolve,reject)=>{const reader=new FileReader();reader.onload=()=>resolve(reader.result);reader.onerror=()=>reject(reader.error||new Error('State file could not be read.'));reader.readAsText(file);}),parsed=stateApi.parse(serialized,file.name),result=await applyStateFile(root,parsed,opts,true);notify(opts,state,'viewer_state_loaded');showStateCompatibilitySummary(result.compatibility);if(typeof opts.setMessage==='function')opts.setMessage(`Imaging viewer state loaded: ${result.compatibility.outcome}.`,'info');}catch(err){replaceState(state,before);normalizeState(state,measures);try{await mount(opts,true);}catch(_restoreError){}if(typeof opts.setMessage==='function')opts.setMessage(`Loading imaging viewer state failed: ${err.message||String(err)}`,'danger');}});
    if(stateReset)stateReset.addEventListener('click',()=>{replaceState(state,resetViewerState(runtime,state,measures));notify(opts,state,'viewer_state_reset');closeStateMenu();mount(opts);});
    const goExtremum=kind=>{const startedAt=performance.now();try{const before=planeSliceSnapshot(runtime,state),descriptor=extremumFor(runtime,state,kind),statusText=`${descriptor.kind.replace(/_/g,' ')} ${fmt(descriptor.value,4)} at voxel ${descriptor.voxel.join(', ')}.`;applyExtremumSelection(runtime,state,descriptor);refreshReadouts();informationControls().update(root,{extremaStatus:statusText});updatePlaneCrosshairs(root,runtime,state,PLANES);scheduleRender(changedSlicePlanes(runtime,state,before));highlightExtremum(root);const identity=currentInteractionIdentity(runtime,state,{planeId:state.lastPlaneId});commitNow('extremum_navigation',identity);profile(opts,'2-D extremum selection',startedAt,`kind=${descriptor.kind} value=${fmt(descriptor.value,8)} voxel=${descriptor.voxel.join(',')} world=${arr(descriptor.worldMm).slice(0,3).map(v=>fmt(v,3)).join(',')} marker=${state.extremumMarker?1:0}`);if(typeof opts.setMessage==='function')opts.setMessage(`${descriptor.kind.replace('_',' ')}: ${fmt(descriptor.value,4)} at voxel ${descriptor.voxel.join(', ')}${descriptor.atlasLabel?' · '+descriptor.atlasLabel:''}`,'info');return descriptor;}catch(err){informationControls().update(root,{extremaStatus:`Extrema navigation failed: ${err.message||String(err)}`});profile(opts,'2-D extremum selection',startedAt,`failed=1 kind=${kind} message=${err&&err.message||String(err)}`);if(typeof opts.setMessage==='function')opts.setMessage(`Extrema navigation failed: ${err.message||String(err)}`,'danger');return null;}};
    const contextMenu=root.querySelector('[data-imaging-context-menu]');if(contextMenu){contextMenu.addEventListener('click',event=>{const btn=event.target.closest('[data-imaging-context-action]');if(!btn)return;const action=btn.getAttribute('data-imaging-context-action');hideContextMenu(root);if(['minimum','maximum','strongest_absolute'].includes(action)){goExtremum(action);return;}const voxel=planeVoxel(state,runtime,state.lastPlaneId),world=voxelToWorld(runtime.payload.spatialReference,voxel),value=focusedValue(runtime,state);if(action==='copy_voxel')clipboardText(voxel.join(', '));else if(action==='copy_world')clipboardText(world.map(v=>fmt(v,6)).join(', '));else if(action==='copy_value')clipboardText(numericInputAttribute(value));else if(action==='set_threshold'){if(setThresholdFromFocusedValue(runtime,state)){commitNow('threshold_from_focused_value');refreshOverlayPresentation();}else if(typeof opts.setMessage==='function')opts.setMessage('The focused voxel does not provide a finite non-zero value for the active threshold mode.','warning');}});contextMenuDocumentListener=event=>{if(root.isConnected&&!contextMenu.contains(event.target))hideContextMenu(root);};document.addEventListener('pointerdown',contextMenuDocumentListener);}
    const bindSilhouetteColour=(selector,field,reason,cssVariable)=>{const input=root.querySelector(selector);if(!input)return;const apply=()=>{if(!/^#[0-9a-f]{6}$/i.test(input.value))return false;state[field]=input.value;const bar=input.closest('.rvImagingSilhouetteColorbar');if(bar&&cssVariable)bar.style.setProperty(cssVariable,input.value);scheduleRender(PLANES);return true;};input.addEventListener('input',apply);input.addEventListener('change',()=>{if(!apply())return;commitNow(reason);});};
    bindSilhouetteColour('[data-imaging-silhouette-negative]','dualOverlaySilhouetteNegativeColor','dual_overlay_silhouette_negative','--rv-silhouette-negative');
    bindSilhouetteColour('[data-imaging-silhouette-positive]','dualOverlaySilhouettePositiveColor','dual_overlay_silhouette_positive','--rv-silhouette-positive');
    const anatomyRegion=root.querySelector('.rvImaging2DAnatomyControls');if(anatomyRegion)anatomyControls().bind(anatomyRegion,{capabilities:['brightness','gamma'],onChange:change=>{if(change.field==='brightness')state.backgroundBrightness=clamp(Number(change.value),0,2);else if(change.field==='gamma'){state.anatomyGamma=clamp(Number(change.value),.25,4);if(state.render3D&&state.render3D.anatomy)state.render3D.anatomy.gamma=state.anatomyGamma;}else throw new Error(`Unsupported 2-D anatomy field: ${change.field}.`);scheduleRender(PLANES);if(change.phase==='commit')commitNow(change.field==='gamma'?'anatomy_gamma':'brightness');else scheduleCommit(change.field==='gamma'?'anatomy_gamma':'brightness',140);}});
    Array.from(root.querySelectorAll('[data-imaging-slice]')).forEach(inp=>{
      const apply=()=>{const plane=inp.getAttribute('data-imaging-slice');if(!PLANES.includes(plane))return;clearExtremumSelection(state);state.lastPlaneId=plane;setPlaneSlice(state,runtime,plane,finite(inp.value,currentSlice(state,runtime,plane)));refreshReadouts();scheduleRender([plane]);};
      inp.addEventListener('input',()=>{apply();scheduleCommit('coordinate',140,()=>currentInteractionIdentity(runtime,state,{planeId:plane}));});inp.addEventListener('change',()=>{apply();commitNow('coordinate',currentInteractionIdentity(runtime,state,{planeId:plane}));});
    });
    PLANES.forEach(plane=>{
      const frame=root.querySelector(`[data-imaging-frame="${plane}"]`),canvas=root.querySelector(`[data-imaging-canvas="${plane}"]`);if(!frame||!canvas)return;
      frame.addEventListener('mouseenter',()=>{state.lastPlaneId=plane;});
      frame.addEventListener('contextmenu',event=>{state.lastPlaneId=plane;showContextMenu(root,event);});
      frame.addEventListener('wheel',evt=>{evt.preventDefault();state.lastPlaneId=plane;if(evt.ctrlKey||evt.metaKey||evt.altKey){const targets=state.syncViews?PLANES:[plane],factor=evt.deltaY>0?1/1.12:1.12;targets.forEach(p=>state.planes[p].zoom=clamp(state.planes[p].zoom*factor,.25,8));updatePlanePresentations(runtime,state,root,targets);scheduleRender(targets);scheduleCommit('zoom',140);}else{clearExtremumSelection(state);setPlaneSlice(state,runtime,plane,currentSlice(state,runtime,plane)+(evt.deltaY>0?1:-1));refreshReadouts();scheduleRender([plane]);scheduleCommit('coordinate',140,()=>currentInteractionIdentity(runtime,state,{planeId:plane}));}},{passive:false});
      frame.addEventListener('click',evt=>{if(frame.dataset.dragged==='1'){frame.dataset.dragged='0';return;}const v=eventVoxel1(runtime,state,plane,evt,canvas);if(!v)return;const before=planeSliceSnapshot(runtime,state);clearExtremumSelection(state);setPlaneVoxel(state,runtime,plane,v);state.lastPlaneId=plane;refreshReadouts();scheduleRender(changedSlicePlanes(runtime,state,before));commitNow('coordinate',currentInteractionIdentity(runtime,state,{planeId:plane}));});
      let drag=null;
      frame.addEventListener('pointerdown',evt=>{if(!(evt.shiftKey||evt.button===1))return;evt.preventDefault();drag={x:evt.clientX,y:evt.clientY,px:state.planes[plane].panX,py:state.planes[plane].panY};frame.setPointerCapture(evt.pointerId);});
      frame.addEventListener('pointermove',evt=>{if(!drag)return;const dx=evt.clientX-drag.x,dy=evt.clientY-drag.y,targets=state.syncViews?PLANES:[plane];targets.forEach(p=>{state.planes[p].panX=drag.px+dx;state.planes[p].panY=drag.py+dy;});frame.dataset.dragged='1';updatePlanePresentations(runtime,state,root,targets);scheduleRender(targets);});
      canvas.addEventListener('pointermove',evt=>{if(drag)return;const v=eventVoxel1(runtime,state,plane,evt,canvas);if(v)updateAtlasReadout(root,runtime,state,v,true);});
      const clearHover=()=>{if(!drag)updateAtlasReadout(root,runtime,state,planeVoxel(state,runtime,state.lastPlaneId),false);};canvas.addEventListener('pointerleave',clearHover);frame.addEventListener('pointerleave',clearHover);
      frame.addEventListener('pointerup',evt=>{if(!drag)return;drag=null;if(frame.hasPointerCapture(evt.pointerId))frame.releasePointerCapture(evt.pointerId);commitNow('pan');updateAtlasReadout(root,runtime,state,planeVoxel(state,runtime,state.lastPlaneId),false);});
    });
    applyControlWidthClass(root);
    if(state.activeViewMode==='orthogonal'&&state.interactive2DRendererMode!=='cpu'&&window.NMImaging2DWebGLRenderer){
      gpuSession=window.NMImaging2DWebGLRenderer.create({root,runtime,onStatus:info=>{
        if(!root.isConnected)return;
        if(info.state==='ready'){
          updatePlanePresentations(runtime,state,root,PLANES);
          const rendered=gpuSession&&gpuSession.render(PLANES,gpuRenderModel(runtime,state,root));
          if(rendered)setGpuCanvasActive(root,true,'High-resolution display','ready');
          else{setGpuCanvasActive(root,false,'Standard display','fallback');requestAnimationFrame(()=>{if(root.isConnected)redraw(runtime,state,root,opts,false,PLANES);});}
        }else if(info.state==='lost'){
          setGpuCanvasActive(root,false,'GPU interrupted · Standard display','lost');requestAnimationFrame(()=>{if(root.isConnected)redraw(runtime,state,root,opts,false,PLANES);});if(typeof opts.setMessage==='function')opts.setMessage('The graphics context was lost. Standard 2-D viewing remains available while NM2 waits for GPU recovery.','warning');
        }else if(info.state==='restoring'){
          setGpuCanvasActive(root,false,'Restoring high-resolution display…','restoring');requestAnimationFrame(()=>{if(root.isConnected)redraw(runtime,state,root,opts,false,PLANES);});
        }else if(info.state==='fallback'){
          const unavailable=info.reason==='webgl2_unavailable'||info.reason==='context_unavailable'||info.reason==='context_lost';setGpuCanvasActive(root,false,unavailable?'GPU unavailable · Standard display':'Standard display','fallback');requestAnimationFrame(()=>{if(root.isConnected)redraw(runtime,state,root,opts,false,PLANES);});
        }
      }});
      const startGpu=()=>{gpuInitHandle=0;if(!root.isConnected||!gpuSession)return;const result=gpuSession.initialize();if(!result.ok&&state.interactive2DRendererMode==='gpu'&&typeof opts.setMessage==='function')opts.setMessage('High-resolution display is unavailable; the standard display remains active.','warning');};
      if(typeof requestIdleCallback==='function')gpuInitHandle=requestIdleCallback(startGpu,{timeout:500});else gpuInitHandle=setTimeout(startGpu,0);
      setGpuCanvasActive(root,false,'Preparing high-resolution display…','pending');
    }else setGpuCanvasActive(root,false,'Standard display','cpu');
    lastGeometry=viewportGeometrySignature(root);
    ROOT_RUNTIME.set(root,{runtime,state,scientificSignature:scientificTabSignature(state),controlHost,gpuSession,presentationReady:presentationLifecycle&&presentationLifecycle.pending||Promise.resolve(),refreshScientificPayload,rebindScientificContext,restoreScientificContext,synchronizeTopbar,renderRaf:()=>renderRaf,commitTimer:()=>commitTimer,cancel:()=>{scientificRefreshSequence++;hideImagingControlTooltip();if(contextMenuDocumentListener){document.removeEventListener('pointerdown',contextMenuDocumentListener);contextMenuDocumentListener=null;}if(renderRaf)cancelAnimationFrame(renderRaf);if(commitTimer)clearTimeout(commitTimer);if(gpuInitHandle){if(typeof cancelIdleCallback==='function')try{cancelIdleCallback(gpuInitHandle);}catch(err){}clearTimeout(gpuInitHandle);}if(gpuSession)try{gpuSession.dispose();}catch(err){}}});
    profile(opts,'runtime control/event binding TOTAL',bindStarted,`planes=${PLANES.length}`);
  }

  async function updateScientificSelection(rootOrId,reason,payload,bindings){
    const root=typeof rootOrId==='string'?document.getElementById(rootOrId):rootOrId,record=root&&ROOT_RUNTIME.get(root);
    if(!root||!record||typeof record.refreshScientificPayload!=='function')return {retained:false,reason:'mounted_runtime_unavailable'};
    const previousState=payload?copy(record.state):null,previousContext=payload&&typeof record.rebindScientificContext==='function'?record.rebindScientificContext(payload,bindings):null;
    if(typeof record.synchronizeTopbar==='function')record.synchronizeTopbar();
    const result=await record.refreshScientificPayload(reason||'metric',previousState);
    if(result&&result.reason==='update_failed'&&previousContext&&typeof record.restoreScientificContext==='function'){record.restoreScientificContext(previousContext,previousState);record.synchronizeTopbar();}
    return Object.assign({},result||{},{state:record.state});
  }

  function applyViewportHeight(root){
    if(!root||!root.isConnected)return;
    // Mixed-native children scroll within their parent metric panel; viewport fitting belongs to standalone viewers.
    if(root.closest('.rvFeatureMixedNativeCard')){
      root.style.removeProperty('--rv-viewer-available-height');
      root.classList.remove('rvViewerCompactHeight','rvViewerBelowMinimumHeight');
      return;
    }
    const panel=root.closest('.rvWorkspaceItem,.rvPanel,.rvDashboardPanel,[data-panel-kind]');
    let available=0;
    if(panel){
      panel.classList.add('rvViewerWorkspacePanel');
      const workspace=panel.closest('.rvVisualWorkspace'),manualCanvas=!!(workspace&&!workspace.classList.contains('isDashboardLayout')&&!workspace.classList.contains('isAutoLayout'));
      if(manualCanvas || (workspace&&workspace.classList.contains('isDashboardLayout'))){
        // Manual panels and dashboard panels retain their own height authority.
        // A dashboard viewer below the viewport remains accessible by scrolling.
        panel.style.removeProperty('max-height');
      }else{
        const panelTop=Math.max(0,panel.getBoundingClientRect().top),panelHeight=Math.max(0,Math.floor(window.innerHeight-panelTop-2));
        panel.style.height=panelHeight+'px';panel.style.maxHeight=panel.style.height;
      }
      const body=panel.querySelector('.rvWorkspaceItemBody,.rvPanelBody,.rvWorkspacePanelBody')||root.parentElement;
      if(body){
        body.style.overflow='hidden';body.style.minHeight='0';
        const bodyRect=body.getBoundingClientRect(),rootTop=root.getBoundingClientRect().top,style=window.getComputedStyle?window.getComputedStyle(body):null;
        const bottomInset=style?(parseFloat(style.paddingBottom||'0')||0)+(parseFloat(style.borderBottomWidth||'0')||0):0;
        available=Math.max(0,Math.floor(bodyRect.bottom-bottomInset-rootTop));
      }
    }
    if(!available){const top=Math.max(0,root.getBoundingClientRect().top);available=Math.max(0,Math.floor(window.innerHeight-top-2));}
    root.style.setProperty('--rv-viewer-available-height',available+'px');
    root.classList.toggle('rvViewerCompactHeight',available<430);
    root.classList.toggle('rvViewerBelowMinimumHeight',available<250);
  }

  async function mount(opts,forceReload){
    const mountStarted=performance.now();
    opts=opts||{};const root=opts.root||(opts.rootId&&document.getElementById(opts.rootId))||document.getElementById('rvImagingViewerRoot');if(!root)return;
    const rootId=text(root.id||opts.rootId||'rvImagingViewerRoot'),rootStyle=root.getAttribute('style')||'',mountSequence=(MOUNT_SEQUENCES.get(rootId)||0)+1;MOUNT_SEQUENCES.set(rootId,mountSequence);root.id=rootId;
    const stableOpts=Object.assign({},opts);delete stableOpts.root;
    const measures=availableMeasures(opts.payload);const state=normalizeState(opts.state||defaultState(measures),measures);
    if(forceReload||!opts.preservePeerTabs)invalidatePeerTabs(root,state);
    disposeRootRuntime(root);
    if(forceReload){RUNTIME_CACHE.clear();profile(opts,'runtime cache clear',mountStarted,'forceReload=1');}
    const shellStarted=performance.now();
    const featureIdentity=Array.from(root.attributes).filter(attr=>attr.name.startsWith('data-feature-'));
    root.outerHTML=shellHtml(measures,state,opts.escape,rootId);
    const live=document.getElementById(rootId);if(!live)return;
    featureIdentity.forEach(attr=>live.setAttribute(attr.name,attr.value));
    if(rootStyle)live.setAttribute('style',rootStyle);registerTabRoot(live,state);
    applyViewportHeight(live);
    profile(opts,'viewer shell replacement/layout',shellStarted,`metrics=${measures.length} enabled=${state.enabledMetricIds.length}`);
    try{
      const loadStarted=performance.now();
      const runtime=await loadWorkspace(stableOpts,live,measures,state);
      profile(opts,'workspace await in mount',loadStarted,`contentId=${text(runtime&&runtime.payload&&runtime.payload.contentId)}`);
      if(MOUNT_SEQUENCES.get(rootId)!==mountSequence||!live.isConnected){profile(opts,'mount abandoned after workspace',mountStarted,'stale=1');return;}
      normalizeWorkspaceCapabilities(state,runtime);
      if((state.activeViewMode==='orthogonal'||state.activeViewMode==='three_dimensional')&&!isSurfaceRuntime(runtime)){
        const viewLabel=state.activeViewMode==='three_dimensional'?'3-D':'2-D';
        if(!runtime.nativeFeatureSampling||typeof runtime.nativeFeatureSampling.load!=='function')throw new Error(`The authoritative native-grid feature source required by the ${viewLabel} viewer is unavailable.`);
        const nativeStarted=performance.now();await runtime.nativeFeatureSampling.load(stableOpts.fetchArray);profile(opts,'native feature assets hydrate',nativeStarted,`view=${state.activeViewMode} grid=${text(runtime.nativeFeatureSampling.gridId)} overlays=${Object.keys(runtime.nativeFeatureSampling.overlays||{}).length}`);
        if(MOUNT_SEQUENCES.get(rootId)!==mountSequence||!live.isConnected){profile(opts,'mount abandoned after native feature hydrate',mountStarted,'stale=1');return;}
      }
      if(isSurfaceRuntime(runtime)&&state.surfaceAtlasPaths&&(state.surfaceAtlasPaths.selectedPath||state.surfaceAtlasPaths.lhPath||state.surfaceAtlasPaths.rhPath))await loadSurfaceAtlas(runtime,state,stableOpts,state.surfaceAtlasPaths.selectedPath||state.surfaceAtlasPaths.lhPath||state.surfaceAtlasPaths.rhPath);
      const stateStarted=performance.now();
      state.contentId=text(runtime.payload.contentId);
      if(isSurfaceRuntime(runtime)){
        const requestedVertex=Math.round(finite(state.currentVoxel&&state.currentVoxel[0],1)),vertex=clamp(requestedVertex,1,runtime.surfaceRuntime.nVertices);state.currentVoxel=[vertex,1,1];state.currentWorldMm=surfaceAdapter().vertexWorld(runtime,state,vertex-1);
      }else{
        if(state.currentVoxel.some(x=>!Number.isFinite(Number(x))))state.currentVoxel=arr(runtime.payload.initialVoxel).map(Number);state.currentVoxel=state.currentVoxel.map((x,i)=>clamp(Math.round(Number(x)),1,runtime.dims[i]));PLANES.forEach(p=>{if(!validVoxel(state.planes[p].voxel))state.planes[p].voxel=state.currentVoxel.slice();});
      }
      if(!state.selectedTemplateId&&runtime.payload.selectedTemplate&&runtime.payload.selectedTemplate.available)state.selectedTemplateId=text(runtime.payload.selectedTemplate.templateId);
      if(!state.selectedAtlasId&&runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.available)state.selectedAtlasId=text(runtime.payload.selectedAtlas.atlasId);
      if(!runtime.overlays[state.activePageMetricId]&&!state.dualOverlayEnabled){
        const loaded=Object.keys(runtime.overlays)[0]||'';
        if(loaded)state.activePageMetricId=loaded;
      }
      normalizeState(state,measures);
      profile(opts,'post-workspace state normalization',stateStarted,`enabled=${state.enabledMetricIds.length}`);
      bindRuntime(stableOpts,live,runtime,state,measures);
      redraw(runtime,state,live,stableOpts,true);
      live.classList.remove('rvImagingPreparing');live.dataset.imagingStatus='ready';
      notify(stableOpts,state,'loaded');
      profile(opts,'mount to first visible render TOTAL',mountStarted,`contentId=${state.contentId} overlays=${Object.keys(runtime.overlays).length}`);return live;
    }catch(err){
      if(MOUNT_SEQUENCES.get(rootId)!==mountSequence||!live.isConnected)return;
      live.classList.remove('rvImagingPreparing');
      const failure=err&&err.message||String(err),trace=err&&err.stack||failure;
      const loading=live.querySelector('[data-imaging-loading]');
      if(loading){loading.hidden=false;loading.style.display='block';loading.classList.add('rvImagingError');loading.style.whiteSpace='pre-wrap';loading.style.overflow='auto';loading.textContent=`Imaging viewer initialization failed:\n${trace}`;}
      live.dataset.imagingStatus='error';
      if(typeof stableOpts.setMessage==='function')stableOpts.setMessage(`The imaging viewer could not be opened:\n${trace}`,'danger');
      console.error('NM2 imaging viewer mount failed:',err);
      profile(opts,'mount to failure TOTAL',mountStarted,`message=${failure} stack=${trace}`);
      if(stableOpts.throwOnMountFailure)throw err;return live;
    }
  }

  const api={availableMeasures,defaultState,normalizeState,normalizeMultiSlice,toolbarHtml,toggleMetric,activateMetric,viewModeBarHtml,metricDisplayState,displayContract,currentInteractionIdentity,overlayColor,activeDisplayRange,shellHtml,mount,unmount,publish,capture,updateScientificSelection,applyViewportHeight,computeROIRows,roiRowsPreparationInput,roiMapperPublicationOptions,multiSliceIndices,multiSliceControlsHtml,readMultiSliceControls,atlasLookupAtVoxel,montageSliceLabel,representationIds:['imaging.2d','imaging.3d'],applyStateFile,_test:{requestedMetricIds,roiRowsForMeasure,roiRowsForMeasures,canonicalROIMaterialization,canonicalROIRowsForMeasures,roiMapperAtlasDescriptor,roiMapperDisplayContract,featureRepresentationDefinition,shared2DOverlayControlsHtml,replace2DOverlayControls,extremumFor,applyExtremumSelection,restoreAutomaticExtremumViewState,clearExtremumSelection,focusedValue,setThresholdFromFocusedValue,applyControlWidthClass,controlBodyHtml,tooltipText,tooltipAttributesFromText,displayRasterSignature,resetImagingScrollPositions,workspaceStructuralIdentity,workspaceStructuralReuseCompatible,reusableAsset,synchronizeMetricShell,metricTabsHtml,scientificTabSignature,viewTabKind,registerTabRoot,activateRetainedViewTab,synchronizeFeatureInterpolationControl,synchronizeAtlasDependentControls,normalizeWorkspaceCapabilities,effectiveFeatureInterpolation}};
  window.NMResultsViewerImagingViewer=api;if(window.NMResultsViewerOutput)window.NMResultsViewerOutput.registerAdapter(api);
})();
