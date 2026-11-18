(function(global){
  'use strict';
  const DEFINITIONS=Object.freeze([
    {id:'feature.metric_bar',label:'Bar',supports:['tabular'],adapterId:'feature.metric_bar',viewModes:['bar']},
    {id:'imaging.2d',label:'2-D planes',supports:['voxel_field','roi_field'],roiSpatialDomains:['volume'],adapterId:'imaging.2d',viewModes:['current','canonical','montage']},
    {id:'imaging.3d.surface',label:'3-D surface',supports:['voxel_field','roi_field'],roiSpatialDomains:['volume'],adapterId:'imaging.3d',entryMode:'surface_projection',viewModes:['current','canonical','montage']},
    {id:'imaging.3d.volume',label:'3-D volume',supports:['voxel_field','roi_field'],roiSpatialDomains:['volume'],adapterId:'imaging.3d',entryMode:'volume_raycast',viewModes:['current','canonical','montage']},
    {id:'imaging.3d.surface_data',label:'3-D surface-data',supports:['surface_field','roi_field'],roiSpatialDomains:['surface'],adapterId:'imaging.3d',entryMode:'surface_projection',viewModes:['current','canonical','montage']},
    {id:'connectivity.matrix',label:'Matrix',supports:['connectivity'],adapterId:'connectivity.matrix',viewModes:['current']},
    {id:'connectivity.network',label:'Topology / ring',supports:['connectivity'],adapterId:'connectivity.network',viewModes:['current']},
    {id:'connectivity.glass_brain',label:'3-D glass brain',supports:['connectivity'],adapterId:'connectivity.glass_brain',viewModes:['current','canonical','montage']},
    {id:'roi.spider',label:'ROI Mapper',role:'comparative_analysis',supports:['voxel_field','surface_field','roi_field'],adapterId:'roi.spider',viewModes:['current']}
  ]);
  function text(v){return String(v==null?'':v).trim();}
  function arr(v){return Array.isArray(v)?v:(v==null?[]:[v]);}
  function supportDomain(featureKinds,context){const explicit=text(context&&context.supportDomain).toLowerCase();if(explicit==='roi_field')return context&&context.roiSidecarAvailable===true?'roi_field':'tabular';if(['voxel_field','surface_field','connectivity','tabular'].includes(explicit))return explicit;const kinds=Array.from(new Set(arr(featureKinds).map(x=>text(x).toLowerCase()).filter(Boolean)));if(kinds.length&&kinds.every(k=>k==='voxel'))return 'voxel_field';if(kinds.length&&kinds.every(k=>k==='surface_vertex'))return 'surface_field';if(kinds.length&&kinds.every(k=>k==='connectivity_edge'))return 'connectivity';if(kinds.length&&kinds.every(k=>k==='roi_field'||k==='roi'))return context&&context.roiSidecarAvailable===true?'roi_field':'tabular';return 'tabular';}
  function frontend(domain){return domain==='voxel_field'||domain==='surface_field'||domain==='roi_field'?'imaging':(domain==='connectivity'?'connectivity':'tabular');}
  function representations(domain,options){const o=options||{},roiDomain=text(o.roiSpatialDomain).toLowerCase();return DEFINITIONS.filter(d=>{if(!d.supports.includes(domain))return false;if(domain!=='roi_field')return true;return !d.roiSpatialDomains||d.roiSpatialDomains.includes(roiDomain);}).map(d=>Object.assign({},d,{supports:d.supports.slice(),roiSpatialDomains:arr(d.roiSpatialDomains).slice(),viewModes:d.viewModes.slice()}));}
  function definition(id){const d=DEFINITIONS.find(row=>row.id===text(id));return d?Object.assign({},d,{supports:d.supports.slice(),roiSpatialDomains:arr(d.roiSpatialDomains).slice(),viewModes:d.viewModes.slice()}):null;}
  function canonicalViews(id){const d=definition(id);if(!d)return[];if(d.adapterId==='imaging.2d')return['axial','coronal','sagittal'];if(d.adapterId==='imaging.3d'||d.adapterId==='connectivity.glass_brain')return['anterior','posterior','left','right','superior','inferior'];return[];}
  global.NMResultsViewerFeatureRepresentations=Object.freeze({DEFINITIONS,supportDomain,frontend,representations,definition,canonicalViews});
})(typeof window!=='undefined'?window:globalThis);
