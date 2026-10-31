"""Debug helper: tile frames onto a checkerboard, upscaled, for eyeballing."""

from PIL import Image


def sheet(frames, path, zoom=6, cols=8, label_rows=None):
    """frames: list of engine.Layer (may differ in size)."""
    cw = max(f.w for f in frames) * zoom
    chh = max(f.h for f in frames) * zoom
    rows = (len(frames) + cols - 1) // cols
    out = Image.new('RGBA', (cols * (cw + 4), rows * (chh + 4)), (40, 42, 54, 255))
    for i, fr in enumerate(frames):
        x, y = (i % cols) * (cw + 4), (i // cols) * (chh + 4)
        bg = Image.new('RGBA', (cw, chh), (90, 96, 112, 255))
        for yy in range(0, chh, zoom * 4):
            for xx in range(0, cw, zoom * 4):
                if (xx // (zoom * 4) + yy // (zoom * 4)) % 2:
                    bg.paste((104, 110, 126, 255), (xx, yy, xx + zoom * 4, yy + zoom * 4))
        im = fr.image().resize((fr.w * zoom, fr.h * zoom), Image.NEAREST)
        bg.alpha_composite(im, (0, chh - im.height))
        out.paste(bg, (x, y))
    out.save(path)
    return path
