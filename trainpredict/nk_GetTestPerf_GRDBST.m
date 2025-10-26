function [rs, ds] = nk_GetTestPerf_GRDBST(~, tXtest, ~, md, ~, ~)
global MODEFL MODELDIR

%ds = SQBMatrixPredict( md, single(tXtest));
switch MODEFL
    case 'classification'
        model = md; 
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

        %[rs, votes] = classRF_predict(tXtest,md);
        % results_file = pyrunfile('cv_py_classGRDBST_predict.py', ...
        %     'results_file' , model_name = md, test_feat =tXtest, ...
        %     rootdir = MODELDIR);
        % results = load(char(results_file));
        % rs = results.predictions;
        % votes = results.probabilities;
        ds = votes(:,2)./sum(votes,2);
        ds = nk_CalibrateProbabilities(ds); 
    case 'regression'
        % %rs = regRF_predict(tXtest,md); ds=rs;
        % results_file = pyrunfile('cv_py_regGRDBST_predict.py', ...
        %     'results_file', model_name = md, teast_feat = tXtest, ...
        %     rootdir = MODELDIR);
        % results = load(char(results_file));
        % rs = results.predictions;
        % ds = rs;

                %rs = regRF_predict(tXtest,md); ds=rs;
        model = md;
        % results_file = pyrunfile('cv_py_regRF_predict.py', ...
        %     'results_file', model_name = md, test_feat = tXtest, ...
        %     rootdir = MODELDIR);
        % results = load(char(results_file));
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
