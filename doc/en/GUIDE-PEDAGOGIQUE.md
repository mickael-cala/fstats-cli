> 🇬🇧 **English translation** — canonical version (authoritative): doc/GUIDE-PEDAGOGIQUE.md. This file mirrors the French source (fstats v2.16.2, 2026-11-24). Code terms (options, outputs, flags) are kept verbatim.

# fstats — the guide to understanding and using the tool

> This guide is aimed at everyone: no programming knowledge is required.
> You will learn what `fstats` does, how to install it, and how to read its
> results. The examples show **real outputs** of the tool.

---

## 1. What is fstats?

`fstats` is a small program that **analyzes text files** and gives you
**numbers about their content**:

- how many **characters**, **words**, **lines** and **sentences** there are;
- which **words are the most frequent**;
- which **expressions come back** (groups of words that follow one another);
- **quality** information: broken encoding, Windows line endings, tabs…

It is designed to be **simple, fast and reliable**:

- **no dependencies**: a single executable file;
- **Windows and Linux**: the same commands everywhere;
- **scriptable**: the output can be JSON or CSV, not just text.

### Who is it for?

- **students** analyzing texts (theses, corpora);
- **developers** who want statistics on logs or data;
- the **curious** who want to explore a text.

### What it does not do (to be honest)

- it does not analyze the **meaning** of words (no AI, no sentiment);
- it reads **UTF-8 text files** (no binary files);
- it is not designed for files of several gigabytes (but it documents its
  limits and knows how to bound its memory).

---

## 2. Installing fstats

For now, fstats is **compiled from source** (there are no pre-built binaries
to download yet). You need:

1. the **Free Pascal** compiler (free) — `fpc` on the command line;
2. the project's sources:

```
git clone https://github.com/mickael-cala/fstats-cli.git
cd fstats-cli
```

3. to compile, from the repository root:

```
fpc -Sg -O2 -Mobjfpc -FE. src\fstats.pas
```

(-Sg is required: the wildcards matcher uses GOTO/LABEL; it is implicit in
the official fpc.cfg files, not in a minimal fpc.cfg.)

The `fstats.exe` executable (Windows) or `fstats` (Linux) appears at the root.

> **Check that everything works:**

```
fstats --version
```

It must display something like `fstats 2.16.2`.

> **Windows note**: `wbld.bat` compiles without having to type the command,
> `wclr.bat` removes the compilation files (`*.o`, `*.ppu`, `*.exe`).

> **Tip (v2.13.0)**: to generate the command line without memorizing the
> options, launch the companion: `fstats --interactive` (built-in wizard) or
> `fcmd` (separate binary). It asks you questions, displays the generated
> command and can run it. Pipe example: `printf '2\n0\n' | fcmd --dry-run`.
>
> cmd.exe trap (documented, knowingly accepted): when PASTING a command into a
> Windows console, `%VAR%` would be expanded by cmd — the command generated
> by the wizard never introduces any `%`, but if your paths contain some,
> it is cmd that will interpret them, not fstats.

---

## 3. First analysis, step by step

Create a small text file, for example `test.txt`, with this content
(3 lines):

```
Voici un exemple simple.
Deuxième phrase avec des mots.
Encore un test !
```

Then run:

```
fstats test.txt
```

Here is what fstats displays (real output, on this very text):

```
File: test.txt
Generated: 2026-08-26 18:53:29

Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23

Top Characters (10 of 25)
-------------------------
   #  Char      Code         Count
   1  'e'       U+0065          11
   2  ' '       U+0020          10
   ...

Top Words (10 of 12)
--------------------
   #  Word                 Count
   1  'un'                     2
   2  'des'                    1
   ...

Longest Lines
-------------
   #  Length  Preview
   1      30  Deuxième phrase avec des mots.
   2      24  Voici un exemple simple.
   3      16  Encore un test !
```

### How to read this table

| Line | What it means |
|---|---|
| `Lines: 3` | the file has 3 lines |
| `Words: 13` | fstats found 13 words |
| `Characters: 72` | 72 characters in total (spaces and line breaks included) |
| `Sentences: 3` | 3 sentences (ending with `.`, `!`, `?` or `…`) |
| `Avg words/sentence: 4` | on average, 4 words per sentence |
| `Line length: min 16, max 30, avg 23` | the shortest line is 16 characters, the longest 30, average 23 |
| `Top Characters` | the most frequent characters (here `e` 11 times, space 10 times…) |
| `Top Words` | the most frequent words (here `un` 2 times, all the others 1 time) |
| `Longest Lines` | the 10 longest lines, with a preview |

