(function(){
  'use strict';

  const {text,escapeHtml}=globalThis.NMResultsViewerPrimitives;
  /**
   * NMResultsViewerInformationControls
   *
   * Pathway-neutral markup, update, and DOM-event owner for Results Viewer
   * information footers and extrema commands. It owns no scientific item
   * identity, extrema eligibility, selection, reveal, flashing, clipping,
   * matrix, camera, or renderer semantics. Pathway adapters supply field
   * models and execute validated extrema commands.
   *
   * Contract: NM-RESULTS-VIEWER-INFORMATION-CONTROLS-V1
   * Failure policy: malformed fields, duplicate identifiers, undeclared
   * capabilities, unsupported extrema kinds, and missing host dispatch fail
   * explicitly.
   */

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-INFORMATION-CONTROLS-V1';
  const CAPABILITIES=Object.freeze(['informationFooter','extrema']);
  const EXTREMA_KINDS=Object.freeze(['minimum','maximum','strongest_absolute']);

  function fail(code,message){
    const error=new Error(String(message||'Results Viewer information-control failure.'));
    error.name='NMResultsViewerInformationControlsError';
    error.code=String(code||'NMResultsViewerInformationControls:Failure');
    throw error;
  }
  function arr(value){return Array.isArray(value)?value:[];}
  function closestWithin(root,target,selector){if(!target||typeof target.closest!=='function')return null;const node=target.closest(selector);return node&&root.contains(node)?node:null;}
  function disabledControl(target){return !!(target&&(target.disabled===true||(typeof target.getAttribute==='function'&&target.getAttribute('aria-disabled')==='true')));}
  function hostApi(){const api=window.NMResultsViewerControlHost;if(!api||typeof api.commandCapability!=='function')fail('NMResultsViewerInformationControls:MissingHost','The pathway-neutral Results Viewer control host is unavailable.');return api;}
  function normalizeCapabilities(value){
    if(!Array.isArray(value)||!value.length)fail('NMResultsViewerInformationControls:MissingCapabilities','Information controls require declared capabilities.');
    const seen=new Set(),out=[];
    value.forEach(raw=>{const capability=text(raw);if(!CAPABILITIES.includes(capability))fail('NMResultsViewerInformationControls:UnknownCapability',`Unsupported Results Viewer information-control capability: ${capability||'(empty)'}.`);if(seen.has(capability))fail('NMResultsViewerInformationControls:DuplicateCapability',`Duplicate information-control capability: ${capability}.`);seen.add(capability);out.push(capability);});
    return Object.freeze(out);
  }
  function normalizeField(field,index){
    const item=field&&typeof field==='object'&&!Array.isArray(field)?field:{};
    const id=text(item.id).trim(),label=text(item.label).trim();
    if(!id)fail('NMResultsViewerInformationControls:MissingFieldId',`Information field ${index+1} requires a non-empty id.`);
    if(!/^[a-z][a-z0-9_]*$/.test(id))fail('NMResultsViewerInformationControls:InvalidFieldId',`Invalid information-field id: ${id}.`);
    if(!label)fail('NMResultsViewerInformationControls:MissingFieldLabel',`Information field ${id} requires a label.`);
    return Object.freeze({id,label,value:item.value==null||item.value===''?'—':text(item.value),className:text(item.className),tooltip:text(item.tooltip),title:text(item.title),ariaLabel:text(item.ariaLabel)});
  }
  function normalizeFields(value){
    const fields=arr(value).map(normalizeField),seen=new Set();
    fields.forEach(field=>{if(seen.has(field.id))fail('NMResultsViewerInformationControls:DuplicateFieldId',`Duplicate information-field id: ${field.id}.`);seen.add(field.id);});
    return Object.freeze(fields);
  }
  function normalizeExtrema(value){
    const items=arr(value).map((raw,index)=>{const item=raw&&typeof raw==='object'&&!Array.isArray(raw)?raw:{},kind=text(item.kind);if(!EXTREMA_KINDS.includes(kind))fail('NMResultsViewerInformationControls:InvalidExtremumKind',`Unsupported extrema kind at position ${index+1}: ${kind||'(empty)'}.`);return Object.freeze({kind,label:text(item.label).trim()||kind,tooltip:text(item.tooltip),disabled:!!item.disabled});});
    const seen=new Set();items.forEach(item=>{if(seen.has(item.kind))fail('NMResultsViewerInformationControls:DuplicateExtremumKind',`Duplicate extrema kind: ${item.kind}.`);seen.add(item.kind);});
    return Object.freeze(items);
  }
  function tooltipAttributes(value,escapeFn){const tooltip=text(value).trim();return tooltip?` data-imaging-tooltip="${escapeFn(tooltip)}" aria-description="${escapeFn(tooltip.replace(/\s*\n\s*/g,' '))}"`:'';}

  /** Render one generic information/extrema footer. */
  function html(options){
    const cfg=options&&typeof options==='object'?options:{},esc=typeof cfg.escape==='function'?cfg.escape:escapeHtml,capabilities=normalizeCapabilities(cfg.capabilities),has=capability=>capabilities.includes(capability),fields=has('informationFooter')?normalizeFields(cfg.fields):Object.freeze([]),extrema=has('extrema')?normalizeExtrema(cfg.extrema):Object.freeze([]);
    if(has('informationFooter')&&!fields.length)fail('NMResultsViewerInformationControls:MissingFields','The informationFooter capability requires at least one field.');
    if(has('extrema')&&!extrema.length)fail('NMResultsViewerInformationControls:MissingExtrema','The extrema capability requires at least one extrema command.');
    const fieldHtml=fields.map(field=>`<span class="rvImagingLocationField${field.className?' '+esc(field.className):''}" data-rv-information-field-container="${esc(field.id)}"${tooltipAttributes(field.tooltip,esc)}${field.title?` title="${esc(field.title)}"`:''}><small data-rv-information-label="${esc(field.id)}">${esc(field.label)}</small><b data-rv-information-field="${esc(field.id)}"${field.ariaLabel?` aria-label="${esc(field.ariaLabel)}"`:''}>${esc(field.value)}</b></span>`).join('');
    const extremaHtml=extrema.map(item=>`<button type="button" data-rv-extremum="${item.kind}"${tooltipAttributes(item.tooltip,esc)}${item.disabled?' disabled':''}>${esc(item.label)}</button>`).join('');
    return `<footer class="rvImagingControls${cfg.className?' '+esc(cfg.className):''}" data-rv-information-footer><div class="rvImagingControlRow rvImagingControlRow--navigation">${fields.length?`<div class="rvImagingControlGroup rvImagingCoordinates rvImagingLocationReadout" data-rv-information-readout data-rv-information-field-count="${fields.length}" style="--rv-information-field-count:${fields.length}" aria-label="${esc(cfg.locationAriaLabel||'Selected item')}">${fieldHtml}</div>`:''}${extrema.length?`<div class="rvImagingControlGroup rvImagingExtremaControls" data-rv-extrema-controls aria-label="${esc(cfg.extremaAriaLabel||'Feature extrema')}"><span class="rvImagingControlGroupLabel">${esc(cfg.extremaLabel||'Extrema')}</span>${extremaHtml}<span class="rvVisuallyHidden" data-rv-extremum-status aria-live="polite">${esc(cfg.extremaStatus||'No extremum selected.')}</span></div>`:''}${cfg.viewHtml||''}${cfg.trailingHtml||''}</div></footer>`;
  }

  /** Update generic footer fields without changing pathway interaction state. */
  function update(root,options){
    if(!root||typeof root.querySelector!=='function')fail('NMResultsViewerInformationControls:InvalidRoot','Information-control updates require one live representation root.');
    const cfg=options&&typeof options==='object'?options:{},updates=arr(cfg.fields);
    updates.forEach((raw,index)=>{const item=raw&&typeof raw==='object'&&!Array.isArray(raw)?raw:{},id=text(item.id).trim();if(!id)fail('NMResultsViewerInformationControls:MissingFieldId',`Information-field update ${index+1} requires an id.`);const valueNode=root.querySelector(`[data-rv-information-field="${id}"]`),labelNode=root.querySelector(`[data-rv-information-label="${id}"]`),container=root.querySelector(`[data-rv-information-field-container="${id}"]`);if(!valueNode||!labelNode||!container)fail('NMResultsViewerInformationControls:UnknownField',`Information field ${id} is not mounted in this representation.`);if(Object.prototype.hasOwnProperty.call(item,'value'))valueNode.textContent=item.value==null||item.value===''?'—':text(item.value);if(Object.prototype.hasOwnProperty.call(item,'label')){const label=text(item.label).trim();if(!label)fail('NMResultsViewerInformationControls:MissingFieldLabel',`Information field ${id} cannot have an empty label.`);labelNode.textContent=label;}if(Object.prototype.hasOwnProperty.call(item,'title')){const title=text(item.title);if(title)valueNode.setAttribute('title',title);else valueNode.removeAttribute('title');}if(Object.prototype.hasOwnProperty.call(item,'ariaLabel')){const aria=text(item.ariaLabel);if(aria)valueNode.setAttribute('aria-label',aria);else valueNode.removeAttribute('aria-label');}if(Object.prototype.hasOwnProperty.call(item,'tooltip')){const tooltip=text(item.tooltip).trim();if(tooltip){container.setAttribute('data-imaging-tooltip',tooltip);container.setAttribute('aria-description',tooltip.replace(/\s*\n\s*/g,' '));}else{container.removeAttribute('data-imaging-tooltip');container.removeAttribute('aria-description');}}});
    if(Object.prototype.hasOwnProperty.call(cfg,'extremaStatus')){const status=root.querySelector('[data-rv-extremum-status]');if(!status)fail('NMResultsViewerInformationControls:MissingExtremaStatus','The extrema status region is not mounted in this representation.');status.textContent=text(cfg.extremaStatus)||'No extremum selected.';}
    return true;
  }

  /** Bind extrema buttons to the G3D host command. */
  function bind(root,options){
    if(!root||typeof root.addEventListener!=='function'||typeof root.removeEventListener!=='function')fail('NMResultsViewerInformationControls:InvalidRoot','Information controls require one live DOM root.');
    const cfg=options&&typeof options==='object'?options:{},dispatch=cfg.dispatch,capabilities=normalizeCapabilities(cfg.capabilities);
    if(typeof dispatch!=='function')fail('NMResultsViewerInformationControls:MissingDispatch','Information controls require one host dispatch function.');
    capabilities.forEach(capability=>{if(!hostApi().SUPPORTED_CAPABILITIES.includes(capability))fail('NMResultsViewerInformationControls:UnknownHostCapability',`The control host does not support information-control capability ${capability}.`);});
    let disposed=false;
    const click=event=>{if(disposed||!capabilities.includes('extrema'))return;const target=closestWithin(root,event&&event.target,'[data-rv-extremum]');if(!target||disabledControl(target))return;const kind=text(target.getAttribute('data-rv-extremum'));if(!EXTREMA_KINDS.includes(kind))fail('NMResultsViewerInformationControls:InvalidExtremumKind',`Unsupported extrema kind: ${kind||'(empty)'}.`);hostApi().commandCapability('extrema.select');dispatch('extrema.select',{kind});};
    root.addEventListener('click',click);
    return Object.freeze({contractVersion:CONTRACT_VERSION,capabilities,dispose:()=>{if(disposed)return false;disposed=true;root.removeEventListener('click',click);return true;}});
  }

  window.NMResultsViewerInformationControls=Object.freeze({contractVersion:CONTRACT_VERSION,CAPABILITIES,EXTREMA_KINDS,html,update,bind,_test:Object.freeze({normalizeCapabilities,normalizeFields,normalizeExtrema})});
})();
