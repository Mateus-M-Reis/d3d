#!/usr/bin/env python3
"""Generate example/main.collection.

Defold's collection format nests protobuf-text strings inside protobuf text,
which is easy to get wrong by hand. Building the strings and JSON-quoting them
at each level keeps the escaping unambiguous.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "example" / "main.collection"


def quoted(text: str) -> str:
    """A protobuf-text string literal (JSON string escaping is compatible)."""
    return json.dumps(text, ensure_ascii=True)


def model_component(component_id: str, mesh: str, material: str,
                    textures: list[tuple[str, str]], name: str) -> str:
    lines = [
        f'mesh: "{mesh}"',
        f'name: "{name}"',
        "materials {",
        '  name: "default"',
        f'  material: "{material}"',
    ]
    for sampler, texture in textures:
        lines += [
            "  textures {",
            f'    sampler: "{sampler}"',
            f'    texture: "{texture}"',
            "  }",
        ]
    lines += ["}", ""]
    return "\n".join(lines)


def embedded_model(component_id: str, mesh: str, material: str,
                   textures: list[tuple[str, str]], name: str,
                   position=(0, 0, 0), scale=(1, 1, 1)) -> str:
    data = model_component(component_id, mesh, material, textures, name)
    block = [
        "embedded_components {",
        f'  id: "{component_id}"',
        '  type: "model"',
        f"  data: {quoted(data)}",
        f"  position {{ x: {position[0]} y: {position[1]} z: {position[2]} }}",
    ]
    if scale != (1, 1, 1):
        block.append(f"  scale3 {{ x: {scale[0]} y: {scale[1]} z: {scale[2]} }}")
    block += ["}", ""]
    return "\n".join(block)


def embedded_camera() -> str:
    data = "aspect_ratio: 1.0\nfov: 0.7854\nnear_z: 0.1\nfar_z: 100.0\nauto_aspect_ratio: 1\n"
    return (
        "embedded_components {\n"
        '  id: "camera"\n'
        '  type: "camera"\n'
        f"  data: {quoted(data)}\n"
        "}\n"
    )


def embedded_light(component_id: str, light_type: str, color, intensity: float) -> str:
    fields = [
        "  struct {",
        "    fields {",
        '      key: "color"',
        "      value {",
        "        list {",
    ]
    for component in color:
        fields.append(f"          values {{ number: {component} }}")
    fields += [
        "        }",
        "      }",
        "    }",
        "    fields {",
        '      key: "intensity"',
        "      value {",
        f"        number: {intensity}",
        "      }",
        "    }",
        "  }",
        "",
    ]
    data = "data {\n" + "\n".join(fields) + "\n" + "}\n"
    return (
        "embedded_components {\n"
        f'  id: "{component_id}"\n'
        f'  type: "{light_type}"\n'
        f"  data: {quoted(data)}\n"
        "}\n"
    )


def component(component_id: str, path: str, properties: dict | None = None) -> str:
    lines = [
        "components {",
        f'  id: "{component_id}"',
        f'  component: "{path}"',
    ]
    for key, value in (properties or {}).items():
        lines += [
            "  properties {",
            f'    id: "{key}"',
            f'    value: "{value}"',
            "    type: PROPERTY_TYPE_NUMBER",
            "  }",
        ]
    lines += ["}", ""]
    return "\n".join(lines)


def instance(instance_id: str, game_object: str, rotation=None) -> str:
    lines = [
        "embedded_instances {",
        f'  id: "{instance_id}"',
        f"  data: {quoted(game_object)}",
    ]
    if rotation:
        lines.append(
            "  rotation { x: %s y: %s z: %s w: %s }" % rotation
        )
    lines += ["}", ""]
    return "\n".join(lines)


PBR = "/d3d/materials/pbr.material"
PBR_TEXTURES = [
    ("albedo_texture", "/example/assets/checker.png"),
    ("normal_texture", "/example/assets/flat_normal.png"),
]


def main() -> None:
    # Camera rig.
    camera = component("orbit", "/example/orbit_camera.script", {"speed": "6.0"})
    camera += embedded_camera()

    # Sun and ambient light. The rotation defines the initial light direction.
    sun = component("sun", "/example/sun.script", {"speed": "2.0"})
    sun += embedded_light("directional_light", "directional_light", (1.0, 0.96, 0.9), 2.2)
    sun += embedded_light("ambient_light", "ambient_light", (0.55, 0.65, 0.85), 0.35)

    # Scene: a ground slab and five cubes.
    scene = component("scene", "/example/scene.script", {})
    scene += embedded_model(
        "ground", "/example/assets/ground.gltf", PBR, PBR_TEXTURES, "ground",
        position=(0, -0.1, 0),
    )
    cubes = [
        ("cube1", (-2.2, 0.5, 0.0)),
        ("cube2", (0.0, 0.5, 0.0)),
        ("cube3", (2.2, 0.5, 0.0)),
        ("cube4", (0.0, 1.5, -1.8)),
        ("cube5", (1.6, 0.5, 2.0)),
    ]
    for cube_id, position in cubes:
        scene += embedded_model(
            cube_id, "/example/assets/cube.gltf", PBR, PBR_TEXTURES, cube_id,
            position=position,
        )

    # Fullscreen presentation quad.
    post_data = model_component(
        "post", "/example/assets/fullscreen_quad.gltf",
        "/d3d/materials/post.material", [], "post",
    )
    post = (
        "embedded_components {\n"
        '  id: "post"\n'
        '  type: "model"\n'
        f"  data: {quoted(post_data)}\n"
        "}\n"
    )

    collection = "name: \"main\"\nscale_along_z: 1\n\n"
    collection += instance("camera", camera)
    collection += instance(
        "sun", sun,
        rotation=(-0.39713126, -0.3099755, -0.14454396, 0.8516507),
    )
    collection += instance("scene", scene)
    collection += instance("post", post)

    OUT.write_text(collection, encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
