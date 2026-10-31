# Defold documentation — offline mirror

Official Defold documentation, mirrored in the LLM-friendly Markdown format
published by the Defold Foundation.

- Source index: <https://defold.com/llms.txt>
- Combined bundle: <https://defold.com/llms-full.txt>
- Upstream sources: <https://github.com/defold/doc>
- Downloaded: 2026-10-31

## Contents

| Path | What it is | Files |
| --- | --- | --- |
| `llms-full.txt` | Manuals + API reference + examples in one 3.4 MB file | 1 |
| `llms.txt` | Top-level index with links to the three indexes | 1 |
| `manuals.md` | Index of manuals | 1 |
| `manuals/` | One Markdown file per manual (rendering, PBR, shaders, lights, camera, physics, …) | 138 |
| `apis.md` | Index of API namespaces | 1 |
| `apis/` | One Markdown file per Lua/C++/extension API namespace | 167 |
| `examples.md` | Index of examples | 1 |
| `examples/` | One Markdown file per official example | 136 |

Total: **444 Markdown files, ~8 MB**.

## How to consult

For a precise question, prefer the per-page files:

```bash
# Rendering pipeline, render targets, predicates
less docs/defold/manuals/render.md

# PBR material data exposed by the engine
less docs/defold/manuals/physically-based-rendering.md

# Built-in light components and the LightBuffer shader block
less docs/defold/manuals/light.md

# Lua API
less docs/defold/apis/render-lua.md
```

For broad or cross-cutting questions, grep the combined bundle:

```bash
rg -n "shadow|LightBuffer|render_target" docs/defold/llms-full.txt
```

The per-page files use the same anchors as the website (for example
`{#manuals:render}`), and code snippets are kept verbatim.

## Updating

Do not edit the mirror by hand. Re-download it with:

```bash
./scripts/update-defold-docs.sh
```

The script fetches the three indexes, extracts every per-page URL and downloads
the pages in parallel. It is idempotent.

## Attribution

The documentation is © the Defold Foundation and is published publicly at
<https://defold.com>. It is included here as an offline engineering reference.
The upstream `defold/doc` repository does not declare a separate license, so do
not republish this mirror as a standalone work.
