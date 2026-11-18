/* NMTrainTemplateUI_main.js
 * Browser-side controller for the NeuroMiner training-template UI.
 * Extracted from NMTrainTemplateUI.m to keep MATLAB code auditable.
 */

const PARAMS = new URLSearchParams(location.search);
const PORT = PARAMS.get("port") || "4821";
let STATE = window.NM_MENU_STATE || {};
const NM_UI_CLIENT_PROFILE = ["1", "true", "on", "yes"].includes(
  String(PARAMS.get("profile") || "").toLowerCase(),
);
const NM_UI_CLIENT_T0 =
  typeof performance !== "undefined" && performance.now
    ? performance.now()
    : Date.now();
/**
 * nmClientNow  Provide the nm client now helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function nmClientNow() {
  return typeof performance !== "undefined" && performance.now
    ? performance.now()
    : Date.now();
}
/**
 * nmClientProfileLog  Provide the nm client profile log helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function nmClientProfileLog(msg) {
  if (!NM_UI_CLIENT_PROFILE) return;
  console.log(`[nm-client-prof] ${msg}`);
}
/**
 * nmClientProfileDelta  Provide the nm client profile delta helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function nmClientProfileDelta(t0) {
  return ((nmClientNow() - t0) / 1000).toFixed(3);
}
let NM_UI_PROFILE_SEQ = 0;
function nmClientProfileId(label) {
  NM_UI_PROFILE_SEQ += 1;
  return `${String(label || "action").replace(/[^A-Za-z0-9_-]/g, "_")}_${Date.now()}_${NM_UI_PROFILE_SEQ}`;
}
function nmClientProfileActionLog(rid, msg) {
  if (!NM_UI_CLIENT_PROFILE) return;
  console.log(`[nm-client-prof rid=${rid || "-"}] ${msg}`);
}
async function nmProfiledMatlabService(payload, label) {
  let req = payload && typeof payload === "object" ? Object.assign({}, payload) : {};
  const rid = req.profileId || (NM_UI_CLIENT_PROFILE ? nmClientProfileId(label || req.operation || "matlabservice") : "");
  const startEpoch = Date.now();
  if (NM_UI_CLIENT_PROFILE) {
    req.profile = true;
    req.profileId = rid;
  }
  const t0 = nmClientNow();
  const tSerialize = nmClientNow();
  const body = JSON.stringify(req);
  const serializeSeconds = (nmClientNow() - tSerialize) / 1000;
  const tFetch = nmClientNow();
  const response = await fetch(API("/api/matlabservice"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
  });
  const fetchHeadersSeconds = (nmClientNow() - tFetch) / 1000;
  const tRead = nmClientNow();
  const text = await response.text();
  const bodyReadSeconds = (nmClientNow() - tRead) / 1000;
  const tParse = nmClientNow();
  let out = {};
  try {
    out = JSON.parse(text || "{}");
  } catch (e) {
    throw new Error(`MATLAB bridge returned invalid JSON: ${e.message}; response length=${text.length}`);
  }
  const parseSeconds = (nmClientNow() - tParse) / 1000;
  if (out && typeof out === "object") {
    if (out.ok !== false && Object.prototype.hasOwnProperty.call(out,"readinessDiagnostic"))
      STATE.readinessDiagnostic = out.readinessDiagnostic;
    out.__nmClientProfileId = rid;
    out.__nmClientProfileStartEpoch = startEpoch;
    out.__nmClientProfileStartPerf = t0;
  }
  if (NM_UI_CLIENT_PROFILE) {
    const b = out && out._nmProfileBridge;
    const bridge = b
      ? ` bridge(inboundRead=${Number(b.inboundReadSeconds || 0).toFixed(3)}s inboundDecode=${Number(b.inboundDecodeSeconds || 0).toFixed(3)}s requestPersist=${Number(b.requestPersistSeconds || 0).toFixed(3)}s waitMATLAB=${Number(b.waitMATLABSeconds || 0).toFixed(3)}s resultRead=${Number(b.resultReadSeconds || 0).toFixed(3)}s)`
      : "";
    nmClientProfileActionLog(
      rid,
      `${label || req.operation || "matlabservice"} serialize=${serializeSeconds.toFixed(3)}s fetchHeaders=${fetchHeadersSeconds.toFixed(3)}s bodyRead=${bodyReadSeconds.toFixed(3)}s parse=${parseSeconds.toFixed(3)}s total=${((nmClientNow() - t0) / 1000).toFixed(3)}s${bridge}`,
    );
  }
  return out;
}
const NM_UI_NAV_PROFILE_ID = PARAMS.get("nmprofid") || "";
const NM_UI_NAV_PROFILE_START = Number(PARAMS.get("nmprofstart") || 0);
if (NM_UI_CLIENT_PROFILE && NM_UI_NAV_PROFILE_ID && NM_UI_NAV_PROFILE_START) {
  window.addEventListener("DOMContentLoaded", () =>
    nmClientProfileActionLog(
      NM_UI_NAV_PROFILE_ID,
      `template DOMContentLoaded ${((Date.now() - NM_UI_NAV_PROFILE_START) / 1000).toFixed(3)}s after workbench navigation start`,
    ),
  );
  window.addEventListener("load", () =>
    nmClientProfileActionLog(
      NM_UI_NAV_PROFILE_ID,
      `template window load ${((Date.now() - NM_UI_NAV_PROFILE_START) / 1000).toFixed(3)}s after workbench navigation start`,
    ),
  );
}
nmClientProfileLog(
  `script loaded after ${nmClientProfileDelta(NM_UI_CLIENT_T0)}s; modalities=${
    Array.isArray(STATE.modalityLabels) ? STATE.modalityLabels.length : "unknown"
  }`,
);
if (typeof window !== "undefined") {
  window.addEventListener("DOMContentLoaded", () =>
    nmClientProfileLog(
      `DOMContentLoaded at ${nmClientProfileDelta(NM_UI_CLIENT_T0)}s`,
    ),
  );
  window.addEventListener("load", () =>
    nmClientProfileLog(`window load at ${nmClientProfileDelta(NM_UI_CLIENT_T0)}s`),
  );
}
let activeEditor = null;
let activeEditorModule = "";
let selectedCanvasNodeId = null;
let NM2_NAV_REVISION = 0;
let NM2_RECOVERY_NAV = null;
const NM2_RESTORE_ENTRY = PARAMS.get("recovery") === "1" || PARAMS.get("reopen") === "1";
let editorReturnViewMode = null;
let canvasOpenContext = null;
let canvasRefreshTimer = null;
let canvasRefreshInFlight = false;
let menuSyncTimer = null;
let menuSyncInFlight = false;
let menuSyncPending = false;
let lastMenuSyncKey = "";
const MENU_CHANGED_PATHS = new Set();
function markMenuChanged(...paths) {
  paths.flat().forEach((p) => { if (p) MENU_CHANGED_PATHS.add(String(p)); });
}
function pendingMenuChangedPaths() {
  return Array.from(MENU_CHANGED_PATHS);
}
function clearMenuChangedPaths(paths) {
  (paths || []).forEach((p) => MENU_CHANGED_PATHS.delete(String(p)));
}
function serviceChangedPaths(root) {
  let paths = pendingMenuChangedPaths();
  if (root) paths.push(String(root));
  return Array.from(new Set(paths));
}
function acceptServiceChangedPaths(paths) {
  clearMenuChangedPaths(paths);
  lastAppliedMenuContextKey = menuContextKeyFromPayload(menuContextState());
}
let lastAppliedMenuContextKey = "";
let lastAppliedCanvasContextKey = "";
let canvasDetailInFlight = {};
let canvasInspectorCollapsed = false;
let canvasInfoPopoverNodeId = "";
/**
 * API  Build an absolute local HTTP bridge URL for a browser request.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
const API = (p) => {
  const url = `http://127.0.0.1:${PORT}${p}${p.indexOf("?") >= 0 ? "&" : "?"}module=menu`;
  return window.NMBridgeAuthenticatedURL ? window.NMBridgeAuthenticatedURL(url) : url;
};

function configuratorSlotAPI(module, path) {
  const p = path || "/api/current";
  const sep = p.indexOf("?") >= 0 ? "&" : "?";
  const url = `http://127.0.0.1:${PORT}${p}${sep}module=${encodeURIComponent(String(module || ""))}`;
  return window.NMBridgeAuthenticatedURL ? window.NMBridgeAuthenticatedURL(url) : url;
}

async function persistConfiguratorChildState(module, state, profileId) {
  if (!module || !state || typeof state !== "object") throw new Error("Configurator child STATE requires a module and object state.");
  const t0 = nmClientNow();
  const tSerialize = nmClientNow();
  const body = JSON.stringify(state);
  const serializeSeconds = (nmClientNow() - tSerialize) / 1000;
  const tFetch = nmClientNow();
  const res = await fetch(configuratorSlotAPI(module), {
    method: "POST", headers: { "Content-Type": "application/json" }, body,
  });
  const fetchHeadersSeconds = (nmClientNow() - tFetch) / 1000;
  const tRead = nmClientNow();
  const responseText = await res.text();
  const bodyReadSeconds = (nmClientNow() - tRead) / 1000;
  const tParse = nmClientNow();
  let out = {};
  try {
    out = JSON.parse(responseText || "{}");
  } catch (e) {
    throw new Error(`Configurator child STATE write returned invalid JSON: ${e.message}`);
  }
  const parseSeconds = (nmClientNow() - tParse) / 1000;
  if (!res.ok || out.ok === false) throw new Error(out.message || `Configurator child STATE write failed: HTTP ${res.status}`);
  nmClientProfileActionLog(
    profileId,
    `child STATE persist module=${module} serialize=${serializeSeconds.toFixed(3)}s fetchHeaders=${fetchHeadersSeconds.toFixed(3)}s bodyRead=${bodyReadSeconds.toFixed(3)}s parse=${parseSeconds.toFixed(3)}s total=${((nmClientNow()-t0)/1000).toFixed(3)}s`,
  );
  return out;
}

async function clearConfiguratorChildrenState() {
  const res = await fetch(API("/api/configuratorchildren/clear"), {
    method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok || out.ok === false) throw new Error(out.message || `Configurator child STATE clear failed: HTTP ${res.status}`);
  return out;
}

function nextTemplateNavigationRevision() {
  const now = Math.floor(Date.now() * 1000);
  NM2_NAV_REVISION = Math.max(NM2_NAV_REVISION + 1, now);
  return NM2_NAV_REVISION;
}

function templateNavigationState(extra) {
  const c = appContext();
  const state = {
    moduleKey: "template",
    subview: activeEditor || currentViewMode(),
    uiViewMode: currentViewMode(),
    editorKind: activeEditor || "",
    editorModule: activeEditorModule || "",
    editorReturnViewMode: editorReturnViewMode || "",
    returnToWorkbench: !!c.returnToWorkbench,
    returnPage: String(c.returnPage || "nm_workbench.html"),
  };
  return Object.assign(state, extra || {});
}

async function persistTemplateNavigation(extra) {
  const revision = nextTemplateNavigationRevision();
  const res = await fetch(API("/api/nm2state"), {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ section: "navigation", revision, state: templateNavigationState(extra) }),
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok && !(out && out.stale)) throw new Error(out.message || `Navigation position could not be saved: HTTP ${res.status}`);
  if (out && out.stale && Number(out.currentRevision || 0) > NM2_NAV_REVISION) NM2_NAV_REVISION = Number(out.currentRevision || 0);
  return out;
}

async function loadTemplateNavigation() {
  const res = await fetch(API("/api/nm2state?section=navigation"), { cache: "no-store" });
  if (!res.ok) return null;
  const out = await res.json();
  NM2_NAV_REVISION = Math.max(NM2_NAV_REVISION, Number(out.revision || 0));
  return out && out.state && typeof out.state === "object" ? out.state : null;
}

async function loadConfiguratorMenuState() {
  const runtimeAppContext = STATE && STATE.appContext ? STATE.appContext : null;
  const res = await fetch(API("/api/state"), { cache: "no-store" });
  if (!res.ok) throw new Error(`Configurator menu STATE load failed: HTTP ${res.status}`);
  const saved = await res.json();
  if (!saved || typeof saved !== "object") throw new Error("Configurator menu STATE is not an object.");
  STATE = saved;
  if (runtimeAppContext) STATE.appContext = runtimeAppContext;
  return STATE;
}
/**
 * appContext  Build the app context shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function appContext() { return (STATE && STATE.appContext) || {}; }
/**
 * isWorkbenchChild  Return whether the is workbench child condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isWorkbenchChild() {
  const c = appContext();
  return !!c.returnToWorkbench || String(c.caller || '').toLowerCase() === 'workbench';
}
/**
 * workbenchReturnUrl  Provide the workbench return url helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function workbenchReturnUrl(profileId, startEpoch) {
  const c = appContext();
  const page = c.returnPage || 'nm_workbench.html';
  const sep = page.includes('?') ? '&' : '?';
  let url = page.includes('?') ? page : `${page}?port=${encodeURIComponent(PORT)}`;
  if (NM_UI_CLIENT_PROFILE) {
    url += `${url.includes('?') ? '&' : '?'}profile=1&nmprofid=${encodeURIComponent(profileId || '')}&nmprofstart=${encodeURIComponent(startEpoch || Date.now())}`;
  }
  return url;
}
/**
 * appChildReturn  Provide the app child return helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function appChildReturn(source) {
  return nmProfiledMatlabService(
    { operation: 'app_child_return', source: source || 'template', state: STATE, timeout: 240 },
    'app_child_return',
  );
}
/**
 * rememberReturnView  Provide the remember return view helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function rememberReturnView() {
  editorReturnViewMode = editorReturnViewMode || currentViewMode();
  return editorReturnViewMode;
}
/**
 * acceptReturnedState  Provide the accept returned state helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function acceptReturnedState(s) {
  let keep = STATE && STATE.uiViewMode;
  let orient = STATE && STATE.canvasFlowOrientation;
  let oldCanvas = STATE && STATE.canvas;
  let appCtx = STATE && STATE.appContext;
  let readiness = STATE && STATE.readinessDiagnostic;
  if (s && typeof s === "object") {
    STATE = s;
    if (STATE.readinessDiagnostic === undefined) STATE.readinessDiagnostic = readiness;
    if (appCtx && (!STATE.appContext || !Object.keys(STATE.appContext || {}).length)) STATE.appContext = appCtx;
    if (keep) STATE.uiViewMode = keep;
    if (orient) STATE.canvasFlowOrientation = orient;
    let incomingNodes = STATE.canvas && Array.isArray(STATE.canvas.nodes) ? STATE.canvas.nodes.length : 0;
    let oldNodes = oldCanvas && Array.isArray(oldCanvas.nodes) ? oldCanvas.nodes.length : 0;
    if ((STATE.canvasDirty || incomingNodes === 0) && oldNodes > 0) {
      STATE.canvas = oldCanvas;
      STATE.canvasDirty = true;
      STATE.canvasDirtyReason = STATE.canvasDirtyReason || "Canvas refresh is pending.";
    }
  }
  return STATE;
}
/**
 * setActiveEditorFromChild  Provide the set active editor from child helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setActiveEditorFromChild(v) {
  if (v) {
    rememberReturnView();
    activeEditor = v;
    if (v !== "preproc" && v !== "ml") activeEditorModule = "";
    persistTemplateNavigation().catch((e) => status("Navigation position could not be saved: " + e.message, "info"));
    return;
  }
  let rv = editorReturnViewMode || currentViewMode();
  activeEditor = null;
  activeEditorModule = "";
  if (rv) STATE.uiViewMode = rv;
  editorReturnViewMode = null;
  persistTemplateNavigation({ subview: rv || "menu", editorKind: "", editorModule: "", editorReturnViewMode: "" })
    .catch((e) => status("Navigation position could not be saved: " + e.message, "info"));
}
/**
 * finishInlineConfigurator  Provide the finish inline configurator helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function finishInlineConfigurator(modalId) {
  let rv = editorReturnViewMode || currentViewMode();
  let el = document.getElementById(modalId);
  if (el) el.classList.remove("open");
  activeEditor = null;
  activeEditorModule = "";
  if (rv) STATE.uiViewMode = rv;
  render();
  syncMenu();
  persistTemplateNavigation({ subview: rv || "menu", editorKind: "", editorModule: "", editorReturnViewMode: "" })
    .catch((e) => status("Navigation position could not be saved: " + e.message, "info"));
  editorReturnViewMode = null;
}
/**
 * arr  Normalize a nullable scalar or array-like value to an array.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function arr(x) {
  return Array.isArray(x) ? x : x === undefined || x === null ? [] : [x];
}
/**
 * status  Provide the status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function status(s, cls) {
  window.NMUIMessageTools.setMessage(s, cls || "info");
}
/**
 * editorStatus  Provide the editor status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function editorStatus(s, cls) {
  window.NMUIMessageTools.setMessage(s, cls || "info");
}
/**
 * cvStatus  Provide the cv status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvStatus(s, cls) {
  window.NMUIMessageTools.setMessage(s, cls, "nm-cv");
}
/**
 * altStatus  Provide the alt status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function altStatus(s, cls) {
  window.NMUIMessageTools.setMessage(s, cls, "nm-altlabel");
}
/**
 * stackingStatus  Provide the stacking status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingStatus(s, cls) {
  status(s, cls);
}
/**
 * synthStatus  Provide the synth status helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function synthStatus(s, cls) {
  status(s, cls);
}
/**
 * CV  Provide the cv helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function CV() {
  if (!STATE.cv || typeof STATE.cv !== "object") STATE.cv = {};
  return STATE.cv;
}
/**
 * Synth  Provide the synth helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function Synth() {
  if (!STATE.synth || typeof STATE.synth !== "object") STATE.synth = {};
  return STATE.synth;
}
/**
 * cvCandidates  Provide the cv candidates helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvCandidates() {
  return arr(CV().cvVectorCandidates);
}
/**
 * cvMode  Provide the cv mode helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvMode() {
  return String(
    CV().cvModeFlag ||
      STATE.altLabelMode ||
      "classification",
  ).toLowerCase();
}
/**
 * cvRegression  Provide the cv regression helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvRegression() {
  return cvMode() === "regression";
}
/**
 * cvMulticlass  Provide the cv multiclass helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvMulticlass() {
  return !!CV().cvIsMulticlass;
}
/**
 * cvLOO  Provide the cv loo helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvLOO() {
  let c = CV();
  return (
    String(c.cvOuterMode || "").toLowerCase() === "loo" ||
    String(c.cvInnerMode || "").toLowerCase() === "loo"
  );
}
/**
 * altCandidates  Provide the alt candidates helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function altCandidates() {
  return arr(STATE.altLabelCandidates);
}
/**
 * altEnabled  Provide the alt enabled helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function altEnabled() {
  return !!STATE.altLabelEnabled;
}
/**
 * multiLabelSelection  Return the currently selected NM.label columns.
 */
function multiLabelSelection() {
  return arr(STATE.multiLabelSelection)
    .map(Number)
    .filter((x) => Number.isFinite(x) && x >= 1);
}
/**
 * multiLabelLabels  Return the browser labels for NM.label columns.
 */
