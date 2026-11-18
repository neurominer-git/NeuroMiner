/**
 * NMResultsViewerPanelControls
 *
 * Pathway-neutral owner for Results Viewer workspace-panel lifecycle and the
 * browser-only pinned/auto-hide presentation of control regions. The component
 * owns panel-header event wiring, collapse/maximize transitions, move/resize
 * interaction, per-panel resize observation, control-overlay lifecycle and
 * disposal. Workspace-specific layout policy is supplied through explicit
 * callbacks; scientific, display and renderer state remain outside this module.
 *
 * Contract: NM-RESULTS-VIEWER-PANEL-CONTROLS-V1
 */
(function(global){
  'use strict';

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-PANEL-CONTROLS-V1';
  const STATES=new WeakMap();
  const MODE_PINNED='pinned';
  const MODE_AUTO='auto_hide';
  const DEFAULT_DURATION=190;
  const DEFAULT_HIDE_DELAY=180;
  const CONTROL_SELECTOR=[
    '.rvFeatureRibbon',
    '.rvLegacyPlotToolbar',
    '.rvPanelControls',
    '.rvModelOptControls',
    '.rvModelOptPartitionToolbar',
    '.rvModelOptMetricToggleStrip',
    '.rvModelOptMatrixViewStrip',
    '.rvModelOptSurfaceControls',
    '.rvModelOptComparisonControls',
    '.rvFusionControls',
    '.rvSubjectPanelHeader',
    '.rvSubjectImageQCControls'
  ].join(',');
  const PLOT_SELECTOR=[
    '.rvFeaturePlotRegion',
    '.rvFeatureRelationViewport',
    '.rvFeatureGraphViewport',
    '.rvClassPlotBox',
    '.rvPlotBox',
    '.rvPiePlot',
    '.rvConfusionSquare',
    '.rvSubjectImageQCViewport',
    '.rvSubjectSurfaceQCViewport',
    '.rvSubjectConnectivityQCViewport',
    '.rvFusionPlot',
    '.rvPanelSvg'
  ].join(',');

  const finite=value=>Number.isFinite(Number(value));
  const number=(value,fallback)=>finite(value)?Number(value):fallback;
  const reducedMotion=()=>!!(global.matchMedia&&global.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const requestFrame=callback=>typeof global.requestAnimationFrame==='function'?global.requestAnimationFrame(callback):global.setTimeout(callback,0);
  const cancelFrame=handle=>{if(!handle)return;if(typeof global.cancelAnimationFrame==='function')global.cancelAnimationFrame(handle);else global.clearTimeout(handle);};

  function panelError(code,message){const error=new Error(String(message||'Results Viewer panel-control failure.'));error.name='NMResultsViewerPanelControlsError';error.code=String(code||'NMResultsViewerPanelControls:Failure');return error;}
  function fail(code,message){throw panelError(code,message);}
  function requirePanel(panel){if(!panel||typeof panel.querySelector!=='function'||typeof panel.addEventListener!=='function')fail('NMResultsViewerPanelControls:InvalidPanel','Panel controls require one live Results Viewer workspace panel.');return panel;}

  function iconHtml(autoHidden){
    return autoHidden
      ? '<svg class="rvPanelControlModeIcon" viewBox="0 0 20 20" aria-hidden="true"><path d="M3.5 4.5h13v4h-13zM6 12.5h8M10 9.8v5.4M7.8 13l2.2 2.2 2.2-2.2"/></svg>'
      : '<svg class="rvPanelControlModeIcon" viewBox="0 0 20 20" aria-hidden="true"><path d="M3.5 4.5h13v4h-13zM6 13.5h8M7.8 11.3 10 9.1l2.2 2.2"/></svg>';
  }

  function bodyForPanel(panel){return panel&&panel.querySelector?panel.querySelector(':scope > .rvWorkspaceItemBody'):null;}
  function panelHead(panel){return panel&&panel.querySelector?panel.querySelector(':scope > .rvWorkspaceItemHead'):null;}
  function panelTools(panel){return panel&&panel.querySelector?panel.querySelector(':scope > .rvWorkspaceItemHead .rvPanelTools'):null;}

  function listen(state,target,type,listener,options){
    if(!target||typeof target.addEventListener!=='function')return false;
    target.addEventListener(type,listener,options);
    state.listeners.push({target,type,listener,options});
    return true;
  }

  function removeListeners(state){
    (state.listeners||[]).forEach(entry=>{try{entry.target.removeEventListener(entry.type,entry.listener,entry.options);}catch(_error){}});
    state.listeners=[];
  }

  function collectControls(panel){
    const body=bodyForPanel(panel);
    if(!body)return [];
    const candidates=Array.from(body.querySelectorAll(CONTROL_SELECTOR)).filter(node=>{
      if(!node||!node.isConnected||node.closest('.rvPanelControlsOverlayHost'))return false;
      const ancestor=node.parentElement&&node.parentElement.closest(CONTROL_SELECTOR);
      return !ancestor||ancestor===node;
    });
    return candidates.filter((node,index)=>!candidates.some((other,otherIndex)=>otherIndex!==index&&other.contains(node)));
  }

  function ensureHost(panel){
    let host=panel.querySelector(':scope > .rvPanelControlsOverlayHost');
    if(host)return host;
    host=global.document.createElement('div');
    host.className='rvPanelControlsOverlayHost';
    host.setAttribute('aria-hidden','true');
    const content=global.document.createElement('div');
    content.className='rvPanelControlsOverlayContent';
    host.appendChild(content);
    const head=panelHead(panel);
    if(head&&head.nextSibling)panel.insertBefore(host,head.nextSibling);else panel.appendChild(host);
    return host;
  }

  function overlayContent(state){return state.host&&state.host.querySelector('.rvPanelControlsOverlayContent');}

  function ensureFlowSlot(control){
    if(control.parentElement&&control.parentElement.classList.contains('rvPanelControlsFlowSlot'))return control.parentElement;
    const slot=global.document.createElement('div');
    slot.className='rvPanelControlsFlowSlot';
    control.parentNode.insertBefore(slot,control);
    slot.appendChild(control);
    return slot;
  }

  function controlHeight(entry){
    const control=entry&&entry.control;
    if(!control)return 0;
    const rect=control.getBoundingClientRect();
    const style=global.getComputedStyle(control);
    return Math.max(0,Math.ceil(Number(rect.height||control.scrollHeight||0)+(parseFloat(style.marginTop)||0)+(parseFloat(style.marginBottom)||0)));
  }

  function totalControlHeight(state){return (state.entries||[]).reduce((sum,entry)=>sum+controlHeight(entry),0);}
  function primaryPlot(panel){const nodes=Array.from(panel.querySelectorAll(PLOT_SELECTOR)).filter(node=>!node.closest('.rvPanelControlsOverlayHost'));return nodes.length?nodes[0]:null;}

  function capturePlotState(state,plot){
    if(!plot)return null;
    if(state.plotState&&state.plotState.node===plot)return state.plotState;
    const rect=plot.getBoundingClientRect();
    state.plotState={node:plot,baseHeight:Math.max(1,Math.round(Number(rect.height||0))),height:plot.style.height||'',minHeight:plot.style.minHeight||'',maxHeight:plot.style.maxHeight||''};
    return state.plotState;
  }

  function expandPlot(state){
    const plot=primaryPlot(state.panel);if(!plot)return;
    const plotState=capturePlotState(state,plot);
    const target=Math.max(1,plotState.baseHeight+Math.max(0,number(state.releaseHeight,0)));
    plot.style.height=`${target}px`;
    if(plot.classList.contains('rvFeatureRelationViewport')||plot.classList.contains('rvFeatureGraphViewport'))plot.style.minHeight=`${target}px`;
  }

  function restorePlot(state){
    const plotState=state.plotState;if(!plotState||!plotState.node)return;
    plotState.node.style.height=plotState.height;
    plotState.node.style.minHeight=plotState.minHeight;
    plotState.node.style.maxHeight=plotState.maxHeight;
    state.plotState=null;
  }

  function lifecycleIcon(state,name,fallback){const value=state.icons&&state.icons[name];return typeof value==='function'?String(value()):String(value==null?fallback:value);}

  function updateLifecycleButtons(state){
    const collapsed=state.panel.classList.contains('isMinimized'),maximized=state.panel.classList.contains('isMaximized');
    const min=state.panel.querySelector('.rvPanelMin');
    if(min){min.innerHTML=collapsed?lifecycleIcon(state,'restore','↗'):lifecycleIcon(state,'collapse','−');min.title=collapsed?'Expand panel':'Collapse panel';min.setAttribute('aria-label',min.title);min.setAttribute('aria-expanded',collapsed?'false':'true');}
    const max=state.panel.querySelector('.rvPanelMax');
    if(max){max.innerHTML=maximized?lifecycleIcon(state,'restore','↗'):lifecycleIcon(state,'maximize','□');max.title=maximized?'Restore panel':'Maximize panel';max.setAttribute('aria-label',max.title);max.setAttribute('aria-pressed',maximized?'true':'false');}
  }

  function updateButton(state){
    if(!state.toggle)return;
    const auto=state.mode===MODE_AUTO;
    state.toggle.innerHTML=iconHtml(auto);
    state.toggle.title=auto?'Pin panel controls':'Auto-hide panel controls';
    state.toggle.setAttribute('aria-label',auto?'Pin panel controls':'Auto-hide panel controls');
    state.toggle.setAttribute('aria-pressed',auto?'true':'false');
    state.toggle.setAttribute('aria-expanded',auto&&state.preview?'true':(!auto?'true':'false'));
  }

  function snapshot(panel){
    const state=STATES.get(panel);if(!state)return null;
    return Object.freeze({contractVersion:CONTRACT_VERSION,mode:state.mode,preview:!!state.preview,releaseHeight:Math.round(number(state.releaseHeight,0)),controlRegionCount:state.entries.length,hasToggle:!!state.toggle,minimized:panel.classList.contains('isMinimized'),maximized:panel.classList.contains('isMaximized'),hidden:panel.classList.contains('isHidden'),moving:!!state.moveStart,resizing:!!state.resizing});
  }

  function notifyStateWrite(state,reason){if(typeof state.onStateWrite==='function')state.onStateWrite({reason:String(reason||'panel_state'),panel:state.panel,snapshot:snapshot(state.panel)});}
  function finishLayoutChange(state,reason,options){
    const opts=options&&typeof options==='object'?options:{};
    const detail={reason:String(reason||'panel_layout'),panel:state.panel,mode:state.mode,releaseHeight:state.releaseHeight,snapshot:snapshot(state.panel)};
    if(opts.layout!==false&&typeof state.onLayoutChanged==='function')state.onLayoutChanged(detail);
    if(opts.notify!==false)notifyStateWrite(state,detail.reason);
  }

  function setPreviewState(state,visible){
    if(!state||state.mode!==MODE_AUTO)visible=false;
    state.preview=!!visible;
    state.panel.classList.toggle('rvPanelControlsPreview',state.preview);
    if(state.host)state.host.setAttribute('aria-hidden',state.preview?'false':'true');
    updateButton(state);
  }

  function cancelHide(state){if(state&&state.hideTimer){global.clearTimeout(state.hideTimer);state.hideTimer=0;}}
  function scheduleHide(state){
    if(!state||state.mode!==MODE_AUTO)return;
    cancelHide(state);
    state.hideTimer=global.setTimeout(()=>{
      state.hideTimer=0;
      const active=global.document.activeElement;
      if((state.host&&state.host.contains(active))||(state.head&&state.head.contains(active)))return;
      setPreviewState(state,false);
    },Math.max(0,number(state.hideDelay,DEFAULT_HIDE_DELAY)));
  }

  function reveal(panel,visible){const state=STATES.get(panel);if(!state)return false;cancelHide(state);setPreviewState(state,visible!==false);return state.preview;}
  function stopObservingControls(state){if(state.observer){try{state.observer.disconnect();}catch(_error){}}}
  function startObservingControls(state){const body=bodyForPanel(state.panel);if(!body||typeof global.MutationObserver!=='function')return;if(!state.observer)state.observer=new global.MutationObserver(()=>scheduleRefresh(state));state.observer.observe(body,{childList:true,subtree:true});}
  function mutate(state,callback){stopObservingControls(state);try{callback();}finally{if(!state.disposed)startObservingControls(state);}}

  function clearTransitions(state){
    if(state.animationTimer){global.clearTimeout(state.animationTimer);state.animationTimer=0;}
    (state.entries||[]).forEach(entry=>{if(entry.slot){entry.slot.style.transition='';entry.slot.classList.remove('isAnimating');}});
    const plot=primaryPlot(state.panel);if(plot)plot.style.transition='';
  }

  function applyAttachedMode(state){
    const content=overlayContent(state);if(!content)return;
    cancelHide(state);setPreviewState(state,false);
    mutate(state,()=>{
      if(state.mode===MODE_AUTO){
        state.releaseHeight=totalControlHeight(state);
        capturePlotState(state,primaryPlot(state.panel));
        state.entries.forEach(entry=>content.appendChild(entry.control));
        state.entries.forEach(entry=>{entry.slot.style.height='0px';entry.slot.style.overflow='hidden';});
        state.panel.classList.add('rvPanelControlsAutoHide');
        state.panel.style.setProperty('--rv-panel-controls-release-height',`${state.releaseHeight}px`);
        expandPlot(state);
      }else{
        state.entries.forEach(entry=>{entry.slot.appendChild(entry.control);entry.slot.style.height='';entry.slot.style.overflow='';});
        state.panel.classList.remove('rvPanelControlsAutoHide','rvPanelControlsPreview');
        state.panel.style.removeProperty('--rv-panel-controls-release-height');
        restorePlot(state);
        state.releaseHeight=0;
      }
    });
    updateButton(state);
  }

  function animateModeChange(state,next){
    const duration=reducedMotion()?0:Math.max(0,number(state.animationDuration,DEFAULT_DURATION));
    const plot=primaryPlot(state.panel),plotStart=Math.max(0,Math.round(Number(plot&&plot.getBoundingClientRect().height||0)));
    if(next===MODE_AUTO)capturePlotState(state,plot);
    const measurements=state.entries.map(entry=>Math.max(1,controlHeight(entry))),release=measurements.reduce((sum,value)=>sum+value,0);
    if(duration===0){state.mode=next;state.panel.dataset.rvPanelControlsMode=next;applyAttachedMode(state);finishLayoutChange(state,'panel_controls_mode');return;}
    cancelHide(state);setPreviewState(state,false);clearTransitions(state);
    mutate(state,()=>{
      const content=overlayContent(state);
      if(next===MODE_AUTO){
        state.entries.forEach((entry,index)=>{entry.slot.style.height=`${measurements[index]}px`;entry.slot.style.overflow='hidden';entry.slot.classList.add('isAnimating');content.appendChild(entry.control);});
        state.mode=MODE_AUTO;state.releaseHeight=release;state.panel.dataset.rvPanelControlsMode=MODE_AUTO;state.panel.classList.add('rvPanelControlsAutoHide');state.panel.style.setProperty('--rv-panel-controls-release-height',`${release}px`);
      }else{
        state.mode=MODE_PINNED;state.panel.dataset.rvPanelControlsMode=MODE_PINNED;state.entries.forEach(entry=>{entry.slot.style.height='0px';entry.slot.style.overflow='hidden';entry.slot.classList.add('isAnimating');entry.slot.appendChild(entry.control);});state.panel.classList.remove('rvPanelControlsAutoHide','rvPanelControlsPreview');state.panel.style.removeProperty('--rv-panel-controls-release-height');
      }
    });
    state.entries.forEach(entry=>entry.slot.style.transition=`height ${duration}ms cubic-bezier(.2,.7,.2,1)`);
    if(plot){plot.style.height=`${plotStart}px`;plot.style.transition=`height ${duration}ms cubic-bezier(.2,.7,.2,1)`;}
    updateButton(state);void state.panel.offsetHeight;
    requestFrame(()=>{
      if(state.disposed)return;
      state.entries.forEach((entry,index)=>entry.slot.style.height=next===MODE_AUTO?'0px':`${measurements[index]}px`);
      if(plot)plot.style.height=`${Math.max(1,plotStart+(next===MODE_AUTO?release:-release))}px`;
    });
    state.animationTimer=global.setTimeout(()=>{
      state.animationTimer=0;if(state.disposed)return;
      state.entries.forEach(entry=>{entry.slot.style.transition='';entry.slot.classList.remove('isAnimating');entry.slot.style.height=next===MODE_AUTO?'0px':'';entry.slot.style.overflow=next===MODE_AUTO?'hidden':'';});
      if(plot){plot.style.transition='';if(next===MODE_AUTO)expandPlot(state);else restorePlot(state);}
      if(next===MODE_PINNED)state.releaseHeight=0;
      finishLayoutChange(state,'panel_controls_mode');
    },duration+34);
  }

  function setMode(panel,mode,options){
    const state=STATES.get(panel);if(!state||!state.entries.length)return false;
    const next=String(mode||'')===MODE_AUTO?MODE_AUTO:MODE_PINNED;
    if(next===state.mode){applyAttachedMode(state);return true;}
    if(options&&options.animate===false){state.mode=next;panel.dataset.rvPanelControlsMode=next;applyAttachedMode(state);finishLayoutChange(state,'panel_controls_mode',options);return true;}
    animateModeChange(state,next);return true;
  }

  function panelRect(panel){return {x:parseFloat(panel.style.left||'0'),y:parseFloat(panel.style.top||'0'),w:parseFloat(panel.style.width||panel.offsetWidth||'0'),h:parseFloat(panel.style.height||panel.offsetHeight||'0')};}
  function validRect(rect){return !!rect&&[rect.x,rect.y,rect.w,rect.h].every(Number.isFinite);}
  function applyRect(panel,rect){if(!validRect(rect))return false;panel.style.left=`${rect.x}px`;panel.style.top=`${rect.y}px`;panel.style.width=`${rect.w}px`;panel.style.height=`${rect.h}px`;return true;}
  const RESIZE_DIRECTIONS=Object.freeze(['n','ne','e','se','s','sw','w','nw']);
  function ensureResizeHandles(panel){
    const handles=[];
    RESIZE_DIRECTIONS.forEach(edge=>{
      let handle=panel.querySelector(`:scope > .rvPanelResizeHandle[data-resize-edge="${edge}"]`);
      if(!handle){handle=global.document.createElement('span');handle.className='rvPanelResizeHandle';handle.dataset.resizeEdge=edge;handle.setAttribute('aria-hidden','true');panel.appendChild(handle);}
      handles.push(handle);
    });
    return handles;
  }
  function panelMinimumSize(panel){
    const style=global.getComputedStyle?global.getComputedStyle(panel):null;
    return {w:Math.max(80,number(style&&parseFloat(style.minWidth),300)),h:Math.max(40,number(style&&parseFloat(style.minHeight),120))};
  }
  function resizedRect(start,event,panel){
    const edge=String(start&&start.edge||''),base=start&&start.rect,minimum=panelMinimumSize(panel);
    if(!validRect(base)||!RESIZE_DIRECTIONS.includes(edge))return null;
    const dx=number(event&&event.clientX,start.pointerX)-start.pointerX,dy=number(event&&event.clientY,start.pointerY)-start.pointerY;
    let x=base.x,y=base.y,w=base.w,h=base.h;
    if(edge.includes('e'))w=Math.max(minimum.w,base.w+dx);
    if(edge.includes('s'))h=Math.max(minimum.h,base.h+dy);
    if(edge.includes('w')){x=base.x+dx;w=base.w-dx;if(x<0){w+=x;x=0;}if(w<minimum.w){x=Math.max(0,base.x+base.w-minimum.w);w=minimum.w;}}
    if(edge.includes('n')){y=base.y+dy;h=base.h-dy;if(y<0){h+=y;y=0;}if(h<minimum.h){y=Math.max(0,base.y+base.h-minimum.h);h=minimum.h;}}
    return {x,y,w,h};
  }
  function autoLayout(state){return typeof state.isAutoLayout==='function'?!!state.isAutoLayout(state.panel):false;}
  function boundsElement(state){return typeof state.getBoundsElement==='function'?state.getBoundsElement(state.panel):(state.boundsElement||state.panel.parentElement);}

  function setCollapsed(panel,collapsed,options){
    const state=STATES.get(panel);if(!state)return false;
    const next=!!collapsed,current=panel.classList.contains('isMinimized');
    if(next===current){updateLifecycleButtons(state);return true;}
    panel.classList.toggle('isMinimized',next);updateLifecycleButtons(state);
    finishLayoutChange(state,next?'panel_collapse':'panel_expand',options);
    return true;
  }

  function setMaximized(panel,maximized,options){
    const state=STATES.get(panel);if(!state)return false;
    const next=!!maximized,current=panel.classList.contains('isMaximized');
    if(next===current){updateLifecycleButtons(state);return true;}
    const dashboard=autoLayout(state);
    if(next){
      if(!dashboard)state.previousRect=panelRect(panel);
      panel.classList.remove('isMinimized');panel.classList.add('isMaximized');
      if(!dashboard){const bounds=boundsElement(state),width=Math.max(600,number(bounds&&bounds.clientWidth,620)-20),height=Math.max(420,number(bounds&&bounds.clientHeight,440)-20);applyRect(panel,{x:10,y:10,w:width,h:height});}
    }else{
      panel.classList.remove('isMaximized');
      if(!dashboard&&validRect(state.previousRect))applyRect(panel,state.previousRect);
      state.previousRect=null;
    }
    updateLifecycleButtons(state);
    finishLayoutChange(state,next?'panel_maximize':'panel_restore',options);
    return true;
  }

  function notifyInteraction(state,kind,active){if(typeof state.onInteractionState==='function')state.onInteractionState({panel:state.panel,kind,active:!!active,snapshot:snapshot(state.panel)});}
  function requireManualMode(state,reason){if(!autoLayout(state))return;if(typeof state.enterManualMode!=='function')fail('NMResultsViewerPanelControls:MissingManualModeAdapter','Moving or resizing a dashboard panel requires an explicit manual-layout adapter.');state.enterManualMode({panel:state.panel,reason:String(reason||'panel_interaction')});}
  function emitGeometry(state,reason,phase){if(typeof state.onGeometryChanged==='function')state.onGeometryChanged({panel:state.panel,reason:String(reason),phase:String(phase||'final'),snapshot:snapshot(state.panel)});}

  function finishMove(state,event,cancelled){
    if(!state.moveStart)return;
    state.moveStart=null;notifyInteraction(state,'move',false);
    const handle=state.moveHandle;
    if(handle&&event&&event.pointerId!==undefined&&typeof handle.releasePointerCapture==='function')try{handle.releasePointerCapture(event.pointerId);}catch(_error){}
    emitGeometry(state,'panel_move',cancelled?'cancel':'final');
    if(!cancelled)notifyStateWrite(state,'panel_move');
  }

  function finishResize(state,cancelled){
    if(!state.resizing)return;
    if(cancelled&&state.resizeStart&&validRect(state.resizeStart.rect))applyRect(state.panel,state.resizeStart.rect);
    const handle=state.resizeHandle,pointerId=state.resizePointerId;
    if(handle&&pointerId!==null&&pointerId!==undefined&&typeof handle.releasePointerCapture==='function')try{handle.releasePointerCapture(pointerId);}catch(_error){}
    state.resizing=false;state.resizeStart=null;state.resizeHandle=null;state.resizePointerId=null;notifyInteraction(state,'resize',false);
    emitGeometry(state,'panel_resize',cancelled?'cancel':'final');
    if(!cancelled)notifyStateWrite(state,'panel_resize');
  }

  function scheduleResize(state,source){
    state.resizeSource=String(source||'observer');
    if(state.resizeFrame)cancelFrame(state.resizeFrame);
    state.resizeFrame=requestFrame(()=>{
      state.resizeFrame=0;
      if(state.disposed||!state.panel.isConnected)return;
      if(typeof state.onResize==='function')state.onResize({panel:state.panel,source:state.resizeSource,resizing:!!state.resizing,moving:!!state.moveStart,snapshot:snapshot(state.panel)});
    });
  }

  function bindPanelLifecycle(state){
    const panel=state.panel,head=state.head,host=state.host;
    const min=panel.querySelector('.rvPanelMin'),max=panel.querySelector('.rvPanelMax'),close=panel.querySelector('.rvPanelClose'),move=panel.querySelector('.rvPanelMove');
    if(min)listen(state,min,'click',event=>{event.preventDefault();event.stopPropagation();setCollapsed(panel,!panel.classList.contains('isMinimized'));});
    if(max)listen(state,max,'click',event=>{event.preventDefault();event.stopPropagation();setMaximized(panel,!panel.classList.contains('isMaximized'));});
    if(close)listen(state,close,'click',event=>{event.preventDefault();event.stopPropagation();const before=snapshot(panel);if(typeof state.onBeforeClose==='function')state.onBeforeClose({panel,snapshot:before});unbind(panel,{restore:false});if(panel.isConnected)panel.remove();if(typeof state.onClose==='function')state.onClose({panel,snapshot:before});});

    if(move){
      state.moveHandle=move;
      listen(state,move,'pointerdown',event=>{
        requireManualMode(state,'panel_move');
        state.moveStart={x:event.clientX,y:event.clientY,left:parseFloat(panel.style.left||'0'),top:parseFloat(panel.style.top||'0')};
        notifyInteraction(state,'move',true);
        if(typeof move.setPointerCapture==='function')move.setPointerCapture(event.pointerId);
      });
      listen(state,move,'pointermove',event=>{
        if(!state.moveStart)return;
        const bounds=boundsElement(state),bw=number(bounds&&bounds.clientWidth,1200),bh=Math.max(number(bounds&&bounds.clientHeight,900),900),left=Math.max(0,Math.min(bw-120,state.moveStart.left+event.clientX-state.moveStart.x)),top=Math.max(0,Math.min(bh-40,state.moveStart.top+event.clientY-state.moveStart.y));
        panel.style.left=`${left}px`;panel.style.top=`${top}px`;emitGeometry(state,'panel_move','preview');
      });
      listen(state,move,'pointerup',event=>finishMove(state,event,false));
      listen(state,move,'pointercancel',event=>finishMove(state,event,true));
    }

    state.resizeHandles=ensureResizeHandles(panel);
    state.resizeHandles.forEach(handle=>{
      listen(state,handle,'pointerdown',event=>{
        event.preventDefault();event.stopPropagation();requireManualMode(state,'panel_resize');
        const rect=panelRect(panel),edge=String(handle.dataset.resizeEdge||'');if(!validRect(rect)||!RESIZE_DIRECTIONS.includes(edge))return;
        state.resizeStart={edge,rect,pointerX:event.clientX,pointerY:event.clientY};state.resizeHandle=handle;state.resizePointerId=event.pointerId;state.resizing=true;notifyInteraction(state,'resize',true);
        if(typeof handle.setPointerCapture==='function')handle.setPointerCapture(event.pointerId);
      });
      listen(state,handle,'pointerup',event=>{if(state.resizeHandle===handle)finishResize(state,false);});
      listen(state,handle,'pointercancel',event=>{if(state.resizeHandle===handle)finishResize(state,true);});
    });
    listen(state,global,'pointermove',event=>{
      if(!state.resizing||!state.resizeStart)return;
      const rect=resizedRect(state.resizeStart,event,panel);if(!rect)return;applyRect(panel,rect);emitGeometry(state,'panel_resize','preview');
    });
    listen(state,global,'pointerup',()=>finishResize(state,false));
    listen(state,global,'pointercancel',()=>finishResize(state,true));

    listen(state,head,'mouseenter',()=>{if(state.mode===MODE_AUTO)reveal(panel,true);});
    listen(state,head,'mouseleave',()=>scheduleHide(state));
    listen(state,head,'focusin',()=>{if(state.mode===MODE_AUTO)reveal(panel,true);});
    listen(state,head,'focusout',event=>{if(!head.contains(event.relatedTarget)&&!host.contains(event.relatedTarget))scheduleHide(state);});
    listen(state,host,'mouseenter',()=>cancelHide(state));
    listen(state,host,'mouseleave',()=>scheduleHide(state));
    listen(state,host,'focusin',()=>{if(state.mode===MODE_AUTO)reveal(panel,true);});
    listen(state,host,'focusout',event=>{if(!host.contains(event.relatedTarget)&&!head.contains(event.relatedTarget))scheduleHide(state);});
    const escape=event=>{if(event.key==='Escape'&&state.mode===MODE_AUTO){event.preventDefault();setPreviewState(state,false);if(state.toggle)state.toggle.focus({preventScroll:true});}};
    listen(state,head,'keydown',escape);listen(state,host,'keydown',escape);
    listen(state,head,'pointerup',event=>{if(state.mode===MODE_AUTO&&event.pointerType==='touch'&&!(event.target&&event.target.closest&&event.target.closest('button')))setPreviewState(state,!state.preview);});

    if(typeof global.ResizeObserver==='function'){
      state.resizeObserver=new global.ResizeObserver(()=>scheduleResize(state,'observer'));
      state.resizeObserver.observe(panel);
    }else if(state.includeWindowResize!==false){
      listen(state,global,'resize',()=>scheduleResize(state,'window'));
    }
  }

  function ensureToggle(state){
    const tools=panelTools(state.panel);if(!tools)return null;
    let button=tools.querySelector('.rvPanelControlsToggle');
    if(!button){
      button=global.document.createElement('button');button.type='button';button.className='rvPanelControlsToggle';
      const anchor=tools.querySelector('.rvPanelMin,.rvPanelMax,.rvPanelClose');tools.insertBefore(button,anchor||null);
      listen(state,button,'click',event=>{event.preventDefault();event.stopPropagation();setMode(state.panel,state.mode===MODE_AUTO?MODE_PINNED:MODE_AUTO);if(state.mode===MODE_AUTO&&typeof button.blur==='function')button.blur();});
    }
    state.toggle=button;updateButton(state);return button;
  }

  function removeToggle(state){if(state.toggle){state.toggle.remove();state.toggle=null;}}

  function refreshControls(state){
    if(!state||state.disposed||!state.panel.isConnected)return;
    const controls=collectControls(state.panel);
    if(!controls.length){
      const existingInOverlay=state.entries.length&&state.entries.every(entry=>state.host.contains(entry.control)&&entry.slot&&entry.slot.isConnected);
      if(existingInOverlay)return;
      mutate(state,()=>{
        (state.entries||[]).forEach(entry=>{if(entry.control&&entry.control.isConnected)entry.control.remove();if(entry.slot&&entry.slot.isConnected)entry.slot.remove();});
        const content=overlayContent(state);if(content)content.replaceChildren();
      });
      state.entries=[];state.mode=MODE_PINNED;state.releaseHeight=0;state.panel.dataset.rvPanelControlsMode=MODE_PINNED;state.panel.classList.remove('rvPanelControlsAutoHide','rvPanelControlsPreview');state.panel.style.removeProperty('--rv-panel-controls-release-height');restorePlot(state);removeToggle(state);return;
    }
    const same=controls.length===state.entries.length&&controls.every((control,index)=>state.entries[index]&&state.entries[index].control===control);
    if(same){ensureToggle(state);applyAttachedMode(state);return;}
    mutate(state,()=>{
      (state.entries||[]).forEach(entry=>{if(entry.control&&entry.control.isConnected&&state.host.contains(entry.control))entry.control.remove();if(entry.slot&&entry.slot.isConnected&&!entry.slot.childNodes.length)entry.slot.remove();});
      state.entries=controls.map(control=>({control,slot:ensureFlowSlot(control)}));
    });
    ensureToggle(state);applyAttachedMode(state);
  }

  function scheduleRefresh(state){if(state.disposed||state.refreshRaf)return;state.refreshRaf=requestFrame(()=>{state.refreshRaf=0;refreshControls(state);});}

  function updateOptions(state,options){
    const opts=options&&typeof options==='object'?options:{};
    state.animationDuration=number(opts.animationDuration,state.animationDuration==null?DEFAULT_DURATION:state.animationDuration);
    state.hideDelay=number(opts.hideDelay,state.hideDelay==null?DEFAULT_HIDE_DELAY:state.hideDelay);
    state.resizeEdge=number(opts.resizeEdge,state.resizeEdge==null?18:state.resizeEdge);
    state.includeWindowResize=opts.includeWindowResize!==false;
    state.icons=opts.icons||state.icons||{};
    ['onLayoutChanged','onStateWrite','onResize','onGeometryChanged','onInteractionState','onBeforeClose','onClose','isAutoLayout','enterManualMode','getBoundsElement'].forEach(name=>{if(Object.prototype.hasOwnProperty.call(opts,name))state[name]=opts[name];});
    if(Object.prototype.hasOwnProperty.call(opts,'boundsElement'))state.boundsElement=opts.boundsElement;
  }

  /** Mount or refresh one Results Viewer workspace panel lifecycle. */
  function bind(panel,options){
    requirePanel(panel);
    let state=STATES.get(panel);
    if(!state){
      const head=panelHead(panel);if(!head)fail('NMResultsViewerPanelControls:MissingHeader','Panel lifecycle requires a direct workspace-panel header.');
      state={panel,head,host:ensureHost(panel),entries:[],mode:String(panel.dataset.rvPanelControlsMode||MODE_PINNED)===MODE_AUTO?MODE_AUTO:MODE_PINNED,preview:false,releaseHeight:0,hideTimer:0,observer:null,resizeObserver:null,refreshRaf:0,resizeFrame:0,animationTimer:0,listeners:[],moveStart:null,resizing:false,resizeStart:null,resizeHandle:null,resizePointerId:null,resizeHandles:[],previousRect:null,disposed:false};
      STATES.set(panel,state);updateOptions(state,options);bindPanelLifecycle(state);startObservingControls(state);
    }else updateOptions(state,options);
    panel.dataset.rvPanelControlsMode=state.mode;updateLifecycleButtons(state);refreshControls(state);scheduleResize(state,'mount');return snapshot(panel);
  }

  function restoreControlFlow(state){
    const content=overlayContent(state);
    mutate(state,()=>{
      (state.entries||[]).forEach(entry=>{
        const slot=entry.slot,control=entry.control;
        if(slot&&slot.isConnected&&control){slot.parentNode.insertBefore(control,slot);slot.remove();}
      });
      if(content)content.replaceChildren();
    });
    state.entries=[];state.panel.classList.remove('rvPanelControlsAutoHide','rvPanelControlsPreview');state.panel.style.removeProperty('--rv-panel-controls-release-height');restorePlot(state);state.releaseHeight=0;
  }

  /** Dispose every listener, observer, timer and temporary DOM host owned by one panel. */
  function unbind(panel,options){
    const state=STATES.get(panel);if(!state)return false;
    const opts=options&&typeof options==='object'?options:{};state.disposed=true;
    cancelHide(state);clearTransitions(state);stopObservingControls(state);
    if(state.resizeObserver)state.resizeObserver.disconnect();
    if(state.refreshRaf)cancelFrame(state.refreshRaf);if(state.resizeFrame)cancelFrame(state.resizeFrame);
    if(opts.restore!==false)restoreControlFlow(state);
    removeToggle(state);removeListeners(state);
    (state.resizeHandles||[]).forEach(handle=>{if(handle&&handle.isConnected)handle.remove();});state.resizeHandles=[];
    if(state.host&&state.host.isConnected)state.host.remove();
    STATES.delete(panel);return true;
  }

  global.NMResultsViewerPanelControls=Object.freeze({CONTRACT_VERSION,MODE_PINNED,MODE_AUTO,bind,unbind,setMode,setCollapsed,setMaximized,reveal,snapshot,_test:Object.freeze({panelError,panelRect,validRect,applyRect,resizedRect,resizeDirections:RESIZE_DIRECTIONS})});
})(typeof window!=='undefined'?window:globalThis);
