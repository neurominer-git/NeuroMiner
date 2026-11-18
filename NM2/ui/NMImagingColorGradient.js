(function(){
  'use strict';

  const {clamp,text,toArray,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  const MAX_STOPS=10;
  const MIN_STOPS=2;
  const DEFAULTS={negative:'#0000ff',midpoint:'#ffffff',positive:'#ff0000'};
  function finite(value,fallback){const number=Number(value);return Number.isFinite(number)?number:fallback;}
  function semantics(){
    const api=typeof window!=='undefined'&&window.NMResultsViewerDisplaySemantics;
    if(!api||typeof api.normalizeColorStops!=='function')throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');
    return api;
  }
  function color(value){
    const string=text(value).trim();
    if(!/^#[0-9a-f]{6}$/i.test(string))throw new Error(`Invalid six-digit hexadecimal colour: ${string||'<empty>'}.`);
    return string.toLowerCase();
  }
  function rgb01(hex){
    const string=color(hex).slice(1);
    return [parseInt(string.slice(0,2),16)/255,parseInt(string.slice(2,4),16)/255,parseInt(string.slice(4,6),16)/255];
  }
  function lerp(a,b,t){return a.map((value,index)=>value+(b[index]-value)*t);}
  function legacyColors(display){
    return {
      negative:display&&display.negativeColor||DEFAULTS.negative,
      midpoint:display&&display.midpointColor||DEFAULTS.midpoint,
      positive:display&&display.positiveColor||DEFAULTS.positive,
      zeroPosition:display&&display.colorZeroPosition==null?.5:Number(display.colorZeroPosition)
    };
  }
  function defaultStops(kind,display){
    return semantics().normalizeColorStops(null,kind,legacyColors(display)).map(stop=>({position:stop.position,color:stop.color}));
  }
  function syncLegacy(display,stops){
    if(!display||!stops.length)return;
    display.negativeColor=stops[0].color;
    display.positiveColor=stops[stops.length-1].color;
    let nearest=stops[0];
    stops.forEach(stop=>{if(Math.abs(stop.position-.5)<Math.abs(nearest.position-.5))nearest=stop;});
    display.midpointColor=nearest.color;
  }
  function resolvedStops(display,kind){
    if(!display||typeof display!=='object')throw new Error('Colour-gradient resolution requires a display-state object.');
    return semantics().normalizeColorStops(display.colorStops,kind,legacyColors(display)).map(stop=>({position:stop.position,color:stop.color}));
  }
  function normalize(display,kind){
    const stops=resolvedStops(display,kind);
    display.colorStops=stops;
    syncLegacy(display,stops);
    return stops;
  }
  function sample(stops,t,scale){
    const list=toArray(stops);
    if(list.length<MIN_STOPS)throw new Error(`Colour sampling requires at least ${MIN_STOPS} resolved stops.`);
    const x=clamp(finite(t,0),0,1);
    let result=rgb01(list[0].color);
    if(x>=list[list.length-1].position)result=rgb01(list[list.length-1].color);
    else{
      for(let index=1;index<list.length;index++){
        const a=list[index-1],b=list[index];
        if(x<=b.position){
          result=lerp(rgb01(a.color),rgb01(b.color),clamp((x-a.position)/(b.position-a.position),0,1));
          break;
        }
      }
    }
    return scale===255?result.map(value=>Math.round(value*255)):result;
  }
  function css(stops,direction){
    const list=toArray(stops);
    if(list.length<MIN_STOPS)throw new Error(`CSS gradients require at least ${MIN_STOPS} resolved stops.`);
    const resolvedDirection=direction||'to top';
    return `linear-gradient(${resolvedDirection},${list.map(stop=>`${color(stop.color)} ${(stop.position*100).toFixed(1)}%`).join(',')})`;
  }
  function lutRgba8(stops,size){
    const list=semantics().normalizeColorStops(stops,'signed',DEFAULTS);
    const count=Math.max(2,Math.round(finite(size,256))),output=new Uint8Array(count*4);
    for(let index=0;index<count;index++){
      const rgb=sample(list,index/(count-1),255),offset=4*index;
      output[offset]=rgb[0];output[offset+1]=rgb[1];output[offset+2]=rgb[2];output[offset+3]=255;
    }
    return output;
  }
  function sampleContract(value,contract,scale){
    const api=semantics(),coordinate=api.colorCoordinate(value,contract);
    if(!Number.isFinite(coordinate))throw new Error('Canonical colour sampling requires an included display value.');
    return sample(contract.colorStops,coordinate,scale);
  }
  function uniforms(stops){
    const list=toArray(stops);
    if(list.length<MIN_STOPS||list.length>MAX_STOPS)throw new Error(`WebGL colour uniforms require ${MIN_STOPS} to ${MAX_STOPS} resolved stops.`);
    const positions=new Float32Array(MAX_STOPS),colors=new Float32Array(MAX_STOPS*3);
    for(let index=0;index<MAX_STOPS;index++){
      const stop=index<list.length?list[index]:list[list.length-1],rgb=rgb01(stop.color);
      positions[index]=stop.position;colors[3*index]=rgb[0];colors[3*index+1]=rgb[1];colors[3*index+2]=rgb[2];
    }
    return {count:list.length,positions,colors};
  }
  function montageNumber(value,digits){
    const n=Number(value);
    if(!Number.isFinite(n))return '—';
    if(Math.abs(n)>=10000||(Math.abs(n)>0&&Math.abs(n)<Math.pow(10,-digits)))
      return n.toExponential(Math.max(1,digits-1));
    return n.toFixed(digits).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');
  }
  function drawMontageColorbar(ctx,legend,gridWidth,height,scale,theme){
    const x=gridWidth+24*scale;
    const y=58*scale;
    const width=22*scale;
    const barHeight=height-112*scale;
    const titleX=gridWidth+88*scale;
    const gradient=ctx.createLinearGradient(0,y+barHeight,0,y);
    legend.colorStops.forEach(stop=>gradient.addColorStop(stop.position,stop.color));
    ctx.fillStyle=gradient;
    ctx.fillRect(x,y,width,barHeight);
    ctx.strokeStyle=theme.border;
    ctx.strokeRect(x,y,width,barHeight);
    ctx.fillStyle=theme.text;
    ctx.textAlign='center';
    ctx.font=`bold ${15*scale}px Arial`;
    ctx.fillText(text(legend.label).replace(/_/g,' '),titleX,26*scale,160*scale);
    const scaleLabels={robust_polarity_wise:'Robust signed',full_data_range:'Full range',symmetric_absolute:'Symmetric |value|',manual:'Manual'};
    ctx.font=`${11*scale}px Arial`;
    ctx.fillText(`${scaleLabels[legend.rangeMode]} color scale`,titleX,45*scale,160*scale);
    ctx.font=`${13*scale}px Arial`;
    ctx.textAlign='left';
    ctx.textBaseline='middle';
    const markY=value=>legend.max>legend.min?y+barHeight*(legend.max-value)/(legend.max-legend.min):y+barHeight/2;
    const marks=legend.thresholdValues.filter(Number.isFinite).filter(value=>value>=legend.min&&value<=legend.max);
    for(let i=0;i<=4;i++){
      const yy=y+i*barHeight/4;
      if(marks.some(value=>Math.abs(yy-markY(value))<17*scale))continue;
      ctx.beginPath();ctx.moveTo(x+width,yy);ctx.lineTo(x+width+6*scale,yy);ctx.stroke();
      ctx.fillText(montageNumber(legend.max+(legend.min-legend.max)*i/4,3),x+width+10*scale,yy,110*scale);
    }
    marks.forEach(value=>{
      const yy=markY(value);
      ctx.fillStyle=theme.threshold;
      ctx.fillRect(x-2*scale,yy-scale,width+4*scale,2*scale);
      ctx.fillStyle=theme.threshold;
      ctx.fillText(`T${value<0?'−':'+'}: ${montageNumber(value,4)}`,x+width+10*scale,yy,110*scale);
    });
  }
  function metricRange(editor){
    const lower=finite(editor&&editor.getAttribute&&editor.getAttribute('data-imaging-colorbar-min-value'),NaN);
    const upper=finite(editor&&editor.getAttribute&&editor.getAttribute('data-imaging-colorbar-max-value'),NaN);
    if(!(Number.isFinite(lower)&&Number.isFinite(upper)&&upper>=lower))throw new Error('Colourbar metric range is invalid.');
    return [lower,upper];
  }
  function metricValue(range,position){return range[0]+(range[1]-range[0])*position;}
  function formatMetricValue(value){
    const number=Number(value);if(!Number.isFinite(number))return '—';const absolute=Math.abs(number);
    if(absolute===0)return '0';if(absolute>=1000||absolute<1e-4)return number.toExponential(2);if(absolute<.1)return number.toFixed(4);if(absolute<10)return number.toFixed(3);if(absolute<100)return number.toFixed(2);return number.toFixed(1);
  }
  function stopMarkup(stops,range,escape){
    return stops.map((stop,index)=>{const percent=(stop.position*100).toFixed(1),label=escape(formatMetricValue(metricValue(range,stop.position)));return `<span class="rvImagingColorStopMetric" data-imaging-color-stop-metric="${index}" style="bottom:${percent}%">${label}</span><button type="button" class="rvImagingColorStop" data-imaging-color-stop="${index}" style="bottom:${percent}%;--rv-stop-color:${escape(stop.color)}" aria-label="Colour stop ${index+1} at ${label}"></button>`;}).join('');
  }
  function html(display,kind,options){
    const settings=options||{},escape=typeof settings.escape==='function'?settings.escape:escapeHtml,stops=resolvedStops(display,kind);
    const top=escape(settings.maxLabel||''),bottom=escape(settings.minLabel||''),tooltip=settings.tooltipAttributes||'';
    const range=[finite(settings.minValue,NaN),finite(settings.maxValue,NaN)];
    if(!(Number.isFinite(range[0])&&Number.isFinite(range[1])&&range[1]>=range[0]))throw new Error('Colourbar labels require a finite ordered range.');
    return `<div class="rvImagingColorbarEditor" data-imaging-colorbar-editor data-effective-polarity="${escape(kind||'signed')}" data-imaging-colorbar-min-value="${escape(range[0])}" data-imaging-colorbar-max-value="${escape(range[1])}" ${tooltip}><span class="rvImagingColorbarLimit rvImagingColorbarLimit--max" data-imaging-colorbar-max>${top}</span><div class="rvImagingColorbarBody"><div class="rvImagingColorbarTrackWrap"><i class="rvImagingColorbarTrack" data-imaging-colorbar-track style="--rv-colorbar-gradient:${escape(css(stops,'to top'))}"></i></div><div class="rvImagingColorbarStops">${stopMarkup(stops,range,escape)}</div></div><span class="rvImagingColorbarLimit rvImagingColorbarLimit--min" data-imaging-colorbar-min>${bottom}</span><input type="color" class="rvImagingColorStopPicker" data-imaging-color-stop-picker aria-label="Colour stop picker"></div>`;
  }
  function menuPosition(width,height,x,y,viewportWidth,viewportHeight,padding){
    const margin=Math.max(0,Number(padding)||8),viewportW=Math.max(1,Number(viewportWidth)||1),viewportH=Math.max(1,Number(viewportHeight)||1),menuW=Math.max(0,Number(width)||0),menuH=Math.max(0,Number(height)||0),pointerX=Number(x)||0,pointerY=Number(y)||0;
    const preferredLeft=pointerX+menuW+margin>viewportW?pointerX-menuW:pointerX,preferredTop=pointerY+menuH+margin>viewportH?pointerY-menuH:pointerY;
    return {left:clamp(preferredLeft,margin,Math.max(margin,viewportW-menuW-margin)),top:clamp(preferredTop,margin,Math.max(margin,viewportH-menuH-margin))};
  }
  function createMenu(items,x,y){
    const old=document.querySelector('.rvImagingColorStopMenu');if(old)old.remove();
    const menu=document.createElement('div');menu.className='rvImagingColorStopMenu';menu.style.visibility='hidden';menu.style.left='0px';menu.style.top='0px';
    items.forEach(item=>{const button=document.createElement('button');button.type='button';button.textContent=item.label;button.disabled=!!item.disabled;button.addEventListener('click',()=>{menu.remove();item.action();});menu.appendChild(button);});
    document.body.appendChild(menu);const rectangle=menu.getBoundingClientRect(),position=menuPosition(rectangle.width,rectangle.height,x,y,window.innerWidth,window.innerHeight,8);menu.style.left=`${Math.round(position.left)}px`;menu.style.top=`${Math.round(position.top)}px`;menu.style.visibility='visible';
    const close=event=>{if(!menu.contains(event.target)){menu.remove();document.removeEventListener('pointerdown',close,true);}};setTimeout(()=>document.addEventListener('pointerdown',close,true),0);return menu;
  }
  function validateEditedStops(stops,kind,display){
    return semantics().normalizeColorStops(stops,kind,legacyColors(display)).map(stop=>({position:stop.position,color:stop.color}));
  }
  function bind(root,options){
    if(!root||!options||typeof options.onEdit!=='function')throw new Error('Colour-gradient binding requires a root and one onEdit command callback.');
    let drag=null,selected=-1;
    const editor=()=>root.querySelector('[data-imaging-colorbar-editor]');
    const display=()=>options.getDisplay&&options.getDisplay();
    const kind=()=>options.getKind?options.getKind():'signed';
    const stopsFor=()=>resolvedStops(display(),kind());
    const emit=(stops,reason,phase)=>options.onEdit(validateEditedStops(stops,kind(),display()),reason||'color_gradient',phase||'commit');
    const render=()=>{const currentEditor=editor(),state=display();if(!currentEditor||!state)return;const stops=resolvedStops(state,kind()),track=currentEditor.querySelector('[data-imaging-colorbar-track]'),holder=currentEditor.querySelector('.rvImagingColorbarStops'),range=metricRange(currentEditor);if(track)track.style.setProperty('--rv-colorbar-gradient',css(stops,'to top'));if(holder)holder.innerHTML=stopMarkup(stops,range,escapeHtml);};
    const trackPosition=(event,track)=>{const rectangle=track.getBoundingClientRect();return clamp(1-(event.clientY-rectangle.top)/Math.max(1,rectangle.height),0,1);};
    const addAt=position=>{const stops=stopsFor();if(stops.length>=MAX_STOPS){if(typeof options.onWarning==='function')options.onWarning(`A maximum of ${MAX_STOPS} colour stops is supported.`);return;}const sampled=sample(stops,position,255),hex='#'+sampled.map(value=>value.toString(16).padStart(2,'0')).join('');stops.push({position,color:hex});stops.sort((a,b)=>a.position-b.position);emit(stops,'color_stop_add','commit');render();};
    const openPicker=index=>{const currentEditor=editor(),picker=currentEditor&&currentEditor.querySelector('[data-imaging-color-stop-picker]'),stops=stopsFor();if(!picker||!stops[index])return;selected=index;picker.value=stops[index].color;try{if(typeof picker.focus==='function')picker.focus({preventScroll:true});}catch(error){}try{if(typeof picker.showPicker==='function')picker.showPicker();else picker.click();}catch(error){picker.click();}};
    const onContext=event=>{const currentEditor=editor();if(!currentEditor||!currentEditor.contains(event.target))return;const stop=event.target.closest('[data-imaging-color-stop]'),track=event.target.closest('[data-imaging-colorbar-track]');if(!stop&&!track)return;event.preventDefault();event.stopPropagation();if(track&&!stop){const position=trackPosition(event,track);createMenu([{label:'Add colour stop',disabled:stopsFor().length>=MAX_STOPS,action:()=>addAt(position)}],event.clientX,event.clientY);return;}const index=Number(stop.getAttribute('data-imaging-color-stop')),stops=stopsFor();createMenu([
      {label:'Open colour picker',action:()=>openPicker(index)},
      {label:'Duplicate stop',disabled:stops.length>=MAX_STOPS,action:()=>{const source=stops[index],previous=index>0?stops[index-1].position:0,next=index<stops.length-1?stops[index+1].position:1;let position=source.position+.025;if(position>=next)position=source.position-.025;if(position<=previous||position===source.position)throw new Error('No valid position is available for the duplicated colour stop.');stops.push({position,color:source.color});stops.sort((a,b)=>a.position-b.position);emit(stops,'color_stop_duplicate','commit');render();}},
      {label:'Delete stop',disabled:stops.length<=MIN_STOPS,action:()=>{stops.splice(index,1);emit(stops,'color_stop_delete','commit');render();}}
    ],event.clientX,event.clientY);};
    const onDouble=event=>{const stop=event.target.closest('[data-imaging-color-stop]');if(!stop||!editor()||!editor().contains(stop))return;event.preventDefault();openPicker(Number(stop.getAttribute('data-imaging-color-stop')));};
    const onPointerDown=event=>{const stop=event.target.closest('[data-imaging-color-stop]');if(!stop||!editor()||!editor().contains(stop)||event.button!==0)return;const index=Number(stop.getAttribute('data-imaging-color-stop'));if(event.detail>=2){event.preventDefault();event.stopPropagation();openPicker(index);return;}const track=editor().querySelector('[data-imaging-colorbar-track]');if(!track)return;drag={index,track,pointerId:event.pointerId,button:stop,label:editor().querySelector(`[data-imaging-color-stop-metric="${index}"]`)};stop.setPointerCapture(event.pointerId);event.preventDefault();};
    const onPointerMove=event=>{if(!drag)return;const stops=stopsFor(),stop=stops[drag.index];if(!stop)return;const previous=drag.index>0?stops[drag.index-1].position+.001:0,next=drag.index<stops.length-1?stops[drag.index+1].position-.001:1;stop.position=Math.round(clamp(trackPosition(event,drag.track),previous,next)*1000)/1000;const validated=validateEditedStops(stops,kind(),display());emit(validated,'color_stop_move','preview');drag.track.style.setProperty('--rv-colorbar-gradient',css(validated,'to top'));const percent=(stop.position*100).toFixed(1);if(drag.button){drag.button.style.bottom=`${percent}%`;drag.button.setAttribute('aria-label',`Colour stop ${drag.index+1} at ${formatMetricValue(metricValue(metricRange(editor()),stop.position))}`);}if(drag.label){drag.label.style.bottom=`${percent}%`;drag.label.textContent=formatMetricValue(metricValue(metricRange(editor()),stop.position));}};
    const endDrag=()=>{if(!drag)return;const stops=stopsFor();drag=null;emit(stops,'color_stop_move','commit');render();};
    const onChange=event=>{if(!event.target.matches('[data-imaging-color-stop-picker]')||selected<0)return;const stops=stopsFor();if(stops[selected]){stops[selected].color=color(event.target.value);emit(stops,'color_stop_color','commit');render();}selected=-1;};
    root.addEventListener('contextmenu',onContext);root.addEventListener('dblclick',onDouble);root.addEventListener('pointerdown',onPointerDown);root.addEventListener('pointermove',onPointerMove);root.addEventListener('pointerup',endDrag);root.addEventListener('pointercancel',endDrag);root.addEventListener('change',onChange);render();
    return {render,dispose:()=>{root.removeEventListener('contextmenu',onContext);root.removeEventListener('dblclick',onDouble);root.removeEventListener('pointerdown',onPointerDown);root.removeEventListener('pointermove',onPointerMove);root.removeEventListener('pointerup',endDrag);root.removeEventListener('pointercancel',endDrag);root.removeEventListener('change',onChange);}};
  }

  window.NMImagingColorGradient={MAX_STOPS,MIN_STOPS,normalize,resolvedStops,defaultStops,sampleRgb01:(stops,t)=>sample(stops,t,1),sampleRgb255:(stops,t)=>sample(stops,t,255),sampleContractRgb01:(value,contract)=>sampleContract(value,contract,1),sampleContractRgb255:(value,contract)=>sampleContract(value,contract,255),css,lutRgba8,uniforms,html,bind,drawMontageColorbar,_test:{syncLegacy,color,rgb01,metricValue,formatMetricValue,stopMarkup,menuPosition}};
})();
