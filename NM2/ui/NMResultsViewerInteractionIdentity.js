(function(global){
  'use strict';

  /** Results Viewer interaction identity and state contracts. */

  const CONTRACT_VERSION='NM-RESULTS-VIEWER-INTERACTION-IDENTITY-V1';
  const STATE_CONTRACT_VERSION='NM-RESULTS-VIEWER-INTERACTION-STATE-V3';
  const KINDS=Object.freeze([
    'voxel',
    'surface_vertex',
    'matrix_cell',
    'connectivity_edge',
    'relation_item',
    'graph_node',
    'graph_link'
  ]);
  const PATHWAYS=Object.freeze(['imaging','connectivity','relation']);

  function identityError(code,message,details){
    const error=new Error(message);
    error.name='NMResultsViewerInteractionIdentityError';
    error.code=code;
    if(details!==undefined)error.details=details;
    return error;
  }

  function fail(code,message,details){throw identityError(code,message,details);}
  function plainObject(value){return !!value&&typeof value==='object'&&!Array.isArray(value);}
  function requireObject(value,label){if(!plainObject(value))fail('NMResultsViewerInteractionIdentity:InvalidObject',`${label} must be one plain object.`);return value;}
  function requireText(value,label){const text=String(value==null?'':value).trim();if(!text)fail('NMResultsViewerInteractionIdentity:MissingText',`${label} must be non-empty.`);return text;} // nm2-allow: NMResultsViewerInteractionIdentity.requireText validates and trims untrusted browser identity text at construction.
  function optionalText(value){const text=String(value==null?'':value).trim();return text||'';} // nm2-allow: NMResultsViewerInteractionIdentity.optionalText canonicalizes optional browser-provided identity fields at construction.
  function integer(value,label,minimum){const number=Number(value);if(!Number.isInteger(number)||number<minimum)fail('NMResultsViewerInteractionIdentity:InvalidInteger',`${label} must be an integer greater than or equal to ${minimum}.`,{label,value});return number;}
  function optionalInteger(value,label,minimum){if(value===undefined||value===null||value==='')return null;return integer(value,label,minimum);}
  function finiteVector(value,label,length){if(!Array.isArray(value)||value.length!==length)fail('NMResultsViewerInteractionIdentity:InvalidVector',`${label} must contain exactly ${length} finite numbers.`);const out=value.map(Number);if(!out.every(Number.isFinite))fail('NMResultsViewerInteractionIdentity:InvalidVector',`${label} must contain exactly ${length} finite numbers.`);return Object.freeze(out);}
  function integerVector(value,label,length,minimum){if(!Array.isArray(value)||value.length!==length)fail('NMResultsViewerInteractionIdentity:InvalidIntegerVector',`${label} must contain exactly ${length} integer values greater than or equal to ${minimum}.`);return Object.freeze(value.map((entry,index)=>integer(entry,`${label}[${index}]`,minimum)));}
  function optionalVector(value,label,length){if(value===undefined||value===null)return null;return finiteVector(value,label,length);}
  function optionalIntegerVector(value,label,length,minimum){if(value===undefined||value===null)return null;return integerVector(value,label,length,minimum);}
  function optionalField(target,name,value){if(value!==null&&value!=='')target[name]=value;}

  function sourceEnvelope(value){
    const input=requireObject(value,'Interaction source');
    const pathway=requireText(input.pathway,'Interaction source pathway');
    if(!PATHWAYS.includes(pathway))fail('NMResultsViewerInteractionIdentity:UnknownPathway',`Unsupported Results Viewer interaction pathway: ${pathway}.`,{pathway});
    const out={pathway,representation:requireText(input.representation,'Interaction source representation')};
    optionalField(out,'contextId',optionalText(input.contextId));
    optionalField(out,'panelId',optionalText(input.panelId));
    optionalField(out,'measureId',optionalText(input.measureId));
    return Object.freeze(out);
  }

  function envelope(kind,source,item){
    return Object.freeze({contractVersion:CONTRACT_VERSION,kind,source:sourceEnvelope(source),item:Object.freeze(item)});
  }

  function createVoxel(spec){
    const input=requireObject(spec,'Voxel identity');
    const item={voxel:integerVector(input.voxel,'Voxel identity voxel',3,1),worldMm:finiteVector(input.worldMm,'Voxel identity worldMm',3),indexBase:1};
    optionalField(item,'planeId',optionalText(input.planeId));
    optionalField(item,'gridId',optionalText(input.gridId));
    const linearIndex=optionalInteger(input.linearIndex,'Voxel identity linearIndex',1);optionalField(item,'linearIndex',linearIndex);
    return envelope('voxel',input.source,item);
  }

  function createSurfaceVertex(spec){
    const input=requireObject(spec,'Surface-vertex identity');
    const item={vertexIndex:integer(input.vertexIndex,'Surface-vertex identity vertexIndex',0),worldMm:finiteVector(input.worldMm,'Surface-vertex identity worldMm',3),indexBase:0};
    optionalField(item,'topologyIdentity',optionalText(input.topologyIdentity));
    optionalField(item,'vertexOrderIdentity',optionalText(input.vertexOrderIdentity));
    optionalField(item,'geometryId',optionalText(input.geometryId));
    optionalField(item,'hemisphere',optionalText(input.hemisphere));
    const sourceVoxel=optionalIntegerVector(input.sourceVoxel,'Surface-vertex identity sourceVoxel',3,1);optionalField(item,'sourceVoxel',sourceVoxel);
    const sourceWorldMm=optionalVector(input.sourceWorldMm,'Surface-vertex identity sourceWorldMm',3);optionalField(item,'sourceWorldMm',sourceWorldMm);
    return envelope('surface_vertex',input.source,item);
  }

  function createMatrixCell(spec){
    const input=requireObject(spec,'Matrix-cell identity');
    const item={row:integer(input.row,'Matrix-cell identity row',0),column:integer(input.column,'Matrix-cell identity column',0),indexBase:0,mirrored:input.mirrored===true};
    optionalField(item,'matrixId',optionalText(input.matrixId));
    optionalField(item,'rowId',optionalText(input.rowId));
    optionalField(item,'columnId',optionalText(input.columnId));
    return envelope('matrix_cell',input.source,item);
  }

  function createConnectivityEdge(spec){
    const input=requireObject(spec,'Connectivity-edge identity');
    const item={
      edgePosition:integer(input.edgePosition,'Connectivity-edge identity edgePosition',1),
      sourcePosition:integer(input.sourcePosition,'Connectivity-edge identity sourcePosition',1),
      targetPosition:integer(input.targetPosition,'Connectivity-edge identity targetPosition',1),
      positionIndexBase:1,
      mirrored:input.mirrored===true
    };
    optionalField(item,'edgeId',optionalText(input.edgeId));
    optionalField(item,'sourceNodeId',optionalText(input.sourceNodeId));
    optionalField(item,'targetNodeId',optionalText(input.targetNodeId));
    const displayRow=optionalInteger(input.displayRow,'Connectivity-edge identity displayRow',0);optionalField(item,'displayRow',displayRow);
    const displayColumn=optionalInteger(input.displayColumn,'Connectivity-edge identity displayColumn',0);optionalField(item,'displayColumn',displayColumn);
    const sourceWorldMm=optionalVector(input.sourceWorldMm,'Connectivity-edge identity sourceWorldMm',3);optionalField(item,'sourceWorldMm',sourceWorldMm);
    const targetWorldMm=optionalVector(input.targetWorldMm,'Connectivity-edge identity targetWorldMm',3);optionalField(item,'targetWorldMm',targetWorldMm);
    return envelope('connectivity_edge',input.source,item);
  }

  function createRelationItem(spec){
    const input=requireObject(spec,'Relation-item identity'),itemType=requireText(input.itemType,'Relation-item identity itemType');
    if(!['feature','pair'].includes(itemType))fail('NMResultsViewerInteractionIdentity:InvalidRelationItemType',`Unsupported relation-item type: ${itemType}.`,{itemType});
    const item={itemType,directed:input.directed===true};
    optionalField(item,'relationId',optionalText(input.relationId));
    if(itemType==='feature')item.featureId=requireText(input.featureId,'Relation feature identity featureId');
    else{item.featureIdA=requireText(input.featureIdA,'Relation-pair identity featureIdA');item.featureIdB=requireText(input.featureIdB,'Relation-pair identity featureIdB');}
    return envelope('relation_item',input.source,item);
  }

  function createGraphNode(spec){
    const input=requireObject(spec,'Graph-node identity'),item={nodeId:requireText(input.nodeId,'Graph-node identity nodeId')};
    optionalField(item,'graphId',optionalText(input.graphId));
    optionalField(item,'featureId',optionalText(input.featureId));
    return envelope('graph_node',input.source,item);
  }

  function createGraphLink(spec){
    const input=requireObject(spec,'Graph-link identity'),item={
      edgeId:requireText(input.edgeId,'Graph-link identity edgeId'),
      sourceNodeId:requireText(input.sourceNodeId,'Graph-link identity sourceNodeId'),
      targetNodeId:requireText(input.targetNodeId,'Graph-link identity targetNodeId'),
      directed:input.directed===true
    };
    optionalField(item,'graphId',optionalText(input.graphId));
    optionalField(item,'sourceFeatureId',optionalText(input.sourceFeatureId));
    optionalField(item,'targetFeatureId',optionalText(input.targetFeatureId));
    return envelope('graph_link',input.source,item);
  }

  function assertIdentity(value,expectedKinds){
    const identity=requireObject(value,'Interaction identity');
    if(identity.contractVersion!==CONTRACT_VERSION)fail('NMResultsViewerInteractionIdentity:ContractVersionMismatch',`Interaction identity contract must be ${CONTRACT_VERSION}.`,{received:identity.contractVersion});
    const kind=requireText(identity.kind,'Interaction identity kind');
    if(!KINDS.includes(kind))fail('NMResultsViewerInteractionIdentity:UnknownKind',`Unsupported Results Viewer interaction kind: ${kind}.`,{kind});
    const allowed=expectedKinds===undefined?null:(Array.isArray(expectedKinds)?expectedKinds:[expectedKinds]);
    if(allowed&&!allowed.includes(kind))fail('NMResultsViewerInteractionIdentity:UnexpectedKind',`Interaction identity kind ${kind} does not satisfy the required kind set ${allowed.join(', ')}.`,{kind,expectedKinds:allowed.slice()});
    const source=sourceEnvelope(identity.source),item=requireObject(identity.item,'Interaction identity item');
    const reconstructed={
      voxel:()=>createVoxel(Object.assign({source},item)),
      surface_vertex:()=>createSurfaceVertex(Object.assign({source},item)),
      matrix_cell:()=>createMatrixCell(Object.assign({source},item)),
      connectivity_edge:()=>createConnectivityEdge(Object.assign({source},item)),
      relation_item:()=>createRelationItem(Object.assign({source},item)),
      graph_node:()=>createGraphNode(Object.assign({source},item)),
      graph_link:()=>createGraphLink(Object.assign({source},item))
    }[kind]();
    if(!sameCanonicalValue(reconstructed,identity))fail('NMResultsViewerInteractionIdentity:InvalidIdentity','Interaction identity does not satisfy its exact typed payload contract.');
    return reconstructed;
  }

  function sameCanonicalValue(expected,received){
    if(Array.isArray(expected))return Array.isArray(received)&&expected.length===received.length&&expected.every((value,index)=>sameCanonicalValue(value,received[index]));
    if(plainObject(expected)){
      if(!plainObject(received))return false;
      const expectedKeys=Object.keys(expected).sort(),receivedKeys=Object.keys(received).sort();
      return expectedKeys.length===receivedKeys.length&&expectedKeys.every((key,index)=>key===receivedKeys[index]&&sameCanonicalValue(expected[key],received[key]));
    }
    return Object.is(expected,received);
  }

  function sourceKey(source){return [source.pathway,source.representation,source.contextId||'',source.measureId||'',source.panelId||''].map(encodeURIComponent).join('|');} // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
  function unorderedPair(a,b){return a<=b?[a,b]:[b,a];}
  function identityKeyUnchecked(identity){
    const source=identity.source,item=identity.item,prefix=`${sourceKey(source)}|${identity.kind}|`;
    if(identity.kind==='voxel')return prefix+[item.gridId||'',item.voxel.join(',')].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    if(identity.kind==='surface_vertex')return prefix+[item.topologyIdentity||item.vertexOrderIdentity||'',item.vertexIndex].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    if(identity.kind==='matrix_cell')return prefix+[item.matrixId||'',item.rowId||item.row,item.columnId||item.column].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    if(identity.kind==='connectivity_edge')return prefix+[item.edgeId||'',item.edgePosition].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    if(identity.kind==='relation_item'){
      if(item.itemType==='feature')return prefix+['feature',item.relationId||'',item.featureId].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
      const pair=item.directed?[item.featureIdA,item.featureIdB]:unorderedPair(item.featureIdA,item.featureIdB);return prefix+['pair',item.relationId||'',pair[0],pair[1],item.directed?'1':'0'].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    }
    if(identity.kind==='graph_node')return prefix+[item.graphId||'',item.nodeId].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
    return prefix+[item.graphId||'',item.edgeId].map(encodeURIComponent).join('|'); // nm2-allow: NMResultsViewerInteractionIdentity typed factories omit optional IDs; identityKeyUnchecked preserves canonical empty-field keys.
  }


  function createState(value){
    const out={contractVersion:STATE_CONTRACT_VERSION,hover:null,selected:null};if(value===undefined)return out;
    const input=requireObject(value,'Interaction state'),keys=Object.keys(input).sort().join('|');if(keys!=='contractVersion|hover|selected'||input.contractVersion!==STATE_CONTRACT_VERSION)fail('NMResultsViewerInteractionIdentity:InvalidState','Invalid interaction-state contract.');
    ['hover','selected'].forEach(field=>{out[field]=input[field]===null?null:assertIdentity(input[field]);});return out;
  }

  function identityKey(value){return identityKeyUnchecked(assertIdentity(value));}
  function sameIdentity(a,b){return identityKey(a)===identityKey(b);}

  global.NMResultsViewerInteractionIdentity=Object.freeze({
    CONTRACT_VERSION,STATE_CONTRACT_VERSION,KINDS,createVoxel,createSurfaceVertex,createMatrixCell,createConnectivityEdge,createRelationItem,createGraphNode,createGraphLink,assertIdentity,identityKey,sameIdentity,createState
  });
})(window);
