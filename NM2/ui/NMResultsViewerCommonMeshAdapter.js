/**
 * NMResultsViewerCommonMeshAdapter
 * -------------------------------------------------------------------------
 * Purpose
 *   Runtime validator and adapter for contract NM-RV-COMMON-MESH-RO-V1.
 *   It is the narrow boundary immediately before NMWebGLMeshRenderer.setMesh.
 *
 * Scientific scope
 *   The adapter validates renderer-ready geometry and attributes that have
 *   already been resolved by a provenance-specific backend. It does not read
 *   NM structures, discover artifacts, establish mesh correspondence, map
 *   values between meshes, rasterize surfaces, or apply TFLSE.
 *
 * Current consumers
 *   Stage 3 activates installFlat for the existing subject surface-QC mesh.
 *   Volumetric imaging continues to call setMesh directly in this stage; its
 *   descriptors are covered by adapter fixtures without changing execution.
 *
 * Public browser contract
 *   validate(renderObject)                  Validate a logical V1 object.
 *   logicalFromFlat(id,mesh,style,metadata) Adapt an existing flat input.
 *   validateFlat(id,mesh,style,metadata)    Validate without installation.
 *   flatten(renderObject)                   Map V1 object to flat renderer input.
 *   install(renderer,renderObject)          Validate and install logical input.
 *   installFlat(renderer,id,mesh,style,metadata)
 *                                            Validate and forward the original
 *                                            mesh/style references unchanged.
 *
 * Ownership and lifecycle
 *   The adapter owns no DOM nodes, WebGL contexts, buffers, textures, workers
 *   or caches. The caller and NMWebGLMeshRenderer retain existing ownership.
 *
 * Failure behavior
 *   Invalid contracts throw Error objects with stable identifiers prefixed
 *   NMResultsViewerCommonMeshAdapter:. There are no silent fallbacks.
 * -------------------------------------------------------------------------
 */
