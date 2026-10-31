# d3d architecture

Status: **proposed** · Target: Defold **1.14+**, modern (SPIR-V) shader pipeline.

## 1. Scope

d3d is a Defold library extension: Lua, GLSL, materials, render targets and
prefabs that a project adds as a ZIP dependency. It owns the 3D render pipeline
and the high-level 3D workflow; it does not fork the engine.

**In scope for 1.0**

- HDR forward renderer with a modern GLSL PBR material.
- Cascaded shadow maps for one directional light.
- Point and spot lights from Defold's built-in `LightBuffer`.
- Sky, distance/height fog, tone mapping, bloom, FXAA.
- Camera rigs driving the built-in camera component.
- Quality tiers, debug views, and a complete example project.
- Documentation and API reference.

**Later**

- Image-based lighting with prefiltered environment maps.
- Clustered light culling for scenes with hundreds of lights.
- Spot/point shadow maps, SSAO, colour grading LUTs.
- Optional native acceleration (C++) for cluster/shadow culling.

**Non-goals**

- Replacing the Defold editor, model importer or physics.
- A full game framework: gameplay controllers ship as optional prefabs, not as
  the core.
- Supporting the legacy ES2 shader pipeline.

## 2. Principles

1. **Engine-first.** Use the camera component, light components, `LightBuffer`,
   glTF `PbrMaterial` data and render targets that Defold already provides.
   Write only what the engine intentionally leaves out.
2. **One pipeline, three quality tiers.** The frame graph is identical on every
   platform; tiers change formats, resolutions and effect toggles, not code
   paths that can silently diverge.
3. **Materials are the public surface.** A developer should get a correct result
   by assigning `d3d/materials/pbr.material` and dropping in a camera and a
   light. Lua configuration is optional.
4. **No legacy GLSL.** Every shader starts with `#version 140`, uses `in/out`,
   `texture()`, and uniform blocks. This is required for Metal/Vulkan/SPIR-V.
5. **Frame-graph state is owned by the render script**; gameplay modules
   communicate through messages and small, pure Lua helpers. No `_G` state like
   `render3d.lua` from Scene3D.
6. **Measure before optimising.** Clustered lighting and native code are
   justified by captures from the example scenes, not by speculation.

## 3. Package layout

```
d3d/
  d3d.render_script          # entry point referenced from game.project
  d3d.render                 # render resources (materials, post targets)
  render/
    pipeline.lua             # frame graph, pass orchestration
    targets.lua              # HDR/shadow/bloom targets, resize handling
    shadows.lua              # CSM fitting and cascade rendering
    post.lua                 # bloom, tonemap, FXAA passes
    frame.lua                # constant buffer assembly
    config.lua               # quality tiers and runtime settings
  materials/
    pbr.material             # explicit maps/factors
    pbr_gltf.material        # consumes the glTF PbrMaterial block
    unlit.material
    sky.material
    shadow_depth.material
    shadow_depth_cutout.material
    post_tonemap.material
    post_bloom_downsample.material
    post_bloom_upsample.material
    post_fxaa.material
    debug_overlay.material
  shaders/
    pbr.vs / pbr.fs
    shadow_depth.vs / shadow_depth.fs
    sky.vs / sky.fs
    fullscreen.vs
    tonemap.fs / bloom.fs / fxaa.fs
    includes/
      brdf.glsl
      shadows.glsl
      fog.glsl
      tonemap.glsl
      frame.glsl
  camera/
    camera_fp.script
    camera_orbit.script
    camera_follow.script
    camera_photo.script
  sun/
    sun.script               # registers a directional light + CSM settings
  prefabs/
    camera.prefab, sun.prefab, player.prefab, ...
  helpers/
    math3d.lua               # based on Scene3D's MIT math3d
    frustum.lua
  api/
    d3d.script_api
```

Materials and shaders live under `d3d/` rather than `builtins/` so the library
is self-contained and every path resolves from the project root.

