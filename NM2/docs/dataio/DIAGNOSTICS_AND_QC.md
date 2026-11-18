# DataIO diagnostics and QC

## Purpose

The DataIO diagnostics page is the scientific and technical review of an import before Commit. It should let a user answer five questions without reading backend code:

1. **Can this import be committed?**
2. **Did NM2 identify the expected number of cases, features, label targets and covariates?**
3. **What is the pattern of missingness and lack of variation?**
4. **Which cases or features have the largest QC values?**
5. **What filtering, Case-ID alignment or backend diagnostic messages require attention?**

The browser presents these questions in that order. Technical provenance and stack information remain available in expandable details rather than dominating the primary view.

## Import status

Diagnostic severity is assigned by the backend and is not inferred by the browser.

- **error / blocking (red)**: the import cannot be committed until the stated problem is corrected;
- **warning (orange)**: Commit is not blocked by the warning itself, but the finding requires review;
- **information (blue)**: records what NM2 found or did;
- **ok (green)**: confirms that a check or processing step completed successfully.

A technically valid import can still be scientifically wrong. A green status therefore does not replace review of case identities, counts, labels, covariates, missingness and QC patterns.

## Import summary

The primary summary reports the final backend-derived counts:

- **cases**: the people, samples, scans or other observations entering the modality;
- **features**: the measurements available to the model;
- **label targets**: classification or regression outcomes;
- **covariates**: additional case-level variables.

Unexpected counts commonly indicate incorrect source selection, filtering, role assignment or Case-ID matching. These counts are produced by the DataIO backend; the browser does not independently recompute filtering or alignment.

## Data completeness

The page uses user-facing descriptions for the principal missingness statistics:

- **cases with no missing features**: all feature values are observed;
- **cases with some missing features**: at least one value is missing and at least one is observed;
- **cases with all features missing**: no feature value is observed;
- **features with all values missing**: no case has an observed value for that feature;
- **constant features**: all observed values are identical;
- **NaN**: MATLAB's numeric missing-value marker;
- **Inf**: positive or negative infinity;
- **feature mean/SD range**: the minimum and maximum feature means and standard deviations across the imported feature space.

Missingness is not automatically blocking. Downstream preprocessing can handle missing values in supported workflows. Completely missing cases/features, constant features and unexpectedly high missingness should nevertheless be investigated before Commit.

## Feature QC

Feature QC summarizes the measurement space. The primary page reports:

- number of features containing missing values;
- constant and near-constant feature counts;
- highest missing-case rate found in any one feature;
- highest outlier-case rate found in any one feature;
- number of features on which the selected QC score is valid.

The QC method and feature-space identifier are retained under expandable method details.

## Case QC

Case QC summarizes the same data from the case perspective. The primary page reports:

- cases with all values missing or constant;
- the highest fraction of missing features observed in any one case;
- the highest fraction of outlying features observed in any one case.

High outlier burden is a signal for scientific inspection, not an automatic exclusion rule.

## Case QC viewer navigation

Case-level QC viewers share one navigation contract across tabular/matrix, volumetric, surface/ROI and connectivity representations. The Case ID is the primary user-facing identity. Ordinary left/right controls move to the previous or next case on the retained Preview QC case axis. **Previous QC-flagged** and **Next QC-flagged** jump only to cases whose existing QC output reaches the active review threshold or whose existing all-missing/constant-case flags are set.

QC-flagged is a viewer/navigation state only. It means **review this case**, not **exclude this case**. No separate persisted flagged-case boolean or second QC statistic authority is created. The diagnostics ranking exposes an **Inspect** action that opens the selected Case ID in the existing provenance-specific viewer while preserving the retained Preview/QC state. Image and surface viewers reuse persisted Preview paging when the requested case is outside the currently displayed page.

Case-level spatial and connectivity viewers expose only subject-level QC metrics. Group mean/SD/missingness/outlier-rate statistics are confined to their group QC viewers. Native volumetric group QC uses the retained feature mean as the anatomical background and overlays the selected group QC statistic; the outlier-rate map is computed at the active or cached |z| threshold. Surface viewers show one legend for the currently displayed quantity rather than simultaneous base-surface and QC legends.

## Tabular non-imaging feature QC

