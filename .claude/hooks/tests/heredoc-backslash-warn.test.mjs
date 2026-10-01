// Behavioral suite for .claude/hooks/heredoc-backslash-warn.mjs (optional hook).
//
//   node --test .claude/hooks/tests/heredoc-backslash-warn.test.mjs
//
// Every case runs the real hook entry as a child process with a PreToolUse
// payload on stdin, the way Claude Code runs it, and asserts the exit code and
// the output. Three outcomes, kept apart:
//   - a warning: exit 0 plus JSON carrying hookSpecificOutput.additionalContext;
//   - silence: exit 0, empty stdout and stderr;
//   - could not run (unparseable payload): exit 0 plus a systemMessage saying
//     so. Never a block - the hook is warn-only - and never silence, because
//     "could not read the command" is not "no heredoc".
//
// Backslashes in these fixtures are built with BS (String.fromCharCode(92)) so
// the fixture text is exactly what a shell command would carry, whatever
// escaping this file itself goes through.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const HOOK = join(HERE, '..', 'heredoc-backslash-warn.mjs');
const BS = String.fromCharCode(92);

function run(stdin) {
  const r = spawnSync(process.execPath, [HOOK], { input: stdin, encoding: 'utf8' });
  return { code: r.status, stdout: r.stdout, stderr: r.stderr };
}

function bash(command) {
  return JSON.stringify({ hook_event_name: 'PreToolUse', tool_name: 'Bash', tool_input: { command } });
}

function expectWarn(command, interpreter) {
  const r = run(bash(command));
  assert.equal(r.code, 0, `exit code (stderr: ${r.stderr})`);
  assert.notEqual(r.stdout.trim(), '', 'expected a warning on stdout, got silence');
  const out = JSON.parse(r.stdout);
  assert.equal(out.hookSpecificOutput?.hookEventName, 'PreToolUse');
  assert.equal(out.hookSpecificOutput?.permissionDecision, undefined, 'a warning must never decide permission');
  const ctx = out.hookSpecificOutput?.additionalContext ?? '';
  assert.match(ctx, new RegExp(`heredoc into ${interpreter}`), 'names the interpreter it saw');
  assert.match(ctx, /Edit tool/, 'names the Edit tool');
  assert.match(ctx, /chr\(92\)/, 'names chr(92)');
  assert.match(ctx, /bytes\(\[92\]\)/, 'names bytes([92])');
  assert.match(ctx, /String\.fromCharCode\(92\)/, 'names String.fromCharCode(92)');
  assert.match(ctx, /cat -A/, 'says how to verify the bytes');
  assert.equal(typeof out.systemMessage, 'string', 'the user sees a one-line notice too');
  return out;
}

function expectSilent(command) {
  const r = run(bash(command));
  assert.equal(r.code, 0, `exit code (stderr: ${r.stderr})`);
  assert.equal(r.stdout, '', 'expected silence');
  assert.equal(r.stderr, '', 'expected silence on stderr');
}

function expectCouldNotRun(stdin) {
  const r = run(stdin);
  assert.equal(r.code, 0, 'warn-only: a payload it cannot read must not block the command');
  assert.notEqual(r.stdout.trim(), '', 'could-not-run must not be silent');
  const out = JSON.parse(r.stdout);
  assert.match(out.systemMessage ?? '', /^heredoc backslash check could not run: /);
  assert.match(out.systemMessage ?? '', /could not parse the hook payload/);
  assert.equal(out.hookSpecificOutput?.permissionDecision, undefined, 'never decides permission');
}

// --- warns ---------------------------------------------------------------

test('warns: python - with a quoted delimiter and \\r in the body', () => {
  expectWarn(`python - <<'EOF'\nopen('x','w').write('a${BS}r${BS}nb')\nEOF`, 'python');
});

test('warns: python3 with an unquoted delimiter', () => {
  expectWarn(`python3 <<EOF\nprint("${BS}t")\nEOF`, 'python3');
});

test('warns: py launcher', () => {
  expectWarn(`py - <<"PY"\nprint('${BS}0')\nPY`, 'py');
});

test('warns: node heredoc', () => {
  expectWarn(`node <<'JS'\nconsole.log('a${BS}nb')\nJS`, 'node');
});

test('warns: node - with a trailing redirect after the delimiter word', () => {
  expectWarn(`node - <<'JS' > out.txt\nconsole.log('${BS}b')\nJS`, 'node');
});

test('warns: bun heredoc', () => {
  expectWarn(`bun run - <<'TS'\nconsole.log("${BS}${BS}")\nTS`, 'bun');
});

test('warns: perl heredoc', () => {
  expectWarn(`perl <<'PL'\nprint "${BS}n";\nPL`, 'perl');
});

