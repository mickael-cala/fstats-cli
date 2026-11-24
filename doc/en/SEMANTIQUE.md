> 🇬🇧 **English translation** — canonical version (authoritative): doc/SEMANTIQUE.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# Technical specification — frozen semantics and output formats

> Reference document for `fstats` (v2.16.2). The semantics described here
> are **frozen**: they will not change in future versions without an
> explicit announcement. For getting started, see the
> [pedagogical guide](GUIDE-PEDAGOGIQUE.md); for the overview, the
> [README](README.md).

## Unknown options / missing values (v2.16.1)

- An argument starting with `--` that matches **no** option of the
  grammar produces `Erreur: option inconnue : --xxx` (exit 1) — and no
  longer “Fichier inaccessible ou introuvable” (the old behavior added it
  to the file list).
- An option whose **bare** form requires a value (`--redact`,
  `--mode`, `--out`, `--word-mode`, `--casefold`, `--histogram`, …) produces
  `Erreur: l'option --xxx exige une valeur` (exit 1). The exact list
  is frozen in `KNOWN_VALUE_OPTS` (fstats.pas); options whose bare
  form is legal (`--check`, `--json`, `--top-lines` = default 10,
  `--compare VALUE`, …) have their own branch in the parser.
- A file actually named `--quelquechose` must be prefixed:
  `fstats ./--fichier.txt` (the message reminds you of this).

## Output formats

### Console

> Illustrative excerpt: the blocks below each show the shape of a section,
> **not the outputs of a single file** (fictional demonstration file
> below; different lines depending on the option illustrated). The real
> outputs measured on repository files are in `VERIFICATION.md` and
> `exemples/README.md` (fr).

```
File: demo.obm (demo name, not a repository fixture)
Generated: 2026-08-26 11:47:13

Summary
-------
  Lines:              27
  Words:             170
  Characters:        976
  Sentences:           7
  Avg words/sentence: 24
  Line length:  min 7, max 68, avg 35

Quality
-------
  Invalid UTF-8:       0
  BOM:               yes
  CRLF:                2
  Tabs:                0
  Non-printable:       0

Top Characters (10 of 67)
-------------------------
   #  Char      Code         Count
   1  ' '       U+0020         143
   ...
```

`Summary` is always displayed; the **Quality** section only appears if at
least one quality counter is non-zero (or a BOM is present) — the output for
“clean” files is therefore strictly identical to that of v2.1. The
**Lexical** section only appears with `--lexical-stats`. The three Top
sections are filtered by `--char`/`--word`/`--line`. The `(N of K)` suffix
only appears if the actual total exceeds the displayed limit
(`--top-words`/`--top-chars`/`--all`).

Console with `--lexical-stats` (dedicated section, pure ASCII):

```
Lexical
-------
  Unique words:       16
  Hapax:              12
  Type-token ratio: 0.8
  Avg word length:  3.75
  Entropy:        3.9219
```

Console with `--ngrams=2 --histogram=line_length --char-classes` (dedicated
C2-B sections, pure ASCII):

```
N-grams (N=2)
-------------
   #  N-gram                       Count
   1  avec des                         1
   2  des mots.                         1
   ...

Histogram (line_length)
-----------------------
  0-9     0
 10-19  # 1
 20-29  # 1
 30-39  # 1
 40+      0

Character Classes
-----------------
  Letters:        57
  Digits:          0
  Whitespace:     12
  Punctuation:     3
  Control:         0
  Other:           0
```

The `N-grams`, `Histogram` and `Character Classes` sections are added when
their options are enabled, **independently** of `--char`/`--word`/`--line`.

### JSON

All JSON exports carry the traceability fields `tool` (`"fstats"`),
`version` and `schema_version` (`"1.0"`), in addition to `generated`.

**1 file + `--json` → single object (“pretty” format):**

```json
{
  "file": "tests/fixtures/test_fr.txt",
  "generated": "2026-08-26 11:38:35",
  "tool": "fstats",
  "version": "2.16.2",
  "schema_version": "1.0",
  "statistics": {
    "lines": 3, "words": 13, "characters": 72,
    "sentences": 3, "avg_words_per_sentence": 4,
    "line_lengths": { "min": 16, "max": 30, "average": 23 }
  },
  "quality": {
    "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0
  },
  "top_characters": [ { "rank": 1, "character": "e", "code_point": "U+0065", "count": 11 } ],
  "top_words":      [ { "rank": 1, "word": "un", "count": 2 } ],
  "longest_lines":  [ { "rank": 1, "length": 30, "content": "Deuxième phrase avec des mots." } ]
}
```

With `--lexical-stats`, an **additive** `"lexical"` block is inserted after
`quality` (existing keys unchanged, `schema_version` stays `"1.0"`):

```json
{
  "...": "...",
  "quality": { "...": "..." },
  "lexical": {
    "unique_words": 12,
    "hapax": 11,
    "type_token_ratio": 0.923077,
    "average_word_length": 4.615385,
    "entropy_bits_per_word": 3.546594
  },
  "top_characters": [ "...": "..." ]
}
```

**Multiple files + `--json` → NDJSON (default, 1 compact object per line):**

```
{"file": "tests\/fixtures\/bom.txt", "generated": "...", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": true, "crlf": 0, "tabs": 0, "nonprintable": 0}, ...}
{"file": "tests\/fixtures\/crlf.txt", "generated": "...", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": false, "crlf": 2, "tabs": 0, "nonprintable": 0}, ...}
```

