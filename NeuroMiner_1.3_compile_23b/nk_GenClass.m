function class = nk_GenClass(g, xlb, nclass, lb, decomposeflag, nanflag)

switch decomposeflag
    
    % Generate binary classification classes (One-Vs-One)
    case 1
        
        cnt=1; class = cell(nclass*(nclass-1)/2,1);
        
        for i=1:nclass-1
            
            ijlb = zeros(1,2);
            ijlb(1) = xlb(i);
            
            for j=i+1:nclass
                
                ijlb(2) = xlb(j);
                class{cnt}.groups = ijlb;
                
                if ~isempty(g{i} ) && ~isempty(g{j})
                    class{cnt}.groupdesc = [g{i} ' vs ' g{j}];
                end
                
                % Positive label
                ind1 = find( lb == ijlb(1) );
                ind2 = find( lb == ijlb(2) );
                label1 = ones(1,numel(ind1))';
                label2 = -1*ones(1,numel(ind2))';
                class{cnt}.ind = [ind1; ind2];
                class{cnt}.label = [ label1; label2 ];
                if nanflag
                    indnan = find( ~isfinite(lb) );
                    labelnan = nan(numel(indnan),1);
                    class{cnt}.ind = [class{cnt}.ind; indnan];
                    class{cnt}.label = [ class{cnt}.label; labelnan ];
                end
                cnt=cnt+1;
            end
        end
    
    % Generate binary classification classes (One-Vs-All)
    case 2
        class = cell(nclass,1);
        for i=1:nclass
            if ~isempty(g{i}), class{i}.groupdesc = [g{i} ' vs ALL']; end
            class{i}.groups(1) = xlb(i);
            indpos = lb==xlb(i); indneg = lb~=xlb(i);
            label = zeros(size(lb)); 
            if any(indpos),label(indpos) = 1; end
            if any(indneg),label(indneg) = -1; end
            class{i}.label = label;
            class{i}.ind = (1:size(lb,1))';
            if nanflag
                indnan = find( ~isfinite(lb) );
                labelnan = nan(numel(indnan),1);
                class{i}.ind = [class{i}.ind; indnan];
                class{i}.label = [ class{i}.label; labelnan ];
            end
        end
    
    % Generate multi-group classification setup
    case 9
        class.groups =  1 : nclass ;
        class.groupdesc = 'Multi-group classification';
        class.label = lb;
        class.ind = (1:size(lb,1))';
        if nanflag
            indnan = find( ~isfinite(lb) );
            labelnan = nan(numel(indnan),1);
            class.ind = [class.ind; indnan];
            class.label = [ class.label; labelnan ];
        end
end