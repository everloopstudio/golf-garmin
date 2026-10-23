using Toybox.Application;
using Toybox.Timer;
using Toybox.WatchUi;

class GolfApp extends Application.AppBase {

    var sync = new GolfSync();
    var model = null;    // ronda en curso, para guardarla si la app se cierra desde el sistema
    var courses = null;  // campos del menu, fijados al mostrarlo
    var loadTimer = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStop(state) {
        if (model != null) {
            model.saveSession();
        }
    }

    // Arranca con la ruedita de carga; el menu de campos sale cuando llega la lista
    // del servidor o, sin conexion, a los 6 s con la ultima lista guardada.
    function getInitialView() {
        sync.sendPending(null);  // rondas que no se pudieron enviar al salir la ultima vez
        sync.fetchCourses(method(:showCourseMenu));
        loadTimer = new Timer.Timer();
        loadTimer.start(method(:showCourseMenu), 6000, false);
        return [ new LoadingView(), new LoadingDelegate() ];
    }

    function showCourseMenu() as Void {
        if (courses != null) {
            return;  // ya mostrado (llego la lista y luego salto el temporizador, o al reves)
        }
        if (loadTimer != null) {
            loadTimer.stop();
        }
        courses = getCourses();
        var menu = new WatchUi.Menu2({ :title => "Campo" });
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        WatchUi.switchToView(menu, new CourseMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}
