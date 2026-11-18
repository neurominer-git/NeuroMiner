function [act, NM, A] = nk_InitAnalysisPrep(NM, A, parentstr, act)

% nk_InitAnalysisPrep
% Refactored to properly support single vs. multi-analysis selection.
% Multi-analysis: only delete / delete & wipe are allowed.
% Single-analysis: full legacy behavior preserved.

disallow = false;
na_str   = '?';

Amodes  = {'generate new','manage existing'};
Aovrwrt = { ...
    'delete', ...
    'delete & wipe', ...
    'complete reset', ...
    'parameter reset', ...
    'update paths and descriptors', ...
    'overwrite NM parameter template', ...
    'manage on disk'}; %#ok<NASGU>  % legacy list had 7; UI exposes 1:6 in original

% ---- init A ----
if ~exist('A','var') || isempty(A)
    A = struct('mode',1,'analdim',1,'ovrwrt',3,'id',na_str,'desc',na_str,'parentdir',na_str,'rootdir',na_str);
end

% Normalize analdim to row vector of unique positive integers (robustness)
if isfield(A,'analdim') && ~isempty(A.analdim)
    A.analdim = unique(A.analdim(:)'); %#ok<NASGU>
else
    A.analdim = 1;
end

mn_str = ''; mn_act = {};

% ===============================
% Menu construction
% ===============================
isMulti = false;

if isfield(NM,'analysis')

    mode_str = Amodes{A.mode};

    if A.mode == 2
        % ---- manage existing ----
        if any(A.analdim > numel(NM.analysis))
            A.analdim(A.analdim > numel(NM.analysis)) = [];
            if isempty(A.analdim), A.analdim = numel(NM.analysis); end
        end

        isMulti = numel(A.analdim) > 1;

        mn_sel_mode = sprintf('Generate new or manage existing analyses [ %s ]|', mode_str );
        mn_str = mn_sel_mode; mn_act = {'manage_analyses'};

        if isMulti
            % Multi-selection display (no selection menu item, but keep state)
            mn_str = [mn_str sprintf('Multiple analyses selected [ %d analyses ]|', numel(A.analdim))];
            mn_act = [mn_act 'noop'];

            % Restrict actions for multi
            if ~ismember(A.ovrwrt,[1 2]), A.ovrwrt = 1; end
            todo_str = {'delete','delete & wipe'};
            mn_todo_anal = sprintf('Specify what to do with selected analyses [ %s ]|', todo_str{A.ovrwrt});
            mn_str = [mn_str mn_todo_anal]; mn_act = [mn_act 'todo_analyses'];

        else
            % Single-selection: populate defaults from analysis slot
            if isfield(NM.analysis{A.analdim},'id')
                if strcmp(A.id,na_str),        A.id        = NM.analysis{A.analdim}.id;        end
                if strcmp(A.desc,na_str),      A.desc      = NM.analysis{A.analdim}.desc;      end
                if strcmp(A.parentdir,na_str), A.parentdir = NM.analysis{A.analdim}.parentdir; end
                if isfield(NM.analysis{A.analdim},'rootdir') && strcmp(A.rootdir,na_str)
                    A.rootdir = NM.analysis{A.analdim}.rootdir;
                end
            end

            anal_str = sprintf('Analysis %g',A.analdim);
            mn_sel_anal = sprintf('Select existing analysis [ %s ]|', anal_str);
            mn_str = [mn_str mn_sel_anal]; mn_act = [mn_act 'sel_analyses'];

            % Action
            todo_str = Aovrwrt{A.ovrwrt};
            mn_todo_anal = sprintf('Specify what to do with selected analysis [ %s ]|', todo_str);
            mn_str = [mn_str mn_todo_anal]; mn_act = [mn_act 'todo_analyses'];
        end

    else
        % ---- generate new ----
        A.analdim = numel(NM.analysis)+1;
        isMulti   = false;
        mn_sel_mode = sprintf('Generate new or manage existing analyses [ %s: analysis %g ]|', mode_str, A.analdim );
        mn_str = mn_sel_mode; mn_act = {'manage_analyses'};
    end
else
    % No NM.analysis yet; generate new is the only meaningful state
    isMulti = false;
end

% ===============================
% Metadata prompts
% Only for non-destructive single-analysis actions: [3 4 5]
% ===============================
if ~isMulti && ismember(A.ovrwrt,[3 4 5])

    if ~strcmp(A.id,na_str), def_str = A.id; else, def_str = na_str; end
    mn_def_analysis_id = sprintf('Define analysis identifier [ %s ]|', def_str);
    if isempty(mn_act)
        mn_str = mn_def_analysis_id; mn_act = {'def_analysis_id'};
    else
        mn_str = [mn_str mn_def_analysis_id]; mn_act = [mn_act 'def_analysis_id'];
    end

    if ~strcmp(A.desc,na_str), desc_str = 'provided'; else, desc_str = na_str; end
    mn_def_analysis_desc = sprintf('Provide analysis description [ %s ]|', desc_str);
    mn_str = [mn_str mn_def_analysis_desc]; mn_act = [mn_act 'def_analysis_desc'];

    mn_def_parentdir = sprintf('Specify parent directory of the analysis [ %s ]|', spm_file(A.parentdir,'short30'));
    mn_str = [mn_str mn_def_parentdir]; mn_act = [mn_act 'def_parentdir'];
end

% ===============================
% Proceed gating
% ===============================
if ~isMulti && ismember(A.ovrwrt,[3 4 5])
    if any(strcmp(A.parentdir,na_str)) || any(strcmp(A.desc,na_str)) || any(strcmp(A.id,na_str))
        disallow = true;
    end
end

if ~disallow
    mn_run = sprintf('PROCEED >>>'); mn_str = [ mn_str mn_run ] ; mn_act = [mn_act 'run'];
end

% ===============================
% UI
% ===============================
mestr = 'Select action of the analysis manager';
if ~exist('act','var') || isempty(act)
    nk_PrintLogo
    fprintf('\n');
    fprintf('You are here: %s >>> ',parentstr);
    act = char(nk_input(mestr,0,'mq', mn_str, mn_act));
end

% ===============================
% Dispatch
% ===============================
switch act

    case 'BACK'
        return

    case 'noop'
        % intentionally empty

    case 'manage_analyses'
        modus = nk_input('Define analysis manager operation mode',0,'mq','generate new|manage existing',[1,2],A.mode);
        if modus>0, A.mode = modus; end

    case 'sel_analyses'
        analdim = A.analdim;
        t_act = 1; brief = 1;
        while t_act>0
            [t_act, analdim, NM, ~, brief] = nk_SelectAnalysis(NM, 0, 'MAIN >>> Select Analysis', analdim, 0,0,[],brief);
        end
        if ~isempty(analdim)
            A.analdim = unique(analdim(:)'); % normalize
            if isscalar(A.analdim)
                A.id        = NM.analysis{A.analdim}.id ;
                A.desc      = NM.analysis{A.analdim}.desc;
                A.parentdir = NM.analysis{A.analdim}.parentdir;
                if isfield(NM.analysis{A.analdim},'rootdir')
                    A.rootdir = NM.analysis{A.analdim}.rootdir;
                end
            end
        end

    case 'todo_analyses'
        if isMulti
            ovrwrt = nk_input('Define what to do with the selected analyses',0,'mq', ...
                             ['delete|' ...
                              'delete and wipe from computer'], ...
                              [1 2], A.ovrwrt);
        else
            ovrwrt = nk_input('Define what to do with the selected analysis',0,'mq', ...
                             ['delete|' ...
                              'delete and wipe from computer|' ...
                              'completely reset|' ...
                              'reset parameters (risk of inconsistency)|' ...
                              'update paths and descriptors|' ...
                              'overwrite current NM parameter template with analysis workspace'], ...
                              1:6, A.ovrwrt);
        end
        if ovrwrt>0, A.ovrwrt = ovrwrt; end

    case 'def_parentdir'
        parentdir = uigetdir(pwd,'Select parent directory of the new analysis');
        if ischar(parentdir) && exist(parentdir,'dir')==7, A.parentdir = parentdir; end

    case 'def_analysis_id'
        if isfield(A,'id') && ~isempty(A.id), id_def = A.id;  else, id_def = []; end
        id = nk_input('Provide an alphanumeric identifier for your analysis',0,'s',id_def);
        if isempty(id) || strcmp(id,''), A.id=na_str; return; end
        A.id = id;
        ind_alphanum = isstrprop(A.id,'alphanum');
        ind_minus = false(size(ind_alphanum)); ind_dot=ind_minus; ind_under=ind_minus;
        f_minus = strfind(A.id,'-'); if ~isempty(f_minus); ind_minus(f_minus)=true; end
        f_under = strfind(A.id,'_'); if ~isempty(f_under); ind_under(f_under)=true; end
        f_dot   = strfind(A.id,'.'); if ~isempty(f_dot);   ind_dot(f_dot)=true;   end
        ind = ~(ind_alphanum | ind_minus | ind_dot | ind_under);
        A.id(ind) = '';

    case 'def_analysis_desc'
        if isfield(A,'desc') && ~isempty(A.desc), desc_def = A.desc; else, desc_def = []; end
        A.desc = nk_input('Describe the analysis you want to initialize',0,'s+',desc_def);

    case 'run'

        % ---- enforce multi-analysis legality ----
        isMulti = numel(A.analdim) > 1;
        if isMulti && ~ismember(A.ovrwrt,[1 2])
            error('Multi-analysis operations are restricted to delete or delete & wipe.');
        end

        switch A.ovrwrt

            % ==========================================================
            % 1/2: delete / delete & wipe (single or multi)
            % ==========================================================
            case {1,2}

                if A.ovrwrt == 2
                    if isMulti
                        askfl = questdlg( ...
                            sprintf('Are you sure you want to wipe %d analyses from your computer?', numel(A.analdim)), ...
                            mestr,'Yes','No','No');
                    else
                        % include analysis id for safety
                        try
                            aid = NM.analysis{A.analdim}.id;
                        catch
                            aid = '?';
                        end
                        askfl = questdlg( ...
                            sprintf('Are you sure you want to wipe analysis "%s" from your computer?', aid), ...
                            mestr,'Yes','No','No');
                    end

                    if strcmp(askfl,'Yes')
                        for i=1:numel(A.analdim)
                            rd = NM.analysis{A.analdim(i)}.rootdir;
                            if exist(rd,'dir')==7
                                rmdir(rd,'s');
                            end
                        end
                    else
                        return
                    end
                end

                % Delete analysis entries (descending indices avoids shifting surprises)
                NM.analysis(sort(A.analdim,'descend')) = [];
                if isempty(NM.analysis), NM = rmfield(NM,'analysis'); end

            % ==========================================================
            % 3/4: reset analysis (single only)
            % ==========================================================
            case {3,4}

                if isMulti
                    error('Reset operations are not allowed for multi-analysis selections.');
                end

                if A.ovrwrt == 3
                    NM.analysis{A.analdim} = [];
                    NM.analysis{A.analdim}.id        = A.id;
                    NM.analysis{A.analdim}.desc      = A.desc;
                    NM.analysis{A.analdim}.parentdir = A.parentdir;
                    NM.analysis{A.analdim}.rootdir   = fullfile( ...
                        NM.analysis{A.analdim}.parentdir, ...
                        sprintf('NM_ID%s_A%g_%s',NM.id,A.analdim,NM.analysis{A.analdim}.id));
                    if ~exist(NM.analysis{A.analdim}.rootdir,'dir')
                        mkdir(NM.analysis{A.analdim}.rootdir);
                    end
                end

                NM.analysis{A.analdim}.params.TrainParam     = NM.TrainParam;
                NM.analysis{A.analdim}.params.datadescriptor = NM.datadescriptor;
                NM.analysis{A.analdim}.params.cv            = NM.cv;
                NM.analysis{A.analdim}.params.id            = NM.id;
                NM.analysis{A.analdim}.meta.TIME            = datestr(now);

                if isfield(NM,'C')
                    NM.analysis{A.analdim}.C = NM.C;
                end

                if isfield(NM.TrainParam, 'LABEL') && NM.TrainParam.LABEL.flag
                    NM.analysis{A.analdim}.params.label.label        = NM.TrainParam.LABEL.newlabel;
                    NM.analysis{A.analdim}.params.label.modeflag     = NM.TrainParam.LABEL.newmode;
                    NM.analysis{A.analdim}.params.label.altlabelflag = NM.TrainParam.LABEL.flag;
                    NM.analysis{A.analdim}.params.label.labelname    = NM.TrainParam.LABEL.newlabelname;
                    if strcmp(NM.TrainParam.LABEL.newmode, 'classification')
                        NM.analysis{A.analdim}.params.label.altgroupnames = NM.TrainParam.LABEL.newgroupnames;
                    end
                else
                    NM.analysis{A.analdim}.params.label.label        = NM.label;
                    NM.analysis{A.analdim}.params.label.modeflag     = NM.modeflag;
                    NM.analysis{A.analdim}.params.label.labelname    = NM.datadescriptor{1,1}.input_settings.label_edit;
                    NM.analysis{A.analdim}.params.label.altlabelflag = 0;
                    if isfield(NM.TrainParam, 'LABEL') && NM.TrainParam.LABEL.flag && ...
                            isfield(NM.TrainParam.LABEL,'newmode') && strcmp(NM.TrainParam.LABEL.newmode, 'classification')
                        NM.analysis{A.analdim}.params.label.altgroupnames = NM.groupnames;
                    end
                end

                try
                    NM.analysis{A.analdim}.meta.USER       = java.lang.System.getProperty('user.name');
                    NM.analysis{A.analdim}.meta.OS.name    = java.lang.System.getProperty('os.name');
                    NM.analysis{A.analdim}.meta.OS.version = java.lang.System.getProperty('os.version');
                    NM.analysis{A.analdim}.meta.OS.arch    = java.lang.System.getProperty('os.arch');
                catch
                    NM.analysis{A.analdim}.meta.USER       = 'NA';
                end

                NM.analysis{A.analdim}.meta.MATLAB.ver = ver;
                NM.analysis{A.analdim}.meta.NM.ver     = NM.defs.NM_ver;
                NM.analysis{A.analdim}.status          = 0;

                [~, NM.analysis{A.analdim}] = nk_NMLogFileManager('init', NM, NM.analysis{A.analdim});

            % ==========================================================
            % 5: update paths & descriptors (single only)
            % ==========================================================
            case 5

                if isMulti
                    error('Update paths is not allowed for multi-analysis selections.');
                end

                old_rootdir     = sprintf('NM_ID%s_A%g_%s',NM.analysis{A.analdim}.params.id,A.analdim,NM.analysis{A.analdim}.id);
                old_rootdirpath = NM.analysis{A.analdim}.rootdir;
                new_rootdirpath = fullfile(A.parentdir,old_rootdir);

                if exist(new_rootdirpath,'dir') && ~strcmp(old_rootdirpath, new_rootdirpath)
                    NM.analysis{A.analdim}.desc      = A.desc;
                    NM.analysis{A.analdim}.parentdir = A.parentdir;
                    NM.analysis{A.analdim}.rootdir   = new_rootdirpath;
                    NM.analysis{A.analdim}.paramdir  = fullfile(new_rootdirpath,'params');

                    [~,n,e] = fileparts(NM.analysis{A.analdim}.paramfile);
                    NM.analysis{A.analdim}.paramfile = fullfile(NM.analysis{A.analdim}.paramdir,n,e);
                    NM.analysis{A.analdim}.logfile   = fullfile(new_rootdirpath, sprintf('NM_Analysis_%s.log', NM.analysis{A.analdim}.id));

                    mess.text = sprintf('Description:');
                    for i=1:numel(A.desc)
                        mess.text = sprintf('%s\n\t\t\t\t\t%s', mess.text, A.desc{i});
                    end
                    mess.text = sprintf('%s\nParent directory: %s\nRoot directory: %s', ...
                        mess.text, A.parentdir, new_rootdirpath);

                    nk_NMLogFileManager('add_entry', NM, NM.analysis{A.analdim}, 'InitAnalysis:UpdatePaths', mess);
                end

            % ==========================================================
            % 6: overwrite NM parameter workspace (single only)
            % ==========================================================
            case 6

                if isMulti
                    error('Overwrite NM parameter template is not allowed for multi-analysis selections.');
                end

                NM.TrainParam = NM.analysis{A.analdim}.params.TrainParam;
                NM.cv         = NM.analysis{A.analdim}.params.cv;

            otherwise
                error('Unsupported operation mode.');
        end

        act = 'BACK';
end
