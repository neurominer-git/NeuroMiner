(function(global){
  'use strict';

  const CONFIG=global.NM_HTML_RELAY_CONFIG||{};
  const PORT=Number(CONFIG.port||0);
  if(!Number.isInteger(PORT)||PORT<1) throw new Error('NM2 html-relay requires a valid bridge port.');
  const BRIDGE_ORIGIN=`http://127.0.0.1:${PORT}`;
  // uihtml hosts its HTMLSource inside MATLAB's own frame hierarchy, so
  // window.top cannot identify the NM2 relay root. Root identity is assigned
  // explicitly by the MATLAB transport authority when materializing HTML.
  const ROOT=CONFIG.root===true;
  const PROXY_MARKER='NM2_HTML_RELAY_V1';
  const ZOOM_LEVELS=Object.freeze([0.5,0.67,0.75,0.8,0.9,1,1.1,1.25,1.5,1.75,2]);
  const RESOURCE_ROOT=String(CONFIG.resourceRoot);

  function normalizeZoom(value){
    const n=Number(value);
    if(!Number.isFinite(n))return 1;
    let best=ZOOM_LEVELS[0],distance=Math.abs(n-best);
    for(const level of ZOOM_LEVELS){
      const d=Math.abs(n-level);if(d<distance){best=level;distance=d;}
    }
    return best;
  }

  function virtualUrl(value){
    const raw=String(value&&value.url!==undefined?value.url:value||'');
    if(/^data:|^blob:/i.test(raw)) return raw;
    let u;
    try{u=new URL(raw,BRIDGE_ORIGIN+'/');}catch(error){throw new Error(`Invalid NM2 relay URL: ${raw}`);}
    if(!/^https?:$/i.test(u.protocol)) throw new Error(`Unsupported NM2 relay URL scheme: ${u.protocol}`);
    const host=String(u.hostname||'').toLowerCase();
    if(!['127.0.0.1','localhost','::1'].includes(host)) throw new Error(`NM2 html-relay rejects non-local URL: ${u.toString()}`);
    if(u.port&&Number(u.port)!==PORT) throw new Error(`NM2 html-relay URL uses unexpected bridge port ${u.port}.`);
    u.protocol='http:';u.hostname='127.0.0.1';u.port=String(PORT);
    return u.toString();
  }

  function supportingResourceUrl(value,target){
    const raw=String(value);
    if(raw.startsWith('results_imaging_cache/')) return new URL(`${RESOURCE_ROOT}${raw}`,global.location.href).toString();
    const source=new URL(target);
    const match=/^\/api\/progress\/([A-Za-z0-9_-]{1,128})$/.exec(source.pathname);
    if(!match)return '';
    const resource=new URL(`${RESOURCE_ROOT}progress/${match[1]}.json`,global.location.href);
    resource.searchParams.set('_',String(Date.now()));
    return resource.toString();
  }

  function bytesToBase64(bytes){
    if(!bytes||!bytes.length) return '';
    const chunk=0x8000,parts=[];
    for(let i=0;i<bytes.length;i+=chunk){
      const sub=bytes.subarray(i,Math.min(bytes.length,i+chunk));
      let s='';for(let j=0;j<sub.length;j++)s+=String.fromCharCode(sub[j]);parts.push(s);
    }
    return btoa(parts.join(''));
  }

  function base64ToBytes(text){
    const s=String(text||'');if(!s)return new Uint8Array(0);
    const bin=atob(s),out=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++)out[i]=bin.charCodeAt(i);
    return out;
  }

  async function bodyBase64(value){
    if(value===undefined||value===null) return '';
    if(typeof value==='string') return bytesToBase64(new TextEncoder().encode(value));
    if(value instanceof ArrayBuffer) return bytesToBase64(new Uint8Array(value));
    if(ArrayBuffer.isView(value)) return bytesToBase64(new Uint8Array(value.buffer,value.byteOffset,value.byteLength));
    if(value instanceof Blob) return bytesToBase64(new Uint8Array(await value.arrayBuffer()));
    if(value instanceof URLSearchParams) return bytesToBase64(new TextEncoder().encode(value.toString()));
    throw new Error(`Unsupported NM2 html-relay request body: ${Object.prototype.toString.call(value)}`);
  }

  function nextId(prefix,sequence){
    sequence.value+=1;
    return `${prefix}${Date.now().toString(36)}_${sequence.value.toString(36)}`;
  }

  function dispatchPagehide(){
    try{global.dispatchEvent(new PageTransitionEvent('pagehide',{persisted:false}));}
    catch(error){global.dispatchEvent(new Event('pagehide'));}
  }

  function createRootChannel(){
    let component=null,resolveReady,resolveLayout;
    const ready=new Promise(resolve=>{resolveReady=resolve;});
    const layoutReady=new Promise(resolve=>{resolveLayout=resolve;});
    const pending=new Map(),sequence={value:0};
    function attach(hc){
      if(component===hc)return;
      component=hc;resolveReady(hc);
      hc.addEventListener('NMRelayResponse',event=>{
        const payload=event&&event.Data||{},id=String(payload.id||'');
        const waiter=pending.get(id);if(!waiter)return;
        pending.delete(id);
        if(payload.error){waiter.reject(new TypeError(`NM2 relay request ${id}: ${payload.error}${payload.detail?'\nPython bridge traceback:\n'+payload.detail:''}`));return;}
        waiter.resolve(payload);
      });
      hc.addEventListener('NMRelayLifecycle',event=>{
        if(String(event&&event.Data||'')==='pagehide')dispatchPagehide();
      });
      hc.addEventListener('NMRelayGeometryApplied',event=>{
        if(!event.Data){resolveLayout();return;}
        const probe=global.document.createElement('div');
        probe.style.cssText='position:fixed;top:0;left:0;width:1px;height:100vh;opacity:0;pointer-events:none';
        global.document.body.appendChild(probe);
        new global.IntersectionObserver(([view],observer)=>{
          if(!view.isIntersecting)return;
          observer.disconnect();
          probe.remove();
          const clipped=Math.ceil(view.boundingClientRect.height/relayZoom-view.intersectionRect.height);
          if(clipped>2)hc.sendEventToMATLAB('NMRelayViewportClip',clipped);
          else resolveLayout();
        }).observe(probe);
      });
      // Positive startup handshake. Without this, a page can render from its
      // embedded state while all bridge-backed controls silently wait forever.
      // Browser screen geometry is reported in the same CSS/logical pixel
      // coordinate system used by the embedded Chromium renderer. This is
      // required because MATLAB Online can expose a different high-DPI
      // coordinate system through groot ScreenSize.
      hc.sendEventToMATLAB('NMRelayReady',{
        marker:PROXY_MARKER,
        availWidth:Number(global.screen.availWidth),
        availHeight:Number(global.screen.availHeight)
      });
    }
    async function request(payload,expectResponse=true){
      const hc=await ready,id=String(payload.id||nextId('r',sequence));
      payload.id=id;
      if(!expectResponse){hc.sendEventToMATLAB('NMRelayRequest',payload);return null;}
      return new Promise((resolve,reject)=>{
        pending.set(id,{resolve,reject});
        try{hc.sendEventToMATLAB('NMRelayRequest',payload);}catch(error){pending.delete(id);reject(error);}
      });
    }
    async function navigate(target){
      const hc=await ready;
      hc.sendEventToMATLAB('NMRelayNavigate',{target:String(target||'')});
    }
    async function setZoom(zoom){
      const hc=await ready;
      hc.sendEventToMATLAB('NMRelayZoom',{zoom:Number(zoom)});
    }
    return Object.freeze({attach,request,navigate,setZoom,layoutReady});
  }

  function createChildChannel(){
    const pending=new Map(),sequence={value:0};
    global.addEventListener('message',event=>{
      const data=event&&event.data||{};
      if(data.marker!==PROXY_MARKER||data.kind!=='response')return;
      const id=String(data.id||''),waiter=pending.get(id);if(!waiter)return;
      pending.delete(id);
      const payload=data.payload||{};
      if(payload.error){waiter.reject(new TypeError(`NM2 relay request ${id}: ${payload.error}${payload.detail?'\nPython bridge traceback:\n'+payload.detail:''}`));return;}
      waiter.resolve(payload);
    });
    async function request(payload,expectResponse=true){
      const id=String(payload.id||nextId('c',sequence));payload.id=id;
      if(expectResponse){
        return new Promise((resolve,reject)=>{
          pending.set(id,{resolve,reject});
          global.parent.postMessage({marker:PROXY_MARKER,kind:'request',id,payload,expectResponse:true},'*');
        });
      }
      global.parent.postMessage({marker:PROXY_MARKER,kind:'request',id,payload,expectResponse:false},'*');
      return null;
    }
    async function navigate(target){
      global.parent.postMessage({marker:PROXY_MARKER,kind:'navigate',target:String(target||'')},'*');
    }
    async function zoom(action){
      global.parent.postMessage({marker:PROXY_MARKER,kind:'zoom',action:String(action||'')},'*');
    }
    return Object.freeze({attach:function(){},request,navigate,setZoom:async function(){},zoom});
  }

  const channel=ROOT?createRootChannel():createChildChannel();
  if(ROOT){
    global.NM_HTML_RELAY_CHANNEL=channel;
    global.addEventListener('message',event=>{
      const data=event&&event.data||{};
      if(data.marker!==PROXY_MARKER||!event.source||event.source===global)return;
      if(data.kind==='request'){
        Promise.resolve(channel.request(data.payload||{},data.expectResponse!==false)).then(payload=>{
          if(data.expectResponse!==false)event.source.postMessage({marker:PROXY_MARKER,kind:'response',id:String(data.id||''),payload:payload||{}},'*');
        }).catch(error=>{
          event.source.postMessage({marker:PROXY_MARKER,kind:'response',id:String(data.id||''),payload:{id:String(data.id||''),error:String(error&&error.message||error)}},'*');
        });
      }else if(data.kind==='navigate'){
        channel.navigate(data.target).catch(error=>console.error('NM2 html-relay navigation failed',error));
      }else if(data.kind==='zoom'){
        const fn=global.NMHTMLRelayZoomAction;
        if(typeof fn==='function')fn(String(data.action||''));
      }
    });
  }

  // The HTML materializer declares the literal top-level setup(htmlComponent)
  // function required by uihtml and delegates it here after the document loads.
  global.NMHTMLRelaySetup=function(htmlComponent){if(ROOT)channel.attach(htmlComponent);};

  let relayZoom=normalizeZoom(CONFIG.zoom===undefined?1:CONFIG.zoom);
  function applyRelayZoom(value,notify){
    if(!ROOT&&notify){channel.zoom(value).catch(error=>console.error('NM2 html-relay child zoom forwarding failed',error));return;}
    relayZoom=normalizeZoom(value);
    global.document.documentElement.style.zoom=String(relayZoom);
    global.NM_HTML_RELAY_ZOOM=relayZoom;
    if(ROOT&&notify){
      channel.setZoom(relayZoom).catch(error=>console.error('NM2 html-relay zoom persistence failed',error));
    }
  }
  function stepRelayZoom(direction){
    if(!ROOT){channel.zoom(direction<0?'out':'in').catch(error=>console.error('NM2 html-relay child zoom forwarding failed',error));return;}
    let index=ZOOM_LEVELS.indexOf(relayZoom);
    if(index<0){relayZoom=normalizeZoom(relayZoom);index=ZOOM_LEVELS.indexOf(relayZoom);}
    index=Math.max(0,Math.min(ZOOM_LEVELS.length-1,index+(direction<0?-1:1)));
    applyRelayZoom(ZOOM_LEVELS[index],true);
  }
  function relayZoomAction(action){
    if(action==='in')stepRelayZoom(1);
    else if(action==='out')stepRelayZoom(-1);
    else if(action==='reset')applyRelayZoom(1,true);
  }
  global.NMHTMLRelayZoomAction=relayZoomAction;
  function installRelayZoomControls(){
    applyRelayZoom(relayZoom,false);
    global.addEventListener('keydown',event=>{
      if(!(event.ctrlKey||event.metaKey)||event.altKey)return;
      const key=String(event.key||'');
      if(key==='+'||key==='='){
        event.preventDefault();stepRelayZoom(1);
      }else if(key==='-'||key==='_'){
        event.preventDefault();stepRelayZoom(-1);
      }else if(key==='0'){
        event.preventDefault();
        if(ROOT)applyRelayZoom(1,true);else channel.zoom('reset').catch(error=>console.error('NM2 html-relay child zoom forwarding failed',error));
      }
    },{capture:true});
    global.addEventListener('wheel',event=>{
      if(!(event.ctrlKey||event.metaKey)||event.altKey||event.deltaY===0)return;
      event.preventDefault();stepRelayZoom(event.deltaY<0?1:-1);
    },{capture:true,passive:false});
  }
  installRelayZoomControls();

  function applyVirtualTarget(){
    let target='';
    const h=String(global.location.hash||'');
    if(h.startsWith('#nmrelay=')){
      try{target=decodeURIComponent(h.slice('#nmrelay='.length));}catch(error){throw new Error(`Invalid NM2 relay navigation fragment: ${error.message||error}`);}
    }
    if(!target&&CONFIG.initialTarget)target=String(CONFIG.initialTarget);
    if(!target)return null;
    const u=new URL(target,BRIDGE_ORIGIN+'/');
    const local=`${global.location.pathname}${u.search||''}`;
    global.history.replaceState(global.history.state,'',local);
    return u;
  }
  const virtualTarget=applyVirtualTarget();
  let parentRunId='',parentClientId='';
  if(!ROOT){
    try{parentRunId=String(global.parent.NM_BRIDGE_RUNID||'');parentClientId=String(global.parent.NM_BRIDGE_CLIENTID||'');}catch(_){/* cross-origin child: requests still use the parent relay proxy */}
  }
  const currentParams=new URL(global.location.href).searchParams;
  global.NM_BRIDGE_RUNID=String(currentParams.get('runid')||(virtualTarget&&virtualTarget.searchParams.get('runid'))||parentRunId||'');
  global.NM_BRIDGE_CLIENTID=String(currentParams.get('clientid')||(virtualTarget&&virtualTarget.searchParams.get('clientid'))||parentClientId||'');
  global.NM_BRIDGE_EMBEDDED=String(currentParams.get('embedded')||(virtualTarget&&virtualTarget.searchParams.get('embedded'))||'')==='1';

  function localEmbeddedUrl(target){
    const u=new URL(String(target||''),BRIDGE_ORIGIN+'/');
    const rel=u.pathname.replace(/^\/+/, '');
    if(!rel||rel.split('/').some(part=>part==='..'))throw new Error(`Invalid NM2 relay navigation target: ${target}`);
    const base=new URL('./',global.location.href),local=new URL(rel,base);
    local.search='';local.hash=`nmrelay=${encodeURIComponent(u.pathname+(u.search||''))}`;
    return local.toString();
  }

  let navigationPending=false;
  global.NMBridgeAuthenticatedURL=function(value){return String(value||'');};
  global.NMBridgeNavigationURL=function(value){
    const target=virtualUrl(value),u=new URL(target);
    if(u.searchParams.get('embedded')==='1') return localEmbeddedUrl(u.pathname+u.search);
    if(!navigationPending){
      navigationPending=true;
      dispatchPagehide();
      global.setTimeout(()=>{channel.navigate(u.pathname+u.search).catch(error=>{navigationPending=false;console.error('NM2 html-relay navigation failed',error);});},100);
    }
    const hold=new URL(global.location.href);hold.hash='nmrelay-navigation-pending';return hold.toString();
  };

  async function awaitWithAbort(promise,signal){
    if(!signal)return promise;
    if(signal.aborted)throw new DOMException('The operation was aborted.','AbortError');
    return new Promise((resolve,reject)=>{
      const abort=()=>reject(new DOMException('The operation was aborted.','AbortError'));
      signal.addEventListener('abort',abort,{once:true});
      Promise.resolve(promise).then(value=>{signal.removeEventListener('abort',abort);resolve(value);},error=>{signal.removeEventListener('abort',abort);reject(error);});
    });
  }

  const nativeFetch=global.fetch.bind(global);
  global.fetch=async function(input,init){
    const raw=input instanceof Request?input.url:input;
    if(/^data:|^blob:/i.test(String(raw||''))) return nativeFetch(input,init);
    const target=virtualUrl(raw);
    let request;
    if(input instanceof Request){request=new Request(target,input);if(init)request=new Request(request,init);}else request=new Request(target,init||{});
    const method=String(request.method||'GET').toUpperCase();
    const resourceUrl=(method==='GET'||method==='HEAD')?supportingResourceUrl(raw,target):'';
    if(resourceUrl) return nativeFetch(new Request(resourceUrl,request));
    let payloadBody='';
    if(method!=='GET'&&method!=='HEAD')payloadBody=bytesToBase64(new Uint8Array(await request.clone().arrayBuffer()));
    const payload={url:request.url,method,headers:Array.from(request.headers.entries()),bodyBase64:payloadBody};
    const response=await awaitWithAbort(channel.request(payload,true),request.signal);
    const status=Number(response.status||0),headers=new Headers(Array.isArray(response.headers)?response.headers:[]);
    const body=(status===204||status===205||status===304)?null:base64ToBytes(response.bodyBase64||'');
    return new Response(body,{status:status||200,statusText:String(response.statusText||''),headers});
  };

  const relayBeacon=function(url,data){
    const target=virtualUrl(url);
    Promise.resolve().then(async()=>{
      const body=await bodyBase64(data);
      const type=data&&data.type?String(data.type):'application/octet-stream';
      await channel.request({url:target,method:'POST',headers:[['content-type',type]],bodyBase64:body,beacon:true},false);
    }).catch(error=>console.error('NM2 html-relay beacon failed',error));
    return true;
  };
  let beaconInstalled=false;
  try{
    Object.defineProperty(global.navigator,'sendBeacon',{configurable:true,value:relayBeacon});
    beaconInstalled=global.navigator.sendBeacon===relayBeacon;
  }catch(error){console.warn('NM2 html-relay could not replace navigator.sendBeacon on the navigator instance.',error);}
  if(!beaconInstalled){
    try{global.navigator.sendBeacon=relayBeacon;beaconInstalled=global.navigator.sendBeacon===relayBeacon;}
    catch(error){console.warn('NM2 html-relay could not assign navigator.sendBeacon.',error);}
  }
  if(!beaconInstalled) throw new Error('NM2 html-relay could not install the sendBeacon transport adapter.');

  global.NM_HTML_RELAY=true;
})(window);
