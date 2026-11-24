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

## 5. Statut P2 — TERMINÉ : vagues 1-5 (v2.14.1 → v2.16.2) ✅

**Corrigés en v2.14.1** (tests 111-113 + wizard rejoué) : frontière 64 Ko
(invalid_utf8 faux positif à l'alignement — bug métrique CI), `WARNING`
classé none (log4j/Python), formules CSV (`= + - @`), gate `--check`
no-op invisible, wizard UX (numéros affichés, entrée invalide ne quitte
plus), code mort (`OptModeAlarm`, deltas watch, `BuildTopLinesJSON`).

**Corrigés en v2.15.0** (tests 114-116 + parité golden 23/23 vs v2.14.1) :
backtracking exponentiel des matchers (`--pattern` glouton linéaire,
`--regex-tag` NFA — un fichier de 1,6 Ko gelait à 100 % CPU indéfiniment),
**boucle infinie sur match de longueur nulle** (`*`, `**`, `a||b` — un
verritable hang, découvert en testant le harnais), lignes/mots non bornés
(tampons à croissance géométrique + bornes de stockage, métriques
exactes). Bonus : le harnais Windows run.bat était inutilisable
(LF au lieu de CRLF : plantage au test 65+ ; `set X=1 ` avec espace
absorbé ; `^>` re-parcouru dans un pipe) — réparé, 63 PASS.

**Corrigés en v2.16.0** (tests 117-119, SHA-256 validé sur vecteurs FIPS
+ parité sha256sum/Get-FileHash) : **baseline falsifiable** (clé `sha256`
dans le summary-json, `--compare` vérifie : contenu changé = FAIL exit 2
même si les métriques sont stables), **fichier hors baseline ignoré en
silence** (avertissement stderr + compteur dans le verdict), **verdict CI
illisible** (dernière ligne console = `Verdict : OK/ATTENTION/ECHEC —
exit N`, jamais dans les formats de données). Bonus : `--fail-on-delta=M>X`
inline n'avait **jamais** fonctionné depuis la v2.6.0 (off-by-one :
traitée comme nom de fichier), et l'exit 2 d'un check injecté était
ignoré. **Delta négatif requalifié ACCEPTÉ** (§6) : le gate protège
contre l'explosion, la décroissance n'est pas une anomalie CI.

**Corrigés en v2.16.1** (tests 120-121) : **options trompeuses** — une
option inconnue (`--patern=x`, typo) ou à valeur manquante (`--redact` nu)
était traitée comme un NOM DE FICHIER : « Fichier inaccessible ou
introuvable » orientait vers le disque au lieu de la ligne de commande ;
message honnête + exit 1 (fichier préfixable `./--x`). **Help --top-lines
mensonger** (« 0 = tous » depuis la v2.8.0, le code désactive la section)
: help + SEMANTIQUE corrigés sur la vérité du code. **`%VAR%` au collage
cmd (wizard) requalifié ACCEPTÉ** : aucune échapperie fiable n'existe
pour `%` en cmd interactif ; la commande générée n'introduit jamais de `%`.

**Corrigés en v2.16.2** (tests 122-123) : **égalités sans tie-break** —
fréquences égales → ordre lexicographique croissant (Top Words, Top Chars
par code point) : déterminisme byte à byte (rupture d'ordre documentée,
compteurs inchangés) ; **`--recursive`/`--include`/`--exclude`/
`--max-depth` — zéro test → sémantique mesurée et figée** (globs relatifs,
`*` ne traverse pas `/`, `**` oui, exclude sur chemin relatif complet,
max-depth = niveaux sous la racine ; test 122 sh+bat).

**Requalifiés ACCEPTÉ_DOCUMENTÉ (v2.16.2, §6) : `Halt()` couches basses**
(libération explicite là où ça compte, OS pour le reste — voir §6),
**homoglyphes/RTL** (table Unicode de confusables hors périmètre).

**ÉTAT : backlog P2 VIDE.** Les vagues 1 à 5 ont traité chaque item du
registre : corrigé + testé, ou requalifié assumé avec justification. Les
seules entrées restantes sont les décisions du §6, qui se lisent comme
des limites périmètre, pas comme des dettes. Duplication run.sh/run.bat :
constat d'architecture (harnais jumeaux 1150/1186 lignes, réalignés
v2.15.0-v2.16.2, chaque nouveau test existe DEJA dans les deux — le coût
de maintenance est le prix de deux environnements natifs).

## 6. ACCEPTÉ_DOCUMENTÉ (décisions assumées) 📗

- Le binaire Win32 i386 (pas de build 64 bits) — CLI texte, suffisant.
- Excel/Calc : l'utilisateur assume l'ouverture du CSV (voir P2 formules).
- `--watch` ré-analyse tout le fichier à chaque tick (v1 documentée).
- Top-K n-grams approximatif sur très gros corpus (sketch borné).
- Casefold unicode = table basique FR/DE (documenté).
- **`Halt()` dans les couches basses** (requalifié v2.16.2) : process CLI
  mono-tâche — au point de sortie, l'OS récupère la mémoire ; les cas
  détenant des ressources de flux (dictionnaires) libèrent
  **explicitement** avant de sortir ; l'entrée principale déroule son
  `try..finally` en flux normal. Un exception-refactor serait du
  cosmétique sans gain utilisateur, au prix d'un risque réel de régression
  des exit codes (la colonne vertébrale de la gate CI).