function multiLabelLabels() {
  return arr(STATE.multiLabelLabels).map((x) => String(x));
}
/**
 * selectedAltCandidate  Apply the ed alt candidate selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedAltCandidate() {
  let n = String(STATE.altLabelSourceVar || "");
  return altCandidates().find((c) => String(c.name || "") === n) || null;
}
/**
 * inferAltMode  Provide the infer alt mode helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function inferAltMode(c) {
  if (!c)
    return STATE.altLabelMode || "classification";
  let h = String(c.taskHint || "").toLowerCase();
  let nu = Number(c.nUniqueNonMissing || 0);
  if (h === "regression" || nu > 2) return "regression";
  return "classification";
}
/**
 * altGroupText  Build the alt group text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function altGroupText() {
  return arr(STATE.altLabelGroupNames).join(", ");
}
/**
 * synthSummaryText  Build the synth summary text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function synthSummaryText() {
  let s = Synth();
  if (!s.synthEnabled) return "Synthetic data generation disabled.";
  let names = ["kNN-based", "ADASYN", "PCAGauss", "Gaussian mixture model", "Gaussian copula"];
  let m = Number(s.synthMethod || 1);
  let text = `Enabled: ${names[m - 1] || "synthetic"} synthetic data generation.`;
  if (s.synthUncertaintyScale > 0)
    text += ` Population uncertainty scale: ${s.synthUncertaintyScale}.`;
  return text;
}
/**
 * labels  Provide the labels helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function labels() {
  return arr(STATE.modalityLabels).length
    ? arr(STATE.modalityLabels)
    : Array.from(
        { length: Number(STATE.numModalities || 1) },
        (_, i) => `Modality #${i + 1}`,
      );
}
/**
 * nmod  Provide the nmod helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function nmod() {
  return Math.max(1, Number(STATE.numModalities || labels().length || 1));
}
/**
 * isStacking  Return whether the is stacking condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function isStacking() {
  return Number(STATE.stackingFlag || 2) === 1;
}
/**
 * stackingVisible  Provide the stacking visible helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingVisible() {
  return (
    isStacking() ||
    !!STATE.stackingAvailable ||
    stackingCandidateAvailable().filter(Boolean).length >= 2
  );
}
/**
 * menuSyncKey  Resolve the menu sync key identifier used to connect UI state with NeuroMiner payload metadata.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function menuSyncKey() {
  try {
    return JSON.stringify(STATE);
  } catch (e) {
    return String(Date.now());
  }
}
/**
 * syncMenuNow  Synchronize the menu now browser state with related controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
function syncMenuNow(force) {
  let key = force ? "" : menuSyncKey();
  if (!force && key && key === lastMenuSyncKey) return Promise.resolve({ skipped: true });
  if (menuSyncInFlight) {
    menuSyncPending = true;
    return Promise.resolve({ queued: true });
  }
  menuSyncInFlight = true;
  if (key) lastMenuSyncKey = key;
  return fetch(API("/api/current"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(STATE),
  })
    .catch(() => {})
    .finally(() => {
      menuSyncInFlight = false;
      if (menuSyncPending) {
        menuSyncPending = false;
        syncMenu(true);
      }
    });
}
/**
 * syncMenu  Synchronize the menu browser state with related controls.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function syncMenu(force) {
  if (force) {
    if (menuSyncTimer) {
      clearTimeout(menuSyncTimer);
      menuSyncTimer = null;
    }
    return syncMenuNow(true);
  }
  if (menuSyncTimer) clearTimeout(menuSyncTimer);
  menuSyncTimer = setTimeout(() => {
    menuSyncTimer = null;
    syncMenuNow(false);
  }, 80);
  return Promise.resolve({ scheduled: true });
}
/**
 * flushMenuSync  Provide the flush menu sync helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function flushMenuSync() {
  if (menuSyncTimer) {
    clearTimeout(menuSyncTimer);
    menuSyncTimer = null;
  }
  while (menuSyncInFlight) await new Promise((resolve) => setTimeout(resolve, 5));
  return syncMenuNow(true);
}
document.addEventListener("change", () => { syncMenu(true); });
document.addEventListener("focusout", () => { syncMenu(true); });
/**
 * menuContextState  Provide the menu context state helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function menuContextState() {
  return {
    uiViewMode: currentViewMode(),
    canvasFlowOrientation: STATE.canvasFlowOrientation || "horizontal",
    activeModality: STATE.activeModality,
    fusionFlag: STATE.fusionFlag,
    fusionModalities: STATE.fusionModalities,
    stackingFlag: STATE.stackingFlag,
    stackingEnabled: isStacking(),
    stackingSelectedAnalyses: STATE.stackingSelectedAnalyses,
    stackingFeatureNameMode: STATE.stackingFeatureNameMode,
    stackingFeatureNameVariable: STATE.stackingFeatureNameVariable,
    stackingPredictionMode: STATE.stackingPredictionMode,
    altLabelEnabled: STATE.altLabelEnabled,
    altLabelMode: STATE.altLabelMode,
    altLabelSourceVar: STATE.altLabelSourceVar,
    altLabelName: STATE.altLabelName,
    altLabelGroupNames: STATE.altLabelGroupNames,
    multiLabelSelection: STATE.multiLabelSelection,
  };
}
/**
 * menuContextKeyFromPayload  Provide the menu context key from payload helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function menuContextKeyFromPayload(payloadState) {
  try {
    return JSON.stringify(payloadState || {});
  } catch (e) {
    return String(Date.now());
  }
}
/**
 * canvasModelIsCurrentForKey  Return whether the canvas model is current for key condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasModelIsCurrentForKey(key) {
  let c = STATE.canvas || {};
  let hasNodes = Array.isArray(c.nodes) && c.nodes.length > 0;
  return hasNodes && !STATE.canvasDirty && key && key === lastAppliedCanvasContextKey;
}
/**
 * initMenuContextKeysFromState  Provide the init menu context keys from state helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function initMenuContextKeysFromState() {
  let key = menuContextKeyFromPayload(menuContextState());
  lastAppliedMenuContextKey = key;
  let c = STATE.canvas || {};
  if (Array.isArray(c.nodes) && c.nodes.length > 0 && !STATE.canvasDirty) {
    lastAppliedCanvasContextKey = key;
  }
}
/**
 * applyMenuContext  Apply the menu context change to local browser state or visible controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * options.force: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 * options.fullState: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 * options.includeCanvas: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function applyMenuContext(options) {
  options = options || {};
  let keepMode = currentViewMode();
  let includeCanvas = options.includeCanvas !== undefined ? !!options.includeCanvas : keepMode === "canvas";
  let payloadState = options.fullState ? STATE : menuContextState();
  let changedPaths = pendingMenuChangedPaths();
  let contextKey = options.fullState ? "" : menuContextKeyFromPayload(payloadState);
  if (!options.force && !options.fullState && contextKey) {
    let menuCurrent = contextKey === lastAppliedMenuContextKey;
    let canvasCurrent = !includeCanvas || canvasModelIsCurrentForKey(contextKey);
    if (menuCurrent && canvasCurrent) {
      clearMenuChangedPaths(pendingMenuChangedPaths());
      if (keepMode) STATE.uiViewMode = keepMode;
      render();
      return { ok: true, skipped: true, reason: "menu context unchanged" };
    }
  }
  await flushMenuSync();
  let res = await nmProfiledMatlabService(
    {
      operation: "train_template_apply_menu",
      state: payloadState,
      stateScope: options.fullState ? "full" : "menuContext",
      changedPaths: changedPaths,
      includeCanvas: includeCanvas,
      timeout: 120,
    },
    "train_template_apply_menu",
  );
  if (!res || res.ok === false || res.error) {
    throw new Error((res && res.message) || "Menu-context apply failed");
  }
  if (res.state) acceptReturnedState(res.state);
  clearMenuChangedPaths(changedPaths);
  if (res.resetConfiguratorChildren) await clearConfiguratorChildrenState();
  if (contextKey) {
    lastAppliedMenuContextKey = contextKey;
    let c = STATE.canvas || {};
    if (includeCanvas && Array.isArray(c.nodes) && c.nodes.length > 0 && !STATE.canvasDirty) {
      lastAppliedCanvasContextKey = contextKey;
    }
  }
  if (keepMode) STATE.uiViewMode = keepMode;
  render();
  nmClientProfileActionLog(
    res && res.__nmClientProfileId,
    `menu action UI-ready total=${res && res.__nmClientProfileStartPerf != null ? ((nmClientNow()-res.__nmClientProfileStartPerf)/1000).toFixed(3) : "n/a"}s`,
  );
  return res;
}
/**
 * canvasRefreshShouldBeDeferred  Return whether the canvas refresh should be deferred condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasRefreshShouldBeDeferred() {
  return (editorReturnViewMode || currentViewMode()) === "canvas";
}
/**
 * markCanvasDirty  Provide the mark canvas dirty helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function markCanvasDirty(reason) {
  if (!STATE) return;
  STATE.canvasDirty = true;
  STATE.canvasDirtyReason = reason || STATE.canvasDirtyReason || "Canvas refresh is pending.";
}
/**
 * scheduleCanvasRefresh  Provide the schedule canvas refresh helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function scheduleCanvasRefresh(delayMs) {
  if (currentViewMode() !== "canvas") return;
  if (canvasRefreshTimer) clearTimeout(canvasRefreshTimer);
  canvasRefreshTimer = setTimeout(() => {
    canvasRefreshTimer = null;
    refreshCanvasState();
  }, Number(delayMs || 120));
}
/**
 * refreshCanvasState  Refresh the canvas state page region after state or artifact availability changes.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function refreshCanvasState() {
  if (canvasRefreshInFlight) return;
  canvasRefreshInFlight = true;
  try {
    await applyMenuContext({ includeCanvas: true, fullState: false });
    STATE.canvasDirty = false;
    STATE.canvasDirtyReason = "";
    render();
  } catch (e) {
    status("Canvas refresh failed: " + e.message, "warn");
  } finally {
    canvasRefreshInFlight = false;
  }
}
/**
 * applyEmbeddedPreproc  Apply the embedded preproc change to local browser state or visible controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function applyEmbeddedPreproc(module, childChangedPaths) {
  let changedPaths = pendingMenuChangedPaths();
  let payload = {
    operation: "train_template_apply_preproc",
    state: STATE,
    module: module || "",
    changedPaths: changedPaths,
    includeCanvas: !canvasRefreshShouldBeDeferred(),
    timeout: 600,
  };
  if (Array.isArray(childChangedPaths)) payload.childChangedPaths = childChangedPaths;
  let res = await nmProfiledMatlabService(payload, "train_template_apply_preproc");
  if (res && res.requiresConfirmation) {
    if (!window.confirm(res.reason)) return { cancelled: true };
    payload.confirmPFEDeactivation = true;
    res = await nmProfiledMatlabService(payload, "train_template_apply_preproc");
  }
  if (!res || res.ok === false || res.error) {
    throw new Error((res && res.message) || "Preprocessing apply failed");
  }
  const tAccept = nmClientNow();
  if (res.state) acceptReturnedState(res.state);
  clearMenuChangedPaths(changedPaths);
  nmClientProfileActionLog(
    res.__nmClientProfileId,
    `preproc browser state accept=${((nmClientNow() - tAccept) / 1000).toFixed(3)}s`,
  );
  return res;
}
/**
 * applyEmbeddedML  Apply the embedded ml change to local browser state or visible controls.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function applyEmbeddedML(module, childChangedPaths) {
  let changedPaths = pendingMenuChangedPaths();
  let payload = {
    operation: "train_template_apply_ml",
    state: STATE,
    module: module || "",
    changedPaths: changedPaths,
    includeCanvas: !canvasRefreshShouldBeDeferred(),
    timeout: 600,
  };
  if (Array.isArray(childChangedPaths)) payload.childChangedPaths = childChangedPaths;
  let res = await nmProfiledMatlabService(payload, "train_template_apply_ml");
  if (!res || res.ok === false || res.error) {
    throw new Error((res && res.message) || "ML apply failed");
  }
  const tAccept = nmClientNow();
  if (res.state) acceptReturnedState(res.state);
  clearMenuChangedPaths(changedPaths);
  nmClientProfileActionLog(
    res.__nmClientProfileId,
    `ML browser state accept=${((nmClientNow() - tAccept) / 1000).toFixed(3)}s`,
  );
  return res;
}
/**
 * exportTrainScaffold  Provide the export train scaffold helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function exportTrainScaffold() {
  try {
    if (activeEditor) {
      status(
        "Close the active configurator before exporting the training-template scaffold.",
        "warn",
      );
      return;
    }
    await applyMenuContext();
    setStatusSafe(
      "A MATLAB folder chooser is opening. It may appear behind this browser window; check MATLAB or the taskbar if you do not see it.",
      "info",
    );
    status(
      "A MATLAB folder chooser is opening. It may appear behind this browser window; check MATLAB or the taskbar if you do not see it.",
      "info",
    );
    let pick = await fetch(API("/api/pickpath"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "directory",
        multiple: false,
        initial: "",
        timeout: 240,
      }),
    }).then((r) => r.json());
    if (pick && pick.error) throw new Error(pick.message ? pick.message : pick.error);
    let paths = arr(pick && pick.paths).filter((x) => String(x || "").trim());
    if (!paths.length) {
      status(
        "Scaffold export cancelled. No export folder was selected.",
        "info",
      );
      return;
    }
    let exportRoot = paths[0];
    status(
      "Exporting training-template scaffold. Please wait...",
      "info",
    );
    let res = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_export_scaffold",
        state: STATE,
        exportRoot: exportRoot,
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error(
        (res && res.message) || "Unknown scaffold export failure",
      );
    if (res.state) acceptReturnedState(res.state);
    let msg = res.message || "Training-template scaffold exported.";
    if (res.exportDir) msg += "\nExport folder: " + res.exportDir;
    if (res.files && res.files.length)
      msg += "\nFiles: " + res.files.join(", ");
    if (res.auditSummary && res.auditSummary.displayText)
      msg += "\n" + res.auditSummary.displayText;
    render();
    status(msg, "ok");
  } catch (e) {
    status("Training-template scaffold export failed: " + e.message, "danger");
  }
}
/**
 * saveTrainTemplate  Provide the save train template helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function saveTrainTemplate() {
  try {
    if (activeEditor) {
      status(
        "Close the active configurator before saving a template snapshot.",
        "warn",
      );
      return;
    }
    await applyMenuContext();
    status("Select a folder for the training-template snapshot.", "info");
    let pick = await fetch(API("/api/pickpath"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "directory",
        multiple: false,
        initial: "",
        timeout: 240,
      }),
    }).then((r) => r.json());
    if (pick && pick.error) throw new Error(pick.message ? pick.message : pick.error);
    let paths = arr(pick && pick.paths).filter((x) => String(x || "").trim());
    if (!paths.length) {
      return;
    }
    let res = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_save_snapshot",
        state: STATE,
        exportRoot: paths[0],
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error((res && res.message) || "Snapshot save failed");
    if (res.state) acceptReturnedState(res.state);
    render();
    status(
      (res.message || "Training template snapshot saved.") +
        "\n" +
        (res.file || ""),
      "ok",
    );
  } catch (e) {
    status("Training-template snapshot save failed: " + e.message, "danger");
  }
}
/**
 * previewText  Build the preview text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function previewText(p) {
  let lines = [];
  lines.push("Source: " + (p.sourceFile || "?"));
  lines.push("Timestamp: " + (p.timestamp || "?"));
  lines.push(
    "Modality compatibility: " + (p.modalityCompatibility || "unknown"),
  );
  lines.push("Highest severity: " + (p.highestSeverity || "unknown"));
  lines.push(
    `Items: ${p.nErrors || 0} error(s), ${p.nWarnings || 0} warning(s), ${p.nInfo || 0} info`,
  );
  lines.push("Category: " + (p.category || "unknown/manual review"));
  let msgs = arr(p.topMessages).slice(0, 5);
  if (msgs.length) {
    lines.push("Top messages:");
    msgs.forEach((m) => lines.push("- " + m));
  }
  return lines.join("\n");
}
/**
 * loadTrainTemplate  Load train template data from injected state, local cache or the MATLAB bridge.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function loadTrainTemplate() {
  try {
    if (activeEditor) {
      status(
        "Close the active configurator before loading a template snapshot.",
        "warn",
      );
      return;
    }
    await applyMenuContext();
    status("Select a training-template snapshot MAT-file.", "info");
    let pick = await fetch(API("/api/pickpath"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "file",
        multiple: false,
        filter: "*.mat",
        initial: "",
        timeout: 240,
      }),
    }).then((r) => r.json());
    if (pick && pick.error) throw new Error(pick.message ? pick.message : pick.error);
    let paths = arr(pick && pick.paths).filter((x) => String(x || "").trim());
    if (!paths.length) {
      return;
    }
    let file = paths[0];
    let pre = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_load_snapshot_preview",
        filename: file,
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (pre && pre.error) throw new Error(pre.message ? pre.message : pre.error);
    if (!pre || pre.ok === false)
      throw new Error((pre && pre.message) || "Snapshot preview failed");
    let p = pre.preview || {};
    let txt = previewText(p);
    status(
      "Snapshot preview completed.\n" + txt,
      p.nErrors > 0 ? "danger" : p.nWarnings > 0 ? "warning" : "ok",
    );
    if (p.nErrors > 0) {
      return;
    }
    let ok = confirm("Apply this training-template snapshot?\n\n" + txt);
    if (!ok) {
      return;
    }
    let app = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_apply_snapshot",
        filename: file,
        confirmApply: true,
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (app && app.error) throw new Error(app.message ? app.message : app.error);
    if (!app || app.ok === false)
      throw new Error((app && app.message) || "Snapshot apply failed");
    if (app.state) acceptReturnedState(app.state);
    render();
    status(
      (app.message || "Snapshot applied.") +
        "\n" +
        (app.auditSummary && app.auditSummary.displayText
          ? app.auditSummary.displayText
          : ""),
      "ok",
    );
  } catch (e) {
    status("Training-template snapshot load failed: " + e.message, "danger");
  }
}
/**
 * exportMethodsSummary  Provide the export methods summary helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function exportMethodsSummary() {
  try {
    if (activeEditor) {
      status(
        "Close the active configurator before exporting the methods summary.",
        "warn",
      );
      return;
    }
    await applyMenuContext();
    status(
      "Choose a folder for the methods-summary export. The MATLAB folder chooser may appear behind the browser.",
      "info",
    );
    let pick = await fetch(API("/api/pickpath"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        kind: "directory",
        multiple: false,
        initial: "",
        timeout: 240,
      }),
    }).then((r) => r.json());
    if (pick && pick.error) throw new Error(pick.message ? pick.message : pick.error);
    let paths = arr(pick && pick.paths).filter((x) => String(x || "").trim());
    if (!paths.length) {
      status(
        "Methods-summary export cancelled. No folder was selected.",
        "info",
      );
      return;
    }
    let res = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_export_methods_summary",
        state: STATE,
        exportRoot: paths[0],
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error((res && res.message) || "Methods-summary export failed");
    if (res.state) acceptReturnedState(res.state);
    render();
    status(
      (res.message || "Methods/configuration summary exported.") +
        "\n" +
        (res.file || ""),
      "ok",
    );
  } catch (e) {
    status("Methods-summary export failed: " + e.message, "danger");
  }
}
/**
 * setStatusSafe  Provide the set status safe helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setStatusSafe(s, cls) {
  try {
    status(s, cls);
  } catch (e) {}
}
/**
 * applyFinishedEmbeddedEditor  Apply the finished embedded editor change to local browser state or visible controls.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 * data.module: browser-side field consumed from data while translating UI state to MATLAB-service requests.
 */
async function applyFinishedEmbeddedEditor(data) {
  let kind = activeEditor;
  let module = (data && data.module) || "";
  if (kind === "preproc") {
    let res = await applyEmbeddedPreproc(module, data && data.changedPaths);
    if (res && res.cancelled) return false;
    if (res && res.state && res.state.canvasDirty) {
      markCanvasDirty(res.state.canvasDirtyReason || "Preprocessing changed; canvas refresh pending.");
      scheduleCanvasRefresh(150);
    }
    render();
    nmClientProfileActionLog(
      res && res.__nmClientProfileId,
      `preproc child-return UI-ready total=${res && res.__nmClientProfileStartPerf != null ? ((nmClientNow()-res.__nmClientProfileStartPerf)/1000).toFixed(3) : "n/a"}s`,
    );
    return;
  }
  if (kind === "ml") {
    let res = await applyEmbeddedML(module, data && data.changedPaths);
    if (res && res.state && res.state.canvasDirty) {
      markCanvasDirty(res.state.canvasDirtyReason || "Machine-learning configuration changed; canvas refresh pending.");
      scheduleCanvasRefresh(150);
    }
    render();
    nmClientProfileActionLog(
      res && res.__nmClientProfileId,
      `ML child-return UI-ready total=${res && res.__nmClientProfileStartPerf != null ? ((nmClientNow()-res.__nmClientProfileStartPerf)/1000).toFixed(3) : "n/a"}s`,
    );
    return;
  }
}
/**
 * modalityIsImaging  Provide the modality is imaging helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function modalityIsImaging(i) {
  let a = arr(STATE.modalityIsImaging);
  return !!a[Number(i) - 1];
}
/**
 * selectedMixesImaging  Apply the ed mixes imaging selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedMixesImaging() {
  let ms = arr(STATE.fusionModalities).map(Number);
  if (ms.length < 2) return false;
  let vals = ms.map(modalityIsImaging);
  return vals.some(Boolean) && vals.some((v) => !v);
}
/**
 * nextModality  Provide the next modality helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function nextModality(v) {
  let n = nmod();
  for (let k = 1; k <= n; k++) {
    let c = ((Number(v || 1) + k - 1) % n) + 1;
    if (c !== Number(v)) return c;
  }
  return Number(v || 1);
}
/**
 * defaultFusionModalities  Provide the default fusion modalities helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function defaultFusionModalities() {
  let v = Number(STATE.activeModality || 1);
  let n = nextModality(v);
  return Array.from(new Set([v, n]));
}
/**
 * activeModalityHeader  Display the current single-modality or shared early-fusion scope.
 */
function activeModalityHeader() {
  const indices = Number(STATE.fusionFlag) === 1
    ? arr(STATE.fusionModalities)
    : [STATE.activeModality];
  const names = labels();
  return `${indices.length > 1 ? "Active modalities" : "Active modality"}: ` +
    indices.map(i => `${names[i - 1].replace(/^#\d+: /, "")} (Modality #${i})`).join(", ");
}
/**
 * modalityText  Build the modality text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function modalityText(i) {
  let labs = labels();
  return (
    (labs[i - 1] || `Modality #${i}`) +
    (modalityIsImaging(i) ? " [imaging]" : " [non-imaging]")
  );
}
/**
 * fusionSummaryText  Build the fusion summary text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function fusionSummaryText() {
  return arr(STATE.fusionModalities).map(Number).map(modalityText).join("; ");
}
/**
 * stackingCandidateIndices  Provide the stacking candidate indices helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingCandidateIndices() {
  return arr(STATE.stackingCandidateIndices).map(Number);
}
/**
 * stackingCandidateLabels  Provide the stacking candidate labels helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingCandidateLabels() {
  return arr(STATE.stackingCandidateLabels);
}
/**
 * stackingCandidateAvailable  Provide the stacking candidate available helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingCandidateAvailable() {
  return arr(STATE.stackingCandidateAvailable).map(Boolean);
}
/**
 * stackingCandidateNFeatures  Provide the stacking candidate nfeatures helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingCandidateNFeatures() {
  return arr(STATE.stackingCandidateNFeatures).map(Number);
}
/**
 * selectedStackingAnalyses  Apply the ed stacking analyses selection to browser state and dependent controls.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function selectedStackingAnalyses() {
  return arr(STATE.stackingSelectedAnalyses)
    .map(Number)
    .filter((x) => Number.isFinite(x));
}
/**
 * stackingAnalysisText  Build the stacking analysis text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingAnalysisText(i) {
  let idx = stackingCandidateIndices(),
    labs = stackingCandidateLabels(),
    av = stackingCandidateAvailable(),
    nf = stackingCandidateNFeatures();
  let k = idx.indexOf(Number(i));
  let txt = k >= 0 ? labs[k] || `Analysis ${i}` : `Analysis ${i}`;
  if (k >= 0)
    txt +=
      ` (${nf[k] || 1} feature${Number(nf[k] || 1) === 1 ? "" : "s"})` +
      (av[k] ? "" : " [unavailable]");
  return txt;
}
/**
 * stackingSummaryText  Build the stacking summary text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function stackingSummaryText() {
  let sel = selectedStackingAnalyses();
  return sel.length
    ? sel.map(stackingAnalysisText).join("; ")
    : "No first-level analyses selected.";
}
/**
 * allowedActiveModalities  Provide the allowed active modalities helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function allowedActiveModalities() {
  let f = Number(STATE.fusionFlag || 0);
  let ms = arr(STATE.fusionModalities).map(Number);
  return f === 0
    ? Array.from({ length: nmod() }, (_, i) => i + 1)
    : ms.length
      ? ms
      : [Number(STATE.activeModality || 1)];
}
/**
 * normalizeMenuState  Normalize menu state payloads into the browser-side model used by the UI.
 * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
 */
function normalizeMenuState() {
  if (!stackingVisible()) STATE.stackingFlag = 2;
  STATE.stackingEnabled = isStacking();
  if (nmod() <= 1) {
    STATE.fusionFlag = 0;
    STATE.fusionModalities = [1];
    STATE.activeModality = 1;
  }
  if (isStacking()) {
    STATE.fusionFlag = 0;
    STATE.fusionModalities = [1];
    STATE.activeModality = 1;
  }
  let f = Number(STATE.fusionFlag || 0);
  let a = Number(STATE.activeModality || 1);
  if (!Number.isFinite(a) || a < 1 || a > nmod()) a = 1;
  STATE.activeModality = a;
  if (f === 0) {
    STATE.fusionModalities = [a];
  } else {
    let m = arr(STATE.fusionModalities)
      .map(Number)
      .filter((x) => Number.isFinite(x) && x >= 1 && x <= nmod());
    m = [...new Set(m)];
    if (m.length < 2) m = defaultFusionModalities();
    STATE.fusionModalities = m;
    if (f === 1 || !m.includes(a)) STATE.activeModality = m[0];
  }
  STATE.isImaging = modalityIsImaging(Number(STATE.activeModality || 1));
}
/**
 * renderAltLabelSummary  Render the alt label summary UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderAltLabelSummary() {
  let fld = document.getElementById("altLabelField");
  if (fld)
    fld.classList.toggle(
      "hidden",
      STATE.altLabelAvailable === false && !altEnabled(),
    );
  let sm = document.getElementById("altLabelSummary");
  if (sm) sm.textContent = String(STATE.altLabelSummary);
}
/**
 * renderMultiLabelSummary  Render analysis-level multi-label selection state.
 */
function renderMultiLabelSummary() {
  let fld = document.getElementById("multiLabelField");
  let available = !!STATE.multiLabelAvailable;
  if (fld) fld.classList.toggle("hidden", !available);
  let choose = document.getElementById("chooseMultiLabels");
  if (choose) choose.disabled = !available || altEnabled();
  let sm = document.getElementById("multiLabelSummary");
  if (!sm) return;
  let sel = multiLabelSelection();
  let labs = multiLabelLabels();
  if (!available) {
    sm.textContent = "";
    return;
  }
  let selectionText =
    sel.length === labs.length
      ? `All ${sel.length} labels selected.`
      : `${sel.length} of ${labs.length} labels selected: ${sel.map((i) => labs[i - 1] || `Label ${i}`).join(", ")}`;
  sm.textContent = altEnabled()
    ? `Native multi-label selection suspended while the alternative label is active. ${selectionText}`
    : selectionText;
}
/**
 * openMultiLabelSelector  Open the native NM.label column selector.
 */
function openMultiLabelSelector() {
  if (!STATE.multiLabelAvailable || altEnabled()) return;
  let list = document.getElementById("multiLabelSelectorList");
  let st = document.getElementById("multiLabelSelectorStatus");
  if (!list || !st) return;
  list.innerHTML = "";
  st.textContent = "";
  let selected = multiLabelSelection();
  multiLabelLabels().forEach((label, idx) => {
    let row = document.createElement("label");
    row.className = "checkitem";
    let cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = idx + 1;
    cb.checked = selected.includes(idx + 1);
    let span = document.createElement("span");
    span.textContent = label || `Label ${idx + 1}`;
    row.appendChild(cb);
    row.appendChild(span);
    list.appendChild(row);
  });
  document.getElementById("multiLabelSelectorModal").classList.add("open");
}
/**
 * closeMultiLabelSelector  Close the multi-label selector without changing state.
 */
function closeMultiLabelSelector() {
  document.getElementById("multiLabelSelectorModal").classList.remove("open");
}
/**
 * confirmMultiLabelSelector  Commit the selected NM.label columns to browser state.
 */
