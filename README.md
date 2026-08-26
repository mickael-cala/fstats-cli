# fstats — analyseur statistique de fichiers texte

[![CI](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml)
[![Licence MIT](https://img.shields.io/badge/Licence-MIT-blue.svg)](LICENSE)

Version 2.4.0 · Free Pascal (mode objfpc) · MIT

`fstats` analyse un ou plusieurs fichiers texte et compte les **caractères** (code
points UTF-8), **mots**, **lignes** et **phrases**, avec export **JSON**/**CSV**,
des **compteurs qualité** (UTF-8 invalide, BOM, CRLF, tabulations, caractères de
contrôle) et une résolution de **globs interne** (`*`, `**`, `?`) pour les shells
qui n'expandent pas les motifs (CMD, PowerShell).
En option (v2.3.0), une **analyse lexicale** : modes de tokenisation
(`--word-mode`), repli de casse (`--casefold`), statistiques de vocabulaire
(`--lexical-stats` : mots uniques, hapax, TTR, longueur moyenne, entropie),
limites Top configurables et CSV v2.
En option (v2.4.0), une **analyse structure** : n-grams sur les mots du mode
courant (`--ngrams`, `--top-ngrams`, `--stopwords`), histogrammes ASCII
(`--histogram` : longueur de ligne, longueur de mot, mots par phrase) et
classes de caractères (`--char-classes`).
La sortie console est compacte, alignée, en **ASCII pur** : conçue pour le
terminal et les scripts (aucune séquence ANSI par défaut, redirection sûre).
L'encodage de sortie est **UTF-8 déterministe**, y compris redirigé vers un
fichier ou un pipe (code page console forcé à UTF-8 au démarrage).

## Compilation / Démarrage rapide

Depuis la racine du dépôt :

```
fpc -O2 -Mobjfpc -FE. src\fstats.pas
```

ou via `wbld.bat` (Windows, avec `Pause` en fin de compilation). L'exécutable
`fstats.exe` est produit à la racine du dépôt. `wclr.bat` supprime les artefacts
de compilation (`*.o`, `*.ppu`, `*.exe`, y compris dans `src\`).

## Utilisation

```
fstats [options] <fichier|glob|-> [fichier2 ...]
```

### Entrées

| Option              | Effet                                                        |
|---------------------|--------------------------------------------------------------|
| `-`, `--stdin`      | Analyse l'entrée standard en UTF-8 (non mélangeable avec des fichiers) |
| `*.txt`, `**/*.md`  | Patterns glob résolus **en interne** (les shells Windows n'expandent pas les globs) |
| `--recursive=DIR`   | Parcourt l'arbre de DIR (répétable)                          |
| `--include=GLOB`    | Filtre d'inclusion pour `--recursive` (répétable)            |
| `--exclude=GLOB`    | Filtre d'exclusion pour `--recursive` (répétable)            |
| `--max-depth=N`     | Profondeur maximale du parcours (0 = racine seule)           |

### Affichage

| Option         | Effet                                                        |
|----------------|--------------------------------------------------------------|
| `--char`       | Section « Top Characters » uniquement                        |
| `--word`       | Section « Top Words » uniquement                             |
| `--line`       | Section « Longest Lines » uniquement                         |
| `--all`        | Toutes les données (pas de limite Top 10)                    |

### Analyse lexicale (v2.3.0)

| Option            | Effet                                                        |
|-------------------|--------------------------------------------------------------|
| `--word-mode=M`   | Tokenisation des mots : `raw` (défaut, historique) \| `ascii` \| `unicode` |
| `--casefold=M`    | Repli de casse : `ascii` (défaut) \| `unicode` \| `none`     |
| `--lexical-stats` | Ajoute `unique_words`, `hapax`, `type_token_ratio`, `average_word_length`, `entropy_bits_per_word` (console + JSON) |
| `--top-words=N`   | Limite de la section mots (défaut 10 ; `0` = tous)           |
| `--top-chars=N`   | Limite de la section caractères (défaut 10 ; `0` = tous)     |
| `--max-unique=N`  | Borne mémoire du nombre de mots uniques stockés (défaut 100 000) |

Sémantique figée : voir « [Sémantique lexicale](#sémantique-lexicale-v230) ».

### Structure (v2.4.0)

| Option              | Effet                                                        |
|---------------------|--------------------------------------------------------------|
| `--ngrams=N`        | N-grams sur les mots du mode courant (`--word-mode` + `--casefold`), N = 1..5 ; fenêtres **par ligne** (ne traversent pas les sauts de ligne) |
| `--top-ngrams=K`    | Limite top-K des n-grams (défaut 10 ; `0` = tous, mémoire non bornée) |
| `--stopwords=L`     | `fr` \| `en` \| `none` (défaut) : retire les mots vides du flux n-gram **uniquement** (les statistiques de mots existantes ne sont pas affectées) ; sans `--ngrams`, l'option est **ignorée silencieusement** |
| `--histogram=M`     | `line_length` \| `word_length` \| `words_per_sentence` (barres ASCII, classes documentées ci-dessous ; les formes à tirets `line-length`, `word-length`, `words-per-sentence` de la roadmap sont aussi acceptées) |
| `--char-classes`    | Classe chaque code point **une seule fois** dans `letters` \| `digits` \| `whitespace` \| `punctuation` \| `control` \| `other` (somme = `characters`) |

Sémantique figée : voir « [Sémantique structure (v2.4.0)](#sémantique-structure-v240) ».

### Exports

| Option                | Effet                                                        |
|-----------------------|--------------------------------------------------------------|
| `--json`              | Export JSON (stdout ou `--out=`) : 1 fichier = objet unique ; plusieurs = NDJSON (1 objet par ligne) |
| `--json-mode=MODE`    | `ndjson` \| `array` \| `aggregate` (implique `--json`)       |
| `--summary-json`      | Objet JSON **plat** par fichier (scripts/jq)                 |
| `--csv[=MODE]`        | Export CSV v2 : `summary` (défaut) \| `words` \| `chars` (stdout ou `--out=`) |
| `--out=FICHIER`       | Redirige la sortie vers un fichier                           |
| `--quiet`             | Pas de confirmation console avec `--out`                     |

### Divers

| Option          | Effet                                                        |
|-----------------|--------------------------------------------------------------|
| `--color`       | Coloriage minimal des titres (console uniquement)            |
| `--no-color`    | Pas de couleur (défaut)                                       |
| `--version`     | Affiche la version et quitte                                 |
| `--help`, `-h`  | Affiche l'aide et quitte                                     |

### Exemples

```
fstats examples\demo.obm
fstats --json --out=stats.json examples\demo.obm
fstats --csv=words --all rapport.txt
fstats --word --line examples\demo.obm
fstats --recursive=docs --include='**/*.md' --summary-json
fstats --recursive=src --exclude='**/vendor/**' --json-mode=aggregate
echo "un deux trois." | fstats - --json
fstats 'tests/**/*.md' --json-mode=array
fstats tests\fixtures\test_fr.txt
fstats --word-mode=ascii --top-words=20 --lexical-stats corpus.txt
fstats --casefold=unicode --lexical-stats --json corpus_fr.txt
fstats --csv=words --top-words=50 rapport.txt
fstats --ngrams=3 --top-ngrams=20 --word-mode=ascii corpus.txt
fstats --ngrams=2 --stopwords=fr corpus_fr.txt
fstats --histogram=line_length --histogram=word_length rapport.txt
fstats --char-classes --json corpus.txt
fstats --help
```

### Codes de retour

| Code | Signification                                                      |
|------|--------------------------------------------------------------------|
| 0    | Succès (au moins un fichier analysé sans erreur)                   |
| 1    | Erreur : fichier manquant/introuvable, glob sans correspondance, option invalide, sortie inécrivable, stdin mélangé avec des fichiers, aucun fichier fourni… |

### Flux de sortie

- **stdout** : les données (console alignée, JSON ou CSV).
- **stderr** : erreurs, avertissements, et confirmation d'écriture avec `--out`.
- Le fichier `--out` ne contient jamais de code ANSI ni de message console.
- L'encodage de sortie est UTF-8 (déterministe) : la console Windows est forcée
  en code page 65001 et les flux texte `stdout`/`stderr` écrivent sans
  conversion, même redirigés vers un fichier ou un pipe.

## Formats de sortie

### Console

```
File: examples\demo.obm
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

`Summary` est toujours affiché ; la section **Quality** n'apparaît que si au
moins un compteur qualité est non nul (ou BOM présent) — la sortie des fichiers
« propres » est donc strictement identique à celle de la v2.1. La section
**Lexical** n'apparaît qu'avec `--lexical-stats`. Les trois sections Top sont
filtrées par `--char`/`--word`/`--line`. Le suffixe `(N of K)` n'apparaît que
si le total réel dépasse la limite affichée (`--top-words`/`--top-chars`/`--all`).

Console avec `--lexical-stats` (section dédiée, ASCII pur) :

```
Lexical
-------
  Unique words:       16
  Hapax:              12
  Type-token ratio: 0.8
  Avg word length:  3.75
  Entropy:        3.9219
```

Console avec `--ngrams=2 --histogram=line_length --char-classes` (sections
C2-B dédiées, ASCII pur) :

```
N-grams (N=2)
-------------
   #  N-gram                       Count
   1  avec des                         1
   2  des mots.                        1
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

Les sections `N-grams`, `Histogram` et `Character Classes` s'ajoutent quand
leurs options sont activées, **indépendamment** de `--char`/`--word`/`--line`.

### JSON

Tous les exports JSON portent les champs de traçabilité `tool` (`"fstats"`),
`version` et `schema_version` (`"1.0"`), en plus de `generated`.

**1 fichier + `--json` → objet unique (format « pretty ») :**

```json
{
  "file": "tests/fixtures/test_fr.txt",
  "generated": "2026-08-26 11:38:35",
  "tool": "fstats",
  "version": "2.4.0",
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

Avec `--lexical-stats`, un bloc **additif** `"lexical"` est inséré après
`quality` (les clés existantes sont inchangées, `schema_version` reste `"1.0"`) :

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

**Plusieurs fichiers + `--json` → NDJSON (défaut, 1 objet compact par ligne) :**

```
{"file": "tests\/fixtures\/bom.txt", "generated": "...", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": true, "crlf": 0, "tabs": 0, "nonprintable": 0}, ...}
{"file": "tests\/fixtures\/crlf.txt", "generated": "...", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": false, "crlf": 2, "tabs": 0, "nonprintable": 0}, ...}
```

Le JSON multi-fichiers **n'est plus concaténé** (défaut v2.1 corrigé) : chaque
ligne est un objet JSON complet et indépendant, validable ligne à ligne
(`JSON.parse` par ligne, `jq -c`…).

**`--json-mode=array` → tableau JSON :**

```json
[
  { "file": "tests\/fixtures\/bom.txt", "...": "...", "quality": { "...", "bom": true } },
  { "file": "tests\/fixtures\/crlf.txt", "...": "...", "quality": { "...", "crlf": 2 } }
]
```

**`--json-mode=aggregate` → objet global avec totaux :**

```json
{
  "tool": "fstats",
  "version": "2.4.0",
  "schema_version": "1.0",
  "generated": "2026-08-26 11:38:40",
  "files": [ { "file": "tests\/docs\/guide\/api.md", "...": "..." } ],
  "totals": { "files": 3, "lines": 9, "words": 21, "characters": 123, "sentences": 3 }
}
```

Les totaux sont la somme exacte des statistiques des fichiers listés.

**`--summary-json` → objet plat par fichier (un par ligne, prêt pour jq) :**

```
{"file": "tests/fixtures/test_fr.txt", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

Avec `--lexical-stats`, `--summary-json` ajoute (toujours à plat) les clés
`unique_words`, `hapax`, `type_token_ratio`, `average_word_length` et
`entropy_bits_per_word` en fin d'objet.

### CSV

**CSV v2 (v2.3.0)** — en-tête fixe : `file,type,rank,value,code_point,count,length`.

> ⚠️ **Rupture documentée** (assumée, faite en C2-A) : le format v1
> (`metric,rank,value,code_point,count` avec lignes `character`/`word`/`line`
> mélangées puis un résumé `sentence_count`/`source_file`/`generated`) est
> **remplacé**. Les valeurs calculées restent strictement identiques ; seules
> la structure et les colonnes changent.

Trois sous-formats (`--csv` seul = `summary`) :

| Sous-format | Contenu | Colonnes remplies |
|---|---|---|
| `--csv=summary` | Une ligne par métrique (`value` = nom, `count` = valeur) | `file`, `type=summary`, `value`, `count` |
| `--csv=words` | Top mots (`rank`, `value` = mot, `count` = fréquence, `length` = code points) | toutes |
| `--csv=chars` | Top caractères (`rank`, `value` = caractère, `code_point` = U+XXXX, `count`, `length` = 1) | toutes |

Exemple `--csv` (summary, métriques du fichier) :

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

Avec `--lexical-stats`, les lignes `unique_words`, `hapax`,
`type_token_ratio`, `average_word_length` et `entropy_bits_per_word` sont
ajoutées en fin de liste. Exemple `--csv=words` (Top 10 par défaut) :

```
file,type,rank,value,code_point,count,length
tests/fixtures/test_fr.txt,word,1,un,,2,2
tests/fixtures/test_fr.txt,word,2,phrase,,1,6
...
```

La limite Top suit `--top-words`/`--top-chars` (ou `--all`) ; `file` donne la
traçabilité (l'horodatage `generated` du format v1 est retiré).

## Compteurs qualité (à lire)

Les compteurs qualité **n'affectent pas** les métriques existantes (caractères,
mots, lignes, phrases) : ils les complètent pour le diagnostic d'hygiène de
fichier. Ils sont exposés dans la section console `Quality`, dans le bloc JSON
`quality`, et à plat dans `--summary-json`.

- **invalid_utf8** : nombre de **séquences UTF-8 invalides** : octet de tête
  invalide, octet de continuation manquant ou incorrect, sur-encodage, plages
  réservées (U+D800–U+DFFF), hors plage Unicode (U+10FFFF). Chaque séquence
  invalide est remplacée par U+FFFD et comptée pour **1** ; le caractère de
  remplacement compte dans les caractères mais agit comme **séparateur de mots**
  (il ne fait jamais partie d'un mot).
- **bom** : booléen ; **vrai si U+FEFF est le tout premier caractère du flux**.
  Le BOM n'est **pas retiré** du contenu : il reste compté comme un caractère
  (lignes, mots, longueurs) et est préservé tel quel dans les exports (octets
  UTF-8 `EF BB BF` ; son rendu console dépend du terminal).
- **crlf** : nombre de **fins de ligne CRLF** (CR immédiatement suivi de LF).
  Un LF seul ou un CR seul compte comme fin de ligne ordinaire **sans**
  incrémenter ce compteur.
- **tabs** : nombre de **tabulations** (U+0009), où qu'elles se trouvent.
- **nonprintable** : nombre de **caractères de contrôle** (U+0000–U+001F et
  U+007F) **hors** LF (U+000A), CR (U+000D) et TAB (U+0009) — ces trois-là étant
  déjà suivis par leurs propres compteurs (lignes/CRLF/tabs).

Exemple : `tests/fixtures/crlf.txt` (2 fins de ligne CRLF) donne
`crlf = 2`, `tabs = 0`, `nonprintable = 0` ; `tests/fixtures/tabs.txt` donne
`tabs = 2` ; `tests/fixtures/invalid-utf8.bin` donne `invalid_utf8 = 1`.

## Sémantique des compteurs (à lire)

- **Caractères** : code points Unicode décodés en UTF-8 strict ; les sauts de
  ligne comptent comme des caractères.
- **Mots** : par défaut (`--word-mode=raw`), suites de caractères de code point
  > `0x20` (espace et caractères de contrôle = séparateurs). Conséquence : la
  ponctuation collée à un mot en fait partie (`simple.`), et une ponctuation
  isolée (`!`) compte comme un mot. Les modes `ascii`/`unicode` retirent la
  ponctuation (voir « Sémantique lexicale »).
- **Phrases** : clôturées par `.`, `!`, `?` ou `…` (U+2026) ; si le fichier se
  termine avec du contenu non blanc après le dernier terminateur, une phrase
  finale supplémentaire est comptée. Un point décimal (`3.14`) clôture donc une
  phrase (limite documentée).
- **Lignes** : terminées par LF, CR ou CRLF ; la longueur est en caractères,
  sans le saut de ligne ; min/max/moyenne portent sur les lignes non vides.
- Les mots ASCII sont normalisés en minuscules (fréquences insensibles à la
  casse pour l'ASCII ; l'Unicode non-ASCII est conservé tel quel) — comportement
  modifiable avec `--casefold` (voir « Sémantique lexicale »).

## Sémantique lexicale (v2.3.0)

### Définition d'un mot (`--word-mode`)

| Mode | Définition du mot (figée) | Séparateurs |
|---|---|---|
| `raw` (défaut) | code point > `0x20` et ≠ U+FFFD (historique, ponctuation incluse) | espaces, contrôles, U+FFFD |
| `ascii` | suite de `[A-Za-z0-9_]` | tout le reste (ponctuation, accents…) |
| `unicode` | suite de **lettres/chiffres Unicode** du périmètre ci-dessous | tout le reste (ponctuation, symboles…) |

Périmètre `unicode` (documenté, sans bibliothèque Unicode complète) :
chiffres ASCII ; lettres ASCII ; Latin-1 (hors `×` U+00D7 et `÷` U+00F7) ;
Latin étendu A/B (U+0100–U+024F) ; API (U+0250–U+02AF) ; marques combinantes
(U+0300–U+036F, restent attachées à la lettre) ; grec (U+0370–U+03FF, hors
point-virgule grec U+037E) ; cyrillique (U+0400–U+04FF) ; latin étendu
additionnel (U+1E00–U+1EFF) ; chiffres arabo-indiens (U+0660–U+0669) et arabes
étendus (U+06F0–U+06F9).

### Repli de casse (`--casefold`)

| Mode | Comportement (figé) |
|---|---|
| `ascii` (défaut) | `A-Z` → `a-z` uniquement (historique) |
| `unicode` | `ascii` + table basique limitée : Latin-1 accentués `À..Þ` → `à..þ` (U+00C0–U+00D6, U+00D8–U+00DE, `+0x20`), `Œ`→`œ`, `Ÿ`→`ÿ`, `ẞ`→`ß` |
| `none` | casse conservée (aucun repli) |

Périmètre assumé : **pas** de case folding Unicode complet (limite RTL FPC) —
la table couvre les accents français/allemand courants, documentée telle
quelle. Exemple : avec `--casefold=unicode`, `Été` et `été` deviennent le même
type ; avec `--casefold=none` ils restent distincts.

### Métriques `--lexical-stats`

Formules figées (mode courant = tokenisation + repli actifs) :

- `unique_words` : nombre de **types** de mots (distincts) du mode courant ;
  plafonné par `--max-unique` le cas échéant (voir ci-dessous).
- `hapax` : nombre de types à fréquence **exactement 1**.
- `type_token_ratio` : `unique_words / words` (types ÷ tokens du mode courant).
- `average_word_length` : longueur moyenne des tokens en **code points**
  (somme des longueurs de tous les tokens ÷ `words`), indépendante de
  `--max-unique` (accumulée en streaming).
- `entropy_bits_per_word` : `-Σ pᵢ log₂ pᵢ` (en bits) sur les types du mode
  courant, avec `pᵢ = countᵢ / words`. Bornée par `[0, log₂(unique_words)]`.

Présence : console (section `Lexical`), JSON (`"lexical": {...}` dans les
objets complet/compact ; clés plates en fin d'objet pour `--summary-json`) et
CSV summary. Ajout **additif** : sans `--lexical-stats`, les clés existantes
sont strictement inchangées (`schema_version` reste `"1.0"`).

### `--max-unique` (borne mémoire)

Défaut 100 000. Tant que le nombre de types stockés est `< N`, chaque nouveau
mot est ajouté ; au-delà, **on cesse d'ajouter de nouveaux types** : les mots
connus continuent d'accumuler leurs fréquences, mais les nouveaux types sont
ignorés pour le vocabulaire. Sémantique documentée : `unique_words` est
**plafonné à N et non exhaustif** ; `hapax`/`type_token_ratio`/`entropie`
portent alors sur le jeu de types stockés. `words` (tokens) et
`average_word_length` restent exacts (comptés en streaming).

## Sémantique structure (v2.4.0)

### N-grams (`--ngrams`)

- **Définition (figée)** : les n-grams sont des fenêtres glissantes de N mots
  (1 ≤ N ≤ 5) sur les **mots du mode courant** — la tokenisation
  (`--word-mode`) et le repli de casse (`--casefold`) actifs sont appliqués,
  cohérent avec `--lexical-stats`.
- **Non-traversée des lignes** : chaque ligne produit ses propres fenêtres ; un
  saut de ligne « casse » le flux (aucun n-gram ne chevauche deux lignes).
- **Top-K (mémoire bornée)** : seuls les `--top-ngrams=K` les plus fréquents
  sont conservés (défaut 10, `0` = tous). Mémoire bornée par un **top-K
  sketch** : quand le dictionnaire des n-grams dépasse `max(8×K, 64)` entrées,
  il est réduit au top-K. Conséquence documentée : sur un très gros corpus, un
  n-gram rare écarté en cours de route peut manquer dans le top final (les
  comptes des n-grams conservés restent exacts). Sur les corpus de test, le
  résultat est exact.
- **JSON** : clé additif `"ngrams": [{"rank": r, "words": [...mots...], "count":
  c}, ...]` (tableau de mots). Console : section « N-grams (N=…) » avec rang,
  n-gram (mots séparés par un espace) et compte.
- **Validation** : `--ngrams=0` ou `--ngrams>5` → erreur fatale (exit 1).
  `--stopwords` et `--top-ngrams` **sans** `--ngrams` sont **ignorés
  silencieusement** (aucun effet, exit 0) — cohérent avec `--include`/
  `--exclude` sans `--recursive`.

### Mots vides (`--stopwords`)

Les mots vides sont retirés **du flux de tokens utilisé pour les n-grams
uniquement** : les statistiques de mots existantes (`words`, top words,
`--lexical-stats`, histogramme `word_length`…) ne sont **pas** affectées.
Le matching s'applique au flux **casefoldé** (défaut `--casefold=ascii` :
`Il` → `il` est retiré ; avec `--casefold=none`, `Il` ne l'est pas).

Listes intégrées (figées, 20 mots par langue) :

| Langue | Mots vides |
|---|---|
| `fr` | `le la les un une des de du et ou mais que qui ce il elle on je tu ne` |
| `en` | `the a an and or but of to in on for with is are was it this that not as` |

Exemple : `fstats --ngrams=2 --stopwords=fr corpus.txt` — « le » et « il » ne
participent pas aux bigrammes, mais restent comptés dans les mots.

### Histogrammes (`--histogram`)

Trois métriques, barres en **ASCII pur** (`#`, 1 barre par occurrence plafonnée
à 60) suivies du compte numérique. Classes **figées** (identiques à l'exemple
de la roadmap §6.6 pour `line_length` ; définies et documentées ici pour les
deux autres) :

| Métrique | Classes | Index de la valeur V |
|---|---|---|
| `line_length` | `0-9`, `10-19`, `20-29`, `30-39`, `40+` | `min(V div 10, 4)` |
| `word_length` | `1-2`, `3-4`, `5-6`, `7-8`, `9-10`, `11-12`, `13+` | `min((V−1) div 2, 6)` |
| `words_per_sentence` | `0-4`, `5-9`, `10-14`, `15-19`, `20+` | `min(V div 5, 4)` |

Sémantique :
- `line_length` : longueur des lignes en **code points**, toutes les lignes
  comprises (les lignes vides tombent dans `0-9`) ; **la somme des classes =
  `lines`**.
- `word_length` : longueur des mots du mode courant en **code points**
  (cohérent avec `average_word_length`) ; **la somme des classes = `words`**.
- `words_per_sentence` : mots par phrase selon la détection de phrases
  existante (`.` `!` `?` `…`) ; une phrase vide (terminateurs consécutifs) est
  comptée dans `0-4` ; **la somme des classes = `sentences`**. En mode
  `--word-mode=raw` (défaut), la ponctuation attachée à un mot
  (`simple.`) appartient au mot mais clôt la phrase immédiatement : les
  comptes par phrase sont alors approximatifs (utiliser
  `--word-mode=ascii|unicode` pour des mots « propres »).

JSON : clé additif `"histogram": {"metric": "line_length", "classes":
[{"range": "0-9", "count": n}, ...]}`. Console : section
« Histogram (metric) ».

### Classes de caractères (`--char-classes`)

Chaque code point est classé **une seule fois** pendant le décodage ; la somme
des six classes est **exactement `characters`** (assertion de test). Plages
**figées** :

| Classe | Plages exactes |
|---|---|
| `whitespace` | `U+0009` (TAB), `U+000A` (LF), `U+000D` (CR), `U+0020` (espace) — cohérent avec le compteur `tabs` (le TAB n'est pas un « non imprimable ») |
| `control` | C0 hors TAB/LF/CR (`U+0000`–`U+001F` moins `U+0009`/`U+000A`/`U+000D`), DEL (`U+007F`), C1 (`U+0080`–`U+009F`) |
| `digits` | `U+0030`–`U+0039` (chiffres ASCII) |
| `letters` | `A-Z` (`U+0041`–`U+005A`), `a-z` (`U+0061`–`U+007A`), Latin-1 hors `×`/`÷` (`U+00C0`–`U+00D6`, `U+00D8`–`U+00F6`, `U+00F8`–`U+00FF`), Latin étendu A/B (`U+0100`–`U+024F`), grec hors point-virgule grec (`U+0370`–`U+03FF` sauf `U+037E`), cyrillique (`U+0400`–`U+04FF`), Latin étendu additionnel (`U+1E00`–`U+1EFF`) |
| `punctuation` | Plages ASCII `U+0021`–`U+002F`, `U+003A`–`U+0040`, `U+005B`–`U+0060`, `U+007B`–`U+007E` + ponctuation/symboles Latin-1 (`U+00A1`–`U+00BF`) |
| `other` | tout le reste : symboles, blancs Unicode non-ASCII (`U+00A0`, `U+2000`…), marques combinantes (`U+0300`–`U+036F`), API (`U+0250`–`U+02AF`), `U+FFFD` (séquences UTF-8 invalides), BOM `U+FEFF`… |

JSON : clé additif `"char_classes": {"letters": n, "digits": n, "whitespace":
n, "punctuation": n, "control": n, "other": n}`. Console : section
« Character Classes ». Les classes `control` et le compteur `nonprintable`
peuvent différer sur un fichier contenant des contrôles C1 (inclus dans
`control`, exclus de `nonprintable`).

### Agrégation multi-fichiers (`--json-mode=aggregate`)

En mode aggregate, `char_classes` et `histogram` sont **sommés classe par
classe** dans `totals` (clés `totals.char_classes` et `totals.histogram`, mêmes
structures que par fichier). Les **n-grams ne sont pas agrégés** (limitation
documentée) : `totals` ne contient pas de clé `ngrams` ; les n-grams restent
présents dans chaque objet de `files`.

## Validation (texte de référence)

`tests/fixtures/test_fr.txt` (3 lignes) : « Voici un exemple simple. / Deuxième
phrase avec des mots. / Encore un test ! »

| Métrique                  | Valeur attendue |
|---------------------------|-----------------|
| Lignes                    | 3               |
| Mots                      | 13              |
| Caractères                | 72              |
| Phrases                   | 3               |
| Moyenne mots/phrase       | 4               |
| Longueur min / max / moy  | 16 / 30 / 23    |

Commandes de vérification :

```
fstats tests\fixtures\test_fr.txt
fstats --json tests\fixtures\test_fr.txt   # valider avec un parseur JSON
fstats --csv  tests\fixtures\test_fr.txt
fstats --help                # code 0
fstats fichier_inconnu.txt   # code 1, message sur stderr
```

Voir `doc/VERIFICATION.md` pour le journal de validation (sorties réelles).

## Structure du projet

```
fstats/
├── .github/workflows/
│   └── ci.yml            # CI GitHub Actions (Windows + Linux)
├── doc/                  # Documentation (roadmaps, journal de validation)
│   ├── README.md
│   ├── ROADMAPFULL.txt
│   ├── ROADMAP-CIBLE1.md
│   ├── ROADMAP-CIBLE2.md
│   ├── ROADMAP-CIBLE3.md
│   └── VERIFICATION.md
├── examples/
│   └── demo.obm          # Fichier de démonstration
├── src/
│   └── fstats.pas        # Code source unique (Free Pascal)
├── tests/
│   ├── run.bat           # Suite de tests Windows (CMD)
│   ├── run.sh            # Suite de tests Linux/Git Bash
│   ├── docs/             # Fixtures markdown (glob/agrégats)
│   └── fixtures/         # Fixtures de test (test_fr.txt, corpus_fr/en, BOM, CRLF…)
├── .gitattributes
├── .gitignore
├── LICENSE               # Licence MIT
├── README.md
├── wbld.bat              # Compilation rapide (Windows)
└── wclr.bat              # Nettoyage des artefacts
```

## Documentation

- `doc/ROADMAP-CIBLE1.md` — Cible 1 « CI / Text Quality Gate » (validée en
  v2.2.0, incrément A : stdin, glob interne, NDJSON/array/aggregate,
  `--summary-json`, compteurs qualité).
- `doc/ROADMAP-CIBLE2.md` — Cible 2 « Corpus Profiler » (vocabulaire,
  n-grammes, distributions, export pandas/R/Excel ; incréments C2-A « Lexique »
  livré en v2.3.0 et C2-B « Structure » livré en v2.4.0).
- `doc/ROADMAP-CIBLE3.md` — Cible 3 « Log Sentinel » (niveaux, top messages,
  patterns, rédaction, watch, sortie NDJSON pour pipelines/Grafana).
- `doc/VERIFICATION.md` — journal de validation (sorties réelles, historique).
- `doc/ROADMAPFULL.txt` — vision d'ensemble et roadmaps complètes.
- `doc/README.md` — index de la documentation.

## Tests automatisés

- `bash tests/run.sh` (Git Bash / Linux) : compile, exécute les cas
  d'acceptation des incréments A, C2-A et C2-B, vérifie les exit codes et
  valide le JSON avec node. Sortie : une ligne PASS/FAIL par cas, puis un bilan
  (exit 0 si tout passe).
- `tests\run.bat` (CMD) : équivalent Windows, mêmes cas et mêmes assertions
  (validation JSON avec node si disponible ; aucun `Pause` final, CI-friendly).
- Prérequis : `fpc` et `node` sur le PATH.
- La CI GitHub Actions exécute les deux suites sur `windows-latest` et
  `ubuntu-latest` à chaque push sur `main`/`master` et sur chaque
  `pull_request`.

## Limites connues

- Fichiers **texte UTF-8** uniquement (pas de binaire) ; une séquence UTF-8
  invalide est remplacée par U+FFFD et comptée (`invalid_utf8`).
- Le **BOM n'est pas supprimé** : il est détecté (`bom`) mais conservé dans les
  données (choix assumé, voir « Compteurs qualité »).
- Globs : `*` ne traverse pas le séparateur `/`, `**` le traverse (et `**/`
  consomme zéro ou plusieurs répertoires), `?` = exactement un caractère sans
  traverser `/`. Casse **insensible** sous Windows, sensible ailleurs. Les
  motifs `--include`/`--exclude` sont matchés contre le **chemin relatif** à la
  racine de `--recursive` (utiliser `**/*.md` pour couvrir les sous-répertoires).
- JSON multi-fichiers : le défaut v2.1 (concaténation d'objets) est **corrigé**
  en v2.2.0 — NDJSON par défaut, ou `--json-mode=array|aggregate`.
- La définition des mots par défaut inclut la ponctuation attachée (mode
  `raw`, voir « Sémantique ») ; `--word-mode=ascii|unicode` retire la
  ponctuation, `--casefold` étend la normalisation de casse.
- Le case folding `--casefold=unicode` est une table **basique limitée**
  (accents français/allemand, voir « Sémantique lexicale »), pas un folding
  Unicode complet.
- N-grams : top-K **approximatif** sur très gros corpus (top-K sketch, voir
  « Sémantique structure ») ; `--top-ngrams=0` rend la mémoire non bornée ;
  les n-grams ne sont **pas agrégés** en `--json-mode=aggregate` (présents par
  fichier uniquement) ; en mode `raw`, la ponctuation attachée participe aux
  n-grams (utiliser `--word-mode=ascii|unicode` pour des mots « propres »).
- Classes de caractères : périmètre **figé** et documenté (voir « Sémantique
  structure ») — pas une classification Unicode complète : les blancs
  Unicode non-ASCII (U+00A0…), les marques combinantes et l'API tombent dans
  `other`, et seuls les chiffres ASCII sont des `digits`.
