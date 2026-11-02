"""More of the Naruto pack: Rock Lee, Might Guy and Pain, with their moves.
Same conventions as characters.py / anims.py; registers itself into the roster when imported."""

import math
import random

import effects as fx
from body import Pose, UNIT as U, W as BASE
from characters import Character, SKIN, SKIN_PALE, cap, flak_vest, headband, itachi_collar, itachi_torso, plate
from effects import ease_in_out, ease_out, seg
from engine import Layer, scale

GREEN = '#3f8f3c'
WARMER = '#f08a24'
BOWL = '#141418'


# ================================================================= shared bits
def bowl_cut(b, f, big=False):
    """The Lee / Guy bowl cut: glossy black helmet with straight bangs."""
    r = 9.4 if big else 9.0
    b.ellipse(7.5, 4.8, r, 7.6, BOWL)
    b.rect(-1.6, 4, 16.6, 10, BOWL)
    f.poly([(-1.2, 7.2), (-1.2, 1), (2, -2.6), (13, -2.6), (16.2, 1), (16.2, 7.2), (14.6, 7.2), (14.6, 3.4),
            (0.4, 3.4), (0.4, 7.2)], BOWL)
    f.line(1.5, -1.4, 6.5, -2.4, '#5a5a6a')                  # shine
    f.line(2.5, -0.6, 4.5, -1, '#8a8a9a')


def big_brows(f):
    """Bushy eyebrows (face grid 18x21)."""
    if f.side:
        f.rect(7.5, 6.4, 12, 8.0, BOWL)
        f.rect(13.5, 6.4, 16.6, 8.0, BOWL)
    else:
        f.rect(2.4, 6.2, 7.8, 8.1, BOWL)
        f.rect(10.2, 6.2, 15.6, 8.1, BOWL)


def belt_band(t, cloth='#c8322f'):
    """Forehead protector worn as a belt."""
    b = t.b
    t.rect(-b['waist'] - 0.5, 19.5, b['waist'] + 0.5, 22.5, cloth)
    plate(t, -5, 19.5, 10)


def lee_torso(t):
    t.line(0, -1, 0, 19, scale(GREEN, 0.75))                  # zip
    belt_band(t)


def guy_torso(t):
    flak_vest(t, '#4e7a3e')
    belt_band(t)


def pain_marks(f):
    """Piercings: studs down the nose and a pair under the lip."""
    stud = '#1a1a20'
    nose = (9 if not f.side else 15.4)
    for y in (11, 12.6, 14.2):
        f.ellipse(nose - 0.9, y, 0.45, 0.45, stud)
        f.ellipse(nose + 0.9, y, 0.45, 0.45, stud)
    for x in ((7.6, 10.4) if not f.side else (14.2, 16)):
        f.ellipse(x, 18.6, 0.45, 0.45, stud)


def pain_hair(b, f):
    hc = '#e8862e'
    b.ellipse(7.5, 4.5, 9, 7, hc)
    b.crown(7.5, 4, [(165, 12, 6), (140, 14, 6), (115, 15, 6), (90, 15, 6), (65, 15, 6), (40, 14, 6), (15, 12, 6)], hc)
    cap(f, hc, 3)
    for x, a in ((1, -60), (5, -75), (10, -105), (14, -120)):
        f.spike(x, 3, a, 4, 3, hc)


ROCK_LEE = Character(
    'rock_lee', 'Rock Lee', 'classic', SKIN, '#16161c', hair=lambda b, f: bowl_cut(b, f), marks=big_brows,
    outfit=dict(top=GREEN, pants=GREEN, sleeve='long', baggy=0.4, pants_baggy=0.5, forearm='#ece6da',
                forearm_wrap=True, shin=WARMER, shin_from=0.5, shin_wrap=False, sandals='#2b3a78'),
    torso=lee_torso, eyes='open', mouth='grin', brows='angry', brow_color=BOWL, color=GREEN, speed=0.85, size=0.9,
    head=1.08, hair_color=BOWL, jutsu=['leaf_hurricane', 'primary_lotus', 'nice_guy'],
    tagline='Taijutsu only. Hard work beats talent! The Springtime of Youth!')

