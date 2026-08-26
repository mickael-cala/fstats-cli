# fstats - journal de verification (sorties reelles)

> **Note (2026-08-26, post-restructuration)** : la compilation se fait depuis la
> racine : `fpc -O2 -Mobjfpc src\fstats.pas`.

Genere le : 2026-08-26 11:56 - executable : `fstats.exe` (`fstats 2.2.0`)
Perimetre : increment A de ROADMAP-CIBLE1.md (stdin, glob interne,
recursivite, JSON multi-fichiers valide NDJSON/array/aggregate, `--summary-json`,
compteurs qualite). Les compteurs historiques sont inchanges vs v2.1.

## 1. Compilation

`fpc -O2 -Mobjfpc fstats.pas` : exit=0
`2397 lines compiled, 0.9 sec, 318464 bytes code, 19460 bytes data`

## 2. Compteurs de reference (test_fr.txt) - inchanges vs v2.1

Attendu : lignes 3, mots 13, caracteres 72, phrases 3, moy. mots/phrase 4,
min/max/moy 16/30/23. Console (exit=0) :

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

Note : pas de section `Quality` pour un fichier propre - la sortie console des
fichiers propres est strictement identique a celle de la v2.1.

## 3. Codes de retour (stdout/stderr separes)

| Cas | Exit | stdout | stderr |
|---|---|---|---|
| Succes : fstats test_fr.txt | 0 | donnees | (vide) |
| Fichier manquant : fstats absent.txt | 1 | (vide) | `Erreur: Fichier inaccessible ou introuvable - ...` |
| Aucun argument : fstats | 1 | (vide) | usage |
| --help | 0 | usage | (vide) |
| --version | 0 | `fstats 2.2.0` | (vide) |
| stdin + fichier : fstats - test_fr.txt | 1 | (vide) | message d'erreur |
| Glob sans correspondance : fstats 'nope/**/*.xyz' | 1 | (vide) | message d'erreur (gate CI jamais vide) |
| Conflit : --json --csv --out=x | 1 | (vide) | `Erreur: avec --out, choisissez seulement --json ou --csv.` |

## 4. stdin

`echo "un deux trois." | fstats - --json` : exit=0, objet JSON valide (parse node),
`"file": "stdin"`, `words: 3`, `sentences: 1`.

## 5. JSON multi-fichiers : NDJSON (defaut v2.2.0, corrige la concat v2.1)

`fstats tests\fixtures\bom.txt tests\fixtures\crlf.txt --json` : exit=0, 2 lignes
JSON, chacune parsee individuellement par node :

- ligne 0 : `bom=true`, `crlf=0` (fichier avec BOM UTF-8)
- ligne 1 : `bom=false`, `crlf=2` (fichier avec 2 fins de ligne CRLF)

## 6. --json-mode=aggregate

`fstats tests\docs\**\*.md --json-mode=aggregate` : exit=0, 3 fichiers trouves
par le glob recursif (`tests\docs\readme.md`, `guide\api.md`, `guide\usage.md`),
totaux = somme exacte des statistiques :

```
totals: files=3 lines=9 words=21 characters=123 sentences=3
```

## 7. --summary-json

`fstats --summary-json test_fr.txt` : exit=0, objet plat JSON valide (parse node) :

```json
{"file": "test_fr.txt", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

## 8. Compteurs qualite (fixtures)

| Fixture | invalid_utf8 | bom | crlf | tabs | nonprintable |
|---|---|---|---|---|---|
| tests\fixtures\bom.txt | 0 | true | 0 | 0 | 0 |
| tests\fixtures\crlf.txt | 0 | false | 2 | 0 | 0 |
| tests\fixtures\tabs.txt | 0 | false | 0 | 2 | 0 |
| tests\fixtures\long-line.txt | 0 | false | 0 | 0 | 0 (line_max=177) |
| tests\fixtures\invalid-utf8.bin | 1 | false | 0 | 0 | 0 |

## 9. Sortie pipee : aucune sequence ANSI

Verification au niveau octet (recherche de ESC 0x1B) sur `fstats test_fr.txt`
pipe : aucune occurrence (attendu : aucune).

## 10. Suite de tests automatises

`tests\run.bat` (CMD, CI-friendly, sans Pause) : exit=0

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

`tests/run.sh` : equivalent bash (meme jeux de cas).

## Conclusion

Increment A (v2.2.0) satisfait tous les criteres d'acceptation de
ROADMAP-CIBLE1.md : compilation propre, compteurs historiques inchanges,
stdin, glob/recursivite internes, JSON multi-fichiers valide (NDJSON par defaut,
array/aggregate), --summary-json, compteurs qualite, codes de retour 0/1
conserves en mode analyse, sortie ASCII pure en pipe.
---

## Increment C2-A « Lexique » (v2.3.0) — 2026-08-26

Validation de l'implementation de `doc/ROADMAP-CIBLE2.md` (C2-A : --word-mode,
--casefold, --lexical-stats, --top-words/--top-chars, --max-unique, CSV v2).
Binaire compile depuis `src/fstats.pas` (mono-fichier, RTL FPC standard).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas` : exit=0

