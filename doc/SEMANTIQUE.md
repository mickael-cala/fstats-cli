# Spécification technique — sémantique figée et formats de sortie

> Document de référence de `fstats` (v2.15.0). La sémantique décrite ici est
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
  "version": "2.15.0",
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
{"file": "tests\/fixtures\/bom.txt", "generated": "...", "tool": "fstats", "version": "2.15.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": true, "crlf": 0, "tabs": 0, "nonprintable": 0}, ...}
{"file": "tests\/fixtures\/crlf.txt", "generated": "...", "tool": "fstats", "version": "2.15.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": false, "crlf": 2, "tabs": 0, "nonprintable": 0}, ...}
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
  "version": "2.15.0",
  "schema_version": "1.0",
  "generated": "2026-08-26 11:38:40",
  "files": [ { "file": "tests\/docs\/guide\/api.md", "...": "..." } ],
  "totals": { "files": 3, "lines": 9, "words": 21, "characters": 123, "sentences": 3 }
}
```

Les totaux sont la somme exacte des statistiques des fichiers listés.

**`--summary-json` → objet plat par fichier (un par ligne, prêt pour jq) :**

```
{"file": "tests/fixtures/test_fr.txt", "tool": "fstats", "version": "2.15.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
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

**Échappement de cellules (v2.14.1)** : les caractères de contrôle LF, CR et
TAB sont d'abord remplacés par les littéraux `\n`, `\r`, `\t` (aucune cellule
ne peut casser la ligne une) ; ensuite guillemets doublés (`"` → `""`) quand
la cellule contient virgule ou guillemet, comme la RFC 4180.
**Neutralisation de formules** : toute cellule commençant par `=`, `+`, `-`
ou `@` est préfixée d'une apostrophe `'` (`=cmd|…` devient `'=cmd|…`) —
défense contre l'injection de formules Excel/LibreOffice (DDE) au moment où
un humain ouvre l'export. L'apostrophe fait partie de la donnée exportée ; ce
n'est **pas** un marqueur qu'un outil tiers doit retirer.

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
  **Frontière de blocs (v2.14.1)** : la lecture se fait par blocs de 64 Kio
  avec **zone tampon** — un caractère multi-octets à cheval sur deux blocs
  est reconstitué, jamais compté comme invalide ; un orphelin en toute fin
  de fichier (séquence tronquée par le EOF, pas par la frontière) compte
  pour 1. La longueur totale vérifiée = taille du fichier + 1 (sentinelle),
  chaque position n'est visitée qu'une fois.
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

## Bornes de stockage (v2.15.0)

**Les métriques sont exactes quelle que soit la taille du fichier ; seules
les données mises en mémoire pour le matching et le regroupement sont
bornées.**

- **Ligne stockée** : au plus `LINE_STORE_MAX` = **65 536 octets UTF-8**
  (constante `fstats_types.pas`). Au-delà, la ligne conservée pour le
  matching (`--pattern`, `--regex-tag`, niveaux de log), le regroupement
  `--top-lines` et les previews (`Longest Lines`) est tronquée à la borne.
  Conséquences documentées : un match situé au-delà de la borne n'est pas
  vu ; deux lignes identiques sur leurs 65 536 premiers octets partagent la
  même clé de regroupement. `line_min`/`line_max`/`line_avg`, le compteur
  de caractères et les longueurs restent **exacts** (comptés à la volée).
- **Mot stocké** : au plus `WORD_STORE_MAX` = **1 024 octets UTF-8**. Un mot
  plus long (possible en `--word-mode=raw` : tout ce qui n'est pas espace
  ni contrôle) compte **une fois** dans `words` et dans le compteur de
  caractères ; seule la clé du dictionnaire (Top Words, n-grams) est
  tronquée à 1 024, et `average_word_chars` / l'histogramme
  `word_length` le mesurent borné (approximation assumée).
