function featnames = get_featnames_VisModels(inp)

juspaceflag = false;
roiflag = false;

if isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 5 && isfield(inp.PREPROC.SPATIAL,'JUSPACE') && ~isempty(inp.PREPROC.SPATIAL.JUSPACE)
    juspaceflag = true;
    juspace_mod = 'SPATIAL';
elseif isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 7 && isfield(inp.PREPROC.SPATIAL,'ROIMEANS') && ~isempty(inp.PREPROC.SPATIAL.ROIMEANS)
    roiflag = true;
    roi_mod = 'SPATIAL';
end

if isfield(inp.PREPROC,'ACTPARAM')
    for a = 1:numel(inp.PREPROC.ACTPARAM)
        if strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'JuSpace')
            juspaceflag = true;
            juspace_mod = 'PREPROC';
            ind_PREPROC = a;
        elseif strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'ROImeans')
            roiflag = true;
            roi_mod = 'PREPROC';
            ind_PREPROC = a;
        end
    end
end

featnames = {};

if juspaceflag && strcmp(juspace_mod,'SPATIAL')
    for a = 1:size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1)
        for b = 1:numel(inp.PREPROC.SPATIAL.JUSPACE.NTNames)
            if size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1) > 1
                featnames{end+1,1} = [inp.PREPROC.SPATIAL.JUSPACE.NTNames{b},['_',inp.PREPROC.SPATIAL.JUSPACE.AtlasNames{a}]];
            else
                featnames{end+1,1} = inp.PREPROC.SPATIAL.JUSPACE.NTNames{b};
            end
        end
    end
    featnames = {featnames};
elseif roiflag && strcmp(roi_mod,'SPATIAL')
    for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels,1)
        featnames{end+1,1} = inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels{a,1};
    end
elseif juspaceflag && strcmp(juspace_mod,'PREPROC')
    for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.Atlas,1)
        for b = 1:numel(inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.NTNames)
            if size(inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.Atlas,1) > 1
                featnames{end+1,1} = [inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.NTNames{b},['_',inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.AtlasNames{a}]];
            else
                featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC}.JUSPACE.NTNames{b};
            end
        end
    end
    featnames = {featnames};
elseif roiflag && strcmp(roi_mod,'PREPROC')
    for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC}.ROIMEANS.AtlasLabels,1)
        featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC}.ROIMEANS.AtlasLabels{a,1};
    end
elseif isfield(inp,'featnames')
    featnames = inp.featnames;
else
    featnames = [];
end

end