using Toybox.Application;
using Toybox.WatchUi;

class GolfApp extends Application.AppBase {

    var sync = new GolfSync();

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        sync.sendPending(null);  // reintenta rondas que no se llegaron a enviar
        var menu = new WatchUi.Menu2({ :title => "Campo" });
        var courses = getCourses();
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        return [ menu, new CourseMenuDelegate() ];
    }
}
