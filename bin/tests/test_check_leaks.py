#!/usr/bin/env python3
"""Hermetic CLI checks for bin/check-leaks.py.

Each case builds a throwaway git repo, so nothing here reads this repository's
own files or touches a remote.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


CHECKER = Path(__file__).resolve().parents[1] / "check-leaks.py"
# A made-up term, assembled so this file does not contain it whole.
TERM = "Acme" + "Widgets"


class CheckLeaksTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="check leaks ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")

    def git(self, *args):
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=t", "-c", "user.email=t@example.com", *args],
                       check=True, capture_output=True)

    def track(self, name, content, binary=False):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if binary else content.encode("utf-8"))
        self.git("add", "--", name)
        return path

    def write_list(self, text, name="tools/leaks.local.txt"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def run_check(self, *args, env=None):
        full_env = {k: v for k, v in os.environ.items() if k != "LEAKS_LIST"}
        full_env.update(env or {})
        return subprocess.run([sys.executable, str(CHECKER), "--root", str(self.root), *args],
                              capture_output=True, text=True, check=False, env=full_env)

    def test_a_listed_term_in_a_tracked_file_fails_and_names_file_line_and_entry(self):
        self.track("docs/a.md", "fine\nsee " + TERM + " for details\n")
        self.write_list("# comment\n\nother-name\n" + TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("docs/a.md: line 2 matches list entry 2", result.stdout)

    def test_output_never_prints_the_term_unless_asked(self):
        self.track("a.md", TERM + "\n")
        self.write_list(TERM + "\n")
        quiet = self.run_check()
        self.assertEqual(quiet.returncode, 1)
        self.assertNotIn(TERM.lower(), (quiet.stdout + quiet.stderr).lower())
        shown = self.run_check("--show")
        self.assertIn(TERM, shown.stdout)

    def test_match_is_case_insensitive(self):
        self.track("a.md", TERM.upper() + "\n")
        self.write_list(TERM.lower() + "\n")
        self.assertEqual(self.run_check().returncode, 1)

    def test_a_matching_path_fails_even_when_the_text_is_clean(self):
        self.track("notes-" + TERM + ".txt", "nothing here\n")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("path matches list entry 1", result.stdout)

    def test_an_untracked_file_is_not_scanned(self):
        self.track("a.md", "clean\n")
        (self.root / "scratch.md").write_text(TERM, encoding="utf-8")
        self.write_list(TERM + "\n")
        self.assertEqual(self.run_check().returncode, 0)

    def test_clean_tree_passes_and_reports_what_it_scanned(self):
        self.track("a.md", "clean\n")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 files scanned", result.stdout)
        self.assertIn("check-leaks: ok", result.stdout)

    def test_no_list_skips_loudly_and_exits_zero(self):
        self.track("a.md", TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertIn("skipped: no list", result.stdout)
        self.assertIn("Nothing was checked", result.stdout)
        self.assertNotIn("check-leaks: ok", result.stdout)

    def test_require_turns_a_missing_list_into_could_not_run(self):
        self.track("a.md", "clean\n")
        result = self.run_check("--require")
        self.assertEqual(result.returncode, 2)
        self.assertIn("could not run: no list", result.stderr)

    def test_env_list_is_used_when_no_file_exists(self):
        self.track("a.md", TERM + "\n")
        result = self.run_check(env={"LEAKS_LIST": "nothing-here\n" + TERM})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("matches list entry 2", result.stdout)
        self.assertIn("$LEAKS_LIST", result.stdout)

    def test_an_empty_env_list_falls_through_to_the_file(self):
        self.track("a.md", TERM + "\n")
        self.write_list(TERM + "\n")
        result = self.run_check(env={"LEAKS_LIST": "   \n"})
        self.assertEqual(result.returncode, 1)

    def test_env_list_wins_over_the_default_file(self):
        self.track("a.md", TERM + "\n")
        self.write_list("unrelated\n")
        result = self.run_check(env={"LEAKS_LIST": TERM})
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("$LEAKS_LIST", result.stdout)

    def test_list_flag_wins_over_env_and_file(self):
        self.track("a.md", TERM + "\n")
        self.write_list("unrelated\n")
        chosen = self.write_list(TERM + "\n", name="elsewhere.txt")
        result = self.run_check("--list", str(chosen), env={"LEAKS_LIST": "unrelated"})
        self.assertEqual(result.returncode, 1)

    def test_a_list_with_only_comments_is_could_not_run_not_clean(self):
        self.track("a.md", TERM + "\n")
        self.write_list("# nothing\n\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("has no entries", result.stderr)

    def test_an_invalid_regex_is_could_not_run(self):
        self.track("a.md", "clean\n")
        self.write_list("fine\n(unclosed\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("entry 2 is not a valid regular expression", result.stderr)

    def test_a_pattern_that_matches_the_empty_string_is_refused(self):
        self.track("a.md", "clean\n")
        self.write_list("x*\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 2)
        self.assertIn("matches the empty string", result.stderr)

    def test_binary_files_are_skipped_and_counted(self):
        self.track("blob.bin", b"\0\0" + TERM.encode("utf-8"), binary=True)
        self.track("a.md", "clean\n")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertIn("1 binary", result.stdout)

    def test_a_tracked_file_deleted_from_disk_is_counted_not_hidden(self):
        path = self.track("gone.md", "clean\n")
        self.track("a.md", "clean\n")
        path.unlink()
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0)
        self.assertIn("1 deleted, symlinked or non-file", result.stdout)

    def test_a_directory_that_is_not_a_git_repo_is_could_not_run(self):
        other = tempfile.TemporaryDirectory(prefix="not a repo ")
        self.addCleanup(other.cleanup)
        (Path(other.name) / "tools").mkdir()
        (Path(other.name) / "tools" / "leaks.local.txt").write_text(TERM + "\n", encoding="utf-8")
        result = subprocess.run([sys.executable, str(CHECKER), "--root", other.name],
                                capture_output=True, text=True, check=False,
                                env={k: v for k, v in os.environ.items() if k != "LEAKS_LIST"})
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn("git ls-files failed", result.stderr)

    def test_the_list_file_is_gitignored_in_this_template(self):
        repo = Path(__file__).resolve().parents[2]
        ignored = subprocess.run(["git", "-C", str(repo), "check-ignore", "-q", "tools/leaks.local.txt"],
                                 check=False)
        self.assertEqual(ignored.returncode, 0, "tools/leaks.local.txt must be gitignored")
        tracked = subprocess.run(["git", "-C", str(repo), "ls-files", "--error-unmatch", "tools/leaks.local.txt"],
                                 check=False, capture_output=True)
        self.assertNotEqual(tracked.returncode, 0, "tools/leaks.local.txt must not be tracked")


if __name__ == "__main__":
    unittest.main()
