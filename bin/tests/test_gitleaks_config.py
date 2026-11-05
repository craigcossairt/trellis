#!/usr/bin/env python3
"""Checks for .gitleaks.toml: it parses, each vendor rule matches its key shape
and nothing it should not, and, when the gitleaks binary is on PATH, the real
scanner flags a fixture key.

Fixtures are assembled at run time from pieces, so this file does not itself
contain a string that looks like a key (and so does not trip secret scanning of
the repository that holds it).
"""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import tomllib
import unittest


CONFIG = Path(__file__).resolve().parents[2] / ".gitleaks.toml"


def _alnum(n, ch="a"):
    return ch * n


# rule id -> (a string the rule must match, strings it must not match)
FIXTURES = {
    "trellis-anthropic-api-key": (
        "sk-" + "ant-" + "api03-" + _alnum(90),
        ["ANTHROPIC_API_KEY=", "sk-" + "ant-" + "api03-short", "sk-" + "ant-" + "api03" + _alnum(90)],
    ),
    "trellis-openai-api-key": (
        "sk-" + "proj-" + _alnum(30) + "T3Blbk" + "FJ" + _alnum(30),
        ["OPENAI_API_KEY=", "sk-" + _alnum(48), "sk-" + "proj-" + _alnum(30) + "T3Blbk" + "FJ" + "ab"],
    ),
    "trellis-xai-api-key": (
        "xai" + "-" + _alnum(80),
        ["XAI_API_KEY=", "xai" + "-" + _alnum(20), "xai" + "-" + _alnum(200)],
    ),
    "trellis-firecrawl-api-key": (
        "fc" + "-" + "0123456789abcdef" * 2,
        ["FIRECRAWL_API_KEY=", "fc" + "-" + "0123456789abcdef", "fc" + "-" + "0123456789abcdef" * 3],
    ),
    "trellis-linear-api-key": (
        "lin" + "_api_" + _alnum(40),
        ["LINEAR_API_KEY=", "lin" + "_api_" + _alnum(12)],
    ),
    "trellis-supabase-access-token": (
        "sb" + "p_" + "0123456789abcdef" * 2 + "01234567",
        ["SUPABASE_ACCESS_TOKEN=", "sb" + "p_" + "0123456789abcdef", "sb" + "p_" + "G" * 40],
    ),
    "trellis-supabase-secret-key": (
        "sb" + "_secret_" + _alnum(30),
        ["SUPABASE_SECRET_KEY=", "sb" + "_secret_" + "short"],
    ),
    "trellis-posthog-personal-api-key": (
        "ph" + "x_" + _alnum(45),
        ["POSTHOG_PERSONAL_API_KEY=", "ph" + "x_" + _alnum(10)],
    ),
}


class GitleaksConfigTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = tomllib.loads(CONFIG.read_text(encoding="utf-8"))
        cls.rules = {r["id"]: r for r in cls.config.get("rules", [])}

    def test_extends_the_default_rules(self):
        self.assertIs(self.config.get("extend", {}).get("useDefault"), True)

    def test_every_vendor_rule_has_a_fixture_and_every_fixture_a_rule(self):
        self.assertEqual(sorted(self.rules), sorted(FIXTURES))

    def test_rule_ids_are_unique_and_prefixed_so_they_never_replace_a_default(self):
        ids = [r["id"] for r in self.config["rules"]]
        self.assertEqual(len(ids), len(set(ids)))
        for rule_id in ids:
            self.assertTrue(rule_id.startswith("trellis-"), rule_id)

    def test_each_rule_matches_its_key_shape(self):
        for rule_id, (positive, _) in FIXTURES.items():
            with self.subTest(rule=rule_id):
                self.assertRegex(positive, re.compile(self.rules[rule_id]["regex"]))

    def test_each_rule_ignores_variable_names_and_near_misses(self):
        for rule_id, (_, negatives) in FIXTURES.items():
            for text in negatives:
                with self.subTest(rule=rule_id, text=text[:24]):
                    self.assertIsNone(re.search(self.rules[rule_id]["regex"], text))

    def test_each_rules_keyword_appears_in_its_key_or_gitleaks_never_runs_it(self):
        # gitleaks evaluates a rule only on text containing one of its keywords
        # (case-insensitive), so a keyword the key does not contain disables the rule.
        for rule_id, (positive, _) in FIXTURES.items():
            keywords = self.rules[rule_id].get("keywords") or []
            with self.subTest(rule=rule_id):
                self.assertTrue(keywords, "rule has no keywords")
                self.assertTrue(any(k.lower() in positive.lower() for k in keywords))

    @unittest.skipUnless(shutil.which("gitleaks"), "skipped: gitleaks binary not on PATH")
    def test_the_real_scanner_flags_each_fixture_and_passes_a_clean_file(self):
        with tempfile.TemporaryDirectory(prefix="gitleaks fixture ") as tmp:
            for rule_id, (positive, _) in FIXTURES.items():
                (Path(tmp) / f"{rule_id}.txt").write_text(f"value = {positive}\n", encoding="utf-8")
            report = Path(tmp).parent / "gitleaks-report.json"
            proc = subprocess.run(
                ["gitleaks", "detect", "--no-git", "--source", tmp, "--config", str(CONFIG),
                 "--redact", "--report-format", "json", "--report-path", str(report), "--exit-code", "7"],
                capture_output=True, encoding="utf-8", errors="replace", check=False)
            self.assertEqual(proc.returncode, 7, proc.stdout + proc.stderr)
            found = report.read_text(encoding="utf-8")
            report.unlink()
            for rule_id in FIXTURES:
                with self.subTest(rule=rule_id):
                    self.assertIn(f'"RuleID": "{rule_id}"', found)
        with tempfile.TemporaryDirectory(prefix="gitleaks clean ") as tmp:
            (Path(tmp) / "env.txt").write_text("ANTHROPIC_API_KEY=\nXAI_API_KEY=\n", encoding="utf-8")
            # Bytecode holds assembled fixtures whole (constant folding); it must not trip the scan.
            (Path(tmp) / "__pycache__").mkdir()
            (Path(tmp) / "__pycache__" / "fixture.txt").write_text(FIXTURES["trellis-xai-api-key"][0], encoding="utf-8")
            proc = subprocess.run(
                ["gitleaks", "detect", "--no-git", "--source", tmp, "--config", str(CONFIG), "--exit-code", "7"],
                capture_output=True, encoding="utf-8", errors="replace", check=False)
            self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()
