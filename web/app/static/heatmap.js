// Mapa de calor de un campo: todos los golpes de todas las rondas, o solo donde cae la salida
// (la posicion del segundo golpe de cada hoyo). Se puede filtrar por hoyo.
(function () {
  var pts = JSON.parse(document.getElementById('heat-data').textContent);  // [lat, lon, hoyo, n]
  var map = L.map('heatmap', { zoomControl: true, attributionControl: false });
  golfitoBasemap(map, '#heat-basemap', '#heat-credit');
  var heat = L.heatLayer([], {
    radius: 22, blur: 18, maxZoom: 19, minOpacity: 0.35, max: 0.6,
    gradient: { 0.2: '#2c7bb6', 0.45: '#abd9e9', 0.65: '#ffffbf', 0.85: '#fdae61', 1.0: '#d7191c' }
  }).addTo(map);

  // el radio va en pixeles: se ajusta al zoom para que al ver todo el campo no se fundan las manchas
  function fitRadius() {
    var r = Math.max(10, Math.min(26, Math.round(8 * Math.pow(2, map.getZoom() - 16))));
    heat.setOptions({ radius: r, blur: Math.round(r * 0.8) });
  }
  map.on('zoomend', fitRadius);

  var mode = 'all';
  var hole = null;

  function draw() {
    var sel = pts.filter(function (p) {
      return (hole === null || p[2] === hole) && (mode === 'all' || p[3] === 2);
    });
    heat.setLatLngs(sel.map(function (p) { return [p[0], p[1], 1]; }));
    var what = mode === 'all' ? 'golpe' : 'salida';
    document.getElementById('heat-count').textContent =
      sel.length + ' ' + what + (sel.length === 1 ? '' : 's') + (hole === null ? '' : ' en el hoyo ' + hole);
    if (sel.length) {
      map.fitBounds(sel.map(function (p) { return [p[0], p[1]]; }), { padding: [30, 30], maxZoom: 19 });
    }
  }

  function group(sel, attr, onPick) {
    var buttons = document.querySelectorAll(sel + ' button');
    buttons.forEach(function (b) {
      b.addEventListener('click', function () {
        buttons.forEach(function (x) { x.classList.remove('on'); });
        b.classList.add('on');
        onPick(b.dataset[attr]);
        draw();
      });
    });
  }

  var holesEl = document.getElementById('heat-holes');
  var holes = Array.from(new Set(pts.map(function (p) { return p[2]; }))).sort(function (a, b) { return a - b; });
  [null].concat(holes).forEach(function (h) {
    var b = document.createElement('button');
    b.type = 'button';
    b.textContent = h === null ? 'Todos' : String(h);
    b.dataset.hole = h === null ? '' : String(h);
    if (h === null) b.classList.add('on');
    holesEl.appendChild(b);
  });
  group('#heat-holes', 'hole', function (v) { hole = v === '' ? null : parseInt(v, 10); });
  group('#heat-mode', 'mode', function (v) { mode = v; });
  draw();
})();
