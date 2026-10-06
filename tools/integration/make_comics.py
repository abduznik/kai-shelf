#!/usr/bin/env python3
"""Writes test comic archives for the integration servers (no dependencies).

    make_comics.py OUT_DIR

Produces, per OUT_DIR:
  komga/Series/{Alpha Saga,Beta Quest}/<name> Vol 01..03.cbz   (4 pages each)
  komga/Big/Series 000..229/<name> Vol 01.cbz                  (pagination stress)
  kavita/{Alpha Saga,Beta Quest}/<name> Vol 01..03.cbz
"""
import os
import struct
import sys
import zipfile
import zlib


def png(w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def cbz(path, pages):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, "w") as z:
        for i in range(pages):
            z.writestr(f"{i + 1:03d}.png", png(60, 90, (40 + i * 40 % 200, 80, 160)))


out = sys.argv[1]
for root in ("komga/Series", "kavita"):
    for series in ("Alpha Saga", "Beta Quest"):
        for vol in range(1, 4):
            cbz(f"{out}/{root}/{series}/{series} Vol {vol:02d}.cbz", 4)
for i in range(230):
    cbz(f"{out}/komga/Big/Series {i:03d}/Series {i:03d} Vol 01.cbz", 1)
