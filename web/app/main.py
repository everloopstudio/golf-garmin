import hmac
import json
import os
import re
import sqlite3
import time
import urllib.error
import urllib.request
from contextlib import closing
from datetime import datetime
from pathlib import Path
from typing import Optional
from urllib.parse import urlencode
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, Form, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field, field_validator
from starlette.middleware.sessions import SessionMiddleware

from . import stats

BASE = Path(__file__).parent
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "golf.db"

APP_PIN = os.environ["APP_PIN"]
DEVICE_TOKEN = os.environ["DEVICE_TOKEN"]
SECRET_KEY = os.environ["SECRET_KEY"]
COOKIE_SECURE = os.environ.get("COOKIE_SECURE", "true").lower() != "false"
TZ = ZoneInfo(os.environ.get("APP_TIMEZONE", "Europe/Andorra"))
GCA_KEY = os.environ.get("GOLFCOURSEAPI_KEY", "").strip()  # opcional: activa el buscador de campos

if len(DEVICE_TOKEN) < 24 or len(SECRET_KEY) < 32:
    raise RuntimeError("DEVICE_TOKEN (>=24) y SECRET_KEY (>=32) deben ser largos y aleatorios")

MAX_BODY = 64 * 1024
IP_MAX_FAILS, IP_WINDOW = 5, 15 * 60          # 5 fallos / 15 min por IP
GLOBAL_MAX_FAILS, GLOBAL_WINDOW = 40, 60 * 60  # 40 fallos / hora entre todas las IPs
INGEST_PER_MIN = 30

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
app.add_middleware(
    SessionMiddleware,
    secret_key=SECRET_KEY,
    session_cookie="golf_session",
    max_age=60 * 60 * 24 * 14,
    same_site="strict",
    https_only=COOKIE_SECURE,
)
app.mount("/static", StaticFiles(directory=BASE / "static"), name="static")
templates = Jinja2Templates(directory=BASE / "templates")


# ---------- base de datos ----------

def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB_PATH, timeout=10)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA foreign_keys = ON")
    return con


def init_db() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    with closing(db()) as con:
        con.executescript(
            """
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS rounds (
                id TEXT PRIMARY KEY,
                course TEXT NOT NULL,
                first_hole INTEGER NOT NULL,
                pars TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                steps INTEGER,
                distance_m REAL,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS shots (
                round_id TEXT NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
                hole INTEGER NOT NULL,
                n INTEGER NOT NULL,
                ts INTEGER,
                lat REAL,
                lon REAL,
                dist REAL
            );
            CREATE INDEX IF NOT EXISTS shots_round ON shots(round_id);
            CREATE TABLE IF NOT EXISTS attempts (
                ip TEXT NOT NULL,
                ts INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS courses (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                pars TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """
        )
        if con.execute("SELECT COUNT(*) FROM courses").fetchone()[0] == 0:
            # mismo campo que trae el reloj de serie (source/GolfCourses.mc)
            con.execute("INSERT INTO courses (name, pars, updated_at) VALUES (?, ?, ?)",
                        ("Valls d'Ordino", json.dumps([3] * 18), int(time.time())))
        con.commit()


init_db()


# ---------- seguridad ----------

@app.middleware("http")
async def security_headers(request: Request, call_next):
    resp = await call_next(request)
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; img-src 'self' data: https://tile.openstreetmap.org; "
        "style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'none'; "
        "base-uri 'none'; form-action 'self'"
    )
    resp.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    # Solo el origen hacia fuera: OpenStreetMap exige Referer para servir las teselas, y con
    # no-referrer el navegador manda "Origin: null" y same_origin() rechazaria los formularios.
    resp.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    resp.headers["Permissions-Policy"] = "geolocation=(), camera=(), microphone=()"
    if request.url.path.startswith("/api/") or request.url.path in ("/login", "/"):
        resp.headers["Cache-Control"] = "no-store"
    return resp


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "?"