The multi-file JSON is **no longer concatenated** (v2.1 default corrected):
each line is a complete, independent JSON object, validatable line by line
(`JSON.parse` per line, `jq -c`…).

**`--json-mode=array` → JSON array:**

```json
[
  { "file": "tests\/fixtures\/bom.txt", "...": "...", "quality": { "...", "bom": true } },
  { "file": "tests\/fixtures\/crlf.txt", "...": "...", "quality": { "...", "crlf": 2 } }
]
```

**`--json-mode=aggregate` → global object with totals:**

```json
{
  "tool": "fstats",
  "version": "2.16.2",
  "schema_version": "1.0",
  "generated": "2026-08-26 11:38:40",
  "files": [ { "file": "tests\/docs\/guide\/api.md", "...": "..." } ],
  "totals": { "files": 3, "lines": 9, "words": 21, "characters": 123, "sentences": 3 }
}
```

The totals are the exact sum of the statistics of the listed files.

**`--summary-json` → flat object per file (one per line, jq-ready):**

```
{"file": "tests/fixtures/test_fr.txt", "sha256": "<64 hex>", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

**`sha256`** (v2.16.0, P2 wave 3): SHA-256 digest (FIPS 180-4) of the
**file contents**, computed streaming — identical to the result of
`sha256sum`/`Get-FileHash`. It is the **baseline integrity** key:
`--compare` verifies it (see Baseline and drift). The key is **omitted**
for stdin and unreadable files; an older baseline without `sha256` still
passes the check (backward compatible).

With `--lexical-stats`, `--summary-json` adds (still flat) the keys
`unique_words`, `hapax`, `type_token_ratio`, `average_word_length` and
`entropy_bits_per_word` at the end of the object.

### CSV

**CSV v2 (v2.3.0)** — fixed header: `file,type,rank,value,code_point,count,length`.

> ⚠️ **Documented breaking change** (assumed, made in C2-A): the v1 format
> (`metric,rank,value,code_point,count` with `character`/`word`/`line` rows
> mixed together, then a `sentence_count`/`source_file`/`generated`
> summary) is **replaced**. The computed values remain strictly identical;
> only the structure and the columns change.

Three sub-formats (`--csv` alone = `summary`):

| Sub-format | Content | Filled columns |
|---|---|---|
| `--csv=summary` | One row per metric (`value` = name, `count` = value) | `file`, `type=summary`, `value`, `count` |
| `--csv=words` | Top words (`rank`, `value` = word, `count` = frequency, `length` = code points) | all |
| `--csv=chars` | Top characters (`rank`, `value` = character, `code_point` = U+XXXX, `count`, `length` = 1) | all |

**Cell escaping (v2.14.1)**: the LF, CR and TAB control characters are
first replaced with the literals `\n`, `\r`, `\t` (no cell can break the
first line); then double quotes are doubled (`"` → `""`) when the cell
contains a comma or a quote, as in RFC 4180.
**Formula neutralization**: any cell starting with `=`, `+`, `-` or `@` is
prefixed with an apostrophe `'` (`=cmd|…` becomes `'=cmd|…`) — a defense
against Excel/LibreOffice formula injection (DDE) at the moment a human
opens the export. The apostrophe is part of the exported data; it is
**not** a marker that a third-party tool must remove.

Example `--csv` (summary, file metrics):

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

With `--lexical-stats`, the `unique_words`, `hapax`,
`type_token_ratio`, `average_word_length` and `entropy_bits_per_word` rows
are appended at the end of the list. Example `--csv=words` (Top 10 by
default):

```
file,type,rank,value,code_point,count,length
tests/fixtures/test_fr.txt,word,1,un,,2,2
tests/fixtures/test_fr.txt,word,2,phrase,,1,6
...
```

The Top limit follows `--top-words`/`--top-chars` (or `--all`); `file`
provides traceability (the `generated` timestamp of the v1 format is
removed).

## Quality counters (must-read)

The quality counters **do not affect** the existing metrics (characters,
words, lines, sentences): they complement them for file-hygiene
diagnostics. They are exposed in the console `Quality` section, in the
JSON `quality` block, and flat in `--summary-json`.

- **invalid_utf8**: number of **invalid UTF-8 sequences**: invalid lead
  byte, missing or incorrect continuation byte, overlong encoding,
  reserved ranges (U+D800–U+DFFF), out of Unicode range (beyond U+10FFFF).
  Each invalid sequence is replaced with U+FFFD and counted as **1**; the
  replacement character counts as a character but acts as a **word
  separator** (it never belongs to a word).
  **Block boundary (v2.14.1)**: reading is done in 64 KiB blocks with a
  **buffer zone** — a multi-byte character straddling two blocks is
  reassembled, never counted as invalid; an orphan at the very end of the
  file (a sequence truncated by EOF, not by the boundary) counts as 1.
  The total verified length = file size + 1 (sentinel); each position is
  visited only once.
- **bom**: boolean; **true if U+FEFF is the very first character of the
  stream**. The BOM is **not removed** from the content: it remains
  counted as a character (lines, words, lengths) and is preserved as-is in
  the exports (UTF-8 bytes `EF BB BF`; its console rendering depends on
  the terminal).
- **crlf**: number of **CRLF line endings** (CR immediately followed by
  LF). A lone LF or a lone CR counts as an ordinary line ending,
  **without** incrementing this counter.
- **tabs**: number of **tabulations** (U+0009), wherever they occur.
- **nonprintable**: number of **control characters** (U+0000–U+001F and
  U+007F) **excluding** LF (U+000A), CR (U+000D) and TAB (U+0009) — these
  three being already tracked by their own counters (lines/CRLF/tabs).

