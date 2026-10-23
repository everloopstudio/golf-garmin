using Toybox.Application;
using Toybox.Lang;

// Campos disponibles: [nombre, [par de cada hoyo]].
// Se gestionan en la web (Campos); el reloj guarda la ultima lista descargada en Storage.
// Esta lista de serie solo se usa si el reloj aun no ha podido descargar ninguna.
function builtinCourses() {
    return [
        ["Valls d'Ordino", [3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3]]
    ];
}

function getCourses() {
    try {
        var cached = Application.Storage.getValue("courses");
        if (cached != null && cached.size() > 0) {
            return cached;
        }
    } catch (e) {
    }
    return builtinCourses();
}
