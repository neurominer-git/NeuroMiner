function [mDTs, mTTs, mWTs, Classes, mcolstart, mcolend] = nk_MultiAssemblePredictions( tsD, tsT, Wkl, mDTs, mTTs, mWTs, Classes, ul, curclass, mcolend )

ClassVec = ones(1,size(tsD,2))*curclass;

% Compute column pointers for multi-group CV2 array construction
mcolstart = mcolend + 1; mcolend = mcolstart + (ul-1);
dest = mcolstart:mcolend;
% Enter decision values and predictions
% for multi-group classification into CV2 arrays
mDTs(:,dest) = tsD; 
mTTs(:,dest) = tsT;
if isempty( Wkl ) && ~isempty( mWTs )
    mWTs(1,dest) = 1;
elseif ~isempty( Wkl ) && ~isempty( mWTs )
    mWTs(1,dest) = Wkl(:).';
end
Classes(1,dest) = ClassVec;
