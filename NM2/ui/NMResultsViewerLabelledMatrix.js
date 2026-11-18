/**
 * NMResultsViewerLabelledMatrix
 * -------------------------------------------------------------------------
 * Generic labelled matrix canvas primitive used by Results Viewer
 * representation adapters. The primitive owns only presentation geometry:
 * responsive canvas sizing, cell iteration, grid/border/axes, selection
 * outlines, pointer hit-testing, and resize observation.
 *
 * Scientific semantics remain caller-owned. Callers provide labels and paint
 * callbacks and retain responsibility for matrix meaning, thresholds, colours,
 * missingness, hover text, and selection identity.
 *
 * Contract: NM-RESULTS-LABELLED-MATRIX-V1
 * -------------------------------------------------------------------------
 */
(function(global){
  'use strict';

  const {abbreviateLabel}=globalThis.NMResultsViewerPrimitives;
  const abbreviatedLabel=abbreviateLabel;

  function finite(value,fallback){
    const number=Number(value);
    return Number.isFinite(number)?number:Number(fallback||0);
  }

  /**
   * begin  Prepare one responsive matrix canvas and return immutable
   * drawing geometry. No scientific cell content is drawn by this function.
   */
  function begin(canvas,viewport,options){
    if(!canvas||typeof canvas.getContext!=='function')throw new Error('NMResultsViewerLabelledMatrix.begin requires one canvas.');
    if(!viewport)throw new Error('NMResultsViewerLabelledMatrix.begin requires one viewport element.');
    const cfg=options||{};
    const rectangular=cfg.nRows!==undefined && cfg.nColumns!==undefined;
    const labels=(rectangular?cfg.columnLabels:Array.isArray(cfg.labels)?cfg.labels:[]).map(value=>String(value==null?'':value));
    const n=Math.max(0,Math.round(finite(cfg.n,rectangular?cfg.nColumns:labels.length)));
    const nRows=rectangular?Math.round(Number(cfg.nRows)):n;
    const nColumns=rectangular?Math.round(Number(cfg.nColumns)):n;
    if(nRows<1||nColumns<1||!Number.isInteger(nRows)||!Number.isInteger(nColumns))throw new Error('NMResultsViewerLabelledMatrix.begin requires positive matrix dimensions.');
    if(rectangular&&(!Array.isArray(cfg.rowLabels)||cfg.rowLabels.length!==nRows||!Array.isArray(cfg.columnLabels)||cfg.columnLabels.length!==nColumns))throw new Error('Rectangular matrix axis labels must match its row and column dimensions.');
    while(labels.length<n)labels.push(`Item ${labels.length+1}`);
    if(labels.length>n)labels.length=n;

    const availableWidth=Math.max(finite(cfg.minimumAvailableWidth,280),finite(viewport.clientWidth,900)-finite(cfg.viewportHorizontalInset,20));
    const availableHeight=Math.max(finite(cfg.minimumAvailableHeight,320),finite(viewport.clientHeight,520)-finite(cfg.viewportVerticalInset,20));
    const tickFont=n<=30?finite(cfg.largeTickFont,11):(n<=70?finite(cfg.mediumTickFont,10):finite(cfg.smallTickFont,9));
    const axisFont=Math.max(10,finite(cfg.axisFont,tickFont));
    const maxChars=Number.isFinite(Number(cfg.maxLabelCharacters))?Math.max(8,Math.round(Number(cfg.maxLabelCharacters))):(n<=30?30:(n<=70?18:12));
    const axisLabels=labels.map(label=>abbreviatedLabel(label,maxChars));
    const rowLabels=rectangular?cfg.rowLabels.map(label=>String(label)):labels;
    const columnLabels=labels;
    const rowAxisLabels=rectangular?rowLabels.map(label=>abbreviatedLabel(label,maxChars)):axisLabels;
    const columnAxisLabels=axisLabels;
    const maxLabelChars=Math.max(8,...rowAxisLabels.map(label=>String(label).length));
    const narrow=availableWidth<finite(cfg.narrowWidth,680);
    let labelExtent=Math.max(finite(cfg.minimumLabelExtent,72),Math.min(narrow?finite(cfg.narrowMaximumLabelExtent,132):finite(cfg.maximumLabelExtent,184),maxLabelChars*tickFont*.58+10));
    const colourbarReserve=Math.max(0,narrow?finite(cfg.narrowColourbarReserve,96):finite(cfg.colourbarReserve,116));
    const top=finite(cfg.topInset,16);
    const axisTitleReserve=finite(cfg.axisTitleReserve,24);
    let labelSideNeed=axisTitleReserve+labelExtent+10;
    let sideReserve=Math.max(labelSideNeed,colourbarReserve);
    let left=Number.isFinite(Number(cfg.leftReserve))?Number(cfg.leftReserve):sideReserve;
    let right=Number.isFinite(Number(cfg.rightReserve))?Number(cfg.rightReserve):sideReserve;
    let bottom=axisTitleReserve+Math.max(64,Math.min(150,labelExtent*.78))+12;
    let fitMatrixSize=Math.floor(Math.min(availableWidth-left-right,availableHeight-top-bottom));
    const compactThreshold=finite(cfg.compactThreshold,180);
    if(fitMatrixSize<compactThreshold){
      labelExtent=Math.max(56,Math.min(labelExtent,96));
      labelSideNeed=axisTitleReserve+labelExtent+8;
      sideReserve=Math.max(labelSideNeed,narrow?88:100);
      left=Number.isFinite(Number(cfg.leftReserve))?Number(cfg.leftReserve):sideReserve;
      right=Number.isFinite(Number(cfg.rightReserve))?Number(cfg.rightReserve):sideReserve;
      bottom=axisTitleReserve+Math.max(52,Math.min(96,labelExtent*.72))+10;
      fitMatrixSize=Math.floor(Math.min(availableWidth-left-right,availableHeight-top-bottom));
    }
    fitMatrixSize=Math.max(finite(cfg.minimumMatrixSize,100),fitMatrixSize);
    const zoom=Math.max(.25,finite(cfg.zoom,1));
    const matrixSize=Math.max(finite(cfg.minimumMatrixSize,100),Math.floor(fitMatrixSize*zoom));
    const cell=matrixSize/n;
    const cellWidth=rectangular?Math.max(8,finite(cfg.cellWidth,20)):cell;
    const cellHeight=rectangular?Math.max(8,finite(cfg.cellHeight,22)):cell;
    const matrixWidth=rectangular?nColumns*cellWidth:matrixSize;
    const matrixHeight=rectangular?nRows*cellHeight:matrixSize;
    const cssWidth=Math.ceil(left+matrixWidth+right);
    const cssHeight=Math.ceil(top+matrixHeight+bottom);
    const dpr=Math.max(1,Math.min(finite(cfg.maximumDevicePixelRatio,2),finite(global.devicePixelRatio,1)));
    canvas.width=Math.max(1,Math.round(cssWidth*dpr));
    canvas.height=Math.max(1,Math.round(cssHeight*dpr));
    canvas.style.width=`${cssWidth}px`;
    canvas.style.height=`${cssHeight}px`;
    const ctx=canvas.getContext('2d');
    ctx.setTransform(dpr,0,0,dpr,0,0);
    ctx.clearRect(0,0,cssWidth,cssHeight);
    ctx.fillStyle=String(cfg.backgroundColor||'#ffffff');
    ctx.fillRect(0,0,cssWidth,cssHeight);
    return {
      canvas,viewport,ctx,n,nRows,nColumns,rectangular,labels,axisLabels,rowLabels,columnLabels,rowAxisLabels,columnAxisLabels,availableWidth,availableHeight,
      tickFont,axisFont,maxChars,narrow,labelExtent,colourbarReserve,top,
      axisTitleReserve,left,right,bottom,fitMatrixSize,zoom,matrixSize,matrixWidth,matrixHeight,cell,cellWidth,cellHeight,cssWidth,cssHeight,dpr,
      x0:left,y0:top,colorbarX:left+matrixWidth+finite(cfg.colorbarGap,22),
      colorbarLabelOffset:narrow?finite(cfg.narrowColorbarLabelOffset,58):finite(cfg.colorbarLabelOffset,68),
      axisTitleX:String(cfg.axisTitleX||'Items'),axisTitleY:String(cfg.axisTitleY||'Items')
    };
  }

  /** Iterate every cell and delegate painting to the caller. */
  function drawCells(frame,painter){
    if(!frame||typeof painter!=='function')return;
    const {ctx,nRows,nColumns,x0,y0,cell,cellWidth,cellHeight}=frame;
    for(let row=0;row<nRows;row+=1){
      for(let column=0;column<nColumns;column+=1){
        painter({ctx,row,column,x:x0+column*cellWidth,y:y0+row*cellHeight,width:cellWidth,height:cellHeight,cell,frame});
      }
    }
  }

  /** Draw optional cell boundaries when the current cell size supports them. */
  function drawGrid(frame,options){
    if(!frame)return;
    const cfg=options||{};
    const {ctx,nRows,nColumns,x0,y0,matrixWidth,matrixHeight,cellWidth,cellHeight}=frame;
    if(Math.min(cellWidth,cellHeight)<finite(cfg.minimumCellSize,6))return;
    ctx.save();
    ctx.strokeStyle=String(cfg.strokeStyle||(Math.min(cellWidth,cellHeight)>=10?'rgba(71,85,105,.20)':'rgba(71,85,105,.12)'));
    ctx.lineWidth=finite(cfg.lineWidth,Math.min(cellWidth,cellHeight)>=10?.55:.35);
    for(let boundary=1;boundary<nColumns;boundary+=1){
      const x=x0+boundary*cellWidth+.5;
      ctx.beginPath();ctx.moveTo(x,y0);ctx.lineTo(x,y0+matrixHeight);ctx.stroke();
    }
    for(let boundary=1;boundary<nRows;boundary+=1){
      const y=y0+boundary*cellHeight+.5;
      ctx.beginPath();ctx.moveTo(x0,y);ctx.lineTo(x0+matrixWidth,y);ctx.stroke();
    }
    ctx.restore();
  }

  /** Draw the outer matrix boundary. */
  function drawBorder(frame,options){
    if(!frame)return;
    const cfg=options||{};
    const {ctx,x0,y0,matrixWidth,matrixHeight}=frame;
    ctx.save();
    ctx.strokeStyle=String(cfg.strokeStyle||'#64748b');
    ctx.lineWidth=finite(cfg.lineWidth,.85);
    ctx.strokeRect(x0+.4,y0+.4,matrixWidth-.8,matrixHeight-.8);
    ctx.restore();
  }

  /** Draw sparse readable labels and symmetric axis titles. */
  function drawAxes(frame,options){
    if(!frame)return;
    const cfg=options||{};
    const {ctx,nRows,nColumns,x0,y0,matrixWidth,matrixHeight,cellWidth,cellHeight,rowAxisLabels,columnAxisLabels,tickFont,axisFont,cssHeight}=frame;
    const minLabelSpacing=Math.max(tickFont+2,finite(cfg.minimumLabelSpacing,11));
    const rowSkip=Math.max(1,Math.ceil(minLabelSpacing/Math.max(1e-9,cellHeight)));
    const columnSkip=Math.max(1,Math.ceil(minLabelSpacing/Math.max(1e-9,cellWidth)));
    const tickIndices=[];
    for(let index=0;index<nRows;index+=rowSkip)tickIndices.push(index);
    if(tickIndices[tickIndices.length-1]!==nRows-1)tickIndices.push(nRows-1);
    const columnTicks=[];
    for(let index=0;index<nColumns;index+=columnSkip)columnTicks.push(index);
    if(columnTicks[columnTicks.length-1]!==nColumns-1)columnTicks.push(nColumns-1);
    ctx.save();
    ctx.fillStyle=String(cfg.textColor||'#334155');
    ctx.font=`${tickFont}px system-ui, sans-serif`;
    ctx.textBaseline='middle';ctx.textAlign='right';
    tickIndices.forEach(index=>ctx.fillText(rowAxisLabels[index],x0-7,y0+(index+.5)*cellHeight));
    columnTicks.forEach(index=>{
      ctx.save();
      ctx.translate(x0+(index+.5)*cellWidth,y0+matrixHeight+8);
      ctx.rotate(finite(cfg.xLabelRotation,-Math.PI/4));
      ctx.textAlign='right';ctx.textBaseline='middle';
      ctx.fillText(columnAxisLabels[index],0,0);
      ctx.restore();
    });
    ctx.font=`600 ${axisFont}px system-ui, sans-serif`;
    ctx.textAlign='center';ctx.textBaseline='middle';
    ctx.fillText(String(cfg.axisTitleX||frame.axisTitleX),x0+matrixWidth/2,cssHeight-12);
    ctx.save();
    ctx.translate(13,y0+matrixHeight/2);ctx.rotate(-Math.PI/2);
    ctx.fillText(String(cfg.axisTitleY||frame.axisTitleY),0,0);
    ctx.restore();
    ctx.restore();
    return tickIndices;
  }

  /** Draw one caller-defined vertical colour scale beside the matrix. */
  function drawColorbar(frame,options){
    if(!frame)return;
    const cfg=options||{};
    const {ctx}=frame;
    const x=finite(cfg.x,frame.colorbarX),y=finite(cfg.y,frame.y0);
    const width=Math.max(4,finite(cfg.width,16)),height=Math.max(1,finite(cfg.height,frame.matrixHeight));
    const colorAtFraction=typeof cfg.colorAtFraction==='function'?cfg.colorAtFraction:(fraction=>String(cfg.color||'#94a3b8'));
    const steps=Math.max(16,Math.round(finite(cfg.steps,height)));
    for(let index=0;index<steps;index+=1){
      const fraction=index/Math.max(1,steps-1);
      ctx.fillStyle=String(colorAtFraction(fraction,index,steps)||'#94a3b8');
      ctx.fillRect(x,y+index*height/steps,width,height/steps+.7);
    }
    ctx.save();
    ctx.strokeStyle=String(cfg.borderColor||'#64748b');ctx.lineWidth=finite(cfg.borderWidth,.8);ctx.strokeRect(x,y,width,height);
    const ticks=Array.isArray(cfg.ticks)?cfg.ticks:[];
    ctx.font=`${finite(cfg.tickFont,frame.tickFont)}px system-ui, sans-serif`;
    ctx.fillStyle=String(cfg.textColor||'#334155');ctx.textAlign='left';ctx.textBaseline='middle';
    ticks.forEach(tick=>{
      const row=tick&&typeof tick==='object'?tick:{value:tick,label:String(tick)};
      const fraction=finite(row.fraction,NaN);if(!Number.isFinite(fraction)||fraction<0||fraction>1)return;
      const yy=y+fraction*height;
      ctx.strokeStyle=String(cfg.tickColor||'#64748b');ctx.lineWidth=finite(cfg.tickWidth,.8);
      ctx.beginPath();ctx.moveTo(x+width,yy);ctx.lineTo(x+width+5,yy);ctx.stroke();
      ctx.fillText(String(row.label==null?row.value:row.label),x+width+8,yy);
    });
    const markers=Array.isArray(cfg.markers)?cfg.markers:[];
    markers.forEach(marker=>{
      const row=marker&&typeof marker==='object'?marker:{fraction:marker};
      const fraction=finite(row.fraction,NaN);if(!Number.isFinite(fraction)||fraction<0||fraction>1)return;
      const yy=y+fraction*height;
      ctx.strokeStyle=String(row.strokeStyle||cfg.markerColor||'#0f172a');ctx.lineWidth=finite(row.lineWidth,cfg.markerWidth||1.5);
      if(Array.isArray(row.lineDash))ctx.setLineDash(row.lineDash);
      ctx.beginPath();ctx.moveTo(x-3,yy);ctx.lineTo(x+width+4,yy);ctx.stroke();ctx.setLineDash([]);
    });
    const label=String(cfg.label||'').trim();
    if(label){
      ctx.save();
      ctx.translate(x+width+finite(cfg.labelOffset,frame.colorbarLabelOffset),y+height/2);ctx.rotate(-Math.PI/2);
      ctx.textAlign='center';ctx.textBaseline='middle';ctx.font=`600 ${finite(cfg.axisFont,frame.axisFont)}px system-ui, sans-serif`;ctx.fillStyle=String(cfg.textColor||'#334155');
      ctx.fillText(label,0,0);ctx.restore();
    }
    ctx.restore();
    return {x,y,width,height};
  }

  /** Draw one stable cell selection outline. */
  function drawSelection(frame,row,column,options){
    if(!frame)return;
    const r=Math.round(Number(row)),c=Math.round(Number(column));
    if(!Number.isFinite(r)||!Number.isFinite(c)||r<0||c<0||r>=frame.nRows||c>=frame.nColumns)return;
    const cfg=options||{};
    const inset=finite(cfg.inset,1);
    frame.ctx.save();
    frame.ctx.strokeStyle=String(cfg.strokeStyle||'#0f172a');
    frame.ctx.lineWidth=finite(cfg.lineWidth,2);
    if(Array.isArray(cfg.lineDash))frame.ctx.setLineDash(cfg.lineDash);
    frame.ctx.strokeRect(frame.x0+c*frame.cellWidth+inset,frame.y0+r*frame.cellHeight+inset,Math.max(1,frame.cellWidth-2*inset),Math.max(1,frame.cellHeight-2*inset));
    frame.ctx.restore();
  }


  /** Draw one persistent matrix cursor through the selected cell. */
  function drawCursor(frame,row,column,options){
    if(!frame)return;
    const r=Math.round(Number(row)),c=Math.round(Number(column));
    if(!Number.isFinite(r)||!Number.isFinite(c)||r<0||c<0||r>=frame.nRows||c>=frame.nColumns)return;
    const cfg=options||{},cx=frame.x0+(c+.5)*frame.cellWidth,cy=frame.y0+(r+.5)*frame.cellHeight;
    const radius=Math.max(2.5,finite(cfg.radius,Math.min(8,Math.max(3,Math.min(frame.cellWidth,frame.cellHeight)*.42))));
    frame.ctx.save();
    frame.ctx.strokeStyle=String(cfg.strokeStyle||'#f59e0b');
    frame.ctx.fillStyle=String(cfg.fillStyle||'rgba(255,255,255,.85)');
    frame.ctx.lineWidth=finite(cfg.lineWidth,1.5);
    if(Array.isArray(cfg.lineDash))frame.ctx.setLineDash(cfg.lineDash);
    frame.ctx.beginPath();frame.ctx.moveTo(frame.x0,cy);frame.ctx.lineTo(frame.x0+frame.matrixWidth,cy);frame.ctx.stroke();
    frame.ctx.beginPath();frame.ctx.moveTo(cx,frame.y0);frame.ctx.lineTo(cx,frame.y0+frame.matrixHeight);frame.ctx.stroke();
    frame.ctx.setLineDash([]);
    frame.ctx.beginPath();frame.ctx.arc(cx,cy,radius,0,Math.PI*2);frame.ctx.fill();frame.ctx.stroke();
    frame.ctx.restore();
    return {x:cx,y:cy,row:r,column:c};
  }

  /** Return the canvas-space centre of one matrix cell. */
  function cellCenter(frame,row,column){
    if(!frame)return null;
    const r=Math.round(Number(row)),c=Math.round(Number(column));
    if(!Number.isFinite(r)||!Number.isFinite(c)||r<0||c<0||r>=frame.nRows||c>=frame.nColumns)return null;
    return {x:frame.x0+(c+.5)*frame.cellWidth,y:frame.y0+(r+.5)*frame.cellHeight,row:r,column:c};
  }

  /** Compute scroll offsets that keep one matrix cell at a requested viewport-local point. */
  function scrollOffsetForCell(frame,viewport,row,column,localPoint){
    if(!frame||!viewport)return null;
    const point=cellCenter(frame,row,column);if(!point)return null;
    const local=localPoint&&typeof localPoint==='object'?localPoint:{};
    const localX=Number.isFinite(Number(local.x))?Number(local.x):finite(viewport.clientWidth,0)/2;
    const localY=Number.isFinite(Number(local.y))?Number(local.y):finite(viewport.clientHeight,0)/2;
    const maxLeft=Math.max(0,finite(frame.cssWidth,0)-finite(viewport.clientWidth,0));
    const maxTop=Math.max(0,finite(frame.cssHeight,0)-finite(viewport.clientHeight,0));
    return {
      left:Math.max(0,Math.min(maxLeft,point.x-localX)),
      top:Math.max(0,Math.min(maxTop,point.y-localY)),
      row:point.row,column:point.column,x:point.x,y:point.y,localX,localY
    };
  }

  /** Highlight an axis in rectangular matrices, or both axes in square matrices. */
  function drawAxisCross(frame,index,options){
    if(!frame)return;
    const i=Math.round(Number(index)),cfg=options||{};
    const row=cfg.axis!=='column',column=cfg.axis!=='row';
    if(!Number.isInteger(i)||i<0||(row&&i>=frame.nRows)||(column&&i>=frame.nColumns))return;
    const {ctx,x0,y0,matrixWidth,matrixHeight,cellWidth,cellHeight}=frame;
    ctx.save();
    ctx.fillStyle=String(cfg.fillStyle||'rgba(245,158,11,.10)');
    if(row)ctx.fillRect(x0,y0+i*cellHeight,matrixWidth,cellHeight);
    if(column)ctx.fillRect(x0+i*cellWidth,y0,cellWidth,matrixHeight);
    ctx.strokeStyle=String(cfg.strokeStyle||'#f59e0b');
    ctx.lineWidth=finite(cfg.lineWidth,1.4);
    if(row)ctx.strokeRect(x0,y0+i*cellHeight,matrixWidth,cellHeight);
    if(column)ctx.strokeRect(x0+i*cellWidth,y0,cellWidth,matrixHeight);
    ctx.restore();
  }

  /** Convert one pointer event to a zero-based matrix row and column. */
  function cellFromEvent(canvas,event,meta,options){
    const frame=meta||canvas&&canvas._rvLabelledMatrixMeta;
    if(!canvas||!event||!frame)return null;
    const rect=canvas.getBoundingClientRect();
    const cssWidth=parseFloat(canvas.style.width||rect.width);
    const cssHeight=parseFloat(canvas.style.height||rect.height);
    const x=(event.clientX-rect.left)*(cssWidth/Math.max(1,rect.width));
    const y=(event.clientY-rect.top)*(cssHeight/Math.max(1,rect.height));
    const column=Math.floor((x-frame.x0)/frame.cellWidth);
    const row=Math.floor((y-frame.y0)/frame.cellHeight);
    if(options&&options.axes){
      const inRow=row>=0&&row<frame.nRows, inColumn=column>=0&&column<frame.nColumns;
      if(inRow&&inColumn)return {row,column,frame};
      if(inRow&&x>=0&&x<frame.x0)return {row,column:-1,frame};
      if(inColumn&&y>=frame.y0+frame.matrixHeight&&y<frame.cssHeight)return {row:-1,column,frame};
      return null;
    }
    if(row<0||column<0||row>=frame.nRows||column>=frame.nColumns)return null;
    return {row,column,frame};
  }

  /** Bind one ResizeObserver and return it to the caller for lifecycle storage. */
  function bindResize(viewport,redraw,previousObserver){
    if(previousObserver&&typeof previousObserver.disconnect==='function'){
      try{previousObserver.disconnect();}catch(error){}
    }
    if(typeof global.ResizeObserver!=='function'||!viewport||typeof redraw!=='function')return null;
    let raf=0;
    const observer=new global.ResizeObserver(()=>{
      if(raf)global.cancelAnimationFrame(raf);
      raf=global.requestAnimationFrame(redraw);
    });
    observer.observe(viewport);
    return observer;
  }

  global.NMResultsViewerLabelledMatrix={
    begin,drawCells,drawGrid,drawBorder,drawAxes,drawColorbar,drawSelection,drawCursor,drawAxisCross,
    cellCenter,scrollOffsetForCell,cellFromEvent,bindResize,abbreviatedLabel,
    contractVersion:'NM-RESULTS-LABELLED-MATRIX-V1'
  };
})(window);
