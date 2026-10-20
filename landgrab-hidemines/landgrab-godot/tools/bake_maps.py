#!/usr/bin/env python3
"""Bakes the 5 fixed Landgrab maps into maps/*.png (run from the project folder: python3 tools/bake_maps.py).

Needs: pip install pillow numpy
Reads the coarse outlines in tools/worlddata.gd.txt, roughens the coasts with a FIXED seed (so the result is always
the same) and writes one PNG per map at full OpenFront-style size. The game just loads these PNGs - nothing is
generated at runtime. You can also open/edit the PNGs in any paint program (keep the 4 exact colours below).

PNG colours:  water (20,60,100)   green (80,150,70)   desert (220,190,110)   snow (245,248,252)
"""
import json, math, os, random, re
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "maps")
SRC = open(os.path.join(HERE, "worlddata.gd.txt")).read()

def _arr(name):
    m = re.search(r"const %s: Array = \[(.*?)\n\]\n" % name, SRC, re.S)
    if m:
        return json.loads("[" + m.group(1) + "]")
    return json.loads(re.search(r"const %s: Array = (\[.*\])" % name, SRC).group(1))

LAND, WATER = _arr("LAND"), _arr("WATER")
DESERTS, MOUNTS = _arr("DESERTS"), _arr("MOUNTS")

C_WATER, C_GREEN, C_DESERT, C_SNOW = (20, 60, 100), (80, 150, 70), (220, 190, 110), (245, 248, 252)
CELL = 4  # terrain block size in px of the full-size image

MAPS = {
    "world":         dict(seed=11, w=2000, h=1000, lon0=-180.0, lon1=180.0, lat0=-58.0, lat1=84.0),
    "europe":        dict(seed=22, w=1600, h=1300, lon0=-25.0,  lon1=50.0,  lat0=33.0,  lat1=72.0),
    "asia":          dict(seed=33, w=1500, h=1300, lon0=25.0,   lon1=150.0, lat0=-11.0, lat1=78.0),
    "north_america": dict(seed=44, w=1500, h=1360, lon0=-170.0, lon1=-50.0, lat0=7.0,   lat1=84.0),
    "africa":        dict(seed=55, w=1400, h=1450, lon0=-20.0,  lon1=52.0,  lat0=-36.0, lat1=38.0),
}

def sub_edge(a, b, out, rng, depth):
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = math.hypot(dx, dy)
    if d < 3.0 or depth > 9:
        out.append(a); return
    ux, uy = dx / d, dy / d
    k = rng.uniform(-1, 1) * d * 0.2
    mid = ((a[0] + b[0]) / 2 - uy * k, (a[1] + b[1]) / 2 + ux * k)
    sub_edge(a, mid, out, rng, depth + 1)
    sub_edge(mid, b, out, rng, depth + 1)

def fill(polys, m, value, img, rng):
    W, H = m["w"], m["h"]
    sx = W / (m["lon1"] - m["lon0"]); sy = H / (m["lat1"] - m["lat0"])
    dr = ImageDraw.Draw(img)
    for poly in polys:
        pts = [((poly[k] - m["lon0"]) * sx, (m["lat1"] - poly[k + 1]) * sy) for k in range(0, len(poly), 2)]
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        if max(xs) < -5 or min(xs) > W + 5 or max(ys) < -5 or min(ys) > H + 5:
            continue
        fine = []
        for e in range(len(pts)):
            sub_edge(pts[e], pts[(e + 1) % len(pts)], fine, rng, 0)
        dr.polygon(fine, fill=value)

def noise(rs, gw, gh, W, H, xs, ys):
    g = rs.random_sample((gh + 1, gw + 1))
    fx = xs / W * gw; fy = ys / H * gh
    ix = np.floor(fx).astype(int); iy = np.floor(fy).astype(int)
    tx = fx - ix; ty = fy - iy
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    a = g[iy, ix]; b = g[iy, ix + 1]; c = g[iy + 1, ix]; d = g[iy + 1, ix + 1]
    return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty

def terrain_cells(m, rs):
    W, H = m["w"], m["h"]
    cw, ch = W // CELL + 1, H // CELL + 1
    cx, cy = np.meshgrid(np.arange(cw), np.arange(ch))
    tx = np.minimum(W - 1, cx * CELL + CELL // 2).astype(float)
    ty = np.minimum(H - 1, cy * CELL + CELL // 2).astype(float)
    lat = m["lat1"] - (ty + 0.5) / H * (m["lat1"] - m["lat0"])
    lon = m["lon0"] + (tx + 0.5) / W * (m["lon1"] - m["lon0"])
    n1 = noise(rs, 30, 20, W, H, tx, ty)
    n2 = noise(rs, 30, 20, W, H, tx, ty)
    snow = (lat > 63.0 + (n1 - 0.5) * 8.0) | (lat < -52.0 + (n1 - 0.5) * 6.0)
    for e in MOUNTS:
        dx = (lon - e[0]) / e[2]; dy = (lat - e[1]) / e[3]
        snow |= dx * dx + dy * dy < 1.0 + (n2 - 0.5) * 0.9
    desert = np.zeros_like(snow)
    for e in DESERTS:
        dx = (lon - e[0]) / e[2]; dy = (lat - e[1]) / e[3]
        desert |= dx * dx + dy * dy < 1.0 + (n1 - 0.5) * 0.9
    desert &= ~snow
    cells = np.zeros((ch, cw), dtype=np.uint8)   # 0 green 1 desert 2 snow
    cells[desert] = 1
    cells[snow] = 2
    return cells

def bake(name, m):
    W, H = m["w"], m["h"]
    rng = random.Random(m["seed"]); rs = np.random.RandomState(m["seed"])
    mask = Image.new("L", (W, H), 0)
    fill(LAND, m, 255, mask, rng)
    fill(WATER, m, 0, mask, rng)
    land = np.array(mask) > 0
    cells = terrain_cells(m, rs)
    yy, xx = np.mgrid[0:H, 0:W]
    t = cells[yy // CELL, xx // CELL]
    rgb = np.zeros((H, W, 3), dtype=np.uint8)
    rgb[:] = C_WATER
    for code, col in ((0, C_GREEN), (1, C_DESERT), (2, C_SNOW)):
        rgb[land & (t == code)] = col
    path = os.path.join(OUT, name + ".png")
    Image.fromarray(rgb, "RGB").save(path, optimize=True)
    print("%-14s %dx%d  land %.1f%%  %s" % (name, W, H, 100.0 * land.mean(), path))

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for n, mm in MAPS.items():
        bake(n, mm)
