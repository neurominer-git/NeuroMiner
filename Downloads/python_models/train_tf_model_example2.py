# train_tf_model_example2.py
# (c) Sergio Mena Ortega, 2025.
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks, regularizers

# - Models are defined within functions. 
# Make sure the function has the name tf_model(), while the file name is different across different models. 

#MODEL FUNCTION
#DO NOT CHANGE tf_model() FUNCTION NAME.
def tf_model(Y, label):
    """
    A predefined 4-layer fully connected classifier/regressor (128x64x32x16) using
    TensorFlow's Functional API. Includes dropout, ELU activation, L2 regularization,
    batch normalization, early stopping, and different training hyperparameters.

    Parameters:
    - Y: np.ndarray of shape (n_samples, n_features)
      Input features for training.

    - label: np.ndarray of shape (n_samples,) or (n_samples, 1)
      Target labels or values for training.

    Returns:
    - A trained Keras model instance ready for predictions or further evaluation.
    """

    # -------------------- Input formatting ---------------------------
    
    # Not tuneable unless you know what you are doing
    Y = np.array(Y).astype(np.float32)
    label = np.array(label).astype(np.float32).reshape(-1)

    # -------------------- Seed for reproducibility --------------------

    random_seed = 45                      # Numerical number used to initialize stochastic parameters. 
    tf.random.set_seed(random_seed)
    np.random.seed(random_seed)


    # -------------------- Label handling -----------------------------

    # Configure task type: 1 for classification, 0 for regression
    is_classification = 1

    if is_classification: # Classification

        labels_bin = ((1 - (label + 1) / 2)).astype(np.int32)  # Binary encoded labels for classification
        label_out = tf.keras.utils.to_categorical(labels_bin, num_classes=2)  # Model-ready label array

        output_activation = 'softmax'     # Activation function used in the final output layer
        output_units = 2                  # Number of output neurons in the final layer
        loss = 'categorical_crossentropy' # Loss function used to optimize model performance during training
        metrics = ['accuracy']            # List of metrics to track during training/evaluation

    else: # Regression
        label_out = label.reshape(-1, 1).astype(np.float32)  # Model-ready label array for regression
    
        output_activation = 'linear'     # Activation function used in the final output layer
        output_units = 1                 # Number of output neurons in the final layer
        loss = 'mean_squared_error'      # Loss function used to optimize model performance during training
        metrics = ['mae']                # List of metrics to track during training/evaluation


    # -------------------- Functional Model Definition --------------------

    # Input layer
    # Shape matches the number of features in the input data
    inputs = layers.Input(shape=(Y.shape[1],), name="input_layer")

    # Layer 1: Dense with 128 neurons + L2 regularization
    # Batch normalization normalizes layer outputs to stabilize and accelerate training
    # ELU activation adds non-linearity and allows small negative values (better than ReLU sometimes)
    # Dropout randomly zeroes 25% of activations to reduce overfitting
    x = layers.Dense(
        128,
        kernel_regularizer=regularizers.l2(5e-5),
        name="dense_128"
    )(inputs)
    x = layers.BatchNormalization(name="batch_norm_1")(x)
    x = layers.Activation('elu', name="activation_elu_1")(x)
    x = layers.Dropout(0.25, name="dropout_1")(x)

    # Layer 2: Dense with 64 neurons + BatchNorm + ELU + Dropout
    x = layers.Dense(
        64,
        kernel_regularizer=regularizers.l2(5e-5),
        name="dense_64"
    )(x)
    x = layers.BatchNormalization(name="batch_norm_2")(x)
    x = layers.Activation('elu', name="activation_elu_2")(x)
    x = layers.Dropout(0.25, name="dropout_2")(x)

    # Layer 3: Dense with 32 neurons + BatchNorm + ELU + Dropout
    x = layers.Dense(
        32,
        kernel_regularizer=regularizers.l2(5e-5),
        name="dense_32"
    )(x)
    x = layers.BatchNormalization(name="batch_norm_3")(x)
    x = layers.Activation('elu', name="activation_elu_3")(x)
    x = layers.Dropout(0.25, name="dropout_3")(x)

    # Layer 4: Dense with 16 neurons + BatchNorm + ELU + Dropout
    x = layers.Dense(
        16,
        kernel_regularizer=regularizers.l2(5e-5),
        name="dense_16"
    )(x)
    x = layers.BatchNormalization(name="batch_norm_4")(x)
    x = layers.Activation('elu', name="activation_elu_4")(x)
    x = layers.Dropout(0.25, name="dropout_4")(x)

    # Output layer: units and activation depend on classification/regression
    outputs = layers.Dense(output_units, activation=output_activation, name="output_layer")(x)

    # Define the functional model from input tensor to output tensor
    model = models.Model(inputs=inputs, outputs=outputs, name="example_model_fn_v2")


    # -------------------- Compile model ------------------------------

    # Compile model specifying optimizer, loss, and metrics
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.0005),  # Adaptive optimizer with smaller learning rate
        loss=loss,
        metrics=metrics
    )


    # -------------------- Early stopping callback --------------------

    # Early stopping halts training when validation loss stops improving
    early_stop = callbacks.EarlyStopping(
        monitor='val_loss',         # Metric to monitor
        patience=15,                # Number of epochs to wait before stopping
        restore_best_weights=True  # Roll back to weights from best epoch
    )


    # -------------------- Train model -------------------------------

    # Fit the model on the input data
    # - validation_split uses 15% of data for validation during training
    # - batch_size sets number of samples per gradient update
    # - epochs is maximum training iterations over the full dataset
    # - callbacks include early stopping to prevent overfitting
    model.fit(
        Y,
        label_out,
        epochs=150,
        batch_size=64,
        validation_split=0.15,
        callbacks=[early_stop],
        verbose=0 
    )


    # -------------------- Return trained model ----------------------

    # The trained model is returned to NeuroMiner.
    return model