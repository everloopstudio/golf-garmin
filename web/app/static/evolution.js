(function () {
  var data = JSON.parse(document.getElementById('chart-data').textContent);
  var css = getComputedStyle(document.documentElement);
  var accent = css.getPropertyValue('--accent').trim();
  var grid = css.getPropertyValue('--line').trim();
  var text = css.getPropertyValue('--muted').trim();
  new Chart(document.getElementById('evo'), {
    type: 'line',
    data: {
      labels: data.map(function (d) { return d.label; }),
      datasets: [{
        data: data.map(function (d) { return d.diff; }),
        borderColor: accent, backgroundColor: accent, tension: 0.3, pointRadius: 3, borderWidth: 2
      }]
    },
    options: {
      maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: text }, grid: { display: false } },
        y: { ticks: { color: text }, grid: { color: grid }, title: { display: true, text: 'vs par', color: text } }
      }
    }
  });
})();
