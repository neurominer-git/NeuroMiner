(function(){
  'use strict';

  /**
   * NMResultsViewerControlHost
   *
   * Pathway-neutral lifecycle and command-routing owner for generic Results
   * Viewer controls. G3A established payload selection, representation
   * selection, and viewport resize; G3B added display-control lifecycle; G3C
   * adds pathway-neutral view/navigation command routing through registered
   * controllers; G3D adds information-footer and extrema command routing.
   * The host stores no scientific, display, renderer, or
   * viewer-state semantics; pathway
   * adapters execute validated commands through one explicit handler.
   *
   * Contract: NM-RESULTS-VIEWER-CONTROL-HOST-V1
   * Failure policy: malformed registrations and unsupported capabilities or
   * commands throw NMResultsViewerControlHostError. Event-triggered failures
   * are routed to the mandatory onError callback.
   */

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-CONTROL-HOST-V1';
  const SUPPORTED_CAPABILITIES=Object.freeze([
    'payloadSelection',
    'representationSelection',
    'viewportResize',
    'threshold',
    'colourbar',
    'displayRange',
    'opacity',
    'zoom',
    'fit',
    'reset',
    'viewSync',
    'camera',
    'presentation3D',
    'geometryVariant',
    'clipping',
    'surfaceVisibility',
    'informationFooter',
    'extrema'
  ]);
  const COMMAND_CAPABILITY=Object.freeze({
    'payload.activate':'payloadSelection',
    'payload.toggle':'payloadSelection',
    'representation.select':'representationSelection',
    'viewport.resize':'viewportResize',
    'display.threshold.update':'threshold',
    'display.colourbar.update':'colourbar',
    'display.range.update':'displayRange',
    'display.opacity.update':'opacity',
    'view.zoom':'zoom',
    'view.fit':'fit',
    'view.reset':'reset',
    'view.sync.toggle':'viewSync',
    'camera.preset.select':'camera',
    'camera.projection.select':'camera',
    'presentation3d.montage.open':'presentation3D',
    'presentation3d.video.open':'presentation3D',
    'geometry.variant.select':'geometryVariant',
    'clipping.mode.select':'clipping',
    'clipping.link.toggle':'clipping',
    'clipping.position.useSelection':'clipping',
    'clipping.position.update':'clipping',
    'clipping.side.select':'clipping',
    'surface.visibility.select':'surfaceVisibility',
    'extrema.select':'extrema'
  });
  const HOSTS_BY_ROOT=new WeakMap();

  function controlHostError(code,message,details){
    const error=new Error(String(message||'Results Viewer control-host failure.')); // nm2-allow: NMResultsViewerControlHost.controlHostError is a public diagnostic constructor accepting omitted message and code.
    error.name='NMResultsViewerControlHostError';
    error.code=String(code||'NMResultsViewerControlHost:Failure'); // nm2-allow: NMResultsViewerControlHost.controlHostError is a public diagnostic constructor accepting omitted message and code.
    if(details!==undefined)error.details=details;
    return error;
  }

  function fail(code,message,details){
    throw controlHostError(code,message,details);
  }

  function isElementLike(value){
    return !!value&&typeof value.addEventListener==='function'&&typeof value.removeEventListener==='function'&&typeof value.contains==='function';
  }

  function requireElement(value,label){
    if(!isElementLike(value))fail('NMResultsViewerControlHost:InvalidElement',`${String(label||'Control region')} must be a live DOM element.`);
    return value;
  }

  function normalizeCapabilities(value){
    if(!Array.isArray(value)||!value.length)fail('NMResultsViewerControlHost:InvalidCapabilities','Control-host capabilities must be a non-empty array.');
    const seen=new Set(),out=[];
    value.forEach(raw=>{
      const capability=String(raw||''); // nm2-allow: NMResultsViewerControlHost validates caller-supplied capability and command text at the mounting and dispatch boundary.
      if(!SUPPORTED_CAPABILITIES.includes(capability))fail('NMResultsViewerControlHost:UnknownCapability',`Unsupported Results Viewer control capability: ${capability||'(empty)'}.`,{capability});
      if(seen.has(capability))fail('NMResultsViewerControlHost:DuplicateCapability',`Duplicate Results Viewer control capability: ${capability}.`,{capability});
      seen.add(capability);out.push(capability);
    });
    return Object.freeze(out);
  }

  function requireCommand(command){
    const name=String(command||''); // nm2-allow: NMResultsViewerControlHost validates caller-supplied capability and command text at the mounting and dispatch boundary.
    const capability=COMMAND_CAPABILITY[name];
    if(!capability)fail('NMResultsViewerControlHost:UnknownCommand',`Unsupported Results Viewer control command: ${name||'(empty)'}.`,{command:name});
    return {name,capability};
  }

  function commandCapability(command){return requireCommand(command).capability;}

  function immutableDetail(value){
    if(value===undefined||value===null)return Object.freeze({});
    if(typeof value!=='object'||Array.isArray(value))fail('NMResultsViewerControlHost:InvalidCommandDetail','Control command detail must be one plain object.');
    return Object.freeze(Object.assign({},value));
  }

  function closestWithin(region,eventTarget,selector){
    if(!eventTarget||typeof eventTarget.closest!=='function')return null;
    const target=eventTarget.closest(selector);
    return target&&region.contains(target)?target:null;
  }

  /** Mount exactly one control host for one representation root. */
  function mount(options){
    const cfg=options&&typeof options==='object'?options:{};
    const root=requireElement(cfg.root,'Control-host root');
    if(HOSTS_BY_ROOT.has(root))fail('NMResultsViewerControlHost:DuplicateMount','A Results Viewer control host is already mounted for this representation root.');
    if(typeof cfg.onCommand!=='function')fail('NMResultsViewerControlHost:MissingCommandHandler','Control-host mount requires one command handler.');
    if(typeof cfg.onError!=='function')fail('NMResultsViewerControlHost:MissingErrorHandler','Control-host mount requires one explicit error handler.');
    const capabilities=normalizeCapabilities(cfg.capabilities);
    const capabilitySet=new Set(capabilities);
    const registrations=new Map();
    let disposed=false;

    function assertMounted(){
      if(disposed)fail('NMResultsViewerControlHost:Unmounted','The Results Viewer control host has already been disposed.');
    }

    function assertCapability(capability){
      const name=String(capability||''); // nm2-allow: NMResultsViewerControlHost validates caller-supplied capability and command text at the mounting and dispatch boundary.
      if(!SUPPORTED_CAPABILITIES.includes(name))fail('NMResultsViewerControlHost:UnknownCapability',`Unsupported Results Viewer control capability: ${name||'(empty)'}.`,{capability:name});
      if(!capabilitySet.has(name))fail('NMResultsViewerControlHost:CapabilityNotDeclared',`Control capability ${name} was not declared by this representation host.`,{capability:name});
      return name;
    }

    /** Dispatch one validated, immutable command envelope to the adapter. */
    function dispatch(command,detail){
      assertMounted();
      const resolved=requireCommand(command);
      assertCapability(resolved.capability);
      const envelope=Object.freeze({
        contractVersion:CONTRACT_VERSION,
        command:resolved.name,
        capability:resolved.capability,
        detail:immutableDetail(detail)
      });
      return cfg.onCommand(envelope);
    }

    function reportEventFailure(error){
      const normalized=error instanceof Error?error:controlHostError('NMResultsViewerControlHost:CommandFailure',String(error));
      cfg.onError(normalized);
    }

    function dispatchFromEvent(command,detail){
      try{
        const result=dispatch(command,detail);
        if(result&&typeof result.then==='function')result.catch(reportEventFailure);
      }catch(error){ // nm2-allow: NMResultsViewerControlHost event and controller callback exceptions are reported through reportEventFailure at the DOM callback boundary.
        reportEventFailure(error);
      }
    }

    /** Register one delegated DOM-event region under a declared capability. */
    function registerRegion(spec){
      assertMounted();
      const regionSpec=spec&&typeof spec==='object'?spec:{};
      const id=String(regionSpec.id||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      if(!id)fail('NMResultsViewerControlHost:MissingRegistrationId','Control-region registration requires a non-empty id.');
      if(registrations.has(id))fail('NMResultsViewerControlHost:DuplicateRegistration',`Duplicate control-host registration id: ${id}.`,{id});
      const capability=assertCapability(regionSpec.capability);
      const region=requireElement(regionSpec.element,`Control region ${id}`);
      const eventType=String(regionSpec.eventType||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      const selector=String(regionSpec.selector||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      if(!eventType)fail('NMResultsViewerControlHost:MissingEventType',`Control region ${id} requires one event type.`,{id});
      if(!selector)fail('NMResultsViewerControlHost:MissingSelector',`Control region ${id} requires one delegated selector.`,{id});
      const command=String(regionSpec.command||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      const commandSpec=requireCommand(command);
      if(commandSpec.capability!==capability)fail('NMResultsViewerControlHost:CommandCapabilityMismatch',`Command ${command} requires capability ${commandSpec.capability}, not ${capability}.`,{id,command,capability});
      const detailFactory=regionSpec.detail;
      if(detailFactory!==undefined&&typeof detailFactory!=='function')fail('NMResultsViewerControlHost:InvalidDetailFactory',`Control region ${id} detail must be a function when provided.`,{id});
      const listener=event=>{
        const target=closestWithin(region,event&&event.target,selector);
        if(!target)return;
        if(target.disabled===true||target.getAttribute('aria-disabled')==='true')return;
        let detail={};
        try{detail=detailFactory?detailFactory(target,event):{};}catch(error){reportEventFailure(error);return;} // nm2-allow: NMResultsViewerControlHost event and controller callback exceptions are reported through reportEventFailure at the DOM callback boundary.
        dispatchFromEvent(command,detail);
      };
      region.addEventListener(eventType,listener);
      registrations.set(id,Object.freeze({id,kind:'region',dispose:()=>region.removeEventListener(eventType,listener)}));
      return id;
    }

    /** Register root viewport-resize lifecycle and coalesced command dispatch. */
    function registerViewport(spec){
      assertMounted();
      const viewportSpec=spec&&typeof spec==='object'?spec:{};
      const id=String(viewportSpec.id||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      if(!id)fail('NMResultsViewerControlHost:MissingRegistrationId','Viewport registration requires a non-empty id.');
      if(registrations.has(id))fail('NMResultsViewerControlHost:DuplicateRegistration',`Duplicate control-host registration id: ${id}.`,{id});
      const capability=assertCapability(viewportSpec.capability);
      if(capability!=='viewportResize')fail('NMResultsViewerControlHost:CommandCapabilityMismatch',`Viewport registration ${id} requires capability viewportResize.`,{id,capability});
      const element=requireElement(viewportSpec.element,`Viewport ${id}`);
      const observeElement=viewportSpec.observeElement===undefined?element:requireElement(viewportSpec.observeElement,`Viewport observer target ${id}`);
      const includeWindow=viewportSpec.includeWindow!==false;
      const detailFactory=viewportSpec.detail;
      if(detailFactory!==undefined&&typeof detailFactory!=='function')fail('NMResultsViewerControlHost:InvalidDetailFactory',`Viewport registration ${id} detail must be a function when provided.`,{id});
      let frame=0,observer=null,lastSource='initial';
      const requestFrame=typeof window.requestAnimationFrame==='function'?window.requestAnimationFrame.bind(window):(fn=>window.setTimeout(fn,0));
      const cancelFrame=typeof window.cancelAnimationFrame==='function'?window.cancelAnimationFrame.bind(window):(handle=>window.clearTimeout(handle));
      const flush=()=>{
        frame=0;
        if(disposed||!root.isConnected)return;
        let detail={source:lastSource};
        try{
          if(detailFactory)detail=Object.assign({source:lastSource},detailFactory(element,lastSource)||{}); // nm2-allow: NMResultsViewerControlHost accepts optional external detailFactory results during viewport-resize dispatch.
        }catch(error){reportEventFailure(error);return;} // nm2-allow: NMResultsViewerControlHost event and controller callback exceptions are reported through reportEventFailure at the DOM callback boundary.
        dispatchFromEvent('viewport.resize',detail);
      };
      const schedule=source=>{
        lastSource=source;
        if(frame)cancelFrame(frame);
        frame=requestFrame(flush);
      };
      const windowListener=()=>schedule('window');
      if(includeWindow)window.addEventListener('resize',windowListener);
      if(typeof window.ResizeObserver==='function'){
        observer=new window.ResizeObserver(()=>schedule('observer'));
        observer.observe(observeElement);
      }
      const disposeRegistration=()=>{
        if(frame){cancelFrame(frame);frame=0;}
        if(observer)observer.disconnect();
        if(includeWindow)window.removeEventListener('resize',windowListener);
      };
      registrations.set(id,Object.freeze({id,kind:'viewport',dispose:disposeRegistration}));
      if(viewportSpec.immediate!==false)schedule('mount');
      return id;
    }

    /**
     * Register one pathway-neutral controller whose event wiring is owned by
     * the controller and whose lifecycle and command boundary are owned by
     * this host.
     */
    function registerController(spec){
      assertMounted();
      const controllerSpec=spec&&typeof spec==='object'?spec:{},id=String(controllerSpec.id||''); // nm2-allow: NMResultsViewerControlHost registration accepts user-controller specs; absent required strings are rejected after conversion.
      if(!id)fail('NMResultsViewerControlHost:MissingRegistrationId','Control-controller registration requires a non-empty id.');
      if(registrations.has(id))fail('NMResultsViewerControlHost:DuplicateRegistration',`Duplicate control-host registration id: ${id}.`,{id});
      const controllerCapabilities=normalizeCapabilities(controllerSpec.capabilities);
      controllerCapabilities.forEach(assertCapability);
      if(typeof controllerSpec.mount!=='function')fail('NMResultsViewerControlHost:MissingControllerMount',`Control controller ${id} requires one mount function.`,{id});
      const allowed=new Set(controllerCapabilities);
      const restrictedDispatch=(command,detail)=>{
        try{
          const resolved=requireCommand(command);
          if(!allowed.has(resolved.capability))fail('NMResultsViewerControlHost:ControllerCapabilityMismatch',`Controller ${id} cannot dispatch ${command}; capability ${resolved.capability} was not registered for this controller.`,{id,command,capability:resolved.capability});
          const result=dispatch(command,detail);
          if(result&&typeof result.then==='function')result.catch(reportEventFailure);
          return result;
        }catch(error){reportEventFailure(error);return undefined;} // nm2-allow: NMResultsViewerControlHost event and controller callback exceptions are reported through reportEventFailure at the DOM callback boundary.
      };
      const controller=controllerSpec.mount(Object.freeze({dispatch:restrictedDispatch,capabilities:controllerCapabilities}));
      if(!controller||typeof controller.dispose!=='function')fail('NMResultsViewerControlHost:InvalidController',`Control controller ${id} must return an object with dispose().`,{id});
      registrations.set(id,Object.freeze({id,kind:'controller',dispose:()=>controller.dispose()}));
      return controller;
    }

    function unregister(id){
      assertMounted();
      const key=String(id||''),registration=registrations.get(key); // nm2-allow: NMResultsViewerControlHost exposed registration and lookup APIs preserve empty-id and missing-host results.
      if(!registration)fail('NMResultsViewerControlHost:UnknownRegistration',`Unknown control-host registration id: ${key||'(empty)'}.`,{id:key});
      registration.dispose();registrations.delete(key);
    }

    /** Remove every listener/observer owned by this host. Idempotent. */
    function dispose(){
      if(disposed)return false;
      disposed=true;
      registrations.forEach(registration=>registration.dispose());
      registrations.clear();
      HOSTS_BY_ROOT.delete(root);
      return true;
    }

    const host=Object.freeze({
      contractVersion:CONTRACT_VERSION,
      root,
      capabilities,
      hasCapability:capability=>capabilitySet.has(String(capability||'')), // nm2-allow: NMResultsViewerControlHost exposed registration and lookup APIs preserve empty-id and missing-host results.
      dispatch,
      registerRegion,
      registerViewport,
      registerController,
      unregister,
      dispose,
      isDisposed:()=>disposed
    });
    HOSTS_BY_ROOT.set(root,host);
    return host;
  }

  function hostForRoot(root){
    return root&&HOSTS_BY_ROOT.get(root)||null; // nm2-allow: NMResultsViewerControlHost exposed registration and lookup APIs preserve empty-id and missing-host results.
  }

  window.NMResultsViewerControlHost=Object.freeze({
    CONTRACT_VERSION,
    SUPPORTED_CAPABILITIES,
    commandCapability,
    mount,
    hostForRoot,
    _test:Object.freeze({controlHostError,normalizeCapabilities,requireCommand})
  });
})();
