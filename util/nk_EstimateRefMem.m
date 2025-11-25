function bytes = nk_EstimateRefMem(Ref, I2, h, isInter, nM)

bytes = 0;
% refs
for m=1:numel(Ref)
    X = Ref{m}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
end
% common large CV2 containers
for n=1:nM
    flds = {'VCV2SUM','VCV2SQ','VCV2SEL','VCV2PROB','SignPosCount','SignNegCount'};
    for f = 1:numel(flds)
        X = I2.(flds{f}){h,n};
        if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
    end
    X = I2.GCV2SUM{h,n};  if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
    X = I2.VCV2STD{h,n};  if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
    X = I2.VCV2MEAN{h,n}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
end
if isfield(I2,'VCV2WPERMREF') && isfield(I2,'VCV2WCORRREF') 
    if isInter
        if numel(I2.VCV2WPERMREF{h}) == n
            for n=1:nM
                X = I2.VCV2WPERMREF{h}{n}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
                X = I2.VCV2WCORRREF{h}{n}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
                X = I2.ModComp_L2n{h}{n};  if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
            end
        end
    else
        X = I2.VCV2WPERMREF{h}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
        X = I2.VCV2WCORRREF{h}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
        X = I2.ModComp_L2n{h};  if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end
        if nM>1, X = I2.ModComp_L2nCube{h}; if ~isempty(X), bytes = bytes + numel(X)*local_bps(X); end, end
    end
end

function b = local_bps(X)

switch class(X)
    case {'double'}, b = 8;
    case {'single'}, b = 4;
    case {'logical','int8','uint8'}, b = 1;
    case {'int16','uint16'}, b = 2;
    case {'int32','uint32'}, b = 4;
    case {'int64','uint64'}, b = 8;
    otherwise, b = 8;
end
