classdef NMFusionStateTools
% NMFusionStateTools  Canonical read access to persisted train-template fusion state.

    methods (Static)
        function flag = flagFromNM(NM)
            % flagFromNM  Read inherited NM.TrainParam.FUSION.flag, defaulting absent state to no fusion.
            flag = 0;
            if ~isstruct(NM) || ~isfield(NM,'TrainParam') || ~isstruct(NM.TrainParam) || ...
                    ~isfield(NM.TrainParam,'FUSION') || isempty(NM.TrainParam.FUSION)
                return;
            end
            FUSION = NM.TrainParam.FUSION;
            if ~isstruct(FUSION) || ~isfield(FUSION,'flag') || isempty(FUSION.flag)
                return;
            end
            flag = round(double(FUSION.flag));
            if ~isscalar(flag) || ~isfinite(flag) || ~ismember(flag,0:3)
                error('NMFusionStateTools:invalidFusionFlag', ...
                    'NM.TrainParam.FUSION.flag must be a scalar value in 0:3.');
            end
        end
    end
end
