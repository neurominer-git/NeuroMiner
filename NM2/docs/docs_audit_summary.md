# NM2 `/docs` consolidation audit and validation

Baseline: `NMModular_common_v4.598_docs_audit(2).zip`

Date: 2026-08-27

## Scope

This deliverable performs only the conceptual `/docs` consolidation. It does not modify production source or tests. That separation is intentional because the subsequent in-code RAG pass will be performed against a newer consolidated codebase supplied by the user.

The replacement directory must therefore be treated as the canonical conceptual documentation set, while the source/test reference migration listed below is a required task for the subsequent in-code pass.

## Before / after

| Measure | Baseline | Replacement | Delta | Reduction |
|---|---:|---:|---:|---:|
| Total files in `/docs` | 292 | 14 | -278 | 95.2% |
| Markdown files | 230 | 14 | -216 | 93.9% |
| Markdown physical LOC | 21,888 | 724 | -21,164 | 96.7% |
| Production source physical LOC | 203,325 | 203,325 | 0 | 0% |
| Test physical LOC | 77,160 | 77,160 | 0 | 0% |

No production or test file is changed by this docs-only package.

## Canonical replacement structure

The replacement contains 14 concept-oriented Markdown documents. They are named by stable architectural concepts rather than patch/stage chronology. The documents cover system architecture, Scientific State/semantics, Results Viewer, Feature Inspection, DataIO, ROI/atlas, imaging, surface, connectivity, common mesh rendering, Report Builder, runtime bridge, and output/export/reproducibility.

Function-local contracts are explicitly excluded from `/docs`. Accepted arguments, return structures, exact validation, materialization/performance costs, mutation, failure semantics, side effects and consumers/dependencies belong inside the implementing function using the standardized 11-section RAG/NOVA template.

## Old-document disposition

`deleted_docs_manifest.csv` records the disposition of all 292 baseline `/docs` files:

- 21: `MERGED` — useful cross-function concepts retained after source verification;
- 87: `MOVE_TO_CODE` — implementation/function contract material to be reconstructed inside source during the in-code RAG pass;
- 122: `DELETE` — stage/patch/acceptance/history material;
- 62: `DELETE_FROM_DOCS` — non-conceptual provenance, audit, test-result, JSON or workspace artefacts.

Historical material is not copied into a `deprecated/` subdirectory. Version control / the retained baseline archive is the history source.

## Structural validation of replacement docs

PASS:

- 14 Markdown files, 724 physical lines.
- All internal Markdown links resolve.
- 114 source-anchor occurrences resolve to live source paths (66 unique source files).
- No C18/G/PORT/S stage identifiers are present in the canonical docs.
- No conceptual document uses the standardized function-local template headings. The only template list appears in `README.md` to define what must remain in source.
- 23 targeted source-claim checks pass, including current Scientific Annotation/Capability/Directory/State contract versions, Report Builder use of Scientific State, browser active Scientific State, canonical ROI provenance, ROI Mapper presentation-only ownership, common mesh renderer reuse, output artifact authority, and bridge/service boundaries.

## Baseline source/test coupling discovered by replacement

Replacing `/docs` exposes obsolete documentation-authority coupling in the baseline:

- 21 production files still point to old Markdown contracts/knowledge indexes.
- 74 test files/manifests still read old Markdown/JSON documentation artefacts.
- Total migration backlog: 95 files.

These files are listed in `RAG_INCODE_MIGRATION_BACKLOG.csv` with the exact old documentation references.

They are deliberately **not edited in v4.598**. The next in-code RAG pass will run on the newer consolidated codebase, where these pointers can be removed or redirected to actual source-level documentation without creating a temporary fork.

Consequently, a historical full regression suite containing those documentation-coupled tests is not expected to pass immediately after deleting the old `/docs` tree. Those tests must be migrated/retired during the in-code documentation pass; otherwise they would continue to make Markdown a competing authority.

## Static/runtime validation independent of deleted docs

PASS:

- Node syntax: 388 JavaScript files checked, 0 failures.
- Python syntax: 57 Python test files compiled, 0 failures.
- Representative source/runtime tests, all PASS:
  - `tests/run_nm_results_viewer_g1a_scientific_selection_source.py`
  - `tests/run_nm_results_viewer_g1c_scientific_contract_source.py`
  - `tests/run_nm_results_viewer_g8e2_scientific_state_admission.js`
  - `tests/run_nm_results_viewer_roi_mapper_port1_r1o_c.js`
  - `tests/run_nm_results_viewer_report_builder_output_plan_race_perf4_r4.js`
  - `tests/run_nm_results_viewer_connectivity_g6b_r6.js`
  - `tests/run_nm_imaging_2d_gpu_single_overlay_r1.js`

The GPU imaging test executed successfully through Chromium/Xvfb.

MATLAB/Octave is not installed in the validation environment, so MATLAB runtime tests were not executed. No claim of MATLAB runtime validation is made.

## Installation

For the conceptual-docs replacement itself:

1. Delete the existing `docs/` directory.
2. Extract/copy the supplied replacement `docs/` directory into the project root.
3. Do **not** copy the audit ledgers into `docs/`; they are development/audit artefacts, not canonical conceptual documentation.
4. During the subsequent in-code RAG pass on the newest consolidated codebase, use `RAG_INCODE_MIGRATION_BACKLOG.csv` to remove old Markdown pointers and migrate/retire documentation-coupled tests.
5. Run the final complete regression suite after that source/test migration.
