"""Animation builders. Each returns an Anim: a list of frames plus metadata.

Base frames are 128x128. Jutsu that need room render onto a larger stage; the
character keeps its 128x128 footprint at (anchor_x, stage_h - 128), so a player
can line the stage up with the walking sprite (Pet Therapy's `size` field).

Poses are joint angles (see body.py): 0 = limb straight down, +90 = pointing
toward +x. Distances below are written as multiples of U, one pixel of the old
48px sprites, so timing and spacing carried over from v1."""

import math
import random

import effects as fx
from body import Pose, UNIT as U, W as BASE, render
from effects import ease_in_out, ease_out, seg
from engine import Layer


class Anim:
    def __init__(self, id, frames, loops=1, moving=False, anchor_x=0, label=None, kind='jutsu'):
        self.id, self.frames, self.loops, self.moving = id, frames, loops, moving
        self.anchor_x, self.label, self.kind = anchor_x, label or id.replace('_', ' ').title(), kind

    @property
    def size(self):
        return (self.frames[0].w / BASE, self.frames[0].h / BASE)


def st(k):
    """Stage size for a multiple of the base frame."""
    return int(round(BASE * k))


# ------------------------------------------------------------------ pose sets
SIGN_F = {'L': (-15, 139, 'fist'), 'R': (15, -139, 'fist')}
HIP_F = {'L': (-35, 104), 'R': (35, -104)}
PUMP_F = {'R': (160, 20, 'fist'), 'L': (-35, 104)}
FLAIL = [{'L': (-150, -20), 'R': (150, 20)}, {'L': (-125, -45), 'R': (125, 45)}]
SPREAD_F = {'L': (-115, -25), 'R': (115, 25)}
WIDE_F = {'L': (-10, 5), 'R': (10, -5)}

FWD_S = {'R': (90, 0), 'L': (75, 10)}
PALM_S = {'R': (40, 50), 'L': (-15, 20)}
UP_S = {'R': (172, 5), 'L': (-15, 20)}
LOW_S = {'R': (35, 35), 'L': (-30, 15)}
SLAM_S = {'R': (55, -5, 'fist'), 'L': (-35, 15)}
MOUTH_S = {'R': (60, 152, 'fist'), 'L': (55, 157, 'fist')}
PUNCH_S = {'R': (90, 0, 'fist'), 'L': (-30, 60, 'fist')}
SIGN_S = {'R': (30, 110, 'fist'), 'L': (40, 105, 'fist')}
TWO_FWD_S = {'R': (82, 4), 'L': (86, 0)}

CROUCH_S = {'R': (55, -95), 'L': (15, -75)}
LUNGE_S = {'R': (45, -45), 'L': (-35, -10)}
STANCE_S = {'R': (22, -4), 'L': (-18, 0)}
SIT_S = {'R': (88, 0), 'L': (92, 0)}

WALK_THIGH = [17, 12, 3, -7, -15, -9, 5, 14]
WALK_KNEE = [-4, -2, -2, -6, -16, -38, -30, -10]


def compose(ch, pose, sw=BASE, sh=BASE, ax=0, dx=0, dy=0, behind=None, front=None,
            opacity=1.0, scale_k=1.0, aura=None):
    """Render the character on a stage and run effect callbacks around it.
    Callbacks get (stage, info) with info anchors already in stage coords."""
    S = Layer(sw, sh)
    body, info = render(ch, pose)
    if scale_k != 1.0:
        big = body.scaled(scale_k)
        ox = ax + dx + BASE / 2 - big.w / 2
        oy = sh - big.h + dy
        body = big
        info = {k: ((v[0] * scale_k + ox, v[1] * scale_k + oy) if isinstance(v, tuple) else v)
                for k, v in info.items()}
    else:
        ox, oy = ax + dx, sh - BASE + dy
        info = {k: ((v[0] + ox, v[1] + oy) if isinstance(v, tuple) else v)
                for k, v in info.items()}
    info['ground'] = sh - 1
    info['origin'] = (ox, oy)
    if aura:
        mask = Layer(sw, sh)
        mask.over(body, int(ox), int(oy))
        fx.aura(S, mask, aura[0], aura[2] if len(aura) > 2 else 0, aura[1])
    if behind:
        behind(S, info)
    if opacity > 0:
        S.over(body, int(ox), int(oy), opacity)
    if front:
        front(S, info)
    return S


# ===================================================================== BASE
def front(ch):
    frames = []
    for i in range(16):
        b = 0.5 - 0.5 * math.cos(2 * math.pi * i / 16)
        eyes = 'closed' if i in (12, 13) else None
        arms = {'L': (-9 - b * 2, 7 + b * 3), 'R': (9 + b * 2, -7 - b * 3)}
        frames.append(compose(ch, Pose(hy=round(b), arms=arms, eyes=eyes, phase=i / 16)))
    return Anim('front', frames, loops=3, kind='base', label='Idle')


def walk_pose(i, **kw):
    r, l = i % 8, (i + 4) % 8
    return Pose(view='side', phase=i / 8,
                arms={'R': (-WALK_THIGH[r] * 1.1, 14 + max(0, WALK_THIGH[r]) * 0.6),
                      'L': (-WALK_THIGH[l] * 1.1, 14 + max(0, WALK_THIGH[l]) * 0.6)},
                legs={'R': (WALK_THIGH[r], WALK_KNEE[r]), 'L': (WALK_THIGH[l], WALK_KNEE[l])},
                lean=1, **kw)


def walk(ch):
    return Anim('walk', [compose(ch, walk_pose(i)) for i in range(8)], kind='base', label='Walk')