The feature-QC profile/histogram pipeline is confined to **tabular non-imaging data**. It uses the retained Preview materialization and the same feature-wise z-score definition as DataIO QC. It does not define a second QC statistic. The active display threshold changes highlighting and QC-flagged navigation only; it does not change imported values or case inclusion.

For `nFeatures <= 6000`, the primary view is the exact feature profile with raw values and z-scores; the distribution histogram is also available. For larger tabular matrices, the **distribution histogram is the default QC overview**. Histogram bars beyond the active review threshold are highlighted, and selecting a bar retrieves at most 20 exact feature names/raw values/z-scores from that z interval. This makes the distribution view actionable without transferring the complete feature vector or name list to the browser.

A high-dimensional **Ordered feature overview** remains available as an optional secondary view. It returns at most 1000 contiguous feature-index bins containing minimum/maximum z-score and missing-value count. This view is useful only when column order carries scientific or technical structure; it must not be interpreted as meaningful when tabular columns are arbitrarily ordered. Feature-name search is bounded to 20 retained-matrix results.

Imaging dimensionality never selects this pipeline. Volumetric voxel data, surface/vertex data and connectivity matrices remain in their dedicated spatial/network QC viewers. ROI/parcellated QC is visualized by projecting the ROI QC vector onto the configured sMRI atlas/template (or the corresponding surface annotation where applicable); ROI vectors are not routed through the tabular profile or histogram pipeline.

The viewer separates the explicit **QC decision** (`Include this case in the import`) from display controls. Plot mode, scale, review threshold, histogram-bin inspection, hover, top-feature selection and feature search are display/review actions only.

## Bounded detailed rankings

The browser shows only bounded top-ranked case and feature tables. It must never create one DOM row per feature for a high-dimensional dataset.

`NMDataIOFeatureQCTools` already enforces this backend boundary. Full feature-level QC vectors are returned only while `nFeatures <= MaxFeatureStatsInResponse` (default 5000). Above that limit, the payload contains compact summaries and bounded top-feature lists, while the browser explains that the full vector was intentionally omitted.

This is essential for tabular SNP, CpG and other omics datasets with hundreds of thousands or millions of features. Feature names and detected-column lists are likewise summarized in the diagnostics view rather than concatenated into an unbounded browser string. Detailed exports/viewers remain the appropriate route for feature-level inspection.

## Filtering and Case-ID alignment

Filtering and alignment details are available in a collapsed section. The backend audit reports source-row filtering, case-axis construction, source-block matching, duplicate Case-ID tuples and materialisation counts. This information supports detailed attrition accounting without forcing every user to read the technical ledger during routine imports.

## Diagnostic-message presentation

The browser groups identical diagnostic messages for display, preserves their backend severity/blocking state and exposes filters for error, warning, information and ok messages. Internal source identifiers and the full raw message are shown under **Technical details** so they remain available for support without dominating novice-facing content.

Display de-duplication does not remove or rewrite backend messages. It only avoids repeating identical entries in the browser view.

## Numeric-source problems

When Preview encounters non-numeric cells in a numeric role, the diagnostics page reports the affected source, column, row and raw value. The browser caps the rendered table to a bounded number of rows and reports the total affected-cell count. Commit remains blocked until the source values are corrected or deliberately mapped as missing.

## Cache and materialisation

Preview and QC consume the same retained materialisation. Changing source identity, row filters, role assignment, alignment keys, case-axis policy, label definitions, relevant import options or spatial provenance invalidates that retained materialisation. Pure display/navigation actions do not.

For spatial data, QC may use resident volume/surface/ROI/connectivity provenance and caches so interactive subject switching does not repeatedly reopen source files.

## Troubleshooting order

1. Read **Import status**.
2. Confirm the **Import summary** counts.
3. Inspect **Data completeness**, **Feature QC** and **Case QC**.
4. Open **Filtering and case-alignment details** if filters or Case IDs were used.
5. Filter **Diagnostic messages** to errors and warnings first.
6. Open **Technical details** only when the backend source identifier or complete message is required.
7. Correct the import setup and run Preview again before Commit.

Database Resume/Modify requires re-entering session credentials and rediscovering live namespaces/objects before source refresh can succeed.
