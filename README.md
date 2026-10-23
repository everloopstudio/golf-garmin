<p align="center">
  <img src="web/app/static/icons/icon-192.png" width="96" alt="GOLFITO">
</p>

<h1 align="center">GOLFITO</h1>

<p align="center">
  Cuenta tus golpes de golf con un reloj Garmin y consulta la tarjeta, el mapa y tus estadísticas en una web propia.
</p>

---

## ¿Qué es?

GOLFITO tiene dos partes que trabajan juntas:

1. **Una app para el reloj** (Garmin Instinct 2). Durante la ronda pulsas un botón en cada golpe: el reloj cuenta los golpes, guarda la posición GPS de cada uno y te dice cuántos metros ha volado la bola.
2. **Una web** (la instalas en tu propio servidor). Al terminar la ronda, el reloj la envía sola y en la web ves la tarjeta, el mapa con los golpes y tus estadísticas por campo y por hoyo.

```
 Reloj Garmin ──Bluetooth──▶ iPhone/Android (app Garmin Connect) ──Internet──▶ Tu web GOLFITO
   cuenta golpes                hace de puente                                 tarjeta, mapa, estadísticas
```

La actividad también se guarda como una actividad normal de golf en Garmin Connect, con el recorrido.

> **Importante:** la app del reloj no está en la tienda de Garmin. Se instala "a mano" copiando un archivo al reloj por USB. Este documento explica cómo.

> **Cada persona monta su propio GOLFITO.** No hay un servidor común: tú pones la web en tu servidor y la app de tu reloj envía las rondas solo a tu web. Para empezar, haz un **fork** de este repositorio (botón *Fork* arriba a la derecha en GitHub): tendrás tu propia copia para desplegarla y cambiarla como quieras.

---

## Qué necesitas

