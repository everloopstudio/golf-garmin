using Toybox.Application;
using Toybox.Timer;
using Toybox.WatchUi;

class GolfApp extends Application.AppBase {

    var sync = new GolfSync();
    var model = null;    // ronda en curso, para guardarla si la app se cierra desde el sistema
    var courses = null;  // campos del menu, fijados al mostrarlo
    var loadTimer = null;
    var introTimer = null;
    var coursesReady = false;  // lista descargada, o se agoto la espera
    var introDone = false;     // la intro ya se ha visto el tiempo minimo

    function initialize() {
        AppBase.initialize();
    }

    function onStop(state) {
        if (model != null) {
            model.saveSession();
        }
    }

    // Arranca con la intro (fondo de estrellas y ruedita). El menu de campos sale cuando
    // se cumplen las dos cosas: la intro lleva al menos 3 s y ha llegado la lista del
    // servidor (o, sin conexion, han pasado 6 s y se usa la ultima lista guardada).
    function getInitialView() {
        sync.sendPending(null);  // rondas que no se pudieron enviar al salir la ultima vez
        sync.fetchCourses(method(:onCoursesReady));
        loadTimer = new Timer.Timer();
        loadTimer.start(method(:onCoursesReady), 6000, false);
        introTimer = new Timer.Timer();
        introTimer.start(method(:onIntroDone), 3000, false);
        return [ new LoadingView(), new LoadingDelegate() ];
    }

    function onCoursesReady() as Void {
        coursesReady = true;
        if (loadTimer != null) {
            loadTimer.stop();
        }
        showCourseMenu();
    }

    function onIntroDone() as Void {
        introDone = true;
        showCourseMenu();
    }

    function showCourseMenu() as Void {
        if (!coursesReady || !introDone || courses != null) {
            return;  // falta algo, o el menu ya se mostro
        }
        courses = getCourses();
        var menu = new WatchUi.Menu2({ :title => "Campo" });
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        WatchUi.switchToView(menu, new CourseMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}
