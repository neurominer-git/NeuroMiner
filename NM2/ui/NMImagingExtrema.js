(function(){
  'use strict';

  const {clamp,text,toArray}=globalThis.NMResultsViewerPrimitives;
  const CACHE=new Map();
  const CACHE_LIMIT=32;
  function finite(v,d){const n=Number(v);return Number.isFinite(n)?n:d;}
  function displaySemantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api)throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');return api;}
  function thresholdIdentity(contract){if(!contract||contract.contractVersion!==displaySemantics().CONTRACT_VERSION)throw new Error('Extrema selection requires a canonical display contract.');const threshold=contract.threshold||{};return [contract.contractVersion,threshold.mode,threshold.lower,threshold.upper,threshold.value].join(':');}
  function cacheSet(key,value){if(CACHE.has(key))CACHE.delete(key);CACHE.set(key,value);while(CACHE.size>CACHE_LIMIT)CACHE.delete(CACHE.keys().next().value);}
  function volumeIndexToVoxel1(dims,index){const nx=dims[0],ny=dims[1],k=Math.floor(index/(nx*ny)),rem=index-k*nx*ny,j=Math.floor(rem/nx),i=rem-j*nx;return [i+1,j+1,k+1];}
  function voxelToWorld(reference,voxel){const m=reference&&reference.affineVoxel1ToWorld;if(!Array.isArray(m)||m.length!==4)return [NaN,NaN,NaN];const v=[Number(voxel[0]),Number(voxel[1]),Number(voxel[2]),1];return [0,1,2].map(r=>toArray(m[r]).slice(0,4).reduce((sum,x,c)=>sum+Number(x)*v[c],0));}
  function transformPoint(matrix,point){const rows=toArray(matrix);if(rows.length!==4)return [NaN,NaN,NaN];const p=[Number(point[0]),Number(point[1]),Number(point[2]),1],q=rows.map(row=>toArray(row).slice(0,4).reduce((sum,x,c)=>sum+Number(x)*p[c],0));if(q.length!==4||q.some(x=>!Number.isFinite(x))||Math.abs(q[3])<Number.EPSILON)return [NaN,NaN,NaN];return [q[0]/q[3],q[1]/q[3],q[2]/q[3]];}
  function worldToVoxel(reference,worldMm){return transformPoint(reference&&reference.affineWorldToVoxel,worldMm);}
  function atlasAtVoxel(runtime,voxel){const dims=toArray(runtime&&runtime.dims).slice(0,3).map(Number),p=toArray(voxel).slice(0,3).map(x=>Math.round(Number(x)));if(dims.length!==3||p.length!==3||p.some((x,i)=>!Number.isFinite(x)||x<1||x>dims[i]))return {code:0,label:'Outside atlas grid',status:'outside'};return atlasAt(runtime,(p[0]-1)+dims[0]*((p[1]-1)+dims[1]*(p[2]-1)));}
  function atlasAt(runtime,index){if(!runtime||!runtime.atlas||!runtime.atlas.data)return {code:0,label:'No atlas selected',status:'unavailable'};const code=Math.max(0,Math.round(finite(runtime.atlas.data[index],0))),labels=runtime.atlas.meta&&runtime.atlas.meta.roiLabels||{};if(!code)return {code:0,label:'Unlabelled',status:'unlabelled'};return {code,label:text(labels['roi_'+code]||('ROI '+code)),status:'labelled'};}
  function identity(runtime,overlay,contract){return [
    'NMImagingExtrema:C18c2.12a',
    text(runtime&&runtime.payload&&runtime.payload.contentId),
    text(overlay&&overlay.meta&&overlay.meta.measureId),
    text(runtime&&runtime.payload&&runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.atlasId),
    toArray(runtime&&runtime.dims).join('x'),
    thresholdIdentity(contract)
  ].join('|');}
  function descriptor(runtime,overlay,index,value,kind){
    if(!(index>=0))return null;const voxel=volumeIndexToVoxel1(runtime.dims,index),worldMm=voxelToWorld(runtime.payload&&runtime.payload.spatialReference,voxel),atlas=atlasAt(runtime,index);
    return {schema:'NMImagingExtremumDescriptor',schemaVersion:1,contractVersion:'C18c2.12a',kind,measureId:text(overlay&&overlay.meta&&overlay.meta.measureId),linearIndex:index+1,voxel,worldMm,value:Number(value),supportValid:true,atlasCode:atlas.code,atlasLabel:atlas.label,atlasStatus:atlas.status};
  }
  function compute(runtime,overlay,contract){
    if(!runtime||!overlay||!overlay.data)throw new Error('Extrema require a hydrated imaging runtime and focused overlay.');
    const key=identity(runtime,overlay,contract);if(CACHE.has(key))return CACHE.get(key);
    const data=overlay.data,support=runtime.support||[],useSupport=support.length===data.length;let min=Infinity,max=-Infinity,minIndex=-1,maxIndex=-1,strongest=-Infinity,strongestIndex=-1,finiteSupportedCount=0;
    for(let i=0;i<data.length;i++){
      if(useSupport&&!support[i])continue;const value=Number(data[i]);if(!displaySemantics().extremaEligible(value,contract,true))continue;finiteSupportedCount++;
      if(value<min){min=value;minIndex=i;}if(value>max){max=value;maxIndex=i;}const magnitude=Math.abs(value);if(magnitude>strongest){strongest=magnitude;strongestIndex=i;}
    }
    if(!finiteSupportedCount)throw new Error('The focused feature overlay contains no threshold-eligible finite values inside its authoritative support.');
    const result={schema:'NMImagingExtremaSet',schemaVersion:1,contractVersion:'C18c2.12a',identity:key,measureId:text(overlay.meta&&overlay.meta.measureId),finiteSupportedCount,minimum:descriptor(runtime,overlay,minIndex,min,'minimum'),maximum:descriptor(runtime,overlay,maxIndex,max,'maximum'),strongestAbsolute:descriptor(runtime,overlay,strongestIndex,data[strongestIndex],'strongest_absolute')};
    cacheSet(key,result);return result;
  }
  function nativeIdentity(runtime,native,overlay,contract){return ['NMImagingExtrema:C18d4.7b:native',text(runtime&&runtime.payload&&runtime.payload.contentId),text(native&&native.gridId),text(native&&native.mappingId),text(overlay&&overlay.meta&&overlay.meta.measureId),text(runtime&&runtime.payload&&runtime.payload.selectedAtlas&&runtime.payload.selectedAtlas.atlasId),thresholdIdentity(contract)].join('|');}
  function nativeDescriptor(runtime,native,overlay,index,value,kind){
    if(!(index>=0))return null;
    const nativeVoxel=volumeIndexToVoxel1(native.dims,index),worldMm=voxelToWorld(native.spatialReference,nativeVoxel),displayVoxelFloat=worldToVoxel(runtime.payload&&runtime.payload.spatialReference,worldMm),displayVoxel=displayVoxelFloat.map(x=>Math.round(x));
    if(displayVoxel.some((x,i)=>!Number.isFinite(x)||x<1||x>runtime.dims[i]))throw new Error('The native feature extremum maps outside the active display grid.');
    const atlas=atlasAtVoxel(runtime,displayVoxel);
    return {schema:'NMImagingExtremumDescriptor',schemaVersion:1,contractVersion:'C18d4.7b',kind,measureId:text(overlay&&overlay.meta&&overlay.meta.measureId),linearIndex:index+1,nativeLinearIndex:index+1,nativeVoxel,voxel:displayVoxel,displayVoxelFloat,worldMm,value:Number(value),supportValid:true,sourceGrid:'native_feature_grid',atlasCode:atlas.code,atlasLabel:atlas.label,atlasStatus:atlas.status};
  }
  function computeNative(runtime,native,overlay,contract){
    if(!runtime||!native||!native.loaded||!overlay||!overlay.data)throw new Error('Native extrema require a hydrated authoritative feature source and focused overlay.');
    const key=nativeIdentity(runtime,native,overlay,contract);if(CACHE.has(key))return CACHE.get(key);
    const data=overlay.data,support=native.support||[],useSupport=support.length===data.length;let min=Infinity,max=-Infinity,minIndex=-1,maxIndex=-1,strongest=-Infinity,strongestIndex=-1,finiteSupportedCount=0;
    for(let i=0;i<data.length;i++){if(useSupport&&!support[i])continue;const value=Number(data[i]);if(!displaySemantics().extremaEligible(value,contract,true))continue;finiteSupportedCount++;if(value<min){min=value;minIndex=i;}if(value>max){max=value;maxIndex=i;}const magnitude=Math.abs(value);if(magnitude>strongest){strongest=magnitude;strongestIndex=i;}}
    if(!finiteSupportedCount)throw new Error('The focused native feature overlay contains no threshold-eligible finite values inside its authoritative support.');
    const result={schema:'NMImagingExtremaSet',schemaVersion:1,contractVersion:'C18d4.7b',identity:key,measureId:text(overlay.meta&&overlay.meta.measureId),sourceGrid:'native_feature_grid',finiteSupportedCount,minimum:nativeDescriptor(runtime,native,overlay,minIndex,min,'minimum'),maximum:nativeDescriptor(runtime,native,overlay,maxIndex,max,'maximum'),strongestAbsolute:nativeDescriptor(runtime,native,overlay,strongestIndex,data[strongestIndex],'strongest_absolute')};
    cacheSet(key,result);return result;
  }
  function selectNative(runtime,native,overlay,contract,kind){const set=computeNative(runtime,native,overlay,contract),k=text(kind).toLowerCase();if(k==='minimum'||k==='min')return set.minimum;if(k==='maximum'||k==='max')return set.maximum;if(k==='strongest_absolute'||k==='strongest'||k==='absolute')return set.strongestAbsolute;throw new Error('Unsupported extremum kind "'+kind+'".');}
  function select(runtime,overlay,contract,kind){const set=compute(runtime,overlay,contract),k=text(kind).toLowerCase();if(k==='minimum'||k==='min')return set.minimum;if(k==='maximum'||k==='max')return set.maximum;if(k==='strongest_absolute'||k==='strongest'||k==='absolute')return set.strongestAbsolute;throw new Error('Unsupported extremum kind "'+kind+'".');}
  function revealPlane(bounds,worldMm,marginMm){
    const b=bounds||{},lo=toArray(b.min).slice(0,3).map(Number),hi=toArray(b.max).slice(0,3).map(Number),p=toArray(worldMm).slice(0,3).map(Number),margin=Math.max(.05,finite(marginMm,.5));
    if(lo.length!==3||hi.length!==3||p.length!==3||lo.concat(hi,p).some(x=>!Number.isFinite(x)))throw new Error('A finite world-coordinate anatomy bound is required for extremum reveal.');
    const candidates=[];['x','y','z'].forEach((axis,i)=>{candidates.push({axis,index:i,distance:Math.abs(p[i]-lo[i]),keep:'positive',position:clamp(p[i]-margin,lo[i],hi[i])});candidates.push({axis,index:i,distance:Math.abs(hi[i]-p[i]),keep:'negative',position:clamp(p[i]+margin,lo[i],hi[i])});});candidates.sort((a,b)=>a.distance-b.distance||a.index-b.index||a.keep.localeCompare(b.keep));const first=candidates[0];return {mode:first.axis==='x'?'sagittal':(first.axis==='y'?'coronal':'axial'),axis:first.axis,positionWorldMm:p.map((v,i)=>i===first.index?first.position:v),keepX:first.axis==='x'?first.keep:'negative',keepY:first.axis==='y'?first.keep:'negative',keepZ:first.axis==='z'?first.keep:'positive',routeDistanceMm:first.distance};
  }
  function trihedralReveal(bounds,worldMm,marginMm){
    const b=bounds||{},lo=toArray(b.min).slice(0,3).map(Number),hi=toArray(b.max).slice(0,3).map(Number),p=toArray(worldMm).slice(0,3).map(Number),margin=Math.max(.05,finite(marginMm,.5)),keep=[],position=[];
    for(let i=0;i<3;i++){const nearMin=Math.abs(p[i]-lo[i])<=Math.abs(hi[i]-p[i]);keep[i]=nearMin?'positive':'negative';position[i]=clamp(p[i]+(nearMin?-margin:margin),lo[i],hi[i]);}
    return {mode:'trihedral',positionWorldMm:position,keepX:keep[0],keepY:keep[1],keepZ:keep[2]};
  }
  function clear(){CACHE.clear();}
  window.NMImagingExtrema={compute,select,computeNative,selectNative,identity,nativeIdentity,volumeIndexToVoxel1,voxelToWorld,worldToVoxel,revealPlane,trihedralReveal,clear,_test:{atlasAt,atlasAtVoxel,descriptor,nativeDescriptor,transformPoint}};
})();
