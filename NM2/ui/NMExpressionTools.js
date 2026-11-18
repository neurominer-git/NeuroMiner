(function(){
  'use strict';
  const MAX_VALUES = 5000;
  const MAX_CHARS = 1000;

  /**
   * helpText  Return user-facing help text for constrained numeric expressions.
   * This shared browser utility is used by preprocessing, training and Results Viewer controls that accept numeric vectors without exposing arbitrary MATLAB eval semantics.
   */
  function helpText(){
    return 'Numeric expression support: simple vectors (1 2 3 or [1,2,3]), MATLAB-style ranges (a:b or a:step:b), powers such as 2.^[-10:1:10] or 10.^[-6:1:3], linspace(a,b,n), logspace(a,b,n), Inf, -Inf, NaN, pi and eps. Expressions are interpreted as numeric vectors only; arbitrary MATLAB commands are deliberately not supported.';
  }

  /**
   * textLabelHelpText  Return user-facing help text for alternative feature-label expressions.
   */
  function textLabelHelpText(){
    return `Alternative label support: enter a MATLAB workspace variable containing a cell/string vector, a quoted cell-array literal such as {'Hippocampus','Amygdala'}, a JSON-style quoted array, or one label per line. Indexed overrides such as 17 = Hippocampus_L are also accepted for direct text entry. Workspace variables are resolved through the restricted MATLAB bridge and then serialized into browser state.`;
  }

  /**
   * splitTopLevel  Split a constrained expression at top-level commas or whitespace.
   * Nested bracket and parenthesis groups are kept intact so vector and function syntax remains parseable.
   */
  function splitTopLevel(s){
    let out=[], buf='', depth=0;
    s=String(s == null ? '' : s);
    for(let i=0;i<s.length;i++){
      const ch=s[i];
      if(ch==='[' || ch==='(') depth++;
      else if(ch===']' || ch===')') depth=Math.max(0,depth-1);
      if(depth===0 && (ch===',' || /\s/.test(ch))){
        if(buf.trim()){ out.push(buf.trim()); buf=''; }
        continue;
      }
      buf+=ch;
    }
    if(buf.trim()) out.push(buf.trim());
    return out;
  }

  /**
   * stripOuter  Strip one enclosing bracket or parenthesis pair from an expression fragment.
   */
  function stripOuter(s){
    s=String(s == null ? '' : s).trim();
    if((s.startsWith('[') && s.endsWith(']')) || (s.startsWith('(') && s.endsWith(')'))) return s.slice(1,-1).trim();
    return s;
  }

  /**
   * parseNumber  Parse one numeric token accepted by the constrained expression grammar.
   */
  function parseNumber(x){
    x=String(x == null ? '' : x).trim();
    const lx=x.toLowerCase();
    if(lx==='inf' || lx==='+inf') return Infinity;
    if(lx==='-inf') return -Infinity;
    if(lx==='nan') return NaN;
    if(lx==='pi') return Math.PI;
    if(lx==='eps') return Number.EPSILON;
    const v=Number(x);
    if(Number.isNaN(v)) throw new Error('Not a numeric token: '+x);
    return v;
  }

  /**
   * parseRange  Expand MATLAB-style a:b or a:step:b numeric ranges.
   */
  function parseRange(a,b,c){
    const start=parseNumber(a);
    let step, stop;
    if(c===undefined){ stop=parseNumber(b); step=start<=stop ? 1 : -1; }
    else { step=parseNumber(b); stop=parseNumber(c); }
    if(!Number.isFinite(start) || !Number.isFinite(step) || !Number.isFinite(stop) || step===0) throw new Error('Invalid colon range');
    let n=Math.floor((stop-start)/step)+1;
    if(n<0) n=0;
    if(n>MAX_VALUES) throw new Error('Expression expands to too many values ('+n+')');
    const out=[];
    for(let i=0;i<n;i++){
      const v=start+i*step;
      if((step>0 && v>stop+1e-12) || (step<0 && v<stop-1e-12)) break;
      out.push(v);
    }
    return out;
  }

  /**
   * parseLocal  Interpret a constrained numeric-vector expression locally in the browser.
   * The grammar intentionally excludes assignment, strings, property access and arbitrary function calls.
   */
  function parseLocal(raw){
    let s=String(raw == null ? '' : raw).trim();
    if(s==='') return [];
    if(s.length>MAX_CHARS) throw new Error('Expression is too long');
    s=s.replace(/\u2212/g,'-');
    const pow=s.match(/^(.+?)\s*\.\^\s*(.+)$/) || s.match(/^(.+?)\s*\^\s*(.+)$/);
    if(pow){
      const base=parseNumber(stripOuter(pow[1]));
      const exps=parseLocal(pow[2]);
      return exps.map(e => Math.pow(base,e));
    }
    const fn=s.match(/^(linspace|logspace)\s*\((.*)\)$/i);
    if(fn){
      const args=splitTopLevel(fn[2]);
      if(args.length!==3) throw new Error(fn[1]+' requires three arguments');
      const a=parseNumber(args[0]), b=parseNumber(args[1]), n=Math.round(parseNumber(args[2]));
      if(n<0 || n>MAX_VALUES) throw new Error('Invalid number of points');
      if(n===0) return [];
      if(n===1) return [fn[1].toLowerCase()==='logspace' ? Math.pow(10,a) : a];
      const out=[];
      for(let i=0;i<n;i++){
        const v=a+(b-a)*i/(n-1);
        out.push(fn[1].toLowerCase()==='logspace' ? Math.pow(10,v) : v);
      }
      return out;
    }
    s=stripOuter(s);
    let r=s.match(/^([^:]+):([^:]+):([^:]+)$/);
    if(r) return parseRange(r[1],r[2],r[3]);
    r=s.match(/^([^:]+):([^:]+)$/);
    if(r) return parseRange(r[1],r[2]);
    const toks=splitTopLevel(s);
    if(toks.length>1){
      let out=[];
      toks.forEach(t => { out=out.concat(parseLocal(t)); });
      if(out.length>MAX_VALUES) throw new Error('Expression expands to too many values');
      return out;
    }
    return [parseNumber(s)];
  }

  /**
   * parseTextLabelExpression  Interpret safe text-label expressions locally.
   *
   * This parser deliberately treats simple unquoted identifiers as unresolved
   * workspace-variable references rather than evaluating them in the browser.
   */
  function parseTextLabelExpression(raw){
    const txt=String(raw == null ? '' : raw).trim();
    if(txt==='') return {ok:true, labels:[], source:'empty'};
    if(txt.length>MAX_CHARS) throw new Error('Label expression is too long');
    if(/^[A-Za-z_]\w*$/.test(txt)) return {ok:false, unresolved:true, variable:txt, error:'Workspace variable requires MATLAB bridge resolution'};
    const out=[];
    const quoted = txt.match(/'([^']*)'|"([^"]*)"/g);
    if(quoted && (/^\s*[\{\[]/.test(txt) || quoted.length > 1)){
      quoted.forEach(q => out.push(q.slice(1,-1)));
      return {ok:true, labels:out, source:'quoted_literal'};
    }
    if(/[\r\n]/.test(txt)){
      txt.split(/\r?\n/).map(x=>x.trim()).filter(Boolean).forEach(line => {
        const m=line.match(/^(?:#?\s*)?(\d+)\s*[:=,]\s*(.+)$/);
        out.push(m ? m[2].trim() : line);
      });
      return {ok:true, labels:out, source:'line_text'};
    }
    if(/;/.test(txt)){
      txt.split(/;/).map(x=>x.trim()).filter(Boolean).forEach(x=>out.push(x));
      return {ok:true, labels:out, source:'semicolon_text'};
    }
    return {ok:true, labels:[txt], source:'single_text'};
  }

  /**
   * interpretTextLabelExpression  Interpret alternative feature labels locally or through the MATLAB bridge.
   */
  async function interpretTextLabelExpression(raw, opts){
    raw=String(raw == null ? '' : raw).trim();
    opts=opts || {};
    if(raw==='') return {ok:true,value:[],source:'empty'};
    let localErr=null;
    try{
      const parsed=parseTextLabelExpression(raw);
      if(parsed && parsed.ok) return {ok:true,value:parsed.labels || [],source:parsed.source || 'local'};
      if(parsed && parsed.unresolved && opts.bridgeOk && typeof opts.matlabService === 'function'){
        const res=await opts.matlabService({operation:'resolve_label_expression', expression:raw, timeout:30});
        if(res && res.ok && res.value !== undefined) return {ok:true,value:res.value,source:'matlab',message:res.message || ''};
        if(res && (res.error || res.message)) throw new Error(res.error || res.message);
        throw new Error('MATLAB label interpreter returned no value.');
      }
      if(parsed && parsed.error) throw new Error(parsed.error);
    }catch(err){ localErr=err; }
    return {ok:false,error:localErr ? localErr.message : 'Label expression did not resolve to text labels'};
  }

  /**
   * finiteOrSpecial  Return whether a parsed numeric value is finite or an accepted special value.
   */
  function finiteOrSpecial(v){ return Number.isFinite(v) || v===Infinity || v===-Infinity || Number.isNaN(v); }

  /**
   * interpretNumericExpression  Interpret a numeric expression locally, with an optional MATLAB bridge fallback.
   * opts.matlabService may be supplied by a browser page to call the restricted MATLAB-side interpreter when local parsing cannot cover a legacy-compatible expression.
   */
  async function interpretNumericExpression(raw, kind, opts){
    raw=String(raw == null ? '' : raw).trim();
    kind=kind || 'numeric_vector';
    opts=opts || {};
    if(raw==='') return {ok:true, value:(kind==='number'?NaN:[]), source:'empty'};
    let localErr=null;
    try{
      const v=parseLocal(raw);
      if(v.every(finiteOrSpecial)){
        if(kind==='number'){
          if(v.length!==1) throw new Error('Expected one numeric value, got '+v.length);
          return {ok:true,value:v[0],source:'local'};
        }
        return {ok:true,value:v,source:'local'};
      }
    }catch(err){ localErr=err; }
    if(opts.bridgeOk && typeof opts.matlabService === 'function'){
      try{
        const res=await opts.matlabService({operation:'interpret_expression', expression:raw, kind:kind, timeout:30});
        if(res && res.ok && res.value !== undefined) return {ok:true,value:res.value,source:'matlab',message:res.message || ''};
        if(res && (res.error || res.message)) throw new Error(res.error || res.message);
        throw new Error('MATLAB interpreter returned no value.');
      }catch(err){
        return {ok:false,error:'Expression could not be interpreted locally or by MATLAB: '+(localErr ? localErr.message : 'local parser rejected the expression')+'; MATLAB: '+(err && err.message ? err.message : String(err))};
      }
    }
    return {ok:false,error:localErr ? localErr.message : 'Expression did not evaluate to a numeric value'};
  }

  /**
   * expressionHelpButton  Create the standard compact expression-help control.
   */
  function expressionHelpButton(){
    const b=document.createElement('button');
    b.type='button'; b.textContent='?'; b.className='exprHelpBtn'; b.title='Numeric expression help';
    return b;
  }

  /**
   * attachExpressionHelp  Attach the standard help control to a field wrapper.
   */
  function attachExpressionHelp(wrap){
    const b=expressionHelpButton();
    let help=null;
    b.onclick=()=>{
      if(help){ help.remove(); help=null; return; }
      help=document.createElement('div');
      help.className='help exprHelp';
      help.textContent=helpText();
      wrap.appendChild(help);
    };
    wrap.appendChild(b);
    return b;
  }


  /**
   * attachTextLabelHelp  Attach the standard help control for feature-label expressions.
   */
  function attachTextLabelHelp(wrap){
    const b=expressionHelpButton();
    b.title='Alternative feature-label help';
    let help=null;
    b.onclick=()=>{
      if(help){ help.remove(); help=null; return; }
      help=document.createElement('div');
      help.className='help exprHelp';
      help.textContent=textLabelHelpText();
      wrap.appendChild(help);
    };
    wrap.appendChild(b);
    return b;
  }

  window.NMExpressionTools = {MAX_VALUES, MAX_CHARS, helpText, textLabelHelpText, splitTopLevel, stripOuter, parseNumber, parseRange, parseLocal, parseTextLabelExpression, finiteOrSpecial, interpretNumericExpression, interpretTextLabelExpression, expressionHelpButton, attachExpressionHelp, attachTextLabelHelp};
})();
