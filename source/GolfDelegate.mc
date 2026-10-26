using Toybox.Application;
using Toybox.Attention;
using Toybox.System;
using Toybox.Timer;
using Toybox.WatchUi;

// Controles del Instinct 2:
//   START/STOP (GPS)   -> +1 golpe (vibra, guarda la posicion GPS)
//   UP                 -> -1 golpe: pide confirmacion (otro UP antes de 3 s)
//   DOWN               -> hoyo siguiente
//   BACK (SET)         -> menu: continuar, hoyo anterior, guardar y salir, descartar
class GolfDelegate extends WatchUi.BehaviorDelegate {

    var model;
    var undoTimer = null;

    function initialize(m) {
        BehaviorDelegate.initialize();
        model = m;
    }

    // Quitar un golpe pide un segundo UP: el primero solo muestra el aviso en pantalla.
    function armUndo() {
        model.undoArmed = true;
        if (undoTimer == null) {
            undoTimer = new Timer.Timer();
        }
        undoTimer.stop();
        undoTimer.start(method(:disarmUndo), 3000, false);
    }

    function disarmUndo() as Void {
        if (undoTimer != null) {
            undoTimer.stop();
        }
        if (model.undoArmed) {
            model.undoArmed = false;
            WatchUi.requestUpdate();
        }
    }

    function onSelect() {
        disarmUndo();
        model.markShot();
        if (Attention has :vibrate) {
            Attention.vibrate([ new Attention.VibeProfile(60, 150) ]);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        if (model.strokes[model.hole] == 0) {
            return true;  // nada que quitar
        }
        if (model.undoArmed) {
            disarmUndo();
            model.undoShot();
        } else {
            armUndo();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        disarmUndo();
        model.nextHole();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        disarmUndo();
        openMenu();
        return true;
    }

    function openMenu() {
        var menu = new WatchUi.Menu2({ :title => "Ronda" });
        menu.addItem(new WatchUi.MenuItem("Continuar", null, :cont, {}));
        menu.addItem(new WatchUi.MenuItem("Hoyo anterior", null, :prev, {}));
        menu.addItem(new WatchUi.MenuItem("Guardar y salir", null, :save, {}));
        menu.addItem(new WatchUi.MenuItem("Descartar", null, :discard, {}));
        WatchUi.pushView(menu, new GolfMenuDelegate(model), WatchUi.SLIDE_UP);
    }
}

class GolfMenuDelegate extends WatchUi.Menu2InputDelegate {

    var model;

    function initialize(m) {
        Menu2InputDelegate.initialize();
        model = m;
    }

    function onSelect(item) {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        if (id == :prev) {
            model.prevHole();
        } else if (id == :save) {
            model.finish(true);
            WatchUi.switchToView(new SummaryView(model, true), new SummaryDelegate(model), WatchUi.SLIDE_IMMEDIATE);
        } else if (id == :discard) {
            model.finish(false);
            WatchUi.switchToView(new SummaryView(model, false), new SummaryDelegate(model), WatchUi.SLIDE_IMMEDIATE);
        }
        WatchUi.requestUpdate();
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
    }
}

// Resumen: cualquier boton envia la ronda a la web y, al terminar, guarda la actividad y sale.
// Guardar justo al salir evita el "failed" de la subida automatica a Garmin Connect.
class SummaryDelegate extends WatchUi.BehaviorDelegate {

    var model;
    var leaving = false;
    var timer = null;

    function initialize(m) {
        BehaviorDelegate.initialize();
        model = m;
    }

    function onButton() {
        if (leaving) {
            saveAndExit();  // segunda pulsacion: no esperar a la web (la ronda queda en cola)
            return true;
        }
        leaving = true;
        timer = new Timer.Timer();
        timer.start(method(:saveAndExit), 15000, false);
        Application.getApp().sync.sendPending(method(:saveAndExit));
        return true;
    }

    function saveAndExit() as Void {
        if (timer != null) {
            timer.stop();
        }
        model.saveSession();
        System.exit();
    }

    function onSelect() {
        return onButton();
    }

    function onBack() {
        return onButton();
    }

    function onNextPage() {
        return onButton();
    }

    function onPreviousPage() {
        return onButton();
    }
}

// Menu inicial: elegir campo y, si tiene mas de 9 hoyos, cuantos jugar.
class CourseMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var course = Application.getApp().courses[item.getId()];
        var pars = course[1];
        if (pars.size() <= 9) {
            startRound(course[0], pars, 1);
            return;
        }
        var menu = new WatchUi.Menu2({ :title => course[0] });
        menu.addItem(new WatchUi.MenuItem("18 hoyos", null, :all, {}));
        menu.addItem(new WatchUi.MenuItem("9 primeros", null, :front, {}));
        menu.addItem(new WatchUi.MenuItem("9 ultimos", null, :back, {}));
        WatchUi.pushView(menu, new HolesMenuDelegate(course[0], pars), WatchUi.SLIDE_LEFT);
    }
}

class HolesMenuDelegate extends WatchUi.Menu2InputDelegate {

    var name;
    var pars;

    function initialize(n, p) {
        Menu2InputDelegate.initialize();
        name = n;
        pars = p;
    }

    function onSelect(item) {
        var id = item.getId();
        var n = pars.size();
        var chosen = pars;
        var first = 1;
        if (id == :front) {
            chosen = pars.slice(0, 9);
        } else if (id == :back) {
            chosen = pars.slice(n - 9, n);
            first = n - 8;
        }
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        startRound(name, chosen, first);
    }

    function onBack() {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }
}

function startRound(name, pars, first) {
    var model = new GolfModel(name, pars, first);
    model.startRound();
    Application.getApp().model = model;
    WatchUi.switchToView(new GolfView(model), new GolfDelegate(model), WatchUi.SLIDE_IMMEDIATE);
}
