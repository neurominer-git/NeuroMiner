function [D, mD] = nk_ComputeMnMdPairWiseDiff(G, func, act)
% Purpose: Compute the legacy median/mean one-vs-all or directed one-vs-one matched performance deltas.
% Syntax: [D,mD] = nk_ComputeMnMdPairWiseDiff(G,func,act)
% Inputs: Matched block-by-model matrix, summary selector mn/md and action meandiff/alldiff.
% Outputs: Canonical delta arrays and corresponding summary values.
% Authority and flow: Preserves the supplied legacy helper exactly as the Cross-analysis Quade plotting delta authority.
% Scientific/state contract: Stage-2 uses md with meandiff/alldiff; browser/report renderers consume these backend deltas rather than reconstructing them.
% Invariants: Input model order and matched block order are preserved.
% Materialization and performance: O(B*A^2) numeric delta work; no feature-scale materialization.
% Resource declaration: Reads no files, parses no XML, loads no atlas/annotation/mesh resources, scans no voxels or vertices, and creates no feature-scale arrays; compact statistical vectors only.
% Interactive/retained use: Intended for explicit statistical comparison/report actions, not high-frequency retained interaction.
% Failure semantics: Unsupported func/act follows legacy behavior; no fallback is added.
% Side effects: No NM mutation; optional legacy file writing occurs only when the existing filename argument is explicitly supplied.
% Consumers and dependencies: NMResultsViewerCrossAnalysisTools Quade plot payload; nm_nanmean/nm_nanmedian.

switch func
    case 'mn'
        func = @nm_nanmean;
    case 'md'
        func = @nm_nanmedian;
end
[m,n] = size(G);

switch act
    case 'meandiff'
        D = zeros(m,n);
        for i=1:n
            vec = true(1,n); vec(i)=false;
            D(:,i) = func(G(:,i)-G(:,vec),2);
        end
        mD = func(D);
    case 'alldiff'
        D = zeros(m,n-1,n);
        mD = zeros(1,n-1,n);
        for i=1:n
            vec = true(1,n); vec(i)=false;
            D(:,:,i) = G(:,i)-G(:,vec);
            mD(:,:,i) = func(D(:,:,i));
        end
        
end
