function op = nk_SurfaceHeatKernel(contract, vertexMask)
% nk_SurfaceHeatKernel  Geometry-aware cotangent FEM surface heat operator.
% DataIO is the sole authority for native/inflated topology and vertex order.
% Uses native (non-inflated) coordinates for the metric; hemispheres do not mix.
% vertexMask excludes nonfinite scalar vertices and their incident graph edges.
% No external graph toolbox or compiled dependency is required.

assert(contract.nativeAvailable && contract.inflatedValidated, ...
    'nk_SurfaceHeatKernel:missingMeshes', ...
    'Surface spatial preprocessing requires corresponding native and inflated DataIO meshes.');

n = contract.vertexCount;
assert(isequal(size(vertexMask),[n 1]), ...
    'nk_SurfaceHeatKernel:invalidMask', ...
    'Surface vertex mask must be an nVertices-by-1 logical vector.');
persistent lastIdentity lastMask lastOperator
if isequal(lastIdentity, contract.nativeGeometryIdentity) && ...
        isequal(lastMask,vertexMask) && ~isempty(lastOperator)
    op = lastOperator;
    return
end

K = sparse(n,n);
m = zeros(n,1);
offset = 0;
for p = 1:contract.partCount
    part = contract.parts(p);
    [v,f] = NMDataIOSurfaceTools.readSurfaceGeometry(part.nativeFile);
    v = double(v);
    f = double(f) + 1; % The DataIO geometry reader returns zero-based faces.
    nv = size(v,1);
    if nv ~= part.vertexCount
        error('nk_SurfaceHeatKernel:changedGeometry', ...
            'Surface vertex count changed after DataIO validation: %s',part.nativeFile);
    end
    if size(f,1) ~= part.faceCount
        error('nk_SurfaceHeatKernel:changedGeometry', ...
            'Surface geometry changed after DataIO validation: %s',part.nativeFile);
    end
    a = f(:,1); b = f(:,2); c = f(:,3);
    ab = v(b,:) - v(a,:);
    ac = v(c,:) - v(a,:);
    cr = cross(ab,ac,2);
    twiceArea = sqrt(sum(cr.^2,2));
    if any(twiceArea <= 0)
        error('nk_SurfaceHeatKernel:degenerateTriangle', ...
            'Surface mesh contains a zero-area triangle: %s',part.nativeFile);
    end
    cotA = sum(ab.*ac,2)./twiceArea;
    cotB = sum((v(c,:)-v(b,:)).*(v(a,:)-v(b,:)),2)./twiceArea;
    cotC = sum((v(a,:)-v(c,:)).*(v(b,:)-v(c,:)),2)./twiceArea;
    wAB = cotC/2; wBC = cotA/2; wCA = cotB/2;
    ii = [a;b;b;c;c;a];
    jj = [b;a;c;b;a;c];
    ww = [wAB;wAB;wBC;wBC;wCA;wCA];
    active = vertexMask(offset+(1:nv));
    ww(~(active(ii) & active(jj))) = 0;
    A = sparse(ii,jj,-ww,nv,nv);
    Kp = A + spdiags(-sum(A,2),0,nv,nv);
    idx = offset+(1:nv);
    K(idx,idx) = Kp;
    m(idx) = accumarray([a;b;c],repmat(twiceArea/6,3,1),[nv,1]);
    offset = offset + nv;
end
if offset ~= n || any(m <= 0)
    error('nk_SurfaceHeatKernel:invalidSurfaceAxis', ...
        'Mesh vertices must match the complete DataIO feature axis with positive vertex areas.');
end
rootInv = 1./sqrt(m);
S = spdiags(rootInv,0,n,n)*K*spdiags(rootInv,0,n,n);
lmax = full(max(sum(abs(S),2))); % Gershgorin upper bound, no eigendecomposition.
if ~isfinite(lmax) || lmax <= 0
    error('nk_SurfaceHeatKernel:invalidLaplacian', ...
        'Surface stiffness operator does not have a positive finite spectral bound.');
end
B = speye(n) - (2/lmax)*S;
op = struct('B',B,'sqrtMass',sqrt(m),'inverseSqrtMass',rootInv, ...
    'lambdaBound',lmax,'vertexCount',n,'vertexMask',vertexMask);
lastIdentity = contract.nativeGeometryIdentity;
lastMask = vertexMask;
lastOperator = op;
end
