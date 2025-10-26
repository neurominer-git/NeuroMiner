#include "mex.h"
#include "matrix.h"
#include <cmath>
#include <cstddef>

/*
 * fastcorr: correlation between two real vectors (double or single).
 * Usage: r = fastcorr(x,y)
 */

template <typename GetX, typename GetY>
static double corr_impl(std::size_t n, GetX X, GetY Y)
{
    // Welford-style single pass with numerically stable updates
    double sum_sq_x = 0.0, sum_sq_y = 0.0, sum_coproduct = 0.0;
    double mean_x = X(0);
    double mean_y = Y(0);

    for (std::size_t i = 1; i < n; ++i)
    {
        const double sweep = static_cast<double>(i) / static_cast<double>(i + 1);
        const double dx = X(i) - mean_x;
        const double dy = Y(i) - mean_y;
        sum_sq_x      += dx * dx * sweep;
        sum_sq_y      += dy * dy * sweep;
        sum_coproduct += dx * dy * sweep;
        mean_x        += dx / static_cast<double>(i + 1);
        mean_y        += dy / static_cast<double>(i + 1);
    }

    const double pop_sd_x = std::sqrt(sum_sq_x / static_cast<double>(n));
    const double pop_sd_y = std::sqrt(sum_sq_y / static_cast<double>(n));
    const double cov_xy   = sum_coproduct / static_cast<double>(n);

    if (pop_sd_x == 0.0 || pop_sd_y == 0.0)
        return mxGetNaN(); // undefined when one vector is constant

    return cov_xy / (pop_sd_x * pop_sd_y);
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    // --- Argument checks ---
    if (nrhs != 2)
        mexErrMsgIdAndTxt("fastcorr:arity", "Expected exactly two input vectors.");

    const mxArray *ax = prhs[0];
    const mxArray *ay = prhs[1];

    if (!mxIsNumeric(ax) || mxIsComplex(ax) || !mxIsNumeric(ay) || mxIsComplex(ay))
        mexErrMsgIdAndTxt("fastcorr:real", "Inputs must be real numeric vectors (single or double).");

    // Allow row or column vectors; forbid empty and matrices
    if (!(mxGetM(ax) == 1 || mxGetN(ax) == 1) || !(mxGetM(ay) == 1 || mxGetN(ay) == 1))
        mexErrMsgIdAndTxt("fastcorr:shape", "Inputs must be vectors (row or column).");

    const mwSize nx = mxGetNumberOfElements(ax);
    const mwSize ny = mxGetNumberOfElements(ay);

    if (nx != ny || nx < 2)
        mexErrMsgIdAndTxt("fastcorr:length", "Vectors must have the same length >= 2.");

    // --- Build element accessors for either double or single ---
    mxClassID cx = mxGetClassID(ax);
    mxClassID cy = mxGetClassID(ay);

    if (!((cx == mxDOUBLE_CLASS) || (cx == mxSINGLE_CLASS)))
        mexErrMsgIdAndTxt("fastcorr:type", "x must be single or double.");
    if (!((cy == mxDOUBLE_CLASS) || (cy == mxSINGLE_CLASS)))
        mexErrMsgIdAndTxt("fastcorr:type", "y must be single or double.");

    const double *xD = nullptr; const float *xF = nullptr;
    const double *yD = nullptr; const float *yF = nullptr;

    if (cx == mxDOUBLE_CLASS) xD = mxGetPr(ax);
    else                      xF = static_cast<const float*>(mxGetData(ax));

    if (cy == mxDOUBLE_CLASS) yD = mxGetPr(ay);
    else                      yF = static_cast<const float*>(mxGetData(ay));

    auto X = [&](std::size_t i) -> double {
        return (xD ? xD[i] : static_cast<double>(xF[i]));
    };
    auto Y = [&](std::size_t i) -> double {
        return (yD ? yD[i] : static_cast<double>(yF[i]));
    };

    // --- Compute correlation as double ---
    const double r = corr_impl(static_cast<std::size_t>(nx), X, Y);

    // --- Output (double scalar) ---
    plhs[0] = mxCreateDoubleMatrix(1, 1, mxREAL);
    *mxGetPr(plhs[0]) = r;
}
