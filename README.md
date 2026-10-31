# d3d

**A complete, modular 3D extension for the [Defold](https://defold.com) game engine.**

d3d packages the rendering pipeline, PBR materials, lighting, shadows, cameras
and gameplay-ready prefabs that a 3D game needs, so a project can start at
"beautiful 3D scene" instead of "empty render script".

> Status: **foundation / design**. The API is not stable yet.

## Why

Defold ships excellent low-level 3D building blocks — model and mesh components,
a camera component, light components with a `LightBuffer`, glTF/PBR material
data, render targets and compute shaders — but it intentionally leaves the
render pipeline and the higher-level 3D workflow to the developer.

Two community projects show the two halves of the problem:

| Project | Strength | Gap |
| --- | --- | --- |
| [Scene3D](https://github.com/indiesoftby/defold-scene3d) | Cameras, controls, character/car controllers, prefabs, shadow experiments | Lighting is basic; materials are stylised, not PBR |
| [Illumination](https://github.com/astrochili/defold-illumination) | Ready-to-use forward lighting with many point/spot lights, normal/specular maps, fog | No render script, no shadows, no PBR, no post-processing |

d3d combines those strengths on top of the *current* Defold feature set, rather
than reimplementing what the engine now provides.

## Goals

- **Modern pipeline** — HDR forward rendering, PBR metallic-roughness,
  image-based lighting, shadow atlas, tone mapping and a small post FX stack.
- **Scalable lighting** — use Defold's light components, with clustered
  light culling when a scene needs more lights than a naive forward loop can
  afford.
- **Batteries included** — camera rigs, first-person/orbit/follow controllers,
  skybox, fog, debug views and photo mode.
- **Editor-first** — everything usable from the Defold editor with prefabs and
  sensible defaults; no custom build step for the common case.
- **Portable** — desktop, mobile and HTML5. No platform-specific code in the
  core path.
- **Documented** — a complete manual, API reference and runnable examples.

## Repository layout (planned)

```
d3d/                 the library itself (Lua, shaders, materials, prefabs)
examples/            a Defold project that exercises every feature
docs/                architecture, research notes and the offline Defold docs
docs/defold/         official Defold documentation mirror (see its README)
scripts/             tooling (docs sync, validation, release)
```

## References

The two reference projects are kept locally for study and are **not** part of
the build or of this repository's history:

- `defold-scene3d-main/` — MIT, Indiesoft LLC
- `defold-illumination-master/` — MIT, Roman Silin

They are listed in `.gitignore`. See `docs/RESEARCH.md` for the analysis.

## License

TBD.