async function confirmMultiLabelSelector() {
  let list = document.getElementById("multiLabelSelectorList");
  let vals = Array.from(list.querySelectorAll("input[type=checkbox]:checked"))
    .map((x) => Number(x.value))
    .filter((x) => Number.isFinite(x) && x >= 1);
  vals = [...new Set(vals)];
  if (!vals.length) {
    document.getElementById("multiLabelSelectorStatus").textContent =
      "Select at least one label.";
    return;
  }
  STATE.multiLabelSelection = vals;
  STATE.multiLabelCount = vals.length;
  markMenuChanged("multiLabelSelection");
  closeMultiLabelSelector();
  render();
  try {
    await flushMenuSync();
    await applyMenuContext();
  } catch (e) {
    status("Multi-label target selection could not be applied: " + e.message, "danger");
  }
}
/**
 * renderAltLabelModal  Render the alt label modal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderAltLabelModal() {
  let en = document.getElementById("altLabelEnabled");
  if (en) en.checked = altEnabled();
  let opts = document.getElementById("altLabelOptions");
  if (opts) opts.classList.toggle("hidden", !altEnabled());
  let sel = document.getElementById("altLabelSourceVar");
  if (sel) {
    let cur = String(STATE.altLabelSourceVar || "");
    sel.innerHTML = "";
    let empty = document.createElement("option");
    empty.value = "";
    empty.textContent = cur
      ? "Keep stored label vector"
      : "Select workspace variable...";
    sel.appendChild(empty);
    altCandidates().forEach((c) => {
      let o = document.createElement("option");
      o.value = c.name;
      o.textContent = `${c.name} (${c.class || ""}, ${arr(c.size).join("x")}, ${c.nUniqueNonMissing || "?"} unique, ${c.taskHint || "ambiguous"})`;
      if (cur && c.name === cur) o.selected = true;
      sel.appendChild(o);
    });
  }
  let nm = document.getElementById("altLabelName");
  if (nm) nm.value = STATE.altLabelName || STATE.altLabelSourceVar || "";
  let md = document.getElementById("altLabelMode");
  if (md)
    md.value =
      STATE.altLabelMode ||
      "classification";
  let gf = document.getElementById("altLabelGroupNamesField");
  if (gf)
    gf.classList.toggle(
      "hidden",
      String(STATE.altLabelMode || "").toLowerCase() !== "classification",
    );
  let gi = document.getElementById("altLabelGroupNames");
  if (gi) gi.value = altGroupText();
  let c = selectedAltCandidate();
  let nu = Number(c ? c.nUniqueNonMissing : STATE.altLabelNValues);
  let invalidBinary = altEnabled() && STATE.altLabelMode === "classification" && nu > 2;
  let st = document.getElementById("altLabelStatus");
  st.classList.toggle("hidden", !invalidBinary);
  st.textContent = invalidBinary
    ? "Classification alternative labels must be binary. Select regression or a binary vector."
    : "";
}
/**
 * renderStackingModal  Render the stacking modal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderStackingModal() {
  document.getElementById("stackingFlag").value = String(Number(STATE.stackingFlag || 2));
  document.getElementById("stackingOptions").classList.toggle("hidden", !isStacking());
  document.getElementById("stackingAnalysesSummary").textContent = stackingSummaryText();
  document.getElementById("stackingDetails").classList.toggle(
    "hidden",
    !isStacking() || selectedStackingAnalyses().length < 1,
  );
  document.getElementById("stackingFeatureNameMode").value = String(Number(STATE.stackingFeatureNameMode || 1));
  document.getElementById("stackingFeatureNameVariableField").classList.toggle(
    "hidden",
    Number(STATE.stackingFeatureNameMode || 1) !== 2,
  );
  document.getElementById("stackingFeatureNameVariable").value = STATE.stackingFeatureNameVariable;
  document.getElementById("stackingPredictionMode").value = String(Number(STATE.stackingPredictionMode || 2));
  const info = document.getElementById("stackingConfigInfo");
  if (!stackingVisible())
    info.textContent = "Stacking is unavailable because fewer than two completed analyses share the current CV setup.";
  else if (!isStacking())
    info.textContent = "Stacking is available but disabled.";
  else
    info.textContent = selectedStackingAnalyses().length >= 2
      ? `Stacking enabled. ${selectedStackingAnalyses().length} first-level analyses selected.`
      : "Stacking enabled. Select at least two first-level analyses.";
}
/**
 * cvFillVectorSelect  Return or update the cv fill vector select control used by the page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function cvFillVectorSelect(id, cur, empty) {
  let sel = document.getElementById(id);
  if (!sel) return;
  sel.innerHTML = "";
  let candidates = cvCandidates();
  let e = document.createElement("option");
  e.value = "";
  e.textContent = candidates.length
    ? empty || "Select workspace vector..."
    : "No suitable n-subject vector found";
  sel.appendChild(e);
  sel.disabled = !candidates.length;
  candidates.forEach((c) => {
    let o = document.createElement("option");
    o.value = c.name;
    o.textContent = `${c.name} (${c.class || ""}, ${arr(c.size).join("x")}, ${c.nUniqueNonMissing || "?"} unique)`;
    if (cur && String(cur) === String(c.name)) o.selected = true;
    sel.appendChild(o);
  });
}
/**
 * cvSetHidden  Provide the cv set hidden helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function cvSetHidden(id, hide) {
  let el = document.getElementById(id);
  if (el) el.classList.toggle("hidden", !!hide);
}
/**
 * cvSetVal  Provide the cv set val helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvSetVal(id, val) {
  let el = document.getElementById(id);
  if (el) el.value = String(val);
}
/**
 * cvSetChecked  Provide the cv set checked helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvSetChecked(id, val) {
  let el = document.getElementById(id);
  if (el) el.checked = !!val;
}
/**
 * cvGetNum  Provide the cv get num helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function cvGetNum(id, d) {
  let el = document.getElementById(id);
  let v = el ? Number(el.value) : NaN;
  return Number.isFinite(v) ? v : d;
}
/**
 * renderCVSummary  Render the cvsummary UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function renderCVSummary() {
  let c = CV(),
    sm = document.getElementById("cvSummary");
  if (!sm) return;
  let fw = Number(c.cvFramework || 1),
    txt = [
      "Pooled",
      "Outer LGO / inner pooled",
      "Nested LGO",
      "Outer LGO / inner LGI",
    ][Math.max(1, Math.min(4, fw)) - 1];
  let bits = [
    txt,
    `CV2 ${String(c.cvOuterMode || "kfold") == "loo" ? "LOO" : (c.cvOuterFold || 10) + " folds"}`,
    `CV1 ${String(c.cvInnerMode || "kfold") == "loo" ? "LOO" : (c.cvInnerFold || 10) + " folds"}`,
  ];
  if (c.cvHasStructure) bits.push("CV structure available");
  sm.textContent = bits.join("; ");
}
/**
 * renderCVModal  Render the cvmodal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCVModal() {
  let c = CV(),
    fw = Number(c.cvFramework || 1);
  if (fw < 1 || fw > 4) fw = 1;
  c.cvFramework = fw;
  if (fw !== 1) c.cvOuterMode = "group";
  if (fw === 3 || fw === 4) c.cvInnerMode = "group";
  if (fw === 4) {
    c.cvOuterPerm = 1;
    c.cvInnerPerm = 1;
  }
  if (fw === 3) {
    c.cvOuterPerm = 1;
    c.cvInnerPerm = 1;
  }
  let outerMode = String(c.cvOuterMode || "kfold"),
    innerMode = String(c.cvInnerMode || "kfold");
  cvSetVal("cvFramework", fw);
  cvSetVal("cvOuterMode", outerMode);
  cvSetVal("cvInnerMode", innerMode);
  cvSetVal("cvOuterPerm", c.cvOuterPerm || 1);
  cvSetVal("cvOuterFold", c.cvOuterFold > 0 ? c.cvOuterFold : 10);
  cvSetVal("cvInnerPerm", c.cvInnerPerm || 1);
  cvSetVal("cvInnerFold", c.cvInnerFold > 0 ? c.cvInnerFold : 10);
  cvSetHidden("cvOuterModeField", fw !== 1);
  cvSetHidden("cvInnerModeField", fw >= 3);
  cvSetHidden("cvOuterGroupField", fw === 1);
  cvSetHidden("cvInnerGroupField", !(fw === 3 || fw === 4));
  cvSetHidden(
    "cvOuterPermField",
    !((fw === 1 && outerMode !== "loo") || fw === 2),
  );
  cvSetHidden("cvOuterFoldField", !(fw === 1 && outerMode !== "loo"));
  cvSetHidden(
    "cvInnerPermField",
    !((fw === 1 || fw === 2) && innerMode !== "loo"),
  );
  cvSetHidden(
    "cvInnerFoldField",
    !((fw === 1 || fw === 2) && innerMode !== "loo"),
  );
  cvFillVectorSelect(
    "cvOuterGroupSourceVar",
    c.cvOuterGroupSourceVar,
    "Select outer group index...",
  );
  cvFillVectorSelect(
    "cvInnerGroupSourceVar",
    c.cvInnerGroupSourceVar,
    "Select inner group index...",
  );
  cvFillVectorSelect(
    "cvConstrainedSourceVar",
    c.cvConstrainedSourceVar,
    "Select constraint index...",
  );
  cvFillVectorSelect(
    "cvOnlyGroupSourceVar",
    c.cvOnlyGroupSourceVar,
    "Select test-only index...",
  );
  let os = document.getElementById("cvOuterGroupSummary");
  if (os)
    os.textContent =
      c.cvOuterGroupSummary ||
      "Group index is read from the selected workspace variable on Finish.";
  let is = document.getElementById("cvInnerGroupSummary");
  if (is)
    is.textContent =
      c.cvInnerGroupSummary ||
      "Group index is read from the selected workspace variable on Finish.";
  let df = document.getElementById("cvDecomposeField"),
    ds = document.getElementById("cvDecompose"),
    di = document.getElementById("cvDecomposeInfo");
  if (df) df.classList.toggle("hidden", !cvMulticlass());
  if (ds) {
    if (cvMulticlass() && cvLOO()) {
      c.cvDecompose = 2;
      ds.value = "2";
      ds.disabled = true;
      if (di)
        di.textContent =
          "Leave-one-out CV restricts multiclass learning to one-vs-all, matching the legacy configurator.";
    } else {
      ds.disabled = false;
      ds.value = String(c.cvDecompose || 1);
      if (di)
        di.textContent = cvMulticlass()
          ? "Select how multiclass labels are decomposed for binary learners."
          : "";
    }
  }
  cvSetChecked("cvEqEnabled", !!c.cvEqEnabled);
  cvSetHidden("cvEqOptions", !c.cvEqEnabled);
  cvSetHidden("cvEqRegression", !(c.cvEqEnabled && cvRegression()));
  cvSetHidden("cvEqClassification", !(c.cvEqEnabled && !cvRegression()));
  cvSetVal("cvEqTarget", c.cvEqTarget || "label");
  let covsel = document.getElementById("cvEqCovariateIndex");
  if (covsel) {
    covsel.innerHTML = "";
    arr(c.cvCovariateNames).forEach((nm, i) => {
      let o = document.createElement("option");
      o.value = i + 1;
      o.textContent = nm;
      if (Number(c.cvEqCovariateIndex || 0) === i + 1) o.selected = true;
      covsel.appendChild(o);
    });
  }
  cvSetHidden(
    "cvEqCovariateField",
    String(c.cvEqTarget || "label") !== "covariate",
  );
  cvSetVal("cvEqMinCount", c.cvEqMinCount || 10);
  cvSetVal("cvEqMaxCount", c.cvEqMaxCount || 10);
  cvSetVal("cvEqBinCount", c.cvEqBinCount || 10);
  cvSetVal("cvEqPosNegRatio", c.cvEqPosNegRatio || 1.5);
  cvSetChecked("cvEqAddRemoved2Test", !!c.cvEqAddRemoved2Test);
  cvSetHidden("cvEqHistogramActions", !(c.cvEqEnabled && cvRegression()));
  let allowCon = fw === 1 && outerMode !== "loo" && innerMode !== "loo";
  if (!allowCon) c.cvConstrainedCV = 2;
  cvSetHidden("cvConstrainedField", !allowCon);
  cvSetChecked("cvConstrainedCV", Number(c.cvConstrainedCV || 2) === 1);
  cvSetHidden("cvConstrainedOptions", Number(c.cvConstrainedCV || 2) !== 1);
  let cs = document.getElementById("cvConstrainedSummary");
  if (cs)
    cs.textContent =
      c.cvConstrainedGroupSummary ||
      "Constraint index is read from the selected workspace variable on Finish.";
  cvSetChecked("cvOnlyGroupFlag", Number(c.cvOnlyGroupFlag || 2) === 1);
  cvSetHidden("cvOnlyGroupOptions", Number(c.cvOnlyGroupFlag || 2) !== 1);
  c.cvOnlyGroupLevel = 1;
  cvSetVal("cvOnlyGroupLevel", 1);
  let og = document.getElementById("cvOnlyGroupSummary");
  if (og)
    og.textContent =
      c.cvOnlyGroupSummary ||
      "Exclusive test cases are read from the selected workspace variable on Finish.";
  cvSetHidden("cvAppendModeField", true);
  cvSetVal("cvAppendMode", 0);
  let lp = document.getElementById("cvLoadPath");
  if (lp) lp.value = c.cvLoadPath || "";
  let sp = document.getElementById("cvSavePath");
  if (sp) sp.value = c.cvSavePath || "";
  let sv = document.getElementById("cvSave");
  if (sv) sv.disabled = !c.cvCanSave && !c.cvHasStructure;
  let inf = document.getElementById("cvConfigInfo");
  if (inf) {
    let msg = [];
    if (outerMode === "loo" || innerMode === "loo")
      msg.push("LOO disables the corresponding permutation setting.");
    if (c.cvBuildRequested)
      msg.push("Build is executed immediately in MATLAB.");
    if (c.cvLoadRequested) msg.push("Load is executed immediately in MATLAB.");
    if (c.cvSaveRequested) msg.push("Save is executed immediately in MATLAB.");
    inf.textContent = msg.length
      ? msg.join("\n")
      : "Configure CV settings. Build, Load and Save are executed immediately in MATLAB.";
  }
  renderCVSummary();
}
/**
 * render  Render the render UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 */
