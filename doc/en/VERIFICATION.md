> 🇬🇧 **English translation** — canonical version (authoritative): doc/VERIFICATION.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# fstats - verification journal (real outputs)

> **Note (2026-08-26, post-restructuring)**: compilation happens from the
> repository root: `fpc -Sg -O2 -Mobjfpc src\fstats.pas` (explicit -Sg since
> the first CI push — the matcher uses GOTO/LABEL, absent from the minimal
> fpc.cfg).

## v2.16.2 — P2 wave 5 (2026-11-24) — P2 complete

### 1. Deterministic ties

File `zebre abricot` ×2: Top Words = `abricot` (2) then `zebre` (2) —
lexicographic order on equal frequencies (test 123; also verified on
chars: increasing code point). **Documented breaking change**: the v2.14.1
golden matrix produced `'ab'` before `'a'` (ties at 2) — v2.16.2 produces
`'a'` before `'ab'`: identical counters, new contractual order. The
sh/bat suites asserted no tie order: **no test broken** (61→62, 68→70
PASS, zero new FAIL).

### 2. --recursive: semantics measured, then frozen by tests

File tree: f1.txt (root) + sub/f2.txt + sub/f2.log + sub/deep/f3.txt:

| Command | Files | Observation |
|---|---|---|
| none | 4 | everything |
| `--include=*.txt` | 1 | `*` does not cross `/` |
| `--include=**/*.txt` | 3 | recursive |
| + `--max-depth=1` | 2 | one level below the root |
| + `--exclude=sub/deep/*` | 2 | full RELATIVE path |

Test 122 in sh and bat: the five counts verified on every run.

### 3. P2 scope status: COMPLETE

Backlog §5 of the register: waves 1 to 5 all handled (fixed or
requalified ACCEPTÉ_DOCUMENTÉ with justification). §6 keeps the owned
decisions, which read as limits, not as debts.

### 4. Node catch-up (2026-11-24): 127/127 on BOTH harnesses

Node LTS (v26.13.1) installed on the dev machine: the 65
node-dependent tests (JSON validation by a real parser), silent
locally all along (SKIP in bat, FAIL in sh), finally run.
**127 passed / 0 failed — in sh AND in bat** (254 verifications).

Two TWIN tests had gone stale unnoticed — aligned with the frozen
semantics, no behavior changed:

- **Test 56 (repetition ids + aggregate)**: expected the
  `delta:lines,delta:lines#2` of the --compare tests; since **v2.16.0**,
  a v2.16+ baseline carries `sha256` → the sha256 check is injected
  AFTER the deltas: `delta:lines,delta:lines#2,sha256`. Stale since
  wave 3.
- **Test 71 (wildcard `*`)**: expected 9/9 « toutes les lignes »
  (all lines; semantics ≤ v2.14.1: empty match counted per line); since
  **v2.15.0**, a ZERO-length match is NOT counted
  (SEMANTIQUE.md « Match de longueur nulle non compté », already
  covered by test 114): 0/0 expected and verified. Stale since wave 2 —
  never seen because node was missing.

Paranoid verification of the diagnosis: the 62 other formerly
node-dependent tests passed without touching the code — the 2 failures
were genuinely stale tests, not regressions.

### 5. First CI push (2026-11-24): -Sg failure (Windows) + test 105 (Linux)

First push of the repository since v2.7.0 (29 commits) → first real CI
run on the Targets 2-3 code + companion + P0/P1/P2 hardening.
**Two failures, two independent causes, reproduced before the fix:**

