# GOLFITO (prototipo 0.1) para Garmin Instinct 2

Contador de golpes con GPS por golpe. No sustituye tu pantalla de inicio: se abre desde la lista de apps.

## Controles
- UP: +1 golpe (el reloj vibra y guarda la posición GPS)
- DOWN: -1 golpe (deshace el último)
- START/STOP (GPS): hoyo siguiente
- BACK (SET): menú (continuar, hoyo anterior, guardar y salir, descartar)

Pantalla: hoyo, par, golpes del hoyo, total (con diferencia al par), metros desde el último golpe (en vivo), pasos y km desde el inicio.

## Campos
Se definen en `source/GolfCourses.mc` (nombre + par de cada hoyo). Al abrir la app se elige campo y, si tiene más de 9 hoyos, 9 primeros / 9 últimos / 18. La app instalada por USB no aparece en los ajustes de Garmin Connect, por eso van en el código.

## Servidor web (carpeta `web/`)
Al guardar la ronda, el reloj envía los golpes (hoyo, hora, GPS, distancia) por HTTPS al servidor a través del móvil. Si falla, se reintenta al abrir la app. La web muestra scorecard, mapa (OpenStreetMap) y estadísticas, con acceso por PIN.

- Reloj: copia `source/Secrets.mc.example` a `source/Secrets.mc` (no se sube al repo) y pon la URL y el `DEVICE_TOKEN`.
- Servidor: ver `.env.example`; en Dokploy, proyecto tipo Compose con este repo, variables en Environment y el dominio en Domains (servicio `web`, puerto 8000).
- En local: `cd web && pip install -r requirements.txt && APP_PIN=1234 DEVICE_TOKEN=... SECRET_KEY=... COOKIE_SECURE=false DATA_DIR=./data uvicorn app.main:app`.
- Los golpes llegan a la web por el envío directo; el `.fit` de la actividad es el normal de Garmin (sin campos propios, porque Garmin Connect dejó de mostrar las actividades con ellos).

## Probar en el simulador (sin reloj)
1. Instala Visual Studio Code y la extensión "Monkey C" de Garmin.
2. Ctrl+Shift+P > "Monkey C: Verify Installation" (descarga el SDK) y "Monkey C: Generate a Developer Key".
3. Ctrl+Shift+P > "Monkey C: Edit Products" y deja marcado Instinct 2 (descarga el dispositivo).
4. Abre esta carpeta, pulsa F5 y elige `instinct2`. Se abre el simulador.
5. En el simulador: Simulation > Set Position (cambia lat/lon entre golpes para simular andar) y usa los botones del reloj.
6. Al guardar, la consola muestra las líneas `hoyo,lat,lon,distancia` de cada golpe.

## Probar en el reloj
1. VS Code: "Monkey C: Build for Device" > instinct2 > se genera un `.prg`.
2. Conecta el Instinct 2 por USB, copia el `.prg` a `GARMIN/Apps/` y desconecta.
3. En el reloj: lista de apps > GOLFITO. Sal al aire libre y espera "GPS ok" antes de la prueba.
4. Prueba corta cerca de casa: 3 golpes en un hoyo, andando 30-50 m entre ellos. Guarda y mira la actividad en Garmin Connect (¿salen las vueltas en el mapa?).

## Qué no está probado
- No se ha compilado ni ejecutado todavía; si el compilador da errores, se corrigen.
- Los golpes como vueltas en el mapa de Garmin Connect: hay que comprobarlo con el reloj real.
- Si la app no corre por versión de API, baja `minApiLevel` en `manifest.xml`.
- El último golpe de cada hoyo (el putt) no tiene distancia, porque la distancia se mide hasta el golpe siguiente.