function render() {
  const __renderT0 = nmClientNow();
  let __renderLast = __renderT0;
  /**
   * __renderMark  Provide the render mark helper used by training-template configurator browser page.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  const __renderMark = (label) => {
    if (!NM_UI_CLIENT_PROFILE) return;
    const now = nmClientNow();
    nmClientProfileLog(
      `render ${label}: ${((now - __renderLast) / 1000).toFixed(3)}s`,
    );
    __renderLast = now;
  };
  normalizeMenuState();
  window.NMModuleNavigationRail.updateReturnButton(appContext(),"Finish / close");
  __renderMark("normalize");
  let f = Number(STATE.fusionFlag || 0);
  let sfld = document.getElementById("stackingField");
  if (sfld) sfld.classList.toggle("hidden", !stackingVisible());
  let ss = document.getElementById("stackingSummary");
  if (ss) {
    if (!stackingVisible()) ss.textContent = "Stacking unavailable.";
    else if (isStacking()) ss.textContent = "Enabled. " + stackingSummaryText();
    else ss.textContent = "Available, currently disabled.";
  }
  let ff = document.getElementById("fusionFlag"),
    am = document.getElementById("activeModality");
  let fopts = [
    [0, "No fusion"],
    [1, "Early fusion: concatenate before preprocessing"],
    [2, "Intermediate fusion: concatenate after preprocessing"],
    [3, "Late fusion: decision-based/bagging"],
  ];
  ff.innerHTML = "";
  fopts.forEach((x) => {
    let o = document.createElement("option");
    o.value = x[0];
    o.textContent = x[1];
    if (f === x[0]) o.selected = true;
    ff.appendChild(o);
  });
  let labs = labels();
  am.innerHTML = "";
  allowedActiveModalities().forEach((i) => {
    let ao = document.createElement("option");
    ao.value = i;
    ao.textContent = labs[i - 1] || `Modality #${i}`;
    if (Number(STATE.activeModality || 1) === i) ao.selected = true;
    am.appendChild(ao);
  });
  __renderMark("fusion/modality selects");
  let fb = document.getElementById("fusionBlock");
  if (fb) fb.classList.toggle("hidden", isStacking() || nmod() <= 1);
  let mf = document.getElementById("fusionModalitiesField");
  if (mf) mf.classList.toggle("hidden", isStacking() || f === 0);
  let fs = document.getElementById("fusionSummary");
  if (fs) fs.textContent = isStacking() || f === 0 ? "" : fusionSummaryText();
  let af = document.getElementById("activeModalityField");
  if (af) af.classList.toggle("hidden", isStacking() || f === 1 || nmod() <= 1);
  let info = document.getElementById("fusionInfo");
  if (info) {
    info.classList.toggle("hidden", nmod() <= 1);
    if (nmod() <= 1) info.textContent = "";
    else if (isStacking())
      info.textContent =
        "Stacking is enabled. Data fusion is disabled, ML remains global, and preprocessing uses dedicated non-imaging STACKING.PREPROC.";
    else if (f === 1)
      info.textContent =
        `Early fusion stores the shared preprocessing pipeline in PREPROC{${arr(STATE.fusionModalities)[0]}} only.` +
        (selectedMixesImaging()
          ? " Mixed imaging/non-imaging early fusion: imaging-specific preprocessing modules are disabled in the editor."
          : "");
    else if (f === 2)
      info.textContent =
        "Intermediate fusion edits the active modality-specific PREPROC; ML remains global.";
    else if (f === 3)
      info.textContent =
        "Late fusion edits the active STRAT{i}.PREPROC and STRAT{i}.SVM/GRD.";
    else
      info.textContent =
        "No fusion edits the selected single PREPROC and global ML configuration.";
  }
  let openPre = document.getElementById("openPreproc");
  if (openPre)
    openPre.textContent = isStacking()
      ? "Open stacker preprocessing"
      : "Open preprocessing pipeline";
  let stkBtn = document.getElementById("openStackingConfig");
  if (stkBtn) stkBtn.classList.toggle("hidden", !stackingVisible());
  document.getElementById("crumb").textContent = isStacking()
    ? "Define parameter template > stacking"
    : f === 1
      ? `Define parameter template > early fusion PREPROC{${arr(STATE.fusionModalities)[0]}}`
      : `Define parameter template > modality #${STATE.activeModality || 1}`;
  __renderMark("context text/summaries");
  renderStackingModal();
  renderAltLabelSummary();
  renderMultiLabelSummary();
  renderAltLabelModal();
  renderCVSummary();
  let ps = document.getElementById("preprocSummary");
  if (ps) ps.textContent = activePreprocSummaryText();
  let pf = document.getElementById("preprocField");
  let ppError = !!(STATE.preprocMixedEarlyFusionIllegal || STATE.preprocAvailabilityInvalid);
  let ppReview = preprocNeedsReview();
  if (pf) {
    pf.classList.toggle("dangerField", ppError);
    pf.classList.toggle("warningField", ppReview && !ppError);
  }
  let pb = document.getElementById("openPreproc");
  if (pb) {
    pb.classList.toggle("dangerButton", ppError);
    pb.classList.toggle("warningButton", ppReview && !ppError);
  }
  updateCopyPreprocButton();
  let sy = document.getElementById("synthSummary");
  if (sy) sy.textContent = synthSummaryText();
  let ms = document.getElementById("mlSummary");
  if (ms) ms.textContent = STATE.mlSummary || "Machine-learning defaults.";
  document.querySelectorAll('#openRFEConfig, [data-open="openRFEConfig"]').forEach(b => {
    b.disabled = !!STATE.seqoptStacking;
    b.title = STATE.seqoptStacking
      ? 'SEQOPT selects and orders stacking predictions itself; filter and wrapper ensembles are unavailable.'
      : '';
  });
  __renderMark("core summaries/modals");
  renderAuditSummary();
  if (window.NMMULTIUI) NMMULTIUI.renderSummary(STATE);
  if (window.NMRFEUI) NMRFEUI.renderSummary(STATE);
  if (window.NMVISUI) NMVISUI.renderSummary(STATE);
  if (window.NMMLIUI) NMMLIUI.renderSummary(STATE);
  if (window.NMSAVUI) NMSAVUI.renderSummary(STATE);
  __renderMark("module summaries");
  renderCVModal();
  renderViewMode();
  __renderMark("view mode");
  renderCanvas();
  __renderMark("canvas");
  if (STATE.fullySyntheticMode) {
    const permitted = ['openCVConfig', 'openPreproc', 'openML'];
    if (STATE.fullySyntheticMulticlass) permitted.push('openMULTIConfig');
    document.querySelectorAll('[data-open]').forEach(el => {
      if (!permitted.includes(el.dataset.open)) {
        el.disabled = true;
        el.title = 'Unavailable for fully synthetic population studies.';
      }
    });
    ['openAltLabelConfig', 'openSynthConfig', 'openStackingConfig',
     'openRFEConfig', 'openVISConfig', 'openMLIConfig', 'openSAVConfig',
     'openVerbosityConfig', 'exportTrainScaffold', 'saveTrainTemplate', 'loadTrainTemplate'].concat(
       STATE.fullySyntheticMulticlass ? [] : ['openMULTIConfig']).forEach(id => {
      const el = document.getElementById(id);
      if (el) el.disabled = true;
    });
  }
  syncMenu();
  __renderMark("syncMenu");
  if (NM_UI_CLIENT_PROFILE)
    nmClientProfileLog(
      `render TOTAL: ${nmClientProfileDelta(__renderT0)}s; modalities=${nmod()}`,
    );
}
const altHelp = NMContextHelp.attachForm(document.getElementById('altLabelModal'),
  'Alternative_Label_Context_Help.html', 'Alternative label help', 'altLabelOverview', 'altLabelOverview');
document.getElementById("openAltLabelConfig").onclick = () => {
  if (activeEditor) {
    status(
      "Another configuration window is already open. Return to the main configuration menu first.",
      "warn",
    );
    return;
  }
  setActiveEditorFromChild("altlabel");
  document.getElementById("altLabelModal").classList.add("open");
  renderAltLabelModal();
};
document.getElementById("closeAltLabelConfig").onclick = async () => {
  try {
    await flushMenuSync();
    await applyMenuContext();
  } catch (e) {
    altStatus("Alternative-label configuration failed: " + e.message, "danger");
    return;
  }
  window.NMUIMessageTools.clearMessage("nm-altlabel");
  altHelp.close();
  document.getElementById("altLabelModal").classList.remove("open");
  setActiveEditorFromChild(null);
};
document.getElementById("altLabelEnabled").onchange = (e) => {
  STATE.altLabelEnabled = !!e.target.checked;
  markMenuChanged("altLabelEnabled", "altLabelSourceVar", "altLabelName", "altLabelMode", "altLabelGroupNames");
  if (STATE.altLabelEnabled) closeMultiLabelSelector();
  render();
};
let chooseMultiLabels = document.getElementById("chooseMultiLabels");
if (chooseMultiLabels) chooseMultiLabels.onclick = openMultiLabelSelector;
let cancelMultiLabelSelection = document.getElementById("cancelMultiLabelSelection");
if (cancelMultiLabelSelection) cancelMultiLabelSelection.onclick = closeMultiLabelSelector;
let confirmMultiLabelSelection = document.getElementById("confirmMultiLabelSelection");
if (confirmMultiLabelSelection) confirmMultiLabelSelection.onclick = confirmMultiLabelSelector;
document.getElementById("altLabelSourceVar").onchange = (e) => {
  STATE.altLabelSourceVar = e.target.value;
  markMenuChanged("altLabelEnabled", "altLabelSourceVar", "altLabelName", "altLabelMode", "altLabelGroupNames");
  let c = selectedAltCandidate();
  if (c) {
    if (!STATE.altLabelName) STATE.altLabelName = c.name;
    STATE.altLabelMode = inferAltMode(c);
    STATE.altLabelNValues = Number(c.nUniqueNonMissing || 0);
  }
  render();
};
document.getElementById("altLabelName").oninput = (e) => {
  STATE.altLabelName = e.target.value;
  markMenuChanged("altLabelEnabled", "altLabelSourceVar", "altLabelName", "altLabelMode", "altLabelGroupNames");
  syncMenu();
};
document.getElementById("altLabelMode").onchange = (e) => {
  STATE.altLabelMode = e.target.value;
  markMenuChanged("altLabelEnabled", "altLabelSourceVar", "altLabelName", "altLabelMode", "altLabelGroupNames");
  render();
};
document.getElementById("altLabelGroupNames").oninput = (e) => {
  STATE.altLabelGroupNames = e.target.value
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
  markMenuChanged("altLabelEnabled", "altLabelSourceVar", "altLabelName", "altLabelMode", "altLabelGroupNames");
  syncMenu();
};
/**
 * synthSetVal  Provide the synth set val helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function synthSetVal(id, val) {
  let e = document.getElementById(id);
  if (e) e.value = val === undefined || val === null ? "" : val;
}
/**
 * synthSetCheck  Provide the synth set check helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function synthSetCheck(id, val) {
  let e = document.getElementById(id);
  if (e) e.checked = !!val;
}
/**
 * synthMark  Provide the synth mark helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function synthMark() {
  Synth().synthDirty = true;
}
/**
 * renderSynthModal  Render the synth modal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderSynthModal() {
  let s = Synth();
  let m = Number(s.synthMethod || 1);
  synthSetCheck("synthEnabled", !!s.synthEnabled);
  document.getElementById("synthOptions").classList.toggle("hidden", !s.synthEnabled);
  synthSetVal("synthMethod", m);
  synthSetVal("synthStandardizeData", Number(s.synthStandardizeData || 2));
  synthSetVal("synthWrite2Disk", Number(s.synthWrite2Disk || 1));
  synthSetVal("synthUncertaintyScale", s.synthUncertaintyScale);
  synthSetVal("synthK", Number(s.synthK || 5));
  synthSetVal("synthDistanceMeasure", s.synthDistanceMeasure || "Euclidean");
  document
    .querySelectorAll(".synthNSyn")
    .forEach((e) => (e.value = Number(s.synthNumSyntheticObservations ?? 0)));
  synthSetVal("synthBeta", Number(s.synthBeta));
  synthSetVal("synthKDensity", Number(s.synthKDensity || 5));
  synthSetVal("synthKSMOTE", Number(s.synthKSMOTE || 5));
  synthSetVal(
    "synthNComponentsText",
    s.synthNComponentsText || arr(s.synthNComponents).join(" ") || "2",
  );
  synthSetVal("synthMinMethod", Number(s.synthMinMethod || 1));
  ["KNN", "ADASYN", "PCAGauss", "GMM", "Copula"].forEach((name, i) => {
    let e = document.getElementById("synthMethod" + name);
    if (e) e.classList.toggle("hidden", m !== i + 1);
  });
}
/**
 * synthApply  Provide the synth apply helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function synthApply() {
  let s = Synth();
  if (!s.synthDirty && !s.synthPresent) return true;
  try {
    await fetch(API("/api/current"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(STATE),
    }).catch(() => {});
    let changedPaths = serviceChangedPaths("synth");
    let res = await fetch(API("/api/matlabservice"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_apply_synth",
        state: STATE,
        changedPaths: changedPaths,
        timeout: 120,
      }),
    }).then((r) => r.json());
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error((res && res.message) || "Synthetic-data request failed.");
    if (res.state && typeof res.state === "object")
      acceptReturnedState(res.state);
    else if (res.synth && typeof res.synth === "object")
      STATE.synth = res.synth;
    acceptServiceChangedPaths(changedPaths);
    if (res.canvasDirty) {
      markCanvasDirty(res.canvasDirtyReason || "Synthetic-data configuration changed; canvas refresh pending.");
      scheduleCanvasRefresh(150);
    }
    render();
    return true;
  } catch (e) {
    synthStatus("Synthetic-data action failed: " + e.message, "danger");
    return false;
  }
}
/**
 * cvShowBuildConfirm  Provide the cv show build confirm helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function cvShowBuildConfirm() {
  let c = CV();
  c.cvAppendMode = 0;
  cvSetVal("cvBuildAppendChoice", 0);
  let m = document.getElementById("cvBuildConfirmModal");
  if (m) m.classList.add("open");
  cvStatus(
    "Choose how the existing compatible cross-validation structure should be handled. Default: overwrite.",
    "warn",
  );
}
/**
 * cvHideBuildConfirm  Provide the cv hide build confirm helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function cvHideBuildConfirm() {
  let m = document.getElementById("cvBuildConfirmModal");
  if (m) m.classList.remove("open");
}
/**
 * cvBuildWithMode  Provide the cv build with mode helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function cvBuildWithMode(mode) {
  CV().cvAppendMode = Number(mode || 0);
  cvHideBuildConfirm();
  await cvApply("build");
}
/**
 * cvApply  Provide the cv apply helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function cvApply(action) {
  try {
    await fetch(API("/api/current"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(STATE),
    }).catch(() => {});
    let changedPaths = serviceChangedPaths("cv");
    let res = await nmProfiledMatlabService({
      operation: "train_template_apply_cv",
      cvAction: action,
      state: STATE,
      changedPaths: changedPaths,
      includeCanvas: !canvasRefreshShouldBeDeferred(),
      timeout: 600,
    }, "train_template_apply_cv");
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error(
        (res && res.message) || "Cross-validation request failed.",
      );
    if (res.state && typeof res.state === "object") {
      acceptReturnedState(res.state);
    } else if (res.cv && typeof res.cv === "object") {
      STATE.cv = res.cv;
      if (res.multi && typeof res.multi === "object") STATE.multi = res.multi;
    }
    acceptServiceChangedPaths(changedPaths);
    let canvasDirty = !!res.canvasDirty || !!(res.state && res.state.canvasDirty);
    if (canvasDirty) {
      markCanvasDirty(res.canvasDirtyReason || (res.state && res.state.canvasDirtyReason) || "Cross-validation changed; canvas refresh pending.");
      scheduleCanvasRefresh(150);
    }
    render();
    // Show only consequential CV operations. MATLAB owns the outcome text.
    window.NMUIMessageTools.clearMessage("nm-cv");
    if (action === "build") cvStatus(res.message, "info");
    if (action === "load" || action === "save") cvStatus(res.message, "ok");
    return true;
  } catch (e) {
    cvStatus("Cross-validation action failed: " + e.message, "danger");
    return false;
  }
}
/**
 * cvPlotHistogram  Provide the cv plot histogram helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function cvPlotHistogram(equalized) {
  let c = CV();
  try {
    await fetch(API("/api/current"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(STATE),
    }).catch(() => {});
    let res = await fetch(API("/api/matlabservice"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "cv_plot_regression_histogram",
        cv: c,
        equalized: !!equalized,
        timeout: 120,
      }),
    }).then((r) => r.json());
    if (res && res.error) throw new Error(res.message ? res.message : res.error);
    if (!res || res.ok === false)
      throw new Error((res && res.message) || "Histogram request failed.");
  } catch (e) {
    cvStatus("Histogram display failed: " + e.message, "danger");
  }
}
/**
 * menuPickPath  Provide the menu pick path helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function menuPickPath(kind, filter, initial) {
  let res = await fetch(API("/api/pickpath"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      kind: kind || "file",
      multiple: false,
      filter: filter || "",
      initial: initial || "",
      timeout: 240,
    }),
  }).then((r) => r.json());
  if (res && res.error) throw new Error(res.message ? res.message : res.error);
  let p = arr(res.paths);
  return p.length ? p[0] : "";
}
// CV uses the shared form-help layout without changing its controls.
const cvModal = document.getElementById('cvConfigModal');
const cvHelp = NMContextHelp.attachForm(cvModal, 'CV_Context_Help.html', 'Cross-validation help', 'cvOverview', 'cvStorage');
cvHelp.button(document.getElementById('cvConstrainedOptions'), 'cvConstrainedSourceVar', 'Constraint group index');
cvHelp.button(document.getElementById('cvEqHistogramActions'), 'cvHistograms', 'Inspect equalization histograms');
cvHelp.button(document.getElementById('cvBuild').parentElement, 'cvOperations', 'Build, load and save CV structures');
document.getElementById("openCVConfig").onclick = () => {
  if (activeEditor) {
    status(
      "Another configuration window is already open. Return to the main configuration menu first.",
      "warn",
    );
    return;
  }
  rememberReturnView();
  setActiveEditorFromChild("cv");
  document.getElementById("cvConfigModal").classList.add("open");
  renderCVModal();
};
document.getElementById("closeCVConfig").onclick = async () => {
  if (!(await cvApply("apply"))) return;
  cvHelp.close();
  finishInlineConfigurator("cvConfigModal");
};
document.getElementById("cvFramework").onchange = (e) => {
  let c = CV();
  c.cvFramework = Number(e.target.value);
  if (c.cvFramework !== 1) c.cvOuterMode = "group";
  if (c.cvFramework >= 3) c.cvInnerMode = "group";
  render();
};
document.getElementById("cvOuterMode").onchange = (e) => {
  CV().cvOuterMode = e.target.value;
  if (e.target.value === "loo") {
    CV().cvOuterFold = -1;
    CV().cvOuterPerm = 1;
  }
  render();
};
document.getElementById("cvInnerMode").onchange = (e) => {
  CV().cvInnerMode = e.target.value;
  if (e.target.value === "loo") {
    CV().cvInnerFold = -1;
    CV().cvInnerPerm = 1;
  }
  render();
};
// Simple CV controls share one binding path; framework/LOO choices retain dedicated handlers.
[
  ['cvOuterPerm', 'input', 'number', 'sync'],
  ['cvOuterFold', 'input', 'number', 'sync'],
  ['cvInnerPerm', 'input', 'number', 'sync'],
  ['cvInnerFold', 'input', 'number', 'sync'],
  ['cvOuterGroupSourceVar', 'change', 'text', 'render'],
  ['cvInnerGroupSourceVar', 'change', 'text', 'render'],
  ['cvDecompose', 'change', 'number', 'render'],
  ['cvEqEnabled', 'change', 'checked', 'render'],
  ['cvEqTarget', 'change', 'text', 'render'],
  ['cvEqCovariateIndex', 'change', 'number', 'render'],
  ['cvEqMinCount', 'input', 'number', 'sync'],
  ['cvEqMaxCount', 'input', 'number', 'sync'],
  ['cvEqBinCount', 'input', 'number', 'sync'],
  ['cvEqPosNegRatio', 'input', 'number', 'sync'],
  ['cvEqAddRemoved2Test', 'change', 'checked', 'render'],
  ['cvConstrainedCV', 'change', 'flag', 'render'],
  ['cvConstrainedSourceVar', 'change', 'text', 'render'],
  ['cvOnlyGroupFlag', 'change', 'flag', 'render'],
  ['cvOnlyGroupSourceVar', 'change', 'text', 'render'],
  ['cvOnlyGroupLevel', 'change', 'number', 'render'],
  ['cvAppendMode', 'change', 'number', 'render'],
  ['cvLoadPath', 'input', 'text', 'sync'],
  ['cvSavePath', 'input', 'text', 'sync'],
 ].forEach(([id, event, kind, action]) => {
  document.getElementById(id)['on' + event] = e => {
    const value = kind === 'number' ? Number(e.target.value) :
      kind === 'checked' ? !!e.target.checked :
      kind === 'flag' ? (e.target.checked ? 1 : 2) : e.target.value;
    CV()[id] = value;
    if (action === 'render') render();
    else syncMenu();
  };
});
document.getElementById("cvPickLoad").onclick = async () => {
  try {
    let p = await menuPickPath(
      "file",
      "CVstruct_*.mat;*.mat",
      CV().cvLoadPath || "",
    );
    if (p) {
      CV().cvLoadPath = p;
      render();
    }
  } catch (e) {
    cvStatus("CV load-path selection failed: " + e.message, "danger");
  }
};
document.getElementById("cvPickSave").onclick = async () => {
  try {
    let p = await menuPickPath("directory", "", "");
    if (p) {
      CV().cvSavePath = p.replace(/[\\\/]+$/, "") + "/CVstruct_NMcv.mat";
      render();
    }
  } catch (e) {
    cvStatus("CV save-path selection failed: " + e.message, "danger");
  }
};
document.getElementById("cvBuild").onclick = async () => {
  let c = CV();
  if (c.cvCanAppend) {
    cvShowBuildConfirm();
  } else {
    c.cvAppendMode = 0;
    await cvApply("build");
  }
};
document.getElementById("cvBuildConfirmProceed").onclick = async () => {
  let el = document.getElementById("cvBuildAppendChoice");
  await cvBuildWithMode(el ? Number(el.value || 0) : 0);
};
document.getElementById("cvBuildConfirmAbort").onclick = () => {
  cvHideBuildConfirm();
};
document.getElementById("cvLoad").onclick = async () => {
  await cvApply("load");
};
document.getElementById("cvSave").onclick = async () => {
  await cvApply("save");
};
document.getElementById("cvPlotOriginal").onclick = () =>
  cvPlotHistogram(false);
document.getElementById("cvPlotEqualized").onclick = () =>
  cvPlotHistogram(true);
const synthHelp = NMContextHelp.attachForm(document.getElementById('synthConfigModal'), 'Synth_Context_Help.html', 'Synthetic-data help', 'synthOverview', 'synthOverview');
document.getElementById("openSynthConfig").onclick = () => {
  if (activeEditor) {
    status(
      "Another configuration window is already open. Return to the main configuration menu first.",
      "warn",
    );
    return;
  }
  setActiveEditorFromChild("synth");
  document.getElementById("synthConfigModal").classList.add("open");
  renderSynthModal();
};
document.getElementById("closeSynthConfig").onclick = async () => {
  if (!(await synthApply())) return;
  synthHelp.close();
  document.getElementById("synthConfigModal").classList.remove("open");
  setActiveEditorFromChild(null);
  render();
};
document.getElementById("synthEnabled").onchange = (e) => {
  let s = Synth();
  s.synthEnabled = !!e.target.checked;
  synthMark();
  render();
  renderSynthModal();
};
document.getElementById("synthMethod").onchange = (e) => {
  Synth().synthMethod = Number(e.target.value);
  synthMark();
  render();
  renderSynthModal();
};
document.getElementById("synthStandardizeData").onchange = (e) => {
  Synth().synthStandardizeData = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthWrite2Disk").onchange = (e) => {
  Synth().synthWrite2Disk = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthUncertaintyScale").oninput = (e) => {
  Synth().synthUncertaintyScale = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthK").oninput = (e) => {
  Synth().synthK = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthDistanceMeasure").onchange = (e) => {
  Synth().synthDistanceMeasure = e.target.value;
  synthMark();
  syncMenu();
};
document.querySelectorAll(".synthNSyn").forEach(
  (e) =>
    (e.oninput = (ev) => {
      Synth().synthNumSyntheticObservations = Number(ev.target.value);
      synthMark();
      syncMenu();
    }),
);
document.getElementById("synthBeta").oninput = (e) => {
  Synth().synthBeta = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthKDensity").oninput = (e) => {
  Synth().synthKDensity = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthKSMOTE").oninput = (e) => {
  Synth().synthKSMOTE = Number(e.target.value);
  synthMark();
  syncMenu();
};
document.getElementById("synthNComponentsText").oninput = (e) => {
  Synth().synthNComponentsText = e.target.value;
  synthMark();
  syncMenu();
};
document.getElementById("synthMinMethod").onchange = (e) => {
  Synth().synthMinMethod = Number(e.target.value);
  synthMark();
  syncMenu();
};
// Stacking uses the shared form-help layout.
const stackingHelp = NMContextHelp.attachForm(document.getElementById('stackingConfigModal'),
  'Stacking_Context_Help.html', 'Stacking help', 'stackingOverview', 'stackingOverview');
document.getElementById("openStackingConfig").onclick = () => {
  if (activeEditor) {
    status(
      "Another configuration window is already open. Return to the main configuration menu first.",
      "warn",
    );
    return;
  }
  editorReturnViewMode = editorReturnViewMode || currentViewMode();
  setActiveEditorFromChild("stacking");
  document.getElementById("stackingConfigModal").classList.add("open");
  renderStackingModal();
};
document.getElementById("closeStackingConfig").onclick = async () => {
  let rv = editorReturnViewMode || currentViewMode();
  stackingHelp.close();
  document.getElementById("stackingConfigModal").classList.remove("open");
  setActiveEditorFromChild(null);
  if (rv) STATE.uiViewMode = rv;
  try {
    await applyMenuContext();
  } catch (e) {
    render();
    status(
      "Stacking configuration could not be applied: " + e.message,
      "danger",
    );
    editorReturnViewMode = null;
    return;
  }
  if (rv) STATE.uiViewMode = rv;
  render();
  editorReturnViewMode = null;
};
document.getElementById("stackingFlag").onchange = (e) => {
  STATE.stackingFlag = Number(e.target.value);
  markMenuChanged("stackingFlag", "fusionFlag", "fusionModalities", "activeModality");
  if (!stackingVisible()) STATE.stackingFlag = 2;
  STATE.stackingEnabled = isStacking();
  render();
};
document.getElementById("stackingFeatureNameMode").onchange = (e) => {
  STATE.stackingFeatureNameMode = Number(e.target.value);
  markMenuChanged("stackingFeatureNameMode", "stackingFeatureNameVariable");
  if (STATE.stackingFeatureNameMode === 1)
    STATE.stackingFeatureNameVariable = "Automatic definition";
  render();
};
document.getElementById("stackingFeatureNameVariable").oninput = (e) => {
  STATE.stackingFeatureNameVariable = e.target.value;
  markMenuChanged("stackingFeatureNameVariable");
  syncMenu();
};
document.getElementById("stackingPredictionMode").onchange = (e) => {
  STATE.stackingPredictionMode = Number(e.target.value);
  markMenuChanged("stackingPredictionMode");
  render();
};
document.getElementById("fusionFlag").onchange = async (e) => {
  STATE.fusionFlag = Number(e.target.value);
  markMenuChanged("fusionFlag", "fusionModalities", "activeModality");
  if (STATE.fusionFlag === 0)
    STATE.fusionModalities = [Number(STATE.activeModality || 1)];
  else if (arr(STATE.fusionModalities).length < 2)
    STATE.fusionModalities = defaultFusionModalities();
  if (STATE.fusionFlag === 1)
    STATE.activeModality = arr(STATE.fusionModalities)[0];
  render();
  try {
    await applyMenuContext();
  } catch (err) {
    status(
      "Fusion strategy could not be applied: " + err.message,
      "danger",
    );
  }
};
document.getElementById("activeModality").onchange = async (e) => {
  STATE.activeModality = Number(e.target.value);
  markMenuChanged("activeModality", "fusionModalities");
  if (Number(STATE.fusionFlag || 0) === 0)
    STATE.fusionModalities = [STATE.activeModality];
  render();
  try {
    await applyMenuContext();
  } catch (err) {
    status(
      "Active modality change could not be applied: " + err.message,
      "danger",
    );
  }
};

/**
 * activePreprocSourceIndex  Provide the active preproc source index helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function activePreprocSourceIndex() {
  return preprocModuleIndex(Number(STATE.activeModality || 1));
}
/**
 * activePreprocStepLabelsForCopy  Provide the active preproc step labels for copy helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function activePreprocStepLabelsForCopy() {
  let idx = activePreprocSourceIndex();
  let by = arr(STATE.preprocStepLabelsByModality);
  let labs = arr(by[idx - 1]);
  if (!labs.length) labs = arr(STATE.preprocStepLabels);
  return labs;
}
/**
 * canCopyActivePreproc  Return whether the can copy active preproc condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canCopyActivePreproc() {
  if (isStacking()) return false;
  if (nmod() <= 1) return false;
  if (Number(STATE.fusionFlag || 0) === 1) return false;
  return !!arr(STATE.preprocStoredByModality)[activePreprocSourceIndex() - 1] || activePreprocStepLabelsForCopy().length > 0;
}
/**
 * updateCopyPreprocButton  Update copy preproc button state or markup after user interaction or bridge refresh.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function updateCopyPreprocButton() {
  let b = document.getElementById("copyPreprocSetup");
  let h = document.getElementById("copyPreprocHint");
  if (!b) return;
  let can = canCopyActivePreproc();
  b.disabled = !can;
  if (h) {
    if (isStacking()) h.textContent = "Stacking preprocessing has a dedicated branch and is not copied to data modalities.";
    else if (nmod() <= 1) h.textContent = "At least two modalities are required.";
    else if (Number(STATE.fusionFlag || 0) === 1) h.textContent = "Early fusion uses one shared preprocessing branch; no per-modality copy is needed.";
    else if (!can) h.textContent = "Configure preprocessing for this modality before copying it.";
    else h.textContent = "Copies only preprocessing; learner, CV, data and labels are unchanged.";
  }
}
/**
 * modalityCopyLabel  Build the modality copy label shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function modalityCopyLabel(i) {
  let labs = labels();
  let txt = labs[i - 1] || `Modality #${i}`;
  let roi = arr(STATE.atlasSplitRoiNames)[i - 1] || "";
  if (roi) txt += ` — ${roi}`;
  txt += modalityIsImaging(i) ? " [imaging]" : " [non-imaging]";
  let nf = arr(STATE.modalityNFeatures || STATE.nFeaturesByModality || []);
  if (nf[i - 1]) txt += `, ${nf[i - 1]} feature(s)`;
  return txt;
}
/**
 * renderCopyPreprocTargets  Render the copy preproc targets UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCopyPreprocTargets() {
  let list = document.getElementById("copyPreprocTargetList");
  if (!list) return;
  list.innerHTML = "";
  let src = activePreprocSourceIndex();
  for (let i = 1; i <= nmod(); i++) {
    if (i === src) continue;
    let row = document.createElement("label");
    row.className = "checkitem";
    let cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = i;
    let lab = document.createElement("span");
    lab.textContent = modalityCopyLabel(i);
    row.appendChild(cb);
    row.appendChild(lab);
    list.appendChild(row);
  }
}
/**
 * copyPreprocSelectedTargets  Provide the copy preproc selected targets helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function copyPreprocSelectedTargets() {
  let list = document.getElementById("copyPreprocTargetList");
  if (!list) return [];
  return Array.from(list.querySelectorAll("input[type=checkbox]:checked"))
    .map((x) => Number(x.value))
    .filter((x) => Number.isFinite(x) && x >= 1 && x <= nmod());
}
/**
 * setCopyPreprocTargets  Provide the set copy preproc targets helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setCopyPreprocTargets(mode) {
  let list = document.getElementById("copyPreprocTargetList");
  if (!list) return;
  let src = activePreprocSourceIndex();
  let flags = arr(STATE.atlasSplitFlags).map(Boolean);
  let keys = arr(STATE.atlasSplitFamilyKeys).map(String);
  let srcKey = keys[src - 1] || "";
  Array.from(list.querySelectorAll("input[type=checkbox]")).forEach((cb) => {
    let i = Number(cb.value);
    if (mode === "all") cb.checked = true;
    else if (mode === "none") cb.checked = false;
    else if (mode === "split") cb.checked = !!(srcKey && flags[i - 1] && keys[i - 1] === srcKey);
  });
}
/**
 * openCopyPreprocModal  Open the copy preproc modal panel, dialog or linked UI target.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function openCopyPreprocModal() {
  if (activeEditor) {
    status("Return to the main configuration menu before copying preprocessing setup.", "warn");
    return;
  }
  if (!canCopyActivePreproc()) {
    status("Configure preprocessing for the active modality before copying it.", "warn");
    return;
  }
  let src = activePreprocSourceIndex();
  let title = document.getElementById("copyPreprocSourceTitle");
  if (title) title.textContent = `Source: ${modalityCopyLabel(src)}`;
  let chain = document.getElementById("copyPreprocChain");
  let labs = activePreprocStepLabelsForCopy();
  if (chain) {
    chain.innerHTML = labs.length
      ? labs.map((x) => `<span class="preprocChip">${escapeHtml(x)}</span>`).join("<span class=preprocArrow>→</span>")
      : "<span class=muted>No preprocessing steps are configured.</span>";
  }
  let sum = document.getElementById("copyPreprocSourceSummary");
  if (sum) sum.textContent = activePreprocSummaryText();
  renderCopyPreprocTargets();
  let splitBtn = document.getElementById("copyPreprocSelectSplitSiblings");
  if (splitBtn) {
    let keys = arr(STATE.atlasSplitFamilyKeys).map(String);
    let flags = arr(STATE.atlasSplitFlags).map(Boolean);
    let srcKey = keys[src - 1] || "";
    let hasSiblings = !!srcKey && flags.some((f, i) => f && i + 1 !== src && keys[i] === srcKey);
    splitBtn.classList.toggle("hidden", !hasSiblings);
  }
  let st = document.getElementById("copyPreprocStatus");
  if (st) st.textContent = "Select target modalities. Copy mode is replace.";
  document.getElementById("copyPreprocModal").classList.add("open");
}
/**
 * closeCopyPreprocModal  Close the copy preproc modal panel or dialog without changing authoritative MATLAB state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function closeCopyPreprocModal() {
  document.getElementById("copyPreprocModal").classList.remove("open");
}
/**
 * confirmCopyPreproc  Provide the confirm copy preproc helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function confirmCopyPreproc() {
  let targets = copyPreprocSelectedTargets();
  let st = document.getElementById("copyPreprocStatus");
  if (!targets.length) {
    if (st) st.textContent = "Select at least one target modality.";
    return;
  }
  try {
    if (st) st.textContent = "Copying preprocessing setup...";
    let res = await fetch(API("/api/matlabservice"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_copy_preproc",
        state: STATE,
        sourceModality: activePreprocSourceIndex(),
        targetModalities: targets,
        includeCanvas: !canvasRefreshShouldBeDeferred(),
        timeout: 600,
      }),
    }).then((r) => r.json());
    if (!res || res.ok === false || res.error) throw new Error((res && (res.message || res.error)) || "Copy failed");
    if (res.state) acceptReturnedState(res.state);
    if (res.configuratorChildren && typeof res.configuratorChildren === "object") {
      for (const [module, childState] of Object.entries(res.configuratorChildren)) await persistConfiguratorChildState(module, childState);
    }
    closeCopyPreprocModal();
    if (res.state && res.state.canvasDirty) markCanvasDirty(res.state.canvasDirtyReason || "Preprocessing setup copy changed the canvas.");
    render();
  } catch (err) {
    if (st) st.textContent = "Copy failed: " + (err.message || String(err));
    status("Copy preprocessing setup failed: " + (err.message || String(err)), "danger");
  }
}

/**
 * openFusionSelector  Open the fusion selector panel, dialog or linked UI target.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function openFusionSelector() {
  if (Number(STATE.fusionFlag || 0) === 0) return;
  let list = document.getElementById("fusionSelectorList"),
    st = document.getElementById("fusionSelectorStatus");
  list.innerHTML = "";
  st.textContent = "";
  let selected = arr(STATE.fusionModalities).map(Number);
  for (let i = 1; i <= nmod(); i++) {
    let row = document.createElement("label");
    row.className = "checkitem";
    let cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = i;
    cb.checked = selected.includes(i);
    let lab = document.createElement("span");
    lab.textContent = modalityText(i);
    row.appendChild(cb);
    row.appendChild(lab);
    list.appendChild(row);
  }
  document.getElementById("fusionSelectorModal").classList.add("open");
}
/**
 * closeFusionSelector  Close the fusion selector panel or dialog without changing authoritative MATLAB state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function closeFusionSelector() {
  document.getElementById("fusionSelectorModal").classList.remove("open");
}
/**
 * confirmFusionSelector  Return or update the confirm fusion selector control used by the page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function confirmFusionSelector() {
  let list = document.getElementById("fusionSelectorList");
  let vals = Array.from(
    list.querySelectorAll("input[type=checkbox]:checked"),
  ).map((x) => Number(x.value));
  vals = [...new Set(vals)].filter(
    (x) => Number.isFinite(x) && x >= 1 && x <= nmod(),
  );
  if (vals.length < 2) {
    document.getElementById("fusionSelectorStatus").textContent =
      "Select at least two modalities for data fusion.";
    return;
  }
  STATE.fusionModalities = vals;
  markMenuChanged("fusionModalities", "activeModality");
  if (
    Number(STATE.fusionFlag || 0) === 1 ||
    !vals.includes(Number(STATE.activeModality || 1))
  )
    STATE.activeModality = vals[0];
  closeFusionSelector();
  render();
  try {
    await applyMenuContext();
  } catch (err) {
    status(
      "Fusion modality selection was not applied to MATLAB: " + err.message,
      "danger",
    );
  }
}
document.getElementById("chooseFusionModalities").onclick = openFusionSelector;
document.getElementById("cancelFusionSelection").onclick = closeFusionSelector;
document.getElementById("confirmFusionSelection").onclick =
  confirmFusionSelector;
let copyPreprocBtn = document.getElementById("copyPreprocSetup");
if (copyPreprocBtn) copyPreprocBtn.onclick = openCopyPreprocModal;
let cancelCopyPreprocBtn = document.getElementById("cancelCopyPreproc");
if (cancelCopyPreprocBtn) cancelCopyPreprocBtn.onclick = closeCopyPreprocModal;
let confirmCopyPreprocBtn = document.getElementById("confirmCopyPreproc");
if (confirmCopyPreprocBtn) confirmCopyPreprocBtn.onclick = confirmCopyPreproc;
let copyPreprocSelectAllBtn = document.getElementById("copyPreprocSelectAll");
if (copyPreprocSelectAllBtn) copyPreprocSelectAllBtn.onclick = () => setCopyPreprocTargets("all");
let copyPreprocUnselectAllBtn = document.getElementById("copyPreprocUnselectAll");
if (copyPreprocUnselectAllBtn) copyPreprocUnselectAllBtn.onclick = () => setCopyPreprocTargets("none");
let copyPreprocSplitBtn = document.getElementById("copyPreprocSelectSplitSiblings");
if (copyPreprocSplitBtn) copyPreprocSplitBtn.onclick = () => setCopyPreprocTargets("split");
/**
 * openStackingSelector  Open the stacking selector panel, dialog or linked UI target.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function openStackingSelector() {
  let list = document.getElementById("stackingAnalysisList"),
    st = document.getElementById("stackingAnalysisStatus");
  list.innerHTML = "";
  st.textContent = "";
  let idx = stackingCandidateIndices(),
    labs = stackingCandidateLabels(),
    av = stackingCandidateAvailable(),
    nf = stackingCandidateNFeatures(),
    selected = selectedStackingAnalyses();
  if (!idx.length)
    st.textContent = "No completed first-level analyses are available.";
  idx.forEach((id, k) => {
    let row = document.createElement("label");
    row.className = "checkitem";
    let cb = document.createElement("input");
    cb.type = "checkbox";
    cb.value = id;
    cb.checked = selected.includes(id);
    cb.disabled = !av[k];
    let lab = document.createElement("span");
    lab.textContent =
      (labs[k] || `Analysis ${id}`) +
      ` (${nf[k] || 1} feature${Number(nf[k] || 1) === 1 ? "" : "s"})` +
      (av[k] ? "" : " [unavailable]");
    row.appendChild(cb);
    row.appendChild(lab);
    list.appendChild(row);
  });
  document.getElementById("stackingAnalysisModal").classList.add("open");
}
/**
 * closeStackingSelector  Close the stacking selector panel or dialog without changing authoritative MATLAB state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function closeStackingSelector() {
  document.getElementById("stackingAnalysisModal").classList.remove("open");
}
/**
 * confirmStackingSelector  Return or update the confirm stacking selector control used by the page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function confirmStackingSelector() {
  let list = document.getElementById("stackingAnalysisList");
  let vals = Array.from(
    list.querySelectorAll("input[type=checkbox]:checked"),
  ).map((x) => Number(x.value));
  vals = [...new Set(vals)].filter((x) => Number.isFinite(x));
  if (vals.length < 2) {
    document.getElementById("stackingAnalysisStatus").textContent =
      "Select at least two completed first-level analyses.";
    return;
  }
  STATE.stackingSelectedAnalyses = vals;
  markMenuChanged("stackingSelectedAnalyses");
  closeStackingSelector();
  render();
}
document.getElementById("chooseStackingAnalyses").onclick =
  openStackingSelector;
document.getElementById("cancelStackingSelection").onclick =
  closeStackingSelector;
document.getElementById("confirmStackingSelection").onclick =
  confirmStackingSelector;
/**
 * mlModuleName  Provide the ml module name helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function mlModuleName(v) {
  return Number(STATE.fusionFlag || 0) === 3 && !isStacking()
    ? `ml_var${v}`
    : "ml_global";
}
/**
 * preprocModuleIndex  Provide the preproc module index helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function preprocModuleIndex(v) {
  let f = Number(STATE.fusionFlag || 0);
  let ms = arr(STATE.fusionModalities).map(Number);
  return f === 1 ? (ms.length ? ms[0] : v) : v;
}
/**
 * preprocModuleName  Provide the preproc module name helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function preprocModuleName(v) {
  return isStacking()
    ? "preproc_stacking"
    : `preproc_var${preprocModuleIndex(v)}`;
}
/**
 * preprocAvailabilityMessage  Provide the preproc availability message helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function preprocAvailabilityMessage() {
  let issues = arr(STATE.preprocAvailabilityIssues);
  return issues.length || STATE.preprocAvailabilityInvalid
    ? STATE.preprocAvailabilityMessage ||
        "A stored preprocessing step is not applicable in the current modality context."
    : "";
}
/**
 * preprocNeedsReview  Provide the preproc needs review helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function preprocNeedsReview() {
  return !!(STATE.preprocNeedsReview || STATE.preprocMixedEarlyFusionIllegal || STATE.preprocAvailabilityInvalid);
}
/**
 * preprocIllegalMessage  Provide the preproc illegal message helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function preprocIllegalMessage() {
  let msg = [];
  if (STATE.preprocMixedEarlyFusionIllegal)
    msg.push(
      STATE.preprocMixedEarlyFusionMessage ||
        "Mixed early-fusion preprocessing contains incompatible imaging-specific steps.",
    );
  let av = preprocAvailabilityMessage();
  if (av) msg.push(av);
  return msg.join("\n");
}
/**
 * activePreprocSummaryText  Build the active preproc summary text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function activePreprocSummaryText() {
  let base = "";
  if (isStacking())
    base =
      STATE.stackingPreprocSummary ||
      STATE.preprocSummary ||
      "No preprocessing status available.";
  else {
    let idx = preprocModuleIndex(Number(STATE.activeModality || 1));
    let summaries = arr(STATE.preprocSummaries);
    base =
      idx >= 1 && summaries[idx - 1]
        ? summaries[idx - 1]
        : STATE.preprocSummary || "No preprocessing status available.";
  }
  let msg = preprocIllegalMessage();
  return msg ? msg + "\n" + base : base;
}
/**
 * auditSeverity  Provide the audit severity helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function auditSeverity() {
  if (STATE.readinessDiagnostic) return "warning";
  let s =
    STATE.auditSummary && STATE.auditSummary.severity
      ? String(STATE.auditSummary.severity).toLowerCase()
      : "ok";
  return ["error", "warning", "ok"].includes(s) ? s : "ok";
}
/**
 * auditSummaryText  Build the audit summary text shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function auditSummaryText() {
  let summary = STATE.auditSummary && STATE.auditSummary.displayText
    ? STATE.auditSummary.displayText : "Configuration audit not available for this session.";
  return STATE.readinessDiagnostic
    ? "Configuration not yet complete: " + STATE.readinessDiagnostic + "\n" + summary
    : summary;
}
/**
 * auditTopMessage  Provide the audit top message helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function auditTopMessage() {
  if (STATE.readinessDiagnostic)
    return { text: "Configuration not yet complete: " + STATE.readinessDiagnostic + ". Complete the indicated settings before creating an analysis.", kind: "warning" };
  let s = auditSeverity();
  if (s !== "error" && s !== "warning") return null;
  let pp = preprocIllegalMessage();
  if (pp) return { text: pp, kind: s === "error" ? "danger" : "warning" };
  let it =
    STATE.auditSummary && STATE.auditSummary.topItem
      ? STATE.auditSummary.topItem
      : null;
  let txt = "";
  if (it && it.title) {
    txt = String(it.title);
    if (it.message) txt += ": " + String(it.message);
  } else txt = auditSummaryText();
  return { text: txt, kind: s === "error" ? "danger" : "warning" };
}
/**
 * renderAuditSummary  Render the audit summary UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderAuditSummary() {
  let fld = document.getElementById("auditField"),
    sum = document.getElementById("auditSummary");
  if (!fld || !sum) return;
  let sev = auditSeverity();
  sum.textContent = auditSummaryText();
  fld.classList.toggle("dangerField", sev === "error");
  fld.classList.toggle("warningField", sev === "warning");
  fld.classList.toggle("okField", sev === "ok");
  let auditMessage = auditTopMessage();
  if (auditMessage) window.NMUIMessageTools.setMessage(auditMessage.text, auditMessage.kind, "nm-audit");
  else window.NMUIMessageTools.clearMessage("nm-audit");
}
/**
 * currentViewMode  Provide the current view mode helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function currentViewMode() {
  return String(STATE.uiViewMode || "menu") === "canvas" ? "canvas" : "menu";
}
/**
 * canvasFlowOrientation  Return whether the canvas flow orientation condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasFlowOrientation() {
  let v = String(STATE.canvasFlowOrientation || "horizontal").toLowerCase();
  return v === "vertical" ? "vertical" : "horizontal";
}
/**
 * updateCanvasMenuStrip  Update canvas menu strip state or markup after user interaction or bridge refresh.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function updateCanvasMenuStrip() {
  let strip = document.getElementById("canvasMenuStrip");
  if (!strip) return;
  let isMulti = !!(STATE.multiAvailable || STATE.isMultiClassProblem);
  strip.querySelectorAll("button[data-open]").forEach((b) => {
    let targetId = b.getAttribute("data-open") || "";
    let target = targetId ? document.getElementById(targetId) : null;
    let hidden = false;
    if (target && target.classList.contains("hidden")) hidden = true;
    if (
      (b.getAttribute("data-requires") || "") === "multiAvailable" &&
      !isMulti
    )
      hidden = true;
    if (
      (b.getAttribute("data-requires") || "") === "multiLabelAvailable" &&
      (!STATE.multiLabelAvailable || altEnabled())
    )
      hidden = true;
    b.classList.toggle("hidden", hidden);
  });
  let orientBtn = document.getElementById("toggleCanvasOrientation");
  if (orientBtn)
    orientBtn.textContent =
      canvasFlowOrientation() === "vertical"
        ? "Flow: vertical"
        : "Flow: horizontal";
}
/**
 * renderViewMode  Render the view mode UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderViewMode() {
  let mode = currentViewMode();
  document.body.classList.toggle("canvasMode", mode === "canvas");
  let mv = document.getElementById("menuView"),
    cv = document.getElementById("canvasView"),
    btn = document.getElementById("toggleCanvasView");
  if (mv) mv.classList.toggle("hidden", mode === "canvas");
  if (cv) cv.classList.toggle("hidden", mode !== "canvas");
  if (btn) btn.textContent = mode === "canvas" ? "Menu view" : "Canvas view";
  updateCanvasMenuStrip();
  updateCanvasInspectorShell();
}
/**
 * canvasInspectorIsCollapsed  Return whether the canvas inspector is collapsed condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasInspectorIsCollapsed() {
  return !!canvasInspectorCollapsed;
}
/**
 * updateCanvasInspectorShell  Update canvas inspector shell state or markup after user interaction or bridge refresh.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function updateCanvasInspectorShell() {
  const layout = document.querySelector("#canvasView .canvasLayout");
  const collapseBtn = document.getElementById("canvasInspectorCollapse");
  const expandBtn = document.getElementById("canvasInspectorExpand");
  if (layout) layout.classList.toggle("inspectorCollapsed", canvasInspectorIsCollapsed());
  if (collapseBtn) {
    collapseBtn.textContent = "×";
    collapseBtn.title = "Collapse info panel";
    collapseBtn.setAttribute("aria-label", "Collapse info panel");
  }
  if (expandBtn) {
    expandBtn.classList.toggle("hidden", !canvasInspectorIsCollapsed());
    expandBtn.title = "Expand info panel";
    expandBtn.setAttribute("aria-label", "Expand info panel");
  }
}
/**
 * setCanvasInspectorCollapsed  Provide the set canvas inspector collapsed helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setCanvasInspectorCollapsed(flag) {
  canvasInspectorCollapsed = !!flag;
  updateCanvasInspectorShell();
  if (!canvasInspectorCollapsed) {
    hideCanvasNodeInfoPopover();
    const sel = canvasNodes().find((n) => String(n.id || "") === String(selectedCanvasNodeId || ""));
    if (sel) renderCanvasDetails(sel);
  } else {
    hideCanvasNodeInfoPopover();
  }
  try { window.dispatchEvent(new Event("resize")); } catch (e) {}
}
/**
 * canvasNodes  Return whether the canvas nodes condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasNodes() {
  let c = STATE.canvas || {};
  return arr(c.nodes);
}
/**
 * canvasEdges  Return whether the canvas edges condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasEdges() {
  let c = STATE.canvas || {};
  return arr(c.edges);
}
/**
 * canvasStatusClass  Return whether the canvas status class condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasStatusClass(s) {
  s = String(s || "ok").toLowerCase();
  return ["ok", "info", "warning", "error", "inactive", "committed"].includes(s) ? s : "ok";
}
/**
 * canvasSafeId  Return whether the canvas safe id condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasSafeId(s) {
  return String(s || "").replace(/[^a-zA-Z0-9_:-]/g, "_");
}
/**
 * canvasCVScopeSubtitle  Return whether the canvas cvscope subtitle condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasCVScopeSubtitle(n) {
  const sub = String((n && n.subtitle) || "").replace(/\s+/g, " ").trim();
  if (sub) return sub;
  const cv = (STATE && STATE.cv && typeof STATE.cv === "object") ? STATE.cv : {};
  /**
   * one  Provide the one helper used by training-template configurator browser page.
   * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  const one = (prefix, defPerm, defFold) => {
    const mode = String(cv[`cv${prefix}Mode`] || "kfold").toLowerCase();
    if (mode.includes("loo")) return "LOO";
    if (mode.includes("group")) {
      const p = Number(cv[`cv${prefix}Perm`] || NaN);
      return Number.isFinite(p) && p > 0 ? `${p} x grouped` : "grouped";
    }
    const p = Number(cv[`cv${prefix}Perm`] || defPerm);
    const f = Number(cv[`cv${prefix}Fold`] || defFold);
    if (Number.isFinite(p) && Number.isFinite(f) && p > 0 && f > 0) return `${p} x ${f}`;
    if (Number.isFinite(f) && f > 0) return `${f} folds`;
    return "configured";
  };
  return `CV2: ${one("Outer", 10, 10)} | CV1: ${one("Inner", 10, 10)}`;
}
/**
 * canvasLayout  Return whether the canvas layout condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasLayout(nodes, edges) {
  let scopeNodes = nodes.filter(
    (n) =>
      String(n.shape || "") == "scope" ||
      String(n.type || "") === "partition_scope",
  );
  let flowNodes = nodes.filter(
    (n) =>
      !(
        String(n.shape || "") == "scope" ||
        String(n.type || "") === "partition_scope"
      ),
  );
  let groups = {};
  flowNodes.forEach((n) => {
    let lane = Number(n.lane || 10);
    if (!Number.isFinite(lane)) lane = 10;
    if (!groups[lane]) groups[lane] = [];
    groups[lane].push(n);
  });
  let lanes = Object.keys(groups)
    .map(Number)
    .sort((a, b) => a - b);
  lanes.forEach((l) =>
    groups[l].sort(
      (a, b) =>
        Number(a.order || 0) - Number(b.order || 0) ||
        String(a.title || "").localeCompare(String(b.title || "")),
    ),
  );
  let pos = {},
    headers = {};
  let orient = canvasFlowOrientation();
  const hasEnsembleContainer = flowNodes.some(
    (n) =>
      String(n.shape || "") === "container" &&
      String(n.type || "").toLowerCase() === "model_selection",
  );
  let marginX = orient === "vertical" ? 176 : 34,
    marginY = 58,
    dx = 272,
    dy = orient === "vertical" && hasEnsembleContainer ? 200 : 136,
    w = 178,
    h = 92;
  let maxRows = 1;
  /**
   * explicitRow  Provide the explicit row helper used by training-template configurator browser page.
   * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
   */
  function explicitRow(n) {
    let r = Number(n && n.row);
    return n &&
      n.row !== null &&
      n.row !== undefined &&
      n.row !== "" &&
      Number.isFinite(r)
      ? r
      : null;
  }
  lanes.forEach((lane, col) => {
    let g = groups[lane];
    let rowExtent = 0;
    g.forEach((n, i) => {
      let r = explicitRow(n);
      rowExtent = Math.max(rowExtent, r === null ? i : r);
    });
    maxRows = Math.max(maxRows, Math.ceil(rowExtent + 1));
    let hdr = "";
    for (let i = 0; i < g.length; i++) {
      if (g[i].columnLabel) {
        hdr = String(g[i].columnLabel);
        break;
      }
    }
    if (!hdr) hdr = canvasDefaultColumnLabel(g, lane, col);
    headers[lane] = hdr;
    g.forEach((n, autoRow) => {
      let rr = explicitRow(n);
      let row = rr === null ? autoRow : rr;
      let x = marginX + col * dx,
        y = marginY + row * dy;
      if (orient === "vertical") {
        x = marginX + row * dx;
        y = marginY + col * dy;
      }
      pos[String(n.id || "")] = {
        x: x,
        y: y,
        w: w,
        h: h,
        lane: lane,
        col: col,
        row: row,
      };
    });
  });
  let width, height;
  if (orient === "vertical") {
    width = Math.max(1080, marginX * 2 + maxRows * dx + w);
    height = Math.max(560, marginY * 2 + Math.max(1, lanes.length) * dy + h);
  } else {
    width = Math.max(1080, marginX * 2 + Math.max(1, lanes.length) * dx + w);
    height = Math.max(560, marginY * 2 + maxRows * dy + h);
  }
  let scopeBounds = {};
  scopeNodes.forEach((sn) => {
    let stack = isStacking();
    let vals = flowNodes
      .filter((n) => {
        let g = String(n.group || "").toLowerCase();
        let t = String(n.type || "").toLowerCase();
        if (stack) return true;
        return !(
          g === "data" ||
          g === "modality" ||
          t === "input" ||
          t === "modality"
        );
      })
      .map((n) => pos[String(n.id || "")])
      .filter(Boolean);
    if (!vals.length) return;
    let rawMinX = Math.min(...vals.map((v) => v.x)),
      rawMinY = Math.min(...vals.map((v) => v.y)),
      rawMaxX = Math.max(...vals.map((v) => v.x + v.w)),
      rawMaxY = Math.max(...vals.map((v) => v.y + v.h));
    let minX = rawMinX - (orient === "vertical" ? 92 : 42),
      minY = rawMinY - (orient === "vertical" ? 8 : 54),
      maxX = rawMaxX + 42,
      maxY = rawMaxY + 42;
    minX = Math.max(8, minX);
    minY = Math.max(40, minY);
    scopeBounds[String(sn.id || "")] = {
      x: minX,
      y: minY,
      w: Math.max(220, maxX - minX),
      h: Math.max(160, maxY - minY),
    };
    width = Math.max(width, maxX + marginX);
    height = Math.max(height, maxY + marginY);
  });
  return {
    pos: pos,
    width: width,
    height: height,
    w: w,
    h: h,
    groups: groups,
    lanes: lanes,
    headers: headers,
    marginX: marginX,
    marginY: marginY,
    dx: dx,
    dy: dy,
    orientation: orient,
    scopeNodes: scopeNodes,
    scopeBounds: scopeBounds,
    flowNodes: flowNodes,
  };
}
/**
 * canvasDefaultColumnLabel  Return whether the canvas default column label condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasDefaultColumnLabel(g, lane, col) {
  let types = g.map((n) => String(n.type || "").toLowerCase());
  if (types.some((t) => t.includes("modality") || t.includes("input")))
    return "Input";
  if (types.some((t) => t.includes("partition"))) return "Partition";
  if (types.some((t) => t.includes("augmentation"))) return "Synthetic data";
  if (types.some((t) => t.includes("preproc"))) {
    let step = Number(g[0].stepIndex || 0);
    return step > 0 ? `Preprocessing: Step ${step}` : "Preprocessing";
  }
  if (types.some((t) => t.includes("learner") || t.includes("meta_learner")))
    return "Learner";
  if (types.some((t) => t.includes("fusion"))) return "Fusion / decision";
  if (types.some((t) => t.includes("model_selection"))) return "Ensemble";
  if (types.some((t) => t.includes("output"))) return "Outputs";
  return `Stage ${col + 1}`;
}
/**
 * svgEl  Provide the svg el helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function svgEl(name, attrs) {
  let e = document.createElementNS("http://www.w3.org/2000/svg", name);
  Object.entries(attrs || {}).forEach(([k, v]) => e.setAttribute(k, String(v)));
  return e;
}
/**
 * svgText  Build the svg text shown to users in the browser UI.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function svgText(parent, text, x, y, cls, maxChars, maxLines) {
  let words = String(text || "")
    .split(/\s+/)
    .filter(Boolean);
  let lines = [],
    cur = "";
  maxChars = maxChars || 24;
  maxLines = maxLines || 2;
  words.forEach((w) => {
    let trial = cur ? cur + " " + w : w;
    if (trial.length > maxChars && cur) {
      lines.push(cur);
      cur = w;
    } else cur = trial;
  });
  if (cur) lines.push(cur);
  lines = lines.slice(0, maxLines);
  if (
    lines.length === maxLines &&
    words.join(" ").length > lines.join(" ").length
  )
    lines[maxLines - 1] = lines[maxLines - 1].replace(/\.*$/, "") + "...";
  lines.forEach((ln, i) => {
    let t = svgEl("text", { x: x, y: y + i * 13, class: cls });
    t.textContent = ln;
    parent.appendChild(t);
  });
}
/**
 * exportCanvasSVG  Provide the export canvas svg helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function exportCanvasSVG() {
  let svg = document.querySelector("#flowCanvas svg");
  if (!svg) {
    status("No SVG canvas is available for export.", "warning");
    return;
  }
  let clone = svg.cloneNode(true);
  clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  let style = document.createElementNS("http://www.w3.org/2000/svg", "style");
  style.setAttribute("type", "text/css");
  style.textContent = `.flowLink{fill:none;stroke:#94a3b8;stroke-width:2}.cvScopeBox{fill:#f8fafc;stroke:#0f5c78;stroke-width:2;stroke-dasharray:7 5;opacity:.42}.cvScopeTitle{font-size:14px;font-weight:800;fill:#0f3750}.cvScopeHint{font-size:11px;fill:#475569}.cvScopeG{cursor:pointer}.cvScopeG.warning .cvScopeBox{stroke:#f59e0b;fill:#fffbeb}.cvScopeG.error .cvScopeBox{stroke:#dc2626;fill:#fef2f2}.flowLink.augmentation_input{stroke:#60a5fa}.flowLink.late_fusion,.flowLink.stacking_input{stroke-width:2.5}.flowNodeBox{fill:#fff;stroke:#cbd5e1;stroke-width:1.5}.flowNodeStripe{stroke-width:5}.flowNodeTextTitle{font:700 13px system-ui,-apple-system,Segoe UI,Arial,sans-serif;fill:#1f2933}.flowNodeTextSub{font:10.5px system-ui,-apple-system,Segoe UI,Arial,sans-serif;fill:#667085}.flowNodeTextSum{font:10.5px system-ui,-apple-system,Segoe UI,Arial,sans-serif;fill:#344054}.laneLabel{font:700 11px system-ui,-apple-system,Segoe UI,Arial,sans-serif;fill:#64748b;text-transform:uppercase}.laneHeaderBox{fill:#f8fafc;stroke:#d8dee4;stroke-width:1}.flowNodeG.ok .flowNodeStripe{stroke:#3b82f6}.flowNodeG.committed .flowNodeStripe,.flowNodeG.data:not(.warning):not(.error) .flowNodeStripe{stroke:#22c55e}.cvScopeG.committed .cvScopeBox{stroke:#22c55e;fill:#f0fdf4}.flowNodeG.info .flowNodeStripe{stroke:#3b82f6}.flowNodeG.warning .flowNodeStripe{stroke:#f59e0b}.flowNodeG.error .flowNodeStripe{stroke:#dc2626}.flowNodeG.inactive{opacity:.55}.flowNodeInfoCircle{fill:#eef2f7;stroke:#b7c3d0;stroke-width:1.2}.flowNodeInfoText{font:700 11px system-ui,-apple-system,Segoe UI,Arial,sans-serif;fill:#334155;dominant-baseline:middle;text-anchor:middle;pointer-events:none}.flowNodeG.stacking .flowNodeStripe{stroke:#f97316}.flowNodeG.stacking .flowNodeBox{fill:#fff7ed}.flowNodeG.warning .flowNodeBox{fill:#fffbeb}.flowNodeG.error .flowNodeBox{fill:#fef2f2}`;
  clone.insertBefore(style, clone.firstChild);
  let txt =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    new XMLSerializer().serializeToString(clone);
  let blob = new Blob([txt], { type: "image/svg+xml;charset=utf-8" });
  let url = URL.createObjectURL(blob);
  let a = document.createElement("a");
  a.href = url;
  a.download = "NM_train_template_canvas.svg";
  document.body.appendChild(a);
  a.click();
  setTimeout(() => {
    URL.revokeObjectURL(url);
    a.remove();
  }, 1000);
}
/**
 * renderCanvas  Render the canvas UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCanvas() {
  let box = document.getElementById("flowCanvas");
  if (!box) return;
  box.innerHTML = "";
  let nodes = canvasNodes();
  let edges = canvasEdges();
  if (STATE.canvasDirty) {
    let d = document.createElement("div");
    d.className = "summary canvasDirtyNotice";
    d.textContent = STATE.canvasDirtyReason || "Canvas refresh is pending.";
    box.appendChild(d);
    if (!nodes.length) return;
  }
  if (!nodes.length) {
    let d = document.createElement("div");
    d.className = "summary";
    d.textContent = "No canvas model is available for the current analysis.";
    box.appendChild(d);
    return;
  }
  let layout = canvasLayout(nodes, edges);
  let svg = svgEl("svg", {
    class: "flowSvg",
    viewBox: `0 0 ${layout.width} ${layout.height}`,
    width: layout.width,
    height: layout.height,
  });
  let defs = svgEl("defs", {});
  let marker = svgEl("marker", {
    id: "arrow",
    viewBox: "0 0 10 10",
    refX: "9",
    refY: "5",
    markerWidth: "7",
    markerHeight: "7",
    orient: "auto-start-reverse",
  });
  marker.appendChild(
    svgEl("path", { d: "M 0 0 L 10 5 L 0 10 z", fill: "#94a3b8" }),
  );
  defs.appendChild(marker);
  svg.appendChild(defs);
  (layout.scopeNodes || []).forEach((n) => {
    let id = String(n.id || ""),
      b = (layout.scopeBounds || {})[id];
    if (!b) return;
    let g = svgEl("g", {
      class: "cvScopeG " + canvasStatusClass(n.status),
      "data-node-id": id,
    });
    g.appendChild(
      svgEl("rect", {
        x: b.x,
        y: b.y,
        width: b.w,
        height: b.h,
        rx: 20,
        ry: 20,
        class: "cvScopeBox",
      }),
    );
    const verticalScope = layout.orientation === "vertical";
    let title = svgEl("text", {
      x: verticalScope ? b.x + b.w - 18 : b.x + 18,
      y: verticalScope ? b.y + 26 : b.y + 26,
      class: "cvScopeTitle",
      "text-anchor": verticalScope ? "end" : "start",
    });
    title.textContent = verticalScope
      ? "CV / partitioning"
      : n.title || "Cross-validation / partitioning";
    g.appendChild(title);
    if (layout.orientation !== "vertical") {
      let hint = svgEl("text", {
        x: b.x + 18,
        y: b.y + 43,
        class: "cvScopeHint",
      });
      hint.textContent = canvasCVScopeSubtitle(n);
      g.appendChild(hint);
    }
    g.onclick = (ev) => {
      ev.stopPropagation();
      selectedCanvasNodeId = id;
      renderCanvasDetails(n);
    };
    g.ondblclick = (ev) => {
      ev.stopPropagation();
      openCanvasNode(n);
    };
    svg.appendChild(g);
  });
  layout.lanes.forEach((lane) => {
    let first = layout.pos[String(layout.groups[lane][0].id || "")];
    if (!first) return;
    if (layout.orientation === "vertical") {
      let rect = svgEl("rect", {
        x: 16,
        y: first.y - 34,
        width: Math.max(180, layout.width - 32),
        height: 24,
        rx: 6,
        ry: 6,
        class: "laneHeaderBox",
      });
      svg.appendChild(rect);
      svgText(
        svg,
        layout.headers[lane] || "Stage",
        24,
        first.y - 18,
        "laneLabel",
        38,
        1,
      );
    } else {
      let rect = svgEl("rect", {
        x: first.x,
        y: 16,
        width: layout.w,
        height: 24,
        rx: 6,
        ry: 6,
        class: "laneHeaderBox",
      });
      svg.appendChild(rect);
      svgText(
        svg,
        layout.headers[lane] || "Stage",
        first.x + 8,
        32,
        "laneLabel",
        24,
        1,
      );
    }
  });
  /**
   * canvasContainerBounds  Return whether the canvas container bounds condition holds for the current UI state.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function canvasContainerBounds(n) {
    if (!n || String(n.shape || "") !== "container") return null;
    const childIds = arr(n.children).map((x) => String(x || "")).filter(Boolean);
    if (!childIds.length) return null;
    const childPos = childIds.map((id) => layout.pos[id]).filter(Boolean);
    if (!childPos.length) return null;
    const isEnsembleContainer = String(n.type || "").toLowerCase() === "model_selection";
    const topPad = isEnsembleContainer ? 56 : 32;
    const bottomPad = isEnsembleContainer ? 34 : 14;
    const minX = Math.min(...childPos.map((p) => p.x)) - 14;
    const minY = Math.min(...childPos.map((p) => p.y)) - topPad;
    const maxX = Math.max(...childPos.map((p) => p.x + p.w)) + 14;
    const maxY = Math.max(...childPos.map((p) => p.y + p.h)) + bottomPad;
    return {
      x: minX,
      y: minY,
      w: Math.max(220, maxX - minX),
      h: Math.max(isEnsembleContainer ? 156 : 126, maxY - minY),
    };
  }
  const containerBounds = {};
  (layout.flowNodes || []).forEach((n) => {
    if (String(n.shape || "") !== "container") return;
    const b = canvasContainerBounds(n);
    if (!b) return;
    const id = String(n.id || "");
    containerBounds[id] = b;
    const g = svgEl("g", {
      class: "flowEnsembleContainerG " + canvasStatusClass(n.status),
      "data-node-id": id,
    });
    g.appendChild(svgEl("rect", {
      x: b.x,
      y: b.y,
      width: b.w,
      height: b.h,
      rx: 14,
      ry: 14,
      class: "flowEnsembleContainerBox",
    }));
    svgText(g, n.title || "Ensemble learning", b.x + 14, b.y + 21, "flowEnsembleContainerTitle", 28, 1);
    svgText(g, n.summary, b.x + 14, b.y + 39, "flowNodeTextSum", 40, 3);
    const infoG = svgEl("g", {
      class: "flowNodeInfo flowEnsembleInfo",
      "data-node-id": id,
    });
    const infoCx = b.x + b.w - 17;
    const infoCy = b.y + b.h - 17;
    infoG.appendChild(svgEl("circle", {
      cx: infoCx,
      cy: infoCy,
      r: 9,
      class: "flowNodeInfoCircle",
    }));
    const infoText = svgEl("text", {
      x: infoCx,
      y: infoCy + 0.5,
      class: "flowNodeInfoText",
    });
    infoText.textContent = "i";
    infoG.appendChild(infoText);
    infoG.onclick = (ev) => handleCanvasInfoClick(n, ev);
    g.appendChild(infoG);
    g.onclick = (ev) => {
      ev.stopPropagation();
      selectedCanvasNodeId = id;
      renderCanvasDetails(n, { deferRich: true });
    };
    g.ondblclick = (ev) => {
      ev.stopPropagation();
      openCanvasNode(n);
    };
    svg.appendChild(g);
  });

  edges.forEach((e) => {
    if (String(e.kind || "") === "cv_context") return;
    const sourceId = String(e.source || "");
    const targetId = String(e.target || "");
    let s = layout.pos[sourceId],
      t = layout.pos[targetId];
    if (!s || !t) return;
    const sourceContainer = containerBounds[sourceId] || null;
    const targetContainer = containerBounds[targetId] || null;
    let d = "",
      labX = 0,
      labY = 0,
      far = false;
    if (layout.orientation === "vertical") {
      const isAuxInput = ["label_input", "covariate_input"].includes(String(e.kind || ""));
      if (isAuxInput) {
        const x1 = sourceContainer ? sourceContainer.x + sourceContainer.w / 2 : s.x + s.w / 2;
        const y1 = sourceContainer ? sourceContainer.y + sourceContainer.h : s.y + s.h;
        const x2 = targetContainer ? targetContainer.x - 8 : t.x - 8;
        const y2 = targetContainer ? targetContainer.y + targetContainer.h / 2 : t.y + t.h / 2;
        d = `M ${x1} ${y1} L ${x1} ${y2} L ${x2} ${y2}`;
        labX = Math.min(x1, x2) + 6;
        labY = y2 - 8;
        far = Math.abs(y2 - y1) > 120 || Math.abs(x2 - x1) > 150;
      } else {
        let x1 = sourceContainer ? sourceContainer.x + sourceContainer.w / 2 : s.x + s.w / 2,
          y1 = sourceContainer ? sourceContainer.y + sourceContainer.h : s.y + s.h,
          x2 = targetContainer ? targetContainer.x + targetContainer.w / 2 : t.x + t.w / 2,
          y2 = targetContainer ? targetContainer.y - 8 : t.y - 8;
        let mid = y1 + Math.max(22, (y2 - y1) / 2);
        if (y2 < y1) {
          mid = y1 + 34;
        }
        d = `M ${x1} ${y1} L ${x1} ${mid} L ${x2} ${mid} L ${x2} ${y2}`;
        labX = (x1 + x2) / 2 + 6;
        labY = Math.min(mid + 12, y2 - 8);
        far = Math.abs(y2 - y1) > 120;
      }
    } else {
      const isAuxInput = ["label_input", "covariate_input"].includes(String(e.kind || ""));
      if (isAuxInput) {
        const x1 = sourceContainer ? sourceContainer.x + sourceContainer.w : s.x + s.w;
        const y1 = sourceContainer ? sourceContainer.y + sourceContainer.h / 2 : s.y + s.h / 2;
        const targetIsRight = (targetContainer ? targetContainer.x : t.x) >= (sourceContainer ? sourceContainer.x : s.x);
        const x2 = targetContainer ? targetContainer.x + targetContainer.w / 2 : t.x + t.w / 2;
        const y2 = targetContainer ? targetContainer.y - 8 : t.y - 8;
        const stepX = targetIsRight ? Math.max(x1 + 22, x2) : Math.min((sourceContainer ? sourceContainer.x : s.x) - 22, x2);
        d = `M ${x1} ${y1} L ${stepX} ${y1} L ${stepX} ${y2}`;
        labX = stepX + (targetIsRight ? 6 : -74);
        labY = Math.min(y1, y2) - 8;
        far = Math.abs(stepX - x1) > 150 || Math.abs(y2 - y1) > 120;
      } else {
        let x1 = sourceContainer ? sourceContainer.x + sourceContainer.w : s.x + s.w,
          y1 = sourceContainer ? sourceContainer.y + sourceContainer.h / 2 : s.y + s.h / 2,
          x2 = targetContainer ? targetContainer.x - 8 : t.x - 8,
          y2 = targetContainer ? targetContainer.y + targetContainer.h / 2 : t.y + t.h / 2;
        let mid = x1 + Math.max(22, (x2 - x1) / 2);
        if (x2 < x1) {
          mid = x1 + 34;
        }
        d = `M ${x1} ${y1} L ${mid} ${y1} L ${mid} ${y2} L ${x2} ${y2}`;
        labX = Math.min(mid + 4, x2 - 74);
        labY = (y1 + y2) / 2 - 5;
        far = Math.abs(x2 - x1) > 150;
      }
    }
    let path = svgEl("path", {
      d: d,
      class: "flowLink " + String(e.kind || "flow"),
      "marker-end": "url(#arrow)",
    });
    svg.appendChild(path);
  });
  nodes.forEach((n) => {
    if (String(n.shape || "") === "container") return;
    let id = String(n.id || ""),
      p = layout.pos[id];
    if (!p) return;
    let accent = String(n.accent || n.group || "").replace(
      /[^a-zA-Z0-9_-]/g,
      "",
    );
    let g = svgEl("g", {
      class:
        "flowNodeG " +
        canvasStatusClass(n.status) +
        " " +
        String(n.shape || "box") +
        " " +
        accent,
      "data-node-id": id,
    });
    if (String(n.shape || "") === "diamond") {
      let pts = `${p.x + p.w / 2},${p.y} ${p.x + p.w},${p.y + p.h / 2} ${p.x + p.w / 2},${p.y + p.h} ${p.x},${p.y + p.h / 2}`;
      g.appendChild(svgEl("polygon", { points: pts, class: "flowNodeBox" }));
      g.appendChild(
        svgEl("line", {
          x1: p.x + 16,
          y1: p.y + p.h - 9,
          x2: p.x + p.w - 16,
          y2: p.y + p.h - 9,
          class: "flowNodeStripe",
        }),
      );
    } else {
      g.appendChild(
        svgEl("rect", {
          x: p.x,
          y: p.y,
          width: p.w,
          height: p.h,
          rx: String(n.shape || "") === "roundbox" ? 14 : 8,
          ry: String(n.shape || "") === "roundbox" ? 14 : 8,
          class: "flowNodeBox",
        }),
      );
      g.appendChild(
        svgEl("line", {
          x1: p.x + 4,
          y1: p.y + 8,
          x2: p.x + 4,
          y2: p.y + p.h - 8,
          class: "flowNodeStripe",
        }),
      );
    }
    svgText(
      g,
      n.title || n.id || "Node",
      p.x + 14,
      p.y + 20,
      "flowNodeTextTitle",
      22,
      1,
    );
    const isInput = n.group === "data" || n.group === "modality";
    if(isInput) svgText(g, n.subtitle, p.x + 14, p.y + 39, "flowNodeTextSub", 27, 1);
    svgText(g, n.summary, p.x + 14, p.y + (isInput ? 59 : 39), "flowNodeTextSum", 28, isInput ? 2 : 3);
    if (canvasNodeNeedsRichDetail(n)) {
      let infoG = svgEl("g", {
        class: "flowNodeInfo",
        "data-node-id": id,
      });
      const infoCx = p.x + p.w - 15;
      const infoCy = p.y + p.h - 15;
      infoG.appendChild(
        svgEl("circle", {
          cx: infoCx,
          cy: infoCy,
          r: 9,
          class: "flowNodeInfoCircle",
        }),
      );
      let infoText = svgEl("text", {
        x: infoCx,
        y: infoCy + 0.5,
        class: "flowNodeInfoText",
      });
      infoText.textContent = "i";
      infoG.appendChild(infoText);
      infoG.onclick = (ev) => handleCanvasInfoClick(n, ev);
      g.appendChild(infoG);
    }
    g.onclick = () => {
      selectedCanvasNodeId = id;
      renderCanvasDetails(n, { deferRich: true });
    };
    g.ondblclick = () => openCanvasNode(n);
    svg.appendChild(g);
  });
  box.appendChild(svg);
  let sel = nodes.find(
    (n) => String(n.id || "") === String(selectedCanvasNodeId || ""),
  );
  if (sel) renderCanvasDetails(sel);
  else if (nodes.length) renderCanvasDetails(nodes[0], { deferRich: true });
}
/**
 * arrayify  Provide the arrayify helper used by training-template configurator browser page.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function arrayify(x) {
  if (x === null || x === undefined) return [];
  return Array.isArray(x) ? x : [x];
}
/**
 * canvasDetailRequestState  Return whether the canvas detail request state condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasDetailRequestState() {
  let s = menuContextState();
  [
    "cv",
    "synth",
    "rfe",
    "multi",
    "vis",
    "mli",
    "sav",
    "audit",
    "cvSummary",
    "synthSummary",
    "rfeSummary",
    "multiSummary",
    "visSummary",
    "mliSummary",
    "savSummary",
    "verbositySummary",
    "mlSummary",
    "mlScope",
    "altLabelSummary",
    "isMultiClassProblem",
    "multiAvailable",
    "modalityLabels",
    "modalityIsImaging",
    "numModalities",
  ].forEach((k) => {
    if (STATE && Object.prototype.hasOwnProperty.call(STATE, k)) s[k] = STATE[k];
  });
  return s;
}
/**
 * canvasNodeNeedsRichDetail  Return whether the canvas node needs rich detail condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasNodeNeedsRichDetail(n) {
  let d = n && n.detail ? n.detail : null;
  if (!d || typeof d !== "object") return false;
  if (d.lazy === true) return true;
  return String(d.mode || "").toLowerCase() === "summary";
}
/**
 * requestCanvasNodeRichDetail  Provide the request canvas node rich detail helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function requestCanvasNodeRichDetail(n) {
  if (!n || !canvasNodeNeedsRichDetail(n)) return;
  let id = String(n.id || "");
  if (!id || canvasDetailInFlight[id]) return;
  canvasDetailInFlight[id] = true;
  try {
    let payloadNode = Object.assign({}, n);
    delete payloadNode.detail;
    let res = await fetch(`http://127.0.0.1:${PORT}/api/matlabservice`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_canvas_detail",
        nodeId: id,
        node: payloadNode,
        state: canvasDetailRequestState(),
        detailMode: "rich",
        timeout: 120,
      }),
    }).then((r) => r.json());
    if (!res || res.ok === false || res.error || !res.detail) {
      let msg = res && (res.message || res.error || res.identifier)
        ? String(res.message || res.error || res.identifier)
        : "Canvas node detail generation failed.";
      status(msg, "error");
      return;
    }
    let nodes = canvasNodes();
    let target = nodes.find((x) => String(x.id || "") === id);
    if (target) target.detail = res.detail;
    if (String(selectedCanvasNodeId || "") === id && target) renderCanvasDetails(target);
    if (target && canvasInspectorIsCollapsed() && String(canvasInfoPopoverNodeId || "") === id) {
      showCanvasNodeInfoPopover(target, null, { preservePosition: true });
    }
  } catch (e) {
    status(e && e.message ? e.message : "Canvas node detail request failed.", "error");
  } finally {
    delete canvasDetailInFlight[id];
  }
}
/**
 * loadCanvasDetailsForAllVisibleNodes  Load canvas details for all visible nodes data from injected state, local cache or the MATLAB bridge.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
async function loadCanvasDetailsForAllVisibleNodes() {
  let nodes = canvasNodes().filter((n) => canvasNodeNeedsRichDetail(n));
  if (!nodes.length) {
    status("All visible canvas cards already have rich details.", "info");
    return;
  }
  for (const n of nodes) {
    await requestCanvasNodeRichDetail(n);
  }
  let selected = canvasNodes().find(
    (n) => String(n.id || "") === String(selectedCanvasNodeId || ""),
  );
  if (selected) renderCanvasDetails(selected);
}

/**
 * canvasDetailHtml  Return whether the canvas detail html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * options.deferRich: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 */
