function [ulb, Label, NaNflag, g, nclass] = nk_Prep4CV(label, modeflag, decomposeflag, groups, groupnames, oldcv)

% Are NaNs in the label?
ulb = unique(label,'rows');
if any(~isfinite(ulb)) 
    NaNflag = true; ind = logical(sum(isfinite(ulb),2));
    ulb = ulb(ind,:);
else
    NaNflag = false;
end

if strcmp(modeflag,'classification') && decomposeflag ~= 9
    nclass = numel(ulb);
    if ~exist('oldcv','var') || isempty(oldcv)
        if ~exist('groupnames','var') || isempty(groupnames)
            g = cell(nclass,1);
            groupnameflag = nk_input('Define classifier descriptions',0,'yes|no',[1,0]);

            if groupnameflag
                for i=1:nclass
                    g{i} = nk_input(['Group #' num2str(i) ' name'],0,'s');
                end
            else
                g{nclass} = [];
            end
        else
            g = groupnames;
        end
    else
        b = [];
        nbincomp =  nclass*(nclass-1)/2;
        for i=1:nbincomp
            groupsstr = regexp(oldcv.class{1,1}{i}.groupdesc, ' vs ','split');
            b = [b groupsstr]; 
        end
        [~, i] = unique(b);
        g = b(sort(i));
    end
    Label = label;
else
    if exist('groups','var')
        if ~isempty(groups)
            Label = groups; 
        else
            Label = ones(size(label,1),1);
        end
    else
        Label = ones(length(label),1);
    end
    indnan = logical(sum(isnan(label),2));
    if any(indnan), Label(indnan,:)=NaN; end
    g=[];nclass=1;
end