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

    // "Reintentar envio" del menu: al terminar se vuelve a montar el menu con el resultado.
    var notice = null;  // resultado del ultimo reintento, se muestra en el titulo del menu
    var focusPing = false;  // tras probar la conexion, dejar el cursor en esa opcion

    function retrySend() as Void {
        sync.sendPending(method(:onRetryDone));
    }

    function onRetryDone() as Void {
        notice = sync.pendingCount() == 0 ? "Enviadas OK" : null;
        rebuildMenu();
    }

    function testConnection() as Void {
        sync.ping(method(:onPingDone));
    }

    function onPingDone() as Void {
        focusPing = true;
        rebuildMenu();
    }

    function rebuildMenu() as Void {
        courses = null;
        showCourseMenu();
    }

    function showCourseMenu() as Void {
        if (!coursesReady || !introDone || courses != null) {
            return;  // falta algo, o el menu ya se mostro
        }
        courses = getCourses();
        // si quedan rondas sin enviar, el titulo lo dice (con el motivo del ultimo fallo)
        var n = sync.pendingCount();
        var title = "Campo";
        if (n > 0) {
            title = n + " sin enviar";
        } else if (notice != null) {
            title = notice;
            notice = null;
        }
        var menu = new WatchUi.Menu2({ :title => title });
        if (n > 0) {
            menu.addItem(new WatchUi.MenuItem("Reintentar envio", sync.errorText(), :retry, {}));
        }
        for (var i = 0; i < courses.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(courses[i][0], courses[i][1].size() + " hoyos", i, {}));
        }
        menu.addItem(new WatchUi.MenuItem("Probar conexion", sync.pingText(), :ping, {}));
        if (focusPing) {
            focusPing = false;
            menu.setFocus(courses.size() + (n > 0 ? 1 : 0));
        }
        WatchUi.switchToView(menu, new CourseMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
    }
}