function canvasDetailHtml(n, options) {
  options = options || {};
  let lines = [];
  let det = n && n.detail ? n.detail : null;
  let title = (det && det.title) || n.title || n.id || "Node";
  let sub = (det && det.subtitle) || n.subtitle || "";
  lines.push(`<h2>${escapeHtml(title)}</h2>`);
  if ((n.group === "data" || n.group === "modality") && sub) lines.push(`<div class="muted">${escapeHtml(sub)}</div>`);
  let sections = det ? arrayify(det.sections) : [];
  sections = sections.filter((sec) => sec && typeof sec === "object");
  if (sections.length) {
    let any = false;
    sections.forEach((sec) => {
      let h = sec && sec.heading ? String(sec.heading) : "Configuration";
      let ls = arrayify(sec.lines).filter((x) => String(x || "").trim().length);
      if (!ls.length) return;
      any = true;
      lines.push(`<div class="auditLine"><b>${escapeHtml(h)}</b></div>`);
      ls.forEach((x) => {
        lines.push(`<div class="auditLine">${escapeHtml(x)}</div>`);
      });
    });
    if (!any && n.summary) lines.push(`<p>${escapeHtml(n.summary)}</p>`);
  } else {
    if (n.summary) lines.push(`<p>${escapeHtml(n.summary)}</p>`);
  }
  let warns = det
    ? arrayify(det.warnings).filter((x) => String(x || "").trim().length)
    : [];
  if (warns.length) {
    lines.push(`<div class="auditLine"><b>Warnings</b></div>`);
    warns.forEach((w) =>
      lines.push(`<div class="auditLine warningText">${escapeHtml(w)}</div>`),
    );
  }
  let loadRich = canvasNodeNeedsRichDetail(n) && !options.deferRich;
  if (loadRich)
    lines.push(`<div class="auditLine muted">Use the small information marker on the canvas card to load detailed node information.</div>`);
  let action = det && det.action ? String(det.action) : "";
  if (action)
    lines.push(`<div class="auditLine muted">${escapeHtml(action)}</div>`);
  return lines.join("");
}

