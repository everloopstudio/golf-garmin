import Toybox.Lang;
using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

// Envia las rondas guardadas al servidor al arrancar la app. Las pendientes se conservan en
// Storage hasta que el servidor responde 200, asi que no se pierde nada si no hay conexion con el movil.
class GolfSync {

    var status = :idle;  // :idle, :sending, :ok, :failed
    var lastCode = null; // ultimo codigo de respuesta (HTTP o error de Garmin, p.ej. -104 = sin movil)

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

    function sendPending() {
        if (status == :sending) {
            return;
        }
        var q = pending();
        if (q == null) {
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
                sendPending();
                return;
            }
        } else {
            status = :failed;
        }
        WatchUi.requestUpdate();
    }
}
