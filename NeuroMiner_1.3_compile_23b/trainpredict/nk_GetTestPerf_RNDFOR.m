function [rs, ds] = nk_GetTestPerf_RNDFOR(~, tXtest, ~, md, ~, ~)
global MODEFL MODELDIR
    
    switch MODEFL
        case 'classification'
            %[rs, votes] = classRF_predict(tXtest,md); 
            model = md;
            predictions = model.predict(tXtest);
            probabilities = model.predict_proba(tXtest);
            rs = double(predictions);
            votes = double(probabilities);

%             results_file = pyrunfile('cv_py_classRF_predict.py', ...
%                 'results_file' , model_name = md, test_feat =tXtest, ...
%                 rootdir = MODELDIR); 
%             results = load(char(results_file));
%             rs = results.predictions;
%             votes = results.probabilities;
            ds = votes(:,2)./sum(votes,2);
        case 'regression'
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
end
