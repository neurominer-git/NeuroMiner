/*
 * NMVolumeRaycastGL2 — WebGL2 volumetric renderer core.
 *
 * Replaces both rejected paths:
 *   - the native-DDA feature renderer (camera-dependent voxel facets)
 *   - the gradient-weighted structural accumulator (fog / shells / stipple)
 *
 * Method. One front-to-back ray march per pixel over a shared parameter t, in
 * which anatomy and features are *co-integrated*. Surfaces are not accumulated;
 * they are located. Each surface is a level crossing of a continuous field,
 * refined by bisection, shaded once, and composited at its own depth. That makes
 * the visible geometry camera-independent and free of both the shell stacking and
 * the stippling that defeated fixed-step accumulation.
 *
 *   anatomy  : level crossing of reconstructed structural scalar × support at uAnatomySurfaceLevel
 *   features : level crossing of the presentation coverage field at 0.5,
 *              clipped by the rendered structural-volume interior, independently
 *              per polarity, with values read by texelFetch from the untouched
 *              native grid
 *
 * Requires WebGL2 (3D textures, texelFetch, native gl_FragDepth).
 */
(function (root) {
  'use strict';

  const {clamp,nowMs}=globalThis.NMResultsViewerPrimitives;
  const MAX_CLIP_PLANES = 3;
  function finite(v, d) { const n = Number(v); return Number.isFinite(n) ? n : d; }

  function glErrorName(gl, code) {
    const table = new Map([
      [gl.NO_ERROR, 'NO_ERROR'],
      [gl.INVALID_ENUM, 'INVALID_ENUM'],
      [gl.INVALID_VALUE, 'INVALID_VALUE'],
      [gl.INVALID_OPERATION, 'INVALID_OPERATION'],
      [gl.INVALID_FRAMEBUFFER_OPERATION, 'INVALID_FRAMEBUFFER_OPERATION'],
      [gl.OUT_OF_MEMORY, 'OUT_OF_MEMORY'],
      [gl.CONTEXT_LOST_WEBGL, 'CONTEXT_LOST_WEBGL']
    ]);
    return table.get(code) || ('0x' + Number(code).toString(16));
  }

  function drainGlErrors(gl, limit) {
    const max = Math.max(1, Math.floor(finite(limit, 32)));
    const errors = [];
    for (let i = 0; i < max; i++) {
      const code = gl.getError();
      if (code === gl.NO_ERROR) break;
      errors.push({ code, name: glErrorName(gl, code) });
    }
    return errors;
  }

  function samplerTypeName(gl, type) {
    const entries = [
      ['SAMPLER_2D', gl.SAMPLER_2D, 'TEXTURE_2D'],
      ['SAMPLER_3D', gl.SAMPLER_3D, 'TEXTURE_3D'],
      ['SAMPLER_CUBE', gl.SAMPLER_CUBE, 'TEXTURE_CUBE_MAP'],
      ['SAMPLER_2D_SHADOW', gl.SAMPLER_2D_SHADOW, 'TEXTURE_2D'],
      ['SAMPLER_CUBE_SHADOW', gl.SAMPLER_CUBE_SHADOW, 'TEXTURE_CUBE_MAP'],
      ['SAMPLER_2D_ARRAY', gl.SAMPLER_2D_ARRAY, 'TEXTURE_2D_ARRAY'],
      ['SAMPLER_2D_ARRAY_SHADOW', gl.SAMPLER_2D_ARRAY_SHADOW, 'TEXTURE_2D_ARRAY'],
      ['INT_SAMPLER_2D', gl.INT_SAMPLER_2D, 'TEXTURE_2D'],
      ['INT_SAMPLER_3D', gl.INT_SAMPLER_3D, 'TEXTURE_3D'],
      ['INT_SAMPLER_CUBE', gl.INT_SAMPLER_CUBE, 'TEXTURE_CUBE_MAP'],
      ['INT_SAMPLER_2D_ARRAY', gl.INT_SAMPLER_2D_ARRAY, 'TEXTURE_2D_ARRAY'],
      ['UNSIGNED_INT_SAMPLER_2D', gl.UNSIGNED_INT_SAMPLER_2D, 'TEXTURE_2D'],
      ['UNSIGNED_INT_SAMPLER_3D', gl.UNSIGNED_INT_SAMPLER_3D, 'TEXTURE_3D'],
      ['UNSIGNED_INT_SAMPLER_CUBE', gl.UNSIGNED_INT_SAMPLER_CUBE, 'TEXTURE_CUBE_MAP'],
      ['UNSIGNED_INT_SAMPLER_2D_ARRAY', gl.UNSIGNED_INT_SAMPLER_2D_ARRAY, 'TEXTURE_2D_ARRAY']
    ];
    for (const entry of entries) if (Number.isFinite(entry[1]) && type === entry[1]) return { name: entry[0], target: entry[2] };
    return null;
  }

  function activeSamplerAudit(gl, program) {
    const count = Number(gl.getProgramParameter(program, gl.ACTIVE_UNIFORMS) || 0);
    const samplers = [];
    for (let i = 0; i < count; i++) {
      const info = gl.getActiveUniform(program, i);
      if (!info) continue;
      const type = samplerTypeName(gl, info.type);
      if (!type) continue;
      const location = gl.getUniformLocation(program, info.name);
      let unit = null;
      try {
        const value = location === null ? null : gl.getUniform(program, location);
        unit = value === null ? null : (ArrayBuffer.isView(value) ? Number(value[0]) : Number(value));
        if (!Number.isFinite(unit)) unit = null;
      } catch (error) {
        unit = null;
      }
      samplers.push({ name: info.name, type: type.name, target: type.target, unit });
    }
    return {
      activeUniforms: count,
      maxFragmentTextureUnits: (() => { const value = gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS); return value === null ? null : Number(value); })(),
      maxCombinedTextureUnits: (() => { const value = gl.getParameter(gl.MAX_COMBINED_TEXTURE_IMAGE_UNITS); return value === null ? null : Number(value); })(),
      samplers
    };
  }

  function textureUnitAudit(gl, units) {
    const previous = Number(gl.getParameter(gl.ACTIVE_TEXTURE) || gl.TEXTURE0);
    const unique = Array.from(new Set((units || []).filter(Number.isFinite).map(Number))).sort((a, b) => a - b);
    const bindings = [];
    for (const unit of unique) {
      gl.activeTexture(gl.TEXTURE0 + unit);
      bindings.push({
        unit,
        bound2D: !!gl.getParameter(gl.TEXTURE_BINDING_2D),
        bound3D: !!gl.getParameter(gl.TEXTURE_BINDING_3D),
        boundCube: !!gl.getParameter(gl.TEXTURE_BINDING_CUBE_MAP),
        bound2DArray: Number.isFinite(gl.TEXTURE_BINDING_2D_ARRAY) ? !!gl.getParameter(gl.TEXTURE_BINDING_2D_ARRAY) : false
      });
    }
    gl.activeTexture(previous);
    return bindings;
  }

  // ------------------------------------------------------------------ context

  const CONTEXT_ATTRIBUTES = { antialias: true, alpha: true, preserveDrawingBuffer: false, depth: true, stencil: false };

  /*
   * Acquires a WebGL2 context, falling back to WebGL1 so the caller can keep the
   * existing renderer alive on machines without WebGL2. The caller inspects
   * .isWebGL2 and only installs this renderer when it is true.
   */
  function acquireContext(canvas, attributes) {
    const attrs = Object.assign({}, CONTEXT_ATTRIBUTES, attributes || {});
    const gl2 = canvas.getContext('webgl2', attrs);
    if (gl2) return { gl: gl2, isWebGL2: true, kind: 'webgl2', attributes: attrs };
    const gl1 = canvas.getContext('webgl', attrs) || canvas.getContext('experimental-webgl', attrs);
    if (gl1) return { gl: gl1, isWebGL2: false, kind: 'webgl1', attributes: attrs };
    throw new Error('Browser WebGL context is unavailable.');
  }

  function capability(gl) {
    const isWebGL2 = typeof WebGL2RenderingContext !== 'undefined' && gl instanceof WebGL2RenderingContext;
    if (!isWebGL2) return { ok: false, reason: 'webgl2_required', isWebGL2: false };
    if (typeof gl.isContextLost === 'function' && gl.isContextLost()) return { ok: false, reason: 'context_lost', isWebGL2: true };
    const rawMax3D = gl.getParameter(gl.MAX_3D_TEXTURE_SIZE), rawUnits = gl.getParameter(gl.MAX_TEXTURE_IMAGE_UNITS);
    if (rawMax3D === null || rawUnits === null) return { ok: false, reason: 'context_unavailable', isWebGL2: true };
    const max3D = Number(rawMax3D), units = Number(rawUnits);
    const colorBufferFloat = !!gl.getExtension('EXT_color_buffer_float');
    if (max3D < 256) return { ok: false, reason: 'max_3d_texture_size_too_small', max3DTextureSize: max3D, isWebGL2: true };
    if (units < 7) return { ok: false, reason: 'insufficient_texture_units', maxTextureImageUnits: units, isWebGL2: true };
    return {
      ok: true, reason: 'ok', isWebGL2: true,
      max3DTextureSize: max3D, maxTextureImageUnits: units,
      colorBufferFloat,
      auditTextureUnitsAvailable: units >= 9,
      parallelShaderCompile: !!gl.getExtension('KHR_parallel_shader_compile')
    };
  }

  // ----------------------------------------------------------------- textures

  function createTexture3D(gl, options) {
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_3D, texture);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    const filter = options.linear ? gl.LINEAR : gl.NEAREST;
    gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_MAG_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_3D, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE);
    gl.texImage3D(
      gl.TEXTURE_3D, 0, options.internalFormat,
      options.dims[0], options.dims[1], options.dims[2], 0,
      options.format, options.type, options.data
    );
    gl.bindTexture(gl.TEXTURE_3D, null);
    return texture;
  }

  function uploadStructural(gl, prepared) {
    const startedAt = nowMs();
    const scalar = createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RGBA8, format: gl.RGBA,
      type: gl.UNSIGNED_BYTE, data: prepared.scalarTexels, linear: true
    });
    const gradient = createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RGBA8, format: gl.RGBA,
      type: gl.UNSIGNED_BYTE, data: prepared.gradientTexels, linear: true
    });
    const gradientScalarSobel = prepared.gradientTexelsScalarSobel ? createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RGBA8, format: gl.RGBA,
      type: gl.UNSIGNED_BYTE, data: prepared.gradientTexelsScalarSobel, linear: true
    }) : null;
    const gradientFieldSobel = prepared.gradientTexelsFieldSobel ? createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RGBA8, format: gl.RGBA,
      type: gl.UNSIGNED_BYTE, data: prepared.gradientTexelsFieldSobel, linear: true
    }) : null;
    return {
      kind: 'structural', key: prepared.key, scalar, gradient,
      gradientScalarSobel, gradientFieldSobel,
      dims: prepared.dims.slice(), spacingMm: prepared.spacingMm.slice(),
      worldToTexture: prepared.worldToTexture,
      gradientReference: prepared.gradientReference,
      gradientReferenceScalarSobel: finite(prepared.gradientReferenceScalarSobel, NaN),
      gradientReferenceFieldSobel: finite(prepared.gradientReferenceFieldSobel, NaN),
      gradientKernel: String(prepared.gradientKernel || ''),
      gradientPreblurSigmaMm: finite(prepared.gradientPreblurSigmaMm, NaN),
      gradientSourceField: String(prepared.gradientSourceField || ''),
      scalarSobelKernel: String(prepared.scalarSobelKernel || ''),
      scalarSobelSourceField: String(prepared.scalarSobelSourceField || ''),
      fieldSobelKernel: String(prepared.fieldSobelKernel || ''),
      fieldSobelSourceField: String(prepared.fieldSobelSourceField || ''),
      fieldSupportSigmaMm: finite(prepared.fieldSupportSigmaMm, NaN),
      crossingField: String(prepared.crossingField || ''),
      normalAuditVariantsIncluded: !!(gradientScalarSobel && gradientFieldSobel),
      levelQuantiles: prepared.levelQuantiles || null,
      bytes: prepared.bytes, uploadMs: nowMs() - startedAt, references: 1
    };
  }

  /*
   * Filter mode is part of the contract, not a quality knob.
   *
   * sigma > 0 (default): LINEAR. The 0.5 level set of the interpolated field is
   *   the continuous presentation boundary.
   * sigma = 0 (audit):   NEAREST. The field is binary, so the 0.5 crossing falls
   *   exactly on a native voxel face and the audit mode reproduces the native
   *   voxel boundary exactly rather than approximately. Verified against a
   *   reference DDA traversal at a median depth difference below 0.01 mm.
   */
  function uploadCoverage(gl, prepared) {
    const startedAt = nowMs();
    const smoothed = finite(prepared.boundarySmoothingMm, 0) > 0;
    const texture = createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RGBA8, format: gl.RGBA,
      type: gl.UNSIGNED_BYTE, data: prepared.coverageTexels, linear: smoothed
    });
    return {
      kind: 'coverage', key: prepared.key, texture, filtered: smoothed,
      dims: prepared.dims.slice(), spacingMm: prepared.spacingMm.slice(),
      worldToTexture: prepared.worldToTexture,
      boundarySmoothingMm: prepared.boundarySmoothingMm,
      coverageReconstruction: String(prepared.coverageReconstruction || ''),
      coverageBoundaryLevel: prepared.coverageBoundaryLevel,
      representedFraction: finite(prepared.representedFraction, 1),
      representedVoxelFraction: finite(prepared.representedVoxelFraction, 1),
      nativeRecoveryMaxMm: finite(prepared.nativeRecoveryMaxMm, NaN),
      valueSmoothingMm: finite(prepared.valueSmoothingMm, NaN),
      valueRange: (prepared.valueRange || [-1, 1]).slice(),
      provenance: prepared.provenance,
      bytes: prepared.bytes, uploadMs: nowMs() - startedAt, references: 1
    };
  }

  /* RG32F, NEAREST only. This is the authoritative decision and value field. */
  function uploadNativeFeature(gl, prepared) {
    const startedAt = nowMs();
    const texture = createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.RG32F, format: gl.RG,
      type: gl.FLOAT, data: prepared.texels, linear: false
    });
    return {
      kind: 'native_feature', key: prepared.key, texture,
      dims: prepared.dims.slice(), spacingMm: prepared.spacingMm.slice(),
      worldToVoxelIndex: prepared.worldToVoxelIndex,
      bytes: prepared.bytes, uploadMs: nowMs() - startedAt, references: 1
    };
  }

  function uploadAtlasLabel(gl, prepared) {
    const startedAt = nowMs();
    const texture = createTexture3D(gl, {
      dims: prepared.dims, internalFormat: gl.R32F, format: gl.RED,
      type: gl.FLOAT, data: prepared.texels, linear: false
    });
    return {
      kind: 'atlas_label', key: prepared.key, texture, dims: prepared.dims.slice(),
      worldToVoxelIndex: prepared.worldToVoxelIndex,
      bytes: prepared.bytes, uploadMs: nowMs() - startedAt, references: 1
    };
  }

  /*
   * Optional volumes (coverage, atlas labels) may be absent. Binding null leaves
   * the sampler unit pointing at the incomplete default texture, which makes the
   * whole draw call sample as black on most drivers even though the shader
   * branches around it. A 1x1x1 texture of the matching internal format keeps
   * every referenced sampler complete.
   */
  function ensureFallbackTextures(gl) {
    if (gl._nmVolumeFallbacks) return gl._nmVolumeFallbacks;
    const one = [1, 1, 1];
    const fallbacks = {
      rgba8: createTexture3D(gl, { dims: one, internalFormat: gl.RGBA8, format: gl.RGBA, type: gl.UNSIGNED_BYTE, data: new Uint8Array(4), linear: true }),
      rg8: createTexture3D(gl, { dims: one, internalFormat: gl.RG8, format: gl.RG, type: gl.UNSIGNED_BYTE, data: new Uint8Array(2), linear: true }),
      rg32f: createTexture3D(gl, { dims: one, internalFormat: gl.RG32F, format: gl.RG, type: gl.FLOAT, data: new Float32Array(2), linear: false }),
      r32f: createTexture3D(gl, { dims: one, internalFormat: gl.R32F, format: gl.RED, type: gl.FLOAT, data: new Float32Array(1), linear: false })
    };
    gl._nmVolumeFallbacks = fallbacks;
    return fallbacks;
  }

  function disposeFallbackTextures(gl) {
    const fallbacks = gl._nmVolumeFallbacks;
    if (!fallbacks) return;
    Object.keys(fallbacks).forEach(key => gl.deleteTexture(fallbacks[key]));
    gl._nmVolumeFallbacks = null;
  }

  function disposeResource(gl, resource) {
    if (!resource) return;
    ['scalar', 'gradient', 'gradientScalarSobel', 'gradientFieldSobel', 'texture'].forEach(name => {
      if (resource[name]) gl.deleteTexture(resource[name]);
      resource[name] = null;
    });
  }

  // ------------------------------------------------------------------ shaders

  const VERTEX_SOURCE = `#version 300 es
precision highp float;
in vec3 aPosition;
uniform mat4 uMVP;
out vec3 vWorldPosition;
void main(){
  vWorldPosition = aPosition;
  gl_Position = uMVP * vec4(aPosition, 1.0);
}`;

  const FRAGMENT_SOURCE = `#version 300 es
#ifndef NM_FIELD_MODE
#define NM_FIELD_MODE -1
#endif
#ifndef NM_TRANSFER_MODE
#define NM_TRANSFER_MODE -1
#endif
#ifndef NM_NORMAL_MODE
#define NM_NORMAL_MODE -1
#endif
#ifndef NM_HIT_RULE
#define NM_HIT_RULE -1
#endif
#ifndef NM_MAX_RAY_STEPS
#define NM_MAX_RAY_STEPS 2048
#endif
#ifndef NM_MAX_EMPTY_STEPS
#define NM_MAX_EMPTY_STEPS 512
#endif
precision highp float;
precision highp int;
precision highp sampler3D;

in vec3 vWorldPosition;
out vec4 fragColor;

uniform mat4  uMVP;
uniform int   uProjectionMode;          // 0 orthographic, 1 perspective
uniform vec3  uEyeWorld;
uniform vec3  uRayDirectionWorld;
uniform vec3  uBoundsMin;
uniform vec3  uBoundsMax;
uniform float uStepMm;
uniform float uEmptySkipMm;      // coarse advance through empty space
uniform int   uMaxSteps;
uniform float uPhaseOffset;             // temporal accumulation: frame-varying jitter

uniform int   uClipCount;
uniform vec4  uClipPlane0;
uniform vec4  uClipPlane1;
uniform vec4  uClipPlane2;

uniform sampler3D uStructuralScalar;              // RGBA8 LINEAR (hi, lo, 0, support)
uniform sampler3D uStructuralGradient;            // central-difference packed unit normal
uniform sampler3D uStructuralGradientScalarSobel; // R1B scalar Sobel audit texture
uniform sampler3D uStructuralGradientFieldSobel;  // R1B support-aware Sobel audit texture
uniform mat4      uWorldToStructuralTex;
uniform vec3      uStructuralTexSize;
uniform int       uStructuralFieldReconstruction;    // 0 trilinear scalar*support, 1 cubic B-spline scalar*support
uniform int       uStructuralTransferReconstruction; // 0 trilinear scalar, 1 cubic B-spline scalar
uniform int       uStructuralNormalEstimator;        // 0 central, 1 scalar Sobel, 2 field Sobel, 3 direct central, 4 hybrid, 5 packed tricubic, 6 direct 8-corner
uniform int       uStructuralHitRule;             // 0 exact hit, 1 strongest bracket, 2 one-step carry
uniform int       uStructuralAuditVariantsAvailable;
uniform float     uStructuralNormalStepVoxels;
uniform float     uAnatomySurfaceLevel;
uniform float     uAnatomySurfaceAlpha;
uniform float     uAnatomyInteriorAlpha;
uniform int       uAnatomyMaxSurfaces;
uniform float     uAnatomyBrightness;
uniform float     uAnatomyGamma;

uniform sampler3D uCoverage;            // RGBA8 LINEAR (positive envelope, negative envelope, positive value, negative value)
uniform mat4      uWorldToCoverageTex;
uniform vec3      uCoverageTexelMm;     // coverage voxel size, world mm, per axis
uniform float     uCoverageLevel;       // fixed at 0.5 by contract
uniform float     uCoverageNudgeMm;     // native-support recovery distance
uniform int       uCoverageAvailable;

uniform sampler3D uFeatureNative;       // RG32F NEAREST (value, support)
uniform mat4      uWorldToFeatureIndex;
uniform ivec3     uFeatureDims;
uniform float     uFeatureOpacity;
uniform float     uFeatureColorIntensity;
uniform float     uFeatureSlabMm;
uniform float     uFeatureInteriorAlpha;
uniform int       uFeatureValueShading;  // 0 native nearest, 1 presentation-smoothed
uniform vec2      uCoverageValueRange;

uniform sampler2D uFeatureLut;
uniform sampler2D uStructuralLut;
uniform vec2      uDisplayRange;
uniform int       uThresholdMode;
uniform float     uNegativeThreshold;
uniform float     uPositiveThreshold;
uniform float     uSingleThreshold;

uniform sampler3D uAtlasLabel;          // R32F NEAREST
uniform mat4      uWorldToAtlasIndex;
uniform ivec3     uAtlasDims;
uniform int       uRoiFocusEnabled;
uniform float     uRoiCodeA;
uniform float     uRoiCodeB;
uniform float     uRoiMix;
uniform float     uOutsideRoiOpacity;
uniform int       uRoiMaskOnly;

uniform vec3  uLightDirection;
uniform vec3  uLightColor;
uniform float uAmbient;
uniform float uDiffuse;
uniform float uSpecular;
uniform float uShininess;

const int   BISECTION_STEPS = 5;
const float EPS = 1e-6;

// ------------------------------------------------------------------ sampling

vec3 texCoord(mat4 m, vec3 world){ return (m * vec4(world, 1.0)).xyz; }
bool insideUnit(vec3 c){
  return all(greaterThanEqual(c, vec3(0.0))) && all(lessThanEqual(c, vec3(1.0)));
}

/* 16-bit structural scalar in .rg, cavity field in .b, support mask in .a */
vec2 structuralAt(vec3 world){
  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec2(0.0, 0.0);
  vec4 t = texture(uStructuralScalar, c);
  return vec2(t.r + t.g / 255.0, t.a);
}

/*
 * The visible anatomy field is scalar * support, not scalar alone.
 * prepareStructural dilates scalar outward across the support boundary so that
 * hardware trilinear filtering does not blend tissue against zeros. That fill
 * means the raw scalar is already at tissue values *outside* the brain, so a
 * low surface level is crossed before support turns on and the first-crossing
 * test never fires -- the anatomy disappears entirely below level ~0.3.
 * Multiplying by the filtered support mask restores a single clean crossing at
 * the boundary and leaves the interior (support == 1) untouched.
 */
float structuralField(vec2 sample_){ return sample_.x * sample_.y; }

/*
 * Normal estimators. All variants use the same bisection-refined
 * anatomical hit. The selector therefore changes shading only, never geometry.
 *
 * R1B compatibility/audit modes:
 *   0 stored central difference, trilinear
 *   1 stored scalar Sobel, trilinear
 *   2 stored field Sobel, trilinear
 *   3 direct exact-field central difference
 *   4 support-adaptive stored central/field-Sobel hybrid
 *
 * R1C1 terracing modes:
 *   5 packed_tricubic: the user's 8-tap B-spline reconstruction of RGBA8 normals
 *   6 direct_field_8corner: eight exact-field samples around the refined hit
 */
vec4 cubicWeights(float x){
  float x2 = x * x, x3 = x2 * x;
  return vec4(-x3 + 3.0 * x2 - 3.0 * x + 1.0,
               3.0 * x3 - 6.0 * x2 + 4.0,
              -3.0 * x3 + 3.0 * x2 + 3.0 * x + 1.0,
               x3) / 6.0;
}
vec4 textureTricubic(sampler3D tex, vec3 coord, vec3 size){
  vec3 c = coord * size - 0.5;
  vec3 f = fract(c);
  c -= f;
  vec4 wx = cubicWeights(f.x), wy = cubicWeights(f.y), wz = cubicWeights(f.z);
  vec2 gx = vec2(wx.x + wx.y, wx.z + wx.w);
  vec2 gy = vec2(wy.x + wy.y, wy.z + wy.w);
  vec2 gz = vec2(wz.x + wz.y, wz.z + wz.w);
  vec2 hx = (vec2(wx.y, wx.w) / gx + vec2(-1.0, 1.0) + c.x + 0.5) / size.x;
  vec2 hy = (vec2(wy.y, wy.w) / gy + vec2(-1.0, 1.0) + c.y + 0.5) / size.y;
  vec2 hz = (vec2(wz.y, wz.w) / gz + vec2(-1.0, 1.0) + c.z + 0.5) / size.z;
  vec4 s = vec4(0.0);
  s += gx.x * gy.x * gz.x * texture(tex, vec3(hx.x, hy.x, hz.x));
  s += gx.y * gy.x * gz.x * texture(tex, vec3(hx.y, hy.x, hz.x));
  s += gx.x * gy.y * gz.x * texture(tex, vec3(hx.x, hy.y, hz.x));
  s += gx.y * gy.y * gz.x * texture(tex, vec3(hx.y, hy.y, hz.x));
  s += gx.x * gy.x * gz.y * texture(tex, vec3(hx.x, hy.x, hz.y));
  s += gx.y * gy.x * gz.y * texture(tex, vec3(hx.y, hy.x, hz.y));
  s += gx.x * gy.y * gz.y * texture(tex, vec3(hx.x, hy.y, hz.y));
  s += gx.y * gy.y * gz.y * texture(tex, vec3(hx.y, hy.y, hz.y));
  return s;
}
/*
 * Reconstruct the packed structural scalar and support either with
 * the shipped hardware trilinear path or with the same positive cubic B-spline
 * used by the corrective normal reconstruction.  Geometry and transfer are
 * independently selectable so the audit can attribute residual terracing.
 * The production candidate uses cubic geometry, trilinear transfer and the
 * packed cubic normal; native structural texels and the surface-level mapping
 * are unchanged.
 */
vec2 decodeStructuralSample(vec4 t){
  return vec2(t.r + t.g / 255.0, t.a);
}
vec2 structuralAtTex(vec3 c){
  if(!insideUnit(c)) return vec2(0.0, 0.0);
  return decodeStructuralSample(texture(uStructuralScalar, c));
}
vec2 structuralAtTexCubic(vec3 c){
  if(!insideUnit(c)) return vec2(0.0, 0.0);
  return decodeStructuralSample(textureTricubic(uStructuralScalar, c, uStructuralTexSize));
}
vec2 structuralFieldSampleAtTex(vec3 c){
#if NM_FIELD_MODE == 1
  return structuralAtTexCubic(c);
#elif NM_FIELD_MODE == 0
  return structuralAtTex(c);
#else
  return uStructuralFieldReconstruction == 1 ? structuralAtTexCubic(c) : structuralAtTex(c);
#endif
}
vec2 structuralTransferSampleAtTex(vec3 c){
#if NM_TRANSFER_MODE == 1
  return structuralAtTexCubic(c);
#elif NM_TRANSFER_MODE == 0
  return structuralAtTex(c);
#else
  return uStructuralTransferReconstruction == 1 ? structuralAtTexCubic(c) : structuralAtTex(c);
#endif
}
vec2 structuralFieldSampleAt(vec3 world){
  return structuralFieldSampleAtTex(texCoord(uWorldToStructuralTex, world));
}
vec2 structuralTransferSampleAt(vec3 world){
  return structuralTransferSampleAtTex(texCoord(uWorldToStructuralTex, world));
}
float structuralFieldAtTex(vec3 c){ return structuralField(structuralFieldSampleAtTex(c)); }
float structuralFieldAtWorld(vec3 world){ return structuralField(structuralFieldSampleAt(world)); }
vec4 normalFromTextureGradient(vec3 gradientTexture){
  vec3 gradientWorld = transpose(mat3(uWorldToStructuralTex)) * gradientTexture;
  float magnitude = length(gradientWorld);
  return vec4(magnitude > 1e-10 ? -gradientWorld / magnitude : vec3(0.0), magnitude);
}
vec4 decodePackedNormal(vec4 packed){
  vec3 decoded = packed.rgb * 2.0 - 1.0;
  float directionLength = length(decoded);
  return vec4(directionLength > 1e-8 ? decoded / directionLength : vec3(0.0), packed.a);
}
vec4 storedStructuralGradientAt(sampler3D volume, vec3 world){
  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec4(0.0);
  return decodePackedNormal(texture(volume, c));
}
vec4 packedTricubicNormalAt(vec3 world){
  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec4(0.0);
  return decodePackedNormal(textureTricubic(uStructuralGradient, c, uStructuralTexSize));
}
vec4 directStructuralGradientAt(vec3 world){
  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec4(0.0);
  vec3 h = vec3(max(0.05, uStructuralNormalStepVoxels)) / uStructuralTexSize;
  vec3 g = vec3(
    (structuralFieldAtTex(c + vec3(h.x, 0.0, 0.0)) - structuralFieldAtTex(c - vec3(h.x, 0.0, 0.0))) / (2.0 * h.x),
    (structuralFieldAtTex(c + vec3(0.0, h.y, 0.0)) - structuralFieldAtTex(c - vec3(0.0, h.y, 0.0))) / (2.0 * h.y),
    (structuralFieldAtTex(c + vec3(0.0, 0.0, h.z)) - structuralFieldAtTex(c - vec3(0.0, 0.0, h.z))) / (2.0 * h.z));
  return normalFromTextureGradient(g);
}
vec4 directEightCornerNormalAt(vec3 world){
  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec4(0.0);
  vec3 h = vec3(max(0.05, uStructuralNormalStepVoxels)) / uStructuralTexSize;
  vec3 g = vec3(0.0);
  for(int iz = 0; iz < 2; iz++){
    float sz = iz == 0 ? -1.0 : 1.0;
    for(int iy = 0; iy < 2; iy++){
      float sy = iy == 0 ? -1.0 : 1.0;
      for(int ix = 0; ix < 2; ix++){
        float sx = ix == 0 ? -1.0 : 1.0;
        float value = structuralFieldAtTex(c + vec3(sx * h.x, sy * h.y, sz * h.z));
        g += vec3(sx / (8.0 * h.x), sy / (8.0 * h.y), sz / (8.0 * h.z)) * value;
      }
    }
  }
  return normalFromTextureGradient(g);
}
vec4 structuralNormalAt(vec3 world){
#if NM_NORMAL_MODE == 5
  return packedTricubicNormalAt(world);
#elif NM_NORMAL_MODE == 0
  return storedStructuralGradientAt(uStructuralGradient, world);
#else
  if(uStructuralNormalEstimator == 6) return directEightCornerNormalAt(world);
  if(uStructuralNormalEstimator == 5) return packedTricubicNormalAt(world);
  if(uStructuralNormalEstimator == 4){
    vec4 central = storedStructuralGradientAt(uStructuralGradient, world);
    vec4 field = storedStructuralGradientAt(uStructuralGradientFieldSobel, world);
    float support = structuralFieldSampleAt(world).y;
    float fieldWeight = 1.0 - smoothstep(0.78, 0.96, support);
    vec3 normal = normalize(mix(central.rgb, field.rgb, fieldWeight));
    return vec4(normal, mix(central.a, field.a, fieldWeight));
  }
  if(uStructuralNormalEstimator == 3) return directStructuralGradientAt(world);
  if(uStructuralNormalEstimator == 2) return storedStructuralGradientAt(uStructuralGradientFieldSobel, world);
  if(uStructuralNormalEstimator == 1) return storedStructuralGradientAt(uStructuralGradientScalarSobel, world);
  return storedStructuralGradientAt(uStructuralGradient, world);
#endif
}
vec2 coverageAt(vec3 world){
  if(uCoverageAvailable == 0) return vec2(0.0);
  vec3 c = texCoord(uWorldToCoverageTex, world);
  if(!insideUnit(c)) return vec2(0.0);
  return texture(uCoverage, c).rg;
}
vec2 featureCoverageAt(vec3 world){ return structuralFieldAtWorld(world) >= uAnatomySurfaceLevel ? coverageAt(world) : vec2(0.0); }
/*
 * Presentation value for colour only. The geometry is continuous but a NEAREST
 * fetch of the native grid changes colour in native-voxel steps, which paints a
 * smooth surface in cubes. Positive and negative reconstructed means are stored independently in .b and
 * .a so overlapping smooth envelopes cannot exchange colours. Reported and
 * inspected values remain the native texelFetch.
 */
float coverageValueAt(vec3 world, float expectedSign){
  vec3 c = texCoord(uWorldToCoverageTex, world);
  if(!insideUnit(c)) return 0.0;
  vec4 t = texture(uCoverage, c);
  float unit = expectedSign < 0.0 ? t.a : t.b;
  return uCoverageValueRange.x + unit * (uCoverageValueRange.y - uCoverageValueRange.x);
}
float displayValue(vec3 hit, float nativeValue, float expectedSign){
  if(uFeatureValueShading != 1 || uCoverageAvailable != 1) return nativeValue;
  float reconstructed = coverageValueAt(hit, expectedSign);
  /* The presentation field must never cross polarity. Near an unsupported edge
     linear filtering may approach zero; retain the authoritative native value
     rather than painting the midpoint colour onto the component surface. */
  return reconstructed * expectedSign > 0.0 ? reconstructed : nativeValue;
}

/*
 * Authoritative native read. NEAREST texelFetch on the untouched native grid:
 * no filtering, no smoothing, no reconstruction participates in the value or the
 * support decision. This is what keeps the coverage field a presentation device.
 */
vec2 nativeFeatureAt(vec3 world){
  vec3 v = (uWorldToFeatureIndex * vec4(world, 1.0)).xyz;
  ivec3 c = ivec3(floor(v + 0.5));
  if(any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, uFeatureDims))) return vec2(0.0, 0.0);
  return texelFetch(uFeatureNative, c, 0).rg;
}

float atlasLabelAt(vec3 world){
  vec3 v = (uWorldToAtlasIndex * vec4(world, 1.0)).xyz;
  ivec3 c = ivec3(floor(v + 0.5));
  if(any(lessThan(c, ivec3(0))) || any(greaterThanEqual(c, uAtlasDims))) return 0.0;
  return texelFetch(uAtlasLabel, c, 0).r;
}
float roiMatchWeight(float label){
  float a = abs(label - uRoiCodeA) < 0.5 ? 1.0 : 0.0;
  float b = abs(label - uRoiCodeB) < 0.5 ? 1.0 : 0.0;
  if(abs(uRoiCodeA - uRoiCodeB) < 0.5) return a;
  return max(a * (1.0 - uRoiMix), b * uRoiMix);
}

// ------------------------------------------------------- feature classification

/* Identical semantics to the CPU projectionClass() and to the legacy shader. */
int projectionClass(float value){
  if(uThresholdMode == 1){
    if(value <= uNegativeThreshold) return -1;
    if(value >= uPositiveThreshold) return 1;
    return 0;
  }
  if(uThresholdMode == 2){
    float t = abs(uSingleThreshold);
    if(abs(value) < t) return 0;
    return value < 0.0 ? -1 : (value > 0.0 ? 1 : 0);
  }
  if(uThresholdMode == 3) return value <= uSingleThreshold ? -1 : 0;
  if(uThresholdMode == 4) return value >= uSingleThreshold ? 1 : 0;
  return value < 0.0 ? -1 : (value > 0.0 ? 1 : 0);
}
float projectionStrength(float value, int klass){
  float threshold, span;
  if(klass < 0){
    threshold = uThresholdMode == 2 ? -abs(uSingleThreshold)
              : (uThresholdMode == 1 ? uNegativeThreshold : uSingleThreshold);
    span = abs(threshold - uDisplayRange.x);
  } else {
    threshold = uThresholdMode == 2 ? abs(uSingleThreshold)
              : (uThresholdMode == 1 ? uPositiveThreshold : uSingleThreshold);
    span = abs(uDisplayRange.y - threshold);
  }
  return clamp(abs(value - threshold) / max(1e-20, span), 0.0, 1.0);
}
vec3 featureColor(float value){
  float t = clamp((value - uDisplayRange.x) / max(1e-20, uDisplayRange.y - uDisplayRange.x), 0.0, 1.0);
  vec3 mapped = clamp(texture(uFeatureLut, vec2(t, 0.5)).rgb, 0.0, 1.0);

  // Presentation-only colour intensity. Transform HSV saturation with a smooth
  // bounded response: intensity 1 is the LUT colour, values above 1 deepen
  // chroma asymptotically, and values below 1 desaturate. Unlike direct RGB
  // multiplication or a per-pixel hard saturation cap, this cannot whiten or
  // introduce clipping contours. Hue, peak channel, opacity and geometry remain
  // unchanged.
  float peak = max(mapped.r, max(mapped.g, mapped.b));
  float floor_ = min(mapped.r, min(mapped.g, mapped.b));
  float chroma = peak - floor_;
  if(peak <= 1e-6 || chroma <= 1e-6) return mapped;
  float saturation = clamp(chroma / peak, 0.0, 1.0);
  float intensity = max(uFeatureColorIntensity, 0.0);
  float targetSaturation = intensity <= 1.0
    ? saturation * intensity
    : 1.0 - pow(max(0.0, 1.0 - saturation), intensity);
  float saturationScale = targetSaturation / max(saturation, 1e-6);
  return clamp(vec3(peak) - (vec3(peak) - mapped) * saturationScale, 0.0, 1.0);
}

// ---------------------------------------------------------------- ray geometry

bool intersectBox(vec3 o, vec3 d, vec3 lo, vec3 hi, out float t0, out float t1){
  vec3 inv = vec3(
    abs(d.x) < 1e-8 ? 1e20 : 1.0 / d.x,
    abs(d.y) < 1e-8 ? 1e20 : 1.0 / d.y,
    abs(d.z) < 1e-8 ? 1e20 : 1.0 / d.z);
  vec3 a = (lo - o) * inv, b = (hi - o) * inv;
  vec3 n = min(a, b), f = max(a, b);
  t0 = max(max(n.x, n.y), n.z);
  t1 = min(min(f.x, f.y), f.z);
  return t1 >= t0;
}
bool clipPlane(vec4 plane, vec3 o, vec3 d, inout float t0, inout float t1){
  float dist = dot(plane.xyz, o) + plane.w, den = dot(plane.xyz, d);
  if(abs(den) < 1e-7) return dist >= 0.0;
  float cross_ = -dist / den;
  if(den > 0.0) t0 = max(t0, cross_); else t1 = min(t1, cross_);
  return t1 >= t0;
}
float projectedDepth(vec3 world){
  vec4 clip = uMVP * vec4(world, 1.0);
  return clip.z / clip.w * 0.5 + 0.5;
}

/* Deterministic interleaved gradient noise; uPhaseOffset advances it per frame. */
float rayPhase(vec2 fragCoord){
  float n = fract(52.9829189 * fract(0.06711056 * fragCoord.x + 0.00583715 * fragCoord.y));
  return fract(n + uPhaseOffset);
}

// ------------------------------------------------------------------ bisection

/*
 * The crossing is bracketed by two consecutive march samples. Bisection on the
 * hardware-interpolated field converges the hit to step/2^BISECTION_STEPS, which
 * makes the hit position a continuous function of screen position. That
 * continuity, not the step size, is what removes both the voxel facets of the DDA
 * and the stippling of jittered accumulation.
 */
float refineStructural(vec3 o, vec3 d, float tLo, float tHi, float level){
  for(int i = 0; i < BISECTION_STEPS; i++){
    float tm = 0.5 * (tLo + tHi);
    if(structuralFieldAtWorld(o + d * tm) < level) tLo = tm; else tHi = tm;
  }
  return 0.5 * (tLo + tHi);
}
float refineCoverage(vec3 o, vec3 d, float tLo, float tHi, float level, bool negativeChannel){
  for(int i = 0; i < BISECTION_STEPS; i++){
    float tm = 0.5 * (tLo + tHi);
    vec2 c = featureCoverageAt(o + d * tm);
    float v = negativeChannel ? c.y : c.x;
    if(v < level) tLo = tm; else tHi = tm;
  }
  return 0.5 * (tLo + tHi);
}

// -------------------------------------------------------------------- shading

/*
 * Phong, following MRIcroGL: ambient*colour + diffuse*colour*N.L + a specular
 * highlight, and nothing else. No ambient-occlusion term.
 *
 * Three occlusion estimators were tried here and each produced its own artefact:
 * binary hemisphere probes quantised occlusion into 13 levels and drew contour
 * lines (8.3% brightness steps); rotating the kernel turned that into speckle
 * concentrated at sulcal edges, where a sampled estimator's binomial variance
 * peaks (12.5% at 16 probes; ~278 needed for 3%); and a precomputed cavity field
 * built from the scalar inherited tissue-intensity variation, appearing as dark
 * and light patches inside sulci at low surface levels. MRIcroGL's raycast
 * shader contains no occlusion term at all -- its relief is the specular
 * highlight, which is a closed-form function of the normal and so can neither
 * band nor speckle.
 */
vec3 shade(vec3 baseColor, vec3 normal, vec3 viewDir){
  vec3 light = normalize(uLightDirection);
  float diffuse = max(dot(normal, light), 0.0);
  vec3 half_ = normalize(light + viewDir);
  float specular = pow(max(dot(normal, half_), 0.0), max(1.0, uShininess));
  vec3 lightScale = vec3(uAmbient) + uDiffuse * diffuse * uLightColor;
  return clamp(baseColor * lightScale + uSpecular * specular * uLightColor, 0.0, 1.0);
}

/*
 * Feature colours encode polarity and magnitude and must not inherit the
 * anatomy's achromatic specular highlight. A low-amplitude half-Lambert term
 * supplies shape relief by darkening only; it cannot create white glints, black
 * spots or hue changes.
 */
vec3 shadeFeature(vec3 baseColor, vec3 normal){
  vec3 light = normalize(uLightDirection);
  float facing = clamp(0.5 + 0.5 * dot(normal, light), 0.0, 1.0);
  float relief = mix(0.88, 1.0, facing * facing * (3.0 - 2.0 * facing));
  return baseColor * relief;
}

/*
 * Cheap sulcal darkening: probe outward along the normal. If tissue is still
 * present at the probe point the sample sits inside a crevice and is darkened.
 * Two taps give a visibly better depth cue than one and cost far less than SSAO.
 */
vec3 coverageNormal(vec3 world, float sign_){
  vec3 h = uCoverageTexelMm;
  vec2 xp = featureCoverageAt(world + vec3(h.x, 0.0, 0.0)), xm = featureCoverageAt(world - vec3(h.x, 0.0, 0.0));
  vec2 yp = featureCoverageAt(world + vec3(0.0, h.y, 0.0)), ym = featureCoverageAt(world - vec3(0.0, h.y, 0.0));
  vec2 zp = featureCoverageAt(world + vec3(0.0, 0.0, h.z)), zm = featureCoverageAt(world - vec3(0.0, 0.0, h.z));
  vec3 g = vec3(
    (xp.x - xp.y) - (xm.x - xm.y),
    (yp.x - yp.y) - (ym.x - ym.y),
    (zp.x - zp.y) - (zm.x - zm.y));
  float len = length(g);
  if(len < 1e-8) return vec3(0.0, 0.0, 1.0);
  return -sign_ * g / len;
}

/*
 * Authoritative value recovery for a presentation-envelope hit. The component-
 * preserving signed-distance surface may sit slightly outside the native voxel
 * union, so a single full-distance nudge can overshoot a thin cluster. Search at
 * fixed sub-voxel intervals along the inward ray and accept only the expected
 * polarity. Every returned value remains a nearest texelFetch of the untouched
 * native grid.
 */
vec2 nativeFeatureForHit(vec3 hit, vec3 direction, float nudgeMm, float expectedSign){
  for(int j = 0; j <= 8; j++){
    float fraction = float(j) / 8.0;
    vec2 nat = nativeFeatureAt(hit + direction * (fraction * nudgeMm));
    int klass = projectionClass(nat.x);
    bool signMatches = expectedSign > 0.0 ? klass > 0 : klass < 0;
    if(nat.y > 0.5 && signMatches) return nat;
  }
  return vec2(0.0, 0.0);
}

// ----------------------------------------------------------------------- main

void main(){
  vec3 direction = uProjectionMode == 1
    ? normalize(vWorldPosition - uEyeWorld)
    : normalize(uRayDirectionWorld);
  vec3 span = uBoundsMax - uBoundsMin;
  float offset = max(0.1, length(span) * 0.01);
  vec3 origin = uProjectionMode == 1 ? uEyeWorld : (vWorldPosition - direction * offset);

  float enterT, exitT;
  if(!intersectBox(origin, direction, uBoundsMin, uBoundsMax, enterT, exitT)) discard;
  enterT = max(enterT, 0.0);
  if(uClipCount > 0 && !clipPlane(uClipPlane0, origin, direction, enterT, exitT)) discard;
  if(uClipCount > 1 && !clipPlane(uClipPlane1, origin, direction, enterT, exitT)) discard;
  if(uClipCount > 2 && !clipPlane(uClipPlane2, origin, direction, enterT, exitT)) discard;
  if(exitT - enterT <= 1e-4) discard;

  vec3  viewDir = normalize(-direction);
  float step_   = max(0.05, uStepMm);
  float phase   = rayPhase(gl_FragCoord.xy);

  vec4  acc          = vec4(0.0);
  float depthT       = -1.0;
  int   anatomyHits  = 0;
  bool  positiveDone = false;
  bool  negativeDone = false;
  float positiveSlabEnd = -1.0;
  float negativeSlabEnd = -1.0;

  /*
   * Empty-space skip. MRIcroGL advances at ~2 voxels while the pre-baked RGBA
   * volume reads alpha == 0, then backs up one coarse step and switches to the
   * fine rate. Our structural texture already carries the support mask in .a, so
   * the same test applies directly: nothing can be visible where support and
   * coverage are both zero.
   */
  if(uEmptySkipMm > step_){
    float tSkip = enterT;
    for(int i = 0; i < NM_MAX_EMPTY_STEPS; i++){
      if(tSkip > exitT) break;
      vec3 q = origin + direction * tSkip;
      if(structuralAt(q).y > 0.0 || max(featureCoverageAt(q).x, featureCoverageAt(q).y) > 0.0) break;
      tSkip += uEmptySkipMm;
    }
    enterT = max(enterT, tSkip - uEmptySkipMm);
    if(exitT - enterT <= 1e-4) discard;
  }

  float tPrev = enterT;
  float fieldPrev = structuralFieldAtWorld(origin + direction * tPrev);
  vec2  cPrev = featureCoverageAt(origin + direction * tPrev);
  float t = enterT + phase * step_;

  for(int i = 0; i < NM_MAX_RAY_STEPS; i++){
    if(i >= uMaxSteps || t > exitT || acc.a > 0.985) break;
    vec3 p = origin + direction * t;

    vec2 s = structuralTransferSampleAt(p);
    vec2 c = featureCoverageAt(p);
    float field = structuralFieldAtWorld(p);

    float roiWeight  = uRoiFocusEnabled == 1 ? roiMatchWeight(atlasLabelAt(p)) : 1.0;
    float roiOpacity = uRoiFocusEnabled == 1 ? mix(uOutsideRoiOpacity, 1.0, roiWeight) : 1.0;

    /*
     * Video Maker ROI-silhouette pass. This is an explicit mask product, not
     * the ordinary attenuated ROI-focus presentation. It returns alpha only
     * where the selected atlas label intersects supported anatomical tissue. The
     * scalar cutoff matches the legacy Video Maker ROI-mask contract.
     */
    if(uRoiMaskOnly == 1){
      if(uRoiFocusEnabled == 1 && roiWeight > 0.001 && s.y > 0.0 && s.x > 0.055){
        acc = vec4(vec3(roiWeight), roiWeight);
        depthT = t;
        break;
      }
      fieldPrev = field;
      cPrev = c;
      tPrev = t;
      t += step_;
      continue;
    }

    // ---- anatomy: locate the surface, do not accumulate it
    if(anatomyHits < uAnatomyMaxSurfaces
       && fieldPrev < uAnatomySurfaceLevel && field >= uAnatomySurfaceLevel){
      float tHit = refineStructural(origin, direction, tPrev, t, uAnatomySurfaceLevel);
      vec3  hit  = origin + direction * tHit;
      /*
       * The gradient is taken at the hit point, with no selection among
       * neighbours.
       *
       * A strongest-of-three argmax was tried here, ported from MRIcroGL's
       * running prevGrad rule. It is the wrong port: that rule exists for
       * accumulation, where the surface is smeared across many samples and the
       * strongest gradient along the ray is the best available estimate. We
       * *locate* the surface, so the hit point is already where the normal should
       * be evaluated, and an argmax switches discontinuously wherever two
       * candidate magnitudes are close -- its switching locus is a level set of a
       * magnitude difference, which draws contour lines.
       *
       * Excess neighbouring-normal jump on the folded surrogate (p90 / p95, deg):
       *
       *     direct hit point            5.09 / 6.78     <- shipped
       *     argmax of three             9.80 / 14.39
       *     magnitude-weighted mean     5.85 / 8.08
       *     MRIcroGL one-step carry    10.13 / 20.06
       */
      vec4 grad = structuralNormalAt(hit);
#if NM_HIT_RULE == 1
      {
        vec4 gradBack = structuralNormalAt(hit - direction * (0.5 * step_));
        vec4 gradFwd  = structuralNormalAt(hit + direction * (0.5 * step_));
        if(gradBack.a > grad.a) grad = gradBack;
        if(gradFwd.a > grad.a) grad = gradFwd;
      }
#elif NM_HIT_RULE == 2
      {
        vec4 previous = structuralNormalAt(origin + direction * tPrev);
        if(grad.a < previous.a) grad.rgb = previous.rgb;
      }
#elif NM_HIT_RULE < 0
      if(uStructuralHitRule == 1){
        vec4 gradBack = structuralNormalAt(hit - direction * (0.5 * step_));
        vec4 gradFwd  = structuralNormalAt(hit + direction * (0.5 * step_));
        if(gradBack.a > grad.a) grad = gradBack;
        if(gradFwd.a > grad.a) grad = gradFwd;
      } else if(uStructuralHitRule == 2){
        vec4 previous = structuralNormalAt(origin + direction * tPrev);
        if(grad.a < previous.a) grad.rgb = previous.rgb;
      }
#endif
      vec3 normal = grad.a > 1e-10 ? grad.rgb : viewDir;
      if(dot(normal, viewDir) < 0.0) normal = -normal;

      float scalar = structuralTransferSampleAt(hit).x; // transfer reconstruction is audited independently of crossing geometry
      vec3  base   = texture(uStructuralLut, vec2(clamp(pow(scalar, 1.0 / max(0.25, uAnatomyGamma)), 0.0, 1.0), 0.5)).rgb * uAnatomyBrightness;
      vec3  color  = shade(base, normal, viewDir);

      float alpha  = clamp(uAnatomySurfaceAlpha, 0.0, 1.0);
      float remain = 1.0 - acc.a;
      acc.rgb += remain * color * alpha;
      acc.a   += remain * alpha;
      if(depthT < 0.0) depthT = tHit;
      anatomyHits++;
    }
    // ---- anatomy interior: a thin translucent haze so the volume is not hollow
    else if(anatomyHits > 0 && uAnatomyInteriorAlpha > 0.0001 && field >= uAnatomySurfaceLevel){
      vec3  base   = texture(uStructuralLut, vec2(clamp(pow(s.x, 1.0 / max(0.25, uAnatomyGamma)), 0.0, 1.0), 0.5)).rgb * uAnatomyBrightness;
      float alpha  = 1.0 - pow(max(0.0, 1.0 - uAnatomyInteriorAlpha), step_);
      float remain = 1.0 - acc.a;
      acc.rgb += remain * base * alpha;
      acc.a   += remain * alpha;
    }

    // ---- features: independent positive and negative coverage crossings
    if(uCoverageAvailable == 1 && uFeatureOpacity > 0.0001){

      if(!positiveDone && cPrev.x < uCoverageLevel && c.x >= uCoverageLevel){
        float tHit = refineCoverage(origin, direction, tPrev, t, uCoverageLevel, false);
        vec3  hit  = origin + direction * tHit;
        vec2  nat  = nativeFeatureForHit(hit, direction, uCoverageNudgeMm, 1.0);
        if(nat.y > 0.5){
          int klass = projectionClass(nat.x);
          /* One presentation value drives colour AND opacity. Taking colour from
             the smoothed field but opacity from the native nearest fetch leaves
             the opacity quantised at the native voxel, which prints a checkerboard
             onto otherwise smooth geometry at every sigma. MRIcroGL avoids this by
             applying the LUT per voxel and interpolating the resulting RGBA, so
             colour and alpha are always reconstructed together. */
          float shown = displayValue(hit, nat.x, 1.0);
          float strength = projectionStrength(shown, klass == 0 ? 1 : klass);
          vec3  normal = coverageNormal(hit, 1.0);
          if(dot(normal, viewDir) < 0.0) normal = -normal;
          vec3  color  = shadeFeature(featureColor(shown), normal);
          float alpha  = clamp(uFeatureOpacity * roiOpacity * (0.18 + 0.82 * strength), 0.0, 0.98);
          float remain = 1.0 - acc.a;
          acc.rgb += remain * color * alpha;
          acc.a   += remain * alpha;
          if(depthT < 0.0) depthT = tHit;
          positiveDone = true;
          positiveSlabEnd = tHit + max(0.0, uFeatureSlabMm);
        }
      }
      else if(positiveDone && t <= positiveSlabEnd && c.x >= uCoverageLevel && uFeatureInteriorAlpha > 0.0001){
        vec2 nat = nativeFeatureAt(p);
        if(nat.y > 0.5){
          float shown = displayValue(p, nat.x, 1.0);
          float strength = projectionStrength(shown, shown < 0.0 ? -1 : 1);
          float alpha  = 1.0 - pow(max(0.0, 1.0 - uFeatureInteriorAlpha * (0.2 + 0.8 * strength)), step_);
          alpha *= uFeatureOpacity * roiOpacity;
          float remain = 1.0 - acc.a;
          acc.rgb += remain * featureColor(shown) * alpha;
          acc.a   += remain * alpha;
        }
      }

      if(!negativeDone && cPrev.y < uCoverageLevel && c.y >= uCoverageLevel){
        float tHit = refineCoverage(origin, direction, tPrev, t, uCoverageLevel, true);
        vec3  hit  = origin + direction * tHit;
        vec2  nat  = nativeFeatureForHit(hit, direction, uCoverageNudgeMm, -1.0);
        if(nat.y > 0.5){
          int klass = projectionClass(nat.x);
          float shown = displayValue(hit, nat.x, -1.0);
          float strength = projectionStrength(shown, klass == 0 ? -1 : klass);
          vec3  normal = coverageNormal(hit, -1.0);
          if(dot(normal, viewDir) < 0.0) normal = -normal;
          vec3  color  = shadeFeature(featureColor(shown), normal);
          float alpha  = clamp(uFeatureOpacity * roiOpacity * (0.18 + 0.82 * strength), 0.0, 0.98);
          float remain = 1.0 - acc.a;
          acc.rgb += remain * color * alpha;
          acc.a   += remain * alpha;
          if(depthT < 0.0) depthT = tHit;
          negativeDone = true;
          negativeSlabEnd = tHit + max(0.0, uFeatureSlabMm);
        }
      }
      else if(negativeDone && t <= negativeSlabEnd && c.y >= uCoverageLevel && uFeatureInteriorAlpha > 0.0001){
        vec2 nat = nativeFeatureAt(p);
        if(nat.y > 0.5){
          float shown = displayValue(p, nat.x, -1.0);
          float strength = projectionStrength(shown, shown < 0.0 ? -1 : 1);
          float alpha  = 1.0 - pow(max(0.0, 1.0 - uFeatureInteriorAlpha * (0.2 + 0.8 * strength)), step_);
          alpha *= uFeatureOpacity * roiOpacity;
          float remain = 1.0 - acc.a;
          acc.rgb += remain * featureColor(shown) * alpha;
          acc.a   += remain * alpha;
        }
      }
    }

    fieldPrev = field;
    cPrev = c;
    tPrev = t;
    t += step_;
  }

  if(acc.a <= 0.002) discard;
  gl_FragDepth = depthT >= 0.0 ? clamp(projectedDepth(origin + direction * depthT), 0.0, 1.0) : 1.0;
  fragColor = vec4(clamp(acc.rgb, 0.0, 1.0), clamp(acc.a, 0.0, 1.0));
}`;

  // ------------------------------------------------------------------ program

  const PRODUCTION_CONFIGURATION = Object.freeze({
    fieldMode:1, transferMode:0, normalMode:5, hitRule:0,
    maxRaySteps:384, maxEmptySteps:192
  });

  const PROGRAM_VARIANTS = Object.freeze({
    production: Object.freeze(Object.assign({role:'production', sourceKind:'specialized'}, PRODUCTION_CONFIGURATION)),
    /* Retained alias for explicit legacy diagnostics; normal rendering never selects it. */
    still: Object.freeze(Object.assign({role:'production', sourceKind:'specialized'}, PRODUCTION_CONFIGURATION)),
    interaction: Object.freeze({role:'production', sourceKind:'specialized', fieldMode:0, transferMode:0, normalMode:0, hitRule:0, maxRaySteps:192, maxEmptySteps:96}),
    /* Branch-complete compatibility and audit sources are explicit audit roles. */
    still_compat: Object.freeze({role:'audit', sourceKind:'branch_complete', fieldMode:-1, transferMode:-1, normalMode:-1, hitRule:-1, maxRaySteps:384, maxEmptySteps:192}),
    audit: Object.freeze({role:'audit', sourceKind:'branch_complete', fieldMode:-1, transferMode:-1, normalMode:-1, hitRule:-1, maxRaySteps:2048, maxEmptySteps:512})
  });

  function normalizeProgramVariant(value){
    const key=String(value||'production');
    if(!Object.prototype.hasOwnProperty.call(PROGRAM_VARIANTS,key)){
      const error=new Error(`Unknown volume shader variant: ${key}`);
      error.code='unknown_shader_variant';
      throw error;
    }
    return key;
  }

  let PROGRAM_SEQUENCE = 0;

  function sourceHash(value){
    const text = String(value == null ? '' : value);
    let hash = 0x811c9dc5;
    for(let i=0;i<text.length;i++){
      hash ^= text.charCodeAt(i);
      hash = Math.imul(hash, 0x01000193);
    }
    return ('00000000' + (hash >>> 0).toString(16)).slice(-8);
  }

  function utf8ByteLength(value){
    const text=String(value==null?'':value);
    if(typeof TextEncoder!=='undefined')return new TextEncoder().encode(text).byteLength;
    return unescape(encodeURIComponent(text)).length;
  }

  function replaceExact(source,search,replacement,label){
    const first=source.indexOf(search),last=source.lastIndexOf(search);
    if(first<0||first!==last)throw new Error(`Production shader specialisation failed at ${label}.`);
    return source.slice(0,first)+replacement+source.slice(first+search.length);
  }

  function removeGlslFunction(source,name){
    const pattern=new RegExp(String.raw`\n(?:bool|int|float|vec[234]|mat[234])\s+${name}\s*\(`);
    const match=pattern.exec(source);
    if(!match)throw new Error(`Production shader specialisation could not locate ${name}().`);
    const start=match.index+1,brace=source.indexOf('{',start);
    if(brace<0)throw new Error(`Production shader specialisation found no body for ${name}().`);
    let depth=0,end=-1;
    for(let i=brace;i<source.length;i++){
      if(source[i]==='{')depth++;
      else if(source[i]==='}'&&--depth===0){end=i+1;break;}
    }
    if(end<0)throw new Error(`Production shader specialisation found an unterminated ${name}().`);
    while(end<source.length&&(source[end]==='\r'||source[end]==='\n'))end++;
    return source.slice(0,start)+source.slice(end);
  }

  function compactGlslSource(source){
    return source.replace(/\/\*[\s\S]*?\*\//g,'').split('\n')
      .map(line=>line.replace(/\/\/.*$/,'').trim()).filter(Boolean).join('\n');
  }

  function productionFragmentSource(spec){
    const supported=(spec.fieldMode===0||spec.fieldMode===1)&&(spec.transferMode===0||spec.transferMode===1)&&(spec.normalMode===0||spec.normalMode===5)&&spec.hitRule===0;
    if(!supported)throw new Error(`Unsupported production shader configuration: field=${spec.fieldMode}; transfer=${spec.transferMode}; normal=${spec.normalMode}; hit=${spec.hitRule}`);
    let source=FRAGMENT_SOURCE;
    source=replaceExact(source,`#ifndef NM_FIELD_MODE
#define NM_FIELD_MODE -1
#endif
#ifndef NM_TRANSFER_MODE
#define NM_TRANSFER_MODE -1
#endif
#ifndef NM_NORMAL_MODE
#define NM_NORMAL_MODE -1
#endif
#ifndef NM_HIT_RULE
#define NM_HIT_RULE -1
#endif
#ifndef NM_MAX_RAY_STEPS
#define NM_MAX_RAY_STEPS 2048
#endif
#ifndef NM_MAX_EMPTY_STEPS
#define NM_MAX_EMPTY_STEPS 512
#endif`, `#define NM_MAX_RAY_STEPS ${spec.maxRaySteps}
#define NM_MAX_EMPTY_STEPS ${spec.maxEmptySteps}`, 'compile-time definitions');
    [
      'uniform sampler3D uStructuralGradientScalarSobel; // R1B scalar Sobel audit texture\n',
      'uniform sampler3D uStructuralGradientFieldSobel;  // R1B support-aware Sobel audit texture\n',
      'uniform int       uStructuralFieldReconstruction;    // 0 trilinear scalar*support, 1 cubic B-spline scalar*support\n',
      'uniform int       uStructuralTransferReconstruction; // 0 trilinear scalar, 1 cubic B-spline scalar\n',
      'uniform int       uStructuralNormalEstimator;        // 0 central, 1 scalar Sobel, 2 field Sobel, 3 direct central, 4 hybrid, 5 packed tricubic, 6 direct 8-corner\n',
      'uniform int       uStructuralHitRule;             // 0 exact hit, 1 strongest bracket, 2 one-step carry\n',
      'uniform int       uStructuralAuditVariantsAvailable;\n',
      'uniform float     uStructuralNormalStepVoxels;\n'
    ].forEach((line,index)=>{source=replaceExact(source,line,'',`audit uniform ${index+1}`);});
    const fieldBody=spec.fieldMode===1?'  return structuralAtTexCubic(c);':'  return structuralAtTex(c);';
    source=replaceExact(source,`vec2 structuralFieldSampleAtTex(vec3 c){
#if NM_FIELD_MODE == 1
  return structuralAtTexCubic(c);
#elif NM_FIELD_MODE == 0
  return structuralAtTex(c);
#else
  return uStructuralFieldReconstruction == 1 ? structuralAtTexCubic(c) : structuralAtTex(c);
#endif
}`,`vec2 structuralFieldSampleAtTex(vec3 c){
${fieldBody}
}`,'field reconstruction');
    const transferBody=spec.transferMode===1?'  return structuralAtTexCubic(c);':'  return structuralAtTex(c);';
    source=replaceExact(source,`vec2 structuralTransferSampleAtTex(vec3 c){
#if NM_TRANSFER_MODE == 1
  return structuralAtTexCubic(c);
#elif NM_TRANSFER_MODE == 0
  return structuralAtTex(c);
#else
  return uStructuralTransferReconstruction == 1 ? structuralAtTexCubic(c) : structuralAtTex(c);
#endif
}`,`vec2 structuralTransferSampleAtTex(vec3 c){
${transferBody}
}`,'transfer reconstruction');
    ['normalFromTextureGradient','storedStructuralGradientAt','directStructuralGradientAt','directEightCornerNormalAt'].forEach(name=>{source=removeGlslFunction(source,name);});
    const normalBody=spec.normalMode===5?'  return packedTricubicNormalAt(world);':`  vec3 c = texCoord(uWorldToStructuralTex, world);
  if(!insideUnit(c)) return vec4(0.0);
  return decodePackedNormal(texture(uStructuralGradient, c));`;
    source=replaceExact(source,`vec4 structuralNormalAt(vec3 world){
#if NM_NORMAL_MODE == 5
  return packedTricubicNormalAt(world);
#elif NM_NORMAL_MODE == 0
  return storedStructuralGradientAt(uStructuralGradient, world);
#else
  if(uStructuralNormalEstimator == 6) return directEightCornerNormalAt(world);
  if(uStructuralNormalEstimator == 5) return packedTricubicNormalAt(world);
  if(uStructuralNormalEstimator == 4){
    vec4 central = storedStructuralGradientAt(uStructuralGradient, world);
    vec4 field = storedStructuralGradientAt(uStructuralGradientFieldSobel, world);
    float support = structuralFieldSampleAt(world).y;
    float fieldWeight = 1.0 - smoothstep(0.78, 0.96, support);
    vec3 normal = normalize(mix(central.rgb, field.rgb, fieldWeight));
    return vec4(normal, mix(central.a, field.a, fieldWeight));
  }
  if(uStructuralNormalEstimator == 3) return directStructuralGradientAt(world);
  if(uStructuralNormalEstimator == 2) return storedStructuralGradientAt(uStructuralGradientFieldSobel, world);
  if(uStructuralNormalEstimator == 1) return storedStructuralGradientAt(uStructuralGradientScalarSobel, world);
  return storedStructuralGradientAt(uStructuralGradient, world);
#endif
}`,`vec4 structuralNormalAt(vec3 world){
${normalBody}
}`,'normal estimator');
    source=replaceExact(source,`#if NM_HIT_RULE == 1
      {
        vec4 gradBack = structuralNormalAt(hit - direction * (0.5 * step_));
        vec4 gradFwd  = structuralNormalAt(hit + direction * (0.5 * step_));
        if(gradBack.a > grad.a) grad = gradBack;
        if(gradFwd.a > grad.a) grad = gradFwd;
      }
#elif NM_HIT_RULE == 2
      {
        vec4 previous = structuralNormalAt(origin + direction * tPrev);
        if(grad.a < previous.a) grad.rgb = previous.rgb;
      }
#elif NM_HIT_RULE < 0
      if(uStructuralHitRule == 1){
        vec4 gradBack = structuralNormalAt(hit - direction * (0.5 * step_));
        vec4 gradFwd  = structuralNormalAt(hit + direction * (0.5 * step_));
        if(gradBack.a > grad.a) grad = gradBack;
        if(gradFwd.a > grad.a) grad = gradFwd;
      } else if(uStructuralHitRule == 2){
        vec4 previous = structuralNormalAt(origin + direction * tPrev);
        if(grad.a < previous.a) grad.rgb = previous.rgb;
      }
#endif
`,'','hit rule');
    return compactGlslSource(source);
  }

  const SPECIALIZED_SOURCE_CACHE=new Map();
  function fragmentSourceForVariant(value){
    const variant=normalizeProgramVariant(value),spec=PROGRAM_VARIANTS[variant];
    if(spec.sourceKind==='specialized'){
      const key=[spec.fieldMode,spec.transferMode,spec.normalMode,spec.hitRule,spec.maxRaySteps,spec.maxEmptySteps].join(':');
      if(!SPECIALIZED_SOURCE_CACHE.has(key))SPECIALIZED_SOURCE_CACHE.set(key,productionFragmentSource(spec));
      return SPECIALIZED_SOURCE_CACHE.get(key);
    }
    const definitions=[
      `#define NM_FIELD_MODE ${spec.fieldMode}`,
      `#define NM_TRANSFER_MODE ${spec.transferMode}`,
      `#define NM_NORMAL_MODE ${spec.normalMode}`,
      `#define NM_HIT_RULE ${spec.hitRule}`,
      `#define NM_MAX_RAY_STEPS ${spec.maxRaySteps}`,
      `#define NM_MAX_EMPTY_STEPS ${spec.maxEmptySteps}`
    ].join('\n');
    return FRAGMENT_SOURCE.replace('#version 300 es',`#version 300 es\n${definitions}`);
  }

  function programSourceIdentity(value){
    const variant=normalizeProgramVariant(value),spec=PROGRAM_VARIANTS[variant],fragmentSource=fragmentSourceForVariant(variant),combined=VERTEX_SOURCE+'\n'+fragmentSource;
    return {variant,role:spec.role,configurationSignature:`field=${spec.fieldMode};transfer=${spec.transferMode};normal=${spec.normalMode};hit=${spec.hitRule};ray=${spec.maxRaySteps};empty=${spec.maxEmptySteps}`,sourceHash:sourceHash(combined),sourceBytes:utf8ByteLength(fragmentSource),sourceLines:fragmentSource.split('\n').length};
  }

  const UNIFORM_NAMES = [
    'uMVP', 'uProjectionMode', 'uEyeWorld', 'uRayDirectionWorld', 'uBoundsMin', 'uBoundsMax',
    'uStepMm', 'uEmptySkipMm', 'uMaxSteps', 'uPhaseOffset',
    'uClipCount', 'uClipPlane0', 'uClipPlane1', 'uClipPlane2',
    'uStructuralScalar', 'uStructuralGradient', 'uStructuralGradientScalarSobel',
    'uStructuralGradientFieldSobel',
    'uWorldToStructuralTex', 'uStructuralTexSize', 'uStructuralFieldReconstruction', 'uStructuralTransferReconstruction', 'uStructuralNormalEstimator', 'uStructuralHitRule',
    'uStructuralAuditVariantsAvailable', 'uStructuralNormalStepVoxels',
    'uAnatomySurfaceLevel', 'uAnatomySurfaceAlpha', 'uAnatomyInteriorAlpha', 'uAnatomyMaxSurfaces',
    'uAnatomyBrightness', 'uAnatomyGamma',
    'uCoverage', 'uWorldToCoverageTex', 'uCoverageTexelMm', 'uCoverageLevel', 'uCoverageNudgeMm', 'uCoverageAvailable',
    'uFeatureNative', 'uWorldToFeatureIndex', 'uFeatureDims',
    'uFeatureOpacity', 'uFeatureColorIntensity', 'uFeatureSlabMm', 'uFeatureInteriorAlpha', 'uFeatureValueShading', 'uCoverageValueRange',
    'uFeatureLut', 'uStructuralLut', 'uDisplayRange',
    'uThresholdMode', 'uNegativeThreshold', 'uPositiveThreshold', 'uSingleThreshold',
    'uAtlasLabel', 'uWorldToAtlasIndex', 'uAtlasDims',
    'uRoiFocusEnabled', 'uRoiCodeA', 'uRoiCodeB', 'uRoiMix', 'uOutsideRoiOpacity', 'uRoiMaskOnly',
    'uLightDirection', 'uLightColor', 'uAmbient', 'uDiffuse', 'uSpecular', 'uShininess'
  ];

  function compileShader(gl, type, source) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    return shader;
  }

  /*
   * Compilation is started here but not waited on. Call resolveProgram() to
   * finish; with KHR_parallel_shader_compile that lets the caller poll instead of
   * stalling the main thread, which is what produced the ~15 s first-frame hang.
   */
  function createProgram(gl, variantName) {
    const variant = normalizeProgramVariant(variantName),identity=programSourceIdentity(variant);
    const startedAt = nowMs();
    const fragmentSource = fragmentSourceForVariant(variant);
    const vs = compileShader(gl, gl.VERTEX_SHADER, VERTEX_SOURCE);
    const fs = compileShader(gl, gl.FRAGMENT_SHADER, fragmentSource);
    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.bindAttribLocation(program, 0, 'aPosition');
    gl.linkProgram(program);
    return {
      program, vertexShader: vs, fragmentShader: fs,
      parallel: gl.getExtension('KHR_parallel_shader_compile'),
      variant, role:identity.role, configurationSignature:identity.configurationSignature,
      sourceBytes:identity.sourceBytes, sourceLines:identity.sourceLines,
      startedAt, completedAt: NaN, locations: null, ready: false,
      programId: `nm-volume-program-${++PROGRAM_SEQUENCE}`,
      sourceHash: identity.sourceHash
    };
  }

  function programReady(gl, handle) {
    if (handle.ready) return true;
    if (handle.parallel) {
      return !!gl.getProgramParameter(handle.program, handle.parallel.COMPLETION_STATUS_KHR);
    }
    return true;
  }

  function resolveProgram(gl, handle) {
    if (handle.ready) return handle;
    if (handle.parallel && !gl.getProgramParameter(handle.program, handle.parallel.COMPLETION_STATUS_KHR)) {
      const error = new Error(`Volume ray-cast program ${handle.variant} is still compiling.`);
      error.code = 'program_pending';
      throw error;
    }
    if (!gl.getProgramParameter(handle.program, gl.LINK_STATUS)) {
      const log = [
        gl.getShaderInfoLog(handle.vertexShader) || '',
        gl.getShaderInfoLog(handle.fragmentShader) || '',
        gl.getProgramInfoLog(handle.program) || ''
      ].filter(Boolean).join('\n');
      throw new Error('Volume ray-cast program failed to link: ' + log);
    }
    gl.deleteShader(handle.vertexShader);
    gl.deleteShader(handle.fragmentShader);
    const locations = {};
    UNIFORM_NAMES.forEach(name => { locations[name] = gl.getUniformLocation(handle.program, name); });
    handle.locations = locations;
    handle.ready = true;
    handle.completedAt = nowMs();
    handle.compileMs = handle.completedAt - handle.startedAt;
    return handle;
  }

  // --------------------------------------------------------------------- draw

  const TEXTURE_UNITS = {
    structuralScalar: 0, structuralGradient: 1, coverage: 2,
    featureNative: 3, atlasLabel: 4, featureLut: 5, structuralLut: 6,
    structuralGradientAuditA: 7, structuralGradientFieldSobel: 8
  };

  function bind3D(gl, unit, texture) {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_3D, texture);
  }
  function bind2D(gl, unit, texture) {
    gl.activeTexture(gl.TEXTURE0 + unit);
    gl.bindTexture(gl.TEXTURE_2D, texture);
  }

  /*
   * state = {
   *   mvp, projection, eye, forward, bounds, clipPlanes,
   *   structural, coverage, nativeFeature, atlasLabel,
   *   featureLut, structuralLut, style, lighting, frameIndex, phaseOffset
   * }
   */
  function draw(gl, handle, state) {
    if (!handle.ready) throw new Error('Volume ray-cast program is not ready.');
    const inheritedErrors = drainGlErrors(gl);
    const l = handle.locations, s = state.style || {}, light = state.lighting || {};
    const zero4 = new Float32Array([0, 0, 0, 1]);
    const identity = new Float32Array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
    const fallback = ensureFallbackTextures(gl);

    gl.useProgram(handle.program);

    gl.uniformMatrix4fv(l.uMVP, false, state.mvp);
    gl.uniform1i(l.uProjectionMode, state.projection === 'perspective' ? 1 : 0);
    gl.uniform3fv(l.uEyeWorld, new Float32Array(state.eye));
    gl.uniform3fv(l.uRayDirectionWorld, new Float32Array(state.forward));
    gl.uniform3fv(l.uBoundsMin, new Float32Array(state.bounds.min));
    gl.uniform3fv(l.uBoundsMax, new Float32Array(state.bounds.max));
    gl.uniform1f(l.uStepMm, finite(s.stepMm, 1));
    /* ~2 voxels, matching MRIcroGL's sliceSize*1.95 */
    gl.uniform1f(l.uEmptySkipMm, Math.max(finite(s.stepMm, 1),
      1.95 * Math.min.apply(null, state.structural.spacingMm)));
    gl.uniform1i(l.uMaxSteps, Math.max(1, Math.floor(finite(s.maxSteps, 512))));
    const phaseOffset = Number.isFinite(Number(state.phaseOffset))
      ? ((Number(state.phaseOffset) % 1) + 1) % 1
      : (finite(state.frameIndex, 0) * 0.6180339887 % 1);
    gl.uniform1f(l.uPhaseOffset, phaseOffset);

    const clip = state.clipPlanes || [];
    gl.uniform1i(l.uClipCount, Math.min(MAX_CLIP_PLANES, clip.length));
    gl.uniform4fv(l.uClipPlane0, clip[0] ? new Float32Array(clip[0]) : zero4);
    gl.uniform4fv(l.uClipPlane1, clip[1] ? new Float32Array(clip[1]) : zero4);
    gl.uniform4fv(l.uClipPlane2, clip[2] ? new Float32Array(clip[2]) : zero4);

    // structural
    bind3D(gl, TEXTURE_UNITS.structuralScalar, state.structural.scalar);
    gl.uniform1i(l.uStructuralScalar, TEXTURE_UNITS.structuralScalar);
    bind3D(gl, TEXTURE_UNITS.structuralGradient, state.structural.gradient);
    gl.uniform1i(l.uStructuralGradient, TEXTURE_UNITS.structuralGradient);
    const variantsAvailable = !!(state.structural.gradientScalarSobel && state.structural.gradientFieldSobel);
    const requestedEstimator = clamp(Math.floor(finite(s.structuralNormalEstimator, 5)), 0, 6);
    let activeEstimator = requestedEstimator;
    if ((activeEstimator === 1 || activeEstimator === 2 || activeEstimator === 4) && !variantsAvailable) activeEstimator = 5;
    if(handle.variant === 'audit' || handle.variant === 'still_compat'){
      bind3D(gl, TEXTURE_UNITS.structuralGradientAuditA,
        state.structural.gradientScalarSobel || state.structural.gradient);
      gl.uniform1i(l.uStructuralGradientScalarSobel, TEXTURE_UNITS.structuralGradientAuditA);
      bind3D(gl, TEXTURE_UNITS.structuralGradientFieldSobel,
        state.structural.gradientFieldSobel || state.structural.gradient);
      gl.uniform1i(l.uStructuralGradientFieldSobel, TEXTURE_UNITS.structuralGradientFieldSobel);
    }
    gl.uniformMatrix4fv(l.uWorldToStructuralTex, false, state.structural.worldToTexture);
    gl.uniform3fv(l.uStructuralTexSize, new Float32Array(state.structural.dims));
    gl.uniform1i(l.uStructuralFieldReconstruction, clamp(Math.floor(finite(s.structuralFieldReconstruction, 1)), 0, 1));
    gl.uniform1i(l.uStructuralTransferReconstruction, clamp(Math.floor(finite(s.structuralTransferReconstruction, 0)), 0, 1));
    gl.uniform1i(l.uStructuralNormalEstimator, activeEstimator);
    gl.uniform1i(l.uStructuralHitRule, clamp(Math.floor(finite(s.structuralHitRule, 0)), 0, 2));
    gl.uniform1i(l.uStructuralAuditVariantsAvailable, variantsAvailable ? 1 : 0);
    const minSpacing = Math.min.apply(null, state.structural.spacingMm);
    const normalStepMm = Math.max(0.05, finite(s.structuralNormalStepMm, 0.5 * minSpacing));
    gl.uniform1f(l.uStructuralNormalStepVoxels, clamp(normalStepMm / Math.max(1e-6, minSpacing), 0.05, 2.0));
    /*
     * The control position is a quantile of the supported structural scalar, not a
     * raw level, so equal slider steps enclose equal amounts of tissue instead of
     * stalling on the histogram plateaus between tissue classes.
     */
    const levelPosition = clamp(finite(s.anatomySurfaceLevel, 0.38), 0.01, 0.99);
    const quantiles = state.structural.levelQuantiles;
    const mappedLevel = (quantiles && quantiles.length === 257)
      ? quantiles[clamp(Math.round(levelPosition * 256), 0, 256)]
      : levelPosition;
    gl.uniform1f(l.uAnatomySurfaceLevel, clamp(finite(mappedLevel, levelPosition), 0.005, 0.995));
    gl.uniform1f(l.uAnatomySurfaceAlpha, clamp(finite(s.anatomySurfaceAlpha, 0.62), 0, 1));
    gl.uniform1f(l.uAnatomyInteriorAlpha, clamp(finite(s.anatomyInteriorAlpha, 0.012), 0, 1));
    gl.uniform1i(l.uAnatomyMaxSurfaces, Math.max(0, Math.floor(finite(s.anatomyMaxSurfaces, 1))));
    gl.uniform1f(l.uAnatomyBrightness, clamp(finite(s.brightness, 1), 0, 2));
    gl.uniform1f(l.uAnatomyGamma, clamp(finite(s.structuralGamma, 1), 0.25, 4));

    // coverage
    const coverage = state.coverage || null;
    gl.uniform1i(l.uCoverageAvailable, coverage ? 1 : 0);
    bind3D(gl, TEXTURE_UNITS.coverage, coverage ? coverage.texture : fallback.rg8);
    gl.uniform1i(l.uCoverage, TEXTURE_UNITS.coverage);
    gl.uniformMatrix4fv(l.uWorldToCoverageTex, false, coverage ? coverage.worldToTexture : identity);
    gl.uniform3fv(l.uCoverageTexelMm, new Float32Array(coverage ? coverage.spacingMm : [1, 1, 1]));
    gl.uniform1f(l.uCoverageLevel, coverage ? finite(coverage.coverageBoundaryLevel, 0.5) : 0.5);
    gl.uniform1f(l.uCoverageNudgeMm, coverage ? Math.max(0.5, finite(coverage.nativeRecoveryMaxMm, finite(coverage.boundarySmoothingMm, 1))) : 1);

    // native feature
    const nativeFeature = state.nativeFeature;
    bind3D(gl, TEXTURE_UNITS.featureNative, nativeFeature ? nativeFeature.texture : fallback.rg32f);
    gl.uniform1i(l.uFeatureNative, TEXTURE_UNITS.featureNative);
    gl.uniformMatrix4fv(l.uWorldToFeatureIndex, false, nativeFeature ? nativeFeature.worldToVoxelIndex : identity);
    gl.uniform3iv(l.uFeatureDims, new Int32Array(nativeFeature ? nativeFeature.dims : [1, 1, 1]));
    gl.uniform1f(l.uFeatureOpacity, clamp(finite(s.featureOpacity, 0.82), 0, 1));
    gl.uniform1f(l.uFeatureColorIntensity, clamp(finite(s.featureColorIntensity, 1), 0.25, 2.5));
    gl.uniform1f(l.uFeatureSlabMm, Math.max(0, finite(s.featureSlabMm, 6)));
    gl.uniform1f(l.uFeatureInteriorAlpha, clamp(finite(s.featureInteriorAlpha, 0.06), 0, 1));
    gl.uniform1i(l.uFeatureValueShading, s.featureValueShading ? 1 : 0);
    gl.uniform2fv(l.uCoverageValueRange, new Float32Array(coverage ? coverage.valueRange : [-1, 1]));

    // colour mapping
    bind2D(gl, TEXTURE_UNITS.featureLut, state.featureLut);
    gl.uniform1i(l.uFeatureLut, TEXTURE_UNITS.featureLut);
    bind2D(gl, TEXTURE_UNITS.structuralLut, state.structuralLut);
    gl.uniform1i(l.uStructuralLut, TEXTURE_UNITS.structuralLut);
    gl.uniform2fv(l.uDisplayRange, new Float32Array(s.displayRange || [0, 1]));
    gl.uniform1i(l.uThresholdMode, Math.floor(finite(s.thresholdMode, 0)));
    gl.uniform1f(l.uNegativeThreshold, finite(s.thresholdLow, 0));
    gl.uniform1f(l.uPositiveThreshold, finite(s.thresholdHigh, 0));
    gl.uniform1f(l.uSingleThreshold, finite(s.thresholdValue, 0));

    // ROI focus
    const atlas = state.atlasLabel || null;
    bind3D(gl, TEXTURE_UNITS.atlasLabel, atlas ? atlas.texture : fallback.r32f);
    gl.uniform1i(l.uAtlasLabel, TEXTURE_UNITS.atlasLabel);
    gl.uniformMatrix4fv(l.uWorldToAtlasIndex, false, atlas ? atlas.worldToVoxelIndex : identity);
    gl.uniform3iv(l.uAtlasDims, new Int32Array(atlas ? atlas.dims : [1, 1, 1]));
    gl.uniform1i(l.uRoiFocusEnabled, (atlas && s.roiFocusEnabled) ? 1 : 0);
    gl.uniform1f(l.uRoiCodeA, finite(s.roiCodeA, 0));
    gl.uniform1f(l.uRoiCodeB, finite(s.roiCodeB, 0));
    gl.uniform1f(l.uRoiMix, clamp(finite(s.roiMix, 1), 0, 1));
    gl.uniform1f(l.uOutsideRoiOpacity, clamp(finite(s.outsideRoiOpacity, 1), 0, 1));
    gl.uniform1i(l.uRoiMaskOnly, (atlas && s.roiFocusEnabled && s.roiMaskOnly) ? 1 : 0);

    // lighting
    gl.uniform3fv(l.uLightDirection, new Float32Array(light.lightDirection || [0.35, 0.5, 0.78]));
    gl.uniform3fv(l.uLightColor, new Float32Array(light.lightColor || [1, 1, 1]));
    gl.uniform1f(l.uAmbient, clamp(finite(light.ambient, 0.22), 0, 2));
    gl.uniform1f(l.uDiffuse, clamp(finite(light.diffuse, 0.82), 0, 2));
    gl.uniform1f(l.uSpecular, clamp(finite(light.specular, 0.25), 0, 2));
    gl.uniform1f(l.uShininess, clamp(finite(light.shininess, 32), 1, 128));

    const bindingErrors = drainGlErrors(gl);
    const samplerAudit = activeSamplerAudit(gl, handle.program);
    const samplerUnits = samplerAudit.samplers.map(item => item.unit).filter(Number.isFinite);
    const textureUnits = textureUnitAudit(gl, samplerUnits);
    const auditErrors = drainGlErrors(gl);
    const byUnit = new Map(textureUnits.map(item => [item.unit, item]));
    const expectedUnits = {
      uStructuralScalar: TEXTURE_UNITS.structuralScalar,
      uStructuralGradient: TEXTURE_UNITS.structuralGradient,
      uStructuralGradientScalarSobel: TEXTURE_UNITS.structuralGradientAuditA,
      uStructuralGradientFieldSobel: TEXTURE_UNITS.structuralGradientFieldSobel,
      uCoverage: TEXTURE_UNITS.coverage,
      uFeatureNative: TEXTURE_UNITS.featureNative,
      uAtlasLabel: TEXTURE_UNITS.atlasLabel,
      uFeatureLut: TEXTURE_UNITS.featureLut,
      uStructuralLut: TEXTURE_UNITS.structuralLut
    };
    const samplerIssues = [];
    const targetsByUnit = new Map();
    samplerAudit.samplers.forEach(item => {
      if (!Number.isFinite(item.unit)) {
        samplerIssues.push(Object.assign({ issue: 'unit_unset' }, item));
        return;
      }
      if (item.unit < 0 || item.unit >= samplerAudit.maxFragmentTextureUnits) {
        samplerIssues.push(Object.assign({ issue: 'unit_out_of_range' }, item));
        return;
      }
      const expected = expectedUnits[item.name];
      if (Number.isFinite(expected) && item.unit !== expected) {
        samplerIssues.push(Object.assign({ issue: 'unexpected_unit', expectedUnit: expected }, item));
      }
      const binding = byUnit.get(item.unit);
      let targetBound = false;
      if (binding) {
        if (item.target === 'TEXTURE_3D') targetBound = binding.bound3D;
        else if (item.target === 'TEXTURE_2D') targetBound = binding.bound2D;
        else if (item.target === 'TEXTURE_CUBE_MAP') targetBound = binding.boundCube;
        else if (item.target === 'TEXTURE_2D_ARRAY') targetBound = binding.bound2DArray;
      }
      if (!targetBound) samplerIssues.push(Object.assign({ issue: 'target_unbound' }, item));
      if (!targetsByUnit.has(item.unit)) targetsByUnit.set(item.unit, new Set());
      targetsByUnit.get(item.unit).add(item.target);
    });
    targetsByUnit.forEach((targets, unit) => {
      if (targets.size > 1) samplerIssues.push({
        issue: 'mixed_sampler_types', unit,
        target: Array.from(targets).sort().join('+'), name: 'multiple_active_samplers'
      });
    });
    return {
      variant: handle.variant,
      inheritedErrors,
      bindingErrors,
      auditErrors,
      samplerAudit,
      textureUnits,
      samplerIssues,
      currentProgramMatches: gl.getParameter(gl.CURRENT_PROGRAM) === handle.program
    };
  }

  const api = {
    MAX_CLIP_PLANES,
    TEXTURE_UNITS,
    PRODUCTION_CONFIGURATION,
    PROGRAM_VARIANTS,
    VERTEX_SOURCE,
    FRAGMENT_SOURCE,
    fragmentSourceForVariant,
    normalizeProgramVariant,
    programSourceIdentity,
    UNIFORM_NAMES,
    glErrorName,
    drainGlErrors,
    activeSamplerAudit,
    textureUnitAudit,
    acquireContext,
    capability,
    createTexture3D,
    uploadStructural,
    uploadCoverage,
    uploadNativeFeature,
    uploadAtlasLabel,
    ensureFallbackTextures,
    disposeFallbackTextures,
    disposeResource,
    createProgram,
    programReady,
    resolveProgram,
    draw
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.NMVolumeRaycastGL2 = api;
})(typeof self !== 'undefined' ? self : (typeof globalThis !== 'undefined' ? globalThis : this));
