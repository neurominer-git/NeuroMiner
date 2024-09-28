function [rs, ds] = nk_GetTestPerf_GRDBST(~, tXtest, ~, md, ~, ~)
global MODEFL MODELDIR

%ds = SQBMatrixPredict( md, single(tXtest));
switch MODEFL
    case 'classification'
        model = md; 
        predictions = model.predict(tXtest);
        probabilities = model.predict_proba(tXtest);
        rs = double(predictions);
        votes = double(probabilities);

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
            predictions = model.predict(tXtest);
            % results_file = pyrunfile('cv_py_regRF_predict.py', ...
            %     'results_file', model_name = md, test_feat = tXtest, ...
            %     rootdir = MODELDIR);
            % results = load(char(results_file));
            rs = double(predictions);
            ds = rs; 
end
