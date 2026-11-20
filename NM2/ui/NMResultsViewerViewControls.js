(function(){
  'use strict';

  const {clamp,text,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  /**
   * NMResultsViewerViewControls
   *
   * Pathway-neutral markup and DOM-event owner for discrete Results Viewer
   * view/navigation controls. It translates controls into canonical G3C
   * commands but owns no camera, matrix, geometry, clipping, renderer, or
   * viewer-state semantics. Pathway adapters execute every command.
   *
   * Contract: NM-RESULTS-VIEWER-VIEW-CONTROLS-V1
   * Failure policy: malformed controls, undeclared capabilities, unsupported
   * command details, and missing host dispatch fail explicitly.
   */

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-VIEW-CONTROLS-V1';
  const TOOLBAR_COMMANDS=Object.freeze(['view.zoom','view.fit','view.reset']);
  const PRESETS=Object.freeze(['left','right','anterior','posterior','superior','inferior']);
  const CLIPPING_AXES=Object.freeze({none:Object.freeze([]),sagittal:Object.freeze(['x']),coronal:Object.freeze(['y']),axial:Object.freeze(['z']),trihedral:Object.freeze(['x','y','z'])});

  function fail(code,message){
    const error=new Error(String(message||'Results Viewer view-control failure.'));
    error.name='NMResultsViewerViewControlsError';
    error.code=String(code||'NMResultsViewerViewControls:Failure');
    throw error;
  }
  function arr(value){return Array.isArray(value)?value:[];}
  function finite(value,fallback){return Number.isFinite(Number(value))?Number(value):fallback;}
  function fmt(value,digits){return finite(value,0).toFixed(digits).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');}
  function atlasDescriptorControlsHtml(runtime,state,esc){
    if(!runtime.payload.capabilities.atlasFileSelection||runtime.payload.capabilities.sourceDomain!=='volume')return '';
    const selected=runtime.payload.selectedAtlas,info=selected.available?selected.descriptorInfo:null,available=Boolean(info&&info.file),candidates=arr(info?info.candidates:[]);
    const delimiterOptions=['auto','tab','comma','semicolon','pipe','whitespace'].map(v=>`<option value="${v}"${state.volumeAtlasDelimiter===v?' selected':''}>${v==='auto'?'auto (detected: '+text(info?info.delimiter:'—')+')':v}</option>`).join('');
    const nameOptions=`<option value=""${!state.volumeAtlasNameColumn?' selected':''}>auto (${esc(info?info.nameColumn:'detect')})</option>`+arr(info?info.columns:[]).map(name=>`<option value="${esc(name)}"${state.volumeAtlasNameColumn===name?' selected':''}>${esc(name)}</option>`).join('');
    const descriptorOptions=candidates.map(file=>`<option value="${esc(file)}"${info.file===file?' selected':''}>${esc(file.split(/[\\/]/).pop())}</option>`).join('');
    const descriptorChoice=candidates.length>1?`<label>ROI description file<select data-imaging-atlas-descriptor-file><option value=""${!available?' selected':''}>Choose sidecar…</option>${descriptorOptions}</select></label>`:'';
    return `${descriptorChoice}<label>Delimiter<select data-imaging-atlas-delimiter${available?'':' disabled'}>${delimiterOptions}</select></label><label>ROI name column<select data-imaging-atlas-name-column${available?'':' disabled'}>${nameOptions}</select></label>`;
  }
  function closestWithin(root,target,selector){if(!target||typeof target.closest!=='function')return null;const node=target.closest(selector);return node&&root.contains(node)?node:null;}
  function disabledControl(target){return !!(target&&(target.disabled===true||(typeof target.getAttribute==='function'&&target.getAttribute('aria-disabled')==='true')));}
  function hostApi(){const api=window.NMResultsViewerControlHost;if(!api||typeof api.commandCapability!=='function')fail('NMResultsViewerViewControls:MissingHost','The pathway-neutral Results Viewer control host is unavailable.');return api;}
  function commandCapability(command){return hostApi().commandCapability(command);}
  function tooltipAttributes(item,escapeFn){if(!item||!item.tooltip)return '';if(typeof item.tooltipAttributes==='function')return text(item.tooltipAttributes(item.tooltip));return ` title="${escapeFn(item.tooltip)}"`;}
  function canonicalToolbarAttributes(item){
    const command=text(item&&item.command);if(!TOOLBAR_COMMANDS.includes(command))fail('NMResultsViewerViewControls:UnsupportedToolbarCommand',`Unsupported view-toolbar command: ${command||'(empty)'}.`);
    if(command==='view.zoom'){
      const direction=text(item&&item.direction);if(!['in','out'].includes(direction))fail('NMResultsViewerViewControls:InvalidZoomDirection',`View zoom requires direction in or out, not ${direction||'(empty)'}.`);
      return `data-rv-view-command="zoom" data-rv-view-direction="${direction}"`;
    }
    return `data-rv-view-command="${command==='view.fit'?'fit':'reset'}"`;
  }

  /** Render one generic zoom/fit/reset control group. */
  function toolbarHtml(options){
    const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,items=arr(cfg.items);
    if(!items.length)fail('NMResultsViewerViewControls:MissingToolbarItems','A view toolbar requires at least one command item.');
    const buttons=items.map(item=>{
      const canonical=canonicalToolbarAttributes(item),legacy=text(item&&item.legacyAttribute),disabled=item&&item.disabled?' disabled':'',aria=item&&item.ariaLabel?` aria-label="${esc(item.ariaLabel)}"`:'',tip=tooltipAttributes(item,esc);
      return `<button type="button" ${canonical}${legacy?' '+legacy:''}${tip}${disabled}${aria}>${esc(item&&item.label||'')}</button>`;
    }).join('');
    return `<div class="rvImagingControlGroup rvImagingZoomControls${cfg.className?' '+esc(cfg.className):''}"${cfg.ariaLabel?` aria-label="${esc(cfg.ariaLabel)}"`:''}><span class="rvImagingControlGroupLabel">${esc(cfg.label||'View')}</span>${buttons}${cfg.trailingHtml||''}</div>`;
  }

  /** Render the canonical six camera-preset buttons. */
  function cameraPresetButtonsHtml(options){
    const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,selected=text(cfg.selectedPreset),legacyAttributeName=text(cfg.legacyAttributeName||'');
    return PRESETS.map(preset=>`<button type="button" data-rv-camera-preset="${preset}"${legacyAttributeName?` ${legacyAttributeName}="${preset}"`:''}${selected===preset?' class="isActive"':''}>${esc(preset[0].toUpperCase()+preset.slice(1))}</button>`).join('');
  }

  function clippingAxes(mode){return Array.from(CLIPPING_AXES[text(mode)]||CLIPPING_AXES.none);}

  /** Render the one shared clipping/cut-away panel for 3-D adapters that expose volumetric half-space clipping. */
  function clippingHtml(options){
    const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,c=cfg.state||{},bounds=cfg.bounds||{},lo=arr(bounds.min),hi=arr(bounds.max),position=arr(c.positionWorldMm),hasSelection=!!cfg.hasSelection;
    const mode=['sagittal','coronal','axial','trihedral'].includes(text(c.mode))?text(c.mode):'none',axisRows=[['x','Sagittal position',[['negative','Keep left (−X)'],['positive','Keep right (+X)']]],['y','Coronal position',[['negative','Keep posterior (−Y)'],['positive','Keep anterior (+Y)']]],['z','Axial position',[['negative','Keep inferior (−Z)'],['positive','Keep superior (+Z)']]]].map((item,index)=>{
      const axis=item[0],keep=text(c['keep'+axis.toUpperCase()])==='positive'?'positive':'negative',value=finite(position[index],0),minimum=finite(lo[index],-1),maximum=finite(hi[index],1),optionsHtml=item[2].map(option=>`<option value="${option[0]}"${keep===option[0]?' selected':''}>${esc(option[1])}</option>`).join('');
      return `<div class="rvImaging3DClipAxis" data-rv-clipping-axis="${axis}" data-imaging-3d-clip-axis="${axis}"><label>${esc(item[1])}<input type="range" min="${esc(minimum)}" max="${esc(maximum)}" step="0.1" value="${esc(value)}" data-rv-clipping-position="${axis}" data-imaging-3d-clip-position="${axis}"><output data-rv-clipping-position-output="${axis}" data-imaging-3d-clip-position-output="${axis}">${esc(fmt(value,2))} mm</output></label><label>Visible side<select data-rv-clipping-keep="${axis}" data-imaging-3d-clip-keep="${axis}">${optionsHtml}</select></label></div>`;
    }).join('');
    const tip=cfg.tooltip?` title="${esc(cfg.tooltip)}"`:'';
    return `<details class="rvImaging3DSection rvImaging3DClipping rvClippingControls" data-rv-clipping-controls open${tip}><summary>${esc(cfg.heading||'Clipping / cut-away')}</summary><label class="rvImaging3DClipModeRow">Mode<select data-rv-clipping-mode data-imaging-3d-clip-mode><option value="none"${mode==='none'?' selected':''}>None</option><option value="sagittal"${mode==='sagittal'?' selected':''}>Sagittal</option><option value="coronal"${mode==='coronal'?' selected':''}>Coronal</option><option value="axial"${mode==='axial'?' selected':''}>Axial</option><option value="trihedral"${mode==='trihedral'?' selected':''}>Trihedral</option></select></label><fieldset class="rvImaging3DClipGroup rvImaging3DClipPositionGroup"><legend>Cut position</legend><label class="rvImagingCheck"${cfg.linkTooltip?` title="${esc(cfg.linkTooltip)}"`:''}><input type="checkbox" data-rv-clipping-linked data-imaging-3d-clip-linked${c.linkedToSelection?' checked':''}${hasSelection?'':' disabled'}> Link cut position to selected voxel</label><button type="button" data-rv-clipping-use-selection data-imaging-3d-clip-use-selection${hasSelection&&mode!=='none'&&!c.linkedToSelection?'':' disabled'}${cfg.selectionTooltip?` title="${esc(cfg.selectionTooltip)}"`:''}>Move to selected voxel</button>${axisRows}</fieldset></details>`;
  }

  function syncClipping(root,state,hasSelection){
    const c=state||{},active=new Set(clippingAxes(c.mode)),enabled=text(c.mode)!=='none',linked=enabled&&!!c.linkedToSelection,pos=arr(c.positionWorldMm);['x','y','z'].forEach((axis,i)=>{const box=root.querySelector(`[data-rv-clipping-axis="${axis}"]`),input=root.querySelector(`[data-rv-clipping-position="${axis}"]`),keep=root.querySelector(`[data-rv-clipping-keep="${axis}"]`),out=root.querySelector(`[data-rv-clipping-position-output="${axis}"]`);if(box)box.hidden=!active.has(axis);if(input){input.value=String(finite(pos[i],0));input.disabled=!enabled||linked;}if(keep)keep.disabled=!enabled;if(out)out.textContent=`${fmt(pos[i],1)} mm`;});const link=root.querySelector('[data-rv-clipping-linked]'),move=root.querySelector('[data-rv-clipping-use-selection]');if(link){link.disabled=!enabled||!hasSelection;link.checked=!!c.linkedToSelection;}if(move)move.disabled=!enabled||!hasSelection||linked;
  }

  /** Shared feature-projection controls. The adapter owns projection semantics; this authority owns presentation and event phases. */
  function featureProjectionHtml(options){
    const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,s=cfg.state||{},limits=cfg.limits||{},tip=key=>{const value=text(cfg.tooltips&&cfg.tooltips[key]);return value?(typeof cfg.tooltipAttributes==='function'?text(cfg.tooltipAttributes(key,value)):` title="${esc(value)}"`):'';},retention=100*clamp(finite(s.supportRetention,.88),finite(limits.retentionMin,.5),finite(limits.retentionMax,.98)),selectivity=clamp(finite(s.supportSelectivity,24),finite(limits.selectivityMin,4),finite(limits.selectivityMax,48)),fwhm=clamp(finite(s.supportFwhmMm,8),1,24),depth=clamp(finite(s.depthMm,0),0,Math.max(0,finite(s.maxDepthMm,12))),range=(field,label,min,max,step,value,suffix,legacy,key)=>`<label class="rvImaging3DProjectionSlider"${tip(key)}><span>${label}</span><input type="range" min="${min}" max="${max}" step="${step}" value="${esc(value)}" data-rv-feature-projection="${field}" ${legacy}><output data-rv-feature-projection-output="${field}" ${legacy}-output>${esc(value)}${suffix}</output></label>`;
    return `<div class="rvImaging3DProjectionControls rvFeatureProjectionControls" data-rv-feature-projection-controls data-imaging-3d-mode-controls="surface_projection"${cfg.hidden?' hidden':''}>${range('depthMm','Projection depth',0,esc(finite(s.maxDepthMm,12)),.1,fmt(depth,1),' mm','data-imaging-3d-depth','depth')}<div class="rvImaging3DProductionProjectionSummary"${tip('summary')}><span>Production projection</span><b>${esc(cfg.summary||'Continuous signed trilinear · TFLSE alpha')}</b></div><div class="rvImaging3DLocalSupportControls" data-imaging-3d-local-support-field>${range('supportRetention','Support retention',100*finite(limits.retentionMin,.5),100*finite(limits.retentionMax,.98),.5,fmt(retention,1),'%','data-imaging-3d-local-support-retention','retention')}<button type="button" class="rvImaging3DSupportDistributionButton" data-rv-feature-projection-action="inspectSupport" data-imaging-3d-local-support-distribution${tip('inspect')}>Inspect support distribution…</button><details class="rvImaging3DProjectionAdvanced"><summary>Advanced transfer and scale</summary>${range('supportSelectivity','Transition steepness',finite(limits.selectivityMin,4),finite(limits.selectivityMax,48),1,fmt(selectivity,0),'','data-imaging-3d-local-support-selectivity','selectivity')}${range('supportFwhmMm','Local-support FWHM',1,24,.5,fmt(fwhm,1),' mm','data-imaging-3d-local-support-fwhm','fwhm')}</details></div></div>`;
  }
  function bindDeferredRange(input,options){
    const cfg=options||{};if(!input)fail('NMResultsViewerViewControls:MissingDeferredRange','Deferred range binding requires an input.');let timer=0,last='';const value=()=>typeof cfg.value==='function'?cfg.value(input):finite(input.value,0),commit=force=>{if(timer){clearTimeout(timer);timer=0;}const current=value(),key=String(current);if(!force&&key===last)return;last=key;if(typeof cfg.commit==='function')cfg.commit(current);},preview=()=>{const current=value();if(typeof cfg.preview==='function')cfg.preview(current);if(timer)clearTimeout(timer);timer=setTimeout(()=>{timer=0;commit(false);},finite(cfg.delay,350));},immediate=()=>commit(true),key=event=>{if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','PageUp','PageDown','Home','End','Enter'].includes(event.key))immediate();};input.addEventListener('input',preview);['pointerup','pointercancel','change','blur'].forEach(type=>input.addEventListener(type,immediate));input.addEventListener('keyup',key);return ()=>{if(timer)clearTimeout(timer);input.removeEventListener('input',preview);['pointerup','pointercancel','change','blur'].forEach(type=>input.removeEventListener(type,immediate));input.removeEventListener('keyup',key);};
  }
  function bindFeatureProjection(root,options){
    const cfg=options,region=root&&(root.matches&&root.matches('[data-rv-feature-projection-controls]')?root:root.querySelector('[data-rv-feature-projection-controls]'));if(!region)fail('NMResultsViewerViewControls:MissingFeatureProjection','The shared feature-projection control region is missing.');if(typeof cfg.onChange!=='function')fail('NMResultsViewerViewControls:MissingFeatureProjectionHandler','Feature-projection controls require one onChange handler.');const cleanups=[],read=(field,input)=>field==='supportRetention'?clamp(finite(input.value,88)/100,0,1):Math.max(0,finite(input.value,0));['depthMm','supportRetention','supportSelectivity'].forEach(field=>{const input=region.querySelector(`[data-rv-feature-projection="${field}"]`);if(!input)fail('NMResultsViewerViewControls:MissingFeatureProjectionField',`Feature-projection control ${field} is missing.`);const emit=phase=>{const value=read(field,input);if(field==='depthMm')input.nextElementSibling.textContent=`${fmt(value,1)} mm`;cfg.onChange({field,value,phase});},preview=()=>emit('preview'),commit=()=>emit('commit');input.addEventListener('input',preview);input.addEventListener('change',commit);cleanups.push(()=>{input.removeEventListener('input',preview);input.removeEventListener('change',commit);});});const fwhm=region.querySelector('[data-rv-feature-projection="supportFwhmMm"]');cleanups.push(bindDeferredRange(fwhm,{value:input=>read('supportFwhmMm',input),preview:value=>cfg.onChange({field:'supportFwhmMm',value,phase:'preview'}),commit:value=>cfg.onChange({field:'supportFwhmMm',value,phase:'commit'})}));const inspect=region.querySelector('[data-rv-feature-projection-action="inspectSupport"]');if(inspect){const click=()=>{if(typeof cfg.onInspectSupport!=='function')fail('NMResultsViewerViewControls:MissingFeatureProjectionInspector','Feature-projection support inspection is unavailable.');cfg.onInspectSupport();};inspect.addEventListener('click',click);cleanups.push(()=>inspect.removeEventListener('click',click));}return {dispose:()=>cleanups.splice(0).forEach(fn=>fn())};
  }

  /** Shared 3-D view presets plus the montage/video actions used by every 3-D adapter. */
  function threeDAdvancedActionsHtml(options){const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml;return `<div class="rvImagingAdvancedViewActions"><button type="button" class="rvImaging3DMontageButton" data-rv-3d-presentation="montage" title="Open a multi-view montage without changing the current 3-D scene">Montage Viewer</button><button type="button" class="rvImaging3DVideoButton" data-rv-3d-presentation="video" title="Create a rotation or ROI-sequence video from the current 3-D scene"><svg class="rvImaging3DVideoIcon" viewBox="0 0 16 16" aria-hidden="true" focusable="false"><rect x="1.5" y="3" width="9" height="10" rx="1.5"></rect><path d="M10.5 6.1 14.5 4.4v7.2l-4-1.7z"></path><path d="m5.2 5.5 3.4 2.5-3.4 2.5z" class="rvImaging3DVideoIconPlay"></path></svg><span>Video Maker</span></button></div>`;}
  function threeDPresentationHtml(options){const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,presets=cameraPresetButtonsHtml({selectedPreset:cfg.selectedPreset,escape:esc});return `<div class="rvImaging3DControlGroup rv3DPresentationControls"><span>${esc(cfg.label||'View preset')}</span><div class="rvImaging3DPresets">${presets}</div>${cfg.includeActions===false?'':threeDAdvancedActionsHtml(cfg)}</div>`;}

  /**
   * Own the delegated DOM wiring for all discrete G3C controls mounted under
   * one representation root. The adapter-provided dispatch executes semantics.
   */
  function bind(root,options){
    if(!root||typeof root.addEventListener!=='function'||typeof root.removeEventListener!=='function')fail('NMResultsViewerViewControls:InvalidRoot','View controls require one live DOM root.');
    const cfg=options&&typeof options==='object'?options:{},dispatch=cfg.dispatch;
    if(typeof dispatch!=='function')fail('NMResultsViewerViewControls:MissingDispatch','View controls require one host dispatch function.');
    const capabilities=arr(cfg.capabilities).map(text);
    if(!capabilities.length)fail('NMResultsViewerViewControls:MissingCapabilities','View controls require declared capabilities.');
    capabilities.forEach(capability=>{if(!hostApi().SUPPORTED_CAPABILITIES.includes(capability))fail('NMResultsViewerViewControls:UnknownCapability',`Unsupported Results Viewer view-control capability: ${capability||'(empty)'}.`);});
    let disposed=false;
    const send=(command,detail)=>{if(disposed)return;commandCapability(command);dispatch(command,detail||{});};

    const click=event=>{
      let target=closestWithin(root,event&&event.target,'[data-rv-view-command]');
      if(target){
        if(disabledControl(target))return;
        const action=text(target.getAttribute('data-rv-view-command'));
        if(action==='zoom')send('view.zoom',{direction:text(target.getAttribute('data-rv-view-direction'))});
        else if(action==='fit')send('view.fit',{});
        else if(action==='reset')send('view.reset',{});
        else fail('NMResultsViewerViewControls:UnknownViewAction',`Unsupported view action: ${action||'(empty)'}.`);
        return;
      }
      target=closestWithin(root,event&&event.target,'[data-rv-camera-preset]');if(target){if(disabledControl(target))return;send('camera.preset.select',{presetId:text(target.getAttribute('data-rv-camera-preset'))});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-3d-presentation]');if(target){if(disabledControl(target))return;const action=text(target.getAttribute('data-rv-3d-presentation'));if(action==='montage')send('presentation3d.montage.open',{});else if(action==='video')send('presentation3d.video.open',{});else fail('NMResultsViewerViewControls:UnknownPresentationAction',`Unsupported 3-D presentation action: ${action||'(empty)'}.`);return;}
      target=closestWithin(root,event&&event.target,'[data-rv-clipping-use-selection]');if(target&&!disabledControl(target))send('clipping.position.useSelection',{});
    };
    const change=event=>{
      let target=closestWithin(root,event&&event.target,'[data-rv-view-sync]');if(target){if(disabledControl(target))return;send('view.sync.toggle',{enabled:!!target.checked});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-camera-projection]');if(target){if(disabledControl(target))return;send('camera.projection.select',{projectionId:text(target.value)});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-geometry-variant]');if(target){if(disabledControl(target))return;send('geometry.variant.select',{variantId:text(target.value)});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-surface-visibility]');if(target){if(disabledControl(target))return;send('surface.visibility.select',{visibility:text(target.value)});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-clipping-mode]');if(target){if(disabledControl(target))return;send('clipping.mode.select',{mode:text(target.value)});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-clipping-linked]');if(target){if(disabledControl(target))return;send('clipping.link.toggle',{enabled:!!target.checked});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-clipping-keep]');if(target){if(disabledControl(target))return;send('clipping.side.select',{axis:text(target.getAttribute('data-rv-clipping-keep')),side:text(target.value)});return;}
      target=closestWithin(root,event&&event.target,'[data-rv-clipping-position]');if(target&&!disabledControl(target))send('clipping.position.update',{axis:text(target.getAttribute('data-rv-clipping-position')),value:Number(target.value),phase:'commit'});
    };
    const input=event=>{
      const target=closestWithin(root,event&&event.target,'[data-rv-clipping-position]');if(target&&!disabledControl(target))send('clipping.position.update',{axis:text(target.getAttribute('data-rv-clipping-position')),value:Number(target.value),phase:'preview'});
    };
    root.addEventListener('click',click);root.addEventListener('change',change);root.addEventListener('input',input);
    return Object.freeze({contractVersion:CONTRACT_VERSION,dispose:()=>{if(disposed)return false;disposed=true;root.removeEventListener('click',click);root.removeEventListener('change',change);root.removeEventListener('input',input);return true;}});
  }

  window.NMResultsViewerViewControls=Object.freeze({contractVersion:CONTRACT_VERSION,atlasDescriptorControlsHtml,toolbarHtml,cameraPresetButtonsHtml,clippingAxes,clippingHtml,syncClipping,featureProjectionHtml,bindFeatureProjection,bindDeferredRange,threeDPresentationHtml,threeDAdvancedActionsHtml,bind,_test:{PRESETS,CLIPPING_AXES,canonicalToolbarAttributes}});
})();
