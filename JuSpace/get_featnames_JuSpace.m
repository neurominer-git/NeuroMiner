function featnames = get_featnames_JuSpace(inp)

juspaceflag = false;

if isfield(iPREPROC, 'SPATIAL') && iPREPROC.SPATIAL.cubetype == 5 && isfield(iPREPROC.SPATIAL,'JUSPACE') && ~isempty(iPREPROC.SPATIAL.JUSPACE)
    juspaceflag = true;
    D = numel(iPREPROC.SPATIAL.JUSPACE.NTList)*size(iPREPROC.SPATIAL.JUSPACE.Atlas,1);
    petlist = {};
    for b = 1:size(iPREPROC.SPATIAL.JUSPACE.Atlas,1)
        for c = 1:numel(iPREPROC.SPATIAL.JUSPACE.NTList)
            if size(iPREPROC.SPATIAL.JUSPACE.Atlas,1) > 1
                petlist{end+1,1} = [iPREPROC.SPATIAL.JUSPACE.NTList{1,c}.id,['_atlas',num2str(b)]];
            else
                petlist{end+1,1} = iPREPROC.SPATIAL.JUSPACE.NTList{1,c}.id;
            end
        end
    end
end
if isfield(iPREPROC,'ACTPARAM')
    for a = 1:numel(iPREPROC.ACTPARAM)
        if strcmp(iPREPROC.ACTPARAM{a}.cmd,'JuSpace')
            juspaceflag = true;
             D = numel(iPREPROC.ACTPARAM{a}.JUSPACE.NTList)*size(iPREPROC.ACTPARAM{a}.JUSPACE.Atlas,1);
            petlist = {};
            for b = 1:size(iPREPROC.ACTPARAM{a}.JUSPACE.Atlas,1)
                for c = 1:numel(iPREPROC.ACTPARAM{a}.JUSPACE.NTList)
                    if size(iPREPROC.ACTPARAM{a}.JUSPACE.Atlas,1) > 1
                        petlist{end+1,1} = [iPREPROC.ACTPARAM{a}.JUSPACE.NTList{1,c}.id,['_atlas',num2str(b)]];
                    else
                        petlist{end+1,1} = iPREPROC.ACTPARAM{a}.JUSPACE.NTList{1,c}.id;
                    end
                end
            end
        end
    end
end


end