classdef NMResultsViewerScientificCapability
% NMResultsViewerScientificCapability
% -------------------------------------------------------------------------
% Dynamic Results Viewer scientific-capability registry.
%
% The registry contains only handles to existing authoritative Results Viewer
% functions. A registered function is interrogated with the reserved call:
%
%   fn('scientificCapability')
%   fn('scientificCapability', context)   % current-context filtering
%
% The returned contract contains semantic needs/provides only. Normal function
% execution is unchanged. The registry therefore says who can be asked, while
% each function owns what it needs and provides.
%
% needs is a cell array of slots; each slot is a cell array of acceptable
% artefact ids. All slots are required; ids inside one slot are alternatives.
%
% Contract: NM-SCIENTIFIC-CAPABILITY-V2
% -------------------------------------------------------------------------

    methods (Static)
        function version = contractVersion()
            version = 'NM-SCIENTIFIC-CAPABILITY-V2';
        end

        function functions = registeredFunctions()
            functions = { ...
                @NMResultsViewerTools.getClassificationPayload; ...
                @NMResultsViewerTools.getRegressionPayload; ...
                @NMResultsViewerTools.getMultiClassPayload; ...
                @NMResultsViewerTools.getSubjectFeatureQC; ...
                @NMResultsViewerTools.getClassificationActionPayload; ...
                @NMResultsViewerTools.getModelOptimizationPayload; ...
                @NMResultsViewerTools.getModelFeatureInspectionPayload; ...
                @NMResultsViewerMLITools.getPayload; ...
                @NMResultsViewerTools.getModelFeatureRelationPayload; ...
                @NMResultsViewerImagingTools.getImagingWorkspace; ...
                @NMResultsViewerSurfaceTools.buildWorkspace; ...
                @NMResultsViewerConnectivityAdapter.build};
        end

        function contracts = interrogate(functions)
            if nargin<1, functions=NMResultsViewerScientificCapability.registeredFunctions(); end % nm2-allow: public capability registry API preserves documented no-argument interrogation
            if isempty(functions)
                contracts=repmat(NMResultsViewerScientificCapability.contract('',{},[]),0,1); return;
            end
            if ~iscell(functions)||any(~cellfun(@(f)isa(f,'function_handle'),functions(:))) % nm2-allow: public registry injection boundary validates caller-supplied function handles
                error('NMResultsViewerScientificCapability:InvalidRegistry', ...
                    'Scientific capability registry must contain function handles only.');
            end
            firstContract=functions{1}('scientificCapability');
            contracts=repmat(firstContract,numel(functions),1);
            for ii=2:numel(functions), contracts(ii)=functions{ii}('scientificCapability'); end
            for ii=1:numel(contracts)
                contracts(ii).functionHandle=functions{ii};
                NMResultsViewerScientificCapability.validate(contracts(ii));
            end
            if numel(unique({contracts.id}))~=numel(contracts)
                error('NMResultsViewerScientificCapability:DuplicateMethodId', ...
                    'Scientific capability registry contains duplicate function ids.');
            end
        end

        function contract = available(contract,context)
            % available  Re-interrogate one validated function for materialized context.
            current=contract.functionHandle('scientificCapability',context);
            current.functionHandle=contract.functionHandle;
            NMResultsViewerScientificCapability.validate(current);
            if ~strcmp(current.id,contract.id)
                error('NMResultsViewerScientificCapability:ChangedMethodId', ...
                    'Conditional capability interrogation changed the function id.');
            end
            declared={contract.provides.id}; actual={current.provides.id};
            if any(~ismember(actual,declared))
                error('NMResultsViewerScientificCapability:UndeclaredProvide', ...
                    'Conditional interrogation returned an undeclared provide.');
            end
            contract=current;
        end

        function tf = isQuery(value)
            tf=ischar(value)&&strcmp(value,'scientificCapability'); % nm2-allow: overloaded provider dispatch boundary distinguishes the reserved query token from ordinary NM input
        end

        function c = contract(id,needs,provides)
            c=struct('contractVersion',NMResultsViewerScientificCapability.contractVersion(), ...
                'id',id,'needs',{needs},'provides',provides,'functionHandle',[]);
        end

        function p = provide(id,kind,family,type)
            p=struct('id',id,'kind',kind,'family',family,'type',type);
        end

        function out = subset(provides,ids)
            if isempty(provides), out=provides; return; end
            out=provides(ismember({provides.id},ids));
        end
    end

    methods (Static, Access=private)
        function validate(c)
            expected={'contractVersion';'id';'needs';'provides';'functionHandle'};
            % nm2-allow: capability provider return boundary validates the fixed contract record
            if ~isstruct(c)||~isscalar(c)||~isequal(sort(fieldnames(c)),sort(expected))|| ...
                    ~strcmp(c.contractVersion,NMResultsViewerScientificCapability.contractVersion())|| ...
                    isempty(regexp(c.id,'^[a-z][a-z0-9_]*$','once'))
                error('NMResultsViewerScientificCapability:InvalidContract', ...
                    'Scientific capability function returned an invalid contract.');
            end
            if ~iscell(c.needs), error('NMResultsViewerScientificCapability:InvalidNeeds','needs must be a cell array.'); end % nm2-allow: capability provider return boundary validates semantic need slots
            for ii=1:numel(c.needs)
                % nm2-allow: capability provider return boundary validates each semantic need slot
                if ~iscell(c.needs{ii})||isempty(c.needs{ii})|| ...
                        any(cellfun(@(x)isempty(regexp(x,'^[a-z][a-z0-9_]*$','once')),c.needs{ii}))
                    error('NMResultsViewerScientificCapability:InvalidNeeds', ...
                        'Each need slot must contain one or more semantic artefact ids.');
                end
            end
            % nm2-allow: capability provider return boundary validates the fixed provides record family
            if ~isstruct(c.provides)||(~isempty(c.provides)&& ...
                    ~isequal(sort(fieldnames(c.provides)),sort({'id';'kind';'family';'type'})))
                error('NMResultsViewerScientificCapability:InvalidProvides','Invalid provides contract.');
            end
            for ii=1:numel(c.provides)
                if isempty(regexp(c.provides(ii).id,'^[a-z][a-z0-9_]*$','once'))|| ...
                        ~ismember(c.provides(ii).kind,{'scientific_artefact','visualization'})
                    error('NMResultsViewerScientificCapability:InvalidProvide','Invalid scientific provide.');
                end
                if strcmp(c.provides(ii).kind,'scientific_artefact')&& ...
                        (isempty(c.provides(ii).family)||isempty(c.provides(ii).type))
                    error('NMResultsViewerScientificCapability:InvalidProvide', ...
                        'Scientific artefacts require payload family and type annotation.');
                end
            end
        end
    end
end
