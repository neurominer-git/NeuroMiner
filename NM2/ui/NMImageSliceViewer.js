(function(){
  'use strict';

  const {clamp}=globalThis.NMResultsViewerPrimitives;
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
   * clamp  Provide the clamp helper used by image-slice viewer used for voxel and QC overlays.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  /**
   * arr3  Provide the arr3 helper used by image-slice viewer used for voxel and QC overlays.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function arr3(v){
    if(!v) return [];
    var a = Array.isArray(v) ? v : Array.prototype.slice.call(v);
    return a.map(function(x){ return Number(x); });
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
   * closestViewport  Close the st viewport panel or dialog without changing authoritative MATLAB state.
   * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
   */
  function closestViewport(frame, canvas){
    if(frame && frame.parentElement) return frame.parentElement;
    if(canvas && canvas.parentElement) return canvas.parentElement;
    return null;
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
    this._resizeBound = false;
    this._resizeHandler = this.fit.bind(this);
    this._created = false;
  }

  SliceViewer.prototype.configure = function(opts){
    this.opts = Object.assign({}, this.opts || {}, opts || {});
    this.zoom = this.validZoom(num(this.opts.zoom, this.zoom));
    this.ensureChrome();
    this.bind();
    this.fit();
    this.updateDefaultCrosshair();
    return this;
  };

  SliceViewer.prototype.elements = function(){
    var frame = asEl(this.opts.frame || this.opts.frameId);
    var canvas = asEl(this.opts.canvas || this.opts.canvasId);
    if(!frame && canvas && this.opts.autoWrap !== false){
      frame = canvas.parentElement;
    }
    var viewport = asEl(this.opts.viewport || this.opts.viewportId) || closestViewport(frame, canvas);
    return {frame:frame, canvas:canvas, viewport:viewport};
  };

  SliceViewer.prototype.dims = function(){
    var d = typeof this.opts.getDims === 'function' ? this.opts.getDims() : this.opts.dims;
    d = arr3(d);
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
    if(typeof this.opts.onZoom === 'function' && notify !== false) this.opts.onZoom(this.zoom);
    this.updateZoomControl();
    this.fit();
    this.updateDefaultCrosshair();
  };

  SliceViewer.prototype.ensureChrome = function(){
    var e = this.elements();
    if(!e.frame || !e.canvas) return;
    e.frame.classList.add('nmSliceFrame');
    e.canvas.classList.add('nmSliceCanvas');
    if(!e.frame.querySelector('[data-nm-slice-crosshair-h]')){
      var h = document.createElement('span');
      h.className = 'nmSliceCrosshair nmSliceCrosshairH';
      h.setAttribute('data-nm-slice-crosshair-h','1');
      h.hidden = true;
      e.frame.appendChild(h);
    }
    if(!e.frame.querySelector('[data-nm-slice-crosshair-v]')){
      var v = document.createElement('span');
      v.className = 'nmSliceCrosshair nmSliceCrosshairV';
      v.setAttribute('data-nm-slice-crosshair-v','1');
      v.hidden = true;
      e.frame.appendChild(v);
    }
    if(!e.frame.querySelector('[data-nm-slice-tip]')){
      var tip = document.createElement('span');
      tip.className = 'nmSliceValueTip';
      tip.setAttribute('data-nm-slice-tip','1');
      tip.hidden = true;
      e.frame.appendChild(tip);
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
          zoom.innerHTML = '<div class="nmSliceZoomValue" data-nm-slice-zoom-value>1.0×</div><div class="nmSliceZoomTrack" data-nm-slice-zoom-track><input class="nmSliceZoomSlider" data-nm-slice-zoom-slider type="range" min="0" max="4" step="0.05" value="1" aria-label="Image zoom"></div><div class="nmSliceZoomLabel">zoom</div>';
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
    var vp = e.viewport || e.frame.parentElement;
    var pad = this.opts.enableZoom === false ? 0 : num(this.opts.zoomReservePx, 42);
    var width = vp ? vp.clientWidth : 0;
    if(vp && window.getComputedStyle){
      var style = window.getComputedStyle(vp);
      width -= num(parseFloat(style.paddingLeft),0) + num(parseFloat(style.paddingRight),0);
    }
    var availW = Math.max(1, width - pad);
    var availH = Math.max(1, vp ? vp.clientHeight : 0);
    if(!Number.isFinite(availW) || availW <= 1) availW = e.canvas.parentElement ? e.canvas.parentElement.clientWidth : e.canvas.clientWidth;
    if(!Number.isFinite(availH) || availH <= 1) availH = e.canvas.parentElement ? e.canvas.parentElement.clientHeight : e.canvas.clientHeight;
    var scale = Math.min(Math.max(1, availW) / w, Math.max(1, availH) / h);
    if(!Number.isFinite(scale) || scale <= 0) scale = 1;
    if(this.opts.zoomMode !== 'fixed') scale *= this.validZoom(this.zoom);
    var cssW = Math.max(1, Math.floor(w * scale));
    var cssH = Math.max(1, Math.floor(h * scale));
    e.canvas.style.width = cssW + 'px';
    e.canvas.style.height = cssH + 'px';
    e.frame.style.width = cssW + 'px';
    e.frame.style.height = cssH + 'px';
    if(this.opts.zoomMode === 'fixed'){
      e.frame.style.overflow = 'hidden';
      e.canvas.style.transformOrigin = 'center center';
      e.canvas.style.transform = 'scale(' + this.zoom + ')';
    }
    var track = vp && vp.querySelector('[data-nm-slice-zoom-track]');
    var slider = track && track.querySelector('[data-nm-slice-zoom-slider]');
    if(slider) slider.style.width = Math.max(80,Math.min(300,track.clientHeight - 8)) + 'px';
    this.updateZoomControl();
  };

  SliceViewer.prototype.voxelValue = function(x,y,z){
    if(typeof this.opts.valueAt === 'function') return this.opts.valueAt(x,y,z);
    return NaN;
  };

  SliceViewer.prototype.formatValue = function(v){
    if(typeof this.opts.formatValue === 'function') return this.opts.formatValue(v);
    return formatDefault(v);
  };

  SliceViewer.prototype.tipText = function(voxel, value){
    if(typeof this.opts.tooltipText === 'function') return this.opts.tooltipText(voxel, value);
    return 'QC ' + this.formatValue(value) + '  |  voxel ' + (voxel.x + 1) + ', ' + (voxel.y + 1) + ', ' + (voxel.z + 1);
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
    var viewW = Math.max(1, e.canvas.clientWidth || e.canvas.width || imgW);
    var viewH = Math.max(1, e.canvas.clientHeight || e.canvas.height || imgH);
    var x = clamp(Math.round(num(voxel.x, 0)), 0, imgW - 1);
    var y = clamp(Math.round(num(voxel.y, 0)), 0, imgH - 1);
    var z = clamp(Math.round(num(voxel.z, this.currentSlice() - 1)), 0, d[2] - 1);
    var px = (x + 0.5) / imgW * viewW;
    var py = (y + 0.5) / imgH * viewH;
    if(this.opts.zoomMode === 'fixed'){
      px = (px - viewW / 2) * this.zoom + viewW / 2;
      py = (py - viewH / 2) * this.zoom + viewH / 2;
    }
    hLine.hidden = py < 0 || py >= viewH;
    vLine.hidden = px < 0 || px >= viewW;
    hLine.style.top = py + 'px';
    vLine.style.left = px + 'px';
    var value = Number.isFinite(Number(voxel.value)) ? Number(voxel.value) : this.voxelValue(x,y,z);
    tip.textContent = this.tipText({x:x,y:y,z:z,value:value}, value);
    if(showTip){
      var anchorX = px, anchorY = py;
      if(evt && Number.isFinite(evt.clientX) && Number.isFinite(evt.clientY)){
        var fr = e.frame.getBoundingClientRect();
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
    var px = clamp(Number(evt.clientX) - rect.left, 0, rect.width - Number.EPSILON);
    var py = clamp(Number(evt.clientY) - rect.top, 0, rect.height - Number.EPSILON);
    var x = clamp(Math.floor(px / Math.max(Number.EPSILON, rect.width) * w), 0, w - 1);
    var y = clamp(Math.floor(py / Math.max(Number.EPSILON, rect.height) * h), 0, h - 1);
    var z = clamp(this.currentSlice() - 1, 0, d[2] - 1);
    return {x:x, y:y, z:z, value:this.voxelValue(x,y,z)};
  };

  SliceViewer.prototype.bestVoxel = function(slice){
    if(typeof this.opts.bestVoxel === 'function') return this.opts.bestVoxel(slice);
    return null;
  };

  SliceViewer.prototype.updateDefaultCrosshair = function(){
    var best = this.bestVoxel(this.currentSlice());
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
      e.frame.addEventListener('pointermove', function(evt){
        var voxel = self.voxelFromEvent(evt);
        if(voxel){
          self.setCrosshair(voxel, true, evt);
          if(typeof self.opts.onHover === 'function') self.opts.onHover(voxel, evt);
        }
      });
      e.frame.addEventListener('pointerleave', function(){ self.updateDefaultCrosshair(); });
    }
    var host = asEl(this.opts.zoomHost || this.opts.zoomHostId) || e.viewport || e.frame.parentElement;
    var slider = host && host.querySelector('[data-nm-slice-zoom-slider]');
    if(slider && this.boundZoom !== slider){
      this.boundZoom = slider;
      var self2 = this;
      /**
       * zhandler  Provide the zhandler helper used by image-slice viewer used for voxel and QC overlays.
       * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
       */
      var zhandler = function(){ self2.setZoom(Number(slider.value), true); };
      slider.addEventListener('input', zhandler);
      slider.addEventListener('change', zhandler);
    }
    if(!this._resizeBound){
      this._resizeBound = true;
      window.addEventListener('resize', this._resizeHandler);
    }
  };

  /**
   * create  Create the create component or browser-side state object.
   * It supports image-slice viewer used for voxel and QC overlays at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function create(opts){
    return new SliceViewer(opts || {}).configure(opts || {});
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
    return canvas[prop].configure(opts || {});
  }

  window.NMImageSliceViewer = {create:create, getOrCreate:getOrCreate, formatValue:formatDefault};
}());
