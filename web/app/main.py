import hmac
import json
import os
import re
import sqlite3
import time
from contextlib import closing
from datetime import datetime
from pathlib import Path
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import Depends, FastAPI, Form, Header, HTTPException, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel, Field, field_validator
from starlette.middleware.sessions import SessionMiddleware

BASE = Path(__file__).parent
DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
DB_PATH = DATA_DIR / "golf.db"

APP_PIN = os.environ["APP_PIN"]
DEVICE_TOKEN = os.environ["DEVICE_TOKEN"]
SECRET_KEY = os.environ["SECRET_KEY"]
COOKIE_SECURE = os.environ.get("COOKIE_SECURE", "true").lower() != "false"
TZ = ZoneInfo(os.environ.get("APP_TIMEZONE", "Europe/Andorra"))

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
            """
        )
        con.commit()


init_db()


# ---------- seguridad ----------

@app.middleware("http")
async def security_headers(request: Request, call_next):
    resp = await call_next(request)
    resp.headers["Content-Security-Policy"] = (
        "default-src 'self'; img-src 'self' data: https://*.tile.openstreetmap.org; "
        "style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'none'; "
        "base-uri 'none'; form-action 'self'"
    )
    resp.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["X-Frame-Options"] = "DENY"
    resp.headers["Referrer-Policy"] = "no-referrer"
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


@app.post("/api/rounds")
async def ingest(
    request: Request,
    x_device_token: str = Header(default=""),
    _: None = Depends(ingest_rate_limit),
):
    if not hmac.compare_digest(x_device_token.encode(), DEVICE_TOKEN.encode()):
        raise HTTPException(status_code=401, detail="unauthorized")
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
    stats = {
        "rounds": len(played),
        "best": min(played, key=lambda r: r["diff"]) if played else None,
        "avg_diff": (sum(r["diff"] for r in played) / len(played)) if played else None,
        "avg_shot": None,
    }
    dists = [r["avg_shot"] for r in played if r["avg_shot"] is not None]
    if dists:
        stats["avg_shot"] = sum(dists) / len(dists)
    chart = [
        {"label": local(r["started_at"]).strftime("%d/%m"), "diff": r["diff"]}
        for r in reversed(played)
    ]
    return templates.TemplateResponse(
        request, "index.html", {"rounds": rounds, "stats": stats, "chart": chart})


@app.get("/rounds/{rid}")
def round_page(request: Request, rid: str, _: None = Depends(require_login)):
    if not re.fullmatch(r"[A-Za-z0-9_-]{4,64}", rid):
        raise HTTPException(status_code=404)
    with closing(db()) as con:
        r = load_round(con, rid)
    if r is None:
        raise HTTPException(status_code=404)
    return templates.TemplateResponse(request, "round.html", {"r": r})


def same_origin(request: Request) -> None:
    # Defensa extra contra CSRF ademas de la cookie SameSite=Strict.
    origin = request.headers.get("origin")
    if origin and origin.split("://", 1)[-1] != request.headers.get("host"):
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
