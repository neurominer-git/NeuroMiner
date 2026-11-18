classdef NMSynthPopulationGenerator
% Pre-data population generator: the ten nk_SimulateML factors, extended
% to independent matrix modalities and native multiclass/regression targets.
% No CV, preprocessing, training, persistence or NM data-container state.
    methods (Static)
        function names = factorNames(plan)
            metrics={'NFeats','NMarkers','AUCmin','AUCmax'};
            if strcmp(plan.definition.modeflag,'regression')
                metrics(3:4)={'Rmin','Rmax'};
            end
            M=numel(plan.definition.modalityNames);
            names=cell(1,4*M+6);
            for m=1:M
                names(4*m-3:4*m)=cellfun(@(metric) ...
                    sprintf('%s: %s',plan.definition.modalityNames{m},metric), ...
                    metrics,'UniformOutput',false);
            end
            names(end-5:end)={'NCases','EventProb','NBatches','BatchPerc','NCasesMiss','NFeatsMiss'};
        end

        function rows = grid(plan)
            M=numel(plan.definition.modalityNames);
            axes=cell(1,4*M+6);
            for m=1:M
                f=plan.modalityFactors{m};
                if strcmp(plan.definition.modeflag,'regression')
                    axes(4*m-3:4*m)={f.NFeats,f.NMarkers,f.Rmin,f.Rmax};
                else
                    axes(4*m-3:4*m)={f.NFeats,f.NMarkers,f.AUCmin,f.AUCmax};
                end
            end
            axes(end-5:end)={plan.NCases,plan.EventProb,plan.NBatches, ...
                plan.BatchPerc,plan.NCasesMiss,plan.NFeatsMiss};
            for i=1:numel(axes)
                validateattributes(axes{i},{'numeric'}, {'vector','nonempty','finite','real'});
            end
            validateattributes(plan.NReps,{'numeric'},{'scalar','integer','positive'});
            validateattributes(plan.seed,{'numeric'}, ...
                {'scalar','integer','nonnegative','<=',intmax('uint32')});
            n=prod(cellfun(@numel,axes));
            assert(isfinite(n) && ...
                plan.seed+n*plan.NReps+200000<=double(intmax('uint32')), ...
                'NMSynthPopulationGenerator:tooManyChildren', ...
                'The number of children exceeds the available uint32 seed range.');
            rows=allcomb2(axes{:});
            for k=1:size(rows,1)
                NMSynthPopulationGenerator.validateRow(plan,rows(k,:));
            end
        end

        function validateRow(plan,row)
            % One scientific contract for each resolved parameter combination.
            M=numel(plan.definition.modalityNames);
            n=row(4*M+1);event=row(4*M+2);batches=row(4*M+3);
            strength=row(4*M+4);missingCases=row(4*M+5);missingFeatures=row(4*M+6);
            K=plan.definition.classCount;mode=plan.definition.modeflag;
            validateattributes(n,{'numeric'},{'scalar','integer','>=',10,'<=',65535});
            validateattributes(batches,{'numeric'},{'scalar','integer','>=',0,'<=',n});
            assert(all([strength,missingCases,missingFeatures]>=0 & ...
                [strength,missingCases,missingFeatures]<=1), ...
                'NMSynthPopulationGenerator:proportion','Invalid batch/missingness fractions.');
            if strcmp(mode,'regression')
                assert(event==0 && K==1,'NMSynthPopulationGenerator:regression', ...
                    'Regression requires one target and EventProb=0.');
            else
                assert(strcmp(mode,'classification') && K>=2 && ...
                    K==floor(K),'NMSynthPopulationGenerator:task', ...
                    'Only binary/multiclass classification or regression are supported.');
                if K==2
                    nPositive=ceil(n*event);
                    assert(event>0 && event<1 && nPositive>=2 && n-nPositive>=2, ...
                        'NMSynthPopulationGenerator:event','Binary class counts must be >=2.');
                else
                    assert(event==0 && n>=2*K,'NMSynthPopulationGenerator:multiclass', ...
                        'Multiclass groups must be balanced with at least two cases each.');
                end
            end
            for m=1:M
                width=row(4*m-3);rate=row(4*m-2);low=row(4*m-1);high=row(4*m);
                validateattributes(width,{'numeric'},{'scalar','integer','positive','<=',100000});
                assert(rate>=0 && (rate<=1 || ...
                    (rate==floor(rate) && rate<=width)), ...
                    'NMSynthPopulationGenerator:markers','Invalid predictive-marker specification.');
                if strcmp(mode,'regression')
                    valid=0<=low && low<=high && high<1;
                else
                    valid=0.5<=low && low<=high && high<1;
                end
                assert(valid,'NMSynthPopulationGenerator:signalRange', ...
                    'Invalid AUC/correlation range for the selected task.');
            end
        end

        function data = generate(plan,row,combinationIndex,repetitionIndex)
            M=numel(plan.definition.modalityNames);
            mode=plan.definition.modeflag;
            K=plan.definition.classCount;
            f=reshape(row(1:4*M),4,M);
            n=row(4*M+1); event=row(4*M+2); batches=row(4*M+3);
            strength=row(4*M+4); missingCases=row(4*M+5); missingFeatures=row(4*M+6);
            NMSynthPopulationGenerator.validateRow(plan,row);
            seed=double(plan.seed)+(combinationIndex-1)*double(plan.NReps)+repetitionIndex-1;
            stream=RandStream('mt19937ar','Seed',seed);
            if strcmp(mode,'regression')
                label=(1:n)';
                z=(label-mean(label))/std(label);
                groups={};
            else
                if K==2
                    counts=[ceil(n*event),n-ceil(n*event)];
                else
                    counts=accumarray(mod((0:n-1)',K)+1,1,[K 1])';
                end
                assert(all(counts>=2),'NMSynthPopulationGenerator:classCount', ...
                    'Each classification group requires at least two cases.');
                label=repelem((1:K)',counts(:));
                groups=arrayfun(@(i)sprintf('Group %d',i),1:K,'UniformOutput',false);
            end
            batch=zeros(n,1);
            if batches>1
                order=randperm(stream,n);
                batch(order)=mod(0:n-1,batches)+1;
            end
            Y=cell(1,M); names=cell(1,M);
            for m=1:M
                width=f(1,m); rate=f(2,m); low=f(3,m); high=f(4,m);
                if rate<=1, nMarkers=ceil(width*rate);else,nMarkers=rate;end
                X=randn(stream,n,width);
                if nMarkers>0
                    if nMarkers==1, targets=(low+high)/2;
                    elseif nMarkers<5, targets=linspace(low,high,nMarkers);
                    else, targets=nk_ExpVec(low,high,nMarkers);end
                    for j=1:nMarkers
                        t=targets(j);
                        if strcmp(mode,'regression')
                            X(:,j)=t*z+sqrt(1-t*t)*randn(stream,n,1);
                        elseif K==2
                            L=ones(n,1);L(label==2)=-1;
                            X(:,j)=nk_CreatPredFeat(t,t,L,false,stream);
                        else
                            delta=2*erfinv(2*t-1);
                            X(:,j)=delta*(double(label)-mean(1:K))+randn(stream,n,1);
                        end
                    end
                end
                X=X(:,randperm(stream,width));
                if batches>1 && strength>0
                    % BatchPerc is defined relative to each generated feature range.
                    featureRange=max(X,[],1)-min(X,[],1);
                    offsets=(2*rand(stream,batches,1)-1)*strength;
                    for b=1:batches
                        rows=batch==b;
                        X(rows,:)=X(rows,:)+rand(stream,nnz(rows),width).* ...
                            (offsets(b)*featureRange);
                    end
                end
                missingRowCount=ceil(missingCases*n);
                missingColCount=ceil(missingFeatures*width);
                if missingRowCount>0 && missingColCount>0
                    affected=randperm(stream,n,missingRowCount);
                    for r=affected
                        cols=randperm(stream,width,missingColCount);
                        X(r,cols)=NaN;
                    end
                end
                Y{m}=X;
                names{m}=arrayfun(@(j)sprintf('Feature_%06d',j), ...
                    1:width,'UniformOutput',false);
            end
            cases=arrayfun(@(i)sprintf('SYNTH_%06d',i),1:n,'UniformOutput',false)';
            data=struct('Y',{Y},'label',label,'cases',{cases}, ...
                'featnames',{names},'groupnames',{groups},'seed',seed, ...
                'combinationIndex',combinationIndex,'repetitionIndex',repetitionIndex, ...
                'factors',row);
        end
    end
end
