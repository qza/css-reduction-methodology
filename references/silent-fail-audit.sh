#!/usr/bin/env bash
#
# silent-fail-audit.sh
#
# Detect silent-fail conditions in CSS that the browser will accept without
# warning but that result in layouts not firing as intended:
#
#   1. @container <name> queries where <name> is not declared anywhere as
#      `container-name: <name>` (or as part of `container: <name> / ...`).
#      Mismatch = the query never matches; layout silently falls back to
#      the default rule.
#
#   2. var(--foo) references where --foo is never defined in any :root,
#      :host, or other declaration block. Reference resolves to the
#      property's initial value; rendered output looks "almost right".
#
# Usage:
#   ./silent-fail-audit.sh [css-glob ...]
#   ./silent-fail-audit.sh "src/**/*.css"
#
# Defaults to "./src/**/*.css" if no args given (requires bash globstar).

set -euo pipefail
shopt -s globstar nullglob

if [[ $# -eq 0 ]]; then
  files=( ./src/**/*.css ./apps/**/*.css ./styles/**/*.css )
else
  files=( "$@" )
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no CSS files found" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# === Pass 1: @container <name> vs container-name declarations ===

# All declared container names. Match `container-name: foo` and `container: foo / ...`.
grep -hE "^[[:space:]]*(container-name|container)[[:space:]]*:" "${files[@]}" 2>/dev/null \
  | sed -E 's/.*container(-name)?[[:space:]]*:[[:space:]]*([a-zA-Z_][a-zA-Z0-9_-]*).*/\2/' \
  | sort -u \
  > "$tmp/declared.txt" || true

# All referenced names in `@container <name> (...)` queries.
# (excludes anonymous queries like `@container (min-width: 500px)`)
grep -hE "^[[:space:]]*@container[[:space:]]+[a-zA-Z_]" "${files[@]}" 2>/dev/null \
  | sed -E 's/.*@container[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*).*/\1/' \
  | sort -u \
  > "$tmp/referenced.txt" || true

undeclared=$(comm -23 "$tmp/referenced.txt" "$tmp/declared.txt" || true)

echo "=== @container audit ==="
if [[ -z "$undeclared" ]]; then
  echo "All @container <name> queries match a declared container-name. OK."
else
  echo "WARNING: queries reference container names that are not declared:"
  echo "$undeclared" | sed 's/^/  - /'
  echo
  echo "Where the bad references appear:"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    grep -nHE "@container[[:space:]]+${name}\b" "${files[@]}" 2>/dev/null | sed 's/^/  /'
  done <<< "$undeclared"
fi

# === Pass 2: var(--foo) referenced but not defined ===

echo
echo "=== Custom property reference audit ==="

# All references: var(--foo), var(--foo, fallback)
grep -ohE "var\(--[a-zA-Z0-9_-]+" "${files[@]}" 2>/dev/null \
  | sed 's/var(--/--/' \
  | sort -u \
  > "$tmp/refs.txt" || true

# All definitions: --foo: value (any leading whitespace; inside any block)
grep -ohE "^[[:space:]]*--[a-zA-Z0-9_-]+[[:space:]]*:" "${files[@]}" 2>/dev/null \
  | sed -E 's/^[[:space:]]*(--[a-zA-Z0-9_-]+)[[:space:]]*:.*/\1/' \
  | sort -u \
  > "$tmp/defs.txt" || true

undef=$(comm -23 "$tmp/refs.txt" "$tmp/defs.txt" || true)

if [[ -z "$undef" ]]; then
  echo "All var(--*) references resolve to a defined custom property. OK."
else
  echo "WARNING: properties referenced via var() but never defined:"
  echo "$undef" | sed 's/^/  - /'
  echo
  echo "Note: tokens may legitimately be defined in JS (e.g. styled-components,"
  echo "CSS-in-JS) or come from a vendor stylesheet. Verify before fixing."
fi
