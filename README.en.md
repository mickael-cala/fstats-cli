> 🇬🇧 **English translation** — canonical version (authoritative): README.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# fstats — command-line text file statistics

**Language / Langue : 🇬🇧 [English (this file)](README.en.md) · 🇫🇷 [Français](README.md)**

[![CI](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/Licence-MIT-blue.svg)](LICENSE)

Version 2.16.2 · Free Pascal (objfpc mode) · MIT

`fstats` is a small, **fast, dependency-free** tool that analyzes UTF-8
text files and displays statistics: characters, words, lines, sentences,
most frequent words, n-grams, histograms… It can also **act as a CI
guard**: threshold checks (`--fail-if`), comparison against a baseline
(`--compare`), and dedicated exit codes (0/1/2/3).

It runs on **Windows and Linux**, on its own, with no heavyweight
environment: all you need to build it is the Free Pascal compiler.

> 👋 **New here?** Start with the [pedagogical guide](doc/en/GUIDE-PEDAGOGIQUE.md):
> it explains step by step, jargon-free, what the tool does and how to use it.

## Quick start

Build from the repository root (Windows):

```
fpc -Sg -O2 -Mobjfpc -FE. src\fstats.pas
fpc -Sg -O2 -Mobjfpc -FE. src\fcmd.pas
```

Under **Linux/macOS**, the same commands with the `/` separator:
`fpc -Sg -O2 -Mobjfpc -FE. src/fstats.pas` (the rest is unchanged).

`-Sg` is **required** (the wildcard matcher in `fstats_lex.pas` uses
`GOTO`/`LABEL`); the official `fpc.cfg` files ship it by default
(`-Sgic`), but a minimal `fpc.cfg` does not — hence the explicit switch,
seen in CI at the v2.16.2 push.

Two executables are created at the root: `fstats.exe` and the companion
`fcmd.exe` (the second line compiles `src\fcmd.pas`).

Ready-to-use build scripts (multi-OS and multi-architecture, they compile
both binaries into `bin/<arch>/` without touching the root binaries used
by the tests):

