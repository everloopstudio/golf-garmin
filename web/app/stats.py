"""Estadisticas de rondas: resumen general, por campo y por hoyo.

Las rondas llegan ya resumidas por main.summarize(). Las medias y la mejor ronda solo
cuentan rondas completas (todos sus hoyos jugados), para que una ronda abandonada a mitad
no parezca la mejor; las estadisticas por hoyo usan cualquier hoyo jugado.
"""
from collections import Counter

RESULTS = [("eagle", "Eagles o mejor"), ("birdie", "Birdies"), ("par", "Pares"),
           ("bogey", "Bogeys"), ("dbl", "Dobles o peor")]


def hole_result(strokes: int, par: int) -> str:
    d = strokes - par
    if d <= -2:
        return "eagle"
    if d == -1:
        return "birdie"
    if d == 0:
        return "par"
    if d == 1:
        return "bogey"
    return "dbl"


def breakdown(rounds: list[dict]) -> list[dict]:
    """Reparto de resultados por hoyo, solo con las categorias que aparecen."""
    c = Counter(hole_result(h["strokes"], h["par"])
                for r in rounds for h in r["per_hole"] if h["strokes"] > 0)
    total = sum(c.values())
    return [{"key": k, "label": label, "n": c[k], "pct": round(100 * c[k] / total)}
            for k, label in RESULTS if c[k]] if total else []


def complete(rounds: list[dict]) -> list[dict]:
    return [r for r in rounds if r["holes_played"] == len(r["pars"])]


def size(r: dict) -> int:
    return 9 if len(r["pars"]) <= 9 else 18


def size_averages(rounds: list[dict]) -> list[dict]:
    """Medias de golpes y contra el par para rondas completas de 9 y de 18 hoyos.
    Solo devuelve los tamanos que tienen alguna ronda."""
    out = []
    for n in (9, 18):
        rs = [r for r in complete(rounds) if size(r) == n]
        if rs:
            out.append({"holes": n, "rounds": len(rs),
                        "total": sum(r["total"] for r in rs) / len(rs),
                        "diff": sum(r["diff"] for r in rs) / len(rs)})
    return out


def best(rounds: list[dict]):
    rs = complete(rounds)
    return min(rs, key=lambda r: (r["diff"], r["started_at"])) if rs else None


def bests_by_size(rounds: list[dict]) -> list[dict]:
    """Mejor ronda completa de 9 y de 18 hoyos, por separado (solo los tamanos jugados)."""
    out = []
    for n in (9, 18):
        b = best([r for r in rounds if size(r) == n])
        if b:
            out.append({"holes": n, "round": b})
    return out


def main_size(rounds: list[dict]) -> int:
    """Tamano de referencia de un campo: 18 si hay alguna ronda completa de 18, si no 9."""
    return 18 if any(size(r) == 18 for r in complete(rounds)) else 9


def course_summaries(rounds: list[dict]) -> list[dict]:
    """Un resumen por campo jugado, ordenado por numero de rondas."""
    by_course: dict[str, list[dict]] = {}
    for r in rounds:
        by_course.setdefault(r["course"], []).append(r)
    out = [{"name": name, "rounds": len(rs), "best": best([r for r in rs if size(r) == main_size(rs)]),
            "best_holes": main_size(rs)} for name, rs in by_course.items()]
    return sorted(out, key=lambda c: (-c["rounds"], c["name"].lower()))


def hole_averages(rounds: list[dict]) -> dict[int, dict]:
    """Por numero de hoyo: par, media de golpes, diferencia media, mejor resultado y veces jugado.
    El par es el de la ronda mas reciente que incluye el hoyo."""
    holes: dict[int, dict] = {}
    for r in sorted(rounds, key=lambda r: r["started_at"]):
        for h in r["per_hole"]:
            e = holes.setdefault(h["hole"], {"hole": h["hole"], "strokes": []})
            e["par"] = h["par"]
            if h["strokes"] > 0:
                e["strokes"].append(h["strokes"])
    out = {}
    for n, e in holes.items():
        s = e["strokes"]
        if s:
            avg = sum(s) / len(s)
            out[n] = {"hole": n, "par": e["par"], "avg": avg, "diff": avg - e["par"],
                      "best": min(s), "played": len(s)}
    return out


def course_detail(rounds: list[dict]) -> dict:
    holes = sorted(hole_averages(rounds).values(), key=lambda h: h["hole"])
    # los 3 hoyos donde mas golpes pierdes de media (solo si pierdes alguno)
    worst = sorted((h for h in holes if h["diff"] > 0), key=lambda h: -h["diff"])[:3]
    for h in holes:
        h["worst"] = h in worst
    dists = [s["dist"] for r in rounds for s in r["shots"] if s["dist"] is not None]
    # la evolucion solo compara rondas completas del mismo tamano
    ref = main_size(rounds)
    done = sorted((r for r in complete(rounds) if size(r) == ref), key=lambda r: r["started_at"])
    return {
        "rounds": rounds,
        "bests": bests_by_size(rounds),
        "chart_holes": ref,
        "averages": size_averages(rounds),
        "avg_shot": sum(dists) / len(dists) if dists else None,
        "holes": holes,
        "breakdown": breakdown(rounds),
        "chart": [{"label": r["started_at"], "diff": r["diff"]} for r in done],
    }
