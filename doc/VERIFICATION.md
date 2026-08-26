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