/**
 * renderCanvasDetails  Render the canvas details UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCanvasDetails(n, options) {
  let d = document.getElementById("canvasDetailsContent") || document.getElementById("canvasDetails");
  if (!d) return;
  d.innerHTML = canvasDetailHtml(n, options);
}

/**
 * handleCanvasInfoClick  Handle the canvas info click event and translate it into page state or bridge requests.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function handleCanvasInfoClick(n, ev) {
  if (ev) ev.stopPropagation();
  if (!n) return;
  selectedCanvasNodeId = String(n.id || selectedCanvasNodeId || "");
  if (canvasInspectorIsCollapsed()) {
    showCanvasNodeInfoPopover(n, ev && ev.currentTarget ? ev.currentTarget : null);
    requestCanvasNodeRichDetail(n);
  } else {
    renderCanvasDetails(n, { deferRich: true });
    requestCanvasNodeRichDetail(n);
  }
}

/**
 * showCanvasNodeInfoPopover  Provide the show canvas node info popover helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * options.preservePosition: browser-side field consumed from options while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function showCanvasNodeInfoPopover(n, anchorEl, options) {
  options = options || {};
  const box = document.getElementById("canvasNodeInfo");
  const host = document.querySelector("#canvasView .canvasLayout");
  if (!box || !host || !n) return;
  const id = String(n.id || "");
  canvasInfoPopoverNodeId = id;
  box.innerHTML = `<div class="canvasNodeInfoHead"><span class="canvasNodeInfoTitle">Canvas details</span>` +
    `<button type="button" class="canvasNodeInfoClose" aria-label="Close canvas node details">×</button></div>` +
    `<div class="canvasNodeInfoBody">${canvasDetailHtml(n, { deferRich: true })}</div>`;
  const closeBtn = box.querySelector(".canvasNodeInfoClose");
  if (closeBtn) closeBtn.onclick = hideCanvasNodeInfoPopover;
  box.classList.remove("hidden");
  if (anchorEl && !options.preservePosition) {
    const hostRect = host.getBoundingClientRect();
    const aRect = anchorEl.getBoundingClientRect();
    let left = aRect.right - hostRect.left + host.scrollLeft + 12;
    let top = aRect.top - hostRect.top + host.scrollTop - 6;
    box.style.left = `${Math.max(10, left)}px`;
    box.style.top = `${Math.max(10, top)}px`;
    const maxRight = host.scrollLeft + host.clientWidth - 10;
    const overflowR = left + box.offsetWidth - maxRight;
    if (overflowR > 0) {
      const flip = aRect.left - hostRect.left + host.scrollLeft - box.offsetWidth - 12;
      box.style.left = `${Math.max(10, flip)}px`;
    }
    const maxBottom = host.scrollTop + host.clientHeight - 10;
    const overflowB = top + box.offsetHeight - maxBottom;
    if (overflowB > 0) {
      box.style.top = `${Math.max(10, top - overflowB)}px`;
    }
  }
}

/**
 * hideCanvasNodeInfoPopover  Provide the hide canvas node info popover helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function hideCanvasNodeInfoPopover() {
  const box = document.getElementById("canvasNodeInfo");
  canvasInfoPopoverNodeId = "";
  if (box) {
    box.classList.add("hidden");
    box.innerHTML = "";
  }
}

/**
 * escapeHtml  Build the escape html inserted into the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function escapeHtml(s) {
  return String(s || "").replace(
    /[&<>\"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c] || c,
  );
}
/**
 * setCanvasNodeContext  Build the set canvas node context shown to users in the browser UI.
 * It supports training-template configurator browser page at a local helper boundary rather than changing MATLAB-side NeuroMiner state.
 */
