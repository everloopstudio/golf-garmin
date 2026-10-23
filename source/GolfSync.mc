import Toybox.Lang;
using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

// Envia las rondas guardadas al servidor: al salir del resumen de la ronda y, por si alguna
// quedo pendiente, al arrancar la app. Las pendientes se conservan en Storage hasta que el
// servidor responde 200, asi que no se pierde nada si no hay conexion con el movil.
class GolfSync {

    var status = :idle;  // :idle, :sending, :ok, :failed
    var lastCode = null; // ultimo codigo de respuesta (HTTP o error de Garmin, p.ej. -104 = sin movil)
    var onDone = null;   // se llama al terminar la cola de envio, bien o mal

    function pending() {
        try {
            var q = Application.Storage.getValue("pending");
            if (q != null && q.size() > 0) {
                return q;
            }
        } catch (e) {
        }
        return null;
    }

    // done: metodo opcional a llamar cuando se termine de enviar todo lo pendiente.
    function sendPending(done as Method or Null) as Void {
        if (done != null) {
            onDone = done;
        }
        if (status == :sending) {
            return;
        }
        var q = pending();
        if (q == null) {
            finishQueue();
            return;
        }
        status = :sending;
        try {
            Communications.makeWebRequest(webhookUrl(), q[0], {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {
                    "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                    "X-Device-Token" => deviceToken()
                },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onResponse));
        } catch (e) {
            status = :failed;
            lastCode = "EXC";
            finishQueue();
        }
        WatchUi.requestUpdate();
    }

    function onResponse(code as Number, data as Dictionary or String or Null) as Void {
        lastCode = code;
        if (code == 200) {
            var q = pending();
            if (q != null) {
                q = q.slice(1, q.size());
                try {
                    Application.Storage.setValue("pending", q);
                } catch (e) {
                }
            }
            status = :ok;
            if (pending() != null) {
                sendPending(null);
                return;
            }
        } else {
            status = :failed;
        }
        finishQueue();
        WatchUi.requestUpdate();
    }

    // La API de campos cuelga del mismo servidor que la de rondas: .../api/rounds -> .../api/courses
    function coursesUrl() {
        var u = webhookUrl();
        return u.substring(0, u.length() - 6) + "courses";
    }

    function fetchCourses() {
        try {
            Communications.makeWebRequest(coursesUrl(), null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "X-Device-Token" => deviceToken() },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onCourses));
        } catch (e) {
        }
    }

    // Guarda la lista como [[nombre, [pares]], ...], descartando entradas mal formadas.
    function onCourses(code as Number, data as Dictionary or String or Null) as Void {
        if (code != 200 || !(data instanceof Dictionary) || !(data["courses"] instanceof Array)) {
            return;
        }
        var list = [];
        var src = data["courses"] as Array;
        for (var i = 0; i < src.size(); i++) {
            var c = src[i];
            if (c instanceof Dictionary && c["name"] instanceof String && c["pars"] instanceof Array
                    && (c["pars"] as Array).size() > 0) {
                list.add([c["name"], c["pars"]]);
            }
        }
        if (list.size() > 0) {
            try {
                Application.Storage.setValue("courses", list);
            } catch (e) {
            }
        }
    }

    function finishQueue() {
        if (onDone != null) {
            var d = onDone;
            onDone = null;
            d.invoke();
        }
    }
}
