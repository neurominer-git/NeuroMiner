/*
 * NMImagingVolumePrepClient — lifecycle-safe browser client for volume preparation.
 *
 * Contract:
 * - scientific preparation remains in NMImagingVolumePrep.js;
 * - this client only schedules deterministic tasks, transfers safe cloned buffers,
 *   caches results by caller-supplied scientific keys, and rejects disposed/cancelled consumers;
 * - WebGL texture creation and upload remain on the renderer-owning main thread;
 * - stale generations may populate the deterministic preparation cache, but callers
 *   must compare the returned generation before installing a result.
 */
(function(root){
  'use strict';

  function now(){return root.performance&&typeof root.performance.now==='function'?root.performance.now():Date.now();}
  function finite(value,fallback){const n=Number(value);return Number.isFinite(n)?n:fallback;}
  function byteLength(value){
    if(!value||typeof value!=='object')return 0;
    if(ArrayBuffer.isView(value))return value.byteLength;
    if(value instanceof ArrayBuffer)return value.byteLength;
    if(Array.isArray(value))return value.reduce((sum,item)=>sum+byteLength(item),0);
    return Object.keys(value).reduce((sum,key)=>sum+byteLength(value[key]),0);
  }
  function cloneForWorker(value,transfer,seen){
    if(value===null||value===undefined||typeof value!=='object')return value;
    if(ArrayBuffer.isView(value)){
      const copy=new value.constructor(value);
      if(!seen.has(copy.buffer)){seen.add(copy.buffer);transfer.push(copy.buffer);}
      return copy;
    }
    if(value instanceof ArrayBuffer){
      const copy=value.slice(0);
      if(!seen.has(copy)){seen.add(copy);transfer.push(copy);}
      return copy;
    }
    if(Array.isArray(value))return value.map(item=>cloneForWorker(item,transfer,seen));
    const out={};Object.keys(value).forEach(key=>{out[key]=cloneForWorker(value[key],transfer,seen);});return out;
  }
  function errorWithCode(message,code,detail){const error=new Error(message);error.code=code;if(detail)error.detail=detail;return error;}

  class Client{
    constructor(options){
      const opts=options&&typeof options==='object'?options:{};
      this.workerUrl=String(opts.workerUrl||'NMImagingVolumePrepWorker.js');
      this.onProfile=typeof opts.onProfile==='function'?opts.onProfile:null;
      this.onError=typeof opts.onError==='function'?opts.onError:null;
      this.cacheLimit=Math.max(2,Math.round(finite(opts.cacheLimit,8)));this.cacheByteLimit=Math.max(32*1024*1024,finite(opts.cacheByteLimit,256*1024*1024));
      this.worker=null;this.readyPromise=null;this.pending=new Map();this.cache=new Map();
      this.nextRequestId=1;this.disposed=false;this.cancelledGenerations=new Set();this.cacheBytes=0;
      this.profile={schema:'nm-imaging-volume-prep-client-profile',version:1,workerUrl:this.workerUrl,workerStartupMs:NaN,requests:[],cacheHits:0,staleRejects:0,failures:0,cacheBytes:0,cacheByteLimit:this.cacheByteLimit};
    }
    _emit(entry){this.profile.requests.push(entry);if(this.profile.requests.length>80)this.profile.requests.shift();if(this.onProfile)try{this.onProfile(entry);}catch(error){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] volume preparation profile callback failed:',error);}}
    _ensureWorker(){
      if(this.disposed)return Promise.reject(errorWithCode('Volume preparation client is disposed.','disposed'));
      if(this.readyPromise)return this.readyPromise;
      if(typeof root.Worker!=='function')return Promise.reject(errorWithCode('Browser Worker API is unavailable.','worker_unavailable'));
      const started=now();
      this.readyPromise=new Promise((resolve,reject)=>{
        let worker;
        try{worker=new root.Worker(this.workerUrl);}catch(error){reject(errorWithCode(`Could not start volume preparation worker: ${error.message||String(error)}`,'worker_start_failed'));return;}
        this.worker=worker;
        worker.onmessage=event=>this._handleMessage(event);
        worker.onerror=event=>{
          const message=(event&&event.message)||'Unknown worker error.';
          const error=errorWithCode(`Volume preparation worker failed: ${message}`,'worker_runtime_failed');
          error.nmReported=true;this.profile.failures++;
          this._emit({phase:'worker_failure',code:error.code,message:error.message});
          const pending=Array.from(this.pending.values());this.pending.clear();
          pending.forEach(item=>{if(item.cacheKey)this._deleteCache(item.cacheKey);item.reject(error);});
          try{worker.terminate();}catch(terminateError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] worker termination failed:',terminateError);}
          if(this.worker===worker)this.worker=null;this.readyPromise=null;
          if(this.onError)try{this.onError(error);}catch(callbackError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] volume preparation error callback failed:',callbackError);}
        };
        const requestId=this.nextRequestId++;
        this.pending.set(requestId,{requestId,task:'ping',cacheKey:'',generation:0,postedAt:now(),inputBytes:0,resolve:message=>{
          this.profile.workerStartupMs=now()-started;
          this._emit({phase:'worker_startup',workerStartupMs:this.profile.workerStartupMs});
          resolve(message);
        },reject});
        worker.postMessage({requestId,generation:0,task:'ping',input:null});
      });
      this.readyPromise.catch(error=>{this.readyPromise=null;if(this.worker){try{this.worker.terminate();}catch(terminateError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] worker termination failed:',terminateError);}this.worker=null;}if(!error.nmReported&&this.onError)try{this.onError(error);}catch(callbackError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] volume preparation error callback failed:',callbackError);};});
      return this.readyPromise;
    }
    _touchCache(key,value){const previous=this.cache.get(key);if(previous)this.cacheBytes=Math.max(0,this.cacheBytes-finite(previous.bytes,0));if(this.cache.has(key))this.cache.delete(key);value.bytes=Math.max(0,finite(value.bytes,value.record&&value.record.outputBytes||0));this.cache.set(key,value);this.cacheBytes+=value.bytes;while(this.cache.size>this.cacheLimit||this.cacheBytes>this.cacheByteLimit){const oldestKey=this.cache.keys().next().value,oldest=this.cache.get(oldestKey);this.cache.delete(oldestKey);this.cacheBytes=Math.max(0,this.cacheBytes-finite(oldest&&oldest.bytes,0));}this.profile.cacheBytes=this.cacheBytes;}
    _deleteCache(key){const item=this.cache.get(key);if(!item)return;this.cache.delete(key);this.cacheBytes=Math.max(0,this.cacheBytes-finite(item.bytes,0));this.profile.cacheBytes=this.cacheBytes;}
    _handleMessage(event){
      const message=event&&event.data||{},requestId=Number(message.requestId),pending=this.pending.get(requestId);
      if(!pending)return;
      this.pending.delete(requestId);
      if(message.ok!==true){
        const error=errorWithCode(message.message||`Volume preparation task ${pending.task} failed.`,'worker_task_failed',{task:pending.task,generation:pending.generation});
        this.profile.failures++;if(pending.cacheKey)this._deleteCache(pending.cacheKey);pending.reject(error);if(this.onError)try{this.onError(error);}catch(callbackError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] volume preparation error callback failed:',callbackError);};return;
      }
      if(pending.task==='ping'){pending.resolve(message);return;}
      const receivedAt=now(),workerPreparationMs=finite(message.timings&&message.timings.workerPreparationMs,NaN),roundTripMs=receivedAt-pending.postedAt,transferAndQueueMs=Number.isFinite(workerPreparationMs)?Math.max(0,roundTripMs-workerPreparationMs):NaN;
      const record={result:message.result,task:pending.task,cacheKey:pending.cacheKey,mainThreadCloneMs:finite(pending.mainThreadCloneMs,0),postMessageMs:finite(pending.postMessageMs,0),workerPreparationMs,roundTripMs,transferAndQueueMs,inputBytes:pending.inputBytes,outputBytes:finite(message.timings&&message.timings.outputBytes,byteLength(message.result)),workerStartupMs:this.profile.workerStartupMs,cacheHit:false};
      if(pending.cacheKey)this._touchCache(pending.cacheKey,{status:'resolved',record,bytes:record.outputBytes});
      this._emit(Object.assign({phase:'worker_request'},record,{result:undefined}));
      pending.resolve(record);
    }
    cancelGeneration(generation){this.cancelledGenerations.add(Number(generation));while(this.cancelledGenerations.size>64)this.cancelledGenerations.delete(this.cancelledGenerations.values().next().value);}
    async prepare(task,input,key,generation){
      if(this.disposed)throw errorWithCode('Volume preparation client is disposed.','disposed');
      const cacheKey=`${String(task)}|${String(key)}`,cached=this.cache.get(cacheKey);
      if(cached){
        this.cache.delete(cacheKey);this.cache.set(cacheKey,cached);this.profile.cacheHits++;
        const base=cached.status==='resolved'?Promise.resolve(cached.record):cached.promise;
        const record=await base;
        if(this.cancelledGenerations.has(Number(generation))){this.profile.staleRejects++;throw errorWithCode('Volume preparation result belongs to a cancelled generation.','stale_generation',{generation});}
        return Object.assign({},record,{generation,cacheHit:true});
      }
      await this._ensureWorker();
      const cloneStartedAt=now(),transfer=[],cloned=cloneForWorker(input,transfer,new Set()),mainThreadCloneMs=now()-cloneStartedAt,requestId=this.nextRequestId++,postedAt=now(),inputBytes=byteLength(cloned);
      const promise=new Promise((resolve,reject)=>{
        this.pending.set(requestId,{requestId,task:String(task),cacheKey,generation:Number(generation),postedAt,inputBytes,mainThreadCloneMs,postMessageMs:NaN,resolve,reject});
        try{const postStartedAt=now();this.worker.postMessage({requestId,generation:Number(generation),task:String(task),input:cloned},transfer);const pending=this.pending.get(requestId);if(pending)pending.postMessageMs=now()-postStartedAt;}catch(error){this.pending.delete(requestId);reject(errorWithCode(`Could not dispatch volume preparation task ${task}: ${error.message||String(error)}`,'worker_post_failed'));}
      });
      this._touchCache(cacheKey,{status:'pending',promise,bytes:0});
      let record;
      try{record=await promise;}catch(error){this._deleteCache(cacheKey);throw error;}
      if(this.cancelledGenerations.has(Number(generation))){this.profile.staleRejects++;throw errorWithCode('Volume preparation result belongs to a cancelled generation.','stale_generation',{generation});}
      return Object.assign({},record,{generation,cacheHit:false});
    }
    getProfile(){return JSON.parse(JSON.stringify(this.profile));}
    dispose(){
      if(this.disposed)return;this.disposed=true;
      const error=errorWithCode('Volume preparation client was disposed.','disposed');
      this.pending.forEach(item=>item.reject(error));this.pending.clear();this.cache.clear();
      if(this.worker)try{this.worker.terminate();}catch(terminateError){if(root.console&&typeof root.console.warn==='function')root.console.warn('[NM imaging] worker termination failed:',terminateError);}this.worker=null;this.readyPromise=null;this.cacheBytes=0;this.profile.cacheBytes=0;
    }
  }

  root.NMImagingVolumePrepClient={create:options=>new Client(options),Client,_test:{cloneForWorker,byteLength}};
})(typeof window!=='undefined'?window:self);
