# DataIO public API

## Purpose

`NMDataIOAPITools` is the public programmatic entry point for scripts, tests and generated workflows. Callers provide source/provenance specifications; the API delegates to the same import authorities used by the browser and does not require direct mutation of `NM.Y`, `NM.cases`, `NM.datadescriptor` or `NM.OOCV`.

## General pattern

```matlab
NM = NMDataIOAPITools.emptyNM();

spec = struct( ...
    'sourceType','tablefile', ...
    'modeflag','classification', ...
    'description','Predictor modality', ...
    'tableFiles',{{'targets.csv','features.csv'}}, ...
    'variableRoles',roles, ...
    'metadataAlignmentMode','shared_key', ...
    'caseAxisPolicy','complete_case');

[NM, out] = NMDataIOAPITools.importTrainingMatrix(NM, spec);
```

The exact spec fields depend on provenance. Consult the corresponding `NMDataIOAPITools` method header and the provenance HTML help before generating a production script.

## Public import entry points

| Scientific source family | Training | OOCV/application |
| --- | --- | --- |
| Matrix/tabular: workspace, MAT-file, MATLAB table, table/spreadsheet file, database | `importTrainingMatrix` | `importOOCVMatrix` |
| ROI-anchored connectivity | `importTrainingConnectivity` | `importOOCVConnectivity` |
| ROI/parcellated data | `importTrainingROI` | `importOOCVROI` |
| Volumetric image lists and native surface scalar lists | `importTrainingImages` | `importOOCVImages` |

These entry points normalize public specs and converge on the same target, alignment, label and provenance authorities as the browser. They are not aliases for direct NM-field mutation.

## Training versus OOCV

Training methods establish or extend the training scientific state. OOCV methods require an explicit application-container target and must reuse training scientific contracts such as the class map and feature/provenance compatibility.

API code should never write `NM.*` scientific fields directly merely to configure an import. Use public configuration/import APIs.

## Tabular alignment

Public matrix/table specs use the same canonical alignment names as the browser:

- `shared_key`
- `key_per_block`
- `row_order`

`variableRoles` carries explicit references to Case-ID, labels, features, feature names, covariates and covariate names. For composite keys, component order is scientifically significant.

## Filters

Tabular filter specifications are object-bound and are applied before alignment/materialisation. API callers should use the same filter schema emitted by DataIO recipes rather than recreating row-selection logic outside DataIO.

## Database API

Database specs identify connector, URL/file/DSN, namespace and objects. Credentials are execution inputs and are not persisted by DataIO. Database adapters end at retrieval/type conversion; scientific processing is generic tabular DataIO.

## Reproducible examples

The acceptance tests under `tests/` provide executable examples, including the three-provenance early-fusion lifecycle with database Shared key, MATLAB-table Key per block and CSV Explicit row order. Generated DataIO API recipes are preferred over manually copying internal browser state structures.
