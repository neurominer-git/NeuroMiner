# train_pytorch_model.py
# (c) Sergio Mena Ortega, 2026.

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

# ------------------------------
# Differentiable Metrics as Losses (PyTorch version)
# ------------------------------

def confusion_soft_counts_torch(y_true_pos, y_pred_pos):
    TP = torch.sum(y_pred_pos * y_true_pos)
    FP = torch.sum(y_pred_pos * (1 - y_true_pos))
    TN = torch.sum((1 - y_pred_pos) * (1 - y_true_pos))
    FN = torch.sum((1 - y_pred_pos) * y_true_pos)
    return TP, FP, TN, FN

def _binary_from_one_hot(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1.0 - smooth)
    return y_pred_pos, y_true_pos

def balanced_accuracy_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    pos_denom = TP + FN
    neg_denom = TN + FP
    sens = torch.where(pos_denom > 0, TP / (pos_denom + smooth), torch.tensor(0.0))
    spec = torch.where(neg_denom > 0, TN / (neg_denom + smooth), torch.tensor(0.0))
    valid_terms = (pos_denom > 0).float() + (neg_denom > 0).float()
    bal_acc = (sens + spec) / valid_terms
    return 1.0 - bal_acc

def enhanced_balanced_accuracy_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    pos_denom = TP + FN
    neg_denom = TN + FP
    sens = torch.where(pos_denom > 0, TP / (pos_denom + smooth), torch.tensor(1.0))
    spec = torch.where(neg_denom > 0, TN / (neg_denom + smooth), torch.tensor(1.0))
    EBA = sens * spec
    return 1.0 - EBA

def true_positive_rate_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    TPR = TP / (TP + FN + smooth)
    return 1.0 - TPR

def false_positive_rate_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    FPR = FP / (FP + TN + smooth)
    return FPR

def positive_predictive_value_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    PPV = TP / (TP + FP + smooth)
    return 1.0 - PPV

def matthews_corrcoef_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    numerator = TP * TN - FP * FN
    denominator = torch.sqrt((TP + FP + smooth) * (TP + FN + smooth) *
                             (TN + FP + smooth) * (TN + FN + smooth))
    MCC = numerator / denominator
    return 1.0 - MCC

def geometric_mean_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    PPV = TP / (TP + FP + smooth)
    TPR = TP / (TP + FN + smooth)
    return 1.0 - torch.sqrt(PPV * TPR)

def fscore_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    precision = TP / (TP + FP + smooth)
    recall = TP / (TP + FN + smooth)
    return 1.0 - 2 * precision * recall / (precision + recall + smooth)

def prognostic_summary_index_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    PPV = TP / (TP + FP + smooth)
    NPV = TN / (TN + FN + smooth)
    return 1.0 - (PPV + NPV - 1)

def number_needed_to_predict_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    PPV = TP / (TP + FP + smooth)
    return 1.0 / (PPV + smooth)

def positive_likelihood_ratio_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    sensitivity = TP / (TP + FN + smooth)
    specificity = TN / (TN + FP + smooth)
    return 1.0 - sensitivity / (1 - specificity + smooth)

def negative_likelihood_ratio_loss_torch(y_pred, y_true, smooth=1e-6):
    y_pred_pos, y_true_pos = _binary_from_one_hot(y_pred, y_true, smooth)
    TP, FP, TN, FN = confusion_soft_counts_torch(y_true_pos, y_pred_pos)
    sensitivity = TP / (TP + FN + smooth)
    specificity = TN / (TN + FP + smooth)
    return (1 - sensitivity) / (specificity + smooth)


def categorical_hinge_loss_torch(y_pred, y_true):
    y_true = y_true.float()
    correct = torch.sum(y_true * y_pred, dim=1)
    incorrect = torch.max((1 - y_true) * y_pred - (y_true * 1e6), dim=1)[0]
    return torch.mean(torch.clamp(incorrect - correct + 1.0, min=0.0))

def auc_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true_pos = y_true[:, 0].float()
    y_pred_pos = torch.clamp(y_pred[:, 0], smooth, 1.0 - smooth)
    pos_scores = y_pred_pos[y_true_pos > 0.5]
    neg_scores = y_pred_pos[y_true_pos <= 0.5]
    if pos_scores.numel() == 0 or neg_scores.numel() == 0:
        return torch.tensor(0.0, device=y_pred.device, requires_grad=True)
    diff = pos_scores.unsqueeze(1) - neg_scores.unsqueeze(0)
    return torch.mean(torch.log1p(torch.exp(-diff)))

# ------------------------------
# Regression and other losses
# ------------------------------
def nrmsd_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true = y_true.float()
    y_pred = y_pred.float()
    mse = torch.mean((y_pred - y_true) ** 2)
    rmse = torch.sqrt(mse + smooth)
    y_range = torch.max(y_true) - torch.min(y_true)
    return 100.0 * rmse / (y_range + smooth)

