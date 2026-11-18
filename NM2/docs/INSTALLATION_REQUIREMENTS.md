# NeuroMiner 2.0 — installation and deployment requirements

**Scope:** NM2 browser workbench, MATLAB scientific backend, Python bridge, Results Viewer/Report Builder, and local/HPC execution.  
**Source baseline:** NM2 5.0081h (October 2026). This document describes the requirements and supported interfaces visible in that source release; it is **not** a declaration that every MATLAB/OS/toolbox combination has been qualified.  
**Related documents:** [System architecture](SYSTEM_ARCHITECTURE.md) · [Runtime bridge architecture](RUNTIME_BRIDGE_ARCHITECTURE.md) · [Report Builder architecture](REPORT_BUILDER_ARCHITECTURE.md) · [Output and export](OUTPUT_EXPORT_REPRODUCIBILITY.md).

## 1. Installation layout: the complete NeuroMiner root is mandatory

NM2 is a modern UI/runtime layer over the established NeuroMiner MATLAB backend. **The NM2-only release archive is not a self-contained installation.** Install or merge the matching NM2 release into a complete NeuroMiner backend **at one common root**; do not merely add several unrelated directories to the MATLAB path and assume that the installation is complete.

```text
<NEUROMINER_ROOT>/
  nm.m                    MATLAB entry point
  nk_Initialize.m         legacy initialization and path authority
  config/                 backend configuration
  cfiles/                 platform-dependent compiled MEX functions
  preproc/                preprocessing and included libraries
  trainpredict/           training/prediction and included libraries
  gridsearch/             optimization code
  visual/                 visualization backend
  ...                     remaining directories of the full backend
  NM2/
    bridge/               MATLAB-to-Python browser bridge
    core/                 NM2 service/scientific adapters
    ui/                   browser workbench and pages
    dataio/               data import and OOCV services
    docs/                 this document
```

`nk_Initialize` derives the NeuroMiner root from the location of the **active** `nm.m` (`fileparts(which('nm.m'))`) and adds backend and `NM2/` paths relative to that root. A misplaced or shadowing `nm.m` can cause missing-backend errors despite other directories already being on MATLAB's path. **Do not work around an incorrect layout by modifying root discovery.**

The full legacy backend contains additional dependencies and platform-specific MEX binaries. Maintain compatible versions of those components and ensure that the MEX files required by the selected scientific methods work on the target OS/architecture. Install optional imaging tools such as SPM through their established initialization mechanism (`nk_ImagingInit` / `imaging_init.mat`); putting a third-party directory on `PATH` or the MATLAB path is not by itself a substitute for successful NM initialization.

### MATLAB path preflight

In a fresh MATLAB session, put the **single complete NeuroMiner root** on the path, then check:

```matlab
which('nm', '-all')                 % Check for shadowed copies
which('nk_Initialize', '-all')      % Must belong to the same installation
root = fileparts(which('nm'));
assert(isfile(fullfile(root,'nk_Initialize.m')), ...
    'Incomplete installation: nk_Initialize.m is absent from the NeuroMiner root.');
assert(isfolder(fullfile(root,'NM2','bridge')), ...
    'Incomplete installation: NM2/bridge is missing.');
assert(isfolder(fullfile(root,'trainpredict')), ...
    'Incomplete installation: backend/trainpredict is missing.');
disp(root)
```

Avoid conflicting releases of `nm.m`, `nk_Initialize.m`, or NM2 classes on the MATLAB path. Verify which copy is active before reporting a startup problem.

## 2. Core runtime prerequisites

