#!/usr/bin/env bash
#
# Download the official Defold documentation in LLM-friendly Markdown form.
#
# Source: https://defold.com/llms.txt (generated from https://github.com/defold/doc)
#
# Usage:
#   scripts/update-defold-docs.sh [destination]
#
# Default destination: docs/defold
#
set -euo pipefail

DEST="${1:-docs/defold}"
BASE="https://defold.com"
INDEXES=(manuals apis examples)

mkdir -p "$DEST"
cd "$DEST"

echo "Downloading indexes..."
curl -fsSL --retry 3 -o llms-full.txt "$BASE/llms-full.txt"
curl -fsSL --retry 3 -o llms.txt "$BASE/llms.txt"
for index in "${INDEXES[@]}"; do
    curl -fsSL --retry 3 -o "$index.md" "$BASE/llms/$index.md"
done

echo "Downloading per-page Markdown..."
for index in "${INDEXES[@]}"; do
    grep -oE "$BASE/llms/$index/[^) ]+\.md" "$index.md" | sort -u > "/tmp/defold-${index}-urls.txt"
done

cat /tmp/defold-manuals-urls.txt /tmp/defold-apis-urls.txt /tmp/defold-examples-urls.txt \
    | sort -u \
    | xargs -P 8 -n 1 -I{} bash -c '
        url="$1"
        rel="${url#https://defold.com/llms/}"
        mkdir -p "$(dirname "$rel")"
        curl -fsSL --retry 3 -o "$rel" "$url"
    ' _ {}

echo "Done."
find . -type f -name '*.md' | wc -l
du -sh .
