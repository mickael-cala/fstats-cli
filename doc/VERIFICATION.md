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