function param = pLR(expected, predicted)

if isempty(expected), param = []; return; end
ind0 = expected ~=0;
expected = expected(ind0); 
predicted = predicted(ind0);
TP = sum( predicted > 0 & expected > 0 );
FP = sum( predicted > 0 & expected < 0 );
TN = sum( predicted < 0 & expected < 0 );
FN = sum( predicted < 0 & expected > 0 );

sensitivity = TP / ( TP + FN );
specificity = TN / ( TN + FP );

param = sensitivity / (1-specificity);

if ~isfinite(param), param = 0; end