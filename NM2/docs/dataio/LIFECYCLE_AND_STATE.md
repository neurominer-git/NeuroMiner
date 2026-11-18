# DataIO lifecycle and state contract

## 1. Purpose

DataIO converts external or workspace data into NeuroMiner training modalities and OOCV/application modalities while retaining the source, case-axis, feature-space and spatial provenance required by later analysis and visualization. The browser is a configuration and inspection client; scientific import semantics remain in MATLAB authorities.

## 2. Ownership

| Responsibility | Authority |
| --- | --- |
| Browser/API state ↔ IO translation and canonical source vocabulary | `NMDataIOStateTools` |
| Training/OOCV write target | `NMDataIOImportTargetTools` |
| Generic tabular/matrix materialisation, Preview and Commit | `NMDataIOImportTools` |
| Public scripted entry points | `NMDataIOAPITools` |
| Label normalization and training-owned class map | `NMDataIOLabelStatsTools` |
| Database retrieval/type conversion | `NMDataIODatabaseTools` |
| OOCV readiness | `NMDataIOOOCVReadinessTools` / analysis runner |
| Browser DataIO modes and container management | `NMDataIOBrowserModeTools` |
| Ephemeral retained materialisation | `NMDataIOMaterializationCache` |
| Diagnostics/message severity | `NMDataIOMessageTools` |
| Feature QC | `NMDataIOFeatureQCTools` / `NMDataIOQCReportTools` |
| Canonical ROI provenance | `NMDataIOROIProvenanceTools` |

A provenance-specific layer may retrieve and convert its raw data. It must not introduce a second Case-ID matcher, filter engine, label canonicalizer, first-axis implementation or scientific result authority.

## 3. Canonical provenance catalogue

`NMDataIOStateTools.sourceTypeCatalogue()` currently owns nine provenance identities:

1. `workspace` — MATLAB workspace variables
2. `matfile` — MAT-file variables
3. `tablevar` — MATLAB tables
4. `tablefile` — text/CSV/Excel files
5. `database` — database connector
6. `image-list` — 3D image files
7. `connectivity` — ROI-anchored connectivity data
8. `surface-list` — surface/vertex scalar files
9. `roi` — ROI/parcellated data

The same catalogue also owns the provenance help-file identity used by DataIO. Browser HTML generation and documentation validation query this catalogue rather than duplicating the list.

## 4. Training lifecycle

```text
source selection
  -> source discovery / header or spatial inspection
  -> scientific role assignment
  -> row filtering (where applicable)
  -> key / row-order contract
  -> first-case-axis policy when a new case axis is established
  -> materialisation
  -> diagnostics + mandatory QC + Preview
  -> Commit
  -> persisted modality data + datadescriptor/input_settings/provenance
```

Training classification labels establish the authoritative raw-value → canonical-class mapping once. The persisted mapping is reused for every labelled OOCV dataset.

## 5. OOCV lifecycle

OOCV imports target an explicit application container and modality index. DataIO allows an OOCV container to hold only a subset of training modalities; the selected trained analysis decides which modalities are required at model-application time.

For classification:

- training class mapping is authoritative;
- OOCV row order and class frequency never define a new class axis;
- an OOCV cohort may omit one or more training classes;
- missing labels remain `NaN`;
- an unseen raw OOCV class is a blocking diagnostic.

## 6. Alignment contracts

### Shared key

One ordered key tuple is applied to every participating row-bearing object. Selecting candidate columns does not change the scientific contract until **Apply shared key** succeeds.

### Key per block

Each label, feature or covariate block receives its own ordered key tuple. Differently named or composite key columns are therefore valid across objects.

### Explicit row order

Participating objects are asserted to share row order and compatible row counts. DataIO does not infer correspondence merely from equal row counts; the user owns this scientific assertion.

### First-case-axis policies

When an import establishes a new case axis, the supported policies are complete-case intersection, target-anchored and feature union. Later modalities align to the established axis.

## 7. Filters

Object-specific and cross-table filters are applied before key uniqueness, alignment and scientific role materialisation. Filter columns need not be scientific columns or Case-ID columns. Missing values are normal data states; missingness becomes filtering behavior only through explicit `is missing` / `is not missing` criteria.

## 8. Preview, retained materialisation and Commit

Preview is the primary non-mutating scientific checkpoint. It executes the canonical materializer, computes diagnostics and mandatory QC, and retains the result in `NMDataIOMaterializationCache`.

The cache is execution state only. It is not written to NM, `input_settings`, recipes or `nm2_state`. Commit reuses a valid retained materialisation; a relevant configuration change invalidates it and Commit invokes the same materializer again rather than a competing path.

## 9. Persistence and recovery

Persistent state contains the scientific configuration needed to reconstruct an unfinished or committed import. Transient external-session state is intentionally excluded.

Database examples:

- database/schema names may be restored because they are part of the scientific source specification;
- passwords are never persisted;
- a live database/schema/table catalogue is never treated as restored merely because a namespace name is present;
- Resume/Modify requires reconnection and rediscovery before live objects are used again.

## 10. Modify and Resume

**Modify** rehydrates an existing modality for intentional replacement. **Resume** reopens a restorable unfinished configuration. Both routes should reconstruct the same scientific controls as a fresh configuration without introducing a second representation of provenance, roles, keys or filters.

## 11. Mandatory-field navigation

Red/green borders are navigation only. They project existing readiness/validation requirements onto the control that owns the next mandatory action:

- red: mandatory action/value currently incomplete;
- bright green: that authoritative requirement is satisfied;
- neutral: optional, hidden, disabled, or only a candidate selector for a separate Apply/Refresh action.

The border state must never become a second validator or alter Preview/Commit eligibility.