That's all: **one command, and you know the essentials of a text.**

---

## 4. Useful options for everyday use

### Analyzing several files, folders, or the standard input

| Command | Effect |
|---|---|
| `fstats a.txt b.txt` | analyzes both files (one summary per file) |
| `fstats "**/*.md"` | analyzes **all** the `.md` files in the folder and subfolders |
| `fstats "*.log"` | analyzes all the `.log` files in the current folder |
| `echo "un deux trois." \| fstats -` | analyzes a text passed "on the fly" (stdin) |
| `fstats --recursive=src --include='**/*.pas'` | walks the `src` tree, filtering |

> The `*.txt` / `**/*.md` patterns are handled **by fstats itself**: your
> terminal does not need to know how to expand globs (useful on Windows).

### Choosing the output

| Command | Effect |
|---|---|
| `fstats --json fichier.txt` | JSON output (readable by programs) |
| `fstats --summary-json fichier.txt` | one JSON line per file (perfect for `jq`) |
| `fstats --csv fichier.txt` | a CSV table (importable into Excel) |
| `fstats --json --out=rapport.json fichier.txt` | writes the output to a file |

### Exploring the vocabulary and the repetitions

| Command | Effect |
|---|---|
| `fstats --lexical-stats fichier.txt` | unique words, hapax, entropy… |
| `fstats --ngrams=2 fichier.txt` | the most frequent word pairs |
| `fstats --ngrams=3 --top-ngrams=10 fichier.txt` | the 10 most frequent word triplets |
| `fstats --ngrams=2 --stopwords=fr fichier.txt` | bigrams without the stop words ("le", "de"…) |
| `fstats --histogram=word_length fichier.txt` | the distribution of word lengths |
| `fstats --char-classes fichier.txt` | letters / digits / whitespace / punctuation… |

> `fstats --help` lists all the options, and the [README](../README.en.md)
> gives the complete reference.

### Assessing the readability of a text

```
fstats --readability test.txt
```

```
Readability
-----------
  Avg sentence words:4.3333
  Avg word chars: 4.6154
  Pct long words:23.0769%
  Score (0-100): 76.6239
```

Four indicators, with nothing to install: how many words per sentence on
average, how many characters per word, the share of long words (7 characters
or more), and a score from 0 to 100 (the higher, the easier to read). It is
an approximation **without syllables** — not an exact Flesch-Kincaid — but
sufficient to compare two versions of a text with each other.

### Analyzing logs (patterns, repeated lines, redaction)

```
fstats --pattern='ERROR|WARN' --top-lines=5 app.log
```

```
Patterns
--------
  Pattern                   Lines  Matches
  'ERROR|WARN'                  5        5

Top Lines
---------
  #  Count  Line
   1      2  2026-01-15 10:00:05 ERROR connection timeout to db.internal
   2      2  2026-01-15 10:00:12 INFO health check OK
```

- `--pattern=TEXTE`: searches for the text in each line (`*` = anything,
  `?` = one character, `|` = "or"). It counts the lines hit and the total
  of occurrences. You can use several.
- `--top-lines=N`: groups **identical** lines and shows the N most frequent
  (handy for spotting the messages that keep coming back in a loop).
- `--redact=email,ipv4,url`: replaces emails, IPs and URLs with `***` in the
  display (the counters, for their part, stay on the raw text).
- `--log-level`: counts the lines by level (`ERROR`, `WARN`, `INFO`,
  `DEBUG`, `TRACE` — whole word, case-insensitive):

```
fstats --log-level app.log
```

```
Log Levels
----------
  Error:               4
  Warn:                1
  Info:                4
  Debug:               0
  Trace:               0
  None:                0
```

- `--filter=error,warn`: only displays the lines of these levels (in
  `Top Lines` / `Longest Lines`). The counters, for their part, always
  cover the whole file.

```
fstats --log-level --filter=error --top-lines=5 app.log
```

### Alarm mode (SCADA / PLCs)

```
fstats --mode=alarm alarms.log
```

It is a shortcut that activates three things at once: the levels
(`--log-level`), the repeated lines (`--top-lines`) and the extraction of
**tags** (`--regex-tag`, default pattern `[A-Z]+[0-9]+` which catches
`PLC1`, `MOTOR23`, `TAG007`…):

```
Log Levels
----------
  Error:               3
  Warn:                2
  Info:                3
  Debug:               0
  Trace:               0
  None:                0

Tags
----
  #  Count  Tag
   1      5  PLC1
   2      2  MOTOR23
   3      1  PLC2
   4      1  SENSOR7
```

