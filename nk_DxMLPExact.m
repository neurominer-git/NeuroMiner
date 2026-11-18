function out = nk_DxMLPExact(model, Z, reference, task, source, requestedActivation)
%NM2DX_MLP Exact reference-relative dense-network contributions.
%  D1 sklearn MLPERC; D2 TFDEEP PyTorch/TensorFlow sequential;
%  D3 matLearn MLP with constant first hidden neuron.
%  All variants use this SINGLE layerwise secant computational authority.
%  out = nm2dx_mlp(model, heldOutCoordinates, referenceCoordinates, task)
%  task: 'regression' (identity raw output) or 'classification' (binary logit).
%
%  The reference must be supplied in the model's actual input coordinates.
%  The score identity is rawScore = referenceScore + sum(contributions,2).
%  Uses fitted coefs_ and intercepts_, without perturbing or refitting the model.
%  Contributions use layerwise activation secants (DeepLIFT-Rescale style):
%  exact completeness does NOT imply a unique or causal feature attribution.
%
% nm2-allow: secant arithmetic requires finite numeric model coordinates.
assert(isnumeric(Z) && ismatrix(Z) && all(isfinite(Z(:))), ...
    'nm2dx:mlpInput', 'MLP coordinates must be finite numeric matrices.');
% nm2-allow: secant arithmetic requires a row-shaped reference vector.
assert(isnumeric(reference) && isrow(reference), ...
    'nm2dx:mlpReference', 'Reference coordinates must be a numeric row.');
% nm2-allow: secant differences require the same fitted feature axis.
assert(size(Z,2)==numel(reference) && all(isfinite(reference)), ...
    'nm2dx:mlpReference', 'Reference feature axis or finiteness is invalid.');

forceBiasNeuron = false;
switch source
    case 'MLPERC'
        [W,b] = sklearnLayers(model,size(Z,2));
        activation = char(model.activation);
        switch task
            case 'regression'
                assert(strcmp(char(model.out_activation_),'identity'), ...
                    'nm2dx:mlpOutputLink','Regressor must have an identity output layer.');
                domain = 'mlperc_regression_raw_response';
            case 'classification'
                assert(strcmp(char(model.out_activation_),'logistic'), ...
                    'nm2dx:mlpOutputLink','Classifier must have one logistic output neuron.');
                assert(isequal(double(py.array.array('d',model.classes_)),[0,1]), ...
                    'nm2dx:mlpClassOrder','D1 positive class must be sklearn class 1.');
                domain = 'mlperc_binary_raw_logit';
            otherwise
                error('nm2dx:mlpTask','Only regression/binary classification are admitted.');
        end
    case 'TFDEEP_pytorch'
        [W,b] = pytorchLayers(model,size(Z,2));
        activation = requestedActivation;
        domain = ['tfdeep_pytorch_' task '_raw'];
    case 'TFDEEP_tensorflow'
        [W,b] = tensorflowLayers(model,size(Z,2));
        activation = requestedActivation;
        domain = ['tfdeep_tensorflow_' task '_raw'];
    case 'matLRN_MLP'
        [W,b] = matLearnLayers(model,size(Z,2));
        forceBiasNeuron = true;
        if strcmp(task,'classification')
            activation = 'tanh';
            domain = 'matlearn_mlp_binary_raw_logit';
            assert(model.standardize==0, 'nm2dx:mlpStandardized', ...
                'D3 requires model coordinates without internal standardization.');
        else
            activation = model.activFunc;
            domain = 'matlearn_mlp_regression_raw';
        end
    otherwise
        error('nm2dx:mlpSource','Unsupported fitted dense-network source.');
end
assert(ismember(task,{'regression','classification'}), ...
    'nm2dx:mlpTask','Only regression and binary classification are admitted.');
% nm2-allow: Exact activation names come from sklearn, TFDEEP and matLearn writers.
assert(ismember(activation,{'identity','linear','relu','tanh','logistic','sig','sigmoid','elu','softplus'}), ...
    'nm2dx:mlpActivation','Unsupported fitted hidden-layer activation.');
% nm2-allow: The fitted dense network must provide paired hidden and output layer arrays.
assert(numel(W)==numel(b) && numel(W)>=2, ...
    'nm2dx:mlpLayers','Fitted neural layers must contain hidden and output layers.');
assert(size(W{1},1)==size(Z,2), ...
    'nm2dx:mlpFeatureAxis','Fitted first-layer input axis differs from component axis.');
