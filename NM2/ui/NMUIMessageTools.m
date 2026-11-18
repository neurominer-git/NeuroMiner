classdef NMUIMessageTools
% NMUIMessageTools
% Shared browser notification authority for NM2 windows.
% The active page/modal header displays the current message. No strip overlays
% or displaces controls. Progress windows own their local progress display.

    methods (Static)
        function txt = css()
            L = { ...
'#nmMessageHeaderButton{flex:0 0 auto;display:inline-flex;align-items:center;justify-content:center;width:34px;height:32px;padding:3px;border:1px solid currentColor!important;border-radius:7px;background:transparent!important;color:inherit!important;cursor:pointer;vertical-align:middle}'
'.nmMessageHeaderActions{display:inline-flex;align-items:center;gap:8px;margin-left:auto;flex:0 0 auto}'
'#nmMessageHeaderButton svg{display:block;width:24px;height:24px}'
'#nmMessageHeaderButton:hover,#nmMessageHeaderButton:focus-visible{outline:2px solid currentColor;outline-offset:2px;background:rgba(127,127,127,.12)!important}'
'.nmMessageHeader-danger{background:var(--nm-danger-soft,#fcecec)!important;color:var(--nm-danger,#85242b)!important}'
'.nmMessageHeader-warn{background:var(--nm-warning-soft,#fff0d9)!important;color:var(--nm-warning,#82500e)!important}'
'html[data-nm-theme] header.nmMessageHeader-danger,html[data-nm-theme] .wbHeader.nmMessageHeader-danger,html[data-nm-theme] .rvHeader.nmMessageHeader-danger{background:color-mix(in srgb,var(--nm-header-bg) 60%,var(--nm-danger) 40%)!important;color:var(--nm-header-text)!important}'
'html[data-nm-theme] header.nmMessageHeader-warn,html[data-nm-theme] .wbHeader.nmMessageHeader-warn,html[data-nm-theme] .rvHeader.nmMessageHeader-warn{background:color-mix(in srgb,var(--nm-header-bg) 68%,var(--nm-warning) 32%)!important;color:var(--nm-header-text)!important}'
'#nmMessageTooltip{position:fixed;z-index:2147483646;display:none;box-sizing:border-box;width:340px;max-width:calc(100vw - 20px);padding:12px 14px;border:1px solid #b9c6d4;border-radius:8px;background:#fff;color:#172033;box-shadow:0 9px 24px #10182855;font:13px/1.5 system-ui,Arial,sans-serif;white-space:pre-wrap;pointer-events:none}'
'#nmMessageDetails{position:fixed;z-index:2147483647;inset:0;display:none;align-items:center;justify-content:center;padding:18px;background:rgba(15,23,42,.60)}'
'#nmMessageDetails.nmMessageOpen{display:flex}'
'#nmMessageDetails .nmMessageDialog{width:min(530px,100%);max-height:calc(100vh - 36px);display:flex;flex-direction:column;background:var(--nm-surface,#fff);color:var(--nm-text,#172033);border:1px solid var(--nm-border,#cbd5e1);border-radius:10px;box-shadow:0 14px 44px #0006}'
'#nmMessageDetails .nmMessageDialogHead{position:relative;display:flex;align-items:center;min-height:48px;box-sizing:border-box;padding:12px 44px 12px 16px;border-bottom:1px solid var(--nm-border,#cbd5e1);font-weight:700}'
'#nmMessageDetails .nmMessageDialogBody{padding:18px;overflow:auto;white-space:pre-wrap;overflow-wrap:anywhere;font:13px/1.55 system-ui,Arial,sans-serif}'
'#nmMessageDetails .nmMessageDialogClose{position:absolute;top:8px;right:8px;display:grid;place-items:center;box-sizing:border-box;border:1px solid var(--nm-border,#cbd5e1);background:transparent;color:inherit;border-radius:999px;width:28px;height:28px;min-width:28px;padding:0;font:600 20px/1 system-ui,Arial,sans-serif;cursor:pointer}'
'#nmMessageDetails.nmMessageDetail-danger .nmMessageDialogHead{background:var(--nm-danger-soft,#fcecec);color:var(--nm-danger,#85242b)}'
'#nmMessageDetails.nmMessageDetail-warn .nmMessageDialogHead{background:var(--nm-warning-soft,#fff0d9);color:var(--nm-warning,#82500e)}'
'#nmMessageDetails .nmMessageDialogClose:focus-visible{outline:2px solid var(--nm-accent,#376b91)}'
};
            txt = strjoin(L, newline);
        end

        function txt = script()
            L = { ...
'(function(){'
'  const INFO_MS=4000,WARN_MS=10000,CONTROL_ID="nmMessageHeaderButton";'
'  const MODALS=["[role=dialog][aria-modal=true]",".nmModalDialog",".taskModalPage.active > .taskModalBox",".selectorOverlay:not(.hidden) > :first-child",".modal.open > .modalBox",".selectorModal.open > .selectorBox",".modalBackdrop > :first-child",".rvModalOverlay > .rvModalCard",".rvImagingModal > .rvImagingModalCard",".rvScientificAnnotationOverlay > :first-child"];'
'  const HEADERS=[".nmModalHead",".modalHead",".selectorHead",".modalHeader",".taskModalHead",".rvReportBuilderHead",".rvScientificAnnotationHead",".rvImagingTopbar","header","h1","h2","h3"];'
'  const empty=()=>({text:"",level:"info",source:"",fingerprint:""});'
'  let state=empty(),audit=empty(),suspended=null,owner=null,timer=null,observer=null,scheduled=false,control=null,tip=null,detail=null,painted="";'
'  function activeState(){return state.text&&state.level==="danger"?state:audit.text?audit:state;}'
'  function normalizeLevel(x){x=String(x||"info").toLowerCase();return x==="danger"||x==="error"?"danger":x==="warn"||x==="warning"?"warn":x==="success"||x==="ok"?"ok":"info";}'
'  function labelForLevel(x){return {danger:"Error",warn:"Warning",info:"Information",ok:"Success"}[normalizeLevel(x)];}'
'  function delayFor(x){return x==="danger"?0:x==="warn"?WARN_MS:INFO_MS;}'
'  function clearTimer(){if(timer)clearTimeout(timer);timer=null;}'
'  function visible(el){if(!el||!el.isConnected||el.hidden||el.getAttribute("aria-hidden")==="true")return false;const cs=getComputedStyle(el);return cs.display!=="none"&&cs.visibility!=="hidden"&&el.getClientRects().length>0;}'
'  function zIndex(el){let z=0;for(let p=el;p;p=p.parentElement){const n=Number(getComputedStyle(p).zIndex);if(Number.isFinite(n))z=Math.max(z,n);}return z;}'
'  function depth(el){let n=0;for(let p=el;p;p=p.parentElement)n++;return n;}'
'  function activeModal(){const found=new Set(),candidates=[];MODALS.forEach(sel=>document.querySelectorAll(sel).forEach(el=>{if(found.has(el)||el.closest("[data-nm-message-skip],#nmMessageDetails")||!visible(el))return;found.add(el);candidates.push({el,z:zIndex(el),depth:depth(el)});}));candidates.sort((a,b)=>a.z-b.z||a.depth-b.depth);return candidates.length?candidates[candidates.length-1].el:null;}'
'  function headerFor(owner){if(owner){const children=Array.from(owner.children);for(const sel of HEADERS){const h=children.find(el=>el.matches(sel));if(h)return h;}return null;}return Array.from(document.body.children).find(el=>el.matches("header,.wbHeader,.rvHeader"))||null;}'
'  function icon(level){const head=''<svg viewBox="0 0 32 32" aria-hidden="true" xmlns="http://www.w3.org/2000/svg">'';if(level==="danger")return head+''<path d="M10 2H22L30 10V22L22 30H10L2 22V10Z" fill="#C4313B"/><path d="M12 12L20 20M20 12L12 20" stroke="#fff" stroke-width="3" stroke-linecap="round"/></svg>'';if(level==="warn")return head+''<path d="M16 2L30 28H2Z" fill="#E49624" stroke="#A9650B"/><path d="M16 11V19" stroke="#fff" stroke-width="3" stroke-linecap="round"/><circle cx="16" cy="23.5" r="1.7" fill="#fff"/></svg>'';if(level==="ok")return head+''<circle cx="16" cy="16" r="14" fill="#268357"/><path d="M9 16L14 21L23 11" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>'';return head+''<circle cx="16" cy="16" r="14" fill="#3578AE"/><path d="M16 14V23" stroke="#fff" stroke-width="3" stroke-linecap="round"/><circle cx="16" cy="9" r="1.8" fill="#fff"/></svg>'';}'
'  function ensureUI(){'
'    if(control)return;'
'    control=document.createElement("button");control.id=CONTROL_ID;control.type="button";control.setAttribute("aria-haspopup","dialog");control.setAttribute("aria-describedby","nmMessageTooltip");'
'    tip=document.createElement("div");tip.id="nmMessageTooltip";tip.setAttribute("role","tooltip");document.body.appendChild(tip);'
'    detail=document.createElement("div");detail.id="nmMessageDetails";'
'    detail.innerHTML=''<section class="nmMessageDialog" role="dialog" aria-modal="true" aria-labelledby="nmMessageDetailTitle"><div class="nmMessageDialogHead"><span id="nmMessageDetailTitle"></span><button class="nmMessageDialogClose" type="button" aria-label="Close notification">&#215;</button></div><div class="nmMessageDialogBody"></div></section>'';'
'    document.body.appendChild(detail);'
'    control.addEventListener("mouseenter",showTip);control.addEventListener("focus",showTip);'
'    control.addEventListener("mouseleave",hideTip);control.addEventListener("blur",hideTip);'
'    control.addEventListener("click",()=>{hideTip();clearTimer();detail.classList.add("nmMessageOpen");detail.querySelector(".nmMessageDialogClose").focus();});'
'    detail.querySelector(".nmMessageDialogClose").addEventListener("click",closeDetail);'
'    window.addEventListener("keydown",ev=>{if(!detail.classList.contains("nmMessageOpen"))return;if(ev.key==="Escape"){ev.preventDefault();ev.stopImmediatePropagation();closeDetail();}else if(ev.key==="Tab"){ev.preventDefault();ev.stopImmediatePropagation();detail.querySelector(".nmMessageDialogClose").focus();}},true);'
'  }'
'  function closeDetail(){detail.classList.remove("nmMessageOpen");if(control.isConnected)control.focus();const shown=activeState(),fingerprint=state.fingerprint,delay=shown===state?delayFor(state.level):0;if(delay)timer=setTimeout(()=>{if(state.fingerprint===fingerprint)clearMessage(state.source);},delay);}'
'  function hideTip(){if(tip)tip.style.display="none";}'
'  function showTip(){if(!activeState().text||!control.isConnected)return;const r=control.getBoundingClientRect();tip.style.display="block";const w=tip.getBoundingClientRect().width;tip.style.left=Math.max(10,Math.min(innerWidth-w-10,r.right-w))+"px";const th=tip.getBoundingClientRect().height;tip.style.top=(r.bottom+th+10<innerHeight?r.bottom+8:Math.max(10,r.top-th-8))+"px";}'
'  function undecorate(){if(owner){owner.classList.remove("nmMessageHeader-danger","nmMessageHeader-warn");owner=null;}if(control&&control.parentNode)control.remove();hideTip();}'
'  function headerActions(h){'
'    let a=h.querySelector(":scope > .headerActions, :scope > .nmMessageHeaderActions");'
'    if(a)return a;'
'    a=document.createElement("div");a.className="nmMessageHeaderActions";'
'    while(h.children.length>1)a.appendChild(h.children[1]);'
'    h.appendChild(a);return a;'
'  }'
'  function syncOwner(){'
'    if(embedded()){undecorate();return;}'
'    if(state.source==="nm-embedded-editor"&&!Array.from(document.querySelectorAll("iframe")).some(f=>visible(f)&&f.closest(".modal.open,.selectorOverlay:not(.hidden),[role=dialog]"))){clearMessage("nm-embedded-editor");return;}'
'    const shown=activeState(),h=headerFor(activeModal());'
'    if(!shown.text||!h){undecorate();painted="";if(detail)detail.classList.remove("nmMessageOpen");return;}'
'    ensureUI();'
'    if(owner!==h){undecorate();owner=h;const a=headerActions(h);a.insertBefore(control,a.firstChild);}'
'    h.classList.toggle("nmMessageHeader-danger",shown.level==="danger");h.classList.toggle("nmMessageHeader-warn",shown.level==="warn");'
'    if(painted===shown.fingerprint)return;painted=shown.fingerprint;'
'    control.innerHTML=icon(shown.level);control.setAttribute("aria-label",labelForLevel(shown.level)+": "+shown.text);'
'    tip.textContent=labelForLevel(shown.level)+"\n"+(shown.text.length>320?shown.text.slice(0,320)+"…":shown.text)+"\nClick for full details.";'
'    detail.classList.remove("nmMessageDetail-danger","nmMessageDetail-warn");if(shown.level==="danger"||shown.level==="warn")detail.classList.add("nmMessageDetail-"+shown.level);'
'    detail.querySelector("#nmMessageDetailTitle").textContent=labelForLevel(shown.level);detail.querySelector(".nmMessageDialogBody").textContent=shown.text;'
'  }'
'  function scheduleSync(){if(scheduled)return;scheduled=true;requestAnimationFrame(()=>{scheduled=false;syncOwner();});}'
'  function embedded(){return window.parent!==window&&document.body.classList.contains("embedded");}'
'  function clearMessage(source){'
'    const src=String(source||"");'
'    if(src==="nm-audit"){audit=empty();syncOwner();return true;}'
'    if(src&&state.source&&src!==state.source)return false;'
'    const restore=src==="nm-embedded-editor"?suspended:null;suspended=null;clearTimer();state=empty();'
'    if(embedded())window.parent.postMessage({type:"nm-ui-notification",text:""},"*");'
'    if(restore)setMessage(restore.text,restore.level,restore.source);else syncOwner();return true;'
'  }'
'  function setMessage(text,level,source){'
'    const msg=String(text||""),lvl=normalizeLevel(level),src=String(source||"");'
'    if(!msg)return clearMessage(src);'
'    const fingerprint=lvl+"|"+src+"|"+msg;'
'    if(src==="nm-audit"){audit={text:msg,level:lvl,source:src,fingerprint};syncOwner();return true;}'
'    if(state.fingerprint===fingerprint){syncOwner();return true;}'
'    if(src==="nm-embedded-editor"&&state.text&&state.source!==src)suspended={...state};else if(src!=="nm-embedded-editor")suspended=null;'
'    clearTimer();state={text:msg,level:lvl,source:src,fingerprint};'
'    if(embedded())window.parent.postMessage({type:"nm-ui-notification",text:msg,level:lvl},"*");'
'    else syncOwner();'
'    const delay=delayFor(lvl);if(delay)timer=setTimeout(()=>{if(state.fingerprint===fingerprint)clearMessage(src);},delay);return true;'
'  }'
'  function initialize(){if(observer)observer.disconnect();observer=new MutationObserver(scheduleSync);observer.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:["class","style","hidden","aria-hidden","open"]});syncOwner();}'
'  window.NMUIMessageTools={setMessage,clearMessage,syncOwner,normalizeLevel,labelForLevel,infoDurationMs:INFO_MS,warningDurationMs:WARN_MS};'
'  window.addEventListener("message",ev=>{const data=ev.data;if(!data||data.type!=="nm-ui-notification")return;const frame=Array.from(document.querySelectorAll("iframe")).find(f=>f.contentWindow===ev.source&&visible(f)&&f.closest(".modal.open,.selectorOverlay:not(.hidden),[role=dialog]"));if(!frame)return;if(!data.text){clearMessage("nm-embedded-editor");return;}const lvl=normalizeLevel(data.level);if(state.level==="danger"&&lvl!=="danger")return;setMessage(data.text,lvl,"nm-embedded-editor");});'
'  if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",initialize,{once:true});else initialize();'
'})();'
};
            txt = strjoin(L, newline);
        end

        function lvl = normalizedLevel(level)
            % normalizedLevel  Normalize a message severity value to the supported UI levels.

            lvl = lower(char(level));
            switch lvl
                case {'danger','error'}
                    lvl = 'danger';
                case {'warn','warning'}
                    lvl = 'warn';
                case {'ok','success'}
                    lvl = 'ok';
                otherwise
                    lvl = 'info';
            end
        end

        function lab = labelForLevel(level)
            % labelForLevel  Return a readable label for a message severity level.

            switch NMUIMessageTools.normalizedLevel(level)
                case 'danger'
                    lab = 'Error';
                case 'warn'
                    lab = 'Warning';
                case 'ok'
                    lab = 'Success';
                otherwise
                    lab = 'Info';
            end
        end
    end
end