def drag(ch):
    frames = []
    for i in range(6):
        k = i % 2
        frames.append(compose(ch, Pose(eyes='wide', brows='worried', mouth='shout' if i % 3 == 0 else 'o',
                                       arms=FLAIL[k], phase=i / 6, by=-6 * U,
                                       legs={'L': (-10 + k * 8, 18 - k * 14), 'R': (10 - k * 8, -18 + k * 14)})))
    return Anim('drag', frames, kind='base', label='Drag')


def sleep(ch):
    """Lying down asleep: the side-view body curled a little and laid on the ground."""
    frames = []
    for i in range(16):
        b = 0.5 - 0.5 * math.cos(2 * math.pi * i / 16)
        pose = Pose(view='side', eyes='closed', mouth='o' if b > 0.6 else 'flat', lying=90,
                    arms={'R': (115 + b * 4, 40), 'L': (100, 45)},
                    legs={'R': (35, -55), 'L': (20, -30)})

        def front(S, I, i=i):
            fx.zzz(S, I['face_c'][0] + 2 * U, I['face_c'][1] - 10 * U, i / 16)

        frames.append(compose(ch, pose, front=front))
    return Anim('sleep', frames, loops=12, kind='base', label='Sleep')


SNACK_ID = {'ramen': 'ramen', 'chips': 'chips', 'tomato': 'tomato', 'dango': 'dango',
            'sake': 'sake', 'book': 'read', 'notebook': 'research', 'flower': 'flower',
            'cinnamon_roll': 'cinnamon_roll', 'shogi': 'shogi'}
SNACK_LABEL = {'ramen': 'Ichiraku Ramen', 'chips': 'Potato Chips', 'tomato': 'Tomato Snack',
               'dango': 'Dango Break', 'sake': 'Sake', 'book': 'Reading Icha Icha',
               'notebook': '"Research"', 'flower': 'Flower Shop',
               'cinnamon_roll': 'Cinnamon Roll', 'shogi': 'Shogi Strategy'}
HOLD_L = (-12, 115)                 # left forearm across the body, hand at the stomach
TO_MOUTH_R = (150, 132)             # elbow up and out, hand brought in to the mouth
LOW_R = (12, -40)


def snack(ch):
    """Eating for real: bowl/bag held at the belly, the other hand travels up to
    the mouth (IK), the mouth opens, chews, the hand goes back down."""
    item = ch.snack
    frames = []
    lift = [0.0, 0.3, 0.65, 1.0, 1.0, 1.0, 0.6, 0.25]
    for i in range(16):
        u = lift[i % 8]
        chewing = (i % 8) in (4, 5, 6, 7)
        pose = Pose(mouth='open' if i % 8 == 3 else ('chew' if chewing and i % 2 else None), phase=i / 16,
                    arms_over_head=u > 0.5 and item not in ('book', 'notebook', 'shogi'))
        draw = None
        if item in ('ramen', 'chips'):
            pose.arms = {'L': HOLD_L, 'R': LOW_R}
            pose.reach = {'L': ((-1, 17), 1.0), 'R': ('mouth', u)}
            draw = (lambda S, I, i=i: (
                fx.prop(S, item, I['handL'][0] + 2 * U, I['handL'][1], i),
                fx.prop(S, 'chopsticks' if item == 'ramen' else 'chip', I['handR'][0], I['handR'][1], i)))
        elif item == 'notebook':
            pose.arms = {'L': HOLD_L, 'R': LOW_R}
            pose.reach = {'L': ((-2, 15), 1.0), 'R': ((3 + (i % 3), 14 + (i % 2)), 1.0)}
            pose.eyes, pose.mouth, pose.blush = 'happy', 'grin', i % 8 < 4
            draw = (lambda S, I, i=i: fx.prop(S, item, I['handL'][0] + 2 * U, I['handL'][1], i))
        elif item == 'book':
            pose.arms = {'L': (-20, 140), 'R': (20, -140)}
            pose.reach = {'L': ((-4, -3), 1.0), 'R': ((4, -3), 1.0)}
            pose.arms_over_head = True
            pose.eyes = 'happy' if i % 8 >= 6 else 'half'
            pose.blush = i % 8 >= 6
            draw = (lambda S, I, i=i: fx.prop(S, 'book', (I['handL'][0] + I['handR'][0]) / 2, I['handL'][1] + 1, i))
        elif item == 'shogi':
            pose.arms = {'L': HOLD_L, 'R': LOW_R}
            pose.reach = {'L': ((-1, 14), 1.0), 'R': ('mouth', 0.9)}
            pose.eyes = 'half' if i < 12 else 'open'
            pose.mouth = 'flat' if i < 12 else 'smirk'
            draw = (lambda S, I, i=i: (fx.prop(S, 'shogi', I['handL'][0] + 2 * U, I['handL'][1], i),
                                       fx.speech(S, '!', int(I['head'][0] + I['face_w'] + 4), int(I['head'][1] - 6))
                                       if i >= 12 else None))
        else:
            pose.arms = {'R': LOW_R, 'L': (-9, 7)}
            pose.reach = {'R': ('mouth', u)}
            if item == 'sake':
                pose.blush = i >= 8
                pose.eyes = 'happy' if i >= 8 else None
            if item == 'flower':
                pose.eyes = 'happy' if u > 0.5 else None
                pose.mouth = 'smile'
            draw = (lambda S, I, i=i: fx.prop(S, item, I['handR'][0], I['handR'][1], i))
        frames.append(compose(ch, pose, front=draw))
    return Anim(SNACK_ID[item], frames, loops=2, kind='idle', label=SNACK_LABEL[item])


