"""Character designs, matched to the character sheet (art/source/character_sheet.png).

Colours are sampled from the sheet's cut-outs in art/. Each character is drawn
by the rig in body.py: hair/headgear on the 16x15 face grid, face marks on the
18x21 face grid, outfits in torso units (origin = middle of the shoulder line,
waist ~y 21, hips y = t.b['torso']). Spike angles: 90 = up, -90 = down."""

from engine import scale

METAL = '#bcc3cd'
METAL_HI = '#eef2f6'
METAL_LO = '#6b7482'
SKIN = '#f3cfbc'
SKIN_PALE = '#f6dccf'
SKIN_TAN = '#ecc0a2'
WRAP = '#ebe7e0'
NAVY_SANDAL = '#2b3a78'


class Character:
    def __init__(self, id, name, era, skin, iris, hair, outfit, torso=None, marks=None,
                 headgear=None, back_item=None, collar=None, eyes='open', mouth='flat',
                 color='#ff8800', build='male', jutsu=(), snack=None, speed=0.5, tagline='',
                 group=None, brows=None, brow_color='#3a2a22', pale_eyes=False, size=1.0, head=1.0,
                 hair_color='#333333', one_sharingan=False, art=None):
        self.id, self.name, self.era = id, name, era
        self.skin, self.iris = skin, iris
        self.hair, self.outfit, self.torso = hair, outfit, torso
        self.marks, self.headgear, self.back_item, self.collar = marks, headgear, back_item, collar
        self.eyes, self.mouth, self.color, self.build = eyes, mouth, color, build
        self.jutsu, self.snack, self.speed, self.tagline = list(jutsu), snack, speed, tagline
        self.group = group or id.replace('_shippuden', '')
        self.brows, self.brow_color, self.pale_eyes = brows, brow_color, pale_eyes
        self.size, self.head, self.hair_color = size, head, hair_color
        self.one_sharingan = one_sharingan
        self.art = art or f'{id}.png'


# =================================================================== helpers
def plate(c, x0, y, w=10, slash=False):
    """Metal forehead plate with the Konoha leaf engraved (hair-grid coords)."""
    c.rect(x0, y, x0 + w - 1, y + 3, METAL)
    c.rect(x0, y, x0 + w - 1, y + 0.4, METAL_HI)
    c.rect(x0, y + 3, x0 + w - 1, y + 3, METAL_LO)
    for x in (x0 + 0.6, x0 + w - 1.4):
        c.ellipse(x + 0.2, y + 1.8, 0.4, 0.35, METAL_LO)
    cx, cy = x0 + w / 2, y + 1.7
    c.ellipse(cx, cy, 1.5, 0.95, METAL_LO)
    c.ellipse(cx + 0.15, cy - 0.1, 0.7, 0.4, METAL)
    c.line(cx + 1.2, cy + 0.4, cx + 2.4, cy - 0.9, METAL_LO)
    c.line(cx - 1.5, cy + 0.2, cx - 2.3, cy + 1.0, METAL_LO)
    if slash:
        c.line(x0 + 0.5, y + 3, x0 + w - 1.5, y + 0.2, '#262a33', 2)


def headband(c, cloth, y=2, slash=False, plate_w=10, tails=0):
    x0 = 3 + (1 if c.side else 0)
    c.rect(-1, y, 16, y + 3, cloth)
    c.rect(-1, y + 3, 16, y + 3, scale(cloth, 0.7))
    plate(c, x0, y, plate_w, slash)
    if tails:
        c.poly([(-1, y + 1), (-2.5 - tails, y + 2.5 + tails), (-2 - tails, y + 3.5 + tails), (-1, y + 3)], cloth)
        c.poly([(-1, y + 2), (-1.5 - tails * 0.6, y + 4 + tails * 1.3),
                (-0.6 - tails * 0.6, y + 4.6 + tails * 1.3), (-0.3, y + 3)], scale(cloth, 0.85))


def bangs(c, xs, top, length, width, col, tilt=0):
    for x in xs:
        c.spike(x, top, -90 + tilt, length, width, col)


def cap(c, col, hairline=4):
    c.poly([(-1, hairline), (-0.5, 0), (3, -3), (12, -3), (15.5, 0), (16, hairline)], col)


def long_curtain(b, col, length, flare=2, jag=True):
    pts = [(-2, 0), (17, 0), (17 + flare, length)]
    if jag:
        step = (19 + 2 * flare) / 6
        for i in range(6):
            pts.append((17 + flare - step * (i + 0.5), length - 2 - (i % 2) * 2))
    pts.append((-2 - flare, length))
    b.poly(pts, col)


def side_locks(f, col, length=13, width=3, inset=0):
    f.poly([(-1 + inset, 2), (-1 + inset + width, 2), (inset + width - 1, length - 2), (inset, length)], col)
    f.poly([(16 - inset, 2), (16 - inset - width, 2), (16 - inset - width + 1, length - 2),
            (15 - inset, length)], col)


def shine(c, x0, x1, y, col='#ffffff'):
    c.line(x0, y, x1, y - 0.6, col)


def zipper(t, y0, y1, col='#f2e6cf', pull=True):
    t.rect(-0.3, y0, 0.3, y1, col)
    if pull:
        t.rect(-1, y0 + 1, 1, y0 + 3, '#aab2bd')


def high_collar(t, col, h=6, open_v=False):
    t.poly([(-6, -h), (6, -h), (8, 1), (-8, 1)], col)
    t.rect(-5, -h, 5, -h + 0.5, scale(col, 1.25))
    if open_v:
        t.poly([(-1.5, -h), (1.5, -h), (0, 0)], scale(col, 0.7))


def mesh(t, x0, y0, x1, y1, base='#4a474b'):
    t.rect(x0, y0, x1, y1, base)
    dark = scale(base, 0.72)
    for y in range(int(y0), int(y1) + 1, 2):
        t.line(x0, y, x1, y, dark)
    for x in range(int(x0), int(x1) + 1, 2):
        t.line(x, y0, x, y1, dark)


def flak_vest(t, col='#666c5c'):
    """Konoha flak jacket: rolled collar, scroll pockets, centre zip."""
    b = t.b
    sh, wa = b['sh'], b['waist']
    t.poly([(-sh + 1, 2), (-sh + 3, -1), (sh - 3, -1), (sh - 1, 2), (b['chest'] + 0.5, 10),
            (wa + 1, 22), (wa + 1.5, 25), (-wa - 1.5, 25), (-wa - 1, 22), (-b['chest'] - 0.5, 10)], col)
    t.poly([(-7, -5), (7, -5), (9, 1), (4, 3), (0, 0), (-4, 3), (-9, 1)], scale(col, 1.12))
    t.line(-7, -5, -9, 1, scale(col, 0.7))
    t.line(7, -5, 9, 1, scale(col, 0.7))
    t.rect(-0.3, 1, 0.3, 25, scale(col, 0.62))
    for px in (-8, 2):
        for py in (10, 16):
            t.rect(px, py, px + 5, py + 4, scale(col, 1.08))
            t.rect(px, py, px + 5, py + 0.6, scale(col, 0.7))
            for sx in (1.2, 2.6, 4.0):
                t.line(px + sx, py + 1.2, px + sx, py + 3.6, scale(col, 0.82))


