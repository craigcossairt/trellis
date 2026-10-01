#!/usr/bin/env node
// =============================================================================
// .claude/hooks/heredoc-backslash-warn.mjs - OPTIONAL PreToolUse(Bash) warning
// =============================================================================
// Not wired by default. Needs node (18 or later) on PATH. To turn it on, add
// the entry shown in .claude/hooks/README.md (section "Optional hooks") to
// .claude/settings.json.
//
// The problem it catches: content written through `python - <<'EOF'` (or node,
// bun, perl) loses or transforms its backslashes. The interpreter reads the
// body as SOURCE, so an escape meant for the output becomes a real CR, NUL or
// backspace byte, and a line continuation collapses. In the project this was
// taken from, that shipped a NUL byte into a doc and split Markdown table rows
// repeatedly - including after a written note said in bold not to do it. A
// note cannot see the command; a hook can, at the moment it runs.
//
// It WARNS and never blocks: some backslashes in a heredoc are meant. A
// warning is exit 0 with JSON whose hookSpecificOutput.additionalContext reaches
// the agent beside the tool result (so after the command ran: the message
// leads with "verify the bytes"), plus a one-line systemMessage for the user.
// No permissionDecision is set, so the normal permission flow is untouched.
//
// Fires when a heredoc body holding a backslash is fed as SOURCE to python,
// python3, python3.x, py, node, bun or perl: the interpreter is the command
// word, or follows a known runner (so `timeout 60 python3 -` and
// `nice -n 10 node -` count, and `echo python -` does not), with no script
// path (or `-`) and no -c/-e/-p/-m program. That includes
// `cat <<EOF | cat | python -`, where the body still reaches the interpreter
// as source through each pipe stage. Stays silent for:
//   - heredocs that are stdin DATA: `python3 x.py <<EOF`, `perl -pe ... <<EOF`,
//     `python3 -m json.tool <<EOF`. The program gets the backslashes intact;
//   - heredocs into cat (written to a file), bash, sh or anything else;
//   - `python -c '...'` one-liners. Deliberate: a backslash there is almost
//     always an escape meant for the code (`'\n'.join`), the command is one
//     visible line, and warning on it would teach agents to ignore the hook;
//   - here-strings (`<<<`), which are not heredocs;
//   - PowerShell here-strings. Out of scope.
//
// Known misses, all rare: a `<<` inside quotes or `$((x<<y))` is read as a
// heredoc and swallows the lines after it; a line continuation between the
// interpreter and its `<<` hides the interpreter; an option that takes a
// separate value and is not listed in OPTIONS below reads the value as a
// script path; and a project-specific wrapper script in front of the
// interpreter is not a known runner - add its basename to RUNNERS below.
//
// A payload it cannot parse is reported, never silent and never blocking:
// exit 0 with a systemMessage saying the check could not run. "Could not read
// the command" is not "no heredoc", but a warn-only hook that blocked on its
// own input trouble would stop every Bash call for a helper's sake. An empty
// payload is silent.
//
// The Cursor, Grok and Codex adapters do not run this: they translate a
// block, and a non-blocking warning has no equivalent in their protocols yet.
//
// Pinned by .claude/hooks/tests/heredoc-backslash-warn.test.mjs (hooks CI).
// =============================================================================

import { readFileSync } from 'node:fs';

const BACKSLASH = String.fromCharCode(92);
const INTERPRETER = /^(python(\d+(\.\d+)*)?|py|node|bun|perl)$/;
// Commands that run a later word as the program. Any other command word means
// an interpreter name after it is only an argument.
const RUNNERS = new Set(['env', 'exec', 'command', 'time', 'sudo', 'nice', 'nohup', 'timeout', 'uv']);
// A heredoc operator, `<<` or `<<-`, never part of a `<<<` here-string. The
// delimiter is single-quoted, double-quoted, or a bare word (optionally
// backslash-quoted).
const HEREDOC = /(?<!<)<<(?!<)(-?)[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|\\?([A-Za-z_][\w.-]*))/g;

