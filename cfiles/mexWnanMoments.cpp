#include "mex.h"
#include <cmath>
#ifdef _OPENMP
#include <omp.h>
#endif

// [m, s] = mexWnanMoments(X, w)
void mexFunction(int nlhs, mxArray *plhs[],
                 int nrhs, const mxArray *prhs[])
{
    // Check inputs
    if(nrhs!=2) mexErrMsgTxt("Usage: [m,s] = mexWnanMoments(X,w)");
    if(nlhs>2)  mexErrMsgTxt("Too many outputs");

    double *X = mxGetPr(prhs[0]);
    double *w = mxGetPr(prhs[1]);
    mwSize n = mxGetM(prhs[0]);
    mwSize p = mxGetN(prhs[0]);

    // Prepare outputs
    plhs[0] = mxCreateDoubleMatrix(1, p, mxREAL);
    plhs[1] = mxCreateDoubleMatrix(1, p, mxREAL);
    double *m = mxGetPr(plhs[0]);
    double *s = mxGetPr(plhs[1]);

    // Main loop: one column per thread
    #pragma omp parallel for
    for(mwSize j=0; j<p; ++j) {
        double sumw=0, sum1=0, sum2=0;
        double *col = X + j*n;      // pointer to X(:,j)

        for(mwSize i=0; i<n; ++i) {
            double xv = col[i];
            if(!mxIsNaN(xv)) {
                double wi = w[i];
                sumw += wi;
                sum1 += wi * xv;
                sum2 += wi * xv * xv;
            }
        }

        if(sumw>0) {
            double mu  = sum1 / sumw;
            double var = sum2/sumw - mu*mu;
            m[j] = mu;
            s[j] = var>0 ? std::sqrt(var) : 0;
        } else {
            m[j] = mxGetNaN();
            s[j] = mxGetNaN();
        }
    }
}
