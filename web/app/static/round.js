(function () {
  var shots = JSON.parse(document.getElementById('shots-data').textContent);
  var pts = shots.filter(function (s) { return s.lat !== null && s.lon !== null; });
  var mapEl = document.getElementById('map');
  if (!pts.length) {
    mapEl.className = 'empty';
    mapEl.textContent = 'Sin coordenadas GPS en esta ronda';
    return;
  }
  var map = L.map('map', { zoomControl: true, attributionControl: false });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }).addTo(map);
  var layer = L.layerGroup().addTo(map);
  var accent = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim();

  function draw(hole) {
    layer.clearLayers();
    var sel = pts.filter(function (s) { return hole === null || s.hole === hole; });
    var holes = {};
    sel.forEach(function (s) { (holes[s.hole] = holes[s.hole] || []).push(s); });
    Object.keys(holes).forEach(function (h) {
      var line = holes[h].map(function (s) { return [s.lat, s.lon]; });
      if (line.length > 1) L.polyline(line, { color: accent, weight: 3, opacity: 0.7 }).addTo(layer);
    });
    sel.forEach(function (s) {
      var icon = L.divIcon({ className: '', html: '<span class="pin">' + s.n + '</span>', iconSize: [24, 24], iconAnchor: [12, 12] });
      var tip = 'Hoyo ' + s.hole + ' · golpe ' + s.n + (s.dist !== null ? ' · ' + Math.round(s.dist) + ' m' : '');
      L.marker([s.lat, s.lon], { icon: icon }).bindTooltip(tip).addTo(layer);
    });
    if (sel.length) map.fitBounds(sel.map(function (s) { return [s.lat, s.lon]; }), { padding: [30, 30], maxZoom: 19 });
  }

  var chips = document.getElementById('chips');
  var holes = Array.from(new Set(pts.map(function (s) { return s.hole; }))).sort(function (a, b) { return a - b; });
  function chip(label, hole) {
    var b = document.createElement('button');
    b.type = 'button'; b.textContent = label;
    b.addEventListener('click', function () {
      Array.from(chips.children).forEach(function (c) { c.classList.remove('on'); });
      b.classList.add('on'); draw(hole);
    });
    chips.appendChild(b); return b;
  }
  chip('Todos', null).classList.add('on');
  holes.forEach(function (h) { chip(String(h), h); });
  draw(null);
})();
