# M1 implementation notes

Status of the first vertical slice, measured against `docs/ARCHITECTURE.md`.
Keep this file updated as milestones land.

## Implemented

| Area | Files |
| --- | --- |
| Frame graph | `d3d/d3d.render_script` |
| Configuration | `d3d/render/config.lua`, `[d3d]` section in `game.project` |
| CSM fitting | `d3d/render/csm.lua` |
| Targets | `d3d/render/targets.lua` |
| PBR shading | `d3d/shaders/pbr.vp`, `d3d/shaders/pbr.fp` |
| Shadow depth | `d3d/shaders/shadow_depth.*`, `d3d/materials/shadow_depth.material` |
| Tone mapping | `d3d/shaders/post.fp`, `d3d/materials/post.material` |
| Example | `example/main.collection`, `example/*.script`, generated assets |
| Tooling | `scripts/build.sh`, `tools/generate_assets.py`, `tools/generate_collection.py` |

### Frame

1. Read the built-in camera component (`camera.get_view/get_projection/...`).
2. Fit three cascades to the camera frustum slices and the sun direction.
3. Render one depth-only target per cascade with a material override.
4. Render opaque models into an `RGBA16F` colour target with a depth texture.
5. Tone map to the default framebuffer via a fullscreen quad.
6. Draw GUI/text on top.

Shadows are sampled with a 3×3 PCF kernel, a slope-scaled normal bias and a
global caster polygon offset. The cascade centre is snapped to the shadow texel
grid to reduce shimmering.

## Engine notes

- **Defold 1.14.0 only.** The project uses the modern shader pipeline
  (`#version 140`, SPIR-V), `render.set_camera`, `graphics.*` constants,
  texture-backed render targets and `LightBuffer`.
- The official directional-shadow example in the docs calls a four-argument
  `diffuse_lambert` overload that does not exist in the 1.14.0 built-in
  `lighting.glsl` (it has three arguments). d3d intentionally implements its own
  lighting and does not include `/builtins/materials/lighting.glsl`.
- `/builtins/assets/gltf/quad_2x2.gltf` does not exist in bob 1.14.0; only a
  1×1 `quad.gltf` is bundled. The example generates its own clip-space
  `fullscreen_quad.gltf`.
- Embedded **components** do not accept a `scale3` field in 1.14.0. The ground
  mesh is generated at its final size instead of scaling a cube.
- `graphics.TEXTURE_FORMAT_RGBA16F` is checked at target creation; the fallback
  is `RGBA` with clipping in the tone mapper.

## Known limitations (deliberately deferred)

- **Runtime output is not verified yet.** The project compiles cleanly with
  bob; there is no GPU smoke test or screenshot in the repository.
- Normal mapping is a placeholder: it perturbs the normal without a proper TBN
  basis. The example uses a flat normal map, so it is not visible.
- One directional shadow caster; point/spot shadows are not rendered.
- Three separate 1024² depth targets instead of one atlas; the architecture
  calls for a 2×2 atlas in M2.
- No sky, bloom, FXAA, SSAO, IBL or clustered lighting yet.
- No quality tiers, mobile performance tuning or HTML5 test.
- Alpha blending is not a separate pass; only opaque/cutout materials.
- `MAX_LIGHT_COUNT` is 32 and must match `[light] max_count` in `game.project`.

## Next steps

1. Verify the frame on a GPU (desktop Linux first, then HTML5) and add a
   screenshot to the README.
2. Replace the placeholder TBN with derivative-based normal mapping.
3. Add a shadow atlas and 5×5 PCF for the high tier.
4. Add bloom + FXAA and a proper sky.
5. Port the Scene3D camera rigs (first-person, orbit with input, photo mode) as
   scripts that drive the built-in camera component.
