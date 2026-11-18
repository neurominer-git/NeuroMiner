(function(){
  'use strict';

  const {text,toArray}=globalThis.NMResultsViewerPrimitives;
  const FILE_SCHEMA='NMImagingViewerStateFile';
  const FILE_VERSION=2;
  const CONTRACT_VERSION='G8D-1';
  const PRESENTATION_FIELDS=['activeViewMode','anatomyInterpolation','featureInterpolation','interactive2DRendererMode','backgroundBrightness','anatomyGamma','tooltipsEnabled','crosshairVisible','syncViews','zoomLinkMode','atlasBoundariesVisible','atlasBoundaryColor','atlasBoundaryOpacity','dualOverlaySilhouetteNegativeColor','dualOverlaySilhouettePositiveColor','roiMinPct','multiSlice','surfaceAtlasPaths'];
  const SEMANTIC_KEYS=['metricKey','sourceField','sourceKey','featureSource','featureSourceId','decompositionId','classId','classLabel','analysisId','contextId','spatialMapId','gridId','contentId','signatureHash','featureKeyHash'];
  const DISPLAY_FIELDS=['thresholdMode','thresholdLow','thresholdHigh','thresholdValue','opacity','negativeColor','midpointColor','positiveColor','colorStops','displayRangeMode','manualDisplayLower','manualDisplayUpper'];
  const THRESHOLD_MODES=Object.freeze(['none','outside_interval','above_abs','above','below']);
  const RENDERING_MODES=Object.freeze(['surface_projection','volume_raycast']);
  const APPEARANCE_ANATOMY_FIELDS=Object.freeze(['opacity','brightness','gamma']);
  const APPEARANCE_LIGHTING_FIELDS=Object.freeze(['frame','ambient','diffuse','specular','shininess','azimuthDeg','elevationDeg','temperature','backgroundColor','backgroundAlpha']);
  const OBSOLETE_DISPLAY_FIELDS=Object.freeze(['negativeThreshold','positiveThreshold','singleThreshold']);
  function finiteOrNull(v){if(v===null||v===undefined||v==='')return null;const n=Number(v);return Number.isFinite(n)?n:null;}
  function clone(value){
    if(value===undefined)return undefined;
    if(value===null||typeof value==='string'||typeof value==='boolean')return value;
    if(typeof value==='number')return Number.isFinite(value)?value:null;
    if(Array.isArray(value)||ArrayBuffer.isView(value))return Array.from(value,x=>clone(x));
    if(typeof value==='object'){
      const out={};
      Object.keys(value).sort().forEach(key=>{
        if(!key.startsWith('_')&&typeof value[key]!=='function'&&value[key]!==undefined)out[key]=clone(value[key]);
      });
      return out;
    }
    return undefined;
  }
  function canonicalStringify(value){return JSON.stringify(clone(value),null,2)+'\n';}
  function runtimeClone(value){
    if(value===undefined||value===null||typeof value==='string'||typeof value==='boolean'||typeof value==='number')return value;
    if(Array.isArray(value)||ArrayBuffer.isView(value))return Array.from(value,x=>runtimeClone(x));
    if(typeof value==='object'){const out={};Object.keys(value).forEach(key=>{if(typeof value[key]!=='function'&&value[key]!==undefined)out[key]=runtimeClone(value[key]);});return out;}return undefined;
  }
  function rehydrateNullNumbers(value){
    if(value===null)return NaN;if(Array.isArray(value))return value.map(rehydrateNullNumbers);if(value&&typeof value==='object'){const out={};Object.keys(value).forEach(key=>{out[key]=rehydrateNullNumbers(value[key]);});return out;}return value;
  }
  function pick(source,fields){const out={};fields.forEach(key=>{if(source&&source[key]!==undefined)out[key]=clone(source[key]);});return out;}
  function numericVector(value,n){const out=toArray(value).slice(0,n).map(finiteOrNull);while(out.length<n)out.push(null);return out;}
  function affineSignature(reference){
    const affine=reference&&reference.affineVoxel1ToWorld;
    return toArray(affine).map(row=>toArray(row).map(v=>{const n=Number(v);return Number.isFinite(n)?Number(n.toPrecision(12)):null;}));
  }
  function gridIdentity(runtime,state){
    const payload=runtime&&runtime.payload||{},reference=payload.spatialReference||{},domain=text(payload.sourceDomain).toLowerCase();
    if(domain==='surface'){const surface=payload.surface||{};return {domain:'surface',gridId:text(reference.gridId||surface.topologyIdentity),dimensions:[Number(surface.native&&surface.native.nVertices||runtime&&runtime.dims&&runtime.dims[0]||0),1,1],affineVoxel1ToWorld:[],displayGridPolicy:'surface_native',topologyIdentity:text(surface.topologyIdentity||reference.topologyIdentity),vertexOrderIdentity:text(surface.vertexOrderIdentity||reference.vertexOrderIdentity),surfaceTemplate:text(surface.surfaceTemplate||reference.surfaceTemplate),partCount:Number(surface.partCount||0)};}
    return {domain:'volume',gridId:text(reference.gridId||state&&state.gridId||payload.gridId),dimensions:toArray(runtime&&runtime.dims||payload.dimensions).slice(0,3).map(Number),affineVoxel1ToWorld:affineSignature(reference),displayGridPolicy:text(state&&state.displayGridPolicy)};
  }
  function sanitizeGrid(grid){return {domain:text(grid&&grid.domain||'volume'),gridId:text(grid&&grid.gridId),dimensions:numericVector(grid&&grid.dimensions,3),affineVoxel1ToWorld:toArray(grid&&grid.affineVoxel1ToWorld).slice(0,4).map(row=>numericVector(row,4)),displayGridPolicy:text(grid&&grid.displayGridPolicy),topologyIdentity:text(grid&&grid.topologyIdentity),vertexOrderIdentity:text(grid&&grid.vertexOrderIdentity),surfaceTemplate:text(grid&&grid.surfaceTemplate),partCount:finiteOrNull(grid&&grid.partCount)};}
  function descriptorValue(meta,key){const v=meta&&meta[key];return v===undefined||v===null?'':text(v);}
  function overlayIdentity(overlay){
    const meta=overlay&&overlay.meta||overlay||{},out={measureId:text(meta.measureId),label:text(meta.label),valuePolarity:text(meta.valuePolarity||meta.polarity)};
    SEMANTIC_KEYS.forEach(key=>{const value=descriptorValue(meta,key);if(value)out[key]=value;});
    return out;
  }
  function sanitizeOverlayIdentity(identity){return identity?overlayIdentity(identity):null;}
  function mergeDefined(){
    const out={};
    Array.from(arguments).forEach(source=>{if(!source||typeof source!=='object')return;Object.keys(source).forEach(key=>{if(source[key]!==undefined&&source[key]!==null&&source[key]!=='')out[key]=source[key];});});
    return out;
  }
  function targetOverlayIdentities(runtime){
    const payload=runtime&&runtime.payload||{},measures=toArray(runtime&&runtime.catalogueMeasures).concat(toArray(payload.measures)),spatialMaps=toArray(payload.spatialMaps),hydrated=runtime&&runtime.overlays||{},ids=new Set();
    measures.forEach(x=>{if(x&&x.measureId)ids.add(text(x.measureId));});spatialMaps.forEach(x=>{if(x&&x.measureId)ids.add(text(x.measureId));});Object.keys(hydrated).forEach(id=>ids.add(text(id)));
    return Array.from(ids).sort().map(id=>{
      const measure=measures.find(x=>text(x&&x.measureId)===id)||{},spatial=spatialMaps.find(x=>text(x&&x.measureId)===id)||{},overlay=hydrated[id]&&hydrated[id].meta||{};
      return overlayIdentity(mergeDefined(measure,spatial,overlay,{measureId:id}));
    });
  }
  function identityById(identities,id){return identities.find(x=>x.measureId===text(id))||null;}
  function availableIds(catalogue,key){return new Set(toArray(catalogue).filter(x=>x&&x.enabled!==false).map(x=>text(x[key])).filter(Boolean));}
  function sourceIdentity(runtime,state){
    const payload=runtime&&runtime.payload||{},selectedTemplate=payload.selectedTemplate||{},selectedAtlas=payload.selectedAtlas||{},overlays=targetOverlayIdentities(runtime),byId=id=>identityById(overlays,id),enabledIds=toArray(state&&state.enabledMetricIds).map(text).filter(Boolean);
    return {sourceDomain:text(payload.sourceDomain||'volume'),contentId:text(payload.contentId),selectedFeatureContextId:text(payload.selectedFeatureContextId||payload.featureContextId),provenance:{resultSourceId:text(payload.resultSourceId),analysisIndex:finiteOrNull(payload.analysisIndex),targetIndex:finiteOrNull(payload.targetIndex),resultTargetIndex:finiteOrNull(payload.resultTargetIndex),classifierIndex:finiteOrNull(payload.classifierIndex),selectedImagingEntryId:text(payload.selectedImagingEntryId)},grid:gridIdentity(runtime,state),templateId:text(state&&state.selectedTemplateId||selectedTemplate.templateId),atlasId:text(state&&state.selectedAtlasId||selectedAtlas.atlasId||'none'),enabledOverlays:enabledIds.map(byId).filter(Boolean),overlayA:byId(state&&state.overlayAId),overlayB:byId(state&&state.overlayBId),activeOverlay:byId(state&&state.activePageMetricId),focusedOverlaySlot:text(state&&state.focusedOverlaySlot||'A')};
  }
  function sanitizeSource(source){
    const enabled=toArray(source&&source.enabledOverlays).map(sanitizeOverlayIdentity).filter(x=>x&&x.measureId);
    return {sourceDomain:text(source&&source.sourceDomain||'volume'),contentId:text(source&&source.contentId),selectedFeatureContextId:text(source&&source.selectedFeatureContextId),provenance:pick(source&&source.provenance,['resultSourceId','analysisIndex','targetIndex','resultTargetIndex','classifierIndex','selectedImagingEntryId']),grid:sanitizeGrid(source&&source.grid||{}),templateId:text(source&&source.templateId),atlasId:text(source&&source.atlasId||'none'),enabledOverlays:enabled,overlayA:sanitizeOverlayIdentity(source&&source.overlayA),overlayB:sanitizeOverlayIdentity(source&&source.overlayB),activeOverlay:sanitizeOverlayIdentity(source&&source.activeOverlay),focusedOverlaySlot:text(source&&source.focusedOverlaySlot||'A')};
  }
  function identityList(source){
    const out=[],seen=new Set();
    toArray(source&&source.enabledOverlays).concat([source&&source.overlayA,source&&source.overlayB,source&&source.activeOverlay]).forEach(identity=>{if(!identity||!identity.measureId||seen.has(identity.measureId))return;seen.add(identity.measureId);out.push(identity);});
    return out;
  }
  function sanitizePlane(plane){return {zoom:finiteOrNull(plane&&plane.zoom),panX:finiteOrNull(plane&&plane.panX),panY:finiteOrNull(plane&&plane.panY),voxel:numericVector(plane&&plane.voxel,3)};}
  function sanitizePlanes(planes){return {axial:sanitizePlane(planes&&planes.axial),coronal:sanitizePlane(planes&&planes.coronal),sagittal:sanitizePlane(planes&&planes.sagittal)};}
  function sanitizeMultiSlice(value){return pick(value,['planeId','rows','columns','startSlice','endSlice','gapPx','labelMode','labelPosition','fitMode','labelFontPx']);}
  function sanitizeDisplayState(value){const source=value&&typeof value==='object'?value:{};const obsolete=OBSOLETE_DISPLAY_FIELDS.filter(key=>Object.prototype.hasOwnProperty.call(source,key));if(obsolete.length)throw new Error(`Obsolete imaging-viewer display fields are not accepted: ${obsolete.join(', ')}.`);const out=pick(source,DISPLAY_FIELDS);if(out.thresholdMode!==undefined&&!THRESHOLD_MODES.includes(text(out.thresholdMode)))throw new Error(`Unknown threshold mode in imaging-viewer state: ${text(out.thresholdMode)}`);return out;}
  function sanitizeDisplayStates(state,identities){
    const source=state&&state.perMetricDisplayState||{},out={};
    identities.forEach(identity=>{if(!identity||!identity.measureId)return;const value=source[identity.measureId];if(value&&typeof value==='object')out[identity.measureId]=sanitizeDisplayState(value);});
    return out;
  }
  function sanitizeMontage(value){return pick(value,['preset','layout','tileWidth','tileHeight','exportScale','gapPx','labelsVisible','orientationVisible','backgroundMode']);}
  function sanitizeVideo(value){return pick(value,['mode','format','fps','rotationRangeDeg','degreesPerFrame','direction','elevationChangeDeg','loopMode','backgroundColor','resolutionPreset','width','height','startView','projection','rankingCriterion','rankingDirection','roiCount','roiDurationSec','transitionSec','sequenceMode','outsideRoiOpacity','anatomyOpacity','outlineOpacity','roiBoundaryOpacity','roiBoundaryColor','showLabel','showRank','showScore','leaderLineColor','leaderLineWidth','labelBackgroundColor','labelBackgroundOpacity','labelFadeSec','zoomEnabled','autoZoomSmallOnly','smallRoiThresholdElements','zoomFactor','zoomInSec','zoomHoldSec','zoomOutSec','previewFps']);}
  function sanitizeAppearanceSnapshot(value){return {anatomy:pick(value&&value.anatomy,APPEARANCE_ANATOMY_FIELDS),lighting:pick(value&&value.lighting,APPEARANCE_LIGHTING_FIELDS)};}
  function sanitizeAppearanceProfiles(value){if(value!==undefined&&value!==null&&(typeof value!=='object'||Array.isArray(value)))throw new Error('The 3-D appearanceProfiles field must be an object.');const source=value||{},unknown=Object.keys(source).filter(id=>!RENDERING_MODES.includes(id));if(unknown.length)throw new Error(`Unknown 3-D appearance profile(s) in imaging-viewer state: ${unknown.join(', ')}.`);const out={};RENDERING_MODES.forEach(id=>{if(source[id]!==undefined&&source[id]!==null){if(typeof source[id]!=='object'||Array.isArray(source[id]))throw new Error(`The 3-D appearance profile ${id} must be an object.`);out[id]=sanitizeAppearanceSnapshot(source[id]);}});return out;}
  function canonicalRenderingMode(value,allowLegacy){const mode=text(value);if(!mode)return 'surface_projection';if(RENDERING_MODES.includes(mode))return mode;if(allowLegacy&&mode==='volume_isosurfaces')return 'volume_raycast';throw new Error(`Unknown 3-D rendering mode in imaging-viewer state: ${mode}`);}
  function sanitizeExtremumReveal(value){
    if(!value||value.active!==true||!value.snapshot||!value.plan)return {active:false,markerSignature:'',snapshot:null,plan:null};
    const snapshot={camera:pick(value.snapshot.camera,['projection','targetWorldMm','orientationQuaternion','distanceMm','panMm','fovDeg','orbitMode','azimuthDeg','elevationDeg']),clipping:pick(value.snapshot.clipping,['mode','linkedToSelection','positionWorldMm','keepX','keepY','keepZ']),selectedPreset:text(value.snapshot.selectedPreset),surfaceHemisphereVisibility:text(value.snapshot.surfaceHemisphereVisibility||'both')};snapshot.clipping.fillCutSurface=false;
    if(snapshot.camera.targetWorldMm!==undefined)snapshot.camera.targetWorldMm=numericVector(snapshot.camera.targetWorldMm,3);if(snapshot.camera.orientationQuaternion!==undefined)snapshot.camera.orientationQuaternion=numericVector(snapshot.camera.orientationQuaternion,4);if(snapshot.camera.panMm!==undefined)snapshot.camera.panMm=numericVector(snapshot.camera.panMm,2);if(snapshot.clipping.positionWorldMm!==undefined)snapshot.clipping.positionWorldMm=numericVector(snapshot.clipping.positionWorldMm,3);
    const plan=pick(value.plan,['axis','axisIndex','mode','keep','preset','exitDistanceMm','intersectionCount','score','planningMode','surfaceHemisphere','surfaceVisibility']);plan.positionWorldMm=numericVector(value.plan.positionWorldMm,3);
    return {active:true,markerSignature:text(value.markerSignature),snapshot,plan};
  }
  function sanitizeRender3D(value){
    const out=pick(value,['renderingMode','gridId','meshQuality','selectedPreset','surfaceHemisphereVisibility']);out.renderingMode=canonicalRenderingMode(out.renderingMode,false);
    const profileId=text(value&&value.appearanceProfileId);if(profileId&&!RENDERING_MODES.includes(profileId))throw new Error(`Unknown 3-D appearance profile in imaging-viewer state: ${profileId}`);if(profileId&&profileId!==out.renderingMode)throw new Error(`The 3-D appearance profile ${profileId} does not match rendering mode ${out.renderingMode}.`);out.appearanceProfileId=profileId||out.renderingMode;out.appearanceProfiles=sanitizeAppearanceProfiles(value&&value.appearanceProfiles);if(!out.appearanceProfiles[out.renderingMode])out.appearanceProfiles[out.renderingMode]=sanitizeAppearanceSnapshot(value);
    out.camera=pick(value&&value.camera,['projection','targetWorldMm','orientationQuaternion','distanceMm','panMm','fovDeg','orbitMode','azimuthDeg','elevationDeg']);
    if(out.camera.targetWorldMm!==undefined)out.camera.targetWorldMm=numericVector(out.camera.targetWorldMm,3);if(out.camera.orientationQuaternion!==undefined)out.camera.orientationQuaternion=numericVector(out.camera.orientationQuaternion,4);if(out.camera.panMm!==undefined)out.camera.panMm=numericVector(out.camera.panMm,2);
    out.anatomy=pick(value&&value.anatomy,['opacity','brightness','gamma','surfaceFoldingSmoothnessMm','surfaceFoldingGamma','surfaceFoldingColor','surfaceFoldingOpacity','volumeSurfaceLevel','volumeBoundarySmoothingMm','volumeInteriorAlpha','volumeMaxSurfaces','volumeOcclusion','volumeOcclusionMm','surfaceDepthMm','maxSurfaceDepthMm','outlineVisible','outlineOpacity','outlineColor']);
    out.overlay=pick(value&&value.overlay,['visible','surfaceFeatureSmoothingMm','projectionDepthMm','maxDepthMm','projectionLocalSupportFwhmMm','projectionLocalSupportRetention','projectionLocalSupportSelectivity','volumeOpacity','volumeColorIntensity','boundarySmoothingMm','volumeSlabDepthMm','featureInteriorAlpha']);out.overlay.surfaceSamplingMode='continuous_signed_trilinear';out.overlay.projectionAlphaMode='threshold_free_local_support';
    out.clipping=pick(value&&value.clipping,['mode','linkedToSelection','positionWorldMm','keepX','keepY','keepZ']);out.clipping.fillCutSurface=false;if(out.clipping.positionWorldMm!==undefined)out.clipping.positionWorldMm=numericVector(out.clipping.positionWorldMm,3);
    out.lighting=pick(value&&value.lighting,['frame','ambient','diffuse','specular','shininess','azimuthDeg','elevationDeg','temperature','backgroundColor','backgroundAlpha']);
    out.montage=sanitizeMontage(value&&value.montage);
    out.video=sanitizeVideo(value&&value.video);
    out.volumeCoverageProvenance=clone(value&&value.volumeCoverageProvenance||null);
    out.selection=pick(value&&value.selection,['surfaceWorldMm','surfaceVoxel','sourceVoxel','sourceWorldMm','vertexIndex','linearIndex','roiCode','roiLabel','featureValue','nativeFeatureValue','displaySmoothingMm','hitType']);
    ['surfaceWorldMm','surfaceVoxel','sourceVoxel','sourceWorldMm'].forEach(key=>{if(out.selection[key]!==undefined)out.selection[key]=numericVector(out.selection[key],3);});
    out.extremumReveal=sanitizeExtremumReveal(value&&value.extremumReveal);
    return out;
  }
  function sanitizeExtremumMarker(value){
    if(!value||typeof value!=='object')return null;
    const out=pick(value,['kind','measureId','linearIndex','vertexIndex','value','nativeValue','displaySmoothingMm','atlasCode','atlasLabel','visible']);out.voxel=numericVector(value.voxel,3);out.worldMm=numericVector(value.worldMm,3);if(value.navigation&&typeof value.navigation==='object'){out.navigation=pick(value.navigation,['mode','exitDistanceMm','intersectionCount','rotationRad','hemisphere','hemisphereVisibility','preset']);out.navigation.direction=numericVector(value.navigation.direction,3);out.navigation.customPlane=[];}return out;
  }
  function sanitizeViewerState(state,identities){
    const out=pick(state,PRESENTATION_FIELDS.filter(x=>x!=='multiSlice'));
    out.multiSlice=sanitizeMultiSlice(state&&state.multiSlice);
    out.displayGridPolicy=text(state&&state.displayGridPolicy);out.selectedTemplateId=text(state&&state.selectedTemplateId);out.selectedAtlasId=text(state&&state.selectedAtlasId);const paths=state&&state.surfaceAtlasPaths||{};out.surfaceAtlasPaths={selectedPath:text(paths.selectedPath),lhPath:text(paths.lhPath),rhPath:text(paths.rhPath)};
    out.enabledMetricIds=toArray(state&&state.enabledMetricIds).map(text).filter(Boolean);out.activePageMetricId=text(state&&state.activePageMetricId);out.overlayAId=text(state&&state.overlayAId);out.overlayBId=text(state&&state.overlayBId);out.focusedOverlaySlot=text(state&&state.focusedOverlaySlot||'A');out.dualOverlayEnabled=!!(state&&state.dualOverlayEnabled);
    out.currentVoxel=numericVector(state&&state.currentVoxel,3);out.currentWorldMm=numericVector(state&&state.currentWorldMm,3);out.planes=sanitizePlanes(state&&state.planes||{});
    out.perMetricDisplayState=sanitizeDisplayStates(state,identities||[]);out.render3D=sanitizeRender3D(state&&state.render3D||{});out.extremumMarker=sanitizeExtremumMarker(state&&state.extremumMarker);
    return out;
  }
  function validateIdentityCoverage(source,viewerState){
    const ids=new Set(identityList(source).map(x=>x.measureId)),requested=toArray(viewerState&&viewerState.enabledMetricIds).concat([viewerState&&viewerState.overlayAId,viewerState&&viewerState.overlayBId,viewerState&&viewerState.activePageMetricId]).map(text).filter(Boolean),missing=Array.from(new Set(requested.filter(id=>!ids.has(id))));
    if(missing.length)throw new Error(`The imaging-viewer state lacks stable identity descriptors for: ${missing.join(', ')}.`);
  }
  function volumeRenderingProvenance(runtime,state){if(text(runtime&&runtime.payload&&runtime.payload.sourceDomain).toLowerCase()==='surface')return null;const api=window.NMImagingVolumeRenderingContract;if(!api||typeof api.provenance!=='function')throw new Error('The canonical imaging volume-rendering contract is unavailable.');const render3D=state&&state.render3D||{},anatomy=render3D.anatomy||{},prepared=render3D.volumeCoverageProvenance||null,boundarySmoothingMm=anatomy.volumeBoundarySmoothingMm,spacing=toArray(runtime&&runtime.nativeFeatureSampling&&runtime.nativeFeatureSampling.spatialReference&&runtime.nativeFeatureSampling.spatialReference.voxelSpacingMm||runtime&&runtime.payload&&runtime.payload.spatialReference&&runtime.payload.spatialReference.voxelSpacingMm).slice(0,3),active={stage:'C18g5-R3G',geometry:Number(boundarySmoothingMm)===0?'native_voxel_boundary_audit':'component_signed_distance_volume_preserving',contractCompliant:true,structuralTransfer:'structural_scalar_level_crossing',structuralDepth:'first_composited_surface',anatomyFeatureComposition:'single_shared_t_front_to_back',featureBoundarySmoothing:'signed_distance_gaussian_user_mm',featureVolumePreservation:'per_polarity_6_connected_component',featureValueReconstruction:'separate_positive_negative_fixed_physical_weighted_mean_rgba8'};return api.provenance({nativeSpacingMm:spacing,contract:{boundarySmoothingMm},activeImplementation:active,preparedCoverage:prepared});}
  function build(runtime,state){const source=sanitizeSource(sourceIdentity(runtime,state)),viewerState=sanitizeViewerState(state,identityList(source));validateIdentityCoverage(source,viewerState);return {schema:FILE_SCHEMA,schemaVersion:FILE_VERSION,contractVersion:CONTRACT_VERSION,serialization:'canonical_json_v1',source,viewerState,renderingContract:clone(volumeRenderingProvenance(runtime,state))};}
  function filename(runtime,state){
    const source=sourceIdentity(runtime,state),metric=text(source.activeOverlay&&source.activeOverlay.measureId||source.overlayA&&source.overlayA.measureId||'viewer').replace(/[^A-Za-z0-9._-]+/g,'_').slice(0,48)||'viewer',content=(source.contentId||'portable').replace(/[^A-Za-z0-9]+/g,'').slice(0,12)||'portable';return `NM_imaging_${metric}_${content}.nmivstate`;
  }
  function migrateV1ToV2(value){const out=runtimeClone(value),render3D=out&&out.viewerState&&out.viewerState.render3D;if(render3D&&typeof render3D==='object'){render3D.renderingMode=canonicalRenderingMode(render3D.renderingMode,true);render3D.appearanceProfileId=render3D.renderingMode;render3D.appearanceProfiles={[render3D.renderingMode]:sanitizeAppearanceSnapshot(render3D)};}out.schemaVersion=2;out.contractVersion=CONTRACT_VERSION;return out;}
  function parse(serialized,name){
    let value;try{value=JSON.parse(text(serialized));}catch(err){throw new Error(`The imaging-viewer state file is not valid JSON: ${err.message||String(err)}`);}
    if(!value||value.schema!==FILE_SCHEMA||!value.viewerState||!value.source)throw new Error(`Unsupported imaging-viewer state schema. Expected ${FILE_SCHEMA} version ${FILE_VERSION}.`);
    const sourceVersion=Number(value.schemaVersion);if(sourceVersion===1)value=migrateV1ToV2(value);else if(sourceVersion!==FILE_VERSION)throw new Error(`Unsupported imaging-viewer state schema version ${text(value.schemaVersion)}. Expected ${FILE_VERSION} or migratable version 1.`);
    const source=sanitizeSource(value.source),viewerState=sanitizeViewerState(value.viewerState,identityList(source));validateIdentityCoverage(source,viewerState);return {schema:FILE_SCHEMA,schemaVersion:FILE_VERSION,contractVersion:text(value.contractVersion),serialization:text(value.serialization),source,viewerState,renderingContract:clone(value.renderingContract||null),__fileName:text(name||'')};
  }
  function equalArray(a,b,tol){const x=toArray(a),y=toArray(b);if(x.length!==y.length)return false;return x.every((v,i)=>{const av=Number(v),bv=Number(y[i]);return Number.isFinite(av)&&Number.isFinite(bv)?Math.abs(av-bv)<=tol:v===y[i];});}
  function gridCompatible(saved,target){
    if(!saved||!target)return false;const sd=text(saved.domain||'volume'),td=text(target.domain||'volume');if(sd!==td)return false;if(saved.displayGridPolicy&&target.displayGridPolicy&&saved.displayGridPolicy!==target.displayGridPolicy)return false;
    if(sd==='surface')return !!saved.topologyIdentity&&saved.topologyIdentity===target.topologyIdentity&&!!saved.vertexOrderIdentity&&saved.vertexOrderIdentity===target.vertexOrderIdentity&&equalArray(saved.dimensions,target.dimensions,0);
    const sdim=toArray(saved.dimensions),tdim=toArray(target.dimensions),sa=toArray(saved.affineVoxel1ToWorld).flat(),ta=toArray(target.affineVoxel1ToWorld).flat(),geometryKnown=sdim.length===3&&tdim.length===3&&sa.length===16&&ta.length===16&&sdim.concat(tdim,sa,ta).every(v=>Number.isFinite(Number(v))),geometryOk=geometryKnown&&equalArray(sdim,tdim,0)&&equalArray(sa,ta,1e-7);
    return geometryOk;
  }
  function semanticScore(saved,target){let compared=0,matched=0;SEMANTIC_KEYS.forEach(key=>{if(saved&&saved[key]){compared++;if(text(saved[key])===text(target&&target[key]))matched++;}});return {compared,matched};}
  function mapOverlay(saved,targetIdentities){
    if(!saved)return {status:'not_requested',savedId:'',targetId:'',reason:''};
    const exact=targetIdentities.find(x=>x.measureId===saved.measureId);
    if(exact){const score=semanticScore(saved,exact);if(score.matched===score.compared)return {status:'exact',savedId:saved.measureId,targetId:exact.measureId,reason:'measure and available semantic identifiers match'};return {status:'incompatible',savedId:saved.measureId,targetId:'',reason:`measureId ${saved.measureId} exists but semantic identifiers differ`};}
    const candidates=targetIdentities.map(target=>({target,score:semanticScore(saved,target)})).filter(x=>x.score.compared>=2&&x.score.matched===x.score.compared);
    if(candidates.length===1)return {status:'remapped',savedId:saved.measureId,targetId:candidates[0].target.measureId,reason:'unique semantic-identifier match'};
    if(candidates.length>1)return {status:'incompatible',savedId:saved.measureId,targetId:'',reason:'semantic remap is ambiguous'};
    return {status:'incompatible',savedId:saved.measureId,targetId:'',reason:`measure ${saved.measureId||saved.label||'unknown'} is unavailable`};
  }
  function assess(file,runtime,state){
    const targetSource=sourceIdentity(runtime,state),targetOverlays=targetOverlayIdentities(runtime),savedIdentities=identityList(file.source),overlayMaps=savedIdentities.map(identity=>mapOverlay(identity,targetOverlays)),mapBySavedId=id=>overlayMaps.find(x=>x.savedId===text(id))||{status:'not_requested',savedId:text(id),targetId:'',reason:''};
    const maps={overlayA:mapBySavedId(file.source.overlayA&&file.source.overlayA.measureId),overlayB:mapBySavedId(file.source.overlayB&&file.source.overlayB.measureId),activeOverlay:mapBySavedId(file.source.activeOverlay&&file.source.activeOverlay.measureId),enabledOverlays:overlayMaps};
    const gridOk=gridCompatible(file.source.grid,targetSource.grid),templateIds=availableIds(runtime&&runtime.payload&&runtime.payload.templateCatalogue,'templateId'),atlasIds=availableIds(runtime&&runtime.payload&&runtime.payload.atlasCatalogue,'atlasId');
    if(targetSource.templateId)templateIds.add(targetSource.templateId);if(targetSource.atlasId)atlasIds.add(targetSource.atlasId);atlasIds.add('none');
    const templateOk=!file.source.templateId||templateIds.has(file.source.templateId),atlasOk=!file.source.atlasId||atlasIds.has(file.source.atlasId),requested=overlayMaps.filter(x=>x.status!=='not_requested'),scientificOk=requested.every(x=>x.status==='exact'||x.status==='remapped')&&templateOk&&atlasOk,exactContent=!!file.source.contentId&&file.source.contentId===targetSource.contentId,hasRemap=requested.some(x=>x.status==='remapped');
    let outcome='Partially applicable';if(gridOk&&scientificOk&&exactContent&&!hasRemap)outcome='Exact match';else if(gridOk&&scientificOk)outcome='Compatible remap';else if(!scientificOk&&!requested.some(x=>x.status==='exact'||x.status==='remapped'))outcome='Incompatible';
    return {outcome,gridCompatible:gridOk,exactContent,templateCompatible:templateOk,atlasCompatible:atlasOk,maps,targetSource};
  }
  function copyFields(target,source,fields,applied){fields.forEach(key=>{if(source&&source[key]!==undefined){target[key]=runtimeClone(source[key]);applied.push(key);}});}
  function mappedId(savedId,maps){if(!savedId)return '';const hit=toArray(maps&&maps.enabledOverlays).find(x=>x.savedId===text(savedId)&&(x.status==='exact'||x.status==='remapped'));return hit?hit.targetId:'';}
  function nonspatial3D(render3D){const safe=runtimeClone(render3D||{});delete safe.gridId;delete safe.camera;delete safe.clipping;delete safe.selection;delete safe.extremumReveal;return safe;}
  function apply(file,runtime,currentState){
    const compatibility=assess(file,runtime,currentState),saved=rehydrateNullNumbers(sanitizeViewerState(file.viewerState,identityList(file.source))),next=runtimeClone(currentState)||{},applied=[],remapped=[],skipped=[],incompatible=[];
    copyFields(next,saved,PRESENTATION_FIELDS,applied);
    compatibility.maps.enabledOverlays.forEach(map=>{if(map.status==='remapped')remapped.push(`${map.savedId} → ${map.targetId}`);else if(map.status==='incompatible')incompatible.push(`overlay ${map.savedId||'unknown'}: ${map.reason}`);});
    const mappedA=compatibility.maps.overlayA.targetId||'',mappedB=compatibility.maps.overlayB.targetId||'',mappedActive=compatibility.maps.activeOverlay.targetId||mappedA;
    if(mappedA){next.overlayAId=mappedA;applied.push('overlayAId');}if(mappedB){next.overlayBId=mappedB;applied.push('overlayBId');}else next.overlayBId='';if(mappedActive){next.activePageMetricId=mappedActive;applied.push('activePageMetricId');}
    next.enabledMetricIds=Array.from(new Set(toArray(saved.enabledMetricIds).map(id=>mappedId(text(id),compatibility.maps)).filter(Boolean).concat([mappedA,mappedB,mappedActive].filter(Boolean))));next.focusedOverlaySlot=saved.focusedOverlaySlot==='B'&&mappedB?'B':'A';next.dualOverlayEnabled=!!(saved.dualOverlayEnabled&&mappedA&&mappedB);
    next.perMetricDisplayState={};Object.keys(saved.perMetricDisplayState||{}).forEach(savedId=>{const targetId=mappedId(savedId,compatibility.maps);if(targetId){next.perMetricDisplayState[targetId]=runtimeClone(saved.perMetricDisplayState[savedId]);applied.push(`display:${targetId}`);}else skipped.push(`display:${savedId}`);});
    if(compatibility.templateCompatible){next.selectedTemplateId=text(saved.selectedTemplateId||file.source.templateId);applied.push('selectedTemplateId');}else incompatible.push(`template: ${file.source.templateId}`);
    if(compatibility.atlasCompatible){next.selectedAtlasId=text(saved.selectedAtlasId||file.source.atlasId||'none');next.atlasBoundariesVisible=!!saved.atlasBoundariesVisible;applied.push('selectedAtlasId');}else{next.atlasBoundariesVisible=false;incompatible.push(`atlas: ${file.source.atlasId}`);}
    if(compatibility.gridCompatible){if(saved.displayGridPolicy){next.displayGridPolicy=text(saved.displayGridPolicy);applied.push('displayGridPolicy');}copyFields(next,saved,['currentVoxel','currentWorldMm','planes','render3D','extremumMarker'],applied);}else{skipped.push('displayGridPolicy','currentVoxel','currentWorldMm','plane coordinates','3-D camera/target/clipping/selection','extremum marker');const safe3D=nonspatial3D(saved.render3D);next.render3D=Object.assign({},next.render3D||{},safe3D);applied.push('3-D nonspatial presentation');}
    const summary={outcome:compatibility.outcome,applied,remapped,skipped,incompatible,gridCompatible:compatibility.gridCompatible,sourceFile:text(file.__fileName||'')};next.stateFileName=summary.sourceFile;next.stateCompatibilityStatus=summary.outcome;next.stateCompatibilitySummary=clone(summary);return {state:next,compatibility:summary};
  }

  window.NMImagingViewerState={FILE_SCHEMA,FILE_VERSION,CONTRACT_VERSION,build,filename,parse,assess,apply,canonicalStringify,sourceIdentity,overlayIdentity,gridCompatible,_test:{clone,semanticScore,mapOverlay,mappedId,basePresentationFields:PRESENTATION_FIELDS.slice(),targetOverlayIdentities,identityList,nonspatial3D,sanitizeViewerState,sanitizeRender3D,sanitizeAppearanceProfiles,canonicalRenderingMode,migrateV1ToV2,validateIdentityCoverage,runtimeClone,rehydrateNullNumbers,volumeRenderingProvenance}};
})();