def login_locked(ip: str) -> bool:
    now = int(time.time())
    with closing(db()) as con:
        con.execute("DELETE FROM attempts WHERE ts < ?", (now - GLOBAL_WINDOW,))
        con.commit()
        ip_fails = con.execute(
            "SELECT COUNT(*) FROM attempts WHERE ip = ? AND ts > ?", (ip, now - IP_WINDOW)
        ).fetchone()[0]
        all_fails = con.execute("SELECT COUNT(*) FROM attempts").fetchone()[0]
    return ip_fails >= IP_MAX_FAILS or all_fails >= GLOBAL_MAX_FAILS


def register_fail(ip: str) -> None:
    with closing(db()) as con:
        con.execute("INSERT INTO attempts (ip, ts) VALUES (?, ?)", (ip, int(time.time())))
        con.commit()


def require_login(request: Request) -> None:
    if not request.session.get("ok"):
        raise HTTPException(status_code=303, headers={"Location": "/login"})


_ingest_hits: dict[str, list[float]] = {}


def ingest_rate_limit(request: Request) -> None:
    ip = client_ip(request)
    now = time.time()
    hits = [t for t in _ingest_hits.get(ip, []) if t > now - 60]
    if len(hits) >= INGEST_PER_MIN:
        raise HTTPException(status_code=429, detail="rate limit")
    hits.append(now)
    _ingest_hits[ip] = hits


# ---------- esquema del reloj ----------

class ShotIn(BaseModel):
    hole: int = Field(ge=1, le=36)
    n: int = Field(ge=1, le=30)
    ts: Optional[int] = Field(default=None, ge=0)
    lat: Optional[float] = Field(default=None, ge=-90, le=90)
    lon: Optional[float] = Field(default=None, ge=-180, le=180)
    dist: Optional[float] = Field(default=None, ge=0, le=1000)


class RoundIn(BaseModel):
    id: str = Field(pattern=r"^[A-Za-z0-9_-]{4,64}$")
    course: str = Field(min_length=1, max_length=60)
    first_hole: int = Field(default=1, ge=1, le=19)
    pars: list[int] = Field(min_length=1, max_length=18)
    started_at: int = Field(ge=0)
    steps: Optional[int] = Field(default=None, ge=0, le=200000)
    distance_m: Optional[float] = Field(default=None, ge=0, le=100000)
    shots: list[ShotIn] = Field(max_length=300)

    @field_validator("pars")
    @classmethod
    def valid_pars(cls, v):
        if any(p < 2 or p > 7 for p in v):
            raise ValueError("par fuera de rango")
        return v


def require_device(x_device_token: str = Header(default="")) -> None:
    if not hmac.compare_digest(x_device_token.encode(), DEVICE_TOKEN.encode()):
        raise HTTPException(status_code=401, detail="unauthorized")


@app.post("/api/rounds")
async def ingest(
    request: Request,
    _: None = Depends(ingest_rate_limit),
    __: None = Depends(require_device),
):
    body = await request.body()
    if len(body) > MAX_BODY:
        raise HTTPException(status_code=413, detail="too large")
    try:
        rnd = RoundIn.model_validate_json(body)
    except ValueError:
        raise HTTPException(status_code=422, detail="invalid payload")

    with closing(db()) as con:
        con.execute("DELETE FROM rounds WHERE id = ?", (rnd.id,))  # reenvio: sustituye
        con.execute(
            "INSERT INTO rounds (id, course, first_hole, pars, started_at, steps, distance_m, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (rnd.id, rnd.course, rnd.first_hole, json.dumps(rnd.pars), rnd.started_at,
             rnd.steps, rnd.distance_m, int(time.time())),
        )
        con.executemany(
            "INSERT INTO shots (round_id, hole, n, ts, lat, lon, dist) VALUES (?, ?, ?, ?, ?, ?, ?)",
            [(rnd.id, s.hole, s.n, s.ts, s.lat, s.lon, s.dist) for s in rnd.shots],
        )
        con.commit()
    return JSONResponse({"ok": True, "shots": len(rnd.shots)})


@app.get("/api/courses")
def api_courses(_: None = Depends(ingest_rate_limit), __: None = Depends(require_device)):
    # Lista compacta para el reloj: [{"name", "pars"}], ordenada por nombre.
    with closing(db()) as con:
        rows = con.execute("SELECT name, pars FROM courses ORDER BY name COLLATE NOCASE").fetchall()
    return JSONResponse({"courses": [{"name": r["name"], "pars": json.loads(r["pars"])} for r in rows]})


