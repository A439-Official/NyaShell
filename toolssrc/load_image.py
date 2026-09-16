from PIL import Image
import numpy as np
import json
import argparse


def image_to_json(path, width=None, height=None):
    with Image.open(path) as img:
        orig_w, orig_h = img.size
        if width and height:
            new_w, new_h = width, height
        elif width:
            new_w = width
            new_h = int(orig_h * width / orig_w)
        elif height:
            new_h = height
            new_w = int(orig_w * height / orig_h)
        else:
            new_w, new_h = orig_w, orig_h
        img = img.resize((new_w, new_h), Image.LANCZOS)
        arr = np.asarray(img.convert("RGBA"), dtype=np.uint8)
    h, w, _ = arr.shape
    packed = arr.view(np.uint32).reshape(h, w)
    uniques, inverse = np.unique(packed, return_inverse=True)
    inverse = inverse.reshape(h, w)
    ub = uniques.view(np.uint8).reshape(-1, 4)
    colors = ["#%02x%02x%02x%02x" % (int(r), int(g), int(b), int(a)) for r, g, b, a in ub]
    data = inverse.T.tolist()
    return {"colors": colors, "data": data}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert an image to a JSON list.")
    parser.add_argument("path", type=str, help="Path to the image file.")
    parser.add_argument("--width", "-w", type=int, default=None, help="Target width.")
    parser.add_argument("--height", type=int, default=None, help="Target height.")
    args = parser.parse_args()

    print(json.dumps(image_to_json(args.path, width=args.width, height=args.height)))
