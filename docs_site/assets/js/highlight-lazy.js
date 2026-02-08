(function() {
  'use strict';

  var observer = new IntersectionObserver(function(entries) {
    entries.forEach(function(entry) {
      if (entry.isIntersecting) {
        var code = entry.target;
        if (!code.classList.contains('hljs')) {
          hljs.highlightElement(code);
        }
        observer.unobserve(code);
      }
    });
  }, {
    rootMargin: '100px'
  });

  function observeCodeBlocks() {
    document.querySelectorAll('pre code:not(.hljs)').forEach(function(block) {
      observer.observe(block);
    });
  }

  // Highlight code inside details when opened
  function setupDetailsHighlighting() {
    document.querySelectorAll('details').forEach(function(details) {
      if (details.dataset.highlightBound) return;
      details.dataset.highlightBound = 'true';
      details.addEventListener('toggle', function() {
        if (details.open) {
          details.querySelectorAll('pre code:not(.hljs)').forEach(function(code) {
            hljs.highlightElement(code);
          });
        }
      });
    });
  }

  // Initial observation
  observeCodeBlocks();
  setupDetailsHighlighting();

  // Re-observe after Turbo navigation
  document.addEventListener('turbo:load', function() {
    observeCodeBlocks();
    setupDetailsHighlighting();
  });
})();
