import Toybox.Lang;
using Toybox.Application;
using Toybox.Communications;
using Toybox.WatchUi;

// Envia las rondas guardadas al servidor. Las pendientes se conservan en Storage y se
// reintentan en el siguiente arranque, asi que no se pierde nada si no hay conexion con el movil.
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

    var onDone = null;   // se llama al terminar la cola de envio (bien o mal)

    // done: metodo opcional a llamar cuando termine el envio de todo lo pendiente.
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

    function finishQueue() {
        if (onDone != null) {
            var d = onDone;
            onDone = null;
            d.invoke();
        }
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
}