% TFDEEP's default classifier uses two logits and returns class-1 posterior.
% Decompose the raw logit DIFFERENCE rather than either probability.
if startsWith(source,'TFDEEP') && strcmp(task,'classification')
    assert(size(W{end},2)==2, 'nm2dx:mlpTwoLogits', ...
        'Default TFDEEP classification requires exactly two output logits.');
    W{end} = W{end}(:,1)-W{end}(:,2);
    b{end} = b{end}(1)-b{end}(2);
end
assert(size(W{end},2)==1, 'nm2dx:mlpOutput', ...
    'Selected output decision function must be scalar.');

n = size(Z,1);
A = Z;
A0 = repmat(reference,n,1);
slopes = cell(1,numel(W)-1);
for j=1:numel(W)-1
    U = A*W{j}+b{j};
    U0 = A0*W{j}+b{j};
    H = activate(U,activation);
    H0 = activate(U0,activation);
    if forceBiasNeuron
        % matLearn fixes the first hidden neuron to exactly one AFTER
        % applying the activation, overriding all incoming weights.
        H(:,1) = 1;
        H0(:,1) = 1;
    end
    DU = U-U0;
    DH = H-H0;
    S = zeros(size(U));
    changed = DU~=0;
    S(changed) = DH(changed)./DU(changed);
    % For identical preactivations, their contribution to the layer
    % difference vanishes. The derivative is the continuous secant limit.
    S(~changed) = derivative(U0(~changed),activation);
    if forceBiasNeuron
        S(:,1) = 0;
    end
    slopes{j} = S;
    A = H;
    A0 = H0;
end
raw = A*W{end}+b{end};
raw0 = A0*W{end}+b{end};
assert(max(abs(raw0-raw0(1)))<1e-12, 'nm2dx:mlpReference', ...
    'Identical reference input must yield an identical reference score.');

