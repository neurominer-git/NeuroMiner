classdef NMHierarchicalClusteringTools
    % NMHierarchicalClusteringTools  Toolbox-independent hierarchical clustering utilities.
    %
    % This class implements deterministic average-linkage agglomeration and
    % exact optimal leaf ordering using base MATLAB only. It is intended for
    % bounded Results Viewer feature-relation matrices whose dissimilarities
    % are complete, finite, symmetric, and non-negative.
    %
    % Public methods do not mutate NeuroMiner state. Stable leaf identifiers
    % are used only for deterministic tie resolution and orientation; they do
    % not alter the clustering objective.

    methods (Static)
        function [linkageMatrix,leafOrder,objective] = averageLinkageOptimalOrder(distanceMatrix,stableLeafIds)
            % averageLinkageOptimalOrder  Build an average-linkage tree and exact optimal leaf order.
            %
            % [Z,ORDER,OBJECTIVE] = averageLinkageOptimalOrder(D,IDS) validates
            % the complete dissimilarity matrix D, builds a deterministic
            % average-linkage tree, and finds the tree-compatible leaf order
            % minimizing the sum of adjacent dissimilarities. IDS must contain
            % one finite unique scalar per row of D and is used for deterministic
            % tie handling only.
            [distanceMatrix,stableLeafIds]=NMHierarchicalClusteringTools.validateInputs( ...
                distanceMatrix,stableLeafIds);
            linkageMatrix=NMHierarchicalClusteringTools.averageLinkageTree( ...
                distanceMatrix,stableLeafIds);
            [leafOrder,objective]=NMHierarchicalClusteringTools.exactOptimalLeafOrder( ...
                linkageMatrix,distanceMatrix,stableLeafIds);
        end

        function distanceMatrix = rmsDistances(X)
            % Canonical RMS distance used for signed contribution profiles and resampling.
            n=size(X,1);
            distanceMatrix=zeros(n,n);
            for ii=1:n-1
                differences=X(ii+1:n,:)-X(ii,:);
                distances=sqrt(mean(differences.^2,2));
                distanceMatrix(ii,ii+1:n)=distances';
                distanceMatrix(ii+1:n,ii)=distances;
            end
        end

        function linkageMatrix = averageLinkage(distanceMatrix,stableLeafIds)
            % Linkage without optimal leaf ordering for repeated stability fits.
            [distanceMatrix,stableLeafIds]=NMHierarchicalClusteringTools.validateInputs(distanceMatrix,stableLeafIds);
            linkageMatrix=NMHierarchicalClusteringTools.averageLinkageTree(distanceMatrix,stableLeafIds);
        end

        function [selection,selectedConsensus] = selectCount(D,X,Z,minimum,maximum,criterion,repeats)
            % Selection on a fixed complete-component axis. Feature bootstrap
            % uses a local RNG and never alters MATLAB's global random stream.
            candidates=minimum:maximum;
            values=nan(size(candidates));
            n=size(D,1);
            selectedConsensus=[];
            bestConsensusScore=NaN;
            if ~strcmp(criterion,'silhouette')
                stream=RandStream('mt19937ar','Seed',271828);
                trees=cell(1,repeats);
            end
            for jj=1:numel(candidates)
                k=candidates(jj);
                if jj==1 && ~strcmp(criterion,'silhouette')
                    for rep=1:repeats
                        indices=randi(stream,size(X,2),[1 size(X,2)]);
                        sampleDistance=NMHierarchicalClusteringTools.rmsDistances(X(:,indices));
                        trees{rep}=NMHierarchicalClusteringTools.averageLinkage(sampleDistance,(1:n)');
                        NMRuntimeProgressTools.writeGenericProgressSafe('Current k', ...
                            sprintf('k=%d: bootstrap %d/%d',k,rep,repeats), ...
                            75*rep/repeats,'resampling');
                    end
                end
                if strcmp(criterion,'silhouette')
                    completed=100*(jj-1)/numel(candidates);
                    increment=100/numel(candidates);
                else
                    completed=75+24*(jj-1)/numel(candidates);
                    increment=24/numel(candidates);
                end
                NMRuntimeProgressTools.writeGenericProgressSafe('Current k', ...
                    sprintf('Evaluating k=%d/%d: %s',k,maximum,upper(criterion)),completed,'selection');
                labels=NMHierarchicalClusteringTools.extractClusters(Z,1:n,'fixed_count',k,0);
                if strcmp(criterion,'silhouette')
                    si=zeros(n,1);
                    for i=1:n
                        same=find(labels==labels(i));same(same==i)=[];
                        if isempty(same),continue;end
                        within=mean(D(i,same));between=inf;
                        for c=1:k
                            if c==labels(i),continue;end
                            between=min(between,mean(D(i,labels==c)));
                        end
                        if max(within,between)>0
                            si(i)=(between-within)/max(within,between);
                        end
                    end
                    values(jj)=mean(si);
                else
                    agreements=nan(1,repeats);
                    consensus=zeros(n,n);
                    for rep=1:repeats
                        perturbed=NMHierarchicalClusteringTools.extractClusters(trees{rep},1:n,'fixed_count',k,0);
                        consensus=consensus+double(perturbed(:)==perturbed(:)');
                        if strcmp(criterion,'ari')
                            contingency=accumarray([labels(:),perturbed(:)],1,[k k]);
                            pairs=@(v) sum(v(:).*(v(:)-1)/2);
                            a=pairs(sum(contingency,2));b=pairs(sum(contingency,1));
                            chance=a*b/(n*(n-1)/2);
                            denominator=(a+b)/2-chance;
                            if denominator>0
                                agreements(rep)=(pairs(contingency)-chance)/denominator;
                            end
                        end
                    end
                    consensus=consensus/repeats;
                    triangle=triu(true(n),1);
                    if strcmp(criterion,'ari')
                        values(jj)=mean(agreements(isfinite(agreements)));
                    elseif strcmp(criterion,'pac')
                        fractions=consensus(triangle);
                        values(jj)=mean(fractions>0.1 & fractions<0.9);
                    else
                        consensusDistance=1-consensus;
                        consensusDistance(1:n+1:end)=0;
                        tree=NMHierarchicalClusteringTools.averageLinkage(consensusDistance,(1:n)');
                        cophenetic=zeros(n,n);
                        members=cell(2*n-1,1);
                        for i=1:n,members{i}=i;end
                        for m=1:n-1
                            left=round(tree(m,1));right=round(tree(m,2));
                            ia=members{left};ib=members{right};
                            cophenetic(ia,ib)=tree(m,3);
                            cophenetic(ib,ia)=tree(m,3);
                            members{n+m}=[ia ib];
                        end
                        observed=consensusDistance(triangle);
                        fitted=cophenetic(triangle);
                        observed=observed-mean(observed);fitted=fitted-mean(fitted);
                        den=sqrt(sum(observed.^2)*sum(fitted.^2));
                        if den>0,values(jj)=sum(observed.*fitted)/den;end
                    end
                    if (strcmp(criterion,'pac') || strcmp(criterion,'cophenetic')) && ...
                            isfinite(values(jj)) && (isnan(bestConsensusScore) || ...
                            (strcmp(criterion,'pac') && values(jj)<bestConsensusScore) || ...
                            (strcmp(criterion,'cophenetic') && values(jj)>bestConsensusScore))
                        bestConsensusScore=values(jj);
                        selectedConsensus=consensus;
                    end
                end
                NMRuntimeProgressTools.writeGenericProgressSafe('Current k', ...
                    sprintf('Completed k=%d/%d: %s',k,maximum,upper(criterion)), ...
                    completed+increment,'selection');
            end
            eligible=find(isfinite(values));
            if isempty(eligible)
                error('NMHierarchicalClusteringTools:NoValidClusterCriterion', ...
                    'The selected criterion is undefined throughout the requested cluster range.');
            end
            if strcmp(criterion,'pac')
                [~,idx]=min(values(eligible));
            else
                [~,idx]=max(values(eligible));
            end
            selected=candidates(eligible(idx));
            selection=struct('criterion',criterion,'testedClusters',candidates,'values',values, ...
                'selectedClusters',selected,'replicates',repeats,'direction', ...
                'max');
            if strcmp(criterion,'pac'),selection.direction='min';end
            if strcmp(criterion,'silhouette'),selection.replicates=0;end
        end

        function [orderedAssignments,count] = extractClusters(linkageMatrix,leafOrder,mode,clusterCount,cutHeight)
            % extractClusters  Cut one linkage tree and normalize cluster IDs by leaf order.
            n=numel(leafOrder);
            orderedAssignments=zeros(1,0);
            count=0;
            if n<1, return; end
            if strcmp(mode,'fixed_count')
                if clusterCount<2 || clusterCount>n, return; end
                mergeCount=n-clusterCount;
            elseif strcmp(mode,'cut_height')
                mergeCount=find(linkageMatrix(:,3)<=cutHeight,1,'last');
                if isempty(mergeCount), mergeCount=0; end
            else
                return;
            end
            members=cell(2*n-1,1);
            for ii=1:n, members{ii}=ii; end
            labels=1:n;
            for row=1:size(linkageMatrix,1)
                left=round(linkageMatrix(row,1));
                right=round(linkageMatrix(row,2));
                newId=n+row;
                members{newId}=[members{left} members{right}];
                if row<=mergeCount
                    labels(members{newId})=newId;
                end
            end
            raw=labels(leafOrder);
            orderedAssignments=zeros(1,n);
            seen=zeros(1,0);
            for position=1:n
                match=find(seen==raw(position),1,'first');
                if isempty(match)
                    seen(end+1)=raw(position); %#ok<AGROW>
                    match=numel(seen);
                end
                orderedAssignments(position)=match;
            end
            count=numel(seen);
        end

        function linkageMatrix = averageLinkageTree(distanceMatrix,stableLeafIds)
            % averageLinkageTree  Construct a deterministic UPGMA/average-linkage tree.
            [distanceMatrix,stableLeafIds]=NMHierarchicalClusteringTools.validateInputs( ...
                distanceMatrix,stableLeafIds);
            n=size(distanceMatrix,1);
            if n<2
                linkageMatrix=zeros(0,3);
                return;
            end
            maxNodes=2*n-1;
            distances=inf(maxNodes,maxNodes);
            distances(1:n,1:n)=distanceMatrix;
            distances(1:maxNodes+1:end)=inf;
            active=false(maxNodes,1);
            active(1:n)=true;
            clusterSize=zeros(maxNodes,1);
            clusterSize(1:n)=1;
            clusterStableMin=inf(maxNodes,1);
            clusterStableMin(1:n)=stableLeafIds;
            linkageMatrix=zeros(n-1,3);
            for row=1:n-1
                activeIds=find(active);
                sub=distances(activeIds,activeIds);
                upperMask=triu(true(numel(activeIds)),1);
                candidateValues=sub(upperMask);
                minimum=min(candidateValues);
                if isempty(minimum) || ~isfinite(minimum)
                    error('NMHierarchicalClusteringTools:averageLinkageCandidate', ...
                        'Average linkage could not resolve a finite active-cluster distance at merge %d.',row);
                end
                tolerance=max(1,abs(minimum))*eps*32;
                [candidateRows,candidateCols]=find(upperMask & abs(sub-minimum)<=tolerance);
                candidatePairs=[activeIds(candidateRows) activeIds(candidateCols)];
                keys=zeros(size(candidatePairs,1),6);
                for ii=1:size(candidatePairs,1)
                    first=candidatePairs(ii,1);
                    second=candidatePairs(ii,2);
                    firstKey=clusterStableMin(first);
                    secondKey=clusterStableMin(second);
                    if firstKey>secondKey || (firstKey==secondKey && first>second)
                        tmp=first; first=second; second=tmp;
                        tmpKey=firstKey; firstKey=secondKey; secondKey=tmpKey;
                    end
                    candidatePairs(ii,:)=[first second];
                    keys(ii,:)=[firstKey secondKey min(first,second) max(first,second) first second];
                end
                [~,order]=sortrows(keys,[1 2 3 4 5 6]);
                left=candidatePairs(order(1),1);
                right=candidatePairs(order(1),2);
                newId=n+row;
                linkageMatrix(row,:)=[left right minimum];
                otherIds=activeIds(activeIds~=left & activeIds~=right);
                totalSize=clusterSize(left)+clusterSize(right);
                for jj=1:numel(otherIds)
                    other=otherIds(jj);
                    value=(clusterSize(left)*distances(left,other)+ ...
                        clusterSize(right)*distances(right,other))/totalSize;
                    distances(newId,other)=value;
                    distances(other,newId)=value;
                end
                active(left)=false;
                active(right)=false;
                active(newId)=true;
                clusterSize(newId)=totalSize;
                clusterStableMin(newId)=min(clusterStableMin(left),clusterStableMin(right));
            end
        end

        function [leafOrder,objective] = exactOptimalLeafOrder(linkageMatrix,distanceMatrix,stableLeafIds)
            % exactOptimalLeafOrder  Find the minimum-adjacent-distance order for one binary tree.
            %
            % The dynamic program stores the best tree-compatible path for
            % every feasible pair of subtree endpoints. Its general complexity
            % is O(n^3) time and O(n^2) retained state per tree level.
            [distanceMatrix,stableLeafIds]=NMHierarchicalClusteringTools.validateInputs( ...
                distanceMatrix,stableLeafIds);
            n=size(distanceMatrix,1);
            NMHierarchicalClusteringTools.validateLinkage(linkageMatrix,n);
            if n==1
                leafOrder=1;
                objective=0;
                return;
            end
            states=cell(2*n-1,1);
            for leaf=1:n
                states{leaf}=struct('left',0,'right',0,'leaves',leaf, ...
                    'cost',0,'firstEnd',uint16(leaf),'secondStart',uint16(leaf));
            end
            for row=1:n-1
                nodeId=n+row;
                leftId=round(linkageMatrix(row,1));
                rightId=round(linkageMatrix(row,2));
                leftState=states{leftId};
                rightState=states{rightId};
                leftLeaves=leftState.leaves(:);
                rightLeaves=rightState.leaves(:);
                allLeaves=[leftLeaves;rightLeaves];
                [~,stableOrder]=sortrows([stableLeafIds(allLeaves) allLeaves],[1 2]);
                leaves=allLeaves(stableOrder);
                leafCount=numel(leaves);
                cost=inf(leafCount,leafCount);
                firstEnd=zeros(leafCount,leafCount,'uint16');
                secondStart=zeros(leafCount,leafCount,'uint16');
                [~,leftPositions]=ismember(leftLeaves,leaves);
                [~,rightPositions]=ismember(rightLeaves,leaves);
                leftCount=numel(leftLeaves);
                rightCount=numel(rightLeaves);

                % For each possible right-subtree entry leaf, resolve the
                % cheapest left-subtree terminal leaf for every left start.
                intermediate=inf(leftCount,rightCount);
                intermediateLeftEnd=zeros(leftCount,rightCount);
                for rightEntry=1:rightCount
                    bridge=distanceMatrix(leftLeaves,rightLeaves(rightEntry));
                    candidates=bsxfun(@plus,leftState.cost,reshape(bridge,1,leftCount));
                    [intermediate(:,rightEntry),bestLeftEnd]=min(candidates,[],2);
                    intermediateLeftEnd(:,rightEntry)=bestLeftEnd;
                end

                % Complete left-to-right paths for all endpoint pairs. The
                % reverse path has the same objective and is recorded with
                % reversed child-transition endpoints.
                for rightEnd=1:rightCount
                    candidates=bsxfun(@plus,intermediate,reshape(rightState.cost(:,rightEnd)',1,rightCount));
                    [bestValues,bestRightEntry]=min(candidates,[],2);
                    for leftStart=1:leftCount
                        rightEntry=bestRightEntry(leftStart);
                        leftEnd=intermediateLeftEnd(leftStart,rightEntry);
                        leftPosition=leftPositions(leftStart);
                        rightPosition=rightPositions(rightEnd);
                        cost(leftPosition,rightPosition)=bestValues(leftStart);
                        firstEnd(leftPosition,rightPosition)=uint16(leftLeaves(leftEnd));
                        secondStart(leftPosition,rightPosition)=uint16(rightLeaves(rightEntry));
                        cost(rightPosition,leftPosition)=bestValues(leftStart);
                        firstEnd(rightPosition,leftPosition)=uint16(rightLeaves(rightEntry));
                        secondStart(rightPosition,leftPosition)=uint16(leftLeaves(leftEnd));
                    end
                end
                states{nodeId}=struct('left',leftId,'right',rightId,'leaves',leaves, ...
                    'cost',cost,'firstEnd',firstEnd,'secondStart',secondStart);
                leftState.cost=[];
                rightState.cost=[];
                states{leftId}=leftState;
                states{rightId}=rightState;
            end
            rootId=2*n-1;
            root=states{rootId};
            minimum=min(root.cost(:));
            tolerance=max(1,abs(minimum))*eps*64;
            [startPositions,endPositions]=find(abs(root.cost-minimum)<=tolerance);
            keys=zeros(numel(startPositions),4);
            normalizedStarts=zeros(numel(startPositions),1);
            normalizedEnds=zeros(numel(startPositions),1);
            for ii=1:numel(startPositions)
                startLeaf=root.leaves(startPositions(ii));
                endLeaf=root.leaves(endPositions(ii));
                if stableLeafIds(startLeaf)>stableLeafIds(endLeaf) || ...
                        (stableLeafIds(startLeaf)==stableLeafIds(endLeaf) && startLeaf>endLeaf)
                    tmp=startLeaf; startLeaf=endLeaf; endLeaf=tmp;
                end
                normalizedStarts(ii)=startLeaf;
                normalizedEnds(ii)=endLeaf;
                keys(ii,:)=[stableLeafIds(startLeaf) stableLeafIds(endLeaf) startLeaf endLeaf];
            end
            [~,candidateOrder]=sortrows(keys,[1 2 3 4]);
            startLeaf=normalizedStarts(candidateOrder(1));
            endLeaf=normalizedEnds(candidateOrder(1));
            leafOrder=NMHierarchicalClusteringTools.reconstructOrder( ...
                rootId,startLeaf,endLeaf,states,n);
            leafOrder=leafOrder(:);
            if stableLeafIds(leafOrder(1))>stableLeafIds(leafOrder(end)) || ...
                    (stableLeafIds(leafOrder(1))==stableLeafIds(leafOrder(end)) && leafOrder(1)>leafOrder(end))
                leafOrder=flipud(leafOrder);
            end
            if numel(leafOrder)~=n || numel(unique(leafOrder))~=n || any(sort(leafOrder(:))'~=(1:n))
                error('NMHierarchicalClusteringTools:leafOrderPermutation', ...
                    'Optimal leaf ordering did not reconstruct one complete leaf permutation.');
            end
            objective=NMHierarchicalClusteringTools.adjacentObjective(distanceMatrix,leafOrder);
            if ~isfinite(objective)
                error('NMHierarchicalClusteringTools:leafOrderObjective', ...
                    'Optimal leaf ordering produced a non-finite adjacency objective.');
            end
        end

        function objective = adjacentObjective(distanceMatrix,leafOrder)
            % adjacentObjective  Sum dissimilarities between adjacent leaves.
            if numel(leafOrder)<2
                objective=0;
                return;
            end
            leafOrder=leafOrder(:);
            indices=sub2ind(size(distanceMatrix),leafOrder(1:end-1),leafOrder(2:end));
            objective=sum(distanceMatrix(indices));
        end
    end

    methods (Static, Access=private)
        function [distanceMatrix,stableLeafIds] = validateInputs(distanceMatrix,stableLeafIds)
            if ~(isnumeric(distanceMatrix) || islogical(distanceMatrix)) || ndims(distanceMatrix)~=2 || ...
                    size(distanceMatrix,1)~=size(distanceMatrix,2) || isempty(distanceMatrix)
                error('NMHierarchicalClusteringTools:distanceShape', ...
                    'The dissimilarity input must be one non-empty square numeric matrix.');
            end
            distanceMatrix=double(distanceMatrix);
            n=size(distanceMatrix,1);
            if n>double(intmax('uint16'))
                error('NMHierarchicalClusteringTools:leafCountLimit', ...
                    'The clustering utility supports at most %d leaves.',double(intmax('uint16')));
            end
            if nargin<2 || isempty(stableLeafIds)
                stableLeafIds=(1:n)';
            end
            if ~(isnumeric(stableLeafIds) || islogical(stableLeafIds)) || numel(stableLeafIds)~=n
                error('NMHierarchicalClusteringTools:stableLeafIdsShape', ...
                    'stableLeafIds must contain one numeric value per dissimilarity row.');
            end
            stableLeafIds=double(stableLeafIds(:));
            if any(~isfinite(stableLeafIds)) || numel(unique(stableLeafIds))~=n
                error('NMHierarchicalClusteringTools:stableLeafIdsInvalid', ...
                    'stableLeafIds must contain finite unique values.');
            end
            if any(~isfinite(distanceMatrix(:))) || any(distanceMatrix(:)<0)
                error('NMHierarchicalClusteringTools:distanceValues', ...
                    'Dissimilarities must be finite and non-negative.');
            end
            tolerance=max(1,max(abs(distanceMatrix(:))))*eps*64;
            transposedDistance=distanceMatrix';
            if max(abs(distanceMatrix(:)-transposedDistance(:)))>tolerance
                error('NMHierarchicalClusteringTools:distanceSymmetry', ...
                    'The dissimilarity matrix must be symmetric.');
            end
            distanceMatrix=(distanceMatrix+distanceMatrix')/2;
            if any(abs(diag(distanceMatrix))>tolerance)
                error('NMHierarchicalClusteringTools:distanceDiagonal', ...
                    'The dissimilarity matrix diagonal must be zero.');
            end
            distanceMatrix(1:n+1:end)=0;
        end

        function validateLinkage(linkageMatrix,n)
            if n==1
                if ~isempty(linkageMatrix)
                    error('NMHierarchicalClusteringTools:linkageShape', ...
                        'A one-leaf tree must have an empty linkage matrix.');
                end
                return;
            end
            if ~isnumeric(linkageMatrix) || ~isequal(size(linkageMatrix),[n-1 3]) || ...
                    any(~isfinite(linkageMatrix(:)))
                error('NMHierarchicalClusteringTools:linkageShape', ...
                    'The linkage matrix must be finite with size (n-1)-by-3.');
            end
            for row=1:n-1
                maximumChild=n+row-1;
                children=linkageMatrix(row,1:2);
                if any(children<1) || any(children>maximumChild) || any(children~=round(children)) || ...
                        children(1)==children(2)
                    error('NMHierarchicalClusteringTools:linkageTopology', ...
                        'Linkage row %d contains an invalid child identifier.',row);
                end
            end
        end

        function order = reconstructOrder(nodeId,startLeaf,endLeaf,states,n)
            if nodeId<=n
                if startLeaf~=nodeId || endLeaf~=nodeId
                    error('NMHierarchicalClusteringTools:reconstructionLeaf', ...
                        'Leaf reconstruction endpoints are inconsistent.');
                end
                order=nodeId;
                return;
            end
            state=states{nodeId};
            leftState=states{state.left};
            rightState=states{state.right};
            startInLeft=any(leftState.leaves==startLeaf);
            endInLeft=any(leftState.leaves==endLeaf);
            if startInLeft==endInLeft
                error('NMHierarchicalClusteringTools:reconstructionEndpoints', ...
                    'Internal-node endpoints must lie in different child subtrees.');
            end
            startPosition=find(state.leaves==startLeaf,1,'first');
            endPosition=find(state.leaves==endLeaf,1,'first');
            firstEnd=double(state.firstEnd(startPosition,endPosition));
            secondStart=double(state.secondStart(startPosition,endPosition));
            if firstEnd<1 || secondStart<1
                error('NMHierarchicalClusteringTools:reconstructionBackpointer', ...
                    'Optimal-leaf-order backpointers are incomplete.');
            end
            if startInLeft
                firstOrder=NMHierarchicalClusteringTools.reconstructOrder( ...
                    state.left,startLeaf,firstEnd,states,n);
                secondOrder=NMHierarchicalClusteringTools.reconstructOrder( ...
                    state.right,secondStart,endLeaf,states,n);
            else
                firstOrder=NMHierarchicalClusteringTools.reconstructOrder( ...
                    state.right,startLeaf,firstEnd,states,n);
                secondOrder=NMHierarchicalClusteringTools.reconstructOrder( ...
                    state.left,secondStart,endLeaf,states,n);
            end
            order=[firstOrder(:);secondOrder(:)];
        end
    end
end
