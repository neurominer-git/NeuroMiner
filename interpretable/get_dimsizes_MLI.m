function [nY,datatype,inp] = get_dimsizes_MLI(inp,nx,FUSION)

juspaceflag = false;
ROImeansflag = false;
inp.refdataflag = false;
if isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 5 && isfield(inp.PREPROC.SPATIAL,'JUSPACE') && ~isempty(inp.PREPROC.SPATIAL.JUSPACE)
    juspaceflag = true;
    juspace_mod = 'SPATIAL';
    inp.refdataflag = true;
elseif isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 7 && isfield(inp.PREPROC.SPATIAL,'ROIMEANS') && ~isempty(inp.PREPROC.SPATIAL.ROIMEANS)
    ROImeansflag = true;
    ROImeans_mod = 'SPATIAL';
    inp.refdataflag = true;
elseif isfield(inp.PREPROC,'ACTPARAM')
    for a = 1:numel(inp.PREPROC.ACTPARAM)
        if strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'JuSpace')
            juspaceflag = true;
            juspace_mod = 'PREPROC';
            ind_PREPROC_juspace = a;
        elseif strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'ROImeans')
            ROImeansflag = true;
            ROImeans_mod = 'PREPROC';
            ind_PREPROC_ROImeans = a;
        end
    end
end

featnames = {};

switch FUSION.flag
    case {0, 2, 3}
        if juspaceflag && strcmp(juspace_mod,'SPATIAL')
            nY = numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)*size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1);
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
             for a = 1:size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1)
                for b = 1:numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)
                    if size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1) > 1
                        featnames{end+1,1} = [inp.PREPROC.SPATIAL.JUSPACE.NTList{1,b}.id,['_atlas',num2str(a)]];
                    else
                        featnames{end+1,1} = inp.PREPROC.SPATIAL.JUSPACE.NTList{1,b}.id;
                    end
                end
            end
            featnames = {featnames};
        elseif juspaceflag && strcmp(juspace_mod,'PREPROC')
            nY = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
               for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1)
                    for b = 1:numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)
                        if size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1) > 1
                            featnames{end+1,1} = [inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList{1,b}.id,['_atlas',num2str(a)]];
                        else
                            featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList{1,b}.id;
                        end
                    end
                end
                featnames = {featnames};
        elseif ROImeansflag && strcmp(ROImeans_mod,'SPATIAL')
            nY = 0;
            for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs,1)
                nY = nY + numel(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs{a});
            end
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels,1)
                featnames{end+1,1} = inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels{a,1};
            end
        elseif ROImeansflag && strcmp(ROImeans_mod,'PREPROC')
            nY = 0;
            for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs,1)
                nY = nY + numel(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs{a});
            end
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasLabels,1)
                featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasLabels{a,1};
            end
        else
            nY = inp.X(nx).dimsizes;
            datatype = inp.X(nx).datatype;
            featnames = inp.featnames(nx);
        end
    case 1
        if juspaceflag && strcmp(juspace_mod,'SPATIAL')
            nY = numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)*size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1);
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1)
                for b = 1:numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)
                    if size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1) > 1
                        featnames{end+1,1} = [inp.PREPROC.SPATIAL.JUSPACE.NTList{1,b}.id,['_atlas',num2str(a)]];
                    else
                        featnames{end+1,1} = inp.PREPROC.SPATIAL.JUSPACE.NTList{1,b}.id;
                    end
                end
            end
            featnames = {featnames};
        elseif juspaceflag && strcmp(juspace_mod,'PREPROC')
            nY = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            nY = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1)
                for b = 1:numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)
                    if size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1) > 1
                        featnames{end+1,1} = [inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList{1,b}.id,['_atlas',num2str(a)]];
                    else
                        featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList{1,b}.id;
                    end
                end
            end
            featnames = {featnames};
        elseif ROImeansflag && strcmp(ROImeans_mod,'SPATIAL')
            nY = 0;
            for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs,1)
                nY = nY + numel(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs{a});
            end
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels,1)
                featnames{end+1,1} = inp.PREPROC.SPATIAL.ROIMEANS.AtlasLabels{a,1};
            end
        elseif ROImeansflag && strcmp(ROImeans_mod,'PREPROC')
            nY = 0;
            for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs,1)
                nY = nY + numel(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs{a});
            end
            datatype = 0;
            inp.MLI.Modality{nx}.imgops.flag = 0;
            for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasLabels,1)
                featnames{end+1,1} = inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasLabels{a,1};
            end
        else
            nY = inp.X(nx).dimsizes;
            datatype = inp.X(nx).datatype;
            featnames = inp.featnames(nx);
        end
end
inp.featnames(nx) = featnames;
end