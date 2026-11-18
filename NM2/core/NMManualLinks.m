classdef NMManualLinks
% NMManualLinks
% Central documentation-link registry for the modular NeuroMiner UI.
%
% Keep this small and explicit. Module classes may later expose their own
% documentation URL via info()/configSpec(), but the UI should not hard-code
% documentation anchors in JavaScript.

    methods (Static)
        function url = basePreprocManual()
            % basePreprocManual  Return the canonical NeuroMiner preprocessing manual URL.
            %
            % Centralizes the base documentation page used by module cards and fallback links so browser JavaScript does not hard-code external manual paths.
            url = 'https://neurominer-git.github.io/NeuroMiner/4.2.02_paramtemp_preprocessing_pipeline.html';
        end

        function links = preprocLinks()
            % preprocLinks  Return a scalar struct whose field names are canonical module ids.
            %
            % Unknown modules can still fall back to basePreprocManual().
            base = NMManualLinks.basePreprocManual();
            links = struct();

            % Exact anchors that are known / manually verified in the NeuroMiner manual.
            links.remvarcomp = [base '#extract-variance-components-from-data'];

            % Conservative generic fallbacks. These deliberately point to the
            % preprocessing-pipeline manual page rather than guessed anchors.
            ids = { ...
                'impute','scale','standardize','unitnormalize','discsym', ...
                'elimzero','skewcorr','copyfeat','rankfeat','extfeat', ...
                'reducedim','extdim','correctnuis','normalize','remmeandiff', ...
                'labelimpute','devmap','graphComputation','graphSparsity', ...
                'graphMetrics','JuSpace','ROImeans','customPreproc'};
            for i = 1:numel(ids)
                id = ids{i};
                if ~isfield(links, id)
                    links.(id) = base;
                end
            end
        end

        function url = forPreprocModule(moduleId)
            % forPreprocModule  Resolve a documentation URL for one preprocessing module id.
            %
            % Looks up verified module-specific anchors and falls back to the base preprocessing manual when no exact link is registered. The method is read-only and safe for UI/RAG link generation.
            links = NMManualLinks.preprocLinks();
            key = char(moduleId);
            key = regexprep(key, '[^A-Za-z0-9_]', '');
            if isfield(links, key)
                url = links.(key);
            else
                url = NMManualLinks.basePreprocManual();
            end
        end
    end
end