| Qué | Para qué |
|---|---|
| Un reloj **Garmin Instinct 2** | Es el único modelo probado. Otros modelos necesitarían ajustes de pantalla. |
| Un **móvil** con la app **Garmin Connect** y el reloj emparejado | El reloj envía las rondas a través del móvil. |
| Un **ordenador** (Linux, Mac o Windows) | Para compilar la app del reloj y copiarla por USB. |
| Un **servidor con Docker** y un **dominio con HTTPS** | Para la web. Aquí se explica con [Dokploy](https://dokploy.com), pero vale cualquier servidor con Docker. |
| *(Opcional)* Una clave gratuita de [GolfCourseAPI](https://golfcourseapi.com) | Para buscar campos y que se rellenen solos los pares. |

---

## Instalación paso a paso

Hazlo en este orden: **primero la web, luego el reloj** (el reloj necesita saber la dirección de tu web).

### Paso 1. Preparar tres "contraseñas"

Necesitas tres valores. Apúntalos, los usarás en el paso 2 y en el 3:

| Nombre | Qué es | Ejemplo |
|---|---|---|
| `APP_PIN` | El PIN para entrar en la web (4 a 8 números; mejor 6 u 8) | `482193` |
| `DEVICE_TOKEN` | Una clave larga que comparten el reloj y la web, para que nadie más pueda enviar rondas | (generada, ver abajo) |
| `SECRET_KEY` | Una clave interna de la web para las sesiones | (generada, ver abajo) |

Para generar `DEVICE_TOKEN` y `SECRET_KEY` (son dos valores **distintos**, ejecuta el comando dos veces):

- **Linux / Mac:**
  ```bash
  openssl rand -hex 32
  ```
- **Windows (PowerShell):**
  ```powershell
  -join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
  ```

### Paso 2. Poner la web en marcha (Dokploy)

1. En Dokploy, crea un proyecto y dentro un servicio de tipo **Compose**.
2. Como origen, pon este repositorio de GitHub (rama `main`). Dokploy usará el archivo `docker-compose.yml` de la raíz.
3. En la pestaña **Environment**, añade:
   ```
   APP_PIN=tu_pin
   DEVICE_TOKEN=el_token_generado
   SECRET_KEY=la_otra_clave_generada
   ```
   Opcionales:
   ```
   GOLFCOURSEAPI_KEY=tu_clave        # activa el buscador de campos
   APP_TIMEZONE=Europe/Madrid        # zona horaria de las fechas (por defecto Europe/Andorra)
   ```
4. En la pestaña **Domains**, añade tu dominio (por ejemplo `golf.midominio.com`), servicio **`web`**, puerto **`8000`**, con **HTTPS** activado.
5. Pulsa **Deploy**.
6. Comprueba que funciona: abre `https://golf.midominio.com` en el navegador. Debe salir la pantalla del PIN.

> **Sin Dokploy:** en cualquier servidor con Docker puedes hacer `docker compose up -d` con un archivo `.env` al lado (copia `.env.example`). Necesitarás poner delante un proxy con HTTPS (Caddy, Traefik, Nginx…) que apunte al puerto 8000 del contenedor. **El HTTPS es obligatorio:** el reloj se niega a enviar datos a una web sin HTTPS.

Las rondas se guardan en un volumen de Docker llamado `golf_data` (archivo `/data/golf.db`). Haz copias de seguridad de ese volumen de vez en cuando.

### Paso 3. Instalar las herramientas de Garmin en el ordenador

1. Instala [Visual Studio Code](https://code.visualstudio.com/).
2. Dentro de VS Code, instala la extensión **"Monkey C"** (de Garmin).
3. Pulsa `Ctrl+Shift+P` (en Mac `Cmd+Shift+P`) y ejecuta:
   - **`Monkey C: Verify Installation`** → descarga el SDK de Garmin (te pedirá una cuenta de Garmin, la misma de Garmin Connect sirve).
   - **`Monkey C: Generate a Developer Key`** → crea tu clave para firmar la app. Guárdala bien: se queda en un archivo llamado `developer_key`.
   - **`Monkey C: Edit Products`** → marca **Instinct 2** para que se descargue el modelo de reloj.

### Paso 4. Decirle al reloj dónde está tu web

1. Copia el archivo `source/Secrets.mc.example` y llama a la copia `source/Secrets.mc`.
2. Ábrelo y cambia las dos líneas:
   ```
   return "https://golf.midominio.com/api/rounds";   // tu dominio + /api/rounds
   return "el_token_generado";                       // el mismo DEVICE_TOKEN del paso 2
   ```
3. Guarda. Este archivo **no se sube a GitHub** (está en `.gitignore`), porque contiene tu token.

### Paso 5. Compilar la app del reloj

Opción fácil, desde VS Code:

- Abre la carpeta del proyecto, `Ctrl+Shift+P` → **`Monkey C: Build for Device`** → elige **instinct2**. Se crea un archivo `.prg` (normalmente en la carpeta `bin/`).

Opción por terminal (cambia las rutas por las tuyas):

```bash
monkeyc -d instinct2 -f monkey.jungle -o bin/golfgarmin.prg -y /ruta/a/tu/developer_key
```

> `monkeyc` está dentro del SDK que descargó VS Code. En Linux suele estar en `~/.Garmin/ConnectIQ/Sdks/<versión>/bin/`.

### Paso 6. Copiar la app al reloj

1. Conecta el reloj al ordenador con el cable USB. Aparece como una unidad llamada **GARMIN** (como un pendrive).
   - Si no aparece enseguida, **espera hasta un minuto**: a veces el reloj tarda en mostrarse como unidad.
2. Copia `golfgarmin.prg` dentro de la carpeta **`GARMIN/APPS/`** del reloj.
3. **Expulsa** la unidad (no tires del cable sin expulsar) y desconecta. Al soltarlo, el reloj instala la app.
4. En el reloj, busca **GOLFITO** en la lista de apps.

Cada vez que cambies algo del reloj (por ejemplo, el token o la dirección de la web), repite los pasos 5 y 6.

### Paso 7. Primera prueba

1. Comprueba que el móvil tiene el **Bluetooth** activado y la app **Garmin Connect** abierta (aunque sea en segundo plano).
2. Abre GOLFITO en el reloj. Verás una pantalla de carga de unos segundos y luego la lista de campos.
3. Elige un campo, pulsa **START** un par de veces (son golpes) y luego **BACK** → **Guardar y salir** → pulsa cualquier botón.
4. Entra en tu web con el PIN: la ronda debe aparecer en la lista.

---

## Cómo se usa

### En el reloj

| Botón | Qué hace |
|---|---|
| **START / GPS** (arriba a la derecha) | **+1 golpe**. El reloj vibra y guarda dónde estás. |
| **UP** (centro izquierda) | **-1 golpe** (para corregir un golpe marcado por error). |
| **DOWN** (abajo izquierda) | **Hoyo siguiente**. |
| **BACK / SET** (abajo derecha) | Menú: continuar, hoyo anterior, **guardar y salir**, descartar. |

En la pantalla verás:

- **Arriba:** el número de hoyo.
- **En la esfera pequeña:** el par del hoyo. Las **8 rayitas** alrededor indican la señal GPS (más rayas gruesas = mejor señal; espera a tener varias antes de empezar).
- **En grande:** los golpes de este hoyo.
- **Golpe ant. / Desde golpe:** cuántos metros voló tu último golpe, o cuánto llevas andado desde el último golpe.
- **Total:** golpes de toda la ronda y cómo vas respecto al par.
- **Abajo:** kilómetros recorridos.

**Truco para medir bien las distancias:** pulsa START justo en el sitio desde donde golpeas. La distancia de cada golpe es la que hay entre ese punto y el sitio del golpe siguiente (por eso el último golpe de cada hoyo, el putt, no tiene distancia).

Al **guardar y salir**, se ve un resumen; al pulsar un botón, la ronda se envía a la web y la actividad se guarda en Garmin Connect. Si en ese momento no hay conexión, no se pierde nada: se envía sola la próxima vez que abras GOLFITO.

### En la web

Entra con tu PIN. En el móvil puedes añadirla a la pantalla de inicio (en Safari: Compartir → *Añadir a pantalla de inicio*) y se abre como una app. Para actualizar, desliza hacia abajo desde arriba.

Arriba tienes tres secciones:

- **Inicio:** resumen (rondas y medias de 9 y 18 hoyos) y la lista de tus rondas. Al pulsar una ronda ves su tarjeta con birdies/bogeys marcados, el reparto de resultados, el mapa con los golpes (puedes filtrar por hoyo) y la lista de golpes con distancias. Desde ahí también puedes **eliminar** la ronda.
- **Estadísticas:** los campos que has jugado. Al pulsar uno ves tu mejor ronda, medias, evolución, tu media en cada hoyo (con los hoyos donde más pierdes resaltados) y el reparto de resultados.
- **Campos:** aquí gestionas los campos que salen en el reloj (crear, editar, buscar). Que un campo esté aquí no significa que lo hayas jugado, y si borras un campo sus estadísticas no se pierden.

### Añadir un campo

En la web, ve a **Campos**:

- **Buscar** (si configuraste `GOLFCOURSEAPI_KEY`): escribe el nombre del club (por ejemplo `camiral`). Si aparece, púlsalo y los hoyos y pares se rellenan solos. Revísalos y guarda. Funciona bien con campos grandes y conocidos; los pequeños suelen no estar.
- **Nuevo campo:** pon el nombre, elige 9 o 18 hoyos y escribe el par de cada hoyo.

El reloj descarga la lista de campos cada vez que abres GOLFITO, así que el campo nuevo aparece la próxima vez que lo abras. En los campos de 18 hoyos, el reloj te deja elegir jugar los 18, los 9 primeros o los 9 últimos.

---

## Si algo falla

| Problema | Qué hacer |
|---|---|
| El reloj conectado por USB **no aparece** como unidad | Espera hasta un minuto. Si sigue sin salir, desconecta, reinicia el reloj y vuelve a conectarlo (mejor directo al ordenador, sin hubs, y con un cable de datos). |
| GOLFITO **no aparece** en el reloj | Comprueba que el `.prg` está en `GARMIN/APPS/` y que expulsaste la unidad antes de desconectar. |
| La ronda **no llega a la web** | Revisa que el móvil tenga Bluetooth y Garmin Connect abierto. La ronda queda guardada en el reloj y se reintenta al abrir GOLFITO. |
| Sigue sin llegar | Comprueba que la dirección y el `DEVICE_TOKEN` de `source/Secrets.mc` son exactamente los del servidor, que la web usa **HTTPS** y que volviste a compilar y copiar la app tras cambiarlos. |
| La lista de campos del reloj **no se actualiza** | Igual que arriba: necesita conexión con el móvil al abrir la app. Sin conexión usa la última lista que descargó. |
| La web dice **"Demasiados intentos"** | Has fallado el PIN 5 veces. Espera 15 minutos. |
| El buscador dice que se ha alcanzado el **límite** | El plan gratuito de GolfCourseAPI tiene un límite diario. Crea el campo a mano o prueba al día siguiente. |
| No hay distancias | Espera a tener buena señal GPS (varias rayas gruesas en la esfera pequeña) antes del primer golpe. |

---

## Para curiosos (estructura del proyecto)

```
├── manifest.xml, monkey.jungle    # configuración de la app del reloj
├── source/                        # código de la app del reloj (lenguaje Monkey C)
│   ├── GolfApp.mc                 #   arranque: pantalla de carga y menú de campos
│   ├── GolfLoading.mc             #   pantalla de carga
│   ├── GolfView.mc                #   pantalla de la ronda y resumen final
│   ├── GolfDelegate.mc            #   botones y menús
│   ├── GolfModel.mc               #   golpes, GPS y actividad
│   ├── GolfSync.mc                #   envío de rondas y descarga de campos
│   ├── GolfCourses.mc             #   lista de campos guardada (y la de serie)
│   └── Secrets.mc.example         #   plantilla de la dirección y el token (cópiala a Secrets.mc)
├── resources/                     # nombre, icono e imágenes del reloj
├── web/                           # la web (Python + FastAPI + SQLite)
│   ├── app/main.py                #   rutas, seguridad y base de datos
│   ├── app/stats.py               #   cálculos de estadísticas
│   ├── app/templates/, app/static/#   páginas, estilos y scripts
│   └── icons/make_icons.py        #   genera iconos y las imágenes del reloj
├── docker-compose.yml             # despliegue de la web
└── .env.example                   # variables que necesita la web
```

### Probar la web en tu ordenador

```bash
cd web
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
APP_PIN=1234 DEVICE_TOKEN=$(openssl rand -hex 32) SECRET_KEY=$(openssl rand -hex 32) \
  COOKIE_SECURE=false DATA_DIR=./data uvicorn app.main:app --reload
```

Y abre `http://127.0.0.1:8000`.

### Probar el reloj sin reloj (simulador)

En VS Code, con la carpeta abierta, pulsa **F5** y elige **instinct2**. Se abre un simulador del reloj donde puedes pulsar los botones con el ratón. Para simular el GPS: menú *Simulation → Set Position*.

> El simulador, como el reloj de verdad, solo envía datos a webs con HTTPS. Contra un servidor local sin HTTPS verás el error `-1001`; es normal.

### Seguridad

- La web pide PIN y bloquea una IP tras 5 intentos fallidos. Si hay muchos fallos desde muchas IPs (un ataque), se bloquean también los dispositivos nuevos, pero no los tuyos: los dispositivos donde ya entraste se recuerdan durante un año. Usa un PIN de 6 u 8 cifras.
- El reloj se identifica con el `DEVICE_TOKEN`; sin él no se pueden enviar rondas ni leer campos.
- Los secretos (`.env`, `source/Secrets.mc`, `developer_key`) **nunca** se suben al repositorio. Si alguno se filtra, genera uno nuevo y cámbialo en el servidor y en el reloj.

---

## Licencia

[PolyForm Noncommercial 1.0.0](LICENSE): puedes usarlo, copiarlo, modificarlo y compartirlo **para cualquier fin no comercial** (uso personal, aficiones, pruebas, clubes, asociaciones, centros educativos…). **No está permitido el uso comercial**, por ejemplo venderlo u ofrecerlo como servicio de pago. Si lo compartes, incluye el archivo `LICENSE` con el aviso de copyright. Se ofrece tal cual, sin garantías.

Las librerías incluidas en `web/app/static/vendor/` mantienen sus propias licencias: [Leaflet](https://leafletjs.com) (BSD-2-Clause) y [Chart.js](https://www.chartjs.org) (MIT). Los mapas son de © colaboradores de [OpenStreetMap](https://www.openstreetmap.org/copyright).
