(function(root){
  'use strict';

  const {clamp,text,toArray}=globalThis.NMResultsViewerPrimitives;
  const CONTRACT_VERSION='NM-RESULTS-VIEWER-DISPLAY-SEMANTICS-V1';
  const REQUEST_VERSION='NM-RESULTS-VIEWER-DISPLAY-REQUEST-V1';
  const THRESHOLD_MODES=Object.freeze(['none','outside_interval','above_abs','above','below']);
  const THRESHOLD_MODE_CODES=Object.freeze({none:0,outside_interval:1,above_abs:2,below:3,above:4});
  const RANGE_MODES=Object.freeze(['robust_polarity_wise','full_data_range','symmetric_absolute','manual']);
  const POLARITIES=Object.freeze(['signed','positive','negative','magnitude']);
  const MAX_COLOR_STOPS=10;
  const MIN_COLOR_STOPS=2;
  const DEFAULT_COLORS=Object.freeze({negative:'#0000ff',midpoint:'#ffffff',positive:'#ff0000'});
  const STATISTICS_CACHE=new WeakMap();
  const DISPLAY_REQUESTS=new WeakMap();
  const DISPLAY_CONTRACTS=new WeakMap();
  const NO_SUPPORT={};
  function finite(value,fallback){
    if(value===null||value===undefined||value===''||typeof value==='boolean'||Array.isArray(value)||(typeof value==='object'&&value!==null))return fallback;
    const number=Number(value);
    return Number.isFinite(number)?number:fallback;
  }
  function fail(code,message){
    const error=new Error(message);
    error.code=code;
    throw error;
  }
  function requireFinite(value,code,label){
    if(typeof value!=='number'||!Number.isFinite(value))fail(code,`${label} must be a finite real number.`);
    return value;
  }
  function requireMode(value,allowed,code,label){
    if(typeof value!=='string'||!allowed.includes(value))fail(code,`${label} must be one of: ${allowed.join(', ')}.`);
    return value;
  }
  function isComplexRepresentation(value){
    return !!(value&&typeof value==='object'&&(
      Object.prototype.hasOwnProperty.call(value,'imag')||
      Object.prototype.hasOwnProperty.call(value,'imaginary')||
      Object.prototype.hasOwnProperty.call(value,'im')
    ));
  }
  function validateDisplayValue(value,label){
    if(typeof value==='number'){
      if(Number.isNaN(value))return {state:'missing',value:NaN};
      if(!Number.isFinite(value))fail('NMDisplaySemantics:NonFiniteValue',`${label} contains an infinite value.`);
      return {state:'finite',value};
    }
    if(isComplexRepresentation(value))fail('NMDisplaySemantics:ComplexValue',`${label} contains a complex value. The scientific backend must define a real-valued transform before display.`);
    fail('NMDisplaySemantics:InvalidValue',`${label} contains a non-numeric value.`);
  }
  function niceStep(target){
    const positive=Math.abs(finite(target,NaN));
    if(!(positive>0))return Number.EPSILON;
    const exponent=Math.floor(Math.log10(positive));
    const magnitude=Math.pow(10,exponent);
    const scaled=positive/magnitude;
    const epsilon=1e-12;
    const nice=scaled<=1+epsilon?1:(scaled<=2+epsilon?2:(scaled<=5+epsilon?5:10));
    return nice*magnitude;
  }
  function quantile(sorted,q){
    if(!sorted.length)return NaN;
    const x=clamp(requireFinite(q,'NMDisplaySemantics:InvalidQuantile','Quantile'),0,1)*(sorted.length-1);
    const lower=Math.floor(x),upper=Math.ceil(x),weight=x-lower;
    return sorted[lower]+(sorted[upper]-sorted[lower])*weight;
  }
  function lowerBound(values,target){
    let lower=0,upper=values.length;
    while(lower<upper){const middle=(lower+upper)>>1;if(values[middle]<target)lower=middle+1;else upper=middle;}
    return lower;
  }
  function upperBound(values,target){
    let lower=0,upper=values.length;
    while(lower<upper){const middle=(lower+upper)>>1;if(values[middle]<=target)lower=middle+1;else upper=middle;}
    return lower;
  }
  function quantileRange(range,q){
    if(!range||range.count<1)return NaN;
    const x=clamp(requireFinite(q,'NMDisplaySemantics:InvalidQuantile','Quantile'),0,1)*(range.count-1);
    const lower=Math.floor(x),upper=Math.ceil(x),weight=x-lower;
    const a=range.values[range.start+lower],b=range.values[range.start+upper];
    return a+(b-a)*weight;
  }
  function deepFreeze(value){
    if(!value||typeof value!=='object'||Object.isFrozen(value))return value;
    Object.keys(value).forEach(key=>deepFreeze(value[key]));
    return Object.freeze(value);
  }

  const CONTRACT_FACETS=Object.freeze(['threshold','shownRange','colorStops','opacity']);
  function contractRequirement(requirement){
    const input=requirement&&typeof requirement==='object'&&!Array.isArray(requirement)?requirement:{};
    const consumer=text(input.consumer).trim();
    if(!consumer)fail('NMDisplaySemantics:InvalidContractRequirement','Display-contract assertion requires a named consumer.');
    const facets=toArray(input.facets).map(value=>text(value).trim());
    if(!facets.length)fail('NMDisplaySemantics:InvalidContractRequirement',`${consumer} must declare at least one required display-contract facet.`);
    const seen=new Set();
    facets.forEach(facet=>{
      if(!CONTRACT_FACETS.includes(facet))fail('NMDisplaySemantics:InvalidContractRequirement',`${consumer} declared unsupported display-contract facet ${facet||'(empty)'}.`);
      if(seen.has(facet))fail('NMDisplaySemantics:InvalidContractRequirement',`${consumer} declared duplicate display-contract facet ${facet}.`);
      seen.add(facet);
    });
    return {consumer,facets,message:text(input.message).trim()};
  }
  function contractFacetFailure(requirement,facet,detail){
    const prefix=requirement.message||`${requirement.consumer} requires a canonical display contract.`;
    fail('NMDisplaySemantics:InvalidContract',`${prefix} Invalid or missing facet ${facet}: ${detail}`);
  }
  function assertThresholdFacet(contract,requirement){
    const threshold=contract.threshold;
    if(!threshold||typeof threshold!=='object'||Array.isArray(threshold))contractFacetFailure(requirement,'threshold','expected one canonical threshold object.');
    const mode=text(threshold.mode).toLowerCase();
    if(!THRESHOLD_MODES.includes(mode))contractFacetFailure(requirement,'threshold',`unknown mode ${mode||'(empty)'}.`);
    if(mode==='outside_interval'){
      if(typeof threshold.lower!=='number'||!Number.isFinite(threshold.lower)||typeof threshold.upper!=='number'||!Number.isFinite(threshold.upper)||!(threshold.lower<threshold.upper))contractFacetFailure(requirement,'threshold','outside-interval bounds must be finite and strictly ordered.');
    }else if(['above_abs','above','below'].includes(mode)){
      if(typeof threshold.value!=='number'||!Number.isFinite(threshold.value))contractFacetFailure(requirement,'threshold','single-threshold value must be finite.');
      if(mode==='above_abs'&&threshold.value<0)contractFacetFailure(requirement,'threshold','absolute threshold must be non-negative.');
    }
  }
  function assertShownRangeFacet(contract,requirement){
    const range=contract.shownRange;
    if(!range||typeof range!=='object'||Array.isArray(range))contractFacetFailure(requirement,'shownRange','expected one canonical shown-range object.');
    if(!RANGE_MODES.includes(text(range.mode)))contractFacetFailure(requirement,'shownRange',`unknown mode ${text(range.mode)||'(empty)'}.`);
    if(typeof range.lower!=='number'||!Number.isFinite(range.lower)||typeof range.upper!=='number'||!Number.isFinite(range.upper)||range.upper<range.lower)contractFacetFailure(requirement,'shownRange','bounds must be finite and ordered.');
  }
  function assertColorStopsFacet(contract,requirement){
    const stops=contract.colorStops;
    if(!Array.isArray(stops)||stops.length<MIN_COLOR_STOPS||stops.length>MAX_COLOR_STOPS)contractFacetFailure(requirement,'colorStops',`expected ${MIN_COLOR_STOPS}-${MAX_COLOR_STOPS} canonical colour stops.`);
    let previous=-Infinity;
    stops.forEach((stop,index)=>{
      if(!stop||typeof stop!=='object'||Array.isArray(stop))contractFacetFailure(requirement,'colorStops',`stop ${index+1} is not an object.`);
      if(typeof stop.position!=='number'||!Number.isFinite(stop.position)||stop.position<0||stop.position>1||stop.position<previous)contractFacetFailure(requirement,'colorStops',`stop ${index+1} has an invalid or unordered position.`);
      if(typeof stop.color!=='string'||!/^#[0-9a-f]{6}$/i.test(stop.color))contractFacetFailure(requirement,'colorStops',`stop ${index+1} has an invalid colour.`);
      previous=stop.position;
    });
  }
  function assertOpacityFacet(contract,requirement){
    if(typeof contract.opacity!=='number'||!Number.isFinite(contract.opacity)||contract.opacity<0||contract.opacity>1)contractFacetFailure(requirement,'opacity','expected a finite value in [0, 1].');
  }
  function assertDisplayContract(contract,requirement){
    const required=contractRequirement(requirement);
    if(!contract||typeof contract!=='object'||Array.isArray(contract))contractFacetFailure(required,'contractVersion','display contract is absent or not an object.');
    if(contract.contractVersion!==CONTRACT_VERSION)contractFacetFailure(required,'contractVersion',`expected ${CONTRACT_VERSION}, received ${text(contract.contractVersion)||'(missing)'}.`);
    required.facets.forEach(facet=>{
      if(facet==='threshold')assertThresholdFacet(contract,required);
      else if(facet==='shownRange')assertShownRangeFacet(contract,required);
      else if(facet==='colorStops')assertColorStopsFacet(contract,required);
      else if(facet==='opacity')assertOpacityFacet(contract,required);
    });
    return contract;
  }

  function declaredRange(overlay){
    const raw=overlay&&overlay.meta&&overlay.meta.valueRange;
    if(raw==null)return null;
    const range=toArray(raw);
    if(range.length!==2)fail('NMDisplaySemantics:InvalidDeclaredRange','Declared valueRange must contain exactly two values.');
    const lower=requireFinite(range[0],'NMDisplaySemantics:InvalidDeclaredRange','Declared range lower bound');
    const upper=requireFinite(range[1],'NMDisplaySemantics:InvalidDeclaredRange','Declared range upper bound');
    if(upper<lower)fail('NMDisplaySemantics:ReversedDeclaredRange','Declared valueRange is reversed.');
    return [lower,upper];
  }
  function orderedRange(overlay){
    const range=declaredRange(overlay);
    if(range)return range;
    const stats=baseStatistics(overlay,null);
    return [stats.exactMin,stats.exactMax];
  }
  function canonicalPolarity(overlay,statistics){
    const raw=overlay&&overlay.meta&&(overlay.meta.valuePolarity||overlay.meta.polarity);
    if(raw!=null&&raw!=='')return requireMode(raw,POLARITIES,'NMDisplaySemantics:InvalidPolarity','Value polarity');
    if(statistics.exactMin<0&&statistics.exactMax>0)return 'signed';
    if(statistics.exactMax<=0&&statistics.exactMin<0)return 'negative';
    return 'positive';
  }
  function baseStatistics(overlay,support){
    if(!overlay||typeof overlay!=='object')fail('NMDisplaySemantics:MissingOverlay','Display semantics require an overlay object.');
    let bySupport=STATISTICS_CACHE.get(overlay);
    if(!bySupport){bySupport=new WeakMap();STATISTICS_CACHE.set(overlay,bySupport);}
    // statisticsData is an explicit scientific-value source (canonical ROI vectors); overlay.data remains the rendering field.
    const statisticalData=overlay.statisticsData,hasStatisticalData=statisticalData!=null;
    const data=hasStatisticalData?statisticalData:overlay.data,statisticalSupport=hasStatisticalData?null:support;
    const key=statisticalSupport&&typeof statisticalSupport==='object'?statisticalSupport:NO_SUPPORT;
    if(bySupport.has(key))return bySupport.get(key);
    if(!(Array.isArray(data)||ArrayBuffer.isView(data)))fail('NMDisplaySemantics:MissingValues','Overlay data must be an array or typed array.');
    if(statisticalSupport!=null&&(!(Array.isArray(statisticalSupport)||ArrayBuffer.isView(statisticalSupport))||statisticalSupport.length!==data.length))fail('NMDisplaySemantics:InvalidSupport','Support must be absent or match overlay data length.');
    const negative=[],positive=[],magnitude=[];
    let exactMin=Infinity,exactMax=-Infinity,count=0,missingCount=0,zeroCount=0;
    for(let index=0;index<data.length;index++){
      if(statisticalSupport&&statisticalSupport[index]===0)continue;
      const validated=validateDisplayValue(data[index],`Overlay value ${index+1}`);
      if(validated.state==='missing'){missingCount++;continue;}
      const value=validated.value;
      count++;
      exactMin=Math.min(exactMin,value);
      exactMax=Math.max(exactMax,value);
      if(value<0){negative.push(value);magnitude.push(Math.abs(value));}
      else if(value>0){positive.push(value);magnitude.push(value);}
      else zeroCount++;
    }
    if(count===0)fail('NMDisplaySemantics:NoFiniteValues','Overlay contains no finite real display values.');
    negative.sort((a,b)=>a-b);positive.sort((a,b)=>a-b);magnitude.sort((a,b)=>a-b);
    const result={count,missingCount,exactMin,exactMax,negative,positive,magnitude,zeroCount,supportIdentity:key};
    bySupport.set(key,result);
    return result;
  }
  function effectivePolarity(overlay,support){
    const statistics=baseStatistics(overlay,support),declared=declaredRange(overlay),domain=declared||[statistics.exactMin,statistics.exactMax];
    const theoretical=canonicalPolarity(overlay,statistics);
    const scale=Math.max(Math.abs(domain[0]),Math.abs(domain[1]),1);
    const tolerance=scale*1e-10;
    const hasNegative=domain[0]<-tolerance;
    const hasPositive=domain[1]>tolerance;
    let kind='none';
    if(hasNegative&&hasPositive)kind='signed';
    else if(hasNegative)kind='negative';
    else if(hasPositive)kind=theoretical==='magnitude'?'magnitude':'positive';
    else if(theoretical==='magnitude')kind='magnitude';
    return {kind,min:domain[0],max:domain[1],hasNegative,hasPositive,hasZero:statistics.zeroCount>0||domain[0]===0||domain[1]===0,theoretical,tolerance};
  }
  function thresholdDefaults(overlay,support,polarity){
    const resolvedPolarity=polarity||effectivePolarity(overlay,support);
    const statistics=baseStatistics(overlay,support);
    const range=declaredRange(overlay)||[statistics.exactMin,statistics.exactMax];
    const span=range[1]-range[0];
    const negative=quantile(statistics.negative,.10);
    const positive=quantile(statistics.positive,.90);
    const magnitude=quantile(statistics.magnitude,.90);
    return {
      negative:Number.isFinite(negative)?negative:Math.min(-Number.EPSILON,range[0]+span*.10),
      positive:Number.isFinite(positive)?positive:Math.max(Number.EPSILON,range[0]+span*.90),
      magnitude:Number.isFinite(magnitude)?magnitude:Math.max(Number.EPSILON,Math.max(Math.abs(range[0]),Math.abs(range[1]))*.90),
      polarity:resolvedPolarity.kind
    };
  }

  function absent(value){return value===undefined||value===null||value==='';}
  function cloneStops(stops){return toArray(stops).map(stop=>({position:stop.position,color:stop.color}));}
  function displayRequestFromState(display,overlay,support,options){
    const state=display&&typeof display==='object'?display:{};
    const settings=options&&typeof options==='object'?options:{};
    const defaults=overlay&&overlay.meta&&overlay.meta.displayDefaults||{};
    const polarity=effectivePolarity(overlay,support);
    let computedThresholdDefaults=null;
    const resolvedThresholdDefaults=()=>{if(!computedThresholdDefaults)computedThresholdDefaults=thresholdDefaults(overlay,support,polarity);return computedThresholdDefaults;};
    const explicitMode=!absent(state.thresholdMode);
    const mode=requireMode(explicitMode?state.thresholdMode:defaults.thresholdMode,THRESHOLD_MODES,'NMDisplaySemantics:InvalidThresholdMode','Threshold mode');
    let threshold={mode};
    const thresholdField=(name,fallback,code,label)=>{
      const explicit=state[name];
      if(!absent(explicit))return requireFinite(explicit,code,label);
      if(explicitMode)fail(code,`${label} must be a finite real number.`);
      const inherited=defaults[name];
      if(typeof inherited==='number'&&Number.isFinite(inherited))return inherited;
      return requireFinite(fallback(),code,label);
    };
    if(mode==='outside_interval'){
      const lower=thresholdField('thresholdLow',()=>resolvedThresholdDefaults().negative,'NMDisplaySemantics:MissingThresholdBound','Threshold lower bound');
      const upper=thresholdField('thresholdHigh',()=>resolvedThresholdDefaults().positive,'NMDisplaySemantics:MissingThresholdBound','Threshold upper bound');
      if(!(lower<upper))fail('NMDisplaySemantics:InvalidThresholdInterval','Outside-interval thresholds require lower < upper.');
      threshold={mode,lower,upper};
    }else if(mode==='above_abs'){
      const value=thresholdField('thresholdValue',()=>resolvedThresholdDefaults().magnitude,'NMDisplaySemantics:MissingThresholdValue','Threshold value');
      if(value<0)fail('NMDisplaySemantics:NegativeAbsoluteThreshold','Absolute threshold must be nonnegative.');
      threshold={mode,value};
    }else if(mode==='above'){
      threshold={mode,value:thresholdField('thresholdValue',()=>resolvedThresholdDefaults().positive,'NMDisplaySemantics:MissingThresholdValue','Threshold value')};
    }else if(mode==='below'){
      threshold={mode,value:thresholdField('thresholdValue',()=>resolvedThresholdDefaults().negative,'NMDisplaySemantics:MissingThresholdValue','Threshold value')};
    }
    const inheritedRangeMode=absent(defaults.displayRangeMode)?'robust_polarity_wise':defaults.displayRangeMode;
    const rangeMode=normalizeRangeMode(absent(state.displayRangeMode)?inheritedRangeMode:state.displayRangeMode);
    const range={mode:rangeMode};
    if(rangeMode==='manual'){
      range.lower=requireFinite(state.manualDisplayLower,'NMDisplaySemantics:InvalidManualRange','Manual display lower bound');
      range.upper=requireFinite(state.manualDisplayUpper,'NMDisplaySemantics:InvalidManualRange','Manual display upper bound');
      if(!(range.lower<range.upper))fail('NMDisplaySemantics:InvalidManualRange','Manual display range requires lower < upper.');
    }
    const inheritedOpacity=defaults.opacity;
    const opacitySource=absent(state.opacity)?(Number.isFinite(Number(settings.defaultOpacity))?Number(settings.defaultOpacity):inheritedOpacity):state.opacity;
    const opacity=requireFinite(opacitySource,'NMDisplaySemantics:InvalidOpacity','Opacity');
    if(opacity<0||opacity>1)fail('NMDisplaySemantics:InvalidOpacity','Opacity must lie in [0,1].');
    const colors={
      negative:normalizeHexColor(absent(state.negativeColor)?inheritedColor(defaults,'negativeColor','negativeColorRgb',DEFAULT_COLORS.negative,'Negative colour'):state.negativeColor,'Negative colour'),
      midpoint:normalizeHexColor(absent(state.midpointColor)?inheritedColor(defaults,'midpointColor','midpointColorRgb',DEFAULT_COLORS.midpoint,'Midpoint colour'):state.midpointColor,'Midpoint colour'),
      positive:normalizeHexColor(absent(state.positiveColor)?inheritedColor(defaults,'positiveColor','positiveColorRgb',DEFAULT_COLORS.positive,'Positive colour'):state.positiveColor,'Positive colour')
    };
    const colorStops=absent(state.colorStops)||toArray(state.colorStops).length===0?null:deepFreeze(cloneStops(normalizeColorStops(state.colorStops,polarity.kind,colors)));
    return deepFreeze({requestVersion:REQUEST_VERSION,threshold,range,opacity,colors,colorStops});
  }
  function requireDisplayRequest(request){
    if(!request||typeof request!=='object'||request.requestVersion!==REQUEST_VERSION)fail('NMDisplaySemantics:InvalidDisplayRequest','Display contract resolution requires a canonical display request.');
    return request;
  }

  function thresholdIncludes(value,threshold){
    switch(threshold.mode){
      case 'none':return true;
      case 'outside_interval':return value<=threshold.lower||value>=threshold.upper;
      case 'above_abs':return Math.abs(value)>=threshold.value;
      case 'above':return value>=threshold.value;
      case 'below':return value<=threshold.value;
      default:fail('NMDisplaySemantics:InvalidThresholdMode','Resolved threshold mode is invalid.');
    }
  }
  function activeRanges(statistics,threshold){
    if(!threshold||typeof threshold!=='object')fail('NMDisplaySemantics:InvalidThreshold','Resolved threshold is required.');
    const mode=requireMode(threshold.mode,THRESHOLD_MODES,'NMDisplaySemantics:InvalidThresholdMode','Threshold mode');
    const negative=statistics.negative,positive=statistics.positive;
    let negativeStart=0,negativeEnd=negative.length,positiveStart=0,positiveEnd=positive.length;
    if(mode==='outside_interval'){
      const lower=requireFinite(threshold.lower,'NMDisplaySemantics:MissingThresholdBound','Negative threshold');
      const upper=requireFinite(threshold.upper,'NMDisplaySemantics:MissingThresholdBound','Positive threshold');
      if(!(lower<upper))fail('NMDisplaySemantics:InvalidThresholdInterval','Outside-interval thresholds require lower < upper.');
      negativeEnd=upperBound(negative,lower);positiveStart=lowerBound(positive,upper);
    }else if(mode==='above_abs'){
      const value=requireFinite(threshold.value,'NMDisplaySemantics:MissingThresholdValue','Absolute threshold');
      if(value<0)fail('NMDisplaySemantics:NegativeAbsoluteThreshold','Absolute threshold must be nonnegative.');
      negativeEnd=upperBound(negative,-value);positiveStart=lowerBound(positive,value);
    }else if(mode==='below'){
      negativeEnd=upperBound(negative,requireFinite(threshold.value,'NMDisplaySemantics:MissingThresholdValue','Threshold value'));positiveStart=positiveEnd;
    }else if(mode==='above'){
      positiveStart=lowerBound(positive,requireFinite(threshold.value,'NMDisplaySemantics:MissingThresholdValue','Threshold value'));negativeEnd=negativeStart;
    }
    return {
      negative:{values:negative,start:negativeStart,end:negativeEnd,count:Math.max(0,negativeEnd-negativeStart)},
      positive:{values:positive,start:positiveStart,end:positiveEnd,count:Math.max(0,positiveEnd-positiveStart)}
    };
  }
  function countBelow(range,value){return Math.max(0,Math.min(range.end,lowerBound(range.values,value))-range.start);}
  function countAbove(range,value){return Math.max(0,range.end-Math.max(range.start,upperBound(range.values,value)));}
  function endpointOr(value,fallback){return Number.isFinite(value)?value:fallback;}
  function normalizeRangeMode(value){return requireMode(value,RANGE_MODES,'NMDisplaySemantics:InvalidRangeMode','Display range mode');}
  function thresholdModeCode(mode){const canonical=text(mode).toLowerCase();if(!Object.prototype.hasOwnProperty.call(THRESHOLD_MODE_CODES,canonical))fail('NMDisplaySemantics:InvalidThresholdMode',`Unknown threshold mode: ${canonical}`);return THRESHOLD_MODE_CODES[canonical];}

  function displayRangeModel(overlay,request,support){
    const resolvedRequest=requireDisplayRequest(request);
    const statistics=baseStatistics(overlay,support);
    const polarity=effectivePolarity(overlay,support);
    const active=activeRanges(statistics,resolvedRequest.threshold);
    const activeCount=active.negative.count+active.positive.count+(resolvedRequest.threshold.mode==='none'?statistics.zeroCount:0);
    const declared=declaredRange(overlay),exactMin=declared?declared[0]:statistics.exactMin,exactMax=declared?declared[1]:statistics.exactMax;
    const mode=normalizeRangeMode(resolvedRequest.range.mode);
    let lower=exactMin,upper=exactMax;
    if(mode==='robust_polarity_wise'){
      const robustNegative=quantileRange(active.negative,.02);
      const robustPositive=quantileRange(active.positive,.98);
      const nearestNegative=active.negative.count?active.negative.values[active.negative.end-1]:NaN;
      const nearestPositive=active.positive.count?active.positive.values[active.positive.start]:NaN;
      if(active.negative.count&&active.positive.count){lower=endpointOr(robustNegative,exactMin);upper=endpointOr(robustPositive,exactMax);}
      else if(active.negative.count){lower=endpointOr(robustNegative,exactMin);upper=endpointOr(nearestNegative,Math.min(0,exactMax));}
      else if(active.positive.count){lower=endpointOr(nearestPositive,Math.max(0,exactMin));upper=endpointOr(robustPositive,exactMax);}
    }else if(mode==='symmetric_absolute'){
      const maximum=Math.max(Math.abs(exactMin),Math.abs(exactMax));lower=-maximum;upper=maximum;
    }else if(mode==='manual'){
      lower=requireFinite(resolvedRequest.range.lower,'NMDisplaySemantics:InvalidManualRange','Manual display lower bound');
      upper=requireFinite(resolvedRequest.range.upper,'NMDisplaySemantics:InvalidManualRange','Manual display upper bound');
      if(!(lower<upper))fail('NMDisplaySemantics:InvalidManualRange','Manual display range requires lower < upper.');
      if(lower<exactMin||upper>exactMax)fail('NMDisplaySemantics:ManualRangeOutsideData','Manual display range must lie within the exact data range.');
    }
    const lowerClippedCount=countBelow(active.negative,lower)+countBelow(active.positive,lower);
    const upperClippedCount=countAbove(active.negative,upper)+countAbove(active.positive,upper);
    const denominator=Math.max(1,activeCount);
    return {
      mode,kind:polarity.kind,exactMin,exactMax,lower,upper,constantRange:upper===lower,activeCount,
      lowerClippedCount,upperClippedCount,
      lowerClippedFraction:lowerClippedCount/denominator,
      upperClippedFraction:upperClippedCount/denominator,
      robustQuantiles:[.02,.98]
    };
  }

  function rgbUnitTripletToHex(value,label){
    const channels=toArray(value);
    if(channels.length!==3||channels.some(channel=>typeof channel!=='number'||!Number.isFinite(channel)||channel<0||channel>1))fail('NMDisplaySemantics:InvalidColor',`${label} must contain three finite channels in [0,1].`);
    return '#'+channels.map(channel=>Math.round(channel*255).toString(16).padStart(2,'0')).join('');
  }
  function inheritedColor(defaults,hexField,rgbField,fallback,label){
    if(!absent(defaults[hexField]))return normalizeHexColor(defaults[hexField],label);
    if(!absent(defaults[rgbField]))return rgbUnitTripletToHex(defaults[rgbField],label);
    return fallback;
  }

  function normalizeHexColor(value,label){
    if(typeof value!=='string'||!/^#[0-9a-f]{6}$/i.test(value))fail('NMDisplaySemantics:InvalidColor',`${label} must be a six-digit hexadecimal colour.`);
    return value.toLowerCase();
  }
  function defaultColorStops(polarity,legacyColors){
    const colors=legacyColors&&typeof legacyColors==='object'?legacyColors:{};
    const negative=normalizeHexColor(colors.negative||DEFAULT_COLORS.negative,'Negative colour');
    const midpoint=normalizeHexColor(colors.midpoint||DEFAULT_COLORS.midpoint,'Midpoint colour');
    const positive=normalizeHexColor(colors.positive||DEFAULT_COLORS.positive,'Positive colour');
    const zeroPosition=colors.zeroPosition==null?.5:requireFinite(colors.zeroPosition,'NMDisplaySemantics:InvalidZeroPosition','Colour zero position');
    if(zeroPosition<0||zeroPosition>1)fail('NMDisplaySemantics:InvalidZeroPosition','Colour zero position must lie in [0,1].');
    if(polarity==='negative')return [{position:0,color:negative},{position:1,color:midpoint}];
    if(polarity==='positive'||polarity==='magnitude'||polarity==='none')return [{position:0,color:midpoint},{position:1,color:positive}];
    if(zeroPosition<=0)return [{position:0,color:midpoint},{position:1,color:positive}];
    if(zeroPosition>=1)return [{position:0,color:negative},{position:1,color:midpoint}];
    return [{position:0,color:negative},{position:zeroPosition,color:midpoint},{position:1,color:positive}];
  }
  function normalizeColorStops(stops,polarity,legacyColors){
    requireMode(polarity,['signed','positive','negative','magnitude','none'],'NMDisplaySemantics:InvalidPolarity','Colour polarity');
    if(stops==null||toArray(stops).length===0)return deepFreeze(defaultColorStops(polarity,legacyColors));
    const list=toArray(stops);
    if(list.length<MIN_COLOR_STOPS||list.length>MAX_COLOR_STOPS)fail('NMDisplaySemantics:InvalidColorStopCount',`Colour stops must contain ${MIN_COLOR_STOPS} to ${MAX_COLOR_STOPS} entries.`);
    const normalized=list.map((stop,index)=>{
      if(!stop||typeof stop!=='object')fail('NMDisplaySemantics:InvalidColorStop',`Colour stop ${index+1} must be an object.`);
      const position=requireFinite(stop.position,'NMDisplaySemantics:InvalidColorStop',`Colour stop ${index+1} position`);
      if(position<0||position>1)fail('NMDisplaySemantics:InvalidColorStop',`Colour stop ${index+1} position must lie in [0,1].`);
      return {position,color:normalizeHexColor(stop.color,`Colour stop ${index+1}`)};
    });
    for(let index=1;index<normalized.length;index++)if(!(normalized[index-1].position<normalized[index].position))fail('NMDisplaySemantics:UnorderedColorStops','Colour-stop positions must be strictly increasing.');
    return deepFreeze(normalized);
  }
  function resolveOpacity(request){
    return requireFinite(requireDisplayRequest(request).opacity,'NMDisplaySemantics:InvalidOpacity','Opacity');
  }
  function zeroPosition(range){
    if(range.constantRange)return .5;
    return clamp((0-range.lower)/(range.upper-range.lower),0,1);
  }
  function resolveDisplayContract(overlay,request,support,identity){
    const resolvedRequest=requireDisplayRequest(request);
    const statistics=baseStatistics(overlay,support);
    declaredRange(overlay);
    const polarity=effectivePolarity(overlay,support);
    const threshold=resolvedRequest.threshold;
    const range=displayRangeModel(overlay,resolvedRequest,support);
    const opacity=resolveOpacity(resolvedRequest);
    const position=zeroPosition(range);
    const colors={negative:resolvedRequest.colors.negative,midpoint:resolvedRequest.colors.midpoint,positive:resolvedRequest.colors.positive,zeroPosition:position};
    const colorStops=normalizeColorStops(resolvedRequest.colorStops,polarity.kind,colors);
    return deepFreeze({
      contractVersion:CONTRACT_VERSION,
      requestVersion:REQUEST_VERSION,
      identity:identity&&typeof identity==='object'?Object.assign({},identity):{},
      valueState:{finiteCount:statistics.count,missingCount:statistics.missingCount},
      polarity:{kind:polarity.kind,theoretical:polarity.theoretical},
      exactRange:{lower:range.exactMin,upper:range.exactMax,constant:range.exactMax===range.exactMin},
      shownRange:{mode:range.mode,lower:range.lower,upper:range.upper,constant:range.constantRange},
      clipping:{lowerCount:range.lowerClippedCount,upperCount:range.upperClippedCount,lowerFraction:range.lowerClippedFraction,upperFraction:range.upperClippedFraction,eligibleCount:range.activeCount},
      threshold,
      opacity,
      zeroPosition:position,
      colorStops
    });
  }
  function classifyValue(value,contract,presence){
    if(!contract||contract.contractVersion!==CONTRACT_VERSION)fail('NMDisplaySemantics:InvalidContract','Display contract is missing or incompatible.');
    if(presence===false||presence==='absent')return deepFreeze({state:'absent',sign:0});
    const validated=validateDisplayValue(value,'Display value');
    if(validated.state==='missing')return deepFreeze({state:'missing',sign:0});
    const included=thresholdIncludes(validated.value,contract.threshold);
    return deepFreeze({state:included?'included':'subthreshold',sign:validated.value<0?-1:(validated.value>0?1:0)});
  }
  function colorCoordinate(value,contract){
    const classification=classifyValue(value,contract,true);
    if(classification.state!=='included')return NaN;
    const lower=contract.shownRange.lower,upper=contract.shownRange.upper;
    if(contract.shownRange.constant)return .5;
    return clamp((value-lower)/(upper-lower),0,1);
  }
  function extremaEligible(value,contract,presence){return classifyValue(value,contract,presence).state==='included';}
  function classificationSign(value,contract,presence){
    const classification=classifyValue(value,contract,presence);
    return classification.state==='included'?classification.sign:0;
  }
  function prepareClassificationSign(contract){
    if(!contract||contract.contractVersion!==CONTRACT_VERSION)fail('NMDisplaySemantics:InvalidContract','Display contract is missing or incompatible.');
    const threshold=contract.threshold||{},mode=requireMode(threshold.mode,THRESHOLD_MODES,'NMDisplaySemantics:InvalidThresholdMode','Threshold mode');
    return function(value,presence){
      if(presence===false||presence==='absent')return 0;if(typeof value!=='number')return classificationSign(value,contract,presence);if(Number.isNaN(value))return 0;if(!Number.isFinite(value))fail('NMDisplaySemantics:NonFiniteValue','Display value contains an infinite value.');
      const included=mode==='none'?true:(mode==='outside_interval'?(value<=threshold.lower||value>=threshold.upper):(mode==='above_abs'?Math.abs(value)>=threshold.value:(mode==='above'?value>=threshold.value:value<=threshold.value)));return included?(value<0?-1:(value>0?1:0)):0;
    };
  }
  function contractForDisplay(display){
    if(!display||typeof display!=='object')fail('NMDisplaySemantics:MissingDisplayState','Display state is required.');
    const contract=DISPLAY_CONTRACTS.get(display);
    if(!contract)fail('NMDisplaySemantics:UnresolvedDisplayState','Display state has not been resolved into a canonical display contract.');
    return contract;
  }

  function synchronizeDisplayState(state,request,contract){
    const target=state&&typeof state==='object'?state:{};
    target.thresholdMode=request.threshold.mode;
    target.thresholdLow=request.threshold.mode==='outside_interval'?request.threshold.lower:NaN;
    target.thresholdHigh=request.threshold.mode==='outside_interval'?request.threshold.upper:NaN;
    target.thresholdValue=['above_abs','above','below'].includes(request.threshold.mode)?request.threshold.value:NaN;
    target.opacity=request.opacity;
    target.displayRangeMode=request.range.mode;
    target.manualDisplayLower=request.range.mode==='manual'?request.range.lower:contract.shownRange.lower;
    target.manualDisplayUpper=request.range.mode==='manual'?request.range.upper:contract.shownRange.upper;
    target.negativeColor=request.colors.negative;
    target.midpointColor=request.colors.midpoint;
    target.positiveColor=request.colors.positive;
    target.colorStops=contract.colorStops.map(stop=>({position:stop.position,color:stop.color}));
    target.effectivePolarity=contract.polarity.kind;
    target.colorZeroPosition=contract.zeroPosition;
    target.exactDataRange=[contract.exactRange.lower,contract.exactRange.upper];
    target.activeDisplayRange=[contract.shownRange.lower,contract.shownRange.upper];
    target.displayRangeClipping={lowerCount:contract.clipping.lowerCount,upperCount:contract.clipping.upperCount,lowerFraction:contract.clipping.lowerFraction,upperFraction:contract.clipping.upperFraction,activeCount:contract.clipping.eligibleCount};
    return target;
  }
  function resolveDisplayState(display,overlay,support,options,identity){
    const state=display&&typeof display==='object'?display:{};
    const request=displayRequestFromState(state,overlay,support,options);
    const contract=resolveDisplayContract(overlay,request,support,identity);
    synchronizeDisplayState(state,request,contract);
    DISPLAY_REQUESTS.set(state,request);
    DISPLAY_CONTRACTS.set(state,contract);
    return {state,request,contract};
  }
  function adoptResolvedDisplayState(target,resolution){
    if(!target||typeof target!=='object'||Array.isArray(target))fail('NMDisplaySemantics:MissingDisplayState','Display-state commit requires one mutable target object.');
    if(!resolution||typeof resolution!=='object'||!resolution.state||typeof resolution.state!=='object')fail('NMDisplaySemantics:InvalidResolution','Display-state commit requires one canonical resolution.');
    const request=resolution.request,contract=resolution.contract;
    if(!request||request.requestVersion!==REQUEST_VERSION)fail('NMDisplaySemantics:InvalidResolution','Display-state commit received an invalid canonical display request.');
    assertDisplayContract(contract,{consumer:'Display-state commit',facets:['threshold','shownRange','colorStops','opacity']});
    Object.assign(target,resolution.state);
    DISPLAY_REQUESTS.set(target,request);
    DISPLAY_CONTRACTS.set(target,contract);
    return {state:target,request,contract};
  }
  function requestForDisplay(display){
    if(!display||typeof display!=='object')fail('NMDisplaySemantics:MissingDisplayState','Display state is required.');
    const request=DISPLAY_REQUESTS.get(display);
    if(!request)fail('NMDisplaySemantics:UnresolvedDisplayState','Display state has not been translated into a canonical display request.');
    return request;
  }


  function thresholdSpec(overlay,display,field){
    const range=declaredRange(overlay)||orderedRange(overlay),lower=range[0],upper=range[1];
    const threshold=requestForDisplay(display).threshold,mode=threshold.mode;
    let minimum=lower,maximum=upper;
    if(field==='thresholdLow'){minimum=Math.min(lower,0,threshold.lower);maximum=Math.min(upper,0);}
    else if(field==='thresholdHigh'){minimum=Math.max(lower,0);maximum=Math.max(upper,0,threshold.upper);}
    else if(field==='thresholdValue'&&mode==='above_abs'){minimum=0;maximum=Math.max(Math.abs(lower),Math.abs(upper));}
    else if(field==='thresholdValue'&&mode==='above')minimum=Math.max(0,lower);
    else if(field==='thresholdValue'&&mode==='below')maximum=Math.min(0,upper);
    if(maximum<minimum)fail('NMDisplaySemantics:InvalidThresholdRange','Threshold input range is invalid.');
    const interval=maximum-minimum;
    const fallback=Math.max(Math.abs(minimum),Math.abs(maximum),Math.abs(lower),Math.abs(upper),1)/1000;
    return {min:minimum,max:maximum,step:niceStep(interval>0?interval/1000:fallback),rangeMin:lower,rangeMax:upper};
  }
  function displayRangeSpec(overlay){
    const range=orderedRange(overlay),span=range[1]-range[0];
    return {min:range[0],max:range[1],step:span===0?Number.EPSILON:span/200};
  }
  function thresholdDigits(step){
    const positive=Math.abs(finite(step,0));if(!(positive>0))return 4;return clamp(Math.ceil(-Math.log10(positive)),0,6);
  }
  function formatThreshold(value,step){
    const number=finite(value,NaN);if(!Number.isFinite(number))return '';
    const digits=thresholdDigits(step),rounded=Math.abs(number)<Math.pow(10,-digits)/2?0:number;
    return rounded.toFixed(digits).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');
  }
  function thresholdTolerance(spec){
    const input=spec||{},lower=finite(input.min,0),upper=finite(input.max,lower),step=Math.abs(finite(input.step,0)),scale=Math.max(1,Math.abs(lower),Math.abs(upper));
    return Math.max(scale*64*Number.EPSILON,step*1e-4,scale*1e-15);
  }
  function normalizeThresholdValue(value,spec){
    const input=spec||{},lower=finite(input.min,-Number.MAX_VALUE),upper=finite(input.max,Number.MAX_VALUE),raw=finite(value,NaN),tolerance=thresholdTolerance({min:lower,max:upper,step:input.step});
    if(!Number.isFinite(raw))return {accepted:false,value:clamp(0,lower,upper),raw,tolerance,boundary:''};
    if(raw<lower-tolerance||raw>upper+tolerance)return {accepted:false,value:clamp(raw,lower,upper),raw,tolerance,boundary:''};
    if(Math.abs(raw-lower)<=tolerance)return {accepted:true,value:lower,raw,tolerance,boundary:'minimum'};
    if(Math.abs(raw-upper)<=tolerance)return {accepted:true,value:upper,raw,tolerance,boundary:'maximum'};
    return {accepted:true,value:clamp(raw,lower,upper),raw,tolerance,boundary:''};
  }
  function trimFixed(value,digits){return value.toFixed(digits).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');}
  function numericAttribute(value){const number=finite(value,NaN);return Number.isFinite(number)?String(Number(number.toPrecision(15))):'';}
  function formatThresholdWithinBounds(value,spec){
    const input=spec||{},result=normalizeThresholdValue(value,input),number=result.value;if(!Number.isFinite(number))return '';
    const lower=finite(input.min,-Number.MAX_VALUE),upper=finite(input.max,Number.MAX_VALUE),base=thresholdDigits(input.step);
    if(result.boundary){
      const tolerance=thresholdTolerance(input);
      for(let digits=base;digits<=15;digits++){
        const candidate=trimFixed(number,digits),parsed=Number(candidate),epsilon=Math.max(1,Math.abs(number))*32*Number.EPSILON;
        if(parsed>=lower-epsilon&&parsed<=upper+epsilon&&Math.abs(parsed-number)<=tolerance)return candidate;
      }
      return numericAttribute(number);
    }
    const formatted=formatThreshold(number,input.step),parsed=Number(formatted);
    return Number.isFinite(parsed)&&parsed>=lower&&parsed<=upper?formatted:numericAttribute(number);
  }
  function colorbarModel(overlay,display,support){
    void overlay;void support;
    const contract=contractForDisplay(display),threshold=contract.threshold;
    return {
      kind:contract.polarity.kind,min:contract.shownRange.lower,max:contract.shownRange.upper,exactMin:contract.exactRange.lower,exactMax:contract.exactRange.upper,
      displayRangeMode:contract.shownRange.mode,lowerClippedCount:contract.clipping.lowerCount,upperClippedCount:contract.clipping.upperCount,
      lowerClippedFraction:contract.clipping.lowerFraction,upperClippedFraction:contract.clipping.upperFraction,activeCount:contract.clipping.eligibleCount,
      colorStops:contract.colorStops.map(stop=>({position:stop.position,color:stop.color})),
      colors:contract.colorStops.map(stop=>stop.color),stops:contract.colorStops.map(stop=>stop.position),
      thresholds:threshold.mode==='outside_interval'?[threshold.lower,threshold.upper]:(threshold.mode==='none'?[]:[threshold.value])
    };
  }


  const API={
    CONTRACT_VERSION,REQUEST_VERSION,THRESHOLD_MODES,THRESHOLD_MODE_CODES,RANGE_MODES,POLARITIES,thresholdModeCode,
    displayRequestFromState,resolveDisplayContract,resolveDisplayState,adoptResolvedDisplayState,requestForDisplay,contractForDisplay,assertDisplayContract,classifyValue,classificationSign,prepareClassificationSign,colorCoordinate,extremaEligible,normalizeColorStops,
    thresholdSpec,thresholdDigits,formatThreshold,thresholdTolerance,normalizeThresholdValue,formatThresholdWithinBounds,
    numericAttribute,colorbarModel,
    _test:{quantile,quantileRange,lowerBound,upperBound,activeRanges,countBelow,countAbove,niceStep,thresholdIncludes,validateDisplayValue,declaredRange,orderedRange,effectivePolarity,thresholdDefaults,displayRangeSpec,displayRangeModel,baseStatistics,normalizeRangeMode}
  };
  if(typeof module!=='undefined'&&module.exports)module.exports=API;
  root.NMResultsViewerDisplaySemantics=API;
  if(typeof window!=='undefined')window.NMResultsViewerDisplaySemantics=API;
})(typeof self!=='undefined'?self:(typeof window!=='undefined'?window:(typeof globalThis!=='undefined'?globalThis:this)));