def rope_belt(t, col, y=16, h=6):
    b = t.b
    w = b['waist'] + 1.8
    t.rect(-w, y, w, y + h, col)
    for x in range(int(-w), int(w) + 1, 2):
        t.line(x, y + h, x + 1.5, y, scale(col, 0.7))
    t.rect(-w, y, w, y + 0.6, scale(col, 1.3))
    t.ellipse(-1, y + h / 2, 3, 3, scale(col, 1.1))
    t.poly([(-2, y + h), (-4, y + h + 18), (0, y + h + 17), (1, y + h)], col)
    t.poly([(0, y + h), (2, y + h + 14), (5, y + h + 13), (2.5, y + h)], scale(col, 0.85))


def skirt_panels(t, col, y0, y1, gap=1.5, flare=3, split=True):
    b = t.b
    w0, w1 = b['waist'] + 0.5, b['hip'] + flare
    if split:
        t.poly([(-w0, y0), (-gap, y0), (-gap - 1, y1), (-w1, y1)], col)
        t.poly([(w0, y0), (gap, y0), (gap + 1, y1), (w1, y1)], col)
        t.line(-gap - 1, y0 + 2, -gap - 1.5, y1, scale(col, 0.8))
        t.line(gap + 1, y0 + 2, gap + 1.5, y1, scale(col, 0.8))
    else:
        t.poly([(-w0, y0), (w0, y0), (w1, y1), (-w1, y1)], col)
    t.rect(-w1, y1 - 0.5, w1, y1, scale(col, 0.75))


def kanji_food(t, x, y, col='#b8322f', k=1.0):
    for dx, dy in ((2, 0), (1, 1), (3, 1), (0, 2), (4, 2), (1, 3), (2, 3), (3, 3), (1, 4), (3, 4),
                   (1, 5), (2, 5), (1, 6), (3, 6), (4, 6)):
        t.rect(x + dx * k, y + dy * k, x + dx * k + k * 0.6, y + dy * k + k * 0.6, col)


def cloud(t, x, y, k=1.0):
    """Akatsuki red cloud with a white rim."""
    for dx, dy, rx, ry in ((2.5, 3, 2.6, 2.4), (5.5, 2.2, 3.2, 2.8), (8.2, 3.2, 2.4, 2.2)):
        t.ellipse(x + dx * k, y + dy * k, rx * k, ry * k, '#efe6e6')
    for dx, dy, rx, ry in ((2.5, 3, 1.9, 1.7), (5.5, 2.2, 2.5, 2.1), (8.2, 3.2, 1.7, 1.5)):
        t.ellipse(x + dx * k, y + dy * k, rx * k, ry * k, '#a82a33')


def spiral_patch(t, x, y, col='#a8322f'):
    t.ellipse(x, y, 1.8, 1.8, col)
    t.ellipse(x, y, 0.7, 0.7, scale(col, 0.6))


# ===================================================================== NARUTO
def naruto_hair(b, f, long=False):
    hc, hl = '#f6cf4a', '#fff08c'
    b.ellipse(7.5, 4.5, 9.5, 7.5, hc)
    b.crown(7.5, 3, [(172, 12, 6), (148, 12 + long, 6), (122, 12, 7), (95, 12 + long, 7),
                     (68, 12, 7), (40, 12 + long, 6), (12, 12, 6)], hc)
    b.spike(-1, 8, 200, 5 + long * 2, 5, hc)
    b.spike(16, 8, -20, 5 + long * 2, 5, hc)
    cap(f, hc)
    bangs(f, (1, 7.5, 14.5), 5, 4 + long, 3, hc)
    f.spike(-0.5, 5, -95, 7 + long * 2, 3, hc)
    f.spike(15.5, 5, -85, 7 + long * 2, 3, hc)
    f.spike(5, -2, 105, 4, 3, hl)
    f.spike(10, -2, 72, 3, 2, hl)


def naruto_marks(f):
    ink = scale(f.ch.skin, 0.55)
    xs = (2, 14) if not f.side else (5, 16)
    for y in (13.5, 14.6, 15.7):
        f.line(xs[0], y, xs[0] + 1.6, y + 0.2, ink)
        f.line(xs[1], y + 0.2, xs[1] + 1.6, y, ink)


def naruto_classic_torso(t):
    b = t.b
    navy, orange = '#1d2b4f', '#e07a4c'
    t.poly([(-b['sh'], 3), (-b['sh'] + 3, -0.5), (b['sh'] - 3, -0.5), (b['sh'], 3),
            (b['chest'] - 0.5, 8), (-b['chest'] + 0.5, 8)], navy)
    t.poly([(-7, -6), (7, -6), (8.5, 2), (3, 4), (0, 1), (-3, 4), (-8.5, 2)], '#efebe7')
    for x in (-6, -3, 3, 6):
        t.line(x, -5.5, x * 1.15, 1.5, '#cfcac4')
    zipper(t, 1, 22)
    t.rect(-b['waist'] - 0.5, 20, b['waist'] + 0.5, 22, navy)
    t.line(-b['waist'] + 1, 12, -b['waist'] + 3, 19, scale(orange, 0.8))
    t.line(b['waist'] - 1, 12, b['waist'] - 3, 19, scale(orange, 0.8))
    spiral_patch(t, b['chest'] - 2, 4, '#c8452a')


def naruto_sage_torso(t):
    """Sage-mode outfit: black high-collar top, brown strap, red cloak with black flames."""
    b = t.b
    black, red, flame = '#2a292d', '#8a2f2d', '#1c1a1d'
    t.poly([(-6, -6), (6, -6), (8, 1), (-8, 1)], black)
    t.rect(-6, -6, 6, -5.5, scale(black, 1.4))
    zipper(t, -5, 22, '#55545a', pull=False)
    t.poly([(b['sh'] - 2, 0), (b['sh'] + 1, 2), (-b['waist'] + 1, 24), (-b['waist'] - 2, 21)], '#8a6a48')
    hem = 62
    for s in (-1, 1):
        t.poly([(s * 4, -1), (s * (b['sh'] - 2), -1), (s * (b['sh'] + 1.5), 2), (s * (b['chest'] + 2), 10),
                (s * (b['hip'] + 7), hem), (s * 6, hem), (s * 5, 22)], red)
        for i in range(4):
            x = s * (6 + i * 4.2)
            t.poly([(x - s * 0.5, hem), (x + s * 2.1, hem - 7 - (i % 2) * 4), (x + s * 4.2, hem)], flame)
        t.rect(min(s * 6, s * (b['hip'] + 7)), hem - 1.6, max(s * 6, s * (b['hip'] + 7)), hem, flame)
        t.line(s * 5, 22, s * 6, hem, scale(red, 0.7))


