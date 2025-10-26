function C = nk_NanMatrixAddition(A, B) % 1) Add them directly – this will produce NaN wherever either input is NaN

C = A + B;

% 2) Find those “NaN because one input was missing” locations,
%    and fill in the one non‐NaN value instead of leaving NaN.
nanC = isnan(C);
% if C is NaN but A is not, use A
maskA = nanC & ~isnan(A);
C(maskA) = A(maskA);
% if C is NaN but B is not, use B
maskB = nanC & ~isnan(B);
C(maskB) = B(maskB);