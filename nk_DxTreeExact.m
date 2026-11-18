function out = nk_DxTreeExact(learner, model, Z)
%NM2DX_TREE Exact node-path contributions for specified fitted tree learners.
%  This is a standalone numerical experiment, not a NeuroMiner backend API.
%  The baseline is the fitted tree root score (plus the ensemble initial
%  predictor for boosting). Split contributions telescope to each leaf.
%  Contributions are exact but depend on the chosen node-score convention;
%  they are not Shapley values or unconditional causal feature effects.
%
% nm2-allow: validate actual numeric predictor matrix at experimental input.
assert(isnumeric(Z) && ismatrix(Z) && all(isfinite(Z(:))), ...
    'nm2dx:treeCoordinates', 'Tree tests require finite original predictor coordinates.');
N = size(Z,1);
P = size(Z,2);
D = zeros(N,P);
b = 0;
switch learner
    case 'DECTRE'
        % nm2-allow: constrain pilot to the explicit binary score axis.
        assert(numel(model.ClassNames)==2 && isequal(model.ClassNames(:),[0;1]), ...
            'nm2dx:treeClassOrder', 'DECTRE class-2 score must represent class 1.');
        % nm2-allow: constrain experiment to fitted backend one split.
        assert(size(model.Children,1)==3 && model.Children(1,1)>0, ...
            'nm2dx:notStump', 'DECTRE pilot expects the fitted single-split tree.');
        [~,~,leaf] = predict(model,Z);
        assert(all(leaf>=1 & leaf<=size(model.ClassProbability,1)), ...
            'nm2dx:treeLeafIndex', 'DECTRE returned an invalid node index.');
        feature = find(strcmp(model.PredictorNames,model.CutPredictor{1}));
        assert(isscalar(feature), 'nm2dx:treeFeature', 'DECTRE root split predictor not resolved.');
        b = model.ClassProbability(1,2)-0.5;
        D(:,feature) = model.ClassProbability(leaf,2)-model.ClassProbability(1,2);
        domain = 'dectre_class2_centered_probability';
    case {'MATLRN_STUMP_CLASSIFICATION','MATLRN_BROKENSTUMP_CLASSIFICATION'}
        % The native matLearn stumps emit hard {-1,+1} class votes.
        if strcmp(learner,'MATLRN_STUMP_CLASSIFICATION')
            j = model.j;
            % thresholdType=0: left +1, right -1; type=1 reverses.
            b = 1-2*model.thresholdType;
            domain = 'matlearn_binary_stump_vote';
        else
            j = model.selectedFeature;
            b = 1;
            domain = 'matlearn_broken_stump_vote';
        end
        assert(j>=1 && j<=P && j==round(j), ...
            'nm2dx:matLearnStumpFeature','Invalid native matLearn split feature.');
        right = Z(:,j)>=model.threshold;
        D(:,j) = -2*b*double(right);
    case 'MATLRN_REGSTUMP_CONSTANT'
        % Constant-leaf regression; reference is the LEFT fitted mean.
        assert(strcmp(model.modelType,'cns'), 'nm2dx:matLearnRegStumpType', ...
            'This experiment supports constant-leaf regression stumps only.');
        j = model.j;
        assert(j>=1 && j<=P && j==round(j), ...
            'nm2dx:matLearnStumpFeature','Invalid native matLearn split feature.');
        b = model.mean1;
        D(:,j) = double(Z(:,j)>=model.threshold)*(model.mean2-model.mean1);
        domain = 'matlearn_regression_stump_constant_leaves';
    case 'MATLRN_RANDOMFOREST_CLASSIFICATION'
        % matLearn returns SUM of hard tree votes as p.D, not a probability.
        % nm2-allow: assert the ml_binaryclass_randomForest producer's tree count.
        assert(model.nModels>0 && numel(model.trainModels)==model.nModels, ...
            'nm2dx:matLearnForestShape','Unexpected number of trained trees.');
        for t=1:model.nModels
            features = model.features{t};
            treeModel = model.trainModels{t};
            % This stage uses only continuous predictors, as trained here.
            assert(all(treeModel.dataTypes(:)==1), ...
                'nm2dx:matLearnForestDiscrete', ...
                'The matLearn tree vote contract is restricted to continuous splits.');
            [rootValue,parts] = matLearnForestVotePath(treeModel.root,Z,features);
            b = b+rootValue;
            D = D+parts;
        end
        domain = 'matlearn_forest_sum_of_hard_votes';
    case {'RNDFOR_REGRESSION','RNDFOR_CLASSIFICATION', ...
          'GRDBST_REGRESSION','GRDBST_CLASSIFICATION'}
        isForest = startsWith(learner,'RNDFOR');
        isClassification = endsWith(learner,'CLASSIFICATION');
        if isForest
            trees = cell(model.estimators_);
            multiplier = 1/numel(trees);
            if isClassification
                assert(isequal(double(py.array.array('d',model.classes_)),[0,1]), ...
                    'nm2dx:treeClassOrder', 'Forest class-2 probability must represent class 1.');
                domain = 'forest_class2_probability';
            else
                domain = 'forest_regression_response';
            end
        else
            trees = cell(py.list(py.numpy.ravel(model.estimators_)));
            multiplier = double(model.learning_rate);
            if isClassification
                assert(isequal(double(py.array.array('d',model.classes_)),[0,1]), ...
                    'nm2dx:treeClassOrder', 'Boosting raw margin must represent class 1.');
                probabilities = double(model.init_.predict_proba(Z).data);
                % nm2-allow: ensure initial binary class link can be inverted.
                assert(size(probabilities,2)==2 && all(probabilities(:)>0), ...
                    'nm2dx:boostInit', 'Initial classifier has invalid class probabilities.');
                initial = log(probabilities(:,2)./probabilities(:,1));
                domain = 'boosting_binary_raw_logit';
            else
                initial = double(model.init_.predict(Z).data);
                initial = initial(:);
                domain = 'boosting_regression_raw_response';
            end
            % nm2-allow: prove default boosting initializer is constant.
            assert(numel(initial)==N && max(abs(initial-initial(1)))<1e-10, ...
                'nm2dx:nonconstantBoostInit', ...
                'This pilot admits only the backend default constant boosting initializer.');
            b = initial(1);
        end
        assert(~isempty(trees), 'nm2dx:emptyEnsemble', 'No fitted trees.');
        for t=1:numel(trees)
            if isClassification && isForest
                [root,parts] = sklearnTreePath(trees{t},Z,true);
            else
                [root,parts] = sklearnTreePath(trees{t},Z,false);
            end
            b = b + multiplier*root;
            D = D + multiplier*parts;
        end
    otherwise
        error('nm2dx:unsupportedTree', 'No verified tree path contract for %s.',learner);
