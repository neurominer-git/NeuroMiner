classdef NMResultsViewerDisplaySemanticsTools
% NMResultsViewerDisplaySemanticsTools  Canonical MATLAB executor for Results Viewer display semantics.
%
% This class executes the serialized browser display contract used by
% NMResultsViewerDisplaySemantics. It owns MATLAB-side threshold inclusion,
% display ranges, colour coordinates, colour interpolation and extrema
% eligibility for reports, exports and direct API consumers. Callers pass
% resolved scientific values and explicit metric/display specifications.

    properties (Constant)
        CONTRACT_VERSION = 'NM-RESULTS-VIEWER-DISPLAY-SEMANTICS-V1'
        REQUEST_VERSION = 'NM-RESULTS-VIEWER-DISPLAY-REQUEST-V1'
        THRESHOLD_MODES = {'none','outside_interval','above_abs','above','below'}
        RANGE_MODES = {'robust_polarity_wise','full_data_range','symmetric_absolute','manual'}
        POLARITIES = {'signed','positive','negative','magnitude'}
        EFFECTIVE_POLARITIES = {'signed','positive','negative','magnitude','none'}
    end

    methods (Static)
        function contract = resolveContract(values, metricSpec, displaySpec, identity)
            % nm2-allow: canonical display executor validates numeric scientific values at its public MATLAB boundary
            if ~(isnumeric(values) || islogical(values))
                error('NMResultsViewerDisplaySemanticsTools:InvalidValues', ...
                    'Display values must be a numeric or logical array.');
            end
            if ~isreal(values)
                error('NMResultsViewerDisplaySemanticsTools:ComplexValue', ...
                    ['Display values are complex. The scientific backend must define ' ...
                     'a real-valued transform before display.']);
            end
            values = double(values(:));
            if any(isinf(values))
                error('NMResultsViewerDisplaySemanticsTools:NonFiniteValue', ...
                    'Display values contain an infinite value.');
            end
            finiteMask = isfinite(values);
            finiteValues = values(finiteMask);
            if isempty(finiteValues)
                error('NMResultsViewerDisplaySemanticsTools:NoFiniteValues', ...
                    'Display values contain no finite real value.');
            end
            NMResultsViewerDisplaySemanticsTools.validateDeclaredRange(metricSpec);
            declaredRange = NMResultsViewerDisplaySemanticsTools.declaredRange(metricSpec);

            theoretical = NMResultsViewerDisplaySemanticsTools.requiredText( ...
                metricSpec,'valuePolarity','Value polarity');
            NMResultsViewerDisplaySemanticsTools.requireMember(theoretical, ...
                NMResultsViewerDisplaySemanticsTools.POLARITIES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidPolarity','Value polarity');

            if isempty(declaredRange)
                exactLower = min(finiteValues);
                exactUpper = max(finiteValues);
            else
                exactLower = declaredRange(1);
                exactUpper = declaredRange(2);
            end
            scale = max([abs(exactLower),abs(exactUpper),1]);
            tolerance = scale * 1e-10;
            hasNegative = exactLower < -tolerance;
            hasPositive = exactUpper > tolerance;
            if hasNegative && hasPositive
                kind = 'signed';
            elseif hasNegative
                kind = 'negative';
            elseif hasPositive
                if strcmp(theoretical,'magnitude'), kind = 'magnitude'; else, kind = 'positive'; end
            elseif strcmp(theoretical,'magnitude')
                kind = 'magnitude';
            else
                kind = 'none';
            end

            threshold = NMResultsViewerDisplaySemanticsTools.resolveThreshold(metricSpec);
            [activeNegative,activePositive,activeCount] = ...
                NMResultsViewerDisplaySemanticsTools.activeRanges(finiteValues,threshold);

            shownMode = 'full_data_range';
            % nm2-allow: display metric projection boundary accepts producer-declared optional range mode
            if isfield(metricSpec,'displayRangeMode') && ~isempty(metricSpec.displayRangeMode)
                shownMode = metricSpec.displayRangeMode;
            end
            % nm2-allow: static and browser display request boundary owns optional range override
            if isfield(displaySpec,'DisplayRangeMode') && ~isempty(displaySpec.DisplayRangeMode)
                shownMode = displaySpec.DisplayRangeMode;
            end
            NMResultsViewerDisplaySemanticsTools.requireMember(shownMode, ...
                NMResultsViewerDisplaySemanticsTools.RANGE_MODES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidRangeMode','Display range mode');
            shownLower = exactLower;
            shownUpper = exactUpper;
            switch shownMode
                case 'full_data_range'
                case 'robust_polarity_wise'
                    if ~isempty(activeNegative) && ~isempty(activePositive)
                        shownLower = NMResultsViewerDisplaySemanticsTools.quantile(activeNegative,0.02);
                        shownUpper = NMResultsViewerDisplaySemanticsTools.quantile(activePositive,0.98);
                    elseif ~isempty(activeNegative)
                        shownLower = NMResultsViewerDisplaySemanticsTools.quantile(activeNegative,0.02);
                        shownUpper = activeNegative(end);
                        if shownUpper == shownLower
                            % A single supra-threshold value (or several equal ones) would
                            % give a zero-width scale: let the scale end at the threshold.
                            shownUpper = min(exactUpper, ...
                                NMResultsViewerDisplaySemanticsTools.thresholdBoundary(threshold,'negative',exactUpper));
                        end
                        if shownUpper == shownLower
                            % All supra-threshold values sit at the threshold: use the exact data range.
                            shownUpper = exactUpper;
                        end
                    elseif ~isempty(activePositive)
                        shownLower = activePositive(1);
                        shownUpper = NMResultsViewerDisplaySemanticsTools.quantile(activePositive,0.98);
                        if shownUpper == shownLower
                            % A single supra-threshold value (or several equal ones) would
                            % give a zero-width scale: let the scale start at the threshold.
                            shownLower = max(exactLower, ...
                                NMResultsViewerDisplaySemanticsTools.thresholdBoundary(threshold,'positive',exactLower));
                        end
                        if shownUpper == shownLower
                            % All supra-threshold values sit at the threshold: use the exact data range.
                            shownLower = exactLower;
                        end
                    end
                case 'symmetric_absolute'
                    maximum = max(abs([exactLower exactUpper]));
                    shownLower = -maximum;
                    shownUpper = maximum;
                case 'manual'
                    shownLower = NMResultsViewerDisplaySemanticsTools.requiredScalar( ...
                        displaySpec,'DisplayRangeLow','Manual display lower bound');
                    shownUpper = NMResultsViewerDisplaySemanticsTools.requiredScalar( ...
                        displaySpec,'DisplayRangeHigh','Manual display upper bound');
                    if ~(shownLower < shownUpper)
                        error('NMResultsViewerDisplaySemanticsTools:InvalidManualRange', ...
                            'Manual display range requires lower < upper.');
                    end
                    if shownLower < exactLower || shownUpper > exactUpper
                        error('NMResultsViewerDisplaySemanticsTools:ManualRangeOutsideData', ...
                            'Manual display range must lie within the exact data range.');
                    end
            end

            opacity = 1;
            % nm2-allow: display presentation request boundary owns optional opacity
            if isfield(displaySpec,'Opacity') && ~isempty(displaySpec.Opacity)
                opacity = NMResultsViewerDisplaySemanticsTools.requiredScalar( ...
                    displaySpec,'Opacity','Opacity');
            end
            if opacity < 0 || opacity > 1
                error('NMResultsViewerDisplaySemanticsTools:InvalidOpacity', ...
                    'Opacity must lie in [0,1].');
            end

            if shownUpper == shownLower
                zeroPosition = 0.5;
            else
                zeroPosition = min(1,max(0,(0-shownLower)/(shownUpper-shownLower)));
            end
            colorStops = NMResultsViewerDisplaySemanticsTools.resolveColorStops( ...
                displaySpec,kind,zeroPosition);

            lowerCount = nnz(activeNegative < shownLower) + nnz(activePositive < shownLower);
            upperCount = nnz(activeNegative > shownUpper) + nnz(activePositive > shownUpper);
            denominator = max(1,activeCount);

            contract = struct();
            contract.contractVersion = NMResultsViewerDisplaySemanticsTools.CONTRACT_VERSION;
            contract.requestVersion = NMResultsViewerDisplaySemanticsTools.REQUEST_VERSION;
            contract.identity = identity;
            contract.valueState = struct('finiteCount',numel(finiteValues), ...
                'missingCount',nnz(isnan(values)));
            contract.polarity = struct('kind',kind,'theoretical',theoretical);
            contract.exactRange = struct('lower',exactLower,'upper',exactUpper, ...
                'constant',exactLower==exactUpper);
            contract.shownRange = struct('mode',shownMode,'lower',shownLower, ...
                'upper',shownUpper,'constant',shownLower==shownUpper);
            contract.clipping = struct('lowerCount',lowerCount,'upperCount',upperCount, ...
                'lowerFraction',lowerCount/denominator,'upperFraction',upperCount/denominator, ...
                'eligibleCount',activeCount);
            contract.threshold = threshold;
            contract.opacity = opacity;
            contract.zeroPosition = zeroPosition;
            contract.colorStops = colorStops;
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
        end

        function classification = classifyValue(value, contract, presence)
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            if ~presence
                classification = struct('state','absent','sign',0);
                return;
            end
            % nm2-allow: display scalar classification boundary validates one numeric scientific value
            if ~(isnumeric(value) || islogical(value)) || ~isscalar(value)
                error('NMResultsViewerDisplaySemanticsTools:InvalidValue', ...
                    'Display value must be one numeric scalar.');
            end
            if ~isreal(value)
                error('NMResultsViewerDisplaySemanticsTools:ComplexValue', ...
                    ['Display value is complex. The scientific backend must define ' ...
                     'a real-valued transform before display.']);
            end
            value = double(value);
            if isnan(value)
                classification = struct('state','missing','sign',0);
                return;
            end
            if ~isfinite(value)
                error('NMResultsViewerDisplaySemanticsTools:NonFiniteValue', ...
                    'Display value is infinite.');
            end
            included = NMResultsViewerDisplaySemanticsTools.thresholdIncludes( ...
                value,contract.threshold);
            if included, state = 'included'; else, state = 'subthreshold'; end
            classification = struct('state',state, ...
                'sign',double(value>0)-double(value<0));
        end

        function mask = eligibilityMask(values, contract, presenceMask)
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            % nm2-allow: display eligibility boundary validates real numeric scientific values
            if ~(isnumeric(values) || islogical(values)) || ~isreal(values)
                error('NMResultsViewerDisplaySemanticsTools:InvalidValues', ...
                    'Display values must be one real numeric or logical array.');
            end
            values = double(values);
            if any(isinf(values(:)))
                error('NMResultsViewerDisplaySemanticsTools:NonFiniteValue', ...
                    'Display values contain an infinite value.');
            end
            % nm2-allow: display eligibility boundary validates the explicit scientific presence axis
            if ~islogical(presenceMask) || ~isequal(size(presenceMask),size(values))
                error('NMResultsViewerDisplaySemanticsTools:InvalidPresenceMask', ...
                    'Presence mask must be logical and match the display-value array.');
            end
            finite = isfinite(values) & presenceMask;
            mask = NMResultsViewerDisplaySemanticsTools.thresholdMask( ...
                values,finite,contract.threshold);
        end

        function classes = classifyArray(values, contract, presenceMask)
            included = NMResultsViewerDisplaySemanticsTools.eligibilityMask( ...
                values,contract,presenceMask);
            values = double(values);
            classes = zeros(size(values),'int8');
            classes(included & values < 0) = -1;
            classes(included & values > 0) = 1;
        end

        function tf = extremaEligible(value, contract, presence)
            classification = NMResultsViewerDisplaySemanticsTools.classifyValue( ...
                value,contract,presence);
            tf = strcmp(classification.state,'included');
        end

        function coordinate = colorCoordinate(value, contract)
            classification = NMResultsViewerDisplaySemanticsTools.classifyValue( ...
                value,contract,true);
            if ~strcmp(classification.state,'included')
                coordinate = NaN;
                return;
            end
            lower = contract.shownRange.lower;
            upper = contract.shownRange.upper;
            if contract.shownRange.constant
                coordinate = 0.5;
            else
                coordinate = min(1,max(0,(double(value)-lower)/(upper-lower)));
            end
        end

        function hex = sampleColorHex(value, contract)
            coordinate = NMResultsViewerDisplaySemanticsTools.colorCoordinate(value,contract);
            if ~isfinite(coordinate)
                error('NMResultsViewerDisplaySemanticsTools:ExcludedColorSample', ...
                    'Colour sampling requires an included display value.');
            end
            hex = NMResultsViewerDisplaySemanticsTools.sampleColorCoordinateHex( ...
                coordinate,contract);
        end

        function colors = sampleColorHexArray(values, contract, excludedColor)
            % One resolved display contract and one color lookup for a graph's edge array.
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            included = NMResultsViewerDisplaySemanticsTools.thresholdMask( ...
                values,isfinite(values),contract.threshold);
            colors = repmat({excludedColor},size(values));
            if ~any(included(:)), return; end
            lower = contract.shownRange.lower;
            upper = contract.shownRange.upper;
            coordinates = 0.5*ones(nnz(included),1);
            if ~contract.shownRange.constant
                coordinates = min(1,max(0,(double(values(included))-lower)/(upper-lower)));
            end
            colors(included) = cellstr(NMResultsViewerDisplaySemanticsTools.interpolateColors(coordinates,contract));
        end

        function hex = sampleColorCoordinateHex(coordinate, contract)
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            % nm2-allow: display colour sampling boundary validates one normalized coordinate
            if ~isnumeric(coordinate) || ~isscalar(coordinate) || ~isreal(coordinate) || ...
                    ~isfinite(coordinate) || coordinate < 0 || coordinate > 1
                error('NMResultsViewerDisplaySemanticsTools:InvalidColorCoordinate', ...
                    'Colour coordinate must be one finite real scalar in [0,1].');
            end
            hex = NMResultsViewerDisplaySemanticsTools.interpolateColors(coordinate,contract);
        end

        function threshold = thresholdFromSpec(spec)
            threshold = NMResultsViewerDisplaySemanticsTools.resolveThreshold(spec);
        end

        function values = thresholdValues(contract)
            NMResultsViewerDisplaySemanticsTools.validateContract(contract);
            threshold = contract.threshold;
            switch threshold.mode
                case 'none'
                    values = [];
                case 'outside_interval'
                    values = [threshold.lower threshold.upper];
                case 'above_abs'
                    values = [-threshold.value threshold.value];
                case {'above','below'}
                    values = threshold.value;
            end
        end

        function validateContract(contract)
            required = {'contractVersion','requestVersion','identity','valueState','polarity', ...
                'exactRange','shownRange','clipping','threshold','opacity', ...
                'zeroPosition','colorStops'};
            NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                contract,required,'Display contract');
            if ~strcmp(contract.contractVersion,NMResultsViewerDisplaySemanticsTools.CONTRACT_VERSION)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Display contract is missing or incompatible.');
            end
            if ~strcmp(contract.requestVersion, ...
                    NMResultsViewerDisplaySemanticsTools.REQUEST_VERSION)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Display request version is incompatible.');
            end
            % nm2-allow: serialized display contract boundary validates scalar identity transport
            if ~isstruct(contract.identity) || ~isscalar(contract.identity)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract identity must be one scalar struct.');
            end
            NMResultsViewerDisplaySemanticsTools.validateCountState(contract.valueState);
            NMResultsViewerDisplaySemanticsTools.validatePolarity(contract.polarity);
            NMResultsViewerDisplaySemanticsTools.validateRange( ...
                contract.exactRange,'exact',{});
            NMResultsViewerDisplaySemanticsTools.validateRange( ...
                contract.shownRange,'shown',NMResultsViewerDisplaySemanticsTools.RANGE_MODES);
            NMResultsViewerDisplaySemanticsTools.validateClipping(contract.clipping);
            NMResultsViewerDisplaySemanticsTools.validateResolvedThreshold(contract.threshold);
            % nm2-allow: serialized display contract boundary validates opacity geometry
            if ~isnumeric(contract.opacity) || ~isscalar(contract.opacity) || ...
                    ~isreal(contract.opacity) || ~isfinite(contract.opacity) || ...
                    contract.opacity < 0 || contract.opacity > 1
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract opacity is invalid.');
            end
            % nm2-allow: serialized display contract boundary validates zero-position geometry
            if ~isnumeric(contract.zeroPosition) || ~isscalar(contract.zeroPosition) || ...
                    ~isreal(contract.zeroPosition) || ~isfinite(contract.zeroPosition) || ...
                    contract.zeroPosition < 0 || contract.zeroPosition > 1
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract zero position is invalid.');
            end
            NMResultsViewerDisplaySemanticsTools.validateColorStops(contract.colorStops);
            expectedZero = 0.5;
            if ~contract.shownRange.constant
                expectedZero = min(1,max(0,(0-contract.shownRange.lower) / ...
                    (contract.shownRange.upper-contract.shownRange.lower)));
            end
            if abs(contract.zeroPosition-expectedZero) > 1e-12
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract zero position is inconsistent with the shown range.');
            end
        end
    end

    methods (Static, Access = private)
        function range = declaredRange(metricSpec)
            % declaredRange  Resolve an explicit display domain from the metric authority without deriving it from current values.
            % Failure semantics: nonnumeric declarations fail rather than being coerced from text; callers validate geometry/order.
            range=[];raw=[];
            % nm2-allow: display metric projection boundary accepts imaging valueRange or Results Viewer displayValueRange
            if isfield(metricSpec,'valueRange') && ~isempty(metricSpec.valueRange)
                raw=metricSpec.valueRange;
            % nm2-allow: display metric projection boundary accepts imaging valueRange or Results Viewer displayValueRange
            elseif isfield(metricSpec,'displayValueRange') && ~isempty(metricSpec.displayValueRange)
                raw=metricSpec.displayValueRange;
            end
            if isempty(raw),return;end
            range=raw(:)';
        end

        function validateDeclaredRange(metricSpec)
            range = NMResultsViewerDisplaySemanticsTools.declaredRange(metricSpec);
            if isempty(range), return; end
            % nm2-allow: producer-declared display range boundary validates two finite scientific bounds
            if ~isnumeric(range) || numel(range) ~= 2 || ~isreal(range) || ...
                    any(~isfinite(range(:)))
                error('NMResultsViewerDisplaySemanticsTools:InvalidDeclaredRange', ...
                    'Declared valueRange must contain exactly two finite real values.');
            end
            range = double(range(:));
            if range(2) < range(1)
                error('NMResultsViewerDisplaySemanticsTools:ReversedDeclaredRange', ...
                    'Declared valueRange is reversed.');
            end
        end

        function [negative,positive,activeCount] = activeRanges(finiteValues,threshold)
            negative = sort(finiteValues(finiteValues < 0));
            positive = sort(finiteValues(finiteValues > 0));
            zeroCount = nnz(finiteValues == 0);
            switch threshold.mode
                case 'none'
                    activeCount = numel(negative)+numel(positive)+zeroCount;
                case 'outside_interval'
                    negative = negative(negative <= threshold.lower);
                    positive = positive(positive >= threshold.upper);
                    activeCount = numel(negative)+numel(positive);
                case 'above_abs'
                    negative = negative(negative <= -threshold.value);
                    positive = positive(positive >= threshold.value);
                    activeCount = numel(negative)+numel(positive);
                case 'above'
                    negative = negative([]);
                    positive = positive(positive >= threshold.value);
                    activeCount = numel(positive);
                case 'below'
                    negative = negative(negative <= threshold.value);
                    positive = positive([]);
                    activeCount = numel(negative);
            end
        end

        function mask = thresholdMask(values,finite,threshold)
            switch threshold.mode
                case 'none'
                    mask = finite;
                case 'outside_interval'
                    mask = finite & (values <= threshold.lower | values >= threshold.upper);
                case 'above_abs'
                    mask = finite & abs(values) >= threshold.value;
                case 'above'
                    mask = finite & values >= threshold.value;
                case 'below'
                    mask = finite & values <= threshold.value;
            end
        end

        function value = thresholdBoundary(threshold,side,unthresholdedValue)
            % Threshold value that bounds the active values on one side of zero.
            % Without a threshold, the caller's exact-range bound applies.
            switch threshold.mode
                case 'outside_interval'
                    if strcmp(side,'positive'), value = threshold.upper; else, value = threshold.lower; end
                case 'above_abs'
                    if strcmp(side,'positive'), value = threshold.value; else, value = -threshold.value; end
                case {'above','below'}
                    value = threshold.value;
                case 'none'
                    value = unthresholdedValue;
            end
        end

        function threshold = resolveThreshold(spec)
            mode = NMResultsViewerDisplaySemanticsTools.requiredText(spec,'thresholdMode','Threshold mode');
            NMResultsViewerDisplaySemanticsTools.requireMember(mode, ...
                NMResultsViewerDisplaySemanticsTools.THRESHOLD_MODES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidThresholdMode','Threshold mode');
            switch mode
                case 'outside_interval'
                    lower = NMResultsViewerDisplaySemanticsTools.requiredScalar(spec,'thresholdLow','Threshold lower bound');
                    upper = NMResultsViewerDisplaySemanticsTools.requiredScalar(spec,'thresholdHigh','Threshold upper bound');
                    if ~(lower < upper)
                        error('NMResultsViewerDisplaySemanticsTools:InvalidThresholdInterval', ...
                            'outside_interval requires finite ordered thresholds.');
                    end
                    threshold = struct('mode',mode,'lower',lower,'upper',upper);
                case 'above_abs'
                    value = NMResultsViewerDisplaySemanticsTools.requiredScalar(spec,'thresholdValue','Threshold value');
                    if value < 0
                        error('NMResultsViewerDisplaySemanticsTools:InvalidAbsoluteThreshold', ...
                            'above_abs requires a finite non-negative threshold.');
                    end
                    threshold = struct('mode',mode,'value',value);
                case {'above','below'}
                    value = NMResultsViewerDisplaySemanticsTools.requiredScalar(spec,'thresholdValue','Threshold value');
                    threshold = struct('mode',mode,'value',value);
                case 'none'
                    threshold = struct('mode',mode);
            end
        end

        function validateResolvedThreshold(threshold)
            mode = threshold.mode;
            NMResultsViewerDisplaySemanticsTools.requireMember(mode, ...
                NMResultsViewerDisplaySemanticsTools.THRESHOLD_MODES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidThresholdMode','Threshold mode');
            switch mode
                case 'outside_interval'
                    NMResultsViewerDisplaySemanticsTools.requireExactFields(threshold,{'mode','lower','upper'},'Resolved threshold');
                    lower=threshold.lower; upper=threshold.upper;
                    % nm2-allow: fixed resolved-threshold contract validates finite interval geometry
                    if ~(NMResultsViewerDisplaySemanticsTools.isFiniteRealScalar(lower) && ...
                            NMResultsViewerDisplaySemanticsTools.isFiniteRealScalar(upper) && lower<upper)
                        error('NMResultsViewerDisplaySemanticsTools:InvalidThresholdInterval', ...
                            'outside_interval requires finite ordered thresholds.');
                    end
                case {'above_abs','above','below'}
                    NMResultsViewerDisplaySemanticsTools.requireExactFields(threshold,{'mode','value'},'Resolved threshold');
                    value=threshold.value;
                    % nm2-allow: fixed resolved-threshold contract validates one finite threshold value
                    if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
                        error('NMResultsViewerDisplaySemanticsTools:InvalidThreshold', ...
                            'Resolved threshold value must be one finite real scalar.');
                    end
                    if strcmp(mode,'above_abs') && value<0
                        error('NMResultsViewerDisplaySemanticsTools:InvalidAbsoluteThreshold', ...
                            'above_abs requires a finite non-negative threshold.');
                    end
                case 'none'
                    NMResultsViewerDisplaySemanticsTools.requireExactFields(threshold,{'mode'},'Resolved threshold');
            end
        end

        function tf = thresholdIncludes(value, threshold)
            switch threshold.mode
                case 'none'
                    tf = true;
                case 'outside_interval'
                    tf = value <= threshold.lower || value >= threshold.upper;
                case 'above_abs'
                    tf = abs(value) >= threshold.value;
                case 'above'
                    tf = value >= threshold.value;
                case 'below'
                    tf = value <= threshold.value;
            end
        end

        function stops = resolveColorStops(displaySpec,kind,zeroPosition)
            % nm2-allow: display presentation request boundary owns optional explicit colour stops
            if isfield(displaySpec,'ColorStops') && ~isempty(displaySpec.ColorStops)
                stops = displaySpec.ColorStops;
                NMResultsViewerDisplaySemanticsTools.validateColorStops(stops);
                return;
            end
            negative = NMResultsViewerDisplaySemanticsTools.colorField( ...
                displaySpec,'NegativeColor','#2563eb');
            midpoint = NMResultsViewerDisplaySemanticsTools.colorField( ...
                displaySpec,'MidpointColor','#ffffff');
            positive = NMResultsViewerDisplaySemanticsTools.colorField( ...
                displaySpec,'PositiveColor','#dc2626');
            switch kind
                case 'negative'
                    stops = struct('position',{0,1},'color',{negative,midpoint});
                case {'positive','magnitude','none'}
                    stops = struct('position',{0,1},'color',{midpoint,positive});
                case 'signed'
                    stops = struct('position',{0,zeroPosition,1}, ...
                        'color',{negative,midpoint,positive});
            end
            NMResultsViewerDisplaySemanticsTools.validateColorStops(stops);
        end

        function validateColorStops(stops)
            % nm2-allow: display presentation contract boundary validates bounded colour-stop cardinality
            if ~isstruct(stops) || numel(stops) < 2 || numel(stops) > 10
                error('NMResultsViewerDisplaySemanticsTools:InvalidColorStopCount', ...
                    'Colour stops must contain 2 to 10 struct entries.');
            end
            previous = -Inf;
            for ii = 1:numel(stops)
                NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                    stops(ii),{'position','color'},sprintf('Colour stop %d',ii));
                % nm2-allow: display contract boundary validates colour-stop numeric geometry
                if ~isnumeric(stops(ii).position) || ...
                        ~isscalar(stops(ii).position) || ...
                        ~isreal(stops(ii).position) || ...
                        ~isfinite(stops(ii).position) || ...
                        stops(ii).position < 0 || stops(ii).position > 1
                    error('NMResultsViewerDisplaySemanticsTools:InvalidColorStop', ...
                        'Colour stop %d position must lie in [0,1].',ii);
                end
                if ~(stops(ii).position > previous)
                    error('NMResultsViewerDisplaySemanticsTools:UnorderedColorStops', ...
                        'Colour-stop positions must be strictly increasing.');
                end
                previous = stops(ii).position;
                NMResultsViewerDisplaySemanticsTools.requireHex( ...
                    stops(ii).color,sprintf('Colour stop %d',ii));
            end
        end

        function validateCountState(state)
            NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                state,{'finiteCount','missingCount'},'Contract value state');
            if ~NMResultsViewerDisplaySemanticsTools.isNonnegativeInteger(state.finiteCount) || ...
                    ~NMResultsViewerDisplaySemanticsTools.isNonnegativeInteger(state.missingCount)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract value-state counts are invalid.');
            end
        end

        function validatePolarity(polarity)
            NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                polarity,{'kind','theoretical'},'Contract polarity');
            NMResultsViewerDisplaySemanticsTools.requireMember( ...
                polarity.kind, ...
                NMResultsViewerDisplaySemanticsTools.EFFECTIVE_POLARITIES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidContract','Effective polarity');
            NMResultsViewerDisplaySemanticsTools.requireMember( ...
                polarity.theoretical, ...
                NMResultsViewerDisplaySemanticsTools.POLARITIES, ...
                'NMResultsViewerDisplaySemanticsTools:InvalidContract','Theoretical polarity');
        end

        function validateRange(range,label,allowedModes)
            if isempty(allowedModes)
                expected={'lower','upper','constant'};
            else
                expected={'mode','lower','upper','constant'};
            end
            NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                range,expected,sprintf('Contract %s range',label));
            % nm2-allow: display contract boundary validates numeric range geometry and scalar flags
            if ~NMResultsViewerDisplaySemanticsTools.isFiniteRealScalar(range.lower) || ...
                    ~NMResultsViewerDisplaySemanticsTools.isFiniteRealScalar(range.upper) || ...
                    range.upper < range.lower || ...
                    ~NMResultsViewerDisplaySemanticsTools.isBooleanScalar(range.constant) || ...
                    logical(range.constant) ~= (range.upper == range.lower)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract %s range is invalid.',label);
            end
            if ~isempty(allowedModes)
                NMResultsViewerDisplaySemanticsTools.requireMember( ...
                    range.mode,allowedModes, ...
                    'NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Display range mode');
            end
        end

        function validateClipping(clipping)
            names = {'lowerCount','upperCount','eligibleCount'};
            NMResultsViewerDisplaySemanticsTools.requireExactFields( ...
                clipping,{'lowerCount','upperCount','lowerFraction','upperFraction','eligibleCount'}, ...
                'Contract clipping state');
            for ii=1:numel(names)
                if ~NMResultsViewerDisplaySemanticsTools.isNonnegativeInteger(clipping.(names{ii}))
                    error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                        'Contract clipping count %s is invalid.',names{ii});
                end
            end
            for name={'lowerFraction','upperFraction'}
                field=name{1};
                % nm2-allow: display contract boundary validates numeric clipping fractions
                if ~isnumeric(clipping.(field)) || ~isscalar(clipping.(field)) || ...
                        ~isreal(clipping.(field)) || ~isfinite(clipping.(field)) || ...
                        clipping.(field) < 0 || clipping.(field) > 1
                    error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                        'Contract clipping fraction %s is invalid.',field);
                end
            end
            if clipping.lowerCount > clipping.eligibleCount || ...
                    clipping.upperCount > clipping.eligibleCount
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract clipping counts exceed the eligible value count.');
            end
            denominator=max(1,double(clipping.eligibleCount));
            if abs(double(clipping.lowerFraction)-double(clipping.lowerCount)/denominator) > 1e-12 || ...
                    abs(double(clipping.upperFraction)-double(clipping.upperCount)/denominator) > 1e-12
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    'Contract clipping fractions are inconsistent with clipping counts.');
            end
        end

        function tf = isNonnegativeInteger(value)
            % nm2-allow: fixed display contract boundary validates nonnegative integer count fields
            tf = isnumeric(value) && isscalar(value) && isreal(value) && ...
                isfinite(value) && value >= 0 && value == floor(value);
        end

        function tf = isFiniteRealScalar(value)
            % nm2-allow: fixed display contract boundary validates finite real scalar fields
            tf=isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
        end

        function tf = isBooleanScalar(value)
            % nm2-allow: fixed display contract boundary validates logical-or-zero-one scalar fields
            tf=islogical(value) && isscalar(value);
            if ~tf
                % nm2-allow: fixed display contract boundary accepts numeric zero-one scalar flags
                tf=isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value) && any(value==[0 1]);
            end
        end

        function value = quantile(sortedValues, probability)
            values = double(sortedValues(:));
            if isempty(values), value = NaN; return; end
            if any(~isfinite(values)) || any(diff(values) < 0)
                error('NMResultsViewerDisplaySemanticsTools:InvalidQuantileValues', ...
                    'Quantile values must be finite and sorted in ascending order.');
            end
            % nm2-allow: internal quantile executor validates its scalar probability argument
            if ~isnumeric(probability) || ~isscalar(probability) || ...
                    ~isfinite(probability) || probability < 0 || probability > 1
                error('NMResultsViewerDisplaySemanticsTools:InvalidQuantile', ...
                    'Quantile probability must lie in [0,1].');
            end
            position = probability * (numel(values)-1) + 1;
            lower = floor(position); upper = ceil(position); fraction = position-lower;
            value = values(lower) + (values(upper)-values(lower))*fraction;
        end

        function requireExactFields(value,expected,label)
            % nm2-allow: fixed display contract boundary validates exact scalar struct schemas
            if ~isstruct(value) || ~isscalar(value)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    '%s must be one scalar struct.',label);
            end
            actual=sort(fieldnames(value));
            required=sort(expected(:));
            if ~isequal(actual,required)
                error('NMResultsViewerDisplaySemanticsTools:InvalidContract', ...
                    '%s fields must be exactly: %s.',label,strjoin(expected,', '));
            end
        end

        function value = requiredText(s,field,label)
            value = s.(field);
            if isempty(value)
                error('NMResultsViewerDisplaySemanticsTools:MissingField', ...
                    '%s is required.',label);
            end
        end

        function value = requiredScalar(s,field,label)
            value=s.(field);
            % nm2-allow: display specification boundary validates required scalar request values
            if ~isnumeric(value) || isempty(value) || ~isscalar(value) || ...
                    ~isreal(value) || ~isfinite(value)
                error('NMResultsViewerDisplaySemanticsTools:MissingField', ...
                    '%s must be a finite real scalar.',label);
            end
            value = double(value);
        end

        function requireMember(value,allowed,code,label)
            if ~any(strcmp(value,allowed))
                error(code,'%s must be one of: %s.',label,strjoin(allowed,', '));
            end
        end

        function color = colorField(s,field,fallback)
            % nm2-allow: display presentation request boundary owns optional colour overrides
            if isfield(s,field) && ~isempty(s.(field))
                color = s.(field);
            else
                color = fallback;
            end
            NMResultsViewerDisplaySemanticsTools.requireHex(color,field);
            color = lower(color);
        end

        function requireHex(color,label)
            if isempty(regexp(color,'^#[0-9A-Fa-f]{6}$','once'))
                error('NMResultsViewerDisplaySemanticsTools:InvalidColor', ...
                    '%s must be a six-digit hexadecimal colour.',label);
            end
        end

        function hex = interpolateColors(coordinate,contract)
            % Internal vector renderer: callers have validated the display contract.
            stops = contract.colorStops;
            stopRgb = zeros(numel(stops),3);
            for ii = 1:numel(stops)
                color = stops(ii).color;
                stopRgb(ii,:) = [hex2dec(color(2:3)),hex2dec(color(4:5)),hex2dec(color(6:7))] / 255;
            end
            p = min(stops(end).position,max(stops(1).position,double(coordinate(:))));
            rgb = interp1([stops.position],stopRgb,p,'linear');
            channels = round(255*min(1,max(0,rgb)));
            hex = reshape(sprintf('#%02x%02x%02x',channels.'),7,[]).';
        end
    end
end
