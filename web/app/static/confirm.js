// Pide confirmacion en los formularios con data-confirm (p. ej. eliminar ronda).
document.addEventListener('submit', function (e) {
  var msg = e.target.getAttribute('data-confirm');
  if (msg && !window.confirm(msg)) e.preventDefault();
});
