function nk_ShowEnsembleDiversity(P, R, VERBOSE, varargin)
% nk_ShowEnsembleDiversity  — quick visual debug for ensemble outputs
% Usage:
%   nk_ShowEnsembleDiversity(P, R, VERBOSE)
%   nk_ShowEnsembleDiversity(P, R, VERBOSE, 'Name','MyFold k=3', 'Tag','NM-P-AND-R')
%
% P : N×M matrix of base predictions (hard votes or probabilities)
% R : M×M diversity kernel (redundancy-like; higher = more similar)
% VERBOSE : if 0 → return immediately; if 1 → create/update figures
%
% Options (name/value):
%   'Name'    : title prefix for the figure (default '')
%   'Tag'     : figure tag to identify/reuse the window (default 'NK-PR-VIZ')
%   'CLimP'   : color limits for P (e.g., [0 1] for probs, [0 1] for hard votes)
%   'CLimR'   : color limits for R (e.g., [0 1])
%   'Colormap': colormap handle or name (default parula)
% =========================================================================
% (c) Nikolaos Koutsouleris, 10/2025

   if ~VERBOSE, return; end

    % ---- parse opts
    p = inputParser;
    p.addParameter('Name','',@(x)ischar(x)||isstring(x));
    p.addParameter('Tag','NK-PR-VIZ',@(x)ischar(x)||isstring(x));
    p.addParameter('CLimP',[],@(x)isnumeric(x)&&numel(x)==2 || isempty(x));
    p.addParameter('CLimR',[],@(x)isnumeric(x)&&numel(x)==2 || isempty(x));
    p.addParameter('Colormap',[],@(x)ischar(x)||isstring(x)||isa(x,'function_handle')||isnumeric(x));
    p.parse(varargin{:});
    opt = p.Results;

    tag  = char(opt.Tag);
    name = char(opt.Name);

    fig = findobj(0,'Type','figure','Tag',tag);
    isNew = isempty(fig) || ~ishghandle(fig);

    if isNew
        % ---------- create ----------
        fig = figure('Name',sprintf('P & R — %s',name), ...
                     'Tag',tag,'NumberTitle','off','Color','w');

        % Try tiledlayout (R2019b+), otherwise fallback to subplot
        useTL = ~isempty(which('tiledlayout'));
        S = struct;
        if useTL
            tl = tiledlayout(fig,1,2,'Padding','compact','TileSpacing','compact');
            axP = nexttile(tl,1);
            axR = nexttile(tl,2);
            S.tl = tl;
        else
            axP = subplot(1,2,1,'Parent',fig);
            axR = subplot(1,2,2,'Parent',fig);
        end

        % P
        imP = imagesc(axP, P);
        axis(axP,'ij'); axis(axP,'tight'); box(axP,'on');
        title(axP, sprintf('P (N×M) — %s',name),'Interpreter','none');
        xlabel(axP,'Learners (M)'); ylabel(axP,'Samples (N)');
        cbP = colorbar(axP); cbP.Label.String = 'prediction / vote';
        if ~isempty(opt.CLimP), caxis(axP,opt.CLimP); end

        % R
        imR = imagesc(axR, R);
        axis(axR,'ij'); axis(axR,'tight'); box(axR,'on');
        title(axR, sprintf('R (M×M) — %s',name),'Interpreter','none');
        xlabel(axR,'Learners (M)'); ylabel(axR,'Learners (M)');
        cbR = colorbar(axR); cbR.Label.String = 'redundancy';
        if ~isempty(opt.CLimR), clim(axR,opt.CLimR); end

        % Colormap
        if ~isempty(opt.Colormap)
            colormap(fig,opt.Colormap);
        else
            colormap(fig,'parula');
        end

        % Stash handles
        S.axP=axP; S.axR=axR; S.imP=imP; S.imR=imR; S.cbP=cbP; S.cbR=cbR;
        setappdata(fig,'NK_PR_HANDLES',S);

    else
        % ---------- update ----------
        S = getappdata(fig,'NK_PR_HANDLES');
        if isempty(S) || ~isfield(S,'imP') || ~ishghandle(S.imP) || ~ishghandle(S.imR)
            delete(fig); % corrupted; recreate cleanly
            nk_ShowEnsembleDiversity(P,R,VERBOSE,varargin{:});
            return
        end

        % Update images
        set(S.imP,'CData',P);
        set(S.imR,'CData',R);

        % Update titles & color limits if provided
        set(get(S.axP,'Title'),'String',sprintf('P (N×M) — %s',name));
        set(get(S.axR,'Title'),'String',sprintf('R (M×M) — %s',name));
        if ~isempty(opt.CLimP), clim(S.axP,opt.CLimP); end
        if ~isempty(opt.CLimR), clim(S.axR,opt.CLimR); end

        % Optional recolor
        if ~isempty(opt.Colormap), colormap(fig,opt.Colormap); end

        drawnow limitrate
    end
end