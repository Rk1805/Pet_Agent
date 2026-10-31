"""The Spider-Man pack: Spider-Man, Miles Morales, Spider-Gwen, Doctor Octopus,
Green Goblin and Venom. Designs, effects and moves for these six live here;
characters.py and anims.py pull them in.

Same conventions as the Naruto pack (see body.py): hair/headgear on the 16x15
face grid, torso in base build units, poses as joint angles."""

import math
import random

import effects as fx
from body import Pose, UNIT as U, W as BASE
from characters import Character, cap
from effects import ease_in_out, ease_out, seg
from engine import Layer, scale

SPIDEY_RED = '#c8202c'
SPIDEY_BLUE = '#2346a6'
WEB_DARK = '#4e0b14'
MILES_BLACK = '#1b1b24'
MILES_RED = '#e0262f'
GWEN_WHITE = '#eff0f5'
GWEN_PINK = '#e2489b'
GWEN_TEAL = '#38c6c3'
SYMBIOTE = '#15141d'
METAL = '#8d949e'
METAL_LO = '#5c636d'


# ============================================================ shared design bits
def emblem(t, x, y, col, k=1.0):
    """Spider emblem on a chest (torso units)."""
    t.ellipse(x, y, 1.1 * k, 1.4 * k, col)
    t.ellipse(x, y + 2.6 * k, 1.4 * k, 2.1 * k, col)
    for s in (-1, 1):
        t.line(x, y - 0.4 * k, x + s * 2.6 * k, y - 2.6 * k, col)
        t.line(x + s * 2.6 * k, y - 2.6 * k, x + s * 3.2 * k, y - 4.6 * k, col)
        t.line(x, y + 0.6 * k, x + s * 3.4 * k, y - 0.2 * k, col)
        t.line(x, y + 1.8 * k, x + s * 3.4 * k, y + 3.0 * k, col)
        t.line(x, y + 2.8 * k, x + s * 2.4 * k, y + 5.0 * k, col)
        t.line(x + s * 2.4 * k, y + 5.0 * k, x + s * 2.8 * k, y + 7.0 * k, col)


def torso_web(t, col, cx=0, cy=8):
    b = t.b
    for x, y in ((-b['sh'], 3), (-b['chest'], 9), (-b['waist'], 21), (0, 22), (b['waist'], 21),
                 (b['chest'], 9), (b['sh'], 3), (-5, -2), (5, -2), (0, -2)):
        t.line(cx, cy, x, y, col)
    for k in (0.35, 0.7):
        t.polyline([(-b['chest'] * k * 1.4, cy - 6 * k), (0, cy - 4 * k), (b['chest'] * k * 1.4, cy - 6 * k)], col)
        t.polyline([(-b['waist'] * k * 1.4, cy + 9 * k), (0, cy + 12 * k), (b['waist'] * k * 1.4, cy + 9 * k)], col)


def mask_head(col, web=None):
    """Hair function for a full-head mask: smooth skull, optional web seams over the top."""
    def hair(b, f):
        b.ellipse(7.5, 5, 8.6, 7.3, col)
        cap(f, col, 4)
        if web:
            for x, y in ((-0.5, 1.5), (3, -2.3), (7.5, -3), (12, -2.3), (15.5, 1.5)):
                f.line(7.5, 4.5, x, y, web)
            f.polyline([(0.5, 2.5), (3.5, 0.6), (7.5, 0), (11.5, 0.6), (14.5, 2.5)], web)
    return hair


# ================================================================== SPIDER-MAN
def spidey_torso(t):
    b = t.b
    torso_web(t, WEB_DARK)
    for s in (-1, 1):
        t.poly([(s * b['sh'], 3), (s * b['chest'], 9), (s * b['waist'], 21), (s * (b['waist'] - 3.5), 21),
                (s * (b['chest'] - 4.5), 9), (s * (b['sh'] - 3), 3)], SPIDEY_BLUE)
    emblem(t, 0, 7, '#14131a')


SPIDER_MAN = Character(
    'spider_man', 'Spider-Man', 'hero', SPIDEY_RED, '#ffffff', hair=mask_head(SPIDEY_RED, WEB_DARK),
    outfit=dict(top=SPIDEY_RED, pants=SPIDEY_BLUE, sleeve='long', sleeve_color=SPIDEY_BLUE,
                sleeve_lower=SPIDEY_RED, sleeve_top=SPIDEY_RED, sleeve_top_len=0.35, baggy=0.2,
                gloves=SPIDEY_RED, fingerless=False, pants_baggy=0.3, boots=SPIDEY_RED, sandals='#7a1219',
                belt=SPIDEY_RED, arm_web=WEB_DARK, arm_web_from='elbow', leg_web=WEB_DARK, leg_web_from='knee'),
    torso=spidey_torso, mask=dict(lens='#f4f6fb', rim='#121118', web=WEB_DARK),
    color=SPIDEY_RED, speed=0.7, snack='pizza', size=0.97, pack='spiderman',
    jutsu=['web_swing', 'web_shot'], tagline='Your friendly neighbourhood Spider-Man. Thwip!')


# ================================================================ MILES MORALES
def miles_torso(t):
    torso_web(t, MILES_RED)
    emblem(t, 0, 7, MILES_RED, 1.15)