# ---------- estadisticas ----------

def load_round(con, rid: str):
    r = con.execute("SELECT * FROM rounds WHERE id = ?", (rid,)).fetchone()
    if r is None:
        return None
    shots = [dict(s) for s in con.execute(
        "SELECT hole, n, ts, lat, lon, dist FROM shots WHERE round_id = ? ORDER BY hole, n", (rid,))]
    return summarize(dict(r), shots)


def summarize(r: dict, shots: list[dict]) -> dict:
    pars = json.loads(r["pars"])
    first = r["first_hole"]
    per_hole = []
    for i, par in enumerate(pars):
        hole = first + i
        strokes = sum(1 for s in shots if s["hole"] == hole)
        per_hole.append({"hole": hole, "par": par, "strokes": strokes})
    played = [h for h in per_hole if h["strokes"] > 0]
    total = sum(h["strokes"] for h in played)
    par_played = sum(h["par"] for h in played)
    dists = [s["dist"] for s in shots if s["dist"] is not None]
    r.update(
        pars=pars,
        per_hole=per_hole,
        total=total,
        par_played=par_played,
        diff=total - par_played,
        holes_played=len(played),
        avg_shot=(sum(dists) / len(dists)) if dists else None,
        shots=shots,
    )
    return r


def all_rounds():
    with closing(db()) as con:
        rows = [dict(x) for x in con.execute("SELECT * FROM rounds ORDER BY started_at DESC")]
        out = []
        for r in rows:
            shots = [dict(s) for s in con.execute(
                "SELECT hole, n, ts, lat, lon, dist FROM shots WHERE round_id = ?", (r["id"],))]
            out.append(summarize(r, shots))
    return out


# ---------- web ----------

@app.get("/login")
def login_page(request: Request):
    if request.session.get("ok"):
        return RedirectResponse("/", status_code=303)
    return templates.TemplateResponse(request, "login.html", {"error": None})


@app.post("/login")
def login(request: Request, pin: str = Form(default="")):
    ip = client_ip(request)
    if login_locked(ip):
        return templates.TemplateResponse(
            request, "login.html", {"error": "Demasiados intentos. Prueba mas tarde."}, status_code=429)
    if re.fullmatch(r"\d{4,8}", pin) and hmac.compare_digest(pin.encode(), APP_PIN.encode()):
        request.session.clear()
        request.session["ok"] = True
        return RedirectResponse("/", status_code=303)
    register_fail(ip)
    return templates.TemplateResponse(request, "login.html", {"error": "PIN incorrecto"}, status_code=401)


@app.post("/logout")
def logout(request: Request):
    request.session.clear()
    return RedirectResponse("/login", status_code=303)


@app.get("/")
def index(request: Request, _: None = Depends(require_login)):
    rounds = all_rounds()
    played = [r for r in rounds if r["holes_played"] > 0]
    return templates.TemplateResponse(request, "index.html", {
        "rounds": rounds,
        "n_rounds": len(played),
        "averages": stats.size_averages(played),
        "courses": stats.course_summaries(played),
    })


@app.get("/stats/course")
def course_stats(request: Request, name: str = "", _: None = Depends(require_login)):
    played = [r for r in all_rounds() if r["holes_played"] > 0 and r["course"] == name]
    if not played:
        raise HTTPException(status_code=404)
    detail = stats.course_detail(played)
    for p in detail["chart"]:
        p["label"] = local(p["label"]).strftime("%d/%m")
    latest = max(played, key=lambda r: r["started_at"])
    return templates.TemplateResponse(request, "course_stats.html", {
        "name": name, "d": detail, "holes_n": len(latest["pars"]), "par": sum(latest["pars"])})