def naruto_scroll(t):
    t.rect(10, 6, 26, 15, '#7a2c2b')
    t.rect(10, 6, 26, 7, scale('#7a2c2b', 1.3))
    t.ellipse(26, 10.5, 2.4, 4.8, '#2a2427')
    t.ellipse(26, 10.5, 1.2, 2.4, '#4a3a3a')
    for x in (14, 19):
        t.rect(x, 6, x + 1, 15, '#3a2a2a')


NARUTO = Character(
    'naruto', 'Naruto Uzumaki', 'classic', SKIN_TAN, '#3b78c8', hair=naruto_hair,
    outfit=dict(top='#e07a4c', pants='#e07a4c', sleeve='long', sleeve_top='#1d2b4f', sleeve_top_len=0.45,
                baggy=1.4, pants_baggy=1.6, pants_cuff=True, holster='L', sandals=NAVY_SANDAL),
    torso=naruto_classic_torso, marks=naruto_marks, headgear=lambda c: headband(c, '#22336a', tails=1),
    mouth='smile', color='#e07a4c', speed=0.6, snack='ramen', brow_color='#c9971c', size=0.88,
    head=1.1, hair_color='#f6cf4a', jutsu=['shadow_clone', 'rasengan'],
    tagline='Believe it! The loud kid in the orange jumpsuit.')

NARUTO_S = Character(
    'naruto_shippuden', 'Naruto Uzumaki', 'shippuden', SKIN_TAN, '#3b78c8',
    hair=lambda b, f: naruto_hair(b, f, long=True),
    outfit=dict(top='#2a292d', pants='#d1734d', sleeve='long', sleeve_color='#2a292d', baggy=1.2,
                sleeve_top='#8a2f2d', sleeve_top_len=0.95,
                pants_baggy=1.5, holster='L', holster_wrap='#e7e3dc', sandals='#232226',
                shin='#232226', shin_from=0.78, shin_wrap=False, long_top=True),
    torso=naruto_sage_torso, back_item=naruto_scroll, marks=naruto_marks,
    headgear=lambda c: headband(c, '#1f1e22', tails=4), mouth='smile', color='#8a2f2d', speed=0.65,
    snack='ramen', brow_color='#c9971c', hair_color='#f6cf4a',
    jutsu=['rasenshuriken', 'sage_mode', 'shadow_clone'],
    tagline='Sage of Mount Myoboku with a Rasenshuriken in hand.')


# ===================================================================== SASUKE
def sasuke_hair(b, f, long=False, band=True):
    hc = '#1f2538'
    b.ellipse(7.5, 4.5, 9, 7, hc)
    b.crown(8, 3, [(165, 11 + long, 6), (140, 12 + long, 7), (115, 11, 7), (90, 9, 6),
                   (60, 10, 7), (30, 11 + long, 6), (8, 10, 5)], hc)
    cap(f, hc, 3)
    if not band:
        bangs(f, (1, 14.5), 2, 7, 3.5, hc)
        f.spike(6.5, 2, -96, 5, 2.5, hc)
        f.spike(9, 2, -100, 8, 1.6, hc)
    else:
        bangs(f, (7.5,), 5, 4, 3, hc)
    side_locks(f, hc, 13 + long, 3)
    shine(f, 3, 7, -1.5, '#46557e')


def sasuke_torso(t):
    navy = '#1a2f5c'
    t.poly([(-7, -7), (7, -7), (9, 2), (-9, 2)], scale(navy, 1.1))
    t.rect(-6.5, -7, 6.5, -6.4, scale(navy, 1.35))
    t.poly([(-1.5, -6), (1.5, -6), (0, 1)], scale(navy, 0.7))
    t.rect(-t.b['waist'], 20, t.b['waist'], 21, scale(navy, 0.7))


def sasuke_shippuden_torso(t):
    b = t.b
    shirt, cloth = '#9d93a6', '#474661'
    t.poly([(-5, -2), (5, -2), (2, 15), (0, 17), (-2, 15)], t.ch.skin)
    t.line(0, 6, 0, 14, scale(t.ch.skin, 0.82))
    t.line(-4, 5, -1, 7, scale(t.ch.skin, 0.85))
    t.line(4, 5, 1, 7, scale(t.ch.skin, 0.85))
    t.poly([(-6, -5), (-3, -6), (-2, 15), (-5, 12)], scale(shirt, 1.05))
    t.poly([(6, -5), (3, -6), (2, 15), (5, 12)], scale(shirt, 0.95))
    t.poly([(-b['waist'] - 2, 20), (b['waist'] + 2, 20), (b['hip'] + 4, 50), (-b['hip'] - 4, 50)], cloth)
    for x in (-6, -2, 2, 6):
        t.line(x, 24, x * 1.35, 49, scale(cloth, 0.72))
    rope_belt(t, '#76599a', 15, 6)


def sasuke_sword(t):
    t.line(9, 17, -16, 44, '#2e2a38', 3)
    t.line(9, 17, 15, 9, '#dcd9e2', 3)
    t.rect(8, 16, 10, 18, '#c9b25a')


SASUKE = Character(
    'sasuke', 'Sasuke Uchiha', 'classic', SKIN_PALE, '#2a2a33', hair=sasuke_hair,
    outfit=dict(top='#1a2f5c', pants='#d8d6d4', pants_len='knee', sleeve='short',
                forearm_L='#e2e0de', sleeve_color='#1a2f5c', holster='R', holster_wrap='#e2e0de',
                shin=WRAP, shin_from=0.35, sandals=NAVY_SANDAL),
    torso=sasuke_torso, headgear=lambda c: headband(c, '#22336a', tails=1), mouth='flat',
    color='#1a2f5c', speed=0.6, snack='tomato', brow_color='#1c2030', size=0.88, head=1.1,
    hair_color='#1f2538', jutsu=['chidori', 'fireball'], tagline='Last of the Uchiha. Fireball and Chidori.')

