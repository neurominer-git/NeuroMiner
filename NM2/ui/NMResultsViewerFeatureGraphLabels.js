(function(global){
  'use strict';

  /**
   * NMResultsViewerFeatureGraphLabels  Plan deterministic graph-node labels without changing scientific graph state.
   *
   * Purpose:
   * - This module is the presentation-only label planner for Results Viewer feature-
   *   relation graphs. It ranks nodes using backend absolute-strength ranks, places
   *   labels inside a measured SVG rectangle, and reports collision diagnostics.
   *
   * Inputs and outputs:
   * - Inputs are canonical node rows plus measured browser geometry. Outputs are label
   *   selections, SVG positions, and diagnostics. The module never constructs edges,
   *   computes graph statistics, changes relation patterns, or selects graph density.
   *
   * Invariants and mutability:
   * - Stable nodeId/featureId values identify nodes.
   * - Input arrays/maps are not mutated.
   * - None suppresses labels; All is unconditional; Top N follows backend rank; Auto
   *   keeps all labels when feasible and otherwise selects a deterministic collision-
   *   aware subset.
   * - Label planning is presentation-only and excluded from scientific/cache identity.
   *
   * Errors and side effects:
   * - Functions are pure except for the exported module assignment at file load.
   * - Invalid geometry is handled through deterministic fallbacks, not silent changes
   *   to graph topology.
   *
   * RAG extraction notes:
   * - Function comments use Summary, Inputs, Returns, Invariants, and Side effects.
   */

  /** finite  Test whether a value can be converted to a finite number. Side effects: none. */
  const finite = value => Number.isFinite(Number(value));

  /** number  Convert a finite value or return the explicit fallback. Side effects: none. */
  const number = (value,fallback) => finite(value) ? Number(value) : fallback;

  /** nodeId  Resolve the stable node identity used by all label maps. Side effects: none. */
  const nodeId = node => String(node && (node.nodeId || node.featureId) || '');

  /**
   * rankNodes  Return a stable node order led by backend absolute-strength rank.
   *
   * Inputs:
   * - nodes: canonical node rows.
   * - priorityNodeIds: optional Set/array of nodes that should be considered first in
   *   Auto mode because they are currently selected or hovered.
   *
   * Returns:
   * - New sorted array. Invalid ranks follow ranked nodes and are resolved by absolute
   *   strength, stable feature index, and stable node identity.
   *
   * Invariants:
   * - The input array is never mutated.
   *
   * Side effects:
   * - None.
   */

  function rankNodes(nodes,priorityNodeIds){
    const priority=priorityNodeIds instanceof Set?priorityNodeIds:new Set(Array.isArray(priorityNodeIds)?priorityNodeIds.map(String):[]);
    return Array.isArray(nodes) ? nodes.slice().sort((a,b)=>{
      const priorityA=priority.has(nodeId(a))?0:1;
      const priorityB=priority.has(nodeId(b))?0:1;
      if(priorityA!==priorityB)return priorityA-priorityB;
      const rankA=number(a&&a.absoluteStrengthRank,Infinity);
      const rankB=number(b&&b.absoluteStrengthRank,Infinity);
      if(rankA!==rankB)return rankA-rankB;
      const strengthA=number(a&&a.absoluteStrength,-Infinity);
      const strengthB=number(b&&b.absoluteStrength,-Infinity);
      if(strengthA!==strengthB)return strengthB-strengthA;
      const indexA=number(a&&a.featureIndex,Infinity);
      const indexB=number(b&&b.featureIndex,Infinity);
      if(indexA!==indexB)return indexA-indexB;
      return nodeId(a).localeCompare(nodeId(b));
    }) : [];
  }

  /**
   * overlapArea  Compute the intersecting area of two axis-aligned label boxes.
   *
   * Returns:
   * - Non-negative overlap area.
   *
   * Side effects:
   * - None.
   */

  function overlapArea(a,b){
    return Math.max(0,Math.min(a.x2,b.x2)-Math.max(a.x1,b.x1))*
      Math.max(0,Math.min(a.y2,b.y2)-Math.max(a.y1,b.y1));
  }

  /**
   * placementCandidates  Return the fixed deterministic label-placement search order.
   *
   * Returns:
   * - Eight candidate directions with SVG text anchors.
   *
   * Side effects:
   * - None.
   */

  function placementCandidates(){
    return [
      {dx:1,dy:0,anchor:'start'}, {dx:-1,dy:0,anchor:'end'},
      {dx:1,dy:-1,anchor:'start'}, {dx:-1,dy:-1,anchor:'end'},
      {dx:1,dy:1,anchor:'start'}, {dx:-1,dy:1,anchor:'end'},
      {dx:0,dy:-1,anchor:'middle'}, {dx:0,dy:1,anchor:'middle'}
    ];
  }

  /**
   * normalizedBounds  Normalize an optional plot rectangle to finite clipping bounds.
   *
   * Returns:
   * - Object with left, top, right, and bottom.
   *
   * Side effects:
   * - None.
   */

  function normalizedBounds(bounds){
    const source=bounds||{};
    return {
      left:number(source.left,0), top:number(source.top,0),
      right:number(source.right,1000), bottom:number(source.bottom,700)
    };
  }

  /**
   * placeLabels  Place an ordered node set and return geometry diagnostics.
   *
   * Inputs:
   * - nodes: already ranked canonical nodes.
   * - positions/radii: Maps keyed by stable node ID.
   * - bounds: measured graph rectangle.
   * - fontSize: resolved SVG label font size.
   * - options: labelAccessor, abbreviate, measureText, collisionAware, and tolerances.
   *
   * Returns:
   * - placements Map, accepted/rejected node arrays, and overlap/outside diagnostics.
   *
   * Invariants:
   * - Candidate order and node order make the result deterministic.
   * - In collisionAware mode a label is accepted only when its best candidate stays
   *   inside bounds and below overlap tolerances.
   *
   * Side effects:
   * - None; all result collections are newly allocated.
   */

  function placeLabels(nodes,positions,radii,bounds,fontSize,options){
    const opts=options||{};
    const ordered=Array.isArray(nodes)?nodes:[];
    const positionMap=positions instanceof Map?positions:new Map();
    const radiusMap=radii instanceof Map?radii:new Map();
    const clip=normalizedBounds(bounds);
    const font=Math.max(6,number(fontSize,10));
    const labelAccessor=typeof opts.labelAccessor==='function'?opts.labelAccessor:(node=>String(node&&node.displayLabel||node&&node.label||node&&node.featureId||''));
    const abbreviate=typeof opts.abbreviate==='function'?opts.abbreviate:((text,maxChars)=>String(text||'').length>maxChars?String(text||'').slice(0,Math.max(1,maxChars-1))+'…':String(text||''));
    const measureText=typeof opts.measureText==='function'?opts.measureText:((text,size)=>Math.max(18,String(text||'').length*size*.56));
    const collisionAware=!!opts.collisionAware;
    const outsideTolerance=Math.max(0,number(opts.outsideTolerance,.25));
    const overlapTolerance=Math.max(0,number(opts.overlapTolerance,.5));
    const placedBoxes=[];
    const placements=new Map();
    const acceptedNodes=[];
    const rejectedNodes=[];
    let totalOverlapArea=0,totalOutsideDistance=0,totalLabelArea=0,maxPairOverlapArea=0,collisionCount=0;
    const candidates=placementCandidates();

    ordered.forEach(node=>{
      const id=nodeId(node),point=positionMap.get(id);
      if(!id||!point||!finite(point.x)||!finite(point.y)){rejectedNodes.push(node);return;}
      const label=abbreviate(labelAccessor(node),28);
      const radius=Math.max(2,number(radiusMap.get(id),4));
      const textW=Math.max(18,number(measureText(label,font),18));
      const textH=Math.max(10,font+3);
      let best=null;
      candidates.forEach((candidate,index)=>{
        const gap=radius+5;
        const x=Number(point.x)+candidate.dx*gap;
        const y=Number(point.y)+candidate.dy*gap+(candidate.dy===0?font*.34:(candidate.dy<0?-2:textH));
        let x1=x,x2=x+textW;
        if(candidate.anchor==='end'){x1=x-textW;x2=x;}
        else if(candidate.anchor==='middle'){x1=x-textW/2;x2=x+textW/2;}
        const box={x1,y1:y-textH,x2,y2:y+2};
        const outside=Math.max(0,clip.left-box.x1)+Math.max(0,box.x2-clip.right)+Math.max(0,clip.top-box.y1)+Math.max(0,box.y2-clip.bottom);
        let overlap=0,maxOverlap=0,collisions=0;
        placedBoxes.forEach(other=>{const area=overlapArea(box,other);overlap+=area;if(area>0)collisions+=1;if(area>maxOverlap)maxOverlap=area;});
        const score=outside*250+overlap+index*.001;
        if(!best||score<best.score)best={score,x,y,anchor:candidate.anchor,box,label,leaderX:x,leaderY:y-font*.25,outside,overlap,maxOverlap,collisions};
      });
      if(!best){rejectedNodes.push(node);return;}
      if(collisionAware&&(best.outside>outsideTolerance||best.overlap>overlapTolerance)){rejectedNodes.push(node);return;}
      placedBoxes.push(best.box);
      placements.set(id,best);
      acceptedNodes.push(node);
      totalOverlapArea+=best.overlap;
      totalOutsideDistance+=best.outside;
      totalLabelArea+=(best.box.x2-best.box.x1)*(best.box.y2-best.box.y1);
      maxPairOverlapArea=Math.max(maxPairOverlapArea,best.maxOverlap);
      collisionCount+=best.collisions;
    });

    return {placements,acceptedNodes,rejectedNodes,diagnostics:{
      totalOverlapArea,totalOutsideDistance,totalLabelArea,maxPairOverlapArea,
      collisionCount,requestedCount:ordered.length,resolvedCount:acceptedNodes.length
    }};
  }

  /**
   * allLabelsFit  Decide whether one placement diagnostic satisfies All-mode tolerances.
   *
   * Returns:
   * - Boolean based on outside distance and total overlap area.
   *
   * Side effects:
   * - None.
   */

  function allLabelsFit(diagnostics,options){
    const d=diagnostics||{};
    const opts=options||{};
    const outsideTolerance=Math.max(0,number(opts.allOutsideTolerance,.25));
    const overlapTolerance=Math.max(0,number(opts.allOverlapTolerance,Math.max(.5,number(d.totalLabelArea,0)*.001)));
    return number(d.totalOutsideDistance,Infinity)<=outsideTolerance &&
      number(d.totalOverlapArea,Infinity)<=overlapTolerance;
  }

  /**
   * plan  Resolve label mode, selected nodes, positions, and diagnostics for one graph render.
   *
   * Inputs:
   * - config: mode, nodes, positions, radii, bounds, font size, maxLabels, optional
   *   priority IDs, and measurement/collision options.
   *
   * Returns:
   * - Normalized mode, counts, selected/rejected nodes, placement Map, and diagnostics.
   *
   * Invariants:
   * - Auto first tests all labels; when they do not fit it accepts a deterministic
   *   collision-aware subset in backend rank order. A small ranked floor prevents an
   *   otherwise unreadable zero-label graph.
   * - Scientific graph state is not read or changed beyond node ranking metadata.
   *
   * Side effects:
   * - None.
   */

  function plan(config){
    const cfg=config||{};
    const mode=String(cfg.mode||'auto').toLowerCase();
    const strictRanked=rankNodes(cfg.nodes||[]);
    const autoRanked=rankNodes(cfg.nodes||[],cfg.priorityNodeIds);
    const ranked=mode==='auto'?autoRanked:strictRanked;
    const totalCount=ranked.length;
    const maxLabels=Math.min(totalCount,Math.max(1,Math.round(number(cfg.maxLabels,20))));
    const placementArgs=[cfg.positions,cfg.radii,cfg.bounds,cfg.fontSize,cfg];
    let result;
    let allFit=false;
    if(mode==='none'||totalCount===0){
      result={placements:new Map(),acceptedNodes:[],rejectedNodes:ranked.slice(),diagnostics:{totalOverlapArea:0,totalOutsideDistance:0,totalLabelArea:0,maxPairOverlapArea:0,collisionCount:0,requestedCount:0,resolvedCount:0}};
    }else if(mode==='all'){
      result=placeLabels(ranked,...placementArgs);
      allFit=allLabelsFit(result.diagnostics,cfg);
    }else if(mode==='top_n'){
      result=placeLabels(ranked.slice(0,maxLabels),...placementArgs);
      allFit=allLabelsFit(result.diagnostics,cfg);
    }else{
      const full=placeLabels(ranked,...placementArgs);
      allFit=allLabelsFit(full.diagnostics,cfg);
      if(allFit){
        result=full;
      }else{
        result=placeLabels(ranked,cfg.positions,cfg.radii,cfg.bounds,cfg.fontSize,Object.assign({},cfg,{collisionAware:true}));
        const minimum=Math.min(totalCount,Math.max(1,Math.round(number(cfg.minimumAutoLabels,6))));
        if(result.acceptedNodes.length<minimum){
          result=placeLabels(ranked.slice(0,minimum),...placementArgs);
        }
      }
    }
    return {
      mode:mode==='top_n'?'top_n':(mode==='all'?'all':(mode==='none'?'none':'auto')),
      totalCount,resolvedCount:result.acceptedNodes.length,maxLabels,
      allFit,rankedNodes:ranked,selectedNodes:result.acceptedNodes,
      rejectedNodes:result.rejectedNodes,placements:result.placements,
      diagnostics:result.diagnostics
    };
  }

  /**
   * statusText  Format resolved node-label mode and count for the graph status strip.
   *
   * Returns:
   * - Human-readable status text.
   *
   * Side effects:
   * - None.
   */

  function statusText(planResult){
    const result=planResult||{};
    const total=Math.max(0,Math.round(number(result.totalCount,0)));
    const count=Math.max(0,Math.round(number(result.resolvedCount,0)));
    const mode=String(result.mode||'auto');
    if(mode==='none')return `Node labels: None · 0 of ${total}`;
    if(mode==='all')return `Node labels: All · ${count} of ${total}`;
    if(mode==='top_n')return `Node labels: Top N · ${count} of ${total}`;
    return `Node labels: Auto · ${count} of ${total}`;
  }

  global.NMResultsViewerFeatureGraphLabels=Object.freeze({rankNodes,placeLabels,plan,statusText});
})(typeof window!=='undefined'?window:globalThis);