// The simple command ending at `text`'s end: the text after the last command
// separator. The `&` of a redirect (`2>&1`, `&>`) is not a separator.
function simpleCommand(text) {
  const masked = text.replace(/\d*>&\d*-?|&>>?/g, (m) => ' '.repeat(m.length));
  const cut = Math.max(
    masked.lastIndexOf('|'),
    masked.lastIndexOf(';'),
    masked.lastIndexOf('&'),
    masked.lastIndexOf('('),
    masked.lastIndexOf('`'),
  );
  return text.slice(cut + 1);
}

// Per interpreter: short option letters that supply the program (-c code,
// -m module, -e code), short letters that take a value (the rest of the
// cluster, or the next word when the letter ends it), long options that
// supply the program, and long options whose value is the next word.
const OPTIONS = {
  python: { program: 'cm', valued: 'WX', long: [], longValued: ['--check-hash-based-pycs'] },
  node: {
    program: 'ep',
    valued: 'r',
    long: ['--eval', '--print'],
    longValued: ['--require', '--import', '--loader', '--experimental-loader', '--input-type', '--env-file'],
  },
  bun: { program: 'ep', valued: 'r', long: ['--eval', '--print'], longValued: ['--preload', '--cwd', '--env-file'] },
  // perl: -0 and -l take optional digits; -i, -x, -C, -d, -D, -I, -M, -m take
  // the rest of the cluster.
  perl: { program: 'eE', valued: 'ixCdDIMm', digits: '0l', long: [], longValued: [] },
};

// What option word `a` means for interpreter `family`: 'program' (it, or the
// word after it, is the program), 'value' (the next word is its value), or
// 'flag'.
function optionKind(family, a) {
  const o = OPTIONS[family];
  if (a.startsWith('--')) {
    const name = a.split('=')[0];
    if (o.long.includes(name)) return 'program';
    if (!a.includes('=') && o.longValued.includes(name)) return 'value';
    return 'flag';
  }
  const cluster = a.slice(1);
  for (let i = 0; i < cluster.length; i += 1) {
    const ch = cluster[i];
    if (o.program.includes(ch)) return 'program';
    if (o.digits?.includes(ch)) {
      // perl -0 takes octal digits or x and hex digits (-0x1e: that e is a
      // digit, not -e); -l takes octal digits.
      const m = cluster.slice(i + 1).match(ch === '0' ? /^(x[0-9a-fA-F]*|[0-7]*)/ : /^[0-7]*/);
      i += m[0].length;
      continue;
    }
    if (o.valued.includes(ch)) return i === cluster.length - 1 ? 'value' : 'flag';
  }
  return 'flag';
}

// The interpreter in `segment` that would read stdin as SOURCE, or null.
// The command word is the first word that is not an assignment; only a known
// runner may put the interpreter later. Stdin is source only when the first
// non-option argument is `-` or absent: `python3 x.py <<EOF` hands the body
// to x.py as data, backslashes intact. An option that supplies the program
// (-c, -m, -e, --eval=..., a perl cluster such as -lne) makes the body data.
function stdinInterpreter(segment) {
  const words = segment.trim().split(/[ \t]+/).filter(Boolean);
  const baseOf = (w) => w.split(/[/\\]/).pop().toLowerCase().replace(/\.exe$/, '');
  const first = words.findIndex((w) => !/^[A-Za-z_]\w*=/.test(w));
  if (first === -1) return null;
  const limit = RUNNERS.has(baseOf(words[first])) ? words.length : first + 1;
  for (let k = first; k < limit; k += 1) {
    const base = baseOf(words[k]);
    if (!INTERPRETER.test(base)) continue;
    let args = words.slice(k + 1);
    if (base === 'bun' && args[0] === 'run') args = args.slice(1);
    for (let j = 0; j < args.length; j += 1) {
      const a = args[j];
      if (/^\d*[<>]/.test(a)) {
        if (/^\d*(>>?|<)$/.test(a)) j += 1; // `> file`: skip the target too
        continue;
      }
      if (a === '-') return base;
      if (a === '--') return args[j + 1] === undefined || args[j + 1] === '-' ? base : null;
      if (a.startsWith('-')) {
        const kind = optionKind(base.startsWith('py') ? 'python' : base, a);
        if (kind === 'program') return null;
        if (kind === 'value') j += 1;
        continue;
      }
      return null; // a script path
    }
    return base;
  }
  return null;
}