```
2795 lines compiled, 1.2 sec, 326416 bytes code, 19492 bytes data
```

### 2. Regression par defaut (test_fr.txt, inchange)

`fstats --summary-json tests/fixtures/test_fr.txt` : 3/13/72/3, moy 4,
min/max/moy 16/30/23, memes champs (pas de cle lexicale sans --lexical-stats) :

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.3.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. --word-mode=ascii (corpus_en.txt, golden)

`fstats --summary-json --word-mode=ascii tests/fixtures/corpus_en.txt` :
`"words": 11` (ponctuation retiree : "Hello," -> "Hello", "test." -> "test").

### 4. --word-mode=unicode (corpus_fr.txt, golden)

`fstats --summary-json --word-mode=unicode tests/fixtures/corpus_fr.txt` :
`"words": 19` (la ponctuation et les apostrophes separent ; les accents
restent dans les mots).

### 5. --casefold (corpus_fr.txt)

`fstats --summary-json --lexical-stats --casefold=unicode tests/fixtures/corpus_fr.txt` :
`words=20, unique_words=16` — "Été" et "été" fusionnent (table basique).

`--casefold=none` : `unique_words=17` (casse conservee, "Été" != "été").

### 6. --lexical-stats (JSON)

`fstats --json --lexical-stats tests/fixtures/test_fr.txt` (exit=0, JSON parse
node) : bloc additif `"lexical"` apres `quality`, cles existantes inchangees,
`schema_version` reste "1.0" :

```
"lexical": { "unique_words": 12, "hapax": 11, "type_token_ratio": 0.923077,
             "average_word_length": 4.615385, "entropy_bits_per_word": 3.546594 }
```

Controles node : TTR = types/tokens (12/13), entropie dans [0, log2(12)].
Console (section dediee, ASCII pur) :

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

`fstats --json --top-words=5 --top-chars=3 tests/fixtures/test_fr.txt` :
exactement 5 entrees `top_words` et 3 entrees `top_characters`.
`--top-words=0` : les 12 mots de test_fr.txt (0 = --all pour la section).

### 8. --max-unique (borne memoire)

`fstats --summary-json --lexical-stats --max-unique=5 tests/fixtures/test_fr.txt` :
`unique_words=5` (plafonne), `words=13` inchange, `average_word_length`
exact (accumule en streaming).

### 9. CSV v2 (rupture documentee)

En-tete exact et ligne summary avec colonne `file` :

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

`--csv=words` : meme en-tete, 10 lignes `word` (Top 10 par defaut) avec la
colonne `length` (code points). `--csv=chars` : colonne `code_point` remplie,
`length` = 1.

### 10. Options invalides et --version

`--word-mode=bogus` / `--max-unique=0` / `--csv=foo` : exit=1 + message
stderr francais. `fstats --version` : `fstats 2.3.0`.

### 11. Suites automatisees

`tests\run.bat` (CMD) : exit=0, 22/22 PASS. `tests/run.sh` (Git Bash) :
exit=0, 22/22 PASS — extraits :

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

### Bilan

C2-A satisfait les criteres de ROADMAP-CIBLE2.md : aucune regression en mode
par defaut (test_fr.txt 3/13/72/3, compteurs qualite, NDJSON/array/aggregate,
--summary-json, stdin, globs, exit codes 0/1, ASCII pur en pipe), nouvelles
options fonctionnelles et golden-teste, CSV v2 (rupture documentee) en place,
version 2.3.0. B et C (n-grams, histogrammes, lisibilite) restent a venir.
---

## Increment C2-B « Structure » (v2.4.0) — 2026-08-26

