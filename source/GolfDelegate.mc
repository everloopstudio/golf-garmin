using Toybox.Application;
using Toybox.Attention;
using Toybox.System;
using Toybox.WatchUi;

// Controles del Instinct 2:
//   UP                 -> +1 golpe (vibra, guarda la posicion GPS)
//   DOWN               -> -1 golpe (deshace el ultimo)
//   START/STOP (GPS)   -> hoyo siguiente
//   BACK (SET)         -> menu: continuar, hoyo anterior, guardar y salir, descartar
class GolfDelegate extends WatchUi.BehaviorDelegate {

    var model;

    function initialize(m) {
        BehaviorDelegate.initialize();
        model = m;
    }

    function onSelect() {
        model.nextHole();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() {
        model.markShot();
        if (Attention has :vibrate) {
            Attention.vibrate([ new Attention.VibeProfile(60, 150) ]);
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onNextPage() {
        model.undoShot();
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
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

class SummaryDelegate extends WatchUi.BehaviorDelegate {

    var model;

    function initialize(m) {
        BehaviorDelegate.initialize();
        model = m;
    }

    function exitApp() {
        model.saveSession();
        System.exit();
    }

    function onSelect() {
        exitApp();
        return true;
    }

    function onBack() {
        exitApp();
        return true;
    }
}

// Menu inicial: elegir campo y, si tiene mas de 9 hoyos, cuantos jugar.
class CourseMenuDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var course = getCourses()[item.getId()];
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
