#!/usr/bin/env python3
"""Hermetic CLI checks for Codex's static wiring validator."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


VALIDATOR = Path(__file__).resolve().parents[1] / "validate-codex.py"


class CodexValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="codex validation ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content.encode("utf-8"))
        return path

    def run_validator(self, porcelain=True):
        return subprocess.run(
            [sys.executable, str(VALIDATOR), "--root", str(self.root)]
            + (["--porcelain"] if porcelain else []),
            capture_output=True, text=True, check=False,
        )

    def router(self, body="Read and follow `.claude/skills/alpha/SKILL.md`.\n"):
        return self.write(".agents/skills/alpha/SKILL.md",
                          "---\nname: alpha\ndescription: Route alpha\n---\n\n" + body)

    def hook_config(self):
        operations = {"SessionStart": "session-start", "PreToolUse": "block-sensitive-files",
                      "PostToolUse": "format-on-edit", "UserPromptSubmit": "brain-enrich"}
        config = {"hooks": {event: [{"hooks": [{"type": "command",
                    "command": "python3 .codex/hooks.py " + operation,
                    "commandWindows": "python .codex/hooks.py " + operation}]}]
                    for event, operation in operations.items()}}
        self.write(".codex/hooks.json", json.dumps(config))
        for name in (".codex/hooks.py", ".claude/hooks/session-start.sh",
                     ".claude/hooks/block-sensitive-files.sh", ".claude/hooks/format-on-edit.sh",
                     ".claude/hooks/hook-file-path.sh"):
            self.write(name, "# fixture\n")
        return config

    def test_retained_adapter_requires_router_for_each_canonical_target(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        (self.root / ".agents").mkdir()
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-router-missing\t.claude/skills/alpha/SKILL.md\t", result.stdout)

    def test_router_requires_loadable_frontmatter_and_lf(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        body = "Read and follow `.claude/skills/alpha/SKILL.md`.\n"
        cases = {
            "---\nname: other\ndescription: Route alpha\n---\n": "name",
            "---\nname: alpha\n---\n": "description",
            "---\nname: alpha\ndescription: Route alpha\n": "closing",
            "name: alpha\ndescription: Route alpha\n---\n": "start",
            "---\r\nname: alpha\r\ndescription: Route alpha\r\n---\r\n": "LF",
        }
        for frontmatter, expected in cases.items():
            with self.subTest(expected=expected):
                self.write(".agents/skills/alpha/SKILL.md", frontmatter + body)
                result = self.run_validator()
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("codex-router-invalid\t.agents/skills/alpha/SKILL.md\t", result.stdout)
                self.assertIn(expected, result.stdout)

    def test_router_checks_its_actual_target_not_its_directory_name(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        self.router("Read `.claude/skills/vanished/SKILL.md`.\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-router-dangling\t.agents/skills/alpha/SKILL.md\t", result.stdout)
        self.assertIn(".claude/skills/vanished/SKILL.md", result.stdout)

    def test_router_must_name_a_canonical_target(self):
        self.router("Read whatever you want.\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-router-invalid", result.stdout)
        self.assertIn("canonical target", result.stdout)

    def test_retained_empty_adapter_is_not_a_completed_check(self):
        (self.root / ".agents").mkdir()
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-router-invalid\t.agents/skills\t", result.stdout)

    def test_missing_or_unloadable_hook_config_is_reported(self):
        (self.root / ".codex").mkdir()
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-config-missing\t.codex/hooks.json\t", result.stdout)
        for content in ("{", "{}", '{"hooks": {}}', '{"hooks": []}',
                        '{"hooks": {"PreToolUse": [null]}}',
                        '{"hooks": {"PreToolUse": [{"hooks": []}]}}',
                        '{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": ""}]}]}}'):
            with self.subTest(content=content):
                self.write(".codex/hooks.json", content)
                result = self.run_validator()
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("codex-config-invalid\t.codex/hooks.json\t", result.stdout)

    def test_missing_hook_implementation_is_reported(self):
        self.hook_config()
        for name in (".codex/hooks.py", ".claude/hooks/block-sensitive-files.sh",
                     ".claude/hooks/session-start.sh", ".claude/hooks/format-on-edit.sh",
                     ".claude/hooks/hook-file-path.sh"):
            with self.subTest(name=name):
                path = self.root / name
                path.rename(path.with_suffix(".saved"))
                result = self.run_validator()
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("codex-hook-missing\t" + name + "\t", result.stdout)
                path.with_suffix(".saved").rename(path)

    def test_brain_deletion_is_allowed_but_partial_deletion_is_reported(self):
        self.hook_config()
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.root / "brain").mkdir()
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-hook-missing\tbrain/hooks/context-enrichment.sh\t", result.stdout)
        self.write("brain/hooks/context-enrichment.sh", "# fixture\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_each_event_requires_its_operation_on_both_platforms(self):
        config = self.hook_config()
        for event in ("SessionStart", "PreToolUse", "PostToolUse", "UserPromptSubmit"):
            for field in ("command", "commandWindows"):
                with self.subTest(event=event, field=field):
                    entry = config["hooks"][event][0]["hooks"][0]
                    original = entry[field]
                    entry[field] = "python .codex/hooks.py unknown-operation"
                    self.write(".codex/hooks.json", json.dumps(config))
                    result = self.run_validator()
                    self.assertEqual(result.returncode, 1, result.stderr)
                    self.assertIn("codex-hook-unwired\t.codex/hooks.json\t", result.stdout)
                    self.assertIn(event + " " + field, result.stdout)
                    entry[field] = original

    def test_identifiable_custom_script_reference_must_exist(self):
        config = self.hook_config()
        config["hooks"]["SessionStart"][0]["hooks"].append({
            "type": "command", "command": "bash scripts/custom-check.sh"})
        self.write(".codex/hooks.json", json.dumps(config))
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-hook-missing\tscripts/custom-check.sh\t", result.stdout)
        self.write("scripts/custom-check.sh", "# fixture\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_inspection_exits_two_instead_of_clean(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        self.router()
        self.write(".claude/commands", "a file cannot be scanned as a directory\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("could not run", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_completed_check_receipt_counts_findings_and_limits_its_claim(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        self.router()
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "codex-check-v1\tcomplete\t0\n")
        result = self.run_validator(porcelain=False)
        self.assertIn("static wiring", result.stdout)
        self.assertIn("runtime activation and trust", result.stdout)
        self.router("Read `.claude/skills/vanished/SKILL.md`.\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(result.stdout.splitlines()[0], "codex-check-v1\tcomplete\t2")

    def test_commands_need_coverage_only_while_the_router_adapter_is_retained(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        self.router()
        self.write(".claude/commands/daily.md", "canonical command\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn("codex-router-missing\t.claude/commands/daily.md\t", result.stdout)
        self.write(".agents/skills/daily/SKILL.md",
                   "---\nname: daily\ndescription: Route daily\n---\nRead `.claude/commands/daily.md`.\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.root / ".agents").rename(self.root / "pruned-agents")
        result = self.run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_frontmatter_rejects_unsupported_or_ambiguous_yaml(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        for description in ("[unclosed", "{bad: value", "*alias", "&anchor text", "|", ">",
                            '""', "''", "true", "null", "123", '"unclosed',
                            "another: mapping", "words # trailing comment"):
            with self.subTest(description=description):
                self.write(".agents/skills/alpha/SKILL.md",
                           "---\nname: alpha\ndescription: " + description
                           + "\n---\nRead `.claude/skills/alpha/SKILL.md`.\n")
                result = self.run_validator()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("codex-router-invalid", result.stdout)
                self.assertIn("description", result.stdout)

    def test_effective_matcher_must_reach_the_patch_hook(self):
        config = self.hook_config()
        for event in ("PreToolUse", "PostToolUse"):
            with self.subTest(event=event):
                config["hooks"][event][0]["matcher"] = "^Bash$"
                self.write(".codex/hooks.json", json.dumps(config))
                result = self.run_validator()
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("codex-hook-unwired", result.stdout)
                self.assertIn(event + " command", result.stdout)
                self.assertIn("apply_patch", result.stdout)
                config["hooks"][event][0]["matcher"] = "^apply_patch$"

    def test_session_start_matcher_must_cover_each_supported_source(self):
        config = self.hook_config()
        config["hooks"]["SessionStart"][0]["matcher"] = "^startup$"
        self.write(".codex/hooks.json", json.dumps(config))
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for source in ("resume", "clear", "compact"):
            self.assertIn(source, result.stdout)

    def test_invalid_matcher_regex_cannot_report_clean(self):
        config = self.hook_config()
        config["hooks"]["PreToolUse"][0]["matcher"] = "["
        self.write(".codex/hooks.json", json.dumps(config))
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("codex-config-invalid", result.stdout)
        self.assertIn("matcher", result.stdout)

    def test_documented_matcher_aliases_and_wildcards_are_allowed(self):
        config = self.hook_config()
        config["hooks"]["UserPromptSubmit"][0]["matcher"] = "^Bash$"  # ignored by Codex
        for matcher in ("^apply_patch$", "Edit|Write", "^Edit$", "^Write$", "*", ""):
            with self.subTest(matcher=matcher):
                for event in ("PreToolUse", "PostToolUse"):
                    config["hooks"][event][0]["matcher"] = matcher
                self.write(".codex/hooks.json", json.dumps(config))
                result = self.run_validator()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_balanced_quoted_frontmatter_and_duplicate_key_rejection(self):
        self.write(".claude/skills/alpha/SKILL.md", "canonical procedure\n")
        for description in ('"Route: alpha # checked"', "'Route alpha''s procedure'"):
            with self.subTest(description=description):
                self.write(".agents/skills/alpha/SKILL.md",
                           "---\nname: 'alpha'\ndescription: " + description
                           + "\n---\nRead `.claude/skills/alpha/SKILL.md`.\n")
                result = self.run_validator()
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.write(".agents/skills/alpha/SKILL.md",
                   "---\nname: alpha\nname: alpha\ndescription: Route alpha\n---\n"
                   "Read `.claude/skills/alpha/SKILL.md`.\n")
        result = self.run_validator()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("duplicate frontmatter name", result.stdout)


if __name__ == "__main__":
    unittest.main()
