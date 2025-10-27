function [nY,datatype,inp] = get_dimsizes_MLI(inp,nx,FUSION)

juspaceflag = false;
ROImeansflag = false;
inp.refdataflag = false;
if isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 5 && isfield(inp.PREPROC.SPATIAL,'JUSPACE') && ~isempty(inp.PREPROC.SPATIAL.JUSPACE)
    juspaceflag = true;
    juspace_mod = 'SPATIAL';
elseif isfield(inp.PREPROC, 'SPATIAL') && inp.PREPROC.SPATIAL.cubetype == 7 && isfield(inp.PREPROC.SPATIAL,'ROIMEANS') && ~isempty(inp.PREPROC.SPATIAL.ROIMEANS)
    ROImeansflag = true;
    ROImeans_mod = 'SPATIAL';
elseif isfield(inp.PREPROC,'ACTPARAM')
    for a = 1:numel(inp.PREPROC.ACTPARAM)
        if strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'JuSpace')
            juspaceflag = true;
            juspace_mod = 'PREPROC';
            ind_PREPROC_juspace = a;
            inp.refdataflag = true;
        elseif strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'ROImeans')
            ROImeansflag = true;
            ROImeans_mod = 'PREPROC';
            ind_PREPROC_ROImeans = a;
            inp.refdataflag = true;
        end
    end
end

issmoothed = false(1,nx); if isfield(inp,'issmoothed') && any(inp.issmoothed), issmoothed = inp.issmoothed; end

if issmoothed, sstr='s'; else, sstr=''; end

OCVstr = 'Y';

if inp.refdataflag && isfield(inp.X(nx),[sstr OCVstr '_orig'])
    inp.X(nx).([sstr OCVstr]) = inp.X(nx).([sstr OCVstr '_orig']);
end

if isfield(inp,'oocvflag') && inp.oocvflag, OCVstr = 'Yocv'; end

if inp.refdataflag && isfield(inp.X(nx),[sstr OCVstr '_orig'])
    inp.X(nx).([sstr OCVstr]) = inp.X(nx).([sstr OCVstr '_orig']);
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
            datatype = 0;

            nY = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);

            inp.MLI.Modality{nx}.imgops.flag = 0;

            issmoothed = false(1,nx); if isfield(inp,'issmoothed') && any(inp.issmoothed), issmoothed = inp.issmoothed; end

            if issmoothed, sstr='s'; else, sstr=''; end

            % do for original Y data

            OCVstr = 'Y';

            inp.X(nx).([sstr OCVstr '_orig']) = inp.X(nx).([ sstr OCVstr]);
    
            Y = inp.X(nx).([sstr OCVstr]);

            YimgROIs = [];

            for k = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas,1)
                a = unique(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas(k,:));
                a = a(a~=0);
                AtlasROIs = a(~isnan(a));
            
                tempYimgROIs = zeros(size(Y,1), numel(AtlasROIs));
            
                for i = 1:numel(AtlasROIs)
                    indVec = round(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas(k,:)) == round(AtlasROIs(i));
                    tempYimgROIs(:,i) = mean(removenan_my(Y(:,indVec)'),1);
                end
                YimgROIs = [YimgROIs,tempYimgROIs];
            end

            inp.X(nx).([sstr OCVstr]) = YimgROIs;

            % do for OOCV Y data

            if isfield(inp,'oocvflag') && inp.oocvflag
                
                OCVstr = 'Yocv';

                inp.X(nx).([sstr OCVstr '_orig']) = inp.X(nx).([ sstr OCVstr]);
        
                Y = inp.X(nx).([sstr OCVstr]);
    
                YimgROIs = [];
    
                for k = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas,1)
                    a = unique(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas(k,:));
                    a = a(a~=0);
                    AtlasROIs = a(~isnan(a));
                
                    tempYimgROIs = zeros(size(Y,1), numel(AtlasROIs));
                
                    for i = 1:numel(AtlasROIs)
                        indVec = round(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.YAtlas(k,:)) == round(AtlasROIs(i));
                        tempYimgROIs(:,i) = mean(removenan_my(Y(:,indVec)'),1);
                    end
                    YimgROIs = [YimgROIs,tempYimgROIs];
                end
    
                inp.X(nx).([sstr OCVstr]) = YimgROIs;

            end

            inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.ROIflag = true;

%             nY = size(inp.X(nx).([ sstr 'Y']),2);
            
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