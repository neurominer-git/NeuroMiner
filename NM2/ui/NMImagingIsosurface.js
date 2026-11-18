(function(root){
  'use strict';

  const {clamp}=globalThis.NMResultsViewerPrimitives;
  function arr(v){return Array.isArray(v)||ArrayBuffer.isView(v)?Array.from(v):[];}
  function finite(v,d){const n=Number(v);return Number.isFinite(n)?n:d;}
  function displaySemantics(){const api=root.NMResultsViewerDisplaySemantics;if(!api||typeof api.assertDisplayContract!=='function')throw new Error('The canonical Results Viewer display-contract assertion authority is unavailable.');return api;}
  function index(d,x,y,z){return x+d[0]*(y+d[1]*z);}
  function transform(m,p){return [0,1,2].map(r=>m[r][0]*p[0]+m[r][1]*p[1]+m[r][2]*p[2]+m[r][3]);}
  function add(a,b){return [a[0]+b[0],a[1]+b[1],a[2]+b[2]];}
  function sub(a,b){return [a[0]-b[0],a[1]-b[1],a[2]-b[2]];}
  function scale(a,s){return [a[0]*s,a[1]*s,a[2]*s];}
  function dot(a,b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
  function cross(a,b){return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];}
  function mean(points){const out=[0,0,0];points.forEach(p=>{out[0]+=p[0];out[1]+=p[1];out[2]+=p[2];});return scale(out,1/Math.max(1,points.length));}
  function interpolate(pa,pb,va,vb){const den=va-vb,t=Math.abs(den)<1e-12?.5:clamp(va/den,0,1);return add(pa,scale(sub(pb,pa),t));}

  function thresholds(contract,range){
    displaySemantics().assertDisplayContract(contract,{consumer:'NMImagingIsosurface threshold extraction',message:'Volumetric isosurface generation requires a canonical display contract.',facets:['threshold']});
    const threshold=contract.threshold,mode=String(threshold.mode||'').toLowerCase();
    const lo=finite(range&&range[0],0),hi=finite(range&&range[1],0);
    if(mode==='none')return {negative:lo<0?0:null,positive:hi>0?0:null};
    if(mode==='outside_interval')return {negative:threshold.lower,positive:threshold.upper};
    if(mode==='above_abs')return {negative:-threshold.value,positive:threshold.value};
    if(mode==='below')return {negative:threshold.value,positive:null};
    if(mode==='above')return {negative:null,positive:threshold.value};
    throw new Error(`Unknown canonical threshold mode: ${mode}`);
  }


  const CORNERS=[[0,0,0],[1,0,0],[1,1,0],[0,1,0],[0,0,1],[1,0,1],[1,1,1],[0,1,1]];
  const TETRA=[[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]];

  function orientedTriangle(a,b,c,outward){
    const n=cross(sub(b,a),sub(c,a));
    return dot(n,outward)>=0?[a,b,c]:[a,c,b];
  }

  function polygonizeTetra(points,values,emit){
    const inside=[],outside=[];
    for(let i=0;i<4;i++)(values[i]>=0?inside:outside).push(i);
    if(!inside.length||inside.length===4)return true;
    const outward=sub(mean(outside.map(i=>points[i])),mean(inside.map(i=>points[i])));
    if(inside.length===1||inside.length===3){
      const pivot=(inside.length===1?inside:outside)[0];
      const others=(inside.length===1?outside:inside);
      const pts=others.map(i=>interpolate(points[pivot],points[i],values[pivot],values[i]));
      return emit(orientedTriangle(pts[0],pts[1],pts[2],outward));
    }
    const i0=inside[0],i1=inside[1],o0=outside[0],o1=outside[1];
    const p00=interpolate(points[i0],points[o0],values[i0],values[o0]);
    const p01=interpolate(points[i0],points[o1],values[i0],values[o1]);
    const p10=interpolate(points[i1],points[o0],values[i1],values[o0]);
    const p11=interpolate(points[i1],points[o1],values[i1],values[o1]);
    if(!emit(orientedTriangle(p00,p10,p11,outward)))return false;
    return emit(orientedTriangle(p00,p11,p01,outward));
  }

  function qualitySpec(q){
    q=String(q||'balanced');
    if(q==='draft')return {requestedStride:3,maxTriangles:80000,maxAdaptiveStride:18};
    if(q==='high')return {requestedStride:1,maxTriangles:350000,maxAdaptiveStride:18};
    return {requestedStride:2,maxTriangles:180000,maxAdaptiveStride:18};
  }

  function emptyPolarity(){
    return {vertices:new Float32Array(0),indices:new Uint32Array(0),triangleCount:0,budgetExceeded:false};
  }

  function buildPolarityAttempt(input,threshold,polarity,stride,maxTriangles){
    if(!Number.isFinite(threshold))return emptyPolarity();
    const dims=input.dims,data=input.data,support=input.support,affine=input.affine;
    const vertices=[],indices=[];
    let triangles=0,budgetExceeded=false;
    const emit=tri=>{
      if(triangles>=maxTriangles){budgetExceeded=true;return false;}
      for(const p of tri){
        const world=transform(affine,[p[0]+1,p[1]+1,p[2]+1]);
        vertices.push(world[0],world[1],world[2]);
        indices.push(indices.length);
      }
      triangles++;
      return true;
    };

    outer:for(let z=0;z<dims[2]-1;z+=stride){
      const z1=Math.min(dims[2]-1,z+stride);
      for(let y=0;y<dims[1]-1;y+=stride){
        const y1=Math.min(dims[1]-1,y+stride);
        for(let x=0;x<dims[0]-1;x+=stride){
          const x1=Math.min(dims[0]-1,x+stride);
          const coords=[[x,y,z],[x1,y,z],[x1,y1,z],[x,y1,z],[x,y,z1],[x1,y,z1],[x1,y1,z1],[x,y1,z1]];
          const values=coords.map(c=>{
            const idx=index(dims,c[0],c[1],c[2]),v=Number(data[idx]);
            if(!support[idx]||!Number.isFinite(v))return -1e30;
            return polarity==='positive'?v-threshold:threshold-v;
          });
          let hasIn=false,hasOut=false;
          for(const v of values){if(v>=0)hasIn=true;else hasOut=true;}
          if(!hasIn||!hasOut)continue;
          for(const tet of TETRA){
            const ok=polygonizeTetra(tet.map(i=>coords[i]),tet.map(i=>values[i]),emit);
            if(!ok||budgetExceeded)break outer;
          }
        }
      }
    }

    if(budgetExceeded)return {vertices:null,indices:null,triangleCount:triangles,budgetExceeded:true};
    return {vertices:new Float32Array(vertices),indices:new Uint32Array(indices),triangleCount:triangles,budgetExceeded:false};
  }

  function adaptiveBuild(input,cutoffs,spec){
    const largestCellSpan=Math.max(1,Math.max(input.dims[0]-1,input.dims[1]-1,input.dims[2]-1));
    const maxStride=Math.min(largestCellSpan,Math.max(spec.requestedStride,spec.maxAdaptiveStride));
    let stride=spec.requestedStride,lastExceeded=[];

    while(stride<=maxStride){
      const positive=buildPolarityAttempt(input,cutoffs.positive,'positive',stride,spec.maxTriangles);
      const negative=buildPolarityAttempt(input,cutoffs.negative,'negative',stride,spec.maxTriangles);
      lastExceeded=[];
      if(positive.budgetExceeded)lastExceeded.push('positive');
      if(negative.budgetExceeded)lastExceeded.push('negative');
      if(!lastExceeded.length){
        positive.truncated=false;negative.truncated=false;
        return {
          positive,negative,
          requestedStride:spec.requestedStride,
          effectiveStride:stride,
          budgetAdjusted:stride!==spec.requestedStride,
          complete:true,
          maxTrianglesPerPolarity:spec.maxTriangles
        };
      }
      stride++;
    }

    throw new Error(
      'Complete volumetric isosurface generation exceeded the triangle budget for '+
      lastExceeded.join(' and ')+' geometry at all allowed adaptive strides. No partial mesh was returned.'
    );
  }

  function build(input){
    const dims=arr(input&&input.dims).slice(0,3).map(Number);
    const affine=arr(input&&input.affine).map(r=>arr(r).slice(0,4).map(Number));
    const data=input&&input.data,support=input&&input.support;
    if(dims.length!==3||dims.some(x=>!Number.isInteger(x)||x<2))throw new Error('Volumetric isosurface dimensions are invalid.');
    const n=dims[0]*dims[1]*dims[2];
    if(!data||data.length!==n||!support||support.length!==n)throw new Error('Volumetric isosurface arrays do not match the display grid.');
    if(affine.length!==4||affine.some(r=>r.length!==4||r.some(x=>!Number.isFinite(x))))throw new Error('Volumetric isosurface affine is invalid.');

    const range=arr(input.range).slice(0,2).map(Number);
    const cutoffs=thresholds(input.displayContract,range);
    const spec=qualitySpec(input.quality);
    const result=adaptiveBuild({dims,data,support,affine},cutoffs,spec);
    return {
      schema:'NMImagingVolumetricIsosurfaceResult',
      schemaVersion:2,
      contractVersion:'C18d3.2',
      quality:String(input.quality||'balanced'),
      stride:result.effectiveStride,
      requestedStride:result.requestedStride,
      effectiveStride:result.effectiveStride,
      budgetAdjusted:result.budgetAdjusted,
      complete:result.complete,
      maxTrianglesPerPolarity:result.maxTrianglesPerPolarity,
      thresholds:cutoffs,
      positive:result.positive,
      negative:result.negative
    };
  }

  root.NMImagingIsosurface={
    build,thresholds,
    _test:{polygonizeTetra,qualitySpec,buildPolarityAttempt,adaptiveBuild}
  };
})(typeof self!=='undefined'?self:(typeof window!=='undefined'?window:(typeof globalThis!=='undefined'?globalThis:this)));