# ==================================================================== JUTSU
def shadow_clone(ch):
    sw = st(3)
    frames = []
    for i in range(24):
        sign = i < 5
        pose = Pose(arms=SIGN_F if sign else HIP_F, eyes='angry' if sign else 'happy',
                    brows='angry' if sign else None, mouth='shout' if sign else 'grin')
        clones = 6 <= i < 20

        def front(S, I, i=i, clones=clones):
            if clones:
                for k, x in enumerate((BASE, BASE * 2)):
                    arms = PUMP_F if k == 0 else HIP_F
                    c, _ = render(ch, Pose(arms=arms, hy=(i + k) % 4 < 2, mouth='grin', eyes='happy',
                                           legs=WIDE_F))
                    S.over(c, x, 0)
            for k, x in enumerate((BASE * 1.5, BASE * 2.5)):
                fx.smoke_puff(S, x, BASE * 0.6, seg(i, 4, 11), 24 * U, seed=k + 1)
                fx.smoke_puff(S, x, BASE * 0.6, seg(i, 18, 24), 24 * U, seed=k + 5)
            if 6 <= i < 9:
                fx.speech(S, 'POOF', int(BASE * 1.75), 4)

        frames.append(compose(ch, pose, sw, front=front))
    return Anim('shadow_clone', frames, label='Shadow Clone Jutsu')


def rasengan(ch):
    sw = st(2)
    frames = []
    for i in range(24):
        if i < 10:
            r = (1 + 4.5 * ease_out(seg(i, 0, 8))) * U
            pose = Pose(view='side', arms=PALM_S, legs=STANCE_S, eyes='focus' if i < 5 else 'angry',
                        brows='angry' if i >= 5 else None, mouth='flat' if i < 5 else 'shout')
            dx, off = 0, (1 * U, -4 * U)
        elif i < 20:
            dx = 24 * U * ease_out(seg(i, 10, 14))
            r = 5.5 * U
            pose = Pose(view='side', arms=FWD_S, legs=LUNGE_S, lean=4, eyes='angry', brows='angry',
                        mouth='shout')
            off = (3 * U, 0)
        else:
            dx = 24 * U * (1 - ease_in_out(seg(i, 19, 23)))
            r = 0
            pose = Pose(view='side', mouth='smile')
            off = (0, 0)

        def front(S, I, i=i, r=r, off=off):
            hx, hy = I['handR']
            if i < 14 and r:
                fx.rasengan(S, hx + off[0], hy + off[1], r, i / 6)
            if 10 <= i < 14:
                o = I['origin'][0]
                fx.speed_lines(S, o + 10, o + 40, [I['hip'][1] - k * 8 for k in range(5)])
            if 14 <= i < 20:
                fx.burst(S, hx + 8 * U, hy, 16 * U, seg(i, 14, 20))
                if i < 17:
                    fx.rasengan(S, hx + 5 * U, hy, (6 - (i - 14)) * U, i / 6)

        frames.append(compose(ch, pose, sw, dx=dx, front=front))
    return Anim('rasengan', frames, label='Rasengan')


def rasenshuriken(ch):
    sw, sh = st(2.5), st(1.5)
    frames = []
    for i in range(28):
        throw = i >= 12
        pose = Pose(view='side', arms=FWD_S if throw else UP_S, legs=STANCE_S,
                    eyes='sage' if i >= 4 else 'focus', mouth='shout' if 10 <= i < 15 else 'flat',
                    brows='angry' if i >= 4 else None)
        tx = sw * 0.75

        def front(S, I, i=i, throw=throw):
            hx, hy = I['handR']
            if not throw:
                r = (1.5 + 3.5 * ease_out(seg(i, 0, 6))) * U
                blade = 13 * U * ease_out(seg(i, 4, 11))
                cy = hy - 9 * U
                if blade > U:
                    fx.rasenshuriken(S, hx, cy, r, i / 3, blade)
                else:
                    fx.rasengan(S, hx, cy, r, i / 3)
            elif i < 17:
                t = seg(i, 12, 17)
                x = hx + (tx - hx) * ease_in_out(t)
                y = hy - 9 * U + (sh - 26 * U - (hy - 9 * U)) * t
                fx.rasenshuriken(S, x, y, 4.5 * U, i / 3, 12 * U)
                fx.speed_lines(S, x - 22 * U, x - 14 * U, (y - 4 * U, y, y + 4 * U))
            else:
                t = seg(i, 17, 28)
                fx.burst(S, tx, sh - 26 * U, 30 * U, t, inner='#f4fbff', outer='#8fd0ff', rays=16)
                if t < 0.5:
                    fx.rasenshuriken(S, tx, sh - 26 * U, 6 * U, i / 3, (16 + 20 * t) * U)

        frames.append(compose(ch, pose, sw, sh, front=front))
    return Anim('rasenshuriken', frames, label='Wind Style: Rasenshuriken')


def sage_mode(ch):
    sh = st(1.25)
    frames = []
    for i in range(24):
        strength = ease_out(seg(i, 0, 8)) * (1 - seg(i, 20, 24))
        pose = Pose(arms=SIGN_F if i < 8 else HIP_F, eyes='closed' if i < 8 else 'sage',
                    mouth='flat' if i < 8 else 'smirk', legs=WIDE_F)

        def front(S, I, i=i):
            if 8 <= i < 12:
                fx.speech(S, 'SAGE', I['head'][0] + 20, I['head'][1] - 16)

        frames.append(compose(ch, pose, BASE, sh, front=front,
                              aura=('#ffb43a', strength, i / 24) if strength > 0.05 else None))
    return Anim('sage_mode', frames, label='Sage Mode')


