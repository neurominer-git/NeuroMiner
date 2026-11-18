classdef NMWorkflow < handle
% NMWorkflow
% Small public API facade for the smoke-gun architecture slice.
% Later this can own model/learner registries as well.

    properties
        registry
        preproc
        model
    end

    methods
        function obj = NMWorkflow(registry)
            % NMWorkflow  Construct a small public workflow facade around preprocessing and model specs.
            %
            % Initializes the module registry, preprocessing sequence and model spec object used by scripted smoke tests. It does not mutate an NM workspace until callers export or materialize legacy structures.
            if nargin < 1 || isempty(registry), registry = NMModuleRegistry.default(); end
            obj.registry = registry;
            obj.preproc = NMPreprocSequence(registry);
            obj.model = NMModelSpec();
        end

        function setLearner(obj, learner, varargin)
            % setLearner  Forward learner selection to the workflow model spec.
            %
            % Stores the learner and optional configuration inside obj.model while keeping preprocessing configuration separate. This is a facade convenience method, not a TrainParam writer.
            obj.model.setLearner(learner, varargin{:});
        end

        function PREPROC = toLegacyPreproc(obj, varargin)
            % toLegacyPreproc  Export the workflow preprocessing sequence to a legacy PREPROC struct.
            %
            % Delegates to NMPreprocSequence.toLegacy with the supplied context so scripted workflows can materialize preprocessing steps without touching the broader NM training template.
            PREPROC = obj.preproc.toLegacy(varargin{:});
        end
    end
end