// Which interpreter, if any, reads the body of the heredoc at `line[index]`.
// Redirections may sit anywhere in a simple command (`<<EOF python3 -`,
// `python3 <<EOF script.py`), so the heredoc's own command is the text before
// it AND the text after it up to the next separator, with every heredoc
// operator removed.
function consumer(line, index, end) {
  const rest = line.slice(end).replace(/\d*>&\d*-?|&>>?/g, (m) => ' '.repeat(m.length));
  const parts = rest.split(/(\|\||&&|[|;&])/);
  const own = stdinInterpreter(`${simpleCommand(line.slice(0, index))} ${parts[0]}`.replace(HEREDOC, ' '));
  if (own) return own;
  // `cat <<EOF | cat | python -`: the body flows down the pipeline, through
  // any number of stages, until a `;`, `&&`, `||` or `&` ends it.
  for (let p = 1; p < parts.length; p += 2) {
    if (parts[p] !== '|') return null;
    const hit = stdinInterpreter(parts[p + 1] ?? '');
    if (hit) return hit;
  }
  return null;
}

// Interpreters that would read a backslash from a heredoc body in `command`.
function findRisky(command) {
  const lines = command.split('\n');
  const found = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const heredocs = [];
    for (const m of line.matchAll(HEREDOC)) {
      heredocs.push({
        strip: m[1] === '-',
        delim: m[2] ?? m[3] ?? m[4],
        target: consumer(line, m.index, m.index + m[0].length),
      });
    }
    i += 1;
    // Bodies follow the line, in operator order.
    for (const h of heredocs) {
      const body = [];
      while (i < lines.length) {
        const l = h.strip ? lines[i].replace(/^\t+/, '') : lines[i];
        i += 1;
        if (l === h.delim) break;
        body.push(l);
      }
      if (h.target && body.some((l) => l.includes(BACKSLASH))) found.push(h.target);
    }
  }
  return [...new Set(found)];
}

function warning(interpreters) {
  const which = interpreters.map((x) => `heredoc into ${x}`).join(' and ');
  return [
    `Backslash in a ${which}. That command has already run. The interpreter read the body as`,
    'source, so an escape meant for the output (backslash-r, backslash-0, backslash-b, a line',
    'continuation) may have landed as a real CR, NUL or backspace byte, or vanished.',
    'Now: verify the bytes it wrote. Run `cat -A <file>` and look for ^M, ^@ or ^H, or count control bytes.',
    'Next time, prefer:',
    '  - the Edit tool (or Write) for any file content that holds a backslash;',
    '  - building the character in code: chr(92) or bytes([92]) in Python, String.fromCharCode(92) in node.',
  ].join('\n');
}

const SILENT = { stdout: '' };

function couldNotRun(reason) {
  return { stdout: JSON.stringify({ systemMessage: `heredoc backslash check could not run: ${reason}. The command was not checked.` }) };
}

function checkPayload(raw) {
  if (!raw || raw.trim() === '') return SILENT;
  let data;
  try {
    data = JSON.parse(raw);
  } catch {
    data = undefined;
  }
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    return couldNotRun('could not parse the hook payload');
  }
  if (data.tool_name !== 'Bash') return SILENT;
  const command = data.tool_input?.command;
  if (typeof command !== 'string') return SILENT;
  const risky = findRisky(command);
  if (risky.length === 0) return SILENT;
  const out = {
    systemMessage: `Warning: backslash in a heredoc into ${risky.join(', ')}. Check the written bytes.`,
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      additionalContext: warning(risky),
    },
  };
  return { stdout: JSON.stringify(out) };
}

// Always runs: no "am I the main module" test, which silently fails when the
// script is reached through a symlinked path. Every outcome exits 0.
let r;
try {
  r = checkPayload(readFileSync(0, 'utf8'));
} catch {
  r = couldNotRun('could not read the hook payload');
}
if (r.stdout) process.stdout.write(r.stdout);
process.exitCode = 0;
