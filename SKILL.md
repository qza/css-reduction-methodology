---
name: css-reduction-methodology
description: A multi-phase methodology for evolving an existing CSS codebase from page-bound chaos to a tokenized primitive system. Five phases (discovery → promotion → migration → pruning → standardization), each with explicit decision rules and known silent-fail traps. Use when the user inherits or has grown a CSS codebase past 3000 lines, has 800-line files, mentions "the design feels inconsistent across pages", asks to "audit CSS", "reduce CSS", "find dead classes", "standardize tokens", or wants to introduce reusable primitives without breaking existing pages. Not for green-field projects (use a design-tokens or design-system skill instead) and not for purely lint-style detection (this is decision + multi-commit refactor flow).
---

# CSS Reduction Methodology

A staged playbook for taking a CSS codebase that has accumulated dead classes, duplicates, hardcoded values, and inconsistent primitives — and reducing it to a tokenized, predictable system **without breaking the rendered UI**.

This is not a one-shot diagnostic. It is a sequence of five phases that span multiple commits (and often multiple sessions). Each phase has a specific judgment call that the agent must make, and each phase has known silent-fail traps that look like "no-op" changes but are real bugs.

## When to use

Trigger on any of:
- "audit CSS" / "reduce CSS" / "clean up styles"
- "standardize tokens" / "find duplicates" / "find dead classes"
- A CSS file >800 lines, several files totalling >3000 lines, or any file that reads as a "junk drawer"
- Visual primitives (cards, callouts, headings) that look slightly different across pages
- The user describes a quasi-stable design and asks to make it consistent without redesigning
- The user mentions inheriting a project, or describes CSS that "grew over time"

Do NOT trigger for:
- New project setup — use a design-tokens or design-system skill
- Single-component refactor — just edit it
- Tailwind-only projects — purging is automatic; positioning matters but reduction is different
- Pure lint runs — this is decision-heavy; for static analysis use a CSS linter

## The five phases

The phases form a DAG, not a sequence. You can move between them, but you should not start a later phase until the earlier phase's invariants are satisfied. Each phase ends in a commit; the commit message captures the decisions.

### Phase 1 — Discovery (preview-driven exploration)

**Goal:** explore 2-3 layout/visual approaches in isolation before betting on one.

**Pattern:**
- Create a `/preview/<feature>-variants/` route or directory.
- Implement each variant with its own scoped CSS, named clearly (`v2-`, `v3-`, `v4-` or by approach: `magazine`, `editorial`, `cardstack`).
- Don't extract any primitives yet. Each variant is allowed to invent local tokens.
- Show the variants side-by-side; let the user pick.

**Judgment call:** how many variants to build before committing to one. Too few and you're guessing; too many and you're wasting time. Three is usually right — one safe, one ambitious, one weird.

**Exit criterion:** user has chosen a winning variant. Other variants stay in the preview route as reference until phase 4.

### Phase 2 — Promotion (page-bound → primitive)

**Goal:** extract the winning variant's reusable parts as named primitives in a shared CSS file.

**Pattern:**
- Identify the visual blocks that will be reused: hero blocks, section blocks, cards, lists, callouts.
- Rename them from page-specific (`<feature>v4-hero`) to generic (`hero-card`, `section-card`, `quote-list`).
- Move them out of the preview file into a shared file (`globals-editorial.css` or similar).
- Mirror the original markup with the new class names on the original page first to verify it still renders.

**Judgment call:** which classes are primitives and which are page-specific. A class is a primitive if there's a plausible second consumer; a class is page-specific if the next page would need slightly different rules. **When in doubt, keep it page-specific** — promoting too eagerly creates abstractions that resist later use.

**Naming:** primitives are unprefixed (`hero-card`) or scope-prefixed by purpose (`legal-highlight`, `cardgrid-section`), not by feature (`v2-hero`). The primitive's name should outlive the variant that birthed it.

**Exit criterion:** every reusable block from phase 1 has a primitive name and lives in the shared file.

### Phase 3 — Migration (rollout)

**Goal:** every page uses the primitives.

**Pattern:**
- Pick pages one at a time, in order from least-risky to most-risky.
- Per page: rewrite markup to use primitive class names, delete the page-bound CSS that becomes redundant.
- Commit per page, not per file. Each commit's message names the page migrated and any compromises ("kept the bottom CTA band as page-specific because content shape differs").
- Verify visually after each migration. Build success ≠ visual correctness.

**Judgment call:** when a page resists the primitive (e.g. "this hero needs a different layout grid than `hero-card` provides"), do you (a) extend the primitive, (b) use a `--modifier`, or (c) opt out? Default to **modifier** — extends the primitive's vocabulary without breaking it. Opt-out only if the page is genuinely sui generis (a marketing landing page versus an admin form).

**Exit criterion:** the most-similar set of pages all render through the primitives. Sui-generis pages may still have page-bound styles.

### Phase 4 — Pruning (dead code removal)

