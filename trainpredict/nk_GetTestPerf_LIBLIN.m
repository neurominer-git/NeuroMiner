function [rs, ds] = nk_GetTestPerf_LIBLIN(~, tXtest, Ytest, md, ~, ~)
global SVM

% Check whether a posthoc calibration model needs to be applied to test estimates
if isfield(md,'BBQ') && ~SVM.LIBLIN.b 
    [~, ~, PTE] = predict_liblin247(Ytest, sparse(tXtest), md.md, sprintf(' -b %g -q',SVM.LIBLIN.b)); 
    nclass = numel(md.md.Label);
    if nclass>2
        ds = zeros(size(Ytest,1), numel(md.md.Labels));
        rs = ds;
        for i=1:nclass
            PTE = exp(PTE(:,i))./(1+exp(PTE(:,i))); 
            predict_test_calib = predictBBQ(md.BBQ,PTE,0);  
            rs(:,i) = sign(predict_test_calib-.5); ds(:,i) = predict_test_calib;
        end
    else
        PTE = exp(PTE(:,1))./(1+exp(PTE(:,1))); 
        predict_test_calib = predictBBQ(md.BBQ,PTE,0);  
        rs = sign(predict_test_calib-.5); ds = predict_test_calib;
    end
else
    [err_test, ~, predict_test] = predict_liblin247(Ytest, sparse(tXtest), md, sprintf(' -b %g -q',SVM.LIBLIN.b )); 
    nclass = numel(md.Label);
    if nclass>2
       ds = predict_test;
       rs = zeros(size(ds));
       idx = (1:size(rs,1))';
       rs(sub2ind(size(rs), idx, err_test)) = 1;
    else
       ds = predict_test(:,1);
       rs = err_test; 
    end
end