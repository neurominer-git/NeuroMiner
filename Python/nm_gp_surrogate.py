# nm_gp_surrogate.py
import numpy as np
from sklearn.gaussian_process import GaussianProcessRegressor
from sklearn.gaussian_process.kernels import RBF, Matern


def _rbf_kernel(n_dims, ard: bool):
    if ard:
        length_scale = np.ones(n_dims)
    else:
        length_scale = 1.0
    # Wide-ish bounds so optimizer has room, similar to MATLAB
    return RBF(length_scale=length_scale,
               length_scale_bounds=(1e-2, 1e5))


def _matern_kernel(nu, n_dims, ard: bool):
    if ard:
        length_scale = np.ones(n_dims)
    else:
        length_scale = 1.0
    return Matern(length_scale=length_scale,
                  length_scale_bounds=(1e-2, 1e5),
                  nu=nu)


def _make_kernel(kernel_name: str, n_dims: int):
    k = kernel_name.lower()

    if k == "ardsquaredexponential":
        base = _rbf_kernel(n_dims=n_dims, ard=True)

    elif k == "squaredexponential":
        base = _rbf_kernel(n_dims=n_dims, ard=False)

    elif k == "ardmatern32":
        base = _matern_kernel(nu=1.5, n_dims=n_dims, ard=True)

    elif k == "matern32":
        base = _matern_kernel(nu=1.5, n_dims=n_dims, ard=False)

    elif k == "ardmatern52":
        base = _matern_kernel(nu=2.5, n_dims=n_dims, ard=True)

    elif k == "matern52":
        base = _matern_kernel(nu=2.5, n_dims=n_dims, ard=False)

    elif k == "ardexponential":
        base = _matern_kernel(nu=0.5, n_dims=n_dims, ard=True)

    elif k == "exponential":
        base = _matern_kernel(nu=0.5, n_dims=n_dims, ard=False)

    else:
        # reasonable fallback: ARD RBF
        base = _rbf_kernel(n_dims=n_dims, ard=True)

    return base


def gp_predict(X_train, y_train, X_test, kernel_name="ardsquaredexponential"):
    X_train = np.asarray(X_train, dtype=float)
    y_train = np.asarray(y_train, dtype=float).ravel()
    X_test  = np.asarray(X_test, dtype=float)

    n_dims = X_train.shape[1]
    kernel = _make_kernel(kernel_name, n_dims)

    gp = GaussianProcessRegressor(
        kernel=kernel,
        alpha=1e-6,         # tiny nugget (observation noise)
        normalize_y=False, 
        n_restarts_optimizer=5,
        random_state=0,
    )
    gp.fit(X_train, y_train)
    mu, sigma = gp.predict(X_test, return_std=True)
    return mu, sigma