test('warns: interpreter given by path and .exe', () => {
  expectWarn(`/c/Python312/python.exe - <<'EOF'\nprint('${BS}n')\nEOF`, 'python');
});

test('warns: env assignment and env prefix before the interpreter', () => {
  expectWarn(`PYTHONIOENCODING=utf-8 env python3 - <<'EOF'\nprint('${BS}n')\nEOF`, 'python3');
});

test('warns: <<- form with a tab-indented delimiter', () => {
  expectWarn(`python - <<-'EOF'\n\tprint('${BS}n')\n\tEOF`, 'python');
});

test('warns: heredoc after cd && on the same line', () => {
  expectWarn(`cd /tmp && python - <<'EOF'\nprint('${BS}n')\nEOF`, 'python');
});

test('warns: cat heredoc piped into python still reaches the interpreter', () => {
  expectWarn(`cat <<'EOF' | python -\nprint('${BS}n')\nEOF`, 'python');
});

test('warns: second heredoc of two, when only it holds the backslash', () => {
  expectWarn(`cat <<'A' > a.txt\nplain\nA\npython - <<'B'\nprint('${BS}n')\nB`, 'python');
});

// Runners that execute a later word as the program, and a redirect whose `&`
// is not a command separator.
test('warns: timeout prefix before the interpreter', () => {
  expectWarn(`timeout 60 python3 - <<'PY'\nprint('${BS}n')\nPY`, 'python3');
});

test('warns: nice -n before node', () => {
  expectWarn(`nice -n 10 node - <<'JS'\nconsole.log('${BS}n')\nJS`, 'node');
});

test('warns: uv run python', () => {
  expectWarn(`uv run python - <<'PY'\nprint('${BS}n')\nPY`, 'python');
});

test('warns: 2>&1 between the interpreter and the heredoc', () => {
  expectWarn(`python3 - 2>&1 <<'PY'\nprint('${BS}n')\nPY`, 'python3');
});

// The redirect target is not a script path.
test('warns: > file between the interpreter and the heredoc', () => {
  expectWarn(`python3 > out.txt <<'PY'\nprint('${BS}n')\nPY`, 'python3');
});

test('warns: sudo, nohup and time wrappers', () => {
  expectWarn(`nohup time sudo perl <<'PL'\nprint "${BS}n";\nPL`, 'perl');
});

test('warns: heredoc inside $( )', () => {
  expectWarn(`out=$(python3 - <<'PY'\nprint('${BS}n')\nPY\n)`, 'python3');
});

test('warns: second of two heredocs on one line', () => {
  expectWarn(`cat <<'A' > a.txt; python3 - <<'B'\nplain\nA\nprint('${BS}n')\nB`, 'python3');
});

// The body still reaches the interpreter through a pass-through stage.
test('warns: two-stage pipeline into python', () => {
  expectWarn(`cat <<'EOF' | cat | python -\nprint('${BS}n')\nEOF`, 'python');
});

// --- silent --------------------------------------------------------------

// echo runs, not python; the interpreter's name is only an argument.
test('silent: interpreter name as an argument to another command', () => {
  expectSilent(`echo python - <<'EOF'\nprint('${BS}n')\nEOF`);
});

// A heredoc that is stdin DATA for a script or an -e program reaches it with
// its backslashes intact, so there is nothing to warn about.
test('silent: python running a script file reads the heredoc as data', () => {
  expectSilent(`python3 scripts/x.py <<'EOF'\n{"a":"b${BS}nc"}\nEOF`);
});

test('silent: node running this hook with a JSON payload', () => {
  expectSilent(`node .claude/hooks/heredoc-backslash-warn.mjs <<'EOF'\n{"command":"a${BS}nb"}\nEOF`);
});

test('silent: cat heredoc piped into a python script', () => {
  expectSilent(`cat <<'EOF' | python3 parse.py\nC:${BS}Users\nEOF`);
});

test('silent: perl -pe program over heredoc data', () => {
  expectSilent(`perl -pe 's/a/b/' <<'EOF'\nx${BS}ny\nEOF`);
});

test('silent: python -m module over heredoc data', () => {
  expectSilent(`python3 -m json.tool <<'EOF'\n{"a":"b${BS}nc"}\nEOF`);
});

// A program option whose value is attached to it (`--eval=...`, `-c'...'`,
// a perl cluster ending in e) supplies the program, so the heredoc is data.
test('silent: node --eval= with the program attached', () => {
  expectSilent(`node --eval='0' <<'EOF'\nx${BS}ny\nEOF`);
});

test('silent: python -c with the program attached', () => {
  expectSilent(`python3 -c'import sys' <<'EOF'\nx${BS}ny\nEOF`);
});

test('silent: perl -lne cluster with the program attached', () => {
  expectSilent(`perl -lne'print' <<'EOF'\nx${BS}ny\nEOF`);
});

