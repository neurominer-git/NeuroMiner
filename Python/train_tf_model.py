# train_tf_model.py
# (c) Sergio Mena Ortega, 2025.

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, optimizers, callbacks, regularizers


# ------------------------------
# Differentiable Metrics as Losses
# ------------------------------

@tf.function(reduce_retracing=True)
def confusion_soft_counts(y_true_pos, y_pred_pos):

    TP = tf.reduce_sum(y_pred_pos * y_true_pos)
    FP = tf.reduce_sum(y_pred_pos * (1 - y_true_pos))
    TN = tf.reduce_sum((1 - y_pred_pos) * (1 - y_true_pos))
    FN = tf.reduce_sum((1 - y_pred_pos) * y_true_pos)

    return TP, FP, TN, FN

# BAC loss function.
@tf.function(reduce_retracing=True)
def balanced_accuracy_loss(y_true, y_pred, smooth=1e-6):

    # assume binary classification
    y_true = tf.cast(y_true[:,0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:,0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)

    # denominators
    pos_denom = TP + FN
    neg_denom = TN + FP

    # sensitivity (only valid if pos_denom > 0)
    sens = tf.where(
        pos_denom > 0,
        TP / (pos_denom + smooth),
        tf.constant(0.0, dtype=tf.float32)
    )

    # specificity (only valid if neg_denom > 0)
    spec = tf.where(
        neg_denom > 0,
        TN / (neg_denom + smooth),
        tf.constant(0.0, dtype=tf.float32)
    )

    # count how many valid terms we had
    valid_terms = tf.cast(pos_denom > 0, tf.float32) + tf.cast(neg_denom > 0, tf.float32)

    # average only over valid terms
    bal_acc = (sens + spec) / valid_terms

    return 1.0 - bal_acc

@tf.function(reduce_retracing=True)
def enhanced_balanced_accuracy_loss(y_true, y_pred, smooth=1e-6):
    """
    Differentiable Enhanced Balanced Accuracy (BAC2) loss.
    - Uses product of sensitivity and specificity if both are defined.
    - Falls back to the valid metric if one denominator is zero.
    """
    # assume binary classification
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)

    # soft counts
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)

    # denominators
    pos_denom = TP + FN
    neg_denom = TN + FP

    # sensitivity (only valid if pos_denom > 0, otherwise set to 1 to have no effect on EBA)
    sens = tf.where(
        pos_denom > 0,
        TP / (pos_denom + smooth),
        tf.constant(1, dtype=tf.float32)
    )

    # specificity (only valid if neg_denom > 0, otherwise set to 1 to have no effect on EBA)
    spec = tf.where(
        neg_denom > 0,
        TN / (neg_denom + smooth),
        tf.constant(1, dtype=tf.float32)
    )

    EBA = sens*spec 

    return 1.0 - EBA

@tf.function(reduce_retracing=True)
def true_positive_rate_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    TPR = TP / (TP + FN + smooth)
    return 1 - TPR


@tf.function(reduce_retracing=True)
def false_positive_rate_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    FPR = FP / (FP + TN + smooth)
    return FPR  # minimize directly


@tf.function(reduce_retracing=True)
def positive_predictive_value_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    PPV = TP / (TP + FP + smooth)
    return 1 - PPV


@tf.function(reduce_retracing=True)
def matthews_corrcoef_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    numerator = TP * TN - FP * FN
    denominator = tf.sqrt((TP + FP + smooth) * (TP + FN + smooth) *
                          (TN + FP + smooth) * (TN + FN + smooth))
    MCC = numerator / denominator
    return 1 - MCC


@tf.function(reduce_retracing=True)
def geometric_mean_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    PPV = TP / (TP + FP + smooth)
    TPR = TP / (TP + FN + smooth)
    GM = tf.sqrt(PPV * TPR)
    return 1 - GM


@tf.function(reduce_retracing=True)
def fscore_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    precision = TP / (TP + FP + smooth)
    recall = TP / (TP + FN + smooth)
    fscore = 2 * precision * recall / (precision + recall + smooth)
    return 1 - fscore


@tf.function(reduce_retracing=True)
def prognostic_summary_index_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    PPV = TP / (TP + FP + smooth)
    NPV = TN / (TN + FN + smooth)
    PSI = PPV + NPV - 1
    return 1 - PSI


@tf.function(reduce_retracing=True)
def number_needed_to_predict_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    PPV = TP / (TP + FP + smooth)
    NNP = 1 / (PPV + smooth)
    return NNP


@tf.function(reduce_retracing=True)
def positive_likelihood_ratio_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    sensitivity = TP / (TP + FN + smooth)
    specificity = TN / (TN + FP + smooth)
    PLR = sensitivity / (1 - specificity + smooth)
    return 1 - PLR


