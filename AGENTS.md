# AGENTS.md

Guidance for AI agents working on **d3d**, a modular 3D extension for the
[Defold](https://defold.com) engine.

## Read this first

1. `README.md` — what d3d is and its goals.
2. `docs/ARCHITECTURE.md` — frame graph, layout, conventions, milestones.
3. `docs/RESEARCH.md` — what was learned from Scene3D and Illumination and why
   the architecture differs.
4. `docs/IMPLEMENTATION.md` — current M1 status and known gaps.

## Repository state

The project is at **M1: working vertical slice**. The following are implemented
and compile with Defold 1.14.0 / bob 1.14.0:

- `d3d/d3d.render_script` — HDR scene pass, three shadow cascades, ACES post.
- `d3d/render/{config,csm,targets}.lua` — configuration, CSM fitting, targets.
- `d3d/shaders/{pbr,shadow_depth,fullscreen,post}.*` — modern GLSL only.
- `d3d/materials/{pbr,shadow_depth,post}.material`.
- `example/` — orbit camera, moving sun, PBR cubes, generated assets.

Not implemented yet: IBL, bloom, FXAA, spot/point shadow maps, clustered
lighting, camera input rigs, mobile quality tiers.

The two reference projects in the repository root are **local study copies**:

- `defold-scene3d-main/` (MIT)
- `defold-illumination-master/` (MIT)

They are git-ignored, are not part of the build, and must not be modified as a
shortcut. When reusing code, port it to modern Defold APIs and keep the MIT
attribution in the file header and `docs/RESEARCH.md`.

## Defold documentation

A complete offline mirror lives in `docs/defold/` (444 Markdown files). Use it
instead of guessing engine APIs.

- `docs/defold/llms-full.txt` — everything in one 3.4 MB file; best for broad
  `grep`/`rg` searches.
- `docs/defold/manuals/<topic>.md` — manuals; start here.
- `docs/defold/apis/<namespace>-lua.md` — Lua API reference.
- `docs/defold/examples/<category>/<name>.md` — official examples with source.

Most relevant files for this project:

```
manuals/render.md
manuals/physically-based-rendering.md
manuals/light.md
manuals/shader.md
manuals/camera.md
manuals/compute.md
apis/render-lua.md
apis/graphics-lua.md
apis/camera-lua.md
examples/render/directional_light_shadows.md
examples/render/post_processing.md
```

Never edit `docs/defold/` by hand. Refresh it with:

```bash
./scripts/update-defold-docs.sh
```

## Target engine facts

- Target: **Defold 1.14.0+**, modern SPIR-V shader pipeline.
- Shaders must start with `#version 140`, use `in`/`out`, `texture()` and
  uniform blocks. No `attribute`, `varying`, `texture2D` or `gl_FragColor`.
- Use the built-in **camera component**, **light components** and `LightBuffer`;
  do not build parallel camera/light systems.
- Use `graphics.*` constants (`graphics.STATE_DEPTH_TEST`,
  `graphics.BUFFER_TYPE_COLOR0_BIT`, …) in new render-script code.
- Coordinate system: Y up, forward `(0, 0, -1)`, right-handed, 1 unit = 1 metre.

## Conventions

- 4 spaces, `snake_case` for files, variables and functions.
- Absolute resource paths from the project root (`/d3d/...`).
- One concern per Lua module; the render script only orchestrates.
- Public API changes require updating `d3d/api/d3d.script_api` and the manual.
- Keep shaders in `d3d/shaders/`, shared GLSL in `d3d/shaders/includes/`.
- Prefer `render.enable_material()` overrides and predicates over duplicating
  materials on components.

## Validation

Build the example with the pinned toolchain:

```bash
./scripts/build.sh
```

The first run downloads JDK 25 and `bob.jar` into `.tools/` (git-ignored). A
successful build ends with `100% Building` and produces
`build/default/*.shbundlec`. Always check the exit code; bob prints some errors
without a non-zero status when output is piped.

Faster local checks:

```bash
# Lua syntax
luajit -bl path/to/file.lua >/dev/null

# GLSL syntax (approximate; Defold wraps uniforms in blocks)
glslangValidator -S frag path/to/file.fs
```

The example has not been run inside a full engine in this environment yet, so
treat visual output as unverified until a runtime capture is added.

Do not commit `bob.jar`, JRE archives, `build/` or `.tools/`.

## Commits

- Small, focused commits with an imperative summary.
- Do not commit the reference checkouts, build output or downloaded toolchains.
- The git remote is `https://github.com/Mateus-M-Reis/d3d.git` (branch `main`).
