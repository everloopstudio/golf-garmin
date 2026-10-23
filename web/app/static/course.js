// Formulario de campo: con 9 hoyos oculta (y desactiva) los hoyos 10-18; suma el par total.
(function () {
  var form = document.querySelector('.course-form');
  var back = form.querySelectorAll('.back9 input');
  function nine() { return form.querySelector('input[name=holes]:checked').value === '9'; }
  function update() {
    var n = nine();
    back.forEach(function (i) { i.disabled = n; i.parentNode.hidden = n; });
    var total = 0;
    form.querySelectorAll('input[name=par]:not(:disabled)').forEach(function (i) { total += parseInt(i.value, 10) || 0; });
    document.getElementById('par-total').textContent = total;
  }
  form.addEventListener('input', update);
  form.addEventListener('change', update);
  update();
})();