SASUKE_S = Character(
    'sasuke_shippuden', 'Sasuke Uchiha', 'shippuden', SKIN_PALE, '#2a2a33',
    hair=lambda b, f: sasuke_hair(b, f, long=True, band=False),
    outfit=dict(top='#9d93a6', pants='#2a2a3a', sleeve='elbow', sleeve_color='#9d93a6', baggy=1.8,
                forearm='#1e1f28', long_top=True, sandals='#232333', shin='#5a5248', shin_from=0.1,
                shin_wrap=False),
    torso=sasuke_shippuden_torso, back_item=sasuke_sword, mouth='flat', color='#76599a', speed=0.65,
    snack='tomato', brow_color='#1c2030', hair_color='#1f2538',
    jutsu=['chidori', 'amaterasu', 'susanoo'], tagline='Rogue avenger: Kusanagi, Amaterasu and Susanoo.')


# ===================================================================== SAKURA
def sakura_hair(b, f):
    hc = '#f0a6b8'
    b.ellipse(7.5, 5, 9.5, 8, hc)
    b.poly([(-2.5, 5), (17.5, 5), (17.5, 12.5), (13, 14), (7.5, 13), (2, 14), (-2.5, 12.5)], hc)
    cap(f, hc, 3)
    f.poly([(-1, 2), (6, 2), (2, 6), (0, 12), (-1, 11)], hc)
    f.poly([(16, 2), (9, 2), (13, 6), (15, 12), (16, 11)], hc)
    f.spike(4, 3, -110, 4, 3, hc)
    f.spike(11, 3, -70, 4, 3, hc)
    shine(f, 2, 6, 0, '#ffe0ec')


def sakura_band(c):
    c.rect(-1, -2, 16, 0, '#a82c3a')
    plate(c, 3 + (1 if c.side else 0), -3.2, 10)


def sakura_marks(f):
    if f.ch.id == 'sakura_shippuden':
        x = 8.4 if not f.side else 10
        f.poly([(x, 3), (x + 1, 4.2), (x, 5.4), (x - 1, 4.2)], '#8a4fb1')


def sakura_torso(t):
    b = t.b
    red, trim = '#8e2e3d', '#f1ece8'
    t.poly([(-4, -5), (4, -5), (5, 1), (-5, 1)], red)
    t.rect(-4, -5, 4, -4.5, trim)
    t.rect(-0.3, -4, 0.3, 20, trim)
    t.rect(-b['waist'] - 0.5, 20, b['waist'] + 0.5, 21, scale(red, 0.75))
    skirt_panels(t, red, 21, 42, gap=0.4, flare=2.5)
    t.ellipse(-3.5, 33, 2.6, 2.6, trim)
    t.ellipse(-3.5, 33, 1.6, 1.6, red)
    t.line(-b['hip'] - 2.5, 42, -b['hip'] - 2.5, 30, trim)
    t.line(b['hip'] + 2.5, 42, b['hip'] + 2.5, 30, trim)


def sakura_shippuden_torso(t):
    b = t.b
    red, skirt = '#7d2d3b', '#c99096'
    t.poly([(-4, -5), (4, -5), (5, 1), (-5, 1)], red)
    zipper(t, -4, 19, '#d8d0cc')
    t.rect(-b['waist'] - 0.5, 19, b['waist'] + 0.5, 21, '#3a2a30')
    t.poly([(-b['waist'], 22), (b['waist'], 22), (b['hip'], 28), (-b['hip'], 28)], '#2e2b33')
    skirt_panels(t, skirt, 20, 40, gap=3, flare=3.5)


SAKURA = Character(
    'sakura', 'Sakura Haruno', 'classic', SKIN, '#3fa874', hair=sakura_hair, headgear=sakura_band,
    marks=sakura_marks,
    outfit=dict(top='#8e2e3d', pants='#3e3046', pants_len='shorts', pants_baggy=0.4, sleeve='short',
                sleeve_color='#8e2e3d', long_top=True, sandals=NAVY_SANDAL),
    torso=sakura_torso, build='female', mouth='smile', color='#f0a6b8', speed=0.55, snack='dango',
    brow_color='#c97890', size=0.88, head=1.1, hair_color='#f0a6b8',
    jutsu=['inner_sakura', 'substitution'], tagline='Top of the class in chakra control. CHA!')

SAKURA_S = Character(
    'sakura_shippuden', 'Sakura Haruno', 'shippuden', SKIN, '#3fa874', hair=sakura_hair,
    headgear=sakura_band, marks=sakura_marks,
    outfit=dict(top='#7d2d3b', pants='#2e2b33', pants_len='knee', pants_baggy=0.3, sleeve='none',
                gloves='#2a282e', fingerless=False, elbow_pad='#c4a3a8', boots='#2e2b33',
                sandals='#2e2b33', heels=True, long_top=True, holster='R', holster_wrap=WRAP),
    torso=sakura_shippuden_torso, build='female', mouth='smile', color='#7d2d3b', speed=0.6,
    snack='dango', brow_color='#c97890', hair_color='#f0a6b8',
    jutsu=['cherry_blossom_impact', 'healing'],
    tagline="Tsunade's apprentice: medic by day, crater-maker by night.")


# ================================================================== SHIKAMARU
def shikamaru_hair(b, f):
    hc = '#25222a'
    b.ellipse(7.5, 4, 8.5, 6.5, hc)
    b.rect(6, -6, 9, -2, hc)
    b.crown(7.5, -5, [(150, 6, 3), (125, 7, 3), (100, 8, 3), (80, 8, 3), (55, 7, 3), (30, 6, 3)], hc)
    b.rect(5.5, -5, 9.5, -4.4, '#8a7a6a')
    f.poly([(-1, 5), (-0.5, 1), (3, -2), (12, -2), (15.5, 1), (16, 5), (13, 1), (2, 1)], hc)
    f.rect(-1, 3, 0, 6, hc)
    f.rect(15, 3, 16, 6, hc)
    shine(f, 4, 9, -1.4, '#55505a')


def shikamaru_marks(f):
    f.ellipse(1.2, 14, 0.5, 0.6, '#d8dbe2')
    if not f.side:
        f.ellipse(16.8, 14, 0.5, 0.6, '#d8dbe2')


def shikamaru_torso(t):
    b = t.b
    vest = '#9c9792'
    mesh(t, -5, -4, 4, 22, '#3e3a3d')
    t.poly([(-b['sh'], 3), (-5, -1), (-4, 24), (-b['waist'] - 0.5, 24), (-b['chest'], 9)], vest)
    t.poly([(b['sh'], 3), (5, -1), (4, 24), (b['waist'] + 0.5, 24), (b['chest'], 9)], vest)
    t.poly([(-7, -5), (-4, -5), (-4, 3), (-8, 1)], scale(vest, 1.1))
    t.poly([(7, -5), (4, -5), (4, 3), (8, 1)], scale(vest, 1.0))
    t.line(-5, -1, -4, 24, '#6f8f5a', 2)
    t.line(5, -1, 4, 24, '#6f8f5a', 2)


