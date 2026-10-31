"""Full-length anime ninja sprite rig (v3).

Characters are drawn from scratch every frame on a 192x192 canvas, feet on the
bottom row, about 170-185px tall. Poses are joint angles; the rig places the
limbs, keeps the feet on the ground, and draws every part on its own layer with
cel shading, outlines and cast shadows before compositing. Side view is real:
'side' poses turn the head, body and limbs to face +x.

Local coordinate systems handed to character specs (via Ctx):
  hair / headgear : the 16x15 face grid (x 0..15, y 0..14; eyes ~row 8, mouth
                    ~row 12). Scaled to the real face automatically.
  face marks      : the 18x21 face grid (eyes rows 10-13, mouth row 17, chin 20).
  torso / collar  : origin at the middle of the shoulder line, y down, in the
                    base build units (waist ~y 21, hips y = t.b['torso'] ~28);
                    scaled per character automatically.
Angles: 0 = limb straight down, +90 = pointing toward +x (screen right /
facing direction in side view)."""

import math
from pathlib import Path

from PIL import Image

from engine import Layer, mix, scale

ART = Path(__file__).resolve().parents[2] / 'art'
W = H = 192
GROUND = H - 1
UNIT = W / 48             # one pixel of the original 48px sprites; effects scale with it
RIG = 1.5                 # rig scale over the base build units
INK = '#1d1626'
SANDAL = '#2c3a6e'

BUILDS = {
    'male':   dict(sh=11.0, chest=11.0, waist=9.0, hip=10.0, torso=28, neck=5,
                   arm=(6.0, 5.0, 4.0), upper=18, fore=16, leg=(9.0, 7.0, 5.0), hipx=4.8,
                   thigh=26, shin=25),
    'female': dict(sh=9.5, chest=9.5, waist=7.0, hip=9.5, torso=27, neck=4,
                   arm=(5.0, 4.0, 3.4), upper=17, fore=15, leg=(8.0, 6.0, 4.4), hipx=4.4,
                   thigh=26, shin=25),
    'big':    dict(sh=15.0, chest=17.0, waist=17.0, hip=14.0, torso=29, neck=7,
                   arm=(8.0, 7.0, 5.5), upper=18, fore=15, leg=(11.0, 9.0, 6.5), hipx=6.5,
                   thigh=25, shin=25),
    'brawny': dict(sh=14.5, chest=14.5, waist=12.0, hip=12.5, torso=30, neck=6,
                   arm=(7.5, 6.5, 5.0), upper=19, fore=17, leg=(10.0, 8.0, 6.0), hipx=6.0,
                   thigh=27, shin=26),
}


def vdir(a):
    r = math.radians(a)
    return math.sin(r), math.cos(r)


def add(p, d, k=1.0):
    return (p[0] + d[0] * k, p[1] + d[1] * k)


def lerp(p, q, t):
    return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)


class Ctx:
    """Drawing helper bound to a layer, a local origin, a scale and an optional
    shear (leaning torso)."""

    def __init__(self, layer, ox, oy, view='front', pose=None, ch=None, sx=1.0, sy=None,
                 shear=0.0, strand=False):
        self.L, self.ox, self.oy, self.view, self.pose, self.ch = layer, ox, oy, view, pose, ch
        self.sx, self.sy = sx, (sx if sy is None else sy)
        self.shear, self.strand = shear, strand
        self.b = BUILDS[ch.build] if ch is not None and hasattr(ch, 'build') else BUILDS['male']

    @property
    def side(self):
        return self.view == 'side'

    def P(self, x, y):
        return (self.ox + x * self.sx + self.shear * y * self.sy, self.oy + y * self.sy)

    def put(self, x, y, c):
        px, py = self.P(x, y)
        self.L.put(px, py, c)

    def rect(self, x0, y0, x1, y1, c):
        self.poly([(x0, y0), (x1 + 1, y0), (x1 + 1, y1 + 1), (x0, y1 + 1)], c)

    def poly(self, pts, c):
        self.L.poly([self.P(x, y) for x, y in pts], c)

    def ellipse(self, cx, cy, rx, ry, c):
        px, py = self.P(cx, cy)
        self.L.ellipse(px, py, rx * self.sx, ry * self.sy, c)

    def line(self, x0, y0, x1, y1, c, w=1):
        a, b = self.P(x0, y0), self.P(x1, y1)
        self.L.line(a[0], a[1], b[0], b[1], c, w)

    def polyline(self, pts, c, w=1):
        self.L.polyline([self.P(x, y) for x, y in pts], c, w)

    def spike(self, bx, by, ang, length, width, c):
        """Triangle whose base is centred on (bx, by), pointing at `ang` degrees
        (0 = right, 90 = up). Hair contexts add a shadow strand down the spike."""
        a = math.radians(ang)
        dx, dy = math.cos(a), -math.sin(a)
        nx, ny = -dy, dx
        self.poly([(bx + nx * width / 2, by + ny * width / 2),
                   (bx + dx * length, by + dy * length),
                   (bx - nx * width / 2, by - ny * width / 2)], c)
        if self.strand and length > 3:
            off = width * 0.18
            sx, sy_ = (nx * off, ny * off) if nx >= 0 else (-nx * off, -ny * off)
            self.line(bx + dx * length * 0.25 + sx, by + dy * length * 0.25 + sy_,
                      bx + dx * length * 0.85 + sx * 0.4, by + dy * length * 0.85 + sy_ * 0.4,
                      scale(c, 0.72))

    def crown(self, cx, cy, spikes, c):
        for ang, length, width in spikes:
            self.spike(cx, cy, ang, length, width, c)