@tf.function(reduce_retracing=True)
def negative_likelihood_ratio_loss(y_true, y_pred, smooth=1e-6):
    y_true = tf.cast(y_true[:, 0], tf.float32)
    y_pred = tf.clip_by_value(y_pred[:, 0], smooth, 1 - smooth)
    TP, FP, TN, FN = confusion_soft_counts(y_true, y_pred)
    sensitivity = TP / (TP + FN + smooth)
    specificity = TN / (TN + FP + smooth)
    NLR = (1 - sensitivity) / (specificity + smooth)
    return NLR  # minimize directly


# ------------------------------
# Model Definition
# ------------------------------

def tf_model_fit(Y, label, layers_sizes, activation="relu",
                 optimizer_name="adam", l2reg=0.0001, lr=0.001,
                 batch_size=32, epochs=100, seed=42,
                 class_weighting=False, use_early_stop=False, patience=5,
                 validation=True, validation_fraction=0.1,
                 loss='categorical_crossentropy', NM_perf_criterion='ACCURACY', task='classification'):

    # ----------------- Seed setting -----------------
    tf.random.set_seed(seed)
    np.random.seed(seed)

    # ----------------- Input conversion -------------
    Y = np.array(Y).astype(np.float32)
    label = np.array(label).astype(np.float32).reshape(-1)

    # ----------------- Model definition -------------
    model = models.Sequential()
    model.add(layers.Input(shape=(Y.shape[1],)))

    for size in layers_sizes:
        model.add(layers.Dense(int(size), activation=activation,
                               kernel_regularizer=regularizers.l2(l2reg)))

    # ----------------- Output layer and label prep -------------
    if task == 'classification':
        # Convert label from {1, -1} → {0, 1} -> hot encoding [1,0], [0,1]
        labels_bin = ((1 - (label + 1) / 2)).astype(np.int32)
        label_out = tf.keras.utils.to_categorical(labels_bin, num_classes=2)
        label_out = np.array(label_out, dtype=np.float32)

        # Add output layer
        model.add(layers.Dense(2, activation='softmax'))

    elif task == 'regression':
        label_out = label.reshape(-1, 1).astype(np.float32)

        # Add output layer
        model.add(layers.Dense(1, activation='linear'))

    # ----------------- Optimizer ---------------------
    if optimizer_name == 'adam':
        opt = optimizers.Adam(learning_rate=lr)
    elif optimizer_name == 'sgd':
        opt = optimizers.SGD(learning_rate=lr)

    # ----------------- Performance Crit. -------------

    #Adapt loss to NM performance criterion.
    if loss == 'performance_criterion':
        if NM_perf_criterion == 'ACCURACY':
            loss = "categorical_crossentropy"
        elif NM_perf_criterion == 'TPR':
            loss = true_positive_rate_loss
        elif NM_perf_criterion == 'FPR':
            loss = false_positive_rate_loss
        elif NM_perf_criterion == 'PPV':
            loss = positive_predictive_value_loss
        elif NM_perf_criterion == 'MCC':
            loss = matthews_corrcoef_loss
        elif NM_perf_criterion == 'AUC':
            loss = auc_loss
        elif NM_perf_criterion == 'GMEAN':
            loss = geometric_mean_loss
        elif NM_perf_criterion == 'BAC':
            loss = balanced_accuracy_loss
        elif NM_perf_criterion == 'BAC2':
            loss = enhanced_balanced_accuracy_loss
        elif NM_perf_criterion == 'FSCORE':
            loss = fscore_loss
        elif NM_perf_criterion == 'PSI':
            loss = prognostic_summary_index_loss
        elif NM_perf_criterion == 'NNP':
            loss = number_needed_to_predict_loss
        elif NM_perf_criterion == 'PLR':
            loss = positive_likelihood_ratio_loss
        elif NM_perf_criterion == 'NLR':
            loss = negative_likelihood_ratio_loss



    # ----------------- Compile model -----------------
    model.compile(optimizer=opt, loss=loss)

    # ----------------- Class weights -----------------
    if class_weighting and task == 'classification':
        class_counts = np.bincount(labels_bin)
        total = len(labels_bin)
        class_weights = {i: total / (2 * count) for i, count in enumerate(class_counts)}
    else:
        class_weights = None

    # ----------------- Callbacks ---------------------
    cb_list = []
    if use_early_stop:
        monitor_metric = 'val_loss' if validation else 'loss'
        cb_list.append(callbacks.EarlyStopping(monitor=monitor_metric,
                                               patience=patience,
                                               restore_best_weights=True))

    # ----------------- Train model -------------------
    model.fit(Y, label_out,
              epochs=epochs,
              batch_size=batch_size,
              verbose=0,
              validation_split=validation_fraction if validation else 0.0,
              callbacks=cb_list,
              class_weight=class_weights)

    # ----------------- Return ------------------------
    return model
