import argparse, sys

from blessed import Terminal
from PIL import Image


import numpy as np

SIXEL_CHARS = bytes(range(0x3F, 0x3F + 64))


def _rle(masks):
    if not masks:
        return ""

    a = np.frombuffer(masks, dtype=np.uint8)

    changes = np.flatnonzero(a[1:] != a[:-1]) + 1

    starts = np.empty(len(changes) + 1, dtype=np.intp)
    starts[0] = 0
    starts[1:] = changes

    ends = np.empty(len(changes) + 1, dtype=np.intp)
    ends[:-1] = changes
    ends[-1] = len(a)

    out = []

    for start, end in zip(starts, ends):
        v = int(a[start])
        n = int(end - start)

        c = chr(0x3F + v)

        if n >= 4:
            out.append(f"!{n}{c}")
        else:
            out.append(c * n)

    return "".join(out)


def _quantize(img, max_colors):
    p = img.convert("RGB").quantize(colors=max_colors)
    raw = p.tobytes()
    pal = p.getpalette()
    used = sorted(set(raw))
    lut = bytearray(256)
    for new, old in enumerate(used):
        lut[old] = new
    idx = raw.translate(bytes(lut))
    colors = [tuple(pal[c * 3 : c * 3 + 3]) for c in used]
    return colors, idx, *img.size


def encode_sixel(img, max_colors=256):
    colors, idx, w, h = _quantize(img, max_colors)
    out = ["\x1bPq", f'"1;1;{w};{h}']

    for i, (r, g, b) in enumerate(colors):
        out.append(f"#{i};2;{r * 100 // 255};{g * 100 // 255};{b * 100 // 255}")

    for y in range(0, h, 6):
        bh = min(6, h - y)
        masks = {}

        for dy in range(bh):
            row = (y + dy) * w
            bit = 1 << dy
            for x in range(w):
                c = idx[row + x]
                if c not in masks:
                    masks[c] = [0] * w
                masks[c][x] |= bit

        for i, c in enumerate(sorted(masks)):
            out.append(("" if i == 0 else "$") + f"#{c}" + _rle(masks[c]))

        out.append("-")

    out.append("\x1b\\")
    return "".join(out)


def encode_symbols(img, max_colors=256):
    colors, idx, w, h = _quantize(img, max_colors)
    if w == 0 or h < 2:
        return ""

    h -= h % 2
    E = "\x1b"
    lines = []

    for y in range(0, h, 2):
        fg = bg = None
        sb = []
        top = y * w
        bot = (y + 1) * w

        for x in range(w):
            a = colors[idx[top + x]]
            b = colors[idx[bot + x]]

            if a != fg:
                sb.append(f"{E}[38;2;{a[0]};{a[1]};{a[2]}m")
                fg = a

            if b != bg:
                sb.append(f"{E}[48;2;{b[0]};{b[1]};{b[2]}m")
                bg = b

            sb.append("\u2580")

        sb.append(f"{E}[0m")
        lines.append("".join(sb))

    return "\n".join(lines)


def _resize(img, width, height, symbols, cw, ch):
    ow, oh = img.size

    if symbols:
        if width is not None:
            w = width
            h = height if height is not None else max(1, round(width * cw * oh / (ch * ow)))
        elif height is not None:
            h = height
            w = max(1, round(height * ch * ow / (cw * oh)))
        else:
            return img
        return img.resize((w, h * 2), Image.LANCZOS)

    if width is not None:
        pw = width * cw
        ph = height * ch if height is not None else max(1, round(pw * oh / ow))
    elif height is not None:
        ph = height * ch
        pw = max(1, round(ph * ow / oh))
    else:
        return img

    return img.resize((pw, ph), Image.LANCZOS)


def print_image(term, path, width=None, height=None, max_colors=256):
    with Image.open(path) as img:
        img = img.convert("RGB")

        ch, cw = term.get_cell_height_and_width()
        if ch <= 0 or cw <= 0:
            ch, cw = 16, 8

        sixel = sys.stdout.isatty() and term.does_sixel(timeout=1.0)
        img = _resize(img, width, height, not sixel, cw, ch)

        s = (encode_sixel if sixel else encode_symbols)(img, max_colors)
        sys.stdout.write(s + ("" if sixel else "\n"))
        sys.stdout.flush()


def main():
    p = argparse.ArgumentParser(description="Print an image to the terminal (Sixel or Unicode half-block).")
    p.add_argument("path")
    p.add_argument("--width", "-w", type=int)
    p.add_argument("--height", "-H", type=int)
    p.add_argument("--colors", "-c", type=int, default=256)
    a = p.parse_args()

    if a.width is not None and a.width <= 0:
        p.error("--width 必须大于 0")
    if a.height is not None and a.height <= 0:
        p.error("--height 必须大于 0")
    if not 2 <= a.colors <= 256:
        p.error("--colors 必须在 2~256 之间")
    if a.width is None and a.height is None:
        p.error("至少需要指定 --width 或 --height")

    print_image(Terminal(), a.path, a.width, a.height, a.colors)


if __name__ == "__main__":
    main()
