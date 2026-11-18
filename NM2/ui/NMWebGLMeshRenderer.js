(function(){
  'use strict';

  const {clamp,nowMs}=globalThis.NMResultsViewerPrimitives;
  const EPS=1e-8;
  const RAYCAST_PREPARED_CACHE=new Map();
  const RAYCAST_PREPARED_CACHE_LIMIT=2;
  const MAX_ELEVATION_RAD=89.5*Math.PI/180;
  function finite(v,d){const n=Number(v);return Number.isFinite(n)?n:d;}
  const PRESENTATION_UNPREMULTIPLY_LUT=(()=>{const lut=new Uint8Array(65536);for(let alpha=1;alpha<255;alpha++)for(let channel=0;channel<256;channel++)lut[(alpha<<8)|channel]=Math.min(255,Math.round(channel*255/alpha));for(let channel=0;channel<256;channel++)lut[(255<<8)|channel]=channel;return lut;})();
  function unpremultiplyPresentationRgba8(data){
    if(!(data instanceof Uint8Array)&&!(data instanceof Uint8ClampedArray))throw new Error('RGBA presentation data must be an 8-bit typed array.');
    if(data.length%4!==0)throw new Error('RGBA presentation data length must be divisible by four.');
    for(let i=0;i<data.length;i+=4){const offset=data[i+3]<<8;data[i]=PRESENTATION_UNPREMULTIPLY_LUT[offset|data[i]];data[i+1]=PRESENTATION_UNPREMULTIPLY_LUT[offset|data[i+1]];data[i+2]=PRESENTATION_UNPREMULTIPLY_LUT[offset|data[i+2]];}
    return data;
  }
  function vec3(v,d){const a=Array.isArray(v)||ArrayBuffer.isView(v)?Array.from(v):[];return [finite(a[0],d&&d[0]||0),finite(a[1],d&&d[1]||0),finite(a[2],d&&d[2]||0)];}
  function add(a,b){return [a[0]+b[0],a[1]+b[1],a[2]+b[2]];}
  function sub(a,b){return [a[0]-b[0],a[1]-b[1],a[2]-b[2]];}
  function scale(a,s){return [a[0]*s,a[1]*s,a[2]*s];}
  function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
  function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
  function norm(a){return Math.sqrt(dot(a,a));}
  function normalize(a,fallback){const n=norm(a);return n>EPS?scale(a,1/n):vec3(fallback||[0,0,1]);}
  function wrapRadians(v){let x=finite(v,0);while(x>Math.PI)x-=2*Math.PI;while(x<=-Math.PI)x+=2*Math.PI;return x;}
  function displaySemantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api||typeof api.assertDisplayContract!=='function')throw new Error('The canonical Results Viewer display-contract assertion authority is unavailable.');return api;}
  function volumePrep(){const api=window.NMImagingVolumePrep;if(!api)throw new Error('The canonical imaging volume-preparation authority is unavailable.');return api;}
  function volumeRaycastGL2(){const api=window.NMVolumeRaycastGL2;if(!api)throw new Error('The canonical WebGL2 volume-raycast authority is unavailable.');return api;}
  function volumePrepClient(){const api=window.NMImagingVolumePrepClient;if(!api||typeof api.create!=='function')throw new Error('The canonical imaging volume-preparation client is unavailable.');return api;}
  function colorGradient(){const api=window.NMImagingColorGradient;if(!api||typeof api.lutRgba8!=='function')throw new Error('The canonical imaging colour-gradient authority is unavailable.');return api;}

  function quatNormalize(q){const a=Array.from(q||[0,0,0,1]).slice(0,4).map(Number),n=Math.hypot(a[0],a[1],a[2],a[3]);return n>EPS?a.map(x=>x/n):[0,0,0,1];}
  function quatMultiply(a,b){a=quatNormalize(a);b=quatNormalize(b);return quatNormalize([
    a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],
    a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],
    a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],
    a[3]*b[3]-a[0]*b[0]-a[1]*b[1]-a[2]*b[2]
  ]);}
  function quatAxisAngle(axis,angle){axis=normalize(axis,[0,0,1]);const s=Math.sin(angle/2);return quatNormalize([axis[0]*s,axis[1]*s,axis[2]*s,Math.cos(angle/2)]);}
  function quatRotate(q,v){q=quatNormalize(q);const u=[q[0],q[1],q[2]],s=q[3],uv=cross(u,v),uuv=cross(u,uv);return add(v,add(scale(uv,2*s),scale(uuv,2)));}
  function quaternionFromTurntable(azimuthRad,elevationRad){
    const yaw=quatAxisAngle([0,0,1],-azimuthRad);
    const right=[Math.cos(azimuthRad),-Math.sin(azimuthRad),0];
    const pitch=quatAxisAngle(right,-elevationRad);
    return quatMultiply(pitch,yaw);
  }
  function turntableAnglesFromQuaternion(q){
    const offset=normalize(quatRotate(q,[0,-1,0]),[0,-1,0]);
    const elevation=Math.asin(clamp(offset[2],-1,1));
    const azimuth=Math.atan2(-offset[0],-offset[1]);
    return {azimuthRad:wrapRadians(azimuth),elevationRad:clamp(elevation,-MAX_ELEVATION_RAD,MAX_ELEVATION_RAD)};
  }
  function turntableBasis(azimuthRad,elevationRad){
    const az=wrapRadians(azimuthRad),el=clamp(elevationRad,-MAX_ELEVATION_RAD,MAX_ELEVATION_RAD),ce=Math.cos(el);
    const offset=[-Math.sin(az)*ce,-Math.cos(az)*ce,Math.sin(el)];
    const forward=normalize(scale(offset,-1),[0,1,0]);
    const right=normalize([Math.cos(az),-Math.sin(az),0],[1,0,0]);
    const up=normalize(cross(right,forward),[0,0,1]);
    return {offset,forward,right,up};
  }

  function resolveLightDirection(lighting,basis){
    const cfg=lighting&&typeof lighting==='object'?lighting:{},direction=normalize(vec3(cfg.lightDirection,[.35,.5,.78]),[.35,.5,.78]);
    if(cfg.space!=='camera'||!basis)return direction;
    const right=normalize(vec3(basis.right,[1,0,0]),[1,0,0]),up=normalize(vec3(basis.up,[0,0,1]),[0,0,1]),towardCamera=normalize(vec3(basis.offset,basis.forward?scale(basis.forward,-1):[0,-1,0]),[0,-1,0]);
    return normalize(add(add(scale(right,direction[0]),scale(up,direction[1])),scale(towardCamera,direction[2])),towardCamera);
  }

  function mat4Identity(){const o=new Float32Array(16);o[0]=o[5]=o[10]=o[15]=1;return o;}
  function mat4Multiply(a,b){const o=new Float32Array(16);for(let c=0;c<4;c+=1)for(let r=0;r<4;r+=1)o[c*4+r]=a[r]*b[c*4]+a[4+r]*b[c*4+1]+a[8+r]*b[c*4+2]+a[12+r]*b[c*4+3];return o;}
  function mat4Perspective(fovy,aspect,near,far){const f=1/Math.tan(fovy/2),o=new Float32Array(16);o[0]=f/Math.max(aspect,EPS);o[5]=f;o[10]=(far+near)/(near-far);o[11]=-1;o[14]=(2*far*near)/(near-far);return o;}
  function mat4Ortho(left,right,bottom,top,near,far){const o=mat4Identity();o[0]=2/(right-left);o[5]=2/(top-bottom);o[10]=-2/(far-near);o[12]=-(right+left)/(right-left);o[13]=-(top+bottom)/(top-bottom);o[14]=-(far+near)/(far-near);return o;}
  function mat4LookAt(eye,target,up){const z=normalize(sub(eye,target),[0,1,0]),x=normalize(cross(up,z),[1,0,0]),y=cross(z,x),o=mat4Identity();o[0]=x[0];o[1]=y[0];o[2]=z[0];o[4]=x[1];o[5]=y[1];o[6]=z[1];o[8]=x[2];o[9]=y[2];o[10]=z[2];o[12]=-dot(x,eye);o[13]=-dot(y,eye);o[14]=-dot(z,eye);return o;}

  function boundsFromVertices(vertices){let lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];for(let i=0;i<vertices.length;i+=3){for(let a=0;a<3;a+=1){const v=Number(vertices[i+a]);if(Number.isFinite(v)){lo[a]=Math.min(lo[a],v);hi[a]=Math.max(hi[a],v);}}}if(lo.some(x=>!Number.isFinite(x))||hi.some(x=>!Number.isFinite(x)))throw new Error('Mesh vertices contain no finite 3-D bounds.');const center=lo.map((x,i)=>(x+hi[i])/2),radius=Math.max(EPS,norm(sub(hi,lo))/2);return {min:lo,max:hi,center,radius};}
  function mergeBounds(bounds){const list=(bounds||[]).filter(Boolean);if(!list.length)return {min:[-1,-1,-1],max:[1,1,1],center:[0,0,0],radius:Math.sqrt(3)};const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];list.forEach(b=>{for(let i=0;i<3;i+=1){lo[i]=Math.min(lo[i],b.min[i]);hi[i]=Math.max(hi[i],b.max[i]);}});return boundsFromVertices(new Float32Array([lo[0],lo[1],lo[2],hi[0],hi[1],hi[2]]));}
  function maxIndex(indices){let out=0;for(let i=0;i<indices.length;i+=1){const value=Number(indices[i]);if(value>out)out=value;}return out;}
  function computeNormals(vertices,indices){const out=new Float32Array(vertices.length);for(let i=0;i<indices.length;i+=3){const ia=indices[i]*3,ib=indices[i+1]*3,ic=indices[i+2]*3;if(ic+2>=vertices.length)continue;const a=[vertices[ia],vertices[ia+1],vertices[ia+2]],b=[vertices[ib],vertices[ib+1],vertices[ib+2]],c=[vertices[ic],vertices[ic+1],vertices[ic+2]],n=cross(sub(b,a),sub(c,a));[ia,ib,ic].forEach(j=>{out[j]+=n[0];out[j+1]+=n[1];out[j+2]+=n[2];});}for(let i=0;i<out.length;i+=3){const n=normalize([out[i],out[i+1],out[i+2]],[0,0,1]);out[i]=n[0];out[i+1]=n[1];out[i+2]=n[2];}return out;}


  function projectionExecutionParameters(contract,colorMode){
    const requiresDisplay=colorMode===5||colorMode===8||colorMode===9||colorMode===11;
    if(!requiresDisplay)return {contract:null,thresholdMode:0,thresholdLow:-3.402823466e38,thresholdHigh:3.402823466e38,thresholdValue:0,displayRange:[0,1],colorStops:null};
    displaySemantics().assertDisplayContract(contract,{consumer:'NMWebGLMeshRenderer feature rendering',message:'Feature rendering requires a canonical display contract.',facets:['threshold','shownRange','colorStops']});
    const thresholdMode=displaySemantics().thresholdModeCode(contract.threshold.mode),displayRange=[Number(contract.shownRange.lower),Number(contract.shownRange.upper)];
    if(displayRange.some(value=>!Number.isFinite(value))||displayRange[1]<displayRange[0])throw new Error('Canonical display range is invalid.');
    let thresholdLow=-3.402823466e38,thresholdHigh=3.402823466e38,thresholdValue=0;
    if(thresholdMode===1){thresholdLow=Number(contract.threshold.lower);thresholdHigh=Number(contract.threshold.upper);if(!Number.isFinite(thresholdLow)||!Number.isFinite(thresholdHigh)||!(thresholdLow<thresholdHigh))throw new Error('Canonical outside-interval threshold is invalid.');}
    else if(thresholdMode>=2){thresholdValue=Number(contract.threshold.value);if(!Number.isFinite(thresholdValue)||(thresholdMode===2&&thresholdValue<0))throw new Error('Canonical single threshold is invalid.');}
    return {contract,thresholdMode,thresholdLow,thresholdHigh,thresholdValue,displayRange,colorStops:contract.colorStops.map(stop=>({position:Number(stop.position),color:String(stop.color)}))};
  }
  function featureInterpolationCode(mode){if(Number.isFinite(Number(mode))&&String(mode).trim()!=='')return clamp(Math.round(Number(mode)),0,1);return String(mode||'').toLowerCase()==='support_aware_linear'?1:0;}
  function surfaceFeatureSamplingCode(mode){
    if(mode===null||mode===undefined||String(mode).trim()==='')return 2;
    if(Number.isFinite(Number(mode))){const code=Math.round(Number(mode));if(code>=0&&code<=2)return code;throw new Error(`Unknown surface feature sampling code: ${mode}`);}
    const value=String(mode).toLowerCase();if(value==='continuous_signed_trilinear')return 2;if(value==='audit_voxel_faithful')return 0;if(value==='audit_threshold_first_support_aware')return 1;throw new Error(`Unknown surface feature sampling mode: ${mode}`);
  }
  function projectionAlphaModeCode(mode){if(mode===null||mode===undefined||String(mode).trim()==='')return 0;if(Number.isFinite(Number(mode))){const code=Math.round(Number(mode));if(code>=0&&code<=1)return code;throw new Error(`Unknown surface projection alpha code: ${mode}`);}const value=String(mode).toLowerCase();if(value==='uniform')return 0;if(value==='threshold_free_local_support')return 1;throw new Error(`Unknown surface projection alpha mode: ${mode}`);}
  function projectionAlphaTransfer(value,selectivity,midpoint,logCompression){const raw=clamp(finite(value,0),0,1),lambda=Math.max(0,finite(logCompression,9)),u=lambda>1e-9?Math.log1p(lambda*raw)/Math.log1p(lambda):raw,k=clamp(finite(selectivity,24),4,48),m=clamp(finite(midpoint,.12),.02,.5),sigmoid=x=>1/(1+Math.exp(-x)),lo=sigmoid(-k*m),hi=sigmoid(k*(1-m)),den=Math.max(1e-12,hi-lo);return clamp((sigmoid(k*(u-m))-lo)/den,0,1);}
  function projectionDiagnosticModeCode(mode){if(Number.isFinite(Number(mode))&&String(mode).trim()!=='')return clamp(Math.round(Number(mode)),0,7);const value=String(mode||'').toLowerCase();if(value==='depth_class')return 1;if(value==='source_voxel_x')return 2;if(value==='source_voxel_y')return 3;if(value==='source_voxel_z')return 4;if(value==='projected_value')return 5;if(value==='path_flags')return 6;if(value==='projection_alpha')return 7;return 0;}
  function rayFeatureModeCode(mode){if(Number.isFinite(Number(mode))&&String(mode).trim()!=='')return clamp(Math.round(Number(mode)),0,1);return String(mode||'').toLowerCase()==='depth_peak_audit'?1:0;}
  function projectionPixelContinuity(depthMm,classCode,activeMask,width,height,jumpThresholdMm){
    const w=Math.max(1,Math.floor(finite(width,0))),h=Math.max(1,Math.floor(finite(height,0))),n=w*h,threshold=Math.max(0,finite(jumpThresholdMm,0));
    if(!depthMm||depthMm.length!==n||!classCode||classCode.length!==n||!activeMask||activeMask.length!==n)throw new Error('Projection diagnostic arrays do not match their pixel dimensions.');
    let activePixels=0,adjacentActivePairs=0,depthJumpPairs=0,signSwitchPairs=0,maxDepthJumpMm=0;const jumps=[];
    for(let i=0;i<n;i++)if(activeMask[i])activePixels++;
    function edge(a,b){if(!activeMask[a]||!activeMask[b])return;adjacentActivePairs++;const delta=Math.abs(Number(depthMm[a])-Number(depthMm[b]));if(Number.isFinite(delta)){jumps.push(delta);maxDepthJumpMm=Math.max(maxDepthJumpMm,delta);if(delta>threshold)depthJumpPairs++;}if(classCode[a]&&classCode[b]&&classCode[a]!==classCode[b])signSwitchPairs++;}
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x;if(x+1<w)edge(i,i+1);if(y+1<h)edge(i,i+w);}
    jumps.sort((a,b)=>a-b);const p95=jumps.length?jumps[Math.min(jumps.length-1,Math.ceil(.95*jumps.length)-1)]:0;
    return {activePixels,adjacentActivePairs,depthJumpThresholdMm:threshold,depthJumpPairs,depthJumpFraction:adjacentActivePairs?depthJumpPairs/adjacentActivePairs:0,signSwitchPairs,signSwitchFraction:adjacentActivePairs?signSwitchPairs/adjacentActivePairs:0,maxDepthJumpMm,p95DepthJumpMm:p95};
  }
  function projectionPixelMaps(depthMm,classCode,activeMask,width,height){
    const w=Math.max(1,Math.floor(finite(width,0))),h=Math.max(1,Math.floor(finite(height,0))),n=w*h;
    if(!depthMm||depthMm.length!==n||!classCode||classCode.length!==n||!activeMask||activeMask.length!==n)throw new Error('Projection diagnostic arrays do not match their pixel dimensions.');
    const localDepthJumpMm=new Float32Array(n),signSwitchMask=new Uint8Array(n);localDepthJumpMm.fill(NaN);
    for(let y=0;y<h;y++)for(let x=0;x<w;x++){
      const i=y*w+x;if(!activeMask[i])continue;let maxJump=0,hasNeighbour=false,signSwitch=false;
      const neighbours=[];if(x>0)neighbours.push(i-1);if(x+1<w)neighbours.push(i+1);if(y>0)neighbours.push(i-w);if(y+1<h)neighbours.push(i+w);
      neighbours.forEach(j=>{if(!activeMask[j])return;hasNeighbour=true;const delta=Math.abs(Number(depthMm[i])-Number(depthMm[j]));if(Number.isFinite(delta))maxJump=Math.max(maxJump,delta);if(classCode[i]&&classCode[j]&&classCode[i]!==classCode[j])signSwitch=true;});
      localDepthJumpMm[i]=hasNeighbour?maxJump:0;signSwitchMask[i]=signSwitch?1:0;
    }
    return {localDepthJumpMm,signSwitchMask};
  }
  function projectionComponentSummary(activeMask,width,height,localDepthJumpMm,signSwitchMask,pathFlags,smallComponentMaxPixels){
    const w=Math.max(1,Math.floor(finite(width,0))),h=Math.max(1,Math.floor(finite(height,0))),n=w*h,maxSmall=Math.max(1,Math.floor(finite(smallComponentMaxPixels,24)));
    if(!activeMask||activeMask.length!==n)throw new Error('Projection component analysis requires a valid active mask.');
    const labels=new Int32Array(n),queue=new Int32Array(n),components=[];let nextId=0;
    for(let seed=0;seed<n;seed++){
      if(!activeMask[seed]||labels[seed])continue;nextId++;let head=0,tail=0;queue[tail++]=seed;labels[seed]=nextId;let pixels=0,perimeter=0,minX=w,minY=h,maxX=-1,maxY=-1,depthSum=0,depthCount=0,maxDepthJump=0,signSwitchPixels=0,unsupportedGapPixels=0,subthresholdGapPixels=0,resumedSegmentPixels=0;
      while(head<tail){const i=queue[head++],x=i%w,y=Math.floor(i/w);pixels++;minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);const jump=Number(localDepthJumpMm&&localDepthJumpMm[i]);if(Number.isFinite(jump)){depthSum+=jump;depthCount++;maxDepthJump=Math.max(maxDepthJump,jump);}if(signSwitchMask&&signSwitchMask[i])signSwitchPixels++;const flags=pathFlags?pathFlags[i]:0;if(flags&1)unsupportedGapPixels++;if(flags&2)subthresholdGapPixels++;if(flags&4)resumedSegmentPixels++;
        const neighbours=[[x-1,y],[x+1,y],[x,y-1],[x,y+1]];for(const pair of neighbours){const nx=pair[0],ny=pair[1];if(nx<0||nx>=w||ny<0||ny>=h){perimeter++;continue;}const j=ny*w+nx;if(!activeMask[j]){perimeter++;continue;}if(!labels[j]){labels[j]=nextId;queue[tail++]=j;}}
      }
      components.push({id:nextId,pixels,perimeterPixels:perimeter,bounds:[minX,minY,maxX,maxY],meanLocalDepthJumpMm:depthCount?depthSum/depthCount:0,maxLocalDepthJumpMm:maxDepthJump,signSwitchPixels,unsupportedGapPixels,subthresholdGapPixels,resumedSegmentPixels,small:pixels<=maxSmall});
    }
    const small=components.filter(c=>c.small),smallPixels=small.reduce((sum,c)=>sum+c.pixels,0),smallSignSwitchPixels=small.reduce((sum,c)=>sum+c.signSwitchPixels,0),smallUnsupportedGapPixels=small.reduce((sum,c)=>sum+c.unsupportedGapPixels,0),smallSubthresholdGapPixels=small.reduce((sum,c)=>sum+c.subthresholdGapPixels,0),smallResumedSegmentPixels=small.reduce((sum,c)=>sum+c.resumedSegmentPixels,0);
    return {componentLabels:labels,components,metrics:{componentCount:components.length,smallComponentMaxPixels:maxSmall,smallComponentCount:small.length,smallComponentPixels:smallPixels,smallComponentSignSwitchFraction:smallPixels?smallSignSwitchPixels/smallPixels:0,smallComponentUnsupportedGapFraction:smallPixels?smallUnsupportedGapPixels/smallPixels:0,smallComponentSubthresholdGapFraction:smallPixels?smallSubthresholdGapPixels/smallPixels:0,smallComponentResumedSegmentFraction:smallPixels?smallResumedSegmentPixels/smallPixels:0}};
  }
  function raycastProgramKind(style){const s=style&&typeof style==='object'?style:{};return s.rayRoiMaskOnly===true?'mask':(rayFeatureModeCode(s.rayFeatureMode)===1?'audit':'scientific');}
  function matrixRowsToColumnMajor(matrix){
    const source=(Array.isArray(matrix)||ArrayBuffer.isView(matrix))?matrix:null,out=new Float32Array(16);let values=null;
    if(source&&source.length===16&&!Array.isArray(source[0])&&!ArrayBuffer.isView(source[0]))values=Array.from(source,Number);
    else if(source&&source.length===4&&Array.from(source).every(row=>(Array.isArray(row)||ArrayBuffer.isView(row))&&row.length===4))values=Array.from(source).flatMap(row=>Array.from(row,Number));
    if(!values||values.length!==16)throw new Error('Fragment-volume world-to-voxel matrix must be a 4-by-4 matrix or a row-major array with 16 values.');
    if(values.some(value=>!Number.isFinite(value)))throw new Error('Fragment-volume world-to-voxel matrix contains a non-finite value.');
    for(let r=0;r<4;r++)for(let c=0;c<4;c++)out[c*4+r]=values[r*4+c];
    return out;
  }
  function chooseAtlasLayout(dims,maxTextureSize){
    const d=Array.from(dims||[]).slice(0,3).map(Number),limit=Math.max(1,Math.floor(finite(maxTextureSize,4096)));
    if(d.length!==3||d.some(x=>!Number.isInteger(x)||x<1))throw new Error('Fragment-volume dimensions are invalid.');
    let best=null;
    for(let cols=1;cols<=d[2];cols++){
      const rows=Math.ceil(d[2]/cols),width=cols*d[0],height=rows*d[1];
      if(width>limit||height>limit)continue;
      const score=Math.max(width,height)*1e9+width*height;
      if(!best||score<best.score)best={cols,rows,width,height,score};
    }
    if(!best)throw new Error(`Fragment-volume atlas ${d.join('×')} exceeds the browser texture limit ${limit}.`);
    return best;
  }
  function encodeFragmentVolumeAtlas(descriptor,maxTextureSize){
    const desc=descriptor&&typeof descriptor==='object'?descriptor:{},dims=Array.from(desc.dims||[]).slice(0,3).map(Number),n=dims.reduce((a,b)=>a*b,1),data=desc.data,support=desc.support;
    if(dims.length!==3||dims.some(x=>!Number.isInteger(x)||x<1)||!data||data.length!==n)throw new Error('Fragment-volume data do not match their dimensions.');
    if(support&&support.length!==n)throw new Error('Fragment-volume support does not match its dimensions.');
    const range=Array.from(desc.valueRange||[]).slice(0,2).map(Number);let lo=finite(range[0],NaN),hi=finite(range[1],NaN);
    if(!Number.isFinite(lo)||!Number.isFinite(hi)){lo=Infinity;hi=-Infinity;for(let i=0;i<n;i++){if(support&&support[i]===0)continue;const v=Number(data[i]);if(Number.isFinite(v)){lo=Math.min(lo,v);hi=Math.max(hi,v);}}}
    if(!Number.isFinite(lo)||!Number.isFinite(hi))throw new Error('Fragment-volume data contain no finite supported values.');
    if(hi<lo){const t=lo;lo=hi;hi=t;}const layout=chooseAtlasLayout(dims,maxTextureSize),pixels=new Uint8Array(layout.width*layout.height*4),scratch=new ArrayBuffer(4),scratchView=new DataView(scratch),scratchBytes=new Uint8Array(scratch),unsupported=[1,0,192,127];
    const index=(x,y,z)=>x+dims[0]*(y+dims[1]*z);
    for(let z=0;z<dims[2];z++){
      const tileX=z%layout.cols,tileY=Math.floor(z/layout.cols);
      for(let y=0;y<dims[1];y++)for(let x=0;x<dims[0];x++){
        const src=index(x,y,z),value=Number(data[src]),valid=(!support||support[src]!==0)&&Number.isFinite(value),dst=4*((tileY*dims[1]+y)*layout.width+tileX*dims[0]+x);
        if(!valid){pixels[dst]=unsupported[0];pixels[dst+1]=unsupported[1];pixels[dst+2]=unsupported[2];pixels[dst+3]=unsupported[3];continue;}
        scratchView.setFloat32(0,value,true);pixels[dst]=scratchBytes[0];pixels[dst+1]=scratchBytes[1];pixels[dst+2]=scratchBytes[2];pixels[dst+3]=scratchBytes[3];
      }
    }
    const spacingMm=vec3(desc.spacingMm,[1,1,1]).map(value=>Math.max(.05,Math.abs(value)));
    return {pixels,dims,range:[lo,hi],spacingMm,cols:layout.cols,rows:layout.rows,width:layout.width,height:layout.height,worldToVoxel:matrixRowsToColumnMajor(desc.worldToVoxel),key:String(desc.key||'')};
  }


  function choosePaddedAtlasLayout(dims,maxTextureSize,padding){
    const d=Array.from(dims||[]).slice(0,3).map(Number),pad=Math.max(0,Math.floor(finite(padding,1))),limit=Math.max(1,Math.floor(finite(maxTextureSize,4096)));
    if(d.length!==3||d.some(x=>!Number.isInteger(x)||x<1))throw new Error('Ray-cast structural-volume dimensions are invalid.');
    const tileWidth=d[0]+2*pad,tileHeight=d[1]+2*pad;let best=null;
    for(let cols=1;cols<=d[2];cols++){
      const rows=Math.ceil(d[2]/cols),width=cols*tileWidth,height=rows*tileHeight;
      if(width>limit||height>limit)continue;
      const score=Math.max(width,height)*1e9+width*height;
      if(!best||score<best.score)best={cols,rows,width,height,tileWidth,tileHeight,padding:pad,score};
    }
    if(!best)throw new Error(`Padded ray-cast atlas ${d.join('×')} exceeds the browser texture limit ${limit}.`);
    return best;
  }
  function matrixRows4(matrix){
    const source=(Array.isArray(matrix)||ArrayBuffer.isView(matrix))?matrix:null;let values=null;
    if(source&&source.length===16&&!Array.isArray(source[0])&&!ArrayBuffer.isView(source[0]))values=Array.from(source,Number);
    else if(source&&source.length===4&&Array.from(source).every(row=>(Array.isArray(row)||ArrayBuffer.isView(row))&&row.length===4))values=Array.from(source).flatMap(row=>Array.from(row,Number));
    if(!values||values.length!==16||values.some(value=>!Number.isFinite(value)))throw new Error('Ray-cast structural world-to-voxel matrix is invalid.');
    return [values.slice(0,4),values.slice(4,8),values.slice(8,12),values.slice(12,16)];
  }
  function prepareRaycastStructuralAtlas(descriptor,maxTextureSize){
    const startedAt=nowMs(),desc=descriptor&&typeof descriptor==='object'?descriptor:{},dims=Array.from(desc.dims||[]).slice(0,3).map(Number),n=dims.reduce((a,b)=>a*b,1),data=desc.data,support=desc.support;
    if(dims.length!==3||dims.some(x=>!Number.isInteger(x)||x<1)||!data||data.length!==n)throw new Error('Ray-cast structural data do not match their dimensions.');
    if(support&&support.length!==n)throw new Error('Ray-cast structural support does not match its dimensions.');
    const range=Array.from(desc.valueRange||[]).slice(0,2).map(Number);let lo=finite(range[0],NaN),hi=finite(range[1],NaN);
    if(!Number.isFinite(lo)||!Number.isFinite(hi)||hi<=lo)throw new Error('Ray-cast structural display window is invalid.');
    const spacing=vec3(desc.spacingMm,[1,1,1]).map(x=>Math.max(.05,Math.abs(x))),voxelToWorldRows=matrixRows4(desc.voxelToWorld),layout=choosePaddedAtlasLayout(dims,maxTextureSize,1),scalar=new Float32Array(n),blurred=new Float32Array(n),index=(x,y,z)=>x+dims[0]*(y+dims[1]*z),valid=i=>(!support||support[i]!==0)&&Number.isFinite(Number(data[i]));
    for(let i=0;i<n;i++)scalar[i]=valid(i)?clamp((Number(data[i])-lo)/(hi-lo),0,1):0;
    // MRIcroGL derives gradients from a lightly blurred display-mapped volume. This
    // support-aware seven-point kernel does not leak structural intensity outside
    // the authoritative foreground mask.
    for(let z=0;z<dims[2];z++)for(let y=0;y<dims[1];y++)for(let x=0;x<dims[0];x++){
      const i=index(x,y,z);if(!valid(i)){blurred[i]=0;continue;}let sum=2*scalar[i],weight=2;
      const addValue=(xx,yy,zz)=>{if(xx<0||yy<0||zz<0||xx>=dims[0]||yy>=dims[1]||zz>=dims[2])return;const j=index(xx,yy,zz);if(valid(j)){sum+=scalar[j];weight++;}};
      addValue(x-1,y,z);addValue(x+1,y,z);addValue(x,y-1,z);addValue(x,y+1,z);addValue(x,y,z-1);addValue(x,y,z+1);blurred[i]=sum/weight;
    }
    const sample=(x,y,z)=>{if(x<0||y<0||z<0||x>=dims[0]||y>=dims[1]||z>=dims[2])return 0;const i=index(x,y,z);return valid(i)?blurred[i]:0;};
    const voxelAxisToWorld=[
      [voxelToWorldRows[0][0]/spacing[0],voxelToWorldRows[0][1]/spacing[1],voxelToWorldRows[0][2]/spacing[2]],
      [voxelToWorldRows[1][0]/spacing[0],voxelToWorldRows[1][1]/spacing[1],voxelToWorldRows[1][2]/spacing[2]],
      [voxelToWorldRows[2][0]/spacing[0],voxelToWorldRows[2][1]/spacing[1],voxelToWorldRows[2][2]/spacing[2]]
    ];
    const worldGradient=(x,y,z)=>{
      const gx=(sample(x+1,y,z)-sample(x-1,y,z))/(2*spacing[0]),gy=(sample(x,y+1,z)-sample(x,y-1,z))/(2*spacing[1]),gz=(sample(x,y,z+1)-sample(x,y,z-1))/(2*spacing[2]);
      const wx=voxelAxisToWorld[0][0]*gx+voxelAxisToWorld[0][1]*gy+voxelAxisToWorld[0][2]*gz,wy=voxelAxisToWorld[1][0]*gx+voxelAxisToWorld[1][1]*gy+voxelAxisToWorld[1][2]*gz,wz=voxelAxisToWorld[2][0]*gx+voxelAxisToWorld[2][1]*gy+voxelAxisToWorld[2][2]*gz;
      return [wx,wy,wz,Math.hypot(wx,wy,wz)];
    };
    // Estimate a robust gradient scale from a deterministic subsample. The scale
    // affects illumination only; structural intensities and support are unchanged.
    const sampledMagnitudes=[];for(let linear=0;linear<n;linear+=17){if(!valid(linear))continue;const z=Math.floor(linear/(dims[0]*dims[1])),rem=linear-z*dims[0]*dims[1],y=Math.floor(rem/dims[0]),x=rem-y*dims[0],m=worldGradient(x,y,z)[3];if(Number.isFinite(m)&&m>0)sampledMagnitudes.push(m);}
    sampledMagnitudes.sort((a,b)=>a-b);const percentileIndex=Math.max(0,Math.min(sampledMagnitudes.length-1,Math.floor(sampledMagnitudes.length*.985))),gradientReference=sampledMagnitudes.length?Math.max(1e-6,sampledMagnitudes[percentileIndex]):1;
    const scalarPixels=new Uint8Array(layout.width*layout.height*4),gradientPixels=new Uint8Array(layout.width*layout.height*4);
    const encodeVoxel=(x,y,z,dst)=>{
      const i=index(x,y,z),supported=valid(i),v=supported?scalar[i]:0,scaled=clamp(v,0,1)*255,high=Math.floor(scaled),fraction=scaled-high;scalarPixels[dst]=high;scalarPixels[dst+1]=Math.round(fraction*255);scalarPixels[dst+2]=0;scalarPixels[dst+3]=supported?255:0;
      if(!supported){gradientPixels[dst]=gradientPixels[dst+1]=gradientPixels[dst+2]=128;gradientPixels[dst+3]=0;return;}
      let [wx,wy,wz,mag]=worldGradient(x,y,z);if(mag>1e-12){wx=-wx/mag;wy=-wy/mag;wz=-wz/mag;}else{wx=0;wy=0;wz=1;mag=0;}
      gradientPixels[dst]=Math.round(clamp(wx*.5+.5,0,1)*255);gradientPixels[dst+1]=Math.round(clamp(wy*.5+.5,0,1)*255);gradientPixels[dst+2]=Math.round(clamp(wz*.5+.5,0,1)*255);gradientPixels[dst+3]=Math.round(clamp(mag/gradientReference,0,1)*255);
    };
    for(let z=0;z<dims[2];z++){
      const tileX=z%layout.cols,tileY=Math.floor(z/layout.cols),originX=tileX*layout.tileWidth,originY=tileY*layout.tileHeight;
      for(let py=0;py<layout.tileHeight;py++)for(let px=0;px<layout.tileWidth;px++){
        const x=clamp(px-layout.padding,0,dims[0]-1),y=clamp(py-layout.padding,0,dims[1]-1),dst=4*((originY+py)*layout.width+originX+px);encodeVoxel(x,y,z,dst);
      }
    }
    return {scalarPixels,gradientPixels,dims,spacingMm:spacing,cols:layout.cols,rows:layout.rows,width:layout.width,height:layout.height,tileWidth:layout.tileWidth,tileHeight:layout.tileHeight,padding:layout.padding,worldToVoxel:matrixRowsToColumnMajor(desc.worldToVoxel),key:String(desc.key||'raycast-structural'),gradientReference,gradientKernel:'support_aware_7_point_center2',prepareMs:nowMs()-startedAt};
  }
  function cachedRaycastStructuralAtlas(descriptor,maxTextureSize){
    const key=[String(descriptor&&descriptor.key||'raycast-structural'),Math.max(1,Math.floor(finite(maxTextureSize,4096)))].join('|'),cached=RAYCAST_PREPARED_CACHE.get(key);
    if(cached){RAYCAST_PREPARED_CACHE.delete(key);RAYCAST_PREPARED_CACHE.set(key,cached);return cached;}
    const packed=prepareRaycastStructuralAtlas(descriptor,maxTextureSize);RAYCAST_PREPARED_CACHE.set(key,packed);
    while(RAYCAST_PREPARED_CACHE.size>RAYCAST_PREPARED_CACHE_LIMIT){const oldest=RAYCAST_PREPARED_CACHE.keys().next().value;RAYCAST_PREPARED_CACHE.delete(oldest);}
    return packed;
  }
  function structuralSurfaceParameters(style){
    const definition=clamp(finite(style&&style.raySurfaceDefinition,.68),0,1);
    return {
      definition,
      gradientLow:.035,
      gradientHigh:.225,
      gradientExponent:1.20,
      interiorFactor:.10,
      coarseStepMultiplier:2.50,
      visibleAlpha:.50,
      definitionContract:'zero_is_exact_unweighted_opacity_and_definition_does_not_change_sampling_or_lighting'
    };
  }
  function structuralSurfaceOpacityWeight(definition,gradientMagnitude,parameters){
    const p=parameters&&typeof parameters==='object'?parameters:structuralSurfaceParameters({raySurfaceDefinition:definition}),d=clamp(finite(definition,p.definition),0,1),g=clamp(finite(gradientMagnitude,0),0,1),den=Math.max(1e-6,p.gradientHigh-p.gradientLow),x=clamp((g-p.gradientLow)/den,0,1),smooth=x*x*(3-2*x),surface=Math.pow(smooth,Math.max(.1,p.gradientExponent)),defined=p.interiorFactor+(1-p.interiorFactor)*surface;
    return (1-d)+d*defined;
  }
  const VOLUME3D_PREPARED=new Map(), VOLUME3D_PREPARED_LIMIT=4;
  function volume3DPrepared(key,build){
    if(VOLUME3D_PREPARED.has(key)){const hit=VOLUME3D_PREPARED.get(key);VOLUME3D_PREPARED.delete(key);VOLUME3D_PREPARED.set(key,hit);return hit;}
    const built=build();VOLUME3D_PREPARED.set(key,built);
    while(VOLUME3D_PREPARED.size>VOLUME3D_PREPARED_LIMIT)VOLUME3D_PREPARED.delete(VOLUME3D_PREPARED.keys().next().value);
    return built;
  }
  /* Voxel size along each axis from a world->voxel affine: 1/||row||. The feature
     descriptor does not carry spacingMm, and the coverage kernel is defined in mm. */
  function spacingFromWorldToVoxel(worldToVoxel){
    const prep=volumePrep(),matrixRows=prep._test&&prep._test.matrixRows4;if(typeof matrixRows!=='function')throw new Error('The canonical volume-preparation affine-row authority is unavailable.');
    const rows=matrixRows(worldToVoxel),out=[0,1,2].map(i=>{const r=rows[i]||[];const n=Math.hypot(finite(r[0],0),finite(r[1],0),finite(r[2],0));return n>1e-9?1/n:NaN;});
    if(!out.every(v=>Number.isFinite(v)&&v>0))throw new Error('The feature world-to-voxel affine does not define finite positive voxel spacing.');
    return out;
  }
  function volume3DCoverageKey(style,featureDescriptor,maxTextureSize){
    const d=featureDescriptor||{},spacing=Array.isArray(d.spacingMm)&&d.spacingMm.length>=3?d.spacingMm.slice(0,3).map(Number):spacingFromWorldToVoxel(d.worldToVoxel),sigma=style.volumeBoundarySmoothingMm,reconstruction=String(style.volumeCoverageReconstruction||'component_signed_distance_volume_preserving');
    return ['c3d-sdf2',volume3DNativeKey(d,spacing),volume3DThresholdKey(style),sigma===null?'default':sigma,reconstruction,Number(maxTextureSize)||0,48*1024*1024].join('|');
  }
  function affineKey(value){return (Array.isArray(value)||ArrayBuffer.isView(value)?Array.from(value):[]).map(x=>Number.isFinite(Number(x))?Number(x).toPrecision(10):'nan').join(',');}
  function volume3DStructuralKey(descriptor,maxTextureSize){const d=descriptor||{};return ['s3d',String(d.key||'structural'),Array.from(d.dims||[]).join('x'),affineKey(d.worldToVoxel),Array.from(d.spacingMm||[]).join(','),Array.from(d.window||[]).join(','),d.data&&d.data.length||0,d.support&&d.support.length||0,d.normalAuditVariants?1:0,Number(maxTextureSize)||0].join('|');}
  function volume3DNativeKey(descriptor,spacingMm){const d=descriptor||{};return ['f3d',String(d.key||'feature'),Array.from(d.dims||[]).join('x'),affineKey(d.worldToVoxel),Array.from(spacingMm||[]).join(','),d.data&&d.data.length||0,d.support&&d.support.length||0].join('|');}
  function volume3DPreparationSpec(mesh,style,maxTextureSize){
    const sd=mesh&&mesh.raycastStructuralVolume,fd=mesh&&mesh.fragmentVolume;if(!sd||!fd)return null;
    const featureSpacing=Array.isArray(fd.spacingMm)&&fd.spacingMm.length>=3?fd.spacingMm.slice(0,3).map(Number):spacingFromWorldToVoxel(fd.worldToVoxel,[1,1,1]);
    const structuralKey=volume3DStructuralKey(sd,maxTextureSize),nativeKey=volume3DNativeKey(fd,featureSpacing),coverageKey=volume3DCoverageKey(style,fd,maxTextureSize);
    return {sd,fd,featureSpacing,structuralKey,nativeKey,coverageKey,
      structuralInput:Object.assign({},sd,{maxTextureSize}),
      nativeInput:Object.assign({},fd,{spacingMm:featureSpacing}),
      coverageInput:Object.assign({},fd,{spacingMm:featureSpacing,maxTextureSize,boundarySmoothingMm:style.volumeBoundarySmoothingMm,coverageReconstruction:style.volumeCoverageReconstruction,memoryBudgetBytes:48*1024*1024,displayContract:style.projectionDisplayContract})};
  }
  function volume3DThresholdKey(style){
    return [style.projectionThresholdMode,style.projectionThresholdLow,style.projectionThresholdHigh,style.projectionThresholdValue].join(',');
  }
  function raycastPhaseTexturePixels(size){
    const n=Math.max(8,Math.min(128,Math.floor(finite(size,64)))),pixels=new Uint8Array(n*n*4),fract=x=>x-Math.floor(x);
    for(let y=0;y<n;y++)for(let x=0;x<n;x++){
      const phase=fract(52.9829189*fract(.06711056*x+.00583715*y)),value=Math.max(0,Math.min(255,Math.floor(phase*256))),i=4*(y*n+x);
      pixels[i]=pixels[i+1]=pixels[i+2]=value;pixels[i+3]=255;
    }
    return {size:n,pixels,algorithm:'fixed_interleaved_gradient_noise_64x64',deterministic:true};
  }
  function raycastTransferLutPixels(style){
    const s=style||{},opacity=clamp(finite(s.rayStructuralOpacity,.55),0,1),brightness=clamp(finite(s.brightness,1),0,2),gamma=clamp(finite(s.structuralGamma,1),.25,4),pixels=new Uint8Array(256*4),tissueLow=.055,tissueHigh=.72;
    for(let i=0;i<256;i++){
      const x=i/255,mapped=Math.pow(x,1/gamma),t=clamp((mapped-tissueLow)/Math.max(1e-6,tissueHigh-tissueLow),0,1),smooth=t*t*(3-2*t),gray=clamp(Math.pow(mapped,.88)*brightness,0,1),alpha=clamp(opacity*.68*Math.pow(smooth,1.08),0,.90),j=4*i;
      pixels[j]=Math.round(gray*255);pixels[j+1]=Math.round(gray*255);pixels[j+2]=Math.round(gray*255);pixels[j+3]=Math.round(alpha*255);
    }
    return pixels;
  }

  function encodeAtlasLabelVolume(descriptor,maxTextureSize){
    const desc=descriptor&&typeof descriptor==='object'?descriptor:{},dims=Array.from(desc.dims||[]).slice(0,3).map(Number),n=dims.reduce((a,b)=>a*b,1),data=desc.data;
    if(dims.length!==3||dims.some(x=>!Number.isInteger(x)||x<1)||!data||data.length!==n)throw new Error('Atlas-label volume does not match its dimensions.');
    const layout=chooseAtlasLayout(dims,maxTextureSize),pixels=new Uint8Array(layout.width*layout.height*4),index=(x,y,z)=>x+dims[0]*(y+dims[1]*z);
    for(let z=0;z<dims[2];z++){
      const tileX=z%layout.cols,tileY=Math.floor(z/layout.cols);
      for(let y=0;y<dims[1];y++)for(let x=0;x<dims[0];x++){
        const value=Math.max(0,Math.floor(finite(data[index(x,y,z)],0)))>>>0,dst=4*((tileY*dims[1]+y)*layout.width+tileX*dims[0]+x);
        pixels[dst]=value&255;pixels[dst+1]=(value>>>8)&255;pixels[dst+2]=(value>>>16)&255;pixels[dst+3]=(value>>>24)&255;
      }
    }
    return {pixels,dims,cols:layout.cols,rows:layout.rows,width:layout.width,height:layout.height,worldToVoxel:matrixRowsToColumnMajor(desc.worldToVoxel),key:String(desc.key||'atlas')};
  }

  function boundaryLineWidthPx(width,height,options){
    const opts=options||{},explicit=finite(opts.lineWidthPx,NaN);
    if(Number.isFinite(explicit))return clamp(explicit,.55,8);
    return clamp(1.25*Math.max(2,finite(height,488))/488,.70,4.5);
  }
  function downsampleBoundaryRgba(source,sourceWidth,sourceHeight,targetWidth,targetHeight){
    const out=new Uint8ClampedArray(targetWidth*targetHeight*4),sx=sourceWidth/targetWidth,sy=sourceHeight/targetHeight;
    for(let y=0;y<targetHeight;y++)for(let x=0;x<targetWidth;x++){
      const x0=Math.floor(x*sx),x1=Math.max(x0+1,Math.floor((x+1)*sx)),y0=Math.floor(y*sy),y1=Math.max(y0+1,Math.floor((y+1)*sy));let r=0,g=0,b=0,a=0,n=0;
      for(let yy=y0;yy<Math.min(sourceHeight,y1);yy++)for(let xx=x0;xx<Math.min(sourceWidth,x1);xx++){const i=4*(xx+sourceWidth*yy);r+=source[i];g+=source[i+1];b+=source[i+2];a+=source[i+3];n++;}
      const j=4*(x+targetWidth*y),d=Math.max(1,n);out[j]=Math.round(r/d);out[j+1]=Math.round(g/d);out[j+2]=Math.round(b/d);out[j+3]=Math.round(a/d);
    }
    return out;
  }
  function contourPixelsFromSeed(seed,width,height,options){
    const w=Math.max(1,Math.floor(finite(width,1))),h=Math.max(1,Math.floor(finite(height,1))),source=seed instanceof Uint8Array||seed instanceof Uint8ClampedArray?seed:new Uint8Array(seed||[]),opts=options||{},color=vec3(opts.color,[.13,.13,.13]).map(value=>Math.round(clamp(value,0,1)*255)),opacity=clamp(finite(opts.opacity,1),0,1),lineWidth=boundaryLineWidthPx(w,h,opts),out=new Uint8ClampedArray(w*h*4);if(source.length!==w*h)return {width:w,height:h,data:out,boundaryCount:0,lineWidthPx:lineWidth};const searchRadius=Math.max(2,Math.ceil(lineWidth*.5+1.5)),half=Math.max(.28,lineWidth*.5),aa=.85;let boundaryCount=0;for(let y=0;y<h;y++)for(let x=0;x<w;x++){let minDistance=Infinity,seedWeight=0;for(let dy=-searchRadius;dy<=searchRadius;dy++){const yy=y+dy;if(yy<0||yy>=h)continue;for(let dx=-searchRadius;dx<=searchRadius;dx++){const xx=x+dx;if(xx<0||xx>=w)continue;const weight=source[xx+w*yy];if(!weight)continue;const distance=Math.hypot(dx,dy);if(distance<minDistance){minDistance=distance;seedWeight=weight/255;}else if(Math.abs(distance-minDistance)<1e-6)seedWeight=Math.max(seedWeight,weight/255);}}if(!Number.isFinite(minDistance))continue;const u=clamp((minDistance-(half-aa))/Math.max(1e-6,2*aa),0,1),coverage=(1-u*u*(3-2*u))*seedWeight;if(coverage<=.002)continue;const dst=4*(x+w*y),alpha=Math.round(255*opacity*coverage);out[dst]=color[0];out[dst+1]=color[1];out[dst+2]=color[2];out[dst+3]=alpha;boundaryCount++;}return {width:w,height:h,data:out,boundaryCount,lineWidthPx:lineWidth};
  }
  function atlasBoundaryPixels(raw,width,height,options){
    const source=raw instanceof Uint8Array?raw:new Uint8Array(raw||[]),w=Math.max(1,Math.floor(finite(width,1))),h=Math.max(1,Math.floor(finite(height,1))),opts=options||{},depthTolerance=clamp(finite(opts.depthTolerance,4/255),1/255,.25),empty=new Uint8ClampedArray(w*h*4);if(source.length!==w*h*4)return {width:w,height:h,data:empty,boundaryCount:0,lineWidthPx:boundaryLineWidthPx(w,h,opts)};const srcIndex=(x,yTop)=>4*((h-1-yTop)*w+x),labelAt=(x,y)=>{if(x<0||y<0||x>=w||y>=h)return 0;const i=srcIndex(x,y);return source[i]+256*source[i+1]+65536*source[i+2];},depthAt=(x,y)=>{if(x<0||y<0||x>=w||y>=h)return NaN;return source[srcIndex(x,y)+3]/255;},seed=new Uint8Array(w*h),neighbours=[[1,0],[-1,0],[0,1],[0,-1]];let seedCount=0;for(let y=0;y<h;y++)for(let x=0;x<w;x++){const center=labelAt(x,y),depth=depthAt(x,y);if(center<=0||!Number.isFinite(depth)||depth<=0)continue;let boundary=false;for(const d of neighbours){const nx=x+d[0],ny=y+d[1],other=labelAt(nx,ny),otherDepth=depthAt(nx,ny);if(other>0&&other!==center&&Number.isFinite(otherDepth)&&Math.abs(otherDepth-depth)<=depthTolerance){boundary=true;break;}}if(boundary){seed[x+w*y]=255;seedCount++;}}if(!seedCount)return {width:w,height:h,data:empty,boundaryCount:0,lineWidthPx:boundaryLineWidthPx(w,h,opts)};return contourPixelsFromSeed(seed,w,h,opts);
  }

  function compileShader(gl,type,source){const sh=gl.createShader(type);gl.shaderSource(sh,source);gl.compileShader(sh);if(!gl.getShaderParameter(sh,gl.COMPILE_STATUS)){const message=gl.getShaderInfoLog(sh)||'unknown shader compile error';gl.deleteShader(sh);throw new Error(message);}return sh;}
  function createRaycastProgram(gl,kind){
    kind=kind==='audit'||kind==='mask'?kind:'scientific';
    const startedAt=nowMs(),hasFragDepth=!!gl.getExtension('EXT_frag_depth'),depthHeader=hasFragDepth?'#extension GL_EXT_frag_depth : enable\n':'',depthWrite=hasFragDepth?'gl_FragDepthEXT=clamp(firstDepth,0.0,1.0);':'';
    const vs=compileShader(gl,gl.VERTEX_SHADER,`
      attribute vec3 aPosition;
      uniform mat4 uMVP;
      varying vec3 vWorldPosition;
      void main(){vWorldPosition=aPosition;gl_Position=uMVP*vec4(aPosition,1.0);}
    `);
    const common=depthHeader+`
      precision highp float;
      precision highp int;
      varying vec3 vWorldPosition;
      uniform mat4 uMVP;
      uniform int uProjectionMode;
      uniform vec3 uEyeWorld;
      uniform vec3 uRayDirectionWorld;
      uniform vec3 uRayBoundsMin;
      uniform vec3 uRayBoundsMax;
      uniform float uRayStepMm;
      uniform int uRayMaxSteps;
      uniform int uRayFeatureMaxSteps;
      uniform float uRayFeatureSlabMm;
      uniform float uRayFeatureOpacity;
      uniform float uRayOverlayDepth;
      uniform float uRaySliceSizeMm;
      uniform float uRayFeatureSliceSizeMm;
      uniform vec3 uRayLightDirection;
      uniform vec3 uRayLightColor;
      uniform float uRayAmbient;
      uniform float uRayDiffuse;
      uniform float uRaySpecular;
      uniform float uRayShininess;
      uniform float uRaySurfaceDefinition;
      uniform float uRaySurfaceLow;
      uniform float uRaySurfaceHigh;
      uniform float uRaySurfaceExponent;
      uniform float uRayInteriorFactor;
      uniform float uRayCoarseStepMultiplier;
      uniform sampler2D uRayPhaseTexture;
      uniform vec2 uRayPhaseTextureSize;
      uniform int uClipCount;
      uniform vec4 uClipPlane0;
      uniform vec4 uClipPlane1;
      uniform vec4 uClipPlane2;
      uniform sampler2D uStructuralScalarAtlas;
      uniform sampler2D uStructuralGradientAtlas;
      uniform sampler2D uStructuralTransferLut;
      uniform vec3 uStructuralVolumeDims;
      uniform vec2 uStructuralVolumeGrid;
      uniform vec2 uStructuralVolumeTextureSize;
      uniform vec2 uStructuralTileSize;
      uniform mat4 uStructuralWorldToVoxel;
      uniform sampler2D uFragmentVolumeAtlas;
      uniform vec3 uFragmentVolumeDims;
      uniform vec2 uFragmentVolumeGrid;
      uniform vec2 uFragmentVolumeTextureSize;
      uniform mat4 uWorldToVoxel;
      uniform int uFeatureInterpolation;
      uniform int uProjectionThresholdMode;
      uniform float uProjectionNegativeThreshold;
      uniform float uProjectionPositiveThreshold;
      uniform float uProjectionSingleThreshold;
      uniform vec2 uProjectionDisplayRange;
      uniform sampler2D uProjectionGradientLut;
      uniform sampler2D uRayAtlasLabelAtlas;
      uniform vec3 uRayAtlasLabelDims;
      uniform vec2 uRayAtlasLabelGrid;
      uniform vec2 uRayAtlasLabelTextureSize;
      uniform mat4 uRayAtlasWorldToVoxel;
      uniform float uRayRoiFocusEnabled;
      uniform float uRayRoiCodeA;
      uniform float uRayRoiCodeB;
      uniform float uRayRoiMix;
      uniform float uRayOutsideRoiOpacity;
      bool fragmentCoordInside(ivec3 c){return c.x>=0&&c.y>=0&&c.z>=0&&float(c.x)<uFragmentVolumeDims.x&&float(c.y)<uFragmentVolumeDims.y&&float(c.z)<uFragmentVolumeDims.z;}
      vec4 fragmentEncodedAt(ivec3 c){if(!fragmentCoordInside(c))return vec4(0.0);float z=float(c.z),tileY=floor((z+0.5)/uFragmentVolumeGrid.x),tileX=z-tileY*uFragmentVolumeGrid.x;vec2 pixel=vec2(tileX*uFragmentVolumeDims.x+float(c.x)+0.5,tileY*uFragmentVolumeDims.y+float(c.y)+0.5);return texture2D(uFragmentVolumeAtlas,pixel/uFragmentVolumeTextureSize);}
      bool decodeFragmentValue(ivec3 c,out float value){if(!fragmentCoordInside(c)){value=0.0;return false;}vec4 encoded=fragmentEncodedAt(c),bytes=floor(encoded*255.0+0.5);if(bytes.r==1.0&&bytes.g==0.0&&bytes.b==192.0&&bytes.a==127.0){value=0.0;return false;}float signValue=bytes.a>=128.0?-1.0:1.0,high=bytes.a-(bytes.a>=128.0?128.0:0.0),exponent=high*2.0+floor(bytes.b/128.0),mantissa=mod(bytes.b,128.0)*65536.0+bytes.g*256.0+bytes.r;if(exponent==0.0)value=signValue*exp2(-126.0)*(mantissa/8388608.0);else value=signValue*exp2(exponent-127.0)*(1.0+mantissa/8388608.0);return true;}
      int projectionClass(float value){if(uProjectionThresholdMode==1){if(value<=uProjectionNegativeThreshold)return -1;if(value>=uProjectionPositiveThreshold)return 1;return 0;}if(uProjectionThresholdMode==2){float t=abs(uProjectionSingleThreshold);if(abs(value)<t)return 0;return value<0.0?-1:(value>0.0?1:0);}if(uProjectionThresholdMode==3)return value<=uProjectionSingleThreshold?-1:0;if(uProjectionThresholdMode==4)return value>=uProjectionSingleThreshold?1:0;return value<0.0?-1:(value>0.0?1:0);}
      bool nativeFeatureCell(ivec3 c,out float value,out int klass){if(!decodeFragmentValue(c,value)){klass=0;return false;}klass=projectionClass(value);return klass!=0;}
      float projectionStrength(float value,int klass){if(klass<0){float threshold=uProjectionThresholdMode==2?-abs(uProjectionSingleThreshold):(uProjectionThresholdMode==1?uProjectionNegativeThreshold:uProjectionSingleThreshold);return clamp(abs(value-threshold)/max(1e-20,abs(threshold-uProjectionDisplayRange.x)),0.0,1.0);}float threshold=uProjectionThresholdMode==2?abs(uProjectionSingleThreshold):(uProjectionThresholdMode==1?uProjectionPositiveThreshold:uProjectionSingleThreshold);return clamp(abs(value-threshold)/max(1e-20,abs(uProjectionDisplayRange.y-threshold)),0.0,1.0);}
      vec3 projectionColor(float value){float t=clamp((value-uProjectionDisplayRange.x)/max(1e-20,uProjectionDisplayRange.y-uProjectionDisplayRange.x),0.0,1.0);return texture2D(uProjectionGradientLut,vec2(t,0.5)).rgb;}
      float resolvedFeatureValue(vec3 voxel1,ivec3 occupiedCell,int desiredClass,float nativeValue){if(uFeatureInterpolation==0)return nativeValue;vec3 p=clamp(voxel1-vec3(1.0),vec3(0.0),uFragmentVolumeDims-vec3(1.0)),f=fract(p);ivec3 base=ivec3(floor(p));float weight=0.0,sum=0.0,lo=3.402823466e38,hi=-3.402823466e38;for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){ivec3 c=base+ivec3(dx,dy,dz);c=ivec3(clamp(vec3(c),vec3(0.0),uFragmentVolumeDims-vec3(1.0)));float wx=dx==0?1.0-f.x:f.x,wy=dy==0?1.0-f.y:f.y,wz=dz==0?1.0-f.z:f.z,w=wx*wy*wz,candidate;int candidateClass;if(w<=0.0||!nativeFeatureCell(c,candidate,candidateClass)||candidateClass!=desiredClass)continue;weight+=w;sum+=w*candidate;lo=min(lo,candidate);hi=max(hi,candidate);}if(weight<=1e-7)return nativeValue;return clamp(sum/weight,lo,hi);}
      float nativeEvidence(ivec3 c,int desiredClass){float value;int klass;if(!nativeFeatureCell(c,value,klass)||klass!=desiredClass)return 0.0;return projectionStrength(value,klass);}
      vec3 worldNormalFromVoxel(vec3 voxelNormal){vec3 worldNormal=vec3(dot(uWorldToVoxel[0].xyz,voxelNormal),dot(uWorldToVoxel[1].xyz,voxelNormal),dot(uWorldToVoxel[2].xyz,voxelNormal));return length(worldNormal)>1e-6?normalize(worldNormal):vec3(0.0);}
      vec3 featureBoundaryNormal(ivec3 cell,int desiredClass,vec3 entryNormalVoxel,vec3 viewDir){float xp=nativeEvidence(cell+ivec3(1,0,0),desiredClass),xm=nativeEvidence(cell-ivec3(1,0,0),desiredClass),yp=nativeEvidence(cell+ivec3(0,1,0),desiredClass),ym=nativeEvidence(cell-ivec3(0,1,0),desiredClass),zp=nativeEvidence(cell+ivec3(0,0,1),desiredClass),zm=nativeEvidence(cell-ivec3(0,0,1),desiredClass);vec3 normal=worldNormalFromVoxel(-(vec3(xp-xm,yp-ym,zp-zm)));if(length(normal)<1e-6)normal=worldNormalFromVoxel(entryNormalVoxel);if(length(normal)<1e-6)normal=viewDir;if(dot(normal,viewDir)<0.0)normal=-normal;return normal;}
      float featureBoundaryShade(vec3 normal,vec3 viewDir){vec3 lightDir=normalize(uRayLightDirection);float diffuse=max(dot(normal,lightDir),0.0),specular=pow(max(dot(reflect(-lightDir,normal),viewDir),0.0),max(1.0,uRayShininess));return clamp(.58+.42*(uRayAmbient+uRayDiffuse*diffuse)+.10*uRaySpecular*specular,.38,1.25);}
      bool rayAtlasCoordInside(ivec3 c){return c.x>=0&&c.y>=0&&c.z>=0&&float(c.x)<uRayAtlasLabelDims.x&&float(c.y)<uRayAtlasLabelDims.y&&float(c.z)<uRayAtlasLabelDims.z;}
      float rayAtlasLabelAtCoord(ivec3 c){if(!rayAtlasCoordInside(c))return 0.0;float z=float(c.z),tileY=floor((z+0.5)/uRayAtlasLabelGrid.x),tileX=z-tileY*uRayAtlasLabelGrid.x;vec2 pixel=vec2(tileX*uRayAtlasLabelDims.x+float(c.x)+0.5,tileY*uRayAtlasLabelDims.y+float(c.y)+0.5);vec4 bytes=floor(texture2D(uRayAtlasLabelAtlas,pixel/uRayAtlasLabelTextureSize)*255.0+0.5);return bytes.r+256.0*bytes.g+65536.0*bytes.b+16777216.0*bytes.a;}
      float rayAtlasLabelAtWorld(vec3 world){vec3 voxel=(uRayAtlasWorldToVoxel*vec4(world,1.0)).xyz;return rayAtlasLabelAtCoord(ivec3(floor(voxel-vec3(0.5))));}
      float roiMatchWeight(float labelValue){float a=abs(labelValue-uRayRoiCodeA)<.5?1.0:0.0,b=abs(labelValue-uRayRoiCodeB)<.5?1.0:0.0;if(abs(uRayRoiCodeA-uRayRoiCodeB)<.5)return a;return max(a*(1.0-uRayRoiMix),b*uRayRoiMix);}
      vec2 structuralAtlasUv(vec3 voxel0,float slice){float z=clamp(slice,0.0,uStructuralVolumeDims.z-1.0),tileY=floor((z+0.5)/uStructuralVolumeGrid.x),tileX=z-tileY*uStructuralVolumeGrid.x;vec2 tileOrigin=vec2(tileX*uStructuralTileSize.x,tileY*uStructuralTileSize.y),pixel=tileOrigin+vec2(1.5)+clamp(voxel0.xy,vec2(0.0),uStructuralVolumeDims.xy-vec2(1.0));return pixel/uStructuralVolumeTextureSize;}
      bool structuralVoxelInside(vec3 voxel1){vec3 voxel0=voxel1-vec3(1.0);return all(greaterThanEqual(voxel0,vec3(-0.5)))&&all(lessThanEqual(voxel0,uStructuralVolumeDims-vec3(0.5)));}
      vec4 structuralAtlasSample(sampler2D atlas,vec3 voxel1){if(!structuralVoxelInside(voxel1))return vec4(0.0);vec3 p=clamp(voxel1-vec3(1.0),vec3(0.0),uStructuralVolumeDims-vec3(1.0));float z0=floor(p.z),z1=min(z0+1.0,uStructuralVolumeDims.z-1.0),fz=fract(p.z);return mix(texture2D(atlas,structuralAtlasUv(p,z0)),texture2D(atlas,structuralAtlasUv(p,z1)),fz);}
      float structuralScalarValue(vec4 encoded){return clamp(encoded.r+encoded.g/255.0,0.0,1.0);}
      bool structuralFeatureMaskAtWorld(vec3 world){vec3 voxel=(uStructuralWorldToVoxel*vec4(world,1.0)).xyz;vec4 encoded=structuralAtlasSample(uStructuralScalarAtlas,voxel);return encoded.a>0.0&&structuralScalarValue(encoded)>.055;}
      float structuralRayPhase(vec2 fragmentCoord){vec2 pixel=mod(floor(fragmentCoord),uRayPhaseTextureSize),uv=(pixel+vec2(.5))/uRayPhaseTextureSize;return texture2D(uRayPhaseTexture,uv).r;}
      bool intersectBox(vec3 boxOrigin,vec3 boxDirection,vec3 boxMin,vec3 boxMax,out float enterT,out float exitT){vec3 inverseDirection=vec3(abs(boxDirection.x)<1e-8?1e20:1.0/boxDirection.x,abs(boxDirection.y)<1e-8?1e20:1.0/boxDirection.y,abs(boxDirection.z)<1e-8?1e20:1.0/boxDirection.z);vec3 t0=(boxMin-boxOrigin)*inverseDirection,t1=(boxMax-boxOrigin)*inverseDirection,nearT=min(t0,t1),farT=max(t0,t1);enterT=max(max(nearT.x,nearT.y),nearT.z);exitT=min(min(farT.x,farT.y),farT.z);return exitT>=enterT;}
      bool intersectRayBox(vec3 origin,vec3 direction,out float enterT,out float exitT){return intersectBox(origin,direction,uRayBoundsMin,uRayBoundsMax,enterT,exitT)&&exitT>=max(enterT,0.0);}
      bool clipRayPlane(vec4 plane,vec3 origin,vec3 direction,inout float enterT,inout float exitT){float distanceAtOrigin=dot(plane.xyz,origin)+plane.w,denominator=dot(plane.xyz,direction);if(abs(denominator)<1e-7)return distanceAtOrigin>=0.0;float crossing=-distanceAtOrigin/denominator;if(denominator>0.0)enterT=max(enterT,crossing);else exitT=min(exitT,crossing);return exitT>=enterT;}
      float projectedDepth(vec3 world){vec4 clip=uMVP*vec4(world,1.0);return clip.z/clip.w*.5+.5;}
      void integrateStructure(vec3 origin,vec3 direction,float enterT,float exitT,float featureT,out vec4 bgAcc,out float bgNearest,out float featureFront){float interval=max(0.0,exitT-enterT),fineStep=max(uRayStepMm,interval/max(float(uRayMaxSteps),1.0)),coarseStep=max(fineStep,min(fineStep*max(1.0,uRayCoarseStepMultiplier),max(fineStep,1.75*uRaySliceSizeMm))),opacityCorrection=fineStep/max(.05,uRaySliceSizeMm),phase=structuralRayPhase(gl_FragCoord.xy),t=enterT+phase*fineStep,previousCoarseT=t,firstSurfaceT=exitT,visibleSurfaceT=exitT;bool refined=false;bgAcc=vec4(0.0);bgNearest=exitT;featureFront=0.0;for(int sampleIndex=0;sampleIndex<384;sampleIndex++){if(sampleIndex>=uRayMaxSteps||t>exitT)break;vec3 world=origin+direction*t,structuralVoxel=(uStructuralWorldToVoxel*vec4(world,1.0)).xyz;vec4 scalarEncoded=structuralAtlasSample(uStructuralScalarAtlas,structuralVoxel);float scalarValue=structuralScalarValue(scalarEncoded);vec4 transfer=texture2D(uStructuralTransferLut,vec2(scalarValue,.5)),grad=structuralAtlasSample(uStructuralGradientAtlas,structuralVoxel);float surfaceness=smoothstep(uRaySurfaceLow,uRaySurfaceHigh,grad.a),surfaceWeight=pow(clamp(surfaceness,0.0,1.0),max(.1,uRaySurfaceExponent)),definedWeight=mix(uRayInteriorFactor,1.0,surfaceWeight),opacityWeight=mix(1.0,definedWeight,clamp(uRaySurfaceDefinition,0.0,1.0)),potentialAlpha=scalarEncoded.a>0.0?transfer.a:0.0,alphaBase=potentialAlpha*opacityWeight;if(!refined){if(potentialAlpha>.001){refined=true;t=max(enterT,previousCoarseT);continue;}previousCoarseT=t;t+=coarseStep;continue;}if(alphaBase>.0001){float alpha=1.0-pow(max(0.0,1.0-alphaBase),opacityCorrection);if(alpha>.0001){vec3 viewDir=normalize(-direction),decoded=grad.rgb*2.0-1.0;float decodedLength=length(decoded);vec3 normal=decodedLength>1e-5?decoded/decodedLength:viewDir;if(dot(normal,viewDir)<0.0)normal=-normal;vec3 lightDirection=normalize(uRayLightDirection);float lightDiffuse=max(dot(normal,lightDirection),0.0),lightSpec=pow(max(dot(reflect(-lightDirection,normal),viewDir),0.0),max(1.0,uRayShininess)),normalReliability=smoothstep(.025,.18,grad.a),lightScale=clamp(vec3(uRayAmbient)+(uRayDiffuse*lightDiffuse+uRaySpecular*lightSpec)*uRayLightColor,vec3(.06),vec3(1.30)),shade=mix(vec3(1.0),lightScale,normalReliability),remain=1.0-bgAcc.a,previousAlpha=bgAcc.a;bgAcc.rgb+=remain*transfer.rgb*shade*alpha;bgAcc.a+=remain*alpha;if(firstSurfaceT==exitT&&alpha>.002)firstSurfaceT=t;if(visibleSurfaceT==exitT&&previousAlpha<.50&&bgAcc.a>=.50)visibleSurfaceT=t;if(t<=featureT)featureFront=bgAcc.a;}}if(bgAcc.a>.985)break;t+=fineStep;}bgNearest=visibleSurfaceT<exitT?visibleSurfaceT:firstSurfaceT;}
    `;
    const maskCommon=depthHeader+`
      precision highp float;
      precision highp int;
      varying vec3 vWorldPosition;
      uniform mat4 uMVP;
      uniform int uProjectionMode;
      uniform vec3 uEyeWorld;
      uniform vec3 uRayDirectionWorld;
      uniform vec3 uRayBoundsMin;
      uniform vec3 uRayBoundsMax;
      uniform float uRayStepMm;
      uniform int uRayMaxSteps;
      uniform int uClipCount;
      uniform vec4 uClipPlane0;
      uniform vec4 uClipPlane1;
      uniform vec4 uClipPlane2;
      uniform sampler2D uStructuralScalarAtlas;
      uniform vec3 uStructuralVolumeDims;
      uniform vec2 uStructuralVolumeGrid;
      uniform vec2 uStructuralVolumeTextureSize;
      uniform vec2 uStructuralTileSize;
      uniform mat4 uStructuralWorldToVoxel;
      uniform sampler2D uRayAtlasLabelAtlas;
      uniform vec3 uRayAtlasLabelDims;
      uniform vec2 uRayAtlasLabelGrid;
      uniform vec2 uRayAtlasLabelTextureSize;
      uniform mat4 uRayAtlasWorldToVoxel;
      uniform float uRayRoiCodeA;
      uniform float uRayRoiCodeB;
      uniform float uRayRoiMix;
      bool rayAtlasCoordInside(ivec3 c){return c.x>=0&&c.y>=0&&c.z>=0&&float(c.x)<uRayAtlasLabelDims.x&&float(c.y)<uRayAtlasLabelDims.y&&float(c.z)<uRayAtlasLabelDims.z;}
      float rayAtlasLabelAtCoord(ivec3 c){if(!rayAtlasCoordInside(c))return 0.0;float z=float(c.z),tileY=floor((z+0.5)/uRayAtlasLabelGrid.x),tileX=z-tileY*uRayAtlasLabelGrid.x;vec2 pixel=vec2(tileX*uRayAtlasLabelDims.x+float(c.x)+0.5,tileY*uRayAtlasLabelDims.y+float(c.y)+0.5);vec4 bytes=floor(texture2D(uRayAtlasLabelAtlas,pixel/uRayAtlasLabelTextureSize)*255.0+0.5);return bytes.r+256.0*bytes.g+65536.0*bytes.b+16777216.0*bytes.a;}
      float rayAtlasLabelAtWorld(vec3 world){vec3 voxel=(uRayAtlasWorldToVoxel*vec4(world,1.0)).xyz;return rayAtlasLabelAtCoord(ivec3(floor(voxel-vec3(0.5))));}
      float roiMatchWeight(float labelValue){float a=abs(labelValue-uRayRoiCodeA)<.5?1.0:0.0,b=abs(labelValue-uRayRoiCodeB)<.5?1.0:0.0;if(abs(uRayRoiCodeA-uRayRoiCodeB)<.5)return a;return max(a*(1.0-uRayRoiMix),b*uRayRoiMix);}
      vec2 structuralAtlasUv(vec3 voxel0,float slice){float z=clamp(slice,0.0,uStructuralVolumeDims.z-1.0),tileY=floor((z+0.5)/uStructuralVolumeGrid.x),tileX=z-tileY*uStructuralVolumeGrid.x;vec2 tileOrigin=vec2(tileX*uStructuralTileSize.x,tileY*uStructuralTileSize.y),pixel=tileOrigin+vec2(1.5)+clamp(voxel0.xy,vec2(0.0),uStructuralVolumeDims.xy-vec2(1.0));return pixel/uStructuralVolumeTextureSize;}
      bool structuralVoxelInside(vec3 voxel1){vec3 voxel0=voxel1-vec3(1.0);return all(greaterThanEqual(voxel0,vec3(-0.5)))&&all(lessThanEqual(voxel0,uStructuralVolumeDims-vec3(0.5)));}
      vec4 structuralAtlasSample(vec3 voxel1){if(!structuralVoxelInside(voxel1))return vec4(0.0);vec3 p=clamp(voxel1-vec3(1.0),vec3(0.0),uStructuralVolumeDims-vec3(1.0));float z0=floor(p.z),z1=min(z0+1.0,uStructuralVolumeDims.z-1.0),fz=fract(p.z);return mix(texture2D(uStructuralScalarAtlas,structuralAtlasUv(p,z0)),texture2D(uStructuralScalarAtlas,structuralAtlasUv(p,z1)),fz);}
      float structuralScalarValue(vec4 encoded){return clamp(encoded.r+encoded.g/255.0,0.0,1.0);}
      bool intersectBox(vec3 boxOrigin,vec3 boxDirection,vec3 boxMin,vec3 boxMax,out float enterT,out float exitT){vec3 inverseDirection=vec3(abs(boxDirection.x)<1e-8?1e20:1.0/boxDirection.x,abs(boxDirection.y)<1e-8?1e20:1.0/boxDirection.y,abs(boxDirection.z)<1e-8?1e20:1.0/boxDirection.z);vec3 t0=(boxMin-boxOrigin)*inverseDirection,t1=(boxMax-boxOrigin)*inverseDirection,nearT=min(t0,t1),farT=max(t0,t1);enterT=max(max(nearT.x,nearT.y),nearT.z);exitT=min(min(farT.x,farT.y),farT.z);return exitT>=enterT;}
      bool intersectRayBox(vec3 origin,vec3 direction,out float enterT,out float exitT){return intersectBox(origin,direction,uRayBoundsMin,uRayBoundsMax,enterT,exitT)&&exitT>=max(enterT,0.0);}
      bool clipRayPlane(vec4 plane,vec3 origin,vec3 direction,inout float enterT,inout float exitT){float distanceAtOrigin=dot(plane.xyz,origin)+plane.w,denominator=dot(plane.xyz,direction);if(abs(denominator)<1e-7)return distanceAtOrigin>=0.0;float crossing=-distanceAtOrigin/denominator;if(denominator>0.0)enterT=max(enterT,crossing);else exitT=min(exitT,crossing);return exitT>=enterT;}
      float projectedDepth(vec3 world){vec4 clip=uMVP*vec4(world,1.0);return clip.z/clip.w*.5+.5;}
    `;
    let mainSource='';
    if(kind==='scientific')mainSource=`
      void main(){
        vec3 direction=uProjectionMode==1?normalize(vWorldPosition-uEyeWorld):normalize(uRayDirectionWorld),span=uRayBoundsMax-uRayBoundsMin;float diagonal=length(span),offset=max(.1,diagonal*.01);vec3 origin=uProjectionMode==1?uEyeWorld:(vWorldPosition-direction*offset);float enterT,exitT;if(!intersectRayBox(origin,direction,enterT,exitT))discard;enterT=max(enterT,0.0);if(uClipCount>0&&!clipRayPlane(uClipPlane0,origin,direction,enterT,exitT))discard;if(uClipCount>1&&!clipRayPlane(uClipPlane1,origin,direction,enterT,exitT))discard;if(uClipCount>2&&!clipRayPlane(uClipPlane2,origin,direction,enterT,exitT))discard;if(exitT-enterT<=.0001)discard;
        float featureFound=0.0,featureFirstT=exitT,featureAccAlpha=0.0,selectedShade=1.0;vec3 featurePremultiplied=vec3(0.0);int selectedClass=0;float outsideFound=0.0,outsideT=exitT,outsideValue=0.0,outsideOpacity=0.0;ivec3 outsideCell=ivec3(0);vec3 outsideEntryNormal=vec3(0.0);
        if(uRayFeatureOpacity>.0001){vec3 gridOrigin=(uWorldToVoxel*vec4(origin,1.0)).xyz-vec3(.5),gridDirection=(uWorldToVoxel*vec4(direction,0.0)).xyz;float featureEnter,featureExit;if(intersectBox(gridOrigin,gridDirection,vec3(0.0),uFragmentVolumeDims,featureEnter,featureExit)){featureEnter=max(featureEnter,enterT);featureExit=min(featureExit,exitT);if(featureExit>featureEnter+.00001){float startT=featureEnter+1e-5;vec3 gridStart=gridOrigin+gridDirection*startT,stepDirection=sign(gridDirection);ivec3 cell=ivec3(clamp(floor(gridStart),vec3(0.0),uFragmentVolumeDims-vec3(1.0)));vec3 boundary=vec3(cell)+vec3(stepDirection.x>0.0?1.0:0.0,stepDirection.y>0.0?1.0:0.0,stepDirection.z>0.0?1.0:0.0),tDelta=vec3(abs(gridDirection.x)<1e-8?1e20:abs(1.0/gridDirection.x),abs(gridDirection.y)<1e-8?1e20:abs(1.0/gridDirection.y),abs(gridDirection.z)<1e-8?1e20:abs(1.0/gridDirection.z)),tMax=vec3(abs(gridDirection.x)<1e-8?1e20:startT+(boundary.x-gridStart.x)/gridDirection.x,abs(gridDirection.y)<1e-8?1e20:startT+(boundary.y-gridStart.y)/gridDirection.y,abs(gridDirection.z)<1e-8?1e20:startT+(boundary.z-gridStart.z)/gridDirection.z);float cellEnterT=startT,slabEndT=featureExit;vec3 entryNormalVoxel=normalize(-gridDirection);float closed=0.0;
          for(int voxelStep=0;voxelStep<384;voxelStep++){if(voxelStep>=uRayFeatureMaxSteps||cellEnterT>featureExit||closed>.5)break;float cellExitT=min(featureExit,min(tMax.x,min(tMax.y,tMax.z))),nativeValue;int nativeClass;float sampleT=.5*(cellEnterT+max(cellEnterT,cellExitT)),segmentMm=max(0.0,cellExitT-cellEnterT);vec3 sampleWorld=origin+direction*sampleT,sampleVoxel=(uWorldToVoxel*vec4(sampleWorld,1.0)).xyz;bool occupied=structuralFeatureMaskAtWorld(sampleWorld)&&nativeFeatureCell(cell,nativeValue,nativeClass);float activeRoiWeight=uRayRoiFocusEnabled>.5?roiMatchWeight(rayAtlasLabelAtWorld(sampleWorld)):1.0,roiOpacity=uRayRoiFocusEnabled>.5?mix(uRayOutsideRoiOpacity,1.0,activeRoiWeight):1.0,activeEligible=uRayRoiFocusEnabled>.5?(activeRoiWeight>.001?1.0:0.0):1.0;
            if(occupied){if(activeEligible<.5&&outsideFound<.5){outsideFound=1.0;outsideT=cellEnterT;outsideValue=resolvedFeatureValue(sampleVoxel,cell,nativeClass,nativeValue);outsideOpacity=roiOpacity;outsideCell=cell;outsideEntryNormal=entryNormalVoxel;}if(featureFound<.5&&activeEligible>.5){featureFound=1.0;featureFirstT=cellEnterT;selectedClass=nativeClass;slabEndT=min(featureExit,cellEnterT+max(.5,uRayFeatureSlabMm));float value=resolvedFeatureValue(sampleVoxel,cell,selectedClass,nativeValue),strength=projectionStrength(value,selectedClass);vec3 viewDir=normalize(-direction),normal=featureBoundaryNormal(cell,selectedClass,entryNormalVoxel,viewDir);selectedShade=featureBoundaryShade(normal,viewDir);vec3 color=projectionColor(value)*selectedShade;float boundaryAlpha=clamp(uRayFeatureOpacity*roiOpacity*(.28+.64*strength),0.0,.94);featurePremultiplied=color*boundaryAlpha;featureAccAlpha=boundaryAlpha;}
              if(featureFound>.5){if(cellEnterT>slabEndT){closed=1.0;}else if(nativeClass==selectedClass&&activeEligible>.5){float value=nativeValue,strength=projectionStrength(value,selectedClass),baseAlpha=clamp(uRayFeatureOpacity*roiOpacity*(.035+.18*strength),0.0,.75),sampleAlpha=1.0-pow(max(0.0,1.0-baseAlpha),segmentMm/max(.05,uRayFeatureSliceSizeMm)),remain=1.0-featureAccAlpha;featurePremultiplied+=remain*projectionColor(value)*(.84+.16*selectedShade)*sampleAlpha;featureAccAlpha+=remain*sampleAlpha;}else if(cellEnterT>featureFirstT+1e-5){closed=1.0;}}
            }else if(featureFound>.5&&cellEnterT>featureFirstT+1e-5){closed=1.0;}
            float nextT=min(tMax.x,min(tMax.y,tMax.z));vec3 crossed=vec3(tMax.x<=nextT+1e-6?1.0:0.0,tMax.y<=nextT+1e-6?1.0:0.0,tMax.z<=nextT+1e-6?1.0:0.0);entryNormalVoxel=normalize(-stepDirection*crossed);if(crossed.x>.5){cell.x+=stepDirection.x>0.0?1:-1;tMax.x+=tDelta.x;}if(crossed.y>.5){cell.y+=stepDirection.y>0.0?1:-1;tMax.y+=tDelta.y;}if(crossed.z>.5){cell.z+=stepDirection.z>0.0?1:-1;tMax.z+=tDelta.z;}cellEnterT=max(cellExitT,nextT);if(!fragmentCoordInside(cell))break;
          }
        }}}
        if(featureFound<.5&&outsideFound>.5){featureFound=1.0;featureFirstT=outsideT;selectedClass=outsideValue<0.0?-1:1;vec3 viewDir=normalize(-direction),normal=featureBoundaryNormal(outsideCell,selectedClass,outsideEntryNormal,viewDir);float strength=projectionStrength(outsideValue,selectedClass);featureAccAlpha=clamp(uRayFeatureOpacity*outsideOpacity*(.22+.50*strength),0.0,.72);featurePremultiplied=projectionColor(outsideValue)*featureBoundaryShade(normal,viewDir)*featureAccAlpha;}
        vec4 bgAcc;float bgNearest,featureFront;integrateStructure(origin,direction,enterT,exitT,featureFirstT,bgAcc,bgNearest,featureFront);vec3 bgColor=bgAcc.a>1e-5?bgAcc.rgb/bgAcc.a:vec3(0.0),finalColor=bgColor;float finalAlpha=bgAcc.a,visibleFeatureAlpha=featureFound>.5?featureAccAlpha*pow(max(0.0,1.0-featureFront),max(.01,uRayOverlayDepth)):0.0;if(visibleFeatureAlpha>.001){vec3 featureColor=featurePremultiplied/max(featureAccAlpha,1e-5);finalColor=bgAcc.a>.001?mix(finalColor,featureColor,visibleFeatureAlpha):featureColor;finalAlpha=max(finalAlpha,visibleFeatureAlpha);}if(finalAlpha<=.002)discard;float nearestT=min(bgNearest,featureFound>.5?featureFirstT:exitT),firstDepth=nearestT<exitT?projectedDepth(origin+direction*nearestT):1.0;${depthWrite}gl_FragColor=vec4(clamp(finalColor*finalAlpha,0.0,1.0),clamp(finalAlpha,0.0,1.0));
      }
    `;
    else if(kind==='audit')mainSource=`
      bool supportAwareAuditSample(vec3 voxel1,out float value,out int klass,out float coverage){coverage=0.0;vec3 voxel0=voxel1-vec3(1.0);if(any(lessThan(voxel0,vec3(-0.5)))||any(greaterThan(voxel0,uFragmentVolumeDims-vec3(0.5)))){value=0.0;klass=0;return false;}ivec3 nearest=ivec3(floor(voxel1-vec3(.5)));float nativeValue;int nativeClass;if(!nativeFeatureCell(nearest,nativeValue,nativeClass)){value=0.0;klass=0;return false;}if(uFeatureInterpolation==0){value=nativeValue;klass=nativeClass;coverage=1.0;return true;}value=resolvedFeatureValue(voxel1,nearest,nativeClass,nativeValue);klass=nativeClass;coverage=1.0;return true;}
      void main(){vec3 direction=uProjectionMode==1?normalize(vWorldPosition-uEyeWorld):normalize(uRayDirectionWorld),span=uRayBoundsMax-uRayBoundsMin;float diagonal=length(span),offset=max(.1,diagonal*.01);vec3 origin=uProjectionMode==1?uEyeWorld:(vWorldPosition-direction*offset);float enterT,exitT;if(!intersectRayBox(origin,direction,enterT,exitT))discard;enterT=max(enterT,0.0);if(uClipCount>0&&!clipRayPlane(uClipPlane0,origin,direction,enterT,exitT))discard;if(uClipCount>1&&!clipRayPlane(uClipPlane1,origin,direction,enterT,exitT))discard;if(uClipCount>2&&!clipRayPlane(uClipPlane2,origin,direction,enterT,exitT))discard;float interval=max(0.0,exitT-enterT);if(interval<=.0001)discard;float stepMm=max(uRayStepMm,interval/max(float(uRayMaxSteps),1.0)),t=enterT+.5*stepMm,bestNeg=0.0,bestPos=0.0,bestNegT=exitT,bestPosT=exitT,bestNegValue=0.0,bestPosValue=0.0,bestNegOpacity=1.0,bestPosOpacity=1.0;for(int sampleIndex=0;sampleIndex<384;sampleIndex++){if(sampleIndex>=uRayMaxSteps||t>exitT)break;vec3 world=origin+direction*t,voxel=(uWorldToVoxel*vec4(world,1.0)).xyz;float value,coverage;int klass;if(uRayFeatureOpacity>.0001&&structuralFeatureMaskAtWorld(world)&&supportAwareAuditSample(voxel,value,klass,coverage)){float activeWeight=uRayRoiFocusEnabled>.5?roiMatchWeight(rayAtlasLabelAtWorld(world)):1.0,roiOpacity=uRayRoiFocusEnabled>.5?mix(uRayOutsideRoiOpacity,1.0,activeWeight):1.0,score=projectionStrength(value,klass)*coverage*(uRayRoiFocusEnabled>.5?mix(.015,1.0,activeWeight):1.0);if(klass<0&&score>bestNeg){bestNeg=score;bestNegT=t;bestNegValue=value;bestNegOpacity=roiOpacity;}else if(klass>0&&score>bestPos){bestPos=score;bestPosT=t;bestPosValue=value;bestPosOpacity=roiOpacity;}}t+=stepMm;}float chooseNegative=bestNeg>bestPos||(abs(bestNeg-bestPos)<1e-7&&bestNegT<=bestPosT)?1.0:0.0,score=chooseNegative>.5?bestNeg:bestPos,featureT=chooseNegative>.5?bestNegT:bestPosT,value=chooseNegative>.5?bestNegValue:bestPosValue,roiOpacity=chooseNegative>.5?bestNegOpacity:bestPosOpacity;vec4 bgAcc;float bgNearest,featureFront;integrateStructure(origin,direction,enterT,exitT,featureT,bgAcc,bgNearest,featureFront);float featureAlpha=clamp(uRayFeatureOpacity*score*(.22+.78*score)*roiOpacity,0.0,.92)*pow(max(0.0,1.0-featureFront),max(.01,uRayOverlayDepth));vec3 bgColor=bgAcc.a>1e-5?bgAcc.rgb/bgAcc.a:vec3(0.0),finalColor=bgColor;float finalAlpha=bgAcc.a;if(featureAlpha>.001){finalColor=bgAcc.a>.001?mix(finalColor,projectionColor(value),featureAlpha):projectionColor(value);finalAlpha=max(finalAlpha,featureAlpha);}if(finalAlpha<=.002)discard;float nearestT=min(bgNearest,score>0.0?featureT:exitT),firstDepth=nearestT<exitT?projectedDepth(origin+direction*nearestT):1.0;${depthWrite}gl_FragColor=vec4(clamp(finalColor*finalAlpha,0.0,1.0),clamp(finalAlpha,0.0,1.0));}
    `;
    else mainSource=`
      void main(){vec3 direction=uProjectionMode==1?normalize(vWorldPosition-uEyeWorld):normalize(uRayDirectionWorld),span=uRayBoundsMax-uRayBoundsMin;float diagonal=length(span),offset=max(.1,diagonal*.01);vec3 origin=uProjectionMode==1?uEyeWorld:(vWorldPosition-direction*offset);float enterT,exitT;if(!intersectRayBox(origin,direction,enterT,exitT))discard;enterT=max(enterT,0.0);if(uClipCount>0&&!clipRayPlane(uClipPlane0,origin,direction,enterT,exitT))discard;if(uClipCount>1&&!clipRayPlane(uClipPlane1,origin,direction,enterT,exitT))discard;if(uClipCount>2&&!clipRayPlane(uClipPlane2,origin,direction,enterT,exitT))discard;float interval=max(0.0,exitT-enterT);if(interval<=.0001)discard;float stepMm=max(uRayStepMm,interval/max(float(uRayMaxSteps),1.0)),t=enterT+.5*stepMm,maskWeight=0.0,maskT=exitT;for(int sampleIndex=0;sampleIndex<384;sampleIndex++){if(sampleIndex>=uRayMaxSteps||t>exitT)break;vec3 world=origin+direction*t,structuralVoxel=(uStructuralWorldToVoxel*vec4(world,1.0)).xyz;vec4 scalarEncoded=structuralAtlasSample(structuralVoxel);float scalarValue=structuralScalarValue(scalarEncoded),activeWeight=roiMatchWeight(rayAtlasLabelAtWorld(world));if(scalarEncoded.a>0.0&&scalarValue>.055&&activeWeight>.001){maskWeight=activeWeight;maskT=t;break;}t+=stepMm;}if(maskWeight<=.001)discard;float firstDepth=projectedDepth(origin+direction*maskT);${depthWrite}gl_FragColor=vec4(vec3(maskWeight),maskWeight);}
    `;
    const fragmentSource=(kind==='mask'?maskCommon:common)+mainSource,fs=compileShader(gl,gl.FRAGMENT_SHADER,fragmentSource),p=gl.createProgram();gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);gl.deleteShader(vs);gl.deleteShader(fs);if(!gl.getProgramParameter(p,gl.LINK_STATUS)){const message=gl.getProgramInfoLog(p)||`unknown ${kind} volume ray-casting program link error`;gl.deleteProgram(p);throw new Error(message);}p._nmHasFragDepth=hasFragDepth;p._nmKind=kind;p._nmCompileMs=nowMs()-startedAt;return p;
  }
  function intersectTriangle(origin,direction,a,b,c){
    const e1=sub(b,a),e2=sub(c,a),p=cross(direction,e2),det=dot(e1,p);
    if(Math.abs(det)<EPS)return null;
    const inv=1/det,tvec=sub(origin,a),u=dot(tvec,p)*inv;
    if(u<0||u>1)return null;
    const q=cross(tvec,e1),v=dot(direction,q)*inv;
    if(v<0||u+v>1)return null;
    const t=dot(e2,q)*inv;
    if(t<=EPS)return null;
    return {distance:t,barycentric:[1-u-v,u,v]};
  }

  function normalizeClipPlane(plane){const p=Array.isArray(plane)||ArrayBuffer.isView(plane)?Array.from(plane):[],n=normalize([finite(p[0],0),finite(p[1],0),finite(p[2],0)],[1,0,0]),scaleFactor=Math.max(EPS,Math.hypot(finite(p[0],0),finite(p[1],0),finite(p[2],0)));return [n[0],n[1],n[2],finite(p[3],0)/scaleFactor];}
  function pointInsideClipPlanes(point,planes,tolerance){const tol=Math.max(0,finite(tolerance,1e-5));return (planes||[]).every(p=>p[0]*point[0]+p[1]*point[1]+p[2]*point[2]+p[3]>=-tol);}

  function clonePresentationValue(value){
    if(Array.isArray(value))return value.map(clonePresentationValue);
    if(ArrayBuffer.isView(value))return Array.from(value);
    if(value&&typeof value==='object'){const out={};Object.keys(value).forEach(key=>{out[key]=clonePresentationValue(value[key]);});return out;}
    return value;
  }

  const COLOR_MODE_NAMES=['solid','sequential','subject_z','rate','vertex_rgb','volume_projection','atlas_boundary','atlas_label_id','volume_locator','volume_raycast','anatomy_outline','volume_slice','atlas_boundary_ribbon'];
  function colorModeName(value){const index=Math.max(0,Math.round(finite(value,0)));return COLOR_MODE_NAMES[index]||`unknown_${index}`;}
  function diagnosticResource(resource){if(!resource)return null;const out={};['key','width','height','cols','rows','tileWidth','tileHeight','gradientReference','prepareMs','uploadMs','references'].forEach(key=>{if(resource[key]!=null&&typeof resource[key]!=='object')out[key]=resource[key];});['dims','spacingMm','valueRange'].forEach(key=>{if(Array.isArray(resource[key])||ArrayBuffer.isView(resource[key]))out[key]=Array.from(resource[key]);});return out;}

  const DEFAULT_CONTEXT_ATTRIBUTES={antialias:true,alpha:true,preserveDrawingBuffer:false};
  function contextFeatureSnapshot(gl,kind){
    if(!gl)return {available:false,kind,reason:'context_unavailable'};
    if(typeof gl.isContextLost==='function'&&gl.isContextLost())return {available:false,kind,reason:'context_lost'};
    const isWebGL2=kind==='webgl2',rawMaxTextureSize=gl.getParameter(gl.MAX_TEXTURE_SIZE),rawMaxTextureUnits=gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS),rawMaxUniforms=gl.getParameter(gl.MAX_FRAGMENT_UNIFORM_VECTORS),rawMax3D=isWebGL2?gl.getParameter(gl.MAX_3D_TEXTURE_SIZE):0;
    if(rawMaxTextureSize===null||rawMaxTextureUnits===null||rawMaxUniforms===null||(isWebGL2&&rawMax3D===null))return {available:false,kind,reason:'context_unavailable'};
    const parallel=gl.getExtension('KHR_parallel_shader_compile'),fragDepth=isWebGL2||!!gl.getExtension('EXT_frag_depth');
    return {available:true,kind,reason:'ok',version:String(gl.getParameter(gl.VERSION)||''),shadingLanguageVersion:String(gl.getParameter(gl.SHADING_LANGUAGE_VERSION)||''),limits:{maxTextureSize:Number(rawMaxTextureSize),max3DTextureSize:isWebGL2?Number(rawMax3D):0,maxTextureImageUnits:Number(rawMaxTextureUnits),maxFragmentUniformVectors:Number(rawMaxUniforms)},features:{texture3D:isWebGL2,texelFetch:isWebGL2,nativeFragmentDepth:fragDepth,parallelShaderCompile:!!parallel,colorBufferFloat:!!gl.getExtension(isWebGL2?'EXT_color_buffer_float':'WEBGL_color_buffer_float'),textureFloat:isWebGL2||!!gl.getExtension('OES_texture_float'),elementIndexUint:isWebGL2||!!gl.getExtension('OES_element_index_uint')}};
  }
  function releaseProbeContext(gl){if(!gl)return;const lose=gl.getExtension('WEBGL_lose_context');if(lose&&typeof lose.loseContext==='function')lose.loseContext();}
  function probeContext(kind){if(typeof document==='undefined'||!document||typeof document.createElement!=='function')return {available:false,kind,reason:'document_unavailable'};const canvas=document.createElement('canvas');canvas.width=2;canvas.height=2;const gl=canvas.getContext(kind,DEFAULT_CONTEXT_ATTRIBUTES);if(!gl)return {available:false,kind,reason:'context_unavailable'};const report=contextFeatureSnapshot(gl,kind);releaseProbeContext(gl);return report;}
  function baseCapabilityReport(activeSnapshot){return {schema:'nm-webgl-capability-report',version:1,stage:'C18g5',migrationStatus:'active',preferredFutureContext:'webgl2',activeContext:(activeSnapshot&&activeSnapshot.kind)||'webgl1',rendererMigrationActive:!!(activeSnapshot&&activeSnapshot.kind==='webgl2'),webgl2:{available:null,kind:'webgl2',reason:'not_probed'},webgl1:activeSnapshot||{available:false,kind:'webgl1',reason:'active_context_unavailable'},active:activeSnapshot||null};}
  function probeWebGLCapabilities(){const report=baseCapabilityReport(probeContext('webgl'));report.webgl2=probeContext('webgl2');return report;}
  function createPerformanceTimings(){return {schema:'nm-webgl-performance-timing',version:1,stage:'C18g5-R3E',measurementContract:'cpu_submit_and_synchronous_api_time_only',gpuCompletionMeasured:false,contextInitMs:NaN,contextAcquireMs:NaN,volumeCapabilityProbeMs:NaN,contextFeatureProbeMs:NaN,gpuTimerProbeMs:NaN,meshProgramCompileMs:NaN,meshLocationResolveMs:NaN,contextListenerInstallMs:NaN,rendererInitPhases:{},textureUploads:{count:0,totalMs:0,totalBytes:0,lastMs:NaN,byKind:{}},frames:{interactive:{firstSubmitMs:NaN,subsequentCount:0,subsequentTotalMs:0,subsequentMaxMs:0,lastSubmitMs:NaN},offscreen:{firstSubmitMs:NaN,subsequentCount:0,subsequentTotalMs:0,subsequentMaxMs:0,lastSubmitMs:NaN}}};}


  let VOLUME_CONTEXT_SEQUENCE=0;

  function requestedVolumeShaderRole(options){
    const role=String(options&&options.volumeShaderRole||'production');
    if(role!=='production'&&role!=='audit')throw new Error(`Unknown volume shader role: ${role}`);
    return role;
  }

  class Renderer{
    constructor(canvas,options){
      if(!canvas||typeof canvas.getContext!=='function')throw new Error('A valid canvas is required.');
      this.canvas=canvas;this.options=options||{};this.volume3DRequestedShaderRole=requestedVolumeShaderRole(this.options);this.gl=null;this.contextCapabilities=null;this.performanceTimings=createPerformanceTimings();this.presentationPremultipliedAlpha=true;this.meshPrograms=new Map();this.meshProgramTimings={};this.activeMeshProgramKey='';this.meshEnabledAttribLocations=new Set();this.raycastProgram=null;this.raycastLocations=null;this.raycastPrograms=new Map();this.raycastLocationSets=new Map();this.raycastProgramTimings={};this.raycastDrawTimings={};this.raycastPhaseTexture=null;this.raycastPhaseTextureSize=64;this.renderResolutionScale=1;this.objects=new Map();this.sceneBounds={min:[-1,-1,-1],max:[1,1,1],center:[0,0,0],radius:Math.sqrt(3)};
      this.camera={projection:'orthographic',targetWorldMm:[0,0,0],orientationQuaternion:[0,0,0,1],distanceMm:5,panMm:[0,0],fovDeg:35,orbitMode:'free',azimuthRad:0,elevationRad:0};
      this.lighting={ambient:.36,diffuse:.68,specular:.10,shininess:24,space:'camera',lightDirection:[.35,.5,.78],lightColor:[1,1,1]};this.backgroundColor=[.96,.97,.98,1];this.clipPlanes=[];this.sharedFragmentVolumes=new Map();this.sharedRaycastStructuralVolumes=new Map();this.sharedAtlasVolumes=new Map();this.sharedVolume3D=new Map();this.volume3DPrograms=new Map();this.volume3DContextGeneration=1;this.volume3DContextIdentity=`nm-webgl-context-${++VOLUME_CONTEXT_SEQUENCE}`;this.volume3DProgramPollFrames=new Map();this.volume3DPrecompileRecords=new Map();this.volume3DFrameIndex=0;this.interactionQuality={active:false,resolutionScale:.58,stepMultiplier:1.45,maxStepsScale:.72,fieldReconstruction:0};this.volumePrepGenerationSequence=0;this.volumePrepReports=[];this.volumePrepClient=volumePrepClient().create({workerUrl:String(this.options.volumePrepWorkerUrl||'NMImagingVolumePrepWorker.js'),cacheLimit:10,onProfile:entry=>{this.volumePrepReports.push(clonePresentationValue(entry));if(this.volumePrepReports.length>40)this.volumePrepReports.shift();if(typeof this.options.onVolumePrepProfile==='function')this.options.onVolumePrepProfile(entry);},onError:error=>{if(typeof this.options.onVolumePrepError==='function')this.options.onVolumePrepError(error);}});this.gpuTimerExt=null;this.gpuTimerQueries=[];this.gpuTimerActive=null;this.gpuTimerStats={available:false,disjoint:false,lastMs:NaN,medianMs:NaN,p95Ms:NaN,count:0,byVariant:{}};this.atlasLabelFramebuffer=null;this.offscreenFramebuffer=null;this.disposed=false;this.contextLost=false;this.resourcesInvalid=false;this._listeners=[];this.rendererInitStartedAt=nowMs();this._initContext();
    }
    _emitRendererProfile(phase,elapsedMs,extra){
      const elapsed=Math.max(0,finite(elapsedMs,0)),totalElapsed=Math.max(0,nowMs()-finite(this.rendererInitStartedAt,nowMs())),event=Object.assign({phase:String(phase||'event'),elapsedMs:elapsed,totalElapsedMs:totalElapsed,contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,contextKind:this.isWebGL2?'webgl2':'webgl1'},extra&&typeof extra==='object'?extra:{});
      if(this.performanceTimings&&this.performanceTimings.rendererInitPhases)this.performanceTimings.rendererInitPhases[event.phase]=clonePresentationValue(event);
      if(typeof this.options.onRendererProfile==='function')this.options.onRendererProfile(event);
      return event;
    }
    _initContext(){
      const totalStarted=nowMs(),contextStarted=nowMs(),gl2=this.canvas.getContext('webgl2',DEFAULT_CONTEXT_ATTRIBUTES),gl=gl2||this.canvas.getContext('webgl',DEFAULT_CONTEXT_ATTRIBUTES)||this.canvas.getContext('experimental-webgl',DEFAULT_CONTEXT_ATTRIBUTES);
      if(!gl)throw new Error('Browser WebGL context is unavailable.');
      this.gl=gl;this.isWebGL2=!!gl2;if(!window.NMWebGLMeshPrograms||typeof window.NMWebGLMeshPrograms.compileProgram!=='function'){const error=new Error('The specialized WebGL mesh-program module is unavailable.');error.code='mesh_program_module_unavailable';throw error;}this.performanceTimings.contextAcquireMs=nowMs()-contextStarted;this._emitRendererProfile('context_acquire',this.performanceTimings.contextAcquireMs,{requestedContext:'webgl2',fallbackUsed:gl2?0:1});
      const capabilityStarted=nowMs();this.volume3DCapability=gl2?volumeRaycastGL2().capability(gl):{ok:false,reason:'webgl2_unavailable',isWebGL2:false};this.performanceTimings.volumeCapabilityProbeMs=nowMs()-capabilityStarted;this._emitRendererProfile('volume_capability_probe',this.performanceTimings.volumeCapabilityProbeMs,{available:this.volume3DCapability&&this.volume3DCapability.ok?1:0,reason:String(this.volume3DCapability&&this.volume3DCapability.reason||'')});
      const featureStarted=nowMs(),contextAttributes=gl.getContextAttributes&&gl.getContextAttributes();this.presentationPremultipliedAlpha=!contextAttributes||contextAttributes.premultipliedAlpha!==false;this.contextCapabilities=baseCapabilityReport(contextFeatureSnapshot(gl,this.isWebGL2?'webgl2':'webgl1'));this.contextCapabilities.volumeCapability=clonePresentationValue(this.volume3DCapability);this.performanceTimings.contextFeatureProbeMs=nowMs()-featureStarted;this._emitRendererProfile('context_feature_probe',this.performanceTimings.contextFeatureProbeMs,{maxTextureSize:this.contextCapabilities&&this.contextCapabilities.active&&this.contextCapabilities.active.limits?this.contextCapabilities.active.limits.maxTextureSize:NaN,maxTextureImageUnits:this.contextCapabilities&&this.contextCapabilities.active&&this.contextCapabilities.active.limits?this.contextCapabilities.active.limits.maxTextureImageUnits:NaN});
      const timerStarted=nowMs();this.gpuTimerExt=this.isWebGL2?gl.getExtension('EXT_disjoint_timer_query_webgl2'):null;this.gpuTimerStats.available=!!this.gpuTimerExt;this.performanceTimings.gpuTimerProbeMs=nowMs()-timerStarted;this._emitRendererProfile('gpu_timer_probe',this.performanceTimings.gpuTimerProbeMs,{available:this.gpuTimerExt?1:0});
      this._emitRendererProfile('mesh_program_deferred',0,{programRole:'surface_mesh',reason:'no_visible_mesh_requested'});
      const listenerStarted=nowMs(),hostTransport=typeof window!=='undefined'&&window.NM_HTML_RELAY===true?'html-relay':'browser',lost=e=>{e.preventDefault();if(this.disposed)return;this.contextLost=true;this.resourcesInvalid=true;this._emitRendererProfile('context_lost',0,{hostTransport});if(typeof this.options.onContextLost==='function')this.options.onContextLost({hostTransport,contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration});},restored=()=>{if(this.disposed)return;this.contextLost=false;this.volume3DContextGeneration+=1;this._emitRendererProfile('context_restored',0,{hostTransport});if(typeof this.options.onContextRestored==='function')this.options.onContextRestored({hostTransport,contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration});};this.canvas.addEventListener('webglcontextlost',lost,false);this.canvas.addEventListener('webglcontextrestored',restored,false);this._listeners.push(['webglcontextlost',lost],['webglcontextrestored',restored]);this.performanceTimings.contextListenerInstallMs=nowMs()-listenerStarted;
      this.performanceTimings.contextInitMs=nowMs()-totalStarted;this._emitRendererProfile('context_listener_install',this.performanceTimings.contextListenerInstallMs,{listenerCount:2});this._emitRendererProfile('complete',this.performanceTimings.contextInitMs,{meshProgramDeferred:this.meshPrograms.size?0:1,meshProgramCompileMs:this.performanceTimings.meshProgramCompileMs,contextAcquireMs:this.performanceTimings.contextAcquireMs});
    }
    _meshProgramHandleForObject(object,reason){
      if(this.disposed||this.contextLost)throw new Error('Mesh-program compilation is unavailable for the inactive renderer.');const module=window.NMWebGLMeshPrograms;if(!module||typeof module.normalizeSpec!=='function'||typeof module.compileProgram!=='function'){const error=new Error('The specialized WebGL mesh-program module is unavailable.');error.code='mesh_program_module_unavailable';throw error;}
      const spec=module.normalizeSpec(object&&object.style||{}),cached=this.meshPrograms.get(spec.key);if(cached)return cached;const started=nowMs();let handle;
      try{handle=module.compileProgram(this.gl,spec);}catch(error){this._emitRendererProfile('mesh_program_failed',nowMs()-started,{programRole:spec.role,programKey:spec.key,reason:String(reason||'visible_mesh_request'),message:error&&error.message||String(error)});throw error;}
      this.meshPrograms.set(spec.key,handle);this.meshProgramTimings[spec.key]=handle.compileMs;this.performanceTimings.meshProgramCompileMs=Object.values(this.meshProgramTimings).reduce((sum,value)=>sum+finite(value,0),0);this._emitRendererProfile('mesh_program_compile',handle.compileMs,{programRole:spec.role,programKey:spec.key,reason:String(reason||'visible_mesh_request'),newlyCompiled:1,sourceBytes:handle.identity.sourceBytes,sourceLines:handle.identity.sourceLines,sourceHash:handle.identity.sourceHash,compileStatusQueriedBeforeLinkFailure:0});this._emitRendererProfile('mesh_location_resolve',0,{programRole:spec.role,programKey:spec.key,reason:String(reason||'visible_mesh_request'),locationCount:Object.keys(handle.locations).length});return handle;
    }
    _activateMeshProgram(handle,m){
      const gl=this.gl,l=handle.locations,clip=this.clipPlanes,zero=new Float32Array([0,0,0,1]);gl.useProgram(handle.program);this.activeMeshProgramKey=handle.key;
      gl.uniformMatrix4fv(l.uMVP,false,m.mvp);gl.uniform2fv(l.uDepthCueRange,new Float32Array(m.depthCueRange));gl.uniform3fv(l.uViewDirection,new Float32Array(m.basis.forward));gl.uniform1f(l.uAmbient,clamp(finite(this.lighting.ambient,.36),0,2));gl.uniform1f(l.uDiffuse,clamp(finite(this.lighting.diffuse,.68),0,2));gl.uniform1f(l.uSpecular,clamp(finite(this.lighting.specular,.10),0,2));gl.uniform1f(l.uShininess,clamp(finite(this.lighting.shininess,24),1,128));gl.uniform3fv(l.uLightDirection,new Float32Array(resolveLightDirection(this.lighting,m.basis)));gl.uniform3fv(l.uLightColor,new Float32Array(vec3(this.lighting.lightColor,[1,1,1])));gl.uniform1i(l.uClipCount,clip.length);gl.uniform4fv(l.uClipPlane0,clip[0]?new Float32Array(clip[0]):zero);gl.uniform4fv(l.uClipPlane1,clip[1]?new Float32Array(clip[1]):zero);gl.uniform4fv(l.uClipPlane2,clip[2]?new Float32Array(clip[2]):zero);return l;
    }
    getCapabilityReport(){return clonePresentationValue(this.contextCapabilities||{schema:'nm-webgl-capability-report',version:1,stage:'C18g5',activeContext:'webgl1',migrationStatus:'capability_unavailable'});}
    gpuHealth(){
      if(this.disposed)return {ok:false,reason:'renderer_disposed',contextKind:this.isWebGL2?'webgl2':'webgl1'};
      if(this.resourcesInvalid)return {ok:false,reason:this.contextLost?'context_lost':'resources_invalid',contextKind:this.isWebGL2?'webgl2':'webgl1',contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration};
      const snapshot=contextFeatureSnapshot(this.gl,this.isWebGL2?'webgl2':'webgl1');
      if(this.contextLost||!snapshot.available)return {ok:false,reason:this.contextLost?'context_lost':String(snapshot.reason||'context_unavailable'),contextKind:this.isWebGL2?'webgl2':'webgl1',contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration};
      return {ok:true,reason:'ok',contextKind:snapshot.kind,contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,limits:clonePresentationValue(snapshot.limits)};
    }
    probeFutureCapabilities(){if(this.disposed)throw new Error('Renderer capability probing is unavailable after disposal.');if(this.contextCapabilities&&this.contextCapabilities.webgl2&&typeof this.contextCapabilities.webgl2.available==='boolean')return Promise.resolve(this.getCapabilityReport());return Promise.resolve().then(()=>{this.contextCapabilities.webgl2=probeContext('webgl2');return this.getCapabilityReport();});}
    getPerformanceReport(){this._pollGpuTimers();const report=clonePresentationValue(this.performanceTimings);report.raycastProgramCompileMs=Object.assign({},this.raycastProgramTimings);report.raycastDrawSubmitMs=clonePresentationValue(this.raycastDrawTimings);report.interactionQuality=this.getInteractionQuality();report.meshPrograms=Array.from(this.meshPrograms.entries()).reduce((out,pair)=>{const h=pair[1];out[pair[0]]={role:String(h.spec&&h.spec.role||''),spec:clonePresentationValue(h.spec||{}),sourceBytes:finite(h.identity&&h.identity.sourceBytes,NaN),sourceLines:finite(h.identity&&h.identity.sourceLines,NaN),sourceHash:String(h.identity&&h.identity.sourceHash||''),compileMs:finite(h.compileMs,NaN),locationCount:h.locations?Object.keys(h.locations).length:0};return out;},{});report.volume3DPrograms=Array.from(this.volume3DPrograms.entries()).reduce((out,pair)=>{const h=pair[1];out[pair[0]]={role:String(h.role||''),configurationSignature:String(h.configurationSignature||''),sourceBytes:finite(h.sourceBytes,NaN),sourceLines:finite(h.sourceLines,NaN),ready:!!h.ready,compileMs:finite(h.compileMs,NaN),pending:!h.ready,programId:String(h.programId||''),sourceHash:String(h.sourceHash||''),startedAt:finite(h.startedAt,NaN),completedAt:finite(h.completedAt,NaN),parallel:!!h.parallel,precompileActive:this.volume3DPrecompileRecords.has(pair[0])};return out;},{});report.volume3DContext={identity:this.volume3DContextIdentity,generation:this.volume3DContextGeneration};report.gpuTimer=clonePresentationValue(this.gpuTimerStats);report.volumePreparationWorker=this.volumePrepClient.getProfile();report.volumePreparationEvents=clonePresentationValue(this.volumePrepReports);return report;}
    updateOptions(options){this.options=Object.assign({},this.options||{},options&&typeof options==='object'?options:{});this.volume3DRequestedShaderRole=requestedVolumeShaderRole(this.options);return this;}
    adoptCanvas(placeholder,options){
      if(!placeholder||typeof placeholder.replaceWith!=='function')throw new Error('A valid destination canvas is required to adopt the prewarmed renderer.');
      const canvas=this.canvas,attributes=Array.from(placeholder.attributes||[]).map(attr=>[attr.name,attr.value]);
      Array.from(canvas.attributes||[]).forEach(attr=>canvas.removeAttribute(attr.name));attributes.forEach(pair=>canvas.setAttribute(pair[0],pair[1]));
      placeholder.replaceWith(canvas);this.updateOptions(options);return canvas;
    }
    resetSceneForSessionReuse(){
      if(this.disposed||this.contextLost)throw new Error('Results Viewer session renderer is unavailable for reuse.');
      this.objects.forEach(object=>this._deleteObjectBuffers(object));this.objects.clear();
      this._deleteAtlasLabelFramebuffer();this._deleteOffscreenFramebuffer();
      this.clipPlanes=[];this.sceneBounds={min:[-1,-1,-1],max:[1,1,1],center:[0,0,0],radius:Math.sqrt(3)};
      this.interactionQuality.active=false;this.volume3DFrameIndex=0;this.volume3DFrameStatus=null;
      if(this.gpuTimerActive&&this.gpuTimerActive.query)this.gl.deleteQuery(this.gpuTimerActive.query);this.gpuTimerQueries.forEach(item=>{if(item&&item.query)this.gl.deleteQuery(item.query);});this.gpuTimerActive=null;this.gpuTimerQueries=[];
      return {contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,programs:this.getPerformanceReport().volume3DPrograms};
    }
    getVolumeProgramStatus(variant){
      const GL2=volumeRaycastGL2(),key=GL2.normalizeProgramVariant(variant),h=this.volume3DPrograms.get(key),identity=GL2.programSourceIdentity(key);
      return h?{variant:key,role:String(h.role||identity.role||''),configurationSignature:String(h.configurationSignature||identity.configurationSignature||''),sourceBytes:finite(h.sourceBytes,identity.sourceBytes),sourceLines:finite(h.sourceLines,identity.sourceLines),contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,exists:true,ready:!!h.ready,pending:!h.ready,programId:String(h.programId||''),sourceHash:String(h.sourceHash||''),startedAt:finite(h.startedAt,NaN),completedAt:finite(h.completedAt,NaN),compileMs:finite(h.compileMs,NaN),parallel:!!h.parallel,precompileActive:this.volume3DPrecompileRecords.has(key)}:{variant:key,role:String(identity.role||''),configurationSignature:String(identity.configurationSignature||''),sourceBytes:finite(identity.sourceBytes,NaN),sourceLines:finite(identity.sourceLines,NaN),contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,exists:false,ready:false,pending:false,programId:'',sourceHash:String(identity.sourceHash||''),startedAt:NaN,completedAt:NaN,compileMs:NaN,parallel:false,precompileActive:false};
    }
    _precompileVolumeProgram(variant,metadata){
      const GL2=volumeRaycastGL2(),key=GL2.normalizeProgramVariant(variant),existing=this.volume3DPrecompileRecords.get(key);
      if(existing)return existing.promise;const current=this.getVolumeProgramStatus(key);if(current.ready)return Promise.resolve(current);
      let resolveRecord;const record={frame:0,startedAt:nowMs(),metadata:metadata||{},promise:null,resolve:null};record.promise=new Promise(resolve=>{resolveRecord=resolve;});record.resolve=resolveRecord;this.volume3DPrecompileRecords.set(key,record);
      const finish=status=>{const active=this.volume3DPrecompileRecords.get(key);if(active!==record)return;if(record.frame){if(typeof window!=='undefined'&&typeof window.cancelAnimationFrame==='function')window.cancelAnimationFrame(record.frame);else clearTimeout(record.frame);}this.volume3DPrecompileRecords.delete(key);const finalStatus=Object.assign({},status,{precompileActive:false});record.resolve(finalStatus);if(typeof this.options.onVolumeProgramProfile==='function')this.options.onVolumeProgramProfile(Object.assign({phase:'complete',reason:String(record.metadata.reason||'prewarm'),elapsedMs:nowMs()-record.startedAt},finalStatus));};
      const fail=error=>{const status=Object.assign(this.getVolumeProgramStatus(key),{ready:false,pending:false,error:error&&error.message||String(error)});this.volume3DCapability={ok:false,reason:'program_link_failed:'+key,message:status.error,isWebGL2:true};finish(status);};
      const schedule=fn=>{const raf=typeof window!=='undefined'&&typeof window.requestAnimationFrame==='function'?window.requestAnimationFrame.bind(window):cb=>setTimeout(cb,16);record.frame=raf(fn);};
      const poll=()=>{record.frame=0;if(this.disposed||this.contextLost){finish(Object.assign(this.getVolumeProgramStatus(key),{ready:false,pending:false,cancelled:true}));return;}try{const handle=this._ensureVolume3DProgram(key,false);if(handle){finish(this.getVolumeProgramStatus(key));return;}}catch(error){fail(error);return;}schedule(poll);};
      let immediate=null;try{immediate=this._ensureVolume3DProgram(key,false);}catch(error){fail(error);return record.promise;}if(typeof this.options.onVolumeProgramProfile==='function')this.options.onVolumeProgramProfile(Object.assign({phase:'start',reason:String(record.metadata.reason||'prewarm')},this.getVolumeProgramStatus(key)));if(immediate)finish(this.getVolumeProgramStatus(key));else schedule(poll);return record.promise;
    }
    precompileVolumePrograms(variants,metadata){
      if(this.disposed)return Promise.resolve({ready:false,disposed:true,programs:[]});if(!this.isWebGL2)return Promise.resolve({ready:false,reason:'webgl2_volume_unavailable',programs:[]});
      const GL2=volumeRaycastGL2(),requested=Array.from(new Set((Array.isArray(variants)?variants:['production']).map(value=>GL2.normalizeProgramVariant(value))));const startedAt=nowMs();
      return Promise.all(requested.map(key=>this._precompileVolumeProgram(key,metadata))).then(programs=>({ready:programs.every(item=>item.ready),elapsedMs:nowMs()-startedAt,programs}));
    }
    _recordTextureUpload(kind,elapsedMs,bytes){const timing=this.performanceTimings.textureUploads,key=String(kind||'unknown'),elapsed=Math.max(0,finite(elapsedMs,0)),size=Math.max(0,finite(bytes,0)),entry=timing.byKind[key]||{count:0,totalMs:0,totalBytes:0,lastMs:NaN};entry.count++;entry.totalMs+=elapsed;entry.totalBytes+=size;entry.lastMs=elapsed;timing.byKind[key]=entry;timing.count++;timing.totalMs+=elapsed;timing.totalBytes+=size;timing.lastMs=elapsed;}
    _recordFrameSubmit(kind,elapsedMs){const target=kind==='offscreen'?'offscreen':'interactive',entry=this.performanceTimings.frames[target],elapsed=Math.max(0,finite(elapsedMs,0));if(!Number.isFinite(entry.firstSubmitMs))entry.firstSubmitMs=elapsed;else{entry.subsequentCount++;entry.subsequentTotalMs+=elapsed;entry.subsequentMaxMs=Math.max(entry.subsequentMaxMs,elapsed);}entry.lastSubmitMs=elapsed;}
    _buffer(target,data){const b=this.gl.createBuffer();this.gl.bindBuffer(target,b);this.gl.bufferData(target,data,this.gl.STATIC_DRAW);return b;}
    /*
     * Purpose: acquire one immutable WebGL2 3-D volume resource from the retained renderer cache.
     * Syntax: renderer._acquireSharedVolume3DResource(key,build)
     * Inputs: deterministic cache key and a zero-argument resource builder.
     * Outputs: the retained resource with one additional reference.
     * Authority and flow: single owner of sharedVolume3D insertion/LRU touch/upload accounting.
     * Scientific/state contract: does not alter data, support, affine, thresholds, or presentation semantics.
     * Invariants: one live resource per key; cache hits never rebuild or re-upload.
     * Materialization and performance: GPU upload occurs only on a cache miss; idle resources are LRU-trimmed elsewhere.
     * Failure semantics: builder/upload failures propagate; no alternate representation is selected silently.
     * Side effects: updates reference count, LRU order, upload profiling, and sharedVolume3D.
     * Consumers and dependencies: surface native-feature projection and volume-raycast resource acquisition.
     */
    _acquireSharedVolume3DResource(key,build){
      const hit=this.sharedVolume3D.get(key);if(hit){hit.references++;hit.usedAt=nowMs();this.sharedVolume3D.delete(key);this.sharedVolume3D.set(key,hit);return hit;}
      const made=build();if(!made)return null;made.references=1;made.usedAt=nowMs();made.cacheKey=key;this.sharedVolume3D.set(key,made);this._recordTextureUpload(made.kind,finite(made.uploadMs,0),finite(made.bytes,0));return made;
    }
    /*
     * Purpose: materialize the authoritative feature value/support field as one shared native WebGL2 RG32F 3-D texture for fragment-sampled feature views.
     * Syntax: renderer._acquireNativeFeature(descriptor)
     * Inputs: aligned native feature descriptor {dims,data,support,spacingMm,worldToVoxel,key}.
     * Outputs: retained native_feature resource sampled with texelFetch/NEAREST.
     * Authority and flow: reuses NMImagingVolumePrep.prepareNativeFeature and NMVolumeRaycastGL2.uploadNativeFeature.
     * Scientific/state contract: channel R is the untouched native float value; channel G is exact logical support.
     * Invariants: no 2-D atlas packing, interpolation, smoothing, thresholding, or value reconstruction occurs here.
     * Materialization and performance: shares the same cache key/resource as the WebGL2 volume renderer; one preparation/upload per content identity.
     * Failure semantics: invalid descriptors or 3-D texture limits fail explicitly; the packed 2-D atlas is not a WebGL2 scientific fallback.
     * Side effects: may populate the prepared CPU cache and shared WebGL2 GPU-resource cache.
     * Consumers and dependencies: colorMode 5 surface projection, colorMode 8 locator planes and colorMode 11 cut slices.
     */
    _acquireNativeFeature(descriptor){
      if(!descriptor)return null;if(!this.isWebGL2)throw new Error('Native 3-D feature sampling requires WebGL2.');
      const dims=Array.from(descriptor.dims||[]).slice(0,3).map(Number),limit=Number(this.gl.getParameter(this.gl.MAX_3D_TEXTURE_SIZE)||0);if(dims.length!==3||dims.some(value=>!Number.isInteger(value)||value<1))throw new Error('Native feature dimensions are invalid.');if(limit<1||dims.some(value=>value>limit))throw new Error(`Native feature volume ${dims.join('×')} exceeds the WebGL2 3-D texture limit ${limit}.`);
      const spacing=vec3(descriptor.spacingMm,[1,1,1]).map(value=>Math.max(.05,Math.abs(value))),key=volume3DNativeKey(descriptor,spacing),prepared=volume3DPrepared(key,()=>volumePrep().prepareNativeFeature(descriptor));
      return this._acquireSharedVolume3DResource(key,()=>volumeRaycastGL2().uploadNativeFeature(this.gl,prepared));
    }
    _acquireFragmentVolume(descriptor){if(!descriptor)return null;const key=String(descriptor.key||''),cached=key?this.sharedFragmentVolumes.get(key):null;if(cached){cached.references++;return cached;}const gl=this.gl,maxTextureSize=Number(gl.getParameter(gl.MAX_TEXTURE_SIZE)||4096),packed=encodeFragmentVolumeAtlas(descriptor,maxTextureSize),texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);const uploadStarted=nowMs();gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,packed.width,packed.height,0,gl.RGBA,gl.UNSIGNED_BYTE,packed.pixels);const uploadMs=nowMs()-uploadStarted;this._recordTextureUpload('feature_volume_atlas',uploadMs,packed.pixels&&packed.pixels.byteLength||0);const resource=Object.assign({texture,references:1,key,uploadMs},packed);if(key)this.sharedFragmentVolumes.set(key,resource);return resource;}
    _releaseFragmentVolume(resource){if(!resource)return;resource.references=Math.max(0,Number(resource.references||1)-1);if(resource.references>0)return;if(resource.texture)this.gl.deleteTexture(resource.texture);if(resource.key)this.sharedFragmentVolumes.delete(resource.key);}
    _createRgbaTexture(width,height,pixels,linear,kind){const gl=this.gl,texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,linear?gl.LINEAR:gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,linear?gl.LINEAR:gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);const uploadStarted=nowMs();gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,width,height,0,gl.RGBA,gl.UNSIGNED_BYTE,pixels);const uploadMs=nowMs()-uploadStarted;this._recordTextureUpload(kind||'rgba_texture',uploadMs,pixels&&pixels.byteLength||0);return texture;}
    _acquireRaycastStructuralVolume(descriptor){if(!descriptor)return null;const key=String(descriptor.key||'raycast-structural'),cached=this.sharedRaycastStructuralVolumes.get(key);if(cached){cached.references++;return cached;}const maxTextureSize=Number(this.gl.getParameter(this.gl.MAX_TEXTURE_SIZE)||4096),packed=cachedRaycastStructuralAtlas(descriptor,maxTextureSize),scalarTexture=this._createRgbaTexture(packed.width,packed.height,packed.scalarPixels,true,'structural_scalar_atlas'),gradientTexture=this._createRgbaTexture(packed.width,packed.height,packed.gradientPixels,true,'structural_gradient_atlas'),resource=Object.assign({scalarTexture,gradientTexture,references:1},packed);delete resource.scalarPixels;delete resource.gradientPixels;this.sharedRaycastStructuralVolumes.set(key,resource);return resource;}
    _releaseRaycastStructuralVolume(resource){if(!resource)return;resource.references=Math.max(0,Number(resource.references||1)-1);if(resource.references>0)return;if(resource.scalarTexture)this.gl.deleteTexture(resource.scalarTexture);if(resource.gradientTexture)this.gl.deleteTexture(resource.gradientTexture);if(resource.key)this.sharedRaycastStructuralVolumes.delete(resource.key);}
    _acquireAtlasVolume(descriptor){if(!descriptor)return null;const key=String(descriptor.key||'atlas');let resource=this.sharedAtlasVolumes.get(key);if(resource){resource.references++;return resource;}const gl=this.gl,maxTextureSize=Number(gl.getParameter(gl.MAX_TEXTURE_SIZE)||4096),packed=encodeAtlasLabelVolume(descriptor,maxTextureSize),texture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,texture);gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);const uploadStarted=nowMs();gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,packed.width,packed.height,0,gl.RGBA,gl.UNSIGNED_BYTE,packed.pixels);const uploadMs=nowMs()-uploadStarted;this._recordTextureUpload('atlas_label_atlas',uploadMs,packed.pixels&&packed.pixels.byteLength||0);resource=Object.assign({texture,references:1,uploadMs},packed);this.sharedAtlasVolumes.set(key,resource);return resource;}
    _releaseAtlasVolume(resource){if(!resource)return;resource.references=Math.max(0,Number(resource.references||1)-1);if(resource.references>0)return;if(resource.texture)this.gl.deleteTexture(resource.texture);this.sharedAtlasVolumes.delete(resource.key);}
    /*
     * WebGL2 volumetric resources.
     *
     * Prepared from the *same descriptors the controller already passes*, so no
     * controller change is required for the geometry path. Reference counted and
     * keyed exactly like the WebGL1 resources, so the interactive viewer, the
     * montage and the video maker share one upload.
     */
    async prepareVolume3D(mesh,style,options){
      const opts=options&&typeof options==='object'?options:{},normalized=this._normalizeStyle(style),maxTextureSize=Number(this.volume3DCapability&&this.volume3DCapability.max3DTextureSize||2048),spec=volume3DPreparationSpec(mesh,normalized,maxTextureSize),generation=Number(opts.generation||0);
      if(!spec)return {mesh,style:normalized,generation,workerUsed:false,timings:{reason:'descriptors_unavailable'}};
      const startedAt=nowMs();
      /* One feature message carries the authoritative native grid only once.
         The worker derives the immutable native texture and the threshold/sigma-
         dependent presentation coverage together, then transfers both results. */
      const [structural,featureBundle]=await Promise.all([
        this.volumePrepClient.prepare('structural',spec.structuralInput,spec.structuralKey,generation),
        this.volumePrepClient.prepare('featureBundle',spec.coverageInput,`${spec.nativeKey}|${spec.coverageKey}`,generation)
      ]);
      const bundle=featureBundle.result||{};
      if(!bundle.native||!bundle.coverage)throw new Error('Volume preparation worker returned an incomplete feature bundle.');
      const preparedMesh=Object.assign({},mesh,{preparedVolume3D:{keys:{structural:spec.structuralKey,nativeFeature:spec.nativeKey,coverage:spec.coverageKey},structural:structural.result,nativeFeature:bundle.native,coverage:bundle.coverage,timings:{workerStartupMs:Math.max(finite(structural.workerStartupMs,0),finite(featureBundle.workerStartupMs,0)),mainThreadCloneMs:finite(structural.mainThreadCloneMs,0)+finite(featureBundle.mainThreadCloneMs,0),postMessageMs:finite(structural.postMessageMs,0)+finite(featureBundle.postMessageMs,0),workerPreparationMs:finite(structural.workerPreparationMs,0)+finite(featureBundle.workerPreparationMs,0),roundTripMs:Math.max(finite(structural.roundTripMs,0),finite(featureBundle.roundTripMs,0)),transferAndQueueMs:finite(structural.transferAndQueueMs,0)+finite(featureBundle.transferAndQueueMs,0),inputBytes:finite(structural.inputBytes,0)+finite(featureBundle.inputBytes,0),outputBytes:finite(structural.outputBytes,0)+finite(featureBundle.outputBytes,0),cacheHits:[structural,featureBundle].filter(x=>x.cacheHit).length,totalMainThreadWaitMs:nowMs()-startedAt}}});
      return {mesh:preparedMesh,style:normalized,generation,workerUsed:true,timings:preparedMesh.preparedVolume3D.timings};
    }
    volume3DNeedsPreparation(id,style){const o=this.objects.get(String(id));if(!o||!o.volumeDescriptors)return true;const normalized=this._normalizeStyle(style),maxTextureSize=Number(this.volume3DCapability&&this.volume3DCapability.max3DTextureSize||2048),next=volume3DCoverageKey(normalized,o.volumeDescriptors.fragmentVolume,maxTextureSize);return !o.volume3D||o.volume3DCoverageKey!==next;}
    nextVolumePreparationGeneration(){this.volumePrepGenerationSequence=Math.max(1,Math.round(finite(this.volumePrepGenerationSequence,0))+1);return this.volumePrepGenerationSequence;}
    cancelVolumePreparation(generation){if(this.volumePrepClient&&typeof this.volumePrepClient.cancelGeneration==='function')this.volumePrepClient.cancelGeneration(generation);}
    _acquireVolume3D(mesh,style){
      if(!this.isWebGL2)return null;
      if(!this.volume3DCapability||!this.volume3DCapability.ok)return null;
      if(!style||style.colorMode!==9)return null;
      const sd=mesh&&mesh.raycastStructuralVolume, fd=mesh&&mesh.fragmentVolume;
      if(!sd||!fd)return null;
      const GL2=volumeRaycastGL2(), Prep=volumePrep(), gl=this.gl;
      const maxTextureSize=Number(this.volume3DCapability.max3DTextureSize||2048),spec=volume3DPreparationSpec(mesh,style,maxTextureSize);
      if(!spec)return null;
      const featureSpacing=spec.featureSpacing,structuralKey=spec.structuralKey,nativeKey=spec.nativeKey,coverageKey=spec.coverageKey,prepared=mesh&&mesh.preparedVolume3D,preparedKeys=prepared&&prepared.keys||{};
      const atlasKey=mesh.atlasVolume?('a3d|'+String(mesh.atlasVolume.key||'atlas')):null;
      const take=(key,build)=>this._acquireSharedVolume3DResource(key,build);
      /*
       * Each stage is isolated so a failure names itself. A single try around the
       * whole block only ever reported "preparation_failed", which is not enough
       * to act on.
       */
      const stage=(name,run)=>{
        try{return run();}
        catch(error){
          this.volume3DCapability={ok:false,reason:'preparation_failed:'+name,
            message:(error&&error.message)||String(error),
            stack:String((error&&error.stack)||'').split('\n').slice(0,3).join(' | '),
            isWebGL2:true};
          throw error;
        }
      };
      let resources=null;
      try{
        const structuralPrepared=prepared&&preparedKeys.structural===structuralKey?prepared.structural:stage('structural_prepare',()=>volume3DPrepared(structuralKey,()=>Prep.prepareStructural(spec.structuralInput)));
        const structural=take(structuralKey,()=>stage('structural_upload',()=>GL2.uploadStructural(gl,structuralPrepared)));
        if(!structural)return null;
        const nativePrepared=prepared&&preparedKeys.nativeFeature===nativeKey?prepared.nativeFeature:stage('native_feature_prepare',()=>volume3DPrepared(nativeKey,()=>Prep.prepareNativeFeature(spec.nativeInput)));
        const nativeFeature=take(nativeKey,()=>stage('native_feature_upload',()=>GL2.uploadNativeFeature(gl,nativePrepared)));
        const coveragePrepared=prepared&&preparedKeys.coverage===coverageKey?prepared.coverage:stage('coverage_prepare',()=>volume3DPrepared(coverageKey,()=>Prep.prepareCoverage(spec.coverageInput)));
        const coverage=take(coverageKey,()=>coveragePrepared?stage('coverage_upload',()=>GL2.uploadCoverage(gl,coveragePrepared)):null);
        const atlas=atlasKey?take(atlasKey,()=>stage('atlas_prepare',()=>{
          const ad=mesh.atlasVolume,n=ad.dims[0]*ad.dims[1]*ad.dims[2],texels=new Float32Array(n);
          for(let i=0;i<n;i++)texels[i]=Number(ad.data[i])||0;
          return GL2.uploadAtlasLabel(gl,{key:atlasKey,dims:ad.dims.slice(),texels,bytes:texels.byteLength,
            worldToVoxelIndex:Prep._test.rowsToColumnMajor(Prep._test.worldToVoxel0Rows(ad.worldToVoxel))});
        })):null;
        resources={structural,coverage,nativeFeature,atlas};
      }catch(error){
        if(!this.volume3DCapability||String(this.volume3DCapability.reason||'').indexOf('preparation_failed')!==0){
          this.volume3DCapability={ok:false,reason:'preparation_failed:unknown',
            message:(error&&error.message)||String(error),isWebGL2:true};
        }
        if(typeof console!=='undefined'&&console&&typeof console.error==='function'){
          console.error('[NM imaging] volumetric preparation failed:',this.volume3DCapability.reason,this.volume3DCapability.message,error);
        }
        return null;
      }
      this._trimVolume3D();
      return resources;
    }
    /* Released resources are retained, not deleted: the controller calls setMesh on
       every style change, and freeing a 30 MB structural texture on each one would
       thrash the montage and video paths. Only unreferenced surplus is dropped. */
    _trimVolume3D(){
      const idle=Array.from(this.sharedVolume3D.values()).filter(r=>r.references<=0);
      const surplus=idle.length-6;
      for(let i=0;i<surplus;i++){const r=idle[i];volumeRaycastGL2().disposeResource(this.gl,r);this.sharedVolume3D.delete(r.cacheKey);}
    }
    _releaseVolume3D(resources){
      if(!resources)return;
      ['structural','coverage','nativeFeature','atlas'].forEach(name=>{
        const r=resources[name];if(!r)return;r.references=Math.max(0,Number(r.references||1)-1);
      });
      this._trimVolume3D();
    }
    /*
     * Every path that fails to produce a volume frame records why.
     *
     * Since the WebGL1 resources are no longer acquired when the WebGL2 path is
     * expected, any failure here draws nothing at all, and the controller has
     * already hidden the mesh -- so the symptom is a black canvas with no message.
     * A frame that cannot be drawn must say so.
     */
    _noteVolume3DFrame(reason,detail){
      const previous=this.volume3DFrameStatus||{};
      const key=String(reason||'ok')+'|'+String((detail&&detail.variant)||'');
      const status=Object.assign({reason:String(reason||'ok'),at:nowMs(),frame:this.volume3DFrameIndex},detail||{});
      status.repeated=previous.key===key?finite(previous.repeated,0)+1:0;
      status.key=key;
      this.volume3DFrameStatus=status;
      if(reason!=='ok'&&status.repeated===0&&typeof console!=='undefined'&&console&&typeof console.warn==='function'){
        console.warn('[NM imaging] no volume frame drawn:',status.reason,JSON.stringify(detail||{}));
      }
      return status;
    }
    getVolumeFrameStatus(){return clonePresentationValue(this.volume3DFrameStatus||{reason:'not_attempted'});}
    _volume3DProgramVariant(o){
      if(this.volume3DRequestedShaderRole==='audit')return 'still_compat';
      if(this.interactionQuality.active)return 'interaction';
      const s=o&&o.style||{},v=o&&o.volume3D,variants=!!(v&&v.structural&&v.structural.normalAuditVariantsIncluded);
      const production=s.rayStructuralFieldReconstruction===1&&s.rayStructuralTransferReconstruction===0&&s.rayStructuralNormalEstimator===5&&s.rayStructuralHitRule===0&&!variants;
      return production?'production':'audit';
    }
    _volume3DAuditReason(o){
      if(this.volume3DRequestedShaderRole==='audit')return 'explicit_renderer_audit_role';
      const v=o&&o.volume3D,variants=!!(v&&v.structural&&v.structural.normalAuditVariantsIncluded);
      return variants?'audit_normal_resources_present':'nonproduction_structural_configuration';
    }
    _ensureVolume3DProgram(variant,blocking,metadata){
      const GL2=volumeRaycastGL2(),key=GL2.normalizeProgramVariant(variant),meta=metadata&&typeof metadata==='object'?metadata:{};
      let handle=this.volume3DPrograms.get(key);
      if(!handle){
        handle=GL2.createProgram(this.gl,key);this.volume3DPrograms.set(key,handle);
        if(typeof this.options.onVolumeProgramProfile==='function')this.options.onVolumeProgramProfile({phase:'compile_start',reason:String(meta.reason||'on_demand'),auditReason:key==='audit'||key==='still_compat'?String(meta.auditReason||'explicit_audit_request'):'',newlyCompiled:true,reused:false,variant:key,role:String(handle.role||''),configurationSignature:String(handle.configurationSignature||''),sourceBytes:finite(handle.sourceBytes,NaN),sourceLines:finite(handle.sourceLines,NaN),programId:String(handle.programId||''),sourceHash:String(handle.sourceHash||''),contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,ready:false,elapsedMs:0});
      }
      if(handle.ready)return handle;
      const complete=()=>{GL2.resolveProgram(this.gl,handle);this.raycastProgramTimings['volume3d_'+key]=finite(handle.compileMs,NaN);if(!handle._nmCompileProfiled&&typeof this.options.onVolumeProgramProfile==='function'){handle._nmCompileProfiled=true;this.options.onVolumeProgramProfile({phase:'compile_complete',reason:String(meta.reason||'on_demand'),auditReason:key==='audit'||key==='still_compat'?String(meta.auditReason||'explicit_audit_request'):'',newlyCompiled:true,reused:false,variant:key,role:String(handle.role||''),configurationSignature:String(handle.configurationSignature||''),sourceBytes:finite(handle.sourceBytes,NaN),sourceLines:finite(handle.sourceLines,NaN),programId:String(handle.programId||''),sourceHash:String(handle.sourceHash||''),contextIdentity:this.volume3DContextIdentity,contextGeneration:this.volume3DContextGeneration,ready:true,elapsedMs:finite(handle.compileMs,NaN)});}return handle;};
      if(GL2.programReady(this.gl,handle))return complete();
      /* KHR_parallel_shader_compile is useful only if no synchronous link-status
         query is issued while COMPLETION_STATUS_KHR is false. A blocking request
         is therefore honoured solely on implementations without the extension. */
      if(blocking===true&&!handle.parallel)return complete();
      return null;
    }
    _scheduleVolume3DProgramRender(variant){
      const key=String(variant||'production');if(this.volume3DProgramPollFrames.has(key)||this.disposed||this.contextLost)return;
      const raf=typeof window!=='undefined'&&typeof window.requestAnimationFrame==='function'?window.requestAnimationFrame.bind(window):fn=>setTimeout(fn,16);
      const tick=()=>{this.volume3DProgramPollFrames.delete(key);if(this.disposed||this.contextLost)return;let ready=null;try{ready=this._ensureVolume3DProgram(key,false,{reason:'scheduled_completion'});}catch(error){this.volume3DCapability={ok:false,reason:'program_link_failed:'+key,message:error&&error.message||String(error),isWebGL2:true};return;}if(ready){this.render();return;}this.volume3DProgramPollFrames.set(key,raf(tick));};
      this.volume3DProgramPollFrames.set(key,raf(tick));
    }
    _beginGpuTimer(variant){
      const gl=this.gl,ext=this.gpuTimerExt;if(!ext||this.gpuTimerActive)return null;try{const query=gl.createQuery();gl.beginQuery(ext.TIME_ELAPSED_EXT,query);this.gpuTimerActive={query,variant:String(variant||'unknown')};return query;}catch(error){return null;}
    }
    _endGpuTimer(){
      const gl=this.gl,ext=this.gpuTimerExt,active=this.gpuTimerActive;if(!ext||!active)return;try{gl.endQuery(ext.TIME_ELAPSED_EXT);this.gpuTimerQueries.push(active);}catch(error){if(active.query)gl.deleteQuery(active.query);}this.gpuTimerActive=null;
    }
    _pollGpuTimers(){
      const gl=this.gl,ext=this.gpuTimerExt;if(!ext||!this.gpuTimerQueries.length)return;const disjoint=!!gl.getParameter(ext.GPU_DISJOINT_EXT);this.gpuTimerStats.disjoint=disjoint;const remaining=[];
      for(const item of this.gpuTimerQueries){let available=false;try{available=!!gl.getQueryParameter(item.query,gl.QUERY_RESULT_AVAILABLE);}catch(error){available=false;}if(!available){remaining.push(item);continue;}let ns=NaN;try{ns=Number(gl.getQueryParameter(item.query,gl.QUERY_RESULT));}catch(error){ns=NaN;}gl.deleteQuery(item.query);if(disjoint||!Number.isFinite(ns))continue;const ms=ns/1e6,group=this.gpuTimerStats.byVariant[item.variant]||{values:[],lastMs:NaN,medianMs:NaN,p95Ms:NaN,count:0};group.values.push(ms);if(group.values.length>120)group.values.shift();const sorted=group.values.slice().sort((a,b)=>a-b),quantile=q=>sorted[Math.min(sorted.length-1,Math.max(0,Math.floor((sorted.length-1)*q)))];group.lastMs=ms;group.medianMs=quantile(.5);group.p95Ms=quantile(.95);group.count++;this.gpuTimerStats.byVariant[item.variant]=group;this.gpuTimerStats.lastMs=ms;this.gpuTimerStats.medianMs=group.medianMs;this.gpuTimerStats.p95Ms=group.p95Ms;this.gpuTimerStats.count++;if(item.variant==='interaction'){if(ms>33&&this.interactionQuality.resolutionScale>.42)this.interactionQuality.resolutionScale=Math.max(.42,this.interactionQuality.resolutionScale-.05);else if(ms<20&&this.interactionQuality.resolutionScale<.68)this.interactionQuality.resolutionScale=Math.min(.68,this.interactionQuality.resolutionScale+.03);}}
      this.gpuTimerQueries=remaining;
    }
    _ensureVolume3DVertexArray(o){
      if(!this.isWebGL2||!o||typeof this.gl.createVertexArray!=='function')return null;
      if(o.volume3DVertexArray)return o.volume3DVertexArray;
      const gl=this.gl,previousVao=gl.getParameter(gl.VERTEX_ARRAY_BINDING),previousArray=gl.getParameter(gl.ARRAY_BUFFER_BINDING);
      const vao=gl.createVertexArray();
      if(!vao)throw new Error('Unable to allocate the WebGL2 volume vertex array.');
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER,o.positionBuffer);
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0,3,gl.FLOAT,false,0,0);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,o.indexBuffer);
      gl.bindVertexArray(previousVao);
      gl.bindBuffer(gl.ARRAY_BUFFER,previousArray);
      o.volume3DVertexArray=vao;
      return vao;
    }
    _auditVolumePresentation(){
      const gl=this.gl;if(!gl||this.contextLost||typeof gl.readPixels!=='function')return {ok:false,reason:'context_unavailable'};
      const width=Math.max(1,Number(gl.drawingBufferWidth)||1),height=Math.max(1,Number(gl.drawingBufferHeight)||1),sampleWidth=Math.min(256,width),sampleHeight=Math.min(256,height),x=Math.max(0,Math.floor((width-sampleWidth)/2)),y=Math.max(0,Math.floor((height-sampleHeight)/2)),pixels=new Uint8Array(sampleWidth*sampleHeight*4);
      if(typeof gl.finish==='function')gl.finish();gl.readPixels(x,y,sampleWidth,sampleHeight,gl.RGBA,gl.UNSIGNED_BYTE,pixels);
      const error=gl.getError();if(error!==gl.NO_ERROR)return {ok:false,reason:'readback_gl_error',error:Number(error)};
      const bg=this.backgroundColor.map(value=>Math.round(clamp(finite(value,0),0,1)*255)),tolerance=6;let different=0;
      for(let i=0;i<pixels.length;i+=16){if(Math.abs(pixels[i]-bg[0])>tolerance||Math.abs(pixels[i+1]-bg[1])>tolerance||Math.abs(pixels[i+2]-bg[2])>tolerance){different++;if(different>=4)break;}}
      return {ok:different>=4,reason:different>=4?'ok':'clear_only',sampleWidth,sampleHeight,differentSamples:different};
    }
    _drawVolume3DObject(o,m){
      const GL2=volumeRaycastGL2(),gl=this.gl,s=o.style,v=o.volume3D;
      const requestedVariant=this._volume3DProgramVariant(o),firstVisibleFrame=!o.volume3DVisibleFrame;let drawVariant=requestedVariant,handle=null;
      try{
        /* Production and interaction programs are requested only by an explicit
           volume-render operation and are polled non-blockingly on the retained
           visible WebGL context. Ordinary 2-D and surface use never enters this path. */
        handle=this._ensureVolume3DProgram(requestedVariant,false,{reason:'visible_volume_request',auditReason:(requestedVariant==='audit'||requestedVariant==='still_compat')?this._volume3DAuditReason(o):''});
        if(!handle&&requestedVariant==='interaction'){
          this._scheduleVolume3DProgramRender('interaction');
          drawVariant=o.volume3DLastGoodVariant||'production';
          handle=this._ensureVolume3DProgram(drawVariant,false,{reason:'interaction_reuse'});
        }
      }catch(error){
        this.volume3DCapability={ok:false,reason:'program_link_failed:'+requestedVariant,message:error.message,isWebGL2:true};
        this._noteVolume3DFrame('program_link_failed',{variant:requestedVariant,message:error&&error.message||String(error),
          stack:String((error&&error.stack)||'').split('\n').slice(0,3).join(' | '),recoverable:false});
        return false;
      }
      if(!handle){
        this._scheduleVolume3DProgramRender(requestedVariant);
        this._noteVolume3DFrame('program_pending',{variant:requestedVariant,
          blockingWasAllowed:false,
          hint:'program completion is polled; no synchronous link-status query is permitted while KHR completion is false',
          recoverable:true});
        return false;
      }
      const surfaceAlpha=Number.isFinite(s.volumeSurfaceAlpha)?s.volumeSurfaceAlpha
        :clamp(.30+.70*finite(s.rayStructuralOpacity,.55),.05,1);
      const bindingDiagnostic=GL2.draw(gl,handle,{
        mvp:m.mvp,projection:this.camera.projection,eye:m.eye,forward:m.basis.forward,
        bounds:o.bounds,clipPlanes:this.clipPlanes,
        structural:v.structural,coverage:v.coverage,nativeFeature:v.nativeFeature,
        atlasLabel:(s.rayRoiFocusEnabled&&v.atlas)?v.atlas:null,
        featureLut:this._ensureProjectionGradientTexture(o),
        structuralLut:this._ensureRaycastTransferTexture(o),
        frameIndex:this.volume3DFrameIndex,
        phaseOffset:Number.isFinite(s.rayFixedPhaseOffset)?s.rayFixedPhaseOffset:null,
        style:{
          stepMm:this.interactionQuality.active?s.rayStepMm*this.interactionQuality.stepMultiplier:s.rayStepMm,
          maxSteps:this.interactionQuality.active?Math.max(32,Math.round(s.rayMaxSteps*this.interactionQuality.maxStepsScale)):s.rayMaxSteps,
          anatomySurfaceLevel:s.volumeSurfaceLevel,anatomySurfaceAlpha:surfaceAlpha,
          anatomyInteriorAlpha:s.volumeInteriorAlpha,anatomyMaxSurfaces:s.volumeMaxSurfaces,
          anatomyOcclusion:s.volumeOcclusion,anatomyOcclusionMm:s.volumeOcclusionMm,
          /* brightness and gamma are already baked into the transfer LUT */
          brightness:1,structuralGamma:1,
          structuralFieldReconstruction:this.interactionQuality.active?this.interactionQuality.fieldReconstruction:s.rayStructuralFieldReconstruction,
          structuralTransferReconstruction:s.rayStructuralTransferReconstruction,
          structuralNormalEstimator:s.rayStructuralNormalEstimator,
          structuralHitRule:s.rayStructuralHitRule,
          structuralNormalStepMm:s.rayStructuralNormalStepMm,
          featureOpacity:s.rayFeatureOpacity,featureColorIntensity:s.rayFeatureColorIntensity,featureSlabMm:s.rayFeatureSlabMm,
          featureInteriorAlpha:finite(s.volumeFeatureInteriorAlpha,.06),
          /* Volume production presentation reconstructs colour and opacity
             within the native polarity class. Classification and reported
             values remain native; native_voxel_audit disables reconstruction. */
          featureValueShading:s.rayFeatureValueReconstruction===true,
          displayRange:s.projectionDisplayRange,
          thresholdMode:s.projectionThresholdMode,
          thresholdLow:s.projectionThresholdLow,
          thresholdHigh:s.projectionThresholdHigh,
          thresholdValue:s.projectionThresholdValue,
          roiFocusEnabled:!!s.rayRoiFocusEnabled&&!!v.atlas,
          roiCodeA:s.rayRoiCodeA,roiCodeB:s.rayRoiCodeB,roiMix:s.rayRoiMix,
          outsideRoiOpacity:s.rayOutsideRoiOpacity,roiMaskOnly:s.rayRoiMaskOnly===true
        },
        lighting:{ambient:clamp(finite(this.lighting.ambient,.22),0,2),diffuse:clamp(finite(this.lighting.diffuse,.82),0,2),
                  /* shininess 10, not 32: a 3 deg normal error swings a shininess-32 highlight
   about ten times as much as it swings the diffuse term, so a tight highlight
   magnifies normal noise instead of hiding it. MRIcroGL uses 10. */
                  specular:clamp(finite(s.volumeOcclusion,.35)*.45,0,1),shininess:clamp(finite(this.lighting.shininess,10),1,128),
                  lightDirection:resolveLightDirection(this.lighting,m.basis),lightColor:vec3(this.lighting.lightColor,[1,1,1])}
      });
      const drain=typeof GL2.drainGlErrors==='function'?limit=>GL2.drainGlErrors(gl,limit):limit=>{const out=[];for(let i=0;i<(limit||32);i++){const code=gl.getError();if(code===gl.NO_ERROR)break;out.push({code,name:String(code)});}return out;};

      gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);
      if(s.depthTest)gl.enable(gl.DEPTH_TEST);else gl.disable(gl.DEPTH_TEST);
      gl.depthMask(true);
      /*
       * R1D-R1d: surface and volume modes now share one retained WebGL context.
       * The mesh shader leaves several vertex-attribute arrays enabled. Their
       * buffers may belong to a different, smaller scene object; drawElements()
       * then validates those stale arrays against the volume proxy indices and
       * raises INVALID_OPERATION. Isolate the raycast proxy in its own WebGL2
       * VAO so only aPosition (location 0) and its EBO participate in validation.
       */
      const previousVertexArray=gl.getParameter(gl.VERTEX_ARRAY_BINDING);
      const volumeVertexArray=this._ensureVolume3DVertexArray(o);
      gl.bindVertexArray(volumeVertexArray);
      const geometryStateErrors=drain(32);

      this._pollGpuTimers();
      const timerPollErrors=drain(32);
      let timerStarted=false;
      /* The first volume frame is diagnostic. A timer-query error must not be
         allowed to contaminate attribution of the first draw. */
      if(!firstVisibleFrame){timerStarted=!!this._beginGpuTimer(drawVariant);}
      const timerBeginErrors=drain(32);
      const immediatePreDrawErrors=drain(32);
      const stateAudit={
        framebufferComplete:gl.checkFramebufferStatus(gl.FRAMEBUFFER)===gl.FRAMEBUFFER_COMPLETE,
        framebufferStatus:Number(gl.checkFramebufferStatus(gl.FRAMEBUFFER)),
        currentProgramMatches:gl.getParameter(gl.CURRENT_PROGRAM)===handle.program,
        arrayBufferBound:!!gl.getParameter(gl.ARRAY_BUFFER_BINDING),
        elementArrayBufferBound:!!gl.getParameter(gl.ELEMENT_ARRAY_BUFFER_BINDING),
        vertexAttrib0Enabled:!!gl.getVertexAttrib(0,gl.VERTEX_ATTRIB_ARRAY_ENABLED),
        dedicatedVertexArray:!!volumeVertexArray&&gl.getParameter(gl.VERTEX_ARRAY_BINDING)===volumeVertexArray,
        enabledVertexAttribs:(()=>{const out=[],count=Number(gl.getParameter(gl.MAX_VERTEX_ATTRIBS)||0);for(let i=0;i<count;i++)if(gl.getVertexAttrib(i,gl.VERTEX_ATTRIB_ARRAY_ENABLED))out.push(i);return out;})(),
        depthTestEnabled:gl.isEnabled(gl.DEPTH_TEST),
        cullFaceEnabled:gl.isEnabled(gl.CULL_FACE),
        blendEnabled:gl.isEnabled(gl.BLEND),
        depthWriteMask:!!gl.getParameter(gl.DEPTH_WRITEMASK),
        indexType:o.indexType===gl.UNSIGNED_INT?'UNSIGNED_INT':(o.indexType===gl.UNSIGNED_SHORT?'UNSIGNED_SHORT':String(o.indexType)),
        indexCount:o.indexCount,
        timerSuppressed:firstVisibleFrame
      };
      const stateAuditErrors=drain(32);

      const startedAt=nowMs();
      gl.drawElements(gl.TRIANGLES,o.indexCount,o.indexType,0);
      const drawErrors=drain(32);
      let programValidation=null,programValidationErrors=[];
      if(drawErrors.length){
        try{
          gl.validateProgram(handle.program);
          programValidation={
            attempted:true,
            valid:!!gl.getProgramParameter(handle.program,gl.VALIDATE_STATUS),
            infoLog:String(gl.getProgramInfoLog(handle.program)||'').trim()
          };
        }catch(error){
          programValidation={attempted:true,valid:false,infoLog:error&&error.message||String(error)};
        }
        programValidationErrors=drain(32);
      }
      if(timerStarted)this._endGpuTimer();
      const timerEndErrors=drain(32);
      /* Restore the renderer's previous VAO before any later mesh pass. */
      gl.bindVertexArray(previousVertexArray);
      const submitMs=nowMs()-startedAt,timing=this.raycastDrawTimings['volume3d_'+drawVariant]||{count:0,firstSubmitMs:NaN,lastSubmitMs:NaN,maxSubmitMs:0};
      timing.count+=1;if(!Number.isFinite(timing.firstSubmitMs))timing.firstSubmitMs=submitMs;
      timing.lastSubmitMs=submitMs;timing.maxSubmitMs=Math.max(timing.maxSubmitMs,submitMs);
      this.raycastDrawTimings['volume3d_'+drawVariant]=timing;

      const phaseErrors={
        inherited:bindingDiagnostic&&bindingDiagnostic.inheritedErrors||[],
        binding:bindingDiagnostic&&bindingDiagnostic.bindingErrors||[],
        bindingAudit:bindingDiagnostic&&bindingDiagnostic.auditErrors||[],
        geometryState:geometryStateErrors,
        timerPoll:timerPollErrors,
        timerBegin:timerBeginErrors,
        immediatePreDraw:immediatePreDrawErrors,
        stateAudit:stateAuditErrors,
        draw:drawErrors,
        programValidation:programValidationErrors,
        timerEnd:timerEndErrors
      };
      const samplerIssues=bindingDiagnostic&&bindingDiagnostic.samplerIssues||[];
      const presentationAudit=firstVisibleFrame&&drawErrors.length===0?this._auditVolumePresentation():null;
      const detail={
        variant:drawVariant,requestedVariant,
        drawCallIssued:true,drawSubmitted:drawErrors.length===0,
        recoverable:true,fallbackAvailable:!!(o.raycastStructuralVolume&&o.fragmentVolume),
        phaseErrors,samplerAudit:bindingDiagnostic&&bindingDiagnostic.samplerAudit||null,
        textureUnits:bindingDiagnostic&&bindingDiagnostic.textureUnits||[],
        samplerIssues,stateAudit,programValidation,presentationAudit,
        consequence:'no geometry submitted for this object; the canvas will show the clear colour'
      };
      let failureReason='';
      if(phaseErrors.binding.length||phaseErrors.bindingAudit.length)failureReason='binding_gl_error';
      else if(samplerIssues.length)failureReason='sampler_binding_invalid';
      else if(phaseErrors.geometryState.length||phaseErrors.stateAudit.length)failureReason='geometry_state_gl_error';
      else if(phaseErrors.immediatePreDraw.length)failureReason='pre_draw_gl_error';
      else if(phaseErrors.draw.length)failureReason='draw_gl_error';
      else if(presentationAudit&&!presentationAudit.ok)failureReason=presentationAudit.reason==='clear_only'?'presentation_blank':'presentation_readback_failed';
      if(failureReason){this._noteVolume3DFrame(failureReason,detail);return false;}

      o.volume3DVisibleFrame=true;o.volume3DLastGoodVariant=drawVariant;
      this._noteVolume3DFrame('ok',Object.assign({},detail,{recoverable:true,consequence:'',diagnosticWarnings:{
        inheritedErrors:phaseErrors.inherited,
        timerPollErrors:phaseErrors.timerPoll,
        timerBeginErrors:phaseErrors.timerBegin,
        timerEndErrors:phaseErrors.timerEnd
      }}));
      return true;
    }
    _deleteObjectBuffers(o){if(!this.gl||!o)return;if(o.volume3DVertexArray&&typeof this.gl.deleteVertexArray==='function'){this.gl.deleteVertexArray(o.volume3DVertexArray);o.volume3DVertexArray=null;}['positionBuffer','normalBuffer','valueBuffer','colorBuffer','alphaBuffer','indexBuffer'].forEach(k=>{if(o[k])this.gl.deleteBuffer(o[k]);});if(o.fragmentVolume)this._releaseFragmentVolume(o.fragmentVolume);if(o.nativeFeatureVolume)this._releaseVolume3D({nativeFeature:o.nativeFeatureVolume});if(o.projectionAlphaVolume)this._releaseFragmentVolume(o.projectionAlphaVolume);if(o.structuralVolume)this._releaseFragmentVolume(o.structuralVolume);if(o.raycastStructuralVolume)this._releaseRaycastStructuralVolume(o.raycastStructuralVolume);if(o.raycastTransferTexture){this.gl.deleteTexture(o.raycastTransferTexture);o.raycastTransferTexture=null;o.raycastTransferKey='';}if(o.projectionGradientTexture){this.gl.deleteTexture(o.projectionGradientTexture);o.projectionGradientTexture=null;o.projectionGradientKey='';}if(o.atlasVolume)this._releaseAtlasVolume(o.atlasVolume);if(o.volume3D){this._releaseVolume3D(o.volume3D);o.volume3D=null;}o.volumeDescriptors=null;o.volume3DCoverageKey='';}
    /**
     * Purpose: replace mutable per-vertex presentation attributes on one retained mesh without reallocating immutable geometry/index buffers.
     * Syntax: renderer.updateVertexAttributes(id, {values, colors, alphas})
     * Inputs: installed object id and any subset of Float32-compatible value/RGB/alpha arrays.
     * Outputs: true when the installed object was updated; false when the object id is absent.
     * Authority and flow: representation controllers decide whether geometry identity is unchanged; this renderer owns GPU buffer mutation.
     * Scientific/state contract: positions, normals, indices and bounds are immutable in this operation.
     * Invariants: supplied attribute lengths must exactly match the installed vertex count.
     * Materialization and performance: uses bufferSubData on existing GPU buffers; creates no buffers, textures, files or scientific arrays beyond typed conversion when required.
     * Failure semantics: attribute-length mismatch throws explicitly; no full-mesh fallback is attempted.
     * Side effects: updates resident CPU attribute references and the corresponding GPU buffer contents.
     * Consumers and dependencies: native vertex-wise surface payload refresh; safe for WebGL1/WebGL2 retained mesh objects.
     */
    updateVertexAttributes(id,attributes){
      const o=this.objects.get(String(id));if(!o)return false;const attrs=attributes&&typeof attributes==='object'?attributes:{},n=o.vertices.length/3,gl=this.gl,update=(field,buffer,expected)=>{if(!Object.prototype.hasOwnProperty.call(attrs,field))return;const source=attrs[field],data=source instanceof Float32Array?source:new Float32Array(source||[]);if(data.length!==expected)throw new Error(`Mesh ${field} update length ${data.length} does not match the installed vertex contract ${expected}.`);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferSubData(gl.ARRAY_BUFFER,0,data);o[field]=data;};update('values',o.valueBuffer,n);update('colors',o.colorBuffer,n*3);update('alphas',o.alphaBuffer,n);return true;
    }
    setMesh(id,mesh,style){
      if(this.disposed)throw new Error('Renderer is disposed.');id=String(id||'mesh');
      const vertices=mesh.vertices instanceof Float32Array?mesh.vertices:new Float32Array(mesh.vertices||[]);if(vertices.length<9||vertices.length%3)throw new Error('Mesh vertices must contain at least three 3-D points.');
      let indices;if(mesh.indices instanceof Uint32Array||mesh.indices instanceof Uint16Array)indices=mesh.indices;else indices=new Uint32Array(mesh.indices||mesh.faces||[]);if(indices.length<3||indices.length%3)throw new Error('Mesh indices must contain triangles.');
      let normals=mesh.normals instanceof Float32Array?mesh.normals:new Float32Array(mesh.normals||[]);if(normals.length!==vertices.length)normals=computeNormals(vertices,indices);
      let values=mesh.values instanceof Float32Array?mesh.values:new Float32Array(mesh.values||[]);if(values.length!==vertices.length/3)values=new Float32Array(vertices.length/3);
      let colors=mesh.colors instanceof Float32Array?mesh.colors:new Float32Array(mesh.colors||[]);if(colors.length!==vertices.length){colors=new Float32Array(vertices.length);for(let i=0;i<colors.length;i+=3){colors[i]=colors[i+1]=colors[i+2]=1;}}
      let alphas=mesh.alphas instanceof Float32Array?mesh.alphas:new Float32Array(mesh.alphas||[]);if(alphas.length!==vertices.length/3){alphas=new Float32Array(vertices.length/3);alphas.fill(1);}
      const old=this.objects.get(id),oldIncludedInSceneBounds=!!(old&&old.style&&old.style.includeInSceneBounds);if(old)this._deleteObjectBuffers(old);
      let indexType=this.gl.UNSIGNED_SHORT,indexData=indices;if(vertices.length/3>65535||maxIndex(indices)>65535){const supportsUint32=!!(this.contextCapabilities&&this.contextCapabilities.active&&this.contextCapabilities.active.features&&this.contextCapabilities.active.features.elementIndexUint);if(!supportsUint32)throw new Error('This browser WebGL context does not support uint32 mesh indices.');indexType=this.gl.UNSIGNED_INT;indexData=indices instanceof Uint32Array?indices:new Uint32Array(indices);}else indexData=indices instanceof Uint16Array?indices:new Uint16Array(indices);
      const normalizedStyle=this._normalizeStyle(style),volume3D=this._acquireVolume3D(mesh,normalizedStyle),webgl2Raycast=normalizedStyle.colorMode===9&&!!volume3D,nativeFeatureSampling=this.isWebGL2&&typeof this.gl.texImage3D==='function'&&this.gl.TEXTURE_3D!==undefined&&(normalizedStyle.colorMode===5||normalizedStyle.colorMode===8||normalizedStyle.colorMode===11);
      const object={id,vertices,normals,values,colors,alphas,indices:indexData,indexType,indexCount:indexData.length,bounds:mesh.bounds||boundsFromVertices(vertices),style:normalizedStyle,fragmentVolume:(webgl2Raycast||nativeFeatureSampling)?null:this._acquireFragmentVolume(mesh.fragmentVolume),nativeFeatureVolume:nativeFeatureSampling?this._acquireNativeFeature(mesh.fragmentVolume):null,nativeFeatureWorldToVoxel:nativeFeatureSampling&&mesh.fragmentVolume?matrixRowsToColumnMajor(mesh.fragmentVolume.worldToVoxel):null,projectionAlphaVolume:webgl2Raycast?null:this._acquireFragmentVolume(mesh.projectionAlphaVolume),structuralVolume:this._acquireFragmentVolume(mesh.structuralVolume),raycastStructuralVolume:webgl2Raycast?null:this._acquireRaycastStructuralVolume(mesh.raycastStructuralVolume),raycastTransferTexture:null,raycastTransferKey:'',projectionGradientTexture:null,projectionGradientKey:'',atlasVolume:webgl2Raycast?null:this._acquireAtlasVolume(mesh.atlasVolume),volume3D,volume3DVisibleFrame:false,volume3DLastGoodVariant:'',positionBuffer:this._buffer(this.gl.ARRAY_BUFFER,vertices),normalBuffer:this._buffer(this.gl.ARRAY_BUFFER,normals),valueBuffer:this._buffer(this.gl.ARRAY_BUFFER,values),colorBuffer:this._buffer(this.gl.ARRAY_BUFFER,colors),alphaBuffer:this._buffer(this.gl.ARRAY_BUFFER,alphas),indexBuffer:this._buffer(this.gl.ELEMENT_ARRAY_BUFFER,indexData),volume3DVertexArray:null};
      object.volumeDescriptors=(mesh&&mesh.raycastStructuralVolume&&mesh.fragmentVolume)?{
        raycastStructuralVolume:mesh.raycastStructuralVolume,fragmentVolume:mesh.fragmentVolume,atlasVolume:mesh.atlasVolume||null}:null;
      object.volume3DPreparationTimings=mesh&&mesh.preparedVolume3D?clonePresentationValue(mesh.preparedVolume3D.timings||{}):null;
      object.volume3DCoverageKey=object.volume3D?volume3DCoverageKey(object.style,mesh.fragmentVolume,Number(this.volume3DCapability&&this.volume3DCapability.max3DTextureSize||2048)):'';object.volume3DPendingCoverageKey='';
      this.objects.set(id,object);if(oldIncludedInSceneBounds||object.style.includeInSceneBounds)this.sceneBounds=mergeBounds(Array.from(this.objects.values()).filter(x=>x.style.includeInSceneBounds).map(x=>x.bounds));return object;
    }
    _normalizeStyle(style){style=style||{};const colorMode=typeof style.colorMode==='number'?style.colorMode:({solid:0,sequential:1,subject_z:2,rate:3,vertex_rgb:4,volume_projection:5,atlas_boundary:6,atlas_label_id:7,volume_locator:8,volume_raycast:9,anatomy_outline:10,volume_slice:11,atlas_boundary_ribbon:12}[String(style.colorMode||'solid')]||0),projectionDisplay=projectionExecutionParameters(style.projectionDisplayContract,colorMode);return {visible:style.visible!==false,colorMode,baseColor:vec3(style.baseColor,[.82,.84,.86]),neutralColor:vec3(style.neutralColor,[.55,.58,.62]),valueRange:(Array.isArray(style.valueRange)?style.valueRange:[0,1]).slice(0,2).map(Number),threshold:Math.max(0,finite(style.threshold,0)),scalarOpacity:clamp(finite(style.scalarOpacity,1),0,1),objectOpacity:clamp(finite(style.objectOpacity,1),0,1),brightness:clamp(finite(style.brightness,1),0,3),depthCueStrength:clamp(finite(style.depthCueStrength,0),0,1),unlit:style.unlit===true,doubleSided:style.doubleSided===true,depthWrite:style.depthWrite!==false,depthPrepass:style.depthPrepass===true,renderOrder:finite(style.renderOrder,0),includeInSceneBounds:style.includeInSceneBounds!==false,featureInterpolation:featureInterpolationCode(style.featureInterpolation),surfaceFeatureSampling:surfaceFeatureSamplingCode(style.surfaceFeatureSampling===undefined?'continuous_signed_trilinear':style.surfaceFeatureSampling),projectionAlphaMode:projectionAlphaModeCode(style.projectionAlphaMode===undefined?'uniform':style.projectionAlphaMode),projectionAlphaSelectivity:clamp(finite(style.projectionAlphaSelectivity,24),4,48),projectionAlphaMidpoint:clamp(finite(style.projectionAlphaMidpoint,.12),.02,.5),projectionAlphaLogCompression:Math.max(0,finite(style.projectionAlphaLogCompression,9)),projectionDiagnosticMode:projectionDiagnosticModeCode(style.projectionDiagnosticMode),volumeSurfaceLevel:clamp(finite(style.volumeSurfaceLevel,.38),.02,.98),volumeSurfaceAlpha:clamp(finite(style.volumeSurfaceAlpha,NaN),0,1),volumeInteriorAlpha:clamp(finite(style.volumeInteriorAlpha,.012),0,.2),volumeMaxSurfaces:clamp(Math.round(finite(style.volumeMaxSurfaces,1)),0,4),volumeOcclusion:clamp(finite(style.volumeOcclusion,.55),0,1),volumeOcclusionMm:Math.max(.2,finite(style.volumeOcclusionMm,1.6)),volumeBoundarySmoothingMm:(style.volumeBoundarySmoothingMm===null||style.volumeBoundarySmoothingMm===undefined||style.volumeBoundarySmoothingMm==='')?null:Math.max(0,finite(style.volumeBoundarySmoothingMm,0)),volumeCoverageReconstruction:String(style.volumeCoverageReconstruction||'component_signed_distance_volume_preserving')==='gaussian_audit'?'gaussian_audit':'component_signed_distance_volume_preserving',projectionSteps:clamp(Math.round(finite(style.projectionSteps,1)),1,33),projectionStepMm:Math.max(0,finite(style.projectionStepMm,0)),projectionSurfaceOffsetMm:Math.max(0,finite(style.projectionSurfaceOffsetMm,0)),projectionDisplayContract:projectionDisplay.contract,projectionThresholdMode:projectionDisplay.thresholdMode,projectionThresholdLow:projectionDisplay.thresholdLow,projectionThresholdHigh:projectionDisplay.thresholdHigh,projectionThresholdValue:projectionDisplay.thresholdValue,projectionDisplayRange:projectionDisplay.displayRange,projectionNegativeColor:vec3(style.projectionNegativeColor,[0,0,1]),projectionMidpointColor:vec3(style.projectionMidpointColor,[1,1,1]),projectionPositiveColor:vec3(style.projectionPositiveColor,[1,0,0]),projectionColorStops:projectionDisplay.colorStops,locatorStructuralWindow:(Array.isArray(style.locatorStructuralWindow)?style.locatorStructuralWindow:[0,1]).slice(0,2).map(Number),locatorOverlayOpacity:clamp(finite(style.locatorOverlayOpacity,1),0,1),surfaceOffsetMm:finite(style.surfaceOffsetMm,0),atlasBoundaryColor:vec3(style.atlasBoundaryColor,[.13,.13,.13]),atlasBoundaryOpacity:clamp(finite(style.atlasBoundaryOpacity,1),0,1),atlasBoundaryStepMm:Math.max(.05,finite(style.atlasBoundaryStepMm,.42)),atlasBoundaryProjectionMode:clamp(Math.round(finite(style.atlasBoundaryProjectionMode,1)),0,1),atlasBoundaryProjectionSteps:clamp(Math.round(finite(style.atlasBoundaryProjectionSteps,14)),1,20),atlasBoundaryProjectionStepMm:Math.max(.05,finite(style.atlasBoundaryProjectionStepMm,.5)),atlasBoundaryLineWidthPx:clamp(finite(style.atlasBoundaryLineWidthPx,1.25),.5,8),atlasBoundaryReferenceHeightPx:Math.max(1,finite(style.atlasBoundaryReferenceHeightPx,488)),atlasBoundaryDepthBias:clamp(finite(style.atlasBoundaryDepthBias,.00018),0,.002),rayStepMm:Math.max(.05,finite(style.rayStepMm,1)),rayMaxSteps:clamp(Math.round(finite(style.rayMaxSteps,288)),32,384),rayFeatureMode:rayFeatureModeCode(style.rayFeatureMode),rayFeatureSlabMm:clamp(finite(style.rayFeatureSlabMm,6),.5,24),rayFeatureValueReconstruction:style.rayFeatureValueReconstruction!==false,rayStructuralOpacity:clamp(finite(style.rayStructuralOpacity,.42),0,2),raySurfaceDefinition:clamp(finite(style.raySurfaceDefinition,.68),0,1),rayFeatureOpacity:clamp(finite(style.rayFeatureOpacity,.82),0,2),rayFeatureColorIntensity:clamp(finite(style.rayFeatureColorIntensity,1),.25,2.5),rayOverlayDepth:clamp(finite(style.rayOverlayDepth,.30),.01,1),structuralGamma:clamp(finite(style.structuralGamma,1),.25,4),rayResolutionScale:clamp(finite(style.rayResolutionScale,1),.4,1),rayStructuralFieldReconstruction:clamp(Math.round(finite(style.rayStructuralFieldReconstruction,1)),0,1),rayStructuralTransferReconstruction:clamp(Math.round(finite(style.rayStructuralTransferReconstruction,0)),0,1),rayStructuralNormalEstimator:clamp(Math.round(finite(style.rayStructuralNormalEstimator,5)),0,6),rayStructuralHitRule:clamp(Math.round(finite(style.rayStructuralHitRule,0)),0,2),rayStructuralNormalStepMm:Math.max(.05,finite(style.rayStructuralNormalStepMm,.5)),rayFixedPhaseOffset:Number.isFinite(Number(style.rayFixedPhaseOffset))?((Number(style.rayFixedPhaseOffset)%1)+1)%1:NaN,rayRoiFocusEnabled:style.rayRoiFocusEnabled===true,rayRoiCodeA:Math.max(0,finite(style.rayRoiCodeA,0)),rayRoiCodeB:Math.max(0,finite(style.rayRoiCodeB,0)),rayRoiMix:clamp(finite(style.rayRoiMix,1),0,1),rayOutsideRoiOpacity:clamp(finite(style.rayOutsideRoiOpacity,.05),0,1),rayRoiMaskOnly:style.rayRoiMaskOnly===true,atlasLabelSource:style.atlasLabelSource==='vertex'?'vertex':'volume',screenSpaceOnly:style.screenSpaceOnly===true,depthTest:style.depthTest!==false};}
    updateStyle(id,patch){const o=this.objects.get(String(id));if(!o)return;o.style=this._normalizeStyle(Object.assign({},o.style,patch||{}));this._refreshVolume3DForStyle(o);}
    /*
     * The controller restyles rather than re-meshing whenever the volume geometry
     * signature is unchanged, so setMesh is not called for a threshold or boundary
     * smoothing change. Those two do change the presentation coverage field, so the
     * resource has to be rebuilt here or the control appears dead.
     */
    _refreshVolume3DForStyle(o){
      if(!o||!o.volumeDescriptors)return;
      if(!this.isWebGL2||!this.volume3DCapability||!this.volume3DCapability.ok)return;
      const next=volume3DCoverageKey(o.style,o.volumeDescriptors.fragmentVolume,Number(this.volume3DCapability&&this.volume3DCapability.max3DTextureSize||2048));
      if(o.volume3D&&o.volume3DCoverageKey===next){o.volume3DPendingCoverageKey='';return;}
      /* Coverage preparation is asynchronous and generation-guarded by the
         controller. Keep the last valid texture during interaction instead of
         rebuilding a multi-megabyte field synchronously on every input event. */
      o.volume3DPendingCoverageKey=next;
    }
    setObjectStyle(id,style){const o=this.objects.get(String(id));if(!o)return false;o.style=this._normalizeStyle(clonePresentationValue(style||{}));this._refreshVolume3DForStyle(o);return true;}
    hasMesh(id){return this.objects.has(String(id));}
    removeMesh(id){const o=this.objects.get(String(id));if(!o)return;const affectsSceneBounds=!!(o.style&&o.style.includeInSceneBounds);this._deleteObjectBuffers(o);this.objects.delete(String(id));if(affectsSceneBounds)this.sceneBounds=mergeBounds(Array.from(this.objects.values()).filter(x=>x.style.includeInSceneBounds).map(x=>x.bounds));}
    setSceneBounds(bounds){if(bounds&&Array.isArray(bounds.min)&&Array.isArray(bounds.max))this.sceneBounds={min:vec3(bounds.min),max:vec3(bounds.max),center:vec3(bounds.center,bounds.min.map((x,i)=>(x+bounds.max[i])/2)),radius:Math.max(EPS,finite(bounds.radius,norm(sub(bounds.max,bounds.min))/2))};}
    fit(){const r=Math.max(EPS,this.sceneBounds.radius),fov=clamp(this.camera.fovDeg,10,90)*Math.PI/180;this.camera.targetWorldMm=this.sceneBounds.center.slice();this.camera.panMm=[0,0];this.camera.distanceMm=Math.max(r*2.25,r*1.22/Math.tan(fov/2));return this.getCameraState();}
    setCameraState(state){state=state||{};this.camera.projection=state.projection==='perspective'?'perspective':'orthographic';this.camera.targetWorldMm=vec3(state.targetWorldMm,this.sceneBounds.center);this.camera.distanceMm=Math.max(EPS,finite(state.distanceMm,this.camera.distanceMm));const pan=Array.isArray(state.panMm)?state.panMm:[0,0];this.camera.panMm=[finite(pan[0],0),finite(pan[1],0)];this.camera.fovDeg=clamp(finite(state.fovDeg,35),10,90);this.camera.orientationQuaternion=quatNormalize(state.orientationQuaternion);
      const hasAngles=Number.isFinite(Number(state.azimuthDeg))&&Number.isFinite(Number(state.elevationDeg));this.camera.orbitMode=state.orbitMode==='turntable'||hasAngles?'turntable':'free';if(this.camera.orbitMode==='turntable'){let angles=hasAngles?{azimuthRad:Number(state.azimuthDeg)*Math.PI/180,elevationRad:Number(state.elevationDeg)*Math.PI/180}:turntableAnglesFromQuaternion(this.camera.orientationQuaternion);this.camera.azimuthRad=wrapRadians(angles.azimuthRad);this.camera.elevationRad=clamp(angles.elevationRad,-MAX_ELEVATION_RAD,MAX_ELEVATION_RAD);this.camera.orientationQuaternion=quaternionFromTurntable(this.camera.azimuthRad,this.camera.elevationRad);}return this.getCameraState();}
    getCameraState(){return {projection:this.camera.projection,targetWorldMm:this.camera.targetWorldMm.slice(),orientationQuaternion:this.camera.orientationQuaternion.slice(),distanceMm:this.camera.distanceMm,panMm:this.camera.panMm.slice(),fovDeg:this.camera.fovDeg,orbitMode:this.camera.orbitMode,azimuthDeg:this.camera.azimuthRad*180/Math.PI,elevationDeg:this.camera.elevationRad*180/Math.PI};}
    getObjectStyle(id){const object=this.objects.get(String(id));return object?clonePresentationValue(object.style):null;}
    getDiagnosticSnapshot(){
      if(this.disposed||this.contextLost)throw new Error('Renderer diagnostics are unavailable.');
      this.render();
      const gl=this.gl,rect=this.canvas.getBoundingClientRect(),matrices=this._matrices(),debug=gl.getExtension('WEBGL_debug_renderer_info'),contextAttributes=gl.getContextAttributes()||{},objects=Array.from(this.objects.values()).map((object,insertionIndex)=>({id:object.id,insertionIndex,visible:!!object.style.visible,screenSpaceOnly:!!object.style.screenSpaceOnly,renderOrder:object.style.renderOrder,shader:object.style.colorMode===9?'volume_raycast':'mesh',colorMode:{code:object.style.colorMode,name:colorModeName(object.style.colorMode)},mesh:{vertices:object.vertices.length/3,triangles:object.indexCount/3,indexType:object.indexType===gl.UNSIGNED_INT?'uint32':'uint16',bounds:clonePresentationValue(object.bounds)},style:clonePresentationValue(object.style),resources:{fragmentVolume:diagnosticResource(object.fragmentVolume),nativeFeatureVolume:diagnosticResource(object.nativeFeatureVolume),structuralVolume:diagnosticResource(object.structuralVolume),raycastStructuralVolume:diagnosticResource(object.raycastStructuralVolume),atlasVolume:diagnosticResource(object.atlasVolume),projectionGradientTexture:!!object.projectionGradientTexture,raycastTransferTexture:!!object.raycastTransferTexture}})).sort((a,b)=>a.renderOrder-b.renderOrder||a.insertionIndex-b.insertionIndex);
      const cssWidth=Math.max(0,rect.width),cssHeight=Math.max(0,rect.height),effectivePixelRatio=[cssWidth?this.canvas.width/cssWidth:NaN,cssHeight?this.canvas.height/cssHeight:NaN];
      return {schema:'nm-webgl-renderer-diagnostic',version:2,capabilities:this.getCapabilityReport(),performance:this.getPerformanceReport(),canvas:{cssWidth,cssHeight,backingWidth:this.canvas.width,backingHeight:this.canvas.height,drawingBufferWidth:gl.drawingBufferWidth,drawingBufferHeight:gl.drawingBufferHeight,effectivePixelRatio,devicePixelRatio:finite(window.devicePixelRatio,1),renderResolutionScale:this.renderResolutionScale,options:{pixelRatio:Number.isFinite(Number(this.options.pixelRatio))?Number(this.options.pixelRatio):null,lockCanvasResolution:this.options.lockCanvasResolution===true}},context:{activeKind:this.isWebGL2?'webgl2':'webgl1',rendererMigrationActive:this.isWebGL2,attributes:clonePresentationValue(contextAttributes),vendor:String(gl.getParameter(debug?debug.UNMASKED_VENDOR_WEBGL:gl.VENDOR)||''),renderer:String(gl.getParameter(debug?debug.UNMASKED_RENDERER_WEBGL:gl.RENDERER)||''),version:String(gl.getParameter(gl.VERSION)||''),shadingLanguageVersion:String(gl.getParameter(gl.SHADING_LANGUAGE_VERSION)||'')},camera:this.getCameraState(),matrices:{mvp:Array.from(matrices.mvp),eye:Array.from(matrices.eye),target:Array.from(matrices.target),basis:clonePresentationValue(matrices.basis),aspect:matrices.aspect,fovRad:matrices.fov},lighting:clonePresentationValue(this.lighting),resolvedLightDirection:resolveLightDirection(this.lighting,matrices.basis),backgroundColor:this.backgroundColor.slice(),clipPlanes:this.getClipPlanes(),sceneBounds:clonePresentationValue(this.sceneBounds),pipeline:{depthFunction:'LEQUAL',meshBlend:['SRC_ALPHA','ONE_MINUS_SRC_ALPHA'],raycastBlend:['ONE','ONE_MINUS_SRC_ALPHA'],depthPrepass:objects.some(object=>object.visible&&object.style.depthPrepass),antialias:contextAttributes.antialias===true,raycastPhase:{algorithm:'fixed_interleaved_gradient_noise_64x64',size:this.raycastPhaseTextureSize,deterministic:true}},objects};
    }
    cameraBasis(){if(this.camera.orbitMode==='turntable')return turntableBasis(this.camera.azimuthRad,this.camera.elevationRad);const q=this.camera.orientationQuaternion,offset=quatRotate(q,[0,-1,0]),up=normalize(quatRotate(q,[0,0,1]),[0,0,1]),forward=normalize(scale(offset,-1),[0,1,0]),right=normalize(cross(forward,up),[1,0,0]),trueUp=normalize(cross(right,forward),up);return {offset,forward,right,up:trueUp};}
    orbit(dx,dy){if(this.camera.orbitMode==='turntable'){this.camera.azimuthRad=wrapRadians(this.camera.azimuthRad-finite(dx,0));this.camera.elevationRad=clamp(this.camera.elevationRad-finite(dy,0),-MAX_ELEVATION_RAD,MAX_ELEVATION_RAD);this.camera.orientationQuaternion=quaternionFromTurntable(this.camera.azimuthRad,this.camera.elevationRad);}else{const b=this.cameraBasis(),yaw=quatAxisAngle([0,0,1],-finite(dx,0)),pitch=quatAxisAngle(b.right,-finite(dy,0));this.camera.orientationQuaternion=quatMultiply(pitch,quatMultiply(yaw,this.camera.orientationQuaternion));}return this.getCameraState();}
    pan(dxMm,dyMm){this.camera.panMm[0]+=finite(dxMm,0);this.camera.panMm[1]+=finite(dyMm,0);return this.getCameraState();}
    zoom(factor){this.camera.distanceMm=clamp(this.camera.distanceMm*finite(factor,1),Math.max(EPS,this.sceneBounds.radius*.15),this.sceneBounds.radius*80);return this.getCameraState();}
    setProjection(mode){this.camera.projection=mode==='perspective'?'perspective':'orthographic';return this.getCameraState();}
    setPreset(name){const presets={posterior:[0,0],anterior:[180,0],left:[90,0],right:[-90,0],superior:[0,89.5],inferior:[180,-89.5]};if(presets[name]){this.camera.orbitMode='turntable';this.camera.azimuthRad=presets[name][0]*Math.PI/180;this.camera.elevationRad=presets[name][1]*Math.PI/180;this.camera.orientationQuaternion=quaternionFromTurntable(this.camera.azimuthRad,this.camera.elevationRad);}return this.getCameraState();}
    setLighting(lighting){this.lighting=Object.assign({},this.lighting,lighting||{});this.lighting.space=this.lighting.space==='world'?'world':'camera';this.lighting.lightDirection=vec3(this.lighting.lightDirection,[.35,.5,.78]);this.lighting.lightColor=vec3(this.lighting.lightColor,[1,1,1]).map(v=>clamp(v,0,1.5));}
    setBackgroundColor(value){const a=Array.isArray(value)?value:[.96,.97,.98,1];this.backgroundColor=[clamp(finite(a[0],.96),0,1),clamp(finite(a[1],.97),0,1),clamp(finite(a[2],.98),0,1),clamp(finite(a[3],1),0,1)];}
    setClipPlanes(planes){this.clipPlanes=(Array.isArray(planes)?planes:[]).slice(0,3).map(normalizeClipPlane);return this.getClipPlanes();}
    getClipPlanes(){return this.clipPlanes.map(p=>p.slice());}
    setInteractionQuality(active,options){const opts=options&&typeof options==='object'?options:{};this.interactionQuality={active:!!active,resolutionScale:clamp(finite(opts.resolutionScale,this.interactionQuality.resolutionScale),.4,1),stepMultiplier:clamp(finite(opts.stepMultiplier,this.interactionQuality.stepMultiplier),1,3),maxStepsScale:clamp(finite(opts.maxStepsScale,this.interactionQuality.maxStepsScale),.25,1),fieldReconstruction:clamp(Math.round(finite(opts.fieldReconstruction,this.interactionQuality.fieldReconstruction)),0,1)};return Object.assign({},this.interactionQuality);}
    getInteractionQuality(){return Object.assign({},this.interactionQuality);}
    resize(resolutionScale){this.renderResolutionScale=clamp(finite(resolutionScale,this.renderResolutionScale||1),.4,1);const requestedPixelRatio=finite(this.options&&this.options.pixelRatio,NaN),baseDpr=Number.isFinite(requestedPixelRatio)?requestedPixelRatio:finite(window.devicePixelRatio,1),dimensionScale=this.options&&this.options.lockCanvasResolution===true?1:this.renderResolutionScale,dpr=clamp(baseDpr*dimensionScale,.5,2),rect=this.canvas.getBoundingClientRect(),w=Math.max(2,Math.round(Math.max(1,rect.width)*dpr)),h=Math.max(2,Math.round(Math.max(1,rect.height)*dpr));if(this.canvas.width!==w||this.canvas.height!==h){this.canvas.width=w;this.canvas.height=h;}return {width:w,height:h,dpr,resolutionScale:this.renderResolutionScale};}
    _matrices(aspectOverride){const b=this.cameraBasis(),panWorld=add(scale(b.right,this.camera.panMm[0]),scale(b.up,this.camera.panMm[1])),target=add(this.camera.targetWorldMm,panWorld),eye=add(target,scale(b.offset,this.camera.distanceMm)),view=mat4LookAt(eye,target,b.up),aspect=Number.isFinite(Number(aspectOverride))&&Number(aspectOverride)>0?Number(aspectOverride):this.canvas.width/Math.max(1,this.canvas.height),r=Math.max(EPS,this.sceneBounds.radius),near=Math.max(.01,this.camera.distanceMm-r*2.5),far=Math.max(near+1,this.camera.distanceMm+r*2.5),fov=this.camera.fovDeg*Math.PI/180,centerDepth=dot(sub(this.sceneBounds.center,eye),b.forward),depthCueRange=[centerDepth-r,centerDepth+r];let projection;if(this.camera.projection==='perspective')projection=mat4Perspective(fov,aspect,near,far);else{const halfH=Math.max(EPS,this.camera.distanceMm*Math.tan(fov/2)),halfW=halfH*aspect;projection=mat4Ortho(-halfW,halfW,-halfH,halfH,near,far);}return {mvp:mat4Multiply(projection,view),basis:b,eye,target,aspect,fov,depthCueRange};}
    _bindObject(o,m,l){const gl=this.gl,s=o.style,nextAttribLocations=new Set([l.aPosition,l.aNormal,l.aValue,l.aColor,l.aAlpha].filter(location=>Number.isInteger(location)&&location>=0));this.meshEnabledAttribLocations.forEach(location=>{if(!nextAttribLocations.has(location))gl.disableVertexAttribArray(location);});const bindAttrib=(location,buffer,size)=>{if(!Number.isInteger(location)||location<0)return;gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.enableVertexAttribArray(location);gl.vertexAttribPointer(location,size,gl.FLOAT,false,0,0);};this.meshEnabledAttribLocations=nextAttribLocations;if(s.doubleSided)gl.disable(gl.CULL_FACE);else{gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);}bindAttrib(l.aPosition,o.positionBuffer,3);bindAttrib(l.aNormal,o.normalBuffer,3);bindAttrib(l.aValue,o.valueBuffer,1);bindAttrib(l.aColor,o.colorBuffer,3);bindAttrib(l.aAlpha,o.alphaBuffer,1);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,o.indexBuffer);gl.uniform1i(l.uColorMode,s.colorMode);gl.uniform1f(l.uSurfaceOffsetMm,s.surfaceOffsetMm);gl.uniform1i(l.uDoubleSided,s.doubleSided?1:0);gl.uniform3fv(l.uBaseColor,new Float32Array(s.baseColor));gl.uniform3fv(l.uNeutralColor,new Float32Array(s.neutralColor));gl.uniform2fv(l.uValueRange,new Float32Array(s.valueRange));gl.uniform1f(l.uThreshold,s.threshold);gl.uniform1f(l.uScalarOpacity,s.scalarOpacity);gl.uniform1f(l.uObjectOpacity,s.objectOpacity);gl.uniform1f(l.uBrightness,s.brightness);gl.uniform1f(l.uDepthCueStrength,s.depthCueStrength);gl.uniform3fv(l.uBackgroundColor,new Float32Array(this.backgroundColor.slice(0,3)));gl.uniform1i(l.uUnlit,s.unlit?1:0);gl.uniform3fv(l.uEyeWorld,new Float32Array(m.eye));if(s.colorMode===5||s.colorMode===8||s.colorMode===11){const nativeFeature=!!o.nativeFeatureVolume,fv=nativeFeature?o.nativeFeatureVolume:o.fragmentVolume;if(!fv)throw new Error('Fragment-sampled feature rendering is missing its aligned feature volume.');{gl.activeTexture(gl.TEXTURE7);if(nativeFeature){gl.bindTexture(gl.TEXTURE_3D,fv.texture);gl.uniform1i(l.uFragmentVolumeNative,7);gl.uniform3fv(l.uFragmentVolumeDims,new Float32Array(fv.dims));gl.uniformMatrix4fv(l.uWorldToVoxel,false,o.nativeFeatureWorldToVoxel);}else{gl.bindTexture(gl.TEXTURE_2D,fv.texture);gl.uniform1i(l.uFragmentVolumeAtlas,7);gl.uniform3fv(l.uFragmentVolumeDims,new Float32Array(fv.dims));gl.uniform2f(l.uFragmentVolumeGrid,fv.cols,fv.rows);gl.uniform2f(l.uFragmentVolumeTextureSize,fv.width,fv.height);gl.uniformMatrix4fv(l.uWorldToVoxel,false,fv.worldToVoxel);}gl.uniform1i(l.uFeatureInterpolation,s.featureInterpolation);gl.uniform1i(l.uSurfaceFeatureSampling,s.surfaceFeatureSampling);gl.uniform1i(l.uProjectionAlphaMode,s.projectionAlphaMode);gl.uniform1f(l.uProjectionAlphaSelectivity,s.projectionAlphaSelectivity);gl.uniform1f(l.uProjectionAlphaMidpoint,s.projectionAlphaMidpoint);gl.uniform1f(l.uProjectionAlphaLogCompression,s.projectionAlphaLogCompression);if(s.projectionAlphaMode===1){const av=o.projectionAlphaVolume;if(!av)throw new Error('Threshold-free local support alpha is missing its aligned volume.');gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_2D,av.texture);gl.uniform1i(l.uProjectionAlphaAtlas,3);gl.uniform3fv(l.uProjectionAlphaDims,new Float32Array(av.dims));gl.uniform2f(l.uProjectionAlphaGrid,av.cols,av.rows);gl.uniform2f(l.uProjectionAlphaTextureSize,av.width,av.height);}}gl.uniform1i(l.uProjectionDiagnosticMode,s.projectionDiagnosticMode);gl.uniform1i(l.uProjectionSteps,s.projectionSteps);gl.uniform1f(l.uProjectionStepMm,s.projectionStepMm);gl.uniform1f(l.uProjectionSurfaceOffsetMm,s.projectionSurfaceOffsetMm);gl.uniform1i(l.uProjectionThresholdMode,s.projectionThresholdMode);gl.uniform1f(l.uProjectionNegativeThreshold,s.projectionThresholdLow);gl.uniform1f(l.uProjectionPositiveThreshold,s.projectionThresholdHigh);gl.uniform1f(l.uProjectionSingleThreshold,s.projectionThresholdValue);gl.uniform2fv(l.uProjectionDisplayRange,new Float32Array(s.projectionDisplayRange));gl.uniform3fv(l.uProjectionNegativeColor,new Float32Array(s.projectionNegativeColor));gl.uniform3fv(l.uProjectionMidpointColor,new Float32Array(s.projectionMidpointColor));gl.uniform3fv(l.uProjectionPositiveColor,new Float32Array(s.projectionPositiveColor));gl.activeTexture(gl.TEXTURE4);gl.bindTexture(gl.TEXTURE_2D,this._ensureProjectionGradientTexture(o));gl.uniform1i(l.uProjectionGradientLut,4);}if(s.colorMode===8||s.colorMode===11){const sv=o.structuralVolume;if(!sv)throw new Error('Fragment-sampled structural plane is missing its structural volume.');gl.activeTexture(gl.TEXTURE5);gl.bindTexture(gl.TEXTURE_2D,sv.texture);gl.uniform1i(l.uStructuralVolumeAtlas,5);gl.uniform3fv(l.uStructuralVolumeDims,new Float32Array(sv.dims));gl.uniform2f(l.uStructuralVolumeGrid,sv.cols,sv.rows);gl.uniform2f(l.uStructuralVolumeTextureSize,sv.width,sv.height);gl.uniformMatrix4fv(l.uStructuralWorldToVoxel,false,sv.worldToVoxel);gl.uniform2fv(l.uStructuralWindow,new Float32Array(s.locatorStructuralWindow));gl.uniform1f(l.uLocatorOverlayOpacity,s.locatorOverlayOpacity);gl.uniform1f(l.uStructuralGamma,s.structuralGamma);}if(s.colorMode===6||(s.colorMode===7&&s.atlasLabelSource!=='vertex')){const av=o.atlasVolume;if(!av)throw new Error('Atlas-boundary rendering is missing its label volume.');gl.activeTexture(gl.TEXTURE6);gl.bindTexture(gl.TEXTURE_2D,av.texture);gl.uniform1i(l.uAtlasLabelAtlas,6);gl.uniform3fv(l.uAtlasLabelDims,new Float32Array(av.dims));gl.uniform2f(l.uAtlasLabelGrid,av.cols,av.rows);gl.uniform2f(l.uAtlasLabelTextureSize,av.width,av.height);gl.uniformMatrix4fv(l.uAtlasWorldToVoxel,false,av.worldToVoxel);}if(s.colorMode===6){gl.uniform3fv(l.uAtlasBoundaryColor,new Float32Array(s.atlasBoundaryColor));gl.uniform1f(l.uAtlasBoundaryOpacity,s.atlasBoundaryOpacity);gl.uniform1f(l.uAtlasBoundaryStepMm,s.atlasBoundaryStepMm);gl.uniform1i(l.uAtlasBoundaryProjectionMode,s.atlasBoundaryProjectionMode);gl.uniform1i(l.uAtlasBoundaryProjectionSteps,s.atlasBoundaryProjectionSteps);gl.uniform1f(l.uAtlasBoundaryProjectionStepMm,s.atlasBoundaryProjectionStepMm);}if(s.colorMode===12){const viewport=gl.getParameter(gl.VIEWPORT),referenceHeight=Math.max(1,s.atlasBoundaryReferenceHeightPx),lineWidth=clamp(s.atlasBoundaryLineWidthPx*Math.max(1,viewport[3])/referenceHeight,.5,8);gl.uniform2f(l.uViewport,Math.max(1,viewport[2]),Math.max(1,viewport[3]));gl.uniform1f(l.uLineWidthPx,lineWidth);gl.uniform1f(l.uDepthBias,s.atlasBoundaryDepthBias);gl.uniform3fv(l.uAtlasBoundaryColor,new Float32Array(s.atlasBoundaryColor));gl.uniform1f(l.uAtlasBoundaryOpacity,s.atlasBoundaryOpacity);}}
    _projectionGradientPixels(style){const stops=Array.isArray(style.projectionColorStops)?style.projectionColorStops:null;if(!stops||!stops.length)throw new Error('Volume projection requires canonical colour-gradient stops.');return colorGradient().lutRgba8(stops,256);}
    _ensureProjectionGradientTexture(o){const key=JSON.stringify(o.style.projectionColorStops||[o.style.projectionNegativeColor,o.style.projectionMidpointColor,o.style.projectionPositiveColor]);if(o.projectionGradientTexture&&o.projectionGradientKey===key)return o.projectionGradientTexture;if(o.projectionGradientTexture){this.gl.deleteTexture(o.projectionGradientTexture);o.projectionGradientTexture=null;o.projectionGradientKey='';}const texture=this._createRgbaTexture(256,1,this._projectionGradientPixels(o.style),true);o.projectionGradientTexture=texture;o.projectionGradientKey=key;return texture;}
    _ensureRaycastProgram(kind){
      kind=kind==='audit'||kind==='mask'?kind:'scientific';
      if(this.raycastPrograms.has(kind)){this.raycastProgram=this.raycastPrograms.get(kind);this.raycastLocations=this.raycastLocationSets.get(kind);return this.raycastProgram;}
      const gl=this.gl,p=createRaycastProgram(gl,kind),names=['aPosition','uMVP','uProjectionMode','uEyeWorld','uRayDirectionWorld','uRayBoundsMin','uRayBoundsMax','uRayStepMm','uRayMaxSteps','uRayFeatureMaxSteps','uRayFeatureMode','uRayFeatureSlabMm','uRayFeatureOpacity','uRayOverlayDepth','uRaySliceSizeMm','uRayFeatureSliceSizeMm','uRayLightDirection','uRayLightColor','uRayViewRight','uRayViewUp','uRayViewToward','uRayAmbient','uRayDiffuse','uRaySpecular','uRayShininess','uRaySurfaceDefinition','uRaySurfaceLow','uRaySurfaceHigh','uRaySurfaceExponent','uRayInteriorFactor','uRayCoarseStepMultiplier','uRayPhaseTexture','uRayPhaseTextureSize','uClipCount','uClipPlane0','uClipPlane1','uClipPlane2','uStructuralScalarAtlas','uStructuralGradientAtlas','uStructuralTransferLut','uStructuralVolumeDims','uStructuralVolumeGrid','uStructuralVolumeTextureSize','uStructuralTileSize','uStructuralWorldToVoxel','uFragmentVolumeAtlas','uFragmentVolumeDims','uFragmentVolumeGrid','uFragmentVolumeTextureSize','uWorldToVoxel','uFeatureInterpolation','uProjectionThresholdMode','uProjectionNegativeThreshold','uProjectionPositiveThreshold','uProjectionSingleThreshold','uProjectionDisplayRange','uProjectionNegativeColor','uProjectionMidpointColor','uProjectionPositiveColor','uProjectionGradientLut','uRayAtlasLabelAtlas','uRayAtlasLabelDims','uRayAtlasLabelGrid','uRayAtlasLabelTextureSize','uRayAtlasWorldToVoxel','uRayRoiFocusEnabled','uRayRoiCodeA','uRayRoiCodeB','uRayRoiMix','uRayOutsideRoiOpacity','uRayRoiMaskOnly'],locations={};
      names.forEach(name=>{locations[name]=name==='aPosition'?gl.getAttribLocation(p,name):gl.getUniformLocation(p,name);});this.raycastPrograms.set(kind,p);this.raycastLocationSets.set(kind,locations);this.raycastProgramTimings[kind]=finite(p._nmCompileMs,NaN);this.raycastProgram=p;this.raycastLocations=locations;return p;
    }
    volumeRaycastCapability(structuralDescriptor,featureDescriptor,atlasDescriptor,style){
      const health=this.gpuHealth();if(!health.ok)return {ok:false,reason:health.reason,isWebGL2:this.isWebGL2};
      /*
       * WebGL2 path. gl_FragDepth is core in GLSL ES 3.00, so EXT_frag_depth does
       * not exist and probing for it always fails -- that probe is a WebGL1 test.
       * The 2-D atlas packing checks below are also WebGL1-specific: with 3-D
       * textures the limit is MAX_3D_TEXTURE_SIZE per axis, not a tiled 2-D
       * layout, and a volume that cannot be packed into an atlas may still be
       * perfectly renderable. Compiling the WebGL1 monolith here would be pure
       * waste on this path, so it is skipped too.
       */
      if(this.isWebGL2&&this.volume3DCapability&&this.volume3DCapability.ok){
        const max3D=Number(this.volume3DCapability.max3DTextureSize||0);
        const units3D=Number(this.volume3DCapability.maxTextureImageUnits||0);
        const productionStyle=style&&style.rayStructuralFieldReconstruction===1&&style.rayStructuralTransferReconstruction===0&&style.rayStructuralNormalEstimator===5&&style.rayStructuralHitRule===0;
        const variant=this.volume3DRequestedShaderRole==='audit'?'still_compat':(productionStyle?'production':'audit'),requiredUnits=variant==='production'?7:9;
        const out={ok:false,maxTextureSize:max3D,max3DTextureSize:max3D,maxTextureUnits:units3D,requiredTextureUnits:requiredUnits,
                   fragmentDepth:true,programKind:'volume3d_'+variant,programCompileMs:NaN,
                   structural:null,feature:null,atlas:null,reason:'',contextKind:'webgl2'};
        if(units3D<requiredUnits){out.reason='insufficient_texture_units';return out;}
        const fits=d=>{const dims=Array.from((d&&d.dims)||[]).slice(0,3).map(Number);
          return dims.length===3&&dims.every(v=>Number.isFinite(v)&&v>=1&&v<=max3D);};
        if(!fits(structuralDescriptor)){out.reason='structural_volume_exceeds_max_3d_texture_size';return out;}
        if(!fits(featureDescriptor)){out.reason='feature_volume_exceeds_max_3d_texture_size';return out;}
        if(atlasDescriptor&&!fits(atlasDescriptor)){out.reason='atlas_volume_exceeds_max_3d_texture_size';return out;}
        try{
          const handle=this._ensureVolume3DProgram(variant,false,{reason:'capability_visible_volume_request',auditReason:(variant==='audit'||variant==='still_compat')?(this.volume3DRequestedShaderRole==='audit'?'explicit_renderer_audit_role':'nonproduction_structural_configuration'):''});
          out.programKind='volume3d_'+variant;out.programCompileMs=finite(handle&&handle.compileMs,NaN);
          out.programPending=!handle;
          if(!handle)this._scheduleVolume3DProgramRender(variant);
        }catch(error){out.reason=(error&&error.message)||String(error);return out;}
        out.structural={dims:Array.from(structuralDescriptor.dims||[])};
        out.feature={dims:Array.from(featureDescriptor.dims||[])};
        if(atlasDescriptor)out.atlas={dims:Array.from(atlasDescriptor.dims||[])};
        out.ok=true;out.reason='ok';return out;
      }
      const gl=this.gl,rawMaxTextureSize=gl.getParameter(gl.MAX_TEXTURE_SIZE),rawMaxUnits=gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS);if(rawMaxTextureSize===null||rawMaxUnits===null)return {ok:false,reason:'context_unavailable',isWebGL2:this.isWebGL2};const maxTextureSize=Number(rawMaxTextureSize),maxUnits=Number(rawMaxUnits),fragDepth=this.isWebGL2||!!gl.getExtension('EXT_frag_depth'),requiredUnits=7,programKind=raycastProgramKind(style),result={ok:false,maxTextureSize,maxTextureUnits:maxUnits,requiredTextureUnits:requiredUnits,fragmentDepth:fragDepth,programKind,programCompileMs:NaN,structural:null,feature:null,atlas:null,reason:''};if(maxUnits<requiredUnits){result.reason='insufficient_texture_units';return result;}if(!fragDepth){result.reason='fragment_depth_unavailable';return result;}try{result.structural=choosePaddedAtlasLayout(structuralDescriptor&&structuralDescriptor.dims,maxTextureSize,1);result.feature=chooseAtlasLayout(featureDescriptor&&featureDescriptor.dims,maxTextureSize);if(atlasDescriptor)result.atlas=chooseAtlasLayout(atlasDescriptor.dims,maxTextureSize);const program=this._ensureRaycastProgram(programKind);result.programCompileMs=finite(program&&program._nmCompileMs,NaN);result.ok=true;result.reason='ok';return result;}catch(err){result.reason=err&&err.message||String(err);return result;}
    }
    _bindFragmentRaycastVolume(resource,textureUnit,locations){const gl=this.gl;if(!resource)throw new Error('Authoritative feature volume is unavailable for GPU ray casting.');gl.activeTexture(gl.TEXTURE0+textureUnit);gl.bindTexture(gl.TEXTURE_2D,resource.texture);gl.uniform1i(locations.uFragmentVolumeAtlas,textureUnit);gl.uniform3fv(locations.uFragmentVolumeDims,new Float32Array(resource.dims));gl.uniform2f(locations.uFragmentVolumeGrid,resource.cols,resource.rows);gl.uniform2f(locations.uFragmentVolumeTextureSize,resource.width,resource.height);}
    _ensureRaycastPhaseTexture(){if(this.raycastPhaseTexture)return this.raycastPhaseTexture;const generated=raycastPhaseTexturePixels(this.raycastPhaseTextureSize),texture=this._createRgbaTexture(generated.size,generated.size,generated.pixels,false,'raycast_phase_texture');this.gl.bindTexture(this.gl.TEXTURE_2D,texture);this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_WRAP_S,this.gl.REPEAT);this.gl.texParameteri(this.gl.TEXTURE_2D,this.gl.TEXTURE_WRAP_T,this.gl.REPEAT);this.raycastPhaseTexture=texture;this.raycastPhaseTextureSize=generated.size;return texture;}
    _ensureRaycastTransferTexture(o){const key=[o.style.rayStructuralOpacity,o.style.brightness,o.style.structuralGamma].join('|');if(o.raycastTransferTexture&&o.raycastTransferKey===key)return o.raycastTransferTexture;if(o.raycastTransferTexture){this.gl.deleteTexture(o.raycastTransferTexture);o.raycastTransferTexture=null;o.raycastTransferKey='';}const texture=this._createRgbaTexture(256,1,raycastTransferLutPixels(o.style),true);o.raycastTransferTexture=texture;o.raycastTransferKey=key;return texture;}
    _drawRaycastObject(o,m){
      if(o.volume3D){
        if(this._drawVolume3DObject(o,m))return;
        if(!o.raycastStructuralVolume||!o.fragmentVolume){
          /* nothing was drawn and there is no WebGL1 resource to fall back to */
          const prior=this.volume3DFrameStatus||{};
          this._noteVolume3DFrame(prior.reason&&prior.reason!=='ok'?prior.reason:'volume_draw_failed',
            Object.assign({},prior,{fallbackAvailable:false,
              consequence:'no geometry submitted for this object; the canvas will show the clear colour'}));
          return;
        }
      }
      const gl=this.gl,s=o.style,kind=raycastProgramKind(s),p=this._ensureRaycastProgram(kind),l=this.raycastLocationSets.get(kind),sv=o.raycastStructuralVolume,fv=o.fragmentVolume,zero=new Float32Array([0,0,0,1]);if(!sv||!fv)throw new Error('MRIcroGL-inspired GPU volume ray casting requires a prepared structural volume and authoritative native feature volume.');gl.useProgram(p);gl.uniformMatrix4fv(l.uMVP,false,m.mvp);gl.uniform1i(l.uProjectionMode,this.camera.projection==='perspective'?1:0);gl.uniform3fv(l.uEyeWorld,new Float32Array(m.eye));gl.uniform3fv(l.uRayDirectionWorld,new Float32Array(m.basis.forward));gl.uniform3fv(l.uRayBoundsMin,new Float32Array(o.bounds.min));gl.uniform3fv(l.uRayBoundsMax,new Float32Array(o.bounds.max));gl.uniform1f(l.uRayStepMm,s.rayStepMm);gl.uniform1i(l.uRayMaxSteps,s.rayMaxSteps);gl.uniform1i(l.uRayFeatureMaxSteps,Math.min(384,Math.max(1,Math.ceil(fv.dims[0]+fv.dims[1]+fv.dims[2]+3))));gl.uniform1i(l.uRayFeatureMode,s.rayFeatureMode);gl.uniform1f(l.uRayFeatureSlabMm,s.rayFeatureSlabMm);gl.uniform1f(l.uRayFeatureOpacity,s.rayFeatureOpacity);gl.uniform1f(l.uRayOverlayDepth,s.rayOverlayDepth);gl.uniform1f(l.uRaySliceSizeMm,Math.max(.05,Math.min.apply(null,sv.spacingMm||[1])));gl.uniform1f(l.uRayFeatureSliceSizeMm,Math.max(.05,Math.min.apply(null,fv.spacingMm||[1])));gl.uniform3fv(l.uRayLightDirection,new Float32Array(resolveLightDirection(this.lighting,m.basis)));gl.uniform3fv(l.uRayLightColor,new Float32Array(vec3(this.lighting.lightColor,[1,1,1])));gl.uniform3fv(l.uRayViewRight,new Float32Array(m.basis.right));gl.uniform3fv(l.uRayViewUp,new Float32Array(m.basis.up));gl.uniform3fv(l.uRayViewToward,new Float32Array(m.basis.offset));gl.uniform1f(l.uRayAmbient,clamp(finite(this.lighting.ambient,.36),0,2));gl.uniform1f(l.uRayDiffuse,clamp(finite(this.lighting.diffuse,.68),0,2));gl.uniform1f(l.uRaySpecular,clamp(finite(this.lighting.specular,.10),0,2));gl.uniform1f(l.uRayShininess,clamp(finite(this.lighting.shininess,24),1,128));const surface=structuralSurfaceParameters(s);gl.uniform1f(l.uRaySurfaceDefinition,surface.definition);gl.uniform1f(l.uRaySurfaceLow,surface.gradientLow);gl.uniform1f(l.uRaySurfaceHigh,surface.gradientHigh);gl.uniform1f(l.uRaySurfaceExponent,surface.gradientExponent);gl.uniform1f(l.uRayInteriorFactor,surface.interiorFactor);gl.uniform1f(l.uRayCoarseStepMultiplier,surface.coarseStepMultiplier);const clip=this.clipPlanes;gl.uniform1i(l.uClipCount,clip.length);gl.uniform4fv(l.uClipPlane0,clip[0]?new Float32Array(clip[0]):zero);gl.uniform4fv(l.uClipPlane1,clip[1]?new Float32Array(clip[1]):zero);gl.uniform4fv(l.uClipPlane2,clip[2]?new Float32Array(clip[2]):zero);
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,sv.scalarTexture);gl.uniform1i(l.uStructuralScalarAtlas,0);gl.activeTexture(gl.TEXTURE1);gl.bindTexture(gl.TEXTURE_2D,sv.gradientTexture);gl.uniform1i(l.uStructuralGradientAtlas,1);gl.activeTexture(gl.TEXTURE2);gl.bindTexture(gl.TEXTURE_2D,this._ensureRaycastTransferTexture(o));gl.uniform1i(l.uStructuralTransferLut,2);gl.activeTexture(gl.TEXTURE6);gl.bindTexture(gl.TEXTURE_2D,this._ensureRaycastPhaseTexture());gl.uniform1i(l.uRayPhaseTexture,6);gl.uniform2f(l.uRayPhaseTextureSize,this.raycastPhaseTextureSize,this.raycastPhaseTextureSize);gl.uniform3fv(l.uStructuralVolumeDims,new Float32Array(sv.dims));gl.uniform2f(l.uStructuralVolumeGrid,sv.cols,sv.rows);gl.uniform2f(l.uStructuralVolumeTextureSize,sv.width,sv.height);gl.uniform2f(l.uStructuralTileSize,sv.tileWidth,sv.tileHeight);gl.uniformMatrix4fv(l.uStructuralWorldToVoxel,false,sv.worldToVoxel);this._bindFragmentRaycastVolume(fv,3,l);gl.uniformMatrix4fv(l.uWorldToVoxel,false,fv.worldToVoxel);gl.uniform1i(l.uFeatureInterpolation,s.featureInterpolation);gl.uniform1i(l.uProjectionThresholdMode,s.projectionThresholdMode);gl.uniform1f(l.uProjectionNegativeThreshold,s.projectionThresholdLow);gl.uniform1f(l.uProjectionPositiveThreshold,s.projectionThresholdHigh);gl.uniform1f(l.uProjectionSingleThreshold,s.projectionThresholdValue);gl.uniform2fv(l.uProjectionDisplayRange,new Float32Array(s.projectionDisplayRange));gl.uniform3fv(l.uProjectionNegativeColor,new Float32Array(s.projectionNegativeColor));gl.uniform3fv(l.uProjectionMidpointColor,new Float32Array(s.projectionMidpointColor));gl.uniform3fv(l.uProjectionPositiveColor,new Float32Array(s.projectionPositiveColor));gl.activeTexture(gl.TEXTURE4);gl.bindTexture(gl.TEXTURE_2D,this._ensureProjectionGradientTexture(o));gl.uniform1i(l.uProjectionGradientLut,4);const roiFocus=!!s.rayRoiFocusEnabled&&!!o.atlasVolume;gl.uniform1f(l.uRayRoiFocusEnabled,roiFocus?1:0);gl.uniform1f(l.uRayRoiCodeA,s.rayRoiCodeA);gl.uniform1f(l.uRayRoiCodeB,s.rayRoiCodeB);gl.uniform1f(l.uRayRoiMix,s.rayRoiMix);gl.uniform1f(l.uRayOutsideRoiOpacity,s.rayOutsideRoiOpacity);gl.uniform1f(l.uRayRoiMaskOnly,roiFocus&&s.rayRoiMaskOnly?1:0);if(roiFocus){const av=o.atlasVolume;gl.activeTexture(gl.TEXTURE5);gl.bindTexture(gl.TEXTURE_2D,av.texture);gl.uniform1i(l.uRayAtlasLabelAtlas,5);gl.uniform3fv(l.uRayAtlasLabelDims,new Float32Array(av.dims));gl.uniform2f(l.uRayAtlasLabelGrid,av.cols,av.rows);gl.uniform2f(l.uRayAtlasLabelTextureSize,av.width,av.height);gl.uniformMatrix4fv(l.uRayAtlasWorldToVoxel,false,av.worldToVoxel);}gl.enable(gl.CULL_FACE);gl.cullFace(gl.BACK);if(s.depthTest)gl.enable(gl.DEPTH_TEST);else gl.disable(gl.DEPTH_TEST);gl.depthMask(!!p._nmHasFragDepth);gl.bindBuffer(gl.ARRAY_BUFFER,o.positionBuffer);gl.enableVertexAttribArray(l.aPosition);gl.vertexAttribPointer(l.aPosition,3,gl.FLOAT,false,0,0);gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,o.indexBuffer);const drawStartedAt=nowMs();gl.drawElements(gl.TRIANGLES,o.indexCount,o.indexType,0);const drawSubmitMs=nowMs()-drawStartedAt,drawTiming=this.raycastDrawTimings[kind]||{count:0,firstSubmitMs:NaN,lastSubmitMs:NaN,maxSubmitMs:0};drawTiming.count+=1;if(!Number.isFinite(drawTiming.firstSubmitMs))drawTiming.firstSubmitMs=drawSubmitMs;drawTiming.lastSubmitMs=drawSubmitMs;drawTiming.maxSubmitMs=Math.max(drawTiming.maxSubmitMs,drawSubmitMs);this.raycastDrawTimings[kind]=drawTiming;
    }

    raycastResourceInfo(id){
      const o=this.objects.get(String(id||'volumeRaycast'));
      if(!o)return null;
      const volume3D=o.volume3D||null,sv=volume3D&&volume3D.structural||o.raycastStructuralVolume,fv=volume3D&&volume3D.nativeFeature||o.fragmentVolume;
      if(!sv)return null;
      const activeVariant=volume3D?this._volume3DProgramVariant(o):'',drawnVariant=volume3D&&o.volume3DLastGoodVariant?o.volume3DLastGoodVariant:activeVariant,programKind=volume3D?'volume3d_'+drawnVariant:raycastProgramKind(o.style),program=volume3D?this.volume3DPrograms.get(drawnVariant):this.raycastPrograms.get(programKind),drawTiming=this.raycastDrawTimings[programKind]||null,variants=!!(volume3D&&volume3D.structural&&volume3D.structural.normalAuditVariantsIncluded),requested=o.style?o.style.rayStructuralNormalEstimator:5;
      let actual=requested;if((actual===1||actual===2||actual===4)&&!variants)actual=5;
      return {key:String(sv.key||''),dims:Array.from(sv.dims||[]),atlas:sv.width&&sv.height?[sv.width,sv.height]:null,grid:sv.cols&&sv.rows?[sv.cols,sv.rows]:null,spacingMm:Array.from(sv.spacingMm||[1,1,1]),featureSpacingMm:Array.from(fv&&fv.spacingMm||[1,1,1]),featureMode:o.style?o.style.rayFeatureMode:0,featureSlabMm:o.style?o.style.rayFeatureSlabMm:NaN,featureValuePresentation:o.style&&o.style.rayFeatureValueReconstruction===true?'polarity_restricted_reconstructed':'native_voxel_audit',featureAnatomyMask:volume3D?'rendered_structural_volume_level':'structural_transfer_support',volumePreparationTimings:clonePresentationValue(o.volume3DPreparationTimings||null),surfaceDefinition:o.style?o.style.raySurfaceDefinition:NaN,surfaceParameters:o.style?structuralSurfaceParameters(o.style):null,featureMaxSteps:fv&&fv.dims?Math.min(384,Math.max(1,Math.ceil(fv.dims[0]+fv.dims[1]+fv.dims[2]+3))):NaN,programKind,programCompileMs:finite(program&&program._nmCompileMs,finite(program&&program.compileMs,NaN)),programPending:!!(volume3D&&program&&!program.ready),programCompileMsByKind:Object.assign({},this.raycastProgramTimings),drawSubmitTiming:drawTiming?Object.assign({},drawTiming):null,gradientReference:finite(sv.gradientReference,NaN),gradientKernel:String(sv.gradientKernel||''),gradientPreblurSigmaMm:finite(sv.gradientPreblurSigmaMm,NaN),gradientSourceField:String(sv.gradientSourceField||''),crossingField:String(sv.crossingField||''),activeFieldReconstruction:o.style?o.style.rayStructuralFieldReconstruction:0,activeFieldReconstructionName:o.style&&o.style.rayStructuralFieldReconstruction===1?'cubic_bspline_scalar_times_support':'trilinear_scalar_times_support',activeTransferReconstruction:o.style?o.style.rayStructuralTransferReconstruction:0,activeTransferReconstructionName:o.style&&o.style.rayStructuralTransferReconstruction===1?'cubic_bspline_scalar':'trilinear_scalar',normalAuditVariantsIncluded:variants,scalarSobelKernel:String(sv.scalarSobelKernel||''),fieldSobelKernel:String(sv.fieldSobelKernel||''),fieldSobelSourceField:String(sv.fieldSobelSourceField||''),fieldSupportSigmaMm:finite(sv.fieldSupportSigmaMm,NaN),activeNormalEstimator:actual,activeNormalEstimatorName:['stored_central_trilinear','stored_scalar_sobel_trilinear','stored_field_sobel_trilinear','direct_crossing_field_central','support_adaptive_hybrid','packed_tricubic_rgba8','direct_crossing_field_8corner'][actual]||'packed_tricubic_rgba8',activeNormalHitRule:(()=>{const rule=o.style?o.style.rayStructuralHitRule:0;return ['exact_refined_hit','strongest_bracket','one_step_previous_carry'][rule]||'exact_refined_hit';})(),normalStepMm:o.style?o.style.rayStructuralNormalStepMm:NaN,normalPhaseOffset:o.style&&Number.isFinite(o.style.rayFixedPhaseOffset)?o.style.rayFixedPhaseOffset:NaN,prepareMs:finite(sv.prepareMs,NaN),fragmentDepth:volume3D?true:!!(program&&program._nmHasFragDepth),phaseTexture:{algorithm:'fixed_interleaved_gradient_noise_64x64',size:this.raycastPhaseTextureSize,deterministic:true,phaseRangeFineSteps:[0,1]},structuralContract:volume3D?'C18g5_R1D_R1a_firefox_visible_frame_compat':'C18g4b-R1_monotonic_surface_definition',renderPath:volume3D?'webgl2_volume3d':'webgl1_dda',contextKind:this.isWebGL2?'webgl2':'webgl1',volume3DReason:this.volume3DCapability?String(this.volume3DCapability.reason||''):'not_probed',volume3DFrameReason:this.volume3DFrameStatus?String(this.volume3DFrameStatus.reason||''):'not_attempted',volume3DFrameVariant:this.volume3DFrameStatus?String(this.volume3DFrameStatus.variant||''):'',volume3DFrameMessage:this.volume3DFrameStatus?String(this.volume3DFrameStatus.message||this.volume3DFrameStatus.hint||''):'',volume3DFrameRepeated:this.volume3DFrameStatus?finite(this.volume3DFrameStatus.repeated,0):0,volume3DMessage:this.volume3DCapability?String(this.volume3DCapability.message||''):'',boundarySmoothingMm:volume3D&&volume3D.coverage?volume3D.coverage.boundarySmoothingMm:NaN,coverageReconstruction:volume3D&&volume3D.coverage?String(volume3D.coverage.coverageReconstruction||''):'',valueSmoothingMm:volume3D&&volume3D.coverage?finite(volume3D.coverage.valueSmoothingMm,NaN):NaN,nativeRecoveryMaxMm:volume3D&&volume3D.coverage?finite(volume3D.coverage.nativeRecoveryMaxMm,NaN):NaN,representedFraction:volume3D&&volume3D.coverage?finite(volume3D.coverage.representedFraction,1):NaN,representedVoxelFraction:volume3D&&volume3D.coverage?finite(volume3D.coverage.representedVoxelFraction,1):NaN,coverageDims:volume3D&&volume3D.coverage?volume3D.coverage.dims.slice():null,volume3DProgramCompileMs:finite(program&&program.compileMs,NaN),legacyResourcesBuilt:!!(o.raycastStructuralVolume||o.fragmentVolume||o.atlasVolume),interactionQuality:this.getInteractionQuality(),requestedProgramKind:volume3D?'volume3d_'+activeVariant:programKind,visibleFrameSubmitted:!!(o&&o.volume3DVisibleFrame)};
    }
    /* Console diagnostic: renderer.volumeDiagnostics() reports why a path was chosen. */
    volumeDiagnostics(id){
      const o=this.objects.get(String(id||'volumeRaycast'));
      return {schema:'nm-volume-render-diagnostic',version:1,
        contextKind:this.isWebGL2?'webgl2':'webgl1',
        modulesLoaded:{NMVolumeRaycastGL2:!!(typeof window!=='undefined'&&window.NMVolumeRaycastGL2),NMImagingVolumePrep:!!(typeof window!=='undefined'&&window.NMImagingVolumePrep)},
        capability:this.volume3DCapability?clonePresentationValue(this.volume3DCapability):null,
        objectPresent:!!o,
        volume3DActive:!!(o&&o.volume3D),
        descriptorsRetained:!!(o&&o.volumeDescriptors),
        coverage:o&&o.volume3D&&o.volume3D.coverage?{dims:o.volume3D.coverage.dims.slice(),sigmaMm:o.volume3D.coverage.boundarySmoothingMm,reconstruction:String(o.volume3D.coverage.coverageReconstruction||''),valueSmoothingMm:finite(o.volume3D.coverage.valueSmoothingMm,NaN),filtered:o.volume3D.coverage.filtered,representedFraction:finite(o.volume3D.coverage.representedFraction,1),representedVoxelFraction:finite(o.volume3D.coverage.representedVoxelFraction,1)}:null,
        coverageKey:o?String(o.volume3DCoverageKey||''):'',
        legacyProgramsCompiled:this.raycastPrograms.size,
        volume3DProgramReady:Array.from(this.volume3DPrograms.values()).some(program=>program&&program.ready),
        requestedProgramVariant:o&&o.volume3D?this._volume3DProgramVariant(o):'',
        lastDrawProgramVariant:o&&o.volume3DLastGoodVariant||'',
        frameStatus:clonePresentationValue(this.volume3DFrameStatus||{reason:'not_attempted'}),
        visibleFrameSubmitted:!!(o&&o.volume3DVisibleFrame),
        programStatus:Array.from(this.volume3DPrograms.entries()).reduce((out,pair)=>{out[pair[0]]={ready:!!pair[1].ready,compileMs:finite(pair[1].compileMs,NaN)};return out;},{}),
        style:o?{volumeSurfaceLevel:o.style.volumeSurfaceLevel,volumeBoundarySmoothingMm:o.style.volumeBoundarySmoothingMm,volumeSurfaceAlpha:o.style.volumeSurfaceAlpha}:null};
    }
    _drawObject(o,m,handle,reason){const active=handle||this._meshProgramHandleForObject(o,reason||'visible_mesh_draw'),locations=this._activateMeshProgram(active,m);this._bindObject(o,m,locations);this.gl.drawElements(this.gl.TRIANGLES,o.indexCount,o.indexType,0);return active;}
    _renderScene(width,height,framebuffer,notify){
      if(this.disposed||this.contextLost)return null;const previousRenderPassInteractive=this.renderPassInteractive;this.renderPassInteractive=!!notify;const frameStarted=nowMs(),gl=this.gl,w=Math.max(2,Math.round(finite(width,2))),h=Math.max(2,Math.round(finite(height,2))),visible=Array.from(this.objects.values()).filter(o=>o.style.visible&&!o.style.screenSpaceOnly),m=this._matrices(w/Math.max(1,h)),bg=this.backgroundColor;gl.bindFramebuffer(gl.FRAMEBUFFER,framebuffer||null);gl.viewport(0,0,w,h);gl.clearColor(bg[0],bg[1],bg[2],bg[3]);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);const all=visible.sort((a,b)=>a.style.renderOrder-b.style.renderOrder),raycasts=all.filter(o=>o.style.colorMode===9),objects=all.filter(o=>o.style.colorMode!==9);
      if(raycasts.length){this.volume3DFrameIndex++;gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.ONE,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);raycasts.forEach(o=>this._drawRaycastObject(o,m));gl.depthMask(true);gl.disable(gl.BLEND);}
      if(objects.length){const prepass=objects.filter(o=>o.style.depthPrepass);if(prepass.length){gl.disable(gl.BLEND);gl.colorMask(false,false,false,false);gl.depthMask(true);prepass.forEach(o=>this._drawObject(o,m,null,'depth_prepass'));gl.colorMask(true,true,true,true);}gl.enable(gl.BLEND);gl.blendFuncSeparate(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA,gl.ONE,gl.ONE_MINUS_SRC_ALPHA);objects.forEach(o=>{if(o.style.depthTest)gl.enable(gl.DEPTH_TEST);else gl.disable(gl.DEPTH_TEST);gl.depthMask(o.style.depthPrepass?false:o.style.depthWrite);this._drawObject(o,m,null,'visible_mesh_draw');});}
      gl.enable(gl.DEPTH_TEST);gl.depthMask(true);gl.disable(gl.BLEND);if(notify&&typeof this.options.onRendered==='function')this.options.onRendered(this.getCameraState(),m.basis);const submitMs=nowMs()-frameStarted;this._recordFrameSubmit(framebuffer?'offscreen':'interactive',submitMs);this.renderPassInteractive=previousRenderPassInteractive;return m;
    }
    render(){if(this.disposed||this.contextLost)return;const visible=Array.from(this.objects.values()).filter(o=>o.style.visible&&!o.style.screenSpaceOnly),visibleRaycasts=visible.filter(o=>o.style.colorMode===9),baseScale=visibleRaycasts.length?Math.min.apply(null,visibleRaycasts.map(o=>o.style.rayResolutionScale||1)):1,resolutionScale=this.interactionQuality.active?Math.min(baseScale,this.interactionQuality.resolutionScale):baseScale;this.resize(resolutionScale);this._renderScene(this.canvas.width,this.canvas.height,null,true);}
    _deleteOffscreenFramebuffer(){const gl=this.gl,f=this.offscreenFramebuffer;if(!gl||!f)return;if(f.texture)gl.deleteTexture(f.texture);if(f.depth)gl.deleteRenderbuffer(f.depth);if(f.framebuffer)gl.deleteFramebuffer(f.framebuffer);this.offscreenFramebuffer=null;}
    _ensureOffscreenFramebuffer(width,height){const gl=this.gl,w=Math.max(2,Math.round(width)),h=Math.max(2,Math.round(height)),existing=this.offscreenFramebuffer;if(existing&&existing.width===w&&existing.height===h)return existing;this._deleteOffscreenFramebuffer();const framebuffer=gl.createFramebuffer(),texture=gl.createTexture(),depth=gl.createRenderbuffer();gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,w,h,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.bindRenderbuffer(gl.RENDERBUFFER,depth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,w,h);gl.bindFramebuffer(gl.FRAMEBUFFER,framebuffer);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,texture,0);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,depth);gl.bindTexture(gl.TEXTURE_2D,null);gl.bindRenderbuffer(gl.RENDERBUFFER,null);if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE){gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.deleteTexture(texture);gl.deleteRenderbuffer(depth);gl.deleteFramebuffer(framebuffer);throw new Error('Shared-scene offscreen framebuffer is incomplete.');}gl.bindFramebuffer(gl.FRAMEBUFFER,null);this.offscreenFramebuffer={framebuffer,texture,depth,width:w,height:h};return this.offscreenFramebuffer;}
    _readRgbaPixels(width,height){const gl=this.gl,w=Math.max(2,Math.round(width)),h=Math.max(2,Math.round(height)),raw=new Uint8Array(w*h*4),data=new Uint8ClampedArray(raw.length);if(typeof gl.finish==='function')gl.finish();gl.readPixels(0,0,w,h,gl.RGBA,gl.UNSIGNED_BYTE,raw);const stride=w*4;for(let y=0;y<h;y++){const src=(h-1-y)*stride,dst=y*stride;data.set(raw.subarray(src,src+stride),dst);}if(this.presentationPremultipliedAlpha)unpremultiplyPresentationRgba8(data);return {width:w,height:h,data,colorEncoding:'presentation_straight_rgba8_source_over_alpha'};}
    _compositeScreenSpaceBoundaries(frame){const boundaryObjects=Array.from(this.objects.values()).filter(o=>o.style.visible&&o.style.screenSpaceOnly&&(o.atlasVolume||(o.style.colorMode===7&&o.style.atlasLabelSource==='vertex')));if(!boundaryObjects.length)return frame;const style=boundaryObjects[0].style,overlay=this.atlasBoundaryOverlay({width:frame.width,height:frame.height,color:style.atlasBoundaryColor,opacity:style.atlasBoundaryOpacity,depthTolerance:4/255});for(let i=0;i<frame.data.length;i+=4){const a=overlay.data[i+3]/255;if(a<=0)continue;frame.data[i]=Math.round(frame.data[i]*(1-a)+overlay.data[i]*a);frame.data[i+1]=Math.round(frame.data[i+1]*(1-a)+overlay.data[i+1]*a);frame.data[i+2]=Math.round(frame.data[i+2]*(1-a)+overlay.data[i+2]*a);frame.data[i+3]=255;}return frame;}
    renderToRgba(options){
      if(this.disposed||this.contextLost)throw new Error('Shared-scene offscreen rendering is unavailable.');const opts=options&&typeof options==='object'?options:{},width=Math.max(2,Math.round(finite(opts.width,0))),height=Math.max(2,Math.round(finite(opts.height,0)));if(!(width>1&&height>1))throw new Error('Shared-scene offscreen rendering requires positive pixel dimensions.');const gl=this.gl,previousFramebuffer=gl.getParameter(gl.FRAMEBUFFER_BINDING),previousViewport=Array.from(gl.getParameter(gl.VIEWPORT)),savedCamera=this.getCameraState(),savedBackground=this.backgroundColor.slice(),savedClip=this.getClipPlanes(),savedStyles=new Map(),overrides=opts.styleOverrides&&typeof opts.styleOverrides==='object'?opts.styleOverrides:{};
      Object.keys(overrides).forEach(id=>{if(!this.objects.has(String(id)))throw new Error(`Shared-scene frame override references unavailable object ${id}.`);savedStyles.set(String(id),this.getObjectStyle(id));});
      try{if(opts.camera){const frameCamera=clonePresentationValue(opts.camera);if(frameCamera.orbitMode!=='turntable'){delete frameCamera.azimuthDeg;delete frameCamera.elevationDeg;}this.setCameraState(frameCamera);}if(Array.isArray(opts.backgroundColor))this.setBackgroundColor(opts.backgroundColor);if(Array.isArray(opts.clipPlanes))this.setClipPlanes(opts.clipPlanes);savedStyles.forEach((style,id)=>this.setObjectStyle(id,Object.assign({},style,overrides[id]||{})));const target=this._ensureOffscreenFramebuffer(width,height);this._renderScene(width,height,target.framebuffer,false);let frame=this._readRgbaPixels(width,height);if(opts.includeScreenSpaceOverlays!==false)frame=this._compositeScreenSpaceBoundaries(frame);return frame;}finally{savedStyles.forEach((style,id)=>this.setObjectStyle(id,style));const restoreCamera=clonePresentationValue(savedCamera);if(restoreCamera.orbitMode!=='turntable'){delete restoreCamera.azimuthDeg;delete restoreCamera.elevationDeg;}this.setCameraState(restoreCamera);this.setBackgroundColor(savedBackground);this.setClipPlanes(savedClip);gl.bindFramebuffer(gl.FRAMEBUFFER,previousFramebuffer);gl.viewport(previousViewport[0],previousViewport[1],previousViewport[2],previousViewport[3]);}
    }
    _renderProjectionDiagnosticFrame(object,mode,width,height,options){
      const opts=options&&typeof options==='object'?options:{},gl=this.gl,previousFramebuffer=gl.getParameter(gl.FRAMEBUFFER_BINDING),previousViewport=Array.from(gl.getParameter(gl.VIEWPORT)),savedCamera=this.getCameraState(),savedClip=this.getClipPlanes(),savedStyle=this.getObjectStyle(object.id),occluder=this.objects.get(String(opts.occluderId||'anatomy'))||null;
      try{
        if(opts.camera){const frameCamera=clonePresentationValue(opts.camera);if(frameCamera.orbitMode!=='turntable'){delete frameCamera.azimuthDeg;delete frameCamera.elevationDeg;}this.setCameraState(frameCamera);}if(Array.isArray(opts.clipPlanes))this.setClipPlanes(opts.clipPlanes);
        const diagnosticStyle=Object.assign({},savedStyle,{visible:true,colorMode:'volume_projection',objectOpacity:1,brightness:1,unlit:true,depthWrite:true,depthPrepass:false,projectionDiagnosticMode:mode});if(mode==='projected_value'&&Array.isArray(opts.valueEncodingRange))diagnosticStyle.projectionDisplayRange=opts.valueEncodingRange.slice(0,2);this.setObjectStyle(object.id,diagnosticStyle);
        const target=this._ensureOffscreenFramebuffer(width,height),m=this._matrices(width/Math.max(1,height));gl.bindFramebuffer(gl.FRAMEBUFFER,target.framebuffer);gl.viewport(0,0,width,height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);gl.disable(gl.BLEND);const diagnosticHandle=this._meshProgramHandleForObject(object,'surface_projection_diagnostic');
        const occlusionApplied=!!(occluder&&occluder.style.visible&&!occluder.style.screenSpaceOnly&&occluder.style.colorMode!==9);if(occlusionApplied){gl.colorMask(false,false,false,false);this._drawObject(occluder,m,null,'surface_projection_diagnostic_occluder');gl.colorMask(true,true,true,true);}this._drawObject(object,m,diagnosticHandle,'surface_projection_diagnostic');const frame=this._readRgbaPixels(width,height);frame.anatomyDepthOcclusionApplied=occlusionApplied;return frame;
      }finally{
        this.setObjectStyle(object.id,savedStyle);const restoreCamera=clonePresentationValue(savedCamera);if(restoreCamera.orbitMode!=='turntable'){delete restoreCamera.azimuthDeg;delete restoreCamera.elevationDeg;}this.setCameraState(restoreCamera);this.setClipPlanes(savedClip);gl.colorMask(true,true,true,true);gl.depthMask(true);gl.enable(gl.DEPTH_TEST);gl.disable(gl.BLEND);gl.bindFramebuffer(gl.FRAMEBUFFER,previousFramebuffer);gl.viewport(previousViewport[0],previousViewport[1],previousViewport[2],previousViewport[3]);
      }
    }
    renderProjectionDiagnostics(options){
      if(this.disposed||this.contextLost)throw new Error('Surface-projection diagnostics are unavailable.');
      const opts=options&&typeof options==='object'?options:{},id=String(opts.objectId||'featureProjection'),object=this.objects.get(id);
      if(!object)throw new Error(`Surface-projection diagnostics require object ${id}.`);
      const featureVolume=object.nativeFeatureVolume||object.fragmentVolume;if(object.style.colorMode!==5||!featureVolume)throw new Error(`Object ${id} is not a fragment-sampled surface projection.`);
      const rect=this.canvas.getBoundingClientRect(),width=Math.max(2,Math.round(finite(opts.width,Math.max(2,rect.width||this.canvas.width||2)))),height=Math.max(2,Math.round(finite(opts.height,Math.max(2,rect.height||this.canvas.height||2)))),valueRange=Array.from(featureVolume.range||object.style.projectionDisplayRange||[0,1]).slice(0,2).map(Number),valueLo=finite(valueRange[0],0),valueHi=finite(valueRange[1],valueLo+1),valueSpan=Math.max(1e-20,valueHi-valueLo),diagnosticOptions=Object.assign({},opts,{valueEncodingRange:[valueLo,valueHi]}),renderDiagnostic=mode=>this._renderProjectionDiagnosticFrame(object,mode,width,height,diagnosticOptions),depthFrame=renderDiagnostic('depth_class'),xFrame=renderDiagnostic('source_voxel_x'),yFrame=renderDiagnostic('source_voxel_y'),zFrame=renderDiagnostic('source_voxel_z'),valueFrame=renderDiagnostic('projected_value'),pathFrame=renderDiagnostic('path_flags'),alphaFrame=renderDiagnostic('projection_alpha'),n=width*height,depthMm=new Float32Array(n),classCode=new Int8Array(n),sourceVoxel=new Float32Array(n*3),projectedValue=new Float32Array(n),projectionAlpha=new Float32Array(n),activeMask=new Uint8Array(n),pathFlags=new Uint8Array(n),dims=Array.from(featureVolume.dims||[]).slice(0,3).map(Number),maxDepthMm=Math.max(0,(object.style.projectionSteps-1)*object.style.projectionStepMm);
      depthMm.fill(NaN);sourceVoxel.fill(NaN);projectedValue.fill(NaN);projectionAlpha.fill(NaN);const decode16=(data,offset)=>((data[offset]*256+data[offset+1])/65535);
      let unsupportedGapPixels=0,subthresholdGapPixels=0,resumedSegmentPixels=0;
      for(let i=0;i<n;i++){
        const offset=i*4;if(depthFrame.data[offset+3]===0)continue;activeMask[i]=1;depthMm[i]=decode16(depthFrame.data,offset)*maxDepthMm;classCode[i]=depthFrame.data[offset+2]<128?-1:1;sourceVoxel[i*3]=.5+decode16(xFrame.data,offset)*dims[0];sourceVoxel[i*3+1]=.5+decode16(yFrame.data,offset)*dims[1];sourceVoxel[i*3+2]=.5+decode16(zFrame.data,offset)*dims[2];projectedValue[i]=valueLo+decode16(valueFrame.data,offset)*valueSpan;projectionAlpha[i]=decode16(alphaFrame.data,offset);let flags=0;if(pathFrame.data[offset]>=128)flags|=1;if(pathFrame.data[offset+1]>=128)flags|=2;if(pathFrame.data[offset+2]>=128)flags|=4;pathFlags[i]=flags;if(flags&1)unsupportedGapPixels++;if(flags&2)subthresholdGapPixels++;if(flags&4)resumedSegmentPixels++;
      }
      const jumpThresholdMm=Math.max(.5,1.5*object.style.projectionStepMm),continuity=projectionPixelContinuity(depthMm,classCode,activeMask,width,height,jumpThresholdMm),maps=projectionPixelMaps(depthMm,classCode,activeMask,width,height),components=projectionComponentSummary(activeMask,width,height,maps.localDepthJumpMm,maps.signSwitchMask,pathFlags,opts.smallComponentMaxPixels);let alphaSum=0,alphaMin=Infinity,alphaMax=-Infinity;for(let i=0;i<n;i++)if(activeMask[i]&&Number.isFinite(projectionAlpha[i])){alphaSum+=projectionAlpha[i];alphaMin=Math.min(alphaMin,projectionAlpha[i]);alphaMax=Math.max(alphaMax,projectionAlpha[i]);}const metrics=Object.assign({},continuity,components.metrics,{unsupportedGapPixels,unsupportedGapFraction:continuity.activePixels?unsupportedGapPixels/continuity.activePixels:0,subthresholdGapPixels,subthresholdGapFraction:continuity.activePixels?subthresholdGapPixels/continuity.activePixels:0,resumedSegmentPixels,resumedSegmentFraction:continuity.activePixels?resumedSegmentPixels/continuity.activePixels:0,projectionAlphaMean:continuity.activePixels?alphaSum/continuity.activePixels:0,projectionAlphaMin:Number.isFinite(alphaMin)?alphaMin:0,projectionAlphaMax:Number.isFinite(alphaMax)?alphaMax:0}),modeCode=object.style.surfaceFeatureSampling,modeName=['audit_voxel_faithful','audit_threshold_first_support_aware','continuous_signed_trilinear'][modeCode]||'unknown',alphaCode=object.style.projectionAlphaMode,alphaName=['uniform','threshold_free_local_support'][alphaCode]||'unknown';
      return {schema:'nm-surface-projection-diagnostics',version:6,contract:'C18g6-R4b',objectId:id,width,height,surfaceSamplingMode:modeName,surfaceSamplingCode:modeCode,projectionAggregationMode:'hard_absolute_maximum',projectionAggregationCode:0,projectionAlphaMode:alphaName,projectionAlphaCode:alphaCode,projectionAlphaSelectivity:object.style.projectionAlphaSelectivity,projectionAlphaTransfer:{function:'normalized_log_compressed_logistic',retention:1-object.style.projectionAlphaMidpoint,midpoint:object.style.projectionAlphaMidpoint,logCompression:object.style.projectionAlphaLogCompression,selectivity:object.style.projectionAlphaSelectivity},projectionSteps:object.style.projectionSteps,projectionStepMm:object.style.projectionStepMm,maxDepthMm,featureDims:dims,projectedValueEncodingRange:[valueLo,valueHi],projectionDisplayRange:Array.from(object.style.projectionDisplayRange||[0,1]).slice(0,2).map(Number),anatomyDepthOcclusionApplied:!!depthFrame.anatomyDepthOcclusionApplied,visibilityContract:'diagnostic fragments depth-tested against the current visible anatomy mesh before readback',encoding:{depth:'uint16_rg_normalized_to_max_depth',class:'blue_channel_negative_0_positive_255',sourceVoxel:'three_uint16_rg_passes_voxel1_coordinates',projectedValue:'uint16_rg_normalized_to_projection_display_range',projectionAlpha:'uint16_rg_normalized_0_to_1',pathFlags:'bit0_unsupported_gap_after_first_active_before_winner;bit1_subthreshold_gap_after_first_active_before_winner;bit2_active_segment_resumed_before_winner',inactive:'alpha_zero'},limitations:{anatomyExitAlongProjectionPath:'not sampled; the diagnostic path does not add a structural-volume dependency to production surface projection',supportEnhancement:'threshold-free local support enhancement is a deterministic local scalar transform for presentation alpha, not exact connected-component TFCE and not an inferential statistic'},metrics,components:components.components,depthMm,classCode,sourceVoxel,projectedValue,projectionAlpha,activeMask,localDepthJumpMm:maps.localDepthJumpMm,signSwitchMask:maps.signSwitchMask,pathFlags,componentLabels:components.componentLabels};
    }

    projectWorldArrayToFrame(worldValues,width,height,cameraState){const points=worldValues instanceof Float32Array||worldValues instanceof Float64Array?worldValues:new Float32Array(worldValues||[]),count=Math.floor(points.length/3),out=new Float32Array(count*4),override=!!cameraState,saved=override?this.getCameraState():null;try{if(override){const frameCamera=clonePresentationValue(cameraState);if(frameCamera.orbitMode!=='turntable'){delete frameCamera.azimuthDeg;delete frameCamera.elevationDeg;}this.setCameraState(frameCamera);}const w=Math.max(2,Math.round(finite(width,2))),h=Math.max(2,Math.round(finite(height,2))),a=this._matrices(w/Math.max(1,h)).mvp;for(let i=0;i<count;i++){const px=points[3*i],py=points[3*i+1],pz=points[3*i+2],x=a[0]*px+a[4]*py+a[8]*pz+a[12],y=a[1]*px+a[5]*py+a[9]*pz+a[13],z=a[2]*px+a[6]*py+a[10]*pz+a[14],q=a[3]*px+a[7]*py+a[11]*pz+a[15],base=4*i;if(Math.abs(q)<EPS){out[base]=out[base+1]=out[base+2]=NaN;out[base+3]=0;continue;}const nx=x/q,ny=y/q,nz=z/q;out[base]=(nx*.5+.5)*w;out[base+1]=(.5-ny*.5)*h;out[base+2]=nz;out[base+3]=q>0&&nx>=-1&&nx<=1&&ny>=-1&&ny<=1&&nz>=-1&&nz<=1?1:0;}return out;}finally{if(override){const restoreCamera=clonePresentationValue(saved);if(restoreCamera.orbitMode!=='turntable'){delete restoreCamera.azimuthDeg;delete restoreCamera.elevationDeg;}this.setCameraState(restoreCamera);}}}
    _deleteAtlasLabelFramebuffer(){const gl=this.gl,f=this.atlasLabelFramebuffer;if(!gl||!f)return;if(f.texture)gl.deleteTexture(f.texture);if(f.depth)gl.deleteRenderbuffer(f.depth);if(f.framebuffer)gl.deleteFramebuffer(f.framebuffer);this.atlasLabelFramebuffer=null;}
    _ensureAtlasLabelFramebuffer(width,height){const gl=this.gl,w=Math.max(2,Math.floor(width)),h=Math.max(2,Math.floor(height)),existing=this.atlasLabelFramebuffer;if(existing&&existing.width===w&&existing.height===h)return existing;this._deleteAtlasLabelFramebuffer();const framebuffer=gl.createFramebuffer(),texture=gl.createTexture(),depth=gl.createRenderbuffer();gl.bindTexture(gl.TEXTURE_2D,texture);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,w,h,0,gl.RGBA,gl.UNSIGNED_BYTE,null);gl.bindRenderbuffer(gl.RENDERBUFFER,depth);gl.renderbufferStorage(gl.RENDERBUFFER,gl.DEPTH_COMPONENT16,w,h);gl.bindFramebuffer(gl.FRAMEBUFFER,framebuffer);gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,texture,0);gl.framebufferRenderbuffer(gl.FRAMEBUFFER,gl.DEPTH_ATTACHMENT,gl.RENDERBUFFER,depth);gl.bindTexture(gl.TEXTURE_2D,null);gl.bindRenderbuffer(gl.RENDERBUFFER,null);if(gl.checkFramebufferStatus(gl.FRAMEBUFFER)!==gl.FRAMEBUFFER_COMPLETE){gl.bindFramebuffer(gl.FRAMEBUFFER,null);gl.deleteTexture(texture);gl.deleteRenderbuffer(depth);gl.deleteFramebuffer(framebuffer);throw new Error('Screen-space atlas-label framebuffer is incomplete.');}gl.bindFramebuffer(gl.FRAMEBUFFER,null);this.atlasLabelFramebuffer={framebuffer,texture,depth,width:w,height:h};return this.atlasLabelFramebuffer;}
    _renderAtlasLabelIds(width,height){
      if(this.disposed||this.contextLost)return null;const objects=Array.from(this.objects.values()).filter(o=>o.style.visible&&o.style.screenSpaceOnly&&(o.atlasVolume||(o.style.colorMode===7&&o.style.atlasLabelSource==='vertex')));if(!objects.length)return null;const gl=this.gl,previousFramebuffer=gl.getParameter(gl.FRAMEBUFFER_BINDING),previousViewport=Array.from(gl.getParameter(gl.VIEWPORT)),f=this._ensureAtlasLabelFramebuffer(width,height),m=this._matrices(f.width/Math.max(1,f.height));gl.bindFramebuffer(gl.FRAMEBUFFER,f.framebuffer);gl.viewport(0,0,f.width,f.height);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.depthMask(true);gl.disable(gl.BLEND);objects.sort((a,b)=>a.style.renderOrder-b.style.renderOrder).forEach(o=>{gl.depthMask(true);this._drawObject(o,m,null,'atlas_label_overlay');});const raw=new Uint8Array(f.width*f.height*4);if(typeof gl.finish==='function')gl.finish();gl.readPixels(0,0,f.width,f.height,gl.RGBA,gl.UNSIGNED_BYTE,raw);gl.bindFramebuffer(gl.FRAMEBUFFER,previousFramebuffer);gl.viewport(previousViewport[0],previousViewport[1],previousViewport[2],previousViewport[3]);return {width:f.width,height:f.height,data:raw};
    }
    atlasBoundaryOverlay(options){const opts=options||{},rect=this.canvas.getBoundingClientRect(),width=Math.max(2,Math.floor(finite(opts.width,Math.max(1,rect.width)))),height=Math.max(2,Math.floor(finite(opts.height,Math.max(1,rect.height)))),supersample=clamp(Math.round(finite(opts.supersample,2)),1,3),renderWidth=width*supersample,renderHeight=height*supersample,labels=this._renderAtlasLabelIds(renderWidth,renderHeight);if(!labels)return {width,height,data:new Uint8ClampedArray(width*height*4),boundaryCount:0,lineWidthPx:boundaryLineWidthPx(width,height,opts)};const high=atlasBoundaryPixels(labels.data,renderWidth,renderHeight,Object.assign({},opts,{lineWidthPx:boundaryLineWidthPx(width,height,opts)*supersample}));if(supersample===1)return high;return {width,height,data:downsampleBoundaryRgba(high.data,renderWidth,renderHeight,width,height),boundaryCount:high.boundaryCount,lineWidthPx:boundaryLineWidthPx(width,height,opts),supersample};}
    readPixelsRgba(){if(this.disposed||this.contextLost)throw new Error('Renderer pixels are unavailable.');this.render();return this._compositeScreenSpaceBoundaries(this._readRgbaPixels(this.canvas.width,this.canvas.height));}
    projectWorldToCanvas(worldMm){const point=vec3(worldMm,[NaN,NaN,NaN]);if(point.some(x=>!Number.isFinite(x)))return {visible:false,x:NaN,y:NaN,depth:NaN};const m=this._matrices(),a=m.mvp,x=a[0]*point[0]+a[4]*point[1]+a[8]*point[2]+a[12],y=a[1]*point[0]+a[5]*point[1]+a[9]*point[2]+a[13],z=a[2]*point[0]+a[6]*point[1]+a[10]*point[2]+a[14],w=a[3]*point[0]+a[7]*point[1]+a[11]*point[2]+a[15];if(Math.abs(w)<EPS)return {visible:false,x:NaN,y:NaN,depth:NaN};const nx=x/w,ny=y/w,nz=z/w,rect=this.canvas.getBoundingClientRect();return {visible:w>0&&nx>=-1&&nx<=1&&ny>=-1&&ny<=1&&nz>=-1&&nz<=1,x:(nx*.5+.5)*Math.max(1,rect.width),y:(.5-ny*.5)*Math.max(1,rect.height),depth:nz};}
    screenRay(clientX,clientY){this.resize(this.renderResolutionScale);const rect=this.canvas.getBoundingClientRect(),x=clamp((finite(clientX,rect.left)-rect.left)/Math.max(1,rect.width),0,1),y=clamp((finite(clientY,rect.top)-rect.top)/Math.max(1,rect.height),0,1),nx=2*x-1,ny=1-2*y,m=this._matrices(),b=m.basis;let origin=m.eye.slice(),direction=b.forward.slice();if(this.camera.projection==='perspective'){const hh=Math.tan(m.fov/2),hw=hh*m.aspect;direction=normalize(add(b.forward,add(scale(b.right,nx*hw),scale(b.up,ny*hh))),b.forward);}else{const hh=this.camera.distanceMm*Math.tan(m.fov/2),hw=hh*m.aspect;origin=add(origin,add(scale(b.right,nx*hw),scale(b.up,ny*hh)));}return {origin,direction};}
    intersectMesh(id,clientX,clientY){const o=this.objects.get(String(id));if(!o||!o.style.visible)return null;const ray=this.screenRay(clientX,clientY),v=o.vertices,idx=o.indices;let best=null;for(let t=0;t<idx.length;t+=3){const ia=idx[t],ib=idx[t+1],ic=idx[t+2];if(o.style.colorMode===4&&o.alphas&&Math.max(o.alphas[ia],o.alphas[ib],o.alphas[ic])<=.002)continue;const a=[v[ia*3],v[ia*3+1],v[ia*3+2]],b=[v[ib*3],v[ib*3+1],v[ib*3+2]],c=[v[ic*3],v[ic*3+1],v[ic*3+2]],hit=intersectTriangle(ray.origin,ray.direction,a,b,c);if(hit){const point=add(ray.origin,scale(ray.direction,hit.distance));if(!pointInsideClipPlanes(point,this.clipPlanes))continue;if(!best||hit.distance<best.distance)best={distance:hit.distance,barycentric:hit.barycentric,triangleIndex:t/3,indices:[ia,ib,ic],point};}}return best;}
    visibilityOfWorldPoint(worldMm,meshId,toleranceMm){const point=vec3(worldMm,[NaN,NaN,NaN]),tol=Math.max(.05,finite(toleranceMm,.75));if(point.some(x=>!Number.isFinite(x)))return {visible:false,occluded:true,reason:'invalid_world_coordinate'};if(!pointInsideClipPlanes(point,this.clipPlanes,tol))return {visible:false,occluded:true,reason:'clipped',worldMm:point};const o=this.objects.get(String(meshId||'anatomy'));if(!o||!o.style.visible)return {visible:true,occluded:false,reason:'mesh_unavailable',worldMm:point};const m=this._matrices(),origin=m.eye.slice(),delta=sub(point,origin),targetDistance=norm(delta);if(!(targetDistance>tol))return {visible:true,occluded:false,reason:'at_camera',worldMm:point};const direction=scale(delta,1/targetDistance),v=o.vertices,idx=o.indices;let nearest=Infinity,triangleIndex=-1;for(let t=0;t<idx.length;t+=3){const ia=idx[t],ib=idx[t+1],ic=idx[t+2];if(o.style.colorMode===4&&o.alphas&&Math.max(o.alphas[ia],o.alphas[ib],o.alphas[ic])<=.002)continue;const a=[v[ia*3],v[ia*3+1],v[ia*3+2]],b=[v[ib*3],v[ib*3+1],v[ib*3+2]],c=[v[ic*3],v[ic*3+1],v[ic*3+2]],hit=intersectTriangle(origin,direction,a,b,c);if(!hit||hit.distance>=targetDistance-tol)continue;const hitPoint=add(origin,scale(direction,hit.distance));if(!pointInsideClipPlanes(hitPoint,this.clipPlanes,tol))continue;if(hit.distance<nearest){nearest=hit.distance;triangleIndex=t/3;}}return Number.isFinite(nearest)?{visible:false,occluded:true,reason:'anatomy_occlusion',worldMm:point,occluderDistanceMm:nearest,targetDistanceMm:targetDistance,triangleIndex}:{visible:true,occluded:false,reason:'line_of_sight',worldMm:point,targetDistanceMm:targetDistance};}
    dispose(){
      if(this.disposed)return;
      this.volume3DProgramPollFrames.forEach(handle=>{if(typeof window!=='undefined'&&typeof window.cancelAnimationFrame==='function')window.cancelAnimationFrame(handle);else clearTimeout(handle);});this.volume3DProgramPollFrames.clear();
      this.volume3DPrecompileRecords.forEach(record=>{if(record&&record.frame){if(typeof window!=='undefined'&&typeof window.cancelAnimationFrame==='function')window.cancelAnimationFrame(record.frame);else clearTimeout(record.frame);}if(record&&typeof record.resolve==='function')record.resolve({ready:false,pending:false,cancelled:true,disposed:true});});this.volume3DPrecompileRecords.clear();
      const glUsable=!!(this.gl&&!this.contextLost&&!this.resourcesInvalid);
      if(glUsable&&this.gpuTimerActive&&this.gpuTimerActive.query)this.gl.deleteQuery(this.gpuTimerActive.query);if(glUsable)this.gpuTimerQueries.forEach(item=>{if(item&&item.query)this.gl.deleteQuery(item.query);});this.gpuTimerQueries=[];this.gpuTimerActive=null;
      if(glUsable)this.objects.forEach(o=>this._deleteObjectBuffers(o));this.objects.clear();if(glUsable){this._deleteAtlasLabelFramebuffer();this._deleteOffscreenFramebuffer();}else{this.atlasLabelFramebuffer=null;this.offscreenFramebuffer=null;}
      if(glUsable&&this.raycastPhaseTexture)this.gl.deleteTexture(this.raycastPhaseTexture);this.raycastPhaseTexture=null;
      if(glUsable)this.meshPrograms.forEach(handle=>{if(handle&&handle.program)this.gl.deleteProgram(handle.program);});this.meshPrograms.clear();this.meshProgramTimings={};this.activeMeshProgramKey='';this.meshEnabledAttribLocations.clear();
      if(glUsable)this.raycastPrograms.forEach(program=>{if(program)this.gl.deleteProgram(program);});this.raycastPrograms.clear();this.raycastLocationSets.clear();this.raycastProgram=null;this.raycastLocations=null;
      if(glUsable&&this.isWebGL2){const GL2=volumeRaycastGL2();this.sharedVolume3D.forEach(res=>GL2.disposeResource(this.gl,res));GL2.disposeFallbackTextures(this.gl);this.volume3DPrograms.forEach(handle=>{if(handle&&handle.program)this.gl.deleteProgram(handle.program);});}this.sharedVolume3D.clear();this.volume3DPrograms.clear();
      if(this.volumePrepClient){this.volumePrepClient.dispose();this.volumePrepClient=null;}this._listeners.forEach(([name,fn])=>this.canvas.removeEventListener(name,fn));this._listeners=[];this.disposed=true;
    }
  }

  function create(canvas,options){return new Renderer(canvas,options);}
  window.NMWebGLMeshRenderer={create,computeNormals,boundsFromVertices,boundaryLineWidthPx,screenSpaceContourPixels:contourPixelsFromSeed,math:{quatNormalize,quatMultiply,quatAxisAngle,quatRotate,quaternionFromTurntable,turntableAnglesFromQuaternion,turntableBasis,resolveLightDirection,mat4Multiply,mat4Perspective,mat4Ortho,mat4LookAt,intersectTriangle,normalizeClipPlane,pointInsideClipPlanes},_test:{featureInterpolationCode,surfaceFeatureSamplingCode,projectionAlphaModeCode,projectionAlphaTransfer,projectionDiagnosticModeCode,projectionPixelContinuity,projectionPixelMaps,projectionComponentSummary,rayFeatureModeCode,raycastProgramKind,matrixRowsToColumnMajor,chooseAtlasLayout,choosePaddedAtlasLayout,encodeFragmentVolumeAtlas,prepareRaycastStructuralAtlas,cachedRaycastStructuralAtlas,structuralSurfaceParameters,structuralSurfaceOpacityWeight,raycastPhaseTexturePixels,raycastTransferLutPixels,encodeAtlasLabelVolume,atlasBoundaryPixels,contourPixelsFromSeed,boundaryLineWidthPx,downsampleBoundaryRgba,colorModeName,diagnosticResource,unpremultiplyPresentationRgba8,contextFeatureSnapshot,baseCapabilityReport,probeWebGLCapabilities,createPerformanceTimings,volume3DCoverageKey,volume3DStructuralKey,volume3DNativeKey,volume3DPreparationSpec}};
})();
