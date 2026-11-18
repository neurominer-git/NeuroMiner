# NeuroMiner 2 DataIO documentation

This directory documents the canonical DataIO contracts implemented by the MATLAB/browser/API code. It is deliberately organized by scientific responsibility rather than by UI screenshots.

## Documents

- [Lifecycle and state](LIFECYCLE_AND_STATE.md): state ownership, Preview/QC/Commit materialisation, persistence, Modify/Resume and OOCV semantics.
- [Public API](PUBLIC_API.md): programmatic import entry points and the contract between API specs and canonical DataIO state.
- [Diagnostics and QC](DIAGNOSTICS_AND_QC.md): blocking/warning semantics, attrition, QC, cache behavior and troubleshooting.
- [Interactive provenance help](help/dataio.html): responsive in-page browser/html-relay help index. Each canonical provenance has one detailed HTML page and stable section anchors used by the DataIO `?` controls.

The authoritative provenance vocabulary is `NMDataIOStateTools.sourceTypeCatalogue()`. Documentation and UI help must not maintain a competing provenance list.
