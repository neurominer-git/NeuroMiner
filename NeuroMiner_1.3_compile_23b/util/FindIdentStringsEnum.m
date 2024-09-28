function [inputCellArray, countMap] = FindIdentStringsEnum(inputCellArray)

% Create a map to store the count of each string
countMap = containers.Map;

% Loop through each string in the cell array
for i = 1:length(inputCellArray)
    currentString = inputCellArray{i};
    
    % Check if the string is already in the map
    if isKey(countMap, currentString)
        % Increment the count and append the index to the string
        countMap(currentString) = countMap(currentString) + 1;
        inputCellArray{i} = [currentString, '_', num2str(countMap(currentString))];
        % If it's not the first occurrence, go back and update the first occurrence
        if countMap(currentString) == 2
            firstOccurrenceIndex = find(strcmp(inputCellArray, currentString), 1, 'first');
            inputCellArray{firstOccurrenceIndex} = [currentString, '_1'];
        end
    else
        % Add the string to the map with count 1
        countMap(currentString) = 1;
    end
end