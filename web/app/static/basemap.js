// Capa de fondo de los mapas: mapa (OpenStreetMap) o satelite (Esri World Imagery).
// Conecta los botones [data-layer] de toggleSel, actualiza el credito y recuerda la eleccion.
window.golfitoBasemap = function (map, toggleSel, creditSel) {
  var bases = {
    map: { layer: L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19 }),
           credit: '© colaboradores de OpenStreetMap' },
    sat: { layer: L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                              { maxZoom: 19, maxNativeZoom: 18 }),
           credit: 'Imágenes © Esri, Maxar, Earthstar Geographics' }
  };
  var buttons = document.querySelectorAll(toggleSel + ' button');
  var current = null;
  function setBase(key) {
    if (!bases[key]) key = 'map';
    if (current) map.removeLayer(bases[current].layer);
    bases[key].layer.addTo(map).bringToBack();
    current = key;
    document.querySelector(creditSel).textContent = bases[key].credit;
    buttons.forEach(function (b) { b.classList.toggle('on', b.dataset.layer === key); });
    try { localStorage.setItem('golfito-basemap', key); } catch (e) {}
  }
  buttons.forEach(function (b) { b.addEventListener('click', function () { setBase(b.dataset.layer); }); });
  var saved = null;
  try { saved = localStorage.getItem('golfito-basemap'); } catch (e) {}
  setBase(saved || 'map');
};
