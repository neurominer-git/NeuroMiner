# NM2 configurator Stage-C failure audit against NM_5.0042

Baseline: `NM_5.0042(1).zip`  
Test suite: Stage-C final configurator suite  
Coding rules: `NM2_Coding_SKILL_v1.2.1`  

No production code was modified in this audit.

## Classification

| Scenario | Classification | Finding | Test-only action |
|---|---|---|---|
| S00 | **Credible production defect** | `NMPreprocModule.cli_configureHelp()` reads `info.description`, but `NMPreprocModule.info()` does not define `description`. `configSpec()` correctly obtains its description from `obj.help()`. The failure is therefore produced by current production code, not by a stale test expectation. | None. Keep S00 failing until production is corrected. |
| S02 | **Stale test/source-layout assumption** | The test searched `menuHtml` for renderer messages (`Alternative-label configuration synchronized.` and `Native multi-label...`) that reside in the separately packaged `NMTrainTemplateUI_main.js`. The state-transition assertions themselves match the current `NMUIStateTools`/`applyMenuService` authority. | Read the exported renderer asset for the UI-text contract and preserve the behavioral state assertions. Surface the original failing assertion in the thrown error. |
| S04 | **Test syntax defect** | `nk_TestNMMLIPort.m` contains a file-scope `assert(...)` after local function definitions. MATLAB rejects this function file with `LocalFunctionNameSameAsFileName`/parser failure. | Remove the vacuous trailing static guard. |
| S05 | **Stale test semantic assumption** | Current `NMMLModule.collectLegacyParamRanges()` emits LIBSVM regression shelves as `Slack` then `Epsilon`, explicitly following the `nk_MLOptimizer_main` consumer order. Two retained tests expected the reverse order. This production logic is unchanged from NM_5.0034b. | Update `nk_TestNMMLLegacyParity` and `nk_TestNMMLModulePort` to assert `Slack`, `Epsilon`. |
| S06 | **Unresolved; focused diagnostic suppressed** | Current Standardize/SkewCorr/ElimZero/ExtFeat/RankFeat/Impute production code still explicitly builds the PX descriptors tested by `nk_TestNMHyperparamPXAudit`. The master discarded `report.tests`, so the failing module is unknown. Relevant production files are unchanged from NM_5.0034b. | Preserve the test contract; make the master report the failing subtest and original message. |
| S08 | **Unresolved; focused diagnostic suppressed** | Current `NMCorrectNuisModule` code still implements the asserted partial/ComBat/DIR mappings, covariate table projection, categorical inference, and `DIR-Lambda` PX path. The master discarded `report.error`. Production is unchanged from NM_5.0034b. | Preserve the test contract; make the master report `report.error`/stack information. |
| S09 | **Unresolved; focused diagnostic suppressed** | Current graph module/rule-set code still documents and implements the tested dual-stage graph construction, subject KL imaging gate, normative CV path, and post-dimensionality-reduction KL rejection. The master discarded the per-subtest reports. Production is unchanged from NM_5.0034b. | Preserve the test contract; make the master report the failing graph sub-contract. |
| S10 | **Test fixture/state-lifecycle defect** | `nk_TestNMTrainTemplatePreprocCommit` creates a new temp directory and immediately calls `NMUIStateTools.writeConfiguratorChild`. Current state authority requires `nm2_state.json` to be initialized first. `NMTrainTemplateUI.export` does this correctly. | Initialize the test session with `NMUIStateTools.initialize(tmpDir,orch.NM,'template')` before writing child state. Also incorporate the user-reported `!isempty` -> `~isempty` MATLAB operator correction in the master. |
| S11 | **Test fixture/lifecycle defect** | `NMTrainTemplateAPITools.configureOneModality` correctly calls `NMStatusGuardTools.assertTrainingConfigurationMode`; the synthetic test NM omitted `NM.defs.import_finished=true`. The guard is unchanged from NM_5.0034b. | Mark the synthetic configurator fixture as already imported: `NM.defs.import_finished=true`, `NM.defs.analyses_locked=false`. |
| S12 | **Test implementation defect** | S12 initializes struct collectors as `0x1` but appends with linear `rows(end+1)`. MATLAB can grow these into `1xN` arrays; later vertical concatenation of runs with different lengths produces the reported `catenate:dimensionMismatch`. | Append with `rows(end+1,1)` consistently so every collector remains an N-by-1 struct array. |

## Overall conclusion

The initial result does **not** support a broad configurator production regression. Six failing scenarios are directly explained by test bugs/stale assumptions (S02, S04, S05, S10, S11, S12). S00 exposes one concrete production bug in the generic preprocessing CLI-help path. S06, S08 and S09 must be rerun with their original focused diagnostics surfaced before any production change is justified.

The latest-code comparison is also informative: `NMPreprocModule.m`, `NMMLModule.m`, `NMTrainTemplateAPITools.m`, `NMStatusGuardTools.m`, `NMCorrectNuisModule.m`, `NMGraphConstructionModule.m`, `NMPreprocRuleSet.m` and `NMUIStateTools.m` are byte-identical between NM_5.0034b and NM_5.0042. `NMTrainTemplateUI.m` changed, but its relevant alternative-label/state ownership remains consistent; the observed S02 issue is a test asset-location assumption.

## Test-only correction r1

Seven test files are changed; no production file is included:

- `tests/nk_TestNMConfiguratorMaster.m`
- `tests/nk_TestNMConfiguratorScalability.m`
- `tests/nk_TestNMAlternativeLabelPort.m`
- `tests/nk_TestNMMLIPort.m`
- `tests/nk_TestNMMLLegacyParity.m`
- `tests/nk_TestNMMLModulePort.m`
- `tests/nk_TestNMTrainTemplatePreprocCommit.m`

After applying r1, S00 is expected to remain a production failure. S06/S08/S09 may still fail, but the master will now report the exact underlying sub-contract rather than only `report.ok=false`.
