(function(){
  'use strict';

  const {clamp}=globalThis.NMResultsViewerPrimitives;
  const activeViewers = new Map();
  window.addEventListener('resize',()=>{
    for(const [key,viewer] of activeViewers){
      if(viewer.elements().frame.isConnected) viewer.fit();
      else activeViewers.delete(key);
    }
  });
  /**
   * asEl  Convert the supplied value into the as el representation expected by the UI.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function asEl(ref){
    if(!ref) return null;
    if(typeof ref === 'string') return document.getElementById(ref);
    return ref;
  }
  /**
   * num  Provide the num helper used by image-slice viewer used for voxel and QC overlays.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function num(v, d){
    var n = Number(v);
    return Number.isFinite(n) ? n : d;
  }
  /**
   * formatDefault  Format the default value for labels, tables or status text.
   * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
   */
  function formatDefault(v){
    var n = Number(v);
    if(!Number.isFinite(n)) return 'NaN';
    var av = Math.abs(n);
    if(av >= 1000 || (av > 0 && av < 0.001)) return n.toExponential(3);
    return n.toFixed(av >= 10 ? 2 : 3).replace(/\.0+$/,'').replace(/(\.\d*?)0+$/,'$1');
  }
  /**
   * SliceViewer  Provide the slice viewer helper used by image-slice viewer used for voxel and QC overlays.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.autoWrap: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.bestVoxel: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.canvas: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.canvasId: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.dims: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.enableWheel: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.enableZoom: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.formatValue: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.frame: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.frameId: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.getDims: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.getSlice: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.maxZoom: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.minZoom: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.onHover: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.onZoom: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.render: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.setSlice: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.slice: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.tooltipText: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.valueAt: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.viewport: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.viewportId: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.zoom: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function SliceViewer(opts){
    this.opts = opts || {};
    this.boundFrame = null;
    this.boundZoom = null;
    this.zoom = num(this.opts.zoom, 1);
    this.view = {x:0.5, y:0.5, selected:null, pending:false};
  }

  SliceViewer.prototype.configure = function(opts){
    this.opts = Object.assign({}, this.opts || {}, opts || {});
    this.view = this.opts.view || this.view;
    this.zoom = this.validZoom(num(this.opts.zoom, this.zoom));
    this.ensureChrome();
    this.bind();
    this.fit();
    return this;
  };

  SliceViewer.prototype.elements = function(){
    var frame = asEl(this.opts.frame || this.opts.frameId);
    var canvas = asEl(this.opts.canvas || this.opts.canvasId);
    if(!frame && canvas && this.opts.autoWrap !== false){
      frame = canvas.parentElement;
    }
    var viewport = asEl(this.opts.viewport || this.opts.viewportId) || (frame && frame.parentElement) || (canvas && canvas.parentElement);
    return {frame:frame, canvas:canvas, viewport:viewport};
  };

  SliceViewer.prototype.dims = function(){
    var d = typeof this.opts.getDims === 'function' ? this.opts.getDims() : this.opts.dims;
    d = d ? Array.from(d, Number) : [];
    if(d.length < 3 || !Number.isFinite(d[0]) || !Number.isFinite(d[1]) || !Number.isFinite(d[2])) return [];
    return [Math.max(1, Math.round(d[0])), Math.max(1, Math.round(d[1])), Math.max(1, Math.round(d[2]))];
  };

  SliceViewer.prototype.currentSlice = function(){
    var d = this.dims();
    var nSlices = d.length ? d[2] : 1;
    var s = typeof this.opts.getSlice === 'function' ? this.opts.getSlice() : this.opts.slice;
    return Math.max(1, Math.min(nSlices, Math.round(num(s, 1))));
  };

  SliceViewer.prototype.validZoom = function(z){
    var minZ = Math.max(0, num(this.opts.minZoom, 0));
    var maxZ = num(this.opts.maxZoom, 4);
    return clamp(num(z, 1), minZ, Math.max(minZ, maxZ));
  };

  SliceViewer.prototype.setZoom = function(z, notify){
    this.zoom = this.validZoom(z);
    if(this.view.pending){
      this.view.x = this.view.selected.x;
      this.view.y = this.view.selected.y;
      this.view.pending = false;
    }
    if(typeof this.opts.onZoom === 'function' && notify !== false) this.opts.onZoom(this.zoom);
    this.updateZoomControl();
    this.applyTransform();
    this.updateDefaultCrosshair();
  };

  SliceViewer.prototype.ensureChrome = function(){
    var e = this.elements();
    if(!e.frame || !e.canvas) return;
    e.frame.classList.add('nmSliceFrame');
    e.canvas.classList.add('nmSliceCanvas');
    for(const [attr,cls] of [
      ['data-nm-slice-crosshair-h','nmSliceCrosshair nmSliceCrosshairH'],
      ['data-nm-slice-crosshair-v','nmSliceCrosshair nmSliceCrosshairV'],
      ['data-nm-slice-tip','nmSliceValueTip']
    ]){
      if(e.frame.querySelector('['+attr+']')) continue;
      const node=document.createElement('span');
      node.className=cls;
      node.setAttribute(attr,'1');
      node.hidden=true;
      e.frame.appendChild(node);
    }
    if(this.opts.enableZoom !== false){
      var host = asEl(this.opts.zoomHost || this.opts.zoomHostId) || e.viewport || e.frame.parentElement;
      if(host){
        host.classList.add('nmSliceZoomHost');
        var zoom = host.querySelector('[data-nm-slice-zoom]');
        if(!zoom){
          zoom = document.createElement('div');
          zoom.className = 'nmSliceZoom';
          zoom.setAttribute('data-nm-slice-zoom','1');
          zoom.innerHTML = '<div class="nmSliceZoomValue" data-nm-slice-zoom-value>1.0×</div><div class="nmSliceZoomTrack" data-nm-slice-zoom-track><input class="nmSliceZoomSlider" data-nm-slice-zoom-slider type="range" min="0" max="4" step="0.05" value="1" aria-label="Image zoom" title="Click to set focus; drag to pan; double-click to reset"></div><div class="nmSliceZoomLabel">zoom</div>';
          host.appendChild(zoom);
        }
      }
    }
  };

  SliceViewer.prototype.updateZoomControl = function(){
    var e = this.elements();
    var host = asEl(this.opts.zoomHost || this.opts.zoomHostId) || e.viewport || (e.frame && e.frame.parentElement);
    if(!host) return;
    var slider = host.querySelector('[data-nm-slice-zoom-slider]');
    var value = host.querySelector('[data-nm-slice-zoom-value]');
    var minZ = Math.max(0, num(this.opts.minZoom, 0));
    var maxZ = num(this.opts.maxZoom, 4);
    if(slider){
      slider.min = String(minZ);
      slider.max = String(maxZ);
      slider.step = String(this.opts.zoomStep || 0.05);
      slider.value = String(this.zoom);
    }
    if(value) value.textContent = this.zoom.toFixed(2).replace(/0$/,'').replace(/\.0$/,'') + '×';
  };

  SliceViewer.prototype.fit = function(){
    var e = this.elements();
    var d = this.dims();
    if(!e.canvas || !e.frame || !d.length) return;
    var h = d[0], w = d[1];
    var vp = e.viewport;
    var style = window.getComputedStyle(vp);
    var width = vp.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    var availW = width - (this.opts.enableZoom === false ? 0 : num(this.opts.zoomReservePx, 42));
    var availH = vp.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
    if(availW <= 0 || availH <= 0) return;
    var scale = Math.min(availW / w, availH / h);
    var cssW = Math.max(1, Math.floor(w * scale)) + 'px';
    var cssH = Math.max(1, Math.floor(h * scale)) + 'px';
    e.canvas.style.width = e.frame.style.width = cssW;
    e.canvas.style.height = e.frame.style.height = cssH;
    this.applyTransform();
    var track = vp && vp.querySelector('[data-nm-slice-zoom-track]');
    var slider = track && track.querySelector('[data-nm-slice-zoom-slider]');
    if(slider) slider.style.width = Math.max(80,Math.min(300,track.clientHeight - 8)) + 'px';
    this.updateZoomControl();
    this.updateDefaultCrosshair();
  };

  SliceViewer.prototype.center = function(value){
    const margin = 0.5 / Math.max(1, this.zoom);
    return clamp(value, margin, 1-margin);
  };

  SliceViewer.prototype.applyTransform = function(){
    const {frame,canvas} = this.elements();
    const x = (0.5-this.center(this.view.x))*frame.clientWidth*this.zoom;
    const y = (0.5-this.center(this.view.y))*frame.clientHeight*this.zoom;
    canvas.style.transform = `translate(${x}px,${y}px) scale(${this.zoom})`;
  };

  SliceViewer.prototype.voxelValue = function(x,y,z){
    if(typeof this.opts.valueAt === 'function') return this.opts.valueAt(x,y,z);
    return NaN;
  };


  SliceViewer.prototype.tipText = function(voxel, value){
    if(typeof this.opts.tooltipText === 'function') return this.opts.tooltipText(voxel, value);
    const valueText = typeof this.opts.formatValue === 'function' ? this.opts.formatValue(value) : formatDefault(value);
    return 'QC ' + valueText + '  |  voxel ' + (voxel.x + 1) + ', ' + (voxel.y + 1) + ', ' + (voxel.z + 1);
  };

  SliceViewer.prototype.setCrosshair = function(voxel, showTip, evt){
    var e = this.elements();
    var d = this.dims();
    if(!e.frame || !e.canvas || !d.length || !voxel){
      this.hideCrosshair();
      return;
    }
    var hLine = e.frame.querySelector('[data-nm-slice-crosshair-h]');
    var vLine = e.frame.querySelector('[data-nm-slice-crosshair-v]');
    var tip = e.frame.querySelector('[data-nm-slice-tip]');
    if(!hLine || !vLine || !tip) return;
    var imgH = d[0], imgW = d[1];
    var fr = e.frame.getBoundingClientRect(), rect = e.canvas.getBoundingClientRect();
    var x = clamp(Math.round(voxel.x), 0, imgW - 1);
    var y = clamp(Math.round(voxel.y), 0, imgH - 1);
    var z = this.currentSlice() - 1;
    var px = rect.left-fr.left + (x+0.5)/imgW*rect.width;
    var py = rect.top-fr.top + (y+0.5)/imgH*rect.height;
    hLine.hidden = py < 0 || py >= fr.height || px < 0 || px >= fr.width;
    vLine.hidden = hLine.hidden;
    hLine.style.top = py + 'px';
    vLine.style.left = px + 'px';
    var value = Number.isFinite(Number(voxel.value)) ? Number(voxel.value) : this.voxelValue(x,y,z);
    tip.textContent = this.tipText({x:x,y:y,z:z,value:value}, value);
    if(showTip){
      var anchorX = px, anchorY = py;
      if(evt && Number.isFinite(evt.clientX) && Number.isFinite(evt.clientY)){
        anchorX = evt.clientX - fr.left;
        anchorY = evt.clientY - fr.top;
      }
      // Measure from the frame origin so shrink-to-fit text cannot inherit a previous edge position.
      tip.style.left = '0px';
      tip.style.top = '0px';
      tip.hidden = false;
      var tipW = tip.offsetWidth, tipH = tip.offsetHeight, margin = 4, gap = 10;
      var frameW = e.frame.clientWidth, frameH = e.frame.clientHeight;
      var left = anchorX + gap;
      var top = anchorY - gap - tipH;
      if(left + tipW + margin > frameW) left = anchorX - gap - tipW;
      if(top < margin) top = anchorY + gap;
      tip.style.left = clamp(left, margin, Math.max(margin, frameW - tipW - margin)) + 'px';
      tip.style.top = clamp(top, margin, Math.max(margin, frameH - tipH - margin)) + 'px';
    } else {
      tip.hidden = true;
    }
  };

  SliceViewer.prototype.hideCrosshair = function(){
    var e = this.elements();
    if(!e.frame) return;
    ['[data-nm-slice-crosshair-h]','[data-nm-slice-crosshair-v]','[data-nm-slice-tip]'].forEach(function(sel){
      var node = e.frame.querySelector(sel);
      if(node) node.hidden = true;
    });
  };

  SliceViewer.prototype.voxelFromEvent = function(evt){
    var e = this.elements();
    var d = this.dims();
    if(!e.canvas || !d.length || !evt) return null;
    var rect = e.canvas.getBoundingClientRect();
    if(rect.width <= 0 || rect.height <= 0) return null;
    var h = d[0], w = d[1];
    var px = evt.clientX - rect.left, py = evt.clientY - rect.top;
    if(px < 0 || py < 0 || px >= rect.width || py >= rect.height) return null;
    var x = Math.floor(px / rect.width * w);
    var y = Math.floor(py / rect.height * h);
    var z = this.currentSlice() - 1;
    return {x:x, y:y, z:z, value:this.voxelValue(x,y,z)};
  };


  SliceViewer.prototype.updateDefaultCrosshair = function(){
    const d = this.dims(), selected = this.view.selected;
    const best = selected && d.length
      ? {x:Math.floor(selected.x*d[1]), y:Math.floor(selected.y*d[0]), z:this.currentSlice()-1}
      : (typeof this.opts.bestVoxel === 'function' ? this.opts.bestVoxel(this.currentSlice()) : null);
    if(best) this.setCrosshair(best, false, null);
    else this.hideCrosshair();
  };

  SliceViewer.prototype.bind = function(){
    var e = this.elements();
    if(!e.frame || !e.canvas) return;
    if(this.boundFrame !== e.frame){
      this.boundFrame = e.frame;
      var self = this;
      e.frame.addEventListener('wheel', function(evt){
        if(self.opts.enableWheel === false) return;
        if(evt.ctrlKey || !self.opts.setSlice){
          if(self.opts.enableZoom === false) return;
          evt.preventDefault();
          self.setZoom(self.zoom * (evt.deltaY < 0 ? 1.1 : 1/1.1));
          return;
        }
        var d = self.dims();
        if(!d.length) return;
        evt.preventDefault();
        var cur = self.currentSlice();
        var direction = Number(evt.deltaY) >= 0 ? 1 : -1;
        var next = clamp(cur + direction, 1, d[2]);
        if(next !== cur && typeof self.opts.setSlice === 'function'){
          self.opts.setSlice(next, evt);
          if(typeof self.opts.render === 'function') self.opts.render();
          self.updateDefaultCrosshair();
        }
      }, {passive:false});
      let drag = null;
      e.frame.addEventListener('pointerdown', evt=>{
        if(evt.button !== 0 || self.opts.enableZoom === false) return;
        drag = {id:evt.pointerId,x:evt.clientX,y:evt.clientY,moved:false};
        e.frame.setPointerCapture(evt.pointerId);
      });
      e.frame.addEventListener('pointermove', function(evt){
        if(drag && drag.id === evt.pointerId && self.zoom > 1){
          const dx = evt.clientX-drag.x, dy = evt.clientY-drag.y;
          if(drag.moved || Math.hypot(dx,dy)>3){
            self.view.x = self.center(self.center(self.view.x)-dx/(e.frame.clientWidth*self.zoom));
            self.view.y = self.center(self.center(self.view.y)-dy/(e.frame.clientHeight*self.zoom));
            self.view.pending = false;
            drag.x = evt.clientX; drag.y = evt.clientY; drag.moved = true;
            self.applyTransform(); self.updateDefaultCrosshair();
            return;
          }
        }
        var voxel = self.voxelFromEvent(evt);
        if(voxel){
          self.setCrosshair(voxel, true, evt);
          if(typeof self.opts.onHover === 'function') self.opts.onHover(voxel, evt);
        }
      });
      e.frame.addEventListener('pointerup', evt=>{
        if(!drag || drag.id !== evt.pointerId) return;
        const voxel = self.voxelFromEvent(evt), d = self.dims();
        if(!drag.moved && Math.hypot(evt.clientX-drag.x,evt.clientY-drag.y)<=3 && voxel){
          self.view.selected = {x:(voxel.x+0.5)/d[1],y:(voxel.y+0.5)/d[0]};
          self.view.pending = true;
        }
        drag = null;
        self.updateDefaultCrosshair();
      });
      e.frame.addEventListener('lostpointercapture', ()=>{drag = null;});
      e.frame.addEventListener('dblclick', ()=>{
        Object.assign(self.view,{x:0.5,y:0.5,selected:null,pending:false});
        self.setZoom(1);
      });
      e.frame.addEventListener('pointerleave', function(){ self.updateDefaultCrosshair(); });
    }
    var host = asEl(this.opts.zoomHost || this.opts.zoomHostId) || e.viewport || e.frame.parentElement;
    var slider = host && host.querySelector('[data-nm-slice-zoom-slider]');
    if(slider && this.boundZoom !== slider){
      this.boundZoom = slider;
      slider.addEventListener('input', () => this.setZoom(Number(slider.value), true));
    }
  };

  /**
   * create  Create the create component or browser-side state object.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function create(opts){
    const viewer = new SliceViewer(opts).configure(opts);
    if(viewer.elements().frame) activeViewers.set(viewer,viewer);
    return viewer;
  }

  /**
   * getOrCreate  Provide the get or create helper used by image-slice viewer used for voxel and QC overlays.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function getOrCreate(key, opts){
    var canvas = asEl((opts || {}).canvas || (opts || {}).canvasId);
    if(!canvas) return create(opts);
    var prop = '__nmImageSliceViewer_' + String(key || 'default');
    if(!canvas[prop]) canvas[prop] = new SliceViewer(opts || {});
    const viewer = canvas[prop].configure(opts);
    activeViewers.set(prop,viewer);
    return viewer;
  }

  // The full matrix is rasterized once at native cell resolution; zoom is a viewport transform.
  function drawMatrix(canvas, matrix, colour){
    const n = matrix.length;
    canvas.width = canvas.height = n;
    const ctx = canvas.getContext('2d'), image = ctx.createImageData(n,n);
    for(let r=0;r<n;r++) for(let c=0;c<n;c++){
      const rgb = colour(matrix[r][c]), offset = 4*(r*n+c);
      image.data.set(rgb,offset);
      image.data[offset+3] = 255;
    }
    ctx.putImageData(image,0,0);
  }

  // Shared guidance for DataIO and Results Viewer; scientific state is unchanged.
  const mouseGestures = {
    volume: ['Click — set zoom centre', 'Drag — pan when zoomed', 'Wheel — change axial slice',
      'Ctrl + wheel — zoom', 'Double-click — reset zoom and pan'],
    surface: ['Click — centre surface', 'Drag — rotate', 'Shift + drag — pan',
      'Middle-drag — pan', 'Wheel — zoom', 'Double-click — reset camera'],
    connectivity: ['Hover — inspect ROI pair', 'Click — set zoom centre',
      'Drag — pan when zoomed', 'Wheel — zoom', 'Double-click — reset zoom and pan']
  };
  function mouseHelpHtml(kind){
    const rows = mouseGestures[kind].map(gesture => `<li>${gesture}</li>`).join('');
    return `<details class="nmMouseHelp" data-mouse-help-kind="${kind}"><summary title="Mouse controls" aria-label="Mouse controls"><img src="NMMouseControlsIcon.png" alt="" width="20" height="20"></summary><div class="nmMouseHelpBody"><strong>Mouse controls</strong><ul>${rows}</ul></div></details>`;
  }
  function mountMouseHelp(target, kind){
    let anchor = target.parentElement;
    if(!anchor.classList.contains('nmMouseHelpAnchor')){
      anchor = document.createElement('div');
      anchor.className = 'nmMouseHelpAnchor';
      target.before(anchor);
      anchor.appendChild(target);
    }
    const existing = anchor.querySelector('.nmMouseHelp');
    if(existing && existing.dataset.mouseHelpKind === kind) return;
    if(existing) existing.remove();
    anchor.insertAdjacentHTML('afterbegin', mouseHelpHtml(kind));
  }
  // Shared DataIO and Results Viewer mean/SD palette; renderer-specific opacity remains local.
  const QC_GROUP_SD_STOPS = [[42, 197, 225], [255, 220, 75], [255, 140, 39], [160, 34, 180]];
  const QC_GROUP_MEAN_STOPS = [[42, 197, 225], [42, 185, 126], [255, 220, 75], [229, 42, 51]];
  const QC_GROUP_NEGATIVE_STOPS = [[42, 197, 225], [140, 30, 220]];
  const QC_GROUP_POSITIVE_STOPS = [[255, 220, 75], [229, 42, 51]];
  function qcRgbInterpolate(stops, index, weight) {
    return stops[index].map((v, i) => Math.round(v + weight * (stops[index + 1][i] - v)));
  }
  /** Mean and SD display transfer; alpha is independent of the global opacity control. */
  function qcGroupTone(value, metricKey, window, kind) {
    const sd = metricKey === 'feature_std' || metricKey === 'group_sd';
    const signed = kind === 'bipolar';
    const bound = Math.max(Math.abs(window[0]), Math.abs(window[1]), 1e-6);
    const normal = Math.max(0, Math.min(1, (value - window[0]) / Math.max(window[1] - window[0], 1e-6)));
    const magnitude = Math.min(1, Math.abs(value) / bound);
    const pivot = Math.max(1e-6, Math.min(2, window[1]));
    const stage = sd ? value <= pivot ? Math.max(0, value) / pivot
      : value <= 3 ? 1 + (value - pivot) / (3 - pivot)
      : 2 + (value - 3) / Math.max(window[1] - 3, 1e-6)
      : signed ? magnitude : 3 * normal;
    const alpha = sd ? stage <= 1 ? 0.7 * Math.pow(stage, 1.3)
      : stage <= 2 ? 0.7 + 0.15 * (stage - 1) : 0.85 + 0.1 * Math.min(1, stage - 2)
      : 0.9 * Math.pow(signed ? magnitude : normal, 1.3);
    const stops = sd ? QC_GROUP_SD_STOPS : signed
      ? value < 0 ? QC_GROUP_NEGATIVE_STOPS : QC_GROUP_POSITIVE_STOPS : QC_GROUP_MEAN_STOPS;
    const x = Math.max(0, Math.min(stops.length - 1, stage));
    const i = Math.min(stops.length - 2, Math.floor(x));
    return { rgb: qcRgbInterpolate(stops, i, x - i), alpha };
  }
  
  /** Render the same transfer as a continuous horizontal or vertical legend. */
  function qcGroupGradient(metricKey, window, kind, direction) {
    const stops = Array.from({ length: 33 }, (_, i) => {
      const value = window[0] + (window[1] - window[0]) * i / 32;
      const tone = qcGroupTone(value, metricKey, window, kind);
      return `rgba(${tone.rgb.join(',')},${tone.alpha.toFixed(3)}) ${100 * i / 32}%`;
    });
    return `linear-gradient(${direction}, ${stops.join(',')})`;
  }
  
  /** Connectivity cells are opaque; composite the mean/SD transfer against white. */
  function qcGroupMatrixRgb(value, metricKey, display) {
    const tone = qcGroupTone(value, metricKey, display.window, display.kind);
    return tone.rgb.map((v) => Math.round(255 * (1 - tone.alpha) + v * tone.alpha));
  }
  window.NMImageSliceViewer = {
    create:create, getOrCreate:getOrCreate, formatValue:formatDefault, drawMatrix:drawMatrix,
    mouseHelpHtml, mountMouseHelp, rgbInterpolate:qcRgbInterpolate,
    groupTone:qcGroupTone, groupGradient:qcGroupGradient, groupMatrixRgb:qcGroupMatrixRgb,
    groupStops:{sd:QC_GROUP_SD_STOPS,mean:QC_GROUP_MEAN_STOPS,
      negative:QC_GROUP_NEGATIVE_STOPS,positive:QC_GROUP_POSITIVE_STOPS}
  };
}());
