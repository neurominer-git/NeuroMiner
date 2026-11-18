function paramfl = nk_PrepPreprocParams(PREPROC, paramfl, analysis, modalind, ll, curlabel)
% nk_PrepPreprocParams - Extract trained preprocessing values for one modality.
%
% The trained model's ModalityVec and NumPreMLParams define the authoritative
% parameter columns. nk_ReturnParamChain must reproduce the same modality-local
% count and source order; disagreement is an explicit model/PREPROC contract
% error. Modalities without preprocessing parameters do not borrow a column from
% another modality.
global VERBOSE MULTI

paramfl.PREPROC = PREPROC;        
if analysis.Model.NumPreMLParams > 0
    
    % Retrieve optimised parameters from GDdims
    paramfl.PXfull = nk_ReturnParamChain(PREPROC, 1);
    % Search for parameter column of given modality
    indm = analysis.Model.ModalityVec{1} == modalind;
    if any(indm) && (isempty(paramfl.PXfull) || ...
            numel(paramfl.PXfull.Params) ~= sum(indm))
        error('nk_PrepPreprocParams:PreprocModelContractMismatch', ...
            ['The trained model contains %g preprocessing parameter columns for ' ...
             'modality #%g, but the active PREPROC defines %g.'], ...
            sum(indm), modalind, local_param_count(paramfl.PXfull));
    end
    % No parameter column found
    NumMLParam = analysis.Model.NumParamDims - analysis.Model.NumPreMLParams ;
    
    for u=1:numel(analysis.bestP)

        % Set pointer to modality-specific preprocessing ignoring the ML
        % parameters
        if ~any(indm)
            paramfl.PXopt{u} = [];
            paramfl.PXunique{u} = [];
            continue
        end
        pnt_vec = NumMLParam(u) + find(indm);
        
        % Check whether multi-class optimization is needed
        if MULTI.flag && paramfl.multiflag
            fld = 'multi_bestP';
        else
            fld = 'bestP';
        end    
        % Retrieve parameters
        if ~iscell(analysis.bestP{1})
            paramfl.PXopt{u} = analysis.(fld){u}(ll, pnt_vec, curlabel);
        else
            paramfl.PXopt{u} =[];
            for uu = 1:numel(ll)
                paramfl.PXopt{u} = [paramfl.PXopt{u} ; analysis.(fld){u}{ll(uu),curlabel}(:, pnt_vec) ];
            end
        end
        % Retrieve unique combinations
        paramfl.PXunique{u} = unique(paramfl.PXopt{u},'rows','stable');
    end
else
    configuredPX = nk_ReturnParamChain(PREPROC, 1);
    if ~isempty(configuredPX)
        error('nk_PrepPreprocParams:MissingTrainedPreprocParameters', ...
            ['The active PREPROC contains optimizable preprocessing parameters, ' ...
             'but the trained model records NumPreMLParams = 0. Retrain the model ' ...
             'with the step-aware preprocessing parameter contract.']);
    end
    if VERBOSE
        fprintf('\n'); fprintf('No preprocessing parameter optimization included in trained model');
    end
end

function n = local_param_count(PX)
n = 0;
if ~isempty(PX) && isfield(PX,'Params')
    n = numel(PX.Params);
end
