"""Genera los iconos de GOLFITO (bola de golf sobre green). Uso: python3 web/icons/make_icons.py"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
OUT = Path(__file__).resolve().parent.parent / "app" / "static" / "icons"
WATCH = Path(__file__).resolve().parents[2] / "resources" / "drawables" / "launcher_icon.png"
LOADING = WATCH.parent / "loading_bg.png"


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background():
    img = Image.new("RGB", (S, S))
    top, bottom = (78, 160, 112), (24, 82, 54)
    px = img.load()
    for y in range(S):
        for x in range(S):
            # degradado diagonal suave
            t = min(1, max(0, (y * 0.8 + x * 0.2) / S))
            px[x, y] = lerp(top, bottom, t)
    # franjas de cesped cortado
    stripes = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(stripes)
    for i in range(-S, 2 * S, 150):
        d.polygon([(i, 0), (i + 75, 0), (i + 75 - S * 0.35, S), (i - S * 0.35, S)], fill=14)
    light = Image.new("RGB", (S, S), (255, 255, 255))
    return Image.composite(light, img, stripes)


def ball(img, cx, cy, r):
    # sombra en el suelo
    sh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sh).ellipse((cx - r * 0.95, cy + r * 0.78, cx + r * 1.05, cy + r * 1.12), fill=120)
    sh = sh.filter(ImageFilter.GaussianBlur(r * 0.12))
    img.paste((10, 45, 28), (0, 0), sh)

    # cuerpo con sombreado esferico (luz arriba a la izquierda)
    body = Image.new("RGB", (S, S), (255, 255, 255))
    bp = body.load()
    lx, ly, lz = -0.45, -0.55, 0.70
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    lx, ly, lz = lx / n, ly / n, lz / n
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            dx, dy = (x - cx) / r, (y - cy) / r
            dd = dx * dx + dy * dy
            if dd > 1:
                continue
            dz = math.sqrt(1 - dd)
            lam = max(0, dx * lx + dy * ly + dz * lz)
            v = 0.62 + 0.38 * lam
            bp[x, y] = (round(250 * v), round(252 * v), round(248 * v))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)

    # hoyuelos: rejilla hexagonal proyectada sobre la esfera
    dim = Image.new("L", (S, S), 0)
    dd_ = ImageDraw.Draw(dim)
    step = r * 0.2
    row = 0
    y = -r
    while y <= r:
        off = step / 2 if row % 2 else 0
        x = -r + off
        while x <= r:
            u, v = x / r, y / r
            q = u * u + v * v
            if q < 0.93:
                k = math.sqrt(1 - q)          # se achatan hacia el borde
                rr = step * 0.34 * (0.45 + 0.55 * k)
                # proyeccion: comprime posiciones hacia el borde
                f = math.sin(math.sqrt(q) * math.pi / 2) / math.sqrt(q) if q > 0 else 1
                px_, py_ = cx + u * r * f * 0.98, cy + v * r * f * 0.98
                dd_.ellipse((px_ - rr, py_ - rr * k ** 0.3, px_ + rr, py_ + rr * k ** 0.3), fill=round(70 * k + 20))
            x += step
        y += step * 0.866
        row += 1
    dim = dim.filter(ImageFilter.GaussianBlur(r * 0.012))
    shade = Image.new("RGB", (S, S), (150, 160, 150))
    body = Image.composite(shade, body, dim)

    # brillo especular
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse((cx - r * 0.62, cy - r * 0.70, cx - r * 0.08, cy - r * 0.25), fill=150)
    hl = hl.filter(ImageFilter.GaussianBlur(r * 0.10))
    body = Image.composite(Image.new("RGB", (S, S), (255, 255, 255)), body, hl)

    img.paste(body, (0, 0), mask)


def flag(img):
    d = ImageDraw.Draw(img)
    x0, y0 = int(S * 0.72), int(S * 0.13)
    d.rounded_rectangle((x0, y0, x0 + 14, y0 + int(S * 0.36)), radius=7, fill=(240, 244, 238))
    d.polygon([(x0 + 14, y0 + 6), (x0 + 14 + 150, y0 + 52), (x0 + 14, y0 + 104)], fill=(233, 85, 61))
    d.ellipse((x0 - 36, y0 + int(S * 0.36) - 10, x0 + 50, y0 + int(S * 0.36) + 18), fill=(16, 58, 37))


def loading_background():
    """Fondo de la pantalla de carga del reloj (176x176, blanco y negro): cielo con estrellas,
    green con bandera y bola. Los textos y la ruedita los dibuja la app."""
    import random

    w = 176
    sub_x, sub_h = 113, 63          # esfera pequena del Instinct 2 (arriba a la derecha)
    im = Image.new("1", (w, w), 0)
    d = ImageDraw.Draw(im)
    green = lambda x: 124 + 9 * math.cos((x - 120) / 70)

    random.seed(7)
    for _ in range(30):
        x, y = random.randint(14, 160), random.randint(10, 110)
        near_text = 58 <= y <= 94          # franja de "GOLFITO"
        in_sub = x > sub_x - 6 and y < sub_h + 6
        near_flag = x > 100 and y > 80
        if not (near_text or in_sub or near_flag):
            d.point((x, y), fill=1)
            if random.random() < 0.18:     # alguna estrella mas grande
                d.point([(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=1)

    curve = [(x, green(x)) for x in range(0, w + 1, 2)]
    d.polygon(curve + [(w, w), (0, w)], fill=1)
    for x, y in curve[::3]:                # collarin punteado del green
        d.point((x, y - 3), fill=1)

    hx = 128
    hy = green(hx)
    d.ellipse((hx - 8, hy + 1, hx + 8, hy + 6), fill=0)
    d.line((hx, hy + 3, hx, hy - 36), fill=1, width=2)
    d.polygon([(hx - 1, hy - 36), (hx - 26, hy - 30), (hx - 20, hy - 26), (hx - 1, hy - 22)], fill=1)

    bx = 56
    by = green(bx) + 2
    d.ellipse((bx - 5, by - 5, bx + 5, by + 5), fill=1, outline=0)
    for dx, dy in [(-2, -2), (2, -2), (0, 1), (-3, 2), (3, 2)]:
        d.point((bx + dx, by + dy), fill=0)
    for gap in (10, 16, 22):               # rastro de la bola
        d.point((bx - gap, green(bx - gap) + 3), fill=0)

    im.convert("RGB").save(LOADING)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    img = background()
    flag(img)
    ball(img, S * 0.46, S * 0.58, S * 0.27)

    img.resize((180, 180), Image.LANCZOS).save(OUT / "apple-touch-icon.png", optimize=True)
    img.resize((192, 192), Image.LANCZOS).save(OUT / "icon-192.png", optimize=True)
    img.resize((512, 512), Image.LANCZOS).save(OUT / "icon-512.png", optimize=True)

    # favicon con esquinas redondeadas
    fav = img.resize((64, 64), Image.LANCZOS).convert("RGBA")
    m = Image.new("L", (64, 64), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, 63, 63), radius=14, fill=255)
    fav.putalpha(m)
    fav.save(OUT / "favicon-64.png", optimize=True)
    fav.resize((32, 32), Image.LANCZOS).save(OUT / "favicon-32.png", optimize=True)

    # reloj (Instinct 2, pantalla monocroma): dibujado a pixel, bola blanca con hoyuelos sobre negro
    w = Image.new("1", (62, 62), 0)
    d = ImageDraw.Draw(w)
    d.ellipse((5, 5, 56, 56), fill=1)
    for row, y in enumerate(range(13, 52, 6)):
        for x in range(10 + (3 if row % 2 else 0), 54, 6):
            if (x - 30.5) ** 2 + (y - 30.5) ** 2 < 19.5 ** 2:
                d.rectangle((x, y, x + 1, y + 1), fill=0)
    d.arc((5, 5, 56, 56), 200, 250, fill=0)  # brillo: corte arriba a la izquierda
    w.convert("RGB").save(WATCH)
    img.save(OUT.parent.parent.parent / "icons" / "golfito-1024.png")
    loading_background()


if __name__ == "__main__":
    main()
