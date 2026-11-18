(function(root){
  'use strict';

  function clamp(value,lower,upper){return Math.max(lower,Math.min(upper,value));}
  function text(value){return String(value==null?'':value);}
  function toArray(value){return Array.isArray(value)||ArrayBuffer.isView(value)?Array.from(value):(value==null?[]:[value]);}
  function escapeHtml(value){return text(value).replace(/[&<>"']/g,character=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));}
  /**
   * abbreviateLabel  Provide the single Results Viewer middle-abbreviation policy.
   * Scientific identifiers and complete labels remain caller-owned; this returns
   * only a bounded display projection and deliberately uses three visible dots.
   */
  function abbreviateLabel(value,maxChars){
    const label=text(value).replace(/\s+/g,' ').trim(),limit=Math.max(8,Math.round(Number(maxChars)||28));
    if(label.length<=limit)return label;
    if(limit<16)return label.slice(0,Math.max(1,limit-3))+'...';
    const head=Math.ceil((limit-3)*.58),tail=Math.max(4,limit-head-3);
    return label.slice(0,head)+'...'+label.slice(label.length-tail);
  }
  function nowMs(){return typeof performance!=='undefined'&&performance&&typeof performance.now==='function'?performance.now():Date.now();}

  root.NMResultsViewerPrimitives=Object.freeze({clamp,text,toArray,escapeHtml,abbreviateLabel,nowMs});
})(typeof globalThis!=='undefined'?globalThis:this);
