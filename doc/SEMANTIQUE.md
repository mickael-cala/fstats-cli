# Spécification technique — sémantique figée et formats de sortie

> Document de référence de `fstats` (v2.4.0). La sémantique décrite ici est
> **figée** : elle ne changera pas dans les versions futures sans annonce
> explicite. Pour la prise en main, voir le
> [guide pédagogique](GUIDE-PEDAGOGIQUE.md) ; pour la vue d'ensemble, le
> [README](../README.md).

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
  finale supplémentaire est comptée. Depuis v2.6.1, un point **entre deux
  chiffres** (`3.14`) ne clôture PAS une phrase (décimale) ; un point après un
  chiffre suivi d'autre chose qu'un chiffre (`Version 3. Fin.`) clôture
  toujours. Un point entouré d'espaces (`3 . 14`) clôture (pas une décimale
  collée).
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

## Sémantique du moteur de checks (v2.6.0)

Cible 1 B+C : `fstats` devient un garde-fou de qualité textuelle pour la CI.
Mode check activé par `--check` **ou implicitement** par `--fail-if`,
`--warn-if`, `--compare` ou `--fail-on-delta`. En mode check, les exit codes
2/3 s'appliquent ; le mode analyse garde 0/1 (aucune rupture).

### Grammaire figée

- `--fail-if=<metric><op><seuil>` (ou arguments séparés : `--fail-if <metric>
  <op> <seuil>`) — check bloquant, répétable. `--warn-if` : même grammaire,
  non bloquant.
- Métrique : `[a-z0-9_]+`. Opérateurs : `>`, `>=`, `<`, `<=`, `=`, `!=`.
  Seuil : `[0-9]+(".[0-9]+")?` ('.' séparateur, sans signe ni exposant,
  indépendant de la locale).
- Métriques du gate : `lines`, `words`, `sentences`, `max_line_length`
  (= `line_max`), `avg_words_per_sentence` (division entière, comme le
  Summary ; alias `avg_sentence_words`), `non_utf8` (alias `invalid_utf8`),
  `bom` (0/1), `crlf`, `tabs`, `nonprintable`. Métrique inconnue ou syntaxe
  invalide → erreur fatale (exit 1, stderr).

### Statuts et exit codes

- Statut d'un check : `ok` | `warn` | `fail` (comparaison numérique stricte).
- Multi-fichiers : le pire statut cumulé gagne (fail > warn > ok).
- Exit : 0 = tous ok (ou aucun check défini) ; 1 = erreur fatale (prime) ;
  2 = au moins un fail ; 3 = aucun fail mais au moins un warn.

### Baseline et dérive (`--compare`, `--fail-on-delta`)

- Baseline : NDJSON produit par `--summary-json` (une ligne JSON par fichier,
  clé `file`) ; un objet unique est accepté. Ligne illisible → exit 1.
- Correspondance par la chaîne `file` telle que fstats l'affiche. Fichier
  sans baseline → checks de dérive ignorés pour ce fichier (documenté).
- `--fail-on-delta=<metric>>X` (répétable, `>` imposé) :
  `delta = (actual - base) / base * 100` ; échec si `delta > X`.
  `base = 0` : delta 0 si actual = 0, sinon dérive infinie (échec — une
  métrique qui passe de 0 à >0 est une dérive infinie, documenté).
- Métriques delta : clés numériques du summary-json (`lines`, `words`,
  `characters`, `sentences`, `avg_words_per_sentence` (alias
  `avg_sentence_words`), `line_min`, `line_max`, `line_avg`, `invalid_utf8`
  (alias `non_utf8`), `bom`, `crlf`, `tabs`, `nonprintable`).

### Sorties

- Console : section `Checks` après Summary (métrique, op, seuil, statut,
  valeur réelle ; pour les deltas, le delta %). ASCII pur.
- JSON pretty/NDJSON : bloc additif `checks` (après `quality`) :
  `{"id": …, "metric": …, "actual": …, "op": …, "threshold": …,
  "status": …}`. `id` = métrique (ou `delta:<metric>`), puis `#2`, `#3`… en
  cas de répétition. Pour un delta, `actual` = delta % et `op` = `>`.
- `--summary-json` et `--csv` : **pas** de section checks (les exit codes
  s'appliquent quand même). `--json-mode=aggregate` : checks par fichier,
  jamais dans `totals`.

## Sémantique de la lisibilité (v2.5.0)

`--readability` ajoute 4 métriques calculées sur **le mode courant** (mêmes
tokens que `--word-mode` + repli `--casefold`, cohérent avec `--lexical-stats`).
Inspiré de Flesch mais **sans syllabes** (aucune détection de syllabes en
français/anglais) : ce n'est pas un Flesch-Kincaid exact — mention explicite
au README.

### Métriques (formules exactes)

- `avg_sentence_words` = `WordCount / SentenceCount` (flottant ; 0 si aucune
  phrase). Ne pas confondre avec `avg_words_per_sentence` du Summary, qui est
  la division **entière** (`div`).
- `avg_word_chars` = `WordCharsTotal / WordCount` (0 si aucun mot) — même
  valeur que `average_word_length` de `--lexical-stats`.
- `pct_long_words` = `100 * LongWordCount / WordCount` (0 si aucun mot), où
  `LongWordCount` = tokens de longueur **>= 7 code points** (constante
  `LONG_WORD_MIN_LEN = 7`).
- `score` (0-100, borné) :

  ```
  score = 100 * (1 - (0.5 * min(ASL/30, 1) + 0.5 * min(max(ALW-3, 0)/5, 1)))
  ```

  avec `ASL = avg_sentence_words` et `ALW = avg_word_chars`. Ancrages : une
  phrase de 30+ mots en moyenne ou des mots de 8+ caractères en moyenne
  annulent chacun la **moitié** du score. Un texte sans aucun mot (fichier
  vide) a un score de 0 (rien à évaluer).

### Clés de sortie

- JSON pretty / NDJSON : bloc additif `readability` avec les 4 clés
  (`avg_sentence_words`, `avg_word_chars`, `pct_long_words`, `score`),
  6 décimales via `FormatFloatTrim`.
- `--summary-json` : clés plates `avg_sentence_words`, `avg_word_chars`,
  `pct_long_words`, `readability_score` en fin d'objet (6 décimales).
- CSV `--csv=summary` : lignes `summary,,avg_sentence_words,,<v>,`,
  `summary,,avg_word_chars,,<v>,`, `summary,,pct_long_words,,<v>,`,
  `summary,,readability_score,,<v>,` (6 décimales).
- Console : section `Readability` (4 lignes, 4 décimales, `%` sur
  `Pct long words`).

Comme les n-grams, la lisibilité **n'est pas agrégée** dans
`--json-mode=aggregate` (présente par fichier uniquement — limitation
assumée et documentée dans le code).

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

Voir `VERIFICATION.md` pour le journal de validation (sorties réelles).
