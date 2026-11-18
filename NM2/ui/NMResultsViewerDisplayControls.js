(function(){
  'use strict';

  const {text,toArray,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  /**
   * NMResultsViewerDisplayControls
   *
   * Pathway-neutral markup, event wiring, and canonical state-write executor
   * for feature display controls. The component never interprets display
   * meaning: every edit is resolved through NMResultsViewerDisplaySemantics
   * into NM-RESULTS-VIEWER-DISPLAY-REQUEST-V1 before a renderer is notified.
   *
   * Contract: NM-RESULTS-VIEWER-DISPLAY-CONTROLS-V1
   */

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-DISPLAY-CONTROLS-V1';
  const CAPABILITIES=Object.freeze(['threshold','colourbar','displayRange','opacity']);
  const COMMAND_FIELDS=Object.freeze({
    'display.threshold.update':Object.freeze(['thresholdLow','thresholdHigh','thresholdValue']),
    'display.colourbar.update':Object.freeze(['colorStops']),
    'display.range.update':Object.freeze(['displayRangeMode','manualDisplayLower','manualDisplayUpper']),
    'display.opacity.update':Object.freeze(['opacity'])
  });
  const DEFAULT_TOOLTIPS=Object.freeze({
    threshold:'Feature threshold\nControls the focused feature threshold. The − and + buttons use a fine polarity-specific increment derived from the exact admissible interval. Manual text is committed with Enter or when focus leaves the field.',
    colourbar:'Editable colour gradient\nRight-click the bar to add a stop. Drag stops to move them. Right-click or double-click a stop for colour and duplication controls.',
    colorScale:'Colour scale\nControls colour normalization only. Robust signed uses separate negative and positive endpoints; Full range uses exact extrema; Symmetric |value| uses equal absolute endpoints; Manual uses explicit limits.',
    manualLower:'Manual lower colour-scale bound.',
    manualUpper:'Manual upper colour-scale bound.',
    exactRange:'Exact finite data range before display clipping.',
    shownRange:'Range mapped to the colour scale after the canonical display request is resolved.',
    clippedRange:'Counts of threshold-eligible values clipped below or above the shown colour range.',
    opacity:'Feature opacity\nAdjusts transparency of the focused feature overlay without changing support, thresholds, values, or colour intensity.'
  });
  function finite(value,fallback){if(value===null||value===undefined||value===''||typeof value==='boolean')return fallback;const number=Number(value);return Number.isFinite(number)?number:fallback;}
  function fmt(value,digits){const number=finite(value,NaN);if(!Number.isFinite(number))return '—';const precision=Number.isFinite(Number(digits))?Number(digits):3;if(Math.abs(number)>=10000||(Math.abs(number)>0&&Math.abs(number)<Math.pow(10,-precision)))return number.toExponential(Math.max(1,precision-1));return number.toFixed(precision).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');}
  function semantics(){const api=window.NMResultsViewerDisplaySemantics;if(!api)throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');return api;}
  function thresholdEditor(){const api=window.NMImagingThresholdEditor;if(!api||typeof api.html!=='function'||typeof api.bindManaged!=='function')throw new Error('The canonical managed threshold editor is unavailable.');return api;}
  function gradient(){const api=window.NMImagingColorGradient;if(!api||typeof api.html!=='function'||typeof api.bind!=='function')throw new Error('The canonical colour-gradient editor is unavailable.');return api;}
  function normalizeCapabilities(value){if(!Array.isArray(value)||!value.length)throw new Error('Display controls require a non-empty capability array.');const seen=new Set();return Object.freeze(value.map(raw=>{const capability=text(raw);if(!CAPABILITIES.includes(capability))throw new Error(`Unsupported display-control capability: ${capability||'(empty)'}.`);if(seen.has(capability))throw new Error(`Duplicate display-control capability: ${capability}.`);seen.add(capability);return capability;}));}
  function tooltipAttributes(config,key,escape){if(config&&typeof config.tooltipAttributes==='function')return text(config.tooltipAttributes(key,DEFAULT_TOOLTIPS[key],escape));const tip=DEFAULT_TOOLTIPS[key]||'';return tip?` data-imaging-tooltip="${escape(tip)}" aria-description="${escape(tip.replace(/\s*\n\s*/g,' '))}"`:'';}
  function numericAttribute(value){return semantics().numericAttribute(value);}
  function displayContract(display){return semantics().contractForDisplay(display);}

  function thresholdFieldHtml(label,field,overlay,display,escape,config){
    const spec=semantics().thresholdSpec(overlay,display,field),value=finite(display&&display[field],spec.min);
    return thresholdEditor().html({label,field,spec,value,escape,tooltip:DEFAULT_TOOLTIPS.threshold,tooltipAttributes:tooltipAttributes(config,'threshold',escape)});
  }
  function thresholdFieldsHtml(overlay,display,escape,config){
    const mode=text(display&&display.thresholdMode).toLowerCase();
    if(mode==='outside_interval')return thresholdFieldHtml('Negative threshold','thresholdLow',overlay,display,escape,config)+thresholdFieldHtml('Positive threshold','thresholdHigh',overlay,display,escape,config);
    if(mode==='above_abs')return thresholdFieldHtml('Magnitude threshold','thresholdValue',overlay,display,escape,config);
    if(mode==='below')return thresholdFieldHtml('Negative threshold','thresholdValue',overlay,display,escape,config);
    if(mode==='above')return thresholdFieldHtml('Positive threshold','thresholdValue',overlay,display,escape,config);
    if(mode==='none')return '';
    throw new Error(`Unknown threshold mode: ${mode||'(empty)'}.`);
  }

  /** Build one display-control DOM fragment from an already resolved display state. */
  function html(options){
    const config=options&&typeof options==='object'?options:{},overlay=config.overlay,display=config.display,support=config.support||null;
    if(!overlay||!display)throw new Error('Display-control markup requires an overlay and resolved display state.');
    const capabilities=normalizeCapabilities(config.capabilities),has=capability=>capabilities.includes(capability),escape=typeof config.escape==='function'?config.escape:escapeHtml;
    const contract=displayContract(display),polarity=contract.polarity,bar=semantics().colorbarModel(overlay,display,support),rangeMode=text(display.displayRangeMode||'robust_polarity_wise'),rangeStep=Math.max(Number.EPSILON,Math.abs(finite(bar&&bar.exactMax,1)-finite(bar&&bar.exactMin,0))/200),manualRange=rangeMode==='manual';
    const colourbarHtml=has('colourbar')?gradient().html(display,polarity.kind,{escape,minValue:finite(bar&&bar.min,contract.shownRange.lower),maxValue:finite(bar&&bar.max,contract.shownRange.upper),minLabel:(bar&&bar.lowerClippedCount?'≤ ':'')+fmt(bar&&bar.min,3),maxLabel:(bar&&bar.upperClippedCount?'≥ ':'')+fmt(bar&&bar.max,3),tooltipAttributes:tooltipAttributes(config,'colourbar',escape)}):'';
    const rangeReadoutHtml=(has('colourbar')||has('displayRange'))?`<div class="rvImagingRangeReadout"><span${tooltipAttributes(config,'exactRange',escape)}>Exact <b>${escape(fmt(bar&&bar.exactMin,4))} … ${escape(fmt(bar&&bar.exactMax,4))}</b></span><span${tooltipAttributes(config,'shownRange',escape)}>Shown <b>${escape(fmt(bar&&bar.min,4))} … ${escape(fmt(bar&&bar.max,4))}</b></span><span${tooltipAttributes(config,'clippedRange',escape)}>Clipped <b>${escape(String(bar&&bar.lowerClippedCount||0))} low / ${escape(String(bar&&bar.upperClippedCount||0))} high</b></span></div>`:'';
    const thresholdsHtml=has('threshold')?`<div class="rvImagingOverlayThresholds" aria-label="Feature thresholds">${thresholdFieldsHtml(overlay,display,escape,config)}</div>`:'';
    const rangeControlsHtml=has('displayRange')?`<div class="rvImagingOverlayRangeControls" aria-label="Colour scale"><label${tooltipAttributes(config,'colorScale',escape)}>Colour scale<select data-imaging-display-range-mode><option value="robust_polarity_wise"${rangeMode==='robust_polarity_wise'?' selected':''}>Robust signed</option><option value="full_data_range"${rangeMode==='full_data_range'?' selected':''}>Full range</option><option value="symmetric_absolute"${rangeMode==='symmetric_absolute'?' selected':''}>Symmetric |value|</option><option value="manual"${rangeMode==='manual'?' selected':''}>Manual</option></select></label><label class="rvImagingManualRange"${manualRange?'':' hidden'}${tooltipAttributes(config,'manualLower',escape)}>Lower<input type="number" step="${escape(numericAttribute(rangeStep))}" value="${escape(numericAttribute(finite(display.manualDisplayLower,bar&&bar.min)))}" data-imaging-display-range-lower></label><label class="rvImagingManualRange"${manualRange?'':' hidden'}${tooltipAttributes(config,'manualUpper',escape)}>Upper<input type="number" step="${escape(numericAttribute(rangeStep))}" value="${escape(numericAttribute(finite(display.manualDisplayUpper,bar&&bar.max)))}" data-imaging-display-range-upper></label></div>`:'';
    const opacityHtml=has('opacity')?`<label class="rvImagingAppearanceField rvImagingOverlayOpacityField"${tooltipAttributes(config,'opacity',escape)}><span>Feature opacity</span><input type="range" min="0" max="1" step="0.01" data-imaging-display="opacity" value="${escape(finite(display.opacity,.85))}"><output>${escape(fmt(display.opacity,2))}</output></label>`:'';
    return Object.freeze({contractVersion:CONTRACT_VERSION,capabilities,polarity,colorbarModel:bar,html:`${colourbarHtml}${rangeReadoutHtml}<div class="rvImagingOverlayDisplayStack" data-imaging-overlay-display-controls>${thresholdsHtml}${rangeControlsHtml}${opacityHtml}</div>`});
  }

  function commandCapability(command){const host=window.NMResultsViewerControlHost;if(!host||typeof host.commandCapability!=='function')throw new Error('The canonical Results Viewer command-capability authority is unavailable.');const capability=host.commandCapability(text(command));if(!CAPABILITIES.includes(capability))throw new Error(`Unsupported display-control command: ${text(command)||'(empty)'}.`);return capability;}
  function validatePatch(command,patch){
    if(!patch||typeof patch!=='object'||Array.isArray(patch))throw new Error('Display-control update requires one plain patch object.');
    const fields=COMMAND_FIELDS[command],keys=Object.keys(patch);if(!keys.length)throw new Error('Display-control update patch is empty.');
    keys.forEach(field=>{if(!fields.includes(field))throw new Error(`Display-control command ${command} cannot write field ${field}.`);});
    return Object.assign({},patch);
  }

  /**
   * Apply one host-routed edit through the canonical G2C display-request boundary.
   * This is the sole mutable display-state write path owned by G3B controls.
   */
  function applyCommand(envelope,options){
    const config=options&&typeof options==='object'?options:{},command=text(envelope&&envelope.command),capability=commandCapability(command),detail=envelope&&envelope.detail||{};
    if(text(envelope&&envelope.capability)!==capability)throw new Error(`Display-control command ${command} has mismatched capability ${text(envelope&&envelope.capability)}.`);
    const overlay=typeof config.getOverlay==='function'?config.getOverlay():null,support=typeof config.getSupport==='function'?config.getSupport():null,display=overlay&&typeof config.getDisplay==='function'?config.getDisplay(overlay,support):null;
    if(!overlay||!display)throw new Error('Display-control update requires an active overlay and resolved display state.');
    const patch=validatePatch(command,detail.patch),candidate=Object.assign({},display,patch),settings={defaultOpacity:Number.isFinite(Number(config.defaultOpacity))?Number(config.defaultOpacity):.85},identity=typeof config.identity==='function'?config.identity(overlay):config.identity;
    const candidateResult=semantics().resolveDisplayState(candidate,overlay,support,settings,identity||{});
    const committed=semantics().adoptResolvedDisplayState(display,candidateResult);
    return Object.freeze({contractVersion:CONTRACT_VERSION,command,capability,phase:text(detail.phase||'commit')==='preview'?'preview':'commit',reason:text(detail.reason||command),patch:Object.freeze(patch),display:committed.state,resolvedRequest:committed.request,resolvedContract:committed.contract});
  }

  /** Bind one root using delegated/dynamic controls and host-routed commands. */
  function bind(root,options){
    const config=options&&typeof options==='object'?options:{};if(!root||typeof root.addEventListener!=='function')throw new Error('Display-control binding requires a live representation root.');if(typeof config.dispatch!=='function')throw new Error('Display-control binding requires a host dispatch function.');
    const capabilities=normalizeCapabilities(config.capabilities),has=capability=>capabilities.includes(capability),getOverlay=typeof config.getOverlay==='function'?config.getOverlay:()=>null,getSupport=typeof config.getSupport==='function'?config.getSupport:()=>null,getDisplay=typeof config.getDisplay==='function'?config.getDisplay:()=>null;
    const emit=(command,patch,reason,phase)=>config.dispatch(command,{patch,reason,phase});
    const thresholdApi=thresholdEditor();let thresholdBinding=null;
    const thresholdOptions={getValue:field=>{const overlay=getOverlay(),display=overlay?getDisplay(overlay,getSupport()):null;return display?display[field]:NaN;},setValue:(field,value,reason)=>emit('display.threshold.update',{[field]:value},reason||'threshold','commit'),labelForField:field=>field==='thresholdLow'?'Negative threshold':(field==='thresholdHigh'?'Positive threshold':'Feature threshold'),onWarning:message=>{if(typeof config.onWarning==='function')config.onWarning(message);}};
    const refresh=()=>{
      if(thresholdBinding&&typeof thresholdBinding.dispose==='function')thresholdBinding.dispose();
      thresholdBinding=has('threshold')?thresholdApi.bindManaged(root,thresholdOptions):null;
      if(gradientBinding&&typeof gradientBinding.render==='function')gradientBinding.render();
    };
    const onChange=event=>{
      const target=event&&event.target;if(!target||typeof target.matches!=='function')return;
      if(has('displayRange')&&target.matches('[data-imaging-display-range-mode],[data-imaging-display-range-lower],[data-imaging-display-range-upper]')){
        const mode=root.querySelector('[data-imaging-display-range-mode]'),lower=root.querySelector('[data-imaging-display-range-lower]'),upper=root.querySelector('[data-imaging-display-range-upper]'),patch={};if(mode)patch.displayRangeMode=mode.value;if(lower)patch.manualDisplayLower=finite(lower.value,NaN);if(upper)patch.manualDisplayUpper=finite(upper.value,NaN);emit('display.range.update',patch,target.matches('[data-imaging-display-range-mode]')?'display_range_mode':'display_range_manual','commit');return;
      }
      if(has('opacity')&&target.matches('[data-imaging-display="opacity"]')){emit('display.opacity.update',{opacity:finite(target.value,NaN)},'display_opacity','commit');}
    };
    const onInput=event=>{
      const target=event&&event.target;if(!target||typeof target.matches!=='function')return;
      if(has('opacity')&&target.matches('[data-imaging-display="opacity"]')){const value=finite(target.value,NaN),output=target.parentElement&&target.parentElement.querySelector('output');if(output)output.textContent=fmt(value,2);emit('display.opacity.update',{opacity:value},'display_opacity','preview');}
    };
    root.addEventListener('change',onChange);root.addEventListener('input',onInput);
    let gradientBinding=null;
    if(has('colourbar'))gradientBinding=gradient().bind(root,{getDisplay:()=>{const overlay=getOverlay();return overlay?getDisplay(overlay,getSupport()):null;},getKind:()=>{const overlay=getOverlay();if(!overlay)throw new Error('Colour-gradient editing requires an active overlay.');const display=getDisplay(overlay,getSupport());return displayContract(display).polarity.kind;},onEdit:(stops,reason,phase)=>emit('display.colourbar.update',{colorStops:stops},reason||'color_gradient',phase||'commit'),onWarning:message=>{if(typeof config.onWarning==='function')config.onWarning(message);}});
    refresh();
    return Object.freeze({contractVersion:CONTRACT_VERSION,capabilities,refresh,dispose:()=>{root.removeEventListener('change',onChange);root.removeEventListener('input',onInput);if(thresholdBinding&&typeof thresholdBinding.dispose==='function')thresholdBinding.dispose();if(gradientBinding&&typeof gradientBinding.dispose==='function')gradientBinding.dispose();}});
  }

  window.NMResultsViewerDisplayControls=Object.freeze({CONTRACT_VERSION,CAPABILITIES,html,bind,applyCommand,_test:Object.freeze({normalizeCapabilities,commandCapability,validatePatch,thresholdFieldsHtml,tooltipAttributes})});
})();
