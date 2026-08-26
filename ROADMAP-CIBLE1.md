# Roadmap Cible 1 — CI / Text Quality Gate pour docs & logs

Statut : **validée** — incrément A livré (v2.2.0, 12/12 tests OK, 2026-08-26). B et C à venir.
Base : ROADMAPFULL.txt (sections 3, 5, 10, 13) — positionnement « fstats = text profiler & quality gate »

## Verdict

La niche **CI / text quality gate pour docs/logs** est la bonne première livraison, et elle est cohérente
avec ce que fstats est déjà. Les compteurs, l'UTF-8 strict et l'export JSON existent ; la valeur à ajouter
n'est pas dans les métriques mais dans le **moteur de décision** (seuils + exit codes + comparaison).

Positionnement livrable :

> **fstats check : un garde-fou de qualité textuelle qui fait échouer la CI quand les docs/logs dérivent.**

## État vérifié (inspection du 2026-08-26, fstats.pas 1512 lignes)

| Déjà solide (prouvé) | Manquant pour la niche |
|---|---|
| Analyse **streaming par blocs** (`BlockRead` + `BUF_SIZE`) — architecture conforme à la §11 de la roadmap | **stdin `-`** : rien dans le parsing d'arguments |
| UTF-8 strict incrémental (`DecodeUTF8`) | **Aucun compteur d'octets invalides** : l'invalide est remplacé silencieusement par U+FFFD → `non_utf8` impossible à vérifier |
| `lines`, `words`, `characters`, `sentences`, `avg_words_per_sentence`, `min/max/avg` de longueur de ligne | **Aucune détection BOM / CRLF / tabs / contrôles** (le code suit déjà CR/LF via `LastCPWasCR`) |
| JSON/CSV, console ASCII pure, `--out`, `--quiet`, exit codes 0/1, gestion d'erreur par fichier (`HadError`) | **JSON multi-fichiers invalide** : `fstats --json a.txt b.txt` concatène deux objets `{...}` (stdout **et** `--out`), exit 0 quand même. La doc ne signale que le cas `--out` ; le cas stdout est pire |
| — | Pas de glob, pas de checks, pas de `--compare` |

## Périmètre : 3 incréments, chacun livrable et testable

### Incrément A — « le tuyau » (rend fstats scriptable en CI) — LIVRÉ (v2.2.0)
- `fstats -` / `--stdin` (interdire le mélange stdin + fichiers)
- **Glob interne non négociable** : sous PowerShell/CMD, `docs/**/*.md` n'est jamais expansé par le shell →
  globs dans les arguments + `--recursive=DIR`, `--include=PATTERN`, `--exclude=PATTERN`
- **NDJSON multi-fichiers** (défaut dès plusieurs fichiers) + `--json-mode=array|aggregate`
- `--summary-json` (objet plat, pratique pour `jq`)
- Compteurs qualité : `invalid_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`

### Incrément B — « le juge » (le cœur de la niche)
- Moteur de checks : `--fail-if METRIQUE OPERATEUR SEUIL`, répétable
- **Exit codes : 0 = OK, 2 = check échoué, 3 = warnings seulement, 1 = erreur fatale** — uniquement en mode check ;
  le mode analyse garde 0/1 (pas de rupture pour les scripts existants)
- Sortie JSON enrichie : section `checks: [{id, metric, actual, op, threshold, status}]` + `schema_version`
- Checks d'emblée : `lines`, `words`, `sentences`, `max_line_length`, `avg_sentence_words`,
  `non_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`

### Incrément C — « la mémoire » (la dérive)
- `--compare baseline.json` + `--fail-on-delta metric>X%` — transforme le gate en outil de QA docs/logs

Les exemples CI (GitHub Actions + GitLab) et les tests golden s'ajoutent tout au long.

## Contrat de sortie proposé (à figer dans le README)

```text
exit 0 : analyse OK / tous les checks passent
exit 1 : erreur fatale (fichier introuvable, option invalide, stdin+fichiers mélangés)
exit 2 : au moins un check échoué            (mode check, incrément B)
exit 3 : warnings seulement                  (mode check, incrément B)
```

```sh
fstats docs/**/*.md --check --fail-if max_line_length>120 --fail-if non_utf8>0
fstats app.log - --check --fail-if max_line_length>500        # via stdin
fstats docs/*.md --check --config fstats.json                 # plus tard
```

## Garde-fous (ce qu'on ne fait pas)

- **Pas de refactor multi-unités** dans cette livraison : le mono-fichier tient jusqu'à ~2 500 lignes,
  le moteur de checks s'ajoute proprement. Le split attendra les modes corpus/logs.
- **Pas de patterns/regex/log-level** : pour les logs, cette livraison couvre la *qualité*
  (UTF-8, lignes, taille, dérive). Le comptage ERROR/WARN est un moteur différent (roadmap §7.3).
- **Pas de config TOML au premier jet** : les `--fail-if` en ligne de commande suffisent pour la CI.
- **Pas de changement des exit codes du mode analyse** (compatibilité).
- Pas de GUI, pas de SQLite, pas de watch.

## Effort & risques

- Delta estimé : **~500–700 lignes de Pascal** sur les 1512 actuelles + fixtures + YAML CI.
  A ≈ 40 % de l'effort, B ≈ 35 %, C ≈ 25 %.
- Risques : (1) le passage en NDJSON est un **changement cassant** pour les scripts existants →
  le faire dès A et le documenter ; (2) la grammaire `--fail-if` doit être figée tôt
  (opérateurs `> >= < <= = !=`, métriques snake_case stables, `schema_version`) ;
  (3) ne pas introduire le code 3 avant un cas d'usage réel (warning ≠ échec).
- Tests : fixtures nouvelles (`bom`, `crlf`, `invalid-utf8`, `long-line`, `empty`) + assertions d'exit codes,
  dans le style du VERIFICATION.md existant, automatisées (test.bat/test.sh) — la CI du projet
  doit pouvoir utiliser fstats lui-même (eat your own dog food).

## Décision

Périmètre validé, incrément A livré (v2.2.0). B et C suivent.