| Component | Requirement | Notes |
|---|---|---|
| MATLAB | A compatible licensed MATLAB release with the NeuroMiner backend and relevant method dependencies | The 5.0081h source does not specify a formally validated minimum MATLAB release. Validate the actual installation and scientific/MEX workflows. |
| Python bridge | **Python 3 executable** accessible to the MATLAB process | The included bridge uses Python standard-library HTTP/JSON/threading facilities; the bridge source itself does not require third-party `pip` packages. Scientific methods may have independent dependencies. |
| Browser UI | Supported graphical browser (Firefox, Chrome/Chromium, Edge) **or** MATLAB `uihtml` relay | A browser for interacting with NM2 is distinct from a renderer used to generate PDFs. |
| Filesystem | Writable user/session directory, output directory, and temporary-profile space | Protect separate users' session state; account for HPC permissions, quotas and cleanup policies. |
| Networking | Local Python bridge on **`127.0.0.1`**, on an available port | If MATLAB runs on a remote HPC node, the bridge's loopback listener is on **that node**. Use a site-approved graphical session or secure loopback tunnel; do not expose the bridge publicly. |
| Imaging/ML dependencies | As required by the selected functionality | SPM, FreeSurfer/surface tooling, third-party libraries, and platform-specific MEX availability are workflow-dependent; do not assume they are mandatory for every tabular analysis. |
| PDF renderer | **Optional for core NM2 use**, required for graphical Report Builder PDF export | HTML report export does not require an external PDF renderer. |

The browser bridge resolves Python 3 in this order: `NM_PYTHON_EXEC` environment variable, MATLAB's `pyenv` executable, then platform command names (`python3`/`python` on Unix, `python`/`py -3` on Windows). The chosen interpreter must be launchable via MATLAB's `system()` environment. It is a separate Python process, not an embedded Python package requirement.

Common startup commands:

```matlab
nm ui                  % Workbench in a selected external browser
nm nosplash ui         % Same, without startup splash screen
nm ui html-relay       % Embedded MATLAB uihtml transport where supported
```

`html-relay` still uses the same Python bridge. A headless MATLAB/SLURM execution cannot perform a graphical `uihtml` interaction test; use a supported browser/desktop environment for the interactive acceptance gate.

## 3. Graphical Report Builder PDF export

**A PDF is not generated by the browser used to operate NM2.** NM2 first writes a static HTML/SVG report and then invokes a **server-side command-line HTML-to-PDF renderer** in the MATLAB execution environment. If conversion fails, the static HTML can remain available; its presence is **not** evidence of a successful PDF export.

### Implemented PDF renderer families in 5.0081h

| Package or executable | NM2 renderer kind | Status and deployment recommendation |
|---|---|---|
| **Chromium** (native Linux package, managed binary, or site module) | `chromium` | **Preferred on Linux/HPC.** Must support headless `--print-to-pdf` with NM2's flags. Avoid Snap wrappers in restricted sessions. |
| **Google Chrome** | `chromium` | Supported; use a native headless-capable executable. |
| **Microsoft Edge** (`microsoft-edge` / `msedge.exe`) | `chromium` | Supported through its Chromium-compatible headless command line; useful if Chrome is not installed. |
| **wkhtmltopdf** | `wkhtmltopdf` | Implemented alternative. Legacy Qt WebKit rendering may differ for modern CSS/SVG; verify a representative NM2 report before adoption. |

**Not automatically supported as PDF renderers:** Firefox, WeasyPrint, PrinceXML, Pandoc, LibreOffice, browser print dialogs, and arbitrary PDF libraries. These may offer external/manual conversion workflows, but NM2 5.0081h has no corresponding command adapter. A generic `chrome-headless-shell` binary has not been validated against NM2's Chrome command flags and should not be listed as qualified merely because it renders PDFs elsewhere.

`wkhtmltopdf` is no longer actively maintained upstream (repository archived in 2023); it is an implemented compatibility option, **not the preferred new HPC dependency**. It also requires careful treatment of untrusted HTML and local-file permissions.

### Renderer discovery and explicit selection

`NMResultsViewerReportTools.resolvePdfRenderer` tries, in order:

1. The export-spec override `PdfRenderer` (with optional `PdfRendererKind`).
2. Platform-specific Chrome, Chromium, and Edge executables.
3. `wkhtmltopdf`.

