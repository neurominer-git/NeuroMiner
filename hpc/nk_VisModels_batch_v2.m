function nk_VisModels_batch_v2(configPath)
% robust config reader (JSON, key=value, or legacy positional)

cfg = read_cfg(configPath); % <— NEW helper below

% Map to your variables (with defaults)
NMpath           = mustfield(cfg, "NMpath");
datpath          = mustfield(cfg, "datpath");
jobdir           = mustfield(cfg, "jobdir");
analind          = numfield(cfg, "analind");

multiflag        = numfield(cfg, "multiflag", 2);
saveparam        = numfield(cfg, "saveparam", 2);
loadparam        = numfield(cfg, "loadparam", 2);
writeCV2flag     = numfield(cfg, "writeCV2flag", 2);
ovrwrt           = numfield(cfg, "ovrwrt", 1);
optparamspath    = strfield(cfg, "optparamspath", "NaN");
optmodelspath    = strfield(cfg, "optmodelspath", "NaN");
CV1flag          = numfield(cfg, "CV1flag", 2);
lowmem           = numfield(cfg, "lowmemflag", 2);
CVRnorm          = numfield(cfg, "CVRnorm", 1);

imagingflag      = numfield(cfg, "imagingflag", 0);
spacedefimg_path = strfield(cfg, "spacedefimg_path", "NaN");

DecompMode       = numfield(cfg, "DecompMode", 2);
simCorrThresh    = numfield(cfg, "simCorrThresh", 0.3);
simCorrMethod    = strfield(cfg, "simCorrMethod", "pearson");
CorrCompCutOff   = numfield(cfg, "CorrCompCutOff", 0.3);
SelCompCutOff    = numfield(cfg, "SelCompCutOff", 0.2);
fdr_comp_search  = numfield(cfg, "fdr_comp_search", 2);

% Grid spec (keep your ranges)
grid = getfield_default(cfg, "grid", struct());
CV2x1 = getfield_default(grid, "perm_start", []);
CV2x2 = getfield_default(grid, "perm_end",   []);
CV2y1 = getfield_default(grid, "fold_start", []);
CV2y2 = getfield_default(grid, "fold_end",   []);

% Accept SLURM array index from env (no need to write N param files)
curCPU = str2double(getenv_default("SLURM_ARRAY_TASK_ID","1"));
numCPU = str2double(getenv_default("SLURM_ARRAY_TASK_MAX", ...
           getenv_default("SLURM_ARRAY_TASK_COUNT","1")));

% Optional: cap MATLAB threads to cpus-per-task
slurm_cpus = str2double(getenv_default("SLURM_CPUS_PER_TASK","1"));
try maxNumCompThreads(slurm_cpus); catch, end

% --- your existing body continues, with the same 'inp' struct ---
% (unchanged, except that you no longer read 'params{1}{k}' from a file)
```

**Helper functions (drop into the same file or a small utility file):**

```matlab
function cfg = read_cfg(p)
% Detect format: JSON, key=value, or legacy positional lines
if ~exist(p,'file'); error('%s not found. Abort job!', p); end
txt = fileread(p); st = strtrim(txt);
if startsWith(st,'{')
    cfg = jsondecode(st);
elseif contains(st,'=')
    cfg = parse_kv(txt);
else
    % legacy positional -> keep your current logic but read lines, not words
    fid=fopen(p); c = textscan(fid,'%s','Delimiter','\n','Whitespace',''); fclose(fid);
    L = c{1};
    if numel(L) < 28, error('Legacy param file has %d lines; expected >=28', numel(L)); end
    cfg = legacy_to_cfg(L); % map positions -> names
end
end

function m = parse_kv(txt)
m = struct();
lines = regexp(txt,'\r\n|\r|\n','split');
for i=1:numel(lines)
    line = strtrim(lines{i});
    if isempty(line) || startsWith(line,'#'), continue; end
    t = regexp(line,'^([^=]+)=(.*)$','tokens','once');
    if isempty(t), error('Bad line in key=value config: %s', line); end
    key = matlab.lang.makeValidName(strtrim(t{1}));
    val = strtrim(t{2});
    num = str2double(val);
    if ~isnan(num) && ~startsWith(lower(val),'0x')
        m.(key) = num;
    else
        m.(key) = val;
    end
end
end

function v = getenv_default(k, d)
v = getenv(k); if isempty(v), v = d; end
end

function v = getfield_default(s, f, d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function v = numfield(s, f, d)
if nargin<3, d = NaN; end
if isfield(s,f), v = double(s.(f)); else, v = d; end
end

function v = strfield(s, f, d)
if nargin<3, d = ""; end
if isfield(s,f), v = string(s.(f)); else, v = string(d); end
v = char(v);
end

function cfg = legacy_to_cfg(L)
% map your legacy positions -> named fields
cfg.NMpath           = L{1};
cfg.datpath          = L{2};
cfg.jobdir           = L{3};
cfg.analind          = str2double(L{4});
cfg.multiflag        = str2double(L{5});
cfg.saveparam        = str2double(L{6});
cfg.loadparam        = str2double(L{7});
cfg.writeCV2flag     = str2double(L{8});
cfg.ovrwrt           = str2double(L{9});
cfg.optparamspath    = L{10};
cfg.optmodelspath    = L{11};
cfg.CV1flag          = str2double(L{12});
cfg.lowmemflag       = str2double(L{13});
cfg.CVRnorm          = str2double(L{14});
cfg.imagingflag      = str2double(L{15});
cfg.spacedefimg_path = L{16};
cfg.curCPU           = str2double(L{17});
cfg.numCPU           = str2double(L{18});
cfg.grid.perm_start  = str2double(L{19});
cfg.grid.perm_end    = str2double(L{20});
cfg.grid.fold_start  = str2double(L{21});
cfg.grid.fold_end    = str2double(L{22});
cfg.DecompMode       = str2double(L{23});
cfg.simCorrThresh    = str2double(L{24});
cfg.simCorrMethod    = L{25};
cfg.CorrCompCutOff   = str2double(L{26});
cfg.SelCompCutOff    = str2double(L{27});
cfg.fdr_comp_search  = str2double(L{28});
end
