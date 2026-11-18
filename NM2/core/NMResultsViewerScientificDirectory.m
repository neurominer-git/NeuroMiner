classdef NMResultsViewerScientificDirectory
% NMResultsViewerScientificDirectory
% -------------------------------------------------------------------------
% Lightweight query/index authority over existing NM 2.0 scientificAnnotation
% records.
%
% Authoritative responsibility:
%   * validate already-resolved scientific annotations and index only their
%     scientific schema with opaque caller-owned payload references;
%   * query only the shared scientificAnnotation.schema vocabulary;
%   * resolve unique scientific addresses with explicit ambiguity/failure;
%   * enumerate schema values for navigation without reading NM or payload data.
%
% This class does NOT inspect NM, retain/interpret scientificAnnotation.material,
% materialize/copy payload values, define schema<->material mappings, or execute
% Report Builder / ROI Mapper behavior. Annotation construction remains owned by
% NMResultsViewerScientificAnnotation and the existing scientific payload
% authorities.
%
% Contract: NM-SCIENTIFIC-DIRECTORY-V1
% PORT-1A.1: index/query only; no downstream consumer migration.
% -------------------------------------------------------------------------

    methods (Static)
        function version = contractVersion()
            version = 'NM-SCIENTIFIC-DIRECTORY-V1';
        end

        function index = build(records)
            % build  Construct an index from caller-owned payload references.
            %
            % records must be a struct array with exactly:
            %   reference             opaque caller-owned lightweight token
            %   scientificAnnotation  canonical annotation attached to payload
            %
            % The Directory never interprets `reference`.
            if isempty(records)
                index = NMResultsViewerScientificDirectory.emptyIndex();
                return;
            end
            if ~isstruct(records) % nm2-allow: public Directory build boundary validates caller-supplied record arrays
                error('NMResultsViewerScientificDirectory:InvalidRecords', ...
                    'Directory records must be a struct array.');
            end
            expected = {'reference';'scientificAnnotation'};
            if ~isequal(sort(fieldnames(records)),sort(expected))
                error('NMResultsViewerScientificDirectory:InvalidRecords', ...
                    'Directory records must contain exactly reference and scientificAnnotation.');
            end
            index = NMResultsViewerScientificDirectory.emptyIndex();
            entries = repmat(NMResultsViewerScientificDirectory.entryTemplate(),numel(records),1);
            for ii = 1:numel(records)
                NMResultsViewerScientificAnnotation.validate(records(ii).scientificAnnotation);
                annotation = records(ii).scientificAnnotation;
                entries(ii).reference = records(ii).reference;
                entries(ii).annotationContractVersion = annotation.contractVersion;
                entries(ii).domain = annotation.domain;
                entries(ii).schema = annotation.schema;
            end
            index.entries = entries;
        end

        function validate(index)
            expectedIndex = {'contractVersion';'entries'};
            % nm2-allow: public Directory query boundary validates retained/caller-supplied index records
            if ~isstruct(index) || ~isscalar(index) || ...
                    ~isequal(sort(fieldnames(index)),sort(expectedIndex))
                error('NMResultsViewerScientificDirectory:InvalidIndex', ...
                    'Scientific Directory index must be one scalar contract struct.');
            end
            if ~strcmp(index.contractVersion,NMResultsViewerScientificDirectory.contractVersion())
                error('NMResultsViewerScientificDirectory:InvalidContractVersion', ...
                    'Scientific Directory index must implement %s.', ...
                    NMResultsViewerScientificDirectory.contractVersion());
            end
            if ~isstruct(index.entries) % nm2-allow: public Directory query boundary validates the fixed entry record family
                error('NMResultsViewerScientificDirectory:InvalidIndex', ...
                    'Scientific Directory entries must be a struct array.');
            end
            expected = {'reference';'annotationContractVersion';'domain';'schema'};
            if ~isempty(index.entries) && ...
                    ~isequal(sort(fieldnames(index.entries)),sort(expected))
                error('NMResultsViewerScientificDirectory:InvalidIndex', ...
                    'Scientific Directory entries use an invalid field schema.');
            end
            schemaTemplate = NMResultsViewerScientificAnnotation.template();
            schemaTemplate = schemaTemplate.schema;
            for ii = 1:numel(index.entries)
                if ~strcmp(index.entries(ii).annotationContractVersion, ...
                        NMResultsViewerScientificAnnotation.contractVersion())
                    error('NMResultsViewerScientificDirectory:InvalidAnnotationVersion', ...
                        'Directory entry uses an unsupported scientific-annotation contract.');
                end
                if isempty(index.entries(ii).domain) || ...
                        ~NMResultsViewerScientificDirectory.sameSchemaShape( ...
                            index.entries(ii).schema,schemaTemplate)
                    error('NMResultsViewerScientificDirectory:InvalidIndexedSchema', ...
                        'Directory entry contains an invalid indexed scientific schema.');
                end
            end
        end

        function [matches,indices] = query(index,criteria)
            % query  Return entries whose scientific schema satisfies criteria.
            %
            % criteria is a struct array with fixed fields:
            %   path   schema path, e.g. 'schema.payload.type'
            %   op     'eq' | 'contains' | 'one_of'
            %   value  criterion value
            %
            % `contains` is intended for schema fields that are collections,
            % e.g. schema.modality.varinds. `one_of` is intended for scalar
            % schema fields queried against a caller-supplied set.
            NMResultsViewerScientificDirectory.validate(index);
            criteria = NMResultsViewerScientificDirectory.validateCriteria(criteria);
            keep = true(numel(index.entries),1);
            for ee = 1:numel(index.entries)
                entry = index.entries(ee);
                for cc = 1:numel(criteria)
                    candidate = NMResultsViewerScientificDirectory.readSchemaPath( ...
                        entry,criteria(cc).path);
                    if ~NMResultsViewerScientificDirectory.matchesCriterion( ...
                            candidate,criteria(cc).op,criteria(cc).value)
                        keep(ee) = false;
                        break;
                    end
                end
            end
            indices = find(keep);
            matches = index.entries(keep);
        end

        function tf = matchesSchema(schema,criteria)
            % matchesSchema  Apply canonical Directory criteria to one schema.
            template=NMResultsViewerScientificAnnotation.template();
            if ~NMResultsViewerScientificDirectory.sameSchemaShape(schema,template.schema)
                error('NMResultsViewerScientificDirectory:InvalidIndexedSchema', ...
                    'Scientific schema does not implement the canonical annotation shape.');
            end
            criteria=NMResultsViewerScientificDirectory.validateCriteria(criteria);
            entry=struct('schema',schema); tf=true;
            for cc=1:numel(criteria)
                candidate=NMResultsViewerScientificDirectory.readSchemaPath(entry,criteria(cc).path);
                if ~NMResultsViewerScientificDirectory.matchesCriterion(candidate,criteria(cc).op,criteria(cc).value)
                    tf=false; return;
                end
            end
        end

        function entry = resolveUnique(index,criteria)
            % resolveUnique  Resolve exactly one scientific address.
            [matches,~] = NMResultsViewerScientificDirectory.query(index,criteria);
            if isempty(matches)
                error('NMResultsViewerScientificDirectory:NoMatch', ...
                    'Scientific Directory query resolved no annotated payload.');
            end
            if numel(matches) ~= 1
                error('NMResultsViewerScientificDirectory:AmbiguousMatch', ...
                    'Scientific Directory query resolved %d annotated payloads.',numel(matches));
            end
            entry = matches(1);
        end

        function values = values(index,path,criteria)
            % values  Enumerate distinct values for one schema path.
            [matches,~] = NMResultsViewerScientificDirectory.query(index,criteria);
            values = cell(0,1);
            for ii = 1:numel(matches)
                value = NMResultsViewerScientificDirectory.readSchemaPath( ...
                    matches(ii),path);
                if ~NMResultsViewerScientificDirectory.cellContains(values,value)
                    values{end+1,1} = value; %#ok<AGROW>
                end
            end
        end

    end

    methods (Static, Access = private)
        function index = emptyIndex()
            index = struct( ...
                'contractVersion',NMResultsViewerScientificDirectory.contractVersion(), ...
                'entries',repmat(NMResultsViewerScientificDirectory.entryTemplate(),0,1));
        end

        function entry = entryTemplate()
            annotationTemplate = NMResultsViewerScientificAnnotation.template();
            entry = struct('reference',[], ...
                'annotationContractVersion','', ...
                'domain','', ...
                'schema',annotationTemplate.schema);
        end

        function criteria = validateCriteria(criteria)
            if isempty(criteria)
                criteria = repmat(struct('path','','op','','value',[]),0,1);
                return;
            end
            if ~isstruct(criteria) % nm2-allow: public Directory criteria boundary validates caller-supplied query records
                error('NMResultsViewerScientificDirectory:InvalidCriteria', ...
                    'Scientific Directory criteria must be a struct array.');
            end
            expected = {'path';'op';'value'};
            if ~isequal(sort(fieldnames(criteria)),sort(expected))
                error('NMResultsViewerScientificDirectory:InvalidCriteria', ...
                    'Each criterion must contain exactly path, op, and value.');
            end
            for ii = 1:numel(criteria)
                if ~ischar(criteria(ii).path) || ~ischar(criteria(ii).op) % nm2-allow: public Directory criteria boundary requires canonical character query tokens
                    error('NMResultsViewerScientificDirectory:InvalidCriteria', ...
                        'Scientific Directory path and op must be canonical character tokens.');
                end
                path = criteria(ii).path;
                op = criteria(ii).op;
                if ~startsWith(path,'schema.')
                    error('NMResultsViewerScientificDirectory:MaterialQueryForbidden', ...
                        'Scientific Directory queries may address schema fields only.');
                end
                if ~ismember(op,{'eq','contains','one_of'})
                    error('NMResultsViewerScientificDirectory:InvalidOperator', ...
                        'Unsupported Scientific Directory operator %s.',op);
                end
                criteria(ii).path = path;
                criteria(ii).op = op;
            end
        end

        function value = readSchemaPath(entry,path)
            parts = strsplit(path,'.');
            if numel(parts) ~= 3 || ~strcmp(parts{1},'schema') % nm2-allow: Directory schema-path request boundary validates the fixed three-token annotation address
                error('NMResultsViewerScientificDirectory:UnknownSchemaPath', ...
                    'Scientific schema path %s is not available in this indexed schema.',path);
            end
            template=NMResultsViewerScientificAnnotation.template();
            groups=fieldnames(template.schema);
            if ~ismember(parts{2},groups)
                error('NMResultsViewerScientificDirectory:UnknownSchemaPath', ...
                    'Scientific schema path %s is not available in this indexed schema.',path);
            end
            fields=fieldnames(template.schema.(parts{2}));
            if ~ismember(parts{3},fields)
                error('NMResultsViewerScientificDirectory:UnknownSchemaPath', ...
                    'Scientific schema path %s is not available in this indexed schema.',path);
            end
            value = entry.schema.(parts{2}).(parts{3});
        end

        function tf = sameSchemaShape(schema,template)
            % nm2-allow: Directory retained-index boundary validates canonical annotation schema shape
            tf = isstruct(schema) && isscalar(schema) && ...
                isequal(sort(fieldnames(schema)),sort(fieldnames(template)));
            if ~tf, return; end
            groups = fieldnames(template);
            for ii = 1:numel(groups)
                group = groups{ii};
                % nm2-allow: Directory retained-index boundary validates each canonical schema group
                if ~isstruct(schema.(group)) || ~isscalar(schema.(group)) || ...
                        ~isequal(sort(fieldnames(schema.(group))), ...
                            sort(fieldnames(template.(group))))
                    tf = false;
                    return;
                end
            end
        end

        function tf = matchesCriterion(candidate,op,wanted)
            switch op
                case 'eq'
                    tf = NMResultsViewerScientificDirectory.equalValue(candidate,wanted);
                case 'contains'
                    tf = NMResultsViewerScientificDirectory.containsValue(candidate,wanted);
                case 'one_of'
                    tf = NMResultsViewerScientificDirectory.oneOf(candidate,wanted);
                otherwise
                    error('NMResultsViewerScientificDirectory:InvalidOperator', ...
                        'Unsupported Scientific Directory operator %s.',op);
            end
        end

        function tf = equalValue(a,b)
            tf = isequaln(a,b);
        end

        function tf = containsValue(candidate,wanted)
            if ischar(candidate) % nm2-allow: contains operator dispatches across canonical annotation scalar/collection value classes
                tf = NMResultsViewerScientificDirectory.equalValue(candidate,wanted);
            elseif isnumeric(candidate) || islogical(candidate) % nm2-allow: contains operator dispatches across canonical annotation scalar/collection value classes
                if ~isscalar(wanted)
                    error('NMResultsViewerScientificDirectory:InvalidContainsCriterion', ...
                        'contains requires one scalar wanted value for numeric/logical schema collections.');
                end
                tf = any(candidate(:) == wanted);
            elseif iscell(candidate) % nm2-allow: contains operator dispatches across canonical annotation scalar/collection value classes
                tf = false;
                for ii = 1:numel(candidate)
                    if NMResultsViewerScientificDirectory.equalValue(candidate{ii},wanted)
                        tf = true;
                        return;
                    end
                end
            else
                error('NMResultsViewerScientificDirectory:UnsupportedSchemaValue', ...
                    'contains does not support schema value class %s.',class(candidate));
            end
        end

        function tf = oneOf(candidate,wanted)
            if ~NMResultsViewerScientificDirectory.isScalarScientificValue(candidate)
                error('NMResultsViewerScientificDirectory:InvalidOneOfCandidate', ...
                    'one_of requires a scalar schema value; use contains for collection-valued schema fields.');
            end
            if iscell(wanted) % nm2-allow: one_of request boundary accepts canonical cell or numeric/logical value sets
                tf = false;
                for ii = 1:numel(wanted)
                    if NMResultsViewerScientificDirectory.equalValue(candidate,wanted{ii})
                        tf = true;
                        return;
                    end
                end
            elseif isnumeric(wanted) || islogical(wanted) % nm2-allow: one_of request boundary accepts canonical cell or numeric/logical value sets
                if isnumeric(candidate) || islogical(candidate) % nm2-allow: numeric one_of criterion requires the canonical numeric/logical scalar schema class
                    tf = any(candidate == wanted(:));
                else
                    error('NMResultsViewerScientificDirectory:InvalidOneOfCriterion', ...
                        'Numeric one_of values require a numeric/logical scalar schema value.');
                end
            else
                tf = NMResultsViewerScientificDirectory.equalValue(candidate,wanted);
            end
        end

        function tf = isScalarScientificValue(value)
            tf = (ischar(value) || ((isnumeric(value) || islogical(value)) && isscalar(value))); % nm2-allow: one_of operator validates canonical scalar annotation value classes
        end

        function tf = cellContains(values,wanted)
            tf = false;
            for ii = 1:numel(values)
                if NMResultsViewerScientificDirectory.equalValue(values{ii},wanted)
                    tf = true;
                    return;
                end
            end
        end
    end
end