def shikamaru_shippuden_torso(t):
    t.poly([(-6, -6), (6, -6), (8, 1), (-8, 1)], '#2b2a2f')
    flak_vest(t)


SHIKAMARU = Character(
    'shikamaru', 'Shikamaru Nara', 'classic', '#ebbca2', '#3a2a1e', hair=shikamaru_hair,
    marks=shikamaru_marks,
    outfit=dict(top='#3e3a3d', pants='#4a4446', pants_len='capri', sleeve='short', sleeve_color='#9c9792',
                arm_band=('R', '#22336a'), pants_baggy=1.5, holster='L', sandals=NAVY_SANDAL, long_top=False),
    torso=shikamaru_torso, eyes='half', mouth='flat', color='#6f8f5a', speed=0.35, snack='shogi',
    brow_color='#25222a', size=0.9, head=1.08, hair_color='#25222a',
    jutsu=['shadow_possession', 'shadow_neck_bind', 'cloud_watch'],
    tagline='"What a drag..." IQ over 200, motivation under 2.')

SHIKAMARU_S = Character(
    'shikamaru_shippuden', 'Shikamaru Nara', 'shippuden', '#ebbca2', '#3a2a1e', hair=shikamaru_hair,
    marks=shikamaru_marks,
    outfit=dict(top='#2b2a2f', pants='#2b2a2f', sleeve='long', spiral='#a8322f', spiral_side='R',
                holster='L', shin=WRAP, shin_from=0.8, sandals='#232333', pants_baggy=1.4),
    torso=shikamaru_shippuden_torso, eyes='half', mouth='flat', color='#666c5c', speed=0.4,
    snack='shogi', brow_color='#25222a', hair_color='#25222a',
    jutsu=['shadow_possession', 'shadow_stitching'], tagline='Jonin strategist. Shadows that bind and stitch.')


# ======================================================================== INO
def ino_hair(b, f, long=False):
    hc = '#efe1a6'
    b.ellipse(7.5, 4, 8.8, 7, hc)
    tail = 34 + long * 10
    b.poly([(9, -2), (15, -3), (19, 6), (19, tail - 8), (16, tail), (14, tail - 10), (12, 6)], hc)
    cap(f, hc, 3)
    f.poly([(-1.5, 2), (8, 1), (6, 5), (5, 11 + long), (2, 13 + long), (-1.5, 12)], hc)
    f.spike(13, 2, -80, 6, 4, hc)
    f.rect(15, 3, 16, 9, hc)
    shine(f, 8, 12, 0, '#fffbe0')


def ino_torso(t, long_skirt=False):
    b = t.b
    purple = '#4d3456' if not long_skirt else '#523559'
    t.poly([(-b['chest'] + 0.5, 13), (b['chest'] - 0.5, 13), (b['waist'], 21), (-b['waist'], 21)], t.ch.skin)
    t.ellipse(0, 18, 0.4, 0.6, scale(t.ch.skin, 0.8))
    t.poly([(-5, -5), (5, -5), (6, 1), (-6, 1)], purple)
    t.rect(-5, -5, 5, -4.5, scale(purple, 1.3))
    t.rect(-b['chest'] + 0.5, 12, b['chest'] - 0.5, 13, scale(purple, 0.75))
    if not long_skirt:
        t.rect(-b['waist'] - 0.6, 20, b['waist'] + 0.6, 22, '#22336a')
        t.rect(-2.5, 20, 2.5, 22, METAL)
        t.poly([(-b['waist'] - 0.5, 22), (b['waist'] + 0.5, 22), (b['hip'] + 2.5, 42), (-b['hip'] - 2.5, 42)], purple)
        t.poly([(b['hip'] - 1, 30), (b['hip'] + 2.5, 30), (b['hip'] + 2.5, 42), (b['hip'] - 0.5, 42)],
               t.ch.skin)
    else:
        t.rect(-b['waist'] - 0.6, 21, b['waist'] + 0.6, 22.5, scale(purple, 0.75))
        skirt_panels(t, purple, 22, 46, gap=2.5, flare=4)


INO = Character(
    'ino', 'Ino Yamanaka', 'classic', SKIN, '#5d9cbc', hair=ino_hair,
    outfit=dict(top='#4d3456', pants='#4d3456', pants_len='none', pants_baggy=0.2, sleeve='none',
                forearm='#2e2534', long_top=True, sandals=NAVY_SANDAL),
    torso=ino_torso, build='female', mouth='smile', color='#4d3456', speed=0.55, snack='flower',
    brow_color='#c9b25a', size=0.9, head=1.08, hair_color='#efe1a6',
    jutsu=['mind_transfer', 'flower_storm'], tagline="Yamanaka clan's mind-walker (and florist).")

INO_S = Character(
    'ino_shippuden', 'Ino Yamanaka', 'shippuden', SKIN, '#5d9cbc', hair=lambda b, f: ino_hair(b, f, long=True),
    outfit=dict(top='#523559', pants='#523559', pants_len='none', pants_baggy=0.2, sleeve='none',
                forearm_R='#5f5a5e', forearm_mesh=True, thigh_wrap=WRAP, leg_mesh='#5f5a5e',
                long_top=True, sandals=NAVY_SANDAL),
    torso=lambda t: ino_torso(t, long_skirt=True), build='female', mouth='smile', color='#523559',
    speed=0.55, snack='flower', brow_color='#c9b25a', hair_color='#efe1a6',
    jutsu=['mind_transfer', 'healing'], tagline='Sensor, medic and mind-transfer specialist.')


# ====================================================================== CHOJI
def choji_hair(b, f, long=False):
    hc = '#9a5a34' if not long else '#a5603a'
    b.ellipse(7.5, 4.5, 9.5, 7.5, hc)
    if long:
        b.crown(7.5, 4, [(185, 13, 6), (165, 14, 6), (145, 14, 6), (122, 14, 6), (100, 13, 6),
                         (80, 13, 6), (58, 14, 6), (35, 14, 6), (15, 14, 6), (-5, 13, 6)], hc)
        b.poly([(-4, 4), (19, 4), (21, 22), (-6, 22)], hc)
    cap(f, hc, 4)
    bangs(f, (1, 14.5), 5, 4, 3, hc)
    f.rect(-1, 4, 0, 8, hc)
    f.rect(15, 4, 16, 8, hc)


def choji_classic_gear(c):
    """Bandana-style protector with two tufts of hair sticking out on top."""
    hc = '#9a5a34'
    c.spike(1.5, 0, 125, 7, 5, hc)
    c.spike(13.5, 0, 55, 7, 5, hc)
    headband(c, '#7a8fa8', y=0.5)


def choji_shippuden_gear(c):
    headband(c, '#8a2f2f', y=1.5)