end
raw = b + sum(D,2);
assert(isfinite(b) && all(isfinite(D(:))) && all(isfinite(raw)), ...
    'nm2dx:nonfiniteTree', 'Tree decomposition returned nonfinite values.');
out = struct('learner',learner,'domain',domain,'contributions',D, ...
    'intercept',b,'rawScore',raw);
end

function [root,D] = sklearnTreePath(estimator,Z,isClassification)
% Convert sklearn fitted tree arrays only. Feature/child indexes are zero-based.
tr = estimator.tree_;
left = double(py.array.array('d',tr.children_left.astype('float64')));
right = double(py.array.array('d',tr.children_right.astype('float64')));
feature = double(py.array.array('d',tr.feature.astype('float64')));
threshold = double(py.array.array('d',tr.threshold));
nodeCount = double(tr.node_count);
assert(numel(left)==nodeCount, 'nm2dx:treeNodeShape', 'Wrong left-child count.');
assert(numel(right)==nodeCount, 'nm2dx:treeNodeShape', 'Wrong right-child count.');
assert(numel(feature)==nodeCount, 'nm2dx:treeNodeShape', 'Wrong split-feature count.');
assert(numel(threshold)==nodeCount, 'nm2dx:treeNodeShape', 'Wrong threshold count.');
value = double(py.array.array('d',py.numpy.ravel(tr.value)));
if isClassification
    assert(numel(value)==2*nodeCount, ...
        'nm2dx:treeClassShape', 'This pilot admits binary sklearn tree probabilities only.');
    classValues = reshape(value,2,[])';
    nodeValue = classValues(:,2)./sum(classValues,2);
else
    assert(numel(value)==nodeCount, ...
        'nm2dx:treeOutputShape', 'This pilot admits single-output regression trees only.');
    nodeValue = value(:);
end
root = nodeValue(1);
N = size(Z,1);
P = size(Z,2);
D = zeros(N,P);
% sklearn tree inference uses float32 predictors, including with double input.
Z = double(single(Z));
for s=1:N
    node = 0;
    while left(node+1)~=-1
        j = feature(node+1)+1;
        assert(j>=1 && j<=P,'nm2dx:treeFeature','Invalid split feature index.');
        if Z(s,j)<=threshold(node+1)
            child = left(node+1);
        else
            child = right(node+1);
        end
        assert(child>=0 && child<nodeCount, ...
            'nm2dx:treeChild', 'Invalid child node index.');
        D(s,j) = D(s,j) + nodeValue(child+1)-nodeValue(node+1);
        node = child;
    end
end
end


function [rootValue,D] = matLearnForestVotePath(root,Z,featureMap)
% Node reference = majority training label, leaf = fitted hard class vote.
% Internal nodes retain their training labels, and the native predictor
% traverses continuous splits with < left / >= right. Node differences
% telescope exactly to the native leaf vote for each held-out subject.
N = size(Z,1);
P = size(Z,2);
D = zeros(N,P);
rootValue = mode(root.y);
for s=1:N
    node = root;
    parentValue = rootValue;
    while ~node.isLeaf
        assert(node.type==1, 'nm2dx:matLearnTreeType', ...
            'This stage supports continuous matLearn tree splits only.');
        j = featureMap(node.splitDimension);
        assert(j>=1 && j<=P && j==round(j), ...
            'nm2dx:matLearnTreeFeature','Invalid local-to-original feature mapping.');
        if Z(s,j)<node.threshold
            child = node.children{1};
        else
            child = node.children{2};
        end
        if child.isLeaf
            childValue = child.val;
        else
            childValue = mode(child.y);
        end
        D(s,j) = D(s,j) + childValue-parentValue;
        node = child;
        parentValue = childValue;
    end
end
end
