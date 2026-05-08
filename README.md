# CSS Reduction Methodology

A Claude Code / Claude Agent skill for evolving an existing CSS codebase from page-bound chaos to a tokenized primitive system. Five staged phases with explicit decision rules and known silent-fail traps.

## What this is

This is **not** a green-field design system skill, and **not** a pure lint runner. It is a multi-commit refactor methodology:

- **Discovery** → explore 2-3 layout variants in a `/preview` route
- **Promotion** → extract winning variant's reusable parts as named primitives
- **Migration** → roll primitives across pages, one commit per page
- **Pruning** → delete every CSS rule that no longer has a consumer
- **Standardization** → tokens, tier scales, identical-body deduplication, silent-fail audit

Each phase has a **judgment call** (which the skill spells out) and **anti-patterns** to avoid (which the skill also spells out).

## When to use

Trigger on phrases like:
- "audit CSS" / "reduce CSS" / "clean up styles"
- "standardize tokens" / "find duplicates" / "find dead classes"
- A CSS file >800 lines, files totalling >3000 lines
- "the design feels inconsistent across pages" but design is already mostly stable

Do not use for:
- Brand-new project setup → use a `design-tokens` or `design-system` skill
- Tailwind-only projects → purging is automatic; use a Tailwind-specific skill
- Pure lint runs → this is decision-heavy; for static analysis use a CSS linter (Stylelint, etc.)

## Installation

### As a Claude Code user-level skill (available in every project)
```bash
git clone https://github.com/zee/css-reduction-methodology.git \
  ~/.claude/skills/css-reduction-methodology
```

### As a project-level skill (only in this repo)
```bash
git clone https://github.com/zee/css-reduction-methodology.git \
  .claude/skills/css-reduction-methodology
```

Restart your Claude Code session. The skill activates when you ask Claude to "audit CSS", "reduce CSS", "find dead classes", "standardize tokens", or any of the trigger phrases listed in `SKILL.md`.

The folder name (`css-reduction-methodology`) must match the skill's `name:` field in the frontmatter — don't rename it on clone.

## What's inside

| File | Purpose |
|---|---|
| `SKILL.md` | Main skill body — phases, decision rules, anti-patterns, cross-cutting lessons |
| `references/dead-class-detector.sh` | Bash: list classes defined in a CSS file with no consumer in any `*.tsx`, `*.ts`, `*.jsx`, `*.html`, `*.vue` file |
| `references/duplicate-finder.py` | Python: find rules with byte-identical bodies (within file and cross-file) |
| `references/silent-fail-audit.sh` | Bash: audit `@container <name>` queries against declared `container-name` and `var(--foo)` references against `--foo` definitions |

## Why phases, not a one-shot script

CSS audit is **judgment-heavy**. Most "dead classes" are obviously dead, but a few are dynamically composed (`className={\`prefix-${kind}\`}`). Most identical-body duplicates should be merged, but some are semantically distinct and should stay separate. Most hex values can be tokenized, but some are decorative SVG paint and should be left alone.

A single one-shot tool either:
- (a) over-reaches and breaks legitimate code, or
- (b) under-reaches by being too conservative.

A staged methodology lets the agent (and the human) make decisions per phase, commit after each, and roll back if needed. The skill captures the decision rules so they don't have to be relearned every time.

## Origin

Distilled from a real multi-week CSS evolution on a production codebase that went from ~10,000 lines of CSS across 12 files to ~3,800 lines across 5 files, while introducing primitives that unified visual treatment across 10+ pages. The decision rules and anti-patterns are the ones that emerged organically — the ones that, in hindsight, would have prevented the false starts.

## License

MIT (or whichever you prefer).
