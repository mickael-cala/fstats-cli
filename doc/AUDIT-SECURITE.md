# Registre de sécurité et de qualité — fstats

> Document vivant, tenu au fil des audits. Convention : chaque constat a un
> **statut** (CORRIGÉ / OUVERT / ACCEPTÉ_DOCUMENTÉ / REFOULÉ_À), un numéro,
> et une entrée dans le CHANGELOG quand son statut change.
> Devise parano/pédago : *ce qu'on ne documente pas, on le cache. Ce qu'on
> documente, on le gère.*

---

## 1. Méthode d'audit (2026-11-23)

Trois auditeurs indépendants en parallèle — un architecte Pascal (dev), un
pentester (cyber), un designer CLI (UX), lecture exhaustive des ~7 600
lignes + exécutions réelles. Synthèse croisée puis **re-vérification
manuelle de chaque constat majeur** avant toute correction (6/6 confirmés).
P0 corrigé en v2.13.1 ; P1 en cours ; P2 ci-dessous.

## 2. Modèle de menace (lire avant d'utiliser fstats sur des données sensibles)

**Actifs**

1. Le contenu des fichiers analysés (logs : emails, IPs, identifiants).
2. Les fichiers du disque (`--out` écrit, `--recursive` lit).
3. Le verdict CI (exit codes 0/1/2/3, baseline `--compare`).
4. Le poste qui exécute le wizard (`--interactive` / `fcmd`).

**Qui contrôle quoi** (la question à se poser avant chaque usage)

| Entrée | Contrôlée par | Niveau de confiance |
|---|---|---|
| `argv` (options, patterns, seuils) | l'opérateur | élevé |
| Fichiers analysés (logs CI, artefacts) | **l'extérieur** | **nul** |
| Baseline NDJSON (`--compare`) | quiconque écrit dans le dépôt | moyen |
| stdin / pipe du wizard | pipeline local | élevé |

**La règle d'or de ce registre** : dès qu'un fichier analysé est fourni par
un tiers (artefact de build, log d'un client), fstats traite **une entrée
hostile**. Les parseurs maison (glob, wildcards, mini-regex, NDJSON,
matching de niveaux) sont écrits défensivement mais ne bénéficient pas des
décennies de durcissement des bibliothèques éprouvées.

## 3. Statut P0 — corrigé en v2.13.1 ✅

| ID | Constat | Correction |
|---|---|---|
| P0-1 | Off-by-one `--pattern` (occurrences adjacentes perdues : `errorerrorerror` → 2) | convention alignée + tests golden 108 |
| P0-2 | Wizard générant des commandes refusées par fstats (`--ngrams=2,3`, `--csv-kind`, `sentence_words`) | table conforme au parseur + test qui **exécute** |
| P0-3 | Suite de tests rouge depuis v2.12.0 (version figée `2.11.0`) | version **dérivée** de `fstats_types.pas` |
| P0-4 | `fcmd --profil=log` promis mais non supporté | noms acceptés |
| P0-5 | `--help` « ASCII pur » contenant un accent | normalisé |

## 4. Statut P1 — corrigé en v2.14.0 ✅

| ID | Constat (vérifié) | Gravité | Correction |
|---|---|---|---|
| P1-1 | **Injection shell Unix** : le wizard exécutait la commande via `FpSystem` (`/bin/sh -c`) ; les valeurs sans espaces n'étaient pas quotées → `;`, `` ` ``, `$(…)` exécutables | RCE | `SysUtils.ExecuteProcess` (argv, **jamais de shell**) via `RunArgs`/`RunTokens` ; `CmdQuote` étendu aux métacaractères pour l'affichage ; `fcmd` refuse le repli PATH silencieux. Reste ouvert (P2) : `%VAR%` développé par cmd.exe au collage |
| P1-2 | **`--out` détruit le fichier d'entrée** (troncature avant l'analyse) | Perte de données | Garde : refus exit 1 + stderr si `--out` ∈ fichiers analysés (chemins absolus, casse ignorée sous Windows) — test 110 (entrée intacte par diff) |
| P1-3 | **Fuite `--redact`** : emails/IPs en clair dans Top Words, n-grams, tags | Divulgation | `RedactString` aux 11 points d'émission + test 109 anti-fuite (grep = 0 sur console/JSON/CSV/summary) |

## 5. Statut P2 — vague 1 corrigée en v2.14.1, reste au backlog 📋