- **Homoglyphes / RTL invisibles** (requalifié v2.16.2) : `ЕRROR`
  cyrillique ou les contrôles bidi nécessitent une table Unicode de
  confusables, hors périmètre d'un outil de statistiques ; les compteurs
  qualité restent vrais sur ce qu'ils mesurent (nonprintable,
  invalid_utf8). L'utilisateur en contexte hostile croise avec des
  outils dédiés (ex. `unicode-security`).
- Les redaction `ipv4`/`url` couvrent des formes simples (pas IPv6/ports).
- **`--fail-on-delta` ne teste que la croissance** (v2.16.0, requalifié) :
  un delta négatif ne peut pas échouer — le gate protège contre
  l'EXPLOSION des métriques (un log qui triple), pas contre la
  décroissance ; la valeur du delta (négative) reste affichée.

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
10. **Une boucle infinie est un bug de sécurité, pas un bug de performance.**
    v2.15.0 : un match de longueur nulle faisait `StartPos := i + 0 = i` —
    le scanner ne quittait JAMAIS la boucle : `--pattern='*'` = hang pur,
    toute ressource machine absorbée pour toujours. Toute avancée dans une
    boucle doit être testée contre l'égalité stricte à son point de départ.
11. **Un harnais de tests qui n'a jamais tourné jusqu'au bout ne teste rien.**
    v2.15.0 : le run.bat Windows était en fins de ligne LF (cmd.exe exige
    CRLF) — il plantait silencieusement au test 65+ depuis son écriture ;
    10 tests s'auto-sabotaient avec `set X=1 ` (l'espace avant `&&` est
    inclus dans la valeur par cmd) et un `^>` dans un pipe devenait une
    redirection. Le signal « 63 PASS / 0 FAIL » n'existait pas avant —
    maintenant il existe et il est vérifié à chaque version.
    **3e occurrence en v2.16.2 (rattrapage node)** : les 65 tests
    node-dépendants étaient SKIP/FAIL silencieux en local faute de node ;
    une fois node installé, deux d'entre eux s'avéraient périmés depuis
    les vagues 2 et 3 (56 : ids sans sha256 ; 71 : match nul compté 9/9)
    sans que personne ne le voie. Un test qui ne tourne pas n'est pas
    vert : il est invisible.
12. **Testez chaque option sous la forme EXACT où la documentation la
    montre.** v2.16.0 : `--fail-on-delta=M>X` — la forme avec `=` — était
    documentée depuis la v2.6.0 et n'avait JAMAIS fonctionné (off-by-one
    sur le préfixe) : l'option tombait dans la branche « fichier ». La
    forme à 3 arguments, testée elle, fonctionnait. Cinq versions de
    « vérifié » n'ont jamais testé ce que l'utilisateur tape en lisant le
    help. Un test par option documentée, avec sa syntaxe documentée.

## 8. Journal des audits

| Date | Version | Audit | Sortie |
|---|---|---|---|
| 2026-11-23 | v2.13.0 | dev × cyber × UX (3 agents + re-vérif manuelle) | P0 → v2.13.1 ; ce registre ; P1 lancé |
| 2026-11-23 | v2.14.0 | — | P1-1/2/3 corrigés + tests 109/110 ; restes notés au §5/P2 |
| 2026-11-23 | v2.14.1 | — | P2 vague 1 corrigée (6 fixes + code mort) ; tests 111-113 ; backlog §5 |
| 2026-11-24 | v2.15.0 | — | P2 vague 2 corrigée (matchers linéaires, hang match nul, bornes stockage) ; tests 114-116 ; harnais Windows réparé (63 PASS) |
| 2026-11-24 | v2.16.0 | — | P2 vague 3 corrigée (SHA-256 baseline, verdict CI, hors-baseline visible, fail-on-delta inline) ; tests 117-119 (66 PASS) |
| 2026-11-24 | v2.16.1 | — | P2 vague 4 corrigée (options honnêtes, help véridique) ; tests 120-121 (68 PASS) |
| 2026-11-24 | v2.16.2 | — | P2 vague 5 corrigée (tie-break, tests recursive) ; backlog P2 VIDE ; tests 122-123 (70 PASS) |
| 2026-11-24 | v2.16.2 | — | Rattrapage node : 127/127 en sh ET bat (254 vérifications) ; 2 tests jumeaux périmés alignés sur la sémantique figée (56 : ids +sha256 v2.16.0 ; 71 : match nul 0/0 v2.15.0) ; 3e occurrence de la leçon 11 (harnais jamais tourné jusqu'au bout) |
