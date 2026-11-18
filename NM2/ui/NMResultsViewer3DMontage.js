(function () {
  "use strict";

  const {clamp,text}=globalThis.NMResultsViewerPrimitives;
  function finite(v, d) {
    const n = Number(v);
    return Number.isFinite(n) ? n : d;
  }
  function normalizeState(value) {
    const s = value && typeof value === "object" ? value : {};
    s.preset = s.preset === "six" ? "six" : "four";
    s.layout = s.layout === "grid" ? "grid" : "showcase";
    s.tileWidth = clamp(Math.round(finite(s.tileWidth, 420)), 280, 760);
    s.tileHeight = clamp(Math.round(finite(s.tileHeight, 330)), 220, 620);
    s.exportScale = clamp(Math.round(finite(s.exportScale, 3)), 2, 4);
    s.gapPx = clamp(Math.round(finite(s.gapPx, 4)), 0, 24);
    s.labelsVisible = s.labelsVisible !== false;
    s.orientationVisible = !!s.orientationVisible;
    s.backgroundMode = ["inherit", "dark", "light", "transparent"].includes(
      text(s.backgroundMode),
    )
      ? text(s.backgroundMode)
      : "inherit";
    return s;
  }
  function viewDefinitions() {
    const none = { mode: "none" };
    return {
      right: { id: "right", label: "Right", azimuthDeg: -90, elevationDeg: 0, clipping: none },
      left: { id: "left", label: "Left", azimuthDeg: 90, elevationDeg: 0, clipping: none },
      anterior: { id: "anterior", label: "Anterior", azimuthDeg: 180, elevationDeg: 0, clipping: none },
      posterior: { id: "posterior", label: "Posterior", azimuthDeg: 0, elevationDeg: 0, clipping: none },
      superior: { id: "superior", label: "Superior", azimuthDeg: 0, elevationDeg: 89.5, clipping: none, anteriorUp: true },
      inferior: { id: "inferior", label: "Inferior", azimuthDeg: 180, elevationDeg: -89.5, clipping: none, anteriorUp: true },
    };
  }
  const DEFAULT_VIEW_SETS = Object.freeze({
    fourShowcase: Object.freeze(["right", "anterior", "posterior", "left"]),
    fourGrid: Object.freeze(["right", "left", "anterior", "posterior"]),
    sixShowcase: Object.freeze(["superior", "inferior", "right", "anterior", "posterior", "left"]),
    sixGrid: Object.freeze(["superior", "inferior", "right", "left", "anterior", "posterior"]),
  });
  function resolveViewSets(value) {
    const sets = value && typeof value === "object" ? value : {},pick=(key,count,legacy)=>Array.isArray(sets[key])&&sets[key].length===count?sets[key].map(text):legacy&&Array.isArray(sets[legacy])&&sets[legacy].length===count?sets[legacy].map(text):DEFAULT_VIEW_SETS[key].slice();
    return {fourShowcase:pick('fourShowcase',4,'four'),fourGrid:pick('fourGrid',4,'four'),sixShowcase:pick('sixShowcase',6,'six'),sixGrid:pick('sixGrid',6,'six')};
  }
  function layoutDefinition(preset, layout, viewSets) {
    const p = preset === "six" ? "six" : "four",
      l = layout === "grid" ? "grid" : "showcase",
      ids = resolveViewSets(viewSets)[`${p}${l === 'grid' ? 'Grid' : 'Showcase'}`];
    if (p === "four" && l === "showcase") return { columns: 4, rows: 1, tiles: ids.map((id, i) => [id, i, 0, 1]) };
    if (p === "four") return { columns: 2, rows: 2, tiles: ids.map((id, i) => [id, i % 2, Math.floor(i / 2), 1]) };
    if (l === "showcase") return { columns: 4, rows: 2, tiles: [[ids[0],0,0,2],[ids[1],2,0,2],...ids.slice(2).map((id,i)=>[id,i,1,1])] };
    return { columns: 2, rows: 3, tiles: ids.map((id, i) => [id, i % 2, Math.floor(i / 2), 1]) };
  }
  function imageCanvas(frame) {
    const canvas = document.createElement("canvas");
    canvas.width = frame.width;
    canvas.height = frame.height;
    const ctx = canvas.getContext("2d"),
      image = ctx.createImageData(frame.width, frame.height);
    image.data.set(frame.data);
    ctx.putImageData(image, 0, 0);
    return canvas;
  }
  function parseHex(hex) {
    let h = text(hex).replace("#", "");
    if (h.length === 3)
      h = h
        .split("")
        .map((c) => c + c)
        .join("");
    return /^[0-9a-f]{6}$/i.test(h)
      ? [
          parseInt(h.slice(0, 2), 16),
          parseInt(h.slice(2, 4), 16),
          parseInt(h.slice(4, 6), 16),
        ]
      : [0, 0, 0];
  }
  function luminance(hex) {
    const c = parseHex(hex)
      .map((v) => v / 255)
      .map((v) =>
        v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4),
      );
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
  }
  function resolveBackground(mode, inherit) {
    const m = ["inherit", "dark", "light", "transparent"].includes(mode)
        ? mode
        : "inherit",
      color =
        m === "dark"
          ? "#101722"
          : m === "light"
            ? "#f4f6f8"
            : inherit || "#18202a",
      alpha = m === "transparent" ? 0 : 1,
      light = m === "transparent" ? false : luminance(color) > 0.45;
    return {
      mode: m,
      color,
      alpha,
      text: light ? "rgba(15,23,42,.86)" : "rgba(255,255,255,.88)",
      muted: light ? "rgba(15,23,42,.62)" : "rgba(255,255,255,.64)",
      badge: light ? "rgba(255,255,255,.72)" : "rgba(15,23,42,.58)",
      border: light ? "rgba(15,23,42,.28)" : "rgba(255,255,255,.30)",
    };
  }
  function contentBounds(frame, background) {
    const bg = parseHex(background.color),
      w = frame.width,
      h = frame.height,
      d = frame.data;
    let x0 = w,
      y0 = h,
      x1 = -1,
      y1 = -1;
    for (let y = 0; y < h; y++)
      for (let x = 0; x < w; x++) {
        const q = 4 * (x + w * y),
          a = d[q + 3],
          delta =
            Math.abs(d[q] - bg[0]) +
            Math.abs(d[q + 1] - bg[1]) +
            Math.abs(d[q + 2] - bg[2]);
        if (background.alpha === 0 ? a > 8 : a > 8 && delta > 18) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    if (x1 < x0 || y1 < y0) return { x: 0, y: 0, width: w, height: h };
    const m = 2;
    return {
      x: Math.max(0, x0 - m),
      y: Math.max(0, y0 - m),
      width: Math.min(w - 1, x1 + m) - Math.max(0, x0 - m) + 1,
      height: Math.min(h - 1, y1 + m) - Math.max(0, y0 - m) + 1,
    };
  }
  function drawLabel(ctx, label, x, y, width, theme, annotationScale) {
    const scale = clamp(finite(annotationScale, 1), 1, 4);
    ctx.save();
    ctx.font = `600 ${11 * scale}px Arial`;
    ctx.textBaseline = "top";
    const pad = 4 * scale,
      edge = 3 * scale,
      w = Math.min(
        width - 2 * edge,
        Math.ceil(ctx.measureText(label).width) + 2 * pad,
      ),
      h = 18 * scale;
    ctx.fillStyle = theme.badge;
    ctx.fillRect(x + edge, y + edge, w, h);
    ctx.fillStyle = theme.text;
    ctx.fillText(label, x + edge + pad, y + 5 * scale);
    ctx.restore();
  }
  function drawOrientation(
    ctx,
    orientation,
    x,
    y,
    width,
    height,
    theme,
    annotationScale,
  ) {
    if (!orientation) return;
    const scale = clamp(finite(annotationScale, 1), 1, 4);
    ctx.save();
    ctx.font = `600 ${9 * scale}px Arial`;
    ctx.fillStyle = theme.muted;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    const inset = 8 * scale,
      marks = [
        [orientation.top, x + width / 2, y + inset],
        [orientation.bottom, x + width / 2, y + height - inset],
        [orientation.left, x + inset, y + height / 2],
        [orientation.right, x + width - inset, y + height / 2],
      ];
    marks.forEach((m) => {
      if (m[0]) ctx.fillText(m[0], m[1], m[2]);
    });
    ctx.restore();
  }
  function adaptiveGeometry(
    layout,
    prepared,
    gap,
    targetWidth,
    targetHeight,
    header,
    pad,
  ) {
    let cellWidth = 1, cellHeight = 1;
    layout.tiles.forEach((tile) => {
      const item = prepared[tile[0]];
      if (!item) return;
      cellWidth = Math.max(cellWidth, item.bounds.width / tile[3]);
      cellHeight = Math.max(cellHeight, item.bounds.height);
    });
    const cols = Array(layout.columns).fill(cellWidth),
      rows = Array(layout.rows).fill(cellHeight);
    const naturalW =
        cols.reduce((a, b) => a + b, 0) + (layout.columns - 1) * gap,
      naturalH = rows.reduce((a, b) => a + b, 0) + (layout.rows - 1) * gap,
      scale = Math.max(
        0.1,
        Math.min(
          (targetWidth - 2 * pad) / Math.max(1, naturalW),
          (targetHeight - header - 2 * pad) / Math.max(1, naturalH),
        ),
      ),
      colW = cols.map((v) => v * scale),
      rowH = rows.map((v) => v * scale),
      x = [pad],
      y = [header + pad];
    for (let i = 1; i < colW.length; i++) x[i] = x[i - 1] + colW[i - 1] + gap;
    for (let i = 1; i < rowH.length; i++) y[i] = y[i - 1] + rowH[i - 1] + gap;
    return {
      scale,
      colW,
      rowH,
      x,
      y,
      width: Math.ceil(
        pad * 2 + colW.reduce((a, b) => a + b, 0) + (layout.columns - 1) * gap,
      ),
      height: Math.ceil(
        header +
          pad * 2 +
          rowH.reduce((a, b) => a + b, 0) +
          (layout.rows - 1) * gap,
      ),
    };
  }
  function compose(
    layout,
    frames,
    settings,
    metadata,
    legend,
    background,
    target,
  ) {
    const theme = resolveBackground(settings.backgroundMode, background),
      annotationScale = clamp(finite(settings.annotationScale, 1), 1, 4),
      gap = settings.gapPx,
      header = 20 * annotationScale,
      pad = 3 * annotationScale,
      prepared = {};
    layout.tiles.forEach((t) => {
      const frame = frames[t[0]];
      if (frame)
        prepared[t[0]] = {
          frame,
          bounds: contentBounds(frame, theme),
          source: imageCanvas(frame),
        };
    });
    const tw = Math.max(480, finite(target && target.width, 1200)),
      th = Math.max(360, finite(target && target.height, 850)),
      legendScale = Math.max(tw/1500,th/780),
      legendReserve = legend ? Math.ceil(176*legendScale) : 0,
      geo = adaptiveGeometry(layout, prepared, gap, tw-legendReserve, th, header, pad),
      canvas = document.createElement("canvas");
    canvas.width = geo.width+legendReserve;
    canvas.height = geo.height;
    const ctx = canvas.getContext("2d");
    if (theme.alpha > 0) {
      ctx.fillStyle = theme.color;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
    } else ctx.clearRect(0, 0, canvas.width, canvas.height);
    const title = text((metadata && metadata[0]) || "3-D imaging montage");
    ctx.fillStyle = theme.muted;
    ctx.font = `${10 * annotationScale}px Arial`;
    ctx.textBaseline = "middle";
    ctx.fillText(title, pad + annotationScale, header / 2);
    if (legend) {
      window.NMImagingColorGradient.drawMontageColorbar(ctx, legend, geo.width,
        geo.height, legendScale, {text: theme.text, border: theme.border, threshold: theme.muted});
    }
    layout.tiles.forEach((t) => {
      const item = prepared[t[0]];
      if (!item) return;
      const x = geo.x[t[1]],
        y = geo.y[t[2]],
        w =
          geo.colW.slice(t[1], t[1] + t[3]).reduce((a, b) => a + b, 0) +
          (t[3] - 1) * gap,
        h = geo.rowH[t[2]],
        b = item.bounds,
        dw = b.width * geo.scale,
        dh = b.height * geo.scale,
        dx = x + (w - dw) / 2,
        dy = y + (h - dh) / 2;
      ctx.drawImage(
        item.source,
        b.x,
        b.y,
        b.width,
        b.height,
        Math.round(dx),
        Math.round(dy),
        Math.max(1, Math.round(dw)),
        Math.max(1, Math.round(dh)),
      );
      if (settings.labelsVisible)
        drawLabel(
          ctx,
          item.frame.label || t[0],
          x,
          y,
          w,
          theme,
          annotationScale,
        );
      if (settings.orientationVisible)
        drawOrientation(
          ctx,
          item.frame.orientation,
          x,
          y,
          w,
          h,
          theme,
          annotationScale,
        );
    });
    canvas.__nmBackground = theme;
    return canvas;
  }
  function closeButton() {
    return '<button type="button" class="rvImagingModalClose" data-3dm-close aria-label="Close 3-D montage"><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M4 4l12 12M16 4L4 16"></path></svg></button>';
  }
  function controlsHtml(value, options) {
    const state = normalizeState(value),
      disabled = options && options.disabled ? " disabled" : "";
    return `<label>Perspectives<select data-3dm-preset${disabled}><option value="four"${state.preset === "four" ? " selected" : ""}>4 perspectives</option><option value="six"${state.preset === "six" ? " selected" : ""}>6 perspectives</option></select></label><label>Layout<select data-3dm-layout${disabled}><option value="showcase"${state.layout === "showcase" ? " selected" : ""}>Layout A</option><option value="grid"${state.layout === "grid" ? " selected" : ""}>Layout B</option></select></label><label>Gap<input type="number" min="0" max="24" value="${state.gapPx}" data-3dm-gap${disabled}></label><label>Export resolution<select data-3dm-export-scale${disabled}><option value="2"${state.exportScale === 2 ? " selected" : ""}>2×</option><option value="3"${state.exportScale === 3 ? " selected" : ""}>3×</option><option value="4"${state.exportScale === 4 ? " selected" : ""}>4×</option></select></label><label>Background<select data-3dm-background${disabled}><option value="inherit"${state.backgroundMode === "inherit" ? " selected" : ""}>Inherit viewer</option><option value="dark"${state.backgroundMode === "dark" ? " selected" : ""}>Dark</option><option value="light"${state.backgroundMode === "light" ? " selected" : ""}>Light</option><option value="transparent"${state.backgroundMode === "transparent" ? " selected" : ""}>Transparent export</option></select></label><label class="rvImagingCheck"><input type="checkbox" data-3dm-labels${state.labelsVisible ? " checked" : ""}${disabled}> Labels</label><label class="rvImagingCheck"><input type="checkbox" data-3dm-orientation${state.orientationVisible ? " checked" : ""}${disabled}> Orientation</label>`;
  }
  function readControls(root, value) {
    if (!root || typeof root.querySelector !== "function") throw new Error("The 3-D Montage Maker control host is unavailable.");
    const state = normalizeState(value), preset = root.querySelector("[data-3dm-preset]"), layout = root.querySelector("[data-3dm-layout]"), gap = root.querySelector("[data-3dm-gap]"), exportScale = root.querySelector("[data-3dm-export-scale]"), background = root.querySelector("[data-3dm-background]"), labels = root.querySelector("[data-3dm-labels]"), orientation = root.querySelector("[data-3dm-orientation]");
    if (![preset, layout, gap, exportScale, background, labels, orientation].every(Boolean)) throw new Error("The 3-D Montage Maker control set is incomplete.");
    state.preset = preset.value; state.layout = layout.value; state.gapPx = gap.value; state.exportScale = exportScale.value; state.backgroundMode = background.value; state.labelsVisible = !!labels.checked; state.orientationVisible = !!orientation.checked;
    return normalizeState(state);
  }

  function elementVisible(el) {
    if (!el) return false;
    const r = el.getBoundingClientRect(),
      cs = window.getComputedStyle ? window.getComputedStyle(el) : null;
    return (
      r.width > 0 &&
      r.height > 0 &&
      (!cs || (cs.display !== "none" && cs.visibility !== "hidden"))
    );
  }
  function applyModalViewport(modal) {
    let left = 0,
      top = 0,
      right = window.innerWidth,
      bottom = window.innerHeight;
    const header = document.querySelector(".rvHeader,body>header,.wbHeader");
    if (elementVisible(header)) {
      const r = header.getBoundingClientRect();
      if (r.top <= 2 && r.bottom > 0) top = Math.max(top, Math.ceil(r.bottom));
    }
    const rail = document.querySelector(".nmNavRail");
    if (elementVisible(rail)) {
      const r = rail.getBoundingClientRect(),
        vertical = r.height >= window.innerHeight * 0.5;
      if (
        r.left <= 2 &&
        r.width < window.innerWidth * 0.5 &&
        window.innerWidth > 760
      )
        left = Math.max(left, Math.ceil(r.right));
      else if (!vertical && r.bottom >= window.innerHeight - 2)
        bottom = Math.min(bottom, Math.floor(r.top));
    }
    modal.style.setProperty("--rv-imaging-modal-left", `${left}px`);
    modal.style.setProperty("--rv-imaging-modal-top", `${top}px`);
    modal.style.setProperty(
      "--rv-imaging-modal-right",
      `${Math.max(0, window.innerWidth - right)}px`,
    );
    modal.style.setProperty(
      "--rv-imaging-modal-bottom",
      `${Math.max(0, window.innerHeight - bottom)}px`,
    );
  }
  function show(config) {
    if (!config || typeof config.renderView !== "function")
      throw new Error("A 3-D montage render callback is required.");
    const state = normalizeState(config.state),
      bounds = config.bounds || {
        min: [-1, -1, -1],
        max: [1, 1, 1],
        center: [0, 0, 0],
      },
      views = config.views && typeof config.views === "object" ? config.views : viewDefinitions(bounds),
      modal = document.createElement("div");
    modal.className = "rvImagingModal rvImaging3DMontageModal";
    modal.setAttribute("role", "dialog");
    modal.setAttribute("aria-modal", "true");
    modal.setAttribute("aria-label", "3-D montage");
    modal.innerHTML = `<div class="rvImagingModalCard"><header><h3>3-D montage</h3>${closeButton()}</header><div class="rvImagingModalControls rvImaging3DMontageToolbar">${controlsHtml(state)}<button type="button" class="primary" data-3dm-export disabled>Export montage</button><span data-3dm-status>Preparing montage…</span><details class="rvImaging3DMontageInfo"><summary>Info</summary><div>${(config.metadata || []).map((line) => `<div>${text(line)}</div>`).join("")}</div></details></div><div class="rvImaging3DMontagePreview" data-3dm-preview-wrap><canvas data-3dm-preview aria-label="3-D brain montage preview"></canvas></div></div>`;
    document.body.appendChild(modal);
    const preview = modal.querySelector("[data-3dm-preview]"),
      wrap = modal.querySelector("[data-3dm-preview-wrap]"),
      status = modal.querySelector("[data-3dm-status]"),
      exportButton = modal.querySelector("[data-3dm-export]");
    let generation = 0,
      composed = null,
      closed = false;
    const key = (e) => {
        if (e.key === "Escape") cleanup();
      },
      resize = () => {
        applyModalViewport(modal);
        render();
      },
      cleanup = () => {
        if (closed) return;
        closed = true;
        generation++;
        window.removeEventListener("resize", resize);
        document.removeEventListener("keydown", key);
        if (typeof config.onClose === "function") config.onClose();
        modal.remove();
      };
    modal.querySelector("[data-3dm-close]").addEventListener("click", cleanup);
    modal.addEventListener("click", (e) => {
      if (e.target === modal) cleanup();
    });
    window.addEventListener("resize", resize);
    document.addEventListener("keydown", key);
    applyModalViewport(modal);
    const render = async () => {
      const g = ++generation,
        layout = layoutDefinition(state.preset, state.layout, config.viewSets),
        frames = {},
        bg = resolveBackground(state.backgroundMode, config.backgroundColor),
        dpr = window.devicePixelRatio,
        fit = Math.min(wrap.clientWidth / (layout.columns * state.tileWidth),
          wrap.clientHeight / (layout.rows * state.tileHeight)),
        ratio = clamp(Math.ceil(fit * dpr), 1, 6),
        target = {
          width: Math.max(640, wrap.clientWidth - 6) * dpr,
          height: Math.max(420, wrap.clientHeight - 6) * dpr,
        };
      status.textContent = "Rendering standardized perspectives…";
      exportButton.disabled = true;
      try {
        for (const tile of layout.tiles) {
          if (closed || g !== generation) return;
          const id = tile[0],
            frame = await config.renderView(
              views[id],
              state.tileWidth * ratio,
              state.tileHeight * ratio,
              { color: bg.color, alpha: bg.alpha },
            );
          frame.label = views[id].label;
          frames[id] = frame;
        }
        if (closed || g !== generation) return;
        composed = compose(
          layout,
          frames,
          Object.assign({}, state, {gapPx: state.gapPx * ratio, annotationScale: ratio}),
          config.metadata || [],
          config.legend || null,
          config.backgroundColor,
          target,
        );
        preview.width = composed.width;
        preview.height = composed.height;
        preview.getContext("2d").drawImage(composed, 0, 0);
        wrap.dataset.backgroundMode = state.backgroundMode;
        status.textContent = `${layout.tiles.length} standardized perspectives · common scale`;
        exportButton.disabled = false;
      } catch (err) {
        status.textContent = (err && err.message) || String(err);
        if (typeof config.onError === "function") config.onError(err);
      }
    };
    const sync = () => {
      Object.assign(state, readControls(modal, state));
      if (typeof config.onStateChange === "function") config.onStateChange(state);
      render();
    };
    ["preset", "layout", "background", "export-scale"].forEach((k) =>
      modal.querySelector(`[data-3dm-${k}]`).addEventListener("change", sync),
    );
    modal.querySelector("[data-3dm-gap]").addEventListener("input", sync);
    modal.querySelector("[data-3dm-labels]").addEventListener("change", sync);
    modal
      .querySelector("[data-3dm-orientation]")
      .addEventListener("change", sync);
    exportButton.addEventListener("click", async () => {
      if (!composed || closed) return;
      const layout = layoutDefinition(state.preset, state.layout, config.viewSets),
        frames = {},
        bg = resolveBackground(state.backgroundMode, config.backgroundColor),
        scale = state.exportScale;
      exportButton.disabled = true;
      status.textContent = `Rendering publication PNG (${scale}×)…`;
      try {
        for (const tile of layout.tiles) {
          if (closed) return;
          const id = tile[0],
            frame = await config.renderView(
              views[id],
              state.tileWidth * scale,
              state.tileHeight * scale,
              { color: bg.color, alpha: bg.alpha },
            );
          frame.label = views[id].label;
          frames[id] = frame;
        }
        const target = {
            width: Math.max(1200, state.tileWidth * scale * layout.columns),
            height: Math.max(850, state.tileHeight * scale * layout.rows),
          },
          publication = compose(
            layout,
            frames,
            Object.assign({}, state, {
              gapPx: state.gapPx * scale,
              annotationScale: scale,
            }),
            config.metadata || [],
            config.legend || null,
            config.backgroundColor,
            target,
          );
        if (typeof config.onExport !== "function")
          throw new Error("No generic artifact exporter was supplied.");
        await config.onExport(publication, { state: Object.assign({}, state) });
        status.textContent = `Publication output · ${publication.width} × ${publication.height}px`;
      } catch (err) {
        status.textContent = (err && err.message) || String(err);
        if (typeof config.onError === "function") config.onError(err);
      } finally {
        exportButton.disabled = false;
      }
    });
    requestAnimationFrame(() => render());
    return { close: cleanup, render, state };
  }
  window.NMResultsViewer3DMontage = {
    normalizeState,
    controlsHtml,
    readControls,
    viewDefinitions,
    layoutDefinition,
    resolveViewSets,
    contentBounds,
    resolveBackground,
    adaptiveGeometry,
    compose,
    show,
  };
})();
