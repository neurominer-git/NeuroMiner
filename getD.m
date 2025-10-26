function [ D, datatype, brainmask, badcoords, threshval, threshop] = getD(FUSEFLAG, inp, n)

if isfield(inp,'stacking') && inp.stacking
    datatype    = 0;
    brainmask   = [];
    badcoords   = false(1,inp.nD);
    threshval   = []; 
    threshop    = [];
    D           = inp.nD;
else
    switch FUSEFLAG
        case {0,1,3}
            switch FUSEFLAG
                case {0, 3}
                    juspaceflag = false;
                    ROImeansflag = false;
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
                            elseif strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'ROImeans')
                                ROImeansflag = true;
                                ROImeans_mod = 'PREPROC';
                                ind_PREPROC_ROImeans = a;
                            end
                        end
                    end

                    if juspaceflag && strcmp(juspace_mod,'SPATIAL')
                        D = numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)*size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1);
                        badcoords = false(1,D);
                        datatype = 0;
                    elseif juspaceflag && strcmp(juspace_mod,'PREPROC')
                        D = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);
                        badcoords = false(1,D);
                        datatype = 0;
                    elseif ROImeansflag && strcmp(ROImeans_mod,'SPATIAL')
                        D = 0;
                        for a = 1:size(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs,1)
                            D = D + numel(inp.PREPROC.SPATIAL.ROIMEANS.AtlasROIs{a});
                        end
                        badcoords = false(1,D);
                        datatype = 0;
                    elseif ROImeansflag && strcmp(ROImeans_mod,'PREPROC')
                        D = 0;
                        for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs,1)
                            D = D + numel(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs{a});
                        end
                        badcoords = false(1,D);
                        datatype = 0;
                    else
                        D = inp.X(1).dimvecx(end);
                        badcoords   = inp.X.badcoords{1};
                        datatype    = inp.X.datatype;
                    end
                    brainmask   = inp.X.brainmask{1};
                    threshval   = inp.X.threshval; 
                    threshop    = inp.X.threshop;
                case 1
                    D = inp.X(1).dimsizes(n);
                    datatype    = inp.X.datatype(n);
                    brainmask   = inp.X.brainmask{n};
                    badcoords   = inp.X.badcoords{n};
                    threshval   = inp.X.threshval{n}; 
                    threshop    = inp.X.threshop{n};
            end
        case 2
            juspaceflag = false;
            ROImeansflag = false;
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
                    elseif strcmp(inp.PREPROC.ACTPARAM{a}.cmd,'ROImeans')
                        ROImeansflag = true;
                        ROImeans_mod = 'PREPROC';
                        ind_PREPROC_ROImeans = a;
                    end
                end
            end

            if juspaceflag && strcmp(juspace_mod,'SPATIAL')
                D = numel(inp.PREPROC.SPATIAL.JUSPACE.NTList)*size(inp.PREPROC.SPATIAL.JUSPACE.Atlas,1);
                badcoords = false(1,D);
                datatype = 0;
            elseif juspaceflag && strcmp(juspace_mod,'PREPROC')
                D = numel(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.NTList)*size(inp.PREPROC.ACTPARAM{ind_PREPROC_juspace}.JUSPACE.Atlas,1);
                badcoords = false(1,D);
                datatype = 0;
            elseif ROImeansflag && strcmp(ROImeans_mod,'SPATIAL')
                D = 0;
                for a = 1:size(inp.PREPROC.SPATIAL.AtlasROIs,1)
                    D = D + numel(inp.PREPROC.SPATIAL.AtlasROIs{a});
                end
                badcoords = false(1,D);
                datatype = 0;
            elseif ROImeansflag && strcmp(ROImeans_mod,'PREPROC')
                D = 0;
                for a = 1:size(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs,1)
                    D = D + numel(inp.PREPROC.ACTPARAM{ind_PREPROC_ROImeans}.ROIMEANS.AtlasROIs{a});
                end
                badcoords = false(1,D);
                datatype = 0;
            else
                D = inp.X(n).dimvecx(end);
                badcoords   = inp.X(n).badcoords{1};
                datatype    = inp.X(n).datatype;
            end
            brainmask   = inp.X(n).brainmask{1};
            threshval   = inp.X(n).threshval; 
            threshop    = inp.X(n).threshop;
    end
end