Validation de l'implementation de `doc/ROADMAP-CIBLE2.md` (C2-B : --ngrams,
--top-ngrams, --stopwords, --histogram, --char-classes, agregation).
Binaire compile depuis `src/fstats.pas` (mono-fichier, RTL FPC standard).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas` : exit=0

```
3577 lines compiled, 0.8 sec, 342128 bytes code, 19668 bytes data
```

### 2. Regression par defaut (test_fr.txt, inchange)

`fstats --summary-json tests/fixtures/test_fr.txt` : 3/13/72/3, moy 4,
min/max/moy 16/30/23, memes champs qu'en v2.3.0 sans les nouvelles options
(seule la version change) :

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. N-grams (goldens)

`fstats --json --ngrams=2 --word-mode=ascii tests/fixtures/corpus_en.txt` :
exactement **9 bigrammes** (comptes = 1), dont `hello world` ; le bigramme
traversant le saut de ligne `test one` est **absent** (les fenetres ne
traversent pas les lignes).

`fstats --json --ngrams=2 tests/fixtures/ngram_lines.txt` (fixture nouvelle
`alpha beta` / `gamma delta`) : **2 bigrammes** (`alpha beta`, `gamma delta`),
`beta gamma` **absent** — un bigramme n'apparaitrait que si les fenetres
traversaient le saut de ligne.

`fstats --json --ngrams=3 --top-ngrams=2 tests/fixtures/test_fr.txt` :
exactement **2 entrees** (top-K). `--ngrams=0` et `--ngrams=6` : exit=1 +
message stderr (`--ngrams attend un entier de 1 a 5`).

### 4. Stopwords

`fstats --json --ngrams=2 --top-ngrams=0 --stopwords=fr tests/fixtures/corpus_fr.txt` :
`words=20` (statistiques de mots inchangees) et **14 bigrammes** : `et`, `le`
et `Il` (casefold ascii -> `il`) sont retires du flux n-gram uniquement
(sans stopwords le fichier donne 16 bigrammes). Verifications : absence de
`et croissant,` et de `le garcon`, presence de `? est` (forme apres retrait
de `il`).

`--stopwords=fr` sans `--ngrams` : **ignore silencieusement** (exit=0, pas de
cle `ngrams` dans le JSON) — decision documentee au README.

### 5. Histogrammes (classes roadmap §6.6 + classes stables)

`fstats --json --histogram=line_length tests/fixtures/test_fr.txt` : classes
**identiques a l'exemple de la roadmap §6.6** `0-9, 10-19, 20-29, 30-39, 40+`,
comptes `0/1/1/1/0`, somme = lignes (3).

`--histogram=word_length` : classes stables `1-2, 3-4, 5-6, 7-8, 9-10, 11-12,
13+` (largueur 2), comptes `3/3/4/3/0/0/0`, somme = mots (13).

`--histogram=words_per_sentence` : classes stables `0-4, 5-9, 10-14, 15-19,
20+` (largueur 5, base 0), comptes `2/1/0/0/0`, somme = phrases (3).
Les formes a tirets de la roadmap (`--histogram=line-length`, `word-length`,
`words-per-sentence`) sont acceptees.

### 6. Char-classes (golden test_fr.txt)

`fstats --json --char-classes tests/fixtures/test_fr.txt` :

```
"char_classes": {"letters": 57, "digits": 0, "whitespace": 12,
                 "punctuation": 3, "control": 0, "other": 0}
```

Conservation : somme des six classes = 72 = `characters` (assertion de test).
Plages exactes documentees au README (« Semantique des classes de
caracteres »).

### 7. Agregation (--json-mode=aggregate)

`fstats tests\docs\**\*.md --json-mode=aggregate --char-classes --histogram=line_length` :
`char_classes` et `histogram` sommes classe par classe dans `totals` :

```
totals.char_classes: {"letters": 93, "digits": 0, "whitespace": 24,
                      "punctuation": 6, "control": 0, "other": 0}
