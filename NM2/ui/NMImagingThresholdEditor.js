(function(){
  'use strict';
  const {clamp,text,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  function finite(value,fallback){if(value===null||value===undefined||value===''||typeof value==='boolean')return fallback;const n=Number(value);return Number.isFinite(n)?n:fallback;}
  function semantics(){const api=typeof window!=='undefined'&&window.NMResultsViewerDisplaySemantics;if(!api)throw new Error('The canonical Results Viewer display-semantics authority is unavailable.');return api;}
  function numericAttribute(value){return semantics().numericAttribute(value);}
  function tolerance(spec){return semantics().thresholdTolerance(spec||{});}
  function normalize(value,spec){return semantics().normalizeThresholdValue(value,spec||{});}
  function format(value,spec){return semantics().formatThresholdWithinBounds(value,spec||{});}
  function canonicalText(value){return text(value).trim().replace(/\u2212/g,'-').replace(/\s+/g,'');}
  function isIncompleteText(value){const raw=canonicalText(value).toLowerCase();return raw===''||/^[+-]?$/.test(raw)||/^[+-]?[.,]$/.test(raw)||/^[+-]?\d+[.,]$/.test(raw)||/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)[e][+-]?$/.test(raw);}
  function parseText(value){const raw=canonicalText(value);if(isIncompleteText(raw))return {kind:'incomplete',raw,value:NaN};if(raw.includes(',')&&raw.includes('.'))return {kind:'invalid',raw,value:NaN};const canonical=raw.replace(',','.');if(!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?$/i.test(canonical))return {kind:'invalid',raw,value:NaN};const n=Number(canonical);return Number.isFinite(n)?{kind:'valid',raw,value:n}:{kind:'invalid',raw,value:NaN};}
  function parseCommitted(value){const parsed=parseText(value);return parsed.kind==='valid'?{ok:true,value:parsed.value,intermediate:false}:{ok:false,value:NaN,intermediate:parsed.kind==='incomplete'};}
  function normalizeSpec(spec){const min=Number(spec&&spec.min),max=Number(spec&&spec.max),step=Number(spec&&spec.step),rangeMin=spec&&spec.rangeMin==null?min:Number(spec.rangeMin),rangeMax=spec&&spec.rangeMax==null?max:Number(spec.rangeMax);if(!Number.isFinite(min)||!Number.isFinite(max)||!Number.isFinite(step)||!Number.isFinite(rangeMin)||!Number.isFinite(rangeMax))throw new Error('Threshold editor specification requires finite numeric bounds and step.');if(max<min)throw new Error('Threshold editor specification has reversed bounds.');if(!(step>0))throw new Error('Threshold editor specification requires a positive step.');if(rangeMax<rangeMin)throw new Error('Threshold editor specification has a reversed data range.');return {min,max,step,rangeMin,rangeMax};}
  function steppedValue(value,direction,spec){const s=normalizeSpec(spec),base=clamp(finite(value,s.min),s.min,s.max),candidate=base+(direction<0?-s.step:s.step),result=normalize(candidate,s);return clamp(Number.isFinite(result.value)?result.value:candidate,s.min,s.max);}
  function tooltipAttributes(value,escapeFn){const esc=typeof escapeFn==='function'?escapeFn:escapeHtml,tip=text(value).trim();return tip?` data-imaging-tooltip="${esc(tip)}" aria-description="${esc(tip.replace(/\s*\n\s*/g,' '))}"`:'';}
  function html(options){
    const opts=options||{},esc=typeof opts.escape==='function'?opts.escape:escapeHtml,spec=normalizeSpec(opts.spec),field=text(opts.field),label=text(opts.label||'Threshold'),shown=format(clamp(finite(opts.value,spec.min),spec.min,spec.max),spec),step=numericAttribute(spec.step),min=numericAttribute(spec.min),max=numericAttribute(spec.max),rangeMin=numericAttribute(spec.rangeMin),rangeMax=numericAttribute(spec.rangeMax),tip=tooltipAttributes(opts.tooltip,esc);
    return `<div class="rvImagingThresholdField"${tip}><span>${esc(label)}</span><div class="rvImagingThresholdEditor" data-imaging-threshold-editor data-imaging-threshold-field="${esc(field)}" data-imaging-threshold-step="${esc(step)}" data-imaging-threshold-min="${esc(min)}" data-imaging-threshold-max="${esc(max)}" data-imaging-range-min="${esc(rangeMin)}" data-imaging-range-max="${esc(rangeMax)}"><button type="button" data-imaging-threshold-action="decrement" aria-label="Decrease ${esc(label)}"><span class="rvImagingThresholdGlyph" aria-hidden="true">−</span></button><input type="text" inputmode="decimal" autocomplete="off" spellcheck="false" data-imaging-threshold-input value="${esc(shown)}" aria-label="${esc(label)} value"><button type="button" data-imaging-threshold-action="increment" aria-label="Increase ${esc(label)}"><span class="rvImagingThresholdGlyph" aria-hidden="true">+</span></button></div></div>`;
  }
  function editorSpec(editor){return normalizeSpec({min:editor.getAttribute('data-imaging-threshold-min'),max:editor.getAttribute('data-imaging-threshold-max'),step:editor.getAttribute('data-imaging-threshold-step'),rangeMin:editor.getAttribute('data-imaging-range-min'),rangeMax:editor.getAttribute('data-imaging-range-max')});}
  function bindEditor(editor,options){
    const opts=options||{};if(editor.dataset&&editor.dataset.imagingThresholdBound==='1')return null;
    const field=text(editor.getAttribute('data-imaging-threshold-field')),input=editor.querySelector('[data-imaging-threshold-input]'),minus=editor.querySelector('[data-imaging-threshold-action="decrement"]'),plus=editor.querySelector('[data-imaging-threshold-action="increment"]');if(!field||!input)return null;
    const spec=editorSpec(editor),listeners=[];if(editor.dataset)editor.dataset.imagingThresholdBound='1';
    const on=(node,type,listener)=>{if(!node)return;node.addEventListener(type,listener);listeners.push([node,type,listener]);};
    const current=()=>finite(typeof opts.getValue==='function'?opts.getValue(field):input.value,spec.min);
    const restore=()=>{input.value=format(clamp(current(),spec.min,spec.max),spec);input.setAttribute('aria-invalid','false');};
    const warn=message=>{if(typeof opts.onWarning==='function')opts.onWarning(message,field,editor);};
    const applyValue=(value,reason)=>{const bounded=clamp(value,spec.min,spec.max);if(typeof opts.setValue==='function')opts.setValue(field,bounded,reason,editor);input.value=format(bounded,spec);input.setAttribute('aria-invalid','false');return bounded;};
    const commit=(reason,showWarning)=>{const entered=text(input.value),parsed=parseText(entered);if(parsed.kind!=='valid'){restore();if(showWarning)warn(`${text(opts.labelForField&&opts.labelForField(field)||field)} requires a complete numeric value. The previous threshold was restored.`);return false;}const result=normalize(parsed.value,spec),value=Number.isFinite(result.value)?result.value:current(),prior=clamp(current(),spec.min,spec.max);if(Math.abs(value-prior)<=tolerance(spec)){input.value=format(prior,spec);input.setAttribute('aria-invalid','false');return true;}applyValue(value,reason);if(showWarning&&!result.accepted)warn(`${text(opts.labelForField&&opts.labelForField(field)||field)} ${entered||'blank'} is outside the allowed range ${format(spec.min,spec)} to ${format(spec.max,spec)}. The value was limited to the nearest endpoint.`);return true;};
    const step=direction=>{let base=current(),parsed=parseText(input.value);if(parsed.kind==='valid'){const normalized=normalize(parsed.value,spec);if(Number.isFinite(normalized.value))base=normalized.value;}applyValue(steppedValue(base,direction,spec),direction<0?'threshold_decrement':'threshold_increment');};
    on(input,'input',()=>{input.setAttribute('aria-invalid',parseText(input.value).kind==='invalid'?'true':'false');});
    on(input,'keydown',event=>{if(event.key==='Enter'){event.preventDefault();commit('threshold_manual',true);}else if(event.key==='Escape'){event.preventDefault();restore();if(typeof input.select==='function')input.select();}});
    const retainInputFocus=event=>{event.preventDefault();};
    on(input,'blur',()=>commit('threshold_manual',true));on(minus,'mousedown',retainInputFocus);on(plus,'mousedown',retainInputFocus);on(minus,'click',()=>step(-1));on(plus,'click',()=>step(1));
    return Object.freeze({field,dispose:()=>{listeners.splice(0).forEach(([node,type,listener])=>{if(typeof node.removeEventListener==='function')node.removeEventListener(type,listener);});if(editor.dataset)delete editor.dataset.imagingThresholdBound;}});
  }
  function bind(root,options){if(!root||typeof root.querySelectorAll!=='function')return 0;let count=0;Array.from(root.querySelectorAll('[data-imaging-threshold-editor]')).forEach(editor=>{if(bindEditor(editor,options))count++;});return count;}
  function bindManaged(root,options){
    if(!root||typeof root.querySelectorAll!=='function')throw new Error('Managed threshold binding requires a live representation root.');
    const bindings=Array.from(root.querySelectorAll('[data-imaging-threshold-editor]')).map(editor=>bindEditor(editor,options)).filter(Boolean);
    return Object.freeze({count:bindings.length,dispose:()=>{bindings.splice(0).forEach(binding=>binding.dispose());}});
  }

  window.NMImagingThresholdEditor={parseText,isIncompleteText,normalize,normalizeSpec,format,steppedValue,html,bind,bindManaged,_test:{numericAttribute,tolerance,editorSpec,isIntermediate:isIncompleteText,parseCommitted,bindEditor}};
})();