def choji_marks(f):
    red = '#d0483a'
    for x in ((2, 13) if not f.side else (5, 15)):
        f.ellipse(x + 1, 15, 1.2, 1.0, red)
        f.ellipse(x + 1, 15, 0.5, 0.4, f.ch.skin)


def choji_torso(t):
    b = t.b
    shirt = '#e3d6c8'
    t.poly([(-8, 0), (8, 0), (9, 27), (-9, 27)], shirt)
    kanji_food(t, -3, 7, '#b8322f', 1.2)
    t.line(-8, 0, -9, 27, scale('#3b5650', 0.75), 2)
    t.line(8, 0, 9, 27, scale('#3b5650', 0.75), 2)
    t.poly([(-8, -6), (8, -6), (10, 1), (-10, 1)], '#ddd2d7')
    t.poly([(-10, 0), (-6, 0), (-7, 34), (-11, 34)], '#ddd2d7')
    t.line(-8, 2, -9, 33, scale('#ddd2d7', 0.85))


def choji_shippuden_torso(t):
    b = t.b
    red, plate_c = '#7a2d38', '#6b6771'
    for y in (2, 7, 12):
        t.rect(-b['chest'] + 1, y, b['chest'] - 1, y + 3.5, plate_c)
        t.rect(-b['chest'] + 1, y + 3.5, b['chest'] - 1, y + 4, scale(plate_c, 0.6))
        t.rect(-b['chest'] + 1, y, b['chest'] - 1, y + 0.6, scale(plate_c, 1.3))
    t.rect(-b['waist'] - 1, 18, b['waist'] + 1, 22, '#383843')
    t.poly([(-b['waist'] - 1, 22), (b['waist'] + 1, 22), (b['hip'] + 5, 50), (-b['hip'] - 5, 50)], red)
    t.rect(-1, 22, 1, 50, scale(red, 0.7))
    for s in (-1, 1):
        for y in (28, 34, 40):
            t.rect(s * (b['hip'] + 1), y, s * (b['hip'] + 4), y + 4, plate_c)


CHOJI = Character(
    'choji', 'Choji Akimichi', 'classic', '#efc5ad', '#2a2a30', hair=choji_hair, headgear=choji_classic_gear,
    marks=choji_marks,
    outfit=dict(top='#3b5650', pants='#4a3b3c', pants_len='knee', sleeve='short', forearm=WRAP,
                forearm_wrap=True, pants_baggy=1.3, holster='L', shin=WRAP, shin_from=0.3,
                sandals='#2c3f80'),
    torso=choji_torso, build='big', eyes='dot', mouth='smile', color='#3b5650', speed=0.4,
    snack='chips', brow_color='#7a4420', size=0.86, head=1.1, hair_color='#9a5a34',
    jutsu=['expansion', 'human_bullet_tank'], tagline="Big-boned, not fat! Don't take the last chip.")

CHOJI_S = Character(
    'choji_shippuden', 'Choji Akimichi', 'shippuden', '#efc5ad', '#2a2a30',
    hair=lambda b, f: choji_hair(b, f, long=True), headgear=choji_shippuden_gear, marks=choji_marks,
    outfit=dict(top='#7a2d38', pants='#383843', sleeve='long', sleeve_top='#6b6771', sleeve_top_len=0.35,
                forearm='#6b6771', shin=WRAP, shin_from=0.6, sandals='#232226', long_top=True),
    torso=choji_shippuden_torso, build='big', eyes='dot', mouth='flat', color='#7a2d38', speed=0.45,
    snack='chips', brow_color='#7a4420', hair_color='#a5603a',
    jutsu=['butterfly_mode', 'partial_expansion'], tagline='Akimichi heir in red armour, butterfly wings unlocked.')


# ===================================================================== HINATA
def hinata_hair(b, f, long=False):
    hc = '#2b2e52'
    b.ellipse(7.5, 4.5, 9, 7.5, hc)
    if long:
        long_curtain(b, hc, 40, flare=2, jag=False)
    else:
        b.poly([(-2, 4), (17, 4), (17, 13), (-2, 13)], hc)
    cap(f, hc, 4)
    f.rect(-1, 2, 16, 5, hc)
    for x in (1, 4, 7, 10, 13):
        f.ellipse(x, 6, 0.8, 0.8, hc)
    side_locks(f, hc, 15 if long else 13, 3, inset=-1)
    shine(f, 2, 8, 0.5, '#5a5fa0')


def hinata_torso(t, shippuden=False):
    b = t.b
    if shippuden:
        jacket, hood = '#a491a6', '#e1cec4'
        t.poly([(-8, -6), (8, -6), (10, 2), (5, 5), (0, 2), (-5, 5), (-10, 2)], hood)
        t.line(0, 2, 0, 27, scale(jacket, 0.65))
        t.rect(-b['hip'], 26.5, b['hip'], 27.5, scale(jacket, 0.8))
    else:
        jacket = '#e7d5cd'
        t.poly([(-8, -6), (8, -6), (10, 2), (-10, 2)], '#d6c3c6')
        t.rect(-3, -4, 2, -2.6, '#22336a')
        t.rect(-2, -4, 1, -2.6, METAL)
        t.line(0, 2, 0, 24, '#bea8b8')
        t.rect(-b['hip'] - 1, 24, b['hip'] + 1, 29, '#f6f2ee')
        for x in range(int(-b['hip']), int(b['hip']) + 1, 2):
            t.line(x, 24, x + 0.5, 29, '#dcd6d2')
        t.ellipse(b['chest'] - 2.5, 4, 1.5, 1.5, '#c99a5a')


HINATA = Character(
    'hinata', 'Hinata Hyuga', 'classic', SKIN_PALE, '#e6dff7', hair=hinata_hair,
    outfit=dict(top='#e7d5cd', pants='#363b56', pants_len='capri', sleeve='long', baggy=1.6,
                sleeve_color='#e7d5cd', cuff='#bea8b8', holster='L', sandals=NAVY_SANDAL),
    torso=hinata_torso, build='female', mouth='smile', color='#bea8b8', speed=0.45,
    snack='cinnamon_roll', pale_eyes=True, brow_color='#2b2e52', size=0.88, head=1.1,
    hair_color='#2b2e52', jutsu=['byakugan', 'gentle_fist'], tagline='Shy Byakugan heiress who never gives up.')

