using Toybox.Application;
using Toybox.WatchUi;

class GolfApp extends Application.AppBase {

    var sync = new GolfSync();
    var model = null;    // ronda en curso, para guardarla si la app se cierra desde el sistema
    var courses = null;  // campos del menu; fijados al arrancar aunque llegue una lista nueva

    function initialize() {
        AppBase.initialize();
    }

    function onStop(state) {
        if (model != null) {
            model.saveSession();
        }
    }

    function getInitialView() {
        sync.sendPending(null);  // rondas que no se pudieron enviar al salir la ultima vez
        sync.fetchCourses();     // lista nueva para la proxima vez que se abra la app
        var menu = new WatchUi.Menu2({ :title => "Campo" });
        courses = getCourses();
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        return [ menu, new CourseMenuDelegate() ];
    }
}
