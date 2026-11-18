/* Shared OOCV-container chooser. The calling runner owns eligibility and readiness. */
(function(global){
  'use strict';
  function arr(x){ return x == null ? [] : (Array.isArray(x) ? x : [x]); }
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  function fmtNumber(x){ const n=Number(x); return Number.isFinite(n) ? String(n) : '—'; }
  function bool(x){ return x === true || x === 1 || x === 'true'; }

  function open(spec){
    const rows=spec.containers;
    let working=rows.some(c=>Number(c.index)===Number(spec.selectedIndex))?spec.selectedIndex:null;
    let applyButton=null;
    global.NMModal.open({
      title:spec.title,size:'wide',
      render:body=>{
        body.innerHTML=`<div class="oocvDatasetModalIntro">${esc(spec.intro)}</div><div class="oocvDatasetModalTableWrap"></div>`;
        const host=body.querySelector('.oocvDatasetModalTableWrap');
        const draw=()=>{
          host.innerHTML=`<table class="oocvDatasetTable"><thead><tr><th>#</th><th>Dataset</th><th>Labels</th><th>Cases</th><th>Modalities</th><th>Status</th></tr></thead><tbody>${rows.map(c=>{
            const idx=Number(c.index||0), mods=arr(c.presentModalities).join(', ')||'—',ready=!!spec.isReady(c);
            const status=ready?'ready':spec.pendingStatus;
            return `<tr class="oocvDatasetModalRow ${Number(working)===idx?'selected':''}" data-index="${idx}" tabindex="0" aria-selected="${Number(working)===idx?'true':'false'}"><td>${idx}</td><td>${esc(c.description||`OOCV ${idx}`)}</td><td>${bool(c.labelsKnown)?'known':'prediction only'}</td><td>${fmtNumber(c.nCases)}</td><td>${esc(mods)}</td><td><span class="pill ${ready?'ok':'warn'}">${esc(status)}</span></td></tr>`;
          }).join('')}</tbody></table>`;
          if(applyButton) applyButton.disabled=!working;
          host.querySelectorAll('.oocvDatasetModalRow').forEach(tr=>{
            const select=()=>{ working=Number(tr.dataset.index); draw(); };
            tr.addEventListener('click',select);
            tr.addEventListener('keydown',ev=>{ if(ev.key==='Enter'||ev.key===' '){ev.preventDefault();select();} });
          });
        };
        draw();
      },
      actions:[
        {label:'Cancel',onClick:m=>m.close()},
        {label:spec.confirmLabel,variant:'primary',disabled:!working,ref:b=>{applyButton=b;},onClick:m=>{
          spec.onSelect(working);
          m.close();
        }}
      ]
    });
  }
  function renderControl(host, spec){
    const rows=spec.containers;
    const selected=rows.find(c=>Number(c.index)===Number(spec.selectedIndex));
    const summary=selected ? `${selected.description||`OOCV ${selected.index}`} · ${fmtNumber(selected.nCases)} cases · modality/modalities ${arr(selected.presentModalities).join(', ')||'—'} · ${bool(selected.labelsKnown)?'labels known':'prediction only'}`
      : rows.length ? spec.emptyText : spec.unavailableText;
    host.innerHTML=`<div class="oocvRunnerSectionHeader"><label class="nmRunnerSectionTitle">${esc(spec.label)}</label><span class="muted">${rows.length} suitable container${rows.length===1?'':'s'}</span></div>`+
      `<div class="oocvDatasetSummary"><div class="oocvDatasetSelectionText">${esc(summary)}</div><button id="selectOOCVDataset" class="oocvSelectorButton nmActionButton" type="button">Select OOCV data…</button></div>`+
      (spec.detail?`<div class="help">${esc(spec.detail)}</div>`:'');
    const button=host.querySelector('#selectOOCVDataset');
    button.disabled=spec.disabled||!rows.length;
    button.addEventListener('click',spec.onClick);
  }
  global.NMOOCVContainerSelector={open,renderControl};
})(window);