MILES = Character(
    'miles_morales', 'Miles Morales', 'hero', MILES_BLACK, '#ffffff', hair=mask_head(MILES_BLACK, MILES_RED),
    outfit=dict(top=MILES_BLACK, pants=MILES_BLACK, sleeve='long', baggy=0.2, gloves=MILES_BLACK,
                fingerless=False, pants_baggy=0.3, boots=MILES_RED, sandals='#f2f2f2',
                arm_web=MILES_RED, leg_web=MILES_RED, leg_web_from='knee'),
    torso=miles_torso, mask=dict(lens='#f4f6fb', rim='#0b0b10', web=MILES_RED, lens_w=1.6),
    color=MILES_RED, speed=0.75, size=0.93, pack='spiderman',
    jutsu=['web_swing', 'venom_strike', 'camouflage', 'vibing'],
    tagline='Brooklyn\'s Spider-Man. Venom Strike, camouflage, headphones always on.')


# ================================================================= SPIDER-GWEN
def gwen_hood(b, f):
    b.ellipse(7.5, 6, 10.6, 10, GWEN_WHITE)
    b.ellipse(7.5, 6.6, 9.3, 8.9, GWEN_PINK)
    f.poly([(-2, 7), (-1.5, 0), (2.5, -3.6), (12.5, -3.6), (16.5, 0), (17, 7), (15.6, 7), (15, 1.5),
            (11.5, -1.6), (3.5, -1.6), (0, 1.5), (-0.6, 7)], GWEN_WHITE)
    f.polyline([(-0.6, 7), (0, 1.5), (3.5, -1.6), (11.5, -1.6), (15, 1.5), (15.6, 7)], GWEN_PINK)
    for x in (2, 5, 8, 11):
        f.line(x, -1.6, x + 0.5, -3.4, '#b9bccc')


def gwen_torso(t):
    b = t.b
    for x in (-8, -4, 0, 4, 8):
        t.line(0, -1, x, 7, '#1d1d28')
    t.polyline([(-b['sh'] + 2, 4), (0, 6), (b['sh'] - 2, 4)], '#1d1d28')
    emblem(t, 0, 9, '#1d1d28', 0.8)
    for s in (-1, 1):
        t.line(s * (b['chest'] - 1), 9, s * (b['waist'] - 1), 21, GWEN_PINK)
        t.line(s * (b['chest'] - 2.5), 10, s * (b['waist'] - 2.5), 21, GWEN_TEAL)


SPIDER_GWEN = Character(
    'spider_gwen', 'Spider-Gwen', 'hero', GWEN_WHITE, '#ffffff', hair=gwen_hood, build='female',
    outfit=dict(top=GWEN_WHITE, pants='#23232f', sleeve='long', sleeve_color=GWEN_WHITE,
                sleeve_lower='#23232f', baggy=0.2, gloves=GWEN_TEAL, fingerless=False, pants_baggy=0.3,
                boots=GWEN_TEAL, sandals='#1f8f8c', leg_web=GWEN_WHITE, leg_web_from='knee'),
    torso=gwen_torso, mask=dict(lens='#f4f6fb', rim='#121118', lens_w=1.35, lens_h=2.2),
    color=GWEN_PINK, speed=0.75, size=0.95, pack='spiderman',
    jutsu=['web_swing', 'web_shot', 'drum_practice'],
    tagline='Ghost-Spider from Earth-65. Drummer for the Mary Janes.')


# ============================================================ DOCTOR OCTOPUS
def ock_hair(b, f):
    hc = '#2b211b'
    b.ellipse(7.5, 4.5, 9.2, 7.2, hc)
    b.crown(7.5, 4, [(160, 10, 7), (125, 10, 7), (90, 9, 7), (55, 10, 7), (20, 10, 7)], hc)
    cap(f, hc, 3)
    for x in (2, 6, 10, 13):
        f.spike(x, 3, -100 + x * 2, 3.5, 3, hc)


def ock_goggles(c):
    for x in (4.3, 11.3):
        c.ellipse(x, 8.2, 2.9, 2.6, '#c9a227')
        c.ellipse(x, 8.2, 2.2, 2.0, '#2a2b34')
        c.put(x - 0.8, 7.4, '#8ea4c8')
    c.line(7, 8, 8.6, 8, '#c9a227')
    c.line(-1, 7.6, 1.5, 8, '#4a3a2a')
    c.line(14.2, 8, 16.5, 7.6, '#4a3a2a')


def ock_torso(t):
    b = t.b
    coat, shirt = '#5b3e2c', '#3d4a3c'
    hem = 64
    t.poly([(-b['sh'], 3), (-b['sh'] + 3, -0.5), (b['sh'] - 3, -0.5), (b['sh'], 3), (b['chest'] + 1, 10),
            (b['hip'] + 5, hem), (-b['hip'] - 5, hem), (-b['chest'] - 1, 10)], coat)
    t.poly([(-3.5, -1), (3.5, -1), (2.5, 24), (-2.5, 24)], shirt)
    for s in (-1, 1):
        t.poly([(s * 3.5, -1), (s * 8, -1), (s * 5, 10), (s * 2.5, 12)], scale(coat, 1.18))
        t.line(s * 2.5, 24, s * 4, hem, scale(coat, 0.7))
    t.rect(-b['waist'] - 1, 19, b['waist'] + 1, 22, METAL)
    t.rect(-b['waist'] - 1, 19, b['waist'] + 1, 19, '#c6ccd4')
    t.ellipse(0, 20.5, 2, 1.6, '#c9a227')