## 4. Frame graph

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Shadow depth pass (optional)                              │
│    target: shadow atlas, depth-only, texture-backed          │
│    view:   sun, orthographic per cascade                     │
│    draws:  d3d_shadow predicate, shadow_depth material       │
├──────────────────────────────────────────────────────────────┤
│ 2. Scene pass → HDR target (RGBA16F + depth texture)         │
│    a. opaque   (d3d_model)   depth write, back-face cull      │
│    b. sky      (d3d_sky)     depth test LEQUAL, no write      │
│    c. alpha    (d3d_alpha)   depth test, no depth write       │
├──────────────────────────────────────────────────────────────┤
│ 3. Post → default framebuffer                                │
│    bloom (optional) → ACES tonemap + exposure + gamma        │
│    → FXAA (optional)                                         │
├──────────────────────────────────────────────────────────────┤
│ 4. GUI / text on top of the final image                      │
└──────────────────────────────────────────────────────────────┘
```

The scene target is recreated when the window size changes (the example in
`docs/defold/manuals/render.md` shows the pattern). On devices where RGBA16F
render targets are unavailable, the HDR tier degrades to RGBA8 and the tonemap
still works, with clipping above 1.0.

### Predicates and tags

| Predicate | Material tag | Contents |
| --- | --- | --- |
| `d3d_shadow` | `d3d_shadow` | Depth-only override for shadow casters |
| `d3d_model` | `d3d_model` | Opaque PBR/unlit models |
| `d3d_alpha` | `d3d_alpha` | Alpha-blended models (phase 2) |
| `d3d_sky` | `d3d_sky` | Skybox |
| `d3d_post` | `d3d_post` | Fullscreen post-processing quad |
| `gui`, `text` | built-ins | UI |

The shadow pass renders the `d3d_model` predicate with
`render.enable_material("d3d_shadow_depth")`, so the same model components are
used for both passes. This is the material-override pattern from Defold's
official directional-shadow example.

## 5. Shadows

- **One directional light**, selected by `d3d/sun/sun.script`. The script posts
  its URL and shadow settings to `@render:`; the render script reads the light's
  world rotation and builds the cascades. No hand-placed shadow camera is
  required (unlike the official example), but a `debug_shadow_camera` option can
  visualize a cascade.
- **Cascades:** 3 by default (1–4 configurable). Practical split scheme with a
  logarithmic blend (`lambda = 0.75`), plus a 10% overlap blend between
  cascades.
- **Atlas:** a single depth texture, 2×2 tiles at 2048² (high), 1024² (low).
  Each cascade renders into its tile with `render.set_viewport()`; the tile
  offset/scale is passed to the receiver shader.
- **Stability:** fit each cascade to the camera frustum slice, snap the
  orthographic center to a shadow texel, and use a bounding sphere for the
  light rotation so the map does not shimmer when the camera rotates.
- **Bias:** front-face culling for closed meshes, polygon offset at caster time,
  slope-scaled normal bias at receiver time. Defaults follow the official
  example, then are tuned per quality tier.
- **Filtering:** 3×3 PCF by default, 5×5 on high, hard comparison on low.
  Nearest-filtered depth texture and explicit comparisons.
- **Cutout shadows:** a `shadow_depth_cutout` variant samples albedo alpha and
  discards, for foliage and fences.
- Skinned/morph/instanced casters need vertex-deformation variants; tracked as
  a separate task because Defold's depth override cannot reproduce them
  automatically.

## 6. Lighting and materials

- Shaders declare the built-in `LightBuffer`:

  ```glsl
  #define MAX_LIGHT_COUNT 32
  uniform LightBuffer {
      vec4 light_info;
      Light lights[MAX_LIGHT_COUNT];
  };
  ```

  `MAX_LIGHT_COUNT` is a compile-time material variant (8/16/32/64), so mobile
  projects do not pay for 64 lights. The active count comes from
  `light_info.w`; ambient from `light_info.xyz`.
- **BRDF:** Cook-Torrance with GGX NDF, Smith height-correlated visibility and
  Schlick Fresnel; metallic-roughness workflow; diffuse = `(1 - F) *
  albedo / π`; energy compensation for multiple scattering (phase 2).
- **Material data:** `pbr_gltf.material` reads the engine-provided
  `PbrMaterial` block (factors, texture-use flags, alpha mode, double-sided).
  `pbr.material` exposes the same parameters as user constants for hand-authored
  meshes. Textures are assigned explicitly on the model component; Defold does
  not auto-bind glTF textures yet.
- **Light types:** directional (with CSM), point (inverse-square with range
  windowing), spot (inner/outer cone from `params.z/w`).
- **Fog:** exponential squared distance fog plus optional height fog, applied
  in the PBR shader before tone mapping, with the sky using the same function.
- **IBL (phase 2):** irradiance cubemap for diffuse, prefiltered mip chain for
  specular, BRDF LUT. The default environment is generated offline; custom
  cubemaps are supplied by the project.
- **Gamma:** all lighting in linear space; sRGB decode on input textures where
  needed; ACES + gamma encode at present time.

## 7. Post-processing

- **Bloom:** threshold (soft knee) → 3-level downsample → upsample with
  additive blend. Targets are half/quarter/eighth resolution.
- **Tone mapping:** exposure (EV) → ACES fitted → gamma 2.2. Optional
  `d3d.set_exposure()` and auto-exposure later.
- **FXAA:** quality 3.11 on medium/high; off on low.
- **Debug:** cascades, shadow map, normals, light complexity, overdraw. Debug
  views are compiled behind `#ifdef D3D_DEBUG` where possible and selected by a
  material constant at runtime.