totals.histogram: line_length ["0-9:3", "10-19:4", "20-29:2", "30-39:0", "40+:0"]
```

Les n-grams ne sont **pas** agreges (limitation documentee) : pas de cle
`ngrams` dans `totals`, ils restent par fichier dans `files`.

### 8. Options invalides et --version

`--ngrams=0` / `--ngrams=6` : exit=1 + message stderr. `--histogram=bogus` /
`--stopwords=bogus` : exit=1 + message stderr. `fstats --version` :
`fstats 2.4.0`.

### 9. Suites automatisees

`tests\run.bat` (CMD, exe racine via `-FE.`) : exit=0, **33/33 PASS**.
`tests/run.sh` (Git Bash, exe dans `src/`) : exit=0, **33/33 PASS** — extraits :

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

### Bilan

C2-B satisfait les criteres de ROADMAP-CIBLE2.md : aucune regression en mode
par defaut (les 22 cas v2.3.0 passent inchanges, version 2.4.0), n-grams
(goldens, non-traversee des lignes, top-K borne, stopwords fr/en), histogrammes
(classes roadmap §6.6 + classes stables documentees, somme = ligne/mots/phrases),
char-classes (conservation = characters, golden), agregation classe par classe,
exit codes 0/1, ASCII pur en pipe. C2-C (lisibilité, optionnel) livré en
v2.5.0 — voir section 10 ci-dessous.

---

## 10. Increment C2-C — lisibilite (v2.5.0)

Date : 2026-08-26. Ajout de `--readability` (4 metriques + score 0-100 sans
syllabes, formule figee dans SEMANTIQUE.md), bump `FSTATS_VERSION` 2.4.0 →
2.5.0, nouvelle fixture `tests/fixtures/empty.txt` (0 octet).

### 10.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (`3736 lines compiled`).

### 10.2 Valeurs de reference (test_fr.txt, mode raw par defaut)

Attendu (recalcul independant node) : ASL = 13/3 = 4.333333 ;
ALW = 60/13 = 4.615385 ; longs = 3 tokens >= 7 (`exemple`, `simple.`,
`Deuxieme`) = 23.076923% ; score =
100*(1-(0.5*min(4.333333/30,1)+0.5*min((4.615385-3)/5,1))) = 76.623932.

`fstats --readability --summary-json tests\fixtures\test_fr.txt` : exit=0,
`avg_sentence_words: 4.333333`, `avg_word_chars: 4.615385`,
`pct_long_words: 23.076923`, `readability_score: 76.623932` — verifie par
node (epsilon 0.001) sur les 4 valeurs.

Console : `Avg sentence words:4.3333 / Avg word chars: 4.6154 /
Pct long words:23.0769% / Score (0-100): 76.6239`.

`--word-mode=ascii` : `Avg word chars: 4.3077`, `Pct long words: 7.6923%`,
score 79.7009 (`Deuxieme` → `deuxi` + `me`).

### 10.3 Cas limites et combinaisons

- Fichier vide (`empty.txt`) : toutes les metriques a 0, score 0, aucun NaN
  (division par zero protegee).
- `--readability --json` : bloc `readability` avec les 4 cles.
- `--readability --lexical-stats` : blocs `lexical` ET `readability`
  presentes (clés plates en summary-json).
- `--readability --csv` : 4 lignes `summary,,avg_sentence_words/avg_word_chars/
  pct_long_words/readability_score,,<v>,`.
- `--json-mode=aggregate` : readability par fichier, PAS dans `totals`
  (comme les n-grams).
- Sortie pipee `--readability` : aucune sequence ANSI.

### 10.4 Suites automatisees

`tests\run.bat` : exit=0, **39/39 PASS**. `tests/run.sh` : exit=0, **39/39
PASS**. Les 33 cas precedents passent inchanges (aucune regression du mode
par defaut : test_fr.txt 3/13/72/3, moy 4, min/max/moy 16/30/23).

### Bilan

C2-C satisfait les criteres de ROADMAP-CIBLE2.md : metriques sur le mode
courant, formule exacte documentee et fgee, pas de Flesch-Kincaid exact
(mentionne au README), score borne [0,100], aucun NaN sur fichier vide,
additif en JSON/CSV, ASCII pur, 39/39 sur les deux suites. Cible 2
**complete**.

---

## 11. Cible 1 B+C — moteur de checks et baseline (v2.6.0)

Date : 2026-08-26. Ajout de `--check`, `--fail-if`, `--warn-if`, `--compare`,
`--fail-on-delta` (mode check, exit 0/1/2/3), bump `FSTATS_VERSION` 2.5.0 →
2.6.0. Alias `invalid_utf8` accepte en plus de `non_utf8` (nom JSON du
summary). Correction d'encodage de doc/ROADMAPFULL.md (mojibake -> UTF-8).

### 11.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (4906 lignes compilees,
362592 octets code). Warnings : uniquement generics.dictionaries (RTL, preexistants).

### 11.2 Exit codes (verifies par node spawnSync, exit reels)

| Commande | Exit | Statut |
|---|---|---|
| `--check --fail-if lines>2 test_fr.txt` (3 lignes) | 2 | FAIL (actual 3) |
| `--check --fail-if lines>5 test_fr.txt` | 0 | OK (actual 3) |
| `--check --warn-if lines>2 test_fr.txt` | 3 | WARN (actual 3) |
| `--check --fail-if lines>1 absent.txt` | 1 | erreur fatale (prime) |
| `--fail-if lines>5 test_fr.txt` (sans --check) | 0 | mode check implicite |
| `--check --fail-if lines>2 --json test_fr.txt` | 2 | `{"id":"lines","metric":"lines","actual":3,"op":">","threshold":2,"status":"fail"}` |

### 11.3 Baseline / derive

`--summary-json` capturee dans bl_test.json, puis `--compare bl_test.json
--fail-on-delta lines>10 test_fr.txt` : exit 0 (`delta lines > 10% : OK (delta
0%)`). Baseline modifie (`"lines": 3` -> `"lines": 1`) : exit 2 (`FAIL (delta
200%)`). `--fail-on-delta` sans `--compare` : exit 1 + stderr (`--fail-on-delta
exige --compare BASELINE`).

### 11.4 Dogfood CI (etape ajoutee a ci.yml, validee localement)

`fstats --check --fail-if non_utf8>0 --fail-if bom>0 --fail-if nonprintable>0
README.md doc\*.md src\fstats.pas` : exit 0, 10 fichiers analyses (commande
exacte du workflow, glob `doc\*.md` sous cmd).

### 11.5 Suites automatisees

`tests\run.bat` : exit=0, **56/56 PASS**. `tests/run.sh` : exit=0, **56/56
PASS**. Les 39 cas precedents passent inchanges (aucune regression du mode
par defaut : test_fr.txt 3/13/72/3).

### Bilan

Cible 1 **complete** (A v2.2.0, B+C v2.6.0) : moteur de checks (grammaire
figee, 10 metriques + alias, statuts ok/warn/fail, exit 0/1/2/3, mode analyse
non rompu), baseline NDJSON + derive en % (base=0 documentee), section
Checks console + bloc checks JSON (id stables), dogfood CI, 56/56 sur les
deux suites.

---

## 12. Correctif v2.6.1 — les decimales 3.14 ne cloturent plus une phrase

Date : 2026-08-26. Limite connue traitee : un point decimal (`3.14`) comptait
comme fin de phrase. Corrections : `FSTATS_VERSION` 2.6.0 → 2.6.1, logique de
cloture differee dans `AnalyzeData` (`DotPending`/`LastCP`, procedure imbriquee
`CloseSentence`), nouvelles fixtures `tests/fixtures/decimal.txt` et
`tests/fixtures/decimal_end.txt`, 3 nouveaux cas (57-59) dans les deux suites.

### 12.1 Regle figee (verifiee par node)

- `Le prix est 3.14 euros. Bravo !` → **2 phrases** (avant : 3), 7 mots.
- `Le prix est 3.14` (fin de flux) → **1 phrase** (avant : 2).
- `Version 3. Fin.` → **2 phrases** (le point apres `3` suivi d'un espace
  cloture toujours).
- `3 . 14. Fin.` → **3 phrases** (point entoure d'espaces = fin de phrase).
- `3.14. 5. Fin.` → **3 phrases** (point entre chiffres ignore, point final
  apres `4` cloture).
- Regression : test_fr.txt reste 3 phrases (3/13/72/3).
- Histogramme words_per_sentence : somme des classes = phrases (2 sur
decimal.txt).

### 12.2 Suites automatisees

`tests\run.bat` : exit=0, **59/59 PASS**. `tests/run.sh` : exit=0, **59/59
PASS**. Les 56 cas precedents passent inchanges.

### Bilan

Correctif verifie : aucun NaN, aucune regression, sémantique figee dans
SEMANTIQUE.md (point entre deux chiffres ≠ fin de phrase ; point apres
chiffre suivi d'un espace = fin de phrase ; point espace = fin de phrase).
La §6.3 du ROADMAPFULL (detection de phrases) est partiellement traitee :
decimales ok, abréviations/URLs hors perimetre.
