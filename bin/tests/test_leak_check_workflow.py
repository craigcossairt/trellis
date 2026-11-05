#!/usr/bin/env python3
"""Checks for the leak-check step in .github/workflows/hooks-ci.yml.

The step runs with the private LEAKS_LIST secret in its environment. On a pull
request the checked-out bin/check-leaks.py is the PR author's code, so the step
must never run that copy while the secret is set. These cases pull the step's
`run:` script out of the workflow file and execute it in throwaway repos where
the PR's copy of the script records whatever list it was handed. They also pin
that no step in the same job runs anything before the secret-bearing one.

Nothing here reads a real secret or reaches a remote.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[2]
WORKFLOW = REPO / ".github" / "workflows" / "hooks-ci.yml"
CHECKER = REPO / "bin" / "check-leaks.py"
STEP = "Leak check (private names in tracked files)"
# A made-up term, assembled so this file does not contain it whole.
TERM = "Acme" + "Widgets"

# The PR author's copy of the script: it records the list it was given, which is
# what an exfiltrating script would do, and otherwise exits 0.
PR_SCRIPT = (
    "import os, pathlib\n"
    "pathlib.Path(os.environ['MARKER']).write_text(os.environ.get('LEAKS_LIST', ''), encoding='utf-8')\n"
    "print('pr copy ran')\n"
)


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def workflow_jobs():
    """{job name: [step text, ...]} from the workflow, split by indentation."""
    lines = WORKFLOW.read_text(encoding="utf-8").splitlines()
    start = lines.index("jobs:")
    jobs, name, steps = {}, None, None
    for line in lines[start + 1:]:
        if line.strip() and _indent(line) == 2 and line.rstrip().endswith(":"):
            name, steps = line.strip()[:-1], []
            jobs[name] = steps
        elif name and line.startswith("      - "):
            steps.append(line + "\n")
        elif name and steps:
            steps[-1] += line + "\n"
    return jobs


def find_step():
    """(job name, steps before it, the step text) for the leak-check step."""
    for job, steps in workflow_jobs().items():
        for i, step in enumerate(steps):
            if f"name: {STEP}" in step.splitlines()[0]:
                return job, steps[:i], step
    raise AssertionError(f"no step named {STEP!r} in {WORKFLOW}")


def run_script(step):
    """The step's `run: |` body, dedented."""
    lines = step.splitlines()
    at = next(i for i, l in enumerate(lines) if l.strip() == "run: |")
    body_indent = None
    out = []
    for line in lines[at + 1:]:
        if line.strip() and _indent(line) <= _indent(lines[at]):
            break
        if line.strip() and body_indent is None:
            body_indent = _indent(line)
        out.append(line[body_indent:] if line.strip() else "")
    return "\n".join(out) + "\n"


def git_bash():
    """Git's bash, never Windows' WSL launcher (CreateProcess searches System32 first)."""
    found = shutil.which("bash")
    if found is None:
        raise unittest.SkipTest("skipped: no bash on PATH")
    return found


class LeakCheckStepTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.job, cls.before, cls.step = find_step()
        cls.script = run_script(cls.step)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="leak step ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.runner_temp = Path(self.temp.name) / "runner temp"
        self.runner_temp.mkdir()
        self.marker = Path(self.temp.name) / "marker.txt"
        self.root.mkdir()
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@example.com",
                               *args], check=True, capture_output=True, text=True).stdout.strip()

    def commit(self, files, message):
        for rel, text in files.items():
            path = self.root / rel
            if text is None:
                self.git("rm", "-q", "--", rel)
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            self.git("add", "--", rel)
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def pr_repo(self, base_has_checker=True):
        """A base commit, then a PR commit that swaps in the author's own script. Returns the base sha."""
        files = {"a.md": TERM + "\n"}
        if base_has_checker:
            files["bin/check-leaks.py"] = CHECKER.read_text(encoding="utf-8")
        base = self.commit(files, "base")
        self.commit({"bin/check-leaks.py": PR_SCRIPT}, "pr")
        return base

    def run_step(self, **env):
        script = self.runner_temp / "step.sh"
        script.write_text(self.script, encoding="utf-8")
        full = {k: v for k, v in os.environ.items() if k != "LEAKS_LIST"}
        full.update({"RUNNER_TEMP": str(self.runner_temp), "MARKER": str(self.marker),
                     "EVENT": "pull_request", "FORK_PR": "false", "BASE_SHA": ""})
        full.update(env)
        return subprocess.run([git_bash(), "--noprofile", "--norc", "-eo", "pipefail", str(script)],
                              cwd=self.root, capture_output=True, text=True, env=full, check=False)

    def assert_pr_code_never_saw_the_list(self):
        if self.marker.exists():
            self.assertEqual(self.marker.read_text(encoding="utf-8"), "", "the PR's script was handed the list")

    # ---- structure -------------------------------------------------------

    def test_no_step_in_the_job_runs_a_command_before_the_secret_step(self):
        # A `run:` step before it would execute PR code in the same job, which can
        # plant files, PATH entries or env (GITHUB_ENV) that the secret step inherits.
        for step in self.before:
            with self.subTest(step=step.splitlines()[0].strip()):
                # `run:` as its own key, or as the step's first key (`- run: ...`).
                self.assertNotRegex(step, r"(?m)^\s+(?:-\s+)?run:", "a step runs commands before the secret step")

    def test_only_the_leak_step_sees_the_secret(self):
        for job, steps in workflow_jobs().items():
            for step in steps:
                if "secrets.LEAKS_LIST" in step:
                    with self.subTest(job=job, step=step.splitlines()[0].strip()):
                        self.assertEqual(step, self.step)

    # ---- behaviour ---------------------------------------------------------

    def test_a_pull_request_runs_the_base_branch_copy_with_the_secret(self):
        base = self.pr_repo()
        result = self.run_step(BASE_SHA=base, LEAKS_LIST=TERM)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("a.md: line 1 matches list entry 1", result.stdout)
        self.assertNotIn("pr copy ran", result.stdout)
        self.assertFalse(self.marker.exists(), "the PR's own script ran")

    def test_a_base_without_the_script_fails_rather_than_run_pr_code_with_the_secret(self):
        base = self.pr_repo(base_has_checker=False)
        result = self.run_step(BASE_SHA=base, LEAKS_LIST=TERM)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("::error", result.stdout)
        self.assertIn("no bin/check-leaks.py", result.stdout)
        self.assertFalse(self.marker.exists(), "the PR's own script ran")
        self.assertNotIn(TERM.lower(), (result.stdout + result.stderr).lower())

    def test_a_base_without_the_script_and_no_secret_runs_the_pr_copy_with_nothing_to_leak(self):
        base = self.pr_repo(base_has_checker=False)
        result = self.run_step(BASE_SHA=base, LEAKS_LIST="  \n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("pr copy ran", result.stdout)
        self.assert_pr_code_never_saw_the_list()

    def test_a_base_commit_missing_from_the_checkout_is_could_not_run(self):
        self.pr_repo()
        result = self.run_step(BASE_SHA="0" * 40, LEAKS_LIST=TERM)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("could not run", result.stdout)
        self.assertFalse(self.marker.exists(), "the PR's own script ran")

    def test_a_fork_pull_request_with_no_secret_fails_instead_of_passing(self):
        base = self.pr_repo()
        result = self.run_step(BASE_SHA=base, FORK_PR="true")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("comes from a fork", result.stdout)

    def test_a_same_repo_pull_request_with_no_secret_announces_the_skip(self):
        base = self.pr_repo()
        result = self.run_step(BASE_SHA=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("::notice title=Leak check skipped", result.stdout)

    def test_a_push_runs_the_checked_out_copy(self):
        # Pushes run only on main, whose tree is already merged and trusted.
        self.commit({"a.md": TERM + "\n", "bin/check-leaks.py": CHECKER.read_text(encoding="utf-8")}, "main")
        result = self.run_step(EVENT="push", LEAKS_LIST=TERM)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("a.md: line 1 matches list entry 1", result.stdout)


HISTORY_STEP = "Secret scan (gitleaks, commits in this push or pull request)"
CONFIG = REPO / ".gitleaks.toml"
# An xAI-shaped fixture key, assembled so this file does not hold one whole.
FAKE_KEY = "xai" + "-" + "a" * 80


def find_named_step(name):
    for job, steps in workflow_jobs().items():
        for step in steps:
            if f"name: {name}" in step.splitlines()[0]:
                return step
    raise AssertionError(f"no step named {name!r} in {WORKFLOW}")


class ScanReportingTests(unittest.TestCase):
    """Both scan steps print where a finding is, with its value masked. Needs no binary."""

    def test_every_gitleaks_scan_prints_findings_redacted(self):
        lines = [line for line in WORKFLOW.read_text(encoding="utf-8").splitlines()
                 if re.match(r"\s*gitleaks (detect|git)\b", line)]
        self.assertEqual(len(lines), 2, lines)
        for line in lines:
            self.assertIn("--verbose", line)
            self.assertIn("--redact", line)


@unittest.skipUnless(shutil.which("gitleaks"), "skipped: gitleaks binary not on PATH")
class HistoryScanStepTests(unittest.TestCase):
    """The commit-range secret scan. Runs where gitleaks is installed (hooks CI)."""

    @classmethod
    def setUpClass(cls):
        cls.script = run_script(find_named_step(HISTORY_STEP))

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="history step ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        subprocess.run(["git", "-C", str(self.root), "init", "-q"], check=True)
        shutil.copy(CONFIG, self.root / ".gitleaks.toml")

    def commit(self, files, message):
        for rel, text in files.items():
            if text is None:
                subprocess.run(["git", "-C", str(self.root), "rm", "-q", "--", rel], check=True)
                continue
            (self.root / rel).write_text(text, encoding="utf-8")
            subprocess.run(["git", "-C", str(self.root), "add", "--", rel], check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@example.com",
                        "commit", "-q", "-m", message], check=True)
        return subprocess.run(["git", "-C", str(self.root), "rev-parse", "HEAD"], check=True,
                              capture_output=True, text=True).stdout.strip()

    def run_step(self, before, after):
        script = Path(self.temp.name) / "step.sh"
        script.write_text(self.script, encoding="utf-8")
        env = dict(os.environ, EVENT="push", PUSH_BEFORE=before, PUSH_AFTER=after, PR_BASE="", PR_HEAD="")
        return subprocess.run([git_bash(), "--noprofile", "--norc", "-eo", "pipefail", str(script)],
                              cwd=self.root, capture_output=True, text=True, env=env, check=False)

    def key_added_then_removed(self):
        base = self.commit({"a.txt": "base\n", ".gitleaks.toml": CONFIG.read_text(encoding="utf-8")}, "base")
        self.commit({"s.txt": "k = " + FAKE_KEY + "\n"}, "add a key")
        head = self.commit({"s.txt": None}, "remove it")
        return base, head

    def test_a_key_added_and_removed_inside_the_range_fails(self):
        base, head = self.key_added_then_removed()
        result = self.run_step(base, head)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("found a secret", result.stdout)

    def test_a_finding_names_its_file_but_never_its_value(self):
        # The error says "the finding above is redacted", so there must be a finding
        # above: --verbose prints it, --redact masks the value (CodeRabbit, trellis#36).
        base, head = self.key_added_then_removed()
        result = self.run_step(base, head)
        out = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, out)
        self.assertIn("s.txt", out)
        self.assertNotIn(FAKE_KEY, out)

    def test_with_no_usable_base_a_key_removed_before_head_still_fails(self):
        # The fallback must cover every commit reachable from head: scanning head
        # alone would miss a key added and then removed earlier.
        _, head = self.key_added_then_removed()
        result = self.run_step("0" * 40, head)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("found a secret", result.stdout)
        self.assertNotIn(FAKE_KEY, result.stdout + result.stderr)

    def test_with_no_usable_base_a_clean_history_passes_and_says_what_it_scanned(self):
        self.commit({"a.txt": "base\n", ".gitleaks.toml": CONFIG.read_text(encoding="utf-8")}, "base")
        head = self.commit({"b.txt": "more\n"}, "more")
        result = self.run_step("0" * 40, head)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("every commit reachable from", result.stdout)


if __name__ == "__main__":
    unittest.main()
