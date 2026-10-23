using Toybox.Graphics;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

// Pantalla de arranque: ruedita mientras se descarga la lista de campos.
class LoadingView extends WatchUi.View {

    var timer;
    var angle = 90;
    var bg = null;
    var logo = null;

    function initialize() {
        View.initialize();
        timer = new Timer.Timer();
    }

    function onShow() {
        timer.start(method(:tick), 100, true);
    }

    function onHide() {
        timer.stop();
    }

    function tick() as Void {
        angle = (angle - 30) % 360;
        WatchUi.requestUpdate();
    }

    // Fondo de estrellas y green (bitmap LoadingBg, ver web/icons/make_icons.py); encima
    // "GOLFITO" en blanco, "Cargando campos" sobre el green y, en la esfera pequena, el logo
    // de Everloop con la ruedita girando alrededor.
    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (bg == null) {
            bg = WatchUi.loadResource(Rez.Drawables.LoadingBg);
        }
        dc.drawBitmap(0, 0, bg);

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.33, Graphics.FONT_LARGE, "GOLFITO", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.82, Graphics.FONT_XTINY, "Cargando campos", Graphics.TEXT_JUSTIFY_CENTER);

        // ruedita: en la esfera pequena si el reloj la tiene; si no, centrada arriba
        var sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var sx = cx;
        var sy = h * 0.20;
        var sr = 14;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (sub != null) {
            sx = sub.x + sub.width / 2;
            sy = sub.y + sub.height / 2;
            sr = sub.width / 2 - 6;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sx, sy, sub.width / 2);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(sx, sy, sub.width / 2 - 1);
            if (logo == null) {
                logo = WatchUi.loadResource(Rez.Drawables.EverloopLogo);
            }
            dc.drawBitmap(sx - logo.getWidth() / 2, sy - logo.getHeight() / 2, logo);
        }
        dc.setPenWidth(4);
        dc.drawArc(sx, sy, sr, Graphics.ARC_CLOCKWISE, angle, angle - 100);
        dc.setPenWidth(1);
    }
}

class LoadingDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() {
        System.exit();
    }
}