function setCanvasNodeContext(n) {
  if (!n) return;
  let m = Number(n.modalityIndex);
  if (Number.isFinite(m) && m >= 1) {
    STATE.activeModality = Math.round(m);
    let sel = document.getElementById("activeModality");
    if (sel) sel.value = String(STATE.activeModality);
    if (Number(STATE.fusionFlag || 0) === 0)
      STATE.fusionModalities = [STATE.activeModality];
  }
  canvasOpenContext = n || null;
}
/**
 * openCanvasModalityDiagnostics  Open the canvas modality diagnostics panel, dialog or linked UI target.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function openCanvasModalityDiagnostics(n) {
  let idx = Number(n && n.modalityIndex ? n.modalityIndex : 0);
  if (!Number.isFinite(idx) || idx < 1) {
    status("No valid modality is linked to this canvas card.", "warning");
    return;
  }
  selectedCanvasNodeId = String(n.id || selectedCanvasNodeId || "");
  renderCanvasDetails(n, { deferRich: true });
  try {
    let res = await fetch(API("/api/matlabservice"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        operation: "train_template_modality_diagnostics",
        modalityIndex: idx,
        timeout: 120,
      }),
    }).then((r) => r.json());
    if (!res || res.ok === false || res.error) {
      throw new Error((res && (res.message || res.error)) || "Modality diagnostics could not be loaded.");
    }
    renderCanvasModalityDiagnosticsModal(res, idx);
  } catch (e) {
    status(`ERROR loading modality diagnostics: ${e.message || String(e)}`, "danger");
  }
}

/**
 * openCanvasDataDashboard  Open the canvas data dashboard panel, dialog or linked UI target.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function openCanvasDataDashboard(kind, n) {
  selectedCanvasNodeId = String((n && n.id) || selectedCanvasNodeId || "");
  if (n) renderCanvasDetails(n, { deferRich: true });
  try {
    let res = await fetch(API("/api/matlabservice"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ operation: "train_template_data_dashboard", kind: kind, timeout: 120 }),
    }).then((r) => r.json());
    if (!res || res.ok === false || res.error) throw new Error((res && (res.message || res.error)) || "Dashboard could not be loaded.");
    renderCanvasDataDashboardModal(res);
  } catch (e) {
    status(`ERROR loading dashboard: ${e.message || String(e)}`, "danger");
  }
}

/**
 * renderCanvasDataDashboardModal  Render the canvas data dashboard modal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCanvasDataDashboardModal(res) {
  const modal = document.getElementById("canvasModalityDiagnosticsModal");
  const titleEl = document.getElementById("canvasModalityDiagTitle");
  const subtitleEl = document.getElementById("canvasModalityDiagSubtitle");
  const bodyEl = document.getElementById("canvasModalityDiagBody");
  if (!modal || !bodyEl) return;
  if (titleEl) titleEl.textContent = res.title || "Dashboard";
  if (subtitleEl) subtitleEl.textContent = res.subtitle || "";
  bodyEl.innerHTML = canvasGenericDataDashboardHtml(res.dashboard || {}, res.kind || "data");
  attachCanvasDashboardChartToggles(bodyEl);
  modal.classList.add("open");
  modal.classList.remove("hidden");
  modal.setAttribute("aria-hidden", "false");
}

/**
 * renderCanvasModalityDiagnosticsModal  Render the canvas modality diagnostics modal UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderCanvasModalityDiagnosticsModal(res, idx) {
  const modal = document.getElementById("canvasModalityDiagnosticsModal");
  const titleEl = document.getElementById("canvasModalityDiagTitle");
  const subtitleEl = document.getElementById("canvasModalityDiagSubtitle");
  const bodyEl = document.getElementById("canvasModalityDiagBody");
  if (!modal || !bodyEl) return;
  if (titleEl) titleEl.textContent = res.title || `Diagnostics modality #${idx}`;
  if (subtitleEl) subtitleEl.textContent = res.subtitle || "Training modality diagnostics.";
  let rows = arrayify(res.rows).filter((r) => r && typeof r === "object");
  let html = [];
  if (rows.length) {
    html.push('<section class="canvasDiagSection"><h3>Modality summary</h3><div class="detailGrid canvasDiagGrid">');
    rows.forEach((row) => {
      html.push(`<div class="detailKey">${escapeHtml(row.key || "")}</div><div>${escapeHtml(row.value === undefined || row.value === null || row.value === "" ? "—" : row.value)}</div>`);
    });
    html.push('</div></section>');
  }
  html.push(canvasQCDashboardHtml(res.qcDashboard || {}, res));
  html.push(canvasSubjectMetadataDashboardHtml(res.metadataDashboard || {}));
  html.push('<section class="canvasDiagSection"><h3>Subject table</h3>');
  html.push('<p class="muted">The subject table lists the stored DataIO preview rows for this modality. It is hidden by default because QC distributions usually provide a clearer first-level quality check.</p>');
  const canShowTable = !!res.hasPersistedPreview;
  const reportButton = res.hasPersistedQCReport ? `<button id="canvasOpenQCReport" type="button">Open ${escapeHtml(res.preview && res.preview.modalityLabel ? res.preview.modalityLabel : 'modality')} QC report</button>` : '';
  html.push(`<div class="buttonRow"><button id="canvasShowInspectionTable" type="button" ${canShowTable ? '' : 'disabled'}>${escapeHtml(res.inspectionButtonLabel || 'Show subject table')}</button>${reportButton}</div>`);
  if (!canShowTable) html.push('<p class="muted">No stored subject table is available for this modality.</p>');
  html.push('<div id="canvasPersistedInspectionArea" class="canvasInspectionArea muted">Subject table hidden.</div>');
  html.push('</section>');
  let diag = arrayify(res.diagnostics).filter((x) => String(x || "").trim().length);
  html.push('<section class="canvasDiagSection"><h3>Messages</h3>');
  if (diag.length) html.push(`<ul>${diag.map((msg) => `<li>${escapeHtml(msg)}</li>`).join("\n")}</ul>`);
  else html.push('<p class="muted">No messages are recorded for this modality.</p>');
  html.push('</section>');
  bodyEl.innerHTML = html.join("\n");
  const showBtn = document.getElementById('canvasShowInspectionTable');
  if (showBtn) showBtn.addEventListener('click', () => renderPersistedCanvasInspection(res));
  const reportBtn = document.getElementById('canvasOpenQCReport');
  if (reportBtn) reportBtn.addEventListener('click', () => openPersistedCanvasQCReport(idx));
  modal.classList.add("open");
  modal.classList.remove("hidden");
  modal.setAttribute("aria-hidden", "false");
}

/**
 * canvasQCDashboardHtml  Return whether the canvas qcdashboard html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasQCDashboardHtml(dash, res) {
  const available = !!(dash && dash.available);
  let html = [];
  html.push('<section class="canvasDiagSection canvasQCDashboardModality"><h3>QC Dashboard</h3>');
  if (!available) {
    const msg = (dash && dash.message) || 'No saved QC results are available for this modality. Run QC in DataIO and save the QC inspection to NM.';
    html.push(`<p class="muted">${escapeHtml(msg)}</p>`);
    html.push('</section>');
    return html.join('\n');
  }
  html.push('<div class="canvasQCSummaryStrip">');
  html.push(canvasQCStatPill('Subjects', formatNumber(dash.nSubjects)));
  html.push(canvasQCStatPill('Features', formatNumber(dash.nFeatures)));
  html.push(canvasQCStatPill('Feature space', dash.featureSpace || '—'));
  html.push(canvasQCStatPill('Primary score', dash.primaryScore || '—'));
  html.push(canvasQCStatPill('Metrics shown', formatNumber(dash.nMetrics)));
  if (Number(dash.nHiddenMetrics || 0) > 0) html.push(canvasQCStatPill('Omitted measures', formatNumber(dash.nHiddenMetrics)));
  html.push('</div>');
  const metrics = arrayify(dash.metrics).filter((m) => m && typeof m === 'object');
  if (!metrics.length) {
    html.push(`<p class="muted">${escapeHtml(dash.message || 'No variable subject-level QC distributions were available.')}</p>`);
  } else {
    html.push('<div class="canvasQCMetricGrid">');
    metrics.forEach((metric) => html.push(canvasQCMetricCardHtml(metric)));
    html.push('</div>');
    const primary = metrics.find((m) => !!m.isPrimary) || metrics[0];
    const outliers = arrayify(primary && primary.topOutliers).filter((r) => r && typeof r === 'object');
    if (outliers.length) html.push(canvasQCTopOutlierTableHtml(primary, outliers));
  }
  if (Number(dash.nHiddenMetrics || 0) > 0) html.push('<p class="muted">Constant or bookkeeping measures are omitted from the charts.</p>');
  if (res && res.hasPersistedQCReport) html.push('<p class="muted">A saved QC report is available from the button in the subject-table section below.</p>');
  html.push('</section>');
  return html.join('\n');
}

/**
 * canvasSubjectMetadataDashboardHtml  Return whether the canvas subject metadata dashboard html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasSubjectMetadataDashboardHtml(dash) {
  const available = !!(dash && dash.available);
  let html = [];
  html.push('<section class="canvasDiagSection"><h3>Subject metadata</h3>');
  if (!available) {
    const msg = (dash && dash.message) || 'No stored global variable or structured covariate summaries are available for this modality.';
    html.push(`<p class="muted">${escapeHtml(msg)}</p>`);
    html.push('</section>');
    return html.join('\n');
  }
  const items = arrayify(dash.items).filter((x) => x && typeof x === 'object' && x.available);
  if (!items.length) {
    html.push(`<p class="muted">${escapeHtml(dash.message || 'No variable subject metadata summaries are available.')}</p>`);
    html.push('</section>');
    return html.join('\n');
  }
  html.push('<div class="canvasQCMetricGrid canvasMetadataGrid">');
  items.forEach((item) => html.push(canvasMetadataCardHtml(item)));
  html.push('</div>');
  if (dash.message) html.push(`<p class="muted">${escapeHtml(dash.message)}</p>`);
  html.push('</section>');
  return html.join('\n');
}

/**
 * canvasGenericDataDashboardHtml  Return whether the canvas generic data dashboard html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasGenericDataDashboardHtml(dash, kind) {
  const available = !!(dash && dash.available);
  let html = [];
  const heading = kind === "labels" ? "Labels" : "Covariates";
  const sectionClass = kind === "covariates" ? "canvasDiagSection canvasDataDashboardCovariates" : "canvasDiagSection canvasDataDashboardLabels";
  html.push(`<section class="${sectionClass}"><h3>${escapeHtml(heading)}</h3>`);
  if (!available) {
    const msg = (dash && dash.message) || `No ${kind} are available.`;
    html.push(`<p class="muted">${escapeHtml(msg)}</p></section>`);
    return html.join("\n");
  }
  const items = arrayify(dash.items).filter((x) => x && typeof x === "object" && x.available);
  if (!items.length) {
    html.push(`<p class="muted">${escapeHtml(dash.message || `No ${kind} summaries are available.`)}</p></section>`);
    return html.join("\n");
  }
  html.push('<div class="canvasQCSummaryStrip">');
  html.push(canvasQCStatPill("Subjects", formatNumber(dash.nSubjects)));
  html.push(canvasQCStatPill(kind === "labels" ? "Label variables" : "Covariates", formatNumber(dash.nItems)));
  if (dash.mode) html.push(canvasQCStatPill("Mode", dash.mode));
  html.push("</div>");
  const gridClass = kind === "covariates" ? "canvasQCMetricGrid canvasMetadataGrid canvasDataVariableStack" : "canvasQCMetricGrid canvasMetadataGrid canvasDataDashboardLabelGrid";
  html.push(`<div class="${gridClass}">`);
  items.forEach((item) => html.push(canvasDataVariableCardHtml(item, { showRole: false, dashboardKind: kind, dashboardMode: dash.mode })));
  html.push("</div>");
  if (dash.message) html.push(`<p class="muted">${escapeHtml(dash.message)}</p>`);
  html.push("</section>");
  return html.join("\n");
}

/**
 * canvasDataVariableCardHtml  Return whether the canvas data variable card html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * item.histCounts: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.histEdges: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.isConstant: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.kind: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.label: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.levels: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.max: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.median: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.message: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.min: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.n: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.nMissing: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.nUnique: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.name: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.p25: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.p75: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.role: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * opts.dashboardKind: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.dashboardMode: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.showRole: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 */
function canvasDataVariableCardHtml(item, opts) {
  opts = opts || {};
  const showRole = opts.showRole !== false;
  const role = (showRole && item.role) ? ` <span class="canvasMetadataRole">${escapeHtml(item.role)}</span>` : "";
  const kind = String(item.kind || "").toLowerCase();
  const dashboardKind = String(opts.dashboardKind || "").toLowerCase();
  const dashboardMode = String(opts.dashboardMode || "").toLowerCase();
  const hasPie = arrayify(item.levels).some((x) => x && typeof x === "object" && Number(x.count) > 0) && Number(item.nUnique) < 100;
  const hasHist = arrayify(item.histCounts).length && !item.isConstant;
  const suppressPie = dashboardKind === "labels" && dashboardMode === "regression";
  const effectiveHasPie = hasPie && !suppressPie;
  const defaultChart = kind === "categorical" && effectiveHasPie ? "pie" : "hist";
  const canSwitch = effectiveHasPie && hasHist;
  let html = [];
  html.push('<article class="canvasQCMetricCard canvasMetadataCard canvasDataVariableCard">');
  html.push(`<div class="canvasQCMetricTitle">${escapeHtml(item.label || item.name || "Variable")}${role}</div>`);
  if (canSwitch) {
    html.push('<div class="canvasChartSwitch" role="group" aria-label="Chart type">');
    html.push(`<button type="button" class="canvasChartSwitchButton${defaultChart === "hist" ? " active" : ""}" data-chart-target="hist">Histogram</button>`);
    html.push(`<button type="button" class="canvasChartSwitchButton${defaultChart === "pie" ? " active" : ""}" data-chart-target="pie">Pie chart</button>`);
    html.push('</div>');
  }
  if (hasHist) html.push(`<div class="canvasChartPane canvasChartPaneHist${defaultChart === "hist" ? "" : " hidden"}">${canvasQCHistogramHtml(item.histCounts, item.histEdges, { showPercentLabels: true, percentDecimals: 1, tickDecimals: 1, axisPx: 760, minTicks: 5, maxTicks: 12 })}</div>`);
  if (effectiveHasPie) html.push(`<div class="canvasChartPane canvasChartPanePie${defaultChart === "pie" ? "" : " hidden"}">${canvasPieChartHtml(item.levels)}</div>`);
  if (!hasHist && !effectiveHasPie) html.push(`<div class="canvasQCHistogram muted">${escapeHtml(item.message || "No distribution chart available")}</div>`);
  html.push('<div class="canvasQCMetricStats canvasDataVariableStats">');
  html.push(`<span>n ${escapeHtml(formatNumber(item.n))}</span>`);
  html.push(`<span>missing ${escapeHtml(formatNumber(item.nMissing))}</span>`);
  if (kind === "categorical") {
    html.push(`<span>levels ${escapeHtml(formatNumber(item.nUnique))}</span>`);
  } else {
    html.push(`<span>median ${escapeHtml(formatNumber(item.median))}</span>`);
    html.push(`<span>IQR ${escapeHtml(formatNumber(item.p25))}–${escapeHtml(formatNumber(item.p75))}</span>`);
    html.push(`<span>range ${escapeHtml(formatNumber(item.min))}–${escapeHtml(formatNumber(item.max))}</span>`);
  }
  html.push("</div>");
  if (item.message) html.push(`<p class="muted canvasMetadataNote">${escapeHtml(item.message)}</p>`);
  html.push("</article>");
  return html.join("\n");
}

/**
 * attachCanvasDashboardChartToggles  Provide the attach canvas dashboard chart toggles helper used by training-template configurator browser page.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function attachCanvasDashboardChartToggles(root) {
  if (!root) return;
  root.querySelectorAll('.canvasDataVariableCard').forEach((card) => {
    const buttons = Array.from(card.querySelectorAll('.canvasChartSwitchButton'));
    if (!buttons.length) return;
    buttons.forEach((btn) => {
      btn.addEventListener('click', () => {
        const target = btn.getAttribute('data-chart-target') || 'hist';
        buttons.forEach((b) => b.classList.toggle('active', b === btn));
        const hist = card.querySelector('.canvasChartPaneHist');
        const pie = card.querySelector('.canvasChartPanePie');
        if (hist) hist.classList.toggle('hidden', target !== 'hist');
        if (pie) pie.classList.toggle('hidden', target !== 'pie');
      });
    });
  });
}

/**
 * canvasPieChartHtml  Return whether the canvas pie chart html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasPieChartHtml(levels) {
  const rows = arrayify(levels).filter((x) => x && typeof x === "object" && Number(x.count) > 0);
  if (!rows.length) return '<div class="canvasQCHistogram muted">No level counts available</div>';
  const total = rows.reduce((a, r) => a + (Number(r.count) || 0), 0) || 1;
  const displayRows = rows.length <= 8 ? rows : rows.slice(0, 7).concat([{
    label: 'Other',
    count: rows.slice(7).reduce((a, r) => a + (Number(r.count) || 0), 0),
    percent: 100 * rows.slice(7).reduce((a, r) => a + (Number(r.count) || 0), 0) / total
  }]);
  const colors = ["#005AB5","#DC3220","#009E73","#F0E442","#6A3D9A","#E66100","#56B4E9","#CC79A7","#8B4513","#4B0092","#1B9E77","#999999","#A6761D","#E7298A","#66A61E","#E6AB02"];
  let acc = 0;
  const cx = 44, cy = 44, r = 34;
  const segs = displayRows.map((r0, idx) => {
    const frac = (Number(r0.count) || 0) / total;
    const fill = colors[idx % colors.length];
    if (frac >= 0.999) return `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}"></circle>`;
    const start = acc * Math.PI * 2 - Math.PI / 2;
    acc += frac;
    const end = acc * Math.PI * 2 - Math.PI / 2;
    const x1 = cx + r * Math.cos(start), y1 = cy + r * Math.sin(start);
    const x2 = cx + r * Math.cos(end), y2 = cy + r * Math.sin(end);
    const large = frac > 0.5 ? 1 : 0;
    return `<path d="M ${cx} ${cy} L ${x1.toFixed(2)} ${y1.toFixed(2)} A ${r} ${r} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)} Z" fill="${fill}"></path>`;
  }).join("");
  const legend = displayRows.map((r0, idx) => `<div class="canvasPieLegendRow"><span class="canvasPieLegendSwatch" style="background:${colors[idx % colors.length]}"></span><span class="canvasPieLegendLabel">${escapeHtml(r0.label || "—")} — ${escapeHtml(formatNumber(r0.count))} (${escapeHtml(formatNumber(r0.percent))}%)</span></div>`).join("");
  return `<div class="canvasPieWrap"><svg viewBox="0 0 88 88" class="canvasPieChart">${segs}</svg><div class="canvasPieLegend">${legend}</div></div>`;
}

/**
 * canvasMetadataCardHtml  Return whether the canvas metadata card html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * item.histCounts: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.histEdges: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.isConstant: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.kind: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.label: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.levels: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.max: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.median: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.message: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.min: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.n: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.nMissing: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.nUnique: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.name: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.p25: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.p75: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 * item.role: browser-side field consumed from item while translating UI state to MATLAB-service requests.
 */
function canvasMetadataCardHtml(item) {
  const role = item.role ? ` <span class="canvasMetadataRole">${escapeHtml(item.role)}</span>` : '';
  let html = [];
  html.push('<article class="canvasQCMetricCard canvasMetadataCard">');
  html.push(`<div class="canvasQCMetricTitle">${escapeHtml(item.label || item.name || 'Subject metadata')}${role}</div>`);
  if (String(item.kind || '').toLowerCase() === 'categorical') {
    html.push(canvasMetadataLevelsHtml(item.levels));
  } else if (arrayify(item.histCounts).length && !item.isConstant) {
    html.push(canvasQCHistogramHtml(item.histCounts, item.histEdges));
  } else {
    html.push(`<div class="canvasQCHistogram muted">${escapeHtml(item.message || 'No distribution chart available')}</div>`);
  }
  html.push('<div class="canvasQCMetricStats">');
  html.push(`<span>n ${escapeHtml(formatNumber(item.n))}</span>`);
  html.push(`<span>missing ${escapeHtml(formatNumber(item.nMissing))}</span>`);
  if (String(item.kind || '').toLowerCase() === 'categorical') {
    html.push(`<span>levels ${escapeHtml(formatNumber(item.nUnique))}</span>`);
  } else {
    html.push(`<span>median ${escapeHtml(formatNumber(item.median))}</span>`);
    html.push(`<span>IQR ${escapeHtml(formatNumber(item.p25))}–${escapeHtml(formatNumber(item.p75))}</span>`);
    html.push(`<span>range ${escapeHtml(formatNumber(item.min))}–${escapeHtml(formatNumber(item.max))}</span>`);
  }
  html.push('</div>');
  if (item.message) html.push(`<p class="muted canvasMetadataNote">${escapeHtml(item.message)}</p>`);
  html.push('</article>');
  return html.join('\n');
}

/**
 * canvasMetadataLevelsHtml  Return whether the canvas metadata levels html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasMetadataLevelsHtml(levels) {
  const rows = arrayify(levels).filter((x) => x && typeof x === 'object');
  if (!rows.length) return '<div class="canvasQCHistogram muted">No level counts available</div>';
  const maxCount = Math.max(1, ...rows.map((r) => Number(r.count) || 0));
  const html = rows.map((r) => {
    const pct = Number(r.percent);
    const w = Math.max(3, Math.round(((Number(r.count) || 0) / maxCount) * 100));
    return `<div class="canvasMetadataLevel"><span class="canvasMetadataLevelLabel">${escapeHtml(r.label || '—')}</span><span class="canvasMetadataLevelBar"><i style="width:${w}%"></i></span><span class="canvasMetadataLevelCount">${escapeHtml(formatNumber(r.count))}${Number.isFinite(pct) ? ` (${escapeHtml(formatNumber(pct))}%)` : ''}</span></div>`;
  }).join('\n');
  return `<div class="canvasMetadataLevels">${html}</div>`;
}

/**
 * canvasQCStatPill  Return whether the canvas qcstat pill condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasQCStatPill(label, value) {
  return `<div class="canvasQCStatPill"><div class="canvasQCStatKey">${escapeHtml(label)}</div><div class="canvasQCStatValue">${escapeHtml(value === undefined || value === null || value === '' ? '—' : value)}</div></div>`;
}

/**
 * canvasQCMetricCardHtml  Return whether the canvas qcmetric card html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasQCMetricCardHtml(metric) {
  const label = metric.label || metric.name || 'QC metric';
  const iqr = `${formatNumber(metric.p25)}–${formatNumber(metric.p75)}`;
  const minmax = `${formatNumber(metric.min)}–${formatNumber(metric.max)}`;
  const cls = metric.isPrimary ? ' canvasQCPrimaryMetric' : '';
  let html = [];
  html.push(`<article class="canvasQCMetricCard${cls}">`);
  html.push(`<div class="canvasQCMetricTitle">${escapeHtml(label)}${metric.isPrimary ? ' <span class="canvasQCPrimaryBadge">primary</span>' : ''}</div>`);
  html.push(canvasQCHistogramHtml(metric.histCounts, metric.histEdges));
  html.push('<div class="canvasQCMetricStats">');
  html.push(`<span>n ${escapeHtml(formatNumber(metric.n))}</span>`);
  html.push(`<span>missing ${escapeHtml(formatNumber(metric.nMissing))}</span>`);
  html.push(`<span>median ${escapeHtml(formatNumber(metric.median))}</span>`);
  html.push(`<span>IQR ${escapeHtml(iqr)}</span>`);
  html.push(`<span>mean ± SD ${escapeHtml(formatNumber(metric.mean))} ± ${escapeHtml(formatNumber(metric.sd))}</span>`);
  html.push(`<span>range ${escapeHtml(minmax)}</span>`);
  html.push('</div>');
  html.push('</article>');
  return html.join('\n');
}

/**
 * canvasQCHistogramHtml  Return whether the canvas qchistogram html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * opts.axisPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.maxTicks: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.minTicks: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.percentDecimals: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.showPercentLabels: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.tickCount: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.tickDecimals: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.tickFontPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.tickMinGapPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 */
function canvasQCHistogramHtml(counts, edges, opts) {
  opts = opts || {};
  const c = arrayify(counts).map(Number).filter((x) => Number.isFinite(x));
  if (!c.length) return '<div class="canvasQCHistogram muted">No histogram data</div>';
  const total = c.reduce((a, v) => a + v, 0) || 1;
  const maxCount = Math.max(1, ...c);
  const showPercentLabels = !!opts.showPercentLabels && c.length <= 30;
  const percentDecimals = Number.isFinite(Number(opts.percentDecimals)) ? Math.max(0, Math.min(3, Math.round(Number(opts.percentDecimals)))) : null;
  const tickDecimals = Number.isFinite(Number(opts.tickDecimals)) ? Math.max(0, Math.min(4, Math.round(Number(opts.tickDecimals)))) : null;
  const bars = c.map((v) => {
    const h = Math.max(3, Math.round((v / maxCount) * 100));
    const pct = 100 * v / total;
    const pctLabel = percentDecimals === null ? formatNumber(pct) : pct.toFixed(percentDecimals);
    const label = showPercentLabels && pct >= 1 ? `<em>${escapeHtml(pctLabel)}%</em>` : '';
    return `<span class="canvasQCHistBar" style="height:${h}%" title="${escapeHtml(formatNumber(v))} (${escapeHtml(formatNumber(pct))}%)">${label}</span>`;
  }).join('');
  const edgeVals = arrayify(edges).map(Number).filter((x) => Number.isFinite(x));
  const tickIdx = canvasSelectAxisTickIndices(edgeVals, {
    axisPx: opts.axisPx,
    minTicks: opts.minTicks,
    maxTicks: opts.maxTicks || opts.tickCount,
    tickDecimals,
    fontPx: opts.tickFontPx,
    minGapPx: opts.tickMinGapPx
  });
  const axis = tickIdx.map((idx) => {
    const x = edgeVals[idx];
    return `<span>${escapeHtml(tickDecimals === null ? formatNumber(x) : x.toFixed(tickDecimals))}</span>`;
  }).join('');
  return `<div class="canvasQCHistogram"><div class="canvasQCHistBars">${bars}</div><div class="canvasQCHistAxis">${axis}</div></div>`;
}

/**
 * canvasSelectAxisTickIndices  Return whether the canvas select axis tick indices condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 * opts.axisPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.fontPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.maxTicks: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.minGapPx: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.minTicks: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * opts.tickDecimals: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 */
function canvasSelectAxisTickIndices(values, opts) {
  opts = opts || {};
  const vals = arrayify(values).map(Number).filter((x) => Number.isFinite(x));
  const n = vals.length;
  if (!n) return [];
  if (n <= 2) return vals.map((_, idx) => idx);
  const tickDecimals = Number.isFinite(Number(opts.tickDecimals)) ? Math.max(0, Math.min(4, Math.round(Number(opts.tickDecimals)))) : null;
  const fontPx = Number.isFinite(Number(opts.fontPx)) ? Math.max(8, Number(opts.fontPx)) : 12;
  const axisPx = Number.isFinite(Number(opts.axisPx)) ? Math.max(80, Number(opts.axisPx)) : 420;
  const minGapPx = Number.isFinite(Number(opts.minGapPx)) ? Math.max(4, Number(opts.minGapPx)) : 18;
  const preferredMinTicks = Math.max(2, Math.round(Number(opts.minTicks) || 2));
  const maxTicks = Math.max(preferredMinTicks, Math.round(Number(opts.maxTicks) || 8));
  const labels = vals.map((x) => tickDecimals === null ? formatNumber(x) : x.toFixed(tickDecimals));
  const maxLabelPx = labels.reduce((mx, label) => Math.max(mx, canvasEstimateTextWidthPx(label, fontPx)), 0);
  const fitTicks = Math.max(2, Math.floor((axisPx + minGapPx) / Math.max(1, maxLabelPx + minGapPx)));
  const targetTicks = Math.max(2, Math.min(maxTicks, fitTicks, n));
  const idx = [];
  for (let i = 0; i < targetTicks; i += 1) {
    const pos = Math.round((i * (n - 1)) / Math.max(1, targetTicks - 1));
    if (!idx.length || idx[idx.length - 1] !== pos) idx.push(pos);
  }
  if (idx[0] !== 0) idx.unshift(0);
  if (idx[idx.length - 1] !== n - 1) idx.push(n - 1);
  return idx.filter((x, i, a) => i === 0 || x !== a[i - 1]);
}

/**
 * canvasEstimateTextWidthPx  Return whether the canvas estimate text width px condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasEstimateTextWidthPx(text, fontPx) {
  const s = String(text == null ? '' : text);
  let units = 0;
  for (let i = 0; i < s.length; i += 1) {
    const ch = s.charAt(i);
    if (/[0-9]/.test(ch)) units += 0.56;
    else if (ch === '.' || ch === ',' || ch === ':' || ch === ';' || ch === '|') units += 0.28;
    else if (ch === '-' || ch === '–' || ch === '+') units += 0.38;
    else units += 0.62;
  }
  return Math.ceil(units * fontPx);
}

/**
 * canvasQCTopOutlierTableHtml  Return whether the canvas qctop outlier table html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasQCTopOutlierTableHtml(metric, outliers) {
  const label = metric && (metric.label || metric.name) ? (metric.label || metric.name) : 'primary QC metric';
  const rows = outliers.map((r) => `<tr><td>${escapeHtml(r.rank || '')}</td><td>${escapeHtml(r.caseId || '')}</td><td>${escapeHtml(formatNumber(r.value))}</td></tr>`).join('\n');
  return `<div class="canvasQCTopOutliers"><h4>Top ${escapeHtml(label)} outliers</h4><div class="tableWrap canvasDiagTableWrap"><table class="canvasDiagTable"><thead><tr><th>Rank</th><th>Case ID</th><th>Value</th></tr></thead><tbody>${rows}</tbody></table></div></div>`;
}

/**
 * formatNumber  Format the number value for labels, tables or status text.
 * It is a normalization helper that makes heterogeneous backend/browser values safe for downstream UI rendering.
 */
