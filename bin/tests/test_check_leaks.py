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
        self.assertNotIn(TERM.lower(), (result.stdout + result.stderr).lower())
        self.assertIn(TERM, self.run_check("--show").stdout)

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
        self.assertIn("1 deleted or non-file", result.stdout)

    def test_masking_uses_the_original_path_so_a_lookbehind_entry_still_masks(self):
        # Entries are matched against the ORIGINAL path, never text an earlier entry
        # already masked: here entry 2 only matches while "internal/" is still there.
        self.track("internal/" + TERM + "/notes.txt", "clean\n")
        self.write_list("internal\n(?<=internal/)" + TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("matches list entry 2", result.stdout)
        self.assertNotIn(TERM.lower(), (result.stdout + result.stderr).lower())
        self.assertNotIn("internal", (result.stdout + result.stderr).lower())

    def test_overlapping_matches_are_masked_once(self):
        self.track("x-" + TERM + "-y.txt", "clean\n")
        self.write_list(TERM + "\n" + TERM[:6] + "\n" + TERM[3:] + "-y\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("x-***.txt: path matches list entry 1", result.stdout)

    def test_a_bad_pattern_reports_only_its_number_without_show(self):
        # Python's re.error text can quote part of the pattern (a group name), and
        # CI logs on a public repo are public.
        self.track("a.md", "clean\n")
        bad = {"LEAKS_LIST": "fine\n(?P=" + TERM + ")"}
        result = self.run_check(env=bad)
        self.assertEqual(result.returncode, 2)
        self.assertIn("entry 2 is not a valid regular expression", result.stderr)
        self.assertNotIn(TERM.lower(), (result.stdout + result.stderr).lower())
        shown = self.run_check("--show", env=bad)
        self.assertEqual(shown.returncode, 2)
        self.assertIn(TERM, shown.stderr)

    def stage_symlink(self, name, target):
        # Stage a symlink straight into the index (mode 120000, the target as blob
        # text). Needs no filesystem symlink support, so it runs on every platform.
        blob = subprocess.run(["git", "-C", str(self.root), "hash-object", "-w", "--stdin"],
                              input=target.encode("utf-8"), capture_output=True,
                              check=True).stdout.decode("ascii").strip()
        self.git("update-index", "--add", "--cacheinfo", f"120000,{blob},{name}")

    def test_a_tracked_symlink_target_is_scanned_without_following_the_link(self):
        self.track("a.md", "clean\n")
        self.stage_symlink("docs/link", "../" + TERM + "/notes.md")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("docs/link: line 1 matches list entry 1", result.stdout)
        self.assertIn("(1 of them symlink targets)", result.stdout)
        self.assertNotIn(TERM.lower(), (result.stdout + result.stderr).lower())

    def test_a_clean_symlink_target_passes_and_the_link_is_never_followed(self):
        self.track("a.md", "clean\n")
        # The link points at an untracked file that holds the term: following the
        # link would flag it, scanning the target text must not.
        (self.root / "private.md").write_text(TERM + "\n", encoding="utf-8")
        self.stage_symlink("link", "private.md")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("(1 of them symlink targets)", result.stdout)

    def test_a_real_filesystem_symlink_is_scanned_by_its_target_text(self):
        # The index-only cases above run everywhere; this one proves the same path
        # with a link `git add` staged itself. It skips where the platform cannot
        # make a symlink (Windows without the privilege) and runs on Linux CI.
        self.track("a.md", "clean\n")
        link = self.root / "real-link"
        try:
            os.symlink(TERM + "-target", link)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f"skipped: this platform cannot create a symlink ({exc})")
        self.git("-c", "core.symlinks=true", "add", "--", "real-link")
        staged = subprocess.run(["git", "-C", str(self.root), "ls-files", "-s", "real-link"],
                                capture_output=True, text=True, check=True).stdout
        if not staged.startswith("120000"):
            self.skipTest("skipped: git staged the link as a regular file on this platform")
        self.write_list(TERM + "\n")
        result = self.run_check()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("real-link: line 1 matches list entry 1", result.stdout)

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
