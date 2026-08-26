# fstats — statistiques de fichiers texte en ligne de commande

[![CI](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml)
[![Licence MIT](https://img.shields.io/badge/Licence-MIT-blue.svg)](LICENSE)

Version 2.5.0 · Free Pascal (mode objfpc) · MIT

`fstats` est un petit outil, **rapide et sans dépendances**, qui analyse des
fichiers texte UTF-8 et affiche des statistiques : caractères, mots, lignes,
phrases, mots les plus fréquents, n-grammes, histogrammes…

Il tourne sur **Windows et Linux**, seul, sans environnement lourd : il suffit
du compilateur Free Pascal pour le construire.

> 👋 **Nouveau ici ?** Commence par le [guide pédagogique](doc/GUIDE-PEDAGOGIQUE.md) :
> il explique pas à pas, sans jargon, ce que fait l'outil et comment l'utiliser.

## Démarrage rapide

Compilation depuis la racine du dépôt :

```
fpc -O2 -Mobjfpc -FE. src\fstats.pas
```

L'exécutable `fstats.exe` est créé à la racine (`wbld.bat` fait pareil sous
Windows ; `wclr.bat` nettoie les artefacts de compilation).

Premières analyses :

```
fstats mon-fichier.txt          # statistiques complètes à l'écran
fstats "**/*.md"                # tous les .md du dossier (glob interne)
echo "un deux trois." | fstats - --summary-json   # depuis l'entrée standard
fstats --json mon-fichier.txt   # export JSON
```

## Ce que fstats sait faire

| Domaine | Fonctionnalités |
|---|---|
| **Comptage** | caractères, mots, lignes, phrases, longueur des lignes (min/max/moyenne) |
| **Diagnostic** | UTF-8 invalide, BOM, fins de ligne CRLF, tabulations, caractères de contrôle |
| **Vocabulaire** | mots uniques, hapax, type-token ratio, longueur moyenne des mots, entropie |
| **Répétitions** | n-grammes (1 à 5 mots), avec filtrage des mots vides (français/anglais) |
| **Distribution** | histogrammes (longueur de ligne, de mot, mots par phrase), classes de caractères |
| **Lisibilité** | mots par phrase, longueur moyenne des mots, % de mots longs (≥ 7), score 0-100 (sans syllabes) |
| **Export** | console alignée ASCII pur, JSON (objet / NDJSON / tableau / agrégat), CSV |

## Utilisation

```
fstats [options] <fichier|glob|-> [fichier2 ...]
```

### Entrées

| Option | Effet |
|---|---|
| `-`, `--stdin` | Analyse l'entrée standard en UTF-8 (non mélangeable avec des fichiers) |
| `*.txt`, `**/*.md` | Patterns glob résolus **en interne** (CMD/PowerShell n'expandent pas les globs) |
| `--recursive=DIR` | Parcourt l'arbre de `DIR` (répétable) |
| `--include=GLOB`, `--exclude=GLOB` | Filtres pour `--recursive` (répétables) |
| `--max-depth=N` | Profondeur maximale du parcours (0 = racine seule) |

### Analyse du texte

| Option | Effet |
|---|---|
| `--word-mode=raw\|ascii\|unicode` | Définition des mots (ponctuation incluse ou non) |
| `--casefold=ascii\|unicode\|none` | Normalisation des majuscules et des accents |
| `--lexical-stats` | Mots uniques, hapax, TTR, longueur moyenne, entropie |
| `--readability` | Mots par phrase, longueur moyenne des mots, % de mots longs (≥ 7 caractères), score 0-100 — approximation **sans syllabes**, pas de Flesch-Kincaid exact |
| `--max-unique=N` | Borne mémoire des mots uniques (défaut 100 000) |
| `--ngrams=N` | N-grammes sur les mots du mode courant (N = 1..5, fenêtres par ligne) |
| `--top-ngrams=K` | Limite du top-K des n-grammes (défaut 10 ; `0` = tous) |
| `--stopwords=fr\|en\|none` | Retire les mots vides du flux n-gramme uniquement |
| `--histogram=M` | `line_length` \| `word_length` \| `words_per_sentence` (barres ASCII) |
| `--char-classes` | Classe chaque caractère : lettres, chiffres, blancs, ponctuation, contrôle, autre |

### Affichage et export

| Option | Effet |
|---|---|
| `--top-words=N`, `--top-chars=N` | Limites des sections Top (défaut 10 ; `0` = tous) |
| `--char`, `--word`, `--line`, `--all` | Sections « Top » ciblées / toutes les données |
| `--json` | JSON : 1 fichier = objet ; plusieurs = NDJSON (1 objet par ligne) |
| `--json-mode=ndjson\|array\|aggregate` | Forme du JSON multi-fichiers (implique `--json`) |
| `--summary-json` | Objet JSON plat par fichier (idéal pour `jq` et les scripts) |
| `--csv[=summary\|words\|chars]` | Export CSV v2 (`--csv` seul = `summary`) |
| `--out=FICHIER` | Écrit la sortie dans un fichier (jamais d'ANSI, jamais de message console) |
| `--quiet` | Pas de confirmation console avec `--out` |
| `--color`, `--no-color` | Coloriage minimal des titres (console uniquement) |
| `--version`, `--help`, `-h` | Version / aide |

### Exemples

```
fstats examples\demo.obm
fstats --json --out=stats.json examples\demo.obm
fstats --csv=words --all rapport.txt
fstats --recursive=docs --include='**/*.md' --summary-json
echo "un deux trois." | fstats - --json
fstats 'tests/**/*.md' --json-mode=aggregate
fstats --word-mode=ascii --top-words=20 --lexical-stats corpus.txt
fstats --casefold=unicode --lexical-stats --json corpus_fr.txt
fstats --ngrams=3 --top-ngrams=20 --word-mode=ascii corpus.txt
fstats --ngrams=2 --stopwords=fr corpus_fr.txt
fstats --histogram=line_length --histogram=word_length rapport.txt
fstats --char-classes --json corpus.txt
fstats --readability rapport.txt
fstats --readability --word-mode=ascii --summary-json corpus.txt
fstats --help
```

## Formats de sortie

- **Console** : sections alignées en ASCII pur (`Summary`, `Quality`, `Lexical`,
  `Readability`, `Top Characters/Words`, `Longest Lines`, `N-grams`,
  `Histogram`, `Character Classes`), sans séquence ANSI — sûre pour les
  scripts et pipes.
- **JSON** : champs de traçabilité (`tool`, `version`, `schema_version`,
  `generated`) + `statistics`, `quality`, et blocs additifs (`lexical`,
  `readability`, `ngrams`, `histogram`, `char_classes`) selon les options.
- **CSV v2** : en-tête fixe `file,type,rank,value,code_point,count,length`,
  trois sous-formats (`summary`, `words`, `chars`).

Les détails précis (exemples complets, schémas JSON, ruptures documentées) sont
dans la [spécification technique](doc/SEMANTIQUE.md).

## Codes de retour

| Code | Signification |
|---|---|
| 0 | Succès (au moins un fichier analysé sans erreur) |
| 1 | Erreur : fichier introuvable, glob sans correspondance, option invalide, sortie inécrivable, stdin mélangé avec des fichiers… |

Les données vont sur **stdout** ; les erreurs, avertissements et confirmations
`--out` vont sur **stderr**.

## Documentation

| Fichier | Contenu |
|---|---|
| [doc/GUIDE-PEDAGOGIQUE.md](doc/GUIDE-PEDAGOGIQUE.md) | **Guide simple** : comprendre et utiliser fstats sans jargon |
| [doc/SEMANTIQUE.md](doc/SEMANTIQUE.md) | Spécification technique : sémantique figée des compteurs, formats JSON/CSV détaillés |
| [doc/VERIFICATION.md](doc/VERIFICATION.md) | Journal de validation (sorties réelles, historique) |
| [doc/ROADMAP-CIBLE1.md](doc/ROADMAP-CIBLE1.md) | Cible 1 « CI / Text Quality Gate » (validée en v2.2.0) |
| [doc/ROADMAP-CIBLE2.md](doc/ROADMAP-CIBLE2.md) | Cible 2 « Corpus Profiler » (C2-A v2.3.0, C2-B v2.4.0, C2-C v2.5.0) |
| [doc/ROADMAP-CIBLE3.md](doc/ROADMAP-CIBLE3.md) | Cible 3 « Log Sentinel » |
| [doc/ROADMAPFULL.txt](doc/ROADMAPFULL.txt) | Vision d'ensemble et roadmaps complètes |
| [doc/README.md](doc/README.md) | Index de la documentation |

## Tests automatisés

- `tests\run.bat` (Windows / CMD) et `tests\run.sh` (Linux / Git Bash) :
  compilation + 39 cas d'acceptation (incréments A, C2-A, C2-B, C2-C) avec
  validation JSON via node et vérification des codes de retour.
- Prérequis : `fpc` et `node` sur le PATH.
- La CI GitHub Actions exécute les deux suites sur `windows-latest` et
  `ubuntu-latest` à chaque push sur `main` et chaque `pull_request`.

## Structure du projet

```
fstats/
├── .github/workflows/ci.yml  # CI GitHub Actions (Windows + Linux)
├── doc/                      # Documentation (guide, spec, roadmaps, validation)
├── examples/demo.obm         # Fichier de démonstration
├── src/fstats.pas            # Code source unique (Free Pascal)
├── tests/                    # Suites de tests + fixtures
├── LICENSE                   # Licence MIT
└── README.md
```

## Limites connues (en bref)

- **Fichiers texte UTF-8 uniquement** : une séquence invalide est remplacée par
  U+FFFD et comptée (`invalid_utf8`).
- Le **BOM est détecté mais conservé** (choix assumé).
- La définition par défaut d'un mot inclut la ponctuation attachée (mode
  `raw`) ; `--word-mode=ascii|unicode` retire la ponctuation.
- Le case folding `unicode` est une table basique limitée (accents
  français/allemand), pas un folding Unicode complet.
- N-grammes : top-K **approximatif** sur très gros corpus (sketch mémoire
  borné) ; non agrégés en `--json-mode=aggregate`.
- Les points décimaux (`3.14`) clôturent une phrase (limite documentée).
- Le score de lisibilité (`--readability`) est une approximation **sans
  syllabes** : ce n'est pas un Flesch-Kincaid exact (la formule est figée dans
  la spécification technique).

Toutes les sémantiques sont détaillées et figées dans la
[spécification technique](doc/SEMANTIQUE.md).
