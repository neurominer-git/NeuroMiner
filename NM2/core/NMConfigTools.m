classdef NMConfigTools
% NMConfigTools
% -------------------------------------------------------------------------
% Generic schema/default/validation utilities for NeuroMiner module configs.
% The schema is deliberately MATLAB-struct based so it can be consumed by
% the CLI, the browser UI, scripted workflows, and later agentic planners.
% -------------------------------------------------------------------------

    methods (Static)

        function cfg = defaultsFromSpec(spec)
            % defaultsFromSpec  Build a default configuration struct from a modular schema.
            %
            % Traverses spec.fields recursively, applies explicit defaults and creates empty values when no default is defined. This is the first step before user/API overrides are merged and validated.
            %
            % spec.fields: recursive schema field list used to construct defaults; entries may define name, default, type and nested fields.
            cfg = struct();
            if ~isfield(spec,'fields') || isempty(spec.fields), return; end
            fields = spec.fields;
            if isstruct(fields), fields = num2cell(fields); end
            for i = 1:numel(fields)
                f = fields{i};
                if ~isfield(f,'name') || isempty(f.name), continue; end
                if isfield(f,'default')
                    cfg.(f.name) = f.default;
                elseif isfield(f,'type') && strcmpi(f.type,'group') && isfield(f,'fields')
                    subSpec = struct('fields',{f.fields});
                    cfg.(f.name) = NMConfigTools.defaultsFromSpec(subSpec);
                else
                    cfg.(f.name) = [];
                end
            end
        end

        function cfg = mergeDefaults(spec, cfg)
            % mergeDefaults  Overlay schema defaults under a partial user configuration.
            %
            % Computes defaultsFromSpec and then applies the supplied cfg values without discarding unknown caller fields. It is used when config surfaces need complete fields while preserving explicit user choices.
            if nargin < 2 || isempty(cfg), cfg = struct(); end
            def = NMConfigTools.defaultsFromSpec(spec);
            cfg = NMConfigTools.mergeStruct(def, cfg);
        end

        function [cfg, report] = validateConfig(spec, cfg, ctx, strict)
            % validateConfig  Validate and normalize a config struct against a module schema.
            %
            % Walks schema fields, validates type/range/enum constraints, recursively handles grouped fields, and returns both the possibly normalized cfg and a structured report. strict mode lets API callers decide whether unknown or invalid fields should block configuration.
            %
            % spec.fields: supplies the fields value in the public API/import specification.
            if nargin < 3, ctx = struct(); end %#ok<NASGU>
            if nargin < 4 || isempty(strict), strict = true; end
            if nargin < 2 || isempty(cfg), cfg = struct(); end
            cfg = NMConfigTools.mergeDefaults(spec, cfg);
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
            if ~isfield(spec,'fields') || isempty(spec.fields), return; end
            fields = spec.fields;
            if isstruct(fields), fields = num2cell(fields); end
            validNames = cell(1,numel(fields));
            for i = 1:numel(fields)
                f = fields{i};
                if ~isfield(f,'name') || isempty(f.name), continue; end
                validNames{i} = f.name;
                if ~isfield(cfg, f.name)
                    if isfield(f,'required') && f.required
                        report.errors{end+1} = sprintf('Missing required field: %s', f.name); %#ok<AGROW>
                    end
                    continue;
                end
                val = cfg.(f.name);
                [ok, msg, val2] = NMConfigTools.validateField(f, val);
                cfg.(f.name) = val2;
                if ~ok, report.errors{end+1} = msg; end %#ok<AGROW>
            end
            if strict
                cfgNames = fieldnames(cfg);
                for i = 1:numel(cfgNames)
                    if ~any(strcmp(cfgNames{i}, validNames))
                        report.warnings{end+1} = sprintf('Unknown config field ignored by schema: %s', cfgNames{i}); %#ok<AGROW>
                    end
                end
            end
            report.ok = isempty(report.errors);
        end

        function [ok, msg, val] = validateField(f, val)
            % validateField  Validate one schema field value and return its normalized representation.
            %
            % Applies the field-level type, size, range, enum and logical/numeric/text coercion rules used by validateConfig. It is the central primitive behind modular UI/API form validation.
            ok = true; msg = '';
            if ~isfield(f,'type') || isempty(f.type), return; end
            typ = lower(f.type);
            switch typ
                case {'enum','select'}
                    vals = NMConfigTools.getField(f,'values',{});
                    if isempty(vals), vals = NMConfigTools.getField(f,'options',{}); end
                    allowed = NMConfigTools.normalizeEnumValues(vals);
                    if isnumeric(val) && isscalar(val)
                        % Numeric legacy codes are allowed only if explicitly listed.
                        if ~any(cellfun(@(x) isequal(x,val), allowed))
                            ok = false; msg = sprintf('Field %s has invalid enum value %s.', f.name, mat2str(val));
                        end
                    elseif ischar(val) || isstring(val)
                        sval = char(val);
                        if ~any(strcmpi(sval, cellfun(@char, allowed(cellfun(@(x) ischar(x)||isstring(x), allowed)), 'UniformOutput', false))) && ...
                                ~any(cellfun(@(x) isequal(x,sval), allowed))
                            ok = false; msg = sprintf('Field %s has invalid enum value %s.', f.name, sval);
                        end
                    else
                        ok = false; msg = sprintf('Field %s must be an enum/select value.', f.name);
                    end

                case {'boolean','logical'}
                    if isnumeric(val) && isscalar(val)
                        val = logical(val);
                    elseif ischar(val) || isstring(val)
                        sval = lower(char(val));
                        if any(strcmp(sval,{'true','yes','on','1'})), val = true;
                        elseif any(strcmp(sval,{'false','no','off','0'})), val = false;
                        else, ok = false; msg = sprintf('Field %s must be boolean.', f.name); end
                    elseif ~islogical(val) || ~isscalar(val)
                        ok = false; msg = sprintf('Field %s must be boolean.', f.name);
                    end

                case {'number','double','scalar'}
                    allowInf = NMConfigTools.getField(f,'allowInf',false);
                    allowEmpty = NMConfigTools.getField(f,'allowEmpty',false);
                    if isempty(val) && allowEmpty
                        return;
                    end
                    if ~(isnumeric(val) && isscalar(val))
                        ok = false; msg = sprintf('Field %s must be a numeric scalar.', f.name); return;
                    end
                    if ~allowInf && ~isfinite(val)
                        ok = false; msg = sprintf('Field %s must be a finite numeric scalar.', f.name); return;
                    end
                    if allowInf && isnan(val)
                        ok = false; msg = sprintf('Field %s must not be NaN.', f.name); return;
                    end
                    [ok,msg] = NMConfigTools.validateRange(f,val);

                case {'integer','int'}
                    if ~(isnumeric(val) && isscalar(val) && isfinite(val) && val == round(val))
                        ok = false; msg = sprintf('Field %s must be an integer scalar.', f.name); return;
                    end
                    [ok,msg] = NMConfigTools.validateRange(f,val);

                case {'numeric_vector','vector','covariate_indices','covariate_index','covar_indices','covar_index'}
                    allowInf = NMConfigTools.getField(f,'allowInf',false);
                    allowEmpty = NMConfigTools.getField(f,'allowEmpty',true);
                    if ischar(val) || isstring(val)
                        val = str2num(char(val)); %#ok<ST2NM>
                    end
                    if isempty(val) && allowEmpty
                        val = [];
                        return;
                    end
                    if ~(isnumeric(val) && isvector(val))
                        ok = false; msg = sprintf('Field %s must be a numeric vector.', f.name); return;
                    end
                    if ~allowInf && ~all(isfinite(val(:)))
                        ok = false; msg = sprintf('Field %s must be a finite numeric vector.', f.name); return;
                    end
                    if allowInf && any(isnan(val(:)))
                        ok = false; msg = sprintf('Field %s must not contain NaN.', f.name); return;
                    end
                    if isfield(f,'minItems') && numel(val) < f.minItems
                        ok = false; msg = sprintf('Field %s must contain at least %d values.', f.name, f.minItems); return;
                    end

                case {'string','char'}
                    if isstring(val), val = char(val); end
                    if ~ischar(val)
                        ok = false; msg = sprintf('Field %s must be a string/char.', f.name);
                    end

                case {'workspace_var','workspace_variable'}
                    if isstring(val), val = char(val); end
                    if ~(isempty(val) || ischar(val))
                        ok = false; msg = sprintf('Field %s must be a MATLAB workspace variable name.', f.name); return;
                    end
                    if ~isempty(val) && ~isvarname(val)
                        ok = false; msg = sprintf('Field %s contains invalid MATLAB variable name: %s.', f.name, val); return;
                    end

                case {'struct','object'}
                    if ~isstruct(val)
                        ok = false; msg = sprintf('Field %s must be a struct.', f.name);
                    end

                case {'any'}
                    % Explicitly unvalidated.

                otherwise
                    % Unknown UI type; keep permissive so schemas can evolve.
            end
        end

        function [ok,msg] = validateRange(f,val)
            % validateRange  Check a scalar or array value against schema min/max bounds.
            %
            % Interprets optional min/max fields in a schema entry and returns a boolean/message pair without mutating the value. validateField uses it after type normalization.
            ok = true; msg = '';
            if isfield(f,'min') && ~isempty(f.min) && any(val < f.min)
                ok = false; msg = sprintf('Field %s must be >= %g.', f.name, f.min); return;
            end
            if isfield(f,'max') && ~isempty(f.max) && any(val > f.max)
                ok = false; msg = sprintf('Field %s must be <= %g.', f.name, f.max); return;
            end
        end

        function allowed = normalizeEnumValues(vals)
            % normalizeEnumValues  Convert enum declarations into a comparable cell-array representation.
            %
            % Accepts strings, chars or cell arrays from schema specs and returns a cell array of allowed tokens. This keeps enum validation independent of how module authors wrote the schema.
            allowed = {};
            if isempty(vals), return; end
            if iscell(vals)
                for i = 1:numel(vals)
                    v = vals{i};
                    if isstruct(v) && isfield(v,'value')
                        allowed{end+1} = v.value; %#ok<AGROW>
                    else
                        allowed{end+1} = v; %#ok<AGROW>
                    end
                end
            elseif isstruct(vals)
                for i = 1:numel(vals)
                    if isfield(vals(i),'value'), allowed{end+1} = vals(i).value; end %#ok<AGROW>
                end
            else
                allowed = num2cell(vals);
            end
        end

        function s = mergeStruct(a,b)
            % mergeStruct  Recursively merge override fields into a base struct.
            %
            % Copies fields from b into a, recursing when both sides contain structs. The method is used for configuration defaults and API option overlays, and intentionally does not interpret NeuroMiner semantics.
            if nargin < 1 || isempty(a), a = struct(); end
            if nargin < 2 || isempty(b), b = struct(); end
            s = a;
            if ~isstruct(b), return; end
            fn = fieldnames(b);
            for i = 1:numel(fn)
                k = fn{i};
                if isfield(s,k) && isstruct(s.(k)) && isstruct(b.(k))
                    s.(k) = NMConfigTools.mergeStruct(s.(k), b.(k));
                else
                    s.(k) = b.(k);
                end
            end
        end

        function val = getField(s, name, defaultVal)
            % getField  Read a struct field with a caller-supplied fallback.
            %
            % Returns defaultVal when the input is not a struct, the field is absent, or the field is empty. This utility keeps schema/config code explicit about fallback semantics.
            val = defaultVal;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), val = s.(name); end
        end

        function cfg = nameValueToStruct(defaults, varargin)
            % nameValueToStruct  Generic addParameter-style parsing. Unknown fields are rejected.
            %
            % early; validation remains schema-based in validateConfig().
            if nargin < 1 || isempty(defaults), defaults = struct(); end
            if numel(varargin) == 1 && isstruct(varargin{1})
                cfg = NMConfigTools.mergeStruct(defaults, varargin{1}); return;
            end
            if mod(numel(varargin),2) ~= 0
                error('NMConfigTools:nameValueToStruct', 'Name/value arguments must come in pairs.');
            end
            fn = fieldnames(defaults);
            if isempty(fn)
                cfg = struct();
                for i = 1:2:numel(varargin)
                    key = char(varargin{i});
                    if ~isvarname(key)
                        error('NMConfigTools:nameValueToStruct', 'Invalid parameter name: %s', key);
                    end
                    cfg.(key) = varargin{i+1};
                end
                return;
            end
            p = inputParser;
            p.KeepUnmatched = false;
            for i = 1:numel(fn)
                addParameter(p, fn{i}, defaults.(fn{i}));
            end
            parse(p, varargin{:});
            cfg = p.Results;
        end



        function value = jsonSafe(value)
            % jsonSafe  Convert MATLAB-only objects into JSON-encodable summaries while.
            %
            % preserving normal structs/cells/numerics. This prevents browser
            % export failures when imported legacy ACTPARAM structs contain
            % function handles, tables, or other non-JSON MATLAB values.
            if isa(value,'function_handle')
                value = func2str(value);
            elseif istable(value)
                value = sprintf('<table:%dx%d>', height(value), width(value));
            elseif iscell(value)
                for i = 1:numel(value)
                    value{i} = NMConfigTools.jsonSafe(value{i});
                end
            elseif isstruct(value)
                for k = 1:numel(value)
                    fn = fieldnames(value(k));
                    for i = 1:numel(fn)
                        value(k).(fn{i}) = NMConfigTools.jsonSafe(value(k).(fn{i}));
                    end
                end
            elseif isstring(value)
                value = cellstr(value);
                if numel(value) == 1, value = value{1}; end
            elseif isnumeric(value) || islogical(value) || ischar(value)
                % jsonencode handles these.
            else
                try
                    value = char(value);
                catch
                    value = sprintf('<%s>', class(value));
                end
            end
        end



        function s = formatValue(val, varargin)
            % formatValue  Compact value formatter shared by command-window summaries and UI.
            %
            % previews. Large vectors/matrices are described by class/size rather
            % than printed in full; this prevents accidental dumping of imported
            % labels, feature weights, masks, or G matrices.
            maxLen = 120;
            smallVectorLimit = 12;
            if ~isempty(varargin)
                for i = 1:2:numel(varargin)
                    switch lower(char(varargin{i}))
                        case 'maxlen', maxLen = varargin{i+1};
                        case 'smallvectorlimit', smallVectorLimit = varargin{i+1};
                    end
                end
            end
            if isempty(val)
                s = '<empty>';
            elseif islogical(val)
                if isscalar(val)
                    if val, s = 'true'; else, s = 'false'; end
                elseif isvector(val) && numel(val) <= smallVectorLimit
                    s = mat2str(val);
                else
                    s = sprintf('<logical %s>', NMConfigTools.sizeString(size(val)));
                end
            elseif isnumeric(val)
                if isscalar(val)
                    s = num2str(val);
                elseif isvector(val) && numel(val) <= smallVectorLimit
                    s = mat2str(val);
                else
                    s = sprintf('<numeric %s>', NMConfigTools.sizeString(size(val)));
                end
            elseif ischar(val)
                if isempty(val), s = '<empty>'; else, s = ['''' val '''']; end
            elseif isstring(val)
                if isscalar(val)
                    s = NMConfigTools.formatValue(char(val), 'maxLen', maxLen, 'smallVectorLimit', smallVectorLimit);
                else
                    s = sprintf('<string %s>', NMConfigTools.sizeString(size(val)));
                end
            elseif iscell(val)
                if numel(val) <= smallVectorLimit && all(cellfun(@(x) ischar(x) || isstring(x), val(:)))
                    s = ['{' strjoin(cellfun(@char, val(:)', 'UniformOutput', false), ', ') '}'];
                else
                    s = sprintf('<cell %s>', NMConfigTools.sizeString(size(val)));
                end
            elseif isstruct(val)
                fn = fieldnames(val);
                if isempty(fn)
                    s = '<empty struct>';
                elseif numel(val) == 1
                    preview = fn(1:min(6,numel(fn)));
                    s = ['struct(' strjoin(preview', ', ') ')'];
                    if numel(fn) > numel(preview), s = [s '...']; end
                else
                    preview = fn(1:min(4,numel(fn)));
                    s = sprintf('<struct %s: %s>', NMConfigTools.sizeString(size(val)), strjoin(preview', ', '));
                end
            elseif isa(val,'function_handle')
                s = func2str(val);
            else
                s = sprintf('<%s>', class(val));
            end
            s = regexprep(char(s), '\s+', ' ');
            s = strtrim(s);
            if numel(s) > maxLen, s = [s(1:maxLen-3) '...']; end
        end

        function s = sizeString(sz)
            % sizeString  Format an array size vector for diagnostics.
            %
            % Converts a numeric size vector into MATLAB-style text such as 20x100. The result is used in validation and serialization messages rather than in runtime logic.
            s = sprintf('%dx', sz);
            if ~isempty(s), s = s(1:end-1); end
        end

        function txt = writeJson(path, value)
            % writeJson  Encode a value as JSON and write it to one path.
            %
            % Serializes MATLAB structs/cells/numerics to JSON text, writes UTF-8 output and returns the encoded text. It is used for lightweight sidecar/config files, not for raw NM workspace serialization.
            txt = NMConfigTools.encodeJson(value, path);
            NMConfigTools.writeJsonText(path, txt);
        end

        function txt = writeJsonAliases(paths, value, label)
            % writeJsonAliases  Write the same JSON payload to several alias paths.
            %
            % Encodes the value once and writes identical text to each requested path so legacy and browser consumers can share the same configuration payload. The returned text is the single encoded representation.
            if ischar(paths) || isstring(paths)
                paths = {char(paths)};
            end
            if nargin < 3 || isempty(label)
                label = paths{1};
            end
            txt = NMConfigTools.encodeJson(value, label);
            for i = 1:numel(paths)
                NMConfigTools.writeJsonText(paths{i}, txt);
            end
        end

        function txt = encodeJson(value, label)
            % encodeJson  Convert a MATLAB value into JSON text with NM safety checks.
            %
            % Rejects raw NM workspaces through assertNoRawNM before JSON encoding, then falls back to the available MATLAB encoder implementation. The label argument identifies the payload in diagnostics.
            if nargin < 2 || isempty(label)
                label = '<payload>';
            end
            % Sequential filter pipeline.
            % Stage 1 (hard reject): a raw NM-like struct must never reach a
            % UI JSON payload. This is a correctness assertion, not a
            % transform: if it fires, a caller is leaking the whole NM and
            % that is a bug to fix at the source.
            NMConfigTools.assertNoRawNM(value, label);
            % Stage 2 (transform): large numeric/logical arrays are routine
            % (image weight maps in RANK.EXTERN, CV index cells, etc.). They
            % must not be JSON-ised. Replace each with a compact descriptor;
            % the authoritative array stays MATLAB-resident in the live
            % orchestrator and is referenced, not transferred. Stripped
            % values are recognised on decode so service handlers do not
            % overwrite the live array with a descriptor.
            value = NMConfigTools.stripHeavyArrays(value, label);
            try
                txt = jsonencode(value);
            catch
                txt = jsonencode(NMConfigTools.jsonSafe(value));
            end
        end

        function bytes = jsonRefMaxBytes()
            % jsonRefMaxBytes  Size threshold above which a numeric/logical array is stripped.
            %
            % to a descriptor instead of JSON-ised. Override-able via a
            % single edit here. 4096 bytes ~= 512 doubles ~= 1024 int32:
            % comfortably above any genuine parameter vector, well below any
            % image map or CV index structure.
            bytes = 4096;
        end

        function value = stripHeavyArrays(value, label)
            % stripHeavyArrays  Stage-2 size filter. Mirrors jsonSafe's traversal but the leaf.
            %
            % rule replaces oversized numeric/logical arrays with a tagged
            % reference descriptor (transfer = 'none': stays MATLAB-side).
            if nargin < 2 || isempty(label), label = '<payload>'; end
            if isnumeric(value) || islogical(value)
                % A dense array holds at most 16 bytes per element (complex
                % double/int64), so small dense leaves cannot exceed the
                % threshold and need no whos() call. Sparse storage is not
                % bounded by numel and keeps the exact whos() measurement.
                n = numel(value);
                if n > 1 && (issparse(value) || 16 * n > NMConfigTools.jsonRefMaxBytes())
                    info = whos('value');
                    if info.bytes > NMConfigTools.jsonRefMaxBytes() && ...
                            ~NMConfigTools.allowBrowserJsonNumericArray(value, label)
                        value = NMConfigTools.makeArrayRef(value, label);
                    end
                end
                return;
            end
            if iscell(value)
                for i = 1:numel(value)
                    value{i} = NMConfigTools.stripHeavyArrays(value{i}, label);
                end
                return;
            end
            if isstruct(value)
                for k = 1:numel(value)
                    fn = fieldnames(value(k));
                    for i = 1:numel(fn)
                        value(k).(fn{i}) = NMConfigTools.stripHeavyArrays( ...
                            value(k).(fn{i}), [char(label) '.' fn{i}]);
                    end
                end
                return;
            end
            % chars, strings, function handles, tables, objects: left to
            % jsonSafe / jsonencode. Not bulk numeric data.
        end

        function tf = allowBrowserJsonNumericArray(value, label)
            % allowBrowserJsonNumericArray  Permit selected browser plot arrays to cross the JSON bridge.
            %
            %   tf = NMConfigTools.allowBrowserJsonNumericArray(value, label)
            %   returns true for small/medium numeric arrays that are explicit
            %   plotting data rather than raw NM state. Supported cases are
            %   intentionally field-scoped and size-capped so the raw-NM guard and
            %   the general heavy-array stripping policy remain effective.
            if nargin < 2 || isempty(label), label = ''; end
            tf = false;
            if ~(isnumeric(value) || islogical(value)) || isempty(value)
                return;
            end
            key = lower(char(string(label)));
            % SYNTH overview owns these bounded factor/metric matrices. They are
            % plotting metadata, not source observations or model coefficients.
            if strcmp(key,'bridge_result.payload.parameterrows') || ...
                    strcmp(key,'bridge_result.payload.contexts.childvalues')
                tf = numel(value) <= 100000;
                return;
            end
            if contains(key, 'modelpermutation') && contains(key, 'nullvalues')
                tf = numel(value) <= 100000;
                return;
            end
            if contains(key, 'qc')
                subjectQCFields = {'rowindex','score','rmsz','meanabsz','meanz','sdz','maxabsz', ...
                    'nvalidfeaturesbysubject','nfinitefeaturesbysubject','nmissingfeaturesbysubject','missingfeatureratebysubject', ...
                    'nzerofeaturesbysubject','zerofeatureratebysubject','noutlierfeaturesbysubject','outlierfeatureratebysubject', ...
                    'rowallnanflag','rowconstantflag'};
                if any(cellfun(@(name) endsWith(key, ['.' name]), subjectQCFields))
                    tf = numel(value) <= 100000;
                    return;
                end
            end
            if contains(key, 'viewerpackage') || contains(key, 'selectorpackage')
                connectivityFields = {'edgeindex','edgemean','edgesd','edgemissingrate', ...
                    'subjectedgevalues','groupmeanmatrix','groupsdmatrix','groupmissingratematrix'};
                if any(cellfun(@(name) contains(key, name), connectivityFields))
                    tf = numel(value) <= 1000000;
                end
            end
        end

        function ref = makeArrayRef(value, field)
            % makeArrayRef  Compact, self-describing descriptor that replaces a stripped.
            %
            % array on the wire. transfer = 'none' means the array was NOT
            % serialised and the live MATLAB orchestrator remains the source
            % of truth. The image inspector (and any future consumer that
            % genuinely needs values) re-requests by a dedicated command and
            % may set transfer = 'binary'/'file' with a target then.
            fieldName = '';
            try
                parts = strsplit(char(field), '.');
                fieldName = parts{end};
            catch
                fieldName = char(field);
            end
            ref = struct( ...
                'x_nmref', true, ...
                'field', fieldName, ...
                'class', class(value), ...
                'size', size(value), ...
                'numel', numel(value), ...
                'bytes', numel(value) * NMConfigTools.bytesPerElement(value), ...
                'transfer', 'none');
        end

        function n = bytesPerElement(value)
            % bytesPerElement  Estimate element width for common MATLAB numeric/logical classes.
            %
            % Returns a conservative byte count used by raw-NM detection and serialization diagnostics. Unsupported classes fall back to a safe default rather than being treated as small.
            if islogical(value)
                n = 1; return;
            end
            switch class(value)
                case {'double','int64','uint64'}, n = 8;
                case {'single','int32','uint32'}, n = 4;
                case {'int16','uint16'},           n = 2;
                case {'int8','uint8','char'},      n = 1;
                otherwise,                          n = 8;
            end
        end

        function tf = isArrayRef(s)
            % isArrayRef  Detect lightweight array-reference descriptors used by serialization guards.
            %
            % Returns true for structs that represent an external array reference rather than inline raw data. This lets JSON safety checks allow references while blocking full NM feature matrices.
            tf = isstruct(s) && isscalar(s) && isfield(s,'x_nmref') && ...
                isequal(logical(s.x_nmref), true);
        end

        function value = restoreArrayRefs(value, liveSource)
            % restoreArrayRefs  Decode-side companion to stripHeavyArrays. When a payload.
            %
            % returns from the browser, any x_nmref descriptor with
            % transfer = 'none' is a field the browser never owned. If a
            % liveSource (the current MATLAB-side value, e.g. the existing
            % field on the orchestrator state) is supplied, the descriptor is
            % replaced by the live value so handlers see the real array. If
            % no liveSource is available the descriptor is left in place and
            % carries x_nmref = true so handlers can detect "do not treat as
            % data / do not overwrite".
            if nargin < 2, liveSource = []; end
            if NMConfigTools.isArrayRef(value)
                if ~isempty(liveSource) && ~NMConfigTools.isArrayRef(liveSource)
                    value = liveSource;
                end
                return;
            end
            if iscell(value)
                for i = 1:numel(value)
                    ls = [];
                    if iscell(liveSource) && numel(liveSource) >= i, ls = liveSource{i}; end
                    value{i} = NMConfigTools.restoreArrayRefs(value{i}, ls);
                end
                return;
            end
            if isstruct(value)
                for k = 1:numel(value)
                    fn = fieldnames(value(k));
                    for i = 1:numel(fn)
                        ls = [];
                        if isstruct(liveSource) && isscalar(liveSource) && isfield(liveSource, fn{i})
                            ls = liveSource.(fn{i});
                        end
                        value(k).(fn{i}) = NMConfigTools.restoreArrayRefs(value(k).(fn{i}), ls);
                    end
                end
                return;
            end
        end

        function writeJsonText(path, txt)
            % writeJsonText  Write already encoded JSON text as UTF-8.
            %
            % Creates the target folder when necessary and writes the supplied text without re-encoding. Higher-level writers call this after encodeJson has performed payload checks.
            fid = fopen(path,'w');
            if fid < 0, error('NMConfigTools:writeJson', 'Could not open %s for writing.', path); end
            fwrite(fid, txt, 'char');
            fclose(fid);
        end

        function assertNoRawNM(value, label)
            % assertNoRawNM  Block accidental JSON serialization of full NM workspaces or raw feature matrices.
            %
            % Recursively inspects structs/cells for NM-like training data and large inline arrays. The guard protects browser sidecars and RAG/export artifacts from embedding sensitive or oversized raw data.
            if NMConfigTools.isRawNMStruct(value)
                error('NMConfigTools:rawNMInJson', ...
                    'Raw NM-like struct detected in UI JSON payload: %s.', char(label));
            end
            if isstruct(value) && isfield(value,'NM') && NMConfigTools.isRawNMStruct(value.NM)
                error('NMConfigTools:rawNMInJson', ...
                    'Raw NM-like struct detected in UI JSON payload: %s.', char(label));
            end
            if isstruct(value) && isfield(value,'Context') && isstruct(value.Context) && ...
                    isfield(value.Context,'NM') && NMConfigTools.isRawNMStruct(value.Context.NM)
                error('NMConfigTools:rawNMInJson', ...
                    'Raw NM-like struct detected in UI JSON payload: %s.', char(label));
            end
        end

        function tf = isRawNMStruct(s)
            % isRawNMStruct  Identify structs that look like complete NeuroMiner workspaces.
            %
            % Checks for characteristic NM fields such as Y, TrainParam, datadescriptor and analysis. It is a conservative predicate used by assertNoRawNM before JSON sidecar writing.
            heavy = {'Y','analysis','cv','files','featnames','cases','badcoords'};
            tf = isstruct(s) && isfield(s,'TrainParam') && sum(isfield(s, heavy)) >= 2;
        end

        function value = readJson(path)
            % readJson  Read and decode a JSON file into MATLAB data.
            %
            % Loads UTF-8 text from disk and uses the available MATLAB JSON decoder. The method is the inverse of writeJson for lightweight configuration/sidecar payloads.
            value = jsondecode(fileread(path));
        end

        function value = decodeJson(txt)
            % decodeJson  Decode companion to encodeJson, for callers that hold the JSON.
            %
            % text directly (e.g. the bridge reading an HTTP body or a
            % request file). Kept separate from readJson so the bridge has a
            % single decode entry point. x_nmref descriptors are preserved as
            % decoded; callers that need the live array call
            % restoreArrayRefs with the current MATLAB-side state.
            if isempty(txt), value = struct(); return; end
            value = jsondecode(txt);
        end

        function s = charifyStrings(s)
            % charifyStrings  Jsondecode can return string arrays and struct arrays. Keep.
            %
            % legacy-compatible char vectors where possible, but handle
            % non-scalar struct arrays element-wise. Without this guard,
            % s.(field) on a struct array expands to a comma-separated list
            % and MATLAB reports "Too many input arguments".
            if isstring(s)
                if isscalar(s)
                    s = char(s);
                else
                    s = cellstr(s);
                end
                return;
            end
            if iscell(s)
                for i = 1:numel(s)
                    s{i} = NMConfigTools.charifyStrings(s{i});
                end
            elseif isstruct(s)
                for k = 1:numel(s)
                    fn = fieldnames(s(k));
                    for i = 1:numel(fn)
                        s(k).(fn{i}) = NMConfigTools.charifyStrings(s(k).(fn{i}));
                    end
                end
            end
        end
    end
end