def ock_tentacles(c):
    """Four metal arms from his back harness. Pose.tent overrides the claw positions
    (torso units, +x = forward); otherwise they sway around his shoulders."""
    pose = c.pose
    ph = pose.phase if pose else 0.0
    ground = (191 - c.oy) / c.sy
    tips = getattr(pose, 'tent', None) if pose else None
    if callable(tips):
        tips = tips(ground)
    sw = math.sin(ph * 2 * math.pi)
    if tips is None and c.side:            # in profile all four trail behind him
        tips = [(-30, 4 + sw * 3), (-36, -16 - sw * 2), (-26, -34 + sw * 2), (-12, -42 - sw * 2)]
    elif tips is None:
        tips = [(-36, 8 + sw * 3), (-31, -22 - sw * 2), (31, -22 + sw * 2), (36, 8 - sw * 3)]
    fwd = -1 / 0.8 if c.side else 1       # back items are mirrored behind the body in side view
    for n, (tx, ty) in enumerate(tips):
        tx *= fwd
        out = -1 if (tx < 0) else 1
        bx, by = 5 * out, 20
        # S-curve: droop down and out from the harness, then sweep up to the claw
        p1, p2 = (bx + 14 * out, by + 16), (tx + 6 * out, ty + 22)
        n = max(17, int(math.hypot(tx - bx, ty - by) / 1.4))     # dense enough to read as one arm
        pts = []
        for j in range(n + 1):
            u = j / n
            x = (1 - u) ** 3 * bx + 3 * (1 - u) ** 2 * u * p1[0] + 3 * (1 - u) * u * u * p2[0] + u ** 3 * tx
            y = (1 - u) ** 3 * by + 3 * (1 - u) ** 2 * u * p1[1] + 3 * (1 - u) * u * u * p2[1] + u ** 3 * ty
            pts.append((x, y))
        for j, (x, y) in enumerate(pts):
            r = 2.7 - 0.8 * j / n
            px, py = c.P(x, y)              # draw directly: Ctx.ellipse can't take the mirrored (negative) scale
            c.L.ellipse(px, py, r * abs(c.sx), r * abs(c.sy), METAL if j % 2 else METAL_LO)
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        ang = math.degrees(math.atan2(-(y1 - y0), x1 - x0))
        for da in (-35, 0, 35):
            c.spike(x1, y1, ang + da, 4.2, 2, METAL_LO)
        c.ellipse(x1, y1, 1.4, 1.4, '#ff4040')


DOC_OCK = Character(
    'doc_ock', 'Doctor Octopus', 'villain', '#ecc0a2', '#3a2a22', hair=ock_hair, headgear=ock_goggles,
    back_item=ock_tentacles, build='big',
    outfit=dict(top='#5b3e2c', pants='#2e2a28', sleeve='long', sleeve_color='#5b3e2c', baggy=1.6,
                long_top=True, sandals='#1d1a18', boots='#24201d', pants_baggy=1.4),
    torso=ock_torso, mouth='smirk', brows='angry', brow_color='#2b211b', color='#c9a227', speed=0.4,
    snack='tea', size=1.0, pack='spiderman', jutsu=['tentacle_slam', 'tentacle_rise'],
    tagline='Otto Octavius. Four arms, zero patience.')


# ================================================================ GREEN GOBLIN
GOB_GREEN = '#5fa83a'
GOB_PURPLE = '#6b2f8a'


def goblin_hat(b, f):
    b.ellipse(7.5, 4, 9.2, 7, GOB_PURPLE)
    b.poly([(12, -2), (19, 3), (23, 13), (20, 14), (16, 6), (10, 2)], GOB_PURPLE)
    cap(f, GOB_PURPLE, 4)
    f.polyline([(-1, 4), (3, 3.2), (12, 3.2), (16, 4)], scale(GOB_PURPLE, 0.7))
    for s, x in ((-1, -0.5), (1, 15.5)):
        f.spike(x, 8.5, 90 - s * 70, 5, 3.4, GOB_GREEN)


def goblin_torso(t):
    b = t.b
    tunic = GOB_PURPLE
    hem = 40
    t.poly([(-b['sh'], 3), (-b['sh'] + 3, -0.5), (b['sh'] - 3, -0.5), (b['sh'], 3), (b['chest'], 9),
            (b['hip'] + 2.5, hem), (-b['hip'] - 2.5, hem), (-b['chest'], 9)], tunic)
    t.poly([(-4, -1), (4, -1), (0, 6)], GOB_GREEN)
    for x in range(-int(b['hip']), int(b['hip']) + 1, 4):
        t.poly([(x, hem - 0.5), (x + 4, hem - 0.5), (x + 2, hem + 3)], tunic)
    t.line(-b['sh'] + 2, 1, b['waist'], 24, '#6a4626', 2)
    t.rect(b['waist'] - 3, 23, b['waist'] + 3, 29, '#7a522c')
    t.rect(b['waist'] - 3, 23, b['waist'] + 3, 24, '#5a3a1e')
    t.rect(-b['waist'], 21, b['waist'], 22, scale(tunic, 0.65))


