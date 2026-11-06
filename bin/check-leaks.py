#!/usr/bin/env python3
"""Fail when a tracked file names something that must not be public.

A template is copied out of a private project, so the private project's names
(company, product, internal hosts, people) tend to survive in an example or a
comment. This check reads a list of regular expressions, one per line, and fails
on any tracked file whose path or text matches one.

The list is NOT in the repository: a public repo that carried its own list of
private names would publish them. It comes from, in this order:

  1. --list PATH
  2. the LEAKS_LIST environment variable (newline-separated; for a CI secret)
  3. tools/leaks.local.txt (gitignored; see tools/leaks.local.txt.example)

Exit codes (a check that could not run must never read as a pass):
  0  no leak found, or no list is configured (and --require was not given)
  1  a tracked file matches a list entry
  2  the check could not run: unreadable list, bad pattern, git failure

With no list the check says so on stdout and exits 0. Pass --require to make a
missing list exit 2, which is what a local run before publishing should use.

The output names the file, the line and the list entry NUMBER, never the matched
text or the pattern, because CI logs on a public repo are public. A matching path
is printed with every listed match masked (each entry matched against the
original path, so one mask cannot hide another entry's match; an entry that
matches with zero length, such as a lookahead, masks the whole path). An entry that does
not compile is reported by number only, since Python's error text can quote part
of it. Use --show on your own machine to print the matched text and the detail.

A tracked symlink is scanned by its target text, read from git's object store
(where git keeps it), never by following the link.

Pattern adapted from the leak check in phuryn/product-engineering
(tools/validate.py, MIT, Copyright (c) 2026 Pawel Huryn); this file is a fresh
implementation. See CREDITS.md.
"""
import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

DEFAULT_LIST = Path("tools") / "leaks.local.txt"
ENV_LIST = "LEAKS_LIST"
BINARY_PROBE = 8192


class PatternError(ValueError):
    """A list entry that does not compile. str() names only the entry number."""

    def __init__(self, number, detail):
        super().__init__(f"entry {number} is not a valid regular expression")
        self.detail = detail


def parse_list(text):
    """Return [(entry_number, compiled_regex)] from a list file's text.

    Blank lines and lines starting with # are skipped; entry numbers count the
    remaining lines from 1. Raises ValueError on a pattern that does not compile
    or that matches the empty string (which would flag every file).
    """
    entries = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        number = len(entries) + 1
        try:
            pattern = re.compile(line, re.IGNORECASE)
        except re.error as exc:
            # re.error's text can quote part of the pattern (a group name, say), and
            # a public CI log is public: the detail prints only under --show.
            raise PatternError(number, str(exc)) from None
        if pattern.search(""):
            raise ValueError(f"entry {number} matches the empty string, so it would flag every file")
        entries.append((number, pattern))
    return entries


def load_entries(list_arg, root):
    """Return (entries, source_description), or (None, None) when no list exists.

    List files are read as utf-8-sig: a byte order mark (some Windows editors write
    one) would otherwise become part of entry 1, which would then never match.
    """
    if list_arg:
        path = Path(list_arg)
        return parse_list(path.read_text(encoding="utf-8-sig")), str(path)
    env = os.environ.get(ENV_LIST)
    if env is not None and env.strip():
        return parse_list(env), f"${ENV_LIST}"
    path = root / DEFAULT_LIST
    if path.exists():
        return parse_list(path.read_text(encoding="utf-8-sig")), DEFAULT_LIST.as_posix()
    return None, None


SYMLINK_MODE = "120000"


def tracked_files(root):
    """Return [(mode, blob_id, path)] for every path in the index."""
    proc = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--stage"], capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError("git ls-files failed: " + proc.stderr.decode("utf-8", "replace").strip())
    files = []
    for record in proc.stdout.decode("utf-8", "surrogateescape").split("\0"):
        if not record:
            continue
        meta, _, rel = record.partition("\t")
        mode, blob, _stage = meta.split(" ")
        files.append((mode, blob, rel))
    return files


