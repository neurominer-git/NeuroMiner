function vizHandles = nk_VisVisitedIdx(visited, candidateMatrix, hpNames)
% Visited indices viz that only updates data (no clf/cla), always plots CV1+CV2.
% Stores/retrieves all handles via figure appdata ('VisitedIndicesVizHandles').

    if nargin < 3, hpNames = []; end
    if isempty(visited), warning('No visited candidate indices to visualize.'); vizHandles = struct(); return; end

    % Unpack (CV1=cost, CV2 present always per your constraint)
    visitedIndices = [visited.index];
    CV1 = [visited.cost];
    CV2 = [visited.CV2];  % <- guaranteed present

    % Decide mode (per-HP vs overall)
    nTotal = size(candidateMatrix,2);
    qualHP = find(arrayfun(@(i) numel(unique(candidateMatrix(:,i))) > 1, 1:nTotal));
    mode = 1 + (numel(qualHP) >= 5);  % 1 if <5, else 2

    % Find or create figure
    figTag = 'VisitedIndicesViz';
    fig = findall(0,'Type','figure','Tag',figTag);
    if isempty(fig) || ~isvalid(fig(1))
        fig = figure('Tag', figTag, 'Name','Visited Indices Analysis', 'NumberTitle','off');
        H = buildOnce(fig, mode, qualHP, hpNames, candidateMatrix);
        setappdata(fig,'VisitedIndicesVizHandles', H);
    else
        fig = fig(1);
        H = getappdata(fig,'VisitedIndicesVizHandles');
        % If layout no longer matches (mode/HPs), rebuild ONCE (still no clf/cla on update path).
        if isempty(H) || ~isstruct(H) || H.mode ~= mode || (mode==1 && ~isequal(H.hpIdx, qualHP))
            close(fig); % safest to avoid orphaned handles; we re-create fully once
            fig = figure('Tag', figTag, 'Name','Visited Indices Analysis', 'NumberTitle','off');
            H = buildOnce(fig, mode, qualHP, hpNames, candidateMatrix);
            setappdata(fig,'VisitedIndicesVizHandles', H);
        end
    end

    % --- Update data only (no deletions) ---
    switch H.mode
        case 1
            for j = 1:numel(H.hpIdx)
                col     = H.hpIdx(j);
                edges   = H.binEdges{j};
                centers = H.binCenters{j};

                hpVals  = candidateMatrix(visitedIndices, col);
                counts  = histcounts(hpVals, edges);
                [~,~,binIdx] = histcounts(hpVals, edges);

                y1 = binMean(CV1, binIdx, numel(centers));
                y2 = binMean(CV2, binIdx, numel(centers));

                % Top histogram
                set(H.hHist{j}, 'XData', centers, 'YData', counts);

                % Bottom grouped bars: update series YData only
                hb = H.hBar{j};   % 1x2 Bar array
                set(hb(1), 'YData', y1(:));
                set(hb(2), 'YData', y2(:));
            end

        case 2
            centers = H.binCenters; edges = H.binEdges;
            counts  = histcounts(visitedIndices, edges);
            [~,~,binIdx] = histcounts(visitedIndices, edges);

            y1 = binMean(CV1, binIdx, numel(centers));
            y2 = binMean(CV2, binIdx, numel(centers));

            set(H.hLeft, 'XData', centers, 'YData', counts);

            hb = H.hRight; % 1x2 Bar array
            set(hb(1), 'YData', y1(:));
            set(hb(2), 'YData', y2(:));
    end

    sgtitle(fig, 'Visited Indices Analysis');
    drawnow limitrate;

    vizHandles = H; % for convenience
end

% ===== helpers =====