Example: `tests/fixtures/crlf.txt` (2 CRLF line endings) gives
`crlf = 2`, `tabs = 0`, `nonprintable = 0`; `tests/fixtures/tabs.txt` gives
`tabs = 2`; `tests/fixtures/invalid-utf8.bin` gives `invalid_utf8 = 1`.

## Storage caps (v2.15.0)

**Metrics are exact regardless of file size; only the data held in memory
for matching and grouping is capped.**

- **Stored line**: at most `LINE_STORE_MAX` = **65,536 UTF-8 bytes**
  (constant in `fstats_types.pas`). Beyond that, the line kept for
  matching (`--pattern`, `--regex-tag`, log levels), `--top-lines`
  grouping and the previews (`Longest Lines`) is truncated at the cap.
  Documented consequences: a match located beyond the cap is not seen;
  two lines identical over their first 65,536 bytes share the same
  grouping key. `line_min`/`line_max`/`line_avg`, the character counter
  and the lengths remain **exact** (counted on the fly).
- **Stored word**: at most `WORD_STORE_MAX` = **1,024 UTF-8 bytes**. A
  longer word (possible under `--word-mode=raw`: anything that is neither
  whitespace nor a control character) still counts **once** in `words`
  and in the character counter; only the dictionary key (Top Words,
  n-grams) is truncated to 1,024, and `average_word_chars` / the
  `word_length` histogram measure it capped (an accepted-and-documented
  approximation).
- Rationale (P2 audit, security register): a file with a single 32 MB
  line would saturate the CPU (quadratic concatenation, 18 s) and
  memory (whole line kept). Appends are now amortized O(1)
  (geometric growth), memory is bounded, and the counters — the nominal
  use case — remain exact.

## Counter semantics (must-read)

- **Characters**: Unicode code points decoded as strict UTF-8; line breaks
  count as characters.
- **Words**: by default (`--word-mode=raw`), runs of characters with code
  point > `0x20` (space and control characters = separators).
  Consequence: punctuation attached to a word is part of it (`simple.`),
  and isolated punctuation (`!`) counts as a word. The `ascii`/`unicode`
  modes strip punctuation (see “Lexical semantics”).
- **Top Words / Top Characters ordering (tie-break, v2.16.2)**:
  descending sort by frequency; at **equal** frequency, deterministic
  order — Top Characters by **ascending code point**, Top Words in
  **ascending lexicographic** order (byte-to-byte comparison). Two runs
  produce the same Top, byte for byte. **Documented breaking change**:
  before v2.16.2, tie order depended on the traversal (not guaranteed);
  at equal count, `abricot` now precedes `zebre` (test 123) — this is the
  frozen behavior. Same rule as `top_lines` (ties → ascending
  alphabetical).
- **Sentences**: closed by `.`, `!`, `?` or `…` (U+2026); if the file
  ends with non-blank content after the last terminator, one extra final
  sentence is counted. Since v2.6.1, a period **between two digits**
  (`3.14`) does NOT close a sentence (decimal); a period after a digit
  followed by anything other than a digit (`Version 3. Fin.`) always
  closes. A period surrounded by spaces (`3 . 14`) closes (not an
  attached decimal).
- **`--sentence-mode` (v2.7.0)**: `basic` (default) = the rule above.
  `smart` = additionally, for the `.` period only (`!`, `?`, `…` always
  close): the period is **swallowed** (no closure) if the current word is
  an abbreviation from the frozen `SMART_ABBREVIATIONS` list (lowercase:
  `e.g`, `i.e`, `m`, `mme`, `mlle`, `dr`, `pr`, `st`, `ste`, `etc`, `mr`,
  `mrs`, `ms`, `jr`, `sr`, `inc`, `ltd`, `co`, `dept`, `fig`, `vs`,
  `www` — with a prefix rule for `e.g.`/`i.e.`: the first period is
  protected because `e.` is a prefix of `e.g`), or if the window of the
  last 8 characters contains `://` (URL, e.g. `https://ex.com`). Documented
  scope: a period following an unrecognized word closes; `www.` without a
  protocol protects only its first period (`www.ex.com` closes at
  `.com`); `e. g` (with a space) swallows its period via the prefix rule.
- **Lines**: terminated by LF, CR or CRLF; length is in characters,
  excluding the line break; min/max/average apply to non-empty lines.
- ASCII words are normalized to lowercase (case-insensitive frequencies
  for ASCII; non-ASCII Unicode is kept as-is) — behavior that can be
  changed with `--casefold` (see “Lexical semantics”).

## Lexical semantics (v2.3.0)

### Word definition (`--word-mode`)

| Mode | Word definition (frozen) | Separators |
|---|---|---|
| `raw` (default) | code points > `0x20` and ≠ U+FFFD (historical, punctuation included) | spaces, controls, U+FFFD |
| `ascii` | run of `[A-Za-z0-9_]` | everything else (punctuation, accents…) |
| `unicode` | run of **Unicode letters/digits** from the scope below | everything else (punctuation, symbols…) |

`unicode` scope (documented, without a full Unicode library): ASCII
digits; ASCII letters; Latin-1 (excluding `×` U+00D7 and `÷` U+00F7);
Latin Extended A/B (U+0100–U+024F); IPA (U+0250–U+02AF); combining marks
(U+0300–U+036F, stay attached to the letter); Greek (U+0370–U+03FF,
excluding Greek semicolon U+037E); Cyrillic (U+0400–U+04FF); Latin
Extended Additional (U+1E00–U+1EFF); Arabic-Indic digits (U+0660–U+0669)
and extended Arabic-Indic digits (U+06F0–U+06F9).

