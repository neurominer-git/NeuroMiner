classdef NMImagingColorMapping
% NMImagingColorMapping
% -------------------------------------------------------------------------
% Pure threshold/default and colour-mapping metadata for orthogonal
% imaging. No UI, SPM, file, report, or NM state dependency.
%
% Documentation: docs/NMImagingColorContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function state = defaults(values, measure)
            % defaults  Resolve registered or display-policy threshold and colour defaults.
            %
            % Authority and flow:
            %   Registered metric thresholds remain authoritative. A measure may additionally
            %   declare displayThresholdPolicy='show_all_nonzero', which is a presentation
            %   default only: the declared display domain determines whether one or two signed
            %   controls are exposed, while the threshold is placed immediately around zero.
            %   The current subject vector never supplies an MLI percentile cutoff.
            % Materialization/performance:
            %   O(F) over the already materialized vector for ordinary default statistics; no
            %   cross-subject scan, source read, atlas lookup, or feature-scale copy occurs here.
            % Failure semantics:
            %   Invalid values, display ranges, registered thresholds, or unknown display
            %   threshold policies fail explicitly.
            if nargin < 2 || isempty(measure), measure = struct(); end
            if ~(isnumeric(values) || islogical(values)) || ~isreal(values)
                error('NMImagingColorMapping:InvalidValues', ...
                    'Overlay values must be one real numeric or logical array.');
            end
            x = double(values(:));
            finite = x(isfinite(x));
            neg = finite(finite < 0);
            pos = finite(finite > 0);
            state = struct( ...
                'schema','NMImagingDisplayDefaults', ...
                'schemaVersion',1, ...
                'measureId',NMImagingColorMapping.textField(measure,'measureId',''), ...
                'measureLabel',NMImagingColorMapping.textField(measure,'label',''), ...
                'valuePolarity',NMImagingColorMapping.textField(measure,'valuePolarity','signed'), ...
                'displayRangeMode',NMImagingColorMapping.textField(measure,'displayRangeMode',''), ...
                'thresholdMode','none', ...
                'thresholdLow',NaN, ...
                'thresholdHigh',NaN, ...
                'thresholdValue',NaN, ...
                'thresholdProvenance','percentile_10_90', ...
                'opacity',0.5, ...
                'negativeColorRgb',[0 0 1], ...
                'midpointColorRgb',[1 1 1], ...
                'positiveColorRgb',[1 0 0], ...
                'valueRange',[NaN NaN], ...
                'hasNegative',~isempty(neg), ...
                'hasPositive',~isempty(pos));
            if ~isempty(finite), state.valueRange = [min(finite) max(finite)]; end
            if isstruct(measure) && isfield(measure,'displayValueRange') && ~isempty(measure.displayValueRange)
                declared = double(measure.displayValueRange(:)');
                if numel(declared) ~= 2 || any(~isfinite(declared)) || declared(2) < declared(1)
                    error('NMImagingColorMapping:InvalidDisplayRange','Declared displayValueRange must contain two finite ordered values.');
                end
                state.valueRange = declared;
                state.hasNegative = declared(1) < 0;
                state.hasPositive = declared(2) > 0;
            end

            threshold = NMResultsViewerDisplaySemanticsTools.thresholdFromSpec(struct( ...
                'thresholdMode',lower(strtrim(NMImagingColorMapping.textField(measure,'thresholdMode','none'))), ...
                'thresholdLow',NMImagingColorMapping.scalarField(measure,'thresholdLow',NaN), ...
                'thresholdHigh',NMImagingColorMapping.scalarField(measure,'thresholdHigh',NaN), ...
                'thresholdValue',NMImagingColorMapping.scalarField(measure,'thresholdValue',NaN)));
            if ~strcmp(threshold.mode,'none')
                state.thresholdMode = threshold.mode;
                state.thresholdProvenance = 'registered_metric';
                if isfield(threshold,'lower'), state.thresholdLow = threshold.lower; end
                if isfield(threshold,'upper'), state.thresholdHigh = threshold.upper; end
                if isfield(threshold,'value'), state.thresholdValue = threshold.value; end
                return;
            end

            displayThresholdPolicy = lower(strtrim(NMImagingColorMapping.textField(measure,'displayThresholdPolicy','')));
            if ~isempty(displayThresholdPolicy)
                if ~strcmp(displayThresholdPolicy,'show_all_nonzero')
                    error('NMImagingColorMapping:UnknownDisplayThresholdPolicy', ...
                        'Unknown display threshold policy: %s.',displayThresholdPolicy);
                end
                % eps(0) is the smallest positive IEEE-754 double. The resulting thresholds
                % exclude exact zeros only; every finite non-zero relevance value remains visible.
                zeroEpsilon = eps(0);
                state.thresholdProvenance = 'display_zero_reference';
                if state.hasNegative && state.hasPositive
                    state.thresholdMode = 'outside_interval';
                    state.thresholdLow = -zeroEpsilon;
                    state.thresholdHigh = zeroEpsilon;
                elseif state.hasPositive
                    state.thresholdMode = 'above';
                    state.thresholdValue = zeroEpsilon;
                elseif state.hasNegative
                    state.thresholdMode = 'below';
                    state.thresholdValue = -zeroEpsilon;
                else
                    state.thresholdMode = 'none';
                end
                return;
            end

            if ~isempty(neg) && ~isempty(pos)
                state.thresholdMode = 'outside_interval';
                state.thresholdLow = prctile(neg,10);
                state.thresholdHigh = prctile(pos,90);
            elseif ~isempty(pos)
                state.thresholdMode = 'above';
                state.thresholdValue = prctile(pos,90);
            elseif ~isempty(neg)
                state.thresholdMode = 'below';
                state.thresholdValue = prctile(neg,10);
            else
                state.thresholdMode = 'none';
            end
        end
    end

    methods (Static, Access = private)
        function value = textField(s,name,default)
            value = default;
            if isstruct(s) && isfield(s,name) && ~isempty(s.(name))
                value = char(string(s.(name)));
            end
        end

        function value = scalarField(s,name,default)
            value = default;
            if ~isstruct(s) || ~isfield(s,name) || isempty(s.(name)), return; end
            raw = s.(name);
            if isnumeric(raw) || islogical(raw)
                raw = double(raw(:));
            elseif ischar(raw) || isstring(raw)
                raw = str2double(string(raw(:)));
            else
                raw = [];
            end
            if ~isempty(raw) && isfinite(raw(1)), value = raw(1); end
        end
    end
end
