"""Jutsu effects and hand-held props, drawn procedurally per frame.

Every effect draws into a scratch layer that is shaded/outlined on its own and
then composited, so effects get the same crisp look as the characters.
Callers pass sizes in real pixels; internal details scale with K (one v1 pixel
of the old 48px sprites), so effects stay proportional to the 128px rig."""

import math
import random

import numpy as np

from body import UNIT as K, Ctx
from engine import C, Layer, mix, scale, text, text_width

FIRE = ['#c9301a', '#ff7a1a', '#ffcf3a', '#fff4c2']
BLACK_FIRE = ['#0b060b', '#1d0c1f', '#3a1240', '#7a2257']
SHADOW = (20, 14, 26, 235)


def ease_out(t):
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 2


def ease_in_out(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def seg(i, a, b):
    """Progress 0..1 of frame i through the frame range [a, b)."""
    if b <= a:
        return 1.0
    return max(0.0, min(1.0, (i - a) / (b - a)))


def _scratch(L):
    return Layer(L.w, L.h)


def _spike(S, bx, by, ang, length, width, c):
    a = math.radians(ang)
    dx, dy = math.cos(a), -math.sin(a)
    nx, ny = -dy, dx
    S.poly([(bx + nx * width / 2, by + ny * width / 2), (bx + dx * length, by + dy * length),
            (bx - nx * width / 2, by - ny * width / 2)], c)


# -------------------------------------------------------------- smoke / dust
def smoke_puff(L, cx, cy, t, r=10, seed=1, light='#f4f5f8', dark='#c4c8d4', rim='#8d93a3'):
    """Ninja 'poof'. t runs 0..1: burst, billow, fade."""
    if t <= 0 or t >= 1:
        return
    rng = random.Random(seed)
    S = _scratch(L)
    grow = ease_out(min(1, t / 0.35))
    blobs = []
    n = 10
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.3, 0.3)
        d = r * 0.6 * grow * rng.uniform(0.7, 1.1)
        br = max(2, r * 0.48 * grow * rng.uniform(0.75, 1.15) * (1 - 0.35 * t))
        blobs.append((cx + math.cos(a) * d, cy + math.sin(a) * d * 0.8 - t * r * 0.3, br))
    blobs.append((cx, cy - t * r * 0.3, r * 0.55 * grow))
    for x, y, br in blobs:
        S.disc(x + K * 0.6, y + K * 0.8, br, dark)
    for x, y, br in blobs:
        S.disc(x, y, br - K * 0.7, light)
    for x, y, br in blobs[:4]:
        S.disc(x - br * 0.3, y - br * 0.35, br * 0.35, '#ffffff')
    S.outline(color=rim)
    L.over(S, opacity=1.0 if t < 0.65 else max(0.0, (1 - t) / 0.35))


def dust(L, cx, gy, t, r=6, seed=2):
    smoke_puff(L, cx, gy - r * 0.5, t, r, seed, light='#e7d8bc', dark='#bda57f', rim='#7a6648')