HINATA_S = Character(
    'hinata_shippuden', 'Hinata Hyuga', 'shippuden', SKIN_PALE, '#e6dff7',
    hair=lambda b, f: hinata_hair(b, f, long=True),
    outfit=dict(top='#a491a6', pants='#393b52', pants_len='capri', sleeve='long', baggy=1.3,
                holster='L', sandals=NAVY_SANDAL),
    torso=lambda t: hinata_torso(t, True), build='female', mouth='smile', color='#a491a6', speed=0.45,
    snack='cinnamon_roll', pale_eyes=True, brow_color='#2b2e52', hair_color='#2b2e52',
    jutsu=['byakugan', 'eight_trigrams', 'twin_lion_fists'],
    tagline='Gentle Fist master: 64 Palms and Twin Lion Fists.')


# ==================================================================== KAKASHI
def kakashi_hair(b, f):
    hc = '#d3d6dc'
    b.ellipse(7.5, 4.5, 9, 7, hc)
    b.crown(6, 3, [(178, 11, 6), (155, 14, 7), (132, 15, 7), (110, 14, 7), (88, 12, 7),
                   (62, 10, 6), (35, 8, 6)], hc)
    cap(f, hc, 3)
    bangs(f, (1, 7), 4, 3, 3, hc, tilt=-12)
    f.spike(13, 5, -75, 4, 3, hc)
    shine(f, 2, 7, -1.5, '#ffffff')


def kakashi_gear(c):
    """Slanted forehead protector over his left eye, plus the face mask."""
    cloth = '#242735'
    s = 1 if c.side else 0
    if c.pose and c.pose.eyes == 'sharingan':
        c.rect(-1, 1, 16, 4, cloth)
        plate(c, 3 + s, 1, 10)
    else:
        c.poly([(-1, 0), (17, 3), (17, 11), (-1, 4)], cloth)
        c.poly([(2 + s, 1), (14 + s, 3), (14 + s, 10.5), (2 + s, 5)], METAL)
        c.line(2 + s, 1, 14 + s, 3, METAL_HI)
        c.line(2 + s, 5, 14 + s, 10.5, METAL_LO)
        c.ellipse(8.5 + s, 5, 1.5, 1.0, METAL_LO)
        c.line(9.5 + s, 5.3, 11 + s, 4.4, METAL_LO)
    mask = '#262a38'
    c.poly([(-1, 10.6), (17, 10.6), (16, 13), (12, 15.2), (4, 15.2), (0, 13)], mask)
    c.line(-1, 10.6, 17, 10.6, scale(mask, 1.3))
    c.line(10 + s * 2, 10.8, 10.5 + s * 2, 12, scale(mask, 1.5))


KAKASHI = Character(
    'kakashi', 'Kakashi Hatake', 'jonin', SKIN_PALE, '#26262c', hair=kakashi_hair, headgear=kakashi_gear,
    outfit=dict(top='#242735', pants='#242735', sleeve='long', spiral='#a8322f', spiral_side='L',
                holster='L', shin=WRAP, shin_from=0.72, sandals='#22253a', pants_baggy=1.4),
    torso=lambda t: (t.poly([(-6, -6), (6, -6), (8, 1), (-8, 1)], '#242735'), flak_vest(t, '#676d60')),
    eyes='half', mouth='flat', color='#9aa3b5', speed=0.45, snack='book', brow_color='#8a90a0',
    hair_color='#d3d6dc', one_sharingan=True, jutsu=['lightning_blade', 'kamui'],
    tagline='Copy Ninja. Late, masked, reading Icha Icha.')


# ==================================================================== JIRAIYA
def jiraiya_hair(b, f):
    hc = '#ecebe8'
    b.ellipse(7.5, 4.5, 9.5, 7.5, hc)
    b.poly([(-3, 2), (18, 2), (22, 16), (20, 26), (23, 36), (17, 32), (15, 40), (11, 33),
            (8, 41), (4, 33), (0, 39), (-2, 31), (-7, 36), (-5, 24), (-7, 14)], hc)
    b.crown(7.5, 3, [(160, 11, 7), (125, 11, 7), (90, 10, 7), (55, 11, 7), (20, 11, 7)], hc)
    cap(f, hc, 3)
    side_locks(f, hc, 15, 3, inset=-1)


def jiraiya_gear(c):
    s = 1 if c.side else 0
    c.spike(3 + s, 1, 115, 6, 4, METAL)
    c.spike(12 + s, 1, 65, 6, 4, METAL)
    c.rect(1 + s, 1, 14 + s, 4, METAL)
    c.rect(1 + s, 1, 14 + s, 1.4, METAL_HI)
    c.rect(1 + s, 4, 14 + s, 4, METAL_LO)
    for dx, dy in ((0, 0), (0, 2), (2, 0), (3, 0), (4, 0), (2, 1), (4, 1), (2, 2), (3, 2), (4, 2)):
        c.rect(5.5 + s + dx, 1.6 + dy * 0.8, 5.5 + s + dx + 0.6, 1.6 + dy * 0.8 + 0.5, '#4a5260')


def jiraiya_marks(f):
    red = '#c8323c'
    xs = (5, 13) if not f.side else (7, 14)
    for x in xs:
        f.line(x, 13.8, x, 17.5, red)


def jiraiya_torso(t):
    b = t.b
    grey, red, mesh_c = '#71726a', '#853435', '#474848'
    mesh(t, -4, -4, 3, 4, mesh_c)
    t.poly([(-5, -2), (5, -2), (0, 9)], grey)
    t.line(-5, -2, 0, 9, scale(grey, 0.7))
    t.line(5, -2, 0, 9, scale(grey, 0.7))
    t.rect(-b['waist'] - 1, 19, b['waist'] + 1, 22, '#2e2a2c')
    t.poly([(-b['waist'] - 2, 22), (b['waist'] + 2, 22), (b['hip'] + 3, 36), (-b['hip'] - 3, 36)], grey)
    for s in (-1, 1):
        t.poly([(s * (b['sh'] + 1), 2), (s * 6, -1), (s * 7, 22), (s * 9, 56),
                (s * (b['hip'] + 6), 56), (s * (b['chest'] + 1), 10)], red)
        t.line(s * 6, -1, s * 9, 56, scale(red, 0.7))
        for y in (8, 38):
            t.ellipse(s * (b['chest'] - 0.5), y, 2.4, 2.4, '#d8b44a')
            t.ellipse(s * (b['chest'] - 0.5), y, 1.0, 1.0, red)


def jiraiya_scroll(t):
    t.rect(-26, 24, 26, 34, '#7a5638')
    t.rect(-26, 24, 26, 25.5, scale('#7a5638', 1.3))
    for x in (-26, 26):
        t.ellipse(x, 29, 2.6, 5.2, '#3a2e2a')
    for x in (-14, 14):
        t.rect(x, 24, x + 1.2, 34, '#4a3a2a')


