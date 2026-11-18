(function(){
  'use strict';

  const {clamp,toArray}=globalThis.NMResultsViewerPrimitives;
  const SCHEMA='nm-imaging-volume-rendering-contract';
  const VERSION=1;
  const STAGE='C18g5';
  const BOUNDARY_LEVEL=.5;
  const DEFAULT_SIGMA_FACTOR=1.2;
  const KERNEL_TRUNCATION_SIGMA=3;
  function finite(value,fallback){const number=Number(value);return Number.isFinite(number)?number:fallback;}
  function spacing3(value){const values=toArray(value).slice(0,3).map(v=>Math.max(Number.EPSILON,finite(v,1)));while(values.length<3)values.push(1);return values;}
  function dims3(value){const values=toArray(value).slice(0,3).map(v=>Math.max(1,Math.floor(finite(v,1))));while(values.length<3)values.push(1);return values;}
  function meanSpacing(spacingMm){const spacing=spacing3(spacingMm);return (spacing[0]+spacing[1]+spacing[2])/3;}
  function defaultSmoothingMm(spacingMm){return Number((DEFAULT_SIGMA_FACTOR*meanSpacing(spacingMm)).toPrecision(12));}
  function defaultCoverageGridSpacingMm(spacingMm,smoothingMm){const sigma=Math.max(0,finite(smoothingMm,defaultSmoothingMm(spacingMm)));return sigma===0?null:Number(Math.max(.25,Math.min(meanSpacing(spacingMm),sigma/2)).toPrecision(12));}
  function kernelRadiusVoxels(spacingMm,smoothingMm){const spacing=spacing3(spacingMm),sigma=Math.max(0,finite(smoothingMm,0));return sigma===0?[0,0,0]:spacing.map(step=>Math.max(1,Math.ceil(KERNEL_TRUNCATION_SIGMA*sigma/step)));}

  function normalize(value,spacingMm){
    const source=value&&typeof value==='object'?value:{},spacing=spacing3(spacingMm),requestedSigma=source.boundarySmoothingMm;
    const sigma=requestedSigma===null||requestedSigma===undefined||requestedSigma===''?defaultSmoothingMm(spacing):Math.max(0,finite(requestedSigma,NaN));
    if(!Number.isFinite(sigma))throw new Error('Boundary smoothing must be a finite non-negative value in millimetres.');
    const requestedGrid=source.coverageGridSpacingMm,grid=sigma===0?null:(requestedGrid===null||requestedGrid===undefined||requestedGrid===''?defaultCoverageGridSpacingMm(spacing,sigma):Math.max(Number.EPSILON,finite(requestedGrid,NaN)));
    if(sigma>0&&!Number.isFinite(grid))throw new Error('Coverage-grid spacing must be a finite positive value in millimetres.');
    const boundaryLevel=finite(source.coverageBoundaryLevel,BOUNDARY_LEVEL);
    if(Math.abs(boundaryLevel-BOUNDARY_LEVEL)>1e-12)throw new Error('The coverage boundary level is fixed at 0.5.');
    return {
      schema:SCHEMA,
      version:VERSION,
      stage:STAGE,
      activationStatus:'active',
      nativeSpacingMm:spacing,
      decisionField:{grid:'native_feature_grid',sampling:'nearest',support:'native_authoritative',thresholds:'exact_display_thresholds',signChannels:['positive','negative']},
      geometryField:{representation:sigma===0?'native_voxel_boundary':'dual_gaussian_coverage',boundarySmoothingMm:sigma,coverageBoundaryLevel:BOUNDARY_LEVEL,coverageGridSpacingMm:grid,kernelTruncationSigma:KERNEL_TRUNCATION_SIGMA,kernelRadiusVoxels:kernelRadiusVoxels(spacing,sigma),positiveNegativeCombination:'independent_channels_no_subtraction',presentationCoverageMayExtendBeyondNativeVoxel:sigma>0},
      valueField:{grid:'native_feature_grid',sampling:'nearest',values:'unmodified'},
      composition:{target:'single_front_to_back_anatomy_feature_loop',active:true},
      auditMode:{boundarySmoothingMm:0,representation:'native_voxel_boundary'},
      provenanceRequired:['contractSchema','contractVersion','activationStatus','boundarySmoothingMm','coverageBoundaryLevel','coverageGridSpacingMm','positiveNegativeCombination','nativeValueSampling']
    };
  }

  function validate(value,spacingMm){
    const errors=[];let normalized=null;
    try{normalized=normalize(value,spacingMm);}catch(error){errors.push(error&&error.message||String(error));return {ok:false,errors,contract:null};}
    if(normalized.decisionField.sampling!=='nearest')errors.push('Native decisions must use nearest-neighbour sampling.');
    if(normalized.valueField.sampling!=='nearest'||normalized.valueField.values!=='unmodified')errors.push('Reported feature values must remain native and unmodified.');
    if(normalized.geometryField.positiveNegativeCombination!=='independent_channels_no_subtraction')errors.push('Positive and negative coverage must remain independent.');
    if(normalized.geometryField.boundarySmoothingMm===0&&normalized.geometryField.representation!=='native_voxel_boundary')errors.push('Zero smoothing must invoke the exact native voxel-boundary audit representation.');
    if(normalized.geometryField.boundarySmoothingMm>0&&normalized.geometryField.representation!=='dual_gaussian_coverage')errors.push('Positive smoothing must use dual coverage fields.');
    return {ok:errors.length===0,errors,contract:normalized};
  }

  function provenance(options){
    const opts=options&&typeof options==='object'?options:{},contract=normalize(opts.contract,opts.nativeSpacingMm),active=opts.activeImplementation&&typeof opts.activeImplementation==='object'?opts.activeImplementation:{},prepared=opts.preparedCoverage&&typeof opts.preparedCoverage==='object'?opts.preparedCoverage:{};
    const geometryField=Object.assign({},contract.geometryField);
    const valueField=Object.assign({},contract.valueField);
    if(Number.isFinite(Number(prepared.boundarySmoothingMm)))geometryField.boundarySmoothingMm=Number(prepared.boundarySmoothingMm);
    if(Number.isFinite(Number(prepared.coverageBoundaryLevel)))geometryField.coverageBoundaryLevel=Number(prepared.coverageBoundaryLevel);
    if(Number.isFinite(Number(prepared.coverageGridSpacingMm)))geometryField.coverageGridSpacingMm=Number(prepared.coverageGridSpacingMm);
    if(prepared.positiveNegativeCombination)geometryField.positiveNegativeCombination=String(prepared.positiveNegativeCombination);
    if(prepared.nativeValueSampling)valueField.sampling=String(prepared.nativeValueSampling);
    return {
      schema:'nm-imaging-volume-rendering-provenance',
      version:1,
      designContract:{schema:contract.schema,version:contract.version,stage:contract.stage,activationStatus:contract.activationStatus},
      activeImplementation:{stage:String(active.stage||'C18g5'),geometry:String(active.geometry||'webgl2_level_crossing'),contractCompliant:active.contractCompliant===true,structuralTransfer:String(active.structuralTransfer||'scalar_times_filtered_support_level_crossing'),structuralDepth:String(active.structuralDepth||'bisection_refined_first_crossing'),anatomyFeatureComposition:String(active.anatomyFeatureComposition||'single_front_to_back_shared_ray')},
      decisionField:contract.decisionField,
      geometryField,
      valueField,
      composition:contract.composition
    };
  }

  function gaussianKernel(spacingMm,smoothingMm){
    const spacing=Math.max(Number.EPSILON,finite(spacingMm,1)),sigma=Math.max(0,finite(smoothingMm,0));
    if(sigma===0)return new Float64Array([1]);
    const radius=Math.max(1,Math.ceil(KERNEL_TRUNCATION_SIGMA*sigma/spacing)),kernel=new Float64Array(radius*2+1);let total=0;
    for(let offset=-radius;offset<=radius;offset++){const distance=offset*spacing,weight=Math.exp(-.5*(distance/sigma)*(distance/sigma));kernel[offset+radius]=weight;total+=weight;}
    for(let i=0;i<kernel.length;i++)kernel[i]/=total;
    return kernel;
  }

  function convolveAxis(input,dims,kernel,axis){
    const output=new Float32Array(input.length),radius=(kernel.length-1)>>1,dx=dims[0],dy=dims[1],dz=dims[2];
    for(let z=0;z<dz;z++)for(let y=0;y<dy;y++)for(let x=0;x<dx;x++){
      let sum=0;
      for(let k=-radius;k<=radius;k++){
        const xx=axis===0?x+k:x,yy=axis===1?y+k:y,zz=axis===2?z+k:z;
        if(xx<0||xx>=dx||yy<0||yy>=dy||zz<0||zz>=dz)continue;
        sum+=input[xx+dx*(yy+dy*zz)]*kernel[k+radius];
      }
      output[x+dx*(y+dy*z)]=sum;
    }
    return output;
  }

  function smoothIndicator(indicator,dims,spacingMm,smoothingMm){
    if(smoothingMm===0)return new Float32Array(indicator);
    const spacing=spacing3(spacingMm),kernels=spacing.map(step=>gaussianKernel(step,smoothingMm));let output=new Float32Array(indicator);
    for(let axis=0;axis<3;axis++)output=convolveAxis(output,dims,kernels[axis],axis);
    return output;
  }

  function buildReferenceCoverage(classField,dimsValue,spacingMm,smoothingMm){
    const dims=dims3(dimsValue),n=dims[0]*dims[1]*dims[2],classes=toArray(classField);if(classes.length!==n)throw new Error(`Native class field length ${classes.length} does not match ${n} voxels.`);
    const sigma=Math.max(0,finite(smoothingMm,0)),positive=new Float32Array(n),negative=new Float32Array(n),nativeClass=new Int8Array(n);
    for(let i=0;i<n;i++){const klass=classes[i]>0?1:(classes[i]<0?-1:0);nativeClass[i]=klass;if(klass>0)positive[i]=1;else if(klass<0)negative[i]=1;}
    return {dims,spacingMm:spacing3(spacingMm),boundarySmoothingMm:sigma,coverageBoundaryLevel:BOUNDARY_LEVEL,nativeClass,positive:smoothIndicator(positive,dims,spacingMm,sigma),negative:smoothIndicator(negative,dims,spacingMm,sigma)};
  }

  function independentCoverageClass(positive,negative,boundaryLevel){const level=finite(boundaryLevel,BOUNDARY_LEVEL);return {positive:finite(positive,0)>=level,negative:finite(negative,0)>=level};}
  function nativeValueAt(values,dimsValue,cell){const dims=dims3(dimsValue),c=toArray(cell).slice(0,3).map(v=>Math.floor(finite(v,-1)));if(c.length<3||c[0]<0||c[0]>=dims[0]||c[1]<0||c[1]>=dims[1]||c[2]<0||c[2]>=dims[2])return NaN;const value=Number(values[c[0]+dims[0]*(c[1]+dims[1]*c[2])]);return Number.isFinite(value)?value:NaN;}

  function cameraInvarianceAcceptance(samples,limits){
    const values=toArray(samples),opts=limits&&typeof limits==='object'?limits:{},maxAreaStep=Math.max(0,finite(opts.maxAreaFractionStep,.03)),maxCentroidStep=Math.max(0,finite(opts.maxCentroidPixelStep,2));let worstArea=0,worstCentroid=0;
    for(let i=1;i<values.length;i++){const previous=values[i-1]||{},current=values[i]||{},den=Math.max(1,Math.abs(finite(previous.area,0))),area=Math.abs(finite(current.area,0)-finite(previous.area,0))/den,centroid=Math.hypot(finite(current.centroidX,0)-finite(previous.centroidX,0),finite(current.centroidY,0)-finite(previous.centroidY,0));worstArea=Math.max(worstArea,area);worstCentroid=Math.max(worstCentroid,centroid);}
    return {ok:values.length>=2&&worstArea<=maxAreaStep&&worstCentroid<=maxCentroidStep,worstAreaFractionStep:worstArea,worstCentroidPixelStep:worstCentroid,limits:{maxAreaFractionStep:maxAreaStep,maxCentroidPixelStep:maxCentroidStep}};
  }

  function nativeValueInvarianceAcceptance(samples,tolerance){const tol=Math.max(0,finite(tolerance,0)),mismatches=toArray(samples).filter(sample=>Math.abs(finite(sample&&sample.reported,NaN)-finite(sample&&sample.native,NaN))>tol||!Number.isFinite(Number(sample&&sample.reported))||!Number.isFinite(Number(sample&&sample.native)));return {ok:mismatches.length===0,mismatchCount:mismatches.length,tolerance:tol};}

  function surfaceCoherenceAcceptance(sample,limits){
    const value=sample&&typeof sample==='object'?sample:{},opts=limits&&typeof limits==='object'?limits:{};
    const maxAxisAlignedNormalFraction=clamp(finite(opts.maxAxisAlignedNormalFraction,.15),0,1);
    const maxDepthRoughnessRatio=Math.max(0,finite(opts.maxDepthRoughnessRatio,.85));
    const axisAlignedNormalFraction=finite(value.axisAlignedNormalFraction,Infinity);
    const depthSecondDifferenceP90Mm=finite(value.depthSecondDifferenceP90Mm,Infinity);
    const referenceDepthSecondDifferenceP90Mm=finite(value.referenceDepthSecondDifferenceP90Mm,NaN);
    const depthRoughnessRatio=Number.isFinite(referenceDepthSecondDifferenceP90Mm)&&referenceDepthSecondDifferenceP90Mm>0?depthSecondDifferenceP90Mm/referenceDepthSecondDifferenceP90Mm:Infinity;
    return {ok:axisAlignedNormalFraction<=maxAxisAlignedNormalFraction&&depthRoughnessRatio<=maxDepthRoughnessRatio,axisAlignedNormalFraction,depthSecondDifferenceP90Mm,referenceDepthSecondDifferenceP90Mm,depthRoughnessRatio,limits:{maxAxisAlignedNormalFraction,maxDepthRoughnessRatio}};
  }

  function auditConvergenceAcceptance(sample,limits){
    const value=sample&&typeof sample==='object'?sample:{},opts=limits&&typeof limits==='object'?limits:{};
    const minSilhouetteIoU=clamp(finite(opts.minSilhouetteIoU,.98),0,1);
    const maxMedianDepthDifferenceMm=Math.max(0,finite(opts.maxMedianDepthDifferenceMm,.15));
    const silhouetteIoU=finite(value.silhouetteIoU,-Infinity);
    const medianDepthDifferenceMm=finite(value.medianDepthDifferenceMm,Infinity);
    return {ok:silhouetteIoU>=minSilhouetteIoU&&medianDepthDifferenceMm<=maxMedianDepthDifferenceMm,silhouetteIoU,medianDepthDifferenceMm,limits:{minSilhouetteIoU,maxMedianDepthDifferenceMm}};
  }

  window.NMImagingVolumeRenderingContract={SCHEMA,VERSION,STAGE,BOUNDARY_LEVEL,defaultSmoothingMm,defaultCoverageGridSpacingMm,kernelRadiusVoxels,normalize,validate,provenance,buildReferenceCoverage,independentCoverageClass,nativeValueAt,cameraInvarianceAcceptance,nativeValueInvarianceAcceptance,surfaceCoherenceAcceptance,auditConvergenceAcceptance,_test:{spacing3,dims3,meanSpacing,gaussianKernel,convolveAxis,smoothIndicator}};
})();