GREEN_GOBLIN = Character(
    'green_goblin', 'Green Goblin', 'villain', GOB_GREEN, '#f3d21a', hair=goblin_hat,
    outfit=dict(top=GOB_PURPLE, pants=GOB_GREEN, sleeve='long', sleeve_color=GOB_GREEN, baggy=0.6,
                long_top=True, gloves=GOB_PURPLE, fingerless=False, boots=GOB_PURPLE, sandals='#3e1a52',
                pants_baggy=0.5),
    torso=goblin_torso, mouth='grin', brows='angry', brow_color='#2f5a1d', color=GOB_GREEN, speed=0.55,
    size=1.0, pack='spiderman', jutsu=['pumpkin_bomb', 'goblin_glider', 'cackle'],
    tagline='Norman Osborn\'s worst idea. Pumpkin bombs and a jet glider.')


# ======================================================================= VENOM
def venom_torso(t):
    b = t.b
    for s in (-1, 1):
        t.polyline([(s * 3, 4), (s * 7, 7), (s * 8, 12)], '#2a2938')
        t.polyline([(s * 3, 15), (s * 6, 17), (s * 6, 21)], '#2a2938')
    w = '#f2f1f4'
    t.ellipse(0, 6, 3.2, 3.6, w)
    t.ellipse(0, 12, 2.4, 4.4, w)
    for s in (-1, 1):
        t.polyline([(s * 2, 4), (s * 7, -1), (s * (b['sh'] - 1), -1)], w, 2)
        t.polyline([(s * 3, 6), (s * 10, 3), (s * b['sh'], 6)], w, 2)
        t.polyline([(s * 2, 12), (s * 8, 17), (s * b['waist'], 22)], w, 2)
        t.polyline([(s * 2, 15), (s * 6, 22), (s * 7, 27)], w, 2)


VENOM = Character(
    'venom', 'Venom', 'villain', SYMBIOTE, '#ffffff', hair=mask_head(SYMBIOTE), build='brawny',
    outfit=dict(top=SYMBIOTE, pants=SYMBIOTE, sleeve='long', baggy=0.3, gloves=SYMBIOTE, fingerless=False,
                pants_baggy=0.4, boots=SYMBIOTE, sandals='#0a0a0f'),
    torso=venom_torso, mask=dict(lens='#f6f6f8', rim=None, shape='venom', lens_w=1.6, lens_h=2.1, lens_dy=-1.5, jaws=True),
    mouth='grin', color='#8c8ca8', speed=0.55, snack='chocolate', size=1.07, pack='spiderman',
    jutsu=['symbiote_lash', 'we_are_venom'], tagline='We are Venom. Fond of chocolate and tater tots.')


SPIDER_CHARACTERS = [SPIDER_MAN, MILES, SPIDER_GWEN, DOC_OCK, GREEN_GOBLIN, VENOM]

import characters as _roster  # noqa: E402
for _c in SPIDER_CHARACTERS:
    if _c.id not in _roster.BY_ID:
        _roster.CHARACTERS.append(_c)
        _roster.BY_ID[_c.id] = _c


# ===================================================================== effects
def web_line(L, x0, y0, x1, y1, sag=0.0):
    S = Layer(L.w, L.h)
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2 + sag
    pts = [((1 - u) ** 2 * x0 + 2 * (1 - u) * u * mx + u * u * x1,
            (1 - u) ** 2 * y0 + 2 * (1 - u) * u * my + u * u * y1) for u in (j / 12 for j in range(13))]
    S.polyline(pts, '#9aa4b8', 3)
    S.polyline(pts, '#ffffff', 1)
    L.over(S)


def web_splat(L, cx, cy, r, opacity=1.0):
    S = Layer(L.w, L.h)
    for a in range(0, 360, 45):
        t = math.radians(a + 10)
        S.line(cx, cy, cx + math.cos(t) * r, cy + math.sin(t) * r, '#ffffff')
    for rr in (0.35, 0.7, 1.0):
        pts = [(cx + math.cos(math.radians(a + 10)) * r * rr, cy + math.sin(math.radians(a + 10)) * r * rr)
               for a in range(0, 405, 45)]
        S.polyline(pts, '#ffffff')
    S.outline(0.3, color='#7d8798')
    L.over(S, opacity=opacity)


def pumpkin(L, cx, cy, r, glow=1.0):
    S = Layer(L.w, L.h)
    S.ellipse(cx, cy, r * 1.15, r, '#f2801f')
    for dx in (-0.55, 0, 0.55):
        S.line(cx + dx * r, cy - r * 0.9, cx + dx * r * 1.1, cy + r * 0.9, '#c95f12')
    S.rect(cx - r * 0.15, cy - r * 1.35, cx + r * 0.15, cy - r * 0.9, '#3d7a2a')
    lit = '#ffe36a' if glow > 0.5 else '#ffb03a'
    for s in (-1, 1):
        S.poly([(cx + s * r * 0.55, cy - r * 0.15), (cx + s * r * 0.2, cy - r * 0.15), (cx + s * r * 0.38, cy - r * 0.5)], lit)
    S.poly([(cx - r * 0.6, cy + r * 0.2), (cx + r * 0.6, cy + r * 0.2), (cx + r * 0.3, cy + r * 0.55),
            (cx, cy + r * 0.4), (cx - r * 0.3, cy + r * 0.55)], lit)
    S.cel(2, 1)
    S.outline(0.3)
    L.over(S)


