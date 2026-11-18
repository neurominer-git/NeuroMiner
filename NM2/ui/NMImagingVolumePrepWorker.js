/*
 * NMImagingVolumePrepWorker — off-main-thread imaging-volume preparation.
 *
 * Message in:  { requestId, generation, task, input }
 *   task 'structural' | 'nativeFeature' | 'coverage' | 'featureBundle' |
 *        'localSupportEnhancement' | 'roiRows'
 *   'featureBundle' prepares the native grid and the coverage field together,
 *   which is what a threshold or smoothing change needs.
 *
 * Message out: { ok, requestId, generation, task, result, timings } with all typed-array buffers
 * transferred rather than copied.
 */
'use strict';
self.window=self;
importScripts('NMResultsViewerPrimitives.js','NMImagingDisplaySemantics.js','NMImagingVolumePrep.js','NMImagingFeatureSampling.js','NMImagingRoiRows.js');

function collectBuffers(result) {
  const transfer = [];
  const seen = new Set();
  const visit = value => {
    if (!value || typeof value !== 'object') return;
    if (ArrayBuffer.isView(value)) {
      if (!seen.has(value.buffer)) { seen.add(value.buffer); transfer.push(value.buffer); }
      return;
    }
    if (Array.isArray(value)) { value.forEach(visit); return; }
    Object.keys(value).forEach(key => visit(value[key]));
  };
  visit(result);
  return transfer;
}

function nowMs() { return self.performance && typeof self.performance.now === 'function' ? self.performance.now() : Date.now(); }

self.onmessage = function (event) {
  const message = event.data || {};
  const startedAt = nowMs();
  const task = String(message.task || '');
  const input = message.input || {};
  try {
    let result = null;
    if (task === 'ping') {
      self.postMessage({ ok: true, requestId: message.requestId, generation: message.generation, task, result: null, timings: { workerPreparationMs: 0, outputBytes: 0 } });
      return;
    } else if (task === 'structural') {
      result = self.NMImagingVolumePrep.prepareStructural(input);
    } else if (task === 'nativeFeature') {
      result = self.NMImagingVolumePrep.prepareNativeFeature(input);
    } else if (task === 'coverage') {
      result = self.NMImagingVolumePrep.prepareCoverage(input);
    } else if (task === 'featureBundle') {
      result = {
        native: self.NMImagingVolumePrep.prepareNativeFeature(input),
        coverage: self.NMImagingVolumePrep.prepareCoverage(input)
      };
    } else if (task === 'localSupportEnhancement') {
      result = self.NMImagingVolumePrep.prepareLocalSupportEnhancement(input);
    } else if (task === 'roiRows') {
      result = self.NMImagingRoiRows.compute(input);
    } else {
      throw new Error(`Unknown volume preparation task "${task}".`);
    }
    const transfer = collectBuffers(result);
    const outputBytes = transfer.reduce((sum, buffer) => sum + buffer.byteLength, 0);
    self.postMessage({ ok: true, requestId: message.requestId, generation: message.generation, task, result, timings: { workerPreparationMs: nowMs() - startedAt, outputBytes } }, transfer);
  } catch (error) {
    self.postMessage({
      ok: false, requestId: message.requestId, generation: message.generation, task,
      message: (error && error.message) || String(error)
    });
  }
};
