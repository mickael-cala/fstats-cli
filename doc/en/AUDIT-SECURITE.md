> 🇬🇧 **English translation** — canonical version (authoritative): doc/AUDIT-SECURITE.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# Security and quality register — fstats

> Living document, kept up to date as audits happen. Convention: every finding
> has a **status** (CORRIGÉ / OUVERT / ACCEPTÉ_DOCUMENTÉ / REFOULÉ_À — fixed /
> open / accepted-and-documented / pushed-back-to), a number, and an entry in
> the CHANGELOG whenever its status changes.
> Paranoid/pedagogical motto: *what we don't document, we hide. What we
> document, we manage.*

---

## 1. Audit method (2026-11-23)

Three independent auditors in parallel — a Pascal architect (dev), a
pentester (cyber), a CLI designer (UX), exhaustive review of the ~7,600
lines + real executions. Cross-checked synthesis, then **manual
re-verification of every major finding** before any fix (6/6 confirmed).
P0 fixed in v2.13.1; P1 in progress; P2 below.

## 2. Threat model (read before using fstats on sensitive data)

**Assets**

1. The content of the analyzed files (logs: emails, IPs, identifiers).
2. The files on disk (`--out` writes, `--recursive` reads).
3. The CI verdict (exit codes 0/1/2/3, `--compare` baseline).
4. The workstation running the wizard (`--interactive` / `fcmd`).

**Who controls what** (the question to ask before every use)

| Input | Controlled by | Trust level |
|---|---|---|
| `argv` (options, patterns, thresholds) | the operator | high |
| Analyzed files (CI logs, artifacts) | **the outside** | **none** |
| NDJSON baseline (`--compare`) | anyone who writes into the repository | medium |
| wizard stdin / pipe | local pipeline | high |