On Linux, the automatic `PATH` candidate order is: `google-chrome`, `google-chrome-stable`, `chromium`, `chromium-browser`, `microsoft-edge`, `microsoft-edge-stable`, `wkhtmltopdf`. **Discovery checks that an executable path exists; it does not prove that the binary can launch or produce a PDF.** The first discovered candidate may therefore be unusable.

For an **API-driven** Report Builder export, the established export options permit an explicit executable path:

```matlab
% Example values within an NM2 report export specification:
exportSpec.PdfRenderer = '/opt/site/bin/chromium';
exportSpec.PdfRendererKind = 'chromium';
% Alternatively:
% exportSpec.PdfRenderer = '/opt/site/bin/wkhtmltopdf';
% exportSpec.PdfRendererKind = 'wkhtmltopdf';
```

These fields identify the documented MATLAB export-spec contract; their presence does not imply that every browser UI exposes a corresponding setting. Paths above are **illustrative**, not real paths to install. If the auto-discovered Snap Chromium precedes a working Edge executable, configure the environment/PATH or use a supported explicit override where available.

### HPC caveat: Snap Chromium may be present but unusable

An installation such as `/snap/bin/chromium` can fail outside a Snap-managed cgroup:

```text
... is not a snap cgroup for tag snap.chromium.chromium
```

This can happen on a login/headnode **without** any active SLURM job. In 5.0081h, NM2 skips known Snap launcher paths only when `SLURM_JOB_ID` is nonempty; an empty variable does **not** establish that the Snap launcher will run. Do not treat `command -v chromium` or exit code 0 from the lookup as a rendering acceptance test.

**HPC deployment recommendation:** ask the system administrator to provide a native, non-Snap Chromium executable or Microsoft Edge through a site-approved package/module or managed application. Confirm that its sandbox, required shared libraries, fonts, and writable user profile are available in the actual MATLAB execution context. Do not globally disable the browser sandbox to conceal a deployment problem.

### Executable check (Linux/HPC)

Run the following from the **same environment/account from which MATLAB is launched**:

```bash
for exe in google-chrome google-chrome-stable chromium chromium-browser \
           microsoft-edge microsoft-edge-stable wkhtmltopdf; do
  if command -v "$exe" >/dev/null 2>&1; then
    printf '%-24s %s\n' "$exe" "$(command -v "$exe")"
  fi
done
printf 'SLURM_JOB_ID=%s\n' "${SLURM_JOB_ID:-<unset>}"
```

Next perform a **real local-file-to-PDF smoke test**, using an administrator-approved native Chromium path, **not** `/snap/bin/chromium`:

```bash
RENDERER=/absolute/path/to/native/chromium  # replace with verified path
WORK=$(mktemp -d)
printf '%s\n' '<!doctype html><html><body><h1>NM2 PDF probe</h1></body></html>' \
  > "$WORK/probe.html"
"$RENDERER" --headless=new --disable-gpu --no-first-run \
  --disable-extensions --disable-dev-shm-usage \
  --allow-file-access-from-files --no-pdf-header-footer \
  --print-to-pdf-no-header --user-data-dir="$WORK/profile" \
  --print-to-pdf="$WORK/probe.pdf" "file://$WORK/probe.html"
test -s "$WORK/probe.pdf" && echo 'PDF probe PASS' || echo 'PDF probe FAIL'
# Inspect the result; remove the probe directory when finished:
# rm -rf "$WORK"
```

For `wkhtmltopdf`, test the same HTML with the command syntax NM2 uses:

```bash
wkhtmltopdf --enable-local-file-access --page-size A4 \
  --margin-top 15mm --margin-right 15mm \
  --margin-bottom 15mm --margin-left 15mm \
  "$WORK/probe.html" "$WORK/probe-wkhtml.pdf"
test -s "$WORK/probe-wkhtml.pdf" && echo 'PDF probe PASS' || echo 'PDF probe FAIL'
```

