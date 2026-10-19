#!/usr/bin/env python3
"""Regenerates Support/AppIcon.icns offline (requires Pillow). Writes only inside the repo."""
import io, os, struct
from PIL import Image, ImageDraw

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024

def render(size=S):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Vertical blue gradient squircle.
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / S
        gd.line([(0, y), (S, y)], fill=(int(40 + 20 * t), int(110 - 40 * t), int(220 - 60 * t), 255))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([100, 100, 924, 924], radius=185, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # Folder.
    d.rounded_rectangle([230, 330, 520, 440], radius=36, fill=(255, 255, 255, 235))
    d.rounded_rectangle([230, 390, 794, 730], radius=48, fill=(255, 255, 255, 250))
    # Bar chart inside the folder ("dashboard").
    for i, h in enumerate([120, 200, 160, 250]):
        x = 300 + i * 105
        d.rounded_rectangle([x, 690 - h, x + 70, 690], radius=14, fill=(52, 120, 220, 255))
    # Green shield badge (read-only).
    cx, cy = 760, 300
    d.ellipse([cx - 120, cy - 120, cx + 120, cy + 120], fill=(255, 255, 255, 255))
    d.ellipse([cx - 100, cy - 100, cx + 100, cy + 100], fill=(46, 160, 90, 255))
    d.line([(cx - 50, cy + 2), (cx - 12, cy + 42), (cx + 55, cy - 40)], fill=(255, 255, 255, 255), width=28, joint="curve")
    return img.resize((size, size), Image.LANCZOS) if size != S else img

def png(size):
    buf = io.BytesIO()
    render(size).save(buf, "PNG")
    return buf.getvalue()

ENTRIES = [("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128),
           ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024)]

def main():
    cache, body = {}, b""
    for code, size in ENTRIES:
        data = cache.setdefault(size, png(size))
        body += code.encode() + struct.pack(">I", len(data) + 8) + data
    out = os.path.join(REPO, "Support", "AppIcon.icns")
    with open(out, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(body) + 8) + body)
    render(512).save(os.path.join(REPO, "Support", "AppIcon-preview.png"))
    print("wrote", out)

if __name__ == "__main__":
    main()
