# CHANGELOG — fstats

Toutes les versions notables de `fstats`, de la plus récente à la plus ancienne.
Format inspiré de [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/).
Les preuves (sorties réelles, tests) sont dans [doc/VERIFICATION.md](doc/VERIFICATION.md).

---

## [2.12.0] — 2026-11-23 — Split interne en unités (comportement inchangé)

### Modifié
- `src/fstats.pas` (6 795 lignes, mono-fichier) éclaté en **8 unités à plat**
  dans `src/` — même binaire, zéro dépendance ajoutée, commande de
  compilation inchangée (`fpc -O2 -Mobjfpc src\fstats.pas`) :
  - `fstats_types.pas`    : constantes, globales, types (`TStats`, options…)
  - `fstats_utf8.pas`     : UTF-8, `VisualChar`, tris, couleurs ANSI, `FormatFloatTrim`
  - `fstats_glob.pas`     : moteur de glob interne (`*`, `**`, `?`), `--recursive`
  - `fstats_lex.pas`      : tokenisation, n-grams, patterns/redaction, log-level, regex-tag
  - `fstats_analyzer.pas` : `AnalyzeData/File/Stdin`, `WatchFile` (C3-D), handlers Ctrl+C
  - `fstats_checks.pas`   : moteur de checks, baseline NDJSON, `--compare`/`--fail-on-delta`
  - `fstats_output.pas`   : stats lexicales/lisibilité, console, JSON, CSV, usage
  - `fstats.pas`          : programme principal seul (parsing CLI, orchestration)
- `FormatFloatTrim` remonté dans `fstats_utf8` pour éviter une dépendance
  circulaire `checks` ↔ `output`.