def scc_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true = y_true.float()
    y_pred = y_pred.float()
    y_true_centered = y_true - torch.mean(y_true)
    y_pred_centered = y_pred - torch.mean(y_pred)
    cov = torch.mean(y_true_centered * y_pred_centered)
    var_true = torch.mean(y_true_centered ** 2)
    var_pred = torch.mean(y_pred_centered ** 2)
    corr = cov / (torch.sqrt(var_true * var_pred) + smooth)
    return 1.0 - corr**2

def cc_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true = y_true.float()
    y_pred = y_pred.float()
    y_true_centered = y_true - torch.mean(y_true)
    y_pred_centered = y_pred - torch.mean(y_pred)
    cov = torch.mean(y_true_centered * y_pred_centered)
    var_true = torch.mean(y_true_centered ** 2)
    var_pred = torch.mean(y_pred_centered ** 2)
    corr = cov / (torch.sqrt(var_true * var_pred) + smooth)
    return 1.0 - corr

def mse_inverse_density_loss_torch(y_pred, y_true, smooth=1e-6):
    y_true = y_true.float()
    y_pred = y_pred.float()
    n = y_true.numel()
    mean_y = torch.mean(y_true)
    std_y = torch.sqrt(torch.mean((y_true - mean_y) ** 2))
    std_y = torch.where(std_y > 0, std_y, torch.tensor(1.0))
    h = 1.06 * std_y * n**(-0.2)
    
    y_col = y_true.view(-1, 1)
    diff_mat = y_col - y_col.t()
    gauss_kernel = torch.exp(-0.5 * (diff_mat / (h + smooth)) ** 2) / (torch.sqrt(2.0 * torch.pi) * (h + smooth))
    p = torch.mean(gauss_kernel, dim=1)
    p = torch.clamp(p, min=smooth)
    w = 1.0 / p
    w = w / torch.sum(w)
    
    diff = y_pred - y_true
    return torch.sum(w * diff**2)



def mean_absolute_percentage_error_torch(y_pred, y_true, eps=1e-8):
    y_true = y_true.float()
    y_pred = y_pred.float()
    return torch.mean(torch.abs((y_true - y_pred) / (y_true + eps))) * 100.0

def log_cosh_loss_torch(y_pred, y_true):
    diff = y_pred - y_true
    return torch.mean(torch.log(torch.cosh(diff + 1e-12)))

def cosine_similarity_loss_torch(y_pred, y_true, dim=1):
    return 1.0 - torch.mean(torch.nn.functional.cosine_similarity(y_pred, y_true, dim=dim))

# ------------------------------
# Helper: activation mapping
# ------------------------------
def get_activation(name):
    if name == "linear":
        return nn.Identity()
    elif name == "sigmoid":
        return nn.Sigmoid()
    elif name == "tanh":
        return nn.Tanh()
    elif name == "relu":
        return nn.ReLU()
    elif name == "elu":
        return nn.ELU()
    elif name == "softplus":
        return nn.Softplus()
    elif name == "swish":
        return nn.ModuleDict({"forward": lambda x: x * torch.sigmoid(x)})["forward"]

# ------------------------------
# Model definition
# ------------------------------
class TorchMLP(nn.Module):
    def __init__(self, input_dim, layers_sizes, activation, l2reg, task="classification"):
        super().__init__()
        layers = []
        self.task = task
        prev_dim = input_dim
        for size in layers_sizes:
            layers.append(nn.Linear(prev_dim, int(size)))
            layers.append(get_activation(activation))
            prev_dim = int(size)
        if task == "classification":
            layers.append(nn.Linear(prev_dim, 2))  # output dim = num_classes
        else:
            layers.append(nn.Linear(prev_dim, 1))
        self.net = nn.Sequential(*layers)

    def forward(self, x):
        return self.net(x)

    def predict(self, x):
        self.eval()
        if isinstance(x, np.ndarray):
            x = torch.tensor(x, dtype=torch.float32)
        with torch.no_grad():
            y = self.forward(x)
            if self.task == 'classification':
                y = torch.softmax(y, dim=1)
            y = y.numpy()
        return y

