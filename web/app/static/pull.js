// Deslizar hacia abajo desde arriba del todo para recargar (util como app en la pantalla de inicio).
(function () {
  var THRESHOLD = 70;
  var ind = document.createElement('div');
  ind.className = 'pull';
  ind.textContent = '↓';
  document.body.appendChild(ind);

  var startY = null;
  var dy = 0;

  function interactive(el) {
    return el.closest && el.closest('#map, input, button, a, select, textarea, .scroll');
  }

  window.addEventListener('touchstart', function (e) {
    if (window.scrollY > 0 || e.touches.length !== 1 || interactive(e.target)) {
      startY = null;
      return;
    }
    startY = e.touches[0].clientY;
    dy = 0;
  }, { passive: true });

  window.addEventListener('touchmove', function (e) {
    if (startY === null) return;
    dy = Math.max(0, e.touches[0].clientY - startY);
    var pull = Math.min(dy, THRESHOLD * 1.6);
    ind.style.transform = 'translate(-50%, ' + (pull * 0.6) + 'px)';
    ind.style.opacity = Math.min(1, pull / THRESHOLD);
    ind.classList.toggle('ready', dy >= THRESHOLD);
  }, { passive: true });

  window.addEventListener('touchend', function () {
    if (startY === null) return;
    startY = null;
    if (dy >= THRESHOLD) {
      ind.classList.add('loading');
      ind.textContent = '';
      window.location.reload();
      return;
    }
    ind.style.transform = '';
    ind.style.opacity = '0';
    ind.classList.remove('ready');
  });
})();
