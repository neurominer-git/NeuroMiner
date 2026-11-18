# NM2 architecture documentation

This directory contains the durable, cross-function documentation for the NM2 codebase.

## Documentation boundary

The source code is the primary RAG/NOVA corpus for function and method behaviour. Substantive functions and methods are documented **inside the implementing function** using the standard sections:

1. Purpose
2. Syntax
3. Inputs
4. Outputs
5. Authority and flow
6. Scientific/state contract
7. Invariants
8. Materialization and performance
9. Failure semantics
10. Side effects
11. Consumers and dependencies

The files in this directory must not duplicate those function-local contracts. They are reserved for concepts that span multiple functions or modules: ownership boundaries, state/data flow, lifecycle relationships, materialization boundaries, and architectural figures.

Historical patch/stage identifiers are not part of the durable documentation taxonomy. Development history belongs in version control or the project patch history, not in this directory.

## Canonical conceptual documents

| Document | Cross-function scope |
|---|---|
| [SYSTEM_ARCHITECTURE.md](SYSTEM_ARCHITECTURE.md) | Overall MATLAB/DataIO/browser/bridge structure and authority boundaries |
| [SCIENTIFIC_STATE_ARCHITECTURE.md](SCIENTIFIC_STATE_ARCHITECTURE.md) | Scientific Annotation, Capability, Directory and runtime Scientific State |
| [RESULTS_VIEWER_ARCHITECTURE.md](RESULTS_VIEWER_ARCHITECTURE.md) | Results Viewer backend, browser state, representations and message routing |
| [FEATURE_INSPECTION_ARCHITECTURE.md](FEATURE_INSPECTION_ARCHITECTURE.md) | Feature Inspection semantics, fusion contexts, graphs and spatial representations |
| [MLI_VISUALIZATION_ARCHITECTURE.md](MLI_VISUALIZATION_ARCHITECTURE.md) | Subject-level ML interpretation selection, Feature Inspection parity, and shared spatial materialization |
| [DATAIO_ARCHITECTURE.md](DATAIO_ARCHITECTURE.md) | DataIO state, probe/import lifecycle, provenance and QC boundaries |
| [ROI_ATLAS_ARCHITECTURE.md](ROI_ATLAS_ARCHITECTURE.md) | Canonical ROI identity/provenance, atlas/annotation references and ROI consumers |
| [IMAGING_ARCHITECTURE.md](IMAGING_ARCHITECTURE.md) | Voxel imaging services, 2-D/3-D browser viewers, caches and retained view state |
| [SURFACE_ARCHITECTURE.md](SURFACE_ARCHITECTURE.md) | Native surface provenance, geometry, annotations and Results Viewer surface pathway |
| [CONNECTIVITY_ARCHITECTURE.md](CONNECTIVITY_ARCHITECTURE.md) | Connectivity import provenance and matrix/network/glass-brain pathway |
| [COMMON_MESH_RENDERING_ARCHITECTURE.md](COMMON_MESH_RENDERING_ARCHITECTURE.md) | Shared WebGL mesh renderer used by surface, connectivity and imaging representations |
| [REPORT_BUILDER_ARCHITECTURE.md](REPORT_BUILDER_ARCHITECTURE.md) | Scientific-State-driven report planning, browser presentation preparation and assembly |
| [RUNTIME_BRIDGE_ARCHITECTURE.md](RUNTIME_BRIDGE_ARCHITECTURE.md) | Local browser bridge, MATLAB-service dispatch, session lifecycle and progress |
| [OUTPUT_EXPORT_REPRODUCIBILITY.md](OUTPUT_EXPORT_REPRODUCIBILITY.md) | Viewer artifact boundary, exports including MLI relevance maps, state persistence, montage/video and code generation |

## Update rule

When implementation changes, update the source-level function documentation first. Update a file here only when the cross-function relationship or architecture has changed. If a statement can be made authoritative by documenting one function, it does not belong here.