# ------------------------------------------------------------------ rasengan
def rasengan(L, cx, cy, r, phase, core='#bfe6ff', body='#4aa8ff', rim='#1d58c4'):
    if r <= 0.5:
        return
    G = _scratch(L)
    G.disc(cx, cy, r + 2.5 * K, (130, 200, 255, 255))
    L.over(G, opacity=0.32)
    S = _scratch(L)
    S.disc(cx, cy, r, body)
    S.disc(cx - r * 0.15, cy - r * 0.15, r * 0.62, core)
    n = max(14, int(r * 4))
    for k in range(4):
        pts = []
        for s in range(n):
            u = s / (n - 1)
            a = phase * 2 * math.pi + k * math.pi / 2 + u * 2.8
            pts.append((cx + math.cos(a) * u * r * 0.95, cy + math.sin(a) * u * r * 0.95))
        S.polyline(pts[: n * 2 // 3], '#ffffff')
        S.polyline(pts[n * 2 // 3 - 1:], '#2f86e8')
    S.disc(cx, cy, max(1.0, r * 0.22), '#ffffff')
    S.outline(color=rim)
    L.over(S)


def rasenshuriken(L, cx, cy, r, phase, blade_len=None):
    blade_len = blade_len or r * 2.6
    W_ = _scratch(L)
    W_.disc(cx, cy, blade_len * 0.95, (200, 235, 255, 255))
    L.over(W_, opacity=0.22)
    B = _scratch(L)
    for k in range(4):
        a = math.radians(phase * 360 + k * 90)
        tip = (cx + math.cos(a) * blade_len, cy + math.sin(a) * blade_len)
        back = (cx + math.cos(a + 0.9) * r * 1.2, cy + math.sin(a + 0.9) * r * 1.2)
        fore = (cx + math.cos(a - 0.35) * r * 0.9, cy + math.sin(a - 0.35) * r * 0.9)
        B.poly([back, tip, fore, (cx, cy)], '#eef8ff')
        mid = (cx + math.cos(a - 0.05) * blade_len * 0.6, cy + math.sin(a - 0.05) * blade_len * 0.6)
        B.line(cx, cy, mid[0], mid[1], '#bfe3ff')
    B.outline(color='#7cc4ff')
    L.over(B)
    rasengan(L, cx, cy, r, phase * 1.5)


def burst(L, cx, cy, r, t, inner='#ffffff', outer='#7cc4ff', rays=12, seed=3):
    """Expanding impact ring with radial streaks."""
    if t <= 0 or t >= 1:
        return
    rng = random.Random(seed)
    S = _scratch(L)
    rr = r * ease_out(t)
    S.disc(cx, cy, rr, outer)
    S.disc(cx, cy, rr * (0.55 + 0.35 * t), inner)
    if t > 0.45:
        S.disc(cx, cy, rr * (t - 0.45) * 1.6, (0, 0, 0, 0))
    for i in range(rays):
        a = 2 * math.pi * i / rays + rng.uniform(-0.2, 0.2)
        d0, d1 = rr * 1.05, rr * (1.3 + rng.uniform(0, 0.4))
        S.line(cx + math.cos(a) * d0, cy + math.sin(a) * d0,
               cx + math.cos(a) * d1, cy + math.sin(a) * d1, inner, 2)
    L.over(S, opacity=1.0 if t < 0.6 else (1 - t) / 0.4)


def speed_lines(L, x0, x1, ys, col=(255, 255, 255, 255), opacity=0.7):
    S = _scratch(L)
    for y in ys:
        S.line(x0, y, x1, y, col)
    L.over(S, opacity=opacity)


# ----------------------------------------------------------------- lightning
def lightning(L, cx, cy, reach, seed, bolts=7, core='#ffffff', glow='#62c1ff',
              halo=(140, 205, 255, 255), forward=False):
    """Crackling Chidori: jagged bolts from (cx, cy). forward=True sends most
    bolts backwards, like a trail behind a charging hand."""
    rng = random.Random(seed)
    G = _scratch(L)
    G.disc(cx, cy, reach * 0.55, halo)
    L.over(G, opacity=0.3)
    paths = []
    for _ in range(bolts):
        a = rng.uniform(0, 2 * math.pi)
        if forward:
            a = math.pi + rng.uniform(-0.9, 0.9)
        length = reach * rng.uniform(0.55, 1.0)
        pts = [(cx, cy)]
        n = rng.randint(4, 6)
        for k in range(1, n + 1):
            d = length * k / n
            j = rng.uniform(-1.6, 1.6) * K
            pts.append((cx + math.cos(a) * d - math.sin(a) * j,
                        cy + math.sin(a) * d + math.cos(a) * j))
        paths.append(pts)
        if rng.random() < 0.5:                       # forks
            fp = pts[n // 2]
            fa = a + rng.choice((-0.8, 0.8))
            paths.append([fp, (fp[0] + math.cos(fa) * length * 0.35, fp[1] + math.sin(fa) * length * 0.35)])
    S = _scratch(L)
    for pts in paths:
        S.polyline(pts, glow, 3)
    for pts in paths:
        S.polyline(pts, core, 1)
    S.disc(cx, cy, 2.2 * K, core)
    L.over(S)


# ---------------------------------------------------------------------- fire
def fireball(L, cx, cy, r, seed, pal=FIRE, trail=0.0):
    rng = random.Random(seed)
    S = _scratch(L)
    for k in range(12):
        a = 2 * math.pi * k / 12 + rng.uniform(-0.2, 0.2)
        S.disc(cx + math.cos(a) * r * 0.7, cy + math.sin(a) * r * 0.7, r * rng.uniform(0.35, 0.5), pal[0])
    S.disc(cx, cy, r * 0.85, pal[0])
    if trail:
        for k in range(5):
            yy = cy + rng.uniform(-r * 0.5, r * 0.5)
            _spike(S, cx - r * 0.5, yy, 180 + rng.uniform(-25, 25),
                   r * trail * rng.uniform(0.8, 1.3), r * 0.6, pal[0])
    S.disc(cx + r * 0.08, cy - r * 0.05, r * 0.66, pal[1])
    for k in range(5):
        a = 2 * math.pi * k / 5 + rng.uniform(0, 1)
        S.disc(cx + math.cos(a) * r * 0.45, cy + math.sin(a) * r * 0.45, r * 0.2, pal[1])
    S.disc(cx + r * 0.12, cy - r * 0.08, r * 0.42, pal[2])
    S.disc(cx + r * 0.15, cy - r * 0.1, r * 0.2, pal[3])
    S.outline(0.45)
    L.over(S)


def flames(L, cx, gy, w, h, phase, seed, pal=FIRE):
    """Bonfire of flickering tongues standing on the ground row gy."""
    if h <= 1:
        return
    rng = random.Random(seed)
    S = _scratch(L)
    n = max(3, int(w / (2.5 * K)))
    for layer_i, col in enumerate(pal[:3]):
        k = 1 - layer_i * 0.28
        for i in range(n):
            x = cx - w / 2 + (i + 0.5) * w / n
            flick = 0.65 + 0.35 * math.sin(phase * 2 * math.pi * 1.7 + i * 1.9 + rng.uniform(0, 3))
            hh = h * k * flick * (1 - abs(i - (n - 1) / 2) / n * 0.9)
            _spike(S, x, gy, 90 + rng.uniform(-12, 12), hh, (w / n) * 2.2 * k, col)
        S.ellipse(cx, gy - 1, w / 2 * k, 2.5 * K * k, col)
    S.outline(0.4)
    L.over(S)


# ------------------------------------------------------------------- susanoo
def susanoo(L, cx, gy, t, col, phase, fade=1.0, k=None):
    """Spectral warrior: translucent body with ribs and a horned skull rising
    out of the ground around the user. t = rise 0..1, fade = opacity."""
    if t <= 0 or fade <= 0:
        return
    k = k or K * 1.25
    base = C(col)
    hi = mix(base, '#ffffff', 0.55)
    dark = mix(base, '#000000', 0.45)
    body = Layer(L.w, L.h)
    body.ellipse(cx, gy - 30 * k, 27 * k, 31 * k, base)
    body.ellipse(cx, gy - 70 * k, 12 * k, 12 * k, base)
    body.ellipse(cx - 27 * k, gy - 46 * k, 9 * k, 8 * k, base)
    body.ellipse(cx + 27 * k, gy - 46 * k, 9 * k, 8 * k, base)
    body.rect(cx - 5 * k, gy - 62 * k, cx + 5 * k, gy - 55 * k, base)
    for i in range(7):
        x = cx + (-30 + i * 10) * k
        hh = (8 + 4 * math.sin(phase * 2 * math.pi * 2 + i * 1.7)) * k
        top = gy - (50 if abs(x - cx) > 12 * k else 78) * k
        _spike(body, x, top + 4 * k, 90 + (x - cx) / k * 0.6, hh, 7 * k, base)
    _spike(body, cx - 8 * k, gy - 78 * k, 115, 10 * k, 4 * k, base)
    _spike(body, cx + 8 * k, gy - 78 * k, 65, 10 * k, 4 * k, base)
    body.outline(color=hi)
    bones = Layer(L.w, L.h)
    bones.rect(cx - k, gy - 54 * k, cx + k, gy - 6 * k, hi)
    for i in range(4):
        y = gy - (14 + i * 9) * k
        rx = (22 - i * 1.5) * k
        bones.ring(cx, y, rx, hi, 1.6 * k)
        bones.rect(cx - rx - 3 * k, y - k, cx + rx + 3 * k, y + rx, (0, 0, 0, 0))
    bones.ellipse(cx - 5 * k, gy - 71 * k, 3 * k, 2.5 * k, '#fff6d8')
    bones.ellipse(cx + 5 * k, gy - 71 * k, 3 * k, 2.5 * k, '#fff6d8')
    bones.rect(cx - 6 * k, gy - 63 * k, cx + 6 * k, gy - 63 * k + 1, dark)
    for x in range(-5, 6, 2):
        bones.rect(cx + x * k, gy - 62 * k, cx + x * k + 1, gy - 61 * k, hi)
    vis = gy - 92 * k + 92 * k * (1 - ease_out(t))
    rows = np.broadcast_to(np.arange(L.h)[:, None] >= vis, (L.h, L.w))
    body.clip(rows)
    bones.clip(rows)
    L.over(body, opacity=0.42 * fade)
    L.over(bones, opacity=0.95 * fade)


# ------------------------------------------------------------------- shadows
def shadow_line(L, x0, gy, length, phase, width=None):
    if length <= 0:
        return
    width = width or 2.2 * K
    S = _scratch(L)
    S.rect(x0, gy - width + 1, x0 + length, gy, SHADOW)
    tip = x0 + length
    wob = math.sin(phase * 2 * math.pi)
    S.ellipse(tip, gy - width / 2 + 0.5, (3 + wob * 0.5) * K, width / 2 + K * 0.6, SHADOW)
    L.over(S)


def shadow_pool(L, cx, gy, rx):
    S = _scratch(L)
    S.ellipse(cx, gy - 1, rx, 2.2 * K, SHADOW)
    L.over(S)


def tendrils(L, x0, gy, spacing, heights, phase):
    S = _scratch(L)
    for i, h in enumerate(heights):
        if h <= 0:
            continue
        x = x0 + i * spacing
        sway = math.sin(phase * 2 * math.pi + i) * 2 * K
        S.poly([(x - 3 * K * 0.6, gy), (x + sway, gy - h), (x + 3 * K * 0.6, gy)], SHADOW)
    L.over(S)


def shadow_hand(L, x, gy, h, phase, grip=0.0):
    """A shadow arm rising from the ground with grasping fingers (Neck Bind)."""
    if h <= 1:
        return
    k = K * 0.8
    S = _scratch(L)
    sway = math.sin(phase * 2 * math.pi) * 1.5 * k
    top = gy - h
    S.poly([(x - 4 * k, gy), (x - 2 * k + sway, top + 3 * k), (x + 2 * k + sway, top + 3 * k),
            (x + 4 * k, gy)], SHADOW)
    S.ellipse(x + sway, top + 3 * k, 4 * k, 3 * k, SHADOW)
    spread = 4 * (1 - grip)
    for j, dx in enumerate((-3, -1, 1, 3)):
        fx_ = x + sway + dx * k * (1 + spread / 4)
        _spike(S, fx_, top + 2 * k, 90 - dx * (6 + spread * 3), (5 + (j in (1, 2))) * k, 2 * k, SHADOW)
    L.over(S)


# ------------------------------------------------------------------- healing
def heal_glow(L, cx, cy, phase, r=5, col=(110, 255, 150, 255), core=(200, 255, 210, 255)):
    G = _scratch(L)
    G.disc(cx, cy, r + K + math.sin(phase * 2 * math.pi) * K * 0.6, col)
    L.over(G, opacity=0.35)
    S = _scratch(L)
    S.disc(cx, cy, r * 0.55, core)
    for k in range(6):
        u = (phase + k / 6) % 1
        sx = cx + math.sin(k * 2.4 + u * 6) * r
        sy = cy - u * r * 2.5
        S.rect(sx - 2, sy, sx + 2, sy, col)
        S.rect(sx, sy - 2, sx, sy + 2, col)
        S.put(sx, sy, '#ffffff')
    L.over(S, opacity=0.9)


# --------------------------------------------------------- ground smashing
def ground_impact(L, cx, gy, t, seed=4, size=1.0):
    """size is relative to the old 48px scale (it is multiplied by K)."""
    if t <= 0 or t >= 1:
        return
    size *= K
    rng = random.Random(seed)
    S = _scratch(L)
    reach = 34 * size * ease_out(min(1, t * 2))
    for k in range(6):
        x, dirn = cx, (-1 if k % 2 else 1)
        pts = [(x, gy)]
        for s in range(5):
            x += dirn * reach / 5 * rng.uniform(0.7, 1.2)
            pts.append((x, gy - rng.choice((0, 0, 1, 2))))
        S.polyline(pts, '#3b2a1c', 2)
    L.over(S)
    R = _scratch(L)
    for k in range(14):
        vx = rng.uniform(-1, 1) * 30 * size
        vy = rng.uniform(25, 45) * size
        tt = t * 1.4
        x = cx + vx * tt
        y = gy - (vy * tt - 36 * size * tt * tt)
        if y > gy:
            continue
        s = rng.choice((2, 2, 3, 3, 4)) * size * 0.5
        R.poly([(x, y + s * 0.3), (x + s * 0.6, y), (x + s, y + s * 0.5), (x + s * 0.7, y + s),
                (x + s * 0.1, y + s * 0.9)], rng.choice(('#8b6a48', '#a3815a', '#6f5238')))
    R.cel(2)
    R.outline(0.4)
    L.over(R)
    for k, off in enumerate((-14, 0, 14)):
        dust(L, cx + off * size, gy, min(0.99, t * 1.1 + k * 0.05), 7 * size, seed + k)
    if t < 0.25:
        burst(L, cx, gy - 2, 12 * size, t / 0.25, inner='#fff7d6', outer='#ffd27a', seed=seed)


# --------------------------------------------------------------- creatures
def crow(L, x, y, flap, flip=False, k=None):
    """A crow with a red eye; flap 0 = wings up, 1 = wings down."""
    k = k or K * 0.9
    S = Layer(int(16 * k) + 4, int(10 * k) + 4)
    o = (2, 2)
    body = '#15131c'
    S.ellipse(o[0] + 8 * k, o[1] + 5 * k, 4.5 * k, 2.2 * k, body)
    S.ellipse(o[0] + 12.5 * k, o[1] + 4 * k, 2 * k, 1.8 * k, body)
    S.poly([(o[0] + 14 * k, o[1] + 3.6 * k), (o[0] + 16 * k, o[1] + 4.4 * k), (o[0] + 14 * k, o[1] + 4.8 * k)], '#3a3442')
    S.poly([(o[0] + 4 * k, o[1] + 5 * k), (o[0], o[1] + 3.5 * k), (o[0] + 0.5 * k, o[1] + 6.5 * k)], body)
    if flap % 2 == 0:
        S.poly([(o[0] + 6 * k, o[1] + 4 * k), (o[0] + 4 * k, o[1]), (o[0] + 11 * k, o[1] + 4 * k)], body)
    else:
        S.poly([(o[0] + 6 * k, o[1] + 5 * k), (o[0] + 5 * k, o[1] + 10 * k), (o[0] + 11 * k, o[1] + 5 * k)], body)
    S.put(o[0] + 13 * k, o[1] + 3.5 * k, '#e01414')
    S.outline(color='#3a3550')
    if flip:
        S = S.flipped()
    L.over(S, x - 2, y - 2)


def toad(L, cx, gy, blink=False, puff=0, k=None):
    """Gamabunta-style chief toad in a blue vest with a pipe."""
    k = k or K * 1.1
    S = _scratch(L)
    body, belly, vest = '#c8552c', '#f2cf98', '#2b3f6c'
    S.ellipse(cx, gy - 15 * k, 25 * k, 15 * k, body)
    S.ellipse(cx, gy - 27 * k, 20 * k, 12 * k, body)
    S.ellipse(cx, gy - 10 * k, 15 * k, 9 * k, belly)
    S.poly([(cx - 25 * k, gy - 18 * k), (cx - 12 * k, gy - 24 * k), (cx - 9 * k, gy - 2 * k), (cx - 22 * k, gy - 2 * k)], vest)
    S.poly([(cx + 25 * k, gy - 18 * k), (cx + 12 * k, gy - 24 * k), (cx + 9 * k, gy - 2 * k), (cx + 22 * k, gy - 2 * k)], vest)
    for sx in (-1, 1):
        S.ellipse(cx + sx * 17 * k, gy - 3 * k, 8 * k, 3.5 * k, body)
        S.ellipse(cx + sx * 11 * k, gy - 36 * k, 6 * k, 6 * k, body)
        for w in (-2, 0, 2):
            S.rect(cx + sx * (17 + w * 2) * k, gy - 2, cx + sx * (17 + w * 2) * k + 1, gy, scale(body, 0.7))
    for i in range(7):
        S.ellipse(cx - 14 * k + i * 5 * k, gy - 30 * k + (i % 2) * 4 * k, 1.2 * k, 1 * k, scale(body, 0.8))
    S.cel(int(4 * k), 1)
    S.outline(0.35)
    L.over(S)
    F = _scratch(L)
    for sx in (-1, 1):
        ex, ey = cx + sx * 11 * k, gy - 37 * k
        if blink:
            F.rect(ex - 3 * k, ey, ex + 3 * k, ey + 1, '#2a1a10')
        else:
            F.ellipse(ex, ey, 3.6 * k, 3.2 * k, '#ffd63a')
            F.rect(ex - 0.5, ey - 2.5 * k, ex + 0.5, ey + 2.5 * k, '#1a1008')
    F.line(cx - 12 * k, gy - 25 * k, cx + 12 * k, gy - 25 * k, '#5a2a14', 2)
    F.line(cx - 14 * k, gy - 34 * k, cx - 8 * k, gy - 40 * k, '#7a2a18', 2)
    F.line(cx + 10 * k, gy - 25 * k, cx + 22 * k, gy - 31 * k, '#6a4a2a', 3)
    F.rect(cx + 21 * k, gy - 34 * k, cx + 23 * k, gy - 31 * k, '#6a4a2a')
    L.over(F)
    if puff:
        smoke_puff(L, cx + 23 * k, gy - (38 + puff * 4) * k, min(0.9, puff), 3 * k, seed=int(puff * 10))


def slug(L, cx, gy, phase, k=None):
    """Katsuyu: white slug with blue stripes."""
    k = k or K * 1.1
    S = _scratch(L)
    body, stripe = '#eef3fb', '#5b8fd6'
    S.ellipse(cx, gy - 6 * k, 22 * k, 6 * k, body)
    S.ellipse(cx - 8 * k, gy - 12 * k, 12 * k, 10 * k, body)
    S.ellipse(cx - 14 * k, gy - 18 * k, 6 * k, 6 * k, body)
    for j, y in enumerate((-15, -11, -7)):
        S.line(cx + (-18 + j * 2) * k, gy + y * k, cx + (14 - j * 3) * k, gy + (y + 4) * k, stripe, 2)
    sway = math.sin(phase * 2 * math.pi) * k
    S.line(cx - 17 * k, gy - 22 * k, cx - 20 * k + sway, gy - 28 * k, body, 3)
    S.line(cx - 12 * k, gy - 22 * k, cx - 10 * k + sway, gy - 28 * k, body, 3)
    S.cel(3, 1, lo=0.85)
    S.outline(0.45)
    S.disc(cx - 20 * k + sway, gy - 28 * k, 1.2 * k, '#2a2a40')
    S.disc(cx - 10 * k + sway, gy - 28 * k, 1.2 * k, '#2a2a40')
    L.over(S)


def summon_seal(L, cx, gy, t):
    """Black summoning script spreading from the palm along the ground."""
    S = _scratch(L)
    reach = 26 * K * ease_out(t)
    for j in range(-3, 4):
        S.line(cx, gy, cx + j * reach / 3, gy - (1 if j % 2 else 0), '#141018', 2)
        for m in range(1, 4):
            S.rect(cx + j * reach / 3 * m / 4, gy - 3, cx + j * reach / 3 * m / 4 + 1, gy - 2, '#141018')
    L.over(S)


# ---------------------------------------------------------------- vortex etc
def kamui(L, cx, cy, r, phase, opacity=1.0):
    if r <= 0.5:
        return
    S = _scratch(L)
    S.disc(cx, cy, r, (40, 32, 56, 255))
    n = max(40, int(r * 8))
    for k in range(3):
        pts = []
        for s in range(n):
            u = s / (n - 1)
            a = -phase * 2 * math.pi * 1.5 + k * 2 * math.pi / 3 + u * 4.2
            rr = r * (1 - u) * 0.95
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.9))
        S.polyline(pts[: int(n * 0.7)], '#8c7bb8', 2)
        S.polyline(pts[int(n * 0.7) - 1:], '#c9bdf0', 1)
    S.disc(cx, cy, max(1, r * 0.18), '#08060c')
    S.outline(color='#1a1424')
    L.over(S, opacity=opacity)


def wings(L, cx, cy, t, phase, col_a='#ff7fae', col_b='#ffb24d'):
    """Chakra butterfly wings behind the user (Choji's Butterfly Mode)."""
    if t <= 0:
        return
    S = _scratch(L)
    k = ease_out(t) * K * 1.2
    flap = 0.8 + 0.2 * math.sin(phase * 2 * math.pi)
    for sx in (-1, 1):
        def P(x, y):
            return (cx + sx * x * k * flap, cy + y * k)
        S.poly([P(2, -2), P(14, -30), P(34, -36), P(38, -24), P(28, -6), P(6, 2)], col_a)
        S.poly([P(3, 2), P(26, 0), P(30, 14), P(18, 22), P(6, 12)], col_b)
        S.poly([P(16, -26), P(30, -30), P(32, -22), P(22, -14)], '#ffd6e6')
        S.poly([P(12, 4), P(22, 6), P(18, 14)], '#ffe2b0')
        for vy in (-20, -10):
            a, b = P(4, 0), P(32, vy - 8)
            S.line(a[0], a[1], b[0], b[1], '#e2588a')
    S.outline(color='#c2416f')
    L.over(S, opacity=0.78)


def trigram_circle(L, cx, gy, t, phase):
    if t <= 0:
        return
    S = _scratch(L)
    rx, ry = 30 * K * ease_out(t), 6 * K * ease_out(t)
    S.ellipse(cx, gy - 2, rx, ry, (130, 190, 255, 255))
    S.ellipse(cx, gy - 2, rx - 2 * K, ry - 1.4 * K, (0, 0, 0, 0))
    for j in range(8):
        a = 2 * math.pi * j / 8 + phase * 0.5
        x, y = cx + math.cos(a) * (rx - 4 * K), gy - 2 + math.sin(a) * (ry - 2 * K)
        for m in range(3):
            S.rect(x - 1.2 * K, y - 2 * K + m * K * 0.9, x + 1.2 * K, y - 2 * K + m * K * 0.9 + 1,
                   '#e9f4ff' if (j + m) % 2 else (130, 190, 255, 255))
    L.over(S, opacity=0.85)


def palm_blast(L, x, y, t, col='#7fc8ff'):
    if t <= 0 or t >= 1:
        return
    S = _scratch(L)
    r = (2 + 5 * ease_out(t)) * K
    S.ellipse(x + r * 0.6, y, r, r * 0.8, col)
    S.ellipse(x + r * 0.8, y, r * 0.5, r * 0.4, '#e6f6ff')
    S.outline(color='#2f6fbf')
    L.over(S, opacity=1 - t * 0.7)


def aura(L, body, color, phase, strength=1.0, seed=5):
    """Flickering chakra flame around a rendered body layer (same size as L)."""
    rng = random.Random(seed + int(phase * 100))
    m = body.px[..., 3] > 100
    S = _scratch(L)
    grown = m.copy()
    for _ in range(int(2 * K)):
        g = grown.copy()
        g[1:] |= grown[:-1]
        g[:-1] |= grown[1:]
        g[:, 1:] |= grown[:, :-1]
        g[:, :-1] |= grown[:, 1:]
        grown = g
    up = grown.copy()
    cols = np.arange(L.w)[None, :]
    for k in range(1, int(5 * K)):
        if rng.random() < 0.85 * strength:
            up[:-k] |= grown[k:] & ((cols // 2) % 4 == (k // 3 + int(phase * 8)) % 4)
    S.mask_fill(up & ~m, color)
    L.over(S, opacity=0.5 * strength)


def ghost(body, tint='#9fe3ff'):
    """Translucent spirit copy of a rendered body."""
    g = body.copy()
    g.tint(tint, 0.65)
    g.fade(0.6)
    return g


def petals(L, cx, cy, t, n=18, seed=6, cols=('#ffb7d0', '#ffd6e5', '#ff8fb8'), radius=22):
    rng = random.Random(seed)
    S = _scratch(L)
    for i in range(n):
        a = rng.uniform(0, 2 * math.pi) + t * 5
        rr = radius * rng.uniform(0.3, 1.0) * (0.4 + 0.6 * t)
        x = cx + math.cos(a) * rr
        y = cy + math.sin(a) * rr * 0.7 - t * 6 * K
        c = rng.choice(cols)
        S.ellipse(x, y, 1.6, 1.1, c)
        S.put(x + 1, y + 1, scale(c, 0.8))
    L.over(S)


def _bigtext(L, s, x, y, fg, bg=None, k=None):
    k = k or max(2, round(K * 0.65))
    w = text_width(s)
    T = Layer(w + 6, 11)
    if bg:
        T.rect(0, 0, w + 3, 8, bg)
        T.poly([(2, 8), (5, 8), (1, 10.5)], bg)
        T.outline(color=fg)
    text(T, s, 2, 2, fg)
    L.over(T.scaled(k), x, y)


def speech(L, s, x, y, fg='#1b1422', bg='#ffffff'):
    _bigtext(L, s, x, y, fg, bg)


def zzz(L, x, y, t):
    """Floating sleep letters."""
    for j in range(3):
        u = (t + j / 3) % 1
        S = Layer(5, 7)
        text(S, 'z' if j % 2 else 'Z', 1, 1, (230, 236, 255, 255))
        S.outline(color='#3a3f5c')
        S = S.scaled(max(2, round(K * 0.65)))
        L.over(S, int(x + u * 6 * K + j * 3), int(y - u * 10 * K), opacity=min(1, (1 - u) * 1.6))


def clouds(L, t, w, y0, seed=7):
    rng = random.Random(seed)
    S = _scratch(L)
    for j in range(3):
        x = (rng.uniform(0, w) + t * (6 + j * 3) * K) % (w + 30 * K) - 15 * K
        y = y0 + j * 7 * K
        for dx, r in ((0, 3), (4, 4), (8, 3)):
            S.disc(x + dx * K, y, r * K, '#ffffff')
    S.outline(color='#b9c6dc')
    L.over(S, opacity=0.9)


# --------------------------------------------------------------------- props
def prop(L, name, x, y, f=0):
    """Hand-held snack/item at hand position (x, y). f = frame index. Drawn on
    the old 48px grid scaled by K*0.75 around the hand."""
    S = _scratch(L)
    k = K * 0.55
    c = Ctx(S, x, y, sx=k, sy=k)
    if name == 'ramen':
        c.rect(-5, -1, 4, 2, '#f4f1ea')
        c.rect(-4, 3, 3, 3, '#d8d2c4')
        c.rect(-5, -1, 4, -1, '#c8323c')
        c.rect(-4, -2, 3, -2, '#f6d27a')
        c.ellipse(-2, -2.5, 1, 0.6, '#f39ab8')
        c.ellipse(1, -2.2, 0.9, 0.5, '#7a4a2a')
        c.line(2, -2, 6, -9, '#c99a5a')
        c.line(3, -2, 7, -9, '#c99a5a')
        if f % 4 in (1, 2):
            c.line(-1, -3, 0, -9, '#f6d27a')
    elif name == 'chopsticks':
        c.line(-1, 1, 4, -7, '#c99a5a')
        c.line(0, 1, 5, -7, '#c99a5a')
        if f % 8 in (1, 2, 3):
            c.line(1, 0, 1.5, 4, '#f6d27a')
            c.line(2, 0, 2.5, 4.5, '#f6d27a')
    elif name == 'chip':
        if f % 8 in (1, 2, 3):
            c.ellipse(0.5, -1, 1.6, 1.2, '#f2c75a')
    elif name == 'chips':
        c.rect(-3, -4, 3, 4, '#d8322f')
        c.rect(-3, -1, 3, 1, '#f6d24a')
        c.rect(-3, -5, 3, -5, '#b8b8c0')
        if f % 4 in (0, 1):
            c.ellipse(5, -6, 1.6, 1.2, '#f2c75a')
    elif name == 'tomato':
        c.ellipse(0, -2, 3, 3, '#e03a2a')
        c.ellipse(-1, -3, 0.8, 0.8, '#ff9a8a')
        c.rect(-1, -5, 1, -5, '#3f9a3a')
        if f >= 6:
            c.ellipse(3, -3, 1.4, 1.4, (0, 0, 0, 0))
    elif name == 'dango':
        c.line(0, 2, 4, -9, '#c99a5a')
        for j, col in enumerate(('#7fbf6a', '#f4f1ea', '#f5a3c0')):
            if f < 8 or j < 2:
                c.ellipse(1 + j * 1.2, -1 - j * 3, 1.8, 1.8, col)
    elif name == 'sake':
        c.rect(-2, -7, 1, 2, '#efe6d0')
        c.rect(-1, -9, 0, -8, '#efe6d0')
        c.rect(-2, -4, 1, -2, '#3a3a5a')
        c.rect(4, 1, 6, 2, '#f4f1ea')
    elif name == 'book':
        c.rect(-6, -4, 5, 2, '#f39a2a')
        c.rect(-1, -4, 0, 2, '#c66a14')
        c.rect(-5, -3, -2, -1, '#ffffff')
        c.rect(2, -2, 3, -2, '#c8323c')
    elif name == 'notebook':
        c.rect(-5, -3, 3, 2, '#f4f1ea')
        for j in range(3):
            c.line(-4, -2 + j * 1.6, -4 + (f + j) % 4 + 2, -2 + j * 1.6, '#7a7f8c')
        c.line(4, -4 + (f % 2), 7, -8 + (f % 2), '#e8b84a')
    elif name == 'flower':
        c.line(0, 2, 1, -6, '#3f9a3a')
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            c.ellipse(1 + dx * 2, -8 + dy * 2, 1.5, 1.5, '#f58ab0')
        c.ellipse(1, -8, 0.8, 0.8, '#ffe14a')
    elif name == 'cinnamon_roll':
        c.ellipse(0, -1, 3.5, 3.5, '#c8843a')
        c.ellipse(0, -1, 2.2, 2.2, '#8a5222')
        c.ellipse(0, -1, 1.4, 1.4, '#c8843a')
        c.ellipse(0, -1, 0.6, 0.6, '#f4e2c0')
        if f >= 8:
            c.ellipse(3, -2, 1.6, 1.6, (0, 0, 0, 0))
    elif name == 'shogi':
        c.poly([(-3, 2), (-3, -2), (0, -5), (3, -2), (3, 2)], '#e9c98a')
        c.rect(-1, -2, 1, 0, '#3a2a1a')
    S.cel(1)
    S.outline(0.35)
    L.over(S)
