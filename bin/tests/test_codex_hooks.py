#!/usr/bin/env python3
"""Behavioral tests for the Codex hook entry point; no model or network required."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / ".codex/hooks.py"

class CodexHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="trellis-codex-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / ".codex").mkdir()
        self.hook = self.root / ".codex/hooks.py"
        shutil.copy2(HOOK, self.hook)
        shutil.copytree(ROOT / ".claude/hooks", self.root / ".claude/hooks")

    def invoke(self, operation, command, cwd=None):
        payload = {
            "hook_event_name": "PreToolUse", "tool_name": "apply_patch",
            "cwd": str(cwd or self.root), "tool_input": {"command": command},
        }
        return subprocess.run(
            [sys.executable, str(self.hook), operation], input=json.dumps(payload),
            text=True, capture_output=True, cwd=cwd or self.root, timeout=45,
        )

    def test_add_file_uses_existing_sensitive_file_policy(self):
        safe = self.invoke("block-sensitive-files", "*** Begin Patch\n*** Add File: demo.txt\n+hello\n*** End Patch")
        self.assertEqual(safe.returncode, 0, safe.stderr)
        secret = self.invoke("block-sensitive-files", "*** Begin Patch\n*** Add File: .env\n+TOKEN=fixture\n*** End Patch")
        self.assertEqual(secret.returncode, 2, secret.stderr)
        self.assertIn("sensitive", secret.stderr)

    def test_every_operation_in_a_mixed_patch_is_checked(self):
        patch = "*** Begin Patch\n*** Add File: safe.txt\n+safe\n*** Update File: .env\n@@\n-old\n+new\n*** End Patch"
        result = self.invoke("block-sensitive-files", patch)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("sensitive", result.stderr)

    def test_patch_header_whitespace_matches_apply_patch_semantics(self):
        for body in ("*** Add File: .env \n+DUMMY=fixture",
                     "*** Add File:   .env\n+DUMMY=fixture",
                     "*** Update File: safe.txt\n*** Move to: .env \n@@\n-old\n+new"):
            with self.subTest(body=body):
                result = self.invoke("block-sensitive-files", "*** Begin Patch\n" + body + "\n*** End Patch")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("sensitive", result.stderr)

    def test_patch_envelope_whitespace_matches_apply_patch_semantics(self):
        for opening, closing in (("*** Begin Patch  ", "*** End Patch"),
                                 ("*** Begin Patch\t", "*** End Patch"),
                                 ("*** Begin Patch", "  *** End Patch  ")):
            for filename, expected in (("safe.txt", 0), (".env", 2)):
                with self.subTest(opening=opening, closing=closing, filename=filename):
                    result = self.invoke("block-sensitive-files",
                        opening + "\n*** Add File: " + filename + "\n+hello  \n" + closing)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    if expected == 2:
                        self.assertIn("sensitive", result.stderr)

    @unittest.skipUnless(os.name == "nt", "Windows filename normalization")
    def test_windows_alias_paths_are_rejected(self):
        for filename in ("package-lock.json.", ".env::$DATA"):
            with self.subTest(filename=filename):
                result = self.invoke("block-sensitive-files",
                    "*** Begin Patch\n*** Add File: " + filename + "\n+DUMMY=fixture\n*** End Patch")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("ambiguous Windows", result.stderr)


    def test_update_delete_and_both_sides_of_rename(self):
        operations = [
            ("*** Update File: safe.txt\n@@\n-old\n+new", 0),
            ("*** Delete File: safe.txt", 0),
            ("*** Delete File: .env", 2),
            ("*** Update File: safe.txt\n*** Move to: .env\n@@\n-old\n+new", 2),
            ("*** Update File: .env\n*** Move to: safe.txt\n@@\n-old\n+new", 2),
            ("*** Update File: safe.txt\n*** Move to: renamed.txt\n@@\n-old\n+new", 0),
            ("*** Add File: .env.example\n+TOKEN=example", 0),
            ("*** Add File: docs/demo.txt\n+*** Delete File: .env", 0),
        ]
        for body, expected in operations:
            with self.subTest(body=body):
                result = self.invoke("block-sensitive-files", "*** Begin Patch\n"+body+"\n*** End Patch")
                self.assertEqual(result.returncode, expected, result.stderr)

    def test_nested_cwd_and_paths_with_spaces(self):
        nested = self.root / "nested folder"
        nested.mkdir()
        (self.root / "safe.txt").write_text("old\n")
        result = self.invoke("block-sensitive-files",
            "*** Begin Patch\n*** Update File: ../safe.txt\n@@\n-old\n+new\n*** End Patch", nested)
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.invoke("block-sensitive-files",
            "*** Begin Patch\n*** Add File: ../../escape.txt\n+x\n*** End Patch", nested)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("outside", result.stderr)

    def test_malformed_and_missing_policy_fail_closed(self):
        for command in (None, "", "*** Begin Patch\n*** Unknown: .env\n*** End Patch",
                        "*** Begin Patch\n*** Move to: .env\n*** End Patch",
                        "*** Begin Patch\n*** Add File: safe.txt\n+x"):
            with self.subTest(command=command):
                self.assertEqual(self.invoke("block-sensitive-files", command).returncode, 2)
        target = self.root / ".claude/hooks/block-sensitive-files.sh"
        target.rename(target.with_suffix(".disabled"))
        result = self.invoke("block-sensitive-files", "*** Begin Patch\n*** Add File: safe.txt\n+x\n*** End Patch")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("missing canonical", result.stderr)

    def test_canonical_policy_failure_is_not_allow(self):
        (self.root / ".claude/hooks/block-sensitive-files.sh").write_text("exit 1\n", newline="\n")
        result = self.invoke("block-sensitive-files", "*** Begin Patch\n*** Add File: safe.txt\n+x\n*** End Patch")
        self.assertEqual(result.returncode, 2, result.stderr)

    def test_symlinks_check_both_named_and_resolved_paths(self):
        (self.root / "safe.txt").write_text("old\n")
        (self.root / "credentials.txt").write_text("dummy\n")
        try:
            (self.root / ".env").symlink_to(self.root / "safe.txt")
            (self.root / "alias.txt").symlink_to(self.root / "credentials.txt")
        except OSError as error:
            self.skipTest("filesystem cannot create symlinks: " + str(error))
        for filename in (".env", "alias.txt"):
            with self.subTest(filename=filename):
                result = self.invoke("block-sensitive-files",
                    "*** Begin Patch\n*** Update File: " + filename + "\n@@\n-old\n+new\n*** End Patch")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("sensitive", result.stderr)

    def test_formatter_receives_all_surviving_paths(self):
        formatter = self.root / ".claude/hooks/format-on-edit.sh"
        formatter.write_text(
            'file_path=$(bash "$CLAUDE_PROJECT_DIR/.claude/hooks/hook-file-path.sh")\n'
            'printf "%s\\n" "$file_path" >> "$CLAUDE_PROJECT_DIR/formatted.txt"\n', newline="\n")
        for filename in ("one.txt", "renamed.txt"):
            (self.root / filename).write_text("text")
        patch = ("*** Begin Patch\n*** Add File: one.txt\n+x\n"
                 "*** Update File: old.txt\n*** Move to: renamed.txt\n@@\n-old\n+new\n"
                 "*** Delete File: gone.txt\n*** End Patch")
        result = self.invoke("format-on-edit", patch)
        self.assertEqual(result.returncode, 0, result.stderr)
        paths = (self.root / "formatted.txt").read_text().splitlines()
        self.assertEqual(paths, [(self.root/"one.txt").as_posix(), (self.root/"renamed.txt").as_posix()])

    def test_session_context_and_optional_brain(self):
        result = self.invoke("session-start", None)
        self.assertEqual(result.returncode, 0, result.stderr)
        output = json.loads(result.stdout)["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "SessionStart")
        self.assertIn("=== SESSION CONTEXT ===", output["additionalContext"])
        self.assertIn("=== END SESSION CONTEXT ===", output["additionalContext"])
        result = self.invoke("brain-enrich", None)
        self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)

    def test_retained_brain_with_missing_hook_reports_failure(self):
        # Reported, never blocking: exit 2 on UserPromptSubmit blocks the
        # user's prompt, so a broken context hook would stop every prompt.
        (self.root / "brain").mkdir()
        result = self.invoke("brain-enrich", None)
        self.assertEqual(result.returncode, 0, result.stderr)
        note = json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"]
        self.assertIn("missing canonical hook", note)

    def test_context_hook_with_a_bad_cwd_falls_back_instead_of_blocking(self):
        payload = {"hook_event_name": "SessionStart", "cwd": str(self.root / "no-such-dir")}
        result = subprocess.run([sys.executable, str(self.hook), "session-start"], input=json.dumps(payload),
                                text=True, capture_output=True, cwd=self.root, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SESSION CONTEXT", json.loads(result.stdout)["hookSpecificOutput"]["additionalContext"])

    def test_unicode_line_separator_cannot_split_a_header(self):
        # str.splitlines() also breaks on U+2028 and U+0085, so this header
        # read as `docs/x` plus a body line here while Codex, splitting on
        # newline only, reads one path that normalizes to .env.
        (self.root / "docs").mkdir()
        for sep in ("\u2028", "\x85"):
            with self.subTest(sep=repr(sep)):
                result = self.invoke("block-sensitive-files",
                                     "*** Begin Patch\n*** Add File: docs/x" + sep + "+y/../../.env\n+T=1\n*** End Patch")
                self.assertEqual(result.returncode, 2, result.stderr)

    def test_crlf_patch_still_parses(self):
        result = self.invoke("block-sensitive-files", "*** Begin Patch\r\n*** Add File: demo.txt\r\n+hello\r\n*** End Patch\r\n")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_launcher_timeouts_outlast_the_adapter(self):
        # A launcher that times out before the adapter decides by its own
        # failure path; for a context hook that used to mean exit 2.
        import importlib.util, re
        spec = importlib.util.spec_from_file_location("trellis_codex_hooks", HOOK)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        config = json.loads((ROOT / ".codex/hooks.json").read_text())
        for groups in config["hooks"].values():
            for handler in (h for g in groups for h in g["hooks"]):
                operation = re.search(r'hooks\.py" (\S+)', handler["command"]).group(1)
                # The last timeout= is the adapter call; the first is git's 3s.
                launcher = int(re.findall(r"timeout=(\d+)", handler["commandWindows"])[-1])
                inner = module.TIMEOUT.get(operation, module.DEFAULT_TIMEOUT)
                with self.subTest(operation=operation):
                    self.assertGreaterEqual(launcher, inner + 5)
                    self.assertLess(launcher, handler["timeout"])

    def test_configured_context_commands_never_block(self):
        env = os.environ.copy()
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, env=env, capture_output=True)
        self.hook.rename(self.hook.with_suffix(".disabled"))
        config = json.loads((ROOT / ".codex/hooks.json").read_text())
        for event in ("SessionStart", "UserPromptSubmit"):
            handler = config["hooks"][event][0]["hooks"][0]
            if os.name == "nt":
                commands = [
                    ["powershell", "-NoProfile", "-NonInteractive", "-Command", handler["commandWindows"]],
                    '"' + os.environ.get("COMSPEC", "C:/Windows/System32/cmd.exe")
                    + '" /D /S /C "' + handler["commandWindows"] + '"',
                ]
            else:
                commands = [["bash", "-c", handler["command"]]]
            for command in commands:
                with self.subTest(event=event, shell=command[0]):
                    result = subprocess.run(command, cwd=self.root, input=json.dumps({"cwd": str(self.root), "prompt": "p"}),
                                            env=env, capture_output=True, text=True, timeout=60)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn("could not run", result.stdout)


    def test_configured_command_preserves_block_verdict_from_nested_cwd(self):
        env = os.environ.copy()
        env.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True, env=env, capture_output=True)
        nested = self.root / "nested folder"
        nested.mkdir()
        config = json.loads((ROOT / ".codex/hooks.json").read_text())
        handler = config["hooks"]["PreToolUse"][0]["hooks"][0]
        if os.name == "nt":
            # Codex wraps a hook command in the selected shell. Starting the
            # nested executable directly misses quoting and exit-code changes.
            commands = [
                ["powershell", "-NoProfile", "-NonInteractive", "-Command", handler["commandWindows"]],
                '"' + os.environ.get("COMSPEC", "C:/Windows/System32/cmd.exe")
                + '" /D /S /C "' + handler["commandWindows"] + '"',
            ]
        else:
            commands = [["bash", "-c", handler["command"]]]
        payload = {"cwd": str(nested), "tool_name": "apply_patch",
                   "tool_input": {"command": "*** Begin Patch\n*** Add File: .env\n+TOKEN=x\n*** End Patch"}}
        allowed = dict(payload, tool_input={"command": "*** Begin Patch\n*** Add File: safe.txt\n+hello\n*** End Patch"})
        for command in commands:
            result = subprocess.run(command, cwd=nested, input=json.dumps(allowed), env=env,
                                    capture_output=True, text=True, timeout=45)
            self.assertEqual((result.returncode, result.stdout), (0, ""), result.stderr)
        for scenario in ("policy", "missing-script", "missing-repository"):
            if scenario == "missing-script":
                self.hook.rename(self.hook.with_suffix(".disabled"))
            if scenario == "missing-repository":
                (self.root / ".git").rename(self.root / ".git-disabled")
            for command in commands:
                with self.subTest(scenario=scenario, shell=command[0]):
                    result = subprocess.run(command, cwd=nested, input=json.dumps(payload), env=env,
                                            capture_output=True, text=True, timeout=45)
                    if os.name == "nt":
                        self.assertEqual(result.returncode, 0, result.stderr)
                        verdict = json.loads(result.stdout)["hookSpecificOutput"]
                        self.assertEqual(verdict["hookEventName"], "PreToolUse")
                        self.assertEqual(verdict["permissionDecision"], "deny")
                        reason = verdict["permissionDecisionReason"]
                    else:
                        self.assertEqual(result.returncode, 2, result.stderr)
                        reason = result.stderr
                    self.assertTrue(reason)
                    if scenario == "policy":
                        self.assertIn("sensitive", reason)

if __name__ == "__main__":
    unittest.main()
