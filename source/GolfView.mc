using Toybox.Application;
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

    // Distribucion pensada para el Instinct 2: el numero de hoyo va en la esfera pequena
    // (subscreen) de arriba a la derecha; el resto se reparte evitando el borde redondo.
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();

        var holeNo = model.firstHole + model.hole;
        var sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var topCx = cx;
        if (sub != null) {
            // esfera pequena: fondo negro, "HOYO" y el numero
            var scx = sub.x + sub.width / 2;
            var scy = sub.y + sub.height / 2;
            dc.fillCircle(scx, scy, sub.width / 2);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(scx, sub.y + sub.height * 0.14, Graphics.FONT_XTINY, "HOYO", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(scx, sub.y + sub.height * 0.36, Graphics.FONT_MEDIUM, holeNo.toString(), Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            topCx = (w * 0.18 + sub.x) / 2;
            dc.drawText(topCx, h * 0.09, Graphics.FONT_SMALL, "Par " + model.pars[model.hole], Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.drawText(cx, h * 0.06, Graphics.FONT_SMALL,
                "Hoyo " + holeNo + "  Par " + model.pars[model.hole], Graphics.TEXT_JUSTIFY_CENTER);
        }

        // golpes del hoyo, en grande
        dc.drawText(cx, h * 0.225, Graphics.FONT_NUMBER_THAI_HOT,
            model.strokes[model.hole].toString(), Graphics.TEXT_JUSTIFY_CENTER);

        var sepY = h * 0.615;
        dc.drawLine(w * 0.25, sepY, w * 0.75, sepY);

        // distancia: en vivo desde el ultimo golpe, o la del ultimo golpe medido
        var live = model.sinceLastShot();
        var distTxt = "Golpe ant.  --";
        if (live != null) {
            distTxt = "Desde golpe  " + fmtMeters(live);
        } else if (model.lastShotDist != null) {
            distTxt = "Golpe ant.  " + fmtMeters(model.lastShotDist);
        }
        dc.drawText(cx, h * 0.625, Graphics.FONT_XTINY, distTxt, Graphics.TEXT_JUSTIFY_CENTER);

        var total = model.totalStrokes();
        var played = model.playedPar();
        var totalTxt = "Total " + total;
        if (played > 0) {
            totalTxt = totalTxt + " (" + fmtDiff(total, played) + ")";
        }
        dc.drawText(cx, h * 0.735, Graphics.FONT_TINY, totalTxt, Graphics.TEXT_JUSTIFY_CENTER);

        // GPS (punto lleno = ok, vacio = buscando) y km recorridos
        var gps = model.gpsOk();
        var info = (gps ? "GPS  " : "GPS...  ") + fmtKm(model.distanceNowM());
        var infoW = dc.getTextWidthInPixels(info, Graphics.FONT_XTINY);
        var dotX = cx - infoW / 2 - 5;
        var infoY = h * 0.86;
        var dotY = infoY + dc.getFontHeight(Graphics.FONT_XTINY) / 2;
        if (gps) {
            dc.fillCircle(dotX, dotY, 3);
        } else {
            dc.drawCircle(dotX, dotY, 3);
        }
        dc.drawText(cx + 4, infoY, Graphics.FONT_XTINY, info, Graphics.TEXT_JUSTIFY_CENTER);
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
        if (saved && Application.getApp().sync.status == :sending) {
            msg = "Enviando...";
        }
        dc.drawText(cx, h * 0.86, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
