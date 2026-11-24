> 🇬🇧 **English translation** — canonical version (authoritative): doc/ROADMAP-CIBLE3.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# Roadmap Target 3 — Log Sentinel

Status: **COMPLETE — C3-A v2.8.0 + C3-B v2.9.0 + C3-C v2.10.0 + C3-D v2.11.0
(2026-11-23, 100 tests)** — patterns, top-lines, redaction, levels, filter,
alarm/tags, watch/follow.

Positioning: `fstats` monitors application and SCADA/PLC logs: levels, top messages,
patterns, redaction, watch. NDJSON output for pipelines/Grafana.

Base: [ROADMAPFULL.md (fr)](../ROADMAPFULL.md) (Mode 3 “Log Sentinel”, §7.1-7.4, §6.9
redaction).
Depends on: Target 1 delivered (v2.2.0: stdin, NDJSON, glob, quality counters, line
statistics).

## Verdict

The FULL roadmap aims at a complete SCADA alarm mode (timestamps, severity, tags,
abnormal intervals). **We adapt**: v1 = log profiling (levels + patterns + top messages
+ redaction) + watch with simple polling. Timestamp parsing and interval analysis stay
out of scope (documented), because they would require a real log-format parser — not
a counter.

## State already in place (v2.2.0, verified)

- stdin, NDJSON (the ideal format for logs), glob/recursion
- Quality counters: `invalid_utf8`, `crlf`, `tabs`, `nonprintable`
  (hygiene of corrupted logs)
- `line min/max/avg` + `longest_lines` (detection of abnormal lines)
- Pure ASCII output, stable exit codes, streaming

## FULL roadmap → adaptations (what is possible)

| Feature (FULL roadmap) | Decision | Reason |
|---|---|---|
| Full regex (`--pattern`, `--regex`) | **ADAPT**: internal literal matcher + `|` + `*`/`?` + simple classes `[0-9]` | `TRegExpr` is not in the standard RTL: it would break single-binary portability |
| Full `--mode=alarm` (timestamp, severity, tag, intervals) | **ADAPT**: v1 = counting by severity and by tag (`--regex-tag`), no time parsing | timestamp parsing = a format parser, outside the counter's scope |
| `--watch` | **DO** it with polling (re-reads from the last position, `--interval`) | no inotify: Windows/Linux/Termux portability |
| Interactive `--tail` / `--grep` | **ADAPT**: `--filter=NIVEAU` (filters the displayed lines) | an interactive tail is another tool |
| Redaction (`--redact`) | **DO** (C3-A) | essential to log without leaking (emails, IP, URLs) |
| SQLite / DuckDB / Parquet / Grafana push | **DISCARDED** | the existing NDJSON export is enough; network push later |
| Plugins / scripting | **DISCARDED** | the roadmap itself advises against it (§7.6) |

## Increments

### C3-A — Patterns & top messages — **DELIVERED (v2.8.0)**

- `--pattern=TEXTE` (repeatable, literal); alternation `A|B`; wildcards `*`/`?`
  (documented internal matcher, NOT a full regex). ✅
- `--top-lines=N`: groups identical lines (count + truncated example), top-K
  bounded like the n-grams. ✅
- `--redact=email,ipv4,url`: replaces with `***` **in the outputs only**
  (the counters are still computed on the raw text). ✅
- JSON: `patterns: [{pattern, matches, lines}]`, `top_lines: [{rank, count, line}]`. ✅
- Console: `Patterns` and `Top Lines` sections. CSV: `pattern`/`topline` rows.
  `--summary-json`: flat keys `patterns`/`top_lines`.

### C3-B — Levels — **DELIVERED (v2.9.0)**

- `--log-level`: detects ERROR/WARN/INFO/DEBUG/TRACE (case-insensitive whole word,
  priority in this order, anywhere in the line). ✅
- Counting per level + `none` (lines without a level). Sum of the 6 = `lines`. ✅
- `--filter=error,warn,...`: filters the console display of lines
  (`Top Lines`, `Longest Lines`), global counters over the whole file. ✅
- JSON: `log_levels: {error: N, warn: N, info: N, debug: N, trace: N, none: N}`. ✅
- Console: `Log Levels` section. CSV: `type=loglevel` rows.

### C3-C — Alarm/SCADA v1 — **DELIVERED (v2.10.0)**

- `--mode=alarm`: shortcut = `--log-level` + `--top-lines` + `--regex-tag`. ✅
- `--regex-tag=PATTERN` (subset: literals + classes `[...]` + `? * +`): extracts
  and counts tags (e.g. `PLC[0-9]+`). ✅
- `--top-tags=N`: bound on the tag top (default 10). ✅
- JSON output: `log_levels` + `tags` (no timestamps, as planned). ✅

### C3-D — Watch (polling) — **DELIVERED (v2.11.0)**

- `--watch` / `--follow`, `--interval=N` (default 2 s, min 1 s): periodic
  summary (lines, levels, delta, timestamp). ✅
- v1: full re-analysis on every tick (byte-by-byte incremental is a future
  optimization, documented); truncated file → `[TRUNCATED]` marker. ✅
- ASCII console, real-time Flush, errors on stderr, Ctrl+C → exit 0. ✅
- Restricted to ONE file (stdin/multi-file → exit 1). ✅

## Semantics to freeze

- Level: first occurrence (whole word, case-insensitive) of
  ERROR > WARN > INFO > DEBUG > TRACE in the line; otherwise `none`.
- Pattern: literal, `|` = alternation, `*` = any sequence, `?` = one character.
  No full regex — document that in black and white.
- Redaction: email `[\w.+-]+@[\w-]+(\.[\w-]+)+`, ipv4 `\d{1,3}(\.\d{1,3}){3}`,
  url `https?://\S+` — applied **after** counting.
- Watch: file must exist at start; minimum interval 1 s; no inotify.

## Guardrails

- No full regex (single-binary portability).
- No timestamp parsing or abnormal intervals in v1.
- No plugins, no SQLite/Parquet, no network push.
- Bounded memory: top-lines/top-tags bounded (default 10, `--all` for everything).
- Pure ASCII console; the counters are never skewed by redaction.

## Effort & risks

- Estimated delta: **~700-900 lines** (A ≈ 35%, B ≈ 25%, C ≈ 20%, D ≈ 20%).
- Risks: (1) internal matcher = documented scope, do not let people believe in a
  full regex; (2) polling watch = CPU cost → incremental re-reading made mandatory,
  minimum interval 1 s; (3) redaction after counting so the statistics are never
  skewed.
- Tests: log fixtures (levels, patterns, tags, long lines, invalid UTF-8),
  extension of `tests/run.bat`; watch tested with a short script and a timeout.

## Decision

Order: **C3-A ✅ → C3-B ✅ → C3-C ✅ → C3-D ✅ — TARGET 3 COMPLETE (v2.11.0,
100 tests).**