test('silent: python -Bc cluster, program in the next word', () => {
  expectSilent(`python3 -Bc 'import sys' <<'EOF'\nx${BS}ny\nEOF`);
});

// Redirections may come before or between the words of a command, so the
// script path can follow the heredoc and the command word can follow it too.
test('silent: script path after the heredoc operator', () => {
  expectSilent(`python3 <<'EOF' script.py\nx${BS}ny\nEOF`);
});

test('warns: interpreter after the heredoc operator', () => {
  expectWarn(`<<'EOF' python3 -\nprint('a${BS}nb')\nEOF`, 'python3');
});

test('warns: python -X utf8 - (option value is a separate word)', () => {
  expectWarn(`python -X utf8 - <<'EOF'\nprint('a${BS}nb')\nEOF`, 'python');
});

test('warns: perl -n cluster with no program option', () => {
  expectWarn(`perl -ln <<'EOF'\nprint "a${BS}n";\nEOF`, 'perl');
});

// The e in -0x1e is a hex digit of the record separator, not -e.
test('warns: perl -0x1e (hex digit e is not a program option)', () => {
  expectWarn(`perl -0x1e <<'EOF'\nprint "a${BS}n";\nEOF`, 'perl');
});

test('silent: || is not a pipe', () => {
  expectSilent(`cat <<'EOF' > f.txt || python3 -\na${BS}nb\nEOF`);
});

test('silent: python heredoc with no backslash', () => {
  expectSilent(`python - <<'EOF'\nprint('hello')\nEOF`);
});

test('silent: cat heredoc with backslashes written to a file', () => {
  expectSilent(`cat <<'EOF' > notes.md\na ${BS}r b ${BS}n\nEOF`);
});

test('silent: bash heredoc with backslashes', () => {
  expectSilent(`bash <<'EOF'\necho "a${BS}nb"\nEOF`);
});

test('silent: sh heredoc with backslashes', () => {
  expectSilent(`sh -s <<'EOF'\nprintf 'x${BS}n'\nEOF`);
});

test('silent: python -c one-liner with a backslash (documented choice)', () => {
  expectSilent(`python -c 'print("a${BS}nb")'`);
});

// The later lines would read as a heredoc body ending at `x` if `<<<` were
// parsed as `<<` with delimiter 'x'.
test('silent: here-string into python is not a heredoc', () => {
  expectSilent(`python <<< 'x'\nprintf 'a${BS}n'\nx`);
});

// If the tab before the closing delimiter were not stripped, the body would
// run on through the printf line and its backslash.
test('silent: <<- body ends at its tab-indented delimiter', () => {
  expectSilent(`python - <<-'EOF'\n\tprint('hi')\n\tEOF\nprintf 'x${BS}n'`);
});

test('silent: backslash outside the heredoc body (line continuation before it)', () => {
  expectSilent(`echo a ${BS}\n  b && python - <<'EOF'\nprint('hi')\nEOF`);
});

test('silent: backslash in a later non-heredoc command after the body', () => {
  expectSilent(`python - <<'EOF'\nprint('hi')\nEOF\nprintf 'x${BS}n'`);
});

test('silent: python heredoc into a file via cat, then python runs the file', () => {
  expectSilent(`cat > s.py <<'EOF'\nprint('${BS}n')\nEOF\npython s.py`);
});

test('silent: the word python inside a cat heredoc body', () => {
  expectSilent(`cat <<'EOF' > README\nrun python - <<X with ${BS}n\nEOF`);
});

// If the hook is ever wired under a wider matcher, it must check the tool
// itself. PowerShell here-strings are out of scope (see the hook header).
test('silent: a PowerShell call whose command text looks like a risky heredoc', () => {
  const r = run(JSON.stringify({ tool_name: 'PowerShell', tool_input: { command: `python - <<'EOF'\nprint('${BS}n')\nEOF` } }));
  assert.equal(r.code, 0);
  assert.equal(r.stdout, '');
});

test('silent: empty payload', () => {
  const r = run('');
  assert.equal(r.code, 0);
  assert.equal(r.stdout, '');
});

test('silent: Bash payload with no command string', () => {
  const r = run(JSON.stringify({ tool_name: 'Bash', tool_input: {} }));
  assert.equal(r.code, 0);
  assert.equal(r.stdout, '');
});

// --- could not run: says so, never blocks ---------------------------------

test('could not run: truncated JSON is reported, not silent, not blocking', () => {
  expectCouldNotRun('{"tool_name": "Bash", "tool_input": ');
});

test('could not run: a JSON payload that is not an object', () => {
  expectCouldNotRun('"just a string"');
});

test('could not run: a JSON array payload', () => {
  expectCouldNotRun('[]');
});
