#train_tf_model_example1.py
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
    A predefined 3-layer fully connected classifier/regressor (100x50x10) with
    dropout, custom activation, L2 regularization, early stopping, etc.

    Parameters:
    - Y: np.ndarray of shape (n_samples, n_features)
    - label: np.ndarray of shape (n_samples,) or (n_samples, 1)

    Returns:
    - A trained Keras model
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

    # Change to configure classification/regression.
    is_classification = 1  # Flag indicating the type of task: 1 = classification, 0 = regression
    
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

    # -------------------- Model definition ---------------------------
    
    # Sequential definition of TF models; a simple stack of layers executed in order.
    # For more flexible models (e.g., multiple inputs/outputs or branches), use tf.keras.Model subclassing (see other examples).
    model = models.Sequential() 


    # -------------------- Input Layer --------------------------------
    
    # Input layer
    # Shape: (number of features,)
    # This is the shape of a single input sample (Y.shape[1] = number of features in input data).
    # Do not change this unless you know what you are doing — it must match the size your input data.
    model.add(layers.Input(shape=(Y.shape[1],)))
    
    # -------------------- Hidden Layers ------------------------------
    
    # LAYER 1: Dense layer with 100 units
    # - Units: 100 hidden neurons
    # - Activation: ReLU 
    # - Regularization: L2 penalty on the kernel weights (lambda = 1e-4)
    model.add(layers.Dense(
        100,
        activation='relu',                       
        kernel_regularizer=regularizers.l2(1e-4)
    ))
    # Dropout layer after first hidden layer
    # - Dropout rate: 30% of the units are randomly set to 0 during training
    model.add(layers.Dropout(0.3))
    
    # LAYER 2: Dense layer with 50 units
    # - Same structure as above but with fewer neurons
    model.add(layers.Dense(
        50,
        activation='relu',                       
        kernel_regularizer=regularizers.l2(1e-4)
    ))
    # Dropout again to prevent overfitting
    model.add(layers.Dropout(0.3))
    
    # LAYER 3: Dense layer with 10 units
    # - Same structure as above but with fewer neurons
    model.add(layers.Dense(
        10,
        activation='relu',                       
        kernel_regularizer=regularizers.l2(1e-4)
    ))
    # Dropout once more (can be tuned or removed based on performance)
    model.add(layers.Dropout(0.3))

    # -------------------- Output Layer -------------------------------

    # Final layer that produces the model's prediction
    # - Units: determined by the task (e.g., 2 for binary classification with one-hot encoding, 1 for regression)
    # - Activation:
    #     - 'softmax' for multi-class or binary classification with one-hot encoding
    #     - 'sigmoid' for binary classification with a single output unit (not used here)
    #     - 'linear' for regression, among others
    model.add(layers.Dense(output_units, activation=output_activation))


    # -------------------- Compile model ------------------------------

    # Compile the model by specifying:
    # - Optimizer: Adam with a learning rate of 0.001
    #   (adaptive learning rate optimizer; works well for most tasks)
    # - Loss: defined earlier as `loss`, e.g.:
    #     - 'categorical_crossentropy' for multiclass classification
    #     - 'mean_squared_error' for regression
    # In addition, you can define your own loss function as described here: https://www.tensorflow.org/api_docs/python/tf/keras/Loss
    # - Metrics: list of metric functions (e.g., ['accuracy'] or ['mae']) to evaluate during training/validation

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.001),
        loss=loss,
        metrics=metrics
    )
    
    # -------------------- Early stopping callback --------------------

    # Early stopping to prevent overfitting:
    # - Monitors the validation loss ('val_loss')
    # - Stops training if it doesn't improve for 10 consecutive epochs (`patience=10`)
    # - Restores the model weights from the epoch with the best validation loss
    early_stop = callbacks.EarlyStopping(
        monitor='val_loss',
        patience=10,
        restore_best_weights=True
    )
    
    # -------------------- Train model -------------------------------
    
    # Train the model using the input data:
    # - Y: input features
    # - label_out: target labels
    # - epochs: maximum number of passes over the entire dataset
    # - batch_size: number of samples per gradient update
    # - validation_split: 20% of the data is used for validation
    # - callbacks: includes early stopping to halt training early if needed
    # - verbose=0: suppress output (use 1 or 2 for progress display)
    model.fit(
        Y,
        label_out,
        epochs=100,
        batch_size=32,
        validation_split=0.2,
        callbacks=[early_stop],
        verbose=0
    )
    
    # -------------------- Return trained model ----------------------
    
    # The trained model is returned to NeuroMiner.
    return model