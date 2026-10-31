"""Tiny pixel-art canvas: straight-alpha float RGBA layers with crisp primitives,
auto-shading and selective outlines. Everything is drawn without anti-aliasing."""

import math

import numpy as np
from PIL import Image, ImageDraw


def C(c, a=None):
    """Hex string / tuple -> RGBA tuple."""
    if isinstance(c, str):
        h = c.lstrip('#')
        c = (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
    elif len(c) == 3:
        c = (*c, 255)
    if a is not None:
        c = (c[0], c[1], c[2], a)
    return tuple(int(v) for v in c)


def scale(c, f):
    c = C(c)
    return (min(255, int(c[0] * f)), min(255, int(c[1] * f)), min(255, int(c[2] * f)), c[3])


def mix(a, b, t):
    a, b = C(a), C(b)
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(4))


class Layer:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.float32)

    # ---------------------------------------------------------------- basics
    def copy(self):
        n = Layer(self.w, self.h)
        n.px = self.px.copy()
        return n

    def put(self, x, y, c):
        x, y = int(math.floor(x)), int(math.floor(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x] = C(c)

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return tuple(self.px[y, x])
        return (0, 0, 0, 0)

    def rect(self, x0, y0, x1, y1, c):
        """Inclusive rectangle."""
        x0, x1 = sorted((int(x0), int(x1)))
        y0, y1 = sorted((int(y0), int(y1)))
        x0, y0 = max(0, x0), max(0, y0)
        x1, y1 = min(self.w - 1, x1), min(self.h - 1, y1)
        if x0 <= x1 and y0 <= y1:
            self.px[y0:y1 + 1, x0:x1 + 1] = C(c)

    def mask_fill(self, mask, c):
        self.px[mask] = C(c)

    def poly_mask(self, pts):
        img = Image.new('L', (self.w, self.h), 0)
        ImageDraw.Draw(img).polygon([(float(x), float(y)) for x, y in pts], fill=255)
        return np.array(img) > 127

    def poly(self, pts, c):
        self.mask_fill(self.poly_mask(pts), c)

    def ellipse_mask(self, cx, cy, rx, ry):
        ys, xs = np.mgrid[0:self.h, 0:self.w]
        return ((xs + 0.5 - cx) / max(rx, 0.01)) ** 2 + ((ys + 0.5 - cy) / max(ry, 0.01)) ** 2 <= 1.0

    def ellipse(self, cx, cy, rx, ry, c):
        self.mask_fill(self.ellipse_mask(cx, cy, rx, ry), c)

    def disc(self, cx, cy, r, c):
        self.ellipse(cx, cy, r, r, c)

    def ring(self, cx, cy, r, c, w=1.0):
        outer = self.ellipse_mask(cx, cy, r, r)
        inner = self.ellipse_mask(cx, cy, r - w, r - w)
        self.mask_fill(outer & ~inner, c)

    def line(self, x0, y0, x1, y1, c, w=1):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        off = (w - 1) // 2
        for i in range(n + 1):
            t = i / n
            x = math.floor(x0 + (x1 - x0) * t + 0.5)
            y = math.floor(y0 + (y1 - y0) * t + 0.5)
            self.rect(x - off, y - off, x - off + w - 1, y - off + w - 1, c)

    def polyline(self, pts, c, w=1):
        for a, b in zip(pts, pts[1:]):
            self.line(a[0], a[1], b[0], b[1], c, w)

    def grid(self, rows, palette, ox, oy):
        """ASCII art: palette maps char -> colour; other chars are skipped."""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch in palette:
                    self.put(ox + i, oy + j, palette[ch])

    # ------------------------------------------------------------ compositing
    def opaque(self, thresh=100):
        return self.px[..., 3] > thresh

    def over(self, other, ox=0, oy=0, opacity=1.0):
        """Composite `other` on top of self with its top-left at (ox, oy)."""
        ox, oy = int(ox), int(oy)
        sx0, sy0 = max(0, -ox), max(0, -oy)
        dx0, dy0 = max(0, ox), max(0, oy)
        w = min(other.w - sx0, self.w - dx0)
        h = min(other.h - sy0, self.h - dy0)
        if w <= 0 or h <= 0:
            return self
        src = other.px[sy0:sy0 + h, sx0:sx0 + w]
        dst = self.px[dy0:dy0 + h, dx0:dx0 + w]
        sa = src[..., 3:4] / 255.0 * opacity
        da = dst[..., 3:4] / 255.0
        oa = sa + da * (1 - sa)
        safe = np.where(oa > 0, oa, 1)
        rgb = (src[..., :3] * sa + dst[..., :3] * da * (1 - sa)) / safe
        dst[..., :3] = rgb
        dst[..., 3:4] = oa * 255.0
        return self

    def clip(self, mask):
        self.px[~mask] = 0
        return self

    def tint(self, color, t):
        c = np.array(C(color)[:3], np.float32)
        m = self.px[..., 3] > 0
        self.px[m, :3] = self.px[m, :3] * (1 - t) + c * t
        return self

    def fade(self, f):
        self.px[..., 3] *= f
        return self

    def flipped(self):
        n = self.copy()
        n.px = n.px[:, ::-1].copy()
        return n

    def scaled(self, k):
        """Nearest-neighbour scale (k may be fractional)."""
        nw, nh = max(1, int(round(self.w * k))), max(1, int(round(self.h * k)))
        ys = np.minimum((np.arange(nh) / k).astype(int), self.h - 1)
        xs = np.minimum((np.arange(nw) / k).astype(int), self.w - 1)
        n = Layer(nw, nh)
        n.px = self.px[ys][:, xs].copy()
        return n

    def rotated90(self, times=1):
        n = Layer(self.h if times % 2 else self.w, self.w if times % 2 else self.h)
        n.px = np.rot90(self.px, times).copy()
        return n

    # --------------------------------------------------------------- styling
    def autoshade(self, hi=1.12, lo=0.80):
        """Light from top-left: brighten top/left edges, darken bottom/right edges."""
        m = self.opaque()
        pad = np.pad(m, 1)
        top = ~pad[:-2, 1:-1]
        left = ~pad[1:-1, :-2]
        bottom = ~pad[2:, 1:-1]
        right = ~pad[1:-1, 2:]
        dark = m & (bottom | right)
        light = m & (top | left) & ~dark
        self.px[dark, :3] *= lo
        self.px[light, :3] = np.minimum(255, self.px[light, :3] * hi)
        return self

    def cel(self, right=2, bottom=0, lo=0.76, hi=1.10, rim=True, protect=None):
        """Cel shading for light from the upper left: a shadow band of `right`
        px along right edges (and `bottom` px along bottom edges), a 1px
        highlight along left/top edges. Shadows are cooled slightly."""
        m = self.opaque()
        shadow = np.zeros_like(m)
        if right:
            s = np.zeros_like(m)
            s[:, :-right] = m[:, right:]
            shadow |= m & ~s
        if bottom:
            s = np.zeros_like(m)
            s[:-bottom] = m[bottom:]
            shadow |= m & ~s
        if protect is not None:
            shadow &= ~protect
        cool = np.array([43, 32, 80], np.float32)
        px = self.px
        px[shadow, :3] = px[shadow, :3] * lo * 0.88 + cool * 0.12
        if rim:
            pad = np.pad(m, 1)
            edge = m & (~pad[1:-1, :-2] | ~pad[:-2, 1:-1]) & ~shadow
            if protect is not None:
                edge &= ~protect
            px[edge, :3] = np.minimum(255, px[edge, :3] * hi + 6)
        return self

    def cast_shadow(self, part, dx=1, dy=2, f=0.72, ox=0, oy=0):
        """Darken what is already on self where `part` (composited at ox, oy)
        would throw a shadow offset by (dx, dy). Call before compositing part."""
        m = part.opaque()
        sh = np.zeros((self.h, self.w), bool)
        x0, y0 = ox + dx, oy + dy
        sx0, sy0 = max(0, -x0), max(0, -y0)
        dx0, dy0 = max(0, x0), max(0, y0)
        w = min(part.w - sx0, self.w - dx0)
        h = min(part.h - sy0, self.h - dy0)
        if w > 0 and h > 0:
            sh[dy0:dy0 + h, dx0:dx0 + w] = m[sy0:sy0 + h, sx0:sx0 + w]
        sh &= self.opaque()
        cool = np.array([43, 32, 80], np.float32)
        self.px[sh, :3] = self.px[sh, :3] * f * 0.9 + cool * 0.1
        return self

    def outline(self, strength=0.32, color=None, thresh=100):
        """Selective outline: each empty pixel touching the sprite gets a darkened
        copy of its neighbours (or a fixed colour)."""
        m = self.opaque(thresh)
        h, w = m.shape
        acc = np.zeros((h, w, 3), np.float32)
        cnt = np.zeros((h, w), np.float32)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            sm = np.zeros_like(m)
            sp = np.zeros((h, w, 3), np.float32)
            ys = slice(max(0, dy), h + min(0, dy))
            yd = slice(max(0, -dy), h + min(0, -dy))
            xs = slice(max(0, dx), w + min(0, dx))
            xd = slice(max(0, -dx), w + min(0, -dx))
            sm[yd, xd] = m[ys, xs]
            sp[yd, xd] = self.px[ys, xs, :3]
            acc += sp * sm[..., None]
            cnt += sm
        edge = (~m) & (cnt > 0)
        if color is not None:
            self.px[edge] = C(color)
        else:
            avg = acc[edge] / cnt[edge][:, None]
            self.px[edge, :3] = avg * strength
            self.px[edge, 3] = 255
        return self

    def bbox(self):
        ys, xs = np.nonzero(self.px[..., 3] > 0)
        if len(xs) == 0:
            return None
        return xs.min(), ys.min(), xs.max(), ys.max()

    def image(self):
        return Image.fromarray(np.clip(self.px, 0, 255).astype(np.uint8), 'RGBA')


def blank(w=48, h=48):
    return Layer(w, h)


# 3x5 pixel font for speech bubbles ("CHA!", "Zz", "POOF").
FONT = {
    'A': ['.#.', '#.#', '###', '#.#', '#.#'], 'C': ['.##', '#..', '#..', '#..', '.##'],
    'H': ['#.#', '#.#', '###', '#.#', '#.#'], 'Z': ['###', '..#', '.#.', '#..', '###'],
    'z': ['...', '###', '.#.', '#..', '###'], '!': ['#', '#', '#', '.', '#'],
    'P': ['##.', '#.#', '##.', '#..', '#..'], 'O': ['.#.', '#.#', '#.#', '#.#', '.#.'],
    'F': ['###', '#..', '##.', '#..', '#..'], 'S': ['.##', '#..', '.#.', '..#', '##.'],
    'D': ['##.', '#.#', '#.#', '#.#', '##.'], 'G': ['.##', '#..', '#.#', '#.#', '.##'],
    'R': ['##.', '#.#', '##.', '#.#', '#.#'], 'E': ['###', '#..', '##.', '#..', '###'],
    'N': ['#.#', '###', '###', '###', '#.#'], 'T': ['###', '.#.', '.#.', '.#.', '.#.'],
    'Y': ['#.#', '#.#', '.#.', '.#.', '.#.'], 'I': ['###', '.#.', '.#.', '.#.', '###'],
    'K': ['#.#', '#.#', '##.', '#.#', '#.#'], 'U': ['#.#', '#.#', '#.#', '#.#', '###'],
    'W': ['#.#', '#.#', '###', '###', '#.#'], 'M': ['#.#', '###', '###', '#.#', '#.#'],
    'L': ['#..', '#..', '#..', '#..', '###'], 'B': ['##.', '#.#', '##.', '#.#', '##.'],
    '?': ['##.', '..#', '.#.', '...', '.#.'], ' ': ['.', '.', '.', '.', '.'],
    '.': ['.', '.', '.', '.', '#'], '-': ['...', '...', '###', '...', '...'],
    '\u2665': ['.#.#.', '#####', '#####', '.###.', '..#..'],
    'V': ['#.#', '#.#', '#.#', '#.#', '.#.'], 'X': ['#.#', '#.#', '.#.', '#.#', '#.#'],
    'J': ['..#', '..#', '..#', '#.#', '.#.'], 'Q': ['.#.', '#.#', '#.#', '##.', '.##'],
    '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'],
    '2': ['##.', '..#', '.#.', '#..', '###'], '3': ['##.', '..#', '.#.', '..#', '##.'],
    '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '##.', '..#', '##.'],
    '6': ['.##', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'],
    '8': ['###', '#.#', '###', '#.#', '###'], '9': ['###', '#.#', '###', '..#', '##.'],
}


def text(layer, s, x, y, c):
    for ch in s:
        g = FONT.get(ch, FONT[' '])
        for j, row in enumerate(g):
            for i, v in enumerate(row):
                if v == '#':
                    layer.put(x + i, y + j, c)
        x += len(g[0]) + 1
    return x


def text_width(s):
    return sum(len(FONT.get(ch, FONT[' '])[0]) + 1 for ch in s) - 1