def glider(L, cx, y, phase, flame=True):
    """Goblin glider: bat-wing deck with yellow eyes and a jet at the back (faces +x)."""
    S = Layer(L.w, L.h)
    k = U
    deck = '#36443a'
    S.poly([(cx - 30 * k, y), (cx - 18 * k, y - 4 * k), (cx + 18 * k, y - 4 * k), (cx + 30 * k, y),
            (cx + 22 * k, y + 2 * k), (cx + 14 * k, y + 6 * k), (cx + 6 * k, y + 3 * k), (cx, y + 7 * k),
            (cx - 6 * k, y + 3 * k), (cx - 14 * k, y + 6 * k), (cx - 22 * k, y + 2 * k)], deck)
    S.poly([(cx + 18 * k, y - 4 * k), (cx + 30 * k, y), (cx + 34 * k, y - 6 * k)], scale(deck, 1.2))
    for s in (-1, 1):
        S.ellipse(cx + 20 * k + s * 3 * k, y - 0.5 * k, 1.6 * k, 1.0 * k, '#ffe36a')
    S.cel(2, 1)
    S.outline(0.3)
    if flame:
        n = 3 + int(phase * 6) % 3
        for j in range(n):
            fx.fireball(S, cx - 32 * k - j * 4 * k, y + 1 * k, (3.2 - j * 0.6) * k, seed=j + int(phase * 10))
    L.over(S)


def tendril(L, x0, y0, x1, y1, phase, width=None, seed=0):
    """A whipping symbiote tendril from (x0, y0) to (x1, y1)."""
    S = Layer(L.w, L.h)
    width = width or 3.2 * U
    rng = random.Random(seed)
    pts = []
    for j in range(16):
        u = j / 15
        wob = math.sin(u * 6 + phase * 2 * math.pi + rng.uniform(0, 1)) * 5 * U * u * (1 - u) * 2
        nx, ny = -(y1 - y0), (x1 - x0)
        d = math.hypot(nx, ny) or 1
        pts.append((x0 + (x1 - x0) * u + nx / d * wob, y0 + (y1 - y0) * u + ny / d * wob))
    for j in range(len(pts) - 1):
        w = width * (1 - j / 18)
        S.line(pts[j][0], pts[j][1], pts[j + 1][0], pts[j + 1][1], SYMBIOTE, max(1, int(w)))
    tx, ty = pts[-1]
    a = math.degrees(math.atan2(-(ty - pts[-3][1]), tx - pts[-3][0]))
    for da in (-30, 30):
        fx._spike(S, tx, ty, a + da, 3 * U, 1.5 * U, SYMBIOTE)
    S.cel(2, 1, hi=1.6)
    S.outline(0.3, color='#2d2a44')
    L.over(S)


def notes(L, x, y, t, col='#ffffff'):
    """Floating music notes."""
    for j in range(3):
        u = (t + j / 3) % 1
        S = Layer(L.w, L.h)
        nx, ny = x + j * 5 * U + math.sin(u * 6) * 2 * U, y - u * 14 * U
        S.ellipse(nx, ny, 1.6 * U, 1.2 * U, col)
        S.line(nx + 1.4 * U, ny, nx + 1.4 * U, ny - 4.5 * U, col, 2)
        S.line(nx + 1.4 * U, ny - 4.5 * U, nx + 3.2 * U, ny - 3.5 * U, col, 2)
        S.outline(0.3, color='#2b2b3a')
        L.over(S, opacity=min(1, (1 - u) * 1.8))


def say(S, text, x, y):
    """Speech bubble clamped inside the stage (fx.speech bubbles are about 4.5px per letter at this scale)."""
    from engine import text_width
    w = (text_width(text) + 6) * max(2, round(U * 0.65))
    fx.speech(S, text, int(min(max(2, x), S.w - w - 2)), int(max(2, y)))


# ======================================================================= moves
UP_R = {'R': (168, 8), 'L': (-25, 30)}
SWING_LEGS = {'R': (35, -70), 'L': (10, -40)}


def web_swing(ch):
    """Thwip up to an anchor, swing in two arcs and land. The pet travels while it plays."""
    from anims import Anim
    sw, sh = st(1.5), st(1.5)
    frames = []
    for i in range(24):
        if i < 4 or i >= 21:
            pose = Pose(view='side', arms=UP_R if i >= 2 and i < 4 else None, legs={'R': (30, -60), 'L': (10, -40)},
                        eyes='focus')
            lift, anchor = 0, None
        else:
            s = ((i - 4) % 8) / 8
            lift = math.sin(math.pi * min(1, s * 1.1)) * 30 * U
            ax = sw * (0.95 - s * 0.9)
            anchor = (ax, 2)
            pose = Pose(view='side', arms=UP_R, legs=SWING_LEGS, lean=2, eyes='happy' if s > 0.4 else 'wide',
                        phase=s)

        def front(S, I, i=i, anchor=anchor):
            hx, hy = I['handR']
            if 2 <= i < 4:
                top = (hx + (sw - hx) * seg(i, 2, 4), hy - (hy - 2) * seg(i, 1, 4))
                web_line(S, hx, hy, *top)
                if i == 2:
                    say(S, 'THWIP!', int(hx - 10 * U), int(hy - 26 * U))
            if anchor:
                web_line(S, hx, hy, anchor[0], anchor[1])
            if i >= 21:
                fx.dust(S, I['origin'][0] + BASE / 2, I['ground'], seg(i, 21, 24), 10 * U)

        frames.append(_compose(ch, pose, sw, sh, dy=-lift, front=front))
    return Anim('web_swing', frames, moving=True, label='Web Swing')


