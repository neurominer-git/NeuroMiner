classdef NMModelSpec < handle
% Minimal lightweight learner registry facade. Enables wf.model.setLearner(...)
% in the public API smoke test without changing current NM model code.

    properties
        learner char = ''
        config struct = struct()
    end

    methods
        function setLearner(obj, learner, varargin)
            % setLearner  Store the learner choice in the workflow model-spec object.
            %
            % Records the requested learner id and name/value config in the lightweight workflow facade. This does not materialize NM.TrainParam; later train-template APIs perform backend conversion.
            obj.learner = char(learner);
            obj.config = NMConfigTools.nameValueToStruct(struct(), varargin{:});
        end
    end
end
