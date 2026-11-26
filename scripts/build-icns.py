#!/usr/bin/env python3
"""Build assets/AppIcon.icns from assets/AppIcon-1024.png.

The box (and some CI images) may not have iconutil or sips, so this writes
a standard macOS ICNS container directly: PNG images for 16, 32, 64, 128,
256, 512, 1024, plus the @2x types (ic11–ic14 / ic10).

Downsampling uses premultiplied-alpha area averaging so the squircle edge
stays black and does not pick up a light fringe.

Usage (from the repo root, or from anywhere):
    python3 scripts/build-icns.py
"""

from __future__ import annotations

import struct
import sys
from io import BytesIO
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "AppIcon-1024.png"
DST = ROOT / "assets" / "AppIcon.icns"

# type, pixel size. Overlapping pixel sizes share one PNG blob.
# icp4/5/6 = 16/32/64 @1x; ic07–ic10 = 128–1024; ic11–ic14 = 16/32/128/256 @2x.
ICON_TYPES: list[tuple[bytes, int]] = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 64),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),  # 512@2x
    (b"ic11", 32),    # 16@2x
    (b"ic12", 64),    # 32@2x
    (b"ic13", 256),   # 128@2x
    (b"ic14", 512),   # 256@2x
]


def downsample_rgba(im: Image.Image, size: int) -> Image.Image:
    """Area-downsample with premultiplied alpha to avoid fringe on corners."""
    if im.size == (size, size):
        return im.convert("RGBA")
    arr = np.asarray(im.convert("RGBA"), dtype=np.float32)
    premul = arr.copy()
    a = arr[..., 3:4]
    premul[..., :3] = arr[..., :3] * (a / 255.0)
    out = cv2.resize(premul, (size, size), interpolation=cv2.INTER_AREA)
    oa = out[..., 3:4]
    rgb = np.zeros_like(out[..., :3])
    np.divide(out[..., :3], oa / 255.0, out=rgb, where=oa > 0.5)
    out[..., :3] = np.clip(rgb, 0, 255)
    out[..., 3] = np.clip(out[..., 3], 0, 255)
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def png_bytes(im: Image.Image) -> bytes:
    buf = BytesIO()
    im.save(buf, format="PNG", optimize=True, compress_level=9)
    return buf.getvalue()


def write_icns(png_by_size: dict[int, bytes], dest: Path) -> None:
    entries: list[tuple[bytes, bytes]] = []
    for typ, size in ICON_TYPES:
        payload = png_by_size[size]
        entries.append((typ, payload))

    header_size = 8
    toc_size = header_size + header_size * len(entries)
    file_length = header_size + toc_size + sum(header_size + len(p) for _, p in entries)

    parts: list[bytes] = [b"icns", struct.pack(">I", file_length)]
    parts.append(b"TOC ")
    parts.append(struct.pack(">I", toc_size))
    for typ, payload in entries:
        parts.append(typ)
        parts.append(struct.pack(">I", header_size + len(payload)))
    for typ, payload in entries:
        parts.append(typ)
        parts.append(struct.pack(">I", header_size + len(payload)))
        parts.append(payload)

    data = b"".join(parts)
    if len(data) != file_length:
        raise RuntimeError(f"icns length mismatch: wrote {len(data)}, declared {file_length}")
    dest.write_bytes(data)


def fringe_ok(im: Image.Image) -> tuple[bool, str]:
    arr = np.asarray(im)
    mid = (arr[..., 3] > 10) & (arr[..., 3] < 245)
    if not mid.any():
        return True, "no mid-alpha pixels"
    mx = int(arr[..., :3][mid].max())
    return mx == 0, f"mid-alpha RGB max={mx}"


def main() -> int:
    if not SRC.is_file():
        print(f"missing source PNG: {SRC}", file=sys.stderr)
        return 1
    master = Image.open(SRC).convert("RGBA")
    if master.size != (1024, 1024):
        print(f"expected 1024x1024 RGBA, got {master.size} {master.mode}", file=sys.stderr)
        return 1
    ok, note = fringe_ok(master)
    if not ok:
        print(f"source has light fringe ({note})", file=sys.stderr)
        return 1

    sizes = sorted({size for _, size in ICON_TYPES})
    png_by_size: dict[int, bytes] = {}
    for size in sizes:
        im = downsample_rgba(master, size)
        ok, note = fringe_ok(im)
        if not ok:
            print(f"{size}px has light fringe ({note})", file=sys.stderr)
            return 1
        png_by_size[size] = png_bytes(im)
        print(f"  {size:4d}px  {len(png_by_size[size]):6d} bytes  {note}")

    DST.parent.mkdir(parents=True, exist_ok=True)
    write_icns(png_by_size, DST)
    print(f"wrote {DST} ({DST.stat().st_size} bytes, {len(ICON_TYPES)} icon types)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