def web_shot(ch):
    from anims import Anim
    sw = st(2.5)
    frames = []
    for i in range(24):
        aim = i >= 3
        pose = Pose(view='side', arms={'R': (90, 0), 'L': (-20, 30)} if aim else None,
                    legs={'R': (22, -4), 'L': (-18, 0)}, eyes='focus' if aim else None)

        def front(S, I, i=i):
            hx, hy = I['handR']
            if 4 <= i < 6:
                say(S, 'THWIP!', int(hx - 6 * U), int(hy - 30 * U))
            if 4 <= i < 11:
                t = seg(i, 4, 11)
                bx = hx + (sw - 18 * U - hx) * ease_out(t)
                web_line(S, hx, hy, bx, hy + 2 * U * t, sag=2 * U)
                S.disc(bx, hy + 2 * U * t, 2.2 * U, '#ffffff')
            if i >= 11:
                web_splat(S, sw - 18 * U, hy + 2 * U, 13 * U * ease_out(seg(i, 11, 14)),
                          opacity=1 - seg(i, 19, 24))

        frames.append(_compose(ch, pose, sw, front=front))
    return Anim('web_shot', frames, label='Web Shooter')


def venom_strike(ch):
    from anims import Anim
    sw = st(2)
    frames = []
    for i in range(24):
        if i < 8:
            pose = Pose(view='side', arms={'R': (40, 60, 'fist'), 'L': (30, 70, 'fist')}, legs={'R': (55, -95), 'L': (15, -75)},
                        eyes='angry', lean=3)
            dx = 0
        elif i < 18:
            pose = Pose(view='side', arms={'R': (90, 0, 'fist'), 'L': (-30, 60, 'fist')}, legs={'R': (45, -45), 'L': (-35, -10)},
                        eyes='angry', lean=5)
            dx = 18 * U * ease_out(seg(i, 8, 11))
        else:
            pose = Pose(view='side', eyes='happy')
            dx = 18 * U * (1 - ease_in_out(seg(i, 18, 23)))

        def front(S, I, i=i):
            hx, hy = I['handR']
            if i < 18:
                fx.lightning(S, hx, hy, (8 + (4 if i >= 8 else 0)) * U, seed=i, bolts=6,
                             core='#fffbe0', glow='#ffd23a', halo=(255, 220, 90, 255))
            if 10 <= i < 16:
                fx.burst(S, hx + 8 * U, hy, 16 * U, seg(i, 10, 16), inner='#fffbe0', outer='#ffd23a')
            if 10 <= i < 13:
                say(S, 'ZAP!', int(hx), int(hy - 30 * U))

        frames.append(_compose(ch, pose, sw, dx=dx, front=front))
    return Anim('venom_strike', frames, label='Venom Strike')


def camouflage(ch):
    from anims import Anim
    frames = []
    for i in range(22):
        t = seg(i, 3, 8) * (1 - seg(i, 15, 20))
        pose = Pose(arms={'L': (-15, 139, 'fist'), 'R': (15, -139, 'fist')} if i < 4 else None,
                    eyes='focus' if i < 4 else ('happy' if i >= 19 else None))

        def front(S, I, i=i, t=t):
            if 0.05 < t < 0.95 or 8 <= i < 15:
                rng = random.Random(i)
                for _ in range(10):
                    x = I['origin'][0] + BASE / 2 + rng.uniform(-14, 14) * U
                    y = I['ground'] - rng.uniform(4, 44) * U
                    S.disc(x, y, 0.7 * U, '#bfe8ff')

        frames.append(_compose(ch, pose, opacity=1 - 0.88 * t, front=front))
    return Anim('camouflage', frames, label='Camouflage')


def vibing(ch, sticks=False):
    """Idle: headphones on and nodding along (Miles), or air-drumming with sticks (Gwen)."""
    from anims import Anim
    frames = []
    for i in range(16):
        b = i % 4 < 2
        if sticks:
            up = i % 2 == 0
            arms = {'L': (-40 if up else -20, 120 if up else 70), 'R': (20 if up else 40, -70 if up else -120)}
        else:
            arms = {'L': (-20, 140), 'R': (20, -140)}
        pose = Pose(arms=arms, hy=1 if b else 0, eyes='happy' if i % 8 < 5 else None, phase=i / 16,
                    arms_over_head=not sticks)
        if not sticks:
            pose.reach = {'L': ('face', 0.75), 'R': ('face', 0.75)}

        def front(S, I, i=i):
            hx, hy = I['head']
            fw = I['face_w']
            if sticks:
                for side in ('L', 'R'):
                    x, y = I['hand' + side]
                    S.line(x, y, x + (-7 if side == 'L' else 7) * U, y - 6 * U, '#d8b07a', 2)
            else:
                band = Layer(S.w, S.h)
                band.ring(hx + fw / 2, hy + fw * 0.45, fw * 0.62, '#2b2b36', 2.2)
                band.clip(_above(band, hy + fw * 0.5))
                for x in (hx - 1.5 * U, hx + fw + 1.5 * U):
                    band.ellipse(x, hy + fw * 0.62, 2.4 * U, 3.2 * U, MILES_RED)
                band.outline(0.3)
                S.over(band)
            notes(S, hx + fw + 2 * U, hy + 2 * U, i / 16)

        frames.append(_compose(ch, pose, front=front))
    label = 'Drum Practice' if sticks else 'Headphones On'
    return Anim('drum_practice' if sticks else 'vibing', frames, loops=2, kind='idle', label=label)