JIRAIYA = Character(
    'jiraiya', 'Jiraiya', 'sannin', '#e2b99c', '#2a2a30', hair=jiraiya_hair, headgear=jiraiya_gear,
    marks=jiraiya_marks,
    outfit=dict(top='#71726a', pants='#71726a', pants_len='long', sleeve='long', baggy=2.0,
                pants_baggy=3.0, mesh_wrist='#474848', mesh_ankle='#474848', long_top=True,
                sandals='#9b2f2f', geta=True),
    torso=jiraiya_torso, back_item=jiraiya_scroll, build='brawny', mouth='smile', color='#853435',
    speed=0.5, snack='notebook', brow_color='#c9cdd6', hair_color='#ecebe8',
    jutsu=['toad_summoning', 'rasengan'], tagline='The Toad Sage. Legendary Sannin, "researcher", author.')


# ==================================================================== TSUNADE
def tsunade_hair(b, f):
    hc = '#e8cf8a'
    b.ellipse(7.5, 4.5, 9, 7.5, hc)
    b.poly([(-2, 8), (2, 10), (1, 30), (-1, 34), (-4, 30), (-4, 14)], hc)
    b.poly([(17, 8), (13, 10), (14, 30), (16, 34), (19, 30), (19, 14)], hc)
    cap(f, hc, 3)
    f.poly([(-1, 2), (7, 1), (3, 5), (1, 12), (-1, 12)], hc)
    f.poly([(16, 2), (8, 1), (12, 5), (14, 12), (16, 12)], hc)
    shine(f, 1, 5, 0, '#fff4c8')


def tsunade_marks(f):
    x = 9 if not f.side else 11
    f.poly([(x, 2.5), (x + 1.1, 3.8), (x, 5.1), (x - 1.1, 3.8)], '#8a4fd1')


def tsunade_torso(t):
    b = t.b
    green, grey, obi = '#486453', '#b8aaa0', '#2d3340'
    t.poly([(-6, -2), (6, -2), (2, 9), (-2, 9)], t.ch.skin)
    t.line(-6, -2, -2, 9, scale(grey, 0.75))
    t.line(6, -2, 2, 9, scale(grey, 0.75))
    t.rect(-b['waist'] - 0.5, 15, b['waist'] + 0.5, 21, obi)
    t.poly([(-b['waist'] - 0.5, 21), (b['waist'] + 0.5, 21), (b['hip'] + 1, 34), (-b['hip'] - 1, 34)], grey)
    for s in (-1, 1):
        t.poly([(s * (b['sh'] + 1), 2), (s * 6, -2), (s * 5, 20), (s * 7, 60), (s * (b['hip'] + 7), 60),
                (s * (b['chest'] + 1), 10)], green)
        t.line(s * 6, -2, s * 7, 60, '#2a3a30', 2)


TSUNADE = Character(
    'tsunade', 'Tsunade', 'sannin', SKIN, '#b07a3a', hair=tsunade_hair, marks=tsunade_marks,
    outfit=dict(top='#b8aaa0', pants='#292d36', pants_len='capri', sleeve='long', sleeve_color='#486453',
                baggy=2.4, flare=1.6, long_top=True, sandals='#1d1e22', heels=True),
    torso=tsunade_torso, build='female', mouth='smirk', color='#486453', speed=0.5, snack='sake',
    brow_color='#b89a50', hair_color='#e8cf8a', jutsu=['ground_smash', 'healing', 'katsuyu'],
    tagline='Fifth Hokage, legendary medic, legendary sucker (at gambling).')


# ===================================================================== ITACHI
def itachi_hair(b, f):
    hc = '#1d1e26'
    b.ellipse(7.5, 4.5, 8.8, 7, hc)
    b.poly([(5, 8), (10, 8), (9, 27), (7.5, 30), (6, 27)], hc)
    cap(f, hc, 3)
    side_locks(f, hc, 14, 3, inset=-1)
    f.spike(8, 5, -95, 4, 3, hc)
    shine(f, 3, 8, -1.5, '#3c3f52')


def itachi_marks(f):
    line = '#9c7464'
    xs = (4.5, 13.5) if not f.side else (8, 14.5)
    f.line(xs[0], 14.2, xs[0] + 1, 15.4, line)
    f.line(xs[1], 14.2, xs[1] - 1, 15.4, line)


def itachi_torso(t):
    b = t.b
    black, lining = '#22242a', '#6e2730'
    sway = 1.5 if t.pose and t.pose.phase % 1 >= 0.5 else 0
    hem = 74
    t.poly([(-b['sh'], 3), (-b['sh'] + 3, -0.5), (b['sh'] - 3, -0.5), (b['sh'], 3),
            (b['chest'] + 1, 10), (b['hip'] + 6 + sway, hem), (-b['hip'] - 6 + sway, hem),
            (-b['chest'] - 1, 10)], black)
    t.line(1, 2, 2 + sway * 0.5, hem, lining, 2)
    t.rect(-b['hip'] - 6 + sway, hem - 0.6, b['hip'] + 6 + sway, hem, lining)
    for x, y in ((-12, 14), (1, 30), (-13, 48)):
        cloud(t, x, y, 1.15)
    t.line(-6, 30, -8 + sway, 72, scale(black, 0.7))
    t.line(6, 30, 8 + sway, 72, scale(black, 0.7))


def itachi_collar(t):
    black, lining = '#22242a', '#6e2730'
    t.poly([(-9, -8), (9, -8), (11, 3), (-11, 3)], black)
    t.poly([(-1, -8), (9, -8), (11, 3), (1, 3)], scale(black, 0.85))
    t.line(-9, -8, 9, -8, lining, 2)
    t.line(0, -7, 1, 3, lining)


ITACHI = Character(
    'itachi', 'Itachi Uchiha', 'akatsuki', SKIN_PALE, '#d81a1a', hair=itachi_hair, marks=itachi_marks,
    collar=itachi_collar, headgear=lambda c: headband(c, '#242735', slash=True, tails=2),
    outfit=dict(top='#22242a', pants='#e9e6e2', sleeve='long', baggy=2.8, flare=1.8, long_top=True,
                sandals='#22253a', sleeve_lower='#22242a'),
    torso=itachi_torso, eyes='sharingan', mouth='flat', color='#a82a33', speed=0.45, snack='dango',
    brow_color='#1d1e26', hair_color='#1d1e26', jutsu=['crow_clone', 'amaterasu', 'susanoo'],
    tagline='Akatsuki. Sharingan always on. Loves dango.')


CHARACTERS = [NARUTO, NARUTO_S, SASUKE, SASUKE_S, SAKURA, SAKURA_S, SHIKAMARU, SHIKAMARU_S,
              INO, INO_S, CHOJI, CHOJI_S, HINATA, HINATA_S, KAKASHI, JIRAIYA, TSUNADE, ITACHI]
BY_ID = {c.id: c for c in CHARACTERS}