### Case folding (`--casefold`)

| Mode | Behavior (frozen) |
|---|---|
| `ascii` (default) | `A-Z` → `a-z` only (historical) |
| `unicode` | `ascii` + a small basic table: accented Latin-1 `À..Þ` → `à..þ` (U+00C0–U+00D6, U+00D8–U+00DE, `+0x20`), `Œ`→`œ`, `Ÿ`→`ÿ`, `ẞ`→`ß` |
| `none` | case preserved (no folding) |

Accepted-and-documented scope: **no** full Unicode case folding (FPC RTL
limitation) — the table covers the common French/German accents,
documented as-is. Example: with `--casefold=unicode`, `Été` and `été`
become the same type; with `--casefold=none` they stay distinct.

### `--lexical-stats` metrics

Frozen formulas (current mode = active tokenization + folding):

- `unique_words`: number of **word types** (distinct) of the current
  mode; capped by `--max-unique` when applicable (see below).
- `hapax`: number of types with frequency **exactly 1**.
- `type_token_ratio`: `unique_words / words` (types ÷ tokens of the
  current mode).
- `average_word_length`: average token length in **code points** (sum of
  the lengths of all tokens ÷ `words`), independent of `--max-unique`
  (accumulated streaming).
- `entropy_bits_per_word`: `-Σ pᵢ log₂ pᵢ` (in bits) over the types of
  the current mode, with `pᵢ = countᵢ / words`. Bounded by
  `[0, log₂(unique_words)]`.

Presence: console (`Lexical` section), JSON (`"lexical": {...}` in the
full/compact objects; flat keys at the end of the object for
`--summary-json`) and CSV summary. The addition is **additive**: without
`--lexical-stats`, the existing keys are strictly unchanged
(`schema_version` stays `"1.0"`).

### `--max-unique` (memory cap)

Default 100,000. As long as the number of stored types is `< N`, every
new word is added; beyond that, **new types stop being added**: known
words keep accumulating their frequencies, but new types are ignored for
the vocabulary. Documented semantics: `unique_words` is **capped at N and
not exhaustive**; `hapax`/`type_token_ratio`/`entropy` then cover the
stored set of types. `words` (tokens) and `average_word_length` remain
exact (counted streaming).

## Structure semantics (v2.4.0)

### N-grams (`--ngrams`)

- **Definition (frozen)**: n-grams are sliding windows of N words
  (1 ≤ N ≤ 5) over the **words of the current mode** — the active
  tokenization (`--word-mode`) and case folding (`--casefold`) are
  applied, consistent with `--lexical-stats`.
- **No crossing of lines**: each line produces its own windows; a line
  break “cuts” the stream (no n-gram spans two lines).
- **Top-K (bounded memory)**: only the `--top-ngrams=K` most frequent
  are kept (default 10, `0` = all). Memory bounded by a **top-K sketch**:
  when the n-gram dictionary exceeds `max(8×K, 64)` entries, it is
  reduced to the top-K. Documented consequence: on a very large corpus, a
  rare n-gram dropped along the way can be missing from the final top
  (the counts of the kept n-grams remain exact). On the test corpora, the
  result is exact.
- **JSON**: additive key `"ngrams": [{"rank": r, "words": [...words...],
  "count": c}, ...]` (array of words). Console: “N-grams (N=…)” section
  with rank, n-gram (words separated by a space) and count.
- **Validation**: `--ngrams=0` or `--ngrams>5` → fatal error (exit 1).
  `--stopwords` and `--top-ngrams` **without** `--ngrams` are **silently
  ignored** (no effect, exit 0) — consistent with `--include`/`--exclude`
  without `--recursive`.

### Stop words (`--stopwords`)

Stop words are removed **from the token stream used for n-grams only**:
the existing word statistics (`words`, top words, `--lexical-stats`,
`word_length` histogram…) are **not** affected. The matching applies to
the **casefolded** stream (default `--casefold=ascii`: `Il` → `il` is
removed; with `--casefold=none`, `Il` is not).

Built-in lists (frozen, 20 words per language):

| Language | Stop words |
|---|---|
| `fr` | `le la les un une des de du et ou mais que qui ce il elle on je tu ne` |
| `en` | `the a an and or but of to in on for with is are was it this that not as` |

Example: `fstats --ngrams=2 --stopwords=fr corpus.txt` — “le” and “il” do
not participate in the bigrams, but remain counted in the words.

### Histograms (`--histogram`)

Three metrics, bars in **pure ASCII** (`#`, 1 bar per occurrence, capped
at 60) followed by the numeric count. **Frozen** classes (identical to
the roadmap §6.6 example for `line_length`; defined and documented here
for the other two):

| Metric | Classes | Index of value V |
|---|---|---|
| `line_length` | `0-9`, `10-19`, `20-29`, `30-39`, `40+` | `min(V div 10, 4)` |
| `word_length` | `1-2`, `3-4`, `5-6`, `7-8`, `9-10`, `11-12`, `13+` | `min((V−1) div 2, 6)` |
| `words_per_sentence` | `0-4`, `5-9`, `10-14`, `15-19`, `20+` | `min(V div 5, 4)` |

Semantics:
- `line_length`: line length in **code points**, all lines included
  (empty lines fall into `0-9`); **the sum of the classes = `lines`**.
- `word_length`: word length of the current mode in **code points**
  (consistent with `average_word_length`); **the sum of the classes =
  `words`**.
