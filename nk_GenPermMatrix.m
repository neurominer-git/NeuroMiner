function G = nk_GenPermMatrix(CV, inp, nperms, baseSeed)
% Replayable "parent permutation matrix" generator.
% Instead of allocating (N×nperms), returns a struct G with:
%   - G.N, G.nperms, G.baseSeed
%   - G.lb{h}  (index sets you permute within)
%   - G.getperm(h,k)  -> N×1 index vector for class h, permutation k

    if numel(nperms) > 1, nperms = nperms(1); end
    if nargin < 4 || isempty(baseSeed), baseSeed = uint64(20251012); end

    fprintf('\nCreating parent permutation handle with %g perms. ', nperms);

    N = numel(inp.label);        % assuming column vector
    G = struct;
    G.N = N;
    G.nperms = nperms;
    G.baseSeed = uint64(baseSeed);
    G.lb = cell(1, inp.nclass);

    if inp.nclass > 1
        for h = 1:inp.nclass
            if isscalar(CV.class{1,1}{1}.groups)
                % one-vs-all
                pos = find(inp.label == CV.class{1,1}{h}.groups(1));
                neg = find(inp.label ~= CV.class{1,1}{h}.groups(1));
                lb  = [pos; neg];
            else
                % one-vs-one
                g1  = CV.class{1,1}{h}.groups(1);
                g2  = CV.class{1,1}{h}.groups(2);
                lb  = [find(inp.label == g1); find(inp.label == g2)];
            end
            G.lb{h} = lb(:);
        end
    else
        % single-class case -> permute all rows
        G.lb{1} = (1:N).';
    end

    % function handle: get the k-th permutation indices for class h
    G.getperm = @(h,k) local_perm_within_indices( ...
                          G.N, G.lb{h}, G.baseSeed, h, k);
end

function pIdx = local_perm_within_indices(N, lb, baseSeed, h, k)
% Returns an N×1 vector of indices like your old indpermA{h}(:,k),
% permuting only within lb and leaving everything else identity.
%
% - N: total number of rows
% - lb: column vector of indices to permute (the set you permuted before)
% - baseSeed: fixed integer for reproducibility
% - h: class index (to derive a distinct substream family per class)
% - k: permutation number (1..nperms), used as Substream

    s = RandStream('Threefry', 'Seed', baseSeed + uint64(h));  % family per class
    s.Substream = k;                                           % permutation id
    pIdx = (1:N)';                                             % identity mapping
    % permute within lb, exactly as before:
    order = randperm(s, numel(lb));
    pIdx(lb) = lb(order);
end