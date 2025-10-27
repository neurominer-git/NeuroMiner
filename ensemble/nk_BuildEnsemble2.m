function [opt_F, opt_hE, opt_E, opt_D, opt_Fcat, opt_mPred] = nk_BuildEnsemble2(C, L, EnsStrat, Classes, Groups)
%
% This is the main interface function for building ensembles of predictors
%
% Inputs:
% C         = Ensemble of base learners' decisions
% L         = Labels
% F         = Feature selection mask (base learner selection mask)
% EnsStrat  = Ensemble Construction Strategy
%
%
global RAND

K=numel(Classes);
switch RAND.Decompose % your choice: 'ovo' or 'ovr'
    case 1
        [oECOC, ~] = nk_OneVsOne(Classes, K);
        EnsStrat.ECOC = struct('Mode','ovo','K',K,'oECOC',oECOC);

    case 2
        oECOC = nk_OneVsAll(Classes, K);
        EnsStrat.ECOC = struct('Mode','ovr','K',K,'oECOC',oECOC);
end

% ---- singleton-aware pre-processing (multi-class) ------------------------
% Classes (mC) tells which dichotomizer each column of C belongs to
if exist('Classes','var') && ~isempty(Classes)
    grp = Classes(:)';                 % 1 x M group ids (dichotomizers)
    M   = size(C,2);
    G   = max(grp);                    % #dichotomizers 

    % Find singleton groups and freeze those indices
    frozenIdx = [];
    for g = 1:G
        idxg = find(grp == g);
        if isscalar(idxg)
            frozenIdx = [frozenIdx idxg]; 
        end
    end
    frozenIdx   = unique(frozenIdx, 'stable');
    dynamicIdx  = setdiff(1:M, frozenIdx);

    % If nothing or only one column remains to optimize, short-circuit
    if isempty(dynamicIdx) || numel(dynamicIdx) <= 1
        % Keep everything we have (no optimization possible)
        tkInd      = sort([frozenIdx dynamicIdx]);          % identity or near-identity
        opt_F      = tkInd;
        opt_E      = C(:, tkInd);

        % Compute perf on the kept set
        opt_hE     = nk_EnsPerf(opt_E, L);

        % Compute diversity on the kept set (respect EnsStrat.Metric/DivFunc)
        switch EnsStrat.DivFunc
            case 'nk_Entropy'
                if isfield(EnsStrat,'Metric') && EnsStrat.Metric == 2
                    Tloc = sign(opt_E); Tloc(Tloc==0) = -1;
                else
                    Tloc = opt_E;
                end
                opt_D = nk_Entropy(Tloc, [], [], []);
            case 'nk_Diversity'
                % needs labels
                opt_D = nk_Diversity(opt_E, L, [], []);
            case 'nk_DiversityKappa'
                opt_D = nk_DiversityKappa(opt_E, L, [], []);
            case 'nk_Lobag'
                opt_D = nk_Lobag(opt_E, L);
            case 'nk_RegAmbig'
                opt_D = nk_RegAmbig(opt_E, L);
            otherwise
                % sensible default
                if isfield(EnsStrat,'Metric') && EnsStrat.Metric == 2
                    Tloc = sign(opt_E); Tloc(Tloc==0) = -1;
                else
                    Tloc = opt_E;
                end
                opt_D = nk_Entropy(Tloc, [], [], []);
        end

        % Category vector for selected columns
        if nargout >= 5
            opt_F = Classes(opt_F);
        end
        % Optional predictions container (keep behavior you had; here empty)
        if nargout >= 6
            opt_mPred = [];
        end
        return
    end

    % Otherwise: pass only the dynamic part to the optimizer
    C_dyn = C(:, dynamicIdx);

    % Call optimizer on dynamic subset
    funcname = ['nk_' EnsStrat.OptFunc];
    [opt_hE_dyn, opt_E_dyn, opt_F_dyn, opt_D_dyn] = feval(funcname, C_dyn, L, EnsStrat);

    % Map back to original indices and union with frozen
    opt_F = sort([frozenIdx, dynamicIdx(opt_F_dyn)]);
    opt_E = C(:, opt_F);
    opt_hE = nk_EnsPerf(opt_E, L);
    opt_D  = opt_D_dyn; % or recompute on full opt_E if you prefer consistency

    % Categories for selected columns & optional predictions
    if nargout >= 5, opt_F = Classes(opt_F); end
    if nargout >= 6, opt_mPred = []; end

end