| OS | Build | Cleanup |
|---|---|---|
| Windows (32 + 64-bit) | `build.bat` → `bin\win32\`, `bin\win64\` | `clear.bat` |
| Linux, bash (amd64 + aarch64) | `build.sh` → `bin/amd64/`, `bin/aarch64/` | `clear.sh` |
| Recent macOS, zsh (Apple Silicon + Intel) | `buildmac.sh` → `bin/aarch64/`, `bin/x86_64/` | `clearmac.sh` |
| Old Intel Mac, bash | `buildmac-intel.sh` → `bin/x86_64/` | `clearmac-intel.sh` |

A missing target (e.g. 64-bit on a 32-bit-only FPC install) is reported
cleanly then skipped: the script continues and recapitulates (exit 1 if
at least one failure; `clear.*` removes only `bin/`, `*.ppu`, `*.o` and
the compiled binaries).

First analyses:

```
fstats mon-fichier.txt          # full statistics on screen
fstats "**/*.md"                # all .md files in the folder (internal glob)
echo "un deux trois." | fstats - --summary-json   # from standard input
fstats --json mon-fichier.txt   # JSON export
```

## Companion: generate the command line (v2.13.0)

Don't feel like memorizing the 50 options? Two equivalent ways:

```
fstats --interactive     # wizard built into fstats
fcmd                     # separate companion binary
```

The wizard offers **3 profiles** (1=corpus, 2=log, 3=gate), then **all the
options by category** (files, analysis, display, sentinel, checks, export,
misc), shows the generated command and asks whether you want to run it —
**the exit code is propagated** (useful in CI). It can be driven over a pipe:

```
printf '2\n0\n' | fcmd --dry-run
# prints: fstats --mode=alarm --top-lines=10 --redact=email,ipv4,url
fcmd --exec              # runs without asking
fcmd --profil=log        # pre-selects the profile
```

## What fstats can do

| Domain | Features |
|---|---|
| **Counting** | characters, words, lines, sentences, line length (min/max/average) |
| **Diagnostics** | invalid UTF-8, BOM, CRLF line endings, tabs, control characters |
| **Quality Gate** | threshold checks (`--fail-if`/`--warn-if`), baseline (`--compare`/`--fail-on-delta`), exit codes 0/1/2/3 for CI |
| **Vocabulary** | unique words, hapax, type-token ratio, average word length, entropy |
| **Repetitions** | n-grams (1 to 5 words), with stop-word filtering (French/English) |
| **Distribution** | histograms (line length, word length, words per sentence), character classes |
| **Readability** | words per sentence, average word length, % of long words (≥ 7), 0-100 score (without syllables) |
| **Log Sentinel** | patterns (`--pattern`), top lines (`--top-lines`), redaction (`--redact`), levels (`--log-level`), filter (`--filter`), tags (`--regex-tag`), alarm mode (`--mode=alarm`), watch (`--watch`) |
| **Export** | pure-ASCII aligned console, JSON (object / NDJSON / array / aggregate), CSV |

## Usage

```
fstats [options] <fichier|glob|-> [fichier2 ...]
```

### Inputs

| Option | Effect |
|---|---|
| `-`, `--stdin` | Analyzes standard input as UTF-8 (cannot be mixed with files) |
| `*.txt`, `**/*.md` | Glob patterns resolved **internally** (CMD/PowerShell do not expand globs) |
| `--recursive=DIR` | Walks the tree of `DIR` (repeatable) |
| `--include=GLOB`, `--exclude=GLOB` | Filters for `--recursive` (repeatable) |
| `--max-depth=N` | Maximum traversal depth (0 = root only) |

### Text analysis

| Option | Effect |
|---|---|
| `--word-mode=raw\|ascii\|unicode` | Word definition (attached punctuation included or not) |
| `--casefold=ascii\|unicode\|none` | Normalization of case and accents |
| `--sentence-mode=basic\|smart` | Sentence end: `basic` (default) = `.` `!` `?` `…` + decimals; `smart` = + abbreviations (`M.`, `etc.`…) and URLs (`https://…`) |
| `--lexical-stats` | Unique words, hapax, TTR, average length, entropy |
| `--readability` | Words per sentence, average word length, % of long words (≥ 7 characters), 0-100 score — approximation **without syllables**, not an exact Flesch-Kincaid |
| `--max-unique=N` | Memory bound for unique words (default 100,000) |
| `--ngrams=N` | N-grams over the words of the current mode (N = 1..5, per-line windows) |
| `--top-ngrams=K` | Top-K limit for n-grams (default 10; `0` = all) |
| `--stopwords=fr\|en\|none` | Strips stop words from the n-gram stream only |
| `--histogram=M` | `line_length` \| `word_length` \| `words_per_sentence` (ASCII bars) |
| `--char-classes` | Classifies each character: letters, digits, whitespace, punctuation, control, other |

### Log Sentinel (Target 3-A/B/C/D)

| Option | Effect |
|---|---|
| `--pattern=TEXT` | Counts occurrences of the pattern in each line (repeatable). Literal + `\|` (alternation) + `*`/`?` (wildcards), case-insensitive. Under CMD, escape `\|`: `--pattern="ERROR\|WARN"` |
| `--top-lines=N` | Top N of identical lines (default 10; absent = disabled; `0` = all). Bounded memory like the n-grams |
| `--redact=LIST` | `email,ipv4,url` (comma-separated): replaced with `***` in the **outputs only** — any text emission: words, n-grams, tags, lines (v2.14.0); the counters are still computed on the raw text |
| `--log-level` | Counts lines by level: priority `ERROR` > `WARN` > `INFO` > `DEBUG` > `TRACE` (whole word, case-insensitive, anywhere in the line) + `none`. Sum = `lines` |
| `--filter=LIST` | `error,warn,info,debug,trace,none` (commas): filters the line **display** (`Top Lines`, `Longest Lines`); the global counters still cover the whole file |
| `--regex-tag=PAT` | Extracts and counts tags (mini-engine: literal + classes `[0-9]`/`[a-z]`… + quantifiers `?` `*` `+`). E.g. `PLC[0-9]+` → `PLC1`, `PLC23` |
| `--top-tags=N` | Top limit for tags (default 10; `0` = all). Bounded memory like the n-grams |
| `--mode=alarm` | SCADA/PLC shortcut: enables `--log-level` + `--top-lines` + `--regex-tag` (default tag `[A-Z]+[0-9]+`: `PLC1`, `TAG007`…) |
| `--watch`, `--follow` | Watches **one** file by polling: re-displays the summary every `--interval` seconds until Ctrl+C (exit 0). Forbidden with stdin or several files |
| `--interval=N` | Watch period in seconds (default 2, min 1) |

### Checks and comparison (CI)

| Option | Effect |
|---|---|
| `--check` | Check mode: CI gate with exit codes 2/3 (implicit with the options below) |
| `--fail-if=METRIC OPERATOR THRESHOLD` | Blocking check, repeatable (e.g. `--fail-if max_line_length>120`) |
| `--warn-if=METRIC OPERATOR THRESHOLD` | Non-blocking check (exit 3 if only warnings) |
| `--compare=BASELINE` | Compares against the values of an NDJSON baseline (`--summary-json` output) |
| `--fail-on-delta=METRIC>X` | Drift check: fails if the metric varies by more than X % vs the baseline |

Gate metrics: `lines`, `words`, `sentences`, `max_line_length`,
`avg_words_per_sentence` (alias `avg_sentence_words`), `non_utf8` (alias
`invalid_utf8`), `bom`, `crlf`, `tabs`, `nonprintable`. Operators:
`>`, `>=`, `<`, `<=`, `=`, `!=`. (Under CMD, escape `>`: `--fail-if lines^>5`
or `--fail-if "lines>5"`.)

### Display and export

| Option | Effect |
|---|---|
| `--top-words=N`, `--top-chars=N` | Limits for the Top sections (default 10; `0` = all) |
| `--char`, `--word`, `--line`, `--all` | Targeted "Top" sections / all the data |
| `--json` | JSON: 1 file = object; several = NDJSON (1 object per line) |
| `--json-mode=ndjson\|array\|aggregate` | Shape of the multi-file JSON (implies `--json`) |
| `--summary-json` | Flat JSON object per file (ideal for `jq` and scripts) |
| `--csv[=summary\|words\|chars]` | CSV v2 export (bare `--csv` = `summary`) |
| `--out=FILE` | Writes the output to a file (never any ANSI, never any console message) |
| `--quiet` | No console confirmation with `--out` |
| `--color`, `--no-color` | Minimal title coloring (console only) |
| `--version`, `--help`, `-h` | Version / help |
| `--interactive`, `--wizard` | Command-line generation wizard (v2.13.0); separate companion: `fcmd` |

### Examples

```
fstats examples\demo.obm
fstats --json --out=stats.json examples\demo.obm
fstats --csv=words --all rapport.txt
fstats --recursive=docs --include='**/*.md' --summary-json
echo "un deux trois." | fstats - --json
fstats 'tests/**/*.md' --json-mode=aggregate
fstats --word-mode=ascii --top-words=20 --lexical-stats corpus.txt
fstats --sentence-mode=smart rapport.txt
fstats --sentence-mode=smart --check --fail-if avg_words_per_sentence>25 docs/*.md
fstats --casefold=unicode --lexical-stats --json corpus_fr.txt
fstats --ngrams=3 --top-ngrams=20 --word-mode=ascii corpus.txt
fstats --ngrams=2 --stopwords=fr corpus_fr.txt
fstats --histogram=line_length --histogram=word_length rapport.txt
fstats --char-classes --json corpus.txt
fstats --readability rapport.txt
fstats --readability --word-mode=ascii --summary-json corpus.txt
fstats --pattern='ERROR|WARN' --top-lines=10 app.log
fstats --pattern='*timeout*' --json app.log
fstats --redact=email,ipv4,url --json app.log
fstats --log-level app.log
fstats --log-level --filter=error,warn --top-lines=5 app.log
fstats --mode=alarm alarms.log
fstats --regex-tag='PLC[0-9]+' --top-tags=10 alarms.log --json
fstats --watch --interval=2 --log-level app.log      # Ctrl+C to stop
echo -e "ERROR x\nINFO ok\nERROR y" | fstats - --pattern=ERROR --summary-json
fstats docs/**/*.md --check --fail-if max_line_length>120 --fail-if non_utf8>0
fstats app.log - --check --fail-if max_line_length>500       # via stdin
fstats --summary-json docs/*.md > baseline.ndjson            # capture
fstats docs/*.md --compare baseline.ndjson --fail-on-delta lines>10
fstats --help
```

## Output formats

- **Console**: sections aligned in pure ASCII (`Summary`, `Checks`, `Quality`,
  `Lexical`, `Readability`, `Top Characters/Words`, `Longest Lines`,
  `N-grams`, `Histogram`, `Character Classes`, `Patterns`, `Top Lines`,
  `Log Levels`, `Tags`), with no ANSI sequences — safe for scripts and pipes.
- **JSON**: traceability fields (`tool`, `version`, `schema_version`,
  `generated`) + `statistics`, `quality`, and additive blocks (`checks`,
  `lexical`, `readability`, `ngrams`, `histogram`, `char_classes`,
  `patterns`, `top_lines`, `log_levels`, `tags`) depending on the options.
- **CSV v2**: fixed header `file,type,rank,value,code_point,count,length`,
  three sub-formats (`summary`, `words`, `chars`).

The precise details (complete examples, JSON schemas, documented breaking
changes) are in the [technical specification](doc/en/SEMANTIQUE.md).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success — analysis OK, or all checks pass |
| 1 | Fatal error: file not found, glob with no match, invalid option, unwritable output, stdin mixed with files… |
| 2 | Check mode: at least one `--fail-if`/`--fail-on-delta` check failed |
| 3 | Check mode: no failure but at least one `--warn-if` triggered |

Data goes to **stdout**; errors, warnings, and `--out` confirmations go
to **stderr**.

## Documentation

| File | Content |
|---|---|
| [CHANGELOG.md](doc/en/CHANGELOG.md) | Version history (v2.2.0 → v2.16.2) |
| [doc/en/GUIDE-PEDAGOGIQUE.md](doc/en/GUIDE-PEDAGOGIQUE.md) | **Simple guide**: understand and use fstats without jargon |
| [doc/en/SEMANTIQUE.md](doc/en/SEMANTIQUE.md) | Technical specification: frozen semantics of the counters, detailed JSON/CSV formats |
| [doc/en/VERIFICATION.md](doc/en/VERIFICATION.md) | Validation journal (real outputs, history) |
| [doc/en/AUDIT-SECURITE.md](doc/en/AUDIT-SECURITE.md) | Security register: threats, fixed/in-progress/backlog risks — **read it before analyzing files provided by third parties** |
| [doc/en/ROADMAP-CIBLE1.md](doc/en/ROADMAP-CIBLE1.md) | Target 1 "CI / Text Quality Gate" (validated: A v2.2.0, B+C v2.6.0) |
| [doc/en/ROADMAP-CIBLE2.md](doc/en/ROADMAP-CIBLE2.md) | Target 2 "Corpus Profiler" (C2-A v2.3.0, C2-B v2.4.0, C2-C v2.5.0) |
| [doc/en/ROADMAP-CIBLE3.md](doc/en/ROADMAP-CIBLE3.md) | Target 3 "Log Sentinel" — **complete** (C3-A v2.8.0 … C3-D v2.11.0: patterns, top-lines, redaction, log-level, filter, alarm, watch) |
| [doc/ROADMAPFULL.md (fr)](doc/ROADMAPFULL.md) | Overall vision and complete roadmaps |
| [doc/en/README.md](doc/en/README.md) | Documentation index |

## Automated tests

- `tests\run.bat` (Windows / CMD) and `tests\run.sh` (Linux / Git Bash):
  build + 127 acceptance cases (Targets 1-2-3, the `fcmd` companion,
  P0/P1/P2 fixes) with JSON validation via node and exit-code checks —
  state verified at v2.16.2: **127/127 on both suites**.
- Prerequisites: `fpc` and `node` on the PATH.
- The GitHub Actions CI runs both suites on `windows-latest` and
  `ubuntu-latest` at every push to `main` and every `pull_request`.

## Project structure

```
fstats/
├── .github/workflows/ci.yml  # GitHub Actions CI (Windows + Linux)
├── doc/                      # Documentation (guide, spec, roadmaps, validation)
├── doc/en/                   # English translations of the documentation
├── exemples/                 # Demo corpus (SCADA logs, texts, data, edge cases)
├── src/fstats.pas            # Main program (entry point, CLI parsing)
├── src/fstats_types.pas      # Constants, globals, types (TStats, options…)
├── src/fstats_utf8.pas       # UTF-8, VisualChar, sorts, ANSI colors, FormatFloatTrim
├── src/fstats_glob.pas       # Internal glob engine (*, **, ?) and --recursive
├── src/fstats_lex.pas        # Tokenization, n-grams, patterns/redaction, log-level, regex-tag
├── src/fstats_sha.pas        # SHA-256 streaming (FIPS 180-4): baseline integrity
├── src/fstats_analyzer.pas   # Analysis (file/stdin) + C3-D watch + Ctrl+C handlers
├── src/fstats_checks.pas     # Quality gate: checks, NDJSON baseline, --fail-on-delta
├── src/fstats_cmdgen.pas     # Shared wizard (command generation, v2.13.0)
├── src/fcmd.pas              # fcmd companion: generates the command line
├── src/fstats_output.pas     # Output: console, JSON, CSV, usage
├── tests/                    # Test suites + fixtures (run.sh + run.bat, 127 cases)
├── LICENSE                   # MIT license
└── README.md
```

## Known limitations (in brief)

> The reference list, prioritized and kept up to date, is the register
> [doc/en/AUDIT-SECURITE.md](doc/en/AUDIT-SECURITE.md) — read it before analyzing
> files provided by third parties.

- `--out` now **refuses** to designate a file being analyzed
  (anti-destruction protection, v2.14.0) — instead of silently emptying it.
- The values entered in the wizard are executed through separate arguments
  (no shell); the **displayed** command, however, remains plain text:
  under cmd.exe, pasting it still expands `%VAR%` (security register P2).
- **UTF-8 text files only**: an invalid sequence is replaced by U+FFFD and
  counted (`invalid_utf8`).
- The **BOM is detected but kept** (a deliberate choice).
- The default definition of a word includes attached punctuation
  (`raw` mode); `--word-mode=ascii|unicode` strips the punctuation.
- The `unicode` case folding is a limited basic table (French/German
  accents), not a full Unicode folding.
- N-grams: top-K is **approximate** on very large corpora
  (bounded-memory sketch); not aggregated in `--json-mode=aggregate`.
- A period **between two digits** (`3.14`) does not close a sentence
  (v2.6.1); a period after a digit followed by a space (`Version 3.`)
  still counts as a sentence end.
- The readability score (`--readability`) is an approximation **without
  syllables**: it is not an exact Flesch-Kincaid (the formula is frozen
  in the technical specification).
- `--regex-tag` is a **mini-engine** (literal + `[...]` classes +
  `? * +`), not a full regex; frozen scope in the technical specification.
- `--top-lines` and `--top-tags`: top-K is **approximate** on very large
  logs (bounded dictionary like the n-grams).
- `--watch` (v1) **re-analyzes the entire file** at every tick
  (byte-by-byte incremental analysis is not implemented); sufficient for
  reasonably sized logs, documented.

All the semantics are detailed and frozen in the
[technical specification](doc/en/SEMANTIQUE.md).
