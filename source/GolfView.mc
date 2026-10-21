using Toybox.Graphics;
using Toybox.Timer;
using Toybox.WatchUi;

function fmtMeters(d) {
    if (d == null) {
        return "--";
    }
    return (d + 0.5).toNumber().toString() + " m";
}

function fmtKm(d) {
    if (d == null) {
        return "--";
    }
    var tenths = (d / 100.0 + 0.5).toNumber();
    return (tenths / 10).toString() + "." + (tenths % 10).toString() + " km";
}

function fmtDiff(strokes, par) {
    var diff = strokes - par;
    if (diff > 0) {
        return "+" + diff.toString();
    }
    return diff.toString();
}

// Pantalla principal: hoyo, golpes del hoyo, total y distancias.
class GolfView extends WatchUi.View {

    var model;
    var timer;

    function initialize(m) {
        View.initialize();
        model = m;
        timer = new Timer.Timer();
    }

    function onShow() {
        timer.start(method(:tick), 1000, true);
    }

    function onHide() {
        timer.stop();
    }

    function tick() {
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var par = model.pars[model.hole];
        dc.drawText(cx, h * 0.04, Graphics.FONT_SMALL,
            "Hoyo " + (model.firstHole + model.hole) + "/" + (model.firstHole + model.holes - 1) + "  Par " + par,
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(cx, h * 0.14, Graphics.FONT_NUMBER_HOT,
            model.strokes[model.hole].toString(),
            Graphics.TEXT_JUSTIFY_CENTER);

        var total = model.totalStrokes();
        var played = model.playedPar();
        var totalTxt = "Total " + total;
        if (played > 0) {
            totalTxt = totalTxt + " (" + fmtDiff(total, played) + ")";
        }
        dc.drawText(cx, h * 0.50, Graphics.FONT_SMALL, totalTxt, Graphics.TEXT_JUSTIFY_CENTER);

        var live = model.sinceLastShot();
        var line3 = "";
        if (live != null) {
            line3 = "Desde golpe " + fmtMeters(live);
        } else if (model.lastShotDist != null) {
            line3 = "Ultimo golpe " + fmtMeters(model.lastShotDist);
        }
        dc.drawText(cx, h * 0.64, Graphics.FONT_XTINY, line3, Graphics.TEXT_JUSTIFY_CENTER);

        var steps = model.stepsNow();
        var stepsTxt = (steps == null) ? "--" : steps.toString();
        dc.drawText(cx, h * 0.76, Graphics.FONT_XTINY,
            stepsTxt + " pasos  " + fmtKm(model.distanceNowM()),
            Graphics.TEXT_JUSTIFY_CENTER);

        dc.drawText(cx, h * 0.88, Graphics.FONT_XTINY,
            model.gpsOk() ? "GPS ok" : "Buscando GPS...",
            Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// Resumen final de la ronda.
class SummaryView extends WatchUi.View {

    var model;
    var saved;

    function initialize(m, s) {
        View.initialize();
        model = m;
        saved = s;
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        dc.drawText(cx, h * 0.05, Graphics.FONT_SMALL,
            saved ? "Ronda guardada" : "Ronda descartada",
            Graphics.TEXT_JUSTIFY_CENTER);

        var total = model.totalStrokes();
        dc.drawText(cx, h * 0.17, Graphics.FONT_NUMBER_HOT, total.toString(),
            Graphics.TEXT_JUSTIFY_CENTER);

        var played = model.playedPar();
        if (played > 0) {
            dc.drawText(cx, h * 0.52, Graphics.FONT_SMALL,
                "Par " + played + " (" + fmtDiff(total, played) + ")",
                Graphics.TEXT_JUSTIFY_CENTER);
        }

        var steps = model.endSteps;
        dc.drawText(cx, h * 0.68, Graphics.FONT_XTINY,
            ((steps == null) ? "--" : steps.toString()) + " pasos  " + fmtKm(model.endDistance),
            Graphics.TEXT_JUSTIFY_CENTER);

        var msg = saved ? "Pulsa para guardar y salir" : "Pulsa una tecla para salir";
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