## 8. Camera workflow

The built-in camera component owns view/projection. d3d ships scripts that move
the game object:

- `camera_fp.script` — first-person yaw/pitch, pointer lock, head bob hooks.
- `camera_orbit.script` — third-person orbit with collision-aware distance.
- `camera_follow.script` — smooth follow with damping and look-ahead.
- `camera_photo.script` — free-fly debug camera (Scene3D's photo mode).

The render script picks the camera:

```lua
render.set_camera(self.camera_url, { use_frustum = true })
```

with `self.camera_url` set by a `d3d.set_camera` message. If no camera is
registered, the render script falls back to the last enabled camera and logs a
warning.

## 9. Public API (draft)

```lua
-- Runtime control (messages to @render:)
d3d.set_quality("low" | "medium" | "high")
d3d.set_exposure(ev)
d3d.set_fog({ color = vmath.vector3(...), density = 0.01, height = 0.0 })
d3d.set_shadows({ enabled = true, cascades = 3, resolution = 2048 })
d3d.set_camera(url)
d3d.set_sun(url)

-- Helpers (pure Lua)
d3d.math3d.*
d3d.camera.screen_to_world(...)
d3d.debug.show_cascades(true)
```

Messages are hashed once; every setter is idempotent. The render script never
requires gameplay scripts, so a project can use d3d without any d3d Lua module.

## 10. Conventions

- Metric units (1 unit = 1 m), Y up, forward `(0, 0, -1)`, right-handed.
- 4 spaces, `snake_case` for files and Lua identifiers.
- Shader uniform blocks: `D3DFrame` (per-frame), `D3DMaterial` (per-material
  fallback), `LightBuffer`, `PbrMaterial`. No loose scalar uniforms in modern
  shaders.
- All paths absolute from the project root (`/d3d/...`).
- Every public module has a `.script_api` entry and a manual page.

## 11. Milestones

| Milestone | Deliverable | Exit criterion |
| --- | --- | --- |
| M0 | Repo, docs mirror, architecture, research | Docs searchable offline; design reviewed |
| M1 | HDR target, PBR material, one directional light, CSM, ACES, example scene | Scene renders correctly on desktop and HTML5 |
| M2 | Point/spot lights, fog, sky, bloom, FXAA, quality tiers | 60 fps at 1080p on the reference scene |
| M3 | IBL, camera rigs, prefabs, debug views, manual | A new project can start from a prefab in < 10 min |
| M4 | Clustered lighting, spot shadows, SSAO, release | 100+ lights at stable frame time |

## 12. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Defold 1.14 APIs still evolving (`TEXTURE_BIT`, render targets) | Pin the minimum version, keep a compatibility shim in `render/targets.lua` |
| RGBA16F unsupported on some WebGL2/mobile devices | Runtime format check; RGBA8 fallback tier |
| Uniform-block size limits with 64 lights + 4 shadow matrices | Material variants by light count; pack matrices into vec4 rows if needed |
| Skinned/cutout shadow casters | Dedicated depth material variants; document the limitation |
| No engine in the dev environment | Download `bob.jar` + a JRE, add `scripts/build.sh` and CI |
| Metal/Vulkan shader differences | Modern GLSL only, no `gl_FragColor`, no implicit conversions; validate with `glslangValidator` and `bob` |

## 13. Open decisions

1. **Native core**: pure Lua/GLSL first. Native code only if profiling shows the
   CPU cluster/cascade work is the bottleneck. This keeps HTML5 support and
   removes the C++ toolchain from contributors' path.
2. **Minimum Defold version**: 1.14.0 unless a needed API is older. The modern
   shader pipeline alone requires 1.9.2+.
3. **License**: to be chosen by the repository owner before the first public
   release.