- `words_per_sentence`: words per sentence per the existing sentence
  detection (`.` `!` `?` `…`); an empty sentence (consecutive
  terminators) is counted in `0-4`; **the sum of the classes =
  `sentences`**. In `--word-mode=raw` mode (default), punctuation
  attached to a word (`simple.`) belongs to the word but closes the
  sentence immediately: per-sentence counts are then approximate (use
  `--word-mode=ascii|unicode` for “clean” words).

JSON: additive key `"histogram": {"metric": "line_length", "classes":
[{"range": "0-9", "count": n}, ...]}`. Console: “Histogram (metric)”
section.

### Character classes (`--char-classes`)

Each code point is classified **exactly once** during decoding; the sum
of the six classes is **exactly `characters`** (test assertion).
**Frozen** ranges:

| Class | Exact ranges |
|---|---|
| `whitespace` | `U+0009` (TAB), `U+000A` (LF), `U+000D` (CR), `U+0020` (space) — consistent with the `tabs` counter (TAB is not a “non-printable”) |
| `control` | C0 excluding TAB/LF/CR (`U+0000`–`U+001F` minus `U+0009`/`U+000A`/`U+000D`), DEL (`U+007F`), C1 (`U+0080`–`U+009F`) |
| `digits` | `U+0030`–`U+0039` (ASCII digits) |
| `letters` | `A-Z` (`U+0041`–`U+005A`), `a-z` (`U+0061`–`U+007A`), Latin-1 excluding `×`/`÷` (`U+00C0`–`U+00D6`, `U+00D8`–`U+00F6`, `U+00F8`–`U+00FF`), Latin Extended A/B (`U+0100`–`U+024F`), Greek excluding Greek semicolon (`U+0370`–`U+03FF` except `U+037E`), Cyrillic (`U+0400`–`U+04FF`), Latin Extended Additional (`U+1E00`–`U+1EFF`) |
| `punctuation` | ASCII ranges `U+0021`–`U+002F`, `U+003A`–`U+0040`, `U+005B`–`U+0060`, `U+007B`–`U+007E` + Latin-1 punctuation/symbols (`U+00A1`–`U+00BF`) |
| `other` | everything else: symbols, non-ASCII Unicode whitespace (`U+00A0`, `U+2000`…), combining marks (`U+0300`–`U+036F`), IPA (`U+0250`–`U+02AF`), `U+FFFD` (invalid UTF-8 sequences), BOM `U+FEFF`… |

JSON: additive key `"char_classes": {"letters": n, "digits": n,
"whitespace": n, "punctuation": n, "control": n, "other": n}`. Console:
“Character Classes” section. The `control` class and the `nonprintable`
counter can differ on a file containing C1 controls (included in
`control`, excluded from `nonprintable`).

### Multi-file aggregation (`--json-mode=aggregate`)

In aggregate mode, `char_classes` and `histogram` are **summed class by
class** into `totals` (keys `totals.char_classes` and `totals.histogram`,
same structures as per file). **N-grams are not aggregated** (documented
limitation): `totals` contains no `ngrams` key; n-grams remain present in
each object of `files`.

## Check engine semantics (v2.6.0)

Target 1 B+C: `fstats` becomes a text-quality guardrail for CI. Check mode
is activated by `--check` **or implicitly** by `--fail-if`, `--warn-if`,
`--compare` or `--fail-on-delta`. In check mode, exit codes 2/3 apply;
analysis mode keeps 0/1 (no breaking change).

### Frozen grammar

- `--fail-if=<metric><op><threshold>` (or separate arguments:
  `--fail-if <metric> <op> <threshold>`) — blocking check, repeatable.
  `--warn-if`: same grammar, non-blocking.
- Metric: `[a-z0-9_]+`. Operators: `>`, `>=`, `<`, `<=`, `=`, `!=`.
  Threshold: `[0-9]+(".[0-9]+")?` ('.' separator, no sign, no exponent,
  locale-independent).
- Gate metrics: `lines`, `words`, `sentences`, `max_line_length`
  (= `line_max`), `avg_words_per_sentence` (integer division, like the
  Summary; alias `avg_sentence_words`), `non_utf8` (alias
  `invalid_utf8`), `bom` (0/1), `crlf`, `tabs`, `nonprintable`.
  Unknown metric or invalid syntax → fatal error (exit 1, stderr).
  NB: **both names are accepted in both engines** (gate and drift); the
  JSON summary key is `invalid_utf8` (the code canonicalizes, it never
  rejects either name).

### Statuses and exit codes

- Status of a check: `ok` | `warn` | `fail` (strict numeric comparison).
- Multi-file: the worst cumulative status wins (fail > warn > ok).
- `--check` **with no check defined**
  (`--fail-if`/`--warn-if`/`--fail-on-delta`): explicit warning on
  stderr (« mode check actif sans aucun check defini… »), exit **0**
  unchanged — the no-op gate is visible, never silent (v2.14.1).
- Exit: 0 = all ok (or no check defined); 1 = fatal error (takes
  precedence); 2 = at least one fail; 3 = no fail but at least one warn.

### Baseline and drift (`--compare`, `--fail-on-delta`)

- Baseline: NDJSON produced by `--summary-json` (one JSON line per file,
  `file` key); a single object is accepted. Unreadable line → exit 1.
- Matching is done on the `file` string exactly as fstats displays it.
  A file with no baseline → drift checks ignored for that file — **and
  VISIBLE** (v2.16.0): stderr warning `absent de la baseline` + counter
  in the verdict line of the console output. Never silent.
