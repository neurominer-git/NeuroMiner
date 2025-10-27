# train_tf_model_example3.py
# (c) Sergio Mena Ortega, 2025.
import os
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, callbacks

# - Models are defined within functions. 
# Make sure the function has the name tf_model(), while the file name is different across different models. 

#LOADING OF PRETRAINED MODEL. 
#Do this outside of the tf_model() function as a global variable to avoid repeated loading overhead during training.
#The pretrained file (.keras or .h5) should be in the same folder as the .py file with the tf_model() definition.

# Get absolute path to current .py file's directory
this_dir = os.path.dirname(os.path.abspath(__file__))

# Full path to model file
model_path = os.path.join(this_dir, "my_model.keras")

#Load model.
base_model = tf.keras.models.load_model(model_path)

#MODEL FUNCTION
#DO NOT CHANGE  FUNCTION NAME tf_model().
def tf_model(Y, label):
    """
    Example that loads a pre-trained model from local disk (e.g. .h5 file),
    adds a custom input projection layer, freezes all pretrained layers,
    and appends a new trainable output layer for either classification or regression.

    Parameters:
    - Y: np.ndarray, shape (n_samples, n_features)
        Input data with a dimensionality different from the pretrained model.
    
    - label: np.ndarray, shape (n_samples,) or (n_samples, 1)
        Target labels for supervised learning.
    
    Returns:
    - model: tf.keras.Model
        Trained model including bridging layers and a frozen pretrained block.
    """

    # -------------------- Input formatting ---------------------------

    # Convert inputs to proper float32 arrays (not tuneable unless expert)
    Y = np.array(Y).astype(np.float32)
    label = np.array(label).astype(np.float32).reshape(-1)

    # -------------------- Seed for reproducibility --------------------

    random_seed = 45
    tf.random.set_seed(random_seed)
    np.random.seed(random_seed)

    # -------------------- Label handling ------------------------------

    is_classification = 1  # 1 = classification, 0 = regression

    if is_classification:
        labels_bin = ((1 - (label + 1) / 2)).astype(np.int32)
        label_out = tf.keras.utils.to_categorical(labels_bin, num_classes=2)

        output_units = 2
        output_activation = 'softmax'
        loss = 'categorical_crossentropy'
        metrics = ['accuracy']
    else:
        label_out = label.reshape(-1, 1).astype(np.float32)

        output_units = 1
        output_activation = 'linear'
        loss = 'mean_squared_error'
        metrics = ['mae']

    # -------------------- Configure pretrained base model ------------------

    # Configure a frozen pretrained model (e.g., trained elsewhere on a related task)
    # This model must have been saved using model.save('pretrained_model.h5')
    # and accept input shape (latent_dim,)
    base_model.trainable = False  # Freeze all pretrained layers

    pretrained_input_dim = base_model.input_shape[-1]  

    # -------------------- Build extended model ------------------------

    # Define input layer for raw data
    inputs = layers.Input(shape=(Y.shape[1],), name='input_layer')

    # Project input to match pretrained model's expected input
    x = layers.Dense(
        pretrained_input_dim,
        activation='relu',
        name='first_layer_bridge'
    )(inputs)

    # Feed into frozen pretrained model
    x = base_model(x, training=False)  # Prevents updating batchnorm/dropout during training

    # Add a custom trainable output layer
    outputs = layers.Dense(
        output_units,
        activation=output_activation,
        name='output_head'
    )(x)

    # Assemble the model
    model = models.Model(inputs=inputs, outputs=outputs, name='transfer_frozen_with_bridge')

    # -------------------- Compile model -------------------------------

    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=0.0005),
        loss=loss,
        metrics=metrics
    )

    # -------------------- Early stopping ------------------------------

    early_stop = callbacks.EarlyStopping(
        monitor='val_loss',
        patience=10,
        restore_best_weights=True
    )

    # -------------------- Train model ---------------------------------

    model.fit(
        Y,
        label_out,
        epochs=60,
        batch_size=32,
        validation_split=0.2,
        callbacks=[early_stop],
        verbose=0
    )

    # -------------------- Return model --------------------------------

    return model