**Corrigés en v2.14.1** (tests 111-113 + wizard rejoué) : frontière 64 Ko
(invalid_utf8 faux positif à l'alignement — bug métrique CI), `WARNING`
classé none (log4j/Python), formules CSV (`= + - @`), gate `--check`
no-op invisible, wizard UX (numéros affichés, entrée invalide ne quitte
plus), code mort (`OptModeAlarm`, deltas watch, `BuildTopLinesJSON`).

**Reste au backlog** (par vagues suivantes) :

- **Robustesse sur entrée hostile**
  - Lignes non bornées en longueur (OOM possible sur une ligne géante ;
    concaténation caractère par caractère quasi-quadratique — mesuré :
    32 Mo sur une ligne ≈ 18 s).
  - Backtracking exponentiel des matchers (`*a*a*…` gèle ; amplifié par
    `--mode=alarm` et son pattern par défaut). → automates linéaires.
- **Verdict CI**
  - `--fail-on-delta` ne teste que la croissance (delta négatif = OK).
  - Baseline sans intégrité (réécrivable par un attaquant du dépôt).
  - Fichier absent de la baseline → checks delta silencieusement ignorés.
- **Détournements sémantiques**
  - Homoglyphes (`ЕRROR` cyrillique) invisibles aux compteurs ;
    caractères RTL invisibles dans les previews.
- **UX**
  - Option inconnue → « Fichier inaccessible ou introuvable » ;
    `--redact`/`--mode` nus → analyse sans protection.
  - `--top-lines=0` : le help dit « tous », le code dit « désactivé ».
  - Pas de verdict final lisible en mode check (dernière ligne = exit code).
  - `%VAR%` développé par cmd.exe au collage de la commande affichée.
- **Hygiène dev**
  - `Halt()` dans les couches basses (try..finally non déroulé).
  - `--recursive`/`--include`/`--exclude`/`--max-depth` : **zéro test**.
  - Duplication run.sh/run.bat (1000+ vs 1050+ lignes) qui divergent déjà.
  - Égalités dans Top Words/Chars sans tie-break → ordre non stable.

## 6. ACCEPTÉ_DOCUMENTÉ (décisions assumées) 📗

- Le binaire Win32 i386 (pas de build 64 bits) — CLI texte, suffisant.
- Excel/Calc : l'utilisateur assume l'ouverture du CSV (voir P2 formules).
- `--watch` ré-analyse tout le fichier à chaque tick (v1 documentée).
- Top-K n-grams approximatif sur très gros corpus (sketch borné).
- Casefold unicode = table basique FR/DE (documenté).
- Les redaction `ipv4`/`url` couvrent des formes simples (pas IPv6/ports).

## 7. Leçons pédagogiques (à relire avant chaque ajout de fonctionnalité)

1. **Un wizard doit boire à la même source de vérité que le parseur.**
   Le bug P0-2 est né d'une table d'options tapée à la main.
2. **Un test qui fige une chaîne protège le bug, pas l'utilisateur.**
   Toujours exécuter ce qu'on génère (test 103b).
3. **Jamais de ligne de commande assemblée comme une string à exécuter.**
   Toujours un argv (P1-1) ; la string affichée est du texte, pas du code.
4. **Une affirmation de sécurité non testée est une vulnérabilité
   documentaire.** Les mentions « anti-path traversal » du header
   fstats.pas:68-149 ont été retirées tant qu'elles ne sont pas prouvées.
5. **Chaque parseur maison vient avec les pièges connus de la bibliothèque
   qu'il imite** — écrire le test du piège en même temps que le parseur.
6. **La version d'un test ne se figure jamais** (P0-3) : dériver ou mourir.
7. **Une protection est un point de passage obligé, ou ce n'est qu'une
   intention.** P1-3 : la redaction existait depuis la v2.8.0, mais dispersée
   en appels ponctuels — les emails fuyaient dans le Top Words, et la doc
   d'alors décrivait cette fuite comme la spec. Corrigé en couvrant les
   *émissions de texte* une par une (11 points) ; testé par « l'objet interdit
   ne doit apparaître dans AUCUNE sortie » (test 109).
8. **Un outil qui lit par blocs doit être testé à sa frontière interne.**
   v2.14.1 : un caractère multi-octets à cheval sur deux blocs de 64 Ko était
   compté `invalid_utf8` — la gate CI accusait un fichier sain d'être cassé
   selon sa taille, pas son contenu. Le test 111 fait glisser le même
   caractère multi-octets sur 6 positions autour de la frontière : un
   compteur correct ne dépend jamais de la position de la coupure.
9. **Un export destiné à Excel est une entrée d'attaque.** v2.14.1 : une
   ligne de log `=cmd|'/c calc'!` ressortait dans le CSV comme une formule
   prête à s'exécuter à l'ouverture. Exporter, c'est émettre du code
   potentiel dans un interpréteur inconnu — neutraliser (`'` préfixe OWASP)
   et tester (test 112).

## 8. Journal des audits

| Date | Version | Audit | Sortie |
|---|---|---|---|
| 2026-11-23 | v2.13.0 | dev × cyber × UX (3 agents + re-vérif manuelle) | P0 → v2.13.1 ; ce registre ; P1 lancé |
| 2026-11-23 | v2.14.0 | — | P1-1/2/3 corrigés + tests 109/110 ; restes notés au §5/P2 |
| 2026-11-23 | v2.14.1 | — | P2 vague 1 corrigée (6 fixes + code mort) ; tests 111-113 ; backlog §5 |