(Real extract: `fstats --mode=alarm tests/fixtures/alarms.log` — the six
levels are always displayed, even at zero.)

You can also target one specific tag: `--regex-tag='PLC[0-9]+'` extracts only
the `PLC…`. The mini-engine accepts the classes `[0-9]`, `[A-Z]`… and the
quantifiers `?` `*` `+` (it is not a complete regex, that is documented).

### Watching a log live (watch)

```
fstats --watch --interval=2 --log-level app.log
```

```
Watching: app.log (every 2s, Ctrl+C to stop)
[2026-11-23 19:55:44] lines=9 words=65 chars=540 sentences=7 | error=4 warn=1 info=4 none=0
[2026-11-23 19:55:46] lines=10 (+1) words=72 chars=584 sentences=7 | error=5 warn=1 info=4 none=0
```

Every 2 seconds, fstats re-analyzes the file and displays a summary with the
**delta** of lines since the last display (`+1` when a line has been added).
`Ctrl+C` stops cleanly (exit code 0). It only works on **one single file**
(not on stdin).

### Checking quality automatically (for CI)

`fstats` can play the role of a **guardrail**: checks against thresholds,
with exit codes that scripts can test.

```
fstats --check --fail-if max_line_length>25 test.txt
```

```
Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23

Checks
------
  max_line_length > 25 : FAIL (actual 30)
```

Here, the longest line is 30 characters: the `max_line_length > 25` check
fails and the command ends with exit code 2 (instead of 0). Since v2.16.0,
the console also ends with a **readable verdict** line
(`Verdict : ECHEC (...) - exit 2`) — no need to decipher the codes by hand.
Exit codes in check mode: **0** = all is well, **2** = at least one check
failed, **3** = only warnings (`--warn-if`), **1** = error (file not found,
invalid option).

To watch a corpus's **drift** over time, you capture a reference state then
compare:

```
fstats --summary-json docs/*.md > baseline.ndjson
fstats docs/*.md --compare baseline.ndjson --fail-on-delta lines>10
```

This second command fails (exit code 2) if a file **gains** more than 10%
of lines compared to the baseline (loss is not an anomaly: it is the
explosion that a CI gate must stop — a documented decision). The baseline
also contains the **SHA-256** of each file (v2.16.0): if a file's content
changes without moving its metrics, the `sha256` check still fails — no
way to disguise a drift.

---

## 5. How fstats counts things

### A "character"

fstats counts **Unicode characters** (called "code points"), in a file
encoded in **UTF-8**. Accents (`é`, `à`), accented letters and even
characters from other alphabets each count for one character. The tool
never cuts a character in two, even if the file is malformed.

### A "word" — and why it depends on the mode

The definition of a word can change depending on the chosen mode:

| Mode | Example with `simple.` | Effect |
|---|---|---|
| `raw` (default) | the word is `simple.` | the punctuation attached to the word is part of it |
| `ascii` | the word is `simple` | ASCII letters/digits only, punctuation removed |
| `unicode` | the word is `simple` | Unicode letters/digits (accents, Greek, Cyrillic…) |

So with the default mode, `fstats test.txt` counts `mots.` (with the period)
as a word. For "clean" words, use `--word-mode=ascii` or
`--word-mode=unicode`.

### A "sentence"

A sentence ends with `.`, `!`, `?` or `…` (ellipsis). If the file ends with
text without final punctuation, a last sentence is counted. Since v2.6.1, a
period **between two digits** (`3.14`) does not close a sentence: it is a
decimal. On the other hand, `Version 3. Fin.` does close after the `3.`
(the period is followed by a space).

Since v2.7.0, `--sentence-mode=smart` additionally protects abbreviations
(`M.`, `Dr.`, `etc.`…) and URLs (`https://…`):

```
fstats --sentence-mode=smart rapport.txt
```

`M. Dupont est là. Bravo.` then makes **2 sentences** instead of 3 in
`basic` mode (the `M.` no longer cuts). The list of recognized abbreviations
is frozen in the [technical specification](SEMANTIQUE.md).

### An "n-gram"

An n-gram is **n words that follow one another**:

- with `--ngrams=2`: the **bigrams** — for "Le chat dort" → `le chat`,
  `chat dort`;
- with `--ngrams=3`: the **trigrams** — `le chat dort`.

It is handy to spot the expressions that come back in a text. The windows do
not cross line breaks (each line produces its own n-grams).

### The quality counters

fstats also checks the file's "health":