- **test-windows, smoke compilation step**:
  `fstats_lex.pas(581,3) GOTO and LABEL are not supported (use switch -Sg)`.
  Root cause: the wildcard matcher (v2.15.0) uses `goto`/`label`; the
  **official** `fpc.cfg` files embed `-Sgic` (hence the local and Linux
  green), but the CI regenerates a minimal `fpc.cfg` (only the `-Fu`) —
  the hidden switch disappeared. EXACT local reproduction (same lines
  581/606): minimal config + `-n` + **cleaning of the leftover
  .ppu/.o files** (otherwise FPC reuses the already-compiled units and
  the goto is no longer visited — lesson: a reproduction is only clean
  with the cache emptied). Fix: **explicit `-Sg`** on the 2 smoke
  compilations (ci.yml), the 2 in run.sh, the 2 in run.bat, and the
  canonical command of every document (a build must not depend on the
  machine's fpc.cfg).
- **test-linux, test 105** (`--interactive` profile gate, 'n'): failure
  without a trap door — the harness delivered no evidence. Local
  investigation: the grep targeted « Commande générée » — **accents
  included** — but the console encoding of the wizard output depends on
  the code page inherited at launch (the code documents it itself:
  « mojibake NON DÉTERMINISTE sous pipes », fstats.pas): the same
  binary produced here, ten minutes apart, a clean NFC « générée » and
  a degraded variant — a ghost seen by three local suites in a row,
  then gone. **The bat twin never had the problem: it greps
  « Commande » WITHOUT accents.** Fix: the sh aligned with its twin
  (grep « Commande » + « --check ») — the assertion targets the
  content, not the typography; tests 105 sh/bat instrumented (output
  dump + exit code in the CI journal at failure time).

Follow-up: re-observation on the next run — if 105 recurs in CI, the
self-printed proof will decide the final fix, no blind reruns.

### 6. GREEN CI on both sides (run #28, 2026-11-24) — first green since v2.7.0

After -Sg (lesson 13) and the alignment of test 105: one last
runner-specific failure remained on test-windows — tests 120/121
(honest options) failed ON THE RUNNER only, with patterns that were
100% ASCII anyway (no code page involved). Repair by instrumentation:
**immediate** capture of the exit code (`set C120_ST=%ERRORLEVEL%`
right at the call) + **numeric** comparison (`if %C120_ST% GEQ 1 if
%C120_ST% LSS 2`) instead of the inherited form `if errorlevel 1 if not
errorlevel 2` read AFTER a `set` — a fragile form whose behavior varied
on the runner. Run #28: **test-windows AND test-linux green**
(127/127 each) — the entire scope (Targets 1-2-3, companion,
P0/P1/P2) validated by GitHub machines, not just the dev machine.
Takeaway: an exit-code capture must be immediate and numeric — any
separator between the command and its reading is a candidate for loss.

---

## v2.16.1 — P2 wave 4 (2026-11-24)

### 1. Misleading options: before/after verified

BEFORE: `fstats --redact f.txt` → `Erreur: Fichier inaccessible ou
introuvable - --redact` (the option treated as a nonexistent file;
the user was looking for a disk failure). `--patern=x` (typo): same
message. AFTER: `l'option --redact exige une valeur (écriture :
--redact=VALEUR)` / `option inconnue : --patern=x [...] préfixez-le :
./--patern=x` — exit 1 in both cases (verified).

### 2. top-lines help: the truth of the code

`--top-lines=0` on app.log: no Top Lines section (disabled);
`--top-lines=3`: a 3-line section. The help said « 0 = tous » ('0 =
all') since v2.8.0: fixed in the help AND in SEMANTIQUE (which
repeated the error).

### 3. Regressions

Normal files analyzed without `--`: unchanged (exit 0, `fstats
fstats.exe` still works — a file named `--x` MUST now be prefixed;
documented breaking change). Candidate false positives reviewed: bare
`--top-lines` (legal, default 10), `-` (stdin), `--` never reached
because Length > 2.

Counting: batch **68 PASS / 0 FAIL**; run.sh 60 passed / 65
node-dependent failures (machine without node, unchanged since
v2.14.1).

---

## v2.16.0 — P2 wave 3 (2026-11-24)

### 1. SHA-256: implementation validated at three levels

- FIPS 180-4 vectors: "abc" → `ba7816bf…015ad` ✓, empty string →
  `e3b0c442…b855` ✓ (a dedicated mini test program).
- Tool parity: `--summary-json tests/fixtures/test_fr.txt` emits
  `sha256: eba4cf176f…bb91` = `sha256sum` to the character (test 119,
  likewise `Get-FileHash` on the Windows side).
- Streaming: hashing in 64 KB blocks, bounded memory (the unit never
  loads the file).

### 2. Baseline integrity: tampering caught

Baseline created on a file, file rewritten with the SAME number of
lines and near-identical words → console check `sha256 != 0 : FAIL
(actual 1)` + **exit 2** (before: stable metrics masked the drift).
Intact file → `sha256` check ok, exit 0. Pre-2.16.0 baseline (without
the key) → silent skip, backward compatible (verified by regenerating
a baseline by hand without the key).

### 3. Console verdict + out-of-baseline visible

`--check --fail-if ...` → last line `Verdict : OK/ATTENTION/ECHEC —
exit N` (exit verified consistent). `--compare` + file missing from
the baseline → stderr `absent de la baseline : checks de derive
ignores` + line `N fichier(s) hors baseline` in the verdict (before:
silence).

### 4. --fail-on-delta inline bug (v2.6.0 → 2.16.0)

`fstats '--fail-on-delta=words>10' --compare=B --check f.txt` BEFORE:
`Erreur: Fichier inaccessible ou introuvable - --fail-on-delta=words>10`
(the option treated as a file); only the spaced form worked. AFTER:
all three forms (`=`, `:`, space) work — tested by hand on the three
forms + consistent exit codes.

### 5. Exit code of an injected check

`--check --compare` with no other check + divergent hash BEFORE: FAIL
displayed, **exit 0** (gate conditioned on Length(Checks)>0). AFTER:
exit 2. The gate condition counts every emitted check (ChecksEmitted).

### 6. Suite counting

run.bat: **66 PASS / 0 FAIL** (117-119 included). run.sh: 58 passed /
65 failures, all node-dependent (node absent from the machine; along
the way: test 48's node-independent counter confirms the delta
behavior without node via the Windows batch, which runs it natively).

---

## v2.15.0 — P2 wave 2 (2026-11-24)

### 1. Generic pattern matching: hang demonstrated, linearity demonstrated

Old v2.14.1 binary (kept as the oracle): a **1,601-byte** file (prefix
`a`×1600 + `x`, one line) + `--pattern='*a*a*a*a*a*a*b'` → **killed at
the 20 s timeout, CPU 100%** (exponential backtracking). New v2.15.0
binary: same file → exit 0 **immediately**. Constructed worst case
(20,800-byte line, non-matching pattern) → 1 s.

### 2. Infinite loop on the empty match (a hang, not slowness)

v2.14.1: `--pattern='*'`, `--pattern='**'`, `--pattern='a||b'` (empty
alternation segment) → **infinite loop** (zero-length match,
`StartPos` never advances). v2.15.0: `--json --pattern='*'` terminates,
output `"lines": 0, "matches": 0`. Test 114 (sh + bat).

### 3. Oracle parity (golden): 23/23

37 reference JSON outputs captured with the v2.14.1 binary BEFORE the
changes: 16 `--pattern` patterns (multiple stars, `?`, alternations,
adjacencies `errorerrorerror`, case, `|`), 9 `--regex-tag` patterns
(classes, nested quantifiers `A*B*C`, `[0-9]*[a-z]+`), `--mode=alarm`,
full fixtures + combination. Capturing the oracle's « hang » patterns
was done under a watchdog (3 patterns excluded from the comparison:
`*`, `**`, `a||b` — their oracle IS the hang, cf. §2). Replayed after:
**23/23 identical** after version/timestamp normalization. The greedy
min-first algorithm reproduces the old DFS exploration order.

### 4. NFA tags: linear

`--regex-tag='a*a*a*b'` on a 6,300-character line: v2.15.0 immediate
(before: backtracking). Test 115 (sh + bat). Documented semantics:
longest match from each position.

### 5. Giant line: exact metrics, bounded storage

A single 33,554,432-byte line (`q` + LF): `lines: 1`, `characters:
33 554 433`, `line_max: 33 554 432` — **exact**. Time: 9 s (v2.14.1:
16 s; initial audit: 18 s with quadratic concatenation + 32 MB kept in
memory). Amortized O(1) append (geometrically growing buffer), bounded
storage `LINE_STORE_MAX` (65 536) / `WORD_STORE_MAX` (1 024). Test 116
(sh + bat): a line of 104,000 `q` → `line_max: 104000`, `characters:
104001`, `words: 1`.

### 6. Windows harness repaired: 63 PASS / 0 FAIL

The run.bat committed in v2.14.1 **had never run to the end**:
- LF line endings while cmd.exe requires CRLF → parse crash at test
  65+ (ghost « after66 »);
- `set C101_OK=1 || …`: the **space before `&&` is included in the
  value** (`"1 "` ≠ `"1"`) → 10 self-sabotaged tests (the
  mini-reproducer displayed `C101_OK=[1 ]`);
- `echo words^>5` in a pipe: the caret is re-scanned by the child cmd
  → `>` became a redirection; the line never reached the wizard, a
  file named `5` was created on disk (observed);
- `\\\"` literals in three findstr: searching for a string that does
  not exist in the JSON.

After CRLF conversion + quoted `set "X=1"` + `^^^>` + fixed findstr:
**63 PASS, 0 FAIL, RESULTAT reached** (the node tests skip for lack of
node on the machine). run.sh: 55 passed + 65 failures, **all
node-dependent** (node absent, pre-existing).

### 7. Compilation and counting

`fpc -O2 -Mobjfpc -FE. src/fstats.pas` and `src/fcmd.pas`: OK.
`fstats --version` = `fstats 2.15.0`; `fcmd --help` = `fcmd v2.15.0`.

---

## v2.14.1 — P2 wave 1 (2026-11-23)

### 1. 64 KB buffer boundary (CI metric bug)

Tested finding: a prefix of 65,535 'a' + `é` (a 2-byte sequence
straddling the boundary) → `invalid_utf8: 2` on a **valid** file (the
`--fail-if non_utf8>0` gate rejected a healthy file depending on its
alignment). Fix: an inter-block buffer zone (leftover bytes carried at
the head of the next block; end-of-file orphan still counted invalid).
After: 6 alignments tested (65 530/65534/65535/65536/65537/65540) →
`invalid_utf8: 0`; `invalid-utf8.bin` (real corruption) → 1, identical
before/after; `aaa\xC3` orphan → 1. Test 111.

### 2. WARNING recognized as a level

`printf 'WARNING disk full / WARN slow / ERROR bad'` + `--log-level`:
`Warn: 2` (before: 1 — WARNING was classified `none`). `ERRORS` stays
`none` (test 86 unchanged). Test 113.

### 3. CSV formulas neutralized

Line `=cmd|"/c calc"!A0 in log` + `--csv`: exported cell
`"'=cmd|""/c calc""!A0 in log"` — prefix apostrophe (OWASP), Excel/Calc
see text. No bare `=cmd` cell. Test 112.

### 4. No-op gate + wizard UX + dead code

- `--check` with no check: stderr `Attention: mode check actif sans
  aucun check defini...`, exit 0 unchanged; no warning when a check
  exists.
- Wizard: global numbers displayed (`[29] --mode = alarm  (actif)`);
  non-numeric input → `[?] entrez un numero de 0 a 7` + re-prompt
  (the session is no longer swallowed).
- Removed (verified dead code): `OptModeAlarm`, `PrevWords/PrevChars/
  PrevSentences`, `BuildTopLinesJSON`. Wizard battery 101-108 replayed
  OK.

### 5. Parity

14 commands vs v2.11.0; only diffs: check-message timestamps (a
battery false positive) and Top Words masking with `--redact` (the
intended P1-3 fix). No fixture has a line starting with `=` nor a
file > 64 KB → no golden impacted.

`--version` = `fstats 2.14.1`. Counting: run.sh = **115** report =
2 compilations + **113 tests**. Dogfood: exit 0.

## v2.14.0 — P1 security (2026-11-23)

### 1. P1-1: argv execution (no more shell)

`RunAndWait` (assembled command line, `FpSystem` = `sh -c` under Unix)
replaced by `RunArgs`/`RunTokens` (`SysUtils.ExecuteProcess`:
fork/execve, CreateProcess — the OS receives an argv, no metacharacter
is interpreted). Wizard battery replayed: 101-108 OK, exit 2
propagated (106), `--exec` OK (103b, 107). `fcmd` isolated (no fstats
beside it): explicit refusal exit 1, no more silent PATH fallback.
`CmdQuote` quotes metacharacters for display.

### 2. P1-2: the --out guard

Before: `fstats f.txt --out=f.txt` → file emptied, exit 1 (data loss).
After: `Erreur: --out (...) designe un fichier analyse (...) - refus`,
exit 1, **input file intact** (verified by a byte diff). Test 110.

### 3. P1-3: leak-free redaction

Before: `--redact=email` on a log containing `jean.dupont@corp.example`
→ the email came out in clear in Top Words
(`'jean.dupont@corp.example' 3`). After: `'***'`. `RedactString`
applied to the 11 emission points (console words, JSON
words/ngrams/tags ×3 formats, CSV words/tags). Test 109: grep
`jean.dupont` = 0 occurrence across console + JSON + CSV +
summary-json. Tests 74-77 (longest_lines, already covered before)
unchanged.

### 4. Parity

17/17 commands identical to the v2.11.0 binary (outside the fixes'
scope). Only intended diff: with `--redact`, a Top Words word
containing a URL masked (`***` instead of
`'https://internal.example.com...`). `--version` = `fstats 2.14.0`.
Counting (recounted): run.sh = **112** report = 2 compilations +
**110 tests** (new in 2.14.0: 109 anti-leak and 110 the --out guard).

`--version` = `fstats 2.14.0`. Dogfood: exit 0.

## v2.13.1 — P0 fixes from the cross audit (2026-11-23)

Cross audit dev × cyber × UX (three independent auditors, findings
re-tested one by one). Verified P0 fixes:

### 1. Off-by-one in `--pattern` (fstats_lex.pas)

Before: `fstats --pattern=error` on `errorerrorerror` →
`"matches": 2`. After: `"matches": 3` (the `EndSi - Start` convention,
aligned with `MatchTagAt`). No adjacent occurrences in the fixtures:
existing golden tests (matches=4/5/3/9) unchanged, 16/16 parity vs
v2.11.0 confirmed.

### 2. Wizard generating commands fstats rejected

Before: corpus profile → `--ngrams=2,3` → `Erreur: --ngrams attend un
entier de 1 a 5`; nonexistent `--csv-kind`/`--histogram=sentence_words`
prompts. After: corpus profile → `fstats --ngrams=2 --lexical-stats
--readability --json` — **executed** (exit 0). Histogram prompt fixed
to `words_per_sentence`, `--csv-kind` → `--csv=summary|words|chars`.
Test 103 now executes the generated command (103b).

### 3. Structurally red test suite (since v2.12.0)

`run.sh:142`/`run.bat:136` hard-coded a grep for `"2.11.0"`. The
expected version is now **derived** from `src/fstats_types.pas`:
- sh: `PASS: --version affiche fstats 2.13.1 (derivation auto)`
- cmd.exe (the exact replayed run.bat block):
  `PASS: --version affiche fstats 2.13.1`

### 4. Miscellaneous

- `fcmd --profil=log|corpus|gate` accepted (the README promised it).
- `--help` without accents (the « pure ASCII » promise).
- New tests: 103b (generated command executed), 108/108b (adjacent
  occurrences). Total: 110 verifications in run.sh (2 compiles + 108
  tests), the same in run.bat.

`--version` = `fstats 2.13.1`. Dogfood: exit 0.

## v2.12.0 — internal split into units (2026-11-23)

### 1. Compilation

`fpc -O2 -Mobjfpc -FE. src/fstats.pas`: exit=0

```
7081 lines compiled, 2.0 sec, 394272 bytes code, 19828 bytes data
```

A footprint **identical** to the v2.11.0 single file (394,272 / 19,828
bytes).

### 2. Structure

`src/` = 8 flat units: `fstats.pas` (main alone, 1,444 lines) +
`fstats_types` (338) + `fstats_utf8` (504) + `fstats_glob` (394) +
`fstats_lex` (1,229) + `fstats_analyzer` (820) + `fstats_checks`
(829) + `fstats_output` (1,523). The compilation command is
unchanged: fpc finds the units in `src/`.

### 3. Parity vs the pre-split binary (v2.11.0)

50 commands compared (standard output/err + exit code): **all
identical** — golden `test_fr.txt` (lines 3, words 13, characters 72,
sentences 3), `--json` (ndjson/array/aggregate), `--summary-json`,
`--csv`, `--all`/`--char`/`--word`/`--line`, `--top-words`/`--top-chars`,
`--ngrams`, `--char-classes`, `--readability`, `--lexical-stats`,
`--sentence-mode`, `--word-mode`, `--case-fold`, `--max-unique`,
`--mode=alarm`, `--pattern`, `--top-lines`, `--redact`, `--log-level`,
`--filter`, `--regex-tag`, `--check`/`--fail-if`/`--warn-if` (exit
0/2/3), `--compare`/`--fail-on-delta`, `--watch=0`,
`--recursive`/`--include`/`--exclude`, direct glob `*.txt`,
`--no-color`/`--color`, `--quiet --out`, `--stdin`, `--help`, unknown
option (exit 1), missing file (exit 1).

`--version` = `fstats 2.12.0`.

### 4. Doc cross-checked against the code (2026-11-23)

- The 47 `--help` options: all present in README.md and SEMANTIQUE.md.
- Gate metrics (code `CanonMetricFailIf` = README: `lines`, `words`,
  `sentences`, `max_line_length`, `avg_words_per_sentence`/`avg_sentence_words`,
  `non_utf8`/`invalid_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`).
- Exit codes 0/1/2/3 (`Halt(0..3)` in the main = doc).
- 100 tests in `tests/run.sh`/`run.bat` = CHANGELOG v2.11.0.
- Compilation command unchanged and valid everywhere (`wbld.bat`,
  `tests/run.*`, CI smoke, `doc/README.md`, GUIDE).
- Current versions bumped to 2.12.0 in README, `doc/README.md`,
  `doc/GUIDE-PEDAGOGIQUE.md`, `doc/SEMANTIQUE.md` (the `--version`
  examples and the sample JSONs' `"version"`).
- Local dogfood (as in the CI): `fstats --check --fail-if non_utf8>0
  --fail-if bom>0 --fail-if nonprintable>0 README.md CHANGELOG.md doc/*.md
  src/*.pas` → exit 0.

Generated on: 2026-08-26 11:56 - executable: `fstats.exe`
(`fstats 2.2.0`)
Scope: increment A of ROADMAP-CIBLE1.md (stdin, internal glob,
recursion, valid multi-file NDJSON/array/aggregate JSON,
`--summary-json`, quality counters). The historical counters are
unchanged vs v2.1.

## v2.13.0 — companion fcmd / --interactive (2026-11-23)

### 1. Compilation

`fpc -O2 -Mobjfpc -FE. src/fstats.pas`: exit=0 (1875 lines)
`fpc -O2 -Mobjfpc -FE. src/fcmd.pas`: exit=0 (113 lines)
`--version` = `fstats 2.13.0`; `fcmd --help` = the companion's help.

### 2. Parity (outside --interactive)

22 commands compared vs the v2.11.0 binary (output + exit code,
except `--help` which gains a line): **all identical** — golden
test_fr.txt 3/13/72/3, JSON/CSV/aggregate, sentinel (alarm, pattern,
redact, log-level, regex-tag), checks+baseline, watch=0, recursive,
glob, stdin, errors.

### 3. Wizard over a pipe (tests 101-107 from run.sh/run.bat, replayed here)

- `fcmd --help` → exit 0, contains « compagnon ».
- `printf '2\n0\n' | fcmd --dry-run` → `fstats --mode=alarm --top-lines=10 --redact=email,ipv4,url`.
- `printf '4\n1\nf\ntests/fixtures/app.log\n2\n15\n2,3\n0\n' | fcmd --dry-run`
  → `fstats tests/fixtures/app.log --ngrams=2,3`.
- `printf '' | fcmd --dry-run` → exit 1 (EOF).
- `printf '3\n1\nf\ntests/fixtures/test_fr.txt\n0\nn\n' | fstats --interactive`
  → exit 0, command displayed with `--check`.
- `printf '3\n1\nf\ntests/fixtures/test_fr.txt\n5\n40\nwords>5\n0\no\n' | fstats --interactive`
  → **exit 2 propagated** (fail-if words>5 on 13 words).
- `printf '2\n1\nf\ntests/fixtures/alarms.log\n0\n' | fcmd --exec`
  → exit 0, fstats executed (output « Lines: »).

### 4. Dogfood

`fstats --check --fail-if non_utf8>0 --fail-if bom>0 --fail-if nonprintable>0
README.md CHANGELOG.md doc/*.md src/*.pas` → exit 0.

---

## 1. Compilation

`fpc -O2 -Mobjfpc fstats.pas`: exit=0
`2397 lines compiled, 0.9 sec, 318464 bytes code, 19460 bytes data`

## 2. Reference counters (test_fr.txt) - unchanged vs v2.1

Expected: lines 3, words 13, characters 72, sentences 3, avg
words/sentence 4, min/max/avg 16/30/23. Console (exit=0):

```
File: test_fr.txt
Generated: 2026-08-26 11:34:44

Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23
```

Note: no `Quality` section for a clean file - the console output of
clean files is strictly identical to v2.1's.

## 3. Exit codes (stdout/stderr separated)

| Case | Exit | stdout | stderr |
|---|---|---|---|
| Success: fstats test_fr.txt | 0 | data | (empty) |
| Missing file: fstats absent.txt | 1 | (empty) | `Erreur: Fichier inaccessible ou introuvable - ...` |
| No argument: fstats | 1 | (empty) | usage |
| --help | 0 | usage | (empty) |
| --version | 0 | `fstats 2.2.0` | (empty) |
| stdin + file: fstats - test_fr.txt | 1 | (empty) | error message |
| Glob with no match: fstats 'nope/**/*.xyz' | 1 | (empty) | error message (CI gate never silently empty) |
| Conflict: --json --csv --out=x | 1 | (empty) | `Erreur: avec --out, choisissez seulement --json ou --csv.` |

## 4. stdin

`echo "un deux trois." | fstats - --json`: exit=0, valid JSON object
(node parse), `"file": "stdin"`, `words: 3`, `sentences: 1`.

## 5. Multi-file JSON: NDJSON (v2.2.0 default, fixes the v2.1 concat)

`fstats tests\fixtures\bom.txt tests\fixtures\crlf.txt --json`: exit=0,
2 JSON lines, each parsed individually by node:

- line 0: `bom=true`, `crlf=0` (file with a UTF-8 BOM)
- line 1: `bom=false`, `crlf=2` (file with 2 CRLF line endings)

## 6. --json-mode=aggregate

`fstats tests\docs\**\*.md --json-mode=aggregate`: exit=0, 3 files
found by the recursive glob (`tests\docs\readme.md`, `guide\api.md`,
`guide\usage.md`), totals = the exact sum of the statistics:

```
totals: files=3 lines=9 words=21 characters=123 sentences=3
```

## 7. --summary-json

`fstats --summary-json test_fr.txt`: exit=0, valid flat JSON object
(node parse):

```json
{"file": "test_fr.txt", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

## 8. Quality counters (fixtures)

| Fixture | invalid_utf8 | bom | crlf | tabs | nonprintable |
|---|---|---|---|---|---|
| tests\fixtures\bom.txt | 0 | true | 0 | 0 | 0 |
| tests\fixtures\crlf.txt | 0 | false | 2 | 0 | 0 |
| tests\fixtures\tabs.txt | 0 | false | 0 | 2 | 0 |
| tests\fixtures\long-line.txt | 0 | false | 0 | 0 | 0 (line_max=177) |
| tests\fixtures\invalid-utf8.bin | 1 | false | 0 | 0 | 0 |

## 9. Piped output: no ANSI sequences

Byte-level verification (search for ESC 0x1B) on piped
`fstats test_fr.txt`: no occurrence (expected: none).

## 10. Automated test suite

`tests\run.bat` (CMD, CI-friendly, no Pause): exit=0

```
PASS: compilation : fpc -O2 -Mobjfpc fstats.pas [exit 0]
PASS: test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23
PASS: stdin : echo "un deux trois." | fstats - --json [words=3]
PASS: stdin + fichier : fstats - test_fr.txt -> exit 1 + message stderr
PASS: NDJSON : 2 fichiers -> 2 lignes parseables [bom=true, crlf=2]
PASS: aggregate : tests\docs\**\*.md -> 3 fichiers, totaux coherents
PASS: --summary-json test_fr.txt -> objet plat JSON valide
PASS: fixture invalid-utf8.bin : invalid_utf8 > 0 dans le JSON
PASS: fstats absent.txt -> exit 1, stdout vide, message stderr
PASS: glob sans correspondance -> exit 1 [gate CI jamais silencieusement vide]
PASS: sortie console pipee : aucune sequence ANSI [ESC]
PASS: --version affiche 2.2.0

RESULTAT : 12 reussi, 0 echec(s)
```

`tests/run.sh`: the bash equivalent (same set of cases).

## Conclusion

Increment A (v2.2.0) meets all the acceptance criteria of
ROADMAP-CIBLE1.md: clean compilation, unchanged historical counters,
stdin, internal glob/recursion, valid multi-file JSON (NDJSON by
default, array/aggregate), --summary-json, quality counters, exit
codes 0/1 kept in analysis mode, pure ASCII output in pipes.
---

## C2-A « Lexicon » increment (v2.3.0) — 2026-08-26

Validation of the implementation of `doc/ROADMAP-CIBLE2.md` (C2-A:
--word-mode, --casefold, --lexical-stats, --top-words/--top-chars,
--max-unique, CSV v2). Binary compiled from `src/fstats.pas` (single
file, standard FPC RTL).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas`: exit=0

```
2795 lines compiled, 1.2 sec, 326416 bytes code, 19492 bytes data
```

### 2. Default-mode regression (test_fr.txt, unchanged)

`fstats --summary-json tests/fixtures/test_fr.txt`: 3/13/72/3, avg 4,
min/max/avg 16/30/23, same fields (no lexical key without
--lexical-stats):

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.3.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. --word-mode=ascii (corpus_en.txt, golden)

`fstats --summary-json --word-mode=ascii tests/fixtures/corpus_en.txt`:
`"words": 11` (punctuation removed: "Hello," -> "Hello", "test." ->
"test").

### 4. --word-mode=unicode (corpus_fr.txt, golden)

`fstats --summary-json --word-mode=unicode tests/fixtures/corpus_fr.txt`:
`"words": 19` (punctuation and apostrophes split; accents stay inside
the words).

### 5. --casefold (corpus_fr.txt)

`fstats --summary-json --lexical-stats --casefold=unicode tests/fixtures/corpus_fr.txt`:
`words=20, unique_words=16` — "Été" and "été" merge (basic table).

`--casefold=none`: `unique_words=17` (case preserved, "Été" != "été").

### 6. --lexical-stats (JSON)

`fstats --json --lexical-stats tests/fixtures/test_fr.txt` (exit=0,
JSON parsed by node): additive `"lexical"` block after `quality`,
existing keys unchanged, `schema_version` stays "1.0":

```
"lexical": { "unique_words": 12, "hapax": 11, "type_token_ratio": 0.923077,
             "average_word_length": 4.615385, "entropy_bits_per_word": 3.546594 }
```

Node checks: TTR = types/tokens (12/13), entropy within [0, log2(12)].
Console (dedicated section, pure ASCII):

```
Lexical
-------
  Unique words:       17
  Hapax:              14
  Type-token ratio: 0.85
  Avg word length:  3.75
  Entropy:        4.0219
```

### 7. --top-words / --top-chars

`fstats --json --top-words=5 --top-chars=3 tests/fixtures/test_fr.txt`:
exactly 5 `top_words` entries and 3 `top_characters` entries.
`--top-words=0`: the 12 words of test_fr.txt (0 = --all for the
section).

### 8. --max-unique (memory bound)

`fstats --summary-json --lexical-stats --max-unique=5 tests/fixtures/test_fr.txt`:
`unique_words=5` (capped), `words=13` unchanged, `average_word_length`
exact (accumulated in streaming).

### 9. CSV v2 (documented breaking change)

Exact header and summary lines with the `file` column:

```
file,type,rank,value,code_point,count,length
tests/fixtures/test_fr.txt,summary,,lines,,3,
tests/fixtures/test_fr.txt,summary,,words,,13,
tests/fixtures/test_fr.txt,summary,,characters,,72,
tests/fixtures/test_fr.txt,summary,,sentences,,3,
tests/fixtures/test_fr.txt,summary,,avg_words_per_sentence,,4,
tests/fixtures/test_fr.txt,summary,,line_min,,16,
tests/fixtures/test_fr.txt,summary,,line_max,,30,
tests/fixtures/test_fr.txt,summary,,line_avg,,23,
tests/fixtures/test_fr.txt,summary,,invalid_utf8,,0,
tests/fixtures/test_fr.txt,summary,,bom,,0,
tests/fixtures/test_fr.txt,summary,,crlf,,0,
tests/fixtures/test_fr.txt,summary,,tabs,,0,
tests/fixtures/test_fr.txt,summary,,nonprintable,,0,
```

`--csv=words`: same header, 10 `word` rows (Top 10 by default) with
the `length` column (code points). `--csv=chars`: `code_point` column
filled, `length` = 1.

### 10. Invalid options and --version

`--word-mode=bogus` / `--max-unique=0` / `--csv=foo`: exit=1 + French
stderr message. `fstats --version`: `fstats 2.3.0`.

### 11. Automated suites

`tests\run.bat` (CMD): exit=0, 22/22 PASS. `tests/run.sh` (Git Bash):
exit=0, 22/22 PASS — excerpts:

```
PASS: --version affiche 2.3.0
PASS: --word-mode=ascii corpus_en.txt -> words=11 [golden]
PASS: --casefold=unicode corpus_fr.txt -> unique_words=16, words=20
PASS: --casefold=none corpus_fr.txt -> unique_words=17, casse conservee
PASS: --lexical-stats : champs presents, TTR=types/tokens, entropie bornee
PASS: --top-words=5 --top-chars=3 -> exactement 5 et 3 entrees
PASS: --top-words=0 -> tous les mots, 12 pour test_fr.txt
PASS: --max-unique=5 -> unique_words plafonne a 5, words=13 inchange
PASS: CSV v2 : en-tete exact, ligne summary avec colonne file, csv=words 10 lignes
PASS: --word-mode=unicode corpus_fr.txt -> words=19 [golden]
PASS: --word-mode=bogus -> exit 1 + message stderr

RESULTAT : 22 reussi, 0 echec(s)
```

### Summary

C2-A meets ROADMAP-CIBLE2.md's criteria: no regression in default mode
(test_fr.txt 3/13/72/3, quality counters, NDJSON/array/aggregate,
--summary-json, stdin, globs, exit codes 0/1, pure ASCII in pipes), new
options functional and golden-tested, CSV v2 (documented breaking
change) in place, version 2.3.0. B and C (n-grams, histograms,
readability) still to come.
---

## C2-B « Structure » increment (v2.4.0) — 2026-08-26

Validation of the implementation of `doc/ROADMAP-CIBLE2.md` (C2-B:
--ngrams, --top-ngrams, --stopwords, --histogram, --char-classes,
aggregation). Binary compiled from `src/fstats.pas` (single file,
standard FPC RTL).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas`: exit=0

```
3577 lines compiled, 0.8 sec, 342128 bytes code, 19668 bytes data
```

### 2. Default-mode regression (test_fr.txt, unchanged)

`fstats --summary-json tests/fixtures/test_fr.txt`: 3/13/72/3, avg 4,
min/max/avg 16/30/23, the same fields as v2.3.0 without the new
options (only the version changes):

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. N-grams (goldens)

`fstats --json --ngrams=2 --word-mode=ascii tests/fixtures/corpus_en.txt`:
exactly **9 bigrams** (counts = 1), including `hello world`; the bigram
crossing the line break `test one` is **absent** (the windows do not
cross lines).

`fstats --json --ngrams=2 tests/fixtures/ngram_lines.txt` (new fixture
`alpha beta` / `gamma delta`): **2 bigrams** (`alpha beta`,
`gamma delta`), `beta gamma` **absent** — a bigram would only appear
if the windows crossed the line break.

`fstats --json --ngrams=3 --top-ngrams=2 tests/fixtures/test_fr.txt`:
exactly **2 entries** (top-K). `--ngrams=0` and `--ngrams=6`: exit=1 +
stderr message (`--ngrams attend un entier de 1 a 5`).

### 4. Stopwords

`fstats --json --ngrams=2 --top-ngrams=0 --stopwords=fr tests/fixtures/corpus_fr.txt`:
`words=20` (word statistics unchanged) and **14 bigrams**: `et`, `le`
and `Il` (casefold ascii -> `il`) are removed from the n-gram stream
only (without stopwords the file gives 16 bigrams). Verifications:
absence of `et croissant,` and of `le garcon`, presence of `? est`
(the form after removing `il`).

`--stopwords=fr` without `--ngrams`: **silently ignored** (exit=0, no
`ngrams` key in the JSON) — decision documented in the README.

### 5. Histograms (roadmap §6.6 classes + stable classes)

`fstats --json --histogram=line_length tests/fixtures/test_fr.txt`:
classes **identical to the roadmap §6.6 example** `0-9, 10-19, 20-29,
30-39, 40+`, counts `0/1/1/1/0`, sum = lines (3).

`--histogram=word_length`: stable classes `1-2, 3-4, 5-6, 7-8, 9-10,
11-12, 13+` (width 2), counts `3/3/4/3/0/0/0`, sum = words (13).

`--histogram=words_per_sentence`: stable classes `0-4, 5-9, 10-14,
15-19, 20+` (width 5, base 0), counts `2/1/0/0/0`, sum = sentences
(3). The roadmap's hyphenated forms (`--histogram=line-length`,
`word-length`, `words-per-sentence`) are accepted.

### 6. Char-classes (golden test_fr.txt)

`fstats --json --char-classes tests/fixtures/test_fr.txt`:

```
"char_classes": {"letters": 57, "digits": 0, "whitespace": 12,
                 "punctuation": 3, "control": 0, "other": 0}
```

Conservation: the sum of the six classes = 72 = `characters` (test
assertion). Exact ranges documented in the README (« Semantique des
classes de caracteres »).

### 7. Aggregation (--json-mode=aggregate)

`fstats tests\docs\**\*.md --json-mode=aggregate --char-classes --histogram=line_length`:
`char_classes` and `histogram` summed class by class in `totals`:

```
totals.char_classes: {"letters": 93, "digits": 0, "whitespace": 24,
                      "punctuation": 6, "control": 0, "other": 0}
totals.histogram: line_length ["0-9:3", "10-19:4", "20-29:2", "30-39:0", "40+:0"]
```

N-grams are **not** aggregated (documented limitation): no `ngrams`
key in `totals`, they remain per file in `files`.

### 8. Invalid options and --version

`--ngrams=0` / `--ngrams=6`: exit=1 + stderr message.
`--histogram=bogus` / `--stopwords=bogus`: exit=1 + stderr message.
`fstats --version`: `fstats 2.4.0`.

### 9. Automated suites

`tests\run.bat` (CMD, root exe via `-FE.`): exit=0, **33/33 PASS**.
`tests/run.sh` (Git Bash, exe in `src/`): exit=0, **33/33 PASS** —
excerpts:

```
PASS: --ngrams=2 --word-mode=ascii corpus_en.txt -> 9 bigrammes, pas de [test one]
PASS: ngram_lines.txt -> 2 bigrammes, pas de [beta gamma]
PASS: --ngrams=3 --top-ngrams=2 -> exactement 2 entrees
PASS: --ngrams=0 / --ngrams=6 -> exit 1 + message stderr
PASS: --stopwords=fr --ngrams=2 corpus_fr.txt -> 14 bigrammes, mots vides retires
PASS: --histogram=line_length -> classes 0-9..40+, somme = lignes
PASS: --histogram=word_length -> somme des classes = mots
PASS: --histogram=words_per_sentence -> somme des classes = phrases
PASS: --char-classes test_fr.txt -> 57/0/12/3/0/0, somme = 72 caracteres
PASS: aggregate --char-classes --histogram -> totaux sommes classe par classe
PASS: sortie pipee ngrams+histogram+char-classes : aucune sequence ANSI

RESULTAT : 33 reussi, 0 echec(s)
```

### Summary

C2-B meets ROADMAP-CIBLE2.md's criteria: no regression in default mode
(the 22 v2.3.0 cases pass unchanged, version 2.4.0), n-grams (goldens,
no crossing of lines, bounded top-K, fr/en stopwords), histograms
(roadmap §6.6 classes + documented stable classes, sum =
lines/words/sentences), char-classes (conservation = characters,
golden), class-by-class aggregation, exit codes 0/1, pure ASCII in
pipes. C2-C (readability, optional) delivered in v2.5.0 — see section
10 below.

---

## 10. C2-C increment — readability (v2.5.0)

Date: 2026-08-26. Addition of `--readability` (4 metrics + a 0-100
score without syllables, formula frozen in SEMANTIQUE.md), bump
`FSTATS_VERSION` 2.4.0 → 2.5.0, new fixture `tests/fixtures/empty.txt`
(0 bytes).

### 10.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas`: exit=0 (`3736 lines
compiled`).

### 10.2 Reference values (test_fr.txt, raw mode by default)

Expected (independent node recomputation): ASL = 13/3 = 4.333333;
ALW = 60/13 = 4.615385; long = 3 tokens >= 7 (`exemple`, `simple.`,
`Deuxieme`) = 23.076923%; score =
100*(1-(0.5*min(4.333333/30,1)+0.5*min((4.615385-3)/5,1))) = 76.623932.

`fstats --readability --summary-json tests\fixtures\test_fr.txt`:
exit=0, `avg_sentence_words: 4.333333`, `avg_word_chars: 4.615385`,
`pct_long_words: 23.076923`, `readability_score: 76.623932` — verified
by node (epsilon 0.001) on all 4 values.

Console: `Avg sentence words:4.3333 / Avg word chars: 4.6154 /
Pct long words:23.0769% / Score (0-100): 76.6239`.

`--word-mode=ascii`: `Avg word chars: 4.3077`, `Pct long words:
7.6923%`, score 79.7009 (`Deuxieme` → `deuxi` + `me`).

### 10.3 Edge cases and combinations

- Empty file (`empty.txt`): all metrics at 0, score 0, no NaN
  (division by zero protected).
- `--readability --json`: a `readability` block with the 4 keys.
- `--readability --lexical-stats`: both `lexical` AND `readability`
  blocks present (flat keys in summary-json).
- `--readability --csv`: 4
  `summary,,avg_sentence_words/avg_word_chars/
  pct_long_words/readability_score,,<v>,` rows.
- `--json-mode=aggregate`: readability per file, NOT in `totals`
  (like the n-grams).
- Piped `--readability` output: no ANSI sequences.

### 10.4 Automated suites

`tests\run.bat`: exit=0, **39/39 PASS**. `tests/run.sh`: exit=0,
**39/39
PASS**. The 33 previous cases pass unchanged (no regression of the
default mode: test_fr.txt 3/13/72/3, avg 4, min/max/avg 16/30/23).

### Summary

C2-C meets ROADMAP-CIBLE2.md's criteria: metrics on the current mode,
exact documented and frozen formula, no exact Flesch-Kincaid
(mentioned in the README), score bounded [0,100], no NaN on an empty
file, additive in JSON/CSV, pure ASCII, 39/39 on both suites. Target 2
**complete**.

---

## 11. Target 1 B+C — checks engine and baseline (v2.6.0)

Date: 2026-08-26. Addition of `--check`, `--fail-if`, `--warn-if`,
`--compare`, `--fail-on-delta` (check mode, exit 0/1/2/3), bump
`FSTATS_VERSION` 2.5.0 → 2.6.0. The `invalid_utf8` alias accepted in
addition to `non_utf8` (the summary's JSON name). Encoding fix for
doc/ROADMAPFULL.md (mojibake -> UTF-8).

### 11.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas`: exit=0 (4906 lines compiled,
362592 bytes of code). Warnings: only generics.dictionaries (RTL,
pre-existing).

### 11.2 Exit codes (verified by node spawnSync, real exits)

| Command | Exit | Status |
|---|---|---|
| `--check --fail-if lines>2 test_fr.txt` (3 lines) | 2 | FAIL (actual 3) |
| `--check --fail-if lines>5 test_fr.txt` | 0 | OK (actual 3) |
| `--check --warn-if lines>2 test_fr.txt` | 3 | WARN (actual 3) |
| `--check --fail-if lines>1 absent.txt` | 1 | fatal error takes precedence |
| `--fail-if lines>5 test_fr.txt` (without --check) | 0 | implicit check mode |
| `--check --fail-if lines>2 --json test_fr.txt` | 2 | `{"id":"lines","metric":"lines","actual":3,"op":">","threshold":2,"status":"fail"}` |

### 11.3 Baseline / drift

`--summary-json` captured into bl_test.json, then `--compare
bl_test.json --fail-on-delta lines>10 test_fr.txt`: exit 0
(`delta lines > 10% : OK (delta 0%)`). Modified baseline
(`"lines": 3` -> `"lines": 1`): exit 2 (`FAIL (delta 200%)`).
`--fail-on-delta` without `--compare`: exit 1 + stderr
(`--fail-on-delta exige --compare BASELINE`).

### 11.4 CI dogfood (step added to ci.yml, validated locally)

`fstats --check --fail-if non_utf8>0 --fail-if bom>0 --fail-if
nonprintable>0 README.md doc\*.md src\fstats.pas`: exit 0, 10 files
analyzed (the workflow's exact command, `doc\*.md` glob under cmd).

### 11.5 Automated suites

`tests\run.bat`: exit=0, **56/56 PASS**. `tests/run.sh`: exit=0,
**56/56
PASS**. The 39 previous cases pass unchanged (no regression of the
default mode: test_fr.txt 3/13/72/3).

### Summary

Target 1 **complete** (A v2.2.0, B+C v2.6.0): checks engine (frozen
grammar, 10 metrics + alias, ok/warn/fail statuses, exit 0/1/2/3,
analysis mode unbroken), NDJSON baseline + drift in % (base=0
documented), console Checks section + checks JSON block (stable ids),
CI dogfood, 56/56 on both suites.

---

## 12. Fix v2.6.1 — decimals like 3.14 no longer close a sentence

Date: 2026-08-26. Known limitation addressed: a decimal point (`3.14`)
counted as a sentence end. Fixes: `FSTATS_VERSION` 2.6.0 → 2.6.1,
deferred closure logic inside `AnalyzeData` (`DotPending`/`LastCP`,
the nested procedure `CloseSentence`), new fixtures
`tests/fixtures/decimal.txt` and `tests/fixtures/decimal_end.txt`,
3 new cases (57-59) in both suites.

### 12.1 Frozen rule (verified by node)

- `Le prix est 3.14 euros. Bravo !` → **2 sentences** (before: 3),
  7 words.
- `Le prix est 3.14` (end of stream) → **1 sentence** (before: 2).
- `Version 3. Fin.` → **2 sentences** (the period after `3` followed
  by a space still closes).
- `3 . 14. Fin.` → **3 sentences** (a period surrounded by spaces =
  sentence end).
- `3.14. 5. Fin.` → **3 sentences** (period between digits ignored,
  final period after `4` closes).
- Regression check: test_fr.txt stays at 3 sentences (3/13/72/3).
- words_per_sentence histogram: sum of the classes = sentences (2 on
  decimal.txt).

### 12.2 Automated suites

`tests\run.bat`: exit=0, **59/59 PASS**. `tests/run.sh`: exit=0,
**59/59
PASS**. The 56 previous cases pass unchanged.

### Summary

Verified fix: no NaN, no regression, semantics frozen in
SEMANTIQUE.md (period between two digits ≠ sentence end; period
after a digit followed by a space = sentence end; period + space =
sentence end).

## 13. v2.7.0 - --sentence-mode=basic|smart

Verified on: 2026-08-26 22:55 - executable: `fstats.exe`
(`fstats 2.7.0`)

### 13.1 The smart mode's frozen rule (verified by node, stdin)

- `M. Dupont est la. Bravo.`: smart → **2 sentences** (the `M.` period
  is swallowed), basic → **3 sentences** (historical behavior
  unchanged).
- `Visitez https://ex.com maintenant.`: smart → **1 sentence** (the
  `.com` period is swallowed: `://` within the window of the last 8
  characters), basic → **2 sentences**.
- `e.g. ceci.`: smart → **1 sentence** (both `e.g.` periods swallowed:
  the first by the prefix rule `e.` → `e.g`, the second by the exact
  match `e.g`).
- `Coût 3.14 euros.`: smart → **1 sentence** (the v2.6.1 decimal rule
  kept in smart).
- `www.ex.com ici.`: smart → **2 sentences** (documented limitation:
  only the first `www.` period is protected, the `.com` one closes).
- `--sentence-mode=bogus`: exit=1, pure-ASCII stderr
  `Erreur: --sentence-mode attend "basic" ou "smart" (recu "bogus")`.
- `--sentence-mode=SMART` and `--sentence-mode:smart`: accepted
  (case-insensitive, `=` and `:`).
- Regression check: test_fr.txt with no option stays at 3 sentences
  (3/13/72/3); explicit `--sentence-mode=basic` gives the same result.

### 13.2 Automated suites

`tests\run.bat`: exit=0, **67/67 PASS**. `tests/run.sh`: exit=0,
**67/67
PASS**. The 59 previous cases pass unchanged (only case 12
`--version` moved from 2.6.1 to 2.7.0).

### Summary

ROADMAPFULL §6.3 (sentence detection) is handled: decimals
(v2.6.1, default mode), abbreviations and URLs (v2.7.0, smart mode,
scope documented in SEMANTIQUE.md). The roadmap's three-value
`--sentence-mode` plan was simplified to two (`none` dropped: not
counting sentences adds nothing).

---

## 14. Target 3-A — Log Sentinel: patterns, top-lines, redaction (v2.8.0)

Date: 2026-11-23. Addition of `--pattern=TEXT` (literal + `|` +
`*`/`?`, case-insensitive, non-overlapping occurrences),
`--top-lines=N` (identical lines grouped, top-K bounded like the
n-grams) and `--redact=email,ipv4,url` (replaced with `***` in the
outputs only, counters on raw content). Bump `FSTATS_VERSION`
2.7.0 → 2.8.0. New fixtures `tests/fixtures/app.log` (9 log lines
with ERROR/WARN/INFO levels, duplicated lines, email/IP/URL) and
`tests/fixtures/redact.txt`.

### 14.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas`: exit=0 (`5900 lines
compiled`).

### 14.2 Patterns (golden app.log)

- `--pattern=ERROR` → `{"pattern":"ERROR","lines":4,"matches":4}` (4 ERROR lines).
- `--pattern='ERROR|WARN'` → 5 lines / 5 matches (4 ERROR + 1 WARN, alternation).
- `--pattern='*timeout*'` → 3/3 (wildcards on both sides, substring match).
- `--pattern='*'` → 9/9 (all lines).
- stdin: `echo -e "ERROR x\nINFO ok\nERROR y" | fstats - --summary-json --pattern=ERROR`
  → `lines=2, matches=2`.

### 14.3 Top-lines (golden app.log)

- `--top-lines=2` → 2 entries, top 1 = `2026-01-15 10:00:05 ERROR connection timeout to db.internal` (count=2),
  top 2 = `2026-01-15 10:00:12 INFO health check OK` (count=2).
- stdin `aaa\nbbb\naaa` + `--top-lines=5` → top 1 = `aaa` count=2.
- Sort: decreasing frequency, then alphabetical (deterministic).

### 14.4 Redaction (golden redact.txt)

- `--redact=email,ipv4,url` → `longest_lines[0].content` =
  `Contact *** or visit *** from ***` (email, URL, IPv4 masked).
- `--redact=email` alone → email masked, `10.0.0.1` kept.
- `--redact=ipv4` alone → IPv4 masked, email kept.
- `--redact=url` alone → URL masked, email kept.
- Counters on raw content: `characters=195` unchanged (redaction only
  affects the outputs).

### 14.5 Invalid options

- `--redact=bogus` → exit 1, stderr `Erreur: --redact attend "email", "ipv4" ou "url"`.
- `--top-lines=abc` → exit 1, stderr `--top-lines attend un entier >= 0`.
- `--pattern=` (empty) → exit 1, stderr `--pattern : valeur vide`.

### 14.6 Non-regression and ANSI

- `test_fr.txt`: 3/13/72/3, avg 4, min/max/avg 16/30/23 (unchanged).
- Piped output with `--pattern --top-lines --redact`: no ANSI sequences (ESC).
- Complete C3-A JSON parseable (patterns + top_lines + redact in longest_lines).

### 14.7 Automated suites

`tests\run.bat` / `tests\run.sh`: 82 cases (67 existing + 15 new
C3-A), expected `--version` `2.8.0`. (No node validation run locally
here — node absent from the environment; cases verified manually one
by one.)

### Summary

C3-A meets ROADMAP-CIBLE3.md's criteria: documented internal matcher
(literal + `|` + `*`/`?`, NOT a full regex), top-lines bounded (like
the n-grams), post-count redaction (counters on raw content),
console/JSON/CSV/summary-json exports, exit codes 0/1 kept, pure
ASCII in pipes. C3-B (levels), C3-C (alarm) and C3-D (watch) still to
come.

---

## 15. Target 3-B — log levels + filter (v2.9.0)

Date: 2026-11-23. Addition of `--log-level` (detection
ERROR>WARN>INFO>DEBUG>TRACE, case-insensitive whole word, sum =
lines) and `--filter=levels` (filters the console display of lines,
counters over the whole file). Bump `FSTATS_VERSION` 2.8.0 → 2.9.0.
New fixture `tests/fixtures/levels.log` (8 lines with all the levels +
ERRORS/whole-word traps).

### 15.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas`: exit=0 (`~6060 lines
compiled`).

### 15.2 Levels (golden levels.log)

`--log-level levels.log` → `error=2, warn=1, info=1, debug=1, trace=1, none=2`.
- `ERRORS not a level word` → `none` (whole word: ERRORS ≠ ERROR).
- `error lowercase counts too` → `error` (case-insensitive).
- Sum = 8 = lines.

`--log-level app.log` → `error=4, warn=1, info=4, debug=0, trace=0, none=0`,
sum = 9 = lines.

### 15.3 Priority and whole word (stdin)

- `WARN then ERROR here` → `error=1, warn=0` (priority ERROR > WARN).
- `ERRORS everywhere` → `none=1` (no whole-word match).

### 15.4 Filter (console)

- `--log-level --filter=error --top-lines=5 app.log` → Top Lines contains only
  the ERROR lines (ranks renumbered 1, 2).
- `--filter=error,warn levels.log` → ERROR + WARN displayed, no INFO.
- `--filter=bogus` → exit 1, stderr `--filter attend "error", ...`.
- Global counters unchanged (lines=9 on app.log despite the filter).

### 15.5 Non-regression and ANSI

- `test_fr.txt`: 3/13/72/3 (unchanged).
- Piped output with `--log-level --filter`: no ANSI sequences.
- `log_levels` present in pretty/NDJSON/summary-json JSON; `loglevel`
  rows in CSV.

### 15.6 Automated suites

`tests\run.bat` / `tests\run.sh`: 90 cases (82 + 8 new C3-B), expected
`--version` `2.9.0`.

### Summary

C3-B delivered: frozen level detection (whole word, priority,
sum=lines), console display filter, JSON/CSV/summary exports,
non-regression OK. C3-C (alarm/SCADA) and C3-D (watch) still to come.

---

## 16. Target 3-C — alarm: regex-tag + mode=alarm (v2.10.0)

Date: 2026-11-23. Addition of the mini-engine `--regex-tag=PATTERN`
(literal + `[...]` classes + `? * +` quantifiers, non-overlapping
extraction) and the shortcut `--mode=alarm` (= `--log-level` +
`--top-lines` + `--regex-tag` with default `[A-Z]+[0-9]+`). Bump
`FSTATS_VERSION` 2.9.0 → 2.10.0. New fixture `tests/fixtures/alarms.log`
(8 SCADA lines with PLC1/MOTOR23/PLC2/SENSOR7).

### 16.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas`: exit=0.

### 16.2 Tags (golden alarms.log)

- `--regex-tag='PLC[0-9]+'` → `PLC1` count=5, `PLC2` count=1.
- `--regex-tag='[A-Z]+[0-9]+' --top-tags=10` → PLC1=5, MOTOR23=2, PLC2=1, SENSOR7=1.
- `--top-tags=2` → exactly 2 entries (PLC1, MOTOR23).
- Quantifier `+`: stdin `PLC sans chiffre\nPLC42 ok` → only `PLC42` extracted.

### 16.3 Alarm mode

`--mode=alarm alarms.log` → `log_levels` (error=3, warn=2, info=3, debug=0,
trace=0, none=0 — sum = 8 = lines: each line carries a level) +
`top_lines` + `tags` (PLC1=5 at the top). Default pattern
`[A-Z]+[0-9]+`.

### 16.4 Invalid options

`--top-tags=abc`, `--mode=bogus`, `--regex-tag=` (empty) → exit 1 +
stderr.

### 16.5 Non-regression

- `test_fr.txt`: 3/13/72/3 (unchanged).
- Piped output with `--mode=alarm`: no ANSI sequences.
- 97 cases in run.sh/run.bat, `--version` = `2.10.0`.

### Summary

C3-C delivered. C3-D (polling watch/follow) still to come.

---

## 17. Target 3-D — watch/follow by polling (v2.11.0) — **Target 3 COMPLETE**

Date: 2026-11-23. Addition of `--watch`/`--follow` + `--interval=N`
(default 2 s, minimum 1): a polling loop that re-analyzes the file at
each tick and prints `[timestamp] lines=N (+delta) words=N chars=N
sentences=N | error=… …`. Cross-platform Ctrl+C handler
(SetConsoleCtrlHandler Windows / FpSignal SIGINT+TERM Linux) → clean
shutdown exit 0. Bump `FSTATS_VERSION` 2.10.0 → 2.11.0.

### 17.1 Watch (verified with a 4 s timeout, interval 1)

`--watch --interval=1 --log-level app.log` → 5 status lines:
`[ts] lines=9 (+0) words=65 chars=540 sentences=7 | error=4 warn=1 info=4 none=0`

### 17.2 Positive delta (a growing file)

Watch in the background + `echo "…ERROR new alarm on PLC9" >> watch_test.log`
→ next tick: `lines=10 (+1) … error=5` (delta and level updated).

### 17.3 Restrictions

- `--watch -` (stdin) → exit 1, stderr.
- `--watch a.log b.log` (2 files) → exit 1, stderr.
- `--interval=0` → exit 1, stderr.

### 17.4 Non-regression

- `test_fr.txt`: 3/13/72/3 (unchanged). 100 cases in run.sh/run.bat,
  `--version` = `2.11.0`.

### Summary

**Target 3 complete**: C3-A (patterns/top-lines/redaction) + C3-B
(log-level/filter) + C3-C (alarm/regex-tag) + C3-D (watch). fstats
v2.11.0 = text profiler + quality gate + log sentinel, still a
single file (6,795 lines), zero dependencies, pure ASCII, stable
exit codes.
