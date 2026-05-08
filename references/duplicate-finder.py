#!/usr/bin/env python3
"""
duplicate-finder.py

Find rule blocks in one or more CSS files whose body (declarations only)
matches another rule's body byte-for-byte after whitespace normalisation.

Usage:
    duplicate-finder.py <css-file> [<css-file> ...]
    duplicate-finder.py path/*.css

Output:
    For each group of 2+ rules sharing an identical body, print:
      - selector list
      - normalised body (first 100 chars)
    Within-file groups are reported per file.
    Cross-file groups (same body in different files) are reported separately.

What this is NOT:
    - It does NOT find rules with the same property set but different values
      (those are inconsistencies; see Phase 5c "Tier scales" in SKILL.md).
    - It does NOT find rules that *should* be merged on semantic grounds
      (a hover state and a different element happening to share output —
      semantics matter more than shared bytes).

Decisions when consolidating:
    - 3+ identical bodies → merge into one rule with grouped selectors.
    - 2 identical bodies but on semantically different components → leave separate.
    - Identical body across files → may indicate one file is redundant.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path


def parse_rules(path: Path):
    """Parse a CSS file into a list of (selector, raw_body, normalized_body) tuples.

    Skips @-rules (media, supports, container, keyframes). Strips comments first.
    Only top-level rules; nested rules inside @-blocks are not parsed.
    """
    content = path.read_text(encoding="utf-8")
    content = re.sub(r"/\*.*?\*/", "", content, flags=re.S)

    n = len(content)
    depth = 0
    sel_start = 0
    body_start = 0
    selector = ""
    rules = []
    i = 0

    while i < n:
        c = content[i]
        if c == "{":
            if depth == 0:
                selector = content[sel_start:i].strip()
                body_start = i + 1
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                body = content[body_start:i].strip()
                if (
                    selector
                    and not selector.startswith("@")
                    and len(re.sub(r"\s+", "", body)) > 20
                ):
                    body_norm = re.sub(r"\s+", "", body)
                    rules.append((selector, body, body_norm))
                sel_start = i + 1
        i += 1   # critical — without this, the loop is infinite

    return rules


def report_duplicates(rules_by_file):
    """Group rules by normalised body and print groups with 2+ members."""
    # within-file groups
    for path, rules in rules_by_file.items():
        groups = defaultdict(list)
        for selector, body, body_norm in rules:
            groups[body_norm].append(selector)
        in_file_dupes = [(b, sels) for b, sels in groups.items() if len(sels) > 1]
        if in_file_dupes:
            print(f"\n=== {path} — within-file duplicates ===")
            for body_norm, sels in in_file_dupes:
                print(f"  {len(sels)} selectors:")
                for s in sels:
                    print(f"    {s[:80]}")
                # show body sample
                for sel, body, bn in rules:
                    if bn == body_norm:
                        sample = re.sub(r"\s+", " ", body).strip()[:100]
                        print(f"    body: {sample}")
                        break

    # cross-file groups
    cross = defaultdict(list)
    for path, rules in rules_by_file.items():
        for selector, _, body_norm in rules:
            cross[body_norm].append((path, selector))
    cross_dupes = [
        (b, items) for b, items in cross.items()
        if len({p for p, _ in items}) >= 2
    ]
    if cross_dupes:
        print("\n=== Cross-file duplicates (body identical across files) ===")
        for body_norm, items in cross_dupes:
            print(f"  {len(items)} occurrences:")
            for path, sel in items:
                print(f"    {path}: {sel[:60]}")


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    rules_by_file = {}
    for arg in argv[1:]:
        path = Path(arg)
        if not path.exists():
            print(f"warning: {arg} not found, skipping", file=sys.stderr)
            continue
        rules_by_file[path] = parse_rules(path)

    if not rules_by_file:
        print("error: no input files", file=sys.stderr)
        sys.exit(1)

    report_duplicates(rules_by_file)


if __name__ == "__main__":
    main(sys.argv)
