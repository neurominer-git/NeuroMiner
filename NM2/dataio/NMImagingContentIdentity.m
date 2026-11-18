classdef NMImagingContentIdentity
% NMImagingContentIdentity
% -------------------------------------------------------------------------
% Deterministic content hashing for numeric imaging assets. The class
% has one responsibility: convert canonical numeric/logical array content,
% class, and shape into a stable compact identity. It performs no file IO,
% scientific transformation, rendering, or NM access.
%
% Documentation: docs/NMImagingContentIdentityContract.md
% -------------------------------------------------------------------------

    methods (Static)
        function id = hashText(value)
            % hashText  Hash one scalar text identity as UTF-8 bytes.
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                error('NMImagingContentIdentity:InvalidText', ...
                    'Content text identity requires one character vector or string scalar.');
            end
            bytes = unicode2native(char(string(value)),'UTF-8');
            id = NMImagingContentIdentity.hashBytes(uint8(bytes));
        end

        function id = fileFingerprint(fileName)
            % fileFingerprint  Build a compact identity from one resolved file and volume suffix.
            fileName = char(string(fileName));
            if isempty(strtrim(fileName))
                error('NMImagingContentIdentity:EmptyFileName', ...
                    'File fingerprints require a nonempty filename.');
            end
            token = regexp(fileName,',([0-9]+)$','tokens','once');
            volumeIndex = 1;
            if ~isempty(token), volumeIndex = str2double(token{1}); end
            base = regexprep(fileName,',\d+$','');
            canonical = base;
            try
                canonical = char(java.io.File(base).getCanonicalPath());
            catch
                canonical = base;
            end
            info = dir(base);
            if isempty(info)
                identity = sprintf('missing|%s|volume=%d',canonical,volumeIndex);
            else
                info = info(1);
                identity = sprintf('file|%s|volume=%d|bytes=%d|datenum=%.17g', ...
                    canonical,volumeIndex,double(info.bytes),double(info.datenum));
            end
            id = NMImagingContentIdentity.hashText(identity);
        end

        function id = hashArray(data, storageClass)
            % hashArray  Hash one real numeric/logical array in column-major order.
            if nargin < 2 || isempty(storageClass), storageClass = class(data); end
            if ~(isnumeric(data) || islogical(data)) || ~isreal(data)
                error('NMImagingContentIdentity:InvalidArray', ...
                    'Content identity accepts only real numeric or logical arrays.');
            end
            storageClass = lower(strtrim(char(string(storageClass))));
            switch storageClass
                case {'single','float32'}
                    normalized = single(data);
                    storageClass = 'single';
                case {'double','float64'}
                    normalized = double(data);
                    storageClass = 'double';
                case 'uint8'
                    normalized = uint8(data);
                case 'uint16'
                    normalized = uint16(data);
                case 'uint32'
                    normalized = uint32(data);
                case 'logical'
                    normalized = uint8(logical(data));
                    storageClass = 'logical';
                otherwise
                    error('NMImagingContentIdentity:UnsupportedStorageClass', ...
                        'Unsupported content-identity storage class "%s".',storageClass);
            end
            if isfloat(normalized)
                normalized(isnan(normalized)) = cast(NaN,'like',normalized);
            end
            [~,~,endian] = computer;
            if endian == 'B' && ~isa(normalized,'uint8')
                normalized = swapbytes(normalized);
            end
            header = uint8(sprintf('%s|%s|',storageClass,mat2str(size(normalized))));
            bytes = typecast(normalized(:),'uint8');
            id = NMImagingContentIdentity.hashBytes([header(:);bytes(:)]);
        end
    end

    methods (Static, Access = private)
        function id = hashBytes(bytes)
            bytes = uint8(bytes(:));
            id = [NMImagingContentIdentity.fnv32(bytes,uint32(2166136261)) ...
                  NMImagingContentIdentity.fnv32(bytes,uint32(3339675911))];
        end

        function txt = fnv32(bytes,seed)
            h = seed;
            prime = uint64(16777619);
            modulus = uint64(4294967296);
            for ii=1:numel(bytes)
                h = bitxor(h,uint32(bytes(ii)));
                h = uint32(mod(uint64(h)*prime,modulus));
            end
            txt = lower(dec2hex(h,8));
        end
    end
end