**Goal:** delete every CSS rule that no longer has a consumer.

**Pattern:**
1. For every class defined in CSS, check whether it appears in any consumer file (`*.tsx`, `*.ts`, `*.jsx`, `*.html`, `*.vue`) outside the CSS file itself.
2. Use boundary-based regex (`[^a-zA-Z0-9_-]X[^a-zA-Z0-9_-]`) — looser regex creates false positives from substrings; stricter regex misses class tokens packed against quotes.
3. Strip CSS comments before grepping: comments often mention classes (`/* uses .btn--{primary,secondary,ghost} */`) and confuse the audit.
4. Verify dynamic class composition: `className={\`prefix-${kind}\`}` won't match the literal full class. Sample-grep the prefix.

**Bash snippet:**
```bash
extract_classes_from_css() {
  # strip comments, then extract .class tokens
  perl -0777 -pe 's{/\*.*?\*/}{}gs' "$1" \
    | grep -oE '\.[a-zA-Z_][a-zA-Z0-9_-]+' \
    | sort -u | sed 's/^\.//'
}

is_class_used() {
  grep -rqE \
    --include="*.tsx" --include="*.ts" --include="*.jsx" \
    --include="*.html" --include="*.vue" \
    "[^a-zA-Z0-9_-]$1[^a-zA-Z0-9_-]" \
    "${PROJECT_SRC:-./src}" 2>/dev/null
}
```

**When a whole file's class set is dead, delete the file** and remove the import. Common after phase 3 — the page-bound CSS that gave way to primitives is now an empty husk.

**Judgment call:** how aggressive to be. Default: delete only when truly unused. If a class **looks** unused but **might** be consumed via dynamic composition or a future feature you can't see, leave a note in the commit message ("verified no usage at HEAD; kept .X because it's referenced in CHANGELOG") rather than relying on memory.

**Exit criterion:** every defined class has a consumer or a documented reason to stay.

### Phase 5 — Standardization (tokens + tiers)

**Goal:** every value in CSS is either a token or a documented exception.

**Pattern:**

**5a. Audit hex / rgb / rgba.** Find every literal color outside `:root` token declarations:
```bash
grep -nE "#[0-9a-fA-F]{3,8}|rgb\(|rgba\(" *.css
```
Categorize each hit:
| Category | Action |
|---|---|
| Already matches a token value (e.g. `#1A1917` matches `--text-primary: #1A1917`) | Replace with `var(--text-primary)` |
| Decorative SVG paint inside a `linear-gradient` | **Leave it.** Document the exemption. |
| `#fff` / `#000` for true white/black on a contrasting surface | Leave or replace with `--paper`/`--ink` — project preference |
| New unique value (e.g. `#0F3D2E`) | Add a token, then replace |
| `rgba(<token-color>, <opacity>)` | Replace with `color-mix(in srgb, var(--token) <pct>%, transparent)` |

**Token naming:** by **role** (`--surface-on-dark-mut`), not by **value** (`--cream`). Values change; roles don't.

**5b. Find identical-body duplicates.** Rules with the same body but different selectors. Common after rapid iteration.

```python
import re
from collections import defaultdict

def find_duplicates(path):
    content = re.sub(r'/\*.*?\*/', '', open(path).read(), flags=re.S)
    n = len(content); depth = 0; sel_start = 0; rules = []; i = 0
    while i < n:
        c = content[i]
        if c == '{':
            if depth == 0:
                selector = content[sel_start:i].strip()
                body_start = i + 1
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                body = re.sub(r'\s+', '', content[body_start:i])
                if selector and not selector.startswith('@') and len(body) > 20:
                    rules.append((selector, body))
                sel_start = i + 1
        i += 1   # CRITICAL — easy to forget; produces an infinite loop
    by_body = defaultdict(list)
    for sel, body in rules:
        by_body[body].append(sel)
    return [(b, sels) for b, sels in by_body.items() if len(sels) > 1]
```

**Decisions when consolidating:**
- 3+ identical bodies → merge into one rule with grouped selectors.
- 2 identical bodies but on **semantically different** components → leave separate. Semantics matter more than shared output.
- Identical body across files → may indicate one file is redundant. Investigate.

**5c. Tier scales.** Replace flat tokens with 3-tier scales for cards, callouts, type. Example for cards:
```
--card-r-sm:    8px;   --card-pad-sm: 16px;   /* notes, callouts, mocks */
--card-r-md:   12px;   --card-pad-md: 24px;   /* standard content cards */
--card-r-lg:   16px;   --card-pad-lg: 32px;   /* hero, section, large editorial */
```
**Decision rule for tiers:** if a primitive uses a value that doesn't fit a tier, either adjust the value to the nearest tier (most cases), or — only rarely — create a new tier. Never accept "this one is special". That's how inconsistency restarts.

**5d. Silent-fail audit.** Some CSS features fail silently if misconfigured.

