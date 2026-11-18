(function(){
  /**
   * arr  Normalize a nullable scalar or array-like value to an array.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function arr(x){ return x == null ? [] : (Array.isArray(x) ? x : [x]); }
  /**
   * esc  Escape text before inserting it into HTML markup.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }
  /**
   * uniq  Provide the uniq helper used by manual artifact-file selector embedded in runtime pages.
   * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function uniq(paths){
    const out = [];
    const seen = new Set();
    arr(paths).forEach(p => {
      const s = String(p || '').trim();
      if(!s) return;
      const key = s.toLowerCase();
      if(seen.has(key)) return;
      seen.add(key);
      out.push(s);
    });
    return out;
  }
  /**
   * baseName  Provide the base name helper used by manual artifact-file selector embedded in runtime pages.
   * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function baseName(path){
    const parts = String(path || '').split(/[\\/]/);
    return parts.length ? parts[parts.length - 1] : String(path || '');
  }
  /**
   * dirName  Provide the dir name helper used by manual artifact-file selector embedded in runtime pages.
   * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function dirName(path){
    const s = String(path || '');
    const i1 = s.lastIndexOf('/');
    const i2 = s.lastIndexOf('\\');
    const i = Math.max(i1, i2);
    return i >= 0 ? s.slice(0, i) : '';
  }

  /**
   * create  Create the create component or browser-side state object.
   * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function create(host, opts){
    if(!host) throw new Error('NMManualArtifactFileList.create requires a host element.');
    let options = Object.assign({
      paths: [],
      emptyText: 'No manual artifact files selected.',
      title: 'Selected artifact files',
      removeLabel: 'Remove',
      clearLabel: 'Clear all',
      onChange: null
    }, opts || {});
    let paths = uniq(options.paths);

    /**
     * notify  Provide the notify helper used by manual artifact-file selector embedded in runtime pages.
     * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function notify(){
      if(typeof options.onChange === 'function') options.onChange(paths.slice());
    }
    /**
     * setPaths  Provide the set paths helper used by manual artifact-file selector embedded in runtime pages.
     * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function setPaths(next, silent){
      paths = uniq(next);
      render();
      if(!silent) notify();
    }
    /**
     * removeAt  Provide the remove at helper used by manual artifact-file selector embedded in runtime pages.
     * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function removeAt(idx){
      paths = paths.filter((_, i) => i !== idx);
      render();
      notify();
    }
    /**
     * clear  Clear the clear UI state, cache or rendered content.
     * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function clear(){ setPaths([], false); }
    /**
     * update  Update update state or markup after user interaction or bridge refresh.
     * It supports manual artifact-file selector embedded in runtime pages at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
     */
    function update(nextPaths, nextOpts){
      options = Object.assign({}, options, nextOpts || {});
      paths = uniq(nextPaths);
      render();
    }
    /**
     * render  Render the render UI region from current browser state.
     * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
     * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
     */
    function render(){
      host.classList.add('nmManualFileListHost');
      if(!paths.length){
        host.innerHTML = `<div class="nmManualFileList empty"><div class="nmManualFileEmpty">${esc(options.emptyText)}</div></div>`;
        return;
      }
      const items = paths.map((p, i) => {
        const name = baseName(p);
        const dir = dirName(p);
        return `<li class="nmManualFileItem" title="${esc(p)}"><div class="nmManualFileText"><strong>${esc(name)}</strong>${dir ? `<small>${esc(dir)}</small>` : ''}</div><button class="nmManualFileRemove" type="button" data-index="${i}">${esc(options.removeLabel)}</button></li>`;
      }).join('');
      host.innerHTML = `<div class="nmManualFileList"><div class="nmManualFileHeader"><span>${esc(options.title)} <strong>${paths.length}</strong></span><button class="nmManualFileClear" type="button">${esc(options.clearLabel)}</button></div><ul>${items}</ul></div>`;
      const clearBtn = host.querySelector('.nmManualFileClear');
      if(clearBtn) clearBtn.addEventListener('click', clear);
      host.querySelectorAll('.nmManualFileRemove').forEach(btn => {
        btn.addEventListener('click', () => removeAt(Number(btn.getAttribute('data-index'))));
      });
    }

    render();
    return {update, getPaths:() => paths.slice(), setPaths, clear};
  }

  window.NMManualArtifactFileList = {create:create, uniquePaths:uniq};
})();
