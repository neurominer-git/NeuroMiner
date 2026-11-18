(function(global){
'use strict';
const esc=global.NMResultsViewerPrimitives.escapeHtml;
function render(root,payload,onAnalysis){
 const rows=payload.rows,criterion=payload.criterion;
 const sizes=[...new Set(rows.map(r=>Number(r.sampleSize)))].sort((a,b)=>a-b);
 const perms=[...new Set(rows.map(r=>Number(r.permutation)))].sort((a,b)=>a-b);
 const values=rows.map(r=>Number(r.value)).filter(Number.isFinite);
 if(!values.length)throw Error('No finite performance values are available for the selected optimization criterion.');
 const xMin=sizes[0],xMax=sizes[sizes.length-1],yMin=Math.min(...values),yMax=Math.max(...values);
 const padding=(yMax-yMin||1)*.1,lo=yMin-padding,hi=yMax+padding;
 const x=n=>65+(n-xMin)/(xMax-xMin||1)*690;
 const y=v=>290-(v-lo)/(hi-lo)*235;
 let svg='<svg viewBox="0 0 820 335" role="img" aria-label="SYNTH cumulative performance by permutation">';
 for(let j=0;j<=4;j++){const v=lo+(hi-lo)*j/4;svg+=`<line x1="65" y1="${y(v)}" x2="755" y2="${y(v)}" stroke="currentColor" opacity=".12"/><text x="55" y="${y(v)+4}" text-anchor="end" font-size="12">${v.toFixed(2)}</text>`;}
 sizes.forEach(n=>svg+=`<text x="${x(n)}" y="313" text-anchor="middle" font-size="12">${n}</text>`);
 const colors=['#157a5b','#c47b35','#6887c5','#8d69b3','#a65555'];
 perms.forEach((p,i)=>{const group=rows.filter(r=>Number(r.permutation)===p).sort((a,b)=>a.sampleSize-b.sampleSize),c=colors[i%colors.length];svg+=`<polyline fill="none" stroke="${c}" stroke-width="2.5" points="${group.map(r=>`${x(r.sampleSize)},${y(r.value)}`).join(' ')}"/>`;group.forEach(r=>svg+=`<circle data-synth-analysis="${r.analysisIndex}" cx="${x(r.sampleSize)}" cy="${y(r.value)}" r="5" fill="${c}" tabindex="0" role="button"><title>N=${r.sampleSize}, permutation ${p}: ${r.value}</title></circle>`);});
 svg+='</svg>';
 const legend=perms.map((p,i)=>`<span style="color:${colors[i%colors.length]}">● Permutation ${p}</span>`).join(' · ');
 root.innerHTML=`<h3>Learning curve — ${esc(criterion.label)}</h3><p>Observed N=${payload.observedN} · ${rows.length} completed analyses · ${esc(payload.status)}</p>${svg}<p>${legend}</p><p>Cumulative cohort size (N) · ${esc(criterion.label)}</p><table class="rvTable"><thead><tr><th>Analysis</th><th>Total N</th><th>Permutation</th><th>${esc(criterion.shortLabel)}</th></tr></thead><tbody>${rows.map(r=>`<tr><td><button type="button" data-synth-analysis="${r.analysisIndex}">${r.analysisIndex}</button></td><td>${r.sampleSize}</td><td>${r.permutation}</td><td>${Number(r.value).toPrecision(5)}</td></tr>`).join('')}</tbody></table>`;
 root.querySelectorAll('[data-synth-analysis]').forEach(node=>{node.addEventListener('click',()=>onAnalysis(Number(node.dataset.synthAnalysis)));if(node.tagName.toLowerCase()==='circle')node.addEventListener('keydown',e=>{if(e.key==='Enter')onAnalysis(Number(node.dataset.synthAnalysis));});});
}
global.NMResultsViewerSynth={render};
})(window);
