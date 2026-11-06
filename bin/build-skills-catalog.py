#!/usr/bin/env python3
"""Generate the skills catalog in README.md from each skill's front matter.

The README table between the two markers is generated, never hand-edited:

    <!-- skills-catalog:start -->
    <!-- skills-catalog:end -->

    python bin/build-skills-catalog.py           # rewrite the section
    python bin/build-skills-catalog.py --check   # write nothing; fail when stale

Every .claude/skills/<name>/SKILL.md must open with a front matter block holding
`name` (equal to its folder) and `description`. The catalog shows the description
up to its "Use when" trigger sentence, which stays in the skill for the agent, on one
line (a `|` block's line breaks become spaces). Comment lines in the front matter are
skipped; any other line that is not a key or an indented continuation makes the skill
malformed. Text outside the markers is kept byte for byte, line endings included.

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
INLINE_COMMENT = re.compile(r"[ \t]#")
TRAILING_COMMENT = re.compile(r"[ \t]+#")


class FrontMatterError(ValueError):
    """A front matter line this parser cannot place: the skill is malformed."""


def _strip_comment(plain):
    """A plain scalar ends at ` #` (YAML comment); `#` with no space before it is text."""
    cut = INLINE_COMMENT.search(plain)
    return plain[:cut.start()] if cut else plain


DOUBLE_ESCAPES = {"\\": "\\", '"': '"', "/": "/", "n": "\n", "t": "\t", " ": " "}
DOUBLE_ESCAPE = re.compile(r"\\(.)")


def _closing_quote(value):
    """Index of the quote that closes value[0]'s quoted scalar, or None if it never closes.

    In single quotes '' is an escaped quote; in double quotes a backslash escapes
    the next character. A `#` inside the quotes is text, so the close is found
    before any comment is looked for.
    """
    quote, i = value[0], 1
    while i < len(value):
        char = value[i]
        if quote == '"' and char == "\\":
            i += 2
            continue
        if char == quote:
            if quote == "'" and value[i + 1:i + 2] == "'":
                i += 2
                continue
            return i
        i += 1
    return None


def _unquote(value, number):
    """Decode a one-line quoted scalar: '' is a quote inside single quotes, and
    double quotes take backslash escapes. After the closing quote only a comment
    (` # ...`) may follow. An escape this parser does not know, a quote that does not
    close on its line, or other text after it is an error rather than a guess."""
    close = _closing_quote(value)
    if close is None:
        raise FrontMatterError(f"line {number} has a quoted value that does not close on its line")
    rest = value[close + 1:]
    if rest.strip() and not TRAILING_COMMENT.match(rest):
        raise FrontMatterError(f"line {number} has text after the closing quote that is not a comment")
    body = value[1:close]
    if value[0] == "'":
        return body.replace("''", "'")

    def escape(match):
        char = match.group(1)
        if char not in DOUBLE_ESCAPES:
            raise FrontMatterError(f"line {number} has an escape this parser does not support")
        return DOUBLE_ESCAPES[char]
    return DOUBLE_ESCAPE.sub(escape, body)


def parse_front_matter(text):
    """Return a dict of the opening front matter block, or None when there is none.

    Handles plain, quoted and block (`>` / `|`) scalars, which is all a skill uses.
    A block that never closes is None: the whole file would otherwise read as front matter.
    Comment lines are skipped. A line that is neither a key, a comment, a blank, nor an
    indented continuation of the key above raises FrontMatterError.
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

    for number, line in enumerate(lines[1:end], 2):
        indented = line.startswith((" ", "\t"))
        stripped = line.strip()
        match = KEY.match(line) if not indented else None
        if match:
            flush()
            key, value, block, style = match.group(1), match.group(2).strip(), [], None
            if value[:1] in (">", "|"):
                style = value[0]
            elif value[:1] in ("'", '"'):
                meta[key], key = _unquote(value, number), None
            else:
                block = [_strip_comment(value)]  # a plain scalar may wrap onto indented lines
        elif not stripped:
            if key is not None:
                block.append("")
        elif stripped.startswith("#") and (not indented or style is None):
            # A comment. Inside an indented `|` / `>` block a `#` line is content.
            continue
        elif indented and key is not None:
            block.append(line if style else _strip_comment(line))
        elif indented:
            raise FrontMatterError(f"line {number} is indented but continues no key")
        else:
            raise FrontMatterError(f"line {number} is not a key, a comment or an indented continuation")
    flush()
    return meta


def summary(description):
    """The catalog's one-line summary: the description without its trigger sentence.

    Whitespace, line breaks included, collapses to single spaces (a `|` block keeps
    its breaks, and a break inside a table row would end the row), and `|` is escaped.
    """
    short = TRIGGER.sub("", description).strip() or description
    return " ".join(short.split()).replace("|", "\\|")


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
        try:
            meta = parse_front_matter(skill.read_text(encoding="utf-8"))
        except FrontMatterError as exc:
            errors.append(f"{where}: front matter {exc}")
            continue
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
    """Replace the text between the markers. Raises ValueError when they are not exactly one pair.

    Everything outside the markers is kept byte for byte. The generated section takes
    CRLF when the README holds any CRLF (a Windows checkout), otherwise LF.
    """
    if readme_text.count(START) != 1 or readme_text.count(END) != 1:
        raise ValueError(f"README needs exactly one {START} and one {END}")
    if readme_text.index(START) > readme_text.index(END):
        raise ValueError("the markers are out of order")
    newline = "\r\n" if "\r\n" in readme_text else "\n"
    head, rest = readme_text.split(START, 1)
    _, tail = rest.split(END, 1)
    section = f"\n{catalog}".replace("\n", newline)
    return f"{head}{START}{section}{END}{tail}"


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
        updated = splice(original, render(rows))
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
