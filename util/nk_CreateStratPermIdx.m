function stratifiedIndices = nk_CreateStratPermIdx(labels)

classes = unique(labels); % Identify unique classes
numLabels = numel(labels); % Total number of labels
stratifiedIndices = zeros(numLabels,1); % Initialize array for stratified permutation indices

startIndex = 1; % Initialize start index for each class block in the permuted indices array

% Loop through each class to permute indices within the class
for i = 1:length(classes)
    class = classes(i); % Current class
    classIndices = find(labels == class); % Indices of labels belonging to the current class
    numClassLabels = length(classIndices); % Number of labels in the current class
    
    % Shuffle indices within this class
    permutedClassIndices = classIndices(randperm(numClassLabels));
    
    % Assign permuted class indices to the appropriate block in the output array
    stratifiedIndices(startIndex:(startIndex + numClassLabels - 1)) = permutedClassIndices;
    
    % Update start index for the next class block
    startIndex = startIndex + numClassLabels;
end
end