/** Shared pointer-to-camera interaction for NMWebGLMeshRenderer consumers. */
(function(global){
  'use strict';
  function bind(canvas,renderer,options){
    if(!canvas||!renderer)throw new Error('Mesh interaction requires one canvas and renderer.');
    const cfg=options||{},listeners=[],on=(type,handler,opts)=>{canvas.addEventListener(type,handler,opts);listeners.push(()=>canvas.removeEventListener(type,handler,opts));};let drag=null,wheelTimer=0;
    const camera=()=>renderer.getCameraState(),emit=(phase,reason,moved,event)=>{if(typeof cfg.onChange==='function')cfg.onChange({camera:camera(),phase,reason,moved:!!moved,event});};
    const unitsPerPixel=()=>{const state=camera();return 2*state.distanceMm*Math.tan(state.fovDeg*Math.PI/360)/Math.max(1,canvas.clientHeight);};
    on('pointerdown',event=>{if(drag || (event.button!==0 && event.button!==1))return;const pan=event.shiftKey||event.button===1;drag={x:event.clientX,y:event.clientY,startX:event.clientX,startY:event.clientY,pan,moved:false,pointerId:event.pointerId};if(canvas.setPointerCapture)canvas.setPointerCapture(event.pointerId);if(typeof cfg.onStart==='function')cfg.onStart({pan,event});event.preventDefault();});
    on('pointermove',event=>{if(!drag||drag.pointerId!==event.pointerId)return;if(!drag.moved&&Math.hypot(event.clientX-drag.startX,event.clientY-drag.startY)<=3)return;const dx=event.clientX-drag.x,dy=event.clientY-drag.y;drag.x=event.clientX;drag.y=event.clientY;drag.moved=true;if(drag.pan){const k=unitsPerPixel();renderer.pan(-dx*k,dy*k);}else renderer.orbit(-dx*.008,dy*.008);emit('preview',drag.pan?'pan':'orbit',drag.moved,event);});
    const end=(event,cancelled)=>{
      if(!drag||drag.pointerId!==event.pointerId)return;
      const current=drag;drag=null;
      if(canvas.hasPointerCapture(current.pointerId))canvas.releasePointerCapture(current.pointerId);
      emit('commit',current.pan?'pan':'orbit',current.moved,event);
      if(cancelled||current.moved||current.pan)return;
      if(cfg.focusOnPick){
        const rect=canvas.getBoundingClientRect(),k=unitsPerPixel();
        renderer.pan((event.clientX-rect.left-rect.width/2)*k,(rect.top+rect.height/2-event.clientY)*k);
        emit('commit','focus',false,event);
      }else if(typeof cfg.onPick==='function')cfg.onPick(event);
    };
    on('pointerup',event=>end(event,false));on('pointercancel',event=>end(event,true));
    on('lostpointercapture',event=>end(event,true));
    if(cfg.onReset)on('dblclick',event=>{cfg.onReset();emit('commit','reset',true,event);});
    on('wheel',event=>{event.preventDefault();if(!wheelTimer&&typeof cfg.onStart==='function')cfg.onStart({pan:false,event});renderer.zoom(event.deltaY>0?1.10:1/1.10);emit('preview','zoom',true,event);if(wheelTimer)clearTimeout(wheelTimer);wheelTimer=setTimeout(()=>{wheelTimer=0;emit('commit','zoom',true,event);},140);},{passive:false});
    return {dispose:()=>{if(wheelTimer)clearTimeout(wheelTimer);listeners.splice(0).forEach(remove=>remove());}};
  }
  global.NMWebGLMeshInteraction=Object.freeze({bind});
})(typeof window!=='undefined'?window:globalThis);
