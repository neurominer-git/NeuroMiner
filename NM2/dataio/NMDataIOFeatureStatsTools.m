classdef NMDataIOFeatureStatsTools
% NMDataIOFeatureStatsTools
% -------------------------------------------------------------------------
% Commit-time feature and case-completeness summaries for DataIO imports.
%
% Scope:
%   - compute numeric matrix descriptives once during import commit;
%   - compute large in-memory matrices in feature chunks at import/probe time
%     and during explicit overview refreshes while the container is in memory;
%   - return plain metadata structs that can be cached in
%     NM.datadescriptor{i}.input_settings.modalityInfo.featureStats.
% -------------------------------------------------------------------------

    methods (Static)
        function stats = emptyStats()
            % emptyStats  Create the fixed-schema empty feature-statistics structure.
            %
            % No required inputs -> stats.
            % It runs during commit/overview generation and caches bounded statistics rather than recomputing them during UI refresh.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            stats = struct();
            stats.schemaVersion = 1;
            stats.createdBy = 'NMDataIOFeatureStatsTools';
            stats.computedAt = '';
            stats.computed = false;
            stats.skipped = false;
            stats.skipReason = '';
            stats.maxStatElements = Inf;
            stats.nCases = NaN;
            stats.nFeatures = NaN;
            stats.nElements = NaN;
            stats.matrixClass = '';
            stats.missingnessKnown = false;
            stats.hasNaN = [];
            stats.nNaN = NaN;
            stats.nanFraction = NaN;
            stats.hasInf = [];
            stats.nInf = NaN;
            stats.infFraction = NaN;
            stats.hasNonFinite = [];
            stats.nNonFinite = NaN;
            stats.nonFiniteFraction = NaN;
            stats.nCompleteCases = NaN;
            stats.nPartialMissingCases = NaN;
            stats.nAllNaNCases = NaN;
            stats.nFeaturesWithNaN = NaN;
            stats.nAllNaNFeatures = NaN;
            stats.nConstantFeatures = NaN;
            stats.nFiniteFeatures = NaN;
            stats.featureMeanMin = NaN;
            stats.featureMeanMax = NaN;
            stats.featureSDMin = NaN;
            stats.featureSDMax = NaN;
        end

        function stats = computeFromMatrix(Y, opts)
            % computeFromMatrix  Compute bounded feature/case descriptive statistics from a numeric data matrix.
            %
            % Y, opts -> stats.
            % It runs during commit/overview generation and caches bounded statistics rather than recomputing them during UI refresh.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % opts.MaxFeatureStatsChunkElements: configures optional max feature stats chunk elements behavior for this call.
            if nargin < 2 || isempty(opts), opts = struct(); end
            stats = NMDataIOFeatureStatsTools.emptyStats();
            stats.maxStatElements = NMDataIOFeatureStatsTools.maxStatElements(opts);

            if isempty(Y)
                stats = NMDataIOFeatureStatsTools.skippedStats(0, 0, 'Matrix is empty.', stats.maxStatElements, class(Y));
                return;
            end
            if ~(isnumeric(Y) || islogical(Y))
                stats = NMDataIOFeatureStatsTools.skippedStats(NaN, NaN, sprintf('Unsupported matrix class: %s.', class(Y)), stats.maxStatElements, class(Y));
                return;
            end

            nCases = double(size(Y,1));
            if ismatrix(Y)
                nFeatures = double(size(Y,2));
            else
                sz = size(Y);
                nFeatures = double(prod(sz(2:end)));
            end
            nElements = double(numel(Y));
            stats.nCases = nCases;
            stats.nFeatures = nFeatures;
            stats.nElements = nElements;
            stats.matrixClass = class(Y);

            M = reshape(Y, size(Y,1), []);
            nElem = double(numel(M));
            nCase = size(M,1);
            nFeat = size(M,2);
            chunkElements = 5e6;
            if isstruct(opts) && isfield(opts,'MaxFeatureStatsChunkElements') && ~isempty(opts.MaxFeatureStatsChunkElements)
                chunkElements = double(opts.MaxFeatureStatsChunkElements);
            end
            if ~isfinite(chunkElements) || chunkElements <= 0
                chunkElements = 5e6;
            end
            colsPerChunk = max(1, floor(chunkElements / max(1,nCase)));

            stats.computed = true;
            stats.skipped = false;
            stats.skipReason = '';
            stats.computedAt = datestr(now, 30);
            stats.missingnessKnown = true;

            byCaseNaN = zeros(nCase, 1);
            nNaN = 0;
            nInf = 0;
            nNonFinite = 0;
            nFeaturesWithNaN = 0;
            nAllNaNFeatures = 0;
            nConstantFeatures = 0;
            nFiniteFeatures = 0;
            featureMeanMin = Inf;
            featureMeanMax = -Inf;
            featureSDMin = Inf;
            featureSDMax = -Inf;

            for c1 = 1:colsPerChunk:nFeat
                c2 = min(nFeat, c1 + colsPerChunk - 1);
                C = double(M(:, c1:c2));
                nanMask = isnan(C);
                infMask = isinf(C);
                finiteMask = isfinite(C);
                nonFiniteMask = nanMask | infMask;

                nNaN = nNaN + double(nnz(nanMask));
                nInf = nInf + double(nnz(infMask));
                nNonFinite = nNonFinite + double(nnz(nonFiniteMask));
                byCaseNaN = byCaseNaN + double(sum(nanMask, 2));

                byFeatNaN = sum(nanMask, 1);
                nFeaturesWithNaN = nFeaturesWithNaN + double(nnz(byFeatNaN > 0));
                nAllNaNFeatures = nAllNaNFeatures + double(nnz(byFeatNaN == nCase));

                nFiniteByFeature = sum(finiteMask, 1);
                nFiniteFeatures = nFiniteFeatures + double(nnz(nFiniteByFeature > 0));

                minC = C;
                minC(~finiteMask) = Inf;
                maxC = C;
                maxC(~finiteMask) = -Inf;
                featMin = min(minC, [], 1);
                featMax = max(maxC, [], 1);
                validFinite = nFiniteByFeature > 0;
                nConstantFeatures = nConstantFeatures + double(nnz(validFinite & featMin == featMax));

                sumC = C;
                sumC(~finiteMask) = 0;
                featSum = sum(sumC, 1);
                featSumSq = sum(sumC.^2, 1);
                featMean = featSum ./ max(1, nFiniteByFeature);
                featMean(~validFinite) = NaN;
                denom = max(1, nFiniteByFeature - 1);
                variance = (featSumSq - (featSum.^2 ./ max(1, nFiniteByFeature))) ./ denom;
                variance(variance < 0) = 0;
                featSD = sqrt(variance);
                featSD(~validFinite) = NaN;

                validMean = featMean(~isnan(featMean));
                validSD = featSD(~isnan(featSD));
                if ~isempty(validMean)
                    featureMeanMin = min(featureMeanMin, double(min(validMean)));
                    featureMeanMax = max(featureMeanMax, double(max(validMean)));
                end
                if ~isempty(validSD)
                    featureSDMin = min(featureSDMin, double(min(validSD)));
                    featureSDMax = max(featureSDMax, double(max(validSD)));
                end
            end

            stats.hasNaN = nNaN > 0;
            stats.nNaN = nNaN;
            stats.nanFraction = stats.nNaN / max(1, nElem);
            stats.hasInf = nInf > 0;
            stats.nInf = nInf;
            stats.infFraction = stats.nInf / max(1, nElem);
            stats.hasNonFinite = nNonFinite > 0;
            stats.nNonFinite = nNonFinite;
            stats.nonFiniteFraction = stats.nNonFinite / max(1, nElem);
            stats.nAllNaNCases = double(nnz(byCaseNaN == nFeat));
            stats.nPartialMissingCases = double(nnz(byCaseNaN > 0 & byCaseNaN < nFeat));
            stats.nCompleteCases = double(nnz(byCaseNaN == 0));
            stats.nFeaturesWithNaN = nFeaturesWithNaN;
            stats.nAllNaNFeatures = nAllNaNFeatures;
            stats.nFiniteFeatures = nFiniteFeatures;
            stats.nConstantFeatures = nConstantFeatures;
            if isfinite(featureMeanMin), stats.featureMeanMin = featureMeanMin; end
            if isfinite(featureMeanMax), stats.featureMeanMax = featureMeanMax; end
            if isfinite(featureSDMin), stats.featureSDMin = featureSDMin; end
            if isfinite(featureSDMax), stats.featureSDMax = featureSDMax; end
        end

        function info = applyToInfo(info, Y, opts)
            % applyToInfo  Attach computed feature statistics to a modality-info structure used by overview rendering.
            %
            % Consumes info, Y, opts; returns info.
            % It runs during commit/overview generation and caches bounded statistics rather than recomputing them during UI refresh.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 3 || isempty(opts), opts = struct(); end
            stats = NMDataIOFeatureStatsTools.computeFromMatrix(Y, opts);
            info.featureStats = stats;
            info.nSubjects = stats.nCases;
            info.nFeatures = stats.nFeatures;
            info.matrixClass = stats.matrixClass;
            if stats.computed
                info.hasNaN = stats.hasNaN;
                info.nNaN = stats.nNaN;
                info.nanFraction = stats.nanFraction;
                info.hasInf = stats.hasInf;
                info.nInf = stats.nInf;
                info.infFraction = stats.infFraction;
                info.hasNonFinite = stats.hasNonFinite;
                info.nNonFinite = stats.nNonFinite;
                info.nonFiniteFraction = stats.nonFiniteFraction;
                info.nSubjectsWithNaN = stats.nAllNaNCases + stats.nPartialMissingCases;
                info.nFeaturesWithNaN = stats.nFeaturesWithNaN;
                info.nAlignedCases = stats.nCases;
                info.nObservedCases = max(0, stats.nCases - stats.nAllNaNCases);
                info.maxNaNBySubject = NaN;
                info.maxNaNByFeature = NaN;
                info.missingnessKnown = true;
            else
                info.hasNaN = [];
                info.nNaN = NaN;
                info.nanFraction = NaN;
                info.hasInf = [];
                info.nInf = NaN;
                info.infFraction = NaN;
                info.hasNonFinite = [];
                info.nNonFinite = NaN;
                info.nonFiniteFraction = NaN;
                info.nSubjectsWithNaN = NaN;
                info.nFeaturesWithNaN = NaN;
                info.nAlignedCases = stats.nCases;
                info.nObservedCases = NaN;
                info.maxNaNBySubject = NaN;
                info.maxNaNByFeature = NaN;
                info.missingnessKnown = false;
            end
        end

        function stats = skippedStats(nCases, nFeatures, reason, maxStatElements, matrixClass)
            % skippedStats  Return a fixed-schema statistics payload explaining why expensive feature stats were skipped.
            %
            % Consumes nCases, nFeatures, reason, maxStatElements, matrixClass; returns stats.
            % It runs during commit/overview generation and caches bounded statistics rather than recomputing them during UI refresh.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            if nargin < 4 || isempty(maxStatElements), maxStatElements = 1e7; end
            if nargin < 5, matrixClass = ''; end
            stats = NMDataIOFeatureStatsTools.emptyStats();
            stats.computedAt = datestr(now, 30);
            stats.computed = false;
            stats.skipped = true;
            stats.skipReason = char(reason);
            stats.maxStatElements = double(maxStatElements);
            stats.nCases = double(nCases);
            stats.nFeatures = double(nFeatures);
            if ~isnan(stats.nCases) && ~isnan(stats.nFeatures)
                stats.nElements = stats.nCases * stats.nFeatures;
            end
            stats.matrixClass = char(matrixClass);
        end

        function maxElements = maxStatElements(opts)
            % maxStatElements  Resolve the configured upper bound for feature-statistics computation.
            %
            % Opts -> maxElements.
            % It runs during commit/overview generation and caches bounded statistics rather than recomputing them during UI refresh.
            % It preserves existing DataIO invariants and does not silently reinterpret source semantics.
            %
            % opts.MaxScanElements: configures optional max scan elements behavior for this call.
            % opts.MaxStatElements: configures optional max stat elements behavior for this call.
            maxElements = Inf;
            if isstruct(opts) && isfield(opts,'MaxStatElements') && ~isempty(opts.MaxStatElements)
                maxElements = double(opts.MaxStatElements);
            elseif isstruct(opts) && isfield(opts,'MaxScanElements') && ~isempty(opts.MaxScanElements)
                maxElements = double(opts.MaxScanElements);
            end
            if ~isfinite(maxElements) || maxElements <= 0
                maxElements = Inf;
            end
        end
    end
end