| Counter | Detects |
|---|---|
| `invalid_utf8` | a broken encoding (replaced by the U+FFFD character) |
| `bom` | a UTF-8 BOM at the start of the file (an encoding marker) |
| `crlf` | the Windows `\r\n` line endings |
| `tabs` | tabs |
| `nonprintable` | control characters |

These counters do **not affect** the main statistics: they complete them
for diagnosis.

---

## 6. Concrete examples (with real outputs)

Let us take our small `test.txt` file again (3 lines, 13 words).

### a) A one-line JSON summary

```
fstats --summary-json test.txt
```

```
{"file": "test.txt", "sha256": "eba4cf176f51968df93145ec2c899db070580e96f3d55af0c4f4995fc781bb91", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0, "top_lines": [{"rank": 1, "count": 1, "line": "Deuxième phrase avec des mots."},{"rank": 2, "count": 1, "line": "Encore un test !"},{"rank": 3, "count": 1, "line": "Voici un exemple simple."}]}
```

Everything is on **one line**: ideal for processing many files with scripts.

### b) From the standard input

```
echo "un deux trois." | fstats - --summary-json
```

```
{"file": "stdin", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "lines": 1, "words": 3, "characters": 17, "sentences": 1, "avg_words_per_sentence": 3, "line_min": 15, "line_max": 15, "line_avg": 15, "invalid_utf8": 0, "bom": false, "crlf": 1, "tabs": 0, "nonprintable": 0, "top_lines": [{"rank": 1, "count": 1, "line": "un deux trois. "}]}
```

(Output captured under `cmd.exe`: `echo` there adds a CR at the end of the
line, hence `crlf: 1`, the 17 characters and the trailing space in `top_lines`.
The same `echo` under a POSIX shell produces no CR: `characters: 15`,
`crlf: 0`. The counters are true about what comes in — it is stdin that
differs.)

You can chain: `cat journal.log | fstats - --summary-json`.

### c) The most frequent bigrams

```
fstats --ngrams=2 --word-mode=ascii test.txt
```

```
N-grams (N=2)
-------------
   #  N-gram                       Count
   1  avec des                         1
   2  des mots                         1
   3  deuxi me                         1
   ...
```

Each pair of consecutive words is counted. Here, all the pairs appear only
once (small text). On a real corpus, the repeated expressions rise to the top.

> A small curiosity visible here: in `ascii` mode, "Deuxième" is split into
> `deuxi` + `me` (the `è` is not ASCII). With `--word-mode=unicode`, the
> word stays whole.

### d) A histogram

```
fstats --histogram=word_length --word-mode=ascii test.txt
```

```
Histogram (word_length)
-----------------------
  1-2    ### 3
  3-4    #### 4
  5-6    ##### 5
  7-8    # 1
  9-10    0
  11-12   0
  13+     0
```

Each `#` is worth one occurrence. At a glance, you see that the words are
mostly 1 to 6 characters long.

### e) Exporting for Excel

```
fstats --csv test.txt
```

```
file,type,rank,value,code_point,count,length
test.txt,summary,,lines,,3,
test.txt,summary,,words,,13,
test.txt,summary,,characters,,72,
...
```

One file per line, openable in any spreadsheet.

### f) The readability of a text

```
fstats --readability test.txt
```

```
Readability
-----------
  Avg sentence words:4.3333
  Avg word chars: 4.6154
  Pct long words:23.0769%
  Score (0-100): 76.6239
```

- **Avg sentence words**: on average, 4.3 words per sentence — short
  sentences, easy to follow.
- **Avg word chars**: 4.6 characters per word on average (punctuation
  included, default mode).
- **Pct long words**: 23% of the words are 7 characters or more
  (`exemple`, `simple.`, `Deuxième`).
- **Score (0-100)**: 76.6 out of 100 — a rather easy-to-read text.

The score is computed without syllables (formula documented in the
[technical specification](SEMANTIQUE.md)): it is not an exact Flesch-Kincaid,
but it lets you compare two versions of a text:

```
fstats --readability --summary-json test.txt
```

```
{"file": "test.txt", "sha256": "eba4cf176f51968df93145ec2c899db070580e96f3d55af0c4f4995fc781bb91", "tool": "fstats", "version": "2.16.2", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0, "avg_sentence_words": 4.333333, "avg_word_chars": 4.615385, "pct_long_words": 23.076923, "readability_score": 76.623932, "top_lines": [{"rank": 1, "count": 1, "line": "Deuxième phrase avec des mots."},{"rank": 2, "count": 1, "line": "Encore un test !"},{"rank": 3, "count": 1, "line": "Voici un exemple simple."}]}
```

