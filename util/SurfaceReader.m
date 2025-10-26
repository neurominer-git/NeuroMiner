function [d, v] = SurfaceReader(filename)

[~,~,e] = fileparts(deblank(filename));
switch e
    case {'.mgh','.mgz'}
        d = MRIread(filename); v = d.vol;
    case '.gii'
        d = GIIread(filename); 
        if ~isnumeric(d.cdata)
            v = d.cdata(1:end)';
        else
            v = d.cdata'; 
        end
    otherwise
        error('Do not know how to process surface files with %s extension',e)
end