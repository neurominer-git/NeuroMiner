(function(){
  'use strict';

  const {clamp,text,toArray}=globalThis.NMResultsViewerPrimitives;
  const PLANES=['axial','coronal','sagittal'];
  const DEFAULT_MAX_BYTES=384*1024*1024;
  function displaySemantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api||typeof api.assertDisplayContract!=='function')throw new Error('The canonical Results Viewer display-contract assertion authority is unavailable.');return api;}
  function finite(v,d){const n=Number(v);return Number.isFinite(n)?n:d;}
  function hexToRgb01(value,fallback){
    let s=text(value||fallback||'#ffffff').replace(/^#/,'');
    if(s.length===3)s=s.split('').map(c=>c+c).join('');
    if(!/^[0-9a-f]{6}$/i.test(s))s='ffffff';
    return [parseInt(s.slice(0,2),16)/255,parseInt(s.slice(2,4),16)/255,parseInt(s.slice(4,6),16)/255];
  }
  function estimateRuntimeBytes(runtime){
    let total=0;
    ['structural','support'].forEach(key=>{const data=runtime&&runtime[key];if(data&&Number.isFinite(data.byteLength))total+=data.byteLength;});
    Object.keys(runtime&&runtime.overlays||{}).forEach(id=>{const data=runtime.overlays[id]&&runtime.overlays[id].data;if(data&&Number.isFinite(data.byteLength))total+=data.byteLength;});
    const atlas=runtime&&runtime.atlas&&runtime.atlas.data;if(atlas&&Number.isFinite(atlas.byteLength))total+=atlas.byteLength;
    const native=runtime&&runtime.nativeFeatureSampling;
    if(native&&native.loaded){
      if(native.support&&Number.isFinite(native.support.byteLength))total+=native.support.byteLength;
      Object.keys(native.overlays||{}).forEach(id=>{const data=native.overlays[id]&&native.overlays[id].data;if(data&&Number.isFinite(data.byteLength))total+=data.byteLength;});
    }
    return total;
  }
  function estimateTextureBytes(runtime){
    let total=0;
    const structural=runtime&&runtime.structural;if(structural&&Number.isFinite(structural.byteLength))total+=structural.byteLength;
    const native=runtime&&runtime.nativeFeatureSampling;
    if(native&&native.loaded){
      if(native.support&&Number.isFinite(native.support.byteLength))total+=native.support.byteLength;
      Object.keys(native.overlays||{}).forEach(id=>{const data=native.overlays[id]&&native.overlays[id].data;if(data&&Number.isFinite(data.byteLength))total+=data.byteLength;});
    }
    const atlas=runtime&&runtime.atlas&&runtime.atlas.data;if(atlas&&Number.isFinite(atlas.byteLength))total+=atlas.byteLength;
    return total;
  }
  function memoryBudgetBytes(){
    const dm=finite(typeof navigator!=='undefined'&&navigator.deviceMemory,0);
    if(dm>0)return Math.min(DEFAULT_MAX_BYTES,Math.max(128*1024*1024,dm*128*1024*1024));
    return DEFAULT_MAX_BYTES;
  }
  function capability(runtime){
    const displayDims=toArray(runtime&&runtime.dims).map(Number),native=runtime&&runtime.nativeFeatureSampling,nativeDims=toArray(native&&native.dims).map(Number);
    if(displayDims.length!==3||displayDims.some(x=>!Number.isFinite(x)||x<1))return {ok:false,reason:'invalid_dimensions'};
    if(!native||!native.loaded||!native.support||nativeDims.length!==3||nativeDims.some(x=>!Number.isFinite(x)||x<1))return {ok:false,reason:'native_feature_unavailable'};
    const bytes=estimateTextureBytes(runtime),budget=memoryBudgetBytes();
    if(bytes>budget)return {ok:false,reason:'memory_budget',bytes,budget};
    return {ok:true,reason:'ok',bytes,budget,displayDims,nativeDims};
  }
  function contextCapability(gl,cap){
    if(!gl)return Object.assign({},cap,{ok:false,reason:'webgl2_unavailable'});
    if(typeof gl.isContextLost==='function'&&gl.isContextLost())return Object.assign({},cap,{ok:false,reason:'context_lost'});
    const rawMax3d=gl.getParameter(gl.MAX_3D_TEXTURE_SIZE),rawMaxUnits=gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS);
    if(rawMax3d===null||rawMaxUnits===null)return Object.assign({},cap,{ok:false,reason:'context_unavailable'});
    const max3d=Number(rawMax3d),maxUnits=Number(rawMaxUnits),maxDim=Math.max(...cap.displayDims,...cap.nativeDims);
    if(max3d<maxDim)return Object.assign({},cap,{ok:false,reason:'volume_exceeds_3d_texture_limit',max3d,maxUnits});
    if(maxUnits<7)return Object.assign({},cap,{ok:false,reason:'insufficient_texture_units',max3d,maxUnits});
    return Object.assign({},cap,{ok:true,reason:'ok',max3d,maxUnits});
  }

  function shader(gl,type,source){
    const sh=gl.createShader(type);gl.shaderSource(sh,source);gl.compileShader(sh);
    if(!gl.getShaderParameter(sh,gl.COMPILE_STATUS)){const msg=gl.getShaderInfoLog(sh)||'Shader compilation failed.';gl.deleteShader(sh);throw new Error(msg);}
    return sh;
  }
  function program(gl,vsSource,fsSource){
    const vs=shader(gl,gl.VERTEX_SHADER,vsSource),fs=shader(gl,gl.FRAGMENT_SHADER,fsSource),p=gl.createProgram();
    gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);gl.deleteShader(vs);gl.deleteShader(fs);
    if(!gl.getProgramParameter(p,gl.LINK_STATUS)){const msg=gl.getProgramInfoLog(p)||'Program link failed.';gl.deleteProgram(p);throw new Error(msg);}
    return p;
  }
  function interpolationCode(mode){return text(mode).toLowerCase()==='nearest'?0:1;}
  function featureInterpolationCode(mode){return text(mode).toLowerCase()==='support_aware_linear'?1:0;}

  const VS=`#version 300 es
  in vec2 aPosition;
  out vec2 vUv;
  void main(){vUv=(aPosition+1.0)*0.5;gl_Position=vec4(aPosition,0.0,1.0);}`;

  const FS=`#version 300 es
  precision highp float;
  precision highp int;
  precision highp sampler3D;
  precision highp usampler3D;
  in vec2 vUv;
  out vec4 outColor;
  uniform sampler3D uStructural;
  uniform sampler3D uOverlayA;
  uniform sampler3D uOverlayB;
  uniform usampler3D uFeatureSupport;
  uniform usampler3D uAtlas;
  uniform sampler2D uAGradient;
  uniform sampler2D uBGradient;
  uniform ivec3 uDisplayDims;
  uniform ivec3 uFeatureDims;
  uniform mat4 uDisplayVoxel1ToFeatureVoxel1;
  uniform int uAxisH;
  uniform int uAxisV;
  uniform int uAxisN;
  uniform int uDirH;
  uniform int uDirV;
  uniform int uSlice;
  uniform int uInterpolation;
  uniform int uFeatureInterpolation;
  uniform float uWindowLo;
  uniform float uWindowHi;
  uniform float uBrightness;
  uniform float uGamma;
  uniform bool uHasA;
  uniform bool uHasB;
  uniform bool uHasAtlas;
  uniform bool uAtlasBoundaries;
  uniform int uAMode;
  uniform int uBMode;
  uniform float uANegativeThreshold;
  uniform float uAPositiveThreshold;
  uniform float uASingleThreshold;
  uniform float uBNegativeThreshold;
  uniform float uBPositiveThreshold;
  uniform float uBSingleThreshold;
  uniform vec2 uARange;
  uniform vec2 uBRange;
  uniform vec3 uANegativeColor;
  uniform vec3 uAMidpointColor;
  uniform vec3 uAPositiveColor;
  uniform vec3 uBNegativeColor;
  uniform vec3 uBPositiveColor;
  uniform float uAOpacity;
  uniform float uBOpacity;
  uniform vec3 uAtlasColor;
  uniform float uAtlasOpacity,uAtlasBoundaryWidthPx;

  int displayAxisSize(int axis){return axis==0?uDisplayDims.x:(axis==1?uDisplayDims.y:uDisplayDims.z);}
  ivec3 composeDisplayCoord(int h,int v,int n){
    ivec3 c=ivec3(0);
    if(uAxisH==0)c.x=h;else if(uAxisH==1)c.y=h;else c.z=h;
    if(uAxisV==0)c.x=v;else if(uAxisV==1)c.y=v;else c.z=v;
    if(uAxisN==0)c.x=n;else if(uAxisN==1)c.y=n;else c.z=n;
    return clamp(c,ivec3(0),uDisplayDims-ivec3(1));
  }
  vec3 composeDisplayCoordF(float h,float v,float n){
    vec3 c=vec3(0.0);
    if(uAxisH==0)c.x=h;else if(uAxisH==1)c.y=h;else c.z=h;
    if(uAxisV==0)c.x=v;else if(uAxisV==1)c.y=v;else c.z=v;
    if(uAxisN==0)c.x=n;else if(uAxisN==1)c.y=n;else c.z=n;
    return c;
  }
  float fetchStructural(int h,int v){return texelFetch(uStructural,composeDisplayCoord(h,v,uSlice),0).r;}
  uint fetchAtlas(int h,int v){return texelFetch(uAtlas,composeDisplayCoord(h,v,uSlice),0).r;}
  float sampleStructuralNearest(float h,float v){return fetchStructural(int(floor(h+0.5)),int(floor(v+0.5)));}
  float sampleStructuralLinear(float h,float v){
    int hs=displayAxisSize(uAxisH),vs=displayAxisSize(uAxisV);
    h=clamp(h,0.0,float(hs-1));v=clamp(v,0.0,float(vs-1));
    int h0=int(floor(h)),v0=int(floor(v)),h1=min(h0+1,hs-1),v1=min(v0+1,vs-1);
    float th=h-float(h0),tv=v-float(v0);
    return mix(mix(fetchStructural(h0,v0),fetchStructural(h1,v0),th),mix(fetchStructural(h0,v1),fetchStructural(h1,v1),th),tv);
  }
  float sampleStructural(float h,float v){return uInterpolation==0?sampleStructuralNearest(h,v):sampleStructuralLinear(h,v);}

  int classify(float value,int mode,float negT,float posT,float singleT){
    if(isnan(value)||isinf(value))return 0;
    if(mode==1){if(value<=negT)return -1;if(value>=posT)return 1;return 0;}
    if(mode==2){float threshold=abs(singleT);if(abs(value)<threshold)return 0;return value<0.0?-1:(value>0.0?1:0);}
    if(mode==3)return value<=singleT?-1:0;
    if(mode==4)return value>=singleT?1:0;
    return value<0.0?-1:(value>0.0?1:0);
  }
  vec3 gradientColor(sampler2D gradient,float value,vec2 range){float t=clamp((value-range.x)/max(1e-20,range.y-range.x),0.0,1.0);return texture(gradient,vec2(t,0.5)).rgb;}
  vec3 displayToFeature0(float h,float v){
    vec3 displayVoxel1=composeDisplayCoordF(h,v,float(uSlice))+vec3(1.0);
    vec4 featureVoxel1=uDisplayVoxel1ToFeatureVoxel1*vec4(displayVoxel1,1.0);
    float w=abs(featureVoxel1.w)>1e-20?featureVoxel1.w:1.0;
    return featureVoxel1.xyz/w-vec3(1.0);
  }
  bool nearestFeatureIndex(vec3 p,out ivec3 index){
    index=ivec3(floor(p+vec3(0.5)));
    return all(greaterThanEqual(index,ivec3(0)))&&all(lessThan(index,uFeatureDims));
  }
  float sampleFeature(sampler3D tex,vec3 p,int mode,float negT,float posT,float singleT,out int klass,out float coverage){
    ivec3 nearest;klass=0;coverage=0.0;
    if(any(lessThan(p,vec3(-0.5)))||any(greaterThan(p,vec3(uFeatureDims)-vec3(0.5))))return 0.0;
    if(uFeatureInterpolation==0){
      if(!nearestFeatureIndex(p,nearest)||texelFetch(uFeatureSupport,nearest,0).r==uint(0))return 0.0;
      float nativeValue=texelFetch(tex,nearest,0).r;klass=classify(nativeValue,mode,negT,posT,singleT);coverage=klass==0?0.0:1.0;return nativeValue;
    }
    int nearestClass=0;if(nearestFeatureIndex(p,nearest)&&texelFetch(uFeatureSupport,nearest,0).r!=uint(0))nearestClass=classify(texelFetch(tex,nearest,0).r,mode,negT,posT,singleT);
    vec3 q=clamp(p,vec3(0.0),vec3(uFeatureDims-ivec3(1))),f=floor(q),t=q-f;ivec3 p0=ivec3(f),p1=min(p0+ivec3(1),uFeatureDims-ivec3(1));
    float negWeight=0.0,posWeight=0.0,negSum=0.0,posSum=0.0,negMin=3.402823466e38,negMax=-3.402823466e38,posMin=3.402823466e38,posMax=-3.402823466e38;
    for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){
      ivec3 c=ivec3(dx==0?p0.x:p1.x,dy==0?p0.y:p1.y,dz==0?p0.z:p1.z);float wx=dx==0?1.0-t.x:t.x,wy=dy==0?1.0-t.y:t.y,wz=dz==0?1.0-t.z:t.z,weight=wx*wy*wz;
      if(weight<=0.0||texelFetch(uFeatureSupport,c,0).r==uint(0))continue;float candidate=texelFetch(tex,c,0).r;int candidateClass=classify(candidate,mode,negT,posT,singleT);
      if(candidateClass<0){negWeight+=weight;negSum+=weight*candidate;negMin=min(negMin,candidate);negMax=max(negMax,candidate);}else if(candidateClass>0){posWeight+=weight;posSum+=weight*candidate;posMin=min(posMin,candidate);posMax=max(posMax,candidate);}
    }
    if(negWeight<=0.0&&posWeight<=0.0)return 0.0;
    if(negWeight>posWeight||(abs(negWeight-posWeight)<=1e-7&&nearestClass<0)){klass=-1;coverage=clamp(negWeight,0.0,1.0);return clamp(negSum/max(negWeight,1e-20),negMin,negMax);}
    klass=1;coverage=clamp(posWeight,0.0,1.0);return clamp(posSum/max(posWeight,1e-20),posMin,posMax);
  }
  float supportAlpha(float coverage){float width=max(fwidth(coverage)*0.72,0.035);return smoothstep(0.5-width,0.5+width,coverage);}
  float boundaryAlpha(float coverage){float width=max(fwidth(coverage),0.055);return 1.0-smoothstep(width*0.40,width*1.50,abs(coverage-0.5));}
  float sampleB(float h,float v,out int klass,out float coverage){return sampleFeature(uOverlayB,displayToFeature0(h,v),uBMode,uBNegativeThreshold,uBPositiveThreshold,uBSingleThreshold,klass,coverage);}
  float atlasBoundaryAlpha(float h,float v){int hs=displayAxisSize(uAxisH),vs=displayAxisSize(uAxisV),hn=int(floor(h+0.5)),vn=int(floor(v+0.5)),nh=hn+(h<float(hn)?-1:1),nv=vn+(v<float(vn)?-1:1);uint code=fetchAtlas(hn,vn);float distancePx=1e20,stepH=max(fwidth(h),1e-6),stepV=max(fwidth(v),1e-6);
    if(nh>=0&&nh<hs){uint other=fetchAtlas(nh,vn);if(other!=code&&(code!=uint(0)||other!=uint(0)))distancePx=(0.5-abs(h-float(hn)))/stepH;}if(nv>=0&&nv<vs){uint other=fetchAtlas(hn,nv);if(other!=code&&(code!=uint(0)||other!=uint(0)))distancePx=min(distancePx,(0.5-abs(v-float(vn)))/stepV);}
    float halfWidth=max(0.1,0.5*uAtlasBoundaryWidthPx),aa=max(0.3,0.35*uAtlasBoundaryWidthPx);return 1.0-smoothstep(max(0.0,halfWidth-aa),halfWidth+aa,distancePx);}
  void main(){
    int hs=displayAxisSize(uAxisH),vs=displayAxisSize(uAxisV);
    float hd=vUv.x*float(hs)-0.5,vd=(1.0-vUv.y)*float(vs)-0.5;
    float h=uDirH>0?hd:float(hs-1)-hd,v=uDirV>0?vd:float(vs-1)-vd;
    h=clamp(h,0.0,float(hs-1));v=clamp(v,0.0,float(vs-1));
    float structural=sampleStructural(h,v),den=max(1e-20,uWindowHi-uWindowLo),normalized=(isnan(structural)||isinf(structural))?0.0:clamp((structural-uWindowLo)/den,0.0,1.0),gray=clamp(pow(normalized,1.0/max(.05,uGamma))*uBrightness,0.0,1.0);
    vec3 color=vec3(gray),featurePoint=displayToFeature0(h,v);
    if(uHasA){int klass=0;float coverage=0.0,value=sampleFeature(uOverlayA,featurePoint,uAMode,uANegativeThreshold,uAPositiveThreshold,uASingleThreshold,klass,coverage),alpha=uFeatureInterpolation==0?coverage:supportAlpha(coverage);if(klass!=0&&alpha>0.001){vec3 fg=gradientColor(uAGradient,value,uARange);color=mix(color,fg,clamp(uAOpacity*alpha,0.0,1.0));}}
    if(uHasB){int klass=0;float coverage=0.0,bValue=sampleB(h,v,klass,coverage);float line=boundaryAlpha(coverage);if(klass!=0&&line>0.001){vec3 c=klass<0?uBNegativeColor:uBPositiveColor;color=mix(color,c,clamp(uBOpacity*line,0.0,1.0));}}
    if(uHasAtlas&&uAtlasBoundaries){float atlasLine=atlasBoundaryAlpha(h,v);if(atlasLine>0.001)color=mix(color,uAtlasColor,clamp(uAtlasOpacity*atlasLine,0.0,1.0));}
    outColor=vec4(color,1.0);
  }`;

  function createFloatTexture(gl,dims,data){
    const tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_3D,tex);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_R,gl.CLAMP_TO_EDGE);gl.texStorage3D(gl.TEXTURE_3D,1,gl.R32F,dims[0],dims[1],dims[2]);gl.texSubImage3D(gl.TEXTURE_3D,0,0,0,0,dims[0],dims[1],dims[2],gl.RED,gl.FLOAT,data);return tex;
  }
  function createUint8Texture(gl,dims,data){
    const tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_3D,tex);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_R,gl.CLAMP_TO_EDGE);gl.texStorage3D(gl.TEXTURE_3D,1,gl.R8UI,dims[0],dims[1],dims[2]);gl.texSubImage3D(gl.TEXTURE_3D,0,0,0,0,dims[0],dims[1],dims[2],gl.RED_INTEGER,gl.UNSIGNED_BYTE,data);return tex;
  }
  function createUint32Texture(gl,dims,data){
    const tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_3D,tex);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MIN_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_MAG_FILTER,gl.NEAREST);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_3D,gl.TEXTURE_WRAP_R,gl.CLAMP_TO_EDGE);gl.texStorage3D(gl.TEXTURE_3D,1,gl.R32UI,dims[0],dims[1],dims[2]);gl.texSubImage3D(gl.TEXTURE_3D,0,0,0,0,dims[0],dims[1],dims[2],gl.RED_INTEGER,gl.UNSIGNED_INT,data);return tex;
  }
  function createGradientTexture(gl){const tex=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,tex);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA8,256,1,0,gl.RGBA,gl.UNSIGNED_BYTE,new Uint8Array(256*4));return tex;}
  function updateGradientTexture(gl,texture,contract){const helper=window.NMImagingColorGradient;if(!helper||!contract)throw new Error('Canonical display-contract gradient upload is unavailable.');const pixels=helper.lutRgba8(contract.colorStops,256);gl.bindTexture(gl.TEXTURE_2D,texture);gl.texSubImage2D(gl.TEXTURE_2D,0,0,0,256,1,gl.RGBA,gl.UNSIGNED_BYTE,pixels);}

  class SharedPlaneRenderer{
    constructor(options){this.options=options||{};this.root=this.options.root;this.runtime=this.options.runtime;this.state='new';this.reason='';this.gl=null;this.canvas=null;this.host=null;this.program=null;this.buffer=null;this.textures={nativeOverlays:{},gradientKeys:{}};this.locations={};this.lastSize='';this.generation=0;this.contextLost=false;this.contextListenersInstalled=false;this.contextLostHandler=null;this.contextRestoredHandler=null;}
    initialize(){
      const cap=capability(this.runtime);if(!cap.ok){this.state='fallback';this.reason=cap.reason;this._notify();return cap;}
      const host=this.root&&this.root.querySelector('.rvImagingPlanes'),canvas=this.root&&this.root.querySelector('[data-imaging-shared-gpu-canvas]');
      if(!host||!canvas){this.state='fallback';this.reason='canvas_unavailable';this._notify();return {ok:false,reason:this.reason};}
      let gl=null;try{gl=canvas.getContext('webgl2',{alpha:true,antialias:false,depth:false,stencil:false,premultipliedAlpha:false,preserveDrawingBuffer:true,powerPreference:'high-performance'});}catch(err){gl=null;}
      const contextCap=contextCapability(gl,cap);if(!contextCap.ok){this.state=contextCap.reason==='context_lost'?'lost':'fallback';this.reason=contextCap.reason;this._notify();return contextCap;}
      this.gl=gl;this.canvas=canvas;this.host=host;this._installContextListeners();
      return this._initializeResources(contextCap);
    }
    _installContextListeners(){
      if(this.contextListenersInstalled||!this.canvas)return;
      this.contextLostHandler=event=>{event.preventDefault();if(this.state==='disposed')return;this.contextLost=true;this.state='lost';this.reason='context_lost';this._notify();};
      this.contextRestoredHandler=()=>{if(this.state==='disposed')return;this.contextLost=false;this.state='restoring';this.reason='context_restored';this._notify();this._restoreResources();};
      this.canvas.addEventListener('webglcontextlost',this.contextLostHandler,{passive:false});this.canvas.addEventListener('webglcontextrestored',this.contextRestoredHandler,false);this.contextListenersInstalled=true;
    }
    _resetResourceReferences(){this.program=null;this.buffer=null;this.textures={nativeOverlays:{},gradientKeys:{}};this.locations={};this.lastSize='';}
    _restoreResources(){
      const cap=contextCapability(this.gl,capability(this.runtime));
      if(!cap.ok){this.state='fallback';this.reason=cap.reason;this._notify();return cap;}
      this._resetResourceReferences();return this._initializeResources(cap);
    }
    _initializeResources(cap){
      const gl=this.gl,canvas=this.canvas;
      try{
        const viewportDims=gl.getParameter(gl.MAX_VIEWPORT_DIMS)||[4096,4096],maxRenderbuffer=Number(gl.getParameter(gl.MAX_RENDERBUFFER_SIZE)||4096);this.maxCanvasWidth=Math.max(1,Math.min(Number(viewportDims[0])||4096,maxRenderbuffer));this.maxCanvasHeight=Math.max(1,Math.min(Number(viewportDims[1])||4096,maxRenderbuffer));
        const native=this.runtime.nativeFeatureSampling,helper=window.NMImagingFeatureSampling;
        if(!helper||typeof helper.displayToNativeVoxelMatrix!=='function'||typeof helper.rowMajorToColumnMajor4!=='function')throw new Error('Native-grid transform support is unavailable.');
        this.program=program(gl,VS,FS);gl.useProgram(this.program);
        this.buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);
        const pos=gl.getAttribLocation(this.program,'aPosition');gl.enableVertexAttribArray(pos);gl.vertexAttribPointer(pos,2,gl.FLOAT,false,0,0);gl.pixelStorei(gl.UNPACK_ALIGNMENT,1);
        this.textures.structural=createFloatTexture(gl,this.runtime.dims,this.runtime.structural);
        this.textures.featureSupport=createUint8Texture(gl,native.dims,native.support);
        Object.keys(native.overlays||{}).forEach(id=>{this.textures.nativeOverlays[id]=createFloatTexture(gl,native.dims,native.overlays[id].data);});
        if(this.runtime.atlas)this.textures.atlas=createUint32Texture(gl,this.runtime.dims,this.runtime.atlas.data);else this.textures.atlas=createUint32Texture(gl,[1,1,1],new Uint32Array([0]));this.textures.gradientA=createGradientTexture(gl);this.textures.gradientB=createGradientTexture(gl);
        this.displayToNativeColumnMajor=helper.rowMajorToColumnMajor4(helper.displayToNativeVoxelMatrix(this.runtime.payload.spatialReference,native));
        this._cacheLocations();this._bindStaticTextures();gl.disable(gl.DEPTH_TEST);gl.disable(gl.BLEND);gl.enable(gl.SCISSOR_TEST);gl.clearColor(0,0,0,0);
        this.contextLost=false;this.state='ready';this.reason='';this.error=null;canvas.hidden=false;canvas.dataset.renderer='webgl2-native-grid';this._notify();return Object.assign({ok:true},cap);
      }catch(err){this.error=err;this.state='fallback';this.reason='initialization_failed';this._notify();return {ok:false,reason:this.reason,error:err};}
    }
    _cacheLocations(){
      const names=['uStructural','uOverlayA','uOverlayB','uFeatureSupport','uAtlas','uAGradient','uBGradient','uDisplayDims','uFeatureDims','uDisplayVoxel1ToFeatureVoxel1','uAxisH','uAxisV','uAxisN','uDirH','uDirV','uSlice','uInterpolation','uFeatureInterpolation','uWindowLo','uWindowHi','uBrightness','uGamma','uHasA','uHasB','uHasAtlas','uAtlasBoundaries','uAMode','uBMode','uANegativeThreshold','uAPositiveThreshold','uASingleThreshold','uBNegativeThreshold','uBPositiveThreshold','uBSingleThreshold','uARange','uBRange','uANegativeColor','uAMidpointColor','uAPositiveColor','uBNegativeColor','uBPositiveColor','uAOpacity','uBOpacity','uAtlasColor','uAtlasOpacity','uAtlasBoundaryWidthPx'];
      names.forEach(name=>{this.locations[name]=this.gl.getUniformLocation(this.program,name);});
    }
    _bindStaticTextures(){
      const gl=this.gl,l=this.locations,native=this.runtime.nativeFeatureSampling;
      gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_3D,this.textures.structural);gl.uniform1i(l.uStructural,0);
      gl.activeTexture(gl.TEXTURE3);gl.bindTexture(gl.TEXTURE_3D,this.textures.featureSupport);gl.uniform1i(l.uFeatureSupport,3);
      gl.activeTexture(gl.TEXTURE4);gl.bindTexture(gl.TEXTURE_3D,this.textures.atlas);gl.uniform1i(l.uAtlas,4);gl.activeTexture(gl.TEXTURE5);gl.bindTexture(gl.TEXTURE_2D,this.textures.gradientA);gl.uniform1i(l.uAGradient,5);gl.activeTexture(gl.TEXTURE6);gl.bindTexture(gl.TEXTURE_2D,this.textures.gradientB);gl.uniform1i(l.uBGradient,6);
      gl.uniform3iv(l.uDisplayDims,new Int32Array(this.runtime.dims));gl.uniform3iv(l.uFeatureDims,new Int32Array(native.dims));gl.uniformMatrix4fv(l.uDisplayVoxel1ToFeatureVoxel1,false,this.displayToNativeColumnMajor);
    }
    _notify(){if(typeof this.options.onStatus==='function')this.options.onStatus({state:this.state,reason:this.reason,error:this.error||null,hostTransport:typeof window!=='undefined'&&window.NM_HTML_RELAY===true?'html-relay':'browser'});}
    _setDisplay(prefix,model){
      const gl=this.gl,l=this.locations,display=model&&model.display||{},contract=model&&model.contract,threshold=contract&&contract.threshold||{},range=contract&&contract.shownRange||{},negative=hexToRgb01(display.negativeColor,'#0000ff'),midpoint=hexToRgb01(display.midpointColor,'#ffffff'),positive=hexToRgb01(display.positiveColor,'#ff0000'),gradientTexture=prefix==='A'?this.textures.gradientA:this.textures.gradientB;
      displaySemantics().assertDisplayContract(contract,{consumer:'NMImaging2DWebGLRenderer feature binding',message:'2-D WebGL rendering requires a canonical display contract.',facets:['threshold','shownRange','colorStops','opacity']});
      updateGradientTexture(gl,gradientTexture,contract);
      gl.uniform1i(l['u'+prefix+'Mode'],displaySemantics().thresholdModeCode(threshold.mode));gl.uniform1f(l['u'+prefix+'NegativeThreshold'],finite(threshold.lower,-3.402823466e38));gl.uniform1f(l['u'+prefix+'PositiveThreshold'],finite(threshold.upper,3.402823466e38));gl.uniform1f(l['u'+prefix+'SingleThreshold'],finite(threshold.value,0));gl.uniform2f(l['u'+prefix+'Range'],finite(range.lower,0),finite(range.upper,1));
      if(prefix==='A'){gl.uniform3fv(l.uANegativeColor,negative);gl.uniform3fv(l.uAMidpointColor,midpoint);gl.uniform3fv(l.uAPositiveColor,positive);gl.uniform1f(l.uAOpacity,contract.opacity);}
      else{gl.uniform3fv(l.uBNegativeColor,negative);gl.uniform3fv(l.uBPositiveColor,positive);gl.uniform1f(l.uBOpacity,contract.opacity);}
    }
    _bindOverlay(unit,uniformName,model){
      const gl=this.gl,texture=model&&this.textures.nativeOverlays[model.id];gl.activeTexture(gl.TEXTURE0+unit);gl.bindTexture(gl.TEXTURE_3D,texture||this.textures.structural);gl.uniform1i(this.locations[uniformName],unit);return !!texture;
    }
    /* Purpose: retain the mounted WebGL2 plane renderer across feature-only
     * scientific payload changes. Inputs/outputs: nextRuntime is a fully
     * hydrated imaging runtime; the result reports whether retained update was
     * possible and which resource classes changed. Authority and flow:
     * loadWorkspace owns scientific materialization; this method owns only GPU
     * resource replacement. Invariants: display-grid structural data must be
     * the exact retained array; feature/support/atlas resources may change.
     * Materialization/performance: no files are read and no structural texture,
     * program, buffer or context is recreated; only changed native feature or
     * atlas textures are uploaded. Failure semantics: new textures are created
     * transactionally and old resources remain installed if creation fails.
     * Side effects: replaces changed GPU textures and runtime bindings in place. */
    updateRuntime(nextRuntime){
      const previousRuntime=this.runtime,previousNative=previousRuntime&&previousRuntime.nativeFeatureSampling,nextNative=nextRuntime&&nextRuntime.nativeFeatureSampling,sameDims=toArray(previousRuntime&&previousRuntime.dims).join('x')===toArray(nextRuntime&&nextRuntime.dims).join('x');
      if(!previousRuntime||!nextRuntime||!sameDims||nextRuntime.structural!==previousRuntime.structural)return {retained:false,reason:'structural_identity_changed'};
      if(!nextNative||!nextNative.loaded||!nextNative.support)return {retained:false,reason:'native_feature_unavailable'};
      if(this.state==='new'||this.state==='fallback'){this.runtime=nextRuntime;return {retained:true,rendererReady:false,structuralRetained:true,featureChanged:true,atlasChanged:!!(previousRuntime.atlas!==nextRuntime.atlas)};}
      if(this.state!=='ready'||!this.gl)return {retained:false,reason:'renderer_not_ready'};
      const bytes=estimateTextureBytes(nextRuntime),budget=memoryBudgetBytes();if(bytes>budget)return {retained:false,reason:'memory_budget',bytes,budget};
      const gl=this.gl,max3d=Number(gl.getParameter(gl.MAX_3D_TEXTURE_SIZE)||0),nativeDims=toArray(nextNative.dims).map(Number);if(nativeDims.length!==3||nativeDims.some(x=>!Number.isFinite(x)||x<1)||Math.max(...nativeDims,...toArray(nextRuntime.dims).map(Number))>max3d)return {retained:false,reason:'volume_exceeds_3d_texture_limit'};
      const helper=window.NMImagingFeatureSampling;if(!helper||typeof helper.displayToNativeVoxelMatrix!=='function'||typeof helper.rowMajorToColumnMajor4!=='function')return {retained:false,reason:'native_transform_unavailable'};
      const created=[],nextOverlayTextures={},previousOverlayTextures=this.textures.nativeOverlays||{},supportChanged=!previousNative||previousNative.support!==nextNative.support||toArray(previousNative.dims).join('x')!==nativeDims.join('x'),atlasChanged=!!((previousRuntime.atlas&&previousRuntime.atlas.data)!==(nextRuntime.atlas&&nextRuntime.atlas.data));
      let nextSupportTexture=this.textures.featureSupport,nextAtlasTexture=this.textures.atlas;
      try{
        if(supportChanged){nextSupportTexture=createUint8Texture(gl,nativeDims,nextNative.support);created.push(nextSupportTexture);}
        Object.keys(nextNative.overlays||{}).forEach(id=>{const previous=previousNative&&previousNative.overlays&&previousNative.overlays[id],current=nextNative.overlays[id],retained=previous&&current&&previous.data===current.data&&previousOverlayTextures[id];if(retained)nextOverlayTextures[id]=previousOverlayTextures[id];else{const texture=createFloatTexture(gl,nativeDims,current.data);created.push(texture);nextOverlayTextures[id]=texture;}});
        if(atlasChanged){const atlas=nextRuntime.atlas&&nextRuntime.atlas.data,nextDims=nextRuntime.dims;nextAtlasTexture=atlas?createUint32Texture(gl,nextDims,atlas):createUint32Texture(gl,[1,1,1],new Uint32Array([0]));created.push(nextAtlasTexture);}
        const displayToNativeColumnMajor=helper.rowMajorToColumnMajor4(helper.displayToNativeVoxelMatrix(nextRuntime.payload.spatialReference,nextNative));
        if(supportChanged&&this.textures.featureSupport)gl.deleteTexture(this.textures.featureSupport);
        Object.keys(previousOverlayTextures).forEach(id=>{if(previousOverlayTextures[id]!==nextOverlayTextures[id])gl.deleteTexture(previousOverlayTextures[id]);});
        if(atlasChanged&&this.textures.atlas)gl.deleteTexture(this.textures.atlas);
        this.runtime=nextRuntime;this.textures.featureSupport=nextSupportTexture;this.textures.nativeOverlays=nextOverlayTextures;this.textures.atlas=nextAtlasTexture;this.displayToNativeColumnMajor=displayToNativeColumnMajor;gl.useProgram(this.program);this._bindStaticTextures();
        return {retained:true,rendererReady:true,structuralRetained:true,featureChanged:supportChanged||Object.keys(nextOverlayTextures).some(id=>nextOverlayTextures[id]!==previousOverlayTextures[id])||Object.keys(previousOverlayTextures).some(id=>!nextOverlayTextures[id]),atlasChanged};
      }catch(err){created.forEach(texture=>{try{gl.deleteTexture(texture);}catch(_){}});throw err;}
    }
    setAtlas(atlas){const next=atlas&&atlas.data?atlas:null,n=this.runtime.dims[0]*this.runtime.dims[1]*this.runtime.dims[2];if(next&&next.data.length!==n)throw new Error('Retained 2-D atlas data do not match the mounted display grid.');this.runtime.atlas=next;if(!this.gl)return true;const gl=this.gl,replacement=next?createUint32Texture(gl,this.runtime.dims,next.data):createUint32Texture(gl,[1,1,1],new Uint32Array([0]));if(this.textures.atlas)gl.deleteTexture(this.textures.atlas);this.textures.atlas=replacement;gl.useProgram(this.program);gl.activeTexture(gl.TEXTURE4);gl.bindTexture(gl.TEXTURE_3D,replacement);gl.uniform1i(this.locations.uAtlas,4);return true;}
    _resize(){
      const requestedDpr=clamp(finite(window.devicePixelRatio,1),1,2),fitDpr=Math.min(requestedDpr,this.maxCanvasWidth/Math.max(1,this.host.clientWidth),this.maxCanvasHeight/Math.max(1,this.host.clientHeight)),dpr=Math.max(.25,fitDpr),w=Math.max(1,Math.round(this.host.clientWidth*dpr)),h=Math.max(1,Math.round(this.host.clientHeight*dpr)),signature=w+'x'+h;
      if(signature===this.lastSize)return false;this.lastSize=signature;this.canvas.width=w;this.canvas.height=h;this.canvas.style.width=this.host.clientWidth+'px';this.canvas.style.height=this.host.clientHeight+'px';this.gl.viewport(0,0,w,h);this.gl.scissor(0,0,w,h);this.gl.clear(this.gl.COLOR_BUFFER_BIT);return true;
    }
    render(planes,model){
      if(this.state!=='ready'||this.contextLost||!this.root||!this.root.isConnected)return false;
      const gl=this.gl,l=this.locations,resized=this._resize(),targets=resized?PLANES:toArray(planes).filter(plane=>PLANES.includes(plane));if(!targets.length)return true;
      gl.useProgram(this.program);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      const windowRange=toArray(model.structuralWindow).map(Number);gl.uniform1f(l.uWindowLo,finite(windowRange[0],0));gl.uniform1f(l.uWindowHi,finite(windowRange[1],1));gl.uniform1f(l.uBrightness,clamp(finite(model.brightness,1),0,2));gl.uniform1f(l.uGamma,clamp(finite(model.gamma,1),.25,4));gl.uniform1i(l.uInterpolation,interpolationCode(model.anatomyInterpolation));gl.uniform1i(l.uFeatureInterpolation,featureInterpolationCode(model.featureInterpolation));
      const hasA=this._bindOverlay(1,'uOverlayA',model.overlayA),hasB=this._bindOverlay(2,'uOverlayB',model.overlayB);gl.uniform1i(l.uHasA,hasA?1:0);gl.uniform1i(l.uHasB,hasB?1:0);gl.uniform1i(l.uHasAtlas,this.runtime.atlas?1:0);gl.uniform1i(l.uAtlasBoundaries,model.atlasBoundaries&&this.runtime.atlas?1:0);if(hasA)this._setDisplay('A',model.overlayA);if(hasB)this._setDisplay('B',model.overlayB);gl.uniform3fv(l.uBNegativeColor,hexToRgb01(model.silhouetteNegativeColor,model.overlayB&&model.overlayB.display&&model.overlayB.display.negativeColor||'#0000ff'));gl.uniform3fv(l.uBPositiveColor,hexToRgb01(model.silhouettePositiveColor,model.overlayB&&model.overlayB.display&&model.overlayB.display.positiveColor||'#ff0000'));
      gl.uniform3fv(l.uAtlasColor,hexToRgb01(model.atlasColor,'#202020'));gl.uniform1f(l.uAtlasOpacity,clamp(finite(model.atlasOpacity,.82),0,1));
      const hostRect=this.host.getBoundingClientRect(),scaleX=this.canvas.width/Math.max(1,hostRect.width),scaleY=this.canvas.height/Math.max(1,hostRect.height);gl.uniform1f(l.uAtlasBoundaryWidthPx,.85*.5*(scaleX+scaleY));gl.clearColor(0,0,0,1);
      targets.forEach(plane=>{
        const planeModel=model.planes&&model.planes[plane];if(!planeModel)return;const frame=planeModel.frame,raster=planeModel.raster;if(!frame||!raster)return;
        const frameRect=frame.getBoundingClientRect(),rasterRect=raster.getBoundingClientRect(),frameX=Math.round((frameRect.left-hostRect.left)*scaleX),frameY=Math.round((hostRect.bottom-frameRect.bottom)*scaleY),frameW=Math.max(1,Math.round(frameRect.width*scaleX)),frameH=Math.max(1,Math.round(frameRect.height*scaleY)),rasterX=Math.round((rasterRect.left-hostRect.left)*scaleX),rasterY=Math.round((hostRect.bottom-rasterRect.bottom)*scaleY),rasterW=Math.max(1,Math.round(rasterRect.width*scaleX)),rasterH=Math.max(1,Math.round(rasterRect.height*scaleY));
        const sx0=Math.max(0,frameX),sy0=Math.max(0,frameY),sx1=Math.min(this.canvas.width,frameX+frameW),sy1=Math.min(this.canvas.height,frameY+frameH);if(sx1<=sx0||sy1<=sy0)return;gl.scissor(sx0,sy0,sx1-sx0,sy1-sy0);gl.clear(gl.COLOR_BUFFER_BIT);gl.viewport(rasterX,rasterY,rasterW,rasterH);
        const definition=planeModel.definition;gl.uniform1i(l.uAxisH,definition.horizontalVoxelAxis-1);gl.uniform1i(l.uAxisV,definition.verticalVoxelAxis-1);gl.uniform1i(l.uAxisN,definition.normalVoxelAxis-1);gl.uniform1i(l.uDirH,definition.horizontalDirection<0?-1:1);gl.uniform1i(l.uDirV,definition.verticalDirection<0?-1:1);gl.uniform1i(l.uSlice,Math.max(0,Math.round(planeModel.slice)-1));gl.drawArrays(gl.TRIANGLES,0,6);
      });
      gl.clearColor(0,0,0,0);gl.scissor(0,0,this.canvas.width,this.canvas.height);this.canvas.dataset.renderGeneration=String(++this.generation);return true;
    }
    dispose(loseContext){
      const gl=this.gl;if(this.canvas&&this.contextListenersInstalled){this.canvas.removeEventListener('webglcontextlost',this.contextLostHandler,false);this.canvas.removeEventListener('webglcontextrestored',this.contextRestoredHandler,false);this.contextListenersInstalled=false;}this.state='disposed';
      if(gl&&!this.contextLost){Object.keys(this.textures.nativeOverlays||{}).forEach(id=>{try{gl.deleteTexture(this.textures.nativeOverlays[id]);}catch(err){}});['structural','featureSupport','atlas','gradientA','gradientB'].forEach(key=>{if(this.textures[key])try{gl.deleteTexture(this.textures[key]);}catch(err){}});if(this.buffer)try{gl.deleteBuffer(this.buffer);}catch(err){}if(this.program)try{gl.deleteProgram(this.program);}catch(err){}if(loseContext!==false){const lose=gl.getExtension('WEBGL_lose_context');if(lose)try{lose.loseContext();}catch(err){}}}
      this.contextLostHandler=null;this.contextRestoredHandler=null;if(this.canvas){this.canvas.hidden=true;this.canvas.removeAttribute('data-renderer');}this.gl=null;
    }
  }

  function create(options){return new SharedPlaneRenderer(options);}
  window.NMImaging2DWebGLRenderer={create,capability,estimateRuntimeBytes,estimateTextureBytes,memoryBudgetBytes,interpolationCode,featureInterpolationCode,_test:{estimateRuntimeBytes,estimateTextureBytes,memoryBudgetBytes,interpolationCode,featureInterpolationCode,hexToRgb01,fragmentShader:FS}};
})();