> The `--word-mode=ascii` mode changes the words used: "Deuxième" becomes
> `deuxi` + `me` (the `è` is not ASCII), so `Avg word chars` and
> `Pct long words` change too (4.3077 and 7.6923% on this file).

---

## 7. The three output formats at a glance

| Format | When to use it |
|---|---|
| **Console** (default) | reading the results on screen; aligned sections, pure ASCII |
| **JSON** (`--json`, `--summary-json`) | processing the results with scripts / tools |
| **CSV** (`--csv`) | importing into a spreadsheet, making charts |

> **Security (v2.14.1)**: a log line starting with `=`, `+`, `-` or `@`
> could be interpreted as a **formula** by Excel or LibreOffice when opening
> it (a real attack vector). fstats prefixes these cells with an apostrophe
> to neutralize them: `"=cmd|..."` becomes `"'=cmd|..."`. If you see this
> apostrophe in an export, it is intentional.

The technical details of the schemas (exact fields, the `ndjson`/`array`/
`aggregate` modes, CSV `summary`/`words`/`chars`) are in the
[technical specification](SEMANTIQUE.md).

---

## 8. Errors and return codes

| Code | Meaning | Example |
|---|---|---|
| `0` | everything went well (or all the checks pass) | `fstats test.txt` |
| `1` | an error occurred | nonexistent file, unknown option, glob with no result… |
| `2` | check mode: at least one `--fail-if` failed | `fstats --check --fail-if lines>100 test.txt` |
| `3` | check mode: no failure, but at least one `--warn-if` triggered | `fstats --check --warn-if lines>2 test.txt` |

Errors are written to **stderr** with an explicit message, the normal output
(the data) to **stdout**: you can redirect one without the other.

---

## 9. Limits (stated honestly)

- **UTF-8 text files only**: no binary, no latin-1 encoding. A broken
  encoding is detected (`invalid_utf8`) and repaired with U+FFFD.
- The **BOM is not removed**: detected (`bom`) but kept in the data.
- In `raw` mode (default), the **punctuation attached to words** is part of
  them: for "clean" words, choose `--word-mode=ascii|unicode`.
- The Unicode case folding (`--casefold=unicode`) covers the common
  French/German accents, not all of Unicode.
- On **very large** corpora, the n-gram top is approximate (bounded memory);
  `--top-ngrams=0` lifts the limit at the cost of memory.
- A period **between two digits** (`3.14`) does not count as a sentence end
  (v2.6.1); a period after a digit followed by a space does.
- The `smart` mode (`--sentence-mode=smart`) only recognizes a **frozen
  list** of abbreviations and URLs with `://` — not every imaginable
  abbreviation.
- `--regex-tag` is a **mini-engine** (literal + classes `[0-9]`… +
  quantifiers `? * +`), not a complete regex. Since v2.15.0 it is
  **linear** (NFA): no pattern can make it freeze anymore, and from each
  position it keeps the longest match.
- Bounded **stored** line/word (v2.15.0): beyond 65,536 bytes for a line
  (1,024 for a word), only the matching, the Top Lines and the dictionaries
  see the truncated part — **the counters, for their part, remain exact**
  over the entire file. A match hidden past the bound (a 100 KB line) is
  not seen: an accepted-and-documented approximation against freezes/memory.
- A **zero-length** match (`--pattern='*'`) counts 0 occurrences, not
  infinitely many (v2.15.0).
- `--top-lines` / `--top-tags`: approximate top-K on very large logs
  (bounded memory, like the n-grams).
- Redaction (`--redact`) applies to the **outputs only**: the counters
  (`words`, `characters`…) are always computed on the raw text.
- `--watch` (v1) re-analyzes the **entire** file at each tick; it is not an
  incremental byte-by-byte tracking.

In 95% of cases — normal files, reasonably sized texts — the results are
exact and reliable.

---

## 10. Going further

- [README](../README.en.md) — overview, all the options, examples.
- [Technical specification](SEMANTIQUE.md) — frozen semantics of the
  counters, detailed JSON/CSV schemas.
- [Validation journal](VERIFICATION.md) — the verifications performed with
  their real outputs.
- [Roadmaps](ROADMAP-CIBLE2.md) / [ROADMAP-CIBLE3.md](ROADMAP-CIBLE3.md) —
  the features to come.
- The **automated tests** (`tests\run.bat` on Windows, `tests\run.sh` on
  Linux) verify that everything works after each modification.

Have fun exploring your texts!