function H = buildOnce(fig, mode, qualHP, hpNames, candidateMatrix)
% Create axes, fixed bins, and handles exactly once. Always create grouped bars with 2 series.

    H = struct(); H.mode = mode; H.hpIdx = qualHP;

    if mode == 1
        n = numel(qualHP);
        H.axHist = cell(1,n); H.axBar = cell(1,n);
        H.hHist  = cell(1,n); H.hBar  = cell(1,n);
        H.binEdges = cell(1,n); H.binCenters = cell(1,n);

        for j = 1:n
            col = qualHP(j);
            if isempty(hpNames) || col > numel(hpNames)
                label = sprintf('HP %d', col);
            else
                label = hpNames{col};
            end

            dataAll = candidateMatrix(:,col);
            numBins = 10;
            minVal = min(dataAll); maxVal = max(dataAll);
            if minVal == maxVal
                pad = max(1, max(1e-12, abs(minVal))*0.01); minVal = minVal - pad; maxVal = maxVal + pad;
            end
            edges   = linspace(minVal, maxVal, numBins+1);
            centers = edges(1:end-1) + diff(edges)/2;
            H.binEdges{j}   = edges;
            H.binCenters{j} = centers;

            % Top histogram (start at zeros)
            axH = subplot(2,n,j,'Parent',fig);
            H.axHist{j} = axH;
            H.hHist{j}  = bar(axH, centers, zeros(size(centers)), 'Tag',sprintf('Hist_HP%d',col));
            xlabel(axH, sprintf('%s Value', label)); ylabel(axH,'Frequency');
            title(axH, sprintf('%s: Visited', label));
            xlim(axH,[minVal maxVal]);

            % Bottom grouped bars (2 series fixed)
            axB = subplot(2,n,n+j,'Parent',fig);
            H.axBar{j} = axB;
            YY = zeros(numel(centers),2);
            hb = bar(axB, centers, YY, 'grouped');
            set(hb(1), 'Tag', sprintf('Bar_CV1_HP%d',col));
            set(hb(2), 'Tag', sprintf('Bar_CV2_HP%d',col));
            H.hBar{j} = hb;
            xlabel(axB, sprintf('%s Value', label)); ylabel(axB,'Avg Performance');
            title(axB, sprintf('%s: Avg Cost (CV1) & CV2', label));
            xlim(axB,[minVal maxVal]);
        end

    else
        nCandidates = size(candidateMatrix,1);
        numBins = min(10, max(1, nCandidates));
        edges   = linspace(0.5, nCandidates+0.5, numBins+1);
        centers = edges(1:end-1) + diff(edges)/2;
        H.binEdges = edges; H.binCenters = centers;

        % Left histogram
        H.axLeft = subplot(1,2,1,'Parent',fig);
        H.hLeft  = bar(H.axLeft, centers, zeros(size(centers)), 'Tag','Hist_VisitedIdx');
        xlabel(H.axLeft,'Candidate Index'); ylabel(H.axLeft,'Frequency');
        title(H.axLeft,'Visited Candidate Indices');
        xlim(H.axLeft,[min(centers) max(centers)]);

        % Right grouped bars (2 series fixed)
        H.axRight = subplot(1,2,2,'Parent',fig);
        YY = zeros(numel(centers),2);
        hb = bar(H.axRight, centers, YY, 'grouped');
        set(hb(1), 'Tag','Bar_CV1_Idx'); set(hb(2), 'Tag','Bar_CV2_Idx');
        H.hRight = hb;
        xlabel(H.axRight,'Candidate Index Bin'); ylabel(H.axRight,'Avg Performance');
        title(H.axRight,'Avg Cost (CV1) & CV2 per Bin');
        xlim(H.axRight,[min(centers) max(centers)]);
    end
end

function m = binMean(values, binIdx, K)
% NaN-robust per-bin mean; empty/all-NaN -> 0
    m = zeros(K,1);
    for k = 1:K
        v = values(binIdx==k);
        if isempty(v), m(k)=0; else, mk = mean(v,'omitnan'); if isnan(mk), mk=0; end; m(k)=mk; end
    end
end