- **`@container <name>`** queries — the `<name>` must match a `container-name` declared on an ancestor. Mismatches make the query a permanent no-op. Layouts look "almost right" but the breakpoint never fires.
  ```bash
  grep -nE "container-name:" *.css   # what's declared
  grep -nE "@container [a-z]"  *.css # what's referenced
  # diff manually; mismatches are bugs
  ```
- **Custom properties referenced but never defined** — fall back to initial value; rendered output looks "almost right".
  ```bash
  grep -ohE "var\(--[a-zA-Z0-9-]+\)" *.css | sort -u > /tmp/used.txt
  grep -ohE "^  --[a-zA-Z0-9-]+" *.css | sort -u > /tmp/defined.txt
  comm -23 /tmp/used.txt /tmp/defined.txt   # used but not defined
  ```
- **`:has()` selectors with typos in the inner compound** — the inner is parsed as a string by the browser, no syntax check, no warning.

**Judgment call:** when a silent-fail bug is found, treat it as a real bug, not a "while we're here" cleanup. Commit it separately with a clear "fix" message. Future maintainers searching for "why didn't this layout fire" need that commit to be findable.

**Exit criterion:** no hex outside tokens (or documented exemptions), no identical-body duplicates, no off-tier values in cards/type, no broken `@container` references, no undefined `var(--...)` references.

## Verifying without breaking the UI

After every phase commit:
1. **typecheck** (TypeScript / Flow / framework equivalent) — catches import breaks.
2. **build** (production build) — catches CSS syntax errors and route generation issues.
3. **Visual verification on at least one page that uses the changed primitive.** Build success does not mean rendering is correct. Either:
   - Open the page in a running dev server (user-driven; harness usually can't keep it up),
   - Or use a browser MCP / Playwright tool to capture a screenshot.

If you can't verify visually, **say so explicitly** in the commit message — don't claim "all pages render correctly" when only build was checked.

## Anti-patterns

| Anti-pattern | Why it's wrong |
|---|---|
| Bulk regex replace across all files at once | Catches false positives. Do per-file with manual review. |
| Assume the build catches all CSS errors | Build catches syntax. It does NOT catch dead classes, hardcoded values, or `@container` typos. CSS is permissive. |
| Inventing new tokens for every value seen | Token explosion is its own problem. Map values to existing tokens first; add a token only if 2+ uses justify it. |
| Tokenizing decorative SVG illustration paint | Those values are paint on a canvas, not theme. Document the exemption in the project's CLAUDE.md. |
| Removing a "dead" class without grepping its prefix dynamically | False positives from `className={\`prefix-${X}\`}`. Always check usage in JSX with the prefix as well as the literal full token. |
| Running parsing scripts in background without testing termination | One forgotten `i += 1` becomes a multi-minute zombie. Foreground first; background only after one verified successful run. |
| Skipping straight from phase 2 (promotion) to phase 5 (standardization) | The pruning step in between is what makes the audit cheap. Without phase 4, phase 5 is trying to standardize against unknown consumers. |

## Cross-cutting lessons

These emerge organically across projects, not within a single phase.

**Density follows content shape, not policy.** A page that displays short, punchy content (about-us, testimonials) will look denser/more impactful than a page that displays prose (legal, terms-of-service). Don't try to force them into the same visual rhythm. Density is a function of content shape × component shape.

**The same primitive can render with different palettes on different pages — by design.** A landing strip speaks marketing voice → brand colors. An about-page gallery speaks classification voice → category colors. Comment the choice in the data file. Resist the temptation to "unify" — readers feel the editorial difference even when they can't articulate it.

**A new primitive is sometimes worth more than a CSS variable.** Long-form prose with `<ul class="legal-list">` of "must do" / "must not do" items reads as an indistinguishable shopping list. Promoting the list to a `<LegalChecklist tone="positive">` component with check/warn icons + tonal background is a 50-line change that transforms a chapter. Reach for new primitives when value-per-line is high, even if it's "scope creep" within the audit.

**The 80% you see is the 20% that needs fixing.** Visual inconsistency is asymmetric — most users don't notice that one card has 14px radius and another has 16px, but a *designer* notices instantly. Standardize aggressively when the primitive is repeated, leave alone when it's a one-off. Don't try to flatten the long tail.

**Build-cache invalidation is a real gotcha.** When alternating between production-build and dev-server modes (Next.js, Vite, etc.), stale `.next/server/vendor-chunks/*` or `.vite/deps/*` from the last production build can hijack the dev server. `rm -rf <build-cache>` after switching modes is cheap insurance.

**Document decisions in commits.** Each commit's message should answer: what was found, what was the decision rule applied, what was deliberately left. Future readers need the decision rule, otherwise a later commit will "fix" the inconsistency you intentionally kept.

## See also

- `references/dead-class-detector.sh` — Bash script to enumerate dead classes
- `references/duplicate-finder.py` — Python script for identical-body duplicates
- `references/silent-fail-audit.sh` — `@container` and `var(--...)` reference verifier