- Rationnel (audit P2, registre sécurité) : un fichier d'une seule ligne de
  32 Mo saturait le CPU (concaténation quadratique, 18 s) et la mémoire
  (ligne entière conservée). L'append est désormais O(1) amorti
  (croissance géométrique), la mémoire est bornée, et les compteurs —
  l'usage nominal — restent exacts.

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
- **`--sentence-mode` (v2.7.0)** : `basic` (défaut) = règle ci-dessus.
  `smart` = en plus, pour le point `.` uniquement (`!`, `?`, `…` clôturent
  toujours) : le point est **avalé** (aucune clôture) si le mot courant est
  une abréviation de la liste figée `SMART_ABBREVIATIONS` (minuscules :
  `e.g`, `i.e`, `m`, `mme`, `mlle`, `dr`, `pr`, `st`, `ste`, `etc`, `mr`,
  `mrs`, `ms`, `jr`, `sr`, `inc`, `ltd`, `co`, `dept`, `fig`, `vs`, `www` —
  avec règle de préfixe pour `e.g.`/`i.e.` : le premier point est protégé car
  `e.` est un préfixe de `e.g`), ou si la fenêtre des 8 derniers caractères
  contient `://` (URL, ex. `https://ex.com`). Périmètre documenté : un
  point qui suit un mot non reconnu clôture ; `www.` sans protocole ne
  protège que son premier point (`www.ex.com` clôture sur `.com`) ; `e. g`
  (espace) avale son point par la règle de préfixe.
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
- `--check` **sans aucun check défini** (`--fail-if`/`--warn-if`/
  `--fail-on-delta`) : avertissement explicite sur stderr
  (« mode check actif sans aucun check defini… »), exit **0** inchangé —
  la gate no-op est visible, jamais silencieuse (v2.14.1).
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

## Sémantique Log Sentinel (v2.8.0, Cible 3-A)

### Patterns (`--pattern=TEXTE`)

- **Matcher interne** (PAS une regex complète) : littéral + `|` (alternance) +
  `*` (n'importe quelle suite, séparateurs compris) + `?` (exactement un
  caractère). Insensible à la casse (UpCase ASCII, comme le glob Windows).
- **v2.15.0 : algorithme glouton linéaire** (aucun backtracking, aucune
  récursion) — un pattern piégeux (`*a*a*a*a*a*a*b`) ne peut plus geler :
  complexité O(len(pattern)×len(ligne)). L'ordre d'exploration est celui de
  l'ancien algorithme (étoile minimale d'abord, reprise sur la dernière
  étoile) ; parité vérifiée sur 37 combinaisons motifs×fichiers.
