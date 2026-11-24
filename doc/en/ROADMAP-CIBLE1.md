> 🇬🇧 **English translation** — canonical version (authoritative): doc/ROADMAP-CIBLE1.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# Roadmap Target 1 — CI / Text Quality Gate for docs & logs

Status: **validated** — increment A delivered (v2.2.0, 12/12 tests OK), B and C delivered
(v2.6.0, 59/59 tests OK across both suites, 2026-08-26). Fix v2.6.1 (decimals 3.14).
Target 1 complete.
Base: [ROADMAPFULL.md (fr)](../ROADMAPFULL.md) (sections 3, 5, 10, 13) — positioning “fstats = text profiler & quality gate”

## Verdict

The **CI / text quality gate for docs/logs** niche is the right first release, and it is consistent
with what fstats already is. Counters, strict UTF-8 and JSON export already exist; the value to add
lies not in the metrics but in the **decision engine** (thresholds + exit codes + comparison).

Deliverable positioning:

> **fstats check: a textual quality guard that fails the CI when docs/logs drift.**

## Verified state (inspection of 2026-08-26, fstats.pas 1512 lines)

| Already solid (proven) | Missing for the niche |
|---|---|
| **Block streaming** analysis (`BlockRead` + `BUF_SIZE`) — architecture consistent with §11 of the roadmap | **stdin `-`**: nothing in argument parsing |
| Incremental strict UTF-8 (`DecodeUTF8`) | **No invalid-byte counter**: the invalid is silently replaced with U+FFFD → `non_utf8` impossible to verify |
| `lines`, `words`, `characters`, `sentences`, `avg_words_per_sentence`, line length `min/max/avg` | **No BOM / CRLF / tabs / controls detection** (the code already tracks CR/LF via `LastCPWasCR`) |
| JSON/CSV, pure ASCII console, `--out`, `--quiet`, exit codes 0/1, per-file error handling (`HadError`) | **Invalid multi-file JSON**: `fstats --json a.txt b.txt` concatenates two `{...}` objects (stdout **and** `--out`), still exit 0. The docs only flag the `--out` case; the stdout case is worse |
| — | No glob, no checks, no `--compare` |

## Scope: 3 increments, each deliverable and testable

### Increment A — “the pipe” (makes fstats scriptable in CI) — DELIVERED (v2.2.0)
- `fstats -` / `--stdin` (forbid mixing stdin + files)
- **Non-negotiable internal glob**: under PowerShell/CMD, `docs/**/*.md` is never expanded by the shell →
  globs in arguments + `--recursive=DIR`, `--include=PATTERN`, `--exclude=PATTERN`
- **Multi-file NDJSON** (default as soon as several files are given) + `--json-mode=array|aggregate`
- `--summary-json` (flat object, handy for `jq`)
- Quality counters: `invalid_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`

### Increment B — “the judge” (the heart of the niche) — DELIVERED (v2.6.0)
- Check engine: `--fail-if METRIQUE OPERATEUR SEUIL`, repeatable
- **Exit codes: 0 = OK, 2 = check failed, 3 = warnings only, 1 = fatal error** — check mode only;
  analysis mode keeps 0/1 (no breakage for existing scripts)
- Enriched JSON output: `checks: [{id, metric, actual, op, threshold, status}]` section + `schema_version`
- Checks from the start: `lines`, `words`, `sentences`, `max_line_length`, `avg_sentence_words`,
  `non_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`
- Delivered: `--check` (check mode, implicit with the check options), `--warn-if`
  (same grammar, non-blocking, exit 3), operators `> >= < <= = !=`, decimal
  thresholds, console `Checks` section after Summary, `checks` JSON block
  pretty/NDJSON (id `metric`/`delta:metric`, `#2`… for repeats). Frozen semantics in
  [SEMANTIQUE.md](SEMANTIQUE.md). 17 new test cases (56 total across both suites).

### Increment C — “the memory” (drift) — DELIVERED (v2.6.0)
- `--compare baseline.json` + `--fail-on-delta metric>X%` — turns the gate into a docs/logs QA tool
- Delivered: NDJSON baseline (`--summary-json` output, one line per file,
  `file` key, single object accepted), `delta = (actual-base)/base*100`,
  `base=0` → infinite drift if actual > 0 (documented), file without baseline
  → drift checks skipped, delta metrics = numeric keys of the
  summary-json, `delta:<metric>` checks in console/JSON.

CI examples (GitHub Actions + GitLab) and golden tests are added along the way.

## Proposed exit contract (to be frozen in the README)

```text
exit 0 : analysis OK / all checks pass
exit 1 : fatal error (file not found, invalid option, stdin+files mixed)
exit 2 : at least one check failed           (check mode, increment B)
exit 3 : warnings only                       (check mode, increment B)
```

```sh
fstats docs/**/*.md --check --fail-if max_line_length>120 --fail-if non_utf8>0
fstats app.log - --check --fail-if max_line_length>500        # via stdin
fstats docs/*.md --check --config fstats.json                 # later
```

## Guardrails (what we do not do)

- **No multi-unit refactor** in this release: the single file holds up to ~2,500 lines,
  the check engine slots in cleanly. The split will wait for the corpus/logs modes.
- **No patterns/regex/log-level**: for logs, this release covers *quality*
  (UTF-8, lines, size, drift). ERROR/WARN counting is a different engine (roadmap §7.3).
- **No TOML config in the first pass**: command-line `--fail-if` is enough for CI.
- **No change to the analysis-mode exit codes** (compatibility).
- No GUI, no SQLite, no watch.

## Effort & risks

- Estimated delta: **~500–700 lines of Pascal** on top of the current 1512 + fixtures + CI YAML.
  A ≈ 40% of the effort, B ≈ 35%, C ≈ 25%.
- Risks: (1) switching to NDJSON is a **breaking change** for existing scripts →
  do it in A and document it; (2) the `--fail-if` grammar must be frozen early
  (operators `> >= < <= = !=`, stable snake_case metrics, `schema_version`);
  (3) do not introduce exit code 3 before a real use case (warning ≠ failure).
- Tests: new fixtures (`bom`, `crlf`, `invalid-utf8`, `long-line`, `empty`) + exit-code
  assertions, in the style of the existing [VERIFICATION.md](VERIFICATION.md), automated
  (test.bat/test.sh) — the project's CI must be able to use fstats itself (eat your own dog food).

## Decision

Scope validated. **All increments delivered**: A (v2.2.0), B and C (v2.6.0), fix v2.6.1,
`--sentence-mode=smart` v2.7.0. **Target 1 complete.**