function formatNumber(v) {
  const x = Number(v);
  if (!Number.isFinite(x)) return '—';
  const ax = Math.abs(x);
  if (ax !== 0 && (ax >= 100000 || ax < 0.001)) return x.toExponential(3);
  if (ax >= 1000) return x.toFixed(0);
  if (ax >= 100) return x.toFixed(1);
  if (ax >= 10) return x.toFixed(2);
  return x.toFixed(3).replace(/0+$/, '').replace(/\.$/, '');
}

/**
 * canvasModalityPreviewTableHtml  Return whether the canvas modality preview table html condition holds for the current UI state.
 * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
 */
function canvasModalityPreviewTableHtml(rows, preview) {
  let columns = arrayify(preview && preview.columns).map((c) => String(c || '')).filter(Boolean);
  if (!columns.length) columns = ["row", "caseId", "status", "missingness", "notes"];
  const labels = (preview && preview.columnLabels && typeof preview.columnLabels === 'object') ? preview.columnLabels : { row: "Row", caseId: "Case ID", status: "Status", missingness: "Missingness", notes: "Notes" };
  const head = columns.map((c) => `<th>${escapeHtml(labels[c] || c)}</th>`).join("");
  const body = rows.map((r) => `<tr>${columns.map((c) => `<td>${escapeHtml(r[c] === undefined || r[c] === null || r[c] === "" ? "—" : r[c])}</td>`).join("")}</tr>`).join("\n");
  return `<div class="tableWrap canvasDiagTableWrap"><table class="canvasDiagTable"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table></div>`;
}

/**
 * renderPersistedCanvasInspection  Render the persisted canvas inspection UI region from current browser state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function renderPersistedCanvasInspection(res) {
  const area = document.getElementById('canvasPersistedInspectionArea');
  if (!area) return;
  const html = [];
  const tableRows = arrayify(res.previewRows).filter((r) => r && typeof r === "object");
  if (tableRows.length) {
    html.push('<h3>Subject table</h3>');
    html.push('<p class="muted">This table lists the stored DataIO preview rows for this modality. Import/include controls are not shown here.</p>');
    html.push(canvasModalityPreviewTableHtml(tableRows, res.preview || {}));
  } else {
    html.push('<p class="muted">No stored subject-table rows are available for this modality.</p>');
  }
  area.classList.remove('muted');
  area.innerHTML = html.join('\n');
}

/**
 * openPersistedCanvasQCReport  Open the persisted canvas qcreport panel, dialog or linked UI target.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function openPersistedCanvasQCReport(idx) {
  try {
    const res = await fetch(API('/api/matlabservice'), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ operation: 'train_template_open_modality_qc_report', modalityIndex: idx, timeout: 120 })
    }).then((r) => r.json());
    if (!res || res.ok === false || res.error) throw new Error((res && (res.message || res.error)) || 'QC report could not be opened.');
  } catch (e) {
    status(`ERROR opening QC report: ${e.message || String(e)}`, 'danger');
  }
}

/**
 * closeCanvasModalityDiagnosticsModal  Close the canvas modality diagnostics modal panel or dialog without changing authoritative MATLAB state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function closeCanvasModalityDiagnosticsModal() {
  const modal = document.getElementById("canvasModalityDiagnosticsModal");
  if (!modal) return;
  modal.classList.remove("open");
  modal.classList.add("hidden");
  modal.setAttribute("aria-hidden", "true");
}


/**
 * openCanvasNode  Open the canvas node panel, dialog or linked UI target.
 * It is part of the interaction layer that translates user gestures into local UI state or explicit bridge requests.
 */
function openCanvasNode(n) {
  if (!n) {
    status("No canvas node selected.", "info");
    return;
  }
  let typ = String(n.type || "").toLowerCase();
  if ((typ === "modality" || typ === "input") && Number(n.modalityIndex || 0) >= 1) {
    openCanvasModalityDiagnostics(n);
    return;
  }
  if (typ === "label") {
    openCanvasDataDashboard("labels", n);
    return;
  }
  if (typ === "covariate") {
    openCanvasDataDashboard("covariates", n);
    return;
  }
  let action = String(n.action || "open").toLowerCase();
  if (action === "noop") {
    status(
      "This canvas node is informational; no configurator is opened.",
      "info",
    );
    return;
  }
  setCanvasNodeContext(n);
  editorReturnViewMode = currentViewMode();
  let hasDeep = !!(n && Object.prototype.hasOwnProperty.call(n, "deepLink"));
  let cfg = String(
    hasDeep ? n.deepLink || "" : (n && n.configurator) || "",
  ).toLowerCase();
  if (STATE.fullySyntheticMode &&
      !(cfg==='cv'||cfg==='preproc'||cfg==='ml'||
        (cfg==='multi'&&STATE.fullySyntheticMulticlass))) {
    status('Only CV, PREPROC, ML and applicable MULTI are available for SYNTH.', 'warn');
    return;
  }
  if (cfg === "preproc") {
    openEditor("preproc", { context: n });
    return;
  }
  if (cfg === "ml") {
    openEditor("ml", { context: n });
    return;
  }
  let map = {
    altlabel: "openAltLabelConfig",
    label: "openAltLabelConfig",
    cv: "openCVConfig",
    synth: "openSynthConfig",
    multi: "openMULTIConfig",
    rfe: "openRFEConfig",
    vis: "openVISConfig",
    mli: "openMLIConfig",
    sav: "openSAVConfig",
    saving: "openSAVConfig",
    verbosity: "openSAVConfig",
    scaffold: "exportTrainScaffold",
    snapshot: "loadTrainTemplate",
    stacking: "openStackingConfig",
    fusion: "chooseFusionModalities",
  };
  let id = map[cfg];
  let el = id ? document.getElementById(id) : null;
  if (el) {
    el.click();
  } else
    status(
      "No direct configurator link is available for this canvas node.",
      "info",
    );
}
/**
 * prepareMLEditorState  Provide the prepare mleditor state helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function prepareMLEditorState(module) {
  let res = await nmProfiledMatlabService(
    {
      operation: "train_template_prepare_ml",
      module: module || "ml_global",
      timeout: 600,
    },
    "train_template_prepare_ml",
  );
  if (!res || res.ok === false || res.error) {
    throw new Error((res && (res.message || res.error)) || "Machine-learning state preparation failed");
  }
  if (res.editorState && typeof res.editorState === "object") {
    await persistConfiguratorChildState(module || "ml_global", res.editorState, res.__nmClientProfileId);
  }
  nmClientProfileActionLog(
    res.__nmClientProfileId,
    `prepare ML ${module}${res.alreadyPrepared ? " (STATE)" : " (initialized)"} total=${res.__nmClientProfileStartPerf != null ? ((nmClientNow()-res.__nmClientProfileStartPerf)/1000).toFixed(3) : "n/a"}s`,
  );
  return res;
}

/**
 * preparePreprocEditorState  Provide the prepare preproc editor state helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
async function preparePreprocEditorState(module) {
  let res = await nmProfiledMatlabService(
    {
      operation: "train_template_prepare_preproc",
      module: module || "",
      timeout: 600,
    },
    "train_template_prepare_preproc",
  );
  if (!res || res.ok === false || res.error) {
    throw new Error((res && (res.message || res.error)) || "Preprocessing state preparation failed");
  }
  if (res.editorState && typeof res.editorState === "object") {
    await persistConfiguratorChildState(module, res.editorState, res.__nmClientProfileId);
  }
  nmClientProfileActionLog(
    res.__nmClientProfileId,
    `prepare preprocessing ${module}${res.alreadyPrepared ? " (STATE)" : " (initialized)"} total=${res.__nmClientProfileStartPerf != null ? ((nmClientNow()-res.__nmClientProfileStartPerf)/1000).toFixed(3) : "n/a"}s`,
  );
  return res;
}

/**
 * openEditor  Open the editor panel, dialog or linked UI target.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * opts.context: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
async function openEditor(kind, opts) {
  opts = opts || {};
  if (activeEditor) {
    status(
      "Another configuration window is already open. Return to the main configuration menu first.",
      "warn",
    );
    return;
  }
  let ctx = opts.context || canvasOpenContext || {};
  editorReturnViewMode = opts.returnViewMode || editorReturnViewMode || currentViewMode();
  let v = Number(STATE.activeModality || 1);
  let m = Number(ctx.modalityIndex);
  if (Number.isFinite(m) && m >= 1) {
    v = Math.round(m);
    STATE.activeModality = v;
    if (Number(STATE.fusionFlag || 0) === 0) STATE.fusionModalities = [v];
  }
  let module = opts.module || (kind === "preproc" ? preprocModuleName(v) : mlModuleName(v));
  let page =
    kind === "preproc" ? "nm_preproc_pipeline_ui.html" : "nm_train_ml_ui.html";
  activeEditor = kind;
  activeEditorModule = module;
  document.getElementById("modalTitle").textContent =
    kind === "preproc"
      ? "Preprocessing pipeline"
      : "Machine-learning configuration";
  document.getElementById("modalPath").textContent = kind === "preproc"
    ? (isStacking() ? "Stacker preprocessing" : activeModalityHeader())
    : (Number(STATE.fusionFlag) === 3 && !isStacking() ? activeModalityHeader() : "");
  let extra =
    kind === "preproc" && isStacking()
      ? "&forceNonImaging=1&stacking=1"
      : kind === "preproc" &&
          Number(STATE.fusionFlag || 0) === 1 &&
          selectedMixesImaging()
        ? "&forceNonImaging=1&fusionMixed=1"
        : "";
  if (kind === "preproc" && ctx) {
    if (ctx.stage) extra += `&focusStage=${encodeURIComponent(ctx.stage)}`;
    if (ctx.moduleId)
      extra += `&focusModule=${encodeURIComponent(ctx.moduleId)}`;
    if (ctx.stepIndex)
      extra += `&focusStep=${encodeURIComponent(ctx.stepIndex)}`;
  }
  if (opts.restoreNavigation) extra += "&restoreNav=1";
  let prepRes = null;
  if (kind === "preproc") {
    try {
      prepRes = await preparePreprocEditorState(module);
    } catch (e) {
      setActiveEditorFromChild(null);
      status("Could not prepare preprocessing state: " + (e.message || String(e)), "danger");
      return;
    }
  } else if (kind === "ml") {
    try {
      prepRes = await prepareMLEditorState(module);
    } catch (e) {
      activeEditor = null;
      activeEditorModule = "";
      status("Could not prepare machine-learning state: " + (e.message || String(e)), "danger");
      return;
    }
  }
  const profileId = prepRes && prepRes.__nmClientProfileId ? prepRes.__nmClientProfileId : "";
  const profileStartPerf = prepRes && prepRes.__nmClientProfileStartPerf != null ? prepRes.__nmClientProfileStartPerf : nmClientNow();
  const tNavState = nmClientNow();
  await persistTemplateNavigation({ subview: kind, editorKind: kind, editorModule: module, editorReturnViewMode: editorReturnViewMode || currentViewMode() });
  nmClientProfileActionLog(profileId, `child navigation STATE persist=${((nmClientNow()-tNavState)/1000).toFixed(3)}s`);
  const editorProfile = NM_UI_CLIENT_PROFILE ? `&profile=1&nmprofid=${encodeURIComponent(profileId)}` : "";
  const editorUrl = `${page}?port=${encodeURIComponent(PORT)}&module=${encodeURIComponent(module)}&embedded=1${extra}${editorProfile}`;
  const frame = document.getElementById("editorFrame");
  if (NM_UI_CLIENT_PROFILE && frame) {
    frame.addEventListener("load", () => {
      nmClientProfileActionLog(profileId, `${kind} child iframe load/UI-ready total=${((nmClientNow()-profileStartPerf)/1000).toFixed(3)}s`);
    }, { once: true });
  }
  frame.contentWindow.location.replace(window.NMBridgeNavigationURL
    ? window.NMBridgeNavigationURL(editorUrl)
    : editorUrl);
  document.getElementById("modal").classList.add("open");
}
document.getElementById("openPreproc").onclick = () => openEditor("preproc");
document.getElementById("openML").onclick = () => openEditor("ml");
let exportBtn = document.getElementById("exportTrainScaffold");
if (exportBtn) exportBtn.onclick = exportTrainScaffold;
let saveBtn = document.getElementById("saveTrainTemplate");
if (saveBtn) saveBtn.onclick = saveTrainTemplate;
let loadBtn = document.getElementById("loadTrainTemplate");
if (loadBtn) loadBtn.onclick = loadTrainTemplate;
let toggleBtn = document.getElementById("toggleCanvasView");
if (toggleBtn)
  toggleBtn.onclick = async () => {
    if (currentViewMode() === "canvas") {
      STATE.uiViewMode = "menu";
      render();
      await persistTemplateNavigation({ subview: "menu", uiViewMode: "menu" });
      return;
    }
    markCanvasDirty("Loading canvas for the current analysis...");
    STATE.uiViewMode = "canvas";
    render();
    try {
      await applyMenuContext();
      STATE.uiViewMode = "canvas";
      render();
      await persistTemplateNavigation({ subview: "canvas", uiViewMode: "canvas" });
    } catch (e) {
      status("Canvas synchronization failed: " + e.message, "danger");
    }
  };
let orientBtn = document.getElementById("toggleCanvasOrientation");
if (orientBtn)
  orientBtn.onclick = () => {
    STATE.canvasFlowOrientation =
      canvasFlowOrientation() === "vertical" ? "horizontal" : "vertical";
    updateCanvasMenuStrip();
    renderCanvas();
  };
let allDetailsBtn = document.getElementById("loadCanvasDetailsAll");
if (allDetailsBtn) allDetailsBtn.onclick = loadCanvasDetailsForAllVisibleNodes;
let canvasCollapseBtn = document.getElementById("canvasInspectorCollapse");
if (canvasCollapseBtn) canvasCollapseBtn.onclick = () => setCanvasInspectorCollapsed(true);
let canvasExpandBtn = document.getElementById("canvasInspectorExpand");
if (canvasExpandBtn) canvasExpandBtn.onclick = () => setCanvasInspectorCollapsed(false);
let canvasDiagCloseBtn = document.getElementById("closeCanvasModalityDiagnosticsModal");
if (canvasDiagCloseBtn) canvasDiagCloseBtn.onclick = closeCanvasModalityDiagnosticsModal;
let svgBtn = document.getElementById("exportCanvasSVG");
if (svgBtn) svgBtn.onclick = exportCanvasSVG;
let methBtn = document.getElementById("exportMethodsSummary");
if (methBtn) methBtn.onclick = exportMethodsSummary;
let strip = document.getElementById("canvasMenuStrip");
if (strip)
  strip.onclick = (ev) => {
    let b =
      ev.target && ev.target.closest
        ? ev.target.closest("button[data-open]")
        : null;
    let id = b && b.getAttribute ? b.getAttribute("data-open") : "";
    if (id) {
      let el = document.getElementById(id);
      if (el) el.click();
    }
  };
/**
 * closeEditor  Close the editor panel or dialog without changing authoritative MATLAB state.
 * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
 * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
 */
function closeEditor() {
  document.getElementById("editorFrame").contentWindow.location.replace("about:blank");
  document.getElementById("modal").classList.remove("open");
  let rv = editorReturnViewMode || currentViewMode();
  activeEditor = null;
  activeEditorModule = "";
  canvasOpenContext = null;
  if (rv) STATE.uiViewMode = rv;
  render();
  editorReturnViewMode = null;
  persistTemplateNavigation({ subview: rv || "menu", editorKind: "", editorModule: "", editorReturnViewMode: "" })
    .catch((e) => status("Navigation position could not be saved: " + e.message, "info"));
}
/**
 * requestEditorFinish  Provide the request editor finish helper used by training-template configurator browser page.
 * It belongs to the browser/MATLAB bridge path and must keep request payloads aligned with the MATLAB service contract.
 * Side effects: may send a request to the local MATLAB bridge and update browser-side UI state from the response.
 */
function requestEditorFinish() {
  if (activeEditor === "stacking") {
    document.getElementById("closeStackingConfig").click();
    return;
  }
  if (activeEditor === "altlabel") {
    document.getElementById("closeAltLabelConfig").click();
    return;
  }
  if (activeEditor === "cv") {
    document.getElementById("closeCVConfig").click();
    return;
  }
  if (activeEditor === "synth") {
    document.getElementById("closeSynthConfig").click();
    return;
  }
  if (activeEditor === "multi") {
    document.getElementById("closeMULTIConfig").click();
    return;
  }
  if (activeEditor === "rfe") {
    document.getElementById("closeRFEConfig").click();
    return;
  }
  if (activeEditor === "vis") {
    document.getElementById("closeVISConfig").click();
    return;
  }
  if (activeEditor === "mli") {
    document.getElementById("closeMLIConfig").click();
    return;
  }
  if (activeEditor === "sav") {
    document.getElementById("closeSAVConfig").click();
    return;
  }
  if (activeEditor === "verbosity") {
    document.getElementById("closeVerbosityConfig").click();
    return;
  }
  if (!activeEditor) {
    closeEditor();
    return;
  }
  let fr = document.getElementById("editorFrame");
  try {
    if (fr && fr.contentWindow) {
      fr.contentWindow.postMessage({ type: "nm-request-finish" }, "*");
      return;
    }
  } catch (e) {}
  editorStatus(
    "Could not contact the configuration window. Use its Finish or Back control if it is still open.",
    "danger",
  );
}
document.getElementById("forceBack").onclick = requestEditorFinish;
window.addEventListener("message", async (ev) => {
  if (ev && ev.data && ev.data.type === "nm-module-done") {
    try {
      if (await applyFinishedEmbeddedEditor(ev.data) === false) return;
    } catch (e) {
      status(
        "The configurator was saved, but its changes could not be applied to the analysis configuration: " + e.message,
        "danger",
      );
      return;
    }
    closeEditor();
  }
});
document.getElementById("finish").onclick = async () => {
  if (activeEditor === "cv") {
    await cvApply("apply");
  }
  if (activeEditor === "synth") {
    await synthApply();
  }
  if (activeEditor === "multi" && window.NMMULTIUI) {
    await NMMULTIUI.apply();
  }
  if (activeEditor === "rfe" && window.NMRFEUI) {
    await NMRFEUI.apply();
  }
  if (activeEditor === "vis" && window.NMVISUI) {
    await NMVISUI.apply();
  }
  if (activeEditor === "mli" && window.NMMLIUI) {
    await NMMLIUI.apply();
  }
  if (
    (activeEditor === "sav" || activeEditor === "verbosity") &&
    window.NMSAVUI
  ) {
    await NMSAVUI.apply();
  }
  if (pendingMenuChangedPaths().length) {
    try {
      await applyMenuContext({ force: true, fullState: false, includeCanvas: false });
    } catch (e) {
      status("Changes from the main configuration menu could not be applied: " + e.message, "danger");
      return;
    }
  } else {
    await flushMenuSync().catch(() => {});
  }
  await fetch(API("/api/current"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(STATE),
  }).catch(() => {});
  if (isWorkbenchChild()) {
    const res = await appChildReturn('template');
    if (res && res.ok === false) {
      status(res.message || res.error || 'Returning to the workbench failed.', 'danger');
      return;
    }
    if (appContext().returnPage === "nm_synth_coordinator.html") {
      const prepared = await nmProfiledMatlabService(
        { operation: 'app_prepare_page', page: 'synth_coordinator', moduleKey: 'synth_coordinator', timeout: 240 },
        'app_prepare_page',
      );
      if (prepared.ok === false) {
        status(prepared.message, 'danger');
        return;
      }
      const route = `${prepared.entryHtml}?port=${encodeURIComponent(PORT)}&synthTab=synthetic&_nmcb=${Date.now()}`;
      window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(route) : route);
      return;
    }
    const profileId = res && res.__nmClientProfileId ? res.__nmClientProfileId : "";
    const navStartEpoch = res && res.__nmClientProfileStartEpoch ? res.__nmClientProfileStartEpoch : Date.now();
    const returnUrl = workbenchReturnUrl(profileId, navStartEpoch);
    nmClientProfileActionLog(profileId, `workbench navigation commit ${((Date.now()-navStartEpoch)/1000).toFixed(3)}s after child-return start`);
    window.location.replace(window.NMBridgeNavigationURL ? window.NMBridgeNavigationURL(returnUrl) : returnUrl);
    return;
  }
  await fetch(`http://127.0.0.1:${PORT}/api/close`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ closed: true, source: "train_template_menu" }),
  }).catch(() => {});
  document.body.innerHTML =
    '<p style="font-family:system-ui;padding:20px">Current parameter-template state saved. You can close this tab.</p>';
};
if (window.NMMULTIUI)
  NMMULTIUI.attach({
    getState: () => STATE,
    setState: (s) => {
      acceptReturnedState(s);
    },
    getActiveEditor: () => activeEditor,
    setActiveEditor: setActiveEditorFromChild,
    render: render,
    sync: syncMenu,
    status: status,
    deferCanvas: canvasRefreshShouldBeDeferred,
    scheduleCanvasRefresh: scheduleCanvasRefresh,
    markCanvasDirty: markCanvasDirty,
    changedPathsFor: serviceChangedPaths,
    clearChangedPaths: acceptServiceChangedPaths,
    API: API,
  });
if (window.NMRFEUI)
  NMRFEUI.attach({
    getState: () => STATE,
    setState: (s) => {
      acceptReturnedState(s);
    },
    getActiveEditor: () => activeEditor,
    setActiveEditor: setActiveEditorFromChild,
    render: render,
    sync: syncMenu,
    status: status,
    deferCanvas: canvasRefreshShouldBeDeferred,
    scheduleCanvasRefresh: scheduleCanvasRefresh,
    markCanvasDirty: markCanvasDirty,
    changedPathsFor: serviceChangedPaths,
    clearChangedPaths: acceptServiceChangedPaths,
    API: API,
  });
if (window.NMVISUI)
  NMVISUI.attach({
    activeModalityHeader: activeModalityHeader,
    getState: () => STATE,
    setState: (s) => {
      acceptReturnedState(s);
    },
    getActiveEditor: () => activeEditor,
    setActiveEditor: setActiveEditorFromChild,
    render: render,
    sync: syncMenu,
    status: status,
    deferCanvas: canvasRefreshShouldBeDeferred,
    scheduleCanvasRefresh: scheduleCanvasRefresh,
    markCanvasDirty: markCanvasDirty,
    changedPathsFor: serviceChangedPaths,
    clearChangedPaths: acceptServiceChangedPaths,
    API: API,
  });
if (window.NMMLIUI)
  NMMLIUI.attach({
    activeModalityHeader: activeModalityHeader,
    getState: () => STATE,
    setState: (s) => {
      acceptReturnedState(s);
    },
    getActiveEditor: () => activeEditor,
    setActiveEditor: setActiveEditorFromChild,
    render: render,
    sync: syncMenu,
    status: status,
    deferCanvas: canvasRefreshShouldBeDeferred,
    scheduleCanvasRefresh: scheduleCanvasRefresh,
    markCanvasDirty: markCanvasDirty,
    changedPathsFor: serviceChangedPaths,
    clearChangedPaths: acceptServiceChangedPaths,
    API: API,
  });
if (window.NMSAVUI)
  NMSAVUI.attach({
    getState: () => STATE,
    setState: (s) => {
      acceptReturnedState(s);
    },
    getActiveEditor: () => activeEditor,
    setActiveEditor: setActiveEditorFromChild,
    render: render,
    sync: syncMenu,
    status: status,
    deferCanvas: canvasRefreshShouldBeDeferred,
    scheduleCanvasRefresh: scheduleCanvasRefresh,
    markCanvasDirty: markCanvasDirty,
    changedPathsFor: serviceChangedPaths,
    clearChangedPaths: acceptServiceChangedPaths,
    API: API,
  });
async function restoreTemplateNavigation(nav) {
  if (!nav || typeof nav !== "object") return;
  const mode = String(nav.uiViewMode || "menu") === "canvas" ? "canvas" : "menu";
  STATE.uiViewMode = mode;
  editorReturnViewMode = String(nav.editorReturnViewMode || mode);
  const subview = String(nav.subview || nav.editorKind || "").toLowerCase();
  if (!subview || subview === "menu" || subview === "canvas") {
    render();
    return;
  }
  if (subview === "preproc" || subview === "ml") {
    await openEditor(subview, {
      module: String(nav.editorModule || ""),
      restoreNavigation: true,
      returnViewMode: editorReturnViewMode,
    });
    return;
  }
  const map = {
    altlabel: "openAltLabelConfig", cv: "openCVConfig", synth: "openSynthConfig", stacking: "openStackingConfig",
    multi: "openMULTIConfig", rfe: "openRFEConfig", vis: "openVISConfig", mli: "openMLIConfig",
    sav: "openSAVConfig", verbosity: "openVerbosityConfig",
  };
  const el = document.getElementById(map[subview] || "");
  if (el) el.click(); else render();
}

(async function bootConfiguratorState() {
  try {
    await loadConfiguratorMenuState();
    NM2_RECOVERY_NAV = await loadTemplateNavigation();
  } catch (e) {
    status("Configuration page could not be initialized: " + (e.message || String(e)), "danger");
  }
  initMenuContextKeysFromState();
  const __initialRenderT0 = nmClientNow();
  nmClientProfileLog("initial render ENTER");
  render();
  nmClientProfileLog(`initial render TOTAL: ${nmClientProfileDelta(__initialRenderT0)}s`);
  if (NM2_RESTORE_ENTRY) {
    try { await restoreTemplateNavigation(NM2_RECOVERY_NAV); }
    catch (e) { status("Previous navigation position could not be restored; the default view was opened instead. " + (e.message || String(e)), "info"); }
  } else {
    try { await persistTemplateNavigation({ subview: currentViewMode(), editorKind: "", editorModule: "", editorReturnViewMode: "" }); }
    catch (e) { status("Navigation position could not be saved: " + (e.message || String(e)), "info"); }
  }
})();
