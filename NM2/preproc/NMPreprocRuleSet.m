classdef NMPreprocRuleSet < handle
% NMPreprocRuleSet
% -------------------------------------------------------------------------
% Central dependency and availability grammar for NeuroMiner preprocessing
% pipelines. This class is intentionally independent of the CLI, browser UI,
% and programmatic API: all three surfaces call the same rule set.
%
% Developer guide
% -------------------------------------------------------------------------
% NMPreprocRuleSet defines the canonical rules that determine where a
% preprocessing module may appear in a pipeline, whether a module should
% automatically add a companion module, and whether parent/child modules
% should move or be deleted together. The rule set is deliberately small:
% modules should expose their own parameter UI in the module class, whereas
% this class should only encode pipeline-level grammar.
%
% The rule set is consumed in two places:
%   1. MATLAB-side validation and programmatic editing of NMPreprocSequence
%      objects, using methods such as isAvailable(), validateSequence(),
%      removalIndices(), blockIndices() and autoChildSteps().
%   2. Browser-side interactive UI logic. NMPreprocUI receives the exported
%      rule specification and mirrors the same decisions for live insertion,
%      movement, deletion and warning messages. If a new rule field is added
%      here, NMPreprocUI usually also needs to know how to interpret it.
%
% Basic rule structure
% -------------------------------------------------------------------------
% A rule is created with obj.rule(moduleId,label) and then modified before it
% is registered with obj.addRule(rule). The default rule contains three main
% fields: addable, availability and sequence.
%
%   r.addable
%       true  : the module may be newly added through the modular system.
%       false : existing imported legacy steps may be preserved, but the
%               module is not offered as a new addable module unless the
%               context explicitly allows unported modules.
%
%   r.availability
%       Context-dependent availability gates. Examples are hasCovars,
%       isImaging, hasNaNsInPredictors, hasJuSpaceDir or isDev. These rules
%       decide whether the module can be inserted in the current modality,
%       stage and NeuroMiner workspace context.
%
%   r.sequence
%       Local grammar for producer/consumer relationships between adjacent
%       preprocessing modules. These rules do not configure module parameters;
%       they only describe sequence legality and parent/child behaviour.
%
% Sequence-rule fields
% -------------------------------------------------------------------------
% The sequence fields should be read directionally. In particular, parent ->
% child behaviour is not the same as child -> parent behaviour. Do not use a
% single flag to encode both directions.
%
%   produces
%       Cell array of abstract objects produced by this module for downstream
%       modules. Example: rankfeat produces {'featureRanking'}; reducedim and
%       remvarcomp produce {'dimensionModel'}. This is primarily descriptive
%       metadata and can be used by validators and UIs.
%
%   consumes
%       Cell array of abstract objects consumed by this module. Example:
%       extfeat consumes {'featureRanking'}; extdim consumes
%       {'dimensionModel'}. This documents that the module expects a suitable
%       upstream producer.
%
%   autoAddChild
%       Convenience insertion. When the parent module is added, the UI/API may
%       automatically insert the named child module immediately afterwards.
%       This does not by itself make the child mandatory. Use it for common
%       producer/consumer pairs where the child is usually needed.
%
%       Example:
%           reducedim.sequence.autoAddChild = 'extdim';
%           remvarcomp.sequence.autoAddChild = 'extdim';
%
%       Adding reducedim/remvarcomp inserts extdim as a convenience child. The
%       child can still be removable if deleteWithParent is false in the child
%       rule.
%
%   requiresImmediatePreviousAny
%       Child legality. The module is valid only if the immediately preceding
%       module is one of the listed parent module IDs. This is the usual way
%       to express that a child module consumes a producer output from the
%       previous step.
%
%       Example:
%           extdim.sequence.requiresImmediatePreviousAny = ...
%               {'reducedim','remvarcomp'};
%
%       This means extdim is valid after reducedim or remvarcomp, but not after
%       unrelated modules or after an intervening preprocessing step.
%
%   mustBeFollowedBy
%       Hard parent legality. The parent module is valid only if the next
%       module is the specified child. Use this only for true hard pairs where
%       the parent is incomplete without the child. Do not use it for optional
%       or convenience children.
%
%       Example:
%           rankfeat.sequence.mustBeFollowedBy = 'extfeat';
%
%       This makes rankfeat -> extfeat a hard pair. By contrast,
%       reducedim/remvarcomp -> extdim is optional: extdim need not exist,
%       so the parent must not be encoded with mustBeFollowedBy.
%
%   mustPrecede / mustFollow
%       Static cross-step ordering. mustPrecede lists module ids that may not
%       already occur before this module; mustFollow lists module ids that may
%       not occur later. These relations belong here, not in module metadata.
%
%   moveWithChild
%       Parent-driven movement. If the parent is moved and its immediate child
%       satisfies the child-legality rule, the child is moved together with the
%       parent as one block. This protects adjacent producer/consumer pairs
%       from being separated by interactive reordering.
%
%       Example:
%           remvarcomp.sequence.moveWithChild = true;
%
%       Moving remvarcomp carries its extdim companion along.
%
%   moveWithParent
%       Child-driven movement. If the child is moved and its immediate parent
%       is one of the allowed parents, the parent is moved together with the
%       child. This is independent of whether the child is mandatory. An
%       optional child can still be structurally attached whenever it exists.
%
%       Examples:
%           extfeat.sequence.moveWithParent = true;
%           extdim.sequence.moveWithParent = true;
%
%       The first is a mandatory hard pair; the second is an optional attached
%       child. In both cases movement must preserve immediate adjacency.
%
%   deleteWithChild
%       Parent-driven deletion. If the parent is deleted and its immediate
%       child satisfies the child-legality rule, the child is also deleted.
%       This is appropriate when the child cannot survive without the producer
%       immediately before it.
%
%       Example:
%           remvarcomp.sequence.deleteWithChild = true;
%
%       Deleting remvarcomp removes the auto-added extdim child, because extdim
%       would otherwise be left without its immediate producer.
%
%   deleteWithParent
%       Child-driven deletion. If the child is deleted and its immediate parent
%       is one of the allowed parents, the parent is also deleted. Use this
%       only for hard pairs where deleting the child makes the parent invalid.
%       Do not set this merely because the child was auto-added.
%
%       Example hard pair:
%           extfeat.sequence.deleteWithParent = true;
%
%       Example soft pair:
%           extdim.sequence.deleteWithParent = false;
%
%       The distinction between deleteWithChild and deleteWithParent is
%       critical. For remvarcomp -> extdim, deleting remvarcomp should delete
%       extdim, but deleting extdim must not delete remvarcomp. For rankfeat ->
%       extfeat, deletion can be symmetric because rankfeat is incomplete
%       without extfeat.
%
% Recommended patterns
% -------------------------------------------------------------------------
% 1. Optional attached child
%    Use when the parent remains scientifically valid without the child, but
%    the child consumes the immediately preceding parent and therefore cannot
%    be moved independently while it exists.
%
%       parent.sequence.produces = {'someObject'};
%       parent.sequence.autoAddChild = 'child';
%       parent.sequence.moveWithChild = true;
%       parent.sequence.deleteWithChild = true;
%
%       child.sequence.consumes = {'someObject'};
%       child.sequence.requiresImmediatePreviousAny = {'parent'};
%       child.sequence.moveWithParent = true;
%       child.sequence.deleteWithParent = false;
%
%    Example: reducedim/remvarcomp -> extdim. Extdim may be omitted or removed
%    alone, but if present it moves with its parent and cannot be detached.
%
% 2. Hard producer/consumer pair
%    Use when the parent is incomplete or invalid without its child.
%
%       parent.sequence.produces = {'someObject'};
%       parent.sequence.mustBeFollowedBy = 'child';
%       parent.sequence.autoAddChild = 'child';
%       parent.sequence.moveWithChild = true;
%       parent.sequence.deleteWithChild = true;
%
%       child.sequence.consumes = {'someObject'};
%       child.sequence.requiresImmediatePreviousAny = {'parent'};
%       child.sequence.moveWithParent = true;
%       child.sequence.deleteWithParent = true;
%
%    Example: rankfeat -> extfeat. The two modules should be inserted, moved
%    and deleted as a hard adjacent pair.
%
% 3. Independent module
%    Use when the module has no immediate producer/consumer dependency. Keep
%    sequence fields empty and define only availability/addable as needed.
%
% Practical development notes
% -------------------------------------------------------------------------
% * Cross-step grammar lives here only. Module classes expose intrinsic
%   capabilities and per-module cardinality; they must not duplicate producer/
%   consumer or ordering relationships in info().sequence.
% * Use availability rules for context gates, not for parent/child grammar.
%   Example: hasCovars belongs in availability; requiresImmediatePreviousAny
%   belongs in sequence.
% * Use module configSpec visibleIf clauses for parameter visibility. Do not
%   put UI field visibility logic into NMPreprocRuleSet.
% * Test every new parent/child rule with five actions: add parent, delete
%   parent, delete child, move parent and move child. Most rule bugs are
%   directional errors in delete/move logic.
% * For optional children, avoid mustBeFollowedBy and keep
%   child.deleteWithParent=false. For hard children, use mustBeFollowedBy and
%   symmetric movement/deletion.
% -------------------------------------------------------------------------

    properties (Access = private)
        Rules
    end

    methods (Static)
        function rs = default()
            % default  Build the standard preprocessing sequencing ruleset.
            %   Encodes subject-vs-CV availability, module dependencies, ordering constraints, and
            %   unique-across-stage rules used by UI and scripts.

            rs = NMPreprocRuleSet();
            rs.installDefaultRules();
        end
    end

    methods
        function obj = NMPreprocRuleSet()
            % NMPreprocRuleSet  Construct an empty preprocessing ruleset container.
            %   Callers normally use default(), but tests/extensions can instantiate and add
            %   constraints programmatically.

            obj.Rules = containers.Map('KeyType','char','ValueType','any');
        end

        function installDefaultRules(obj)
            % installDefaultRules  Populate this ruleset with the standard NeuroMiner preprocessing constraints.
            %   Adds canonical module rules for scaling, imputation, spatial extractors, graph
            %   chains, reduction/extraction pairs, and legacy placeholders so UI/API availability
            %   checks match legacy PREPROC semantics.

            % Independent/simple modules already ported.
            obj.addRule(obj.rule('scale',        'Scale data'));
            obj.addRule(obj.rule('standardize',  'Standardize data'));
            obj.addRule(obj.rule('unitnormalize','Normalize data to unit vector'));
            obj.addRule(obj.rule('discsym',      'Apply binning or symbolization'));
            obj.addRule(obj.rule('elimzero',     'Prune non-informative columns'));
            obj.addRule(obj.rule('skewcorr',     'Apply skewness correction'));
            obj.addRule(obj.rule('copyfeat',     'Copy feature matrix'));

            r = obj.rule('impute','Impute missing values');
            r.availability.requiresAny = {'hasNaNsInPredictors','isStackingInputLayer'};
            r.availability.unavailableMessage = 'Imputation is available only if the current modality contains missing values or input-layer stacking predictions are being configured.';
            obj.addRule(r);

            % Covariate-dependent modules. Ported modules are addable when covariates exist.
            for id = {'correctnuis','remmeandiff'}
                r = obj.rule(id{1}, obj.prettyLabel(id{1}));
                r.availability.requiresAll = {'hasCovars'};
                r.availability.unavailableMessage = 'This preprocessing step requires at least one covariate in the current dataset.';
                r.addable = true;
                obj.addRule(r);
            end

            r = obj.rule('normalize', obj.prettyLabel('normalize'));
            r.availability.requiresAll = {'hasCovars'};
            r.availability.unavailableMessage = 'This preprocessing step requires at least one covariate in the current dataset.';
            r.addable = false; % not ported yet; existing legacy steps are preserved.
            obj.addRule(r);

            % Missing-label post-processing. Kept in the ruleset although it
            % will probably move to wf.labelProcessing later.
            r = obj.rule('labelimpute','Propagate labels to unlabeled training data');
            r.availability.requiresAll = {'hasNaNsInLabels'};
            r.availability.unavailableMessage = 'Label imputation is available only when the current outcome labels contain missing values.';
            r.addable = true;
            obj.addRule(r);

            % Subject-stage and dual-stage imaging modules. The panel itself
            % is stage-driven, not imaging-driven: imaging is only a module
            % capability checked by isAvailable(). Future non-imaging subject
            % modules can therefore be registered without changing the UI.
            r = obj.rule('smoothing','Gaussian smoothing');
            r.sequence.mustPrecede = {'JuSpace','ROImeans'};
            r.addable = true;
            obj.addRule(r);

            r = obj.rule('waveletSpatial','Wavelet spatial reconstruction');
            r.sequence.mustPrecede = {'JuSpace','ROImeans','graphComputation'};
            r.addable = true;
            obj.addRule(r);

            r = obj.rule('spatiallegacy','Legacy spatial operation');
            r.addable = false;
            obj.addRule(r);

            % Feature-ranking producer/consumer block.
            r = obj.rule('rankfeat','Rank, weight, or mask features');
            r.sequence.produces = {'featureRanking'};
            r.sequence.mustBeFollowedBy = 'extfeat';
            r.sequence.autoAddChild = 'extfeat';
            r.sequence.moveWithChild = true;
            r.sequence.deleteWithChild = true;
            r.addable = true;
            obj.addRule(r);

            r = obj.rule('extfeat','Apply feature-ranking action');
            r.sequence.consumes = {'featureRanking'};
            r.sequence.requiresImmediatePreviousAny = {'rankfeat'};
            r.sequence.moveWithParent = true;
            r.sequence.deleteWithParent = true;
            r.availability.requiresImmediatePreviousAny = {'rankfeat'};
            r.addable = true;
            obj.addRule(r);

            % Dimensionality-reduction producer and extraction child.
            % reducedim is now ported and auto-adds extdim so the dimensionality
            % grid lives in extdim rather than forcing repeated projection fits.
            r = obj.rule('reducedim','Apply dimensionality reduction');
            r.sequence.produces = {'dimensionModel'};
            r.sequence.autoAddChild = 'extdim';
            r.sequence.moveWithChild = true;
            r.sequence.deleteWithChild = true;   % removing the producer removes its companion child
            r.addable = true;
            obj.addRule(r);

            % Variance-component removal is a second producer for extdim.
            % Extdim is optional, and is auto-added only when back-projection
            % is inactive. When present it remains attached to its producer
            % during movement, while removing extdim alone keeps the parent.
            r = obj.rule('remvarcomp','Remove variance components');
            r.sequence.produces = {'dimensionModel'};
            r.sequence.autoAddChild = 'extdim';
            r.sequence.moveWithChild = true;
            r.sequence.deleteWithChild = true;   % removing the producer removes its companion child
            r.addable = true;
            obj.addRule(r);

            r = obj.rule('extdim','Extract subspaces from reduced projections');
            r.sequence.consumes = {'dimensionModel'};
            r.sequence.requiresImmediatePreviousAny = {'reducedim','remvarcomp'};
            r.sequence.moveWithParent = true;
            r.sequence.deleteWithParent = false; % optional child: removing extdim keeps producer
            r.availability.requiresImmediatePreviousAny = {'reducedim','remvarcomp'};
            r.addable = true;
            obj.addRule(r);

            % Dual-stage imaging feature extractors; module capability metadata
            % constrains stage eligibility, imaging-only availability and global uniqueness.
            r = obj.rule('JuSpace','Spatial correlation with neuromaps');
            r.availability.requiresAll = {'hasJuSpaceDir'};
            r.availability.unavailableMessage = 'JuSpace is available after its resource directory has been configured in NeuroMiner.';
            r.addable = true; obj.addRule(r);
            r = obj.rule('ROImeans','Compute ROI mean values');
            r.addable = true; obj.addRule(r);
            r = obj.rule('devmap','Measure deviation from normative data');
            r.addable = true; obj.addRule(r);

            % Graph preprocessing modules are now ported. Graph construction
            % is dual-stage only for its KL-divergence mode; subject-stage
            % placement is guarded by the same spatial-extractor gate as
            % JuSpace/ROImeans.
            r = obj.rule('graphComputation', obj.prettyLabel('graphComputation'));
            r.addable = true; obj.addRule(r);
            r = obj.rule('graphSparsity', obj.prettyLabel('graphSparsity'));
            r.addable = true; obj.addRule(r);
            r = obj.rule('graphMetrics', obj.prettyLabel('graphMetrics'));
            r.addable = true; obj.addRule(r);

            r = obj.rule('customPreproc', obj.prettyLabel('customPreproc'));
            r.availability.requiresAll = {'isDev'};
            r.availability.unavailableMessage = 'This preprocessing step is not available in the current application mode.';
            r.addable = false;
            obj.addRule(r);
        end

        function addRule(obj, r)
            % addRule  Register or replace one module sequencing rule.
            %   Canonicalizes the rule id and stores the rule struct used by isAvailable,
            %   validateSequence, and addable-module queries.

            r.id = obj.canon(r.id);
            obj.Rules(r.id) = r;
        end

        function tf = hasRule(obj, id)
            % hasRule  Test whether a sequencing rule exists for a module id or alias.
            %   Used by registry/sequence code before resolving constraints for modules that may
            %   only be preserved as legacy placeholders.

            tf = obj.Rules.isKey(obj.canon(id));
        end

        function r = getRule(obj, id)
            % getRule  Resolve the sequencing rule for a module id.
            %   Returns the registered rule or a permissive default rule, allowing legacy/imported
            %   commands to remain inspectable even if no explicit rule was defined.

            id = obj.canon(id);
            if obj.Rules.isKey(id)
                r = obj.Rules(id);
            else
                r = obj.rule(id, id);
            end
        end

        function ids = list(obj)
            % list  Return sorted ids of modules with explicit rules.
            %   Supports diagnostics, UI schema generation, and maintainers auditing which
            %   preprocessing modules have dedicated availability constraints.

            ids = sort(obj.Rules.keys);
        end

        function result = crossCVFeatureIdentity(~, registry, subjectSteps, cvSteps)
            % Cross-CV1 PFE requires stable feature positions and identities.
            result = struct('eligible',true,'reason','','offending',{{}});
            stages = {'subject','cv'};
            sequences = {subjectSteps,cvSteps};
            for stage = 1:2
                steps = sequences{stage};
                for k = 1:numel(steps)
                    step = steps{k};
                    if ~step.enabled, continue; end
                    module = registry.get(step.moduleId);
                    if module.Capabilities.changesFeatureSpace
                        result.offending{end+1} = sprintf('%s step %d: %s', ...
                            stages{stage},k,module.DisplayName); %#ok<AGROW>
                    end
                end
            end
            if ~isempty(result.offending)
                result.eligible = false;
                result.reason = ['Cross-CV1 feature stability requires unchanged feature identity. ', ...
                    'Remove feature-changing preprocessing: ',strjoin(result.offending,'; '),'.'];
            end
        end

        function [ok, reasons] = isAvailable(obj, moduleId, ctx, seq, insertIndex)
            % isAvailable  Test whether a module can be inserted at a sequence position.
            %   Evaluates stage, context, ordering, dependency, and uniqueness constraints before
            %   scripts/UI mutate the sequence.

            if nargin < 3 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            if nargin < 4, seq = []; end
            if nargin < 5 || isempty(insertIndex)
                if ~isempty(seq) && isprop(seq,'Steps'), insertIndex = numel(seq.Steps) + 1; else, insertIndex = inf; end
            end

            r = obj.getRule(moduleId);
            ok = true; reasons = {};
            if any(strcmp(r.id,{'smoothing','waveletspatial'})) && ...
                    strcmp(ctx.datasource,'surf') && ~ctx.surfaceSpatialAvailable
                ok = false;
                reasons{end+1} = 'Surface smoothing and wavelets require DataIO-validated non-inflated geometry matching the imported vertex axis.'; %#ok<AGROW>
            end
            [module, info] = obj.moduleFromSeq(seq, moduleId);
            stage = obj.executionStage(ctx, seq);

            if ctx.isSeqoptStacking && (any(strcmp(obj.canon(moduleId), ...
                    {'rankfeat','extfeat','copyfeat'})) || ...
                    (~isempty(module) && info.capabilities.changesFeatureSpace))
                ok = false;
                reasons{end+1} = ['Sequential optimization requires every stacking prediction source. ', ...
                    'Feature ranking, pruning, dimensionality reduction and feature-space ', ...
                    'replacement cannot be used in stacking preprocessing.']; %#ok<AGROW>
            end

            if NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false) && isfield(r,'addable') && ~r.addable && ~NMPreprocRuleSet.ctxBool(ctx,'allowUnportedModules',false)
                ok = false;
                reasons{end+1} = 'Module is represented as a legacy placeholder; adding new instances is disabled until its canonical configurator is ported.'; %#ok<AGROW>
            end

            if ~isempty(module)
                cap = info.capabilities;
                seqmeta = info.sequence;

                if isfield(cap,'executionStages') && ~isempty(cap.executionStages)
                    allowed = cellfun(@(x) strcmpi(x,stage), cap.executionStages);
                    if ~any(allowed)
                        ok = false;
                        reasons{end+1} = sprintf('Module is not eligible for the %s preprocessing stage.', stage); %#ok<AGROW>
                    end
                end

                if isfield(cap,'imagingOnly') && cap.imagingOnly && NMPreprocRuleSet.ctxKnownFalse(ctx,'isImaging')
                    ok = false;
                    reasons{end+1} = 'Module is available only for imaging modalities.'; %#ok<AGROW>
                end

                if strcmp(obj.canon(module.Id),'graphcomputation') && strcmpi(stage,'subject')
                    if NMPreprocRuleSet.ctxKnownFalse(ctx,'isImaging')
                        ok = false;
                        reasons{end+1} = 'Subject-specific KL graph construction is available only for imaging modalities.'; %#ok<AGROW>
                    end
                    if NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false) && obj.sequenceContainsAnySpatialFeatureExtractor(ctx)
                        ok = false;
                        reasons{end+1} = 'Only one spatial feature extractor is allowed across subject-specific and CV-bound preprocessing. JuSpace, ROI means and subject-specific KL graph construction are mutually exclusive once selected in either stage.'; %#ok<AGROW>
                    end
                    if ~obj.imageSpaceAvailableBefore(seq, insertIndex, ctx)
                        ok = false;
                        reasons{end+1} = 'Cannot insert subject-specific KL graph construction here because the spatial-extractor allow flag is off after prior preprocessing.'; %#ok<AGROW>
                    end
                    if obj.anyLaterRequiresImageSpace(seq, insertIndex)
                        ok = false;
                        reasons{end+1} = 'Cannot insert subject-specific KL graph construction before a later image-space module such as smoothing.'; %#ok<AGROW>
                    end
                end

                ignoreCurrentForSelector = NMPreprocRuleSet.ctxBool(ctx,'ignoreCurrentSequenceForSelector',false);

                if NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false) && ~ignoreCurrentForSelector && isfield(seqmeta,'allowMultiple') && ~seqmeta.allowMultiple && obj.sequenceContains(seq, module.Id, [])
                    ok = false;
                    reasons{end+1} = sprintf('Module %s may occur only once in the %s sequence.', module.Id, stage); %#ok<AGROW>
                end

                if NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false) && ~ignoreCurrentForSelector && isfield(cap,'uniqueAcrossStages') && cap.uniqueAcrossStages && obj.sequenceContainsAny(ctx, seq, module.Id)
                    ok = false;
                    reasons{end+1} = sprintf('Module %s may occur only once across subject-specific and CV-bound preprocessing.', module.Id); %#ok<AGROW>
                end

                if NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false) && ~ignoreCurrentForSelector && isfield(cap,'requiresSpatialFeatureExtractionAllowed') && cap.requiresSpatialFeatureExtractionAllowed && obj.sequenceContainsAnySpatialFeatureExtractor(ctx)
                    ok = false;
                    reasons{end+1} = 'Only one spatial feature extractor is allowed across subject-specific and CV-bound preprocessing. JuSpace, ROI means and KL graph construction are mutually exclusive once selected in either stage.'; %#ok<AGROW>
                end

                if isfield(cap,'requiresSpatialFeatureExtractionAllowed') && cap.requiresSpatialFeatureExtractionAllowed && ~obj.imageSpaceAvailableBefore(seq, insertIndex, ctx)
                    ok = false;
                    reasons{end+1} = 'Cannot insert JuSpace/ROImeans here because the spatial-extractor allow flag is off after prior preprocessing.'; %#ok<AGROW>
                elseif isfield(cap,'requiresImageSpace') && cap.requiresImageSpace && ~obj.imageSpaceAvailableBefore(seq, insertIndex, ctx)
                    ok = false;
                    reasons{end+1} = 'Cannot insert an image-space module here because prior preprocessing has switched the spatial-extractor allow flag off.'; %#ok<AGROW>
                end

                laterStart = insertIndex;
                if ~NMPreprocRuleSet.ctxBool(ctx,'internalForAdd',false), laterStart = insertIndex + 1; end
                if isfield(cap,'isImageSpaceTerminal') && cap.isImageSpaceTerminal && obj.anyLaterRequiresImageSpace(seq, laterStart)
                    ok = false;
                    reasons{end+1} = 'Cannot insert JuSpace/ROImeans before a later image-space module such as smoothing.'; %#ok<AGROW>
                end

                if ~isempty(r.sequence.mustPrecede) && obj.anyPriorModule(seq, insertIndex, r.sequence.mustPrecede)
                    ok = false;
                    reasons{end+1} = sprintf('Module must precede: %s.', strjoin(r.sequence.mustPrecede, ', ')); %#ok<AGROW>
                end

                if ~isempty(r.sequence.mustFollow) && obj.anyLaterModule(seq, insertIndex, r.sequence.mustFollow)
                    ok = false;
                    reasons{end+1} = sprintf('Module must follow: %s.', strjoin(r.sequence.mustFollow, ', ')); %#ok<AGROW>
                end
            end

            av = r.availability;
            [ok, reasons] = obj.checkContextRequirements(av, ctx, ok, reasons);

            if isfield(av,'requiresImmediatePreviousAny') && ~isempty(av.requiresImmediatePreviousAny)
                prevId = obj.previousModuleId(seq, insertIndex);
                if isempty(prevId) || ~any(strcmp(prevId, av.requiresImmediatePreviousAny))
                    ok = false;
                    reasons{end+1} = sprintf('Can only be inserted immediately after: %s.', strjoin(av.requiresImmediatePreviousAny, ', ')); %#ok<AGROW>
                end
            end
        end

        function assertCanInsert(obj, moduleId, ctx, seq, insertIndex)
            % assertCanInsert  Enforce availability before a sequence insertion mutates state.
            %   Wraps isAvailable and raises a detailed error listing violated constraints;
            %   NMPreprocSequence.insert uses it as the insertion gate.

            ctx2 = ctx; ctx2.internalForAdd = true;
            [ok, reasons] = obj.isAvailable(moduleId, ctx2, seq, insertIndex);
            if ~ok
                error('NMPreprocRuleSet:notAvailable', 'Cannot insert preprocessing module %s at position %d:\n%s', ...
                    char(moduleId), insertIndex, strjoin(reasons, newline));
            end
        end

        function report = validateSequence(obj, seq, registry, ctx)
            % validateSequence  Validate all constraints for an existing preprocessing sequence.
            %   Returns a report with errors/warnings used by NMPreprocSequence.validate and the
            %   orchestrator export gate.

            if nargin < 4 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            report = struct('ok',true,'errors',{{}},'warnings',{{}});
            ids = obj.sequenceIds(seq);

            for i = 1:numel(ids)
                id = ids{i}; r = obj.getRule(id);

                % Unknown/legacy module should not crash validation if it is
                % present in an imported ACTPARAM sequence.
                if nargin >= 3 && ~isempty(registry) && ~registry.has(id)
                    report.warnings{end+1} = sprintf('Step %d/%s is not registered. It will be preserved only if wrapped as a raw legacy step.', i, id); %#ok<AGROW>
                end

                if isfield(r.sequence,'requiresImmediatePreviousAny') && ~isempty(r.sequence.requiresImmediatePreviousAny)
                    if i == 1 || ~any(strcmp(ids{i-1}, r.sequence.requiresImmediatePreviousAny))
                        report.errors{end+1} = sprintf('Step %d/%s must be placed immediately after: %s.', ...
                            i, id, strjoin(r.sequence.requiresImmediatePreviousAny, ', ')); %#ok<AGROW>
                    end
                end

                if isfield(r.sequence,'mustBeFollowedBy') && ~isempty(r.sequence.mustBeFollowedBy)
                    if i == numel(ids) || ~strcmp(ids{i+1}, r.sequence.mustBeFollowedBy)
                        report.errors{end+1} = sprintf('Step %d/%s must be followed immediately by %s.', ...
                            i, id, r.sequence.mustBeFollowedBy); %#ok<AGROW>
                    end
                end

                [avail, why] = obj.isAvailable(id, ctx, seq, i);
                if ~avail
                    msg = sprintf('Step %d/%s is not available in the current context: %s', i, id, strjoin(why, '; '));
                    if ctx.isSeqoptStacking || ctx.strictAvailability
                        report.errors{end+1} = msg; %#ok<AGROW>
                    else
                        report.warnings{end+1} = msg; %#ok<AGROW>
                    end
                end

                if strcmp(id,'graphcomputation') && obj.stepIsKLGraph(seq.Steps{i})
                    if ~obj.imageSpaceAvailableBefore(seq, i, ctx)
                        report.errors{end+1} = sprintf('Step %d/graphComputation in KL-divergence mode requires image-space input at its insertion point.', i); %#ok<AGROW>
                    end
                    if obj.anyLaterRequiresImageSpace(seq, i+1)
                        report.errors{end+1} = sprintf('Step %d/graphComputation in KL-divergence mode cannot precede a later image-space preprocessing step such as smoothing.', i); %#ok<AGROW>
                    end
                end

                if strcmp(id,'remvarcomp') && obj.stepUsesWaveletRemVarComp(seq.Steps{i})
                    if NMPreprocRuleSet.ctxKnownFalse(ctx,'isImaging')
                        report.errors{end+1} = sprintf('Step %d/remvarcomp uses a wavelet-based method, which is available only for imaging modalities.', i); %#ok<AGROW>
                    end
                    if ~obj.imageSpaceAvailableBefore(seq, i, ctx)
                        report.errors{end+1} = sprintf('Step %d/remvarcomp uses a wavelet-based method but prior preprocessing has already left image space.', i); %#ok<AGROW>
                    end
                end
            end
            report.warnings = [report.warnings obj.imageSpaceWarnings(seq, ctx)];
            report = obj.addGraphSequenceDiagnostics(report, ids);
            if obj.countSpatialFeatureExtractorsAcrossContext(ctx) > 1
                report.errors{end+1} = 'Only one spatial feature extractor is allowed across subject-specific and CV-bound preprocessing. JuSpace, ROI means and KL graph construction are mutually exclusive once selected in either stage.'; %#ok<AGROW>
            end

            % Additional computational-consistency warnings for projection-producer->extdim.
            for i = 1:max(0,numel(ids)-1)
                if any(strcmp(ids{i},{'reducedim','remvarcomp'}))
                    try
                        pcfg = seq.Steps{i}.config;
                        if strcmp(ids{i},'reducedim')
                            pDim = pcfg.fitDim;
                            pMode = pcfg.percMode;
                        else
                            pDim = pcfg.fitDim;
                            if isfield(pcfg,'dimensionMode'), pMode = pcfg.dimensionMode; else, pMode = 'absolute'; end
                        end
                        if numel(pDim) > 1 && i < numel(ids) && strcmp(ids{i+1},'extdim')
                            report.warnings{end+1} = sprintf(['Step %d/%s has a dimensionality grid while step %d/extdim also extracts ', ...
                                'a dimensionality grid. This may reintroduce repeated projection fits; prefer scalar producer dimensionality and place the optimization grid in extdim.'], i, ids{i}, i+1); %#ok<AGROW>
                        elseif numel(pDim) > 1 && (i == numel(ids) || ~strcmp(ids{i+1},'extdim'))
                            report.warnings{end+1} = sprintf(['Step %d/%s carries a dimensionality grid without an extdim child. ', ...
                                'This is allowed for legacy compatibility but may recompute the projection model for each dimensionality.'], i, ids{i}); %#ok<AGROW>
                        end
                        if i < numel(ids) && strcmp(ids{i+1},'extdim')
                            if strcmp(ids{i},'remvarcomp') && obj.stepBackProjects(seq.Steps{i})
                                report.warnings{end+1} = sprintf(['Step %d/remvarcomp back-projects the adjusted data into input space, ', ...
                                    'therefore step %d/extdim is probably misplaced. Remove extdim unless you intentionally want to extract ', ...
                                    'dimensions from the non-back-projected projection output.'], i, i+1); %#ok<AGROW>
                            end
                            ccfg = seq.Steps{i+1}.config;
                            if isfield(ccfg,'percMode') && any(strcmp(pMode,{'absolute','fixed'})) && strcmp(ccfg.percMode,'absolute')
                                edims = [];
                                if isfield(ccfg,'dims'), edims = ccfg.dims; end
                                if isfield(ccfg,'scheduleMode') && ~strcmp(ccfg.scheduleMode,'user') && isfield(ccfg,'rangeMax')
                                    edims = ccfg.rangeMax;
                                end
                                if ~isempty(edims) && max(edims(:)) > max(pDim(:))
                                    report.warnings{end+1} = sprintf('Step %d/extdim requests dimensions above the projection size in step %d/%s.', i+1, i, ids{i}); %#ok<AGROW>
                                end
                            end
                        end
                    catch
                        % Do not make the generic rule validator fragile.
                    end
                end
            end
            report.ok = isempty(report.errors);
        end

        function idx = removalIndices(obj, seq, idx)
            % removalIndices  Return all sequence indices removed for a requested step deletion.
            %   Expands a single deletion to dependent child/parent block members so UI/API removal
            %   does not leave invalid preprocessing fragments behind.

            ids = obj.sequenceIds(seq);
            if idx < 1 || idx > numel(ids), error('NMPreprocRuleSet:badIndex','Step index out of range.'); end
            idx = idx(:)';
            for k = idx
                r = obj.getRule(ids{k});
                if isfield(r.sequence,'deleteWithParent') && r.sequence.deleteWithParent && k > 1
                    if obj.isImmediateChildOf(r, ids{k-1})
                        idx(end+1) = k - 1; %#ok<AGROW>
                    end
                end
                if isfield(r.sequence,'deleteWithChild') && r.sequence.deleteWithChild && k < numel(ids)
                    childRule = obj.getRule(ids{k+1});
                    if obj.isImmediateChildOf(childRule, ids{k})
                        idx(end+1) = k + 1; %#ok<AGROW>
                    end
                end
            end
            idx = unique(idx);
        end

        function block = blockIndices(obj, seq, idx)
            % blockIndices  Return the contiguous dependency block around one step.
            %   Detects parent/child preprocessing pairs for move and remove operations, preserving
            %   required immediate-neighbor relationships.

            ids = obj.sequenceIds(seq);
            if idx < 1 || idx > numel(ids), error('NMPreprocRuleSet:badIndex','Step index out of range.'); end
            block = idx;
            r = obj.getRule(ids{idx});
            if isfield(r.sequence,'requiresImmediatePreviousAny') && ~isempty(r.sequence.requiresImmediatePreviousAny) && idx > 1
                if any(strcmp(ids{idx-1}, r.sequence.requiresImmediatePreviousAny)) && ...
                        NMPreprocRuleSet.seqBool(r.sequence,'moveWithParent',false)
                    block = [idx-1 idx];
                    return;
                end
            end
            if idx < numel(ids)
                childRule = obj.getRule(ids{idx+1});
                if obj.isImmediateChildOf(childRule, ids{idx}) && ...
                        NMPreprocRuleSet.seqBool(r.sequence,'moveWithChild',false)
                    block = [idx idx+1];
                end
            end
        end

        function steps = autoChildSteps(obj, moduleId, registry, parentStep)
            % autoChildSteps  Build automatically inserted child steps for a parent module.
            %   Used by NMPreprocSequence after inserting modules such as dimensionality reduction
            %   or RemVarComp when a required extraction/back-projection child should follow.

            steps = {};
            if nargin < 4, parentStep = struct(); end
            r = obj.getRule(moduleId);
            if isfield(r.sequence,'autoAddChild') && ~isempty(r.sequence.autoAddChild)
                if strcmp(obj.canon(moduleId),'remvarcomp') && obj.stepBackProjects(parentStep)
                    % Back-projection returns RemVarComp output to input space;
                    % ExtDim is therefore not auto-inserted for this configured parent.
                    return;
                end
                childId = r.sequence.autoAddChild;
                if registry.has(childId)
                    child = registry.get(childId);
                    steps{end+1} = struct('moduleId',child.Id,'config',child.defaultConfig()); %#ok<AGROW>
                end
            end
        end

        function infos = getAddableModuleInfos(obj, registry, seq, ctx, insertIndex)
            % getAddableModuleInfos  Return metadata for modules valid at an insertion point.
            %   Combines registry infos with isAvailable results so UI pickers and power-user
            %   tooling can present only legal choices.

            ids = registry.list();
            infos = {};
            for i = 1:numel(ids)
                ctx2 = ctx; ctx2.internalForAdd = true;
                [ok, reasons] = obj.isAvailable(ids{i}, ctx2, seq, insertIndex);
                m = registry.get(ids{i}); info = m.info();
                info.available = ok;
                info.unavailableReasons = reasons;
                if ok, infos{end+1} = info; end %#ok<AGROW>
            end
        end

        function specs = getAddableConfigSpecs(obj, registry, seq, ctx, insertIndex)
            % getAddableConfigSpecs  Return config schemas for modules addable at a position.
            %   Combines getAddableModuleInfos with registry configSpec calls so UI/API callers can
            %   render only valid module editors.

            infos = obj.getAddableModuleInfos(registry, seq, ctx, insertIndex);
            specs = cell(1,numel(infos));
            for i = 1:numel(infos)
                specs{i} = registry.get(infos{i}.id).configSpec(ctx);
            end
        end

        function [insertIndex, allowed, reason, allowedAtEnd] = getSpatialExtractorGate(obj, seq, ctx)
            % getSpatialExtractorGate  Report where spatial feature extractors may be inserted.
            %   Exposes image-space gating for UI/API code deciding whether JuSpace, ROI means, or
            %   graph construction can still be added safely.

            % Public wrapper used by orchestrator/API code. The actual replay
            % implementation remains private to keep the rule grammar local.
            [insertIndex, allowed, reason, allowedAtEnd] = obj.spatialExtractorGate(seq, ctx);
        end

        function ui = toUISpec(obj, ctx)
            % toUISpec  Serialize ruleset constraints for browser/API inspection.
            %   Exports rule ids, descriptions, availability flags, and sequencing metadata so
            %   UI/RAG layers can explain why modules are enabled or disabled.

            if nargin < 2 || isempty(ctx), ctx = NMPreprocContext.empty(); end
            ids = obj.list();
            modules = cell(1,numel(ids));
            for i = 1:numel(ids)
                r = obj.getRule(ids{i});
                modules{i} = r;
            end
            ui = struct();
            ui.kind = 'NMPreprocRuleSet';
            ui.schemaVersion = 1;
            ui.context = NMPreprocContext.toUISummary(ctx);
            ui.modules = modules;
        end

        function txt = describe(obj, moduleId)
            % describe  Return a readable explanation of one module rule.
            %   Formats context requirements, ordering constraints, dependency rules, and
            %   multiplicity limits for CLI diagnostics and power-user guidance.

            r = obj.getRule(moduleId);
            parts = {};
            if isfield(r.availability,'requiresAll') && ~isempty(r.availability.requiresAll)
                parts{end+1} = ['requires context: ' strjoin(r.availability.requiresAll, ', ')]; %#ok<AGROW>
            end
            if isfield(r.availability,'requiresAny') && ~isempty(r.availability.requiresAny)
                parts{end+1} = ['requires any context: ' strjoin(r.availability.requiresAny, ', ')]; %#ok<AGROW>
            end
            if isfield(r.sequence,'requiresImmediatePreviousAny') && ~isempty(r.sequence.requiresImmediatePreviousAny)
                parts{end+1} = ['requires immediate previous: ' strjoin(r.sequence.requiresImmediatePreviousAny, ', ')]; %#ok<AGROW>
            end
            if isfield(r.sequence,'mustBeFollowedBy') && ~isempty(r.sequence.mustBeFollowedBy)
                parts{end+1} = ['must be followed by: ' r.sequence.mustBeFollowedBy]; %#ok<AGROW>
            end
            if isfield(r.sequence,'autoAddChild') && ~isempty(r.sequence.autoAddChild)
                parts{end+1} = ['auto-add child: ' r.sequence.autoAddChild]; %#ok<AGROW>
            end
            if ~isempty(r.sequence.mustPrecede)
                parts{end+1} = ['must precede: ' strjoin(r.sequence.mustPrecede, ', ')]; %#ok<AGROW>
            end
            if ~isempty(r.sequence.mustFollow)
                parts{end+1} = ['must follow: ' strjoin(r.sequence.mustFollow, ', ')]; %#ok<AGROW>
            end
            if isfield(r,'addable') && ~r.addable
                parts{end+1} = 'legacy placeholder; not addable until ported'; %#ok<AGROW>
            end
            if isempty(parts), txt = 'none'; else, txt = strjoin(parts, '; '); end
        end
    end

    methods
        function tf = stepIsSpatialFeatureExtractor(obj, seq, st)
            if isempty(st) || ~isfield(st,'moduleId'), tf = false; return; end
            id = obj.canon(st.moduleId);
            if strcmp(id,'graphcomputation') && obj.stepIsKLGraph(st), tf = true; return; end
            tf = obj.moduleCapability(seq, st.moduleId, 'isSpatialFeatureExtractor');
        end

        function tf = stepIsDimensionalityReductionLike(obj, seq, st)
            if isempty(st) || ~isfield(st,'moduleId'), tf = false; return; end
            id = obj.canon(st.moduleId);
            if strcmp(id,'graphcomputation') && obj.stepIsKLGraph(st), tf = true; return; end
            if strcmp(id,'remvarcomp')
                tf = ~obj.stepBackProjects(st);
                return;
            end
            tf = obj.moduleCapability(seq, st.moduleId, 'isDimensionalityReductionLike');
        end

        function tf = stepUsesExternalFeatureWeights(obj, st)
            tf = false;
            if isempty(st) || ~isfield(st,'moduleId') || ~strcmp(obj.canon(st.moduleId),'rankfeat'), return; end
            tf = any(strcmpi(st.config.algorithm, {'extern','extern2'}));
        end

        function facts = resolveStepFacts(obj, seq, st)
            % resolveStepFacts  Resolve browser/API scientific facts for one canonical step.
            %   This is a read-only projection of RuleSet and registered-module authority.
            %   It is not persisted state and contains no compatibility fallbacks.
            if isempty(st) || ~isfield(st,'moduleId') || isempty(st.moduleId)
                error('NMPreprocRuleSet:invalidStep','Cannot resolve preprocessing facts for a step without moduleId.');
            end
            id = obj.canon(st.moduleId);
            facts = struct();
            facts.moduleId = char(string(st.moduleId));
            facts.valid = true;
            facts.backProjects = false;
            facts.imagingOnly = obj.moduleCapability(seq, st.moduleId, 'imagingOnly');
            facts.requiresImageSpace = obj.moduleCapability(seq, st.moduleId, 'requiresImageSpace');
            facts.invalidatesImageSpace = obj.moduleCapability(seq, st.moduleId, 'invalidatesImageSpace');
            facts.restoresImageSpace = false;
            facts.isImageSpaceTerminal = obj.moduleCapability(seq, st.moduleId, 'isImageSpaceTerminal');
            facts.requiresSpatialFeatureExtractionAllowed = obj.moduleCapability(seq, st.moduleId, 'requiresSpatialFeatureExtractionAllowed');
            facts.isSpatialFeatureExtractor = obj.stepIsSpatialFeatureExtractor(seq, st);
            facts.isDimensionalityReductionLike = obj.stepIsDimensionalityReductionLike(seq, st);
            facts.usesExternalFeatureWeights = obj.stepUsesExternalFeatureWeights(st);
            facts.usesWaveletImageMethod = false;

            if strcmp(id,'graphcomputation') && obj.stepIsKLGraph(st)
                facts.requiresImageSpace = true;
                facts.invalidatesImageSpace = true;
                facts.isImageSpaceTerminal = true;
                facts.requiresSpatialFeatureExtractionAllowed = true;
            elseif strcmp(id,'remvarcomp')
                facts.backProjects = obj.stepBackProjects(st);
                facts.usesWaveletImageMethod = obj.stepUsesWaveletRemVarComp(st);
                facts.requiresImageSpace = facts.requiresImageSpace || facts.usesWaveletImageMethod;
                facts.invalidatesImageSpace = ~facts.backProjects;
                facts.restoresImageSpace = facts.backProjects;
            end
        end

        function facts = resolveSequenceFacts(obj, seq, soft)
            % resolveSequenceFacts  Project RuleSet facts for every step in sequence order.
            %   soft=true is a UI boundary: invalid canonical state becomes an explicit
            %   per-step diagnostic instead of a silent fallback.
            if nargin < 3 || isempty(soft), soft = false; end
            facts = cell(1,numel(seq.Steps));
            for i = 1:numel(seq.Steps)
                try
                    facts{i} = obj.resolveStepFacts(seq, seq.Steps{i});
                catch ME
                    if ~soft, rethrow(ME); end
                    facts{i} = struct('moduleId',char(string(seq.Steps{i}.moduleId)), ...
                        'valid',false,'error',ME.message);
                end
            end
        end
    end

    methods (Access = private)
        function [module, info] = moduleFromSeq(~, seq, moduleId)
            module = []; info = struct();
            try
                if ~isempty(seq) && isprop(seq,'Registry') && seq.Registry.has(moduleId)
                    module = seq.Registry.get(moduleId);
                    info = module.info();
                end
            catch
                module = []; info = struct();
            end
        end

        function stage = executionStage(~, ctx, seq)
            stage = 'cv';
            try
                if isstruct(ctx) && isfield(ctx,'executionStage') && ~isempty(ctx.executionStage)
                    stage = lower(char(ctx.executionStage));
                elseif ~isempty(seq) && isprop(seq,'ExecutionStage') && ~isempty(seq.ExecutionStage)
                    stage = lower(char(seq.ExecutionStage));
                end
            catch
                stage = 'cv';
            end
        end

        function tf = sequenceContains(obj, seq, moduleId, excludeSeq)
            tf = false;
            if nargin < 4, excludeSeq = []; end
            if isempty(seq) || isequal(seq, excludeSeq) || ~isprop(seq,'Steps'), return; end
            ids = obj.sequenceIds(seq);
            tf = any(strcmp(obj.canon(moduleId), ids));
        end

        function tf = sequenceContainsAny(obj, ctx, currentSeq, moduleId)
            tf = false;
            seqs = {currentSeq};
            if isstruct(ctx) && isfield(ctx,'allSequences') && ~isempty(ctx.allSequences)
                seqs = ctx.allSequences;
                if isstruct(seqs), seqs = num2cell(seqs); end
            end
            for i = 1:numel(seqs)
                if obj.sequenceContains(seqs{i}, moduleId, [])
                    tf = true; return;
                end
            end
        end

        function tf = sequenceContainsAnySpatialFeatureExtractor(obj, ctx)
            tf = false;
            if ~isstruct(ctx) || ~isfield(ctx,'allSequences') || isempty(ctx.allSequences), return; end
            seqs = ctx.allSequences;
            if isstruct(seqs), seqs = num2cell(seqs); end
            for i = 1:numel(seqs)
                seq = seqs{i};
                if isempty(seq) || ~isprop(seq,'Steps'), continue; end
                for j = 1:numel(seq.Steps)
                    if obj.stepIsSpatialFeatureExtractor(seq, seq.Steps{j})
                        tf = true; return;
                    end
                end
            end
        end

        function n = countSpatialFeatureExtractorsAcrossContext(obj, ctx)
            n = 0;
            if ~isstruct(ctx) || ~isfield(ctx,'allSequences') || isempty(ctx.allSequences), return; end
            seqs = ctx.allSequences;
            if isstruct(seqs), seqs = num2cell(seqs); end
            for i = 1:numel(seqs)
                seq = seqs{i};
                if isempty(seq) || ~isprop(seq,'Steps'), continue; end
                for j = 1:numel(seq.Steps)
                    if obj.stepIsSpatialFeatureExtractor(seq, seq.Steps{j})
                        n = n + 1;
                    end
                end
            end
        end

        function [insertIndex, allowed, reason, allowedAtEnd] = spatialExtractorGate(obj, seq, ctx)
            % Return the last legal insertion position for JuSpace/ROImeans
            % as a 1-based insert index. allowed=false means the modules are
            % not addable anywhere in this stage. allowedAtEnd captures the
            % boolean image-space flag after the current stage.
            if nargin < 3 || isempty(ctx), ctx = struct(); end
            insertIndex = 1; allowed = true; reason = ''; allowedAtEnd = true;
            if isempty(seq) || ~isprop(seq,'Steps'), return; end

            if strcmpi(obj.executionStage(ctx, seq), 'cv') && ~obj.subjectStagePreservesImageSpace(ctx)
                insertIndex = 0; allowed = false; allowedAtEnd = false;
                reason = 'Subject-specific preprocessing has already left imaging space.';
                return;
            end

            for ii = 1:numel(seq.Steps)
                if obj.stepIsSpatialFeatureExtractor(seq, seq.Steps{ii})
                    insertIndex = 0; allowed = false; allowedAtEnd = false;
                    reason = 'JuSpace/ROImeans is already present in this stage.';
                    return;
                end
            end

            flag = true;
            insertAfter = 0;
            for ii = 1:numel(seq.Steps)
                st = seq.Steps{ii};
                if strcmp(obj.canon(st.moduleId),'remvarcomp') && obj.stepBackProjects(st)
                    flag = true;
                    insertAfter = ii;
                    continue;
                end
                if obj.stepInvalidatesImageSpace(seq, st)
                    flag = false;
                    continue;
                end
                if flag
                    insertAfter = ii;
                end
            end
            insertIndex = insertAfter + 1;
            allowedAtEnd = flag;
        end

        function tf = imageSpaceAvailableBefore(obj, seq, insertIndex, ctx)
            tf = true;
            if nargin < 4, ctx = struct(); end
            if isempty(seq) || ~isprop(seq,'Steps'), return; end

            % CV-bound image-space operations can only start from image space
            % if the subject-specific sequence has not already reduced the
            % data to derived features (JuSpace/ROImeans or equivalent legacy
            % spatial terminal). A later CV remvarcomp step cannot reconstruct
            % original images if the subject stage has already left image space.
            if strcmpi(obj.executionStage(ctx, seq), 'cv') && ~obj.subjectStagePreservesImageSpace(ctx)
                tf = false;
                return;
            end

            n = min(insertIndex-1, numel(seq.Steps));
            for ii = 1:n
                tf = obj.imageSpaceAfterStep(seq, seq.Steps{ii}, tf);
            end
        end

        function tf = subjectStagePreservesImageSpace(obj, ctx)
            tf = true;
            if ~isstruct(ctx) || ~isfield(ctx,'allSequences') || isempty(ctx.allSequences), return; end
            seqs = ctx.allSequences;
            if isstruct(seqs), seqs = num2cell(seqs); end
            for ii = 1:numel(seqs)
                seq = seqs{ii};
                if isempty(seq) || ~isprop(seq,'ExecutionStage') || ~strcmpi(seq.ExecutionStage,'subject') || ~isprop(seq,'Steps')
                    continue;
                end
                tf = obj.imageSpaceAvailableAfterSequence(seq, true);
                return;
            end
        end

        function tf = imageSpaceAvailableAfterSequence(obj, seq, startVal)
            if nargin < 3, startVal = true; end
            tf = startVal;
            if isempty(seq) || ~isprop(seq,'Steps'), return; end
            for ii = 1:numel(seq.Steps)
                tf = obj.imageSpaceAfterStep(seq, seq.Steps{ii}, tf);
            end
        end

        function tf = imageSpaceAfterStep(obj, seq, st, current)
            tf = current;
            if isempty(st) || ~isfield(st,'moduleId'), return; end
            id = obj.canon(st.moduleId);

            if strcmp(id,'remvarcomp')
                if obj.stepBackProjects(st)
                    % Back-projection is an explicit module-level override:
                    % it re-enables downstream spatial feature extraction.
                    tf = true;
                else
                    tf = false;
                end
                return;
            end

            if obj.stepInvalidatesImageSpace(seq, st)
                tf = false;
            end
        end

        function tf = stepInvalidatesImageSpace(obj, seq, st)
            if isempty(st) || ~isfield(st,'moduleId'), tf = false; return; end
            id = obj.canon(st.moduleId);

            % Config-conditioned overrides remain RuleSet-owned. Intrinsic
            % image-space invalidation is owned by registered module metadata.
            if strcmp(id,'graphcomputation') && obj.stepIsKLGraph(st)
                tf = true; return;
            end
            if strcmp(id,'remvarcomp')
                tf = ~obj.stepBackProjects(st); return;
            end
            tf = obj.moduleCapability(seq, st.moduleId, 'invalidatesImageSpace');
        end

        function tf = stepUsesWaveletRemVarComp(~, st)
            tf = any(strcmpi(char(st.config.reductionMethod), {'waveletPCA','waveletICA','waveletDirect'}));
        end

        function tf = stepBackProjects(~, st)
            tf = logical(st.config.backProject);
        end

        function tf = stepIsKLGraph(~, st)
            tf = strcmp(st.config.method, 'KL divergence');
        end

        function report = addGraphSequenceDiagnostics(obj, report, ids) %#ok<INUSL>
            gcomp = find(strcmp(ids,'graphcomputation'));
            gspar = find(strcmp(ids,'graphsparsity'));
            gmet  = find(strcmp(ids,'graphmetrics'));
            if ~isempty(gspar) && ~isempty(gmet) && gspar(1) > gmet(1)
                report.errors{end+1} = 'Graph sparsity thresholding must not follow graph metrics; graph metrics transform edge vectors into graph-derived features.';
            end
            if ~isempty(gmet) && ~isempty(gcomp) && gmet(1) < gcomp(1)
                report.warnings{end+1} = 'Graph metrics precede graph construction. This is only valid if the input data are already graph-edge vectors.';
            elseif ~isempty(gmet) && isempty(gcomp)
                report.warnings{end+1} = 'Graph metrics were selected without graph construction. This is valid only if the input data are already graph-edge vectors.';
            end
            if ~isempty(gspar) && ~isempty(gcomp) && gspar(1) < gcomp(1)
                report.warnings{end+1} = 'Graph sparsity thresholding precedes graph construction. This is valid only if the input data are already graph-edge vectors.';
            elseif ~isempty(gspar) && isempty(gcomp)
                report.warnings{end+1} = 'Graph sparsity thresholding was selected without graph construction. This is valid only if the input data are already graph-edge vectors.';
            end
        end

        function warnings = imageSpaceWarnings(obj, seq, ctx) %#ok<INUSD>
            warnings = {};
            if isempty(seq) || ~isprop(seq,'Steps'), return; end
            ids = obj.sequenceIds(seq);
            for ii = 1:numel(ids)
                if obj.stepIsSpatialFeatureExtractor(seq, seq.Steps{ii})
                    for jj = ii+1:numel(ids)
                        if obj.stepIsDimensionalityReductionLike(seq, seq.Steps{jj})
                            warnings{end+1} = sprintf(['Step %d/%s is followed by step %d/%s. ', ...
                                'This stacks spatial feature extraction with a dimensionality-reduction-like operation; ', ...
                                'it is technically allowed but should be justified scientifically.'], ii, ids{ii}, jj, ids{jj}); %#ok<AGROW>
                            break;
                        end
                    end
                    for jj = ii+1:numel(ids)
                        if obj.stepUsesExternalFeatureWeights(seq.Steps{jj})
                            warnings{end+1} = sprintf(['Step %d/%s is followed by step %d/%s using an external feature-weight vector. ', ...
                                'The external vector must match the post-JuSpace/ROImeans feature space; otherwise execution will fail.'], ii, ids{ii}, jj, ids{jj}); %#ok<AGROW>
                            break;
                        end
                    end
                end
            end
        end

        function tf = anyPriorTerminal(obj, seq, insertIndex)
            tf = false;
            if isempty(seq) || ~isprop(seq,'Steps'), return; end
            n = min(insertIndex-1, numel(seq.Steps));
            for i = 1:n
                if obj.moduleCapability(seq, seq.Steps{i}.moduleId, 'isImageSpaceTerminal')
                    tf = true; return;
                end
            end
        end

        function tf = anyLaterRequiresImageSpace(obj, seq, insertIndex)
            tf = false;
            if isempty(seq) || ~isprop(seq,'Steps'), return; end
            for i = insertIndex:numel(seq.Steps)
                if obj.moduleCapability(seq, seq.Steps{i}.moduleId, 'requiresImageSpace')
                    tf = true; return;
                end
            end
        end

        function tf = anyPriorModule(obj, seq, insertIndex, moduleIds)
            tf = false;
            ids = obj.sequenceIds(seq);
            moduleIds = cellfun(@(x)obj.canon(x), moduleIds, 'UniformOutput', false);
            for i = 1:min(insertIndex-1,numel(ids))
                if any(strcmp(ids{i}, moduleIds)), tf = true; return; end
            end
        end

        function tf = anyLaterModule(obj, seq, insertIndex, moduleIds)
            tf = false;
            ids = obj.sequenceIds(seq);
            moduleIds = cellfun(@(x)obj.canon(x), moduleIds, 'UniformOutput', false);
            for i = insertIndex:numel(ids)
                if any(strcmp(ids{i}, moduleIds)), tf = true; return; end
            end
        end

        function tf = moduleCapability(~, seq, moduleId, field)
            if ~seq.Registry.has(moduleId), tf = false; return; end
            module = seq.Registry.get(moduleId);
            tf = logical(module.Capabilities.(field));
        end

        function r = rule(~, id, label)
            r = struct();
            r.id = id;
            r.label = label;
            r.addable = true;
            r.availability = struct('requiresAll',{{}},'requiresAny',{{}}, ...
                'requiresImmediatePreviousAny',{{}},'unavailableMessage','');
            r.sequence = struct('produces',{{}},'consumes',{{}}, ...
                'requiresImmediatePreviousAny',{{}},'mustBeFollowedBy','', ...
                'autoAddChild','', 'moveWithChild',false, 'deleteWithChild',false, ...
                'moveWithParent',false, 'deleteWithParent',false, ...
                'mustPrecede',{{}},'mustFollow',{{}});
        end

        function [ok, reasons] = checkContextRequirements(obj, av, ctx, ok, reasons) %#ok<INUSL>
            if isfield(av,'requiresAll') && ~isempty(av.requiresAll)
                for i = 1:numel(av.requiresAll)
                    key = av.requiresAll{i};
                    if NMPreprocRuleSet.ctxKnownFalse(ctx,key)
                        ok = false;
                        reasons{end+1} = sprintf('Requires %s.', key); %#ok<AGROW>
                    end
                end
            end
            if isfield(av,'requiresAny') && ~isempty(av.requiresAny)
                vals = false(1,numel(av.requiresAny)); known = false(1,numel(av.requiresAny));
                for i = 1:numel(av.requiresAny)
                    [known(i), vals(i)] = NMPreprocRuleSet.ctxKnownValue(ctx,av.requiresAny{i});
                end
                if any(known) && ~any(vals)
                    ok = false;
                    if isfield(av,'unavailableMessage') && ~isempty(av.unavailableMessage)
                        reasons{end+1} = av.unavailableMessage; %#ok<AGROW>
                    else
                        reasons{end+1} = sprintf('Requires at least one of: %s.', strjoin(av.requiresAny, ', ')); %#ok<AGROW>
                    end
                end
            end
        end

        function ids = sequenceIds(obj, seq) %#ok<INUSL>
            ids = {};
            if isempty(seq) || ~isprop(seq,'Steps'), return; end
            ids = cell(1,numel(seq.Steps));
            for i = 1:numel(seq.Steps), ids{i} = obj.canon(seq.Steps{i}.moduleId); end
        end

        function id = previousModuleId(obj, seq, insertIndex)
            id = '';
            if isempty(seq) || ~isprop(seq,'Steps') || insertIndex <= 1 || isempty(seq.Steps), return; end
            prev = insertIndex - 1;
            if prev >= 1 && prev <= numel(seq.Steps), id = obj.canon(seq.Steps{prev}.moduleId); end
        end

        function tf = isImmediateChildOf(obj, childRule, parentId)
            tf = false;
            if isfield(childRule.sequence,'requiresImmediatePreviousAny') && ~isempty(childRule.sequence.requiresImmediatePreviousAny)
                tf = any(strcmp(obj.canon(parentId), childRule.sequence.requiresImmediatePreviousAny));
            end
        end

        function id = canon(~, id)
            id = char(id);
            switch lower(id)
                case {'discretize','symbolize','binning'}
                    id = 'discsym';
                otherwise
                    id = lower(id);
            end
        end

        function s = prettyLabel(~, id)
            switch id
                case 'correctnuis', s = 'Regress out nuisance covariates';
                case 'normalize', s = 'Normalize to group mean';
                case 'remmeandiff', s = 'Offset correction';
                case 'reducedim', s = 'Apply dimensionality reduction';
                case 'remvarcomp', s = 'Extract variance components';
                case 'graphComputation', s = 'Compute individual networks';
                case 'graphSparsity', s = 'Apply connectivity sparsity threshold';
                case 'graphMetrics', s = 'Compute graph metrics';
                case 'customPreproc', s = 'Custom preprocessing function';
                otherwise, s = id;
            end
        end
    end

    methods (Static, Access = private)
        function tf = seqBool(seq, key, defaultVal)
            if nargin < 3, defaultVal = false; end
            tf = defaultVal;
            try
                if isstruct(seq) && isfield(seq,key) && ~isempty(seq.(key))
                    tf = logical(seq.(key));
                end
            catch
                tf = defaultVal;
            end
        end

        function tf = ctxBool(ctx, key, defaultVal)
            if nargin < 3, defaultVal = false; end
            if isstruct(ctx) && isfield(ctx,key) && ~isempty(ctx.(key))
                tf = logical(ctx.(key));
            else
                tf = defaultVal;
            end
        end

        function tf = ctxKnownFalse(ctx, key)
            [known, val] = NMPreprocRuleSet.ctxKnownValue(ctx,key);
            tf = known && ~val;
        end

        function [known, val] = ctxKnownValue(ctx, key)
            known = false; val = false;
            if isstruct(ctx) && isfield(ctx,key) && ~isempty(ctx.(key))
                known = true; val = logical(ctx.(key));
            end
        end
    end
end