A simple smoke test only checks process launch, local-file access and file creation. **Final acceptance requires inspection of a representative NM2 report** containing figures, SVG/text, page breaks, captions, and any required imaging panels, exported through Report Builder itself.

## 4. Deployment and acceptance matrix

| Environment | Core runtime gate | Interactive UI gate | PDF gate |
|---|---|---|---|
| Local Windows/macOS/Linux workstation | Full root + MATLAB backend/MEX + Python 3 | Normal browser or supported HTML relay | Functional Chrome/Chromium/Edge or wkhtmltopdf executable |
| Remote HPC login/headnode | Full root visible to MATLAB + launchable Python 3 + writable session space | Site-approved GUI/browser session or authorized tunnel to the loopback bridge | Native renderer functional **on headnode**, not just on user's laptop |
| SLURM compute job | Full root, process-private I/O, Python/runtime and selected scientific dependencies | Headless service/test path; interactive uihtml not supported | Renderer tested inside the job's actual constraints, modules, cgroups and mount namespace |
| MATLAB Online | Full root and launchable Python 3 in the hosted session | Validate HTML relay/graphics support in the actual MATLAB Online environment | Renderer in the hosted MATLAB environment if supported; a browser on the user's PC does not supply it |

Before declaring the installation ready, verify: **(a)** one authoritative `nm.m` and complete root; **(b)** Python bridge startup; **(c)** representative end-to-end MATLAB calculation; **(d)** interactive UI in its intended deployment mode; and **(e)** a real NM2 PDF export **if PDF is required**. Preserve build ID, MATLAB release, OS/session type, renderer executable/version, and the renderer's stdout/stderr on failure.

## 5. Common failure signatures

| Symptom | Likely boundary | Action |
|---|---|---|
| `nk_Initialize` references missing backend directories | Incomplete root or wrong `nm.m` selected | Repair deployment layout and resolve path shadowing; do not add discovery fallbacks. |
| Bridge says no Python 3 was found | `NM_PYTHON_EXEC`, `pyenv`, or executable launch | Provide a working Python 3 executable accessible through MATLAB `system()`. |
| Browser cannot reach Python bridge on remote node | Loopback-only listener / incorrect remote transport | Use permitted local graphical execution or a secure loopback tunnel. |
| HTML report created, PDF reports `snap cgroup` error | Snap launcher selected outside its runtime | Install/select native Chromium or Edge; verify with a real CLI PDF probe. |
| Browser-based inspection works, PDF export fails | UI browser and server-side renderer are separate | Check renderer probe log and command stderr in the MATLAB host environment. |
| `wkhtmltopdf` produces incomplete styling | Legacy rendering engine | Prefer native Chromium/Edge and compare against source HTML. |

## 6. Provenance and references

NM2 source authorities inspected for this document: `nm.m`, `nk_Initialize.m` (legacy backend), `NM2/bridge/nm_open_ui.m`, `NM2/bridge/nm_ui_bridge_python_template.m`, and `NM2/core/NMResultsViewerReportTools.m` (`resolvePdfRenderer`, `pdfRendererCandidates`, `resolveExecutable`, `chromiumPdfCommand`, and `wkhtmltopdfCommand`).

External background:

- [Chrome Headless command-line reference](https://developer.chrome.com/docs/automation-and-testing/headless-cli) — `--print-to-pdf` and related flags.
- [wkhtmltopdf repository](https://github.com/wkhtmltopdf/wkhtmltopdf) — upstream archive status.
- [wkhtmltopdf project status](https://wkhtmltopdf.org/status) — Qt WebKit maintenance and security limitations.

*This document describes source-confirmed options and deployment acceptance requirements. It does not install or bundle MATLAB, NeuroMiner legacy components, SPM, browsers, or PDF-renderer binaries.*