- `--fail-on-delta=<metric>>X` (repeatable, `>` mandatory):
  `delta = (actual - base) / base * 100`; failure if `delta > X`.
  `base = 0`: delta 0 if actual = 0, otherwise infinite drift (failure —
  a metric going from 0 to >0 is infinite drift, documented).
  **A NEGATIVE delta cannot fail** (an accepted-and-documented growth
  threshold, security register §6: the gate protects against metric
  explosion, a decrease is not an anomaly for logs); the delta value
  (negative) is still displayed, readable.
  Accepted forms: `--fail-on-delta=M>X` (v2.16.0: the `=` form had been
  silently broken since v2.6.0 — off-by-one on the prefix),
  `--fail-on-delta:M>X`, or `--fail-on-delta M>X` (3 arguments).
- **`sha256` integrity** (v2.16.0): if the baseline entry carries the
  `sha256` key and the hash of the current file contents differs, a
  `sha256` check **fails** (console: `sha256 != 0 : FAIL (actual 1)`,
  `actual 1` = divergence) — the file changed its content even if its
  metrics are stable (masked drift). Identical hash → `sha256` check
  `ok` (`actual 0`, proven integrity = useful information, not noise).
  Baseline without the `sha256` key → check skipped (backward
  compatible). stdin / unreadable file: no verification.
- Delta metrics: numeric keys of summary-json (`lines`, `words`,
  `characters`, `sentences`, `avg_words_per_sentence` (alias
  `avg_sentence_words`), `line_min`, `line_max`, `line_avg`,
  `invalid_utf8` (alias `non_utf8`), `bom`, `crlf`, `tabs`,
  `nonprintable`). NOTE: the `sha256` key is NOT a delta metric (a hash
  drift is an integrity failure, not a percentage).

### Check outputs

- **Console verdict** (v2.16.0): in check mode with at least one check
  (or a `sha256` check issued by `--compare`), the console output ends
  with a readable line:
  `Verdict : OK (tous les checks passent) - exit 0`
  / `Verdict : ATTENTION (...) - exit 3` / `Verdict : ECHEC (...) - exit 2`
  (+ an `N fichier(s) hors baseline` line when applicable).
  The verdict **never** appears in `--json`/`--csv`/`--summary-json`
  (pure data formats — scripts read the exit codes).
- Console: `Checks` section after Summary (metric, op, threshold,
  status, actual value; for deltas, the delta %). Pure ASCII. The
  integrity check displays as `sha256 != 0 : FAIL (actual 1)`
  (divergence) or ok with `actual 0`.
- Pretty/NDJSON JSON: additive `checks` block (after `quality`):
  `{"id": …, "metric": …, "actual": …, "op": …, "threshold": …,
  "status": …}`. `id` = metric (or `delta:<metric>`), then `#2`,
  `#3`… on repeats. For a delta, `actual` = delta % and `op` = `>`.
  The `sha256` check: `id = "sha256"`, `metric = "sha256"`, `actual` = 0
  (identical) or 1 (divergence), `op = "!="`, `threshold = 0`.
- `--summary-json` and `--csv`: **no** checks section (the exit codes
  still apply). `--json-mode=aggregate`: checks per file, never in
  `totals`.

## Readability semantics (v2.5.0)

`--readability` adds 4 metrics computed on **the current mode** (same
tokens as `--word-mode` + `--casefold` folding, consistent with
`--lexical-stats`). Inspired by Flesch but **without syllables** (no
syllable detection in French/English): this is not an exact
Flesch-Kincaid — explicitly noted in the README.

### Metrics (exact formulas)

- `avg_sentence_words` = `WordCount / SentenceCount` (floating; 0 if no
  sentence). Not to be confused with `avg_words_per_sentence` from the
  Summary, which is **integer** division (`div`).
- `avg_word_chars` = `WordCharsTotal / WordCount` (0 if no word) — same
  value as `average_word_length` from `--lexical-stats`.
- `pct_long_words` = `100 * LongWordCount / WordCount` (0 if no word),
  where `LongWordCount` = tokens of length **>= 7 code points** (constant
  `LONG_WORD_MIN_LEN = 7`).
- `score` (0-100, bounded):

  ```
  score = 100 * (1 - (0.5 * min(ASL/30, 1) + 0.5 * min(max(ALW-3, 0)/5, 1)))
  ```

  with `ASL = avg_sentence_words` and `ALW = avg_word_chars`. Anchors:
  an average sentence of 30+ words or an average word of 8+ characters
  each zero out **half** the score. A text without any word (empty file)
  gets a score of 0 (nothing to assess).

### Output keys

- Pretty / NDJSON JSON: additive `readability` block with the 4 keys
  (`avg_sentence_words`, `avg_word_chars`, `pct_long_words`, `score`),
  6 decimals via `FormatFloatTrim`.
- `--summary-json`: flat keys `avg_sentence_words`, `avg_word_chars`,
  `pct_long_words`, `readability_score` at the end of the object
  (6 decimals).
- CSV `--csv=summary`: rows `summary,,avg_sentence_words,,<v>,`,
  `summary,,avg_word_chars,,<v>,`, `summary,,pct_long_words,,<v>,`,
  `summary,,readability_score,,<v>,` (6 decimals).
- Console: `Readability` section (4 lines, 4 decimals, `%` on
  `Pct long words`).

Like the n-grams, readability **is not aggregated** in
`--json-mode=aggregate` (present per file only — an
accepted-and-documented limitation, noted in the code).

## Log Sentinel semantics (v2.8.0, Target 3-A)