class Pose:
    def __init__(self, **kw):
        self.view = 'front'
        self.bx = self.by = 0          # whole-body offset in px (by < 0 = airborne)
        self.lean = 0                  # shoulders shift forward (base units)
        self.hx = self.hy = 0          # extra head offset (base units)
        self.eyes = None
        self.mouth = None
        self.brows = None              # None/'angry'/'worried'/'raised'/'soft'
        self.arms = None               # {'L': (shoulder_angle, elbow_bend[, hand]), 'R': ...}
        self.legs = None               # {'L': (hip_angle, knee_bend), 'R': ...}
        self.arms_over_head = False
        self.phase = 0.0
        self.blush = False
        self.lying = 0                 # rotate the finished body by this many degrees onto the ground
        self.reach = None              # {'R': (target, blend)}: solve the arm so the hand reaches a target.
                                       # target = 'mouth' | 'face' | 'chest' | 'belly' | (x, y) torso units
        self.under = []
        self.over = []
        self.__dict__.update(kw)


def default_limbs(view):
    if view == 'side':
        return ({'L': (-6, 14), 'R': (4, 12)}, {'L': (0, 0), 'R': (0, 0)})
    return ({'L': (-9, 7), 'R': (9, -7)}, {'L': (-3, 2), 'R': (3, -2)})


def capsule(L, p, q, w1, w2, c):
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy) or 1
    nx, ny = -dy / d, dx / d
    L.poly([(p[0] + nx * w1 / 2, p[1] + ny * w1 / 2), (q[0] + nx * w2 / 2, q[1] + ny * w2 / 2),
            (q[0] - nx * w2 / 2, q[1] - ny * w2 / 2), (p[0] - nx * w1 / 2, p[1] - ny * w1 / 2)], c)
    L.ellipse(p[0], p[1], w1 / 2, w1 / 2, c)
    L.ellipse(q[0], q[1], w2 / 2, w2 / 2, c)


def strap(L, p, q, w, c):
    """Flat band across a limb (no rounded caps)."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy) or 1
    nx, ny = -dy / d * w / 2, dx / d * w / 2
    L.poly([(p[0] + nx, p[1] + ny), (q[0] + nx, q[1] + ny), (q[0] - nx, q[1] - ny), (p[0] - nx, p[1] - ny)], c)


def bands(L, p, q, w, c, every=3.0, start=0.0, end=1.0):
    """Lines across a limb segment (bandage wraps, straps, mesh)."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy) or 1
    nx, ny = -dy / d, dx / d
    n = max(1, int(d * (end - start) / every))
    for i in range(n + 1):
        t = start + (end - start) * i / n
        cx, cy = p[0] + dx * t, p[1] + dy * t
        L.line(cx - nx * w / 2, cy - ny * w / 2, cx + nx * w / 2, cy + ny * w / 2, c)


def finish(L, right=2, bottom=0, outline=True):
    L.cel(right, bottom)
    if outline:
        L.outline(0.3)
    return L


def k_of(ch):
    return RIG * getattr(ch, 'size', 1.0)


def scaled_build(ch):
    k = k_of(ch)
    b = BUILDS[ch.build]
    out = {key: (tuple(v * k for v in val) if isinstance(val, tuple) else val * k)
           for key, val in b.items()}
    return out


def head_dims(ch):
    k = k_of(ch) * getattr(ch, 'head', 1.0)
    fw = max(16, round(18 * k))
    fh = round(fw * 21 / 18)
    return fw, fh


