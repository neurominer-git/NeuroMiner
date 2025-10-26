function [opt_F, opt_hE, opt_E, opt_D, opt_Fcat, opt_mPred] = nk_BuildEnsemble(C, L, EnsStrat, Classes, Groups)
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
global MULTI
if MULTI.flag && MULTI.train
    funcname = ['nk_Multi' EnsStrat.OptFunc];
    [opt_hE, opt_E, opt_F, opt_Fcat, opt_D, opt_mPred] = ...
        feval(funcname, C, L, EnsStrat, Classes, Groups);
else
    funcname = ['nk_' EnsStrat.OptFunc];
    [opt_hE, opt_E, opt_F, opt_D] = feval(funcname, C, L, EnsStrat);
    opt_Fcat = []; opt_mPred = [];
end

switch lower(EnsStrat.DiversitySource)
    case 'lobag'
        if isfield(EnsStrat,'OptFunc') && strcmpi(EnsStrat.OptFunc,'EDMin')
            % opt_D is ED  (lower=better)
            ED = max(-1, min(2, opt_D));     % clamp ED to theory bounds
            opt_D = (2 - ED) / 3;            % ED [-1,2] -> Dnorm [1,0] (higher=better)
        else
            % opt_D is likely -ED (higher=better) as used in CVMax-style
            negED = max(-2, min(1, opt_D));  % since -ED ∈ [-2,1]
            opt_D = (negED + 2) / 3;         % -ED [-2,1] -> Dnorm [0,1]
        end
    case 'entropy'
        opt_D = -opt_D;

end


