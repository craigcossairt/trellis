#!/usr/bin/env python3
"""Read-only checks for Codex routers and static hook wiring. No shell execution."""

import argparse
import json
from pathlib import Path
import re
import sys

REQUIRED_HOOK_FILES = (
    ".codex/hooks.py", ".claude/hooks/session-start.sh",
    ".claude/hooks/block-sensitive-files.sh", ".claude/hooks/format-on-edit.sh",
    ".claude/hooks/hook-file-path.sh",
)
OPERATIONS = {
    "SessionStart": "session-start", "PreToolUse": "block-sensitive-files",
    "PostToolUse": "format-on-edit", "UserPromptSubmit": "brain-enrich",
}
MATCH_CASES = {
    "SessionStart": [("startup",), ("resume",), ("clear",), ("compact",)],
    "PreToolUse": [("apply_patch", "Edit", "Write")],
    "PostToolUse": [("apply_patch", "Edit", "Write")],
    "UserPromptSubmit": [("prompt",)],  # Codex ignores this event's matcher.
}
# Only these literal repository paths are identifiable without interpreting a
# shell program. Dynamic paths, external commands and other layouts need a
# runtime check. Never execute a hook command while surveying a repository.
SCRIPT_REFERENCE = re.compile(
    r"(?<![A-Za-z0-9_.-])((?:\.codex|\.claude|brain|bin|scripts)/"
    r"(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.(?:py|sh|ps1|js))"
    r"(?=$|[\s\"'`;()|&<>])"
)


def children(path):
    # Path.glob may suppress filesystem errors. A failed scan is exit 2, never
    # an empty list that could silently remove canonical coverage requirements.
    if not path.exists():
        return []
    return sorted(path.iterdir())


def skill_files(path):
    return [directory / "SKILL.md" for directory in children(path)
            if directory.is_dir() and (directory / "SKILL.md").exists()]


def scalar_string(value):
    """The routers use two single-line strings, not the full YAML language."""
    if value.startswith('"'):
        value = json.loads(value)  # JSON double-quoted strings are valid YAML.
    elif value.startswith("'"):
        if not re.fullmatch(r"'(?:[^']|'')*'", value):
            raise ValueError("unsupported single-quoted string")
        value = value[1:-1].replace("''", "'")
    elif (not value or not value[0].isalpha()
          or value.lower() in {"true", "false", "null", "yes", "no", "on", "off", "y", "n"}
          or re.search(r":(?:\s|$)|(?:^|\s)#", value)):
        raise ValueError("use a plain string beginning with a letter, or quote it")
    if not isinstance(value, str) or not value.strip() or any(ord(char) < 32 for char in value):
        raise ValueError("must be a non-empty single-line string")
    return value


def router_errors(data, expected_name):
    errors = []
    if b"\r" in data:
        errors.append("must use LF line endings")
    text = data.decode("utf-8")
    lines = text.splitlines()
    if not lines or lines[0] != "---":
        return errors + ["must start with --- frontmatter"]
    try:
        closing = lines.index("---", 1)
    except ValueError:
        return errors + ["frontmatter is missing a closing ---"]
    values = {}
    for line in lines[1:closing]:
        if not line.strip() or line.startswith("#"):
            continue
        match = re.fullmatch(r"(name|description):[ \t]*(.*)", line)
        if not match:
            errors.append("frontmatter supports only single-line name and description fields")
            continue
        key, value = match.groups()
        if key in values:
            errors.append("duplicate frontmatter " + key)
            continue
        try:
            values[key] = scalar_string(value.strip())
        except ValueError as error:
            errors.append(key + ": " + str(error))
    for key in ("name", "description"):
        if key not in values:
            errors.append("frontmatter missing " + key)
        elif key == "name" and values[key] != expected_name:
            errors.append("frontmatter name must match " + expected_name)
    return errors


def hook_entries(config):
    """Return command entries, refusing structures Codex would not load."""
    if not isinstance(config, dict) or not isinstance(config.get("hooks"), dict) or not config["hooks"]:
        raise ValueError("hooks must be a non-empty object")
    entries = []
    for event, groups in config["hooks"].items():
        if not isinstance(groups, list) or not groups:
            raise ValueError(event + " must hold hook groups")
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list) or not group["hooks"]:
                raise ValueError(event + " has an empty or invalid hook group")
            if "matcher" in group and not isinstance(group["matcher"], str):
                raise ValueError(event + " matcher must be a string")
            matcher = group.get("matcher", "")
            pattern = None
            if event != "UserPromptSubmit" and matcher not in ("", "*"):
                try:
                    pattern = re.compile(matcher)
                except re.error as error:
                    raise ValueError(event + " has an invalid matcher: " + str(error)) from error
            for entry in group["hooks"]:
                if not isinstance(entry, dict) or entry.get("type") != "command":
                    raise ValueError(event + " must use command hooks")
                for field in ("command", "commandWindows"):
                    if field == "commandWindows" and field not in entry:
                        continue
                    if not isinstance(entry.get(field), str) or not entry[field].strip():
                        raise ValueError(event + " has an empty or invalid " + field)
                entries.append((event, entry, pattern))
    return entries