@app.get("/rounds/{rid}")
def round_page(request: Request, rid: str, _: None = Depends(require_login)):
    if not re.fullmatch(r"[A-Za-z0-9_-]{4,64}", rid):
        raise HTTPException(status_code=404)
    with closing(db()) as con:
        r = load_round(con, rid)
    if r is None:
        raise HTTPException(status_code=404)
    # medias por hoyo en ese campo, para marcar los hoyos en los que mejoraste tu media
    same = [x for x in all_rounds() if x["course"] == r["course"] and x["holes_played"] > 0]
    avgs = stats.hole_averages(same)
    for h in r["per_hole"]:
        a = avgs.get(h["hole"])
        h["better"] = bool(a and a["played"] > 1 and 0 < h["strokes"] < a["avg"])
    return templates.TemplateResponse(request, "round.html", {
        "r": r, "breakdown": stats.breakdown([r]), "course_rounds": len(same)})


def same_origin(request: Request) -> None:
    # Defensa extra contra CSRF ademas de la cookie SameSite=Strict.
    origin = request.headers.get("origin")
    if not origin:
        return
    hosts = {request.headers.get("host"), request.headers.get("x-forwarded-host")}
    if origin.split("://", 1)[-1] not in hosts:
        raise HTTPException(status_code=403)


@app.post("/rounds/{rid}/delete")
def delete_round(
    request: Request, rid: str,
    _: None = Depends(require_login), __: None = Depends(same_origin),
):
    if not re.fullmatch(r"[A-Za-z0-9_-]{4,64}", rid):
        raise HTTPException(status_code=404)
    with closing(db()) as con:
        con.execute("DELETE FROM rounds WHERE id = ?", (rid,))  # los golpes caen en cascada
        con.commit()
    return RedirectResponse("/", status_code=303)


# ---------- campos ----------

def all_courses():
    with closing(db()) as con:
        rows = [dict(r) for r in con.execute("SELECT * FROM courses ORDER BY name COLLATE NOCASE")]
    for r in rows:
        r["pars"] = json.loads(r["pars"])
    return rows


def parse_course_form(name: str, holes: str, pars: list[str]):
    name = name.strip()
    if not 1 <= len(name) <= 40:
        return None, "El nombre debe tener entre 1 y 40 caracteres."
    if holes not in ("9", "18"):
        return None, "Elige 9 o 18 hoyos."
    n = int(holes)
    try:
        values = [int(p) for p in pars[:n]]
    except ValueError:
        return None, "Los pares deben ser numeros."
    if len(values) != n or any(p < 2 or p > 7 for p in values):
        return None, "Cada hoyo necesita un par entre 2 y 7."
    return (name, values), None


def course_form(request: Request, course: dict, error: Optional[str] = None, status: int = 200,
                info: Optional[str] = None):
    return templates.TemplateResponse(
        request, "course.html", {"c": course, "error": error, "info": info}, status_code=status)


# ---------- buscador de campos (GolfCourseAPI) ----------
# Solo cubre bien campos grandes; si no encuentra el campo o no trae pares, se crea a mano.

class GcaError(Exception):
    pass


