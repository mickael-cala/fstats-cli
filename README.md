# fstats — statistiques de fichiers texte en ligne de commande

**Langue / Language : 🇫🇷 [Français (ce fichier)](README.md) · 🇬🇧 [English](README.en.md)**

[![CI](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/mickael-cala/fstats-cli/actions/workflows/ci.yml)
[![Licence MIT](https://img.shields.io/badge/Licence-MIT-blue.svg)](LICENSE)

Version 2.16.2 · Free Pascal (mode objfpc) · MIT

`fstats` est un petit outil, **rapide et sans dépendances**, qui analyse des
fichiers texte UTF-8 et affiche des statistiques : caractères, mots, lignes,
phrases, mots les plus fréquents, n-grams, histogrammes… Il peut aussi
**servir de garde-fou en CI** : checks sur des seuils (`--fail-if`),
comparaison à une baseline (`--compare`) et exit codes dédiés (0/1/2/3).

Il tourne sur **Windows et Linux**, seul, sans environnement lourd : il suffit
du compilateur Free Pascal pour le construire.

> 👋 **Nouveau ici ?** Commence par le [guide pédagogique](doc/GUIDE-PEDAGOGIQUE.md) :
> il explique pas à pas, sans jargon, ce que fait l'outil et comment l'utiliser.

## Démarrage rapide

Compilation depuis la racine du dépôt (Windows) :

```
fpc -Sg -O2 -Mobjfpc -FE. src\fstats.pas
fpc -Sg -O2 -Mobjfpc -FE. src\fcmd.pas
```

Sous **Linux/macOS**, mêmes commandes avec le séparateur `/` :
`fpc -Sg -O2 -Mobjfpc -FE. src/fstats.pas` (le reste est inchangé).

`-Sg` est **requis** (le matcheur wildcards `fstats_lex.pas` utilise
`GOTO`/`LABEL`) ; les `fpc.cfg` officiels l'embarquent par défaut (`-Sgic`),
mais un `fpc.cfg` minimal ne l'a pas — d'où le switch explicite (vu en CI
au push v2.16.2).

Deux exécutables sont créés à la racine : `fstats.exe` et le compagnon
`fcmd.exe` (la deuxième ligne compile `src\fcmd.pas`).

Scripts de build prêts à l'emploi (multi-OS et multi-architecture, ils
compilent les deux binaires dans `bin/<arch>/` sans toucher aux binaires
de la racine utilisés par les tests) :

| OS | Build | Nettoyage |
|---|---|---|
| Windows (32 + 64 bits) | `build.bat` → `bin\win32\`, `bin\win64\` | `clear.bat` |
| Linux, bash (amd64 + aarch64) | `build.sh` → `bin/amd64/`, `bin/aarch64/` | `clear.sh` |
| macOS récent, zsh (Apple Silicon + Intel) | `buildmac.sh` → `bin/aarch64/`, `bin/x86_64/` | `clearmac.sh` |
| Vieux Mac Intel, bash | `buildmac-intel.sh` → `bin/x86_64/` | `clearmac-intel.sh` |

Une cible absente (ex. 64 bits sur une installation FPC 32 bits seule)
est signalée proprement puis ignorée : le script continue et récapitule
(exit 1 si au moins un échec ; `clear.*` ne supprime que `bin/`,
`*.ppu`, `*.o` et les binaires compilés).

Premières analyses :

```
fstats mon-fichier.txt          # statistiques complètes à l'écran
fstats "**/*.md"                # tous les .md du dossier (glob interne)
echo "un deux trois." | fstats - --summary-json   # depuis l'entrée standard
fstats --json mon-fichier.txt   # export JSON
```

## Compagnon : générer la ligne de commande (v2.13.0)

Pas envie de retenir les 50 options ? Deux façons équivalentes :

```
fstats --interactive     # wizard intégré à fstats
fcmd                     # binaire compagnon séparé
```

Le wizard propose **3 profils** (1=corpus, 2=log, 3=gate), puis **toutes les
options par catégorie** (fichiers, analyse, affichage, sentinel, checks,
export, divers), affiche la commande générée et demande si vous voulez
l'exécuter — **le exit code est propagé** (utile en CI). Pilotable en pipe :

```
printf '2\n0\n' | fcmd --dry-run
# affiche : fstats --mode=alarm --top-lines=10 --redact=email,ipv4,url
fcmd --exec              # exécute sans demander
fcmd --profil=log        # pré-sélectionne le profil
```

## Ce que fstats sait faire

| Domaine | Fonctionnalités |
|---|---|
| **Comptage** | caractères, mots, lignes, phrases, longueur des lignes (min/max/moyenne) |
| **Diagnostic** | UTF-8 invalide, BOM, fins de ligne CRLF, tabulations, caractères de contrôle |
| **Quality Gate** | checks sur seuils (`--fail-if`/`--warn-if`), baseline (`--compare`/`--fail-on-delta`), exit codes 0/1/2/3 pour la CI |
| **Vocabulaire** | mots uniques, hapax, type-token ratio, longueur moyenne des mots, entropie |
| **Répétitions** | n-grams (1 à 5 mots), avec filtrage des mots vides (français/anglais) |
| **Distribution** | histogrammes (longueur de ligne, de mot, mots par phrase), classes de caractères |
| **Lisibilité** | mots par phrase, longueur moyenne des mots, % de mots longs (≥ 7), score 0-100 (sans syllabes) |
| **Log Sentinel** | patterns (`--pattern`), top lignes (`--top-lines`), redaction (`--redact`), niveaux (`--log-level`), filtre (`--filter`), tags (`--regex-tag`), mode alarm (`--mode=alarm`), watch (`--watch`) |
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
| `--sentence-mode=basic\|smart` | Fin de phrase : `basic` (défaut) = `.` `!` `?` `…` + décimales ; `smart` = + abréviations (`M.`, `etc.`…) et URLs (`https://…`) |
| `--lexical-stats` | Mots uniques, hapax, TTR, longueur moyenne, entropie |
| `--readability` | Mots par phrase, longueur moyenne des mots, % de mots longs (≥ 7 caractères), score 0-100 — approximation **sans syllabes**, pas de Flesch-Kincaid exact |
| `--max-unique=N` | Borne mémoire des mots uniques (défaut 100 000) |
| `--ngrams=N` | N-grams sur les mots du mode courant (N = 1..5, fenêtres par ligne) |
| `--top-ngrams=K` | Limite du top-K des n-grams (défaut 10 ; `0` = tous) |
| `--stopwords=fr\|en\|none` | Retire les mots vides du flux n-grams uniquement |
| `--histogram=M` | `line_length` \| `word_length` \| `words_per_sentence` (barres ASCII) |
| `--char-classes` | Classe chaque caractère : lettres, chiffres, blancs, ponctuation, contrôle, autre |

### Log Sentinel (Cible 3-A/B/C/D)

| Option | Effet |
|---|---|
| `--pattern=TEXTE` | Compte les occurrences du pattern dans chaque ligne (répétable). Littéral + `\|` (alternance) + `*`/`?` (wildcards), insensible à la casse. Sous CMD, échapper `\|` : `--pattern="ERROR\|WARN"` |
| `--top-lines=N` | Top N des lignes identiques (défaut 10 ; absent = désactivé ; `0` = tous). Mémoire bornée comme les n-grams |
| `--redact=LISTE` | `email,ipv4,url` (séparés par virgule) : remplace par `***` dans les **sorties seulement** — toute émission de texte : mots, n-grams, tags, lignes (v2.14.0) ; les compteurs restent calculés sur le texte brut |
| `--log-level` | Compte les lignes par niveau : priorité `ERROR` > `WARN` > `INFO` > `DEBUG` > `TRACE` (mot entier, insensible à la casse, n'importe où dans la ligne) + `none`. Somme = `lines` |
| `--filter=LISTE` | `error,warn,info,debug,trace,none` (virgules) : filtre l'**affichage** des lignes (`Top Lines`, `Longest Lines`) ; les compteurs globaux restent sur tout le fichier |
| `--regex-tag=PAT` | Extrait et compte les tags (mini-moteur : littéral + classes `[0-9]`/`[a-z]`… + quantifieurs `?` `*` `+`). Ex. `PLC[0-9]+` → `PLC1`, `PLC23` |
| `--top-tags=N` | Limite du top des tags (défaut 10 ; `0` = tous). Mémoire bornée comme les n-grams |
| `--mode=alarm` | Raccourci SCADA/PLC : active `--log-level` + `--top-lines` + `--regex-tag` (tag par défaut `[A-Z]+[0-9]+` : `PLC1`, `TAG007`…) |
| `--watch`, `--follow` | Surveille **un** fichier en polling : ré-affiche le résumé toutes les `--interval` secondes jusqu'au Ctrl+C (exit 0). Interdit avec stdin ou plusieurs fichiers |
| `--interval=N` | Période du watch en secondes (défaut 2, min 1) |

### Checks et comparaison (CI)

| Option | Effet |
|---|---|
| `--check` | Mode check : gate CI avec exit codes 2/3 (implicite avec les options ci-dessous) |
| `--fail-if=METRIQUE OPERATEUR SEUIL` | Check bloquant, répétable (ex. `--fail-if max_line_length>120`) |
| `--warn-if=METRIQUE OPERATEUR SEUIL` | Check non bloquant (exit 3 si seulement des warnings) |
| `--compare=BASELINE` | Compare aux valeurs d'une baseline NDJSON (sortie `--summary-json`) |
| `--fail-on-delta=METRIQUE>X` | Check de dérive : échoue si la métrique varie de plus de X % vs baseline |

Métriques du gate : `lines`, `words`, `sentences`, `max_line_length`,
`avg_words_per_sentence` (alias `avg_sentence_words`), `non_utf8` (alias
`invalid_utf8`), `bom`, `crlf`, `tabs`, `nonprintable`. Opérateurs :
`>`, `>=`, `<`, `<=`, `=`, `!=`. (Sous CMD, échapper `>` : `--fail-if lines^>5`
ou `--fail-if "lines>5"`.)

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
| `--interactive`, `--wizard` | Wizard de génération de la ligne de commande (v2.13.0) ; compagnon séparé : `fcmd` |

### Exemples

```
fstats examples\demo.obm
fstats --json --out=stats.json examples\demo.obm
fstats --csv=words --all rapport.txt
fstats --recursive=docs --include='**/*.md' --summary-json
echo "un deux trois." | fstats - --json
fstats 'tests/**/*.md' --json-mode=aggregate
fstats --word-mode=ascii --top-words=20 --lexical-stats corpus.txt
fstats --sentence-mode=smart rapport.txt
fstats --sentence-mode=smart --check --fail-if avg_words_per_sentence>25 docs/*.md
fstats --casefold=unicode --lexical-stats --json corpus_fr.txt
fstats --ngrams=3 --top-ngrams=20 --word-mode=ascii corpus.txt
fstats --ngrams=2 --stopwords=fr corpus_fr.txt
fstats --histogram=line_length --histogram=word_length rapport.txt
fstats --char-classes --json corpus.txt
fstats --readability rapport.txt
fstats --readability --word-mode=ascii --summary-json corpus.txt
fstats --pattern='ERROR|WARN' --top-lines=10 app.log
fstats --pattern='*timeout*' --json app.log
fstats --redact=email,ipv4,url --json app.log
fstats --log-level app.log
fstats --log-level --filter=error,warn --top-lines=5 app.log
fstats --mode=alarm alarms.log
fstats --regex-tag='PLC[0-9]+' --top-tags=10 alarms.log --json
fstats --watch --interval=2 --log-level app.log      # Ctrl+C pour arrêter
echo -e "ERROR x\nINFO ok\nERROR y" | fstats - --pattern=ERROR --summary-json
fstats docs/**/*.md --check --fail-if max_line_length>120 --fail-if non_utf8>0
fstats app.log - --check --fail-if max_line_length>500       # via stdin
fstats --summary-json docs/*.md > baseline.ndjson            # capture
fstats docs/*.md --compare baseline.ndjson --fail-on-delta lines>10
fstats --help
```

## Formats de sortie

- **Console** : sections alignées en ASCII pur (`Summary`, `Checks`, `Quality`, `Lexical`,
  `Readability`, `Top Characters/Words`, `Longest Lines`, `N-grams`,
  `Histogram`, `Character Classes`, `Patterns`, `Top Lines`, `Log Levels`, `Tags`),
  sans séquence ANSI — sûre pour les scripts et pipes.
- **JSON** : champs de traçabilité (`tool`, `version`, `schema_version`,
  `generated`) + `statistics`, `quality`, et blocs additifs (`checks`, `lexical`,
  `readability`, `ngrams`, `histogram`, `char_classes`, `patterns`, `top_lines`,
  `log_levels`, `tags`) selon les options.
- **CSV v2** : en-tête fixe `file,type,rank,value,code_point,count,length`,
  trois sous-formats (`summary`, `words`, `chars`).

Les détails précis (exemples complets, schémas JSON, ruptures documentées) sont
dans la [spécification technique](doc/SEMANTIQUE.md).

## Codes de retour

| Code | Signification |
|---|---|
| 0 | Succès — analyse OK, ou tous les checks passent |
| 1 | Erreur fatale : fichier introuvable, glob sans correspondance, option invalide, sortie inécrivable, stdin mélangé avec des fichiers… |
| 2 | Mode check : au moins un check `--fail-if`/`--fail-on-delta` échoué |
| 3 | Mode check : aucun échec mais au moins un `--warn-if` déclenché |

Les données vont sur **stdout** ; les erreurs, avertissements et confirmations
`--out` vont sur **stderr**.

## Documentation

| Fichier | Contenu |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | Historique des versions (v2.2.0 → v2.16.2) |
| [doc/GUIDE-PEDAGOGIQUE.md](doc/GUIDE-PEDAGOGIQUE.md) | **Guide simple** : comprendre et utiliser fstats sans jargon |
| [doc/SEMANTIQUE.md](doc/SEMANTIQUE.md) | Spécification technique : sémantique figée des compteurs, formats JSON/CSV détaillés |
| [doc/VERIFICATION.md](doc/VERIFICATION.md) | Journal de validation (sorties réelles, historique) |
| [doc/AUDIT-SECURITE.md](doc/AUDIT-SECURITE.md) | Registre de sécurité : menaces, risques corrigés/en cours/backlog — **à lire avant d'analyser des fichiers fournis par des tiers** |
| [doc/ROADMAP-CIBLE1.md](doc/ROADMAP-CIBLE1.md) | Cible 1 « CI / Text Quality Gate » (validée : A v2.2.0, B+C v2.6.0) |
| [doc/ROADMAP-CIBLE2.md](doc/ROADMAP-CIBLE2.md) | Cible 2 « Corpus Profiler » (C2-A v2.3.0, C2-B v2.4.0, C2-C v2.5.0) |
| [doc/ROADMAP-CIBLE3.md](doc/ROADMAP-CIBLE3.md) | Cible 3 « Log Sentinel » — **complète** (C3-A v2.8.0 … C3-D v2.11.0 : patterns, top-lines, redaction, log-level, filter, alarm, watch) |
| [doc/ROADMAPFULL.md](doc/ROADMAPFULL.md) | Vision d'ensemble et roadmaps complètes |
| [doc/README.md](doc/README.md) | Index de la documentation |
| [README.en.md](README.en.md) | 🇬🇧 English translation of this README — tous les documents ont leur miroir anglais dans [doc/en/](doc/en/README.md) |

**Exemples prêts à l'emploi** : le dossier [exemples/](exemples/README.md)
embarque logs SCADA, corpus FR/EN, données, cas-limites et baseline — avec
des commandes dont chaque compteur annoncé a été vérifié.

## Tests automatisés

- `tests\run.bat` (Windows / CMD) et `tests\run.sh` (Linux / Git Bash) :
  compilation + 127 cas d'acceptation (Cibles 1-2-3, compagnon `fcmd`,
  correctifs P0/P1/P2) avec validation JSON via node et vérification des
  codes de retour — état vérifié v2.16.2 : **127/127 sur les deux suites**.
- Prérequis : `fpc` et `node` sur le PATH.
- La CI GitHub Actions exécute les deux suites sur `windows-latest` et
  `ubuntu-latest` à chaque push sur `main` et chaque `pull_request`.

## Structure du projet

```
fstats/
├── .github/workflows/ci.yml  # CI GitHub Actions (Windows + Linux)
├── doc/                      # Documentation (guide, spec, roadmaps, validation)
├── doc/en/                   # English translations of the documentation
├── exemples/                 # Corpus de démonstration (logs SCADA, textes, données, cas-limites)
├── src/fstats.pas            # Programme principal (point d'entrée, parsing CLI)
├── src/fstats_types.pas      # Constantes, globales, types (TStats, options…)
├── src/fstats_utf8.pas       # UTF-8, VisualChar, tris, couleurs ANSI, FormatFloatTrim
├── src/fstats_glob.pas       # Moteur de glob interne (*, **, ?) et --recursive
├── src/fstats_lex.pas        # Tokenisation, n-grams, patterns/redaction, log-level, regex-tag
├── src/fstats_sha.pas        # SHA-256 streaming (FIPS 180-4) : intégrité baseline
├── src/fstats_analyzer.pas   # Analyse (fichier/stdin) + watch C3-D + handlers Ctrl+C
├── src/fstats_checks.pas     # Quality gate : checks, baseline NDJSON, --fail-on-delta
├── src/fstats_cmdgen.pas     # Wizard partagé (génération de commande, v2.13.0)
├── src/fcmd.pas              # Compagnon fcmd : génère la ligne de commande
├── src/fstats_output.pas     # Sorties : console, JSON, CSV, usage
├── tests/                    # Suites de tests + fixtures (run.sh + run.bat, 127 cas)
├── LICENSE                   # Licence MIT
└── README.md
```

## Limites connues (en bref)

> La liste de référence, priorisée et tenue à jour, est le registre
> [doc/AUDIT-SECURITE.md](doc/AUDIT-SECURITE.md) — à lire avant d'analyser
> des fichiers fournis par des tiers.

- `--out` **refuse** désormais de désigner un fichier analysé (protection
  anti-destruction, v2.14.0) — au lieu de le vider silencieusement.
- Les valeurs saisies dans le wizard sont exécutées via des arguments
  séparés (aucun shell) ; en revanche, la commande **affichée** reste du
  texte : sous cmd.exe, un collage développe encore `%VAR%` (registre P2).
- **Fichiers texte UTF-8 uniquement** : une séquence invalide est remplacée par
  U+FFFD et comptée (`invalid_utf8`).
- Le **BOM est détecté mais conservé** (choix assumé).
- La définition par défaut d'un mot inclut la ponctuation attachée (mode
  `raw`) ; `--word-mode=ascii|unicode` retire la ponctuation.
- Le case folding `unicode` est une table basique limitée (accents
  français/allemand), pas un folding Unicode complet.
- N-grams : top-K **approximatif** sur très gros corpus (sketch mémoire
  borné) ; non agrégés en `--json-mode=aggregate`.
- Un point **entre deux chiffres** (`3.14`) ne clôture pas une phrase (v2.6.1) ;
  un point après un chiffre suivi d'un espace (`Version 3.`) reste une fin de
  phrase.
- Le score de lisibilité (`--readability`) est une approximation **sans
  syllabes** : ce n'est pas un Flesch-Kincaid exact (la formule est figée dans
  la spécification technique).
- `--regex-tag` est un **mini-moteur** (littéral + classes `[...]` + `? * +`),
  pas une regex complète ; périmètre figé dans la spécification technique.
- `--top-lines` et `--top-tags` : top-K **approximatif** sur très gros logs
  (dictionnaire borné comme les n-grams).
- `--watch` (v1) **ré-analyse le fichier en entier** à chaque tick (l'incrémental
  octet à octet n'est pas implémenté) ; suffisant pour des logs de taille
  raisonnable, documenté.

Toutes les sémantiques sont détaillées et figées dans la
[spécification technique](doc/SEMANTIQUE.md).