def validate(root):
    if not root.is_dir():
        raise OSError("root is not a directory: " + str(root))
    findings = []
    for adapter in (".agents", ".codex"):
        if (root / adapter).exists() and not (root / adapter).is_dir():
            raise OSError(adapter + " is not a directory")
    if (root / ".agents").is_dir():
        covered = set()
        routers = skill_files(root / ".agents/skills")
        if not routers:
            findings.append(("codex-router-invalid", ".agents/skills", "retained adapter has no routers"))
        for router in routers:
            data = router.read_bytes()
            subject = router.relative_to(root).as_posix()
            for error in router_errors(data, router.parent.name):
                findings.append(("codex-router-invalid", subject, error))
            targets = re.findall(
                r"`(\.claude/(?:skills/[A-Za-z0-9_-]+/SKILL\.md|commands/[A-Za-z0-9_-]+\.md))`",
                data.decode("utf-8"),
            )
            if not targets:
                findings.append(("codex-router-invalid", subject, "must name a backticked canonical target"))
            for target in targets:
                if not (root / target).is_file():
                    findings.append(("codex-router-dangling", subject, "missing canonical target " + target))
                else:
                    covered.add(target)
        canonical = skill_files(root / ".claude/skills") + [
            path for path in children(root / ".claude/commands") if path.suffix == ".md"]
        for path in sorted(canonical):
            target = path.relative_to(root).as_posix()
            if target not in covered:
                findings.append(("codex-router-missing", target, "no Codex router references this procedure"))
    if (root / ".codex").is_dir():
        required = list(REQUIRED_HOOK_FILES)
        if (root / "brain").exists():
            required.append("brain/hooks/context-enrichment.sh")
        for name in required:
            if not (root / name).is_file():
                findings.append(("codex-hook-missing", name, "required by the retained Codex hook adapter"))
        path = root / ".codex/hooks.json"
        if not path.is_file():
            findings.append(("codex-config-missing", ".codex/hooks.json", "retained adapter has no hook config"))
        else:
            try:
                entries = hook_entries(json.loads(path.read_text(encoding="utf-8")))
            except ValueError as error:
                findings.append(("codex-config-invalid", ".codex/hooks.json", str(error)))
            else:
                references = set()
                for _, entry, _ in entries:
                    for field in ("command", "commandWindows"):
                        references.update(SCRIPT_REFERENCE.findall(entry.get(field, "")))
                for reference in sorted(references - set(required)):
                    if not (root / reference).is_file():
                        findings.append(("codex-hook-missing", reference,
                                         "literal script reference in .codex/hooks.json is absent"))
                for event, operation in OPERATIONS.items():
                    for field in ("command", "commandWindows"):
                        for names in MATCH_CASES[event]:
                            wired = any(
                                entry_event == event and ".codex/hooks.py" in entry.get(field, "")
                                and re.search(r"\b" + re.escape(operation) + r"\b", entry.get(field, ""))
                                and (pattern is None or any(pattern.search(name) for name in names))
                                for entry_event, entry, pattern in entries
                            )
                            if not wired:
                                findings.append(("codex-hook-unwired", ".codex/hooks.json",
                                                 event + " " + field + " does not route " + names[0]
                                                 + " to hooks.py " + operation))
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--porcelain", action="store_true")
    args = parser.parse_args()
    try:
        findings = validate(args.root.resolve())
    except (OSError, UnicodeError) as error:
        print("validate-codex: could not run: " + str(error), file=sys.stderr)
        return 2
    if args.porcelain:
        print("codex-check-v1\tcomplete\t" + str(len(findings)))
    for row in findings:
        print("\t".join(row))
    if not args.porcelain:
        print("Codex static wiring: " + str(len(findings)) + " finding(s).")
        print("Not verified: runtime activation and trust; arbitrary shell command behavior.")
    return int(bool(findings))


if __name__ == "__main__":
    raise SystemExit(main())
