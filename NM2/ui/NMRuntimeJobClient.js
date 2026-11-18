(function(global){
  'use strict';

  /**
   * NMRuntimeJobClient
   *
   * Purpose
   *   Submit and reattach to long-running MATLAB jobs through the file-backed
   *   NM2 bridge job channel. The initiating HTTP request is acknowledged
   *   immediately; completion is observed by polling bridge-owned job status.
   *
   * Authority and flow
   *   The Python bridge owns durable transport state (queued/running/final).
   *   MATLAB owns execution and the final service result. This client owns only
   *   browser submission, reattachment and result retrieval. It does not infer
   *   scientific state or treat progress payloads as completion authority.
   *
   * Invariants
   *   - No wall-clock timeout is applied to an accepted runtime job.
   *   - Job identity is stable across browser reloads through localStorage.
   *   - A final service result is fetched only after the job status reports a
   *     terminal state and resultAvailable=true.
   *   - Temporary HTTP/poll failures do not mark the MATLAB job as failed.
   *
   * Materialization and performance
   *   Polling transfers only compact status JSON at a configurable interval.
   *   The potentially larger service result is transferred once at completion.
   *   No scientific arrays are copied or cached by this helper.
   *
   * Failure semantics
   *   Submission/contract errors are explicit. Once a job is accepted,
   *   transient status-transport failures are retried without a deadline.
   *   A missing persisted job clears stale browser reattachment state.
   */
  class NMRuntimeJobClient {
    constructor(options){
      const o = options || {};
      this.port = String(o.port || global.NM_UI_PORT || '4821');
      this.runId = String(o.runId || global.NM_BRIDGE_RUNID || '');
      this.base = `http://127.0.0.1:${this.port}`;
      const baseStorageKey = String(o.storageKey || 'nm2_runtime_job');
      this.storageKey = this.runId ? `${baseStorageKey}_${this.runId}` : baseStorageKey;
      this.pollMs = Math.max(100, Number(o.pollMs || 750));
    }

    api(path){ return `${this.base}${path}`; }

    safeStorageGet(){
      try{
        const raw = global.localStorage ? global.localStorage.getItem(this.storageKey) : '';
        return raw ? JSON.parse(raw) : null;
      } catch(_){ return null; }
    }

    safeStorageSet(value){
      try{
        if(global.localStorage) global.localStorage.setItem(this.storageKey, JSON.stringify(value || {}));
      } catch(_){}
    }

    safeStorageClear(jobId){
      try{
        if(!global.localStorage) return;
        const cur = this.safeStorageGet();
        if(!jobId || !cur || String(cur.jobId || '') === String(jobId)) global.localStorage.removeItem(this.storageKey);
      } catch(_){}
    }

    static createJobId(prefix){
      const p = String(prefix || 'job').replace(/[^A-Za-z0-9_-]/g, '') || 'job';
      try{
        if(global.crypto && typeof global.crypto.randomUUID === 'function') return `${p}_${global.crypto.randomUUID().replace(/-/g,'')}`;
      } catch(_){}
      return `${p}_${Date.now()}_${Math.random().toString(36).slice(2,12)}`.replace(/[^A-Za-z0-9_-]/g, '');
    }

    async requestJson(path, options){
      const response = await global.fetch(this.api(path), options || {});
      const txt = await response.text();
      let obj = {};
      try { obj = JSON.parse(txt || '{}'); }
      catch(_){ throw new Error(`Runtime-job bridge returned non-JSON for ${path}: ${(txt || '').slice(0,300)}`); }
      if(obj && typeof obj === 'object' && !Object.prototype.hasOwnProperty.call(obj,'httpStatus')) obj.httpStatus = response.status;
      return obj;
    }

    async status(jobId){
      const id = encodeURIComponent(String(jobId || ''));
      if(!id) throw new Error('Runtime job id is required.');
      return this.requestJson(`/api/matlabjob/${id}`, {cache:'no-store'});
    }

    async result(jobId){
      const id = encodeURIComponent(String(jobId || ''));
      if(!id) throw new Error('Runtime job id is required.');
      return this.requestJson(`/api/matlabjob/${id}/result`, {cache:'no-store'});
    }

    async active(operation){
      const op = String(operation || '');
      const q = op ? `?operation=${encodeURIComponent(op)}` : '';
      const out = await this.requestJson(`/api/matlabjob/active${q}`, {cache:'no-store'});
      return out && out.found && out.job ? out.job : null;
    }

    async find(operation){
      const op = String(operation || '');
      const stored = this.safeStorageGet();
      if(stored && stored.jobId && (!op || String(stored.operation || '') === op)){
        try{
          const st = await this.status(stored.jobId);
          if(st && st.ok !== false && String(st.jobId || '') === String(stored.jobId)) return st;
          if(st && Number(st.httpStatus) === 404) this.safeStorageClear(stored.jobId);
        } catch(_){
          // Preserve the local job identity across a transient bridge failure.
          return stored;
        }
      }
      try{
        const st = await this.active(op);
        if(st && st.jobId){
          this.safeStorageSet({jobId:st.jobId, operation:st.operation || op, progressTaskId:st.progressTaskId || ''});
          return st;
        }
      } catch(_){}
      return null;
    }

    async submit(payload, options){
      const req = Object.assign({}, payload || {});
      delete req.timeout;
      const o = options || {};
      const operation = String(req.operation || '');
      if(!operation) throw new Error('Runtime job requires a MATLAB operation.');
      const jobId = String(o.jobId || o.progressTaskId || NMRuntimeJobClient.createJobId(operation));
      const progressTaskId = String(o.progressTaskId || req.progressTaskId || '');
      req.jobId = jobId;
      this.safeStorageSet({jobId, operation, progressTaskId});
      let out;
      try{
        out = await this.requestJson('/api/matlabjob', {
          method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(req)
        });
      } catch(err){
        // Submission may have reached the bridge before the connection failed.
        // Keep the durable id so wait() can discover that accepted job.
        return {ok:true, accepted:true, uncertain:true, jobId, operation, progressTaskId, transportError:String(err && err.message || err)};
      }
      if(out && out.accepted && out.jobId){
        this.safeStorageSet({jobId:out.jobId, operation:out.operation || operation, progressTaskId:out.progressTaskId || progressTaskId});
        return out;
      }
      if(out && out.busy && out.jobId && String(out.operation || '') === operation){
        this.safeStorageSet({jobId:out.jobId, operation, progressTaskId:out.progressTaskId || progressTaskId});
        return Object.assign({}, out, {accepted:true, reattached:true});
      }
      this.safeStorageClear(jobId);
      throw new Error((out && (out.message || out.error)) || 'MATLAB runtime job was not accepted by the bridge.');
    }

    async wait(jobId, onStatus){
      const id = String(jobId || '');
      if(!id) throw new Error('Runtime job id is required.');
      for(;;){
        let st = null;
        try{
          st = await this.status(id);
        } catch(err){
          if(typeof onStatus === 'function') onStatus({ok:true, active:true, done:false, transient:true, jobId:id, message:`Runtime-job status transport is temporarily unavailable: ${err && err.message || String(err)}`});
          await new Promise(resolve => setTimeout(resolve, this.pollMs));
          continue;
        }
        if(st && Number(st.httpStatus) === 404){
          this.safeStorageClear(id);
          throw new Error('The persisted MATLAB runtime job is no longer available in this bridge session.');
        }
        if(typeof onStatus === 'function') onStatus(st || {});
        if(st && st.done){
          let out = null;
          if(st.resultAvailable){
            for(;;){
              try { out = await this.result(id); break; }
              catch(err){
                if(typeof onStatus === 'function') onStatus(Object.assign({}, st, {transient:true, message:`Runtime-job result transport is temporarily unavailable: ${err && err.message || String(err)}`}));
                await new Promise(resolve => setTimeout(resolve, this.pollMs));
              }
            }
          }
          this.safeStorageClear(id);
          if(out) return out;
          return {ok:!st.failed, message:st.message || (st.failed ? 'MATLAB runtime job failed.' : 'MATLAB runtime job completed.'), jobStatus:st};
        }
        await new Promise(resolve => setTimeout(resolve, this.pollMs));
      }
    }

    async run(payload, options){
      const o = options || {};
      const op = String((payload && payload.operation) || '');
      let st = await this.find(op);
      let jobId = st && st.jobId ? String(st.jobId) : '';
      if(!jobId){
        const accepted = await this.submit(payload, o);
        jobId = String(accepted.jobId || '');
        st = accepted;
        if(typeof o.onAccepted === 'function') o.onAccepted(accepted);
      } else if(typeof o.onAccepted === 'function') {
        o.onAccepted(Object.assign({accepted:true, reattached:true}, st));
      }
      return this.wait(jobId, o.onStatus);
    }
  }

  global.NMRuntimeJobClient = NMRuntimeJobClient;
})(window);
