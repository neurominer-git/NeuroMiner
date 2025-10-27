function Perf = nk_MultiPerfQuant(expected, predicted, modus)

nsubj = numel(expected);
ngroups = unique(expected(~isnan(expected)));
inanp = isnan(predicted);
inane = isnan(expected);
nG = numel(ngroups);

switch modus
    case 0 % Multi-class accuracy
        errs = predicted ~= expected;
        Perf= ( 1 - sum(errs)/ nsubj) * 100;
    case 1 % Mean One-vs-Rest BAC
        Perfi = zeros(nG,1); 
        for i = 1:nG
            expi=-1*ones(size(expected)); predi=-1*ones(size(expected));
            indp = predicted == ngroups(i); inde = expected == ngroups(i);
            expi(inde)=1; predi(indp)=1;
            expi(inane)=NaN; predi(inanp)=NaN;
            Perfi(i) = BAC(expi,predi);
        end
        Perf = mean(Perfi);
    case 2 % TMR
        confmatrix = nk_ComputeConfMatrix(expected, predicted, nG);
        Perf = nk_MultiClassRatio2Random(confmatrix);
end
