#!/usr/bin/env python3
"""Hermetic CLI checks for bin/build-skills-catalog.py."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


BUILDER = Path(__file__).resolve().parents[1] / "build-skills-catalog.py"
START = "<!-- skills-catalog:start -->"
END = "<!-- skills-catalog:end -->"


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="skills catalog ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.readme("# Title\n\nintro\n\n" + START + "\n" + END + "\n\noutro\n")

    def readme(self, text):
        (self.root / "README.md").write_bytes(text.encode("utf-8"))

    def read(self):
        return (self.root / "README.md").read_bytes().decode("utf-8")

    def skill(self, name, front, folder=None):
        path = self.root / ".claude" / "skills" / (folder or name) / "SKILL.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(front.encode("utf-8"))

    def run_builder(self, *args):
        return subprocess.run([sys.executable, str(BUILDER), "--root", str(self.root), *args],
                              capture_output=True, text=True, check=False)

    def test_writes_a_row_per_skill_sorted_and_keeps_text_outside_the_markers(self):
        self.skill("zeta", "---\nname: zeta\ndescription: Last one.\n---\nbody\n")
        self.skill("alpha", "---\nname: alpha\ndescription: First one.\n---\nbody\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertTrue(text.startswith("# Title\n\nintro\n\n" + START + "\n"))
        self.assertTrue(text.endswith(END + "\n\noutro\n"))
        self.assertLess(text.index("`alpha`"), text.index("`zeta`"))
        self.assertIn("| [`alpha`](.claude/skills/alpha/SKILL.md) | First one. |", text)

    def test_description_is_cut_before_its_use_when_trigger_and_pipes_are_escaped(self):
        self.skill("alpha", "---\nname: alpha\ndescription: Does a | b. Use when asked to 'go'.\n---\n")
        self.run_builder()
        row = [l for l in self.read().splitlines() if "`alpha`" in l][0]
        self.assertTrue(row.endswith("| Does a \\| b. |"), row)

    def test_plain_quoted_and_block_scalars_all_parse(self):
        self.skill("plain", "---\nname: plain\ndescription: Plain text here.\n---\n")
        self.skill("quoted", "---\nname: \"quoted\"\ndescription: 'Quoted: with a colon.'\n---\n")
        self.skill("block", "---\nname: block\ndescription: >\n  Folded line one\n  and line two.\nother: x\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertIn("| Plain text here. |", text)
        self.assertIn("| Quoted: with a colon. |", text)
        self.assertIn("| Folded line one and line two. |", text)

    def test_a_plain_description_wrapped_onto_indented_lines_is_kept_whole(self):
        self.skill("wrap", "---\nname: wrap\ndescription: First half\n  second half.\nother: x\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        self.assertIn("| First half second half. |", self.read())

    def test_a_quoted_scalar_followed_by_a_comment_drops_the_comment_and_the_quotes(self):
        self.skill("sq", "---\nname: sq\ndescription: 'Ready.' # owner note\n---\n")
        self.skill("dq", "---\nname: dq\ndescription: \"Set.\"   # owner note\n---\n")
        self.skill("sqhash", "---\nname: sqhash\ndescription: 'Keep # this, it''s text.' # drop\n---\n")
        self.skill("dqhash", "---\nname: dqhash\ndescription: \"Keep # this \\\"too\\\".\" # drop\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertIn("| [`sq`](.claude/skills/sq/SKILL.md) | Ready. |", text)
        self.assertIn("| [`dq`](.claude/skills/dq/SKILL.md) | Set. |", text)
        self.assertIn("| Keep # this, it's text. |", text)
        self.assertIn("| Keep # this \"too\". |", text)
        self.assertNotIn("owner", text)
        self.assertNotIn("drop", text)

    def test_text_after_a_closing_quote_that_is_not_a_comment_is_malformed(self):
        self.skill("junk", "---\nname: junk\ndescription: 'Ready.' trailing\n---\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("junk/SKILL.md", result.stderr)

    def test_quoted_scalars_decode_their_escapes(self):
        # YAML: in single quotes '' is one quote; in double quotes \" and \\ are escapes.
        self.skill("single", "---\nname: single\ndescription: 'It''s ready.'\n---\n")
        self.skill("double", "---\nname: double\ndescription: \"Say \\\"hi\\\" to a\\\\b.\"\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertIn("| It's ready. |", text)
        self.assertIn("| Say \"hi\" to a\\b. |", text)

    def test_a_multi_line_literal_block_renders_as_one_table_row(self):
        self.skill("lit", "---\nname: lit\ndescription: |\n  Line one.\n  Line two | piped.\nother: x\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        rows = [l for l in self.read().splitlines() if "`lit`" in l]
        self.assertEqual(rows, ["| [`lit`](.claude/skills/lit/SKILL.md) | Line one. Line two \\| piped. |"])
        inside = self.read().split(START, 1)[1].split(END, 1)[0]
        self.assertEqual([l for l in inside.splitlines() if l and not l.startswith("|")], [])

    def test_a_comment_line_after_the_description_is_not_part_of_it(self):
        self.skill("cmt", "---\nname: cmt\ndescription: First.\n# Owner note\n  # indented note\nother: x\n---\n")
        self.skill("inline", "---\nname: inline\ndescription: Second. # trailing note\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertIn("| [`cmt`](.claude/skills/cmt/SKILL.md) | First. |", text)
        self.assertIn("| [`inline`](.claude/skills/inline/SKILL.md) | Second. |", text)
        self.assertNotIn("note", text)

    def test_a_hash_with_no_space_before_it_or_inside_quotes_is_kept(self):
        # YAML starts a comment only at a `#` after whitespace in a plain scalar.
        self.skill("hash", "---\nname: hash\ndescription: Uses C# and a#tag.\n---\n")
        self.skill("quoted", "---\nname: quoted\ndescription: 'Quoted # kept.'\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        self.assertIn("| Uses C# and a#tag. |", self.read())
        self.assertIn("| Quoted # kept. |", self.read())

    def test_an_unindented_line_that_is_not_a_key_is_a_malformed_skill(self):
        self.skill("bad", "---\nname: bad\ndescription: First.\nnot a key line\n---\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("bad/SKILL.md", result.stderr)
        self.assertIn("not a key", result.stderr)

    def test_an_indented_line_with_no_key_to_continue_is_a_malformed_skill(self):
        self.skill("orphan", "---\nname: orphan\ndescription: 'Quoted.'\n  stray continuation\n---\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("orphan/SKILL.md", result.stderr)

    def test_text_outside_the_markers_keeps_its_bytes_in_a_mixed_line_ending_readme(self):
        head = "# T\r\n\r\nintro with LF\n\r\n"
        tail = "\r\noutro LF\nlast CRLF\r\n"
        self.readme(head + START + "\r\n" + END + tail)
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertTrue(text.startswith(head + START), repr(text[:60]))
        self.assertTrue(text.endswith(END + tail), repr(text[-60:]))
        self.assertEqual(self.run_builder("--check").returncode, 0)

    def test_check_passes_after_a_write_and_fails_when_a_skill_changes(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.run_builder()
        self.assertEqual(self.run_builder("--check").returncode, 0)
        self.skill("alpha", "---\nname: alpha\ndescription: Changed.\n---\n")
        result = self.run_builder("--check")
        self.assertEqual(result.returncode, 1)
        self.assertIn("stale", result.stderr)

    def test_check_writes_nothing(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        before = self.read()
        self.assertEqual(self.run_builder("--check").returncode, 1)
        self.assertEqual(self.read(), before)

    def test_a_new_skill_with_no_catalog_row_is_stale(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.run_builder()
        self.skill("beta", "---\nname: beta\ndescription: Second.\n---\n")
        self.assertEqual(self.run_builder("--check").returncode, 1)

    def test_a_hand_edit_inside_the_markers_is_stale(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.run_builder()
        self.readme(self.read().replace("First.", "Edited by hand."))
        self.assertEqual(self.run_builder("--check").returncode, 1)

    def test_a_name_that_differs_from_the_folder_fails(self):
        self.skill("alpha", "---\nname: other\ndescription: First.\n---\n", folder="alpha")
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("does not match the folder", result.stderr)

    def test_missing_description_fails(self):
        self.skill("alpha", "---\nname: alpha\n---\n")
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no description", result.stderr)

    def test_no_front_matter_fails(self):
        self.skill("alpha", "# just a body\n")
        self.assertEqual(self.run_builder().returncode, 1)

    def test_front_matter_that_never_closes_fails(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n\nbody text with no closing fence\n")
        self.assertEqual(self.run_builder().returncode, 1)

    def test_a_skill_folder_without_a_skill_file_fails(self):
        (self.root / ".claude" / "skills" / "empty").mkdir(parents=True)
        result = self.run_builder()
        self.assertEqual(result.returncode, 1)
        self.assertIn("no SKILL.md", result.stderr)

    def test_a_bad_skill_does_not_rewrite_the_readme(self):
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.run_builder()
        before = self.read()
        self.skill("beta", "# no front matter\n")
        self.assertEqual(self.run_builder().returncode, 1)
        self.assertEqual(self.read(), before)

    def test_missing_markers_are_could_not_run(self):
        self.readme("# no markers here\n")
        result = self.run_builder("--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("could not run", result.stderr)

    def test_duplicate_or_reversed_markers_are_could_not_run(self):
        self.readme(START + "\n" + END + "\n" + START + "\n" + END + "\n")
        self.assertEqual(self.run_builder("--check").returncode, 2)
        self.readme(END + "\n" + START + "\n")
        result = self.run_builder("--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn("out of order", result.stderr)

    def test_missing_readme_is_could_not_run(self):
        (self.root / "README.md").unlink()
        self.assertEqual(self.run_builder("--check").returncode, 2)

    def test_no_skills_directory_renders_an_explicit_empty_state(self):
        self.assertEqual(self.run_builder().returncode, 0)
        self.assertIn("No skills are installed.", self.read())

    def test_a_crlf_readme_stays_crlf_and_checks_clean(self):
        self.readme("# T\r\n\r\n" + START + "\r\n" + END + "\r\n")
        self.skill("alpha", "---\nname: alpha\ndescription: First.\n---\n")
        self.assertEqual(self.run_builder().returncode, 0)
        text = self.read()
        self.assertNotIn("\n", text.replace("\r\n", ""))
        self.assertEqual(self.run_builder("--check").returncode, 0)


if __name__ == "__main__":
    unittest.main()
