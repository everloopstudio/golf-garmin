using Toybox.Application;
using Toybox.WatchUi;

class GolfApp extends Application.AppBase {

    var sync = new GolfSync();
    var model = null;  // ronda en curso, para guardarla si la app se cierra desde el sistema

    function initialize() {
        AppBase.initialize();
    }

    function onStop(state) {
        if (model != null) {
            model.saveSession();
        }
    }

    function getInitialView() {
        sync.sendPending();  // envia las rondas guardadas (nunca durante el guardado, ver GolfModel.finish)
        var menu = new WatchUi.Menu2({ :title => "Campo" });
        var courses = getCourses();
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        return [ menu, new CourseMenuDelegate() ];
    }
}
