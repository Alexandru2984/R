(function () {
  'use strict';
  let lastActivity = 0;
  function activity() {
    const now = Date.now();
    if (now - lastActivity > 30000 && window.Shiny && Shiny.setInputValue) {
      lastActivity = now;
      Shiny.setInputValue('activity', now, {priority: 'event'});
    }
  }
  document.addEventListener('pointerdown', activity, {passive: true});
  document.addEventListener('keydown', function (event) {
    activity();
    if (event.key === '/' && !event.ctrlKey && !event.metaKey && !event.altKey &&
        !/INPUT|TEXTAREA|SELECT/.test(event.target.tagName) && !event.target.isContentEditable) {
      const input = document.getElementById('path_filter');
      if (input && input.getClientRects().length) { event.preventDefault(); input.focus(); }
    }
  });
  // Give newly opened dialogs a useful keyboard focus target.
  document.addEventListener('shown.bs.modal', function () {
    const input = document.querySelector('.modal.show input');
    if (input) input.focus();
  });
})();

// Native date controls avoid the system datepicker's noConflict/data-API bug.
(function () {
  'use strict';
  function register() {
    if (!window.Shiny || !window.jQuery) return;
    const $ = window.jQuery;
    const binding = new Shiny.InputBinding();
    $.extend(binding, {
      find: function (scope) { return $(scope).find('.traffic-date-range'); },
      getValue: function (el) { return Array.from(el.querySelectorAll('input')).map(input => input.value); },
      subscribe: function (el, callback) { $(el).on('change.trafficDates', 'input', function () { callback(false); }); },
      unsubscribe: function (el) { $(el).off('.trafficDates'); },
      receiveMessage: function (el, data) {
        const inputs = el.querySelectorAll('input');
        if (data.value) {
          if (data.value.start !== undefined && data.value.start !== null) inputs[0].value = data.value.start;
          if (data.value.end !== undefined && data.value.end !== null) inputs[1].value = data.value.end;
        }
        if (data.max) inputs.forEach(input => { input.max = data.max; });
        if (data.min) inputs.forEach(input => { input.min = data.min; });
        $(inputs[0]).trigger('change');
      }
    });
    Shiny.inputBindings.register(binding, 'traffic.nativeDateRange');
  }
  if (window.Shiny) register(); else document.addEventListener('DOMContentLoaded', register, {once: true});
})();
