import Toybox.Lang;
using Toybox.Activity;
using Toybox.ActivityMonitor;
using Toybox.ActivityRecording;
using Toybox.Application;
using Toybox.FitContributor;
using Toybox.Math;
using Toybox.Position;
using Toybox.System;
using Toybox.Time;

// Estado de la ronda: golpes por hoyo, posiciones GPS de cada golpe y actividad grabada.
class GolfModel {

    var courseName;
    var firstHole;           // numero real del primer hoyo (1, o 10 si se juegan los 9 ultimos)
    var roundStart = 0;
    var pars;
    var holes;
    var hole = 0;            // hoyo actual (indice desde 0)
    var strokes;             // golpes por hoyo
    var shots = [];          // [hoyo, lat, lon, distDesdeGolpeAnterior, epoch]
    var lastLoc = null;      // [lat, lon] del ultimo golpe del hoyo actual
    var lastShotDist = null; // metros del ultimo golpe medido
    var session = null;
    var strokeField = null;  // campo FIT propio en cada registro: golpes acumulados
    var holeField = null;    // campo FIT propio en cada registro: hoyo actual
    var startSteps = 0;
    var endSteps = null;
    var endDistance = null;

    function initialize(name, p, first) {
        courseName = name;
        firstHole = first;
        pars = p;
        holes = pars.size();
        strokes = new [holes];
        for (var i = 0; i < holes; i++) {
            strokes[i] = 0;
        }
    }

    function onPosition(info as Position.Info) as Void {
        // Solo mantiene el GPS activo; la posicion se lee con Position.getInfo().
    }

