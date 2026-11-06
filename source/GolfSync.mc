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
    var coursesDone = null;

    function pendingCount() {
        var q = pending();
        return q == null ? 0 : q.size();
    }

    // Texto corto del ultimo fallo de envio, para mostrarlo en el reloj.
    function errorText() {
        var c = lastCode;
        if (c == null) {
            try {
                c = Application.Storage.getValue("lastErr");
            } catch (e) {
            }
        }
        return codeText(c);
    }

    // Motivo corto + codigo, p. ej. "sin movil (-104)". Codigos en Toybox.Communications.
    function codeText(c) {
        if (c == null) {
            return "";
        }
        var why = "error";
        if (c == -104) {
            why = "sin movil";
        } else if (c == -2) {
            why = "movil no responde";
        } else if (c == -102) {
            why = "envio muy grande";
        } else if (c == -300 || c == "timeout") {
            why = "sin respuesta";
        } else if (c == 401) {
            why = "token incorrecto";
        } else if (c == -1001) {
            why = "requiere https";
        }
        return c == "timeout" ? why : why + " (" + c + ")";
    }

    // Guarda el codigo del ultimo fallo (o lo borra con null) para verlo en la siguiente apertura.
    function rememberError(c) {
        try {
            Application.Storage.setValue("lastErr", c);
        } catch (e) {
        }
    }

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
            rememberError(lastCode);
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
            rememberError(null);
            if (pending() != null) {
                sendPending(null);
                return;
            }
        } else {
            status = :failed;
            rememberError(code);
        }
        finishQueue();
        WatchUi.requestUpdate();
    }

    // La API de campos cuelga del mismo servidor que la de rondas: .../api/rounds -> .../api/courses
    function coursesUrl() {
        var u = webhookUrl();
        return u.substring(0, u.length() - 6) + "courses";
    }

    // Prueba de conexion sin datos de ronda: GET .../healthz. Separa "no hay conexion" de
    // "la conexion va pero la ronda no sale".
    var pingCode = null;
    var pingDone = null;

    function ping(done as Method) as Void {
        pingDone = done;
        var u = webhookUrl();
        try {
            Communications.makeWebRequest(u.substring(0, u.length() - 10) + "healthz", null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onPing));
        } catch (e) {
            onPing(-999, null);
        }
    }

    function onPing(code as Number, data as Dictionary or String or Null) as Void {
        pingCode = code;
        if (pingDone != null) {
            var d = pingDone;
            pingDone = null;
            d.invoke();
        }
    }

    function pingText() {
        if (pingCode == null) {
            return "Pulsa para probar";
        }
        return pingCode == 200 ? "Conexion OK" : "Fallo: " + codeText(pingCode);
    }

    // done: se llama al terminar la descarga, haya ido bien o no.
    function fetchCourses(done as Method) as Void {
        coursesDone = done;
        try {
            Communications.makeWebRequest(coursesUrl(), null, {
                :method => Communications.HTTP_REQUEST_METHOD_GET,
                :headers => { "X-Device-Token" => deviceToken() },
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            }, method(:onCourses));
        } catch (e) {
            coursesDone.invoke();
        }
    }

    // Guarda la lista como [[nombre, [pares]], ...], descartando entradas mal formadas.
    function onCourses(code as Number, data as Dictionary or String or Null) as Void {
        if (code == 200 && data instanceof Dictionary && data["courses"] instanceof Array) {
            storeCourses(data["courses"] as Array);
        }
        if (coursesDone != null) {
            coursesDone.invoke();
        }
    }

    function storeCourses(src as Array) as Void {
        var list = [];
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
