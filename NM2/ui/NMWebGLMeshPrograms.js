(function(){
  'use strict';

  const {clamp}=globalThis.NMResultsViewerPrimitives;
  /*
   * NM-RV-MESH-PROGRAMS-V1
   * Purpose: build and cache-role metadata for small ESSL 1.00/3.00 mesh programs
   * used by the common retained NMWebGLMeshRenderer.
   * Inputs: normalized renderer style only; geometry and scientific payloads
   * remain owned by the renderer and source adapters.
   * Supported roles: base triangle mesh, accepted production volumetric
   * surface projection, anatomy outline, atlas boundary and atlas label.
   * Projection diagnostics and structural locator/slice modes use dedicated
   * specialized programs. No generic mesh-program fallback exists.
   * Invariants: no compile at module load, no COMPILE_STATUS query on a
   * successful link, explicit variant keys, and no ownership of WebGL
   * programs after the returned handle is installed in the renderer cache.
   * Failure: compile/link errors are explicit and include programKey.
   * WebGL2 fragment-sampled feature views (surface projection, locator and cut
   * slices) use the authoritative native RG32F 3-D feature texture; WebGL1
   * retains the packed 2-D compatibility representation.
   * Not supported: line/edge primitives, source-schema inference, native-surface
   * TFLSE, or independent renderer lifecycle.
   */

  const CONTRACT='NM-RV-MESH-PROGRAMS-V1';
  const ROLE={
    BASE:'base_mesh',
    SURFACE_PROJECTION:'surface_projection_production',
    OUTLINE:'anatomy_outline',
    ATLAS_BOUNDARY:'atlas_boundary',
    ATLAS_LABEL:'atlas_label',
    LOCATOR:'volume_locator',
    PROJECTION_DIAGNOSTIC:'surface_projection_diagnostic',
    ATLAS_BOUNDARY_RIBBON:'atlas_boundary_ribbon'
  };
  const COMMON_ATTRIBS=['aPosition','aNormal','aValue','aColor','aAlpha'];
  const COMMON_UNIFORMS=['uMVP','uSurfaceOffsetMm','uDoubleSided','uBaseColor','uNeutralColor','uValueRange','uThreshold','uScalarOpacity','uObjectOpacity','uBrightness','uDepthCueStrength','uDepthCueRange','uViewDirection','uBackgroundColor','uUnlit','uAmbient','uDiffuse','uSpecular','uShininess','uLightDirection','uLightColor','uEyeWorld','uClipCount','uClipPlane0','uClipPlane1','uClipPlane2'];

  function finite(value,fallback){const n=Number(value);return Number.isFinite(n)?n:fallback;}
  function hashText(value){let h=2166136261>>>0;const text=String(value||'');for(let i=0;i<text.length;i++){h^=text.charCodeAt(i);h=Math.imul(h,16777619)>>>0;}return h.toString(16).padStart(8,'0');}
  function stepBucket(value){const n=clamp(Math.round(finite(value,1)),1,33);return n<=4?4:n<=8?8:n<=16?16:33;}
  function atlasStepBucket(value){const n=clamp(Math.round(finite(value,1)),1,20);return n<=4?4:n<=8?8:n<=12?12:20;}

  function ribbonVertexSource(){return `
      attribute vec3 aPosition;
      attribute vec3 aNormal;
      attribute float aValue;
      uniform mat4 uMVP;
      uniform vec2 uViewport;
      uniform float uLineWidthPx;
      uniform float uDepthBias;
      varying float vRibbonSide;
      void main(){
        vec4 clipA=uMVP*vec4(aPosition,1.0);
        vec4 clipB=uMVP*vec4(aPosition+aNormal,1.0);
        float safeWA=max(abs(clipA.w),1.0e-6),safeWB=max(abs(clipB.w),1.0e-6);
        vec2 ndcA=clipA.xy/safeWA,ndcB=clipB.xy/safeWB;
        vec2 pixelDelta=(ndcB-ndcA)*max(uViewport,vec2(1.0));
        float magnitude=length(pixelDelta);
        vec2 tangent=magnitude>1.0e-5?pixelDelta/magnitude:vec2(1.0,0.0);
        vec2 screenNormal=vec2(-tangent.y,tangent.x);
        clipA.xy+=screenNormal*(uLineWidthPx/max(uViewport,vec2(1.0)))*aValue*clipA.w;
        clipA.z-=uDepthBias*clipA.w;
        vRibbonSide=aValue;
        gl_Position=clipA;
      }
    `;}

  function ribbonFragmentSource(){return `
      precision highp float;
      varying float vRibbonSide;
      uniform vec3 uAtlasBoundaryColor;
      uniform float uAtlasBoundaryOpacity;
      void main(){
        float edge=abs(vRibbonSide);
        float coverage=1.0-smoothstep(0.72,1.0,edge);
        float alpha=clamp(uAtlasBoundaryOpacity*coverage,0.0,1.0);
        if(alpha<=0.002)discard;
        gl_FragColor=vec4(uAtlasBoundaryColor,alpha);
      }
    `;}

  function vertexSource(role){
    if(role===ROLE.ATLAS_BOUNDARY_RIBBON)return ribbonVertexSource();
    const needsValues=role===ROLE.BASE;
    return `
      attribute vec3 aPosition;
      attribute vec3 aNormal;
      ${needsValues?'attribute float aValue;\n      attribute vec3 aColor;\n      attribute float aAlpha;':''}
      uniform mat4 uMVP;
      uniform float uSurfaceOffsetMm;
      varying vec3 vNormal;
      varying vec3 vWorldPosition;
      ${needsValues?'varying float vValue;\n      varying vec3 vPremultipliedColor;\n      varying float vAlpha;':''}
      void main(){
        vNormal=normalize(aNormal);
        vec3 displayedPosition=aPosition+vNormal*uSurfaceOffsetMm;
        vWorldPosition=displayedPosition;
        ${needsValues?'vValue=aValue;\n        vAlpha=clamp(aAlpha,0.0,1.0);\n        vPremultipliedColor=aColor*vAlpha;':''}
        gl_Position=uMVP*vec4(displayedPosition,1.0);
      }
    `;
  }

  function clipUniforms(){return `
      uniform int uClipCount;
      uniform vec4 uClipPlane0;
      uniform vec4 uClipPlane1;
      uniform vec4 uClipPlane2;
      bool clipped(){
        if(uClipCount>0&&dot(uClipPlane0.xyz,vWorldPosition)+uClipPlane0.w<0.0)return true;
        if(uClipCount>1&&dot(uClipPlane1.xyz,vWorldPosition)+uClipPlane1.w<0.0)return true;
        if(uClipCount>2&&dot(uClipPlane2.xyz,vWorldPosition)+uClipPlane2.w<0.0)return true;
        return false;
      }
  `;}

  function lightingUniforms(){return `
      uniform int uDoubleSided;
      uniform float uBrightness;
      uniform float uDepthCueStrength;
      uniform vec2 uDepthCueRange;
      uniform vec3 uViewDirection;
      uniform vec3 uBackgroundColor;
      uniform int uUnlit;
      uniform float uAmbient;
      uniform float uDiffuse;
      uniform float uSpecular;
      uniform float uShininess;
      uniform vec3 uLightDirection;
      uniform vec3 uLightColor;
      uniform vec3 uEyeWorld;
      vec3 applyLighting(vec3 color){
        vec3 n=normalize(vNormal);if(uDoubleSided==1&&!gl_FrontFacing)n=-n;
        vec3 l=normalize(uLightDirection),v=normalize(uEyeWorld-vWorldPosition),h=normalize(l+v);
        float diffuse=max(dot(n,l),0.0),spec=pow(max(dot(n,h),0.0),max(1.0,uShininess));
        vec3 scaleValue=uUnlit==1?vec3(1.0):clamp(vec3(uAmbient)+(uDiffuse*diffuse+uSpecular*spec)*uLightColor,vec3(0.0),vec3(1.6));
        vec3 litColor=clamp(color*scaleValue*uBrightness,0.0,1.0);
        float viewDepth=dot(vWorldPosition-uEyeWorld,normalize(uViewDirection));
        float relativeDepth=clamp((viewDepth-uDepthCueRange.x)/max(0.0001,uDepthCueRange.y-uDepthCueRange.x),0.0,1.0);
        return mix(litColor,uBackgroundColor,clamp(uDepthCueStrength,0.0,1.0)*smoothstep(0.10,0.90,relativeDepth));
      }
  `;}

  function baseFragmentSource(){return `
      precision highp float;
      precision highp int;
      varying vec3 vNormal;
      varying vec3 vWorldPosition;
      varying float vValue;
      varying vec3 vPremultipliedColor;
      varying float vAlpha;
      uniform int uColorMode;
      uniform vec3 uBaseColor;
      uniform vec3 uNeutralColor;
      uniform vec2 uValueRange;
      uniform float uThreshold;
      uniform float uScalarOpacity;
      uniform float uObjectOpacity;
      ${clipUniforms()}
      ${lightingUniforms()}
      vec3 seqColor(float t){
        vec3 c0=vec3(0.08,0.24,0.70),c1=vec3(0.05,0.68,0.82),c2=vec3(0.95,0.78,0.24),c3=vec3(0.78,0.18,0.12);
        if(t<0.333333)return mix(c0,c1,t/0.333333);
        if(t<0.666667)return mix(c1,c2,(t-0.333333)/0.333334);
        return mix(c2,c3,(t-0.666667)/0.333333);
      }
      vec3 scalarColor(){
        float den=max(uValueRange.y-uValueRange.x,0.000001),t=clamp((vValue-uValueRange.x)/den,0.0,1.0);
        if(uColorMode==2){float az=abs(vValue);return az<uThreshold?uNeutralColor:(vValue>=0.0?vec3(1.0,0.22,0.18):vec3(0.15,0.50,1.0));}
        if(uColorMode==3)return mix(vec3(0.92,0.95,1.0),vec3(0.88,0.22,0.10),t);
        return seqColor(t);
      }
      void main(){
        if(clipped())discard;
        float rawCoverage=uColorMode==4?clamp(vAlpha,0.0,1.0):1.0;
        float coverage=uColorMode==4?rawCoverage*rawCoverage*(3.0-2.0*rawCoverage):1.0;
        float alpha=clamp(uObjectOpacity*coverage,0.0,1.0);if(alpha<=0.002)discard;
        vec3 color=uBaseColor;
        if(uColorMode==4)color=rawCoverage>0.00001?clamp(vPremultipliedColor/rawCoverage,0.0,1.0):vec3(0.0);
        else if(uColorMode>0)color=mix(uNeutralColor,scalarColor(),clamp(uScalarOpacity,0.0,1.0));
        gl_FragColor=vec4(applyLighting(color),alpha);
      }
  `;}

  function floatAtlasDecode(prefix,textureFunction){const sample=textureFunction||'texture2D';return `
      bool ${prefix}CoordInside(ivec3 c){return c.x>=0&&c.y>=0&&c.z>=0&&float(c.x)<u${prefix}Dims.x&&float(c.y)<u${prefix}Dims.y&&float(c.z)<u${prefix}Dims.z;}
      vec4 ${prefix}EncodedAt(ivec3 c){
        if(!${prefix}CoordInside(c))return vec4(0.0);
        float z=float(c.z),tileY=floor((z+0.5)/u${prefix}Grid.x),tileX=z-tileY*u${prefix}Grid.x;
        vec2 pixel=vec2(tileX*u${prefix}Dims.x+float(c.x)+0.5,tileY*u${prefix}Dims.y+float(c.y)+0.5);
        return ${sample}(u${prefix}Atlas,pixel/u${prefix}TextureSize);
      }
      bool decode${prefix}(ivec3 c,out float value){
        if(!${prefix}CoordInside(c)){value=0.0;return false;}
        vec4 encoded=${prefix}EncodedAt(c),bytes=floor(encoded*255.0+0.5);
        if(bytes.r==1.0&&bytes.g==0.0&&bytes.b==192.0&&bytes.a==127.0){value=0.0;return false;}
        float signValue=bytes.a>=128.0?-1.0:1.0,high=bytes.a-(bytes.a>=128.0?128.0:0.0),exponent=high*2.0+floor(bytes.b/128.0),mantissa=mod(bytes.b,128.0)*65536.0+bytes.g*256.0+bytes.r;
        if(exponent==0.0)value=signValue*exp2(-126.0)*(mantissa/8388608.0);else value=signValue*exp2(exponent-127.0)*(1.0+mantissa/8388608.0);
        return true;
      }
  `;}

  function nativeFeature3DDecode(){return `
      bool FragmentVolumeCoordInside(ivec3 c){return all(greaterThanEqual(c,ivec3(0)))&&all(lessThan(c,ivec3(uFragmentVolumeDims)));}
      bool decodeFragmentVolume(ivec3 c,out float value){
        if(!FragmentVolumeCoordInside(c)){value=0.0;return false;}
        vec2 native=texelFetch(uFragmentVolumeNative,c,0).rg;
        if(native.g<0.5){value=0.0;return false;}
        value=native.r;return true;
      }
  `;}

  function projectionVertexSource300(){return `#version 300 es
      in vec3 aPosition;
      in vec3 aNormal;
      uniform mat4 uMVP;
      uniform float uSurfaceOffsetMm;
      out vec3 vNormal;
      out vec3 vWorldPosition;
      void main(){
        vNormal=normalize(aNormal);
        vec3 displayedPosition=aPosition+vNormal*uSurfaceOffsetMm;
        vWorldPosition=displayedPosition;
        gl_Position=uMVP*vec4(displayedPosition,1.0);
      }
    `;}

  function projectionFragmentSource(spec,nativeFeature3D){
    const steps=stepBucket(spec&&spec.projectionSteps),alphaMode=Number(spec&&spec.projectionAlphaMode)===1?1:0,diagnosticMode=clamp(Math.round(finite(spec&&spec.projectionDiagnosticMode,0)),0,7),sampling=Number(spec&&spec.surfaceFeatureSampling)===0?0:2,sampleFunction=sampling===0?'voxelFaithfulProjectionSample':'continuousSignedProjectionSample',native3D=nativeFeature3D===true,textureFunction=native3D?'texture':'texture2D',fragColor=native3D?'nmFragColor':'gl_FragColor';
    return `${native3D?'#version 300 es\n':''}
      precision highp float;
      precision highp int;
      #define NM_PROJECTION_STEPS ${steps}
      #define NM_PROJECTION_ALPHA_MODE ${alphaMode}
      #define NM_PROJECTION_DIAGNOSTIC ${diagnosticMode}
      ${native3D?'in':'varying'} vec3 vNormal;
      ${native3D?'in':'varying'} vec3 vWorldPosition;
      ${native3D?'out vec4 nmFragColor;':''}
      uniform float uObjectOpacity;
      ${native3D?'uniform highp sampler3D uFragmentVolumeNative;':`uniform sampler2D uFragmentVolumeAtlas;
      uniform vec2 uFragmentVolumeGrid;
      uniform vec2 uFragmentVolumeTextureSize;`}
      uniform vec3 uFragmentVolumeDims;
      uniform mat4 uWorldToVoxel;
      uniform int uProjectionSteps;
      uniform float uProjectionStepMm;
      uniform float uProjectionSurfaceOffsetMm;
      uniform int uProjectionThresholdMode;
      uniform float uProjectionNegativeThreshold;
      uniform float uProjectionPositiveThreshold;
      uniform float uProjectionSingleThreshold;
      uniform vec2 uProjectionDisplayRange;
      uniform sampler2D uProjectionGradientLut;
      ${alphaMode===1?`uniform sampler2D uProjectionAlphaAtlas;
      uniform vec3 uProjectionAlphaDims;
      uniform vec2 uProjectionAlphaGrid;
      uniform vec2 uProjectionAlphaTextureSize;
      uniform float uProjectionAlphaSelectivity;
      uniform float uProjectionAlphaMidpoint;
      uniform float uProjectionAlphaLogCompression;`:''}
      ${clipUniforms()}
      ${native3D?nativeFeature3DDecode():floatAtlasDecode('FragmentVolume')}
      ${alphaMode===1?floatAtlasDecode('ProjectionAlpha',textureFunction):''}
      int projectionClass(float value){
        if(uProjectionThresholdMode==1){if(value<=uProjectionNegativeThreshold)return -1;if(value>=uProjectionPositiveThreshold)return 1;return 0;}
        if(uProjectionThresholdMode==2){float t=abs(uProjectionSingleThreshold);if(abs(value)<t)return 0;return value<0.0?-1:(value>0.0?1:0);}
        if(uProjectionThresholdMode==3)return value<=uProjectionSingleThreshold?-1:0;
        if(uProjectionThresholdMode==4)return value>=uProjectionSingleThreshold?1:0;
        return value<0.0?-1:(value>0.0?1:0);
      }
      ${sampling===0?`bool voxelFaithfulProjectionSample(vec3 voxel1,out float value,out int klass){
        ivec3 nearest=ivec3(floor(voxel1-vec3(0.5)));if(!decodeFragmentVolume(nearest,value)){value=0.0;klass=0;return false;}klass=projectionClass(value);return klass!=0;
      }`:`bool continuousSignedProjectionSample(vec3 voxel1,out float value,out int klass){
        vec3 voxel0=voxel1-vec3(1.0);if(any(lessThan(voxel0,vec3(-0.5)))||any(greaterThan(voxel0,uFragmentVolumeDims-vec3(0.5)))){value=0.0;klass=0;return false;}
        ivec3 nearest=ivec3(floor(voxel1-vec3(0.5)));float nearestValue;if(!decodeFragmentVolume(nearest,nearestValue)){value=0.0;klass=0;return false;}
        vec3 p=clamp(voxel0,vec3(0.0),uFragmentVolumeDims-vec3(1.0)),f=fract(p);ivec3 base=ivec3(floor(p));float weight=0.0,sum=0.0;
        for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){
          ivec3 c=base+ivec3(dx,dy,dz);c=ivec3(min(vec3(c),uFragmentVolumeDims-vec3(1.0)));float wx=dx==0?1.0-f.x:f.x,wy=dy==0?1.0-f.y:f.y,wz=dz==0?1.0-f.z:f.z,w=wx*wy*wz,candidate;
          if(w<=0.0||!decodeFragmentVolume(c,candidate))continue;weight+=w;sum+=w*candidate;
        }
        if(weight<=1e-7){value=0.0;klass=0;return false;}value=sum/weight;klass=projectionClass(value);return klass!=0;
      }`}
      bool projectionCandidateReplaces(float candidate,float bestValue){if(uProjectionThresholdMode==3)return candidate<bestValue;if(uProjectionThresholdMode==4)return candidate>bestValue;return abs(candidate)>abs(bestValue);}
      bool projectHardMaximum(out float bestValue,out int bestClass,out vec3 bestVoxel1,out float bestDepthMm){
        vec3 n=normalize(vNormal),surface=vWorldPosition-n*uProjectionSurfaceOffsetMm;bool found=false;bestValue=0.0;bestClass=0;bestVoxel1=vec3(0.0);bestDepthMm=0.0;
        for(int s=0;s<NM_PROJECTION_STEPS;s++){
          if(s>=uProjectionSteps)continue;
          float depthMm=float(s)*uProjectionStepMm;vec3 world=surface-n*depthMm,voxel=(uWorldToVoxel*vec4(world,1.0)).xyz;float candidate;int klass;
          if(!${sampleFunction}(voxel,candidate,klass))continue;
          if(!found||projectionCandidateReplaces(candidate,bestValue)){bestValue=candidate;bestClass=klass;bestVoxel1=voxel;bestDepthMm=depthMm;found=true;}
        }
        return found;
      }
      bool projectionSupport(vec3 voxel1){ivec3 nearest=ivec3(floor(voxel1-vec3(0.5)));float candidate;return decodeFragmentVolume(nearest,candidate);}
      vec4 projectionPathDiagnostic(float bestDepthMm){
        vec3 n=normalize(vNormal),surface=vWorldPosition-n*uProjectionSurfaceOffsetMm;bool seenActive=false,gapAfterActive=false,unsupportedGap=false,subthresholdGap=false,resumed=false;
        for(int s=0;s<NM_PROJECTION_STEPS;s++){
          if(s>=uProjectionSteps)continue;float depthMm=float(s)*uProjectionStepMm;if(depthMm>bestDepthMm+0.25*max(uProjectionStepMm,1e-6))continue;vec3 voxel=(uWorldToVoxel*vec4(surface-n*depthMm,1.0)).xyz;float candidate;int klass;bool isActive=${sampleFunction}(voxel,candidate,klass),supported=projectionSupport(voxel);
          if(isActive){if(seenActive&&gapAfterActive)resumed=true;seenActive=true;gapAfterActive=false;}else if(seenActive){gapAfterActive=true;if(supported)subthresholdGap=true;else unsupportedGap=true;}
        }
        return vec4(unsupportedGap?1.0:0.0,subthresholdGap?1.0:0.0,resumed?1.0:0.0,1.0);
      }
      vec3 projectionColor(float value){float t=clamp((value-uProjectionDisplayRange.x)/max(1e-20,uProjectionDisplayRange.y-uProjectionDisplayRange.x),0.0,1.0);return ${textureFunction}(uProjectionGradientLut,vec2(t,0.5)).rgb;}
      ${alphaMode===1?`
      float projectionAlphaTransfer(float support){
        float raw=clamp(support,0.0,1.0),lambda=max(uProjectionAlphaLogCompression,0.0),u=lambda>0.000001?log(1.0+lambda*raw)/log(1.0+lambda):raw,k=clamp(uProjectionAlphaSelectivity,4.0,48.0),midpoint=clamp(uProjectionAlphaMidpoint,0.02,0.5);
        float lo=1.0/(1.0+exp(k*midpoint)),hi=1.0/(1.0+exp(-k*(1.0-midpoint))),current=1.0/(1.0+exp(-k*(u-midpoint)));
        return clamp((current-lo)/max(hi-lo,0.000001),0.0,1.0);
      }
      float projectionAlphaAt(vec3 voxel1){
        vec3 voxel0=voxel1-vec3(1.0);if(any(lessThan(voxel0,vec3(-0.5)))||any(greaterThan(voxel0,uProjectionAlphaDims-vec3(0.5))))return 0.0;
        vec3 p=clamp(voxel0,vec3(0.0),uProjectionAlphaDims-vec3(1.0)),f=fract(p);ivec3 base=ivec3(floor(p));float sum=0.0,weight=0.0;
        for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){ivec3 c=base+ivec3(dx,dy,dz);c=ivec3(min(vec3(c),uProjectionAlphaDims-vec3(1.0)));float wx=dx==0?1.0-f.x:f.x,wy=dy==0?1.0-f.y:f.y,wz=dz==0?1.0-f.z:f.z,w=wx*wy*wz,candidate;if(w<=0.0||!decodeProjectionAlpha(c,candidate))continue;sum+=w*candidate;weight+=w;}
        return weight>1e-7?projectionAlphaTransfer(sum/weight):0.0;
      }`:''}
      vec4 packed16(float normalized,float blue){float packedValue=floor(clamp(normalized,0.0,1.0)*65535.0+0.5),highByte=floor(packedValue/256.0),lowByte=packedValue-highByte*256.0;return vec4(highByte/255.0,lowByte/255.0,blue,1.0);}
      void main(){
        if(clipped())discard;
        float projectedValue,projectedDepthMm;vec3 projectedVoxel1;int projectedClass;if(!projectHardMaximum(projectedValue,projectedClass,projectedVoxel1,projectedDepthMm))discard;
        float supportAlpha=${alphaMode===1?'projectionAlphaAt(projectedVoxel1)':'1.0'};
        #if NM_PROJECTION_DIAGNOSTIC == 1
          float maxDepth=max(float(uProjectionSteps>1?uProjectionSteps-1:0)*uProjectionStepMm,1e-6);${fragColor}=packed16(projectedDepthMm/maxDepth,projectedClass<0?0.0:1.0);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 2
          ${fragColor}=packed16((projectedVoxel1.x-0.5)/max(uFragmentVolumeDims.x,1.0),0.0);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 3
          ${fragColor}=packed16((projectedVoxel1.y-0.5)/max(uFragmentVolumeDims.y,1.0),0.0);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 4
          ${fragColor}=packed16((projectedVoxel1.z-0.5)/max(uFragmentVolumeDims.z,1.0),0.0);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 5
          ${fragColor}=packed16((projectedValue-uProjectionDisplayRange.x)/max(1e-20,uProjectionDisplayRange.y-uProjectionDisplayRange.x),0.0);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 6
          ${fragColor}=projectionPathDiagnostic(projectedDepthMm);return;
        #elif NM_PROJECTION_DIAGNOSTIC == 7
          ${fragColor}=packed16(supportAlpha,0.0);return;
        #else
          float alpha=uObjectOpacity*supportAlpha;if(alpha<=0.002)discard;${fragColor}=vec4(projectionColor(projectedValue),clamp(alpha,0.0,1.0));
        #endif
      }
    `;
  }

  function outlineFragmentSource(){return `
      precision highp float;
      varying vec3 vNormal;
      varying vec3 vWorldPosition;
      uniform int uDoubleSided;
      uniform vec3 uBaseColor;
      uniform float uObjectOpacity;
      uniform vec3 uEyeWorld;
      ${clipUniforms()}
      void main(){
        if(clipped())discard;
        vec3 n=normalize(vNormal);if(uDoubleSided==1&&!gl_FrontFacing)n=-n;
        float rim=clamp(1.0-abs(dot(n,normalize(uEyeWorld-vWorldPosition))),0.0,1.0),alpha=clamp(uObjectOpacity*smoothstep(.56,.93,rim),0.0,1.0);if(alpha<=0.002)discard;
        gl_FragColor=vec4(uBaseColor,alpha);
      }
    `;}

  function atlasLabelCommon(){return `
      uniform sampler2D uAtlasLabelAtlas;
      uniform vec3 uAtlasLabelDims;
      uniform vec2 uAtlasLabelGrid;
      uniform vec2 uAtlasLabelTextureSize;
      uniform mat4 uAtlasWorldToVoxel;
      bool atlasCoordInside(ivec3 c){return c.x>=0&&c.y>=0&&c.z>=0&&float(c.x)<uAtlasLabelDims.x&&float(c.y)<uAtlasLabelDims.y&&float(c.z)<uAtlasLabelDims.z;}
      float atlasLabelAtCoord(ivec3 c){
        if(!atlasCoordInside(c))return 0.0;
        float z=float(c.z),tileY=floor((z+0.5)/uAtlasLabelGrid.x),tileX=z-tileY*uAtlasLabelGrid.x;
        vec2 pixel=vec2(tileX*uAtlasLabelDims.x+float(c.x)+0.5,tileY*uAtlasLabelDims.y+float(c.y)+0.5);
        vec4 bytes=floor(texture2D(uAtlasLabelAtlas,pixel/uAtlasLabelTextureSize)*255.0+0.5);
        return bytes.r+bytes.g*256.0+bytes.b*65536.0+bytes.a*16777216.0;
      }
      float atlasLabelAtWorld(vec3 world){vec3 voxel=(uAtlasWorldToVoxel*vec4(world,1.0)).xyz;return atlasLabelAtCoord(ivec3(floor(voxel-vec3(0.5))));}
  `;}

  function atlasBoundaryFragmentSource(spec){
    const steps=atlasStepBucket(spec&&spec.atlasBoundaryProjectionSteps),projected=Number(spec&&spec.atlasBoundaryProjectionMode)!==0;
    return `
      precision highp float;
      precision highp int;
      #define NM_ATLAS_STEPS ${steps}
      varying vec3 vNormal;
      varying vec3 vWorldPosition;
      uniform float uObjectOpacity;
      uniform vec3 uAtlasBoundaryColor;
      uniform float uAtlasBoundaryOpacity;
      uniform float uAtlasBoundaryStepMm;
      uniform int uAtlasBoundaryProjectionSteps;
      uniform float uAtlasBoundaryProjectionStepMm;
      ${clipUniforms()}
      ${atlasLabelCommon()}
      bool labelsDiffer(float a,float b){return a>0.5&&b>0.5&&abs(a-b)>0.5;}
      bool projectedAtlasLabel(vec3 surface,vec3 normal,out float labelValue){
        ${projected?`vec3 n=normalize(normal);float candidate=0.0,firstNonzero=0.0;int stableCount=0;
        for(int s=0;s<NM_ATLAS_STEPS;s++){
          if(s>=uAtlasBoundaryProjectionSteps)continue;
          float current=atlasLabelAtWorld(surface-n*(float(s)*uAtlasBoundaryProjectionStepMm));
          if(current<0.5){candidate=0.0;stableCount=0;continue;}
          if(firstNonzero<0.5)firstNonzero=current;
          if(candidate>0.5&&abs(current-candidate)<0.5){stableCount+=1;if(stableCount>=2){labelValue=candidate;return true;}}
          else{candidate=current;stableCount=1;}
        }
        labelValue=firstNonzero;return labelValue>0.5;`:`labelValue=atlasLabelAtWorld(surface);return labelValue>0.5;`}
      }
      void main(){
        if(clipped())discard;
        vec3 n=normalize(vNormal),reference=abs(n.z)<0.85?vec3(0.0,0.0,1.0):vec3(0.0,1.0,0.0),t1=normalize(cross(n,reference)),t2=normalize(cross(n,t1));
        float center,other;if(!projectedAtlasLabel(vWorldPosition,n,center))discard;float stepMm=max(0.05,uAtlasBoundaryStepMm);float boundary=0.0;
        if(projectedAtlasLabel(vWorldPosition+t1*stepMm,n,other)&&labelsDiffer(center,other))boundary=1.0;
        else if(projectedAtlasLabel(vWorldPosition-t1*stepMm,n,other)&&labelsDiffer(center,other))boundary=1.0;
        else if(projectedAtlasLabel(vWorldPosition+t2*stepMm,n,other)&&labelsDiffer(center,other))boundary=1.0;
        else if(projectedAtlasLabel(vWorldPosition-t2*stepMm,n,other)&&labelsDiffer(center,other))boundary=1.0;
        if(boundary<=0.001)discard;gl_FragColor=vec4(uAtlasBoundaryColor,clamp(uObjectOpacity*uAtlasBoundaryOpacity*boundary,0.0,1.0));
      }
    `;
  }

  function atlasLabelFragmentSource(){return `
      precision highp float;
      precision highp int;
      varying vec3 vWorldPosition;
      ${clipUniforms()}
      ${atlasLabelCommon()}
      void main(){
        if(clipped())discard;float labelValue=atlasLabelAtWorld(vWorldPosition);if(labelValue<0.5)discard;float labelCode=floor(labelValue+0.5),r=mod(labelCode,256.0),g=mod(floor(labelCode/256.0),256.0),b=mod(floor(labelCode/65536.0),256.0);gl_FragColor=vec4(r/255.0,g/255.0,b/255.0,gl_FragCoord.z);
      }
    `;}

  /*
   * Purpose: render the shared structural locator/cut-slice plane while sampling
   * the authoritative feature field according to its declared interpolation mode.
   * Inputs: normalized locator style and whether the WebGL2 native feature texture
   * is installed. Structural anatomy remains a support-aware continuous 2-D atlas.
   * Authority and flow: feature values/support are consumed from the same native
   * RG32F resource as surface projection and volume rendering on WebGL2; WebGL1
   * retains the packed feature atlas but uses identical sampling semantics.
   * Scientific/state contract: voxel_faithful is one nearest supported native voxel;
   * support_aware_linear interpolates classified positive/negative contributors
   * independently and never cancels opposite polarities before thresholding.
   * Invariants: the shader does not alter ROI identity, support, thresholds or values.
   * Materialization and performance: no feature arrays are created here; one texelFetch
   * serves voxel-faithful feature samples and at most eight reads serve linear samples.
   * Failure semantics: unsupported/out-of-grid/subthreshold feature samples leave the
   * structural slice visible; resource/program failures remain explicit in the renderer.
   * Consumers and dependencies: volume_locator and volume_slice mesh color modes.
   */
  function locatorFragmentSource(spec,nativeFeature3D){
    const mode=Number(spec&&spec.colorMode)===11?11:8,native3D=nativeFeature3D===true,textureFunction=native3D?'texture':'texture2D',fragColor=native3D?'nmFragColor':'gl_FragColor';
    return `${native3D?'#version 300 es\n':''}
      precision highp float;
      precision highp int;
      ${native3D?'in':'varying'} vec3 vNormal;
      ${native3D?'in':'varying'} vec3 vWorldPosition;
      ${native3D?'out vec4 nmFragColor;':''}
      uniform float uObjectOpacity;
      uniform float uStructuralGamma;
      uniform vec2 uStructuralWindow;
      uniform float uLocatorOverlayOpacity;
      uniform sampler2D uStructuralVolumeAtlas;
      uniform vec3 uStructuralVolumeDims;
      uniform vec2 uStructuralVolumeGrid;
      uniform vec2 uStructuralVolumeTextureSize;
      uniform mat4 uStructuralWorldToVoxel;
      ${native3D?'uniform highp sampler3D uFragmentVolumeNative;':`uniform sampler2D uFragmentVolumeAtlas;
      uniform vec2 uFragmentVolumeGrid;
      uniform vec2 uFragmentVolumeTextureSize;`}
      uniform vec3 uFragmentVolumeDims;
      uniform mat4 uWorldToVoxel;
      uniform int uFeatureInterpolation;
      uniform int uProjectionThresholdMode;
      uniform float uProjectionNegativeThreshold;
      uniform float uProjectionPositiveThreshold;
      uniform float uProjectionSingleThreshold;
      uniform vec2 uProjectionDisplayRange;
      uniform sampler2D uProjectionGradientLut;
      ${clipUniforms()}
      ${floatAtlasDecode('StructuralVolume',textureFunction)}
      ${native3D?nativeFeature3DDecode():floatAtlasDecode('FragmentVolume')}
      int projectionClass(float value){if(uProjectionThresholdMode==1){if(value<=uProjectionNegativeThreshold)return -1;if(value>=uProjectionPositiveThreshold)return 1;return 0;}if(uProjectionThresholdMode==2){float t=abs(uProjectionSingleThreshold);if(abs(value)<t)return 0;return value<0.0?-1:(value>0.0?1:0);}if(uProjectionThresholdMode==3)return value<=uProjectionSingleThreshold?-1:0;if(uProjectionThresholdMode==4)return value>=uProjectionSingleThreshold?1:0;return value<0.0?-1:(value>0.0?1:0);}
      bool supportAwareStructuralSample(vec3 voxel1,out float value,out float coverage){
        vec3 voxel0=voxel1-vec3(1.0);coverage=0.0;if(any(lessThan(voxel0,vec3(-0.5)))||any(greaterThan(voxel0,uStructuralVolumeDims-vec3(0.5)))){value=0.0;return false;}
        vec3 p=clamp(voxel0,vec3(0.0),uStructuralVolumeDims-vec3(1.0)),f=fract(p);ivec3 base=ivec3(floor(p));float sum=0.0,weight=0.0;
        for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){ivec3 c=base+ivec3(dx,dy,dz);c=ivec3(min(vec3(c),uStructuralVolumeDims-vec3(1.0)));float wx=dx==0?1.0-f.x:f.x,wy=dy==0?1.0-f.y:f.y,wz=dz==0?1.0-f.z:f.z,w=wx*wy*wz,candidate;if(w<=0.0||!decodeStructuralVolume(c,candidate))continue;sum+=w*candidate;weight+=w;}
        if(weight<=1e-7){value=0.0;return false;}value=sum/weight;coverage=clamp(weight,0.0,1.0);return true;
      }
      bool featureSample(vec3 voxel1,out float value,out float coverage,out int klass){
        coverage=0.0;klass=0;
        if(uFeatureInterpolation==0){ivec3 nearest=ivec3(floor(voxel1-vec3(0.5)));if(!decodeFragmentVolume(nearest,value)){value=0.0;return false;}klass=projectionClass(value);coverage=klass==0?0.0:1.0;return klass!=0;}
        vec3 voxel0=voxel1-vec3(1.0);if(any(lessThan(voxel0,vec3(-0.5)))||any(greaterThan(voxel0,uFragmentVolumeDims-vec3(0.5)))){value=0.0;return false;}
        ivec3 nearest=ivec3(floor(voxel1-vec3(0.5)));float nearestValue=0.0;int nearestClass=decodeFragmentVolume(nearest,nearestValue)?projectionClass(nearestValue):0;
        vec3 p=clamp(voxel0,vec3(0.0),uFragmentVolumeDims-vec3(1.0)),f=fract(p);ivec3 base=ivec3(floor(p));float negativeWeight=0.0,negativeSum=0.0,negativeMin=3.402823466e38,negativeMax=-3.402823466e38,positiveWeight=0.0,positiveSum=0.0,positiveMin=3.402823466e38,positiveMax=-3.402823466e38;
        for(int dz=0;dz<2;dz++)for(int dy=0;dy<2;dy++)for(int dx=0;dx<2;dx++){ivec3 c=base+ivec3(dx,dy,dz);c=ivec3(min(vec3(c),uFragmentVolumeDims-vec3(1.0)));float wx=dx==0?1.0-f.x:f.x,wy=dy==0?1.0-f.y:f.y,wz=dz==0?1.0-f.z:f.z,w=wx*wy*wz,candidate;if(w<=0.0||!decodeFragmentVolume(c,candidate))continue;int candidateClass=projectionClass(candidate);if(candidateClass<0){negativeWeight+=w;negativeSum+=w*candidate;negativeMin=min(negativeMin,candidate);negativeMax=max(negativeMax,candidate);}else if(candidateClass>0){positiveWeight+=w;positiveSum+=w*candidate;positiveMin=min(positiveMin,candidate);positiveMax=max(positiveMax,candidate);}}
        int displayClass=0;if(negativeWeight>positiveWeight)displayClass=-1;else if(positiveWeight>negativeWeight)displayClass=1;else if(positiveWeight>0.0||negativeWeight>0.0)displayClass=nearestClass!=0?nearestClass:(abs(negativeSum)>abs(positiveSum)?-1:1);
        float weight=displayClass<0?negativeWeight:positiveWeight,sum=displayClass<0?negativeSum:positiveSum,minValue=displayClass<0?negativeMin:positiveMin,maxValue=displayClass<0?negativeMax:positiveMax;
        if(displayClass==0||weight<=1e-7){value=0.0;return false;}coverage=clamp(weight,0.0,1.0);value=clamp(sum/weight,minValue,maxValue);klass=coverage>=0.5?displayClass:0;return klass!=0;
      }
      vec3 projectionColor(float value){float t=clamp((value-uProjectionDisplayRange.x)/max(1e-20,uProjectionDisplayRange.y-uProjectionDisplayRange.x),0.0,1.0);return ${textureFunction}(uProjectionGradientLut,vec2(t,0.5)).rgb;}
      void main(){
        if(clipped())discard;float structuralValue,structuralCoverage;if(!supportAwareStructuralSample((uStructuralWorldToVoxel*vec4(vWorldPosition,1.0)).xyz,structuralValue,structuralCoverage))discard;
        float normalizedValue=clamp((structuralValue-uStructuralWindow.x)/max(1e-20,uStructuralWindow.y-uStructuralWindow.x),0.0,1.0);normalizedValue=pow(normalizedValue,1.0/max(.05,uStructuralGamma));
        ${mode===11?'float tissue=clamp((normalizedValue-.025)/.95,0.0,1.0);tissue=tissue*tissue*(3.0-2.0*tissue);float gray=clamp(.025+.965*pow(tissue,1.12),0.0,1.0);':'float gray=normalizedValue;'}
        vec3 color=vec3(gray);float alpha=clamp(uObjectOpacity*smoothstep(${mode===11?'.08,.72':'.05,.55'},structuralCoverage),0.0,1.0);
        float featureValue,featureCoverage;int featureClass;if(featureSample((uWorldToVoxel*vec4(vWorldPosition,1.0)).xyz,featureValue,featureCoverage,featureClass)){float edgeAlpha=uFeatureInterpolation==0?1.0:smoothstep(.34,.66,featureCoverage);color=mix(color,projectionColor(featureValue),clamp(uLocatorOverlayOpacity*edgeAlpha,0.0,1.0));}
        if(alpha<=0.002)discard;${fragColor}=vec4(color,alpha);
      }
    `;
  }

  function normalizeSpec(style){
    const s=style||{},mode=Math.round(finite(s.colorMode,0));
    if(mode>=0&&mode<=4)return {role:ROLE.BASE,key:ROLE.BASE,colorMode:mode};
    if(mode===5){const sampling=Math.round(finite(s.surfaceFeatureSampling,2));if(sampling!==0&&sampling!==2)throw new Error('The selected surface-projection sampling mode is unavailable for this view.');const bucket=stepBucket(s.projectionSteps),alpha=Number(s.projectionAlphaMode)===1?1:0,diagnostic=clamp(Math.round(finite(s.projectionDiagnosticMode,0)),0,7),role=diagnostic?ROLE.PROJECTION_DIAGNOSTIC:ROLE.SURFACE_PROJECTION;return {role,key:`${role}|sampling=${sampling}|steps=${bucket}|alpha=${alpha}${diagnostic?`|diagnostic=${diagnostic}`:''}`,colorMode:mode,surfaceFeatureSampling:sampling,projectionSteps:bucket,projectionAlphaMode:alpha,projectionDiagnosticMode:diagnostic};}
    if(mode===6){const bucket=atlasStepBucket(s.atlasBoundaryProjectionSteps),projected=Number(s.atlasBoundaryProjectionMode)!==0?1:0;return {role:ROLE.ATLAS_BOUNDARY,key:`${ROLE.ATLAS_BOUNDARY}|steps=${bucket}|projected=${projected}`,colorMode:mode,atlasBoundaryProjectionSteps:bucket,atlasBoundaryProjectionMode:projected};}
    if(mode===7)return {role:ROLE.ATLAS_LABEL,key:ROLE.ATLAS_LABEL,colorMode:mode};
    if(mode===8||mode===11)return {role:ROLE.LOCATOR,key:`${ROLE.LOCATOR}|mode=${mode}`,colorMode:mode};
    if(mode===10)return {role:ROLE.OUTLINE,key:ROLE.OUTLINE,colorMode:mode};
    if(mode===12)return {role:ROLE.ATLAS_BOUNDARY_RIBBON,key:ROLE.ATLAS_BOUNDARY_RIBBON,colorMode:mode};
    throw new Error(`Unsupported mesh color mode: ${mode}.`);
  }

  function fragmentSource(spec,options){
    const nativeFeature3D=!!(options&&options.nativeFeature3D);
    switch(spec.role){
      case ROLE.BASE:return baseFragmentSource();
      case ROLE.SURFACE_PROJECTION:
      case ROLE.PROJECTION_DIAGNOSTIC:return projectionFragmentSource(spec,nativeFeature3D);
      case ROLE.OUTLINE:return outlineFragmentSource();
      case ROLE.ATLAS_BOUNDARY:return atlasBoundaryFragmentSource(spec);
      case ROLE.ATLAS_LABEL:return atlasLabelFragmentSource();
      case ROLE.LOCATOR:return locatorFragmentSource(spec,nativeFeature3D);
      case ROLE.ATLAS_BOUNDARY_RIBBON:return ribbonFragmentSource();
      default:throw new Error(`Unsupported specialized mesh-program role: ${spec.role}`);
    }
  }

  function isProjectionRole(spec){return !!spec&&(spec.role===ROLE.SURFACE_PROJECTION||spec.role===ROLE.PROJECTION_DIAGNOSTIC);}
  function isFeatureFragmentRole(spec){return isProjectionRole(spec)||!!spec&&spec.role===ROLE.LOCATOR;}
  function nativeFeature3DContext(gl,spec){return isFeatureFragmentRole(spec)&&!!gl&&typeof gl.texImage3D==='function'&&gl.TEXTURE_3D!==undefined;}
  function sourcesForSpec(spec,options){const normalized=spec&&spec.role?spec:normalizeSpec(spec),nativeFeature3D=isFeatureFragmentRole(normalized)&&!!(options&&options.nativeFeature3D),vertex=nativeFeature3D?projectionVertexSource300():vertexSource(normalized.role),fragment=fragmentSource(normalized,{nativeFeature3D});return {spec:normalized,vertex,fragment,identity:{key:normalized.key,role:normalized.role,featureVolumeRepresentation:nativeFeature3D?'native_texture_3d':'packed_texture_2d',sourceBytes:vertex.length+fragment.length,sourceLines:(vertex.match(/\n/g)||[]).length+(fragment.match(/\n/g)||[]).length+2,sourceHash:hashText(vertex+'\n---fragment---\n'+fragment)}};}

  function locations(gl,program,spec,options){
    const names={attributes:[],uniforms:[]},nativeFeature3D=isFeatureFragmentRole(spec)&&!!(options&&options.nativeFeature3D);
    if(spec.role===ROLE.BASE)names.attributes=COMMON_ATTRIBS.slice();else if(spec.role===ROLE.ATLAS_BOUNDARY_RIBBON)names.attributes=['aPosition','aNormal','aValue'];else names.attributes=['aPosition','aNormal'];
    names.uniforms=COMMON_UNIFORMS.slice();
    if(spec.role===ROLE.BASE||spec.role===ROLE.ATLAS_BOUNDARY_RIBBON)names.uniforms.push('uColorMode');
    if(spec.role===ROLE.ATLAS_BOUNDARY_RIBBON)names.uniforms.push('uViewport','uLineWidthPx','uDepthBias','uAtlasBoundaryColor','uAtlasBoundaryOpacity');
    if(spec.role===ROLE.SURFACE_PROJECTION||spec.role===ROLE.PROJECTION_DIAGNOSTIC){names.uniforms.push(nativeFeature3D?'uFragmentVolumeNative':'uFragmentVolumeAtlas','uFragmentVolumeDims','uWorldToVoxel','uProjectionSteps','uProjectionStepMm','uProjectionSurfaceOffsetMm','uProjectionThresholdMode','uProjectionNegativeThreshold','uProjectionPositiveThreshold','uProjectionSingleThreshold','uProjectionDisplayRange','uProjectionGradientLut','uProjectionAlphaAtlas','uProjectionAlphaDims','uProjectionAlphaGrid','uProjectionAlphaTextureSize','uProjectionAlphaSelectivity','uProjectionAlphaMidpoint','uProjectionAlphaLogCompression');if(!nativeFeature3D)names.uniforms.push('uFragmentVolumeGrid','uFragmentVolumeTextureSize');}
    if(spec.role===ROLE.ATLAS_BOUNDARY||spec.role===ROLE.ATLAS_LABEL)names.uniforms.push('uAtlasLabelAtlas','uAtlasLabelDims','uAtlasLabelGrid','uAtlasLabelTextureSize','uAtlasWorldToVoxel');
    if(spec.role===ROLE.ATLAS_BOUNDARY)names.uniforms.push('uAtlasBoundaryColor','uAtlasBoundaryOpacity','uAtlasBoundaryStepMm','uAtlasBoundaryProjectionSteps','uAtlasBoundaryProjectionStepMm');
    if(spec.role===ROLE.LOCATOR){names.uniforms.push('uStructuralVolumeAtlas','uStructuralVolumeDims','uStructuralVolumeGrid','uStructuralVolumeTextureSize','uStructuralWorldToVoxel','uStructuralWindow','uStructuralGamma',nativeFeature3D?'uFragmentVolumeNative':'uFragmentVolumeAtlas','uFragmentVolumeDims','uWorldToVoxel','uFeatureInterpolation','uProjectionThresholdMode','uProjectionNegativeThreshold','uProjectionPositiveThreshold','uProjectionSingleThreshold','uProjectionDisplayRange','uProjectionGradientLut','uLocatorOverlayOpacity');if(!nativeFeature3D)names.uniforms.push('uFragmentVolumeGrid','uFragmentVolumeTextureSize');}
    const out={};names.attributes.forEach(name=>{out[name]=gl.getAttribLocation(program,name);});names.uniforms.forEach(name=>{out[name]=gl.getUniformLocation(program,name);});return out;
  }

  function compileProgram(gl,spec,options){
    const opts=options||{},normalized=spec&&spec.role?spec:normalizeSpec(spec),nativeFeature3D=opts.nativeFeature3D===undefined?nativeFeature3DContext(gl,normalized):isFeatureFragmentRole(normalized)&&opts.nativeFeature3D===true,src=sourcesForSpec(normalized,{nativeFeature3D}),started=typeof performance!=='undefined'&&performance.now?performance.now():Date.now(),vertex=gl.createShader(gl.VERTEX_SHADER),fragment=gl.createShader(gl.FRAGMENT_SHADER);let program=null;
    gl.shaderSource(vertex,src.vertex);gl.shaderSource(fragment,src.fragment);gl.compileShader(vertex);gl.compileShader(fragment);program=gl.createProgram();gl.attachShader(program,vertex);gl.attachShader(program,fragment);gl.linkProgram(program);
    const linked=!!gl.getProgramParameter(program,gl.LINK_STATUS),elapsed=(typeof performance!=='undefined'&&performance.now?performance.now():Date.now())-started;
    if(!linked){const vertexOk=gl.getShaderParameter(vertex,gl.COMPILE_STATUS),fragmentOk=gl.getShaderParameter(fragment,gl.COMPILE_STATUS),message=[gl.getProgramInfoLog(program)||'mesh program link failed',vertexOk?'':gl.getShaderInfoLog(vertex)||'vertex shader compile failed',fragmentOk?'':gl.getShaderInfoLog(fragment)||'fragment shader compile failed'].filter(Boolean).join('\n');gl.deleteShader(vertex);gl.deleteShader(fragment);gl.deleteProgram(program);const error=new Error(message);error.code='mesh_program_link_failed';error.programKey=src.spec.key;throw error;}
    gl.deleteShader(vertex);gl.deleteShader(fragment);const handle={program,locations:locations(gl,program,src.spec,{nativeFeature3D}),spec:src.spec,identity:src.identity,compileMs:elapsed,createdAt:Date.now()};if(typeof opts.onProfile==='function')opts.onProfile({phase:'mesh_program_compile',programKey:src.spec.key,programRole:src.spec.role,elapsedMs:elapsed,sourceBytes:src.identity.sourceBytes,sourceLines:src.identity.sourceLines,sourceHash:src.identity.sourceHash,featureVolumeRepresentation:src.identity.featureVolumeRepresentation,locationCount:Object.keys(handle.locations).length,compileStatusQueriedBeforeLinkFailure:0});return handle;
  }

  window.NMWebGLMeshPrograms={CONTRACT,ROLE,stepBucket,atlasStepBucket,normalizeSpec,sourcesForSpec,compileProgram,locations,_test:{hashText,vertexSource,projectionVertexSource300,nativeFeature3DContext,isFeatureFragmentRole,ribbonVertexSource,ribbonFragmentSource,baseFragmentSource,projectionFragmentSource,outlineFragmentSource,atlasBoundaryFragmentSource,atlasLabelFragmentSource,locatorFragmentSource}};
})();
