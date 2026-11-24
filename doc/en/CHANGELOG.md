> 🇬🇧 **English translation** — canonical version (authoritative): CHANGELOG.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# CHANGELOG — fstats

All notable versions of `fstats`, from the most recent to the oldest.
Format inspired by [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Evidence (real outputs, tests) is in [doc/en/VERIFICATION.md](VERIFICATION.md).

---

## [2.16.2] — 2026-11-24 — P2 (wave 5): deterministic ties, --recursive tests; P2 COMPLETE

Last wave of the security register P2 backlog — the remaining items are
either fixed, or requalified ACCEPTED_DOCUMENTED with their justification.

### Fixed
- **ties without tie-break → unstable order** (Top Words, Top Chars):
  equal frequencies → ascending lexicographic order (ascending code
  point for chars). Two runs now give the same result byte for byte.
  **Documented order break**: at equal frequency, the order may differ
  from previous versions (e.g. `'a'` before `'ab'` now) — counters and
  sets are unchanged, only the order of ties changes (the old one was
  arbitrary, non-contractual).
- **`--recursive`/`--include`/`--exclude`/`--max-depth`: zero tests** →
  test 122 (sh + bat): reference tree, glob semantics measured and
  frozen (`*.txt` = root only — `*` does not cross `/` —, `**/*.txt` =
  recursive, `--exclude` on the full RELATIVE path, `--max-depth=N` =
  levels below the root).

### Accepted-and-documented (requalified, register §6)
- **`Halt()` in the low layers**: single-task CLI process — exiting
  lets the OS reclaim the memory; the cases with critical resources
  (stream dictionaries) release them EXPLICITLY before exiting; the
  main entry point unwinds its `try..finally` in the normal flow. An
  exception-refactor would be cosmetics with no user gain, at the
  price of an exit-code regression risk.
- **Homoglyphs** (Cyrillic `ЕRROR`) **and RTL characters**: detection
  would need a Unicode confusables table, outside the scope of a
  statistics tool; the quality counters (nonprintable, invalid_utf8)
  remain true to what they measure.

### GREEN CI (2026-11-24, run #28) — first green since v2.7.0

- Last runner failure: tests 120/121 (honest options) on test-windows
  only, 100% ASCII patterns. Repair: immediate capture of
  `%ERRORLEVEL%` + GEQ/LSS numeric comparison (the legacy form
  `if errorlevel 1 if not errorlevel 2`, read after a `set`, was
  fragile on the runner).
- **Run #28: test-windows AND test-linux green** (127/127 each). 254
  verifications executed by the GitHub machines.

### CI (2026-11-24, first push post-v2.7.0): explicit -Sg + test 105
- **test-windows failed at compilation**: the wildcard matcher
  (fstats_lex.pas, v2.15.0) uses GOTO/LABEL; the official fpc.cfg
  files embed `-Sgic` (green locally / on Linux), not the regenerated
  fpc.cfg of the CI. Exact local reproduction (minimal config +
  emptied ppu cache). Fix: **explicit `-Sg`** in ci.yml (2 smoke),
  run.sh (2), run.bat (2) + canonical command of the documents (README,
  doc/README, GUIDE, ROADMAPFULL, VERIFICATION, header fstats.pas).
- **test-linux, test 105** (--interactive gate profile) failed on a
  grep with accents ("Commande générée"): the console encoding of the
  wizard output depends on the inherited code page at launch ("mojibake
  NON DÉTERMINISTE", as documented in fstats.pas) — the bat twin, for
  its part, greps without accents and never failed. Fix: sh aligned
  with its twin; the assertion targets the content (exit 0 +
  "Commande" + "--check"). Tests 105 sh/bat instrumented: on failure,
  the output and exit code are printed to the CI log.
- VERIFICATION §5: complete incident log (including the local
  code-page-inherited ghost — identical binary, different outputs).

### Counting
- Tests 122 (recursive), 123 (tie-break). Batch: **70 PASS / 0 FAIL**.
  run.sh: 62 passed / 65 node-dependent failures (machine without
  node).

### Tests (node catch-up, 2026-11-24)
- Node LTS installed on the dev machine: the 65 node-dependent tests
  finally run locally → **127 passed / 0 failures in sh AND in bat**.
- **2 stale twin tests, aligned with the frozen semantics** (no
  behavior change in the code): test 56 — expected ids
  `delta:lines,delta:lines#2,sha256` since v2.16.0 (the v2.16+
  baseline carries sha256, the check is injected after the deltas);
  test 71 — `--pattern='*'` → **0/0** since v2.15.0 (zero-length match
  not counted, cf. test 114), the expectation "9/9 toutes les lignes"
  dated from the pre-wave-2 semantics. Both tests silent from day one
  (SKIP/FAIL node), never re-read for lack of node.

### Docs (paranoid/pedagogical pass of 2026-11-24)
- `ROADMAPFULL.md` caught up — it had been left stuck at v2.13.0:
  preamble "État du projet v2.16.2", § 11 updated (11 .pas files,
  `fstats_sha.pas` added), § 13 dated v2.16.2 + new entry "v4.0 —
  Durcissement sécurité LIVRÉ (P0 v2.13.1, P1 v2.14.0, P2 v2.14.1 →
  v2.16.2)", each item cross-checked against this CHANGELOG. The
  TARGET 1-3 roadmaps verified as conforming (statuses and gaps
  already traced).
- `README.md`: "100 cas d'acceptation" → **127** — **127 acceptance cases**
  (the tests 101-123 added from v2.13.1 to v2.16.2 had never been carried
  over there — same family of stale items as tests 56/71: a forgotten tally
  stays invisible as long as no machine verifies it).

### Multi-OS build scripts (2026-11-24, post-delivery)

- **New `build.*` / `clear.*` scripts**: real build scripts per OS and
  architecture, replacing `wbld.bat`/`wclr.bat` (removed) — Windows
  `build.bat`/`clear.bat` (32-bit → `bin\win32\`, 64-bit →
  `bin\win64\`), Linux `build.sh`/`clear.sh` in bash (`amd64` →
  `bin/amd64/`, `aarch64` → `bin/aarch64/`), recent macOS
  `buildmac.sh`/`clearmac.sh` in **zsh** (native aarch64 + cross
  x86_64), old Intel Macs `buildmac-intel.sh`/`clearmac-intel.sh` in
  bash 3.2-compatible (x86_64). Common points: `fpc` location (PATH
  then known install paths), **explicit `-Sg`** (matcher goto, lesson
  13), outputs isolated in `bin/<arch>/` (the test binaries at the
  root stay untouched), a missing target is reported cleanly without
  stopping the others (clear recap + exit 1), `clear.*` removes ONLY
  `bin/`, `*.ppu`, `*.o` and the compiled binaries (root and `src/`) —
  sources, tests, docs and examples untouched.
- **Verified locally (32-bit Windows workstation)**: `build.bat`
  compiles `fstats` + `fcmd` into `bin\win32\` (smoke `--version` +
  companion `--help` OK); the 64-bit target missing on that
  workstation produces the expected clean failure message (recap 1/2,
  exit 1); `build.sh` validated in failure mode from that same
  workstation (clean 0/2, empty folders purged); `clear.bat`/
  `clear.sh` verified; `bash -n` OK on the 6 `.sh`. **Honest scope**:
  zsh absent from the local environment — `buildmac.sh`/
  `clearmac.sh` are written in the common POSIX subset shared by
  zsh/bash, macOS execution remains to be confirmed on a target
  machine (traced in VERIFICATION).

---

## [2.16.1] — 2026-11-24 — P2 (wave 4): honest options messages, truthful help

### Fixed
- **Unknown option / missing value**: `--patern=x` (typo) or `--redact`
  (bare) were treated as FILE NAMES — the user got "Fichier inaccessible
  ou introuvable - --redact", which pointed them at the disk instead of
  at their command line. Now: `option inconnue :
  --xxx` / `l'option --redact exige une valeur` + exit 1. A file really
  named `--x` is spelled `./--x` (the message says so).
- **Lying `--top-lines` help**: since v2.8.0 the help said "0 = tous",
  while the code answers "0 = section désactivée" (and SEMANTIQUE
  repeated the error). Help + SEMANTIQUE corrected to the code's truth:
  `0 = désactivé`, option absent = disabled.

### Accepted-and-documented
- `%VAR%` expanded by cmd.exe at paste time (wizard): no reliable
  escape exists for `%` in interactive cmd — documented limitation
  (GUIDE § "%VAR%", cf. SEMANTIQUE), the generated command never
  introduces a `%` itself.

### Tests
- 120 (unknown option), 121 (missing value) in sh and bat. Windows:
  **68 PASS / 0 FAIL**.

---

## [2.16.0] — 2026-11-24 — P2 (wave 3): baseline SHA-256 integrity, CI verdict, --fail-on-delta inline

Third P2 wave: the **CI gate verdict**. Two discoveries along the way:
the inline form `--fail-on-delta=M>X` (documented since v2.6.0) **had
never worked** (off-by-one on the prefix, the option fell into the
"file" branch), and exit code 2 could be **ignored** when only an
injected check failed.

### Added
- **Baseline integrity (SHA-256)**: `--summary-json` emits a `sha256`
  key (FIPS 180-4, streaming, identical to `sha256sum`/`Get-FileHash` —
  parity tested + FIPS vectors). `--compare` verifies it: changed
  content → `sha256` check **FAIL + exit 2** (a drift invisible to the
  metrics: token replaced, line rewritten). Identical hash → `sha256`
  check ok. Old baseline without the key: skipped (backward
  compatible). stdin / unreadable file: key omitted, no verification.
  **Additive** break documented (SEMANTIQUE).
- **Readable final verdict**: the check-mode console output ends with
  `Verdict : OK/ATTENTION/ECHEC - exit N` (+ `N fichier(s) hors baseline`).
  Never in --json/--csv/--summary-json (pure formats, exit codes).
- **Out-of-baseline file made visible**: `--compare` + missing file →
  stderr warning `absent de la baseline` + a counter in the verdict
  (before: delta checks were ignored SILENTLY).

### Fixed
- **Inline `--fail-on-delta=M>X`** (bug present since v2.6.0):
  `Copy(Param,1,15) = '--fail-on-delta='` never matched (the prefix is
  16 long) and the value kept the `=` (`Copy(ParamOrig,16)` →
  `=words>10` → "métrique inconnue"). The option was treated as a
  **file**: `fstats --fail-on-delta=words>1 f.txt` analyzed f.txt AND
  looked for the file `--fail-on-delta=words>1`. Prefixes and offset
  fixed (16/17); the 3-argument form was correct, for its part.
- **Exit code ignored on injected check**: `--check --compare` without
  `--fail-if` with a diverging hash displayed FAIL but exited 0 (the
  gate required `Length(Checks) > 0`). The gate now counts every
  emitted check, including `sha256`.

### Tests
- 117 (console verdict OK/ECHEC + exit 0/2), 118 (out-of-baseline
  made visible), 119 (sha256 = sha256sum/Get-FileHash + tampering →
  FAIL + exit 2) — in run.sh AND run.bat. Windows: **66 PASS /
  0 FAIL**.

---

## [2.15.0] — 2026-11-24 — P2 (wave 2): linear matchers, anti-freeze, bounded lines/words

Second P2 wave: robustness on hostile input. A **1.6 KB** file plus an
innocent pattern (`*a*a*a*a*a*a*b` with no match) froze fstats at 100%
CPU **indefinitely** (exponential backtracking); a pattern matching
empty (`*`, `**`, `a||b`) **looped forever**. Both fixed and tested. As
a bonus, repairing the Windows test harness revealed four run.bat bugs
never executed to the end (detail below).

### Fixed
- **Linear wildcard matching (`--pattern`)** (fstats_lex.pas):
  `WildcardMatch`/`WildcardMatchAt` rewritten as an iterative greedy
  algorithm with two markers (last star + resume position) —
  O(len(P)×len(S)) worst case, zero recursion. The algorithm explores
  in the same order as the old one (minimal star first):
  binary-vs-v2.14.1 parity checked over 37 pattern×file combinations
  (23/23 on normalized JSON output, 0 diff).
- **Empty match = infinite loop killed**: `--pattern='*'` (or empty
  alternation segment `a||b`) produced zero-length matches and
  `StartPos := i + 0` looped back forever. An empty match is not an
  occurrence: move forward by one position without counting (test 114).
- **Linear `--regex-tag` mini-regex engine** (fstats_lex.pas):
  `MatchTagAt` rewritten as an NFA state-set simulation —
  O(len(S)×len(pattern)) per starting position, zero backtracking.
  Semantics documented: **longest match** from the position. Test 115:
  a 6.3 KB line with `a*a*a*b` — before, a freeze; after, instant.
- **Geometric-growth line/word buffer** (fstats_analyzer.pas):
  per-character accumulation `S := S + c` was nearly quadratic (32 MB
  on a single line = 18 s, measured). Amortized O(1) append: 32 MB →
  9 s (the rest is UTF-8 decoding code point by code point).
- **Bounded storage, exact metrics** (LINE_STORE_MAX = 65,536,
  WORD_STORE_MAX = 1,024): beyond that, the **stored** line/word
  (pattern matching, tags, log levels, Top Lines, longest word) is
  truncated — the metrics (lines, words, characters, min/max/avg
  lengths, quality counters) remain exact. Approximation documented
  (LIMITES + SEMANTIQUE).

### Windows test harness repaired (run.bat, never executed to the end)
- **LF line endings**: the file was 100% LF; cmd.exe requires CRLF —
  the batch crashed midway (ghost `after66`) and NEVER reached tests
  66+. Converted to CRLF: 63 PASS / 0 FAIL reached.
- **`set X=1 ` (trailing space)**: the space before `&&` is included in
  the value by cmd (`C101_OK="1 "` ≠ `"1"`) — 10 self-sabotaged tests.
  The quoted form `set "X=1"` applied.
- **`echo words^>5` in a pipe**: the caret is re-parsed by the child
  cmd — `>` became a redirection, the line never reached the wizard (a
  file named `5` got created!). Double caret `^^^>` applied.
- **`\\"` literal in the findstr calls**: three tests were searching
  for a string with backslashes that does not exist in the produced
  JSON.
- Tests 114 (pattern anti-freeze + empty match), 115 (tag NFA
  anti-freeze), 116 (104 KB line: exact metrics) added in sh and bat.

### Cleanup (dead code + version)
- `TokenMatchAt` removed (its only consumer was the old backtracking).
- Version 2.15.0 (FSTATS_VERSION, CMDGEN_VERSION).

---

## [2.14.1] — 2026-11-23 — P2 (wave 1): 64 KB boundary, WARNING, CSV formulas, visible gate, wizard UX

First wave of the security register P2 backlog. Each fix comes with a
dedicated test (111-113); bugs discovered by the audit, all
**re-tested at runtime** before the fix.

### Fixed
- **64 KB buffer boundary** (metric bug, tested alignment by
  alignment): a multi-byte character straddling two read blocks was
  counted as `invalid_utf8` (2 false positives per cut character) — a
  **valid** UTF-8 file failed the CI gate depending on its alignment
  (65,535 bytes + `é` → `invalid_utf8: 2`). Inter-block buffer zone:
  the remaining bytes are carried over to the head of the next block;
  an orphan sequence start at end of file stays counted invalid (a
  genuinely broken file). Verified on 6 alignments (65,530 to 65,540)
  + orphan + identical invalid fixtures.
- **`WARNING` recognized as a warn level** (whole word, alongside
  `WARN`): the most widespread real-world level (log4j, Python, Node)
  was classified `none`. `ERRORS` stays `none` (whole word, golden
  unchanged).
- **CSV formula injection neutralized**: `CsvEscape` prefixes an
  apostrophe onto values starting with `=`, `+`, `-`, `@` (OWASP
  practice) — `=cmd|"/c calc"!A0` (DDE) displays as text in
  Excel/Calc.
- **No-op gate made visible**: `--check` with no check defined prints
  a stderr warning ("le gate ne teste rien") — exit codes and outputs
  unchanged (CI backward compatible).
- **Wizard UX**: global numbers (1-49) displayed in the lists (the
  prompt asked for a number that was nowhere visible); a non-numeric
  entry at the category prompt no longer quits the session (message +
  re-prompt).
- **Dead code removed**: `OptModeAlarm` (never read), `PrevWords/Chars/
  Sentences` of the watch (prepared deltas never displayed),
  `BuildTopLinesJSON` (uncalled duplicate of `BuildTopLinesJSONRedact`).

### Verified (tests 111-113)
- 111: `é` straddling the boundary → `invalid_utf8: 0`; orphan → 1.
- 112: cell `=cmd` prefixed `'=cmd`, no bare `=cmd` cell.
- 113: `WARNING` + `WARN` → `warn: 2` (before: 1).
- Parity of 14 commands vs v2.11.0 (only diffs: the timestamp of the
  check messages, and the masking of Top Words with `--redact` — P1-3
  fix, intentional).
- 115 verifications in total (113 tests + 2 compilations — recounted).

---

## [2.14.0] — 2026-11-23 — P1 security (argv execution, --out guard, leak-free redaction)

The three P1 workstreams of the security audit (register:
`doc/AUDIT-SECURITE.md`), each fix verified by a dedicated test.

### Fixed
- **argv execution, never a shell** (P1-1): the wizard ran its command
  via `FpSystem` (`/bin/sh -c`) on Unix, and did not quote values that
  contained no spaces → `;`, `` ` ``, `$(…)` inside an entered value
  executed arbitrary code. Replaced with `SysUtils.ExecuteProcess`
  (separate argv: fork/execve, CreateProcess — no shell). The
  **displayed** command now also quotes the metacharacters
  (`& | < > ^ % !` /
  `; $ \` ( ) …`). Documented limit: `%VAR%` is still expanded by
  cmd.exe at paste time (register P2). `fcmd` finally refuses the
  silent PATH fallback (an arbitrary `fstats` from the PATH can no
  longer be executed in its place).
- **`--out` no longer destroys the input file** (P1-2): `Rewrite`
  used to happen before the analysis → `fstats f.txt --out=f.txt`
  emptied `f.txt` irreversibly. Guard: refuse (exit 1 + stderr) if
  `--out` designates an analyzed file (absolute paths compared, case
  ignored under Windows).
- **Leak-free `--redact`** (P1-3): redaction only covered
  top-lines/longest-lines; emails/IPs came out in clear in the
  **Top Words**, n-grams and **tags** (console, JSON, CSV, summary).
  `RedactString` is now applied at the 11 file-text emission points.
  Test 109: the email must appear in **no** output (grep over console +
  JSON + CSV + summary).

### Added
- Tests 109 (redaction anti-leak) and 110 (--out guard, intact input
  verified by byte comparison) in `run.sh`/`run.bat`: **110 tests +
  2 compilations = 112 verifications** in total.

### Verified
- Parity 17/17 commands vs v2.11.0 outside the scope of the fixes (only
  intentional diff: with `--redact`, one word containing a masked
  URL).
- Wizard battery replayed: 101-108 + isolated fcmd refuses the PATH
  fallback.

---

## [2.13.1] — 2026-11-23 — P0 fixes (dev × cyber × UX audit)

Fixes coming out of the cross-audit by three independent auditors
(architecture/security/UX), each finding re-verified at runtime.

### Fixed
- **Off-by-one `--pattern`** (`fstats_lex.pas`, `WildcardMatchAt`):
  `MatchLen` counted one character too many, **adjacent** occurrences
  were lost (`errorerrorerror` + `--pattern=error` → 2 instead of 3).
  Convention aligned with the tag engine (`EndSi - Start`). New golden
  tests 108/108b (`aaaa`/`aa` → 2, `error`×3 → 3). No existing
  fixture has adjacent occurrences: no existing counter changes.
- **Wizard conforming to the parser** (`fstats_cmdgen.pas`): the
  corpus profile no longer generates `--ngrams=2,3` (rejected by
  fstats) but `--ngrams=2`; `--csv-kind` (nonexistent option) replaced
  with `--csv=summary|words|chars`; `--histogram`: prompt corrected to
  `line_length|word_length|words_per_sentence`. Test 103 no longer
  freezes the string: the generated command is **executed** (103b,
  exit 0 expected).
- **Auto-derived version test** (`tests/run.sh` + `run.bat`): the
  suite had been **structurally red** since v2.12.0
  (`grep "2.11.0"` frozen). The expected version is now extracted from
  `src/fstats_types.pas`. Verified under sh and cmd.exe
  (`PASS: --version affiche fstats 2.13.1`).
- **`fcmd --profil=log|corpus|gate`**: the names promised by the
  README are accepted (not just the numbers).
- **`--help`: pure ASCII promise kept** ("génération" without its
  accent).

### Verified
- Parity: the counters remain identical to the v2.11.0 binary over 16
  commands covering all subsystems (the off-by-one only changes
  adjacent occurrences, absent from the fixtures).

---

## [2.13.0] — 2026-11-23 — Command-line generator companion (fcmd / --interactive)

### Added
- **`fstats --interactive`** (alias `--wizard`): built-in wizard that
  asks the questions (3 profiles: corpus / log / gate, then every
  option by category), displays the generated command and, on
  confirmation, re-runs itself with that command, **propagating the
  exit code** (useful in CI).
- **`fcmd`**: separate companion binary (`src/fcmd.pas`) with the same
  logic: `fcmd` (wizard + confirmation), `fcmd --dry-run` (only prints
  the command, copy-paste), `fcmd --exec` (runs it without asking),
  `fcmd --profil=N`, `fcmd --help`. The wizard can be driven through
  a pipe (`printf '2\n0\n' | fcmd --dry-run`).
- **`src/fstats_cmdgen.pas`**: shared logic (table of the 50 options,
  profiles, quoted shell generation, cross-platform child execution).
- 7 new acceptance tests (101-107) in `tests/run.sh` / `run.bat`:
  107 tests in total.

### Changed
- `wbld.bat` compiles both binaries (script renamed `build.bat` in
  2.16.2); CI: compilation smoke test of
  `fcmd.pas` in addition to `fstats.pas`.
- `--help` documents `--interactive`.

### Verified
- Parity: without `--interactive`, fstats v2.13.0 is identical to the
  v2.11.0 binary over 22 commands (output + exit code; only `--help`
  differs, one line added).
- Wizard tested over a pipe: profiles, option editing, EOF (exit 1),
  execution with exit-code propagation (fail-if `words>5` → exit 2).

---

## [2.12.0] — 2026-11-23 — Internal split into units (behavior unchanged)

### Changed
- `src/fstats.pas` (6,795 lines, single file) split into **8 flat
  units** in `src/` — same binary, zero added dependency, compilation
  command unchanged (`fpc -O2 -Mobjfpc src\fstats.pas`):
  - `fstats_types.pas`    : constants, globals, types (`TStats`, options…)
  - `fstats_utf8.pas`     : UTF-8, `VisualChar`, sorts, ANSI colors, `FormatFloatTrim`
  - `fstats_glob.pas`     : internal glob engine (`*`, `**`, `?`), `--recursive`
  - `fstats_lex.pas`      : tokenization, n-grams, patterns/redaction, log-level, regex-tag
  - `fstats_analyzer.pas` : `AnalyzeData/File/Stdin`, `WatchFile` (C3-D), Ctrl+C handlers
  - `fstats_checks.pas`   : checks engine, NDJSON baseline, `--compare`/`--fail-on-delta`
  - `fstats_output.pas`   : lexical/readability stats, console, JSON, CSV, usage
  - `fstats.pas`          : main program only (CLI parsing, orchestration)
- `FormatFloatTrim` hoisted into `fstats_utf8` to avoid a circular
  dependency `checks` ↔ `output`.

### Verified
- Parity with the v2.11.0 single-file binary: **50 commands**
  compared, identical output + exit code (golden `test_fr.txt`
  3/13/72/3, JSON ndjson/array/aggregate, `--summary-json`, CSV, glob,
  `--recursive`, `--watch`, `--mode=alarm`, `--redact`,
  `--log-level`/`--filter`, `--regex-tag`, checks + baseline
  `--compare`/`--fail-on-delta`, `--stdin`, `--help`, error cases).
- Identical binary footprint: 394,272 bytes of code, 19,828 bytes of
  data.
- `--version` = `fstats 2.12.0`.
- Docs: current versions updated to 2.12.0 (README, `doc/README.md`,
  `doc/GUIDE-PEDAGOGIQUE.md`, `doc/SEMANTIQUE.md`); historical
  references (dated sections of VERIFICATION.md, roadmaps) left as
  they are.

---

## [2.11.0] — 2026-11-23 — Target 3-D: watch

### Added
- `--watch` / `--follow`: periodic monitoring of a log file (polling),
  ASCII summary every `--interval` seconds until Ctrl+C (exit 0).
- `--interval=N`: watch period in seconds (default 2, min 1).
- Cross-platform Ctrl+C handler (Windows `SetConsoleCtrlHandler`,
  Linux `FpSignal` SIGINT/SIGTERM) → clean shutdown.
- Display of the line delta between two ticks (`+N`), `[TRUNCATED]`
  marker if the file shrank, levels if `--log-level`.
- Watch restricted to ONE file (stdin and multi-file → exit 1).
- **Target 3 (Log Sentinel) complete.** 100 acceptance tests.

### Limited (documented)
- Watch v1: full re-analysis of the file on each tick (no
  byte-by-byte incremental).

---

## [2.10.0] — 2026-11-23 — Target 3-C: alarm / tags

### Added
- `--regex-tag=PATTERN`: subset mini-regex engine (literals + `[...]`
  classes + quantifiers `?` `*` `+`) to extract and count tags
  (e.g. `PLC[0-9]+` → `PLC1`, `PLC23`). Non-overlapping occurrences.
- `--top-tags=N`: cap on the tag top (default 10, 0 = all, bounded
  memory).
- `--mode=alarm`: SCADA/PLC shortcut = `--log-level` + `--top-lines` +
  `--regex-tag` (default pattern `[A-Z]+[0-9]+`: `PLC1`, `TAG007`…).
- Exports: `Tags` console section, `tags` JSON block, flat key in
  `--summary-json`, `type=tag` CSV lines. 97 tests.

---

## [2.9.0] — 2026-11-23 — Target 3-B: log levels + filter

### Added
- `--log-level`: counts the lines per level (`ERROR` > `WARN` >
  `INFO` > `DEBUG` > `TRACE`, whole word, case-insensitive, anywhere
  in the line) + `none`. Sum of the 6 = `lines`.
- `--filter=error,warn,...`: filters the console display of the lines
  (`Top Lines`, `Longest Lines`) with rank renumbering; the global
  counters still cover the whole file.
- Exports: `Log Levels` console section, `log_levels` JSON block,
  flat key in `--summary-json`, `type=loglevel` CSV lines. 90 tests.

---

## [2.8.0] — 2026-11-23 — Target 3-A: patterns, top-lines, redaction

### Added
- `--pattern=TEXTE` (repeatable): per-line occurrence counting,
  internal matcher literal + `|` (alternation) + `*`/`?` (wildcards),
  case-insensitive, non-overlapping occurrences. `patterns` JSON
  block.
- `--top-lines=N`: top-N of identical lines (bounded memory like the
  n-grams). `top_lines` JSON block.
- `--redact=email,ipv4,url`: replaced with `***` in the outputs only;
  the counters still run on the raw text. 82 tests.

---

## [2.7.0] — 2026-08-26 — `--sentence-mode=basic|smart`

### Added
- `--sentence-mode=smart`: on top of `basic` mode, the `.` period is
  swallowed for a frozen list of fr/en abbreviations (`M.`, `Dr.`,
  `etc.`, `e.g.`…) and for URLs (`://` in the window of the last 8
  characters).
- `!` `?` `…` always close a sentence. 67 tests.

---

## [2.6.1] — 2026-08-26 — decimal fix

### Fixed
- A period **between two digits** (`3.14`) no longer closes a
  sentence. A period after a digit followed by a space (`Version 3.`)
  still closes. 59 tests.

---

## [2.6.0] — 2026-08-26 — Target 1 B+C: checks engine and baseline

### Added
- `--check`, `--fail-if=METRIQUE OP SEUIL`, `--warn-if=...` (10
  metrics, operators `> >= < <= = !=`, decimal thresholds).
- `--compare=BASELINE` (`--summary-json` NDJSON) +
  `--fail-on-delta=METRIQUE>X%`.
- Exit codes **0/1/2/3** in check mode (2 = fail, 3 = warn); analysis
  mode unchanged (0/1). `Checks` console section + `checks` JSON
  block. Dogfooded in CI. 56 tests.

---

## [2.5.0] — 2026-08-26 — C2-C: readability

### Added
- `--readability`: 4 metrics (`avg_sentence_words`, `avg_word_chars`,
  `pct_long_words`, a 0-100 score) **without syllables** (an
  approximation inspired by Flesch, formula frozen in SEMANTIQUE.md).
  39 tests.

---

## [2.4.0] — 2026-08-26 — C2-B: structure

### Added
- `--ngrams=N` (1..5), `--top-ngrams=K`, `--stopwords=fr|en|none`
  (per-line windows, bounded top-K).
- `--histogram=line_length|word_length|words_per_sentence`
  (ASCII bars).
- `--char-classes` (6 classes, sum = `characters`).
- Class-by-class aggregation in `--json-mode=aggregate`. 33 tests.

---

## [2.3.0] — 2026-08-26 — C2-A: lexicon

### Added
- `--word-mode=raw|ascii|unicode`, `--casefold=ascii|unicode|none`.
- `--lexical-stats`: `unique_words`, `hapax`, `type_token_ratio`,
  `average_word_length`, `entropy_bits_per_word`.
- `--top-words=N`, `--top-chars=N`, `--max-unique=N` (memory bound,
  default 100,000).
- **CSV v2** (documented break): header
  `file,type,rank,value,code_point,count,length`, sub-formats
  `summary|words|chars`. 22 tests.

---

## [2.2.0] — 2026-08-26 — Increment A: robustness and pipelines

### Added
- Standard input `-` / `--stdin` (cannot be mixed with files).
- Internal glob (`*`, `**`, `?`) + `--recursive=DIR`, `--include`,
  `--exclude`, `--max-depth=N`.
- Valid multi-file JSON: NDJSON by default,
  `--json-mode=array|aggregate`.
- `--summary-json` (flat object per file, ready for `jq`).
- Quality counters: `invalid_utf8`, `bom`, `crlf`, `tabs`,
  `nonprintable`.
- Pure ASCII console output guaranteed when piped (no ANSI). 12
  tests.

---

## Earlier versions (v2.1 and before)

- v2.1: basic analysis (lines, words, characters, sentences, top
  characters/words/lines), JSON/CSV v1 export, aligned console.
- v2.0: first public version (basic counters + JSON).
