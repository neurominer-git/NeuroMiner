classdef NMPrivacyTools
% NMPrivacyTools
% -------------------------------------------------------------------------
% Privacy/shareability utilities for NeuroMiner application workspaces.
% -------------------------------------------------------------------------

    methods (Static)
        function [NM, report] = scrambleInputFeaturesForSharing(NM, spec)
            % scrambleInputFeaturesForSharing  #ok<INUSD>.
            if nargin < 2 || isempty(spec), spec = struct(); end
            if ~isstruct(NM) || ~isfield(NM,'Y') || ~iscell(NM.Y)
                error('NMPrivacyTools:noTrainingData', 'NM.Y is missing or is not a cell array; input features cannot be scrambled.');
            end
            nMod = numel(NM.Y);
            template = struct('modalityIndex',0, 'nCases',0, 'nFeatures',0, ...
                'wasLinked',false, 'ok',false, 'message','');
            report = struct();
            report.ok = true;
            report.message = 'Input features were replaced by random double matrices.';
            report.nModalities = nMod;
            report.modalities = repmat(template, 1, nMod);
            for i = 1:nMod
                R = template;
                R.modalityIndex = i;
                y = NM.Y{i};
                if ischar(y) || isstring(y)
                    R.wasLinked = true;
                    m = NMPrivacyTools.caseCount(NM);
                    n = NMPrivacyTools.linkedFeatureCount(NM, i);
                else
                    if ~(isnumeric(y) || islogical(y))
                        error('NMPrivacyTools:unsupportedTrainingData', ...
                            'Cannot scramble modality %d because NM.Y{%d} is neither a link nor a numeric/logical matrix.', i, i);
                    end
                    [m,n] = size(y);
                end
                NM.Y{i} = rand(m,n);
                R.nCases = m;
                R.nFeatures = n;
                R.ok = true;
                R.message = 'Input features replaced by random double data.';
                report.modalities(i) = R;
            end
            if ~isfield(NM,'defs') || ~isstruct(NM.defs), NM.defs = struct(); end
            NM.defs.data_scrambled = 1;
        end
    end

    methods (Static, Access=private)
        function n = caseCount(NM)
            n = 0;
            if isstruct(NM) && isfield(NM,'cases') && ~isempty(NM.cases)
                n = numel(NM.cases);
            end
            if n < 1
                error('NMPrivacyTools:missingCaseCount', 'Cannot scramble linked data because NM.cases is empty.');
            end
        end

        function n = linkedFeatureCount(NM, i)
            if ~isfield(NM,'datadescriptor') || ~iscell(NM.datadescriptor) || i > numel(NM.datadescriptor) || ...
                    ~isstruct(NM.datadescriptor{i}) || ~isfield(NM.datadescriptor{i},'input_settings') || ...
                    ~isstruct(NM.datadescriptor{i}.input_settings) || ~isfield(NM.datadescriptor{i}.input_settings,'Ydims') || ...
                    isempty(NM.datadescriptor{i}.input_settings.Ydims)
                error('NMPrivacyTools:missingYdims', ...
                    'Cannot scramble linked modality %d because datadescriptor{%d}.input_settings.Ydims is missing.', i, i);
            end
            dims = double(NM.datadescriptor{i}.input_settings.Ydims);
            dims = dims(isfinite(dims) & dims > 0);
            if isempty(dims)
                error('NMPrivacyTools:badYdims', ...
                    'Cannot scramble linked modality %d because input_settings.Ydims does not contain a positive finite feature count.', i);
            end
            n = prod(dims(:));
        end
    end
end
