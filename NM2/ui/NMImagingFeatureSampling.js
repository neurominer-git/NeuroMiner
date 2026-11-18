(function(){
  'use strict';
  const {clamp,text,toArray}=globalThis.NMResultsViewerPrimitives;
  function volumeIndex(dims,i,j,k){return i+dims[0]*(j+dims[1]*k);}
  function inside(dims,i,j,k){return i>=0&&j>=0&&k>=0&&i<dims[0]&&j<dims[1]&&k<dims[2];}
  function displaySemantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api)throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');return api;}

  function classify(value,contract){return displaySemantics().classificationSign(value,contract,true);}

  function nativeDescriptor(runtime,data,voxel,contract){
    const dims=toArray(runtime&&runtime.dims).slice(0,3).map(Number);
    const point=toArray(voxel).slice(0,3).map(Number);
    const i=Math.round(point[0])-1,j=Math.round(point[1])-1,k=Math.round(point[2])-1;
    if(dims.length!==3||point.length!==3||!inside(dims,i,j,k))return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1};
    const index=volumeIndex(dims,i,j,k);
    const supported=!(runtime.support&&runtime.support.length===data.length)||!!runtime.support[index];
    const value=supported?Number(data[index]):NaN;
    const klass=supported?classify(value,contract):0;
    return {value,klass,displayKlass:klass,coverage:klass?1:0,supported,index,voxel:[i+1,j+1,k+1]};
  }

  function sampleVoxelFaithful(runtime,data,voxel,contract){
    return nativeDescriptor(runtime,data,voxel,contract);
  }

  function sampleSupportAwareLinear(runtime,data,voxel,contract){
    const dims=toArray(runtime&&runtime.dims).slice(0,3).map(Number),point=toArray(voxel).slice(0,3).map(Number);
    if(dims.length!==3||point.length!==3||point.some(x=>!Number.isFinite(x)))return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1,contributors:0};
    const p0=point.map(x=>x-1);if(p0.some((x,i)=>x<-.5||x>dims[i]-.5))return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1,contributors:0};const nearest=nativeDescriptor(runtime,data,voxel,contract),x=clamp(p0[0],0,dims[0]-1),y=clamp(p0[1],0,dims[1]-1),z=clamp(p0[2],0,dims[2]-1);
    const x0=Math.floor(x),y0=Math.floor(y),z0=Math.floor(z),x1=Math.min(x0+1,dims[0]-1),y1=Math.min(y0+1,dims[1]-1),z1=Math.min(z0+1,dims[2]-1),tx=x-x0,ty=y-y0,tz=z-z0;
    const support=runtime.support||[],useSupport=support.length===data.length,xs=[[x0,1-tx],[x1,tx]],ys=[[y0,1-ty],[y1,ty]],zs=[[z0,1-tz],[z1,tz]];
    const groups={"-1":{weight:0,sum:0,min:Infinity,max:-Infinity,count:0},"1":{weight:0,sum:0,min:Infinity,max:-Infinity,count:0}};
    for(const [i,wx] of xs)for(const [j,wy] of ys)for(const [k,wz] of zs){
      const weight=wx*wy*wz;if(!(weight>0))continue;const index=volumeIndex(dims,i,j,k);if(useSupport&&!support[index])continue;
      const value=Number(data[index]),klass=classify(value,contract);if(!Number.isFinite(value)||!klass)continue;const group=groups[String(klass)];group.weight+=weight;group.sum+=weight*value;group.min=Math.min(group.min,value);group.max=Math.max(group.max,value);group.count++;
    }
    let displayKlass=0,group=null;if(groups['-1'].weight>groups['1'].weight)displayKlass=-1;else if(groups['1'].weight>groups['-1'].weight)displayKlass=1;else if(groups['1'].weight>0||groups['-1'].weight>0)displayKlass=nearest.displayKlass||((Math.abs(groups['-1'].sum)>Math.abs(groups['1'].sum))?-1:1);
    if(displayKlass)group=groups[String(displayKlass)];const coverage=group?clamp(group.weight,0,1):0;
    if(!group||!(coverage>0)||!group.count)return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:nearest.index,contributors:0};
    const value=clamp(group.sum/group.weight,group.min,group.max),klass=coverage>=.5?displayKlass:0;
    return {value,klass,displayKlass,coverage,supported:klass!==0,index:nearest.index,contributors:group.count,localRange:[group.min,group.max]};
  }

  function sampleContinuousSignedTrilinear(runtime,data,voxel,contract){
    const dims=toArray(runtime&&runtime.dims).slice(0,3).map(Number),point=toArray(voxel).slice(0,3).map(Number);
    if(dims.length!==3||point.length!==3||point.some(x=>!Number.isFinite(x)))return {value:NaN,klass:0,displayKlass:0,coverage:0,supportCoverage:0,supported:false,index:-1,contributors:0};
    const p0=point.map(x=>x-1);if(p0.some((x,i)=>x<-.5||x>dims[i]-.5))return {value:NaN,klass:0,displayKlass:0,coverage:0,supportCoverage:0,supported:false,index:-1,contributors:0};
    const nearest=nativeDescriptor(runtime,data,voxel,contract);
    if(!nearest.supported||!Number.isFinite(nearest.value))return {value:NaN,klass:0,displayKlass:0,coverage:0,supportCoverage:0,supported:false,index:nearest.index,contributors:0};
    const x=clamp(p0[0],0,dims[0]-1),y=clamp(p0[1],0,dims[1]-1),z=clamp(p0[2],0,dims[2]-1),x0=Math.floor(x),y0=Math.floor(y),z0=Math.floor(z),x1=Math.min(x0+1,dims[0]-1),y1=Math.min(y0+1,dims[1]-1),z1=Math.min(z0+1,dims[2]-1),tx=x-x0,ty=y-y0,tz=z-z0;
    const support=runtime.support||[],useSupport=support.length===data.length,xs=[[x0,1-tx],[x1,tx]],ys=[[y0,1-ty],[y1,ty]],zs=[[z0,1-tz],[z1,tz]];let weight=0,sum=0,count=0;
    for(const [i,wx] of xs)for(const [j,wy] of ys)for(const [k,wz] of zs){
      const w=wx*wy*wz;if(!(w>0))continue;const index=volumeIndex(dims,i,j,k);if(useSupport&&!support[index])continue;const candidate=Number(data[index]);if(!Number.isFinite(candidate))continue;weight+=w;sum+=w*candidate;count++;
    }
    if(!(weight>0)||!count)return {value:NaN,klass:0,displayKlass:0,coverage:0,supportCoverage:0,supported:false,index:nearest.index,contributors:0};
    const value=sum/weight,klass=classify(value,contract);
    return {value,klass,displayKlass:klass,coverage:klass?1:0,supportCoverage:clamp(weight,0,1),supported:true,index:nearest.index,contributors:count,voxel:point.slice()};
  }

  function normalizeMode(value){return text(value).toLowerCase()==='support_aware_linear'?'support_aware_linear':'voxel_faithful';}
  function sample(runtime,data,voxel,contract,mode){return normalizeMode(mode)==='support_aware_linear'?sampleSupportAwareLinear(runtime,data,voxel,contract):sampleVoxelFaithful(runtime,data,voxel,contract);}

  /* Prepared native-grid sampler for high-volume consumers such as ROI aggregation.
   * This is the same sampling authority as sample(), with invariant dimensions,
   * support, threshold classifier and interpolation mode resolved once per series. */
  function prepareSampler(runtime,data,contract,mode){
    const dims=toArray(runtime&&runtime.dims).slice(0,3).map(Number);if(dims.length!==3||dims.some(x=>!Number.isFinite(x)||x<1))throw new Error('Prepared native feature sampling requires valid dimensions.');
    if(!data||typeof data.length!=='number')throw new Error('Prepared native feature sampling requires feature data.');
    const support=runtime&&runtime.support||[],useSupport=support.length===data.length,semantics=displaySemantics(),sign=typeof semantics.prepareClassificationSign==='function'?semantics.prepareClassificationSign(contract):(value=>semantics.classificationSign(value,contract,true)),normalized=normalizeMode(mode);
    const nearest=(x,y,z)=>{const i=Math.round(x)-1,j=Math.round(y)-1,k=Math.round(z)-1;if(!inside(dims,i,j,k))return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1};const index=volumeIndex(dims,i,j,k),supported=!useSupport||!!support[index],value=supported?Number(data[index]):NaN,klass=supported?sign(value):0;return {value,klass,displayKlass:klass,coverage:klass?1:0,supported,index};};
    if(normalized==='voxel_faithful')return voxel=>{const x=Number(voxel&&voxel[0]),y=Number(voxel&&voxel[1]),z=Number(voxel&&voxel[2]);if(![x,y,z].every(Number.isFinite))return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1};return nearest(x,y,z);};
    return voxel=>{
      const px=Number(voxel&&voxel[0])-1,py=Number(voxel&&voxel[1])-1,pz=Number(voxel&&voxel[2])-1;if(![px,py,pz].every(Number.isFinite)||px<-.5||py<-.5||pz<-.5||px>dims[0]-.5||py>dims[1]-.5||pz>dims[2]-.5)return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:-1,contributors:0};
      const n=nearest(px+1,py+1,pz+1),x=clamp(px,0,dims[0]-1),y=clamp(py,0,dims[1]-1),z=clamp(pz,0,dims[2]-1),x0=Math.floor(x),y0=Math.floor(y),z0=Math.floor(z),x1=Math.min(x0+1,dims[0]-1),y1=Math.min(y0+1,dims[1]-1),z1=Math.min(z0+1,dims[2]-1),tx=x-x0,ty=y-y0,tz=z-z0;
      let nw=0,ns=0,nmin=Infinity,nmax=-Infinity,nc=0,pw=0,ps=0,pmin=Infinity,pmax=-Infinity,pc=0;
      for(let ax=0;ax<2;ax++){const i=ax?x1:x0,wx=ax?tx:1-tx;for(let ay=0;ay<2;ay++){const j=ay?y1:y0,wy=ay?ty:1-ty;for(let az=0;az<2;az++){const k=az?z1:z0,wz=az?tz:1-tz,w=wx*wy*wz;if(!(w>0))continue;const index=volumeIndex(dims,i,j,k);if(useSupport&&!support[index])continue;const value=Number(data[index]);if(!Number.isFinite(value))continue;const klass=sign(value);if(klass<0){nw+=w;ns+=w*value;nmin=Math.min(nmin,value);nmax=Math.max(nmax,value);nc++;}else if(klass>0){pw+=w;ps+=w*value;pmin=Math.min(pmin,value);pmax=Math.max(pmax,value);pc++;}}}}
      let displayKlass=0;if(nw>pw)displayKlass=-1;else if(pw>nw)displayKlass=1;else if(pw>0||nw>0)displayKlass=n.displayKlass||((Math.abs(ns)>Math.abs(ps))?-1:1);const weight=displayKlass<0?nw:pw,sum=displayKlass<0?ns:ps,min=displayKlass<0?nmin:pmin,max=displayKlass<0?nmax:pmax,count=displayKlass<0?nc:pc,coverage=clamp(weight,0,1);
      if(!displayKlass||!(coverage>0)||!count)return {value:NaN,klass:0,displayKlass:0,coverage:0,supported:false,index:n.index,contributors:0};const value=clamp(sum/weight,min,max),klass=coverage>=.5?displayKlass:0;return {value,klass,displayKlass,coverage,supported:klass!==0,index:n.index,contributors:count,localRange:[min,max]};
    };
  }
  const SURFACE_MODES=['continuous_signed_trilinear','audit_voxel_faithful','audit_threshold_first_support_aware'];
  function normalizeSurfaceMode(value){const mode=text(value).toLowerCase();if(!mode)return 'continuous_signed_trilinear';if(!SURFACE_MODES.includes(mode))throw new Error(`Unsupported surface feature sampling mode: ${text(value)}`);return mode;}
  function sampleSurface(runtime,data,voxel,contract,mode){
    const normalized=normalizeSurfaceMode(mode);
    if(normalized==='continuous_signed_trilinear')return sampleContinuousSignedTrilinear(runtime,data,voxel,contract);
    if(normalized==='audit_threshold_first_support_aware')return sampleSupportAwareLinear(runtime,data,voxel,contract);
    return sampleVoxelFaithful(runtime,data,voxel,contract);
  }

  function flattenMatrix(value){
    const out=[];
    (function walk(v){if(Array.isArray(v)||ArrayBuffer.isView(v)){for(const x of Array.from(v))walk(x);}else out.push(Number(v));})(value);
    return out;
  }
  function matrix4(value,label){
    const matrix=flattenMatrix(value);
    if(matrix.length!==16||matrix.some(x=>!Number.isFinite(x)))throw new Error(`${label||'Matrix'} must contain 16 finite values.`);
    return matrix;
  }
  function multiplyMatrix4(a,b){
    a=matrix4(a,'Left matrix');b=matrix4(b,'Right matrix');
    const out=new Array(16).fill(0);
    for(let row=0;row<4;row++)for(let col=0;col<4;col++)for(let k=0;k<4;k++)out[row*4+col]+=a[row*4+k]*b[k*4+col];
    return out;
  }
  function transformPoint(matrix,point){
    const m=matrix4(matrix,'Transform matrix'),p=toArray(point).slice(0,3).map(Number);
    if(p.length!==3||p.some(x=>!Number.isFinite(x)))return [NaN,NaN,NaN];
    const x=p[0],y=p[1],z=p[2];
    const q=[m[0]*x+m[1]*y+m[2]*z+m[3],m[4]*x+m[5]*y+m[6]*z+m[7],m[8]*x+m[9]*y+m[10]*z+m[11],m[12]*x+m[13]*y+m[14]*z+m[15]];
    if(!Number.isFinite(q[3])||Math.abs(q[3])<Number.EPSILON)return [NaN,NaN,NaN];
    return [q[0]/q[3],q[1]/q[3],q[2]/q[3]];
  }
  function rowMajorToColumnMajor4(matrix){
    const m=matrix4(matrix,'Transform matrix'),out=new Float32Array(16);
    for(let row=0;row<4;row++)for(let col=0;col<4;col++)out[col*4+row]=m[row*4+col];
    return out;
  }
  function displayToNativeVoxelMatrix(displaySpatialReference,nativeRuntime){
    const display=displaySpatialReference||{},native=nativeRuntime||{};
    const voxel1ToWorld=matrix4(display.affineVoxel1ToWorld,'Display voxel-to-world affine');
    const worldToNative=matrix4(native.worldToFeatureVoxel||(native.spatialReference&&native.spatialReference.affineWorldToVoxel),'Native world-to-voxel affine');
    return multiplyMatrix4(worldToNative,voxel1ToWorld);
  }
  function displayVoxel0ToNativeVoxel1(matrix,displayVoxel0){
    const point=toArray(displayVoxel0).slice(0,3).map(Number);
    if(point.length!==3||point.some(x=>!Number.isFinite(x)))return [NaN,NaN,NaN];
    return transformPoint(matrix,[point[0]+1,point[1]+1,point[2]+1]);
  }

  function materializeNearestLabels(displayDimensions,displaySpatialReference,nativeRuntime,nativeLabels){
    const displayDims=nativeDimensions(displayDimensions),nativeDims=nativeDimensions(nativeRuntime&&nativeRuntime.dims),nativeCount=nativeDims[0]*nativeDims[1]*nativeDims[2];
    if(!nativeLabels||nativeLabels.length!==nativeCount)throw new Error('Native atlas label data do not match the authoritative native grid.');
    const m=displayToNativeVoxelMatrix(displaySpatialReference,nativeRuntime),out=new Uint32Array(displayDims[0]*displayDims[1]*displayDims[2]),nativeX=nativeDims[0],nativeY=nativeDims[1],nativeZ=nativeDims[2];
    let targetIndex=0;
    for(let k=1;k<=displayDims[2];k++){
      const kx=m[2]*k+m[3],ky=m[6]*k+m[7],kz=m[10]*k+m[11];
      for(let j=1;j<=displayDims[1];j++){
        let x=m[0]+m[1]*j+kx,y=m[4]+m[5]*j+ky,z=m[8]+m[9]*j+kz;
        for(let i=1;i<=displayDims[0];i++,targetIndex++,x+=m[0],y+=m[4],z+=m[8]){
          if(x<1||y<1||z<1||x>nativeX||y>nativeY||z>nativeZ)continue;
          const ni=Math.floor(x+.5)-1,nj=Math.floor(y+.5)-1,nk=Math.floor(z+.5)-1;
          out[targetIndex]=Number(nativeLabels[ni+nativeX*(nj+nativeY*nk)])>>>0;
        }
      }
    }
    return out;
  }

  function nativeDimensions(value){
    const dims=toArray(value).slice(0,3).map(Number);
    if(dims.length!==3||dims.some(x=>!Number.isFinite(x)||x<1||Math.round(x)!==x))throw new Error('Native feature dimensions must contain three positive integers.');
    return dims;
  }

  function validateNativeFeatureSamplingPayload(payload,displayOverlays){
    const p=payload||{};if(!p.available)return null;
    if(text(p.schema)!=='NMImagingNativeFeatureSamplingPayload'||Number(p.schemaVersion)!==1||text(p.contractVersion)!=='C18d4.7a')throw new Error('Unsupported native feature sampling payload.');
    const dims=nativeDimensions(p.dimensions),n=dims[0]*dims[1]*dims[2],gridId=text(p.gridId),mappingId=text(p.mappingId),ref=p.spatialReference||{};
    const storageEncoding=text(p.storageEncoding);
    if(!gridId||!mappingId)throw new Error('Native feature sampling payload is missing grid or mapping identity.');
    if(!['dense_grid_v1','indexed_lookup_v1'].includes(storageEncoding))throw new Error('Native feature sampling storage encoding is unsupported.');
    if(text(p.coordinateConvention)!=='spm_one_based_direct'||text(ref.coordinateConvention)!=='spm_one_based_direct')throw new Error('Native feature sampling requires spm_one_based_direct coordinates.');
    const refDims=nativeDimensions(ref.dimensions);if(refDims.some((x,i)=>x!==dims[i])||text(ref.gridId)!==gridId)throw new Error('Native feature dimensions and spatial-reference identity disagree.');
    const w2v=flattenMatrix(p.worldToFeatureVoxel),v2w=flattenMatrix(p.featureVoxelToWorld),rw2v=flattenMatrix(ref.affineWorldToVoxel),rv2w=flattenMatrix(ref.affineVoxel1ToWorld);
    if(w2v.length!==16||v2w.length!==16||rw2v.length!==16||rv2w.length!==16)throw new Error('Native feature affine transforms must be 4-by-4 matrices.');
    const maxError=(a,b)=>Math.max(...a.map((x,i)=>Math.abs(x-b[i])));if(maxError(w2v,rw2v)>1e-10||maxError(v2w,rv2w)>1e-10)throw new Error('Explicit native feature transforms disagree with the spatial reference.');
    const support=p.support||{};if(text(support.dataType)!=='uint8'||Number(support.elementCount)!==n||!text(support.contentHash))throw new Error('Native feature support asset metadata are invalid.');
    const overlays=toArray(p.overlays),ids=overlays.map(x=>text(x&&x.measureId));if(!overlays.length||ids.some(x=>!x)||new Set(ids).size!==ids.length)throw new Error('Native feature overlays require unique nonempty measure IDs.');
    let indexedLookup=null;
    if(storageEncoding==='dense_grid_v1'){
      for(const overlay of overlays){if(text(overlay.dataType)!=='float32'||Number(overlay.elementCount)!==n||!text(overlay.contentHash))throw new Error(`Native feature overlay metadata are invalid for ${text(overlay.measureId)||'an unnamed measure'}.`);}
    }else{
      indexedLookup=p.indexedLookup;const lookupType=text(indexedLookup.dataType),valueCount=Number(indexedLookup.valueCount),unsupportedIndex=Number(indexedLookup.unsupportedIndex),firstValueIndex=Number(indexedLookup.firstValueIndex);
      if(!['uint8','uint16','uint32'].includes(lookupType)||Number(indexedLookup.elementCount)!==n||!text(indexedLookup.url)||!text(indexedLookup.contentHash)||!Number.isInteger(valueCount)||valueCount<1||unsupportedIndex!==1||firstValueIndex!==2)throw new Error('Indexed native feature lookup metadata are invalid.');
      for(const overlay of overlays){const values=toArray(overlay.compactValues),finite=toArray(overlay.compactFinite);if(text(overlay.dataType)!=='float32'||Number(overlay.elementCount)!==n||!text(overlay.contentHash)||values.length!==valueCount||finite.length!==valueCount)throw new Error(`Indexed native feature overlay metadata are invalid for ${text(overlay.measureId)||'an unnamed measure'}.`);}
    }
    const displayIds=toArray(displayOverlays).map(x=>text(x&&x.measureId)).filter(Boolean);if(displayIds.length&&(displayIds.length!==ids.length||displayIds.some(id=>!ids.includes(id))))throw new Error('Native feature measures do not match the displayed overlay set.');
    const semantics=p.samplingSemantics||{};if(text(semantics.sourceAuthority)!=='native_feature_grid'||text(semantics.thresholdEvaluation)!=='after_native_grid_sampling'||text(semantics.outsideSupport)!=='invalid_transparent')throw new Error('Native feature sampling semantics are incomplete or incompatible.');
    return {descriptor:p,dims,n,gridId,mappingId,storageEncoding,indexedLookup,spatialReference:ref,worldToFeatureVoxel:w2v,featureVoxelToWorld:v2w,measureIds:ids.slice()};
  }

  function prepareNativeFeatureSampling(payload,displayOverlays){
    const checked=validateNativeFeatureSamplingPayload(payload,displayOverlays);if(!checked)return null;
    const runtime={...checked,loaded:false,support:null,overlays:{},lookup:null,_promise:null};
    const contentIdentity=meta=>text(meta&&(meta.contentHash||meta.dataHash||meta.hash||meta.cacheKey));
    /* Reuse only content-addressed native-grid arrays on an identical grid and
     * mapping. Missing hashes intentionally disable reuse rather than guessing. */
    runtime.reuseFrom=function(previous){
      if(!previous||previous.gridId!==runtime.gridId||previous.mappingId!==runtime.mappingId||toArray(previous.dims).join('x')!==runtime.dims.join('x'))return {support:false,overlays:0};
      const descriptor=runtime.descriptor,previousDescriptor=previous.descriptor||{},supportIdentity=contentIdentity(descriptor.support),previousSupportIdentity=contentIdentity(previousDescriptor.support);let supportReused=false,overlaysReused=0;
      if(previous.support&&previous.support.length===runtime.n&&supportIdentity&&supportIdentity===previousSupportIdentity){runtime.support=previous.support;supportReused=true;}
      if(runtime.storageEncoding==='indexed_lookup_v1'&&previous.storageEncoding==='indexed_lookup_v1'&&previous.lookup&&previous.lookup.length===runtime.n&&contentIdentity(runtime.indexedLookup)===contentIdentity(previous.indexedLookup))runtime.lookup=previous.lookup;
      for(const meta of toArray(descriptor.overlays)){
        const id=text(meta.measureId),prior=previous.overlays&&previous.overlays[id],priorMeta=prior&&prior.meta||toArray(previousDescriptor.overlays).find(item=>text(item&&item.measureId)===id);if(!prior||!prior.data||prior.data.length!==runtime.n)continue;
        const identity=contentIdentity(meta),priorIdentity=contentIdentity(priorMeta);if(identity&&identity===priorIdentity){runtime.overlays[id]={meta,data:prior.data};overlaysReused++;}
      }
      runtime.loaded=!!runtime.support&&toArray(descriptor.overlays).every(meta=>runtime.overlays[text(meta.measureId)]&&runtime.overlays[text(meta.measureId)].data);return {support:supportReused,overlays:overlaysReused,loaded:runtime.loaded};
    };
    runtime.reuseDisplayOverlays=function(displayOverlays){
      let overlaysReused=0;const display=displayOverlays||{};
      for(const meta of toArray(runtime.descriptor&&runtime.descriptor.overlays)){
        const id=text(meta.measureId),candidate=display[id];if(!candidate||!candidate.data||candidate.data.length!==runtime.n)continue;
        const identity=contentIdentity(meta),displayIdentity=contentIdentity(candidate.meta);
        if(identity&&identity===displayIdentity){runtime.overlays[id]={meta,data:candidate.data};overlaysReused++;}
      }
      runtime.loaded=!!runtime.support&&toArray(runtime.descriptor.overlays).every(meta=>runtime.overlays[text(meta.measureId)]&&runtime.overlays[text(meta.measureId)].data);
      return {overlays:overlaysReused,loaded:runtime.loaded};
    };
    runtime.load=function(fetchArray){
      if(runtime.loaded)return Promise.resolve(runtime);
      if(runtime._promise)return runtime._promise;
      if(typeof fetchArray!=='function')return Promise.reject(new Error('Native feature hydration requires a binary-array fetch function.'));
      runtime._promise=(async()=>{
        const descriptor=runtime.descriptor,overlayMeta=toArray(descriptor.overlays);
        if(runtime.storageEncoding==='indexed_lookup_v1'){
          const lookupMeta=runtime.indexedLookup,lookup=runtime.lookup||await fetchArray(lookupMeta.url,lookupMeta.dataType,runtime.n);if(!lookup||lookup.length!==runtime.n)throw new Error('Hydrated indexed native feature lookup length is invalid.');runtime.lookup=lookup;
          const missing=overlayMeta.filter(meta=>{const prior=runtime.overlays[text(meta.measureId)];return !(prior&&prior.data&&prior.data.length===runtime.n);});
          if(!runtime.support||missing.length){const support=runtime.support||new Uint8Array(runtime.n),records=missing.map(meta=>({meta,data:new Float32Array(runtime.n),values:toArray(meta.compactValues),finite:toArray(meta.compactFinite)}));for(let ii=0;ii<runtime.n;ii++){const lookupValue=Number(lookup[ii]),inside=lookupValue>=2;if(!runtime.support)support[ii]=inside?1:0;for(const record of records){const valueIndex=lookupValue-2;record.data[ii]=inside&&record.finite[valueIndex]?Number(record.values[valueIndex]):NaN;}}runtime.support=support;for(const record of records)runtime.overlays[text(record.meta.measureId)]={meta:record.meta,data:record.data};}
        }else{
          const supportMeta=descriptor.support,supportPromise=runtime.support?Promise.resolve(runtime.support):(text(supportMeta.url)?fetchArray(supportMeta.url,'uint8',runtime.n):Promise.reject(new Error('Native feature support URL is unavailable.')));
          const overlayPromises=overlayMeta.map(meta=>{const id=text(meta.measureId),prior=runtime.overlays[id];if(prior&&prior.data&&prior.data.length===runtime.n)return Promise.resolve({id,meta,data:prior.data});if(!text(meta.url))return Promise.reject(new Error(`Native feature overlay URL is unavailable for ${id}.`));return fetchArray(meta.url,'float32',runtime.n).then(data=>({id,meta,data}));});
          const [support,records]=await Promise.all([supportPromise,Promise.all(overlayPromises)]);if(!support||support.length!==runtime.n)throw new Error('Hydrated native feature support length is invalid.');runtime.support=support;for(const record of records){if(!record.data||record.data.length!==runtime.n)throw new Error(`Hydrated native feature overlay length is invalid for ${record.id}.`);runtime.overlays[record.id]={meta:record.meta,data:record.data};}
        }
        runtime.loaded=!!runtime.support&&overlayMeta.every(meta=>runtime.overlays[text(meta.measureId)]&&runtime.overlays[text(meta.measureId)].data);if(!runtime.loaded)throw new Error('Native feature hydration did not produce all requested arrays.');return runtime;
      })().catch(err=>{runtime._promise=null;throw err;});
      return runtime._promise;
    };
    runtime.overlay=function(measureId){return runtime.overlays[text(measureId)]||null;};
    return runtime;
  }


  window.NMImagingFeatureSampling={
    classify,nativeDescriptor,sampleVoxelFaithful,sampleSupportAwareLinear,sampleContinuousSignedTrilinear,sample,prepareSampler,sampleSurface,normalizeMode,normalizeSurfaceMode,
    validateNativeFeatureSamplingPayload,prepareNativeFeatureSampling,
    matrix4,multiplyMatrix4,transformPoint,rowMajorToColumnMajor4,displayToNativeVoxelMatrix,displayVoxel0ToNativeVoxel1,materializeNearestLabels,
    _test:{volumeIndex,inside,flattenMatrix,nativeDimensions}
  };
})();