- **Match de longueur nulle non compté** (v2.15.0) : un pattern qui matche
  vide à une position (`*`, `**`, segment vide d'alternation `a||b`) n'est
  pas une occurrence — le compteur reste 0 et le scanner avance d'une
  position (avant : boucle infinie).
- **Occurrences non chevauchantes**, recherchées de gauche à droite dans chaque
  ligne. Une ligne contribue à `lines` si elle contient au moins un match, et
  à `matches` du nombre total d'occurrences.
- Le matching s'effectue sur la ligne telle que construite en interne
  (`VisualChar` appliqué : les contrôles deviennent `\t`, `[CTRL]`…), **bornée
  à `LINE_STORE_MAX` = 65 536 octets** (v2.15.0, cf. Bornes de stockage) :
  un match au-delà de la borne n'est pas vu.
- Répétable : chaque `--pattern` produit une entrée distincte dans `patterns`.
- JSON : `"patterns": [{"pattern": "...", "lines": N, "matches": M}, ...]`.
  Console : section `Patterns`. CSV : lignes `type=pattern` (`value`=pattern,
  `count`=matches, `length`=lines). `--summary-json` : clé plate `patterns`.

### Top lignes identiques (`--top-lines=N`)

- Regroupe les lignes **identiques** (comparaison exacte de la chaîne interne)
  et conserve les N plus fréquentes (défaut 10 ; `0` = tous ; option absente =
  section désactivée). Tri décroissant par fréquence, puis alphabétique pour
  les égalités (déterminisme).
- **Mémoire bornée** comme les n-grams : quand le dictionnaire dépasse
  `max(8×N, 64)` entrées, il est réduit au top-N (les lignes rares écartées en
  cours de route sont perdues — approximation documentée, exacte sur les petits
  corpus).
- JSON : `"top_lines": [{"rank": r, "count": c, "line": "..."}, ...]`.
  Console : section `Top Lines`. CSV : lignes `type=topline` (`rank`, `value`=ligne,
  `count`). `--summary-json` : clé plate `top_lines`.
- Non agrégé en `--json-mode=aggregate` (comme les n-grams et la lisibilité) :
  présent par fichier uniquement.

### Redaction (`--redact=email,ipv4,url`)

- Liste séparée par des virgules, répétable. Chaque mode remplace les
  occurrences trouvées par `***` **dans les sorties uniquement** (console,
  JSON, CSV) — les compteurs (`words`, `characters`, `lines`…) restent calculés
  sur le **texte brut** (documenté, testé).
- **email** : `partie-locale@domaine.tld` avec au moins un point dans le domaine
  et des caractères `[A-Za-z0-9._+-]` pour la partie locale.
- **ipv4** : 4 groupes de 1-3 chiffres séparés par `.`, non suivis d'un chiffre
  ni d'un point (évite les décimales `3.14` et les versions `1.2.3.4.5`).
- **url** : `http://…` ou `https://…` jusqu'au prochain blanc ou fin de chaîne.
- La redaction s'applique à **toute émission de texte issu du fichier** :
  `longest_lines.content`, `top_lines.line`, aperçus console des lignes, et
  — depuis **v2.14.0 (P1-3)** — **top mots, n-grams et tags** dans tous les
  formats (console, JSON, CSV, `--summary-json`). Les caractères uniques du
  Top Characters ne sont pas redactés (un seul caractère ne reconstitue pas
  une donnée). Historique parano : avant v2.14.0, le Top Words laissait
  fuiter les emails/IPs/URLs malgré `--redact` — la doc d'alors décrivait ce
  comportement comme voulu ; c'était un défaut, corrigé et testé
  (test 109 du run.sh : grep de l'objet redacté = 0 dans toutes les sorties).

## Sémantique Log Sentinel — niveaux (v2.9.0, Cible 3-B)

### Niveaux de log (`--log-level`)

- Détection par **mot entier** insensible à la casse, n'importe où dans la
  ligne : `ERROR`, `WARN` (et **`WARNING`**, v2.14.1 — log4j, Python),
  `INFO`, `DEBUG`, `TRACE`. Un « mot entier » est délimité par des caractères
  non-alphanumériques ASCII ou les bords de chaîne (`ERRORS` ne matche pas
  `ERROR` ; `ERROR:` oui). `WARNING` compte dans le niveau `warn` (il n'y a
  pas de niveau « warning » distinct).
- **Priorité figée** : `ERROR` > `WARN` > `INFO` > `DEBUG` > `TRACE` — le
  premier trouvé dans cet ordre gagne, même si un niveau plus bas est aussi
  présent (`WARN then ERROR` → `error`).
- `none` = ligne sans aucun de ces mots. **Somme des 6 niveaux = `lines`**
  (assertion de test).
- JSON : `"log_levels": {"error": N, "warn": N, "info": N, "debug": N,
  "trace": N, "none": N}`. Console : section `Log Levels`. CSV : lignes
  `type=loglevel` (`value`=nom, `count`=lignes). `--summary-json` : clé plate
  `log_levels`. Non agrégé en `--json-mode=aggregate` (comme n-grams).

### Filtre (`--filter=error,warn,...`)

- Liste de niveaux séparés par des virgules (`error,warn,info,debug,trace,none`,
  insensible à la casse). Filtre **l'affichage console** des sections de lignes
  (`Top Lines`, `Longest Lines`) : seules les lignes dont le niveau détecté
  appartient à l'ensemble sont affichées, avec renumérotation des rangs.
- **Les compteurs globaux restent sur tout le fichier** (documenté, testé) :
  `lines`, `words`, `log_levels`, `patterns`… ne sont pas affectés.
- En JSON/CSV, toutes les lignes sont exportées (le filtre est console-only).
- `--filter` sans `--log-level` est accepté (le filtre s'applique quand même à
  l'affichage, la détection étant faite à la volée).

## Sémantique Log Sentinel — alarm / tags (v2.10.0, Cible 3-C)

### Extraction de tags (`--regex-tag=PATTERN`)

- **Mini-moteur regex subset** (PAS une regex complète, périmètre figé) :
  littéraux + classes `[...]` (plages `a-z`, `0-9`, `A-Z`, chars isolés) +
  quantifieurs `?` (0..1), `+` (1..∞), `*` (0..∞) après un token ; défaut = 1.
  Insensible à la casse pour les littéraux.
- **v2.15.0 : simulation NFA à ensemble d'états** (aucun backtracking) —
  complexité O(len(ligne)×len(pattern)) par position de départ ; un pattern
  à quantifieurs imbriqués (`a*a*a*b` sur une longue ligne) ne peut plus
  geler. Sémantique figée : depuis chaque position, le match retenu est le
  **plus long** ; un match vide n'est pas extrait (le scanner avance d'une
  position).
- Extraction : occurrences **non chevauchantes**, de gauche à droite, dans
  chaque ligne **stockée** (bornée à `LINE_STORE_MAX` = 65 536 octets,
  v2.15.0). Le tag = la sous-chaîne matchée.
- Exemples : `PLC[0-9]+` → `PLC1`, `PLC23` ; `[A-Z]+[0-9]+` → `PLC1`, `MOTOR23`,
  `SENSOR7`.
- Top-K borné comme les n-grams/top-lines : `--top-tags=N` (défaut 10, `0` =
  tous) ; dictionnaire réduit au top-N au-delà de `max(8×N, 64)` entrées.
- JSON : `"tags": [{"rank": r, "tag": "...", "count": N}, ...]`. Console :
  section `Tags`. CSV : lignes `type=tag`. `--summary-json` : clé plate `tags`.
  Non agrégé en `--json-mode=aggregate`.

### Mode alarm (`--mode=alarm`)

- Raccourci SCADA/PLC : active `--log-level` + `--top-lines` (10) +
  `--regex-tag` avec le pattern par défaut `[A-Z]+[0-9]+` (identifiants type
  `PLC1`, `TAG007`). Si `--regex-tag` est aussi passé, il prend le relais.
- `--mode` n'accepte que `alarm` (autre valeur → exit 1).

## Sémantique Log Sentinel — watch (v2.11.0, Cible 3-D)

### Watch (`--watch` / `--follow` + `--interval=N`)

- Surveille **exactement un fichier** (stdin et multi-fichiers interdits → exit 1).
  Fichier absent au départ → exit 1.
- Boucle infinie en polling : toutes les `N` secondes (défaut 2, min 1), le
  fichier est **ré-analysé complètement** (v1 — l'incrémental octet à octet
  n'est pas implémenté, limitation documentée) et une ligne de statut ASCII
  est affichée :
  `[timestamp] lines=N (+delta) words=N chars=N sentences=N | error=… warn=… info=… none=…`
  (les niveaux n'apparaissent qu'avec `--log-level`).
- `+delta` = variation des lignes depuis le tick précédent. Si le fichier a
  rétréci (troncature/rotation), un marqueur `[TRUNCATED]` est affiché.
- Fichier illisible en cours de route → message sur stderr, la boucle continue.
- **Ctrl+C** (SIGINT/SIGTERM) → arrêt propre, message `Stopped.`, **exit 0**.
- Console ASCII pur (aucun ANSI), `Flush` après chaque ligne (temps réel).

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

### Compagnon — génération de la ligne de commande (v2.13.0)

- `fstats --interactive` (alias `--wizard`) : wizard interactif (profils
  corpus/log/gate + toutes les options par catégorie). Affiche la commande
  générée ; sur confirmation `o`, fstats se ré-exécute avec cette commande et
  **propage le exit code** du fils. Sans entrée (EOF/pipe fermé), affiche
  seulement la commande (exit 0 si annulé, 1 si EOF avant la fin).
- `fcmd` : binaire compagnon séparé, même logique. Options :
  `--dry-run` (affiche seulement, exit 0), `--exec` (exécute sans demander,
  exit code propagé), `--profil=N` (1=corpus 2=log 3=gate ; les noms
  `corpus`/`log`/`gate` sont acceptés depuis v2.13.1), `--help`.
  Le wizard lit ligne par ligne sur stdin : pilotable en pipe
  (`printf '2\n0\n' | fcmd --dry-run`). `fcmd` exécute le `fstats` situé
  dans le même répertoire que lui-même (sinon refus explicite — v2.14.0).
- **v2.14.0 (P1-1)** : l'exécution se fait par **arguments séparés**
  (`SysUtils.ExecuteProcess` : fork/execve ou CreateProcess) — jamais de
  shell. Une valeur contenant `; rm -rf` est un simple argument. La commande
  affichée quotte les métacaractères (espace, tabulation, `& | < > ^ % !` ;
  `; $ \` ( ) …`) ; limite connue : cmd.exe développe `%VAR%` au collage
  même entre guillemets (registre sécurité, P2).
- Sortie du wizard : `Commande générée :` puis la ligne quotée pour le shell
  courant (guillemets doubles sous Windows, simples sous Unix).

Voir `VERIFICATION.md` pour le journal de validation (sorties réelles).
