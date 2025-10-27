function id = nk_ExtractID(nam, ext)

%idstr = regexp([nam ext],'_ID.*\.','match');
%id = idstr{1}(4:end-1);
idpos = regexp(nam,'ID\d\d\d\d\d\d_\d\d\d\d\d');
if isempty(idpos)
    idpos = regexp(nam,'ID\d\d\d\d\d_\d\d\d\d\d');
    id = nam(idpos+2:idpos+12);
else
    id = nam(idpos+2:idpos+13);
end
