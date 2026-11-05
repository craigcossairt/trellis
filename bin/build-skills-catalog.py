#!/usr/bin/env python3
"""Generate the skills catalog in README.md from each skill's front matter.

The README table between the two markers is generated, never hand-edited:

    <!-- skills-catalog:start -->
    <!-- skills-catalog:end -->

    python bin/build-skills-catalog.py           # rewrite the section
    python bin/build-skills-catalog.py --check   # write nothing; fail when stale

Every .claude/skills/<name>/SKILL.md must open with a front matter block holding
`name` (equal to its folder) and `description`. The catalog shows the description
up to its "Use when" trigger sentence, which stays in the skill for the agent.

Exit codes (a check that could not run must never read as a pass):
  0  the catalog is current (--check) or was written
  1  a skill is malformed, or the catalog is stale (--check)
  2  the check could not run: README or markers missing, unreadable file

Pattern (generate a README section from front matter, fail CI when it is stale)
after the catalog builder in xai-org/xai-cookbook, which is under the X.AI Beta
Testing License; none of its code is used here. See CREDITS.md.
"""
import argparse
import re
import sys
from pathlib import Path

START = "<!-- skills-catalog:start -->"
END = "<!-- skills-catalog:end -->"
TRIGGER = re.compile(r"\s*\bUse when\b.*$", re.DOTALL)
KEY = re.compile(r"^([A-Za-z0-9_-]+):[ \t]*(.*)$")


def parse_front_matter(text):
    """Return a dict of the opening front matter block, or None when there is none.

    Handles plain, quoted and block (`>` / `|`) scalars, which is all a skill uses.
    A block that never closes is None: the whole file would otherwise read as front matter.
    """
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    try:
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return None
    meta, key, block, style = {}, None, [], None

    def flush():
        if key is not None:
            joiner = "\n" if style == "|" else " "
            meta[key] = joiner.join(s.strip() for s in block).strip()

    for line in lines[1:end]:
        match = KEY.match(line) if not line.startswith((" ", "\t")) else None
        if match:
            flush()
            key, value, block, style = match.group(1), match.group(2).strip(), [], None
            if value[:1] in (">", "|"):
                style = value[0]
            elif len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                meta[key], key = value[1:-1], None
            else:
                meta[key], key = value, None
        elif key is not None:
            block.append(line)
    flush()
    return meta


def summary(description):
    """The catalog's one-line summary: the description without its trigger sentence."""
    short = TRIGGER.sub("", description).strip()
    return (short or description).replace("|", "\\|")


def load_skills(skills_dir):
    """Return (rows, errors). rows is [(name, summary)] sorted by name."""
    rows, errors = [], []
    if not skills_dir.is_dir():
        return rows, errors
    for folder in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        skill = folder / "SKILL.md"
        where = skill.as_posix()
        if not skill.is_file():
            errors.append(f"{folder.as_posix()}: no SKILL.md")
            continue
        meta = parse_front_matter(skill.read_text(encoding="utf-8"))
        if meta is None:
            errors.append(f"{where}: must open with a front matter block between --- lines")
            continue
        if meta.get("name") != folder.name:
            errors.append(f"{where}: name {meta.get('name')!r} does not match the folder {folder.name!r}")
            continue
        if not meta.get("description"):
            errors.append(f"{where}: front matter has no description")
            continue
        rows.append((folder.name, summary(meta["description"])))
    return rows, errors


def render(rows):
    if not rows:
        return "No skills are installed.\n"
    lines = ["| Skill | What it does |", "| --- | --- |"]
    lines += [f"| [`{name}`](.claude/skills/{name}/SKILL.md) | {text} |" for name, text in rows]
    return "\n".join(lines) + "\n"


def splice(readme_text, catalog):
    """Replace the text between the markers. Raises ValueError when they are not exactly one pair."""
    if readme_text.count(START) != 1 or readme_text.count(END) != 1:
        raise ValueError(f"README needs exactly one {START} and one {END}")
    if readme_text.index(START) > readme_text.index(END):
        raise ValueError("the markers are out of order")
    head, rest = readme_text.split(START, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{START}\n{catalog}{END}{tail}"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate the skills catalog in README.md.")
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    parser.add_argument("--check", action="store_true", help="write nothing; exit 1 when the README is stale")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    readme = root / "README.md"

    try:
        original = readme.read_bytes().decode("utf-8")
        rows, errors = load_skills(root / ".claude" / "skills")
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        if errors:
            return 1
        newline = "\r\n" if "\r\n" in original else "\n"
        updated = splice(original.replace("\r\n", "\n"), render(rows)).replace("\n", newline)
    except (OSError, ValueError, UnicodeError) as exc:
        print(f"build-skills-catalog: could not run: {exc}", file=sys.stderr)
        return 2

    if updated == original:
        print(f"skills catalog is current ({len(rows)} skill(s))")
        return 0
    if args.check:
        print("skills catalog is stale: run `python bin/build-skills-catalog.py` and commit README.md", file=sys.stderr)
        return 1
    readme.write_bytes(updated.encode("utf-8"))
    print(f"skills catalog written ({len(rows)} skill(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