### Patterns (`--pattern=TEXT`)

- **Internal matcher** (NOT a full regex): literals + `|` (alternation) +
  `*` (any run, separators included) + `?` (exactly one character).
  Case-insensitive (ASCII UpCase, like the Windows glob).
- **v2.15.0: linear greedy algorithm** (no backtracking, no recursion)
  — a pathological pattern (`*a*a*a*a*a*a*b`) can no longer freeze:
  complexity O(len(pattern)×len(line)). The exploration order is that
  of the old algorithm (minimal star first, resume on the last star);
  parity verified on 37 pattern×file combinations.
- **Zero-length match not counted** (v2.15.0): a pattern matching empty
  at a position (`*`, `**`, empty alternation segment `a||b`) is not an
  occurrence — the counter stays at 0 and the scanner advances one
  position (before: infinite loop).
- **Non-overlapping occurrences**, searched left to right in each
  line. A line contributes to `lines` if it contains at least one match,
  and to `matches` by its total number of occurrences.
- Matching happens on the line as built internally (`VisualChar`
  applied: controls become `\t`, `[CTRL]`…), **capped at
  `LINE_STORE_MAX` = 65,536 bytes** (v2.15.0, cf. Storage caps): a match
  beyond the cap is not seen.
- Repeatable: each `--pattern` produces a distinct entry in `patterns`.
- JSON: `"patterns": [{"pattern": "...", "lines": N, "matches": M},
  ...]`. Console: `Patterns` section. CSV: `type=pattern` rows
  (`value`=pattern, `count`=matches, `length`=lines). `--summary-json`:
  flat key `patterns`.

### Top identical lines (`--top-lines=N`)

- Groups **identical** lines (exact comparison of the internal string)
  and keeps the N most frequent (default 10 if the option is passed
  without a value; **`0` = section disabled**, option absent =
  disabled — v2.16.1: the help and this doc used to say “0 = all”,
  which was wrong). Descending sort by frequency, then alphabetical for
  ties (determinism).
- **Bounded memory** like the n-grams: when the dictionary exceeds
  `max(8×N, 64)` entries, it is reduced to the top-N (rare lines dropped
  along the way are lost — documented approximation, exact on small
  corpora).
- JSON: `"top_lines": [{"rank": r, "count": c, "line": "..."}, ...]`.
  Console: `Top Lines` section. CSV: `type=topline` rows (`rank`,
  `value`=line, `count`). `--summary-json`: flat key `top_lines`.
- Not aggregated in `--json-mode=aggregate` (like the n-grams and
  readability): present per file only.

### Redaction (`--redact=email,ipv4,url`)

- Comma-separated list, repeatable. Each mode replaces the found
  occurrences with `***` **in the outputs only** (console, JSON, CSV) —
  the counters (`words`, `characters`, `lines`…) remain computed on the
  **raw text** (documented, tested).
- **email**: `local-part@domain.tld` with at least one dot in the
  domain and characters `[A-Za-z0-9._+-]` for the local part.
- **ipv4**: 4 groups of 1-3 digits separated by `.`, not followed by a
  digit or a dot (keeps out the decimals `3.14` and the versions
  `1.2.3.4.5`).
- **url**: `http://…` or `https://…` up to the next whitespace or end
  of string.
- Redaction applies to **any emission of text originating from the
  file**: `longest_lines.content`, `top_lines.line`, console line
  previews, and — since **v2.14.0 (P1-3)** — **top words, n-grams and
  tags** in all formats (console, JSON, CSV, `--summary-json`). Single
  characters from Top Characters are not redacted (a single character
  does not reconstruct data). Paranoid history note: before v2.14.0, Top
  Words leaked emails/IPs/URLs despite `--redact` — the doc of the time
  described that behavior as intended; it was a defect, fixed and
  tested (test 109 of run.sh: grep of the redacted target = 0 across
  all outputs).

## Log Sentinel semantics — levels (v2.9.0, Target 3-B)

### Log levels (`--log-level`)

- Detection by case-insensitive **whole word**, anywhere in the line:
  `ERROR`, `WARN` (and **`WARNING`**, v2.14.1 — log4j, Python), `INFO`,
  `DEBUG`, `TRACE`. A “whole word” is delimited by non-alphanumeric
  ASCII characters or by the string edges (`ERRORS` does not match
  `ERROR`; `ERROR:` does). `WARNING` counts toward the `warn` level
  (there is no distinct “warning” level).
- **Frozen priority**: `ERROR` > `WARN` > `INFO` > `DEBUG` > `TRACE` —
  the first found in this order wins, even if a lower level is also
  present (`WARN then ERROR` → `error`).
- `none` = a line with none of these words. **The sum of the 6 levels =
  `lines`** (test assertion).
- JSON: `"log_levels": {"error": N, "warn": N, "info": N, "debug": N,
  "trace": N, "none": N}`. Console: `Log Levels` section. CSV:
  `type=loglevel` rows (`value`=name, `count`=lines).
  `--summary-json`: flat key `log_levels`. Not aggregated in
  `--json-mode=aggregate` (like the n-grams).

### Filter (`--filter=error,warn,...`)

- Comma-separated list of levels
  (`error,warn,info,debug,trace,none`, case-insensitive). Filters the
  **console display** of the line sections (`Top Lines`, `Longest
  Lines`): only lines whose detected level belongs to the set are
  displayed, with ranks renumbered.
- **The global counters still cover the whole file** (documented,
  tested): `lines`, `words`, `log_levels`, `patterns`… are not
  affected.