(function(global){
  'use strict';

  const CONTRACT_ID='NM-RV-COMMON-MESH-RO-V1';
  const SCHEMA='nm-results-viewer-common-mesh-render-object';
  const SCHEMA_VERSION=1;
  const VOLUMETRIC_FIELDS=Object.freeze([
    'fragmentVolume','projectionAlphaVolume','structuralVolume',
    'raycastStructuralVolume','atlasVolume','preparedVolume3D'
  ]);

  function fail(identifier,message){
    const error=new Error(message);
    error.name='NMResultsViewerCommonMeshAdapterError';
    error.identifier=identifier;
    error.code=identifier;
    throw error;
  }
  function object(value){return value&&typeof value==='object'&&!Array.isArray(value)?value:null;}
  function string(value){return String(value===undefined||value===null?'':value).trim();}
  function arrayLike(value){return Array.isArray(value)||(typeof ArrayBuffer!=='undefined'&&ArrayBuffer.isView&&ArrayBuffer.isView(value));}
  function requireString(value,field){const out=string(value);if(!out)fail('NMResultsViewerCommonMeshAdapter:MissingIdentity',`${field} must be a non-empty stable identifier.`);return out;}
  function requireObject(value,field){const out=object(value);if(!out)fail('NMResultsViewerCommonMeshAdapter:InvalidObject',`${field} must be an object.`);return out;}
  function requireArrayLike(value,field){if(!arrayLike(value))fail('NMResultsViewerCommonMeshAdapter:InvalidArray',`${field} must be an Array or typed array.`);return value;}
  function requireFiniteArray(value,field,multiple,minLength){
    const out=requireArrayLike(value,field),length=Number(out.length||0);
    if(length<minLength||length%multiple!==0)fail('NMResultsViewerCommonMeshAdapter:InvalidArrayLength',`${field} must contain at least ${minLength} values and its length must be divisible by ${multiple}.`);
    for(let i=0;i<length;i++)if(!Number.isFinite(Number(out[i])))fail('NMResultsViewerCommonMeshAdapter:NonFiniteGeometry',`${field} contains a non-finite value at index ${i}.`);
    return out;
  }
  function validateIndices(indices,nVertices){
    const out=requireArrayLike(indices,'geometry.indices'),length=Number(out.length||0);
    if(length<3||length%3!==0)fail('NMResultsViewerCommonMeshAdapter:InvalidIndexLength','geometry.indices must contain complete indexed triangles.');
    for(let i=0;i<length;i++){
      const value=Number(out[i]);
      if(!Number.isInteger(value)||value<0||value>=nVertices)fail('NMResultsViewerCommonMeshAdapter:InvalidIndex',`geometry.indices[${i}] is outside the zero-based vertex range.`);
    }
    return out;
  }
  function validateBounds(bounds){
    if(bounds===undefined||bounds===null)return null;
    const source=requireObject(bounds,'geometry.bounds');
    ['min','max'].forEach(field=>{
      const values=requireArrayLike(source[field],`geometry.bounds.${field}`);
      if(values.length!==3)fail('NMResultsViewerCommonMeshAdapter:InvalidBounds',`geometry.bounds.${field} must contain three coordinates.`);
      for(let i=0;i<3;i++)if(!Number.isFinite(Number(values[i])))fail('NMResultsViewerCommonMeshAdapter:InvalidBounds',`geometry.bounds.${field} contains a non-finite coordinate.`);
    });
    if(source.center!==undefined){
      const center=requireArrayLike(source.center,'geometry.bounds.center');
      if(center.length!==3||Array.from(center).some(value=>!Number.isFinite(Number(value))))fail('NMResultsViewerCommonMeshAdapter:InvalidBounds','geometry.bounds.center must contain three finite coordinates.');
    }
    if(source.radius!==undefined&&(!Number.isFinite(Number(source.radius))||Number(source.radius)<=0))fail('NMResultsViewerCommonMeshAdapter:InvalidBounds','geometry.bounds.radius must be positive and finite.');
    return source;
  }
  function validateAttribute(attribute,name,nVertices,components,allowNonFinite){
    if(attribute===undefined||attribute===null)return null;
    const source=requireObject(attribute,`attributes.${name}`);
    if(string(source.domain)!=='vertex')fail('NMResultsViewerCommonMeshAdapter:UnsupportedAttributeDomain',`attributes.${name}.domain must be vertex in V1.`);
    const values=requireArrayLike(source.values,`attributes.${name}.values`),expected=nVertices*components;
    if(values.length!==expected)fail('NMResultsViewerCommonMeshAdapter:AttributeLengthMismatch',`attributes.${name}.values must contain exactly ${expected} values for ${nVertices} vertices.`);
    let nonFiniteCount=0;
    for(let i=0;i<values.length;i++)if(!Number.isFinite(Number(values[i])))nonFiniteCount++;
    if(nonFiniteCount&&!allowNonFinite)fail('NMResultsViewerCommonMeshAdapter:NonFiniteAttribute',`attributes.${name}.values contains ${nonFiniteCount} non-finite values.`);
    return {source,values,nonFiniteCount};
  }
  function validateVolumetricExtension(extension){
    if(extension===undefined||extension===null)return null;
    const source=requireObject(extension,'extensions.volumetric');
    Object.keys(source).forEach(key=>{
      if(VOLUMETRIC_FIELDS.indexOf(key)<0)fail('NMResultsViewerCommonMeshAdapter:UnsupportedVolumetricField',`extensions.volumetric.${key} is not part of the V1 runtime mapping.`);
    });
    return source;
  }
  function validate(renderObject){
    const source=requireObject(renderObject,'renderObject');
    if(string(source.schema)!==SCHEMA)fail('NMResultsViewerCommonMeshAdapter:InvalidSchema',`renderObject.schema must be ${SCHEMA}.`);
    if(Number(source.schemaVersion)!==SCHEMA_VERSION)fail('NMResultsViewerCommonMeshAdapter:InvalidSchemaVersion','renderObject.schemaVersion must be 1.');
    const objectId=requireString(source.objectId,'objectId');
    const geometry=requireObject(source.geometry,'geometry');
    const geometryId=requireString(geometry.geometryId,'geometry.geometryId');
    if(string(geometry.primitive)!=='triangles')fail('NMResultsViewerCommonMeshAdapter:UnsupportedPrimitive','geometry.primitive must be triangles in V1.');
    const coordinateSpace=requireString(geometry.coordinateSpace,'geometry.coordinateSpace');
    const vertices=requireFiniteArray(geometry.vertices,'geometry.vertices',3,9),nVertices=vertices.length/3;
    const indices=validateIndices(geometry.indices,nVertices);
    if(geometry.normals!==undefined&&geometry.normals!==null){
      const normals=requireFiniteArray(geometry.normals,'geometry.normals',3,vertices.length);
      if(normals.length!==vertices.length)fail('NMResultsViewerCommonMeshAdapter:NormalLengthMismatch','geometry.normals must contain one normal per vertex.');
    }
    validateBounds(geometry.bounds);
    const attributes=object(source.attributes)||{};
    Object.keys(attributes).forEach(key=>{if(['scalar','rgb','alpha'].indexOf(key)<0)fail('NMResultsViewerCommonMeshAdapter:UnsupportedAttribute',`attributes.${key} is not supported by V1.`);});
    const scalar=validateAttribute(attributes.scalar,'scalar',nVertices,1,true);
    const rgb=validateAttribute(attributes.rgb,'rgb',nVertices,3,false);
    const alpha=validateAttribute(attributes.alpha,'alpha',nVertices,1,false);
    const appearance=requireObject(source.appearance,'appearance');
    const picking=requireObject(source.picking,'picking');
    const elementDomain=string(picking.elementDomain||'triangle');
    if(elementDomain!=='triangle')fail('NMResultsViewerCommonMeshAdapter:UnsupportedPickingDomain','picking.elementDomain must be triangle in V1.');
    if(picking.metadataIdentity!==undefined&&picking.metadataIdentity!==null)requireString(picking.metadataIdentity,'picking.metadataIdentity');
    const provenance=requireObject(source.provenance,'provenance');
    const sourceFamily=requireString(provenance.sourceFamily,'provenance.sourceFamily');
    const sourceIdentity=requireString(provenance.sourceIdentity,'provenance.sourceIdentity');
    const provenanceGeometryId=requireString(provenance.geometryIdentity,'provenance.geometryIdentity');
    if(provenanceGeometryId!==geometryId)fail('NMResultsViewerCommonMeshAdapter:GeometryIdentityMismatch','provenance.geometryIdentity must equal geometry.geometryId.');
    const hasAttributes=!!(scalar||rgb||alpha);
    if(hasAttributes)requireString(provenance.attributeIdentity,'provenance.attributeIdentity');
    if(provenance.mappingRequired===true)requireString(provenance.mappingIdentity,'provenance.mappingIdentity');
    const extensions=requireObject(source.extensions,'extensions');
    Object.keys(extensions).forEach(key=>{if(key!=='volumetric')fail('NMResultsViewerCommonMeshAdapter:UnsupportedExtension',`extensions.${key} is not supported by V1.`);});
    const volumetric=validateVolumetricExtension(extensions.volumetric);
    return Object.freeze({
      ok:true,contractId:CONTRACT_ID,schema:SCHEMA,schemaVersion:SCHEMA_VERSION,
      objectId,geometryId,coordinateSpace,sourceFamily,sourceIdentity,
      nVertices,nTriangles:indices.length/3,
      attributes:{scalar:!!scalar,rgb:!!rgb,alpha:!!alpha,scalarNonFiniteCount:scalar?scalar.nonFiniteCount:0},
      volumetricFields:volumetric?Object.keys(volumetric):[]
    });
  }
  function logicalFromFlat(id,mesh,style,metadata){
    const sourceMesh=requireObject(mesh,'mesh'),meta=requireObject(metadata,'metadata'),attributes={};
    if(sourceMesh.values!==undefined&&sourceMesh.values!==null)attributes.scalar={domain:'vertex',values:sourceMesh.values,role:string(meta.scalarRole||'scientific_or_derived_scalar')};
    if(sourceMesh.colors!==undefined&&sourceMesh.colors!==null)attributes.rgb={domain:'vertex',values:sourceMesh.colors,role:string(meta.rgbRole||'presentation_rgb')};
    if(sourceMesh.alphas!==undefined&&sourceMesh.alphas!==null)attributes.alpha={domain:'vertex',values:sourceMesh.alphas,role:string(meta.alphaRole||'presentation_alpha')};
    const volumetric={};
    VOLUMETRIC_FIELDS.forEach(field=>{if(sourceMesh[field]!==undefined&&sourceMesh[field]!==null)volumetric[field]=sourceMesh[field];});
    return {
      schema:SCHEMA,
      schemaVersion:SCHEMA_VERSION,
      objectId:requireString(id,'objectId'),
      geometry:{
        geometryId:requireString(meta.geometryId,'metadata.geometryId'),
        primitive:'triangles',
        coordinateSpace:requireString(meta.coordinateSpace,'metadata.coordinateSpace'),
        vertices:sourceMesh.vertices,
        indices:sourceMesh.indices!==undefined?sourceMesh.indices:sourceMesh.faces,
        normals:sourceMesh.normals,
        bounds:sourceMesh.bounds
      },
      attributes,
      appearance:requireObject(style||{},'style'),
      picking:{elementDomain:'triangle',metadataIdentity:meta.pickingMetadataIdentity||null},
      provenance:{
        sourceFamily:requireString(meta.sourceFamily,'metadata.sourceFamily'),
        sourceIdentity:requireString(meta.sourceIdentity,'metadata.sourceIdentity'),
        geometryIdentity:requireString(meta.geometryId,'metadata.geometryId'),
        attributeIdentity:Object.keys(attributes).length?requireString(meta.attributeIdentity,'metadata.attributeIdentity'):null,
        mappingRequired:meta.mappingRequired===true,
        mappingIdentity:meta.mappingIdentity||null
      },
      extensions:{volumetric:Object.keys(volumetric).length?volumetric:null}
    };
  }
  function flatten(renderObject){
    const report=validate(renderObject),source=renderObject,geometry=source.geometry,attributes=source.attributes||{},volumetric=source.extensions&&source.extensions.volumetric||null;
    const mesh={vertices:geometry.vertices,indices:geometry.indices};
    if(geometry.normals!==undefined&&geometry.normals!==null)mesh.normals=geometry.normals;
    if(geometry.bounds!==undefined&&geometry.bounds!==null)mesh.bounds=geometry.bounds;
    if(attributes.scalar)mesh.values=attributes.scalar.values;
    if(attributes.rgb)mesh.colors=attributes.rgb.values;
    if(attributes.alpha)mesh.alphas=attributes.alpha.values;
    if(volumetric)VOLUMETRIC_FIELDS.forEach(field=>{if(volumetric[field]!==undefined&&volumetric[field]!==null)mesh[field]=volumetric[field];});
    return {id:source.objectId,mesh,style:source.appearance,report};
  }
  function validateFlat(id,mesh,style,metadata){
    const logical=logicalFromFlat(id,mesh,style,metadata),report=validate(logical);
    return {logical,report};
  }
  function install(renderer,renderObject){
    if(!renderer||typeof renderer.setMesh!=='function')fail('NMResultsViewerCommonMeshAdapter:InvalidRenderer','renderer.setMesh is required.');
    const flat=flatten(renderObject),installed=renderer.setMesh(flat.id,flat.mesh,flat.style);
    return {installed,report:flat.report};
  }
  function installFlat(renderer,id,mesh,style,metadata){
    if(!renderer||typeof renderer.setMesh!=='function')fail('NMResultsViewerCommonMeshAdapter:InvalidRenderer','renderer.setMesh is required.');
    const validation=validateFlat(id,mesh,style,metadata),installed=renderer.setMesh(id,mesh,style);
    return {installed,report:validation.report,logical:validation.logical};
  }

  global.NMResultsViewerCommonMeshAdapter=Object.freeze({
    contractId:CONTRACT_ID,
    schema:SCHEMA,
    schemaVersion:SCHEMA_VERSION,
    validate,
    validateFlat,
    logicalFromFlat,
    flatten,
    install,
    installFlat,
    _test:Object.freeze({VOLUMETRIC_FIELDS,arrayLike})
  });
})(typeof window!=='undefined'?window:globalThis);