def _above(layer, y):
    import numpy as np
    m = np.ones((layer.h, layer.w), bool)
    m[int(max(0, y)):] = False
    return m


def drum_practice(ch):
    return vibing(ch, sticks=True)


def tentacle_slam(ch):
    from anims import Anim
    sw = st(2)
    frames = []
    for i in range(24):
        if i < 8:
            r = ease_out(seg(i, 0, 7))
            tips = [(-10 - 6 * r, -30 - 20 * r), (0, -40 - 22 * r), (10, -38 - 22 * r), (-24, -6)]
            pose = Pose(view='side', tent=tips, eyes='angry', mouth='grin', lean=-1)
        elif i < 18:
            s = ease_out(seg(i, 8, 11))
            tips = (lambda g, s=s: [(30 + 22 * s, -40 + (g + 40) * s), (38 + 26 * s, -45 + (g + 45) * s),
                                    (24 + 18 * s, -40 + (g + 40) * s), (-24, -6)])
            pose = Pose(view='side', tent=tips, eyes='angry', mouth='shout', lean=3)
        else:
            pose = Pose(view='side', mouth='smirk')

        def front(S, I, i=i):
            g = I['ground']
            x = I['origin'][0] + BASE / 2 + 52 * U
            if 10 <= i < 20:
                fx.ground_impact(S, x, g, seg(i, 10, 20), size=0.9)
                fx.dust(S, x, g, seg(i, 10, 18), 14 * U)
            if 10 <= i < 13:
                say(S, 'SMASH!', int(x - 14 * U), int(g - 70 * U))

        frames.append(_compose(ch, pose, sw, front=front))
    return Anim('tentacle_slam', frames, label='Tentacle Slam')


def stage_tentacle(S, base, tip, out, k):
    """A tentacle drawn straight onto the stage (used when it reaches past the body's own canvas)."""
    T = Layer(S.w, S.h)
    (bx, by), (tx, ty) = base, tip
    p1, p2 = (bx + 14 * k * out, by + 6 * k), (tx - 4 * k * out, ty - 26 * k)
    n = max(19, int(math.hypot(tx - bx, ty - by) / (1.4 * k)))
    pts = []
    for j in range(n + 1):
        u = j / n
        pts.append(((1 - u) ** 3 * bx + 3 * (1 - u) ** 2 * u * p1[0] + 3 * (1 - u) * u * u * p2[0] + u ** 3 * tx,
                    (1 - u) ** 3 * by + 3 * (1 - u) ** 2 * u * p1[1] + 3 * (1 - u) * u * u * p2[1] + u ** 3 * ty))
    for j, (x, y) in enumerate(pts):
        r = (2.7 - 0.7 * j / n) * k
        T.ellipse(x, y, r, r, METAL if j % 2 else METAL_LO)
    for da in (-50, 0, 50):
        fx._spike(T, tx, ty, -90 + da, 4 * k, 2 * k, METAL_LO)
    T.cel(2, 1)
    T.outline(0.3)
    S.over(T)


def tentacle_rise(ch):
    """Two arms plant on the ground and lift him up; the other two wave."""
    from anims import Anim
    sh = st(1.8)
    frames = []
    for i in range(28):
        h = 34 * U * ease_in_out(seg(i, 2, 10)) * (1 - ease_in_out(seg(i, 20, 27)))
        wave = math.sin(i / 3) * 6
        pose = Pose(tent=[(14, -34 + wave), (30, -18 - wave)], legs={'L': (-8, 15), 'R': (8, -15)},
                    mouth='grin' if h > 10 else 'smirk', arms={'L': (-35, 104), 'R': (35, -104)}, phase=i / 28)

        def behind(S, I, h=h):
            hx, hy = I['hip']
            k = I['scale']
            for out, dx in ((-1, 26), (1, 16)):
                stage_tentacle(S, (hx + out * 6 * k, hy - 8 * k), (hx + out * dx * k * 1.6, I['ground'] - 1), out, k)

        def front(S, I, i=i):
            if 12 <= i < 18:
                say(S, 'HAHA!', int(I['head'][0] + I['face_w'] + 4), int(I['head'][1] - 10 * U))

        frames.append(_compose(ch, pose, sh=sh, dy=-h, behind=behind, front=front))
    return Anim('tentacle_rise', frames, label='Rise of the Arms')


def pumpkin_bomb(ch):
    from anims import Anim
    sw = st(2.5)
    frames = []
    land = sw - 30 * U
    for i in range(26):
        if i < 6:
            pose = Pose(view='side', arms={'R': (-40, 20, 'fist'), 'L': (-15, 20)}, eyes='angry', mouth='grin')
        elif i < 9:
            pose = Pose(view='side', arms={'R': (95, -10)}, eyes='angry', mouth='open', lean=3)
        else:
            pose = Pose(view='side', arms={'R': (-35, 104), 'L': (35, -104)}, mouth='grin', eyes='happy')

        def front(S, I, i=i):
            hx, hy = I['handR']
            g = I['ground']
            if i < 7:
                pumpkin(S, hx + 1 * U, hy - 1 * U, 3 * U, glow=i % 2)
            elif i < 15:
                t = seg(i, 7, 15)
                x = hx + (land - hx) * t
                y = hy + (g - 6 * U - hy) * t - math.sin(math.pi * t) * 14 * U
                pumpkin(S, x, y, 3 * U, glow=i % 2)
            if 15 <= i < 25:
                t = seg(i, 15, 25)
                fx.fireball(S, land, g - 16 * U, 18 * U * ease_out(min(1, t * 2)) * (1 - t * 0.4), seed=i)
                fx.smoke_puff(S, land, g - 14 * U, t, 26 * U, seed=7)
                say(S, 'HAHAHA!', int(I['head'][0] - 10 * U), int(I['head'][1] - 22 * U))

        frames.append(_compose(ch, pose, sw, front=front))
    return Anim('pumpkin_bomb', frames, label='Pumpkin Bomb')


