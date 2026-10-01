#!/usr/bin/env python3
"""Translate Codex hook payloads; file policy stays in .claude/hooks/."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TARGETS = {
    "session-start": (".claude/hooks/session-start.sh", "SessionStart"),
    "block-sensitive-files": (".claude/hooks/block-sensitive-files.sh", "PreToolUse"),
    "format-on-edit": (".claude/hooks/format-on-edit.sh", "PostToolUse"),
    "brain-enrich": ("brain/hooks/context-enrichment.sh", "UserPromptSubmit"),
}

def bash_path():
    configured = os.environ.get("TRELLIS_BASH")
    if configured:
        if not Path(configured).is_file():
            raise ValueError("TRELLIS_BASH does not name a Bash executable")
        return configured
    if os.name == "nt":
        git = shutil.which("git")
        candidates = [Path(git).parent.parent / "bin/bash.exe"] if git else []
        candidates += [Path(os.environ.get("ProgramFiles", "C:/Program Files")) / "Git/bin/bash.exe"]
        for candidate in candidates:
            if candidate.is_file():
                return str(candidate)
        raise ValueError("Git Bash not found; set TRELLIS_BASH to Git for Windows bash.exe")
    found = shutil.which("bash")
    if not found:
        raise ValueError("Bash not found")
    return found

def patch_paths(command, cwd):
    """Read operation headers, never text inside added/removed/context lines."""
    if not isinstance(command, str):
        raise ValueError("apply_patch requires tool_input.command")
    lines = command.strip().splitlines()
    if len(lines) < 3 or lines[0].strip() != "*** Begin Patch" or lines[-1].strip() != "*** End Patch":
        raise ValueError("invalid patch envelope")
    paths = []
    operation = None
    for line in lines[1:-1]:
        raw = None
        for kind in ("Add", "Update", "Delete"):
            prefix = "*** " + kind + " File: "
            if line.startswith(prefix):
                raw = line[len(prefix):]
                operation = kind
                break
        if line.startswith("*** Move to: "):
            if operation != "Update":
                raise ValueError("move must follow an update operation")
            raw = line[len("*** Move to: "):]
        if raw is not None:
            # Codex trims trailing header whitespace before interpreting paths.
            raw = raw.rstrip()
            if not raw or any(ord(char) < 32 for char in raw):
                raise ValueError("empty or invalid patch target")
            named = (cwd / raw).absolute()
            if os.name == "nt" and any(
                ":" in part or (part not in (".", "..") and part.endswith((" ", ".")))
                for part in named.parts[1:]
            ):
                raise ValueError("ambiguous Windows patch target")
            resolved = named.resolve()
            if not named.is_relative_to(ROOT) or not resolved.is_relative_to(ROOT):
                raise ValueError("patch target is outside this repository")
            # A sensitive filename may alias a safe file, or the other way round.
            # Apply the canonical policy to both spellings, not just the target.
            paths.extend((named, resolved))
        elif operation == "Update" and (line.startswith("@@") or line == "*** End of File"):
            continue
        elif operation == "Add" and line.startswith("+"):
            continue
        elif operation == "Update" and (not line or line[0] in " +-"):
            continue
        else:
            raise ValueError("unrecognized patch operation or body")
    if not paths:
        raise ValueError("patch contains no supported file operations")
    return list(dict.fromkeys(paths))

def run_target(operation, payload, cwd, bash):
    relative, _ = TARGETS[operation]
    target = ROOT / relative
    if operation == "brain-enrich" and not (ROOT / "brain").exists():
        return ""
    if not target.is_file():
        raise ValueError("missing canonical hook: " + relative)
    env = os.environ.copy()
    env["CLAUDE_PROJECT_DIR"] = ROOT.as_posix()
    env["PATH"] = str(Path(bash).parent) + os.pathsep + env.get("PATH", "")
    result = subprocess.run(
        [bash, target.as_posix()], input=json.dumps(payload), text=True,
        capture_output=True, cwd=cwd, env=env, timeout=30,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or "canonical hook failed")
    return result.stdout

def main():
    operation = sys.argv[1] if len(sys.argv) == 2 else ""
    if operation not in TARGETS:
        raise ValueError("usage: hooks.py <session-start|block-sensitive-files|format-on-edit|brain-enrich>")
    payload = json.load(sys.stdin)
    if not isinstance(payload, dict):
        raise ValueError("hook payload must be an object")
    cwd = Path(payload.get("cwd", str(ROOT))).resolve()
    if not cwd.is_relative_to(ROOT) or not cwd.is_dir():
        raise ValueError("hook cwd must be inside this repository")
    bash = bash_path()
    if operation in ("block-sensitive-files", "format-on-edit"):
        if payload.get("tool_name") != "apply_patch":
            raise ValueError("expected the Codex apply_patch tool")
        tool_input = payload.get("tool_input")
        if not isinstance(tool_input, dict):
            raise ValueError("missing tool_input")
        paths = patch_paths(tool_input.get("command"), cwd)
        if operation == "format-on-edit":
            paths = dict.fromkeys(path.resolve() for path in paths)
        for path in paths:
            if operation == "format-on-edit" and not path.is_file():
                continue
            run_target(operation, {"tool_input": {"file_path": path.as_posix()}}, cwd, bash)
    else:
        output = run_target(operation, payload, cwd, bash)
        if output:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": TARGETS[operation][1], "additionalContext": output,
            }}))
    return 0

if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, TypeError, OSError, subprocess.SubprocessError) as error:
        print("Trellis Codex hook: " + str(error), file=sys.stderr)
        sys.exit(2)
