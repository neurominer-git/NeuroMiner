function [optparam, optind, optfound, optmodel] = nk_SimAnneal(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr)

global VERBOSE TRAINFUNC RFE

% #####################################################################
% This code does:
% 1) Feature selection using SA
% 2) This is a simple code working on 1 single shot only. That is, this
% code work with a set of trainin, cross-validation and test set. 
% 3) If you want to make N-fold cross validation, you can certainly do so
% by covering the code by a for-loop.
% #####################################################################

r = rfe_algo_settings(Y, label, Ynew, labelnew, Ps, FullFeat, FullParam, ActStr);

n = size(r.Y,2); % the number of data instances (m) and the features (n)

% #####################################################################
% ==== Make the order of features to be introduced to the SA =====
% #####################################################################
% The normal order
featureID_sorted = 1:n;
% featureID_order = featureID_sorted(randperm(n)); % Randomly shuffle the voxel order
featureID_order = featureID_sorted ; % the MI-descend order

%% 
% =================================================================
%                       SA framework
% =================================================================
% ===== SA operating parameters ==== @#$% user-defined
% @#$% user-defined objective function
objFunction = @ObjectiveFunction1; 

% @#$% user-defined solution mapping function
%nextSolution = @NextSolution3; 

% @#$% SA parameters
c               = RFE.Wrapper.SA.c;
T               = RFE.Wrapper.SA.T;
T_initial       = T;
T_stop          = RFE.Wrapper.SA.T_stop; % the stopping temperature 
alpha           = RFE.Wrapper.SA.alpha;
itt_max         = RFE.Wrapper.SA.itt_max;
Rep_T_max       = RFE.Wrapper.SA.Rep_T_max; % max number of Rep in one temperature T
Rep_accept_max  = RFE.Wrapper.SA.Rep_accept_max; % if solution accepted this many, then update T
kc              = RFE.Wrapper.SA.kc; % k-constant. The smaller kc --> less solution accepted @#$% user-defined

% ====================================================
% initialize or evaluate the solution for user-defined function  % @#$% user-defined
x_curr = false(1,n); 
x_curr(1:min(5,n)) = true;
%F_curr          = -1e+9; % F_curr = objFunction(x_curr);
F_curr = objFunction(n, c, labelnew, r.Ynew(:,x_curr), label, r.Y(:,x_curr), Ps, r.Criterion.ylb_short);
x_best          = x_curr;
F_best          = F_curr;
storage_new     = {};
% ====================================================

% ====================================================
% initial value for SA
Rep_T           = 0;
Rep_accept      = 0;
itt             = 1;
converges       = 0;
%is_best_updated = 0; % toggle flag set to 1 when the best solution is updated

if VERBOSE
    fprintf('\n----------------------')
    fprintf('\nSIMULATED ANNEALING')
    fprintf('\n----------------------')
    fprintf('\nOptimization data mode: %s', ActStr)
    fprintf('\nParameter evaluation: %s', r.evaldir)
    fprintf('\nStopping temperature: %g', T_stop)
    fprintf('\nMax number of iterations: %g', itt_max)
    fprintf('\nMax number of repetitions in one temperature: %g', Rep_T_max)
    fprintf('\nAlpha: %g', alpha)
    fprintf('\nKc (smaller kc => less solutions accepted): %g', kc)
end

