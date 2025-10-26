function [out, fnd, out2, out3, out4] = nk_CheckLoadFile(pth, filetyp, f, d, ovrwrt, nclass)
global FUSION RAND 

% Check file type
a = regexp(filetyp,'CVdatamat','ONCE'); if ~isempty(a), a=1; else, a=0; end

nvar = size(pth,1); % get number of variates

out = []; fnd = false; out2=[]; out3 = [];
if ~exist('ovrwrt','var') || isempty(ovrwrt), ovrwrt  = false; end

% Addition of 11/05/2024: Dealing with missing data
if ~isfield(FUSION,'DealWithCompleteNanRows')
    DealWithCompleteNanRows = 1;
else
    DealWithCompleteNanRows = FUSION.DealWithCompleteNanRows;
end

for i=1:nvar

    px = deblank(pth(i,:));
    
    if exist(px,'file')
        fnd = true;
        if ovrwrt
            fprintf('\nFound %s file, CV2 partition [%g,%g].',filetyp, f, d)
        else
            [~,n] = fileparts(px);
            if ~a
                fprintf('\nFound %s file for modality #%g, CV2 partition [%g,%g].',filetyp, i, f, d)
            else
                fprintf('\nFound %s file, CV2 partition [%g,%g].',filetyp, f, d)
            end
            loadstr = sprintf('\nLoading %s file:\n%s',filetyp, n);
            fprintf(loadstr);
            try
                load(px);
            catch
                fprintf('\nCould not open file. May be corrupt. Recompute CV2 partition [%g,%g].',f,d);
                fnd = false;
                return
            end
            
            if exist('GD','var')
                out = GD;
            
            elseif exist('pGD','var')
                out = pGD;

            elseif exist('mapY','var')
                
                [iy,jy] = size(mapY.Tr);
                
                switch FUSION.flag % Concatenate modality data into single structure 

                    case 2 % Intermediate fusion
                        
                        if ~iscell(mapY.Tr{1,1}{1})
                            t_nclass = 1;
                            multiproc = true;
                        else
                            t_nclass = nclass;
                            multiproc = false;
                        end
                        if i == 1
                            out = mapY; 
                            out.Tr = cell(iy,jy);
                            out.CV = cell(iy,jy);
                            out.Ts = cell(iy,jy);
                            out.VI = cell(iy,jy);
                            
                            if ~multiproc
                                for k=1:iy
                                    for l=1:jy
                                        out.Tr{k,l} = cell(t_nclass,1);
                                        out.CV{k,l} = cell(t_nclass,1);
                                        out.Ts{k,l} = cell(t_nclass,1);
                                        out.VI{k,l} = cell(t_nclass,1);
                                    end
                                end
                            end
                            
                        end
                        
                        if i>1, fprintf('\nAdding data of modality #%g to single data matrix.',i); end
                        for k=1:iy
                            for l=1:jy
                                for j=1:t_nclass
                                    % in multi-class preprocessing we don't
                                    % have a one-nested cell array as data
                                    % container, e.g.
                                    % mapY.Tr{CV1 perm, CV1 fold}{data shelves}
                                    if multiproc
                                        TR = mapY.Tr{k,l};
                                        CV = mapY.CV{k,l};
                                        TS = mapY.Ts{k,l};
                                        nZo = size(out.Tr{k,l},1);
                                    else
                                        % in binary preprocessing we have a
                                        % two-nested cell arrays as data
                                        % containers, e.g.:
                                        % mapY.Tr{CV1 perm, CV1 fold}{binary classifier}{data shelves}
                                        TR = mapY.Tr{k,l}{j};
                                        CV = mapY.CV{k,l}{j};
                                        TS = mapY.Ts{k,l}{j};
                                        nZo = size(out.Tr{k,l}{j},1);
                                    end
                                    if i>1
                                        % Create mixtures of data shelves,
                                        % if modality concatenation is
                                        % activated
                                        cnt = 1;
                                        nZp = size(TR,1);
                                        MixCount = nZo * nZp;
                                        tOut.Tr = cell(MixCount,1);
                                        tOut.CV = cell(MixCount,1);
                                        tOut.Ts = cell(MixCount,1);
                                        tOut.VI = cell(MixCount,1);
                                        for zp = 1:nZp
                                            for zo = 1:nZo
                                                if multiproc
                                                    tOut.Tr{cnt} = [ out.Tr{k,l}{zo}, TR{zp} ];
                                                    tOut.CV{cnt} = [ out.CV{k,l}{zo}, CV{zp} ];
                                                    tOut.Ts{cnt} = [ out.Ts{k,l}{zo}, TS{zp} ];
                                                    tOut.VI{cnt} = [ out.VI{k,l}{zo}; i*ones(size(TR{zp},2),1) ]; 
                                                else
                                                    tOut.Tr{cnt} = [ out.Tr{k,l}{j}{zo}, TR{zp} ];
                                                    tOut.CV{cnt} = [ out.CV{k,l}{j}{zo}, CV{zp} ];
                                                    tOut.Ts{cnt} = [ out.Ts{k,l}{j}{zo}, TS{zp} ];
                                                    tOut.VI{cnt} = [ out.VI{k,l}{j}{zo}; i*ones(size(TR{zp},2),1) ]; 
                                                end
                                                cnt = cnt+1;
                                            end
                                        end
                                        if multiproc
                                            out.Tr{k,l} = tOut.Tr;
                                            out.CV{k,l} = tOut.CV;
                                            out.Ts{k,l} = tOut.Ts;
                                            out.VI{k,l} = tOut.VI;
                                        else
                                            out.Tr{k,l}{j} = tOut.Tr;
                                            out.CV{k,l}{j} = tOut.CV;
                                            out.Ts{k,l}{j} = tOut.Ts;
                                            out.VI{k,l}{j} = tOut.VI;
                                        end
                                        clear tOut;
                                    else
                                        if multiproc
                                            out.Tr{k,l} = TR;
                                            out.CV{k,l} = CV;
                                            out.Ts{k,l} = TS;
                                            for m=1:numel(TR)
                                                out.VI{k,l}{m} = ones(size(TR{m},2),1);
                                            end
                                        else
                                            out.Tr{k,l}{j} = TR;
                                            out.CV{k,l}{j} = CV;
                                            out.Ts{k,l}{j} = TS;
                                            for m=1:numel(TR)
                                                out.VI{k,l}{j}{m} = ones(size(TR{m},2),1);
                                            end
                                        end
                                    end
                                end   
                            end
                        end
                       
                    case {0,1,3,4} % Create structure storing modality information separately
                        
                        if i == 1
                            out = mapY; 
                            out.Tr = cell(iy,jy,nvar);
                            out.CV = cell(iy,jy,nvar);
                            out.Ts = cell(iy,jy,nvar);
                            if size(mapY.Tr{1,1},2) == nclass
                                for g=1:nvar
                                    for k=1:iy
                                        for l=1:jy
                                            out.Tr{k,l,g} = cell(1,nclass);
                                            out.CV{k,l,g} = cell(1,nclass);
                                            out.Ts{k,l,g} = cell(1,nclass);
                                        end
                                    end
                                end
                            end
                        end
                        for k=1:iy
                            for l=1:jy
                                if size(mapY.Tr{k,l},2) == nclass && ~RAND.Decompose == 9
                                    for j=1:nclass % loop through binary
                                        % Concatenate CV1 training data
                                        out.Tr{k,l,i}(:,j) = mapY.Tr{k,l}(:,j);
                                        % Concatenate CV1 test data
                                        out.CV{k,l,i}(:,j) = mapY.CV{k,l}(:,j);
                                        % Concatenate CV2 test data
                                        out.Ts{k,l,i}(:,j) = mapY.Ts{k,l}(:,j);
                                    end
                                else
                                   out.Tr{k,l,i} = mapY.Tr{k,l};
                                   % Concatenate CV1 test data
                                   out.CV{k,l,i} = mapY.CV{k,l};
                                   % Concatenate CV2 test data
                                   out.Ts{k,l,i} = mapY.Ts{k,l};
                                end
                                
                            end
                        end
                        
                end

            elseif exist('mapYocv','var') 
                [iy,jy] = size(mapYocv.Ts);

                switch FUSION.flag % Concatenate modality data into single structure
                    case 2
                        if i == 1
                            out = mapYocv; out.Ts = cell(iy,jy);
                            if iscell(mapYocv.Ts{1,1})
                                for k=1:iy
                                    for l=1:jy
                                        out.Ts{k,l} = cell(nclass,1);
                                    end
                                end
                            end
                        end
                        if i >1, fprintf('\nAdding data of modality #%g to single data matrix.',i); end
                        for k=1:iy
                            for l=1:jy
                                if iscell(mapYocv.Ts{k,l})
                                    for j=1:nclass % loop through binary   
                                        % Concatenate CV2 test data
                                        out.Ts{k,l}{j} = [out.Ts{k,l}{j} mapYocv.Ts{k,l}{j}];
                                    end
                                else
                                   % Concatenate CV2 test data
                                   out.Ts{k,l} = [out.Ts{k,l} mapYocv.Ts{k,l}];
                                end
                            end
                        end
                        
                    case {0,1,3,4} % Create structure storing modality information separately for MKL
                        if i == 1 
                            out = mapYocv; 
                            out.Ts = cell(iy,jy,nvar);
                        end
                        for k=1:iy
                            for l=1:jy
                                if iscell(mapYocv.Ts{k,l})
                                    for j=1:nclass % loop through binary 
                                        % Concatenate CV2 test data
                                        out.Ts{k,l,i}{j} = mapYocv.Ts{k,l}{j};
                                    end
                                else
                                   % Concatenate CV2 test data
                                   out.Ts{k,l,i} = mapYocv.Ts{k,l};
                                end
                            end
                        end
                        
                end
            end
        end
        if exist('MD','var')
            out2=MD;
        end
        if exist('xpos','var')
            out3=xpos;out4=ypos;
        end
    end
end

if exist('mapY','var') && (FUSION.flag == 1 || FUSION.flag == 2)
    fprintf('\nChecking combined data shelves for missing data.')
    [iy,jy] = size(mapY.Tr);
    out = nk_DealWithNaNCases(out, iy, jy, nclass, DealWithCompleteNanRows);
end