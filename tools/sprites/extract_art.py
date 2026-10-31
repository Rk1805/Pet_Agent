"""Cut each figure out of the character sheet with rembg's isnet-anime model.

Run from a virtualenv that has rembg[cpu] installed (the model, ~176 MB, is
downloaded to ~/.rembg on first use):

    python extract_art.py art/source/character_sheet.png art [ids...]

BOXES are the figures' rectangles on the sheet; EXCLUDE blanks out bits of
neighbouring figures that touch a cut-out."""
import sys
from collections import deque
import numpy as np
from PIL import Image
from rembg import remove, new_session

SHEET, OUT = sys.argv[1], sys.argv[2]
BOXES = {
    'naruto': (20, 58, 82, 258), 'sasuke': (102, 58, 150, 258), 'sakura': (176, 58, 216, 258),
    'shikamaru': (237, 58, 292, 258), 'ino': (308, 58, 355, 258), 'choji': (366, 58, 432, 258),
    'jiraiya': (502, 58, 586, 258), 'hinata': (600, 58, 645, 258),
    'naruto_shippuden': (4, 279, 100, 498), 'sasuke_shippuden': (100, 279, 163, 498),
    'sakura_shippuden': (163, 279, 229, 498), 'shikamaru_shippuden': (229, 279, 292, 498),
    'ino_shippuden': (293, 279, 352, 498), 'choji_shippuden': (360, 279, 432, 498),
    'kakashi': (437, 279, 495, 498), 'hinata_shippuden': (595, 279, 662, 498),
    'tsunade': (650, 279, 720, 498), 'itachi': (712, 279, 800, 498),
}
UP = 4
EXCLUDE = {'kakashi': [(484, 392, 520, 470), (489, 470, 520, 500)], 'itachi': [(690, 372, 724, 482)]}
sheet = Image.open(SHEET).convert('RGB')
sess = new_session('isnet-anime')


def largest_component(m):
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    best, best_n, cur = 0, 0, 0
    for y in range(h):
        for x in range(w):
            if m[y, x] and not lab[y, x]:
                cur += 1
                q = deque([(y, x)]); lab[y, x] = cur; n = 0
                while q:
                    cy, cx = q.popleft(); n += 1
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur; q.append((ny, nx))
                if n > best_n:
                    best, best_n = cur, n
    return lab == best


def center_component(m, box_local):
    """Component overlapping the figure's own box the most."""
    h, w = m.shape
    lab = np.zeros((h, w), np.int32)
    cur = 0
    for y in range(h):
        for x in range(w):
            if m[y, x] and not lab[y, x]:
                cur += 1
                q = deque([(y, x)]); lab[y, x] = cur
                while q:
                    cy, cx = q.popleft()
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < h and 0 <= nx < w and m[ny, nx] and not lab[ny, nx]:
                            lab[ny, nx] = cur; q.append((ny, nx))
    bx0, by0, bx1, by1 = box_local
    sub = lab[by0:by1, bx0:bx1]
    ids, counts = np.unique(sub[sub > 0], return_counts=True)
    return lab == ids[np.argmax(counts)]


only = sys.argv[3:] or list(BOXES)
for cid in only:
    x0, y0, x1, y1 = BOXES[cid]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    side = int(max(x1 - x0, y1 - y0) + 24)
    sx0, sy0 = int(cx - side / 2), int(cy - side / 2)
    crop = sheet.crop((sx0, sy0, sx0 + side, sy0 + side))
    big = crop.resize((1024, 1024), Image.LANCZOS)
    mask = remove(big, session=sess, only_mask=True, post_process_mask=False)
    mask = np.array(mask.resize(crop.size, Image.LANCZOS)).astype(np.float32) / 255
    bl = (x0 - sx0, y0 - sy0, x1 - sx0, y1 - sy0)
    # neighbours may share the crop: forbid columns well outside the box
    cols = np.arange(side)[None, :]
    mask *= ((cols >= bl[0] - 2) & (cols < bl[2] + 2))
    rows = np.arange(side)[:, None]
    mask *= (rows < bl[3] + 2)
    for ex0, ey0, ex1, ey1 in EXCLUDE.get(cid, []):
        mask[max(0, ey0 - sy0):max(0, ey1 - sy0), max(0, ex0 - sx0):max(0, ex1 - sx0)] = 0
    core = center_component(mask > 0.45, bl)
    grown = core.copy()
    for _ in range(2):
        g = grown.copy(); g[1:] |= grown[:-1]; g[:-1] |= grown[1:]; g[:, 1:] |= grown[:, :-1]; g[:, :-1] |= grown[:, 1:]
        grown = g
    alpha = np.clip((mask - 0.12) / 0.7, 0, 1) * grown
    rgba = np.dstack([np.array(crop), (alpha * 255).astype(np.uint8)])
    img = Image.fromarray(rgba, 'RGBA')
    img = img.crop(img.getbbox())
    img.save(f'{OUT}/{cid}.png')
    print(cid, img.size)