% Back-propagate LOCAL SECANT MULTIPLIERS, not gradient/importance weights.
multiplier = repmat(W{end}(:)',n,1);
for j=numel(slopes):-1:1
    multiplier = (multiplier.*slopes{j})*W{j}';
end
D = (Z-reference).*multiplier;
reconstructed = raw0(1)+sum(D,2);
assert(all(isfinite(D(:))) && all(isfinite(raw)) && isfinite(raw0(1)), ...
    'nm2dx:mlpNonfinite','MLP contributions/reconstructed score are nonfinite.');
out = struct('domain',domain,'activation',activation, ...
    'reference',reference,'referenceScore',raw0(1), ...
    'contributions',D,'rawScore',reconstructed, ...
    'forwardRawScore',raw(:),'secantMultiplier',multiplier, ...
    'maxCompletenessError',max(abs(reconstructed-raw(:))));
end

function H = activate(U,activation)
switch activation
    case 'identity'
        H = U;
    case 'relu'
        H = max(0,U);
    case 'tanh'
        H = tanh(U);
    case {'logistic','sig','sigmoid'}
        H = 1./(1+exp(-U));
    case 'linear'
        H = U;
    case 'elu'
        H = max(0,U)+min(0,exp(U)-1);
    case 'softplus'
        H = max(U,0)+log1p(exp(-abs(U)));
end
end

function S = derivative(U,activation)
switch activation
    case 'identity'
        S = ones(size(U));
    case 'relu'
        S = double(U>0);
    case 'tanh'
        S = 1-tanh(U).^2;
    case {'logistic','sig','sigmoid'}
        P = 1./(1+exp(-U));
        S = P.*(1-P);
    case 'linear'
        S = ones(size(U));
    case 'elu'
        S = ones(size(U));
        S(U<=0) = exp(U(U<=0));
    case 'softplus'
        S = 1./(1+exp(-U));
end
end

function [W,b] = sklearnLayers(model,nInputs)
coefs = cell(model.coefs_);
intercepts = cell(model.intercepts_);
% nm2-allow: Validate externally fitted sklearn layer counts before conversion.
assert(numel(coefs)==numel(intercepts) && numel(coefs)>=2, ...
    'nm2dx:mlpLayers','Expected fitted sklearn coefs_/intercepts_.');
W = cell(size(coefs)); b = cell(size(coefs));
for j=1:numel(coefs)
    b{j} = double(py.array.array('d',py.numpy.ravel(intercepts{j})));
    nj = numel(b{j});
    flat = double(py.array.array('d',py.numpy.ravel(coefs{j})));
    assert(numel(flat)==nInputs*nj,'nm2dx:mlpWeightShape', ...
        'Fitted sklearn weight shape conflicts with previous layer.');
    W{j} = reshape(flat,nj,nInputs)';
    b{j} = reshape(b{j},1,[]);
    nInputs = nj;
end
end

function [W,b] = pytorchLayers(model,nInputs)
% TorchMLP registers one nn.Sequential child containing alternating
% Linear/activation modules. Read it through nn.Module.children() rather
% than MATLAB attribute access to the dynamically registered model.net.
rootChildren = cell(py.list(model.children()));
% nm2-allow: Validate fitted TorchMLP module structure before traversing its layers.
assert(numel(rootChildren)==1,'nm2dx:torchArchitecture', ...
    'Expected the single registered TorchMLP sequential module.');
modules = cell(py.list(rootChildren{1}.children()));
% nm2-allow: TorchMLP writer creates a nonempty alternating Linear/activation sequence.
assert(mod(numel(modules),2)==1 && numel(modules)>=3, ...
    'nm2dx:torchArchitecture','Only default TorchMLP dense sequential models are admitted.');
nLayers = (numel(modules)+1)/2;
W = cell(1,nLayers); b = cell(1,nLayers);
for j=1:nLayers
    layer = modules{2*j-1};
    nj = double(layer.out_features);
    assert(double(layer.in_features)==nInputs, ...
        'nm2dx:torchShape','TorchMLP layer width does not match previous layer.');
    % nn.Linear registers weight and bias as Parameters. PyTorch's
    % parameters() API avoids the same dynamic-attribute bridge problem.
    params = cell(py.list(layer.parameters()));
    % nm2-allow: Each default TorchMLP Linear layer has exactly weight and bias parameters.
    assert(numel(params)==2,'nm2dx:torchParameters', ...
        'Expected weight and bias in fitted TorchMLP Linear layer.');
    flat = double(py.array.array('d',py.numpy.ravel( ...
        params{1}.detach().cpu().numpy())));
    W{j} = reshape(flat,nInputs,nj);
    b{j} = reshape(double(py.array.array('d',py.numpy.ravel( ...
        params{2}.detach().cpu().numpy()))),1,[]);
    nInputs = nj;
end
end

function [W,b] = tensorflowLayers(model,nInputs)
% tf_model_fit constructs Keras Sequential(Dense...,Dense).
layers = cell(py.list(model.layers));
assert(numel(layers)>=2, 'nm2dx:tfArchitecture', ...
    'Only default TFDEEP Sequential Dense models are admitted.');
W = cell(size(layers)); b = cell(size(layers));
for j=1:numel(layers)
    values = cell(py.list(layers{j}.get_weights()));
    assert(numel(values)==2,'nm2dx:tfArchitecture', ...
        'Only Keras Dense kernel/bias layers are admitted.');
    b{j} = reshape(double(py.array.array('d',py.numpy.ravel(values{2}))),1,[]);
    nj = numel(b{j});
    flat = double(py.array.array('d',py.numpy.ravel(values{1})));
    assert(numel(flat)==nInputs*nj,'nm2dx:tfShape', ...
        'Fitted Dense kernel width differs from previous layer.');
    W{j} = reshape(flat,nj,nInputs)';
    nInputs = nj;
end
end

function [W,b] = matLearnLayers(model,nInputs)
% matLearn flattens MATLAB column-major weights; first hidden neuron is
% overwritten with constant one in the actual native prediction function.
hidden = model.nHidden;
% nm2-allow: Validate matLearn fitted architecture at model entry.
assert(isrow(hidden) && numel(hidden)>=1 && all(hidden>=2), ...
    'nm2dx:matLearnArchitecture','Expected explicit hidden neurons including bias units.');
flat = model.w(:);
nLayers = numel(hidden)+1;
W = cell(1,nLayers); b = cell(1,nLayers);
prev = nInputs; offset = 0;
for j=1:numel(hidden)
    width = hidden(j);
    count = prev*width;
    W{j} = reshape(flat(offset+(1:count)),prev,width);
    b{j} = zeros(1,width);
    offset = offset+count;
    prev = width;
end
assert(numel(flat)==offset+prev,'nm2dx:matLearnWeights', ...
    'Flattened matLearn MLP weights do not match hidden architecture.');
W{end} = reshape(flat(offset+(1:prev)),prev,1);
b{end} = 0;
end
