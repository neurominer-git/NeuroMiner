function [rs, ds] = nk_GetTestPerf_RNDFOR(~, tXtest, ~, md, ~, ~)
global MODEFL
    
    switch MODEFL
        case 'classification'
            model = md;
            %Get predictions and probabilities.
            if size(tXtest,1) == 1 && size(tXtest,2) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
            elseif size(tXtest, 2) == 1 
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
            elseif size(tXtest, 1) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
                votes = double(model.predict_proba(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
            else
                rs = double(model.predict(tXtest).data);
                votes = double(model.predict_proba(tXtest).data);
            end
            ds = votes(:,2)./sum(votes,2);
        case 'regression'
            model = md; 
            %Get predictions. 
            if size(tXtest,1) == 1 && size(tXtest,2) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(1))).data);
            elseif size(tXtest, 2) == 1 
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(-1), int64(1))).data);
            elseif size(tXtest, 1) == 1
                rs = double(model.predict(py.numpy.array(tXtest).reshape(int64(1), int64(-1))).data);
            else
                rs = double(model.predict(double(tXtest)).data);
            end
            ds = rs;
    end
end
