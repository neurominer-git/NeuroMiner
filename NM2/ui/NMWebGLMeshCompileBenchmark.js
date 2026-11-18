(function(){
  'use strict';

  /*
   * NM-RV-MESH-COMPILE-BENCHMARK-V1
   * Isolated target-browser benchmark for Stage 3P2A. It compiles declared
   * source shapes on a private canvas and never installs a Results Viewer
   * object, mutates viewer state, or retains WebGL resources after each run.
   * Successful link-only variants avoid per-shader status synchronization;
   * shader status and logs are queried only after link failure.
   */
  const CONTRACT='NM-RV-MESH-COMPILE-BENCHMARK-V1';
  function nowMs(){return typeof performance!=='undefined'&&performance&&typeof performance.now==='function'?performance.now():Date.now();}
  function lines(text){return (String(text||'').match(/\n/g)||[]).length+1;}
  function compile(gl,vertexSource,fragmentSource,mode){
    const started=nowMs(),vertex=gl.createShader(gl.VERTEX_SHADER),fragment=gl.createShader(gl.FRAGMENT_SHADER),timings={vertexSubmitMs:0,vertexStatusMs:0,fragmentSubmitMs:0,fragmentStatusMs:0,linkSubmitMs:0,linkStatusMs:0};
    let phase=nowMs();gl.shaderSource(vertex,vertexSource);gl.compileShader(vertex);timings.vertexSubmitMs=nowMs()-phase;
    if(mode==='immediate_status'){phase=nowMs();if(!gl.getShaderParameter(vertex,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(vertex)||'vertex compile failed');timings.vertexStatusMs=nowMs()-phase;}
    phase=nowMs();gl.shaderSource(fragment,fragmentSource);gl.compileShader(fragment);timings.fragmentSubmitMs=nowMs()-phase;
    if(mode==='immediate_status'){phase=nowMs();if(!gl.getShaderParameter(fragment,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(fragment)||'fragment compile failed');timings.fragmentStatusMs=nowMs()-phase;}
    const program=gl.createProgram();gl.attachShader(program,vertex);gl.attachShader(program,fragment);phase=nowMs();gl.linkProgram(program);timings.linkSubmitMs=nowMs()-phase;phase=nowMs();const linked=!!gl.getProgramParameter(program,gl.LINK_STATUS);timings.linkStatusMs=nowMs()-phase;
    if(!linked){const vertexOk=gl.getShaderParameter(vertex,gl.COMPILE_STATUS),fragmentOk=gl.getShaderParameter(fragment,gl.COMPILE_STATUS),message=[gl.getProgramInfoLog(program)||'program link failed',vertexOk?'':gl.getShaderInfoLog(vertex),fragmentOk?'':gl.getShaderInfoLog(fragment)].filter(Boolean).join('\n');gl.deleteShader(vertex);gl.deleteShader(fragment);gl.deleteProgram(program);throw new Error(message);}
    gl.deleteShader(vertex);gl.deleteShader(fragment);return {program,totalMs:nowMs()-started,timings};
  }
  function variants(){
    const programs=window.NMWebGLMeshPrograms;if(!programs)throw new Error('NMWebGLMeshPrograms is unavailable.');
    const specs=[
      {id:'base_mesh',spec:{role:programs.ROLE.BASE,key:'base_mesh'}},
      {id:'surface_projection_production_steps_4_tflse',spec:{role:programs.ROLE.SURFACE_PROJECTION,key:'surface_projection_production|steps=4|alpha=1',projectionSteps:4,projectionAlphaMode:1,projectionDiagnosticMode:0}},
      {id:'surface_projection_diagnostic_depth',spec:{role:programs.ROLE.PROJECTION_DIAGNOSTIC,key:'surface_projection_diagnostic|steps=4|alpha=1|diagnostic=1',projectionSteps:4,projectionAlphaMode:1,projectionDiagnosticMode:1}},
      {id:'volume_locator',spec:{role:programs.ROLE.LOCATOR,key:'volume_locator|mode=8',colorMode:8}},
      {id:'atlas_boundary',spec:{role:programs.ROLE.ATLAS_BOUNDARY,key:'atlas_boundary|steps=8|projected=1',atlasBoundaryProjectionSteps:8,atlasBoundaryProjectionMode:1}}
    ];
    return specs.map(item=>{const source=programs.sourcesForSpec(item.spec);return {id:item.id,mode:'link_only',vertex:source.vertex,fragment:source.fragment};});
  }
  function summarize(values){const sorted=values.slice().sort((a,b)=>a-b),mean=sorted.reduce((a,b)=>a+b,0)/Math.max(1,sorted.length),median=sorted[Math.floor(sorted.length/2)]||0;return {count:values.length,meanMs:mean,medianMs:median,minMs:sorted[0]||0,maxMs:sorted[sorted.length-1]||0};}
  async function run(options){
    const opts=options||{},canvas=opts.canvas||document.createElement('canvas');canvas.width=canvas.width||16;canvas.height=canvas.height||16;const gl=canvas.getContext('webgl2',{antialias:false,alpha:true,preserveDrawingBuffer:false})||canvas.getContext('webgl',{antialias:false,alpha:true,preserveDrawingBuffer:false});if(!gl)throw new Error('WebGL is unavailable for mesh compile benchmarking.');const iterations=Math.max(1,Math.min(5,Math.round(Number(opts.iterations)||1))),results=[];
    for(const variant of variants()){
      const measurements=[];for(let i=0;i<iterations;i++){await new Promise(resolve=>setTimeout(resolve,0));const item=compile(gl,variant.vertex,variant.fragment,variant.mode);measurements.push(item.totalMs);gl.deleteProgram(item.program);}
      results.push({id:variant.id,statusMode:variant.mode,sourceBytes:variant.vertex.length+variant.fragment.length,sourceLines:lines(variant.vertex)+lines(variant.fragment),measurementsMs:measurements,summary:summarize(measurements)});
    }
    return {ok:true,contract:CONTRACT,contextKind:gl instanceof WebGL2RenderingContext?'webgl2':'webgl1',version:String(gl.getParameter(gl.VERSION)||''),shadingLanguageVersion:String(gl.getParameter(gl.SHADING_LANGUAGE_VERSION)||''),renderer:(()=>{const debug=gl.getExtension('WEBGL_debug_renderer_info');return debug?String(gl.getParameter(debug.UNMASKED_RENDERER_WEBGL)||''):'';})(),iterations,results};
  }
  window.NMWebGLMeshCompileBenchmark={CONTRACT,run,variants,_test:{compile,lines,summarize}};
})();
