function [data, labels, covars] = cv_SynthGaussianCopula(realData, realLabels, realCovars, IN)

if ~exist("IN","var") || isempty(IN)

    %IN.NRanalysis = 1;
    numSyntheticObservations = 100;
    %IN.add2orig = 0;
    %IN.NReps = 10;
    %IN.SitesIdx = 0;
    %IN.condIdx = -1;

else
    numSyntheticObservations = IN.numSyntheticObservations;
end

% Initialize variables to store the synthetic data and labels (& covars)
if length(numSyntheticObservations) > 1
    synteticData = zeros(sum(numSyntheticObservations), size(realData, 2));
    syntheticLabels = zeros(sum(numSyntheticObservations), 1);
else
    syntheticData = zeros(numSyntheticObservations, size(realData, 2));
    syntheticLabels = zeros(numSyntheticObservations, 1);
end

if ~isempty(realCovars)
    syntheticCovars = zeros(numSyntheticObservations, size(realCovars,2));
else
    syntheticCovars = [];
end
fprintf('\nGenerating synthetic data using Gaussian Copula functions.');
fprintf('\n\tNo. of synthetic observations: %g\n', numSyntheticObservations);

% Do we need to standardize the data?
% if std_flag == 1
%     fprintf('\nStandardizing data')
%     std_realData = nk_PerfStandardizeObj(realData);
% else
%     std_realData = realData;
% end


dRealData = size(realData,2);
if ~isempty(realCovars)
    dRealCovars = size(realCovars,2);
    realData= [realData realCovars realLabels];
    uXC = nk_CountUniques(realCovars);
else
    realData = [realData realLabels];
    dRealCovars = 0;
end
    % Define column names
columnNames = IN.YColNames;
columnNames{length(columnNames)+1} = 'label';


uXL = nk_CountUniques(realLabels);

%% TO DO: missing data --> impute

%% Gaussian Copula synthesizer code

% Convert the MATLAB array to a pandas DataFrame
realData_tab = array2table(realData, 'VariableNames', columnNames);

if ~isMATLABReleaseOlderThan('R2024a', 'release')


    metadata = py.sdv.metadata.SingleTableMetadata();
    metadata.detect_from_dataframe(realData_tab);

    % preallocate space for simulated dataset
    %sim_sample = py.pandas.DataFrame(columns = realData_tab.columns);

    % constraints
    constraints = py.list();

    % keep relationship between outer and inner leave-one-group-out categorization the same
    if isfield(IN, 'cv1lco') && isfield(IN, 'cv2lco') && IN.cv1lco > 0 && IN.cv2lco > 0
        fixed_cvlco_constraint = py.sdv.constraints.FixedConstrained(column_names = ['CV1LCO', 'CV2LCO']);
        constraints.append(fixed_cvlco_constraint);
    end

    % consider dummy-coded sites
    if isfield(IN, 'sitesCols') && ~isnumeric(IN.sitesCols)
        sitesColsPy = IN.sitesCols - 1;
        auxSitesColsNames = realData_tab.columns(sitesColsPy);

        sites_constraint = py.dict(pyargs('constraint_class', 'OneHotEncoding', 'constraint_parameters', py.dict(pyargs('column_names', auxSitesColsNames))));
        disp(sites_constraint);
        constraints.append(sites_constraint);
    end


    model = py.svd.single_table.GaussianCopulaSynthesizer(metadata);
    model.add_constraints(constraints = constraints);
    model.fit(realData_tab);

    % conditions
    print(len(condVals))
    if size(condVals,2) > 0
        condition = py.pandas.DataFrame({condColName : condVals});%, num_rows = condN)
        sim_sample = model.sample_remaining_columns(condition);
    else
        sim_sample = model.sample(n_obs);
    end


    % Convert the pandas DataFrame to a MATLAB array
    matlabCell = cell(sim_sample.values.tolist());
    syntheticDataCovarsLabels = cell2mat(matlabCell);

    fprintf('\nDone!\n')
else
    
    origDataFile = sprintf('%s/origData.csv',IN.analrootdir);
    writetable(realData_tab, origDataFile);


    M_file = pyrunfile('py_simulate_data2.py', 'out_path', ...
        data_file = origDataFile, ...
        n_obs = int64(IN.numSyntheticObservations), ... % if vector, then n observations to be simulated within each group (defined by label)
        cv1lco = int64(IN.cv1lcoIdx), ... % vector of
        cv2lco = int64(IN.cv2lcoIdx), ...
        sitesCols = int64(IN.sitesIdxY), ... % must have length > 1 (dummy coded sites), otherwise discarded
        condVals = int64(IN.condGroupVec), ... % vector that has length = n-to-simulate (nc)
        condColName = IN.condName, ... % column name of the variable that provides groups for special sampling % condCol = int64(condIdxY), ...
        rootdir = IN.analrootdir);
    toc
    syntheticDataCovarsLabels = readtable(py2mat(M_file));

    
end




% Extract covariates
if ~isempty(realCovars)
    % Extract synthetic data
    syntheticData = syntheticDataCovarsLabels(:,1:dRealData);

    syntheticCovars = syntheticDataCovarsLabels(:,dRealData+1:dRealData+dRealCovars);
    rIdx = find(uXC.U<10); % is this a check whether it is ca
    if ~isempty(rIdx)
        for i=1:numel(rIdx)
            if size(uXC.UX{rIdx(i)},1) == 1
                syntheticCovars(:,rIdx(i)) = repelem(uXC.UX{rIdx(i)}, numSyntheticObservations);

            else
                syntheticCovars(:,rIdx(i)) = interp1(uXC.UX{rIdx(i)},uXC.UX{rIdx(i)},syntheticCovars(:,rIdx(i)),'nearest','extrap');

            end
        end
    end
    covars = table2array(syntheticCovars);

else % no covariates (currently always since covariates are handled in nk_SimulateML
    
    syntheticData = syntheticDataCovarsLabels(:,1:end-1);
    covars = [];
end

% Extract the synthetic labels
syntheticLabels = syntheticDataCovarsLabels(:, dRealData+dRealCovars+1:end);
syntheticLabels = table2array(syntheticLabels);

% next part prob irrelevant

if ~strcmp(IN.condName, 'label')
    rIdx = find(uXL.U<10);
    if ~isempty(rIdx)
        for i=1:numel(rIdx)
            syntheticLabels(:,rIdx(i)) = interp1(uXL.UX{rIdx(i)},uXL.UX{rIdx(i)},syntheticLabels(:,rIdx(i)),'nearest','extrap');
        end
    end
end

% Combine the real and synthetic data and labels
data = table2array(syntheticData);
labels = syntheticLabels;

    
end