# ------------------------------
# Main training function
# ------------------------------
def torch_model_fit(
    Y, label, layers_sizes, activation="relu", optimizer_name="adam",
    l2reg=0.0001, lr=0.001, batch_size=32, epochs=100, seed=42,
    class_weighting=False, use_early_stop=False, patience=5,
    validation=True, validation_fraction=0.1, loss="categorical_crossentropy",
    NM_perf_criterion="ACCURACY", task="classification"
):
    torch.manual_seed(seed)
    np.random.seed(seed)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"[Pytorch framework] training on device: {device}")
    # Input
    Y = torch.tensor(np.asarray(Y), dtype=torch.float32)
    label = np.asarray(label).reshape(-1)
    num_classes = len(np.unique(label))

    # Labels: always 2D one-hot
    if task == "classification":
        labels_bin = ((1 - (label + 1)/2)).astype(np.int64)
        y = torch.tensor(labels_bin, dtype=torch.long)
        y = torch.nn.functional.one_hot(y, num_classes=num_classes).float()
    else:
        y = torch.tensor(label, dtype=torch.float32).view(-1,1)

    # Class weighting
    if class_weighting and task=="classification":
        class_counts = np.bincount(labels_bin)
        weights = len(labels_bin)/(num_classes*class_counts)
        class_weights = torch.tensor(weights, dtype=torch.float32).to(device)
    else:
        class_weights = None

    # Loss selection
    if loss=="categorical_crossentropy":
        criterion = nn.CrossEntropyLoss(weight=class_weights)
    elif loss=="kl_divergence":
        criterion = nn.KLDivLoss(reduction="batchmean")
    elif loss=="categorical_hinge":
        criterion = categorical_hinge_loss_torch
    elif loss=="mean_squared_error":
        criterion = nn.MSELoss()
    elif loss=="mean_absolute_error":
        criterion = nn.L1Loss()
    elif loss=="mean_absolute_percentage_error":
        criterion = mean_absolute_percentage_error_torch
    elif loss=="huber":
        criterion = nn.HuberLoss()
    elif loss=="log_cosh":
        criterion = log_cosh_loss_torch
    elif loss=="cosine_similarity":
        criterion = cosine_similarity_loss_torch
    elif loss=="performance_criterion":
        perf_map = {
            "ACCURACY": nn.CrossEntropyLoss(weight=class_weights), 
            "TPR": true_positive_rate_loss_torch,
            "FPR": false_positive_rate_loss_torch,
            "PPV": positive_predictive_value_loss_torch,
            "MCC": matthews_corrcoef_loss_torch,
            "BAC": balanced_accuracy_loss_torch,
            "BAC2": enhanced_balanced_accuracy_loss_torch,
            "GMEAN": geometric_mean_loss_torch,
            "FSCORE": fscore_loss_torch,
            "PSI": prognostic_summary_index_loss_torch,
            "NNP": number_needed_to_predict_loss_torch,
            "PLR": positive_likelihood_ratio_loss_torch,
            "NLR": negative_likelihood_ratio_loss_torch,
            "MSE": nn.MSELoss(),
            "NRMSD": nrmsd_loss_torch,
            "SCC": scc_loss_torch,
            "CC": cc_loss_torch,
            "MAERR": nn.L1Loss(),
            "MSEINVDENS": mse_inverse_density_loss_torch
        }
        criterion = perf_map[NM_perf_criterion]

    # Dataset split
    n = len(Y)
    if validation:
        n_val = int(n*validation_fraction)
        idx = np.random.permutation(n)
        val_idx, train_idx = idx[:n_val], idx[n_val:]
        Y_train, Y_val = Y[train_idx], Y[val_idx]
        y_train, y_val = y[train_idx], y[val_idx]
    else:
        Y_train, y_train = Y, y
        Y_val, y_val = None, None

    Y_train, y_train = Y_train.to(device), y_train.to(device)
    if validation: Y_val, y_val = Y_val.to(device), y_val.to(device)

    train_loader = torch.utils.data.DataLoader(torch.utils.data.TensorDataset(Y_train, y_train), batch_size=batch_size, shuffle=True)

    # Model
    model = TorchMLP(input_dim=Y.shape[1], layers_sizes=layers_sizes, activation=activation, l2reg=l2reg, task=task).to(device)

    # Optimizer
    opt_map = {"adam": optim.Adam, "sgd": optim.SGD, "adagrad": optim.Adagrad}
    optimizer = opt_map[optimizer_name.lower()](model.parameters(), lr=lr, weight_decay=l2reg)

    # Training loop
    best_val_loss = np.inf
    patience_counter = 0
    for epoch in range(epochs):
        model.train()
        epoch_loss = 0.0
        for xb, yb in train_loader:
            optimizer.zero_grad()
            out = model(xb)

            if loss=="kl_divergence":
                out = torch.nn.functional.log_softmax(out, dim=1)

            # For CrossEntropyLoss only, use 1D indices
            if isinstance(criterion, nn.CrossEntropyLoss):
                yb_loss = torch.argmax(yb, dim=1)
            else:
                yb_loss = yb

            loss_val = criterion(out, yb_loss)
            loss_val.backward()
            optimizer.step()
            epoch_loss += loss_val.item()

        # Validation
        if validation:
            model.eval()
            with torch.no_grad():
                out_val = model(Y_val)
                if isinstance(criterion, nn.CrossEntropyLoss):
                    y_val_loss = torch.argmax(y_val, dim=1)
                else:
                    y_val_loss = y_val
                val_loss = criterion(out_val, y_val_loss).item()

            if use_early_stop:
                if val_loss < best_val_loss:
                    best_val_loss = val_loss
                    best_state = {k: v.cpu().clone() for k,v in model.state_dict().items()}
                    patience_counter = 0
                else:
                    patience_counter += 1
                    if patience_counter >= patience:
                        model.load_state_dict(best_state)
                        break

    model.to("cpu")
    return model
