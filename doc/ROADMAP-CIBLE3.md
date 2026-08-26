# Roadmap Cible 3 — Log Sentinel

Positionnement : `fstats` surveille les logs applicatifs et SCADA/PLC :
niveaux, top messages, patterns, redaction, watch. Sortie NDJSON pour
pipelines/Grafana.

Base : ROADMAPFULL.txt (Mode 3 « Log Sentinel », §7.1-7.4, §6.9 redaction).
Dépend : Cible 1 livrée (v2.2.0 : stdin, NDJSON, glob, compteurs qualité,
statistiques de lignes).

## Verdict

La roadmap FULL vise un mode alarm SCADA complet (timestamps, sévérité, tags,
intervalles anormaux). **On adapte** : la v1 = profilage de logs
(niveaux + patterns + top messages + redaction) + watch en polling simple.
Le parsing temporel et l'analyse d'intervalles restent hors périmètre
(documenté), car ils demanderaient un vrai parseur de formats de logs — pas un
compteur.

## État déjà en place (v2.2.0, vérifié)

- stdin, NDJSON (format idéal pour les logs), glob/recursivité
- Compteurs qualité : `invalid_utf8`, `crlf`, `tabs`, `nonprintable`
  (hygiène des logs corrompus)
- `line min/max/avg` + `longest_lines` (détection de lignes anormales)
- Sortie ASCII pure, exit codes stables, streaming

## Roadmap FULL → adaptations (ce qui est possible)

| Feature (roadmap FULL) | Décision | Raison |
|---|---|---|
| Regex complète (`--pattern`, `--regex`) | **ADAPTER** : matcher interne littéral + `|` + `*`/`?` + classes simples `[0-9]` | `TRegExpr` n'est pas dans la RTL standard : casserait la portabilité mono-binaire |
| `--mode=alarm` complet (timestamp, sévérité, tag, intervalles) | **ADAPTER** : v1 = comptage par sévérité et par tag (`--regex-tag`), sans parsing temporel | parsing de timestamps = parseur de formats, hors périmètre compteur |
| `--watch` | **FAIRE** en polling (relit depuis la dernière position, `--interval`) | pas d'inotify : portabilité Windows/Linux/Termux |
| `--tail` / `--grep` interactifs | **ADAPTER** : `--filter=NIVEAU` (filtre les lignes affichées) | le tail interactif est un autre outil |
| Redaction (`--redact`) | **FAIRE** (C3-A) | essentiel pour loguer sans fuiter (emails, IP, URLs) |
| SQLite / DuckDB / Parquet / Grafana push | **ÉCARTÉ** | export NDJSON existant suffit ; push réseau plus tard |
| Plugins / scripting | **ÉCARTÉ** | la roadmap elle-même le déconseille (§7.6) |

## Incréments

### C3-A — Patterns & top messages

- `--pattern=TEXTE` (répétable, littéral) ; alternance `A|B` ; wildcards
  `*`/`?` (matcher interne documenté, PAS une regex complète).
- `--top-lines=N` : regroupe les lignes identiques (count + exemple tronqué).
- `--redact=email,ipv4,url` : remplace par `***` **dans les sorties seulement**
  (les compteurs restent calculés sur le texte brut).
- JSON : `patterns: [{pattern, matches, lines}]`, `top_lines: [{rank, count, line}]`.

### C3-B — Niveaux

- `--log-level` : détecte ERROR/WARN/INFO/DEBUG/TRACE (mot entier insensible à
  la casse, priorité dans cet ordre, sémantique documentée : n'importe où dans
  la ligne).
- Comptage par niveau + `none` (lignes sans niveau).
- `--filter=ERROR[,WARN]` : ne conserve que les lignes de ces niveaux
  (avec `--log-level`).
- JSON : `log_levels: {error: N, warn: N, info: N, debug: N, trace: N, none: N}`.

### C3-C — Alarm/SCADA v1

- `--mode=alarm` : raccourci = `--log-level` + `--top-lines` + `--regex-tag`.
- `--regex-tag=PATTERN` (subset : identifiants type `TAG[0-9]+`, classes
  simples) : extrait et compte les tags.
- Sortie JSON : par sévérité + top tags (cf. roadmap §7.4, sans timestamps).

### C3-D — Watch (polling)

- `--watch` / `--follow`, `--interval=N` (défaut 2 s, min 1 s) : résumé
  périodique (lignes, niveaux, erreurs, dernière MAJ).
- Suivi de position : ne relit que les octets ajoutés ; fichier tronqué =
  repart de zéro.
- Console ASCII uniquement ; erreurs sur stderr ; exit 0 tant que lisible.

## Sémantique à figer

- Niveau : première occurrence (mot entier, insensible à la casse) de
  ERROR > WARN > INFO > DEBUG > TRACE dans la ligne ; sinon `none`.
- Pattern : littéral, `|` = alternance, `*` = n'importe quelle suite, `?` = un
  caractère. Pas de regex complète — documenter noir sur blanc.
- Redaction : email `[\w.+-]+@[\w-]+(\.[\w-]+)+`, ipv4
  `\d{1,3}(\.\d{1,3}){3}`, url `https?://\S+` — appliquée **après** comptage.
- Watch : fichier existant au départ ; intervalle min 1 s ; pas d'inotify.

## Garde-fous

- Pas de regex complète (portabilité mono-binaire).
- Pas de parsing de timestamps ni d'intervalles anormaux en v1.
- Pas de plugins, pas de SQLite/Parquet, pas de push réseau.
- Mémoire bornée : top-lines/top-tags bornés (défaut 10, `--all` pour tout).
- Console ASCII pure ; les compteurs ne sont jamais faussés par la redaction.

## Effort & risques

- Delta estimé : **~700-900 lignes** (A ≈ 35 %, B ≈ 25 %, C ≈ 20 %, D ≈ 20 %).
- Risques : (1) matcher interne = périmètre documenté, ne pas laisser croire à
  une regex complète ; (2) watch en polling = coût CPU → relecture
  incrémentale obligatoire, intervalle min 1 s ; (3) redaction post-comptage
  pour ne pas fausser les statistiques.
- Tests : fixtures logs (niveaux, patterns, tags, lignes longues, UTF-8
  invalide), extension de `tests/run.bat` ; watch testé en script court avec
  timeout.

## Décision

Ordre : **C3-A → C3-B → C3-C → C3-D**. C3-D peut être repoussé si le polling
est jugé secondaire.