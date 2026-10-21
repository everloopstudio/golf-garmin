#!/usr/bin/env python3
"""Lista los golpes de una actividad .fit de Golf Cuenta: hoyo, hora, coordenadas y distancia al golpe anterior.

Uso: python3 tools/golpes.py actividad.fit
Requiere: pip install fitparse
"""
import math
import sys
from fitparse import FitFile

SEMI = 180 / 2 ** 31


def dist_m(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dp, dl = p2 - p1, math.radians(b[1] - a[1])
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371000 * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h))


def main(path):
    prev_strokes = 0
    prev = None
    n = 0
    print("n,hoyo,hora_utc,lat,lon,dist_desde_anterior_m")
    for m in FitFile(path).get_messages("record"):
        v = m.get_values()
        strokes = v.get("golpes")
        if strokes is None:
            continue
        if strokes > prev_strokes:
            lat, lon = v.get("position_lat"), v.get("position_long")
            pos = (lat * SEMI, lon * SEMI) if lat is not None and lon is not None else None
            d = round(dist_m(prev, pos)) if prev and pos else ""
            n += 1
            print(f"{n},{v.get('hoyo', '')},{v['timestamp']},{pos[0] if pos else ''},{pos[1] if pos else ''},{d}")
            if pos:
                prev = pos
        prev_strokes = strokes
        if v.get("hoyo") is not None and v.get("hoyo") != getattr(main, "h", None):
            main.h = v["hoyo"]
            prev = None


if __name__ == "__main__":
    main(sys.argv[1])
