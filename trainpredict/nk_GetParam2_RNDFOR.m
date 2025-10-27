% ==========================================================================
% FORMAT [param, model] = nk_GetParam_MEXELM(Y, label, SlackParam, ~, ...
%                                           ModelOnly)
% ==========================================================================
% Train LIBLINEAR models and evaluate their performance using Y & label, 
% SlackParam,
% if ModelOnly = 1, return only model
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% (c) Nikolaos Koutsouleris, 08/2012

function [param, model] = nk_GetParam2_RNDFOR(Y, label, ModelOnly, Param)
global EVALFUNC MODEFL 

param = [];
switch MODEFL
    case 'classification'
        if iscell(Y)  % MCL-based learning not implemented yet
        else % Univariate case

            feat = double(Y);
            lab = int64(label);
            n_est = int64(Param(1));
            n_maxfeat = double(Param(2));
            crit = int64(Param(4));
            maxd = int64(Param(3));
            minss = double(Param(5));
            minsl = double(Param(6));
            minwfl = double(Param(7));
            maxln = int64(Param(8));
            minid = int64(Param(9));
            boot = logical(Param(10)); % bool
            oobs = logical(Param(11)); % bool; only available if boot == true
            classw = int64(Param(14));
            ccpa = int64(Param(12));
            maxs = int64(Param(13));

            switch crit
                case 1
                    crit = 'gini';
                case 2
                    crit = 'log_loss';
                case 3
                    crit = 'entropy';
            end


            switch n_maxfeat
                case -1
                    n_maxfeat = 'sqrt';
                case -2
                    n_maxfeat = 'log2';
                case 0
                    n_maxfeat = string(missing);
            end

            if maxd == 0
                maxd = string(missing);
            end

            if minsl >= 1.0
                minsl = int64(minsl);
            end

            if minss > 1.0
                minss = int64(minss);
            end

            if maxln == 0
                maxln = string(missing);
            end

            switch classw
                case 0
                    classw = string(missing);
                case 1
                    classw = 'balanced';
                case 2
                    classw = 'balanced_subsample';
            end


            if maxs == 0
                maxs = string(missing);
            end

            if boot
                randomstate = 42;
                boot = true; 
            else
                randomstate = string(missing); %check if this is accepted as Python None
                boot = false; 
            end
            
            model = py.sklearn.ensemble.RandomForestClassifier(n_estimators = n_est,...
                max_features = n_maxfeat,...
                criterion = crit,...
                max_depth = maxd,...
                min_samples_split = minss,...
                min_samples_leaf = minsl,...
                min_weight_fraction_leaf = minwfl,...
                max_leaf_nodes = maxln,...
                min_impurity_decrease = minid,...
                bootstrap = boot,...
                oob_score = oobs,...
                class_weight = classw,...
                ccp_alpha = ccpa,...
                max_samples = maxs,...
                random_state = int8(randomstate));
        end
    case 'regression'
        feat = Y;
        lab = label;
        n_est = int64(Param(1));
        n_maxfeat = double(Param(2));
        crit = int64(Param(4));
        maxd = int64(Param(3));
        minss = double(Param(5));
        minsl = double(Param(6));
        minwfl = double(Param(7));
        maxln = int64(Param(8));
        minid = int64(Param(9));
        boot = logical(Param(10));
        oobs = logical(Param(11));
        ccpa = int64(Param(12));
        maxs = int64(Param(13));

        %criterion
        switch crit
            case 1
                crit = 'squared_error';
            case 2
                crit = 'absolute_error';
            case 3
                crit = 'poisson';
        end


        % max_depth
        if maxd == 0
            maxd = string(missing);
        end

        % max_features
        switch n_maxfeat

            case -1
                n_maxfeat = 'sqrt';
            case -2
                n_maxfeat = 'log2';
            case 0
                n_maxfeat = string(missing);
        end

        % min_samples_leaf
        if minsl >= 1.0
            minsl = int64(minsl);
        end

        % min_samples_split
        if minss > 1.0
            minss = int64(minss);
        end

        % max_leaf_nodes
        if maxln == 0
            maxln = string(missing);
        end

        % max_samples
        if maxs == 0
            maxs = string(missing);
        end

        % set random state
        if boot
            randomstate = 42;
        else
            randomstate = string(missing); %check if this is accepted as Python None
        end

        model = py.sklearn.ensemble.RandomForestRegressor(n_estimators = n_est, ...
            max_features = n_maxfeat, ...
            criterion = crit, ...
            max_depth = maxd, ...
            min_samples_split = minss, ...
            min_samples_leaf = minsl, ...
            min_weight_fraction_leaf = minwfl, ...
            max_leaf_nodes = maxln, ...
            min_impurity_decrease = minid, ...
            bootstrap = boot, ...
            oob_score = oobs, ...
            ccp_alpha = ccpa, ...
            max_samples = maxs, ...
            random_state = int8(randomstate)); % others: verbose, random_state, warm_start, n_jobs

end

if size(feat,1) == 1 && size(feat,2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(1)), double(lab'));
elseif size(feat, 2) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(-1), int64(1)), double(lab'));
elseif size(feat, 1) == 1
    model = model.fit(py.numpy.array(feat).reshape(int64(1), int64(-1)), double(lab'));
else 
    model = model.fit(double(feat), double(lab'));
end

% is this part still necessary?
if ~ModelOnly
    [param.target] = nk_GetTestPerf_RNDFOR([], Y, label, md);
    param.dec_values = param.target;
    param.val = EVALFUNC(label, param.dec_values);
end
