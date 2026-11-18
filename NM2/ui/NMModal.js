/* NMModal.js
 * -------------------------------------------------------------------------
 * Minimal, dependency-free modal dialog for NeuroMiner browser UI pages.
 *
 * Designed as a shared host for runtime sub-tools (e.g. the CV2 GridAct
 * picker) so individual runner pages don't each reimplement focus trapping,
 * Escape handling, and backdrop dismissal. The modal owns only its shell;
 * callers supply body content and footer actions.
 *
 * Usage:
 *   const modal = NMModal.open({
 *     title: 'Select CV2 partitions',
 *     render: (bodyEl) => { ... populate bodyEl ... },
 *     actions: [
 *       { label:'Cancel', onClick:(m)=>m.close() },
 *       { label:'Apply', variant:'primary', onClick:(m)=>{ ...; m.close(); } }
 *     ],
 *     onClose: () => { ... }
 *   });
 * ------------------------------------------------------------------------- */
(function(global){
  'use strict';

  /**
   * esc  Escape text before inserting it into HTML markup.
   * It is a small browser utility used to keep later rendering and request-building code simple and predictable.
   */
  function esc(s){ return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

  const FOCUSABLE = 'a[href],area[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])';

  /**
   * Modal  Provide the modal helper used by shared modal-dialog helper used by browser UI pages.
   * It is a browser rendering helper: it updates DOM or SVG state from already retrieved NeuroMiner payloads and does not define new scientific results.
   * opts.dismissOnEscape: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * opts.onClose: browser-side field consumed from opts while translating UI state to MATLAB-service requests.
   * Side effects: updates DOM markup, CSS classes or control state for the active browser page.
   */
  function Modal(opts){
    this.opts = opts || {};
    this.previousActive = document.activeElement;
    this.onKeydown = this.onKeydown.bind(this);
    this.build();
  }

  Modal.prototype.build = function(){
    const o = this.opts;
    const overlay = document.createElement('div');
    overlay.className = 'nmModalOverlay';
    overlay.setAttribute('role', 'presentation');

    const dialog = document.createElement('div');
    dialog.className = 'nmModalDialog' + (o.size ? ' nmModal-' + o.size : '');
    dialog.setAttribute('role', 'dialog');
    dialog.setAttribute('aria-modal', 'true');
    const titleId = 'nmModalTitle_' + Math.random().toString(36).slice(2,8);
    if(o.title) dialog.setAttribute('aria-labelledby', titleId);

    const head = document.createElement('div');
    head.className = 'nmModalHead';
    const closeLabel = esc(o.closeLabel || 'Close dialog');
    const closeGlyph = esc(o.closeGlyph || '\u00d7');
    head.innerHTML = `<h2 class="nmModalTitle" id="${titleId}">${esc(o.title || '')}</h2>` +
      `<button type="button" class="nmModalClose" aria-label="${closeLabel}" title="${closeLabel}">${closeGlyph}</button>`;

    const body = document.createElement('div');
    body.className = 'nmModalBody';

    const foot = document.createElement('div');
    foot.className = 'nmModalFoot';

    dialog.appendChild(head);
    dialog.appendChild(body);
    dialog.appendChild(foot);
    overlay.appendChild(dialog);

    this.overlay = overlay;
    this.dialog = dialog;
    this.body = body;
    this.foot = foot;

    // Close affordances
    head.querySelector('.nmModalClose').addEventListener('click', () => this.close());
    if(o.dismissOnBackdrop !== false){
      overlay.addEventListener('mousedown', (ev) => { if(ev.target === overlay) this.close(); });
    }

    // Footer actions
    const actions = Array.isArray(o.actions) ? o.actions : [];
    actions.forEach((a) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'nmModalBtn' + (a.variant ? ' nmModalBtn-' + a.variant : '');
      btn.textContent = a.label || 'OK';
      if(a.disabled) btn.disabled = true;
      btn.addEventListener('click', () => { if(typeof a.onClick === 'function') a.onClick(this); });
      this.foot.appendChild(btn);
      if(a.ref && typeof a.ref === 'function') a.ref(btn);
    });
    if(!actions.length) this.foot.style.display = 'none';

    // Body content
    if(typeof o.render === 'function') o.render(this.body, this);
    else if(typeof o.html === 'string') this.body.innerHTML = o.html;

    document.body.appendChild(overlay);
    this.lockScroll(true);
    document.addEventListener('keydown', this.onKeydown, true);
    this.focusFirst();
  };

  Modal.prototype.focusFirst = function(){
    const f = this.dialog.querySelectorAll(FOCUSABLE);
    if(f.length) f[0].focus();
    else this.dialog.focus();
  };

  Modal.prototype.onKeydown = function(ev){
    if(ev.key === 'Escape'){
      if(this.opts.dismissOnEscape !== false){ ev.preventDefault(); this.close(); }
      return;
    }
    if(ev.key === 'Tab'){
      // Trap focus within the dialog.
      const f = Array.prototype.filter.call(this.dialog.querySelectorAll(FOCUSABLE), el => el.offsetParent !== null || el === document.activeElement);
      if(!f.length) return;
      const first = f[0], last = f[f.length - 1];
      if(ev.shiftKey && document.activeElement === first){ ev.preventDefault(); last.focus(); }
      else if(!ev.shiftKey && document.activeElement === last){ ev.preventDefault(); first.focus(); }
    }
  };

  Modal.prototype.lockScroll = function(on){
    try { document.body.style.overflow = on ? 'hidden' : ''; } catch(e){}
  };

  Modal.prototype.setActionDisabled = function(label, disabled){
    Array.prototype.forEach.call(this.foot.querySelectorAll('.nmModalBtn'), (btn) => {
      if(btn.textContent === label) btn.disabled = !!disabled;
    });
  };

  Modal.prototype.close = function(){
    if(this.closed) return;
    this.closed = true;
    document.removeEventListener('keydown', this.onKeydown, true);
    this.lockScroll(false);
    if(this.overlay && this.overlay.parentNode) this.overlay.parentNode.removeChild(this.overlay);
    if(this.previousActive && typeof this.previousActive.focus === 'function'){
      try { this.previousActive.focus(); } catch(e){}
    }
    if(typeof this.opts.onClose === 'function') this.opts.onClose(this);
  };

  global.NMModal = {
    open: (opts) => new Modal(opts),
    Modal
  };
})(window);