    function startRound() {
        roundStart = Time.now().value();
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        var m = ActivityMonitor.getInfo();
        if (m != null && m.steps != null) {
            startSteps = m.steps;
        }
        session = ActivityRecording.createSession({
            :name => "Golf",
            :sport => Activity.SPORT_GOLF,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        try {
            strokeField = session.createField("golpes", 0, FitContributor.DATA_TYPE_UINT8,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
            holeField = session.createField("hoyo", 1, FitContributor.DATA_TYPE_UINT8,
                { :mesgType => FitContributor.MESG_TYPE_RECORD });
        } catch (e) {
            strokeField = null;
            holeField = null;
        }
        updateFields();
        session.start();
    }

    // Posicion actual [lat, lon] o null si el GPS aun no es fiable.
    function currentLoc() {
        var info = Position.getInfo();
        if (info == null || info.position == null) {
            return null;
        }
        if (info.accuracy == null || info.accuracy < Position.QUALITY_POOR) {
            return null;
        }
        return info.position.toDegrees();
    }

    function gpsOk() {
        return currentLoc() != null;
    }

    function distanceM(lat1, lon1, lat2, lon2) {
        var p1 = Math.toRadians(lat1);
        var p2 = Math.toRadians(lat2);
        var dp = Math.toRadians(lat2 - lat1);
        var dl = Math.toRadians(lon2 - lon1);
        var a = Math.sin(dp / 2) * Math.sin(dp / 2)
            + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2) * Math.sin(dl / 2);
        var c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return 6371000.0 * c;
    }

    // Distancia en metros desde el ultimo golpe hasta donde estoy ahora (en vivo).
    function sinceLastShot() {
        if (lastLoc == null) {
            return null;
        }
        var loc = currentLoc();
        if (loc == null) {
            return null;
        }
        return distanceM(lastLoc[0], lastLoc[1], loc[0], loc[1]);
    }

    function markShot() {
        var loc = currentLoc();
        strokes[hole] = strokes[hole] + 1;
        var d = null;
        if (loc != null && lastLoc != null) {
            d = distanceM(lastLoc[0], lastLoc[1], loc[0], loc[1]);
            lastShotDist = d;
        }
        lastLoc = loc;
        if (loc != null) {
            shots.add([hole, loc[0], loc[1], d, Time.now().value()]);
        } else {
            shots.add([hole, null, null, null, Time.now().value()]);
        }
        save();
    }

    function undoShot() {
        if (strokes[hole] <= 0) {
            return;
        }
        strokes[hole] = strokes[hole] - 1;
        var idx = -1;
        for (var i = shots.size() - 1; i >= 0; i--) {
            if (shots[i][0] == hole) {
                idx = i;
                break;
            }
        }
        if (idx >= 0) {
            var kept = [];
            for (var j = 0; j < shots.size(); j++) {
                if (j != idx) {
                    kept.add(shots[j]);
                }
            }
            shots = kept;
        }
        lastLoc = null;
        lastShotDist = null;
        for (var k = shots.size() - 1; k >= 0; k--) {
            if (shots[k][0] == hole) {
                if (shots[k][1] != null) {
                    lastLoc = [shots[k][1], shots[k][2]];
                }
                break;
            }
        }
        save();
    }

    function nextHole() {
        if (hole < holes - 1) {
            hole = hole + 1;
            lastLoc = null;
            lastShotDist = null;
            updateFields();
        }
    }

    function prevHole() {
        if (hole > 0) {
            hole = hole - 1;
            lastLoc = null;
            lastShotDist = null;
            updateFields();
        }
    }

    function totalStrokes() {
        var t = 0;
        for (var i = 0; i < holes; i++) {
            t = t + strokes[i];
        }
        return t;
    }

    // Par de los hoyos ya jugados (con algun golpe).
    function playedPar() {
        var t = 0;
        for (var i = 0; i < holes; i++) {
            if (strokes[i] > 0) {
                t = t + pars[i];
            }
        }
        return t;
    }

    function stepsNow() {
        var m = ActivityMonitor.getInfo();
        if (m == null || m.steps == null) {
            return null;
        }
        return m.steps - startSteps;
    }

    function distanceNowM() {
        var a = Activity.getActivityInfo();
        if (a == null || a.elapsedDistance == null) {
            return null;
        }
        return a.elapsedDistance;
    }

    // Los campos se graban con cada registro (1/s): un cambio en "golpes" marca el instante del golpe.
    function updateFields() {
        if (strokeField != null) {
            strokeField.setData(totalStrokes());
        }
        if (holeField != null) {
            holeField.setData(hole + 1);
        }
    }

    function save() {
        updateFields();
        try {
            Application.Storage.setValue("shots", shots);
            Application.Storage.setValue("strokes", strokes);
        } catch (e) {
            // sin almacenamiento no pasa nada: la actividad sigue grabandose
        }
    }

    // saveIt = true guarda la actividad en Garmin Connect; false la descarta.
    function finish(saveIt) {
        endSteps = stepsNow();
        endDistance = distanceNowM();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (session != null) {
            session.stop();
            if (saveIt) {
                session.save();
            } else {
                session.discard();
            }
            session = null;
        }
        if (saveIt) {
            queueForUpload();
        }
        printCsv();
    }

    // Deja la ronda en la cola de envio; GolfSync la manda al servidor (y reintenta si falla).
    function queueForUpload() {
        var out = [];
        var perHole = {};
        for (var i = 0; i < shots.size(); i++) {
            var s = shots[i];
            var n = perHole.hasKey(s[0]) ? perHole[s[0]] + 1 : 1;
            perHole[s[0]] = n;
            out.add({ "hole" => firstHole + s[0], "n" => n, "ts" => s[4],
                      "lat" => s[1], "lon" => s[2], "dist" => s[3] });
        }
        var payload = {
            "id" => "r" + roundStart,
            "course" => courseName,
            "first_hole" => firstHole,
            "pars" => pars,
            "started_at" => roundStart,
            "steps" => endSteps,
            "distance_m" => endDistance,
            "shots" => out
        };
        try {
            var queue = [];
            var old = Application.Storage.getValue("pending");
            if (old != null) {
                queue = old as Array;
            }
            queue.add(payload);
            Application.Storage.setValue("pending", queue);
        } catch (e) {
            // sin almacenamiento no se puede reintentar
        }
    }

    // Para el simulador: copia estas lineas de la consola para dibujar los golpes en un mapa.
    function printCsv() {
        System.println("hoyo,lat,lon,dist_desde_golpe_anterior_m");
        for (var i = 0; i < shots.size(); i++) {
            var s = shots[i];
            System.println(firstHole + s[0] + "," + s[1] + "," + s[2] + "," + s[3]);
        }
    }
}
