classdef NMConfigureAPITools
% NMConfigureAPITools
% -------------------------------------------------------------------------
% Small shared helpers for public, non-interactive cli_configure APIs used by
% the train-template scaffold export.  The helpers deliberately do not know
% about NeuroMiner backend semantics; they only merge an optional existing
% state/configuration struct with name/value modifications and create a small
% validation report.  The owning configurator remains responsible for
% normalization and legacy materialization.
% -------------------------------------------------------------------------

    methods (Static)
        function [state, rest, report] = parseState(defaultState, args, reservedNames, strict)
            % parseState  Merge optional state and name/value updates for public configure APIs.
            %
            % Accepts a default state, an argument cell array, optional aliases and reserved option names. It returns the updated state, unconsumed arguments and a report so each owning tool can perform domain-specific normalization and legacy materialization.
            state = defaultState;
            rest = args;
            report = NMConfigureAPITools.report(true, 'Configuration parsed.');
            if ~isempty(rest) && (isempty(rest{1}) || isstruct(rest{1}))
                if isstruct(rest{1})
                    state = NMConfigureAPITools.mergeStruct(state, rest{1});
                end
                rest = rest(2:end);
            end
            if mod(numel(rest),2) ~= 0
                report.ok = false;
                report.errors{end+1} = 'Name/value arguments must occur in pairs.';
                return;
            end
            for i = 1:2:numel(rest)
                name = rest{i};
                val = rest{i+1};
                if ~(ischar(name) || (isstring(name) && isscalar(name)))
                    report.ok = false;
                    report.errors{end+1} = sprintf('Argument %d is not a valid option name.', i);
                    continue;
                end
                key = char(string(name));
                if ismember(key,reservedNames), continue; end
                if ~ismember(key,fieldnames(state))
                    report.warnings{end+1} = sprintf('Unknown option ''%s'' ignored.', key);
                    continue;
                end
                state = NMConfigureAPITools.mergeStruct(state, struct(key, {val}));
            end
            if strict
                unknown = setdiff(fieldnames(state), fieldnames(defaultState));
                report.errors = [report.errors, report.warnings, strcat('Unknown option: ', unknown)'];
            end
            report.ok = isempty(report.errors);
        end

        function state = normalizeChoices(state, choices, errorID)
            % Resolve only owner-declared categorical API fields, recursively.
            names = fieldnames(choices);
            for k = 1:numel(names)
                key = names{k};
                c = choices.(key);
                if ~ismember('symbol',fieldnames(c))
                    state.(key) = NMConfigureAPITools.normalizeChoices(state.(key),c,errorID);
                    continue;
                end
                value = state.(key);
                ix = find(strcmp(value,{c.symbol}),1);
                if ~isempty(ix)
                    state.(key) = c(ix).code;
                else
                    assert(any(cellfun(@(code)isequal(code,value),{c.code})), ...
                        errorID,'Invalid categorical option %s.',key);
                end
            end
        end

        function val = optionValue(args, name, defaultVal)
            % Read the canonical routing key from the public name/value list.
            val = defaultVal;
            if isempty(args), return; end
            startIdx = 1;
            if ~isempty(args) && (isempty(args{1}) || isstruct(args{1})), startIdx = 2; end
            if mod(numel(args)-startIdx+1,2), return; end
            for k = startIdx:2:numel(args)
                if strcmp(args{k},name), val = args{k+1}; return; end
            end
        end

        function state = mergeStruct(base, update)
            % mergeStruct  Shallow-merge user state fields into a default state.
            %
            % Copies fields from update into base without interpreting backend semantics. This keeps generic CLI parsing separate from module-specific validation performed by normalizeState/applyToNM.
            state = base;
            fn = fieldnames(update);
            for i = 1:numel(fn)
                f = fn{i};
                if isfield(state, f) && isstruct(state.(f)) && isstruct(update.(f)) && isscalar(state.(f)) && isscalar(update.(f))
                    state.(f) = NMConfigureAPITools.mergeStruct(state.(f), update.(f));
                else
                    state.(f) = update.(f);
                end
            end
        end

        function report = report(ok, message)
            % report  Create the fixed-schema report returned by configure helpers.
            %
            % Returns a scalar struct with ok/message/error fields so all public cli_configure methods expose consistent success and failure metadata.
            if nargin < 1 || isempty(ok), ok = true; end
            if nargin < 2, message = ''; end
            report = struct('ok', logical(ok), 'message', char(string(message)), 'errors', {{}}, 'warnings', {{}});
        end

        function report = appendException(report, ME)
            % appendException  Attach a caught exception to a configure report.
            %
            % Marks the report as failed and stores the exception identifier, message and stack. This preserves diagnostics for API callers instead of silently hiding configuration errors.
            report.ok = false;
            report.errors{end+1} = ME.message;
            report.exception = ME.message;
            report.identifier = ME.identifier;
        end


        function tf = hasModifications(args)
            % Existing calls mark dirty only for explicit name/value updates.
            tf = false;
            if isempty(args), return; end
            startIdx = 1;
            if ~isempty(args) && (isempty(args{1}) || isstruct(args{1})), startIdx = 2; end
            tf = numel(args) >= startIdx + 1;
        end

        function out = choiceText(c)
            entries = cell(1,numel(c));
            for j = 1:numel(c)
                entries{j} = sprintf('''%s'': %s', c(j).symbol, c(j).description);
            end
            out = strjoin(entries,newline);
        end

        function txt = formatConfigSpec(spec)
            % Render authoritative configuration metadata for the Command Window.
            rule = repmat('=',1,76);
            lines = {rule, sprintf('%s (%s)',spec.title,spec.id),rule, spec.description};
            nested = {};
            for k = 1:numel(spec.fields)
                f = spec.fields{k};
                lines{end+1} = ''; %#ok<AGROW>
                lines{end+1} = '+++++'; %#ok<AGROW>
                lines{end+1} = sprintf('%s (%s)',f.label,f.name); %#ok<AGROW>
                lines{end+1} = sprintf('  Type:    %s',f.type); %#ok<AGROW>
                lines{end+1} = sprintf('  Default: %s',NMConfigureAPITools.helpValueText(f.default)); %#ok<AGROW>
                helpText = '(not documented in configSpec)';
                names = fieldnames(f);
                for j = 1:numel(names)
                    switch names{j}
                        case 'values'
                            values = NMConfigTools.normalizeEnumValues(f.values);
                            rendered = cellfun(@NMConfigureAPITools.helpValueText,values,'UniformOutput',false);
                            switch class(f.values)
                                case 'cell'
                                    if ~isempty(f.values)
                                        switch class(f.values{1})
                                            case 'struct'
                                                for j = 1:numel(values)
                                                    entry = f.values{j};
                                                    rendered{j} = sprintf('%s (%s)',rendered{j},entry.label);
                                                    if any(strcmp(fieldnames(entry),'symbol'))
                                                        rendered{j} = sprintf('%s [%s]',rendered{j},entry.symbol);
                                                    end
                                                end
                                        end
                                    end
                            end
                            lines{end+1} = sprintf('  Choices: %s',strjoin(rendered,', ')); %#ok<AGROW>
                        case 'min'
                            lines{end+1} = sprintf('  Minimum: %s',NMConfigureAPITools.helpValueText(f.min)); %#ok<AGROW>
                        case 'max'
                            lines{end+1} = sprintf('  Maximum: %s',NMConfigureAPITools.helpValueText(f.max)); %#ok<AGROW>
                        case 'help'
                            helpText = f.help;
                    end
                end
                lines{end+1} = sprintf('  Help:    %s',helpText); %#ok<AGROW>
                if strcmp(f.type,'subconfig')
                    specs = f.subconfigSpecs;
                    keys = fieldnames(specs);
                    ids = {};
                    for j = 1:numel(keys)
                        child = specs.(keys{j});
                        if ~isempty(child.fields), ids{end+1} = child.id; end %#ok<AGROW>
                    end
                    if ~isempty(ids)
                        nested{end+1} = sprintf('%s (%s): %s',f.label,f.name,strjoin(ids,', ')); %#ok<AGROW>
                        nested{end+1} = sprintf('  Example: m.configureHelp(''algo'',''%s'')',ids{1}); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(nested)
                lines = [lines(1:4) {'' 'Nested subconfigurators available:'} nested lines(5:end)];
            end
            wrapped = cellfun(@NMConfigureAPITools.wrapConfigHelpLine,lines,'UniformOutput',false);
            txt = strjoin([wrapped{:}],newline);
        end

        function wrapped = wrapConfigHelpLine(line)
            % Wrap labels, choice lists and prose to a consistent Command Window width.
            width = 90;
            wrapped = {};
            prefix = regexp(line,'^  [A-Za-z ]+:\s+','match','once');
            if isempty(prefix)
                indent = regexp(line,'^\s*','match','once');
            else
                indent = repmat(' ',1,numel(prefix));
            end
            while numel(line) > width
                cut = find(line(1:width)==' ',1,'last');
                if isempty(cut), cut = width+1; end
                if cut <= numel(indent), cut = width+1; end
                wrapped{end+1} = deblank(line(1:cut-1)); %#ok<AGROW>
                line = [indent strtrim(line(cut:end))];
            end
            wrapped{end+1} = line;
        end

        function child = subconfigSpec(spec, id)
            % Select existing nested metadata by its public algorithm ID.
            for k = 1:numel(spec.fields)
                field = spec.fields{k};
                if ~strcmp(field.type,'subconfig'), continue; end
                specs = field.subconfigSpecs;
                keys = fieldnames(specs);
                for j = 1:numel(keys)
                    child = specs.(keys{j});
                    if strcmp(id,child.id), return; end
                end
            end
            error('NMPreprocModule:unknownSubconfig', ...
                'Unknown subconfigurator %s in %s. Call configureHelp() for available methods.',id,spec.id);
        end

        function txt = helpValueText(value)
            % Present a schema value without expanding large data defaults.
            switch class(value)
                case 'char'
                    txt = value;
                case 'string'
                    txt = strjoin(cellstr(value),', ');
                case {'double','single','logical','int8','int16','int32','int64', ...
                      'uint8','uint16','uint32','uint64'}
                    if numel(value) > 16
                        txt = sprintf('%s array of size %s',class(value),mat2str(size(value)));
                    else
                        txt = mat2str(value);
                    end
                case 'cell'
                    txt = strjoin(cellfun(@NMConfigureAPITools.helpValueText,value,'UniformOutput',false),', ');
                case 'struct'
                    names = fieldnames(value);
                    if isempty(names)
                        txt = 'struct()';
                    else
                        txt = sprintf('struct with fields: %s',strjoin(names,', '));
                    end
                otherwise
                    txt = strtrim(evalc('disp(value)'));
            end
        end

        function h = helpStruct(name, syntax, options, examples, varargin)
            % helpStruct  Build a standard help object for public configure functions.
            %
            % Packages name, syntax, option and example metadata into a fixed struct used by cli_configureHelp methods, scaffold export and RAG documentation extraction.
            if nargin < 4, examples = {}; end
            choices = struct();
            if ~isempty(varargin), choices = varargin{1}; end
            h = struct('name',name,'syntax',syntax,'options',options,'examples',{examples});
            h.choices = choices;
            names = fieldnames(choices);
            for k = 1:numel(names)
                key = names{k};
                if ismember(key,fieldnames(h.options)), continue; end
                c = choices.(key);
                h.options.(key) = NMConfigureAPITools.choiceText(c);
            end
        end
    end

end