def goblin_glider(ch):
    from anims import Anim
    sh = st(1.8)
    frames = []
    for i in range(28):
        rise = 26 * U * ease_out(seg(i, 3, 9)) * (1 - ease_in_out(seg(i, 22, 27)))
        bob = math.sin(i / 2) * 1.5 * U if 9 <= i < 22 else 0
        lift = rise + bob + (7 * U if i >= 2 else 0)
        pose = Pose(view='side', legs={'R': (25, -40), 'L': (-15, -20)},
                    arms={'R': (60, 40), 'L': (-30, 40)}, mouth='grin', eyes='angry', lean=2)

        def front(S, I, i=i, lift=lift):
            cx = I['origin'][0] + BASE / 2
            if i >= 2:
                glider(S, cx + 2 * U, I['ground'] - lift + 2 * U, i / 6, flame=3 <= i < 25)
            if i < 4:
                fx.smoke_puff(S, cx, I['ground'] - 8 * U, seg(i, 0, 4), 18 * U, seed=3)
            if 12 <= i < 16:
                say(S, 'HAHAHA!', int(I['head'][0] + I['face_w']), int(I['head'][1] - 14 * U))

        frames.append(_compose(ch, pose, sh=sh, dy=-lift, front=front))
    return Anim('goblin_glider', frames, moving=True, label='Goblin Glider')


def cackle(ch):
    from anims import Anim
    frames = []
    for i in range(16):
        pose = Pose(arms={'L': (-35, 104), 'R': (35, -104)}, hy=i % 2, mouth='open' if i % 4 < 2 else 'grin',
                    eyes='happy' if i % 8 < 4 else 'angry', lean=0.5 * (i % 2))

        def front(S, I, i=i):
            if i % 8 < 6:
                say(S, 'HAHA' if i % 8 < 3 else 'HAHAHA', int(I['head'][0] + I['face_w'] - 4),
                          int(I['head'][1] - 12 * U - (i % 2) * U))

        frames.append(_compose(ch, pose, sh=st(1.25), front=front))
    return Anim('cackle', frames, loops=2, kind='idle', label='Evil Cackle')


def symbiote_lash(ch):
    from anims import Anim
    sw = st(2.5)
    frames = []
    for i in range(24):
        pose = Pose(view='side', arms={'R': (80, 10), 'L': (60, 30)} if 4 <= i < 18 else None,
                    legs={'R': (45, -45), 'L': (-35, -10)} if 4 <= i < 18 else None,
                    mouth='shout' if 4 <= i < 18 else 'grin', lean=3 if 4 <= i < 18 else 0)

        def front(S, I, i=i):
            cx, cy = I['chest']
            reach = 70 * U * ease_out(seg(i, 3, 9)) * (1 - ease_in_out(seg(i, 16, 22)))
            if reach > 2:
                for k, dy in enumerate((-18, -6, 6, 16)):
                    tendril(S, cx, cy + dy * 0.4 * U, cx + reach * (1 - k * 0.08), cy + dy * U, i / 6 + k * 0.3,
                            seed=k)
            if 9 <= i < 13:
                say(S, 'RAAH!', int(I['head'][0] - 4 * U), int(I['head'][1] - 26 * U))

        frames.append(_compose(ch, pose, sw, front=front))
    return Anim('symbiote_lash', frames, label='Symbiote Lash')


def we_are_venom(ch):
    from anims import Anim
    sw = st(1.8)
    frames = []
    for i in range(24):
        on = 3 <= i < 21
        pose = Pose(arms={'L': (-115, -25), 'R': (115, 25)} if on else None, mouth='shout' if on else 'grin',
                    hy=-(i % 2) if on else 0)

        def front(S, I, i=i):
            if 5 <= i < 20:
                say(S, 'WE ARE VENOM!', int(I['origin'][0] + BASE * 0.42), 2)

        frames.append(_compose(ch, pose, sw, aura=('#3b2a66', 0.9, i / 24) if on else None, front=front))
    return Anim('we_are_venom', frames, label='We Are Venom')


MOVES = {
    'web_swing': web_swing, 'web_shot': web_shot, 'venom_strike': venom_strike, 'camouflage': camouflage,
    'vibing': vibing, 'drum_practice': drum_practice, 'tentacle_slam': tentacle_slam,
    'tentacle_rise': tentacle_rise, 'pumpkin_bomb': pumpkin_bomb, 'goblin_glider': goblin_glider,
    'cackle': cackle, 'symbiote_lash': symbiote_lash, 'we_are_venom': we_are_venom,
}


def st(k):
    return int(round(BASE * k))


def _compose(ch, pose, sw=BASE, sh=BASE, **kw):
    from anims import compose
    return compose(ch, pose, sw, sh, **kw)