MIGHT_GUY = Character(
    'might_guy', 'Might Guy', 'jonin', SKIN, '#16161c', hair=lambda b, f: bowl_cut(b, f, big=True), marks=big_brows,
    outfit=dict(top=GREEN, pants=GREEN, sleeve='long', baggy=0.5, pants_baggy=0.6, shin=WARMER, shin_from=0.5,
                shin_wrap=False, sandals='#2b3a78'),
    torso=guy_torso, eyes='open', mouth='grin', brow_color=BOWL, color='#2f7a30', speed=0.8, size=1.04,
    hair_color=BOWL, jutsu=['dynamic_entry', 'eight_gates', 'nice_guy'],
    tagline="Konoha's Sublime Green Beast of Prey. Kakashi's eternal rival.")

PAIN = Character(
    'pain', 'Pain', 'akatsuki', SKIN_PALE, '#b9a6e6', hair=pain_hair, marks=pain_marks,
    collar=itachi_collar, headgear=lambda c: headband(c, '#242735', y=0, slash=True),
    outfit=dict(top='#22242a', pants='#2c2e36', sleeve='long', baggy=2.8, flare=1.8, long_top=True,
                sandals='#22253a', sleeve_lower='#22242a'),
    torso=itachi_torso, eyes='rinnegan', mouth='flat', brows='angry', brow_color='#c06a22', color='#7a5bd0',
    speed=0.4, hair_color='#e8862e', jutsu=['shinra_tensei', 'chibaku_tensei'],
    tagline='Leader of the Akatsuki. Feel pain. Know pain.')

NEW = [ROCK_LEE, MIGHT_GUY, PAIN]


# ======================================================================== moves
def st(k):
    return int(round(BASE * k))


def _compose(ch, pose, sw=BASE, sh=BASE, **kw):
    from anims import compose
    return compose(ch, pose, sw, sh, **kw)


def say(S, text, x, y):
    from engine import text_width
    w = (text_width(text) + 6) * max(2, round(U * 0.65))
    fx.speech(S, text, int(min(max(2, x), S.w - w - 2)), int(max(2, y)))


def sparkle(S, x, y, r):
    """Four-point twinkle (the Nice Guy tooth shine)."""
    T = Layer(S.w, S.h)
    T.poly([(x, y - r), (x + r * 0.25, y), (x, y + r), (x - r * 0.25, y)], '#ffffff')
    T.poly([(x - r, y), (x, y - r * 0.25), (x + r, y), (x, y + r * 0.25)], '#ffffff')
    T.outline(0.3, color='#c8d8ff')
    S.over(T)


def wind_arcs(S, cx, cy, r, phase):
    for k in range(3):
        a0 = phase * 2 * math.pi + k * 2.1
        pts = [(cx + math.cos(a0 + j * 0.18) * (r + k * 3 * U), cy + math.sin(a0 + j * 0.18) * (r * 0.35 + k * U))
               for j in range(9)]
        T = Layer(S.w, S.h)
        T.polyline(pts, '#eaf6ff', 2)
        S.over(T, opacity=0.8)


def nice_guy(ch):
    from anims import Anim
    frames = []
    for i in range(16):
        on = i >= 3
        pose = Pose(arms={'R': (62, -32, 'fist'), 'L': (-35, 104)} if on else None, mouth='grin',
                    eyes='happy' if on else None, hy=-1 if on and i % 4 < 2 else 0)

        def front(S, I, i=i):
            if 5 <= i < 13:
                mx, my = I['mouth']
                sparkle(S, mx + 2 * U, my - 1 * U, (3 + (i % 3)) * U)
            if 6 <= i < 14:
                say(S, 'YOUTH!', int(I['head'][0] + I['face_w']), int(I['head'][1] - 14 * U))

        frames.append(_compose(ch, pose, sh=st(1.2), front=front))
    return Anim('nice_guy', frames, loops=2, kind='idle', label='Nice Guy Pose')