def chidori(ch, name='chidori', label='Chidori', eyes='sharingan'):
    sw = st(2.5)
    frames = []
    for i in range(24):
        if i < 10:
            dx = 0
            pose = Pose(view='side', arms=LOW_S, legs=CROUCH_S, eyes=eyes, brows='angry',
                        mouth='flat' if i < 6 else 'shout')
        elif i < 18:
            dx = 56 * U * ease_out(seg(i, 10, 14))
            pose = Pose(view='side', arms=FWD_S, legs=LUNGE_S, lean=5, eyes=eyes, brows='angry',
                        mouth='shout')
        else:
            dx = 56 * U * (1 - ease_in_out(seg(i, 18, 23)))
            pose = Pose(view='side', eyes=eyes)

        def front(S, I, i=i):
            hx, hy = I['handR']
            if i < 10:
                fx.lightning(S, hx + U, hy, (7 + 6 * ease_out(seg(i, 0, 6))) * U, seed=i * 7 + 1,
                             bolts=5 + i // 2)
            elif i < 14:
                fx.lightning(S, hx + 2 * U, hy, 12 * U, seed=i * 7 + 1, bolts=8, forward=True)
                o = I['origin'][0]
                fx.speed_lines(S, o + 6, o + 36, [I['hip'][1] - k * 9 for k in range(5)])
            elif i < 18:
                fx.burst(S, hx + 6 * U, hy, 14 * U, seg(i, 14, 18), inner='#ffffff', outer='#62c1ff')
                fx.lightning(S, hx + 6 * U, hy, 14 * U, seed=i * 3, bolts=9)

        frames.append(compose(ch, pose, sw, dx=dx, front=front))
    return Anim(name, frames, label=label)


def lightning_blade(ch):
    return chidori(ch, 'lightning_blade', 'Lightning Blade (Raikiri)', 'sharingan')


def fireball(ch):
    sw, sh = st(3), st(1.25)
    frames = []
    for i in range(24):
        pose = Pose(view='side', arms=MOUTH_S, arms_over_head=True, legs=STANCE_S,
                    eyes='closed' if i < 4 else 'sharingan', mouth='open' if i >= 5 else 'flat',
                    lean=-2 if i >= 5 else 0)

        def front(S, I, i=i):
            mx, my = I['mouth']
            if 5 <= i < 20:
                r = (3 + 15 * ease_out(seg(i, 5, 16))) * U
                fx.fireball(S, mx + 4 * U + r, my - r * 0.25, r, seed=i, trail=0.7)
            if i >= 18:
                t = seg(i, 18, 24)
                for k, x in enumerate((0.42, 0.56, 0.7)):
                    fx.smoke_puff(S, sw * x, my - 4 * U, t, 10 * U, seed=k + 9, light='#bfc2cc',
                                  dark='#8d919c', rim='#5c606b')

        frames.append(compose(ch, pose, sw, sh, front=front))
    return Anim('fireball', frames, label='Fire Style: Great Fireball')


def amaterasu(ch):
    sw = st(2.5)
    frames = []
    for i in range(26):
        pose = Pose(view='side', eyes='mangekyo', mouth='flat', brows='angry',
                    arms={'R': (85, -10), 'L': (-10, 20)} if 4 <= i < 22 else None)

        def front(S, I, i=i):
            if i >= 3:
                ex, ey = I['eye']
                S.rect(ex, ey + 3, ex, ey + 6, '#b0101a')
            if 6 <= i < 26:
                grow = ease_out(seg(i, 6, 12)) * (1 - seg(i, 22, 26))
                fx.flames(S, sw * 0.72, I['ground'], (8 + 26 * grow) * U, (4 + 26 * grow) * U, i / 6,
                          seed=11, pal=fx.BLACK_FIRE)

        frames.append(compose(ch, pose, sw, front=front))
    return Anim('amaterasu', frames, label='Amaterasu')


def susanoo(ch, col):
    sw = sh = st(2)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(28):
        t = ease_out(seg(i, 5, 14))
        fade = 1 - seg(i, 23, 28)
        pose = Pose(eyes='mangekyo', mouth='flat', brows='angry', arms=HIP_F if i >= 5 else None,
                    legs=WIDE_F)

        def front(S, I, i=i, t=t, fade=fade):
            fx.susanoo(S, sw / 2, I['ground'], t, col, i / 8, fade, k=U * 0.92)

        frames.append(compose(ch, pose, sw, sh, ax=ax, front=front,
                              aura=(col, ease_out(seg(i, 0, 5)), i / 28) if i < 8 else None))
    return Anim('susanoo', frames, anchor_x=ax, label='Susanoo')


def inner_sakura(ch):
    sw, sh = st(1.5), st(1.25)
    frames = []
    for i in range(22):
        up = 4 <= i < 18 and (i // 2) % 2 == 0
        pose = Pose(arms=PUMP_F if up else HIP_F, eyes='angry', brows='angry',
                    mouth='shout' if i >= 4 else 'flat', hy=0 if up else 1, legs=WIDE_F)

        def front(S, I, i=i):
            if 4 <= i < 18:
                fx.speech(S, 'CHA!', I['head'][0] + 22, I['head'][1] - 18)

        frames.append(compose(ch, pose, sw, sh, front=front,
                              aura=('#ff5a5a', 0.9, i / 22) if 4 <= i < 18 else None))
    return Anim('inner_sakura', frames, label='Inner Sakura: CHA!')


def log(S, cx, gy):
    L = Layer(S.w, S.h)
    w, h = 7 * U, 40 * U
    L.rect(cx - w, gy - h, cx + w, gy, '#8a5a32')
    for x in (-4, -1, 2, 5):
        L.line(cx + x * U, gy - h + 6, cx + x * U + 1, gy - 3, '#6a4224')
    L.ellipse(cx, gy - h, w + 0.5, 2.5 * U, '#d8b07a')
    L.ring(cx, gy - h, w * 0.55, '#a87a48', 1.5)
    L.ring(cx, gy - h, w * 0.25, '#a87a48', 1)
    L.cel(4)
    L.outline(0.35)
    S.over(L)


def substitution(ch):
    frames = []
    for i in range(22):
        visible = i < 6 or i >= 18
        pose = Pose(arms=SIGN_F if i < 5 else None, eyes='focus' if i < 5 else 'happy',
                    mouth='flat' if i < 18 else 'smile')

        def front(S, I, i=i):
            if 6 <= i < 18:
                log(S, BASE / 2, I['ground'])
            fx.smoke_puff(S, BASE / 2, BASE * 0.6, seg(i, 4, 10), 26 * U, seed=3)
            fx.smoke_puff(S, BASE / 2, BASE * 0.6, seg(i, 16, 22), 26 * U, seed=4)

        frames.append(compose(ch, pose, front=front, opacity=1.0 if visible else 0.0))
    return Anim('substitution', frames, label='Substitution Jutsu')


def ground_smash(ch, name='cherry_blossom_impact', label='Cherry Blossom Impact', size=1.2,
                 sw=None, sh=None, petal=True):
    sw, sh = sw or st(2), sh or st(1.25)
    frames = []
    for i in range(24):
        if i < 6:
            dy = -int(14 * U * math.sin(math.pi * seg(i, 0, 6)))
            pose = Pose(view='side', arms=UP_S, legs={'R': (40, -60), 'L': (-10, -50)},
                        eyes='angry', brows='angry', mouth='shout')
        elif i < 22:
            dy = 0
            pose = Pose(view='side', arms=SLAM_S, legs=CROUCH_S, lean=6, eyes='angry', brows='angry',
                        mouth='shout' if i < 12 else 'smirk')
        else:
            dy = 0
            pose = Pose(view='side', mouth='smirk')

        def front(S, I, i=i):
            hx, hy = I['handR']
            if i < 6:
                fx.heal_glow(S, hx, hy - U, i / 6, r=3 * U, col=(130, 220, 255, 255),
                             core=(220, 245, 255, 255))
            t = seg(i, 6, 20)
            fx.ground_impact(S, hx + 2 * U, I['ground'], t, seed=21, size=size)
            if petal and 6 <= i < 20:
                fx.petals(S, hx + 4 * U, I['ground'] - 14 * U, t, seed=3, radius=22 * U)

        frames.append(compose(ch, pose, sw, sh, dy=dy, front=front))
    return Anim(name, frames, label=label)


def tsunade_smash(ch):
    return ground_smash(ch, 'ground_smash', 'Strength of a Hundred: Ground Smash', 1.45,
                        st(2.5), st(1.5), petal=False)


def healing(ch):
    sw = st(1.5)
    frames = []
    for i in range(16):
        pose = Pose(view='side', arms=TWO_FWD_S, legs=STANCE_S,
                    eyes='focus' if i % 8 < 6 else 'closed', mouth='smile', hy=1 if i % 8 >= 4 else 0)

        def front(S, I, i=i):
            hx, hy = I['handR']
            fx.heal_glow(S, hx + 3 * U, hy, i / 8, r=5 * U)

        frames.append(compose(ch, pose, sw, front=front))
    return Anim('healing', frames, loops=2, label='Mystic Palm (Healing)')


def shadow_possession(ch, stitch=False):
    sw = st(3)
    sh = st(1.5) if stitch else BASE
    n = 30 if stitch else 26
    frames = []
    for i in range(n):
        pose = Pose(arms=SIGN_F if i < 22 else None, eyes='focus' if i < 22 else 'half',
                    mouth='flat' if i < 22 else 'smirk', legs=WIDE_F)

        def behind(S, I, i=i):
            g = I['ground']
            if stitch:
                length = 96 * U * ease_out(seg(i, 3, 11)) * (1 - seg(i, 26, 30))
            else:
                length = 112 * U * ease_out(seg(i, 3, 13)) * (1 - seg(i, 22, 26))
            fx.shadow_pool(S, BASE / 2, g, 14 * U)
            fx.shadow_line(S, BASE / 2, g, length, i / 6)

        def front(S, I, i=i):
            if stitch and 11 <= i < 27:
                grow = ease_out(seg(i, 11, 17)) * (1 - seg(i, 23, 27))
                hs = [grow * h * U for h in (18, 30, 40, 34, 24, 16)]
                fx.tendrils(S, sw * 0.62, I['ground'], 6 * U, hs, i / 8)

        frames.append(compose(ch, pose, sw, sh, behind=behind, front=front))
    if stitch:
        return Anim('shadow_stitching', frames, label='Shadow Stitching')
    return Anim('shadow_possession', frames, label='Shadow Possession Jutsu')


def shadow_stitching(ch):
    return shadow_possession(ch, stitch=True)


def shadow_neck_bind(ch):
    sw, sh = st(3), st(1.25)
    frames = []
    for i in range(28):
        pose = Pose(arms=SIGN_F if i < 24 else None, eyes='focus' if i < 24 else 'half',
                    mouth='flat' if i < 24 else 'smirk', legs=WIDE_F)

        def behind(S, I, i=i):
            g = I['ground']
            length = 80 * U * ease_out(seg(i, 3, 10)) * (1 - seg(i, 24, 28))
            fx.shadow_pool(S, BASE / 2, g, 14 * U)
            fx.shadow_line(S, BASE / 2, g, length, i / 6)

        def front(S, I, i=i):
            if 10 <= i < 26:
                h = 34 * U * ease_out(seg(i, 10, 15)) * (1 - seg(i, 22, 26))
                grip = seg(i, 15, 19)
                fx.shadow_hand(S, BASE / 2 + 76 * U, I['ground'], h, i / 8, grip)
                fx.shadow_hand(S, BASE / 2 + 88 * U, I['ground'], h * 0.85, i / 8 + 0.3, grip)

        frames.append(compose(ch, pose, sw, sh, behind=behind, front=front))
    return Anim('shadow_neck_bind', frames, label='Shadow Neck Bind')


def cloud_watch(ch):
    sw = st(1.5)
    frames = []
    for i in range(24):
        pose = Pose(arms={'L': (-160, -25), 'R': (160, 25)},
                    eyes='half' if i % 12 < 10 else 'closed', mouth='flat', hy=i // 6 % 2,
                    legs={'L': (-4, 0), 'R': (6, 0)})
        body, _ = render(ch, pose)
        lying = body.rotated90(1)
        bb = lying.bbox()
        S = Layer(sw, BASE)
        fx.clouds(S, i / 2, sw, 8 * U)
        S.over(lying, -bb[0] + 4, BASE - 1 - bb[3])
        if i % 12 >= 10:
            fx.speech(S, 'Z', int(sw * 0.2), int(BASE * 0.45))
        frames.append(S)
    return Anim('cloud_watch', frames, loops=2, label='Cloud Watching ("What a drag")', kind='idle')


def mind_transfer(ch):
    sw = st(3)
    frames = []
    diamond = {'R': (80, 8), 'L': (84, 2)}
    for i in range(24):
        if i < 6:
            pose = Pose(view='side', eyes='focus', arms=diamond, legs=STANCE_S)
        elif i < 20:
            pose = Pose(view='side', eyes='closed', mouth='o', hy=2, lean=-2,
                        arms={'R': (5, 5), 'L': (-5, 5)})
        else:
            pose = Pose(view='side', eyes='wide', mouth='smile')

        def front(S, I, i=i):
            if 6 <= i < 20:
                if i < 16:
                    x = 96 * U * ease_in_out(seg(i, 6, 14))
                else:
                    x = 96 * U * (1 - ease_in_out(seg(i, 16, 20)))
                spirit, _ = render(ch, Pose(view='side', eyes='focus', arms=diamond, legs=STANCE_S))
                g = fx.ghost(spirit)
                d = 1 if i < 16 else -1
                for k in range(3):
                    S.over(g, int(x - (k + 1) * 6 * U * d), -8, 0.18)
                S.over(g, int(x), -8)
            if 4 <= i < 7:
                fx.speech(S, 'MIND', I['head'][0] + 22, I['head'][1] - 16)

        frames.append(compose(ch, pose, sw, front=front))
    return Anim('mind_transfer', frames, label='Mind Transfer Jutsu')


def flower_storm(ch):
    sw, sh = st(1.5), st(1.25)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(20):
        pose = Pose(arms=SPREAD_F if 3 <= i < 17 else None, eyes='happy' if i >= 3 else None,
                    mouth='smile')

        def front(S, I, i=i):
            if i >= 2:
                fx.petals(S, sw / 2, sh - 60 * U * 0.9, seg(i, 2, 20), n=40, seed=8, radius=34 * U,
                          cols=('#ffb7d0', '#ffe066', '#c9a2ff', '#ffffff', '#ff8fb8'))

        frames.append(compose(ch, pose, sw, sh, ax=ax, front=front))
    return Anim('flower_storm', frames, anchor_x=ax, label='Yamanaka Flower Storm')


def expansion(ch):
    sw = sh = st(2)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(26):
        if i < 4:
            k = 1.0
        elif i < 12:
            k = 1 + ease_out(seg(i, 4, 12))
        elif i < 20:
            k = 2.0
        else:
            k = 2 - ease_in_out(seg(i, 20, 26))
        pose = Pose(arms=SIGN_F if i < 4 else (PUMP_F if 12 <= i < 20 and i % 4 < 2 else HIP_F),
                    eyes='angry' if i >= 4 else 'focus', brows='angry' if i >= 4 else None,
                    mouth='shout' if 4 <= i < 20 else 'smile', legs=WIDE_F)

        def front(S, I, i=i):
            fx.smoke_puff(S, sw / 2, sh - 70 * U, seg(i, 3, 9), 36 * U, seed=2)
            if 12 <= i < 15:
                fx.speech(S, 'BAIKA', 10, 8)

        frames.append(compose(ch, pose, sw, sh, ax=ax, scale_k=k, front=front))
    return Anim('expansion', frames, anchor_x=ax, label='Expansion Jutsu')


def human_bullet_tank(ch):
    frames = []
    hair = ch.hair_color
    for i in range(28):
        S = Layer(BASE, BASE)
        if i < 4 or i >= 24:
            body, _ = render(ch, Pose(arms=SIGN_F, eyes='angry', brows='angry', mouth='shout'))
            if i < 2 or i >= 26:
                S.over(body)
            t = seg(i, 0, 4) if i < 4 else seg(i, 24, 28)
            fx.smoke_puff(S, BASE / 2, BASE * 0.6, t, 30 * U, seed=i // 4)
            frames.append(S)
            continue
        r = 22 * U * 0.9
        cx, cy = BASE / 2, BASE - 1 - r
        ang = -(i - 4) * 50
        B = Layer(BASE, BASE)
        B.disc(cx, cy, r, '#4f8a4a')
        for k in range(3):
            a = math.radians(ang + k * 120)
            B.line(cx, cy, cx + math.cos(a) * r, cy + math.sin(a) * r, '#3c6e39', 3)
        a = math.radians(ang)
        hcx, hcy = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
        B.disc(hcx, hcy, r * 0.32, hair)
        for s in range(6):
            sa = a + (s - 2.5) * 0.35
            fx._spike(B, hcx + math.cos(sa) * r * 0.28, hcy + math.sin(sa) * r * 0.28,
                      -math.degrees(sa), r * 0.2, r * 0.12, hair)
        a2 = math.radians(ang + 180)
        B.disc(cx + math.cos(a2) * r * 0.6, cy + math.sin(a2) * r * 0.6, r * 0.22, '#f1f1ec')
        B.cel(6, 2)
        B.outline(0.32)
        fx.dust(S, 14, BASE - 1, ((i - 4) % 6) / 6, 12, seed=i % 3)
        S.over(B)
        fx.speed_lines(S, 0, 14, (cy - 20, cy, cy + 20), opacity=0.5)
        frames.append(S)
    return Anim('human_bullet_tank', frames, moving=True, label='Human Bullet Tank')


def butterfly_mode(ch):
    sw, sh = st(2), st(1.5)
    ax = (sw - BASE) // 2
    frames = []
    for i in range(24):
        t = ease_out(seg(i, 2, 10))
        pose = Pose(eyes='angry' if i >= 2 else 'focus', brows='angry', mouth='flat',
                    arms=HIP_F if i >= 4 else SIGN_F, legs=WIDE_F)

        def behind(S, I, i=i, t=t):
            cx, cy = I['chest']
            fx.wings(S, cx, cy - 4 * U, t, i / 6)

        frames.append(compose(ch, pose, sw, sh, ax=ax, behind=behind,
                              aura=('#ff8fb8', 0.8 * t, i / 24) if t > 0.1 else None))
    return Anim('butterfly_mode', frames, anchor_x=ax, label='Butterfly Mode')


def partial_expansion(ch):
    sw, sh = st(2.5), st(1.25)
    frames = []
    for i in range(22):
        pose = Pose(view='side', arms=PUNCH_S if 3 <= i < 18 else None, legs=LUNGE_S, eyes='angry',
                    brows='angry', mouth='shout' if 3 <= i < 16 else 'smile')

        def front(S, I, i=i):
            if not 3 <= i < 18:
                return
            hx, hy = I['handR']
            g = ease_out(seg(i, 3, 10)) * (1 - seg(i, 15, 18))
            r = (3 + 13 * g) * U
            fx_x = hx + r * 2.2
            F = Layer(S.w, S.h)
            F.line(hx, hy, fx_x - r * 0.6, hy - r * 0.4, '#c8332f', max(5, int(r * 0.9)))
            F.disc(fx_x, hy - r * 0.4, r, ch.skin)
            for k in range(4):
                yy = hy - r * 1.0 + k * r * 0.45
                F.line(fx_x + r * 0.15, yy, fx_x + r * 0.85, yy, '#c79a7a', 2)
            F.cel(int(r * 0.35) + 1, 2)
            F.outline(0.35)
            S.over(F)
            if 10 <= i < 15:
                fx.burst(S, fx_x + r, hy - r * 0.4, 14 * U, seg(i, 10, 15), inner='#fff4c2',
                         outer='#ffb24d')

        frames.append(compose(ch, pose, sw, sh, front=front))
    return Anim('partial_expansion', frames, label='Partial Expansion: Giant Fist')


def kamui(ch):
    sw, sh = st(2), st(1.25)
    frames = []
    for i in range(24):
        pose = Pose(view='side', eyes='sharingan' if i >= 2 else None, legs=STANCE_S,
                    arms={'R': (85, -8), 'L': (-10, 20)} if 3 <= i < 20 else None)

        def front(S, I, i=i):
            if 4 <= i < 20:
                r = 12 * U * ease_out(seg(i, 4, 10)) * (1 - ease_in_out(seg(i, 16, 20)))
                fx.kamui(S, sw * 0.75, sh - 34 * U, r, i / 8)

        frames.append(compose(ch, pose, sw, sh, front=front))
    return Anim('kamui', frames, label='Kamui')


def summoning(ch, name, label, creature, sw, sh):
    frames = []
    cx = BASE + (sw - BASE) / 2
    for i in range(32):
        if i < 5:
            pose = Pose(view='side', arms=SLAM_S, legs=CROUCH_S, lean=6, mouth='shout',
                        eyes='angry', brows='angry')
        else:
            pose = Pose(arms=PUMP_F if 8 <= i < 14 else HIP_F, mouth='grin' if i < 28 else 'smile',
                        legs=WIDE_F)

        def front(S, I, i=i):
            g = I['ground']
            if i < 6:
                fx.summon_seal(S, I['handR'][0] + 2 * U, g, seg(i, 0, 5))
            if 6 <= i < 29:
                creature(S, cx, i)
            fx.smoke_puff(S, cx, g - 30 * U, seg(i, 4, 11), 34 * U, seed=12)
            fx.smoke_puff(S, cx, g - 30 * U, seg(i, 26, 32), 34 * U, seed=13)

        frames.append(compose(ch, pose, sw, sh, front=front))
    return Anim(name, frames, label=label)


def toad_summoning(ch):
    return summoning(ch, 'toad_summoning', 'Summoning: Gamabunta',
                     lambda S, cx, i: fx.toad(S, cx, S.h - 1, blink=i in (16, 17),
                                              puff=((i - 6) % 8) / 8 if i > 10 else 0),
                     st(2.5), st(1.5))


def katsuyu(ch):
    return summoning(ch, 'katsuyu', 'Summoning: Katsuyu',
                     lambda S, cx, i: fx.slug(S, cx, S.h - 1, i / 10), st(2.5), st(1.25))


def byakugan(ch):
    frames = []
    for i in range(22):
        on = 4 <= i < 19
        pose = Pose(arms=SIGN_F if i < 4 else None,
                    eyes='byakugan' if on else ('closed' if i < 4 else None), mouth='flat',
                    brows='angry' if on else None)
        frames.append(compose(ch, pose, aura=('#a9c8ff', 0.6, i / 22) if on else None))
    return Anim('byakugan', frames, label='Byakugan')


def eight_trigrams(ch, name='eight_trigrams', label='Eight Trigrams 64 Palms', count='64!'):
    sw, sh = st(2.5), st(1.25)
    ax = int(20 * U)
    frames = []
    for i in range(28):
        right = i % 2 == 0
        if i < 6:
            arms = {'R': (70, 20), 'L': (-40, 30)}
        elif i < 24:
            arms = {'R': (90, 0), 'L': (-25, 20)} if right else {'L': (95, -5), 'R': (20, 60)}
        else:
            arms = {'R': (92, 0), 'L': (95, -3)}
        pose = Pose(view='side', arms=arms, legs=LUNGE_S, lean=3, eyes='byakugan', brows='angry',
                    mouth='shout' if 6 <= i < 24 else 'flat')

        def behind(S, I, i=i):
            fx.trigram_circle(S, ax + BASE / 2, I['ground'],
                              ease_out(seg(i, 0, 6)) * (1 - seg(i, 24, 28)), i / 10)

        def front(S, I, i=i, right=right):
            if 6 <= i < 24:
                h = I['handR'] if right else I['handL']
                fx.palm_blast(S, h[0] + 2 * U, h[1], 0.5)
            if 24 <= i < 28:
                fx.burst(S, I['handR'][0] + 8 * U, I['handR'][1], 16 * U, seg(i, 24, 28),
                         inner='#e6f6ff', outer='#7fc8ff')
            if 14 <= i < 20 and count:
                fx.speech(S, count, I['head'][0] + 22, I['head'][1] - 16)

        frames.append(compose(ch, pose, sw, sh, ax=ax, behind=behind, front=front,
                              aura=('#a9c8ff', 0.5, i / 28)))
    return Anim(name, frames, anchor_x=ax, label=label)


def gentle_fist(ch):
    return eight_trigrams(ch, 'gentle_fist', 'Gentle Fist', None)


BLUE_FIRE = ['#2f6fd6', '#6fb4ff', '#c4e4ff', '#ffffff']


def twin_lion_fists(ch):
    sw, sh = st(2.5), st(1.25)
    frames = []
    for i in range(24):
        if i < 10:
            dx = 0
            pose = Pose(view='side', arms=TWO_FWD_S, legs=STANCE_S)
        elif i < 18:
            dx = 40 * U * ease_out(seg(i, 10, 14))
            pose = Pose(view='side', arms=TWO_FWD_S, legs=LUNGE_S, lean=4)
        else:
            dx = 40 * U * (1 - ease_in_out(seg(i, 18, 23)))
            pose = Pose(view='side')

        def front(S, I, i=i):
            if i < 16:
                r = (2 + 7 * ease_out(seg(i, 0, 8))) * U
                for k, h in enumerate((I['handR'], I['handL'])):
                    fx.fireball(S, h[0] + r * 0.6, h[1] - k * 3 * U, r, seed=i * 3 + k, pal=BLUE_FIRE,
                                trail=0.6 if i >= 10 else 0.2)
            if 14 <= i < 19:
                fx.burst(S, I['handR'][0] + 10 * U, I['handR'][1], 18 * U, seg(i, 14, 19),
                         inner='#e6f6ff', outer='#6fb4ff')
            if 10 <= i < 14:
                o = I['origin'][0]
                fx.speed_lines(S, o + 20, o + 60, [I['hip'][1] - k * 12 for k in range(5)])

        frames.append(compose(ch, pose, sw, sh, dx=dx, front=front))
    return Anim('twin_lion_fists', frames, label='Twin Lion Fists')


def crow_clone(ch):
    sw, sh = st(2), st(1.75)
    rng = random.Random(5)
    oy = sh - BASE
    crows = [(rng.uniform(44, 84), rng.uniform(40, 110), rng.uniform(1.5, 4), rng.uniform(-3.5, -1.2))
             for _ in range(14)]
    frames = []
    for i in range(30):
        if i < 4:
            op = 1.0
        elif i < 8:
            op = 1 - seg(i, 4, 8)
        elif i < 24:
            op = 0.0
        else:
            op = seg(i, 24, 29)
        pose = Pose(eyes='sharingan', mouth='flat')

        def front(S, I, i=i):
            if 4 <= i < 26:
                tt = (i - 4) if i < 16 else max(0, 26 - i) * 1.2
                for k, (x, y, vx, vy) in enumerate(crows):
                    px = x + vx * tt * 2.2 * U
                    py = oy + y + vy * tt * 2.2 * U
                    fx.crow(S, int(px), int(py), (i + k) % 2)

        frames.append(compose(ch, pose, sw, sh, front=front, opacity=op))
    return Anim('crow_clone', frames, label='Crow Clone')


JUTSU = {
    'shadow_clone': shadow_clone, 'rasengan': rasengan, 'rasenshuriken': rasenshuriken,
    'sage_mode': sage_mode, 'chidori': chidori, 'fireball': fireball, 'amaterasu': amaterasu,
    'inner_sakura': inner_sakura, 'substitution': substitution,
    'cherry_blossom_impact': ground_smash, 'healing': healing,
    'shadow_possession': shadow_possession, 'shadow_stitching': shadow_stitching,
    'shadow_neck_bind': shadow_neck_bind,
    'cloud_watch': cloud_watch, 'mind_transfer': mind_transfer, 'flower_storm': flower_storm,
    'expansion': expansion, 'human_bullet_tank': human_bullet_tank,
    'butterfly_mode': butterfly_mode, 'partial_expansion': partial_expansion,
    'lightning_blade': lightning_blade, 'kamui': kamui, 'toad_summoning': toad_summoning,
    'byakugan': byakugan, 'eight_trigrams': eight_trigrams, 'ground_smash': tsunade_smash,
    'katsuyu': katsuyu, 'crow_clone': crow_clone, 'gentle_fist': gentle_fist,
    'twin_lion_fists': twin_lion_fists,
}

SUSANOO_COLOR = {'sasuke_shippuden': '#8a4fd8', 'itachi': '#ff5a3a'}


def build_all(ch):
    anims = [front(ch), walk(ch), drag(ch), sleep(ch)]
    if ch.snack:
        anims.append(snack(ch))
    for j in ch.jutsu:
        if j == 'susanoo':
            anims.append(susanoo(ch, SUSANOO_COLOR.get(ch.id, '#8a4fd8')))
        else:
            anims.append(JUTSU[j](ch))
    return anims
