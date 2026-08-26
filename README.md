# fstats — analyseur statistique de fichiers texte

Version 2.2.0 · Free Pascal (mode objfpc) · MIT

`fstats` analyse un ou plusieurs fichiers texte et compte les **caractères** (code
points UTF-8), **mots**, **lignes** et **phrases**, avec export **JSON**/**CSV**,
des **compteurs qualité** (UTF-8 invalide, BOM, CRLF, tabulations, caractères de
contrôle) et une résolution de **globs interne** (`*`, `**`, `?`) pour les shells
qui n'expandent pas les motifs (CMD, PowerShell).
La sortie console est compacte, alignée, en **ASCII pur** : conçue pour le
terminal et les scripts (aucune séquence ANSI par défaut, redirection sûre).
L'encodage de sortie est **UTF-8 déterministe**, y compris redirigé vers un
fichier ou un pipe (code page console forcé à UTF-8 au démarrage).

## Compilation

```
fpc -O2 -Mobjfpc fstats.pas
```

ou via `wbld.bat` (Windows). Un exécutable précompilé `fstats.exe` (Windows 32/64)
est fourni. `wclr.bat` supprime les artefacts de compilation (`*.o`, `*.ppu`, `*.exe`).

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

### Exports

| Option                | Effet                                                        |
|-----------------------|--------------------------------------------------------------|
| `--json`              | Export JSON (stdout ou `--out=`) : 1 fichier = objet unique ; plusieurs = NDJSON (1 objet par ligne) |
| `--json-mode=MODE`    | `ndjson` \| `array` \| `aggregate` (implique `--json`)       |
| `--summary-json`      | Objet JSON **plat** par fichier (scripts/jq)                 |
| `--csv`               | Export CSV (stdout ou `--out=`)                              |
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
fstats demo.obm
fstats --json --out=stats.json demo.obm
fstats --csv --all rapport.txt
fstats --word --line demo.obm
fstats --recursive=docs --include='**/*.md' --summary-json
fstats --recursive=src --exclude='**/vendor/**' --json-mode=aggregate
echo "un deux trois." | fstats - --json
fstats 'tests/**/*.md' --json-mode=array
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
File: demo.obm
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
« propres » est donc strictement identique à celle de la v2.1. Les trois
sections Top sont filtrées par `--char`/`--word`/`--line`. Le suffixe
`(N of K)` n'apparaît que si le total réel dépasse la limite affichée.

### JSON

Tous les exports JSON portent les champs de traçabilité `tool` (`"fstats"`),
`version` et `schema_version` (`"1.0"`), en plus de `generated`.

**1 fichier + `--json` → objet unique (format « pretty ») :**

```json
{
  "file": "test_fr.txt",
  "generated": "2026-08-26 11:38:35",
  "tool": "fstats",
  "version": "2.2.0",
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

**Plusieurs fichiers + `--json` → NDJSON (défaut, 1 objet compact par ligne) :**

```
{"file": "tests\/fixtures\/bom.txt", "generated": "...", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": true, "crlf": 0, "tabs": 0, "nonprintable": 0}, ...}
{"file": "tests\/fixtures\/crlf.txt", "generated": "...", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "statistics": {...}, "quality": {"invalid_utf8": 0, "bom": false, "crlf": 2, "tabs": 0, "nonprintable": 0}, ...}
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
  "version": "2.2.0",
  "schema_version": "1.0",
  "generated": "2026-08-26 11:38:40",
  "files": [ { "file": "tests\/docs\/guide\/api.md", "...": "..." } ],
  "totals": { "files": 3, "lines": 9, "words": 21, "characters": 123, "sentences": 3 }
}
```

Les totaux sont la somme exacte des statistiques des fichiers listés.

**`--summary-json` → objet plat par fichier (un par ligne, prêt pour jq) :**

```
{"file": "test_fr.txt", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### CSV

En-tête fixe : `metric,rank,value,code_point,count`.

Lignes `character`/`word`/`line` pour les Top 10 (ou tout avec `--all`), puis
les lignes de résumé et de traçabilité :

```
sentence_count,,7,,
avg_words_per_sentence,,24,,
source_file,,demo.obm,,
generated,,2026-08-26 10:35:45,,
```

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
- **Mots** : suites de caractères de code point > `0x20` (espace et caractères
  de contrôle = séparateurs). Conséquence : la ponctuation collée à un mot en
  fait partie (`simple.`), et une ponctuation isolée (`!`) compte comme un mot.
- **Phrases** : clôturées par `.`, `!`, `?` ou `…` (U+2026) ; si le fichier se
  termine avec du contenu non blanc après le dernier terminateur, une phrase
  finale supplémentaire est comptée. Un point décimal (`3.14`) clôture donc une
  phrase (limite documentée).
- **Lignes** : terminées par LF, CR ou CRLF ; la longueur est en caractères,
  sans le saut de ligne ; min/max/moyenne portent sur les lignes non vides.
- Les mots ASCII sont normalisés en minuscules (fréquences insensibles à la
  casse pour l'ASCII ; l'Unicode non-ASCII est conservé tel quel).

## Validation (texte de référence)

`test_fr.txt` (3 lignes) : « Voici un exemple simple. / Deuxième phrase avec
des mots. / Encore un test ! »

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
fstats test_fr.txt
fstats --json test_fr.txt    # valider avec un parseur JSON
fstats --csv  test_fr.txt
fstats --help                # code 0
fstats fichier_inconnu.txt   # code 1, message sur stderr
fstats verifier : voir VERIFICATION.md (journal de validation, sorties reelles)
```

## Tests automatisés

- `bash tests/run.sh` (Git Bash / Linux) : compile, exécute les cas
  d'acceptation de l'incrément A, vérifie les exit codes et valide le JSON avec
  node. Sortie : une ligne PASS/FAIL par cas, puis un bilan (exit 0 si tout
  passe).
- `tests\run.bat` (CMD) : équivalent Windows, mêmes cas et mêmes assertions
  (validation JSON avec node si disponible ; aucun `Pause` final, CI-friendly).
- Prérequis : `fpc` et `node` sur le PATH.

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
- La définition des mots inclut la ponctuation attachée (voir « Sémantique ») ;
  un mode « mots strictement alphabétiques » peut être ajouté sur demande.
