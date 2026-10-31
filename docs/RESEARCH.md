# Research: what to learn from Scene3D and Illumination

This note records how the two reference projects work, what is worth adopting,
and what must change for a modern Defold (1.14+) 3D extension.

Both projects are local-only checkouts (see `.gitignore`):

- `defold-scene3d-main/` — MIT, Indiesoft LLC
- `defold-illumination-master/` — MIT, Roman Silin

## 1. Illumination — forward lighting without a render script

### How it works

- `illumination.lua` builds a **32×32 RGBA8 data texture** (`data.png`). Pixels
  0–4 hold environment data (light count, fog, ambient, sun colour/direction,
  fog colour); every following group of 5 pixels describes one light
  (`illumination.lua:15-29, 140-195`).
- Positions are quantised to 24-bit integers over a ±2048 world and decoded in
  the shader (`illumination.lua:163-180`, `model.fp:39-49`).
- There is **no render script**. A mesh material samples `DATA_TEXTURE` and
  loops over every light in the fragment shader (`model.fp:229-304`). Fog,
  ambient, directional light and up to ~200 point/spot lights are all evaluated
  per fragment.
- Light components (`light_point.go`, `light_spot.go`) register themselves with
  the module; `resource.set_texture()` uploads the buffer when something moves.
- It supports diffuse, normal, specular and baked-light/emission maps, plus
  linear/radial fog. An “editor fallback” shades geometry when the data texture
  is empty (`model.fp:129-145`).

### Strengths worth keeping

- **Editor workflow**: drop a light prefab, tweak colour/radius/cutoff, done.
- Light budget communicated honestly: ~200 supported, 20–30 comfortable.
- Normal/specular maps and fog are integrated into one material.
- Zero render-script setup — attractive for small projects.

### Problems to fix

- **Legacy GLSL only** (`attribute`, `varying`, `texture2D`, `gl_FragColor`).
  The modern Defold pipeline requires `#version 140`, `in/out`, `texture()` and
  uniform blocks. See `docs/defold/manuals/shader.md`.
- **No culling**: every fragment loops over every light. Cost scales with
  `pixels × lights`, the main reason 20–30 lights is the practical limit.
- **No shadows, no PBR, no HDR, no post-processing.**
- Data texture is rebuilt in Lua and re-uploaded; fine for a demo, not for
  hundreds of moving lights.
- Lighting model is ad-hoc (Blinn-Phong-like specular, no energy conservation).

### What d3d takes

- The idea of lightweight, prefab-based lights — but implemented with Defold's
  native Light components instead of a custom packed texture.
- The editor-fallback trick, so materials look reasonable before any lights or
  render script are configured.
- Normal/specular/emission map support, rebuilt around a metallic-roughness
  PBR model.

## 2. Scene3D — a 3D framework around one render script

### How it works

- A single `scene3d/render/render3d.render_script` draws `model`, `sky`, `tile`,
  `particle`, `gui` and `text` predicates. It supports several viewports by
  looping over `render3d.viewports` and setting viewport/view/projection per
  view (`render3d.render_script:50-84`).
- Camera state lives in the global Lua module `scene3d/render/render3d.lua`
  (position, front/right/up, FOV, near/far, viewports). The
  `camera3d.script` writes to it every frame (`camera3d.script:21-44`);
  `light_directional.script` writes ambient/sun/fog values
  (`light_directional.script:33-51`).
- Materials are stylised, vertex-colour or texture based, with a simple
  directional + ambient term and linear fog (`basic_color.fp`). They are
  **legacy GLSL** and do no gamma correction.
- A **native C++ extension** provides frustum culling (`scene3d.frustum_*`),
  a `prerender` callback (used to update the camera after physics), mesh
  visibility helpers and simplex noise (`scene3d/api/scene3d.script_api`).
- Prefabs cover primitives, buildings, icons, a character controller, car
  physics, blob shadows, sky sphere, photo mode and camera rigs.

### Strengths worth keeping

- **Game-ready layer**: first-person/orbit cameras, character and vehicle
  controllers, prototyping prefabs, photo mode, debug helpers.
- Late-update / prerender pattern: camera follows physics-updated objects
  without one-frame lag.
- Metric units, OpenGL right-handed coordinates, forward `(0, 0, -1)` —
  consistent with Defold and glTF.
- Clear separation between render-script state and gameplay scripts.

### Problems to fix

- Predates Defold's camera component, light components, `LightBuffer`, PBR
  material data and the modern shader pipeline.
- Lighting is global directional + ambient only; point/spot lights, shadows and
  image-based lighting are absent. The `shadows` scene is blob shadows, not
  shadow mapping.
- No HDR, tone mapping, bloom, AA or colour grading.
- Global mutable module state makes multiple cameras/scenes awkward.

### What d3d takes

- The camera-rig and late-update ideas (adapted to the built-in camera
  component).
- The prefab-first philosophy and metric/coordinate conventions.
- `math3d.lua` as the starting point for the math helpers (MIT, with
  attribution) — ported and extended, not copy-pasted blindly.

## 3. What Defold 1.14 gives us for free

Verified against the mirrored docs in `docs/defold/`:

| Feature | Where | Consequence for d3d |
| --- | --- | --- |
| Camera component, `camera` Lua API, `render.set_camera()` | `manuals/camera.md` | Don't write a camera component; write **rigs** that drive the built-in one |
| Light components (ambient/directional/point/spot) and `LightBuffer` | `manuals/light.md` | Don't pack lights into a texture; consume the engine buffer |
| glTF PBR material data (`PbrMaterial` block) | `manuals/physically-based-rendering.md` | PBR shader can read authored metallic/roughness/emissive data |
| Modern GLSL / SPIR-V (`#version 140`) | `manuals/shader.md` | New shaders only; no legacy syntax |
| Offscreen targets: RGBA16F, depth textures, MSAA | `manuals/render.md`, `apis/render-lua.md` | HDR pipeline, shadow maps, post FX are possible without native code |
| Material override via `render.enable_material()` | `manuals/render.md` | One depth-only material can render every shadow caster |
| Compute shaders (technical preview) | `manuals/compute.md` | Future GPU light culling; not a v1 dependency |

Defold deliberately does **not** ship a PBR lighting model, shadow maps,
post-processing or clustered lighting. That is exactly the space d3d fills.

## 4. Conclusions

1. Build on the engine's camera and light components; do not duplicate them.
2. Target the modern shader pipeline exclusively. Legacy GLSL from both
   references cannot be reused as-is.
3. The renderer must be HDR and offscreen from day one; retrofitting HDR after
   materials and post FX exist is painful.
4. Shadow mapping is the single biggest visual upgrade over both references and
   must be in the first milestone.
5. Scene3D's gameplay layer is valuable but orthogonal. Ship the renderer
   first, then port camera rigs and controllers as optional prefabs.
6. Clustered lighting is a phase-2 optimisation; the engine `LightBuffer`
   (64 lights by default) is enough for the first release.