def leaf_hurricane(ch):
    from anims import Anim
    sw = st(2)
    frames = []
    for i in range(22):
        spin = 4 <= i < 16
        view = ('side' if (i // 2) % 2 == 0 else 'front') if spin else 'side'
        pose = Pose(view=view, eyes='angry', mouth='shout' if spin else 'flat', brows='angry',
                    legs={'R': (100, 0), 'L': (-10, -30)} if spin else {'R': (55, -95), 'L': (15, -75)},
                    arms={'R': (-60, 40, 'fist'), 'L': (60, -40, 'fist')} if spin else None)

        def front(S, I, i=i, spin=spin):
            cx = I['origin'][0] + BASE / 2
            if spin:
                wind_arcs(S, cx, I['hip'][1], 22 * U, i / 6)
                fx.dust(S, cx, I['ground'], ((i - 4) % 6) / 6, 14 * U, seed=i % 3)
            if 5 <= i < 13:
                say(S, 'KONOHA SENPU!', int(cx), int(I['head'][1] - 18 * U))

        frames.append(_compose(ch, pose, sw, dy=-6 * U if spin else 0, front=front))
    return Anim('leaf_hurricane', frames, label='Leaf Hurricane')


def primary_lotus(ch):
    from anims import Anim
    sh = st(1.9)
    frames = []
    for i in range(28):
        if i < 6:
            pose, lift = Pose(view='side', legs={'R': (55, -95), 'L': (15, -75)}, eyes='angry', brows='angry'), 0
        elif i < 20:
            t = seg(i, 6, 20)
            lift = 40 * U * math.sin(math.pi * min(1, t * 1.15))
            pose = Pose(view='side', lying=(i * 70) % 360, legs={'R': (5, 0), 'L': (-5, 0)},
                        arms={'R': (170, 0, 'fist'), 'L': (-170, 0, 'fist')}, eyes='angry', mouth='shout')
        else:
            pose, lift = Pose(view='side', legs={'R': (55, -95), 'L': (15, -75)}, mouth='grin'), 0

        def front(S, I, i=i):
            g, cx = I['ground'], I['origin'][0] + BASE / 2
            if 6 <= i < 20:
                for k in range(3):
                    S.line(cx - (6 + k * 5) * U, g - 60 * U - k * 8 * U, cx - (6 + k * 5) * U + 4 * U, g - 20 * U, '#ece6da', 2)
            if 18 <= i < 27:
                fx.ground_impact(S, cx, g, seg(i, 18, 27), size=0.8)
                fx.dust(S, cx, g, seg(i, 18, 26), 18 * U)
            if 19 <= i < 24:
                say(S, 'LOTUS!', int(cx - 10 * U), int(g - 70 * U))

        frames.append(_compose(ch, pose, sh=sh, dy=-lift, front=front))
    return Anim('primary_lotus', frames, label='Primary Lotus')


def dynamic_entry(ch):
    from anims import Anim
    frames = []
    for i in range(20):
        fly = 3 <= i < 17
        pose = Pose(view='side', legs={'R': (88, 0), 'L': (-30, -70)} if fly else {'R': (55, -95), 'L': (15, -75)},
                    arms={'R': (-40, 30, 'fist'), 'L': (40, 60, 'fist')} if fly else None,
                    eyes='angry', brows='angry', mouth='shout' if fly else 'grin', lean=-3 if fly else 0)

        def front(S, I, i=i, fly=fly):
            o = I['origin'][0]
            if fly:
                fx.speed_lines(S, o, o + 50, [I['hip'][1] - k * 10 for k in range(6)])
            if 4 <= i < 12:
                say(S, 'DYNAMIC ENTRY!', int(o + 20), int(I['head'][1] - 16 * U))

        frames.append(_compose(ch, pose, sh=st(1.3), dy=-10 * U if fly else 0, front=front))
    return Anim('dynamic_entry', frames, moving=True, label='Dynamic Entry!')


def eight_gates(ch):
    from anims import Anim
    sw = st(1.6)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(28):
        red = i >= 14
        pose = Pose(arms={'L': (-30, 60, 'fist'), 'R': (30, -60, 'fist')}, legs={'L': (-14, 10), 'R': (14, -10)},
                    eyes='angry' if i > 3 else 'closed', brows='angry', mouth='shout' if i > 6 else 'flat', hy=i % 2)
        col = '#e0302a' if red else '#5fdc6a'

        def front(S, I, i=i):
            cx = I['origin'][0] + BASE / 2
            if i > 4:
                for k in range(3):
                    fx.smoke_puff(S, cx + (k - 1) * 14 * U, I['head'][1] - 8 * U, ((i + k * 3) % 9) / 9, 9 * U, seed=k)
            if 8 <= i < 15:
                say(S, 'GATE OPEN!', int(cx - 20 * U), 4)
            if 16 <= i < 24:
                say(S, 'EIGHT GATES!', int(cx - 24 * U), 4)

        frames.append(_compose(ch, pose, sw, st(1.3), ax=ax, front=front,
                               aura=(col, min(1.0, 0.4 + i / 20), i / 28)))
    return Anim('eight_gates', frames, anchor_x=ax, label='Eight Gates')


def shinra_tensei(ch):
    from anims import Anim
    sw = st(2.6)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(24):
        push = i >= 6
        pose = Pose(arms={'R': (115, -15), 'L': (-25, 30)} if push else {'R': (40, 40), 'L': (-25, 30)},
                    eyes='rinnegan', brows='angry', mouth='open' if 4 <= i < 9 else 'flat')

        def front(S, I, i=i):
            cx, cy = sw / 2, I['chest'][1]
            if i >= 6:
                for k in range(3):
                    t = seg(i, 6 + k * 3, 18 + k * 3)
                    if 0 < t < 1:
                        R = Layer(S.w, S.h)
                        R.ring(cx, cy, 8 * U + t * 120 * U, '#efe8ff', 2 + 3 * (1 - t))
                        S.over(R, opacity=1 - t)
                fx.dust(S, cx - 50 * U, I['ground'], seg(i, 8, 20), 16 * U, seed=1)
                fx.dust(S, cx + 50 * U, I['ground'], seg(i, 8, 20), 16 * U, seed=2)
            if 3 <= i < 10:
                say(S, 'SHINRA TENSEI', int(cx - 30 * U), 4)

        frames.append(_compose(ch, pose, sw, st(1.3), ax=ax, front=front,
                               aura=('#b9a6e6', 0.7, i / 24) if 5 <= i < 12 else None))
    return Anim('shinra_tensei', frames, anchor_x=ax, label='Shinra Tensei')


def chibaku_tensei(ch):
    from anims import Anim
    sw, sh = st(1.8), st(2.1)
    ax = (sw - BASE) // 2
    rng = random.Random(9)
    rocks = [(rng.uniform(-1, 1), rng.uniform(0.2, 1.0), rng.uniform(1.6, 3.4)) for _ in range(14)]
    frames = []
    for i in range(30):
        pose = Pose(arms={'R': (170, 5), 'L': (-25, 30)} if i >= 3 else None, eyes='rinnegan', brows='angry',
                    mouth='open' if 3 <= i < 8 else 'flat')

        def front(S, I, i=i):
            cx = sw / 2
            hx, hy = I['handR']
            if 3 <= i < 9:
                t = seg(i, 3, 9)
                S.disc(hx, hy - t * (hy - 40 * U), 2.5 * U, '#14101c')
            if i >= 9:
                oy = 16 * U
                r = (3 + 10 * ease_out(seg(i, 9, 26))) * U
                for rx, ry, rs in rocks:
                    t = seg(i, 9 + ry * 6, 22 + ry * 6)
                    x = cx + rx * sw * 0.45 * (1 - t)
                    y = I['ground'] - (I['ground'] - oy) * t
                    if t < 1:
                        S.disc(x, y, rs * U, '#7b6f66')
                S.disc(cx, oy, r, '#3a3440')
                S.disc(cx, oy, r * 0.7, '#14101c')
            if 10 <= i < 18:
                say(S, 'CHIBAKU TENSEI', int(cx - 32 * U), int(sh * 0.45))

        frames.append(_compose(ch, pose, sw, sh, ax=ax, front=front))
    return Anim('chibaku_tensei', frames, anchor_x=ax, label='Chibaku Tensei')


MOVES = {'nice_guy': nice_guy, 'leaf_hurricane': leaf_hurricane, 'primary_lotus': primary_lotus,
         'dynamic_entry': dynamic_entry, 'eight_gates': eight_gates, 'shinra_tensei': shinra_tensei,
         'chibaku_tensei': chibaku_tensei}

# Join the roster right after Itachi (Naruto pack), before the Spider-Man pack.
import characters as _roster  # noqa: E402
for _c in reversed(NEW):
    if _c.id not in _roster.BY_ID:
        _roster.CHARACTERS.insert(_roster.CHARACTERS.index(_roster.BY_ID['itachi']) + 1, _c)
        _roster.BY_ID[_c.id] = _c
