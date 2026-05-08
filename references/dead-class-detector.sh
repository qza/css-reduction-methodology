#!/usr/bin/env bash
#
# dead-class-detector.sh
#
# For a given CSS file, list class names defined inside it that have no
# consumer in any *.tsx, *.ts, *.jsx, *.html, or *.vue file under a project
# source root. Class names are extracted with comments stripped first.
#
# Usage:
#   ./dead-class-detector.sh <css-file> [project-source-root]
#
#   Default source root: $PROJECT_SRC env var, or "./src", or "."
#
# Boundary semantics:
#   A class is considered "used" if it appears in a consumer file surrounded
#   on each side by a non-class-name character: [^a-zA-Z0-9_-]X[^a-zA-Z0-9_-]
#   This catches `className="X"`, `className="a X b"`, `\`prefix-${X}\``
#   when the inner ${X} is a literal token (rare). It does NOT catch fully
#   dynamic compositions like `className={\`X-\${kind}\`}` where the suffix
#   is unknown — sample-grep the prefix manually for those.
#
# Known false positives:
#   - Class is named in a CSS comment elsewhere (we strip comments only in
#     the file under audit; cross-file comments still match).
#   - Class is part of a `@apply` rule in another CSS file (Tailwind etc.).
#
# Always eyeball the report before deleting.

set -euo pipefail

CSS_FILE="${1:?usage: $0 <css-file> [project-source-root]}"
SRC_ROOT="${2:-${PROJECT_SRC:-./src}}"

if [[ ! -f "$CSS_FILE" ]]; then
  echo "error: $CSS_FILE not found" >&2
  exit 1
fi

if [[ ! -d "$SRC_ROOT" ]]; then
  # try repo root as a fallback
  SRC_ROOT="."
fi

# Extract class tokens from CSS file with comments stripped.
classes=$(
  perl -0777 -pe 's{/\*.*?\*/}{}gs' "$CSS_FILE" \
    | grep -oE '\.[a-zA-Z_][a-zA-Z0-9_-]+' \
    | sort -u \
    | sed 's/^\.//'
)

total=$(echo "$classes" | wc -l)
dead=0
dead_list=""

for cls in $classes; do
  # boundary-based search across consumer file types
  if ! grep -rqE \
       --include="*.tsx" --include="*.ts" \
       --include="*.jsx" --include="*.js" \
       --include="*.html" --include="*.vue" \
       --include="*.svelte" --include="*.astro" \
       "[^a-zA-Z0-9_-]${cls}[^a-zA-Z0-9_-]" \
       "$SRC_ROOT" 2>/dev/null; then
    dead=$((dead + 1))
    dead_list="${dead_list}${cls}"$'\n'
  fi
done

echo "=== $(basename "$CSS_FILE") ==="
echo "total classes: $total | dead: $dead"
if [[ $dead -gt 0 ]]; then
  echo
  echo "$dead_list" | sort -u
fi
