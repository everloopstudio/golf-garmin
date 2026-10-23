using Toybox.Graphics;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

// Pantalla de arranque: ruedita mientras se descarga la lista de campos.
class LoadingView extends WatchUi.View {

    var timer;
    var angle = 90;

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

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
        dc.clear();
        // la ruedita va dentro de la esfera pequena si el reloj la tiene; si no, en el centro
        var sub = (WatchUi has :getSubscreen) ? WatchUi.getSubscreen() : null;
        var sx = cx;
        var sy = h * 0.30;
        var sr = 16;
        if (sub != null) {
            sx = sub.x + sub.width / 2;
            sy = sub.y + sub.height / 2;
            sr = sub.width / 2 - 8;
            dc.fillCircle(sx, sy, sub.width / 2);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        }
        dc.setPenWidth(4);
        dc.drawArc(sx, sy, sr, Graphics.ARC_CLOCKWISE, angle, angle - 100);
        dc.setPenWidth(1);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 0.46, Graphics.FONT_MEDIUM, "GOLFITO", Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(cx, h * 0.66, Graphics.FONT_XTINY, "Cargando campos", Graphics.TEXT_JUSTIFY_CENTER);
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