# --------------------------------------------------------------------- limbs
def solve_arm(ch, shoulder, target, side_key, view):
    """Two-bone IK: (shoulder_angle, elbow_bend) that puts the wrist on target,
    elbow pointing outward (front view) or down (side view)."""
    b = scaled_build(ch)
    l1, l2 = b['upper'], b['fore'] + 2.2 * k_of(ch)
    dx, dy = target[0] - shoulder[0], target[1] - shoulder[1]
    d = max(1e-3, min(math.hypot(dx, dy), l1 + l2 - 0.01, ))
    d = max(d, abs(l1 - l2) + 0.01)
    theta = math.atan2(dx, dy)
    alpha = math.acos(max(-1, min(1, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    best = None
    for sign in (1, -1):
        a1 = theta + sign * alpha
        ex, ey = shoulder[0] + l1 * math.sin(a1), shoulder[1] + l1 * math.cos(a1)
        a2 = math.atan2(target[0] - ex, target[1] - ey)
        if view == 'side':
            score = ey
        else:
            score = ex if side_key == 'R' else -ex
        if best is None or score > best[0]:
            best = (score, math.degrees(a1), math.degrees(a2 - a1))
    return best[1], best[2]


def arm_chain(ch, origin, spec):
    b = scaled_build(ch)
    e = add(origin, vdir(spec[0]), b['upper'])
    w = add(e, vdir(spec[0] + spec[1]), b['fore'])
    return origin, e, w, vdir(spec[0] + spec[1])


def arm_layer(ch, spec, origin, side_key, view):
    o, b, k = ch.outfit, scaled_build(ch), k_of(ch)
    s, e, w, d = arm_chain(ch, origin, spec)
    hand_kind = spec[2] if len(spec) > 2 else 'open'
    w0, w1, w2 = b['arm']
    L = Layer(W, H)
    skin = ch.skin
    capsule(L, s, e, w0, w1, skin)
    capsule(L, e, w, w1, w2, skin)
    sleeve = o.get('sleeve', 'long')
    scol = o.get('sleeve_color', o['top'])
    bag = o.get('baggy', 1.0) * k
    if sleeve in ('long', 'elbow', 'short', 'cap'):
        end = {'long': 1, 'elbow': 1, 'short': 0.7, 'cap': 0.38}[sleeve]
        capsule(L, s, lerp(s, e, end), w0 + bag, w1 + bag * (0.6 if end < 1 else 1), scol)
        if sleeve == 'long':
            cuff_end = lerp(e, w, 0.88)
            capsule(L, e, cuff_end, w1 + bag, w2 + bag * o.get('flare', 1.0), o.get('sleeve_lower', scol))
            if o.get('cuff'):
                capsule(L, lerp(e, w, 0.76), cuff_end, w2 + bag + 0.6, w2 + bag + 0.6, o['cuff'])
    if o.get('sleeve_top'):
        capsule(L, s, lerp(s, e, o.get('sleeve_top_len', 0.5)), w0 + bag + 0.6, w1 + bag, o['sleeve_top'])
    if o.get('spiral') and (view == 'side' or side_key == o.get('spiral_side', 'R')):
        c = lerp(s, e, 0.25)
        L.ellipse(c[0], c[1], 1.6 * k, 1.6 * k, o['spiral'])
        L.ellipse(c[0], c[1], 0.6 * k, 0.6 * k, scale(o['spiral'], 0.6))
    if o.get('arm_band') and o['arm_band'][0] == side_key and view == 'front':
        p0, p1 = lerp(s, e, 0.45), lerp(s, e, 0.7)
        capsule(L, p0, p1, w0 + bag + 0.8, w1 + bag + 0.8, o['arm_band'][1])
        mid = lerp(p0, p1, 0.5)
        L.rect(mid[0] - 1.5 * k, mid[1] - 1.2 * k, mid[0] + 1.2 * k, mid[1] + 1.2 * k, '#c3cad4')
    fore = o.get('forearm_' + side_key, o.get('forearm'))
    if fore:
        f0 = lerp(e, w, 0.15)
        capsule(L, f0, lerp(e, w, 0.95), w1 + 0.8, w2 + 0.8, fore)
        if o.get('forearm_wrap'):
            bands(L, f0, lerp(e, w, 0.95), w1 + 0.8, scale(fore, 0.8), 2.2 * k)
        if o.get('forearm_mesh'):
            bands(L, f0, lerp(e, w, 0.95), w1 + 0.8, scale(fore, 0.7), 1.2 * k)
    if o.get('elbow_pad'):
        L.ellipse(e[0], e[1], w1 / 2 + 0.8, w1 / 2 + 0.8, o['elbow_pad'])
    if o.get('mesh_wrist'):
        capsule(L, lerp(e, w, 0.7), lerp(e, w, 0.98), w2 + 0.8, w2 + 0.8, o['mesh_wrist'])
        bands(L, lerp(e, w, 0.7), lerp(e, w, 0.98), w2 + 0.8, scale(o['mesh_wrist'], 0.7), 1.2 * k)
    hand = o.get('gloves') or skin
    hc = add(w, d, 2.2 * k)
    hr = 1.7 * k
    if hand_kind == 'fist':
        L.ellipse(hc[0], hc[1], hr * 1.1, hr * 1.1, hand)
    else:
        L.ellipse(hc[0], hc[1], hr, hr * 1.15, hand)
        tip = add(hc, d, 1.5 * k)
        L.ellipse(tip[0], tip[1], hr * 0.8, hr * 0.8, hand)
        nx, ny = -d[1], d[0]
        thumb = (hc[0] + nx * hr * (1 if side_key == 'R' else -1) * 0.9, hc[1] + ny * hr * 0.9)
        L.ellipse(thumb[0], thumb[1], hr * 0.45, hr * 0.45, hand)
        if o.get('gloves') and o.get('fingerless', True):
            L.ellipse(tip[0], tip[1], hr * 0.6, hr * 0.6, skin)
    if o.get('glove_plate'):
        L.rect(hc[0] - k, hc[1] - k, hc[0] + 0.4 * k, hc[1] + 0.4 * k, o['glove_plate'])
    finish(L, right=2, bottom=1)
    return L, add(w, d, 2.6 * k)


def leg_chain(ch, origin, spec):
    b = scaled_build(ch)
    kn = add(origin, vdir(spec[0]), b['thigh'])
    an = add(kn, vdir(spec[0] + spec[1]), b['shin'])
    return origin, kn, an


def leg_layer(ch, spec, origin, view, side_key):
    o, b, k = ch.outfit, scaled_build(ch), k_of(ch)
    h, kn, an = leg_chain(ch, origin, spec)
    w0, w1, w2 = b['leg']
    L = Layer(W, H)
    skin = ch.skin
    capsule(L, h, kn, w0, w1, skin)
    capsule(L, kn, an, w1, w2, skin)
    plen = {'long': 0.97, 'capri': 0.8, 'knee': 0.58, 'shorts': 0.34, 'micro': 0.2,
            'none': 0.0}[o.get('pants_len', 'long')]
    pc = o['pants']
    bag = o.get('pants_baggy', 1.0) * k
    if plen > 0:
        if plen <= 0.5:
            capsule(L, h, lerp(h, kn, plen / 0.5), w0 + bag, w0 + bag - k, pc)
        else:
            capsule(L, h, kn, w0 + bag, w1 + bag, pc)
            capsule(L, kn, lerp(kn, an, (plen - 0.5) / 0.5), w1 + bag, w2 + bag + 0.6 * k, pc)
            if o.get('pants_cuff'):
                c0 = lerp(kn, an, (plen - 0.5) / 0.5 - 0.08)
                capsule(L, c0, lerp(kn, an, (plen - 0.5) / 0.5), w2 + bag + 0.8 * k, w2 + bag + 0.8 * k,
                        scale(pc, 0.85))
    if o.get('leg_mesh'):
        capsule(L, lerp(h, kn, 0.6), lerp(kn, an, 0.4), w1 + 0.6, w2 + 0.6, o['leg_mesh'])
        bands(L, lerp(h, kn, 0.6), lerp(kn, an, 0.4), w1 + 0.6, scale(o['leg_mesh'], 0.65), 1.3 * k)
    if o.get('thigh_wrap'):
        capsule(L, h, lerp(h, kn, 0.85), w0 + 0.4, w1 + 0.4, o['thigh_wrap'])
        bands(L, h, lerp(h, kn, 0.85), w0, scale(o['thigh_wrap'], 0.8), 2.4 * k)
    if o.get('holster') == side_key:
        wrap = o.get('holster_wrap', '#eeeae0')
        tw = w0 + bag + 0.8
        for t0 in (0.42, 0.62):
            strap(L, lerp(h, kn, t0), lerp(h, kn, t0 + 0.07), tw, wrap)
            strap(L, lerp(h, kn, t0 + 0.07), lerp(h, kn, t0 + 0.085), tw, scale(wrap, 0.75))
        hc = lerp(h, kn, 0.56)
        off = (-1 if (view == 'front' and side_key == 'L') else 1) * (tw / 2)
        L.rect(hc[0] + off - 1.4 * k, hc[1] - 3.2 * k, hc[0] + off + 1.0 * k, hc[1] + 3.2 * k,
               o.get('holster_color', '#25325e'))
    if o.get('boots'):
        b0 = lerp(kn, an, 0.06)
        capsule(L, b0, an, w1 + 1.2, w2 + 1.4, o['boots'])
        capsule(L, b0, lerp(kn, an, 0.12), w1 + 1.6, w1 + 1.4, scale(o['boots'], 1.25))
    elif o.get('shin'):
        s0 = lerp(kn, an, o.get('shin_from', 0.55))
        capsule(L, s0, an, w2 + 1.4, w2 + 1.0, o['shin'])
        if o.get('shin_wrap', True):
            bands(L, s0, an, w2 + 1.4, scale(o['shin'], 0.78), 2.2 * k)
    if o.get('mesh_ankle'):
        capsule(L, lerp(kn, an, 0.7), an, w2 + 1.0, w2 + 1.0, o['mesh_ankle'])
        bands(L, lerp(kn, an, 0.7), an, w2 + 1.0, scale(o['mesh_ankle'], 0.7), 1.3 * k)
    draw_foot(L, ch, an, view, k)
    finish(L, right=2)
    return L


def draw_foot(L, ch, an, view, k):
    o = ch.outfit
    ax, ay = an
    sandal = o.get('sandals', SANDAL)
    sole = scale(sandal, 0.65)
    boot = o.get('boots')
    top = boot or ch.skin
    fh = 4 * k
    if view == 'side':
        L.poly([(ax - 2.5 * k, ay - k), (ax + 2.5 * k, ay - k), (ax + 8 * k, ay + 2.6 * k),
                (ax + 8 * k, ay + fh - 0.5), (ax - 2.5 * k, ay + fh - 0.5)], top)
        if not boot:
            L.rect(ax - 2.5 * k, ay - k, ax + 2 * k, ay + k, sandal)
            L.line(ax + 2 * k, ay + k, ax + 5 * k, ay + 2 * k, sandal, 2)
        if o.get('heels'):
            L.rect(ax - 2.5 * k, ay + 2 * k, ax - k, ay + fh, sole)
        if o.get('geta'):
            L.rect(ax - 3 * k, ay + fh - 1.2 * k, ax + 8 * k, ay + fh, sole)
        L.rect(ax - 3 * k, ay + fh - 1, ax + 8 * k, ay + fh, sole)
    else:
        L.ellipse(ax, ay + 1.6 * k, 3.3 * k, 2.6 * k, top)
        if not boot:
            L.rect(ax - 3 * k, ay - k, ax + 3 * k, ay + k, sandal)
            for x in (-2, 0, 2):
                L.put(ax + x * k, ay + 3 * k, scale(ch.skin, 0.8))
        L.rect(ax - 3.5 * k, ay + fh - 1, ax + 3.5 * k, ay + fh, sole)


# ---------------------------------------------------------------------- torso
def torso_points(b, view):
    sh, ch_, wa, hp, T, n = b['sh'], b['chest'], b['waist'], b['hip'], b['torso'], b['neck'] / 2 + 1
    pts = [(-n, -2), (n, -2), (sh - 3, -0.5), (sh, 3), (ch_, 9), (wa, 21), (hp, T), (-hp, T),
           (-wa, 21), (-ch_, 9), (-sh, 3), (-sh + 3, -0.5)]
    if view == 'side':
        pts = [(x * 0.78 + (1.5 if x > 0 and 4 < y < 16 else 0), y) for x, y in pts]
    return pts


def shoulder_joints(b, view):
    if view == 'side':
        return {'L': (-3.5, 3.5), 'R': (2.5, 3.5)}
    return {'L': (-(b['sh'] - 2.5), 3.5), 'R': (b['sh'] - 2.5, 3.5)}


def hip_joints(b, view):
    if view == 'side':
        return {'L': (-2.0, b['torso'] - 3), 'R': (2.0, b['torso'] - 3)}
    return {'L': (-b['hipx'], b['torso'] - 3), 'R': (b['hipx'], b['torso'] - 3)}


def torso_layer(ch, pose, tx, ty):
    o, b, k = ch.outfit, BUILDS[ch.build], k_of(ch)
    L = Layer(W, H)
    shear = -pose.lean / b['torso'] if pose.lean else 0.0
    t = Ctx(L, tx + pose.lean * k, ty, pose.view, pose, ch, sx=k, shear=shear)
    side_k = 0.8 if pose.view == 'side' else 1.0
    nw = b['neck']
    t.rect(-nw / 2, -7, nw / 2 - 1, 1, ch.skin)
    t.rect(-nw / 2, -5, nw / 2 - 1, -4, scale(ch.skin, 0.8))
    t.poly(torso_points(b, pose.view), o['top'])
    if not o.get('long_top'):
        T = b['torso']
        t.poly([(-b['waist'] - 0.5, 22), (b['waist'] + 0.5, 22), (b['hip'], T), (-b['hip'], T)],
               o['pants'])
        if o.get('belt'):
            t.poly([(-b['waist'] - 0.5, 21), (b['waist'] + 0.5, 21), (b['waist'] + 0.8, 23),
                    (-b['waist'] - 0.8, 23)], o['belt'])
    if ch.torso:
        t.sx = k * side_k          # outfits are drawn front-on; squeeze them for the side view
        ch.torso(t)
    finish(L, right=round(5 * k) if pose.view == 'front' else round(4 * k))
    return L


# ----------------------------------------------------------------------- face
def face_points(fw, fh, view):
    if view == 'side':
        n = [(0.06, 0.18), (0.14, 0.05), (0.32, 0.0), (0.7, 0.0), (0.88, 0.05), (0.95, 0.2),
             (0.97, 0.5), (1.0, 0.64), (0.95, 0.74), (0.86, 0.86), (0.7, 0.97), (0.6, 1.0),
             (0.44, 0.94), (0.2, 0.78), (0.06, 0.55)]
    else:
        n = [(0.05, 0.18), (0.12, 0.05), (0.3, 0.0), (0.7, 0.0), (0.88, 0.05), (0.95, 0.18),
             (0.96, 0.56), (0.86, 0.77), (0.64, 0.95), (0.5, 1.0), (0.36, 0.95), (0.14, 0.77),
             (0.04, 0.56)]
    return [(x * (fw - 1), y * (fh - 1)) for x, y in n]


def eye_boxes(fw, fh, view):
    """(cx, cy, w, h) for the screen-left and screen-right eyes."""
    ew, eh = fw * 0.22, fh * 0.15
    cy = fh * 0.6
    if view == 'side':
        return (fw * 0.5, cy, ew * 0.95, eh), (fw * 0.83, cy, ew * 0.6, eh)
    return (fw * 0.29, cy, ew, eh), (fw * 0.71, cy, ew, eh)


def draw_eye(L, box, style, iris, pupil, ch, mirror, special=None):
    cx, cy, ew, eh = box
    x0, x1 = cx - ew / 2, cx + ew / 2
    y0, y1 = cy - eh / 2, cy + eh / 2
    ink = INK
    if style in ('closed', 'sleepy'):
        L.line(x0, cy + eh * 0.15, x1, cy + eh * 0.15, ink, 1)
        L.put(x0 if not mirror else x1, cy, ink)
        return
    if style == 'happy':
        L.line(x0, cy + eh * 0.25, cx, cy - eh * 0.2, ink)
        L.line(cx, cy - eh * 0.2, x1, cy + eh * 0.25, ink)
        return
    if style == 'dot':
        L.ellipse(cx, cy, max(0.9, ew * 0.14), max(1.2, eh * 0.3), ink)
        return
    top = y0
    if style == 'half':
        top = y0 + eh * 0.35
    elif style == 'focus':
        top = y0 + eh * 0.25
    # white of the eye
    L.poly([(x0, top + 1), (x1, top), (x1 - ew * 0.05, y1), (x0 + ew * 0.1, y1)], '#fbf7f3')
    # iris
    ix = cx + (ew * 0.08 if not mirror else -ew * 0.08)
    irx, iry = max(1.2, ew * 0.3), max(1.6, eh * 0.48)
    L.ellipse(ix, cy + eh * 0.05, irx, iry, iris)
    L.ellipse(ix, cy - eh * 0.12, irx, iry * 0.55, scale(iris, 0.72))
    if special in ('sharingan', 'mangekyo'):
        L.ellipse(ix, cy + eh * 0.05, irx * 0.4, irx * 0.4, '#1a0303')
        for a in (0, 120, 240):
            r = math.radians(a)
            L.put(ix + math.cos(r) * irx * 0.7, cy + eh * 0.05 + math.sin(r) * iry * 0.6, '#1a0303')
    elif not ch.pale_eyes and special != 'byakugan':
        L.ellipse(ix, cy + eh * 0.08, irx * 0.45, iry * 0.45, pupil)
    L.put(ix - irx * 0.4, cy - eh * 0.15, '#ffffff')
    L.put(ix - irx * 0.4 + 1, cy - eh * 0.15, '#ffffff')
    L.put(ix + irx * 0.3, cy + eh * 0.3, mix(iris, '#ffffff', 0.5))
    # clip iris/white outside the lids by repainting lids
    lash_w = 2 if ew >= 5 else 1
    L.line(x0 - 0.5, top + 0.8, x1 + 0.5, top - 0.4, ink, lash_w)
    outer = (x0 - 0.8, top + 1.5) if not mirror else (x1 + 0.8, top + 0.6)
    L.put(*outer, ink)
    L.line(x0 + ew * 0.25, y1 + 0.5, x1 - ew * 0.1, y1 + 0.5, mix(ink, ch.skin, 0.45))


def face_layer(ch, pose, hx, hy, fw, fh):
    L = Layer(W, H)
    skin = ch.skin
    pts = [(hx + x, hy + y) for x, y in face_points(fw, fh, pose.view)]
    L.poly(pts, skin)
    ex = hx + (fw * 0.05 if pose.view == 'side' else 0)
    ey0, ey1 = hy + fh * 0.44, hy + fh * 0.64
    if pose.view == 'side':
        L.ellipse(hx + fw * 0.12, (ey0 + ey1) / 2, fw * 0.08, fh * 0.1, skin)
    else:
        L.ellipse(hx + 0.5, (ey0 + ey1) / 2, fw * 0.06, fh * 0.09, skin)
        L.ellipse(hx + fw - 1.5, (ey0 + ey1) / 2, fw * 0.06, fh * 0.09, skin)
    L.cel(right=max(2, round(fw * 0.1)), bottom=1, lo=0.86, hi=1.03)
    sh = scale(skin, 0.8)
    if pose.view == 'side':
        L.put(ex + fw * 0.13, (ey0 + ey1) / 2, sh)
        L.put(hx + fw * 0.95, hy + fh * 0.7, sh)
    else:
        L.put(hx + fw * 0.53, hy + fh * 0.72, sh)
        L.put(hx + fw * 0.53, hy + fh * 0.73 + 1, scale(skin, 0.9))
    L.outline(0.3)
    f = Ctx(L, hx, hy, pose.view, pose, ch, sx=fw / 18, sy=fh / 21)
    draw_brows(L, ch, pose, fw, fh, hx, hy)
    draw_eyes(L, ch, pose, fw, fh, hx, hy)
    draw_mouth(L, ch, pose, fw, fh, hx, hy)
    if pose.blush:
        pink = mix(skin, '#ff6b7a', 0.45)
        for (bx, by, _, _) in eye_boxes(fw, fh, pose.view):
            L.rect(hx + bx - 1.5, hy + by + fh * 0.12, hx + bx + 1.5, hy + by + fh * 0.12, pink)
    if ch.marks:
        ch.marks(f)
    return L


def draw_brows(L, ch, pose, fw, fh, hx, hy):
    style = pose.brows or ch.brows
    if (pose.eyes or ch.eyes) == 'closed' and not pose.brows:
        style = 'soft'
    col = ch.brow_color
    for i, (cx, cy, ew, eh) in enumerate(eye_boxes(fw, fh, pose.view)):
        mirror = i == 1
        x0, x1 = hx + cx - ew * 0.55, hx + cx + ew * 0.55
        y = hy + cy - eh * 1.25
        inner_dy = {'angry': eh * 0.5, 'worried': -eh * 0.4, 'raised': -eh * 0.4, 'soft': 0.0}.get(style, 0.0)
        outer_dy = {'raised': -eh * 0.4}.get(style, eh * 0.15)
        if mirror:
            L.line(x0, y + inner_dy, x1, y + outer_dy, col)
        else:
            L.line(x0, y + outer_dy, x1, y + inner_dy, col)


def draw_eyes(L, ch, pose, fw, fh, hx, hy):
    style = pose.eyes or ch.eyes
    iris, special = ch.iris, None
    if style in ('sharingan', 'mangekyo', 'rinnegan', 'byakugan', 'sage'):
        special, style = style, 'open'
    sp_iris = {'sharingan': '#d81a1a', 'mangekyo': '#e01414', 'byakugan': '#e8e4f4',
               'sage': '#f2b51c', 'rinnegan': '#b9a6e6'}
    for i, box in enumerate(eye_boxes(fw, fh, pose.view)):
        mirror = i == 1
        sp = special
        if special == 'sharingan' and ch.one_sharingan and not mirror:
            sp = None
        col = sp_iris.get(sp, iris)
        pupil = scale(col, 0.35) if sp != 'sage' else '#20140a'
        b = (hx + box[0], hy + box[1], box[2], box[3])
        draw_eye(L, b, style, col, pupil, ch, mirror, sp)
        cx, cy, ew, eh = b
        if sp == 'byakugan':
            vein = '#a99cc6'
            for dx in (-ew * 0.7, ew * 0.7):
                L.line(cx + dx, cy - eh * 0.6, cx + dx * 1.15, cy + eh * 0.2, vein)
        if sp == 'sage':
            orange = '#e8752a'
            L.line(cx - ew * 0.7, cy - eh * 0.75, cx + ew * 0.7, cy - eh * 0.75, orange, 2)
    if special == 'sharingan' and ch.one_sharingan:
        cx, cy, ew, eh = eye_boxes(fw, fh, pose.view)[1]
        for y in (-eh * 1.6, -eh * 1.0, eh * 0.9, eh * 1.5):
            L.put(hx + cx, hy + cy + y, '#c99a8a')


def draw_mouth(L, ch, pose, fw, fh, hx, hy):
    m = pose.mouth or ch.mouth
    cx = hx + (fw * 0.5 if pose.view == 'front' else fw * 0.72)
    y = hy + fh * 0.82
    mw = fw * 0.14
    soft = mix(ch.skin, INK, 0.5)
    ink = mix(ch.skin, INK, 0.75)
    red = '#7a2630'
    if m == 'flat':
        L.line(cx - mw * 0.6, y, cx + mw * 0.6, y, soft)
    elif m == 'smile':
        L.line(cx - mw, y - 1, cx - mw * 0.4, y, ink)
        L.line(cx - mw * 0.4, y, cx + mw * 0.4, y, ink)
        L.line(cx + mw * 0.4, y, cx + mw, y - 1, ink)
    elif m == 'smirk':
        L.line(cx - mw * 0.4, y, cx + mw * 0.5, y, ink)
        L.line(cx + mw * 0.5, y, cx + mw, y - 1.2, ink)
    elif m == 'open':
        L.ellipse(cx, y + 1, mw * 0.55, mw * 0.5, red)
        L.line(cx - mw * 0.55, y, cx + mw * 0.55, y, ink)
    elif m == 'shout':
        L.poly([(cx - mw, y - 1), (cx + mw, y - 1), (cx + mw * 0.6, y + mw * 1.2), (cx - mw * 0.6, y + mw * 1.2)], red)
        L.line(cx - mw * 0.8, y - 1, cx + mw * 0.8, y - 1, '#ffffff')
        L.line(cx - mw * 0.4, y + mw * 1.0, cx + mw * 0.4, y + mw * 1.0, '#d8606a')
    elif m == 'grin':
        L.poly([(cx - mw * 1.2, y - 1.5), (cx + mw * 1.2, y - 1.5), (cx + mw * 0.8, y + 1.5), (cx - mw * 0.8, y + 1.5)],
               '#ffffff')
        L.line(cx - mw * 1.2, y - 1.5, cx + mw * 1.2, y - 1.5, ink)
        L.line(cx - mw * 0.8, y + 1.5, cx + mw * 0.8, y + 1.5, ink)
    elif m == 'o':
        L.ellipse(cx, y + 0.5, mw * 0.35, mw * 0.4, red)
    elif m == 'chew':
        L.line(cx - mw * 0.7, y, cx + mw * 0.7, y, ink)
        L.put(cx - mw * 0.7, y + 1, soft)
        L.put(cx + mw * 0.7, y + 1, soft)


# --------------------------------------------------------------------- render
def lowest_point(ch, legs, hips):
    b = scaled_build(ch)
    low = -1e9
    for side in 'LR':
        h, kn, an = leg_chain(ch, hips[side], legs[side])
        low = max(low, an[1] + 4 * k_of(ch), kn[1] + b['leg'][1] / 2, h[1] + b['leg'][0] / 2)
    return low


def render(ch, pose=None):
    """Return (layer, info). info holds absolute anchor points for effects."""
    pose = pose or Pose()
    if pose.lying:
        return render_lying(ch, pose)
    view = pose.view
    b, k = BUILDS[ch.build], k_of(ch)
    arms_d, legs_d = default_limbs(view)
    arms = dict(arms_d, **(pose.arms or {}))
    legs = dict(legs_d, **(pose.legs or {}))
    sj = {key: (x * k, y * k) for key, (x, y) in shoulder_joints(b, view).items()}
    hj = {key: (x * k, y * k) for key, (x, y) in hip_joints(b, view).items()}
    tx = W / 2 + pose.bx
    ty = GROUND - lowest_point(ch, legs, hj) + pose.by
    lean = pose.lean * k
    S = {key: (tx + v[0] + lean, ty + v[1]) for key, v in sj.items()}
    Hp = {key: (tx + v[0], ty + v[1]) for key, v in hj.items()}
    fw, fh = head_dims(ch)
    hx = round(tx + lean + pose.hx * k - fw / 2 + (fw * 0.08 if view == 'side' else 0))
    hy = round(ty + pose.hy * k - fh - 4 * k)
    if pose.reach:
        named = {'mouth': (hx + fw * (0.5 if view == 'front' else 0.75), hy + fh * 0.84),
                 'face': (hx + fw * 0.5, hy + fh * 0.6),
                 'chest': (tx + lean, ty + 9 * k), 'belly': (tx + lean, ty + 17 * k)}
        for side, (target, blend) in pose.reach.items():
            goal = named[target] if isinstance(target, str) else (tx + lean + target[0] * k, ty + target[1] * k)
            _, _, rest, _ = arm_chain(ch, S[side], arms[side])
            rest = arm_chain(ch, S[side], arms[side])[2]
            goal = lerp(rest, goal, blend)
            a1, bend = solve_arm(ch, S[side], goal, side, view)
            hand = arms[side][2] if len(arms[side]) > 2 else 'open'
            arms[side] = (a1, bend, hand)

    out = Layer(W, H)
    eyes = eye_boxes(fw, fh, view)
    info = {'head': (hx, hy), 'face_c': (hx + fw * (0.5 if view == 'front' else 0.65), hy + fh * 0.6),
            'eye': (hx + eyes[1][0], hy + eyes[1][1]),
            'mouth': (hx + fw * (0.5 if view == 'front' else 0.72), hy + fh * 0.82),
            'chest': (tx + lean, ty + 10 * k), 'hip': (tx, ty + b['torso'] * k), 'feet_y': GROUND,
            'shoulderR': S['R'], 'shoulderL': S['L'], 'scale': k, 'face_w': fw}
    arm_layers = {}
    for side in 'LR':
        al, tip = arm_layer(ch, arms[side], S[side], side, view)
        arm_layers[side] = al
        info['hand' + side] = tip
    for fn in pose.under:
        fn(out, info)
    if ch.back_item:
        bl = Layer(W, H)
        # items on the back sit behind the body: mirrored to the trailing side in side view
        ch.back_item(Ctx(bl, tx + lean, ty, view, pose, ch, sx=-k * 0.8 if view == 'side' else k, sy=k))
        out.over(finish(bl, right=3))
    hb, hf = Layer(W, H), Layer(W, H)
    shift = fw * 0.06 if view == 'side' else 0
    hs = (fw / 16, fh / 15)
    ch.hair(Ctx(hb, hx - shift, hy, view, pose, ch, sx=hs[0], sy=hs[1], strand=True),
            Ctx(hf, hx + shift, hy, view, pose, ch, sx=hs[0], sy=hs[1], strand=True))
    out.over(finish(hb, right=3, bottom=1))
    if view == 'side':
        out.over(arm_layers['L'])
    for side in 'LR':
        out.over(leg_layer(ch, legs[side], Hp[side], view, side))
    tl = torso_layer(ch, pose, tx, ty)
    out.cast_shadow(tl, 1, 2, 0.8)
    out.over(tl)
    front_arms = ['R'] if view == 'side' else ['L', 'R']

    def put_arms():
        for s_ in front_arms:
            out.cast_shadow(arm_layers[s_], 1, 1, 0.82)
            out.over(arm_layers[s_])

    if not pose.arms_over_head:
        put_arms()
    fl = face_layer(ch, pose, hx, hy, fw, fh)
    out.cast_shadow(fl, 0, 2, 0.75)
    out.over(fl)
    if ch.collar:
        cl = Layer(W, H)
        ch.collar(Ctx(cl, tx + lean, ty, view, pose, ch, sx=k * (0.8 if view == 'side' else 1), sy=k))
        out.over(finish(cl, right=3))
    finish(hf, right=3, bottom=1)
    out.cast_shadow(hf, 1, 2, 0.78)
    out.over(hf)
    if ch.headgear:
        g = Layer(W, H)
        ch.headgear(Ctx(g, hx + shift, hy, view, pose, ch, sx=hs[0], sy=hs[1]))
        g.cel(right=2, lo=0.82)
        g.outline(0.3)
        out.cast_shadow(g, 0, 1, 0.82)
        out.over(g)
    if pose.arms_over_head:
        put_arms()
    for fn in pose.over:
        fn(out, info)
    return out, info


def render_lying(ch, pose):
    """Render the pose upright, then rotate it so the character lies on the ground."""
    import numpy as np
    up = Pose(**{k_: v for k_, v in pose.__dict__.items() if k_ != 'lying'})
    up.lying = 0
    body, info = render(ch, up)
    img = body.image().convert('RGBa').rotate(pose.lying, expand=True, resample=Image.NEAREST)
    img = img.convert('RGBA')
    bb = img.getbbox()
    canvas = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    ox = W / 2 - (bb[0] + bb[2]) / 2
    oy = GROUND + 1 - bb[3]
    canvas.alpha_composite(img, (int(ox), int(oy)))
    # rotate anchors the same way
    cxo, cyo = body.w / 2, body.h / 2
    r = math.radians(-pose.lying)
    ex, ey = img.width / 2, img.height / 2

    def tr(p):
        dx, dy = p[0] - cxo, p[1] - cyo
        return (ex + dx * math.cos(r) - dy * math.sin(r) + ox, ey + dx * math.sin(r) + dy * math.cos(r) + oy)

    info = {k_: (tr(v) if isinstance(v, tuple) else v) for k_, v in info.items()}
    L = Layer(W, H)
    L.px = np.asarray(canvas).astype(np.float32).copy()
    return L, info


_HEIGHT = {}


def standing_height(ch):
    """Height in px of the character's neutral standing pose (for scaling drawings)."""
    if ch.id not in _HEIGHT:
        bb = render(ch, Pose())[0].bbox()
        _HEIGHT[ch.id] = bb[3] - bb[1] + 1
    return _HEIGHT[ch.id]