% Start SA optimization
while converges == 0 && itt <= itt_max
    
    % pick a new solution x_new
    x_new = NextSolution4(x_curr, n, featureID_order, T, T_initial);
    
    if ~any(x_new), x_new = x_curr; end
    % @#$% user-defined objective function
    % F_new = objFunction(x_new): Calculate F_new from x_new: 
    F_new = objFunction(n, c, labelnew, r.Ynew(:,x_new), label, r.Y(:,x_new), Ps, r.Criterion.ylb_short);

    % Anything you want to keep is here % @#$% user-defined
    storage_new.itt = itt;
    storage_new.sol = x_new;
    storage_new.value = F_new;
    storage_new.alpha = alpha;
    storage_new.T = T;
        
    % The code here is exactly the same as the one above except not
    % showing any plot which is much faster.
    % Check: update solution
    if feval(r.evaldir, F_new, F_curr)
        % back up before update
        %F_prev = F_curr; % backup the previous
        %x_prev = x_curr; % backup the previous
        % update
        F_curr = F_new; % accept the solution
        x_curr = x_new; % accept the solution
        Rep_accept = Rep_accept + 1;
        % check the best solution
        if feval(r.evaldir, F_new, F_best)
            if VERBOSE, fprintf('\nIteration %5.0f/%g: T = %1.3f\t==> NEW optimum: # Features: %5.0f (%3.0f%%) ==> %s = %g', ...
                    itt, itt_max, T, sum(x_new), sum(x_new)*100/n, ActStr, F_new); 
            end
            F_best = F_new;
            x_best = x_new;
            %storage_best = storage_new;
            %is_best_updated = true;
        end
    elseif exp((F_new-F_curr)/(kc*T)) > rand(1)
        % back up before update
        %F_prev = F_curr; % backup the previous
        %x_prev = x_curr; % backup the previous
        % update
        F_curr = F_new; % accept the solution
        x_curr = x_new; % accept the solution
        Rep_accept = Rep_accept + 1;
    end

    % update the counters
    Rep_T = Rep_T + 1;
    itt = itt + 1;
    
    % Check: update temperature
    if Rep_T >= Rep_T_max || Rep_accept >= Rep_accept_max
        T = alpha*T;
        Rep_T = 0;
        Rep_accept = 0;
        %F_curr = F_best;
        %x_curr = x_best;
    end
    
    % stop criteria by temperature
    if T < T_stop
        converges = 1;
    end
    
    % %     % Check for convergence???
    % %     % -- Well, in some objective function, it's very hard to define the
    % %     % stopping criteria because the solution is very jumy even at the end,
    % %     % therefore, I don't check convergence here. Anyway, you can do so
    % %     % here.
    % %     % =========================================================
    % %     if F_curr - F_prev > something
    % %         converges = 1;
    % %     end
    
end

% =========== END of SA =====================
if VERBOSE
    if converges
        fprintf('\nSA algorithm converged')
    else
        fprintf('\n%g iterations reached. Algorithm terminated.',itt_max);
    end
end
%% CHECK IF OPTIMIZED FEATURE SPACE PERFORMS BETTER THAN ORIGINAL SPACE
if ~feval(r.evaldir, F_best, r.FullParam)
    optparam = r.FullParam; optind = r.FullInd; optfound = 0;
    if VERBOSE
        fprintf('\n----------------------')
        fprintf('\nSA OPTIMIZATION RESULT')
        fprintf('\n----------------------')
        fprintf('\nOriginal feature set performance (%s): %g', ActStr, r.FullParam)
        fprintf('\nSA-optimized performance (%s): %g', ActStr, F_best)
        fprintf('\nFeatures selected by SA: %d/%d (%3.1f%%)', sum(x_best), n, sum(x_best)*100/n)
        fprintf('\n==> SA did NOT improve performance. Using original feature set.')
        fprintf('\n')
    end
else
    optind = r.FullInd(x_best); optparam = F_best; optfound = 1;
    if VERBOSE
        fprintf('\n----------------------')
        fprintf('\nSA OPTIMIZATION RESULT')
        fprintf('\n----------------------')
        fprintf('\nOriginal feature set performance (%s): %g', ActStr, r.FullParam)
        fprintf('\nSA-optimized performance (%s): %g', ActStr, F_best)
        fprintf('\nFeatures selected by SA: %d/%d (%3.1f%%)', sum(x_best), n, sum(x_best)*100/n)
        
        % Calculate improvement
        if feval(r.evaldir, 0, r.FullParam)  % Check if higher is better
            improvement = ((F_best - r.FullParam) / abs(r.FullParam)) * 100;
        else  % Lower is better
            improvement = ((r.FullParam - F_best) / abs(r.FullParam)) * 100;
        end
        fprintf('\nImprovement: %+.2f%%', improvement)
        fprintf('\n==> SA successfully improved performance!')
        fprintf('\n')
    end
end
%SIG = nk_CheckMatrixEmptyNonVarNonFinite(Y(:,optind));
[~,optmodel] = TRAINFUNC(Y(:,optind), label, 1, Ps); 

end