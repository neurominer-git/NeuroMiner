/**
 * NMResultsViewerFeatureRibbon  Plan adaptive Feature Inspection ribbon lanes.
 *
 * The planner treats complete semantic control groups as the wrapping unit. It
 * measures compact groups at their intrinsic one-line label width, reserves
 * bounded preferred widths for long text-entry groups, shrinks those bounded
 * groups before creating another lane, and expands them only up to explicit
 * maxima after all compact groups have been protected. It never changes
 * scientific control state.
 */
(function(global){
  'use strict';

  const GROUP_SELECTOR='.rvFeatureRibbonGroup[data-feature-semantic-group]';
  const LANE_SELECTOR=':scope > .rvFeatureRibbonLane';
  const DIVIDER_COST_PX=20;
  const FLUID_MIN_WIDTH_FALLBACK_PX=240;
  const FLUID_PREFERRED_WIDTH_FALLBACK_PX=320;
  const FLUID_MAX_WIDTH_FALLBACK_PX=420;

  /** Return semantic groups in their declared stable order. */
  function orderedGroups(root){
    return Array.from(root.querySelectorAll(GROUP_SELECTOR)).sort((a,b)=>{
      const ao=Number(a.dataset.rvRibbonOrder||0),bo=Number(b.dataset.rvRibbonOrder||0);
      return ao===bo?0:ao-bo;
    });
  }

  /** Return the usable inline width after ribbon padding. */
  function usableWidth(root){
    const style=global.getComputedStyle(root);
    const left=parseFloat(style.paddingLeft)||0,right=parseFloat(style.paddingRight)||0;
    return Math.max(1,Math.floor(Number(root.clientWidth||0)-left-right-4));
  }

  /** Parse one positive CSS length from an element, retaining a stable fallback. */
  function cssLength(element,property,fallback){
    const value=parseFloat(global.getComputedStyle(element).getPropertyValue(property));
    return Number.isFinite(value)&&value>0?value:fallback;
  }

  /** Create one hidden measurement host that inherits production width tokens. */
  function measurementHost(root,width){
    const host=document.createElement('div');
    host.className='rvFeatureRibbonMeasure';
    host.style.width=`${Math.max(1,width)}px`;
    root.appendChild(host);
    return host;
  }

  /** Measure one non-mutating compact-group clone in the requested variant. */
  function measuredGroupWidth(group,variant,host,available){
    const clone=group.cloneNode(true);
    clone.removeAttribute('id');
    clone.style.removeProperty('--rv-feature-ribbon-planned-width');
    clone.dataset.rvRibbonVariant=variant;
    clone.classList.add('rvFeatureRibbonMeasureGroup');
    host.appendChild(clone);
    const rect=clone.getBoundingClientRect();
    const width=Math.ceil(Math.max(Number(rect.width||0),Number(clone.scrollWidth||0)));
    clone.remove();
    return variant==='stacked'?Math.min(available,Math.max(1,width)):Math.max(1,width);
  }

  /**
   * Measure one semantic group.
   *
   * Compact groups use intrinsic rendered width, including one-line captions.
   * Fluid groups use bounded minimum/preferred/maximum width tokens so they do
   * not consume space required by compact groups or grow indefinitely.
   */
  function groupMeasurement(group,host,available){
    const kind=String(group.dataset.rvRibbonKind||'compact');
    if(kind==='fluid'){
      const minimum=Math.min(available,cssLength(group,'--rv-feature-fluid-min-width',FLUID_MIN_WIDTH_FALLBACK_PX));
      const preferred=Math.min(available,Math.max(minimum,cssLength(group,'--rv-feature-fluid-preferred-width',FLUID_PREFERRED_WIDTH_FALLBACK_PX)));
      const maximum=Math.min(available,Math.max(preferred,cssLength(group,'--rv-feature-fluid-max-width',FLUID_MAX_WIDTH_FALLBACK_PX)));
      return {kind,variant:'fluid',width:preferred,minWidth:minimum,preferredWidth:preferred,maxWidth:maximum,assignedWidth:preferred};
    }
    let variant='compact';
    let width=measuredGroupWidth(group,variant,host,available);
    if(width>available){
      variant='stacked';
      width=available;
    }
    return {kind,variant,width,minWidth:width,preferredWidth:width,maxWidth:width,assignedWidth:width};
  }

  /** Build shallow lanes using whole-group greedy packing at measured widths. */
  function packGroups(groups,measurements,available){
    const lanes=[];
    let lane=[],used=0;
    groups.forEach(group=>{
      const item=measurements.get(group);
      const cost=item.width+(lane.length?DIVIDER_COST_PX:0);
      if(lane.length&&used+cost>available){
        lanes.push(lane);
        lane=[];
        used=0;
      }
      lane.push(group);
      used+=item.width+(lane.length>1?DIVIDER_COST_PX:0);
    });
    if(lane.length)lanes.push(lane);
    return lanes;
  }

  /**
   * Expand fluid groups only after compact groups have their intrinsic widths.
   * Growth is shared across fluid groups and stops at their explicit maxima.
   */
  function allocateLaneWidths(lanes,measurements,available){
    lanes.forEach(lane=>{
      lane.forEach(group=>{measurements.get(group).assignedWidth=measurements.get(group).width;});
      const dividerCost=Math.max(0,lane.length-1)*DIVIDER_COST_PX;
      let used=dividerCost+lane.reduce((sum,group)=>sum+measurements.get(group).assignedWidth,0);
      let residual=Math.max(0,available-used);
      let growable=lane.filter(group=>{
        const item=measurements.get(group);
        return item.kind==='fluid'&&item.assignedWidth+0.5<item.maxWidth;
      });
      while(residual>0.5&&growable.length){
        const share=residual/growable.length;
        let consumed=0;
        growable.forEach(group=>{
          const item=measurements.get(group);
          const growth=Math.min(share,item.maxWidth-item.assignedWidth);
          item.assignedWidth+=growth;
          consumed+=growth;
        });
        if(consumed<=0.5)break;
        residual-=consumed;
        growable=growable.filter(group=>{
          const item=measurements.get(group);
          return item.assignedWidth+0.5<item.maxWidth;
        });
      }
    });
  }

  /** Replace previous lanes rather than layering new layout containers around them. */
  function rebuildLanes(root,groups,lanes,measurements){
    const note=root.querySelector(':scope > .rvFeaturePageNote');
    groups.forEach(group=>group.remove());
    Array.from(root.querySelectorAll(LANE_SELECTOR)).forEach(lane=>lane.remove());
    lanes.forEach((laneGroups,index)=>{
      const lane=document.createElement('div');
      lane.className='rvFeatureRibbonLane';
      lane.dataset.rvRibbonLane=String(index+1);
      laneGroups.forEach(group=>{
        const item=measurements.get(group);
        group.dataset.rvRibbonVariant=item.variant;
        if(item.kind==='fluid')group.style.setProperty('--rv-feature-ribbon-planned-width',`${Math.max(1,Math.floor(item.assignedWidth))}px`);
        else group.style.removeProperty('--rv-feature-ribbon-planned-width');
        lane.appendChild(group);
      });
      root.insertBefore(lane,note||null);
    });
  }

  /** Compute lane diagnostics used by browser geometry tests and production tracing. */
  function laneDiagnostics(root,available){
    const lanes=Array.from(root.querySelectorAll(LANE_SELECTOR));
    const laneMetrics=lanes.map(lane=>{
      const groups=Array.from(lane.children).filter(node=>node.matches&&node.matches(GROUP_SELECTOR));
      const rects=groups.map(group=>group.getBoundingClientRect());
      const used=rects.length?Math.max(...rects.map(rect=>rect.right))-Math.min(...rects.map(rect=>rect.left)):0;
      return {groupCount:groups.length,usedWidth:Math.round(used),availableWidth:available};
    });
    root.dataset.rvRibbonLaneCount=String(lanes.length);
    root.dataset.rvRibbonAvailableWidth=String(available);
    return laneMetrics;
  }

  /**
   * plan  Reflow one Feature Inspection ribbon without replacing controls.
   *
   * @param {HTMLElement} root - `.rvFeatureRibbon` element.
   * @returns {{laneCount:number, availableWidth:number, density:string, lanes:Array}}
   */
  function plan(root){
    if(!root||!root.matches||!root.matches('.rvFeatureRibbon'))throw new Error('NMResultsViewerFeatureRibbon.plan requires one .rvFeatureRibbon root.');
    const groups=orderedGroups(root);
    const available=usableWidth(root);
    if(!groups.length){
      root.dataset.rvRibbonLaneCount='0';
      root.dataset.rvRibbonAvailableWidth=String(available);
      return {laneCount:0,availableWidth:available,density:'standard',lanes:[]};
    }
    const candidate=density=>{
      root.dataset.rvRibbonDensity=density;
      const host=measurementHost(root,available);
      const measurements=new Map();
      groups.forEach(group=>measurements.set(group,groupMeasurement(group,host,available)));
      host.remove();
      const lanes=packGroups(groups,measurements,available);
      allocateLaneWidths(lanes,measurements,available);
      return {density,measurements,lanes};
    };
    const standard=candidate('standard');
    const tight=candidate('tight');
    const chosen=tight.lanes.length<standard.lanes.length?tight:standard;
    root.dataset.rvRibbonDensity=chosen.density;
    rebuildLanes(root,groups,chosen.lanes,chosen.measurements);
    const metrics=laneDiagnostics(root,available);
    return {laneCount:chosen.lanes.length,availableWidth:available,density:chosen.density,lanes:metrics};
  }

  /** Return visible, non-absolute direct children that participate in inline geometry. */
  function geometryChildren(region){
    return Array.from(region.children||[]).filter(child=>{
      if(!child||typeof child.getBoundingClientRect!=='function'||child.hidden)return false;
      const style=global.getComputedStyle(child);
      return style.display!=='none'&&style.visibility!=='hidden'&&style.position!=='absolute'&&style.position!=='fixed';
    });
  }

  /**
   * geometry  Inspect one planned ribbon for overflow or sibling overlap.
   *
   * The diagnostic is intentionally stricter than scrollWidth alone: controls
   * that geometrically intersect inside a no-wrap subgroup are invalid even if
   * the browser reports a clipped scroll box. The returned deficit estimates
   * how much additional panel width is required before a paired layout should
   * be retried.
   */
  function geometry(root){
    if(!root||!root.matches||!root.matches('.rvFeatureRibbon'))throw new Error('NMResultsViewerFeatureRibbon.geometry requires one .rvFeatureRibbon root.');
    const regions=[root].concat(Array.from(root.querySelectorAll('.rvFeatureRibbonLane,.rvFeatureRibbonGroup,.rvFeatureRibbonFields,.rvFeatureRibbonSubgroup')));
    let overflow=false,overlap=false,maxDeficit=0;
    const failures=[];
    regions.forEach(region=>{
      if(!region||region.hidden||typeof region.getBoundingClientRect!=='function')return;
      const style=global.getComputedStyle(region);
      if(style.display==='none'||style.visibility==='hidden')return;
      const bounds=region.getBoundingClientRect();
      const client=Math.max(0,Number(region.clientWidth||0));
      const scroll=Math.max(0,Number(region.scrollWidth||0));
      if(client>0&&scroll>client+1){
        const deficit=scroll-client;
        overflow=true;maxDeficit=Math.max(maxDeficit,deficit);
        failures.push({kind:'scrollOverflow',deficit:Math.ceil(deficit),regionClass:String(region.className||'')});
      }
      const children=geometryChildren(region).map(child=>({child,rect:child.getBoundingClientRect()})).filter(item=>item.rect.width>0&&item.rect.height>0).sort((a,b)=>a.rect.left-b.rect.left||a.rect.top-b.rect.top);
      children.forEach(item=>{
        const rightDeficit=item.rect.right-bounds.right;
        const leftDeficit=bounds.left-item.rect.left;
        if(rightDeficit>1||leftDeficit>1){
          const deficit=Math.max(rightDeficit,leftDeficit);
          overflow=true;maxDeficit=Math.max(maxDeficit,deficit);
          failures.push({kind:'boundsOverflow',deficit:Math.ceil(deficit),regionClass:String(region.className||'')});
        }
      });
      for(let i=1;i<children.length;i+=1){
        const previous=children[i-1].rect,current=children[i].rect;
        const verticalIntersection=Math.min(previous.bottom,current.bottom)-Math.max(previous.top,current.top);
        const horizontalIntersection=previous.right-current.left;
        if(verticalIntersection>1&&horizontalIntersection>1){
          overlap=true;maxDeficit=Math.max(maxDeficit,horizontalIntersection);
          failures.push({kind:'siblingOverlap',deficit:Math.ceil(horizontalIntersection),regionClass:String(region.className||'')});
        }
      }
    });
    return {ok:!(overflow||overlap),overflow,overlap,maxDeficit:Math.ceil(maxDeficit),failures};
  }

  /** Return whether the current workspace may attempt a two-column Feature Inspection layout. */
  function pairingAllowed(workspaceWidth,itemCount,minimumWorkspaceWidth,baseWorkspaceWidth){
    const width=Math.max(0,Number(workspaceWidth||0));
    const count=Math.max(0,Math.round(Number(itemCount||0)));
    const base=Math.max(0,Number(baseWorkspaceWidth||1480));
    const guarded=Math.max(base,Math.max(0,Number(minimumWorkspaceWidth||0)));
    return count>=2&&width>=guarded;
  }

  /**
   * nextPairingMinimumWidth  Convert one failed paired-layout geometry probe
   * into a monotonic workspace-width guard with a small hysteresis margin.
   */
  function nextPairingMinimumWidth(workspaceWidth,maxDeficit,currentMinimum){
    const width=Math.max(0,Number(workspaceWidth||0));
    const deficit=Math.max(0,Number(maxDeficit||0));
    const current=Math.max(0,Number(currentMinimum||0));
    const increment=Math.max(96,2*Math.ceil(deficit)+48);
    return Math.ceil(Math.max(current,width+increment));
  }

  /** Plan every ribbon below one container and return their diagnostics. */
  function planAll(container){
    const scope=container||document;
    return Array.from(scope.querySelectorAll('.rvFeatureRibbon')).map(root=>plan(root));
  }

  global.NMResultsViewerFeatureRibbon=Object.freeze({plan,planAll,geometry,pairingAllowed,nextPairingMinimumWidth});
})(window);
