#!/usr/bin/env python3
"""Generate the small binary assets used by the d3d example project.

Everything is written as plain glTF 2.0 with an embedded buffer, so the files
are self-contained, diffable and reproducible without a DCC tool.
"""

from __future__ import annotations

import base64
import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "example" / "assets"


def pack_floats(values: list[tuple[float, ...]]) -> bytes:
    out = bytearray()
    for value in values:
        out += struct.pack("<" + "f" * len(value), *value)
    return bytes(out)


def write_gltf(path: Path, positions, normals, uvs, indices, name: str) -> None:
    pos_data = pack_floats(positions)
    norm_data = pack_floats(normals)
    uv_data = pack_floats(uvs)
    idx_data = struct.pack("<" + "H" * len(indices), *indices)

    # Keep every bufferView 4-byte aligned.
    def align(data: bytes) -> bytes:
        return data + b"\x00" * ((4 - len(data) % 4) % 4)

    pos_data = align(pos_data)
    norm_data = align(norm_data)
    uv_data = align(uv_data)
    idx_data = align(idx_data)

    blob = pos_data + norm_data + uv_data + idx_data
    offsets = [0, len(pos_data), len(pos_data) + len(norm_data),
               len(pos_data) + len(norm_data) + len(uv_data)]
    lengths = [len(pos_data), len(norm_data), len(uv_data), len(idx_data)]

    gltf = {
        "asset": {"version": "2.0", "generator": "d3d asset generator"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": name}],
        "meshes": [{
            "name": name,
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": 3,
                "material": 0,
            }],
        }],
        "materials": [{
            "name": "default",
            "pbrMetallicRoughness": {
                "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.7,
            },
        }],
        "accessors": [
            {
                "bufferView": 0, "componentType": 5126, "count": len(positions),
                "type": "VEC3",
                "min": [min(p[i] for p in positions) for i in range(3)],
                "max": [max(p[i] for p in positions) for i in range(3)],
            },
            {"bufferView": 1, "componentType": 5126, "count": len(normals), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(uvs), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets[i], "byteLength": lengths[i],
             "target": 34963 if i == 3 else 34962}
            for i in range(4)
        ],
        "buffers": [{
            "byteLength": len(blob),
            "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode("ascii"),
        }],
    }

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(gltf, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)")


def box(name: str, size: tuple[float, float, float]) -> None:
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    faces = [
        ([(hx, -hy, hz), (hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz)], (1, 0, 0)),
        ([(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)], (-1, 0, 0)),
        ([(-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz), (-hx, hy, -hz)], (0, 1, 0)),
        ([(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)], (0, -1, 0)),
        ([(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)], (0, 0, 1)),
        ([(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)], (0, 0, -1)),
    ]
    positions, normals, uvs, indices = [], [], [], []
    for verts, normal in faces:
        base = len(positions)
        positions.extend(verts)
        normals.extend([normal] * 4)
        uvs.extend([(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)])
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    write_gltf(ASSETS / f"{name}.gltf", positions, normals, uvs, indices, name.title())


def cube() -> None:
    box("cube", (1.0, 1.0, 1.0))
    box("ground", (12.0, 0.2, 12.0))


def fullscreen_quad() -> None:
    positions = [(-1.0, -1.0, 0.0), (1.0, -1.0, 0.0), (1.0, 1.0, 0.0), (-1.0, 1.0, 0.0)]
    normals = [(0.0, 0.0, 1.0)] * 4
    uvs = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
    indices = [0, 1, 2, 0, 2, 3]
    write_gltf(ASSETS / "fullscreen_quad.gltf", positions, normals, uvs, indices, "FullscreenQuad")


def png_chunk(kind: bytes, data: bytes) -> bytes:
    chunk = kind + data
    return struct.pack(">I", len(data)) + chunk + struct.pack(">I", zlib.crc32(chunk) & 0xFFFFFFFF)


def write_png(path: Path, width: int, height: int, pixel) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type: none
        for x in range(width):
            raw.extend(pixel(x, y))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    data = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    print(f"wrote {path.relative_to(ROOT)} ({len(data)} bytes)")


def textures() -> None:
    def checker(x, y):
        # 8x8 checks, two neutral grays with a little colour variation.
        c = 205 if ((x // 8) + (y // 8)) % 2 == 0 else 140
        return (c, c, c, 255)

    write_png(ASSETS / "checker.png", 64, 64, checker)

    def flat_normal(x, y):
        return (128, 128, 255, 255)

    write_png(ASSETS / "flat_normal.png", 8, 8, flat_normal)

    write_png(ASSETS / "white.png", 4, 4, lambda x, y: (255, 255, 255, 255))
    write_png(ASSETS / "black.png", 4, 4, lambda x, y: (0, 0, 0, 255))


def main() -> None:
    cube()
    fullscreen_quad()
    textures()


if __name__ == "__main__":
    main()