**The golden rule of this register**: as soon as an analyzed file is
supplied by a third party (build artifact, a client's log), fstats is
dealing with **hostile input**. The homegrown parsers (glob, wildcards,
mini-regex, NDJSON, level matching) are written defensively, but they do
not benefit from the decades of hardening behind proven libraries.

## 3. P0 status — fixed in v2.13.1 ✅

| ID | Finding | Fix |
|---|---|---|
| P0-1 | Off-by-one `--pattern` (adjacent occurrences lost: `errorerrorerror` → 2) | convention aligned + golden tests 108 |
| P0-2 | Wizard generating commands fstats rejects (`--ngrams=2,3`, `--csv-kind`, `sentence_words`) | table aligned with the parser + a test that **executes** |
| P0-3 | Test suite red since v2.12.0 (version frozen at `2.11.0`) | version **derived** from `fstats_types.pas` |
| P0-4 | `fcmd --profil=log` promised but not supported | accepted names |
| P0-5 | `--help` "pure ASCII" containing an accented character | normalized |

## 4. P1 status — fixed in v2.14.0 ✅

| ID | Finding (verified) | Severity | Fix |
|---|---|---|---|
| P1-1 | **Unix shell injection**: the wizard ran the command via `FpSystem` (`/bin/sh -c`); values without spaces were not quoted → `;`, `` ` ``, `$(…)` executable | RCE | `SysUtils.ExecuteProcess` (argv, **never a shell**) via `RunArgs`/`RunTokens`; `CmdQuote` extended to metacharacters for display; `fcmd` refuses the silent PATH fallback. Still open (P2): `%VAR%` expanded by cmd.exe on paste |
| P1-2 | **`--out` destroys the input file** (truncated before analysis) | Data loss | Guard: exit 1 + stderr refusal if `--out` ∈ analyzed files (absolute paths, case-insensitive under Windows) — test 110 (input proven intact by diff) |
| P1-3 | **`--redact` leak**: emails/IPs in clear text in Top Words, n-grams, tags | Disclosure | `RedactString` at the 11 emission points + anti-leak test 109 (grep = 0 across console/JSON/CSV/summary) |

## 5. P2 status — DONE: waves 1-5 (v2.14.1 → v2.16.2) ✅

**Fixed in v2.14.1** (tests 111-113 + wizard replayed): the 64 KB boundary
(invalid_utf8 false positive at the alignment — a CI metric bug), `WARNING`
classified as none (log4j/Python), CSV formulas (`= + - @`), the `--check`
gate an invisible no-op, wizard UX (numbers displayed, invalid input no
longer exits), dead code (`OptModeAlarm`, deltas watch, `BuildTopLinesJSON`).

**Fixed in v2.15.0** (tests 114-116 + golden parity 23/23 vs v2.14.1):
exponential backtracking in the matchers (`--pattern` greedy linear,
`--regex-tag` NFA — a 1.6 KB file froze at 100% CPU indefinitely),
**infinite loop on zero-length match** (`*`, `**`, `a||b` — a genuine
hang, discovered while testing the harness), unbounded lines/words
(geometric-growth buffers + storage bounds, exact metrics). Bonus: the
Windows run.bat harness was unusable (LF instead of CRLF: crash at test
65+; `set X=1 ` with a trailing space absorbed; `^>` re-parsed in a
pipe) — repaired, 63 PASS.

**Fixed in v2.16.0** (tests 117-119, SHA-256 validated on FIPS vectors +
sha256sum/Get-FileHash parity): **a forgeable baseline** (`sha256` key in
the summary-json, verified by `--compare`: changed content = FAIL exit 2
even when the metrics are stable), **files outside the baseline silently
ignored** (an stderr warning + a counter in the verdict), **unreadable CI
verdict** (last console line = `Verdict : OK/ATTENTION/ECHEC — exit N`,
never in the data formats). Bonus: `--fail-on-delta=M>X` inline had
**never** worked since v2.6.0 (off-by-one: treated as a file name), and
the exit 2 of an injected check was ignored. **A negative delta
requalified as ACCEPTÉ (§6)**: the gate protects against explosion;
shrinkage is not a CI anomaly.

**Fixed in v2.16.1** (tests 120-121): **misleading options** — an unknown
option (`--patern=x`, a typo) or one missing its value (a bare `--redact`)
was handled as a FILE NAME: « Fichier inaccessible ou introuvable »
("file unavailable or not found") pointed at the disk instead of the
command line; honest message + exit 1 (a file can still be passed as
`./--x`). **The `--top-lines` help lied** (« 0 = tous » since v2.8.0,
while the code disables the section): help + SEMANTIQUE corrected to the
code's truth. **`%VAR%` at cmd paste time (wizard) requalified as
ACCEPTÉ**: no reliable escaping exists for `%` in interactive cmd; the
generated command never introduces a `%`.

**Fixed in v2.16.2** (tests 122-123): **ties without a tie-break** —
equal frequencies → ascending lexicographic order (Top Words, Top Chars
by code point): byte-for-byte determinism (a documented ordering break,
counters unchanged); **`--recursive`/`--include`/`--exclude`/
`--max-depth` — zero tests → semantics measured and frozen** (relative
globs, `*` does not cross `/`, `**` does, exclude on the full relative
path, max-depth = levels below the root; test 122 sh+bat).

**Requalified as ACCEPTÉ_DOCUMENTÉ (v2.16.2, §6): low-level `Halt()`**
(explicit release where it matters, the OS for the rest — see §6),
**homoglyphs/RTL** (a Unicode confusables table is out of scope).

**STATUS: the P2 backlog is EMPTY.** Waves 1 through 5 processed every
item in the register: fixed + tested, or a requalification we stand
behind, with justification. The only entries left are the §6 decisions,
which read as scope limits, not as debt. run.sh/run.bat duplication: an
architecture finding (twin harnesses 1150/1186 lines, realigned
v2.15.0-v2.16.2, every new test ALREADY exists in both — the maintenance
cost is the price of two native environments).

## 6. ACCEPTÉ_DOCUMENTÉ (deliberate decisions) 📗

- The Win32 i386 binary (no 64-bit build) — a text CLI, sufficient.
- Excel/Calc: the user takes responsibility for opening the CSV (see the
  P2 formulas finding).
- `--watch` re-analyzes the whole file on every tick (documented v1).
- Approximate Top-K n-grams on very large corpora (a bounded sketch).
- Unicode casefold = basic FR/DE table (documented).
- **`Halt()` in the low layers** (requalified v2.16.2): a single-task CLI
  process — at the exit point, the OS reclaims the memory; the cases that
  hold stream resources (dictionaries) release **explicitly** before
  exiting; the main entry runs through its `try..finally` on the normal
  path. An exception refactor would be cosmetics with no user gain, at
  the price of a real risk of exit code regressions (the backbone of the
  CI gate).
- **Invisible homoglyphs / RTL** (requalified v2.16.2): Cyrillic `ЕRROR`
  or bidi controls require a Unicode confusables table, out of scope for
  a statistics tool; the quality counters remain true to what they
  measure (nonprintable, invalid_utf8). A user in a hostile context
  cross-checks with dedicated tools (e.g. `unicode-security`).
- The `ipv4`/`url` redactions cover simple forms (no IPv6/ports).
- **`--fail-on-delta` only tests growth** (v2.16.0, requalified): a
  negative delta cannot make the gate fail — the gate protects against
  the EXPLOSION of the metrics (a log tripling), not against shrinkage;
  the (negative) delta value is still displayed.

## 7. Pedagogical lessons (re-read before every new feature)

1. **A wizard must drink from the same source of truth as the parser.**
   The P0-2 bug was born of a hand-typed options table.
2. **A test that freezes a string protects the bug, not the user.**
   Always execute what you generate (test 103b).
3. **Never assemble a command line as a string to execute.** Always an
   argv (P1-1); the displayed string is text, not code.
4. **An untested security claim is a documentary vulnerability.** The
   "anti-path traversal" mentions in the fstats.pas:68-149 header were
   removed until they are proven.
5. **Every homegrown parser comes with the known traps of the library it
   imitates** — write the trap's test at the same time as the parser.
6. **A test's version is never frozen** (P0-3): derive it or die.
7. **A protection is a mandatory point of passage, or it is only an
   intention.** P1-3: redaction had existed since v2.8.0, but scattered
   across one-off calls — emails were leaking into Top Words, and the
   doc of the day described that leak as the spec. Fixed by covering the
   *text emissions* one by one (11 points); tested by "the forbidden
   object must not appear in ANY output" (test 109).
8. **A tool that reads in blocks must be tested at its internal
   boundary.** v2.14.1: a multi-byte character straddling two 64 KB
   blocks was counted `invalid_utf8` — the CI gate accused a healthy
   file of being broken based on its size, not its content. Test 111
   slides the same multi-byte character across 6 positions around the
   boundary: a correct counter never depends on where the cut falls.
9. **An export meant for Excel is an attack input.** v2.14.1: a log
   line `=cmd|'/c calc'!` came out in the CSV as a formula ready to
   execute on open. Exporting is emitting potential code into an
   unknown interpreter — neutralize (`'` OWASP prefix) and test
   (test 112).
10. **An infinite loop is a security bug, not a performance bug.**
    v2.15.0: a zero-length match made `StartPos := i + 0 = i` — the
    scanner NEVER left the loop: `--pattern='*'` = a pure hang, every
    machine resource absorbed forever. Any advance in a loop must be
    tested against strict equality with its starting point.
11. **A test harness that has never run to the end tests nothing.**
    v2.15.0: the Windows run.bat had LF line endings (cmd.exe requires
    CRLF) — it was crashing silently at test 65+ from the moment it was
    written; 10 tests sabotaged themselves with `set X=1 ` (the space
    before `&&` is included in the value by cmd) and a `^>` in a pipe
    became a redirection. The "63 PASS / 0 FAIL" signal did not exist
    before — it exists now, and it is verified at every release.
    **Third occurrence in v2.16.2 (node catch-up)**: the 65
    node-dependent tests were silently SKIP/FAIL locally for lack of
    node; once node was installed, two of them turned out to be stale
    since waves 2 and 3 (56: ids without sha256; 71: null match counted
    9/9) without anyone seeing it. A test that does not run is not
    green: it is invisible.
12. **Test every option in the EXACT form the documentation shows.**
    v2.16.0: `--fail-on-delta=M>X` — the form with `=` — had been
    documented since v2.6.0 and had NEVER worked (off-by-one on the
    prefix): the option fell into the "file" branch. The 3-argument
    form, the one that was tested, worked. Five versions of "verified"
    never tested what the user types while reading the help. One test
    per documented option, with its documented syntax.
13. **A build that depends on a machine's hidden settings is not
    reproducible.** (2026-11-24, first CI push). The v2.15.0 matcher
    uses GOTO/LABEL; five versions of "it compiles on my machine"
    rested on the `-Sgic` of the official fpc.cfg — invisible in the
    command line. First machine with a different fpc.cfg (the CI
    regenerates a minimal one): red build. The switches a build depends
    on belong in the command, not in the environment. And to reproduce
    a compilation failure: clear the cache (.ppu/.o) — FPC reuses
    already-compiled units, and an already-compiled goto rejects nothing
    anymore. **Extension (run #28)**: likewise, an exit code capture
    must be **immediate and numeric** (`set ST=%ERRORLEVEL%` right at
    the call, then `if %ST% GEQ 1`) — the inherited form
    `if errorlevel N`, read after an intervening `set`, failed on the
    sole CI runner (tests 120/121) while passing everywhere else.

## 8. Audit journal

| Date | Version | Audit | Outcome |
|---|---|---|---|
| 2026-11-23 | v2.13.0 | dev × cyber × UX (3 agents + manual re-verification) | P0 → v2.13.1; this register; P1 started |
| 2026-11-23 | v2.14.0 | — | P1-1/2/3 fixed + tests 109/110; leftovers recorded under §5/P2 |
| 2026-11-23 | v2.14.1 | — | P2 wave 1 fixed (6 fixes + dead code); tests 111-113; §5 backlog |
| 2026-11-24 | v2.15.0 | — | P2 wave 2 fixed (linear matchers, null-match hang, storage bounds); tests 114-116; Windows harness repaired (63 PASS) |
| 2026-11-24 | v2.16.0 | — | P2 wave 3 fixed (SHA-256 baseline, CI verdict, off-baseline made visible, inline fail-on-delta); tests 117-119 (66 PASS) |
| 2026-11-24 | v2.16.1 | — | P2 wave 4 fixed (honest options, truthful help); tests 120-121 (68 PASS) |
| 2026-11-24 | v2.16.2 | — | P2 wave 5 fixed (tie-break, recursive tests); P2 backlog EMPTY; tests 122-123 (70 PASS) |
| 2026-11-24 | v2.16.2 | — | Node catch-up: 127/127 in sh AND bat (254 verifications); 2 stale twin tests aligned with the frozen semantics (56: ids +sha256 v2.16.0; 71: null match 0/0 v2.15.0); third occurrence of lesson 11 (a harness never run to the end) |
| 2026-11-24 | v2.16.2 | — | First CI push: -Sg failure (Windows, compilation) + test 105 (Linux); -Sg made explicit everywhere (lesson 13); test 105 instrumented (self-printed proof in CI) |
| 2026-11-24 | v2.16.2 | — | Run #28: CI GREEN on test-windows + test-linux (127/127 each); ghost failure 120/121 fixed by immediate, numeric exit code capture (lesson 13 extended) |
