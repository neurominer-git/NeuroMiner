(function () {
  // Shared, presentation-only help authority for training-template editors.
  function attach(modal, layout, file, title) {
    const panel = document.createElement('aside');
    panel.className = 'nmHelpPanel hidden';
    panel.innerHTML = '<div class="nmHelpHeader"><span>Context help</span><button type="button">Close help</button></div><iframe class="nmHelpFrame" sandbox=""></iframe>';
    const frame = panel.querySelector('iframe');
    frame.title = title;
    layout.appendChild(panel);
    function close() {
      panel.classList.add('hidden');
      modal.classList.remove('nmHelpOpen');
    }
    function open(topic) {
      const url = new URL(file, document.baseURI);
      url.hash = topic;
      frame.src = window.NMBridgeAuthenticatedURL ? window.NMBridgeAuthenticatedURL(url.toString()) : url.toString();
      panel.classList.remove('hidden');
      modal.classList.add('nmHelpOpen');
    }
    function button(parent, topic, label) {
      const control = document.createElement('button');
      control.type = 'button';
      control.className = 'nmHelpButton';
      control.textContent = '?';
      control.title = 'Help: ' + label;
      control.setAttribute('aria-label', 'Help: ' + label);
      control.onclick = event => {
        event.preventDefault();
        event.stopPropagation();
        open(typeof topic === 'function' ? topic() : topic);
      };
      parent.appendChild(control);
    }
    panel.querySelector('.nmHelpHeader button').onclick = close;
    return {button, close};
  }
  // One form-layout authority for the CV, Stacking and alternative-label editors.
  function attachForm(modal, file, title, overview, defaultTopic) {
    const body = modal.querySelector('.selectorBody');
    const layout = document.createElement('div');
    layout.className = 'nmFormHelpLayout';
    body.before(layout);
    layout.appendChild(body);
    const help = attach(modal, layout, file, title);
    help.button(modal.querySelector('.selectorHead b'), overview, title);
    body.querySelectorAll('.field > label').forEach(label => {
      const control = label.control || label.querySelector('input[id], select[id]');
      help.button(label, label.dataset.helpTopic || (control && control.id) || defaultTopic, label.textContent);
    });
    modal.querySelectorAll('.rfePane h2, .rfeMini > h3').forEach(heading => help.button(heading, heading.parentElement.id, heading.textContent));
    return help;
  }
  window.NMContextHelp = {attach, attachForm};
})();
