"""Real pose drawings -> animation frames.

Put drawings in art/<character id>/<animation id>.png, e.g.

    art/naruto_shippuden/walk.png      8 side-view walk-cycle poses, left to right
    art/naruto_shippuden/ramen.png     eating poses
    art/naruto_shippuden/rasengan.png  the jutsu, pose by pose

Each file is one strip of poses in order, facing right, on a plain white (or
transparent) background. A grid also works (e.g. a sprite sheet); say so in
art/<id>/frames.json. Whenever a drawing exists it replaces the generated
puppet animation for that id; everything else keeps working as before.

art/<id>/frames.json (optional) tunes each animation:
    {"walk":  {"hold": 1},                 # ticks (1/10 s) each pose stays on screen
     "sleep": {"height": 0.38},            # median pose height vs the standing art
     "rasengan": {"hold": 2, "frames": 6}, # expected number of poses in the strip
     "idle":  {"grid": [5, 5]}}            # columns x rows for sprite sheets
"""

import json
from pathlib import Path

import numpy as np
from PIL import Image

from body import W, standing_height
from engine import Layer

ROOT = Path(__file__).resolve().parents[2] / 'art'
DEFAULT_HEIGHT = {'sleep': 0.38}
DEFAULT_HOLD = {'walk': 1, 'drag': 1}


def drawings_for(ch):
    d = ROOT / ch.id
    if not d.is_dir():
        return {}, {}
    cfg = {}
    if (d / 'frames.json').exists():
        cfg = json.loads((d / 'frames.json').read_text())
    return {p.stem: p for p in d.glob('*.png')}, cfg


def remove_background(im):
    """Alpha from the image if it has one, else flood-fill the plain background
    in from the borders and soften/un-tint the edge pixels."""
    a = np.asarray(im.convert('RGBA')).astype(np.float32)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    if (border[:, 3] < 250).mean() > 0.5:
        return a
    rgb = a[..., :3]
    bg = np.median(border[:, :3], axis=0)
    dist = np.sqrt(((rgb - bg) ** 2).sum(-1))
    similar = dist < 38
    reach = np.zeros_like(similar)
    reach[0], reach[-1], reach[:, 0], reach[:, -1] = similar[0], similar[-1], similar[:, 0], similar[:, -1]
    while True:
        grown = reach.copy()
        grown[1:] |= reach[:-1]
        grown[:-1] |= reach[1:]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= similar
        if (grown == reach).all():
            break
        reach = grown
    alpha = np.where(reach, 0.0, 1.0)
    edge = (~reach) & (dist < 90)
    near = np.zeros_like(reach)
    near[1:] |= reach[:-1]
    near[:-1] |= reach[1:]
    near[:, 1:] |= reach[:, :-1]
    near[:, :-1] |= reach[:, 1:]
    soft = edge & near
    alpha[soft] = np.clip((dist[soft] - 20) / 70, 0.15, 1.0)
    k = alpha[..., None]
    a[..., :3] = np.where(k > 0, (rgb - bg * (1 - k)) / np.maximum(k, 1e-3), 0)
    a[..., 3] = alpha * 255
    return np.clip(a, 0, 255)


def split(a, grid=None, expected=None):
    """Return the individual pose arrays."""
    h, w = a.shape[:2]
    if grid:
        cols, rows = grid
        cw, rh = w / cols, h / rows
        cells = [a[int(r * rh):int((r + 1) * rh), int(c * cw):int((c + 1) * cw)]
                 for r in range(rows) for c in range(cols)]
        return [c for c in cells if (c[..., 3] > 40).sum() > 50]
    occupied = (a[..., 3] > 40).sum(0) > 1
    runs, start, gap = [], None, 0
    for x, on in enumerate(occupied):
        if on:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= 3:
                runs.append((start, x - gap))
                start, gap = None, 0
    if start is not None:
        runs.append((start, w - 1))
    runs = [r for r in runs if r[1] - r[0] > w * 0.02]
    # poses drawn close together merge into one wide run: split those evenly
    if len(runs) > 1 and not expected:
        widths = sorted(r[1] - r[0] for r in runs)
        typical = widths[len(widths) // 2]
        out = []
        for x0, x1 in runs:
            k = max(1, round((x1 - x0) / typical))
            step = (x1 - x0 + 1) / k
            out += [(int(x0 + i * step), int(x0 + (i + 1) * step) - 1) for i in range(k)]
        runs = out
    if expected and len(runs) != expected:
        step = w / expected
        runs = [(int(i * step), int((i + 1) * step) - 1) for i in range(expected)]
    return [a[:, x0:x1 + 1] for x0, x1 in runs]


def crop(a):
    ys, xs = np.nonzero(a[..., 3] > 20)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def to_frames(ch, path, opts):
    poses = [crop(p) for p in split(remove_background(Image.open(path)), opts.get('grid'),
                                    opts.get('frames'))]
    if not poses:
        return None, 0
    standing = standing_height(ch)
    target = standing * opts.get('height', DEFAULT_HEIGHT.get(path.stem, 1.0))
    s = target / float(np.median([p.shape[0] for p in poses]))
    imgs = []
    for p in poses:
        im = Image.fromarray(p.astype(np.uint8), 'RGBA')
        im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
        imgs.append(im)
    stage_w = max(W, max(i.width for i in imgs) + 8)
    stage_w = int(np.ceil(stage_w / (W / 4)) * (W / 4))
    stage_h = max(W, max(i.height for i in imgs) + 8)
    stage_h = int(np.ceil(stage_h / (W / 4)) * (W / 4))
    hold = opts.get('hold', DEFAULT_HOLD.get(path.stem, 2))
    frames = []
    for im in imgs:
        canvas = Image.new('RGBA', (stage_w, stage_h), (0, 0, 0, 0))
        canvas.alpha_composite(im, (int(stage_w / 2 - im.width / 2), stage_h - im.height))
        L = Layer(stage_w, stage_h)
        L.px = np.asarray(canvas).astype(np.float32).copy()
        frames.extend([L] * hold)
    return frames, (stage_w - W) // 2


def apply_drawings(ch, built):
    """Swap in drawn frames for every animation that has a drawing."""
    files, cfg = drawings_for(ch)
    used = []
    for a in built:
        key = 'front' if a.id == 'front' and 'front' in files else a.id
        if key == 'front' and 'idle' in files:
            key = 'idle'
        if key in files:
            frames, anchor = to_frames(ch, files[key], cfg.get(key, {}))
            if frames:
                a.frames, a.anchor_x = frames, anchor
                used.append(a.id)
    return used