### Vérifié
- Parité avec le binaire mono-fichier v2.11.0 : **50 commandes** comparées,
  sortie + exit code identiques (golden `test_fr.txt` 3/13/72/3, JSON
  ndjson/array/aggregate, `--summary-json`, CSV, glob, `--recursive`,
  `--watch`, `--mode=alarm`, `--redact`, `--log-level`/`--filter`,
  `--regex-tag`, checks + baseline `--compare`/`--fail-on-delta`, `--stdin`,
  `--help`, cas d'erreur).
- Empreinte binaire identique : 394 272 octets de code, 19 828 octets de données.
- `--version` = `fstats 2.12.0`.

---

## [2.11.0] — 2026-11-23 — Cible 3-D : watch

### Ajouté
- `--watch` / `--follow` : surveillance périodique d'un fichier log (polling),
  résumé ASCII toutes les `--interval` secondes jusqu'au Ctrl+C (exit 0).
- `--interval=N` : période du watch en secondes (défaut 2, min 1).
- Handler Ctrl+C cross-plateforme (Windows `SetConsoleCtrlHandler`, Linux
  `FpSignal` SIGINT/SIGTERM) → arrêt propre.
- Affichage du delta de lignes entre deux ticks (`+N`), marqueur `[TRUNCATED]`
  si le fichier a rétréci, niveaux si `--log-level`.
- Watch restreint à UN fichier (stdin et multi-fichiers → exit 1).
- **Cible 3 (Log Sentinel) complète.** 100 tests d'acceptation.

### Limité (documenté)
- v1 du watch : ré-analyse complète du fichier à chaque tick (pas
  d'incrémental octet à octet).

---

## [2.10.0] — 2026-11-23 — Cible 3-C : alarm / tags

### Ajouté
- `--regex-tag=PATTERN` : mini-moteur regex subset (littéraux + classes
  `[...]` + quantifieurs `?` `*` `+`) pour extraire et compter les tags
  (ex. `PLC[0-9]+` → `PLC1`, `PLC23`). Occurrences non chevauchantes.
- `--top-tags=N` : borne du top des tags (défaut 10, 0 = tous, mémoire bornée).
- `--mode=alarm` : raccourci SCADA/PLC = `--log-level` + `--top-lines` +
  `--regex-tag` (pattern défaut `[A-Z]+[0-9]+` : `PLC1`, `TAG007`…).
- Exports : section console `Tags`, bloc JSON `tags`, clé plate
  `--summary-json`, lignes CSV `type=tag`. 97 tests.

---

## [2.9.0] — 2026-11-23 — Cible 3-B : niveaux de log + filtre

### Ajouté
- `--log-level` : compte les lignes par niveau (`ERROR` > `WARN` > `INFO` >
  `DEBUG` > `TRACE`, mot entier insensible à la casse, n'importe où dans la
  ligne) + `none`. Somme des 6 = `lines`.
- `--filter=error,warn,...` : filtre l'affichage console des lignes
  (`Top Lines`, `Longest Lines`) avec renumérotation des rangs ; les compteurs
  globaux restent sur tout le fichier.
- Exports : section console `Log Levels`, bloc JSON `log_levels`, clé plate
  `--summary-json`, lignes CSV `type=loglevel`. 90 tests.

---

## [2.8.0] — 2026-11-23 — Cible 3-A : patterns, top-lines, redaction

### Ajouté
- `--pattern=TEXTE` (répétable) : comptage d'occurrences par ligne, matcher
  interne littéral + `|` (alternance) + `*`/`?` (wildcards), insensible à la
  casse, occurrences non chevauchantes. Bloc JSON `patterns`.
- `--top-lines=N` : top-N des lignes identiques (mémoire bornée comme les
  n-grams). Bloc JSON `top_lines`.
- `--redact=email,ipv4,url` : remplace par `***` dans les sorties seulement ;
  les compteurs restent sur le texte brut. 82 tests.

---

## [2.7.0] — 2026-08-26 — `--sentence-mode=basic|smart`

### Ajouté
- `--sentence-mode=smart` : en plus du mode `basic`, le point `.` est avalé
  pour une liste figée d'abréviations fr/en (`M.`, `Dr.`, `etc.`, `e.g.`…)
  et les URLs (`://` dans la fenêtre des 8 derniers caractères).
- `!` `?` `…` clôturent toujours. 67 tests.

---

## [2.6.1] — 2026-08-26 — correctif décimales

### Corrigé
- Un point **entre deux chiffres** (`3.14`) ne clôture plus une phrase.
  Un point après un chiffre suivi d'un espace (`Version 3.`) clôture toujours.
  59 tests.

---

## [2.6.0] — 2026-08-26 — Cible 1 B+C : moteur de checks et baseline

### Ajouté
- `--check`, `--fail-if=METRIQUE OP SEUIL`, `--warn-if=...` (10 métriques,
  opérateurs `> >= < <= = !=`, seuils décimaux).
- `--compare=BASELINE` (NDJSON `--summary-json`) + `--fail-on-delta=METRIQUE>X%`.
- Exit codes **0/1/2/3** en mode check (2 = fail, 3 = warn) ; mode analyse
  inchangé (0/1). Section `Checks` console + bloc JSON `checks`. Dogfood CI.
  56 tests.

---

## [2.5.0] — 2026-08-26 — C2-C : lisibilité

### Ajouté
- `--readability` : 4 métriques (`avg_sentence_words`, `avg_word_chars`,
  `pct_long_words`, score 0-100) **sans syllabes** (approximation inspirée de
  Flesch, formule figée dans SEMANTIQUE.md). 39 tests.

---

## [2.4.0] — 2026-08-26 — C2-B : structure

### Ajouté
- `--ngrams=N` (1..5), `--top-ngrams=K`, `--stopwords=fr|en|none` (fenêtres par
  ligne, top-K borné).
- `--histogram=line_length|word_length|words_per_sentence` (barres ASCII).
- `--char-classes` (6 classes, somme = `characters`).
- Agrégation classe par classe en `--json-mode=aggregate`. 33 tests.

---

## [2.3.0] — 2026-08-26 — C2-A : lexique

### Ajouté
- `--word-mode=raw|ascii|unicode`, `--casefold=ascii|unicode|none`.
- `--lexical-stats` : `unique_words`, `hapax`, `type_token_ratio`,
  `average_word_length`, `entropy_bits_per_word`.
- `--top-words=N`, `--top-chars=N`, `--max-unique=N` (borne mémoire, défaut 100 000).
- **CSV v2** (rupture documentée) : en-tête `file,type,rank,value,code_point,count,length`,
  sous-formats `summary|words|chars`. 22 tests.

---

## [2.2.0] — 2026-08-26 — Incrément A : robustesse et pipelines

### Ajouté
- Entrée standard `-` / `--stdin` (non mélangeable avec des fichiers).
- Glob interne (`*`, `**`, `?`) + `--recursive=DIR`, `--include`, `--exclude`,
  `--max-depth=N`.
- JSON multi-fichiers valide : NDJSON par défaut, `--json-mode=array|aggregate`.
- `--summary-json` (objet plat par fichier, prêt pour `jq`).
- Compteurs qualité : `invalid_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`.
- Sortie console ASCII pur garantie en pipe (aucun ANSI). 12 tests.

---

## Versions antérieures (v2.1 et avant)

- v2.1 : analyse de base (lignes, mots, caractères, phrases, top caractères/
  mots/lignes), export JSON/CSV v1, console alignée.
- v2.0 : première version publique (compteurs de base + JSON).
