/*
 * NMImagingVolumePrep — volume and surface-support preparation.
 *
 * Worker-safe: no window, no document, no DOM. Produces flat typed arrays laid out
 * for gl.texImage3D (x fastest, then y, then z) together with column-major
 * world -> normalised-texture-coordinate matrices.
 *
 * Four products:
 *   prepareStructural()              cropped structural scalar + gradient
 *   prepareNativeFeature()           native value/support grid (authoritative)
 *   prepareCoverage()                dual-polarity volume-rendering envelopes
 *   prepareLocalSupportEnhancement() threshold-free local-support alpha field
 *
 * Contract (NMImagingVolumeRenderingContract):
 *   decisions and reported values are native and nearest. Production geometry is
 *   reconstructed from per-component signed-distance envelopes with preserved
 *   physical volume; colour is reconstructed separately. sigma = 0 reproduces the
 *   native voxel boundary exactly. The historic occupancy-Gaussian field remains
 *   available only through the explicit gaussian_audit descriptor.
 *
 * Local support enhancement is a separate, non-inferential
 * presentation field. It changes alpha only and does not enter support,
 * threshold, sign, value, or hard-maximum depth selection.
 */
(function (root) {
  'use strict';

  const {clamp,nowMs}=globalThis.NMResultsViewerPrimitives;
  const KERNEL_TRUNCATION_SIGMA = 3;
  /* Default physical width of the signed-distance curvature-smoothing pass. */
  const DEFAULT_SIGMA_FACTOR = 1.2;
  /*
   * Public compatibility constant retained for older diagnostics. Production no
   * longer uses a small-cluster Gaussian branch.
   */
  const SMALL_SCALE_SIGMA_FACTOR = 0.25;
  const DEFAULT_MEMORY_BUDGET_BYTES = 48 * 1024 * 1024;
  function finite(v, d) { const n = Number(v); return Number.isFinite(n) ? n : d; }
  function arr(v) { return (Array.isArray(v) || ArrayBuffer.isView(v)) ? Array.from(v) : []; }
  function displaySemantics() {
    let api = root.NMResultsViewerDisplaySemantics;
    if ((!api || typeof api.assertDisplayContract !== 'function') && typeof module !== 'undefined' && module.exports && typeof require === 'function') api = require('./NMImagingDisplaySemantics.js');
    if (!api || typeof api.assertDisplayContract !== 'function') throw new Error('The canonical Results Viewer display-contract assertion authority is unavailable.');
    return api;
  }

  function dims3(value) {
    const d = arr(value).slice(0, 3).map(v => Math.max(1, Math.floor(finite(v, 1))));
    while (d.length < 3) d.push(1);
    return d;
  }
  function spacing3(value) {
    const s = arr(value).slice(0, 3).map(v => Math.max(1e-6, Math.abs(finite(v, 1))));
    while (s.length < 3) s.push(1);
    return s;
  }
  /*
   * Affines reach this module in more than one shape, and the difference is not
   * cosmetic: locatorStructuralDescriptor supplies invert4x4() output (4 nested
   * rows) while the feature record supplies worldToFeatureVoxel, which is a flat
   * 16-value row-major array. The renderer's own matrixRowsToColumnMajor accepts
   * both, so this must too. A 3x4 form (affine rows without the homogeneous row)
   * is also accepted and completed with [0,0,0,1].
   */
  function matrixRows4(value) {
    const source = (Array.isArray(value) || ArrayBuffer.isView(value)) ? Array.from(value) : null;
    if (!source) throw new Error('A 4x4 affine matrix or a row-major array of 16 values is required.');
    const nested = source.length && (Array.isArray(source[0]) || ArrayBuffer.isView(source[0]));
    let values = null;
    if (nested) {
      const rows = source.map(r => Array.from(r, Number));
      if ((rows.length === 4 || rows.length === 3) && rows.every(r => r.length === 4)) {
        values = rows.reduce((a, r) => a.concat(r), []);
      }
    } else if (source.length === 16 || source.length === 12) {
      values = source.map(Number);
    }
    if (values && values.length === 12) values = values.concat([0, 0, 0, 1]);
    if (!values || values.length !== 16) {
      throw new Error('A 4x4 affine matrix or a row-major array of 16 values is required.');
    }
    if (values.some(v => !Number.isFinite(v))) {
      throw new Error('The affine matrix contains a non-finite value.');
    }
    return [0, 1, 2, 3].map(r => values.slice(r * 4, r * 4 + 4));
  }
  function rowsToColumnMajor(rows) {
    const out = new Float32Array(16);
    for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) out[c * 4 + r] = rows[r][c];
    return out;
  }

  /*
   * worldToVoxel in this codebase yields 1-based voxel-centre coordinates: voxel k
   * (0-based) has its centre at value k + 1. Everything below works in 0-based
   * continuous coordinates, so the incoming matrix is shifted by -1 once, here.
   */
  function worldToVoxel0Rows(worldToVoxel) {
    const rows = matrixRows4(worldToVoxel).map(r => r.slice());
    for (let i = 0; i < 3; i++) rows[i][3] -= 1;
    return rows;
  }

  /* world -> normalised 3D texture coordinates, given a crop origin and a refine factor. */
  function textureMatrix(worldToVoxel0, origin, refine, dims) {
    const rows = worldToVoxel0.map(r => r.slice());
    for (let i = 0; i < 3; i++) {
      const k = refine[i] / dims[i];
      rows[i][3] = k * (rows[i][3] - origin[i] + 0.5);
      for (let c = 0; c < 3; c++) rows[i][c] *= k;
    }
    return rowsToColumnMajor(rows);
  }

  /* world -> 0-based voxel index, for texelFetch of the authoritative native grid. */
  function voxelIndexMatrix(worldToVoxel0) {
    return rowsToColumnMajor(worldToVoxel0);
  }

  // ---------------------------------------------------------------- thresholds

  /* Bit-identical to projectionClass() in the fragment shader. */
  function projectionClass(value, spec) {
    if (!Number.isFinite(value)) return 0;
    if (spec.mode === 1) {
      if (value <= spec.negative) return -1;
      if (value >= spec.positive) return 1;
      return 0;
    }
    if (spec.mode === 2) {
      const t = Math.abs(spec.single);
      if (Math.abs(value) < t) return 0;
      return value < 0 ? -1 : (value > 0 ? 1 : 0);
    }
    if (spec.mode === 3) return value <= spec.single ? -1 : 0;
    if (spec.mode === 4) return value >= spec.single ? 1 : 0;
    return value < 0 ? -1 : (value > 0 ? 1 : 0);
  }

  function thresholdSpec(contract) {
    displaySemantics().assertDisplayContract(contract,{consumer:'NMImagingVolumePrep threshold extraction',message:'Volume preparation requires a canonical display contract.',facets:['threshold']});
    const threshold = contract.threshold;
    const mode = displaySemantics().thresholdModeCode(threshold.mode);
    if (mode === 1) {
      if (!Number.isFinite(threshold.lower) || !Number.isFinite(threshold.upper) || !(threshold.lower < threshold.upper)) throw new Error('Canonical outside-interval thresholds are invalid.');
      return { mode, negative: threshold.lower, positive: threshold.upper, single: 0 };
    }
    if (mode === 2 || mode === 3 || mode === 4) {
      if (!Number.isFinite(threshold.value)) throw new Error('Canonical single threshold is invalid.');
      if (mode === 2 && threshold.value < 0) throw new Error('Canonical absolute threshold is negative.');
      return { mode, negative: 0, positive: 0, single: threshold.value };
    }
    return { mode, negative: 0, positive: 0, single: 0 };
  }

  /* Native, nearest, authoritative. No interpolation participates. */
  function nativeClassField(data, support, dims, spec) {
    const n = dims[0] * dims[1] * dims[2];
    if (!data || data.length !== n) throw new Error('Feature data do not match their dimensions.');
    if (support && support.length !== n) throw new Error('Feature support does not match its dimensions.');
    const klass = new Int8Array(n);
    let positiveCount = 0, negativeCount = 0;
    for (let i = 0; i < n; i++) {
      if (support && support[i] === 0) continue;
      const c = projectionClass(Number(data[i]), spec);
      klass[i] = c;
      if (c > 0) positiveCount++; else if (c < 0) negativeCount++;
    }
    return { klass, positiveCount, negativeCount };
  }

  // ------------------------------------------------------------- gaussian blur

  function gaussianKernel(spacingMm, sigmaMm) {
    const spacing = Math.max(1e-6, finite(spacingMm, 1));
    const sigma = Math.max(0, finite(sigmaMm, 0));
    if (sigma === 0) return new Float32Array([1]);
    const radius = Math.max(1, Math.ceil(KERNEL_TRUNCATION_SIGMA * sigma / spacing));
    const kernel = new Float32Array(radius * 2 + 1);
    let total = 0;
    for (let o = -radius; o <= radius; o++) {
      const d = o * spacing, w = Math.exp(-0.5 * (d / sigma) * (d / sigma));
      kernel[o + radius] = w;
      total += w;
    }
    for (let i = 0; i < kernel.length; i++) kernel[i] /= total;
    return kernel;
  }

  /*
   * Separable convolution with clamped edges, operating in place across a scratch
   * line buffer. Lines that are entirely zero are skipped -- statistical maps are
   * sparse and this dominates the runtime saving on real data.
   */
  function convolveAxis(field, dims, kernel, axis) {
    if (kernel.length < 2) return field;
    const dx = dims[0], dy = dims[1], dz = dims[2];
    const radius = (kernel.length - 1) >> 1;
    const length = dims[axis];
    const stride = axis === 0 ? 1 : (axis === 1 ? dx : dx * dy);
    const outer0 = axis === 0 ? dy : dx;
    const outer1 = axis === 0 ? dz : (axis === 1 ? dz : dy);
    const step0 = axis === 0 ? dx : 1;
    const step1 = axis === 0 ? dx * dy : (axis === 1 ? dx * dy : dx);
    const line = new Float32Array(length);
    const interiorLo = Math.min(radius, length);
    const interiorHi = Math.max(interiorLo, length - radius);

    for (let b = 0; b < outer1; b++) {
      for (let a = 0; a < outer0; a++) {
        const base = a * step0 + b * step1;

        // Gather the line and bail out early: statistical maps are sparse and most
        // lines are identically zero, which dominates the runtime saving.
        let first = -1, last = -1;
        for (let i = 0; i < length; i++) {
          const v = field[base + i * stride];
          line[i] = v;
          if (v !== 0) { if (first < 0) first = i; last = i; }
        }
        if (first < 0) continue;

        const lo = Math.max(0, first - radius), hi = Math.min(length - 1, last + radius);
        for (let i = lo; i <= hi; i++) {
          let sum = 0;
          if (i >= interiorLo && i < interiorHi) {
            // Interior: no clamping, tight loop.
            const start = i - radius;
            for (let k = 0; k < kernel.length; k++) sum += line[start + k] * kernel[k];
          } else {
            for (let k = -radius; k <= radius; k++) {
              let j = i + k;
              if (j < 0) j = 0; else if (j >= length) j = length - 1;
              sum += line[j] * kernel[k + radius];
            }
          }
          field[base + i * stride] = sum;
        }
        // Zero anything the widened support did not reach but that was non-zero before.
        for (let i = 0; i < lo; i++) field[base + i * stride] = 0;
        for (let i = hi + 1; i < length; i++) field[base + i * stride] = 0;
      }
    }
    return field;
  }

  /*
   * Exact squared Euclidean distance transform, Felzenszwalb & Huttenlocher's
   * lower-envelope-of-parabolas method: O(n) per axis, separable, exact in world
   * millimetres for anisotropic spacing.
   */
  function edt1d(f, out, length, spacing, v, z) {
    let k = 0;
    v[0] = 0; z[0] = -Infinity; z[1] = Infinity;
    for (let q = 1; q < length; q++) {
      const pq = q * spacing;
      let s;
      for (;;) {
        const pv = v[k] * spacing;
        s = ((f[q] + pq * pq) - (f[v[k]] + pv * pv)) / (2 * pq - 2 * pv);
        if (s <= z[k]) k--; else break;
      }
      k++; v[k] = q; z[k] = s; z[k + 1] = Infinity;
    }
    k = 0;
    for (let q = 0; q < length; q++) {
      const pq = q * spacing;
      while (z[k + 1] < pq) k++;
      const d = pq - v[k] * spacing;
      out[q] = d * d + f[v[k]];
    }
  }

  /* Distance in mm from each occupied voxel to the nearest unoccupied voxel. */
  function insideDistance(indicator, dims, spacingMm) {
    const [dx, dy, dz] = dims;
    const n = dx * dy * dz;
    const field = new Float32Array(n);
    const INF = 1e20;
    for (let i = 0; i < n; i++) field[i] = indicator[i] ? INF : 0;
    const maxLen = Math.max(dx, dy, dz);
    const line = new Float32Array(maxLen), out = new Float32Array(maxLen);
    const v = new Int32Array(maxLen), z = new Float32Array(maxLen + 1);
    const axes = [
      { length: dx, stride: 1, outer0: dy, step0: dx, outer1: dz, step1: dx * dy, spacing: spacingMm[0] },
      { length: dy, stride: dx, outer0: dx, step0: 1, outer1: dz, step1: dx * dy, spacing: spacingMm[1] },
      { length: dz, stride: dx * dy, outer0: dx, step0: 1, outer1: dy, step1: dx, spacing: spacingMm[2] }
    ];
    for (const axis of axes) {
      for (let b = 0; b < axis.outer1; b++) {
        for (let a = 0; a < axis.outer0; a++) {
          const base = a * axis.step0 + b * axis.step1;
          let any = false;
          for (let i = 0; i < axis.length; i++) {
            const value = field[base + i * axis.stride];
            line[i] = value;
            if (value !== 0) any = true;
          }
          if (!any) continue;
          edt1d(line, out, axis.length, axis.spacing, v, z);
          for (let i = 0; i < axis.length; i++) field[base + i * axis.stride] = out[i];
        }
      }
    }
    for (let i = 0; i < n; i++) field[i] = Math.sqrt(field[i]);
    return field;
  }

  /*
   * Largest inscribed-ball radius anywhere in each 6-connected component, assigned
   * to every voxel of that component. This is the "contiguous mass" scale: a long
   * thin tube scores low however far it extends, a compact blob scores high, so it
   * captures anisotropy of shape rather than of extent. Computed on the native
   * grid, which is far smaller than the coverage grid and has identical
   * connectivity under nearest-neighbour replication.
   */
  /* 6-connected component labels; -1 outside. Shared by the scale measure and the
     cluster-representation report so both agree on what a cluster is. */
  function componentLabels(indicator, dims) {
    const [dx, dy, dz] = dims, n = dx * dy * dz;
    const label = new Int32Array(n).fill(-1);
    const parent = [];
    const find = a => { while (parent[a] !== a) { parent[a] = parent[parent[a]]; a = parent[a]; } return a; };
    const union = (a, b) => { a = find(a); b = find(b); if (a !== b) parent[b] = a; };
    for (let z = 0; z < dz; z++) {
      for (let y = 0; y < dy; y++) {
        for (let x = 0; x < dx; x++) {
          const i = x + dx * (y + dy * z);
          if (!indicator[i]) continue;
          const neighbours = [x > 0 ? label[i - 1] : -1, y > 0 ? label[i - dx] : -1, z > 0 ? label[i - dx * dy] : -1];
          let root = -1;
          for (const nb of neighbours) {
            if (nb < 0) continue;
            if (root < 0) root = find(nb); else union(root, nb);
          }
          if (root < 0) { root = parent.length; parent.push(root); }
          label[i] = root;
        }
      }
    }
    for (let i = 0; i < n; i++) if (label[i] >= 0) label[i] = find(label[i]);
    return label;
  }

  function componentScale(indicator, dims, spacingMm) {
    const [dx, dy, dz] = dims, n = dx * dy * dz;
    const distance = insideDistance(indicator, dims, spacingMm);
    const label = componentLabels(indicator, dims);
    const peak = new Map();
    for (let i = 0; i < n; i++) {
      if (label[i] < 0) continue;
      const d = distance[i];
      if (!peak.has(label[i]) || d > peak.get(label[i])) peak.set(label[i], d);
    }
    const scale = new Float32Array(n);
    for (let i = 0; i < n; i++) if (label[i] >= 0) scale[i] = peak.get(label[i]) || 0;
    return scale;
  }

  function smoothSeparable(field, dims, spacingMm, sigmaMm) {
    if (!(sigmaMm > 0)) return field;
    for (let axis = 0; axis < 3; axis++) {
      convolveAxis(field, dims, gaussianKernel(spacingMm[axis], sigmaMm), axis);
    }
    return field;
  }

  function signedDistanceField(indicator, dims, spacingMm) {
    const n = dims[0] * dims[1] * dims[2];
    if (!indicator || indicator.length !== n) throw new Error('Signed-distance support does not match its dimensions.');
    const inverse = new Uint8Array(n);
    for (let i = 0; i < n; i++) inverse[i] = indicator[i] ? 0 : 1;
    const inside = insideDistance(indicator, dims, spacingMm);
    const outside = insideDistance(inverse, dims, spacingMm);
    const signed = new Float32Array(n);
    for (let i = 0; i < n; i++) signed[i] = inside[i] - outside[i];
    return signed;
  }

  function componentRecords(indicator, dims) {
    const labels = componentLabels(indicator, dims), recordsById = new Map();
    const [dx, dy] = dims;
    for (let z = 0; z < dims[2]; z++) {
      for (let y = 0; y < dims[1]; y++) {
        const row = dx * (y + dy * z);
        for (let x = 0; x < dx; x++) {
          const id = labels[row + x];
          if (id < 0) continue;
          let record = recordsById.get(id);
          if (!record) {
            record = { id, count: 0, lo: [x, y, z], hi: [x, y, z] };
            recordsById.set(id, record);
          }
          record.count++;
          if (x < record.lo[0]) record.lo[0] = x; if (x > record.hi[0]) record.hi[0] = x;
          if (y < record.lo[1]) record.lo[1] = y; if (y > record.hi[1]) record.hi[1] = y;
          if (z < record.lo[2]) record.lo[2] = z; if (z > record.hi[2]) record.hi[2] = z;
        }
      }
    }
    return { labels, records: Array.from(recordsById.values()).sort((a, b) => a.id - b.id) };
  }

  function volumePreservingLevel(field, targetCount) {
    const n = field.length;
    if (!n) throw new Error('Cannot determine an envelope level from an empty field.');
    const target = clamp(Math.round(finite(targetCount, 0)), 1, Math.max(1, n - 1));
    const sorted = new Float32Array(field);
    sorted.sort();
    const split = n - target;
    if (split <= 0) return sorted[0] - Math.max(1e-6, Math.abs(sorted[0]) * 1e-6);
    if (split >= n) return sorted[n - 1] + Math.max(1e-6, Math.abs(sorted[n - 1]) * 1e-6);
    return 0.5 * (sorted[split - 1] + sorted[split]);
  }

  function smoothstepRange(value, lo, hi) {
    const t = clamp((value - lo) / Math.max(1e-12, hi - lo), 0, 1);
    return t * t * (3 - 2 * t);
  }

  /*
   * Component-wise, volume-preserving signed-distance envelope.
   *
   * Each polarity is split into 6-connected native components. A component is
   * replicated onto the refined physical grid, converted to an exact Euclidean
   * signed-distance field, smoothed in millimetres, and assigned a component-
   * specific iso-level that preserves its native physical volume. The final
   * polarity field is the maximum of those independent envelopes.
   *
   * This differs fundamentally from smoothing a binary occupancy field. A small
   * component is no longer forced below a fixed 0.5 level merely because the
   * Gaussian kernel is wider than the component. The level moves to preserve the
   * component volume, while the signed-distance geometry rounds voxel corners and
   * removes axis-aligned stair steps. Native support, thresholds, values and
   * component identity remain authoritative.
   */
  function signedDistanceEnvelope(info, nativeDims, boxLo, refine, coverageDims, coverageSpacing, sigmaMm) {
    const startedAt = nowMs(), out = new Float32Array(coverageDims[0] * coverageDims[1] * coverageDims[2]);
    const refineProduct = refine[0] * refine[1] * refine[2];
    const maxCoverageSpacing = Math.max.apply(null, coverageSpacing);
    const padMm = Math.max(2 * maxCoverageSpacing, KERNEL_TRUNCATION_SIGMA * sigmaMm + maxCoverageSpacing);
    const pad = coverageSpacing.map(s => Math.max(2, Math.ceil(padMm / s)));
    let targetCells = 0, realisedCells = 0, componentsKept = 0;

    for (const component of info.records) {
      const globalLo = [0, 1, 2].map(i => clamp(
        (component.lo[i] - boxLo[i]) * refine[i] - pad[i], 0, coverageDims[i] - 1));
      const globalHi = [0, 1, 2].map(i => clamp(
        (component.hi[i] - boxLo[i] + 1) * refine[i] - 1 + pad[i], 0, coverageDims[i] - 1));
      const localDims = [0, 1, 2].map(i => globalHi[i] - globalLo[i] + 1);
      const localCount = localDims[0] * localDims[1] * localDims[2];
      const indicator = new Uint8Array(localCount);

      for (let z = component.lo[2]; z <= component.hi[2]; z++) {
        for (let y = component.lo[1]; y <= component.hi[1]; y++) {
          const nativeRow = nativeDims[0] * (y + nativeDims[1] * z);
          for (let x = component.lo[0]; x <= component.hi[0]; x++) {
            if (info.labels[nativeRow + x] !== component.id) continue;
            const lx0 = (x - boxLo[0]) * refine[0] - globalLo[0];
            const ly0 = (y - boxLo[1]) * refine[1] - globalLo[1];
            const lz0 = (z - boxLo[2]) * refine[2] - globalLo[2];
            for (let rz = 0; rz < refine[2]; rz++) {
              for (let ry = 0; ry < refine[1]; ry++) {
                const start = lx0 + localDims[0] * ((ly0 + ry) + localDims[1] * (lz0 + rz));
                indicator.fill(1, start, start + refine[0]);
              }
            }
          }
        }
      }

      const target = component.count * refineProduct;
      targetCells += target;
      const signed = signedDistanceField(indicator, localDims, coverageSpacing);
      smoothSeparable(signed, localDims, coverageSpacing, sigmaMm);
      const level = volumePreservingLevel(signed, target);
      const featherMm = Math.max(0.5 * Math.min.apply(null, coverageSpacing), Math.min(maxCoverageSpacing, 0.20 * sigmaMm));
      const lo = level - featherMm, hi = level + featherMm;
      let componentRealised = 0;

      for (let z = 0; z < localDims[2]; z++) {
        const gz = globalLo[2] + z;
        for (let y = 0; y < localDims[1]; y++) {
          const gy = globalLo[1] + y;
          const localRow = localDims[0] * (y + localDims[1] * z);
          const globalRow = coverageDims[0] * (gy + coverageDims[1] * gz) + globalLo[0];
          for (let x = 0; x < localDims[0]; x++) {
            const coverage = smoothstepRange(signed[localRow + x], lo, hi);
            if (coverage >= 0.5) componentRealised++;
            const gi = globalRow + x;
            if (coverage > out[gi]) out[gi] = coverage;
          }
        }
      }
      realisedCells += componentRealised;
      if (componentRealised > 0) componentsKept++;
    }

    return {
      field: out,
      components: info.records.length,
      componentsKept,
      targetCells,
      realisedCells,
      prepareMs: nowMs() - startedAt,
      reconstruction: 'component_signed_distance_volume_preserving'
    };
  }

  // --------------------------------------------------------- structural volume

  /*
   * Crops to the support bounding box, dilates scalar and gradient outward across
   * the support boundary, and precomputes a world-space gradient.
   *
   * The dilation matters: without it, hardware trilinear filtering blends real
   * tissue against zeros in the half-texel shell outside the mask, which
   * manufactures a spurious high-gradient interface exactly at the brain edge.
   * That artefact is a contributor to the "etched contour" appearance.
   */
  function prepareStructural(descriptor) {
    const startedAt = nowMs();
    const desc = descriptor && typeof descriptor === 'object' ? descriptor : {};
    const srcDims = dims3(desc.dims);
    const n = srcDims[0] * srcDims[1] * srcDims[2];
    const data = desc.data, support = desc.support;
    if (!data || data.length !== n) throw new Error('Structural data do not match their dimensions.');
    if (support && support.length !== n) throw new Error('Structural support does not match its dimensions.');

    const range = arr(desc.valueRange).slice(0, 2).map(Number);
    const lo = finite(range[0], NaN), hi = finite(range[1], NaN);
    if (!Number.isFinite(lo) || !Number.isFinite(hi) || hi <= lo) {
      throw new Error('Structural display window is invalid.');
    }
    const spacing = spacing3(desc.spacingMm);
    const voxelToWorld = matrixRows4(desc.voxelToWorld);
    const worldToVoxel0 = worldToVoxel0Rows(desc.worldToVoxel);
    const margin = Math.max(0, Math.floor(finite(desc.cropMarginVoxels, 2)));
    const srcIndex = (x, y, z) => x + srcDims[0] * (y + srcDims[1] * z);
    const valid = i => (!support || support[i] !== 0) && Number.isFinite(Number(data[i]));

    // --- crop to the support bounding box
    let x0 = srcDims[0], y0 = srcDims[1], z0 = srcDims[2], x1 = -1, y1 = -1, z1 = -1;
    for (let z = 0; z < srcDims[2]; z++) {
      for (let y = 0; y < srcDims[1]; y++) {
        for (let x = 0; x < srcDims[0]; x++) {
          if (!valid(srcIndex(x, y, z))) continue;
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
          if (z < z0) z0 = z; if (z > z1) z1 = z;
        }
      }
    }
    if (x1 < 0) throw new Error('The structural volume contains no supported voxels.');
    const origin = [
      Math.max(0, x0 - margin), Math.max(0, y0 - margin), Math.max(0, z0 - margin)
    ];
    const dims = [
      Math.min(srcDims[0] - 1, x1 + margin) - origin[0] + 1,
      Math.min(srcDims[1] - 1, y1 + margin) - origin[1] + 1,
      Math.min(srcDims[2] - 1, z1 + margin) - origin[2] + 1
    ];
    const maxTextureSize = Math.max(16, Math.floor(finite(desc.maxTextureSize, 2048)));
    if (dims.some(d => d > maxTextureSize)) {
      throw new Error(`Cropped structural volume ${dims.join('x')} exceeds MAX_3D_TEXTURE_SIZE ${maxTextureSize}.`);
    }

    const m = dims[0] * dims[1] * dims[2];
    const index = (x, y, z) => x + dims[0] * (y + dims[1] * z);
    const scalar = new Float32Array(m);
    const inside = new Uint8Array(m);

    for (let z = 0; z < dims[2]; z++) {
      for (let y = 0; y < dims[1]; y++) {
        for (let x = 0; x < dims[0]; x++) {
          const s = srcIndex(x + origin[0], y + origin[1], z + origin[2]);
          const d = index(x, y, z);
          if (valid(s)) {
            scalar[d] = clamp((Number(data[s]) - lo) / (hi - lo), 0, 1);
            inside[d] = 1;
          }
        }
      }
    }

    // --- dilate scalar outward across the support boundary (two voxels)
    const filled = new Uint8Array(inside);
    for (let pass = 0; pass < 2; pass++) {
      const previous = new Uint8Array(filled);
      for (let z = 0; z < dims[2]; z++) {
        for (let y = 0; y < dims[1]; y++) {
          for (let x = 0; x < dims[0]; x++) {
            const d = index(x, y, z);
            if (previous[d]) continue;
            let sum = 0, count = 0;
            for (let a = 0; a < 6; a++) {
              const xx = x + (a === 0 ? -1 : a === 1 ? 1 : 0);
              const yy = y + (a === 2 ? -1 : a === 3 ? 1 : 0);
              const zz = z + (a === 4 ? -1 : a === 5 ? 1 : 0);
              if (xx < 0 || yy < 0 || zz < 0 || xx >= dims[0] || yy >= dims[1] || zz >= dims[2]) continue;
              const e = index(xx, yy, zz);
              if (!previous[e]) continue;
              sum += scalar[e]; count++;
            }
            if (count) { scalar[d] = sum / count; filled[d] = 1; }
          }
        }
      }
    }

    /*
     * The gradient must be taken of the field the renderer actually crosses.
     *
     * The visible surface is the level set of `scalar x support` (structuralField
     * in the shader), but the stored normal was the gradient of `scalar` alone.
     * Since grad(s*u) = u*grad(s) + s*grad(u), the second term was simply missing,
     * and it dominates wherever the crossing lies inside the support transition --
     * which is exactly where low surface levels put it, and where the anatomically
     * locked dark/light lines appear.
     *
     * Measured against a finite-difference reference of the crossing field on a
     * folded surrogate (p90 disagreement, degrees):
     *
     *     level   scalar only   scalar x support   scalar Sobel
     *     0.15       50.53          22.53             36.26
     *     0.35       17.30           8.79             24.03
     *     0.55        9.34           8.81             21.49
     *
     * An 8-corner Sobel was tested as well, on both fields, and was worse at every
     * level: its wider stencil oversmooths folded cortex. Feathering the support
     * before forming the product was also worse. The field mismatch, not the
     * differencing operator, was the defect.
     *
     * The dilated scalar is still what gets stored and coloured; only the gradient
     * source changes.
     */
    const crossingField = new Float32Array(m);
    for (let i = 0; i < m; i++) crossingField[i] = scalar[i] * (inside[i] ? 1 : 0);
    const blurred = new Float32Array(crossingField);
    smoothSeparable(blurred, dims, spacing, Math.max(spacing[0], spacing[1], spacing[2]) * 0.5);

    const axisToWorld = [0, 1, 2].map(r => [
      voxelToWorld[r][0] / spacing[0], voxelToWorld[r][1] / spacing[1], voxelToWorld[r][2] / spacing[2]
    ]);
    const sampleBlur = (x, y, z) => blurred[index(clamp(x, 0, dims[0] - 1), clamp(y, 0, dims[1] - 1), clamp(z, 0, dims[2] - 1))];
    const gradientAt = (x, y, z) => {
      const gx = (sampleBlur(x + 1, y, z) - sampleBlur(x - 1, y, z)) / (2 * spacing[0]);
      const gy = (sampleBlur(x, y + 1, z) - sampleBlur(x, y - 1, z)) / (2 * spacing[1]);
      const gz = (sampleBlur(x, y, z + 1) - sampleBlur(x, y, z - 1)) / (2 * spacing[2]);
      const wx = axisToWorld[0][0] * gx + axisToWorld[0][1] * gy + axisToWorld[0][2] * gz;
      const wy = axisToWorld[1][0] * gx + axisToWorld[1][1] * gy + axisToWorld[1][2] * gz;
      const wz = axisToWorld[2][0] * gx + axisToWorld[2][1] * gy + axisToWorld[2][2] * gz;
      return [wx, wy, wz, Math.hypot(wx, wy, wz)];
    };

    // robust gradient scale from a deterministic subsample
    const magnitudes = [];
    for (let linear = 0; linear < m; linear += 17) {
      if (!filled[linear]) continue;
      const z = Math.floor(linear / (dims[0] * dims[1]));
      const rem = linear - z * dims[0] * dims[1];
      const y = Math.floor(rem / dims[0]);
      const mag = gradientAt(rem - y * dims[0], y, z)[3];
      if (mag > 0) magnitudes.push(mag);
    }
    magnitudes.sort((a, b) => a - b);
    const gradientReference = magnitudes.length
      ? Math.max(1e-6, magnitudes[clamp(Math.floor(magnitudes.length * 0.985), 0, magnitudes.length - 1)])
      : 1;

    // --- pack: scalar RGBA8 = (hi, lo, 0, support) ; gradient RGBA8 = (n.xyz, |g|)
    const scalarTexels = new Uint8Array(m * 4);
    const gradientTexels = new Uint8Array(m * 4);
    for (let z = 0; z < dims[2]; z++) {
      for (let y = 0; y < dims[1]; y++) {
        for (let x = 0; x < dims[0]; x++) {
          const d = index(x, y, z), o = d * 4;
          const scaled = clamp(scalar[d], 0, 1) * 255;
          const high = Math.floor(scaled);
          scalarTexels[o] = high;
          scalarTexels[o + 1] = Math.round((scaled - high) * 255);
          scalarTexels[o + 2] = 0;
          scalarTexels[o + 3] = inside[d] ? 255 : 0;

          /*
           * Unit directions, normalised per voxel.
           *
           * Storing the unnormalised gradient and normalising once after
           * reconstruction is the theoretically better operation -- it keeps
           * magnitude weighting through the interpolation -- and it measured
           * marginally better on a synthetic fixture (7.65 vs 7.75 deg p90).
           * On real data it is much worse, because the encoding range then has to
           * span the whole gradient distribution: the median voxel length is
           * 0.0068 of the global maximum, so a typical voxel gets about two of
           * 255 levels per component. The quantisation cost swamps the 0.1 deg of
           * theoretical gain. Normalising first spends the full range on
           * direction, which is the only thing the shading uses.
           */
          let [gx, gy, gz, mag] = gradientAt(x, y, z);
          if (mag > 1e-12) { gx = -gx / mag; gy = -gy / mag; gz = -gz / mag; }
          else { gx = 0; gy = 0; gz = 1; mag = 0; }
          gradientTexels[o] = Math.round(clamp(gx * 0.5 + 0.5, 0, 1) * 255);
          gradientTexels[o + 1] = Math.round(clamp(gy * 0.5 + 0.5, 0, 1) * 255);
          gradientTexels[o + 2] = Math.round(clamp(gz * 0.5 + 0.5, 0, 1) * 255);
          gradientTexels[o + 3] = Math.round(clamp(mag / gradientReference, 0, 1) * 255);
        }
      }
    }

    /*
     * A T1 histogram is trimodal, so equal steps in raw scalar are not equal steps
     * in "how much tissue is enclosed": the level control stalls on the plateaus
     * between tissue classes and lurches at the ramps. This table maps a uniform
     * 0..1 control position onto quantiles of the supported scalar.
     */
    const levelSample = [];
    for (let linear = 0; linear < m; linear += 7) if (inside[linear]) levelSample.push(scalar[linear]);
    levelSample.sort((a, b) => a - b);
    const levelQuantiles = new Float32Array(257);
    for (let i = 0; i <= 256; i++) {
      levelQuantiles[i] = levelSample.length
        ? levelSample[clamp(Math.round((i / 256) * (levelSample.length - 1)), 0, levelSample.length - 1)]
        : i / 256;
    }

    return {
      schema: 'nm-imaging-structural-volume-3d',
      version: 1,
      key: String(desc.key || 'structural'),
      dims,
      origin,
      sourceDims: srcDims,
      spacingMm: spacing,
      scalarTexels,
      gradientTexels,
      gradientReference,
      levelQuantiles,
      worldToTexture: textureMatrix(worldToVoxel0, origin, [1, 1, 1], dims),
      valueRange: [lo, hi],
      bytes: scalarTexels.byteLength + gradientTexels.byteLength,
      prepareMs: nowMs() - startedAt
    };
  }

  // ------------------------------------------------------ native feature grid

  /*
   * RG32F, sampled with NEAREST/texelFetch only. This is the authoritative
   * decision and value field; nothing in the renderer may filter it.
   */
  function prepareNativeFeature(descriptor) {
    const startedAt = nowMs();
    const desc = descriptor && typeof descriptor === 'object' ? descriptor : {};
    const dims = dims3(desc.dims);
    const n = dims[0] * dims[1] * dims[2];
    const data = desc.data, support = desc.support;
    if (!data || data.length !== n) throw new Error('Native feature data do not match their dimensions.');
    const texels = new Float32Array(n * 2);
    for (let i = 0; i < n; i++) {
      const supported = (!support || support[i] !== 0) && Number.isFinite(Number(data[i]));
      texels[i * 2] = supported ? Number(data[i]) : 0;
      texels[i * 2 + 1] = supported ? 1 : 0;
    }
    return {
      schema: 'nm-imaging-native-feature-volume-3d',
      version: 1,
      key: String(desc.key || 'feature'),
      dims,
      spacingMm: spacing3(desc.spacingMm),
      texels,
      worldToVoxelIndex: voxelIndexMatrix(worldToVoxel0Rows(desc.worldToVoxel)),
      bytes: texels.byteLength,
      prepareMs: nowMs() - startedAt
    };
  }

  // -------------------------------- threshold-free local support enhancement

  /*
   * Deterministic local support transform used only to modulate the alpha of
   * the surface projection.  Positive and negative fields are evaluated
   * independently and no display threshold participates.
   *
   * Let m_s(v)=max(s*x(v),0), s in {-1,+1}, and let w(v,u) be a normalized
   * physical Gaussian neighbourhood.  For extent exponent E=1, the TFCE-like
   * height integral has the closed form
   *
   *   integral_0^m(v) [sum_u w(v,u) 1(m(u)>=h)] h^H dh
   *     = sum_u w(v,u) min(m(v),m(u))^(H+1) / (H+1).
   *
   * We report the monotone amplitude-equivalent root of this integral.  This
   * avoids threshold stepping, connected-component labelling and shell graphs.
   * The local Gaussian is sampled on native voxel centres.  The exact stencil
   * is used while it remains small; otherwise a deterministic sparse physical
   * stencil bounds computational cost independently of voxel resolution.
   */
  function localSupportStencil(spacingMm, fwhmMm, maximumSamples) {
    const spacing = spacing3(spacingMm);
    const fwhm = Math.max(1e-6, finite(fwhmMm, 8));
    const sigma = fwhm / Math.sqrt(8 * Math.log(2));
    const truncationMm = KERNEL_TRUNCATION_SIGMA * sigma;
    const limit = Math.max(27, Math.floor(finite(maximumSamples, 343)));
    const radii = spacing.map(s => Math.ceil(truncationMm / s));
    const exact = [];
    for (let dz = -radii[2]; dz <= radii[2]; dz++) {
      for (let dy = -radii[1]; dy <= radii[1]; dy++) {
        for (let dx = -radii[0]; dx <= radii[0]; dx++) {
          const px = dx * spacing[0], py = dy * spacing[1], pz = dz * spacing[2];
          const distance2 = px * px + py * py + pz * pz;
          if (distance2 > truncationMm * truncationMm + 1e-9) continue;
          exact.push({ dx, dy, dz, weight: Math.exp(-0.5 * distance2 / (sigma * sigma)) });
        }
      }
    }
    let entries = exact, mode = 'exact_native_voxel_gaussian';
    if (exact.length > limit) {
      const selected = new Map();
      const add = (dx, dy, dz) => {
        const key = `${dx},${dy},${dz}`;
        if (selected.has(key) || selected.size >= limit) return;
        const px = dx * spacing[0], py = dy * spacing[1], pz = dz * spacing[2];
        const distance2 = px * px + py * py + pz * pz;
        if (distance2 > truncationMm * truncationMm + 1e-9) return;
        selected.set(key, { dx, dy, dz, weight: Math.exp(-0.5 * distance2 / (sigma * sigma)) });
      };
      /* Preserve the complete immediate 3x3x3 native neighbourhood. */
      for (let dz = -1; dz <= 1; dz++) for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) add(dx, dy, dz);
      /* Add symmetric physical-range probes at two sigma on each axis. */
      for (let axis = 0; axis < 3; axis++) {
        const offset = Math.max(1, Math.min(radii[axis], Math.round(2 * sigma / spacing[axis])));
        const positive = [0, 0, 0], negative = [0, 0, 0]; positive[axis] = offset; negative[axis] = -offset;
        add(positive[0], positive[1], positive[2]); add(negative[0], negative[1], negative[2]);
      }
      /* Fill any larger requested budget with complete inversion pairs in descending Gaussian weight. */
      const remaining = exact.filter(item => !selected.has(`${item.dx},${item.dy},${item.dz}`)).sort((a, b) => b.weight - a.weight || a.dz - b.dz || a.dy - b.dy || a.dx - b.dx);
      for (const item of remaining) {
        if (selected.size >= limit) break;
        const inverseKey = `${-item.dx},${-item.dy},${-item.dz}`;
        if (selected.has(`${item.dx},${item.dy},${item.dz}`)) continue;
        if (selected.size + (selected.has(inverseKey) ? 1 : 2) > limit) continue;
        add(item.dx, item.dy, item.dz); add(-item.dx, -item.dy, -item.dz);
      }
      entries = Array.from(selected.values());
      mode = 'sparse_core_plus_physical_axis_gaussian_stencil';
    }
    let total = entries.reduce((sum, item) => sum + item.weight, 0);
    if (!(total > 0)) throw new Error('Threshold-free local support stencil has zero weight.');
    entries.forEach(item => { item.weight /= total; });
    return { entries, sigmaMm: sigma, fwhmMm: fwhm, truncationMm, mode, exactSampleCount: exact.length };
  }

  function robustPositivePercentile(values, percentile) {
    let count = 0;
    for (let i = 0; i < values.length; i++) if (Number.isFinite(values[i]) && values[i] > 0) count++;
    if (!count) return 1;
    const sample = new Float32Array(count); let cursor = 0;
    for (let i = 0; i < values.length; i++) if (Number.isFinite(values[i]) && values[i] > 0) sample[cursor++] = values[i];
    sample.sort();
    const q = clamp(finite(percentile, 0.995), 0.5, 1), index = Math.min(sample.length - 1, Math.max(0, Math.floor(q * (sample.length - 1))));
    return Math.max(1e-20, Number(sample[index]));
  }

  function prepareLocalSupportEnhancement(descriptor) {
    const startedAt = nowMs();
    const desc = descriptor && typeof descriptor === 'object' ? descriptor : {};
    const dims = dims3(desc.dims), spacing = spacing3(desc.spacingMm), n = dims[0] * dims[1] * dims[2];
    const data = desc.data, support = desc.support;
    if (!data || data.length !== n) throw new Error('Threshold-free local support data do not match their dimensions.');
    if (support && support.length !== n) throw new Error('Threshold-free local support mask does not match its dimensions.');
    const heightExponent = clamp(finite(desc.heightExponent, 2), 0, 6), power = heightExponent + 1;
    const normalizationPercentile = clamp(finite(desc.normalizationPercentile, 0.995), 0.5, 1);
    const stencil = localSupportStencil(spacing, desc.localSupportFwhmMm, desc.maximumStencilSamples);
    const entries = stencil.entries, sx = dims[0], sy = dims[1], sz = dims[2], plane = sx * sy;
    const magnitude = new Float32Array(n), polarity = new Int8Array(n), accumulatedPower = new Float64Array(n);
    let positiveVoxels = 0, negativeVoxels = 0;
    for (let i = 0; i < n; i++) {
      if (support && support[i] === 0) continue;
      const value = Number(data[i]);
      if (!Number.isFinite(value) || value === 0) continue;
      magnitude[i] = Math.abs(value);
      polarity[i] = value > 0 ? 1 : -1;
      if (value > 0) positiveVoxels++; else negativeVoxels++;
    }
    /*
     * Offset-major traversal is mathematically identical to the direct
     * voxel-major definition above but removes per-neighbour closures and
     * repeated coordinate reconstruction.  It is material for full native
     * grids and remains deterministic because stencil and loop order are fixed.
     */
    for (let q = 0; q < entries.length; q++) {
      const item = entries[q], dx = item.dx, dy = item.dy, dz = item.dz, weight = item.weight;
      const x0 = Math.max(0, -dx), x1 = Math.min(sx, sx - dx);
      const y0 = Math.max(0, -dy), y1 = Math.min(sy, sy - dy);
      const z0 = Math.max(0, -dz), z1 = Math.min(sz, sz - dz);
      const offset = dx + sx * dy + plane * dz;
      for (let z = z0; z < z1; z++) {
        for (let y = y0; y < y1; y++) {
          let index = x0 + sx * (y + sy * z), neighbourIndex = index + offset;
          for (let x = x0; x < x1; x++, index++, neighbourIndex++) {
            const sign = polarity[index];
            if (sign === 0 || polarity[neighbourIndex] !== sign) continue;
            const sharedHeight = Math.min(magnitude[index], magnitude[neighbourIndex]);
            if (!(sharedHeight > 0)) continue;
            let term;
            if (power === 3) term = sharedHeight * sharedHeight * sharedHeight;
            else if (power === 2) term = sharedHeight * sharedHeight;
            else term = Math.pow(sharedHeight, power);
            accumulatedPower[index] += weight * term;
          }
        }
      }
    }
    const enhancement = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const sum = accumulatedPower[i];
      if (sum > 0 && Number.isFinite(sum)) enhancement[i] = power === 3 ? Math.cbrt(sum) : Math.pow(sum, 1 / power);
    }
    const normalizationReference = robustPositivePercentile(enhancement, normalizationPercentile), alpha = new Float32Array(n);
    let nonzeroAlphaVoxels = 0;
    for (let i = 0; i < n; i++) {
      const value = enhancement[i];
      if (!(value > 0)) continue;
      alpha[i] = clamp(value / normalizationReference, 0, 1);
      if (alpha[i] > 0) nonzeroAlphaVoxels++;
    }
    return {
      schema: 'nm-threshold-free-local-support-enhancement', version: 1,
      key: String(desc.key || 'local-support-enhancement'), dims, spacingMm: spacing,
      alpha, valueRange: [0, 1], localSupportFwhmMm: stencil.fwhmMm,
      gaussianSigmaMm: stencil.sigmaMm, gaussianTruncationMm: stencil.truncationMm,
      heightExponent, extentExponent: 1, normalizationPercentile, normalizationReference,
      polarityHandling: 'positive_negative_independent_shared_normalization',
      stencilMode: stencil.mode, stencilSamples: entries.length, exactStencilSamples: stencil.exactSampleCount,
      positiveVoxels, negativeVoxels, nonzeroAlphaVoxels,
      algorithm: 'closed_form_local_height_integral_E1_native_voxel_gaussian',
      traversal: 'deterministic_offset_major',
      bytes: alpha.byteLength, prepareMs: nowMs() - startedAt
    };
  }

  // ---------------------------------------------------------- coverage fields

  function defaultSmoothingMm(spacingMm) {
    const s = spacing3(spacingMm);
    return DEFAULT_SIGMA_FACTOR * (s[0] + s[1] + s[2]) / 3;
  }

  const COVERAGE_BYTES_PER_VOXEL = 4;              // RGBA8: positive envelope, negative envelope, positive value, negative value

  /*
   * Chooses an integer per-axis refinement of the native grid from a single
   * world-space target spacing, so the coverage grid stays near-isotropic in
   * millimetres even when the native grid is anisotropic. Under budget pressure
   * the target spacing is relaxed uniformly rather than one axis at a time,
   * which avoids the elongated voxels a per-axis backoff produces.
   *
   * Integer refinement keeps the world -> texture mapping exact.
   */
  function chooseRefinement(nativeSpacing, boxDims, sigmaMm, budgetBytes, maxTextureSize) {
    const finest = Math.min.apply(null, nativeSpacing);
    let target = Math.max(0.3, Math.min(sigmaMm * 0.5, finest * 0.5));
    let refine = [1, 1, 1];
    for (let attempt = 0; attempt < 64; attempt++) {
      refine = nativeSpacing.map((s, i) => clamp(
        Math.round(s / target), 1, Math.max(1, Math.floor(maxTextureSize / boxDims[i]))
      ));
      const voxels = refine.reduce((a, r, i) => a * r * boxDims[i], 1);
      if (voxels * COVERAGE_BYTES_PER_VOXEL <= budgetBytes) break;
      if (refine.every(r => r === 1)) break;
      target *= 1.18;
    }
    return refine;
  }

  /*
   * Dual positive/negative support envelopes.
   *
   * Production reconstruction treats every 6-connected native support component
   * independently. The replicated native voxel union is converted to an exact
   * Euclidean signed-distance field in world millimetres, smoothed by the selected
   * physical width and thresholded at a component-specific level that preserves
   * the component's native physical volume. Positive and negative channels remain
   * independent. Sigma zero is the exact native voxel boundary. The historic
   * uniformly blurred occupancy field remains available only as gaussian_audit.
   */
  function prepareCoverage(descriptor) {
    const startedAt = nowMs();
    const desc = descriptor && typeof descriptor === 'object' ? descriptor : {};
    const dims = dims3(desc.dims);
    const spacing = spacing3(desc.spacingMm);
    const spec = thresholdSpec(desc.displayContract);
    const worldToVoxel0 = worldToVoxel0Rows(desc.worldToVoxel);
    const maxTextureSize = Math.max(16, Math.floor(finite(desc.maxTextureSize, 2048)));
    const budget = Math.max(4 * 1024 * 1024, finite(desc.memoryBudgetBytes, DEFAULT_MEMORY_BUDGET_BYTES));
    const requestedMode = String(desc.coverageReconstruction || desc.supportEnvelopeMode || '').toLowerCase();
    const coverageReconstruction = requestedMode === 'gaussian_audit'
      ? 'gaussian_audit'
      : 'component_signed_distance_volume_preserving';

    const requested = desc.boundarySmoothingMm;
    const sigma = (requested === null || requested === undefined || requested === '')
      ? defaultSmoothingMm(spacing)
      : Math.max(0, finite(requested, NaN));
    if (!Number.isFinite(sigma)) throw new Error('Boundary smoothing must be a finite non-negative value in millimetres.');

    const { klass, positiveCount, negativeCount } = nativeClassField(desc.data, desc.support, dims, spec);
    if (!positiveCount && !negativeCount) return null;
    const nativeCount = dims[0] * dims[1] * dims[2];
    const positiveMask = new Uint8Array(nativeCount), negativeMask = new Uint8Array(nativeCount);
    for (let i = 0; i < nativeCount; i++) {
      if (klass[i] > 0) positiveMask[i] = 1;
      else if (klass[i] < 0) negativeMask[i] = 1;
    }
    const positiveInfo = componentRecords(positiveMask, dims), negativeInfo = componentRecords(negativeMask, dims);

    // Native bounding box of the authoritative decision field. Production signed-
    // distance reconstruction receives a virtual zero-valued shell outside the
    // native feature grid; the audit Gaussian path retains the historic clamped
    // crop so it remains directly comparable to prior builds.
    const maxNativeSpacing = Math.max.apply(null, spacing);
    const radius = spacing.map(s => sigma > 0
      ? Math.ceil((KERNEL_TRUNCATION_SIGMA * sigma + maxNativeSpacing) / s) + 1
      : 1);
    let lo = [dims[0], dims[1], dims[2]], hi = [-1, -1, -1];
    for (let z = 0; z < dims[2]; z++) {
      for (let y = 0; y < dims[1]; y++) {
        const rowBase = dims[0] * (y + dims[1] * z);
        for (let x = 0; x < dims[0]; x++) {
          if (!klass[rowBase + x]) continue;
          if (x < lo[0]) lo[0] = x; if (x > hi[0]) hi[0] = x;
          if (y < lo[1]) lo[1] = y; if (y > hi[1]) hi[1] = y;
          if (z < lo[2]) lo[2] = z; if (z > hi[2]) hi[2] = z;
        }
      }
    }
    const virtualPadding = coverageReconstruction !== 'gaussian_audit' && sigma > 0;
    const boxLo = [0, 1, 2].map(i => virtualPadding ? lo[i] - radius[i] : Math.max(0, lo[i] - radius[i]));
    const boxHi = [0, 1, 2].map(i => virtualPadding ? hi[i] + radius[i] : Math.min(dims[i] - 1, hi[i] + radius[i]));
    const boxDims = [0, 1, 2].map(i => boxHi[i] - boxLo[i] + 1);

    const refinementSigma = coverageReconstruction === 'component_signed_distance_volume_preserving'
      ? Math.max(sigma, Math.min.apply(null, spacing))
      : sigma;
    const refine = sigma > 0
      ? chooseRefinement(spacing, boxDims, refinementSigma, budget, maxTextureSize)
      : [1, 1, 1];
    const cDims = [0, 1, 2].map(i => boxDims[i] * refine[i]);
    if (cDims.some((d, i) => d > maxTextureSize)) {
      throw new Error(`Coverage grid ${cDims.join('x')} exceeds MAX_3D_TEXTURE_SIZE ${maxTextureSize}.`);
    }
    const cSpacing = [0, 1, 2].map(i => spacing[i] / refine[i]);
    const cCount = cDims[0] * cDims[1] * cDims[2];

    // Replicated native decision and separate polarity-restricted value numerators.
    // The support envelope is replaced below in production mode; these seeds remain
    // the exact audit geometry and the fixed-kernel value reconstruction input.
    const positiveSeed = new Float32Array(cCount), negativeSeed = new Float32Array(cCount);
    const positiveWeighted = new Float32Array(cCount), positiveOccupancy = new Float32Array(cCount);
    const negativeWeighted = new Float32Array(cCount), negativeOccupancy = new Float32Array(cCount);
    for (let z = 0; z < cDims[2]; z++) {
      const nz = boxLo[2] + Math.floor(z / refine[2]);
      if (nz < 0 || nz >= dims[2]) continue;
      for (let y = 0; y < cDims[1]; y++) {
        const ny = boxLo[1] + Math.floor(y / refine[1]);
        if (ny < 0 || ny >= dims[1]) continue;
        const srcRow = dims[0] * (ny + dims[1] * nz);
        const dstRow = cDims[0] * (y + cDims[1] * z);
        for (let x = 0; x < cDims[0]; x++) {
          const nx = boxLo[0] + Math.floor(x / refine[0]);
          if (nx < 0 || nx >= dims[0]) continue;
          const sourceIndex = srcRow + nx, targetIndex = dstRow + x, c = klass[sourceIndex];
          if (c > 0) {
            positiveSeed[targetIndex] = 1;
            positiveWeighted[targetIndex] = Number(desc.data[sourceIndex]) || 0;
            positiveOccupancy[targetIndex] = 1;
          } else if (c < 0) {
            negativeSeed[targetIndex] = 1;
            negativeWeighted[targetIndex] = Number(desc.data[sourceIndex]) || 0;
            negativeOccupancy[targetIndex] = 1;
          }
        }
      }
    }

    let positive = positiveSeed, negative = negativeSeed;
    let positiveEnvelope = null, negativeEnvelope = null;
    let activeReconstruction = sigma > 0 ? coverageReconstruction : 'native_voxel_boundary';
    if (sigma > 0 && coverageReconstruction === 'gaussian_audit') {
      smoothSeparable(positive, cDims, cSpacing, sigma);
      smoothSeparable(negative, cDims, cSpacing, sigma);
    } else if (sigma > 0) {
      positiveEnvelope = signedDistanceEnvelope(positiveInfo, dims, boxLo, refine, cDims, cSpacing, sigma);
      negativeEnvelope = signedDistanceEnvelope(negativeInfo, dims, boxLo, refine, cDims, cSpacing, sigma);
      positive = positiveEnvelope.field;
      negative = negativeEnvelope.field;
    }

    /*
     * Feature amplitude and feature support are reconstructed independently.
     * Boundary smoothing controls only the signed-distance envelope. Production
     * colour uses a fixed physical kernel tied to the native feature spacing, so
     * changing boundary smoothness cannot silently alter feature amplitudes. The
     * audit branch retains the historic same-sigma value blur for direct parity.
     */
    const meanNativeSpacing = (spacing[0] + spacing[1] + spacing[2]) / 3;
    const valueSmoothingMm = sigma > 0
      ? (coverageReconstruction === 'gaussian_audit' ? sigma : 0.5 * meanNativeSpacing)
      : 0;
    smoothSeparable(positiveWeighted, cDims, cSpacing, valueSmoothingMm);
    smoothSeparable(positiveOccupancy, cDims, cSpacing, valueSmoothingMm);
    smoothSeparable(negativeWeighted, cDims, cSpacing, valueSmoothingMm);
    smoothSeparable(negativeOccupancy, cDims, cSpacing, valueSmoothingMm);

    const range = arr(desc.valueRange).slice(0, 2).map(Number);
    const vLo = Number.isFinite(range[0]) ? range[0] : -1;
    const vHi = (Number.isFinite(range[1]) && range[1] > vLo) ? range[1] : (vLo + 1);
    const coverageTexels = new Uint8Array(cCount * 4);
    for (let i = 0; i < cCount; i++) {
      const o = i * 4;
      coverageTexels[o] = Math.round(clamp(positive[i], 0, 1) * 255);
      coverageTexels[o + 1] = Math.round(clamp(negative[i], 0, 1) * 255);
      const positiveMean = positiveOccupancy[i] > 1e-6 ? positiveWeighted[i] / positiveOccupancy[i] : 0;
      const negativeMean = negativeOccupancy[i] > 1e-6 ? negativeWeighted[i] / negativeOccupancy[i] : 0;
      /*
       * Keep the reconstructed values polarity-specific. The signed-distance
       * envelopes can overlap after smoothing; selecting one shared scalar by the
       * larger envelope allows a negative value to colour a positive surface (and
       * vice versa), producing isolated wrong-colour patches. One 8-bit channel
       * per polarity is sufficient for the 256-entry presentation LUT and remains
       * linearly filterable. Native values and reports retain full precision.
       */
      coverageTexels[o + 2] = Math.round(clamp((positiveMean - vLo) / (vHi - vLo), 0, 1) * 255);
      coverageTexels[o + 3] = Math.round(clamp((negativeMean - vLo) / (vHi - vLo), 0, 1) * 255);
    }

    // Native-centre representation remains diagnostic. Cluster preservation in the
    // production path is guaranteed by the per-component volume-preserving level,
    // not inferred from whether every original centre remains inside the rounded
    // envelope.
    let representedPositive = 0, representedNegative = 0;
    const positivePeak = new Map(), negativePeak = new Map();
    for (let z = 0; z < dims[2]; z++) {
      for (let y = 0; y < dims[1]; y++) {
        const row = dims[0] * (y + dims[1] * z);
        for (let x = 0; x < dims[0]; x++) {
          const k = klass[row + x];
          if (!k) continue;
          const cx = clamp(Math.floor((x - boxLo[0]) * refine[0] + 0.5 * refine[0]), 0, cDims[0] - 1);
          const cy = clamp(Math.floor((y - boxLo[1]) * refine[1] + 0.5 * refine[1]), 0, cDims[1] - 1);
          const cz = clamp(Math.floor((z - boxLo[2]) * refine[2] + 0.5 * refine[2]), 0, cDims[2] - 1);
          const i = cx + cDims[0] * (cy + cDims[1] * cz), value = k > 0 ? positive[i] : negative[i];
          if (value >= 0.5) { if (k > 0) representedPositive++; else representedNegative++; }
          const info = k > 0 ? positiveInfo : negativeInfo, peaks = k > 0 ? positivePeak : negativePeak;
          const id = info.labels[row + x];
          if (id >= 0 && (!peaks.has(id) || value > peaks.get(id))) peaks.set(id, value);
        }
      }
    }
    const representedVoxelFraction = (positiveCount + negativeCount)
      ? (representedPositive + representedNegative) / (positiveCount + negativeCount) : 1;
    const clustersTotal = positiveInfo.records.length + negativeInfo.records.length;
    let clustersKeptAtNativeCentres = 0;
    positivePeak.forEach(peak => { if (peak >= 0.5) clustersKeptAtNativeCentres++; });
    negativePeak.forEach(peak => { if (peak >= 0.5) clustersKeptAtNativeCentres++; });
    const componentsKept = activeReconstruction === 'component_signed_distance_volume_preserving'
      ? finite(positiveEnvelope && positiveEnvelope.componentsKept, 0) + finite(negativeEnvelope && negativeEnvelope.componentsKept, 0)
      : clustersKeptAtNativeCentres;
    const representedFraction = clustersTotal ? componentsKept / clustersTotal : representedVoxelFraction;
    const nativeRecoveryMaxMm = activeReconstruction === 'component_signed_distance_volume_preserving'
      ? Math.max(2 * maxNativeSpacing, 1.5 * sigma)
      : Math.max(0.5, sigma);

    return {
      schema: 'nm-imaging-coverage-field-3d',
      version: 3,
      key: String(desc.key || 'coverage'),
      dims: cDims,
      spacingMm: cSpacing,
      nativeDims: dims,
      nativeSpacingMm: spacing,
      origin: boxLo,
      refine,
      coverageTexels,
      boundarySmoothingMm: sigma,
      smallScaleSigmaMm: null,
      valueSmoothingMm,
      coverageReconstruction: activeReconstruction,
      coverageBoundaryLevel: 0.5,
      valueRange: [vLo, vHi],
      coverageGridSpacingMm: Math.min.apply(null, cSpacing),
      nativeRecoveryMaxMm,
      positiveCount,
      negativeCount,
      representedPositive,
      representedNegative,
      representedFraction,
      representedVoxelFraction,
      clustersTotal,
      clustersKept: componentsKept,
      clustersKeptAtNativeCentres,
      worldToTexture: textureMatrix(worldToVoxel0, boxLo, refine, cDims),
      bytes: coverageTexels.byteLength,
      prepareMs: nowMs() - startedAt,
      envelopePrepareMs: finite(positiveEnvelope && positiveEnvelope.prepareMs, 0) + finite(negativeEnvelope && negativeEnvelope.prepareMs, 0),
      provenance: {
        contractSchema: 'nm-imaging-volume-rendering-contract',
        contractVersion: 1,
        activationStatus: 'active',
        boundarySmoothingMm: sigma,
        coverageBoundaryLevel: 0.5,
        coverageGridSpacingMm: Math.min.apply(null, cSpacing),
        positiveNegativeCombination: 'independent_channels_no_subtraction',
        nativeValueSampling: 'nearest_texel_fetch',
        kernelTruncationSigma: KERNEL_TRUNCATION_SIGMA,
        supportEnvelopeReconstruction: activeReconstruction,
        distanceMetric: activeReconstruction === 'component_signed_distance_volume_preserving' ? 'exact_euclidean_world_mm' : 'not_applicable',
        componentConnectivity: activeReconstruction === 'component_signed_distance_volume_preserving' ? 6 : null,
        isoLevelPolicy: activeReconstruction === 'component_signed_distance_volume_preserving' ? 'per_component_native_volume_preserving_quantile' : 'fixed_0.5',
        componentCombination: activeReconstruction === 'component_signed_distance_volume_preserving' ? 'maximum_union_within_polarity' : 'single_global_field',
        indicatorPlacement: 'nearest_native_voxel_replication',
        smoothingSchedule: activeReconstruction === 'component_signed_distance_volume_preserving'
          ? 'signed_distance_gaussian_user_mm'
          : (activeReconstruction === 'gaussian_audit' ? 'uniform_user_selected_gaussian_audit' : 'none_native_voxel_audit'),
        valueReconstruction: activeReconstruction === 'component_signed_distance_volume_preserving'
          ? 'separate_positive_negative_fixed_physical_weighted_mean_rgba8'
          : 'separate_positive_negative_same_sigma_weighted_mean_audit_rgba8',
        valueSmoothingMm,
        nativeRecoveryMaxMm,
        representedFraction,
        representedVoxelFraction,
        clustersTotal,
        clustersKept: componentsKept,
        normalReconstruction: 'shader_central_difference_of_support_envelope'
      }
    };
  }

  const api = {
    KERNEL_TRUNCATION_SIGMA,
    DEFAULT_SIGMA_FACTOR,
    SMALL_SCALE_SIGMA_FACTOR,
    prepareStructural,
    prepareNativeFeature,
    prepareLocalSupportEnhancement,
    prepareCoverage,
    defaultSmoothingMm,
    projectionClass,
    thresholdSpec,
    _test: {
      gaussianKernel, convolveAxis, smoothSeparable, nativeClassField,
      localSupportStencil, robustPositivePercentile,
      chooseRefinement, textureMatrix, worldToVoxel0Rows, rowsToColumnMajor, matrixRows4,
      insideDistance, signedDistanceField, edt1d, componentScale, componentLabels,
      componentRecords, volumePreservingLevel, signedDistanceEnvelope
    }
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.NMImagingVolumePrep = api;
})(typeof self !== 'undefined' ? self : (typeof globalThis !== 'undefined' ? globalThis : this));
