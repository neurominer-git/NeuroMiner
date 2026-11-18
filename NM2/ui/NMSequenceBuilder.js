/* Prognostic sequence builder: display-only source catalogue, numeric C output.
 * The stacking configurator owns the source order; this module never selects analyses.
 */
const NMSequenceBuilder = (() => {
    const PAGE_SIZE = 8;
    const MAX_CANDIDATES = 5000;
    let active = null;
    const elem = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;
        return e;
    };
    const nodesFromCatalog = (catalog) => Array.isArray(catalog) ? catalog : catalog ? [catalog] : [];
    const caption = (source) => source.parts === 1 ? `#${source.analysis}` : `#${source.analysis}.${source.part}`;
    const matrixRows = (matrix) => {
        const numeric = typeof matrix === 'number' ? [[matrix]] : Array.isArray(matrix) && Array.isArray(matrix[0]) ? matrix : Array.isArray(matrix) ? [matrix] : [];
        return numeric.map(row => {
            const nodes=[];let ended=false,malformed=false;
            for(const value of row){
                if(Number.isInteger(value)&&value>0){if(ended)malformed=true;nodes.push(value);}
                else {ended=true;if(value!==null&&value!==0&&!Number.isNaN(value))malformed=true;}
            }
            return {nodes,included:true,malformed};
        });
    };
    const permutations = (n, low, high) => {
        let total = 0;
        for (let k = low; k <= high; k++) {
            let term = 1;
            for (let j = 0; j < k; j++) term *= n-j;
            total += term;
        }
        return total;
    };
    const duplicates = (rows) => {
        const seen = new Map(), duplicate = new Set();
        rows.forEach((row, i) => {
            if (!row.included || !row.nodes.length) return;
            const key = row.nodes.join(',');
            if (seen.has(key)) { duplicate.add(seen.get(key)); duplicate.add(i); }
            else seen.set(key,i);
        });
        return duplicate;
    };
    function note(text, kind) {
        active.message.textContent = text;
        active.message.className = 'nmsb-message ' + kind;
        active.status(text, kind === 'error' ? 'danger' : kind === 'warning' ? 'warn' : 'info');
    }
    function field(matrix, sourceCatalog, commit, status) {
        const sources = nodesFromCatalog(sourceCatalog);
        const root = elem('div','nmsb-field');
        const summary = elem('span','nmsb-summary');
        const parsed = matrixRows(matrix);
        const currentCount = parsed.filter(row => row.nodes.length && row.nodes.every(node => sources.some(source => source.node === node))).length;
        summary.textContent = `${currentCount} candidate sequence${currentCount === 1 ? '' : 's'} · ${sources.length} available prediction source${sources.length === 1 ? '' : 's'}`;
        const button = elem('button','nmsb-open','Edit sequences…');
        button.type = 'button';
        button.disabled = sources.length === 0;
        button.onclick = () => open(matrix, sources, (value) => { commit(value); summary.textContent = `${value.length} candidate sequences · ${sources.length} available prediction sources`; }, status);
        root.append(summary,button);
        if (!sources.length) root.append(elem('div','muted','Select completed first-level analyses in Stacking to configure prognostic sequences.'));
        return root;
    }
    function open(matrix, catalog, commit, status) {
        if (active) throw new Error('A sequence editor is already open.');
        const sourceByNode = new Map(catalog.map(source => [source.node,source]));
        const old = matrixRows(matrix);
        const invalid = old.length === 0 || old.some(row => row.malformed || row.nodes.length === 0 || row.nodes.length !== new Set(row.nodes).size || row.nodes.some(n => !sourceByNode.has(n)));
        const rows = invalid ? [] : old;
        const overlay = elem('div','nmsb-overlay');
        overlay.setAttribute('role','dialog');overlay.setAttribute('aria-modal','true');overlay.setAttribute('aria-label','Prognostic Sequence Builder');
        overlay.innerHTML = `<section class="nmsb-dialog"><header class="nmsb-head"><div><small>Machine learning · Sequential optimization</small><h2>Prognostic Sequence Builder</h2><p>Generate and arrange candidate prediction sequences</p></div><button type="button" class="nmsb-close" aria-label="Close sequence builder">×</button></header><div class="nmsb-message" role="status" aria-live="polite"></div><div class="nmsb-columns"><main class="nmsb-body"><section class="nmsb-generator"><h3>Generate candidate sequences</h3><div class="nmsb-controls"><label>Minimum length<select data-role="min"></select></label><label>Maximum length<select data-role="max"></select></label><button type="button" data-role="generate">Generate all permutations</button><strong data-role="estimate"></strong></div></section><section class="nmsb-sources"><div class="nmsb-sourcehead"><h3>Available prediction sources</h3><button type="button" data-role="stacking">Edit stacking analyses ↗</button></div><p>Drag a source into a sequence row. The numbers refer to completed analyses.</p><div data-role="sources" class="nmsb-sourcecards"></div></section><section class="nmsb-matrix"><div class="nmsb-sourcehead"><h3>Candidate sequence matrix</h3><span data-role="rows-count"></span></div><div class="nmsb-matrixhead"><span>Include · Sequence</span><span>Prediction order (drag to rearrange)</span></div><div data-role="rows" class="nmsb-rows"></div><div class="nmsb-matrixactions"><button type="button" data-role="add-row">+ Add empty sequence</button></div><div class="nmsb-pages"><span data-role="page-info"></span><label data-role="all-label"><input type="checkbox" data-role="all"> Show all sequences</label><button type="button" data-role="prev">‹ Previous</button><button type="button" data-role="next">Next ›</button></div></section></main><aside class="nmsb-help"><h3>ⓘ Context help</h3><p>Each row is a candidate order in which previously trained models are consulted. The optimizer may defer a decision to the next model.</p><h4>Analysis cards</h4><p>Card numbers are actual analysis indices. Hover or focus a card to inspect its description and completion status. Multiple prediction sources from one analysis are numbered separately.</p><h4>Reorder and remove</h4><p>Drag cards within a row or use Alt + Left/Right. Drag a card onto the adjacent trash icon to remove that card. Use × beside S1, S2, etc., to delete a whole sequence. Add empty rows for manual sequence building.</p><h4>Inclusion</h4><p>Uncheck a sequence to exclude it from optimization without deleting it from the editor. Included sequences must be unique.</p><h4>Generate</h4><p>Choose a minimum and maximum length to generate every ordered permutation without repeating a prediction source. Generating replaces current row edits.</p><h4>Stacking</h4><p>The Stacking configuration determines which models are available. Changing those models makes the previous sequences out of date.</p><h4>Computational cost</h4><p>Each included sequence is a candidate hyperparameter. The search grows rapidly with the number of sources. Generation is limited to 5,000 candidates in this editor.</p></aside></div><footer class="nmsb-footer"><span data-role="summary"></span><div><button type="button" data-role="cancel">Cancel</button><button type="button" data-role="apply" class="primary">Apply sequences</button></div></footer></section>`;
        const find = key => overlay.querySelector(`[data-role="${key}"]`);
        document.body.append(overlay);
        const n = catalog.length;
        active = {overlay, message:overlay.querySelector('.nmsb-message'),status,rows,sourceByNode,page:0,all:false,pointer:null,min:1,max:n,commit,find};
        const close = () => { overlay.remove(); active=null; };
        overlay.querySelector('.nmsb-close').onclick=close;
        find('cancel').onclick=close;
        find('stacking').onclick=()=>{close();window.parent.postMessage({type:'nm-sequence-open-stacking'},'*');};
        find('all').onchange=e=>{active.all=e.target.checked;render();};
        find('prev').onclick=()=>{active.page--;render();};
        find('next').onclick=()=>{active.page++;render();};
        find('add-row').onclick=()=>{active.rows.push({nodes:[],included:true});active.all=false;find('all').checked=false;active.page=Math.floor((active.rows.length-1)/PAGE_SIZE);render();};
        for (const key of ['min','max']) {
            const select=find(key);
            for (let k=1;k<=n;k++) {const option=elem('option','',String(k));option.value=String(k);select.append(option);}
            select.value=key==='min'?'1':String(n);
            select.onchange=e=>{active[key]=Number(e.target.value);if(active.min>active.max){active[key==='min'?'max':'min']=active[key];find(key==='min'?'max':'min').value=e.target.value;}renderEstimate();};
        }
        function renderEstimate() {
            const count=permutations(n,active.min,active.max);
            find('estimate').textContent=count.toLocaleString()+' possible sequences';
            find('generate').disabled=count>MAX_CANDIDATES;
            if(count>MAX_CANDIDATES) note('This selection would generate more than 5,000 sequences. Reduce the length range before generating.','warning');
        }
        function generateRows() {
            const result=[];
            function visit(prefix, used, target) {
                if(prefix.length===target) {result.push({nodes:prefix,included:true});return;}
                for (const source of catalog) if(!used.has(source.node)) {
                    const next = new Set(used);next.add(source.node);
                    visit([...prefix,source.node],next,target);
                }
            }
            for(let k=active.min;k<=active.max;k++)visit([],new Set(),k);
            return result;
        }
        find('generate').onclick=()=>{
            active.rows=generateRows();active.page=0;render();note(`Generated ${active.rows.length} candidate sequences. Review the selection before applying.`,'info');
        };
        // Pointer-based card movement also works in embedded browser hosts where
        // native HTML drag-and-drop does not dispatch reliably.
        function clearPointer() {
            const p=active.pointer;
            if (!p) return;
            if (p.ghost) p.ghost.remove();
            p.chip.classList.remove('nmsb-dragging');
            overlay.querySelectorAll('.nmsb-drop-hover').forEach(el=>el.classList.remove('nmsb-drop-hover'));
            active.pointer=null;
        }
        function move(drag,row,index) {
            if (drag.row>=0 && drag.row!==row) {
                note('To add this analysis to another sequence, drag it from Available prediction sources.','warning');
                return;
            }
            const target=active.rows[row].nodes;
            if(drag.row===row) {
                target.splice(drag.index,1);
                target.splice(index,0,drag.node);
            } else if(!target.includes(drag.node)) {
                target.splice(index,0,drag.node);
            } else {
                note(`Sequence S${row+1} already contains this analysis.`, 'warning');
                return;
            }
            render();
        }
        function remove(row,index) {
            active.rows[row].nodes.splice(index,1);
            render();
        }
        function card(source,row,index) {
            const button=elem('button','nmsb-chip',caption(source));button.type='button';
            button.title=source.description+'\n'+(source.completed?'Analysis completed':'Completion status unavailable')+'\nPerformance: inspect in Results Viewer';
            button.setAttribute('aria-label',button.title);
            button.dataset.index=String(index);
            button.onpointerdown=e=>{
                if(e.button!==0) return;
                active.pointer={chip:button,node:source.node,row,index,x:e.clientX,y:e.clientY,started:false,ghost:null};
                button.setPointerCapture(e.pointerId);
            };
            button.onpointermove=e=>{
                const p=active.pointer;
                if(!p || p.chip!==button) return;
                if(!p.started && Math.hypot(e.clientX-p.x,e.clientY-p.y)<5) return;
                if(!p.started){
                    p.started=true;
                    p.ghost=elem('div','nmsb-chip nmsb-ghost',caption(source));
                    overlay.append(p.ghost);
                    button.classList.add('nmsb-dragging');
                }
                p.ghost.style.left=(e.clientX+12)+'px';
                p.ghost.style.top=(e.clientY+12)+'px';
                overlay.querySelectorAll('.nmsb-drop-hover').forEach(el=>el.classList.remove('nmsb-drop-hover'));
                const hit=document.elementFromPoint(e.clientX,e.clientY);
                const landing=hit && hit.closest('.nmsb-trash, .nmsb-chip, .nmsb-rowcards');
                if(landing) landing.classList.add('nmsb-drop-hover');
            };
            button.onpointerup=e=>{
                const p=active.pointer;
                if(!p || p.chip!==button) return;
                const hit=p.started && document.elementFromPoint(e.clientX,e.clientY);
                const landing=hit && hit.closest('.nmsb-trash, .nmsb-rowcards');
                const targetChip=hit && hit.closest('.nmsb-rowcards .nmsb-chip');
                const rowBox=landing || (targetChip && targetChip.closest('.nmsb-rowcards'));
                const rowIndex=rowBox?Number(rowBox.dataset.row):-1;
                const targetIndex=targetChip?Number(targetChip.dataset.index):rowIndex>=0?active.rows[rowIndex].nodes.length:-1;
                const isTrash=landing && landing.classList.contains('nmsb-trash');
                clearPointer();
                if(!rowBox || rowIndex<0) return;
                if(isTrash){if(p.row===rowIndex)remove(rowIndex,p.index);return;}
                move(p,rowIndex,targetIndex);
            };
            button.onpointercancel=clearPointer;
            if(row>=0){
                button.onkeydown=e=>{
                    if(e.altKey&&(e.key==='ArrowLeft'||e.key==='ArrowRight')){
                        e.preventDefault();const to=index+(e.key==='ArrowLeft'?-1:1);
                        if(to>=0&&to<active.rows[row].nodes.length)move({row,index,node:source.node},row,to);
                    }
                    if(e.key==='Delete'){e.preventDefault();remove(row,index);}
                };
            }
            return button;
        }
        function render() {
            const pane=find('rows');pane.replaceChildren();
            find('sources').replaceChildren(...catalog.map(source=>card(source,-1,-1)));
            const rows=active.rows,dups=duplicates(rows);
            const pageCount=Math.max(1,Math.ceil(rows.length/PAGE_SIZE));
            active.page=Math.min(active.page,pageCount-1);
            const start=active.all?0:active.page*PAGE_SIZE;
            const end=active.all?rows.length:Math.min(rows.length,start+PAGE_SIZE);
            for(let i=start;i<end;i++) {
                const item=rows[i], line=elem('div','nmsb-sequence'+(dups.has(i)?' nmsb-duplicate':'')+(item.included?'':' nmsb-excluded'));
                const heading=elem('label','nmsb-rowlabel');const check=elem('input');check.type='checkbox';check.checked=item.included;
                check.onchange=()=>{item.included=check.checked;render();};
                const deleteRow=elem('button','nmsb-delete-row','×');deleteRow.type='button';deleteRow.title=`Delete sequence S${i+1}`;deleteRow.setAttribute('aria-label',deleteRow.title);
                deleteRow.onclick=()=>{rows.splice(i,1);render();};
                heading.append(check,elem('b','',`S${i+1}`),deleteRow);
                const items=elem('div','nmsb-rowcards');items.dataset.row=String(i);
                item.nodes.forEach((node,index)=>{
                    if(index)items.append(elem('span','nmsb-arrow','→'));
                    items.append(card(sourceByNode.get(node),i,index));
                });
                if(!item.nodes.length)items.append(elem('span','nmsb-empty','Drop an analysis here'));
                const trash=elem('div','nmsb-trash');trash.dataset.row=String(i);trash.title='Drag an analysis here to remove it from this sequence';
                trash.innerHTML='<svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M8 6V4h8v2M5 6l1 14h12l1-14M10 10v7m4-7v7"/></svg>';
                line.append(heading,items,trash);pane.append(line);
            }
            find('rows-count').textContent=`${rows.length} rows`;
            find('page-info').textContent=active.all?`Showing all ${rows.length} sequences`:`Showing ${rows.length?start+1:0}–${end} of ${rows.length}`;
            find('all-label').hidden=rows.length<=PAGE_SIZE;
            find('prev').hidden=active.all||pageCount===1;find('next').hidden=active.all||pageCount===1;
            find('prev').disabled=active.page===0;find('next').disabled=active.page>=pageCount-1;
            const selected=rows.filter(r=>r.included).length;
            find('summary').textContent=`${selected} included · ${dups.size} duplicate rows`;
            if(dups.size) note('Some included sequences are identical. Change their order or exclude duplicates before applying.','warning');
            else if(active.message.classList.contains('warning') && active.message.textContent.startsWith('Some included sequences')) note('The duplicate sequences have been resolved.','info');
        }
        find('apply').onclick=()=>{
            const rows=active.rows.filter(row=>row.included);
            if(!rows.length){note('Include at least one sequence before applying.','error');return;}
            const empty=active.rows.findIndex(row=>row.included&&!row.nodes.length);
            if(empty>=0){note(`Sequence S${empty+1} is empty. Add a prediction source, exclude it, or delete the row before applying.`,'error');return;}
            if(duplicates(active.rows).size){note('Identical included sequences cannot be applied. Change their order or exclude duplicates.','error');return;}
            const width=Math.max(...rows.map(row=>row.nodes.length));
            // Zero is a browser transport sentinel for NaN padding; the ML owner restores NaN.
            const C=rows.map(row=>[...row.nodes,...Array(width-row.nodes.length).fill(0)]);
            active.commit(C);
            close();
        };
        renderEstimate();
        if (invalid && permutations(n,1,n) <= MAX_CANDIDATES) {
            active.rows=generateRows();
            render();
            note('Your previous sequences no longer match the selected prediction sources. A replacement set was generated; review and apply it to save.','warning');
        } else {
            render();
            if(invalid) note('Your saved sequences do not match the current prediction sources. Select a shorter sequence range and generate a new set.','warning');
        }
    }
    return {field};
})();
