> 🇬🇧 **English translation** — canonical version (authoritative): doc/ROADMAP-CIBLE2.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# Roadmap Target 2 — Corpus Profiler

Status: **C2-A, C2-B and C2-C delivered** (v2.5.0, tests OK, 2026-08-26).
Target 2 complete.

Positioning: `fstats` explores a text corpus: vocabulary, n-grams, distributions, export
for pandas/R/Excel.

Base: [ROADMAPFULL.md (fr)](../ROADMAPFULL.md) (Mode 2 “Corpus Profiler”, §6.1-6.8, §8 CSV).
Depends on: Target 1 delivered (v2.2.0: glob, NDJSON/array/aggregate, --summary-json,
streaming, strict UTF-8, quality counters).

## Verdict

A natural extension of Target 1: it reuses the existing hash dictionaries
(`TCharDict`/`TWordDict`) and the multi-file JSON export already in place. The value:
make fstats a corpus exploration tool (docs, linguistics, beginner NLP) **with zero
dependencies**, while staying single-file, streaming and pure-ASCII.

## State already in place (v2.2.0, verified)

- Block streaming, O(1) character/word dictionaries
- Top 10 characters/words/lines (`--all` for everything)
- Multi-file NDJSON/array/aggregate + `--summary-json`
- Globs/recursion, stdin
- Quality counters (hygiene diagnostic before lexical analysis)

## FULL roadmap → adaptations (what is possible)

| Feature (FULL roadmap) | Decision | Reason |
|---|---|---|
| Improved top words (`--word-mode`) | **DO** (C2-A) | simple mechanism on the existing stream |
| Full Unicode case folding | **ADAPT**: `ascii` first, then a basic accent table | no Unicode case folding in the FPC RTL; documented scope |
| `smart` sentence detection (decimals, abbreviations, URLs) | **DONE (v2.6.1 + v2.7.0)**: `3.14` decimals in the default mode; `--sentence-mode=basic\|smart` — `smart` protects a frozen list of fr/en abbreviations (`M.`, `etc.`…) and `://` URLs; documented scope (`www.` without protocol partial, `e. g` swallows its period) | a full heuristic is beyond reasonable reach, opaque semantics → frozen list + simple documented rules |
| Lexical statistics (unique, hapax, TTR, entropy) | **DO** (C2-A) | trivial computation from frequencies |
| N-grams | **DO** (C2-B) | bounded windows over words |
| ASCII histograms | **DO** (C2-B) | reuses the existing console output |
| Character classes | **DO** (C2-B) | counting during decoding |
| Readability (Flesch/Flesch-Kincaid…) | **ADAPT**: simple metrics (words/sentence, chars/word, % long words, documented 0-100 score) | syllables are non-trivial in FR/EN, no lib |
| CSV v2 export (`file` column, sub-formats) | **DO** (C2-A) | useful for pandas/Excel; documented breaking change |
| SQLite / DuckDB / Parquet | **DISCARDED** | roadmap §7.5: “later” |

## Increments

### C2-A — Lexicon (the core)

- `--word-mode=raw|ascii|unicode`: `raw` = current behavior;
  `ascii` = words `[A-Za-z0-9_]+` (punctuation removed); `unicode` = Unicode letters and
  digits, punctuation removed.
- `--casefold=ascii|unicode|none`: `ascii` = ASCII lowercase (current);
  `unicode` = limited basic table (French/German accents etc., scope
  documented in the README); `none` = case preserved.
- `--lexical-stats`: `unique_words`, `hapax`, `type_token_ratio`,
  `average_word_length`, `entropy_bits_per_word` (approx. from the
  frequencies, documented formula).
- `--top-words=N`, `--top-chars=N` (replaces the fixed limit of 10), and
  `--max-unique=N` (memory guard, default 100,000).
- `--csv=summary|words|chars`: CSV v2 with a `file` column (header
  `file,type,rank,value,code_point,count,length`).
- Console output: new sections, still pure ASCII.

### C2-B — Structure

- `--ngrams=N` (1..5) + `--top-ngrams=K` + `--stopwords=fr|en|none` (built-in
  short lists).
- `--histogram=line_length|word_length|words_per_sentence` (ASCII bins identical
  to the roadmap examples).
- `--char-classes`: `letters`/`digits`/`whitespace`/`punctuation`/`control`/
  `other` (JSON + console).

### C2-C — Readability (small added value, optional) — DELIVERED (v2.5.0)

- `--readability`: `avg_sentence_words`, `avg_word_chars`,
  `pct_long_words` (>= 7 characters), simple 0-100 score (formula inspired by
  Flesch, without syllables, documented).
- No exact Flesch-Kincaid: say so in the README.
- Delivered: formula frozen in [SEMANTIQUE.md](SEMANTIQUE.md) (“Readability
  semantics”); 6 new cases in both suites (39 total); `readability` in
  console, JSON pretty/NDJSON, `--summary-json` (flat keys), CSV summary;
  not aggregated in `--json-mode=aggregate` (like n-grams).

### `smart` sentence detection — DELIVERED (v2.6.1 + v2.7.0)

- v2.6.1: `3.14` decimals no longer close a sentence (period-between-two-digits
  rule, in the default mode).
- v2.7.0: `--sentence-mode=basic|smart`. `smart` = `basic` + abbreviations
  (frozen list `SMART_ABBREVIATIONS`, fr/en) + `://` URLs (window over the last
  8 characters). Scope documented in [SEMANTIQUE.md](SEMANTIQUE.md)
  (“Sentence semantics”): `www.` without protocol partial, `e. g` swallows
  its period, `!`/`?`/`…` always close. 8 new cases in both suites (67 total).

## Semantics to freeze (from C2-A)

- `word-mode=ascii`: word = a run of `[A-Za-z0-9_]`, everything else separates;
  lowercase (unless `casefold=none`).
- N-grams: windows over the words of the current mode, never crossing line
  breaks; only top-K are kept (bounded memory).
- `entropy = -Σ p_i log2 p_i` over the types of the current mode.
- `hapax` = types with frequency 1; `TTR` = types/tokens of the current mode.
- CSV v2 = **breaking change** of the current CSV format: do it in C2-A,
  document it, keep the values strictly identical.

## Guardrails

- No heavy NLP, no models, no dependencies: still a single Pascal file,
  standard FPC RTL.
- Bounded memory: `--max-unique=N`, bounded top-K, n-grams limited to top-K.
- Pure ASCII console output, no ANSI when piped.
- Do not change the semantics of the existing counters in default mode
  (regression forbidden: test_fr.txt 3/13/72/3).

## Effort & risks

- Estimated delta: **~600-800 lines** of Pascal (A ≈ 45%, B ≈ 40%, C ≈ 15%).
- Risks: (1) breaking CSV v2 → document it and do it early; (2) limited unicode
  casefold → explicit scope, no “full Unicode” promise; (3) n-grams on large
  corpora → bounded top-K by default, `--max-unique`.
- Tests: corpus fixtures (fr/en, accents), golden, extension of
  `tests/run.bat`, JSON validation with node.

## Decision

Order: **C2-A → C2-B → C2-C** (C2-C optional). Start with C2-A.
