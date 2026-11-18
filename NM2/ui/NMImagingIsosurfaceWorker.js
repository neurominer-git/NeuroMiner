'use strict';
importScripts('NMResultsViewerPrimitives.js','NMImagingDisplaySemantics.js','NMImagingIsosurface.js');
self.onmessage=function(event){
  const message=event.data||{};
  try{
    const result=self.NMImagingIsosurface.build(message.input||{}),transfer=[];
    ['positive','negative'].forEach(key=>{transfer.push(result[key].vertices.buffer,result[key].indices.buffer);});
    self.postMessage({ok:true,generation:message.generation,result},transfer);
  }catch(err){self.postMessage({ok:false,generation:message.generation,message:err&&err.message||String(err)});}
};