- In JSON/CSV, all lines are exported (the filter is console-only).
- `--filter` without `--log-level` is accepted (the filter still
  applies to the display, detection being done on the fly).

## Log Sentinel semantics — alarm / tags (v2.10.0, Target 3-C)

### Tag extraction (`--regex-tag=PATTERN`)

- **Regex-subset mini-engine** (NOT a full regex, frozen scope):
  literals + `[...]` classes (ranges `a-z`, `0-9`, `A-Z`, single chars)
  + quantifiers `?` (0..1), `+` (1..∞), `*` (0..∞) after a token;
  default = 1. Case-insensitive for literals.
- **v2.15.0: NFA state-set simulation** (no backtracking) — complexity
  O(len(line)×len(pattern)) per starting position; a pattern with
  nested quantifiers (`a*a*a*b` on a long line) can no longer freeze.
  Frozen semantics: from each position, the retained match is the
  **longest**; an empty match is not extracted (the scanner advances
  one position).
- Extraction: **non-overlapping** occurrences, left to right, in each
  **stored** line (capped at `LINE_STORE_MAX` = 65,536 bytes, v2.15.0).
  The tag = the matched substring.
- Examples: `PLC[0-9]+` → `PLC1`, `PLC23`; `[A-Z]+[0-9]+` → `PLC1`,
  `MOTOR23`, `SENSOR7`.
- Top-K capped like the n-grams/top-lines: `--top-tags=N` (default 10,
  `0` = all); the dictionary is reduced to the top-N beyond
  `max(8×N, 64)` entries.
- JSON: `"tags": [{"rank": r, "tag": "...", "count": N}, ...]`.
  Console: `Tags` section. CSV: `type=tag` rows. `--summary-json`: flat
  key `tags`. Not aggregated in `--json-mode=aggregate`.

### Alarm mode (`--mode=alarm`)

- SCADA/PLC shortcut: enables `--log-level` + `--top-lines` (10) +
  `--regex-tag` with the default pattern `[A-Z]+[0-9]+` (`PLC1`,
  `TAG007`-type identifiers). If `--regex-tag` is also passed, it takes
  over.
- `--mode` accepts only `alarm` (any other value → exit 1).

## Log Sentinel semantics — watch (v2.11.0, Target 3-D)

### Watch (`--watch` / `--follow` + `--interval=N`)

- Watches **exactly one file** (stdin and multi-file are forbidden →
  exit 1). File absent at startup → exit 1.
- Infinite polling loop: every `N` seconds (default 2, min 1), the
  file is **fully re-analyzed** (v1 — the byte-by-byte incremental mode
  is not implemented, documented limitation) and an ASCII status line
  is displayed:
  `[timestamp] lines=N (+delta) words=N chars=N sentences=N | error=… warn=… info=… none=…`
  (levels only appear with `--log-level`).
- `+delta` = change in lines since the previous tick. If the file
  shrank (truncation/rotation), a `[TRUNCATED]` marker is displayed.
- Unreadable file along the way → message on stderr, the loop
  continues.
- **Ctrl+C** (SIGINT/SIGTERM) → clean shutdown, message `Stopped.`,
  **exit 0**.
- Pure ASCII console (no ANSI), `Flush` after each line (real time).

## Validation (reference text)

`tests/fixtures/test_fr.txt` (3 lines): “Voici un exemple simple. /
Deuxième phrase avec des mots. / Encore un test !”

| Metric                    | Expected value  |
|---------------------------|-----------------|
| Lines                     | 3               |
| Words                     | 13              |
| Characters                | 72              |
| Sentences                 | 3               |
| Avg words/sentence        | 4               |
| Length min / max / avg    | 16 / 30 / 23    |

Verification commands:

```
fstats tests\fixtures\test_fr.txt
fstats --json tests\fixtures\test_fr.txt   # validate with a JSON parser
fstats --csv  tests\fixtures\test_fr.txt
fstats --help                # exit code 0
fstats fichier_inconnu.txt   # exit code 1, message on stderr
```

### Companion — command-line generation (v2.13.0)

- `fstats --interactive` (alias `--wizard`): interactive wizard
  (corpus/log/gate profiles + all options by category). Displays the
  generated command; on `o` confirmation, fstats re-executes itself with
  that command and **propagates the exit code of the child**. Without
  input (EOF/closed pipe), only displays the command (exit 0 if
  canceled, 1 if EOF before the end).
- `fcmd`: separate companion binary, same logic. Options:
  `--dry-run` (display only, exit 0), `--exec` (execute without asking,
  exit code propagated), `--profil=N` (1=corpus 2=log 3=gate; the names
  `corpus`/`log`/`gate` are accepted since v2.13.1), `--help`.
  The wizard reads stdin line by line: pipe-drivable
  (`printf '2\n0\n' | fcmd --dry-run`). `fcmd` executes the `fstats`
  located in the same directory as itself (otherwise an explicit
  refusal — v2.14.0).
- **v2.14.0 (P1-1)**: execution goes through **separate arguments**
  (`SysUtils.ExecuteProcess`: fork/execve or CreateProcess) — never
  through a shell. A value containing `; rm -rf` is just an argument.
  The displayed command quotes metacharacters (space, tab,
  `& | < > ^ % ! ; $ \ ( ) …`) ; known limit: cmd.exe expands
  `%VAR%` at paste time even between quotes (security register, P2).
- Wizard output: `Commande générée :` then the quoted line for the
  current shell (double quotes under Windows, single quotes under
  Unix).

See `VERIFICATION.md` for the validation journal (actual outputs).