def gca_get(path: str, params: Optional[dict] = None) -> dict:
    url = "https://api.golfcourseapi.com/v1" + path + ("?" + urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {GCA_KEY}", "User-Agent": "GOLFITO/0.1"})
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 429:
            raise GcaError("Se ha alcanzado el limite diario de busquedas. Prueba manana.")
        raise GcaError(f"El buscador ha respondido con un error ({e.code}).")
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise GcaError("No se ha podido conectar con el buscador de campos.")


def gca_name(c: dict) -> str:
    club, course = (c.get("club_name") or "").strip(), (c.get("course_name") or "").strip()
    name = club if not course or course.lower() == club.lower() else f"{club} - {course}"
    return name[:40].strip()


def gca_pars(c: dict) -> Optional[list[int]]:
    """Pares del primer tee con hoyos (caballeros y si no, damas), recortados a 18 o 9."""
    tees = c.get("tees") or {}
    groups = [tees.get(k) for k in ("male", "female")]
    for tee in [t for g in groups if isinstance(g, list) for t in g]:
        pars = [h.get("par") for h in tee.get("holes") or []]
        if len(pars) >= 9 and all(isinstance(p, int) and 2 <= p <= 7 for p in pars):
            return pars[:18] if len(pars) >= 18 else pars[:9]
    return None


@app.get("/courses")
def courses_page(request: Request, q: str = "", _: None = Depends(require_login)):
    q = q.strip()[:60]
    results, search_error = None, None
    if q and GCA_KEY:
        try:
            found = gca_get("/search", {"search_query": q}).get("courses") or []
            # la busqueda devuelve el resumen del campo; los pares llegan al elegirlo (detalle)
            results = []
            for c in found[:20]:
                loc = c.get("location") or {}
                results.append({
                    "id": str(c.get("id")), "name": gca_name(c),
                    "place": ", ".join(x for x in (loc.get("city"), loc.get("country")) if x and x != "Unknown"),
                })
        except GcaError as e:
            search_error = str(e)
    return templates.TemplateResponse(request, "courses.html", {
        "courses": all_courses(), "q": q, "results": results, "search_error": search_error,
        "search_enabled": bool(GCA_KEY)})


@app.get("/courses/new")
def course_new(request: Request, gca: str = "", name: str = "",
               _: None = Depends(require_login)):
    course = {"id": None, "name": name.strip()[:40], "pars": [3] * 18}
    if not gca or not GCA_KEY or not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", gca):
        return course_form(request, course)
    try:
        data = gca_get(f"/courses/{gca}")
    except GcaError as e:
        return course_form(request, course, info=f"{e} Rellena el campo a mano.")
    c = data.get("course", data)
    course["name"] = gca_name(c) or course["name"]
    pars = gca_pars(c)
    if pars:
        course["pars"] = pars
        return course_form(request, course, info="Datos importados del buscador. Revisalos y guarda.")
    return course_form(request, course, info="El buscador no tiene los pares de este campo: ponlos a mano.")


@app.get("/courses/{cid}")
def course_edit(request: Request, cid: int, _: None = Depends(require_login)):
    c = next((c for c in all_courses() if c["id"] == cid), None)
    if c is None:
        raise HTTPException(status_code=404)
    return course_form(request, c)


@app.post("/courses/save")
async def course_save(
    request: Request,
    _: None = Depends(require_login), __: None = Depends(same_origin),
):
    form = await request.form()
    cid = form.get("id") or None
    parsed, error = parse_course_form(
        str(form.get("name", "")), str(form.get("holes", "")), [str(v) for v in form.getlist("par")])
    if error:
        draft = {"id": cid, "name": form.get("name", ""),
                 "pars": [int(v) if str(v).isdigit() else 3 for v in form.getlist("par")]}
        return course_form(request, draft, error, status=422)
    name, pars = parsed
    try:
        with closing(db()) as con:
            if cid:
                con.execute("UPDATE courses SET name = ?, pars = ?, updated_at = ? WHERE id = ?",
                            (name, json.dumps(pars), int(time.time()), int(cid)))
            else:
                con.execute("INSERT INTO courses (name, pars, updated_at) VALUES (?, ?, ?)",
                            (name, json.dumps(pars), int(time.time())))
            con.commit()
    except sqlite3.IntegrityError:
        return course_form(request, {"id": cid, "name": name, "pars": pars},
                           "Ya existe un campo con ese nombre.", status=422)
    return RedirectResponse("/courses", status_code=303)


@app.post("/courses/{cid}/delete")
def course_delete(
    request: Request, cid: int,
    _: None = Depends(require_login), __: None = Depends(same_origin),
):
    with closing(db()) as con:
        con.execute("DELETE FROM courses WHERE id = ?", (cid,))
        con.commit()
    return RedirectResponse("/courses", status_code=303)


@app.get("/favicon.ico")
def favicon():
    return FileResponse(BASE / "static" / "icons" / "favicon-32.png", media_type="image/png")


@app.get("/apple-touch-icon.png")
@app.get("/apple-touch-icon-precomposed.png")
def apple_touch_icon():
    return FileResponse(BASE / "static" / "icons" / "apple-touch-icon.png", media_type="image/png")


@app.get("/healthz")
def healthz():
    return {"ok": True}


def local(ts: int) -> datetime:
    return datetime.fromtimestamp(ts, TZ)


def fmt_date(ts: int) -> str:
    return local(ts).strftime("%d/%m/%Y %H:%M")


def fmt_diff(d: int) -> str:
    return f"+{d}" if d > 0 else str(d)


templates.env.filters["date"] = fmt_date
templates.env.filters["diff"] = fmt_diff