def symlink_target(root, blob):
    """The tracked text of a symlink: git stores the target path as the blob.

    Read from the object store, never through the link, so a link to a file
    outside the tree is not followed, and a checkout without symlink support
    (where git writes a plain file) reads the same text.
    """
    proc = subprocess.run(["git", "-C", str(root), "cat-file", "blob", blob], capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError("git cat-file failed: " + proc.stderr.decode("utf-8", "replace").strip())
    return proc.stdout


def scan(root, entries, show):
    """Return (findings, scanned, symlinks, skipped_binary, skipped_missing)."""
    findings = []
    scanned = symlinks = skipped_binary = skipped_missing = 0
    for mode, blob, rel in tracked_files(root):
        path = root / rel
        # The path itself may hold the term, so a public log gets it masked.
        shown = rel if show else _mask(rel, entries)
        for number, pattern in entries:
            match = pattern.search(rel)
            if match:
                findings.append(_finding(shown, "path", number, match, show))
        if mode == SYMLINK_MODE:
            data = symlink_target(root, blob)
            symlinks += 1
        elif path.is_symlink() or not path.is_file():
            # A tracked path deleted from the working tree (or a submodule, or a
            # file replaced on disk by a link) has no text of its own to read;
            # counted and reported, never silently dropped.
            skipped_missing += 1
            continue
        else:
            data = path.read_bytes()
        if b"\0" in data[:BINARY_PROBE]:
            skipped_binary += 1
            continue
        scanned += 1
        for line_no, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
            for number, pattern in entries:
                match = pattern.search(line)
                if match:
                    findings.append(_finding(shown, line_no, number, match, show))
    return findings, scanned, symlinks, skipped_binary, skipped_missing


def _mask(text, entries):
    """Replace every listed match with ***, each one found in the ORIGINAL text.

    Masking one entry at a time would let an earlier mask remove the context a
    later entry needs (a lookbehind, say), leaving that later match in plain
    view. So every entry's spans are collected first, overlaps merged, then the
    text is masked once.

    A zero-length match (a lookahead such as `(?=Name)`) has no span to hide, yet
    the name sits right after it, so any zero-length match masks the whole text.
    """
    matches = [m for _, pattern in entries for m in pattern.finditer(text)]
    if any(m.end() == m.start() for m in matches):
        return "***"
    spans = sorted((m.start(), m.end()) for m in matches)
    merged = []
    for start, end in spans:
        if merged and start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    out, last = [], 0
    for start, end in merged:
        out.append(text[last:start] + "***")
        last = end
    return "".join(out) + text[last:]


def _finding(rel, where, number, match, show):
    where = "path" if where == "path" else f"line {where}"
    text = f"{rel}: {where} matches list entry {number}"
    return text + (f" ({match.group(0)!r})" if show else "")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Fail when a tracked file names a listed private term.")
    parser.add_argument("--root", default=".", help="repository root (default: current directory)")
    parser.add_argument("--list", dest="list_path", help="path to the pattern list")
    parser.add_argument("--require", action="store_true", help="exit 2 instead of skipping when no list exists")
    parser.add_argument("--show", action="store_true", help="print the matched text (never in public CI logs)")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()

    try:
        entries, source = load_entries(args.list_path, root)
        if entries is None:
            if args.require:
                print(f"check-leaks: could not run: no list. Give --list, set ${ENV_LIST}, or create {DEFAULT_LIST.as_posix()}.",
                      file=sys.stderr)
                return 2
            print(f"check-leaks: skipped: no list (no --list, ${ENV_LIST} unset, no {DEFAULT_LIST.as_posix()}). "
                  "Nothing was checked.")
            return 0
        if not entries:
            print(f"check-leaks: could not run: {source} has no entries.", file=sys.stderr)
            return 2
        findings, scanned, symlinks, skipped_binary, skipped_missing = scan(root, entries, args.show)
    except PatternError as exc:
        detail = f": {exc.detail}" if args.show else " (rerun with --show on your own machine for the detail)"
        print(f"check-leaks: could not run: {exc}{detail}", file=sys.stderr)
        return 2
    except (OSError, ValueError, RuntimeError, UnicodeError) as exc:
        print(f"check-leaks: could not run: {exc}", file=sys.stderr)
        return 2

    for finding in findings:
        print(finding)
    print(f"check-leaks: {len(entries)} entries from {source}; {scanned} files scanned "
          f"({symlinks} of them symlink targets), "
          f"{skipped_binary} binary and {skipped_missing} deleted or non-file skipped.")
    if findings:
        print(f"check-leaks: FAILED with {len(findings)} match(es).")
        return 1
    print("check-leaks: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
