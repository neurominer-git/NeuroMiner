function getperm = nk_VisXPermHelper_gen(N, L, baseSeed)
% Returns a function handle: idx = getperm(k)
% that deterministically returns the k-th permutation indices for labels L.
% Works stratified (by labels) or unstratified if L is empty.

    if nargin < 3 || isempty(baseSeed)
        baseSeed = 1357911;  % any fixed integer -> reproducible
    end

    % Use a counter-based RNG with substreams (great for replay)
    baseStream = RandStream('Threefry', 'Seed', baseSeed);

    if nargin >= 2 && ~isempty(L)
        uL  = unique(L(:)');
        nuL = numel(uL);
        % Stratified permutation function
        getperm = @(k) stratified_perm(N, L, uL, nuL, baseStream, k);
    else
        % Unstratified permutation function
        getperm = @(k) plain_perm(N, baseStream, k);
    end
end

function idx = plain_perm(N, baseStream, k)
    s = RandStream('Threefry','Seed',baseStream.Seed);
    s.Substream = k;                   % <-- replay key
    idx = randperm(s, N).';
end

function idx = stratified_perm(N, L, uL, nuL, baseStream, k)
    s = RandStream('Threefry','Seed',baseStream.Seed);
    s.Substream = k;                   % <-- replay key
    idx = zeros(N,1,'uint32');
    pool = uint32((1:N).');
    offset = 0;
    % We permute within each class *using the same stream* to stay deterministic
    for n = 1:nuL
        mask = (L == uL(n));
        nn   = sum(mask);
        % pick nn positions from the remaining pool
        pick = randperm(s, numel(pool)-(offset), nn) + offset;
        idx(mask) = pool(pick);
        % remove used entries by swapping down the offset (no reallocation)
        pool(pick) = [];
    end
    idx = double(idx);  % match your existing numeric type if needed
end
